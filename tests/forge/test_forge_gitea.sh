#!/usr/bin/env bash
# tests/forge/test_forge_gitea.sh -- unit tests of the gitea provider (Gitea and Forgejo: m3w, Codeberg).
# CLASS (section 11.4.289(C)(2)): gate-logic / unit against the loopback fixture server; the write paths
# (create, update, the --enable-releases settings change) are proven here only and are LIVE-UNPROVEN.
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/forge/lib.sh
. "$HERE/lib.sh"
ft_init
T=$'\t'
SHA=0123456789abcdef0123456789abcdef01234567
FT_ENV=(TEST_GITEA_TOKEN=giteaTESTtokenQwErTyUiOpAsDfGh)
U=git@gitea.test:o/r.git
printf 'notes body\n' >"$FT_SBX/notes.md"
hosts() { ft_hosts "gitea.test${T}gitea${T}http://127.0.0.1:@PORT@/api/v1${T}TEST_GITEA_TOKEN${T}-"; }
REPO_OK='"GET /api/v1/repos/o/r":[{"status":200,"body":{"full_name":"o/r","has_releases":true}}]'
TAG_OK='"GET /api/v1/repos/o/r/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"sha":"'$SHA'"}}}]'
REL_NONE='"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{"message":"not found"}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'"}}]'
ensure() { ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" "$@"; }

# G1 release present
ft_server '{"routes":{'"$REPO_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'"}}]}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "G1 rc" "$FT_RC" 0
ft_has "G1 present" "$FT_OUT" "RELEASE: present id=11 prerelease=true"
ft_has "G1 target" "$FT_OUT" "target=$SHA"

# G2 release absent (repo has releases) is reported absent, never as present
ft_server '{"routes":{'"$REPO_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{"message":"not found"}}]}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "G2 rc" "$FT_RC" 0
ft_has "G2 absent" "$FT_OUT" "RELEASE: absent"
ft_lacks "G2 not present" "$FT_OUT" "RELEASE: present"

# G3 Codeberg-style: releases unit off -> GAP releases_disabled (release-get and release-ensure)
OFF='"GET /api/v1/repos/o/r":[{"status":200,"body":{"full_name":"o/r","has_releases":false}}],"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{"message":"The target couldn'"'"'t be found."}}]'
ft_server '{"routes":{'"$OFF"','"$TAG_OK"'}}'; hosts
ft_run release-get --url "$U" --tag v1
ft_ok "G3 release-get rc GAP" "$FT_RC" 3
ft_has "G3 reason" "$FT_OUT" "REASON: releases_disabled"
ensure --prerelease
ft_ok "G3b release-ensure rc GAP" "$FT_RC" 3
ft_has "G3b reason" "$FT_OUT" "REASON: releases_disabled"
ft_ok "G3b no write" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) ))" 0

# G4 --enable-releases: one PATCH has_releases:true, read back, then create (the release lookup answers 404
# while the unit is off, 404 again after enabling, then 200 on the read-back)
ft_server '{"routes":{
 "GET /api/v1/repos/o/r":[{"status":200,"body":{"has_releases":false}},{"status":200,"body":{"has_releases":true}}],
 "PATCH /api/v1/repos/o/r":[{"status":200,"body":{"has_releases":true}}],
 '"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":404,"body":{}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'"}}],
 "POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]}}'; hosts
ensure --prerelease --enable-releases
ft_ok "G4 rc" "$FT_RC" 0
ft_has "G4 notice logged" "$FT_ERR" "NOTICE: enabling the Releases unit"
ft_has "G4 patch body" "$(ft_reqs | grep '"PATCH"')" 'has_releases'
ft_has "G4 action" "$FT_OUT" "ACTION: created"
ft_has "G4 readback" "$FT_OUT" "READBACK: ok"
# the settings change is read back: a server that keeps has_releases false makes it a FAIL, not a create
ft_server '{"routes":{
 "GET /api/v1/repos/o/r":[{"status":200,"body":{"has_releases":false}}],
 "PATCH /api/v1/repos/o/r":[{"status":200,"body":{"has_releases":false}}],
 '"$TAG_OK"','"$REL_NONE"'}}'; hosts
ensure --prerelease --enable-releases
ft_ok "G4b enable not read back: rc FAIL" "$FT_RC" 1
ft_has "G4b reason" "$FT_OUT" "REASON: enable_releases_not_confirmed"
ft_ok "G4b no create" "$(ft_req_count POST)" 0

# G5 create + read back; the POST payload carries tag, target sha and prerelease
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"','"$REL_NONE"',"POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]}}'; hosts
ensure --prerelease
ft_ok "G5 rc" "$FT_RC" 0
ft_has "G5 created" "$FT_OUT" "ACTION: created"
ft_has "G5 readback" "$FT_OUT" "READBACK: ok"
P="$(ft_reqs | grep '"POST"')"
ft_has "G5 payload tag" "$P" 'tag_name'
ft_has "G5 payload sha" "$P" "$SHA"
ft_has "G5 payload prerelease" "$P" 'prerelease'
ft_has "G5 notes in payload" "$P" 'notes body'
ft_has "G5 result" "$FT_OUT" "RESULT: OK"

# G6 read-back mismatch: server shows prerelease=false after create -> FAIL
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":false,"target_commitish":"'$SHA'"}}],"POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]}}'; hosts
ensure --prerelease
ft_ok "G6 rc FAIL" "$FT_RC" 1
ft_has "G6 reason" "$FT_OUT" "REASON: readback_mismatch"
# the release still absent after a 201 is a FAIL too
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{}}],"POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]}}'; hosts
ensure --prerelease
ft_ok "G6b readback absent: rc FAIL" "$FT_RC" 1
# target mismatch
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":404,"body":{}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":true,"target_commitish":"ffffffffffffffffffffffffffffffffffffffff"}}],"POST /api/v1/repos/o/r/releases":[{"status":201,"body":{"id":11}}]}}'; hosts
ensure --prerelease
ft_ok "G6c readback target mismatch: rc FAIL" "$FT_RC" 1

# G7 409 on create: re-read once and accept the present release if it matches
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"','"$REL_NONE"',"POST /api/v1/repos/o/r/releases":[{"status":409,"body":{"message":"exists"}}]}}'; hosts
ensure --prerelease
ft_ok "G7 rc" "$FT_RC" 0
ft_has "G7 action" "$FT_OUT" "ACTION: kept"

# G8 present and matching: kept, no write
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'"}}]}}'; hosts
ensure --prerelease
ft_ok "G8 rc" "$FT_RC" 0
ft_has "G8 kept" "$FT_OUT" "ACTION: kept"
ft_ok "G8 no write" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) ))" 0

# G9 present but prerelease differs: FAIL without --update; PATCH with --update
G9S='{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":false,"target_commitish":"'$SHA'"}},{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":true,"target_commitish":"'$SHA'"}}],"PATCH /api/v1/repos/o/r/releases/11":[{"status":200,"body":{"id":11}}]}}'
ft_server "$G9S"; hosts
ensure --prerelease
ft_ok "G9 mismatch without --update: rc FAIL" "$FT_RC" 1
ft_has "G9 reason" "$FT_OUT" "REASON: present_mismatch"
ft_ok "G9 no write" "$(ft_req_count PATCH)" 0
ft_server "$G9S"; hosts
ensure --prerelease --update
ft_ok "G9b --update rc" "$FT_RC" 0
ft_has "G9b updated" "$FT_OUT" "ACTION: updated"

# G10 tag absent on the forge: GAP, never a create (tags arrive by git push only)
ft_server '{"routes":{'"$REPO_OK"',"GET /api/v1/repos/o/r/tags/v1":[{"status":404,"body":{}}],'"$REL_NONE"'}}'; hosts
ensure --prerelease
ft_ok "G10 rc GAP" "$FT_RC" 3
ft_has "G10 reason" "$FT_OUT" "REASON: tag_absent_on_forge"
ft_ok "G10 no create" "$(ft_req_count POST)" 0
# tag present at another commit: FAIL
ft_server '{"routes":{'"$REPO_OK"',"GET /api/v1/repos/o/r/tags/v1":[{"status":200,"body":{"name":"v1","commit":{"sha":"ffffffffffffffffffffffffffffffffffffffff"}}}],'"$REL_NONE"'}}'; hosts
ensure --prerelease
ft_ok "G10b tag at another sha: rc FAIL" "$FT_RC" 1
ft_has "G10b reason" "$FT_OUT" "REASON: tag_sha_mismatch"

# G11 auth failure / unexpected status / redirect / not accessible
ft_server '{"routes":{"GET /api/v1/repos/o/r":[{"status":401,"body":{"message":"unauthorized"}}]}}'; hosts
ft_run repo-exists --url "$U"
ft_ok "G11 401 rc API" "$FT_RC" 4
ft_has "G11 reason" "$FT_OUT" "REASON: auth_failed"
ft_server '{"routes":{"GET /api/v1/repos/o/r":[{"status":404,"body":{"message":"not found"}}]}}'; hosts
ft_run repo-exists --url "$U"
ft_ok "G11b 404 repo rc GAP" "$FT_RC" 3
ft_has "G11b reason" "$FT_OUT" "REASON: not_accessible"
ft_server '{"routes":{"GET /api/v1/repos/o/r":[{"status":302,"headers":{"Location":"http://127.0.0.1:1/x"},"body":{}}]}}'; hosts
ft_run repo-exists --url "$U"
ft_ok "G11c redirect rc API" "$FT_RC" 4
ft_has "G11c reason" "$FT_OUT" "REASON: redirect_refused"
ft_ok "G11c redirect not followed" "$(ft_req_count GET)" 1
ft_server '{"routes":{"GET /api/v1/repos/o/r":[{"status":500,"body":"oops"}]}}'; hosts
ft_run repo-exists --url "$U"
ft_ok "G11d 500 rc API" "$FT_RC" 4

# G12 --dry-run performs no write
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"','"$REL_NONE"'}}'; hosts
ensure --prerelease --dry-run
ft_ok "G12 rc" "$FT_RC" 0
ft_has "G12 would create" "$FT_OUT" "ACTION: would-create"
ft_ok "G12 no write" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) ))" 0

# G13 tag-get, probe, usage errors
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/version":[{"status":200,"body":{"version":"1.22.0"}}],"GET /api/v1/repos/o/r/releases":[{"status":200,"body":[]}],"GET /api/v1/repos/o/r/tags":[{"status":200,"body":[{"name":"v1"}]}]}}'; hosts
ft_run tag-get --url "$U" --tag v1
ft_has "G13 tag sha" "$FT_OUT" "TAG: present sha=$SHA"
ft_run probe --url "$U"
ft_ok "G13 probe rc" "$FT_RC" 0
ft_has "G13 probe version status" "$FT_OUT" "PROBE: version status=200"
ft_has "G13 probe repo peer" "$FT_OUT" "PROBE: repo status=200 peer=127.0.0.1:$FT_PORT http="
ft_has "G13 probe repo keys" "$FT_OUT" "object keys=full_name,has_releases"
ft_ok "G13 probe is read-only" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) + $(ft_req_count PUT) ))" 0
ft_run release-ensure --url "$U" --tag 'v1;x' --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "G13 unsafe tag: rc usage" "$FT_RC" 2
ft_run release-ensure --url "$U" --tag v1 --sha abc --notes-file "$FT_SBX/notes.md"
ft_ok "G13 short sha: rc usage" "$FT_RC" 2
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA"
ft_ok "G13 missing notes: rc usage" "$FT_RC" 2
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md" --asset /etc/hostname
ft_ok "G13 --asset not implemented: rc usage" "$FT_RC" 2

# G14 (I4) endpoint identity: the provider request id is read from the answer headers, an unsafe value is
# replaced, and FORGE_TRACE_PEER=1 prints one PEER line per answer (none without it)
rid() { ft_server '{"routes":{"GET /api/v1/repos/o/r":[{"status":200,"headers":{"X-Request-Id":"'"$1"'"},"body":{"full_name":"o/r","has_releases":true}}]}}'; hosts; }
rid req-42.abc
ft_run repo-exists --url "$U"
ft_lacks "G14 no PEER line without FORGE_TRACE_PEER" "$FT_OUT$FT_ERR" "PEER:"
rid 'bad value;rm'
ft_run probe --url "$U"
ft_has "G14 unsafe request id replaced in the PROBE line" "$FT_OUT" "request_id=x-request-id=unsafe"
ft_lacks "G14 unsafe value not printed" "$FT_OUT$FT_ERR" "bad value;rm"
rid req-43
FT_ENV=(TEST_GITEA_TOKEN=giteaTESTtokenQwErTyUiOpAsDfGh FORGE_TRACE_PEER=1)
ft_run repo-exists --url "$U"
ft_has "G14 PEER line" "$FT_OUT$FT_ERR" "PEER: GET /api/v1/repos/o/r status=200 peer=127.0.0.1:$FT_PORT"
ft_has "G14 PEER request id" "$FT_OUT$FT_ERR" "request_id=x-request-id=req-43"
ft_has "G14 plain http has no certificate" "$FT_OUT$FT_ERR" "cert_sha256=none"
FT_ENV=(TEST_GITEA_TOKEN=giteaTESTtokenQwErTyUiOpAsDfGh)

# N16 (I6) a release whose tag_name is another tag is a mismatch, never "present"
ft_server '{"routes":{'"$REPO_OK"','"$TAG_OK"',"GET /api/v1/repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":11,"tag_name":"v2","prerelease":false,"draft":false,"target_commitish":"'$SHA'"}}]}}'; hosts
ft_run release-ensure --url "$U" --tag v1 --sha "$SHA" --notes-file "$FT_SBX/notes.md"
ft_ok "N16 other tag_name: rc FAIL" "$FT_RC" 1
ft_has "N16 reason" "$FT_OUT" "REASON: present_mismatch"
ft_ok "N16 no write" "$(( $(ft_req_count POST) + $(ft_req_count PATCH) ))" 0

# G15 (round 2, shellcheck SC2218) --enable-releases --dry-run on a repository whose Releases unit is off:
# the dry-run ends through fg_end_ensure (it was called before its definition: "command not found" and the
# run went on to a real PATCH). Nothing is written; the tag's commit is checked, so the end is OK.
ft_server '{"routes":{'"$OFF"','"$TAG_OK"'}}'; hosts
ensure --prerelease --enable-releases --dry-run
ft_ok "G15 rc" "$FT_RC" 0
ft_has "G15 would-create" "$FT_OUT" "ACTION: would-create"
ft_lacks "G15 no command-not-found" "$FT_ERR" "command not found"
ft_ok "G15 no write" "$(( $(ft_req_count PATCH) + $(ft_req_count POST) ))" 0

# G16 (round 3, review X06/X12/X13 + R2-I2) unit tests of _fg_peer_read: the loopback fixture has no TLS, so the
# leaf-certificate parse is driven with a crafted "$FG_TMP/code" file in the layout curl's -w writes (5 value lines,
# then %{certs}). The certificate is a real self-signed test certificate made by openssl here; the expected digest is
# computed independently by openssl (DER sha256). Honest limit: the exact %{certs} text of a real curl run is only
# live-observed (scripts/forge/live_probe.sh), never fixture-proven.
if command -v openssl >/dev/null 2>&1; then
  PR="$FT_SBX/pr"; mkdir -p "$PR/t1" "$PR/t2"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$PR/k.pem" -out "$PR/c1.pem" -days 2 -subj "/CN=leaf.example" >/dev/null 2>&1
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$PR/k2.pem" -out "$PR/c2.pem" -days 2 -subj "/CN=issuer.example" >/dev/null 2>&1
  D1="$(openssl x509 -in "$PR/c1.pem" -outform DER 2>/dev/null | sha256sum)"; D1="${D1%% *}"
  D2="$(openssl x509 -in "$PR/c2.pem" -outform DER 2>/dev/null | sha256sum)"; D2="${D2%% *}"
  FLIB="$(dirname "$FORGE")/lib"
  # pr_run IP SUBJECT HDRLINE SECRET -> FG_PEER_* fields, one per line
  pr_run() {
    { printf '200\n%s\n443\n2\n0\n' "$1"
      printf 'Subject:%s\nIssuer:CN = issuer.example\nCert:\n' "$2"; cat "$PR/c1.pem"
      printf 'Subject:CN = issuer.example\nCert:\n'; cat "$PR/c2.pem"; } >"$PR/t1/code"
    printf 'HTTP/1.1 200 OK\r\n%s\r\n' "$3" >"$PR/t1/hdrs"
    # shellcheck disable=SC2016  # the child script is single-quoted on purpose: it expands in the child
    env -i PATH="$PATH" bash -c '
      FG_TMP="$1"; . "$2/common.sh"; . "$2/http.sh"; FG_TMP="$1"
      FG_SEC_NAMES=(SECRET_TOKEN); FG_SEC_VALS=("$4")
      { IFS= read -r FG_CODE; IFS= read -r FG_PEER_IP; IFS= read -r FG_PEER_PORT; IFS= read -r FG_PEER_HTTP
        IFS= read -r FG_PEER_TLS; } <"$FG_TMP/code"
      _fg_peer_read
      printf "ip=%s\ncert=%s\nsubject=%s\nreqid=%s\n" "$FG_PEER_IP" "$FG_PEER_CERT" "$FG_PEER_SUBJECT" "$FG_PEER_REQID"' \
      pr "$PR/t1" "$FLIB" x "$4"
  }
  SECV=prSECRETvalueKzQwPlMnBvCx
  o="$(pr_run 127.0.0.1 'CN = leaf.example' 'X-Request-Id: abc-123' "$SECV")"
  ft_has "G16 leaf certificate digest = openssl's DER sha256 of the LEAF" "$o" "cert=$D1"
  ft_lacks "G16 never the issuer's digest" "$o" "cert=$D2"
  ft_ok "G16 control: the two test certificates differ" "$([ "$D1" != "$D2" ] && [ -n "$D1" ] && echo y)" y
  ft_has "G16 subject of the leaf, spaces as _" "$o" "subject=CN_=_leaf.example"
  ft_has "G16 clean ip kept" "$o" "ip=127.0.0.1"
  ft_has "G16 request id kept" "$o" "reqid=x-request-id=abc-123"
  o="$(pr_run '127.0.0.1;rm' 'CN = leaf.example' 'X-Request-Id: abc' "$SECV")"
  ft_has "G16 X13 ip outside the charset: unsafe" "$o" "ip=unsafe"
  # shellcheck disable=SC2016  # a literal hostile subject
  o="$(pr_run 127.0.0.1 'CN = $(id)<x>' 'X-Request-Id: abc' "$SECV")"
  ft_has "G16 X12 subject outside the charset: unsafe" "$o" "subject=unsafe"
  o="$(pr_run 127.0.0.1 "CN = ab${SECV:2:14}" 'X-Request-Id: abc' "$SECV")"
  ft_has "G16 a token window in the certificate subject: unsafe" "$o" "subject=unsafe"
  ft_lacks "G16 subject token not printed" "$o" "${SECV:2:14}"
  o="$(pr_run 127.0.0.1 'CN = leaf.example' "X-Request-Id: ${SECV}" "$SECV")"
  ft_has "G16 a token in the request id: unsafe" "$o" "reqid=x-request-id=unsafe"
  o="$(pr_run 127.0.0.1 'CN = leaf.example' 'X-Request-Id: abc' "$SECV")"
  ft_lacks "G16 negative control: nothing marked unsafe on clean input" "$o" "unsafe"
else
  ft_skip "G16 _fg_peer_read certificate unit tests" "openssl_absent"
fi

# G17 (round 3, R2-I1) Gitea stores target_commitish as sent: a present release whose target equals --sha does
# NOT prove the tag's commit when the tag call reports none (rc 5, never OK; dry-run the same)
ft_server '{"routes":{'"$REPO_OK"',"GET /api/v1/repos/o/r/tags/v1":[{"status":200,"body":{"name":"v1"}}],
 "GET /api/v1/repos/o/r/releases/tags/v1":[{"status":200,"body":{"id":11,"tag_name":"v1","prerelease":false,"draft":false,"target_commitish":"'$SHA'"}}]}}'; hosts
ensure
ft_ok "G17 target = sha, tag commit unreported: rc 5" "$FT_RC" 5
ft_has "G17 echo noted" "$FT_OUT" "NOTE: target_echo_only"
ensure --dry-run
ft_ok "G17 dry-run: rc 5" "$FT_RC" 5

ft_done
