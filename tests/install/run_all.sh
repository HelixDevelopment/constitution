#!/usr/bin/env bash
# run_all.sh — runs every installer/updater suite and the four installer gates with their meta-tests.
# Each suite sandboxes itself under mktemp -d (tests/install/lib.sh); nothing touches $HOME or this repo.
# Usage: bash tests/install/run_all.sh [--quick]   (--quick skips chaos and stress/perf)
# Exit: 0 every suite and gate passed · 1 at least one failed.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; gates="$here/../../scripts/gates"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
suites=(test_unit test_integration test_updater test_e2e test_agent test_security test_determinism test_detection test_self_guard test_git_wrapper test_minor test_lock test_round6 test_round8 test_round9 test_round10 test_round11)
[ "$quick" = 1 ] || suites+=(test_chaos test_stress_perf)
failed=()
for s in "${suites[@]}"; do
  echo "=== $s"; t0=$SECONDS
  if bash "$here/$s.sh"; then echo "=== $s OK ($((SECONDS-t0))s)"; else failed+=("$s"); echo "=== $s FAILED"; fi
done
for g in cm_installer_truncation_safe cm_installer_no_push_no_force cm_installer_snippets_consistent cm_installer_script_modes; do
  for f in "$g.sh" "${g}_mutation_test.sh"; do
    echo "=== $f"; bash "$gates/$f" || failed+=("$f")
  done
done
if [ "${#failed[@]}" -eq 0 ]; then echo "RUN_ALL: PASS"; exit 0; fi
echo "RUN_ALL: FAIL (${failed[*]})"; exit 1
