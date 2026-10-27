#!/usr/bin/env bash
# Round-7 review polish fixes. Each block names the finding it pins; every case drives the REAL code (fixtures are loopback / reserved names,
# key values are obviously fake).
#   m7-1 key-material detection covers key-name values AND args after a key-flag AND URL query keys (no plaintext backup)
#   m7-2 the @unresolvable-expansion@ marker has a killing test      m7-3 TOKEN/SECRET/PASSWORD/AUTH key names are covered
#   m7-4 a relative JEV_HOME is refused (never cwd-dependent)         m7-5 the hook's pending marker is where status reads it
#   m7-6 the MCP JEV_MODE rewrite survives a concurrent writer        n7-2 calibrate: header, atomic thresholds, capped copies
#   n7-3 register rewrites JEV_MODE in every covered file             n7-4 governance guide list item
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
for dep in jq python3; do command -v "$dep" >/dev/null 2>&1 || { assert_skip "$dep absent"; finish; exit $?; }; done
LIB="$REPO/scripts/jev/lib_decide.sh"; ST="$REPO/scripts/jev/jev-status.sh"; REG="$REPO/skills/jev-decision-layer/register.sh"; CAL="$REPO/scripts/jev/jev-calibrate.sh"
km() { ( set +u; source "$LIB"; jev_file_has_key_material "$1" ); }   # rc 0 = holds key material

make_fixture_env k
# ---- m7-1 / m7-3: what counts as key material --------------------------------------------------------------------------------
F="$T/km"; mkdir -p "$F"
jq -n '{mcpServers:{a:{command:"x",args:["--api-key","FAKEVALUE1234"]}}}' > "$F/args.json"
jq -n '{mcpServers:{a:{command:"x",args:["--api-key=FAKEVALUE1234"]}}}' > "$F/argseq.json"
jq -n '{mcpServers:{a:{url:"https://mcp.example.test/sse?key=FAKEVALUE1234"}}}' > "$F/query.json"
jq -n '{mcpServers:{a:{url:"https://mcp.example.test/sse?x=1&access_token=FAKEVALUE1234"}}}' > "$F/query2.json"
jq -n '{mcpServers:{a:{headers:{Authorization:"Bearer FAKEVALUE1234"}}}}' > "$F/auth.json"
jq -n '{mcpServers:{a:{env:{SERVICE_TOKEN:"FAKEVALUE1234"}}}}' > "$F/token.json"
jq -n '{mcpServers:{a:{env:{CLIENT_SECRET:"FAKEVALUE1234"}}}}' > "$F/secret.json"
jq -n '{mcpServers:{a:{env:{DB_PASSWORD:"FAKEVALUE1234"}}}}' > "$F/password.json"
jq -n '{mcpServers:{a:{env:{X_API_KEY:"FAKEVALUE1234"}}}}' > "$F/apikey.json"
jq -n '{mcpServers:{a:{command:"npx",args:["-y","pkg","--verbose","--port","8080"],url:"https://mcp.example.test/sse?mode=fast&limit=5"}}}' > "$F/clean.json"
printf 'x --api-key FAKEVALUE1234\nurl=https://h.test/p?token=FAKEVALUE1234\n' > "$F/notjson.txt"
for n in args argseq query query2 auth token secret password apikey; do
  km "$F/$n.json"; assert_rc 0 "$?" "m7-1/m7-3 $n.json counts as key material"
done
km "$F/notjson.txt"; assert_rc 0 "$?" "m7-1 unparseable file with a key flag / query key counts as key material"
km "$F/clean.json"; assert_rc 1 "$?" "m7-1 control: a file with args/query but no key-shaped name is NOT key material"
km "$F/missing.json"; assert_rc 0 "$?" "m7-1 control: an unreadable file is judged key-bearing (conservative)"
# end-to-end: no plaintext backup is made of the args / query shapes
for n in args query auth token; do
  cp "$F/$n.json" "$F/bk_$n.json"
  ( set +u; source "$LIB"; jev_backup_once "$F/bk_$n.json" 1700000000 ) >/dev/null 2>&1
  assert_eq "0" "$(ls "$F"/bk_"$n".json.prejev.* 2>/dev/null | wc -l)" "m7-1 no .prejev backup of the $n.json shape"
done
cp "$F/clean.json" "$F/bk_clean.json"; ( set +u; source "$LIB"; jev_backup_once "$F/bk_clean.json" 1700000000 ) >/dev/null 2>&1
assert_eq "1" "$(ls "$F"/bk_clean.json.prejev.* 2>/dev/null | wc -l)" "m7-1 control: a key-free file still gets its ONE backup"
assert_not_contains "$REPO/docs/jev/governance-guide.md" 'and `/.mcp.json`' "n7-4 the garbled list item is gone"
assert_contains "$REPO/docs/jev/governance-guide.md" 'both `$CLAUDE_CONFIG_DIR/.claude.json` and `$CLAUDE_CONFIG_DIR/.mcp.json`' "n7-4 ... and spelled out"
assert_contains "$REPO/docs/jev/governance-guide.md" "by key name, by an argument that follows a key flag, and by a credential-shaped URL query" "m7-1 the guide states how detection works (no overclaim)"

# ---- m7-2: an expansion in the PATH of an env-file base URL is not loopback-ok ----------------------------------------------
make_fixture_env x; unset JEV_BASE_URL
printf 'JEV_BASE_URL=https://127.0.0.1:8095/$(id)\n' > "$JEV_CONFIG_DIR/env"
V="$( set +u; source "$LIB"; jev_base_verdict )"
assert_ne "ok" "$V" "m7-2 \$(...) in the path of the env-file base URL is not 'ok'"
printf "%s" "$V" > "$T/v.out"; assert_contains "$T/v.out" "hosted-or-non-loopback-base-url(env-file)" "m7-2 ... it is rejected as the env-file base (the marker, not the host classifier)"
printf 'JEV_BASE_URL=https://127.0.0.1:8095/plain\n' > "$JEV_CONFIG_DIR/env"
assert_eq "ok" "$( set +u; source "$LIB"; jev_base_verdict )" "m7-2 control: a plain loopback path is ok"

# ---- m7-4: relative JEV_HOME is refused ---------------------------------------------------------------------------------------
make_fixture_env h; mkdir -p "$T/a" "$T/b"
( cd "$T/a" && JEV_HOME=rel bash -c 'set +u; source "$1"; jev_home' _ "$LIB" ) >"$T/h1.out" 2>"$T/h1.err"; rc=$?
assert_nonzero "$rc" "m7-4 sourcing the resolver with a relative JEV_HOME is refused"
assert_contains "$T/h1.err" "JEV_HOME must be an absolute path" "m7-4 ... with a stated reason"
( cd "$T/b" && JEV_HOME=rel bash "$ST" --json ) >"$T/h2.out" 2>"$T/h2.err"; rc=$?
assert_nonzero "$rc" "m7-4 jev-status with a relative JEV_HOME is refused from another cwd too"
( cd "$T/a" && JEV_HOME="$T/abs" bash -c 'set +u; source "$1"; jev_home' _ "$LIB" ) >"$T/h3.out" 2>/dev/null; rc=$?
assert_eq "0" "$rc" "m7-4 control: an absolute JEV_HOME is accepted"
assert_eq "$T/abs" "$(cat "$T/h3.out")" "m7-4 ... and is returned unchanged"
assert_not_contains "$LIB" "a default can never depend on the caller's working directory (r6" "m7-4 the resolver comment no longer overclaims"

# ---- m7-5: the hook's pending marker is the one status reads --------------------------------------------------------------------
while [ "${PATH#"$FIXTURES/bin:"}" != "$PATH" ]; do PATH="${PATH#"$FIXTURES/bin:"}"; done; make_hook_host scripts/jev/bootstrap.sh; rm -f "$HOST_C/scripts/jev/bootstrap.sh"; cp "$LIB" "$HOST_C/scripts/jev/lib_decide.sh"
run_hook_host
assert_rc 0 "$HOOK_RC" "m7-5 missing bootstrap: hook rc 0"
assert_file_exists "$HOST_P/.jev-state/bootstrap.pending" "m7-5 the pending marker is written under the resolved state dir"
assert_file_absent "$HOST_P/.jev/bootstrap.pending" "m7-5 ... and NOT under the project .jev (nothing reads it there)"
PJ="$( cd "$T" && env HOME="$HOST_P/home" JEV_STATE_DIR="$HOST_P/.jev-state" JEV_CONFIG_DIR="$HOST_P/.cfg" JEV_EVIDENCE_DIR="$HOST_P/.ev" bash "$ST" --json 2>/dev/null )"
assert_eq "true" "$(printf '%s' "$PJ" | jq -r '.bootstrap.pending')" "m7-5 jev-status shows the hook's pending state"

# ---- m7-6: concurrent writer during the MCP mode rewrite -------------------------------------------------------------------------
make_fixture_env c
CF="$T/c.json"; jq -n '{keep:1,mcpServers:{jev:{env:{JEV_MODE:"enforce"}}}}' > "$CF"
cat > "$T/writer.sh" <<'W'
#!/usr/bin/env bash
# simulated concurrent writer: adds one key per call
n="$(cat "$WCOUNT" 2>/dev/null || echo 0)"; [ "$n" -lt "${WMAX:-999}" ] || exit 0; n=$((n+1)); printf '%s' "$n" > "$WCOUNT"
jq --arg k "w$n" '. + {($k): true}' "$WFILE" > "$WFILE.w" && mv -f "$WFILE.w" "$WFILE"
W
chmod +x "$T/writer.sh"
export WCOUNT="$T/wcount" WFILE="$CF"; rm -f "$WCOUNT"
( set +u; source "$LIB"; WMAX=1 JEV_TEST=1 JEV_BEFORE_WRITE_CMD="$T/writer.sh" jev_mcp_mode_rewrite "$CF" shadow ) >/dev/null 2>"$T/c1.err"; rc=$?
assert_eq "0" "$rc" "m7-6 a writer that interfered once: the rewrite retried and succeeded"
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$CF")" "m7-6 ... the mode is rewritten"
assert_eq "true" "$(jq -r '.w1' "$CF")" "m7-6 ... and the concurrent writer's change is NOT lost"
jq -n '{keep:1,mcpServers:{jev:{env:{JEV_MODE:"enforce"}}}}' > "$CF"; rm -f "$WCOUNT"
( set +u; source "$LIB"; JEV_TEST=1 JEV_BEFORE_WRITE_CMD="$T/writer.sh" jev_mcp_mode_rewrite "$CF" shadow ) >/dev/null 2>"$T/c2.err"; rc=$?
assert_nonzero "$rc" "m7-6 a writer that always interferes: the rewrite is SKIPPED (nonzero), not forced"
assert_contains "$T/c2.err" "changed while being rewritten" "m7-6 ... with a warning"
assert_eq "true" "$(jq -r '.w1 and .w2' "$CF")" "m7-6 ... and the concurrent writer's changes are intact"
assert_eq "enforce" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$CF")" "m7-6 ... the file is left as the other writer wrote it"
jq -n '{keep:1,mcpServers:{jev:{env:{JEV_MODE:"enforce"}}}}' > "$CF"
( set +u; source "$LIB"; jev_mcp_mode_rewrite "$CF" shadow ) >/dev/null 2>&1; rc=$?
assert_eq "0" "$rc" "m7-6 control: no concurrent writer -> plain success"
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$CF")" "m7-6 ... mode rewritten"
assert_contains "$REPO/scripts/jev/bootstrap.sh" "jev_mcp_mode_rewrite" "m7-6 bootstrap stage 5 uses the guarded rewrite"

# ---- n7-3: register rewrites JEV_MODE in every covered file ----------------------------------------------------------------------
make_fixture_env r; unset JEV_BASE_URL
B="$T/box"; mkdir -p "$B/.claude" "$HOME/.claude-x"; export JEV_HOME="$B"
printf '{"mcpServers":{}}\n' > "$B/.mcp.json"
jq -n '{mcpServers:{jev:{env:{JEV_MODE:"enforce",JEV_BASE_URL:"https://127.0.0.1:8095"}}}}' > "$HOME/.claude-x/.mcp.json"
env JEV_MODE=shadow bash "$REG" >/dev/null 2>&1 </dev/null
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$HOME/.claude-x/.mcp.json")" "n7-3 register also rewrote JEV_MODE in \$HOME/.claude-*/.mcp.json (status would not mismatch)"
assert_eq "shadow" "$(jq -r '.mcpServers.jev.env.JEV_MODE' "$B/.mcp.json")" "n7-3 ... and in the target home's .mcp.json"

# ---- n7-2: calibrate -------------------------------------------------------------------------------------------------------------
assert_not_contains "$CAL" "JEV_EVIDENCE_DIR (default .jev)" "n7-2 calibrate header no longer claims the .jev default"
assert_contains "$CAL" "jev_write_atomic" "n7-2 write_thresholds uses jev_write_atomic"
make_fixture_env t; unset JEV_BASE_URL
TD="$T/thr"; mkdir -p "$TD"
printf '{"old":true}\n' > "$TD/real.json"; ln -s "$TD/real.json" "$TD/jev-thresholds.json"
for e in 1 2 3 4 5 6 7 8; do : > "$TD/jev-thresholds.17000000$e.json"; done
( set +u; source "$LIB"; NOW=1700000099; OUTPUT='{"new":true}'
  eval "$(sed -n '/^write_thresholds()/,/^}/p' "$CAL")"; write_thresholds "$TD/jev-thresholds.json" )
assert_eq "true" "$(jq -r '.new' "$TD/real.json")" "n7-2 a symlinked thresholds file is written THROUGH (still a symlink)"
assert_eq "1" "$([ -L "$TD/jev-thresholds.json" ] && echo 1 || echo 0)" "n7-2 ... the symlink survives"
assert_le() { if [ "$1" -le "$2" ] 2>/dev/null; then ok "$3"; else fail "$3 ([$1] > [$2])"; fi; }
assert_le "$(ls "$TD"/jev-thresholds.1*.json 2>/dev/null | wc -l)" 5 "n7-2 timestamped threshold copies are capped at 5"
assert_file_exists "$TD/jev-thresholds.1700000099.json" "n7-2 the newest copy (the previous content) is kept"

finish
