#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (R4-I2 recurrence, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review found that batch_bisect.py's T085
# Round 3 run_gate_on_tree() fix (process-group-only reaping) was STILL
# incomplete: "a grandchild that calls setsid escapes the process-group
# kill. In batch_bisect it wrote its marker 2.5s after the call had
# returned PASS, which contradicts the docstring's claim that 'any
# detached grandchild' stays in the group."
#
# Fixed by routing run_gate_on_tree() through the ONE shared primitive,
# fc_common.run_gate_reaped() (section 11.4.227) -- a Linux cgroup v2
# scope per invocation, whose membership is INHERITED by every fork()
# and UNCHANGED by setsid()/exec() (unlike process-GROUP membership),
# so `cgroup.kill` genuinely reaches a setsid()-detached grandchild.
#
# This file proves, with a DETERMINISTIC (no-race) genuine-setsid-
# detachment fixture (mirrors
# test_fc_common_run_gate_reaped_r5_regression.sh's own technique: the
# grandchild calls os.setsid() itself -- a real, synchronous syscall,
# not a forked `setsid <cmd>` binary racing an external fork+exec), that
# run_gate_on_tree() no longer leaves a confirmed-detached grandchild
# running.
#
# Usage: sh test_batch_bisect_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/gates/batch_bisect.py"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "ok $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $1"; }

if [ ! -f "$TOOL" ]; then
    bad "control needle: $TOOL does not exist -- cannot regression-test it"
    exit 1
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

echo "-- run_gate_on_tree() reaps a GENUINELY setsid()-detached grandchild (R4-I2 recurrence) --"

OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile
import time

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect", mod_path)
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
        "with open(%r, 'w') as fh:\n"
        "    fh.write(str(os.getpid()))\n"
        "with open(%r, 'w') as fh:\n"
        "    fh.write(str(os.getpgid(0)))\n"
        "time.sleep(3)\n"
        "with open(%r, 'w') as fh:\n"
        "    fh.write('leaked')\n"
        % (pidfile, detach_confirm, marker)
    )
gate = os.path.join(scratch, "setsid_gate.sh")
with open(gate, "w") as fh:
    # 0.6s head start so the grandchild reliably completes its own
    # os.setsid() + confirmation write BEFORE this gate script itself
    # exits (which is what triggers run_gate_on_tree()'s own reaping) --
    # otherwise reaping could race the grandchild's own setsid() call
    # and kill it before genuine detachment ever completed, proving
    # nothing about a truly-detached process.
    fh.write(
        "#!/bin/sh\n%s %s >/dev/null 2>&1 &\nsleep 0.6\nexit 0\n"
        % (sys.executable, helper_py)
    )
os.chmod(gate, 0o755)

tree = tempfile.mkdtemp(dir=scratch)
verdict, rc = mod.run_gate_on_tree(gate, tree)
if verdict != "PASS" or rc != 0:
    print("FAIL: unexpected verdict=%s rc=%s (gate itself should PASS)" % (verdict, rc))
    sys.exit(1)

deadline = time.time() + 3
while time.time() < deadline and not os.path.exists(detach_confirm):
    time.sleep(0.05)
if not (os.path.exists(detach_confirm) and os.path.exists(pidfile)):
    print("FAIL: the grandchild never confirmed genuine setsid() detachment -- test premise broken")
    sys.exit(1)
with open(pidfile) as fh:
    gpid = int(fh.read().strip())
with open(detach_confirm) as fh:
    gpgid = fh.read().strip()
print("INFO: grandchild genuinely detached, pid=%d pgid=%s" % (gpid, gpgid))

time.sleep(3.2)  # the grandchild's own sleep(3) would complete by now if still alive
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
    print("FAIL: the GENUINELY setsid()-detached grandchild SURVIVED run_gate_on_tree()'s return (leaked=%s still_alive=%s) -- R4-I2 is STILL OPEN in batch_bisect.py" % (leaked, still_alive))
    sys.exit(1)

print("PASS: the genuinely setsid()-detached grandchild was reaped -- R4-I2 closed in batch_bisect.py")
sys.exit(0)
PYEOF
)
RC=$?
echo "$OUT"

if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q "^PASS:"; then
    ok "1: run_gate_on_tree() reaps a genuinely setsid()-detached grandchild (R4-I2 recurrence closed)"
else
    bad "1: run_gate_on_tree() did NOT reap a genuinely setsid()-detached grandchild: $OUT"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
