#!/bin/bash
# fc_timer_selftest_mutations.sh - paired §1.1 mutation runner for fc_timer.sh / its selftest
#   (spec 004-fast-dev-cycles; T048 restart round-1, findings R1-I1/R1-I2/R1-I5/R1-m4).
#
# Purpose : prove fc_timer_selftest.sh is load-bearing. Each mutation below re-introduces one
#           real defect into a COPY of fc_timer.sh (the reviewer's own mutations M1..M6 adopted
#           verbatim in intent, plus the fixer's own MX1..MX3 for the new exit-flush code, the
#           round-5 FA*/FU1/FD1/FE*/FB* rows for the opt-in signal flush and fc_timer_run, and the
#           V6 F1G/FU2/R11/R12 rows for the final bounded review's findings, and the round-4
#           reviewer survivors R13/R18 adopted verbatim), runs
#           the UNMODIFIED selftest against that copy (FC_TIMER_SELFTEST_LIB), and requires the
#           selftest to exit non-zero AND to report a FAIL line naming the expected assertion --
#           a mutant killed for an unrelated reason does not count as caught.
# Usage   : bash fc_timer_selftest_mutations.sh      (exit 0 = every mutant killed for the right
#           reason; 1 = a mutant survived or was killed for the wrong reason; 2 = setup error)
# Inputs  : fc_timer.sh + fc_timer_selftest.sh next to this file. No network, no repo writes:
#           every mutant lives in a mktemp dir that is removed on exit.
# Control : the unmutated library is run first through the SAME path and must PASS (a runner
#           that kills everything proves nothing, §11.4.273).
# Every mutation anchor is LITERAL source text (with its own $ expansions) -- never expanded here.
# shellcheck disable=SC2016  # every SC2016 here (verified: all 29 flagged lines) is a mutate() anchor or replacement: single-quoted LITERAL fc_timer.sh source text whose $ must not expand in this runner
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/fc_timer.sh"
SELFTEST="$HERE/fc_timer_selftest.sh"
ROOT="$(cd "$HERE/../../../.." && pwd)"
[ -f "$LIB" ] && [ -f "$SELFTEST" ] || { echo "FATAL: fc_timer.sh / selftest not found next to $0"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 required for exact-anchor mutation"; exit 2; }

TMP="$(mktemp -d)" || { echo "FATAL: mktemp -d failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
fail=0

run_selftest() {  # <lib> <outfile> -> echoes rc
  FC_TIMER_SELFTEST_LIB="$1" FC_TIMER_REPO_ROOT="$ROOT" bash "$SELFTEST" >"$2" 2>&1
  echo "$?"
}

rc="$(run_selftest "$LIB" "$TMP/control.out")"
if [ "$rc" = 0 ]; then
  echo "ok   control: the unmutated library passes the selftest through the mutation path"
else
  echo "NOT ok control: the unmutated library FAILS through the mutation path (rc=$rc) -- runner is blind"
  grep '^FAIL' "$TMP/control.out" | head -5
  exit 1
fi

# mutate <id> <expected FAIL substring> <anchor> <replacement>
mutate() {
  local id="$1" want="$2" anchor="$3" repl="$4" n mut out rc
  # exact multi-line substring count (grep -cF counts per LINE of a multi-line pattern)
  n="$(ANCHOR="$anchor" python3 -c 'import os,sys; print(open(sys.argv[1]).read().count(os.environ["ANCHOR"]))' "$LIB")"
  if [ "$n" != 1 ]; then
    echo "NOT ok $id: anchor found $n times (want exactly 1): $anchor"; fail=1; return
  fi
  mut="$TMP/fc_timer_$id.sh"; out="$TMP/$id.out"
  ANCHOR="$anchor" REPL="$repl" python3 -c '
import os,sys
s=open(sys.argv[1]).read(); s=s.replace(os.environ["ANCHOR"],os.environ["REPL"],1); open(sys.argv[2],"w").write(s)
' "$LIB" "$mut"
  if cmp -s "$LIB" "$mut"; then echo "NOT ok $id: mutation produced an identical file"; fail=1; return; fi
  rc="$(run_selftest "$mut" "$out")"
  if [ "$rc" != 0 ] && grep '^FAIL' "$out" | grep -qF -- "$want"; then
    echo "ok   $id killed (rc=$rc): $(grep '^FAIL' "$out" | grep -F -- "$want" | head -n1 | cut -c1-150)"
  else
    echo "NOT ok $id SURVIVED or killed for the wrong reason (rc=$rc, wanted a FAIL naming '$want')"
    grep '^FAIL' "$out" | head -3
    fail=1
  fi
}

# Reviewer M1 (R1): leave CHK0 un-popped (stack misalignment).
mutate M1 "auto-tracked section 2" \
  '"_FC_TIMER_STACK_CHK0[$idx]" "_FC_TIMER_STACK_FAIL0[$idx]"' '"_FC_TIMER_STACK_FAIL0[$idx]"'
# Reviewer M2: drop the negative-duration clamp.
mutate M2 "M2: a backward clock step" \
  '[ "$duration_ms" -ge 0 ] || duration_ms=0' ':'
# Reviewer M3 (verbatim): remove the memoisation guard -- run id + fingerprint re-derived per call.
mutate M3 "M3: the fingerprint memoised" \
  '  if [ "$_FC_TIMER_INITED" = 1 ]; then
    return 0
  fi
  if [ -n "${FC_TIMER_RUN_ID:-}" ]; then' '  if [ -n "${FC_TIMER_RUN_ID:-}" ]; then'
# Fixer M3b: the R1-I1 defect itself -- mint the timestamp lazily at resolution time again.
mutate M3b "R1-I1: unpinned run id" \
  '_FC_TIMER_RUN_ID="${_FC_TIMER_SOURCE_TS}_$$"' '_FC_TIMER_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)_$$"'
# Reviewer M4: auto fails delta computed against chk0.
mutate M4 "M4: auto-tracked deltas" \
  'fail1=$((vn - fail0))' 'fail1=$((vn - chk0))'
# Reviewer M5: unknown flag silently ignored.
mutate M5 "unknown flag" \
  '*) echo "fc_timer_end: unknown argument: $1" >&2; return 2 ;;' '*) shift ;;'
# Reviewer M6 / R1-m4: an --extra VALUE treated as the --min-ms flag.
mutate M6 "M6: fc_timer_gate_end --extra" \
  '      --checks|--fails|--warns|--extra) i=$((i + 2)) ;;' '      --checks|--fails|--warns) i=$((i + 2)) ;;'
# Fixer MX1: close_all records an aborted frame as PASS.
mutate MX1 "I2: fc_timer_close_all --rc 3" \
  'fc_timer_end --extra "result=aborted;rc=$rc$note" --fails 1 2>/dev/null || break' 'fc_timer_end --extra "result=aborted;rc=$rc$note" 2>/dev/null || break'
# Fixer MX2: the exit flush replaces (drops) the caller's prior EXIT trap.
mutate MX2 "prior EXIT trap still ran" \
  '(exit \"\$_fc_timer_exit_rc\"); ${old}" EXIT' '(exit \"\$_fc_timer_exit_rc\")" EXIT'
# Fixer MX3: no `set +e` in the trap -> under set -e the prior trap never runs.
mutate MX3 "prior EXIT trap still ran" \
  '_fc_timer_exit_rc=\$?; set +e; _fc_timer_exit_flush' '_fc_timer_exit_rc=\$?; _fc_timer_exit_flush'
# Fixer MX4: the exit flush is never installed (the class regression R1-I2 describes).
mutate MX4 "set -e abort with an open frame" \
  '    _FC_TIMER_EXIT_FLUSH_INSTALLED=1
  fi' '    trap - EXIT
    _FC_TIMER_EXIT_FLUSH_INSTALLED=1
  fi'

# Round-3 reviewer RN2: fc_timer_reset no longer re-mints the source timestamp.
mutate RN2 "RN2: fc_timer_reset re-mints" \
  '  _FC_TIMER_ROWS_WRITTEN=0
  _FC_TIMER_SOURCE_TS="$(date -u +%Y%m%dT%H%M%SZ)"
  return 0' '  _FC_TIMER_ROWS_WRITTEN=0
  return 0'
# Round-3 reviewer RN4: a non-numeric --rc maps to 0 (WARN) instead of 255 (FAIL).
mutate RN4 "RN4: fc_timer_close_all --rc abc" \
  '  _fc_timer_is_uint "$rc" || rc=255' '  _fc_timer_is_uint "$rc" || rc=0'

# Round-4 F1 (signal-death class), paired mutations for the new signal flush:
# FS1: the signal traps are never installed (the F1 defect itself: TERM records WARN rc=0).
mutate FS1 "F1-TERM: a process killed by SIGTERM" \
  '        trap "_fc_timer_signal_flush $sig $num" "$sig"' '        :'
# FS2: the handler closes the frames with the stale status instead of 128+N.
mutate FS2 "F1-HUP: a process killed by SIGHUP" \
  '  fc_timer_close_all --rc "$_FC_TIMER_SIGNAL_RC"
  trap - "$name"' '  fc_timer_close_all --rc 0
  trap - "$name"'
# FS3: no re-raise -- an `exit 128+N` look-alike (breaks WIFSIGNALED / SIGINT cooperative exit).
mutate FS3 "F1-INT-signaled" \
  '  kill -s "$name" "$BASHPID"' '  :'
# FS4: the EXIT flush ignores the signal marker (a prior trap's `exit 0` hides the signal).
mutate FS4 "F1-compose-exit0" \
  '  if [ -n "${_FC_TIMER_SIGNAL_RC:-}" ]; then
    rc="$_FC_TIMER_SIGNAL_RC"' '  if false; then
    rc="$_FC_TIMER_SIGNAL_RC"'
# FS5: an IGNORED signal is re-armed (nohup / `trap ''` semantics broken).
mutate FS5 "F1-compose-ignored" \
  '        continue   # ignored (trap '"''"' SIG): never re-arm it' '        trap "_fc_timer_signal_flush $sig $num" "$sig"; continue'
# FS6: a prior handler is REPLACED instead of composed (a handled TERM becomes a death).
mutate FS6 "F1-compose-return" \
  '      trap "_FC_TIMER_SIGNAL_RC=$((128 + num)); ${body}
_FC_TIMER_SIGNAL_RC=" "$sig"' '      trap "_fc_timer_signal_flush $sig $num" "$sig"'
# FS7: signal traps installed even with FC_TIMING=0 (signal behaviour changed when timing is off).
mutate FS7 "F1-off" \
  '  if [ "$want_signals" = 1 ] && [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ] && _fc_timer_enabled; then' '  if [ "$want_signals" = 1 ] && [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ]; then'
# FS8: QUIT added to the class (bash ignores SIGQUIT -- the flush would make it fatal).
mutate FS8 "F1-QUIT" \
  '_FC_TIMER_FLUSH_SIGNALS="HUP INT TERM' '_FC_TIMER_FLUSH_SIGNALS="QUIT HUP INT TERM'
# FS9: the class shrunk back to TERM only (HUP / INT deaths recorded WARN rc=0 again).
mutate FS9 "F1-class" \
  '_FC_TIMER_FLUSH_SIGNALS="HUP INT TERM USR1 USR2 ALRM PIPE XCPU XFSZ VTALRM PROF"' '_FC_TIMER_FLUSH_SIGNALS="TERM"'

# Round-5 F-A (the signal-DEFERRAL class) -- signals are opt-in, and fc_timer_run keeps a trapped
# signal deliverable while a long child runs:
# FA1: the default install arms the signal traps again (the F-A defect: a single-PID TERM is
#      deferred until the foreground child exits).
mutate FA1 "F-A-default-TERM" \
  '  if [ "$want_signals" = 1 ] && [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ] && _fc_timer_enabled; then' '  if [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ] && _fc_timer_enabled; then'
# FA2: fc_timer_run never backgrounds (an armed caller is unkillable during the child again).
mutate FA2 "F-A-run-TERM" \
  '  if [ "$_FC_TIMER_SIGNALS_ARMED" != 1 ] || ! _fc_timer_enabled || [ "$(type -t -- "$1")" != file ]; then' '  if true; then'
# FA3: a bare background job instead of the subshell -- the child IGNORES SIGINT/SIGQUIT.
mutate FA3 "F-A-run-intquit" \
  '    ( exec "$@" ) <&0 &' '    "$@" <&0 &'
# FA4: stdin not passed -- a background job reads /dev/null.
mutate FA4 "F-A-run-stdin" \
  '    ( exec "$@" ) <&0 &' '    ( exec "$@" ) &'
# FA5: no re-wait after a composed handler returns (fc_timer_run reports 143, not the child).
mutate FA5 "F-A-run-compose" \
  '    if kill -0 "$_fcr_pid" 2>/dev/null && [ "$_fcr_guard" -lt 10000 ]; then' '    if false; then'
# (round-5 FA5b retired in V6: the composed handler no longer bumps a sequence -- fc_timer_run now
#  keys on the child being alive, so that counter and its mutant no longer exist.)
# V6 F1 (fixer): the spin guard shrunk to one wait -- a non-class / late-set trap that returns
#  makes fc_timer_run report 128+N with the child still running again.
mutate F1G "F1-late-trap-WINCH" \
  '[ "$_fcr_guard" -lt 10000 ]; then' '[ "$_fcr_guard" -lt 1 ]; then'
# V6 review round 4, reviewer mutant R13 (adopted verbatim): the spin bound 10000 -> 2. Every
#  F1-late case interrupted the wait only once, so it survived; F1-repeat-WINCH interrupts it five times.
mutate R13 "F1-repeat-WINCH" \
  '[ "$_fcr_guard" -lt 10000 ]; then' '[ "$_fcr_guard" -lt 2 ]; then'
# V6 review round 4, reviewer mutant R18 (adopted verbatim): PIPE dropped from the flush class. The
#  selftest used to iterate the library's own list, so the PIPE assertions vanished and it passed with
#  0 failures; it now pins the 11-signal class and the assertion count.
mutate R18 "F1-class" \
  '_FC_TIMER_FLUSH_SIGNALS="HUP INT TERM USR1 USR2 ALRM PIPE XCPU XFSZ VTALRM PROF"' '_FC_TIMER_FLUSH_SIGNALS="HUP INT TERM USR1 USR2 ALRM XCPU XFSZ VTALRM PROF"'
# FA6: a shell function is run in a background subshell (its state change is lost).
mutate FA6 "F-A-run-function" \
  ' || ! _fc_timer_enabled || [ "$(type -t -- "$1")" != file ]; then' ' || ! _fc_timer_enabled; then'
# V6 review round 3, reviewer mutant AM7 (adopted in intent; the reviewer's exact text was not in
#  the brief): a shell BUILTIN is started in the background instead of run in place -- `fc_timer_run
#  cd` / `read` silently change nothing in the caller.
mutate AM7 "F-A-run-builtin-cd" \
  '[ "$(type -t -- "$1")" != file ]; then' '[ "$(type -t -- "$1")" = function ]; then'
# V6 review round 3, reviewer mutant AM8 (the closed-stdin branch removed, `<&0` always used) is NOT
#  a row: it is an EQUIVALENT mutant on this host's bash 5.2.37 (measured, V6_signal_model.md §7):
#  bash treats `<&0` with fd 0 closed as a no-op self-duplication, so the child starts with fd 0
#  closed exactly as the `<&-` branch starts it, and the command runs. The selftest still pins the
#  behaviour (F-A-run-closed-stdin: with fd 0 closed the command runs and returns 0).
# FA7: an unknown install flag is silently accepted.
mutate FA7 "F-A-badflag" \
  '      *) echo "fc_timer_install_exit_flush: unknown argument: $1 (only --signals is accepted)" >&2; return 2 ;;' '      *) shift ;;'
# FU1: the signals=untracked honesty note dropped (an untracked signal death reads as a clean exit).
mutate FU1 "F-A-default-TERM: the open frame" \
  '    note=";signals=untracked"' '    note=""'
# V6 F6 (fixer): the armed rc=0 note dropped -- an untrapped ABRT death reads as a clean exit again.
mutate FU2 "F6-armed-nonclass" \
  '      note=";signals=untracked-nonclass"' '      note=""'
# V6 F3 (reviewer mutant R12, adopted verbatim in intent): the signal flush drops the EXIT trap
#  before re-raising -- the caller's own EXIT cleanup no longer runs on an armed signal death.
mutate R12 "F3-exit-cleanup" \
  '  kill -s "$name" "$BASHPID"' '  trap - EXIT
  kill -s "$name" "$BASHPID"'
# V6 F4 (reviewer mutant R11, adopted verbatim): re-raise at $$ -- an armed SUBSHELL kills its parent.
mutate R11 "F4-subshell" \
  '  kill -s "$name" "$BASHPID"' '  kill -s "$name" "$$"'
# Round-5 F-D: the library no longer clears an inherited marker.
mutate FD1 "F-D: an inherited" \
  'unset _FC_TIMER_SIGNAL_RC
' ''
# Round-5 F-E: the frame popped before the row is durable (date failure / append failure).
mutate FE1 "F-E: a failed end-time read" \
  '  end_ns="$(_fc_timer_now_ns)" || return $?' '  end_ns="$(_fc_timer_now_ns)" || { _fc_timer_pop "$idx"; return 2; }'
mutate FE2 "F-E: a failed append" \
  "(frame '\$id' kept on the stack)\" >&2; return 2; }" "\" >&2; _fc_timer_pop \"\$idx\"; return 2; }"
# Round-5 F-B (reviewer mutant, adopted verbatim): the prior-trap unescape replaced by `:` --
# a body containing a single quote then runs with the literal '\'' escape in it.
mutate FB1 "F-B: a prior TERM trap body" \
  "      body=\"\${body//\\'\\\\\\'\\'/\\'}\"" '      :'
mutate FB2 "F-B: a prior EXIT trap body" \
  "    old=\"\${old//\\'\\\\\\'\\'/\\'}\"" '    :'

echo
if [ "$fail" = 0 ]; then echo "=== fc_timer MUTATIONS: ALL KILLED ==="; else echo "=== fc_timer MUTATIONS: SURVIVORS ABOVE ==="; fi
exit "$fail"
