#!/usr/bin/env bash
# run_gates_r3.sh — round-3 runs for the pull-request delivery vehicle (CON-PENDINGprdecl, CON-PENDINGprgate,
# CON-PENDINGprauth): the §11.4.297 anchor gate and its propagation gate, the account-name gate (default lookup,
# explicit config, --changed-since a base), the post-update hub-gates test, the full-suite manifest (--verify-manifest),
# the gate-ledger ratchet, the git-env class census, the workable-items engine validate and diff, and the index
# freshness gate. Each command, its output and its exit status are recorded; account names read from config/delivery.conf
# are replaced by <account>, the root path by <root>, run-specific temporary paths by <tmp> and timestamps by <time>,
# so two passes can be compared by sha256. Mutation tests are run separately (they take about half an hour each).
# Usage: run_gates_r3.sh <repo-root> <out-dir> <since-rev>
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic
set -u -o pipefail
ROOT="${1:?repo root}"; OUT="${2:?out dir}"; SINCE="${3:?since rev}"
mkdir -p -- "$OUT" || exit 2
ACCS="$(awk -F= '{sub(/#.*/,"")} $1=="pr_reviewers"||$1=="pr_assignees"{print $2}' "$ROOT/config/delivery.conf" | tr ', ' '\n\n' | grep . | sort -u)"
[ -n "$ACCS" ] || exit 2
red() { local s; s="$(cat)"; while IFS= read -r a; do s="$(printf '%s' "$s" | sed "s/${a}/<account>/gI")"; done <<<"$ACCS"
    printf '%s\n' "$s" | sed -e "s|$ROOT|<root>|g" -e 's|/mnt/DATA1TB/claude-work/tmp/[A-Za-z0-9._/-]*|<tmp>|g' \
        -e 's/[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z/<time>/g' -e 's/[0-9.]* s)$/<s>)/'; }
run() { local n="$1" rc; shift
    { echo "# command: $*"; (cd "$ROOT" && timeout 1200 "$@") 2>&1; rc=$?; echo "# exit: $rc"; } | red >"$OUT/$n.txt"; }
G="$ROOT/scripts/gates"; E="$ROOT/scripts/workable-items/bin/workable-items"
run gate_anchor_wired bash "$G/cm_pr_delivery_anchor_wired.sh" --root "$ROOT"
run gate_propagation_297 bash "$G/cm_covenant_114_297_propagation.sh"
run gate_account_free_default bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT"
run gate_account_free_with_config bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT" --consumer-config "$ROOT/config/delivery.conf"
run gate_account_free_changed_since bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT" --changed-since "$SINCE"
run test_post_update_hub_gates bash "$ROOT/tests/test_post_update_hub_gates.sh"
run verify_manifest bash "$ROOT/scripts/run_full_suite.sh" --verify-manifest
run gate_ledger_ratchet bash "$G/cm_gate_ledger_ratchet.sh"
run git_env_census python3 "$ROOT/scripts/validation/git_env_class_census.py"
run engine_validate "$E" validate --db "$ROOT/docs/workable_items.db"
run engine_diff "$E" diff --db "$ROOT/docs/workable_items.db" --issues "$ROOT/docs/Issues.md" --fixed "$ROOT/docs/Fixed.md"
run index_fresh bash "$G/cm_constitution_index_fresh.sh"
grep -H '^# exit:' "$OUT"/*.txt
