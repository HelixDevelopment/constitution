#!/usr/bin/env bash
# probe_selfflag.sh — does CM-PR-DELIVERY-ACCOUNT-NAME-FREE --changed-since report the consumer's own
# config/delivery.conf when that file lives INSIDE the scanned root (this repository is its own consumer)?
# Runs in a throwaway clone <probe> of HEAD with only config/delivery.conf added (no binary DB change).
# Usage: probe_selfflag.sh <repo-root> <probe-clone> <out-file>
set -u -o pipefail
ROOT="${1:?}"; P="${2:?}"; OUT="${3:?}"
ACC="$(awk -F= '/^pr_reviewers=/{print $2}' "$ROOT/config/delivery.conf" | tr -d ' ')"; [ -n "$ACC" ] || exit 2
git -C "$P" checkout -q --detach "$(git -C "$ROOT" rev-parse HEAD)" || exit 2
mkdir -p "$P/config" && cp "$ROOT/config/delivery.conf" "$P/config/delivery.conf"
{ echo "# probe clone at $(git -C "$P" rev-parse HEAD), untracked: config/delivery.conf"
  timeout 300 bash "$P/scripts/gates/cm_pr_delivery_account_name_free.sh" --root "$P" \
      --consumer-config "$P/config/delivery.conf" --changed-since HEAD 2>&1 | tail -4
  echo "# exit: ${PIPESTATUS[0]}"; } | sed "s/${ACC}/<reviewer-account>/gI" >"$OUT"
rm -f "${P:?}/config/delivery.conf"
