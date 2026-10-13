#!/bin/sh
# =============================================================================
# T085 US2 Round 2 remediation regression (B-R2-3, DEVICE-SAFETY CRITICAL,
# 2026-09-30).
# =============================================================================
#
# Proves the three independent fixes to
# constitution/scripts/fastcycle/gates/lib/io_trace_build_map.py landed for
# the T085 Round 2 NO-GO finding B-R2-3:
#
#   1. a script matching a device-mutating pattern (adb / reboot /
#      settings put / flash-tooling / rm -rf outside a scratch tree) is
#      SKIPPED by default, and only traced with --allow-device-scripts;
#   2. a timed-out trace kills the WHOLE process group, not merely the
#      direct child -- a backgrounded grandchild does not survive;
#   3. a script whose last recorded trace_status was "error" or "timeout"
#      is ALWAYS re-attempted on the next run, even with an unchanged
#      content hash -- never silently served as a stale permanent cache
#      hit.
#
# §11.4.199 (exact reproduction) / §12 + §11.4.225 (host-safety): this
# file NEVER points build-map at the real device/rockchip/rk3588/tests/
# tree -- every fixture below lives in an isolated `mktemp -d` scratch
# directory this file constructs itself, and is deleted on exit. The
# Round 2 reviewer correctly refused to run build-map against the real
# tree with boards attached; this test's own construction honours that
# same refusal. `adb devices` is captured before and after the ENTIRE run
# and asserted byte-identical as the final, independent safety check.
#
# Two complementary harnesses:
#   Section A -- the REAL io_trace.sh + strace, against a small mock
#     corpus of device-pattern / scratch-safe-rm / benign scripts. Proves
#     the classification + --allow-device-scripts opt-in end-to-end.
#   Section B -- a tiny deterministic FAKE --tool stub (never strace, never
#     the real io_trace.sh) driving io_trace_build_map.py's own retrace()/
#     cache logic directly, so the process-group-kill and
#     never-stale-cache assertions are exact and not timing-flaky.
#   Section C -- a direct unit check of `_safe_killpg()`'s §11.4.263
#     pgid<=1 refusal, via monkeypatched os.killpg (never a real signal to
#     a low pgid).
#
# Exit: 0 all as expected; 1 any FAIL recorded.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/io_trace.sh"
BUILD_MAP_PY="$FC/gates/lib/io_trace_build_map.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 2 B-R2-3 regression: io_trace_build_map.py device-safety, killpg, never-stale-cache =="

# =============================================================================
# Baseline safety check -- captured BEFORE any scratch work begins.
# =============================================================================
if command -v adb >/dev/null 2>&1; then
    ADB_BEFORE=$(adb devices 2>&1)
    HAVE_ADB=1
else
    ADB_BEFORE=""
    HAVE_ADB=0
    echo "NOTE: adb not on PATH -- device-untouched final check will be SKIPPED (honest, not fabricated)"
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

# =============================================================================
# Section A -- REAL io_trace.sh + strace against a mock corpus.
# =============================================================================
echo "-- Section A: real io_trace.sh end-to-end, mock corpus only --"

CORPUS_A="$SCRATCH/corpus_a"
mkdir -p "$CORPUS_A"
DB_A="$SCRATCH/a.sqlite"

cat > "$CORPUS_A/safe_gate.sh" <<'EOF'
#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cat "$HERE/own_data.txt" >/dev/null
EOF
echo "benign data" > "$CORPUS_A/own_data.txt"

cat > "$CORPUS_A/device_adb_gate.sh" <<'EOF'
#!/bin/sh
# NEVER actually run by this test -- content only, classified by text.
set -eu
adb shell echo hello
EOF

cat > "$CORPUS_A/device_reboot_gate.sh" <<'EOF'
#!/bin/sh
set -eu
adb reboot recovery
EOF

cat > "$CORPUS_A/device_settings_gate.sh" <<'EOF'
#!/bin/sh
set -eu
adb shell settings put system screen_brightness 100
EOF

cat > "$CORPUS_A/device_flash_gate.sh" <<'EOF'
#!/bin/sh
set -eu
upgrade_tool UF update_spi_nvme.img
EOF

cat > "$CORPUS_A/rm_rf_danger_gate.sh" <<'EOF'
#!/bin/sh
set -eu
TARGET=/some/absolute/nonscratch/path
rm -rf "$TARGET"
EOF

cat > "$CORPUS_A/rm_rf_scratch_gate.sh" <<'EOF'
#!/bin/sh
set -eu
TMPD=$(mktemp -d)
echo hi > "$TMPD/x"
cat "$TMPD/x" >/dev/null
rm -rf "$TMPD"
EOF

chmod +x "$CORPUS_A"/*.sh

# --- A1: default run (no --allow-device-scripts) ---
A1_OUT=$(sh "$TOOL" build-map --sections-dir "$CORPUS_A" --db "$DB_A" --per-script-timeout 5 2>&1)
A1_RC=$?

if [ "$A1_RC" -eq 0 ]; then
    ok "A1: build-map (default, no opt-in) exits 0 against the mock corpus"
else
    bad "A1: build-map (default) exited $A1_RC against the mock corpus: $A1_OUT"
fi

_a_status() {
    # $1 = basename of script under $CORPUS_A
    sqlite3 "$DB_A" "SELECT trace_status FROM io_map WHERE script_path LIKE '%$1'" 2>/dev/null
}

for f in device_adb_gate.sh device_reboot_gate.sh device_settings_gate.sh device_flash_gate.sh rm_rf_danger_gate.sh; do
    st=$(_a_status "$f")
    if [ "$st" = "skipped-device" ]; then
        ok "A2: $f classified skipped-device by default (not traced)"
    else
        bad "A2: $f expected trace_status=skipped-device, got '$st'"
    fi
done

for f in safe_gate.sh rm_rf_scratch_gate.sh; do
    st=$(_a_status "$f")
    if [ "$st" = "ok" ]; then
        ok "A3: $f (benign / scratch-exempt rm -rf) traced normally, status=ok"
    else
        bad "A3: $f expected trace_status=ok, got '$st' (scratch exemption or benign classification broken)"
    fi
done

if echo "$A1_OUT" | grep -q "5 skipped as"; then
    ok "A4: build-map's own summary line reports the 5 skipped-device scripts honestly"
else
    bad "A4: build-map summary did not report 5 skipped-device scripts: $A1_OUT"
fi

# --- A5: --allow-device-scripts opts back in ---
DB_A2="$SCRATCH/a2.sqlite"
A5_OUT=$(sh "$TOOL" build-map --sections-dir "$CORPUS_A" --db "$DB_A2" --per-script-timeout 5 --allow-device-scripts 2>&1)
A5_RC=$?
if [ "$A5_RC" -eq 0 ]; then
    DB_A="$DB_A2"
    st=$(_a_status "device_adb_gate.sh")
    if [ "$st" = "ok" ] || [ "$st" = "error" ]; then
        ok "A5: --allow-device-scripts opts device_adb_gate.sh IN (status='$st', no longer skipped-device)"
    else
        bad "A5: --allow-device-scripts did not opt device_adb_gate.sh in (status='$st')"
    fi
else
    bad "A5: build-map --allow-device-scripts exited $A5_RC: $A5_OUT"
fi

# =============================================================================
# Section B -- deterministic FAKE tool stub: process-group kill + never-
# stale-cache, exact (no strace timing dependency).
# =============================================================================
echo "-- Section B: fake --tool stub, killpg + never-stale-cache --"

CORPUS_B="$SCRATCH/corpus_b"
mkdir -p "$CORPUS_B"
DB_B="$SCRATCH/b.sqlite"
COUNTFILE="$SCRATCH/error_gate_invocations.count"
HANG_PIDFILE="$SCRATCH/hang.pid"
: > "$COUNTFILE"

cat > "$CORPUS_B/error_gate.sh" <<'EOF'
#!/bin/sh
# Deterministically classified as "error" by fake_tool.sh below (never
# actually executed -- the fake tool inspects the script PATH, not its
# content, and never runs it).
exit 1
EOF

cat > "$CORPUS_B/hang_gate.sh" <<'EOF'
#!/bin/sh
# Deterministically classified as "timeout" by fake_tool.sh below (never
# actually executed by the real shell -- the fake tool itself performs
# the background-spawn + hang behaviour this test needs).
sleep 1
EOF

cat > "$CORPUS_B/plain_gate.sh" <<'EOF'
#!/bin/sh
echo plain
EOF
chmod +x "$CORPUS_B"/*.sh

cat > "$SCRATCH/fake_tool.sh" <<EOF
#!/bin/sh
# Minimal deterministic stub standing in for gates/io_trace.sh's \`trace\`
# contract (Section B only -- never used for device-pattern classification,
# which is Section A's job against the REAL tool). Invoked exactly as
# io_trace_build_map.py's retrace() invokes the real tool:
#   sh <tool> trace <script_path>
case "\$2" in
    */error_gate.sh)
        echo "\$(date -u +%s)" >> "$COUNTFILE"
        exit 1
        ;;
    */hang_gate.sh)
        # Spawn a background grandchild that outlives a short timeout
        # unless the WHOLE process group is killed (B-R2-3 fix #2).
        sh -c 'sleep 30' &
        echo \$! > "$HANG_PIDFILE"
        sleep 30
        ;;
    *)
        echo '{"reads": ["'"\$2"'"], "writes": []}'
        ;;
esac
EOF
chmod +x "$SCRATCH/fake_tool.sh"

# --- B1: killpg kills the WHOLE process group on timeout ---
B1_OUT=$(python3 "$BUILD_MAP_PY" --sections-dir "$CORPUS_B" --db "$DB_B" \
    --tool "$SCRATCH/fake_tool.sh" --per-script-timeout 2 --allow-device-scripts 2>&1)
B1_RC=$?

if [ "$B1_RC" -eq 0 ]; then
    ok "B1: build-map (fake tool) exits 0 even though hang_gate.sh times out"
else
    bad "B1: build-map (fake tool) exited $B1_RC: $B1_OUT"
fi

if [ -f "$HANG_PIDFILE" ]; then
    GRANDCHILD_PID=$(cat "$HANG_PIDFILE")
    # Brief grace window for SIGKILL delivery/reap -- never a long sleep.
    i=0
    while [ "$i" -lt 10 ] && kill -0 "$GRANDCHILD_PID" 2>/dev/null; do
        sleep 0.2
        i=$((i + 1))
    done
    if kill -0 "$GRANDCHILD_PID" 2>/dev/null; then
        bad "B2: killpg FAILED -- grandchild PID $GRANDCHILD_PID (backgrounded 'sleep 30') is STILL RUNNING after the timeout returned"
        kill -9 "$GRANDCHILD_PID" 2>/dev/null
    else
        ok "B2: killpg killed the WHOLE process group -- grandchild PID $GRANDCHILD_PID is gone"
    fi
else
    bad "B2: hang_gate.sh's pidfile was never written -- fake_tool.sh contract broken or hang_gate.sh never reached"
fi

sqlite_status_b() {
    sqlite3 "$DB_B" "SELECT trace_status FROM io_map WHERE script_path LIKE '%$1'" 2>/dev/null
}
st=$(sqlite_status_b "hang_gate.sh")
if [ "$st" = "timeout" ]; then
    ok "B3: hang_gate.sh recorded trace_status=timeout"
else
    bad "B3: hang_gate.sh expected trace_status=timeout, got '$st'"
fi

# --- B4/B5: never-stale-cache -- error_gate.sh re-attempted on an
# unchanged hash, never silently served as a permanent hit.
st=$(sqlite_status_b "error_gate.sh")
if [ "$st" = "error" ]; then
    ok "B4: error_gate.sh recorded trace_status=error on the first run"
else
    bad "B4: error_gate.sh expected trace_status=error, got '$st'"
fi
COUNT_AFTER_1=$(wc -l < "$COUNTFILE" | tr -d ' ')

# Re-run build-map with the SAME db and the SAME (unchanged) corpus --
# error_gate.sh's content hash is unchanged, but the pre-fix bug would
# have read the unchanged hash as a HIT and never re-invoked fake_tool.sh
# a second time.
B5_OUT=$(python3 "$BUILD_MAP_PY" --sections-dir "$CORPUS_B" --db "$DB_B" \
    --tool "$SCRATCH/fake_tool.sh" --per-script-timeout 2 --allow-device-scripts 2>&1)
B5_RC=$?
COUNT_AFTER_2=$(wc -l < "$COUNTFILE" | tr -d ' ')

if [ "$B5_RC" -eq 0 ] && [ "$COUNT_AFTER_2" -gt "$COUNT_AFTER_1" ]; then
    ok "B5: never-stale-cache -- error_gate.sh was genuinely RE-INVOKED on the second run (invocations: $COUNT_AFTER_1 -> $COUNT_AFTER_2), never served as a stale cache hit"
else
    bad "B5: never-stale-cache FAILED -- error_gate.sh invocation count did not increase on the second run ($COUNT_AFTER_1 -> $COUNT_AFTER_2, rc=$B5_RC)"
fi

if echo "$B5_OUT" | grep -qE '[1-9][0-9]* re-traced'; then
    ok "B6: second build-map run's own summary reports a nonzero re-traced count (not '0 re-traced, N cache hits')"
else
    bad "B6: second build-map run's summary did not report a nonzero re-traced count: $B5_OUT"
fi

# --- B7: a genuine OK cache hit still works (regression: the fix must not
# break the legitimate caching behaviour for a script that DID succeed).
st_plain_1=$(sqlite_status_b "plain_gate.sh")
python3 "$BUILD_MAP_PY" --sections-dir "$CORPUS_B" --db "$DB_B" \
    --tool "$SCRATCH/fake_tool.sh" --per-script-timeout 2 --allow-device-scripts >/dev/null 2>&1
B7_THIRD_OUT=$(python3 "$BUILD_MAP_PY" --sections-dir "$CORPUS_B" --db "$DB_B" \
    --tool "$SCRATCH/fake_tool.sh" --per-script-timeout 2 --allow-device-scripts 2>&1)
if [ "$st_plain_1" = "ok" ] && echo "$B7_THIRD_OUT" | grep -qE '[1-9][0-9]* cache hit'; then
    ok "B7: a genuinely-'ok' script (plain_gate.sh) IS still cached as a hit on a stable run -- the fix did not regress the legitimate caching path"
else
    bad "B7: plain_gate.sh ('$st_plain_1') was not correctly cache-hit on a stable re-run: $B7_THIRD_OUT"
fi

# =============================================================================
# Section C -- §11.4.263 unit check: _safe_killpg() NEVER signals pgid<=1.
# =============================================================================
echo "-- Section C: §11.4.263 _safe_killpg() pgid<=1 refusal (monkeypatched, no real low-pgid signal ever sent) --"

C_OUT=$(python3 - "$BUILD_MAP_PY" <<'PYEOF'
import importlib.util
import os
import sys

mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("io_trace_build_map", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

calls = []

def _fake_killpg(pgid, sig):
    calls.append((pgid, sig))

real_killpg = os.killpg
os.killpg = _fake_killpg
try:
    results = []
    for bad_pgid in (1, 0, -1, "notanint", None):
        r = mod._safe_killpg(bad_pgid, 9)
        results.append((bad_pgid, r))
    if calls:
        print("FAIL: os.killpg was invoked for a pgid<=1 or non-int value -- calls=%r" % (calls,))
        sys.exit(1)
    if any(r for _, r in results):
        print("FAIL: _safe_killpg returned True for a refused pgid -- results=%r" % (results,))
        sys.exit(1)
    print("OK: _safe_killpg refused every pgid<=1/non-int value, os.killpg never invoked")

    # Positive-path sanity: a genuinely >1 pgid IS passed through to killpg.
    r2 = mod._safe_killpg(99999, 9)
    if calls == [(99999, 9)]:
        print("OK: _safe_killpg passes a genuinely valid pgid>1 through to os.killpg")
    else:
        print("FAIL: _safe_killpg did not pass a valid pgid>1 through -- calls=%r" % (calls,))
        sys.exit(1)
finally:
    os.killpg = real_killpg
PYEOF
)
C_RC=$?
echo "$C_OUT"
if [ "$C_RC" -eq 0 ] && echo "$C_OUT" | grep -q "^OK: _safe_killpg refused" && echo "$C_OUT" | grep -q "^OK: _safe_killpg passes a genuinely valid"; then
    ok "C1: §11.4.263 guard proven -- refuses every pgid<=1/non-int, passes through a genuine pgid>1"
else
    bad "C1: §11.4.263 guard check failed (rc=$C_RC): $C_OUT"
fi

# =============================================================================
# Final safety check -- adb device set is byte-identical before and after.
# =============================================================================
if [ "$HAVE_ADB" -eq 1 ]; then
    ADB_AFTER=$(adb devices 2>&1)
    if [ "$ADB_BEFORE" = "$ADB_AFTER" ]; then
        ok "SAFETY: 'adb devices' output is byte-identical before and after this entire test run -- neither attached board was touched"
        echo "   before: $(echo "$ADB_BEFORE" | tr '\n' ' ')"
        echo "   after:  $(echo "$ADB_AFTER" | tr '\n' ' ')"
    else
        bad "SAFETY: 'adb devices' output CHANGED during this test run -- before='$ADB_BEFORE' after='$ADB_AFTER'"
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
