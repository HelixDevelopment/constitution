#!/usr/bin/env python3
# ============================================================================
# codegraph_safe_helper.py — read-only probes used by codegraph_safe.sh
# ============================================================================
# Purpose
#   Small, deterministic measurements the launcher needs and that are awkward
#   in POSIX shell: real /proc argv identity of CodeGraph processes (never a
#   substring match, §11.4.201 / §11.4.174), read-only DB facts, post-run
#   count verification, the control-needled scope proof (§11.4.273) and the
#   runner receipt check.
# Usage
#   codegraph_safe_helper.py identity <pid>
#   codegraph_safe_helper.py scan <project> writer|reader
#   codegraph_safe_helper.py dbinfo <project>
#   codegraph_safe_helper.py pending <project> [--threshold N]
#   codegraph_safe_helper.py verify <project> [--reported N] [--status-files N]
#                                           [--expected N --tolerance-pct P]
#   codegraph_safe_helper.py scope <project> <baseline-file> [<exceptions-file>]
#   codegraph_safe_helper.py receipt <runner-dir> <stock-version>
# Inputs   /proc, <project>/.codegraph/codegraph.db (opened mode=ro), baseline;
#          CG_SAFE_PENDING_PROBE_BUDGET_S (pending probe wall-clock budget, default 30)
# Outputs  stdout lines (documented per sub-command); never prints file CONTENTS
#          (only paths / counts), so no credential can leak (§11.4.10)
# Exit codes
#   identity: 0 codegraph process ("OK <op> <root>"), 1 alive but NOT codegraph,
#             2 no such process
#   scan:     0 no conflicting live process, 1 conflict (one line per process)
#   dbinfo:   0 always (JSON document; nodes_present via a LIMIT-1 probe — the nodes
#             table is NEVER counted, it holds ~15M rows on a large project)
#   pending:  0 pending refs BELOW threshold, 1 AT_OR_ABOVE threshold (inclusive),
#             3 UNKNOWN (no DB / table or idx_unresolved_status missing / probe over
#             budget / SQL error — callers must take the conservative path), 2 usage.
#             One line: PENDING verdict=<V> counted=<n> threshold=<T> ... The count is
#             BOUNDED: count(*) over (select 1 ... where status='pending' LIMIT T+1), so
#             a 47M-row table costs at most T+1 index entries, never a full COUNT(*).
#   verify / scope / receipt: 0 PASS, 1 FAIL. verify additionally asserts
#             pending_zero (no status='pending' unresolved_refs left; fail-closed when it
#             cannot be evaluated) and prints VERIFY_NOTE version_stamp (informational:
#             indexed_with_version / indexed_with_extraction_version are written ONLY by
#             a completed full index, never by sync, so an interrupted-then-synced index
#             lacks them and `codegraph status` reports it stale — a known gap, not a
#             failure of the run; the stamps are NEVER fabricated here).
#   any sub-command: 2 usage error
# Side effects  none (DB opened read-only; no writes anywhere)
# Dependencies  python3 (stdlib only: sqlite3, fnmatch, hashlib, json)
# Cross-references  codegraph_safe.sh, scope_baseline.txt, tests/test_unit_safe.sh,
#   constitution §11.4.78 / §11.4.174 / §11.4.201 / §11.4.263 / §11.4.273
# ============================================================================
import fnmatch
import hashlib
import json
import os
import re
import sqlite3
import sys
import time

WRITER_OPS = {"init", "index", "sync", "serve"}   # sync can DELETE rows; serve keeps the DB current
BULK_READ_BLOCKERS = {"init", "index", "sync"}    # a read is refused only while the DB is being rewritten


def argv_of(pid):
    try:
        raw = open(f"/proc/{pid}/cmdline", "rb").read()
    except OSError:
        return None
    return [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a != b""]


def codegraph_identity(pid):
    """Return (op, root) when <pid> is a node process running */lib/dist/bin/codegraph.js.

    Identity = argv[0] basename is `node`/`nodejs` AND one argv element ends in
    /lib/dist/bin/codegraph.js. A shell that merely MENTIONS codegraph.js in its
    argv (a carrier) is not an indexer.
    """
    argv = argv_of(pid)
    if argv is None:
        return None, "gone"
    if not argv or os.path.basename(argv[0]) not in ("node", "nodejs"):
        return None, "not-node"
    idx = None
    for i, a in enumerate(argv[1:], start=1):
        if a.endswith("/lib/dist/bin/codegraph.js"):
            idx = i
            break
    if idx is None:
        return None, "not-codegraph"
    rest = argv[idx + 1:]
    op = rest[0] if rest else ""
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        cwd = "/"
    pos = [a for a in rest[1:] if not a.startswith("-")]
    if op == "serve" or not pos:
        root = cwd
    else:
        root = os.path.normpath(os.path.join(cwd, pos[-1]))
    return (op, root), "ok"


def cmd_identity(args):
    if len(args) != 1 or not args[0].isdigit():
        return 2
    pid = int(args[0])
    if pid <= 1:
        return 2
    ident, why = codegraph_identity(pid)
    if ident is None:
        print(why)
        return 2 if why == "gone" else 1
    print(f"OK {ident[0]} {ident[1]}")
    return 0


def related(root, project):
    return root == project or root.startswith(project.rstrip("/") + "/")


def cmd_scan(args):
    if len(args) != 2 or args[1] not in ("writer", "reader"):
        return 2
    project = os.path.realpath(args[0])
    ops = WRITER_OPS if args[1] == "writer" else BULK_READ_BLOCKERS
    me = os.getpid()
    hits = []
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        pid = int(d)
        if pid <= 1 or pid == me:
            continue
        ident, _ = codegraph_identity(pid)
        if ident is None:
            continue
        op, root = ident
        if op in ops and related(os.path.realpath(root), project):
            hits.append((pid, op, root))
    for pid, op, root in sorted(hits):
        print(f"LIVE pid={pid} op={op} root={root}")
    return 1 if hits else 0


def open_ro(project):
    p = os.path.join(project, ".codegraph", "codegraph.db")
    if not os.path.exists(p):
        return None
    c = sqlite3.connect(f"file:{p}?mode=ro", uri=True, timeout=10)
    c.execute("pragma busy_timeout=10000")
    return c


def db_facts(project):
    f = {"exists": False, "files": 0, "nodes_present": False, "state": None, "accounted": None,
         "stamp_version": None, "stamp_extraction": None, "error": None}
    try:
        c = open_ro(project)
    except sqlite3.Error as e:
        f["error"] = str(e)
        return f
    if c is None:
        return f
    f["exists"] = True
    try:
        f["files"] = c.execute("select count(*) from files").fetchone()[0]
    except sqlite3.Error as e:
        f["error"] = str(e)
    try:  # existence only: a COUNT(*) over the nodes table (~15M rows) is never needed
        f["nodes_present"] = c.execute("select 1 from nodes limit 1").fetchone() is not None
    except sqlite3.Error:
        f["nodes_present"] = False
    try:
        for k, v in c.execute("select key, value from project_metadata where key in "
                              "('index_state','index_files_accounted','indexed_with_version','indexed_with_extraction_version')"):
            if k == "index_state":
                f["state"] = v
            elif k == "index_files_accounted":
                f["accounted"] = v
            elif k == "indexed_with_version":
                f["stamp_version"] = v
            else:
                f["stamp_extraction"] = v
    except sqlite3.Error:
        pass
    c.close()
    return f


PENDING_TABLE = "unresolved_refs"
PENDING_INDEX = "idx_unresolved_status"   # CodeGraph schema.sql: ON unresolved_refs(status)


def pending_probe(project, cap):
    """Bounded count of status='pending' unresolved_refs, capped at `cap` rows.

    Returns (count_or_None, reason_or_None). `INDEXED BY` makes a missing index an error
    instead of a silent full scan of a table that holds ~47M rows on a large project; a
    wall-clock budget (progress handler) is a second bound. Any failure -> (None, reason):
    the caller decides conservatively, this function never guesses a count.
    """
    try:
        c = open_ro(project)
    except sqlite3.Error as e:
        return None, f"{type(e).__name__}: {e}"
    if c is None:
        return None, "no database"
    try:
        try:
            budget = float(os.environ.get("CG_SAFE_PENDING_PROBE_BUDGET_S", "30"))
        except ValueError:
            budget = 30.0
        deadline = time.monotonic() + budget
        c.set_progress_handler(lambda: 1 if time.monotonic() > deadline else 0, 100000)
        n = c.execute(
            f"select count(*) from (select 1 from {PENDING_TABLE} indexed by {PENDING_INDEX} "
            f"where status = 'pending' limit ?)", (cap,)).fetchone()[0]
        return n, None
    except sqlite3.Error as e:
        return None, f"{type(e).__name__}: {e}"
    finally:
        c.close()


def cmd_pending(args):
    if not args:
        return 2
    project = args[0]
    threshold = opt(args[1:], "--threshold")
    if threshold is None:
        threshold = 150000
    if threshold < 1:
        return 2
    n, why = pending_probe(project, threshold + 1)
    if n is None:
        print(f"PENDING verdict=UNKNOWN counted=? threshold={threshold} table={PENDING_TABLE} "
              f"index={PENDING_INDEX} reason={why}")
        return 3
    hit = n >= threshold
    print(f"PENDING verdict={'AT_OR_ABOVE' if hit else 'BELOW'} counted={n} threshold={threshold} "
          f"table={PENDING_TABLE} index={PENDING_INDEX} bounded_count_limit={threshold + 1}")
    return 1 if hit else 0


def cmd_dbinfo(args):
    if len(args) != 1:
        return 2
    print(json.dumps(db_facts(args[0]), sort_keys=True))
    return 0


def opt(args, name, cast=int):
    if name in args:
        i = args.index(name)
        if i + 1 < len(args) and args[i + 1] != "":
            return cast(args[i + 1])
    return None


def cmd_verify(args):
    if not args:
        return 2
    project = args[0]
    rest = args[1:]
    f = db_facts(project)
    ok = True

    def res(name, good, detail):
        nonlocal ok
        print(f"VERIFY {name} {'PASS' if good else 'FAIL'} {detail}")
        ok = ok and good

    res("db_present", f["exists"] and f["error"] is None, f"exists={f['exists']} error={f['error']}")
    res("index_state", f["state"] == "complete", f"index_state={f['state']}")
    n = f["files"]
    res("files_nonzero", n > 0, f"files={n}")
    pcap = 10000
    pn, pwhy = pending_probe(project, pcap + 1)
    if pn is None:
        res("pending_zero", False, f"cannot evaluate pending unresolved refs ({pwhy}) — cannot prove pending==0")
    else:
        shown = f">{pcap}" if pn > pcap else str(pn)
        res("pending_zero", pn == 0, f"pending_unresolved_refs={shown} (status='pending' only; failed retry-tail rows are not pending)")
    if f["accounted"] is not None:
        try:
            acc = int(f["accounted"])
        except ValueError:
            acc = -1
        res("files_eq_accounted", acc == n, f"files={n} index_files_accounted={f['accounted']}")
    rep = opt(rest, "--reported")
    if rep is not None:
        res("files_eq_reported", rep == n, f"files={n} reported_by_index={rep}")
    stf = opt(rest, "--status-files")
    if stf is not None:
        res("files_eq_status", stf == n, f"files={n} status_files={stf}")
    exp = opt(rest, "--expected")
    if exp is not None:
        tol = opt(rest, "--tolerance-pct", float)
        tol = 0.0 if tol is None else tol
        lim = exp * tol / 100.0
        res("files_vs_expected", abs(n - exp) <= lim, f"files={n} expected={exp} tolerance_pct={tol}")
    if f["stamp_version"] and f["stamp_extraction"]:
        print(f"VERIFY_NOTE version_stamp PRESENT indexed_with_version={f['stamp_version']} "
              f"indexed_with_extraction_version={f['stamp_extraction']}")
    else:
        print(f"VERIFY_NOTE version_stamp ABSENT indexed_with_version={f['stamp_version']} "
              f"indexed_with_extraction_version={f['stamp_extraction']} — known gap, informational only: these stamps are written "
              f"ONLY by a completed full index (indexAll), never by sync, so an interrupted-then-synced index lacks them "
              f"and `codegraph status` will report the index as stale. Not a failure of this run (files/state/pending were "
              f"verified above); a full `index` would stamp it. The stamps are not fabricated here.")
    print(f"VERIFY_FILES {n}")
    return 0 if ok else 1


# ---------------------------------------------------------------- scope proof
def load_baseline(path):
    rules = []
    for ln in open(path, encoding="utf-8"):
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        parts = ln.split()
        if len(parts) != 3 or parts[1] not in ("secret", "exclude"):
            raise ValueError(f"bad baseline line: {ln!r}")
        cls, kind, pat = parts
        if ":" not in pat:
            raise ValueError(f"bad pattern: {pat!r}")
        rules.append((cls, kind, pat))
    return rules


# Classes eligible for a per-path exception. Deliberately narrow: only the two
# basename/dirname *substring* heuristics ('secret' appearing anywhere in a path
# component) are prone to false-positiving on legitimate source (a HAL implementing
# a "shared secret" crypto protocol, a tool that SCANS for secrets, a public API's
# own "Secret Manager" service schema). The four credential-CONTENT classes
# (env_file, keystore, signing_key, service_account — §11.4.10) admit NO exceptions
# ever: their patterns match file *type*/*role* (a .env file, a .jks keystore, a
# .pem/.key/.pk8 signing key, a *service-account*.json), where a match is never a
# false positive by design, so this set is a hard allowlist, not configuration.
ALLOWED_EXCEPTION_CLASSES = frozenset(("secret_named", "secrets_dir"))


def load_exceptions(path):
    """Narrow, auditable per-EXACT-path exceptions for ALLOWED_EXCEPTION_CLASSES only.

    Format: '<class> <exact-project-relative-path>' one per line; '#'  starts a
    trailing comment (stripped) or a whole-line comment; blank lines ignored. A
    path here is EXACT — never a glob/pattern — so an exception only ever silences
    the ONE file it names, verified non-credential by a human/agent at the time it
    was added (the comment should say why). A typo'd path simply never matches
    anything and the underlying SCOPE_CLASS FAIL persists — fail-closed, not
    fail-open: this file can only narrow an ALREADY-KNOWN, ALREADY-VERIFIED hit,
    never broaden what the baseline patterns themselves catch.

    Missing/absent file -> {} (exceptions are optional; no exceptions is the
    default, strictest posture). A line naming a class outside
    ALLOWED_EXCEPTION_CLASSES is a hard error (raises) — this is the enforcement
    point that keeps credential-CONTENT classes exception-proof.
    """
    exc = {}
    if not path or not os.path.isfile(path):
        return exc
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    for ln in lines:
        ln = ln.split("#", 1)[0].strip()
        if not ln:
            continue
        parts = ln.split()
        if len(parts) != 2:
            raise ValueError(f"bad exceptions line: {ln!r}")
        cls, exact_path = parts
        if cls not in ALLOWED_EXCEPTION_CLASSES:
            raise ValueError(
                f"exception class {cls!r} is not in the allowed set {sorted(ALLOWED_EXCEPTION_CLASSES)} — "
                f"credential-CONTENT classes (env_file/keystore/signing_key/service_account) MUST NOT be "
                f"excepted (§11.4.10); only path-substring heuristic classes may be")
        if exact_path.startswith("/") or "*" in exact_path or "?" in exact_path:
            raise ValueError(f"exceptions must be an exact project-relative path, not a pattern: {exact_path!r}")
        exc.setdefault(cls, set()).add(exact_path)
    return exc


def match(pattern, path):
    """Project-RELATIVE path matcher. Absolute paths never match (anchored)."""
    if path.startswith("/"):
        return False
    how, val = pattern.split(":", 1)
    comps = path.split("/")
    if how == "exact":
        return path == val
    if how == "seg":
        return val in comps
    if how == "segglob":
        return any(fnmatch.fnmatchcase(c, val) for c in comps)
    if how == "dir":
        return val in comps[:-1]
    if how == "topdir":
        return len(comps) > 1 and comps[0] == val
    raise ValueError(f"unknown matcher {how!r}")


def cmd_scope(args):
    if len(args) not in (2, 3):
        return 2
    project, baseline = os.path.realpath(args[0]), args[1]
    exceptions_arg = args[2] if len(args) == 3 else None
    try:
        rules = load_baseline(baseline)
    except (OSError, ValueError) as e:
        print(f"SCOPE FAIL baseline unreadable: {e}")
        return 1
    try:
        exceptions = load_exceptions(exceptions_arg)
    except ValueError as e:
        print(f"SCOPE FAIL exceptions file invalid: {e}")
        return 1
    try:
        c = open_ro(project)
        paths = [r[0] for r in c.execute("select path from files order by path")] if c else []
        if c:
            c.close()
    except sqlite3.Error as e:
        print(f"SCOPE FAIL files table unreadable: {e}")
        return 1
    if not paths:
        print("SCOPE FAIL BLIND: files table empty — a zero class count would prove nothing")
        return 1

    def count(pat):
        return sum(1 for p in paths if match(pat, p))

    # control needle (§11.4.273): a path that is BOTH in the table and present on disk,
    # queried through the SAME matcher, must be found; a fabricated path must not be.
    needle = next((p for p in paths if not p.startswith("/") and os.path.isfile(os.path.join(project, p))), None)
    if needle is None:
        print("SCOPE FAIL BLIND: no files-table row resolves to a project-relative file on disk; "
              "the anchored matcher cannot see this table shape")
        return 1
    pos_exact = count("exact:" + needle)
    pos_glob = count("segglob:" + needle.split("/")[-1])
    top = needle.split("/")[0]
    pos_top = count("topdir:" + top) if "/" in needle else 1
    fabricated = "__cg_scope_needle_absent__/" + hashlib.sha256(needle.encode()).hexdigest()[:16] + ".none"
    neg = count("exact:" + fabricated) + count("segglob:" + fabricated.split("/")[-1])
    ok = pos_exact >= 1 and pos_glob >= 1 and pos_top >= 1 and neg == 0
    print(f"SCOPE_NEEDLE positive={needle} exact={pos_exact} segglob={pos_glob} topdir={pos_top} "
          f"negative={fabricated} found={neg} -> {'SEEING' if ok else 'BLIND'}")
    if not ok:
        print("SCOPE FAIL BLIND: control needle failed — class counts are not evidence")
        return 1
    failed = False
    class_kind = {}
    class_hits = {}
    for cls, kind, pat in rules:
        class_kind[cls] = kind
        hit_set = class_hits.setdefault(cls, set())
        hit_set.update(p for p in paths if match(pat, p))
    for cls in sorted(class_hits):
        kind = class_kind[cls]
        hits = class_hits[cls]
        excepted = exceptions.get(cls, set()) & hits  # only EXACT, ACTUAL hits ever count as excepted
        remaining = sorted(hits - excepted)
        n = len(remaining)
        verdict = "PASS" if n == 0 else "FAIL"
        failed = failed or n > 0
        exc_note = f" excepted={len(excepted)}" if excepted else ""
        print(f"SCOPE_CLASS {cls} kind={kind} count={n}{exc_note} {verdict}")
        for p in remaining[:5]:
            print(f"  SCOPE_HIT {cls} {p}")
    print(f"SCOPE {'FAIL' if failed else 'PASS'} rows={len(paths)} classes={len(class_hits)}")
    return 1 if failed else 0


def cmd_receipt(args):
    if len(args) != 2:
        return 2
    rdir, stock_ver = args
    try:
        rc = json.load(open(os.path.join(rdir, "RUNNER_RECEIPT.json")))
        dbjs = os.path.join(rdir, "lib", "dist", "db", "index.js")
        sha = hashlib.sha256(open(dbjs, "rb").read()).hexdigest()
    except (OSError, ValueError) as e:
        print(f"RECEIPT FAIL unreadable: {e}")
        return 1
    good = (rc.get("patched_dbjs_sha256") == sha and rc.get("codegraph_version") == stock_ver
            and bool(rc.get("patch_id")))
    print(f"RECEIPT {'PASS' if good else 'FAIL'} patch_id={rc.get('patch_id')} "
          f"receipt_version={rc.get('codegraph_version')} stock_version={stock_ver} sha_match={rc.get('patched_dbjs_sha256') == sha}")
    return 0 if good else 1


def main():
    if len(sys.argv) < 2:
        return 2
    cmds = {"identity": cmd_identity, "scan": cmd_scan, "dbinfo": cmd_dbinfo, "pending": cmd_pending, "verify": cmd_verify,
            "scope": cmd_scope, "receipt": cmd_receipt}
    fn = cmds.get(sys.argv[1])
    if fn is None:
        return 2
    try:
        return fn(sys.argv[2:])
    except ValueError as e:
        print(f"ERROR {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
