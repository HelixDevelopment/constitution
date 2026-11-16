#!/bin/bash
# runmut10.sh <tree> <K>: run round-10 mutant K (mut10/K, built by mkmut10.py) suite by suite (r10, r9, r8, r7, r6, pl)
# against the FROZEN round-10 tree <tree>, stopping at the first suite that kills it. Verdict appended to mutruns10/verdicts.tsv.
set -u
R=/mnt/DATA1TB/claude-work/scratch/jev_r10.uPH6
T="${1:?tree}"; K="${2:?mutant}"
P="$R/mut10/$K/scripts/jev/jev-place.sh"; [ -f "$P" ] || { echo "no mutant $K" >&2; exit 2; }
mkdir -p "$R/mutruns10/claims"; mkdir "$R/mutruns10/claims/$K" 2>/dev/null || exit 0
for t in r10 r9 r8 r7 r6 pl; do
  bash "$R/tools/runsuite.sh" "$T" "$t" "$R/mutruns10/${K}_$t" "$P"
  line="$(awk -F'\t' -v k="${K}_$t" '$1==k' "$R/runs/results.tsv" | tail -1)"
  case "$line" in *"rc=0"*"fails=0"*) v=survived ;; *) v=killed ;; esac
  first="$(grep -m1 '^FAIL\|^not ok' "$R/mutruns10/${K}_$t.txt" | cut -c1-200)"
  printf '%s\t%s\t%s\t%s\n' "$K" "$t" "$v" "$first" >> "$R/mutruns10/verdicts.tsv"
  [ "$v" = killed ] && break
done
