#!/usr/bin/env bash
# tests/layout/run_all.sh — run every tests/layout/test_*.sh suite and print a
# per-suite and total PASS/FAIL line. Exit 0 only when every suite exits 0.
# LAYOUT_SRC_ROOT (optional) points the suites at another source tree (for
# example a `git archive HEAD` export, to observe RED on the unfixed code).
# Usage: bash tests/layout/run_all.sh [suite-name-substring]
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
filter="${1:-}"
total=0; failed=0
for t in "$HERE"/test_*.sh; do
    name="$(basename "$t" .sh)"
    case "$name" in test_layout_mutations) continue ;; esac
    [ -n "$filter" ] && case "$name" in *"$filter"*) ;; *) continue ;; esac
    total=$((total + 1))
    out="$(bash "$t" 2>&1)"; rc=$?
    line="$(printf '%s\n' "$out" | grep -E ': PASS=[0-9]+ FAIL=[0-9]+$' | tail -1)"
    [ -n "$line" ] || line="$name: no summary line"
    printf '%-26s rc=%d  %s\n' "$name" "$rc" "$line"
    if [ "$rc" -ne 0 ]; then
        failed=$((failed + 1))
        printf '%s\n' "$out" | grep -E '^FAIL' | sed 's/^/    /'
    fi
done
printf '==== layout suites: %d run, %d failed\n' "$total" "$failed"
[ "$failed" -eq 0 ] && [ "$total" -gt 0 ]
