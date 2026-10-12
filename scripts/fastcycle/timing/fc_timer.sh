#!/bin/bash
# fc_timer.sh - monotonic per-section/per-gate timer library for spec-004 fastcycle
#               instrumentation (plan.md T-A01, T-A02; research.md DEC-05; tasks.md T028).
#
# Purpose : `source` this file once near the top of ANY bash script (a pre-build suite, a
#           commit wrapper, an exporter, a test runner) and wrap each timeable unit of work
#           (a SECTION banner, a single gate/check that may run long, a commit-path stage) in
#           `fc_timer_start <id>` ... `fc_timer_end` calls. Every completed pair appends exactly
#           ONE row to a caller-supplied TSV -- never a fixed/guessed row count -- carrying:
#           run id, candidate fingerprint, the id, monotonic start/end nanosecond timestamps,
#           the elapsed duration in milliseconds, a PASS/FAIL/WARN verdict, and a checks/
#           fails/warns count delta for that unit (DEC-05's `{run_id, section, start_ns,
#           end_ns, verdict, checks, fails, warns}` row shape, plus `candidate_fingerprint`
#           per T-A01's "key every row to the candidate fingerprint and a run id", plus a
#           convenience `duration_ms` column, plus a trailing free-form `extra` column so a
#           specific integration -- e.g. a per-remote push row -- can attach fields this
#           generic mechanism does not itself know about, without ever changing the column
#           count of any OTHER row).
#
# Usage   : source ".../constitution/scripts/fastcycle/timing/fc_timer.sh"
#           export FC_TIMER_TSV="qa-results/fastcycle/<run-id>/prebuild_sections.tsv"   # required
#                                                                                        # unless
#                                                                                        # FC_TIMING=0
#           fc_timer_track TESTS_PASSED ERRORS WARNINGS   # optional: auto-diff these globals
#           fc_timer_start "SECTION A: ..."
#           ... real work; log_pass/log_fail/log_warn increment the tracked globals ...
#           fc_timer_end                                   # writes one row, auto-diffed counts
#           fc_timer_start "gate:some-slow-check"
#           ...
#           fc_timer_gate_end                               # writes a row ONLY if > 1s (T-A01)
#
# Public functions:
#   fc_timer_track <checks_var> <fails_var> <warns_var>
#       Register the NAMES (not values) of three global integer counters the caller maintains
#       as running totals (e.g. pre_build_verification.sh's TESTS_PASSED/ERRORS/WARNINGS).
#       fc_timer_start snapshots their current values; fc_timer_end diffs them to get the
#       per-unit delta. Pass "" for any counter the caller does not have; its delta is then
#       always 0 unless overridden by fc_timer_end's --checks/--fails/--warns flags. Safe to
#       call again to change the registration; takes effect on the NEXT fc_timer_start.
#   fc_timer_start <id>
#       Push a new timing frame (id, start ns, counter snapshot) onto an internal stack.
#       Frames nest: fc_timer_start A; fc_timer_start B; fc_timer_end (ends B); fc_timer_end
#       (ends A) is valid and produces two independent, correctly-ordered rows. <id> is
#       REQUIRED and must be non-empty.
#   fc_timer_end [<expected_id>] [--checks N] [--fails N] [--warns N] [--extra STR]
#                [--min-ms N]
#       Pop the MOST RECENTLY pushed (innermost) frame, compute its elapsed duration and
#       counter deltas, derive a verdict (FAIL if fails>0, else WARN if warns>0, else PASS),
#       and append one row to $FC_TIMER_TSV. If a non-flag first argument is given it is
#       compared to the popped frame's id for a diagnostic warning only (mismatches never
#       abort -- the popped frame's OWN id and timing are always what gets written; this is
#       deliberate: a caller with genuinely nested/reordered sections still gets correct,
#       attributable rows). --checks/--fails/--warns, when given, OVERRIDE the auto-tracked
#       delta for that field. --extra attaches a free-form string (e.g. "remote=github;
#       tip=<hash>") as the row's trailing column. --min-ms N suppresses the row entirely
#       (the frame is still popped -- its time is simply not recorded) when the elapsed
#       duration is below N milliseconds -- this is the primitive T-A01's "per-gate rows for
#       gates > 1 s" rule is built from; see fc_timer_gate_end for the convenience wrapper.
#       Calling fc_timer_end with an EMPTY stack is a non-fatal usage warning (stderr) that
#       returns 0 -- a caller with a conditional/early-exit branch that might legitimately
#       skip a matching fc_timer_start must not have its whole run aborted for this. A bad
#       flag, a non-numeric --checks/--fails/--warns/--min-ms value, or a `date` failure IS
#       fatal (return 2) -- those are genuine programmer/environment bugs worth catching
#       immediately, never silently tolerated (S11.4.6 fail-closed).
#   fc_timer_gate_start <id>
#       Alias for fc_timer_start (naming clarity only -- identical behaviour).
#   fc_timer_gate_end [<expected_id>] [--checks N] [--fails N] [--warns N] [--extra STR]
#                      [--min-ms N]
#       Identical to fc_timer_end, except when the caller does not supply --min-ms this
#       wrapper injects ${FC_TIMER_GATE_THRESHOLD_MS:-1000} (T-A01's "> 1 s" default,
#       overridable) -- so a bare `fc_timer_gate_end` only ever writes a row for a gate that
#       actually took longer than the threshold, exactly the T-A01 acceptance criterion.
#   fc_timer_init
#       Force-resolve (and memoize) the run id and candidate fingerprint now instead of
#       lazily on the first fc_timer_start. Idempotent; safe to call more than once or never
#       (fc_timer_start calls it internally on first use). Has no effect when FC_TIMING=0
#       (nothing to resolve for a run that will never write a row).
#   fc_timer_reset
#       Clear ALL internal state (stack, tracked-counter registration, memoized run id/
#       candidate fingerprint, rows-written count) so the NEXT fc_timer_start begins a fresh
#       run (a new run id, unless FC_TIMER_RUN_ID pins one). Intended for long-lived
#       processes/test harnesses that want to time several independent "runs" without
#       re-sourcing this file (re-sourcing is itself a safe no-op -- see "Idempotent sourcing"
#       below -- it does NOT reset state).
#   fc_timer_enabled
#       Return code 0 if timing is currently enabled, 1 if FC_TIMING=0. Pure query, no side
#       effects.
#   fc_timer_run_id
#       Print (stdout) the current run's id, resolving/memoizing it first if not already
#       resolved. Works regardless of FC_TIMING (an explicit, caller-requested introspection
#       query is not part of the automatic per-section hot path "no-op" contract below).
#   fc_timer_candidate_fingerprint
#       Print (stdout) the current run's candidate fingerprint (see CANDIDATE FINGERPRINT
#       RESOLUTION below), resolving/memoizing it first if not already resolved. Same
#       FC_TIMING-independence as fc_timer_run_id.
#   fc_timer_stack_depth
#       Print (stdout) the number of currently-open (started, not yet ended) frames. A
#       non-zero value at the natural end of a caller's script means one or more
#       fc_timer_start calls were never matched by fc_timer_end -- the caller MAY choose to
#       check and warn about this (this library does not do so automatically: an automatic
#       warning would itself be output the golden-output "instrumentation changes nothing"
#       rule must never introduce).
#   fc_timer_rows_written
#       Print (stdout) the total number of rows actually appended to $FC_TIMER_TSV so far in
#       the current process (across fc_timer_reset boundaries this counts from the last
#       reset). Useful for tests and for a caller wanting to confirm at least one row landed.
#   fc_timer_close_all [--rc N] [--note STR] / fc_timer_install_exit_flush [--signals] /
#   fc_timer_run <command> [args...]
#       The exit/signal flush and its interruptible-child runner -- documented in full at their
#       definitions near the end of this file. Short form: install the flush once; pass
#       --signals ONLY if every long foreground child is run through fc_timer_run (a trapped
#       signal is otherwise deferred by bash until that child exits -- see the T048 round-5 F-A
#       note there).
#
# FC_TIMING no-op contract (T028 acceptance criterion, T-A01/T-A02 "Rollback": "timers are
#   wrapped in a function that is a no-op when FC_TIMING=0"): when the literal string "0" is
#   the value of $FC_TIMING, fc_timer_start / fc_timer_gate_start / fc_timer_end /
#   fc_timer_gate_end / fc_timer_track become TRUE no-ops -- they touch NEITHER the internal
#   stack NOR the filesystem NOR the clock, and always return 0. Any other value of
#   $FC_TIMING (including unset, empty, "1", or garbage) means ENABLED -- this library
#   defaults to instrumenting, consistent with T-A01's timers being additive/always-on by
#   default and opt-OUT via FC_TIMING=0, never opt-in. (fc_timer_track's registration call
#   itself is harmless and inert either way -- it only ever affects behaviour indirectly,
#   through a later fc_timer_start/fc_timer_end, both of which already honour FC_TIMING --
#   so it is intentionally NOT gated on FC_TIMING here.) fc_timer_run_id/
#   fc_timer_candidate_fingerprint/fc_timer_stack_depth/fc_timer_rows_written/fc_timer_enabled
#   are pure introspection and are NEVER part of a script's automatic per-section timing
#   path -- they are unaffected by FC_TIMING by design (see their own docs above).
#
# RUN ID RESOLUTION: $FC_TIMER_RUN_ID if set (caller-pinned, e.g. so several sourcing scripts
#   in one logical pipeline share one run id); otherwise generated once per process as
#   "<UTC compact timestamp>_<pid>" (e.g. "20260928T103245Z_48213") -- unique per real
#   invocation, sortable, and never re-derived mid-run (memoized after the first
#   fc_timer_start/fc_timer_init/fc_timer_run_id/fc_timer_candidate_fingerprint call, so every
#   row in one process's TSV output shares the identical run id).
#
# CANDIDATE FINGERPRINT RESOLUTION: $FC_TIMER_CANDIDATE_FINGERPRINT if set (caller-pinned);
#   otherwise `git -C "$FC_TIMER_REPO_ROOT" rev-parse HEAD` where $FC_TIMER_REPO_ROOT defaults
#   to the directory FOUR levels above this file's own resolved location
#   (constitution/scripts/fastcycle/timing/fc_timer.sh -> ../../../.. = the consuming
#   project's repo root, per the S11.4.28/S11.4.177 "consumed by reference, never copied"
#   layout every project incorporating this constitution shares) -- this is deliberately
#   ANCHORED TO THIS FILE'S OWN PATH, not the caller's current working directory, so the
#   fingerprint is stable regardless of what directory the sourcing script happens to be
#   running from. If `git rev-parse HEAD` fails (not a git checkout, git absent, detached
#   worktree oddities) the fingerprint is the literal string "UNKNOWN" -- never a crash, never
#   a silently-empty field.
#
# Honest limits (S11.4.6 -- stated, not hidden):
#   - `date +%s%N` is WALL-CLOCK time, not a true CLOCK_MONOTONIC reading (GNU `date` exposes
#     no such clock). It is the exact mechanism plan.md T-A01 names ("monotonic `date +%s%N`
#     start/end") and is used here verbatim; a backward clock adjustment mid-section would
#     yield a negative raw delta, which this library clamps to 0ms rather than emitting a
#     negative/nonsensical duration -- it does NOT retroactively correct the recorded
#     start_ns/end_ns fields themselves, which remain the real, unmodified `date` output.
#   - `%N` (nanoseconds) is a GNU coreutils extension; a non-GNU `date` (e.g. unpatched BSD/
#     macOS) either errors or emits a literal "N" -- fc_timer_start/fc_timer_end validate the
#     `date +%s%N` output is all-decimal-digits and FAIL CLOSED (return 2, clear stderr
#     message) rather than silently computing garbage arithmetic on a malformed timestamp.
#   - Concurrent processes appending to the SAME $FC_TIMER_TSV path are NOT synchronised by
#     this library (no locking). A single `printf ... >>` append is one write(2) call, which
#     is atomic on POSIX filesystems for rows well under the typical PIPE_BUF/block size, but
#     genuinely concurrent multi-process writers to one TSV path must serialise themselves.
#   - Toggling $FC_TIMING between a fc_timer_start and its matching fc_timer_end for the SAME
#     frame (enabled at start, disabled at end, or vice versa) is unsupported: the frame is
#     silently left dangling (never written) rather than crashing -- this library assumes
#     FC_TIMING is stable for the lifetime of any single start/end pair, which is how every
#     documented caller uses it.
#
# Idempotent sourcing: sourcing this file more than once in the same process is a safe no-op
#   after the first time (function definitions and state are established once; state is never
#   reset by a re-source -- use fc_timer_reset for that). Executing this file directly
#   (`bash fc_timer.sh` / `./fc_timer.sh`) instead of sourcing it is refused with a clear
#   usage message and exit 1 -- it defines functions for a caller to use and has no useful
#   standalone behaviour of its own.
#
# Zero stdout in the hot path: fc_timer_start/fc_timer_end/fc_timer_gate_start/
#   fc_timer_gate_end/fc_timer_track/fc_timer_init NEVER write to stdout on success (only
#   diagnostics, always to stderr, on genuine usage errors) -- this is load-bearing for the
#   plan.md "Rule for every A-task" golden-output guarantee (instrumentation must not change
#   any verdict a wrapped script prints to stdout).
#
# Dependencies: bash (array + indirect-parameter-expansion features; tested against bash
#   5.2), coreutils `date` with GNU %N support, `git` (optional -- only needed for the default
#   candidate-fingerprint resolution; absence degrades to "UNKNOWN", never a crash).
# See: contracts/common-conventions.md (fc_timer.sh predates a dedicated contract -- it is
#   explicitly listed there under "Tool map ... no contract in this directory covers"; this
#   header is its interface of record until one is written). S11.4.115(F) (candidate
#   fingerprint), S11.4.6 (fail-closed / no-guessing), S11.4.28 / S11.4.177 (consumed by
#   reference from constitution/scripts/fastcycle/, never copied).

# --- refuse direct execution: this file only makes sense sourced ---
if ! (return 0 2>/dev/null); then
  echo "fc_timer.sh: this is a library, meant to be 'source'd, not executed directly." >&2
  echo "Usage: source \".../constitution/scripts/fastcycle/timing/fc_timer.sh\"" >&2
  echo "       fc_timer_start <id> ; ... ; fc_timer_end" >&2
  exit 1
fi

# --- idempotent sourcing guard: a second `source` of this file is a safe no-op ---
if [ -n "${_FC_TIMER_SH_LOADED:-}" ]; then
  return 0
fi
_FC_TIMER_SH_LOADED=1

# Resolve this file's own directory once, at source time, independent of the caller's cwd
# (BASH_SOURCE[0] inside a function defined in THIS file always refers to THIS file's path,
# regardless of where the caller invoked that function from or what its own cwd is).
_FC_TIMER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_FC_TIMER_DEFAULT_REPO_ROOT="$(cd "$_FC_TIMER_LIB_DIR/../../../.." && pwd)"

FC_TIMER_GATE_THRESHOLD_MS_DEFAULT=1000

# --- internal state (never read or written directly by callers -- use the public functions) ---
_FC_TIMER_STACK_ID=()
_FC_TIMER_STACK_START_NS=()
_FC_TIMER_STACK_CHK0=()
_FC_TIMER_STACK_FAIL0=()
_FC_TIMER_STACK_WARN0=()
_FC_TIMER_TRACK_CHECKS_VAR=""
_FC_TIMER_TRACK_FAILS_VAR=""
_FC_TIMER_TRACK_WARNS_VAR=""
_FC_TIMER_RUN_ID=""
_FC_TIMER_CANDIDATE_FINGERPRINT=""
_FC_TIMER_INITED=0
_FC_TIMER_ROWS_WRITTEN=0
_FC_TIMER_EXIT_FLUSH_INSTALLED=0
_FC_TIMER_SIGNALS_ARMED=0
# T048 round-5 F-D: the signal marker is OWNED by this library and starts EMPTY in every process.
# It was previously first assigned inside a signal handler only, so a value inherited from the
# environment (an exported _FC_TIMER_SIGNAL_RC=143 in a parent) made a CLEAN `exit 0` record its
# open frame `FAIL rc=143` (measured). `unset` first also drops any export attribute, so the
# marker is never re-exported to this process's children either.
unset _FC_TIMER_SIGNAL_RC
# T048 restart round-1 R1-I1 (2026-10-08): the run id's timestamp half is minted HERE, in the
# shell that sources this file, never lazily inside a resolver. Every documented caller reads
# the run id through a `$(fc_timer_run_id)` command substitution -- a SUBSHELL whose
# memoisation can never reach the parent -- so a lazily-minted "<now>_<pid>" was re-minted by
# each such read and two reads straddling a second boundary disagreed (measured: 4 of 151 real
# commit TSVs carried a row run_id that differed from their own filename stem). `$$` is the
# PARENT's pid in every subshell, so "<source-time ts>_$$" is identical in the parent and in
# every subshell of it, memoised or not -- the class (any caller, any number of $(...) reads)
# is closed at the library, not per call site. fc_timer_reset re-mints it for a new run.
_FC_TIMER_SOURCE_TS="$(date -u +%Y%m%dT%H%M%SZ)"

# _fc_timer_enabled -- 0 (true) unless FC_TIMING is exactly "0".
_fc_timer_enabled() {
  case "${FC_TIMING:-1}" in
    0) return 1 ;;
    *) return 0 ;;
  esac
}
fc_timer_enabled() { _fc_timer_enabled; }

# _fc_timer_is_uint <str> -- true iff <str> is one or more decimal digits (non-negative
# integer, no sign, no leading/trailing junk). Used to validate every numeric value this
# library arithmetic-evaluates before it ever reaches a bash `$(( ))` expression.
_fc_timer_is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# _fc_timer_norm <str> -- strip leading zeros from a validated non-negative-integer string
# (avoids bash `$(( ))` treating a leading-zero literal as octal, e.g. `$((08))` errors and
# `$((010))` == 8, not 10). Mirrors host_guard.sh's norm() in this same directory tree.
_fc_timer_norm() {
  local v="$1"
  while :; do
    case "$v" in
      0?*) v="${v#0}" ;;
      *) break ;;
    esac
  done
  printf '%s' "$v"
}

# _fc_timer_indirect <varname> -- print the current value of the global variable NAMED by
# <varname>, or "" if <varname> is empty or names an unset variable. Never errors under
# `set -u`, even when <varname> refers to a variable that does not exist.
_fc_timer_indirect() {
  local name="$1"
  if [ -z "$name" ]; then
    printf '%s' ""
    return 0
  fi
  if [ -n "${!name+x}" ]; then
    printf '%s' "${!name}"
  else
    printf '%s' ""
  fi
}

fc_timer_track() {
  _FC_TIMER_TRACK_CHECKS_VAR="${1:-}"
  _FC_TIMER_TRACK_FAILS_VAR="${2:-}"
  _FC_TIMER_TRACK_WARNS_VAR="${3:-}"
  return 0
}

_fc_timer_ensure_init() {
  if [ "$_FC_TIMER_INITED" = 1 ]; then
    return 0
  fi
  if [ -n "${FC_TIMER_RUN_ID:-}" ]; then
    _FC_TIMER_RUN_ID="$FC_TIMER_RUN_ID"
  else
    _FC_TIMER_RUN_ID="${_FC_TIMER_SOURCE_TS}_$$"
  fi
  if [ -n "${FC_TIMER_CANDIDATE_FINGERPRINT:-}" ]; then
    _FC_TIMER_CANDIDATE_FINGERPRINT="$FC_TIMER_CANDIDATE_FINGERPRINT"
  else
    local root fp
    root="${FC_TIMER_REPO_ROOT:-$_FC_TIMER_DEFAULT_REPO_ROOT}"
    fp="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || fp=""
    if [ -z "$fp" ]; then
      fp="UNKNOWN"
    fi
    _FC_TIMER_CANDIDATE_FINGERPRINT="$fp"
  fi
  _FC_TIMER_INITED=1
  return 0
}
fc_timer_init() {
  if ! _fc_timer_enabled; then
    return 0
  fi
  _fc_timer_ensure_init
}

fc_timer_run_id() {
  _fc_timer_ensure_init
  printf '%s\n' "$_FC_TIMER_RUN_ID"
}
fc_timer_candidate_fingerprint() {
  _fc_timer_ensure_init
  printf '%s\n' "$_FC_TIMER_CANDIDATE_FINGERPRINT"
}
fc_timer_stack_depth() {
  printf '%s\n' "${#_FC_TIMER_STACK_ID[@]}"
}
fc_timer_rows_written() {
  printf '%s\n' "$_FC_TIMER_ROWS_WRITTEN"
}

fc_timer_reset() {
  _FC_TIMER_STACK_ID=()
  _FC_TIMER_STACK_START_NS=()
  _FC_TIMER_STACK_CHK0=()
  _FC_TIMER_STACK_FAIL0=()
  _FC_TIMER_STACK_WARN0=()
  _FC_TIMER_TRACK_CHECKS_VAR=""
  _FC_TIMER_TRACK_FAILS_VAR=""
  _FC_TIMER_TRACK_WARNS_VAR=""
  _FC_TIMER_RUN_ID=""
  _FC_TIMER_CANDIDATE_FINGERPRINT=""
  _FC_TIMER_INITED=0
  _FC_TIMER_ROWS_WRITTEN=0
  _FC_TIMER_SOURCE_TS="$(date -u +%Y%m%dT%H%M%SZ)"
  return 0
}

# _fc_timer_ensure_tsv -- create $FC_TIMER_TSV (and its parent directory) with the canonical
# header row if it does not already exist. Fails closed (return 2) if FC_TIMER_TSV is unset
# (S11.4.6: never guess an output path) or cannot be created/written.
_fc_timer_ensure_tsv() {
  local tsv="${FC_TIMER_TSV:-}"
  if [ -z "$tsv" ]; then
    echo "fc_timer: FC_TIMER_TSV is not set -- refusing to guess an output path (timing is" >&2
    echo "          enabled; either export FC_TIMER_TSV=<path> or set FC_TIMING=0)" >&2
    return 2
  fi
  if [ ! -f "$tsv" ]; then
    mkdir -p "$(dirname "$tsv")" 2>/dev/null || { echo "fc_timer: cannot create directory for FC_TIMER_TSV=$tsv" >&2; return 2; }
    printf 'run_id\tcandidate_fingerprint\tid\tstart_ns\tend_ns\tduration_ms\tverdict\tchecks\tfails\twarns\textra\n' > "$tsv" 2>/dev/null || { echo "fc_timer: cannot write header to FC_TIMER_TSV=$tsv" >&2; return 2; }
  fi
  return 0
}

# _fc_timer_now_ns -- print `date +%s%N`, validated as all-decimal-digits. Fails closed
# (return 2) on a non-GNU `date` or any other malformed output.
_fc_timer_now_ns() {
  local ns
  ns="$(date +%s%N 2>/dev/null)" || { echo "fc_timer: 'date +%s%N' failed to run" >&2; return 2; }
  _fc_timer_is_uint "$ns" || { echo "fc_timer: 'date +%s%N' produced a non-numeric timestamp ('$ns') -- is this GNU date (coreutils)? %N (nanoseconds) is a GNU extension." >&2; return 2; }
  printf '%s' "$ns"
  return 0
}

fc_timer_start() {
  if ! _fc_timer_enabled; then
    return 0
  fi
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "fc_timer_start: missing required <id> argument" >&2
    return 2
  fi
  _fc_timer_ensure_init
  _fc_timer_ensure_tsv || return $?
  local start_ns
  start_ns="$(_fc_timer_now_ns)" || return $?
  local chk0 fail0 warn0
  chk0="$(_fc_timer_indirect "$_FC_TIMER_TRACK_CHECKS_VAR")"
  fail0="$(_fc_timer_indirect "$_FC_TIMER_TRACK_FAILS_VAR")"
  warn0="$(_fc_timer_indirect "$_FC_TIMER_TRACK_WARNS_VAR")"
  _fc_timer_is_uint "$chk0" || chk0=0
  _fc_timer_is_uint "$fail0" || fail0=0
  _fc_timer_is_uint "$warn0" || warn0=0
  _FC_TIMER_STACK_ID+=("$id")
  _FC_TIMER_STACK_START_NS+=("$start_ns")
  _FC_TIMER_STACK_CHK0+=("$chk0")
  _FC_TIMER_STACK_FAIL0+=("$fail0")
  _FC_TIMER_STACK_WARN0+=("$warn0")
  return 0
}
fc_timer_gate_start() {
  fc_timer_start "$@"
}

fc_timer_end() {
  if ! _fc_timer_enabled; then
    return 0
  fi
  # ALL argument validation happens HERE, entirely BEFORE any stack pop below, by design: a
  # caller who passes a bad flag or a non-numeric value gets return 2 with the OFFENDING
  # frame still intact on the stack (fc_timer_stack_depth unchanged) -- they can fix the call
  # and retry fc_timer_end without having silently lost that frame's timing data. This is
  # deliberately different from "no active timer to end" (empty stack) and "expected id
  # mismatch" below, which are non-fatal usage NOTES about a frame that WAS validly ended.
  local expect_id="" checks="" fails="" warns="" extra="" min_ms=""
  if [ $# -gt 0 ]; then
    case "$1" in
      --*) : ;;
      *) expect_id="$1"; shift ;;
    esac
  fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --checks)
        [ $# -ge 2 ] || { echo "fc_timer_end: --checks requires a value" >&2; return 2; }
        _fc_timer_is_uint "$2" || { echo "fc_timer_end: --checks must be a non-negative integer: '$2'" >&2; return 2; }
        checks="$(_fc_timer_norm "$2")"; shift 2 ;;
      --fails)
        [ $# -ge 2 ] || { echo "fc_timer_end: --fails requires a value" >&2; return 2; }
        _fc_timer_is_uint "$2" || { echo "fc_timer_end: --fails must be a non-negative integer: '$2'" >&2; return 2; }
        fails="$(_fc_timer_norm "$2")"; shift 2 ;;
      --warns)
        [ $# -ge 2 ] || { echo "fc_timer_end: --warns requires a value" >&2; return 2; }
        _fc_timer_is_uint "$2" || { echo "fc_timer_end: --warns must be a non-negative integer: '$2'" >&2; return 2; }
        warns="$(_fc_timer_norm "$2")"; shift 2 ;;
      --extra)
        [ $# -ge 2 ] || { echo "fc_timer_end: --extra requires a value" >&2; return 2; }
        extra="$2"; shift 2 ;;
      --min-ms)
        [ $# -ge 2 ] || { echo "fc_timer_end: --min-ms requires a value" >&2; return 2; }
        _fc_timer_is_uint "$2" || { echo "fc_timer_end: --min-ms must be a non-negative integer: '$2'" >&2; return 2; }
        min_ms="$(_fc_timer_norm "$2")"; shift 2 ;;
      *) echo "fc_timer_end: unknown argument: $1" >&2; return 2 ;;
    esac
  done

  local depth=${#_FC_TIMER_STACK_ID[@]}
  if [ "$depth" -eq 0 ]; then
    echo "fc_timer_end: warning -- no active timer to end (stack is empty); ignoring" >&2
    return 0
  fi
  local idx=$((depth - 1))
  local id="${_FC_TIMER_STACK_ID[$idx]}"
  local start_ns="${_FC_TIMER_STACK_START_NS[$idx]}"
  local chk0="${_FC_TIMER_STACK_CHK0[$idx]}"
  local fail0="${_FC_TIMER_STACK_FAIL0[$idx]}"
  local warn0="${_FC_TIMER_STACK_WARN0[$idx]}"
  # T048 round-5 F-E: the frame is NOT popped here. It is popped only once its row is durably
  # appended (or deliberately suppressed by --min-ms) -- see _fc_timer_pop below -- so a `date`
  # failure, an unwritable TSV, or an exit flush that runs mid-call never loses a validly-started
  # frame: the frame stays on the stack, fc_timer_end returns 2, and the caller (or the exit
  # flush) can still record it.

  if [ -n "$expect_id" ] && [ "$expect_id" != "$id" ]; then
    echo "fc_timer_end: warning -- expected to end '$expect_id' but the innermost open timer is '$id'; ending '$id' (the actual innermost frame is always what gets recorded)" >&2
  fi

  # A `date +%s%N` failure here returns 2 with the frame STILL on the stack (round-5 F-E).
  local end_ns
  end_ns="$(_fc_timer_now_ns)" || return $?

  chk0="$(_fc_timer_norm "$chk0")"
  fail0="$(_fc_timer_norm "$fail0")"
  warn0="$(_fc_timer_norm "$warn0")"
  local start_ns_n end_ns_n
  start_ns_n="$(_fc_timer_norm "$start_ns")"
  end_ns_n="$(_fc_timer_norm "$end_ns")"
  local duration_ms=$(( (end_ns_n - start_ns_n) / 1000000 ))
  [ "$duration_ms" -ge 0 ] || duration_ms=0

  if [ -n "$min_ms" ] && [ "$duration_ms" -lt "$min_ms" ]; then
    _fc_timer_pop "$idx"
    return 0
  fi

  local chk1 fail1 warn1
  if [ -n "$checks" ]; then
    chk1="$checks"
  else
    local v vn
    v="$(_fc_timer_indirect "$_FC_TIMER_TRACK_CHECKS_VAR")"
    if _fc_timer_is_uint "$v"; then vn="$(_fc_timer_norm "$v")"; chk1=$((vn - chk0)); [ "$chk1" -ge 0 ] || chk1=0; else chk1=0; fi
  fi
  if [ -n "$fails" ]; then
    fail1="$fails"
  else
    local v vn
    v="$(_fc_timer_indirect "$_FC_TIMER_TRACK_FAILS_VAR")"
    if _fc_timer_is_uint "$v"; then vn="$(_fc_timer_norm "$v")"; fail1=$((vn - fail0)); [ "$fail1" -ge 0 ] || fail1=0; else fail1=0; fi
  fi
  if [ -n "$warns" ]; then
    warn1="$warns"
  else
    local v vn
    v="$(_fc_timer_indirect "$_FC_TIMER_TRACK_WARNS_VAR")"
    if _fc_timer_is_uint "$v"; then vn="$(_fc_timer_norm "$v")"; warn1=$((vn - warn0)); [ "$warn1" -ge 0 ] || warn1=0; else warn1=0; fi
  fi

  local verdict
  if [ "$fail1" -gt 0 ]; then
    verdict=FAIL
  elif [ "$warn1" -gt 0 ]; then
    verdict=WARN
  else
    verdict=PASS
  fi

  _fc_timer_ensure_init
  _fc_timer_ensure_tsv || return $?

  local safe_id safe_extra
  safe_id="$(printf '%s' "$id" | tr '\t\n\r' '   ')"
  safe_extra="$(printf '%s' "$extra" | tr '\t\n\r' '   ')"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$_FC_TIMER_RUN_ID" "$_FC_TIMER_CANDIDATE_FINGERPRINT" "$safe_id" \
    "$start_ns" "$end_ns" "$duration_ms" "$verdict" "$chk1" "$fail1" "$warn1" "$safe_extra" \
    >> "$FC_TIMER_TSV" 2>/dev/null || { echo "fc_timer_end: failed to append row to FC_TIMER_TSV=$FC_TIMER_TSV (frame '$id' kept on the stack)" >&2; return 2; }

  # Honest residual (round-5 F-E, S11.4.6): the append and the pop are two commands, and bash
  # runs a pending trap between commands. A trapped signal (fc_timer_install_exit_flush
  # --signals) arriving in exactly that window makes the signal flush record this frame a
  # SECOND time (an `aborted` row after the real one, same id). That duplicate is visible in
  # the TSV; the alternative order (pop first) silently LOST the frame instead.
  _fc_timer_pop "$idx"
  _FC_TIMER_ROWS_WRITTEN=$((_FC_TIMER_ROWS_WRITTEN + 1))
  return 0
}

# _fc_timer_pop <idx> -- drop stack frame <idx> (always the innermost) from every parallel array.
_fc_timer_pop() {
  local idx="$1"
  unset "_FC_TIMER_STACK_ID[$idx]" "_FC_TIMER_STACK_START_NS[$idx]" \
        "_FC_TIMER_STACK_CHK0[$idx]" "_FC_TIMER_STACK_FAIL0[$idx]" "_FC_TIMER_STACK_WARN0[$idx]"
}

fc_timer_gate_end() {
  # T048 restart round-1 R1-m4: scan FLAGS, never values -- every value-taking flag skips its
  # value, so `--extra --min-ms` (a VALUE that reads like a flag) can no longer switch the
  # default gate threshold off. fc_timer_end itself still validates everything.
  local has_min=0 i=1 a
  if [ $# -gt 0 ]; then
    case "$1" in --*) : ;; *) i=2 ;; esac
  fi
  while [ "$i" -le $# ]; do
    a="${!i}"
    case "$a" in
      --min-ms) has_min=1; i=$((i + 2)) ;;
      --checks|--fails|--warns|--extra) i=$((i + 2)) ;;
      *) i=$((i + 1)) ;;
    esac
  done
  if [ "$has_min" = 1 ]; then
    fc_timer_end "$@"
  else
    fc_timer_end "$@" --min-ms "${FC_TIMER_GATE_THRESHOLD_MS:-$FC_TIMER_GATE_THRESHOLD_MS_DEFAULT}"
  fi
}

# fc_timer_close_all [--rc N] [--note STR] -- T048 restart round-1 R1-I2 (the open-frame-at-exit
#   CLASS): pop EVERY still-open frame, innermost first, writing one row each with extra
#   "result=aborted;rc=N<STR>" and a FAIL verdict when N != 0 (WARN when N == 0: a frame still
#   open at a clean exit is a wiring bug, never a silent PASS). A no-op (zero rows, zero output)
#   on an empty stack or when FC_TIMING=0. Never writes to stdout. Returns 0.
fc_timer_close_all() {
  local rc=0 note=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rc) rc="${2:-0}"; shift 2 2>/dev/null || shift ;;
      --note) note="${2:-}"; shift 2 2>/dev/null || shift ;;
      *) shift ;;
    esac
  done
  _fc_timer_is_uint "$rc" || rc=255
  _fc_timer_enabled || return 0
  local guard=0
  while [ "${#_FC_TIMER_STACK_ID[@]}" -gt 0 ] && [ "$guard" -lt 1000 ]; do
    guard=$((guard + 1))
    if [ "$rc" -ne 0 ]; then
      fc_timer_end --extra "result=aborted;rc=$rc$note" --fails 1 2>/dev/null || break
    else
      fc_timer_end --extra "result=aborted;rc=$rc$note" --warns 1 2>/dev/null || break
    fi
  done
  return 0
}

# fc_timer_install_exit_flush [--signals] -- R1-I2: install ONE EXIT trap that runs
#   fc_timer_close_all with the process's real exit status, so every `exit N` / `set -e` abort /
#   refusal path records its open frames instead of silently losing them (one class-level flush
#   in place of a per-site end call at every exit). Composes with -- never replaces -- an EXIT
#   trap already installed: the prior trap runs afterwards and sees the ORIGINAL `$?`; the exit
#   status of the process is never changed. Idempotent. Call it AFTER any later `trap ... EXIT`
#   the caller installs (a later plain `trap` would otherwise replace it). An unknown argument
#   is refused (return 2, nothing installed).
#
#   SIGNALS ARE OPT-IN (T048 round-5 F-A; the measured model is
#   docs/qa/t048_restart_round5_20261009/V6_signal_model.md in the consuming project):
#     bash DEFERS a trapped signal until the running FOREGROUND child exits (measured, bash
#     5.2.37, all 11 signals below: a single-PID kill of a script whose trap was installed took
#     the child's full remaining run time to take effect; the same script without a trap died
#     in < 0.1 s). A library that silently trapped every catchable signal therefore made every
#     caller with a long foreground child (a git commit, a push, a build) unkillable by a
#     single-PID TERM/HUP/USR1/... for as long as that child ran. So:
#     * default (no flag) -> ONLY the EXIT trap. The process's signal behaviour is byte-for-byte
#       what it was without this library (measured parity, every signal in the class). The cost,
#       stated honestly: bash runs the EXIT trap on a fatal signal with `$?` = the last COMPLETED
#       command's status (measured: 0 for every class signal), so a signal death with an open
#       frame is recorded `WARN|result=aborted;rc=0;signals=untracked` -- the `signals=untracked`
#       note marks exactly the rows whose rc=0 cannot distinguish a signal death from a clean
#       exit with a frame left open (rc != 0 rows are already FAIL and carry no note). One class
#       member writes NO row at all in this mode: bash runs no EXIT trap for a death by SIGPROF
#       (measured), so a frame open at a PROF death is simply absent from the TSV (pinned by the
#       selftest, F-A-default-PROF). --signals closes that gap (the PROF handler writes the row).
#     * --signals -> additionally trap every signal in _FC_TIMER_FLUSH_SIGNALS (round-4 F1):
#         no prior trap      -> the handler closes every open frame with FAIL rc=128+N, restores
#                               the default disposition and RE-RAISES the signal, so the process
#                               still dies BY THE SIGNAL (WIFSIGNALED; a parent's SIGINT
#                               wait-and-cooperative-exit keeps working; `exit 130` would not);
#         prior trap ''      -> left alone: an IGNORED signal (the caller's choice, or nohup's /
#                               `&`'s SIG_IGN) is never re-armed;
#         prior trap <body>  -> composed: the body runs with _FC_TIMER_SIGNAL_RC=128+N set; if it
#                               exits, the EXIT flush records the frames FAIL rc=128+N (the
#                               process status stays the body's choice); if it RETURNS, the
#                               script continues exactly as before and the marker is cleared.
#       A caller passing --signals takes on ONE obligation: run every potentially long FOREGROUND
#       child through fc_timer_run (below), CALLED DIRECTLY IN THE ARMED SHELL, which keeps the
#       trapped signal deliverable at once. A child run plainly still defers the signal until it
#       exits (pinned by the selftest). So does fc_timer_run used inside a command substitution
#       `$(fc_timer_run ...)` or as a stage of a pipeline (V6 F2, measured: with a 3 s child and a
#       TERM sent at 0.4 s, both forms ended at ~3.06 s vs ~0.47 s called directly): the armed shell is then waiting on the substitution / pipeline, which
#       is itself a foreground child, and bash defers the trapped signal until that ends. Capture
#       output through a redirection to a file instead (`fc_timer_run cmd >"$out"`).
#     * with --signals, an armed exit with rc=0 (a clean `exit 0` with a frame left open, OR a
#       death by a signal outside the class, e.g. an external ABRT) records
#       `WARN|result=aborted;rc=0;signals=untracked-nonclass` -- never a bare clean exit (V6 F6).
#     * a FAIL rc=128+N row from a signal that arrived during fc_timer_run means that run's child
#       MAY STILL BE RUNNING (V6 N4): the flush never signals it (see fc_timer_run). The row does
#       not carry the child's pid -- the row shape is pinned exactly by its consumers.
#   Deliberately NOT trapped even with --signals (measured, documented gaps -- never silent):
#     * QUIT: bash IGNORES SIGQUIT in every mode (measured: the script survives it), so it is
#       not a death; trapping it would turn an ignored signal into a fatal one.
#     * ABRT SEGV BUS FPE ILL SYS TRAP (the synchronous-fault class): a shell trap on a real
#       fault makes bash's C handler return to the faulting instruction (a fault loop). An
#       EXTERNALLY sent one of these still records `WARN rc=0` -- the honest residual.
#     * KILL / STOP: untrappable by definition (no flush can run; the frame is simply absent).
#   The signal traps are installed only when timing is enabled at install time (FC_TIMING=0
#   must change nothing about the process's signal behaviour). A later plain `trap ... SIG` by
#   the caller replaces the corresponding handler, exactly as for EXIT.
_FC_TIMER_FLUSH_SIGNALS="HUP INT TERM USR1 USR2 ALRM PIPE XCPU XFSZ VTALRM PROF"

# _fc_timer_signal_flush <SIGNAME> <signum> -- the no-prior-trap handler (see above).
_fc_timer_signal_flush() {
  local name="$1" num="$2"
  _FC_TIMER_SIGNAL_RC=$((128 + num))
  set +e
  fc_timer_close_all --rc "$_FC_TIMER_SIGNAL_RC"
  trap - "$name"
  # §11.4.263: named-signal form `kill -s NAME PID` (never `kill -NAME`, the shape a negated
  # process-group target takes); $BASHPID is this shell itself, always an integer > 1.
  kill -s "$name" "$BASHPID"
  # Not reached when the signal is fatal by default; if a disposition we cannot see kept the
  # process alive, exit with the signal status rather than resume a half-interrupted script.
  exit "$_FC_TIMER_SIGNAL_RC"
}

# _fc_timer_exit_flush <exit status> -- the body of the EXIT trap (see above).
#   rc=0 with no signal marker cannot tell a clean exit with a frame left open from a death by a
#   signal nothing trapped, so such a row ALWAYS carries a note (V6 F6):
#     ;signals=untracked          -- installed without --signals (no signal is tracked);
#     ;signals=untracked-nonclass -- --signals armed, but a signal OUTSIDE the class (ABRT, SEGV,
#                                    ...) is never trapped, so it also lands here with rc=0.
_fc_timer_exit_flush() {
  local rc="${1:-0}" note=""
  if [ -n "${_FC_TIMER_SIGNAL_RC:-}" ]; then
    rc="$_FC_TIMER_SIGNAL_RC"
  elif [ "$rc" = 0 ]; then
    if [ "$_FC_TIMER_SIGNALS_ARMED" = 1 ]; then
      note=";signals=untracked-nonclass"
    else
      note=";signals=untracked"
    fi
  fi
  fc_timer_close_all --rc "$rc" --note "$note"
}

fc_timer_install_exit_flush() {
  local want_signals=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --signals) want_signals=1; shift ;;
      *) echo "fc_timer_install_exit_flush: unknown argument: $1 (only --signals is accepted)" >&2; return 2 ;;
    esac
  done
  if [ "$_FC_TIMER_EXIT_FLUSH_INSTALLED" != 1 ]; then
    local old
    old="$(trap -p EXIT)"
    old="${old#trap -- \'}"
    old="${old%\' EXIT}"
    old="${old//\'\\\'\'/\'}"
    # `set +e` inside the trap: under the caller's `set -e`, the `(exit N)` that re-arms `$?`
    # for the prior trap would itself abort the trap before the prior trap ever ran (measured).
    # The shell is already exiting, so dropping errexit here changes nothing else.
    # shellcheck disable=SC2064,SC2154  # SC2064: only ${old} (the caller's prior EXIT trap body) is expanded at install time, on purpose, to chain it; every other $ is \-escaped to expand at trap-fire time. SC2154: _fc_timer_exit_rc is assigned inside the trap string itself (_fc_timer_exit_rc=$?) when the trap fires, never in this scope
    trap "_fc_timer_exit_rc=\$?; set +e; _fc_timer_exit_flush \"\$_fc_timer_exit_rc\"; (exit \"\$_fc_timer_exit_rc\"); ${old}" EXIT
    _FC_TIMER_EXIT_FLUSH_INSTALLED=1
  fi
  if [ "$want_signals" = 1 ] && [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ] && _fc_timer_enabled; then
    local sig num prior body
    for sig in $_FC_TIMER_FLUSH_SIGNALS; do
      num="$(kill -l "$sig" 2>/dev/null)" || continue
      _fc_timer_is_uint "$num" || continue
      prior="$(trap -p "$sig")"
      if [ -z "$prior" ]; then
        # shellcheck disable=SC2064  # $sig and $num are bound by the enclosing for-loop and expanded at install time on purpose: each handler must carry its own signal name and number
        trap "_fc_timer_signal_flush $sig $num" "$sig"
        continue
      fi
      body="${prior#trap -- \'}"
      body="${body%\' SIG"$sig"}"
      body="${body%\' "$sig"}"
      body="${body//\'\\\'\'/\'}"
      if [ -z "$body" ]; then
        continue   # ignored (trap '' SIG): never re-arm it
      fi
      # shellcheck disable=SC2064  # $num (loop-bound signal number, for 128+num) and ${body} (this signal's prior trap body) are expanded at install time on purpose to chain it; the other $ are \-escaped to expand at signal time
      trap "_FC_TIMER_SIGNAL_RC=$((128 + num)); ${body}
_FC_TIMER_SIGNAL_RC=" "$sig"
    done
    _FC_TIMER_SIGNALS_ARMED=1
  fi
  return 0
}

# fc_timer_run <command> [args...] -- run <command> as a FOREGROUND-equivalent child that a
#   trapped signal can still interrupt (T048 round-5 F-A). Returns the command's exit status,
#   exactly as running it directly would (128+N when the child itself dies of signal N).
#   * signals NOT armed (no --signals install), FC_TIMING=0, or <command> is a shell function /
#     builtin / keyword: the command is simply run in place ("$@") -- zero behaviour change, and
#     a function keeps its ability to change the caller's state.
#   * signals armed and <command> is an external program: it is started in the background with
#     the dispositions it would have had in the foreground -- stdin is passed through explicitly
#     (bash would otherwise give a background job /dev/null), it is started from a subshell so
#     SIGINT/SIGQUIT are NOT ignored (bash ignores them in a bare `cmd &`), a caller's own ignore
#     (`trap '' INT`, nohup, `&`) is inherited just as a foreground child would inherit it -- and
#     then `wait`ed for. `wait` is interrupted by a trapped
#     signal at once (measured), so the flush runs and the process dies by the signal while the
#     child is still running. The child is NOT signalled by the flush: a single-PID kill of an
#     uninstrumented script also leaves its child running (measured), and a process-group kill
#     (terminal Ctrl-C, systemd, `timeout`) still reaches the child directly; so an aborted FAIL
#     row recorded during fc_timer_run may leave that child running (V6 N4). ANY trap whose handler
#     RETURNS interrupts `wait` too -- a composed prior trap, a trap on a signal outside the class
#     (WINCH), or a class trap the caller set after the install (V6 F1); fc_timer_run then keeps
#     waiting while the child is alive, so the status it returns is the child's own. Honest
#     residual: after 10000 such interruptions in one call it stops waiting and returns the last
#     `wait` status (128+N) with the child possibly still running -- a bound against a spin, never
#     reached by any realistic signal rate.
#   * call it DIRECTLY in the armed shell: inside `$(...)` or a pipeline it cannot help (see the
#     --signals obligation above).
fc_timer_run() {
  if [ $# -eq 0 ]; then
    echo "fc_timer_run: missing <command>" >&2
    return 2
  fi
  if [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ] || ! _fc_timer_enabled || [ "$(type -t -- "$1")" != file ]; then
    "$@"
    return $?
  fi
  local _fcr_pid _fcr_rc _fcr_guard=0
  # A `( ... ) &` SUBSHELL, never a bare `cmd &`: bash ignores SIGINT/SIGQUIT only in a bare
  # simple background command (measured, bash 5.2.37: `cmd &` -> SigIgn 0x6; `( exec cmd ) &`
  # -> 0x0), and the subshell resets the caller's signal HANDLERS to default while keeping an
  # IGNORE -- exactly what exec'ing the command in the foreground does. Pinned by the selftest
  # (F-A-run-intquit / F-A-run-ignored), so a bash that behaves otherwise fails loudly.
  if { true <&0; } 2>/dev/null; then
    ( exec "$@" ) <&0 &
  else
    ( exec "$@" ) <&- &
  fi
  _fcr_pid=$!
  # V6 F1: `wait` returns early whenever ANY trap whose handler RETURNS runs -- a composed class
  # handler, a trap on a signal outside the class (WINCH), or a class trap the caller set AFTER
  # the install -- with the child possibly still running. So: keep waiting while the child is
  # alive, then wait once more, which returns the child's OWN status (bash remembers a finished
  # child's status for a repeated wait -- also when it exited between an interrupted wait and the
  # probe). A class signal with no prior trap never returns here: its handler re-raises and the
  # process dies by the signal (FAIL rc=128+N row).
  while :; do
    _fcr_rc=0
    wait "$_fcr_pid" || _fcr_rc=$?
    _fcr_guard=$((_fcr_guard + 1))
    if kill -0 "$_fcr_pid" 2>/dev/null && [ "$_fcr_guard" -lt 10000 ]; then
      continue
    fi
    break
  done
  if ! kill -0 "$_fcr_pid" 2>/dev/null; then
    _fcr_rc=0
    wait "$_fcr_pid" 2>/dev/null || _fcr_rc=$?
  fi
  return "$_fcr_rc"
}

return 0
