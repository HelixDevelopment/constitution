#!/usr/bin/env bash
# release_publish_gitea.sh — publish (create or update) a Gitea/Forgejo release
# for an existing git tag, through the Gitea REST API. Safe to re-run
# (last write wins for title, notes and the draft/prerelease flags).
#
# Why: GitHub and GitLab releases are cut with `gh` / `glab`; the m3w.org
# upstream runs Gitea, which has no such CLI on our hosts, so the API is used.
#
# Usage:
#   M3W_GITEA_TOKEN=... scripts/release_publish_gitea.sh --tag TAG \
#       [--notes-file FILE | --generic-notes] [--title TITLE] \
#       [--base-url URL] [--repo OWNER/REPO] [--token-var NAME] \
#       [--prerelease] [--draft] [--dry-run]
#
# Defaults: base URL https://git.m3w.org, repo Helix/constitution, title = TAG.
# Notes: the CHANGELOG.md section whose heading is exactly `## TAG` or
# `## [TAG]` (up to the next `## `). If no such section exists the script
# refuses (exit 3) unless --notes-file or --generic-notes is given; it never
# publishes an [Unreleased]/[vNEXT] section under a tag.
# The token is read from the environment ONLY (never argv, never printed),
# validated against a strict charset, kept out of child environments and sent
# via a 0600 curl config file; curl runs with -q (no ~/.curlrc), no redirects,
# and a protocol allow-list.
#
# Exit codes: 0 published/updated, 2 usage, 3 precondition missing or refused
# (token variable unset = SKIPPED-NO-TOKEN, bad token charset, tag not in local
# git, jq/curl missing, no matching changelog section), 4 API/network failure.
# A missing token is reported as SKIPPED-NO-TOKEN, never as success (§11.4.201).
set -u
set +x
LC_ALL=C; export LC_ALL

TAG="" NOTES_FILE="" TITLE="" BASE_URL="https://git.m3w.org" REPO="Helix/constitution"
PRERELEASE=false DRAFT=false DRY=0 TOKEN_VAR="M3W_GITEA_TOKEN" GENERIC=0

die() { local rc="$2"; printf 'release_publish_gitea: %s\n' "$1" >&2; exit "${rc:-2}"; }

need_val() { [ "$1" -ge 2 ] || die "option $2 needs a value" 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) need_val $# "$1"; TAG="$2"; shift 2 ;;
    --notes-file) need_val $# "$1"; NOTES_FILE="$2"; shift 2 ;;
    --title) need_val $# "$1"; TITLE="$2"; shift 2 ;;
    --base-url) need_val $# "$1"; BASE_URL="$2"; shift 2 ;;
    --repo) need_val $# "$1"; REPO="$2"; shift 2 ;;
    --token-var) need_val $# "$1"; TOKEN_VAR="$2"; shift 2 ;;
    --generic-notes) GENERIC=1; shift ;;
    --prerelease) PRERELEASE=true; shift ;;
    --draft) DRAFT=true; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" 2 ;;
  esac
done

[ -n "$TAG" ] || die "--tag is required" 2
printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die "tag has unsafe characters: refusing" 2
printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$' || die "repo must be OWNER/REPO" 2
case "$REPO" in *..*|./*|*/.|*/..) die "repo has dot segments: refusing" 2 ;; esac
printf '%s' "$TOKEN_VAR" | grep -Eq '^[A-Z_][A-Z0-9_]*$' || die "--token-var must be an env var NAME" 2
# https always; plain http only for an exact loopback host:port with nothing after it.
SCHEME_OK=0
if printf '%s' "$BASE_URL" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$'; then SCHEME_OK=1; PROTO='=https'
elif printf '%s' "$BASE_URL" | grep -Eq '^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}/?$'; then SCHEME_OK=1; PROTO='=http'; fi
[ "$SCHEME_OK" -eq 1 ] || die "base URL must be https://host[:port] (or http://127.0.0.1|localhost|[::1]:port for tests), no userinfo, no path" 2
BASE_URL="${BASE_URL%/}"
command -v jq >/dev/null 2>&1 || die "jq is required" 3
command -v curl >/dev/null 2>&1 || die "curl is required" 3
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 || die "tag $TAG does not exist in this repository" 3

# Read the token once, drop it from the environment so no child inherits it.
TOKEN="${!TOKEN_VAR:-}"
unset "$TOKEN_VAR" 2>/dev/null || true
if [ -z "$TOKEN" ] && [ "$DRY" -eq 0 ]; then
  printf 'SKIPPED-NO-TOKEN: env var %s is not set; nothing was published\n' "$TOKEN_VAR" >&2
  exit 3
fi
if [ -n "$TOKEN" ] && ! printf '%s' "$TOKEN" | grep -Eq '^[A-Za-z0-9._~+/=-]{8,200}$'; then
  die "token has characters outside [A-Za-z0-9._~+/=-] or a bad length: refusing" 3
fi

[ -n "$TITLE" ] || TITLE="$TAG"

W="$(mktemp -d "${TMPDIR:-/tmp}/rpg.XXXXXX")" || die "cannot create a temp dir" 3
: "${W:?}"
cleanup() { [ -n "${W:-}" ] && [ -d "$W" ] && { rm -f -- "$W/body.txt" "$W/payload.json" "$W/curl.cfg" "$W/resp.out" "$W/err.out"; rmdir -- "$W" 2>/dev/null; }; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM
chmod 700 "$W"

# Notes -> file (never through argv).
if [ -n "$NOTES_FILE" ]; then
  [ -r "$NOTES_FILE" ] || die "notes file not readable: $NOTES_FILE" 3
  cp -- "$NOTES_FILE" "$W/body.txt"
elif [ "$GENERIC" -eq 1 ]; then
  printf 'Release %s\n' "$TAG" > "$W/body.txt"
else
  [ -r CHANGELOG.md ] || die "CHANGELOG.md not found; use --notes-file or --generic-notes" 3
  TAG="$TAG" awk '
    BEGIN { t = ENVIRON["TAG"]; on = 0 }
    /^## / {
      if (on) exit
      h = substr($0, 4)
      if (h == t || index(h, t " ") == 1 || h == "[" t "]" || index(h, "[" t "] ") == 1) { on = 1 }
    }
    on { print }
  ' CHANGELOG.md > "$W/body.txt"
  [ -s "$W/body.txt" ] || die "no CHANGELOG.md section headed '## $TAG' or '## [$TAG]'; use --notes-file or --generic-notes" 3
fi

TARGET="$(git rev-list -n1 "refs/tags/$TAG")"
jq -n --arg t "$TAG" --arg n "$TITLE" --rawfile b "$W/body.txt" --arg c "$TARGET" \
  --argjson d "$DRAFT" --argjson p "$PRERELEASE" \
  '{tag_name:$t,name:$n,body:$b,target_commitish:$c,draft:$d,prerelease:$p}' > "$W/payload.json" \
  || die "could not build the payload" 3

if [ "$DRY" -eq 1 ]; then
  printf 'DRY-RUN: would publish %s on %s/%s (target %s, notes %s bytes)\n' "$TAG" "$BASE_URL" "$REPO" "$TARGET" "$(wc -c < "$W/body.txt")"
  exit 0
fi

# Token goes into a 0600 curl config file (never argv); the charset check above
# rules out quotes, backslashes and newlines, so the line cannot be broken out of.
( umask 077; printf 'header = "Authorization: token %s"\n' "$TOKEN" > "$W/curl.cfg" )
TOKEN=""

API_CODE="" API_BODY=""
api() { # method path [payload-file]
  local m="$1" p="$2" f="${3:-}"
  local args=(-q -sS -m 60 --max-redirs 0 --proto "$PROTO" -K "$W/curl.cfg" -X "$m" -o "$W/resp.out" -w '%{http_code}')
  [ -n "$f" ] && args+=(-H 'Content-Type: application/json' --data-binary "@$f")
  API_CODE="$(curl "${args[@]}" "$BASE_URL/api/v1/repos/$REPO$p" 2>"$W/err.out")" || {
    printf 'release_publish_gitea: network/request failure: %s\n' "$(tr -d '\r' < "$W/err.out" | head -c 300)" >&2
    return 1
  }
  API_BODY="$(cat "$W/resp.out" 2>/dev/null)"
}

update_release() { # id
  local id="$1"
  printf '%s' "$id" | grep -Eq '^[0-9]+$' || die "unexpected release id in API response" 4
  api PATCH "/releases/$id" "$W/payload.json" || exit 4
  [ "$API_CODE" = "200" ] || die "update failed: HTTP $API_CODE" 4
  printf 'UPDATED release %s (id %s) on %s/%s\n' "$TAG" "$id" "$BASE_URL" "$REPO"
}

api GET "/releases/tags/$TAG" || exit 4
case "$API_CODE" in
  200) update_release "$(printf '%s' "$API_BODY" | jq -r '.id // empty' 2>/dev/null)" ;;
  404)
    api POST "/releases" "$W/payload.json" || exit 4
    case "$API_CODE" in
      201) printf 'CREATED release %s (id %s) on %s/%s\n' "$TAG" "$(printf '%s' "$API_BODY" | jq -r '.id // "?"' 2>/dev/null)" "$BASE_URL" "$REPO" ;;
      409) # created concurrently or not visible to the tag lookup: re-read once and update
        api GET "/releases/tags/$TAG" || exit 4
        [ "$API_CODE" = "200" ] || die "release exists (409) but cannot be read back: HTTP $API_CODE" 4
        update_release "$(printf '%s' "$API_BODY" | jq -r '.id // empty' 2>/dev/null)" ;;
      *) die "create failed: HTTP $API_CODE" 4 ;;
    esac ;;
  401|403) die "authentication/permission failure: HTTP $API_CODE (token scope write:repository needed)" 4 ;;
  *) die "unexpected HTTP $API_CODE while looking up the release" 4 ;;
esac
