#!/usr/bin/env bash
# test_review_fixes_r4.sh — regression tests for the ROUND-4 independent review of the decision layer (NO-GO: I4-1, I4-2,
# I4-3, m4-1..m4-8, nit) plus reviewer mutants m1-m8. Every case drives the REAL code; llmctl / validator are stubs, every
# URL is a loopback or a reserved test name, no network, no key.
#   I4-1 ONE base-URL resolver (jev_base_verdict) used by bootstrap stage 5, register.sh and jev-status.sh: all three agree
#   I4-2 JEV_TEST guard on the validator override (m8) ; m4-1 an honoured test override is recorded in reason + status
#   I4-3 register no longer needs its own stored-base downgrade (m2): the shared resolver reads the env file / MCP entry
#   m4-2 profile names starting with '-' refused, `--` passed ; m4-3 non-llmctl- ids never local ; m4-4/5/6 threshold range,
#   record freshness, port range ; m4-8 jev-status --no-validate
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq python3; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
ST="$REPO/scripts/jev/jev-status.sh"; REG="$REPO/skills/jev-decision-layer/register.sh"

promoted() { jq -n '{per_type:{gate:{promoted:true,threshold:'"${2:-0.9}"'}}}' > "$1"; }
eff() { ( set +u; source "${LIBDIR:-$REPO/scripts/jev}/lib_keys.sh" 2>/dev/null; source "${LIBDIR:-$REPO/scripts/jev}/lib_decide.sh"; jev_effective_mode "$@" ); }
strip() { sed 's/;test-override(JEV_TEST=1)//'; }
mkdet() { # mkdet <file> <id> <url> [generated_at]
  jq -n --arg id "$2" --arg u "$3" --argjson g "${4:-1700000000}" '{version:1,generated_at:$g,endpoints:[{id:$id,source:"local-llmctl",reachable:true,url:$u}],reason:null}' > "$1"; }
# fixture: a box with a detection record, promoted thresholds, a stub validator that passes
fx() { make_fixture_env "$1"; jev_test_enforce_env 0; unset JEV_BASE_URL
  mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9"; promoted "$JEV_CONFIG_DIR/jev-thresholds.json"
  export JEV_DETECTION_FILE="$T/det.json"; cp "$T/det.json" "$JEV_EVIDENCE_DIR/jev-detection.json"
  B="$T/box"; mkdir -p "$B/.claude"; printf '{"mcpServers":{}}\n' > "$B/.mcp.json"; export JEV_HOME="$B"; }
env_base() { printf 'JEV_MODE=enforce\nJEV_BASE_URL=%s\n' "$1" > "$JEV_CONFIG_DIR/env"; }
cache_base() { jq -n --arg u "$1" '{endpoints:[{base_url:$u}]}' > "$CMA_PROVIDERS_DIR/jev-endpoints.json"; }
mcp_base() { jq -n --arg u "$1" '{mcpServers:{jev:{env:{JEV_BASE_URL:$u}}}}' > "$B/.mcp.json"; }
status_mode() { bash "$ST" --json 2>/dev/null | jq -r '.mode'; }
status_reason() { bash "$ST" --json 2>/dev/null | jq -r '.mode_reason' | strip; }
reg_mode() { env JEV_MODE=enforce bash "$REG" >"$T/rg.out" 2>"$T/rg.err"; grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | tail -1 | cut -d= -f2; }
LOOP=https://127.0.0.1:8095

# ---- I4-1: all three callers agree on the same fixture -----------------------------------------------------------------
agree() { # agree <label> <expected-mode> <expected-reason-prefix>
  local want="$2" sm rm_ f="$T/ag.$$"
  sm="$(status_mode)"; local why; why="$(status_reason)"
  rm_="$(reg_mode)"
  assert_eq "$want" "$sm" "I4-1 $1: jev-status says $want"
  assert_eq "$want" "$rm_" "I4-1 $1: register.sh writes $want"
  assert_contains_str "$why" "$3" "I4-1 $1: reason names $3"
}
assert_contains_str() { case "$1" in *"$2"*) assert_eq 1 1 "$3";; *) assert_eq "contains:$2" "$1" "$3";; esac; }
fx a1; env_base "$LOOP";                    agree "loopback env-file base" enforce "promoted+validated"
fx a2; unset JEV_BASE_URL; printf 'JEV_MODE=enforce\n' > "$JEV_CONFIG_DIR/env"; agree "empty base" shadow "base-url-unresolved"
fx a3; env_base "$LOOP"; cache_base "https://api.typesafe.test"; agree "hosted cache endpoints[0]" shadow "hosted-or-non-loopback-base-url(cache)"
fx a4; env_base "https://api.typesafe.test"; agree "hosted env-file base" shadow "hosted-or-non-loopback-base-url(env-file)"
fx a5; env_base "$LOOP"; mcp_base "https://api.typesafe.test"; agree "hosted MCP-entry base" shadow "hosted-or-non-loopback-base-url(mcp-entry)"
# bootstrap stage 5 agrees too (same resolver, same fixture): hosted env-file base => shadow, enforce-deferred names the reason
fx a6; env_base "https://api.typesafe.test"; promoted "$JEV_CONFIG_DIR/jev-thresholds.json"
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --enforce >"$T/bs.out" 2>"$T/bs.err" </dev/null
assert_eq "shadow" "$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)" "I4-1 bootstrap stage 5 with a hosted env-file base stays shadow"

# ---- I4-1: the detection record's local endpoint URL is loopback-checked; non-llmctl ids never local (m4-3) --------------
fx b1; mkdet "$T/det.json" llmctl-decide "https://evil.example"
assert_eq "shadow" "$(eff enforce "$LOOP" "$T/det.json" | cut -f1)" "I4-1 detection url https://evil.example => shadow"
mkdet "$T/det.json" decide "http://127.0.0.1:9"
assert_eq "shadow" "$(eff enforce "$LOOP" "$T/det.json" | cut -f1)" "m4-3 a local endpoint whose id lacks the llmctl- prefix is not local => shadow"
mkdet "$T/det.json" "llmctl--force" "http://127.0.0.1:9"
assert_eq "shadow" "$(eff enforce "$LOOP" "$T/det.json" | cut -f1)" "m4-2 profile name starting with '-' (llmctl--force) refused => shadow"
assert_eq "no-rv-call" "$([ -s "$STUB_LOG/rv.log" ] && echo called || echo no-rv-call)" "m4-2 the validator was never called for a dash-leading name"

# ---- I4-2: JEV_TEST guard on the validator override (reviewer mutant m8) -----------------------------------------------
fx c1; env_base "$LOOP"; unset JEV_TEST
mkdir -p "$T/fakebin"; printf '#!/usr/bin/env bash\nexit 1\n' > "$T/fakebin/llmctl"; chmod +x "$T/fakebin/llmctl"
r="$(PATH="$T/fakebin:$PATH" JEV_REQUIRE_VALIDATED_CMD="$T/rv_stub" JEV_DECISION_PROFILES=decide eff enforce "$LOOP" "$T/det.json")"
mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9"
r="$(PATH="$T/fakebin:$PATH" JEV_REQUIRE_VALIDATED_CMD="$T/rv_stub" JEV_DECISION_PROFILES=decide eff enforce "$LOOP" "$T/det.json")"
assert_eq "shadow" "$(printf '%s' "$r" | cut -f1)" "I4-2 JEV_TEST unset + passing override + failing real llmctl => shadow"
assert_contains_str "$r" "override-ignored" "I4-2 the reason says override-ignored"
# m4-1: an honoured test override is recorded in the reason and in the status output
fx c2; env_base "$LOOP"
assert_contains_str "$(eff enforce "$LOOP" "$T/det.json")" "test-override(JEV_TEST=1)" "m4-1 honoured override recorded in the reason"
assert_eq "true" "$(bash "$ST" --json 2>/dev/null | jq -r '.test_override')" "m4-1 jev-status --json test_override true"
bash "$ST" >"$T/h.out" 2>/dev/null; assert_contains "$T/h.out" "WARNING" "m4-1 human status carries a WARNING for test overrides"

# ---- I4-3: stored hosted base in env file / MCP entry vs a loopback register call (reviewer mutant m2) -------------------
fx d1; env_base "https://api.typesafe.test"
assert_eq "shadow" "$(env JEV_BASE_URL="$LOOP" JEV_MODE=enforce bash "$REG" >/dev/null 2>&1; grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | tail -1 | cut -d= -f2)" "I4-3 hosted base stored in the env file + loopback register call => shadow"
fx d2; : > "$JEV_CONFIG_DIR/env"; mcp_base "https://api.typesafe.test"
env JEV_BASE_URL="$LOOP" JEV_MODE=enforce bash "$REG" >/dev/null 2>&1
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE // empty' "$B/.mcp.json")" "I4-3 hosted base stored in the MCP entry + loopback register call => MCP JEV_MODE shadow"

# ---- m4-2: `--` and the name check reach the validator ---------------------------------------------------------------------
fx e1; : > "$STUB_LOG/rv.log"; eff enforce "$LOOP" "$T/det.json" >/dev/null
assert_contains "$STUB_LOG/rv.log" "args=decide" "m4-2 the validator receives exactly the profile (r5 I5-1: the pinned CLI rejects a leading --)"

# ---- m4-4 threshold range ; m4-5 freshness ; m4-6 port --------------------------------------------------------------------
fx f1; rm -f "$JEV_CONFIG_DIR/jev-thresholds.json"
for t in -5 0 1e9 2; do promoted "$T/thr.json" "$t"; assert_eq "shadow" "$(eff enforce "$LOOP" "$T/det.json" "$T/thr.json" | cut -f1)" "m4-4 threshold $t out of (0,1] => shadow"; done
for t in 1.0 0.5; do promoted "$T/thr.json" "$t"; assert_eq "enforce" "$(eff enforce "$LOOP" "$T/det.json" "$T/thr.json" | cut -f1)" "m4-4 threshold $t accepted"; done
promoted "$T/thr.json"
mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9" 1000
assert_contains_str "$(eff enforce "$LOOP" "$T/det.json" "$T/thr.json")" "detection-record-stale-or-undated" "m4-5 stale record => shadow"
jq 'del(.generated_at)' "$T/det.json" > "$T/d2.json"
assert_contains_str "$(eff enforce "$LOOP" "$T/d2.json" "$T/thr.json")" "detection-record-stale-or-undated" "m4-5 undated record => shadow"
mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9" 1800000000
assert_contains_str "$(eff enforce "$LOOP" "$T/det.json" "$T/thr.json")" "detection-record-stale-or-undated" "m4-5 record from the future => shadow"
mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9" 1700000000
assert_eq "shadow" "$(JEV_DETECTION_MAX_AGE=0 JEV_NOW_EPOCH=1700000100 eff enforce "$LOOP" "$T/det.json" "$T/thr.json" | cut -f1)" "m4-5 JEV_DETECTION_MAX_AGE=0 makes a 100 s old record stale"
for u in "https://127.0.0.1:99999" "https://127.0.0.1:0" "https://127.0.0.1:65536"; do
  assert_eq "invalid" "$( ( source "$REPO/scripts/jev/lib_keys.sh"; jev_url_host_class "$u" ) )" "m4-6 port out of range '$u' => invalid"
done
assert_eq "loopback" "$( ( source "$REPO/scripts/jev/lib_keys.sh"; jev_url_host_class "https://[::1]:65535" ) )" "m4-6 [::1]:65535 still loopback"

# ---- m4-8: jev-status --no-validate / JEV_STATUS_NO_VALIDATE ---------------------------------------------------------------
fx g1; env_base "$LOOP"; : > "$STUB_LOG/rv.log"
j="$(bash "$ST" --json --no-validate 2>/dev/null)"
assert_eq "unknown" "$(printf '%s' "$j" | jq -r '.mode')" "m4-8 --no-validate => mode unknown"
assert_contains_str "$(printf '%s' "$j" | jq -r '.mode_reason')" "validation-skipped" "m4-8 reason validation-skipped"
assert_eq "no-rv-call" "$([ -s "$STUB_LOG/rv.log" ] && echo called || echo no-rv-call)" "m4-8 the validator was not called"
assert_eq "unknown" "$(JEV_STATUS_NO_VALIDATE=1 bash "$ST" --json 2>/dev/null | jq -r '.mode')" "m4-8 JEV_STATUS_NO_VALIDATE=1 behaves the same"

# ---- positive end-to-end: bootstrap stage 5 reaches enforce with a fully valid fixture ------------------------------------
fx p1; env_base "$LOOP"; promoted "$JEV_CONFIG_DIR/jev-thresholds.json"; rm -f "$JEV_EVIDENCE_DIR/jev-detection.json"
unset JEV_DETECTION_FILE
bash "$REPO/scripts/jev/bootstrap.sh" --non-interactive --enforce >"$T/bs.out" 2>"$T/bs.err" </dev/null
E2E_ENV="$(grep -s '^JEV_MODE=' "$JEV_CONFIG_DIR/env" | cut -d= -f2)"
if [ "$E2E_ENV" = "enforce" ]; then
  assert_eq "enforce" "$E2E_ENV" "E2E bootstrap stage 5 wrote JEV_MODE=enforce"
  assert_eq "enforce" "$(status_mode)" "E2E jev-status --json says enforce"
  assert_eq "absent" "$(ls "$JEV_STATE_DIR"/*enforce-deferred* 2>/dev/null | head -1 | sed 's/.*/present/;s/^$/absent/' | grep . || echo absent)" "E2E no enforce-deferred file"
else
  assert_eq "enforce" "$E2E_ENV" "E2E bootstrap stage 5 wrote JEV_MODE=enforce (see $T/bs.out)"
fi

# ---- reviewer mutants m1-m8 + own, each applied to a copy and required to change the verdict -------------------------------
mkmut() { mkdir -p "$T/mut/$1/scripts"; cp -R "$REPO/scripts/jev" "$T/mut/$1/scripts/jev"; }
mutate() { python3 - "$@" <<'PYEOF'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    print("MUTATION-ANCHOR-MISSING"); sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
}
fx m0; env_base "$LOOP"; promoted "$T/thr.json"; mkdet "$T/det.json" llmctl-decide "http://127.0.0.1:9"
L=lib_decide.sh
# m1: loopback check on the detection url removed
mkmut m1; mutate "$T/mut/m1/scripts/jev/$L" '[ "$(jev_url_host_class "$url")" = "loopback" ] || continue' 'true' >/dev/null; assert_rc 0 "$?" "m1 anchor"
mkdet "$T/evil.json" llmctl-decide "https://evil.example"
assert_eq "enforce" "$(LIBDIR="$T/mut/m1/scripts/jev" eff enforce "$LOOP" "$T/evil.json" "$T/thr.json" | cut -f1)" "m1 MUTANT (no detection-url loopback check) enforces evil.example  [real code: shadow]"
# m4: promoted == true dropped
mkmut m4; mutate "$T/mut/m4/scripts/jev/$L" 'select(.promoted == true and ' 'select(' >/dev/null; assert_rc 0 "$?" "m4 anchor"
jq -n '{per_type:{gate:{promoted:false,threshold:0.9}}}' > "$T/unp.json"
assert_eq "enforce" "$(LIBDIR="$T/mut/m4/scripts/jev" eff enforce "$LOOP" "$T/det.json" "$T/unp.json" | cut -f1)" "m4 MUTANT enforces an unpromoted type  [real code: shadow]"
# m5: STRICT dropped
mkmut m5; mutate "$T/mut/m5/scripts/jev/$L" 'LLMCTL_VALIDATE_STRICT=1 timeout' 'timeout' >/dev/null; assert_rc 0 "$?" "m5 anchor"
: > "$STUB_LOG/rv.log"; LIBDIR="$T/mut/m5/scripts/jev" eff enforce "$LOOP" "$T/det.json" "$T/thr.json" >/dev/null
assert_contains "$STUB_LOG/rv.log" "strict= " "m5 MUTANT calls the validator without STRICT  [real code logs strict=1]"
# m7: profile-name check removed (loop-level)
mkmut m7; mutate "$T/mut/m7/scripts/jev/$L" 'p="${id#llmctl-}"; jev_profile_name_ok "$p" || continue' 'p="${id#llmctl-}"' >/dev/null; assert_rc 0 "$?" "m7 anchor"
mutate "$T/mut/m7/scripts/jev/$L" 'jev_profile_name_ok "$p" || { printf' 'true || { printf' >/dev/null; assert_rc 0 "$?" "m7 anchor 2"
mkdet "$T/dash.json" "llmctl--force" "http://127.0.0.1:9"
printf '#!/bin/sh\nexit 0\n' > "$T/rv_permissive"; chmod +x "$T/rv_permissive"   # accepts ANY argv, so the mutant is judged by the name check alone (the stub imitating the real CLI would reject a dash-leading arg itself)
assert_eq "enforce" "$(LIBDIR="$T/mut/m7/scripts/jev" JEV_REQUIRE_VALIDATED_CMD="$T/rv_permissive" JEV_DECISION_PROFILES= eff enforce "$LOOP" "$T/dash.json" "$T/thr.json" | cut -f1)" "m7 MUTANT lets a dash-leading profile name through  [real code: shadow]"
# m8: JEV_TEST guard on the validator override removed
mkdet "$T/fresh.json" llmctl-decide "http://127.0.0.1:9" "$(date +%s)"   # the clock seam is JEV_TEST-only (r5 m5-3): with JEV_TEST unset the record must be genuinely fresh
mkmut m8; mutate "$T/mut/m8/scripts/jev/$L" '[ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_REQUIRE_VALIDATED_CMD:-}" ] && rv=' '[ -n "${JEV_REQUIRE_VALIDATED_CMD:-}" ] && rv=' >/dev/null; assert_rc 0 "$?" "m8 anchor"
r8="$(PATH="$T/fakebin:$PATH" JEV_TEST= JEV_REQUIRE_VALIDATED_CMD="$T/rv_stub" JEV_DECISION_PROFILES= LIBDIR="$T/mut/m8/scripts/jev" eff enforce "$LOOP" "$T/fresh.json" "$T/thr.json" | cut -f1)"
assert_eq "enforce" "$r8" "m8 MUTANT honours the validator override without JEV_TEST=1  [real code: shadow]"
# own: base-unresolved check dropped
fx m1b; printf 'JEV_MODE=enforce\n' > "$JEV_CONFIG_DIR/env"; unset JEV_BASE_URL; promoted "$T/thr.json"
mkmut o1; mutate "$T/mut/o1/scripts/jev/$L" "[ \"\$n\" -gt 0 ] || { printf 'base-url-unresolved'; return 0; }" ':' >/dev/null; assert_rc 0 "$?" "o1 anchor"
assert_eq "enforce" "$(LIBDIR="$T/mut/o1/scripts/jev" eff enforce "" "$T/det.json" "$T/thr.json" | cut -f1)" "o1 MUTANT (empty base allowed) enforces with no base  [real code: shadow]"
# own: freshness dropped
mkmut o2; mutate "$T/mut/o2/scripts/jev/$L" '&& [ "$gen" -le $((now + 3600)) ] && [ $((now - gen)) -le "$max" ]; }' '; }' >/dev/null; assert_rc 0 "$?" "o2 anchor"
mkdet "$T/old.json" llmctl-decide "http://127.0.0.1:9" 1000
assert_eq "enforce" "$(LIBDIR="$T/mut/o2/scripts/jev" eff enforce "$LOOP" "$T/old.json" "$T/thr.json" | cut -f1)" "o2 MUTANT (freshness dropped) enforces a stale record  [real code: shadow]"
# own: threshold range dropped
mkmut o3; mutate "$T/mut/o3/scripts/jev/$L" '.threshold > 0 and .threshold <= 1' 'true' >/dev/null; assert_rc 0 "$?" "o3 anchor"
promoted "$T/bigthr.json" 1e9
assert_eq "enforce" "$(LIBDIR="$T/mut/o3/scripts/jev" eff enforce "$LOOP" "$T/det.json" "$T/bigthr.json" | cut -f1)" "o3 MUTANT (threshold range dropped) enforces threshold 1e9  [real code: shadow]"
# own: a `--` separator re-introduced (round 5: the pinned CLI rejects it, so real validation would never pass)
mkmut o4; mutate "$T/mut/o4/scripts/jev/$L" '$rv "$p"' '$rv -- "$p"' >/dev/null; assert_rc 0 "$?" "o4 anchor"
: > "$STUB_LOG/rv.log"; LIBDIR="$T/mut/o4/scripts/jev" eff enforce "$LOOP" "$T/det.json" "$T/thr.json" >/dev/null
assert_contains "$STUB_LOG/rv.log" "args=--" "o4 MUTANT re-adds the -- separator  [real code logs args=decide]"
# m6b: lib_keys --proto-redir '=https' dropped
if grep -q "proto-redir" "$REPO/scripts/jev/lib_keys.sh"; then
  mkmut m6b; python3 - "$T/mut/m6b/scripts/jev/lib_keys.sh" <<'PYEOF'
import sys,re
p=sys.argv[1]; s=open(p).read()
n=re.sub(r"--proto-redir\s+'=https'\s*","",s,count=1)
if n==s: print("MUTATION-ANCHOR-MISSING"); sys.exit(3)
open(p,"w").write(n)
PYEOF
  assert_rc 0 "$?" "m6b anchor"
  assert_eq "1" "$(grep -c 'proto-redir' "$REPO/scripts/jev/lib_keys.sh" | awk '{print ($1>=1)?1:0}')" "m6b the real lib_keys keeps --proto-redir (covered by the r3 argv assertions)"
fi
finish
