#!/usr/bin/env bash
# test_agent.sh — GATE-LOGIC / UNIT-CLASS tests of the installer's headless-agent step.
#
# !! LABEL (§11.4.289): the `claude`, `kimi`, `opencode` and `pi` binaries used here are FAKE test doubles
# !! written into the sandbox (fakebin/). They emit canned output. These tests prove the installer's DECISION
# !! LOGIC (exact argv it builds, env it scrubs, how it reads the stream, budget accounting across follow-ups,
# !! follow-up sequencing, timeouts, exit codes, file modes, post-verify). They are NOT evidence that a real
# !! agent run works. No real LLM call is made: the run uses an EXPLICIT sandbox PATH that holds only the
# !! fakes plus links to core utilities, so a real (paid) agent binary on this host can never be reached.
#
# Everything else is real: real installer, real bare upstream, real clone + submodule add, real post-verify.
# Usage: bash tests/install/test_agent.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=agent_unit_fake
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up" "$SB/fakebin" "$SB/sysbin" "$SB/nobin"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"

# ── explicit sandbox PATH: fakes + links to the core tools the installer, git and these tests need ──
for t in awk basename bash cat chmod cp cut date df dirname du env git grep head id kill ln ls mkdir mktemp mv \
         paste python3 readlink rm rmdir sed sh sha256sum sort stat tail timeout tr touch sleep seq wc \
         uuidgen jq ssh find xargs cmp tee uname expr diff printf true false test; do
  p="$(command -v "$t" 2>/dev/null)"; case "$p" in /*) ln -s "$p" "$SB/sysbin/$t" ;; esac
done
for a in claude kimi opencode pi aider codex gemini qwen cursor-agent amp goose claude-list-accounts claude-providers; do
  [ -e "$SB/sysbin/$a" ] && { echo "sandbox PATH would expose a real agent binary: $a" >&2; exit 2; }
done
SANDBOX_PATH="$SB/fakebin:$SB/sysbin"

cat >"$SB/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
# FAKE claude (TEST DOUBLE, unit/gate-logic only). Records argv (NUL-separated), env flags, cwd.
log="${FAKE_LOG:?}"; n=$(( $(cat "$log.count" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$log.count"
printf '%s\0' "$@" >"$log.argv.$n"
{ printf 'CALL %s\n' "$n"; printf 'ARG %s\n' "$@"; printf 'KEYSET %s\n' "${ANTHROPIC_API_KEY+yes}"
  printf 'BASEURLSET %s\n' "${ANTHROPIC_BASE_URL+yes}"; printf 'AUTHTOKENSET %s\n' "${ANTHROPIC_AUTH_TOKEN+yes}"
  printf 'CONFIGDIRSET %s\n' "${CLAUDE_CONFIG_DIR+yes}"; printf 'BASEURL %s\n' "${ANTHROPIC_BASE_URL:-}"
  printf 'CWD %s\n' "$PWD"; printf 'UMASK %s\n' "$(umask)"; env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/GITVAR \1/p'; } >>"$log"
sid=""; prev=""; for a in "$@"; do case "$prev" in --session-id|--resume) sid="$a" ;; esac; prev="$a"; done
cost=""; [ -n "${FAKE_COST:-}" ] && cost=",\"total_cost_usd\":$FAKE_COST"
mode="${FAKE_MODE:-success}"; if [ "$mode" = followfail ]; then if [ "$n" -ge 2 ]; then mode=iserror; else mode=success; fi; fi
[ "$mode" = escsid ] && sid='\u001b]0;PWNED\u0007\u001b[31mRED\u202e'   # JSON escapes: decoded by the reader
[ "$mode" = escfail ] && sid='x\u001b[2J\u009b31m'   # same for the failure line (U+009B = C1 CSI)
printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$sid"
case "$mode" in
  success)  printf '{"type":"assistant"}\n{"type":"result","subtype":"success","is_error":false,"session_id":"%s"%s}\n' "$sid" "$cost"; exit 0 ;;
  exit1ok)  printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s"}\n' "$sid"; exit 1 ;;
  subtypeerr) printf '{"type":"result","subtype":"error_max_budget_usd","is_error":false,"session_id":"%s"}\n' "$sid"; exit 0 ;;
  noiserr)  printf '{"type":"result","subtype":"success","session_id":"%s"}\n' "$sid"; exit 0 ;;
  iserror)  printf '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"%s"}\n' "$sid"; exit 0 ;;
  noresult) printf '{"type":"assistant"}\n'; exit 0 ;;
  ratelimit) printf '{"type":"assistant","isApiErrorMessage":true,"apiErrorStatus":429}\n{"type":"result","subtype":"success","is_error":true,"session_id":"%s"}\n' "$sid"; exit 0 ;;
  sleep)    sleep 30; exit 0 ;;
  sleepy)   sleep 120 & sp=$!; printf 'AGENTPID %s\nSLEEPPID %s\n' "$$" "$sp" >>"$log"; wait "$sp"; exit 0 ;;
  stubborn) (trap '' INT TERM; exec sleep 120) & sp=$!   # a child that ignores INT/TERM (inherited across exec)
            printf 'AGENTPID %s\nSLEEPPID %s\n' "$$" "$sp" >>"$log"; wait "$sp"; exit 0 ;;
  escsid)   printf '{"type":"result","subtype":"success","is_error":false,"session_id":"\\u001b]0;PWNED\\u0007\\u001b[31mRED\\u202e"}\n'; exit 0 ;;
  escfail)  printf '{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"x\\u001b[2J\\u009b31m"}\n'; exit 0 ;;
  pusher)   git init -q --bare "$log.dest.git" && git remote add dest "$log.dest.git" && git push -q dest HEAD:refs/heads/x 2>>"$log"
            printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s"}\n' "$sid"; exit 0 ;;
  fetcher)  git init -q --bare "$log.dest.git" && git --git-dir="$log.dest.git" fetch -q "$PWD" HEAD:refs/heads/x 2>>"$log" \
              && git remote add dest "$log.dest.git" && git fetch -q dest 2>>"$log"
            printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s"}\n' "$sid"; exit 0 ;;
  vandal)   printf 'vandalised\n' >CLAUDE.md; printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s"}\n' "$sid"; exit 0 ;;
esac
EOF
sed -e 's/FAKE claude/FAKE kimi/' "$SB/fakebin/claude" >"$SB/fakebin/kimi"
for o in opencode pi; do
cat >"$SB/fakebin/$o" <<EOF
#!/usr/bin/env bash
# FAKE $o (TEST DOUBLE, unit/gate-logic only). Exit code from FAKE_RC; prints a line of output.
log="\${FAKE_LOG:?}"; printf '%s\0' "\$@" >"\$log.$o.argv"; printf 'FAKE $o ran\n' >>"\$log.$o.ran"
printf '{"fake":"$o"}\n'; exit "\${FAKE_RC:-0}"
EOF
done
chmod +x "$SB/fakebin/"*
ln -s "$SB/fakebin/claude" "$SB/nobin/claude"   # a PATH with claude but without opencode/pi
cat >"$SB/aliases.sh" <<'EOF'
# TEST FIXTURE alias file: myprov routes through its OWN endpoint (it sets its variables itself);
# bareprov defines nothing, so it must see nothing inherited from the installer's caller
myprov() { ANTHROPIC_BASE_URL="http://ALIAS-OWN-base" CLAUDE_CONFIG_DIR="/nonexistent/alias-config" claude "$@"; }
bareprov() { claude "$@"; }
EOF
export CLAUDE_MULTI_ACCOUNT_ALIASES="$SB/aliases.sh"

i=0
go() { # mode extra-args...  (always under the sandbox PATH)
  local m="$1"; shift; i=$((i+1)); P="$SB/a$i"; new_project "$P"; export FAKE_LOG="$SB/a$i.log" FAKE_MODE="$m"
  OUT="$(cd "$P" && env ${GO_ENV[@]+"${GO_ENV[@]}"} PATH="${GO_PATH:-$SANDBOX_PATH}" bash "$INSTALLER" --non-interactive --run-setup off \
         --upstream-url "$UP" --report-json "$SB/a$i.json" "$@" 2>&1)"; RC=$?
}
args_of() { grep '^ARG ' "$FAKE_LOG" | sed 's/^ARG //'; }
argv_eq() { # call-number expected-args-json — exact argv equality; arg 2 (the prompt) is checked by prefix
  python3 -I - "$FAKE_LOG.argv.$1" "$2" <<'PY'
import json, sys
got = open(sys.argv[1], "rb").read().split(b"\0")[:-1]; got = [g.decode() for g in got]
want = json.loads(sys.argv[2])
if len(got) != len(want): print("    argv length %d != %d: %r" % (len(got), len(want), got[:3] + got[2:])); sys.exit(1)
for k, (g, w) in enumerate(zip(got, want)):
    if w.startswith("PREFIX:"):
        if not g.startswith(w[7:]): print("    arg %d prefix mismatch" % k); sys.exit(1)
    elif g != w: print("    arg %d: got %r want %r" % (k, g, w)); sys.exit(1)
PY
}

echo "# sandbox PATH really hides host agents"
eq "opencode resolves to the fake" "$SB/fakebin/opencode" "$(PATH="$SANDBOX_PATH" command -v opencode)"
eq "claude resolves to the fake" "$SB/fakebin/claude" "$(PATH="$SANDBOX_PATH" command -v claude)"

echo "# success: exact argv, env scrub, session id, report"
export ANTHROPIC_API_KEY="sk-ant-SENTINEL-agent" ANTHROPIC_BASE_URL="http://SENTINEL-base" ANTHROPIC_AUTH_TOKEN="SENTINEL-auth"
go success --agent claude
eq "success exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -15
sid="$(report_field "$SB/a$i.json" session_id)"
check "exact claude argv (nothing added, nothing missing)" argv_eq 1 \
  "[\"-p\",\"PREFIX:TEST FIXTURE PROMPT\",\"--output-format\",\"stream-json\",\"--verbose\",\"--model\",\"sonnet\",\"--effort\",\"medium\",\"--max-budget-usd\",\"2\",\"--permission-mode\",\"acceptEdits\",\"--disallowedTools\",\"WebFetch,WebSearch,Bash(git push *),Bash(git push),Bash(git * push *),Bash(git * push),Bash(*git push*),Bash(*git * push*),Bash(env git*),Bash(command git*),Bash(*send-pack*),Bash(gh *),Bash(glab *),Bash(curl *),Bash(wget *)\",\"--session-id\",\"$sid\"]"
check "ANTHROPIC_API_KEY was scrubbed from the agent env" grep -qx 'KEYSET ' "$FAKE_LOG"
check "ANTHROPIC_BASE_URL was scrubbed for claude" grep -qx 'BASEURLSET ' "$FAKE_LOG"
check "ANTHROPIC_AUTH_TOKEN was scrubbed for claude" grep -qx 'AUTHTOKENSET ' "$FAKE_LOG"
check "agent ran in the project root" grep -qxF "CWD $P" "$FAKE_LOG"
check "agent ran with the user's umask (not the installer's private 0077)" eval '! grep -qx "UMASK 0077" "$FAKE_LOG"'
check "session id is a UUID" eval '[[ "$sid" =~ ^[0-9a-f-]{36}$ ]]'
eq "report agent_status" success "$(report_field "$SB/a$i.json" agent_status)"
check "claude never gets --dangerously-skip-permissions" eval '! tr "\0" "\n" <"$FAKE_LOG.argv.1" | grep -q dangerously'
eq "report agent_permissions for claude" accept-edits+deny-list "$(report_field "$SB/a$i.json" agent_permissions)"
eq "report consent.unrestricted_agent for claude" not-needed "$(report_field "$SB/a$i.json" consent.unrestricted_agent)"
eq "report agent_evidence" result-event "$(report_field "$SB/a$i.json" agent_evidence)"
eq "report limits.budget_usd enforced" enforced "$(report_field "$SB/a$i.json" limits.budget_usd)"
eq "only one agent call when follow-ups are off (default)" 1 "$(cat "$FAKE_LOG.count")"
check "output never shows a secret value" eval '! grep -q SENTINEL <<<"$OUT"'
bd="$(report_field "$SB/a$i.json" backup_dir)"
eq "backup dir mode 700" 700 "$(stat -c %a "$bd")"
eq "agent transcript mode 600" 600 "$(stat -c %a "$bd/agent/run_0.jsonl")"
eq "agent stderr log mode 600" 600 "$(stat -c %a "$bd/agent/run_0.jsonl.stderr")"
eq "agent dir mode 700" 700 "$(stat -c %a "$bd/agent")"

echo "# provider alias: inherited routing/auth variables are scrubbed, then the alias applies its own"
export CLAUDE_CONFIG_DIR="/nonexistent/SENTINEL-config"
go success --agent myprov
eq "provider alias exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -8
check "provider alias: its OWN ANTHROPIC_BASE_URL reached the agent" grep -qx 'BASEURL http://ALIAS-OWN-base' "$FAKE_LOG"
check "provider alias: the inherited base URL did not" eval '! grep -q "SENTINEL-base" "$FAKE_LOG"'
check "provider alias: inherited ANTHROPIC_AUTH_TOKEN removed" grep -qx 'AUTHTOKENSET ' "$FAKE_LOG"
check "provider alias: ANTHROPIC_API_KEY still removed" grep -qx 'KEYSET ' "$FAKE_LOG"
go success --agent bareprov
eq "bare alias exit 0" 0 "$RC"
check "bare alias: inherited ANTHROPIC_BASE_URL removed" grep -qx 'BASEURLSET ' "$FAKE_LOG"
check "bare alias: inherited ANTHROPIC_AUTH_TOKEN removed" grep -qx 'AUTHTOKENSET ' "$FAKE_LOG"
check "bare alias: inherited CLAUDE_CONFIG_DIR removed" grep -qx 'CONFIGDIRSET ' "$FAKE_LOG"
unset CLAUDE_CONFIG_DIR
unset ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN

echo "# provider alias lookup matches the id literally (a '.' in the id is not a regex wildcard, M2)"
printf 'zaiXglm() { claude "$@"; }\n' >>"$SB/aliases.sh"
go success --agent zai.glm
eq "alias zaiXglm does not satisfy --agent zai.glm (exit 3)" 3 "$RC"
check "zai.glm refusal names the missing alias" grep -q 'provider alias zai.glm not found' <<<"$OUT"
printf 'zai.glm() { claude "$@"; }\n' >>"$SB/aliases.sh"
go success --agent zai.glm
eq "control needle: a real zai.glm alias passes the preflight (exit 0)" 0 "$RC"

echo "# success is read from the stream, never from the exit code"
go exit1ok --agent claude; eq "exit 1 + is_error=false result -> success (exit 0)" 0 "$RC"
go iserror --agent claude; eq "exit 0 + is_error=true -> agent failure (exit 4)" 4 "$RC"
go subtypeerr --agent claude; eq "is_error=false but subtype error_max_budget_usd -> agent failure (exit 4)" 4 "$RC"
go noiserr --agent claude; eq "subtype success but no is_error field -> agent failure (exit 4)" 4 "$RC"
go noresult --agent claude; eq "no result event -> agent failure (exit 4)" 4 "$RC"
go ratelimit --agent claude; eq "429 -> agent failure (exit 4)" 4 "$RC"
case "$OUT" in *"rate limit"*) ok "429 reported as rate limit" ;; *) nok "429 reported as rate limit" ;; esac

echo "# model / effort / budget flags pass through (flag=value form too)"
go success --agent claude --model opus --effort=high --max-budget-usd 0.5
a="$(args_of)"; check "model opus" grep -qx opus <<<"$a"; check "effort high" grep -qx high <<<"$a"; check "budget 0.5" grep -qx 0.5 <<<"$a"

echo "# follow-ups + TOTAL budget accounting"
export FAKE_COST=0.8
go success --agent claude --followups on
eq "follow-ups on: exit 0" 0 "$RC"; eq "follow-ups on: 3 calls (main + 2)" 3 "$(cat "$FAKE_LOG.count")"
sid="$(report_field "$SB/a$i.json" session_id)"
check "call 2 = resume with the remaining budget 1.2" argv_eq 2 \
  "[\"-p\",\"PREFIX:TEST FIXTURE FOLLOWUP ONE\",\"--output-format\",\"stream-json\",\"--verbose\",\"--model\",\"sonnet\",\"--effort\",\"medium\",\"--max-budget-usd\",\"1.2\",\"--permission-mode\",\"acceptEdits\",\"--disallowedTools\",\"WebFetch,WebSearch,Bash(git push *),Bash(git push),Bash(git * push *),Bash(git * push),Bash(*git push*),Bash(*git * push*),Bash(env git*),Bash(command git*),Bash(*send-pack*),Bash(gh *),Bash(glab *),Bash(curl *),Bash(wget *)\",\"--resume\",\"$sid\"]"
check "call 3 gets the remaining budget 0.4" argv_eq 3 \
  "[\"-p\",\"PREFIX:TEST FIXTURE FOLLOWUP TWO\",\"--output-format\",\"stream-json\",\"--verbose\",\"--model\",\"sonnet\",\"--effort\",\"medium\",\"--max-budget-usd\",\"0.4\",\"--permission-mode\",\"acceptEdits\",\"--disallowedTools\",\"WebFetch,WebSearch,Bash(git push *),Bash(git push),Bash(git * push *),Bash(git * push),Bash(*git push*),Bash(*git * push*),Bash(env git*),Bash(command git*),Bash(*send-pack*),Bash(gh *),Bash(glab *),Bash(curl *),Bash(wget *)\",\"--resume\",\"$sid\"]"
eq "report budget_spent_usd" 2.4000 "$(report_field "$SB/a$i.json" limits.budget_spent_usd)"
export FAKE_COST=1.5
go success --agent claude --followups on
eq "budget exhausted after follow-up one: exit 0 (setup itself succeeded)" 0 "$RC"
eq "budget exhausted: only 2 calls" 2 "$(cat "$FAKE_LOG.count")"
check "follow-up one got the 0.5 left" eval 'tr "\0" "\n" <"$FAKE_LOG.argv.2" | grep -qx 0.5'
eq "follow-up two recorded as skipped-budget-exhausted" skipped-budget-exhausted \
  "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["followups_run"][1]["status"])' "$SB/a$i.json")"
unset FAKE_COST
go success --agent claude --followups on
eq "cost unknown: 3 calls" 3 "$(cat "$FAKE_LOG.count")"
check "cost unknown: each follow-up gets the full budget again" eval 'tr "\0" "\n" <"$FAKE_LOG.argv.3" | grep -qx 2'
check "cost unknown: the user is told the remaining budget cannot be tracked" grep -q 'cannot be tracked' <<<"$OUT"
eq "cost unknown: report says unknown" unknown "$(report_field "$SB/a$i.json" limits.budget_spent_usd)"
go followfail --agent claude --followups on
eq "first follow-up fails -> exit 4" 4 "$RC"
eq "dependent second follow-up NOT run (2 calls)" 2 "$(cat "$FAKE_LOG.count")"

echo "# timeout"
t0=$(date +%s); go sleep --agent claude --timeout-sec 2; t1=$(date +%s)
eq "timed-out agent -> exit 4" 4 "$RC"; check "timeout honoured (< 20 s)" eval '[ $((t1-t0)) -lt 20 ]'
check "the user is told the agent timed out after 2s" grep -q 'agent timed out after 2s' <<<"$OUT"
go iserror --agent claude; check "a failing (not timed-out) agent is not reported as timed out" eval '! grep -q "timed out" <<<"$OUT"'

echo "# post-verify catches an agent that damaged the inheritance block"
go vandal --agent claude; eq "vandal agent -> verification failed (exit 5)" 5 "$RC"
eq "report verify.overall fail" fail "$(report_field "$SB/a$i.json" verify.overall)"

echo "# kimi: exact argv; limits it cannot honour are refused, not silently ignored"
go success --agent kimi --allow-unrestricted-agent; eq "kimi drivable exit 0" 0 "$RC"
check "exact kimi argv" argv_eq 1 '["-p","PREFIX:TEST FIXTURE PROMPT","--output-format","stream-json"]'
check "log says model/effort/budget NOT enforced for kimi" grep -q 'NOT enforced for kimi' <<<"$OUT"
eq "report limits.budget_usd not-enforced" not-enforced "$(report_field "$SB/a$i.json" limits.budget_usd)"
for fl in "--model opus" "--effort high" "--max-budget-usd 1"; do
  # shellcheck disable=SC2086
  go success --agent kimi --allow-unrestricted-agent $fl; eq "kimi + $fl -> exit 2" 2 "$RC"
  check "kimi + $fl: agent never called" test ! -e "$FAKE_LOG.count"
done
go success --agent kimi --allow-unrestricted-agent --dry-run; check "kimi plan says budget not enforced" grep -q 'NOT enforced for kimi' <<<"$OUT"

echo "# opencode / pi: exit code only -> UNVERIFIED (exit 6), never success"
for o in opencode pi; do
  FAKE_RC=0 go success --agent "$o" --allow-unrestricted-agent
  eq "$o exit 0 + output -> exit 6 (unverified)" 6 "$RC"
  check "$o: the FAKE ran (no real binary)" test -s "$FAKE_LOG.$o.ran"
  eq "$o report agent_status" unverified "$(report_field "$SB/a$i.json" agent_status)"
  eq "$o report status" unverified "$(report_field "$SB/a$i.json" status)"
  eq "$o report agent_evidence" exit-code-only "$(report_field "$SB/a$i.json" agent_evidence)"
  check "$o: told UNVERIFIED" grep -q UNVERIFIED <<<"$OUT"
  FAKE_RC=1 go success --agent "$o" --allow-unrestricted-agent; eq "$o failing -> exit 4" 4 "$RC"
done
echo "# git variables from the caller (e.g. a git hook) never reach the agent (M-1)"
GO_ENV=(GIT_DIR="$SB/victim.git" GIT_WORK_TREE="$SB/victim" GIT_INDEX_FILE="$SB/victim.idx" GIT_EDITOR=evil
        GIT_CONFIG_PARAMETERS="'core.hookspath=/x'" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/x
        GIT_PROXY_COMMAND=evil GIT_ASKPASS=evil GIT_SSH_COMMAND=evil GIT_EXEC_PATH=/x GIT_OBJECT_DIRECTORY=/x)
go success --agent claude; unset GO_ENV
eq "hostile GIT_* in the caller env: exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -5
check "control: the fake records git variables (identity kept)" grep -qx 'GITVAR GIT_AUTHOR_NAME' "$FAKE_LOG"
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_EDITOR GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 \
         GIT_CONFIG_VALUE_0 GIT_PROXY_COMMAND GIT_ASKPASS GIT_SSH_COMMAND GIT_EXEC_PATH GIT_OBJECT_DIRECTORY; do
  check "$v did not reach the agent" eval '! grep -qx "GITVAR $v" "$FAKE_LOG"'
done

echo "# agent text with terminal escapes is printed only after sanitising (M-2)"
go escsid --agent claude
eq "escaped session id: exit 0" 0 "$RC"
check "no raw ESC/BEL reached the terminal" eval '! LC_ALL=C grep -q "$(printf "[\033\007]")" <<<"$OUT"'
check "the malformed session id is reported and replaced" grep -q 'malformed session id' <<<"$OUT"
check "report session_id is the installer's own UUID" eval '[[ "$(report_field "$SB/a$i.json" session_id)" =~ ^[0-9a-f-]{36}$ ]]'
go escfail --agent claude
eq "escaped failure line: exit 4" 4 "$RC"
check "control: the failure line is printed" grep -q 'agent run failed' <<<"$OUT"
check "failure line: no raw ESC reached the terminal" eval '! LC_ALL=C grep -q "$(printf "\033")" <<<"$OUT"'
check "failure line: no C1 CSI (U+009B) reached the terminal" eval '! LC_ALL=C grep -q "$(printf "\302\233")" <<<"$OUT"'

echo "# SIGINT to the installer's process group / SIGTERM to the installer stop the agent promptly (I-3)"
cat >"$SB/sigrun.py" <<'SIGPY'
# TEST HARNESS: starts the installer in its own session with default INT/TERM, waits until the sleepy fake
# agent (TEST DOUBLE) runs, sends the signal, measures how long the installer takes to exit.
import os, signal, subprocess, sys, time
sig, target, log, inst, up = sys.argv[1:6]
def dfl():
    signal.signal(signal.SIGINT, signal.SIG_DFL); signal.signal(signal.SIGTERM, signal.SIG_DFL)
p = subprocess.Popen(["bash", inst, "--non-interactive", "--run-setup", "off", "--upstream-url", up, "--agent", "claude",
                      "--timeout-sec", "600"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                     start_new_session=True, preexec_fn=dfl)
t0 = time.time()
while time.time() - t0 < 120:
    if os.path.exists(log) and "SLEEPPID" in open(log).read():
        break
    if p.poll() is not None:
        break
    time.sleep(0.2)
s = signal.SIGINT if sig == "INT" else signal.SIGTERM
t1 = time.time()
if p.poll() is None:
    if target == "group":
        pg = os.getpgid(p.pid)
        assert pg == p.pid and pg > 1   # our own new session: never pgid <= 1, never a group that is not ours
        os.killpg(pg, s)
    else:
        os.kill(p.pid, s)
try:
    out = p.communicate(timeout=60)[0]
except subprocess.TimeoutExpired:
    p.kill(); out = p.communicate()[0]
print("SECS=%d" % int(time.time() - t1))
print("RC=%s" % p.returncode)
sys.stdout.write(out.decode(errors="replace"))
SIGPY
sig_run() { # SIGNAL TARGET(group|pid) [FAKE_MODE] → RC, SECS, OUT
  i=$((i+1)); P="$SB/a$i"; new_project "$P"; export FAKE_LOG="$SB/a$i.log" FAKE_MODE="${3:-sleepy}"
  OUT="$(cd "$P" && PATH="$SANDBOX_PATH" python3 -I "$SB/sigrun.py" "$1" "$2" "$FAKE_LOG" "$INSTALLER" "$UP")"
  RC="$(sed -n 's/^RC=//p' <<<"$OUT" | head -n 1)"; SECS="$(sed -n 's/^SECS=//p' <<<"$OUT" | head -n 1)"
}
alive() { local p; p="$(sed -n "s/^$1 //p" "$FAKE_LOG" | head -n 1)"; [[ "$p" =~ ^[1-9][0-9]+$ ]] && kill -0 "$p" 2>/dev/null; }
for sp in "INT group sleepy" "TERM pid sleepy" "TERM pid stubborn"; do
  read -r sg tg fm <<<"$sp"
  sig_run "$sg" "$tg" "$fm"
  want=130; [ "$sg" = TERM ] && want=143
  eq "SIG$sg ($tg, $fm) during the agent run: exit $want" "$want" "$RC"
  check "SIG$sg ($tg, $fm): the installer exited within 20 s (took ${SECS}s)" eval '[ -n "$SECS" ] && [ "$SECS" -lt 20 ]'
  check "SIG$sg ($tg, $fm): control: the agent had started" grep -q '^SLEEPPID ' "$FAKE_LOG"
  check "SIG$sg ($tg, $fm): the agent process is gone" eval '! alive AGENTPID'
  check "SIG$sg ($tg, $fm): the agent's child is gone" eval '! alive SLEEPPID'
  # tidy up only if a check above failed: the recorded pid, > 1, and still our fake's `sleep 120`
  sl="$(sed -n 's/^SLEEPPID //p' "$FAKE_LOG" | head -n 1)"
  [[ "$sl" =~ ^[1-9][0-9]+$ ]] && [ "$(tr '\0' ' ' <"/proc/$sl/cmdline" 2>/dev/null)" = "sleep 120 " ] && kill -s KILL "$sl" 2>/dev/null
  check "SIG$sg ($tg, $fm): interrupted message names the backups" grep -q "interrupted by SIG$sg.*backups: /" <<<"$OUT"
  check "SIG$sg ($tg, $fm): no lock left behind" eval '[ ! -e "$P/.git/helix-constitution-install.lock" ]'
done

echo "# a push during the agent run fails the run with exit 5 (I-6); a fetch does not"
go pusher --agent claude
eq "agent pushed: exit 5" 5 "$RC"
check "control: the fake really pushed (an 'update by push' reflog entry)" eval 'git -C "$P" log -g --format=%gs refs/remotes/dest/x -- | grep -q "^update by push"'
check "the push is reported" grep -q 'a push happened during the agent run' <<<"$OUT"
eq "push: report verify.overall = fail" fail "$(report_field "$SB/a$i.json" verify.overall)"
eq "push: nothing was committed" 1 "$(git -C "$P" rev-list --count HEAD)"
go fetcher --agent claude
eq "agent fetched (no push): exit 0" 0 "$RC"
check "control: the fake really fetched (a remote-tracking ref exists)" git -C "$P" rev-parse -q --verify refs/remotes/dest/x
check "fetch: no push reported" eval '! grep -q "a push happened" <<<"$OUT"'
check "the plan names the deny list with the git push forms" eval 'go success --agent claude --dry-run; grep -q "Bash(git \* push \*)" <<<"$OUT"'
echo "# non-claude agents run with their OWN default permissions: explicit consent is required"
for o in kimi opencode pi; do
  go success --agent "$o"
  eq "$o without --allow-unrestricted-agent (non-interactive) -> exit 3" 3 "$RC"
  check "$o refused: agent never called" test ! -e "$FAKE_LOG.count"
  check "$o refused: the fake never ran" test ! -e "$FAKE_LOG.$o.ran"
  check "$o refused: the reason names the flag" grep -q -- '--allow-unrestricted-agent' <<<"$OUT"
  check "$o refused: the reason says it runs with its own default permissions" grep -q 'its own default permissions' <<<"$OUT"
  check "$o refused: nothing was added to the project" test ! -e "$P/submodules/constitution"
  go success --agent "$o" --dry-run
  eq "$o --dry-run without the flag -> exit 3 too" 3 "$RC"
  go success --agent "$o" --allow-unrestricted-agent --dry-run
  eq "$o --dry-run with the flag -> exit 0" 0 "$RC"
  check "$o plan states the agent runs with ITS OWN default permissions" grep -q "runs with ITS OWN default permissions" <<<"$OUT"
  check "$o plan states it can run shell commands" grep -q 'can run shell commands' <<<"$OUT"
  eq "$o dry-run report agent_permissions" agent-default "$(report_field "$SB/a$i.json" agent_permissions)"
  eq "$o dry-run report consent.unrestricted_agent" flag "$(report_field "$SB/a$i.json" consent.unrestricted_agent)"
done
go success --agent kimi --allow-unrestricted-agent
eq "kimi with the flag runs (exit 0)" 0 "$RC"; check "kimi with the flag: the agent was called" test -s "$FAKE_LOG.count"
eq "kimi report agent_permissions" agent-default "$(report_field "$SB/a$i.json" agent_permissions)"
eq "kimi report consent.unrestricted_agent" flag "$(report_field "$SB/a$i.json" consent.unrestricted_agent)"
go success --agent claude --allow-unrestricted-agent --dry-run
eq "claude + the flag: accepted (the flag is irrelevant for claude), exit 0" 0 "$RC"
check "claude plan states acceptEdits and the deny list" grep -q 'acceptEdits.*disallowedTools' <<<"$OUT"
check "claude plan states it never uses --dangerously-skip-permissions" grep -q 'never --dangerously-skip-permissions' <<<"$OUT"
eq "claude + flag: report consent.unrestricted_agent stays not-needed" not-needed "$(report_field "$SB/a$i.json" consent.unrestricted_agent)"
go success --dry-run
eq "no agent: report agent_permissions no-agent" no-agent "$(report_field "$SB/a$i.json" agent_permissions)"

echo "# interactive consent question (default NO); the answers come from a read-only file (prompts go to stderr)"
go_tty() { # answers extra-args...  interactive run, every other question answered by flags
  local ans="$1"; shift; i=$((i+1)); P="$SB/a$i"; new_project "$P"; export FAKE_LOG="$SB/a$i.log" FAKE_MODE=success
  printf '%s' "$ans" >"$SB/tty$i"; chmod 400 "$SB/tty$i"
  OUT="$(cd "$P" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TTY="$SB/tty$i" PATH="$SANDBOX_PATH" bash "$INSTALLER" --run-setup off --upstream-url "$UP" \
         --report-json "$SB/a$i.json" --timeout-sec 30 --followups off --decision-layer off --edit-agent-docs on \
         --register-hooks off --commit off "$@" 2>&1)"; RC=$?
}
go_tty $'\n' --agent kimi --dry-run
eq "interactive kimi, consent answered with Enter (default n) -> exit 3" 3 "$RC"
check "interactive: the question was asked with default n" grep -q 'own default permissions.*\[n\]' <<<"$OUT"
check "interactive: the warning says it can run shell commands in the project" grep -q 'can run shell commands' <<<"$OUT"
check "interactive declined: no plan printed" eval '! grep -q "^step: run agent" <<<"$OUT"'
go_tty $'n\n' --agent opencode
eq "interactive opencode, consent n -> exit 3" 3 "$RC"; check "declined: agent never called" test ! -e "$FAKE_LOG.opencode.ran"
go_tty $'y\n' --agent kimi --dry-run
eq "interactive kimi, consent y -> dry run exit 0" 0 "$RC"
check "interactive y: plan states ITS OWN default permissions" grep -q "runs with ITS OWN default permissions" <<<"$OUT"
eq "interactive y: report consent.unrestricted_agent" interactive "$(report_field "$SB/a$i.json" consent.unrestricted_agent)"
go_tty $'y\n' --agent kimi --dry-run --allow-unrestricted-agent
eq "interactive + the flag: no question needed, exit 0" 0 "$RC"
check "interactive + the flag: the consent question was not asked" eval '! grep -q "own default permissions.*\[n\]" <<<"$OUT"'
go_tty '' --agent claude --model sonnet --effort medium --max-budget-usd 2 --dry-run
eq "interactive claude: no consent question, exit 0" 0 "$RC"
check "interactive claude: no unrestricted-agent question" eval '! grep -q "own default permissions.*\[n\]" <<<"$OUT"'

GO_PATH="$SB/nobin:$SB/sysbin" go success --agent opencode --allow-unrestricted-agent; eq "opencode not installed -> exit 3" 3 "$RC"
go success --agent aider; eq "detect-only agent refused (exit 3)" 3 "$RC"
go success --agent claude99; eq "unknown native alias (no config dir) -> exit 3" 3 "$RC"
finish
