#!/bin/bash
# drive.sh <checkout> <logdir> [first-screen [longest-s]]: three full screens, one at a time, all on ONE local calendar day (operator decision).
#  - SUITE_NOW is fixed once for the whole drive (noon UTC of the local start day) and exported to every screen, so all
#    three screens see the same injected clock (the suite pins every `date` to it).
#  - screen 1 starts only at 01:05 local or later; screen n (n > 1) starts only when the local day is still the start day
#    and the time left until 23:55 is at least 1.5 times the longest screen so far; else the drive stops (honest refusal,
#    written to drive.log), so no screen can cross midnight.
#  - before each start it waits (bounded sleeps of 60 s) until the session scope's pids.current is below 3000.
set -u
co="${1:?}"; ld="${2:?}"; first="${3:-1}"; me="$(dirname "$0")"; mkdir -p "$ld"
pidsf="/sys/fs/cgroup$(sed -n 's/^0:://p' /proc/self/cgroup)/pids.current"
until [ "$((10#$(date +%H%M)))" -ge 105 ]; do sleep 60; done
day="$(date +%F)"; export SUITE_NOW="${day}T12:00:00Z"; longest="${4:-0}" # a resumed drive passes the longest earlier screen
echo "$(date -Is) drive start (first screen $first, longest so far ${longest}s) day $day SUITE_NOW $SUITE_NOW" >>"$ld/drive.log"
for n in $(seq "$first" 3); do
  while [ -r "$pidsf" ] && [ "$(cat "$pidsf")" -ge 3000 ]; do echo "$(date -Is) screen $n waits: pids.current $(cat "$pidsf")" >>"$ld/drive.log"; sleep 60; done
  now="$(date +%s)"; left=$(( $(date -d "$day 23:55" +%s) - now ))
  refuse=0; [ "$(date +%F)" = "$day" ] || refuse=1; [ "$n" -gt 1 ] && [ $((left * 2)) -lt $((longest * 3)) ] && refuse=1
  if [ "$refuse" = 1 ]; then
    echo "$(date -Is) screen $n REFUSED: ${left}s left today, longest screen ${longest}s (needs 1.5x)" >>"$ld/drive.log"; exit 3; fi
  echo "$(date -Is) screen $n start (pids.current $(cat "$pidsf" 2>/dev/null || echo unreadable))" >>"$ld/drive.log"
  t0="$(date +%s)"; bash "$me/run.sh" "$co" "$ld" "$n"; rc=$?; dt=$(( $(date +%s) - t0 )); [ "$dt" -gt "$longest" ] && longest=$dt
  echo "$(date -Is) screen $n rc=$rc duration ${dt}s" >>"$ld/drive.log"
  t="$ld/tmp$n"; [ -n "${t:-}" ] && [ -d "$t" ] && rm -rf -- "${t:?}"
done
echo "$(date -Is) all done" >>"$ld/drive.log"
