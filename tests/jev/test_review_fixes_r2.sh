#!/usr/bin/env bash
# test_review_fixes_r2.sh — regression tests for the ROUND-2 independent review of the decision layer
# (NO-GO: I-new-1, I-new-2 and minors m1-m5 + the userinfo mutant). Written RED-first; every case drives the REAL
# script. curl is a recording stub, llmctl a stub, every key a DUMMY assembled from fragments, no network.
#   I-new-1  a record `ca_file` NEVER reaches --cacert on a request that carries a key (operator JEV_CA_FILE may)
#   I-new-2  the gate and bootstrap classify a registry service by ONE predicate (labels.profile // name)
#   m1       percent-encoded dot/slash/control segments refused; explicit :443 accepted; shared-origin pins
#   m3       enforce needs a PROMOTED type (register + wiring gate), JEV_CONFIG_DIR honoured, require-validated
#   m4       mktemp for the refusal file; plain GET only to loopback / llmctl-* / pinned origin; --proto =http,https
#   m5       an ambient JEV_PINS_FILE never differs from bootstrap's view (builtin pins => unset)
#   m2       no request reaches the live gateway ports (8095/8096): the guard curl shim refuses and logs
#   item 5   the `@` userinfo check is pinned by its own reason string
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl python3; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
GATES="$REPO/scripts/gates"
PROBE="$REPO/scripts/jev/jev-probe.sh"
KEY="$(printf '%s-%s-%s' dummyk1 A1b2C3d4 E5f6G7h8I9j0)"

setup() {
  make_fixture_env "$1"
  REC="$T/rec"; mkdir -p "$REC" "$T/rbin"; export REC_DIR="$REC"
  cat > "$T/rbin/curl" <<'XEOF'
#!/usr/bin/env bash
out="${REC_DIR:?}"; printf '%s\n' "$*" >> "$out/curl.argv"
printf '%s\n' "${JEV_PINS_FILE:-unset}" >> "$out/curl.pinsenv"
usecfg=0; prev=""; for a in "$@"; do [ "$prev" = "-K" ] && [ "$a" = "-" ] && usecfg=1; prev="$a"; done
[ "$usecfg" = 1 ] && cat >> "$out/curl.stdin"
printf '%s' "${REC_CODE:-200}"
XEOF
  chmod +x "$T/rbin/curl"; export PATH="$T/rbin:$PATH"
  PINS="$T/pins.json"
  jq -n '{hosted:{typesafe:{key_var:"TYPESAFE_API_KEY",base_url:"https://api.typesafe.test",systemone_path:"/v1/systemone",models:["jev-latest"],enabled:true},
          openrouter:{key_var:"OPENROUTER_API_KEY",base_url:"https://api.openrouter.test/api",systemone_path:"/v1/systemone",models:["typesafe/jev-1.13"],enabled:true}},
          local_gateway:{host:"127.0.0.1",port:8095,scheme:"https",key_var:"LLMCTL_API_KEY",enabled:true}}' > "$PINS"
  export CMA_JEV_PINS_FILE="$PINS"
  unset JEV_CA_FILE
}
mkrec() { # mkrec <file> <id> <url> <key_var> [ca]
  jq -n --arg id "$2" --arg u "$3" --arg kv "$4" --arg ca "${5:-}" \
    '{version:1,generated_at:1700000000,endpoints:[{id:$id,source:"api-keys-file",model:"jev-latest",reachable:true,probed_at:1700000000,parallel:1,url:$u,probe_path:"/v1/systemone",reachable_basis:"probe"}
       + (if $kv != "" then {key_var:$kv} else {} end) + (if $ca != "" then {ca_file:$ca} else {} end)]}' > "$1"
}

# ---- I-new-1: the record's ca_file never replaces system trust on a keyed request ----------------------------------------
setup n1; export TYPESAFE_API_KEY="$KEY"; : > "$T/evil-ca.pem"
mkrec "$T/det.json" ep "https://api.typesafe.test" TYPESAFE_API_KEY "$T/evil-ca.pem"
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "https://api.typesafe.test" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "N1 keyed probe still answers (system trust)"
assert_not_contains "$REC/curl.argv" "--cacert" "N1 a record ca_file never reaches --cacert on a keyed request"
assert_not_contains "$REC/curl.argv" "evil-ca.pem" "N1 the record's CA path is not on curl's argv at all"
setup n1e; export TYPESAFE_API_KEY="$KEY"; : > "$T/op-ca.pem"
mkrec "$T/det.json" ep "https://api.typesafe.test" TYPESAFE_API_KEY "$T/evil-ca.pem"
JEV_CA_FILE="$T/op-ca.pem" JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" ep "https://api.typesafe.test" >/dev/null 2>&1
assert_contains "$REC/curl.argv" "--cacert $T/op-ca.pem" "N1-POS the OPERATOR's JEV_CA_FILE env is honoured on a keyed request"
assert_not_contains "$REC/curl.argv" "evil-ca.pem" "N1-POS and the record CA is still ignored"
setup n1u; : > "$T/loc-ca.pem"
mkrec "$T/det.json" llmctl-decide-x "https://127.0.0.1:9" "" "$T/loc-ca.pem"
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" llmctl-decide-x "https://127.0.0.1:9" >/dev/null 2>&1
assert_contains "$REC/curl.argv" "--cacert $T/loc-ca.pem" "N1-POS an UNKEYED local llmctl-* probe may use the record's CA (no key travels)"

# ---- m4: refusal file via mktemp; plain GET only to loopback / llmctl-* / a pinned origin; --proto ---------------------
assert_not_contains "$PROBE" '.jev-probe-refusal.$$' "M4 no predictable \$\$ temp name in jev-probe.sh"
assert_not_contains "$PROBE" ".jev-probe-refusal" "M4 no refusal temp file at all (stderr is captured in-process)"
setup m4a
mkrec "$T/det.json" other-ep "https://attacker.example/x" ""
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" other-ep "https://attacker.example/x" >"$T/m4a.out" 2>"$T/m4a.err"; rc=$?
assert_rc 2 "$rc" "M4 an untrusted record URL (unpinned, non-loopback, not llmctl-*) is not even GET-probed (rc 2)"
if [ -s "$REC/curl.argv" ]; then fail "M4 curl was started for an unpinned non-loopback host"; else ok "M4 curl never started for it"; fi
assert_contains "$T/m4a.err" "refus" "M4 the refusal is stated"
setup m4b
mkrec "$T/det.json" other-ep "http://127.0.0.1:9/x" ""
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" other-ep "http://127.0.0.1:9/x" >/dev/null 2>&1
assert_contains "$REC/curl.argv" "--proto =http,https" "M4 plain GETs are pinned to http(s) only"
assert_contains "$REC/curl.argv" "127.0.0.1:9/x" "M4-POS a loopback URL IS probed"
setup m4c
mkrec "$T/det.json" hosted-x "https://api.typesafe.test" ""
JEV_DETECTION_FILE="$T/det.json" bash "$PROBE" hosted-x "https://api.typesafe.test" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "M4-POS a pinned origin without a key var is still GET-probed"

# ---- item 5: the userinfo check is pinned by its own reason ------------------------------------------------------------------
. "$REPO/scripts/jev/lib_keys.sh"
for u in "https://api.typesafe.test@attacker.example/v1" "https://user:pw@api.typesafe.test/v1"; do
  setup u5; msg="$(jev_pin_ok TYPESAFE_API_KEY "$u" 2>&1 >/dev/null)"; rc=$?
  assert_ne "0" "$rc" "U5 userinfo URL refused"
  printf '%s' "$msg" > "$T/u5.msg"
  assert_contains "$T/u5.msg" "not a plain https URL" "U5 refused BY the userinfo check (reason: not a plain https URL), not by an origin mismatch"
done

# ---- m1: percent-encoded segments, :443, two pins sharing an origin ----------------------------------------------------------
for u in "https://api.openrouter.test/api/%2e%2e/evil" "https://api.openrouter.test/api/%2E%2E/x" "https://api.typesafe.test/v1/%0d%0aX" \
         "https://api.openrouter.test/api/a%2fb" "https://api.openrouter.test/api/a%5Cb" "https://api.openrouter.test/api/%2E/x"; do
  setup m1; v=OPENROUTER_API_KEY; case "$u" in *typesafe*) v=TYPESAFE_API_KEY ;; esac
  jev_pin_ok "$v" "$u" >/dev/null 2>&1; rc=$?
  assert_ne "0" "$rc" "M1 percent-encoded dot/slash/control segment refused: ${u#https://}"
done
setup m1b; jev_pin_ok TYPESAFE_API_KEY "https://api.typesafe.test:443/v1/systemone" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "M1-POS an explicit :443 equals the pinned origin"
setup m1c; jev_pin_ok TYPESAFE_API_KEY "https://api.typesafe.test:8443/v1" >/dev/null 2>&1; rc=$?
assert_ne "0" "$rc" "M1-NEG a different port is a different origin"
setup m1d
jq -n '{hosted:{a:{key_var:"A_API_KEY",base_url:"https://shared.test/one",enabled:true},b:{key_var:"B_API_KEY",base_url:"https://shared.test/two",enabled:true}}}' > "$T/pins2.json"
export CMA_JEV_PINS_FILE="$T/pins2.json"
jev_pin_ok B_API_KEY "https://shared.test/two/x" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "M1 two pins on one origin: the SECOND pin's variable + path is accepted"
jev_pin_ok A_API_KEY "https://shared.test/one/x" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "M1 two pins on one origin: the first pin still accepted"
jev_pin_ok A_API_KEY "https://shared.test/two/x" >/dev/null 2>&1; rc=$?
assert_ne "0" "$rc" "M1-NEG a variable on the wrong pin's path is refused"
jev_pin_ok C_API_KEY "https://shared.test/one/x" >/dev/null 2>&1; rc=$?
assert_ne "0" "$rc" "M1-NEG an unrelated variable is refused on a shared origin"

# ---- I-new-2: one predicate for gate and bootstrap ---------------------------------------------------------------------------
empty_rec() {
  jq -n '{version:1,generated_at:1700000000,endpoints:[],reason:"no decision endpoint",capacity:{decision_instances:0},
          tools:{llmctl:{source:"unavailable",reason:"fixture",ref:"unpinned",path:""},claude_toolkit:{source:"unavailable",reason:"fixture",ref:"unpinned",path:""}}}' > "$1"
}
mkstatus() { # mkstatus <name> <label-profile>
  jq -n --arg n "$1" --arg p "$2" '{gateway:{running:true},profiles:[],registry:{services:[{name:$n,protocol:"http",healthy:true,url:"http://127.0.0.1:9",labels:{kind:"decide",profile:$p}}]}}'
}
run_bs() { bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive >"$T/bs.out" 2>"$T/bs.err"; RC=$?; DET="$JEV_EVIDENCE_DIR/jev-detection.json"; }
for case_ in "verdict:decide-tiny:jev-verdict" "json:decide-real:jev-json"; do
  IFS=: read -r tag lbl proto <<< "$case_"
  setup p; make_fixture_constitution_root with-submodules; empty_rec "$T/empty.json"
  mkstatus "svc-other-name" "$lbl" > "$T/status.json"
  jq -n --arg l "$lbl" --arg p "$proto" '{decision_instances:{($l):{protocol:$p,effective_slots_per_instance:2}}}' > "$T/cap.json"
  export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
  JEV_DETECTION_FILE="$T/empty.json" bash "$GATES/cm_jev_detection.sh" >"$T/gate.out" 2>&1; grc=$?
  run_bs; n="$(jq '.endpoints|length' "$DET" 2>/dev/null || echo X)"
  if [ "$proto" = "jev-verdict" ]; then
    assert_rc 0 "$grc" "P1 label!=name, profile protocol jev-verdict: the gate calls the empty record lawful"
    assert_eq "0" "$n" "P1 and bootstrap detects no endpoint (the two agree)"
  else
    assert_ne "0" "$grc" "P2 label!=name, usable profile: the gate calls the empty record a contradiction"
    assert_eq "1" "$n" "P2 and bootstrap detects ONE endpoint (the two agree)"
  fi
done
assert_contains "$REPO/scripts/jev/lib_decide.sh" "jev_decide_services" "P3 the shared predicate lives in lib_decide.sh"

# ---- m3: enforce needs a PROMOTED type; JEV_CONFIG_DIR; require-validated ----------------------------------------------------
setup rg
seed_local_detection "$T/det_local.json" decide-x   # enforce needs a local-llmctl endpoint in the record (r3 I3-3)
reg() { # reg <box> [cfgdir]  (JEV_CONFIG_DIR from the fixture env is overridden explicitly)
  JEV_TEST=1 JEV_DETECTION_FILE="$T/det_local.json" JEV_CONFIG_DIR="${2:-$1/.config/jev}" JEV_HOME="$1" JEV_MODE=enforce bash "$REPO/skills/jev-decision-layer/register.sh" >"$T/rg.out" 2>"$T/rg.err"; }
mode_of() { grep -s '^JEV_MODE=' "$1" | cut -d= -f2; }
B="$T/box"; mkdir -p "$B/.claude" "$B/.config/jev"
jq -n '{per_type:{noul:{threshold:0.9,promoted:false}}}' > "$B/.config/jev/jev-thresholds.json"
export JEV_TEST=1 JEV_BASE_URL=https://127.0.0.1:8095 JEV_REQUIRE_VALIDATED_CMD="true" JEV_DECISION_PROFILES="decide-x"
reg "$B"; assert_eq "shadow" "$(mode_of "$B/.config/jev/env")" "M3 an UNPROMOTED type with a numeric threshold does not enable enforce"
B2="$T/box2"; mkdir -p "$B2/.claude" "$T/cfg2"
jq -n '{per_type:{noul:{threshold:0.9,promoted:true}}}' > "$T/cfg2/jev-thresholds.json"
reg "$B2" "$T/cfg2"
assert_eq "enforce" "$(mode_of "$T/cfg2/env")" "M3-POS promoted type + validated PASS + relocated JEV_CONFIG_DIR => enforce (env written under JEV_CONFIG_DIR)"
B3="$T/box3"; mkdir -p "$B3/.claude" "$T/cfg3"
cp "$T/cfg2/jev-thresholds.json" "$T/cfg3/jev-thresholds.json"
JEV_REQUIRE_VALIDATED_CMD="false" reg "$B3" "$T/cfg3"
assert_eq "shadow" "$(mode_of "$T/cfg3/env")" "M3 promoted type but require-validated FAILS => honest downgrade to shadow"
assert_contains "$T/rg.err" "require-validated" "M3 the downgrade names require-validated on stderr"
unset JEV_REQUIRE_VALIDATED_CMD JEV_DECISION_PROFILES
# wiring gate clause 6
w6() { # w6 <thresholds-json>
  setup w6; mkdir -p "$JEV_CONFIG_DIR"; printf 'JEV_MODE=enforce\n' > "$JEV_CONFIG_DIR/env"; printf '%s' "$1" > "$JEV_CONFIG_DIR/jev-thresholds.json"
  empty_rec "$T/det.json"
  JEV_HOME="$HOME" JEV_CONFIG_DIR="$JEV_CONFIG_DIR" JEV_DETECTION_FILE="$T/det.json" bash "$GATES/cm_jev_wiring.sh" >"$T/w6.out" 2>&1; return $?
}
w6 '{"per_type":{"noul":{"threshold":0.9,"promoted":false}}}'; assert_nonzero "$?" "M3 wiring clause 6: enforce with only UNPROMOTED types FAILs"
assert_contains "$T/w6.out" "no type is PROMOTED" "M3 and the failure is clause 6's own (not an unrelated clause)"
w6 '{"per_type":{"noul":{"threshold":0.9,"promoted":true}}}'; rc=$?
if grep -q "clause 6" "$T/w6.out" && ! grep -qi "FAIL.*thresholds" "$T/w6.out"; then ok "M3-POS wiring clause 6: a promoted type satisfies the clause"; else fail "M3-POS wiring clause 6 rejected a promoted type (rc $rc)"; fi

# ---- m5: ambient JEV_PINS_FILE vs bootstrap's builtin pins -------------------------------------------------------------------
setup m5; make_fixture_constitution_root with-submodules
unset CMA_JEV_PINS_FILE
jq -n '{hosted:{evil:{key_var:"EVIL_API_KEY",base_url:"https://evil.test",enabled:true}}}' > "$T/ambient.json"
nice -n 10 python3 "$FIXTURES/jev_server.py" 0 >"$T/srv.port" 2>/dev/null & SRV=$!
trap 'kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null' EXIT
for _ in $(seq 1 50); do grep -q '^PORT ' "$T/srv.port" 2>/dev/null && break; sleep 0.1; done
PORT="$(sed -n 's/^PORT //p' "$T/srv.port" | head -1)"
jq -n --arg u "http://127.0.0.1:$PORT" '{gateway:{running:true},profiles:[{profile:"decide-real",running:true}],registry:{services:[{name:"decide-gateway",protocol:"http",healthy:true,url:$u,labels:{kind:"gateway",profile:"decide"}}]}}' > "$T/status.json"
jq -n '{decision_instances:{"decide-real":{protocol:"jev-json",effective_slots_per_instance:1}}}' > "$T/cap.json"
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
JEV_PINS_FILE="$T/ambient.json" run_bs
assert_eq "builtin-default" "$(jq -r '.key_discovery.pins_source // "?"' "$DET" 2>/dev/null)" "M5 bootstrap used the builtin pins"
if [ -s "$REC/curl.pinsenv" ] && ! grep -qv '^unset$' "$REC/curl.pinsenv"; then ok "M5 no child of bootstrap ever sees the ambient JEV_PINS_FILE"; else fail "M5 a child saw JEV_PINS_FILE=$(sort -u "$REC/curl.pinsenv" 2>/dev/null | head -2 | tr '\n' ' ')"; fi

# ---- m2: the guard curl never lets a request reach the live gateway ports --------------------------------------------------------
setup m2; make_fixture_constitution_root with-submodules
GUARD="$FIXTURES/bin/curl"; export STUB_LOG="$T/log"; mkdir -p "$STUB_LOG"
PATH="$FIXTURES/bin:$(echo "$PATH" | tr ':' '\n' | grep -vxF "$T/rbin" | paste -sd:)" "$GUARD" -sS -o /dev/null https://127.0.0.1:8095/healthz; rc=$?
assert_eq "7" "$rc" "M2 guard curl refuses the live decide-gateway port (8095)"
PATH="$FIXTURES/bin:$(echo "$PATH" | tr ':' '\n' | grep -vxF "$T/rbin" | paste -sd:)" "$GUARD" -sS -o /dev/null http://127.0.0.1:8096/healthz; rc=$?
assert_eq "7" "$rc" "M2 guard curl refuses the live decide-service port (8096)"
assert_eq "2" "$(grep -c 'refused live port' "$STUB_LOG/guard-curl.log" 2>/dev/null || echo 0)" "M2 both refusals are logged"
assert_eq "0" "$(grep -c '127.0.0.1:8096' "$HERE"/test_decision_layer_gaps.sh | tr -d ' ')" "M2 test_decision_layer_gaps.sh no longer names the live decide-service port 8096 in fixtures"

# m2 end-to-end: the documented default gateway (basis llmctl-default-port) is never really contacted
setup m2e; make_fixture_constitution_root with-submodules
export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vxF "$T/rbin" | paste -sd:)"
export STUB_LOG="$T/log2"; mkdir -p "$STUB_LOG"
jq -n '{gateway:{running:true},profiles:[{profile:"decide-real",running:true}],registry:{services:[]}}' > "$T/status.json"
jq -n '{decision_instances:{"decide-real":{protocol:"jev-json",effective_slots_per_instance:1}}}' > "$T/cap.json"
export LLMCTL_STATUS_JSON="$T/status.json" LLMCTL_CAPACITY_JSON="$T/cap.json"
unset LLMCTL_ENDPOINT LLMCTL_DECIDE_PORT
run_bs
assert_eq "llmctl-default-port" "$(jq -r '.endpoints[0].url_basis // "?"' "$DET" 2>/dev/null)" "M2E the fixture really took the default-port fallback"
assert_eq "false" "$(jq -r '.endpoints[0].reachable' "$DET" 2>/dev/null)" "M2E default gateway: reachable=false (the guard refused the live port)"
assert_contains "$STUB_LOG/guard-curl.log" "refused live port 8095" "M2E the guard log proves the probe was refused, not answered"

finish
