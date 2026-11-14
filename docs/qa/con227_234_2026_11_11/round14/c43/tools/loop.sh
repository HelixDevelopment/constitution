#!/bin/bash
# loop.sh OUTDIR N WORKER : runs c43_only.sh N times, keeps every p43 json and output
O="${1:?}"; N="${2:?}"; k="${3:?}"; R="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$O"
for i in $(seq 1 "$N"); do
  l=$(cut -d' ' -f1 /proc/loadavg); case "$l" in 6[0-9].*|[7-9][0-9].*) echo "load $l > 60, stop" >"$O/stopped_$k"; exit 3;; esac
  TMPDIR="$R/../tmp" KEEP="$O/p43_${k}_$i.json" bash "$R/c43_only.sh" >"$O/out_${k}_$i.txt" 2>&1
  echo "$k $i rc=$? load=$l $(grep -c '^FAIL' "$O/out_${k}_$i.txt") $(grep -c OFFENDER "$O/out_${k}_$i.txt")" >>"$O/summary.txt"
done
