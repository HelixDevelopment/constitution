#!/usr/bin/env bash
# tests/forge/test_forge_github_gitlab.sh -- unit tests of the github and gitlab REST providers.
# CLASS (section 11.4.289(C)(2)): gate-logic / unit against the loopback fixture server; the write paths
# are LIVE-UNPROVEN. (tag_and_release.sh keeps its gh/glab legs; forge.sh talks REST over curl.)
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/forge/lib.sh
. "$HERE/lib.sh"
ft_init
T=$'\t'
SHA=0123456789abcdef0123456789abcdef01234567
printf 'notes\n' >"$FT_SBX/notes.md"

# ---- github ----
FT_ENV=(TEST_GH_TOKEN=ghTESTtokenQwErTyUiOpAsDfGhghij)
UG=git@github.test:old/name.git
gh_hosts() { ft_hosts "github.test${T}github${T}http://127.0.0.1:@PORT@${T}TEST_GH_TOKEN${T}-"; }
# H1 a renamed repo (301 to the same API origin) is resolved to its canonical name, once
ft_server '{"routes":{
 "GET /repos/old/name":[{"status":301,"body":{"message":"Moved Permanently","url":"@SELF@/repositories/42"}}],
 "GET /repositories/42":[{"status":200,"body":{"full_name":"new/repo"}}],
 "GET /repos/new/repo/releases/tags/v1":[{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"target_commitish":"main","draft":false}}]}}'
gh_hosts
ft_run release-get --url "$UG" --tag v1
ft_ok "H1 rc" "$FT_RC" 0
ft_has "H1 canonical name" "$FT_OUT" "NOTE: repo_moved canonical=new/repo"
ft_has "H1 present" "$FT_OUT" "RELEASE: present id=3 prerelease=true"
ft_has "H1 bearer auth" "$(ft_reqs)" '"Authorization": "Bearer ghTESTtoken'
ft_has "H1 api version header" "$(ft_reqs)" 'X-GitHub-Api-Version'

# H2 create + read back on GitHub; tag deref through git/ref + git/tags
UG2=git@github.test:o/r.git
ft_server '{"routes":{
 "GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r"}}],
 "GET /repos/o/r/git/ref/tags/v1":[{"status":200,"body":{"ref":"refs/tags/v1","object":{"type":"tag","sha":"2222222222222222222222222222222222222222"}}}],
 "GET /repos/o/r/git/tags/2222222222222222222222222222222222222222":[{"status":200,"body":{"object":{"type":"commit","sha":"'$SHA'"}}}],
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"target_commitish":"main","draft":false}}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":3}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_ok "H2 rc" "$FT_RC" 0
ft_has "H2 created" "$FT_OUT" "ACTION: created"
ft_has "H2 readback" "$FT_OUT" "READBACK: ok"
ft_has "H2 target not a sha -> noted, tag sha checked instead" "$FT_OUT" "NOTE: target_unverified"
ft_has "H2 payload draft false" "$(ft_reqs | grep '"POST"')" 'draft'

# H3 a draft release found by tag is reported, never treated as the published release
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r"}}],
 "GET /repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"draft":true}}]}}'; gh_hosts
ft_run release-get --url "$UG2" --tag v1
ft_has "H3 draft flagged" "$FT_OUT" "draft=true"
# H3b release-ensure: an existing DRAFT for the tag is a mismatch (FAIL), never "kept"
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r"}}],
 "GET /repos/o/r/git/ref/tags/v1":[{"status":200,"body":{"ref":"refs/tags/v1","object":{"type":"commit","sha":"'$SHA'"}}}],
 "GET /repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"draft":true,"target_commitish":"'$SHA'"}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_ok "H3b draft: rc FAIL" "$FT_RC" 1
ft_has "H3b reason" "$FT_OUT" "REASON: present_mismatch"
ft_lacks "H3b never kept" "$FT_OUT" "ACTION: kept"

# ---- round 2 (independent review 2026-11-12: I2, I6 N18, M1, M4) ----
GREPO='"GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r"}}]'
GREF_C='"GET /repos/o/r/git/ref/tags/v1":[{"status":200,"body":{"ref":"refs/tags/v1","object":{"type":"commit","sha":"'$SHA'"}}}]'
# H4 (I2) a tag of a tag of a tag (the commit is never reached) and target "main": neither the tag nor the release target can be tied to the commit: never "OK"
ft_server '{"routes":{'"$GREPO"',
 "GET /repos/o/r/git/ref/tags/v1":[{"status":200,"body":{"ref":"refs/tags/v1","object":{"type":"tag","sha":"2222222222222222222222222222222222222222"}}}],
 "GET /repos/o/r/git/tags/2222222222222222222222222222222222222222":[{"status":200,"body":{"object":{"type":"tag","sha":"3333333333333333333333333333333333333333"}}}],
 "GET /repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"target_commitish":"main","draft":false}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_ok "H4 unverified commit: rc 5" "$FT_RC" 5
ft_has "H4 reason" "$FT_OUT" "REASON: commit_unverified"
ft_has "H4 result" "$FT_OUT" "RESULT: UNVERIFIED-COMMIT"
ft_lacks "H4 never OK" "$FT_OUT" "RESULT: OK"
# H4b positive control: the same tag with release target = the sha is OK
ft_server '{"routes":{'"$GREPO"',
 "GET /repos/o/r/git/ref/tags/v1":[{"status":200,"body":{"ref":"refs/tags/v1","object":{"type":"tag","sha":"2222222222222222222222222222222222222222"}}}],
 "GET /repos/o/r/git/tags/2222222222222222222222222222222222222222":[{"status":200,"body":{"object":{"type":"tag","sha":"3333333333333333333333333333333333333333"}}}],
 "GET /repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'","draft":false}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
# round 3 (review R2-I1): this was the round-2 "positive control" and asserted a false pass. GitHub documents
# target_commitish as "unused if the Git tag already exists": equal to --sha it proves nothing about the tag
ft_ok "H4b target = sha, tag unverified: rc 5" "$FT_RC" 5
ft_has "H4b echo noted" "$FT_OUT" "NOTE: target_echo_only"
ft_lacks "H4b never OK" "$FT_OUT" "RESULT: OK"

# N18 (I6) git/ref answers with ANOTHER ref (prefix match, refs/tags/v1-rc): the tag is absent, not v1
ft_server '{"routes":{'"$GREPO"',
 "GET /repos/o/r/git/ref/tags/v1":[{"status":200,"body":{"ref":"refs/tags/v1-rc","object":{"type":"commit","sha":"'$SHA'"}}}]}}'; gh_hosts
ft_run tag-get --url "$UG2" --tag v1
ft_has "N18 other ref: tag absent" "$FT_OUT" "TAG: absent"
ft_lacks "N18 sha not reported" "$FT_OUT" "TAG: present"

# M1 a 422 on create is "exists" only with errors[].code already_exists
ft_server '{"routes":{'"$GREPO"','"$GREF_C"',
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}}],
 "GET /repos/o/r/releases":[{"status":200,"body":[]}],
 "POST /repos/o/r/releases":[{"status":422,"body":{"message":"Validation Failed","errors":[{"resource":"Release","code":"invalid","field":"target_commitish"}]}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_ok "M1 422 invalid: rc API" "$FT_RC" 4
ft_has "M1 reason" "$FT_OUT" "REASON: unexpected_status_422"
ft_server '{"routes":{'"$GREPO"','"$GREF_C"',
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":200,"body":{"id":3,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'","draft":false}}],
 "GET /repos/o/r/releases":[{"status":200,"body":[]}],
 "POST /repos/o/r/releases":[{"status":422,"body":{"message":"Validation Failed","errors":[{"resource":"Release","code":"already_exists","field":"tag_name"}]}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_ok "M1b 422 already_exists: rc 0" "$FT_RC" 0
ft_lacks "M1b not created" "$FT_OUT" "ACTION: created"

# M4 a 404 by tag but a DRAFT of the tag in the list: reported as a draft mismatch, nothing created
ft_server '{"routes":{'"$GREPO"','"$GREF_C"',
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}}],
 "GET /repos/o/r/releases":[{"status":200,"body":[{"id":8,"tag_name":"v0","draft":false},{"id":9,"tag_name":"v1","draft":true,"prerelease":true,"target_commitish":"'$SHA'"}]}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":10}}]}}'; gh_hosts
ft_run release-ensure --url "$UG2" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_has "M4 draft found" "$FT_OUT" "NOTE: draft_found"
ft_ok "M4 rc FAIL" "$FT_RC" 1
ft_has "M4 reason" "$FT_OUT" "REASON: present_mismatch"
ft_ok "M4 no POST" "$(ft_req_count POST)" 0
ft_run release-get --url "$UG2" --tag v1
ft_has "M4b release-get shows the draft" "$FT_OUT" "RELEASE: present id=9"

# ---- gitlab ----
FT_ENV=(TEST_GL_TOKEN=glTESTtokenQwErTyUiOpAsDfGhghij)
UL=git@gitlab.test:grp/sub/proj.git
gl_hosts() { ft_hosts "gitlab.test${T}gitlab${T}http://127.0.0.1:@PORT@/api/v4${T}TEST_GL_TOKEN${T}-"; }
ft_server '{"routes":{
 "GET /api/v4/projects/grp%2Fsub%2Fproj":[{"status":200,"body":{"path_with_namespace":"grp/sub/proj"}}],
 "GET /api/v4/projects/grp%2Fsub%2Fproj/repository/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"id":"'$SHA'"}}}],
 "GET /api/v4/projects/grp%2Fsub%2Fproj/releases/v1":[{"status":404,"body":{}},{"status":200,"body":{"tag_name":"v1","commit":{"id":"'$SHA'"}}}],
 "POST /api/v4/projects/grp%2Fsub%2Fproj/releases":[{"status":201,"body":{"tag_name":"v1"}}]}}'; gl_hosts
ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --prerelease
ft_ok "L1 rc" "$FT_RC" 0
ft_has "L1 PRIVATE-TOKEN header" "$(ft_reqs)" '"PRIVATE-TOKEN": "glTESTtoken'
ft_has "L1 path url-encoded" "$(ft_reqs)" 'grp%2Fsub%2Fproj'
ft_has "L1 created" "$FT_OUT" "ACTION: created"
ft_has "L1 prerelease unsupported noted" "$FT_OUT" "NOTE: prerelease_unsupported"
ft_has "L1 readback" "$FT_OUT" "READBACK: ok"
ft_lacks "L1 no Authorization header sent" "$(ft_reqs)" '"Authorization"'

# L2 (live finding 2026-11-12, docs/qa/multiforge_2026_11_12/readpaths.txt): a GitLab release is addressed by
# its TAG, and tags carry dots; the id check must accept it (it reported "id=invalid") and --update must work
TV=lab-v1.2.3
ft_server '{"routes":{
 "GET /api/v4/projects/grp%2Fsub%2Fproj":[{"status":200,"body":{"path_with_namespace":"grp/sub/proj"}}],
 "GET /api/v4/projects/grp%2Fsub%2Fproj/repository/tags/'$TV'":[{"status":200,"body":{"name":"'$TV'","commit":{"id":"'$SHA'"}}}],
 "GET /api/v4/projects/grp%2Fsub%2Fproj/releases/'$TV'":[{"status":200,"body":{"tag_name":"'$TV'","commit":{"id":"1111111111111111111111111111111111111111"}}},{"status":200,"body":{"tag_name":"'$TV'","commit":{"id":"1111111111111111111111111111111111111111"}}},{"status":200,"body":{"tag_name":"'$TV'","commit":{"id":"'$SHA'"}}}],
 "PUT /api/v4/projects/grp%2Fsub%2Fproj/releases/'$TV'":[{"status":200,"body":{"tag_name":"'$TV'"}}]}}'; gl_hosts
ft_run release-get --url "$UL" --tag "$TV"
ft_has "L2 dotted tag id shown" "$FT_OUT" "RELEASE: present id=$TV"
ft_run release-ensure --url "$UL" --tag "$TV" --sha "$SHA" --notes-file "$FT_SBX/notes.md" --update
ft_ok "L2 update rc" "$FT_RC" 0
ft_has "L2 updated" "$FT_OUT" "ACTION: updated"
ft_ok "L2 one PUT" "$(ft_req_count PUT)" 1

# N11 (I6) GitLab answers 409 to create (the release exists): read back, kept, never "created"
ft_server '{"routes":{
 "GET /api/v4/projects/grp%2Fsub%2Fproj":[{"status":200,"body":{"path_with_namespace":"grp/sub/proj"}}],
 "GET /api/v4/projects/grp%2Fsub%2Fproj/repository/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"id":"'$SHA'"}}}],
 "GET /api/v4/projects/grp%2Fsub%2Fproj/releases/v1":[{"status":404,"body":{}},{"status":200,"body":{"tag_name":"v1","commit":{"id":"'$SHA'"}}}],
 "POST /api/v4/projects/grp%2Fsub%2Fproj/releases":[{"status":409,"body":{"message":"Release already exists"}}]}}'; gl_hosts
ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "N11 409: rc 0" "$FT_RC" 0
ft_lacks "N11 not created" "$FT_OUT" "ACTION: created"
ft_has "N11 kept" "$FT_OUT" "ACTION: kept"

# L3 (round 3, R2-I1) GitLab DERIVES the release commit.id from the tag: a release already present whose
# commit.id equals --sha proves the commit even when the tag call reports none (rc 0, real and dry-run alike)
GLR='"GET /api/v4/projects/grp%2Fsub%2Fproj":[{"status":200,"body":{"path_with_namespace":"grp/sub/proj"}}],"GET /api/v4/projects/grp%2Fsub%2Fproj/repository/tags/v1":[{"status":200,"body":{"name":"v1"}}]'
ft_server '{"routes":{'"$GLR"',"GET /api/v4/projects/grp%2Fsub%2Fproj/releases/v1":[{"status":200,"body":{"tag_name":"v1","commit":{"id":"'$SHA'"}}}]}}'; gl_hosts
ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "L3 derived target of a present release: rc 0" "$FT_RC" 0
ft_has "L3 tag commit not reported" "$FT_OUT" "NOTE: tag_sha_unverified"
ft_has "L3 kept" "$FT_OUT" "ACTION: kept"
ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --dry-run
ft_ok "L3 dry-run the same" "$FT_RC" 0
# L3b the derived target belongs to ANOTHER commit: a mismatch, never OK
ft_server '{"routes":{'"$GLR"',"GET /api/v4/projects/grp%2Fsub%2Fproj/releases/v1":[{"status":200,"body":{"tag_name":"v1","commit":{"id":"1111111111111111111111111111111111111111"}}}]}}'; gl_hosts
ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "L3b derived target differs: rc 1" "$FT_RC" 1
# L3c the release is ABSENT and created: the read-back commit.id comes after the write, so it does not change
# the verdict fixed before the write (rc 5); the dry-run of the same state says the same (rc 5)
gl3c() { ft_server '{"routes":{'"$GLR"',"GET /api/v4/projects/grp%2Fsub%2Fproj/releases/v1":[{"status":404,"body":{}},{"status":200,"body":{"tag_name":"v1","commit":{"id":"'$SHA'"}}}],
 "POST /api/v4/projects/grp%2Fsub%2Fproj/releases":[{"status":201,"body":{"tag_name":"v1"}}]}}'; gl_hosts; }
gl3c; ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "L3c created on an unverified tag: rc 5" "$FT_RC" 5
ft_has "L3c created" "$FT_OUT" "ACTION: created"
gl3c; ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --dry-run
ft_ok "L3c dry-run: rc 5 too" "$FT_RC" 5
# L3d (review m5, W14) the create answers "exists" (409) and the release read back AFTER that answer has a
# derived commit.id equal to --sha: the guide's row "(a) only" -- the read-back after a write attempt does not
# raise the verdict fixed before it, so an unverified tag still ends UNVERIFIED-COMMIT (rc 5), never OK
ft_server '{"routes":{'"$GLR"',"GET /api/v4/projects/grp%2Fsub%2Fproj/releases/v1":[{"status":404,"body":{}},{"status":200,"body":{"tag_name":"v1","commit":{"id":"'$SHA'"}}}],
 "POST /api/v4/projects/grp%2Fsub%2Fproj/releases":[{"status":409,"body":{"message":"Release already exists"}}]}}'; gl_hosts
ft_run release-ensure --url "$UL" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "L3d exists after create, derived target read after the write: rc 5" "$FT_RC" 5
ft_has "L3d kept" "$FT_OUT" "ACTION: kept"

ft_done
