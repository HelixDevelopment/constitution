# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: the variables set here are read by scripts/forge/forge.sh
# scripts/forge/providers/github.sh -- GitHub REST API (api.github.com) over curl. Contract: see gitea.sh.
# forge.sh talks REST for every forge; scripts/release/tag_and_release.sh keeps its own gh legs (design
# decision, scratch design multiforge_design.md section 3.5 and 4).
# A renamed repository answers 301 with a "url" on the same API origin (/repositories/<id>); prov_repo
# follows that ONE hop itself (curl never follows redirects) and continues with the canonical full_name.
# A redirect to any other origin is refused before a second request (the token pin).
# A DRAFT release is invisible to GET /releases/tags/{tag}; on a 404 there the release list (first page,
# 100 items, needs a token with push access to show drafts) is searched for a draft of the tag, so a draft is
# reported (and release-ensure refuses it as present_mismatch) instead of a second release being created.
# When the list cannot be read, or holds 100 items without a match: "NOTE: draft_lookup_unavailable" /
# "NOTE: draft_lookup_first_page_only" (a draft beyond the first page is not seen).
# A 422 on create is "exists" only when the answer says errors[].code == "already_exists"; any other 422
# (bad target, bad tag) is an error.
# Write paths (POST /releases, PATCH /releases/{id}) are LIVE-UNPROVEN.

prov_init() {
  FG_AUTH_FMT='Authorization: Bearer %s'
  FG_HDRS=('Accept: application/vnd.github+json' 'X-GitHub-Api-Version: 2022-11-28')
  FG_RPATH="/repos/$FG_OWNER/$FG_REPO"
  FG_PRE_SUPPORTED=1
  FG_TARGET_DERIVED=0   # GitHub: target_commitish is the stored request field ("unused if the Git tag already exists")
}

prov_repo() {
  local u fn o r
  fg_http GET "$FG_RPATH" || return 1
  FG_HAS_RELEASES=unknown
  if [ "$FG_CODE" = 301 ]; then
    u="$(fg_json '.url // empty')"
    case "$u" in "$FG_API_ORIGIN"/repositories/*) ;; *) FG_NET=pin; return 1 ;; esac
    [[ ${u#"$FG_API_ORIGIN"} =~ ^/repositories/[0-9]{1,20}$ ]] || { FG_NET=pin; return 1; }
    fg_http_url GET "$u" || return 1
    [ "$FG_CODE" = 200 ] || return 0
    fn="$(fg_json '.full_name // empty')"
    o="${fn%%/*}"; r="${fn#*/}"
    if fg_ok_segment "$o" && fg_ok_segment "$r" && [ "$fn" = "$o/$r" ]; then
      FG_OWNER="$o" FG_REPO="$r" FG_RPATH="/repos/$o/$r"
      fg_line "NOTE: repo_moved canonical=$o/$r"
    else
      FG_CODE=000
    fi
  fi
  return 0
}

prov_release_get() {
  FG_REL_STATE=error FG_REL_GAP="" FG_REL_ID="" FG_REL_TAG="" FG_REL_PRE=unknown FG_REL_TARGET="" FG_REL_DRAFT=unknown
  fg_http GET "$FG_RPATH/releases/tags/$1" || return 1
  case "$FG_CODE" in
    200) FG_REL_STATE=present
         FG_REL_ID="$(fg_json '.id // empty')"; FG_REL_TAG="$(fg_json '.tag_name // empty')"
         FG_REL_PRE="$(fg_bool "$(fg_json '.prerelease')")"; FG_REL_DRAFT="$(fg_bool "$(fg_json '.draft')")"
         FG_REL_TARGET="$(fg_json '.target_commitish // empty')" ;;
    404) _github_draft_lookup "$1" || return 1 ;;
  esac
  return 0
}

_github_draft_lookup() { # TAG: after a 404 by tag, look for a draft of TAG on the first page of the list
  local n
  FG_REL_STATE=absent
  fg_http GET "$FG_RPATH/releases?per_page=100" || return 1
  if [ "$FG_CODE" != 200 ]; then fg_line "NOTE: draft_lookup_unavailable (release list answered status=$FG_CODE)"; FG_CODE=404; return 0; fi
  n="$(jq -r --arg t "$1" '[.[]? | select(.tag_name == $t and .draft == true)] | length' <"$FG_TMP/resp" 2>/dev/null)"
  if [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ]; then
    jq --arg t "$1" '[.[]? | select(.tag_name == $t and .draft == true)][0]' <"$FG_TMP/resp" >"$FG_TMP/page.json" 2>/dev/null
    FG_REL_STATE=present
    FG_REL_ID="$(jq -r '.id // empty' <"$FG_TMP/page.json" 2>/dev/null)"; FG_REL_TAG="$(jq -r '.tag_name // empty' <"$FG_TMP/page.json" 2>/dev/null)"
    FG_REL_PRE="$(fg_bool "$(jq -r '.prerelease' <"$FG_TMP/page.json" 2>/dev/null)")"; FG_REL_DRAFT=true
    FG_REL_TARGET="$(jq -r '.target_commitish // empty' <"$FG_TMP/page.json" 2>/dev/null)"
    fg_line "NOTE: draft_found (the release of this tag is a draft)"
  elif [ "$(fg_json 'length')" = 100 ]; then fg_line "NOTE: draft_lookup_first_page_only (100 releases listed, no draft of this tag on the first page)"
  fi
  FG_CODE=404
  return 0
}

_github_payload() { # TAG SHA TITLE NOTES PRE
  jq -n --arg t "$1" --arg c "$2" --arg n "$3" --rawfile b "$4" --argjson p "$5" \
    '{tag_name:$t,target_commitish:$c,name:$n,body:$b,draft:false,prerelease:$p}' >"$FG_TMP/payload.json" 2>/dev/null
}

prov_release_create() {
  FG_CREATE=error
  _github_payload "$1" "$2" "$3" "$4" "$5" || return 0
  fg_http POST "$FG_RPATH/releases" "$FG_TMP/payload.json" || return 1
  case "$FG_CODE" in
    201) FG_CREATE=created ;;
    422) [ "$(fg_json '[.errors[]? | select(.code == "already_exists")] | length')" -ge 1 ] 2>/dev/null && FG_CREATE=exists ;;
  esac
  return 0
}

prov_release_update() {
  FG_UPDATE=error
  jq -n --arg n "$4" --rawfile b "$5" --argjson p "$6" '{name:$n,body:$b,draft:false,prerelease:$p}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http PATCH "$FG_RPATH/releases/$1" "$FG_TMP/payload.json" || return 1
  [ "$FG_CODE" = 200 ] && FG_UPDATE=updated
  return 0
}

prov_tag_get() {
  local t s
  FG_TAG_STATE=error FG_TAG_SHA=""
  fg_http GET "$FG_RPATH/git/ref/tags/$1" || return 1
  case "$FG_CODE" in
    404) FG_TAG_STATE=absent; return 0 ;;
    200) ;;
    *) return 0 ;;
  esac
  [ "$(fg_json '.ref // empty')" = "refs/tags/$1" ] || { FG_TAG_STATE=absent; return 0; }
  t="$(fg_json '.object.type // empty')"; s="$(fg_json '.object.sha // empty')"
  if [ "$t" = tag ] && fg_ok_sha "$s"; then
    fg_http GET "$FG_RPATH/git/tags/$s" || return 1
    [ "$FG_CODE" = 200 ] || return 0
    t="$(fg_json '.object.type // empty')"; s="$(fg_json '.object.sha // empty')"
  fi
  FG_TAG_STATE=present
  [ "$t" = commit ] && FG_TAG_SHA="$s"
  return 0
}

prov_probe() {
  fg_probe_get repo "${FG_API_BASE}$FG_RPATH"
  fg_probe_get releases "${FG_API_BASE}$FG_RPATH/releases?per_page=1"
  fg_probe_get tags "${FG_API_BASE}$FG_RPATH/tags?per_page=1"
}
