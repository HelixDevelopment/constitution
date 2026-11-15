#!/usr/bin/env bash
# write_driver_r5.sh <W> : writes <E>/final/driver.txt for the final (s4) runs from the recorded files
set -euo pipefail
W=${1:?usage: write_driver_r5.sh <W>}
E=$W/work/docs/qa/land_vehicle_r5_2026_11_13
S=$W/snap/s4
canon() { grep -E '^(PASS|FAIL|RESULT)' "$1" | sed -E 's/[0-9a-f]{40,64}/<sha>/g; s#/[^ ]*/lvtest\.[A-Za-z0-9]+#<T>#g'; }
res() { grep '^RESULT' "$1" | tail -1; }
{
  echo "driver: one run at a time per slot, at most 2 slots; each run: systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 bash <snap>/tests/release/test_land_vehicle.sh [<lander>]"
  echo "snapshot s4 (frozen copy, the suite reads its file incrementally; equal to the committed files):"
  ( cd "$W" && sha256sum snap/s4/scripts/release/land_vehicle.sh snap/s4/tests/release/test_land_vehicle.sh | sed 's#  snap/#  <W>/snap/#' )
  for f in scripts/release/land_vehicle.sh tests/release/test_land_vehicle.sh; do
    if cmp -s "$S/$f" "$W/work/$f"; then echo "  $f: snapshot == work tree"; else echo "  $f: snapshot DIFFERS from the work tree"; fi
  done
  for n in 1 2 3; do
    log=$W/out/s4green$n.log
    echo "green$n start $(cat "$W/out/s4green$n.start") log-last-written $(date -d "@$(stat -c %Y "$log")" '+%Y-%m-%d %H:%M:%S %Z') $(res "$log")"
  done
  echo "red start $(cat "$W/out/s4red.start") log-last-written $(date -d "@$(stat -c %Y "$W/out/s4red.log")" '+%Y-%m-%d %H:%M:%S %Z') rc=$(cat "$W/out/s4red.rc") $(res "$W/out/s4red.log")"
  echo "canonical sha256 (PASS/FAIL/RESULT lines, 40-64 hex -> <sha>, lvtest paths -> <T>):"
  for n in 1 2 3; do echo "green_run$n $(canon "$W/out/s4green$n.log" | sha256sum | cut -d' ' -f1)"; done
  echo "exit status and end time of each green run, as printed by the shell that ran it (rc=\$? after the run, then date):"
  echo "green1 rc=0 end Sat Nov 14 05:40:06 AM CET 2026"
  echo "green2 rc=0 end Sat Nov 14 06:00:44 AM CET 2026"
  echo "green3 rc=0 end Sat Nov 14 06:20:36 AM CET 2026"
  echo "survivors, round-5 section of the s4 test (LANDER_TEST_R5_ONLY=1), see mut/survivors_s4_r5section.tsv:"
  sed 's/^/  /' "$W/mutout/s4surv/results.tsv"
  echo "red lander: <W>/red/land_vehicle.sh = c0a3a8bc:scripts/release/land_vehicle.sh sha256 $(sha256sum "$W/red/land_vehicle.sh" | cut -d' ' -f1)"
  echo "red: FAIL lines $(grep -c '^FAIL' "$W/out/s4red.log"), of them R5-* $(grep -c '^FAIL R5-' "$W/out/s4red.log")"
  echo "host: 16 cores; load average 85-90 during the s3 runs (uptime samples 01:29, 01:42); 35-37 at 06:12 and 06:18 (during s4 green3 and the survivor runs); not sampled during s4 green1, green2 and the red run; timing is not asserted"
  echo "TasksMax=2000 per scope; pids.events of the scopes were NOT captured this round (UNCONFIRMED whether the limit was ever reached; no run failed with a fork error)"
} > "$E/final/driver.txt"
cat "$E/final/driver.txt"
