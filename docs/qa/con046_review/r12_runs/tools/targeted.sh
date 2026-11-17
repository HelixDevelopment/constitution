#!/bin/bash
# targeted.sh <n>: the round-12 affected set, run n of 3, on the clean worktree wt (head 892aa4ea), MUT_JOBS=3
set -u
d=/mnt/DATA1TB/claude-work/scratch/fx046r12.KQXD; n="${1:?}"
re='^(RVR11-|gen-norm-|eq-|selftest-|gen-andor-5d778c1c49|gen-rxq-1faaa1a2b7|gen-strip-99db10f56c|gen-strip-7144af3e42|gen-pybool-6ef1faee03|gen-rxq-774fef6d84|gen-rxq-53ad123043|gen-rxq-da7dc34398|gen-andor-2468ed98ae|no-casefold-no-nfc$|casefold-without-nfc$|V13-casefold-to-lower$|normalise-to-empty$|self-authoriser-allowed$|self-always$|RV10-05-email-space-strip$|ident-names-ascii-strip$)'
t="$d/tmpT$n"; mkdir -p "$t"
cd "$d/wt" || exit 9
{ echo "start $(date -Is) head $(git rev-parse HEAD) clean-tree-lines $(git status --porcelain --untracked-files=all | wc -l) SUITE_NOW 2026-11-15T12:00:00Z MUT_JOBS 3 MUT_ONLY $re"; } > "$d/ev/targeted$n.log"
TMPDIR="$t" SUITE_NOW=2026-11-15T12:00:00Z MUT_JOBS=3 MUT_ONLY="$re" "$d/runscope.sh" "con046r12-t$n" 2000 "$d/ev/targeted$n.body.log" bash scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh
rc=$?
cat "$d/ev/targeted$n.body.log" >> "$d/ev/targeted$n.log"; rm -f "$d/ev/targeted$n.body.log"
echo "end $(date -Is) head $(git rev-parse HEAD) clean-tree-lines $(git status --porcelain --untracked-files=all | wc -l) rc=$rc" >> "$d/ev/targeted$n.log"
[ -n "$t" ] && [ -d "$t" ] && rm -rf -- "${t:?}"
