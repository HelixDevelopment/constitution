# shellcheck shell=bash
# shellcheck disable=SC2034   # sourced: the variables set here are read by scripts/forge/forge.sh
# scripts/forge/providers/gitflic.sh -- GitFlic (gitflic.ru, API api.gitflic.ru; self-hosted: <host>/rest-api).
# Own API, not Gitea-compatible. Contract: see gitea.sh.
# API facts (docs.gitflic.ru/api release, tag, pagination; read-only probes 2026-11-12): auth
# "Authorization: token"; list GET /project/{o}/{p}/release?page=N&size=S (zero-based) ->
# _embedded.releaseTagModelList[] {id, tagName, preRelease, commitId, title}, page{totalPages, number};
# there is NO get-by-tag, so a lookup PAGES THROUGH the list and matches tagName (FORGE_GITFLIC_MAX_PAGES,
# default 20, size 50; reaching the cap without a match is GAP readback_page_cap, never "absent", because
# gitflic.ru allows 500 requests per hour). Tags: GET .../tag?page&size -> _embedded.tagList[] {name, commitId}
# (GET .../tag/{name} answered 400 in the probe, so tags are looked up by iteration too).
# Write paths (POST .../release, PUT .../release/{id}) are LIVE-UNPROVEN; GitFlic has no draft concept.

GITFLIC_SIZE=50

prov_init() {
  FG_AUTH_FMT='Authorization: token %s'
  FG_HDRS=('Accept: application/json')
  FG_RPATH="/project/$FG_OWNER/$FG_REPO"
  FG_PRE_SUPPORTED=1
  FG_TARGET_DERIVED=0   # GitFlic: whether commitId is derived from the tag is UNCONFIRMED (not live-proven), so it is not trusted
}

prov_repo() {
  fg_http GET "$FG_RPATH" || return 1
  FG_HAS_RELEASES=unknown
}

_gitflic_max_pages() {
  local m="${FORGE_GITFLIC_MAX_PAGES:-20}"
  [[ $m =~ ^[0-9]{1,3}$ ]] && [ "$m" -ge 1 ] || m=20
  printf '%s' "$m"
}

# _gitflic_find KIND TAG: KIND release|tag. Sets _GF_FOUND (1|0|cap|error) and leaves the match in page.json
_gitflic_find() {
  local kind="$1" tag="$2" p=0 max tp n listkey key path
  max="$(_gitflic_max_pages)"
  if [ "$kind" = release ]; then path="$FG_RPATH/release"; listkey=releaseTagModelList; key=tagName
  else path="$FG_RPATH/tag"; listkey=tagList; key=name; fi
  _GF_FOUND=error
  while [ "$p" -lt "$max" ]; do
    fg_http GET "$path?page=$p&size=$GITFLIC_SIZE" || return 1
    [ "$FG_CODE" = 200 ] || return 0
    n="$(jq -r --arg l "$listkey" --arg k "$key" --arg t "$tag" \
          '[(._embedded[$l] // [])[] | select(.[$k] == $t)] | length' <"$FG_TMP/resp" 2>/dev/null)"
    [[ $n =~ ^[0-9]+$ ]] || return 0
    if [ "$n" -ge 1 ]; then
      jq --arg l "$listkey" --arg k "$key" --arg t "$tag" \
        '[(._embedded[$l] // [])[] | select(.[$k] == $t)][0]' <"$FG_TMP/resp" >"$FG_TMP/page.json" 2>/dev/null || return 0
      _GF_FOUND=1; return 0
    fi
    tp="$(fg_json '.page.totalPages // 0')"
    [[ $tp =~ ^[0-9]+$ ]] || return 0
    p=$((p + 1))
    if [ "$p" -ge "$tp" ]; then _GF_FOUND=0; return 0; fi
  done
  _GF_FOUND=cap
  return 0
}

prov_release_get() {
  FG_REL_STATE=error FG_REL_GAP="" FG_REL_ID="" FG_REL_TAG="" FG_REL_PRE=unknown FG_REL_TARGET="" FG_REL_DRAFT=false
  _gitflic_find release "$1" || return 1
  case "$_GF_FOUND" in
    1) FG_REL_STATE=present
       FG_REL_ID="$(jq -r '.id // empty' <"$FG_TMP/page.json" 2>/dev/null)"
       FG_REL_TAG="$(jq -r '.tagName // empty' <"$FG_TMP/page.json" 2>/dev/null)"
       FG_REL_PRE="$(fg_bool "$(jq -r '.preRelease' <"$FG_TMP/page.json" 2>/dev/null)")"
       FG_REL_TARGET="$(jq -r '.commitId // empty' <"$FG_TMP/page.json" 2>/dev/null)" ;;
    0) FG_REL_STATE=absent ;;
    cap) FG_REL_STATE=gap; FG_REL_GAP=readback_page_cap ;;
  esac
  return 0
}

prov_release_create() { # TAG SHA TITLE NOTES PRE
  FG_CREATE=error
  jq -n --arg t "$1" --arg n "$3" --rawfile b "$4" --argjson p "$5" \
    '{title:$n,description:$b,tagName:$t,preRelease:$p,attachProjectArchive:false}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http POST "$FG_RPATH/release" "$FG_TMP/payload.json" || return 1
  case "$FG_CODE" in 200|201) FG_CREATE=created ;; 409) FG_CREATE=exists ;; esac
  return 0
}

prov_release_update() { # ID TAG SHA TITLE NOTES PRE
  FG_UPDATE=error
  jq -n --arg t "$2" --arg n "$4" --rawfile b "$5" --argjson p "$6" \
    '{title:$n,description:$b,tagName:$t,preRelease:$p}' >"$FG_TMP/payload.json" 2>/dev/null || return 0
  fg_http PUT "$FG_RPATH/release/$1" "$FG_TMP/payload.json" || return 1
  [ "$FG_CODE" = 200 ] && FG_UPDATE=updated
  return 0
}

prov_tag_get() {
  FG_TAG_STATE=error FG_TAG_SHA=""
  _gitflic_find tag "$1" || return 1
  case "$_GF_FOUND" in
    1) FG_TAG_STATE=present; FG_TAG_SHA="$(jq -r '.commitId // empty' <"$FG_TMP/page.json" 2>/dev/null)" ;;
    0) FG_TAG_STATE=absent ;;
    cap) FG_TAG_STATE=unknown ;;
  esac
  return 0
}

prov_probe() {
  fg_probe_get repo "${FG_API_BASE}$FG_RPATH"
  fg_probe_get releases "${FG_API_BASE}$FG_RPATH/release?page=0&size=1"
  fg_probe_get tags "${FG_API_BASE}$FG_RPATH/tag?page=0&size=1"
}
