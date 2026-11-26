#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME shared with lib.sh
# tests/pi-constitution/run_all.sh — runs every pi-constitution test suite:
# unit, integration, e2e, determinism, security, cli, provenance, stress/perf, mutations, chaos.
#
# Usage: bash tests/pi-constitution/run_all.sh [--quick]
#   --quick  skips stress/perf, mutations (slower suites)
# Exit: 0 every suite passed · 1 at least one failed.
#
# Every suite is fully deterministic: no dependence on pi's LLM to invoke tools (except best-effort
# e2e/cli), no LLM calls anywhere, no writes to $HOME, all sandboxes under mktemp -d.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$REPO/scripts/lib/safe_rm.sh"
export CONSTITUTION_JEV_HOOK=off
export GIT_CONFIG_NOSYSTEM=1

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
failed=()
run_suite() {
  local name="${1:?missing suite name}"
  local script="$here/test_$name.sh"
  echo "=== $name"
  if bash "$script"; then echo "=== $name OK"; else failed+=("$name"); echo "=== $name FAILED"; fi
}

run_suite unit
run_suite integration
run_suite e2e
run_suite determinism
run_suite security
run_suite attacks
run_suite cli
run_suite provenance
[ "$quick" = 1 ] || run_suite stress_perf
[ "$quick" = 1 ] || run_suite mutations
[ "$quick" = 1 ] || run_suite chaos

if [ "${#failed[@]}" -eq 0 ]; then echo "RUN_ALL: PASS"; exit 0; fi
echo "RUN_ALL: FAIL (${failed[*]})"; exit 1
