#!/usr/bin/env bash
# Round-6 review fixes (STRUCTURAL round, §11.4.276). Each block names the finding it pins.
#   I6-2 ONE shared path resolver (lib_decide.sh: jev_state_dir/jev_config_dir/jev_evidence_dir/jev_detection_file/...) used by
#        bootstrap, jev-status, register, calibrate and the gates. A scan test fails on any remaining independent derivation.
#   I6-1 key material: no plaintext backups of key-bearing files, at most ONE backup of other files, docs state what the toolkit writes
#   m6-1 status compares every MCP mode with the mode IN FORCE ; m6-2 every JEV_BASE_URL occurrence / unparseable cache / TYPESAFE_BASE_URL
#   m6-3 stage 5 rewrites EVERY jev entry in the covered set ; m6-4 writes keep symlinks ; m6-5 register refuses shell-active values
#   n6-1 JEV_NOW_EPOCH is JEV_TEST-only everywhere ; n6-3 stub-server wait
# Every case drives the REAL code; llmctl / validator are stubs, every URL is loopback or a reserved test name.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq python3; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
ST="$REPO/scripts/jev/jev-status.sh"; REG="$REPO/skills/jev-decision-layer/register.sh"; BS="$REPO/scripts/jev/bootstrap.sh"
LIB="$REPO/scripts/jev/lib_decide.sh"
LOOP=https://127.0.0.1:8095; HOSTED=https://api.typesafe.test

promoted() { jq -n '{per_type:{gate:{promoted:true,threshold:0.9}}}' > "$1"; }
eff() { ( set +u; source "$REPO/scripts/jev/lib_keys.sh" 2>/dev/null; source "$LIB"; jev_effective_mode "$@" ); }
strip() { sed 's/;test-override(JEV_TEST=1)//'; }
mkdet() { jq -n --arg id "$2" --arg u "$3" --argjson g "${4:-1700000000}" '{version:1,generated_at:$g,endpoints:[{id:$id,source:"local-llmctl",reachable:true,url:$u}],reason:null}' > "$1"; }
fx() { make_fixture_env "$1"; jev_test_enforce_env 0; unset JEV_BASE_URL
  mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9"; promoted "$JEV_CONFIG_DIR/jev-thresholds.json"
  export JEV_DETECTION_FILE="$T/det.json"; cp "$T/det.json" "$JEV_EVIDENCE_DIR/jev-detection.json"
  B="$T/box"; mkdir -p "$B/.claude"; printf '{"mcpServers":{}}\n' > "$B/.mcp.json"; export JEV_HOME="$B"; }
mode_of() { grep -E '^[[:space:]]*(export[[:space:]]+)?JEV_MODE=' "$1" 2>/dev/null | tail -1 | sed -E 's/^[[:space:]]*(export[[:space:]]+)?JEV_MODE=//'; }
status_json() { bash "$ST" --json 2>/dev/null; }
R() { eff enforce "" "$T/det.json" | strip; }
SHADOW_HOSTED="shadow	hosted-or-non-loopback-base-url"

# ---- I6-2 (A): NO path env at all -> every component lands on the SAME record, independent of the cwd ----------------------
fx p1; unset JEV_EVIDENCE_DIR JEV_STATE_DIR JEV_CONFIG_DIR JEV_DETECTION_FILE JEV_HOME
CA="$T/cwdA"; CB="$T/cwdB"; CC="$T/cwdC"; mkdir -p "$CA" "$CB" "$CC"
WANT="$HOME/.local/state/jev/evidence/jev-detection.json"
( cd "$CA" && bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null )
assert_file_exists "$WANT" "I6-2 bootstrap (cwd A, no path env) wrote the detection record under \$HOME/.local/state/jev/evidence"
assert_file_absent "$CA/.jev" "I6-2 bootstrap left nothing under <cwd>/.jev"
( cd "$CB" && env JEV_MODE=shadow bash "$REG" >/dev/null 2>&1 </dev/null )
assert_file_absent "$CB/.jev" "I6-2 register (cwd B) created nothing under <cwd>/.jev"
SJ="$( cd "$CC" && bash "$ST" --json 2>/dev/null )"
assert_eq "true" "$(printf '%s' "$SJ" | jq -r '(.detection != null) and ((.detection.endpoints // []) | type == "array")')" "I6-2 jev-status (cwd C) finds the detection record bootstrap wrote (inline in its JSON)"
assert_eq "$(jq -S -c . "$WANT")" "$(printf '%s' "$SJ" | jq -S -c .detection)" "I6-2 ... and it is byte-for-byte the record at the resolver path"
assert_file_absent "$CC/.jev" "I6-2 jev-status left nothing under <cwd>/.jev"

# ---- I6-2 (B): resolver unit assertions ----------------------------------------------------------------------------------
res() { ( set +u; cd "$T"; source "$LIB"; "$@" ); }
fx p2; unset JEV_EVIDENCE_DIR JEV_STATE_DIR JEV_CONFIG_DIR JEV_DETECTION_FILE JEV_HOME
assert_eq "$HOME/.local/state/jev" "$(res jev_state_dir)" "I6-2 jev_state_dir default"
assert_eq "$HOME/.local/state/jev/evidence" "$(res jev_evidence_dir)" "I6-2 jev_evidence_dir default is absolute, state-relative (no cwd .jev)"
assert_eq "$HOME/.local/state/jev/evidence/jev-detection.json" "$(res jev_detection_file)" "I6-2 jev_detection_file default"
assert_eq "/x/e/jev-detection.json" "$(JEV_EVIDENCE_DIR=/x/e res jev_detection_file)" "I6-2 JEV_EVIDENCE_DIR selects the detection record"
assert_eq "/y/d.json" "$(JEV_EVIDENCE_DIR=/x/e JEV_DETECTION_FILE=/y/d.json res jev_detection_file)" "I6-2 JEV_DETECTION_FILE wins"
assert_eq "$T/rel/e" "$(JEV_EVIDENCE_DIR=rel/e res jev_evidence_dir)" "I6-2 a relative JEV_EVIDENCE_DIR is made absolute against the cwd of the CALL (one rule for all callers)"
assert_eq "/h/.local/state/jev" "$(JEV_HOME=/h res jev_state_dir)" "I6-2 JEV_HOME moves state with it"
assert_eq "$HOME/.local/share/claude-multi-account/providers/jev-endpoints.json" "$(JEV_HOME=/h res jev_default_cache_file)" "I6-2 default cache candidate is under the real HOME, not JEV_HOME"

# ---- I6-2 (C): scan - any remaining independent derivation of those paths fails -----------------------------------------------
# A line is an offender when it derives a covered path itself (an env default or a literal state/config/share location) and
# carries no `# jev-path-ok: <reason>` on the same line or the line directly above. lib_decide.sh IS the resolver (exempt).
OFFENDER_RE='\$\{(JEV_HOME|JEV_STATE_DIR|JEV_CONFIG_DIR|JEV_EVIDENCE_DIR|JEV_DETECTION_FILE|JEV_BOOTSTRAP_HOME|CMA_PROVIDERS_DIR|CLAUDE_TOOLKIT_DIR):-[^}]|\.local/state/jev|\.config/jev|\.local/share/(helix|claude-multi-account)|:-\.jev|/\.jev/jev-'
scan_file() { # scan_file <file> -> offending "file:line:text" lines. A marker covers its own line, the next line, and a backslash-continued statement.
  OFFENDER_RE="$OFFENDER_RE" awk -v f="$1" '
    BEGIN { re = ENVIRON["OFFENDER_RE"]; cover = 0 }
    { line = $0; marked = (line ~ /jev-path-ok:/)
      if (line ~ /^[[:space:]]*#/) { cover = marked ? 1 : 0; next }
      if (line ~ re && !marked && !cover) printf "%s:%d:%s\n", f, NR, line
      if (marked) cover = 1
      else if (cover && line !~ /\\[[:space:]]*$/) cover = 0 }' "$1"
}
SCAN_OUT=""
for f in "$REPO"/scripts/jev/*.sh "$REPO/skills/jev-decision-layer/register.sh" "$REPO"/scripts/gates/cm_jev_*.sh; do
  case "$f" in */lib_decide.sh|*_mutation_test.sh) continue;; esac
  [ -f "$f" ] && SCAN_OUT="$SCAN_OUT$(scan_file "$f")"$'\n'
done
SCAN_OUT="$(printf '%s' "$SCAN_OUT" | sed '/^$/d')"
if [ -z "$SCAN_OUT" ]; then ok "I6-2 scan: no component outside lib_decide.sh derives a state/config/evidence/detection path itself"; else fail "I6-2 scan found independent derivations:
$SCAN_OUT"; fi
# control needle (§11.4.273): a planted offender is detected, a clean file and a marked line are not
printf 'X="${JEV_STATE_DIR:-$HOME/.local/state/jev}"\n' > "$T/planted.sh"
printf 'X="$(jev_state_dir)"\n# jev-path-ok: fixture sandbox\nY="${JEV_HOME:-/x}"\n' > "$T/clean.sh"
assert_ne "" "$(scan_file "$T/planted.sh")" "I6-2 scan control needle: a planted offender IS detected"
assert_eq "" "$(scan_file "$T/clean.sh")" "I6-2 scan control needle: a clean file / marked line is NOT flagged"

# ---- I6-1: no plaintext backup of key-bearing files; at most one backup of the rest --------------------------------------------
fx k1
jq -n '{mcpServers:{jev:{env:{TYPESAFE_API_KEY:"not-a-real-key-value",JEV_BASE_URL:"https://127.0.0.1:8095"}}}}' > "$B/.mcp.json"
env JEV_MODE=shadow bash "$REG" >/dev/null 2>&1 </dev/null
assert_eq "0" "$(ls "$B"/.mcp.json.prejev.* 2>/dev/null | wc -l)" "I6-1 register makes NO backup of a key-bearing .mcp.json"
assert_eq "not-a-real-key-value" "$(jq -r '.mcpServers.jev.env.TYPESAFE_API_KEY' "$B/.mcp.json")" "I6-1 ... and the key is still intact after the edit"
fx k2
printf '{"mcpServers":{"other":{"command":"x"}}}\n' > "$B/.mcp.json"
env JEV_MODE=shadow JEV_NOW_EPOCH=1700000001 bash "$REG" >/dev/null 2>&1 </dev/null
env JEV_MODE=shadow JEV_NOW_EPOCH=1700000002 bash "$REG" >/dev/null 2>&1 </dev/null
assert_le() { if [ "$1" -le "$2" ] 2>/dev/null; then ok "$3"; else fail "$3 ([$1] > [$2])"; fi; }
assert_le "$(ls "$B"/.mcp.json.prejev.* 2>/dev/null | wc -l)" 1 "I6-1 repeated runs keep at most ONE backup of a key-free file (no accumulation)"
BK="$(ls "$B"/.mcp.json.prejev.* 2>/dev/null | head -1)"
if [ -n "$BK" ]; then assert_eq "600" "$(stat -c %a "$BK")" "I6-1 the backup is mode 0600"; assert_contains "$BK" '"other"' "I6-1 the one backup holds the ORIGINAL content"; else fail "I6-1 expected one backup of a key-free file"; fi
assert_not_contains "$REPO/docs/jev/governance-guide.md" "no key value is copied into agent configs" "I6-1 governance guide no longer carries the false 'no key value is copied' claim"
assert_contains "$REPO/docs/jev/governance-guide.md" "jev-setup.sh" "I6-1 governance guide names the toolkit script that writes key values into agent configs"
assert_contains "$REPO/docs/jev/governance-guide.md" "TYPESAFE_API_KEY" "I6-1 governance guide names the variable the toolkit writes"

# ---- m6-2: base-url holes (reviewer probes verbatim) ---------------------------------------------------------------------------
envbase() { fx "$1"; printf '%b' "$2" > "$JEV_CONFIG_DIR/env"; }
envbase h1 "JEV_BASE_URL=$LOOP\ndeclare -x JEV_BASE_URL=https://evil.example\n"; assert_eq "$SHADOW_HOSTED(env-file)" "$(R)" "m6-2 'declare -x JEV_BASE_URL=evil' after a loopback line => shadow"
envbase h2 "A=1; JEV_BASE_URL=https://evil.example\n";                              assert_eq "$SHADOW_HOSTED(env-file)" "$(R)" "m6-2 'A=1; JEV_BASE_URL=evil' => shadow"
envbase h3 "# JEV_BASE_URL=https://evil.example\nJEV_BASE_URL=$LOOP\n";              assert_eq "$SHADOW_HOSTED(env-file)" "$(R)" "m6-2 a commented-out hosted assignment still counts as a candidate => shadow"
envbase h4 "JEV_BASE_URL=$LOOP\n";                                                  assert_eq "enforce	promoted+validated" "$(R)" "m6-2 control: a single loopback assignment => enforce"
fx h5; printf 'garbage{' > "$CMA_PROVIDERS_DIR/jev-endpoints.json"
assert_ne "enforce	promoted+validated" "$(R)" "m6-2 an unparseable provider cache fails closed (not enforce)"
fx h6; export TYPESAFE_BASE_URL="$HOSTED"
assert_eq "$SHADOW_HOSTED" "$(R | cut -d'(' -f1)" "m6-2 TYPESAFE_BASE_URL (hosted) is read => shadow"
unset TYPESAFE_BASE_URL
fx h7; mkdir -p "$HOME/.claude-acct1"; jq -n --arg u "$HOSTED" '{projects:{"/p":{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}}}' > "$HOME/.claude-acct1/.claude.json"
assert_eq "$SHADOW_HOSTED(mcp-entry)" "$(R)" "m6-2 hosted base in \$HOME/.claude-*/.claude.json => shadow"
fx h8; mkdir -p "$B/.kimi-code"; jq -n --arg u "$HOSTED" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}' > "$B/.kimi-code/mcp.json"
assert_eq "$SHADOW_HOSTED(mcp-entry)" "$(R)" "m6-2 hosted base in <home>/.kimi-code/mcp.json => shadow"
fx h9; jq -n --arg u "$HOSTED" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}' > "$B/mcp.json"
assert_eq "$SHADOW_HOSTED(mcp-entry)" "$(R)" "m6-2 hosted base in <home>/mcp.json (Kimi) => shadow"

# ---- m6-1: status compares every MCP mode with the mode IN FORCE --------------------------------------------------------------
fx s1; rm -f "$JEV_CONFIG_DIR/env"; jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}' > "$B/.mcp.json"
unset JEV_TEST JEV_DECISION_PROFILES JEV_REQUIRE_VALIDATED_CMD
assert_eq "true" "$(status_json | jq -r '.mcp_mode_mismatch')" "m6-1 env file absent + MCP enforce while the mode in force is shadow => mismatch"
fx s2; printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$LOOP" > "$JEV_CONFIG_DIR/env"; jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}' > "$B/.mcp.json"
unset JEV_TEST JEV_DECISION_PROFILES JEV_REQUIRE_VALIDATED_CMD
assert_eq "true" "$(status_json | jq -r '.mcp_mode_mismatch')" "m6-1 stored enforce, effective shadow (no validated profile), MCP enforce => mismatch"

# ---- m6-3 / m6-4: stage 5 rewrites EVERY jev entry in the covered set; symlinks survive ----------------------------------------
fx t1; printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$LOOP" > "$JEV_CONFIG_DIR/env"; rm -f "$JEV_CONFIG_DIR/jev-thresholds.json"
mkdir -p "$HOME/.claude-acct1" "$B/.kimi-code"
jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}' > "$B/.mcp.json"
jq -n --arg u "$LOOP" '{projects:{"/p":{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}}}' > "$HOME/.claude-acct1/.claude.json"
jq -n --arg u "$LOOP" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u,JEV_MODE:"enforce"}}}}' > "$B/.kimi-code/mcp.json"
bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$B/.mcp.json")" "m6-3 stage 5 downgraded <home>/.mcp.json"
assert_eq "shadow" "$(jq -r '.projects["/p"].mcpServers.jev.env.JEV_MODE' "$HOME/.claude-acct1/.claude.json")" "m6-3 stage 5 downgraded a nested entry in \$HOME/.claude-*/.claude.json"
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$B/.kimi-code/mcp.json")" "m6-3 stage 5 downgraded <home>/.kimi-code/mcp.json"
fx t2; printf '{"mcpServers":{"jev":{"env":{"JEV_BASE_URL":"%s","JEV_MODE":"enforce"}}}}\n' "$LOOP" > "$T/real-mcp.json"; rm -f "$B/.mcp.json"; ln -s "$T/real-mcp.json" "$B/.mcp.json"
printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$LOOP" > "$T/real-env"; rm -f "$JEV_CONFIG_DIR/env" "$JEV_CONFIG_DIR/jev-thresholds.json"; ln -s "$T/real-env" "$JEV_CONFIG_DIR/env"
bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null
[ -L "$B/.mcp.json" ] && ok "m6-4 a symlinked .mcp.json is still a symlink after the stage-5 write" || fail "m6-4 .mcp.json symlink was replaced by a regular file"
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$T/real-mcp.json")" "m6-4 ... and the write landed in the link target"
[ -L "$JEV_CONFIG_DIR/env" ] && ok "m6-4 a symlinked env file is still a symlink after the write" || fail "m6-4 env file symlink was replaced"
fx t3; printf 'JEV_MODE=enforce\n' > "$T/real-env"; rm -f "$JEV_CONFIG_DIR/env"; ln -s "$T/real-env" "$JEV_CONFIG_DIR/env"
env JEV_MODE=shadow bash "$REG" >/dev/null 2>&1 </dev/null
[ -L "$JEV_CONFIG_DIR/env" ] && ok "m6-4 register keeps a symlinked env file a symlink" || fail "m6-4 register replaced the env-file symlink"

# ---- m6-5: register refuses shell-active values -------------------------------------------------------------------------------
fx u1; printf 'JEV_MODE=shadow\n' > "$JEV_CONFIG_DIR/env"
env JEV_MODE=shadow JEV_MODEL='a;cmd' bash "$REG" >"$T/u1.out" 2>&1 </dev/null; rc=$?
assert_nonzero "$rc" "m6-5 JEV_MODEL='a;cmd' is refused"
assert_not_contains "$JEV_CONFIG_DIR/env" 'a;cmd' "m6-5 ... and never reaches the env file"
fx u2; env JEV_MODE=shadow JEV_BASE_URL='http://127.0.0.1:8095/$(id)' bash "$REG" >"$T/u2.out" 2>&1 </dev/null; rc=$?
assert_nonzero "$rc" "m6-5 JEV_BASE_URL with a command substitution is refused"
fx u3; env JEV_MODE=shadow JEV_BASE_URL='http://127.0.0.1:8095/ok/path' bash "$REG" >"$T/u3.out" 2>&1 </dev/null; rc=$?
assert_eq "0" "$rc" "m6-5 control: a plain loopback URL with a path is accepted"

# ---- n6-1: JEV_NOW_EPOCH is JEV_TEST-only in every component ----------------------------------------------------------------
fx n1; unset JEV_TEST JEV_DETECTION_FILE; rm -f "$JEV_EVIDENCE_DIR/jev-detection.json"; export JEV_NOW_EPOCH=1700000000
( cd "$T" && bash "$BS" --non-interactive >/dev/null 2>&1 </dev/null )
assert_eq "true" "$(jq -r '(.generated_at // 0) > 1750000000' "$JEV_EVIDENCE_DIR/jev-detection.json" 2>/dev/null)" "n6-1 JEV_NOW_EPOCH without JEV_TEST=1 is ignored by bootstrap (record is dated with the real clock)"

# ---- n6-3: the stub-server wait is long and its failure is distinct -------------------------------------------------------------
assert_contains "$HERE/test_bootstrap_e2e_stub_server.sh" "seq 1 300" "n6-3 stub-server start-up wait raised to 30 s"
assert_contains "$HERE/test_bootstrap_e2e_stub_server.sh" "harness start-up failure" "n6-3 a slow start is reported as a harness failure, not a product assertion"

finish
