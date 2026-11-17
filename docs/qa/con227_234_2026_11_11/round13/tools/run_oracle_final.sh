#!/usr/bin/env bash
# run_oracle_final.sh D OUT: the oracle on the final round-13 tree ($D/repo, its committed pin) over every case file
# (the round-12 reviewer's 48 cases, the 85 fixtures of round 13), and the round-12 gate ($D/r12repo) over the four
# fixtures added last (cases_r13d, cases_r13e), so RED and GREEN cover the same 133 cases. OUT must not exist.
set -u
D="${1:?D}"; OUT="${2:?OUT}"
[ -e "$OUT" ] && { echo "refusing: $OUT exists" >&2; exit 2; }
mkdir -p "$OUT" || exit 2
cd "$D" || exit 2
for c in cases_r1 cases_r2 cases_r2b cases_r13_all; do
  python3 -I tools/oracle13.py r13 "$D/repo" "tools/$c.json" "$OUT/r13/$c" "$D/repo/tests/release/netgate_pin.tsv" >"$OUT/r13.$c.txt" 2>"$OUT/r13.$c.err"
  echo "done r13 $c rc=$?"
done
for c in cases_r13d cases_r13e; do
  python3 -I tools/oracle13.py r12 "$D/r12repo" "tools/$c.json" "$OUT/r12/$c" "$D/repo/tests/release/netgate_pin.tsv" >"$OUT/r12.$c.txt" 2>"$OUT/r12.$c.err"
  echo "done r12 $c rc=$?"
done
echo ALLDONE
