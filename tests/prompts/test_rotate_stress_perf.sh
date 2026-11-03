#!/usr/bin/env bash
# test_rotate_stress_perf.sh — STRESS (200 consecutive rotations: numbering
# 03..202, 2 digits up to 99 then 3 digits, gap-free, unique, no file lost) and
# PERFORMANCE (the 200 rotations complete within ROTATE_PERF_BUDGET_SEC, default
# 120 s; measured wall-clock is printed).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -r "$ROTATE" ] || { no "rotate script present"; summary stress_perf; exit 1; }
BUDGET="${ROTATE_PERF_BUDGET_SEC:-120}"
S="$(mk_sandbox)"; D="$(mk_setup_dir "$S")"
fails=0
t0="$(date +%s%N)"
for i in $(seq 1 200); do
  printf '# p%d\n\n## PROMPT\n\n```\nprompt number %d\n```\n' "$i" "$i" >"$S/src.md"
  bash "$ROTATE" "r$i" --source "$S/src.md" --dir "$D" >/dev/null 2>&1 || fails=$((fails + 1))
done
t1="$(date +%s%N)"
ms=$(( (t1 - t0) / 1000000 ))
[ "$fails" -eq 0 ] && ok "200 rotations all rc=0" || no "$fails of 200 rotations failed"
n="$(cd "$D" && ls | grep -cE '^[0-9]+_.*\.md$')"
[ "$n" -eq 202 ] && ok "202 numbered files (01..202)" || no "numbered files: $n"
[ -f "$D/latest.md" ] && grep -q 'prompt number 200' "$D/latest.md" && ok "latest.md holds rotation 200" || no "latest.md wrong"
[ -f "$D/99_r97.md" ] && [ -f "$D/100_r98.md" ] && [ -f "$D/202_r200.md" ] && ok "width switches 99 -> 100 (99_r97, 100_r98, 202_r200)" || no "width switch wrong: $(ls "$D" | sort -n | sed -n '97,102p' | tr '\n' ' ')"
nums="$(cd "$D" && ls | sed -nE 's/^([0-9]+)_.*\.md$/\1/p' | sed 's/^0*//' | sort -n | tr '\n' ' ')"
[ "$nums" = "$(seq 1 202 | tr '\n' ' ')" ] && ok "numbering gap-free and unique 1..202" || no "numbering broken"
grep -q 'prompt number 199' "$D/202_r200.md" && ok "202_r200.md holds rotation 199 content (no loss)" || no "content chain broken"
[ ! -e "$D/.rotate.lock" ] && ok "no lock left after stress" || no "lock left after stress"
[ "$((ms / 1000))" -lt "$BUDGET" ] && ok "performance: 200 rotations in ${ms} ms (< ${BUDGET}s)" || no "performance: ${ms} ms >= ${BUDGET}s"
summary stress_perf
