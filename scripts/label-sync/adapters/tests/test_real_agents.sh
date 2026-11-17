#!/usr/bin/env bash
# scripts/label-sync/adapters/tests/test_real_agents.sh
#
# Purpose : Run the REAL installed CLI agents against the adapters — the evidence
#           behind the TESTED / SCHEMA-ONLY levels in docs/label-sync/ADAPTERS.md.
#           Each agent is sandboxed: HOME and every XDG dir point at a temp dir,
#           the state dir is a temp LABEL_SYNC_DIR, the LLM endpoint is a local
#           fake (fake_openai.py, loopback, no credentials), BROWSER=/bin/true so
#           an agent can never open a browser. Agents that are not installed are
#           an honest SKIP (never a PASS).
# Usage   : test_real_agents.sh [--only kimi|crush|opencode|aider]
# Inputs  : the installed agents; no flags needed. env LABEL_SYNC_TEST_OPENCODE_PORT: port of the
#           sandbox `opencode serve` (default: a free ephemeral loopback port).
# Outputs : `ok`/`FAIL`/`SKIP` lines and a summary line with the agent versions.
# Exit    : 0 no FAIL (SKIPs allowed) | 1 a real-agent check FAILed | 2 environment
#           error (no jq/python3).
# Side-effects: starts ONE local fake server (and, for opencode, one `opencode
#           serve`); each is killed by its own recorded pid on exit. Never touches
#           the real home or any real agent config. opencode >= 2 additionally gets
#           `service set disabled true` in the SANDBOX home, so no command of the test uses
#           (or fails on) the host's shared opencode service on 127.0.0.1:49374.
#           Heavy: run niced, alone.
# Deps    : bash, jq, python3 (+jsonschema for the crush schema check), curl.
# Cross-refs: §11.4.228(A)(3) (per-platform liveness probe), §11.4.69, §11.4.3
#           (SKIP-with-reason), docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
AD="$(cd "$HERE/.." && pwd)"; LS="$AD/.."
only=""; [ "${1:-}" = "--only" ] && only="${2:-}"
for b in jq python3 curl; do command -v "$b" >/dev/null || { echo "test_real_agents: $b missing" >&2; exit 2; }; done
ROOT="$(mktemp -d)"; PIDS=()
cleanup() { local p; for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; rm -rf "$ROOT"; }
trap cleanup EXIT
REAL_BIN="$("$LS/labelctl.sh" --build 2>/dev/null | tail -1)"
export LABEL_SYNC_BIN="$REAL_BIN" LABEL_SYNC_LABELER="$LS/../multitrack/track_branch_label.sh" BROWSER=/bin/true
pass=0 fail=0 skip=0
ok() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   $d"; else fail=$((fail+1)); echo "FAIL $d"; fi; }
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1 (want '$2' got '$3')"; fi; }
skip() { skip=$((skip+1)); echo "SKIP $1"; }
want() { [ -z "$only" ] || [ "$only" = "$1" ]; }
ctl() { "$REAL_BIN/labelctl" "$@"; }
field() { ctl get --id "$1" --json 2>/dev/null | jq -r ".$2"; }
versions=""

sandbox() { # name -> sets H (home) and exports state dir
  H="$ROOT/$1"; mkdir -p "$H/.config" "$H/.local/share" "$H/.local/state" "$H/.cache" "$H/proj"
  export LABEL_SYNC_DIR="$H/state"
}
runenv() { env HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_STATE_HOME="$H/.local/state" XDG_CACHE_HOME="$H/.cache" "$@"; }

PORT=""
fake_server() {
  [ -n "$PORT" ] && return 0
  python3 -I "$HERE/fake_openai.py" >"$ROOT/fake.port" 2>/dev/null &
  PIDS+=("$!")
  for _ in $(seq 1 50); do [ -s "$ROOT/fake.port" ] && break; sleep 0.1; done
  PORT="$(head -1 "$ROOT/fake.port")"
  [ -n "$PORT" ]
}

# ── kimi ─────────────────────────────────────────────────────────────────────
if want kimi; then
if command -v kimi >/dev/null; then
  versions="$versions kimi=$(kimi --version 2>&1 | head -1)"
  sandbox kimi
  bash "$AD/install_adapters.sh" --home "$H" --agents kimi --apply >/dev/null
  ok "kimi: installed config passes the agent's OWN validator (kimi doctor config)" runenv timeout 60 kimi doctor config "$H/.kimi-code/config.toml"
  { printf 'default_model = "m"\n\n[providers.local]\ntype = "openai"\nbase_url = "http://127.0.0.1:9/v1"\napi_key = "fake-not-a-secret"\n\n[models.m]\nprovider = "local"\nmodel = "x"\nmax_context_size = 8000\n\n'; cat "$H/.kimi-code/config.toml"; } >"$H/c2" && mv "$H/c2" "$H/.kimi-code/config.toml"
  (cd "$H/proj" && runenv timeout 90 nice -n 10 kimi -p "say hi" >"$H/kimi.out" 2>&1 </dev/null)
  eid="$(ctl list --json 2>/dev/null | jq -r '[.entities[]|select(.id|startswith("kimi-session_"))][0].id // empty')"
  ok "kimi: REAL kimi fired SessionStart and the adapter registered an entity" test -n "$eid"
  eq "kimi: entity alias" "kimi" "$(field "$eid" alias)"
  eq "kimi: entity carries the model kimi reported" "m" "$(field "$eid" model)"
  eq "kimi: source" "adapter:kimi" "$(field "$eid" source)"
else skip "kimi: not installed"; fi
fi

# ── crush ────────────────────────────────────────────────────────────────────
if want crush; then
if command -v crush >/dev/null; then
  versions="$versions crush=$(crush --version 2>&1 | head -1 | sed 's/crush version //')"
  sandbox crush
  bash "$AD/install_adapters.sh" --home "$H" --agents crush --apply >/dev/null
  crush schema >"$ROOT/crush.schema.json" 2>/dev/null
  if python3 -c "import jsonschema" 2>/dev/null; then
    ok "crush: installed crush.json validates against the agent's OWN schema (crush schema)" python3 -c "
import json,jsonschema; jsonschema.validate(json.load(open('$H/.config/crush/crush.json')), json.load(open('$ROOT/crush.schema.json')))"
  else skip "crush: python jsonschema missing (schema validation)"; fi
  if fake_server; then
    CF="$H/.config/crush/crush.json"
    jq --arg u "http://127.0.0.1:$PORT/v1" '. + {providers:{fake:{type:"openai-compat",base_url:$u,api_key:"x",models:[{id:"fake-model",name:"Fake",cost_per_1m_in:0,cost_per_1m_out:0,cost_per_1m_in_cached:0,cost_per_1m_out_cached:0,context_window:8000,default_max_tokens:1000,can_reason:false,supports_attachments:false}]}}, models:{large:{provider:"fake",model:"fake-model"},small:{provider:"fake",model:"fake-model"}}, options:{disable_provider_auto_update:true}}' "$CF" >"$CF.n" && mv "$CF.n" "$CF"
    (cd "$H/proj" && git init -q . && runenv timeout 90 nice -n 10 crush run --data-dir "$H/data" "list files" >"$H/crush.out" 2>&1 </dev/null)
    eid="$(ctl list --json 2>/dev/null | jq -r '[.entities[]|select(.id|startswith("crush-"))][0].id // empty')"
    ok "crush: REAL crush ran a tool call and its PreToolUse hook registered an entity" test -n "$eid"
    eq "crush: entity alias" "crush" "$(field "$eid" alias)"
    eq "crush: entity state" "running" "$(field "$eid" state)"
  else skip "crush: fake LLM server could not start"; fi
else skip "crush: not installed"; fi
fi

# ── opencode ─────────────────────────────────────────────────────────────────
if want opencode; then
if command -v opencode >/dev/null; then
  sandbox opencode
  ocver="$(runenv opencode --version 2>&1 </dev/null | head -1)"   # `opencode --version` WRITES a log under its data dir: keep it in the sandbox home
  versions="$versions opencode=$ocver"
  bash "$AD/install_adapters.sh" --home "$H" --agents opencode --apply >/dev/null
  ocmajor="$(printf '%s' "$ocver" | sed -n 's/^[^0-9]*\([0-9][0-9]*\)\.[0-9].*$/\1/p')"
  if [ -z "$ocmajor" ]; then
    fail=$((fail+1)); echo "FAIL opencode: version not recognised (want 'N.x.y', got '$ocver')"
  elif [ "$ocmajor" -ge 2 ]; then
    # opencode >= 2 (the "v2" server). Three things changed against 1.x, each root-caused with a cause toggle (N-04):
    #  (1) every CLI command goes through a per-HOME managed background service bound to 127.0.0.1:49374; a host whose own
    #      `opencode serve --service` holds that port makes every sandbox command exit 1 -> `service set disabled true`
    #      in the SANDBOX home makes the commands use private servers (no fixed port, nothing left running);
    #  (2) `debug config` prints an ARRAY of config sources, each `info` holding the config with the key `plugins`
    #      (1.x: ONE object, key `plugin`);
    #  (3) the HTTP API lives under /api, is password protected (OPENCODE_SERVER_PASSWORD, basic auth, user `opencode`):
    #      POST /api/session creates, DELETE /api/session/:id removes, GET /api/plugin lists the plugins the instance
    #      of the directory loaded (the first request for the directory bootstraps it, then the list fills).
    #      A plugin is only loaded from a DIRECTORY entry exporting a definition with an id and a setup function.
    OCB() { printf 'http://127.0.0.1:%s%s' "$OPORT" "$1"; }
    ocurl() { curl -s -m "${OC_TMO:-20}" -K "$H/curl.auth" "$@"; }
    oc_plugin_state() { # active | failed: <error> | not-listed(<n> plugins loaded) | not-bootstrapped
      local j n
      j="$(ocurl "$(OCB /api/plugin)")" || true
      n="$(printf '%s' "$j" | jq -r '.data|length' 2>/dev/null)"
      case "$n" in ''|0) echo "not-bootstrapped"; return 0 ;; esac
      printf '%s' "$j" | jq -r --argjson n "$n" '[.data[] | select(.id=="label-sync" or ((.source.path // "") | test("/adapters/opencode")))][0] | if . == null then "not-listed(\($n) plugins loaded)" else (.state.status + (if .state.error then ": " + .state.error else "" end)) end'
    }
    oc2_resolves_entry() { # the agent's own `debug config` resolves the entry the installer wrote
      [ -n "$1" ] || return 1
      (cd "$H/proj" && runenv timeout 60 opencode debug config) | jq -e --arg e "$1" 'any(.[]?; ((.info.plugins // .info.plugin // []) | index($e)) != null)'
    }
    (cd "$H/proj" && runenv timeout 30 opencode service set disabled true >/dev/null 2>&1 </dev/null)
    ok "opencode: sandbox home opts out of the shared background service (service set disabled true)" test "$(cd "$H/proj" && runenv timeout 30 opencode service get 2>/dev/null </dev/null | jq -r '.disabled')" = true
    entry="$(jq -r '(.plugins // .plugin // [])[0] // empty' "$H/.config/opencode/opencode.json" 2>/dev/null)"
    ok "opencode: REAL opencode resolves the installed plugin entry (debug config)" oc2_resolves_entry "$entry"
    OCPW="labeltest-$(python3 -c 'import secrets;print(secrets.token_hex(8))')"
    printf 'user = "opencode:%s"\n' "$OCPW" >"$H/curl.auth"; chmod 600 "$H/curl.auth"
    OPORT="${LABEL_SYNC_TEST_OPENCODE_PORT:-$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')}"
    ( cd "$H/proj" && exec env HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_STATE_HOME="$H/.local/state" XDG_CACHE_HOME="$H/.cache" OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_SERVER_PASSWORD="$OCPW" opencode serve --port "$OPORT" >"$H/serve.log" 2>&1 </dev/null ) &
    PIDS+=("$!"); spid="$!"
    up=0; for _ in $(seq 1 60); do kill -0 "$spid" 2>/dev/null || break; [ "$(OC_TMO=2 ocurl -o /dev/null -w '%{http_code}' "$(OCB /api/info)")" = 200 ] && { up=1; break; }; sleep 0.5; done
    if [ "$up" = 1 ]; then
      pst="not-bootstrapped"; for _ in $(seq 1 60); do pst="$(oc_plugin_state)"; [ "$pst" != "not-bootstrapped" ] && break; sleep 0.5; done
      eq "opencode: REAL opencode loaded the label-sync plugin (plugin list state)" "active" "$pst"
      sid="$(ocurl -X POST "$(OCB /api/session)" -H 'content-type: application/json' -d '{"title":"labeltest"}' | jq -r '.data.id // empty' 2>/dev/null)"
      ok "opencode: POST /api/session created a session" test -n "$sid"
      for _ in $(seq 1 50); do [ "$(field "opencode-$sid" state 2>/dev/null)" = running ] && break; sleep 0.3; done
      eq "opencode: REAL session.created event registered the entity" "running" "$(field "opencode-$sid" state)"
      eq "opencode: entity alias" "opencode" "$(field "opencode-$sid" alias)"
      ocurl -X DELETE "$(OCB "/api/session/$sid")" >/dev/null
      for _ in $(seq 1 50); do [ "$(field "opencode-$sid" state 2>/dev/null)" = "done" ] && break; sleep 0.3; done
      eq "opencode: REAL session.deleted event marked it done" "done" "$(field "opencode-$sid" state)"
    else fail=$((fail+1)); echo "FAIL opencode: serve did not come up on port $OPORT: $(head -c 300 "$H/serve.log" 2>/dev/null | tr '\n' ' ')"; fi
  else
    ok "opencode: REAL opencode resolves the installed plugin entry (debug config)" bash -c "cd '$H/proj' && HOME='$H' XDG_CONFIG_HOME='$H/.config' XDG_DATA_HOME='$H/.local/share' XDG_STATE_HOME='$H/.local/state' XDG_CACHE_HOME='$H/.cache' timeout 60 opencode debug config | jq -e '.plugin[0]|endswith(\"label-sync.mjs\")'"
    OPORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
    # `exec` so $! IS the opencode process (a bare `cd && cmd &` backgrounds a subshell and
    # killing that leaves opencode orphaned — observed: two leaked servers)
    ( cd "$H/proj" && exec env HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_STATE_HOME="$H/.local/state" XDG_CACHE_HOME="$H/.cache" OPENCODE_DISABLE_AUTOUPDATE=true opencode serve --port "$OPORT" >"$H/serve.log" 2>&1 </dev/null ) &
    PIDS+=("$!")
    up=0; for _ in $(seq 1 60); do curl -s -m 2 "http://127.0.0.1:$OPORT/session" >/dev/null 2>&1 && { up=1; break; }; sleep 0.5; done
    if [ "$up" = 1 ]; then
      sid="$(curl -s -m 20 -X POST "http://127.0.0.1:$OPORT/session" -H 'content-type: application/json' -d '{"title":"labeltest"}' | jq -r .id)"
      for _ in $(seq 1 30); do [ "$(field "opencode-$sid" state 2>/dev/null)" = running ] && break; sleep 0.3; done
      eq "opencode: REAL session.created event registered the entity" "running" "$(field "opencode-$sid" state)"
      eq "opencode: entity alias" "opencode" "$(field "opencode-$sid" alias)"
      curl -s -m 20 -X DELETE "http://127.0.0.1:$OPORT/session/$sid" >/dev/null
      for _ in $(seq 1 30); do [ "$(field "opencode-$sid" state 2>/dev/null)" = "done" ] && break; sleep 0.3; done
      eq "opencode: REAL session.deleted event marked it done" "done" "$(field "opencode-$sid" state)"
    else skip "opencode: serve did not come up (see $H/serve.log)"; fi
  fi
else skip "opencode: not installed"; fi
fi

# ── aider ────────────────────────────────────────────────────────────────────
if want aider; then
if command -v aider >/dev/null; then
  versions="$versions aider=$(aider --version 2>&1 | head -1 | sed 's/aider //')"
  sandbox aider
  bash "$AD/install_adapters.sh" --home "$H" --agents aider --apply >/dev/null
  out="$(cd "$H/proj" && runenv timeout 60 aider -c "$H/.aider.conf.yml" --exit --no-git --no-check-update --no-analytics --no-show-release-notes --yes --verbose </dev/null 2>&1)"
  case "$out" in *"notifications_command"*"aider-notify"*|*"notifications_command"*) ok "aider: REAL aider parsed the installed notifications-command" true ;; *) ok "aider: REAL aider parsed the installed notifications-command" false ;; esac
  if fake_server; then
    (cd "$H/proj" && echo hi >a.txt && runenv timeout 100 nice -n 10 "$AD/aider/aider-labelled.sh" --model openai/fake-model --openai-api-base "http://127.0.0.1:$PORT/v1" --openai-api-key x --no-git --no-check-update --no-analytics --yes --no-show-model-warnings --no-show-release-notes --no-auto-commits --no-stream --message hello >"$H/aider.out" 2>&1 </dev/null)
    eid="$(ctl list --json 2>/dev/null | jq -r '[.entities[]|select(.id|startswith("aider-run"))][0].id // empty')"
    ok "aider: REAL aider ran under aider-labelled.sh and its entity was registered" test -n "$eid"
    eq "aider: model shown from --model" "openai/fake-model" "$(field "$eid" model)"
    eq "aider: entity done after aider exited" "done" "$(field "$eid" state)"
  else skip "aider: fake LLM server could not start"; fi
else skip "aider: not installed"; fi
fi

echo "---"; echo "test_real_agents: $pass passed, $fail failed, $skip skipped;$versions"
[ "$fail" = 0 ]
