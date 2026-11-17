#!/usr/bin/env bash
# run_gates_r2.sh — round-2 gate runs for CON-423/CON-424: the §11.4.297 anchor gate, the account-name gate
# (default lookup, explicit config, --changed-since a base), the post-update hub-gates test and the full-suite
# manifest gate. Each command, its output and its exit status are recorded; account names read from
# config/delivery.conf are replaced by <account>. Usage: run_gates_r2.sh <repo-root> <out-dir> <since-rev>
set -u -o pipefail
ROOT="${1:?repo root}"; OUT="${2:?out dir}"; SINCE="${3:?since rev}"
ACCS="$(awk -F= '{sub(/#.*/,"")} $1=="pr_reviewers"||$1=="pr_assignees"{print $2}' "$ROOT/config/delivery.conf" | tr ', ' '\n\n' | grep . | sort -u)"
[ -n "$ACCS" ] || exit 2
red() { local s; s="$(cat)"; while IFS= read -r a; do s="$(printf '%s' "$s" | sed "s/${a}/<account>/gI")"; done <<<"$ACCS"; printf '%s\n' "$s" | sed "s|$ROOT|<root>|g"; }
run() { local n="$1"; shift
    { echo "# command: $*"; echo "# time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; (cd "$ROOT" && timeout 900 "$@") 2>&1; echo "# exit: $?"; } | red >"$OUT/$n.txt"; }
G="$ROOT/scripts/gates"
run gate_anchor_wired bash "$G/cm_pr_delivery_anchor_wired.sh" --root "$ROOT"
run gate_account_free_default bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT"
run gate_account_free_with_config bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT" --consumer-config "$ROOT/config/delivery.conf"
run gate_account_free_changed_since bash "$G/cm_pr_delivery_account_name_free.sh" --root "$ROOT" --changed-since "$SINCE"
run test_post_update_hub_gates bash "$ROOT/tests/test_post_update_hub_gates.sh"
run gate_full_suite_manifest bash "$G/cm_full_suite_manifest_complete.sh" --root "$ROOT"
grep -H '^# exit:' "$OUT"/gate_*.txt "$OUT"/test_*.txt
