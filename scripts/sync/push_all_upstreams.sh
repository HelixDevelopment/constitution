#!/usr/bin/env bash
# scripts/sync/push_all_upstreams.sh -- §11.4.299 guarded post-merge helper: fast-forward push of one merged sha to
# EVERY upstream of one repository that does not yet carry it, then a read-back with verify_upstream_parity.sh.
# USAGE  push_all_upstreams.sh --repo DIR --sha SHA [--branch main] [--exempt FILE] [--apply]
#   default is a DRY RUN (prints the pushes it would make); --apply performs them.
# SAFETY  never force: the refspec is `SHA:refs/heads/BRANCH` (never `+`), no --force/--force-with-lease/--no-verify; git itself
#   refuses a non-fast-forward and the refusal is reported as BLOCKED, never bypassed. SHA must be a commit of DIR and an
#   ancestor-or-equal of DIR's local BRANCH tip is NOT required (a merged sha fetched from the platform is accepted) but
#   it must exist locally. Per-upstream result lines: PUSHED / BLOCKED / SKIPPED. EXIT 0 every upstream reads the sha
#   after the push (read-back) · 1 a push was refused or a read-back differs · 2 cannot determine / usage.
# Classification: universal (§11.4.17).
for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE; do unset "$_v"; done
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
REPO=""; SHA=""; BRANCH=main; EXEMPT=""; APPLY=0
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="${2:-}"; shift 2;; --sha) SHA="${2:-}"; shift 2;; --branch) BRANCH="${2:-}"; shift 2;;
  --exempt) EXEMPT="${2:-}"; shift 2;; --apply) APPLY=1; shift;;
  -h|--help) sed -n '2,12p' "$0"; exit 0;;
  *) echo "push_all_upstreams: unknown argument: $1" >&2; exit 2;; esac; done
[ -n "$REPO" ] && [ -n "$SHA" ] || { echo "push_all_upstreams: --repo and --sha are required" >&2; exit 2; }
git -C "$REPO" cat-file -e "$SHA^{commit}" 2>/dev/null || { echo "push_all_upstreams: sha not in $REPO" >&2; exit 2; }
EX=(); [ -n "$EXEMPT" ] && EX=(--exempt "$EXEMPT")
out=$(VUP_RAW=1 bash "$HERE/verify_upstream_parity.sh" --repo "$REPO" --branch "$BRANCH" --sha "$SHA" "${EX[@]}" 2>&1); rc=$?
printf '%s\n' "$out" | sed -E 's#(://)[^/@]*@#\1#'
[ "$rc" = 2 ] && grep -q 'no upstream is declared' <<<"$out" && exit 2
BLOCK=0
while read -r word url _; do
  [ "$word" = BEHIND ] || continue
  if [ "$APPLY" = 1 ]; then
    if git -C "$REPO" push "$url" "$SHA:refs/heads/$BRANCH" >/dev/null 2>&1; then echo "PUSHED   $(printf '%s' "$url" | sed -E 's#(://)[^/@]*@#\1#')"
    else echo "BLOCKED  $(printf '%s' "$url" | sed -E 's#(://)[^/@]*@#\1#')  (push refused; never forced)"; BLOCK=1; fi
  else echo "WOULD-PUSH  $(printf '%s' "$url" | sed -E 's#(://)[^/@]*@#\1#')"; fi
done < <(grep -E '^[[:space:]]+BEHIND[[:space:]]' <<<"$out")
[ "$APPLY" = 1 ] || { echo "DRY-RUN: nothing pushed (use --apply)"; exit "$rc"; }
echo "-- read-back --"
bash "$HERE/verify_upstream_parity.sh" --repo "$REPO" --branch "$BRANCH" --sha "$SHA" "${EX[@]}"; rc2=$?
[ "$BLOCK" = 1 ] && [ "$rc2" = 0 ] && rc2=1
exit "$rc2"
