#!/bin/bash
# redold.sh: RED side for round 10: each round-10 killer mutant through GATE_UNDER_TEST on the round-9 suite (vehicle head 1dba697e, clean clone)
# (the GREEN side is the MUT_ONLY run of the round-10 suite, logs/mutonly1.log: 6 killed). Starts after rvrun finished (<=2 heavy jobs).
R="$(cd "$(dirname "$0")/.." && pwd)"; T=scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh
until grep -q DONE $R/rvrun/runs/summary.txt 2>/dev/null; do sleep 60; done
echo "start $(date -Is) old=$(git -C $R/red/old rev-parse HEAD)" > $R/red/out/summary.txt
for m in $R/red/mut/*.sh; do n=$(basename $m .sh)
  ( cd $R/red/old && TMPDIR=$R/../tmpC GATE_UNDER_TEST=$m nice -n 10 bash $T ) > $R/red/out/old.$n.log 2>&1; echo "old $n rc=$?" >> $R/red/out/summary.txt
done; echo "end $(date -Is)" >> $R/red/out/summary.txt; echo DONE >> $R/red/out/summary.txt
