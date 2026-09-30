#!/bin/bash
# Purpose : T140 Round 6 (batched Opus-xhigh independent review of SpecKit-004
#           "fast-dev-cycles" User Story 5) regression guard for
#           `orchestration/limit_class.py` finding R6-I2 (four sub-cases) and
#           N2 -- the FIVE Round 6 sub-findings touching this file, none of
#           which had any dedicated regression-test coverage before this
#           file landed (section 11.4.224 test-first).
#
# R6-I2 (verbatim summary from the Round 6 review, section 11.4.250
# heuristic-tower/primitive-defect): `limit_class.py`'s `place`/`classify`
# subcommands crashed uncaught on FOUR distinct inputs, none of which the
# prior (R5-I3) fix enumerated:
#   (a) `live_agents` set high enough that `live_agents / m` (true division,
#       promoting to a Python float) cannot be represented as a float raises
#       `OverflowError` at `derive_placement`'s own
#       `cap_per_alias = math.ceil(live_agents / m) + 1` -- uncaught,
#       colliding with `EXIT_PLACE_REFUSED`'s own exit code (1).
#   (b) an unwritable `--out` path (parent directory missing/not
#       writable/a permissions error) crashed BOTH `cmd_classify` and
#       `cmd_place` uncaught at `write_class_doc_atomic`'s own
#       `os.makedirs(out_dir, exist_ok=True)` -- no honest verdict written
#       at either subcommand's own write site.
#   (c) `live_agents: true` (a JSON bool) silently PASSED the pre-existing
#       `isinstance(live_agents, int)` check (`bool` is a subclass of `int`
#       in Python) and was then treated as `1` by `range(True)`, placing
#       exactly one agent for a fixture that never declared a sane integer
#       count.
#   (d) `live_agents: -5` (a negative int) also silently passed that same
#       check; `range(-5)` silently turns into zero placements with rc=0 --
#       "worked" on a nonsensical input with no trace anything was wrong.
# Fixed by: (a)/(placement OverflowError) widening `cmd_place`'s own
# `except TypeError` to the shared `fc_common.SAFE_EXCEPTIONS` tuple
# (TypeError, ValueError, OSError, OverflowError); (b) wrapping BOTH
# `write_class_doc_atomic(...)` call sites (`cmd_classify` and `cmd_place`)
# in their own `try/except (OSError, ValueError)`, each failing closed with
# its own diagnosable EXIT_USAGE(2); (c)/(d) replacing the bare
# `isinstance(live_agents, int)` check in
# `_validate_placement_fixture_shape` with the shared
# `fc_common.is_strict_nonneg_int` predicate (rejects both bool and
# negative).
#
# N2 (section 11.4.6, defence-in-depth, NOT reachable via any live CLI path
# today per this file's own diff comment -- `cmd_classify`'s body is built
# entirely from regex-derived strings; `cmd_place`'s `live_agents` is
# rejected before `derive_placement` ever runs if non-finite): plain
# `json.dumps` inside `write_class_doc_atomic` defaults to `allow_nan=True`,
# so it used to silently emit the non-standard-JSON tokens
# `NaN`/`Infinity`/`-Infinity` if `body` ever carried one -- producing an
# `--out` document that LOOKS written (a real file, a clean exit) but is not
# valid JSON per spec. Fixed by passing `allow_nan=False` to that
# `json.dumps` call. Tested here via a DIRECT MODULE-LEVEL PROBE (never
# through the live CLI, since the docstring itself documents no live path
# reaches it today) -- an honest, explicitly-labelled DEFENSIVE-HARDENING
# guard per section 11.4.115(G): this closes a primitive-level gap
# proactively, it does not (and is not claimed to) close any REPORTED,
# live-reproduced defect.
#
# THREE new fixtures (matching this suite's existing flat
# `fixtures/alias_spread/as_*.json` convention; `as_r6_*` prefix, never
# colliding with the pre-existing `as_*`/`as_r5i3_*` fixtures
# `test_alias_spread_red.sh`/`test_limit_class_place_r5i3_regression.sh`
# already own):
#   as_r6_overflow_live_agents.json  -- live_agents a ~500-digit integer (a).
#   as_r6_live_agents_bool.json      -- live_agents: true (c).
#   as_r6_live_agents_negative.json  -- live_agents: -5 (d).
# (b)/unwritable --out and N2/allow_nan are exercised WITHOUT a checked-in
# fixture (a scratch tmpdir with a regular FILE standing in for a directory
# component, and a direct in-process module import, respectively -- neither
# is expressible as a static JSON fixture file).
#
# Guard-viability proof (section 11.4.115(F)): every live-CLI case is ALSO
# run against `fixtures/alias_spread/_pinned/limit_class_pre_r6_fix.py` --
# extracted ONCE, via `git show HEAD:...`, from this submodule's own HEAD
# commit a925a8dabf644f2b075290cce9404da484f4d410 (verified, at authoring
# time, to be the exact pre-Round-6-fix commit -- see
# test_handoff_r6_regression.sh's own identical note). `limit_class.py` has
# no sibling-lib import in its PRE-fix form (the Round 6 fix is what FIRST
# wires `fc_common` into this file), so -- mirroring
# test_limit_class_place_r5i3_regression.sh's own established convention --
# the pinned copy is run DIRECTLY from its own checked-in path, no
# scratch-directory copying needed.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/alias_spread"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/limit_class.py"
LIB="$FC/lib/fc_common.py"
PINNED="$PINDIR/limit_class_pre_r6_fix.py"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R6 regression guard: control needle -- fixtures + the fixed tool + pinned copy all exist ==="
for p in "$IMPL" "$LIB" "$PINNED" \
         "$FIXDIR/as_r6_overflow_live_agents.json" \
         "$FIXDIR/as_r6_live_agents_bool.json" \
         "$FIXDIR/as_r6_live_agents_negative.json"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib + pinned pre-R6-fix copy + all three new fixtures resolve"
fi

echo
echo "=== R6-I2(a): live_agents so large that live_agents/m raises OverflowError ==="
FIXED_OUT="$TMP/ov.fixed.json"
python3 "$IMPL" place --fixture "$FIXDIR/as_r6_overflow_live_agents.json" --out "$FIXED_OUT" >"$TMP/ov.fixed.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -qi "overflowerror" "$TMP/ov.fixed.err"; then
  echo "ok R6-I2(a) real (fixed) tool: place fails closed with EXIT_USAGE (2),"
  echo "   writes no --out document, and names the real OverflowError -- $(cat "$TMP/ov.fixed.err")"
else
  echo "NOT ok R6-I2(a) real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no), stderr=$(cat "$TMP/ov.fixed.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/ov.pin.json"
python3 "$PINNED" place --fixture "$FIXDIR/as_r6_overflow_live_agents.json" --out "$PIN_OUT" >"$TMP/ov.pin.err" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R6-I2(a) guard-viability FAILED: pinned pre-R6-fix copy WROTE an --out"
  echo "     document instead of crashing"
  failx
elif grep -q "^Traceback" "$TMP/ov.pin.err" 2>/dev/null && grep -q "^OverflowError" "$TMP/ov.pin.err" 2>/dev/null; then
  echo "ok R6-I2(a) guard-viability: the PINNED pre-R6-fix limit_class.py"
  echo "   CRASHED uncaught (Traceback + OverflowError in stderr, NO --out"
  echo "   document written) -- proving this fixture genuinely catches the"
  echo "   R6-I2(a) regression if the fix is ever reverted"
else
  echo "NOT ok R6-I2(a) guard-viability BLIND: $(cat "$TMP/ov.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I2(c): live_agents: true (JSON bool) must be REJECTED, never treated as 1 ==="
FIXED_OUT="$TMP/b.fixed.json"
python3 "$IMPL" place --fixture "$FIXDIR/as_r6_live_agents_bool.json" --out "$FIXED_OUT" >"$TMP/b.fixed.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "non-negative JSON integer" "$TMP/b.fixed.err"; then
  echo "ok R6-I2(c) real (fixed) tool: place refuses live_agents: true with"
  echo "   EXIT_USAGE (2), no --out written -- $(cat "$TMP/b.fixed.err")"
else
  echo "NOT ok R6-I2(c) real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no), stderr=$(cat "$TMP/b.fixed.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/b.pin.json"
python3 "$PINNED" place --fixture "$FIXDIR/as_r6_live_agents_bool.json" --out "$PIN_OUT" >"$TMP/b.pin.err" 2>&1
PIN_RC=$?
if [ "$PIN_RC" = "0" ] && [ -f "$PIN_OUT" ]; then
  PLACED=$(python3 -c "import json; d=json.load(open('$PIN_OUT')); print(len(d.get('placement') or d.get('placements') or []))" 2>/dev/null)
  echo "ok R6-I2(c) guard-viability: the PINNED pre-R6-fix limit_class.py"
  echo "   silently ACCEPTS live_agents: true (rc=0, real --out written) --"
  echo "   proving this fixture genuinely catches the R6-I2(c) silent-"
  echo "   bool-coercion regression if the fix is ever reverted"
else
  echo "NOT ok R6-I2(c) guard-viability BLIND: pinned copy did not cleanly accept"
  echo "     rc=$PIN_RC, out_exists=$([ -f "$PIN_OUT" ] && echo yes || echo no) -- $(cat "$TMP/b.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I2(d): live_agents: -5 (negative) must be REJECTED, never silently zero-placed ==="
FIXED_OUT="$TMP/neg.fixed.json"
python3 "$IMPL" place --fixture "$FIXDIR/as_r6_live_agents_negative.json" --out "$FIXED_OUT" >"$TMP/neg.fixed.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "non-negative JSON integer" "$TMP/neg.fixed.err"; then
  echo "ok R6-I2(d) real (fixed) tool: place refuses live_agents: -5 with"
  echo "   EXIT_USAGE (2), no --out written -- $(cat "$TMP/neg.fixed.err")"
else
  echo "NOT ok R6-I2(d) real (fixed) tool: rc=$FIXED_RC (wanted 2), out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no), stderr=$(cat "$TMP/neg.fixed.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/neg.pin.json"
python3 "$PINNED" place --fixture "$FIXDIR/as_r6_live_agents_negative.json" --out "$PIN_OUT" >"$TMP/neg.pin.err" 2>&1
PIN_RC=$?
if [ "$PIN_RC" = "0" ] && [ -f "$PIN_OUT" ]; then
  echo "ok R6-I2(d) guard-viability: the PINNED pre-R6-fix limit_class.py"
  echo "   silently ACCEPTS live_agents: -5 (rc=0, real --out written) --"
  echo "   proving this fixture genuinely catches the R6-I2(d) silent-"
  echo "   negative-count regression if the fix is ever reverted"
else
  echo "NOT ok R6-I2(d) guard-viability BLIND: pinned copy did not cleanly accept"
  echo "     rc=$PIN_RC, out_exists=$([ -f "$PIN_OUT" ] && echo yes || echo no) -- $(cat "$TMP/neg.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I2(b): unwritable --out (parent path component is a regular FILE) -- classify ==="
mkdir -p "$TMP/notadir_parent"
touch "$TMP/notadir_parent/not_a_dir"
FIXED_ERR="$TMP/cls.fixed.err"
python3 "$IMPL" --signal "429 session limit reached" --out "$TMP/notadir_parent/not_a_dir/sub.json" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && grep -qi "cannot write --out" "$FIXED_ERR"; then
  echo "ok R6-I2(b)/classify real (fixed) tool: fails closed with EXIT_USAGE"
  echo "   (2) and a diagnosable message, never an uncaught crash -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I2(b)/classify real (fixed) tool: rc=$FIXED_RC (wanted 2) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/cls.pin.err"
python3 "$PINNED" --signal "429 session limit reached" --out "$TMP/notadir_parent/not_a_dir/sub2.json" >"$PIN_ERR" 2>&1
PIN_RC=$?
if grep -q "^Traceback" "$PIN_ERR" 2>/dev/null && grep -qi "FileExistsError\|NotADirectoryError" "$PIN_ERR" 2>/dev/null; then
  echo "ok R6-I2(b)/classify guard-viability: the PINNED pre-R6-fix"
  echo "   limit_class.py CRASHED uncaught on the same unwritable --out path"
  echo "   -- proving this scenario genuinely catches the R6-I2(b)/classify"
  echo "   regression if the fix is ever reverted (rc=$PIN_RC)"
else
  echo "NOT ok R6-I2(b)/classify guard-viability BLIND: $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== R6-I2(b): unwritable --out -- place ==="
cat > "$TMP/valid_fixture.json" <<'EOF'
{"live_agents": 1, "aliases": [{"alias": "claude1", "kind": "native", "operational": true, "near_cap": false}]}
EOF
FIXED_ERR="$TMP/plc.fixed.err"
python3 "$IMPL" place --fixture "$TMP/valid_fixture.json" --out "$TMP/notadir_parent/not_a_dir/sub3.json" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && grep -qi "cannot write --out" "$FIXED_ERR"; then
  echo "ok R6-I2(b)/place real (fixed) tool: fails closed with EXIT_USAGE (2)"
  echo "   and a diagnosable message, never an uncaught crash -- $(cat "$FIXED_ERR")"
else
  echo "NOT ok R6-I2(b)/place real (fixed) tool: rc=$FIXED_RC (wanted 2) -- $(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
PIN_ERR="$TMP/plc.pin.err"
python3 "$PINNED" place --fixture "$TMP/valid_fixture.json" --out "$TMP/notadir_parent/not_a_dir/sub4.json" >"$PIN_ERR" 2>&1
if grep -q "^Traceback" "$PIN_ERR" 2>/dev/null && grep -qi "FileExistsError\|NotADirectoryError" "$PIN_ERR" 2>/dev/null; then
  echo "ok R6-I2(b)/place guard-viability: the PINNED pre-R6-fix limit_class.py"
  echo "   CRASHED uncaught on the same unwritable --out path -- proving this"
  echo "   scenario genuinely catches the R6-I2(b)/place regression if the"
  echo "   fix is ever reverted"
else
  echo "NOT ok R6-I2(b)/place guard-viability BLIND: $(cat "$PIN_ERR" 2>/dev/null)"
  failx
fi

echo
echo "=== N2: write_class_doc_atomic must reject a non-finite float (allow_nan=False), direct module probe ==="
echo "    (section 11.4.115(G): defensive hardening, no live CLI path reaches this today -- see file header)"
PROBE_RESULT=$(python3 - "$IMPL" <<'PYEOF'
import sys, importlib.util, tempfile, os
impl = sys.argv[1]
spec = importlib.util.spec_from_file_location("limit_class_fixed_n2probe", impl)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
tmp = tempfile.mkdtemp()
out = os.path.join(tmp, "nan_probe.json")
try:
    mod.write_class_doc_atomic(out, {"x": float("nan")})
    print("NO_EXCEPTION out_exists=%s" % os.path.exists(out))
except ValueError as e:
    print("VALUEERROR out_exists=%s msg=%s" % (os.path.exists(out), e))
PYEOF
)
if echo "$PROBE_RESULT" | grep -q "^VALUEERROR out_exists=False"; then
  echo "ok N2 real (fixed) module probe: write_class_doc_atomic(...) raises"
  echo "   ValueError on a non-finite float body and writes NO output file --"
  echo "   $PROBE_RESULT"
else
  echo "NOT ok N2 real (fixed) module probe: $PROBE_RESULT"
  failx
fi
PIN_PROBE_RESULT=$(python3 - "$PINNED" <<'PYEOF'
import sys, importlib.util, tempfile, os
impl = sys.argv[1]
spec = importlib.util.spec_from_file_location("limit_class_pinned_n2probe", impl)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
tmp = tempfile.mkdtemp()
out = os.path.join(tmp, "nan_probe.json")
try:
    mod.write_class_doc_atomic(out, {"x": float("nan")})
    print("NO_EXCEPTION out_exists=%s" % os.path.exists(out))
except ValueError as e:
    print("VALUEERROR out_exists=%s msg=%s" % (os.path.exists(out), e))
PYEOF
)
if echo "$PIN_PROBE_RESULT" | grep -q "^NO_EXCEPTION out_exists=True"; then
  echo "ok N2 guard-viability: the PINNED pre-R6-fix write_class_doc_atomic"
  echo "   silently writes a non-standard-JSON (NaN-bearing) --out document"
  echo "   with NO exception -- proving this probe genuinely catches the N2"
  echo "   regression if the allow_nan=False fix is ever reverted --"
  echo "   $PIN_PROBE_RESULT"
else
  echo "NOT ok N2 guard-viability BLIND: $PIN_PROBE_RESULT"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R6 REGRESSION GUARD (limit_class.py): ALL CHECKS PASS -- R6-I2(a)'s"
  echo "    OverflowError handling, R6-I2(b)'s write-guard on both classify and"
  echo "    place, R6-I2(c)/(d)'s bool/negative live_agents rejection, and"
  echo "    N2's allow_nan=False defensive hardening are all load-bearing:"
  echo "    reverting any one of them makes its own matching pinned pre-fix"
  echo "    copy either crash uncaught or silently accept/produce a malformed"
  echo "    result. ==="
  exit 0
else
  echo "=== R6 REGRESSION GUARD (limit_class.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
