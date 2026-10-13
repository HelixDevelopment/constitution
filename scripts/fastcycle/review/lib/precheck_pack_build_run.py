#!/usr/bin/env python3
"""precheck_pack_build_run.py - real implementation behind
review/precheck_pack_build.sh, the one-shot convenience wrapper that
automates the manual slicer.py + precheck_pack.sh sequence a human/agent
otherwise repeats by hand every review round (spec-004 "fast-dev-cycles";
RB-001/RB-002 per contracts/review-batch-and-precheck.md). This is
precheck_pack_build.sh's OWN internal library (house pattern:
gates/io_trace.sh -> gates/lib/io_trace_parse.py; review/precheck_pack.sh
-> review/lib/precheck_pack_run.py) -- invoked ONLY by that thin POSIX sh
dispatcher, never called directly by a contract-facing caller.

Two subcommands, both operating on real data only (constitution 11.4.6 --
nothing fabricated):

  prepare --repo <const-root> --base <ref> --head <ref>
          --paths-file <file, one changed path per line>
          --scratch <dir> --logic-group <name>
      For every changed path: computes the REAL `git diff <base> <head> --
      <path>` content, writes it verbatim to
      <scratch>/changes/NNNN.diff, and writes a sibling
      <scratch>/changes/NNNN.json change descriptor whose `change_id` is
      the REAL sha256 of those exact diff bytes (the same verification
      review/slicer.py's own load_change() performs on load -- computed
      here with the identical hashlib.sha256(bytes).hexdigest() primitive,
      so a descriptor this tool writes always passes slicer.py's own
      content-address check). `lines_changed` is the real count of lines
      in the diff beginning with '+' or '-', excluding the `+++`/`---`
      file-header lines (never a guessed/fabricated line count). Also
      writes <scratch>/config.yaml mapping every changed path to the one
      given --logic-group (review/slicer.py's own --config contract:
      a top-level `components: {<path>: <logic group>}` mapping; RB-001
      DEC-06 "shared logic group, feature, or defect class" -- this
      wrapper's default behaviour per its own CLI contract is "all
      changed paths of ONE commit/range share one logic group", with
      --logic-group as the caller's override). Prints, to stdout, two
      lines a POSIX sh caller can parse without eval:
          DESCRIPTORS=<comma-joined absolute paths to each *.json descriptor>
          CONFIG=<absolute path to config.yaml>
      Exit: 0 on success; 2 on a usage/IO error (unreadable --paths-file,
      --repo not a git worktree, a `git diff` invocation itself failing);
      a `git diff` that runs but returns an empty (unchanged) result for a
      declared path is NOT an error (DEC: a path present in --paths-file
      but genuinely unchanged between base/head is a caller bug, not this
      tool's to silently paper over -- it still gets a real, empty-diff
      descriptor with lines_changed=0, never dropped: RB-001 "batching
      never drops a change" extended to this wrapper's own intake step).

  emit --out-dir <dir> [--validate-only]
      Reads <dir>/precheck.json (schema-checked: "schema" ==
      "precheck/v1", "batch_id" present and not the literal "UNKNOWN",
      "all_pass" a real bool) and, unless --validate-only, prints the
      EXACT two marker lines scripts/hooks/review_dispatch_guard.sh's own
      documented RB-002 convention requires on a review dispatch's
      description, so a caller can copy them verbatim:
          PRECHECK-PACK: <dir>/precheck.json
          BATCH-ID: <batch_id>
      Exit: 0 if the pack is schema-valid AND all_pass is true (dispatch-
      ready); 1 if schema-valid but all_pass is false (produced, but not
      yet dispatch-ready -- the real precheck_pack.sh exit-code
      convention, contracts/review-batch-and-precheck.md "Exit codes");
      3 if <dir>/precheck.json is missing, unreadable, or fails the
      schema check (an honest "no usable pack here" signal, distinct from
      both 0 and 1, matching this project's own other tools' convention
      of a distinct exit code for "no honest verdict" rather than folding
      it into a generic 2 -- review/precheck_pack_run.py's own
      --determinism-check uses exit 4 for exactly this shape of
      distinction). --validate-only suppresses the marker-line stdout
      (used by the sh dispatcher's idempotent-cache-check path, which
      must not print a possibly-stale marker before the cache is
      confirmed trustworthy).

  bind --repo <r> --base <sha> --head <sha> --batch <in> --out <out>
       [--kind commit|snapshot] [--rewrite-changes]
      Writes a `binding` {schema, base_sha, head_sha, kind, paths:[{path,
      change_id, status}]} into the batch (slicer.py's body_hash recomputed),
      enumerating the changed paths NUL-safely and computing each change_id with
      EXACTLY the argv the gate recomputes (lib/precheck_common.py, one shared
      definition -- F13). By default the binding's change_ids must equal
      batch.changes; --rewrite-changes replaces them (test fixtures only).

  snapshot --repo <r> --paths-file <NUL- or newline-separated paths>
      For UNCOMMITTED work: builds an UNREFERENCED commit object (no ref, no
      branch, no working-tree or index change -- a temporary index file only)
      whose tree is HEAD's tree with the listed paths replaced by their
      working-tree bytes (absent => removed; symlinks refused), parent HEAD,
      dates pinned to HEAD's so the same content yields the same sha. Prints
      BASE_SHA=/HEAD_SHA=. The object is ordinary unreachable git data.

  snapshot-manifest --repo <r> --base <sha> --head <sha> --paths-file <f> --out <f>
      F15: (re)writes WORKTREE_SNAPSHOT_MD5.txt for a snapshot pack from the
      frozen head object (never from the live tree, so it cannot drift).

  present-paths --repo <r> --head <sha> --paths-file <f> [--extra <path>]...
      NUL-separated subset of the paths that exist at head: the pathspec file
      for the PARTIAL checkout of a --repo-root pack (`git checkout
      --pathspec-from-file --pathspec-file-nul`, literal pathspecs). Exit 3
      when none exists (an all-deletions batch: nothing to materialise).

  verify --pack <precheck.json> [--pack <p2>]... [--expect-base <sha>
         --expect-head <sha>] [--print-gate-version]
      The dispatch-readiness verifier used by scripts/hooks/
      review_dispatch_guard.sh and the builder cache: schema, genuine batch_id,
      all_pass true, body_hash recomputed, gate_version == the CURRENT gate,
      provenance base/head distinct, existing in provenance.repo, base an
      ancestor of head (a root commit for the empty tree; head^1 == base for a
      snapshot -- F5), head_sha_source == "batch-binding-verified", shellcheck
      PASS in whole-file mode -- or in the opt-in baseline-delta mode with
      tool.rule baseline-delta and its base resolved (ATM-1217) -- with binding
      state "bound"; and (F1) the batch
      file recorded in provenance still exists with the recorded sha256,
      carries the pack's batch_id, a valid body_hash and a binding equal to the
      pack's base/head/kind, every bound change_id recomputes in the repo, and
      the repo WORKING TREE still holds the head bytes of every bound path (a
      pack whose code moved on is stale). Several --pack values = one review of
      a cross-repo batch: each must be ready and they must cover DISTINCT repos.
      Exit 0 ready; 1 not ready (reasons on stderr). Honest boundary: a
      determined producer can forge a self-consistent pack AND batch; only a
      signing key would authenticate it.

Decoupling (11.4.28/11.4.177): this file carries no project literal
beyond its own house-pattern paths; every repo/path/commit value is a
caller-supplied argument.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile

SCHEMA = "precheck/v1"
BINDING_SCHEMA = "precheck-binding/v1"
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
# F13: the diff argv, git env, canonical JSON, body_hash and gate_version are ONE
# definition shared with the gate (lib/precheck_common.py) -- never a copy.
from precheck_common import (CANONICAL_EXCEPTIONS_REL, EMPTY_TREE, _DIFF_PIN, _body_hash_of, _canon,  # noqa: E402
                             _change_diff_argv, _git_env, gate_version as _gate_version)


def _read_path_list(path):
    """NUL-safe path list (F14): NUL-separated when the file holds a NUL byte,
    else newline-separated; empty entries dropped; a newline inside a name is
    only representable in the NUL form."""
    with open(path, "rb") as fh:
        raw = fh.read()
    sep = b"\0" if b"\0" in raw else b"\n"
    return [x.decode("utf-8", "surrogateescape") for x in raw.split(sep) if x != b"" and x.strip(b"\r\n")]


def _changed_paths(repo, base, head):
    """NUL-safe [(status, path)] of base..head (renames split into D + A)."""
    p = subprocess.run(["git", "-C", repo] + _DIFF_PIN + ["diff", "-z", "--name-status", "--no-renames",
                                                          "--no-textconv", "--no-ext-diff", base, head],
                       capture_output=True, timeout=120, env=_git_env())
    if p.returncode != 0:
        raise RuntimeError("git diff --name-status failed: %s" % p.stderr.decode("utf-8", "replace").strip())
    toks = p.stdout.split(b"\0")
    out, i = [], 0
    while i + 1 < len(toks):
        st = toks[i].decode("utf-8", "replace")
        if not st:
            i += 1
            continue
        out.append((st, toks[i + 1].decode("utf-8", "surrogateescape")))
        i += 2
    return out


def _write_bytes(path, data):
    out_dir = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def _lines_changed_of(diff_bytes):
    """Real count of changed lines in a unified diff: every line starting
    with '+' or '-' EXCLUDING the '+++'/'---' file-header lines. Decoded
    permissively (errors="replace") so a binary-file diff (which carries
    no +/- hunk lines at all -- git emits a single "Binary files ... and
    ... differ" line) never crashes this tool; it legitimately counts 0,
    never a fabricated non-zero guess."""
    text = diff_bytes.decode("utf-8", errors="replace")
    count = 0
    for line in text.splitlines():
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+") or line.startswith("-"):
            count += 1
    return count


def cmd_prepare(a):
    if not os.path.isdir(a.repo):
        print("precheck_pack_build: --repo is not a directory: %s" % a.repo, file=sys.stderr)
        return 2
    try:
        paths = _read_path_list(a.paths_file)
    except OSError as exc:
        print("precheck_pack_build: cannot read --paths-file %s: %s" % (a.paths_file, exc), file=sys.stderr)
        return 2
    if not paths:
        print("precheck_pack_build: --paths-file names zero changed paths -- nothing to prepare",
              file=sys.stderr)
        return 2

    changes_dir = os.path.join(a.scratch, "changes")
    os.makedirs(changes_dir, exist_ok=True)

    descriptor_paths = []
    for i, path in enumerate(paths, start=1):
        try:
            proc = subprocess.run(_change_diff_argv(a.repo, a.base, a.head, path),
                                  capture_output=True, timeout=60, env=_git_env())
        except (OSError, subprocess.TimeoutExpired) as exc:
            print("precheck_pack_build: real `git diff` for %r failed to run: %s" % (path, exc),
                  file=sys.stderr)
            return 2
        if proc.returncode != 0:
            # `git diff <a> <b> -- <path>` (no --exit-code) returns 0 regardless of
            # whether a difference was found -- real, empirically confirmed on this
            # host (`git diff HEAD~1 HEAD -- <real file>` and `git diff HEAD HEAD --
            # <real file>` both exit 0); only a genuine git-level error (e.g. a bad
            # ref) returns non-zero (128). A non-zero exit here is therefore always a
            # real error this tool must not silently swallow into a fabricated empty
            # descriptor -- never "no differences".
            print("precheck_pack_build: real `git diff` for %r exited %d: %s"
                  % (path, proc.returncode, (proc.stderr or b"").decode("utf-8", errors="replace")),
                  file=sys.stderr)
            return 2
        diff_bytes = proc.stdout

        diff_name = "%04d.diff" % i
        json_name = "%04d.json" % i
        diff_path = os.path.join(changes_dir, diff_name)
        json_path = os.path.join(changes_dir, json_name)
        _write_bytes(diff_path, diff_bytes)

        change_id = "sha256:" + hashlib.sha256(diff_bytes).hexdigest()
        descriptor = {
            "change_id": change_id,
            "path": path,
            "diff": diff_name,
            "lines_changed": _lines_changed_of(diff_bytes),
        }
        with open(json_path, "w", encoding="utf-8") as fh:
            json.dump(descriptor, fh, sort_keys=True)
            fh.write("\n")
        descriptor_paths.append(os.path.abspath(json_path))

    # review/slicer.py's --config contract (its own module docstring): a YAML
    # mapping `components: {<changed path>: <logic group>}`. Every key is
    # written via json.dumps() -- a valid YAML double-quoted scalar for ANY
    # string content (colons, quotes, leading dashes, unicode all handled
    # correctly), never a hand-rolled YAML-escaping guess.
    config_path = os.path.join(a.scratch, "config.yaml")
    lines = ["components:"]
    for path in paths:
        lines.append("  %s: %s" % (json.dumps(path), json.dumps(a.logic_group)))
    with open(config_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print("DESCRIPTORS=%s" % ",".join(descriptor_paths))
    print("CONFIG=%s" % os.path.abspath(config_path))
    return 0


def _params_mismatch(doc, sc_timeout, sc_ex_timeout, sc_rule=None):
    """M5: a cached pack is reusable only when it was built with the requested
    shellcheck budgets (the cache key is the commit range; the budgets are not)."""
    import precheck_pack_run as gate  # same directory; the gate's own defaults (never a copy)
    sc = [c for c in (doc.get("checks") or []) if isinstance(c, dict) and c.get("check") == "shellcheck"]
    tool = ((sc[0].get("evidence") or {}).get("tool") or {}) if len(sc) == 1 else {}
    out = []
    rule = sc_rule or gate.DEFAULT_SC_RULE
    if tool.get("rule", gate.DEFAULT_SC_RULE) != rule:  # ATM-1217: the rule changes the verdict
        out.append("cached pack was built with --shellcheck-rule %r, %r requested" % (tool.get("rule"), rule))
    for label, want, key, default in (
            ("--shellcheck-timeout", sc_timeout, "timeout_s", gate._default_sc_timeout(rule)),
            ("--shellcheck-exception-timeout", sc_ex_timeout, "exception_timeout_s", gate.DEFAULT_EXCEPTION_TIMEOUT),
            ("memory cap (MiB)", None, "memory_cap_mib", gate.DEFAULT_MEM_CAP_MIB),
            ("size cap (lines)", None, "max_lines", gate.DEFAULT_MAX_LINES)):
        if want in (None, ""):
            want = default
        try:
            same = float(tool.get(key)) == float(want)
        except (TypeError, ValueError):
            same = False
        if not same:
            out.append("cached pack was built with %s %r, %r requested" % (label, tool.get(key), want))
    return out


def cmd_emit(a):
    path = os.path.join(a.out_dir, "precheck.json")
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        print("precheck_pack_build: no usable pack at %s: %s" % (path, exc), file=sys.stderr)
        return 3
    if not isinstance(doc, dict):
        print("precheck_pack_build: %s is not a JSON object" % path, file=sys.stderr)
        return 3
    if doc.get("schema") != SCHEMA:
        print("precheck_pack_build: %s has schema=%r, want %r"
              % (path, doc.get("schema"), SCHEMA), file=sys.stderr)
        return 3
    batch_id = doc.get("batch_id")
    if not isinstance(batch_id, str) or not batch_id or batch_id == "UNKNOWN":
        print("precheck_pack_build: %s carries no genuine batch_id (got %r)"
              % (path, batch_id), file=sys.stderr)
        return 3
    all_pass = doc.get("all_pass")
    if not isinstance(all_pass, bool):
        print("precheck_pack_build: %s has a non-boolean all_pass (got %r)"
              % (path, all_pass), file=sys.stderr)
        return 3

    if a.expect_base or a.expect_head:
        # F-R2-9: a cached pack is reusable only when it is intact (body_hash), was
        # produced by the CURRENT gate (gate_version) and is bound to the requested
        # base/head. Verdict-outcome reasons (a FAIL is a legitimate cached result)
        # do not invalidate the cache.
        outcome = ("all_pass is not true", "shellcheck verdict is not PASS", "provenance.head_sha_source",
                   "shellcheck binding")
        stale = [x for x in pack_readiness(doc, a.expect_base, a.expect_head, deep=False)
                 if not x.startswith(outcome)]
        stale.extend(_params_mismatch(doc, a.expect_sc_timeout, a.expect_sc_exception_timeout, a.expect_sc_rule))
        if stale:
            print("precheck_pack_build: cached pack at %s is stale/unbound: %s" % (path, "; ".join(stale)),
                  file=sys.stderr)
            return 3

    if not a.validate_only:
        print("PRECHECK-PACK: %s" % os.path.abspath(path))
        print("BATCH-ID: %s" % batch_id)

    return 0 if all_pass else 1


def cmd_bind(a):
    try:
        with open(a.batch, encoding="utf-8") as fh:
            batch = json.load(fh)
    except (OSError, ValueError) as exc:
        print("precheck_pack_build: cannot read --batch: %s" % exc, file=sys.stderr)
        return 2
    if not isinstance(batch, dict):
        print("precheck_pack_build: --batch is not a JSON object", file=sys.stderr)
        return 2
    try:
        changed = _changed_paths(a.repo, a.base, a.head)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        print("precheck_pack_build: %s" % exc, file=sys.stderr)
        return 2
    if not changed:
        print("precheck_pack_build: %s..%s changes no path -- nothing to bind" % (a.base, a.head), file=sys.stderr)
        return 2
    paths = []
    for st, path in changed:
        d = subprocess.run(_change_diff_argv(a.repo, a.base, a.head, path), capture_output=True,
                           timeout=60, env=_git_env())
        if d.returncode != 0:
            print("precheck_pack_build: git diff for %r exited %d" % (path, d.returncode), file=sys.stderr)
            return 2
        paths.append({"path": path, "status": st, "change_id": "sha256:" + hashlib.sha256(d.stdout).hexdigest()})
    ids = sorted(p["change_id"] for p in paths)
    if a.rewrite_changes:
        batch["changes"] = ids
    elif ids != sorted(c for c in (batch.get("changes") or []) if isinstance(c, str)):
        print("precheck_pack_build: the binding's change_ids differ from batch.changes (descriptors and "
              "binding disagree)", file=sys.stderr)
        return 2
    batch["binding"] = {"schema": BINDING_SCHEMA, "base_sha": a.base, "head_sha": a.head,
                        "kind": a.kind, "paths": paths}
    if "body_hash" in batch:
        batch["body_hash"] = _body_hash_of(batch)
    _write_bytes(a.out, (_canon(batch) + "\n").encode("utf-8"))
    print("BOUND %d path(s) %s..%s" % (len(paths), a.base, a.head))
    return 0


def _submodule_head(path):
    """HEAD commit of the git repository whose toplevel IS `path`, else None."""
    top = subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"], capture_output=True, timeout=30,
                         env=_git_env())
    if top.returncode != 0 or os.path.realpath(top.stdout.decode("utf-8", "surrogateescape").strip()) != \
            os.path.realpath(path):
        return None
    hd = subprocess.run(["git", "-C", path, "rev-parse", "--verify", "--quiet", "HEAD^{commit}"],
                        capture_output=True, timeout=30, env=_git_env())
    sha = hd.stdout.decode("ascii", "replace").strip()
    return sha if hd.returncode == 0 and sha else None


def cmd_snapshot(a):
    env = _git_env()
    def git(*args, **kw):
        return subprocess.run(["git", "--literal-pathspecs", "-C", a.repo] + list(args), capture_output=True,
                              timeout=120, env=kw.get("env", env), input=kw.get("input"))
    try:
        paths = _read_path_list(a.paths_file)
    except OSError as exc:
        print("precheck_pack_build: cannot read --paths-file: %s" % exc, file=sys.stderr)
        return 2
    if not paths:
        print("precheck_pack_build: --paths-file names no path", file=sys.stderr)
        return 2
    hd = git("rev-parse", "--verify", "HEAD^{commit}")
    if hd.returncode != 0:
        print("precheck_pack_build: --repo has no HEAD commit", file=sys.stderr)
        return 2
    base = hd.stdout.decode().strip()
    with tempfile.TemporaryDirectory() as td:
        ienv = dict(env, GIT_INDEX_FILE=os.path.join(td, "index"))
        if git("read-tree", base, env=ienv).returncode != 0:
            print("precheck_pack_build: read-tree failed", file=sys.stderr)
            return 2
        for rel in paths:
            full = os.path.join(a.repo, rel)
            if os.path.islink(full):
                print("precheck_pack_build: refusing to snapshot a symlink: %s" % rel, file=sys.stderr)
                return 2
            sub_head = _submodule_head(full) if os.path.isdir(full) else None
            if sub_head:
                # I4: an initialised submodule -> its checked-out commit as a gitlink
                r = git("update-index", "--add", "--cacheinfo", "160000,%s,%s" % (sub_head, rel), env=ienv)
            elif os.path.isfile(full):
                ho = git("hash-object", "-w", "--no-filters", "--", rel)
                if ho.returncode != 0:
                    print("precheck_pack_build: hash-object failed for %s" % rel, file=sys.stderr)
                    return 2
                mode = "100755" if os.access(full, os.X_OK) else "100644"
                r = git("update-index", "--add", "--cacheinfo", "%s,%s,%s" % (mode, ho.stdout.decode().strip(), rel),
                        env=ienv)
            elif not os.path.lexists(full):
                r = git("update-index", "--force-remove", "--", rel, env=ienv)
            else:
                print("precheck_pack_build: not a regular file: %s" % rel, file=sys.stderr)
                return 2
            if r.returncode != 0:
                print("precheck_pack_build: update-index failed for %s: %s" % (rel, r.stderr.decode().strip()),
                      file=sys.stderr)
                return 2
        wt = git("write-tree", env=ienv)
        if wt.returncode != 0:
            print("precheck_pack_build: write-tree failed", file=sys.stderr)
            return 2
        tree = wt.stdout.decode().strip()
    date = git("show", "-s", "--format=%ci", base).stdout.decode().strip()
    cenv = dict(env, GIT_AUTHOR_NAME="precheck snapshot", GIT_AUTHOR_EMAIL="precheck-snapshot@invalid",
                GIT_COMMITTER_NAME="precheck snapshot", GIT_COMMITTER_EMAIL="precheck-snapshot@invalid",
                GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
    ct = git("commit-tree", tree, "-p", base, "-m", "precheck snapshot of uncommitted work (unreferenced)",
             env=cenv)
    if ct.returncode != 0:
        print("precheck_pack_build: commit-tree failed: %s" % ct.stderr.decode().strip(), file=sys.stderr)
        return 2
    print("BASE_SHA=%s" % base)
    print("HEAD_SHA=%s" % ct.stdout.decode().strip())
    return 0


def _git_out(repo, args, timeout=60):
    return subprocess.run(["git", "--literal-pathspecs", "-C", repo] + args, capture_output=True,
                          timeout=timeout, env=_git_env())


def _head_blob(repo, head, rel):
    """-> ("tracked", bytes) | ("absent", None) | ("symlink", target bytes) |
    ("gitlink", commit sha bytes) | ("error", None)."""
    lt = _git_out(repo, ["ls-tree", "-z", head, "--", rel])
    if lt.returncode != 0:
        return "error", None
    if not lt.stdout:
        return "absent", None
    meta = lt.stdout.split(b"\t", 1)[0].decode("ascii", "replace").split()
    if len(meta) == 3 and meta[0] == "160000" and meta[1] == "commit":
        return "gitlink", meta[2].encode("ascii")
    if len(meta) != 3 or meta[1] != "blob":
        return "error", None
    cf = _git_out(repo, ["cat-file", "blob", meta[2]])
    if cf.returncode != 0:
        return "error", None
    return ("symlink" if meta[0] == "120000" else "tracked"), cf.stdout


def _gitlink_current(repo, rel, sha):
    """I4: a submodule pointer "holds the head bytes" when the checked-out submodule
    is at that commit (an initialised submodule) or, uninitialised (an empty
    directory), when the repo index records that commit."""
    full = os.path.join(repo, rel)
    if os.path.islink(full) or not os.path.isdir(full):
        return False
    top = _git_out(full, ["rev-parse", "--show-toplevel"], 30)
    if top.returncode == 0 and os.path.realpath(top.stdout.decode("utf-8", "surrogateescape").strip()) == \
            os.path.realpath(full):
        hd = _git_out(full, ["rev-parse", "--verify", "--quiet", "HEAD"], 30)
        return hd.returncode == 0 and hd.stdout.decode("ascii", "replace").strip() == sha
    ls = _git_out(repo, ["ls-files", "-s", "-z", "--", rel], 30)
    meta = ls.stdout.split(b"\t", 1)[0].decode("ascii", "replace").split()
    return ls.returncode == 0 and len(meta) == 3 and meta[0] == "160000" and meta[1] == sha


def _batch_readiness(doc, base, head, repo):
    """F1: the batch the pack was built from must still exist unchanged, carry the
    pack's batch_id, be bound to the pack's base/head, have change_ids that
    recompute in `repo`, and the repo working tree must still hold the head bytes
    of every bound path (a pack whose code moved on is STALE)."""
    r = []
    p = doc.get("provenance") or {}
    bpath, bsha = p.get("batch_path"), p.get("batch_sha256")
    if not (isinstance(bpath, str) and os.path.isabs(bpath) and isinstance(bsha, str)):
        return ["provenance does not record batch_path/batch_sha256 (pack predates F1 -- rebuild)"]
    try:
        with open(bpath, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        return ["batch file %s is missing/unreadable: %s" % (bpath, exc)]
    if hashlib.sha256(raw).hexdigest() != bsha:
        r.append("batch file %s changed since the gate ran (sha256 mismatch)" % bpath)
    try:
        batch = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        return r + ["batch file %s does not parse: %s" % (bpath, exc)]
    if not isinstance(batch, dict):
        return r + ["batch file %s is not a JSON object" % bpath]
    if batch.get("batch_id") != doc.get("batch_id"):
        r.append("batch_id %r of the batch file != pack batch_id %r" % (batch.get("batch_id"), doc.get("batch_id")))
    if "body_hash" in batch and batch.get("body_hash") != _body_hash_of(batch):
        r.append("batch body_hash does not match the batch content")
    bnd = batch.get("binding")
    if not isinstance(bnd, dict):
        return r + ["batch carries no binding"]
    if bnd.get("base_sha") != base or bnd.get("head_sha") != head:
        r.append("batch binding %s..%s != pack provenance %s..%s" % (bnd.get("base_sha"), bnd.get("head_sha"), base, head))
    if bnd.get("kind") != p.get("kind"):
        r.append("batch binding kind %r != pack provenance kind %r" % (bnd.get("kind"), p.get("kind")))
    paths = bnd.get("paths")
    if not isinstance(paths, list) or not paths:
        return r + ["batch binding has no paths"]
    if not (isinstance(repo, str) and os.path.isdir(repo)):
        return r
    stale = []
    for e in paths:
        if not (isinstance(e, dict) and isinstance(e.get("path"), str) and isinstance(e.get("change_id"), str)):
            r.append("malformed binding entry %r" % (e,))
            continue
        rel = e["path"]
        d = subprocess.run(_change_diff_argv(repo, base, head, rel), capture_output=True, timeout=60, env=_git_env())
        if d.returncode != 0 or "sha256:" + hashlib.sha256(d.stdout).hexdigest() != e["change_id"]:
            r.append("change_id of %r does not recompute in %s" % (rel, repo))
        st, blob = _head_blob(repo, head, rel)
        full = os.path.join(repo, rel)
        try:
            if st == "absent":
                cur_ok = not os.path.lexists(full)
            elif st == "symlink":
                cur_ok = os.path.islink(full) and os.fsencode(os.readlink(full)) == blob
            elif st == "gitlink":
                cur_ok = _gitlink_current(repo, rel, blob.decode("ascii"))
            elif st == "tracked":
                if os.path.islink(full) or not os.path.isfile(full):
                    cur_ok = False
                else:
                    with open(full, "rb") as fh:
                        cur_ok = fh.read() == blob
            else:
                cur_ok = False
        except OSError:
            cur_ok = False
        if not cur_ok:
            stale.append(rel)
    if stale:
        r.append("working tree of %s diverges from the reviewed head for: %s (stale pack -- rebuild)"
                 % (repo, ", ".join(stale)))
    return r


def cmd_snapshot_manifest(a):
    """F15: writes WORKTREE_SNAPSHOT_MD5.txt for a --snapshot-paths pack -- one
    line per snapshotted path: md5 of the working-tree bytes AS FROZEN (read
    back from the head commit, so the manifest can never drift from the
    reviewed object), the repo, the status at base (tracked-modified |
    UNTRACKED-new | deleted) and the diff line count. Names are written as JSON
    strings when they hold a character a plain line cannot carry."""
    paths = _read_path_list(a.paths_file)
    repo_name = os.path.basename(os.path.realpath(a.repo))
    lines = ["# working-tree (uncommitted) snapshot frozen into unreferenced commit %s on base %s; "
             "md5 of each snapshotted file as frozen" % (a.head, a.base)]
    for rel in paths:
        st_h, blob = _head_blob(a.repo, a.head, rel)
        st_b, _bb = _head_blob(a.repo, a.base, rel)
        status = ("deleted" if st_h == "absent" else ("UNTRACKED-new" if st_b == "absent" else "tracked-modified"))
        md5 = hashlib.md5(blob).hexdigest() if blob is not None and st_h != "absent" else "-" * 32
        d = subprocess.run(_change_diff_argv(a.repo, a.base, a.head, rel), capture_output=True, timeout=60,
                           env=_git_env())
        shown = rel if rel.isprintable() and "  " not in rel else json.dumps(rel, ensure_ascii=False)
        lines.append("%s  %s  (repo=%s, %s, difflines=%d)" % (md5, shown, repo_name, status,
                                                            _lines_changed_of(d.stdout)))
    _write_bytes(a.out, ("\n".join(lines) + "\n").encode("utf-8", "surrogateescape"))
    return 0


def cmd_present_paths(a):
    """NUL-separated list of the --paths-file entries (+ --extra) that EXIST at
    --head in --repo (a path deleted at head cannot be checked out) -- the
    pathspec file for the partial `git checkout` of a --repo-root pack.
    NUL-safe end to end (a newline in a name is carried verbatim)."""
    try:
        paths = _read_path_list(a.paths_file) + list(a.extra or [])
    except OSError as exc:
        print("precheck_pack_build: cannot read --paths-file: %s" % exc, file=sys.stderr)
        return 2
    out, seen = [], set()
    for path in paths:
        if path in seen:
            continue
        seen.add(path)
        lt = _git_out(a.repo, ["ls-tree", "-z", a.head, "--", path])
        if lt.returncode != 0:
            print("precheck_pack_build: git ls-tree failed for %r" % path, file=sys.stderr)
            return 2
        if lt.stdout:
            out.append(path)
    if not out:
        print("precheck_pack_build: no changed path exists at head -- nothing to check out", file=sys.stderr)
        return 3
    sys.stdout.buffer.write(b"".join(x.encode("utf-8", "surrogateescape") + b"\0" for x in out))
    return 0


def _installed_shellcheck_version():
    """The `shellcheck --version` of this host (a version probe, not a lint: no memory cap)."""
    try:
        with tempfile.TemporaryDirectory() as empty:
            p = subprocess.run(["shellcheck", "--version"], capture_output=True, timeout=30, cwd=empty,
                               env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": empty,
                                    "LC_ALL": "C.UTF-8"})
    except (OSError, subprocess.TimeoutExpired):
        return None
    for ln in p.stdout.decode("utf-8", "replace").splitlines():
        if ln.lower().startswith("version:"):
            return ln.split(":", 1)[1].strip()
    return None


def _blob_sha(repo, commit, rel):
    """-> ("tracked", sha256 hex) | ("absent", None) | (other status, None)."""
    if commit == EMPTY_TREE:
        return "absent", None
    st, blob = _head_blob(repo, commit, rel)
    return st, (hashlib.sha256(blob).hexdigest() if st == "tracked" else None)


def _exceptions_readiness(p, repo, base, head):
    """I1: provenance.exceptions must record exactly the canonical TSV the bound head
    (and base) carry -- a pack built with another exceptions file, or none while the
    head tracks one, is not dispatch-ready."""
    r = []
    exc = p.get("exceptions")
    hst, hsha = _blob_sha(repo, head, CANONICAL_EXCEPTIONS_REL)
    bst, bsha = _blob_sha(repo, base, CANONICAL_EXCEPTIONS_REL)
    if hst not in ("tracked", "absent") or bst not in ("tracked", "absent"):
        return ["%s is not a regular file at base/head (%s/%s)" % (CANONICAL_EXCEPTIONS_REL, bst, hst)]
    if hst == "absent":
        if isinstance(exc, dict) and exc.get("head_blob_sha256"):
            r.append("provenance.exceptions records a %s the head does not track" % CANONICAL_EXCEPTIONS_REL)
        return r
    if not (isinstance(exc, dict) and exc.get("path") == CANONICAL_EXCEPTIONS_REL and exc.get("bound") is True
            and exc.get("head_blob_sha256") == hsha and exc.get("base_blob_sha256") == bsha):
        r.append("provenance.exceptions %r does not record the canonical %s of head (sha256 %s) and base (%s) -- "
                 "the pack was built with another exceptions file or none" % (exc, CANONICAL_EXCEPTIONS_REL, hsha, bsha))
    return r


_PARAM_KEYS = ("timeout_s", "exception_timeout_s", "memory_cap_mib", "max_lines")


def _params_readiness(p, tool):
    """GR12: provenance.shellcheck_params must be exactly the parameters the shellcheck evidence records, every
    one inside the gate's ceilings; a pack linted in the gate's TEST MODE (a private lock directory) is never
    dispatch-ready."""
    import precheck_pack_run as gate  # same directory; the gate's own ceilings (never a copy)
    r = []
    if tool.get("test_mode"):
        r.append("the pack was built in the gate's TEST MODE (PRECHECK_TEST_MODE: private lock directory) -- "
                 "never dispatch-ready")
    sp = p.get("shellcheck_params")
    want = {k: tool.get(k) for k in _PARAM_KEYS}
    if not isinstance(sp, dict) or sp != want:
        r.append("provenance.shellcheck_params %r != the shellcheck evidence's tool parameters %r" % (sp, want))
        return r
    ceil = {"timeout_s": gate.MAX_SC_TIMEOUT, "exception_timeout_s": gate.MAX_EXCEPTION_TIMEOUT,
            "memory_cap_mib": gate.DEFAULT_MEM_CAP_MIB, "max_lines": gate.DEFAULT_MAX_LINES}
    for k in _PARAM_KEYS:
        v = sp[k]
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not 0 < v <= ceil[k]:
            r.append("provenance.shellcheck_params.%s=%r is outside 0..%s" % (k, v, ceil[k]))
    return r


def _gitlink_bumps(repo, base, head):
    """F2: every submodule pointer (mode 160000) that differs between base and head of `repo` -> list of
    (path, old sha | None when added, new sha | None when removed). Read from git, never from the pack."""
    d = _git_out(repo, ["-c", "core.quotePath=false", "diff", "--raw", "-z", "--no-renames", "--no-abbrev",
                        "--no-textconv", "--no-ext-diff", base, head], 120)
    if d.returncode != 0:
        return None
    toks = d.stdout.split(b"\0")
    out, i = [], 0
    while i + 1 < len(toks):
        meta = toks[i].decode("ascii", "replace")
        path = toks[i + 1].decode("utf-8", "surrogateescape")
        i += 2
        f = meta.lstrip(":").split()
        if len(f) < 5:
            continue
        omode, nmode, osha, nsha = f[0], f[1], f[2], f[3]
        if "160000" in (omode, nmode):
            out.append((path, osha if omode == "160000" else None, nsha if nmode == "160000" else None))
    return out


def _copack_reasons(entries):
    """F2: a pack whose range bumps a gitlink is backed only together with a co-cited pack whose repo IS that
    submodule (realpath of <repo>/<path>) and whose base..head is exactly the old..new pointer (EMPTY_TREE
    base for a newly added submodule) -- otherwise the submodule's own changes reach review with no precheck.
    A removed submodule needs nothing. `entries` = [(pack path, doc)] of the readable packs."""
    r = []
    ranges = {}
    for path, doc in entries:
        p = (doc.get("provenance") or {}) if isinstance(doc, dict) else {}
        repo, base = p.get("repo"), p.get("base_sha")
        if isinstance(repo, str) and isinstance(base, list) and len(base) == 1:
            ranges[os.path.realpath(repo)] = (base[0], p.get("head_sha"))
    for path, doc in entries:
        p = (doc.get("provenance") or {}) if isinstance(doc, dict) else {}
        repo, base, head = p.get("repo"), p.get("base_sha"), p.get("head_sha")
        if not (isinstance(repo, str) and isinstance(base, list) and len(base) == 1 and isinstance(head, str)):
            continue
        bumps = _gitlink_bumps(repo, base[0], head)
        if bumps is None:
            r.append("%s: cannot list the gitlink changes of %s..%s in %s -- failing closed" % (path, base[0], head, repo))
            continue
        for sub, old, new in bumps:
            if new is None:
                continue
            want = (old or EMPTY_TREE, new)
            got = ranges.get(os.path.realpath(os.path.join(repo, sub)))
            if got != want:
                r.append("%s: the range bumps submodule %r %s..%s, but no co-cited pack covers exactly that range "
                         "of that submodule (got %s) -- a gitlink bump needs the submodule's own pack (F2)"
                         % (path, sub, want[0], want[1], ("%s..%s" % got) if got else "none"))
    return r


DELTA_ACTIVATION_REL = "precheck_shellcheck_delta.activation"  # next to precheck_pack.sh (review/)


def delta_activation():
    """r4 F8: the operator's explicit activation of the baseline-delta rule for dispatch -- a regular,
    non-symlink file review/precheck_shellcheck_delta.activation of THIS checkout (so a producer's own
    batch can add it only by getting it reviewed and merged) with `decision-ref: <reference>` (>= 8
    characters) and `activated-on: YYYY-MM-DD`. -> {"path", "decision_ref", "activated_on"} or
    {"path", "error"}. Absent = not activated (the r4 patch ships it absent)."""
    import re as _re
    path = os.path.join(os.path.dirname(_HERE), DELTA_ACTIVATION_REL)
    out = {"path": path}
    if os.path.islink(path) or not os.path.isfile(path):
        out["error"] = ("no operator activation record %s (DESIGN 4.8: activation is one operator decision; until "
                        "then only whole-file packs are dispatch-ready)" % path)
        return out
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as exc:
        out["error"] = "activation record %s unreadable: %s" % (path, exc)
        return out
    kv = {}
    for ln in text.splitlines():
        if ln.strip() and not ln.lstrip().startswith("#") and ":" in ln:
            k, v = ln.split(":", 1)
            kv[k.strip()] = v.strip()
    ref, day = kv.get("decision-ref", ""), kv.get("activated-on", "")
    if len(ref) < 8 or not _re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", day):
        out["error"] = ("activation record %s needs 'decision-ref: <reference, >= 8 chars>' and "
                        "'activated-on: YYYY-MM-DD' (got %r / %r)" % (path, ref, day))
        return out
    out.update(decision_ref=ref, activated_on=day)
    return out


def pack_readiness(doc, expect_base=None, expect_head=None, deep=True, allowed_roots=None):
    """-> list of reasons the pack is NOT dispatch-ready ([] = ready). `deep`
    adds the F1 batch/working-tree checks (the builder's cache check passes
    deep=False: a cache hit is judged by content address, not by the tree).
    `allowed_roots` (I3): when given, provenance.repo must BE one of them."""
    import re as _re
    r = []
    if not isinstance(doc, dict):
        return ["not a JSON object"]
    if doc.get("schema") != SCHEMA:
        r.append("schema %r != %r" % (doc.get("schema"), SCHEMA))
    bid = doc.get("batch_id")
    if not isinstance(bid, str) or not bid or bid == "UNKNOWN":
        r.append("no genuine batch_id")
    if doc.get("all_pass") is not True:
        r.append("all_pass is not true")
    try:
        if doc.get("body_hash") != _body_hash_of(doc):
            r.append("body_hash does not match the pack content")
    except (TypeError, ValueError) as exc:
        r.append("body not hashable: %s" % exc)
    try:
        gv = _gate_version()
    except OSError as exc:
        gv = None
        r.append("cannot read the gate library: %s" % exc)
    if gv and doc.get("gate_version") != gv:
        r.append("gate_version %r is not the current gate (%s) -- rebuild the pack" % (doc.get("gate_version"), gv))
    p = doc.get("provenance")
    if not isinstance(p, dict):
        r.append("no provenance")
        p = {}
    base = p.get("base_sha")
    base = base[0] if isinstance(base, list) and len(base) == 1 else None
    head = p.get("head_sha")
    hexre = r"[0-9a-f]{40,64}"
    if not (isinstance(base, str) and _re.fullmatch(hexre, base)):
        r.append("provenance.base_sha is not exactly one commit sha")
        base = None
    if not (isinstance(head, str) and _re.fullmatch(hexre, head)):
        r.append("provenance.head_sha missing")
        head = None
    if base and head and base == head:
        r.append("provenance base == head")
    if p.get("head_sha_source") != "batch-binding-verified":
        r.append("provenance.head_sha_source is %r, not 'batch-binding-verified'" % p.get("head_sha_source"))
    repo = p.get("repo")
    repo_ok = isinstance(repo, str) and os.path.isabs(repo)
    if repo_ok and base and head:
        hc = _git_out(repo, ["cat-file", "-e", head + "^{commit}"], 30)
        if hc.returncode != 0:
            r.append("provenance commit %s does not exist in %s" % (head, repo))
        if base == EMPTY_TREE:
            par = _git_out(repo, ["rev-list", "--parents", "-n", "1", head], 30)
            if par.returncode != 0 or len(par.stdout.split()) != 1:
                r.append("base is the empty tree but head %s is not a root commit" % head)
        else:
            bc = _git_out(repo, ["cat-file", "-e", base + "^{commit}"], 30)
            if bc.returncode != 0:
                r.append("provenance commit %s does not exist in %s" % (base, repo))
            elif _git_out(repo, ["merge-base", "--is-ancestor", base, head], 60).returncode != 0:
                r.append("provenance base %s is not an ancestor of head %s (F5)" % (base, head))
            if p.get("kind") == "snapshot":
                par1 = _git_out(repo, ["rev-parse", "--verify", "--quiet", head + "^1"], 30)
                if par1.stdout.decode("ascii", "replace").strip() != base:
                    r.append("snapshot head %s is not exactly one commit on top of base %s (F5)" % (head, base))
    elif not repo_ok:
        r.append("provenance.repo is not an absolute repository path")
    if allowed_roots and repo_ok and os.path.realpath(repo) not in {os.path.realpath(x) for x in allowed_roots}:
        r.append("provenance.repo %s is outside the allowed repositories (%s) -- a pack from an unrelated repo "
                 "cannot back this review (I3)" % (repo, ", ".join(allowed_roots)))
    if repo_ok and base and head:
        r.extend(_exceptions_readiness(p, repo, base, head))
    want_v = _installed_shellcheck_version()
    if want_v is None:
        r.append("cannot read this host's shellcheck version to compare with provenance.shellcheck_version")
    elif p.get("shellcheck_version") != want_v:
        r.append("provenance.shellcheck_version %r != this host's shellcheck %r (M6: rebuild with the pinned linter)"
                 % (p.get("shellcheck_version"), want_v))
    if expect_base and base != expect_base:
        r.append("pack base %s != expected %s" % (base, expect_base))
    if expect_head and head != expect_head:
        r.append("pack head %s != expected %s" % (head, expect_head))
    sc = [c for c in (doc.get("checks") or []) if isinstance(c, dict) and c.get("check") == "shellcheck"]
    if len(sc) != 1:
        r.append("no single shellcheck check")
    else:
        ev = sc[0].get("evidence") or {}
        b = ev.get("binding") or {}
        if sc[0].get("verdict") != "PASS":
            r.append("shellcheck verdict is not PASS")
        mode, rule = ev.get("mode"), (ev.get("tool") or {}).get("rule", "whole-file")
        if mode == "baseline-delta":
            # ATM-1217: the opt-in delta rule is dispatch-ready only as what it claims to be -- requested
            # (tool.rule), with its base resolved and its own rule id recorded
            dl = ev.get("delta") or {}
            if rule != "baseline-delta" or dl.get("base_resolved") is not True or not dl.get("rule_id"):
                r.append("shellcheck mode baseline-delta is inconsistent (tool.rule=%r, delta.base_resolved=%r, "
                         "delta.rule_id=%r)" % (rule, dl.get("base_resolved"), dl.get("rule_id")))
            import precheck_pack_run as _g  # same directory; the gate's own rule id (never a copy)
            if dl.get("rule_id") and dl.get("rule_id") != _g.DELTA_RULE_ID:
                r.append("shellcheck delta.rule_id %r is not this gate's %r" % (dl.get("rule_id"), _g.DELTA_RULE_ID))
            if deep:
                # r4 F8 (11.4.240): a producer cannot opt its own batch into the laxer rule for DISPATCH; the
                # delta rule is dispatch-ready only after the operator's explicit activation record exists
                act = delta_activation()
                if act.get("error"):
                    r.append("shellcheck mode baseline-delta is not activated for dispatch: %s" % act["error"])
        elif mode != "whole-file" or rule != "whole-file":
            r.append("shellcheck did not run in whole-file or baseline-delta mode (mode=%r, rule=%r)" % (mode, rule))
        if b.get("state") != "bound":
            r.append("shellcheck binding is %r, not 'bound'" % b.get("state"))
        r.extend(_params_readiness(p, ev.get("tool") or {}))
    if deep and base and head and repo_ok:
        r.extend(_batch_readiness(doc, base, head, repo))
    return r


def cmd_verify(a):
    if a.print_gate_version:
        print(_gate_version())
        return 0
    if not a.pack:
        print("precheck_pack_build: verify needs --pack", file=sys.stderr)
        return 2
    if len(a.pack) > 1 and (a.expect_base or a.expect_head):
        print("precheck_pack_build: --expect-base/--expect-head apply to a single --pack", file=sys.stderr)
        return 2
    reasons, repos, ids, entries = [], {}, [], []
    for path in a.pack:
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
        except (OSError, ValueError) as exc:
            reasons.append("%s: cannot read pack: %s" % (path, exc))
            continue
        for x in pack_readiness(doc, a.expect_base, a.expect_head, allowed_roots=a.allowed_root):
            reasons.append(("%s: %s" % (path, x)) if len(a.pack) > 1 else x)
        repo = (doc.get("provenance") or {}).get("repo") if isinstance(doc, dict) else None
        if isinstance(repo, str):
            key = os.path.realpath(repo)
            if key in repos:
                reasons.append("packs %s and %s cover the same repo %s -- a cross-repo review carries ONE pack "
                               "per repo" % (repos[key], path, repo))
            repos[key] = path
        ids.append(doc.get("batch_id") if isinstance(doc, dict) else None)
        entries.append((path, doc))
    reasons.extend(_copack_reasons(entries))
    if reasons:
        for x in reasons:
            print("NOT-READY: %s" % x, file=sys.stderr)
        return 1
    print("READY %s" % " ".join(str(i) for i in ids))
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="precheck_pack_build_run")
    sub = p.add_subparsers(dest="cmd", required=True)

    pp = sub.add_parser("prepare")
    pp.add_argument("--repo", required=True)
    pp.add_argument("--base", required=True)
    pp.add_argument("--head", required=True)
    pp.add_argument("--paths-file", required=True)
    pp.add_argument("--scratch", required=True)
    pp.add_argument("--logic-group", required=True)
    pp.set_defaults(func=cmd_prepare)

    pe = sub.add_parser("emit")
    pe.add_argument("--out-dir", required=True)
    pe.add_argument("--validate-only", action="store_true")
    pe.add_argument("--expect-base")
    pe.add_argument("--expect-head")
    pe.add_argument("--expect-sc-timeout")
    pe.add_argument("--expect-sc-exception-timeout")
    pe.add_argument("--expect-sc-rule")
    pe.set_defaults(func=cmd_emit)

    pb = sub.add_parser("bind")
    pb.add_argument("--repo", required=True)
    pb.add_argument("--base", required=True)
    pb.add_argument("--head", required=True)
    pb.add_argument("--batch", required=True)
    pb.add_argument("--out", required=True)
    pb.add_argument("--rewrite-changes", action="store_true")
    pb.add_argument("--kind", choices=("commit", "snapshot"), default="commit")
    pb.set_defaults(func=cmd_bind)

    ps = sub.add_parser("snapshot")
    ps.add_argument("--repo", required=True)
    ps.add_argument("--paths-file", required=True)
    ps.set_defaults(func=cmd_snapshot)

    psm = sub.add_parser("snapshot-manifest")
    psm.add_argument("--repo", required=True)
    psm.add_argument("--base", required=True)
    psm.add_argument("--head", required=True)
    psm.add_argument("--paths-file", required=True)
    psm.add_argument("--out", required=True)
    psm.set_defaults(func=cmd_snapshot_manifest)

    psp = sub.add_parser("present-paths")
    psp.add_argument("--repo", required=True)
    psp.add_argument("--head", required=True)
    psp.add_argument("--paths-file", required=True)
    psp.add_argument("--extra", action="append", default=[])
    psp.set_defaults(func=cmd_present_paths)

    pv = sub.add_parser("verify")
    pv.add_argument("--pack", action="append", default=[])
    pv.add_argument("--expect-base")
    pv.add_argument("--expect-head")
    pv.add_argument("--print-gate-version", action="store_true")
    pv.add_argument("--allowed-root", action="append", default=[])
    pv.set_defaults(func=cmd_verify)

    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    try:
        return a.func(a)
    except Exception as exc:  # an internal error is never a finding -- refuse honestly
        print("precheck_pack_build: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
