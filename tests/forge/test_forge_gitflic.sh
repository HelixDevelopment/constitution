#!/usr/bin/env bash
# tests/forge/test_forge_gitflic.sh -- unit tests of the gitflic provider (own API, no get-by-tag: the
# read-back pages through the list). CLASS (section 11.4.289(C)(2)): gate-logic / unit against the
# loopback fixture server; the write paths are LIVE-UNPROVEN.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/forge/lib.sh
. "$HERE/lib.sh"
ft_init
T=$'\t'
SHA=0123456789abcdef0123456789abcdef01234567
FT_ENV=(TEST_GITFLIC_TOKEN=gitflicTESTtokenQwErTyUiOpAsDfGh)
U=git@gitflic.test:o/r.git
printf 'notes\n' >"$FT_SBX/notes.md"
hosts() { ft_hosts "gitflic.test${T}gitflic${T}http://127.0.0.1:@PORT@${T}TEST_GITFLIC_TOKEN${T}-"; }
REPO='"GET /project/o/r":[{"status":200,"body":{"alias":"r","defaultBranch":"main"}}]'
rel() { printf '{"id":"%s","tagName":"%s","preRelease":%s,"commitId":"%s","title":"%s"}' "$1" "$2" "$3" "$4" "$2"; }
page() { # number totalPages items...
  local n="$1" tp="$2"; shift 2; local IFS=,
  printf '{"_embedded":{"releaseTagModelList":[%s]},"page":{"size":50,"totalElements":99,"totalPages":%s,"number":%s}}' "$*" "$tp" "$n"
}
TAGP='"GET /project/o/r/tag?page=0&size=50":[{"status":200,"body":{"_embedded":{"tagList":[{"name":"v0","commitId":"1111111111111111111111111111111111111111"},{"name":"v1","commitId":"'$SHA'"}]},"page":{"size":50,"totalElements":2,"totalPages":1,"number":0}}}]'
ensure() { ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" "$@"; }

# F1 release found on page 2 (by iteration)
ft_server '{"routes":{'"$REPO"',
 "GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$(page 0 2 "$(rel a1 v0 false 1111111111111111111111111111111111111111)")"'}],
 "GET /project/o/r/release?page=1&size=50":[{"status":200,"body":'"$(page 1 2 "$(rel 5f0c2b1e-0000-4000-8000-000000000001 v1 true "$SHA")")"'}]}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "F1 rc" "$FT_RC" 0
ft_has "F1 present on page 2" "$FT_OUT" "RELEASE: present id=5f0c2b1e-0000-4000-8000-000000000001 prerelease=true"
ft_has "F1 auth header form" "$(ft_reqs)" '"Authorization": "token gitflicTESTtoken'

# F2 empty project (no _embedded) = absent
ft_server '{"routes":{'"$REPO"',"GET /project/o/r/release?page=0&size=50":[{"status":200,"body":{"page":{"size":50,"totalElements":0,"totalPages":0,"number":0}}}]}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "F2 rc" "$FT_RC" 0
ft_has "F2 absent" "$FT_OUT" "RELEASE: absent"

# F3 page cap reached without a match: GAP readback_page_cap (never "absent")
ft_server '{"routes":{'"$REPO"',"GET /project/o/r/release":[{"status":200,"body":'"$(page 0 9 "$(rel a1 v0 false 1111111111111111111111111111111111111111)")"'}]}}'; hosts
FT_ENV=(TEST_GITFLIC_TOKEN=gitflicTESTtokenQwErTyUiOpAsDfGh FORGE_GITFLIC_MAX_PAGES=2)
ft_run release-get --url "$U" --tag v1
ft_ok "F3 rc GAP" "$FT_RC" 3
ft_has "F3 reason" "$FT_OUT" "REASON: readback_page_cap"
ft_ok "F3 stopped at the cap" "$(ft_req_count GET)" 3
FT_ENV=(TEST_GITFLIC_TOKEN=gitflicTESTtokenQwErTyUiOpAsDfGh)

# F4 create, then read back by iterating the list
EMPTY='{"page":{"size":50,"totalElements":0,"totalPages":0,"number":0}}'
ft_server '{"routes":{'"$REPO"','"$TAGP"',
 "GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$EMPTY"'},{"status":200,"body":'"$(page 0 1 "$(rel 5f0c2b1e-0000-4000-8000-000000000001 v1 true "$SHA")")"'}],
 "POST /project/o/r/release":[{"status":200,"body":'"$(rel 5f0c2b1e-0000-4000-8000-000000000001 v1 true "$SHA")"'}]}}'; hosts
ensure --prerelease
ft_ok "F4 rc" "$FT_RC" 0
ft_has "F4 created" "$FT_OUT" "ACTION: created"
ft_has "F4 readback" "$FT_OUT" "READBACK: ok"
P="$(ft_reqs | grep '"POST"')"
ft_has "F4 payload tagName" "$P" 'tagName'
ft_has "F4 payload preRelease" "$P" 'preRelease'
ft_has "F4 no project archive" "$P" 'attachProjectArchive'

# F5 create answered 2xx but the list never shows it: FAIL
ft_server '{"routes":{'"$REPO"','"$TAGP"',"GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$EMPTY"'}],
 "POST /project/o/r/release":[{"status":200,"body":{"id":"x"}}]}}'; hosts
ensure --prerelease
ft_ok "F5 rc FAIL" "$FT_RC" 1
ft_has "F5 reason" "$FT_OUT" "REASON: readback_mismatch"

# F6 tag-get by list iteration
ft_server '{"routes":{'"$REPO"','"$TAGP"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "F6 tag sha" "$FT_OUT" "TAG: present sha=$SHA"
ft_run tag-get --url "$U" --tag v9
ft_has "F6b absent tag" "$FT_OUT" "TAG: absent"

# F7 update with PUT on mismatch + --update
ft_server '{"routes":{'"$REPO"','"$TAGP"',
 "GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$(page 0 1 "$(rel 5f0c2b1e-0000-4000-8000-000000000001 v1 false "$SHA")")"'},{"status":200,"body":'"$(page 0 1 "$(rel 5f0c2b1e-0000-4000-8000-000000000001 v1 true "$SHA")")"'}],
 "PUT /project/o/r/release/5f0c2b1e-0000-4000-8000-000000000001":[{"status":200,"body":{}}]}}'; hosts
ensure --prerelease --update
ft_ok "F7 rc" "$FT_RC" 0
ft_has "F7 updated" "$FT_OUT" "ACTION: updated"
ft_ok "F7 one PUT" "$(ft_req_count PUT)" 1

# F8 a release id that is not a safe token (path injection attempt) is refused
ft_server '{"routes":{'"$REPO"','"$TAGP"',"GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$(page 0 1 "$(rel '../../x' v1 false "$SHA")")"'}]}}'; hosts
ensure --prerelease --update
ft_ok "F8 unsafe id: rc API" "$FT_RC" 4
ft_ok "F8 no PUT" "$(ft_req_count PUT)" 0

# F9 (round 3, review X16) the GitFlic release commitId is READ and compared: a release whose commitId is
# another commit than --sha (the tag's commit is verified = --sha) is a mismatch, never "kept"
ft_server '{"routes":{'"$REPO"','"$TAGP"',
 "GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$(page 0 1 "$(rel a1 v1 false 1111111111111111111111111111111111111111)")"'}]}}'; hosts
ensure
ft_ok "F9 commitId differs: rc 1" "$FT_RC" 1
ft_has "F9 reason" "$FT_OUT" "REASON: present_mismatch"
ft_has "F9 target shown" "$FT_OUT" "target=1111111111111111111111111111111111111111"
# F9b GitFlic commitId equal to --sha on an UNVERIFIED tag commit: UNCONFIRMED whether GitFlic derives it
# from the tag, so it is not trusted (rc 5, never OK)
ft_server '{"routes":{'"$REPO"',
 "GET /project/o/r/tag?page=0&size=50":[{"status":200,"body":{"_embedded":{"tagList":[{"name":"v1"}]},"page":{"size":50,"totalElements":1,"totalPages":1,"number":0}}}],
 "GET /project/o/r/release?page=0&size=50":[{"status":200,"body":'"$(page 0 1 "$(rel a1 v1 false "$SHA")")"'}]}}'; hosts
ensure
ft_ok "F9b gitflic commitId not trusted alone: rc 5" "$FT_RC" 5
ft_has "F9b echo noted" "$FT_OUT" "NOTE: target_echo_only"

ft_done
