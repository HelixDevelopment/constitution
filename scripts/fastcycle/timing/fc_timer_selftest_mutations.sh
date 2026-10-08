#!/bin/bash
# fc_timer_selftest_mutations.sh - paired §1.1 mutation runner for fc_timer.sh / its selftest
#   (spec 004-fast-dev-cycles; T048 restart round-1, findings R1-I1/R1-I2/R1-I5/R1-m4).
#
# Purpose : prove fc_timer_selftest.sh is load-bearing. Each mutation below re-introduces one
#           real defect into a COPY of fc_timer.sh (the reviewer's own mutations M1..M6 adopted
#           verbatim in intent, plus the fixer's own MX1..MX3 for the new exit-flush code), runs
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
# shellcheck disable=SC2016
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
  'fc_timer_end --extra "result=aborted;rc=$rc" --fails 1 2>/dev/null || break' 'fc_timer_end --extra "result=aborted;rc=$rc" 2>/dev/null || break'
# Fixer MX2: the exit flush replaces (drops) the caller's prior EXIT trap.
mutate MX2 "prior EXIT trap still ran" \
  '(exit \"\$_fc_timer_exit_rc\"); ${old}" EXIT' '(exit \"\$_fc_timer_exit_rc\")" EXIT'
# Fixer MX3: no `set +e` in the trap -> under set -e the prior trap never runs.
mutate MX3 "prior EXIT trap still ran" \
  '_fc_timer_exit_rc=\$?; set +e; fc_timer_close_all' '_fc_timer_exit_rc=\$?; fc_timer_close_all'
# Fixer MX4: the exit flush is never installed (the class regression R1-I2 describes).
mutate MX4 "set -e abort with an open frame" \
  '  _FC_TIMER_EXIT_FLUSH_INSTALLED=1
  return 0
}' '  trap - EXIT
  _FC_TIMER_EXIT_FLUSH_INSTALLED=1
  return 0
}'

# Round-3 reviewer RN2: fc_timer_reset no longer re-mints the source timestamp.
mutate RN2 "RN2: fc_timer_reset re-mints" \
  '  _FC_TIMER_ROWS_WRITTEN=0
  _FC_TIMER_SOURCE_TS="$(date -u +%Y%m%dT%H%M%SZ)"
  return 0' '  _FC_TIMER_ROWS_WRITTEN=0
  return 0'
# Round-3 reviewer RN4: a non-numeric --rc maps to 0 (WARN) instead of 255 (FAIL).
mutate RN4 "RN4: fc_timer_close_all --rc abc" \
  '    _fc_timer_is_uint "$rc" || rc=255' '    _fc_timer_is_uint "$rc" || rc=0'

echo
if [ "$fail" = 0 ]; then echo "=== fc_timer MUTATIONS: ALL KILLED ==="; else echo "=== fc_timer MUTATIONS: SURVIVORS ABOVE ==="; fi
exit "$fail"
