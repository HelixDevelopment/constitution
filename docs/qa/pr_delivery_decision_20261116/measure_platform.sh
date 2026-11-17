#!/usr/bin/env bash
# measure_platform.sh — read-only measurement of the hosting-platform facts the PR-delivery
# decision of 2026-11-16 (§11.4.297) depends on. It never writes to the platform.
# Usage: measure_platform.sh <repo-root> <out-dir>
# The reviewer account is read from <repo-root>/config/delivery.conf (key pr_reviewers) and is
# replaced by the token <reviewer-account> in every output, so no evidence file carries the
# account name (CM-PR-DELIVERY-ACCOUNT-NAME-FREE scans changed files under --changed-since).
# Exit: 0 all reads done; 2 a read failed (the failing read is named in the output).
set -u -o pipefail
ROOT="${1:?repo root}"; OUT="${2:?out dir}"
REPO="HelixDevelopment/HelixConstitution"
CONF="$ROOT/config/delivery.conf"
ACC="$(awk -F= '/^pr_reviewers=/{print $2}' "$CONF" | tr -d ' ')"
[ -n "$ACC" ] || { echo "no pr_reviewers in $CONF" >&2; exit 2; }
red() { sed "s/${ACC}/<reviewer-account>/gI"; }
rc=0
run() { # name, command...
    local n="$1"; shift
    { echo "# command: $*"; echo "# time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"; timeout 60 "$@" 2>&1; echo "# exit: $?"; } | red >"$OUT/$n.txt"
    grep -q '^# exit: 0$' "$OUT/$n.txt" || rc=2
}
run repo_settings gh api "repos/$REPO" --jq '{full_name,default_branch,allow_merge_commit,allow_squash_merge,allow_rebase_merge,delete_branch_on_merge,allow_auto_merge,owner_type:.owner.type,permissions}'
run branch_protection_main gh api "repos/$REPO/branches/main/protection"
run rulesets gh api "repos/$REPO/rulesets"
run ruleset_detail gh api "repos/$REPO/rulesets/27164960" --jq '{name,enforcement,target,conditions,rules,bypass_actors}'
run self_login gh api user --jq .login
run reviewer_permission gh api "repos/$REPO/collaborators/$ACC/permission" --jq '{permission,role_name}'
for pr in 7 8 9; do
    run "pr_$pr" gh pr view "$pr" -R "$REPO" --json number,state,author,mergedBy,mergeCommit,headRefName,headRefOid,reviewRequests,reviews,baseRefName
done
# own submodule repositories listed in config/delivery.conf own_repositories (read-only)
awk -F= '/^own_repositories=/{print $2}' "$CONF" | tr ',' '\n' | awk -F: 'NR>1{print $2}' | while IFS= read -r r; do
    n="sub_$(printf '%s' "$r" | tr '/' '_')"
    { echo "# repo: $r"; timeout 30 gh api "repos/$r" --jq '{full_name,default_branch,permissions}' 2>&1; echo "# exit: $?";
      timeout 30 gh api "repos/$r/rulesets" --jq '[.[]|{name,enforcement}]' 2>&1; echo "# exit: $?"; } | red >"$OUT/$n.txt"
done
# merge form of the three merges: second parent must equal the PR head
for pr in 7 8 9; do
    mc="$(gh pr view "$pr" -R "$REPO" --json mergeCommit --jq .mergeCommit.oid 2>/dev/null)"
    hd="$(gh pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid 2>/dev/null)"
    p2="$(git -C "$ROOT" rev-parse "$mc^2" 2>/dev/null)"
    printf 'pr=%s merge_commit=%s head=%s second_parent=%s form=%s\n' "$pr" "$mc" "$hd" "$p2" \
        "$([ -n "$p2" ] && [ "$p2" = "$hd" ] && echo merge-commit-second-parent-is-head || echo NOT-MATCHED)"
done >"$OUT/merge_form.txt"
grep -q NOT-MATCHED "$OUT/merge_form.txt" && rc=2
# control needle: the redaction must actually work (§11.4.273)
printf 'x %s y\n' "$ACC" | red | grep -q '<reviewer-account>' || { echo "redaction control needle failed" >&2; exit 2; }
grep -rqiw -- "$ACC" "$OUT" && { echo "account name leaked into $OUT" >&2; exit 2; }
exit "$rc"
