#!/usr/bin/env bash
# targeted14.sh <log> <locale>: one targeted Part-1 + Part-2 run of the CON-046 suite in a capped scope (round 14).
# The regex is the round-13 one (r13_runs/tools/targeted13.sh) extended with every mutant family round 14 touches:
# all reviewer mutants (RV*), the round-14 own mutants, the new generated compare member, and the crash family.
set -u
log="${1:?log}"; loc="${2:?locale}"
cd /mnt/DATA1TB/claude-work/scratch/fx14.xn59/repo || exit 2
re='^(conf-|skel-|empty-skeleton|no-casefold-no-nfc$|casefold-without-nfc$|RVR11-0[12]|RVX-|V13-casefold|normalise-to-empty|locale-|gen-normcls-|gen-norm-|V29-python|auth-arg-is-committer|eq-idpy|selftest-|V12-authoriser-only-Cc$|authoriser-control-chars-allowed$|gen-pybool-|gen-strip-|eq-ident-strip-truthiness$|unborn-|shallow-|fetchfix-|hook-|RV[0-9]+-|RVR13-|ident-|self-|auth-|braille-|blank-|q-map|e-|f-default|brokenhead-|outer-k|crash|gen-cmp-d48974649d$)'
systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 env LC_ALL="$loc" TMPDIR=/mnt/DATA1TB/claude-work/tmp MUT_JOBS=6 MUT_ONLY="$re" \
  bash scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh >"$log" 2>&1
echo "rc=$?" >>"$log"
