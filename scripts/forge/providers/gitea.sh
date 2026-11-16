# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: the variables set here are read by scripts/forge/forge.sh
# scripts/forge/providers/gitea.sh -- Gitea and Forgejo (git.m3w.org, codeberg.org), REST API v1.
# Sourced by scripts/forge/forge.sh. The provider contract (every providers/*.sh defines these):
#   prov_init                     auth header format (FG_AUTH_FMT), extra headers (FG_HDRS), FG_RPATH, FG_PRE_SUPPORTED
#                                 FG_TARGET_DERIVED: 1 only where the release target read back is DERIVED by the forge
#                                 from the tag (GitLab commit.id); 0 where it is the stored field the tool itself sent
#   prov_repo                     GET the repository; FG_HAS_RELEASES true|false|unknown
#   prov_release_get TAG          FG_REL_STATE present|absent|gap|error, FG_REL_GAP, FG_REL_ID, FG_REL_TAG,
#                                 FG_REL_PRE, FG_REL_TARGET, FG_REL_DRAFT
#   prov_release_create TAG SHA TITLE NOTES_FILE PRE    FG_CREATE created|exists|refused|error
#   prov_release_update ID TAG SHA TITLE NOTES_FILE PRE FG_UPDATE updated|error
#   prov_tag_get TAG              FG_TAG_STATE present|absent|unknown|error, FG_TAG_SHA
#   prov_enable_releases          the ONE reversible settings change of --enable-releases (gitea only)
#   prov_probe                    read-only GETs, prints "PROBE: <what> status=<code> <key names>"
# Every function returns 1 only when no HTTP answer arrived (FG_NET set by fg_http).
# API facts (docs + read-only probes 2026-11-12): auth "Authorization: token"; GET /repos/{o}/{r} carries
# has_releases; Codeberg's repo has has_releases=false and then every /releases URL answers 404.
# Write paths (POST /releases, PATCH /releases/{id}, PATCH /repos/{o}/{r}) are LIVE-UNPROVEN.

prov_init() {
  FG_AUTH_FMT='Authorization: token %s'
  FG_HDRS=('Accept: application/json')
  FG_RPATH="/repos/$FG_OWNER/$FG_REPO"
  FG_PRE_SUPPORTED=1
  FG_TARGET_DERIVED=0   # Gitea/Forgejo store target_commitish as sent
}

prov_repo() {
  fg_http GET "$FG_RPATH" || return 1
  FG_HAS_RELEASES="$(fg_bool "$(fg_json '.has_releases')")"
}

_gitea_rel_fields() {
  FG_REL_ID="$(fg_json '.id // empty')"
  FG_REL_TAG="$(fg_json '.tag_name // empty')"
  FG_REL_PRE="$(fg_bool "$(fg_json '.prerelease')")"
  FG_REL_DRAFT="$(fg_bool "$(fg_json '.draft')")"
  FG_REL_TARGET="$(fg_json '.target_commitish // empty')"
}

prov_release_get() {
  FG_REL_STATE=error FG_REL_GAP="" FG_REL_ID="" FG_REL_TAG="" FG_REL_PRE=unknown FG_REL_TARGET="" FG_REL_DRAFT=unknown
  fg_http GET "$FG_RPATH/releases/tags/$1" || return 1
  case "$FG_CODE" in
    200) FG_REL_STATE=present; _gitea_rel_fields ;;
    404) if [ "${FG_HAS_RELEASES:-unknown}" = false ]; then FG_REL_STATE=gap; FG_REL_GAP=releases_disabled
         else FG_REL_STATE=absent; fi ;;
  esac
  return 0
}

_gitea_payload() { # TAG SHA TITLE NOTES PRE
  jq -n --arg t "$1" --arg c "$2" --arg n "$3" --rawfile b "$4" --argjson p "$5" \
    '{tag_name:$t,target_commitish:$c,name:$n,body:$b,draft:false,prerelease:$p}' >"$FG_TMP/payload.json" 2>/dev/null
}

prov_release_create() {
  FG_CREATE=error
  _gitea_payload "$1" "$2" "$3" "$4" "$5" || return 0
  fg_http POST "$FG_RPATH/releases" "$FG_TMP/payload.json" || return 1
  case "$FG_CODE" in 201) FG_CREATE=created ;; 409) FG_CREATE=exists ;; esac
  return 0
}

prov_release_update() {
  FG_UPDATE=error
  _gitea_payload "$2" "$3" "$4" "$5" "$6" || return 0
  fg_http PATCH "$FG_RPATH/releases/$1" "$FG_TMP/payload.json" || return 1
  [ "$FG_CODE" = 200 ] && FG_UPDATE=updated
  return 0
}

prov_tag_get() {
  FG_TAG_STATE=error FG_TAG_SHA=""
  fg_http GET "$FG_RPATH/tags/$1" || return 1
  case "$FG_CODE" in
    200) FG_TAG_STATE=present; FG_TAG_SHA="$(fg_json '.commit.sha // empty')" ;;
    404) FG_TAG_STATE=absent ;;
  esac
  return 0
}

prov_enable_releases() {
  FG_ENABLE=error
  printf '{"has_releases":true}' >"$FG_TMP/payload.json"
  fg_http PATCH "$FG_RPATH" "$FG_TMP/payload.json" || return 1
  [ "$FG_CODE" = 200 ] || return 0
  prov_repo || return 1
  [ "$FG_CODE" = 200 ] && [ "$FG_HAS_RELEASES" = true ] && FG_ENABLE=enabled
  return 0
}

prov_probe() {
  fg_probe_get version "${FG_API_BASE}/version"
  fg_probe_get repo "${FG_API_BASE}$FG_RPATH"
  fg_probe_get releases "${FG_API_BASE}$FG_RPATH/releases?limit=1"
  fg_probe_get tags "${FG_API_BASE}$FG_RPATH/tags?limit=1"
}
