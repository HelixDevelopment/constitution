#!/bin/bash
# baseline_replay.sh - SC-002/SC-005 gate-replay harness (spec-004
# "fast-dev-cycles", User Story 1, T043; plan.md T-A10, T-H02;
# contracts/common-conventions.md C-001..C-007). Guarded by
# constitution/scripts/fastcycle/tests/test_baseline_replay_red.sh (T024).
#
# Purpose: given a sample item (or a select_sample.py output doc), FREEZE
# its "relevant work landed here" commit + tree hash, then REPLAY a
# caller-named gate command against an isolated checkout of that frozen
# commit, >=N times cold and >=N times warm, recording per-run timing +
# verdict + per-type medians -- the T-A10 "before" baseline every later
# SC-002 (gate speed) / SC-005 (cycle-time) claim in this initiative is
# measured against. This is an OPEN-GAP tool (contracts/common-
# conventions.md's own "Tool map" note lists "$FC/cycle/baseline_replay.sh
# (T-A10/T-H02)" among the tools no contract in that directory covers --
# "their interface, output and RED fixtures are fixed by the plan task
# text until a contract is written"); this script follows plan.md T-A10's
# own text plus C-001..C-007.
#
# =============================================================================
# FOUR SUBCOMMANDS
# =============================================================================
#   freeze --item ID [--repo-root DIR] [--db-path PATH] --out PATH
#       Resolve ID's frozen {commit, tree} via subject-only `git log`
#       search (see FREEZE MECHANISM below). Read-only, zero disk writes
#       beyond --out.
#   selfcheck --out PATH
#       C-004 control-needle self-test for THIS script's OWN verdict
#       classification (a real `true` MUST classify PASS, a real `false`
#       MUST classify FAIL) -- run automatically, inline, before every
#       `replay`; exposed standalone so a caller can verify the instrument
#       in isolation. Exit 3 on failure (C-001 row 3).
#   replay --commit SHA --tree SHA --gate-cmd "CMD..." [--cold-runs 10]
#       [--warm-runs 10] [--repo-root DIR] [--worktree-root DIR]
#       [--min-free-kb K] [--min-free-kb-objects K] [--timeout-s N] --out PATH
#       Isolate a `git worktree` checkout of SHA (see DISK SAFETY below),
#       run CMD inside it cold-runs+warm-runs times sequentially, record
#       per-run {start_ns,end_ns,duration_ms,exit_code,verdict}, remove the
#       worktree (always, via trap), write the canonical report.
#   replay-sample --sample PATH --gate-cmd "CMD..." [--cold-runs 10]
#       [--warm-runs 10] [--repo-root DIR] [--worktree-root DIR]
#       [--min-free-kb K] [--timeout-s N] --out PATH
#       Read a select_sample.py (T043 sibling) output doc's `items` array;
#       for each, freeze then replay; an item whose freeze is UNMEASURED
#       is SKIPPED with the reason recorded (never silently dropped,
#       DEC-03's own "never silently dropped" language applied here);
#       aggregate per-type medians.
#
# =============================================================================
# FREEZE MECHANISM (design judgment call, documented per task instruction)
# =============================================================================
# "The exact commit the item's relevant work landed on" is resolved by
# reusing `$FC/cycle/cycle_report.py`'s (T041, already reviewed)
# `git_subject_matches()` definition VERBATIM, reimplemented here in shell:
# `git log --all -i --grep=<id> --pretty=format:%H|%aI|%cI|%s`, filtered in
# a second pass to lines whose SUBJECT (4th field, not the full message
# git --grep searches) literally contains the item id -- git's own --grep
# matches the full commit message, and a body-only mention is materially
# weaker evidence of "this IS the commit" than a subject mention (verified
# 2026-09-28 against this exact repo: `git log --all -i --grep=ATM-953`
# returns 3 commits, only 1 of which -- f1abb59e, subject "...ATM-953
# video-to-TV..." -- names ATM-953 in its subject; the other 2 are
# body-only mentions of an UNRELATED change). Of the surviving subject
# matches, the LATEST by author date is chosen (matches cycle_report.py's
# own `commit_push` stage END instant -- the commit that closed out the
# item's commit-push activity is the natural "landed here" point). Verified
# live 2026-09-28: ATM-953 -> commit f1abb59eac851e560a49b9fb4465297f84d66bae,
# tree 7160a3865cfeb4922f18530239921c2870d45185 (matches its own
# Fixed/2026-07-28 closure date exactly). Zero surviving subject matches ->
# UNMEASURED (exit 0 from `freeze`; the ABSENCE of a resolvable commit is
# an honest, correctly-recorded result, not an error -- matching
# cycle_report.py's own UNMEASURED-is-legitimate convention), never a
# silent fall-back to HEAD or any other guessed commit (S11.4.6).
#
# =============================================================================
# DISK SAFETY (a genuine host-safety finding made while designing this
# tool, documented in full because it changes the tool's own defaults --
# S11.4.6/S12.6)
# =============================================================================
# Two measurements taken directly against THIS host before writing this
# script's worktree-creation logic:
#   (1) `git worktree add` for THIS project materialises a FULL checkout of
#       every tracked file at the target commit. Measured directly against
#       one of this repo's OWN pre-existing agent worktrees
#       (.claude/worktrees/agent-a17eb3df7db2f148a, excluding its .git):
#       49 GB. This repo's root filesystem (/mnt/track1, mapper
#       track_crypt1) had 108 GB free at measurement time, with THREE such
#       worktrees already present (~147 GB already committed to them) --
#       creating a FOURTH full checkout for a mere bounded/representative
#       demonstration would be a real, avoidable host-disk-exhaustion risk
#       (S12.6), not a reasonable default for anything short of a genuine
#       T045 production run.
#   (2) `/tmp` on this host is `tmpfs` -- RAM-BACKED, not disk-backed --
#       measured at 126 GB total / 101 GB already used / 25 GB free at
#       measurement time. Defaulting `--worktree-root` under `/tmp` (a
#       tempting, "obviously scratch" choice) would therefore risk WRITING
#       A MULTI-GIGABYTE CHECKOUT INTO RAM, exactly the class of host-
#       session-safety disaster this project's own Constitution S12
#       documents multiple forensic OOM incidents about.
# Consequence for THIS script's defaults: `--worktree-root` defaults to
# `<repo-root>/.fc_worktrees` (a sibling of the EXISTING, already-
# precedented `.claude/worktrees/` pattern this exact repo already uses --
# `git worktree list` shows three such worktrees today -- confirmed
# disk-backed, same filesystem as the repo itself, NEVER tmpfs); a caller
# pointing `--worktree-root` at a known-disk-backed `/tmp` on a DIFFERENT
# host may still do so explicitly. `--min-free-kb` (default:
# DEFAULT_MIN_FREE_KB = 67 GiB = 70254592 KiB, derived from the two
# measurements this file documents -- ~49 GiB superproject checkout + ~7.4
# GiB submodules -- plus 10 GiB headroom; T048 restart round 1, R6-F10: the
# earlier 10 GiB default was five times smaller than the checkout it guards;
# operator-tunable for a different project) is checked
# via `df -Pk` against the worktree-root's OWN filesystem immediately
# before every `git worktree add`; insufficient free space REFUSES (exit
# 4, BLIND -- "could not measure", never a silent skip of the check) with
# the real `df` numbers printed, before any checkout is attempted. T048 restart
# round 2 (V4-4): submodule objects a replay fetches land under
# <git-common-dir>/worktrees/<n>/modules, i.e. on the filesystem of the git
# object store, which need not be the --worktree-root filesystem; that
# filesystem is checked too, against --min-free-kb-objects (default
# DEFAULT_MIN_FREE_KB_OBJECTS = 18 GiB: ~7.4 GiB of submodule objects rounded up
# to 8 + 10 GiB headroom). Both checks, the worktree add and every run happen
# under exclusive locks per repository AND per filesystem (T048 restart round 3,
# V4R3-6: the round-2 per-repository lock let replays of two DIFFERENT
# repositories on one filesystem both pass the check), so two replays by this
# user can never both pass the check of one filesystem and then together
# exhaust it; a second replay is refused (exit 4) while the first runs. HONEST
# BOUNDARY: replays by different users (per-user lock directory) are not
# serialised against each other.
#
# =============================================================================
# COLD vs WARM (honest boundary, S11.4.6 -- stated per task instruction)
# =============================================================================
# T-A10's own text: "replay ... >=10 times cold and >=10 times warm ...
# Token baseline...". Investigated 2026-09-28: `$FC/gates/verdict_cache.py`
# (T068, the ONLY app-level caching mechanism plan.md names anywhere in
# this initiative) does NOT exist in this tree yet (US2, a LATER user
# story). With no cache mechanism to warm, this script's `cold` and `warm`
# phases are, RIGHT NOW, mechanically IDENTICAL operations (same gate
# command, same frozen worktree, run sequentially) -- the only difference
# either phase could exhibit today is the OS's own filesystem page cache,
# which this script does NOT attempt to control (no `posix_fadvise`/cache-
# drop step) since doing so would need root and is out of this task's
# scope. This is recorded HONESTLY in every `replay`/`replay-sample`
# report's `cache_mechanism` field rather than silently pretending a real
# distinction exists. Once T068 lands, `--gate-cmd` (or a companion
# `--warm-cmd`) is this script's existing hook point for a real cache-
# warm-up step -- no interface change needed then.
#
# =============================================================================
# EXIT CODES (C-001's uniform table)
# =============================================================================
# 0 report written (a per-run gate FAIL is recorded DATA, not a harness
#   exit-code failure -- this script measures gate outcomes, it does not
#   itself judge them); 1 `--determinism-check` genuinely differs -- the
#   two internal re-runs of the SAME frozen {commit, tree, gate-cmd} this
#   script itself performs (C-003; NOT a delegation to fc_common.py's
#   generic byte-identical wrapper -- see DETERMINISM below) produced
#   different `verdict_set`s, a real determinism defect (S11.4.50); 2
#   usage/config error; 3 selfcheck (C-004 control needle) failed -- the
#   verdict-classification instrument is not trustworthy this run,
#   nothing else runs; 4 BLIND -- git failed or commit/tree unresolvable,
#   worktree/submodule creation failed, disk pre-flight refused, tracker DB
#   present but unreadable, a gate run that could not be STARTED
#   (HARNESS_ERROR; the report is still written), any replay-sample item that
#   could not be measured for a harness reason (report still written),
#   --determinism-check runs that never completed (deterministic=null), or
#   another replay holding a lock; 128+N the tool was stopped by signal N (sent
#   to the main pid, the supervisor, the worker or their process group) -- no
#   report is written, the run-log directory is marked INTERRUPTED.
#   Verdicts per run (closed set): PASS | FAIL | UNMEASURED | HARNESS_ERROR,
#   see classify_run(); median_ms is over PASS runs only (R6-F9).
#
# =============================================================================
# DETERMINISM (C-003; T024 RED-test contract stub 1/3) -- HONEST BOUNDARY,
# a real design correction made after directly testing the first draft
# =============================================================================
# `replay`'s report embeds REAL wall-clock measurements (start_ns/end_ns/
# duration_ms/median_ms) inside its hashed body -- that data is
# INHERENTLY non-deterministic between two separate invocations (real
# timing jitter always differs), so this tool does NOT compose with
# fc_common.py's generic byte-identical-`body_hash` `determinism-check`
# the way cycle_report.py / select_sample.py's own timing-free bodies
# correctly do -- verified directly: an earlier draft that DID delegate
# to the generic mechanism reported "nondeterministic" on its very first
# real run against a real scratch repo (2026-09-28), even though nothing
# was actually wrong. T024's own RED-test contract stub 1/3 already says
# what THIS tool's determinism means: "two independent invocations ...
# MUST produce the SAME verdict SET (per-item PASS/FAIL/SKIP
# classification, compared as a set, never merely as equal counts)".
# `replay --determinism-check` therefore runs the SAME frozen
# {commit, tree, gate-cmd} TWICE internally and compares ONLY the two
# runs' `verdict_set` fields (never the timing fields); exit 0 = both
# invocations give one identical verdict per phase, exit 1 = genuinely
# differs (a real determinism defect, S11.4.50) -- including a phase whose
# verdict set holds MORE than one verdict inside a single invocation (a
# within-run flake, T048 restart round 1 R6-F7), exit 4 = some run never
# completed or never started (no determinism verdict, deterministic=null);
# zero runs are refused (exit 2). Both verdict sets are printed either way
# AND (as of T043 round-2 review finding N5) writing the same
# `baseline-replay-determinism/v1` document to the mandatory `--out`
# PATH every other subcommand already writes to.
#
# =============================================================================
# SAFETY (C-006)
# =============================================================================
# Read-only on the CALLER's live working tree at all times: every
# checkout happens in an isolated `git worktree`, never `git checkout`/
# `reset`/`stash`/`clean` against the repo the caller invoked this script
# from. Worktree cleanup (`git worktree remove --force`, needed because
# the replayed gate may leave scratch files inside its own checkout) is
# unconditional, and nothing the tool starts outlives it (S11.4.14, leave the
# target quiescent). T048 restart round 3 (STRUCTURAL, V4R3-1..14): after three
# rounds in which every added stop mechanism (traps, TERM forwarding, a session
# and token per gate, a /proc environ scan, poll-then-KILL, an inherited lock
# fd) brought new gaps -- the last one: a SIGKILL of the main pid left the run
# loop executing every remaining scheduled run -- all of it is replaced by ONE
# supervisor, cycle/fc_supervisor.py, which owns every descendant by
# construction (child subreaper + PDEATHSIG chain + pidfd-only signalling) and
# stops the whole tree whatever stopped the tool (see "PROCESS SUPERVISION"
# below and the supervisor's docstring, which states its one honest boundary:
# both supervisor processes SIGKILLed at the same moment). Replays are
# serialised per repository AND per filesystem (see _fc_supervise), and every
# temp file lives in one private directory the supervisor removes.
#
# HONEST BOUNDARY (S11.4.6): `--gate-cmd "CMD..."` is a single string this
# script word-splits on whitespace (parse_gate_cmd: `read -r -a`, with NO
# pathname expansion -- T048 restart round 1 replaced the earlier unquoted
# expansions, which also glob-expanded each word) into an argv array before
# exec'ing it -- CMD and every one of its own arguments MUST NOT contain
# embedded whitespace (e.g. a path with a space in it). This is a real,
# stated limitation, not a silent one; every sibling $FC tool that accepts
# a shell command string (this is the first) will need the same note or a
# genuine array-CLI redesign once a caller hits it.
#
# Dependencies: bash (arrays), git, python3 >= 3.9 (stdlib only -- JSON
# assembly + fc_common's canon/body_hash_of, matching every sibling $FC tool,
# and the process supervisor, which needs os.pidfd_open / pidfd_send_signal:
# Linux >= 5.3), coreutils `date`/`df`; Linux /proc with
# /proc/<pid>/task/<tid>/children.
set -u

# --- resolve this script's own directory, independent of caller's cwd ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_REPO_ROOT="$(cd "$FC/../../.." && pwd)"

die() { echo "baseline_replay: $*" >&2; exit 2; }
blind() { echo "baseline_replay: BLIND: $*" >&2; exit 4; }

isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }

usage() {
  cat >&2 <<'EOF'
Usage:
  baseline_replay.sh freeze --item ID [--repo-root DIR] [--db-path PATH] --out PATH
  baseline_replay.sh selfcheck --out PATH
  baseline_replay.sh replay --commit SHA --tree SHA --gate-cmd "CMD..."
      [--cold-runs N] [--warm-runs N] [--repo-root DIR] [--worktree-root DIR]
      [--min-free-kb K] [--min-free-kb-objects K] [--timeout-s N] --out PATH
      [--determinism-check]
  baseline_replay.sh replay-sample --sample PATH --gate-cmd "CMD..."
      [--cold-runs N] [--warm-runs N] [--repo-root DIR] [--worktree-root DIR]
      [--min-free-kb K] [--min-free-kb-objects K] [--timeout-s N] --out PATH
EOF
  exit 2
}

[ $# -ge 1 ] || usage
SUBCMD=$1; shift
ORIG_ARGS=("$@")
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------------------
# now_ns -- date +%s%N, validated all-decimal (matches fc_timer.sh's own
# _fc_timer_now_ns convention exactly, for cross-tool consistency).
# ---------------------------------------------------------------------------
now_ns() {
  local ns
  ns="$(date +%s%N 2>/dev/null)" || { echo "baseline_replay: 'date +%s%N' failed" >&2; return 2; }
  case "$ns" in ''|*[!0-9]*) echo "baseline_replay: 'date +%s%N' produced a non-numeric timestamp ('$ns') -- needs GNU date" >&2; return 2 ;; esac
  printf '%s' "$ns"
}

# ---------------------------------------------------------------------------
# Disk floor default (T048 restart round 1, R6-F10). The DISK SAFETY section
# above and the submodule comment in do_one_replay() document a full checkout of
# this project at ~49 GiB plus ~7.4 GiB of submodules. The earlier 10 GiB
# default was 5x below that, so the check passed with far too little room and
# the checkout itself could exhaust the disk. Derivation: 49 GiB + 8 GiB
# (7.4 rounded up) + 10 GiB headroom = 67 GiB = 67 * 1048576 KiB. Still a
# caller-tunable flag: a different project passes its own measured size.
# ---------------------------------------------------------------------------
DEFAULT_MIN_FREE_KB=70254592
# T048 restart round 2 (V4-4): floor for the filesystem of the git object store
# (submodule objects): 8 GiB (7.4 rounded up) + 10 GiB headroom = 18 GiB.
DEFAULT_MIN_FREE_KB_OBJECTS=18874368

# ---------------------------------------------------------------------------
# PROCESS SUPERVISION (T048 restart round 3, STRUCTURAL -- replaces the round-1/2
# traps, TERM forwarding, per-gate sessions, per-run tokens, /proc environ scan
# and poll-then-KILL; docs/qa/t048_restart_round3_20261008/V4_baseline.md).
#
# `replay`, `replay-sample` and `selfcheck` never do their work in the process
# the caller started. After the arguments are validated, _fc_supervise `exec`s
# fc_supervisor.py (same pid): it takes the replay locks, creates the private
# temp directory and runs THIS script again as the worker, under a keeper
# process that owns every descendant by construction (PR_SET_CHILD_SUBREAPER,
# pidfd-only signalling, PDEATHSIG chain -- see fc_supervisor.py's docstring for
# the layout and its one honest boundary). Whatever stops the tool -- a signal
# to the main pid, the supervisor, the worker or a process group, a SIGKILL of
# the main pid, the worker's own exit -- the supervisor stops the whole tree,
# then removes the worktrees / marks the run-log directories still listed in the
# ledger, then removes the temp directory. The worker therefore has no cleanup
# traps at all: a stop signal simply ends it (exit 128+N).
#
# Every long-running child of the worker (a gate run, `git worktree add` and its
# hooks, the submodule update) runs under `fc_supervisor.py run`
# (_fc_run_child), which bounds it with --timeout-s and stops whatever it left
# running before it returns. It is started in the background and `wait`ed for,
# so a stop signal to the worker is acted on at once (bash defers a trapped
# signal only until the CURRENT foreground command ends; `wait` is interrupted).
# ---------------------------------------------------------------------------
_FC_TMPDIR=""
_FC_SUPERVISOR="$SCRIPT_DIR/fc_supervisor.py"
_FC_ENTRY_SIGIGN=0
_fc_mktemp() { mktemp "$_FC_TMPDIR/f.XXXXXX"; }
# freeze only (it starts no child that could outlive it): a private temp dir
# removed by the EXIT trap
# shellcheck disable=SC2329 # invoked from the EXIT trap string installed in the dispatch
_fc_rm_tmpdir() {
  case "$_FC_TMPDIR" in */fc_baseline_replay.*) rm -rf -- "$_FC_TMPDIR" ;; esac
  return 0
}

# FC_BR_STOP_GRACE_S: seconds between SIGTERM and SIGKILL when a stop has to end
# a process (default 10).
_FC_GRACE="${FC_BR_STOP_GRACE_S:-10}"
isnum "$_FC_GRACE" || die "FC_BR_STOP_GRACE_S must be a non-negative integer"

# _fc_supervise REPO_ROOT WORKTREE_ROOT: in the process the caller started,
# hand over to the supervisor (exec, never returns); in the worker, a no-op.
# With a REPO_ROOT the supervisor takes two kinds of exclusive, non-blocking
# locks (V4-4, V4R3-6):
#  - per repository: <git-common-dir>/fc_baseline_replay.lock (the COMMON dir,
#    so a linked worktree of the same repository is the same lock);
#  - per filesystem: <lock-dir>/fc_baseline_replay.fs-<st_dev>.lock for the
#    worktree root's filesystem and the object store's, so two DIFFERENT
#    repositories cannot both pass the free-space checks of one filesystem.
#    <lock-dir> is $FC_REPLAY_LOCK_DIR, else $XDG_RUNTIME_DIR, else /tmp -- per
#    user (HONEST BOUNDARY §11.4.6: replays by different users, or with
#    different lock dirs, are not serialised against each other).
# The lock file descriptions are O_CLOEXEC in the supervisor: no worker, gate
# or hook process ever holds them (V4R3-5).
_FC_IS_WORKER=0
_fc_supervise() {
  # a SHELL variable, never the environment (the hand-off variables are unset by
  # _fc_worker_init so that a gate which is itself an FC tool supervises itself)
  [ "$_FC_IS_WORKER" = 1 ] && return 0
  [ -f "$_FC_SUPERVISOR" ] || blind "the process supervisor $_FC_SUPERVISOR is missing -- refusing to run gates that could not be stopped completely"
  command -v python3 >/dev/null 2>&1 || blind "python3 not found -- it runs the process supervisor"
  local args=() common lockdir ign
  if [ -n "$1" ]; then
    common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    { [ -n "$common" ] && [ -d "$common" ]; } || blind "cannot resolve the git directory of --repo-root $1"
    lockdir="${FC_REPLAY_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
    args+=(--lock "$common/fc_baseline_replay.lock" --lock-dir "$lockdir" --lock-fs "$2" --lock-fs "$common")
  fi
  # The signals the CALLER ignored (nohup, ...) stay ignored everywhere. Read from
  # a CHILD (awk's own /proc/self), never /proc/$$: a non-interactive bash ignores
  # SIGQUIT internally from startup (measured: SigIgn bit 3 set in bash's own
  # status although its parent restored the default) while passing the caller's
  # ORIGINAL dispositions to every program it execs -- reading bash's own mask
  # made QUIT look "ignored by the caller" and the whole tool unstoppable by it.
  ign="$(awk '/^SigIgn:/{print $2; exit}' /proc/self/status 2>/dev/null)"
  case "$ign" in ''|*[!0-9a-fA-F]*) ign=0 ;; esac
  export FC_BR_OUT_OVERRIDE="$_FC_OUT_OVERRIDE"
  exec python3 -I "$_FC_SUPERVISOR" main --tmp-parent "${TMPDIR:-/tmp}" --entry-sigign "$ign" \
    --grace "$_FC_GRACE" "${args[@]}" -- "$BASH" "$SCRIPT_PATH" "$SUBCMD" "${ORIG_ARGS[@]}"
}

# _fc_worker_init: in the worker, take over the supervisor's hand-off variables
# (then remove them from the environment: a gate that is itself an FC tool must
# start its OWN supervisor) and make every stop signal end the worker at once.
_fc_worker_init() {
  [ "${FC_BR_SUPERVISOR_PID:-}" = "$PPID" ] || blind "FC_BR_SUPERVISED is set but this process was not started by the supervisor (parent $PPID) -- refusing to run unsupervised"
  _FC_TMPDIR="${FC_BR_TMPDIR:-}"
  case "$_FC_TMPDIR" in */fc_baseline_replay.*) ;; *) blind "the supervisor's temp directory is missing" ;; esac
  [ -d "$_FC_TMPDIR" ] || blind "the supervisor's temp directory $_FC_TMPDIR does not exist"
  _FC_ENTRY_SIGIGN="${FC_BR_ENTRY_SIGIGN:-0}"
  _FC_OUT_OVERRIDE="${FC_BR_OUT_OVERRIDE:-}"
  unset FC_BR_SUPERVISED FC_BR_TMPDIR FC_BR_SUPERVISOR_PID FC_BR_ENTRY_SIGIGN FC_BR_OUT_OVERRIDE
  _FC_IS_WORKER=1
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 131' QUIT
  trap 'exit 143' TERM
}

# _fc_run_child LOG TIMEOUT_S MARKER CWD -- CMD...: run CMD in CWD under
# `fc_supervisor.py run` (bounded by TIMEOUT_S; whatever CMD leaves running is
# stopped before this returns), stdout+stderr to LOG, stdin /dev/null. Returns
# CMD's exit code (124/137 on timeout, 125 if the run supervisor itself failed);
# MARKER receives the outcome: exited | timed_out | cd_failed | exec_failed.
_fc_run_child() {
  local log="$1" tmo="$2" mk="$3" cwd="$4"
  shift 4
  [ "${1:-}" = -- ] && shift
  python3 -I "$_FC_SUPERVISOR" run --timeout "$tmo" --kill-after 5 --grace "$_FC_GRACE" --marker "$mk" \
    --cwd "$cwd" --entry-sigign "$_FC_ENTRY_SIGIGN" -- "$@" >"$log" 2>&1 </dev/null &
  wait "$!"
}

# Ledger (see fc_supervisor.py): one file per worktree / run-log directory,
# written BEFORE the thing it names is created, removed once it is cleaned up /
# referenced by a report. _fc_ledger_add KIND FIELD... -> sets _FC_LEDGER_FILE.
_fc_ledger_add() {
  local kind="$1"
  shift
  _FC_LEDGER_FILE="$(mktemp "$_FC_TMPDIR/ledger.$kind.XXXXXX")" || return 1
  printf '%s\0' "$@" >"$_FC_LEDGER_FILE" || return 1
}

# ---------------------------------------------------------------------------
# Verdicts (closed set, T048 restart round 1, R6-F8):
#   PASS          the gate ran and exited 0
#   FAIL          the gate ran and exited non-zero (including its OWN 124/126/127)
#   UNMEASURED    the gate did not finish: killed by --timeout-s
#   HARNESS_ERROR the gate never ran: cd into the worktree failed, the command was
#                 not found / not executable (exec failed), or the run supervisor
#                 itself failed or recorded no outcome
# Whether the gate ran, and whether it timed out, is OBSERVED, never inferred from
# the exit code: `fc_supervisor.py run` writes the outcome to a marker file
# (exited | timed_out | cd_failed | exec_failed). T048 restart round 3: the
# timeout used to be inferred from "exit 124/137 after at least the limit"; a
# gate's own 124 or 137 can no longer be mistaken for a timeout (or vice versa).
# T048 restart round 2 (V4-2): an exit status >= 129 does NOT say the gate was
# killed -- "exited 128+N" and "killed by signal N" give the same number -- so it
# is a FAIL whose reason states the ambiguity and names no signal. (The round-2
# "UNMEASURED | stopped by this harness" branch is gone, V4R3-9: a run the
# harness stops is never classified -- the whole tool stops, the supervisor marks
# the run-log directory INTERRUPTED, and no report is written.)
#
# classify_run RC MARKER TIMEOUT_MS -> prints "VERDICT|reason".
# ---------------------------------------------------------------------------
classify_run() {
  local rc="$1" mk="$2" tmo_ms="$3"
  case "$mk" in
    cd_failed|exec_failed) printf 'HARNESS_ERROR|%s' "$mk"; return 0 ;;
    timed_out) printf 'UNMEASURED|timed out (exit %s, limit %sms)' "$rc" "$tmo_ms"; return 0 ;;
    exited) ;;
    *) printf 'HARNESS_ERROR|the run supervisor recorded no outcome (exit %s, marker %s)' "$rc" "${mk:-empty}"; return 0 ;;
  esac
  if [ "$rc" = 0 ]; then printf 'PASS|exit 0'; return 0; fi
  if [ "$rc" -ge 129 ]; then
    printf 'FAIL|exit %s (the gate exited %s itself, or was killed from outside this harness -- the status cannot tell which; this harness sent it nothing)' "$rc" "$rc"
    return 0
  fi
  printf 'FAIL|exit %s' "$rc"
}

# ---------------------------------------------------------------------------
# run_gate_once CWD TIMEOUT_S LOG -- CMD...
# Runs CMD once inside CWD under the run supervisor (_fc_run_child), bounded by
# TIMEOUT_S, stdout+stderr to LOG, and sets RG_START_NS RG_END_NS RG_DURATION_MS
# RG_RC RG_VERDICT RG_REASON. Returns 4 only when the clock or a temp file cannot
# be obtained (BLIND). The measured duration includes the run supervisor's own
# start-up (a Python process, tens of milliseconds) -- the same for every run.
# ---------------------------------------------------------------------------
run_gate_once() {
  local cwd="$1" tmo="$2" log="$3"
  shift 3
  [ "${1:-}" = -- ] && shift
  local marker
  marker="$(_fc_mktemp)" || { echo "baseline_replay: mktemp failed (temp directory unusable)" >&2; return 4; }
  RG_START_NS="$(now_ns)" || { rm -f "$marker"; return 4; }
  _fc_run_child "$log" "$tmo" "$marker" "$cwd" -- "$@"
  RG_RC=$?
  RG_END_NS="$(now_ns)" || { rm -f "$marker"; return 4; }
  RG_DURATION_MS=$(( (RG_END_NS - RG_START_NS) / 1000000 ))
  [ "$RG_DURATION_MS" -ge 0 ] || RG_DURATION_MS=0
  local mk=""
  [ -s "$marker" ] && mk="$(cat "$marker")"
  rm -f "$marker"
  local cls
  cls="$(classify_run "$RG_RC" "$mk" "$((tmo * 1000))")"
  RG_VERDICT="${cls%%|*}"
  RG_REASON="${cls#*|}"
  return 0
}

# ---------------------------------------------------------------------------
# selfcheck: C-004 control needle for the verdict instrument. T048 restart
# round 1 (R6-F20): it used to round-trip only the pure classifier on the exit
# codes of `true`/`false`, so the real run path (background launch, timeout,
# exec-failure detection) -- where F8 lived -- was never exercised. It now runs
# REAL gates through run_gate_once() and checks each verdict:
#   true -> PASS; false -> FAIL; a command that exits 127 itself -> FAIL;
#   a command that exits 255 itself -> FAIL (V4-2: never "signal 127");
#   a command that exits 124 itself, at once -> FAIL (round 3: a timeout is
#   observed by the run supervisor, never inferred from the number 124);
#   a command that does not exist -> HARNESS_ERROR; `sleep 5` under a 1 s
#   timeout -> UNMEASURED.
# Sets SC_CHECKS (one "name|ok|got|want" line per check); returns 0 iff all ok.
# ---------------------------------------------------------------------------
run_selfcheck() {
  SC_CHECKS=""
  local d all_ok=1
  d="$(mktemp -d "$_FC_TMPDIR/selfcheck.XXXXXX")" || { echo "baseline_replay: selfcheck: mktemp -d failed" >&2; return 1; }
  _sc_one() { # name want timeout cmd...
    local name="$1" want="$2" tmo="$3"
    shift 3
    if ! run_gate_once "$d" "$tmo" "$d/$name.log" -- "$@"; then
      SC_CHECKS="${SC_CHECKS}${name}|false|BLIND|${want}"$'\n'; all_ok=0; return
    fi
    if [ "$RG_VERDICT" = "$want" ]; then
      SC_CHECKS="${SC_CHECKS}${name}|true|${RG_VERDICT}|${want}"$'\n'
    else
      SC_CHECKS="${SC_CHECKS}${name}|false|${RG_VERDICT}|${want}"$'\n'
      echo "baseline_replay: selfcheck FAILED: $name classified $RG_VERDICT ($RG_REASON), expected $want" >&2
      all_ok=0
    fi
  }
  _sc_one true_pass PASS 30 true
  _sc_one false_fail FAIL 30 false
  _sc_one own_exit_127_fail FAIL 30 "$BASH" -c 'exit 127'
  _sc_one own_exit_255_fail FAIL 30 "$BASH" -c 'exit 255'
  _sc_one own_exit_124_fail FAIL 30 "$BASH" -c 'exit 124'
  _sc_one exec_failure_harness_error HARNESS_ERROR 30 fc-selfcheck-no-such-command-6b1f
  _sc_one timeout_unmeasured UNMEASURED 1 sleep 5
  rm -rf "$d"
  unset -f _sc_one
  [ "$all_ok" = 1 ]
}

# ---------------------------------------------------------------------------
# git_subject_freeze REPO_ROOT ITEM_ID
# Sets FZ_SHA FZ_TREE FZ_ADATE FZ_SUBJECT FZ_COUNT (FZ_SHA=UNMEASURED when no
# subject matches) and returns 0; returns 4 with FZ_ERR set when git itself
# fails. Runs in the CALLER's shell (never inside $(...)) so the globals survive.
#
# T048 restart round 1 fixes:
#  - R6-F3: `git log ... 2>/dev/null || raw=""` turned "not a repository", "git
#    missing" or a corrupt repo into "no commit found" with exit 0. Now the repo
#    is checked first and a failing git log / rev-parse is BLIND (exit 4). Only a
#    SUCCESSFUL git log with no subject match is UNMEASURED.
#  - R6-F4: "latest by author date" compared %aI STRINGS, which order wrongly
#    across timezone offsets (12:00+05:00 = 07:00Z sorts after 09:00+00:00). It
#    now compares %at (epoch seconds). On an exact tie the commit git log lists
#    first (the most recently committed) is kept.
#  - R6-F19: the old `for line in $raw` loop word-split AND pathname-expanded
#    every line; it is now a `read -r` loop over a here-string (no globbing).
#  - `--grep` is given `-F`: the item id is a literal string, never a regex.
# ---------------------------------------------------------------------------
git_subject_freeze() {
  local root="$1" item_id="$2"
  FZ_SHA=UNMEASURED; FZ_TREE=UNMEASURED; FZ_ADATE=""; FZ_SUBJECT=""; FZ_COUNT=0; FZ_ERR=""
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    FZ_ERR="not a git repository (or git unavailable): $root"
    return 4
  fi
  local errf raw rc
  errf="$(_fc_mktemp)" || { FZ_ERR="mktemp failed"; return 4; }
  raw="$(git -C "$root" log --all -i -F --grep="$item_id" --pretty=format:'%H%x1f%at%x1f%aI%x1f%s' 2>"$errf")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    FZ_ERR="git log failed (exit $rc): $(head -c 500 "$errf")"
    rm -f "$errf"
    return 4
  fi
  rm -f "$errf"
  # T043 round-4 finding B2 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a plain substring case-match (`*"$item_id"*`) makes ATM-95 match
  # ATM-953, ATM-103 match ATM-1038, etc. -- reproduced on this project's
  # own real history: `--item ATM-103` silently froze commit fd5585c7's
  # "...ATM-1038 option b" subject with exit 0, no BLIND, no warning.
  # This is exactly the "silent fall-back to any other guessed commit"
  # §11.4.6 forbids. Fixed with a token-boundary regex: the item id must
  # be bounded by a non-alnum-non-hyphen char (or string start) on the
  # left and a non-digit char (or string end) on the right, so ATM-103
  # can never match inside ATM-1038 or ATM-953.
  local item_re
  item_re="$(printf '%s' "$item_id" | sed 's/[][\.^$*+?(){}|]/\\&/g')"
  local best_at="" sha at adate subject
  while IFS=$'\x1f' read -r sha at adate subject; do
    [ -n "$sha" ] || continue
    if ! isnum "$at"; then
      FZ_ERR="git log returned a non-numeric author timestamp '$at' for $sha"
      return 4
    fi
    if [[ "$subject" =~ (^|[^A-Za-z0-9-])${item_re}([^0-9]|$) ]]; then
      FZ_COUNT=$((FZ_COUNT + 1))
      if [ -z "$best_at" ] || [ "$at" -gt "$best_at" ]; then
        best_at="$at"; FZ_SHA="$sha"; FZ_ADATE="$adate"; FZ_SUBJECT="$subject"
      fi
    fi
  done <<<"$raw"
  [ "$FZ_SHA" = UNMEASURED ] && return 0
  FZ_TREE="$(git -C "$root" rev-parse --verify --quiet "${FZ_SHA}^{tree}" 2>/dev/null)"
  if [ -z "$FZ_TREE" ]; then
    FZ_ERR="cannot resolve the tree of $FZ_SHA (corrupt or partial object store)"
    FZ_TREE=UNMEASURED
    return 4
  fi
  return 0
}

# ---------------------------------------------------------------------------
# emit_doc schema body_json out_path -- via fc_common.py (C-002).
# T048 restart round 1 (R6-F12): emit_doc no longer reads FC_OUT. FC_OUT (set by
# fc_common.py determinism-check) is honoured ONCE, at the top level, for the
# subcommand's own --out (see the dispatch at the end of this file); before, every
# internal emit honoured it, so replay-sample's internal per-item freeze wrote
# into the caller's FC_OUT instead of its own temp file and every item was then
# recorded as a harness error with exit 0.
# ---------------------------------------------------------------------------
emit_doc() {
  local schema="$1" body_json="$2" out_path="$3"
  mkdir -p "$(dirname "$out_path")" 2>/dev/null
  local run_meta
  run_meta="$(python3 -c 'import json,platform; print(json.dumps({"host": platform.node()}))')"
  python3 "$FC/lib/fc_common.py" emit --schema "$schema" --body-json "$body_json" \
    --run-meta-json "$run_meta" --out "$out_path"
  return $?
}

# ---------------------------------------------------------------------------
# freeze_to_body ITEM REPO_ROOT DB_PATH -> sets FZ_BODY (JSON) and returns 0, or
# prints the reason and returns 4 (BLIND). T048 restart round 1 (R6-F5): every
# value reaches Python through argv (a quoted heredoc is the program text), never
# spliced into Python source -- a subject containing `\N` used to be a Python
# SyntaxError (exit 2) and `\t` was silently turned into a TAB.
# ---------------------------------------------------------------------------
freeze_to_body() {
  local item="$1" repo_root="$2" db_path="$3"
  local item_type="UNKNOWN" item_type_note=""
  if [ -f "$db_path" ]; then
    # An existing but unreadable tracker DB is BLIND (header EXIT CODES row 4),
    # never silently UNKNOWN; an item simply absent from a readable DB is UNKNOWN.
    item_type="$(python3 - "$db_path" "$item" <<'PY' 2>/dev/null
import sqlite3, sys
try:
    conn = sqlite3.connect('file:%s?mode=ro' % sys.argv[1], uri=True)
    row = conn.execute('SELECT type FROM items WHERE atm_id = ? LIMIT 1', (sys.argv[2],)).fetchone()
except Exception:
    sys.exit(4)
print(row[0] if row else 'UNKNOWN')
PY
)" || { echo "baseline_replay: BLIND: tracker DB $db_path exists but cannot be read" >&2; return 4; }
  else
    item_type_note="tracker DB not present at $db_path"
  fi
  if ! git_subject_freeze "$repo_root" "$item"; then
    echo "baseline_replay: BLIND: freeze $item: $FZ_ERR" >&2
    return 4
  fi
  FZ_BODY="$(python3 - "$item" "$item_type" "$item_type_note" "$FZ_SHA" "$FZ_TREE" "$FZ_ADATE" \
      "$FZ_SUBJECT" "$FZ_COUNT" "$repo_root" <<'PY'
import json, sys
item, itype, inote, sha, tree, adate, subject, count, root = sys.argv[1:10]
body = {"item_id": item, "item_type": itype, "candidate_commit_count": int(count)}
if inote:
    body["item_type_note"] = inote
if sha == "UNMEASURED":
    body.update(commit="UNMEASURED", tree="UNMEASURED",
                missing_instrument="no git log commit whose SUBJECT line references %s was found "
                                   "under --all (repo_root=%s)" % (item, root))
else:
    body.update(commit=sha, tree=tree, commit_author_date=adate, commit_subject=subject)
print(json.dumps(body))
PY
)" || { echo "baseline_replay: BLIND: cannot assemble the freeze body for $item" >&2; return 4; }
  return 0
}

# =============================================================================
# freeze
# =============================================================================
cmd_freeze() {
  local item="" repo_root="" db_path="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --item) [ $# -ge 2 ] || die "freeze: --item needs a value"; item="$2"; shift 2 ;;
      --repo-root) [ $# -ge 2 ] || die "freeze: --repo-root needs a value"; repo_root="$2"; shift 2 ;;
      --db-path) [ $# -ge 2 ] || die "freeze: --db-path needs a value"; db_path="$2"; shift 2 ;;
      --out) [ $# -ge 2 ] || die "freeze: --out needs a value"; out="$2"; shift 2 ;;
      *) die "freeze: unknown argument: $1" ;;
    esac
  done
  [ -n "$item" ] || die "freeze: --item is required"
  case "$item" in *$'\n'*|*$'\r'*) die "freeze: --item must be a single line" ;; esac
  # T048 restart round 2 (V4-6 class: a blank value read as present): an id that
  # is blank or carries whitespace names no item -- `git log --grep "   "`
  # matches every commit.
  case "$item" in *[[:space:]]*) die "freeze: --item must not contain whitespace (got '$item')" ;; esac
  [ -n "$out" ] || die "freeze: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$db_path" ] || db_path="$repo_root/docs/workable_items.db"
  freeze_to_body "$item" "$repo_root" "$db_path" || return 4
  emit_doc "baseline-replay-freeze/v1" "$FZ_BODY" "$out"
}

# =============================================================================
# selfcheck
# =============================================================================
cmd_selfcheck() {
  local out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) [ $# -ge 2 ] || die "selfcheck: --out needs a value"; out="$2"; shift 2 ;;
      *) die "selfcheck: unknown argument: $1" ;;
    esac
  done
  [ -n "$out" ] || die "selfcheck: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  # selfcheck runs real gates too: it runs under the process supervisor like
  # replay (T048 restart round 2 V4-9 / round 3).
  _fc_supervise "" ""
  local sc_rc=0
  run_selfcheck || sc_rc=3
  local body
  body="$(python3 - "$SC_CHECKS" "$sc_rc" <<'PY'
import json, sys
checks = []
for line in sys.argv[1].splitlines():
    if not line:
        continue
    name, ok, got, want = line.split("|", 3)
    checks.append({"name": name, "ok": ok == "true", "got": got, "want": want})
print(json.dumps({"result": "ok" if sys.argv[2] == "0" else "FAILED", "checks": checks}))
PY
)"
  [ "$sc_rc" = 0 ] || return 3
  emit_doc "baseline-replay-selfcheck/v1" "$body" "$out"
}

# =============================================================================
# _fc_submodule_reference_update SRC TGT
#   T048 round-3 review finding R3-B1 fix (2026-09-30): the round-2
#   `--reference "$repo_root"` invocation was proven, by live measurement
#   (git 2.50.1, file:// transport, see the comment above the call site
#   below for the exact numbers), to be a NO-OP for object reuse -- a
#   single `--reference <path>` passed to `git submodule update` is
#   handed to git-clone(1) VERBATIM for EVERY submodule being cloned; it
#   is NEVER expanded to `<path>/.git/modules/<name>` per submodule (that
#   round-2 claim was independently re-tested this dispatch and is FALSE
#   for this codepath -- see below). Registering the SUPERPROJECT's own
#   `.git/objects` as an alternate buys nothing, because a submodule's
#   blobs/trees/commits were never stored there in the first place; they
#   live at `<repo>/.git/modules/<name>/objects`, a COMPLETELY SEPARATE
#   object store one directory level down. (git DOES have a genuine
#   feature for automatic per-submodule alternate resolution --
#   `-c submodule.alternateLocation=superproject` -- but it is wired only
#   into the `git clone --recurse-submodules --reference <path>`
#   codepath; re-tested live this dispatch with THIS git version and
#   confirmed it has NO effect on a `git submodule update --init
#   --recursive --reference <path>` call against an ALREADY-EXISTING
#   checkout, which is what a `git worktree add`-based replay needs, so
#   it cannot be used here.)
#
#   This function does manually what `--reference` alone does not:
#   submodule-BY-submodule, computing THAT submodule's own already-
#   fetched object store under SRC's git-common-dir (`git -C "$SRC"
#   rev-parse --git-common-dir` -- resolves correctly even when $SRC is
#   ITSELF a linked worktree of some other checkout, since
#   `--git-common-dir` always resolves to the shared repo, never a
#   per-worktree path; verified live) and passing THAT specific path as
#   `--reference` for a single-submodule `git submodule update --init --
#   <path>` call. It then RECURSES into any submodule that itself
#   declares a `.gitmodules` (a nested submodule), using SRC/<path> --
#   the corresponding already-checked-out submodule directory inside
#   SRC -- as the new source: a nested submodule's own object store
#   lives at `<parent's-git-common-dir>/modules/<nested-name>`, which
#   `git -C "$SRC/<path>" rev-parse --git-common-dir` resolves to
#   directly (verified live against a real 2-level-nested scratch
#   fixture: 0 objects transferred at BOTH the top-level AND the nested
#   level).
#
#   Degrades safely per submodule, independently: a submodule SRC has
#   never fetched (its `.git/modules/<name>` does not exist under SRC's
#   git-common-dir) gets NO `--reference` flag at all and falls through
#   to a normal network clone for THAT submodule only -- verified live,
#   exit 0, unaffected. A submodule whose remote is genuinely
#   unreachable still correctly fails non-zero regardless of whether a
#   `--reference` was supplied (verified live: --reference never removes
#   the need to negotiate refs with the remote; it only avoids
#   re-transferring objects the remote and the reference already agree
#   on) -- so this function preserves the exact "refuse to run gate_cmd
#   against a partially-checked-out tree" semantics the caller below
#   already depends on.
#
#   TGT is the linked worktree checkout ($wt_path) whose OWN
#   .gitmodules (at the frozen commit) is walked; SRC is the tree to
#   borrow already-fetched submodule objects from (initially $repo_root,
#   then recursively SRC's own corresponding submodule directory).
#   Returns the first non-zero exit encountered (or 0).
# =============================================================================
# invoked indirectly: exported with export -f and run via bash -c in a child shell below
# shellcheck disable=SC2329
_fc_submodule_reference_update() {
  local src="$1" tgt="$2"
  [ -f "$tgt/.gitmodules" ] || return 0

  local src_common=""
  src_common="$(git -C "$src" rev-parse --git-common-dir 2>/dev/null)" || src_common=""
  if [ -n "$src_common" ]; then
    case "$src_common" in
      /*) : ;;
      *) src_common="$(cd "$src" 2>/dev/null && cd "$src_common" 2>/dev/null && pwd)" || src_common="" ;;
    esac
  fi

  local list_file
  list_file="$(mktemp "${_FC_TMPDIR:-${TMPDIR:-/tmp}}/sm.XXXXXX")" || return 1
  git -C "$tgt" config -f .gitmodules --get-regexp '^submodule\..*\.path$' >"$list_file" 2>/dev/null

  local key path name ref_path rc=0
  # false positive: the loop only READS list_file via the redirect; rm -f merely unlinks it on early return, nothing is written through the pipeline
  # shellcheck disable=SC2094
  while IFS=' ' read -r key path; do
    [ -n "$key" ] || continue
    name="${key#submodule.}"
    name="${name%.path}"
    ref_path=""
    if [ -n "$src_common" ] && [ -d "$src_common/modules/$name" ]; then
      ref_path="$src_common/modules/$name"
    fi
    # T048 restart round 1 (R6-F15): `-c protocol.file.allow=never` alone does
    # NOT hold against the environment -- measured: `GIT_ALLOW_PROTOCOL=file git
    # -c protocol.file.allow=never submodule update --init` cloned a file://
    # submodule (rc=0), because GIT_ALLOW_PROTOCOL, when set, REPLACES the whole
    # protocol.*.allow policy. The env vars that can re-open a protocol are
    # removed for this one call (never touching the caller's own environment).
    if [ -n "$ref_path" ]; then
      env -u GIT_ALLOW_PROTOCOL -u GIT_PROTOCOL_FROM_USER -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
        git -c protocol.ext.allow=never -c protocol.file.allow=never \
        -C "$tgt" submodule update --init --quiet --reference "$ref_path" -- "$path"
    else
      env -u GIT_ALLOW_PROTOCOL -u GIT_PROTOCOL_FROM_USER -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
        git -c protocol.ext.allow=never -c protocol.file.allow=never \
        -C "$tgt" submodule update --init --quiet -- "$path"
    fi
    rc=$?
    [ "$rc" -eq 0 ] || { rm -f "$list_file"; return "$rc"; }

    if [ -f "$tgt/$path/.gitmodules" ]; then
      _fc_submodule_reference_update "$src/$path" "$tgt/$path"
      rc=$?
      [ "$rc" -eq 0 ] || { rm -f "$list_file"; return "$rc"; }
    fi
  done <"$list_file"
  rm -f "$list_file"
  return 0
}

# =============================================================================
# One frozen-commit replay: creates+removes exactly one worktree, runs
# gate_cmd cold_runs+warm_runs times inside it. Prints the JSON body on
# stdout (caller decides schema/out). Returns 0 on a successfully-measured
# run (gate PASS/FAIL is data, not a harness failure), 4 on BLIND.
# =============================================================================
# do_one_replay wraps the body so that the worker removes its own worktree on
# EVERY return path (success, and each BLIND `return 4`). T048 restart round 3:
# this replaces the EXIT trap + printf-%q-quoted cleanup string of rounds 1-2 --
# the worker no longer has traps, and the paths live in globals that outlive the
# body (the round-2 "unbound variable in the trap" class cannot recur). A stop of
# the tool never reaches this code: the supervisor removes the worktree from the
# ledger instead.
_FC_WT_REPO=""
_FC_WT_PATH=""
_FC_WT_LEDGER=""
_FC_LOG_DIR=""
_FC_LOG_LEDGER=""
_fc_wt_cleanup() {
  if [ -n "$_FC_WT_PATH" ]; then
    git -C "$_FC_WT_REPO" worktree remove --force "$_FC_WT_PATH" >/dev/null 2>&1
    rm -rf "$_FC_WT_PATH" 2>/dev/null
    git -C "$_FC_WT_REPO" worktree prune >/dev/null 2>&1
  fi
  [ -n "$_FC_WT_LEDGER" ] && rm -f "$_FC_WT_LEDGER"
  _FC_WT_PATH=""; _FC_WT_LEDGER=""
  return 0
}
do_one_replay() {
  _FC_WT_REPO=""; _FC_WT_PATH=""; _FC_WT_LEDGER=""; _FC_LOG_DIR=""; _FC_LOG_LEDGER=""
  _do_one_replay_body "$@"
  local rc=$?
  _fc_wt_cleanup
  if [ -n "$_FC_LOG_LEDGER" ]; then
    # a log directory no report will reference (a BLIND return after the runs
    # began) is marked as such, never left unexplained (V4R3-14)
    if [ "$rc" != 0 ] && [ -d "$_FC_LOG_DIR" ]; then
      printf 'No report references this run-log directory: the replay stopped with a harness error (BLIND, exit %s) before writing one. The logs are partial evidence.\n' "$rc" >"$_FC_LOG_DIR/INTERRUPTED" 2>/dev/null
    fi
    rm -f "$_FC_LOG_LEDGER"
  fi
  return "$rc"
}

_do_one_replay_body() {
  local commit="$1" tree="$2" repo_root="$3" worktree_root="$4" min_free_kb="$5"
  local timeout_s="$6" cold_runs="$7" warm_runs="$8" min_free_kb_objects="$9"
  shift 9
  local gate_cmd=("$@")

  [ ${#gate_cmd[@]} -ge 1 ] || { echo "baseline_replay: replay: --gate-cmd must be non-empty" >&2; return 4; }

  mkdir -p "$worktree_root" 2>/dev/null || { echo "baseline_replay: cannot create --worktree-root $worktree_root" >&2; return 4; }
  local free_kb
  free_kb="$(df -Pk "$worktree_root" 2>/dev/null | awk 'NR==2{print $4}')"
  isnum "$free_kb" || { echo "baseline_replay: cannot read free disk space for $worktree_root (df failed)" >&2; return 4; }
  if [ "$free_kb" -lt "$min_free_kb" ]; then
    echo "baseline_replay: BLIND: insufficient free disk at $worktree_root: ${free_kb}KB available, ${min_free_kb}KB required (--min-free-kb) -- refusing to create a worktree checkout" >&2
    return 4
  fi
  # T048 restart round 2 (V4-4): submodule objects the replay fetches land under
  # <git-common-dir>/worktrees/<n>/modules -- on the filesystem of the git object
  # store, which need not be the --worktree-root filesystem. Checked separately,
  # against its own floor, before anything is created.
  local objects_dir objects_free_kb
  objects_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$objects_dir" ] && [ -d "$objects_dir" ] || { echo "baseline_replay: BLIND: cannot resolve the git object store (git-common-dir) of $repo_root" >&2; return 4; }
  objects_free_kb="$(df -Pk "$objects_dir" 2>/dev/null | awk 'NR==2{print $4}')"
  isnum "$objects_free_kb" || { echo "baseline_replay: cannot read free disk space for $objects_dir (df failed)" >&2; return 4; }
  if [ "$objects_free_kb" -lt "$min_free_kb_objects" ]; then
    echo "baseline_replay: BLIND: insufficient free disk for the git object store $objects_dir: ${objects_free_kb}KB available, ${min_free_kb_objects}KB required (--min-free-kb-objects) -- submodule objects of the replayed commit are fetched there; refusing to create a worktree checkout" >&2
    return 4
  fi

  local wt_path
  wt_path="$(mktemp -d "$worktree_root/replay.XXXXXX")" || { echo "baseline_replay: mktemp -d under $worktree_root failed" >&2; return 4; }
  rmdir "$wt_path" 2>/dev/null  # git worktree add requires the target NOT already exist

  # Registered in the ledger BEFORE `git worktree add`, so a stop at any moment
  # from here on is cleaned up by the supervisor (T048 restart round 3).
  _FC_WT_REPO="$repo_root"
  _FC_WT_PATH="$wt_path"
  _fc_ledger_add wt "$repo_root" "$wt_path" || { echo "baseline_replay: BLIND: cannot write the cleanup ledger" >&2; return 4; }
  _FC_WT_LEDGER="$_FC_LEDGER_FILE"
  # `git worktree add` runs the repository's post-checkout hook. It runs under
  # the run supervisor, so a process the hook leaves running is stopped as soon
  # as the add returns (V4R3-5's hook `sleep &` used to outlive the tool and
  # hold the replay lock).
  local _wa_log _wa_mk _wa_rc
  _wa_log="$(_fc_mktemp)" || { echo "baseline_replay: BLIND: mktemp failed" >&2; return 4; }
  _wa_mk="$(_fc_mktemp)" || { rm -f "$_wa_log"; echo "baseline_replay: BLIND: mktemp failed" >&2; return 4; }
  _fc_run_child "$_wa_log" "$timeout_s" "$_wa_mk" "$repo_root" -- git -C "$repo_root" worktree add --detach --quiet "$wt_path" "$commit"
  _wa_rc=$?
  if [ "$_wa_rc" -ne 0 ]; then
    echo "baseline_replay: BLIND: git worktree add failed for commit $commit at $wt_path (exit $_wa_rc, outcome $(cat "$_wa_mk" 2>/dev/null)): $(head -c 500 "$_wa_log" 2>/dev/null)" >&2
    rm -f "$_wa_log" "$_wa_mk"
    return 4
  fi
  rm -f "$_wa_log" "$_wa_mk"

  # T048 restart round 1 (R6-F3, same class): a failed rev-parse used to leave
  # actual_tree empty and the report then carried an empty tree; a frozen tree of
  # "UNMEASURED" silently switched the match check off. Now an unresolvable tree
  # is BLIND, `--tree UNMEASURED` is refused by the argument parser, and the
  # report says whether the tree was actually verified (tree_verified).
  local actual_tree tree_verified=false
  actual_tree="$(git -C "$wt_path" rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null)"
  if [ -z "$actual_tree" ]; then
    echo "baseline_replay: BLIND: cannot resolve the checked-out tree for commit $commit at $wt_path" >&2
    return 4
  fi
  if [ -n "$tree" ]; then
    if [ "$actual_tree" != "$tree" ]; then
      echo "baseline_replay: BLIND: checked-out tree ($actual_tree) != frozen tree ($tree) for commit $commit" >&2
      return 4
    fi
    tree_verified=true
  fi

  # T048 remediation (finding F9, BLOCKING, 2026-09-29 -- systematic-debugging
  # per §11.4.102): `git worktree add --detach` above checks out ONLY the
  # superproject tree -- every git-submodule gitlink (160000 mode entry;
  # this repo has 28 direct submodules incl. device/rockchip/atmosphere/
  # presenter, .../smarttube-player, tools/helixqa/HelixQA, constitution --
  # plus their own nested submodules) is left as an EMPTY placeholder
  # directory in the new worktree. pre_build_verification.sh (line 65: `set
  # -euo pipefail`) reads files out of those submodules (independently
  # verified: PRESENTER_SRC="device/rockchip/atmosphere/presenter/Presenter/
  # src/main/java/com/atmosphere/presenter", CC83's helper awk's
  # "$PRESENTER_SRC/PresenterService.kt"; smarttube-player/SharedModules and
  # .../MediaServiceCore are also read by name, e.g. line ~29471). On THIS
  # host, GNU Awk 5.1.0 exits status 2 -- not 1 -- when its input file does
  # not exist ("awk: fatal: cannot open file ... for reading", independently
  # reproduced: `awk '{print}' /nonexistent 2>&1; echo $?` -> exit 2). CC83
  # captures that failing command's output via a plain assignment
  # (`_cc83_body="$(_cc83_onvideostopped_body ...)"`, itself an `awk ...
  # 2>/dev/null` call) -- under `set -e`, a failing command substitution on
  # the right-hand side of a plain variable assignment DOES trigger errexit
  # (assignment statements are not one of bash's documented `set -e`
  # exemptions, unlike an `if`/`while` condition or a `&&`/`||` operand), so
  # pre_build_verification.sh dies immediately, mid-check, with exit status
  # 2 -- NEVER reaching its own coded `exit 0`/`exit 1` paths. Reproduced
  # twice, deterministically, by hand: an isolated `git worktree add
  # --detach` checkout of ATM-799's frozen commit (07f9b2dd) with NO
  # submodule init dies at CC83 in 4.7s with exit 2, matching this baseline
  # run's own recorded `{"exit_code":2,...}` for every one of the 14
  # cold+warm runs across all 7 duration-eligible items (durations ranging
  # 4.1s-263s ONLY because each frozen commit's version of the script
  # reaches ITS OWN first missing-submodule-file check at a different
  # line/point in an otherwise-successful run, not because of a timeout --
  # `timeout`'s own failure codes are 124/125/126/127/137, never bare 2).
  # THE FIX: make the isolated worktree a faithful replica of what
  # pre_build_verification.sh actually expects to run against (a normal,
  # fully-submoduled checkout of the commit -- the ONLY context this
  # 41k-line gate script was ever written/tested for) by initialising every
  # submodule (direct + nested, since smarttube-player's own checks read
  # ITS nested SharedModules/MediaServiceCore) before running gate_cmd.
  # SECOND CORRECTION (T048 round-2 review finding F9, 2026-09-30 -- the
  # FIRST correction, immediately below, remains fully accurate and
  # unchanged): the claim originally here -- that a linked worktree's
  # submodule `.git/modules` is part of this repo's COMMON git dir,
  # automatically SHARED with the main checkout -- is ALSO WRONG,
  # independently discovered live in a LATER dispatch's own end-to-end
  # proof runs (a real `do_one_replay()` call genuinely stalled 950+
  # CPU-seconds on a real network fetch of `submodules/open_design` despite
  # $repo_root already having that exact submodule fully fetched): a
  # linked worktree's submodule git-dirs live under the PER-WORKTREE
  # `.git/worktrees/<name>/modules/<submodule>` path, NOT the shared
  # `.git/modules/<submodule>` this comment used to claim. `--recursive`
  # alone does NOT reuse the main checkout's already-fetched submodule
  # objects at all -- see `_fc_submodule_reference_update()` (defined
  # above `do_one_replay`, invoked a few lines below at the actual
  # submodule-update call site) for what genuinely closes this gap
  # (T048 round-3 review finding R3-B1: a bare `--reference "$repo_root"`
  # was ALSO tried and independently proven, by live measurement, to be
  # a no-op here -- see that function's own comment + the invocation
  # site's comment for the full correction and the live verification
  # that proved the bug, the false round-2 fix, AND the real fix).
  # HONEST CORRECTION (§11.4.6 -- an earlier draft of this comment claimed
  # "no clone, no network" unconditionally and was WRONG; independently
  # observed live via `ps aux` during this fix's own end-to-end proof
  # runs): when a FROZEN commit (an OLD one especially) pins a submodule
  # SHA that was never locally fetched, `git submodule update --init`
  # does NOT fail or go BLIND -- it does exactly what it is designed to
  # do and performs a REAL network clone of that submodule (observed live:
  # `git submodule--helper clone ... git@github.com:ATMOSphere1234321/
  # ATMOSphere-Lampa.git` and, separately, `...ATMOSphere-SmartTube.git`,
  # each followed by a real `git index-pack ... on the-factory` transfer).
  # That is CORRECT, intended git behaviour, not a bug -- the fetched
  # objects land in the shared `.git/modules/<name>/` object store, so the
  # cost is paid ONCE per missing submodule SHA across the life of this
  # repo's local clone, never repeated for that same SHA again (later
  # do_one_replay calls, this run or a future one, reuse it). It is,
  # however, a genuinely SLOW one-time cost for a large submodule (e.g.
  # smarttube-player's tracked history, ~2.2 GiB working-tree size) --
  # observed adding SEVERAL MINUTES to a single do_one_replay call the
  # first time a historical commit needs it. The BLIND path below is for
  # the genuine failure case only (network unreachable, auth rejected, or
  # the pinned SHA truly gone from every configured remote) -- never for
  # "needs a network fetch", which is expected, cacheable, and correct.
  # Measured disk cost once fully cached: `du -sh` on all 28 direct
  # submodule paths in the MAIN checkout (which already recurses through
  # their own nested content) is ~7.4 GiB total, ON TOP OF the ~49 GiB
  # superproject checkout. (An earlier version of this sentence called that
  # "well inside the --min-free-kb 10 GiB headroom" -- false: 49 + 7.4 GiB is
  # more than five times 10 GiB. T048 restart round 1, R6-F10 raised the
  # default floor to DEFAULT_MIN_FREE_KB = 67 GiB, derived from these two
  # measurements plus 10 GiB headroom.)
  #
  # T048 remediation, signal-safety hardening added AFTER independently
  # observing the multi-minute network-clone cost above IN THIS SAME
  # dispatch's own end-to-end proof runs: the SAME T043 round-4 finding B1
  # class (a plain FOREGROUND command defers any trapped HUP/QUIT signal
  # -- and, empirically re-confirmed live during this exact investigation,
  # can leave a git-worktree-remove needed EVEN for a plain TERM sent to
  # only the top-level script process while a `git submodule--helper`
  # grandchild keeps running detached, reparented, and orphaned) applies
  # here just as much as it did to the gate-cmd run below -- this step can
  # now take LONGER than the gate-cmd itself on a stale local checkout.
  # Fixed the identical way: BACKGROUND the command + `wait` on it
  # explicitly (promptly interruptible by a pending trapped signal,
  # unlike a synchronous foreground pipeline) and bound it with `timeout`
  # (reusing the caller's own --timeout-s knob rather than adding a new
  # CLI flag) so a genuine network stall cannot hang this step forever.
  #
  # Security remediation (T048 review, 2026-09-29): `$commit` here is
  # always EITHER a SHA `cmd_freeze` resolved via `git log --all --grep`
  # against THIS repo's own already-fetched local history, or an
  # operator-supplied `--commit` argument -- in both cases `git -C
  # "$repo_root" worktree add --detach "$wt_path" "$commit"` a few lines
  # above ALREADY required that commit's TREE to be a valid, already-
  # present object in $repo_root's local object store (worktree add never
  # fetches; an unreachable SHA fails there with BLIND before this line is
  # ever reached). So $commit itself is never unvalidated external input.
  # $commit's TREE CONTENT, however, is only as trustworthy as this repo's
  # own history -- and its .gitmodules is ordinary versioned content, so a
  # submodule path this specific commit introduces (one with no prior
  # `submodule.<name>.url` already recorded in the shared `.git/config`
  # from the main checkout's own real `git submodule init`) has its
  # fetch URL read straight out of THAT COMMIT's .gitmodules with no
  # allowlist check. Git's own `ext::` submodule-URL remote-code-execution
  # class (the CVE-2017-1000117 family) is denied by this host's git 2.50.1
  # default (`protocol.ext.allow=user`, confirmed via `git config --get`
  # returning unset -- i.e. the compiled-in default, "deny for an
  # operation like this one that did not explicitly opt in"), so this is
  # belt-and-braces defense-in-depth, not a bypass of an otherwise-open
  # hole: pin `ext`/`file` to `never` explicitly on THIS invocation only
  # (never touching the caller's global git config) so a future git
  # version or a differently-configured host cannot re-open it. An ambient
  # `GIT_ALLOW_PROTOCOL` / `GIT_CONFIG_*` environment override is NOT stopped
  # by `-c` alone (an earlier version of this comment claimed it was; measured
  # false, T048 restart round 1 R6-F15) -- those variables are removed with
  # `env -u` on the call itself inside _fc_submodule_reference_update(). `file`
  # is denied too -- a crafted local-path submodule URL pointing at an
  # attacker-writable bare repo is the same class of risk as `ext::`, and
  # this project's own real submodules (confirmed via `.gitmodules`) are
  # exclusively `git@github.com:...` SSH URLs, so neither protocol is ever
  # legitimately needed here.
  # T048 round-2 review finding F9 (2026-09-30, §11.4.102 root-cause
  # investigation): a linked worktree's `git submodule update --init
  # --recursive` clones EACH submodule into its OWN per-worktree git-dir
  # (`.git/worktrees/<name>/modules/<submodule>`, NOT the shared common
  # `.git/modules/<submodule>` every earlier draft of this file's own
  # comments assumed) -- reproduced live: a real do_one_replay() run
  # genuinely stalled 950+ CPU-seconds on a real network `git index-pack`
  # for `submodules/open_design`, even though $repo_root (the MAIN
  # checkout this worktree was created FROM) already has that exact
  # submodule fully fetched at `.git/modules/submodules/open_design`.
  # T048 round-3 review finding R3-B1 (2026-09-30, CORRECTS the round-2
  # text that used to sit here): the round-2 claim that a bare
  # `--reference "$repo_root"` makes "git's own submodule-clone machinery
  # automatically resolve `<reference>/.git/modules/<name>`" is FALSE --
  # independently re-measured live this dispatch (git 2.50.1, file://
  # transport, `git count-objects` before/after, exactly the round-3
  # reviewer's own methodology): a fresh submodule clone transferred the
  # IDENTICAL object count with `--reference "$repo_root"` as with no
  # `--reference` at all (both fetch everything over the wire), while
  # referencing the submodule's OWN store directly
  # (`"$repo_root"/.git/modules/<name>`) transferred ZERO objects. A
  # single `--reference <path>` on `git submodule update` is passed to
  # git-clone(1) verbatim for every submodule being cloned; it is never
  # expanded per-submodule on this codepath. (git DOES have a genuine
  # `-c submodule.alternateLocation=superproject` feature for automatic
  # per-submodule alternate resolution, but it is wired only into `git
  # clone --recurse-submodules --reference <path>`'s initial-clone
  # codepath -- re-tested live and confirmed it has NO effect on a
  # `submodule update --init --recursive --reference <path>` call
  # against an ALREADY-EXISTING checkout, which is what a `git worktree
  # add`-based replay needs here.) Fixed by `_fc_submodule_reference_
  # update()` (defined above `do_one_replay`) which loops submodule-BY-
  # submodule, computing and passing EACH submodule's own already-
  # fetched store under $repo_root's git-common-dir individually
  # (`git -C "$repo_root" rev-parse --git-common-dir` -- resolves
  # correctly even when $repo_root is itself a linked worktree, since
  # `--git-common-dir` always resolves to the shared repo, not a
  # per-worktree path) as that ONE submodule's `--reference` --
  # RECURSING into any submodule that itself declares its own
  # `.gitmodules` (a nested submodule) using $repo_root's OWN
  # already-checked-out copy of that submodule as the new reference
  # source, since a nested submodule's store lives at
  # `<parent-store>/modules/<nested-name>`, which `rev-parse
  # --git-common-dir` composes correctly from within that checked-out
  # directory (verified live against a real 2-level-nested scratch
  # fixture: 0 objects transferred at BOTH the top-level AND the nested
  # level). Degrades safely per submodule, independently, exactly as the
  # round-2 text claimed for its own (broken) form: a submodule
  # $repo_root has never fetched gets no `--reference` flag and falls
  # through to a normal network clone for THAT submodule only (verified
  # live, exit 0, unaffected); a submodule whose remote is genuinely
  # unreachable still correctly fails non-zero regardless of whether a
  # `--reference` was supplied (verified live: `--reference` never
  # removes the need to negotiate refs with the remote -- it only avoids
  # re-transferring objects the remote and the reference already
  # agree on), preserving the exact "refuse to run gate_cmd against a
  # partially-checked-out tree" semantics the caller below depends on.
  # `--reference` (not `--reference-if-able`) is deliberate: this git
  # version's `submodule update` does not recognise the `-if-able` form
  # at all (confirmed live: real exit 1, a usage error).
  # T048 restart round 3: run under the run supervisor like a gate run -- every
  # `git submodule--helper` / `git index-pack` process it starts is a descendant
  # of it, whatever process group or session git puts them in, and is stopped
  # with it. The helper function is exported only for this one child and
  # un-exported again, so the GATE never inherits it.
  export -f _fc_submodule_reference_update
  local _sm_mk submodule_rc
  _sm_mk="$(_fc_mktemp)" || { export -fn _fc_submodule_reference_update; echo "baseline_replay: BLIND: mktemp failed" >&2; return 4; }
  # the bash -c body is single-quoted on purpose: $1/$2 must expand in the child shell, not here
  # shellcheck disable=SC2016
  _fc_run_child /dev/null "$timeout_s" "$_sm_mk" "$repo_root" -- \
      env _FC_TMPDIR="$_FC_TMPDIR" "$BASH" -c '_fc_submodule_reference_update "$1" "$2"' fc-submodule "$repo_root" "$wt_path"
  submodule_rc=$?
  export -fn _fc_submodule_reference_update
  if [ "$submodule_rc" -ne 0 ]; then
    echo "baseline_replay: BLIND: git submodule update --init --recursive failed (exit $submodule_rc$( [ "$(cat "$_sm_mk" 2>/dev/null)" = timed_out ] && echo ", timed out after ${timeout_s}s")) for commit $commit at $wt_path (a frozen submodule SHA may be absent from the local object store, or a network fetch stalled -- refusing to run gate_cmd against a partially-checked-out tree)" >&2
    rm -f "$_sm_mk"
    return 4
  fi
  rm -f "$_sm_mk"

  # T048 remediation (finding F9 continued): after the submodule fix above,
  # a SECOND, DISTINCT missing-prerequisite class was independently
  # reproduced for the "slow" items (ATM-610/611/627/277/SPK-609, 170-263s
  # elapsed vs. the "fast" CC83 class' 4-5s): a pre-build gate this project
  # runs can itself contain a "cmd; rc=$?" style SEQUENTIAL (`;`), not
  # errexit-exempt, inline sub-script invocation (contrast this SAME file's
  # own later "§11.4.1-safe live-run" harness check, which deliberately
  # uses the errexit-EXEMPT `if cmd; then rc=0; else rc=$?; fi` form
  # instead) whose sub-script is DESIGNED to exit 2 as an honest SKIP when
  # a single, project-defined, gitignored host-build prerequisite is
  # absent -- a tool git NEVER tracks and that a bare `git worktree add`
  # checkout therefore NEVER has, while this project's own long-lived,
  # repeatedly-built dev tree (the environment T045's cited "~18.9 min per
  # full run" evidence-block figure was measured against) has it sitting
  # around from a PRIOR build, since nothing in this project's normal
  # workflow ever `make clean`s host tools. So the SKIP=2 the isolated
  # worktree hits here is real to the worktree, but NOT representative of
  # the environment this gate's timing was ever measured or is meant to be
  # measured against. Rather than chasing every gate's own inline
  # sub-script sites for a similar gap (a full project-side audit found
  # this class affects exactly one such site; every OTHER inline
  # sub-script run in this file already uses the errexit-exempt `if`-form),
  # compile the ONE confirmed, cheap, self-contained, no-network host tool
  # this isolated worktree is missing -- IF the caller has named one via
  # the two `FC_REPLAY_HOSTTOOL_*` env vars below. §11.4.28(B): this
  # generic replay machinery takes any such project-specific prerequisite
  # as caller-supplied DATA, never a hardcoded literal path -- leaving
  # either env var unset makes this whole step an honest no-op. BOUNDED,
  # not a slippery slope toward replicating a full project build: this
  # project's own concrete instance names a single ~1575-line file, ~1s to
  # compile, verified independently (`cc -O2` on it exits 0, its own
  # `--help` runs, and the gate that needed it genuinely PASSes against it
  # afterward instead of SKIPping). A compile failure is treated exactly
  # like the worktree-add/submodule-update failures above -- an honest
  # BLIND (unmeasurable), never silently absorbed.
  local _rt_src="" _rt_bin=""
  if [ -n "${FC_REPLAY_HOSTTOOL_SRC:-}" ] && [ -n "${FC_REPLAY_HOSTTOOL_BIN:-}" ]; then
    _rt_src="$wt_path/${FC_REPLAY_HOSTTOOL_SRC}"
    _rt_bin="$wt_path/${FC_REPLAY_HOSTTOOL_BIN}"
  fi
  if [ -n "$_rt_src" ] && [ -f "$_rt_src" ] && [ ! -x "$_rt_bin" ]; then
    # Security remediation (T048 review, 2026-09-29): symlink-follow-write
    # guard. $wt_path is a disposable `git worktree add --detach` checkout
    # of $commit (an arbitrary, possibly-historical commit from this
    # repo's own local history -- see the submodule-fetch comment above
    # for why $commit itself is never unvalidated external input, though
    # its TREE CONTENT is still only as trustworthy as this repo's own
    # history). Git tracks symlinks as ordinary blobs (mode 120000), so
    # nothing here prevents SOME commit in that history from having
    # checked out the configured host-tool's containing directory (or the
    # source/binary leaf entries themselves) as a symlink pointing OUTSIDE
    # this worktree -- `cc -O2 -o "$_rt_bin" "$_rt_src"` would then
    # transparently follow that symlink and CREATE or OVERWRITE an
    # attacker-chosen file anywhere the invoking user can write, driven
    # entirely by tree content this script never authored. Refuse (BLIND)
    # rather than follow: canonicalize the source file's containing
    # directory with `pwd -P` (resolves every symlink component, unlike a
    # plain path-string prefix check) and verify the RESULT still lives
    # strictly inside $wt_path's own canonical path before compiling
    # anything; independently also refuse if either the source or the
    # binary path itself is a symlink LEAF (a legitimate directory
    # containing a symlinked single file, which the directory-containment
    # check alone would not catch).
    local _rt_dir _rt_dir_real wt_path_real
    _rt_dir="$(dirname "$_rt_src")"
    _rt_dir_real="$(cd "$_rt_dir" 2>/dev/null && pwd -P)"
    wt_path_real="$(cd "$wt_path" 2>/dev/null && pwd -P)"
    if [ -z "$_rt_dir_real" ] || [ -z "$wt_path_real" ] || \
       { [ "$_rt_dir_real" != "$wt_path_real" ] && \
         [ "${_rt_dir_real#"$wt_path_real"/}" = "$_rt_dir_real" ]; } || \
       [ -L "$_rt_src" ] || [ -L "$_rt_bin" ]; then
      echo "baseline_replay: BLIND: configured host-tool path (FC_REPLAY_HOSTTOOL_SRC=${FC_REPLAY_HOSTTOOL_SRC}, FC_REPLAY_HOSTTOOL_BIN=${FC_REPLAY_HOSTTOOL_BIN}) resolves OUTSIDE the isolated worktree (worktree is ${wt_path_real:-$wt_path}) for commit $commit -- refusing to compile through what appears to be a git-tracked symlink escaping the disposable checkout, which could otherwise write an attacker-chosen file anywhere the invoking user can write" >&2
      return 4
    fi
    if ! cc -O2 -o "$_rt_bin" "$_rt_src" >/dev/null 2>&1; then
      echo "baseline_replay: BLIND: host-tool compile failed for $_rt_src at $wt_path (FC_REPLAY_HOSTTOOL_SRC names a gitignored host-build prerequisite the caller's gate_cmd needs; without it, that gate's own inline sub-run can crash the whole gate under set -e via an honest exit-2 SKIP the wrapper cannot safely capture)" >&2
      return 4
    fi
  fi

  # T048 remediation (finding F9 continued -- the output-discarding
  # hardening asked for independently of the root cause fix above): the
  # gate-cmd's combined stdout+stderr used to go straight to `/dev/null`
  # (a prior version of this line), so a future crash/hang/unexpected
  # nonzero exit had NO captured evidence to diagnose from without
  # re-running the whole (multi-minute) replay by hand. Every run gets its
  # own persistent log file, recorded in its JSON row (captured-evidence
  # citation per §11.4.5).
  # T048 restart round 1 (R6-F6): the earlier name
  # `${commit:0:12}_${phase}_${idx}.log` directly under replay-logs/ was NOT
  # unique -- the two internal runs of --determinism-check, a re-run, and two
  # sample items frozen to the same commit all wrote the same paths, so run 2
  # overwrote run 1's evidence and the recorded log_path cited the wrong run
  # (measured: run 1's cold_1.log contained run 2's output). Each do_one_replay
  # call now creates its OWN fresh directory with mktemp -d (unique by
  # construction, never reused), a sibling of $wt_path so the worktree removal
  # never touches it. The directory is recorded as the
  # report's log_dir.
  mkdir -p "$worktree_root/replay-logs" 2>/dev/null || { echo "baseline_replay: cannot create run-log directory $worktree_root/replay-logs" >&2; return 4; }
  local run_log_dir
  run_log_dir="$(mktemp -d "$worktree_root/replay-logs/${commit:0:12}.XXXXXX")" || { echo "baseline_replay: cannot create a unique run-log directory under $worktree_root/replay-logs" >&2; return 4; }
  # ledger: a stop before the report is written marks this directory INTERRUPTED
  # (V4R3-14) instead of leaving unowned partial evidence behind
  _FC_LOG_DIR="$run_log_dir"
  _fc_ledger_add logs "$run_log_dir" || { echo "baseline_replay: BLIND: cannot write the cleanup ledger" >&2; return 4; }
  _FC_LOG_LEDGER="$_FC_LEDGER_FILE"

  local rows='[]' harness_error=0
  local phase run_idx n_runs run_log
  for phase in cold warm; do
    if [ "$phase" = cold ]; then n_runs="$cold_runs"; else n_runs="$warm_runs"; fi
    run_idx=1
    # A HARNESS_ERROR means the gate could not be started at all; repeating the
    # same failed launch measures nothing, so the loop stops at the first one.
    while [ "$run_idx" -le "$n_runs" ] && [ "$harness_error" = 0 ]; do
      run_log="$run_log_dir/${phase}_${run_idx}.log"
      run_gate_once "$wt_path" "$timeout_s" "$run_log" -- "${gate_cmd[@]}" || return 4
      [ "$RG_VERDICT" = HARNESS_ERROR ] && harness_error=1
      rows="$(python3 - "$rows" "$phase" "$run_idx" "$RG_START_NS" "$RG_END_NS" "$RG_DURATION_MS" \
          "$RG_RC" "$RG_VERDICT" "$RG_REASON" "$run_log" <<'PY'
import json, sys
a = sys.argv
rows = json.loads(a[1])
rows.append({"phase": a[2], "run_index": int(a[3]), "start_ns": int(a[4]), "end_ns": int(a[5]),
             "duration_ms": int(a[6]), "exit_code": int(a[7]), "verdict": a[8], "verdict_reason": a[9],
             "log_path": a[10]})
print(json.dumps(rows))
PY
)" || { echo "baseline_replay: cannot record run row" >&2; return 4; }
      run_idx=$((run_idx + 1))
    done
  done

  _fc_wt_cleanup

  # Report body. T048 restart round 1:
  #  - R6-F5: every value is passed through argv; the program text is a quoted
  #    heredoc, so no data is ever parsed as Python source.
  #  - R6-F9: median_ms is computed over PASS runs ONLY. A FAIL may be a crash
  #    that stopped part-way (the documented F9 forensic: 14 runs that all
  #    crashed with exit 2 after 4-263 s), and UNMEASURED / HARNESS_ERROR runs
  #    never completed; none of them is a measurement of how long the gate
  #    takes. The per-verdict breakdown keeps the FAIL durations visible
  #    (by_verdict) without letting them into the baseline.
  python3 - "$rows" "$commit" "$actual_tree" "$tree_verified" "$cold_runs" "$warm_runs" \
      "$min_free_kb" "$timeout_s" "$run_log_dir" "$harness_error" "$min_free_kb_objects" "${gate_cmd[@]}" <<'PY'
import json, statistics, sys
a = sys.argv
rows = json.loads(a[1])
commit, tree, tree_verified = a[2], a[3], a[4] == "true"
cold_runs, warm_runs, min_free_kb, timeout_s = int(a[5]), int(a[6]), int(a[7]), int(a[8])
log_dir, harness_error, min_free_kb_objects, gate_cmd = a[9], a[10] == "1", int(a[11]), a[12:]
def med(vals):
    return int(round(statistics.median(vals))) if vals else "UNMEASURED"
phases = ("cold", "warm")
median_ms = {p: med([r["duration_ms"] for r in rows if r["phase"] == p and r["verdict"] == "PASS"])
             for p in phases}
by_verdict = {}
for p in phases:
    by_verdict[p] = {}
    for v in sorted({r["verdict"] for r in rows if r["phase"] == p}):
        d = [r["duration_ms"] for r in rows if r["phase"] == p and r["verdict"] == v]
        by_verdict[p][v] = {"n_runs": len(d), "median_ms": med(d)}
verdict_set = {p: sorted({r["verdict"] for r in rows if r["phase"] == p}) for p in phases}
print(json.dumps({
    "commit": commit, "tree": tree, "tree_verified": tree_verified, "gate_cmd": gate_cmd,
    "cold_runs": cold_runs, "warm_runs": warm_runs, "min_free_kb": min_free_kb,
    "min_free_kb_objects": min_free_kb_objects, "timeout_s": timeout_s,
    "cache_mechanism": "none (T068 verdict_cache.py not landed in this tree, verified 2026-09-28)",
    "median_basis": "PASS runs only (FAIL/UNMEASURED/HARNESS_ERROR excluded, see by_verdict)",
    "log_dir": log_dir, "harness_error": harness_error,
    "runs": rows, "median_ms": median_ms, "by_verdict": by_verdict, "verdict_set": verdict_set,
}))
PY
}

# =============================================================================
# run_replay_isolated BODY_FILE do_one_replay-args... -- one replay, its report
# body to BODY_FILE. T048 restart round 3: a plain call. The background job +
# TERM forwarding of rounds 1-2 (R6-F11a) existed only so the main shell could
# stop the replay; stopping is the supervisor's job now (the worker is a
# descendant it owns), and a stop signal ends the worker itself at once.
# =============================================================================
run_replay_isolated() {
  local body_file="$1"
  shift
  do_one_replay "$@" >"$body_file"
}

# parse_gate_cmd STR -> sets GATE_ARGV. Word-splits on whitespace WITHOUT
# pathname expansion (T048 restart round 1, R6-F19 class: the old unquoted
# `$gate_cmd_str` expansions also glob-expanded every word against the caller's
# cwd). HONEST BOUNDARY (unchanged): an argument cannot itself contain
# whitespace.
parse_gate_cmd() {
  case "$1" in *$'\n'*|*$'\r'*) die "--gate-cmd must be a single line" ;; esac
  GATE_ARGV=()
  read -r -a GATE_ARGV <<<"$1"
  [ "${#GATE_ARGV[@]}" -ge 1 ] || die "--gate-cmd must name a command"
}

# validate_run_counts COLD WARM TIMEOUT_S MIN_FREE_KB MIN_FREE_KB_OBJECTS (T048
# restart round 1: R6-F7 zero runs, R6-F18 --timeout-s 0 which DISABLES
# the run supervisor's bound).
validate_run_counts() {
  isnum "$1" || die "--cold-runs must be a non-negative integer"
  isnum "$2" || die "--warm-runs must be a non-negative integer"
  [ $(( $1 + $2 )) -ge 1 ] || die "--cold-runs + --warm-runs must be at least 1 (zero runs measure nothing)"
  { isnum "$3" && [ "$3" -ge 1 ]; } || die "--timeout-s must be a positive integer (0 would disable the bound)"
  isnum "$4" || die "--min-free-kb must be a non-negative integer"
  isnum "$5" || die "--min-free-kb-objects must be a non-negative integer"
}

# body_field FILE EXPR -> prints a field of a JSON body file (data read from the
# file, the expression is always a literal from this script).
body_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = d
for k in sys.argv[2].split("."):
    v = v[k]
print(json.dumps(v) if not isinstance(v, str) else v)
PY
}

# =============================================================================
# replay
# =============================================================================
cmd_replay() {
  local commit="" tree="" gate_cmd_str="" cold_runs=10 warm_runs=10
  local repo_root="" worktree_root="" min_free_kb="$DEFAULT_MIN_FREE_KB" timeout_s=1800 out=""
  local min_free_kb_objects="$DEFAULT_MIN_FREE_KB_OBJECTS" determinism_check=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --determinism-check) determinism_check=1; shift; continue ;;
    esac
    [ $# -ge 2 ] || die "replay: $1 needs a value"
    case "$1" in
      --commit) commit="$2" ;;
      --tree) tree="$2" ;;
      --gate-cmd) gate_cmd_str="$2" ;;
      --cold-runs) cold_runs="$2" ;;
      --warm-runs) warm_runs="$2" ;;
      --repo-root) repo_root="$2" ;;
      --worktree-root) worktree_root="$2" ;;
      --min-free-kb) min_free_kb="$2" ;;
      --min-free-kb-objects) min_free_kb_objects="$2" ;;
      --timeout-s) timeout_s="$2" ;;
      --out) out="$2" ;;
      *) die "replay: unknown argument: $1" ;;
    esac
    shift 2
  done
  [ -n "$commit" ] || die "replay: --commit is required"
  [ -n "$gate_cmd_str" ] || die "replay: --gate-cmd is required"
  [ -n "$out" ] || die "replay: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  # T048 restart round 1 (R6-F3 class): a freeze that could not resolve the tree
  # must never switch the tree-match check off. Omit --tree to replay without a
  # tree check (recorded as tree_verified=false); never pass UNMEASURED.
  [ "$tree" = UNMEASURED ] && die "replay: --tree UNMEASURED refused -- the frozen tree was never resolved; omit --tree explicitly to replay without a tree check"
  validate_run_counts "$cold_runs" "$warm_runs" "$timeout_s" "$min_free_kb" "$min_free_kb_objects"
  parse_gate_cmd "$gate_cmd_str"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$worktree_root" ] || worktree_root="$repo_root/.fc_worktrees"
  # T043 round-4 finding B3 (BLOCKING, agent ad5d869e28efdddbd, 2026-09-28):
  # a RELATIVE --worktree-root resolves against the CALLER's cwd for
  # mktemp/rev-parse/df/the gate's own `cd`, but against $repo_root for
  # `git -C "$repo_root" worktree add` -- two different base directories
  # for the SAME value, silently pointing at two different locations.
  # Fixed the SAME way repo_root already is, two lines up: resolve to an
  # absolute, canonical path up front so every later consumer (mktemp,
  # df, git -C, the gate's cd) agrees on the SAME directory.
  mkdir -p "$worktree_root" 2>/dev/null || die "replay: cannot create --worktree-root $worktree_root"
  worktree_root="$(cd "$worktree_root" 2>/dev/null && pwd)" || die "replay: cannot resolve --worktree-root $worktree_root to an absolute path"

  _fc_supervise "$repo_root" "$worktree_root"   # the caller's process becomes the supervisor here
  run_selfcheck || return 3

  local body1 body2
  body1="$(_fc_mktemp)" || blind "mktemp failed"
  run_replay_isolated "$body1" "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
    "$timeout_s" "$cold_runs" "$warm_runs" "$min_free_kb_objects" "${GATE_ARGV[@]}" || { rm -f "$body1"; return 4; }

  if [ "$determinism_check" = 1 ]; then
    # DETERMINISM (C-003). `replay`'s report embeds real wall-clock timing, so
    # a byte-identical body comparison can never pass (verified 2026-09-28);
    # this flag replays the SAME frozen {commit, tree, gate-cmd} twice and
    # compares the VERDICTS. T048 restart round 1 (R6-F7) tightened the rule:
    #  - a phase whose verdict set holds more than one verdict inside ONE
    #    invocation is itself non-deterministic (an alternating PASS/FAIL gate
    #    with --cold-runs 2 gave {"cold":["FAIL","PASS"]} twice and used to be
    #    reported deterministic);
    #  - both phases are compared (a warm-only difference is a difference);
    #  - a run that never completed (UNMEASURED) or never started
    #    (HARNESS_ERROR) gives NO verdict: deterministic=null, exit 4 --
    #    "could not measure, twice" is not "deterministic";
    #  - zero runs are refused by validate_run_counts (a check over nothing
    #    cannot fail).
    body2="$(_fc_mktemp)" || blind "mktemp failed"
    run_replay_isolated "$body2" "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
      "$timeout_s" "$cold_runs" "$warm_runs" "$min_free_kb_objects" "${GATE_ARGV[@]}" || { rm -f "$body1" "$body2"; return 4; }
    local det_body det_rc emit_rc
    det_body="$(python3 - "$body1" "$body2" <<'PY'
import json, sys
b1, b2 = (json.load(open(p)) for p in sys.argv[1:3])
phases = ("cold", "warm")
vs1, vs2 = b1["verdict_set"], b2["verdict_set"]
out = {"run1_verdict_set": vs1, "run2_verdict_set": vs2,
       "run1_log_dir": b1["log_dir"], "run2_log_dir": b2["log_dir"]}
unmeasurable = sorted({r["verdict"] for b in (b1, b2) for r in b["runs"]
                       if r["verdict"] in ("UNMEASURED", "HARNESS_ERROR")})
if unmeasurable:
    out.update(deterministic=None,
               reason="no determinism verdict: run(s) classified %s" % ",".join(unmeasurable))
    print(json.dumps(out))
    sys.exit(4)
flaky = sorted({p for b in (b1, b2) for p in phases if len(b["verdict_set"].get(p, [])) > 1})
differs = sorted({p for p in phases if vs1.get(p, []) != vs2.get(p, [])})
det = not flaky and not differs
out.update(deterministic=det, within_run_flaky_phases=flaky, differing_phases=differs)
print(json.dumps(out))
sys.exit(0 if det else 1)
PY
)"
    det_rc=$?
    rm -f "$body1" "$body2"
    echo "$det_body"
    # T043 round-3 review finding F3(c): a --out write failure is always
    # surfaced, and escalates a would-be exit 0 to 4 (a caller must never see
    # exit 0 when the mandatory --out contract was not honoured).
    emit_doc "baseline-replay-determinism/v1" "$det_body" "$out"
    emit_rc=$?
    if [ "$emit_rc" != 0 ]; then
      echo "baseline_replay: WARNING: writing the --determinism-check result to --out ($out) failed (emit_doc exit $emit_rc) -- the determinism verdict printed above is still accurate, but the mandatory --out contract was not honored" >&2
      [ "$det_rc" = 0 ] && return 4
    fi
    return "$det_rc"
  fi

  local body herr
  body="$(cat "$body1")"
  herr="$(body_field "$body1" harness_error)"
  rm -f "$body1"
  emit_doc "baseline-replay/v1" "$body" "$out" || return $?
  # R6-F8: a gate that could not even be started is BLIND (exit 4), never a
  # recorded "gate FAIL" with exit 0. The report is still written as evidence.
  if [ "$herr" = true ]; then
    echo "baseline_replay: BLIND: the gate command could not be started (HARNESS_ERROR, see the report's runs[].verdict_reason)" >&2
    return 4
  fi
  return 0
}

# =============================================================================
# replay-sample
# =============================================================================
cmd_replay_sample() {
  local sample="" gate_cmd_str="" cold_runs=10 warm_runs=10
  local repo_root="" worktree_root="" min_free_kb="$DEFAULT_MIN_FREE_KB" timeout_s=1800 out=""
  local min_free_kb_objects="$DEFAULT_MIN_FREE_KB_OBJECTS"
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "replay-sample: $1 needs a value"
    case "$1" in
      --sample) sample="$2" ;;
      --gate-cmd) gate_cmd_str="$2" ;;
      --cold-runs) cold_runs="$2" ;;
      --warm-runs) warm_runs="$2" ;;
      --repo-root) repo_root="$2" ;;
      --worktree-root) worktree_root="$2" ;;
      --min-free-kb) min_free_kb="$2" ;;
      --min-free-kb-objects) min_free_kb_objects="$2" ;;
      --timeout-s) timeout_s="$2" ;;
      --out) out="$2" ;;
      *) die "replay-sample: unknown argument: $1" ;;
    esac
    shift 2
  done
  [ -n "$sample" ] || die "replay-sample: --sample is required"
  [ -n "$gate_cmd_str" ] || die "replay-sample: --gate-cmd is required"
  [ -n "$out" ] || die "replay-sample: --out is required"
  [ -n "$_FC_OUT_OVERRIDE" ] && out="$_FC_OUT_OVERRIDE"
  validate_run_counts "$cold_runs" "$warm_runs" "$timeout_s" "$min_free_kb" "$min_free_kb_objects"
  parse_gate_cmd "$gate_cmd_str"
  [ -f "$sample" ] || blind "--sample file not found: $sample"
  [ -n "$repo_root" ] || repo_root="$DEFAULT_REPO_ROOT"
  repo_root="$(cd "$repo_root" 2>/dev/null && pwd)" || blind "cannot resolve --repo-root"
  [ -n "$worktree_root" ] || worktree_root="$repo_root/.fc_worktrees"
  # T043 round-4 finding B3: resolve --worktree-root to one absolute path up
  # front (see cmd_replay).
  mkdir -p "$worktree_root" 2>/dev/null || die "replay-sample: cannot create --worktree-root $worktree_root"
  worktree_root="$(cd "$worktree_root" 2>/dev/null && pwd)" || die "replay-sample: cannot resolve --worktree-root $worktree_root to an absolute path"
  local db_path="$repo_root/docs/workable_items.db"

  _fc_supervise "$repo_root" "$worktree_root"   # the caller's process becomes the supervisor here
  run_selfcheck || return 3

  # Item ids are read as NUL-separated DATA (R6-F5: the sample path used to be
  # spliced into Python source, and ids were split on newlines).
  local ids_file entries_file
  ids_file="$(_fc_mktemp)" || blind "mktemp failed"
  entries_file="$(_fc_mktemp)" || blind "mktemp failed"
  python3 - "$sample" >"$ids_file" <<'PY' || { rm -f "$ids_file" "$entries_file"; blind "--sample is not a readable select_sample.py output doc (an object with an 'items' list of {item_id: <non-empty string without whitespace>})"; }
import json, sys
doc = json.load(open(sys.argv[1]))
items = doc.get("items") if isinstance(doc, dict) else None
if not isinstance(items, list):
    sys.exit(4)
for it in items:
    iid = it.get("item_id") if isinstance(it, dict) else None
    # T048 restart round 2 (V4-6 class): a blank / whitespace-carrying id is not
    # an id (`git log --grep " "` matches every commit).
    if not isinstance(iid, str) or not iid or "\0" in iid or any(c.isspace() for c in iid):
        sys.exit(4)
    sys.stdout.write(iid + "\0")
PY

  local item_id n_harness=0
  while IFS= read -r -d '' item_id; do
    local entry_kind="" commit="" tree="" body_file="" reason=""
    if ! freeze_to_body "$item_id" "$repo_root" "$db_path"; then
      entry_kind=harness; reason="freeze BLIND: ${FZ_ERR:-tracker DB unreadable}"
    elif [ "$FZ_SHA" = UNMEASURED ]; then
      entry_kind=skipped; reason="freeze UNMEASURED (no subject-matching commit found)"
    else
      commit="$FZ_SHA"; tree="$FZ_TREE"
      body_file="$(_fc_mktemp)" || blind "mktemp failed"
      if run_replay_isolated "$body_file" "$commit" "$tree" "$repo_root" "$worktree_root" "$min_free_kb" \
           "$timeout_s" "$cold_runs" "$warm_runs" "$min_free_kb_objects" "${GATE_ARGV[@]}"; then
        entry_kind=replayed
      else
        entry_kind=harness; reason="replay harness error rc=$?"
      fi
    fi
    [ "$entry_kind" = harness ] && n_harness=$((n_harness + 1))
    python3 - "$entry_kind" "$item_id" "$commit" "$tree" "$reason" "$body_file" >>"$entries_file" <<'PY' || blind "cannot record the replay-sample entry for an item"
import json, sys
kind, iid, commit, tree, reason, body_file = sys.argv[1:7]
e = {"item_id": iid}
if kind == "replayed":
    b = json.load(open(body_file))
    e.update(skipped=False, skip_reason=None, commit=b["commit"], tree=b["tree"],
             tree_verified=b["tree_verified"], median_ms=b["median_ms"], verdict_set=b["verdict_set"],
             log_dir=b["log_dir"], harness_error=b["harness_error"])
else:
    e.update(skipped=True, skip_reason=reason, harness_error=(kind == "harness"))
    if commit:
        e.update(commit=commit, tree=tree)
print(json.dumps(e))
PY
    if [ "$entry_kind" = replayed ] && [ "$(body_field "$body_file" harness_error)" = true ]; then
      n_harness=$((n_harness + 1))
    fi
    [ -n "$body_file" ] && rm -f "$body_file"
  done <"$ids_file"
  rm -f "$ids_file"

  local body
  body="$(python3 - "$sample" "$cold_runs" "$warm_runs" "$entries_file" "${GATE_ARGV[@]}" <<'PY'
import json, sys
a = sys.argv
items = [json.loads(l) for l in open(a[4]) if l.strip()]
print(json.dumps({"sample_path": a[1], "gate_cmd": a[5:], "cold_runs": int(a[2]),
                  "warm_runs": int(a[3]), "items": items}))
PY
)" || { rm -f "$entries_file"; blind "cannot assemble the replay-sample report"; }
  rm -f "$entries_file"
  emit_doc "baseline-replay-sample/v1" "$body" "$out" || return $?
  # R6-F3/F8/F12 class: an item that could not be measured because the HARNESS
  # failed (freeze BLIND, worktree/submodule failure, a gate that never started)
  # is recorded per item AND makes the whole run exit 4, never exit 0.
  if [ "$n_harness" -gt 0 ]; then
    echo "baseline_replay: BLIND: $n_harness sample item(s) could not be measured because the harness failed (see items[].skip_reason / harness_error in the report)" >&2
    return 4
  fi
  return 0
}

# T048 restart round 1 (R6-F12): FC_OUT (set by fc_common.py determinism-check
# for the command it re-runs) redirects THIS invocation's top-level --out only.
# It is captured once here and then removed from the environment, so no internal
# emit and no child process -- in particular the replayed gate, which may itself
# be an FC tool -- ever sees it. (Round 3: the supervisor hands it to the worker
# as FC_BR_OUT_OVERRIDE, which the worker reads and unsets the same way.)
_FC_OUT_OVERRIDE="${FC_OUT:-}"
unset FC_OUT

case "$SUBCMD" in
  replay|replay-sample|selfcheck)
    # the worker (started by the supervisor): take over the hand-off variables
    [ "${FC_BR_SUPERVISED:-}" = 1 ] && _fc_worker_init ;;
  freeze)
    # T048 restart round 2 (V4-9): one private temp directory, removed by the EXIT
    # trap (freeze starts no child that could outlive it)
    _FC_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/fc_baseline_replay.XXXXXX")" || { echo "baseline_replay: BLIND: cannot create a private temp directory under ${TMPDIR:-/tmp}" >&2; exit 4; }
    trap _fc_rm_tmpdir EXIT ;;
esac

case "$SUBCMD" in
  freeze) cmd_freeze "$@"; exit $? ;;
  selfcheck) cmd_selfcheck "$@"; exit $? ;;
  replay) cmd_replay "$@"; exit $? ;;
  replay-sample) cmd_replay_sample "$@"; exit $? ;;
  *) usage ;;
esac
