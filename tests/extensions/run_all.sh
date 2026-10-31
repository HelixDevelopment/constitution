#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# run_all.sh — runs every extension-engine suite: unit (python), cli, security, e2e, determinism,
# attacks (adversarial security review), round9 (S1 journal ownership, T1 non-canonical TMPDIR), reviewfix (E1 round-1 review regressions), provenance (wiring binding, clone portability, revocation,
# agent-side constructs, review-round mutants), integration (real git submodule add, both layouts), chaos, stress/perf, then the paired §1.1
# mutation tests. Each suite sandboxes itself under mktemp -d; nothing touches $HOME or this repo.
# Usage: bash tests/extensions/run_all.sh [--quick]   (--quick skips integration, chaos, stress, mutations)
# Exit: 0 every suite passed · 1 at least one failed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
failed=()
echo "=== test_unit.py"; if python3 -I "$here/test_unit.py"; then :; else failed+=(test_unit); fi
suites=(test_cli test_security test_e2e test_determinism test_attacks test_provenance test_reviewfix test_round9 test_round10)
[ "$quick" = 1 ] || suites+=(test_integration test_chaos test_stress_perf test_mutations)
for s in "${suites[@]}"; do
  echo "=== $s"; t0=$SECONDS
  if bash "$here/$s.sh"; then echo "=== $s OK ($((SECONDS-t0))s)"; else failed+=("$s"); echo "=== $s FAILED"; fi
done
if [ "${#failed[@]}" -eq 0 ]; then echo "RUN_ALL: PASS"; exit 0; fi
echo "RUN_ALL: FAIL (${failed[*]})"; exit 1
