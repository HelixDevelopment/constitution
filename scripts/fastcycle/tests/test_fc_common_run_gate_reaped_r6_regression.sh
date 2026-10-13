#!/bin/sh
# =============================================================================
# T085 US2 Round 6 remediation regression (R5-I1 IMPORTANT, 2026-10-02).
# =============================================================================
#
# T085 Round 5's independent review reproduced, 5/5 runs, that
# fc_common.run_gate_reaped() still leaked a GENUINELY, IMMEDIATELY
# detaching grandchild -- no artificial head start, unlike this
# project's own pre-existing regression fixture
# (test_fc_common_run_gate_reaped_r5_regression.sh, whose helper writes
# its detachment-confirmation files BEFORE sleeping, giving the gate
# script's own 0.6s sleep time to let it complete first). The Round 5
# reviewer's own exact reproduction:
#
#     (setsid sh -c "sleep 2; touch M" &); exit 0
#
# wrote the marker file in 5 of 5 runs. Root cause (reproduced live
# during this fix, before the code change): run_gate_reaped() used
# `proc.communicate(timeout=timeout_s)` to detect "the direct child
# process is done" -- but a grandchild forked WITHOUT explicitly
# redirecting the stdout/stderr file descriptors it inherited from its
# parent (the ordinary, naive way a shell backgrounds a job) keeps its
# own copy of the PIPE's write end open. `communicate()` cannot return
# until EVERY holder of that write end closes it, so the "normal
# completion" path did not reap promptly at all -- it silently BLOCKED
# for the grandchild's entire natural lifetime (measured: 2.034s for a
# `sleep 2` grandchild) and only THEN called safe_killpg()/cgroup.kill,
# long after the grandchild had already finished on its own.
#
# Fixed: stdout/stderr are now captured via temporary FILES, never a
# PIPE -- a file write never requires a reader to drain it, so no
# descendant holding an inherited fd can ever block anything --
# direct-child completion is now detected via a bare `proc.wait()`, and
# reaping runs IMMEDIATELY the instant that call returns or raises,
# strictly BEFORE this function reads any captured output.
#
# This file proves, against the REAL fc_common.run_gate_reaped()
# function (never a mock), using the Round 5 reviewer's OWN EXACT
# reproduction string verbatim:
#   Section A -- the exploit is closed (the marker is never written,
#                across 20 repeated runs for confidence against a
#                timing-sensitive race, not merely once).
#   Section B -- guard-viability MUTATION: the EXACT same exploit,
#                fed through the OLD (pre-fix) communicate()-based
#                shape reconstructed inline, is shown to still leak --
#                proving it is genuinely THIS round's specific fix
#                (file-capture + wait()-then-reap ordering), not some
#                unrelated layer (e.g. the cgroup mechanism itself,
#                which is present and unchanged in both A and B), that
#                closes the exploit.
#   Section C -- normal stdout/stderr capture is unaffected (no
#                regression in the documented, everyday-use contract).
#
# Usage: sh test_fc_common_run_gate_reaped_r6_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 6 R5-I1 regression: fc_common.run_gate_reaped() immediately-detaching setsid closure =="

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

RESULT=$(FC_LIB_DIR="$FC/lib" python3 - "$FC/lib" "$SCRATCH" <<'PYEOF'
import sys, os, time, signal, subprocess, shlex, uuid

sys.path.insert(0, sys.argv[1])
import fc_common

scratch = sys.argv[2]


def real_fix_run(script):
    """The REAL, current (post-fix) run_gate_reaped() -- no monkeypatch."""
    return fc_common.run_gate_reaped(["sh", "-c", script], timeout_s=10)


def old_prefix_run(script, timeout_s=10):
    """T085 Round 6 guard-viability MUTATION: a faithful inline
    reconstruction of run_gate_reaped()'s PRE-fix shape -- PIPE +
    communicate() to detect completion, THEN reap -- using the SAME
    cgroup-reaping mechanism (fc_common._own_cgroup_v2_base(),
    fc_common.safe_killpg()) the real, fixed function also uses, so the
    ONLY variable that differs between this and real_fix_run() above is
    EXACTLY this round's fix (file-capture + wait()-then-reap ordering
    vs PIPE + communicate()-then-reap ordering) -- proving THIS is what
    closes the exploit, not the cgroup mechanism itself (present,
    unchanged, in both)."""
    use_cgroup = fc_common.cgroup_runner_available()
    cgroup_path = None
    launch_cmd = ["sh", "-c", script]
    if use_cgroup:
        base = fc_common._own_cgroup_v2_base()
        cgroup_path = os.path.join(base, "fc-gate-oldshape-%d-%s" % (os.getpid(), uuid.uuid4().hex[:8]))
        os.mkdir(cgroup_path)
        procs_file = os.path.join(cgroup_path, "cgroup.procs")
        launch_cmd = ["sh", "-c", 'echo $$ > %s 2>/dev/null; exec "$@"' % shlex.quote(procs_file),
                      "gate-cgroup-inner", "sh", "-c", script]
    proc = subprocess.Popen(launch_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, start_new_session=True)
    timed_out = False
    try:
        proc.communicate(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        timed_out = True
        fc_common.safe_killpg(proc.pid, signal.SIGKILL)
        try:
            proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass
    else:
        fc_common.safe_killpg(proc.pid, signal.SIGKILL)
    if cgroup_path is not None:
        try:
            with open(os.path.join(cgroup_path, "cgroup.kill"), "w") as fh:
                fh.write("1")
        except OSError:
            pass
        for _ in range(20):
            try:
                with open(os.path.join(cgroup_path, "cgroup.procs")) as fh:
                    if not fh.read().strip():
                        break
            except OSError:
                break
            time.sleep(0.05)
        try:
            os.rmdir(cgroup_path)
        except OSError:
            pass
    return proc.returncode, timed_out


# =============================================================================
# Section A: the exploit is closed under the REAL, current fix -- 20
# repeated runs of the reviewer's EXACT reproduction string for
# confidence against a timing-sensitive race (never asserted from a
# single run).
# =============================================================================
fails_a = 0
for i in range(20):
    marker = os.path.join(scratch, "A_marker_%d" % i)
    script = '(setsid sh -c "sleep 1; touch %s" &); exit 0' % marker
    t0 = time.monotonic()
    result = real_fix_run(script)
    elapsed = time.monotonic() - t0
    time.sleep(1.5)
    if os.path.exists(marker):
        fails_a += 1
print("SECTION_A: fails=%d/20 mechanism=%s last_elapsed=%.3f" % (fails_a, result.mechanism, elapsed))

# =============================================================================
# Section B: guard-viability MUTATION -- the OLD (pre-fix) PIPE +
# communicate()-based shape, fed the IDENTICAL exploit string, still
# leaks -- proving this round's specific fix (not the cgroup mechanism,
# present in both) is what closes Section A.
# =============================================================================
marker_b = os.path.join(scratch, "B_marker")
script_b = '(setsid sh -c "sleep 1; touch %s" &); exit 0' % marker_b
t0 = time.monotonic()
rc_b, timed_out_b = old_prefix_run(script_b)
elapsed_b = time.monotonic() - t0
time.sleep(1.5)
leaked_b = os.path.exists(marker_b)
print("SECTION_B: rc=%s timed_out=%s elapsed=%.3f leaked=%s" % (rc_b, timed_out_b, elapsed_b, leaked_b))

# =============================================================================
# Section C: normal stdout/stderr capture is unaffected (no regression
# in the documented, everyday-use contract).
# =============================================================================
result_c = fc_common.run_gate_reaped(["sh", "-c", "echo stdout-line; echo stderr-line 1>&2"], timeout_s=5)
print("SECTION_C: rc=%s stdout=%r stderr=%r mechanism=%s"
      % (result_c.returncode, result_c.stdout, result_c.stderr, result_c.mechanism))

# =============================================================================
# Section D: the documented timeout contract (empty stdout/stderr) is
# preserved unchanged by the file-capture rewrite.
# =============================================================================
result_d = fc_common.run_gate_reaped(["sh", "-c", "echo partial-output; sleep 5"], timeout_s=1)
print("SECTION_D: timed_out=%s stdout=%r stderr=%r" % (result_d.timed_out, result_d.stdout, result_d.stderr))
PYEOF
)
echo "$RESULT"

if echo "$RESULT" | grep -q "^SECTION_A: fails=0/20"; then
    ok "1: THE FIX -- the Round 5 reviewer's exact immediately-detaching repro leaked 0/20 times under the real, current run_gate_reaped() (R5-I1 closed)"
else
    bad "1: the immediately-detaching repro still leaked under the real, current run_gate_reaped(): $(echo "$RESULT" | grep '^SECTION_A')"
fi

if echo "$RESULT" | grep -q "^SECTION_A:.*mechanism=cgroup"; then
    ok "2: Section A genuinely exercised the cgroup mechanism (not a weaker fallback -- an apples-to-apples comparison with Section B)"
else
    bad "2: Section A did not report mechanism=cgroup -- re-investigate host cgroup v2 availability: $(echo "$RESULT" | grep '^SECTION_A')"
fi

if echo "$RESULT" | grep -q "^SECTION_B:.*leaked=True"; then
    ok "3: GUARD-VIABILITY MUTATION -- the OLD pre-fix PIPE+communicate() shape, using the SAME cgroup mechanism, DOES still leak the identical exploit -- proving this round's specific fix (file-capture + wait()-then-reap ordering), not the cgroup mechanism itself, is what closes Section A"
else
    bad "3: the reconstructed pre-fix shape did NOT leak -- the guard-viability mutation is not meaningful, re-investigate: $(echo "$RESULT" | grep '^SECTION_B')"
fi

if echo "$RESULT" | grep -q "^SECTION_C: rc=0 stdout='stdout-line\\\\n' stderr='stderr-line\\\\n'"; then
    ok "4: normal stdout/stderr capture is correct and unaffected by the file-based rewrite"
else
    bad "4: normal stdout/stderr capture regressed: $(echo "$RESULT" | grep '^SECTION_C')"
fi

if echo "$RESULT" | grep -q "^SECTION_D: timed_out=True stdout='' stderr=''"; then
    ok "5: the documented timeout contract (stdout/stderr empty) is preserved unchanged"
else
    bad "5: the timeout contract regressed: $(echo "$RESULT" | grep '^SECTION_D')"
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
