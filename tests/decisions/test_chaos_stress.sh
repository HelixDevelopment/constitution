#!/usr/bin/env bash
# test_chaos_stress.sh — chaos (SIGKILL mid-write, then re-run recovers; backup restorable; lock contention),
# stress (repeated set/unset runs) and performance (time budget) for the REAL wizard.
# The write delay is a test seam honoured only with CONSTITUTION_DECISIONS_TEST=1 (it widens the window, it fakes nothing).
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap cleanup_sandbox EXIT
C="$DEC_CLI"
echo "== chaos: SIGKILL during atomic write =="
P="$(new_project chaos)"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.91 >/dev/null 2>&1
old_yml="$(cat "$P/.constitution/decisions.yml")"; old_claude="$(cat "$P/CLAUDE.md")"
CONSTITUTION_DECISIONS_TEST=1 CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.98 >"$SB/k.out" 2>&1 &
kpid=$!
for _ in $(seq 1 50); do ls "$P/.constitution"/.decisions.yml.tmp.* >/dev/null 2>&1 && break; sleep 0.1; done
check "temp file seen before kill (window reached)" bash -c "ls '$P/.constitution'/.decisions.yml.tmp.* >/dev/null 2>&1"
kill -KILL "$kpid" 2>/dev/null; wait "$kpid" 2>/dev/null
check "file after kill is old or new, never partial" bash -c "grep -q 'calibration.floor: 0.91' '$P/.constitution/decisions.yml' || grep -q 'calibration.floor: 0.98' '$P/.constitution/decisions.yml'"
check "intent journal left by the kill" test -f "$P/.constitution/decisions.intent"
expect_rc "check after kill reports the unfinished write (rc 4), not clean (round 6)" 4 "$C" --project-root "$P" --check
check "…and says so, not 'edited outside the wizard' (no false tamper alarm)" bash -c "grep -qi 'did not finish' '$SB/last.err' && ! grep -qi 'edited outside' '$SB/last.err'"
expect_rc "re-run recovers" 0 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.98
check "recovered value" grep -q 'calibration.floor: 0.98' "$P/.constitution/decisions.yml"
check "stale temp removed" bash -c "! ls '$P/.constitution'/.decisions.yml.tmp.* >/dev/null 2>&1"
check "intent cleared" test ! -e "$P/.constitution/decisions.intent"
expect_rc "check clean after recovery" 0 "$C" --project-root "$P" --check
bk="$(ls -d "$P"/.constitution-install-backup/*-decisions* | sort | tail -1)"
check "backup restorable (holds previous yml)" bash -c "grep -q 'calibration.floor: 0.91' '$bk/.constitution/decisions.yml'"
check "backup restorable (holds previous CLAUDE.md)" test "$(cat "$bk/CLAUDE.md")" = "$old_claude"
: "$old_yml"
echo "== chaos: concurrent run gets the lock refusal =="
CONSTITUTION_DECISIONS_TEST=1 CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.93 >/dev/null 2>&1 &
lp=$!
for _ in $(seq 1 50); do ls "$P/.constitution"/.decisions.yml.tmp.* >/dev/null 2>&1 && break; sleep 0.1; done
expect_rc "second concurrent writer refused" 5 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.94
wait "$lp"; check "first writer finished" grep -q 'calibration.floor: 0.93' "$P/.constitution/decisions.yml"
echo "== stress: 100 alternating runs =="
S="$(new_project stress)"; t0=$(date +%s%N); bad_runs=0
for i in $(seq 1 50); do
  "$C" --project-root "$S" --non-interactive --set budget.max_usd_per_day="$i" >/dev/null 2>&1 || bad_runs=$((bad_runs+1))
  "$C" --project-root "$S" --non-interactive --unset budget.max_usd_per_day >/dev/null 2>&1 || bad_runs=$((bad_runs+1))
done
t1=$(date +%s%N)
check "100 runs all rc0" test "$bad_runs" = 0
check "single BEGIN marker after 100 runs" test "$(grep -c 'BEGIN constitution-decisions' "$S/CLAUDE.md")" = 1
check "user text intact after 100 runs" grep -q '^User text above.$' "$S/CLAUDE.md"
expect_rc "check clean after stress" 0 "$C" --project-root "$S" --check
avg_ms=$(( (t1-t0)/100000000 ))
printf '  info: 100 runs in %d ms total wall, avg %d ms/run (host load %s)\n' "$(( (t1-t0)/1000000 ))" "$avg_ms" "$(cut -d' ' -f1 /proc/loadavg)"
echo "== performance: one write and one show under a 5 s budget each =="
t0=$(date +%s%N); "$C" --project-root "$S" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1; t1=$(date +%s%N)
check "write under 5000 ms ($(( (t1-t0)/1000000 )) ms)" test $(( (t1-t0)/1000000 )) -lt 5000
t0=$(date +%s%N); "$C" --project-root "$S" --show --json >/dev/null 2>&1; t1=$(date +%s%N)
check "show under 5000 ms ($(( (t1-t0)/1000000 )) ms)" test $(( (t1-t0)/1000000 )) -lt 5000
finish test_chaos_stress
