#!/usr/bin/env python3
"""custody_sweep.py - stash/worktree custody inventory + propose-only sweep
(spec-004 "fast-dev-cycles", User Story 5, T137, plan task T-B08; FR-016,
FR-017; contracts/common-conventions.md's open-gap tool list -- no contract
file exists yet, so this file's interface is fixed by (a) T137's own plan-
task text and (b) the RED test's already-committed, independently-derived
fixture schema (T129, tests/test_custody_sweep_red.sh +
tests/fixtures/custody_sweep/*.json), per common-conventions.md's stated
convention for open-gap tools ("their interface, output and RED fixtures
are fixed by the plan task text until a contract is written").

Purpose (T137's own task line, verbatim): "inventory stashes and worktrees
with owner item, last commit, dirty-file hashes, existing custody backups;
propose land/keep/retire each with a verified backup; executes nothing
without operator confirmation".

HONEST CORRECTION carried forward from T129's own EVIDENCE block (section
11.4.6) -- this file's task line originally repeated a STALE "seeded with
the known state" claim (stash@{3} already-landed / two worktrees / a
stash@{5} backup) that T129's live re-verification found wrong on all
three counts. This implementation NEVER hardcodes any specific stash id,
worktree id, or count from that stale text -- every inventory below is
computed by genuinely re-querying `git stash list` / `git worktree list`
live, every run, with zero assumptions about today's specific contents
(exactly as T129's own EVIDENCE block instructs).

Three subcommands:

  inventory --repo-root <path> [--backup-root <path>] --out <path>
      Read-only. Enumerates the REAL, live `git stash list` and `git
      worktree list --porcelain` for --repo-root (default: `git
      rev-parse --show-toplevel` from cwd), and for each entry resolves:
        - entry_kind ("stash" | "worktree"), entry_id
        - owner_item: best-effort ATM-NNN extraction from the stash
          message / worktree HEAD commit subject / worktree branch name,
          else null (never guessed beyond that regex, section 11.4.6)
        - last_commit: the stash's own commit (stash entries) or the
          worktree's live HEAD sha (worktree entries)
        - dirty_file_hash: sha256 of the real patch content (`git stash
          show -p <ref>` for a stash; `git -C <path> diff HEAD` for a
          worktree), computed FRESH every run -- never cached, never
          assumed from a prior run
        - existing_backup: {backup_artifact_path, backup_hash} if a
          matching backup artifact is found under --backup-root (see
          BACKUP LAYOUT below), with backup_hash recomputed live against
          the real file on disk (section 11.4.245: the oracle re-derives,
          it never trusts a stored value) -- else null, with an explicit
          `backup_search_paths` list of exactly what was checked and
          found absent (section 11.4.201(6): an absence is reported with
          the paths that were actually probed, never a bare null with no
          trace of the search).

  propose --inventory <path> --out <path> [--backup-root <path>]
      Read-only (no git mutation of any kind -- no `stash drop`, no
      `worktree remove`, no `git push`; section 11.4.113 / C-006). For
      each inventoried entry, proposes exactly one of {keep, land,
      retire} using the safe-reversible default (section 11.4.101): an
      entry with NO verified backup on disk is always proposed `keep`
      (the non-destructive action); an entry WITH a verified backup
      (existing_backup non-null AND its hash independently re-verified
      against the real file at propose time) is proposed `retire`
      (worktree) or `land` (stash) -- attaching that verified
      backup_hash + backup_artifact_path. Every proposal's own verdict
      (ALLOWED | REFUSED) is computed via `derive_verdict` below (the
      section 9.2 rule: a destructive proposal without a hash-verified
      backup is REFUSED) so an operator reviewing the output document
      never has to re-derive it by hand. NOTHING is executed -- this
      subcommand only writes a proposal document; turning a proposal
      into a real `git stash drop` / `git worktree remove` is a
      SEPARATE, later, explicitly-operator-confirmed step this tool
      does not implement at all (no --apply flag exists on this tool,
      unlike host_report.py cleanup's --apply + backup-marker pattern --
      section 9.2 / 11.4.101: the safest "executes nothing" is not
      merely defaulting to read-only, it is not shipping the destructive
      code path in the first place).

  verify-proposal --proposal <path> [--repo-root <path>] [--out <path>]
      Read-only. Takes ONE proposal document matching the RED test's own
      fixture schema exactly:
        {entry_kind, entry_id, action, backup_hash, backup_artifact_path
         [, expected_verdict, reason]}
      (the last two are fixture-authoring metadata this subcommand reads
      but never trusts -- see below) and independently computes
      ALLOWED | REFUSED via `derive_verdict`, re-hashing the real
      backup_artifact_path file (resolved against --repo-root, default
      `git rev-parse --show-toplevel`) at verification time. If the
      input document carries its own `expected_verdict` field (as every
      one of T129's five fixtures does) and it disagrees with the
      independently computed verdict, that disagreement is reported
      (never silently swallowed) but NEVER substituted for the computed
      verdict -- the computed verdict alone decides the exit code,
      exactly per this file's own EVIDENCE block requirement ("the hash
      MUST be re-verified against the live file at test time, never
      trusted from this fixture alone").

Exit codes (contracts/common-conventions.md C-001, verbatim table):
  0 success / ALLOWED
  1 a finding: REFUSED, or a disagreement between a supplied
    expected_verdict and the independently computed verdict
  2 usage / configuration error (bad args, unreadable/invalid JSON,
    missing required proposal fields, unresolvable --repo-root)
  3 self-test failed (`selftest` subcommand only: a control needle did
    not discriminate, or a golden/negative-control fixture resolved to
    the wrong verdict)
  4 BLIND: a required input file genuinely could not be read at all
    (e.g. the --inventory document for `propose` is missing or unparseable)
    -- reserved for "could not look", never for "looked and found no
    backup" (that is a REFUSED finding, not BLIND; see derive_verdict).

--determinism-check (C-003): re-invokes this SAME process twice as
subprocesses with the SAME argv (minus the flag itself) and compares
body_hash (run_meta -- host name -- is excluded from the hash by
construction, matching every sibling C-002 tool in this tree). Exit 0
stable, 1 body_hash mismatch, 4 a run produced no honest verdict.

HONEST BOUNDARY on `inventory --determinism-check` specifically (section
11.4.6, measured live during this tool's own build/verify pass, never
assumed): `verify-proposal` and `propose --inventory <fixed-file>` are
pure functions of a file argument and are PROVEN byte-deterministic
across back-to-back runs (measured: identical body_hash both times).
`inventory`'s only "input" is live, externally-mutable `git` state on
THIS checkout -- on a heavily-contended, actively multi-track-committed
shared repository (this project's own standing operating mode, section
11.4.176/11.4.192), the tracked working-tree diff of the MAIN worktree
entry can genuinely change between two subprocess invocations a fraction
of a second apart (measured live: the same HEAD commit, a DIFFERENT
`dirty_file_hash.sha256` on the second call, because a concurrent
process wrote to a tracked file in between). This is NOT a code defect
in this file -- it is the same honest limitation any live-external-state
reader in this tree has (e.g. a host-resource-attribution tool sampling
live host state) -- and `inventory --determinism-check` is expected to
occasionally report exit 1 on this specific checkout for exactly that
reason, never silently claimed stable when it measurably was not.

BACKUP LAYOUT (this tool's own convention going forward -- no pre-
existing stash-backup convention was found anywhere under qa-results/ or
docs/ by T129's own exhaustive `grep -rl "stash@{5}"`, so this is stated
here as a NEW, explicit, documented layout rather than silently invented
inline):
  <backup-root>/backup_worktrees/<entry_id>/tracked.patch   (worktree;
      matches the REAL, already-existing layout under
      qa-results/agent_custody_20260926/backup_worktrees/<id>/tracked.patch)
  <backup-root>/backup_stashes/<sanitized_entry_id>/patch.diff  (stash;
      sanitized_entry_id = entry_id with every '{', '}', '@' replaced by
      '_', e.g. stash@{5} -> stash_5 -- NO such directory currently
      exists for any real stash in this repo, so every stash entry's
      existing_backup resolves null today, honestly, until an operator
      creates one via this layout).

Producer != Verifier (section 11.4.240): this file is the LATER
implementation of T-B08; T129's RED test and its five fixtures were
authored and committed BEFORE this file existed, by a different task, and
this file's `derive_verdict` below is an independent implementation of
the section 9.2 rule -- it does not import, share code with, or read
T129's test file's own from-scratch `derive_verdict` Python function
(this file only READS the fixture *data* files under
tests/fixtures/custody_sweep/ in the `selftest` subcommand, exactly as
C-005 mandates every tool's self-validation triple do).
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers. Imported by
# file path (not a package) since constitution/scripts/fastcycle has no
# __init__.py anywhere -- matches this tree's established flat-script layout
# (identical to closure/reopen_rate.py's own wiring).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402  (path-inserted import, see above)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

SCHEMA_INVENTORY = "custody-sweep-inventory/v1"
SCHEMA_PROPOSE = "custody-sweep-propose/v1"
SCHEMA_VERIFY = "custody-sweep-verify/v1"

# ---------------------------------------------------------------------------
# T140 Round 9/9b review (fixed here; mirrors `handoff.py`'s/
# `limit_class.py`'s own identically-purposed helpers, section 11.4.227
# reuse-the-SAME-discipline): three cooperating fixes closing the WHOLE
# "a diagnostic-print/pre-parse crash can leave --out lying" defect class
# both Round 9 reviewers converged on, rather than the two specific sites
# either one reported (their own shared framing: "the fix should close the
# whole class, not these two points").
#
# `_real_print` is captured BEFORE any renaming below so `_safe_print`'s
# own implementation always calls the REAL builtin, never itself.
# ---------------------------------------------------------------------------
_real_print = print


def _safe_print(*args, **kwargs):
    """T140 Round 9 review finding R9-I1 + R9-M2 (fixed here; section
    11.4.227 reuse-the-SAME-discipline -- every `print(...)` call site in
    this file's subcommand handlers and dispatch boundary below is
    renamed to this function): NO diagnostic/success print anywhere in
    this file may be allowed to raise and escape uncaught -- a `--out`
    document already written (the durable, authoritative record of this
    invocation's real result) must NEVER be silently OVERWRITTEN by
    `main()`'s own dispatch-boundary internal-error doc merely because a
    SUBSEQUENT, best-effort stdout/stderr diagnostic print failed (see
    `handoff.py`'s own sibling `_safe_print` for the exact live repro of
    this class -- identical mechanism, applied here).

    Also closes R9-I1 (a closed/unwritable stderr -- dead pipe reader,
    ENOSPC log redirect, `2>/dev/full` -- previously escaped the SAME
    way, uncaught, before the `--out` doc was even attempted, exiting
    120, outside this tool's documented {0,1,2,3,4} contract; live-
    reproduced: `custody_sweep.py inventory --repo-root /nonexist --out
    X` normally rc=2 with a document written, `2>/dev/full` rc=120 with
    NO document written): swallows ANY exception from the underlying
    `print()` call and, on failure, best-effort re-points the TARGET
    stream's own file descriptor at `os.devnull` (this round's own
    proven fix direction) so a LATER print to the SAME now-broken
    stream, or Python's own interpreter-shutdown flush of it, cannot
    re-raise and turn an otherwise-clean exit code into an unrelated
    120."""
    stream = kwargs.get("file", sys.stdout)
    try:
        _real_print(*args, **kwargs)
    except Exception:
        try:
            fd = stream.fileno()
            os.dup2(os.open(os.devnull, os.O_WRONLY), fd)
        except Exception:
            pass


def _safe_str(exc):
    """T140 Round 9 review finding R9-M1 (fixed here): see `handoff.py`'s
    own identically-purposed sibling for the full rationale. Falls back to
    just the exception's type name on failure."""
    try:
        return str(exc)
    except Exception:
        return "<%s: str() raised>" % type(exc).__name__


def _scan_argv_for_out(argv):
    """T140 Round 9b review finding R9b-I1 (fixed here): see `handoff.py`'s
    own identically-purposed sibling for the full rationale -- best-effort
    extraction of `--out`'s value directly from RAW argv, usable even
    BEFORE `build_arg_parser()` has constructed/parsed anything. Supports
    both `--out VALUE` and `--out=VALUE`. `selftest` carries no `--out`
    flag -- this scan correctly returns None for it, same as any other
    invocation genuinely lacking one."""
    for i, tok in enumerate(argv):
        if tok == "--out" and i + 1 < len(argv):
            return argv[i + 1]
        if tok.startswith("--out="):
            return tok[len("--out="):]
    return None


def _invalidate_stale_out(out_path):
    """T140 Round 9b review finding R9b-I1 (fixed here): see `handoff.py`'s
    own identically-purposed sibling for the full rationale and live
    repro -- remove any EXISTING `--out` file EARLY, before any
    computation for THIS invocation begins, so a crash reaching `main()`
    BEFORE a fresh document is written for THIS invocation can never
    leave a STALE, previous-run `--out` document in place looking like a
    genuine, fresh result. Best-effort: a removal failure is swallowed
    here -- it surfaces downstream when the real write is attempted."""
    if not out_path:
        return
    try:
        os.remove(out_path)
    except OSError:
        pass


ATM_RE = re.compile(r"ATM-\d+")
DESTRUCTIVE_ACTIONS = ("land", "retire")
VALID_ACTIONS = ("keep", "land", "retire")
DIFF_FILE_RE = re.compile(r"^diff --git a/(.+?) b/")


# ---------------------------------------------------------------------------
# Small git helpers. Every call is read-only (section 11.4.113 / C-006: no
# tool in this file issues stash/clean/reset --hard/push --force/-- any
# mutating git subcommand -- grep this file for 'push', 'drop', 'remove',
# 'reset', 'clean' to confirm none appear as an argv element anywhere below).
# ---------------------------------------------------------------------------
def _run(args, cwd=None, check=True, env=None):
    """`env=None` (the default, EVERY pre-existing call site) preserves the
    exact prior behaviour -- `subprocess.run`'s own `env=None` default means
    "inherit the parent process's environment unchanged", so this parameter
    is purely additive and never a behaviour change for any call site that
    does not pass it. `env=<dict>` REPLACES the child's environment
    entirely (never merges with `os.environ`) -- the ONE thing a caller
    genuinely needing isolation (see `_sanitized_scratch_env()` below) can
    rely on (T140 Round 8 review finding R8-I2)."""
    proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True, env=env)
    if check and proc.returncode != 0:
        raise RuntimeError(
            "command failed (rc=%d): %s\nstderr: %s" % (proc.returncode, " ".join(args), proc.stderr.strip())
        )
    return proc.returncode, proc.stdout, proc.stderr


def _sanitized_scratch_env():
    """T140 Round 8 review finding R8-I2 (section 11.4.201/11.4.6): builds a
    FRESH environment dict (never mutates `os.environ`) fully isolated from
    the parent process's own git state, for use ONLY by git operations
    against a throwaway SCRATCH repository (e.g.
    `_selftest_golden_good_scratch_check`'s own `git init`/`config`/`add`/
    `commit`/`status`/`diff` calls).

    Round 8's own live reproduction: this tool's scratch-repo `_run(...)`
    calls previously passed NO explicit `env=` at all, so they silently
    inherited whatever `GIT_DIR`/`GIT_WORK_TREE`/etc. happened to be set in
    the CALLING process's environment -- the NORMAL case whenever this tool
    is invoked from inside a real git hook. `git`'s own `-C <path>` flag
    does NOT override an explicitly-set `GIT_DIR` (git honours `GIT_DIR`
    over `-C`'s cwd-style redirection), so every one of this tool's own
    `-C <scratch_repo>` calls silently landed on the HOST's real repository
    instead -- reproduced live: a throwaway victim repo's `.git/config`
    gained unwanted `core.hooksPath=` (empty, disabling its hooks),
    `user.email`/`user.name` overrides, and `commit.gpgsign=false`, and in
    the SAME run the selftest itself wrongly FAILED its own golden-good
    case (rc=3) because `git -C <scratch>` operations were silently
    redirected onto the unrelated victim repo instead of the scratch one.

    Strips EVERY `GIT_*` environment variable (not merely `GIT_DIR`/
    `GIT_WORK_TREE` -- the full set git itself recognises, e.g.
    `GIT_INDEX_FILE`/`GIT_OBJECT_DIRECTORY`/
    `GIT_ALTERNATE_OBJECT_DIRECTORIES`/`GIT_CONFIG`, none of which this
    function enumerates individually -- any environment variable whose name
    starts with `GIT_` is caller-controlled git-redirection state and is
    stripped uniformly) and additionally pins `GIT_CONFIG_NOSYSTEM=1` +
    `GIT_CONFIG_GLOBAL=/dev/null` so no system-wide or user-global git
    config (hooks, signing keys, aliases) can influence the scratch
    operation either -- full isolation from BOTH the parent process's own
    git environment AND any global/system git config, matching this
    function's own scratch-repo contract exactly. NEVER used for this
    tool's own `--repo-root` git calls (those legitimately need the
    caller's real ambient environment) -- scratch-only, by construction of
    every call site that passes it."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    return env


def resolve_repo_root(explicit):
    if explicit:
        root = os.path.abspath(explicit)
        if not os.path.isdir(os.path.join(root, ".git")) and not os.path.isfile(os.path.join(root, ".git")):
            raise RuntimeError("--repo-root %r has no .git -- not a git checkout" % explicit)
        return root
    rc, out, err = _run(["git", "rev-parse", "--show-toplevel"], check=False)
    if rc != 0:
        raise RuntimeError("could not resolve a repo root: not inside a git checkout and no "
                            "--repo-root given (git rev-parse --show-toplevel failed: %s)" % err.strip())
    return out.strip()


def sha256_of_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_of_text(text):
    return sha256_of_bytes(text.encode("utf-8"))


def owner_item_from_text(*texts):
    for t in texts:
        if not t:
            continue
        m = ATM_RE.search(t)
        if m:
            return m.group(0)
    return None


# ---------------------------------------------------------------------------
# Inventory: stashes
# ---------------------------------------------------------------------------
def list_stash_entries(root):
    rc, out, _ = _run(["git", "-C", root, "stash", "list"], check=False)
    if rc != 0:
        return []
    entries = []
    for line in out.splitlines():
        m = re.match(r"^(stash@\{\d+\}): (.*)$", line)
        if not m:
            continue
        entries.append({"ref": m.group(1), "message": m.group(2)})
    return entries


def stash_files_touched(root, ref, env=None):
    rc, out, _ = _run(["git", "-C", root, "stash", "show", "-p", ref], check=False, env=env)
    if rc != 0:
        return [], ""
    files = []
    for line in out.splitlines():
        m = DIFF_FILE_RE.match(line)
        if m:
            files.append(m.group(1))
    return files, out


def stash_base_commit(root, ref):
    rc, out, _ = _run(["git", "-C", root, "rev-parse", "%s^1" % ref], check=False)
    if rc != 0:
        return None
    return out.strip()


def stash_commit(root, ref):
    rc, out, _ = _run(["git", "-C", root, "rev-parse", ref], check=False)
    if rc != 0:
        return None
    return out.strip()


def find_stash_backup(root, backup_root, entry_id):
    sanitized = re.sub(r"[{}@]", "_", entry_id)
    candidate = os.path.join(backup_root, "backup_stashes", sanitized, "patch.diff")
    searched = [os.path.relpath(candidate, root) if candidate.startswith(root) else candidate]
    if os.path.isfile(candidate):
        with open(candidate, "rb") as fh:
            data = fh.read()
        return {"backup_artifact_path": searched[0], "backup_hash": sha256_of_bytes(data)}, searched
    return None, searched


def build_stash_entry(root, backup_root, ref, message):
    files, patch_text = stash_files_touched(root, ref)
    owner_item = owner_item_from_text(message)
    dirty_hash = sha256_of_text(patch_text) if patch_text else None
    dirty_status = "dirty" if patch_text else "empty_patch"
    backup, searched = find_stash_backup(root, backup_root, ref)
    return {
        "entry_kind": "stash",
        "entry_id": ref,
        "message": message,
        "owner_item": owner_item,
        "last_commit": stash_commit(root, ref),
        "base_commit": stash_base_commit(root, ref),
        "files_touched": files,
        "dirty_file_hash": {"status": dirty_status, "sha256": dirty_hash},
        "existing_backup": backup,
        "backup_search_paths": searched,
    }


# ---------------------------------------------------------------------------
# Inventory: worktrees
# ---------------------------------------------------------------------------
AGENT_WT_RE = re.compile(r"\.claude/worktrees/agent-([0-9a-fA-F]+)$")


def list_worktree_entries(root, env=None):
    rc, out, _ = _run(["git", "-C", root, "worktree", "list", "--porcelain"], check=False, env=env)
    if rc != 0:
        return []
    entries = []
    cur = {}
    for line in out.splitlines():
        if line.startswith("worktree "):
            if cur:
                entries.append(cur)
            cur = {"path": line[len("worktree "):].strip()}
        elif line.startswith("HEAD "):
            cur["head"] = line[len("HEAD "):].strip()
        elif line.startswith("branch "):
            cur["branch"] = line[len("branch "):].strip()
        elif line == "bare":
            cur["bare"] = True
        elif line == "detached":
            cur["detached"] = True
    if cur:
        entries.append(cur)
    return entries


def worktree_entry_id(path, root):
    m = AGENT_WT_RE.search(path)
    if m:
        return m.group(1)
    if os.path.abspath(path) == os.path.abspath(root):
        return "MAIN"
    return os.path.basename(path.rstrip("/"))


def worktree_head_subject(path):
    rc, out, _ = _run(["git", "-C", path, "log", "-1", "--format=%s"], check=False)
    if rc != 0:
        return None
    return out.strip()


def worktree_dirty_state(path, env=None):
    rc, status_out, _ = _run(["git", "-C", path, "status", "--porcelain=v1"], check=False, env=env)
    if rc != 0:
        return {"status": "UNMEASURED", "sha256": None, "has_untracked": None}, ""
    if not status_out.strip():
        return {"status": "clean", "sha256": None, "has_untracked": False}, ""
    rc2, diff_out, _ = _run(["git", "-C", path, "diff", "HEAD"], check=False, env=env)
    has_untracked = any(line.startswith("?? ") for line in status_out.splitlines())
    if rc2 == 0 and diff_out:
        return {"status": "dirty", "sha256": sha256_of_text(diff_out), "has_untracked": has_untracked}, diff_out
    if has_untracked:
        return {"status": "untracked_only", "sha256": None, "has_untracked": True}, ""
    return {"status": "clean", "sha256": None, "has_untracked": False}, ""


def resolve_live_dirty_state(entry_kind, entry_id, root, env=None):
    """Independently RE-DERIVES the entry's CURRENT live dirty state, fresh,
    at call time -- reusing the EXACT SAME git-querying functions `inventory`
    itself uses to compute `dirty_file_hash` in the first place (never a
    second implementation, section 11.4.227) -- so a backup can be checked
    against what the stash/worktree ACTUALLY looks like RIGHT NOW, never
    against a stale value cached in an inventory document and never against
    itself (section 9.2 / T140 review finding I3: hashing the backup file
    and comparing it to itself proves nothing about whether that backup
    still covers today's content).

    Returns (live_sha256_or_None, has_untracked_bool_or_None, found_bool).

    found=False means entry_id no longer resolves to a LIVE stash/worktree
    at all (e.g. already dropped/removed since the inventory was taken) --
    treated conservatively as "cannot verify coverage", never as "matches"
    (section 11.4.101 safe-reversible default; section 11.4.201: an
    unresolvable signal takes the conservative-safe branch, never the
    permissive one).

    has_untracked is always False for a stash entry: `git stash` (without
    `-u`) never captures untracked files in the first place, so there is no
    untracked-coverage question to ask of a stash backup the way there is
    for a worktree's tracked-only tracked.patch backup (see BACKUP LAYOUT
    above -- a worktree's backup covers `git diff HEAD` only, never `git
    status`'s `??` entries).
    """
    if entry_kind == "stash":
        rc, _out, _err = _run(["git", "-C", root, "rev-parse", "--verify", "-q", entry_id],
                               check=False, env=env)
        if rc != 0:
            return None, False, False
        _files, patch_text = stash_files_touched(root, entry_id, env=env)
        live_hash = sha256_of_text(patch_text) if patch_text else None
        return live_hash, False, True
    if entry_kind == "worktree":
        for wt in list_worktree_entries(root, env=env):
            path = wt.get("path")
            if not path:
                continue
            if worktree_entry_id(path, root) != entry_id:
                continue
            if not os.path.isdir(path):
                return None, None, False
            dirty_state, _diff = worktree_dirty_state(path, env=env)
            return dirty_state.get("sha256"), bool(dirty_state.get("has_untracked")), True
        return None, None, False
    return None, None, False


def find_worktree_backup(root, backup_root, entry_id):
    candidate = os.path.join(backup_root, "backup_worktrees", entry_id, "tracked.patch")
    searched = [os.path.relpath(candidate, root) if candidate.startswith(root) else candidate]
    if os.path.isfile(candidate):
        with open(candidate, "rb") as fh:
            data = fh.read()
        return {"backup_artifact_path": searched[0], "backup_hash": sha256_of_bytes(data)}, searched
    return None, searched


def build_worktree_entry(root, backup_root, wt):
    path = wt.get("path")
    entry_id = worktree_entry_id(path, root)
    branch = wt.get("branch", "")
    subject = worktree_head_subject(path) if path and os.path.isdir(path) else None
    owner_item = owner_item_from_text(subject, branch)
    dirty_state, _diff = worktree_dirty_state(path) if path and os.path.isdir(path) else (
        {"status": "UNMEASURED", "sha256": None, "has_untracked": None}, "")
    backup, searched = find_worktree_backup(root, backup_root, entry_id)
    return {
        "entry_kind": "worktree",
        "entry_id": entry_id,
        "path": path,
        "branch": branch,
        "is_main": entry_id == "MAIN",
        "owner_item": owner_item,
        "last_commit": wt.get("head"),
        "dirty_file_hash": dirty_state,
        "existing_backup": backup,
        "backup_search_paths": searched,
    }


# ---------------------------------------------------------------------------
# Core rule (section 9.2): a destructive proposal (land | retire) is ALLOWED
# only when (a) it carries a backup_hash that matches the sha256 of the REAL
# file at backup_artifact_path, re-hashed fresh every call, AND (b) that
# same real backup content matches the entry's OWN, INDEPENDENTLY
# re-derived LIVE dirty content, re-hashed fresh every call via
# resolve_live_dirty_state() -- never a destructive proposal with no
# verifiable backup, and never one whose backup is stale relative to what
# is ACTUALLY live right now. 'keep' (non-destructive) is always ALLOWED
# regardless of backup_hash (section 11.4.201(1) false-positive guard --
# refusing 'keep' for lacking a backup_hash would make the rule "refuse
# everything", proving nothing).
#
# T140 review finding I3 (fixed here): the PRIOR version of this function
# compared the backup file's re-computed hash against `backup_hash` -- a
# value that itself came from hashing that SAME backup file (at inventory
# time). That comparison is circular: it always matched regardless of
# whether the backup was still current, so a diverged/stale backup was
# silently accepted. This version closes that gap by additionally
# comparing the backup's real content against the entry's LIVE dirty
# content (re-derived fresh, never cached, never trusted from an inventory
# document) via resolve_live_dirty_state(), and by refusing to allow a
# worktree with untracked content the tracked-only backup layout cannot
# possibly cover (section 11.4.6: never silently ignored).
# ---------------------------------------------------------------------------
def derive_verdict(action, backup_hash, backup_artifact_path, root, entry_kind=None, entry_id=None, env=None):
    """Returns (verdict, detail) where verdict is 'ALLOWED' or 'REFUSED' and
    detail explains why (section 11.4.201: every refusal names its reason).

    entry_kind/entry_id are used ONLY to independently re-derive the LIVE
    dirty state to compare the backup against (never to look anything else
    up) -- every call site (propose, verify-proposal, selftest) passes them
    so this anti-circularity check applies uniformly everywhere a
    destructive verdict can be minted, per T140 finding I3.

    `env` (T140 Round 8 review finding R8-I2) is `None` for every real
    (non-scratch) call site (propose, verify-proposal) -- unchanged
    behaviour, `resolve_live_dirty_state`/`_run` inherit the caller's own
    ambient environment exactly as before. Only
    `_selftest_golden_good_scratch_check` passes a non-`None`,
    `_sanitized_scratch_env()`-built dict here, so its OWN re-derivation of
    the scratch repo's live dirty state (via `resolve_live_dirty_state` ->
    `list_worktree_entries`/`worktree_dirty_state`) stays fully isolated
    from the parent process's real git environment too -- never only the
    scratch check's OWN direct `_run(...)` calls, since a partially-
    sanitized fix would still leave THIS function's own internal git calls
    silently redirectable."""
    if action not in VALID_ACTIONS:
        return "REFUSED", "unknown action %r (must be one of %s)" % (action, VALID_ACTIONS)
    if action not in DESTRUCTIVE_ACTIONS:
        return "ALLOWED", "'%s' is non-destructive; no backup required" % action
    if not backup_hash or not backup_artifact_path:
        return "REFUSED", "destructive action '%s' has no backup_hash/backup_artifact_path" % action
    full = backup_artifact_path
    if not os.path.isabs(full):
        full = os.path.join(root, backup_artifact_path)
    if not os.path.isfile(full):
        return "REFUSED", "claimed backup_artifact_path %r does not exist on disk" % backup_artifact_path
    # T140 Round 7 review finding R7-I4 (section 11.4.201(11)
    # artifact-usability, fixed here): `os.path.isfile` returning True only
    # proves the path EXISTS and has file-type mode bits -- it says nothing
    # about whether THIS process can actually READ it (e.g. a mode-000 file,
    # or one owned by a different uid, exactly the same class of real-world
    # filesystem-permission gap `cmd_resume_check`'s own `_merkle_over_dir`
    # fix in the sibling `handoff.py` already closes for a different call
    # site). An unreadable-but-existing backup_artifact_path used to crash
    # this tool uncaught (PermissionError, an OSError) with no honest
    # verdict at all. Fail CLOSED instead (section 11.4.101): this backup
    # cannot be independently re-verified, so it is never silently trusted.
    try:
        with open(full, "rb") as fh:
            real_hash = sha256_of_bytes(fh.read())
    except OSError as exc:
        return "REFUSED", ("claimed backup_artifact_path %r exists but could not be read (%s: %s) "
                            "-- this tool cannot independently re-verify a backup it cannot open"
                            % (backup_artifact_path, type(exc).__name__, exc))
    if real_hash != backup_hash:
        return "REFUSED", ("backup_hash %r does not match the real sha256 (%r) of %r -- stale, "
                            "tampered, or wrong hash" % (backup_hash, real_hash, backup_artifact_path))

    # Anti-circularity check (T140 I3): the claimed backup_hash matches the
    # real bytes of the backup file (just proven above) -- but that alone
    # says nothing about whether the backup still covers what is LIVE right
    # now. Re-derive the live state fresh and compare against it, never
    # against backup_hash/real_hash a second time.
    if not entry_kind or not entry_id:
        return "REFUSED", ("cannot independently verify backup coverage: no entry_kind/entry_id was "
                            "supplied to re-derive the live dirty state against")
    # T140 Round 7 review finding R7-I4 (fixed here): `entry_id` reaches this
    # point UNVALIDATED (only checked for truthiness above) and is fed
    # directly into a real `git`/`subprocess.run` argv element by
    # `resolve_live_dirty_state` -> `_run`. An `entry_id` that is a JSON
    # NUMBER (e.g. `1`, truthy) raises an uncaught TypeError from
    # `subprocess.run` ("expected str, bytes or os.PathLike object, not
    # int"); an `entry_id` string containing an embedded NUL byte raises an
    # uncaught ValueError ("embedded null byte") from the SAME call -- both
    # are `fc_common.SAFE_EXCEPTIONS` members, but neither was ever CAUGHT
    # anywhere between here and `main()`'s own pre-Round-7 dispatch, so both
    # crashed uncaught. Fail CLOSED instead (section 11.4.101): this tool
    # cannot re-derive live state for an entry_id it cannot even pass to
    # git, so the backup's coverage is unverifiable -- the SAME REFUSED
    # class `found=False` (a live stash/worktree genuinely absent) already
    # uses immediately below, since both are "cannot confirm this backup
    # still covers something real" facts.
    try:
        live_hash, has_untracked, found = resolve_live_dirty_state(entry_kind, entry_id, root, env=env)
    except fc_common.SAFE_EXCEPTIONS as exc:
        return "REFUSED", ("could not independently re-derive the live dirty state for entry_id "
                            "%r (kind=%s): %s: %s -- entry_id must be a genuine string identifying "
                            "a real stash/worktree; cannot confirm the backup still covers "
                            "anything real" % (entry_id, entry_kind, type(exc).__name__, exc))
    if not found:
        return "REFUSED", ("entry_id %r (%s) no longer resolves to a live stash/worktree -- cannot "
                            "independently verify the backup still covers its content" % (entry_id, entry_kind))
    if entry_kind == "worktree" and has_untracked is not False:
        # has_untracked is True, or None (undeterminable) -- either way the
        # tracked-only backup layout (BACKUP LAYOUT above) cannot possibly
        # cover untracked content, so it is never silently ignored.
        return "REFUSED", ("worktree %r has untracked content (has_untracked=%r) that the tracked-diff-"
                            "only backup at %r cannot cover -- retire refused to avoid losing it"
                            % (entry_id, has_untracked, backup_artifact_path))
    if live_hash != real_hash:
        return "REFUSED", ("backup content at %r (sha256=%r) does NOT match the entry's freshly "
                            "re-derived LIVE dirty content (sha256=%r) -- the backup is stale and no "
                            "longer covers today's live changes" % (backup_artifact_path, real_hash, live_hash))
    return "ALLOWED", ("backup_hash independently re-verified against BOTH the real backup file at %r "
                        "AND the entry's freshly re-derived live dirty content (no untracked content)"
                        % backup_artifact_path)


# ---------------------------------------------------------------------------
# Output assembly (C-002 canonical JSON + body_hash, identical convention to
# closure/reopen_rate.py's own write_report).
# ---------------------------------------------------------------------------
def write_doc(out_path, schema, body, run_meta):
    doc = dict(body)
    doc["schema"] = schema
    doc["body_hash"] = body_hash_of(dict(doc))
    doc["run_meta"] = run_meta
    text = canon(doc) + "\n"
    if out_path:
        out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
        os.makedirs(out_dir, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".custody_sweep.")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
            os.replace(tmp, out_path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    return doc, text


def run_meta():
    return {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}


# ---------------------------------------------------------------------------
# Subcommand: inventory
# ---------------------------------------------------------------------------
def cmd_inventory(a):
    root = resolve_repo_root(a.repo_root)
    backup_root = os.path.abspath(a.backup_root) if a.backup_root else \
        os.path.join(root, "qa-results", "agent_custody_20260926")

    stash_raw = list_stash_entries(root)
    stash_entries = [build_stash_entry(root, backup_root, e["ref"], e["message"]) for e in stash_raw]

    wt_raw = list_worktree_entries(root)
    wt_entries = [build_worktree_entry(root, backup_root, w) for w in wt_raw]

    entries = stash_entries + wt_entries
    body = {
        "repo_root": root,
        "backup_root": backup_root,
        "entries": entries,
        "counts": {
            "stash": len(stash_entries),
            "worktree": len(wt_entries),
            "with_verified_backup": sum(1 for e in entries if e.get("existing_backup")),
        },
    }
    # T140 Round 6 review finding R6-I2's sibling fix applied here too
    # (section 11.4.227 reuse-not-reinvention, section 11.4.250 -- written
    # defensively for the SAME class of finding Round 6 found in this
    # SAME orchestration/ directory's sibling `write_class_doc_atomic`
    # call sites, rather than waiting for a future round to independently
    # rediscover it here): an unwritable --out path (parent directory
    # missing/not writable/a permissions error) used to crash this
    # subcommand uncaught with no honest verdict at all.
    try:
        doc, text = write_doc(a.out, SCHEMA_INVENTORY, body, run_meta())
    except OSError as exc:
        _safe_print("custody_sweep inventory: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    _safe_print(text.rstrip("\n") if not a.out else
          "custody_sweep inventory: %d stash + %d worktree entries -> %s"
          % (len(stash_entries), len(wt_entries), a.out))
    return 0


# ---------------------------------------------------------------------------
# Subcommand: propose
# ---------------------------------------------------------------------------
def propose_action_for(entry, root):
    backup = entry.get("existing_backup")
    if not backup:
        return "keep"
    # T140 Round 7 review finding R7-I3 (fixed here): was `entry["entry_kind"]`
    # (direct indexing) -- an entry with a truthy `existing_backup` but no
    # `entry_kind` key at all raised an uncaught KeyError. `.get()` instead
    # yields None for a genuinely missing key, and `derive_verdict`'s own
    # pre-existing "cannot independently verify backup coverage: no
    # entry_kind/entry_id was supplied" REFUSED branch already handles that
    # safely and diagnosably -- no new validation code needed, this is the
    # SAME safe-reversible default (section 11.4.101) every other malformed-
    # field case in this tool already resolves to.
    verdict, _detail = derive_verdict(
        "retire" if entry.get("entry_kind") == "worktree" else "land",
        backup.get("backup_hash"), backup.get("backup_artifact_path"), root,
        entry_kind=entry.get("entry_kind"), entry_id=entry.get("entry_id"),
    )
    if verdict != "ALLOWED":
        # A stale/unverifiable backup record is treated exactly like no
        # backup at all -- the safe-reversible default (section 11.4.101)
        # still wins.
        return "keep"
    return "retire" if entry["entry_kind"] == "worktree" else "land"


def _validate_propose_entries_shape(entries):
    """T140 Round 7 review finding R7-I3 (section 11.4.250 heuristic-tower/
    primitive-defect, section 11.4.227 reuse-the-SAME-discipline): `propose`
    used to index every `entries[i]`/`existing_backup`/`backup_*` field
    without first confirming its JSON shape -- a non-dict entry (`entry.get`
    -> AttributeError), a non-dict `existing_backup` (same), or a
    non-string `backup_artifact_path`/`backup_hash` (the EXACT R6-I3(2)
    crash class `cmd_verify_proposal` already closes for `--proposal`, but
    that Round 6 fix never reached `--inventory`'s own `entries` array --
    its docstring even claims elsewhere, in `limit_class.py`, that this
    function "ALREADY handles equivalent malformed inputs cleanly", which
    was true for `--proposal` but was NEVER checked against `--inventory`)
    crashed `propose_action_for()`/`derive_verdict()` uncaught. Mirrors
    `cmd_verify_proposal`'s own field-shape checks (see its "T140 Round 6
    review finding R6-I3" comment) -- applied per-entry here since
    `--inventory` carries a LIST of entries rather than one proposal.

    Also closes a SIBLING crash `cmd_verify_proposal` never had:
    `propose_action_for` used to index `entry["entry_kind"]` directly
    (never `.get()`) whenever `existing_backup` was truthy, so an entry
    with a real backup but no `entry_kind` key at all raised an uncaught
    `KeyError`. Fixed at the call site itself (`propose_action_for` below,
    `entry.get("entry_kind")` in place of `entry["entry_kind"]`) rather
    than here, because `derive_verdict`'s OWN existing "cannot
    independently verify backup coverage: no entry_kind/entry_id was
    supplied" REFUSED branch already handles `entry_kind=None` safely and
    diagnosably -- no NEW validation code is needed for that specific
    field's ABSENCE, only its type when PRESENT (checked below, alongside
    every other field this function guards).

    Returns a diagnosable message (naming the bad entry/field + expected
    type + actual type/value) if any `entries[i]` has a malformed shape, or
    None if every entry is well-formed enough for `propose_action_for`/
    `derive_verdict` to safely index into (a MISSING field is left to the
    existing `.get()`-based honest-absence handling throughout this file,
    exactly as before -- this function checks TYPE, never PRESENCE, matching
    `limit_class.py`'s own `_validate_placement_fixture_shape` convention)."""
    for i, entry in enumerate(entries):
        if not isinstance(entry, dict):
            return "entries[%d] is not a JSON object (got %s: %r)" % (i, type(entry).__name__, entry)
        entry_kind = entry.get("entry_kind")
        if entry_kind is not None and not isinstance(entry_kind, str):
            return "entries[%d].entry_kind must be a JSON string when present (got %s: %r)" % (
                i, type(entry_kind).__name__, entry_kind)
        backup = entry.get("existing_backup")
        if backup is not None and not isinstance(backup, dict):
            return "entries[%d].existing_backup must be a JSON object when present (got %s: %r)" % (
                i, type(backup).__name__, backup)
        if isinstance(backup, dict):
            for field_name in ("backup_hash", "backup_artifact_path"):
                field_val = backup.get(field_name)
                if field_val is not None and not isinstance(field_val, str):
                    return ("entries[%d].existing_backup.%s must be a JSON string when present "
                            "(got %s: %r) -- this tool cannot re-hash or resolve a filesystem "
                            "path from a non-string value") % (
                                i, field_name, type(field_val).__name__, field_val)
    return None


def cmd_propose(a):
    root = resolve_repo_root(a.repo_root)
    try:
        # T140 Round 7 review finding R7-I3 (fixed here): the `open()` call
        # itself used to sit OUTSIDE any try block -- a missing --inventory
        # file crashed uncaught (FileNotFoundError, an OSError) before the
        # already-existing `strict_loads` try/except (which only wrapped the
        # PARSE step) ever ran. Both the open AND the parse are now inside
        # ONE try, and the except clause is widened from `ValueError` alone
        # to `(OSError, ValueError)` -- never narrowed, every case the
        # previous `ValueError`-only clause caught is still caught.
        with open(a.inventory, encoding="utf-8") as fh:
            # T140 Round 6 review finding R6-I1(b)'s sibling fix applied
            # here too (section 11.4.227 reuse-not-reinvention):
            # `fc_common.strict_loads`, never plain `json.load`, so a
            # non-finite JSON constant anywhere in --inventory is refused
            # here at parse time.
            inv = fc_common.strict_loads(fh.read())
    except (OSError, ValueError) as exc:
        _safe_print("custody_sweep propose: --inventory %r unreadable or not valid JSON: %s" % (a.inventory, exc),
              file=sys.stderr)
        return 2

    # T140 Round 7 review finding R7-I3 (fixed here): a non-dict top-level
    # --inventory value (e.g. a bare JSON list, int, or null) used to crash
    # `inv.get("entries")` immediately below UNCAUGHT with a bare
    # `AttributeError` -- a class fc_common.SAFE_EXCEPTIONS does NOT cover
    # (deliberately: it is TypeError/ValueError/OSError/OverflowError only,
    # never AttributeError, per fc_common.py's own module docstring), so
    # even the new top-level dispatch boundary in main() below would NOT
    # have caught this one -- it must be fixed at the SOURCE, exactly like
    # `cmd_verify_proposal`'s own pre-existing `isinstance(d, dict)` guard
    # (its "T140 Round 6 review finding R6-I3" comment).
    if not isinstance(inv, dict):
        _safe_print("custody_sweep propose: --inventory %r top-level value is not a JSON object "
              "(got %s: %r)" % (a.inventory, type(inv).__name__, inv), file=sys.stderr)
        return 2

    entries = inv.get("entries")
    if entries is None:
        _safe_print("custody_sweep propose: --inventory %r has no 'entries' array" % a.inventory, file=sys.stderr)
        return 2
    # T140 Round 7 review finding R7-I3 (fixed here): a non-list `entries`
    # value (e.g. a bare string or object) used to crash the `for entry in
    # entries:` loop below -- iterating a string silently walks it
    # character-by-character (the SAME fail-OPEN class section 11.4.201(6)
    # names elsewhere in this tree, never a crash but a WORSE, silent
    # wrong-answer), and iterating a non-iterable value (int/bool/null)
    # raises an uncaught TypeError. Fail CLOSED with a diagnosable message
    # instead, naming the real type.
    if not isinstance(entries, list):
        _safe_print("custody_sweep propose: --inventory %r field 'entries' must be a JSON list "
              "(got %s: %r)" % (a.inventory, type(entries).__name__, entries), file=sys.stderr)
        return 2

    shape_error = _validate_propose_entries_shape(entries)
    if shape_error is not None:
        _safe_print("custody_sweep propose: --inventory %r has a malformed entry: %s"
              % (a.inventory, shape_error), file=sys.stderr)
        return 2

    proposals = []
    for entry in entries:
        action = propose_action_for(entry, root)
        backup = entry.get("existing_backup") or {}
        backup_hash = backup.get("backup_hash") if action in DESTRUCTIVE_ACTIONS else None
        backup_path = backup.get("backup_artifact_path") if action in DESTRUCTIVE_ACTIONS else None
        verdict, detail = derive_verdict(action, backup_hash, backup_path, root,
                                          entry_kind=entry.get("entry_kind"), entry_id=entry.get("entry_id"))
        proposals.append({
            "entry_kind": entry.get("entry_kind"),
            "entry_id": entry.get("entry_id"),
            "owner_item": entry.get("owner_item"),
            "action": action,
            "backup_hash": backup_hash,
            "backup_artifact_path": backup_path,
            "verdict": verdict,
            "verdict_detail": detail,
        })

    body = {
        "repo_root": root,
        "source_inventory": os.path.abspath(a.inventory),
        "proposals": proposals,
        "counts": {
            "total": len(proposals),
            "keep": sum(1 for p in proposals if p["action"] == "keep"),
            "land": sum(1 for p in proposals if p["action"] == "land"),
            "retire": sum(1 for p in proposals if p["action"] == "retire"),
            "allowed": sum(1 for p in proposals if p["verdict"] == "ALLOWED"),
            "refused": sum(1 for p in proposals if p["verdict"] == "REFUSED"),
        },
        "note": "propose-only -- this document is never auto-applied; turning any proposal "
                "into a real git mutation requires a separate, explicit, operator-confirmed step "
                "this tool does not implement (no --apply flag exists on custody_sweep.py).",
    }
    # T140 Round 6 review finding R6-I2's sibling fix applied here too --
    # see cmd_inventory's own identical comment above.
    try:
        doc, text = write_doc(a.out, SCHEMA_PROPOSE, body, run_meta())
    except OSError as exc:
        _safe_print("custody_sweep propose: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    _safe_print(text.rstrip("\n") if not a.out else
          "custody_sweep propose: %d proposal(s) (%d allowed, %d refused) -> %s"
          % (len(proposals), body["counts"]["allowed"], body["counts"]["refused"], a.out))
    return 0


# ---------------------------------------------------------------------------
# Subcommand: verify-proposal
# ---------------------------------------------------------------------------
REQUIRED_PROPOSAL_KEYS = ("entry_kind", "entry_id", "action")


def cmd_verify_proposal(a):
    try:
        root = resolve_repo_root(a.repo_root)
    except RuntimeError as exc:
        _safe_print("custody_sweep verify-proposal: %s" % exc, file=sys.stderr)
        return 2

    try:
        with open(a.proposal, encoding="utf-8") as fh:
            # T140 Round 6 review finding R6-I1(b)'s sibling fix applied
            # here too (section 11.4.227 reuse-not-reinvention):
            # `fc_common.strict_loads`, never plain `json.load`, so a
            # non-finite JSON constant anywhere in --proposal is refused
            # HERE, at parse time. `strict_loads` raises a plain `ValueError`
            # (never `json.JSONDecodeError` specifically) on ANY parse
            # failure including a non-finite constant, so the except clause
            # below is widened from `json.JSONDecodeError` to `ValueError`
            # (json.JSONDecodeError is itself a ValueError subclass, so
            # every case the narrower clause already caught is still caught
            # -- this widens, never narrows, what is handled).
            d = fc_common.strict_loads(fh.read())
    except (OSError, ValueError) as exc:
        _safe_print("custody_sweep verify-proposal: --proposal %r unreadable or not valid JSON: %s"
              % (a.proposal, exc), file=sys.stderr)
        return 2

    # T140 Round 6 review finding R6-I3 (section 11.4.250, fixed here): a
    # PRIOR round's docstring elsewhere in this tree (limit_class.py's own
    # `_validate_placement_fixture_shape`, discussing R5-I3) incorrectly
    # claimed this function "ALREADY handles equivalent malformed inputs
    # cleanly" -- it did NOT. A --proposal top-level JSON value that is not
    # an object (e.g. the bare int `5`, or `null`) used to crash this
    # function uncaught at `k not in d` below (`TypeError: argument of type
    # 'int' is not iterable`) -- an uncaught crash whose default Python exit
    # code (1) is INDISTINGUISHABLE from this tool's own REFUSED/finding
    # exit code (1, module docstring "Exit codes"), and which `main()`'s own
    # `except RuntimeError` catch (this is a bare TypeError, not a
    # RuntimeError) does not catch either. Fail CLOSED here instead, BEFORE
    # the `missing`-keys membership check below is ever reached, with the
    # SAME diagnosable EXIT_USAGE(2) convention every other malformed-
    # --proposal case in this function already uses.
    if not isinstance(d, dict):
        _safe_print("custody_sweep verify-proposal: --proposal %r top-level value is not a JSON "
              "object (got %s: %r)" % (a.proposal, type(d).__name__, d), file=sys.stderr)
        return 2

    missing = [k for k in REQUIRED_PROPOSAL_KEYS if k not in d]
    if missing:
        _safe_print("custody_sweep verify-proposal: --proposal %r missing required key(s): %s"
              % (a.proposal, ", ".join(missing)), file=sys.stderr)
        return 2

    action = d["action"]
    backup_hash = d.get("backup_hash")
    backup_artifact_path = d.get("backup_artifact_path")
    # T140 Round 6 review finding R6-I3, second half (fixed here): a
    # `backup_artifact_path` that is present but NOT a string (e.g. the
    # JSON list `["a"]`) used to crash `derive_verdict` uncaught
    # (`os.path.isabs()`/`os.path.join()` both require a str/bytes/PathLike
    # argument, never a list) -- exactly the same class of "cannot inspect,
    # therefore cannot confirm safe" gap `limit_class.py`'s own R5-I3/R6-I2
    # fixes already close for their own sibling fields. `backup_hash` is
    # type-checked identically for the same reason, even though this
    # file's own current code path does not itself index into it the way
    # `backup_artifact_path` is used as a path -- section 11.4.6, never
    # assume a field is safe merely because no crash has YET been observed
    # from it.
    for field_name, field_val in (("backup_hash", backup_hash), ("backup_artifact_path", backup_artifact_path)):
        if field_val is not None and not isinstance(field_val, str):
            _safe_print("custody_sweep verify-proposal: --proposal %r field `%s` must be a JSON "
                  "string when present (got %s: %r) -- this tool cannot re-hash or resolve a "
                  "filesystem path from a non-string value" % (
                      a.proposal, field_name, type(field_val).__name__, field_val), file=sys.stderr)
            return 2
    verdict, detail = derive_verdict(action, backup_hash, backup_artifact_path, root,
                                      entry_kind=d.get("entry_kind"), entry_id=d.get("entry_id"))

    disagreement = None
    supplied = d.get("expected_verdict")
    if supplied is not None and supplied != verdict:
        disagreement = ("supplied expected_verdict=%r disagrees with the independently "
                         "computed verdict=%r -- the computed verdict is authoritative, "
                         "the supplied value is never trusted" % (supplied, verdict))

    body = {
        "proposal_path": os.path.abspath(a.proposal),
        "entry_kind": d.get("entry_kind"),
        "entry_id": d.get("entry_id"),
        "action": action,
        "verdict": verdict,
        "verdict_detail": detail,
        "supplied_expected_verdict": supplied,
        "disagreement": disagreement,
    }
    # T140 Round 6 review finding R6-I2's sibling fix applied here too --
    # see cmd_inventory's own identical comment above.
    try:
        doc, text = write_doc(a.out, SCHEMA_VERIFY, body, run_meta())
    except OSError as exc:
        _safe_print("custody_sweep verify-proposal: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    if a.out:
        _safe_print("custody_sweep verify-proposal: %s %s (%s) -> %s"
              % (d.get("entry_id"), verdict, detail, a.out))
    else:
        _safe_print(text.rstrip("\n"))
    if disagreement:
        _safe_print("custody_sweep verify-proposal: WARNING: %s" % disagreement, file=sys.stderr)
        return 1
    return 0 if verdict == "ALLOWED" else 1


# ---------------------------------------------------------------------------
# Subcommand: selftest (C-005 self-validation triple, read-only against
# T129's own already-committed fixtures under
# tests/fixtures/custody_sweep/ -- this tool only READS those files, it
# never edits/owns them; per this file's own EVIDENCE/producer!=verifier
# note above, this is expected reuse of the C-005 fixture set T129 already
# built, not a coupling to the RED test's own separate derive_verdict
# implementation).
# ---------------------------------------------------------------------------
SELFTEST_FIXTURES = (
    ("proposal_golden_bad_no_hash.json", "REFUSED"),
    ("proposal_golden_bad_wrong_hash.json", "REFUSED"),
    ("proposal_golden_bad_stash5_no_backup.json", "REFUSED"),
    ("proposal_golden_good_verified_hash.json", "ALLOWED"),
    ("proposal_negctrl_keep_no_hash.json", "ALLOWED"),
)


def _selftest_golden_good_scratch_check():
    """T140 Round 7 review finding R7-I6 (section 11.4.6/11.4.201(6),
    fixed here): the checked-in golden-good fixture
    `proposal_golden_good_verified_hash.json` names a REAL worktree
    (`entry_id: "a17eb3df7db2f148a"`) that existed in THIS repo at
    fixture-authoring time and was later legitimately removed (backed up,
    verified, operator-authorized) during a disk-space emergency cleanup
    this same session -- so that fixture's own `entry_kind=worktree` +
    `entry_id` combination no longer resolves via `list_worktree_entries`,
    and `derive_verdict`'s own anti-circularity check (T140 finding I3)
    correctly, HONESTLY refuses a backup whose entry no longer exists live
    -- exactly the behaviour that check exists to enforce. The fixture
    being refused is therefore not a defect in `derive_verdict` at all; it
    is `cmd_selftest`'s OWN self-validation being BLINDED by incidental
    host state it should never have depended on in the first place (a
    `found=False` here is a section 11.4.201(6) FALSE-NULL when read as
    "the golden-good case genuinely fails" -- it really means "the
    fixture's chosen entry_id happens not to exist right now", a fact
    about THIS host's git state, not about `derive_verdict`'s own
    correctness).

    Fix (per T140 Round 7 review's own suggested direction): construct a
    throwaway, fully SELF-CONTAINED scratch git repository at test time --
    a real `git init`, a real committed file, a real dirty modification
    producing a real `git diff HEAD` patch, and a real backup file on disk
    whose bytes are IDENTICAL to that live patch -- so this check proves
    the exact SAME property the checked-in fixture's own `reason` field
    documents ("a destructive retire proposal for a real, currently-live
    worktree with a verified backup that matches BOTH the real backup
    file's content AND the entry's live dirty content is ALLOWED")
    WITHOUT depending on any specific real worktree existing in whichever
    project repo this tool happens to be run against. Never touches this
    project's OWN worktrees/stashes/locks (section 11.4.176/11.4.192
    git-lock contention discipline) -- the scratch repo is entirely
    separate, created and torn down inside one
    `tempfile.TemporaryDirectory()`; `commit.gpgsign`/`core.hooksPath` are
    explicitly disabled on the scratch repo's own local config so a global
    signing/hook configuration on the HOST (never this repo's own, which a
    fresh `git init` does not inherit) cannot make this selftest hang
    waiting on a passphrase prompt or run an unrelated hook.

    Returns (verdict, detail) exactly like `derive_verdict` itself, so the
    caller (`cmd_selftest`) applies the IDENTICAL pass/fail comparison it
    already applies to every other `SELFTEST_FIXTURES` entry.

    T140 Round 8 review finding R8-I2 (section 11.4.201/11.4.6, fixed
    here): every git call this function makes -- its own direct
    `_run(...)` calls below AND `worktree_dirty_state`'s AND
    `derive_verdict`'s own internal `resolve_live_dirty_state` ->
    `list_worktree_entries`/`worktree_dirty_state` re-derivation -- now
    passes the SAME `_sanitized_scratch_env()`-built environment, so this
    scratch repo is fully isolated from whatever `GIT_DIR`/`GIT_WORK_TREE`/
    etc. the CALLING process happens to have set (the normal case when
    this tool runs from inside a real git hook). Live-reproduced before
    this fix: a `GIT_DIR` inherited from the caller silently redirected
    EVERY one of this function's own `-C <scratch_repo>` calls onto an
    unrelated victim repository instead (git honours an explicit `GIT_DIR`
    over `-C`'s cwd-style redirection) -- mutating that victim's own
    `.git/config` (`core.hooksPath`, `user.email`/`user.name`,
    `commit.gpgsign`) and, in the SAME run, making this selftest wrongly
    FAIL its own golden-good case (the scratch repo's `git add`/`commit`
    themselves landed on the wrong repository and either failed outright
    or silently diverged, and `derive_verdict`'s own internal
    re-derivation likewise queried the wrong repository's worktree list).
    A caller with NO such variables set is entirely unaffected (a
    freshly-stripped environment identical in substance to the one it
    already had)."""
    scratch_env = _sanitized_scratch_env()
    with tempfile.TemporaryDirectory() as tmp:
        # The backup file lives OUTSIDE the scratch git repo directory
        # (a sibling of it, both inside `tmp`) -- deliberately: a backup
        # file written INSIDE the repo directory itself would show up as a
        # genuine untracked file in `git status`, tripping derive_verdict's
        # OWN (correct) "worktree has untracked content the tracked-diff-
        # only backup cannot cover" REFUSED branch the moment this
        # function's own second, internal `resolve_live_dirty_state` re-
        # derives live state -- a self-inflicted false REFUSED this fix
        # measured live while authoring it, never assumed away.
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        try:
            _run(["git", "init", "--quiet", repo], check=True, env=scratch_env)
            _run(["git", "-C", repo, "config", "commit.gpgsign", "false"], check=True, env=scratch_env)
            _run(["git", "-C", repo, "config", "core.hooksPath", ""], check=False, env=scratch_env)
            _run(["git", "-C", repo, "config", "user.email", "custody-sweep-selftest@example.invalid"],
                 check=True, env=scratch_env)
            _run(["git", "-C", repo, "config", "user.name", "custody_sweep selftest"],
                 check=True, env=scratch_env)
            tracked = os.path.join(repo, "tracked.txt")
            with open(tracked, "w", encoding="utf-8") as fh:
                fh.write("baseline content\n")
            _run(["git", "-C", repo, "add", "tracked.txt"], check=True, env=scratch_env)
            _run(["git", "-C", repo, "commit", "--quiet", "-m", "selftest baseline"],
                 check=True, env=scratch_env)
            with open(tracked, "w", encoding="utf-8") as fh:
                fh.write("baseline content\nlive dirty edit\n")
            dirty_state, diff_text = worktree_dirty_state(repo, env=scratch_env)
        except (OSError, RuntimeError) as exc:
            return "REFUSED", ("scratch selftest setup raised %s: %s -- an internal setup failure is "
                                "never silently read as ALLOWED") % (type(exc).__name__, exc)
        if dirty_state.get("status") != "dirty" or not diff_text:
            return "REFUSED", ("scratch selftest setup failed to produce a dirty worktree (status=%r) "
                                "-- an internal setup failure is never silently read as ALLOWED"
                                % dirty_state.get("status"))
        backup_path = os.path.join(tmp, "backup.patch")
        with open(backup_path, "w", encoding="utf-8") as fh:
            fh.write(diff_text)
        with open(backup_path, "rb") as fh:
            backup_hash = sha256_of_bytes(fh.read())
        entry_id = worktree_entry_id(repo, repo)  # repo is its own repo-root -> "MAIN"
        return derive_verdict("retire", backup_hash, backup_path, repo,
                               entry_kind="worktree", entry_id=entry_id, env=scratch_env)


def cmd_selftest(a):
    root = resolve_repo_root(a.repo_root)
    fixdir = a.fixtures_dir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "custody_sweep")
    fixdir = os.path.abspath(fixdir)

    # Control needle first (section 11.4.273 / C-004): a known-present
    # fixture file must resolve before any absence below is trusted.
    known_present = os.path.join(fixdir, SELFTEST_FIXTURES[0][0])
    if not os.path.isfile(known_present):
        _safe_print("custody_sweep selftest: control needle FAILED -- known-present fixture "
              "%r does not resolve; fixtures_dir may be wrong" % known_present, file=sys.stderr)
        return 3
    fabricated = os.path.join(fixdir, "definitely_never_shipped_fixture_xyz.json")
    if os.path.isfile(fabricated):
        _safe_print("custody_sweep selftest: control needle FAILED -- a fabricated fixture name "
              "unexpectedly exists; the fixtures_dir is not what this tool expects", file=sys.stderr)
        return 3
    _safe_print("custody_sweep selftest: control needle OK (known-present resolves, fabricated absent)")

    ok = True
    for fname, expected in SELFTEST_FIXTURES:
        fpath = os.path.join(fixdir, fname)
        if not os.path.isfile(fpath):
            _safe_print("custody_sweep selftest: fixture %r is MISSING" % fpath, file=sys.stderr)
            ok = False
            continue
        with open(fpath, encoding="utf-8") as fh:
            d = json.load(fh)
        if fname == "proposal_golden_good_verified_hash.json":
            # T140 Round 7 review finding R7-I6 (see
            # _selftest_golden_good_scratch_check's own docstring above):
            # this ONE fixture's own checked-in entry_id no longer
            # resolves to a real, currently-live worktree in `root` -- the
            # fixture's FIELDS are read above (for the "fixture is MISSING"
            # sanity check + the file being valid JSON), but the actual
            # verdict this ONE case checks is derived from a fully
            # self-contained scratch repo instead, never from `d`'s own
            # `entry_id`/`backup_hash`/`backup_artifact_path` values.
            verdict, detail = _selftest_golden_good_scratch_check()
        else:
            verdict, detail = derive_verdict(d["action"], d.get("backup_hash"), d.get("backup_artifact_path"), root,
                                              entry_kind=d.get("entry_kind"), entry_id=d.get("entry_id"))
        if verdict == expected:
            _safe_print("custody_sweep selftest: ok %s -> %s (%s)" % (fname, verdict, detail))
        else:
            _safe_print("custody_sweep selftest: NOT ok %s -> %s, expected %s (%s)"
                  % (fname, verdict, expected, detail), file=sys.stderr)
            ok = False

    if not ok:
        return 3

    # Discrimination needle (section 11.4.107(10) / 11.4.201(1)): the
    # REFUSED-expected and ALLOWED-expected fixtures must genuinely diverge.
    refused = {f for f, e in SELFTEST_FIXTURES if e == "REFUSED"}
    allowed = {f for f, e in SELFTEST_FIXTURES if e == "ALLOWED"}
    if not refused or not allowed:
        _safe_print("custody_sweep selftest: discrimination needle FAILED -- fixture set has no "
              "both-sides coverage", file=sys.stderr)
        return 3
    _safe_print("custody_sweep selftest: ALL %d fixture(s) resolved correctly; REFUSED/ALLOWED genuinely "
          "diverge (%d vs %d)" % (len(SELFTEST_FIXTURES), len(refused), len(allowed)))
    return 0


# ---------------------------------------------------------------------------
# --determinism-check (C-003): re-invoke this SAME process twice with the
# same argv (minus the flag) and compare body_hash.
# ---------------------------------------------------------------------------
def run_determinism_check(argv, timeout_s=120):
    inner = [a for a in argv if a != "--determinism-check"]
    runs = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in (1, 2):
            out_i = os.path.join(tmp, "run%d.json" % i)
            cmd = [sys.executable, os.path.abspath(__file__)] + inner + ["--out", out_i]
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                _safe_print("custody_sweep: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (0, 1) or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                _safe_print("custody_sweep: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                runs.append(json.load(fh).get("body_hash"))
    if runs[0] is None or runs[0] != runs[1]:
        _safe_print("custody_sweep: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    _safe_print("custody_sweep: deterministic (body_hash=%s)" % runs[0])
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    # T140 Round 9b review finding R9b-I1 (fixed here): `__doc__` is `None`
    # under `python -OO`/`PYTHONOPTIMIZE=2` -- `__doc__.split(...)` raised
    # an uncaught `AttributeError` HERE, before ANY of this function's own
    # subparsers were built, escaping `main()` entirely (see `main()`'s
    # own boundary widening below for the defense-in-depth half of this
    # same fix). `(__doc__ or "")` makes this call site simply never
    # crash, matching `handoff.py`'s/`limit_class.py`'s own identical
    # sibling fix.
    p = argparse.ArgumentParser(prog="custody_sweep.py", description=(__doc__ or "").split("\n\n")[0])
    p.add_argument("--determinism-check", action="store_true",
                   help="re-invoke this same subcommand twice and compare body_hash (C-003)")
    sub = p.add_subparsers(dest="subcommand")

    inv = sub.add_parser("inventory")
    inv.add_argument("--repo-root")
    inv.add_argument("--backup-root")
    inv.add_argument("--out")

    prop = sub.add_parser("propose")
    prop.add_argument("--inventory", required=True)
    prop.add_argument("--repo-root")
    prop.add_argument("--out")

    ver = sub.add_parser("verify-proposal")
    ver.add_argument("--proposal", required=True)
    ver.add_argument("--repo-root")
    ver.add_argument("--out")

    st = sub.add_parser("selftest")
    st.add_argument("--repo-root")
    st.add_argument("--fixtures-dir")

    return p


SCHEMA_INTERNAL_ERROR = "custody-sweep-internal-error/v1"


def _write_dispatch_internal_error_doc(out_path, subcommand, exc):
    """T140 Round 7 review (section 11.4.250 heuristic-tower/primitive-
    defect -- "This is the 7th round of the same class... The shared
    helper was only applied where earlier reviewers pointed. No tool has
    a single fail-closed boundary around its whole dispatch. Fix ONE
    boundary, not one crash site at a time"): on ANY exception escaping a
    subcommand handler and being caught by main()'s dispatch boundary
    below, this tool MUST still write SOME verdict/output document to
    --out (when one was requested) rather than leaving a stale or
    entirely absent --out file -- the audit trail (section 11.4.5/11.4.69)
    is never silently lost regardless of what crashed. Best-effort: an
    --out write failure here is itself swallowed (never raised a second
    time out of an already-failing error path) -- the caller's stderr
    diagnostic in main() is what remains authoritative in that
    doubly-unlucky case.

    T140 Round 8 review finding R8-I1(d) (fixed here): was `except
    OSError` alone -- inconsistent with `limit_class.py`'s own sibling
    helper (which already caught the shared `fc_common.SAFE_EXCEPTIONS`
    tuple) and, more importantly, still narrower than the write itself can
    raise (`write_doc`'s own `json.dumps(..., sort_keys=True)` can raise
    `TypeError` on a mutually-incomparable-keys `body`, exactly the class
    R8-I1's own widened dispatch boundary below now exists to catch for
    every OTHER site in this file). Widened to bare `Exception` -- the
    SAME widening `main()`'s own dispatch boundary below receives, so this
    best-effort write-of-a-minimal-error-doc can never itself raise a
    second, different uncaught exception out of an already-failing error
    path (this call site is unconditionally best-effort by its own
    docstring above; a write failure here was always meant to be silently
    absorbed, whatever its exact exception class).

    T140 Round 9/9b review (fixed here): signature changed from `(a,
    subcommand, exc)` (the whole `args` namespace) to `(out_path,
    subcommand, exc)` -- matching `handoff.py`'s/`limit_class.py`'s own
    sibling helpers exactly (section 11.4.227 reuse-the-SAME-discipline)
    -- because `main()`'s own boundary below now also has to cover the
    case where `args` was NEVER successfully parsed (a crash in
    `build_arg_parser()`/`parse_args()` itself), so the caller resolves
    `out_path` honestly (from `args.out` when available, else a raw-argv
    scan) BEFORE calling this function, rather than this function
    assuming an `args`-like object with a `.out` attribute always exists.
    `str(exc)` also replaced with `_safe_str(exc)` (R9-M1)."""
    if not out_path:
        return
    body = {
        "subcommand": subcommand,
        "internal_error": {"class": type(exc).__name__, "detail": _safe_str(exc)},
    }
    try:
        write_doc(out_path, SCHEMA_INTERNAL_ERROR, body, run_meta())
    except Exception:
        pass


def main(argv):
    if "--determinism-check" in argv:
        # T140 Round 8 review finding R8-I1 minor (a) (fixed here):
        # `run_determinism_check` used to run entirely OUTSIDE this
        # function's own dispatch boundary (it re-invokes THIS SAME
        # script as a subprocess, whose own child-process `main()` call is
        # already protected by the boundary below -- but the PARENT
        # invocation's own bookkeeping around those subprocess calls
        # (json.load-ing each child's --out document, comparing body_hash)
        # was not). Wrapped in the SAME bare `except Exception` this
        # function's own subcommand dispatch below now uses (section
        # 11.4.227 reuse-not-reinvention), never `BaseException`, so a
        # genuinely unanticipated crash here still fails closed with a
        # diagnosable message and EXIT_USAGE(2), rather than an uncaught
        # traceback -- there is no single caller-level `--out` document to
        # write an internal-error doc to here (each subprocess run already
        # writes its OWN --out inside a throwaway temp dir, per
        # `run_determinism_check`'s own body), so this boundary is
        # diagnostic-message-only, matching this function's own existing
        # `subprocess.TimeoutExpired`/`rc not in (0, 1)` failure paths
        # immediately inside `run_determinism_check` itself.
        try:
            return run_determinism_check(argv)
        except Exception as exc:
            _safe_print("custody_sweep.py: --determinism-check raised an uncaught %s: %s -- this is a "
                  "genuinely unanticipated case; treat as unsafe/unverified until independently, "
                  "manually re-verified" % (type(exc).__name__, _safe_str(exc)), file=sys.stderr)
            return 2

    # T140 Round 9b review finding R9b-I1 (fixed here, point 3 of that
    # round's own prescription): pre-invalidate any stale --out file
    # BEFORE any computation for this invocation begins, using a raw-argv
    # scan that works even if argument-parser construction/parsing itself
    # (below, now inside the SAME boundary -- point 1) later crashes. See
    # `_invalidate_stale_out`'s own docstring for the full rationale and
    # live repro (live-reproduced HERE too, for THIS tool specifically:
    # `inventory --repo-root /nonexist --out X` with stderr on `/dev/full`
    # used to exit 120 with `--out` never written at all, R9-I1's own
    # fix; a stale PRE-EXISTING `--out` in that same scenario would
    # previously have been left untouched, exactly the R9b-I1 class this
    # pre-invalidation closes).
    _invalidate_stale_out(_scan_argv_for_out(argv))

    args = None
    try:
        # T140 Round 9b review finding R9b-I1 (fixed here, point 1 of that
        # round's own prescription): argument-parser CONSTRUCTION and
        # PARSING now live INSIDE this SAME dispatch boundary, not before
        # it (previously `args = build_arg_parser().parse_args(argv)` sat
        # entirely OUTSIDE any boundary here -- the ONLY one of this
        # file's own three sibling tools missing even a `SystemExit`-only
        # wrapper around it). A crash reaching here from
        # `build_arg_parser()`/`parse_args()` itself (live-proven: the
        # `__doc__.split()` AttributeError under `python -OO`/
        # `PYTHONOPTIMIZE=2`, independently fixed at its own source in
        # `build_arg_parser()` above via `(__doc__ or "")`, point 2) used
        # to escape this function ENTIRELY uncaught with a bare rc=1 and
        # no internal-error document at all -- widened per section
        # 11.4.227 reuse-the-SAME-discipline, matching every other
        # boundary widening in this file's history. `SystemExit`
        # (argparse's own `--help`/usage-error path) is NOT a subclass of
        # `Exception`, so it is unaffected by this widening and still
        # propagates exactly as before (the `except SystemExit: raise`
        # clause immediately below makes this explicit rather than
        # relying on it falling through every `except Exception`/`except
        # RuntimeError` clause unmatched, matching `limit_class.py`'s own
        # sibling convention).
        args = build_arg_parser().parse_args(argv)
        if args.subcommand is None:
            _safe_print("custody_sweep.py: a subcommand is required "
                  "(inventory | propose | verify-proposal | selftest)", file=sys.stderr)
            return 2

        if args.subcommand == "inventory":
            return cmd_inventory(args)
        if args.subcommand == "propose":
            return cmd_propose(args)
        if args.subcommand == "verify-proposal":
            return cmd_verify_proposal(args)
        if args.subcommand == "selftest":
            return cmd_selftest(args)
    except SystemExit:
        raise
    except RuntimeError as exc:
        # T140 Round 8 review finding R8-I1 minor (c) (fixed here): this
        # branch used to write NO --out document at all on a RuntimeError
        # (e.g. `resolve_repo_root`'s own "not inside a git checkout"
        # refusal) -- the audit trail (section 11.4.5/11.4.69) was silently
        # lost for this ONE exception class even though it fails closed
        # with the SAME EXIT_USAGE(2) convention every other error path in
        # this function already uses. `RuntimeError` is deliberately its
        # own, MORE SPECIFIC `except` clause listed BEFORE the broader
        # `except Exception` immediately below -- Python tries handlers in
        # source order, so a `RuntimeError` is always caught HERE first
        # regardless of `RuntimeError` also being an `Exception` subclass
        # -- this branch's own, more specific stderr message (naming just
        # the refusal reason, never "raised an uncaught RuntimeError while
        # dispatching") is preserved unchanged.
        #
        # T140 Round 9/9b review (fixed here): the --out document write
        # now happens BEFORE the diagnostic print (point 4), through
        # `_safe_print` (never able to escape and corrupt an already-
        # written --out doc, or exit 120 on a closed stderr, R9-I1's own
        # fix). `out_path` resolves honestly even in the (currently
        # unreachable for THIS specific except clause, since `args` is
        # always bound by the time a RuntimeError can be raised from the
        # subcommand dispatch above -- but resolved the SAME defensive
        # way as the `except Exception` clause immediately below, for
        # consistency and future-proofing) case `args` is None.
        out_path = getattr(args, "out", None) if args is not None else _scan_argv_for_out(argv)
        subcommand = getattr(args, "subcommand", None) if args is not None else None
        _write_dispatch_internal_error_doc(out_path, subcommand, exc)
        _safe_print("custody_sweep.py: %s" % _safe_str(exc), file=sys.stderr)
        return 2
    except Exception as exc:
        # T140 Round 7 review, the ONE top-level dispatch boundary wrapping
        # EVERY subcommand this file dispatches to (see
        # _write_dispatch_internal_error_doc's own docstring immediately
        # above): a genuinely unanticipated crash reaching here -- one none
        # of R7-I3/R7-I4/R7-I6's own specific, diagnosable fixes above
        # enumerated -- still fails CLOSED with an honest, diagnosable
        # message, a real --out write (when --out was given), and this
        # tool's own established EXIT_USAGE(2) convention, rather than an
        # uncaught crash landing on Python's own default exit code 1
        # (indistinguishable from this tool's REFUSED/finding exit code).
        #
        # T140 Round 8 review finding R8-I1 (WIDENED here): was `except
        # fc_common.SAFE_EXCEPTIONS` -- Round 8's own live fuzzing (5,000
        # random-field-mutation variants) proved this narrower catch set
        # (TypeError/ValueError/OSError/OverflowError) still let
        # `KeyError`/`IndexError`/`AttributeError` escape uncaught in ALL
        # THREE sibling fastcycle orchestration tools, and `RecursionError`
        # escape uncaught in this file's own siblings (`handoff.py`,
        # `limit_class.py`) -- proven live, TWICE independently: (1)
        # reverting this same round's own point-fix in
        # `propose_action_for` (`entry.get(...)` back to
        # `entry["entry_kind"]`) makes `propose` crash with an uncaught
        # `KeyError`; (2) injecting a `KeyError` at the very TOP of
        # `cmd_verify_proposal` (before ANY of ITS own internal
        # try/excepts could run) crashes uncaught here too. Widened to
        # bare `Exception` -- deliberately NEVER `BaseException`:
        # `SystemExit`/`KeyboardInterrupt` are NOT subclasses of
        # `Exception` (Python's own exception hierarchy places both
        # directly under `BaseException`), so an operator interrupt or
        # this process's own `sys.exit()` correctly stays UNCAUGHT here,
        # exactly as before this widening. `fc_common.SAFE_EXCEPTIONS`
        # itself is UNCHANGED (still the narrower, shared floor every
        # sibling tool's own per-site except-clauses OR onto, per its own
        # module docstring) -- only this ONE top-level dispatch boundary
        # is widened, the fix Round 8's own review recommended directly:
        # "the fix is to change what the boundary catches to `Exception`,
        # not to add one more type to the list."
        #
        # T140 Round 9/9b review (fixed here): `out_path`/`subcommand`
        # resolve honestly even when `args` was never successfully parsed
        # (a build_arg_parser()/parse_args() crash) -- falling back to
        # the raw-argv scan / `None` respectively -- and the --out
        # document write now happens BEFORE the diagnostic print (point
        # 4), through `_safe_print` (never able to escape and trigger a
        # SECOND, corrupting boundary re-entry -- a raising print
        # previously escaped `main()` ENTIRELY, past this very except
        # clause, to the interpreter's own top-level uncaught-exception
        # handler, or -- for a closed/full stderr -- exited 120 with the
        # --out document never written at all, R9-I1's own fix).
        out_path = getattr(args, "out", None) if args is not None else _scan_argv_for_out(argv)
        subcommand = getattr(args, "subcommand", None) if args is not None else None
        _write_dispatch_internal_error_doc(out_path, subcommand, exc)
        _safe_print("custody_sweep.py: subcommand %r raised an uncaught %s while dispatching: %s -- this "
              "is a genuinely unanticipated case no individual fix above enumerated; treat as "
              "unsafe/unverified until independently, manually re-verified"
              % (subcommand, type(exc).__name__, _safe_str(exc)), file=sys.stderr)
        return 2

    _safe_print("custody_sweep.py: unknown subcommand %r" % args.subcommand, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
