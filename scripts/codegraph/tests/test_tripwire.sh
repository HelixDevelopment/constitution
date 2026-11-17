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
    # T4 drives the REAL df read (no override). The threshold is derived from the free space
    # measured on the df target, never hard-coded: a fixed 400 GiB did not trip on a volume with
    # more than 400 GiB free (audit 2026-11-16 F7). The df target is the first candidate whose
    # free space is at least 5 GiB and free space + 2 GiB fits the documented bound [5,500]; the
    # tripwire only runs df on --dir and writes nothing there. The tripwire's own logged avail_bytes must match the independent df
    # read within 2 GiB, and its logged min_bytes must be the derived threshold (control needles: the
    # trip came from the real df and from the measured threshold, not from a default or a fixed value).
    # No candidate fits -> honest SKIP, never counted as a PASS (T6 covers the override path).
    t4_dir=""; t4_gib=""; t4_fb=""
    for cand in "$W" "${XDG_RUNTIME_DIR:-}" /dev/shm /; do
        [ -n "$cand" ] && [ -d "$cand" ] || continue
        fb="$(df -B1 --output=avail "$cand" 2>/dev/null | tail -n 1 | tr -d ' ')"
        case "$fb" in ''|*[!0-9]*) continue ;; esac
        # a target with less than 5 GiB free would need the lower clamp of the bound, and a
        # clamped threshold would no longer be derived from the measurement: skip it
        g=$(( fb / 1073741824 + 2 ))
        if [ "$g" -ge 7 ] && [ "$g" -le 500 ]; then t4_dir="$cand"; t4_gib="$g"; t4_fb="$fb"; break; fi
    done
    if [ -z "$t4_dir" ]; then
        printf 'RESULT T4 SKIP real-df trip: no df target with 5 to 498 GiB free (threshold bound [5,500]); override path covered by T6\n'
    else
        spawn_live
        bash "$TW" --pid "$LIVE" --dir "$t4_dir" --min-gib "$t4_gib" --interval 1 --log "$W/t4.log" >/dev/null 2>&1; rc=$?
        st="$(t_pid_state "$LIVE")"
        lav="$(sed -n 's/.*avail_bytes=\([0-9][0-9]*\) min_bytes.*/\1/p' "$W/t4.log" 2>/dev/null | tail -n 1)"
        lmin="$(sed -n 's/.*avail_bytes=[0-9][0-9]* min_bytes=\([0-9][0-9]*\).*/\1/p' "$W/t4.log" 2>/dev/null | tail -n 1)"
        dif=$(( ${lav:-0} - t4_fb )); [ "$dif" -lt 0 ] && dif=$(( -dif ))
        [ "$rc" -eq 10 ] && [ "$st" = "T" ] && grep -q TRIPPED "$W/t4.log" && [ -f "$W/t4.log.TRIPPED" ] \
            && [ -n "$lav" ] && [ "$dif" -le 2147483648 ] && [ "${lmin:-0}" = "$(( t4_gib * 1073741824 ))" ]
        t_check T4 "real-identity indexer + free < threshold (real df, threshold from measured free space) -> SIGSTOP (state T, not killed), exit 10, marker" $? \
            "rc=$rc state=$st dir=$t4_dir min_gib=$t4_gib df_bytes=$t4_fb logged_avail=${lav:-none} logged_min=${lmin:-none}"
        t_kill_codegraph_pid "$LIVE"; LIVE=""
    fi
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
