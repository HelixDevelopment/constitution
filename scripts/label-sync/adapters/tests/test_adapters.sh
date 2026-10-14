#!/usr/bin/env bash
# scripts/label-sync/adapters/tests/test_adapters.sh
#
# Purpose : HERMETIC test suite for the label-sync CLI-agent adapters (no real
#           agent is run; payloads are the shapes captured from / documented by
#           each agent — see ADAPTERS.md). Covers the shared lib + event CLI, the
#           kimi/crush/aider/codex/gemini/qwen hooks, the OpenCode plugin module,
#           the generic supervising wrapper and install_adapters.sh (dry-run,
#           idempotency, backups, refusal of invalid/conflicting configs, --home
#           isolation, rollback). Real-agent runs live in test_real_agents.sh.
# Usage   : test_adapters.sh [--only SECTION]      SECTION = lib|kimi|crush|aider|codex|gemini|run|opencode|install
# Inputs  : none (all state in temp dirs; HOME is pointed at a poisoned temp dir
#           so any stray write to the real home is caught).
# Outputs : `ok`/`FAIL` lines and a summary.
# Exit    : 0 all pass | 1 a test failed | 2 environment error (jq/python3/node missing).
# Side-effects: temp dirs only (removed on exit).
# Deps    : bash, jq, python3 (>=3.11, PyYAML), node (for the opencode section).
# Cross-refs: §11.4.43/§11.4.224 (tests-first), §11.4.18, §1.1 (paired mutation:
#           ../prove_adapter_mutations.sh), docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
AD="${ADAPTERS_DIR:-$(cd "$HERE/.." && pwd)}"
LS="$AD/.."
only=""
[ "${1:-}" = "--only" ] && only="${2:-}"
for b in jq python3; do command -v "$b" >/dev/null || { echo "test_adapters: $b missing" >&2; exit 2; }; done

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
POISON="$ROOT/poison-home"; mkdir -p "$POISON"
export HOME="$POISON" XDG_CACHE_HOME="${REAL_XDG_CACHE:-}"
# the labelctl binary cache must be shared (a rebuild per test would take minutes)
export LABEL_SYNC_BIN="${LABEL_SYNC_BIN:-$("$LS/labelctl.sh" --build 2>/dev/null | tail -1)}"
unset XDG_CACHE_HOME
[ -x "$LABEL_SYNC_BIN/labelctl" ] || { echo "test_adapters: cannot build labelctl" >&2; exit 2; }
export LABEL_SYNC_LABELER="$LS/../multitrack/track_branch_label.sh"
pass=0 fail=0
ok() { # desc, then a command
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); echo "ok   $d"; else fail=$((fail+1)); echo "FAIL $d"; fi
}
eq() { # desc expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else fail=$((fail+1)); echo "FAIL $1 (want '$2' got '$3')"; fi
}
newstate() { export LABEL_SYNC_DIR="$ROOT/state-$RANDOM$RANDOM"; mkdir -p "$LABEL_SYNC_DIR"; }
ctl() { "$LABEL_SYNC_BIN/labelctl" "$@"; }
field() { ctl get --id "$1" --json 2>/dev/null | jq -r ".$2"; }
count() { ctl list --json 2>/dev/null | jq '.entities|length'; }
want() { [ -z "$only" ] || [ "$only" = "$1" ]; }

# ── lib + event CLI ──────────────────────────────────────────────────────────
if want lib; then
newstate
EV="$AD/lib/label-adapter-event.sh"
out="$(bash "$EV" --agent kimi --event register --session s1 --cwd "$LS" --model k3)"
eq "lib: event CLI prints the entity id" "kimi-s1" "$out"
eq "lib: alias is the agent name" "kimi" "$(field kimi-s1 alias)"
eq "lib: kind=session" "session" "$(field kimi-s1 kind)"
eq "lib: follow_active=false (own identity)" "false" "$(field kimi-s1 follow_active)"
eq "lib: model shown" "k3" "$(field kimi-s1 model)"
eq "lib: effort NOT invented from the Claude session (empty)" "" "$(field kimi-s1 effort | sed 's/^null$//')"
eq "lib: source records the adapter" "adapter:kimi" "$(field kimi-s1 source)"
case "$(ctl label kimi-s1)" in "(T"*" - kimi - k3 - ?)") ok "lib: label grammar 5-field with ? effort" true ;; *) ok "lib: label grammar" false ;; esac
bash "$EV" --agent kimi --event register --session s1 --cwd "$LS" --model k3 >/dev/null
eq "lib: re-register is idempotent (1 entity)" "1" "$(count)"
started="$(field kimi-s1 started_at)"; sleep 1
bash "$EV" --agent kimi --event heartbeat --session s1 --state idle >/dev/null
eq "lib: heartbeat sets state" "idle" "$(field kimi-s1 state)"
eq "lib: started_at preserved across upserts" "$started" "$(field kimi-s1 started_at)"
bash "$EV" --agent opencode --event heartbeat --session ghost --state idle >/dev/null
eq "lib: heartbeat of an unknown entity registers it (level-triggered)" "idle" "$(field opencode-ghost state)"
bash "$EV" --agent kimi --event "done" --session s1 >/dev/null
eq "lib: done marks state=done" "done" "$(field kimi-s1 state)"
ctl switch-alias --alias claude2 --model opus --effort max >/dev/null
case "$(ctl label kimi-s1)" in *"claude2"*) ok "lib: non-Claude agent must NOT follow the Claude switch" false ;; *) ok "lib: non-Claude agent keeps its own alias after an operator switch" true ;; esac
LABEL_SYNC_FOLLOW_ACTIVE=1 bash "$EV" --agent kimi --event register --session f1 --cwd "$LS" >/dev/null
ctl switch-alias --alias claude3 --model haiku --effort low >/dev/null
case "$(ctl label kimi-f1)" in *"claude3 - haiku - low"*) ok "lib: LABEL_SYNC_FOLLOW_ACTIVE=1 follows the operator switch" true ;; *) ok "lib: follow switch ($(ctl label kimi-f1))" false ;; esac
LABEL_SYNC_AGENT_ALIAS=my-kimi bash "$EV" --agent kimi --event register --session a1 --cwd "$LS" >/dev/null
eq "lib: LABEL_SYNC_AGENT_ALIAS overrides alias" "my-kimi" "$(field kimi-a1 alias)"
# disabled -> no writes at all
newstate
LABEL_SYNC_DISABLE=1 bash "$EV" --agent kimi --event register --session z >/dev/null; rc=$?
eq "lib: LABEL_SYNC_DISABLE=1 exits 0" "0" "$rc"
ok "lib: LABEL_SYNC_DISABLE=1 writes nothing" test ! -e "$LABEL_SYNC_DIR/events.jsonl"
# usage errors
bash "$EV" --event register >/dev/null 2>&1; eq "lib: missing --agent exits 2" "2" "$?"
bash "$EV" --agent x --event bogus >/dev/null 2>&1; eq "lib: bad --event exits 2" "2" "$?"
# hostile session id
newstate
bash "$EV" --agent kimi --event register --session 'a/b;$(touch '"$ROOT"'/pwn) `x`' --cwd "$LS" >/dev/null
ok "lib: hostile session id never executes" test ! -e "$ROOT/pwn"
eq "lib: the hostile-session register still produced ONE (sanitized) entity" "1" "$(count)"
case "$(ctl list --json | jq -r '.entities[0].id')" in *[!A-Za-z0-9._-]*|null) ok "lib: hostile id sanitized" false ;; *) ok "lib: hostile id sanitized" true ;; esac
# bus unusable => still exit 0
LABEL_SYNC_DIR=/proc/nonexistent/x bash "$EV" --agent kimi --event register --session q >/dev/null 2>&1; eq "lib: unusable state dir is fail-soft (exit 0)" "0" "$?"
# long id bounded and distinct
newstate
l1="$(printf 'a%.0s' $(seq 1 200))1"; l2="$(printf 'a%.0s' $(seq 1 200))2"
bash "$EV" --agent kimi --event register --session "$l1" >/dev/null; bash "$EV" --agent kimi --event register --session "$l2" >/dev/null
eq "lib: two long ids stay distinct" "2" "$(count)"
fi

# ── kimi ─────────────────────────────────────────────────────────────────────
if want kimi; then
newstate
K="$AD/kimi/kimi-hook.sh"
kh() { printf '%s' "$1" | bash "$K"; }
# shape CAPTURED from a real kimi 2.1.1 run (SessionStart / UserPromptSubmit)
out="$(kh '{"hook_event_name":"SessionStart","session_id":"session_775c69e2","cwd":"'"$LS"'","client_type":"kimi_code_cli","source":"startup","model":"kimi-code/k3","profile":"agent"}')"; rc=$?
eq "kimi: hook prints nothing" "" "$out"; eq "kimi: hook exits 0" "0" "$rc"
eq "kimi: SessionStart registers with the payload model" "kimi-code/k3" "$(field kimi-session_775c69e2 model)"
eq "kimi: SessionStart state running" "running" "$(field kimi-session_775c69e2 state)"
kh '{"hook_event_name":"UserPromptSubmit","session_id":"session_775c69e2","cwd":"/x","prompt":[{"type":"text","text":"SECRET-CANARY-123"}],"is_steer":false}'
eq "kimi: UserPromptSubmit keeps running" "running" "$(field kimi-session_775c69e2 state)"
ok "kimi: the prompt text never reaches the bus" bash -c "! grep -rq SECRET-CANARY-123 '$LABEL_SYNC_DIR'"
kh '{"hook_event_name":"Stop","session_id":"session_775c69e2","cwd":"/x"}'
eq "kimi: Stop -> idle" "idle" "$(field kimi-session_775c69e2 state)"
kh '{"hook_event_name":"SubagentStart","session_id":"session_775c69e2","cwd":"/x","agent_name":"explorer","prompt":"p"}'
eq "kimi: SubagentStart registers a subagent" "subagent" "$(field kimi-session_775c69e2.sub.explorer kind)"
eq "kimi: subagent parent is the session entity" "kimi-session_775c69e2" "$(field kimi-session_775c69e2.sub.explorer parent_id)"
kh '{"hook_event_name":"SubagentStop","session_id":"session_775c69e2","cwd":"/x","agent_name":"explorer"}'
eq "kimi: SubagentStop -> done" "done" "$(field kimi-session_775c69e2.sub.explorer state)"
kh '{"hook_event_name":"SessionEnd","session_id":"session_775c69e2","cwd":"/x","reason":"exit"}'
eq "kimi: SessionEnd -> done" "done" "$(field kimi-session_775c69e2 state)"
kh '{"hook_event_name":"SessionStart","session_id":"m2","cwd":"/x","model":{"name":"obj-model"}}'
eq "kimi: object-shaped model tolerated" "obj-model" "$(field kimi-m2 model)"
for bad in '' 'not json' '[1,2]' '{"hook_event_name":"SessionStart"}' '{"hook_event_name":"Weird","session_id":"w"}'; do
  out="$(printf '%s' "$bad" | bash "$K")"; rc=$?
  eq "kimi: bad/odd input '${bad:0:20}' exits 0 silently" "0:" "$rc:$out"
done
eq "kimi: odd inputs created no entity" "0" "$(ctl list --json | jq '[.entities[]|select(.id=="kimi-w" or .id=="kimi-")]|length')"
fi

# ── crush ────────────────────────────────────────────────────────────────────
if want crush; then
newstate
C="$AD/crush/crush-hook.sh"
out="$(CRUSH_SESSION_ID=cs1 CRUSH_CWD="$LS" bash "$C" <<<'{"event":"PreToolUse","session_id":"cs1","cwd":"/x","tool_name":"bash","tool_input":{"command":"echo SECRET-CANARY-9"}}')"; rc=$?
eq "crush: stdout is the decision-free envelope" '{"version":1}' "$out"
eq "crush: exit 0 (never 2/49)" "0" "$rc"
eq "crush: PreToolUse registers+running" "running" "$(field crush-cs1 state)"
ok "crush: tool input never reaches the bus" bash -c "! grep -rq SECRET-CANARY-9 '$LABEL_SYNC_DIR'"
out="$(bash "$C" <<<'{"event":"PreToolUse","session_id":"cs2","cwd":"/x","tool_name":"ls"}')"
eq "crush: stdin-only payload (no env) works" "running" "$(field crush-cs2 state)"
out="$(LABEL_SYNC_DISABLE=1 CRUSH_SESSION_ID=cs3 bash "$C" </dev/null)"; rc=$?
eq "crush: disabled still answers with the envelope" "0:{\"version\":1}" "$rc:$out"
ok "crush: disabled wrote no entity" test -z "$(ctl list --json | jq -r '.entities[]|select(.id=="crush-cs3").id')"
out="$(LABEL_SYNC_LABELCTL=/nonexistent LABEL_SYNC_BIN=/nonexistent CRUSH_SESSION_ID=cs4 bash "$C" </dev/null)"; rc=$?
eq "crush: no labelctl => still envelope + exit 0" "0:{\"version\":1}" "$rc:$out"
fi

# ── aider ────────────────────────────────────────────────────────────────────
if want aider; then
newstate
N="$AD/aider/aider-notify.sh"
LABEL_SYNC_ENTITY_ID=aider-fixed bash "$N"; rc=$?
eq "aider-notify: exits 0" "0" "$rc"
eq "aider-notify: heartbeat idle on the wrapper's entity id" "idle" "$(field aider-fixed state)"
# wrapper with a fake aider
FA="$ROOT/fake-aider"; cat >"$FA" <<'FAKE'
#!/usr/bin/env bash
echo "ARGS: $*" >"$FAKE_AIDER_OUT"
echo "ENTITY: ${LABEL_SYNC_ENTITY_ID:-}" >>"$FAKE_AIDER_OUT"
bash -c "$NOTIFY_CMD" || true
exit "${FAKE_AIDER_RC:-0}"
FAKE
chmod +x "$FA"
newstate
export FAKE_AIDER_OUT="$ROOT/aider.out" LABEL_SYNC_AIDER_BIN="$FA" FAKE_AIDER_RC=3
export NOTIFY_CMD="bash $N"
bash "$AD/aider/aider-labelled.sh" --model gpt-5 --yes; rc=$?
eq "aider-labelled: propagates aider's exit code" "3" "$rc"
ok "aider-labelled: passes --notifications-command" grep -q -- '--notifications-command bash .*aider-notify.sh' "$FAKE_AIDER_OUT"
ok "aider-labelled: keeps the user's own args" grep -q -- '--model gpt-5 --yes' "$FAKE_AIDER_OUT"
eid="$(sed -n 's/^ENTITY: //p' "$FAKE_AIDER_OUT")"
ok "aider-labelled: child got LABEL_SYNC_ENTITY_ID" test -n "$eid"
eq "aider-labelled: model parsed from --model" "gpt-5" "$(field "$eid" model)"
eq "aider-labelled: entity done after exit" "done" "$(field "$eid" state)"
eq "aider-labelled: notify updated the SAME entity (1 entity)" "1" "$(count)"
newstate
bash "$AD/aider/aider-labelled.sh" --notifications-command "echo mine"
ok "aider-labelled: user's own --notifications-command is not duplicated" bash -c "[ \"\$(grep -o -- '--notifications-command' '$FAKE_AIDER_OUT' | wc -l)\" = 1 ]"
unset FAKE_AIDER_OUT LABEL_SYNC_AIDER_BIN FAKE_AIDER_RC NOTIFY_CMD
fi

# ── codex / gemini / qwen ────────────────────────────────────────────────────
if want codex; then
newstate
X="$AD/codex/codex-notify.sh"
bash "$X" '{"type":"agent-turn-complete","thread-id":"th1","turn-id":"t1","cwd":"'"$LS"'","input-messages":["SECRET-CANARY-7"],"last-assistant-message":"SECRET-CANARY-8"}'; rc=$?
eq "codex: exits 0" "0" "$rc"
eq "codex: agent-turn-complete -> idle heartbeat (registers)" "idle" "$(field codex-th1 state)"
ok "codex: messages never reach the bus" bash -c "! grep -rqE 'SECRET-CANARY-[78]' '$LABEL_SYNC_DIR'"
bash "$X" '{"type":"something-else","thread-id":"th2"}'; eq "codex: other event types ignored" "" "$(field codex-th2 state 2>/dev/null | sed 's/^null$//')"
bash "$X" 'garbage'; eq "codex: garbage exits 0" "0" "$?"
bash "$X"; eq "codex: no argv exits 0" "0" "$?"
fi
if want gemini; then
newstate
G="$AD/gemini/gemini-hook.sh"; Q="$AD/qwen/qwen-hook.sh"
out="$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"gs1","cwd":"'"$LS"'"}' | bash "$G")"; rc=$?
eq "gemini: stdout is {} and exit 0" "0:{}" "$rc:$out"
eq "gemini: SessionStart registers" "running" "$(field gemini-gs1 state)"
printf '%s' '{"hook_event_name":"AfterAgent","session_id":"gs1"}' | bash "$G" >/dev/null
eq "gemini: AfterAgent -> idle" "idle" "$(field gemini-gs1 state)"
printf '%s' '{"hook_event_name":"SessionEnd","session_id":"gs1"}' | bash "$G" >/dev/null
eq "gemini: SessionEnd -> done" "done" "$(field gemini-gs1 state)"
out="$(printf '%s' '{"hook_event_name":"SessionStart","session_id":"qs1","cwd":"'"$LS"'"}' | bash "$Q")"
eq "qwen: delegates with agent name qwen" "qwen" "$(field qwen-qs1 alias)"
eq "qwen: stdout {}" "{}" "$out"
out="$(printf 'junk' | bash "$G")"; eq "gemini: junk input still prints {}" "{}" "$out"
fi

# ── generic wrapper ──────────────────────────────────────────────────────────
if want run; then
newstate
R="$AD/generic/label-agent-run.sh"
bash "$R" --agent codex --model gpt-5 -- bash -c 'exit 0'; eq "run: exit 0 propagated" "0" "$?"
bash "$R" --agent codex -- bash -c 'exit 3'; eq "run: exit 3 propagated" "3" "$?"
bash "$R" --agent codex -- /nonexistent/binary 2>/dev/null; eq "run: 127 propagated" "127" "$?"
bash "$R" --agent codex 2>/dev/null; eq "run: no command => usage exit 2" "2" "$?"
bash "$R" --bogus 2>/dev/null; eq "run: unknown option => exit 2" "2" "$?"
# entity visible while running, done afterwards; child sees its entity id
out="$(bash "$R" --agent codex --model gpt-5 --alias myagent -- bash -c 'echo "$LABEL_SYNC_ENTITY_ID"; "$LABEL_SYNC_BIN/labelctl" list --text' 2>&1)"
eid="$(printf '%s\n' "$out" | head -1)"
case "$out" in *"myagent - gpt-5 - ?"*) ok "run: label visible WHILE the agent runs (alias+model)" true ;; *) ok "run: label visible while running ($out)" false ;; esac
eq "run: entity done after the agent exits" "done" "$(field "$eid" state)"
# signal: TERM to the wrapper is forwarded; exit 143; entity done
newstate
bash "$R" --agent codex -- sleep 30 &
wp=$!
for _ in $(seq 1 50); do [ "$(count)" = 1 ] && break; sleep 0.1; done
kill -TERM "$wp"; wait "$wp"; rc=$?
eq "run: TERM forwarded; wrapper exit 143" "143" "$rc"
eq "run: entity done after TERM" "done" "$(ctl list --json | jq -r '.entities[0].state')"
ok "run: no orphan sleep left" bash -c "! pgrep -f 'sleep 30' -P $wp"
# review-2 F: TERM forwarded is PROVEN by the child (it records the signal and
# exits 7), not inferred from 143 (which bash dying would also produce)
newstate
TRAPC="$ROOT/trapchild.sh"
printf '#!/usr/bin/env bash\ntrap '"'"'echo CHILD_GOT_TERM >"%s"; exit 7'"'"' TERM\nsleep 30 & wait\n' "$ROOT/term.marker" >"$TRAPC"
bash "$R" --agent codex -- bash "$TRAPC" &
wp=$!
for _ in $(seq 1 50); do [ "$(count)" = 1 ] && break; sleep 0.1; done
sleep 0.3; kill -TERM "$wp"; wait "$wp"; rc=$?
eq "run: TERM really forwarded (the child trapped it and exited 7)" "7" "$rc"
ok "run: the child recorded the forwarded TERM" grep -q CHILD_GOT_TERM "$ROOT/term.marker"
# review-2 F: a TERM that arrives WHILE registering leaves no running ghost and
# never starts the agent (deterministic: a labelctl shim slows `register`)
newstate
SHIM="$ROOT/slowctl.sh"
printf '#!/usr/bin/env bash\nr=0; [ "$1" = register ] && { sleep 1.5; r=1; }\n"%s/labelctl" "$@"; rc=$?\n[ "$r" = 1 ] && touch "%s/shim.done"\nexit $rc\n' "$LABEL_SYNC_BIN" "$ROOT" >"$SHIM"; chmod +x "$SHIM"
rm -f "$ROOT/started.marker" "$ROOT/shim.done"
LABEL_SYNC_LABELCTL="$SHIM" bash "$R" --agent codex -- bash -c "touch '$ROOT/started.marker'; sleep 5" &
wp=$!; sleep 0.5; kill -TERM "$wp"; wait "$wp"; rc=$?
eq "run: TERM during registration => wrapper exit 143" "143" "$rc"
ok "run: TERM during registration => the agent was never started" test ! -e "$ROOT/started.marker"
for _ in $(seq 1 50); do [ -e "$ROOT/shim.done" ] && break; sleep 0.1; done   # the slowed register really completed
sleep 0.3
ok "run: fixture — the slowed registration really completed" test -e "$ROOT/shim.done"
eq "run: TERM during registration => no running ghost entity" "0" "$(ctl list --json | jq -r '[.entities[]|select(.state!="done")]|length')"
# re-review 7: a TERM landing AFTER the "signalled while registering" check but
# BEFORE the child pid is known must still reach the agent (test-only seam:
# the wrapper signals itself right before the spawn).
newstate
t0=$SECONDS
LABEL_SYNC_TEST_MODE=1 LABEL_AGENT_RUN_TEST_SIGNAL_BEFORE_SPAWN=TERM bash "$R" --agent codex -- sleep 8; rc=$?
el=$((SECONDS - t0))
ok "run: a TERM in the spawn window still stops the agent (took ${el}s, rc $rc; the agent sleeps 8)" test "$el" -lt 5
eq "run: ...the wrapper exits 143 for that TERM" "143" "$rc"
LABEL_AGENT_RUN_TEST_SIGNAL_BEFORE_SPAWN=TERM bash "$R" --agent codex -- true; rc=$?
eq "run: the spawn seam is inert without LABEL_SYNC_TEST_MODE=1" "0" "$rc"
# review-2 N8: the agent reads the wrapper's stdin
out="$(printf 'IN-CANARY-42' | bash "$R" --agent codex -- cat 2>/dev/null)"
eq "run: the agent receives the wrapper's stdin" "IN-CANARY-42" "$out"
# review-2 I: an option missing its value is a usage error, never a hang
timeout 10 bash "$R" --agent >/dev/null 2>&1; eq "run: trailing --agent without a value exits 2 (no hang)" "2" "$?"
timeout 10 bash "$AD/lib/label-adapter-event.sh" --agent kimi --event >/dev/null 2>&1; eq "lib: trailing --event without a value exits 2 (no hang)" "2" "$?"
# review-2 B: a terminal Ctrl-C reaches the agent exactly ONCE (pty)
if command -v script >/dev/null 2>&1; then
  # emulate an interactive terminal: the pty session starts with DEFAULT
  # SIGINT/SIGQUIT even when this suite itself was launched in the background
  # (an inherited SIG_IGN cannot be reset by any shell: "ignored upon entry")
  TERMRUN=(); env --default-signal=INT,QUIT true 2>/dev/null && TERMRUN=(env --default-signal=INT,QUIT)
  CNT="$ROOT/intcount.sh"
  printf '#!/usr/bin/env bash\nn=0; trap '"'"'n=$((n+1))'"'"' INT\nfor _ in $(seq 25); do sleep 0.1 || :; done\necho "INTS=$n"\n' >"$CNT"
  TTYO="$( { sleep 1; printf '\003'; sleep 3; } | "${TERMRUN[@]}" script -qec "bash '$R' --agent codex -- bash '$CNT'" /dev/null 2>&1 | tr -d '\r')"
  case "$TTYO" in *"INTS=1"*) ok "run: tty Ctrl-C delivered to the agent exactly once (INT not ignored, not duplicated)" true ;;
    *) ok "run: tty Ctrl-C delivered exactly once (got: $(printf '%s' "$TTYO" | grep -o 'INTS=[0-9]*'))" false ;; esac
  PIDF="$ROOT/b2.pid"; rm -f "$PIDF"; CNT2="$ROOT/intcount2.sh"
  printf '#!/usr/bin/env bash\necho "$PPID" >"%s"\nn=0; trap '"'"'n=$((n+1))'"'"' INT\nfor _ in $(seq 25); do sleep 0.1 || :; done\necho "INTS=$n"\n' "$PIDF" >"$CNT2"
  ( for _ in $(seq 50); do [ -s "$PIDF" ] && break; sleep 0.1; done; lp="$(cat "$PIDF" 2>/dev/null)"
    case "$lp" in ''|*[!0-9]*) ;; *) [ "$lp" -gt 1 ] && grep -qa label-agent-run "/proc/$lp/cmdline" && kill -INT "$lp" ;; esac ) &
  KP=$!
  TTYO2="$( { sleep 4; } | "${TERMRUN[@]}" script -qec "bash '$R' --agent codex -- bash '$CNT2'" /dev/null 2>&1 | tr -d '\r')"
  wait "$KP" 2>/dev/null
  case "$TTYO2" in *"INTS=0"*) ok "run: an external SIGINT is not duplicated onto a tty-foreground agent" true ;;
    *) ok "run: no duplicate SIGINT (got: $(printf '%s' "$TTYO2" | grep -o 'INTS=[0-9]*'))" false ;; esac
else echo "SKIP run: tty Ctrl-C (script(1) not installed)"; fi
# fail-soft: bus unusable, command still runs and its code returns
LABEL_SYNC_DIR=/proc/nonexistent/x bash "$R" --agent codex -- bash -c 'exit 7' 2>/dev/null; eq "run: unusable bus still runs the command" "7" "$?"
# arguments never recorded
newstate
bash "$R" --agent codex -- bash -c 'true' --token=SECRET-CANARY-5 2>/dev/null
ok "run: command arguments never recorded" bash -c "! grep -rq SECRET-CANARY-5 '$LABEL_SYNC_DIR'"
fi

# ── opencode plugin ──────────────────────────────────────────────────────────
if want opencode; then
if command -v node >/dev/null; then
newstate
P="$AD/opencode/label-sync.mjs"
ok "opencode: plugin parses (node --check)" node --check "$P"
drive() { LABEL_SYNC_PLUGIN_SYNC=1 node --input-type=module -e "
import m from 'file://$P';
const h = await m.server({ directory: '$LS' });
const ev = JSON.parse(process.argv[1]);
if (ev.hook === 'chat.message') await h['chat.message'](ev.input); else await h.event({ event: ev.event });
" "$1"; }
drive '{"event":{"type":"session.created","properties":{"info":{"id":"ses_A","directory":"'"$LS"'"}}}}'
eq "opencode: session.created registers" "running" "$(field opencode-ses_A state)"
eq "opencode: alias is opencode" "opencode" "$(field opencode-ses_A alias)"
drive '{"hook":"chat.message","input":{"sessionID":"ses_A","model":{"providerID":"anthropic","modelID":"claude-x"}}}'
eq "opencode: chat.message carries the real model" "anthropic/claude-x" "$(field opencode-ses_A model)"
drive '{"event":{"type":"session.idle","properties":{"sessionID":"ses_A"}}}'
eq "opencode: session.idle -> idle" "idle" "$(field opencode-ses_A state)"
drive '{"event":{"type":"session.created","properties":{"info":{"id":"ses_B","parentID":"ses_A","directory":"'"$LS"'"}}}}'
eq "opencode: child session is a subagent" "subagent" "$(field opencode-ses_B kind)"
eq "opencode: subagent parent is the parent entity" "opencode-ses_A" "$(field opencode-ses_B parent_id)"
drive '{"event":{"type":"session.deleted","properties":{"info":{"id":"ses_A"}}}}'
eq "opencode: session.deleted -> done" "done" "$(field opencode-ses_A state)"
out="$(drive '{"event":{"type":"message.part.updated","properties":{"part":{"text":"SECRET-CANARY-3"}}}}' 2>&1)"; rc=$?
eq "opencode: unrelated events are ignored without error" "0" "$rc"
ok "opencode: message content never reaches the bus" bash -c "! grep -rq SECRET-CANARY-3 '$LABEL_SYNC_DIR'"
out="$(drive 'not json at all' 2>&1)"; ok "opencode: a throwing driver does not corrupt state" test -r "$LABEL_SYNC_DIR/events.jsonl"
out="$(LABEL_SYNC_PLUGIN_SYNC=1 node --input-type=module -e "
import m from 'file://$P'; const h = await m.server({}); await h.event({}); await h.event(null); await h['chat.message'](undefined); console.log('no-throw')" 2>&1)"
eq "opencode: malformed hook inputs never throw" "no-throw" "$out"
else echo "SKIP opencode section: node not installed"; fi
fi

# ── installer ────────────────────────────────────────────────────────────────
if want install; then
INST="$AD/install_adapters.sh"
tree_sum() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum); }
ALLAG=kimi,opencode,crush,aider,codex,gemini,qwen
H="$ROOT/h1"; mkdir -p "$H"
before="$(tree_sum "$H")"; pb="$(tree_sum "$POISON")"
out="$(bash "$INST" --home "$H" --agents $ALLAG)"; rc=$?
eq "install: default is dry-run, exit 0" "0" "$rc"
eq "install: dry-run writes NOTHING" "$before" "$(tree_sum "$H")"
case "$out" in *"would-created"*"DRY-RUN"*) ok "install: dry-run announces itself" true ;; *"DRY-RUN"*) ok "install: dry-run reports would-created" "$(printf '%s' "$out" | grep -c would-created)" ;; *) ok "install: dry-run announces itself" false ;; esac
bash "$INST" --home "$H" --agents $ALLAG --apply >/dev/null; rc=$?
eq "install: --apply exit 0" "0" "$rc"
for f in .kimi-code/config.toml .config/opencode/opencode.json .config/crush/crush.json .aider.conf.yml .codex/config.toml .gemini/settings.json .qwen/settings.json; do
  ok "install: wrote $f" test -s "$H/$f"
done
ok "install: kimi config is valid TOML with 6 hooks" python3 -c "import tomllib,sys;d=tomllib.load(open('$H/.kimi-code/config.toml','rb'));assert len(d['hooks'])==6 and all(set(h)<= {'event','command','timeout'} for h in d['hooks'])"
ok "install: codex notify is a TOP-LEVEL key" python3 -c "import tomllib;d=tomllib.load(open('$H/.codex/config.toml','rb'));assert d['notify'][0]=='bash'"
ok "install: aider yaml sets notifications + command" python3 -c "import yaml;d=yaml.safe_load(open('$H/.aider.conf.yml'));assert d['notifications'] is True and 'aider-notify.sh' in d['notifications-command']"
ok "install: crush PreToolUse hook entry" jq -e '.hooks.PreToolUse[0].command|test("crush-hook.sh")' "$H/.config/crush/crush.json"
ok "install: opencode plugin is a file:// URL to an existing file" bash -c "u=\$(jq -r '.plugin[0]' '$H/.config/opencode/opencode.json'); [ -r \"\${u#file://}\" ]"
ok "install: gemini hooks use command type" jq -e '.hooks.SessionStart[0].hooks[0].type=="command"' "$H/.gemini/settings.json"
one="$(tree_sum "$H")"
bash "$INST" --home "$H" --agents $ALLAG --apply >/dev/null
eq "install: second --apply is byte-identical (idempotent)" "$one" "$(tree_sum "$H")"
eq "install: idempotent run created no backups" "0" "$(find "$H" -name '*.label-sync.bak.*' | wc -l)"
eq "install: poisoned real HOME untouched" "$pb" "$(tree_sum "$POISON")"
# clobber check: existing user content survives and a backup is made
H2="$ROOT/h2"; mkdir -p "$H2/.kimi-code" "$H2/.config/crush" "$H2/.config/opencode" "$H2/.codex"
printf 'default_model = "mine"\n\n[models.mine]\nprovider = "p"\nmodel = "m"\nmax_context_size = 1000\n' >"$H2/.kimi-code/config.toml"
printf '{"options":{"debug":true},"hooks":{"PreToolUse":[{"command":"./mine.sh"}]}}\n' >"$H2/.config/crush/crush.json"
printf '{"theme":"x","plugin":["some-other-plugin@1.0"]}\n' >"$H2/.config/opencode/opencode.json"
printf '[tui]\ntheme = "dark"\n' >"$H2/.codex/config.toml"
bash "$INST" --home "$H2" --agents kimi,crush,opencode,codex --apply >/dev/null; rc=$?
eq "install: merge into existing configs exit 0" "0" "$rc"
ok "install: kimi user content preserved" grep -q 'default_model = "mine"' "$H2/.kimi-code/config.toml"
ok "install: crush user hook preserved + ours added" jq -e '(.hooks.PreToolUse|length)==2 and .options.debug==true and .hooks.PreToolUse[0].command=="./mine.sh"' "$H2/.config/crush/crush.json"
ok "install: opencode other plugin + theme preserved" jq -e '.theme=="x" and (.plugin|length)==2 and .plugin[0]=="some-other-plugin@1.0"' "$H2/.config/opencode/opencode.json"
ok "install: codex notify precedes [tui] and the table survives" python3 -c "import tomllib;d=tomllib.load(open('$H2/.codex/config.toml','rb'));assert d['notify'][0]=='bash' and d['tui']['theme']=='dark'"
eq "install: one backup per changed existing file (4)" "4" "$(find "$H2" -name '*.label-sync.bak.*' | wc -l)"
ok "install: backup holds the ORIGINAL content" bash -c "grep -q 'default_model = \"mine\"' \$(ls $H2/.kimi-code/config.toml.label-sync.bak.*)"
# rollback
bash "$INST" --home "$H2" --agents kimi,crush,opencode,codex --apply --remove >/dev/null; rc=$?
eq "install: --remove exit 0" "0" "$rc"
ok "install: --remove restored kimi to the user's content" bash -c "! grep -q 'label-sync' '$H2/.kimi-code/config.toml' && grep -q 'default_model' '$H2/.kimi-code/config.toml'"
ok "install: --remove kept crush user hook, dropped ours" jq -e '(.hooks.PreToolUse|length)==1 and .hooks.PreToolUse[0].command=="./mine.sh"' "$H2/.config/crush/crush.json"
ok "install: --remove kept opencode other plugin" jq -e '.plugin==["some-other-plugin@1.0"]' "$H2/.config/opencode/opencode.json"
ok "install: --remove kept codex [tui]" python3 -c "import tomllib;d=tomllib.load(open('$H2/.codex/config.toml','rb'));assert 'notify' not in d and d['tui']['theme']=='dark'"
# refusals: invalid existing files are NEVER touched
H3="$ROOT/h3"; mkdir -p "$H3/.kimi-code" "$H3/.config/crush" "$H3/.config/opencode" "$H3/.codex" "$H3/.gemini"
printf 'this = is [not toml\n' >"$H3/.kimi-code/config.toml"
printf '{ "broken": \n' >"$H3/.config/crush/crush.json"
printf '[1,2,3]\n' >"$H3/.config/opencode/opencode.json"
printf 'notify = ["mine.sh"]\n' >"$H3/.codex/config.toml"
printf 'a: [unclosed\n' >"$H3/.aider.conf.yml"
printf '{"hooks": "nope"}\n' >"$H3/.gemini/settings.json"
b3="$(tree_sum "$H3")"
out="$(bash "$INST" --home "$H3" --agents kimi,crush,opencode,codex,aider,gemini --apply)"; rc=$?
eq "install: refusals exit 1" "1" "$rc"
eq "install: refused configs are byte-identical (untouched, no backup)" "$b3" "$(tree_sum "$H3")"
for a in kimi crush opencode aider; do case "$out" in *"$a invalid"*) ok "install: $a reported invalid" true ;; *) ok "install: $a reported invalid" false ;; esac; done
for a in codex gemini; do case "$out" in *"$a conflict"*) ok "install: $a reported conflict" true ;; *) ok "install: $a reported conflict" false ;; esac; done
# aider own notifications-command conflict
H4="$ROOT/h4"; mkdir -p "$H4"; printf 'notifications-command: "notify-send mine"\nmodel: gpt-5\n' >"$H4/.aider.conf.yml"
b4="$(tree_sum "$H4")"; bash "$INST" --home "$H4" --agents aider --apply >/dev/null; eq "install: aider own notifications-command is a conflict (exit 1)" "1" "$?"
eq "install: aider conflict leaves the file untouched" "$b4" "$(tree_sum "$H4")"
# usage / environment
bash "$INST" --home "$ROOT/does-not-exist" >/dev/null 2>&1; eq "install: bad --home exits 2" "2" "$?"
bash "$INST" --home "$H" --agents nosuch >/dev/null 2>&1; eq "install: unknown agent exits 2" "2" "$?"
bash "$INST" --bogus >/dev/null 2>&1; eq "install: unknown flag exits 2" "2" "$?"
# auto-detection
H5="$ROOT/h5"; mkdir -p "$H5/.kimi-code"
out="$(bash "$INST" --home "$H5" --apply)"
case "$out" in *"kimi created"*) ok "install: auto wires the agent whose config dir exists" true ;; *) ok "install: auto wires detected" false ;; esac
ok "install: auto leaves undetected agents alone" test ! -e "$H5/.codex"
case "$out" in *"codex not-detected"*) ok "install: undetected agents are reported, not failed" true ;; *) ok "install: not-detected reported" false ;; esac
# symlinked config: edited at the target, link survives
H6="$ROOT/h6"; mkdir -p "$H6/.codex" "$ROOT/dotfiles"; printf '[tui]\ntheme="d"\n' >"$ROOT/dotfiles/codex.toml"; ln -s "$ROOT/dotfiles/codex.toml" "$H6/.codex/config.toml"
bash "$INST" --home "$H6" --agents codex --apply >/dev/null
ok "install: symlinked config stays a symlink" test -L "$H6/.codex/config.toml"
ok "install: symlink target edited" grep -q 'notify' "$ROOT/dotfiles/codex.toml"
# --list works and writes nothing
bash "$INST" --home "$H5" --list >/dev/null; eq "install: --list exits 0" "0" "$?"
# review-2 A: idempotency and EXACT rollback when STARTING FROM EXISTING files
H7="$ROOT/h7"; mkdir -p "$H7/.kimi-code" "$H7/.config/opencode" "$H7/.config/crush" "$H7/.codex" "$H7/.gemini" "$H7/.qwen"
printf 'default_model = "mine"\napi_key = "sk-KIMI-CANARY"\n\n[models.mine]\nprovider = "p"' >"$H7/.kimi-code/config.toml"   # no trailing newline
printf '{"theme":"x",\n "plugin": ["other@1"]}' >"$H7/.config/opencode/opencode.json"
printf '{"options": {"debug": true}}\n' >"$H7/.config/crush/crush.json"
printf 'model: gpt-5\n# a comment\n' >"$H7/.aider.conf.yml"
printf '[tui]\ntheme = "dark"\n' >"$H7/.codex/config.toml"
printf '{\n    "ui": {"theme": "x"}\n}\n' >"$H7/.gemini/settings.json"
printf '{}' >"$H7/.qwen/settings.json"
chmod 0644 "$H7/.kimi-code/config.toml"
o7="$(tree_sum "$H7")"
declare -A ORIG7; for f in .kimi-code/config.toml .config/opencode/opencode.json .config/crush/crush.json .aider.conf.yml .codex/config.toml .gemini/settings.json .qwen/settings.json; do ORIG7[$f]="$(sha256sum <"$H7/$f")"; done
( umask 000; bash "$INST" --home "$H7" --agents $ALLAG --apply >/dev/null ); eq "install(A): apply over existing configs exit 0" "0" "$?"
a1="$(tree_sum "$H7")"
( umask 000; bash "$INST" --home "$H7" --agents $ALLAG --apply >/dev/null )
eq "install(A): a second --apply over EXISTING configs is byte-identical" "$a1" "$(tree_sum "$H7")"
eq "install(A): exactly one backup per pre-existing file (no pile-up of api_key copies)" "7" "$(find "$H7" -name '*.label-sync.bak.*' | wc -l)"
eq "install(A): backups are 0600 even under umask 000 and a 0644 original" "600" "$(stat -c %a "$(ls "$H7"/.kimi-code/config.toml.label-sync.bak.* | head -1)")"
eq "install(A): the config keeps its own mode" "644" "$(stat -c %a "$H7/.kimi-code/config.toml")"
bash "$INST" --home "$H7" --agents $ALLAG --apply --remove >/dev/null; eq "install(A): --remove exit 0" "0" "$?"
for f in "${!ORIG7[@]}"; do eq "install(A): --remove restores the ORIGINAL bytes of $f" "${ORIG7[$f]}" "$(sha256sum <"$H7/$f")"; done
bash "$INST" --home "$H7" --agents $ALLAG --apply >/dev/null; bash "$INST" --home "$H7" --agents $ALLAG --apply --remove >/dev/null
eq "install(A): apply/remove cycles keep the backups bounded" "14" "$(find "$H7" -name '*.label-sync.bak.*' | wc -l)"
H8="$ROOT/h8"; mkdir -p "$H8/.kimi-code" "$H8/.gemini"
bash "$INST" --home "$H8" --agents kimi,gemini --apply >/dev/null; bash "$INST" --home "$H8" --agents kimi,gemini --apply --remove >/dev/null
ok "install(A): a config the installer CREATED is gone again after --remove (kimi)" test ! -e "$H8/.kimi-code/config.toml"
ok "install(A): a config the installer CREATED is gone again after --remove (gemini)" test ! -e "$H8/.gemini/settings.json"
# review-2 H: adapters dir with a space works (quoted); with '$' it is refused
SP="$ROOT/dir with space"; mkdir -p "$SP"; cp -a "$AD" "$SP/adapters"
H9="$ROOT/h9"; mkdir -p "$H9"
bash "$SP/adapters/install_adapters.sh" --home "$H9" --agents kimi,crush,gemini,aider,opencode --apply >/dev/null; eq "install(H): adapters dir with a space: exit 0" "0" "$?"
ok "install(H): the kimi hook command is a valid shell command for that path" python3 -c "
import tomllib,shlex,os;d=tomllib.load(open('$H9/.kimi-code/config.toml','rb'));a=shlex.split(d['hooks'][0]['command']);assert a[0]=='bash' and os.path.isfile(a[1]),a"
ok "install(H): the crush hook command is a valid shell command for that path" python3 -c "
import json,shlex,os;d=json.load(open('$H9/.config/crush/crush.json'));a=shlex.split(d['hooks']['PreToolUse'][0]['command']);assert os.path.isfile(a[1]),a"
ok "install(H): the opencode plugin URL resolves (percent-encoded)" python3 -c "
import json,urllib.parse,os;u=json.load(open('$H9/.config/opencode/opencode.json'))['plugin'][0];assert u.startswith('file://') and ' ' not in u and os.path.isfile(urllib.parse.unquote(u[7:])),u"
DL="$ROOT/dol\$lar"; mkdir -p "$DL"; cp -a "$AD" "$DL/adapters"; H10="$ROOT/h10"; mkdir -p "$H10"
bash "$DL/adapters/install_adapters.sh" --home "$H10" --agents kimi --apply >/dev/null 2>&1; eq "install(H): adapters dir with '\$' is refused (exit 2)" "2" "$?"
ok "install(H): ...and nothing was written" test ! -e "$H10/.kimi-code/config.toml"
timeout 10 bash "$INST" --home >/dev/null 2>&1; eq "install(I): trailing --home without a value exits 2 (no hang)" "2" "$?"
timeout 10 bash "$INST" --agents >/dev/null 2>&1; eq "install(I): trailing --agents without a value exits 2 (no hang)" "2" "$?"
# permissions: new files 0600
ok "install: new config created 0600" test "$(stat -c %a "$H/.codex/config.toml")" = 600
eq "install: poisoned real HOME still untouched at the end" "$pb" "$(tree_sum "$POISON")"
fi

echo "---"; echo "test_adapters: $pass passed, $fail failed"
[ "$fail" = 0 ]
