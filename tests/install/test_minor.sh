#!/usr/bin/env bash
# test_minor.sh — round-2 review MINOR findings, one RED-first case each (real installer, local repos only).
#
#   M1 interactive menu: an out-of-range number prints a message and re-asks; `--agent <number>` exits 2
#   M2 a staging clone left by a killed run is REPORTED (warning + report note), never deleted
#   M3 a cost printed in exponent form (jq prints 1e-05) is normalised before it is summed
#   M4 a missing core tool (here: timeout) stops the installer up front with exit 3
#   M5 the verify step runs `git status` under the user's umask, so the submodule index keeps 0644 (not 0600)
# Usage: bash tests/install/test_minor.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=minor
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"
NI=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
lib() { HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"; }   # functions only, nothing runs

echo "# M1 interactive menu: out-of-range number re-asks"
printf '99\n0\n' >"$SB/answers"
out="$( (
  lib; hi_init_state 2>/dev/null
  hi_detect_agents() { printf 'fakeagent|cli|x|true|/x|1.0|ok\n'; }
  hi_was_set() { [ "$1" != --agent ]; }
  # the answers and the menu go through fds 8/7 exactly as hi_open_tty sets them up for a terminal
  # (a regular file cannot stand in for /dev/tty there: opening it for writing would truncate the answers)
  exec 8<"$SB/answers" 7>"$SB/menu.out"
  hi_interactive_questions >/dev/null 2>&1
  printf 'AGENT=%s\n' "$O_AGENT"
) 2>&1)"
case "$out" in *"AGENT=none"*) ok "after 99 the menu re-asked and took 0 (none)" ;; *) nok "menu re-ask (got: $out)" ;; esac
check "message names the bad number and the range" grep -q 'there is no agent number 99; choose 0..1' "$SB/menu.out"
eq "the question was asked twice" 2 "$(grep -o 'Which agent should run the setup prompt' "$SB/menu.out" | wc -l)"
P="$SB/m1"; new_project "$P"; f="$(tree_fingerprint "$P")"
run_installer "$P" --non-interactive --agent 5 --run-setup off --upstream-url "$UP"
eq "--agent 5 (a bare number) in non-interactive mode -> exit 2" 2 "$RC"
check "--agent 5: says a number is only a menu choice" grep -q 'only a menu choice' <<<"$OUT"
eq "--agent 5: project unchanged" "$f" "$(tree_fingerprint "$P")"

echo "# M2 leftover staging clone from a killed run is reported, never deleted"
P="$SB/m2"; new_project "$P"
LEFT="$P/.constitution-install-backup/20200101T000000Z-1/staging/constitution"
mkdir -p "$LEFT"; printf 'x\n' >"$LEFT/x"
run_installer "$P" "${NI[@]}" --report-json "$SB/m2.json"
eq "install still succeeds" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6
check "warning names the leftover clone" grep -qF "leftover clone from an interrupted run: $LEFT" <<<"$OUT"
check "report notes carry it" python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if any(sys.argv[2] in n for n in d.get("notes",[])) else 1)' "$SB/m2.json" "$LEFT"
check "leftover clone was NOT deleted" test -f "$LEFT/x"
run_installer "$P" "${NI[@]}" --dry-run
check "dry run reports it too" grep -qF 'leftover clone from an interrupted run' <<<"$OUT"

echo "# M3 exponent-form cost is normalised"
eq "hi_account_cost cost=1e-03 adds 0.001" 0.0010 "$( (lib; S_SPENT=0; S_COST_KNOWN=1; hi_account_cost 'result=success session=x rate_limited=0 cost=1e-03'; printf '%s' "$S_SPENT") )"
eq "hi_account_cost cost=2.5E-2 adds 0.025" 0.0250 "$( (lib; S_SPENT=0; S_COST_KNOWN=1; hi_account_cost 'result=success session=x rate_limited=0 cost=2.5E-2'; printf '%s' "$S_SPENT") )"
eq "hi_account_cost cost=1e-03x is not a number -> untrackable" 0 "$( (lib; S_SPENT=0; S_COST_KNOWN=1; hi_account_cost 'result=success session=x rate_limited=0 cost=1e-03x'; printf '%s' "$S_COST_KNOWN") )"
# a JSON emitter writes a tiny cost in exponent form; jq 1.8 even re-renders it as 1.5E-7 (capital E, measured)
printf '{"type":"system","subtype":"init","session_id":"s1"}\n{"type":"result","subtype":"success","is_error":false,"session_id":"s1","total_cost_usd":1.5e-7}\n' >"$SB/stream.jsonl"
if command -v jq >/dev/null 2>&1; then
  mkdir -p "$SB/nopy"; for t in jq grep awk sed cat; do ln -s "$(command -v "$t")" "$SB/nopy/$t"; done
  raw="$(jq -r 'select(.type=="result") | .total_cost_usd | tostring' "$SB/stream.jsonl")"
  check "precondition: jq itself prints the exponent form ($raw)" grep -q '[eE]-' <<<"$raw"
  line="$( (lib; PATH="$SB/nopy"; hi_parse_stream "$SB/stream.jsonl") )"
  pyline="$( (lib; hi_parse_stream "$SB/stream.jsonl") )"
  check "jq branch (python hidden) prints a plain decimal cost ($line)" grep -qE 'cost=[0-9]+(\.[0-9]+)?$' <<<"$line"
  eq "jq branch and python branch print the same line" "$pyline" "$line"
  eq "the cost stays trackable" 1 "$( (lib; S_SPENT=0; S_COST_KNOWN=1; hi_account_cost "$line"; printf '%s' "$S_COST_KNOWN") )"
else
  printf '  SKIP jq branch: jq not installed on this host (not counted as a pass)\n'
fi

echo "# M4 a missing core tool stops the installer up front (exit 3)"
mkdir -p "$SB/notimeout"
for d in /usr/local/bin /usr/bin /bin; do
  for t in "$d"/*; do b="${t##*/}"; [ "$b" = timeout ] && continue; [ -e "$SB/notimeout/$b" ] || ln -s "$t" "$SB/notimeout/$b" 2>/dev/null; done
done
check "precondition: timeout is really hidden" eval '! PATH="$SB/notimeout" command -v timeout >/dev/null'
P="$SB/m4"; new_project "$P"; f="$(tree_fingerprint "$P")"
OUT="$(cd "$P" && PATH="$SB/notimeout" bash "$INSTALLER" "${NI[@]}" 2>&1)"; RC=$?
eq "missing timeout -> exit 3" 3 "$RC"
check "message names the missing tool" grep -q 'timeout' <<<"$OUT"
eq "project unchanged" "$f" "$(tree_fingerprint "$P")"

echo "# M5 verify keeps the user's umask for git status (index not 0600)"
P="$SB/m5"; new_project "$P"
OUT="$(cd "$P" && umask 022 && bash "$INSTALLER" "${NI[@]}" 2>&1)"; RC=$?
eq "install exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6
idx="$(git -C "$P/submodules/constitution" rev-parse --git-path index)"; case "$idx" in /*) ;; *) idx="$P/submodules/constitution/$idx" ;; esac
eq "submodule index mode under umask 022" 644 "$(stat -c %a "$idx")"
finish
