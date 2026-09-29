#!/usr/bin/env bash
# ============================================================================
# test_tripwire.sh — tests for disk_tripwire.sh (§11.4.263 / §11.4.174 / §12)
# ============================================================================
# Purpose      Prove the tripwire (a) refuses invalid pids and pid<=1, (b) never
#              signals a process that is not a real codegraph indexer (carrier
#              golden-false), (c) SIGSTOPs (never kills) a real-identity indexer
#              when free disk < threshold (golden-true), (d) exits quietly when
#              the indexer ends, (e) bounds its threshold.
# Usage        bash test_tripwire.sh ; ONLY=T1,T4 bash test_tripwire.sh
# Inputs       tests/fixtures/stub_cg (node stub with the real process identity)
# Outputs      RESULT lines; exit 1 on any failure
# Side effects short-lived stub/carrier processes (identity-checked cleanup)
# Dependencies bash, node, coreutils (df)
# Cross-refs   ../disk_tripwire.sh, run_all.sh, test_mutation.sh
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CG_DIR="${CG_DIR:-$(cd "$HERE/.." && pwd)}"
# shellcheck source=lib_test.sh
. "$HERE/lib_test.sh"
TW="$CG_DIR/disk_tripwire.sh"
W="$(t_workdir tripwire)"
cp -a "$HERE/fixtures/stub_cg" "$W/stub"
LIVE=""; CAR=""

cleanup() {
    t_kill_codegraph_pid "$LIVE"
    case "$CAR" in ''|*[!0-9]*) ;; *)
        [ "$CAR" -gt 1 ] && tr '\0' ' ' 2>/dev/null < "/proc/$CAR/cmdline" | grep -q '^bash -c sleep 300; : ' && kill -TERM "$CAR" 2>/dev/null ;;
    esac
}
trap cleanup EXIT

spawn_live() {
    STUB_SLEEP_MS="${1:-60000}" node "$W/stub/lib/dist/bin/codegraph.js" sleep >/dev/null 2>&1 &
    LIVE=$!
    sleep 0.3
}

if t_want T1; then
    r=0
    for bad in abc 0 1 -5 ''; do
        bash "$TW" --pid "$bad" --dir "$W" --min-gib 10 --interval 1 --log "$W/t1.log" >/dev/null 2>&1
        [ $? -eq 2 ] || r=1
    done
    t_check T1 "pid not an int > 1 -> refused (exit 2), no signal (§11.4.263)" "$r" "a bad pid was accepted"
fi

if t_want T2; then
    bash -c 'sleep 300; :' /x/lib/dist/bin/codegraph.js & CAR=$!; sleep 0.2
    bash "$TW" --pid "$CAR" --dir "$W" --min-gib 400 --interval 1 --log "$W/t2.log" >/dev/null 2>&1; rc=$?
    st="$(t_pid_state "$CAR")"
    [ "$rc" -eq 2 ] && [ "$st" = "S" ]
    t_check T2 "carrier (argv mentions codegraph.js, not a node indexer) -> refuses to arm, never signalled" $? "rc=$rc state=$st"
fi

if t_want T3; then
    spawn_live
    r=0
    for bad in 0 4 501 x; do
        bash "$TW" --pid "$LIVE" --dir "$W" --min-gib "$bad" --interval 1 --log "$W/t3.log" >/dev/null 2>&1
        [ $? -eq 2 ] || r=1
    done
    t_check T3 "threshold outside the documented bound [5,500] GiB -> refused" "$r" "an out-of-range threshold was accepted"
    t_kill_codegraph_pid "$LIVE"; LIVE=""
fi

if t_want T4; then
    spawn_live
    bash "$TW" --pid "$LIVE" --dir "$W" --min-gib 400 --interval 1 --log "$W/t4.log" >/dev/null 2>&1; rc=$?
    st="$(t_pid_state "$LIVE")"
    [ "$rc" -eq 10 ] && [ "$st" = "T" ] && grep -q TRIPPED "$W/t4.log" && [ -f "$W/t4.log.TRIPPED" ]
    t_check T4 "real-identity indexer + free < threshold -> SIGSTOP (state T, not killed), exit 10, marker" $? "rc=$rc state=$st"
    t_kill_codegraph_pid "$LIVE"; LIVE=""
fi

if t_want T5; then
    spawn_live 2000
    bash "$TW" --pid "$LIVE" --dir "$W" --min-gib 5 --interval 1 --log "$W/t5.log" >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 0 ] && grep -q 'gone' "$W/t5.log" && [ ! -f "$W/t5.log.TRIPPED" ]
    t_check T5 "enough free disk -> no trip; exits 0 when the indexer ends" $? "rc=$rc"
    LIVE=""
fi

if t_want T6; then
    spawn_live
    CG_SAFE_TEST_FREE_BYTES=1 bash "$TW" --pid "$LIVE" --dir "$W" --min-gib 5 --interval 1 --log "$W/t6.log" >/dev/null 2>&1; rc=$?
    st="$(t_pid_state "$LIVE")"
    [ "$rc" -eq 10 ] && [ "$st" = "T" ]
    t_check T6 "test-only lower-only free-bytes override trips at the default-range threshold" $? "rc=$rc state=$st"
    t_kill_codegraph_pid "$LIVE"; LIVE=""
fi

t_finish
