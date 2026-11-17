#!/bin/bash
# redgreen.sh <old|new> <mutant-file>: one GATE_UNDER_TEST run; old = the round-8 test (HEAD eca2f4f1) with GNU date first on PATH
B=<scratch>; w="${1:?}"; m="${2:?}"; n="$(basename "$m" .sh)"; log="$B/r9/red/$w.$n.log"
if [ "$w" = old ]; then d=$B/r9/old; P="$B/r9/gnubin:$PATH"; else d=$B/constitution; P="$PATH"; fi
( cd "$d" && PATH="$P" TMPDIR=$B/tmp GATE_UNDER_TEST="$m" nice -n 10 bash scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh ) >"$log" 2>&1; echo "$w $n rc=$?"
