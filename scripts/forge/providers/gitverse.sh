# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: the variables set here are read by scripts/forge/forge.sh
# scripts/forge/providers/gitverse.sh -- GitVerse (gitverse.ru, API api.gitverse.ru), GitHub-shaped own API.
# Contract: see gitea.sh.
# API facts (gitverse.ru/docs/developers/public-api; read-only probes 2026-11-12): auth "Authorization:
# Bearer" plus the MANDATORY header "Accept: application/vnd.gitverse.object+json;version=1" (without it the
# API answers 415). Probed anomaly: GET /repos/{o}/{r}/releases answers 404 {"code":"REPO_NOT_FOUND"} for a
# repository that GET /repos/{o}/{r} answers 200, and /releases/tags/{tag} answers 404. That state cannot be
# told apart from "no release yet" or "releases unsupported", so it is the GAP releases_unsupported_or_empty,
# never "absent" and never success. forge.sh release-ensure creates there only with the explicit opt-in
# --try-create-on-ambiguous, and then only the read-back decides. The prerelease field is not documented:
# when the read-back does not report it, forge.sh says "NOTE: prerelease_unverified".
# Tags: git/matching-refs/tags/{tag} works; git/tags/{sha} and /tags answer 400 (live 2026-11-12); the commit of
# an annotated tag is read from commits/{tag-object-sha} (live 2026-11-16), else "TAG: present sha=unknown".
# Write paths (POST /releases, PATCH /releases/{id}) are LIVE-UNPROVEN.

prov_init() {
  FG_AUTH_FMT='Authorization: Bearer %s'
  FG_HDRS=('Accept: application/vnd.gitverse.object+json;version=1')
  FG_RPATH="/repos/$FG_OWNER/$FG_REPO"
  FG_PRE_SUPPORTED=1
  FG_TARGET_DERIVED=0   # GitVerse: GitHub-shaped, target_commitish is the stored request field
}

prov_repo() {
  fg_http GET "$FG_RPATH" || return 1
  FG_HAS_RELEASES=unknown
}

prov_release_get() {
  FG_REL_STATE=error FG_REL_GAP="" FG_REL_ID="" FG_REL_TAG="" FG_REL_PRE=unknown FG_REL_TARGET="" FG_REL_DRAFT=unknown
  fg_http GET "$FG_RPATH/releases/tags/$1" || return 1
  case "$FG_CODE" in
    200) FG_REL_STATE=present
         FG_REL_ID="$(fg_json '.id // empty')"; FG_REL_TAG="$(fg_json '.tag_name // empty')"
         FG_REL_PRE="$(fg_bool "$(fg_json '.prerelease')")"; FG_REL_DRAFT="$(fg_bool "$(fg_json '.draft')")"
         FG_REL_TARGET="$(fg_json '.target_commitish // empty')"
         return 0 ;;
    404) ;;
    *) return 0 ;;
  esac
  # 404 by tag: absent only when the release LIST itself works
  fg_http GET "$FG_RPATH/releases?per_page=1" || return 1
  case "$FG_CODE" in
    200) FG_REL_STATE=absent ;;
    404) FG_REL_STATE=gap; FG_REL_GAP=releases_unsupported_or_empty ;;
  esac
  return 0
}

prov_release_create() { # TAG SHA TITLE NOTES PRE
  FG_CREATE=error
  jq -n --arg t "$1" --arg c "$2" --arg n "$3" --rawfile b "$4" --argjson p "$5" \
    '{tag_name:$t,target_commitish:$c,name:$n,body:$b,draft:false,prerelease:$p}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http POST "$FG_RPATH/releases" "$FG_TMP/payload.json" || return 1
  case "$FG_CODE" in
    200|201) FG_CREATE=created ;;
    409|422) FG_CREATE=exists ;;
    403|404) FG_CREATE=refused ;;
  esac
  return 0
}

prov_release_update() { # ID TAG SHA TITLE NOTES PRE
  FG_UPDATE=error
  jq -n --arg n "$4" --rawfile b "$5" --argjson p "$6" '{name:$n,body:$b,prerelease:$p}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http PATCH "$FG_RPATH/releases/$1" "$FG_TMP/payload.json" || return 1
  [ "$FG_CODE" = 200 ] && FG_UPDATE=updated
  return 0
}

prov_tag_get() {
  local t s o
  FG_TAG_STATE=error FG_TAG_SHA=""
  fg_http GET "$FG_RPATH/git/matching-refs/tags/$1" || return 1
  case "$FG_CODE" in 200) ;; 404) FG_TAG_STATE=absent; return 0 ;; *) return 0 ;; esac
  t="$(jq -r --arg r "refs/tags/$1" '[.[]? | select(.ref == $r)][0].object.type // empty' <"$FG_TMP/resp" 2>/dev/null)"
  s="$(jq -r --arg r "refs/tags/$1" '[.[]? | select(.ref == $r)][0].object.sha // empty' <"$FG_TMP/resp" 2>/dev/null)"
  [ -n "$t" ] || { FG_TAG_STATE=absent; return 0; }
  if [ "$t" = tag ] && fg_ok_sha "$s"; then
    o="$s"
    fg_http GET "$FG_RPATH/git/tags/$o" || return 1
    if [ "$FG_CODE" = 200 ]; then
      t="$(fg_json '.object.type // empty')"; s="$(fg_json '.object.sha // empty')"
    else
      # live 2026-11-12/16: GitVerse answers 400 VALIDATION_ERROR to git/tags/{sha} (and to /tags), but
      # GET commits/{tag-object-sha} (the object.url of the matching-refs answer) answers 200 with the commit
      # the forge PEELS from the tag (live v73.3: tag object e915eef..., sha aa5ae0a... = ls-remote T^{}).
      # Asked by the tag-object sha, never by the tag name (a branch of that name could shadow it). Only a
      # full commit id that is not the tag-object sha itself counts; anything else: commit unverified.
      fg_http GET "$FG_RPATH/commits/$o" || return 1
      s=""; [ "$FG_CODE" = 200 ] && s="$(fg_json '.sha // empty')"
      if fg_ok_sha "$s" && [ "$s" != "$o" ]; then t=commit; else FG_TAG_STATE=present; FG_TAG_SHA=""; return 0; fi
    fi
  fi
  FG_TAG_STATE=present
  [ "$t" = commit ] && FG_TAG_SHA="$s"
  return 0
}

prov_probe() {
  fg_probe_get repo "${FG_API_BASE}$FG_RPATH"
  fg_probe_get releases "${FG_API_BASE}$FG_RPATH/releases?per_page=1"
  fg_probe_get tags "${FG_API_BASE}$FG_RPATH/git/matching-refs/tags/"
}
