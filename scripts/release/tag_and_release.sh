#!/usr/bin/env bash
# scripts/release/tag_and_release.sh — tag one reviewed release commit, push it
# to every upstream, then publish platform releases, safely and resumably.
#
# Usage:
#   scripts/release/tag_and_release.sh --tag TAG --sha SHA --remotes "R1 R2 ..." \
#       [--title TITLE] [--prerelease] [--message MSG] \
#       [--release github:REMOTE:OWNER/REPO]... \
#       [--release gitlab:REMOTE:OWNER/REPO]... \
#       [--release gitea:REMOTE:BASE_URL:OWNER/REPO]... \
#       [--no-badge-check] [--dry-run]
#
# What it guarantees (each one is a finding of the v73.4 review, I-3 and m-3/m-4):
#   * nothing is written before every preflight passes: every remote is fetched
#     (a failed fetch aborts), every remote's main must be an ancestor of SHA,
#     HEAD must equal SHA with a clean tree, the FIRST "## " heading of
#     `git show SHA:CHANGELOG.md` must start with TAG, and (unless
#     --no-badge-check) scripts/badges/compute_badges.sh --check must pass;
#   * main and the tag reach a remote together: `git push --atomic REMOTE
#     SHA:refs/heads/main refs/tags/TAG:refs/tags/TAG`; when a server does not
#     support atomic pushes, main is pushed first and the tag ONLY after the
#     remote's main reads back as SHA, so a tag never lands on a remote whose
#     main does not contain it;
#   * a remote is OK only when `git ls-remote` shows main == SHA, the tag object
#     == the local tag object and the tag peels to SHA; a platform release is
#     created ONLY for an OK remote, GitLab gets --ref SHA as a second guard,
#     GitHub uses --verify-tag, and every release is looked up before it is
#     created (a re-run never creates a second one); GitHub legs are de-duplicated
#     by repository id and an inaccessible repository is an honest GAP;
#   * re-running after a partial failure is the resume path: an existing local
#     annotated tag that peels to SHA is reused, remotes already OK are skipped,
#     existing releases are kept; a local or remote tag of the same name that
#     points anywhere else stops the run (never deleted, never replaced);
#   * nothing is ever forced: no --force, no --force-with-lease, no "+" refspec,
#     no tag deletion, no history rewrite (§11.4.113).
#   * release notes are cut from `git show SHA:CHANGELOG.md`, never from the
#     working tree.
#
# Exit status (machine-readable; the last line is "RESULT: <word> ..."):
#   0 OK       every remote OK and every requested release present
#   1 FAIL     any MISMATCH, push failure, release failure, or a preflight abort
#   2 USAGE    bad arguments
#   5 GAPS     no failure, but at least one leg was SKIPPED (no credential, no
#              access); a gap is never reported as released
# A --dry-run that passes preflight prints the plan and exits 0 without writing.
set -u
set +x
LC_ALL=C; export LC_ALL

TAG="" SHA="" REMOTES="" TITLE="" MESSAGE="" PRERELEASE=0 DRY=0 BADGE_CHECK=1
RELEASES=()
usage() { sed -n '2,46p' "$0"; }
die_usage() { printf 'tag_and_release: %s\n' "$1" >&2; printf 'RESULT: USAGE\n'; exit 2; }
need() { [ "$1" -ge 2 ] || die_usage "option $2 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) need $# "$1"; TAG="$2"; shift 2 ;;
    --sha) need $# "$1"; SHA="$2"; shift 2 ;;
    --remotes) need $# "$1"; REMOTES="$2"; shift 2 ;;
    --title) need $# "$1"; TITLE="$2"; shift 2 ;;
    --message) need $# "$1"; MESSAGE="$2"; shift 2 ;;
    --release) need $# "$1"; RELEASES+=("$2"); shift 2 ;;
    --prerelease) PRERELEASE=1; shift ;;
    --no-badge-check) BADGE_CHECK=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done
[ -n "$TAG" ] || die_usage "--tag is required"
[ -n "$SHA" ] || die_usage "--sha is required"
[ -n "$REMOTES" ] || die_usage "--remotes is required (the upstream list is DATA, never guessed)"
printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die_usage "tag has unsafe characters"
for r in $REMOTES; do
  printf '%s' "$r" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die_usage "remote name has unsafe characters: $r"
done
for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do
  case "$spec" in
    github:*:*/*|gitlab:*:*/*|gitea:*:https://*:*/*|gitea:*:http://*:*/*) ;;
    *) die_usage "bad --release spec: $spec" ;;
  esac
  rr="${spec#*:}"; rr="${rr%%:*}"
  case " $REMOTES " in *" $rr "*) ;; *) die_usage "--release names remote '$rr' that is not in --remotes" ;; esac
done
[ -n "$TITLE" ] || TITLE="$TAG"
[ -n "$MESSAGE" ] || MESSAGE="$TAG"

FAILS=0 GAPS=0
fail() { FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$*"; }
gap()  { GAPS=$((GAPS + 1));  printf 'GAP %s\n' "$*"; }
abort() { printf 'ABORT %s\n' "$*"; printf 'RESULT: FAIL fails=1 gaps=0 (aborted before any write)\n'; exit 1; }

printf '== %s start tag=%s sha=%s dry_run=%s\n' "$(date -Is)" "$TAG" "$SHA" "$DRY"

# ---------- preflight (no writes) ----------
git rev-parse --git-dir >/dev/null 2>&1 || abort "not inside a git repository"
FULL="$(git rev-parse -q --verify "$SHA^{commit}" 2>/dev/null)" || abort "SHA $SHA is not a commit here"
SHA="$FULL"
[ "$(git rev-parse HEAD)" = "$SHA" ] || abort "HEAD $(git rev-parse HEAD) != $SHA"
[ -z "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ] || abort "working tree is not clean"

declare -A RMAIN
for r in $REMOTES; do
  git remote get-url "$r" >/dev/null 2>&1 || abort "remote $r is not configured"
  # No destination refspec and no "+": the fetched tip lands in FETCH_HEAD only.
  if ! git fetch -q --no-tags "$r" refs/heads/main 2>"${TMPDIR:-/tmp}/tar_fetch.$$"; then
    printf '%s\n' "$(head -c 400 "${TMPDIR:-/tmp}/tar_fetch.$$")"; rm -f -- "${TMPDIR:-/tmp}/tar_fetch.$$"
    abort "fetch of $r main failed"
  fi
  rm -f -- "${TMPDIR:-/tmp}/tar_fetch.$$"
  t="$(git rev-parse FETCH_HEAD)"
  RMAIN[$r]="$t"
  git merge-base --is-ancestor "$t" "$SHA" || abort "$r main $t is not an ancestor of $SHA (main moved; merge the new main into the release commit and re-review)"
done

FIRST="$(git show "$SHA:CHANGELOG.md" 2>/dev/null | awk '/^## /{print substr($0,4); exit}')"
case "$FIRST" in
  "$TAG"|"$TAG "*) ;;
  *) abort "the first '## ' heading of CHANGELOG.md at $SHA is not '$TAG ...' (got: ${FIRST:-<none>})" ;;
esac
NOTES="$(mktemp "${TMPDIR:-/tmp}/tar_notes.XXXXXX")" || abort "cannot create a temp file"
: "${NOTES:?}"
trap 'rm -f -- "$NOTES"' EXIT
git show "$SHA:CHANGELOG.md" | TAG="$TAG" awk 'BEGIN{t=ENVIRON["TAG"];on=0} /^## /{if(on)exit; h=substr($0,4); if(h==t||index(h,t" ")==1)on=1} on{print}' > "$NOTES"
[ -s "$NOTES" ] || abort "no release notes for $TAG at $SHA"

if [ "$BADGE_CHECK" -eq 1 ]; then
  [ -f scripts/badges/compute_badges.sh ] || abort "scripts/badges/compute_badges.sh absent (use --no-badge-check only where the repository has no badge computer)"
  bash scripts/badges/compute_badges.sh --check >/dev/null 2>&1 || abort "compute_badges.sh --check fails at $SHA"
fi

# Local tag: reuse when it peels to SHA (resume), stop when it points elsewhere.
LOCAL_TAG_EXISTS=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  [ "$(git cat-file -t "refs/tags/$TAG")" = tag ] || abort "local $TAG is a lightweight tag; refusing to reuse it"
  [ "$(git rev-parse "refs/tags/$TAG^{commit}")" = "$SHA" ] || abort "local $TAG points at $(git rev-parse "refs/tags/$TAG^{commit}"), not $SHA"
  LOCAL_TAG_EXISTS=1
fi

# Remote tags of the same name must be absent or the very same object.
declare -A RTAG
for r in $REMOTES; do
  ro="$(git ls-remote "$r" "refs/tags/$TAG" 2>/dev/null | awk '$2=="refs/tags/'"$TAG"'"{print $1}')" || true
  RTAG[$r]="$ro"
  if [ -n "$ro" ]; then
    [ "$LOCAL_TAG_EXISTS" -eq 1 ] || abort "$r already has $TAG ($ro) but no local tag exists; fetch that tag and check it, never re-create it"
    [ "$ro" = "$(git rev-parse "refs/tags/$TAG")" ] || abort "$r has a different $TAG object ($ro); never replaced (§11.4.113)"
  fi
done

if [ "$DRY" -eq 1 ]; then
  for r in $REMOTES; do printf 'PLAN push --atomic %s %s:refs/heads/main refs/tags/%s (remote main %s, remote tag %s)\n' "$r" "$SHA" "$TAG" "${RMAIN[$r]}" "${RTAG[$r]:-absent}"; done
  for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do printf 'PLAN release %s\n' "$spec"; done
  printf 'RESULT: OK dry-run (no tag created, nothing pushed)\n'
  exit 0
fi

if [ "$LOCAL_TAG_EXISTS" -eq 0 ]; then
  git tag -a "$TAG" -m "$MESSAGE" "$SHA" || abort "git tag failed"
  printf 'TAG created %s -> %s\n' "$TAG" "$SHA"
else
  printf 'TAG reused %s -> %s (resume)\n' "$TAG" "$SHA"
fi
TAGOBJ="$(git rev-parse "refs/tags/$TAG")"

# ---------- push ----------
remote_state() { # remote -> "MAIN TAGOBJ TAGPEELED"
  local out m o p
  out="$(git ls-remote "$1" refs/heads/main "refs/tags/$TAG" "refs/tags/$TAG^{}" 2>/dev/null)" || { printf 'ERR ERR ERR'; return 1; }
  m="$(printf '%s\n' "$out" | awk '$2=="refs/heads/main"{print $1}')"
  o="$(printf '%s\n' "$out" | awk -v t="refs/tags/$TAG" '$2==t{print $1}')"
  p="$(printf '%s\n' "$out" | awk -v t="refs/tags/$TAG^{}" '$2==t{print $1}')"
  printf '%s %s %s' "${m:--}" "${o:--}" "${p:--}"
}
is_ok() { local s; s="$(remote_state "$1")"; [ "$s" = "$SHA $TAGOBJ $SHA" ]; }

declare -A OK
for r in $REMOTES; do
  if is_ok "$r"; then OK[$r]=1; printf 'PUSH %s already OK (skipped)\n' "$r"; continue; fi
  errf="$(mktemp "${TMPDIR:-/tmp}/tar_push.XXXXXX")"
  if git push --atomic "$r" "$SHA:refs/heads/main" "refs/tags/$TAG:refs/tags/$TAG" 2>"$errf"; then
    printf 'PUSH %s atomic ok\n' "$r"
  elif grep -q 'does not support --atomic' "$errf"; then
    printf 'PUSH %s: server has no atomic push; main first, tag only after main reads back\n' "$r"
    if git push "$r" "$SHA:refs/heads/main" 2>>"$errf" && [ "$(remote_state "$r" | cut -d' ' -f1)" = "$SHA" ]; then
      git push "$r" "refs/tags/$TAG:refs/tags/$TAG" 2>>"$errf" || printf 'PUSH %s tag push failed\n' "$r"
    else
      printf 'PUSH %s main push failed; tag NOT pushed\n' "$r"
    fi
  else
    printf 'PUSH %s failed: %s\n' "$r" "$(tr '\n' ' ' <"$errf" | head -c 300)"
  fi
  rm -f -- "$errf"
done

printf '== ls-remote verify\n'
for r in $REMOTES; do
  s="$(remote_state "$r")"
  if [ "$s" = "$SHA $TAGOBJ $SHA" ]; then OK[$r]=1; printf 'VERIFY %s OK main=%s tag=%s\n' "$r" "$SHA" "$TAGOBJ"
  else unset 'OK[$r]'; fail "VERIFY $r MISMATCH main/tagobj/peeled=$s expected=$SHA/$TAGOBJ/$SHA"; fi
done

# ---------- platform releases (only for OK remotes) ----------
PRE_GH=() PRE_TITLE="$TITLE"
[ "$PRERELEASE" -eq 1 ] && PRE_GH=(--prerelease)
declare -A GH_SEEN
for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do
  kind="${spec%%:*}"; rest="${spec#*:}"; r="${rest%%:*}"; target="${rest#*:}"
  if [ -z "${OK[$r]:-}" ]; then fail "RELEASE $spec not attempted: remote $r is not OK"; continue; fi
  case "$kind" in
    github)
      if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then gap "RELEASE $spec SKIPPED-NO-TOKEN (gh not authenticated)"; continue; fi
      id="$(gh api "repos/$target" --jq .id 2>/dev/null)" || id=""
      if [ -z "$id" ]; then gap "RELEASE $spec NOT-ACCESSIBLE (gh api repos/$target failed; not released there)"; continue; fi
      if [ -n "${GH_SEEN[$id]:-}" ]; then printf 'RELEASE %s same repository id %s as %s (deduplicated)\n' "$spec" "$id" "${GH_SEEN[$id]}"; continue; fi
      GH_SEEN[$id]="$target"
      if gh release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s already exists (kept)\n' "$spec"; continue; fi
      if gh release create "$TAG" -R "$target" "${PRE_GH[@]+"${PRE_GH[@]}"}" --verify-tag --title "$PRE_TITLE" --notes-file "$NOTES" >/dev/null 2>&1 \
         && gh release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s CREATED\n' "$spec"
      else fail "RELEASE $spec create failed"; fi ;;
    gitlab)
      if ! command -v glab >/dev/null 2>&1 || ! glab auth status >/dev/null 2>&1; then gap "RELEASE $spec SKIPPED-NO-TOKEN (glab not authenticated)"; continue; fi
      if glab release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s already exists (kept)\n' "$spec"; continue; fi
      # --ref SHA: if the tag were somehow absent, glab would otherwise tag the default branch.
      if glab release create "$TAG" -R "$target" --ref "$SHA" --name "$PRE_TITLE" --notes-file "$NOTES" >/dev/null 2>&1 \
         && glab release view "$TAG" -R "$target" >/dev/null 2>&1; then printf 'RELEASE %s CREATED\n' "$spec"
      else fail "RELEASE $spec create failed"; fi ;;
    gitea)
      base="${target%:*}"; repo="${target##*:}"
      args=(--tag "$TAG" --notes-file "$NOTES" --title "$PRE_TITLE" --base-url "$base" --repo "$repo")
      [ "$PRERELEASE" -eq 1 ] && args+=(--prerelease)
      bash scripts/release_publish_gitea.sh "${args[@]}" >/dev/null 2>&1; rc=$?
      case "$rc" in
        0) printf 'RELEASE %s CREATED-OR-UPDATED\n' "$spec" ;;
        3) gap "RELEASE $spec SKIPPED-OR-REFUSED rc=3 (token absent or precondition)" ;;
        *) fail "RELEASE $spec failed rc=$rc" ;;
      esac ;;
  esac
done
for r in $REMOTES; do
  covered=0
  for spec in "${RELEASES[@]+"${RELEASES[@]}"}"; do rr="${spec#*:}"; [ "${rr%%:*}" = "$r" ] && covered=1; done
  [ "$covered" -eq 0 ] && printf 'INFO %s: tag pushed only (no platform release requested)\n' "$r"
done

printf '== %s end\n' "$(date -Is)"
if [ "$FAILS" -gt 0 ]; then printf 'RESULT: FAIL fails=%d gaps=%d (re-run the same command to resume)\n' "$FAILS" "$GAPS"; exit 1; fi
if [ "$GAPS" -gt 0 ]; then printf 'RESULT: GAPS fails=0 gaps=%d\n' "$GAPS"; exit 5; fi
printf 'RESULT: OK fails=0 gaps=0\n'; exit 0
