#!/usr/bin/env bash
# driver_r4.sh <snapshot-root> <round3-lander> <outdir>: runs inside its own systemd --user
# scope (own pids budget), sequential, nice -n 10:
#   3 GREEN runs of the round-4 suite on the round-4 lander, canonicalised and hashed;
#   1 RED run of the same suite on the round-3 lander;
#   every producer mutant (mutants_r4.py: 85 ported round-3 + Z group) and every reviewer
#   mutant (reviewer_mutants_r4.py), LANDER_TEST_FAILFAST=1 (a survivor ran the whole suite).
# Records the scope's pids.events "max" counter around every run (no growth = no fork starvation).
set -uo pipefail
R=${1:?snapshot root}; ORIG=${2:?round-3 lander}; O=${3:?outdir}
TEST=$R/tests/release/test_land_vehicle.sh; L=$R/scripts/release/land_vehicle.sh
TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${TMPDIR:?set TMPDIR to a scratch directory}"
EV=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/pids.events
ev() { awk '$1=="max"{print $2}' "$EV" 2>/dev/null || echo NA; }
canon() { grep -E '^(PASS|FAIL|RESULT)' "$1" | sed -E 's/[0-9a-f]{40,64}/<sha>/g; s#/[^ ]*/lvtest\.[A-Za-z0-9]+#<T>#g'; }
mkdir -p "$O"
D=$O/driver.txt
echo "scope=$(cut -d: -f3 /proc/self/cgroup) pids.max=$(cat "${EV%events}max" 2>/dev/null)" > "$D"
for i in 1 2 3; do
  b=$(ev); s0=$(date +%s); bash "$TEST" > "$O/green_run$i.log" 2>&1; rc=$?; a=$(ev)
  canon "$O/green_run$i.log" > "$O/green_run$i.canon"
  echo "green_run$i rc=$rc secs=$(( $(date +%s) - s0 )) pids_max_events $b->$a canon_sha256=$(sha256sum < "$O/green_run$i.canon" | cut -c1-64) $(tail -1 "$O/green_run$i.log")" >> "$D"
done
b=$(ev); bash "$TEST" "$ORIG" > "$O/red_round3_lander.log" 2>&1; rc=$?; a=$(ev)
echo "red_on_round3_lander rc=$rc pids_max_events $b->$a $(tail -1 "$O/red_round3_lander.log") fails=$(grep -c '^FAIL' "$O/red_round3_lander.log")" >> "$D"
for set in producer reviewer; do
  M=$O/mut_$set; mkdir -p "$M"
  if [ "$set" = producer ]; then gen=$TOOLS/mutants_r4.py; else gen=$TOOLS/reviewer_mutants_r4.py; fi
  python3 -I "$gen" "$L" "$M/m" > "$M/generate.txt" 2>&1
  : > "$M/results.txt"
  for d in "$M"/m/*/; do
    n=$(basename "$d"); b=$(ev)
    LANDER_TEST_FAILFAST=1 bash "$TEST" "$d/land_vehicle.sh" > "$M/$n.log" 2>&1; rc=$?; a=$(ev)
    first=$(grep -m1 '^FAIL' "$M/$n.log" | cut -c1-170)
    if [ $rc -ne 0 ]; then v=KILLED; else v=SURVIVED; fi
    echo "$n $v rc=$rc pids_max_events $b->$a $(tail -1 "$M/$n.log" | cut -c1-50) :: $first" >> "$M/results.txt"
  done
  echo DONE >> "$M/results.txt"
done
echo DRIVER_DONE >> "$D"
