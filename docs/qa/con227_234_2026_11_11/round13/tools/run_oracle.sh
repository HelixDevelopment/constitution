#!/usr/bin/env bash
# run_oracle.sh D: RED (r12) and GREEN (r13) oracle runs over the four case files
set -u
D="${1:?}"; cd "$D" || exit 2
for m in r12 r13; do
  for c in cases_r1 cases_r2 cases_r2b cases_r13; do
    repo="$D/repo"; [ "$m" = r12 ] && repo="$D/r12repo"
    python3 -I tools/oracle13.py "$m" "$repo" "tools/$c.json" "oracle/$m/$c" "$D/pin_try.tsv" > "oracle/$m.$c.txt" 2>"oracle/$m.$c.err"
    echo "done $m $c rc=$?"
  done
done
echo ALLDONE
