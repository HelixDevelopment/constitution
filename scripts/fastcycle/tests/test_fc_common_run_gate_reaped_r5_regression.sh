#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (R4-I2 IMPORTANT, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review found the T085 Round 2/3 process-
# group reaping fix (fc_common.safe_killpg(), start_new_session=True)
# applied at only TWO of NINE real gate-execution sites
# (io_trace_build_map.py's retrace(), batch_bisect.py's
# run_gate_on_tree()) -- the other seven (gate_audit.run_gate,
# gate_runner_shard run-shard, catchset_compare x2, flake_ledger,
# gate_runner_order, backstop_run) each independently ran a bare
# `subprocess.run(cmd, timeout=...)` with NO process isolation.
#
# WORSE: even the two "already-fixed" sites had a gap process-group-only
# reaping can never close -- a grandchild that calls `setsid()` leaves
# the traced process's own process group entirely (a brand-new session
# + group), so `killpg()` cannot reach it. Reproduced live in
# batch_bisect ("wrote its marker 2.5s after the call had already
# returned PASS").
#
# Fixed with ONE shared primitive, fc_common.run_gate_reaped() (section
# 11.4.227), that reaps via a Linux cgroup v2 "scope" per invocation --
# cgroup membership, unlike process-GROUP membership, is INHERITED by
# every fork() and UNCHANGED by setsid()/exec(); writing "1" to that
# cgroup's `cgroup.kill` file kills every member unconditionally. Falls
# back, honestly (never silently), to the pre-existing process-group-
# only mechanism on a host without cgroup v2 delegation.
#
# This file proves, with a DETERMINISTIC (no-race) genuine-setsid-
# detachment fixture, that run_gate_reaped() closes the gap when a
# cgroup v2 scope is available, and HONESTLY documents (never hides)
# that the process-group-only fallback retains the pre-existing R4-I2
# limitation when cgroups are forced unavailable.
#
# Usage: sh test_fc_common_run_gate_reaped_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 R4-I2 regression: fc_common.run_gate_reaped() cgroup-based setsid-escape closure =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

RESULT=$(FC_LIB_DIR="$FC/lib" python3 - "$FC/lib" "$SCRATCH" <<'PYEOF'
import sys, os, tempfile, time

sys.path.insert(0, sys.argv[1])
import fc_common

scratch_root = sys.argv[2]


def run_setsid_leak_test(force_unavailable):
    scratch = tempfile.mkdtemp(dir=scratch_root)
    marker = os.path.join(scratch, "leaked")
    detach_confirm = os.path.join(scratch, "detached")
    pidfile = os.path.join(scratch, "pid")

    # The grandchild helper calls os.setsid() itself (a REAL, SYNCHRONOUS
    # syscall -- no race against an external fork+exec+setsid-binary
    # sequence), confirms genuine detachment BEFORE sleeping, so this
    # test can deterministically wait for confirmed detachment before
    # ever asking whether reaping caught it.
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
    script = os.path.join(scratch, "gate.sh")
    with open(script, "w") as fh:
        # The gate script's own 0.6s sleep gives the backgrounded
        # grandchild a deterministic head start to complete its
        # os.setsid() + write its detachment confirmation BEFORE the
        # gate script itself exits (which is what triggers
        # run_gate_reaped()'s own reaping) -- otherwise reaping can
        # race the grandchild's own setsid() call and kill it before
        # detachment ever completes, which would prove nothing about
        # whether a GENUINELY detached process is reaped.
        fh.write(
            "#!/bin/sh\n%s %s >/dev/null 2>&1 &\nsleep 0.6\necho gate-ran\nexit 0\n"
            % (sys.executable, helper_py)
        )
    os.chmod(script, 0o755)

    if force_unavailable:
        os.environ["FC_CGROUP_RUNNER_TEST_FORCE_UNAVAILABLE"] = "1"
    else:
        os.environ.pop("FC_CGROUP_RUNNER_TEST_FORCE_UNAVAILABLE", None)
    fc_common._cgroup_runner_available_cache = None

    result = fc_common.run_gate_reaped(["sh", script], timeout_s=10)

    deadline = time.time() + 3
    while time.time() < deadline and not os.path.exists(detach_confirm):
        time.sleep(0.05)
    detached = os.path.exists(detach_confirm) and os.path.exists(pidfile)

    time.sleep(3.2)  # the grandchild's own sleep(3) would complete by now if still alive
    leaked = os.path.exists(marker)
    still_alive = False
    if detached:
        with open(pidfile) as fh:
            gpid = int(fh.read().strip())
        try:
            os.kill(gpid, 0)
            still_alive = True
        except OSError:
            still_alive = False
        try:
            os.kill(gpid, 9)
        except OSError:
            pass
    return result.mechanism, detached, leaked, still_alive, result.returncode, (result.stdout or "").strip()


mech_c, detached_c, leaked_c, alive_c, rc_c, out_c = run_setsid_leak_test(False)
print("CGROUP_RUN mechanism=%s detached=%s leaked=%s alive=%s rc=%s stdout=%r"
      % (mech_c, detached_c, leaked_c, alive_c, rc_c, out_c))

mech_p, detached_p, leaked_p, alive_p, rc_p, out_p = run_setsid_leak_test(True)
print("PGROUP_RUN mechanism=%s detached=%s leaked=%s alive=%s rc=%s stdout=%r"
      % (mech_p, detached_p, leaked_p, alive_p, rc_p, out_p))
PYEOF
)
echo "$RESULT"

CGROUP_LINE=$(echo "$RESULT" | grep "^CGROUP_RUN")
PGROUP_LINE=$(echo "$RESULT" | grep "^PGROUP_RUN")

if echo "$CGROUP_LINE" | grep -q "mechanism=cgroup"; then
    ok "1: cgroup mechanism genuinely selected (cgroup v2 delegation confirmed available on this host)"
else
    bad "1: expected mechanism=cgroup on this host, got: $CGROUP_LINE"
fi

if echo "$CGROUP_LINE" | grep -q "detached=True"; then
    ok "2: the grandchild genuinely confirmed setsid() detachment before reaping began (test premise is sound, not a race)"
else
    bad "2: the grandchild never confirmed genuine detachment -- test premise broken, results below are not meaningful: $CGROUP_LINE"
fi

if echo "$CGROUP_LINE" | grep -q "leaked=False" && echo "$CGROUP_LINE" | grep -q "alive=False"; then
    ok "3: THE FIX -- with the cgroup mechanism, a GENUINELY setsid()-detached grandchild is still killed (never leaked, never left running) -- R4-I2 closed"
else
    bad "3: the setsid-detached grandchild LEAKED or is still alive under the cgroup mechanism -- R4-I2 is NOT closed: $CGROUP_LINE"
fi

if echo "$CGROUP_LINE" | grep -q "rc=0" && echo "$CGROUP_LINE" | grep -q "stdout='gate-ran'"; then
    ok "4: the gate's own normal output (rc=0, stdout='gate-ran') is reported correctly through the cgroup-wrapped invocation"
else
    bad "4: the gate's own rc/stdout were not reported correctly through the cgroup wrapper: $CGROUP_LINE"
fi

if echo "$PGROUP_LINE" | grep -q "mechanism=process-group"; then
    ok "5: the FC_CGROUP_RUNNER_TEST_FORCE_UNAVAILABLE escape hatch genuinely forces the process-group-only fallback"
else
    bad "5: expected mechanism=process-group when forced unavailable, got: $PGROUP_LINE"
fi

if echo "$PGROUP_LINE" | grep -q "detached=True"; then
    ok "6: the fallback-path grandchild also genuinely confirmed detachment (apples-to-apples comparison)"
else
    bad "6: the fallback-path grandchild never confirmed genuine detachment -- comparison is not meaningful: $PGROUP_LINE"
fi

if echo "$PGROUP_LINE" | grep -q "leaked=True"; then
    ok "7: HONEST BOUNDARY documented -- without cgroup v2 (forced-unavailable fallback), a setsid()-detached grandchild DOES still leak, exactly as the pre-existing R3 mechanism always did; run_gate_reaped() never silently claims a stronger guarantee than what actually ran (its own .mechanism field told the truth in check 5)"
else
    bad "7: unexpected -- the process-group-only fallback did NOT leak the setsid grandchild; either the test environment changed or the fallback is stronger than documented (re-investigate, do not just celebrate)"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
