#!/usr/bin/env bash
# run_all.sh — runs every installer/updater suite and the four installer gates with their meta-tests.
# Each suite sandboxes itself under mktemp -d (tests/install/lib.sh); nothing touches $HOME or this repo.
# Usage: bash tests/install/run_all.sh [--quick]   (--quick skips chaos, stress/perf and timeout_tty)
# Exit: 0 every suite and gate passed · 1 at least one failed.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; gates="$here/../../scripts/gates"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
suites=(test_unit test_integration test_updater test_e2e test_agent test_security test_determinism test_detection test_self_guard test_git_wrapper test_minor test_lock test_round6 test_round8 test_round9 test_round10 test_round11 test_upstream_main test_sigpipe test_python_isolation test_shell_state_patsub)
[ "$quick" = 1 ] || suites+=(test_chaos test_stress_perf test_timeout_tty)
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
