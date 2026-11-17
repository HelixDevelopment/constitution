#!/usr/bin/env bash
# test_forge_branch_protect.sh -- hermetic tests for scripts/security/forge_branch_protect.sh.
#
# Purpose: drive the REAL script through its real invocation path against a
# loopback forge fixture (tests/security/fixtures/forge_fixture.py) with PATH
# shims for curl (argv log) and gh (fake keyring token), a fake 0600 keys file
# and a targets file (FORGE_PROTECT_TARGETS_FILE). Asserts exit codes, output
# and the requests seen on the wire: apply gating, the exact request bodies,
# token handling (also under bash -x), de-duplication by content, read-back of
# the protection fields, rate limits, probe failures, missing prerequisites.
# Gate-logic tests only (§11.4.289): they prove the script's decisions, never
# that a real forge accepted anything. No request leaves 127.0.0.1.
#
# Usage: bash tests/security/test_forge_branch_protect.sh
#        FBP_SCRIPT=/path/to/copy bash ...   (run against another copy, e.g. a mutant)
#        SEC_TEST_FAILFAST=1 stops at the first failing case (used by the mutation test)
# Exit: 0 all cases hold; 1 a case failed; 2 environment error.
# shellcheck disable=SC2034  # RC and EXPECT_* are read inside the eval'd check strings
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
SCRIPT="${FBP_SCRIPT:-$here/scripts/security/forge_branch_protect.sh}"
FIX="$here/tests/security/fixtures"
for t in curl jq python3; do command -v "$t" >/dev/null 2>&1 || { echo "env: $t missing" >&2; exit 2; }; done
REAL_CURL="$(command -v curl)"; export REAL_CURL
tmp="$(mktemp -d)"
FPID=""; FPID2=""
cleanup(){ [ -n "$FPID" ] && kill "$FPID" 2>/dev/null; [ -n "$FPID2" ] && kill "$FPID2" 2>/dev/null; wait 2>/dev/null; rm -rf "${tmp:?}"; }
trap cleanup EXIT
export SEC_TEST_LOG="$tmp/log"; mkdir -p "$SEC_TEST_LOG"
SCEN="$tmp/scen.json"; echo '{}' > "$SCEN"
python3 -I "$FIX/forge_fixture.py" "$SCEN" "$SEC_TEST_LOG/req.jsonl" "$tmp/port" & FPID=$!
for _ in $(seq 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
[ -s "$tmp/port" ] || { echo "env: fixture did not start" >&2; exit 2; }
P=$(cat "$tmp/port"); B="http://127.0.0.1:$P"
# A second loopback listener: the target of a redirect and of a proxy variable. Nothing may reach it.
SCEN2="$tmp/scen2.json"; echo '{}' > "$SCEN2"; REQ2="$SEC_TEST_LOG/req2.jsonl"; : > "$REQ2"
python3 -I "$FIX/forge_fixture.py" "$SCEN2" "$REQ2" "$tmp/port2" & FPID2=$!
for _ in $(seq 50); do [ -s "$tmp/port2" ] && break; sleep 0.1; done
[ -s "$tmp/port2" ] || { echo "env: second fixture did not start" >&2; exit 2; }
P2=$(cat "$tmp/port2")

GHTOK=FAKEGH_TOKEN_9f8e7d6c5b4a; M3TOK=FAKEM3W_TOKEN_1a2b3c4d; CBTOK=FAKECB_TOKEN_5e6f7a8b; GLTOK=FAKEGL_TOKEN_0c0d0e0f
export FAKE_GH_TOKEN=$GHTOK
KEYS="$tmp/keys.sh"
printf 'export M3W_GITEA_TOKEN=%s\nexport CODEBERG_GITEA_TOKEN=%s\nexport GITLAB_TOKEN=%s\nexport GITFLIC_TOKEN=FAKEGF_TOKEN_1111\n' "$M3TOK" "$CBTOK" "$GLTOK" > "$KEYS"; chmod 600 "$KEYS"
TF="$tmp/targets"
cat > "$TF" <<EOF
github_hd|github|$B/gh|HelixDevelopment|constitution|-
github_vd|github|$B/ghv|vasic-digital|HelixConstitution|-
gitlab_vd|gitlab|$B/gl/api/v4|vasic-digital|HelixConstitution|GITLAB_TOKEN
m3w|gitea|$B/gt/api/v1|Helix|constitution|M3W_GITEA_TOKEN
codeberg|gitea|$B/cb/api/v1|HelixDevelopment|constitution|CODEBERG_GITEA_TOKEN
gitflic|gitflic|$B/gf|helixdevelopment|helixconstitution|GITFLIC_TOKEN
EOF

n=0; bad=0
ok(){ n=$((n+1)); echo "ok   $n $1"; }
nok(){ n=$((n+1)); bad=$((bad+1)); echo "FAIL $n $1"; if [ "${SEC_TEST_FAILFAST:-}" = 1 ]; then echo "RESULT: failfast at $n"; exit 1; fi; }
check(){ if eval "$2"; then ok "$1"; else nok "$1"; sed 's/^/     | /' "$tmp/out" "$tmp/err" | head -40; fi; }

# run SCENARIO_JSON ARGS... -> RC, $tmp/out, $tmp/err; extra env via RUN_ENV array
declare -a RUN_ENV=()
run(){
  printf '%s' "$1" > "$SCEN"; shift
  : > "$SEC_TEST_LOG/req.jsonl"; : > "$SEC_TEST_LOG/curl_argv.log"; : > "$REQ2"
  : > "$SEC_TEST_LOG/gh_argv.log"; : > "$SEC_TEST_LOG/gh_env.log"
  # Proxy variables of the calling shell are removed; a case that needs one sets it in RUN_ENV.
  env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    PATH="$FIX/bin:$PATH" KEYS_FILE="$KEYS" FORGE_PROTECT_TARGETS_FILE="$TF" FORGE_PROTECT_TEST_LOOPBACK=yes ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
    ${RUN_SHELL:-bash} "$SCRIPT" "$@" > "$tmp/out" 2> "$tmp/err"
  RC=$?
}
APPLY=(FORGE_PROTECT_APPLY=yes FORGE_PROTECT_ALLOW_TARGETS_OVERRIDE=yes)
nreq(){ python3 -I -c 'import json,sys
n=0
for l in open(sys.argv[1]):
    if json.loads(l)["k"].startswith(sys.argv[2]): n+=1
print(n)' "$SEC_TEST_LOG/req.jsonl" "$1"; }
reqbody(){ python3 -I -c 'import json,sys
for l in open(sys.argv[1]):
    d=json.loads(l)
    if d["k"].startswith(sys.argv[2]): print(d["body"])' "$SEC_TEST_LOG/req.jsonl" "$1" | head -1; }
jsoneq(){ python3 -I -c 'import json,sys; sys.exit(0 if json.loads(sys.argv[1])==json.loads(sys.argv[2]) else 1)' "$1" "$2" 2>/dev/null; }
anytok(){ grep -qF -e "$GHTOK" -e "$M3TOK" -e "$CBTOK" -e "$GLTOK" "$@"; }

G=/gh/repos/HelixDevelopment/constitution
RS_OK='{"id":42,"name":"protect-main-no-force-no-delete","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
gh_base(){ printf '"GET %s":[200,{"full_name":"HelixDevelopment/constitution","private":false}],"GET %s/branches/main/protection":[404,{"message":"Branch not protected"}]' "$G" "$G"; }
gh_rs(){ printf '"GET %s/rulesets?per_page=100":%s,"GET %s/rulesets":%s' "$G" "$1" "$G" "$1"; }
gh_post(){ printf '"POST %s/rulesets":%s' "$G" "$1"; }
gh_det(){ printf '"GET %s/rulesets/%s":%s' "$G" "$1" "$2"; }
gh_rules(){ printf '"GET %s/rules/branches/main":%s' "$G" "$1"; }
RULES42='[200,[{"type":"deletion","ruleset_id":42},{"type":"non_fast_forward","ruleset_id":42}]]'
RULES7='[200,[{"type":"deletion","ruleset_id":7},{"type":"non_fast_forward","ruleset_id":7}]]'
EXPECT_GH='{"name":"protect-main-no-force-no-delete","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}'
GH_HAPPY="{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules "$RULES42")}"

# ---- 1 gating ---------------------------------------------------------------------------------
RUN_ENV=(); run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "apply without FORGE_PROTECT_APPLY -> 3, nothing sent" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=("${APPLY[@]}"); run "$GH_HAPPY" apply --target github_hd --apply-confirm m3w
check "confirm names another target -> 3" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=("${APPLY[@]}"); run "$GH_HAPPY" apply --target github_hd --target m3w --apply-confirm github_hd
check "two targets -> 3" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=(FORGE_PROTECT_APPLY=YES FORGE_PROTECT_ALLOW_TARGETS_OVERRIDE=yes); run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "FORGE_PROTECT_APPLY=YES (not exact) -> 3" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=(); run "$GH_HAPPY" probe --target github-hd
check "unknown --target (probe) -> 2" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=("${APPLY[@]}"); run "$GH_HAPPY" apply --target github-hd --apply-confirm github-hd
check "unknown --target with a confirmed apply -> 2, nothing sent" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=("${APPLY[@]}"); run "{}" apply --target gitlab_vd --apply-confirm gitlab_vd
check "apply to a target outside the allowlist (gitlab_vd) -> 3" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=("${APPLY[@]}"); run "{}" apply --target github_vd --apply-confirm github_vd
check "apply to github_vd (private, Free plan) -> 3" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=(FORGE_PROTECT_APPLY=yes); run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "targets-file override without FORGE_PROTECT_ALLOW_TARGETS_OVERRIDE -> 3" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'

# ---- 2 GitHub body + happy path -----------------------------------------------------------------
RUN_ENV=("${APPLY[@]}"); run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "github apply happy path -> 0, RESULT: APPLIED" '[ $RC -eq 0 ] && grep -q "RESULT: APPLIED" "$tmp/out"'
check "exactly one POST" '[ "$(nreq "POST $G/rulesets")" = 1 ]'
check "POST body is exactly the reviewed ruleset" 'jsoneq "$(reqbody "POST $G/rulesets")" "$EXPECT_GH"'
# ---- 3 token handling ---------------------------------------------------------------------------
check "token never in curl argv, stdout or stderr" '! anytok "$SEC_TEST_LOG/curl_argv.log" "$tmp/out" "$tmp/err"'
check "github token on the wire only as Bearer header" 'grep -qF "\"auth\": \"Bearer $GHTOK\"" "$SEC_TEST_LOG/req.jsonl"'
RUN_ENV=("${APPLY[@]}"); RUN_SHELL="bash -x" run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "token not printed under bash -x" '! anytok "$tmp/out" "$tmp/err" && [ "$(nreq "POST $G/rulesets")" = 1 ]'

# ---- 4 de-dup by content ------------------------------------------------------------------------
OTHER_OK="${RS_OK/protect-main-no-force-no-delete/legacy-protection}"
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[{"id":7,"name":"legacy-protection"}]]'),$(gh_det 7 "[200,${OTHER_OK/\"id\":42/\"id\":7}]"),$(gh_post '[201,{"id":42}]'),$(gh_rules "$RULES7")}" apply --target github_hd --apply-confirm github_hd
check "compliant ruleset under another name -> 0 POST, rc 0" '[ $RC -eq 0 ] && [ "$(nreq "POST")" = 0 ] && grep -q "ALREADY COMPLIANT" "$tmp/out"'
DISABLED="${RS_OK/\"active\"/\"disabled\"}"
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[{"id":42,"name":"protect-main-no-force-no-delete"}]]'),$(gh_det 42 "[200,$DISABLED]"),$(gh_post '[201,{"id":43}]')}" apply --target github_hd --apply-confirm github_hd
check "same-name ruleset with enforcement disabled -> NON-COMPLIANT, 0 POST, rc 1" '[ $RC -eq 1 ] && [ "$(nreq "POST")" = 0 ] && grep -q "NON-COMPLIANT" "$tmp/out"'
BYPASS="${RS_OK/\"bypass_actors\":[]/\"bypass_actors\":[{\"actor_id\":5,\"actor_type\":\"RepositoryRole\"}]}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs '[200,[{"id":42,"name":"protect-main-no-force-no-delete"}]]'),$(gh_det 42 "[200,$BYPASS]")}" probe --target github_hd
check "same-name ruleset with a bypass actor -> NON-COMPLIANT, rc 1" '[ $RC -eq 1 ] && grep -q "NON-COMPLIANT" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[500,{"message":"Server Error"}]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules "$RULES42")}" apply --target github_hd --apply-confirm github_hd
check "ruleset list GET 500 -> 0 POST, rc 1" '[ $RC -eq 1 ] && [ "$(nreq "POST")" = 0 ]'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[{"id":9,"name":"x"}]]'),$(gh_det 9 '[500,{"message":"boom"}]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules "$RULES42")}" apply --target github_hd --apply-confirm github_hd
check "unreadable existing ruleset detail -> 0 POST, rc 1" '[ $RC -eq 1 ] && [ "$(nreq "POST")" = 0 ]'

# ---- 5 read-back --------------------------------------------------------------------------------
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules '[200,[]]')}" apply --target github_hd --apply-confirm github_hd
check "read-back rules 200 [] -> rc 1" '[ $RC -eq 1 ] && ! grep -q "RESULT: APPLIED" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules '[200,[{"type":"deletion","ruleset_id":42},{"type":"non_fast_forward","ruleset_id":99}]]')}" apply --target github_hd --apply-confirm github_hd
check "read-back rule from another ruleset -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules '[429,{"message":"slow down"}]')}" apply --target github_hd --apply-confirm github_hd
check "readback rules/branches rate limited -> rc 4, not APPLIED" '[ $RC -eq 4 ] && grep -q RATE-LIMITED "$tmp/out" && ! grep -q "RESULT: APPLIED" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules '[500,[{"type":"deletion","ruleset_id":42},{"type":"non_fast_forward","ruleset_id":42}]]')}" apply --target github_hd --apply-confirm github_hd
check "readback rules/branches HTTP 500 with a rules-shaped body -> rc 1, not APPLIED" '[ $RC -eq 1 ] && ! grep -q "RESULT: APPLIED" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$DISABLED]"),$(gh_rules "$RULES42")}" apply --target github_hd --apply-confirm github_hd
check "read-back ruleset with enforcement disabled -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$RS_OK]")}" apply --target github_hd --apply-confirm github_hd
check "read-back rules 404 -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[422,{"message":"Validation Failed","id":42}]'),$(gh_det 42 "[200,$RS_OK]"),$(gh_rules "$RULES42")}" apply --target github_hd --apply-confirm github_hd
check "POST 422 -> rc 1 even when a read-back would pass" '[ $RC -eq 1 ] && ! grep -q "RESULT: APPLIED" "$tmp/out"'

# ---- 6 rate limit / plan block ----------------------------------------------------------------
RUN_ENV=(); run "{$(gh_base),$(gh_rs '[403,{"message":"API rate limit exceeded for user ID 1."}]')}" plan --target github_hd
check "403 rate limit -> RATE-LIMITED, rc 4, not BLOCKED-PLAN" '[ $RC -eq 4 ] && grep -q RATE-LIMITED "$tmp/out" && ! grep -q BLOCKED-PLAN "$tmp/out"'
RUN_ENV=(); run "{$(gh_base),$(gh_rs '[429,{"message":"Too Many Requests"}]')}" plan --target github_hd
check "429 -> rc 4" '[ $RC -eq 4 ] && grep -q RATE-LIMITED "$tmp/out"'
RUN_ENV=(); run "{$(gh_base),$(gh_rs '[403,{"message":"Forbidden"},{"x-ratelimit-remaining":"0"}]')}" plan --target github_hd
check "403 with x-ratelimit-remaining 0 -> rc 4" '[ $RC -eq 4 ] && grep -q RATE-LIMITED "$tmp/out"'
RUN_ENV=(); run "{$(gh_base),$(gh_rs '[403,{"message":"Resource not accessible by integration"}]')}" plan --target github_hd
check "plain 403 -> rc 1, not BLOCKED-PLAN" '[ $RC -eq 1 ] && ! grep -q BLOCKED-PLAN "$tmp/out"'
V=/ghv/repos/vasic-digital/HelixConstitution; UPG='[403,{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}]'
RUN_ENV=(); run "{\"GET $V\":[200,{\"private\":true}],\"GET $V/branches/main/protection\":$UPG,\"GET $V/rulesets?per_page=100\":$UPG,\"GET $V/rulesets\":$UPG}" plan --target github_vd
check "github_vd upgrade 403 -> BLOCKED-PLAN, rc 7 (not protectable, never read as done), nothing written" '[ $RC -eq 7 ] && grep -q BLOCKED-PLAN "$tmp/out" && [ "$(nreq "POST")" = 0 ]'

# ---- 7 Gitea / Forgejo --------------------------------------------------------------------------
T=/gt/api/v1/repos/Helix/constitution
gt_base(){ printf '"GET /gt/swagger.v1.json":[200,{"definitions":{"CreateBranchProtectionOption":{"properties":{"enable_force_push":{},"enable_push":{}}}}}],"GET %s":[200,{"full_name":"Helix/constitution"}],"GET /gt/api/v1/version":[200,{"version":"1.27.3"}]' "$T"; }
GT_RB_OK='{"rule_name":"main","enable_push":true,"enable_push_whitelist":false,"enable_force_push":false}'
EXPECT_GT='{"rule_name":"main","enable_push":true,"enable_push_whitelist":false,"enable_force_push":false,"required_approvals":0,"enable_status_check":false,"block_on_rejected_reviews":false,"block_on_outdated_branch":false}'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]],\"POST $T/branch_protections\":[201,$GT_RB_OK],\"GET $T/branch_protections/main\":[200,$GT_RB_OK]}" apply --target m3w --apply-confirm m3w
check "m3w apply happy path -> 0, RESULT: APPLIED" '[ $RC -eq 0 ] && grep -q "RESULT: APPLIED" "$tmp/out"'
check "m3w POST body is exactly the reviewed body (enable_force_push false, enable_push true)" 'jsoneq "$(reqbody "POST $T/branch_protections")" "$EXPECT_GT"'
check "gitea token only as 'token' header, never in argv/output" 'grep -qF "\"auth\": \"token $M3TOK\"" "$SEC_TEST_LOG/req.jsonl" && ! anytok "$SEC_TEST_LOG/curl_argv.log" "$tmp/out" "$tmp/err"'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":false,\"enable_force_push\":true}]],\"POST $T/branch_protections\":[403,{\"message\":\"Branch protection already exist\"}],\"GET $T/branch_protections/main\":[200,{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":false,\"enable_force_push\":true}]}" apply --target m3w --apply-confirm m3w
check "existing rule with enable_force_push true -> NON-COMPLIANT, 0 POST, rc 1" '[ $RC -eq 1 ] && [ "$(nreq "POST")" = 0 ] && grep -q NON-COMPLIANT "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]],\"POST $T/branch_protections\":[403,{\"message\":\"forbidden\"}],\"GET $T/branch_protections/main\":[200,$GT_RB_OK]}" apply --target m3w --apply-confirm m3w
check "gitea POST 403 -> rc 1" '[ $RC -eq 1 ] && ! grep -q "RESULT: APPLIED" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]],\"POST $T/branch_protections\":[201,{}],\"GET $T/branch_protections/main\":[200,{\"rule_name\":\"main\",\"enable_push\":false,\"enable_push_whitelist\":false,\"enable_force_push\":false}]}" apply --target m3w --apply-confirm m3w
check "gitea read-back enable_push false -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]],\"POST $T/branch_protections\":[201,{}],\"GET $T/branch_protections/main\":[200,{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":false,\"enable_force_push\":true}]}" apply --target m3w --apply-confirm m3w
check "gitea read-back enable_force_push true -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]],\"POST $T/branch_protections\":[201,{}],\"GET $T/branch_protections/main\":[200,{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":true,\"enable_force_push\":false}]}" apply --target m3w --apply-confirm m3w
check "gitea read-back with a push allowlist -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=(); run "{$(gt_base),\"GET $T/branch_protections\":[200,[$GT_RB_OK]]}" probe --target m3w
check "gitea compliant rule present -> ALREADY PRESENT, rc 0" '[ $RC -eq 0 ] && grep -q "ALREADY PRESENT" "$tmp/out"'
C=/cb/api/v1/repos/HelixDevelopment/constitution
cb_base(){ printf '"GET /cb/swagger.v1.json":[200,{"definitions":{"CreateBranchProtectionOption":{"properties":{"enable_push":{}}}}}],"GET %s":[200,{}],"GET /cb/api/v1/version":[200,{"version":"17.0.0+gitea-1.22.0"}]' "$C"; }
RUN_ENV=("${APPLY[@]}"); run "{$(cb_base),\"GET $C/branch_protections\":[200,[]],\"POST $C/branch_protections\":[201,{}],\"GET $C/branch_protections/main\":[200,{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":false}]}" apply --target codeberg --apply-confirm codeberg
check "codeberg (no field) -> force-push UNCONFIRMED printed, rc 6" '[ $RC -eq 6 ] && grep -q "force-push blocking: UNCONFIRMED" "$tmp/out"'
check "codeberg POST body has no enable_force_push" 'reqbody "POST $C/branch_protections" | jq -e "has(\"enable_force_push\")|not" >/dev/null'
RUN_ENV=(); run "{\"GET $C\":[200,{}],\"GET /cb/api/v1/version\":[200,{}],\"GET $C/branch_protections\":[200,[]]}" plan --target codeberg
check "swagger unreadable -> WARNING printed" 'grep -q "WARNING: swagger unreadable" "$tmp/out"'

# ---- 8 probe failures, branch, prerequisites, credentials ------------------------------------
DEAD="$tmp/targets_dead"; dp=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
printf 'github_hd|github|http://127.0.0.1:%s/gh|HelixDevelopment|constitution|-\nm3w|gitea|http://127.0.0.1:%s/gt/api/v1|Helix|constitution|M3W_GITEA_TOKEN\n' "$dp" "$dp" > "$DEAD"
RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$DEAD"); run "{}" probe
check "forge unreachable in probe -> rc 1" '[ $RC -eq 1 ]'
RUN_ENV=(); run "{$(gh_base),$(gh_rs '[200,[]]')}" probe --target github_hd
check "github probe, nothing protected -> rc 0, state ABSENT, no write" '[ $RC -eq 0 ] && grep -q "state: ABSENT" "$tmp/out" && [ "$(nreq "POST")" = 0 ]'
RUN_ENV=(); run "{}" probe --target github_hd --branch ../x
check "branch ../x -> 2" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ]'
RUN_ENV=(); run "{}" probe --target github_hd --branch a/../b
check "branch a/../b -> 2" '[ $RC -eq 2 ]'
RUN_ENV=(); run "{}" probe --target github_hd --branch /main
check "branch /main -> 2" '[ $RC -eq 2 ]'
# membership must not depend on a pipe into grep -q (under pipefail the writer can die of
# SIGPIPE once grep has matched, and a known name then reads as unknown): many targets after
# the selected one make that race certain.
BIGTF="$tmp/targets_big"; { head -1 "$TF"; for i in $(seq 1 3000); do printf 'fill%s|gitflic|%s/gf|o|r|GITFLIC_TOKEN\n' "$i" "$B"; done; } > "$BIGTF"
env PATH="$FIX/bin:$PATH" KEYS_FILE="$KEYS" FORGE_PROTECT_TARGETS_FILE="$BIGTF" FORGE_PROTECT_TEST_LOOPBACK=yes bash "$SCRIPT" probe --target github_hd > "$tmp/out" 2> "$tmp/err"; RC=$?
check "first of 3001 targets is known (no SIGPIPE false refusal), rc != 2" '[ $RC -ne 2 ] && ! grep -q "unknown target" "$tmp/err"'
RUN_ENV=(); run "{}" probe --target github_hd --branch main..x
check "branch main..x (a .. inside a segment) -> 2, nothing sent" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ]'
NB="$tmp/nojq"; mkdir -p "$NB"
for tool in bash env python3 curl gh cat sed grep stat sha256sum cut head tail mktemp seq dirname printf; do
  p=$(command -v "$tool" 2>/dev/null) && [ -n "$p" ] && [ "${p#/}" != "$p" ] && ln -sf "$p" "$NB/$tool"
done
ln -sf "$FIX/bin/curl" "$NB/curl"; ln -sf "$FIX/bin/gh" "$NB/gh"
printf '%s' "$GH_HAPPY" > "$SCEN"
env PATH="$NB" KEYS_FILE="$KEYS" FORGE_PROTECT_TARGETS_FILE="$TF" FORGE_PROTECT_TEST_LOOPBACK=yes "$NB/bash" "$SCRIPT" probe --target github_hd > "$tmp/out" 2> "$tmp/err"; RC=$?
check "jq missing -> 5" '[ $RC -eq 5 ] && grep -q "missing prerequisite: jq" "$tmp/err"'
KB="$tmp/keys_bad.sh"; printf 'export M3W_GITEA_TOKEN='"'"'a"b'"'"'\n' > "$KB"; chmod 600 "$KB"
RUN_ENV=(KEYS_FILE="$KB"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe --target m3w
check "token holding a quote -> credential_malformed, rc 1, no authenticated request" '[ $RC -eq 1 ] && grep -q credential_malformed "$tmp/out" && [ "$(nreq "GET $T")" = 0 ]'
KW="$tmp/keys_world.sh"; cp "$KEYS" "$KW"; chmod 644 "$KW"
RUN_ENV=(KEYS_FILE="$KW"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe --target m3w
check "keys file 0644 -> refused, credential_absent, rc 1" '[ $RC -eq 1 ] && grep -q "readable by group/others" "$tmp/err" && grep -q credential_absent "$tmp/out"'
RUN_ENV=(); run "{\"GET /gf/project/helixdevelopment/helixconstitution\":[200,{}]}" plan --target gitflic
check "gitflic plan -> manual UI step, rc 0" '[ $RC -eq 0 ] && grep -q "Manual UI step" "$tmp/out"'
RUN_ENV=(); run "{\"GET /gl/api/v4/projects/vasic-digital%2FHelixConstitution\":[200,{}],\"GET /gl/api/v4/projects/vasic-digital%2FHelixConstitution/protected_branches/main\":[200,{\"name\":\"main\",\"allow_force_push\":false}]}" plan --target gitlab_vd
check "gitlab plan -> probe only, out of apply scope, rc 0" '[ $RC -eq 0 ] && grep -q "out of the apply scope" "$tmp/out" && [ "$(nreq "POST")" = 0 ]'
RUN_ENV=(); run "{}" --list
check "--list prints the targets" '[ $RC -eq 0 ] && grep -q "^m3w|gitea|" "$tmp/out"'

# ---- 9 round 2: existing-state compliance (F1) -----------------------------------------------------
# ALREADY COMPLIANT needs the full predicate AND the GET /rules/branches ground truth.
L7='[200,[{"id":7,"name":"legacy-protection"}]]'
det7(){ printf '%s' "$(gh_det 7 "[200,$1]")"; }
OK7="${OTHER_OK/\"id\":42/\"id\":7}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$OK7")}" probe --target github_hd
check "compliant-looking ruleset whose rules/branches read-back answers 404 -> UNKNOWN, not ALREADY COMPLIANT, rc 1, 0 POST" '[ $RC -eq 1 ] && ! grep -q "ALREADY COMPLIANT" "$tmp/out" && grep -q "state: UNKNOWN" "$tmp/out" && [ "$(nreq "POST")" = 0 ]'
check "the compliant path asked GET /rules/branches/main" '[ "$(nreq "GET $G/rules/branches/main")" = 1 ]'
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$OK7"),$(gh_rules '[200,[{"type":"deletion","ruleset_id":7},{"type":"non_fast_forward","ruleset_id":99}]]')}" probe --target github_hd
check "compliant-looking ruleset, rules/branches lists only one type for it -> NOT CONFIRMED, rc 1, not ALREADY COMPLIANT" '[ $RC -eq 1 ] && ! grep -q "ALREADY COMPLIANT" "$tmp/out" && grep -q "NOT CONFIRMED" "$tmp/out"'
EXMAIN="${OK7/\"exclude\":[]/\"exclude\":[\"refs/heads/main\"]}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$EXMAIN"),$(gh_rules "$RULES7")}" probe --target github_hd
check "ruleset that includes AND excludes refs/heads/main -> not compliant, state ABSENT" '! grep -q "ALREADY COMPLIANT" "$tmp/out" && grep -q "state: ABSENT" "$tmp/out"'
EXALL="${OK7/\"exclude\":[]/\"exclude\":[\"refs/heads/*\"]}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$EXALL"),$(gh_rules "$RULES7")}" probe --target github_hd
check "ruleset excluding refs/heads/* -> not compliant, state ABSENT" '! grep -q "ALREADY COMPLIANT" "$tmp/out" && grep -q "state: ABSENT" "$tmp/out"'
NOBY="${OK7/\"bypass_actors\":[],/}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$NOBY"),$(gh_rules "$RULES7"),$(gh_post '[201,{"id":42}]')}" plan --target github_hd
check "ruleset without a bypass_actors field -> UNCONFIRMED, rc 1, no plan to POST" '[ $RC -eq 1 ] && grep -q "UNCONFIRMED" "$tmp/out" && ! grep -q "ALREADY COMPLIANT" "$tmp/out" && ! grep -q "plan: POST" "$tmp/out"'
DEV="${OK7/refs\/heads\/main/refs/heads/dev}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$DEV"),$(gh_rules "$RULES7")}" probe --target github_hd
check "ruleset for another branch (refs/heads/dev) -> not compliant for main, state ABSENT" '! grep -q "ALREADY COMPLIANT" "$tmp/out" && grep -q "state: ABSENT" "$tmp/out"'
TAGRS="${OK7/\"target\":\"branch\"/\"target\":\"tag\"}"
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$L7"),$(det7 "$TAGRS"),$(gh_rules "$RULES7")}" probe --target github_hd
check "tag ruleset with the same rules -> not compliant, state ABSENT" '! grep -q "ALREADY COMPLIANT" "$tmp/out" && grep -q "state: ABSENT" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gh_base),$(gh_rs '[200,[]]'),$(gh_post '[201,{"id":42}]'),$(gh_det 42 "[200,$EXMAIN]"),$(gh_rules "$RULES42")}" apply --target github_hd --apply-confirm github_hd
check "read-back ruleset that excludes main -> rc 1, not APPLIED" '[ $RC -eq 1 ] && ! grep -q "RESULT: APPLIED" "$tmp/out"'
BIGL=$(python3 -I -c 'import json;print(json.dumps([200,[{"id":1000+i,"name":"r%d"%i} for i in range(100)]]))')
RUN_ENV=(); run "{$(gh_base),$(gh_rs "$BIGL")}" plan --target github_hd
check "100 rulesets (one full page) -> UNKNOWN, rc 1, nothing planned" '[ $RC -eq 1 ] && grep -q "not paginated" "$tmp/out" && ! grep -q "plan: POST" "$tmp/out"'

# ---- 10 round 2: token-to-host binding (F3) --------------------------------------------------------
DECOY=DECOY_SECRET_7c6b5a4f3e2d
KD="$tmp/keys_decoy.sh"; cp "$KEYS" "$KD"; printf 'export SOME_OTHER_SECRET=%s\n' "$DECOY" >> "$KD"; chmod 600 "$KD"
TD="$tmp/targets_decoy"; printf 'm3w|gitea|%s/gt/api/v1|Helix|constitution|SOME_OTHER_SECRET\n' "$B" > "$TD"
RUN_ENV=(KEYS_FILE="$KD" FORGE_PROTECT_TARGETS_FILE="$TD"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe
check "a target naming an unbound keys-file variable -> 2, nothing sent, decoy never on the wire" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ] && ! grep -qF "$DECOY" "$SEC_TEST_LOG/req.jsonl" "$tmp/out" "$tmp/err"'
TH="$tmp/targets_host"; printf 'm3w|gitea|https://example.invalid/api/v1|Helix|constitution|M3W_GITEA_TOKEN\n' > "$TH"
RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$TH"); run "{}" --list
check "M3W token bound to git.m3w.org: a target on another host -> 2" '[ $RC -eq 2 ] && grep -q "bound to" "$tmp/err"'
printf 'github_hd|github|https://gitlab.com/api/v4|HelixDevelopment|constitution|-\n' > "$TH"
RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$TH"); run "{}" --list
check "gh keyring token bound to api.github.com: a target on gitlab.com -> 2" '[ $RC -eq 2 ]'
printf 'm3w|gitea|http://git.m3w.org/api/v1|Helix|constitution|M3W_GITEA_TOKEN\n' > "$TH"
RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$TH"); run "{}" --list
check "plain http:// to the bound (non-loopback) host -> 2" '[ $RC -eq 2 ]'
printf 'm3w|gitea|https://u@git.m3w.org/api/v1|Helix|constitution|M3W_GITEA_TOKEN\n' > "$TH"
RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$TH"); run "{}" --list
check "a base URL with user info -> 2" '[ $RC -eq 2 ]'
RUN_ENV=(FORGE_PROTECT_TEST_LOOPBACK=no); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe --target m3w
check "loopback base without FORGE_PROTECT_TEST_LOOPBACK=yes -> 2, nothing sent" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ]'
TP4="$tmp/targets_p4"; printf 'github_hd|github|%s/gh|vasic-digital|HelixConstitution|-\n' "$B" > "$TP4"
RUN_ENV=("${APPLY[@]}" FORGE_PROTECT_TARGETS_FILE="$TP4"); run "{$(gh_base)}" apply --target github_hd --apply-confirm github_hd
check "apply: target named github_hd but another owner/repo than the built-in -> 3, nothing sent" '[ $RC -eq 3 ] && [ "$(nreq "")" = 0 ]'

# ---- 11 round 2: surviving reviewer mutants (F4) ---------------------------------------------------
RUN_ENV=("${APPLY[@]}"); run "$GH_HAPPY" apply --target github_hd --apply-confirm github-hd
check "unknown --apply-confirm target -> 2 (usage), not 3" '[ $RC -eq 2 ] && [ "$(nreq "")" = 0 ]'
K640="$tmp/keys_640.sh"; cp "$KEYS" "$K640"; chmod 640 "$K640"
RUN_ENV=(KEYS_FILE="$K640"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe --target m3w
check "keys file 0640 (group-readable) -> refused, credential_absent, rc 1" '[ $RC -eq 1 ] && grep -q "readable by group/others" "$tmp/err" && grep -q credential_absent "$tmp/out"'
KNL="$tmp/keys_nl.sh"; printf "export M3W_GITEA_TOKEN=\$'FAKEM3W_TOKEN_1a2b\\\\nheader = X-Injected'\n" > "$KNL"; chmod 600 "$KNL"
RUN_ENV=(KEYS_FILE="$KNL"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe --target m3w
check "token holding a newline -> credential_malformed, no authenticated request" '[ $RC -eq 1 ] && grep -q credential_malformed "$tmp/out" && [ "$(nreq "GET $T")" = 0 ]'
KCR="$tmp/keys_cr.sh"; printf "export M3W_GITEA_TOKEN=\$'FAKEM3W_TOKEN_1a2b\\\\rX'\n" > "$KCR"; chmod 600 "$KCR"
RUN_ENV=(KEYS_FILE="$KCR"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]]}" probe --target m3w
check "token holding a CR -> credential_malformed" '[ $RC -eq 1 ] && grep -q credential_malformed "$tmp/out" && [ "$(nreq "GET $T")" = 0 ]'
CBP="{\"GET /cb/swagger.v1.json\":[200,{\"definitions\":{\"CreateBranchProtectionOption\":{\"properties\":{\"enable_push\":{}}}}}],\"GET $C\":[200,{}],\"GET /cb/api/v1/version\":[200,{}],\"GET $C/branch_protections\":[200,[{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":false}]],\"GET /gt/swagger.v1.json\":[200,{}],\"GET $T\":[200,{}],\"GET /gt/api/v1/version\":[200,{}],\"GET $T/branch_protections\":[500,{\"message\":\"boom\"}]}"
RUN_ENV=(); run "$CBP" probe --target m3w --target codeberg
check "a failure (1) then an UNCONFIRMED (6) in one run -> exit 1 (order 4 > 1 > 6)" '[ $RC -eq 1 ] && grep -q "force-push blocking: UNCONFIRMED" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[]],\"POST $T/branch_protections\":[201,{}],\"GET $T/branch_protections/main\":[200,{\"rule_name\":\"other\",\"enable_push\":true,\"enable_push_whitelist\":false,\"enable_force_push\":false}]}" apply --target m3w --apply-confirm m3w
check "gitea read-back of a rule for another branch -> rc 1, not APPLIED" '[ $RC -eq 1 ] && ! grep -q "RESULT: APPLIED" "$tmp/out"'
RUN_ENV=("${APPLY[@]}"); run "$GH_HAPPY" --target github_hd
check "no mode given -> plan (dry run): rc 0, plan printed, 0 POST even with the apply env set" '[ $RC -eq 0 ] && grep -q "mode=plan" "$tmp/out" && [ "$(nreq "POST")" = 0 ]'
RUN_ENV=(); run "{$(gh_base | sed 's/\[404,{"message":"Branch not protected"}\]/[500,{"message":"boom"}]/'),$(gh_rs '[200,[]]')}" probe --target github_hd
check "branch-protection GET 500 -> reported FAILED, rc 1" '[ $RC -eq 1 ] && grep -q "FAILED: GET branch protection" "$tmp/out"'

# ---- 12 round 2: Gitea glob rules (F5) -------------------------------------------------------------
RUN_ENV=(); run "{$(gt_base),\"GET $T/branch_protections\":[200,[$GT_RB_OK,{\"rule_name\":\"ma*\",\"enable_push\":true,\"enable_push_whitelist\":false,\"enable_force_push\":true}]]}" probe --target m3w
check "an extra glob rule next to the exact rule -> UNCONFIRMED note, rc 6" '[ $RC -eq 6 ] && grep -q "glob rule" "$tmp/out"'


# ---- 13 round 3: token-to-host binding, class-wide (review r3 F1, F5) -----------------------------
# Start-up refusal only (--list sends nothing): no case here can reach a real host, also under a mutant.
# Each bound token variable gets the same rejected shapes: a host that merely STARTS with the bound
# host, one that merely ENDS with it, a sub-domain, user info, a port other than 443, plain http.
bindrc(){ printf '%s|%s|%s|o|r|%s\n' "$1" "$2" "$3" "$4" > "$tmp/targets_bind"
  RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$tmp/targets_bind" FORGE_PROTECT_TEST_LOOPBACK=no); run "{}" --list; }
while IFS='|' read -r tn tp tv good; do
  base=${good%%/*}; path=${good#"$base"}
  for bb in "https://$base.evil.example$path" "https://evil$base$path" "https://x.$base$path" \
             "https://u@$base$path" "https://u:p@$base$path" "https://$base:8443$path" "https://$base:0443$path" \
             "https://$base:80$path" "http://$base$path"; do
    bindrc "$tn" "$tp" "$bb" "$tv"
    check "token ${tv/#-/gh-keyring} bound to $base: base $bb refused at start-up -> 2" '[ $RC -eq 2 ] && grep -q "bound to" "$tmp/err" && [ "$(nreq "")" = 0 ]'
  done
  for gb in "https://$base$path" "https://$base:443$path" "https://${base^^}$path"; do
    bindrc "$tn" "$tp" "$gb" "$tv"
    check "token ${tv/#-/gh-keyring}: the bound base $gb is accepted (golden-FALSE) -> 0" '[ $RC -eq 0 ] && ! grep -q "bound to" "$tmp/err"'
  done
done <<'BINDS'
github_hd|github|-|api.github.com
m3w|gitea|M3W_GITEA_TOKEN|git.m3w.org/api/v1
codeberg|gitea|CODEBERG_GITEA_TOKEN|codeberg.org/api/v1
gitlab_vd|gitlab|GITLAB_TOKEN|gitlab.com/api/v4
BINDS

# Apply tuple: a targets file may replace ONLY the base (and only with a loopback one). Each other
# field changed alone -> 3, nothing sent. Two token variables (gh keyring, M3W).
for line in \
  "github_hd|github|$B/gh|vasic-digital|constitution|-" \
  "github_hd|github|$B/gh|HelixDevelopment|HelixConstitution|-" \
  "github_hd|github|$B/gh|HelixDevelopment|constitution|M3W_GITEA_TOKEN" \
  "github_hd|gitea|$B/gh|HelixDevelopment|constitution|-" \
  "m3w|gitea|$B/gt/api/v1|OtherOwner|constitution|M3W_GITEA_TOKEN" \
  "m3w|gitea|$B/gt/api/v1|Helix|other|M3W_GITEA_TOKEN" \
  "m3w|gitea|$B/gt/api/v1|Helix|constitution|CODEBERG_GITEA_TOKEN" \
  "m3w|github|$B/gt/api/v1|Helix|constitution|M3W_GITEA_TOKEN"; do
  printf '%s\n' "$line" > "$tmp/targets_tuple"; tn=${line%%|*}
  RUN_ENV=("${APPLY[@]}" FORGE_PROTECT_TARGETS_FILE="$tmp/targets_tuple"); run "$GH_HAPPY" apply --target "$tn" --apply-confirm "$tn"
  check "apply: only one tuple field differs from built-in $tn (${line#*|}) -> 3, nothing sent" '[ $RC -eq 3 ] && grep -q "differs from the built-in target" "$tmp/err" && [ "$(nreq "")" = 0 ]'
done

# ---- 14 round 3: exit order 4 > 1 > 7 > 6 > 0 with several targets (review r3 F2) ------------------
VPLAN="\"GET $V\":[200,{\"private\":true}],\"GET $V/branches/main/protection\":$UPG,\"GET $V/rulesets?per_page=100\":$UPG,\"GET $V/rulesets\":$UPG"
CB6="\"GET /cb/swagger.v1.json\":[200,{\"definitions\":{\"CreateBranchProtectionOption\":{\"properties\":{\"enable_push\":{}}}}}],\"GET $C\":[200,{}],\"GET /cb/api/v1/version\":[200,{}],\"GET $C/branch_protections\":[200,[{\"rule_name\":\"main\",\"enable_push\":true,\"enable_push_whitelist\":false}]]"
GT1="\"GET /gt/swagger.v1.json\":[200,{}],\"GET $T\":[200,{}],\"GET /gt/api/v1/version\":[200,{}],\"GET $T/branch_protections\":[500,{\"message\":\"boom\"}]"
HD4="$(gh_base),$(gh_rs '[429,{"message":"Too Many Requests"}]')"
HD1="$(gh_base),$(gh_rs '[403,{"message":"Resource not accessible by integration"}]')"
# ordered TARGETS file: the outcomes arrive in exactly this order
ordrun(){ local scen=$1; shift; : > "$tmp/targets_ord"; local x; for x in "$@"; do grep "^$x|" "$TF" >> "$tmp/targets_ord"; done
  RUN_ENV=(FORGE_PROTECT_TARGETS_FILE="$tmp/targets_ord"); run "$scen" probe; }
ordrun "{$HD4,$VPLAN}" github_hd github_vd
check "order: 4 then 7 -> 4" '[ $RC -eq 4 ] && grep -q RATE-LIMITED "$tmp/out" && grep -q BLOCKED-PLAN "$tmp/out"'
ordrun "{$HD4,$VPLAN}" github_vd github_hd
check "order: 7 then 4 -> 4" '[ $RC -eq 4 ] && grep -q BLOCKED-PLAN "$tmp/out"'
ordrun "{$HD1,$VPLAN}" github_hd github_vd
check "order: 1 then 7 -> 1" '[ $RC -eq 1 ] && grep -q BLOCKED-PLAN "$tmp/out"'
ordrun "{$HD1,$VPLAN}" github_vd github_hd
check "order: 7 then 1 -> 1" '[ $RC -eq 1 ] && grep -q BLOCKED-PLAN "$tmp/out"'
ordrun "{$VPLAN,$CB6}" github_vd codeberg
check "order: 7 then 6 -> 7" '[ $RC -eq 7 ] && grep -q "force-push blocking: UNCONFIRMED" "$tmp/out"'
ordrun "{$VPLAN,$CB6}" codeberg github_vd
check "order: 6 then 7 -> 7" '[ $RC -eq 7 ] && grep -q BLOCKED-PLAN "$tmp/out"'
ordrun "{$HD4,$GT1}" github_hd m3w
check "order: 4 then 1 -> 4" '[ $RC -eq 4 ] && grep -q "FAILED: GET branch_protections" "$tmp/out"'
ordrun "{$HD4,$GT1}" m3w github_hd
check "order: 1 then 4 -> 4" '[ $RC -eq 4 ] && grep -q RATE-LIMITED "$tmp/out"'
ordrun "{$GT1,$CB6}" codeberg m3w
check "order: 6 then 1 -> 1" '[ $RC -eq 1 ] && grep -q "force-push blocking: UNCONFIRMED" "$tmp/out"'
ordrun "{$VPLAN}" github_vd
check "order: 7 alone -> 7" '[ $RC -eq 7 ]'
ordrun "{$CB6}" codeberg
check "order: 6 alone -> 6" '[ $RC -eq 6 ]'

# ---- 15 round 3: curl hardening (review r3 F3) ------------------------------------------------------
# A hostile .curlrc must be ignored (curl -q). Control needle: the same .curlrc IS read by a curl run
# without -q on this host, so a zero below is evidence, not a blind instrument.
CH="$tmp/curlhome"; mkdir -p "$CH"; printf 'header = "X-Curlrc: injected"\n' > "$CH/.curlrc"
: > "$SEC_TEST_LOG/req.jsonl"; printf '{}' > "$SCEN"
env -u http_proxy -u HTTP_PROXY -u all_proxy -u ALL_PROXY CURL_HOME="$CH" "$REAL_CURL" -sS -o /dev/null "$B/needle" 2>/dev/null
check "control needle: curl without -q reads CURL_HOME/.curlrc on this host" 'grep -q "\"xc\": \"injected\"" "$SEC_TEST_LOG/req.jsonl"'
RUN_ENV=("${APPLY[@]}" CURL_HOME="$CH" XDG_CONFIG_HOME="$CH"); run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "hostile .curlrc ignored: no request carries its header, apply still happy" '[ $RC -eq 0 ] && [ "$(nreq "")" -gt 0 ] && ! grep -q "\"xc\": \"injected\"" "$SEC_TEST_LOG/req.jsonl"'
RUN_ENV=(CURL_HOME="$CH"); run "{$(gt_base),\"GET $T/branch_protections\":[200,[$GT_RB_OK]]}" probe --target m3w
check "hostile .curlrc ignored on the gitea path (swagger + token requests)" '[ $RC -eq 0 ] && ! grep -q "\"xc\": \"injected\"" "$SEC_TEST_LOG/req.jsonl"'
# A 302 to another port must not be followed (no -L): the second listener sees nothing, the token stays.
RUN_ENV=(); run "{\"GET $G\":[302,{},{\"Location\":\"http://127.0.0.1:$P2$G\"}],$(gh_rs '[200,[]]')}" probe --target github_hd
check "302 to another port is not followed: second listener got 0 requests, rc 1" '[ $RC -eq 1 ] && [ ! -s "$REQ2" ] && grep -q "HTTP 302" "$tmp/out"'
RUN_ENV=(); run "{$(gt_base),\"GET $T/branch_protections\":[302,{},{\"Location\":\"http://127.0.0.1:$P2$T/branch_protections\"}]}" probe --target m3w
check "gitea: 302 to another port is not followed, rc 1" '[ $RC -eq 1 ] && [ ! -s "$REQ2" ]'

# ---- 16 round 3: proxies and gh host pinning (review r3 F5) ------------------------------------------
for pv in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY; do
  RUN_ENV=("$pv=http://127.0.0.1:$P2"); run "$GH_HAPPY" probe --target github_hd
  check "loopback test mode with $pv set -> 2, nothing sent, the proxy listener got nothing" '[ $RC -eq 2 ] && grep -q "proxy" "$tmp/err" && [ "$(nreq "")" = 0 ] && [ ! -s "$REQ2" ]'
done
RUN_ENV=("http_proxy=http://127.0.0.1:$P2" FORGE_PROTECT_TEST_LOOPBACK=no FORGE_PROTECT_TARGETS_FILE=); run "{}" --list
check "a proxy variable outside the loopback test mode is not refused (golden-FALSE): --list -> 0" '[ $RC -eq 0 ] && grep -q "^github_hd|github|https://api.github.com|" "$tmp/out"'
RUN_ENV=("${APPLY[@]}" GH_HOST=ghe.evil.example GH_ENTERPRISE_TOKEN=x GITHUB_ENTERPRISE_TOKEN=x); run "$GH_HAPPY" apply --target github_hd --apply-confirm github_hd
check "gh keyring token read with --hostname github.com" '[ $RC -eq 0 ] && grep -qx "auth token --hostname github.com" "$SEC_TEST_LOG/gh_argv.log" && ! grep -v -x "auth token --hostname github.com" "$SEC_TEST_LOG/gh_argv.log" | grep -q .'
check "GH_HOST and enterprise tokens never reach gh" '[ -s "$SEC_TEST_LOG/gh_env.log" ] && ! grep -v -x "ENV GH_HOST=unset GH_ENTERPRISE_TOKEN= GITHUB_ENTERPRISE_TOKEN=" "$SEC_TEST_LOG/gh_env.log" | grep -q .'

# ---- 17 round 3: Gitea glob rules with ? and [ (review r3 F4) ----------------------------------------
for gname in 'ma?n' '[m]ain' 'm*'; do
  gj=$(jq -cn --arg n "$gname" '{rule_name:$n,enable_push:true,enable_push_whitelist:false,enable_force_push:true}')
  RUN_ENV=(); run "{$(gt_base),\"GET $T/branch_protections\":[200,[$GT_RB_OK,$gj]]}" probe --target m3w
  check "glob rule '$gname' next to the exact rule -> UNCONFIRMED note, rc 6" '[ $RC -eq 6 ] && grep -qF "glob rule '"'"'$gname'"'"'" "$tmp/out"'
done
RUN_ENV=(); run "{$(gt_base),\"GET $T/branch_protections\":[200,[$GT_RB_OK,{\"rule_name\":\"dev\",\"enable_push\":true,\"enable_push_whitelist\":false,\"enable_force_push\":true}]]}" probe --target m3w
check "a plain rule for another branch is not a glob (golden-FALSE): rc 0, no note" '[ $RC -eq 0 ] && ! grep -q "glob rule" "$tmp/out"'

echo "RESULT: $((n-bad))/$n passed"
[ "$bad" -eq 0 ]
