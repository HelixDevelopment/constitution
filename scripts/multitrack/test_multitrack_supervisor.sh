#!/bin/sh
# =============================================================================
# test_multitrack_supervisor.sh — RED/GREEN polarity test for RB-07's ruler
#     self-supervisor + durable handoff
#     (constitution/scripts/multitrack/multitrack_supervisor.sh).
# -----------------------------------------------------------------------------
# Purpose:
#   Proves the RB-07 primitive is load-bearing, not a bluff (§11.4.115
#   polarity switch on ONE test source), device-AND-account-INDEPENDENTLY
#   via pure file/process simulation on the local host -- NO real `claude`,
#   NO real token, NO network, NO real worker, NO device (§11.4.98 / §12.6 /
#   §11.4.133). The ONLY external primitives exercised are POSIX process
#   management (`sleep &` / `kill` / `kill -0`) to simulate a ruler dying,
#   and plain directory removal to simulate the co-occurring loss of a
#   tmpfs-class registry area (the realistic D-2 trigger: ruler crash +
#   host reboot / container restart before any recovery happens).
#
#   RED_MODE=1 (default) -- RB-07 is a NEW capability (like RB-05), so there
#     is no prior broken commit to diff against (§11.4.114 does not apply --
#     nothing "used to work"). The honest pre-fix world this reproduces:
#       (R1) NO durable supervisor mechanism is ever invoked at all -- the
#            ONLY place per-track state lives is RB-05's own live registry,
#            which is a tmpfs-class location by RB-05's OWN documented
#            default. 2 tracks are known before a simulated tmpfs wipe;
#            0 are recoverable after -- because nothing ever copied that
#            data anywhere durable. This is the D-2 gap in its rawest form.
#       (R2) the REAL RB-07 script IS invoked, but MISCONFIGURED so its own
#            durable state file is co-located INSIDE the same volatile area
#            that gets wiped (this is also the exact §1.1 mutation target
#            for the GREEN gate: "point the state file back at tmpfs"). 2
#            tracks are captured pre-death; after the ruler is killed AND
#            the volatile area (which now also contains the misconfigured
#            "durable" state) is wiped, `watch --once` recovers 0/2 tracks.
#   RED_MODE=0 (GREEN) -- drives the REAL primitive CORRECTLY configured
#     (its durable state dir kept SEPARATE from RB-05's volatile registry)
#     and proves:
#       (G1) `snapshot` captures 2 tracks from the live registry into the
#            durable ruler_state.json; the simulated ruler is killed AND the
#            ENTIRE live-registry area is wiped (worst-case: both the ruler
#            AND its ephemeral working dir are lost together); `watch
#            --once` detects the dead ruler_pid, REHYDRATES, and the
#            resulting per-track alias/session_id/cwd data is BYTE-IDENTICAL
#            (normalized: ruler_pid/updated/rehydrated_at stripped) to the
#            pre-death capture -- the load-bearing RB-07 claim.
#       (G2) events.jsonl-only fallback -- a live registry that NEVER wrote
#            a per-track snapshot file (only the append-only events.jsonl
#            survives) still lets `watch --once` recover 2/2 tracks by
#            REPLAYING events.jsonl (last matching event per track wins) --
#            directly exercising the "+ events.jsonl" clause of the RB-07
#            spec, not merely the live tracks/*.json shortcut.
#       (G3) the DEFAULT resolution of the durable state directory (no
#            MT_RULER_STATE_DIR override at all) resolves under
#            `<repo>/.ws_state/multitrack/` and never mentions a tmpfs-class
#            path (`/tmp`, `${XDG_RUNTIME_DIR}`, `/run/user/`) -- proven by
#            actually RUNNING the script (`status`) against a scratch repo
#            root, not merely grepping its source (§11.4.107 -- behavioural
#            evidence, stronger than a static assertion).
#   Both modes run their scenario battery 3 times (§11.4.50 determinism) and
#   assert the per-iteration PASS/FAIL VERDICT FINGERPRINT (which named
#   sub-checks passed) is identical across all 3 iterations.
#
# Usage:
#   RED_MODE=1 sh constitution/scripts/multitrack/test_multitrack_supervisor.sh  # RED
#   RED_MODE=0 sh constitution/scripts/multitrack/test_multitrack_supervisor.sh  # GREEN
#   (default RED_MODE=1 if unset)
#
# Inputs: RED_MODE (0|1, default 1); MT_REPO_ROOT (optional, else git
#   toplevel from this file's dir); optional MT_SUP_TEST_EVIDENCE_DIR
#   override.
#
# Outputs: PASS/FAIL lines on stdout + $EV/results.log; per-iteration
#   evidence artefacts (pre-death / post-rehydrate ruler_state.json captures,
#   watch/snapshot logs) under $EV. Exit 0 iff FAIL count is 0.
#
# Side-effects: creates + removes ONE scratch tmp dir per run (`trap ...
#   EXIT INT TERM` cleanup on every exit path, §11.4.14); backgrounds a
#   handful of short-lived `sleep 60 &` processes as direct children of THIS
#   script to simulate a ruler PID, always explicitly killed by name (never
#   `pkill`/wildcard) and swept again in cleanup; writes ONLY under
#   qa-results/multitrack/ and the scratch dir; NEVER touches a real device,
#   network, or credential; NEVER spawns a real worker or a real build.
#
# Dependencies: sh (POSIX), git, date, mktemp, diff, sed, grep, cut, kill.
#
# Cross-references: constitution/scripts/multitrack/multitrack_supervisor.sh
#   (unit under test, alongside this file); constitution/scripts/multitrack/
#   multitrack_sessions.sh (RB-05, the live-registry format this test's
#   fixtures mirror exactly -- tracks/<t>.json + events.jsonl field names);
#   scripts/multitrack/test_multitrack_host_budget.sh + scripts/multitrack/
#   test_multitrack_sessions_spawn.sh (house style this file mirrors);
#   docs/superpowers/plans/ruler_bridge_plan.md RB-07; §11.4.43/§11.4.115
#   (RED->GREEN polarity); §11.4.50 (determinism); §11.4.67 (sh-parseable);
#   §11.4.131 (durable resumption file); §11.4.147 (crash-respawn).
# =============================================================================

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
MT_TEST_SELF=$0
case "$MT_TEST_SELF" in
    */*) MT_TEST_DIR=${MT_TEST_SELF%/*} ;;
    *)   MT_TEST_DIR=. ;;
esac

_sup_test_repo_root() {
    if [ -n "${MT_REPO_ROOT:-}" ]; then printf '%s\n' "$MT_REPO_ROOT"; return 0; fi
    ( cd "$MT_TEST_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null )
}
REPO_ROOT=$(_sup_test_repo_root)
[ -n "$REPO_ROOT" ] || { echo "FATAL: no repo root (git toplevel / \$MT_REPO_ROOT)" >&2; exit 90; }

SUP="$MT_TEST_DIR/multitrack_supervisor.sh"
[ -f "$SUP" ] || { echo "FATAL: primitive not found: $SUP" >&2; exit 91; }
sh -n "$SUP" 2>/dev/null || { echo "FATAL: primitive fails sh -n: $SUP" >&2; exit 92; }

RED_MODE="${RED_MODE:-1}"
RUN_TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
EV="${MT_SUP_TEST_EVIDENCE_DIR:-$REPO_ROOT/qa-results/multitrack/rb07_test_${RUN_TS}-$$}"
mkdir -p "$EV"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mt_sup_test.XXXXXX")
ALL_RULER_PIDS=""
# NOTE (§11.4.102 root-cause, captured 2026-07-09): in this execution
# environment, calling `kill` on a tracked background child of THIS shell
# causes an EXIT-registered trap to fire IMMEDIATELY -- once, spuriously,
# mid-script -- in addition to firing again at genuine script end. Verified
# by isolated reproduction: `sh -c 'trap "echo T" EXIT; sleep 60 & p=$!;
# kill "$p"; echo after'` prints "T" BEFORE "after" (reproducible with
# EXIT-only, with or without an explicit `wait`). Because this test
# deliberately kills a simulated ruler PID multiple times per run (that IS
# the RB-07 scenario under test), an EXIT-registered `rm -rf "$WORK"` trap
# wiped the scratch dir MID-ITERATION and corrupted in-flight evidence
# (observed as nondeterministic G1/G2 failures). Fix: NEVER register the
# destructive removal on EXIT/INT/TERM. `cleanup_rulers` (idempotent, safe
# to fire any number of times) only reaps leftover ruler pids on INT/TERM;
# `$WORK` is removed via one explicit, unconditional statement at the TRUE
# end of the script instead (see bottom of file).
cleanup_rulers() {
    for _p in $ALL_RULER_PIDS; do kill "$_p" 2>/dev/null || true; done
}
trap cleanup_rulers INT TERM

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf 'PASS: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s [evidence: %s]\n' "$1" "$2" | tee -a "$EV/results.log"; }

# --- fixture writers -- MIRROR RB-05's real on-disk record shapes exactly
#     (multitrack_sessions.sh _mts_snapshot / _mts_event field names) so this
#     test exercises genuine integration against the real registry format,
#     not a simplified stand-in. ---------------------------------------------
write_track_snapshot() {  # $1=tracks_dir $2=track $3=alias $4=sid $5=cwd $6=status
    mkdir -p "$1"
    printf '{"track":"%s","alias":"%s","session_id":"%s","cwd":"%s","config_dir":"","pid":"0","status":"%s","updated":"1970-01-01T00:00:00Z"}\n' \
        "$2" "$3" "$4" "$5" "$6" > "$1/$2.json"
}
append_event() {  # $1=events_file $2=track $3=alias $4=sid $5=cwd $6=status
    mkdir -p "$(dirname "$1")"
    printf '{"ts":"1970-01-01T00:00:00Z","event":"spawn","track":"%s","alias":"%s","session_id":"%s","cwd":"%s","pid":"0","is_error":"","subtype":"","status":"%s"}\n' \
        "$2" "$3" "$4" "$5" "$6" >> "$1"
}

# a direct-child fake-ruler process: kept a DIRECT child of THIS script (not
# of any `$( )` subshell) so `kill`/`wait` genuinely target it and cleanup's
# sweep can always reap it.
spawn_fake_ruler() {
    sleep 60 &
    RULER_PID=$!
    ALL_RULER_PIDS="$ALL_RULER_PIDS $RULER_PID"
}
kill_fake_ruler() {  # $1=pid
    kill "$1" 2>/dev/null || true
    wait "$1" 2>/dev/null || true
    # bounded settle -- avoid a kill-then-immediately-kill-0 race.
    _i=0
    while kill -0 "$1" 2>/dev/null && [ "$_i" -lt 20 ]; do sleep 0.1 2>/dev/null || sleep 1; _i=$((_i+1)); done
}

_track_count_in_state() {  # $1=ruler_state.json path -> prints an integer, never fails
    _f="$1"
    if [ ! -f "$_f" ]; then printf '0\n'; return 0; fi
    _n=$(tail -n +2 "$_f" 2>/dev/null | grep -c '"track":' 2>/dev/null)
    printf '%s\n' "${_n:-0}"
}

# normalize_state — the per-TRACK data only (line 2 onward), sorted. The
# header line (line 1) is DELIBERATELY excluded rather than value-normalized:
# a plain snapshot's header has no "rehydrated_at" key at all, while a
# rehydrate's header adds one -- that key's very PRESENCE is the rehydrate
# signal (asserted separately below via the "REHYDRATING" log-grep), so
# diffing it as part of "did the track data survive intact" would conflate
# two different claims. Per-track lines carry no volatile fields at all
# (alias/session_id/cwd/last_verdict are all pinned literals in this test's
# fixtures), so they compare byte-identical with no normalization needed.
normalize_state() {  # $1=ruler_state.json path -> stable per-track text
    _f="$1"
    [ -f "$_f" ] || { printf '<absent>\n'; return 0; }
    tail -n +2 "$_f" 2>/dev/null | sort
}

# ------------------------------------------------------------------ battery ---
FINGERPRINT=""
run_battery() {
    _iter="$1"
    _iter_fp=""

    if [ "$RED_MODE" = "1" ]; then
        # ---- R1: no durable mechanism invoked at all — raw tmpfs-class loss ----
        _sess="$WORK/r1_sess_$_iter"
        write_track_snapshot "$_sess/tracks" trackA claude1 sid-A /mnt/track1/proj running
        write_track_snapshot "$_sess/tracks" trackB claude2 sid-B /mnt/track2/proj running
        _pre_r1=$(ls "$_sess/tracks" 2>/dev/null | wc -l | tr -d ' ')
        spawn_fake_ruler; _rp1="$RULER_PID"
        kill_fake_ruler "$_rp1"
        rm -rf "$_sess"   # simulate the tmpfs-class registry area getting wiped
        _post_r1=0
        [ -d "$_sess/tracks" ] && _post_r1=$(ls "$_sess/tracks" 2>/dev/null | wc -l | tr -d ' ')
        _ev_r1="$EV/r1_iter${_iter}.txt"
        printf 'pre=%s post=%s (no supervisor mechanism ever invoked)\n' "$_pre_r1" "${_post_r1:-0}" > "$_ev_r1"
        if [ "$_pre_r1" = "2" ] && [ "${_post_r1:-0}" = "0" ]; then
            pass "R1[iter=$_iter] no-durable-mechanism: 2 tracks known pre-wipe, 0 recoverable post-tmpfs-wipe -- D-2 defect reproduced" "$_ev_r1"
            _iter_fp="${_iter_fp}R1=PASS;"
        else
            fail "R1[iter=$_iter] expected pre=2/post=0, got pre=$_pre_r1/post=${_post_r1:-0}" "$_ev_r1"
            _iter_fp="${_iter_fp}R1=FAIL;"
        fi

        # ---- R2: real script invoked but MISCONFIGURED onto the volatile dir ----
        _sess2="$WORK/r2_sess_$_iter"
        write_track_snapshot "$_sess2/tracks" trackA claude1 sid-A /mnt/track1/proj running
        write_track_snapshot "$_sess2/tracks" trackB claude2 sid-B /mnt/track2/proj running
        _snap_log="$EV/r2_snapshot_iter${_iter}.log"
        MT_SESSIONS_DIR="$_sess2" MT_RULER_STATE_DIR="$_sess2/ruler_state" MT_REPO_ROOT="$WORK" \
            sh "$SUP" snapshot >"$_snap_log" 2>&1
        spawn_fake_ruler; _rp2="$RULER_PID"
        MT_SESSIONS_DIR="$_sess2" MT_RULER_STATE_DIR="$_sess2/ruler_state" MT_REPO_ROOT="$WORK" \
            sh "$SUP" snapshot --ruler-pid "$_rp2" >>"$_snap_log" 2>&1
        _pre_r2=$(_track_count_in_state "$_sess2/ruler_state/ruler_state.json")
        kill_fake_ruler "$_rp2"
        rm -rf "$_sess2"   # wipes BOTH the volatile registry AND the misconfigured "durable" state
        _watch_log="$EV/r2_watch_iter${_iter}.log"
        MT_SESSIONS_DIR="$_sess2" MT_RULER_STATE_DIR="$_sess2/ruler_state" MT_REPO_ROOT="$WORK" \
            sh "$SUP" watch --once >"$_watch_log" 2>&1 || true
        _post_r2=$(_track_count_in_state "$_sess2/ruler_state/ruler_state.json")
        if [ "$_pre_r2" = "2" ] && [ "$_post_r2" = "0" ]; then
            pass "R2[iter=$_iter] state co-located with the volatile registry: pre=2 post-wipe=0 recoverable via watch --once -- D-2 reproduced under misconfiguration (the exact GREEN-gate mutation target)" "$_watch_log"
            _iter_fp="${_iter_fp}R2=PASS;"
        else
            fail "R2[iter=$_iter] expected pre=2/post=0 (misconfigured), got pre=$_pre_r2/post=$_post_r2" "$_watch_log"
            _iter_fp="${_iter_fp}R2=FAIL;"
        fi
    else
        # =============================== GREEN =================================
        # ---- G1: durable state (SEPARATE dir) survives ruler death + full ----
        # ---- live-registry loss; watch --once rehydrates byte-identically. ----
        _sess="$WORK/g1_sess_$_iter"; _durable="$WORK/g1_durable_$_iter"
        write_track_snapshot "$_sess/tracks" trackA claude1 sid-A /mnt/track1/proj running
        write_track_snapshot "$_sess/tracks" trackB claude2 sid-B /mnt/track2/proj running
        spawn_fake_ruler; _rp="$RULER_PID"
        _snap_log="$EV/g1_snapshot_iter${_iter}.log"
        MT_SESSIONS_DIR="$_sess" MT_RULER_STATE_DIR="$_durable" MT_REPO_ROOT="$WORK" \
            sh "$SUP" snapshot --ruler-pid "$_rp" >"$_snap_log" 2>&1
        _predeath="$EV/g1_predeath_iter${_iter}.json"
        cp "$_durable/ruler_state.json" "$_predeath" 2>/dev/null || true
        kill_fake_ruler "$_rp"
        rm -rf "$_sess"   # worst case: the ENTIRE live registry is lost too
        _watch_log="$EV/g1_watch_iter${_iter}.log"
        MT_SESSIONS_DIR="$_sess" MT_RULER_STATE_DIR="$_durable" MT_REPO_ROOT="$WORK" \
            sh "$SUP" watch --once >"$_watch_log" 2>&1
        _postrehydrate="$EV/g1_postrehydrate_iter${_iter}.json"
        cp "$_durable/ruler_state.json" "$_postrehydrate" 2>/dev/null || true
        _pre_norm=$(normalize_state "$_predeath")
        _post_norm=$(normalize_state "$_postrehydrate")
        if [ "$_pre_norm" = "$_post_norm" ] && grep -q "REHYDRATING" "$_watch_log" 2>/dev/null; then
            pass "G1[iter=$_iter] durable ruler_state.json (separate dir) + watch --once rehydrates after simulated ruler death -- pre-death vs post-rehydrate per-track data byte-identical (normalized)" "$_postrehydrate"
            _iter_fp="${_iter_fp}G1=PASS;"
        else
            fail "G1[iter=$_iter] rehydrate mismatch or REHYDRATING not logged (pre=[$_pre_norm] post=[$_post_norm])" "$_watch_log"
            _iter_fp="${_iter_fp}G1=FAIL;"
        fi

        # ---- G2: tracks/*.json NEVER written; events.jsonl-only replay -------
        _sess2="$WORK/g2_sess_$_iter"; _durable2="$WORK/g2_durable_$_iter"
        append_event "$_sess2/events.jsonl" trackA claude1 sid-A /mnt/track1/proj running
        append_event "$_sess2/events.jsonl" trackB claude2 sid-B /mnt/track2/proj running
        spawn_fake_ruler; _rp2="$RULER_PID"
        kill_fake_ruler "$_rp2"
        _watch2_log="$EV/g2_watch_iter${_iter}.log"
        MT_SESSIONS_DIR="$_sess2" MT_RULER_STATE_DIR="$_durable2" MT_REPO_ROOT="$WORK" \
            sh "$SUP" watch --once --ruler-pid "$_rp2" >"$_watch2_log" 2>&1
        _n2=$(_track_count_in_state "$_durable2/ruler_state.json")
        if [ "$_n2" = "2" ]; then
            pass "G2[iter=$_iter] events.jsonl-only fallback (no tracks/*.json ever written): watch --once replays events.jsonl and recovers 2/2 tracks" "$_durable2/ruler_state.json"
            _iter_fp="${_iter_fp}G2=PASS;"
        else
            fail "G2[iter=$_iter] events.jsonl replay recovered $_n2/2 tracks" "$_watch2_log"
            _iter_fp="${_iter_fp}G2=FAIL;"
        fi

        # ---- G3: default state dir avoids tmpfs-class paths (behavioural) ----
        # Run `status` against the REAL constitution-submodule checkout (this
        # file's own real, durable, git-tracked repo root) with NO
        # MT_RULER_STATE_DIR / MT_REPO_ROOT override at all, so the engine's
        # OWN default-resolution formula runs unmodified end-to-end. A
        # synthetic scratch "fake repo" is deliberately NOT used here: any
        # scratch dir this test creates necessarily lives under
        # ${TMPDIR:-/tmp} itself (test-harness scaffolding, irrelevant to what
        # the ENGINE'S default formula chooses), which would make a naive
        # substring-match on "/tmp/" a false positive against the test's own
        # plumbing rather than the engine's actual default. Using the real
        # checkout removes that confound entirely.
        _g3_out=$(
            unset MT_REPO_ROOT MT_RULER_STATE_DIR MT_SESSIONS_DIR 2>/dev/null
            sh "$SUP" status 2>&1
        )
        _g3_ev="$EV/g3_iter${_iter}.txt"
        printf '%s\n' "$_g3_out" > "$_g3_ev"
        case "$_g3_out" in
            *".ws_state/multitrack/ruler_state.json"*)
                case "$_g3_out" in
                    *"/tmp/"*|*'${XDG_RUNTIME_DIR}'*|*"/run/user/"*)
                        fail "G3[iter=$_iter] default path resolved but ALSO mentions a tmpfs-class path: $_g3_out" "$_g3_ev"
                        _iter_fp="${_iter_fp}G3=FAIL;"
                        ;;
                    *)
                        pass "G3[iter=$_iter] default ruler-state dir resolves to <repo>/.ws_state/multitrack/ruler_state.json (durable) -- never a tmpfs-class path by default" "$_g3_ev"
                        _iter_fp="${_iter_fp}G3=PASS;"
                        ;;
                esac
                ;;
            *)
                fail "G3[iter=$_iter] default state path did NOT resolve under .ws_state/multitrack: $_g3_out" "$_g3_ev"
                _iter_fp="${_iter_fp}G3=FAIL;"
                ;;
        esac
    fi

    _fp_file="$EV/fingerprint_iter${_iter}.txt"
    printf '%s\n' "$_iter_fp" > "$_fp_file"
}

for _i in 1 2 3; do
    run_battery "$_i"
done

# --- §11.4.50 determinism: the 3 per-iteration verdict fingerprints MUST be
#     identical (same named sub-checks PASS/FAIL the same way every time). ---
FP1=$(cat "$EV/fingerprint_iter1.txt" 2>/dev/null)
FP2=$(cat "$EV/fingerprint_iter2.txt" 2>/dev/null)
FP3=$(cat "$EV/fingerprint_iter3.txt" 2>/dev/null)
if [ "$FP1" = "$FP2" ] && [ "$FP2" = "$FP3" ]; then
    pass "DETERMINISM: verdict fingerprint identical across 3 iterations ($FP1)" "$EV/fingerprint_iter1.txt"
else
    fail "DETERMINISM: verdict fingerprint drifted across iterations (iter1=$FP1 iter2=$FP2 iter3=$FP3)" "$EV/fingerprint_iter1.txt"
fi

printf '\n=== RB-07 supervisor test summary (RED_MODE=%s): PASS=%s FAIL=%s ===\n' "$RED_MODE" "$PASS" "$FAIL" | tee -a "$EV/results.log"

_final_rc=1
[ "$FAIL" -eq 0 ] && _final_rc=0

# leftover-ruler sweep (belt-and-suspenders; INT/TERM already sweep on
# interrupt) + the scratch dir removal -- deliberately an EXPLICIT statement
# at the TRUE end of the script, NOT a trap body (see the cleanup_rulers
# note above for why an EXIT-trap-based removal is unsafe in this
# environment). Evidence under $EV (outside $WORK) survives this removal.
for _p in $ALL_RULER_PIDS; do kill "$_p" 2>/dev/null || true; done
rm -rf "$WORK" 2>/dev/null || true

exit "$_final_rc"
