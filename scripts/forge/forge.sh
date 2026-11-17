#!/usr/bin/env bash
# scripts/forge/forge.sh -- one entry point for the release APIs of every forge this project pushes to
# (GitHub, GitLab, Gitea/Forgejo: m3w and Codeberg, GitFlic, GitVerse), REST over curl, API keys only.
# Full guide: docs/guides/multiforge_release_guide.md; manual: docs/manuals/forge_tool_manual.md.
#
# Usage:
#   forge.sh detect         (--remote NAME | --url URL)                 provider, host, repo, API base (no network)
#   forge.sh probe          (--remote NAME | --url URL)                 read-only GETs; HTTP status + JSON key names only
#   forge.sh repo-exists    (--remote NAME | --url URL)
#   forge.sh release-get    (--remote NAME | --url URL) --tag TAG
#   forge.sh tag-get        (--remote NAME | --url URL) --tag TAG       the tag's commit as the API reports it
#   forge.sh release-ensure (--remote NAME | --url URL) --tag TAG --sha SHA40 --notes-file FILE
#                           [--title T] [--prerelease] [--update] [--dry-run]
#                           [--enable-releases] [--try-create-on-ambiguous]
#
# release-ensure is idempotent: the tag must already be on the forge (tags arrive by git push; this tool
# never creates, moves or deletes a tag or a release, never pushes, never forces). An absent release is
# created and then READ BACK (tag, prerelease where the forge has the flag, target where it reports a commit);
# a present release that matches is kept; one that differs is a FAIL unless --update (then PATCH/PUT and
# read back). It ends OK only when the COMMIT was checked BEFORE any write: the tag's commit as the forge
# reports it equals --sha, or (GitLab only) a release already present reports the commit the forge derives
# from the tag. A target_commitish read back is the value the tool (or someone) sent, never proof. Otherwise
# the run ends "RESULT: UNVERIFIED-COMMIT" (exit 5, REASON commit_unverified), in a real run and a dry-run
# alike: the release may exist, but the tool could not prove which commit it is on. The notes file is refused when it is the keys file or the .env
# (notes_is_credentials_file) or when its text, or the title, contains a candidate token value
# (notes_contain_token / title_contains_token); the scanned copy is what is sent. --enable-releases: on a Gitea/Forgejo repository whose Releases unit is off (Codeberg), make
# the ONE reversible settings change PATCH /repos/{o}/{r} {"has_releases":true}, logged, then read back.
# --try-create-on-ambiguous: on GitVerse, whose release list answers 404 for an existing repository, try the
# create; only the read-back decides. --dry-run: GETs only, prints what it would do.
#
# Hosts map (DATA, a trust boundary: it decides which origin receives which token variable):
# FORGE_HOSTS_FILE, default config/forge/hosts.tsv; it must be a regular file (no symlink) owned by this
# user or root and not writable by others (hosts_file_insecure). Token: the names that map lists for the
# host, looked up in the environment, then FORGE_KEYS_FILE (default ~/api_keys.sh, must be mode 0600),
# then FORGE_ENV_FILE (default <repository root>/.env, parsed, never executed, and only when forge.sh lies
# inside that repository; otherwise "NOTE dotenv_not_trusted"). Reads run unauthenticated
# when no token is found ("AUTH: none"); writes need one (GAP credentials_absent:<names>).
#
# Output: KEY: value lines on stdout, messages "forge: ..." on stderr, last line "RESULT: <WORD>", before it
# "REASON: <code>" when there is one. Exit: 0 OK, 1 FAIL (read-back or state mismatch), 2 USAGE (also a bad
# hosts file: hosts_file_invalid / hosts_file_insecure, and a refused notes file), 5 UNVERIFIED-COMMIT
# (commit_unverified, release-ensure only), 129/130/143 INTERRUPTED (a signal; REASON interrupted),
# 3 GAP (credentials_absent:<vars>, credentials_invalid:<var>, unknown_forge, not_accessible,
# releases_disabled, releases_unsupported_or_empty, tag_absent_on_forge, readback_page_cap),
# 4 API (auth_failed, redirect_refused, unexpected_status_<code>, network_<class>).
# Credential rules: lib/common.sh (clean re-exec), lib/credentials.sh, lib/http.sh. No token is ever in an
# argv, a URL, a child environment, a file or a message.
set +x   # first: an inherited xtrace traces this one line only
set +a
set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
_fg_d="${BASH_SOURCE[0]}"; case "$_fg_d" in */*) _fg_d="${_fg_d%/*}" ;; *) _fg_d=. ;; esac
# shellcheck source=scripts/forge/lib/common.sh
. "$_fg_d/lib/common.sh" || { printf 'forge: cannot load lib/common.sh\nRESULT: USAGE\n'; exit 2; }
fg_env_clean "$@"; _fg_rc=$?
case "$_fg_rc" in
  0) ;;
  3) fg_msg "/proc/\$\$/environ is not readable: the child environment cannot be checked (Linux /proc required)"; fg_end GAP 3 environment_unverifiable ;;
  *) fg_msg "cannot build a clean environment for the child processes (status $_fg_rc)"; fg_end GAP 3 environment_unverifiable ;;
esac
set +x +a
FG_DIR="$(cd "$_fg_d" && pwd)"
# the signal traps come FIRST (review finding R2-m2): a signal during the slow reads below (the keys file is
# sourced in a child, up to FORGE_KEYS_TIMEOUT seconds) still ends with REASON and RESULT lines, never silent.
# fg_interrupted is defined in lib/http.sh; until it is loaded this small handler does the same.
# shellcheck disable=SC2329  # invoked by the traps below
_fg_early_int() { trap - HUP INT TERM; printf 'forge: interrupted by a signal\n' >&2; printf 'REASON: interrupted\nRESULT: INTERRUPTED\n'; exit "$1"; }
trap '_fg_early_int 129' HUP; trap '_fg_early_int 130' INT; trap '_fg_early_int 143' TERM
FG_DIR_PHYS="$(cd "$_fg_d" && pwd -P)"
# shellcheck source=scripts/forge/lib/credentials.sh
. "$FG_DIR/lib/credentials.sh" || fg_end USAGE 2 install_broken
# shellcheck source=scripts/forge/lib/http.sh
. "$FG_DIR/lib/http.sh" || fg_end USAGE 2 install_broken

CMD="${1:-}"; [ $# -gt 0 ] && shift
REMOTE="" URL="" TAG="" SHA="" NOTES="" TITLE="" PRE=false UPDATE=0 DRY=0 ENABLE=0 TRYAMB=0
need() { [ "$1" -ge 2 ] || fg_usage_err "option $2 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --remote) need $# "$1"; REMOTE="$2"; shift 2 ;;
    --url) need $# "$1"; URL="$2"; shift 2 ;;
    --tag) need $# "$1"; TAG="$2"; shift 2 ;;
    --sha) need $# "$1"; SHA="$2"; shift 2 ;;
    --notes-file) need $# "$1"; NOTES="$2"; shift 2 ;;
    --title) need $# "$1"; TITLE="$2"; shift 2 ;;
    --prerelease) PRE=true; shift ;;
    --update) UPDATE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --enable-releases) ENABLE=1; shift ;;
    --try-create-on-ambiguous) TRYAMB=1; shift ;;
    --asset) fg_usage_err "--asset is not implemented yet (release assets are a later phase)" not_implemented ;;
    -h|--help) sed -n '2,47p' "$0"; exit 0 ;;
    *) if [[ $1 =~ ^--?[A-Za-z][A-Za-z0-9-]{0,40}$ ]]; then fg_usage_err "unknown option: $1"
       else fg_usage_err "unknown argument (not shown: it is not shaped like an option)"; fi ;;
  esac
done
case "$CMD" in
  detect|probe|repo-exists|release-get|tag-get|release-ensure) ;;
  -h|--help) sed -n '2,47p' "$0"; exit 0 ;;
  "") fg_usage_err "a command is required (detect, probe, repo-exists, release-get, tag-get, release-ensure)" ;;
  *) fg_usage_err "unknown command (see --help)" ;;
esac

# ---- hosts map -------------------------------------------------------------------------------------------
FG_HOSTS_FILE="${FORGE_HOSTS_FILE:-$FG_DIR/../../config/forge/hosts.tsv}"
FG_PROVIDER="" FG_API_BASE="" FG_TOKEN_VARS="" FG_ALL_TOKEN_VARS=""
_fg_api_base_ok() {
  local o
  o="$(fg_origin "$1")" || return 1
  [[ ${1#"$o"} =~ ^(/[A-Za-z0-9._-]+)*$ ]] || return 1
  case "$o" in https://*) return 0 ;; esac
  [ "${FORGE_TEST_ALLOW_HTTP_LOOPBACK:-0}" = 1 ] && fg_origin_is_loopback "$o" && return 0
  return 1
}
fg_hosts_load() { # HOST: validate the WHOLE map, then select the row of HOST
  local h p a t _note line n=0 seen=" " v mode owner dir dmode downer
  [ -f "$FG_HOSTS_FILE" ] && [ -r "$FG_HOSTS_FILE" ] || fg_usage_err "hosts map not readable" hosts_file_invalid
  # the map decides where tokens go: a symlink, a file of another user, or one others can write is refused
  [ ! -L "$FG_HOSTS_FILE" ] || fg_usage_err "hosts map is a symlink: refused" hosts_file_insecure
  mode="$(stat -c '%a' -- "$FG_HOSTS_FILE" 2>/dev/null)"; owner="$(stat -c '%u' -- "$FG_HOSTS_FILE" 2>/dev/null)"
  [[ $mode =~ ^[0-7]+$ ]] && [ $(( 8#$mode & 8#002 )) -eq 0 ] || fg_usage_err "hosts map is writable by others: refused" hosts_file_insecure
  { [ "$owner" = "$(id -u)" ] || [ "$owner" = 0 ]; } || fg_usage_err "hosts map is owned by another user: refused" hosts_file_insecure
  # its directory too (review finding R2-m5): another user who can write the directory can replace the file.
  # Allowed: a directory of this user or root, not writable by others, or writable by others with the sticky
  # bit (/tmp style: nobody can replace a file of another user there).
  case "$FG_HOSTS_FILE" in */*) dir="${FG_HOSTS_FILE%/*}"; dir="${dir:-/}" ;; *) dir=. ;; esac
  dmode="$(stat -c '%a' -- "$dir" 2>/dev/null)"; downer="$(stat -c '%u' -- "$dir" 2>/dev/null)"
  [[ $dmode =~ ^[0-7]+$ ]] || fg_usage_err "hosts map directory cannot be checked: refused" hosts_file_insecure
  { [ "$downer" = "$(id -u)" ] || [ "$downer" = 0 ]; } || fg_usage_err "hosts map directory is owned by another user: refused" hosts_file_insecure
  [ $(( 8#$dmode & 8#002 )) -eq 0 ] || [ $(( 8#$dmode & 8#1000 )) -ne 0 ] || fg_usage_err "hosts map directory is writable by others: refused" hosts_file_insecure
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in ''|'#'*) continue ;; esac
    IFS=$'\t' read -r h p a t _note <<<"$line"
    h="${h,,}"
    [[ $h =~ ^[a-z0-9][a-z0-9.-]{0,252}$ ]] || fg_usage_err "hosts map line $n: bad host" hosts_file_invalid
    case "$p" in github|gitlab|gitea|gitflic|gitverse) ;; *) fg_usage_err "hosts map line $n: unknown provider" hosts_file_invalid ;; esac
    _fg_api_base_ok "${a:-}" || fg_usage_err "hosts map line $n: the API base must be https://host[:port][/path] (no userinfo)" hosts_file_invalid
    [ -n "${t:-}" ] || fg_usage_err "hosts map line $n: no token variable" hosts_file_invalid
    for v in ${t//,/ }; do fg_ok_varname "$v" || fg_usage_err "hosts map line $n: token variable names must match [A-Z][A-Z0-9_]*TOKEN" hosts_file_invalid; done
    FG_ALL_TOKEN_VARS="${FG_ALL_TOKEN_VARS:+$FG_ALL_TOKEN_VARS,}$t"
    case "$seen" in *" $h "*) fg_usage_err "hosts map line $n: duplicate host" hosts_file_invalid ;; esac
    seen="$seen$h "
    if [ "$h" = "$1" ]; then FG_PROVIDER="$p" FG_API_BASE="${a%/}" FG_TOKEN_VARS="$t"; fi
  done <"$FG_HOSTS_FILE"
  return 0
}

# ---- remote URL -> host + path ---------------------------------------------------------------------------
fg_parse_url() { # URL: sets FG_HOST FG_PATH or ends the run (the URL itself is never printed)
  local u="$1" rest auth ui hp
  case "$u" in
    ssh://*)
      rest="${u#ssh://}"; auth="${rest%%/*}"; [ "$rest" != "$auth" ] || fg_usage_err "remote URL has no path"
      FG_PATH="${rest#*/}"
      case "$auth" in *@*) ui="${auth%@*}"; hp="${auth##*@}"; case "$ui" in *:*|*%*) fg_usage_err "remote URL carries a password: refused (not shown)" ;; esac ;; *) hp="$auth" ;; esac
      FG_HOST="${hp%%:*}"
      [ "$hp" = "$FG_HOST" ] || fg_ok_port "${hp#*:}" || fg_usage_err "remote URL has a bad port" ;;
    https://*)
      rest="${u#https://}"; auth="${rest%%/*}"; [ "$rest" != "$auth" ] || fg_usage_err "remote URL has no path"
      case "$auth" in *@*) fg_usage_err "https remote URL carries userinfo: refused (not shown)" ;; esac
      FG_PATH="${rest#*/}"; FG_HOST="${auth%%:*}"
      [ "$auth" = "$FG_HOST" ] || fg_ok_port "${auth#*:}" || fg_usage_err "remote URL has a bad port" ;;
    *://*) fg_usage_err "remote URL scheme not supported (ssh://, https:// or scp form git@host:path)" ;;
    *)
      if [[ $u =~ ^([A-Za-z0-9._-]+@)?([A-Za-z0-9.-]+):([^/].*|/.+)$ ]]; then
        FG_HOST="${BASH_REMATCH[2]}"; FG_PATH="${BASH_REMATCH[3]#/}"
      else fg_usage_err "remote URL not understood (not shown)"; fi ;;
  esac
  FG_HOST="${FG_HOST,,}"
  [[ $FG_HOST =~ ^[a-z0-9][a-z0-9.-]{0,252}$ ]] || fg_usage_err "remote URL has a bad host"
  FG_PATH="${FG_PATH%/}"; FG_PATH="${FG_PATH%.git}"
}

fg_split_repo() { # sets FG_OWNER FG_REPO FG_REPO_FULL from FG_PATH, per provider
  local IFS=/ segs s
  read -r -a segs <<<"$FG_PATH"
  for s in "${segs[@]}"; do fg_ok_segment "$s" || fg_usage_err "remote URL path has an unsafe segment (not shown)"; done
  [ "${#segs[@]}" -ge 2 ] || fg_usage_err "remote URL path must be OWNER/REPO"
  if [ "$FG_PROVIDER" != gitlab ] && [ "${#segs[@]}" -ne 2 ]; then fg_usage_err "remote URL path must be exactly OWNER/REPO on $FG_PROVIDER"; fi
  [ "${#segs[@]}" -le 20 ] || fg_usage_err "remote URL path too deep"
  # shellcheck disable=SC2034   # FG_OWNER and FG_REPO are read by the sourced providers
  FG_OWNER="${segs[0]}"
  # shellcheck disable=SC2034
  FG_REPO="${segs[${#segs[@]}-1]}"
  FG_REPO_FULL="$FG_PATH"
}

if [ -n "$REMOTE" ] && [ -n "$URL" ]; then fg_usage_err "give --remote or --url, not both"; fi
if [ -n "$REMOTE" ]; then
  [[ $REMOTE =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || fg_usage_err "remote name has unsafe characters"
  URL="$(git remote get-url "$REMOTE" 2>/dev/null)" || fg_usage_err "no such git remote in this repository"
fi
[ -n "$URL" ] || fg_usage_err "--remote NAME or --url URL is required"
fg_parse_url "$URL"
fg_hosts_load "$FG_HOST"
[ -n "$FG_PROVIDER" ] || fg_gap unknown_forge "no row for this host in the hosts map (config/forge/hosts.tsv); nothing is guessed"
fg_split_repo
FG_API_ORIGIN="$(fg_origin "$FG_API_BASE")"
FG_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || FG_REPO_ROOT=""

if [ "$CMD" = detect ]; then
  fg_line "PROVIDER: $FG_PROVIDER"; fg_line "HOST: $FG_HOST"; fg_line "REPO: $FG_REPO_FULL"
  fg_line "API: $FG_API_BASE"; fg_line "TOKEN_VARS: $FG_TOKEN_VARS"
  fg_end OK 0
fi

# ---- arguments of the network commands ----------------------------------------------------------------------
case "$CMD" in release-get|tag-get|release-ensure)
  [ -n "$TAG" ] || fg_usage_err "--tag is required"
  fg_ok_tag "$TAG" || fg_usage_err "tag has unsafe characters: refused" ;;
esac
if [ "$CMD" = release-ensure ]; then
  fg_ok_sha "$SHA" || fg_usage_err "--sha must be a full 40-character lower-case commit id"
  [ -n "$NOTES" ] || fg_usage_err "--notes-file is required"
  [ -r "$NOTES" ] && [ ! -d "$NOTES" ] || fg_usage_err "notes file is not readable (the path is not shown)"
  # a FIFO, a socket or a device could block the read or never end (review findings R2-m6 and round 2 minor):
  # only a regular file, or exactly /dev/null (empty notes, used by scripts that publish no text), is read
  [ -f "$NOTES" ] || [ "$NOTES" = /dev/null ] || fg_usage_err "notes file is not a regular file (FIFO, device or socket): refused" notes_not_regular
  [ -n "$TITLE" ] || TITLE="$TAG"
  [ "${#TITLE}" -le 200 ] || fg_usage_err "--title longer than 200 characters"
fi
command -v curl >/dev/null 2>&1 || fg_gap tool_missing "curl is required"
command -v jq >/dev/null 2>&1 || fg_gap tool_missing "jq is required"
command -v timeout >/dev/null 2>&1 || fg_gap tool_missing "timeout (coreutils) is required"

# ---- token -------------------------------------------------------------------------------------------------
# shellcheck disable=SC2086   # the comma list is split on purpose
fg_token_resolve ${FG_TOKEN_VARS//,/ }
case "$FG_TOKEN_STATE" in
  found) fg_line "AUTH: $FG_TOKEN_SOURCE:$FG_TOKEN_NAME" ;;
  invalid) fg_gap "credentials_invalid:$FG_TOKEN_BAD" "the token variable holds characters outside [A-Za-z0-9._~+/=-] or has a bad length; it is never sent" ;;
  *) if [ "$CMD" = release-ensure ]; then
       fg_gap "credentials_absent:$FG_TOKEN_VARS" "no usable token in the environment, the keys file or the project .env (names: $FG_TOKEN_VARS)"
     fi
     fg_line "AUTH: none" ;;
esac

# every candidate token value the tool can know of (all hosts, all sources): the notes scan and the output
# sanitiser of lib/common.sh use this set (review findings R2-I2 and R2-m1)
fg_secrets_load; _fg_sec_rc=$?
[ "$_fg_sec_rc" -eq 0 ] || [ "$CMD" = release-ensure ] || fg_msg "WARNING keys_file_incomplete: the keys file could not be read to its end; output is checked against the values that were read"
fg_tmp_init || fg_gap tmp_unavailable "cannot create a private temporary directory"

# ---- notes and title of release-ensure: never publish a credential -------------------------------------
if [ "$CMD" = release-ensure ]; then
  fg_is_credential_file "$NOTES" && fg_usage_err "the notes file is the keys file or the .env (same file): refused, it would publish credentials" notes_is_credentials_file
  [ "$_fg_sec_rc" -eq 0 ] || fg_gap keys_file_unreadable "the keys file could not be read to its end (timeout or failure): the notes cannot be checked against every token value; nothing is published"
  # the bytes are COUNTED while reading (never the size stat reports): at most FG_NOTES_MAX + 1 bytes are read
  FG_NOTES_MAX=1000000
  NOTES_TEXT="$(head -c "$((FG_NOTES_MAX + 1))" -- "$NOTES" 2>/dev/null; printf x)" || fg_usage_err "notes file is not readable (the path is not shown)"
  NOTES_TEXT="${NOTES_TEXT%x}"
  [ "${#NOTES_TEXT}" -le "$FG_NOTES_MAX" ] || { NOTES_TEXT=""; fg_usage_err "notes file larger than $FG_NOTES_MAX bytes" notes_too_large; }
  if fg_text_has_secret "$NOTES_TEXT"; then
    NOTES_TEXT=""; fg_usage_err "the notes text contains the value of $FG_SECRET_NAME: refused (value not shown)" notes_contain_token
  fi
  fg_text_has_secret "$TITLE" && fg_usage_err "the title contains the value of $FG_SECRET_NAME: refused (value not shown)" title_contains_token
  # what was scanned is what is sent (a later change of the notes file cannot slip a token in)
  ( umask 077; printf '%s' "$NOTES_TEXT" >"$FG_TMP/notes.txt" ) || fg_gap tmp_unavailable "cannot write the private copy of the notes"
  NOTES="$FG_TMP/notes.txt"; NOTES_TEXT=""
fi
# shellcheck source=/dev/null
. "$FG_DIR/providers/$FG_PROVIDER.sh" || fg_end USAGE 2 install_broken
prov_init
fg_line "PROVIDER: $FG_PROVIDER"; fg_line "REPO: $FG_REPO_FULL"

# shellcheck disable=SC2329  # called by the providers (prov_probe), which shellcheck does not follow
fg_probe_get() { # NAME URL: one read-only GET, prints status and key names
  if fg_http_url GET "$2"; then fg_line "PROBE: $1 status=$FG_CODE $(fg_peer_fields) $(fg_keys_summary)"
  else fg_line "PROBE: $1 no-answer class=$FG_NET"; fi
}

# fg_need_repo: the repository must answer 200 (after the provider's own canonicalisation)
fg_need_repo() {
  prov_repo || fg_net_end
  case "$FG_CODE" in
    200) return 0 ;;
    401|403) fg_api_err auth_failed "the forge refused the request (HTTP $FG_CODE): token missing, wrong or without scope" ;;
    404) fg_gap not_accessible "repository not found or not visible with this token (HTTP 404)" ;;
    3??) fg_api_err redirect_refused "the forge answered a redirect (HTTP $FG_CODE); redirects are never followed" ;;
    *) fg_api_err "unexpected_status_$FG_CODE" "unexpected HTTP $FG_CODE for the repository" ;;
  esac
}

# fg_ok_rel_id ID: a release id that may reach a URL path. GitLab addresses a release by its TAG (dots allowed,
# still no "/" and no ".."); every other forge by a numeric id or a UUID.
fg_ok_rel_id() { fg_ok_id "$1" || { [ "$FG_PROVIDER" = gitlab ] && fg_ok_tag "$1"; }; }

fg_rel_line() {
  local id="$FG_REL_ID" tgt="$FG_REL_TARGET"
  fg_ok_rel_id "$id" || id=invalid
  fg_ok_sha "$tgt" || tgt=unknown
  fg_line "RELEASE: present id=$id prerelease=$FG_REL_PRE draft=$FG_REL_DRAFT tag_ok=$([ "$FG_REL_TAG" = "$TAG" ] && echo yes || echo no) target=$tgt"
}

fg_release_get_or_end() {
  prov_release_get "$TAG" || fg_net_end
  case "$FG_REL_STATE" in
    present|absent) return 0 ;;
    gap) return 0 ;;
    *) case "$FG_CODE" in
         401|403) fg_api_err auth_failed "the forge refused the release lookup (HTTP $FG_CODE)" ;;
         3??) fg_api_err redirect_refused "redirect on the release lookup (HTTP $FG_CODE); never followed" ;;
         *) fg_api_err "unexpected_status_$FG_CODE" "unexpected HTTP $FG_CODE on the release lookup" ;;
       esac ;;
  esac
}

case "$CMD" in
  probe)
    prov_repo || true
    [ "$FG_CODE" = 200 ] || fg_line "NOTE: repository answered status=${FG_CODE:-none}"
    prov_probe
    fg_end OK 0 ;;
  repo-exists)
    fg_need_repo; fg_line "REPO_STATE: exists"; fg_end OK 0 ;;
  tag-get)
    fg_need_repo
    prov_tag_get "$TAG" || fg_net_end
    case "$FG_TAG_STATE" in
      present) if fg_ok_sha "$FG_TAG_SHA"; then fg_line "TAG: present sha=$FG_TAG_SHA"; else fg_line "TAG: present sha=unknown"; fi; fg_end OK 0 ;;
      absent) fg_line "TAG: absent"; fg_end OK 0 ;;
      unknown) fg_gap readback_page_cap "the tag list was not searched to its end (page cap)" ;;
      *) fg_api_err "unexpected_status_$FG_CODE" "unexpected HTTP $FG_CODE on the tag lookup" ;;
    esac ;;
  release-get)
    fg_need_repo
    fg_release_get_or_end
    case "$FG_REL_STATE" in
      present) fg_rel_line; fg_end OK 0 ;;
      absent) fg_line "RELEASE: absent"; fg_end OK 0 ;;
      gap) fg_gap "$FG_REL_GAP" ;;
    esac ;;
esac

# fg_end_ensure: the end of EVERY release-ensure path that does not fail (the only "fg_end OK" of
# release-ensure; tests/forge/test_forge_gitverse.sh S1 checks that structurally). OK needs FG_COMMIT_OK=1,
# and FG_COMMIT_OK is decided BEFORE the first write, from read-only state only (review finding R2-I1):
#   (a) the tag's commit as the forge reports it equals --sha (FG_TAG_OK), or
#   (b) a release that was ALREADY present reports a target that the forge DERIVES from the tag
#       (FG_TARGET_DERIVED=1: GitLab commit.id) and that target equals --sha.
# A target the tool itself sent (Gitea, GitHub, GitVerse target_commitish; GitFlic commitId, UNCONFIRMED) never
# counts: reading back our own value proves nothing about where the tag points. Because the verdict is fixed
# before any write, a dry-run and a real run of the same state end the same way (except where the real write
# itself fails). Otherwise UNVERIFIED-COMMIT (exit 5), never OK.
fg_end_ensure() {
  if [ "$FG_COMMIT_OK" = 1 ]; then fg_end OK 0; fi
  fg_msg "the tag's commit was not verified, and no release target derived from the tag was read before any write: the release is not proven to be on --sha"
  fg_end UNVERIFIED-COMMIT 5 commit_unverified
}

# ---- release-ensure ----------------------------------------------------------------------------------------
fg_need_repo
prov_tag_get "$TAG" || fg_net_end
FG_TAG_OK=0 FG_TARGET_OK=0 FG_COMMIT_OK=0 FG_WROTE=0
case "$FG_TAG_STATE" in
  present) if fg_ok_sha "$FG_TAG_SHA"; then
             [ "$FG_TAG_SHA" = "$SHA" ] || fg_fail tag_sha_mismatch "the tag on the forge points at another commit than --sha"
             FG_TAG_OK=1 FG_COMMIT_OK=1
             fg_line "TAG: present sha=$FG_TAG_SHA"
           else fg_line "NOTE: tag_sha_unverified (the forge did not report the tag's commit)"; fi ;;
  absent) fg_gap tag_absent_on_forge "the tag is not on the forge; push it first (this tool never creates tags)" ;;
  unknown) fg_gap readback_page_cap "the tag list was not searched to its end (page cap)" ;;
  *) fg_api_err "unexpected_status_$FG_CODE" "unexpected HTTP $FG_CODE on the tag lookup" ;;
esac
[ "$FG_PRE_SUPPORTED" = 1 ] || [ "$PRE" = false ] || fg_line "NOTE: prerelease_unsupported ($FG_PROVIDER has no pre-release flag; the release is not marked pre-release)"

fg_release_get_or_end
if [ "$FG_REL_STATE" = gap ] && [ "$FG_REL_GAP" = releases_disabled ]; then
  [ "$ENABLE" -eq 1 ] || fg_gap releases_disabled "the repository's Releases unit is off; enable it (repo settings) or re-run with --enable-releases"
  if [ "$DRY" -eq 1 ]; then fg_line "ACTION: would-enable-releases"; fg_line "ACTION: would-create"; fg_end_ensure; fi
  fg_msg "NOTICE: enabling the Releases unit of $FG_REPO_FULL (PATCH has_releases=true, reversible in the repository settings)"
  FG_WROTE=1
  prov_enable_releases || fg_net_end
  [ "${FG_ENABLE:-}" = enabled ] || fg_fail enable_releases_not_confirmed "the settings change was not confirmed by a read-back (has_releases still not true)"
  fg_line "ACTION: releases-enabled"
  fg_release_get_or_end
fi


fg_matches() { # status 0 when the present release matches what is wanted (prints notes for unknowns)
  local ok=0
  FG_TARGET_OK=0
  [ "$FG_REL_TAG" = "$TAG" ] || ok=1
  case "$FG_REL_DRAFT" in
    true) ok=1 ;;
    false) ;;
    *) fg_line "NOTE: draft_unverified (the forge did not report the draft flag)" ;;
  esac
  if [ "$FG_PRE_SUPPORTED" = 1 ]; then
    case "$FG_REL_PRE" in
      true|false) [ "$FG_REL_PRE" = "$PRE" ] || ok=1 ;;
      *) fg_line "NOTE: prerelease_unverified (the forge did not report the flag)" ;;
    esac
  fi
  if fg_ok_sha "$FG_REL_TARGET"; then
    if [ "$FG_REL_TARGET" != "$SHA" ]; then ok=1
    elif [ "$FG_TARGET_DERIVED" = 1 ]; then FG_TARGET_OK=1
    elif [ "$FG_TAG_OK" != 1 ]; then fg_line "NOTE: target_echo_only (the release target equals --sha, but $FG_PROVIDER stores the target it was sent: that does not show where the tag points)"; fi
  elif [ "$FG_TAG_OK" = 1 ]; then fg_line "NOTE: target_unverified (the release target is not a commit id; the tag's commit was checked)"
  else fg_line "NOTE: target_unverified (the release target is not a commit id, and the tag's commit was not reported either)"; fi
  return "$ok"
}

fg_readback() { # after a write: the release must be present and match
  prov_release_get "$TAG" || fg_net_end
  [ "$FG_REL_STATE" = present ] || fg_fail readback_mismatch "the release is not visible after the write (state ${FG_REL_STATE})"
  fg_rel_line
  fg_matches || fg_fail readback_mismatch "the release read back does not match (tag, draft, prerelease or target)"
  fg_line "READBACK: ok"
}

fg_do_update() {
  fg_ok_rel_id "$FG_REL_ID" || fg_api_err unsafe_id "the release id returned by the forge is not a safe identifier (not used)"
  if [ "$DRY" -eq 1 ]; then fg_line "ACTION: would-update"; fg_end_ensure; fi
  FG_WROTE=1
  prov_release_update "$FG_REL_ID" "$TAG" "$SHA" "$TITLE" "$NOTES" "$PRE" || fg_net_end
  [ "$FG_UPDATE" = updated ] || fg_api_err "unexpected_status_$FG_CODE" "update refused (HTTP $FG_CODE)"
  fg_line "ACTION: updated"
  fg_readback
  fg_end_ensure
}

fg_do_create() {
  if [ "$DRY" -eq 1 ]; then fg_line "ACTION: would-create"; fg_end_ensure; fi
  FG_WROTE=1
  prov_release_create "$TAG" "$SHA" "$TITLE" "$NOTES" "$PRE" || fg_net_end
  case "$FG_CREATE" in
    created) fg_line "ACTION: created"; fg_readback; fg_end_ensure ;;
    exists)
      fg_release_get_or_end
      [ "$FG_REL_STATE" = present ] || fg_fail readback_mismatch "the forge said the release exists but it cannot be read back"
      fg_rel_line
      if fg_matches; then fg_line "ACTION: kept"; fg_end_ensure; fi
      [ "$UPDATE" -eq 1 ] && fg_do_update
      fg_fail present_mismatch "a release for this tag exists and differs; re-run with --update to change it" ;;
    refused) return 1 ;;
    *) case "$FG_CODE" in
         401|403) fg_api_err auth_failed "the forge refused the create (HTTP $FG_CODE): token scope?" ;;
         *) fg_api_err "unexpected_status_$FG_CODE" "create refused (HTTP $FG_CODE)" ;;
       esac ;;
  esac
}

case "$FG_REL_STATE" in
  present)
    fg_rel_line
    fg_matches; _fg_m=$?
    # (b) of fg_end_ensure: a derived target of a release that was present before any write
    [ "$FG_TARGET_OK" = 1 ] && [ "$FG_WROTE" -eq 0 ] && FG_COMMIT_OK=1
    if [ "$_fg_m" -eq 0 ]; then fg_line "ACTION: kept"; fg_end_ensure; fi
    [ "$UPDATE" -eq 1 ] && fg_do_update
    fg_fail present_mismatch "a release for this tag exists and differs; re-run with --update to change it" ;;
  absent)
    fg_line "RELEASE: absent"
    fg_do_create || fg_api_err "unexpected_status_$FG_CODE" "create refused (HTTP $FG_CODE)" ;;
  gap)
    if [ "$FG_REL_GAP" = releases_unsupported_or_empty ] && [ "$TRYAMB" -eq 1 ]; then
      fg_msg "NOTICE: release list is ambiguous (404 for an existing repository); trying the create, the read-back decides"
      fg_do_create || fg_gap releases_unsupported_or_empty "the create was refused (HTTP $FG_CODE): releases look unsupported here"
    fi
    fg_gap "$FG_REL_GAP" ;;
esac
fg_end FAIL 1 internal_state
