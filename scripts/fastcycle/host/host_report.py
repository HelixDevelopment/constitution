#!/usr/bin/env python3
"""host_report.py - Host resource attribution, guarded clean-up and host-safety
limit checks (SpecKit-004 "fast-dev-cycles", User Story 6, plan tasks
T-F01..T-F05, contract contracts/host-resource-attribution.md).

Purpose: measure where disk and time go on the host (T-F01/T-F02), propose
right-sizing gated behind a verified backup + operator confirmation
(T-F03), prove that no §12.6/§12.12/§11.4.58/§12.7 host-safety limit is
weakened by a speed-up (T-F04), and monitor free space against the largest
floor in use plus propose (never apply) a CodeGraph WAL-checkpoint policy
(T-F05).

Invocations (contract "Invocations" section, verbatim flag names):
    host_report.py attribute   --config <cfg> --out <attribution.json>
    host_report.py cleanup     --target <path> --backup-marker <marker.json>
                                --confirmation <confirm.json> --out <action.json> [--apply]
    host_report.py limits      --speedup <id> --phase before|after --out <limits.json>
    host_report.py limits-diff --before <a.json> --after <b.json>
    host_report.py floor       --config <cfg> --out <floor.json>
      ("floor" is T-F05's CLI form; the contract's own "Invocations" section
      does not list it -- per common-conventions.md's own stated fallback
      for a plan tool a contract's Invocations block omits, its interface is
      fixed by the plan task text (T-F05) until the contract is amended.)

Exit codes (contract "Exit codes" line, per subcommand):
    attribute   : 0 measured cleanly, 3 needle failed (no result file), 4 BLIND
                  (a measurement command failed for >=1 row -- that row is
                  UNMEASURED, never coerced to 0, and the WHOLE run signals
                  BLIND rather than a false clean 0).
    cleanup     : 0 executed / dry-run plan, 1 refused.
    limits      : 0 all four checks enforced, 1 any not enforced.
    limits-diff : 0 identical (no limit weakened), 1 weakened (named).
    floor       : 0 margin sufficient, 1 alert (would breach the largest floor).
    (usage/config errors: 2, per C-001, all subcommands.)

MEASUREMENT-INSTRUMENT TRAP (§11.4.201(7), found+closed while building the
needle for T141): `btrfs filesystem du -s` invoked immediately after writing
a file, with NO `sync`, reports Total=Exclusive=0 for a genuinely UNSHARED
file (delayed-allocation extents not yet committed) -- indistinguishable
from a real reflinked-copy result. Every exclusive-bytes measurement below
therefore calls `_sync()` first.

Producer != Verifier (§11.4.240): this file is the T147..T151 implementation
turning the T141..T145 RED tests GREEN; those tests' own needle/derived-
oracle arithmetic is written independently in the test files, never
imported from here.

Stdlib + PyYAML only (matching the sibling gates/catchset_compare.py /
closure/escape_classify.py tools' own `import yaml` convention for
--config); imports canon()/body_hash_of() from the sibling lib/fc_common.py
(C-002), matching this tree's established flat-script import-by-path
pattern (no __init__.py anywhere under constitution/scripts/fastcycle/).
"""
import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

try:
    import yaml
except ImportError:  # pragma: no cover - PyYAML is a stated project dependency
    yaml = None

SCHEMA_ATTRIBUTE = "host-attribute/v1"
SCHEMA_CLEANUP = "host-cleanup/v1"
SCHEMA_LIMITS = "host-limits/v1"
SCHEMA_FLOOR = "host-floor/v1"

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_NEEDLE = 3
EXIT_BLIND = 4

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(TOOL_DIR, "..", "..", "..", ".."))
HOST_GUARD_SH = os.path.join(TOOL_DIR, "..", "lib", "host_guard.sh")

HASH64_RE = re.compile(r"[0-9a-f]{64}")

# HR-005: over-budget synthetic probe size. Large enough that ANY genuine
# real-world host limit clamps it far below this value -- robust against
# small, ordinary live-host fluctuation between the moment this process
# reads /proc and the moment the subprocess it spawns re-reads it a few
# milliseconds later (see probe_* below).
PROBE_N = 1_000_000


class ConfigError(Exception):
    pass


def _resolve(path):
    """A config-supplied path is relative to the project root (fastcycle.yaml's
    own stated convention); resolve it against REPO_ROOT so the tool works
    regardless of the caller's cwd, and pass an already-absolute path through.
    """
    if os.path.isabs(path):
        return path
    return os.path.join(REPO_ROOT, path)


def require(node, *keys):
    cur = node
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            raise ConfigError("config missing key: %s" % ".".join(str(x) for x in keys))
        cur = cur[k]
    return cur


def load_config(path):
    if yaml is None:
        print("host_report: PyYAML is not available in this environment", file=sys.stderr)
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = yaml.safe_load(fh)
    except (OSError, yaml.YAMLError) as exc:
        print("host_report: --config %r unreadable or not valid YAML: %s" % (path, exc), file=sys.stderr)
        return None
    if not isinstance(cfg, dict):
        print("host_report: --config must be a YAML mapping", file=sys.stderr)
        return None
    return cfg


# ---------------------------------------------------------------------------
# C-002 canonical-doc writer (mirrors fc_common.cmd_emit's atomic-write
# discipline; reimplemented locally so callers can pass a dict body directly
# instead of a JSON string through argparse).
# ---------------------------------------------------------------------------
def write_doc(out_path, schema, body, run_meta=None):
    doc = dict(body)
    doc["schema"] = schema
    doc["body_hash"] = body_hash_of(doc)
    doc["run_meta"] = run_meta or {}
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".host_report.")
    try:
        umask = os.umask(0)
        os.umask(umask)
        os.fchmod(fd, 0o666 & ~umask)
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


def _hostname():
    try:
        return os.uname().nodename
    except AttributeError:  # pragma: no cover - POSIX-only project
        return "unknown"


def _read_json_file(path):
    if not path:
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Shared process / hashing helpers
# ---------------------------------------------------------------------------
def run_cmd(argv, timeout=60, env=None):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env)
        return proc.returncode, proc.stdout, proc.stderr
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, None, str(exc)


def _sync():
    # See module docstring: real, measured btrfs delayed-allocation trap.
    try:
        subprocess.run(["sync"], timeout=30, capture_output=True)
    except (OSError, subprocess.TimeoutExpired):
        pass


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def content_address(path):
    """Deterministic content address for a file OR a directory tree: a single
    file's own sha256, or the sha256 of a sorted `relpath\\0filehash` manifest
    over every regular file beneath a directory (HR-004(a) re-verification).
    """
    if os.path.isfile(path):
        return sha256_file(path)
    entries = []
    for dirpath, dirs, files in os.walk(path):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, path)
            entries.append((rel, sha256_file(p)))
    entries.sort()
    manifest = "\n".join("%s\0%s" % e for e in entries)
    return hashlib.sha256(manifest.encode("utf-8")).hexdigest()


def unique_inode_count(path):
    seen = set()
    for dirpath, _dirs, files in os.walk(path):
        for f in files:
            p = os.path.join(dirpath, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            seen.add((st.st_dev, st.st_ino))
    return len(seen)


def path_is_live(path):
    """HR-003 liveness: is any process's real cwd (via /proc) this path or a
    descendant of it. None means "could not determine" (no /proc access);
    False means genuinely checked and no live holder found.
    """
    target = os.path.realpath(path)
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return None
    for pid in pids:
        try:
            cwd = os.readlink("/proc/%s/cwd" % pid)
        except OSError:
            continue
        if cwd == target or cwd.startswith(target + os.sep):
            return True
    return False


def _write_evidence(evidence_dir, name, content):
    os.makedirs(evidence_dir, exist_ok=True)
    path = os.path.join(evidence_dir, name)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)
    return path


def measured(value, cmd, output_path, sha256):
    return {"value": value, "evidence": {"cmd": list(cmd), "output_path": output_path, "sha256": sha256}}


def unmeasured(reason):
    return {"value": "UNMEASURED", "missing_instrument": reason}


# ---------------------------------------------------------------------------
# C-004 schema validator: "the report's numbers are generated from
# measurements only" (T-F02 protecting test) -- every numeric value MUST
# cite a real evidence object; every UNMEASURED value MUST name its
# missing_instrument reason. Real, structural, non-decorative (T142).
# ---------------------------------------------------------------------------
def _valid_measurement(entry):
    if not isinstance(entry, dict) or "value" not in entry:
        return False, "missing 'value'"
    v = entry["value"]
    if v == "UNMEASURED":
        mi = entry.get("missing_instrument")
        if not isinstance(mi, str) or not mi:
            return False, "UNMEASURED with no missing_instrument reason"
        return True, ""
    if isinstance(v, bool):
        return False, "value must be a number or the literal 'UNMEASURED', not a bool"
    if isinstance(v, (int, float)):
        ev = entry.get("evidence")
        if not isinstance(ev, dict):
            return False, "measured numeric value with no evidence object (hand-entered figure)"
        sha = ev.get("sha256")
        if not isinstance(sha, str) or not HASH64_RE.fullmatch(sha):
            return False, "evidence.sha256 missing or not 64 lowercase hex chars"
        if not isinstance(ev.get("cmd"), list) or not ev.get("cmd"):
            return False, "evidence.cmd missing or empty"
        if not ev.get("output_path"):
            return False, "evidence.output_path missing"
        return True, ""
    return False, "value must be a number or the literal 'UNMEASURED', got %r" % (v,)


def validate_attribution_doc(doc):
    if not isinstance(doc, dict):
        return False, "doc is not an object"
    needle = doc.get("needle")
    if not isinstance(needle, dict):
        return False, "missing 'needle' object"
    consumers = doc.get("consumers")
    if not isinstance(consumers, list):
        return False, "missing 'consumers' list"
    for i, row in enumerate(consumers):
        if not isinstance(row, dict) or not row.get("path"):
            return False, "consumers[%d] missing 'path'" % i
        for field in ("apparent_bytes", "exclusive_bytes", "time_attributed_ms"):
            entry = row.get(field)
            ok, why = _valid_measurement(entry)
            if not ok:
                return False, "consumers[%d].%s: %s" % (i, field, why)
    return True, ""


# ---------------------------------------------------------------------------
# T-F01: btrfs apparent/exclusive-bytes measurement
# ---------------------------------------------------------------------------
def _parse_btrfs_du(out):
    data_lines = [line for line in out.splitlines() if line.strip() and not line.strip().startswith("Total")]
    if len(data_lines) != 1:
        return None
    parts = data_lines[0].split()
    if len(parts) < 3:
        return None
    try:
        return int(parts[0]), int(parts[1])
    except ValueError:
        return None


def measure_apparent_bytes(path, evidence_dir, idx):
    if not os.path.exists(path):
        return {"value": 0, "note": "root_absent"}
    rc, out, err = run_cmd(["du", "--apparent-size", "-sb", path], timeout=120)
    if rc != 0 or out is None:
        return unmeasured("du_apparent_size_failed: %s" % (err or "").strip()[:200])
    try:
        n = int(out.split()[0])
    except (ValueError, IndexError):
        return unmeasured("du_apparent_size_unparseable")
    out_path = _write_evidence(evidence_dir, "du_apparent_%d.log" % idx, out)
    return measured(n, ["du", "--apparent-size", "-sb", path], out_path, sha256_file(out_path))


def measure_exclusive_bytes(path, evidence_dir, idx):
    """Returns (total_entry, exclusive_entry)."""
    if not os.path.exists(path):
        e = {"value": 0, "note": "root_absent"}
        return e, dict(e)
    if not shutil.which("btrfs"):
        u = unmeasured("btrfs_binary_unavailable")
        return u, dict(u)
    _sync()
    rc, out, err = run_cmd(["btrfs", "filesystem", "du", "-s", "--raw", path], timeout=180)
    if rc != 0 or out is None:
        u = unmeasured("btrfs_filesystem_du_failed: %s" % (err or "").strip()[:200])
        return u, dict(u)
    parsed = _parse_btrfs_du(out)
    if parsed is None:
        u = unmeasured("btrfs_filesystem_du_unparseable")
        return u, dict(u)
    total, exclusive = parsed
    out_path = _write_evidence(evidence_dir, "btrfs_du_%d.log" % idx, out)
    sha = sha256_file(out_path)
    cmd = ["btrfs", "filesystem", "du", "-s", "--raw", path]
    return measured(total, cmd, out_path, sha), measured(exclusive, cmd, out_path, sha)


NEEDLE_TOLERANCE_BYTES = 4096
NEEDLE_KNOWN_SIZE = 65536


def run_needle(needle_dir, evidence_dir):
    """T-F01 control needle: a fresh unshared file measures its own full size;
    a freshly reflinked copy of it measures ~0 exclusive bytes. Returns
    (needle_dict, None) on success or (None, reason) on failure -- a failure
    here means the exclusive-bytes instrument is not trustworthy this run
    (C-001 exit 3), never silently degraded to a partial report.
    """
    if os.path.exists(needle_dir):
        shutil.rmtree(needle_dir, ignore_errors=True)
    os.makedirs(needle_dir, exist_ok=True)
    try:
        orig = os.path.join(needle_dir, "unshared.bin")
        with open(orig, "wb") as fh:
            fh.write(os.urandom(NEEDLE_KNOWN_SIZE))
        if not shutil.which("btrfs"):
            return None, "btrfs_binary_unavailable"
        _sync()
        rc, out, err = run_cmd(["btrfs", "filesystem", "du", "-s", "--raw", orig], timeout=60)
        if rc != 0 or out is None:
            return None, "btrfs_filesystem_du_failed(unshared): %s" % (err or "").strip()[:200]
        parsed = _parse_btrfs_du(out)
        if parsed is None:
            return None, "btrfs_filesystem_du_unparseable(unshared)"
        u_total, u_excl = parsed
        u_ev_path = _write_evidence(evidence_dir, "needle_unshared.log", out)
        u_sha = sha256_file(u_ev_path)

        copy = os.path.join(needle_dir, "reflinked.bin")
        rc2, _out2, err2 = run_cmd(["cp", "--reflink=always", orig, copy], timeout=60)
        if rc2 != 0:
            return None, "reflink_unsupported: %s" % (err2 or "").strip()[:200]
        _sync()
        rc3, out3, err3 = run_cmd(["btrfs", "filesystem", "du", "-s", "--raw", copy], timeout=60)
        if rc3 != 0 or out3 is None:
            return None, "btrfs_filesystem_du_failed(copy): %s" % (err3 or "").strip()[:200]
        parsed3 = _parse_btrfs_du(out3)
        if parsed3 is None:
            return None, "btrfs_filesystem_du_unparseable(copy)"
        r_total, r_excl = parsed3
        r_ev_path = _write_evidence(evidence_dir, "needle_reflinked.log", out3)
        r_sha = sha256_file(r_ev_path)

        if u_total != NEEDLE_KNOWN_SIZE or u_excl != NEEDLE_KNOWN_SIZE:
            return None, ("needle_mismatch_unshared: total=%r exclusive=%r expected=%r"
                           % (u_total, u_excl, NEEDLE_KNOWN_SIZE))
        if r_total != NEEDLE_KNOWN_SIZE or r_excl > NEEDLE_TOLERANCE_BYTES:
            return None, ("needle_mismatch_reflinked: total=%r exclusive=%r expected_total=%r tolerance=%r"
                           % (r_total, r_excl, NEEDLE_KNOWN_SIZE, NEEDLE_TOLERANCE_BYTES))

        u_cmd = ["btrfs", "filesystem", "du", "-s", "--raw", orig]
        r_cmd = ["btrfs", "filesystem", "du", "-s", "--raw", copy]
        needle = {
            "unshared_file": {
                "expected_bytes": NEEDLE_KNOWN_SIZE, "total_bytes": u_total, "exclusive_bytes": u_excl,
                "evidence": {"cmd": u_cmd, "output_path": u_ev_path, "sha256": u_sha},
            },
            "reflinked_copy": {
                "expected_bytes": NEEDLE_KNOWN_SIZE, "total_bytes": r_total, "exclusive_bytes": r_excl,
                "evidence": {"cmd": r_cmd, "output_path": r_ev_path, "sha256": r_sha},
            },
        }
        return needle, None
    finally:
        shutil.rmtree(needle_dir, ignore_errors=True)


# ---------------------------------------------------------------------------
# T-F02: consumer enumeration (worktrees / session scratch / hardlink mirrors)
# ---------------------------------------------------------------------------
def list_git_worktrees(prefix):
    rc, out, _err = run_cmd(["git", "worktree", "list", "--porcelain"], timeout=30, env=dict(os.environ, GIT_DIR=""))
    if rc != 0 or out is None:
        rc, out, _err = run_cmd(["git", "-C", REPO_ROOT, "worktree", "list", "--porcelain"], timeout=30)
    if rc != 0 or out is None:
        return []
    paths = [line[len("worktree "):].strip() for line in out.splitlines() if line.startswith("worktree ")]
    result = []
    for p in paths:
        rel = os.path.relpath(p, REPO_ROOT)
        if rel == ".":
            continue  # the main worktree itself, not an agent working copy
        if rel.startswith(prefix):
            result.append(rel)
    return result


def cmd_attribute(args):
    cfg = load_config(args.config)
    if cfg is None:
        return EXIT_USAGE
    try:
        evidence_root = require(cfg, "paths", "evidence_root")
        host_cfg = require(cfg, "host")
        attribution_roots = require(host_cfg, "attribution_roots")
        worktree_prefix = require(host_cfg, "worktree_prefix")
        session_scratch_roots = require(host_cfg, "session_scratch_roots")
        hardlink_mirror_roots = require(host_cfg, "hardlink_mirror_roots")
        needle_scratch_dir = require(host_cfg, "needle_scratch_dir")
    except ConfigError as exc:
        print("host_report: %s" % exc, file=sys.stderr)
        return EXIT_USAGE

    run_id = "attribute_%d_%d" % (int(time.time()), os.getpid())
    evidence_dir = os.path.join(_resolve(evidence_root), run_id)
    needle_dir = _resolve(needle_scratch_dir)

    needle, needle_err = run_needle(needle_dir, evidence_dir)
    if needle is None:
        print("host_report: attribute needle FAILED: %s -- exclusive-bytes instrument not "
              "trustworthy this run" % needle_err, file=sys.stderr)
        return EXIT_NEEDLE

    consumers = []
    idx = [0]
    any_unmeasured = [False]

    def _mark(entry):
        if isinstance(entry, dict) and entry.get("value") == "UNMEASURED":
            any_unmeasured[0] = True
        return entry

    def _add_root(path, consumer_type, extra=None):
        idx[0] += 1
        abs_path = _resolve(path)
        ab = _mark(measure_apparent_bytes(abs_path, evidence_dir, idx[0]))
        _tot, excl = measure_exclusive_bytes(abs_path, evidence_dir, idx[0])
        excl = _mark(excl)
        row = {
            "path": path, "consumer_type": consumer_type,
            "apparent_bytes": ab, "exclusive_bytes": excl,
            "time_attributed_ms": unmeasured("no_timing_rows_for_consumer"),
        }
        if extra:
            row.update(extra)
        consumers.append(row)

    for root in attribution_roots:
        _add_root(root["path"], root.get("consumer_type", "other"))

    for wt in list_git_worktrees(worktree_prefix):
        _add_root(wt, "agent_working_copy", {"session_live": path_is_live(_resolve(wt))})

    for root in session_scratch_roots:
        abs_root = root if os.path.isabs(root) else _resolve(root)
        if not os.path.isdir(abs_root):
            continue
        try:
            entries = sorted(os.listdir(abs_root))
        except OSError:
            entries = []
        for name in entries:
            idx[0] += 1
            p = os.path.join(abs_root, name)
            ab = _mark(measure_apparent_bytes(p, evidence_dir, idx[0]))
            consumers.append({
                "path": p, "consumer_type": "session_scratch",
                "apparent_bytes": ab,
                "exclusive_bytes": unmeasured("session_scratch_not_on_btrfs_boundary"),
                "session_live": path_is_live(p),
                "time_attributed_ms": unmeasured("no_timing_rows_for_consumer"),
            })

    for root in hardlink_mirror_roots:
        idx[0] += 1
        abs_root = _resolve(root)
        ab = _mark(measure_apparent_bytes(abs_root, evidence_dir, idx[0]))
        uniq = unique_inode_count(abs_root) if os.path.isdir(abs_root) else 0
        consumers.append({
            "path": root, "consumer_type": "backup_mirror",
            "apparent_bytes": ab,
            "exclusive_bytes": unmeasured("hardlink_mirror_exclusive_not_applicable"),
            "unique_inode_count": uniq,
            "time_attributed_ms": unmeasured("no_timing_rows_for_consumer"),
        })

    body = {"config": args.config, "needle": needle, "consumers": consumers}
    ok, why = validate_attribution_doc(dict(body, schema=SCHEMA_ATTRIBUTE))
    if not ok:
        print("host_report: internal error: attribution doc failed its own schema "
              "validation: %s" % why, file=sys.stderr)
        return EXIT_BLIND
    write_doc(args.out, SCHEMA_ATTRIBUTE, body, run_meta={"host": _hostname()})
    if any_unmeasured[0]:
        print("host_report: attribute: >=1 consumer row UNMEASURED (measurement command "
              "failed) -- BLIND, see --out for detail", file=sys.stderr)
        return EXIT_BLIND
    return EXIT_OK


# ---------------------------------------------------------------------------
# T-F03: guarded clean-up
# ---------------------------------------------------------------------------
def cmd_cleanup(args):
    target = args.target
    reasons = []

    marker = _read_json_file(args.backup_marker)
    backup_path = None
    if marker is None:
        reasons.append("backup_marker_missing_or_unreadable")
    elif marker.get("target") != target:
        reasons.append("backup_marker_target_mismatch")
    else:
        backup_path = marker.get("backup_path")
        if not backup_path or not os.path.exists(backup_path):
            reasons.append("backup_path_missing")
        else:
            recorded = marker.get("content_address")
            actual = content_address(backup_path)
            if recorded != actual:
                reasons.append("backup_hash_mismatch")

    confirmation = _read_json_file(args.confirmation)
    if confirmation is None:
        reasons.append("confirmation_missing_or_unreadable")
    elif confirmation.get("target") != target:
        reasons.append("confirmation_target_mismatch")

    live = path_is_live(target) if os.path.exists(target) else False
    if live:
        reasons.append("target_live_session_dir")

    action = {"target": target, "apply": bool(args.apply), "refused": bool(reasons), "reasons": reasons,
              "live_check": live}

    if reasons:
        write_doc(args.out, SCHEMA_CLEANUP, action, run_meta={"host": _hostname()})
        print("host_report: cleanup refused for %r: %s" % (target, ", ".join(reasons)), file=sys.stderr)
        return EXIT_FINDING

    if not args.apply:
        action["executed"] = False
        action["plan"] = ("dry-run: would remove %r after backup at %r re-verifies" % (target, backup_path))
        write_doc(args.out, SCHEMA_CLEANUP, action, run_meta={"host": _hostname()})
        return EXIT_OK

    pre_addr = content_address(backup_path)
    if os.path.isdir(target):
        shutil.rmtree(target)
    else:
        os.remove(target)
    post_addr = content_address(backup_path)
    reverified = (post_addr == pre_addr == marker.get("content_address"))
    action["executed"] = True
    action["backup_reverified"] = reverified
    write_doc(args.out, SCHEMA_CLEANUP, action, run_meta={"host": _hostname()})
    if not reverified:
        print("host_report: cleanup executed but backup did NOT re-verify afterward "
              "(pre=%s post=%s recorded=%s)" % (pre_addr, post_addr, marker.get("content_address")),
              file=sys.stderr)
        return EXIT_FINDING
    return EXIT_OK


# ---------------------------------------------------------------------------
# T-F04: host-safety limit checks (HR-005 -- an enforcement probe, never a
# config read: each check deliberately requests far more than any plausible
# real capacity and proves the guard clamps/refuses it).
# ---------------------------------------------------------------------------
def _run_host_guard(n, kind, extra_args=None, env_overrides=None):
    env = dict(os.environ)
    if env_overrides:
        env.update({k: str(v) for k, v in env_overrides.items()})
    argv = ["sh", HOST_GUARD_SH, str(n), "--kind", kind] + (extra_args or [])
    rc, out, err = run_cmd(argv, timeout=30, env=env)
    if rc != 0 or out is None:
        return None, None, (err or "").strip()
    returned_n = None
    reason = None
    for line in out.splitlines():
        if line.startswith("N="):
            try:
                returned_n = int(line[len("N="):])
            except ValueError:
                pass
        elif line.startswith("REASON="):
            reason = line[len("REASON="):]
    return returned_n, reason, None


def _read_meminfo():
    tot = os.environ.get("FC_GUARD_MEM_TOTAL_KB")
    avail = os.environ.get("FC_GUARD_MEM_AVAIL_KB")
    if tot is None or avail is None:
        live_tot = live_avail = None
        try:
            with open("/proc/meminfo", encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("MemTotal:"):
                        live_tot = line.split()[1]
                    elif line.startswith("MemAvailable:"):
                        live_avail = line.split()[1]
        except OSError:
            pass
        tot = tot if tot is not None else live_tot
        avail = avail if avail is not None else live_avail
    try:
        return int(tot), int(avail)
    except (TypeError, ValueError):
        return None, None


def _read_ulimit_threads():
    ulim = os.environ.get("FC_GUARD_ULIMIT_U")
    if ulim is None:
        rc, out, _err = run_cmd(["sh", "-c", "ulimit -u"], timeout=10)
        ulim = out.strip() if rc == 0 and out else None
    unlimited = (ulim == "unlimited")
    thr = os.environ.get("FC_GUARD_THREADS")
    if thr is None:
        rc, out, _err = run_cmd(["sh", "-c", "ps -L --no-headers -U \"$(id -ru)\" 2>/dev/null | wc -l"],
                                 timeout=15)
        thr = out.strip() if rc == 0 and out is not None else None
    try:
        ulim_i = None if unlimited or ulim is None else int(ulim)
    except ValueError:
        ulim_i = None
    try:
        thr_i = int(thr) if thr is not None else None
    except ValueError:
        thr_i = None
    return ulim_i, thr_i, unlimited


def _read_active_agents(registry_status_path):
    try:
        with open(registry_status_path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return None
    latest = {}
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        latest[parts[0]] = parts[1]
    return sum(1 for s in latest.values() if s in ("dispatched", "in-flight"))


def probe_memory_ceiling():
    tot, avail = _read_meminfo()
    if tot is None or avail is None or tot < 1:
        return {"enforced": None, "reason": "unmeasured", "note": "meminfo_unreadable"}
    budget_kb = tot * 60 // 100 - (tot - avail)
    per_job = budget_kb + 1 if budget_kb > 0 else 1
    returned_n, reason, err = _run_host_guard(PROBE_N, "jobs", ["--per-job-mem-kb", str(per_job)])
    if returned_n is None:
        return {"enforced": False, "reason": "probe_failed", "note": err, "requested_n": PROBE_N}
    return {"enforced": returned_n < PROBE_N, "requested_n": PROBE_N, "returned_n": returned_n,
            "reason": reason, "budget_kb": budget_kb, "per_job_mem_kb_probed": per_job}


def probe_thread_headroom():
    ulim, thr, unlimited = _read_ulimit_threads()
    if unlimited:
        return {"enforced": None, "reason": "unlimited_ulimit", "requested_n": PROBE_N}
    if ulim is None or thr is None:
        return {"enforced": None, "reason": "unmeasured", "note": "ulimit_or_threads_unreadable"}
    headroom = ulim - thr
    per_job = headroom + 1 if headroom > 0 else 1
    returned_n, reason, err = _run_host_guard(PROBE_N, "jobs", ["--threads-per-job", str(per_job)])
    if returned_n is None:
        return {"enforced": False, "reason": "probe_failed", "note": err, "requested_n": PROBE_N}
    return {"enforced": returned_n < PROBE_N, "requested_n": PROBE_N, "returned_n": returned_n,
            "reason": reason, "thread_headroom": headroom, "threads_per_job_probed": per_job}


def probe_agent_cap(registry_status_path):
    active = _read_active_agents(registry_status_path)
    note = None
    if active is None:
        active = 0
        note = "agent_registry_status_unreadable_defaulted_to_0"
    returned_n, reason, err = _run_host_guard(PROBE_N, "agents",
                                               env_overrides={"FC_GUARD_ACTIVE_AGENTS": active})
    if returned_n is None:
        return {"enforced": False, "reason": "probe_failed", "note": err, "requested_n": PROBE_N}
    result = {"enforced": returned_n < PROBE_N, "requested_n": PROBE_N, "returned_n": returned_n,
              "reason": reason, "active_agents": active}
    if note:
        result["note"] = note
    return result


def probe_job_cap():
    script = os.path.join(REPO_ROOT, "scripts", "lib", "host_session_safety.sh")
    if not os.path.isfile(script):
        return {"enforced": None, "reason": "unmeasured", "note": "host_session_safety.sh_absent"}
    shell_cmd = "set -e; . %s >/dev/null 2>&1; host_safe_aosp_jobs %d" % (shlex.quote(script), PROBE_N)
    rc, out, err = run_cmd(["bash", "-c", shell_cmd], timeout=30)
    if rc != 0 or out is None:
        return {"enforced": False, "reason": "probe_failed", "note": (err or "").strip()[:200],
                "requested_n": PROBE_N}
    lines = [l for l in out.strip().splitlines() if l.strip()]
    try:
        j = int(lines[-1]) if lines else None
    except ValueError:
        j = None
    if j is None:
        return {"enforced": False, "reason": "unparseable_output", "requested_n": PROBE_N}
    return {"enforced": j < PROBE_N, "requested_n": PROBE_N, "returned_n": j, "reason": "host_safe_aosp_jobs"}


# §11.4.225 telemetry (measurement, never a pass/fail limit per HR-005).
def parse_cpu_stat(text):
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2:
            try:
                out[parts[0]] = int(parts[1])
            except ValueError:
                pass
    return out


def cpu_throttle_delta(before, after):
    return {
        "nr_throttled_delta": after.get("nr_throttled", 0) - before.get("nr_throttled", 0),
        "throttled_usec_delta": after.get("throttled_usec", 0) - before.get("throttled_usec", 0),
        "nr_periods_delta": after.get("nr_periods", 0) - before.get("nr_periods", 0),
    }


def _read_cpu_stat_path():
    return os.environ.get("FC_HOST_CPU_STAT_PATH", "/sys/fs/cgroup/cpu.stat")


def measure_cpu_throttle_telemetry(quiet_s=0.2, load_s=0.2):
    path = _read_cpu_stat_path()
    try:
        with open(path, encoding="utf-8") as fh:
            before_quiet = parse_cpu_stat(fh.read())
    except OSError:
        return unmeasured("cgroup_cpu_stat_unavailable")
    time.sleep(quiet_s)
    try:
        with open(path, encoding="utf-8") as fh:
            after_quiet = parse_cpu_stat(fh.read())
    except OSError:
        return unmeasured("cgroup_cpu_stat_unavailable")
    quiet_delta = cpu_throttle_delta(before_quiet, after_quiet)
    try:
        proc = subprocess.Popen(["python3", "-c", "x=0\nwhile True: x+=1"])
        time.sleep(load_s)
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    except OSError:
        pass
    try:
        with open(path, encoding="utf-8") as fh:
            after_load = parse_cpu_stat(fh.read())
    except OSError:
        return {"value": "UNMEASURED", "missing_instrument": "cgroup_cpu_stat_unavailable",
                "quiet_window": quiet_delta}
    load_delta = cpu_throttle_delta(after_quiet, after_load)
    return {"quiet_window": quiet_delta, "load_window": load_delta}


def measure_swap_pagein_rate():
    try:
        with open("/proc/vmstat", encoding="utf-8") as fh:
            before = {parts[0]: int(parts[1]) for parts in (l.split() for l in fh) if len(parts) == 2}
    except (OSError, ValueError):
        return unmeasured("proc_vmstat_unavailable")
    time.sleep(0.1)
    try:
        with open("/proc/vmstat", encoding="utf-8") as fh:
            after = {parts[0]: int(parts[1]) for parts in (l.split() for l in fh) if len(parts) == 2}
    except (OSError, ValueError):
        return unmeasured("proc_vmstat_unavailable")
    return {"pswpin_delta": after.get("pswpin", 0) - before.get("pswpin", 0),
            "pswpout_delta": after.get("pswpout", 0) - before.get("pswpout", 0)}


def cmd_limits(args):
    registry_status_path = _resolve("docs/requests/agent_registry.status.tsv")
    limits = {
        "memory_ceiling": probe_memory_ceiling(),
        "thread_headroom": probe_thread_headroom(),
        "agent_cap": probe_agent_cap(registry_status_path),
        "job_cap": probe_job_cap(),
    }
    telemetry = {
        "cpu_throttle": measure_cpu_throttle_telemetry(),
        "swap_pagein": measure_swap_pagein_rate(),
    }
    body = {"speedup": args.speedup, "phase": args.phase, "limits": limits, "telemetry": telemetry}
    write_doc(args.out, SCHEMA_LIMITS, body, run_meta={"host": _hostname()})
    not_enforced = [name for name, row in limits.items() if row.get("enforced") is False]
    if not_enforced:
        print("host_report: limits NOT enforced: %s" % ", ".join(not_enforced), file=sys.stderr)
        return EXIT_FINDING
    return EXIT_OK


def cmd_limits_diff(args):
    before = _read_json_file(args.before)
    after = _read_json_file(args.after)
    if before is None or after is None:
        print("host_report: limits-diff: --before or --after unreadable", file=sys.stderr)
        return EXIT_USAGE
    b_limits = before.get("limits", {})
    a_limits = after.get("limits", {})
    weakened = []
    for name, b_row in b_limits.items():
        if b_row.get("enforced") is True:
            a_row = a_limits.get(name)
            if not isinstance(a_row, dict) or a_row.get("enforced") is not True:
                weakened.append(name)
    if weakened:
        print("host_report: limits-diff: WEAKENED after speed-up: %s" % ", ".join(weakened))
        return EXIT_FINDING
    print("host_report: limits-diff: no limit weakened")
    return EXIT_OK


# ---------------------------------------------------------------------------
# T-F05: disk-floor monitor + WAL-checkpoint policy proposal
# ---------------------------------------------------------------------------
def _read_free_kb(volume_path):
    override = os.environ.get("FC_FLOOR_FREE_KB")
    if override is not None:
        try:
            return int(override)
        except ValueError:
            return None
    rc, out, _err = run_cmd(["df", "-k", "--output=avail", volume_path], timeout=30)
    if rc != 0 or out is None:
        return None
    lines = [l for l in out.strip().splitlines() if l.strip()]
    if len(lines) < 2:
        return None
    try:
        return int(lines[-1].strip())
    except ValueError:
        return None


def cmd_floor(args):
    cfg = load_config(args.config)
    if cfg is None:
        return EXIT_USAGE
    try:
        disk_floor = require(cfg, "host", "disk_floor")
        volume_path = require(disk_floor, "volume_path")
        floors_gib = require(disk_floor, "floors_gib")
        codegraph_safe_script = require(disk_floor, "codegraph_safe_script")
    except ConfigError as exc:
        print("host_report: %s" % exc, file=sys.stderr)
        return EXIT_USAGE
    if not isinstance(floors_gib, dict) or not floors_gib:
        print("host_report: host.disk_floor.floors_gib must be a non-empty mapping", file=sys.stderr)
        return EXIT_USAGE

    free_kb = _read_free_kb(_resolve(volume_path))
    if free_kb is None:
        print("host_report: floor: could not measure free space on %r" % volume_path, file=sys.stderr)
        return EXIT_BLIND
    free_gib = free_kb / 1024 / 1024
    largest_name = max(floors_gib, key=lambda k: floors_gib[k])
    largest_floor_gib = floors_gib[largest_name]
    margin_gib = free_gib - largest_floor_gib
    alert = margin_gib < 0

    body = {
        "volume_path": volume_path, "free_gib": free_gib, "floors_gib": floors_gib,
        "largest_floor_name": largest_name, "largest_floor_gib": largest_floor_gib,
        "margin_gib": margin_gib, "alert": alert,
        "wal_checkpoint_proposal": {
            "operator_confirmed": False,
            "mechanism": "reuse %s's existing --tripwire-min-gib/--tripwire-interval tripwire "
                         "as a periodic WAL-checkpoint policy on the CodeGraph DB (no new "
                         "mechanism invented, memory card 2026-09-24b)" % codegraph_safe_script,
            "codegraph_safe_script": codegraph_safe_script,
        },
    }
    write_doc(args.out, SCHEMA_FLOOR, body, run_meta={"host": _hostname()})
    if alert:
        print("host_report: floor ALERT: %.2f GiB free < %.2f GiB largest floor (%s), margin %.2f GiB"
              % (free_gib, largest_floor_gib, largest_name, margin_gib), file=sys.stderr)
        return EXIT_FINDING
    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="host_report.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd_name", required=True)

    a = sub.add_parser("attribute")
    a.add_argument("--config", required=True)
    a.add_argument("--out", required=True)

    c = sub.add_parser("cleanup")
    c.add_argument("--target", required=True)
    c.add_argument("--backup-marker", required=True)
    c.add_argument("--confirmation", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--apply", action="store_true")

    l = sub.add_parser("limits")
    l.add_argument("--speedup", required=True)
    l.add_argument("--phase", required=True, choices=("before", "after"))
    l.add_argument("--out", required=True)

    ld = sub.add_parser("limits-diff")
    ld.add_argument("--before", required=True)
    ld.add_argument("--after", required=True)

    f = sub.add_parser("floor")
    f.add_argument("--config", required=True)
    f.add_argument("--out", required=True)

    return p


def main(argv):
    args = build_arg_parser().parse_args(argv)
    table = {
        "attribute": cmd_attribute,
        "cleanup": cmd_cleanup,
        "limits": cmd_limits,
        "limits-diff": cmd_limits_diff,
        "floor": cmd_floor,
    }
    try:
        return table[args.cmd_name](args)
    except Exception as exc:  # C-001: an internal error is never a finding (1)
        print("host_report: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return EXIT_BLIND


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
