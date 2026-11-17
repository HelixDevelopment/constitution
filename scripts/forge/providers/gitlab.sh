# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: the variables set here are read by scripts/forge/forge.sh
# scripts/forge/providers/gitlab.sh -- GitLab REST API v4 over curl. Contract: see gitea.sh.
# The project is addressed by its URL-encoded full path (group/sub/project -> group%2Fsub%2Fproject).
# GitLab releases have NO pre-release flag: FG_PRE_SUPPORTED=0, forge.sh reports
# "NOTE: prerelease_unsupported" and never claims a pre-release there. The release target is the tag's
# commit (commit.id in the release object). scripts/release/tag_and_release.sh keeps its glab leg.
# Write paths (POST /releases, PUT /releases/{tag}) are LIVE-UNPROVEN.

prov_init() {
  FG_AUTH_FMT='PRIVATE-TOKEN: %s'
  FG_HDRS=('Accept: application/json')
  FG_RPATH="/projects/${FG_REPO_FULL//\//%2F}"
  FG_PRE_SUPPORTED=0
  FG_TARGET_DERIVED=1   # GitLab: the release commit.id is the commit the forge resolves from the tag
}

prov_repo() {
  fg_http GET "$FG_RPATH" || return 1
  FG_HAS_RELEASES=unknown
}

prov_release_get() {
  FG_REL_STATE=error FG_REL_GAP="" FG_REL_ID="" FG_REL_TAG="" FG_REL_PRE=unknown FG_REL_TARGET="" FG_REL_DRAFT=false
  fg_http GET "$FG_RPATH/releases/$1" || return 1
  case "$FG_CODE" in
    200) FG_REL_STATE=present
         FG_REL_TAG="$(fg_json '.tag_name // empty')"; FG_REL_ID="$FG_REL_TAG"
         FG_REL_TARGET="$(fg_json '.commit.id // empty')" ;;
    404) FG_REL_STATE=absent ;;
  esac
  return 0
}

prov_release_create() { # TAG SHA TITLE NOTES PRE (PRE ignored: no such flag on GitLab)
  FG_CREATE=error
  jq -n --arg t "$1" --arg n "$3" --rawfile b "$4" '{tag_name:$t,name:$n,description:$b}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http POST "$FG_RPATH/releases" "$FG_TMP/payload.json" || return 1
  case "$FG_CODE" in 201) FG_CREATE=created ;; 409) FG_CREATE=exists ;; esac
  return 0
}

prov_release_update() { # ID(=TAG) TAG SHA TITLE NOTES PRE
  FG_UPDATE=error
  jq -n --arg n "$4" --rawfile b "$5" '{name:$n,description:$b}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http PUT "$FG_RPATH/releases/$2" "$FG_TMP/payload.json" || return 1
  [ "$FG_CODE" = 200 ] && FG_UPDATE=updated
  return 0
}

prov_tag_get() {
  FG_TAG_STATE=error FG_TAG_SHA=""
  fg_http GET "$FG_RPATH/repository/tags/$1" || return 1
  case "$FG_CODE" in
    200) FG_TAG_STATE=present; FG_TAG_SHA="$(fg_json '.commit.id // empty')" ;;
    404) FG_TAG_STATE=absent ;;
  esac
  return 0
}

prov_probe() {
  fg_probe_get repo "${FG_API_BASE}$FG_RPATH"
  fg_probe_get releases "${FG_API_BASE}$FG_RPATH/releases?per_page=1"
  fg_probe_get tags "${FG_API_BASE}$FG_RPATH/repository/tags?per_page=1"
}
