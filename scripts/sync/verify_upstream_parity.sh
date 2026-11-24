#!/usr/bin/env bash
# scripts/sync/verify_upstream_parity.sh -- §11.4.299 read-only proof that a merged `main` is on EVERY upstream.
#
# PURPOSE  A merge (a pull request merged on the hosting platform, or a local fast-forward) moves `main` on ONE host.
#   §11.4.299 says the work is not delivered until every declared upstream of the repository reads the merged sha.
#   This script enumerates the upstreams of a repository (or of a whole fleet) and READS each one back with
#   `git ls-remote`; it never pushes, fetches, commits or changes any ref (push helper: push_all_upstreams.sh).
#
# USAGE  verify_upstream_parity.sh [--repo DIR | --fleet ROOT] [--branch main] [--sha SHA]
#          [--exempt FILE] [--own-org ORG]... [--skip PATH]... [--timeout SEC] [--quiet] [-h|--help]
#   --repo DIR     check one repository (default: the current directory)
#   --fleet ROOT   check ROOT and every submodule its .gitmodules declares, recursively (derived, never a roster);
#                  a submodule whose declared URL is outside every --own-org is a NOTE (third party), never a verdict input;
#                  an uninitialised own submodule is CANNOT-DETERMINE (exit 2), never skipped silently
#   --branch B     the branch every upstream must carry (default main)
#   --sha SHA      the sha that must be on every upstream (default: the local <branch> tip, else HEAD); a sha newer
#                  than the local tip is accepted (the merged sha of a pull request read from the platform)
#   --exempt FILE  TSV `<repo-relative-path>\t<url-substring>\t<reason>`; a matching upstream is reported EXEMPT with
#                  its reason on every run and is not a verdict input; an empty reason makes the run exit 2
#   --own-org ORG  repeatable; with --fleet only submodules whose URL contains `/ORG/` or `:ORG/` are own
#   --skip PATH    repeatable; a repo-relative path of a submodule to leave out (reported as NOTE)
# UPSTREAMS  the union, de-duplicated by normalised URL, of (1) every push URL of every remote
#   (`git remote get-url --all --push`, NOT the first-URL-only form) and (2) every `UPSTREAMABLE_REPOSITORY` of every
#   enabled recipe `upstreams/*.sh` / `Upstreams/*.sh` (a `*.sh.disabled` recipe is not enabled).
# VERDICT per upstream  CURRENT (tip == sha) · AHEAD (tip contains sha) · BEHIND (tip is an ancestor of sha: push owed)
#   · DIVERGED (neither contains the other) · DIFFERS (tip not in the local object store: direction unknown) ·
#   UNREACHABLE (no answer) · NO-BRANCH (answered, branch absent) · EXEMPT.
# EXIT  0 every upstream CURRENT or AHEAD or EXEMPT · 1 at least one BEHIND, DIVERGED, DIFFERS or NO-BRANCH ·
#   2 could not determine (a repo with no upstream, an UNREACHABLE upstream, a bad exemption, an uninitialised own
#   submodule, a usage error) -- 2 is NEVER a pass; precedence: 1 outranks 2 outranks 0.
# SAFETY  read-only: only `git ls-remote`, `git rev-parse`, `git merge-base --is-ancestor`, `git remote`, `git config`.
#   Output never carries a credential: userinfo is stripped from every printed URL.
# Classification: universal (§11.4.17) -- no project literal.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE; do unset "$_ge_v"; done
set -u

BRANCH=main; SHA=""; REPO=""; FLEET=""; EXEMPT=""; TIMEOUT=25; QUIET=0
OWN=(); SKIP=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --fleet) FLEET="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --sha) SHA="${2:-}"; shift 2 ;;
    --exempt) EXEMPT="${2:-}"; shift 2 ;;
    --own-org) OWN+=("${2:-}"); shift 2 ;;
    --skip) SKIP+=("${2:-}"); shift 2 ;;
    --timeout) TIMEOUT="${2:-25}"; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "verify_upstream_parity: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] && [ -n "$FLEET" ] && { echo "verify_upstream_parity: --repo and --fleet are exclusive" >&2; exit 2; }
[ -z "$REPO" ] && [ -z "$FLEET" ] && REPO="."
if [ -n "$SHA" ] && ! printf '%s' "$SHA" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "verify_upstream_parity: --sha must be a full 40-hex sha" >&2; exit 2
fi

F1=0; F2=0   # findings (1) and could-not-determine (2) counters
say() { [ "$QUIET" = 1 ] && return 0; printf '%s\n' "$*"; }
redact() { if [ "${VUP_RAW:-0}" = 1 ]; then cat; else sed -E 's#(://)[^/@]*@#\1#'; fi; }
norm() { printf '%s' "$1" | sed -E 's#^ssh://##; s#^[a-z+]+://##; s#^[^@/]*@##; s#:[0-9]+/#/#; s#:#/#; s#\.git$##; s#/+$##' | tr 'A-Z' 'a-z'; }

# exemption lookup: prints reason (rc 0) when (repo-rel path, url) is exempt; rc 3 on an empty reason; rc 1 none
exempt_reason() {
  [ -n "$EXEMPT" ] && [ -r "$EXEMPT" ] || return 1
  local rel="$1" url="$2" p s r
  while IFS=$'\t' read -r p s r; do
    case "$p" in ''|'#'*) continue ;; esac
    [ "$p" = "$rel" ] || continue
    case "$url" in *"$s"*)
      [ -n "${r// /}" ] || return 3
      printf '%s' "$r"; return 0 ;;
    esac
  done < "$EXEMPT"
  return 1
}

check_repo() {  # $1 = absolute dir, $2 = display name
  local dir="$1" name="$2" urls="" u rec line sha_exp
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    say "CANNOT-DETERMINE  $name  not a git working tree (uninitialised submodule?)"; F2=$((F2+1)); return
  fi
  while read -r u; do [ -n "$u" ] && urls="$urls"$'\n'"$u"; done < <(
    for r in $(git -C "$dir" remote 2>/dev/null); do git -C "$dir" remote get-url --all --push "$r" 2>/dev/null; done)
  for rec in "$dir"/upstreams/*.sh "$dir"/Upstreams/*.sh; do
    [ -f "$rec" ] || continue
    line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?UPSTREAMABLE_REPOSITORY=' "$rec" | head -1 | sed -E 's/^[^=]*=//; s/^["'"'"']//; s/["'"'"'].*$//')
    [ -n "$line" ] && urls="$urls"$'\n'"$line"
  done
  # de-duplicate by normalised URL, keep the first spelling
  local seen="" uniq=""
  while read -r u; do
    [ -n "$u" ] || continue
    k=$(norm "$u")
    case "$seen" in *"|$k|"*) continue ;; esac
    seen="$seen|$k|"; uniq="$uniq"$'\n'"$u"
  done <<< "$urls"
  if [ -z "${uniq//[$'\n ']/}" ]; then
    say "CANNOT-DETERMINE  $name  no upstream is declared (no push URL, no enabled upstreams/*.sh recipe)"; F2=$((F2+1)); return
  fi
  sha_exp="$SHA"
  [ -z "$sha_exp" ] && sha_exp=$(git -C "$dir" rev-parse --verify -q "refs/heads/$BRANCH^{commit}" 2>/dev/null || git -C "$dir" rev-parse --verify -q HEAD 2>/dev/null)
  if [ -z "$sha_exp" ]; then say "CANNOT-DETERMINE  $name  no local $BRANCH tip and no HEAD"; F2=$((F2+1)); return; fi
  say "== $name  branch=$BRANCH sha=${sha_exp:0:12}"
  local n=0 tmpd; tmpd=$(mktemp -d) || { F2=$((F2+1)); return; }
  while read -r u; do
    [ -n "$u" ] || continue; n=$((n+1))
    ( timeout "$TIMEOUT" git -C "$dir" ls-remote "$u" "refs/heads/$BRANCH" > "$tmpd/$n.out" 2> "$tmpd/$n.err"; echo $? > "$tmpd/$n.rc" ) &
    printf '%s\n' "$u" > "$tmpd/$n.url"
  done <<< "$uniq"
  wait
  local i tip rc shown why
  for i in $(seq 1 "$n"); do
    u=$(cat "$tmpd/$i.url"); shown=$(printf '%s' "$u" | redact); rc=$(cat "$tmpd/$i.rc" 2>/dev/null || echo 99)
    if why=$(exempt_reason "$name" "$u"); then
      say "  EXEMPT       $shown  reason: $why"; continue
    else
      case $? in 3) say "  BAD-EXEMPTION $shown  (empty reason)"; F2=$((F2+1)); continue ;; esac
    fi
    if [ "$rc" != 0 ]; then say "  UNREACHABLE  $shown  (ls-remote rc=$rc)"; F2=$((F2+1)); continue; fi
    tip=$(awk '{print $1}' "$tmpd/$i.out" | head -1)
    if [ -z "$tip" ]; then say "  NO-BRANCH    $shown  (answered, no refs/heads/$BRANCH)"; F1=$((F1+1)); continue; fi
    if [ "$tip" = "$sha_exp" ]; then say "  CURRENT      $shown  $tip"
    elif ! git -C "$dir" cat-file -e "$tip^{commit}" 2>/dev/null; then say "  DIFFERS      $shown  tip $tip not in the local object store (direction unknown; fetch to classify)"; F1=$((F1+1))
    elif git -C "$dir" merge-base --is-ancestor "$sha_exp" "$tip" 2>/dev/null; then say "  AHEAD        $shown  $tip contains $sha_exp"
    elif git -C "$dir" merge-base --is-ancestor "$tip" "$sha_exp" 2>/dev/null; then say "  BEHIND       $shown  tip $tip, push owed (fast-forward)"; F1=$((F1+1))
    else say "  DIVERGED     $shown  tip $tip and $sha_exp are not ancestors of each other"; F1=$((F1+1)); fi
  done
  rm -rf "${tmpd:?}"
}

is_own() {  # $1 url ; with no --own-org every submodule is own
  [ "${#OWN[@]}" -eq 0 ] && return 0
  local o; for o in "${OWN[@]}"; do case "$1" in *"/$o/"*|*":$o/"*) return 0 ;; esac; done; return 1
}
is_skipped() { local s; for s in "${SKIP[@]:-}"; do [ -n "$s" ] && [ "$s" = "$1" ] && return 0; done; return 1; }

walk() {  # $1 abs dir, $2 display name
  check_repo "$1" "$2"
  [ -f "$1/.gitmodules" ] || return 0
  local key path url
  while read -r key path; do
    url=$(git config -f "$1/.gitmodules" --get "${key%.path}.url" 2>/dev/null)
    local rel="${2#.}"; rel="${rel#/}"; [ -n "$rel" ] && rel="$rel/$path" || rel="$path"
    if is_skipped "$rel"; then say "NOTE  $rel  skipped by --skip"; continue; fi
    if ! is_own "$url"; then say "NOTE  $rel  third party (url outside --own-org), not a verdict input"; continue; fi
    if [ ! -e "$1/$path/.git" ]; then say "CANNOT-DETERMINE  $rel  declared submodule is not initialised"; F2=$((F2+1)); continue; fi
    walk "$1/$path" "$rel"
  done < <(git config -f "$1/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null)
}

if [ -n "$FLEET" ]; then
  ROOT=$(cd "$FLEET" 2>/dev/null && pwd) || { echo "verify_upstream_parity: --fleet root not found" >&2; exit 2; }
  walk "$ROOT" "."
else
  ROOT=$(cd "$REPO" 2>/dev/null && pwd) || { echo "verify_upstream_parity: --repo not found" >&2; exit 2; }
  check_repo "$ROOT" "$(basename "$ROOT")"
fi
if [ "$F1" -gt 0 ]; then echo "RESULT: BEHIND-OR-DIVERGED ($F1 finding(s), $F2 undetermined) -- exit 1"; exit 1; fi
if [ "$F2" -gt 0 ]; then echo "RESULT: CANNOT-DETERMINE ($F2 undetermined) -- exit 2 (never a pass)"; exit 2; fi
echo "RESULT: every upstream carries the sha -- exit 0"; exit 0
