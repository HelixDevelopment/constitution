#!/usr/bin/env bash
# r8_chaos_probe.sh REPO_DIR N → the test_round8 "chaos on the UPDATE path" SIGTERM case, N times at delays around
# 1.1 s, against the installer of REPO_DIR. After `wait` returns for the first run it records whether a git
# index.lock exists under the project and whether processes of the killed group are still alive, then whether the
# clean re-run converges (the test's own assertion). Probe only; never edits REPO_DIR.
T_NAME=r8probe
# shellcheck source=/dev/null
. "${1:?repo}/tests/install/lib.sh"
N="${2:?N}"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
mkinstalled() { new_project "$1"; run_installer "$1" "${BASE[@]}"; git -C "$1" commit -qm add; }
fails=0; lock_after_wait=0; alive_after_wait=0; lock_and_fail=0; j=0
for ((k = 1; k <= N; k++)); do
  for delay in 0.9 1.0 1.1 1.2 1.3; do
    j=$((j+1)); P="$SB/u$j"; mkinstalled "$P"
    advance_upstream "$SB/up" "helixconstitution-v999.1$j" || exit 2; VT="$(tagsha "$SB/up" "helixconstitution-v999.1$j")"
    (cd "$P" && exec python3 -I -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
       setsid bash "$INSTALLER" "${BASE[@]}" >"$SB/u$j.log" 2>&1) &
    pid=$!; sleep "$delay"
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [[ "$pgid" =~ ^[0-9]+$ ]] && [ "$pgid" -gt 1 ]; then kill -s TERM -- "-$pgid" 2>/dev/null; fi
    wait "$pid" 2>/dev/null; rc1=$?
    locks="$(find "$P/.git" -name index.lock 2>/dev/null | sed "s#^$P/##" | tr '\n' ' ')"
    alive=0; if [[ "$pgid" =~ ^[0-9]+$ ]] && [ "$pgid" -gt 1 ]; then alive="$(ps -o pid= -g "$pgid" 2>/dev/null | wc -l | tr -d ' ')"; fi
    [ -n "$locks" ] && lock_after_wait=$((lock_after_wait+1)); [ "$alive" -gt 0 ] && alive_after_wait=$((alive_after_wait+1))
    run_installer "$P" "${BASE[@]}"
    if [ "$RC" = 0 ] && [ "$(gitlink "$P")" = "$VT" ]; then res=converged; else res="FAIL rc=$RC"; fails=$((fails+1)); [ -n "$locks" ] && lock_and_fail=$((lock_and_fail+1)); fi
    echo "case=$j delay=$delay rc1=$rc1 alive_after_wait=$alive locks_after_wait=[${locks% }] rerun=$res"
  done
done
echo "SUMMARY cases=$j fails=$fails lock_after_wait=$lock_after_wait alive_after_wait=$alive_after_wait lock_and_fail=$lock_and_fail"
finish >/dev/null 2>&1 || true
