#!/bin/sh
# =============================================================================
# T085 US2 Round 3 remediation regression (R3-B1 BLOCKING + R3-I1
# IMPORTANT, 2026-10-02).
# =============================================================================
#
# Proves, against the REAL io_trace.sh + io_trace_build_map.py (and,
# where noted, a scratch corpus this file constructs itself -- NEVER the
# real device/rockchip/rk3588/tests/ tree, per §11.4.199/§12/§11.4.225),
# the T085 Round 3 independent review's R3-B1 and R3-I1 findings:
#
#   R3-B1 (BLOCKING) -- the B-R2-3 device-safety classifier is a
#     text-only deny-list that, BY CONSTRUCTION, can never be complete;
#     the Round 3 reviewer measured 675/1244 of this project's REAL
#     device/rockchip/rk3588/tests/*.sh corpus classifying as NOT
#     device-mutating by text alone, including a real file
#     (test_api_proxy_pinning_census.sh) that reaches `adb -s <real D1
#     serial>` only through a sourced library's `ADB="${ADB:-adb}"`
#     variable. Fixed two ways:
#       (a) PRIMARY, defense-in-depth-proof: EVERY script build-map
#           actually hands to retrace() in the default (no
#           --allow-device-scripts) mode now runs inside a sandbox where
#           adb/fastboot/upgrade_tool/rkdeveloptool/uhubctl/tuya_control
#           are each replaced by a stub that never forwards to the real
#           binary -- this holds EVEN FOR a script the classifier cannot
#           possibly see through (demonstrated below with an obfuscated,
#           string-concatenation-constructed command name that contains
#           the literal substring "adb" NOWHERE in its source text).
#       (b) SECONDARY: the classifier's own patterns are widened to
#           catch every real, unflagged shape the review demonstrated.
#   R3-I1 (IMPORTANT, io_trace_build_map.py's half -- see
#     test_batch_bisect_r3_regression.sh for batch_bisect.py's half) --
#     retrace()'s process-group kill ran ONLY on the timeout path; a
#     gate backgrounding a detached grandchild and returning NORMALLY
#     left that grandchild running. Fixed: the whole group is now
#     killed on EVERY return path.
#
# Usage: sh test_io_trace_build_map_r3_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REPO_ROOT=$(cd "$FC/../../.." && pwd)
TOOL="$FC/gates/io_trace.sh"
BUILD_MAP_PY="$FC/gates/lib/io_trace_build_map.py"
REAL_CORPUS_FILE="$REPO_ROOT/device/rockchip/rk3588/tests/test_api_proxy_pinning_census.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 3 R3-B1/R3-I1 regression: io_trace_build_map.py classifier + sandbox + normal-return killpg =="

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
# Section A -- the EXACT real corpus file the Round 3 review named,
# classified READ-ONLY (never executed) through the REAL (now-fixed)
# classifier.
# =============================================================================
echo "-- Section A: the real test_api_proxy_pinning_census.sh, classified read-only --"

if [ -f "$REAL_CORPUS_FILE" ]; then
    A_OUT=$(python3 - "$BUILD_MAP_PY" "$REAL_CORPUS_FILE" <<'PYEOF'
import importlib.util
import sys

mod_path, real_file = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("io_trace_build_map", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

with open(real_file, "r", errors="replace") as fh:
    text = fh.read()

is_device, reason = mod.classify_device_mutating(text)
print("is_device_mutating=%s reason=%s" % (is_device, reason))
if not is_device:
    sys.exit(1)
PYEOF
)
    A_RC=$?
    echo "$A_OUT"
    if [ "$A_RC" -eq 0 ] && echo "$A_OUT" | grep -q "^is_device_mutating=True"; then
        ok "A1: the REAL test_api_proxy_pinning_census.sh (reaches adb only via a sourced \${ADB} variable) is now correctly classified device-mutating ($A_OUT)"
    else
        bad "A1: the real corpus file was NOT classified device-mutating -- R3-B1's exact reproduction is still unflagged: $A_OUT"
    fi
else
    echo "NOTE: $REAL_CORPUS_FILE not found on this checkout -- A1 SKIPPED (honest, not fabricated as pass)"
fi

# =============================================================================
# Section B -- classifier accuracy: every "unflagged shape" the Round 3
# review's own bullet list named, now correctly classified, PLUS a
# negative control proving genuinely-scratch-exempt rm -rf still is NOT
# over-flagged (the §11.4.201(1) false-positive guard).
# =============================================================================
echo "-- Section B: classifier accuracy against every R3-B1 unflagged shape --"

B_OUT=$(python3 - "$BUILD_MAP_PY" <<'PYEOF'
import importlib.util
import sys

mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("io_trace_build_map", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# (label, script_text, expected_is_device_mutating)
cases = [
    ("rm-Rf-mixed-case",       "#!/bin/sh\nrm -Rf /opt/data\n",                               True),
    ("rm-rf-substring-work",   "#!/bin/sh\nrm -rf /srv/network_share\n",                      True),
    ("rm-rf-substring-tmp",    "#!/bin/sh\nrm -rf /var/tmp_important_data\n",                 True),
    ("rm-rf-substring-evid",   '#!/bin/sh\nrm -rf "$HOME"/Documents/evidence\n',               True),
    ("find-delete",            "#!/bin/sh\nfind / -name '*.log' -delete\n",                    True),
    ("bare-svc-verb",          "#!/bin/sh\nsvc wifi disable\n",                                True),
    ("reboot-in-identifier",   "#!/bin/sh\nsh ./helper_reboot.sh\n",                           True),
    ("sys-usb-authorized",     "#!/bin/sh\necho 0 > /sys/bus/usb/devices/1-1/authorized\n",    True),
    ("uhubctl",                "#!/bin/sh\nuhubctl -a off -p 2\n",                             True),
    ("systemctl-stop",         "#!/bin/sh\nsystemctl --user stop some.service\n",               True),
    ("kill-wide-signal",       "#!/bin/sh\nkill -9 -1\n",                                      True),
    ("adb-via-dollar-var",     '#!/bin/sh\nADB="${ADB:-adb}"\n"${ADB}" -s SER shell echo hi\n', True),
    # Negative controls -- must remain NOT flagged.
    ("rm-rf-scratch-var",      '#!/bin/sh\nTMPD=$(mktemp -d)\nrm -rf "$TMPD"\n',                False),
    ("rm-rf-tmp-literal",      "#!/bin/sh\nrm -rf /tmp/some/scratch/dir\n",                     False),
    ("benign-file-read",       "#!/bin/sh\ncat \"$(dirname \"$0\")/own_data.txt\"\n",            False),
]

failures = []
for label, text, expected in cases:
    is_device, reason = mod.classify_device_mutating(text)
    status = "OK" if is_device == expected else "MISMATCH"
    print("%s: label=%s expected=%s got=%s reason=%s" % (status, label, expected, is_device, reason))
    if is_device != expected:
        failures.append(label)

if failures:
    print("FAILURES: %s" % ",".join(failures))
    sys.exit(1)
print("ALL CASES CORRECT")
PYEOF
)
B_RC=$?
echo "$B_OUT"
if [ "$B_RC" -eq 0 ] && echo "$B_OUT" | grep -q "^ALL CASES CORRECT"; then
    ok "B1: every R3-B1 unflagged shape is now correctly classified device-mutating, and every genuine scratch-exempt / benign case remains correctly NOT flagged (false-positive guard)"
else
    bad "B1: classifier accuracy check failed -- see MISMATCH lines above: $B_OUT"
fi

# =============================================================================
# Section C -- PRIMARY defense proof: a script STRUCTURALLY INVISIBLE to
# the text classifier (the command name is built at runtime via string
# concatenation, "adb" never appears as a contiguous substring anywhere
# in the script's own source) is STILL unable to reach a real adb binary
# -- because every retraced script runs inside the device-reaching-
# binary sandbox regardless of what the classifier decided.
# =============================================================================
echo "-- Section C: sandbox defense for a script the classifier structurally cannot see through --"

CORPUS_C="$SCRATCH/corpus_c"
mkdir -p "$CORPUS_C"
DB_C="$SCRATCH/c.sqlite"
REAL_ADB_MARKER="$SCRATCH/REAL_ADB_INVOKED.marker"

# A "real-looking" adb on a system PATH location this test's own parent
# shell will prepend -- simulating a dev host with platform-tools
# installed. If the sandbox were absent or broken, THIS is what a
# device-mutating command would actually reach.
FAKE_SYSTEM_PATH="$SCRATCH/fake_system_path"
mkdir -p "$FAKE_SYSTEM_PATH"
cat > "$FAKE_SYSTEM_PATH/adb" <<EOF
#!/bin/sh
echo "REAL adb invoked with: \$*" > "$REAL_ADB_MARKER"
exit 0
EOF
chmod +x "$FAKE_SYSTEM_PATH/adb"

# Pre-check: confirm this script's command-name construction is genuinely
# invisible to classify_device_mutating() -- the test's own premise.
cat > "$CORPUS_C/obfuscated_adb_gate.sh" <<'EOF'
#!/bin/sh
set -eu
TOOLNAME="${TOOLNAME:-ad}""b"
"$TOOLNAME" -s FAKE_SERIAL shell echo hacked
EOF
chmod +x "$CORPUS_C/obfuscated_adb_gate.sh"

PRECHECK_OUT=$(python3 - "$BUILD_MAP_PY" "$CORPUS_C/obfuscated_adb_gate.sh" <<'PYEOF'
import importlib.util
import sys

mod_path, script_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("io_trace_build_map", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

with open(script_path) as fh:
    text = fh.read()
is_device, reason = mod.classify_device_mutating(text)
print("is_device_mutating=%s reason=%s" % (is_device, reason))
sys.exit(0 if is_device is False else 1)
PYEOF
)
PRECHECK_RC=$?
if [ "$PRECHECK_RC" -eq 0 ]; then
    ok "C0 (premise check): the obfuscated gate script is genuinely NOT classified device-mutating by text alone ($PRECHECK_OUT) -- this IS the 'unflagged path' R3-B1 requires testing"
else
    bad "C0 (premise check): the obfuscated gate unexpectedly WAS classified device-mutating ($PRECHECK_OUT) -- this test no longer exercises the unflagged path it's meant to; its construction needs revisiting"
fi

# Run the REAL io_trace.sh build-map, default mode (no
# --allow-device-scripts), with the fake-real-adb directory prepended to
# THIS shell's own PATH (the environment build-map's own process
# inherits from) -- proving the sandbox wins over an inherited PATH
# entry, not merely over an empty one.
C_OUT=$(PATH="$FAKE_SYSTEM_PATH:$PATH" sh "$TOOL" build-map --sections-dir "$CORPUS_C" --db "$DB_C" --per-script-timeout 5 2>&1)
C_RC=$?

if [ "$C_RC" -eq 0 ]; then
    ok "C1: build-map (default, no opt-in) exits 0 against the obfuscated-gate corpus"
else
    bad "C1: build-map exited $C_RC: $C_OUT"
fi

TRACE_STATUS_C=$(sqlite3 "$DB_C" "SELECT trace_status FROM io_map WHERE script_path LIKE '%obfuscated_adb_gate.sh'" 2>/dev/null)
if [ "$TRACE_STATUS_C" != "skipped-device" ] && [ -n "$TRACE_STATUS_C" ]; then
    ok "C2: the obfuscated gate was genuinely RETRACED (trace_status='$TRACE_STATUS_C'), NOT skipped by the classifier -- confirming this run exercised the classifier's own blind spot, not merely the deny-list path"
else
    bad "C2: the obfuscated gate's trace_status is '$TRACE_STATUS_C' -- either not recorded at all, or (unexpectedly) classified skipped-device, meaning this run did not actually exercise the unflagged-path sandbox defense"
fi

if [ ! -f "$REAL_ADB_MARKER" ]; then
    ok "C3: the REAL (fake-system-PATH) adb was NEVER invoked -- the sandbox stub intercepted the obfuscated command name instead, even though the classifier could not see it coming. THE R3-B1 PRIMARY FIX."
else
    bad "C3: the REAL adb WAS invoked (marker: $(cat "$REAL_ADB_MARKER" 2>/dev/null)) -- the sandbox did NOT intercept the obfuscated command, R3-B1 is still open"
fi

# =============================================================================
# Section D -- R3-I1 (io_trace_build_map.py half): retrace()'s
# process-group kill now applies on a NORMAL (non-timeout) return too,
# not only on timeout -- deterministic fake --tool stub, never
# strace/timing-dependent (mirrors the Round 2 regression's own Section
# B convention).
# =============================================================================
echo "-- Section D: retrace() kills a backgrounded grandchild even on a normal (non-timeout) return --"

CORPUS_D="$SCRATCH/corpus_d"
mkdir -p "$CORPUS_D"
DB_D="$SCRATCH/d.sqlite"
ORPHAN_MARKER="$SCRATCH/orphan_d.marker"
ORPHAN_PIDFILE="$SCRATCH/orphan_d.pid"

cat > "$CORPUS_D/normal_orphan_gate.sh" <<'EOF'
#!/bin/sh
# Never actually executed by this section -- fake_tool_d.sh below
# inspects the script PATH only, classifying by filename, and performs
# the background-spawn itself in the fake tool's OWN process (which
# retrace() places in its own process group via start_new_session=True,
# exactly as it would the real `sh io_trace.sh trace <script>` chain).
echo plain
EOF
chmod +x "$CORPUS_D/normal_orphan_gate.sh"

cat > "$SCRATCH/fake_tool_d.sh" <<EOF
#!/bin/sh
case "\$2" in
    */normal_orphan_gate.sh)
        ( sleep 2; echo done > "$ORPHAN_MARKER" ) >/dev/null 2>&1 &
        echo \$! > "$ORPHAN_PIDFILE"
        echo '{"reads": [], "writes": []}'
        exit 0
        ;;
    *)
        echo '{"reads": [], "writes": []}'
        ;;
esac
EOF
chmod +x "$SCRATCH/fake_tool_d.sh"

D_OUT=$(python3 "$BUILD_MAP_PY" --sections-dir "$CORPUS_D" --db "$DB_D" \
    --tool "$SCRATCH/fake_tool_d.sh" --per-script-timeout 10 --allow-device-scripts 2>&1)
D_RC=$?

if [ "$D_RC" -eq 0 ]; then
    ok "D1: build-map (fake tool) exits 0 against normal_orphan_gate.sh (a normal, non-timeout trace)"
else
    bad "D1: build-map (fake tool) exited $D_RC: $D_OUT"
fi

if [ -f "$ORPHAN_PIDFILE" ]; then
    ORPHAN_PID=$(cat "$ORPHAN_PIDFILE")
    i=0
    while [ "$i" -lt 10 ] && kill -0 "$ORPHAN_PID" 2>/dev/null; do
        sleep 0.2
        i=$((i + 1))
    done
    if kill -0 "$ORPHAN_PID" 2>/dev/null; then
        bad "D2: the backgrounded grandchild (PID $ORPHAN_PID) is STILL RUNNING after retrace()'s normal return -- the R3-I1 bug"
        kill -9 "$ORPHAN_PID" 2>/dev/null
    else
        ok "D2: the backgrounded grandchild (PID $ORPHAN_PID) was killed by retrace()'s own normal-return group-kill, never left running"
    fi
else
    bad "D2: normal_orphan_gate.sh's pidfile was never written -- fake_tool_d.sh contract broken or the case was never reached"
fi

if [ ! -f "$ORPHAN_MARKER" ]; then
    ok "D3: the backgrounded grandchild's own marker file was NEVER written (killed before its 2s sleep completed)"
else
    bad "D3: the backgrounded grandchild's marker file WAS written -- it ran to completion despite retrace()'s normal return, confirming the R3-I1 bug"
fi

# =============================================================================
# Final safety check -- adb device set is byte-identical before and after
# this ENTIRE regression file (the real D1/D2 boards, if attached, were
# never touched by anything above).
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
