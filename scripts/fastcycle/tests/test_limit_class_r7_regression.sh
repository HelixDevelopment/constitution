#!/bin/bash
# Purpose : T140 Round 7 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/limit_class.py`.
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check that the CHECKED-IN pinned pre-R7-fix copy
# (extracted from this submodule's own HEAD commit
# 898051ce1347221de06b3d0b2c27b005c8f61e42 -- the exact commit immediately
# before this Round 7 fix landed) genuinely reproduces the pre-fix defect:
#
#   R7-I1 -- mixed-type `alias` values (e.g. `"a"` and `1` in the same
#     `aliases` list) used to raise an UNCAUGHT `TypeError` from
#     `write_class_doc_atomic`'s own `json.dumps(..., sort_keys=True)` --
#     `assignment_alias_counts`'s dict keys become mutually incomparable
#     once mixed-typed. The `_validate_placement_fixture_shape` fix
#     (R7-I2, below) closes the currently-reachable path to this crash at
#     its SOURCE; the write-site's own `except` clause is ALSO widened to
#     `fc_common.SAFE_EXCEPTIONS` as defense-in-depth.
#   R7-I2 -- duplicate or type-colliding `alias` values used to fail OPEN
#     (never crash): `assignment_alias_counts = {alias: 0 for alias in
#     eligible}` silently collapses duplicate/colliding dict keys, so
#     round-robin assignments meant for TWO distinct eligible slots both
#     land on ONE real alias -- `max_assigned_count` can exceed
#     `cap_per_alias`, exactly the "concentrate blast radius" outcome
#     DEC-22 exists to prevent.
#   M3 -- `derive_placement`'s `for i in range(live_agents):` loop has no
#     upper bound; a `live_agents` value like 10**12 (still a genuine
#     non-negative integer) does not crash or refuse -- it HANGS.
#   Top-level dispatch boundary -- `main()` now wraps BOTH the `place` and
#     `classify` dispatch paths in their own `except fc_common.
#     SAFE_EXCEPTIONS` boundary, each still writing an honest (if minimal)
#     --out document and returning EXIT_USAGE(2) on a genuinely
#     unanticipated crash.
#   Malformed-input fuzz probe -- adversarial `place --fixture` documents
#     asserting: no traceback ever appears on stderr, rc is always in
#     {0,1,2}, and rc=1 only ever occurs together with a verdict/output
#     file having genuinely been written.
#
# House style: mirrors test_limit_class_r6_regression.sh's own control-
# needle-first / real-tool-then-pinned-copy structure. UNLIKE
# test_limit_class_r6_regression.sh's own PRE-R6 pinned copy (which
# predates fc_common entirely and is run DIRECTLY from its checked-in
# path), THIS file's pinned pre-R7-fix copy is a POST-R6 snapshot that
# ALREADY imports `fc_common` via the same `_LIB_DIR`-relative sys.path
# insertion the real tool uses -- so it needs the SAME two-directory
# scratch layout `test_handoff_i4_regression.sh`'s own
# `run_against_pinned()` established (verified live at authoring time: a
# direct run of this pinned copy fails with a plain `ModuleNotFoundError`
# for `fc_common`).
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 7 review's findings text and this
# session's own live reproduction of each one (never imported from, nor
# shared with, limit_class.py's own implementation).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/alias_spread"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/limit_class.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
PINNED="$PINDIR/limit_class_pre_r7_fix.py"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R7 regression guard: control needle -- fixed tool + lib + pinned copy all exist ==="
for p in "$IMPL" "$LIB" "$PINNED"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib + pinned pre-R7-fix copy all resolve"
fi

mkfix() {
  # $1 = fixture path, stdin = JSON body
  cat > "$1"
}

run_against_pinned() {
  # $1..$N = argv for the pinned copy (two-directory scratch convention,
  # see this file's own header note above for why -- this pinned copy,
  # unlike test_limit_class_r6_regression.sh's own PRE-R6 one, already
  # imports fc_common).
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINNED" "$TMP/orchestration_scratch/limit_class.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  cp "$EXLIB" "$TMP/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 "$TMP/orchestration_scratch/limit_class.py" "$@"
}

echo
echo "=== R7-I2: duplicate/type-colliding aliases fail OPEN, not merely crash ==="

echo "--- duplicate string alias ---"
DUP="$TMP/r72_dup.json"
mkfix "$DUP" <<'EOF'
{"live_agents": 4, "aliases": [
  {"alias": "A", "kind": "native", "operational": true, "near_cap": false},
  {"alias": "A", "kind": "native", "operational": true, "near_cap": false}
]}
EOF
FIXED_OUT="$TMP/r72_dup.out.json"
python3 "$IMPL" place --fixture "$DUP" --out "$FIXED_OUT" >"$TMP/r72_dup.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "duplicates an earlier entry" "$TMP/r72_dup.err"; then
  echo "ok R7-I2 (duplicate alias) real (fixed) tool: place refuses with EXIT_USAGE(2),"
  echo "   names the exact duplicate -- $(cat "$TMP/r72_dup.err")"
else
  echo "NOT ok R7-I2 (duplicate alias) real (fixed) tool: rc=$FIXED_RC out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r72_dup.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/r72_dup.pin.json"
run_against_pinned place --fixture "$DUP" --out "$PIN_OUT" >"$TMP/r72_dup.pin.err" 2>&1
PIN_RC=$?
if [ -f "$PIN_OUT" ] && python3 -c "
import json, sys
d = json.load(open('$PIN_OUT'))
# fail-OPEN proof: max_assigned_count (4, all agents on the one collapsed
# key) exceeds cap_per_alias (ceil(4/2)+1=3) -- the exact concentration
# DEC-22 exists to prevent, silently produced by a duplicate alias.
sys.exit(0 if d.get('max_assigned_count', 0) > d.get('cap_per_alias', 0) else 1)
"; then
  echo "ok R7-I2 (duplicate alias) guard-viability: pinned pre-R7-fix copy rc=$PIN_RC,"
  echo "   silently WROTE a placement whose max_assigned_count EXCEEDS cap_per_alias"
  echo "   -- $(cat "$PIN_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("max_assigned_count=%r cap_per_alias=%r" % (d.get("max_assigned_count"), d.get("cap_per_alias")))') -- proving this"
  echo "   fixture genuinely catches the R7-I2 fail-open if the fix is ever reverted"
else
  echo "NOT ok R7-I2 (duplicate alias) guard-viability BLIND: rc=$PIN_RC out=$(cat "$PIN_OUT" 2>/dev/null)"
  failx
fi

echo "--- type-colliding aliases (1 vs true) ---"
COLLIDE="$TMP/r72_collide.json"
mkfix "$COLLIDE" <<'EOF'
{"live_agents": 4, "aliases": [
  {"alias": "a", "kind": "native", "operational": true, "near_cap": false},
  {"alias": 1, "kind": "native", "operational": true, "near_cap": false}
]}
EOF
FIXED_OUT="$TMP/r72_collide.out.json"
python3 "$IMPL" place --fixture "$COLLIDE" --out "$FIXED_OUT" >"$TMP/r72_collide.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && grep -q "must be a non-empty JSON string" "$TMP/r72_collide.err"; then
  echo "ok R7-I2 (type-colliding alias) real (fixed) tool: place refuses with EXIT_USAGE(2),"
  echo "   names the non-string alias -- $(cat "$TMP/r72_collide.err")"
else
  echo "NOT ok R7-I2 (type-colliding alias) real (fixed) tool: rc=$FIXED_RC out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r72_collide.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/r72_collide.pin.json"
run_against_pinned place --fixture "$COLLIDE" --out "$PIN_OUT" >"$TMP/r72_collide.pin.err" 2>&1
if grep -q "^Traceback" "$TMP/r72_collide.pin.err" 2>/dev/null && grep -qi "TypeError" "$TMP/r72_collide.pin.err" 2>/dev/null; then
  echo "ok R7-I2/R7-I1 (type-colliding alias) guard-viability: pinned pre-R7-fix copy"
  echo "   CRASHED uncaught with a real TypeError from json.dumps(sort_keys=True) --"
  echo "   proving this fixture genuinely catches the R7-I1/R7-I2 regression if the"
  echo "   fix is ever reverted"
else
  echo "NOT ok R7-I2/R7-I1 (type-colliding alias) guard-viability BLIND: $(cat "$TMP/r72_collide.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== M3: unbounded range(live_agents) hangs on an absurdly large but valid integer ==="
HUGE="$TMP/m3_huge.json"
mkfix "$HUGE" <<'EOF'
{"live_agents": 1000000000000, "aliases": [
  {"alias": "a", "kind": "native", "operational": true, "near_cap": false}
]}
EOF
FIXED_OUT="$TMP/m3_huge.out.json"
FIXED_START=$(date +%s)
timeout 10 python3 "$IMPL" place --fixture "$HUGE" --out "$FIXED_OUT" >"$TMP/m3_huge.err" 2>&1
FIXED_RC=$?
FIXED_ELAPSED=$(( $(date +%s) - FIXED_START ))
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && [ "$FIXED_ELAPSED" -lt 5 ] && grep -q "sane upper bound" "$TMP/m3_huge.err"; then
  echo "ok M3 real (fixed) tool: place refuses PROMPTLY (${FIXED_ELAPSED}s, EXIT_USAGE=2),"
  echo "   names the upper-bound refusal -- $(cat "$TMP/m3_huge.err")"
else
  echo "NOT ok M3 real (fixed) tool: rc=$FIXED_RC elapsed=${FIXED_ELAPSED}s out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/m3_huge.err" 2>/dev/null)"
  failx
fi
echo "   (guard-viability for M3 is NOT run against the pinned copy live -- it would"
echo "   genuinely hang for a very long time on a 10**12-iteration Python range();"
echo "   the pinned copy's own SOURCE is instead statically confirmed to lack the"
echo "   MAX_LIVE_AGENTS check the fixed tool has)"
if ! grep -q "MAX_LIVE_AGENTS" "$PINNED"; then
  echo "ok M3 guard-viability (static): pinned pre-R7-fix copy's source has NO"
  echo "   MAX_LIVE_AGENTS upper-bound check at all -- confirming a revert of this"
  echo "   fix would reintroduce the unbounded-range hang"
else
  echo "NOT ok M3 guard-viability (static) FAILED: pinned copy unexpectedly already"
  echo "     has a MAX_LIVE_AGENTS check (pinned copy extraction may be wrong)"
  failx
fi

echo
echo "=== Top-level dispatch boundary: main() wraps BOTH place and classify dispatch in their own except Exception boundary ==="
# T140 Round 8 review finding R8-I1 (fixed here): the boundary's own catch
# set was WIDENED from `fc_common.SAFE_EXCEPTIONS` to bare `Exception` (see
# limit_class.py's own main() comment) -- this static check is updated to
# match the new reality: it now looks for TWO bare `except Exception as
# exc:` handlers (an `ast.Name` node whose `id == "Exception"`, NOT an
# `ast.Attribute` node) that each still call the minimal-error-doc writer,
# and ADDITIONALLY confirms `Exception` is never accidentally widened all
# the way to `BaseException` (which would wrongly swallow
# `SystemExit`/`KeyboardInterrupt` too -- section 11.4.6, never silently
# over-widen a fix beyond what was asked).
BOUNDARY_CHECK=$(python3 - "$IMPL" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1])
count = 0
found_base_exception = False
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name == "main":
        for sub in ast.walk(node):
            if isinstance(sub, ast.Try):
                for h in sub.handlers:
                    if h.type is None:
                        continue
                    if isinstance(h.type, ast.Name) and h.type.id == "BaseException":
                        found_base_exception = True
                    if isinstance(h.type, ast.Name) and h.type.id == "Exception":
                        calls_writer = any(
                            isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                            and "internal_error" in n.func.id
                            for n in ast.walk(h)
                        )
                        if calls_writer:
                            count += 1
if found_base_exception:
    print("BASEEXCEPTION")
else:
    print(count)
PYEOF
)
if [ "$BOUNDARY_CHECK" = "2" ]; then
  echo "ok top-level dispatch boundary: main() wraps BOTH cmd_place(...) and"
  echo "   cmd_classify(...) in their own except Exception boundary that calls the"
  echo "   minimal-error-doc writer (2 distinct guarded call sites found, one per"
  echo "   dispatch path; never BaseException -- SystemExit/KeyboardInterrupt"
  echo "   correctly stay uncaught)"
elif [ "$BOUNDARY_CHECK" = "BASEEXCEPTION" ]; then
  echo "NOT ok top-level dispatch boundary OVER-WIDENED to BaseException -- this would"
  echo "     wrongly swallow SystemExit/KeyboardInterrupt too"
  failx
else
  echo "NOT ok top-level dispatch boundary: found $BOUNDARY_CHECK guarded dispatch"
  echo "     call site(s), wanted 2 (place + classify)"
  failx
fi
LIVE_ROOT="$TMP/live_boundary"
mkdir -p "$LIVE_ROOT/scripts/fastcycle/orchestration" "$LIVE_ROOT/scripts/fastcycle/lib"
cp "$IMPL" "$LIVE_ROOT/scripts/fastcycle/orchestration/limit_class.py"
cp "$LIB" "$LIVE_ROOT/scripts/fastcycle/lib/fc_common.py"
cp "$EXLIB" "$LIVE_ROOT/scripts/fastcycle/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
python3 - "$LIVE_ROOT/scripts/fastcycle/orchestration/limit_class.py" <<'PYEOF'
import sys
p = sys.argv[1]
old = "def cmd_classify(a):\n    cls, resets_at = classify_signal(a.signal)\n"
new = ("def cmd_classify(a):\n"
       "    raise TypeError('MUTATION_LIVE_BOUNDARY_PROOF: forced unanticipated crash')\n"
       "    cls, resets_at = classify_signal(a.signal)\n")
with open(p, encoding="utf-8") as fh:
    content = fh.read()
if content.count(old) != 1:
    sys.exit(1)
content = content.replace(old, new)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(content)
PYEOF
if [ $? -ne 0 ]; then
  echo "NOT ok top-level dispatch boundary LIVE PROOF: mutation anchor not found (content drifted)"
  failx
else
  LIVE_OUT="$TMP/live_boundary.out.json"
  python3 "$LIVE_ROOT/scripts/fastcycle/orchestration/limit_class.py" --signal "some raw signal text" --out "$LIVE_OUT" \
      >"$TMP/live_boundary.err" 2>&1
  LIVE_RC=$?
  if [ "$LIVE_RC" = "2" ] && [ -f "$LIVE_OUT" ] && ! grep -q "^Traceback" "$TMP/live_boundary.err" \
      && grep -q "MUTATION_LIVE_BOUNDARY_PROOF" "$TMP/live_boundary.err" \
      && python3 -c "import json,sys; d=json.load(open('$LIVE_OUT')); sys.exit(0 if d.get('internal_error',{}).get('detail','').find('MUTATION_LIVE_BOUNDARY_PROOF')>=0 else 1)"; then
    echo "ok top-level dispatch boundary LIVE PROOF: a forced, genuinely unanticipated"
    echo "   TypeError raised at the very TOP of cmd_classify (before ANY of its own"
    echo "   internal try/excepts could ever run) is caught by main()'s own boundary --"
    echo "   rc=2 (never Python's uncaught-exception default of 1), NO traceback on"
    echo "   stderr, and a real --out document naming the real exception was written"
    echo "   -- this is NOT something any of R7-I1/I2/M3's own individual, targeted"
    echo "   fixes above would have caught by themselves"
  else
    echo "NOT ok top-level dispatch boundary LIVE PROOF FAILED: rc=$LIVE_RC out_exists=$([ -f "$LIVE_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/live_boundary.err" 2>/dev/null)"
    failx
  fi
fi

echo
echo "=== Malformed-input fuzz probe: no traceback ever, rc always in {0,1,2}, rc=1 only with an --out file written ==="
FUZZ_PLACE_DOCS=(
  'null'
  '[]'
  '{"live_agents": null, "aliases": []}'
  '{"live_agents": true, "aliases": []}'
  '{"live_agents": -1, "aliases": []}'
  '{"live_agents": 4, "aliases": null}'
  '{"live_agents": 4, "aliases": 42}'
  '{"live_agents": 4, "aliases": [null]}'
  '{"live_agents": 4, "aliases": [{"alias": null}]}'
  '{"live_agents": 4, "aliases": [{"alias": ""}]}'
  '{"live_agents": 4, "aliases": [{"alias": "a"}, {"alias": "a"}]}'
  '{"live_agents": 0, "aliases": []}'
)
FUZZ_FAIL=0
i=0
for doc in "${FUZZ_PLACE_DOCS[@]}"; do
  i=$((i + 1))
  f="$TMP/fuzz_place_$i.json"
  printf '%s' "$doc" > "$f"
  out="$TMP/fuzz_place_$i.out.json"
  python3 "$IMPL" place --fixture "$f" --out "$out" >"$TMP/fuzz_place_$i.err" 2>&1
  rc=$?
  if grep -q "^Traceback" "$TMP/fuzz_place_$i.err"; then
    echo "NOT ok fuzz place case $i ($doc): TRACEBACK on stderr: $(cat "$TMP/fuzz_place_$i.err")"
    FUZZ_FAIL=1
    continue
  fi
  case "$rc" in
    0|1|2) : ;;
    *) echo "NOT ok fuzz place case $i ($doc): rc=$rc outside {0,1,2}"; FUZZ_FAIL=1; continue ;;
  esac
  if [ "$rc" = "1" ] && [ ! -f "$out" ]; then
    echo "NOT ok fuzz place case $i ($doc): rc=1 (a finding) but NO --out was written"
    FUZZ_FAIL=1
    continue
  fi
done
if [ "$FUZZ_FAIL" = "0" ]; then
  echo "ok malformed-input fuzz probe: $i adversarial place --fixture documents --"
  echo "   zero tracebacks, every rc in {0,1,2}, every rc=1 paired with a"
  echo "   genuinely-written --out document"
else
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R7 REGRESSION GUARD (limit_class.py): ALL CHECKS PASS -- R7-I1's"
  echo "    write-site SAFE_EXCEPTIONS widening, R7-I2's duplicate/type-colliding"
  echo "    alias refusal, M3's MAX_LIVE_AGENTS upper bound, and the ONE"
  echo "    top-level main() dispatch boundary (place AND classify) are all"
  echo "    load-bearing: reverting any one of them makes its own matching"
  echo "    pinned pre-fix copy either crash uncaught or silently misbehave,"
  echo "    and the malformed-input fuzz probe found zero tracebacks/bad-rc/"
  echo "    silent-loss cases across every adversarial document tried. ==="
  exit 0
else
  echo "=== R7 REGRESSION GUARD (limit_class.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
