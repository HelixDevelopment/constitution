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
        - dirty_file_hash: sha256 of the real patch content as RAW BYTES
          (`git stash show -p <CANONICAL_PATCH_OPTS> <ref>` for a stash;
          `git -C <path> diff <CANONICAL_PATCH_OPTS> HEAD` for a worktree
          -- binary-safe, CRLF-preserving; T140 Round 11 finding B1),
          computed FRESH every run -- never cached, never assumed from a
          prior run; plus has_untracked (a stash's `-u` third parent
          counts), dirty_submodules and has_unmerged -- the coverage facts
          `derive_verdict` refuses on
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
  2 usage / configuration error (bad args, unreadable/invalid JSON --
    INCLUDING a missing or unparseable `propose --inventory` document or
    `verify-proposal --proposal` document -- missing required proposal
    fields, unresolvable --repo-root). Check order for `propose`: the repo
    root is resolved FIRST, so outside a git checkout with no --repo-root
    the run fails on that (rc=2, internal-error document) before the
    --inventory file is ever opened -- both paths are rc=2 (T140 Round 13,
    round-12 finding M-3: this table formerly claimed a missing --inventory
    was "BLIND (exit 4)"; the live code and the round-11 regression test
    both return 2, so the table is corrected to the real contract)
  3 self-test failed (`selftest` subcommand only: a control needle did
    not discriminate, or a golden/negative-control fixture resolved to
    the wrong verdict)
  4 `--determinism-check` only: a run produced no honest verdict (it
    timed out, crashed, or wrote no --out). No other subcommand path
    returns 4 today.

CONSUMERS MUST GATE ON THE EXIT CODE, NEVER ON --out's MERE PRESENCE (T140
Round 13, round-12 finding M-2 + adjudication ruling 1): a handled failure
(e.g. an unreadable --proposal / --inventory) deletes a stale regular-file
--out before returning, but a pure argparse usage error (rc=2 -- e.g. a
missing required flag) exits BEFORE the operation is attempted and leaves
whatever was at --out untouched, and a non-regular-file --out (FIFO,
device, symlink) is never deleted. `run_meta` holds only the host name, so
a stale --out is NOT distinguishable from a fresh one by its content. Only
rc=0 means "this run produced this --out and the verdict is ALLOWED";
rc=1 means "this run produced this --out and it contains a finding";
anything else means "do not trust whatever is at --out".

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

RESTORABILITY ORACLE (T140 Round 13, round-12 finding B-1): a land/retire
verdict is ALLOWED only when, after every cheaper check, the backup is
proven to RESTORE the work -- for a worktree, it is applied onto a fresh,
isolated scratch checkout of the worktree's HEAD and EVERY live file
(tracked, untracked AND gitignored; only the top-level `.git` is excluded)
must be byte-identical afterwards, and the index must hold no staged-only
content; for a stash, base + backup must reproduce the stash's own tree and
its `^2` index must hold nothing beyond it. Consequence, stated plainly: a
worktree holding ANY gitignored file (build output, a local `.env`, caches)
or a POPULATED submodule is never retire-ALLOWED, because `git worktree
remove` would delete that content and no patch backup carries it (round-12
finding I-1) -- an operator who has decided such content is disposable must
remove it explicitly first. See the oracle block above `derive_verdict` for
the oracle's own honest boundary.

GIT STATE OUTSIDE THE FILES (T140 Round 15, round-14 findings BLOCKING-1/2,
IMPORTANT-1, MINOR-3): `git worktree remove --force` also deletes the
worktree's per-worktree admin directory (`<common>/worktrees/<id>/`), and
dropping a stash can orphan its base history. A retire is therefore also
REFUSED when that admin directory holds a submodule git dir (`modules/`), a
per-worktree ref, in-progress operation state, any entry this tool does not
recognise, or a reflog/pseudo-ref commit reachable from no shared ref; a land
is REFUSED when the stash's base history is held by nothing but the stash. A
worktree whose reflog still holds commits superseded by amend/reset/rebase is
refused until those are anchored or the reflog is explicitly expired. Every
git call ignores ambient git-redirection variables (GIT_DIR, GIT_INDEX_FILE,
...; IMPORTANT-2) and is bounded by CUSTODY_SWEEP_GIT_TIMEOUT_S (default
1800 s; MINOR-4) -- a timeout refuses, never allows.

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
import fc_entry  # noqa: E402  (T140 Round 10 review: the ONE shared CLI-entry
# primitive -- emit_result/diag channel split, FcArgumentParser, run_cli_main,
# safe_str, scan_argv_for_out, invalidate_stale_out -- see fc_entry.py's own
# module docstring; replaces this file's own former per-tool copies of every
# one of those, section 11.4.227/11.4.251)

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of
diag = fc_entry.diag
emit_result = fc_entry.emit_result
safe_str = fc_entry.safe_str
scan_argv_for_out = fc_entry.scan_argv_for_out
invalidate_stale_out = fc_entry.invalidate_stale_out
FcArgumentParser = fc_entry.FcArgumentParser
run_cli_main = fc_entry.run_cli_main

SCHEMA_INVENTORY = "custody-sweep-inventory/v1"
SCHEMA_PROPOSE = "custody-sweep-propose/v1"
SCHEMA_VERIFY = "custody-sweep-verify/v1"

# ---------------------------------------------------------------------------
# T140 Round 10 independent review (docs/CONTINUATION.md ADDENDUM 114): the
# shared `_real_print`/`_safe_print`/`_safe_str`/`_scan_argv_for_out`/
# `_invalidate_stale_out` helpers this file used to define LOCALLY (Round
# 9/9b) are now imported, ONCE, from `fc_entry.py` above -- see that
# module's own docstring for the full rationale. UNLIKE `handoff.py`/
# `limit_class.py` (where `--out` is always the real deliverable and every
# print is genuinely diagnostic), this file's own `inventory`/`propose`/
# `verify-proposal` print the verdict DOCUMENT ITSELF to stdout as their
# ONLY delivery channel whenever `--out` is omitted -- see T140 Round 10
# review finding B1, fixed at each of those three call sites below via
# `emit_result` (never `diag`).
# ---------------------------------------------------------------------------


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
# T140 Round 15 (round-14 finding IMPORTANT-2, fixed here): git EXPORTS
# GIT_DIR / GIT_INDEX_FILE / GIT_WORK_TREE / ... to every hook it runs, and
# being invoked from inside a hook is this tool's documented NORMAL case. An
# inherited GIT_INDEX_FILE silently redirected the index-divergence check to
# the MAIN checkout's index (reproduced live: staged-only content in a linked
# worktree was REFUSED without the variable and ALLOWED with it -- then lost
# on retire). Every git call this tool makes names its target explicitly
# (`-C <path>`), so NO ambient git-redirection variable is ever legitimate for
# it. Rather than enumerating the (growing) set of redirection variables, the
# environment is built from an ALLOWLIST: every `GIT_*` variable is dropped
# except the ones below, which only choose WHICH user/system config file,
# identity, git binary directory, transport helper or trace sink to use --
# none of them can point a `-C <path>` command at a different repository,
# index, object store, ref namespace, config parameter set or diff shape.
_AMBIENT_GIT_KEEP_EXACT = frozenset((
    "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG_NOSYSTEM", "GIT_EXEC_PATH",
    "GIT_ASKPASS", "GIT_TERMINAL_PROMPT", "GIT_SSH", "GIT_SSH_COMMAND", "GIT_SSH_VARIANT",
))
_AMBIENT_GIT_KEEP_PREFIX = ("GIT_AUTHOR_", "GIT_COMMITTER_", "GIT_TRACE")


def _targeted_git_env(base=None):
    """Returns a NEW environment dict (never mutates `os.environ`) for a git
    command that targets an explicitly named path: `base` (default
    `os.environ`) minus every `GIT_*` variable not on the allowlist above."""
    src = os.environ if base is None else base
    return {k: v for k, v in src.items()
            if not k.startswith("GIT_") or k in _AMBIENT_GIT_KEEP_EXACT
            or k.startswith(_AMBIENT_GIT_KEEP_PREFIX)}


# T140 Round 15 (round-14 finding MINOR-4, fixed here): a hanging smudge/clean
# filter (or a stuck git) used to hang the whole tool forever -- `_run` had no
# timeout. Every git call is now bounded. The child is started in its OWN
# session so a timeout can kill the whole process group (a filter spawned by
# git holds our stdout pipe open; killing only `git` would leave
# `communicate()` blocked on that pipe for the filter's lifetime -- the
# section 11.4.201(12) pipe-inheritance footgun). A timeout is reported as
# rc=124 with a "TIMED OUT" stderr: every caller already treats a non-zero rc
# as "could not look" -> refuse (the one rc-specific caller,
# `_conversion_config`'s rc==1 "no matching key", can never see 124).
_GIT_TIMEOUT_ENV = "CUSTODY_SWEEP_GIT_TIMEOUT_S"
_GIT_TIMEOUT_DEFAULT_S = 1800.0
_TIMEOUT_RC = 124

# T140 Round 17 (round-16 finding MINOR-1): a short, FIXED grace period for
# draining stdout/stderr after the process-group kill above -- deliberately
# NOT derived from `_git_timeout_s()` (which may be the 1800s production
# default) so a surviving orphan can never turn the post-kill drain into a
# second multi-minute wait.
_KILL_DRAIN_GRACE_S = 3.0


def _group_has_survivor(pgid):
    """T140 Round 17 (round-16 finding MINOR-1): section 11.4.201 -- probes
    the REAL kernel state via signal 0, never guesses. True if the process
    group `pgid` still has ANY member alive; False if it is genuinely empty
    (every reachable member already died); None if `pgid` itself is not a
    valid signalable group id (section 11.4.263: never signal a process
    group <= 1). Used ONLY to decide, after a post-kill drain already timed
    out once, whether a surviving pipe-holder is (a) still inside OUR OWN
    process group -- meaning the kill above did not actually do its job, a
    genuine defect that must stay observable as a hang -- or (b) has
    escaped that group entirely (e.g. a filter that called `setsid`), where
    nothing further can be targeted without guessing at an unrelated pid."""
    if not (isinstance(pgid, int) and pgid > 1):
        return None
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # exists but unsignalable by us -- the safe default keeps draining
        # rather than falsely declaring the group clean and abandoning it.
        return True


def _git_timeout_s():
    raw = os.environ.get(_GIT_TIMEOUT_ENV, "")
    try:
        val = float(raw) if raw else _GIT_TIMEOUT_DEFAULT_S
    except ValueError:
        val = _GIT_TIMEOUT_DEFAULT_S
    return val if val > 0 else _GIT_TIMEOUT_DEFAULT_S


def _exec(args, cwd=None, env=None, input_bytes=None):
    """Runs `args` bounded by the git timeout. Returns (rc, stdout_bytes,
    stderr_bytes). `env=None` means `_targeted_git_env()` (IMPORTANT-2): the
    ambient environment minus every git-redirection variable; an explicit
    `env` dict (a scratch-repository env) is used exactly as given."""
    import signal as _signal
    child_env = _targeted_git_env() if env is None else env
    proc = subprocess.Popen(args, cwd=cwd, env=child_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
                            start_new_session=True)
    try:
        out, err = proc.communicate(input=input_bytes, timeout=_git_timeout_s())
        return proc.returncode, out, err
    except subprocess.TimeoutExpired:
        pgid = proc.pid
        # section 11.4.263: never signal a process group <= 1. With
        # start_new_session=True the child leads its own group whose id is
        # its pid; validate it is a real int > 1 before killpg.
        if isinstance(pgid, int) and pgid > 1:
            try:
                os.killpg(pgid, _signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            proc.kill()
        # T140 Round 17 (round-16 finding MINOR-1, fixed here): this second
        # `communicate()` used to have NO timeout. Killing the process
        # GROUP reaps `git` itself, but a smudge/clean filter that escaped
        # the group (e.g. via `setsid`) keeps its OWN dup of our stdout/
        # stderr PIPE write-end open; `communicate()` blocks reading those
        # pipes until EVERY holder of the write end closes it, so an
        # unbounded call here defeated the very timeout it exists to
        # enforce (measured live: ~25s instead of ~3s with a `setsid sleep
        # 25 & cat`-style filter; hangs FOREVER with `sleep infinity`). A
        # short, bounded drain attempt is tried first; if it times out,
        # `_group_has_survivor(pgid)` (signal 0 -- the REAL kernel state,
        # never a guess) tells apart two different causes before deciding
        # what to do next: something STILL alive in OUR OWN process group
        # means the kill above did not actually do its job (a genuine
        # kill-logic defect, e.g. killing only the direct child and not the
        # group) -- that MUST stay observable as a hang, so the ORIGINAL
        # unbounded drain runs for that case. A genuinely EMPTY group means
        # the kill worked and whatever still holds a write end open has
        # ESCAPED it entirely (the `setsid` case) -- nothing further can be
        # targeted without guessing at an unrelated pid (forbidden), so the
        # drain is ABANDONED instead of re-blocking indefinitely -- the
        # TIMED OUT result below is the only thing any caller ever sees
        # either way, so losing already-buffered partial output here is
        # harmless (it still fails toward REFUSED, never ALLOWED: every
        # caller treats a non-zero/124 rc as "could not look" -> refuse).
        try:
            proc.communicate(timeout=_KILL_DRAIN_GRACE_S)
        except subprocess.TimeoutExpired:
            # Reap OUR OWN direct child FIRST (it was already SIGKILLed
            # above, so this does not block): `communicate(timeout=...)`
            # raising TimeoutExpired does NOT itself call `wait()`, so
            # `proc` can still be an un-reaped zombie at this point -- and
            # a zombie answers a signal-0 probe just like a live process
            # (it is still a valid process-table entry until reaped),
            # which would make `_group_has_survivor` see OUR OWN already-
            # dead child as a "survivor" every single time, never reaching
            # the abandon path below.
            try:
                proc.wait(timeout=_KILL_DRAIN_GRACE_S)
            except subprocess.TimeoutExpired:
                pass
            if _group_has_survivor(pgid) is False:
                for pipe in (proc.stdin, proc.stdout, proc.stderr):
                    if pipe is not None:
                        try:
                            pipe.close()
                        except OSError:
                            pass
                try:
                    proc.wait(timeout=_KILL_DRAIN_GRACE_S)
                except subprocess.TimeoutExpired:
                    pass
            else:
                proc.communicate()
        return _TIMEOUT_RC, b"", ("TIMED OUT after %gs (%s=%s): %s"
                                  % (_git_timeout_s(), _GIT_TIMEOUT_ENV, os.environ.get(_GIT_TIMEOUT_ENV, ""),
                                     " ".join(args))).encode("utf-8", "replace")


def _run(args, cwd=None, check=True, env=None):
    """`env=None` (the default) runs with `_targeted_git_env()` -- the
    caller's ambient environment with every git-REDIRECTION variable removed
    (T140 Round 15, round-14 finding IMPORTANT-2; formerly the raw ambient
    environment, which let a hook-exported GIT_INDEX_FILE / GIT_DIR silently
    redirect a `-C <path>` call). `env=<dict>` REPLACES the child's
    environment entirely (never merges with `os.environ`) -- used by the
    scratch-repository call sites (see `_sanitized_scratch_env()` below; T140
    Round 8 review finding R8-I2). Bounded by the git timeout (MINOR-4)."""
    # T140 Round 11 review finding I6 (fixed here): `errors="surrogateescape"`
    # -- a strict text decode (the former default) raised an uncaught
    # UnicodeDecodeError on ANY non-UTF-8 byte in git's output (a stash
    # message, a commit subject, a worktree path), aborting the WHOLE
    # inventory. surrogateescape round-trips every byte losslessly (a path
    # decoded this way is still usable with os.* calls); strings bound for
    # the JSON output are passed through `_json_safe()` before writing.
    # Patch CONTENT is never read through this function at all -- see
    # `_run_bytes()` below (Round 11 finding B1). The universal-newline
    # translation `text=True` used to apply is reproduced explicitly.
    rc, out_b, err_b = _exec(args, cwd=cwd, env=env)

    def _dec(b):
        return b.decode("utf-8", "surrogateescape").replace("\r\n", "\n").replace("\r", "\n")

    out, err = _dec(out_b), _dec(err_b)
    if check and rc != 0:
        raise RuntimeError("command failed (rc=%d): %s\nstderr: %s" % (rc, " ".join(args), err.strip()))
    return rc, out, err


def _run_bytes(args, cwd=None, env=None, input_bytes=None):
    """T140 Round 11 review finding B1 (fixed here): runs a git command and
    returns its stdout as RAW BYTES, never decoded. Every patch whose sha256
    decides a destructive verdict MUST be read through this function: the
    former text-mode read (universal newlines) silently rewrote CRLF to LF,
    so the hash the tool compared against was the hash of a patch that no
    longer applies to the real files (reproduced live: a CR-stripped backup
    was ALLOWED, the faithful one REFUSED forever). Returns (rc, bytes,
    stderr_text). Same env + timeout semantics as `_run` (Round 15)."""
    rc, out, err = _exec(args, cwd=cwd, env=env, input_bytes=input_bytes)
    return rc, out, err.decode("utf-8", "replace")


# T140 Round 11 review finding B1 (fixed here): the ONE canonical patch
# shape a backup must byte-match. Every option is load-bearing:
#   --binary          a binary change is emitted as a restorable base85
#                     literal, never the content-free "Binary files differ"
#                     line the former plain `git diff HEAD` produced
#                     (reproduced live: that "backup" fails `git apply`
#                     with "cannot apply binary patch ... without full index
#                     line" -- the binary change was unrecoverable)
#   --no-textconv     a configured textconv filter would emit a LOSSY,
#                     human-readable rendering instead of the real bytes
#   --no-ext-diff / --no-color   no external diff driver, no ANSI escapes
#   --src-prefix/--dst-prefix    a user `diff.noprefix=true` cannot change
#                     the patch shape (`git apply` needs the a/ b/ prefixes)
#   --no-relative     a user `diff.relative` cannot silently drop changes
#                     outside the current subdirectory
#   --ignore-submodules=none     a `submodule.*.ignore` config cannot HIDE a
#                     submodule change (see the submodule check below)
# An operator creating a backup MUST use the same options, e.g. for a
# worktree:  git -C <wt> diff HEAD <CANONICAL_PATCH_OPTS> > tracked.patch
# and for a stash:  git stash show -p <CANONICAL_PATCH_OPTS> <ref> > patch.diff
# A backup created with a plain `git diff HEAD` (pre-Round-11 convention)
# no longer byte-matches (if nothing else, --binary implies --full-index)
# and is honestly REFUSED -> `keep`, the safe-reversible default.
CANONICAL_PATCH_OPTS = (
    "--binary", "--no-color", "--no-ext-diff", "--no-textconv", "--no-relative",
    "--src-prefix=a/", "--dst-prefix=b/", "--ignore-submodules=none",
)


def _json_safe(obj):
    """T140 Round 11 review finding I6 (fixed here): recursively replaces
    any surrogate-escaped (non-UTF-8) character in a string with U+FFFD so
    `canon()` (ensure_ascii=False, then `.encode("utf-8")`) can never crash
    on a non-UTF-8 stash message / commit subject / path. Display-only --
    never applied to a value this tool later passes back to git."""
    if isinstance(obj, str):
        try:
            obj.encode("utf-8")
            return obj
        except UnicodeEncodeError:
            return obj.encode("utf-8", "surrogateescape").decode("utf-8", "replace")
    if isinstance(obj, list):
        return [_json_safe(x) for x in obj]
    if isinstance(obj, dict):
        return {_json_safe(k): _json_safe(v) for k, v in obj.items()}
    return obj


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
    function's own scratch-repo contract exactly. Scratch-only, by
    construction of every call site that passes it; this tool's own
    `--repo-root` / live-worktree git calls use `_targeted_git_env()`
    instead (T140 Round 15, IMPORTANT-2: they keep the caller's user/system
    config but never an ambient git-redirection variable)."""
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
    """Returns (files_touched, patch_bytes). T140 Round 11 finding B1: the
    patch is read as RAW BYTES with CANONICAL_PATCH_OPTS (binary-safe,
    CRLF-preserving) -- its sha256 is what a backup must byte-match. The
    file list is decoded for display only (surrogateescape, I6)."""
    rc, out, _ = _run_bytes(["git", "-C", root, "stash", "show", "-p"] + list(CANONICAL_PATCH_OPTS) + [ref],
                            env=env)
    if rc != 0:
        return [], b""
    files = []
    for raw_line in out.split(b"\n"):
        if not raw_line.startswith(b"diff --git "):
            continue
        m = DIFF_FILE_RE.match(raw_line.decode("utf-8", "surrogateescape"))
        if m:
            files.append(m.group(1))
    return files, out


def stash_has_untracked(root, ref, env=None):
    """T140 Round 11 review finding B1 scenario 3 (fixed here): a stash made
    with `git stash push -u`/`--include-untracked` (or `-a`) stores the
    untracked files in a THIRD parent commit (`<ref>^3`) that `git stash
    show -p` does NOT include -- so a `patch.diff` backup can never cover
    them. The former docstring claim "a stash never captures untracked
    files" was FALSE for exactly the common -u case. Returns True when
    `<ref>^3` resolves, False when it genuinely does not, None when the
    question itself could not be answered (treated as unsafe by the
    caller)."""
    rc, _out, err = _run(["git", "-C", root, "rev-parse", "--verify", "-q", "%s^3" % ref],
                         check=False, env=env)
    if rc == 0:
        return True
    # `rev-parse --verify -q` exits 1 with EMPTY stderr for "no such
    # revision"; anything else (a non-empty stderr) is an unanswered
    # question, never silently read as "no untracked part".
    return False if not err.strip() else None


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
    files, patch_bytes = stash_files_touched(root, ref)
    owner_item = owner_item_from_text(message)
    dirty_hash = sha256_of_bytes(patch_bytes) if patch_bytes else None
    dirty_status = "dirty" if patch_bytes else "empty_patch"
    backup, searched = find_stash_backup(root, backup_root, ref)
    return {
        "entry_kind": "stash",
        "entry_id": ref,
        "message": message,
        "owner_item": owner_item,
        "last_commit": stash_commit(root, ref),
        "base_commit": stash_base_commit(root, ref),
        "files_touched": files,
        "dirty_file_hash": {"status": dirty_status, "sha256": dirty_hash,
                            "has_untracked": stash_has_untracked(root, ref)},
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


def _same_dir(a, b):
    """T140 Round 13 (round-12 finding M-1, fixed here): `--repo-root` may be
    a SYMLINK to a worktree while git reports every worktree path already
    symlink-resolved, so the former `abspath(a) == abspath(b)` never matched
    and a symlinked --repo-root pointing at a LINKED worktree was not
    recognised as "the checkout this tool was pointed at". Both sides are
    now fully resolved."""
    return os.path.realpath(a) == os.path.realpath(b)


def worktree_entry_id(path, root):
    m = AGENT_WT_RE.search(path)
    if m:
        return m.group(1)
    if _same_dir(path, root):
        return "MAIN"
    return os.path.basename(path.rstrip("/"))


def worktree_head_subject(path):
    rc, out, _ = _run(["git", "-C", path, "log", "-1", "--format=%s"], check=False)
    if rc != 0:
        return None
    return out.strip()


def _parse_status_v2_z(raw):
    """T140 Round 11 review finding B1 scenario 4 (fixed here): parses
    `git status --porcelain=v2 -z` RAW BYTES. Returns a dict
      {any_change, has_untracked, dirty_submodules: [path, ...],
       has_unmerged}
    or None when a record cannot be parsed (the caller treats an unparseable
    status as UNMEASURED -- never as clean).

    porcelain v2 is used (never v1) because it carries the `<sub>` field:
    "N..." for an ordinary path, "S<c><m><u>" for a SUBMODULE. A changed
    submodule is the case the former code silently ALLOWED to be retired:
    `git diff HEAD` records only the gitlink line ("Subproject commit
    <sha>-dirty"), never the submodule's own uncommitted changes or its
    unpushed commits -- and a linked worktree's submodule git dirs live
    under `.git/worktrees/<id>/modules/`, deleted with the worktree. Every
    changed submodule entry is therefore reported, whatever its c/m/u
    flags (a moved pointer alone can name commits that exist only in that
    about-to-be-deleted submodule git dir)."""
    res = {"any_change": False, "has_untracked": False, "dirty_submodules": [], "has_unmerged": False}
    tokens = raw.split(b"\0")
    i = 0
    while i < len(tokens):
        rec = tokens[i]
        i += 1
        if not rec:
            continue
        if rec.startswith(b"# "):
            continue
        if rec.startswith(b"? "):
            res["any_change"] = True
            res["has_untracked"] = True
            continue
        if rec.startswith(b"! "):
            continue  # ignored entry (only emitted with --ignored, never requested here)
        if rec.startswith(b"1 "):
            parts = rec.split(b" ", 8)
            if len(parts) != 9:
                return None
        elif rec.startswith(b"2 "):
            parts = rec.split(b" ", 9)
            if len(parts) != 10:
                return None
            i += 1  # a rename/copy record is followed by its ORIGINAL path as the next NUL token
        elif rec.startswith(b"u "):
            parts = rec.split(b" ", 10)
            if len(parts) != 11:
                return None
            res["has_unmerged"] = True
        else:
            return None
        res["any_change"] = True
        sub_field = parts[2]
        if sub_field.startswith(b"S"):
            res["dirty_submodules"].append(parts[-1].decode("utf-8", "surrogateescape"))
    return res


_UNMEASURED_WT_STATE = {"status": "UNMEASURED", "sha256": None, "has_untracked": None,
                        "dirty_submodules": None, "has_unmerged": None}


def worktree_dirty_state(path, env=None):
    """Returns (state_dict, patch_bytes). T140 Round 11 review findings
    B1/I6 (fixed here):
      - the patch is read as RAW BYTES with CANONICAL_PATCH_OPTS (binary-
        safe, CRLF-preserving, textconv-free); its sha256 is what a
        `tracked.patch` backup must byte-match;
      - status is read via porcelain v2 -z so a changed SUBMODULE is
        detected (see `_parse_status_v2_z`) and a non-UTF-8 path can never
        crash the run;
      - a FAILED `git diff` is now UNMEASURED -- the former code fell
        through to "untracked_only"/"clean" when the diff command itself
        failed (a fail-open read of "could not look" as "nothing there")."""
    rc, raw, _ = _run_bytes(["git", "-C", path, "status", "--porcelain=v2", "-z",
                             "--untracked-files=all", "--ignore-submodules=none"], env=env)
    if rc != 0:
        return dict(_UNMEASURED_WT_STATE), b""
    parsed = _parse_status_v2_z(raw)
    if parsed is None:
        return dict(_UNMEASURED_WT_STATE), b""
    extra = {"has_untracked": parsed["has_untracked"], "dirty_submodules": parsed["dirty_submodules"],
             "has_unmerged": parsed["has_unmerged"]}
    if not parsed["any_change"]:
        return dict(status="clean", sha256=None, **extra), b""
    rc2, diff_out, _ = _run_bytes(["git", "-C", path, "diff"] + list(CANONICAL_PATCH_OPTS) + ["HEAD"],
                                  env=env)
    if rc2 != 0:
        return dict(_UNMEASURED_WT_STATE), b""
    if diff_out:
        return dict(status="dirty", sha256=sha256_of_bytes(diff_out), **extra), diff_out
    if parsed["has_untracked"]:
        return dict(status="untracked_only", sha256=None, **extra), b""
    return dict(status="clean", sha256=None, **extra), b""


# ---------------------------------------------------------------------------
# T140 Round 15 (round-14 findings BLOCKING-1 + BLOCKING-2 + MINOR-3, fixed
# here as ONE check class): what `git worktree remove --force` deletes is not
# only the worktree's working directory (the restorability oracle covers
# that) but ALSO its per-worktree ADMIN directory, `<common>/worktrees/<id>/`.
# That directory can hold git state found nowhere else, which the oracle never
# looked at -- reproduced live in round 14, each ALLOWED and then permanently
# lost after retire:
#   - a deinit'd submodule's own git dir under `modules/<name>`, holding a
#     commit that was never pushed (lost IMMEDIATELY on remove);
#   - a commit reachable only from the worktree's own reflog (`logs/HEAD`),
#     e.g. a detached-HEAD commit abandoned by checking a branch back out;
#   - a commit held only by a PER-WORKTREE ref (`refs/worktree/*`,
#     `refs/bisect/*`, `refs/rewritten/*` -- git's documented per-worktree
#     namespaces, gitrepository-layout(5) / git-worktree(1));
#   - in-progress operation state (`rebase-merge/` todo + autostash,
#     `rebase-apply/` mailbox, `sequencer/`, `MERGE_HEAD`/`MERGE_MSG`, ...).
# The check is an ALLOWLIST over the admin directory's top-level entries: an
# entry this tool does not positively know to be either harmless or checked is
# REFUSED by name -- an unknown future git file can only cause a false REFUSAL
# (the safe direction), never a silent loss. Every object id recorded in the
# admin directory's reflogs and pseudo-refs must be reachable from a SHARED
# ref (`refs/stash` and the per-worktree namespaces never count: a stash can
# itself be dropped by this tool, and a per-worktree ref is deleted with its
# worktree).
#
# HONEST BOUNDARY (section 11.4.6): a commit superseded by `commit --amend` /
# `reset` / `rebase` stays in `logs/HEAD` until the reflog expires, so such a
# worktree is REFUSED until an operator either anchors that commit on a
# branch/tag or explicitly expires the reflog -- deliberate: the tool cannot
# tell an intentionally discarded commit from a lost one. A repository whose
# ref storage is not the `files` backend (reftable) is REFUSED as not
# inspectable by this check. `COMMIT_EDITMSG` (the text of the last commit
# attempt) is treated as harmless.
# ---------------------------------------------------------------------------
_ADMIN_HARMLESS = frozenset(("commondir", "gitdir", "index", "locked", "COMMIT_EDITMSG"))
# Entries whose content is CHECKED below rather than refused outright.
_ADMIN_CHECKED = frozenset(("HEAD", "ORIG_HEAD", "FETCH_HEAD", "AUTO_MERGE", "logs", "refs", "modules"))
_ADMIN_IN_PROGRESS = frozenset((
    "rebase-merge", "rebase-apply", "sequencer", "MERGE_HEAD", "MERGE_MSG", "MERGE_MODE", "MERGE_AUTOSTASH",
    "SQUASH_MSG", "CHERRY_PICK_HEAD", "REVERT_HEAD", "REBASE_HEAD", "BISECT_START", "BISECT_LOG",
    "BISECT_TERMS", "BISECT_NAMES", "BISECT_EXPECTED_REV", "BISECT_ANCESTORS_OK", "BISECT_RUN",
    "BISECT_FIRST_PARENT", "index.lock", "HEAD.lock",
))
_PER_WORKTREE_REF_PREFIXES = ("refs/worktree/", "refs/bisect/", "refs/rewritten/")
_OID_RE = re.compile(r"^[0-9a-f]{40}(?:[0-9a-f]{24})?$")


def _shared_anchor_oids(path, env=None):
    """Object ids of every ref that SURVIVES the removal of any worktree and
    cannot itself be dropped by this tool: everything `for-each-ref` lists
    EXCEPT `refs/stash` and the per-worktree namespaces. Returns (set, None)
    or (None, reason)."""
    rc, out, err = _run_bytes(["git", "-C", path, "for-each-ref", "--format=%(objectname) %(refname)"], env=env)
    if rc != 0:
        return None, "git for-each-ref failed: %s" % err.strip()
    oids = set()
    for line in out.decode("utf-8", "surrogateescape").splitlines():
        oid, _sp, ref = line.partition(" ")
        if not _OID_RE.match(oid):
            return None, "unparseable for-each-ref line %r" % line[:120]
        if ref == "refs/stash" or ref.startswith(_PER_WORKTREE_REF_PREFIXES):
            continue
        oids.add(oid)
    return oids, None


def _unanchored_commits(path, candidates, env=None):
    """Of `candidates` (object ids), returns (list_of_commit_ids_reachable
    from NO shared anchor ref, None) or (None, reason). Object ids that no
    longer exist are skipped (already gone -- nothing left to lose); non-
    commit ids are skipped (only commits carry history)."""
    cands = sorted({c for c in candidates if c and not _null_oid(c)})
    if not cands:
        return [], None
    rc, out, err = _run_bytes(["git", "--no-replace-objects", "-C", path, "cat-file",
                               "--batch-check=%(objectname) %(objecttype)"],
                              env=env, input_bytes="".join(c + "\n" for c in cands).encode())
    if rc != 0:
        return None, "git cat-file --batch-check failed: %s" % err.strip()
    commits = []
    for line in out.decode("utf-8", "replace").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == "commit":
            commits.append(parts[0])
        elif len(parts) == 2 and parts[1] == "missing":
            continue
        elif len(parts) == 2 and parts[1] in ("tree", "blob", "tag"):
            continue
        else:
            return None, "unparseable cat-file line %r" % line[:120]
    if not commits:
        return [], None
    anchors, why = _shared_anchor_oids(path, env=env)
    if anchors is None:
        return None, why
    stdin = "".join(c + "\n" for c in commits) + "".join("^" + a + "\n" for a in sorted(anchors))
    # --no-replace-objects: walk the REAL parent links (what gc keeps); any
    # refs/replace/* ref is itself in the anchor set, so history reachable
    # only through a replacement commit is still counted as anchored.
    rc, out, err = _run_bytes(["git", "--no-replace-objects", "-C", path, "rev-list", "--stdin"], env=env,
                              input_bytes=stdin.encode())
    if rc != 0:
        return None, "git rev-list failed: %s" % err.strip()
    return [x for x in out.decode("utf-8", "replace").split() if x], None


def _walk_raise(exc):
    """T140 Round 17 (round-16 finding MINOR-2, fixed here): `os.walk`'s
    DEFAULT `onerror` silently SWALLOWS an unreadable directory (e.g.
    permission denied) -- it just yields nothing for it, as if it were
    empty. That contradicts this module's own fail-closed design: the
    sibling `os.scandir` call in `_snapshot_files` already lets a
    permission error propagate so the caller refuses ("could not look",
    never "nothing there"). Passed as `os.walk(..., onerror=_walk_raise)`
    below so a `logs/`/`refs/` admin-dir subtree this process cannot read
    RAISES (caught by the `except (OSError, ValueError)` around the walk)
    instead of silently reading as zero entries -- the exact state that let
    `chmod 000` on an admin `refs/worktree`/`logs` directory flip the
    verdict from REFUSED to ALLOWED (reproduced live: `worktree
    admin_dir_problems` returned `([], None)` instead of
    `(None, "could not read ...")`)."""
    raise exc


def _oids_in_file(fp, reflog):
    """Object ids recorded in an admin-dir file. A reflog line is
    '<old> <new> <ident>\\t<msg>'; a pseudo-ref holds '<oid>' (FETCH_HEAD:
    '<oid>\\t...' per line). A symbolic 'ref: ...' line holds none. Raises
    ValueError on an unparseable reflog line."""
    with open(fp, "rb") as fh:
        text = fh.read().decode("utf-8", "surrogateescape")
    oids = []
    for line in text.splitlines():
        if not line.strip():
            continue
        if reflog:
            parts = line.split(" ", 2)
            if len(parts) < 3 or not _OID_RE.match(parts[0]) or not _OID_RE.match(parts[1]):
                raise ValueError("unparseable reflog line in %s: %r" % (fp, line[:120]))
            oids.extend(parts[:2])
        else:
            tok = line.split()[0] if line.split() else ""
            if _OID_RE.match(tok):
                oids.append(tok)
    return oids


def worktree_admin_dir_problems(path, env=None):
    """Returns (problems, None) or (None, reason-it-could-not-be-checked) for
    the per-worktree admin directory of the LINKED worktree at `path` (see
    the block comment above)."""
    rc, out, err = _run(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-dir",
                         "--git-common-dir"], check=False, env=env)
    lines = out.splitlines()
    if rc != 0 or len(lines) != 2:
        return None, "could not resolve the worktree's git dirs: %s" % err.strip()
    admin, common = lines
    if os.path.realpath(admin) == os.path.realpath(common):
        return None, "the worktree has no separate per-worktree admin directory (it is the main worktree)"
    rc, fmt, _err = _run(["git", "-C", path, "rev-parse", "--show-ref-format"], check=False, env=env)
    if rc == 0 and fmt.strip() and fmt.strip() != "files":
        return None, "ref storage %r is not inspectable by this check (only 'files')" % fmt.strip()
    problems, candidates = [], []
    try:
        names = sorted(os.listdir(admin))
        for name in names:
            fp = os.path.join(admin, name)
            if name in _ADMIN_HARMLESS:
                continue
            if name in _ADMIN_IN_PROGRESS:
                problems.append("%s: in-progress operation state in the per-worktree admin dir (deleted with "
                                "the worktree)" % name)
                continue
            if name not in _ADMIN_CHECKED:
                problems.append("%s: unrecognised per-worktree admin entry (deleted with the worktree; this "
                                "tool cannot prove its content is held anywhere else)" % name)
                continue
            if name == "modules":
                subs = sorted(os.listdir(fp)) if os.path.isdir(fp) else ["<not a directory>"]
                if subs:
                    problems.append("modules/%s: a submodule git dir inside the per-worktree admin dir "
                                    "(its commits/refs are deleted with the worktree)" % ",".join(subs))
                continue
            if name in ("logs", "refs"):
                if not os.path.isdir(fp):
                    problems.append("%s: unexpected non-directory admin entry" % name)
                    continue
                for dirpath, _dirs, files in os.walk(fp, onerror=_walk_raise):
                    for f in sorted(files):
                        full = os.path.join(dirpath, f)
                        rel = os.path.relpath(full, admin).replace(os.sep, "/")
                        if name == "refs":
                            problems.append("%s: a per-worktree ref (deleted with the worktree)" % rel)
                            candidates.extend(_oids_in_file(full, reflog=False))
                        else:
                            candidates.extend(_oids_in_file(full, reflog=True))
                continue
            candidates.extend(_oids_in_file(fp, reflog=False))  # HEAD / ORIG_HEAD / FETCH_HEAD / AUTO_MERGE
    except (OSError, ValueError) as exc:
        return None, "could not read the per-worktree admin dir %r (%s: %s)" % (admin, type(exc).__name__, exc)
    lost, why = _unanchored_commits(path, candidates, env=env)
    if lost is None:
        return None, why
    if lost:
        problems.append("%d commit(s) reachable only through this worktree's own refs/reflog/pseudo-refs "
                        "(no branch/tag/remote ref holds them; they die with the worktree), e.g. %s"
                        % (len(lost), ", ".join(lost[:3])))
    return problems, None


def stash_history_unanchored(root, ref, env=None):
    """T140 Round 15 (round-14 finding IMPORTANT-1, fixed here): dropping a
    stash deletes the only reference to its BASE commit's history when that
    history is held by nothing else (e.g. the branch the stash was taken on
    was deleted). The stash's own patch is a delta AGAINST that base, so it
    never carries the base's content (reproduced live: a file committed only
    on the deleted branch was lost after drop + gc while `land` was
    ALLOWED). Returns (problems, None) or (None, reason): every parent of
    the stash commit and of its `^2` index commit must be reachable from a
    shared ref other than `refs/stash`."""
    cands = []
    for spec in (ref, "%s^2" % ref):
        rc, out, err = _run(["git", "-C", root, "rev-list", "--parents", "--max-count=1", spec],
                            check=False, env=env)
        toks = out.split()
        if rc != 0 or not toks:
            return None, "could not list the parents of %s: %s" % (spec, err.strip())
        cands.extend(toks[1:])
    # the ^3 untracked commit (if any) has no parents; ^2 is the index commit
    # itself, judged by content elsewhere -- only real history parents here.
    stash_oid = _run(["git", "-C", root, "rev-parse", ref], check=False, env=env)[1].strip()
    idx_oid = _run(["git", "-C", root, "rev-parse", "%s^2" % ref], check=False, env=env)[1].strip()
    third = _run(["git", "-C", root, "rev-parse", "--verify", "-q", "%s^3" % ref], check=False, env=env)[1].strip()
    cands = [c for c in cands if c not in (stash_oid, idx_oid, third)]
    lost, why = _unanchored_commits(root, cands, env=env)
    if lost is None:
        return None, why
    if lost:
        return ["%d commit(s) of the stash's base history are reachable from no branch/tag/remote ref -- only "
                "the stash keeps them alive (e.g. %s)" % (len(lost), ", ".join(lost[:3]))], None
    return [], None


STASH_REF_RE = re.compile(r"^stash@\{\d+\}$")


def resolve_live_dirty_state(entry_kind, entry_id, root, env=None):
    """Independently RE-DERIVES the entry's CURRENT live state, fresh, at
    call time -- reusing the EXACT SAME git-querying functions `inventory`
    itself uses (never a second implementation, section 11.4.227) -- so a
    backup is checked against what the stash/worktree ACTUALLY looks like
    RIGHT NOW, never against a cached inventory value and never against
    itself (section 9.2 / T140 finding I3).

    Returns a dict:
      found             False => entry_id does not resolve to exactly one
                        live stash/worktree (dropped/removed since the
                        inventory, malformed, or AMBIGUOUS) -- the caller
                        refuses, never reads it as "matches"
      ambiguous         True when >1 live worktree maps to entry_id
      live_hash         sha256 of the canonical raw-bytes patch, or None
      has_untracked     True/False/None -- for a worktree: `git status`
                        `??` entries; for a STASH: the `-u` third parent
                        (T140 Round 11 finding B1 scenario 3 -- the former
                        "always False for a stash" was false for -u)
      dirty_submodules  list of changed submodule paths (worktree), [] for
                        a stash, None when undeterminable
      has_unmerged      True when the worktree has unresolved conflicts
      is_main           True when the worktree is the repository's MAIN
                        worktree (git always lists it FIRST) or the
                        checkout this tool was pointed at (--repo-root)
                        (T140 Round 11 finding B1 scenario 5)
      path              the resolved worktree path (worktree only)
      head_unreachable  True when a DETACHED worktree's HEAD is reachable
                        from no ref (its commits die with the worktree)
      measured          False when the live state could not be read at all
                        (a failed git status/diff) -- the caller refuses
    """
    res = {"found": False, "ambiguous": False, "live_hash": None, "has_untracked": None,
           "dirty_submodules": None, "has_unmerged": None, "is_main": False, "path": None,
           "measured": False}
    if entry_kind == "stash":
        if not isinstance(entry_id, str) or not STASH_REF_RE.match(entry_id):
            return res
        rc, _out, _err = _run(["git", "-C", root, "rev-parse", "--verify", "-q", entry_id],
                               check=False, env=env)
        if rc != 0:
            return res
        _files, patch_bytes = stash_files_touched(root, entry_id, env=env)
        res.update(found=True,
                   live_hash=sha256_of_bytes(patch_bytes) if patch_bytes else None,
                   has_untracked=stash_has_untracked(root, entry_id, env=env),
                   dirty_submodules=[], has_unmerged=False, measured=True)
        # T140 Round 15 IMPORTANT-1: the stash's base history must survive
        # the drop (see stash_history_unanchored).
        res["history_problems"], res["history_why"] = stash_history_unanchored(root, entry_id, env=env)
        return res
    if entry_kind == "worktree":
        matches = []
        for idx, wt in enumerate(list_worktree_entries(root, env=env)):
            path = wt.get("path")
            if not path:
                continue
            if worktree_entry_id(path, root) != entry_id:
                continue
            matches.append((idx, path, wt))
        if len(matches) > 1:
            res["ambiguous"] = True
            return res
        if not matches:
            return res
        idx, path, wt = matches[0]
        res["path"] = path
        res["is_main"] = (idx == 0) or _same_dir(path, root)
        if not os.path.isdir(path):
            return res
        # T140 Round 11 (B1 sibling, found while fixing B1): a DETACHED
        # worktree whose HEAD commit is reachable from NO ref holds commits
        # that exist only via that worktree's own HEAD/reflog -- both live
        # under `.git/worktrees/<id>/` and are deleted with the worktree,
        # so `git gc` later destroys the commits. No patch backup covers
        # committed history, so this is refused like any uncovered content.
        res["head_unreachable"] = False
        if wt.get("detached"):
            head = wt.get("head")
            rc, out, _ = _run(["git", "-C", root, "for-each-ref", "--count=1", "--format=%(refname)",
                               "--contains", head or "HEAD"], check=False, env=env)
            res["head_unreachable"] = None if (rc != 0 or not head) else (not out.strip())
        state, _diff = worktree_dirty_state(path, env=env)
        if state.get("status") == "UNMEASURED":
            # Could not look -- reported as found-but-unmeasured; every
            # coverage field stays None so the caller refuses.
            res["found"] = True
            return res
        res.update(found=True, live_hash=state.get("sha256"),
                   has_untracked=state.get("has_untracked"),
                   dirty_submodules=state.get("dirty_submodules"),
                   has_unmerged=state.get("has_unmerged"), measured=True,
                   head=wt.get("head"))
        # T140 Round 15 BLOCKING-1/2 + MINOR-3: what `worktree remove` also
        # deletes -- the per-worktree admin dir (see worktree_admin_dir_problems).
        # Not computed for the MAIN worktree (refused unconditionally anyway).
        if res["is_main"]:
            res["history_problems"], res["history_why"] = [], None
        else:
            res["history_problems"], res["history_why"] = worktree_admin_dir_problems(path, env=env)
        return res
    return res


# ---------------------------------------------------------------------------
# T140 Round 13 (round-12 review finding B-1, fixed here): the POSITIVE
# RESTORABILITY ORACLE.
#
# Root cause the round-12 reviewer named: every check above compares the
# backup against what `git diff HEAD` / `git stash show -p` REPORTS. That is
# a proxy for "this backup brings the work back", and anything that makes the
# live files diverge from what git reports defeats it -- reproduced live in
# round 12 with `update-index --assume-unchanged` / `--skip-worktree` (the
# edit is invisible to `git diff`), staged content that differs from the
# worktree (`git diff HEAD` diffs the WORKTREE, never the index; a stash's
# `^2` index parent is never in `stash show -p`), and a lossy clean filter
# (the diff is of the FILTERED content, the real file keeps the unfiltered
# bytes). Patching each instance would be the heuristic-tower pattern
# (section 11.4.250); the fix is a check that does not consult git's report
# at all:
#
#   WORKTREE: take the entry's own HEAD commit, check it out into a FRESH,
#   ISOLATED scratch repository (a new `git init` under a temp dir that
#   borrows the real object store READ-ONLY through objects/info/alternates
#   -- nothing is ever written to the real repository: no `worktree add`, no
#   ref, no index, no object), `git apply` the backup there, then BYTE-
#   COMPARE every file in the REAL worktree (excluding its own top-level
#   `.git`) against the post-apply scratch checkout. Any difference -- a
#   file whose content/symlink target/exec bit differs, a file present live
#   but absent after restore (untracked, IGNORED, inside a populated
#   submodule, an assume-unchanged edit...), or the reverse -- REFUSES.
#   Plus the INDEX: for every path whose staged blob differs from HEAD, the
#   staged blob must equal the live file's clean-filtered content (or be a
#   HEAD-side blob merely moved by a rename) -- otherwise the staged
#   version exists ONLY in the about-to-be-deleted index (the one property a
#   live-file comparison cannot see).
#
#   STASH: dropping a stash loses its worktree tree, its index tree (`^2`)
#   and its untracked tree (`^3`, already refused above). The backup is
#   applied onto the base commit's tree in a scratch index and the resulting
#   tree id must EQUAL the stash's own tree; and every path whose `^2` blob
#   differs from BOTH the base and the stash tree is index-only content no
#   patch backup carries -- REFUSED.
#
# HONEST BOUNDARY (section 11.4.6) -- what this oracle does NOT prove:
#   - it compares file CONTENT, symlink targets and the owner exec bit; it
#     does not compare other permission bits, ownership, timestamps,
#     extended attributes or ACLs (a restore would not reproduce those
#     either, and none of them is "work" in the sense this tool guards);
#   - an INDEX entry's MODE alone (a staged chmod later reverted live) is
#     not checked -- only staged CONTENT;
#   - the scratch checkout reproduces the live checkout's byte conversion
#     only as faithfully as the conversion config transferred to it (every
#     `filter.*` and the `core.*` keys that change checkout bytes, read as
#     EFFECTIVE values from the live worktree) plus the repository's
#     `info/attributes`; a smudge filter that is non-deterministic or needs
#     data outside the object store (e.g. git-lfs content that is not
#     already local) makes the scratch checkout differ or fail -- which
#     REFUSES, the safe direction, never a false ALLOWED;
#   - it is a point-in-time proof: a live file changed AFTER the comparison
#     and before an operator acts on the proposal is not covered -- that is
#     what the later, separate, operator-confirmed step must re-verify.
# ---------------------------------------------------------------------------
# Config keys whose EFFECTIVE value changes the bytes a checkout / `git
# apply` writes. Transferred from the live worktree into the scratch
# repository (via GIT_CONFIG_COUNT, so a key with any byte in it cannot be
# mis-split the way a `-c key=value` argv could).
_CONVERSION_CONFIG_RE = (r"^(filter\..*|core\.(autocrlf|eol|safecrlf|symlinks|filemode|"
                         r"checkroundtripencoding|attributesfile|precomposeunicode|ignorecase))$")
# Never let a scratch git run a hook, fsmonitor, auto-gc or a transport.
_SCRATCH_PINNED_CONFIG = (
    ("core.hooksPath", "/dev/null"), ("core.fsmonitor", "false"), ("advice.detachedHead", "false"),
    ("gc.auto", "0"), ("maintenance.auto", "false"), ("protocol.allow", "never"),
    ("submodule.recurse", "false"),
)
_ORACLE_MAX_LISTED = 10
_SCRATCH_SPACE_MARGIN = 64 * 1024 * 1024


def _null_oid(oid):
    return bool(oid) and set(oid) == {"0"}


def _conversion_config(path, env=None):
    """Returns a list of (key, value) EFFECTIVE conversion-config pairs from
    the live worktree, or None when the question could not be answered
    (treated as unmeasurable -> refuse)."""
    rc, out, _err = _run_bytes(["git", "-C", path, "config", "-z", "--get-regexp", _CONVERSION_CONFIG_RE],
                               env=env)
    if rc == 1:
        return []  # git config's documented "no matching key" exit
    if rc != 0:
        return None
    pairs = []
    for rec in out.split(b"\0"):
        if not rec:
            continue
        key, _sep, value = rec.partition(b"\n")
        pairs.append((key.decode("utf-8", "surrogateescape"), value.decode("utf-8", "surrogateescape")))
    return pairs


def _scratch_git_env(conv_pairs, extra=None):
    env = _sanitized_scratch_env()
    pairs = list(conv_pairs) + list(_SCRATCH_PINNED_CONFIG)
    env["GIT_CONFIG_COUNT"] = str(len(pairs))
    for n, (k, v) in enumerate(pairs):
        env["GIT_CONFIG_KEY_%d" % n] = k
        env["GIT_CONFIG_VALUE_%d" % n] = v
    if extra:
        env.update(extra)
    return env


def _make_scratch_repo(scratch, object_dir, object_format, attributes_src, senv):
    """`git init` a throwaway repository at `scratch` that READS the real
    object store through objects/info/alternates (never writes to it).
    Raises RuntimeError on failure."""
    _run(["git", "init", "--quiet", "--object-format=%s" % object_format, scratch], check=True, env=senv)
    alt = os.path.join(scratch, ".git", "objects", "info", "alternates")
    os.makedirs(os.path.dirname(alt), exist_ok=True)
    with open(alt, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(object_dir + "\n")
    if attributes_src and os.path.isfile(attributes_src):
        info = os.path.join(scratch, ".git", "info")
        os.makedirs(info, exist_ok=True)
        with open(attributes_src, "rb") as src, open(os.path.join(info, "attributes"), "wb") as dst:
            dst.write(src.read())


def _repo_storage(path, env=None):
    """Returns (object_dir, object_format, info_attributes_path) for the
    repository `path` belongs to, or raises RuntimeError."""
    _rc, objdir, _ = _run(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-path", "objects"],
                          check=True, env=env)
    _rc, fmt, _ = _run(["git", "-C", path, "rev-parse", "--show-object-format"], check=True, env=env)
    _rc, attrs, _ = _run(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-path",
                          "info/attributes"], check=True, env=env)
    return objdir.strip(), fmt.strip(), attrs.strip()


def _sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _snapshot_files(top):
    """Maps every non-directory entry under `top` (relative path, '/'-
    separated) to a comparable descriptor, never following a symlink.
    Excludes ONLY `top`'s own top-level `.git` (the repository metadata,
    which a restore re-creates). Directories are not recorded: an empty
    directory carries no content. Raises OSError when any part cannot be
    read -- the caller refuses (could not look, never "nothing there")."""
    import stat as _stat
    out = {}
    stack = [""]
    while stack:
        rel = stack.pop()
        with os.scandir(os.path.join(top, rel) if rel else top) as it:
            for ent in it:
                r = (rel + "/" + ent.name) if rel else ent.name
                if not rel and ent.name == ".git":
                    continue
                st = os.lstat(ent.path)
                if _stat.S_ISDIR(st.st_mode):
                    stack.append(r)
                elif _stat.S_ISLNK(st.st_mode):
                    out[r] = ("symlink", os.readlink(ent.path))
                elif _stat.S_ISREG(st.st_mode):
                    out[r] = ("file", bool(st.st_mode & 0o100), _sha256_file(ent.path))
                else:
                    out[r] = ("special", _stat.S_IFMT(st.st_mode))
    return out


def _describe_tree_diff(live, restored):
    problems = []
    for r in sorted(set(live) | set(restored)):
        lv, rv = live.get(r), restored.get(r)
        if lv == rv:
            continue
        if rv is None:
            problems.append("%s: present LIVE but absent after restore (untracked/ignored/hidden content "
                            "the backup does not carry)" % r)
        elif lv is None:
            problems.append("%s: present after restore but absent LIVE" % r)
        elif lv[0] != rv[0]:
            problems.append("%s: file type differs (live %s, restored %s)" % (r, lv[0], rv[0]))
        elif lv[0] == "file" and lv[2] == rv[2]:
            problems.append("%s: exec bit differs (live %s, restored %s)" % (r, lv[1], rv[1]))
        else:
            problems.append("%s: content differs from the restored copy" % r)
    return problems


def _summarize(problems):
    shown = problems[:_ORACLE_MAX_LISTED]
    more = len(problems) - len(shown)
    return "; ".join(_json_safe(shown)) + (" ... (+%d more)" % more if more > 0 else "")


def _scratch_space_ok(path, head, tmpdir, env=None):
    """True when the temp filesystem has room for a full checkout of
    `head` (twice its blob bytes + a margin), False when it does not, None
    when it could not be determined."""
    rc, out, _ = _run_bytes(["git", "-C", path, "ls-tree", "-r", "-l", "-z", head], env=env)
    if rc != 0:
        return None
    total = 0
    for rec in out.split(b"\0"):
        if not rec:
            continue
        meta = rec.split(b"\t", 1)[0].split()
        if len(meta) == 4 and meta[3].isdigit():
            total += int(meta[3])
    try:
        sv = os.statvfs(tmpdir)
    except OSError:
        return None
    return sv.f_bavail * sv.f_frsize >= 2 * total + _SCRATCH_SPACE_MARGIN


def _worktree_index_unique_paths(path, env=None):
    """Returns (problems, None) or (None, reason-it-could-not-be-measured).
    A problem is a path whose STAGED content exists nowhere but the index:
    staged blob != HEAD blob, != the live file's clean-filtered content, and
    not merely a HEAD-side blob moved by a rename. Computed from the index
    itself (`diff-index --cached`, no stat cache involved), so neither
    assume-unchanged nor skip-worktree can hide it. `--ita-invisible-in-
    index`: an intent-to-add (`git add -N`) entry carries NO staged content
    (it is shown as an empty blob otherwise and would be a false refusal);
    its real content is the live file, which the restore comparison
    covers."""
    rc, raw, err = _run_bytes(["git", "-C", path, "diff-index", "--cached", "-z", "--no-renames",
                               "--ita-invisible-in-index", "--ignore-submodules=none", "HEAD"], env=env)
    if rc != 0:
        return None, "git diff-index --cached failed: %s" % err.strip()
    toks = raw.split(b"\0")
    recs = []
    i = 0
    while i < len(toks):
        meta = toks[i]
        i += 1
        if not meta:
            continue
        if not meta.startswith(b":") or i >= len(toks):
            return None, "unparseable diff-index record %r" % meta[:80]
        fields = meta[1:].split(b" ")
        if len(fields) != 5:
            return None, "unparseable diff-index record %r" % meta[:80]
        p = toks[i].decode("utf-8", "surrogateescape")
        i += 1
        recs.append((fields[1].decode(), fields[2].decode(), fields[3].decode(), fields[4].decode()[:1], p))
    head_side = {hH for (_mI, hH, _hI, _s, _p) in recs if not _null_oid(hH)}
    problems, to_hash = [], []
    for m_index, _h_head, h_index, status, p in recs:
        if status == "U":
            problems.append("%s: unmerged index entry (conflict stages exist only in the index)" % p)
            continue
        if status == "D" or m_index == "160000" or _null_oid(h_index) or h_index in head_side:
            continue
        fp = os.path.join(path, p)
        if not os.path.lexists(fp):
            problems.append("%s: staged content whose worktree file is absent" % p)
        elif os.path.islink(fp) or m_index == "120000":
            # Not hashed by path (a symlink would be followed): hash the
            # exact bytes a checkout of the staged entry would reproduce.
            if os.path.islink(fp) and m_index == "120000":
                data = os.fsencode(os.readlink(fp))
                rc2, out2, _ = _run_bytes(["git", "-C", path, "hash-object", "--no-filters", "--stdin"],
                                          env=env, input_bytes=data)
                if rc2 != 0:
                    return None, "git hash-object failed for symlink %r" % p
                if out2.strip().decode() != h_index:
                    problems.append("%s: staged symlink target differs from the live one" % p)
            else:
                problems.append("%s: staged entry type/path not comparable with the live file" % p)
        else:
            to_hash.append((p, h_index))
    # T140 Round 15 (round-14 finding MINOR-1, fixed here): paths are passed
    # as ARGV after `--`, never via `--stdin-paths`, which C-unquotes a line
    # starting with '"' (a file literally named `"q"` was hashed as `q` --
    # the check compared against the WRONG file). Chunked to bound argv size.
    hashed = []
    for start in range(0, len(to_hash), 256):
        chunk = to_hash[start:start + 256]
        rc3, out3, err3 = _run_bytes(["git", "-C", path, "hash-object", "--"] + [p for p, _h in chunk], env=env)
        lines = out3.decode("utf-8", "replace").split()
        if rc3 != 0 or len(lines) != len(chunk):
            return None, "git hash-object failed: %s" % err3.strip()
        hashed.extend(lines)
    if to_hash:
        for (p, h_index), h_live in zip(to_hash, hashed):
            if h_live != h_index:
                problems.append("%s: STAGED content differs from the worktree file (exists only in the "
                                "index)" % p)
    return problems, None


def restore_oracle_worktree(path, head, backup_full, env=None):
    """Returns (True, detail) when the backup PROVABLY restores the live
    worktree, else (False, detail). Never raises for a git/OS failure --
    that is (False, "could not prove ...")."""
    if not head or _null_oid(head):
        return False, "worktree has no HEAD commit to restore onto"
    try:
        idx_problems, why = _worktree_index_unique_paths(path, env=env)
        if idx_problems is None:
            return False, "could not inspect the index (%s)" % why
        if idx_problems:
            return False, ("index holds STAGED content no backup carries -- %s" % _summarize(idx_problems))
        conv = _conversion_config(path, env=env)
        if conv is None:
            return False, "could not read the live worktree's conversion config"
        objdir, fmt, attrs = _repo_storage(path, env=env)
        tmpdir = tempfile.gettempdir()
        space = _scratch_space_ok(path, head, tmpdir, env=env)
        if not space:
            return False, ("insufficient (or undeterminable) free space under %r for a full scratch "
                           "checkout of %s -- restorability cannot be proven" % (tmpdir, head))
        real_top = os.path.realpath(path)
        with tempfile.TemporaryDirectory(prefix="custody_restore_") as tmp:
            if os.path.realpath(tmp).startswith(real_top + os.sep):
                return False, "scratch directory %r would sit inside the worktree under test" % tmp
            scratch = os.path.join(tmp, "restore")
            senv = _scratch_git_env(conv)
            _make_scratch_repo(scratch, objdir, fmt, attrs, senv)
            rc, _o, err = _run(["git", "-C", scratch, "checkout", "--quiet", "--detach", head],
                               check=False, env=senv)
            if rc != 0:
                return False, "scratch checkout of HEAD %s failed: %s" % (head, err.strip()[:300])
            rc, _o, err = _run(["git", "-C", scratch, "apply", "--whitespace=nowarn", backup_full],
                               check=False, env=senv)
            if rc != 0:
                return False, ("the backup does NOT apply onto a fresh checkout of HEAD %s: %s"
                               % (head, err.strip()[:300]))
            restored = _snapshot_files(scratch)
            live = _snapshot_files(path)
        problems = _describe_tree_diff(live, restored)
        if problems:
            return False, ("%d path(s) differ between the LIVE worktree and the backup restored onto a "
                           "fresh checkout of HEAD -- %s" % (len(problems), _summarize(problems)))
        return True, ("backup applied onto a fresh isolated checkout of HEAD %s reproduces all %d live "
                      "file(s) byte-for-byte (tracked, untracked and ignored alike), and the index holds "
                      "no staged-only content" % (head, len(live)))
    except (OSError, RuntimeError, ValueError) as exc:
        return False, "could not prove restorability (%s: %s)" % (type(exc).__name__, exc)


def restore_oracle_stash(root, ref, backup_full, env=None):
    """Returns (True, detail) when the backup PROVABLY reproduces the
    stash's worktree tree and the stash's index holds nothing beyond it,
    else (False, detail)."""
    try:
        def rev(spec):
            _rc, out, _ = _run(["git", "-C", root, "rev-parse", "--verify", "-q", spec], check=True, env=env)
            return out.strip()

        base, index_c, tree = rev("%s^1" % ref), rev("%s^2" % ref), rev("%s^{tree}" % ref)

        def changed(a, b):
            rc, out, err = _run_bytes(["git", "-C", root, "diff-tree", "-r", "-z", "--name-only",
                                       "--no-renames", "--ignore-submodules=none", a, b], env=env)
            if rc != 0:
                raise RuntimeError("git diff-tree %s %s failed: %s" % (a, b, err.strip()))
            return {t.decode("utf-8", "surrogateescape") for t in out.split(b"\0") if t}

        index_only = sorted(changed(base, index_c) & changed(index_c, ref))
        if index_only:
            return False, ("the stash's index (^2) holds STAGED content that differs from both its base and "
                           "its worktree tree -- no patch backup carries it: %s"
                           % _summarize([p + ": staged-only content" for p in index_only]))
        objdir, fmt, _attrs = _repo_storage(root, env=env)
        with tempfile.TemporaryDirectory(prefix="custody_restore_") as tmp:
            scratch = os.path.join(tmp, "restore")
            senv = _scratch_git_env([])
            _make_scratch_repo(scratch, objdir, fmt, None, senv)
            senv = _scratch_git_env([], {"GIT_INDEX_FILE": os.path.join(tmp, "restore.index")})
            _run(["git", "-C", scratch, "read-tree", base], check=True, env=senv)
            rc, _o, err = _run(["git", "-C", scratch, "apply", "--cached", "--whitespace=nowarn", backup_full],
                               check=False, env=senv)
            if rc != 0:
                return False, ("the backup does NOT apply onto the stash's base tree %s: %s"
                               % (base, err.strip()[:300]))
            _rc, got, _ = _run(["git", "-C", scratch, "write-tree"], check=True, env=senv)
        got = got.strip()
        if got != tree:
            return False, ("the backup applied onto the stash's base produces tree %s, NOT the stash's own "
                           "tree %s -- it does not restore the stashed work" % (got, tree))
        return True, ("backup applied onto the stash's base tree reproduces the stash tree %s exactly, and "
                      "its index holds no staged-only content" % tree)
    except (OSError, RuntimeError, ValueError) as exc:
        return False, "could not prove restorability (%s: %s)" % (type(exc).__name__, exc)


def find_worktree_backup(root, backup_root, entry_id):
    candidate = os.path.join(backup_root, "backup_worktrees", entry_id, "tracked.patch")
    searched = [os.path.relpath(candidate, root) if candidate.startswith(root) else candidate]
    if os.path.isfile(candidate):
        with open(candidate, "rb") as fh:
            data = fh.read()
        return {"backup_artifact_path": searched[0], "backup_hash": sha256_of_bytes(data)}, searched
    return None, searched


def build_worktree_entry(root, backup_root, wt, index=None):
    path = wt.get("path")
    entry_id = worktree_entry_id(path, root)
    branch = wt.get("branch", "")
    subject = worktree_head_subject(path) if path and os.path.isdir(path) else None
    owner_item = owner_item_from_text(subject, branch)
    dirty_state, _diff = worktree_dirty_state(path) if path and os.path.isdir(path) else (
        dict(_UNMEASURED_WT_STATE), b"")
    backup, searched = find_worktree_backup(root, backup_root, entry_id)
    # T140 Round 11 finding B1 scenario 5: `git worktree list` ALWAYS lists
    # the main worktree first; the checkout this tool was pointed at counts
    # too. The former `entry_id == "MAIN"` test missed the real main
    # worktree whenever --repo-root was a LINKED worktree.
    is_main = (index == 0) or bool(path and _same_dir(path, root))
    return {
        "entry_kind": "worktree",
        "entry_id": entry_id,
        "path": path,
        "branch": branch,
        "is_main": is_main,
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
            backup_bytes = fh.read()
        real_hash = sha256_of_bytes(backup_bytes)
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
        live = resolve_live_dirty_state(entry_kind, entry_id, root, env=env)
    except fc_common.SAFE_EXCEPTIONS as exc:
        return "REFUSED", ("could not independently re-derive the live dirty state for entry_id "
                            "%r (kind=%s): %s: %s -- entry_id must be a genuine string identifying "
                            "a real stash/worktree; cannot confirm the backup still covers "
                            "anything real" % (entry_id, entry_kind, type(exc).__name__, exc))
    if live.get("ambiguous"):
        return "REFUSED", ("entry_id %r (%s) is AMBIGUOUS -- more than one live worktree maps to it; "
                            "cannot tell which one the backup covers" % (entry_id, entry_kind))
    if not live.get("found"):
        return "REFUSED", ("entry_id %r (%s) no longer resolves to a live stash/worktree -- cannot "
                            "independently verify the backup still covers its content" % (entry_id, entry_kind))
    # T140 Round 11 review finding B1 scenario 5 (fixed here): the MAIN
    # worktree (and the checkout this tool was pointed at) is NEVER a retire
    # candidate, whatever its backup looks like -- `is_main` existed in the
    # data model but no verdict path ever checked it, so a gitignored-
    # everything main checkout with a matching backup was ALLOWED retire
    # (reproduced live). Checked BEFORE any coverage question: there is no
    # backup that makes deleting the main checkout a reversible action.
    if entry_kind == "worktree" and live.get("is_main"):
        return "REFUSED", ("worktree %r is the repository's MAIN worktree / the checkout this tool was "
                            "pointed at (%r) -- it is never a retire candidate" % (entry_id, live.get("path")))
    if not live.get("measured"):
        return "REFUSED", ("the live state of %s %r could not be read (git status/diff failed) -- "
                            "cannot confirm the backup covers it" % (entry_kind, entry_id))
    has_untracked = live.get("has_untracked")
    if has_untracked is not False:
        # True, or None (undeterminable) -- either way a tracked-diff-only
        # backup (worktree tracked.patch / stash patch.diff) cannot possibly
        # cover untracked content, so it is never silently ignored.
        # T140 Round 11 review finding B1 scenario 3 (fixed here): this now
        # applies to STASHES too -- a `git stash push -u` stash keeps its
        # untracked files in the `^3` parent, which `git stash show -p`
        # (and therefore patch.diff) never contains; `land` was ALLOWED on
        # exactly that case (reproduced live).
        return "REFUSED", ("%s %r has untracked content (has_untracked=%r) that the tracked-diff-only "
                            "backup at %r cannot cover -- %s refused to avoid losing it"
                            % (entry_kind, entry_id, has_untracked, backup_artifact_path, action))
    dirty_submodules = live.get("dirty_submodules")
    if dirty_submodules is None or dirty_submodules:
        # T140 Round 11 review finding B1 scenario 4 (fixed here): a patch
        # records a submodule only as a gitlink line ("Subproject commit
        # <sha>-dirty") -- the submodule's own uncommitted changes and any
        # commits that exist only in its (worktree-local) git dir are NOT
        # in any backup this tool knows how to verify.
        return "REFUSED", ("%s %r has changed submodule(s) %r whose own content no patch backup can "
                            "capture -- %s refused" % (entry_kind, entry_id, dirty_submodules, action))
    head_unreachable = live.get("head_unreachable", False)
    if head_unreachable is not False:
        return "REFUSED", ("worktree %r is on a DETACHED HEAD %s from any branch/tag -- its commits "
                            "would be lost with the worktree's own reflog; no patch backup covers "
                            "committed history, %s refused"
                            % (entry_id, "unreachable" if head_unreachable else "of undeterminable reachability",
                               action))
    if live.get("has_unmerged"):
        return "REFUSED", ("%s %r has unresolved merge conflicts -- index state a patch backup cannot "
                            "capture; %s refused" % (entry_kind, entry_id, action))
    # T140 Round 15 (round-14 BLOCKING-1/2 + MINOR-3 for a worktree,
    # IMPORTANT-1 for a stash): git state that the destructive action deletes
    # OUTSIDE anything a patch backup or the file-tree oracle covers -- the
    # worktree's per-worktree admin dir (submodule git dirs, own reflog,
    # per-worktree refs, in-progress operations) / the stash's base history.
    history_problems = live.get("history_problems")
    if history_problems is None:
        return "REFUSED", ("could not prove that %s %r holds no git state outside its files (%s) -- %s refused"
                            % (entry_kind, entry_id, live.get("history_why"), action))
    if history_problems:
        return "REFUSED", ("%s %r holds git state that '%s' would destroy and no patch backup carries -- %s"
                            % (entry_kind, entry_id, action, _summarize(history_problems)))
    live_hash = live.get("live_hash")
    if live_hash != real_hash:
        return "REFUSED", ("backup content at %r (sha256=%r) does NOT match the entry's freshly "
                            "re-derived LIVE dirty content (sha256=%r) -- the backup is stale and no "
                            "longer covers today's live changes" % (backup_artifact_path, real_hash, live_hash))
    # T140 Round 13 (round-12 finding B-1, fixed here): every check above is
    # a NECESSARY condition measured against what git REPORTS. The final,
    # sufficient condition is the positive restorability oracle -- it never
    # consults git's report of the change, it restores the backup in an
    # isolated scratch repository and compares the result with what is
    # really on disk (see the oracle block above for what it does and does
    # not prove). Checked LAST so its cost is paid only by a candidate every
    # cheaper check already accepts.
    # T140 Round 15 (round-14 finding MINOR-2, fixed here): the oracle must
    # apply EXACTLY the bytes whose sha256 was just verified -- never re-read
    # the backup path, which could change between the hash and the apply.
    # The verified bytes are written to a private temp copy and the oracle
    # consumes that copy only.
    try:
        with tempfile.TemporaryDirectory(prefix="custody_backup_") as bdir:
            backup_full = os.path.join(bdir, "verified_backup.patch")
            with open(backup_full, "wb") as fh:
                fh.write(backup_bytes)
            if entry_kind == "worktree":
                restorable, why = restore_oracle_worktree(live.get("path"), live.get("head"), backup_full, env=env)
            else:
                restorable, why = restore_oracle_stash(root, entry_id, backup_full, env=env)
    except OSError as exc:
        restorable, why = False, "could not stage the verified backup bytes (%s: %s)" % (type(exc).__name__, exc)
    if not restorable:
        return "REFUSED", ("RESTORABILITY ORACLE: the backup at %r does NOT provably restore %s %r -- %s; "
                            "%s refused" % (backup_artifact_path, entry_kind, entry_id, why, action))
    return "ALLOWED", ("backup_hash independently re-verified against BOTH the real backup file at %r "
                        "AND the entry's freshly re-derived live dirty content (canonical binary-safe "
                        "raw-bytes patch; no changed submodule, not the main worktree), AND the "
                        "RESTORABILITY ORACLE passed: %s" % (backup_artifact_path, why))


# ---------------------------------------------------------------------------
# Output assembly (C-002 canonical JSON + body_hash, identical convention to
# closure/reopen_rate.py's own write_report).
# ---------------------------------------------------------------------------
def write_doc(out_path, schema, body, run_meta):
    doc = _json_safe(dict(body))  # T140 Round 11 I6: never crash canon() on a non-UTF-8 string
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

    # T140 Round 11 review finding I6 (fixed here): per-entry error
    # isolation -- ONE unreadable entry (a failing git call, an undecodable
    # byte) becomes ONE honest UNMEASURED entry naming its error, never a
    # crash that aborts the WHOLE inventory.
    def _isolated(kind, entry_id, build):
        try:
            return build()
        except Exception as exc:
            return {
                "entry_kind": kind,
                "entry_id": entry_id,
                "dirty_file_hash": dict(_UNMEASURED_WT_STATE),
                "existing_backup": None,
                "backup_search_paths": [],
                "inventory_error": {"class": type(exc).__name__, "detail": safe_str(exc)},
            }

    stash_raw = list_stash_entries(root)
    stash_entries = [_isolated("stash", e["ref"],
                               lambda e=e: build_stash_entry(root, backup_root, e["ref"], e["message"]))
                     for e in stash_raw]

    wt_raw = list_worktree_entries(root)
    wt_entries = [_isolated("worktree", w.get("path"),
                            lambda w=w, idx=idx: build_worktree_entry(root, backup_root, w, index=idx))
                  for idx, w in enumerate(wt_raw)]

    entries = _json_safe(stash_entries + wt_entries)
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
        diag("custody_sweep inventory: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    # T140 Round 10 review finding B1 (fixed here): WITHOUT `--out`, the
    # verdict DOCUMENT ITSELF (`text`) is this subcommand's ONLY delivery
    # channel -- its PRIMARY output, never a mere diagnostic. Printed via
    # `emit_result`, never `diag`: a write/flush failure here (live-
    # reproduced: `inventory --repo-root big > /dev/full` on a 60-stash
    # repo whose inventory JSON is 29,235 bytes) MUST be reported as an
    # honest, non-zero exit -- the retired `diag`-everywhere shape
    # (`_safe_print`) swallowed this failure and returned rc=0 with
    # NOTHING delivered, a section 11.4 PASS-bluff. WITH `--out`, the real
    # verdict already landed durably in that file -- this line is then a
    # genuine, best-effort summary, unchanged from before, via `diag`.
    if a.out:
        diag("custody_sweep inventory: %d stash + %d worktree entries -> %s"
             % (len(stash_entries), len(wt_entries), a.out))
        return 0
    try:
        emit_result(text.rstrip("\n"))
    except Exception as exc:
        diag("custody_sweep inventory: cannot deliver the inventory verdict to stdout "
             "(--out was not given, so stdout is this invocation's ONLY delivery channel): "
             "%s: %s" % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
        return 2
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
        diag("custody_sweep propose: --inventory %r unreadable or not valid JSON: %s" % (a.inventory, exc),
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
        diag("custody_sweep propose: --inventory %r top-level value is not a JSON object "
              "(got %s: %r)" % (a.inventory, type(inv).__name__, inv), file=sys.stderr)
        return 2

    entries = inv.get("entries")
    if entries is None:
        diag("custody_sweep propose: --inventory %r has no 'entries' array" % a.inventory, file=sys.stderr)
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
        diag("custody_sweep propose: --inventory %r field 'entries' must be a JSON list "
              "(got %s: %r)" % (a.inventory, type(entries).__name__, entries), file=sys.stderr)
        return 2

    shape_error = _validate_propose_entries_shape(entries)
    if shape_error is not None:
        diag("custody_sweep propose: --inventory %r has a malformed entry: %s"
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
        diag("custody_sweep propose: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    # T140 Round 10 review finding B1 (fixed here): see `cmd_inventory`'s
    # own identical comment above -- WITHOUT `--out`, `text` is this
    # subcommand's ONLY delivery channel, so it goes through `emit_result`
    # (never `diag`), and a failure to deliver it is an honest, non-zero
    # exit, never a swallowed rc=0 (live-reproduced on a 60-stash repo
    # whose proposal JSON is 13,728 bytes: `propose ... > /dev/full`).
    if a.out:
        diag("custody_sweep propose: %d proposal(s) (%d allowed, %d refused) -> %s"
             % (len(proposals), body["counts"]["allowed"], body["counts"]["refused"], a.out))
        return 0
    try:
        emit_result(text.rstrip("\n"))
    except Exception as exc:
        diag("custody_sweep propose: cannot deliver the proposal verdict to stdout "
             "(--out was not given, so stdout is this invocation's ONLY delivery channel): "
             "%s: %s" % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
        return 2
    return 0


# ---------------------------------------------------------------------------
# Subcommand: verify-proposal
# ---------------------------------------------------------------------------
REQUIRED_PROPOSAL_KEYS = ("entry_kind", "entry_id", "action")


def cmd_verify_proposal(a):
    try:
        root = resolve_repo_root(a.repo_root)
    except RuntimeError as exc:
        diag("custody_sweep verify-proposal: %s" % exc, file=sys.stderr)
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
        diag("custody_sweep verify-proposal: --proposal %r unreadable or not valid JSON: %s"
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
        diag("custody_sweep verify-proposal: --proposal %r top-level value is not a JSON "
              "object (got %s: %r)" % (a.proposal, type(d).__name__, d), file=sys.stderr)
        return 2

    missing = [k for k in REQUIRED_PROPOSAL_KEYS if k not in d]
    if missing:
        diag("custody_sweep verify-proposal: --proposal %r missing required key(s): %s"
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
            diag("custody_sweep verify-proposal: --proposal %r field `%s` must be a JSON "
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
        diag("custody_sweep verify-proposal: cannot write --out %s: %s" % (a.out, exc), file=sys.stderr)
        return 2
    if a.out:
        diag("custody_sweep verify-proposal: %s %s (%s) -> %s"
              % (d.get("entry_id"), verdict, detail, a.out))
    else:
        # T140 Round 10 review finding B1 (fixed here): see `cmd_inventory`'s
        # own identical comment above -- WITHOUT `--out`, `text` is this
        # subcommand's ONLY delivery channel, so it goes through
        # `emit_result` (never `diag`), and a failure to deliver it is an
        # honest, non-zero exit, never a swallowed rc=0/rc=1 that silently
        # omits the verdict text entirely.
        try:
            emit_result(text.rstrip("\n"))
        except Exception as exc:
            diag("custody_sweep verify-proposal: cannot deliver the verify-proposal verdict to "
                 "stdout (--out was not given, so stdout is this invocation's ONLY delivery "
                 "channel): %s: %s" % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
            return 2
    if disagreement:
        diag("custody_sweep verify-proposal: WARNING: %s" % disagreement, file=sys.stderr)
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
            with open(tracked, "wb") as fh:
                fh.write(b"baseline content\r\n")
            _run(["git", "-C", repo, "add", "tracked.txt"], check=True, env=scratch_env)
            _run(["git", "-C", repo, "commit", "--quiet", "-m", "selftest baseline"],
                 check=True, env=scratch_env)
            # T140 Round 11 review finding B1 scenario 5 (fixed here): the
            # PRIOR version of this check retired the scratch repo's OWN
            # main checkout (`worktree_entry_id(repo, repo)` -> "MAIN") and
            # called that the golden-GOOD case -- i.e. the selftest was
            # validating exactly the case that must be REFUSED. The golden-
            # good case is now a genuine LINKED worktree of the scratch
            # repo, dirtied, retired against `repo` (its main) as root.
            linked = os.path.join(tmp, "linked_wt")
            _run(["git", "-C", repo, "worktree", "add", "--quiet", "-b", "selftest-linked", linked],
                 check=True, env=scratch_env)
            # CRLF content (B1 scenario 2): a text-mode read would rewrite
            # these bytes, so this golden-good case only passes when the
            # whole pipeline is genuinely byte-faithful.
            with open(os.path.join(linked, "tracked.txt"), "wb") as fh:
                fh.write(b"baseline content\r\nlive dirty edit\r\n")
            dirty_state, diff_bytes = worktree_dirty_state(linked, env=scratch_env)
        except (OSError, RuntimeError) as exc:
            return "REFUSED", ("scratch selftest setup raised %s: %s -- an internal setup failure is "
                                "never silently read as ALLOWED") % (type(exc).__name__, exc)
        if dirty_state.get("status") != "dirty" or not diff_bytes:
            return "REFUSED", ("scratch selftest setup failed to produce a dirty worktree (status=%r) "
                                "-- an internal setup failure is never silently read as ALLOWED"
                                % dirty_state.get("status"))
        backup_path = os.path.join(tmp, "backup.patch")
        # Bytes mode (B1 item 6): the backup is the exact raw patch bytes.
        with open(backup_path, "wb") as fh:
            fh.write(diff_bytes)
        with open(backup_path, "rb") as fh:
            backup_hash = sha256_of_bytes(fh.read())
        entry_id = worktree_entry_id(linked, repo)
        if entry_id == "MAIN":
            return "REFUSED", "scratch selftest setup resolved the linked worktree as MAIN -- setup defect"
        verdict, detail = derive_verdict("retire", backup_hash, backup_path, repo,
                                         entry_kind="worktree", entry_id=entry_id, env=scratch_env)
        if verdict != "ALLOWED":
            return verdict, detail
        # T140 Round 11 review finding B2 (fixed here): the checked-in
        # `proposal_golden_bad_wrong_hash.json` fixture is refused only
        # because its backup path does not exist on this host -- it never
        # REACHES the hash comparison. These two golden-bad cases reuse the
        # live, otherwise-ALLOWED scratch state so each refusal can only
        # come from the specific check it names (the detail is asserted).
        for label, claimed_hash, must_contain in (
                ("wrong-hash", "0" * 64, "does not match the real sha256"),
        ):
            v, d = derive_verdict("retire", claimed_hash, backup_path, repo,
                                  entry_kind="worktree", entry_id=entry_id, env=scratch_env)
            if v != "REFUSED" or must_contain not in d:
                return "REFUSED", ("selftest golden-bad %s FAILED: got %s (%s), expected REFUSED naming "
                                    "%r" % (label, v, d, must_contain))
        with open(os.path.join(linked, "tracked.txt"), "ab") as fh:
            fh.write(b"edit made AFTER the backup\r\n")
        v, d = derive_verdict("retire", backup_hash, backup_path, repo,
                              entry_kind="worktree", entry_id=entry_id, env=scratch_env)
        if v != "REFUSED" or "freshly re-derived LIVE" not in d:
            return "REFUSED", ("selftest golden-bad stale-backup FAILED: got %s (%s), expected REFUSED by "
                                "the live-content comparison" % (v, d))
        # Negative control inside the SAME scratch repo: an identically-
        # backed-up retire of the MAIN checkout must be REFUSED, or the
        # ALLOWED above proves nothing about the is_main gate.
        with open(tracked, "wb") as fh:
            fh.write(b"baseline content\r\nmain dirty edit\r\n")
        _st, main_bytes = worktree_dirty_state(repo, env=scratch_env)
        main_backup = os.path.join(tmp, "main_backup.patch")
        with open(main_backup, "wb") as fh:
            fh.write(main_bytes)
        main_verdict, main_detail = derive_verdict(
            "retire", sha256_of_bytes(main_bytes), main_backup, repo,
            entry_kind="worktree", entry_id="MAIN", env=scratch_env)
        if main_verdict != "REFUSED":
            return "REFUSED", ("selftest negative control FAILED: retiring the scratch repo's MAIN "
                                "checkout was %s (%s) -- the is_main gate is not working"
                                % (main_verdict, main_detail))
        return verdict, detail


def cmd_selftest(a):
    root = resolve_repo_root(a.repo_root)
    fixdir = a.fixtures_dir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "custody_sweep")
    fixdir = os.path.abspath(fixdir)

    # Control needle first (section 11.4.273 / C-004): a known-present
    # fixture file must resolve before any absence below is trusted.
    known_present = os.path.join(fixdir, SELFTEST_FIXTURES[0][0])
    if not os.path.isfile(known_present):
        diag("custody_sweep selftest: control needle FAILED -- known-present fixture "
              "%r does not resolve; fixtures_dir may be wrong" % known_present, file=sys.stderr)
        return 3
    fabricated = os.path.join(fixdir, "definitely_never_shipped_fixture_xyz.json")
    if os.path.isfile(fabricated):
        diag("custody_sweep selftest: control needle FAILED -- a fabricated fixture name "
              "unexpectedly exists; the fixtures_dir is not what this tool expects", file=sys.stderr)
        return 3
    diag("custody_sweep selftest: control needle OK (known-present resolves, fabricated absent)")

    ok = True
    for fname, expected in SELFTEST_FIXTURES:
        fpath = os.path.join(fixdir, fname)
        if not os.path.isfile(fpath):
            diag("custody_sweep selftest: fixture %r is MISSING" % fpath, file=sys.stderr)
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
            diag("custody_sweep selftest: ok %s -> %s (%s)" % (fname, verdict, detail))
        else:
            diag("custody_sweep selftest: NOT ok %s -> %s, expected %s (%s)"
                  % (fname, verdict, expected, detail), file=sys.stderr)
            ok = False

    if not ok:
        return 3

    # Discrimination needle (section 11.4.107(10) / 11.4.201(1)): the
    # REFUSED-expected and ALLOWED-expected fixtures must genuinely diverge.
    refused = {f for f, e in SELFTEST_FIXTURES if e == "REFUSED"}
    allowed = {f for f, e in SELFTEST_FIXTURES if e == "ALLOWED"}
    if not refused or not allowed:
        diag("custody_sweep selftest: discrimination needle FAILED -- fixture set has no "
              "both-sides coverage", file=sys.stderr)
        return 3
    diag("custody_sweep selftest: ALL %d fixture(s) resolved correctly; REFUSED/ALLOWED genuinely "
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
                diag("custody_sweep: determinism-check run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode not in (0, 1) or not os.path.exists(out_i):
                # T140 Round 10 review finding I1(c) (fixed here): see
                # `handoff.py`'s own identically-purposed sibling fix for
                # the full rationale.
                diag(proc.stderr, end="", file=sys.stderr)
                diag("custody_sweep: determinism-check run %d rc=%d, no honest verdict"
                      % (i, proc.returncode), file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                runs.append(json.load(fh).get("body_hash"))
    if runs[0] is None or runs[0] != runs[1]:
        diag("custody_sweep: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]), file=sys.stderr)
        return 1
    diag("custody_sweep: deterministic (body_hash=%s)" % runs[0])
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
    #
    # T140 Round 10 review finding I1(a) (fixed here): `FcArgumentParser`
    # -- see `fc_entry.FcArgumentParser`'s own docstring for the full
    # rationale (closes the ONE remaining raw-write path into
    # argparse-owned `--help`/usage-error message printing).
    p = FcArgumentParser(prog="custody_sweep.py", description=(__doc__ or "").split("\n\n")[0])
    # T140 Round 13 (round-12 finding M-2): surfaced in --help itself, not
    # only in the module docstring a caller may never read. (Set as an
    # attribute so the constructor line above keeps the exact shape the
    # round-9 regression guard mutates.)
    p.epilog = ("Exit codes: 0 ALLOWED/success, 1 finding (REFUSED or expected_verdict "
                "disagreement), 2 usage/configuration error, 3 selftest failed, 4 "
                "--determinism-check had no honest verdict. Consumers MUST gate on the exit "
                "code, never on --out's mere presence: a usage error leaves a stale --out "
                "untouched and a stale --out is not distinguishable from a fresh one by content.")
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
    `str(exc)` also replaced with `safe_str(exc)` (R9-M1)."""
    if not out_path:
        return
    body = {
        "subcommand": subcommand,
        "internal_error": {"class": type(exc).__name__, "detail": safe_str(exc)},
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
            diag("custody_sweep.py: --determinism-check raised an uncaught %s: %s -- this is a "
                  "genuinely unanticipated case; treat as unsafe/unverified until independently, "
                  "manually re-verified" % (type(exc).__name__, safe_str(exc)), file=sys.stderr)
            return 2

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
        # T140 Round 11 review finding I3 (fixed here): once argv has PARSED, this
        # invocation's --out is genuinely this run's designated output -- a stale
        # document from an earlier run must not survive ANY handled exit below (a
        # rc=1 refusal / rc=2 config error that writes nothing used to leave the
        # PREVIOUS run's verdict there, looking current; C-001). A pure argparse
        # usage error (SystemExit before this line) still leaves --out untouched,
        # per Round 10 finding M3 (guarded by the r9 regression suites).
        invalidate_stale_out(getattr(args, "out", None))
        if args.subcommand is None:
            diag("custody_sweep.py: a subcommand is required "
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
        # `diag` (never able to escape and corrupt an already-
        # written --out doc, or exit 120 on a closed stderr, R9-I1's own
        # fix). `out_path` resolves honestly even in the (currently
        # unreachable for THIS specific except clause, since `args` is
        # always bound by the time a RuntimeError can be raised from the
        # subcommand dispatch above -- but resolved the SAME defensive
        # way as the `except Exception` clause immediately below, for
        # consistency and future-proofing) case `args` is None.
        #
        # T140 Round 10 review finding M3, first half (fixed here): the
        # pre-invalidation this file's own `main()` used to run
        # UNCONDITIONALLY at the very top is now made ONLY here (and in
        # the `except Exception` clause immediately below) -- see
        # `handoff.py`'s own identically-purposed sibling fix for the full
        # rationale.
        out_path = getattr(args, "out", None) if args is not None else scan_argv_for_out(argv)
        subcommand = getattr(args, "subcommand", None) if args is not None else None
        invalidate_stale_out(out_path)
        _write_dispatch_internal_error_doc(out_path, subcommand, exc)
        diag("custody_sweep.py: %s" % safe_str(exc), file=sys.stderr)
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
        #
        # T140 Round 10 review finding M3 (fixed here): pre-invalidation
        # now happens ONLY here too -- see the `except RuntimeError`
        # clause's own comment immediately above for the full rationale.
        out_path = getattr(args, "out", None) if args is not None else scan_argv_for_out(argv)
        subcommand = getattr(args, "subcommand", None) if args is not None else None
        invalidate_stale_out(out_path)
        _write_dispatch_internal_error_doc(out_path, subcommand, exc)
        diag("custody_sweep.py: subcommand %r raised an uncaught %s while dispatching: %s -- this "
              "is a genuinely unanticipated case no individual fix above enumerated; treat as "
              "unsafe/unverified until independently, manually re-verified"
              % (subcommand, type(exc).__name__, safe_str(exc)), file=sys.stderr)
        return 2

    diag("custody_sweep.py: unknown subcommand %r" % args.subcommand, file=sys.stderr)
    return 2


if __name__ == "__main__":
    # T140 Round 10 review, "Recommended root-cause work" item 1 (fixed
    # here): `run_cli_main` -- see `handoff.py`'s own identically-purposed
    # sibling fix for the full mechanism.
    run_cli_main(main, sys.argv[1:])
