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
# Inputs  : the installed agents; no flags needed.
# Outputs : `ok`/`FAIL`/`SKIP` lines and a summary line with the agent versions.
# Exit    : 0 no FAIL (SKIPs allowed) | 1 a real-agent check FAILed | 2 environment
#           error (no jq/python3).
# Side-effects: starts ONE local fake server (and, for opencode, one `opencode
#           serve`); each is killed by its own recorded pid on exit. Never touches
#           the real home or any real agent config. Heavy: run niced, alone.
# Deps    : bash, jq, python3 (+jsonschema for the crush schema check), curl.
# Cross-refs: §11.4.228(A)(3) (per-platform liveness probe), §11.4.69, §11.4.3
#           (SKIP-with-reason), docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
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
  versions="$versions opencode=$(opencode --version 2>&1 | head -1)"
  sandbox opencode
  bash "$AD/install_adapters.sh" --home "$H" --agents opencode --apply >/dev/null
  ok "opencode: REAL opencode resolves the installed plugin entry (debug config)" bash -c "cd '$H/proj' && HOME='$H' XDG_CONFIG_HOME='$H/.config' XDG_DATA_HOME='$H/.local/share' XDG_STATE_HOME='$H/.local/state' XDG_CACHE_HOME='$H/.cache' timeout 60 opencode debug config | jq -e '.plugin[0]|endswith(\"label-sync.mjs\")'"
  OPORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  (cd "$H/proj" && runenv OPENCODE_DISABLE_AUTOUPDATE=true nohup opencode serve --port "$OPORT" >"$H/serve.log" 2>&1 </dev/null & echo $! >"$H/serve.pid")
  PIDS+=("$(cat "$H/serve.pid" 2>/dev/null)")
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
