#!/usr/bin/env bash
# tests/forge/test_forge_gitverse.sh -- unit tests of the gitverse provider (GitHub-shaped own API with a
# mandatory versioned Accept header; the release list answers 404 REPO_NOT_FOUND for a repo that exists).
# CLASS (section 11.4.289(C)(2)): gate-logic / unit against the loopback fixture server; the write paths
# are LIVE-UNPROVEN.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/forge/lib.sh
. "$HERE/lib.sh"
ft_init
T=$'\t'
SHA=0123456789abcdef0123456789abcdef01234567
FT_ENV=(TEST_GITVERSE_TOKEN=gitverseTESTtokenQwErTyUiOpAsDfGh)
U=git@gitverse.test:o/r.git
printf 'notes\n' >"$FT_SBX/notes.md"
hosts() { ft_hosts "gitverse.test${T}gitverse${T}http://127.0.0.1:@PORT@${T}TEST_GITVERSE_TOKEN${T}-"; }
REPO='"GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r","permissions":{"admin":true}}}]'
AMBIG='"GET /repos/o/r/releases":[{"status":404,"body":{"code":"REPO_NOT_FOUND","message":"not found"}}],"GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{"code":"RELEASE_OR_TAG_NOT_FOUND"}}]'
TAG='"GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v1","object":{"type":"commit","sha":"'$SHA'"}}]}]'
ensure() { ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" "$@"; }

# V1 the ambiguous 404 is a GAP releases_unsupported_or_empty, never "absent" and never success
ft_server '{"routes":{'"$REPO"','"$AMBIG"','"$TAG"'}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "V1 rc GAP" "$FT_RC" 3
ft_has "V1 reason" "$FT_OUT" "REASON: releases_unsupported_or_empty"
ft_lacks "V1 not absent" "$FT_OUT" "RELEASE: absent"
ft_has "V1 Accept header sent" "$(ft_reqs)" 'application/vnd.gitverse.object+json;version=1'
ft_has "V1 Bearer auth" "$(ft_reqs)" '"Authorization": "Bearer gitverseTESTtoken'
ensure --prerelease
ft_ok "V1b ensure rc GAP" "$FT_RC" 3
ft_has "V1b reason" "$FT_OUT" "REASON: releases_unsupported_or_empty"
ft_ok "V1b no write without opt-in" "$(ft_req_count POST)" 0

# V2 --try-create-on-ambiguous: create, then the read-back decides
ft_server '{"routes":{'"$REPO"','"$TAG"',
 "GET /repos/o/r/releases":[{"status":404,"body":{"code":"REPO_NOT_FOUND"}}],
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{"code":"RELEASE_OR_TAG_NOT_FOUND"}},{"status":200,"body":{"id":5,"tag_name":"v1","prerelease":true}}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":5}}]}}'; hosts
ensure --prerelease --try-create-on-ambiguous
ft_ok "V2 rc" "$FT_RC" 0
ft_has "V2 notice" "$FT_ERR" "NOTICE: release list is ambiguous"
ft_has "V2 created" "$FT_OUT" "ACTION: created"
ft_has "V2 readback" "$FT_OUT" "READBACK: ok"
# a failed create on the ambiguous state stays the GAP (never success)
ft_server '{"routes":{'"$REPO"','"$TAG"','"$AMBIG"',"POST /repos/o/r/releases":[{"status":404,"body":{"code":"REPO_NOT_FOUND"}}]}}'; hosts
ensure --prerelease --try-create-on-ambiguous
ft_ok "V2b create refused: rc GAP" "$FT_RC" 3
ft_has "V2b reason" "$FT_OUT" "REASON: releases_unsupported_or_empty"
# a 201 that cannot be read back: FAIL
ft_server '{"routes":{'"$REPO"','"$TAG"','"$AMBIG"',"POST /repos/o/r/releases":[{"status":201,"body":{"id":5}}]}}'; hosts
ensure --prerelease --try-create-on-ambiguous
ft_ok "V2c 201 without read-back: rc FAIL" "$FT_RC" 1

# V3 a working list (200 []) with tag lookup 404 is a real "absent"
ft_server '{"routes":{'"$REPO"',"GET /repos/o/r/releases":[{"status":200,"body":[]}],"GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}}]}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "V3 rc" "$FT_RC" 0
ft_has "V3 absent" "$FT_OUT" "RELEASE: absent"

# V4 prerelease not reported by the server: read-back notes it as unverified, never claims it
ft_server '{"routes":{'"$REPO"','"$TAG"',"GET /repos/o/r/releases":[{"status":200,"body":[]}],
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":200,"body":{"id":5,"tag_name":"v1"}}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":5}}]}}'; hosts
ensure --prerelease
ft_ok "V4 rc" "$FT_RC" 0
ft_has "V4 prerelease unverified note" "$FT_OUT" "NOTE: prerelease_unverified"

# V5 415 (Accept header missing upstream) is an API failure, not success
ft_server '{"routes":{"GET /repos/o/r":[{"status":415,"body":{}}]}}'; hosts
ft_run repo-exists --url "$U"
ft_ok "V5 rc API" "$FT_RC" 4

# V6 tag-get through matching-refs; an annotated tag is dereferenced once
ft_server '{"routes":{'"$REPO"',
 "GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v10","object":{"type":"commit","sha":"1111111111111111111111111111111111111111"}},{"ref":"refs/tags/v1","object":{"type":"tag","sha":"2222222222222222222222222222222222222222"}}]}],
 "GET /repos/o/r/git/tags/2222222222222222222222222222222222222222":[{"status":200,"body":{"object":{"type":"commit","sha":"'$SHA'"}}}]}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "V6 annotated tag dereferenced (and v10 not mistaken for v1)" "$FT_OUT" "TAG: present sha=$SHA"

# V7 (live finding 2026-11-12, docs/qa/multiforge_2026_11_12/readpaths.txt): GitVerse answers 400 to
# git/tags/{sha}, so an annotated tag's commit cannot be read. The tag is reported PRESENT with an
# UNVERIFIED commit, never as a page-cap gap and never with a guessed sha.
ft_server '{"routes":{'"$REPO"',
 "GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v1","object":{"type":"tag","sha":"2222222222222222222222222222222222222222"}}]}],
 "GET /repos/o/r/git/tags/2222222222222222222222222222222222222222":[{"status":400,"body":{"error":{"code":"VALIDATION_ERROR"}}}]}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_ok "V7 rc" "$FT_RC" 0
ft_has "V7 present, commit unverified" "$FT_OUT" "TAG: present sha=unknown"
ft_lacks "V7 no page-cap reason" "$FT_OUT" "readback_page_cap"
ft_lacks "V7 the tag-object sha is never shown as the commit" "$FT_OUT" "sha=2222222222222222222222222222222222222222"

# V8 (I2, review 2026-11-12) the V7 annotated tag (commit unreadable) and a release whose target is "main":
# nothing ties the release to the commit, so release-ensure never ends OK (rc 5 UNVERIFIED-COMMIT)
ATAG='"GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v1","object":{"type":"tag","sha":"2222222222222222222222222222222222222222"}}]}],"GET /repos/o/r/git/tags/2222222222222222222222222222222222222222":[{"status":400,"body":{"error":{"code":"VALIDATION_ERROR"}}}]'
rel() { printf '"GET /repos/o/r/releases":[{"status":200,"body":[]}],"GET /repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":5,"tag_name":"v1","prerelease":true,"draft":false,"target_commitish":"%s"}}]' "$1"; }
ft_server '{"routes":{'"$REPO"','"$ATAG"','"$(rel main)"'}}'; hosts
ensure --prerelease
ft_ok "V8 rc 5" "$FT_RC" 5
ft_has "V8 reason" "$FT_OUT" "REASON: commit_unverified"
ft_ok "V8 last line" "$(printf '%s\n' "$FT_OUT" | tail -1)" "RESULT: UNVERIFIED-COMMIT"
ft_lacks "V8 never OK" "$FT_OUT" "RESULT: OK"
ensure --prerelease --dry-run
ft_ok "V8 dry-run rc 5 too" "$FT_RC" 5
# V8b (round 3, review finding R2-I1; corrects the round-2 "positive control", which asserted a false pass):
# a GitVerse release target equal to --sha is only the value that was SENT (target_commitish is a stored
# request field there, as on GitHub, not where the tag points), so with the tag's commit unverified the run
# is UNVERIFIED-COMMIT, never OK; the note says why
ft_server '{"routes":{'"$REPO"','"$ATAG"','"$(rel "$SHA")"'}}'; hosts
ensure --prerelease
ft_ok "V8b target = sha but tag unverified: rc 5" "$FT_RC" 5
ft_has "V8b echo noted" "$FT_OUT" "NOTE: target_echo_only"
ft_lacks "V8b never OK" "$FT_OUT" "RESULT: OK"
ensure --prerelease --dry-run
ft_ok "V8b dry-run rc 5 too" "$FT_RC" 5
# V8c positive control: the tag's commit IS verified (lightweight tag) and the target is "main": OK
ft_server '{"routes":{'"$REPO"','"$TAG"','"$(rel main)"'}}'; hosts
ensure --prerelease
ft_ok "V8c verified tag commit: rc 0" "$FT_RC" 0
ft_has "V8c OK" "$FT_OUT" "RESULT: OK"

# Q1 (review R2-I1, RED on aefc2049: rc 0) the tool creates the release on an annotated tag whose commit
# cannot be read; the read-back target is the very value the tool sent. That echo is no proof: rc 5 in the
# real run, and the same rc 5 in a dry-run of the same state (the verdict is fixed before any write)
q1() { ft_server '{"routes":{'"$REPO"','"$ATAG"',
 "GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":200,"body":{"id":5,"tag_name":"v1","prerelease":false,"draft":false,"target_commitish":"'$SHA'"}}],
 "GET /repos/o/r/releases":[{"status":200,"body":[]}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":5}}]}}'; hosts; }
q1; ensure
ft_ok "Q1 echo of own target: rc 5" "$FT_RC" 5
ft_has "Q1 the write did happen" "$FT_OUT" "ACTION: created"
ft_has "Q1 read back" "$FT_OUT" "READBACK: ok"
ft_ok "Q1 last line" "$(printf '%s\n' "$FT_OUT" | tail -1)" "RESULT: UNVERIFIED-COMMIT"
q1; ensure --dry-run
ft_ok "Q1 dry-run of the same state: rc 5 (no disagreement)" "$FT_RC" 5
ft_has "Q1 dry-run would-create" "$FT_OUT" "ACTION: would-create"
ft_ok "Q1 dry-run wrote nothing" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) + $(ft_req_count PUT) ))" 0

# Q5 (review X09) --dry-run --update on a present release that differs: no PATCH, "would-update"
ft_server '{"routes":{'"$REPO"','"$TAG"',"GET /repos/o/r/releases":[{"status":200,"body":[]}],
 "GET /repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":5,"tag_name":"v1","prerelease":false,"draft":false,"target_commitish":"main"}}],
 "PATCH /repos/o/r/releases/5":[{"status":200,"body":{}}]}}'; hosts
ensure --prerelease --update --dry-run
ft_has "Q5 would-update" "$FT_OUT" "ACTION: would-update"
ft_ok "Q5 dry-run update: no write" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) + $(ft_req_count PUT) ))" 0
ft_ok "Q5 rc 0 (tag commit verified)" "$FT_RC" 0
ensure --prerelease --update
ft_ok "Q5b control: without --dry-run the PATCH is sent" "$(ft_req_count PATCH)" 1

# Q4 (review probe) --try-create-on-ambiguous --dry-run on the ambiguous GitVerse 404: never a write
ft_server '{"routes":{'"$REPO"','"$TAG"',"GET /repos/o/r/releases/tags/v1":[{"status":404,"body":{}}],"GET /repos/o/r/releases":[{"status":404,"body":{}}],
 "POST /repos/o/r/releases":[{"status":201,"body":{"id":5}}]}}'; hosts
ensure --try-create-on-ambiguous --dry-run
ft_ok "Q4 dry-run ambiguous: no write" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) + $(ft_req_count PUT) ))" 0

# Q2 / Q2b / Q3 (review R2-I2, RED on aefc2049) a server that reflects the token value in a request-id header
# (X-Request-Id, X-Trace-Id) or as a JSON key name: never printed, in PROBE lines, PEER lines or messages
TOKV=gitverseTESTtokenQwErTyUiOpAsDfGh
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"headers":{"X-Request-Id":"'$TOKV'"},"body":{"full_name":"o/r"}}],
 "GET /repos/o/r/releases":[{"status":200,"headers":{"X-Request-Id":"'$TOKV'"},"body":[]}],
 "GET /repos/o/r/git/matching-refs/tags/":[{"status":200,"headers":{"X-Request-Id":"'$TOKV'"},"body":[]}]}}'; hosts
ft_run probe --url "$U"
ft_lacks "Q2 reflected token not printed by probe" "$FT_OUT$FT_ERR" "$TOKV"
ft_lacks "Q2 nor a 12-character part of it" "$FT_OUT$FT_ERR" "${TOKV:5:12}"
ft_has "Q2 the field is shown as unsafe" "$FT_OUT" "request_id=x-request-id=unsafe"
ft_has "Q2 control: the probe ran" "$FT_OUT" "PROBE: repo status=200"
FT_ENV=(TEST_GITVERSE_TOKEN="$TOKV" FORGE_TRACE_PEER=1)
ft_run release-get --url "$U" --tag v1
ft_lacks "Q2b reflected token not printed in PEER lines" "$FT_OUT$FT_ERR" "$TOKV"
ft_has "Q2b control: PEER lines printed" "$FT_OUT" "PEER: GET /repos/o/r status=200"
FT_ENV=(TEST_GITVERSE_TOKEN="$TOKV")
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"headers":{"X-Trace-Id":"ab'$TOKV'"},"body":{"full_name":"o/r"}}]}}'; hosts
ft_run probe --url "$U"
ft_lacks "Q3 x-trace-id reflection (token inside a longer id) not printed" "$FT_OUT$FT_ERR" "$TOKV"
# a part of the token reflected (the server cut it): still caught
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"headers":{"X-Request-Id":"'${TOKV:3:14}'"},"body":{"full_name":"o/r"}}]}}'; hosts
ft_run probe --url "$U"
ft_lacks "Q3b a 14-character part of the token not printed" "$FT_OUT$FT_ERR" "${TOKV:3:14}"
# a JSON KEY NAME that is the token (the probe prints key names): scrubbed by the central sanitiser
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"body":{"full_name":"o/r","'$TOKV'":1}}]}}'; hosts
ft_run probe --url "$U"
ft_lacks "Q3c token as a JSON key name not printed" "$FT_OUT$FT_ERR" "$TOKV"
ft_has "Q3c the word holding it is shown as unsafe, the key kept" "$FT_OUT" "object keys=unsafe"
# a value of ANOTHER host's token variable (from the environment) reflected: caught too
OTOKV=githubOTHERtokenQwErTyUiOpAsDfGhXYZ
FT_ENV=(TEST_GITVERSE_TOKEN="$TOKV" SOME_OTHER_TOKEN="$OTOKV")
ft_server '{"routes":{"GET /repos/o/r":[{"status":200,"headers":{"X-Request-Id":"'$OTOKV'"},"body":{"full_name":"o/r"}}]}}'; hosts
ft_run probe --url "$U"
ft_lacks "Q3d another variable's token reflected: not printed" "$FT_OUT$FT_ERR" "$OTOKV"
FT_ENV=(TEST_GITVERSE_TOKEN="$TOKV")

# G1-G8 (CON-PENDINGgv, live finding 2026-11-16, release rehearsal B-M6): GitVerse answers 400 to
# git/tags/{sha}, but GET /repos/{o}/{r}/commits/{tag-object-sha} answers 200 with the PEELED commit (live,
# read-only, helixconstitution-v73.3: tag object e915eef..., commit aa5ae0a..., equal to `git ls-remote`
# refs/tags/T^{}). The matching-refs answer itself names that URL in object.url. So the annotated tag's commit
# IS readable: the forge peels it server-side from the tag-object sha (never from the tag NAME, which a branch
# of the same name could shadow). Only a 200 whose sha is a full commit id DIFFERENT from the tag-object sha counts.
GOBJ=2222222222222222222222222222222222222222
GTAG='"GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v1","object":{"type":"tag","sha":"'$GOBJ'"}}]}],"GET /repos/o/r/git/tags/'$GOBJ'":[{"status":400,"body":{"error":{"code":"VALIDATION_ERROR"}}}]'
gcommit() { printf '"GET /repos/o/r/commits/%s":[{"status":%s,"body":%s}]' "$GOBJ" "$1" "$2"; }
# G1 the peeled commit is read through commits/{tag-object-sha}
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 200 '{"sha":"'$SHA'"}')"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_ok "G1 rc" "$FT_RC" 0
ft_has "G1 annotated tag commit read via commits/{tag-object-sha}" "$FT_OUT" "TAG: present sha=$SHA"
ft_has "G1 the request used the tag-object sha" "$(ft_reqs)" "/repos/o/r/commits/$GOBJ"
ft_lacks "G1 never by tag name" "$(ft_reqs)" "/repos/o/r/commits/v1"
# G2 release-ensure on the ambiguous release list (the live v73.3 state) now ends OK in a dry-run: the commit
# was verified BEFORE any write (this exact state ended rc 5 UNVERIFIED-COMMIT before the fix)
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 200 '{"sha":"'$SHA'"}')"','"$AMBIG"'}}'; hosts
ensure --try-create-on-ambiguous --dry-run
ft_ok "G2 dry-run rc 0" "$FT_RC" 0
ft_has "G2 tag commit shown" "$FT_OUT" "TAG: present sha=$SHA"
ft_has "G2 would-create" "$FT_OUT" "ACTION: would-create"
ft_lacks "G2 not unverified" "$FT_OUT" "tag_sha_unverified"
ft_ok "G2 dry-run wrote nothing" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) + $(ft_req_count PUT) ))" 0
# G3 the forge's peeled commit differs from --sha: FAIL tag_sha_mismatch (rc 1), never OK
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 200 '{"sha":"3333333333333333333333333333333333333333"}')"','"$AMBIG"'}}'; hosts
ensure --try-create-on-ambiguous --dry-run
ft_ok "G3 mismatch rc 1" "$FT_RC" 1
ft_has "G3 reason" "$FT_OUT" "REASON: tag_sha_mismatch"
# G4 the commits endpoint echoes the tag-object sha: not a commit of the tag, stays unverified
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 200 '{"sha":"'$GOBJ'"}')"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "G4 echo of the tag-object sha is unknown" "$FT_OUT" "TAG: present sha=unknown"
ft_lacks "G4 tag-object sha never shown as the commit" "$FT_OUT" "sha=$GOBJ"
# G5 commits/{sha} refused (422, as GitVerse answers for an unknown object): unverified, rc 5 on ensure
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 422 '{"error":{"code":"UNPROCESSABLE_ENTITY"}}')"','"$(rel "$SHA")"'}}'; hosts
ensure --prerelease
ft_ok "G5 refused commit lookup: rc 5" "$FT_RC" 5
ft_has "G5 unverified note" "$FT_OUT" "NOTE: tag_sha_unverified"
# G5b a non-200 answer that still carries a commit-shaped sha is never read as the tag's commit
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 404 '{"sha":"'$SHA'"}')"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "G5b non-200 body sha ignored" "$FT_OUT" "TAG: present sha=unknown"
# G6 a 200 whose sha is not a full lowercase commit id: unverified
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 200 '{"sha":"aa5ae0a"}')"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "G6 short sha is unknown" "$FT_OUT" "TAG: present sha=unknown"
# G7 a 200 with no sha field: unverified
ft_server '{"routes":{'"$REPO"','"$GTAG"','"$(gcommit 200 '{"url":"x"}')"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "G7 no sha field is unknown" "$FT_OUT" "TAG: present sha=unknown"
# G8 git/tags/{sha} works (a future GitVerse): it is used and the commits lookup is not needed
ft_server '{"routes":{'"$REPO"',
 "GET /repos/o/r/git/matching-refs/tags/v1":[{"status":200,"body":[{"ref":"refs/tags/v1","object":{"type":"tag","sha":"'$GOBJ'"}}]}],
 "GET /repos/o/r/git/tags/'$GOBJ'":[{"status":200,"body":{"object":{"type":"commit","sha":"'$SHA'"}}}],
 '"$(gcommit 200 '{"sha":"3333333333333333333333333333333333333333"}')"'}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "G8 git/tags answer used" "$FT_OUT" "TAG: present sha=$SHA"
ft_lacks "G8 commits lookup not made" "$(ft_reqs)" "/repos/o/r/commits/"

# S1 (review R2-I1, structural) release-ensure reaches OK at exactly one place: fg_end_ensure, which needs
# FG_COMMIT_OK. Count the "fg_end OK" calls after the definition line of fg_end_ensure: exactly one.
ft_ok "S1 one OK exit in release-ensure" "$(sed -n '/^fg_end_ensure() {/,$p' "$FORGE" | grep -c 'fg_end OK')" 1
# shellcheck disable=SC2016  # a literal source-text pattern
ft_ok "S1 that exit is guarded by FG_COMMIT_OK" "$(sed -n '/^fg_end_ensure() {/,$p' "$FORGE" | grep -c 'if \[ "\$FG_COMMIT_OK" = 1 \]; then fg_end OK 0; fi')" 1
ft_ok "S1 control: the definition is found" "$(grep -c '^fg_end_ensure() {' "$FORGE")" 1

ft_done
