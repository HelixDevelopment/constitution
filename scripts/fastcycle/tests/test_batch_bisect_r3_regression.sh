#!/bin/sh
# =============================================================================
# T085 US2 Round 3 remediation regression (R3-I1, IMPORTANT, 2026-10-02).
# =============================================================================
#
# Proves that batch_bisect.py's run_gate_on_tree() no longer leaves a
# detached grandchild running after a NORMAL (non-timeout) return.
#
# T085 Round 3 R3-I1 (independent review): the Round 2 B-R2-3 process-
# group-kill fix landed ONLY in io_trace_build_map.py's retrace(), and
# ONLY on its timeout path -- a gate script that backgrounds a detached
# child (e.g. `( sleep 4; dangerous_cmd ) >/dev/null 2>&1 &`) and itself
# exits 0 WELL WITHIN the timeout left that child running after the
# caller already considered the gate "done". The review named
# batch_bisect.run_gate_on_tree's own `subprocess.run(timeout=...)` as
# having the SAME gap -- confirmed here and fixed by running the gate in
# its own process group and killing the WHOLE group on EVERY return
# path (normal, timeout, and OSError), via the shared
# fc_common.safe_killpg() primitive.
#
# §11.4.199: every scenario drives run_gate_on_tree() directly (the same
# convention test_batch_bisect_r2_regression.sh's own Section G already
# uses for its hung-gate unit check), never a synthetic stand-in for the
# process-management logic under test.
#
# Usage: sh test_batch_bisect_r3_regression.sh
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

# =============================================================================
# Section A -- REAL tool, unmutated: a gate that backgrounds a detached
# grandchild and returns normally leaves NO orphan behind.
# =============================================================================
echo "-- Section A: run_gate_on_tree() kills a backgrounded grandchild even on a normal return --"

A_OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile
import time

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

marker = os.path.join(scratch, "orphan_a.marker")
gate = os.path.join(scratch, "backgrounds_grandchild_a.sh")
with open(gate, "w") as fh:
    fh.write(
        "#!/bin/sh\n"
        "( sleep 2; echo orphan-ran > %r ) >/dev/null 2>&1 &\n"
        "exit 0\n" % marker
    )
os.chmod(gate, 0o755)

tree = tempfile.mkdtemp(dir=scratch)
t0 = time.time()
verdict, rc = mod.run_gate_on_tree(gate, tree)
elapsed = time.time() - t0

if verdict != "PASS" or rc != 0:
    print("FAIL: unexpected verdict=%s rc=%s (gate itself should PASS)" % (verdict, rc))
    sys.exit(1)

if os.path.exists(marker):
    print("FAIL: orphan already ran (marker exists) before run_gate_on_tree() even returned -- test timing assumption broken")
    sys.exit(1)

# Give the (correctly-fixed) group-kill a brief moment to take effect, and
# the (if-broken) backgrounded sleep its full 2s to prove it either DID or
# did NOT survive -- never a long sleep, bounded well under this
# function's own normal-path overhead.
deadline = time.time() + 3.0
while time.time() < deadline:
    if os.path.exists(marker):
        break
    time.sleep(0.1)

if os.path.exists(marker):
    print("FAIL: the backgrounded grandchild SURVIVED run_gate_on_tree()'s normal return and wrote its marker -- the R3-I1 bug")
    sys.exit(1)
else:
    print("OK: elapsed=%.2fs -- the backgrounded grandchild was killed, its marker never appeared" % elapsed)
PYEOF
)
A_RC=$?
echo "$A_OUT"
if [ "$A_RC" -eq 0 ] && echo "$A_OUT" | grep -q "^OK: elapsed="; then
    ok "A1: a gate backgrounding a detached grandchild and returning normally leaves NO orphan running -- THE R3-I1 FIX"
else
    bad "A1: orphan-after-normal-return check failed: $A_OUT"
fi

# =============================================================================
# Section B -- mutation-flip proof: on a SCRATCH COPY of the real source
# (never the tracked file), revert run_gate_on_tree() to the pre-fix
# subprocess.run(timeout=...) pattern (no process group, no cleanup on a
# normal return), and confirm Section A's own assertion now FAILS to
# hold -- proving this guard is genuinely load-bearing (§11.4.115(F)),
# not tautological.
# =============================================================================
echo "-- Section B: mutation-flip proof (run_gate_on_tree reverted to the pre-fix pattern) --"

MUT_ROOT="$SCRATCH/mutbb"
mkdir -p "$MUT_ROOT/gates" "$MUT_ROOT/lib"
cp "$TOOL" "$MUT_ROOT/gates/batch_bisect.py"
cp "$FC/lib/fc_common.py" "$MUT_ROOT/lib/fc_common.py"
MUT_TOOL="$MUT_ROOT/gates/batch_bisect.py"

python3 - "$MUT_TOOL" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
import re
m = re.search(
    r"def run_gate_on_tree\(gate_path, tree_dir\):.*?\n\n\nclass GateRunner",
    text, re.DOTALL,
)
if m is None:
    sys.stderr.write("could not locate run_gate_on_tree()'s full body uniquely\n")
    sys.exit(1)
replacement = '''def run_gate_on_tree(gate_path, tree_dir):
    """T085-R3-I1-MUTATION: reverted to the pre-fix pattern -- no process
    group, no cleanup on a normal return."""
    try:
        proc = subprocess.run(
            [gate_path, tree_dir], capture_output=True, text=True,
            timeout=GATE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return "FAIL", -1
    return ("PASS" if proc.returncode == 0 else "FAIL"), proc.returncode


class GateRunner'''
text = text[:m.start()] + replacement + text[m.end():]
with open(path, "w") as f:
    f.write(text)
PYEOF
MUT_SETUP_RC=$?

if [ "$MUT_SETUP_RC" -ne 0 ]; then
    bad "B0: mutation setup could not uniquely locate run_gate_on_tree() in a fresh copy"
else
    ok "B0: mutation setup uniquely located and reverted run_gate_on_tree() to the pre-fix pattern in a scratch copy"

    B_OUT=$(python3 - "$MUT_TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile
import time

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect_mut", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

marker = os.path.join(scratch, "orphan_b.marker")
gate = os.path.join(scratch, "backgrounds_grandchild_b.sh")
with open(gate, "w") as fh:
    fh.write(
        "#!/bin/sh\n"
        "( sleep 2; echo orphan-ran > %r ) >/dev/null 2>&1 &\n"
        "exit 0\n" % marker
    )
os.chmod(gate, 0o755)

tree = tempfile.mkdtemp(dir=scratch)
mod.run_gate_on_tree(gate, tree)

deadline = time.time() + 3.0
while time.time() < deadline:
    if os.path.exists(marker):
        break
    time.sleep(0.1)

if os.path.exists(marker):
    print("OK: mutation-flip -- with the pre-fix pattern restored, the backgrounded grandchild SURVIVES and writes its marker, confirming this guard is load-bearing, not tautological")
else:
    print("FAIL: mutation-flip FAILED -- the pre-fix pattern was restored but the grandchild still did not survive; the test cannot distinguish fixed from broken")
    sys.exit(1)
PYEOF
)
    B_RC=$?
    echo "$B_OUT"
    if [ "$B_RC" -eq 0 ] && echo "$B_OUT" | grep -q "^OK: mutation-flip"; then
        ok "B1: mutation-flip proves Section A's guard is genuinely load-bearing"
    else
        bad "B1: mutation-flip did not reproduce the pre-fix orphan behaviour: $B_OUT"
    fi
fi

# =============================================================================
# Section C -- T085 Round 3 m1 (MINOR): build_tree()'s own realpath
# escape check (distinct from cmd_run()'s earlier syntactic check,
# unreachable via the CLI alone) is independently load-bearing when
# called directly -- the exact review finding: "removing it (RM3)
# SURVIVES 11/11, and it is unreachable via cmd_run".
# =============================================================================
echo "-- Section C: build_tree()'s OWN realpath target_file escape check (m1) --"

C_OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

base_tree = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(base_tree, "widget.txt"), "w") as fh:
    fh.write("base\n")
patches_dir = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(patches_dir, "patch.txt"), "w") as fh:
    fh.write("patched\n")

# Calling build_tree() DIRECTLY (never through cmd_run()'s own earlier
# syntactic validation) with a target_file that escapes the disposable
# tree -- proves build_tree()'s OWN check, independent of any caller.
changes = [{"change_id": "chg-escape", "target_file": "../../../../tmp/m1_escape_probe.txt", "patch": "patch.txt"}]
try:
    mod.build_tree(base_tree, patches_dir, changes)
    print("FAIL: build_tree() did NOT raise TargetPathEscapeError for an escaping target_file called directly")
    sys.exit(1)
except mod.TargetPathEscapeError:
    print("OK: build_tree() raised TargetPathEscapeError when called directly with an escaping target_file")
PYEOF
)
C_RC=$?
echo "$C_OUT"
if [ "$C_RC" -eq 0 ] && echo "$C_OUT" | grep -q "^OK: build_tree"; then
    ok "C1: build_tree()'s OWN realpath escape check fires when called directly (bypassing cmd_run()'s syntactic pre-check)"
else
    bad "C1: build_tree()'s own escape check did not fire when called directly: $C_OUT"
fi

# Mutation-flip: strip the dst_real check and confirm C1's own assertion
# now fails to hold. batch_bisect.py resolves fc_common.py via a relative
# "../lib" hop from its OWN directory -- place the mutated copy in the
# same gates/+lib/ sibling layout so that import still resolves.
MUT_M1_ROOT="$SCRATCH/mutm1"
mkdir -p "$MUT_M1_ROOT/gates" "$MUT_M1_ROOT/lib"
cp "$FC/lib/fc_common.py" "$MUT_M1_ROOT/lib/fc_common.py"
MUT_M1="$MUT_M1_ROOT/gates/batch_bisect.py"
cp "$TOOL" "$MUT_M1"
python3 - "$MUT_M1" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
target = (
    '        dst_real = os.path.realpath(dst)\n'
    '        if dst_real != tmp_real and not dst_real.startswith(tmp_real + os.sep):\n'
)
if text.count(target) != 1:
    sys.stderr.write("expected exactly 1 occurrence, found %d\n" % text.count(target))
    sys.exit(1)
replacement = (
    '        dst_real = os.path.realpath(dst)\n'
    '        if False:  # T085-R3-m1-MUTATION: check stripped\n'
)
text = text.replace(target, replacement)
with open(path, "w") as f:
    f.write(text)
PYEOF
if [ $? -ne 0 ]; then
    bad "C2 mutation setup: could not uniquely locate the dst_real check"
else
    ok "C2 mutation setup: dst_real check uniquely located and stripped in a scratch copy"
    C3_OUT=$(python3 - "$MUT_M1" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect_mut_m1", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

base_tree = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(base_tree, "widget.txt"), "w") as fh:
    fh.write("base\n")
patches_dir = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(patches_dir, "patch.txt"), "w") as fh:
    fh.write("patched\n")

# build_tree() creates its own tempdir via tempfile.mkdtemp(prefix=...)
# with NO `dir=` argument (the system default temp dir, depth unknown to
# this caller) -- use the SAME "enough ../ segments to reach /tmp/
# regardless of actual depth" technique C1 above already used
# successfully, rather than trying to compute an exact relative path to
# an unknown tempdir.
victim = "/tmp/m1_escape_probe_mutflip.txt"
if os.path.exists(victim):
    os.remove(victim)
changes = [{"change_id": "chg-escape", "target_file": "../../../../tmp/m1_escape_probe_mutflip.txt", "patch": "patch.txt"}]
try:
    mod.build_tree(base_tree, patches_dir, changes)
except mod.TargetPathEscapeError:
    print("FAIL: still raised TargetPathEscapeError with the check stripped -- mutation ineffective")
    sys.exit(1)
if os.path.exists(victim):
    print("OK: mutation-flip -- with the check stripped, build_tree() wrote OUTSIDE the disposable tree to %s, confirming C1's guard is genuinely load-bearing" % victim)
    os.remove(victim)
else:
    print("FAIL: mutation stripped but no escape write observed either -- test construction problem")
    sys.exit(1)
PYEOF
)
    C3_RC=$?
    echo "$C3_OUT"
    if [ "$C3_RC" -eq 0 ] && echo "$C3_OUT" | grep -q "^OK: mutation-flip"; then
        ok "C3: mutation-flip proves build_tree()'s own target_file escape check is genuinely load-bearing, not tautological"
    else
        bad "C3: mutation-flip did not demonstrate the escape: $C3_OUT"
    fi
fi

# =============================================================================
# Section D -- T085 Round 3 m5 (MINOR): a change's `patch` field (the
# READ side) is now also containment-checked against patches_dir -- a
# `patch` value escaping patches_dir can no longer copy an arbitrary
# readable file into the disposable tree.
# =============================================================================
echo "-- Section D: build_tree()'s patch (read-side) containment check (m5) --"

D_OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect_d", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

base_tree = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(base_tree, "widget.txt"), "w") as fh:
    fh.write("base\n")
patches_dir = tempfile.mkdtemp(dir=scratch)

outside_file = os.path.join(scratch, "outside_patches_dir_marker.txt")
with open(outside_file, "w") as fh:
    fh.write("MARKER -- must never be copied into the disposable tree\n")

changes = [{"change_id": "chg-read-escape", "target_file": "widget.txt", "patch": "../outside_patches_dir_marker.txt"}]
try:
    mod.build_tree(base_tree, patches_dir, changes)
    print("FAIL: build_tree() did NOT raise TargetPathEscapeError for a patch escaping patches_dir")
    sys.exit(1)
except mod.TargetPathEscapeError:
    print("OK: build_tree() raised TargetPathEscapeError for a patch value escaping patches_dir")
PYEOF
)
D_RC=$?
echo "$D_OUT"
if [ "$D_RC" -eq 0 ] && echo "$D_OUT" | grep -q "^OK: build_tree"; then
    ok "D1: a patch value escaping patches_dir is refused -- THE m5 FIX"
else
    bad "D1: patch-escape was not refused: $D_OUT"
fi

# Negative control: a genuinely safe, in-tree patch value must NOT be
# refused -- the fix does not over-reject legitimate batches.
D2_OUT=$(python3 - "$TOOL" "$SCRATCH" <<'PYEOF'
import importlib.util
import os
import sys
import tempfile

mod_path, scratch = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("batch_bisect_d2", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

base_tree = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(base_tree, "widget.txt"), "w") as fh:
    fh.write("base\n")
patches_dir = tempfile.mkdtemp(dir=scratch)
with open(os.path.join(patches_dir, "patch.txt"), "w") as fh:
    fh.write("patched\n")

changes = [{"change_id": "chg-safe", "target_file": "widget.txt", "patch": "patch.txt"}]
tree = mod.build_tree(base_tree, patches_dir, changes)
content = open(os.path.join(tree, "widget.txt")).read()
if content == "patched\n":
    print("OK: a genuinely safe, in-patches-dir patch value is NOT over-rejected")
else:
    print("FAIL: safe patch application did not take effect: %r" % content)
    sys.exit(1)
PYEOF
)
D2_RC=$?
echo "$D2_OUT"
if [ "$D2_RC" -eq 0 ] && echo "$D2_OUT" | grep -q "^OK: a genuinely safe"; then
    ok "D2 (negative control): a genuinely in-tree patch value is not over-rejected by the m5 fix"
else
    bad "D2 (negative control) FAILED: $D2_OUT"
fi

echo "---"
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
