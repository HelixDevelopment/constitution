#!/usr/bin/env bash
# run_all.sh — runs every sync-all-upstreams suite, the CM-SYNC-UPSTREAMS-FF-ONLY gate and its meta-test, and
# (unless --quick) the stress/chaos, performance and engine paired-mutation suites. Each suite sandboxes
# itself under mktemp -d (scripts/sync/fixture_lib.sh: real git against real bare repositories, no network);
# nothing touches $HOME, the user's git config or this repository. Suites run one after another.
# Usage: bash tests/sync/run_all.sh [--quick]   (--quick skips chaos, perf, the mutation suites)
# Exit: 0 every suite and gate passed · 1 at least one failed.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; gates="$here/../../scripts/gates"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
command -v python3 >/dev/null 2>&1 || { echo "RUN_ALL: BLIND — python3 missing"; exit 1; }
failed=()
echo "=== test_unit"
if python3 -I "$here/test_unit.py"; then echo "=== test_unit OK"; else failed+=(test_unit); fi
suites=(test_integration test_e2e test_full_automation test_security test_determinism test_ui)
[ "$quick" = 1 ] || suites+=(test_chaos test_perf)
for s in "${suites[@]}"; do
  echo "=== $s"; t0=$SECONDS
  if bash "$here/$s.sh"; then echo "=== $s OK ($((SECONDS-t0))s)"; else failed+=("$s"); echo "=== $s FAILED"; fi
done
echo "=== cm_sync_upstreams_ff_only"
bash "$gates/cm_sync_upstreams_ff_only.sh" || failed+=(cm_sync_upstreams_ff_only)
if [ "$quick" = 0 ]; then
  echo "=== cm_sync_upstreams_ff_only_mutation_test"
  bash "$gates/cm_sync_upstreams_ff_only_mutation_test.sh" || failed+=(cm_sync_upstreams_ff_only_mutation_test)
  echo "=== test_mutations"
  python3 -I "$here/test_mutations.py" || failed+=(test_mutations)
fi
if [ "${#failed[@]}" -eq 0 ]; then echo "RUN_ALL: PASS"; exit 0; fi
echo "RUN_ALL: FAIL (${failed[*]})"; exit 1
