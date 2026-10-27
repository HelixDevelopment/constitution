#!/usr/bin/env bash
# test_review_fixes_r3.sh — regression tests for the ROUND-3 independent review of the decision layer (NO-GO: I3-1, I3-2,
# I3-3 and minors m-r3-1..4 + the --globoff nit + reviewer mutations R1-R5). Written RED-first; every case drives the REAL
# code. curl is a recording stub, llmctl/require-validated a stub, every key a DUMMY assembled from fragments, no network.
#   I3-1  bootstrap stage 5 never writes enforce on "a thresholds file exists" (needs promoted type + local endpoint + validated)
#   I3-2  a stored enforce is re-derived on EVERY run and downgraded (env file, MCP env.JEV_MODE, jev-status --json)
#   I3-3  register never writes enforce for a hosted / non-loopback base URL, nor from a hosted-only record
#   m-r3-1 unkeyed probe refuses userinfo SSRF forms; the llmctl-* id is not trusted; docs line matches the code
#   m-r3-2 the require-validated / profile overrides are honoured only with JEV_TEST=1
#   m-r3-3 curl -q is the FIRST argument of every curl call;  nit: --globoff + encoded pinned-path forms refused
#   R1-R5 reviewer mutations, each applied to a copy and required to FAIL the scenario that guards it
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq curl python3; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
PROBE="$REPO/scripts/jev/jev-probe.sh"
KEY="$(printf '%s-%s-%s' dummyk3 Z9y8X7w6 V5u4T3s2R1q0)"

setup() {
  make_fixture_env "$1"
  REC="$T/rec"; mkdir -p "$REC" "$T/rbin"; export REC_DIR="$REC"
  cat > "$T/rbin/curl" <<'XEOF'
#!/usr/bin/env bash
out="${REC_DIR:?}"; printf '%s\n' "$*" >> "$out/curl.argv"
printf '%s\n' "$1" >> "$out/curl.first"
usecfg=0; prev=""; for a in "$@"; do [ "$prev" = "-K" ] && [ "$a" = "-" ] && usecfg=1; prev="$a"; done
[ "$usecfg" = 1 ] && cat >> "$out/curl.stdin"
printf '%s' "${REC_CODE:-200}"
XEOF
  chmod +x "$T/rbin/curl"; export PATH="$T/rbin:$PATH"
  PINS="$T/pins.json"
  jq -n '{hosted:{typesafe:{key_var:"TYPESAFE_API_KEY",base_url:"https://api.typesafe.test",systemone_path:"/v1/systemone",models:["jev-latest"],enabled:true}},
          local_gateway:{host:"127.0.0.1",port:8095,scheme:"https",key_var:"LLMCTL_API_KEY",enabled:true}}' > "$PINS"
  export CMA_JEV_PINS_FILE="$PINS"
  unset JEV_CA_FILE
}
mkrec() { # mkrec <file> <id> <url> [source]
  jq -n --arg id "$2" --arg u "$3" --arg s "${4:-api-keys-file}" \
    '{version:1,generated_at:1700000000,endpoints:[{id:$id,source:$s,reachable:true,probed_at:1700000000,parallel:1,url:$u,probe_path:"/v1/systemone",reachable_basis:"probe"}]}' > "$1"
}
promoted() { jq -n '{per_type:{gate:{promoted:true,threshold:0.9}}}' > "$1"; }
unpromoted() { jq -n '{per_type:{gate:{promoted:false,threshold:0.9}}}' > "$1"; }
# eff <req> <base> <det> <thr...> -> "MODE<TAB>REASON" from the REAL shared function
# (the r4 `;test-override(JEV_TEST=1)` note is stripped here: it is asserted in test_review_fixes_r4.sh)
eff() { ( set +u; source "${LIBDIR:-$REPO/scripts/jev}/lib_keys.sh" 2>/dev/null; source "${LIBDIR:-$REPO/scripts/jev}/lib_decide.sh"; jev_effective_mode "$@" ) | sed 's/;test-override(JEV_TEST=1)//'; }

# ---- jev_effective_mode table (I3-1 / I3-3 / m-r3-2 / R2 / R4) ---------------------------------------------------------
setup em; jev_test_enforce_env 0
seed_local_detection "$T/loc.json" decide; promoted "$T/thr.json"; unpromoted "$T/unp.json"
mkrec "$T/host.json" ep "https://api.typesafe.test" api-keys-file
: > "$STUB_LOG/rv.log"
assert_eq "enforce	promoted+validated" "$(eff enforce "https://127.0.0.1:8095" "$T/loc.json" "$T/thr.json")" "EM-POS loopback base + local endpoint + promoted + validated PASS => enforce"
assert_contains "$STUB_LOG/rv.log" "strict=1 args=decide" "EM-POS require-validated is called with LLMCTL_VALIDATE_STRICT=1 for the profile"
assert_eq "shadow	hosted-or-non-loopback-base-url(explicit)" "$(eff enforce "https://api.typesafe.ai" "$T/loc.json" "$T/thr.json")" "EM-I3-3 hosted base URL => shadow even with promoted thresholds"
for b in "https://127.0.0.1@evil.example/" "http://127.0.0.1:80@evil.example/" "https://localhost.evil.example" "https://[::1]@evil.example/"; do
  assert_eq "shadow" "$(eff enforce "$b" "$T/loc.json" "$T/thr.json" | cut -f1)" "EM-I3-3 userinfo/lookalike base '$b' => shadow"
done
assert_eq "shadow	no-promoted-threshold" "$(eff enforce "" "$T/loc.json" "$T/unp.json")" "EM-R2 an UNPROMOTED type with a numeric threshold => shadow"
assert_eq "shadow	no-promoted-threshold" "$(eff enforce "" "$T/loc.json" "$T/none.json")" "EM-I3-1 no thresholds file => shadow"
assert_eq "shadow	no-qualifying-local-llmctl-endpoint(hosted-or-non-llmctl-or-non-loopback-never-enforce)" "$(eff enforce "" "$T/host.json" "$T/thr.json")" "EM-I3-3 hosted-only record => shadow"
assert_eq "shadow	no-detection-record" "$(eff enforce "" "$T/absent.json" "$T/thr.json")" "EM no detection record => shadow"
assert_eq "shadow	not-requested" "$(eff shadow "" "$T/loc.json" "$T/thr.json")" "EM enforce is never inferred from a thresholds file alone"
jev_test_enforce_env 1
assert_eq "shadow	require-validated-not-passed:decide" "$(eff enforce "" "$T/loc.json" "$T/thr.json")" "EM-R4 a FAILING require-validated => shadow"
# overrides without JEV_TEST=1 are ignored (and loudly noted); the fixture llmctl stub fails require-validated
unset JEV_TEST
r="$(eff enforce "" "$T/loc.json" "$T/thr.json")"
assert_eq "shadow" "$(printf '%s' "$r" | cut -f1)" "EM-m-r3-2 overrides without JEV_TEST=1 never enable enforce"
case "$r" in *override-ignored*) assert_eq 1 1 "EM-m-r3-2 the ignore is noted in the reason" ;; *) assert_eq "override-ignored" "$r" "EM-m-r3-2 the ignore is noted in the reason" ;; esac

# ---- I3-1 / I3-2 bootstrap: --enforce with an unpromoted file, then a downgrade of a stored enforce -----------------------
setup bs; unset JEV_TEST
bs() { bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive "$@" >"$T/bs.out" 2>"$T/bs.err"; RC=$?; }
unpromoted "$JEV_CONFIG_DIR/jev-thresholds.json"
bs --enforce; assert_rc 0 "$RC" "BS-1 bootstrap --enforce rc 0"
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "BS-I3-1 --enforce + an unpromoted thresholds file stays shadow"
promoted "$JEV_CONFIG_DIR/jev-thresholds.json"
bs --enforce
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "BS-I3-1 --enforce + promoted thresholds but NO local endpoint/validator stays shadow"
# I3-2: a stored enforce (hand-set), thresholds removed, rerun => every stored artifact and status say shadow
rm -f "$JEV_CONFIG_DIR/jev-thresholds.json"
sed -i 's/^JEV_MODE=.*/JEV_MODE=enforce/' "$JEV_CONFIG_DIR/env"
bs
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "BS-I3-2 stored enforce + thresholds removed => the env file is rewritten to shadow"
JEV_STATE_DIR="$JEV_STATE_DIR" JEV_EVIDENCE_DIR="$JEV_EVIDENCE_DIR" JEV_CONFIG_DIR="$JEV_CONFIG_DIR" bash "$REPO/scripts/jev/jev-status.sh" --json > "$T/st.json" 2>/dev/null
assert_eq "shadow" "$(jq -r '.mode' "$T/st.json")" "BS-I3-2 jev-status --json says shadow"

# ---- I3-2 / I3-3 register: MCP env.JEV_MODE and a hosted base URL --------------------------------------------------------
setup rg; jev_test_enforce_env 0
seed_local_detection "$T/det_local.json" decide
B="$T/box"; mkdir -p "$B/.claude" "$T/cfg"; promoted "$T/cfg/jev-thresholds.json"
reg() { # reg <extra-env...> : JEV_MODE=enforce requested, local record
  env JEV_DETECTION_FILE="$T/det_local.json" JEV_CONFIG_DIR="$T/cfg" JEV_HOME="$B" JEV_MODE=enforce "$@" bash "$REPO/skills/jev-decision-layer/register.sh" >"$T/rg.out" 2>"$T/rg.err"; RC=$?; }
mode_of() { grep -s '^JEV_MODE=' "$1" | cut -d= -f2; }
mcp_mode() { jq -r '.mcpServers.jev.env.JEV_MODE // empty' "$B/.mcp.json" 2>/dev/null; }
reg; assert_eq "enforce" "$(mode_of "$T/cfg/env")" "RG-POS promoted + local record + validated => enforce"
assert_eq "enforce" "$(mcp_mode)" "RG-POS the MCP env.JEV_MODE agrees"
rm -f "$T/cfg/jev-thresholds.json"; reg
assert_eq "shadow" "$(mode_of "$T/cfg/env")" "RG-I3-2 thresholds removed + rerun => env file downgraded to shadow"
assert_eq "shadow" "$(mcp_mode)" "RG-I3-2 thresholds removed + rerun => MCP env.JEV_MODE downgraded to shadow"
promoted "$T/cfg/jev-thresholds.json"
reg JEV_BASE_URL="https://api.typesafe.ai" JEV_KEY_VAR=TYPESAFE_API_KEY
assert_eq "shadow" "$(mode_of "$T/cfg/env")" "RG-I3-3 hosted base URL + promoted thresholds => shadow"
assert_eq "shadow" "$(mcp_mode)" "RG-I3-3 hosted base URL => MCP env.JEV_MODE shadow"
reg JEV_BASE_URL="https://127.0.0.1@evil.example/"
assert_eq "shadow" "$(mode_of "$T/cfg/env")" "RG-I3-3 userinfo base URL => shadow"

# ---- m-r3-1 probe SSRF forms -----------------------------------------------------------------------------------------------
for u in "http://127.0.0.1:80@evil.example/" "http://[::1]@evil.example/" "http://localhost:1@evil.example/"; do
  setup pr; : > "$REC/curl.argv"
  mkrec "$T/d.json" ep "$u" local-llmctl
  JEV_DETECTION_FILE="$T/d.json" bash "$PROBE" ep "$u" >/dev/null 2>&1; rc=$?
  assert_rc 2 "$rc" "PR-m-r3-1 unkeyed probe of '$u' exits 2"
  assert_eq "0" "$(wc -l < "$REC/curl.argv" | tr -d ' ')" "PR-m-r3-1 curl was never started for '$u'"
done
setup pr2; mkrec "$T/d.json" llmctl-x "https://evil.example/" local-llmctl
JEV_DETECTION_FILE="$T/d.json" bash "$PROBE" llmctl-x "https://evil.example/" >/dev/null 2>&1; rc=$?
assert_rc 2 "$rc" "PR-m-r3-1 the llmctl-* id exemption is gone (id llmctl-x + public URL => exit 2)"
assert_eq "0" "$([ -f "$REC/curl.argv" ] && wc -l < "$REC/curl.argv" | tr -d ' ' || echo 0)" "PR-m-r3-1 no curl for the llmctl-x public URL"
setup pr3; mkrec "$T/d.json" ep "http://127.0.0.1:9" local-llmctl
JEV_DETECTION_FILE="$T/d.json" bash "$PROBE" ep "http://127.0.0.1:9" >/dev/null 2>&1; rc=$?
assert_rc 0 "$rc" "PR-POS a genuine loopback URL is probed unkeyed"
assert_eq "-q" "$(head -1 "$REC/curl.first")" "PR-m-r3-3 curl -q is the FIRST argument (probe)"
assert_contains "$REC/curl.argv" "--globoff" "PR-nit --globoff on the probe curl"
# pinned-origin path forms
setup pp
for p in "/v1/%25" "/v1/..;/x" "/v1/%u0041" "/v1/%7f" "/v1/{a}" "/v1/[a]"; do
  : > "$REC/curl.argv"
  mkrec "$T/d.json" ep "https://api.typesafe.test$p" api-keys-file
  JEV_DETECTION_FILE="$T/d.json" bash "$PROBE" ep "https://api.typesafe.test$p" >/dev/null 2>&1; rc=$?
  assert_rc 2 "$rc" "PP-nit encoded/odd path '$p' on a pinned origin is refused"
done

# ---- m-r3-3 keyed auth_probe and bootstrap probe_http: -q first, key on STDIN only (R1) -------------------------------------
setup ap
KF="$T/keys.sh"; printf "export TYPESAFE_API_KEY='%s'\n" "$KEY" > "$KF"; chmod 600 "$KF"
( set +u; export JEV_API_KEYS_FILE="$KF"; source "$REPO/scripts/jev/lib_keys.sh"; auth_probe TYPESAFE_API_KEY "https://api.typesafe.test/v1/systemone" jev-latest >/dev/null 2>&1 ) || true
if [ -s "$REC/curl.first" ]; then
  assert_eq "-q" "$(head -1 "$REC/curl.first")" "AP-m-r3-3 curl -q is the FIRST argument (auth_probe)"
  assert_contains "$REC/curl.argv" "--globoff" "AP-nit --globoff on auth_probe"
  assert_not_contains "$REC/curl.argv" "$KEY" "AP-R1 the key is never on curl's argv"
  assert_contains "$REC/curl.stdin" "$KEY" "AP-R1 the key travels on STDIN (-K -)"
else
  assert_eq "called" "not-called" "AP auth_probe reached curl"
fi
for f in jev-probe.sh lib_keys.sh bootstrap.sh; do
  n="$(grep -cE '(args|a)=\(-q ' "$REPO/scripts/jev/$f")"
  [ "$n" -ge 1 ] && assert_eq 1 1 "Q-m-r3-3 $f builds its curl args with -q first" || assert_eq ">=1" "$n" "Q-m-r3-3 $f builds its curl args with -q first"
done

# ---- reviewer mutations R1-R5: each must make its guarding scenario FAIL on the mutant ---------------------------------
mkmut() { # mkmut <name> -> $T/mut/<name> holds scripts/jev (a mutable copy)
  mkdir -p "$T/mut/$1/scripts"; cp -R "$REPO/scripts/jev" "$T/mut/$1/scripts/jev"
}
mutate() { python3 - "$@" <<'PYEOF'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    print("MUTATION-ANCHOR-MISSING"); sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
}
# R2: remove `promoted == true` from the predicate => an unpromoted type enforces
setup mu; jev_test_enforce_env 0; seed_local_detection "$T/loc.json" decide; unpromoted "$T/unp.json"
mkmut r2; mutate "$T/mut/r2/scripts/jev/lib_decide.sh" 'select(.promoted == true and ' 'select(' >"$T/m.out"; mrc=$?
assert_rc 0 "$mrc" "R2 mutation anchor found"
assert_eq "enforce" "$(LIBDIR="$T/mut/r2/scripts/jev" eff enforce "" "$T/loc.json" "$T/unp.json" | cut -f1)" "R2 MUTANT (no promoted==true) wrongly enforces an unpromoted type  [the real code says shadow, see EM-R2]"
# R4: ignore a failed require-validated
mkmut r4; mutate "$T/mut/r4/scripts/jev/lib_decide.sh" 'LLMCTL_VALIDATE_STRICT=1 timeout 60 $rv "$p" >/dev/null 2>&1 \' 'LLMCTL_VALIDATE_STRICT=1 timeout 60 $rv "$p" >/dev/null 2>&1 || true; true \' >"$T/m.out"; mrc=$?
assert_rc 0 "$mrc" "R4 mutation anchor found"
jev_test_enforce_env 1; promoted "$T/thr.json"
assert_eq "enforce" "$(LIBDIR="$T/mut/r4/scripts/jev" eff enforce "" "$T/loc.json" "$T/thr.json" | cut -f1)" "R4 MUTANT (failed require-validated ignored) wrongly enforces  [the real code says shadow, see EM-R4]"
# R5: drop the hosted-only deferral (no local-llmctl endpoint needed) => hosted-only record enforces
mkmut r5; mutate "$T/mut/r5/scripts/jev/lib_decide.sh" '[ -n "$profs" ] ||' 'true ||' >"$T/m.out"; mrc=$?
assert_rc 0 "$mrc" "R5 mutation anchor found"
jev_test_enforce_env 0; mkrec "$T/host.json" ep "https://api.typesafe.test" api-keys-file
assert_eq "enforce" "$(LIBDIR="$T/mut/r5/scripts/jev" eff enforce "" "$T/host.json" "$T/thr.json" | cut -f1)" "R5 MUTANT (hosted-only deferral removed) wrongly enforces  [the real code says shadow, see EM-I3-3]"
# R1: key via -H on argv instead of stdin => the argv-leak assertion catches it
setup mu1; printf "export TYPESAFE_API_KEY='%s'\n" "$KEY" > "$T/keys.sh"; chmod 600 "$T/keys.sh"
mkmut r1
mutate "$T/mut/r1/scripts/jev/lib_keys.sh" "c=\"\$(printf 'header = \"Authorization: Bearer %s\"\\n' \"\$ek\" | curl \"\${args[@]}\" \"\$u\" 2>/dev/null)\"" "c=\"\$(curl -H \"Authorization: Bearer \$ek\" \"\${args[@]}\" \"\$u\" 2>/dev/null)\"" >"$T/m.out"; mrc=$?
assert_rc 0 "$mrc" "R1 mutation anchor found"
( set +u; export JEV_API_KEYS_FILE="$T/keys.sh"; source "$T/mut/r1/scripts/jev/lib_keys.sh"; auth_probe TYPESAFE_API_KEY "https://api.typesafe.test/v1/systemone" jev-latest >/dev/null 2>&1 </dev/null ) || true
if grep -qF -- "$KEY" "$REC/curl.argv" 2>/dev/null; then assert_eq 1 1 "R1 MUTANT (key via -H on argv) is caught: the key shows on curl's argv"
else assert_eq "key-on-argv" "key-not-on-argv" "R1 MUTANT is caught by the argv-leak assertion"; fi
# R3: a keyed probe falling back to the record's ca_file => --cacert from the record
setup mu3; export TYPESAFE_API_KEY="$KEY"; : > "$T/evil-ca.pem"
mkmut r3; cp "$REPO/scripts/jev/jev-probe.sh" "$T/mut/r3/scripts/jev/jev-probe.sh"
if grep -q 'rec_ca' "$T/mut/r3/scripts/jev/jev-probe.sh"; then
  mutate "$T/mut/r3/scripts/jev/jev-probe.sh" '"$md" "$ca")"' '"$md" "${ca:-$rec_ca}")"' >"$T/m.out"; mrc=$?
  assert_rc 0 "$mrc" "R3 mutation anchor found"
  jq -n --arg ca "$T/evil-ca.pem" '{version:1,generated_at:1700000000,endpoints:[{id:"ep",source:"api-keys-file",reachable:true,url:"https://api.typesafe.test",key_var:"TYPESAFE_API_KEY",ca_file:$ca,probe_path:"/v1/systemone"}]}' > "$T/d.json"
  : > "$REC/curl.argv"
  JEV_DETECTION_FILE="$T/d.json" bash "$T/mut/r3/scripts/jev/jev-probe.sh" ep "https://api.typesafe.test" >/dev/null 2>&1
  if grep -qF -- "--cacert $T/evil-ca.pem" "$REC/curl.argv"; then assert_eq 1 1 "R3 MUTANT (record ca_file on a keyed probe) is caught: --cacert reaches curl"
  else assert_eq "cacert-from-record" "no-cacert" "R3 MUTANT is caught"; fi
else
  assert_eq "rec_ca-present" "rec_ca-missing" "R3 anchor variable present in jev-probe.sh"
fi
finish
