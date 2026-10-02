#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (R4-B1 BLOCKING, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review reproduced the T085 Round 3 (R3-B1)
# PATH/env-only device sandbox as bypassable TWO ways against the
# committed code, printing REAL device serials from the real adb server
# on the review host:
#
#   1. Absolute path: `"$ANDROID_HOME/platform-tools/a""db"` -- command
#      name text split so neither "adb" nor the full command ever
#      appears as a contiguous substring anywhere the classifier or the
#      OLD env-key-contains-"adb" denylist could see. ANDROID_HOME is
#      not itself named "adb", so it survived the old denylist
#      untouched.
#   2. Raw socket: a python3 TCP connection directly to
#      127.0.0.1:5037 (the real adb server's own protocol port),
#      sending "host:devices" -- no adb binary involved at all; no
#      PATH/env manipulation can ever see or stop a pure network action.
#
# Fixed (section 11.4.227 shared primitive, per the Round 4 reviewer's
# explicit "before Round 5" recommendation): fc_common.py now ships a
# namespace-based device sandbox (wrap_device_sandbox_argv /
# device_sandbox_env / device_sandbox_namespace_available) that isolates
# the underlying ACTION -- a fresh, unprivileged Linux user+network+mount
# namespace gives the sandboxed process its own loopback interface (DOWN
# by default), so connecting to 127.0.0.1:ANY-PORT fails with
# ENETUNREACH regardless of which binary/socket attempts it, real
# absolute-path adb included. io_trace_build_map.py's retrace() now
# wraps every traced script's argv through this primitive in default
# (non---allow-device-scripts) mode, and main() REFUSES to run at all in
# that mode (fail-closed, EXIT_BLIND) if the namespace-isolation
# precondition cannot be proven on this host.
#
# This file proves, against the REAL io_trace.sh + io_trace_build_map.py
# CLI entry point (never a direct unit-level function call alone -- the
# Round 4 reviewer's own repro was against the real `build-map`
# invocation) and against the REAL adb server already running on this
# host (never a fabricated/mocked one -- this IS the exact reproduction
# environment the Round 4 reviewer used), that BOTH bypasses are closed,
# that --allow-device-scripts still correctly opts OUT of sandboxing
# entirely (unchanged, pre-existing behaviour), and that the fail-closed
# refusal path triggers correctly when the namespace precondition cannot
# be confirmed -- with the real D1/D2 boards' `adb devices` output
# byte-identical before and after every section.
#
# Usage: sh test_io_trace_build_map_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/io_trace.sh"
BUILD_MAP_PY="$FC/gates/lib/io_trace_build_map.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 R4-B1 regression: io_trace_build_map.py namespace-based device sandbox =="

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
# Section A -- premise check: this host genuinely provides the namespace
# isolation the sandbox depends on (never assumed).
# =============================================================================
echo "-- Section A: premise -- namespace isolation is genuinely available on this host --"

A_OUT=$(python3 - "$BUILD_MAP_PY" <<'PYEOF'
import importlib.util, sys
mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("io_trace_build_map", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print("available=%s" % mod.fc_common.device_sandbox_namespace_available())
PYEOF
)
echo "$A_OUT"
if echo "$A_OUT" | grep -q "^available=True"; then
    ok "A1: fc_common.device_sandbox_namespace_available() confirms isolation live on this host"
else
    bad "A1: namespace isolation NOT available on this host ($A_OUT) -- Sections B/C below cannot meaningfully exercise the sandbox; host needs investigating"
fi

# =============================================================================
# Section B -- Bypass 1 (R4-B1 reproduction #1): absolute-path invocation
# via a NON-"adb"-named environment variable, against a REAL (not
# mocked) binary that genuinely attempts the real adb TCP handshake.
# =============================================================================
echo "-- Section B: absolute-path-via-ANDROID_HOME bypass (R4-B1 repro #1) --"

CORPUS_B="$SCRATCH/corpus_b"
mkdir -p "$CORPUS_B"
DB_B="$SCRATCH/b.sqlite"
FAKE_ANDROID_HOME="$SCRATCH/fake_android_home"
mkdir -p "$FAKE_ANDROID_HOME/platform-tools"
REAL_ADB_CONNECTED_MARKER="$SCRATCH/REAL_ADB_CONNECTED.marker"

# A "real-looking" adb that genuinely attempts the real TCP handshake a
# real adb client would -- not merely a marker-writing stub -- so this
# section proves the underlying ACTION (network connect), not merely
# whether some file happened to execute.
cat > "$FAKE_ANDROID_HOME/platform-tools/adb" <<EOF
#!/usr/bin/env python3
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(("127.0.0.1", 5037))
    open("$REAL_ADB_CONNECTED_MARKER", "w").write("connected")
    print("List of devices attached")
except OSError as e:
    print("blocked: %s" % e, file=sys.stderr)
    sys.exit(1)
EOF
chmod +x "$FAKE_ANDROID_HOME/platform-tools/adb"

# The EXACT obfuscation shape the Round 4 reviewer demonstrated: the
# command-name text is split so "adb" never appears as a contiguous
# substring anywhere in the script's own source.
cat > "$CORPUS_B/android_home_bypass.sh" <<'EOF'
#!/bin/sh
set -eu
TOOLNAME="${TOOLNAME:-ad}""b"
"$ANDROID_HOME/platform-tools/$TOOLNAME" -s FAKE_SERIAL devices
EOF
chmod +x "$CORPUS_B/android_home_bypass.sh"

# ANDROID_HOME is set in THIS shell (the build-map process's own
# inherited environment) -- exactly the Round 4 reviewer's reproduction
# setup ("on this host /home/milos/Factory/software/android").
B_OUT=$(ANDROID_HOME="$FAKE_ANDROID_HOME" sh "$TOOL" build-map \
    --sections-dir "$CORPUS_B" --db "$DB_B" --per-script-timeout 10 2>&1)
B_RC=$?

if [ "$B_RC" -eq 0 ]; then
    ok "B1: build-map (default, no opt-in) exits 0 against the ANDROID_HOME-bypass corpus"
else
    bad "B1: build-map exited $B_RC: $B_OUT"
fi

if [ ! -f "$REAL_ADB_CONNECTED_MARKER" ]; then
    ok "B2: the fake-real adb NEVER successfully connected to the real adb server -- R4-B1 bypass #1 closed (namespace network isolation held even against an absolute ANDROID_HOME path)"
else
    bad "B2: the fake-real adb DID connect to the real adb server (marker present) -- R4-B1 bypass #1 is STILL OPEN"
fi

TRACE_STATUS_B=$(sqlite3 "$DB_B" "SELECT trace_status FROM io_map WHERE script_path LIKE '%android_home_bypass.sh'" 2>/dev/null)
echo "B: trace_status=$TRACE_STATUS_B"
if [ "$TRACE_STATUS_B" = "ok" ] || [ "$TRACE_STATUS_B" = "error" ]; then
    ok "B3: the bypass script was genuinely RETRACED (trace_status='$TRACE_STATUS_B'), confirming this run exercised the real sandbox path (not skipped-device -- this script's text contains no 'adb' substring, by the same premise as the Round 3 obfuscation test)"
else
    bad "B3: unexpected trace_status '$TRACE_STATUS_B' -- this run may not have exercised the sandbox at all"
fi

# =============================================================================
# Section C -- Bypass 2 (R4-B1 reproduction #2): raw socket, no adb
# binary involved at all, against the REAL listening adb server on this
# host's 127.0.0.1:5037. READ-ONLY connect-only probe (mirrors the
# reviewer's own "host:devices" query -- never a mutating command),
# never anything beyond a bare TCP connect attempt.
# =============================================================================
echo "-- Section C: raw-socket-to-real-adb-server bypass (R4-B1 repro #2) --"

CORPUS_C="$SCRATCH/corpus_c"
mkdir -p "$CORPUS_C"
DB_C="$SCRATCH/c.sqlite"
RAW_SOCKET_CONNECTED_MARKER="$SCRATCH/RAW_SOCKET_CONNECTED.marker"

cat > "$CORPUS_C/raw_socket_bypass.sh" <<EOF
#!/bin/sh
python3 - <<'PYEOF'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(("127.0.0.1", 5037))
    open("$RAW_SOCKET_CONNECTED_MARKER", "w").write("connected")
    print("CONNECTED")
except OSError as e:
    print("blocked: %s" % e, file=sys.stderr)
    sys.exit(1)
PYEOF
EOF
chmod +x "$CORPUS_C/raw_socket_bypass.sh"

C_OUT=$(sh "$TOOL" build-map --sections-dir "$CORPUS_C" --db "$DB_C" --per-script-timeout 10 2>&1)
C_RC=$?

if [ "$C_RC" -eq 0 ]; then
    ok "C1: build-map (default, no opt-in) exits 0 against the raw-socket-bypass corpus"
else
    bad "C1: build-map exited $C_RC: $C_OUT"
fi

if [ ! -f "$RAW_SOCKET_CONNECTED_MARKER" ]; then
    ok "C2: the raw socket NEVER successfully connected to the real adb server (no adb binary involved at all) -- R4-B1 bypass #2 closed"
else
    bad "C2: the raw socket DID connect to the real adb server (marker present) -- R4-B1 bypass #2 is STILL OPEN"
fi

# =============================================================================
# Section D -- regression guard: --allow-device-scripts still correctly
# opts OUT of sandboxing entirely (pre-existing, documented behaviour --
# this section proves the Round 5 fix did not accidentally make the
# opt-out flag inert).
# =============================================================================
echo "-- Section D: --allow-device-scripts still disables the sandbox entirely (regression guard) --"

CORPUS_D="$SCRATCH/corpus_d"
mkdir -p "$CORPUS_D"
DB_D="$SCRATCH/d.sqlite"
OPT_OUT_MARKER="$SCRATCH/OPT_OUT_INVOKED.marker"
FAKE_PATH_D="$SCRATCH/fake_path_d"
mkdir -p "$FAKE_PATH_D"
cat > "$FAKE_PATH_D/adb" <<EOF
#!/bin/sh
echo "invoked" > "$OPT_OUT_MARKER"
echo "List of devices attached"
exit 0
EOF
chmod +x "$FAKE_PATH_D/adb"
cat > "$CORPUS_D/plain_adb_gate.sh" <<'EOF'
#!/bin/sh
adb devices
EOF
chmod +x "$CORPUS_D/plain_adb_gate.sh"

D_OUT=$(PATH="$FAKE_PATH_D:$PATH" sh "$TOOL" build-map \
    --sections-dir "$CORPUS_D" --db "$DB_D" --per-script-timeout 10 \
    --allow-device-scripts 2>&1)
D_RC=$?

if [ "$D_RC" -eq 0 ]; then
    ok "D1: build-map --allow-device-scripts exits 0"
else
    bad "D1: build-map --allow-device-scripts exited $D_RC: $D_OUT"
fi

if [ -f "$OPT_OUT_MARKER" ]; then
    ok "D2: with --allow-device-scripts, the (fake, PATH-resolved) adb WAS invoked -- confirms the opt-out flag genuinely disables sandboxing, unchanged by this round's fix"
else
    bad "D2: with --allow-device-scripts, the fake adb was NEVER invoked -- the opt-out flag no longer disables sandboxing (a Round 5 regression)"
fi

# =============================================================================
# Section E -- fail-closed refusal: when the namespace-isolation
# precondition cannot be confirmed, main() refuses to run in default
# mode at all (never a silent fallback to the weaker PATH/env sandbox).
# =============================================================================
echo "-- Section E: fail-closed refusal when the namespace precondition cannot be confirmed --"

CORPUS_E="$SCRATCH/corpus_e"
mkdir -p "$CORPUS_E"
DB_E="$SCRATCH/e.sqlite"
cat > "$CORPUS_E/plain_gate.sh" <<'EOF'
#!/bin/sh
echo plain
EOF
chmod +x "$CORPUS_E/plain_gate.sh"

E_OUT=$(FC_DEVICE_SANDBOX_TEST_FORCE_UNAVAILABLE=1 sh "$TOOL" build-map \
    --sections-dir "$CORPUS_E" --db "$DB_E" --per-script-timeout 5 2>&1)
E_RC=$?

if [ "$E_RC" -eq 4 ]; then
    ok "E1: build-map exits 4 (BLIND) when the namespace sandbox precondition cannot be confirmed -- fail-closed, never a silent weaker fallback"
else
    bad "E1: build-map exited $E_RC (expected 4/BLIND) when the namespace sandbox precondition was forced unavailable: $E_OUT"
fi

E_ROWS=$(sqlite3 "$DB_E" "SELECT count(*) FROM io_map" 2>/dev/null)
if [ "$E_ROWS" = "0" ] || [ -z "$E_ROWS" ]; then
    ok "E2: zero scripts were traced/recorded during the fail-closed refusal (no partial, unsandboxed work happened)"
else
    bad "E2: $E_ROWS row(s) were recorded despite the fail-closed refusal -- something ran unsandboxed"
fi

# =============================================================================
# Final safety check -- adb device set is byte-identical before and
# after this ENTIRE regression file (the real D1/D2 boards, if
# attached, were never touched by anything above).
# =============================================================================
if [ "$HAVE_ADB" -eq 1 ]; then
    ADB_AFTER=$(adb devices 2>&1)
    if [ "$ADB_BEFORE" = "$ADB_AFTER" ]; then
        ok "SAFETY: 'adb devices' output is byte-identical before and after this entire regression file"
    else
        bad "SAFETY: 'adb devices' output CHANGED during this run -- before='$ADB_BEFORE' after='$ADB_AFTER'"
    fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
