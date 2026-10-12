#!/usr/bin/env bash
# scripts/label-sync/render/tests/test_render.sh
#
# Purpose : Hermetic test suite for the label-sync RENDERERS (statusline,
#           title, shell integration, labelrun, tmux-status, watch-labels).
#           Written FIRST (TDD, §11.4.224): it is RED until the renderers exist.
#           Anti-bluff: every assertion is on a captured output / state delta
#           (a rendered label, an OSC byte sequence, an entity's recorded state,
#           an exit code), never on the mere presence of a file.
# Usage   : bash scripts/label-sync/render/tests/test_render.sh
#           RENDER_DIR=<dir>   test a different copy of the render dir (used by
#                              prove_mutations.sh against mutated scratch copies)
# Inputs  : none; ALL state lives in a temp LABEL_SYNC_DIR (trap-removed).
# Outputs : one PASS/FAIL line per case + a summary.
# Exit    : 0 all cases pass | 1 a case failed | 2 environment (no jq / go).
# Side-effects: temp dir under $TMPDIR; starts + stops its OWN label-busd
#           instances; never touches ~/.claude* or a real state dir.
# Deps    : bash>=5, jq, go (first run builds the label-sync binaries), script(1)
#           optional (tty banner case SKIPs without it).
# Cross-refs: §11.4.182, §11.4.116, §11.4.224, §1.1, docs/label-sync/RENDERERS.md.
# Classification: universal (§11.4.17).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RENDER="$(cd "${RENDER_DIR:-$HERE/..}" && pwd)"
REAL_LS="$(cd "$HERE/../.." && pwd)"           # the real scripts/label-sync
LCTL="$REAL_LS/labelctl.sh"
command -v jq >/dev/null 2>&1 || { echo "test_render: jq missing" >&2; exit 2; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/label_render_t.XXXXXX")" || exit 2
BUSD_PIDS=()
cleanup() {
  local p
  for p in "${BUSD_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done   # only OUR daemons
  rm -rf "$TMPD"
}
trap cleanup EXIT

export LABEL_SYNC_DIR="$TMPD/state"
export LABEL_SYNC_LABELCTL="$LCTL"
export LABEL_SYNC_CMD_MIN_INTERVAL=0
export CLAUDE_CODE_SESSION_ID=""
unset TMUX STY
"$LCTL" --build >/dev/null || { echo "test_render: cannot build label-sync" >&2; exit 2; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $1  -- $2"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want [$2] got [$3]"; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "want substring [$2] in [$3]" ;; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1" "unexpected substring [$2] in [$3]" ;; *) ok "$1" ;; esac; }
now_us() { local t="$EPOCHREALTIME"; echo "${t/./}"; }
wait_for() { # <timeout-s> <cmd...> ; polls every 50ms
  local to="$1"; shift; local n=$((to*20))
  while [ "$n" -gt 0 ]; do "$@" && return 0; sleep 0.05; n=$((n-1)); done; return 1
}
sl() { printf '%s' "$1" | bash "$RENDER/statusline.sh" 2>/dev/null; }   # statusline on stdin JSON
SJ() { printf '{"session_id":"%s","model":{"id":"claude-x","display_name":"X"},"workspace":{"current_dir":"/tmp"},"cwd":"/tmp"}' "$1"; }
ent_field() { "$LCTL" get --id "$1" --json 2>/dev/null | jq -r ".$2 // empty"; }

STUB="$TMPD/stub_labeler.sh"
printf '#!/usr/bin/env bash\necho "(T4/stubbr - claude7 - opus - high)"\n' >"$STUB"; chmod +x "$STUB"
export LABEL_SYNC_LABELER="$STUB"

for f in lib.sh statusline.sh title.sh shell-hook.sh shell-integration.bash shell-integration.zsh shell-integration.fish tmux-status.sh labelrun watch-labels.sh; do
  [ -f "$RENDER/$f" ] && ok "renderer present: $f" || bad "renderer present: $f" "missing $RENDER/$f"
done

# ───────────────────────── A. statusline ─────────────────────────
"$LCTL" switch-alias --alias claude1 --model opus --effort high >/dev/null
"$LCTL" register --id sess1 --kind session --session S1 --track 3 --branch main --alias claude1 --model opus --effort high --follow-active true >/dev/null
BASE_LABEL="(T3/main - claude1 - opus - high)"
export LABEL_SYNC_STATUSLINE_DERIVE=0
"$LCTL" busd --reconcile 200ms >"$TMPD/busd1.log" 2>&1 & BUSD_PIDS+=("$!")
wait_for 5 test -S "$LABEL_SYNC_DIR/bus.sock"
eq "A1 statusline prints this session's live label" "$BASE_LABEL" "$(sl "$(SJ S1)")"
"$LCTL" switch-alias --alias claude2 --model sonnet --effort xhigh >/dev/null
eq "A2 alias switch changes the very next statusline output" "(T3/main - claude2 - sonnet - xhigh)" "$(sl "$(SJ S1)")"
out="$(sl "$(SJ S1)")"; eq "A3 statusline is exactly one line" "1" "$(printf '%s\n' "$out" | wc -l)"
t0="$(now_us)"; for _ in $(seq 20); do sl "$(SJ S1)" >/dev/null; done; t1="$(now_us)"
AVG_SL_MS=$(( (t1-t0)/20/1000 ))
[ "$AVG_SL_MS" -lt 100 ] && ok "A4 statusline latency avg ${AVG_SL_MS}ms < 100ms (20 runs, busd up)" || bad "A4 statusline latency" "avg ${AVG_SL_MS}ms"
echo "METRIC statusline_avg_ms=$AVG_SL_MS"
out="$(sl "$(SJ UNKNOWN_SESSION)")"
has "A5 unknown session => honest ? fields" "(T?/? - ? - ? - ?)" "$out"; has "A5b unknown session => marker" "[no-session]" "$out"
rc=0; out="$(LABEL_SYNC_DIR="$TMPD/nonexistent" bash "$RENDER/statusline.sh" <<<"$(SJ S1)" 2>/dev/null)" || rc=$?
eq "A6 bus/state down => rc 0 (fail soft)" "0" "$rc"; has "A6b state down => ? fields" "?" "$out"; has "A6c state down => marker" "[no-state]" "$out"
rc=0; out="$(printf 'not json at all {{{' | bash "$RENDER/statusline.sh" 2>/dev/null)" || rc=$?
eq "A7 garbage stdin => rc 0" "0" "$rc"; has "A7b garbage stdin => still a ? label" "?" "$out"
rc=0; out="$(bash "$RENDER/statusline.sh" </dev/null 2>/dev/null)" || rc=$?
eq "A7c empty stdin => rc 0" "0" "$rc"
out="$(LABEL_SYNC_DIR="$TMPD/nonexistent" LABEL_SYNC_STATUSLINE_DERIVE=1 LABEL_SYNC_STATUSLINE_CACHE_TTL=0 LABEL_SYNC_CACHE_DIR="$TMPD/cache" bash "$RENDER/statusline.sh" <<<"$(SJ S9)" 2>/dev/null)"
has "A8 state down + derive => labeler label" "(T4/stubbr - claude7 - opus - high)" "$out"; has "A8b derived marker" "[derived" "$out"
# staleness: a session that stops heartbeating goes stale (TTL=1s, own daemon)
kill "${BUSD_PIDS[0]}" 2>/dev/null; wait "${BUSD_PIDS[0]}" 2>/dev/null; BUSD_PIDS=()
export LABEL_SYNC_TTL=1
"$LCTL" register --id sess_stale --kind session --session SSTALE --track 5 --branch b --alias claude2 --model sonnet --effort xhigh --follow-active true >/dev/null
"$LCTL" busd --reconcile 200ms >"$TMPD/busd2.log" 2>&1 & BUSD_PIDS+=("$!")
wait_for 8 bash -c "[[ \"\$(printf '%s' '$(SJ SSTALE)' | bash '$RENDER/statusline.sh' 2>/dev/null)\" == *'[stale]'* ]]"
has "A9 un-heartbeated session shows staleness marker" "[stale]" "$(sl "$(SJ SSTALE)")"
"$LCTL" heartbeat --id sess_stale >/dev/null
wait_for 5 bash -c "[[ \"\$(printf '%s' '$(SJ SSTALE)' | bash '$RENDER/statusline.sh' 2>/dev/null)\" != *'[stale]'* ]]"
hasnt "A9b heartbeat revives (marker gone)" "[stale]" "$(sl "$(SJ SSTALE)")"
unset LABEL_SYNC_TTL
kill "${BUSD_PIDS[0]}" 2>/dev/null; wait "${BUSD_PIDS[0]}" 2>/dev/null; BUSD_PIDS=()

# ───────────────────────── B. title ─────────────────────────
SINK="$TMPD/title.sink"; : >"$SINK"
bash "$RENDER/title.sh" --text "hello" --sink "$SINK"
eq "B1 OSC 0 sequence written" "$(printf '\033]0;hello\007')" "$(cat "$SINK")"
: >"$SINK"; bash "$RENDER/title.sh" --text "$(printf 'a\033]0;evil\007b')" --sink "$SINK"
eq "B2 control chars stripped (no escape injection)" "$(printf '\033]0;a]0;evilb\007')" "$(cat "$SINK")"
rc=0; out="$(bash "$RENDER/title.sh" --text x </dev/null 2>&1)" || rc=$?
eq "B3 non-tty, no sink => rc 0" "0" "$rc"; eq "B3b non-tty, no sink => no output" "" "$out"
rc=0; out="$(TERM=dumb bash "$RENDER/title.sh" --text x --sink "$SINK" 2>&1; echo "rc=$?")"
has "B4 TERM=dumb => rc 0" "rc=0" "$out"
: >"$SINK"; TERM=dumb bash "$RENDER/title.sh" --text x --sink "$SINK"; eq "B4b TERM=dumb => nothing written" "" "$(cat "$SINK")"
: >"$SINK"; TMUX=/tmp/x,1,0 bash "$RENDER/title.sh" --text hi --sink "$SINK" --passthrough
eq "B5 tmux passthrough wraps in DCS" "$(printf '\033Ptmux;\033\033]0;hi\007\033\\')" "$(cat "$SINK")"
: >"$SINK"; TMUX=/tmp/x,1,0 bash "$RENDER/title.sh" --text hi --sink "$SINK"
eq "B5b tmux without --passthrough: plain OSC (tmux sets pane title itself)" "$(printf '\033]0;hi\007')" "$(cat "$SINK")"
: >"$SINK"; bash "$RENDER/title.sh" --session S1 --sink "$SINK"
has "B6 title from snapshot label of a session" "claude2 - sonnet - xhigh" "$(cat "$SINK")"

# ───────────────────────── C. shell integration (bash) ─────────────────────────
export LABEL_SYNC_DIR="$TMPD/state_sh"; rm -rf "$LABEL_SYNC_DIR"
"$LCTL" switch-alias --alias claude7 --model opus --effort high >/dev/null
TSINK="$TMPD/shell.title"; : >"$TSINK"
export LABEL_SYNC_TITLE_SINK="$TSINK"
DRV="$TMPD/drv.sh"
cat >"$DRV" <<DRVEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR LABEL_SYNC_LABELCTL LABEL_SYNC_LABELER LABEL_SYNC_TITLE_SINK LABEL_SYNC_CMD_MIN_INTERVAL
source "$RENDER/shell-integration.bash"
echo "SHELL_ID=\$LABEL_SYNC_SHELL_ID"
__ls_precmd
DRVEOF
SHID="$(bash "$DRV" 2>/dev/null | sed -n 's/^SHELL_ID=//p')"
[ -n "$SHID" ] && ok "C0 integration exports LABEL_SYNC_SHELL_ID" || bad "C0 integration exports LABEL_SYNC_SHELL_ID" "empty"
# That shell exited; its entity must end up done (unregister-on-exit)
wait_for 5 bash -c "[ \"\$('$LCTL' get --id '$SHID' --json 2>/dev/null | jq -r .state)\" = done ]"
eq "C1 shell entity registered then unregistered on shell exit" "done" "$(ent_field "$SHID" state)"
eq "C1b shell entity kind" "shell" "$(ent_field "$SHID" kind)"

# long-lived scripted shell: prompt cycles driven explicitly
SCEN="$TMPD/scen.sh"
cat >"$SCEN" <<SCEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR LABEL_SYNC_LABELCTL LABEL_SYNC_LABELER LABEL_SYNC_TITLE_SINK LABEL_SYNC_CMD_MIN_INTERVAL
source "$RENDER/shell-integration.bash"
echo "SHELL_ID=\$LABEL_SYNC_SHELL_ID"
mycmd() { :; }
__ls_precmd
# wait until our registration lands
for i in \$(seq 100); do "\$LABEL_SYNC_LABELCTL" get --id "\$LABEL_SYNC_SHELL_ID" >/dev/null 2>&1 && break; sleep 0.05; done
__ls_precmd
echo "SZ1=\$(wc -c <"\$LABEL_SYNC_TITLE_SINK")"
__ls_precmd; __ls_precmd
echo "SZ2=\$(wc -c <"\$LABEL_SYNC_TITLE_SINK")"
"\$LABEL_SYNC_LABELCTL" switch-alias --alias claude8 --model sonnet --effort low >/dev/null
__ls_precmd
echo "SZ3=\$(wc -c <"\$LABEL_SYNC_TITLE_SINK")"
# commands with secret-looking args, run under the DEBUG trap (one per prompt cycle)
__ls_precmd
mycmd --token=TOPSECRET123 PASSWORD=hunter2hunter2
sleep 0.5
__ls_precmd
FOO=ENVSECRET999 mycmd arg
sleep 0.5
__ls_precmd
sleep 1.2
echo "DONE"
SCEOF
OUT="$(bash "$SCEN" 2>/dev/null)"
SHID2="$(printf '%s\n' "$OUT" | sed -n 's/^SHELL_ID=//p' | head -1)"
SZ1="$(printf '%s\n' "$OUT" | sed -n 's/^SZ1=//p')"; SZ2="$(printf '%s\n' "$OUT" | sed -n 's/^SZ2=//p')"; SZ3="$(printf '%s\n' "$OUT" | sed -n 's/^SZ3=//p')"
has "C2 title carries the live label (alias claude7)" "claude7" "$(cat "$TSINK")"
eq "C3 unchanged seq => title NOT rewritten (cheap skip)" "$SZ1" "$SZ2"
[ "${SZ3:-0}" -gt "${SZ2:-0}" ] && ok "C4 alias switch => title refreshed on next prompt" || bad "C4 alias switch => title refreshed" "size $SZ2 -> $SZ3"
has "C4b refreshed title carries claude8" "claude8" "$(tail -c 200 "$TSINK")"
CMDS="$("$LCTL" list --json 2>/dev/null | jq -r '.entities | map(select(.kind=="command")) | .[].source' 2>/dev/null)"
has "C5 command entity records argv0 only" "argv0=mycmd" "$CMDS"
ALLSTATE="$(cat "$LABEL_SYNC_DIR"/events.jsonl "$LABEL_SYNC_DIR"/snapshot.json "$LABEL_SYNC_DIR"/fold.json 2>/dev/null)"
hasnt "C6 secret arg never recorded (token)" "TOPSECRET123" "$ALLSTATE"
hasnt "C6b secret arg never recorded (password=)" "hunter2hunter2" "$ALLSTATE"
hasnt "C6c env-prefix secret never recorded" "ENVSECRET999" "$ALLSTATE"
has "C6d a hash is recorded (h=)" ":h=" "$CMDS"
running_cmds() { "$LCTL" list --json 2>/dev/null | jq -r '.entities | map(select(.kind=="command" and .state=="running")) | length' 2>/dev/null; }
wait_for 6 bash -c "[ \"\$('$LCTL' list --json 2>/dev/null | jq -r '.entities | map(select(.kind==\"command\" and .state==\"running\")) | length')\" = 0 ]"
eq "C7 finished commands (and the exit-time in-flight one) are not left running" "0" "$(running_cmds)"

# performance: prompt overhead
PERF="$TMPD/perf.sh"
cat >"$PERF" <<PEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR LABEL_SYNC_LABELCTL LABEL_SYNC_LABELER LABEL_SYNC_TITLE_SINK LABEL_SYNC_CMD_MIN_INTERVAL
source "$RENDER/shell-integration.bash"
for i in \$(seq 100); do "\$LABEL_SYNC_LABELCTL" get --id "\$LABEL_SYNC_SHELL_ID" >/dev/null 2>&1 && break; sleep 0.05; done
__ls_precmd; __ls_precmd
__LS_MIN=999999   # no command registrations while measuring: seq stays unchanged
t0=\${EPOCHREALTIME/./}; for i in \$(seq 300); do __ls_precmd; done; t1=\${EPOCHREALTIME/./}
echo "UNCHANGED_US=\$(( (t1-t0)/300 ))"
tot=0
for i in \$(seq 10); do
  "\$LABEL_SYNC_LABELCTL" heartbeat --id "\$LABEL_SYNC_SHELL_ID" >/dev/null 2>&1   # out-of-band seq change (untimed)
  a=\${EPOCHREALTIME/./}; __ls_precmd; b=\${EPOCHREALTIME/./}; tot=\$((tot + b - a))
done
echo "CHANGED_US=\$(( tot/10 ))"
# DEBUG-trap cost per command
t0=\${EPOCHREALTIME/./}; for i in \$(seq 300); do :; done; t1=\${EPOCHREALTIME/./}; echo "TRAP_US=\$(( (t1-t0)/300 ))"
PEOF
POUT="$(bash "$PERF" 2>/dev/null)"
UNCH="$(printf '%s\n' "$POUT" | sed -n 's/^UNCHANGED_US=//p')"; CHG="$(printf '%s\n' "$POUT" | sed -n 's/^CHANGED_US=//p')"; TRP="$(printf '%s\n' "$POUT" | sed -n 's/^TRAP_US=//p')"
[ -n "$UNCH" ] && [ "$UNCH" -lt 5000 ] && ok "C8 prompt hook, seq unchanged: ${UNCH}us avg < 5000us" || bad "C8 prompt hook unchanged" "${UNCH:-none}us"
[ -n "$CHG" ] && [ "$CHG" -lt 100000 ] && ok "C8b prompt hook after an out-of-band seq change (jq refresh): ${CHG}us avg < 100000us" || bad "C8b changed" "${CHG:-none}us"
[ -n "$TRP" ] && [ "$TRP" -lt 2000 ] && ok "C8c per-command DEBUG-trap loop overhead ${TRP}us < 2000us" || bad "C8c trap" "${TRP:-none}us"
echo "METRIC prompt_unchanged_us=${UNCH:-?} prompt_changed_us=${CHG:-?} debug_loop_us=${TRP:-?}"
# never blocks / fail soft when state is unusable
BADDRV="$TMPD/bad.sh"
cat >"$BADDRV" <<BEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent LABEL_SYNC_TITLE_SINK="$TMPD/bad.sink"
source "$RENDER/shell-integration.bash"
t0=\${EPOCHREALTIME/./}; __ls_precmd; r=\$?; t1=\${EPOCHREALTIME/./}
echo "RC=\$r US=\$((t1-t0))"
BEOF
BOUT="$(bash "$BADDRV" 2>&1)"
has "C9 unusable state: prompt hook rc 0" "RC=0" "$BOUT"
BUS="$(printf '%s' "$BOUT" | sed -n 's/.*US=//p')"
[ -n "$BUS" ] && [ "$BUS" -lt 100000 ] && ok "C9b unusable state: prompt hook returns in ${BUS}us" || bad "C9b" "${BUS:-none}"
# the helper reads command text from STDIN only (never argv)
HOOKSRC="$(cat "$RENDER/shell-hook.sh" "$RENDER/shell-integration.bash" 2>/dev/null)"
hasnt "C10 shell-integration never passes command text in argv (\$BASH_COMMAND not in a command line)" '--cmd "$BASH_COMMAND"' "$HOOKSRC"

# ───────────────────────── D. labelrun ─────────────────────────
export LABEL_SYNC_DIR="$TMPD/state_run"; rm -rf "$LABEL_SYNC_DIR"
"$LCTL" switch-alias --alias claude3 --model haiku --effort low >/dev/null
LR="$RENDER/labelrun"
bash "$LR" -- true; eq "D1 exit 0 propagated" "0" "$?"
bash "$LR" -- bash -c 'exit 7'; eq "D2 exit 7 propagated" "7" "$?"
bash "$LR" -- bash -c 'kill -TERM $$'; eq "D3 child killed by SIGTERM => 143" "143" "$?"
bash "$LR" -- /nonexistent/cmd 2>/dev/null; eq "D4 command not found => 127" "127" "$?"
eq "D5 stdin passed through to the child" "xyz" "$(echo xyz | bash "$LR" -- cat)"
eq "D5b stdout of the child untouched, banner absent when stderr not a tty" "" "$(bash "$LR" -- true 2>&1 >/dev/null)"
# SIGTERM to labelrun itself: forwards, exits 143, cleans up
bash "$LR" --kind flow --name nightly -- sleep 30 &
LRPID=$!
wait_for 5 bash -c "'$LCTL' list --json 2>/dev/null | jq -e '.entities | map(select(.kind==\"flow\" and .state==\"running\")) | length > 0' >/dev/null"
FLOW_ID="$("$LCTL" list --json | jq -r '.entities | map(select(.kind=="flow"))[0].id')"
eq "D6 --kind flow registered" "flow" "$(ent_field "$FLOW_ID" kind)"
has "D6b --name recorded" "name=nightly" "$(ent_field "$FLOW_ID" source)"
CHILD="$(pgrep -P "$LRPID" -x sleep | head -1)"
kill -TERM "$LRPID"; wait "$LRPID"; RC=$?
eq "D7 SIGTERM to labelrun => 143" "143" "$RC"
wait_for 5 bash -c "[ \"\$('$LCTL' get --id '$FLOW_ID' --json | jq -r .state)\" = done ]"
eq "D7b entity marked done after SIGTERM" "done" "$(ent_field "$FLOW_ID" state)"
if [ -n "$CHILD" ]; then kill -0 "$CHILD" 2>/dev/null && bad "D7c child terminated" "sleep $CHILD still alive" || ok "D7c supervised child terminated by forwarded signal"; else bad "D7c" "child pid not found"; fi
# parent linkage: under an integrated shell the entity is a child of it
LABEL_SYNC_SHELL_ID="shell-fake-1" bash "$LR" -- true
PAR="$("$LCTL" list --json | jq -r '.entities | map(select(.kind=="command")) | last | .parent_id')"
eq "D8 entity parent = enclosing shell id" "shell-fake-1" "$PAR"
# fail soft when labelctl unusable
LABEL_SYNC_LABELCTL=/nonexistent bash "$LR" -- bash -c 'exit 5' 2>/dev/null; eq "D9 labelctl unavailable: command still runs, exit propagated" "5" "$?"
# tty banner
if command -v script >/dev/null 2>&1; then
  TTYOUT="$(script -qec "bash '$LR' --name bnr -- true" /dev/null 2>&1 | tr -d '\r')"
  has "D10 banner (label) printed on a tty" "claude3" "$TTYOUT"
else echo "SKIP  D10 tty banner (script(1) not installed)"; fi
# all runs ended in done
LEFT="$("$LCTL" list --json | jq -r '.entities | map(select(.state=="running")) | length')"
eq "D11 no entity left running after all runs" "0" "$LEFT"

# ───────────────────────── E. watch-labels / F. tmux-status ─────────────────────────
export LABEL_SYNC_DIR="$TMPD/state_w"; rm -rf "$LABEL_SYNC_DIR"
"$LCTL" switch-alias --alias claude5 --model opus --effort max >/dev/null
"$LCTL" register --id wa --kind agent --track 1 --branch main --alias claude5 --model opus --effort max --follow-active true --pid $$ >/dev/null
"$LCTL" register --id wb --kind shell --track 2 --branch dev --alias claude6 --model haiku --effort low --follow-active false --pid $$ >/dev/null
W1="$(bash "$RENDER/watch-labels.sh" --once 2>/dev/null)"
has "E1 table lists a label" "(T1/main - claude5 - opus - max)" "$W1"
has "E1b table lists the other-alias label" "(T2/dev - claude6 - haiku - low)" "$W1"
has "E1c alias group header" "claude6" "$(printf '%s' "$W1" | grep -i -E '^(==|#|alias)' )"
hasnt "E1d no screen-clear escape when not a tty" "$(printf '\033[2J')" "$W1"
( sleep 0.4; "$LCTL" switch-alias --alias claude9 --model fable --effort high >/dev/null ) &
W2="$(bash "$RENDER/watch-labels.sh" --interval-ms 50 --iterations 2 --timeout-s 5 2>/dev/null)"
has "E2 watch redraws after a seq change (new alias shown)" "claude9" "$W2"
has "E2b first frame also present" "claude5" "$W2"
"$LCTL" update --id wb --pid "$$" >/dev/null
eq "F1 tmux-status by pane pid prints that shell's label" "(T2/dev - claude6 - haiku - low)" "$(bash "$RENDER/tmux-status.sh" --pane-pid "$$" --kind shell 2>/dev/null)"
eq "F2 tmux-status unknown pid => honest ?" "?" "$(bash "$RENDER/tmux-status.sh" --pane-pid 999999 2>/dev/null)"
"$LCTL" register --id wc --kind agent --track 7 --branch 'x#[fg=red]y' --alias claude5 --model opus --effort max --follow-active false >/dev/null
WC="$(bash "$RENDER/tmux-status.sh" --entity wc 2>/dev/null)"
eq "F3 tmux-status replaces # (tmux format injection) in the label" "(T7/x_[fg=red]y - claude5 - opus - max)" "$WC"

echo "RESULT pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
