#!/usr/bin/env bash
# run_all.sh — run every setup-prompt test suite and the gate's paired mutation
# test; print one RESULT line per suite and a total. Exit 0 only if all pass.
# Usage: bash tests/prompts/run_all.sh [--quick]   (--quick skips the stress/perf suite and the
#        round 3, 4 and 5 mutation proofs and the lock-race mutants, which re-run a suite once per mutant)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
suites=(test_rotate_unit test_rotate_integration test_rotate_e2e test_rotate_security
        test_rotate_chaos test_rotate_idem_determinism test_rotate_hardening
        test_setup_prompt_content test_setup_prompt_behaviour
        test_setup_prompt_extract_equivalence test_setup_prompt_round3 test_setup_prompt_round4
        test_setup_prompt_round5 test_setup_prompt_round5_stops test_rotate_lock_race test_setup_prompt_round7)
[ "$quick" -eq 0 ] && suites+=(test_rotate_stress_perf test_setup_prompt_round3_mutants test_setup_prompt_round4_mutants
                             test_setup_prompt_round5_stops_mutants test_setup_prompt_round5_mutants test_rotate_lock_race_mutants test_setup_prompt_round7_mutants)
failed=0
for s in "${suites[@]}"; do
  out="$(bash "$here/$s.sh" 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -E '^(FAIL|RESULT)'
  [ "$rc" -eq 0 ] || failed=$((failed + 1))
done
out="$(bash "$repo/scripts/gates/cm_setup_prompt_latest_present_mutation_test.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | grep -E '^(BAD|META RESULT|VERDICT|real-repo)'
[ "$rc" -eq 0 ] || failed=$((failed + 1))
echo "TOTAL: failed_suites=$failed"
[ "$failed" -eq 0 ]
