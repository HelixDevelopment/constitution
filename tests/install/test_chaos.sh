#!/usr/bin/env bash
# test_chaos.sh — CHAOS tests: the REAL installer is interrupted with SIGINT / SIGTERM delivered to its whole
# process group (like Ctrl-C) at many points of a real ADD (during upstream probing, `git submodule add`,
# checkout, inheritance edits), then re-run cleanly: the re-run MUST converge to the same correct end state.
# Also: network loss (upstream disappears) mid-life then recovery, and backup restore (--restore).
# Process-group signals are guarded per §11.4.263 (pgid must be an integer > 1).
# Usage: bash tests/install/test_chaos.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=chaos
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
BASH_BASE=("${BASE[@]}")

i=0; interrupted=0
for sig in INT TERM; do
  for delay in 0.05 0.15 0.3 0.5 0.8 1.2 1.8 2.6; do
    i=$((i+1)); P="$SB/c$i"; new_project "$P"
    # a backgrounded child inherits SIGINT=ignored from bash; restore the default so Ctrl-C semantics are real
    (cd "$P" && exec python3 -I -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
       setsid bash "$INSTALLER" "${BASH_BASE[@]}" >"$SB/c$i.log" 2>&1) &
    pid=$!; sleep "$delay"
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [[ "$pgid" =~ ^[0-9]+$ ]] && [ "$pgid" -gt 1 ]; then kill -s "$sig" -- "-$pgid" 2>/dev/null; fi
    wait "$pid" 2>/dev/null; rc1=$?; [ "$rc1" != 0 ] && interrupted=$((interrupted+1))
    run_installer "$P" "${BASE[@]}" --report-json "$SB/c$i.json"
    if [ "$RC" = 0 ] && [ "$(gitlink "$P")" = "$V0" ] \
       && [ "$(grep -cx '## INHERITED FROM submodules/constitution/CLAUDE.md' "$P/CLAUDE.md")" = 1 ] \
       && [ "$(git -C "$P/submodules/constitution" rev-parse HEAD)" = "$V0" ] \
       && [ -z "$(git -C "$P/submodules/constitution" status --porcelain)" ]; then
      ok "SIG$sig after ${delay}s (first run rc=$rc1): clean re-run converged"
    else
      nok "SIG$sig after ${delay}s (first run rc=$rc1): re-run rc=$RC"; printf '%s\n' "$OUT" | tail -12
    fi
  done
done

check "signals really interrupted most first runs ($interrupted of $i non-zero)" eval '[ "$interrupted" -ge 10 ]'

echo "# backup is restorable"
P="$SB/bk"; new_project "$P"; printf '# Mine\nkeep me\n' >"$P/CLAUDE.md"; printf '# agents\n' >"$P/AGENTS.md"
git -C "$P" add CLAUDE.md AGENTS.md; git -C "$P" commit -qm docs
run_installer "$P" "${BASE[@]}" --report-json "$SB/bk.json"; eq "install with existing docs exit 0" 0 "$RC"
bdir="$(report_field "$SB/bk.json" backup_dir)"
check "backup dir recorded and present" test -d "$bdir"
run_installer "$P" --restore "$bdir"; eq "--restore exit 0" 0 "$RC"
eq "CLAUDE.md restored byte-identical" "$(git -C "$P" show HEAD:CLAUDE.md | sha256sum)" "$(sha256sum <"$P/CLAUDE.md")"
eq "AGENTS.md restored byte-identical" "$(git -C "$P" show HEAD:AGENTS.md | sha256sum)" "$(sha256sum <"$P/AGENTS.md")"
run_installer "$P" --restore "$SB"; eq "--restore outside the project backup root refused (exit 2)" 2 "$RC"

echo "# network loss then recovery"
P="$SB/net"; new_project "$P"
mv "$UP" "$SB/up/hidden.git"; s0="$(project_state "$P")"
run_installer "$P" "${BASE[@]}"; eq "upstream gone -> exit 3" 3 "$RC"; eq "network loss wrote nothing" "$s0" "$(project_state "$P")"
mv "$SB/up/hidden.git" "$UP"
run_installer "$P" "${BASE[@]}"; eq "upstream back -> exit 0" 0 "$RC"; eq "recovered gitlink" "$V0" "$(gitlink "$P")"
git -C "$P" commit -qm add; advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2
mv "$UP" "$SB/up/hidden.git"; s0="$(project_state "$P")"
run_installer "$P" "${BASE[@]}"; eq "update with upstream gone -> exit 3" 3 "$RC"; eq "failed update wrote nothing" "$s0" "$(project_state "$P")"
mv "$SB/up/hidden.git" "$UP"
run_installer "$P" "${BASE[@]}"; eq "update after recovery exit 0" 0 "$RC"
eq "update after recovery reached new tag" "$(tagsha "$SB/up" helixconstitution-v999.1)" "$(gitlink "$P")"
finish
