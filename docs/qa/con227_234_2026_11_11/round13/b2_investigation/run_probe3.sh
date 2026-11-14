#!/bin/bash
# run_probe3.sh E: start p5.sh as line 294 does, sample the looping bash's fd count and fd numbers
E="${1:?}"
env -i PATH="$PATH" HOME=/h timeout 30 bash "$E/p5.sh" >"$E/o3.txt" 2>&1 &
tp=$!
sleep 0.3
bp=$(pgrep -P "$tp" | head -1)
echo "timeout=$tp bash=$bp"
for i in $(seq 1 12); do
  [ -d "/proc/$bp" ] || { echo "gone at sample $i"; break; }
  n=$(ls "/proc/$bp/fd" 2>/dev/null | wc -l); lo=$(ls "/proc/$bp/fd" 2>/dev/null | sort -n | tr '\n' ' ' | cut -c1-160)
  ch=$(ls /proc/"$bp"/task/*/children 2>/dev/null | xargs cat 2>/dev/null | wc -w)
  printf 't=%s fds=%s children=%s list=%s\n' "$i" "$n" "$ch" "$lo"
  sleep 2
done
wait "$tp"; echo "r8=$?"; head -c 600 "$E/o3.txt"
