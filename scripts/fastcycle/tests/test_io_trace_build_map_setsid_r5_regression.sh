#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (R4-I2 recurrence, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review found the setsid-escape gap (see
# test_batch_bisect_r5_regression.sh's own header for the full citation)
# present at BOTH "already-fixed" T085 Round 3 sites -- this file is
# io_trace_build_map.py's half (batch_bisect.py's is the sibling file
# above). retrace() now delegates its whole launch/timeout/reap
# lifecycle to fc_common.run_gate_reaped() (section 11.4.227), which
# reaps via a Linux cgroup v2 scope when available -- cgroup membership
# is immune to setsid()/exec(), unlike the process-GROUP-only mechanism
# retrace() used before.
#
# Deterministic (no-race) genuine-setsid-detachment fixture, same
# technique as test_fc_common_run_gate_reaped_r5_regression.sh and
# test_batch_bisect_r5_regression.sh.
#
# Usage: sh test_io_trace_build_map_setsid_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
BUILD_MAP_PY="$FC/gates/lib/io_trace_build_map.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 R4-I2 recurrence regression: io_trace_build_map.py retrace() setsid-escape closure =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

OUT=$(python3 - "$BUILD_MAP_PY" "$SCRATCH" <<'PYEOF'
import importlib.util, os, sys, tempfile, time

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("io_trace_build_map", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

marker = os.path.join(scratch, "leaked")
detach_confirm = os.path.join(scratch, "detached")
pidfile = os.path.join(scratch, "pid")

helper_py = os.path.join(scratch, "helper.py")
with open(helper_py, "w") as fh:
    fh.write(
        "import os, time\n"
        "os.setsid()\n"
        "with open(%r, 'w') as fh:\n    fh.write(str(os.getpid()))\n"
        "with open(%r, 'w') as fh:\n    fh.write(str(os.getpgid(0)))\n"
        "time.sleep(3)\n"
        "with open(%r, 'w') as fh:\n    fh.write('leaked')\n"
        % (pidfile, detach_confirm, marker)
    )

# A fake --tool stub: `trace` subcommand backgrounds the setsid helper,
# gives it a 0.6s head start to genuinely detach, then returns a valid
# {"reads":[],"writes":[]} result -- exercising retrace() exactly as
# io_trace.sh's own `trace` subcommand would, without needing strace or
# a real device-adjacent script.
fake_tool = os.path.join(scratch, "fake_tool.sh")
with open(fake_tool, "w") as fh:
    fh.write(
        "#!/bin/sh\n"
        "case \"$2\" in\n"
        "    */target.sh)\n"
        "        %s %s >/dev/null 2>&1 &\n"
        "        sleep 0.6\n"
        "        echo '{\"reads\": [], \"writes\": []}'\n"
        "        exit 0\n"
        "        ;;\n"
        "esac\n" % (sys.executable, helper_py)
    )
os.chmod(fake_tool, 0o755)

target = os.path.join(scratch, "target.sh")
with open(target, "w") as fh:
    fh.write("#!/bin/sh\necho plain\n")
os.chmod(target, 0o755)

status, reads, writes = mod.retrace(fake_tool, target, timeout_s=10, env=None, use_namespace_sandbox=False)
if status != "ok":
    print("FAIL: unexpected retrace() status=%s (expected ok)" % status)
    sys.exit(1)

deadline = time.time() + 3
while time.time() < deadline and not os.path.exists(detach_confirm):
    time.sleep(0.05)
if not (os.path.exists(detach_confirm) and os.path.exists(pidfile)):
    print("FAIL: the grandchild never confirmed genuine setsid() detachment -- test premise broken")
    sys.exit(1)
with open(pidfile) as fh:
    gpid = int(fh.read().strip())

time.sleep(3.2)
leaked = os.path.exists(marker)
try:
    os.kill(gpid, 0)
    still_alive = True
except OSError:
    still_alive = False
finally:
    try:
        os.kill(gpid, 9)
    except OSError:
        pass

if leaked or still_alive:
    print("FAIL: the GENUINELY setsid()-detached grandchild SURVIVED retrace()'s return (leaked=%s still_alive=%s)" % (leaked, still_alive))
    sys.exit(1)

print("PASS: the genuinely setsid()-detached grandchild was reaped by retrace()")
sys.exit(0)
PYEOF
)
RC=$?
echo "$OUT"

if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^PASS:"; then
    ok "1: retrace() reaps a genuinely setsid()-detached grandchild (R4-I2 recurrence closed)"
else
    bad "1: retrace() did NOT reap a genuinely setsid()-detached grandchild: $OUT"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
