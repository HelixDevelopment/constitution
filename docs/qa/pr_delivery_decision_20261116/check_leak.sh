#!/usr/bin/env bash
# check_leak.sh — the reviewer account must appear in config/delivery.conf and in no other file this
# change touches (text files; the binary tracker DB is checked with sqlite3 on the two new items).
# Control needles: positive (config/delivery.conf must hit), negative (a fabricated name must not).
# Usage: check_leak.sh <repo-root>   Exit 0 clean, 1 leak, 2 blind.
set -u -o pipefail
R="${1:?}"; cd "$R" || exit 2
ACC="$(awk -F= '/^pr_reviewers=/{print $2}' config/delivery.conf | tr -d ' ')"; [ -n "$ACC" ] || exit 2
grep -qiw -- "$ACC" config/delivery.conf || { echo "BLIND positive needle"; exit 2; }
grep -rqiw -- "zz-fabricated-account-qq" config docs/guides/pr_delivery_landing_guide.md && { echo "BLIND negative needle"; exit 2; }
rc=0
for f in $( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u); do
    [ "$f" = config/delivery.conf ] && continue
    [ "$f" = docs/workable_items.db ] && continue
    grep -qiw -- "$ACC" "$f" && { echo "LEAK: $f"; rc=1; }
done
n="$(sqlite3 docs/workable_items.db "select count(*) from items where atm_id in ('CON-423','CON-424') and (lower(title) like lower('%$ACC%') or lower(description) like lower('%$ACC%'))")"
[ "$n" = 0 ] || { echo "LEAK: tracker items"; rc=1; }
[ "$rc" = 0 ] && echo "CLEAN: account only in config/delivery.conf"
exit "$rc"
