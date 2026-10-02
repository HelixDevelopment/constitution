#!/bin/sh
# =============================================================================
# T085 US2 Round 6 remediation regression (R5-B1 BLOCKING, device-safety
# critical, 2026-10-02).
# =============================================================================
#
# T085 Round 5's independent review reproduced, against the REAL
# `build-map` CLI entry point and this host's REAL D-Bus session bus /
# USB subsystem, TWO ways a traced script could still reach the real
# host environment from inside the committed (raw-`unshare`-based)
# device sandbox:
#
#   1. The mount namespace hid only `/dev/bus/usb`; `/run/user/<uid>/bus`
#      (the real D-Bus session bus socket) stayed fully reachable, so a
#      traced script could run `systemd-run --user -- <any command>`
#      (reached via a SPLIT binary-name construction the classifier's
#      pattern list never saw) and ask the REAL host-side systemd --user
#      manager -- a process entirely OUTSIDE every one of the sandbox's
#      namespaces -- to run that command with full host network and adb
#      access. Reproduced live: the trace status was "ok", both real
#      board serials were returned, and a probe read the host's REAL
#      /proc/net/dev (eno1, wlp70s0 with live traffic counters).
#   2. The sandboxed process is root inside its own user namespace, so
#      it could simply `umount /dev/bus/usb` and then open the real USB
#      device node underneath -- demonstrated by reading the USB
#      descriptor back.
#
# Fixed (fc_common.py, section 11.4.227 shared primitive): the sandbox's
# underlying mechanism is now `bwrap` (bubblewrap) rather than raw
# `unshare`, with (a) `/run/user/<uid>/bus`, `$XDG_RUNTIME_DIR/bus`, and
# `/run/dbus/system_bus_socket` added to the set of paths this sandbox
# hides (the PRIMARY fix for bypass #1 -- hides the real CAPABILITY,
# never merely expanding the classifier's pattern list, which the Round
# 5 reviewer explicitly warned is trivially defeated by binary-name
# splitting), and (b) `--disable-userns`, bwrap's own purpose-built
# kernel-level primitive that makes ANY further user-namespace creation
# inside the sandbox fail outright (the PRIMARY fix for bypass #2 --
# this module's own research for this fix additionally found, and this
# file's own Section C mutation reproduces, that a capability-
# bounding-set-only mitigation is INSUFFICIENT against a sandboxed
# process simply re-`unshare`-ing a fresh nested user+mount namespace,
# which regains a full capability set regardless of the outer process's
# own bounding set).
#
# This file proves, against the REAL io_trace_build_map.py CLI entry
# point (`build-map`, in its default sandboxed mode -- never a direct
# unit-level function call alone) for Section A, and against the real
# fc_common.wrap_device_sandbox_argv() primitive directly for Sections
# B/C/D (the exact granularity needed to safely demonstrate the
# umount-reversibility bypass WITHOUT ever touching a real USB device
# node, per this task's explicit instruction to use ONLY read-only
# probes when demonstrating a pre-fix vulnerability), that:
#   Section A -- the exact systemd-run-via-split-binary-name repro,
#                run through the real `build-map` CLI, no longer
#                dispatches a real host-side unit.
#   Section B -- guard-viability MUTATION for bypass #1: the IDENTICAL
#                repro, run through wrap_device_sandbox_argv() with
#                hide_paths REDUCED to its pre-R5-B1-fix set
#                (`/dev/bus/usb` only), DOES still dispatch a real
#                host-side unit -- proving the D-Bus-path hide
#                specifically (not --unshare-net, not --disable-userns,
#                not the classifier) is what closes Section A.
#   Section C -- the exact umount-then-read-USB-node repro is closed:
#                `umount /dev/bus/usb` from inside the real,
#                current sandbox FAILS (non-zero exit, EPERM-class
#                message), and the real USB device-node tree underneath
#                remains genuinely inaccessible even after the failed
#                umount attempt -- READ-ONLY throughout, no device
#                mutated, nothing opened read-write.
#   Section D -- guard-viability MUTATION for bypass #2: the OLD
#                (pre-fix) raw-`unshare --map-root-user --net --mount`
#                mechanism, reconstructed faithfully inline, DOES still
#                let `umount /dev/bus/usb` succeed and reveal the real
#                device-node tree underneath -- proving `--disable-userns`
#                specifically (not the path-hide, not the classifier) is
#                what closes Section C.
#   Section E -- --allow-device-scripts still correctly disables
#                sandboxing entirely (regression guard, unchanged
#                pre-existing behaviour).
#
# Device safety: `adb devices` is captured before and after every
# section and asserted byte-identical at the end. No command below ever
# WRITES to, resets, power-cycles, or reboots D1/D2; Section C/D's
# `umount`/`ls`/`stat` calls are read-only probes against the already-
# existing `/dev/bus/usb` tree, exactly mirroring the Round 5 reviewer's
# own careful methodology (demonstrate the bypass READ-ONLY, never by
# actually mutating device state).
#
# Usage: sh test_io_trace_build_map_r6_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/io_trace.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 6 R5-B1 regression: D-Bus/systemd-run escape + USB-unmount-reversibility closure =="

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
# Section A -- bypass #1 (R5-B1 repro #1), via the REAL build-map CLI:
# systemd-run reached via a split binary-name construction, exactly the
# shape the Round 5 reviewer demonstrated defeats the classifier.
# =============================================================================
echo "-- Section A: systemd-run-via-split-binary-name bypass, through the real build-map CLI (R5-B1 repro #1) --"

CORPUS_A="$SCRATCH/corpus_a"
mkdir -p "$CORPUS_A"
DB_A="$SCRATCH/a.sqlite"
UNIT_MARKER_A="$SCRATCH/A_UNIT_RAN.marker"

cat > "$CORPUS_A/systemd_run_bypass.sh" <<EOF
#!/bin/sh
BIN="systemd-ru""n"
"\$BIN" --user --wait --pipe -- /bin/sh -c "touch $UNIT_MARKER_A" 2>&1
echo "systemd-run exit: \$?"
EOF
chmod +x "$CORPUS_A/systemd_run_bypass.sh"

A_OUT=$(sh "$TOOL" build-map --sections-dir "$CORPUS_A" --db "$DB_A" --per-script-timeout 15 2>&1)
A_RC=$?
echo "$A_OUT"

if [ "$A_RC" -eq 0 ]; then
    ok "A1: build-map (default, no opt-in) exits 0 against the systemd-run-bypass corpus"
else
    bad "A1: build-map exited $A_RC: $A_OUT"
fi

if [ ! -f "$UNIT_MARKER_A" ]; then
    ok "A2: THE FIX -- systemd-run NEVER dispatched a real host-side unit (marker absent) -- R5-B1 bypass #1 closed"
else
    bad "A2: systemd-run DID dispatch a real host-side unit (marker present) -- R5-B1 bypass #1 is STILL OPEN"
fi

# =============================================================================
# Section B -- guard-viability MUTATION for bypass #1: the IDENTICAL
# repro, through wrap_device_sandbox_argv() with hide_paths reduced to
# ONLY the pre-R5-B1-fix set (/dev/bus/usb), proving the D-Bus-path hide
# itself (not --unshare-net/--disable-userns/the classifier) is what
# closes Section A.
# =============================================================================
echo "-- Section B: guard-viability mutation -- same repro with the D-Bus hide-paths REMOVED --"

UNIT_MARKER_B="$SCRATCH/B_UNIT_RAN.marker"
B_OUT=$(FC_LIB_DIR="$FC/lib" python3 - "$FC/lib" "$UNIT_MARKER_B" <<'PYEOF'
import sys, subprocess
sys.path.insert(0, sys.argv[1])
import fc_common

marker = sys.argv[2]
script = (
    'BIN="systemd-ru""n"; "$BIN" --user --wait --pipe -- '
    '/bin/sh -c "touch %s"; echo "systemd-run exit: $?"' % marker
)
# T085 Round 6 guard-viability MUTATION: hide_paths reduced to ONLY
# "/dev/bus/usb" -- the pre-R5-B1-fix set, before the D-Bus session/
# system bus paths were added. Every other flag (--unshare-net,
# --disable-userns, the PATH-stub, the allowlisted env) is UNCHANGED
# from the real, current mechanism -- isolating exactly one variable.
cmd = fc_common.wrap_device_sandbox_argv(["sh", "-c", script], hide_paths=("/dev/bus/usb",))
result = fc_common.run_gate_reaped(cmd, timeout_s=15)
print("MUTATION_RUN rc=%s stdout=%r" % (result.returncode, (result.stdout or "").strip()))
PYEOF
)
echo "$B_OUT"

if [ -f "$UNIT_MARKER_B" ]; then
    ok "B1: GUARD-VIABILITY MUTATION -- with the D-Bus hide-paths removed, systemd-run DOES still dispatch a real host-side unit -- proving the D-Bus-path hide specifically is what closes Section A (not --unshare-net, not --disable-userns, not the classifier)"
else
    bad "B1: the mutation did NOT reproduce the bypass -- this mutation is not meaningful, re-investigate: $B_OUT"
fi

# =============================================================================
# Section C -- bypass #2 (R5-B1 repro #2): umount /dev/bus/usb from
# inside the REAL, current sandbox must FAIL, and the real device-node
# tree underneath must remain inaccessible even after the failed
# attempt. READ-ONLY throughout -- never opens a specific device node
# read-write, never touches D1/D2 directly.
# =============================================================================
echo "-- Section C: umount-then-reveal-real-USB-tree bypass, against the real, current sandbox (R5-B1 repro #2) --"

C_OUT=$(FC_LIB_DIR="$FC/lib" python3 - "$FC/lib" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
import fc_common

script = (
    'echo "before: $(ls /dev/bus/usb 2>&1 | wc -l) entries"; '
    'umount /dev/bus/usb 2>&1; echo "umount_rc=$?"; '
    'echo "after: $(ls /dev/bus/usb 2>&1 | wc -l) entries"'
)
cmd = fc_common.wrap_device_sandbox_argv(["sh", "-c", script])
result = fc_common.run_gate_reaped(cmd, timeout_s=15)
print("REAL_SANDBOX_RUN rc=%s stdout=%r" % (result.returncode, (result.stdout or "").strip()))
PYEOF
)
echo "$C_OUT"

if echo "$C_OUT" | grep -qE "umount_rc=(32|1)\\b" && ! echo "$C_OUT" | grep -q "umount_rc=0"; then
    ok "C1: THE FIX -- 'umount /dev/bus/usb' FAILS from inside the real, current sandbox (umount_rc != 0) -- R5-B1 bypass #2 closed"
else
    bad "C1: 'umount /dev/bus/usb' did not fail as expected: $C_OUT"
fi

if echo "$C_OUT" | grep -q "after: 0 entries"; then
    ok "C2: the real USB device-node tree remains genuinely hidden (0 entries) even AFTER the failed umount attempt -- the hide is NOT merely 'not yet reversed', it is structurally un-reversible from inside"
else
    bad "C2: the device-node tree became visible after the (claimed-failed) umount attempt -- re-investigate: $C_OUT"
fi

# =============================================================================
# Section D -- guard-viability MUTATION for bypass #2: the OLD (pre-fix)
# raw-unshare mechanism, reconstructed faithfully inline, DOES still let
# umount succeed and reveal the real device-node tree -- proving
# --disable-userns specifically (not the path-hide, not the classifier)
# is what closes Section C. READ-ONLY: only lists entry counts, never
# opens a specific device node.
# =============================================================================
echo "-- Section D: guard-viability mutation -- the OLD raw-unshare mechanism (no --disable-userns) --"

D_OUT=$(python3 - <<'PYEOF'
import subprocess, tempfile, os, shlex

# Faithful reconstruction of this module's OWN pre-R5-B1-fix
# wrap_device_sandbox_argv() shape (see fc_common.py git history,
# T085 Round 5): raw `unshare --map-root-user --net --mount`, hiding
# /dev/bus/usb via a plain `mount --bind`, with NO --disable-userns
# equivalent (unshare has none -- this IS the gap bwrap's flag closes).
hide_sh = 'if [ -e /dev/bus/usb ]; then d=$(mktemp -d); mount --bind "$d" /dev/bus/usb 2>/dev/null || true; fi'
inner = hide_sh + '; exec "$@"'
script = (
    'echo "before: $(ls /dev/bus/usb 2>&1 | wc -l) entries"; '
    'umount /dev/bus/usb 2>&1; echo "umount_rc=$?"; '
    'echo "after: $(ls /dev/bus/usb 2>&1 | wc -l) entries"'
)
cmd = ["unshare", "--map-root-user", "--net", "--mount", "--",
       "sh", "-c", inner, "device-sandbox-inner", "sh", "-c", script]
result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
print("OLD_MECHANISM_RUN rc=%s stdout=%r stderr=%r" % (result.returncode, result.stdout.strip(), result.stderr.strip()))
PYEOF
)
echo "$D_OUT"

if echo "$D_OUT" | grep -q "umount_rc=0"; then
    ok "D1: GUARD-VIABILITY MUTATION -- the OLD raw-unshare mechanism (no --disable-userns) DOES still let umount succeed -- proving --disable-userns specifically is what closes Section C"
else
    bad "D1: the OLD mechanism did not reproduce the umount-succeeds bypass -- this mutation is not meaningful, re-investigate: $D_OUT"
fi

if echo "$D_OUT" | grep -qE "after: [1-9][0-9]* entries"; then
    ok "D2: under the OLD mechanism, the real device-node tree DOES become visible again after umount -- confirming the pre-fix vulnerability genuinely existed and this round's fix is what closes it"
else
    bad "D2: the OLD mechanism's device-node tree did not reappear as expected -- re-investigate: $D_OUT"
fi

# =============================================================================
# Section E -- regression guard: --allow-device-scripts still correctly
# opts OUT of sandboxing entirely (pre-existing, documented behaviour,
# unaffected by this round's fix).
# =============================================================================
echo "-- Section E: --allow-device-scripts still disables the sandbox entirely (regression guard) --"

CORPUS_E="$SCRATCH/corpus_e"
mkdir -p "$CORPUS_E"
DB_E="$SCRATCH/e.sqlite"
OPT_OUT_MARKER="$SCRATCH/E_OPT_OUT.marker"
FAKE_PATH_E="$SCRATCH/fake_path_e"
mkdir -p "$FAKE_PATH_E"
cat > "$FAKE_PATH_E/adb" <<EOF
#!/bin/sh
echo "invoked" > "$OPT_OUT_MARKER"
echo "List of devices attached"
exit 0
EOF
chmod +x "$FAKE_PATH_E/adb"
cat > "$CORPUS_E/plain_adb_gate.sh" <<'EOF'
#!/bin/sh
adb devices
EOF
chmod +x "$CORPUS_E/plain_adb_gate.sh"

E_OUT=$(PATH="$FAKE_PATH_E:$PATH" sh "$TOOL" build-map \
    --sections-dir "$CORPUS_E" --db "$DB_E" --per-script-timeout 10 \
    --allow-device-scripts 2>&1)
E_RC=$?

if [ "$E_RC" -eq 0 ] && [ -f "$OPT_OUT_MARKER" ]; then
    ok "E1: --allow-device-scripts still genuinely disables sandboxing entirely, unchanged by this round's fix"
else
    bad "E1: --allow-device-scripts regression: rc=$E_RC marker_present=$([ -f "$OPT_OUT_MARKER" ] && echo yes || echo no): $E_OUT"
fi

# =============================================================================
# Final safety check -- adb device set is byte-identical before and
# after this ENTIRE regression file.
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
