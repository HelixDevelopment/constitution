#!/usr/bin/env bash
# tests/sync/test_robustness.sh -- ROBUSTNESS suite (review round 4 findings RV4-1 .. RV4-15 and the mutants
# V01 V02 V04 V08 V09 V13 V16 V17 V18 V22 that survived round 4): races between inspection and write, a staged
# gitlink, long and huge remote stderr, signals, the environment and repository config that could re-enable
# prompts or helpers, unwritable evidence directories, overlapping roots, odd gitlink paths. The body is
# scripts/sync/robustness_checks.py; it drives the real engine (SX_ENGINE, default the wrapper) against real
# git in a mktemp sandbox; no network (file:// and 127.0.0.1 only), $HOME untouched.
# Usage: bash tests/sync/test_robustness.sh [--only NAME,NAME]   Exit: 0 pass, 1 a check failed, 2 no sandbox.
# Classification: universal (§11.4.17).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -I "$here/../../scripts/sync/robustness_checks.py" "$@"
