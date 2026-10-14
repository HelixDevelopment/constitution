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
# Deps    : bash>=5, jq, go (first run builds the label-sync binaries), python3
#           (byte-level output checker, control-needled before use), script(1)
#           optional (tty cases SKIP without it).
# Cross-refs: §11.4.182, §11.4.116, §11.4.224, §1.1, docs/label-sync/RENDERERS.md.
# Classification: universal (§11.4.17).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RENDER="$(cd "${RENDER_DIR:-$HERE/..}" && pwd)"
REAL_LS="$(cd "$HERE/../.." && pwd)"           # the real scripts/label-sync
LCTL="$REAL_LS/labelctl.sh"
command -v jq >/dev/null 2>&1 || { echo "test_render: jq missing" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "test_render: python3 missing (byte checker)" >&2; exit 2; }

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
unset TMUX STY CLAUDE_CONFIG_DIR LABEL_SYNC_SHELL_ID LABEL_SYNC_PARENT_ID
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

# Honest stub of the canonical labeler: like track_branch_label.sh, the ALIAS
# comes ONLY from the CLAUDE_CONFIG_DIR basename `.claude-<alias>`, else `?`.
STUB="$TMPD/stub_labeler.sh"
cat >"$STUB" <<'STUBEOF'
#!/usr/bin/env bash
a="?"; c="${CLAUDE_CONFIG_DIR:-}"; c="${c%/}"; c="${c##*/}"
case "$c" in .claude-?*) a="${c#.claude-}" ;; esac
echo "(T4/stubbr - $a - opus - high)"
STUBEOF
chmod +x "$STUB"
export LABEL_SYNC_LABELER="$STUB"
# A labeler that ALWAYS reports an alias (models a labeler deriving one without a
# Claude alias env) — the shell integration must still NOT pin on it.
ALWAYS7="$TMPD/always7_labeler.sh"
printf '#!/usr/bin/env bash\necho "(T4/stubbr - claude7 - opus - high)"\n' >"$ALWAYS7"; chmod +x "$ALWAYS7"
mkdir -p "$TMPD/cfg/.claude-claude7" "$TMPD/cfg/.claude-claude5"
ent_bool() { "$LCTL" get --id "$1" --json 2>/dev/null | jq -r ".$2"; }

# Byte-level output checker (python3 -I, reads a file): counts C0 (except LF when
# --lines), DEL, C1, bidi controls and invalid UTF-8. --title strips exactly one
# leading ESC]0; and one trailing BEL first. --cr drops CR (pty output).
CHK="$TMPD/chk.py"
cat >"$CHK" <<'CHKEOF'
import sys
a = sys.argv[1:]; f = a[-1]; b = open(f, 'rb').read()
if '--cr' in a: b = b.replace(b'\r', b'')
if '--title' in a:
    if not (b.startswith(b'\x1b]0;') and b.endswith(b'\x07')): print('BADFRAME'); sys.exit(0)
    b = b[4:-1]
bad = 0
try:
    t = b.decode('utf-8')
except UnicodeDecodeError:
    print('INVALID_UTF8'); sys.exit(0)
for ch in t:
    o = ord(ch)
    if ch == '\n' and '--lines' in a: continue
    if o < 0x20 or o == 0x7f or 0x80 <= o <= 0x9f or o in (0x200e, 0x200f, 0x061c) or 0x202a <= o <= 0x202e or 0x2066 <= o <= 0x2069:
        bad += 1
print(bad)
CHKEOF
chk() { python3 -I "$CHK" "$@" 2>/dev/null; }

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
out="$(CLAUDE_CONFIG_DIR="$TMPD/cfg/.claude-claude7" LABEL_SYNC_DIR="$TMPD/nonexistent" LABEL_SYNC_STATUSLINE_DERIVE=1 LABEL_SYNC_STATUSLINE_CACHE_TTL=0 LABEL_SYNC_CACHE_DIR="$TMPD/cache" bash "$RENDER/statusline.sh" <<<"$(SJ S9)" 2>/dev/null)"
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
# wait until our registration is PUBLISHED: the seq file (written LAST, after
# snapshot.json) has moved past the seq the first prompt saw AND the snapshot
# carries our label. Waiting on \`labelctl get\` alone raced (review-2 C2): get
# reads the log-complete state, which is visible BEFORE seq is rewritten, so the
# next prompt could still read the old seq and skip the title refresh.
for i in \$(seq 200); do
  { read -r __s <"\$LABEL_SYNC_DIR/seq"; } 2>/dev/null || __s=""
  [ -n "\$__s" ] && [ "\$__s" != "\$__ls_seen_seq" ] && [ -n "\$(ls_entity_label "\$LABEL_SYNC_SHELL_ID")" ] && break
  [ -s "\$LABEL_SYNC_TITLE_SINK" ] && break     # the first prompt already rendered it
  sleep 0.05
done
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
hasnt "C6d no digest of the command text is recorded (digest removed, finding 7)" ":h=" "$CMDS"
eq "C12 plain terminal (no Claude alias env) registers following the active alias" "true" "$(ent_bool "$SHID2" follow_active)"
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
# median of 3 samples (§11.4.50): one fork can stall >100 ms on a loaded host
BUS="$( { printf '%s\n' "$BOUT"; bash "$BADDRV" 2>&1; bash "$BADDRV" 2>&1; } | sed -n 's/.*US=//p' | sort -n | sed -n 2p)"
[ -n "$BUS" ] && [ "$BUS" -lt 100000 ] && ok "C9b unusable state: prompt hook returns in ${BUS}us" || bad "C9b" "${BUS:-none}"
# the helper reads command text from STDIN only (never argv)
HOOKSRC="$(cat "$RENDER/shell-hook.sh" "$RENDER/shell-integration.bash" 2>/dev/null)"
hasnt "C10 shell-integration never passes command text in argv (\$BASH_COMMAND not in a command line)" '--cmd "$BASH_COMMAND"' "$HOOKSRC"
hasnt "C10b command text is never piped to the helper either" '| $__LS_SETSID "$__LS_HOOK" cmd-start' "$HOOKSRC"
# C11: a REAL Claude alias env (CLAUDE_CONFIG_DIR=.../.claude-claude5) pins the shell
BIND="$TMPD/bind.sh"
cat >"$BIND" <<BEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR LABEL_SYNC_LABELCTL LABEL_SYNC_LABELER LABEL_SYNC_TITLE_SINK LABEL_SYNC_CMD_MIN_INTERVAL
source "$RENDER/shell-integration.bash"
echo "SHELL_ID=\$LABEL_SYNC_SHELL_ID"
for i in \$(seq 100); do "\$LABEL_SYNC_LABELCTL" get --id "\$LABEL_SYNC_SHELL_ID" >/dev/null 2>&1 && break; sleep 0.05; done
trap - EXIT
BEOF
SH5="$(CLAUDE_CONFIG_DIR="$TMPD/cfg/.claude-claude5" bash "$BIND" 2>/dev/null | sed -n 's/^SHELL_ID=//p')"
"$LCTL" switch-alias --alias claude9 --model haiku --effort low >/dev/null
eq "C11 real Claude alias env pins the shell (follow_active=false)" "false" "$(ent_bool "$SH5" follow_active)"
has "C11b pinned shell keeps its own alias across switch-alias" "claude5" "$("$LCTL" label "$SH5" 2>/dev/null)"
SH7="$(LABEL_SYNC_LABELER="$ALWAYS7" bash "$BIND" 2>/dev/null | sed -n 's/^SHELL_ID=//p')"
"$LCTL" switch-alias --alias claude8 --model sonnet --effort low >/dev/null
eq "C13 labeler alias WITHOUT a Claude alias env does not pin (follow_active=true)" "true" "$(ent_bool "$SH7" follow_active)"
has "C13b that shell follows switch-alias" "claude8" "$("$LCTL" label "$SH7" 2>/dev/null)"
HSTID="$(HOSTNAME='evil_host name' bash -c 'source "'"$RENDER"'/shell-integration.bash"; echo "$LABEL_SYNC_SHELL_ID"; trap - EXIT' 2>/dev/null)"
[[ $HSTID =~ ^[A-Za-z0-9._:@/-]{1,160}$ ]] && ok "C14 shell id matches the CONTRACT id grammar even for a hostname with _ and space ($HSTID)" || bad "C14 shell id grammar" "$HSTID"

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
# D12: SIGINT to labelrun ends the child. labelrun is started the way an
# interactive shell starts a job (INT/QUIT at their defaults — a non-interactive
# `&` would hand labelrun SIGINT already ignored, which no bash can trap); the
# point under test is that labelrun's OWN `&` child must not inherit SIG_IGN.
env --default-signal=INT,QUIT bash "$LR" --name intr -- sleep 4 &
LRP=$!
wait_for 5 pgrep -P "$LRP" >/dev/null
t0="$(now_us)"; kill -INT "$LRP"; wait "$LRP"; RC=$?; t1="$(now_us)"
DT_MS=$(( (t1 - t0) / 1000 ))
eq "D12 SIGINT to labelrun => child ends, exit 130" "130" "$RC"
[ "$DT_MS" -lt 1500 ] && ok "D12b SIGINT handled in ${DT_MS}ms < 1500ms (child did not ignore it)" || bad "D12b SIGINT latency" "${DT_MS}ms"
# D13: a terminal Ctrl-C reaches the child exactly ONCE (no forwarded duplicate)
CNT="$TMPD/intcount.sh"
cat >"$CNT" <<'CEOF'
#!/usr/bin/env bash
n=0; trap 'n=$((n+1))' INT
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do sleep 0.1 || :; done
echo "INTS=$n"
CEOF
if command -v script >/dev/null 2>&1; then
  TTYO="$( { sleep 1; printf '\003'; sleep 3; } | script -qec "bash '$LR' -- bash '$CNT'" /dev/null 2>&1 | tr -d '\r')"
  has "D13 tty Ctrl-C delivered to the child exactly once (trap active: INT not ignored)" "INTS=1" "$TTYO"
  # D13b: the decision itself. Two near-simultaneous SIGINTs coalesce, so D13
  # cannot see a duplicate; instead send `kill -INT <labelrun>` (NOT via the tty)
  # while the child sits in the terminal's foreground group: labelrun must NOT
  # forward it (the documented rule), so the child counts 0.
  PIDF="$TMPD/d13b.pid"; rm -f "$PIDF"
  CNT2="$TMPD/intcount2.sh"
  printf '#!/usr/bin/env bash\necho "$PPID" >"%s"\nn=0; trap '"'"'n=$((n+1))'"'"' INT\nfor _ in $(seq 25); do sleep 0.1 || :; done\necho "INTS=$n"\n' "$PIDF" >"$CNT2"
  ( wait_for 5 test -s "$PIDF"; lp="$(cat "$PIDF")"
    case "$lp" in ''|*[!0-9]*) ;; *) [ "$lp" -gt 1 ] && grep -qa labelrun "/proc/$lp/cmdline" && kill -INT "$lp" ;; esac ) &
  KP=$!
  TTYO2="$( { sleep 4; } | script -qec "bash '$LR' -- bash '$CNT2'" /dev/null 2>&1 | tr -d '\r')"
  wait "$KP" 2>/dev/null
  has "D13b external SIGINT to labelrun is not duplicated onto a tty-foreground child" "INTS=0" "$TTYO2"
else echo "SKIP  D13 tty Ctrl-C (script(1) not installed)"; fi
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

# ───────────────────────── G. review findings: sanitising, secrets, traps ─────────────────────────
# G0: control needles for the byte checker itself (§11.4.273) — it must SEE a C1
# byte, a bidi control, an ESC and invalid UTF-8, and must pass clean text.
printf 'clean é 日\n' >"$TMPD/n_good"; printf 'a\xc2\x9db' >"$TMPD/n_c1"; printf 'a\xe2\x80\xaeb' >"$TMPD/n_bidi"
printf 'a\033b' >"$TMPD/n_esc"; printf 'a\xffb' >"$TMPD/n_inv"
eq "G0 checker: clean text => 0" "0" "$(chk --lines "$TMPD/n_good")"
eq "G0b checker sees C1 (c2 9d)" "1" "$(chk "$TMPD/n_c1")"; eq "G0c checker sees bidi" "1" "$(chk "$TMPD/n_bidi")"
eq "G0d checker sees ESC" "1" "$(chk "$TMPD/n_esc")"; eq "G0e checker sees invalid UTF-8" "INVALID_UTF8" "$(chk "$TMPD/n_inv")"

# G1: the shared sanitiser, exact bytes, under BOTH locales
P=$'MARK\e]0;evil\aX\e]52;c;ZXZpbA==\a\e[31m\xc2\x9d\xc2\x9c\xc2\x80\xe2\x80\xaeY\xe2\x81\xa6\xe2\x80\x8fZ\x7f\xff\xfe\xc3END\xc3\xa9\xe6\x97\xa5\xc2\e\x9d\xc0\xaf\xed\xa0\x80OK'
E=$'MARK]0;evilX]52;c;ZXZpbA==[31mYZEND\xc3\xa9\xe6\x97\xa5OK'
for loc in C C.utf8; do
  got="$(LC_ALL=$loc bash -c '. "$1/lib.sh"; ls_sanitize "$2"' _ "$RENDER" "$P" | od -An -tx1 | tr -d ' \n')"
  eq "G1 [$loc] ls_sanitize strips C0/DEL/C1/bidi/invalid UTF-8, never joins bytes into a C1" "$(printf '%s' "$E" | od -An -tx1 | tr -d ' \n')" "$got"
  n="$(LC_ALL=$loc bash -c '. "$1/lib.sh"; x="$(printf "a%.0s" $(seq 5000))"; ls_sanitize "$x" | wc -c' _ "$RENDER")"
  eq "G1b [$loc] huge input capped at 512 bytes" "512" "$n"
  LC_ALL=$loc bash -c '. "$1/lib.sh"; x=""; for i in $(seq 300); do x+=$'"'"'\xc3\xa9'"'"'; done; ls_sanitize "$x" 511' _ "$RENDER" >"$TMPD/g1c"
  eq "G1c [$loc] cap lands on a character boundary (valid UTF-8, 510 bytes)" "0 510" "$(chk "$TMPD/g1c") $(wc -c <"$TMPD/g1c")"
done

# Hostile snapshot (defence in depth for old logs: the store sanitises on write,
# so it is hand-written here). Label/alias carry ESC ]0;, ESC ]52;, CSI, C1, bidi, DEL, a NUL and 100k chars.
HD="$TMPD/state_hostile"; mkdir -p "$HD"
python3 -I - "$HD" <<'PYJ'
import json, sys
d = sys.argv[1]
P = "MARK\u001b]0;evil\u0007X\u001b]52;c;ZXZpbA==\u0007\u001b[31m\u009d\u009c\u0080‮Y⁦‏Z\u007f\u0000END\nFORGED-ROW" + "W" * 100000
e = {"id": "hostile1", "kind": "session", "session_id": "SH", "pid": 424242, "alias": P, "label": P, "state": "running"}
json.dump({"seq": 7, "active": {"alias": P, "model": "m\u001bx", "effort": "e"}, "entities": [e]}, open(d + "/snapshot.json", "w"))
open(d + "/seq", "w").write("7\n")
PYJ
HOST_LC="$TMPD/hostile_labeler.sh"
printf '#!/usr/bin/env bash\nprintf "(T4/MARK\\033]0;x\\007\\302\\235\\342\\200\\256\\377\\376z - a - m - e)\\n"\n' >"$HOST_LC"; chmod +x "$HOST_LC"
for loc in C C.utf8; do
  LC_ALL=$loc LABEL_SYNC_DIR="$HD" bash "$RENDER/statusline.sh" <<<'{"session_id":"SH"}' >"$TMPD/g_sl" 2>/dev/null
  eq "G2 [$loc] statusline: hostile snapshot label => no control/C1/bidi/invalid byte" "0" "$(chk --lines "$TMPD/g_sl")"
  has "G2b [$loc] statusline still shows the label text" "MARK" "$(cat "$TMPD/g_sl")"
  [ "$(wc -c <"$TMPD/g_sl")" -le 513 ] && ok "G2c [$loc] statusline output capped ($(wc -c <"$TMPD/g_sl") bytes)" || bad "G2c [$loc] cap" "$(wc -c <"$TMPD/g_sl")"
  LC_ALL=$loc LABEL_SYNC_DIR="$TMPD/nonexistent" LABEL_SYNC_STATUSLINE_DERIVE=1 LABEL_SYNC_STATUSLINE_CACHE_TTL=0 LABEL_SYNC_LABELER="$HOST_LC" bash "$RENDER/statusline.sh" <<<'{"session_id":"SD"}' >"$TMPD/g_sld" 2>/dev/null
  eq "G3 [$loc] statusline derived path: hostile labeler => clean" "0" "$(chk --lines "$TMPD/g_sld")"
  has "G3b [$loc] derived label still shown" "MARK" "$(cat "$TMPD/g_sld")"
  : >"$TMPD/g_t"; LC_ALL=$loc LABEL_SYNC_DIR="$HD" bash "$RENDER/title.sh" --entity hostile1 --sink "$TMPD/g_t"
  eq "G4 [$loc] title.sh --entity: payload between ESC]0; and BEL is clean" "0" "$(chk --title "$TMPD/g_t")"
  has "G4b [$loc] title carries the label text" "MARK" "$(cat "$TMPD/g_t")"
  : >"$TMPD/g_t2"; LC_ALL=$loc bash "$RENDER/title.sh" --text "$P" --sink "$TMPD/g_t2"
  eq "G4c [$loc] title.sh --text with raw C1/bidi/invalid bytes => clean" "0" "$(chk --title "$TMPD/g_t2")"
  LC_ALL=$loc LABEL_SYNC_DIR="$HD" bash "$RENDER/tmux-status.sh" --entity hostile1 >"$TMPD/g_tm" 2>/dev/null
  eq "G5 [$loc] tmux-status --entity => clean" "0" "$(chk --lines "$TMPD/g_tm")"; has "G5b [$loc] tmux label shown" "MARK" "$(cat "$TMPD/g_tm")"
  LC_ALL=$loc LABEL_SYNC_DIR="$HD" bash "$RENDER/tmux-status.sh" --active >"$TMPD/g_tma" 2>/dev/null
  eq "G5c [$loc] tmux-status --active => clean" "0" "$(chk --lines "$TMPD/g_tma")"
  LC_ALL=$loc LABEL_SYNC_DIR="$HD" bash "$RENDER/watch-labels.sh" --once >"$TMPD/g_w" 2>/dev/null
  eq "G6 [$loc] watch-labels => clean" "0" "$(chk --lines "$TMPD/g_w")"; has "G6b [$loc] watch shows the row" "hostile1" "$(cat "$TMPD/g_w")"
  hasnt "G6c [$loc] an embedded newline cannot forge a table row" $'\nFORGED-ROW' "$(cat "$TMPD/g_w")"
  GSH="$TMPD/g_shell.sh"
  cat >"$GSH" <<GEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR="$HD" LABEL_SYNC_LABELCTL=/nonexistent LABEL_SYNC_TITLE_SINK="$TMPD/g_st"
source "$RENDER/shell-integration.bash"
LABEL_SYNC_SHELL_ID=hostile1
__ls_precmd
printf '%s' "\$__LS_SEG" >"$TMPD/g_seg"
GEOF
  : >"$TMPD/g_st"; LC_ALL=$loc bash "$GSH" 2>/dev/null
  eq "G7 [$loc] shell integration title => clean" "0" "$(chk --title "$TMPD/g_st")"
  eq "G7b [$loc] PS1 segment (__LS_SEG) => clean" "0" "$(chk "$TMPD/g_seg")"; has "G7c [$loc] segment shows label" "MARK" "$(cat "$TMPD/g_seg")"
  LC_ALL=$loc LABEL_SYNC_DEBUG=1 LABEL_SYNC_DIR="$TMPD/g_hook" bash "$RENDER/shell-hook.sh" "$(printf 'op\033]0;evil\007\302\235x')" --id x 2>"$TMPD/g_hk" >/dev/null
  eq "G8 [$loc] shell-hook diagnostics => clean" "0" "$(chk --lines "$TMPD/g_hk")"; has "G8b [$loc] diagnostic still printed" "unknown op" "$(cat "$TMPD/g_hk")"
done
if command -v script >/dev/null 2>&1; then
  LABEL_SYNC_DIR="$TMPD/state_run" script -qec "bash '$LR' --name \"\$(printf 'bn\033]0;evil\007\302\235')\" -- true" /dev/null 2>&1 | grep -a '^labelrun:' >"$TMPD/g_bn"
  eq "G9 labelrun tty banner => clean" "0" "$(chk --cr --lines "$TMPD/g_bn")"; has "G9b banner printed" "labelrun:" "$(cat "$TMPD/g_bn")"
else echo "SKIP  G9 labelrun banner (script(1) not installed)"; fi

# G10: argv0 recorded only when the shell resolves it; FAKE tokens typed as the
# first word (unresolvable, or resolvable-but-token-shaped) never reach state.
export LABEL_SYNC_DIR="$TMPD/state_sec"; rm -rf "$LABEL_SYNC_DIR"
SEC="$TMPD/sec.sh"
cat >"$SEC" <<'SEOF'
#!/usr/bin/env bash
export LABEL_SYNC_DIR LABEL_SYNC_LABELCTL LABEL_SYNC_LABELER LABEL_SYNC_CMD_MIN_INTERVAL
source "$1/shell-integration.bash"
for i in $(seq 100); do "$LABEL_SYNC_LABELCTL" get --id "$LABEL_SYNC_SHELL_ID" >/dev/null 2>&1 && break; sleep 0.05; done
ghp_FAKEfnFAKEfnFAKEfnFAKE01234() { :; }
knowncmd() { :; }
__ls_precmd; hunter2hunter2 2>/dev/null
__ls_precmd; ghp_FAKEFAKEFAKEFAKEFAKEFAKE0000000000 2>/dev/null
__ls_precmd; AKIAFAKEFAKEFAKEFAKE 2>/dev/null
__ls_precmd; glpat-FAKEFAKEFAKEFAKEFAKE 2>/dev/null
__ls_precmd; xoxb-FAKE-0000-FAKEFAKE 2>/dev/null
__ls_precmd; sk-FAKEFAKEFAKEFAKEFAKEFAKE 2>/dev/null
__ls_precmd; 0123456789abcdef0123456789abcdef 2>/dev/null
__ls_precmd; ghp_FAKEfnFAKEfnFAKEfnFAKE01234
__ls_precmd; knowncmd
__ls_precmd
sleep 1.5
SEOF
bash "$SEC" "$RENDER" 2>/dev/null
SECSTATE="$(cat "$LABEL_SYNC_DIR"/events.jsonl "$LABEL_SYNC_DIR"/snapshot.json "$LABEL_SYNC_DIR"/fold.json "$LABEL_SYNC_DIR"/base.json 2>/dev/null)"
for tok in hunter2hunter2 ghp_FAKEFAKEFAKE AKIAFAKEFAKE glpat-FAKEFAKE xoxb-FAKE sk-FAKEFAKE 0123456789abcdef0123 ghp_FAKEfnFAKEfn; do
  hasnt "G10 first-word FAKE secret '$tok' never recorded" "$tok" "$SECSTATE"
done
SECSRC="$("$LCTL" list --json 2>/dev/null | jq -r '.entities | map(select(.kind=="command")) | .[].source')"
has "G10b positive control: a resolvable function IS recorded" "argv0=knowncmd" "$SECSRC"
eq "G10c every secret-shaped first word recorded as argv0=?" "8" "$(printf '%s\n' "$SECSRC" | grep -c 'argv0=?$')"
for tok in ghp_FAKEFAKEFAKEFAKEFAKE00 glpat-FAKEFAKEFAKE AKIAFAKEFAKEFAKEFAKE xoxp-FAKE sk-FAKEFAKEFAKE QUJDREVGR0hJSktMTU5PUFFSU1RVVldY1; do
  bash "$RENDER/shell-hook.sh" cmd-start --id "bk-$RANDOM" --parent x --pid $$ --cwd /tmp --argv0 "$tok"
done
bash "$RENDER/shell-hook.sh" cmd-start --id bk-ls --parent x --pid $$ --cwd /tmp --argv0 /usr/bin/ls
BKS="$("$LCTL" list --json 2>/dev/null | jq -r '.entities | map(select(.id|startswith("bk-"))) | .[].source')"
eq "G11 shell-hook backstop redacts token-shaped argv0 even if passed (6 of 6)" "6" "$(printf '%s\n' "$BKS" | grep -c 'argv0=?$')"
has "G11b backstop positive control: /usr/bin/ls recorded as basename" "argv0=ls" "$BKS"

# G20-G23: trap/PROMPT_COMMAND hygiene, set -e / set -u safety
TR="$TMPD/traps.sh"
cat >"$TR" <<'TEOF'
#!/usr/bin/env bash
export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent LABEL_SYNC_CMD_MIN_INTERVAL=0
F="$2"
PROMPT_COMMAND='echo PREVPC >>"$F"'
source "$1/shell-integration.bash"
true lastarg1; echo "U1=$_"
true lastarg2; echo "U2=$_"
__ls_precmd
true lastarg3; echo "U3=$_"
eval "$PROMPT_COMMAND"
trap - EXIT
TEOF
: >"$TMPD/tr_f"; TRO="$(bash "$TR" "$RENDER" "$TMPD/tr_f" 2>/dev/null)"
has "G20 DEBUG trap preserves \$_ (first command of a cycle)" "U1=lastarg1" "$TRO"
has "G20b DEBUG trap preserves \$_ (later command, early-return path)" "U2=lastarg2" "$TRO"
has "G20c DEBUG trap preserves \$_ after a prompt cycle" "U3=lastarg3" "$TRO"
# G22: a pre-existing DEBUG trap is chained. bash hides it inside `source`
# unless `set -T` (script case), so an INTERACTIVE shell installs ours at the
# first prompt (G22b, driven on a pty). Only lines written AFTER sourcing count.
: >"$TMPD/tr_d"
bash -c 'set -T; export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent; F="$2"; trap "echo PREVDBG >>\"\$F\"" DEBUG; source "$1/shell-integration.bash"; : >"$F"; true a; true b; trap - EXIT' _ "$RENDER" "$TMPD/tr_d" 2>/dev/null
has "G22 script (set -T): a pre-existing DEBUG trap still runs (chained, not dropped)" "PREVDBG" "$(cat "$TMPD/tr_d")"
if command -v script >/dev/null 2>&1; then
  : >"$TMPD/tr_i"
  printf 'export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent\ntrap '"'"'echo PREVDBG >>"%s"'"'"' DEBUG\nsource "%s/shell-integration.bash"\n: >"%s"\nPS1="P> "\n' "$TMPD/tr_i" "$RENDER" "$TMPD/tr_i" >"$TMPD/irc"
  IOUT="$(printf 'true lastarg9\ntrap -p DEBUG\nexit\n' | script -qec "bash --noprofile --rcfile '$TMPD/irc' -i" /dev/null 2>&1 | tr -d '\r')"
  has "G22b interactive bash: a DEBUG trap set before sourcing still runs after the first prompt" "PREVDBG" "$(cat "$TMPD/tr_i")"
  has "G22c interactive bash: our hook is installed too (chained first)" "__ls_debug" "$IOUT"
else echo "SKIP  G22b/G22c interactive DEBUG chaining (script(1) not installed)"; fi
has "G23 a pre-existing PROMPT_COMMAND still runs (chained, not clobbered)" "PREVPC" "$(cat "$TMPD/tr_f")"
TA="$(bash -c 'PROMPT_COMMAND=(prevpc_a); source "'"$RENDER"'/shell-integration.bash"; echo "${PROMPT_COMMAND[*]}"; trap - EXIT' 2>/dev/null)"
eq "G23b array PROMPT_COMMAND keeps the previous element and appends ours" "prevpc_a __ls_precmd" "$TA"
SE="$(bash -c 'set -eu; export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent; source "'"$RENDER"'/shell-integration.bash"; __ls_precmd; true x; false || :; __ls_precmd; echo SURVIVED; trap - EXIT' 2>/dev/null; echo "rc=$?")"
has "G21 set -eu shell, missing seq file: hooks never end the shell" "SURVIVED" "$SE"; has "G21b set -eu shell exits 0" "rc=0" "$SE"
SE2="$(bash -c 'set -eu; export LABEL_SYNC_DIR="'"$HD"'" LABEL_SYNC_LABELCTL=/nonexistent LABEL_SYNC_SHELL_ID=x; source "'"$RENDER"'/shell-integration.bash"; LABEL_SYNC_SHELL_ID=no-such-entity; __ls_precmd; echo SURVIVED2; trap - EXIT' 2>/dev/null)"
has "G21c set -eu shell, label lookup finds nothing: hooks never end the shell" "SURVIVED2" "$SE2"

# G30: no salt / nothing secret exported to children
SALT="$(bash -c 'export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent; source "'"$RENDER"'/shell-integration.bash"; bash -c "echo \${LABEL_SYNC_SALT-unset}"; trap - EXIT' 2>/dev/null)"
eq "G30 no LABEL_SYNC_SALT in any child's environment" "unset" "$SALT"
hasnt "G30b no salt/digest code left in the integrations" "LABEL_SYNC_SALT" "$(cat "$RENDER"/shell-integration.* "$RENDER/shell-hook.sh")"

# ───────────────────────── H. second review (findings 8, 11) ─────────────────────────
# H1 (finding 11 / reviewer mutant B4): the statusline prefers the SESSION entity
# of its session_id over an EARLIER-sorting agent of the same session.
"$LCTL" register --id h_agent --kind agent --session S11 --track 9 --branch hb --alias claude3 --model haiku --effort low --follow-active false >/dev/null
"$LCTL" register --id h_sess --kind session --session S11 --track 9 --branch hb --alias claude4 --model opus --effort max --follow-active false >/dev/null
eq "H1 statusline shows the session entity, not an earlier agent of that session" "(T9/hb - claude4 - opus - max)" "$(LABEL_SYNC_STATUSLINE_DERIVE=0 sl "$(SJ S11)")"
eq "H1b control: the agent really sorts first in the snapshot" "h_agent" "$(jq -r '[.entities[]|select(.session_id=="S11")][0].id' "$LABEL_SYNC_DIR/snapshot.json")"
# H2-H4 (finding 8): a shell's track/branch/cwd follow a `git checkout` and a `cd`.
REALLAB="$(cd "$REAL_LS/../multitrack" && pwd)/track_branch_label.sh"   # the real labeler (RENDER may be a scratch copy)
HR1="$TMPD/h_repo1"; HR2="$TMPD/h_repo2"
for r in "$HR1:hb1" "$HR2:hb2"; do
  git init -q -b "${r##*:}" "${r%%:*}" && git -C "${r%%:*}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
done
HSCEN="$TMPD/hscen.sh"
cat >"$HSCEN" <<HEOF
#!/usr/bin/env bash
export LABEL_SYNC_DIR LABEL_SYNC_LABELCTL LABEL_SYNC_TITLE_SINK LABEL_SYNC_CMD_MIN_INTERVAL
export LABEL_SYNC_LABELER="$REALLAB"
cd "$HR1"
source "$RENDER/shell-integration.bash"
echo "SHELL_ID=\$LABEL_SYNC_SHELL_ID"
br() { "\$LABEL_SYNC_LABELCTL" get --id "\$LABEL_SYNC_SHELL_ID" --json 2>/dev/null | jq -r ".\$1 // empty"; }
waitf() { for i in \$(seq 200); do [ "\$(br "\$1")" = "\$2" ] && return 0; sleep 0.05; done; return 1; }
__ls_precmd
waitf branch hb1; echo "B0=\$(br branch)"
git checkout -q -b hb1-next
__ls_precmd
waitf branch hb1-next; echo "B1=\$(br branch)"
cd "$HR2"
__ls_precmd
waitf branch hb2; echo "B2=\$(br branch)"; echo "C2=\$(br cwd)"
mkdir -p "$HR2/sub"; cd "$HR2/sub"
__ls_precmd
waitf cwd "$HR2/sub"; echo "C3=\$(br cwd)"
cd /
__ls_precmd
waitf cwd /; sleep 0.3; echo "B3=\$(br branch)"
trap - EXIT
HEOF
HOUT="$(LABEL_SYNC_TITLE_SINK="$TMPD/h_title" bash "$HSCEN" 2>/dev/null)"
eq "H2 fixture: the shell starts on hb1" "hb1" "$(printf '%s\n' "$HOUT" | sed -n 's/^B0=//p')"
eq "H3 git checkout in the shell's repo => the shell entity's branch follows" "hb1-next" "$(printf '%s\n' "$HOUT" | sed -n 's/^B1=//p')"
eq "H4 cd into another repo => branch follows" "hb2" "$(printf '%s\n' "$HOUT" | sed -n 's/^B2=//p')"
eq "H4b cd into another repo => cwd follows" "$HR2" "$(printf '%s\n' "$HOUT" | sed -n 's/^C2=//p')"
eq "H4d cd within the same repo (HEAD unchanged) => cwd follows" "$HR2/sub" "$(printf '%s\n' "$HOUT" | sed -n 's/^C3=//p')"
eq "H4c cd outside any repo => branch CLEARED, never kept from the previous repo" "" "$(printf '%s\n' "$HOUT" | sed -n 's/^B3=//p')"
NOFORK="$(bash -c 'export LABEL_SYNC_DIR=/proc/nonexistent/x LABEL_SYNC_LABELCTL=/nonexistent; cd "$2"; source "$1/shell-integration.bash"; __ls_place_changed && echo CHANGED || echo SAME; cd /; __ls_place_changed && echo CHANGED || echo SAME; trap - EXIT' _ "$RENDER" "$HR1" 2>/dev/null | tr '\n' ' ')"
eq "H5 unchanged cwd + HEAD => no refresh (cheap path); a cd => refresh" "SAME CHANGED " "$NOFORK"

echo "RESULT pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
