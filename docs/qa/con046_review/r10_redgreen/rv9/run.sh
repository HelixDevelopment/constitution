#!/usr/bin/env bash
# reviewer mutants RV9-01..RV9-11 through the round-10 suite (GATE_UNDER_TEST: Part 1 + Part 3), sequential, nice
C=<scratch>/r10/snapA/c; T=scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh; O=<scratch>/r10/rvrun/runs
for g in REAL <scratch>/r10/../rev_con046_r9/mut/*.sh <scratch>/r10/../rev_con046_r9/mut2/*.sh; do
  if [ $g = REAL ]; then m=REAL; gp=$C/scripts/gates/cm_submodule_pin_not_downgraded.sh; else m=$(basename $g .sh); gp=$g; fi
  ( cd $C && TMPDIR=<scratch>/r10/../tmpB GATE_UNDER_TEST=$gp nice -n 10 bash $T ) > $O/$m.log 2>&1; echo "$m rc=$?" >> $O/summary.txt
done
( cd <scratch>/r10/rvrun/wt && TMPDIR=<scratch>/r10/../tmpB GATE_UNDER_TEST=<scratch>/r10/rvrun/wt/scripts/gates/cm_submodule_pin_not_downgraded.sh nice -n 10 bash $T ) > $O/RV9-09-hook-norepo-exit0.log 2>&1; echo "RV9-09-hook-norepo-exit0 rc=$?" >> $O/summary.txt
echo DONE >> $O/summary.txt
