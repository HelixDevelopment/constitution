#!/usr/bin/env bash
# scripts/sync/verify_constitution_latest.sh -- §11.4.299 (and §11.4.26/§11.4.35) read-only check that a consuming project's
# constitution submodule IS the latest upstream codebase and that every nested submodule of it is initialised and at its
# recorded pin (and, unless --no-nested-remote, at its own remote head).
# USAGE  verify_constitution_latest.sh --root PROJECT_ROOT [--path submodules/constitution] [--branch main]
#          [--no-nested-remote] [--timeout SEC] [--quiet]
# CHECKS (read-only: git ls-files, rev-parse, ls-remote, merge-base, submodule status)
#   1 the recorded gitlink (index) equals the checked-out HEAD                       else 1 (unstaged pin move)
#   2 HEAD equals `git ls-remote <origin> refs/heads/<branch>`                       CURRENT
#       HEAD is an ancestor of the remote tip -> BEHIND (fast-forward owed, the standing operator authorisation applies)
#       the remote tip is an ancestor of HEAD -> AHEAD (the checkout carries unpublished commits)   both exit 1
#       tip not in the local object store -> DIFFERS (fetch to classify)                          exit 1
#   3 `git submodule status --recursive` inside it: a `-` row (uninitialised), `+` (checkout != recorded) or `U` -> exit 1
#   4 each nested submodule HEAD vs the remote default-branch head of its declared URL -> BEHIND / DIFFERS exit 1
#     (UNREACHABLE -> 2). A nested pin that is intentionally older must be recorded by the project as DATA; none is assumed.
# EXIT  0 all current · 1 any finding · 2 cannot determine (unreachable remote, missing submodule, usage); 2 is never a pass,
#   1 outranks 2.
for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE; do unset "$_v"; done
set -u
ROOT=""; SP=submodules/constitution; BR=main; NESTED=1; TO=25; Q=0
while [ $# -gt 0 ]; do case "$1" in
  --root) ROOT="${2:-}"; [ $# -ge 2 ] || { echo "verify_constitution_latest: option needs a value" >&2; exit 2; }; shift 2;; --path) SP="${2:-}"; [ $# -ge 2 ] || { echo "verify_constitution_latest: option needs a value" >&2; exit 2; }; shift 2;; --branch) BR="${2:-}"; [ $# -ge 2 ] || { echo "verify_constitution_latest: option needs a value" >&2; exit 2; }; shift 2;;
  --no-nested-remote) NESTED=0; shift;; --timeout) TO="${2:-25}"; [ $# -ge 2 ] || { echo "verify_constitution_latest: option needs a value" >&2; exit 2; }; shift 2;; --quiet) Q=1; shift;;
  -h|--help) sed -n '2,19p' "$0"; exit 0;; *) echo "unknown argument: $1" >&2; exit 2;; esac; done
[ -n "$ROOT" ] || { echo "--root required" >&2; exit 2; }
F1=0; F2=0; say() { [ "$Q" = 1 ] || printf '%s\n' "$*"; }
D="$ROOT/$SP"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "RESULT: CANNOT-DETERMINE (root not a git tree) -- exit 2"; exit 2; }
if ! git -C "$D" rev-parse --git-dir >/dev/null 2>&1; then echo "RESULT: CANNOT-DETERMINE ($SP not initialised) -- exit 2"; exit 2; fi
HEAD_SHA=$(git -C "$D" rev-parse HEAD)
REC=$(git -C "$ROOT" ls-files -s -- "$SP" | awk '$1=="160000"{print $2}')
if [ -z "$REC" ]; then say "CANNOT-DETERMINE  no gitlink recorded for $SP"; F2=$((F2+1))
elif [ "$REC" = "$HEAD_SHA" ]; then say "CURRENT   gitlink == checkout ${HEAD_SHA:0:12}"
else say "DRIFT     gitlink ${REC:0:12} != checkout ${HEAD_SHA:0:12}"; F1=$((F1+1)); fi
URL=$(git -C "$D" remote get-url origin 2>/dev/null)
TIP=$(timeout "$TO" git -C "$D" ls-remote "$URL" "refs/heads/$BR" 2>/dev/null | awk '{print $1}' | head -1)
if [ -z "$TIP" ]; then say "UNREACHABLE  constitution origin (no answer for $BR)"; F2=$((F2+1))
elif [ "$TIP" = "$HEAD_SHA" ]; then say "CURRENT   constitution == upstream $BR ${TIP:0:12}"
elif ! git -C "$D" cat-file -e "$TIP^{commit}" 2>/dev/null; then say "DIFFERS   constitution ${HEAD_SHA:0:12} upstream ${TIP:0:12} (not in object store; fetch to classify)"; F1=$((F1+1))
elif git -C "$D" merge-base --is-ancestor "$HEAD_SHA" "$TIP"; then say "BEHIND    constitution ${HEAD_SHA:0:12} upstream ${TIP:0:12} (fast-forward owed)"; F1=$((F1+1))
else say "AHEAD     constitution ${HEAD_SHA:0:12} carries commits upstream ${TIP:0:12} lacks"; F1=$((F1+1)); fi
VCLERR=$(mktemp) || exit 2
ST=$(git -C "$D" submodule status --recursive 2>"$VCLERR"); src=$?; n=0; bad=0
if [ "$src" != 0 ]; then say "CANNOT-DETERMINE  recursive submodule status failed (rc=$src): $(head -2 "$VCLERR" | tr '\n' ' ')"; F2=$((F2+1)); fi
rm -f "$VCLERR"
while IFS= read -r l; do [ -n "$l" ] || continue; n=$((n+1)); case "${l:0:1}" in
  -) say "UNINITIALISED  ${l:1}"; F1=$((F1+1)); bad=$((bad+1));; +) say "NOT-AT-PIN      ${l:1}"; F1=$((F1+1)); bad=$((bad+1));; U) say "CONFLICT        ${l:1}"; F1=$((F1+1)); bad=$((bad+1));; esac; done <<< "$ST"
say "NESTED   $n submodule row(s), $bad not initialised/at pin"
[ "$n" -gt 0 ] || { say "CANNOT-DETERMINE  no nested rows read (a constitution with zero submodules is not this one)"; F2=$((F2+1)); }
if [ "$NESTED" = 1 ] && [ "$bad" = 0 ]; then
  while IFS= read -r l; do [ -n "$l" ] || continue; sha=$(echo "${l:1}" | awk '{print $1}'); path=$(echo "${l:1}" | awk '{print $2}')
    sub="$D/$path"; u=$(git -C "$sub" remote get-url origin 2>/dev/null); [ -n "$u" ] || { say "CANNOT-DETERMINE  $path has no origin"; F2=$((F2+1)); continue; }
    t=$(timeout "$TO" git -C "$sub" ls-remote "$u" HEAD 2>/dev/null | awk '{print $1}' | head -1)
    if [ -z "$t" ]; then say "  UNREACHABLE $path"; F2=$((F2+1))
    elif [ "$t" = "$sha" ]; then say "  CURRENT     $path"
    elif ! git -C "$sub" cat-file -e "$t^{commit}" 2>/dev/null; then say "  DIFFERS     $path ${sha:0:12} vs ${t:0:12}"; F1=$((F1+1))
    elif git -C "$sub" merge-base --is-ancestor "$sha" "$t"; then say "  BEHIND      $path ${sha:0:12} vs ${t:0:12}"; F1=$((F1+1))
    else say "  AHEAD       $path ${sha:0:12} vs ${t:0:12}"; F1=$((F1+1)); fi
  done <<< "$(git -C "$D" submodule status 2>/dev/null)"
fi
[ "$F1" -gt 0 ] && { echo "RESULT: NOT-LATEST ($F1 finding(s), $F2 undetermined) -- exit 1"; exit 1; }
[ "$F2" -gt 0 ] && { echo "RESULT: CANNOT-DETERMINE ($F2) -- exit 2 (never a pass)"; exit 2; }
echo "RESULT: constitution is the latest upstream and its submodules are initialised and current -- exit 0"; exit 0
