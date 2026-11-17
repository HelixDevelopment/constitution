#!/usr/bin/env bash
# run_gates.sh — runs the §11.4.297 gates against this repository with its own config/delivery.conf
# and records each command, its output and its exit status. Account names in the output are replaced
# by <reviewer-account>. Usage: run_gates.sh <repo-root> <out-dir> <since-rev>
set -u -o pipefail
ROOT="${1:?repo root}"; OUT="${2:?out dir}"; SINCE="${3:?since rev}"
ACC="$(awk -F= '/^pr_reviewers=/{print $2}' "$ROOT/config/delivery.conf" | tr -d ' ')"
[ -n "$ACC" ] || exit 2
red() { sed "s/${ACC}/<reviewer-account>/gI"; }
run() { local n="$1"; shift
    { echo "# command: $*"; echo "# time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; timeout 600 "$@" 2>&1; echo "# exit: $?"; } | red >"$OUT/$n.txt"; }
G="$ROOT/scripts/gates"
run gate_anchor_wired bash "$G/cm_pr_delivery_anchor_wired.sh" --root "$ROOT"
run gate_account_free_default bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT"
run gate_account_free_with_config bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT" --consumer-config "$ROOT/config/delivery.conf"
run gate_account_free_changed_since bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT" --consumer-config "$ROOT/config/delivery.conf" --changed-since "$SINCE"
run gate_account_free_mutation bash "$G/cm_pr_delivery_account_name_free_mutation_test.sh"
grep -H '^# exit:' "$OUT"/gate_*.txt
