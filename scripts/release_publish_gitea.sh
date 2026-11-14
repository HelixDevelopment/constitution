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
# to curl on its standard input (-K -): it is never written to a file (round 5,
# J4); curl runs with -q (no ~/.curlrc), no redirects, a protocol allow-list, a
# connect timeout and a total timeout. curl's own stderr is never printed (it can
# carry a credential): a failure prints curl's exit status and one word of a
# closed set (scripts/release/redact_cut.sh rc_err_class, or "timeout").
#
# Exit codes: 0 published/updated, 2 usage, 3 precondition missing or refused
# (token variable unset = SKIPPED-NO-TOKEN, bad token charset, tag not in local
# git, jq/curl missing, no matching changelog section), 4 API/network failure.
# A missing token is reported as SKIPPED-NO-TOKEN, never as success (§11.4.201).
set +x   # first: an inherited xtrace (bash -x, SHELLOPTS=xtrace) traces this one line only
set -u
LC_ALL=C; export LC_ALL

TAG="" NOTES_FILE="" TITLE="" BASE_URL="https://git.m3w.org" REPO="Helix/constitution"
PRERELEASE=false DRAFT=false DRY=0 TOKEN_VAR="M3W_GITEA_TOKEN" GENERIC=0
HELP=0   # round 10 (R9-2): -h sets it; it is never taken from the caller

DIE_FD=2
die() { local rc="$2"; printf 'release_publish_gitea: %s\n' "$1" >&"$DIE_FD"; exit "${rc:-2}"; }
# the one redact-then-cut helper for external-command output (round 3, CON-234 n-4 class)
# shellcheck source=scripts/release/redact_cut.sh
_rc_d="${BASH_SOURCE[0]}"; case "$_rc_d" in */*) _rc_d="${_rc_d%/*}" ;; *) _rc_d=. ;; esac   # no external command before the lockdown (round 6)
. "$(cd "$_rc_d" && pwd)/release/redact_cut.sh" || die "cannot load release/redact_cut.sh" 3
# The token variable may be named by --token-var; it is looked up in the arguments the same way the argument loop
# below reads them (an option with a value takes the next word), so rc_env_clean carries that variable over (as a
# shell variable no child receives). An invalid name is carried as nothing and refused by the check after the loop.
_rpg_tv=M3W_GITEA_TOKEN; _rpg_a=("$@"); _rpg_i=0
while [ "$_rpg_i" -lt "${#_rpg_a[@]}" ]; do
  case "${_rpg_a[_rpg_i]}" in
    --token-var) _rpg_tv="${_rpg_a[_rpg_i+1]:-}"; _rpg_i=$((_rpg_i + 2)) ;;
    --tag|--notes-file|--title|--base-url|--repo) _rpg_i=$((_rpg_i + 2)) ;;
    *) _rpg_i=$((_rpg_i + 1)) ;;
  esac
done
[[ $_rpg_tv =~ ^[A-Z_][A-Z0-9_]*$ ]] || _rpg_tv=""
rc_env_clean "$_rpg_tv" "$@"; _rc=$?   # children get an environment built from the allow-list only (round 7, L1 L2; K3); this shell keeps the values
[ "$_rc" -ne 2 ] || die "--token-var names a variable that bash gives a meaning of its own: refusing" 2
[ "$_rc" -eq 0 ] || die "cannot build a clean environment for the child processes (rc_env_clean status $_rc; Linux /proc is required)" 3
unset -v _rpg_tv _rpg_a _rpg_i
rc_git_env   # no git trace anywhere, no terminal prompt, GIT_TRACE_REDACT=1

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
    -h|--help) HELP=1; shift ;;   # printed after the token is dropped (round 6: no external command before)
    *) if [[ $1 =~ ^--?[A-Za-z][A-Za-z0-9-]{0,40}$ ]]; then die "unknown argument: $1" 2
       else die "unknown argument (not shown: it is not shaped like an option)" 2; fi ;;
  esac
done

[[ $TOKEN_VAR =~ ^[A-Z_][A-Z0-9_]*$ ]] || die "--token-var must be an env var NAME" 2
# Read the token once, drop it from the environment so no child inherits it. The holding variable is unset
# first, so it is never exported (a caller's exported variable of the same name would otherwise keep its
# export attribute and hand the token to every child). Round 6 (X11): this runs right after the argument loop,
# before the first external command, because --token-var may name a variable on the rc_env_lockdown
# allow-list (GH_HOST, say), which the lockdown leaves exported.
unset -v _rpg_tok
_rpg_tok="${!TOKEN_VAR:-}"
unset -v "$TOKEN_VAR" 2>/dev/null || true
if [ "${HELP:-0}" -eq 1 ]; then sed -n '2,29p' "$0"; exit 0; fi
[ -n "$TAG" ] || die "--tag is required" 2
printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || die "tag has unsafe characters: refusing" 2
printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$' || die "repo must be OWNER/REPO" 2
case "$REPO" in *..*|./*|*/.) die "repo has dot segments: refusing" 2 ;; esac
# The URL must be exactly scheme://host[:port] (rc_safe_url: no userinfo, no path, no query; round 6, K4 wires
# the helper here), https always, plain http only for a loopback host with a port.
SCHEME_OK=0
if [ "$(rc_safe_url "$BASE_URL")" = "${BASE_URL%/}" ]; then
  case "$BASE_URL" in
    https://*) SCHEME_OK=1; PROTO='=https' ;;
    http://127.0.0.1:[0-9]*|http://localhost:[0-9]*|http://\[::1\]:[0-9]*) SCHEME_OK=1; PROTO='=http' ;;
  esac
fi
[ "$SCHEME_OK" -eq 1 ] || die "base URL must be https://host[:port] (or http://127.0.0.1|localhost|[::1]:port for tests), no userinfo, no path" 2
BASE_URL="${BASE_URL%/}"
command -v jq >/dev/null 2>&1 || die "jq is required" 3
command -v curl >/dev/null 2>&1 || die "curl is required" 3
rc_net git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 || die "tag $TAG does not exist in this repository" 3

if [ -z "$_rpg_tok" ] && [ "$DRY" -eq 0 ]; then
  printf 'SKIPPED-NO-TOKEN: env var %s is not set; nothing was published\n' "$TOKEN_VAR" >&2
  exit 3
fi
if [ -n "$_rpg_tok" ] && ! [[ $_rpg_tok =~ ^[A-Za-z0-9._~+/=-]{8,200}$ ]]; then
  die "token has characters outside [A-Za-z0-9._~+/=-] or a bad length: refusing" 3
fi

[ -n "$TITLE" ] || TITLE="$TAG"

W="$(mktemp -d "${TMPDIR:-/tmp}/rpg.XXXXXX")" || die "cannot create a temp dir" 3
: "${W:?}"
cleanup() { [ -n "${W:-}" ] && [ -d "$W" ] && { [ -f "$W/ext.err" ] && rc_redact_cut 2000 mark <"$W/ext.err" >&3; rm -f -- "$W/body.txt" "$W/payload.json" "$W/resp.out" "$W/code.out" "$W/ext.err"; rmdir -- "$W" 2>/dev/null; }; }
# every file of the run lives in the 0700 directory W; the signal traps end the run through the EXIT trap,
# so W is removed on SIGHUP, SIGINT and SIGTERM as well (round 4, H2); only SIGKILL leaves it behind
trap cleanup EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
chmod 700 "$W"
# stderr of every external command (git, jq, awk) that is not captured explicitly is collected and printed at
# exit through the helper (redacted, then cut); this script's own messages use fd 3 (round 3, G1 class)
exec 3>&2 2>"$W/ext.err"; DIE_FD=3

# Notes -> file (never through argv).
if [ -n "$NOTES_FILE" ]; then
  [ -r "$NOTES_FILE" ] || die "notes file is not readable (the path is not shown)" 3
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

TARGET="$(rc_net git rev-list -n1 "refs/tags/$TAG")"
jq -n --arg t "$TAG" --arg n "$TITLE" --rawfile b "$W/body.txt" --arg c "$TARGET" \
  --argjson d "$DRAFT" --argjson p "$PRERELEASE" \
  '{tag_name:$t,name:$n,body:$b,target_commitish:$c,draft:$d,prerelease:$p}' > "$W/payload.json" \
  || die "could not build the payload" 3

if [ "$DRY" -eq 1 ]; then
  printf 'DRY-RUN: would publish %s on %s/%s (target %s, notes %s bytes)\n' "$TAG" "$BASE_URL" "$REPO" "$TARGET" "$(wc -c < "$W/body.txt")"
  exit 0
fi

# The token reaches curl as a config line on curl's standard input (-K -): printf is a shell builtin, so the
# token is in no argv and in no file; the charset check above rules out quotes, backslashes and newlines, so
# the line cannot be broken out of. curl's stderr is captured into a variable and only classified.
API_CODE="" API_BODY=""
api() { # method path [payload-file]
  local m="$1" p="$2" f="${3:-}" x_curl crc cls
  local args=(-q -sS -m 60 --connect-timeout 20 --max-redirs 0 --proto "$PROTO" -K - -X "$m" -o "$W/resp.out" -w '%{http_code}')
  [ -n "$f" ] && args+=(-H 'Content-Type: application/json' --data-binary "@$f")
  : >"$W/code.out"
  x_curl="$(printf 'header = "Authorization: token %s"\n' "$_rpg_tok" | rc_net curl "${args[@]}" "$BASE_URL/api/v1/repos/$REPO$p" 2>&1 >"$W/code.out")"; crc=$?
  if [ "$crc" -ne 0 ]; then
    if [ "$crc" -eq 28 ]; then cls=timeout; else cls="$(printf '%s' "$x_curl" | rc_err_class)"; fi
    printf 'release_publish_gitea: network/request failure (curl exit %s, reason class: %s; curl'"'"'s own message is withheld (it can carry a credential))\n' "$crc" "$cls" >&3
    return 1
  fi
  API_CODE="$(cat "$W/code.out" 2>/dev/null)"
  # the HTTP status is printed in messages below, so it must be the three digits it claims to be
  [[ $API_CODE =~ ^[0-9]{3}$ ]] || { printf 'release_publish_gitea: the HTTP status curl reported is not a number (not shown)\n' >&3; return 1; }
  API_BODY="$(cat "$W/resp.out" 2>/dev/null)"
}

update_release() { # id
  local id="$1"
  [[ $id =~ ^[0-9]{1,20}$ ]] || die "unexpected release id in API response (not shown)" 4   # one line of digits (X6)
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
      201) NEWID="$(printf '%s' "$API_BODY" | jq -r '.id // empty' 2>/dev/null)"
           # a server-returned value is printed only when it is the number it must be (round 4, I-4)
           [[ $NEWID =~ ^[0-9]{1,20}$ ]] || die "release created but the API returned no numeric id; check it on $BASE_URL/$REPO" 4
           printf 'CREATED release %s (id %s) on %s/%s\n' "$TAG" "$NEWID" "$BASE_URL" "$REPO" ;;
      409) # created concurrently or not visible to the tag lookup: re-read once and update
        api GET "/releases/tags/$TAG" || exit 4
        [ "$API_CODE" = "200" ] || die "release exists (409) but cannot be read back: HTTP $API_CODE" 4
        update_release "$(printf '%s' "$API_BODY" | jq -r '.id // empty' 2>/dev/null)" ;;
      *) die "create failed: HTTP $API_CODE" 4 ;;
    esac ;;
  401|403) die "authentication/permission failure: HTTP $API_CODE (token scope write:repository needed)" 4 ;;
  *) die "unexpected HTTP $API_CODE while looking up the release" 4 ;;
esac
