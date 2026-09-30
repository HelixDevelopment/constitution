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
def _run(args, cwd=None, check=True):
    proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise RuntimeError(
            "command failed (rc=%d): %s\nstderr: %s" % (proc.returncode, " ".join(args), proc.stderr.strip())
        )
    return proc.returncode, proc.stdout, proc.stderr


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


def stash_files_touched(root, ref):
    rc, out, _ = _run(["git", "-C", root, "stash", "show", "-p", ref], check=False)
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


def list_worktree_entries(root):
    rc, out, _ = _run(["git", "-C", root, "worktree", "list", "--porcelain"], check=False)
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


def worktree_dirty_state(path):
    rc, status_out, _ = _run(["git", "-C", path, "status", "--porcelain=v1"], check=False)
    if rc != 0:
        return {"status": "UNMEASURED", "sha256": None, "has_untracked": None}, ""
    if not status_out.strip():
        return {"status": "clean", "sha256": None, "has_untracked": False}, ""
    rc2, diff_out, _ = _run(["git", "-C", path, "diff", "HEAD"], check=False)
    has_untracked = any(line.startswith("?? ") for line in status_out.splitlines())
    if rc2 == 0 and diff_out:
        return {"status": "dirty", "sha256": sha256_of_text(diff_out), "has_untracked": has_untracked}, diff_out
    if has_untracked:
        return {"status": "untracked_only", "sha256": None, "has_untracked": True}, ""
    return {"status": "clean", "sha256": None, "has_untracked": False}, ""


def resolve_live_dirty_state(entry_kind, entry_id, root):
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
        rc, _out, _err = _run(["git", "-C", root, "rev-parse", "--verify", "-q", entry_id], check=False)
        if rc != 0:
            return None, False, False
        _files, patch_text = stash_files_touched(root, entry_id)
        live_hash = sha256_of_text(patch_text) if patch_text else None
        return live_hash, False, True
    if entry_kind == "worktree":
        for wt in list_worktree_entries(root):
            path = wt.get("path")
            if not path:
                continue
            if worktree_entry_id(path, root) != entry_id:
                continue
            if not os.path.isdir(path):
                return None, None, False
            dirty_state, _diff = worktree_dirty_state(path)
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
def derive_verdict(action, backup_hash, backup_artifact_path, root, entry_kind=None, entry_id=None):
    """Returns (verdict, detail) where verdict is 'ALLOWED' or 'REFUSED' and
    detail explains why (section 11.4.201: every refusal names its reason).

    entry_kind/entry_id are used ONLY to independently re-derive the LIVE
    dirty state to compare the backup against (never to look anything else
    up) -- every call site (propose, verify-proposal, selftest) passes them
    so this anti-circularity check applies uniformly everywhere a
    destructive verdict can be minted, per T140 finding I3."""
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
    with open(full, "rb") as fh:
        real_hash = sha256_of_bytes(fh.read())
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
    live_hash, has_untracked, found = resolve_live_dirty_state(entry_kind, entry_id, root)
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
        print("custody_sweep inventory: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    print(text.rstrip("\n") if not a.out else
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
    verdict, _detail = derive_verdict(
        "retire" if entry["entry_kind"] == "worktree" else "land",
        backup.get("backup_hash"), backup.get("backup_artifact_path"), root,
        entry_kind=entry.get("entry_kind"), entry_id=entry.get("entry_id"),
    )
    if verdict != "ALLOWED":
        # A stale/unverifiable backup record is treated exactly like no
        # backup at all -- the safe-reversible default (section 11.4.101)
        # still wins.
        return "keep"
    return "retire" if entry["entry_kind"] == "worktree" else "land"


def cmd_propose(a):
    root = resolve_repo_root(a.repo_root)
    with open(a.inventory, encoding="utf-8") as fh:
        try:
            # T140 Round 6 review finding R6-I1(b)'s sibling fix applied
            # here too (section 11.4.227 reuse-not-reinvention):
            # `fc_common.strict_loads`, never plain `json.load`, so a
            # non-finite JSON constant anywhere in --inventory is refused
            # here at parse time. `strict_loads` raises a plain `ValueError`
            # on any parse failure; `json.JSONDecodeError` is itself a
            # `ValueError` subclass, so the except clause below is widened
            # to `ValueError` (never narrowed -- every case the previous
            # `json.JSONDecodeError`-only clause caught is still caught).
            inv = fc_common.strict_loads(fh.read())
        except ValueError as exc:
            print("custody_sweep propose: --inventory %r is not valid JSON: %s" % (a.inventory, exc),
                  file=sys.stderr)
            return 2
    entries = inv.get("entries")
    if entries is None:
        print("custody_sweep propose: --inventory %r has no 'entries' array" % a.inventory, file=sys.stderr)
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
        print("custody_sweep propose: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    print(text.rstrip("\n") if not a.out else
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
        print("custody_sweep verify-proposal: %s" % exc, file=sys.stderr)
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
        print("custody_sweep verify-proposal: --proposal %r unreadable or not valid JSON: %s"
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
        print("custody_sweep verify-proposal: --proposal %r top-level value is not a JSON "
              "object (got %s: %r)" % (a.proposal, type(d).__name__, d), file=sys.stderr)
        return 2

    missing = [k for k in REQUIRED_PROPOSAL_KEYS if k not in d]
    if missing:
        print("custody_sweep verify-proposal: --proposal %r missing required key(s): %s"
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
            print("custody_sweep verify-proposal: --proposal %r field `%s` must be a JSON "
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
        print("custody_sweep verify-proposal: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    if a.out:
        print("custody_sweep verify-proposal: %s %s (%s) -> %s"
              % (d.get("entry_id"), verdict, detail, a.out))
    else:
        print(text.rstrip("\n"))
    if disagreement:
        print("custody_sweep verify-proposal: WARNING: %s" % disagreement, file=sys.stderr)
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


def cmd_selftest(a):
    root = resolve_repo_root(a.repo_root)
    fixdir = a.fixtures_dir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "custody_sweep")
    fixdir = os.path.abspath(fixdir)

    # Control needle first (section 11.4.273 / C-004): a known-present
    # fixture file must resolve before any absence below is trusted.
    known_present = os.path.join(fixdir, SELFTEST_FIXTURES[0][0])
    if not os.path.isfile(known_present):
        print("custody_sweep selftest: control needle FAILED -- known-present fixture "
              "%r does not resolve; fixtures_dir may be wrong" % known_present, file=sys.stderr)
        return 3
    fabricated = os.path.join(fixdir, "definitely_never_shipped_fixture_xyz.json")
    if os.path.isfile(fabricated):
        print("custody_sweep selftest: control needle FAILED -- a fabricated fixture name "
              "unexpectedly exists; the fixtures_dir is not what this tool expects", file=sys.stderr)
        return 3
    print("custody_sweep selftest: control needle OK (known-present resolves, fabricated absent)")

    ok = True
    for fname, expected in SELFTEST_FIXTURES:
        fpath = os.path.join(fixdir, fname)
        if not os.path.isfile(fpath):
            print("custody_sweep selftest: fixture %r is MISSING" % fpath, file=sys.stderr)
            ok = False
            continue
        with open(fpath, encoding="utf-8") as fh:
            d = json.load(fh)
        verdict, detail = derive_verdict(d["action"], d.get("backup_hash"), d.get("backup_artifact_path"), root,
                                          entry_kind=d.get("entry_kind"), entry_id=d.get("entry_id"))
        if verdict == expected:
            print("custody_sweep selftest: ok %s -> %s (%s)" % (fname, verdict, detail))
        else:
            print("custody_sweep selftest: NOT ok %s -> %s, expected %s (%s)"
                  % (fname, verdict, expected, detail), file=sys.stderr)
            ok = False

    if not ok:
        return 3

    # Discrimination needle (section 11.4.107(10) / 11.4.201(1)): the
    # REFUSED-expected and ALLOWED-expected fixtures must genuinely diverge.
    refused = {f for f, e in SELFTEST_FIXTURES if e == "REFUSED"}
    allowed = {f for f, e in SELFTEST_FIXTURES if e == "ALLOWED"}
    if not refused or not allowed:
        print("custody_sweep selftest: discrimination needle FAILED -- fixture set has no "
              "both-sides coverage", file=sys.stderr)
        return 3
    print("custody_sweep selftest: ALL %d fixture(s) resolved correctly; REFUSED/ALLOWED genuinely "
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
                print("custody_sweep: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (0, 1) or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("custody_sweep: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                runs.append(json.load(fh).get("body_hash"))
    if runs[0] is None or runs[0] != runs[1]:
        print("custody_sweep: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    print("custody_sweep: deterministic (body_hash=%s)" % runs[0])
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="custody_sweep.py", description=__doc__.split("\n\n")[0])
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


def main(argv):
    if "--determinism-check" in argv:
        return run_determinism_check(argv)

    args = build_arg_parser().parse_args(argv)
    if args.subcommand is None:
        print("custody_sweep.py: a subcommand is required "
              "(inventory | propose | verify-proposal | selftest)", file=sys.stderr)
        return 2

    try:
        if args.subcommand == "inventory":
            return cmd_inventory(args)
        if args.subcommand == "propose":
            return cmd_propose(args)
        if args.subcommand == "verify-proposal":
            return cmd_verify_proposal(args)
        if args.subcommand == "selftest":
            return cmd_selftest(args)
    except RuntimeError as exc:
        print("custody_sweep.py: %s" % exc, file=sys.stderr)
        return 2

    print("custody_sweep.py: unknown subcommand %r" % args.subcommand, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
