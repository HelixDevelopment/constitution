#!/usr/bin/env bash
# test_review_fixes.sh — regression tests for the independent review of the decision-layer change
# (NO-GO: B1, I1-I3 and 8 minors). Written RED-first; every case drives the REAL script. No network:
# curl is always a recording stub, llmctl a stub, every key a DUMMY assembled from fragments.
#   B1   a key is sent ONLY to an https URL whose origin AND variable name match a provider pin
#   I1   gate clause 7 accepts the two lawful empty records, and the llmctl calls are bounded
#   I2   the hosted-curl stub never reaches the real curl
#   I3   no unsupported claim in the anchor/docs
#   M    key_state order, backslash, quoting, keys-file timeout, clause-8 independence, ca_file,
#        leak-scan control needle, wiring clause 5 over provider .env files, register.sh enforce
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
GATES="$REPO/scripts/gates"
PROBE="$REPO/scripts/jev/jev-probe.sh"

KEY="$(printf '%s-%s-%s' dummyk1 A1b2C3d4 E5f6G7h8I9j0)"
QKEY="$(printf 'dummyq"%s\\%s-%s' A1b2C3 d4E5f6 G7h8I9j0)"     # contains a double quote and a backslash

setup() {
  make_fixture_env "$1"
  REC="$T/rec"; mkdir -p "$REC" "$T/rbin"; export REC_DIR="$REC"
  cat > "$T/rbin/curl" <<'EOF'
#!/usr/bin/env bash
# recording curl stub: argv + stdin config are recorded; no network, ever.
out="${REC_DIR:?}"; printf '%s\n' "$*" >> "$out/curl.argv"
usecfg=0; prev=""; for a in "$@"; do [ "$prev" = "-K" ] && [ "$a" = "-" ] && usecfg=1; prev="$a"; done
[ "$usecfg" = 1 ] && cat >> "$out/curl.stdin"
printf '%s' "${REC_CODE:-200}"
EOF
  chmod +x "$T/rbin/curl"; export PATH="$T/rbin:$PATH"
  PINS="$T/pins.json"
  jq -n '{hosted:{typesafe:{key_var:"TYPESAFE_API_KEY",base_url:"https://api.typesafe.test",systemone_path:"/v1/systemone",models:["jev-latest"],enabled:true},
          openrouter:{key_var:"OPENROUTER_API_KEY",base_url:"https://api.openrouter.test/api",systemone_path:"/v1/systemone",models:["typesafe/jev-1.13"],enabled:true}},
          local_gateway:{host:"127.0.0.1",port:8095,scheme:"https",key_var:"LLMCTL_API_KEY",enabled:true}}' > "$PINS"
  export CMA_JEV_PINS_FILE="$PINS"
  KEYS="$HOME/api_keys.sh"
}
mkrec() { # mkrec <file> <id> <url> <key_var>
  jq -n --arg id "$2" --arg u "$3" --arg kv "$4" \
    '{version:1,generated_at:1700000000,endpoints:[{id:$id,source:"api-keys-file",model:"jev-latest",reachable:true,probed_at:1700000000,parallel:1,url:$u,key_var:$kv,probe_path:"/v1/systemone",reachable_basis:"probe"}]}' > "$1"
}
sent_key() { [ -s "$REC/curl.stdin" ] && grep -qF -- "$1" "$REC/curl.stdin"; }

# ---- B1: jev-probe.sh never sends a key to an unpinned / non-https / mismatched origin -------------------------
refused() { # refused <label> <url> <key_var>
  setup b1; export TYPESAFE_API_KEY="$KEY" OPENROUTER_API_KEY="$KEY" SOME_UNRELATED_TOKEN="$KEY"
  mkrec "$T/det.json" ep "$2" "$3"
  JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "$2" >"$T/p.out" 2>"$T/p.err"; local rc=$?
  assert_ne "0" "$rc" "B1 $1: probe refuses (rc != 0)"
  if sent_key "$KEY"; then fail "B1 $1: KEY WAS SENT"; else ok "B1 $1: no key on any curl stdin"; fi
  if [ -s "$REC/curl.argv" ]; then fail "B1 $1: curl was invoked at all ($(head -c 120 "$REC/curl.argv"))"; else ok "B1 $1: curl never invoked"; fi
  assert_contains "$T/p.err" "refus" "B1 $1: the refusal is stated honestly (stderr)"
}
refused "http host, unrelated variable"      "http://attacker.example"                    SOME_UNRELATED_TOKEN
refused "https unpinned host, pinned var"    "https://attacker.example"                   TYPESAFE_API_KEY
refused "pinned host over plain http"        "http://api.typesafe.test"                   TYPESAFE_API_KEY
refused "pinned host, other pin's variable"  "https://api.typesafe.test"                  OPENROUTER_API_KEY
refused "userinfo trick"                     "https://api.typesafe.test@attacker.example" TYPESAFE_API_KEY
refused "suffix host trick"                  "https://api.typesafe.test.attacker.example" TYPESAFE_API_KEY
refused "pinned host, path outside the pin"  "https://api.openrouter.test/other"          OPENROUTER_API_KEY

setup b1p; export TYPESAFE_API_KEY="$KEY"
mkrec "$T/det.json" ep "https://api.typesafe.test" TYPESAFE_API_KEY
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "https://api.typesafe.test" >"$T/p.out" 2>"$T/p.err"; rc=$?
assert_rc 0 "$rc" "B1 POSITIVE: pinned https origin + its own variable is probed (rc 0)"
if sent_key "$KEY"; then ok "B1 POSITIVE: the key reached curl on stdin config"; else fail "B1 POSITIVE: the key did not reach curl stdin"; fi
assert_contains "$REC/curl.argv" "--proto =https" "B1 curl is pinned to https (--proto =https)"
assert_contains "$REC/curl.argv" "--proto-redir =https" "B1 redirects are pinned to https too"
assert_not_contains "$REC/curl.argv" "$KEY" "B1 the key is never on a command line"
# the pinned path prefix of a pin with a path
setup b1q; export OPENROUTER_API_KEY="$KEY"
mkrec "$T/det.json" ep "https://api.openrouter.test/api" OPENROUTER_API_KEY
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "https://api.openrouter.test/api" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "B1 POSITIVE: a pin with a path prefix is honoured"

# ---- B1b: the bootstrap toolkit-cache probe applies the same rule -----------------------------------------------------
setup b1b; export JEV_HOSTED_PROBE=1
printf 'export TYPESAFE_API_KEY=%q\n' "$KEY" > "$KEYS"; chmod 600 "$KEYS"
make_fixture_constitution_root with-submodules
jq -n '{endpoints:[{provider_id:"evil",base_url:"https://attacker.example",model:"jev-latest",key_var:"TYPESAFE_API_KEY"}]}' > "$T/eps.json"
mkdir -p "$CMA_PROVIDERS_DIR"; cp "$T/eps.json" "$CMA_PROVIDERS_DIR/jev-endpoints.json"
export FIXTURE_ENDPOINTS="$T/eps.json"
jq -n '{gateway:{running:false},profiles:[]}' > "$T/status.json"; export LLMCTL_STATUS_JSON="$T/status.json"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/b1b.out" 2>"$T/b1b.err"
DET="$JEV_EVIDENCE_DIR/jev-detection.json"
if [ -s "$REC/curl.argv" ] && grep -qF attacker.example "$REC/curl.argv"; then fail "B1b a tampered cache entry received a curl call"; else ok "B1b no curl call to the tampered cache host"; fi
if sent_key "$KEY" && ! grep -qF "api.typesafe.test" "$REC/curl.argv"; then fail "B1b key sent somewhere other than the pin"; else ok "B1b key only ever went to the pinned origin"; fi
assert_eq "refused" "$(jq -r '[.endpoints[]|select(.id=="evil")|.auth_status_class][0]' "$DET")" "B1b the tampered entry is recorded auth_status_class=refused"
assert_eq "null" "$(jq -r '[.endpoints[]|select(.id=="evil")|.reachable][0]' "$DET")" "B1b and is NOT reachable=true (refused is not an answer)"

# ---- M: curl-config quoting for a key containing " and \ -------------------------------------------------------------------
setup mq; export TYPESAFE_API_KEY="$QKEY"
mkrec "$T/det.json" ep "https://api.typesafe.test" TYPESAFE_API_KEY
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "https://api.typesafe.test" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "M quoting: probe with a quote/backslash key rc 0"
want="header = \"Authorization: Bearer ${QKEY//\\/\\\\}\""; want="${want//\"x/\\\"x}"
exp="$(printf '%s' "$QKEY" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
assert_eq "header = \"Authorization: Bearer $exp\"" "$(head -1 "$REC/curl.stdin" 2>/dev/null)" "M quoting: \" and \\ are escaped in the curl config (the key survives intact)"

# ---- M: a RECORD ca_file never reaches a keyed request (r2 I-new-1); the operator's JEV_CA_FILE env does -------------------------------------------------------------------------------------------
setup mca; export TYPESAFE_API_KEY="$KEY"; : > "$T/ca.pem"
mkrec "$T/det.json" ep "https://api.typesafe.test" TYPESAFE_API_KEY
jq --arg ca "$T/ca.pem" '.endpoints[0].ca_file=$ca' "$T/det.json" > "$T/det2.json"
JEV_DETECTION_FILE="$T/det2.json" bash "$PROBE" ep "https://api.typesafe.test" >/dev/null 2>&1
assert_not_contains "$REC/curl.argv" "--cacert" "M ca_file: the authenticated probe ignores the record's CA file (untrusted)"
setup mca2; export TYPESAFE_API_KEY="$KEY"; : > "$T/ca.pem"
mkrec "$T/det.json" ep "https://api.typesafe.test" TYPESAFE_API_KEY
JEV_CA_FILE="$T/ca.pem" JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "https://api.typesafe.test" >/dev/null 2>&1
assert_contains "$REC/curl.argv" "--cacert $T/ca.pem" "M ca_file: the OPERATOR's JEV_CA_FILE env is used on the authenticated probe"

# ---- M: key_state ----------------------------------------------------------------------------------------------------------------
setup ks
# shellcheck source=../../scripts/jev/lib_keys.sh
. "$REPO/scripts/jev/lib_keys.sh"
write_kv() { printf 'export TYPESAFE_API_KEY=%q\n' "$1" > "$KEYS"; chmod 600 "$KEYS"; }
write_kv "changeme"; r="$(key_state TYPESAFE_API_KEY)"
printf '%s' "$r" > "$T/r.txt"; assert_contains "$T/r.txt" "known dummy" "M key_state: 'changeme' is reported as a known dummy, not as 'shorter than 16'"
BS="$(printf '\\%.0s' $(seq 1 20))"; write_kv "$BS"; r="$(key_state TYPESAFE_API_KEY 2>"$T/ks.err")"
assert_eq "placeholder" "$(printf '%s' "$r" | cut -f1)" "M key_state: a value of 20 backslashes is a placeholder"
printf '%s' "$r" > "$T/r.txt"; assert_contains "$T/r.txt" "repeated" "M key_state: reason is 'one repeated character'"
assert_eq "0" "$(wc -c < "$T/ks.err" | tr -d ' ')" "M key_state: no tr/shell warning on a backslash-leading value"
write_kv "$(printf 'dummyk1-A1b2\nC3d4E5f6G7h8')"; r="$(key_state TYPESAFE_API_KEY)"
assert_ne "real" "$(printf '%s' "$r" | cut -f1)" "M key_state: a value with a newline is never 'real'"
write_kv "$KEY"; assert_eq "real" "$(key_state TYPESAFE_API_KEY)" "M key_state: control — a normal dummy key is real"
# keys file that never returns: bounded
printf 'sleep 300\nexport TYPESAFE_API_KEY=%q\n' "$KEY" > "$KEYS"
st=$(date +%s); r="$(JEV_KEYS_FILE_TIMEOUT=2 key_state TYPESAFE_API_KEY)"; el=$(( $(date +%s) - st ))
if [ "$el" -lt 15 ]; then ok "M keys-file timeout: key_state bounded (${el}s)"; else fail "M keys-file timeout: took ${el}s"; fi
assert_eq "absent" "$(printf '%s' "$r" | cut -f1)" "M keys-file timeout: reported absent (never real)"
printf '%s' "$r" > "$T/r.txt"; assert_contains "$T/r.txt" "timed out" "M keys-file timeout: the reason says so"

# ---- I1: gate clause 7 -----------------------------------------------------------------------------------------------------------
empty_rec() {
  jq -n '{version:1,generated_at:1700000000,endpoints:[],reason:"no decision endpoint",capacity:{decision_instances:0},
          tools:{llmctl:{source:"unavailable",reason:"fixture",ref:"unpinned",path:""},claude_toolkit:{source:"unavailable",reason:"fixture",ref:"unpinned",path:""}}}' > "$1"
}
fake_llmctl() { # fake_llmctl <status-json> <capacity-json>
  mkdir -p "$T/fb"; printf '%s' "$1" > "$T/fb/status.json"; printf '%s' "$2" > "$T/fb/cap.json"
  cat > "$T/fb/llmctl" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "decide status") cat "$T/fb/status.json" ;; "decide capacity") cat "$T/fb/cap.json" ;; *) exit 1 ;; esac
EOF
  chmod +x "$T/fb/llmctl"; export PATH="$T/fb:$PATH"
}
c7() { JEV_DETECTION_FILE="$T/empty.json" bash "$GATES/cm_jev_detection.sh" >"$T/c7.out" 2>&1; }
setup c7a; empty_rec "$T/empty.json"
fake_llmctl '{"gateway":{"running":true},"profiles":[]}' '{}'
c7; assert_rc 0 "$?" "I1 golden-FALSE: gateway running, no profile running => empty record is lawful"
setup c7b; empty_rec "$T/empty.json"
fake_llmctl '{"gateway":{"running":true},"profiles":[{"profile":"decide-tiny","running":true}]}' '{"decision_instances":{"decide-tiny":{"protocol":"jev-verdict","effective_slots_per_instance":2}}}'
c7; assert_rc 0 "$?" "I1 golden-FALSE: only a jev-verdict (no driver) profile running => empty record is lawful"
setup c7c; empty_rec "$T/empty.json"
fake_llmctl '{"gateway":{"running":true},"profiles":[{"profile":"decide-real","running":true}]}' '{"decision_instances":{"decide-real":{"protocol":"jev-json","effective_slots_per_instance":2}}}'
c7; assert_nonzero "$?" "I1 golden-TRUE: a running usable decision profile with an empty record => contradiction (RED)"
assert_contains "$T/c7.out" "decide-real" "I1 the contradiction names the profile"
assert_not_contains "$T/c7.out" "ok: clause 7" "M the gate prints no 'ok' for a clause that FAILed"
setup c7d; empty_rec "$T/empty.json"
mkdir -p "$T/fh"; printf '%s\n' '#!/usr/bin/env bash' 'sleep 300' > "$T/fh/llmctl"; chmod +x "$T/fh/llmctl"; export PATH="$T/fh:$PATH"
st=$(date +%s); JEV_TOOL_TIMEOUT=2 c7; rc=$?; el=$(( $(date +%s) - st ))
if [ "$el" -lt 20 ]; then ok "I1 the llmctl call is bounded (${el}s with a hanging llmctl)"; else fail "I1 gate took ${el}s with a hanging llmctl"; fi
assert_rc 0 "$rc" "I1 a hanging llmctl cannot cross-check: NOTE, not a FAIL"
assert_contains "$T/c7.out" "timed out" "I1 the timeout is stated"

# ---- M: clause 8 judges the RECORD's key state, not the runner's environment ----------------------------------------------
setup c8; empty_rec "$T/x.json"
jq -n '{version:1,generated_at:1700000000,endpoints:[{id:"hosted-typesafe",source:"api-keys-file",model:"jev-latest",reachable:null,reachable_basis:"probe-unavailable",probed_at:1700000000,parallel:1,url:"https://api.typesafe.test",key_var:"TYPESAFE_API_KEY"}],
        capacity:{decision_instances:0},key_discovery:{vars:[{key_var:"TYPESAFE_API_KEY",state:"placeholder"}]},
        tools:{llmctl:{source:"unavailable",reason:"f",ref:"u",path:""},claude_toolkit:{source:"unavailable",reason:"f",ref:"u",path:""}}}' > "$T/rec8.json"
printf 'export TYPESAFE_API_KEY=%q\n' "$KEY" > "$KEYS"; chmod 600 "$KEYS"      # the RUNNER holds a real key
JEV_DETECTION_FILE="$T/rec8.json" bash "$GATES/cm_jev_detection.sh" >"$T/c8a.out" 2>&1
assert_rc 0 "$?" "M clause 8: record says placeholder at detection time => same verdict on a host that has a real key"
jq '.key_discovery.vars[0].state="real"' "$T/rec8.json" > "$T/rec8b.json"; rm -f "$KEYS"
JEV_DETECTION_FILE="$T/rec8b.json" bash "$GATES/cm_jev_detection.sh" >"$T/c8b.out" 2>&1
assert_nonzero "$?" "M clause 8: record says a real key was present and the endpoint is unproven => RED on a host without the key"
jq 'del(.key_discovery)' "$T/rec8.json" > "$T/rec8c.json"; printf 'export TYPESAFE_API_KEY=%q\n' "$KEY" > "$KEYS"
JEV_DETECTION_FILE="$T/rec8c.json" bash "$GATES/cm_jev_detection.sh" >"$T/c8c.out" 2>&1
assert_contains "$T/c8c.out" "depends on the environment" "M clause 8: a record without key_discovery falls back to the host and says the verdict is environment-dependent"

# ---- M: wiring clause 5 sees provider .env files ---------------------------------------------------------------------------------
setup w5
mkdir -p "$HOME/.claude" "$CMA_PROVIDERS_DIR"
jq -n '{endpoints:[{id:"llmctl-decide-x",source:"local-llmctl",model:"decide-x-model",reachable:true,url:"https://127.0.0.1:1",parallel:1,probed_at:1}]}' > "$T/det.json"
printf 'ANTHROPIC_MODEL=decide-x-model\n' > "$CMA_PROVIDERS_DIR/someprovider.env"
JEV_HOME="$HOME" JEV_DETECTION_FILE="$T/det.json" bash "$GATES/cm_jev_wiring.sh" >"$T/w5.out" 2>&1
assert_contains "$T/w5.out" "someprovider.env" "M wiring clause 5: a decision model wired as a chat model in a provider .env is caught"
rm -f "$CMA_PROVIDERS_DIR/someprovider.env"
JEV_HOME="$HOME" JEV_DETECTION_FILE="$T/det.json" bash "$GATES/cm_jev_wiring.sh" >"$T/w5b.out" 2>&1
assert_not_contains "$T/w5b.out" "clause5:" "M wiring clause 5 NEG: with no offending provider file nothing is flagged"
printf 'models.json hit\n{"m":"llmctl-decide-x"}\n' > "$HOME/.claude/models.json"
JEV_HOME="$HOME" JEV_DETECTION_FILE="$T/det.json" bash "$GATES/cm_jev_wiring.sh" >"$T/w5c.out" 2>&1
assert_eq "1" "$(grep -c "clause5: decision endpoint id 'llmctl-decide-x' found" "$T/w5c.out")" "M wiring clause 5: one finding per config file (no duplicate find results)"

# ---- M: register.sh never copies an uncalibrated enforce -----------------------------------------------------------------------------
setup rg
B="$T/box"; mkdir -p "$B/.claude" "$B/.config/jev"
JEV_CONFIG_DIR="$B/.config/jev" JEV_HOME="$B" JEV_MODE=enforce bash "$REPO/skills/jev-decision-layer/register.sh" >"$T/rg.out" 2>"$T/rg.err"
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$B/.config/jev/env" | cut -d= -f2)" "M register: JEV_MODE=enforce without calibrated thresholds is written as shadow"
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE // "shadow"' "$B/.mcp.json" 2>/dev/null || echo shadow)" "M register: the MCP entry carries shadow too"
assert_contains "$T/rg.err" "enforce" "M register: the downgrade is stated (stderr)"
B2="$T/box2"; mkdir -p "$B2/.claude" "$B2/.config/jev"
jq -n '{per_type:{gate:{threshold:0.9,promoted:true}}}' > "$B2/.config/jev/jev-thresholds.json"
seed_local_detection "$T/det_l.json" decide-x
JEV_TEST=1 JEV_BASE_URL=https://127.0.0.1:8095 JEV_DETECTION_FILE="$T/det_l.json" JEV_CONFIG_DIR="$B2/.config/jev" JEV_REQUIRE_VALIDATED_CMD=true JEV_DECISION_PROFILES=decide-x JEV_HOME="$B2" JEV_MODE=enforce bash "$REPO/skills/jev-decision-layer/register.sh" >/dev/null 2>&1
assert_eq "enforce" "$(grep -s '^JEV_MODE=' "$B2/.config/jev/env" | cut -d= -f2)" "M register NEG: with calibrated thresholds enforce is honoured"

# ---- I2: the hosted curl stub never reaches the real curl -------------------------------------------------------------------------------
setup i2
export STUB_LOG="$T/log"; mkdir -p "$STUB_LOG"
"$FIXTURES/bin-hosted/curl" -sS -o /dev/null -w '%{http_code}' https://not-a-stub-host.example/x >"$T/i2.out" 2>"$T/i2.err"; rc=$?
assert_ne "0" "$rc" "I2 an unknown host fails in the stub"
assert_contains "$STUB_LOG/curl.log" "REFUSED_UNKNOWN_HOST" "I2 and is logged as refused (no passthrough to the real curl)"
if grep -n 'exec /usr/bin/curl\|exec curl' "$FIXTURES/bin-hosted/curl" >/dev/null 2>&1; then fail "I2 the stub still contains a passthrough to the real curl"; else ok "I2 no passthrough exec remains in the stub"; fi
assert_contains "$HERE/test_hosted_key_discovery.sh" "api.openrouter.test" "I2 the openrouter pin host matches the stub glob"

# ---- M: the leak scan has a control needle ------------------------------------------------------------------------------------------------------
setup lk
printf '%s\n' "$KEY" > "$T/planted.txt"
assert_eq "1" "$(leaks_count "$KEY" "$T")" "M leaks_count sees a planted needle"
assert_eq "0" "$(leaks_count "not-present-needle-zzzz" "$T")" "M leaks_count negative control"
leak_scan_selftest "$T"; assert_rc 0 "$?" "M leak_scan_selftest passes on a readable root"
leak_scan_selftest "$T/does-not-exist" 2>/dev/null; assert_nonzero "$?" "M leak_scan_selftest FAILS on a blind (missing) root — a blind grep cannot report 0 leaks"

# ---- I3: unsupported claims withdrawn ----------------------------------------------------------------------------------------------------------------
CANON="$REPO/Constitution.md"
assert_not_contains "$CANON" "authentication class of 2xx with zero key-prefix hits" "I3 the unevidenced 2xx live claim is withdrawn from the anchor"
for f in "$REPO/docs/jev/bootstrap-reference.md" "$REPO/docs/jev/governance-guide.md" "$CANON"; do
  assert_not_contains "$f" "SERVED IMMEDIATELY" "I3 no 'served immediately' claim in $(basename "$f")"
  assert_not_contains "$f" "Every external call is bounded" "I3 no unqualified 'every external call is bounded' in $(basename "$f")"
done
finish
