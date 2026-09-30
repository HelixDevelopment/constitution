#!/bin/bash
# Purpose : T140 Round 7 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/handoff.py`.
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check that the CHECKED-IN pinned pre-R7-fix copy
# (extracted from this submodule's own HEAD commit
# 898051ce1347221de06b3d0b2c27b005c8f61e42 -- the exact commit immediately
# before this Round 7 fix landed) genuinely reproduces the pre-fix defect:
#
#   R7-I5(a) -- `validate`/`verify` crash on a `partial_artefacts` field
#     whose top-level shape is not a list (silently iterated character-by-
#     character), an entry whose `path` is present but not a string
#     (crashes `os.path.join`), and a `path` that resolves to an EXISTING
#     but UNREADABLE file (crashes `content_address`'s bare `open()`).
#   R7-I5(b) -- `write`, `validate`/`verify`, and `resume`/`resume-check`
#     ALL crash on an unwritable `--out` (and `write` ALSO on an
#     unwritable `--handoff`) -- the R6 write-guard fix (widely applied in
#     the sibling `limit_class.py`/`custody_sweep.py`) never actually
#     reached this file's own `write_json_atomic`/`write_report_atomic`
#     call sites.
#   Top-level dispatch boundary -- `main()` now wraps its subcommand
#     dispatch table lookup+call in ONE `except fc_common.SAFE_EXCEPTIONS`
#     boundary that still writes an honest (if minimal) --out document and
#     returns EXIT_USAGE(2) on a genuinely unanticipated crash.
#   Malformed-input fuzz probe -- adversarial `--handoff` record bodies
#     (missing keys, wrong types, garbage) fed to `validate` and
#     `resume-check`, asserting: no traceback ever appears on stderr, rc
#     is always in {0,1,2}, and rc=1 only ever occurs together with a
#     verdict/output file having genuinely been written.
#
# House style: mirrors test_handoff_r6_regression.sh's own control-needle-
# first / real-tool-then-pinned-copy / two-directory scratch layout
# (`run_against_pinned()`, identical to test_handoff_i4_regression.sh's own
# convention) / closing-summary structure.
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 7 review's findings text and this
# session's own live reproduction of each one (never imported from, nor
# shared with, handoff.py's own implementation).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/resume_revalidate"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/handoff.py"
LIB="$FC/lib/fc_common.py"
PINNED="$PINDIR/handoff_pre_r7_fix.py"

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

run_against_pinned() {
  # $1..$N = argv for the pinned copy (identical two-directory scratch
  # convention to test_handoff_i4_regression.sh's own run_against_pinned()
  # / test_handoff_r6_regression.sh's own identical reuse of it).
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINNED" "$TMP/orchestration_scratch/handoff.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  python3 "$TMP/orchestration_scratch/handoff.py" "$@"
}

write_real_handoff() {
  # $1 = --handoff path to write a genuine, self-integrity-valid handoff
  # record to, using the REAL (fixed) tool's own `write` subcommand.
  python3 "$IMPL" write --item-id NONE --agent-key a1 --alias claude1 --model sonnet \
      --effort high --phase PLAN --handoff "$1" --out "$TMP/_write_report_$(basename "$1").json" \
      >/dev/null 2>&1
}

echo
echo "=== R7-I5(a): validate/verify crash on malformed partial_artefacts ==="

echo "--- partial_artefacts is a non-list (a truthy string) ---"
H="$TMP/i5a_nonlist.json"
write_real_handoff "$H"
python3 -c "
import json
with open('$H') as fh: d = json.load(fh)
d['partial_artefacts'] = 'not-a-list'
with open('$H', 'w') as fh: json.dump(d, fh)
"
FIXED_OUT="$TMP/i5a_nonlist.out.json"
python3 "$IMPL" validate --handoff "$H" --out "$FIXED_OUT" >"$TMP/i5a_nonlist.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "1" ] && [ -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/i5a_nonlist.err" \
    && python3 -c "import json,sys; d=json.load(open('$FIXED_OUT')); sys.exit(0 if any('partial_artefacts' in m and 'not-a-list' in m for m in d.get('mismatches',[])) else 1)"; then
  echo "ok R7-I5(a) (non-list partial_artefacts) real (fixed) tool: validate INVALID (rc=1),"
  echo "   writes a real --out naming the malformed field, never crashes"
else
  echo "NOT ok R7-I5(a) (non-list partial_artefacts) real (fixed) tool: rc=$FIXED_RC out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/i5a_nonlist.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/i5a_nonlist.pin.json"
run_against_pinned validate --handoff "$H" --out "$PIN_OUT" >"$TMP/i5a_nonlist.pin.err" 2>&1
PIN_RC=$?
# Pre-fix behaviour is a SILENT WRONG ANSWER (iterates the string char-by-
# char, contributing bogus mismatches for each character), never a crash
# -- proven live at authoring time. The guard-viability proof here is
# therefore that the PRE-fix copy's `mismatches` list differs in SHAPE
# from the fixed tool's own single, diagnosable "malformed:..." entry
# (many bogus per-character entries instead of one honest one), not that
# it crashes.
if [ -f "$PIN_OUT" ] && python3 -c "
import json, sys
d = json.load(open('$PIN_OUT'))
ms = d.get('mismatches', [])
# pre-fix: one bogus 'partial_artefact:None:missing' PER CHARACTER of the
# 11-character string 'not-a-list' -- proving the char-by-char fail-open.
sys.exit(0 if ms.count('partial_artefact:None:missing') >= 5 else 1)
"; then
  echo "ok R7-I5(a) (non-list partial_artefacts) guard-viability: pinned pre-R7-fix copy"
  echo "   silently iterated the string CHARACTER BY CHARACTER (>=5 bogus"
  echo "   'partial_artefact:None:missing' mismatches) -- proving this fixture"
  echo "   genuinely catches the R7-I5(a) fail-open if the fix is ever reverted"
else
  echo "NOT ok R7-I5(a) (non-list partial_artefacts) guard-viability BLIND: rc=$PIN_RC out=$(cat "$PIN_OUT" 2>/dev/null)"
  failx
fi

echo "--- partial_artefacts entry's path is a JSON int ---"
H="$TMP/i5a_pathint.json"
write_real_handoff "$H"
python3 -c "
import json
with open('$H') as fh: d = json.load(fh)
d['partial_artefacts'] = [{'path': 42, 'content_address': 'sha256:deadbeef'}]
with open('$H', 'w') as fh: json.dump(d, fh)
"
FIXED_OUT="$TMP/i5a_pathint.out.json"
python3 "$IMPL" validate --handoff "$H" --out "$FIXED_OUT" >"$TMP/i5a_pathint.err" 2>&1
if [ -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/i5a_pathint.err"; then
  echo "ok R7-I5(a) (int path) real (fixed) tool: writes a real --out (never crashes)"
else
  echo "NOT ok R7-I5(a) (int path) real (fixed) tool: out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/i5a_pathint.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/i5a_pathint.pin.json"
run_against_pinned validate --handoff "$H" --out "$PIN_OUT" >"$TMP/i5a_pathint.pin.err" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R7-I5(a) (int path) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
  failx
elif grep -q "^Traceback" "$TMP/i5a_pathint.pin.err" 2>/dev/null && grep -qi "TypeError" "$TMP/i5a_pathint.pin.err" 2>/dev/null; then
  echo "ok R7-I5(a) (int path) guard-viability: pinned pre-R7-fix copy CRASHED uncaught"
  echo "   with a real TypeError from os.path.join -- proving this fixture genuinely"
  echo "   catches the R7-I5(a) regression if the fix is ever reverted"
else
  echo "NOT ok R7-I5(a) (int path) guard-viability BLIND: $(cat "$TMP/i5a_pathint.pin.err" 2>/dev/null)"
  failx
fi

echo "--- partial_artefacts entry's path is an existing but UNREADABLE file ---"
H="$TMP/i5a_unreadable.json"
write_real_handoff "$H"
touch "$TMP/i5a_secret.bin"
chmod 000 "$TMP/i5a_secret.bin"
python3 -c "
import json
with open('$H') as fh: d = json.load(fh)
d['partial_artefacts'] = [{'path': '$TMP/i5a_secret.bin', 'content_address': 'sha256:deadbeef'}]
with open('$H', 'w') as fh: json.dump(d, fh)
"
if [ ! -r "$TMP/i5a_secret.bin" ]; then
  FIXED_OUT="$TMP/i5a_unreadable.out.json"
  python3 "$IMPL" validate --handoff "$H" --out "$FIXED_OUT" >"$TMP/i5a_unreadable.err" 2>&1
  if [ -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/i5a_unreadable.err" \
      && python3 -c "import json,sys; d=json.load(open('$FIXED_OUT')); sys.exit(0 if any('unreadable' in m for m in d.get('mismatches',[])) else 1)"; then
    echo "ok R7-I5(a) (unreadable path) real (fixed) tool: writes a real --out naming"
    echo "   the unreadable artefact, never crashes"
  else
    echo "NOT ok R7-I5(a) (unreadable path) real (fixed) tool: out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/i5a_unreadable.err" 2>/dev/null)"
    failx
  fi
  PIN_OUT="$TMP/i5a_unreadable.pin.json"
  run_against_pinned validate --handoff "$H" --out "$PIN_OUT" >"$TMP/i5a_unreadable.pin.err" 2>&1
  if [ -f "$PIN_OUT" ]; then
    echo "NOT ok R7-I5(a) (unreadable path) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
    failx
  elif grep -q "^Traceback" "$TMP/i5a_unreadable.pin.err" 2>/dev/null && grep -qi "PermissionError" "$TMP/i5a_unreadable.pin.err" 2>/dev/null; then
    echo "ok R7-I5(a) (unreadable path) guard-viability: pinned pre-R7-fix copy CRASHED"
    echo "   uncaught with a real PermissionError -- proving this fixture genuinely"
    echo "   catches the R7-I5(a) regression if the fix is ever reverted"
  else
    echo "NOT ok R7-I5(a) (unreadable path) guard-viability BLIND: $(cat "$TMP/i5a_unreadable.pin.err" 2>/dev/null)"
    failx
  fi
else
  echo "SKIP R7-I5(a) (unreadable path): running as a user for whom chmod 000 does not"
  echo "   deny read (likely root) -- this sub-case's own precondition does not hold on"
  echo "   this host, honestly skipped rather than fabricated (section 11.4.3)"
fi
chmod 644 "$TMP/i5a_secret.bin"

echo
echo "=== R7-I5(b): write/validate/resume-check crash on an unwritable --out (or --handoff) ==="
mkdir -p "$TMP/notadir_parent"
touch "$TMP/notadir_parent/notadir"
UNWRITABLE_OUT="$TMP/notadir_parent/notadir/out.json"

echo "--- write: unwritable --out ---"
FIXED_ERR="$TMP/i5b_write_out.err"
python3 "$IMPL" write --item-id NONE --agent-key a1 --alias claude1 --model sonnet --effort high \
    --phase PLAN --handoff "$TMP/i5b_write.json" --out "$UNWRITABLE_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && ! grep -q "^Traceback" "$FIXED_ERR"; then
  echo "ok R7-I5(b) (write, unwritable --out) real (fixed) tool: EXIT_USAGE(2), no traceback"
else
  echo "NOT ok R7-I5(b) (write, unwritable --out) real (fixed) tool: rc=$FIXED_RC stderr=$(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
run_against_pinned write --item-id NONE --agent-key a1 --alias claude1 --model sonnet --effort high \
    --phase PLAN --handoff "$TMP/i5b_write.pin.json" --out "$UNWRITABLE_OUT" >"$TMP/i5b_write_out.pin.err" 2>&1
if grep -q "^Traceback" "$TMP/i5b_write_out.pin.err" 2>/dev/null; then
  echo "ok R7-I5(b) (write, unwritable --out) guard-viability: pinned pre-R7-fix copy"
  echo "   CRASHED uncaught -- proving this fixture genuinely catches the R7-I5(b)"
  echo "   regression if the fix is ever reverted"
else
  echo "NOT ok R7-I5(b) (write, unwritable --out) guard-viability BLIND: $(cat "$TMP/i5b_write_out.pin.err" 2>/dev/null)"
  failx
fi

echo "--- write: unwritable --handoff ---"
FIXED_ERR="$TMP/i5b_write_handoff.err"
python3 "$IMPL" write --item-id NONE --agent-key a1 --alias claude1 --model sonnet --effort high \
    --phase PLAN --handoff "$UNWRITABLE_OUT" --out "$TMP/i5b_write_handoff.out.json" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && ! grep -q "^Traceback" "$FIXED_ERR"; then
  echo "ok R7-I5(b) (write, unwritable --handoff) real (fixed) tool: EXIT_USAGE(2), no traceback"
else
  echo "NOT ok R7-I5(b) (write, unwritable --handoff) real (fixed) tool: rc=$FIXED_RC stderr=$(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
run_against_pinned write --item-id NONE --agent-key a1 --alias claude1 --model sonnet --effort high \
    --phase PLAN --handoff "$UNWRITABLE_OUT" --out "$TMP/i5b_write_handoff.pin.out.json" \
    >"$TMP/i5b_write_handoff.pin.err" 2>&1
if grep -q "^Traceback" "$TMP/i5b_write_handoff.pin.err" 2>/dev/null; then
  echo "ok R7-I5(b) (write, unwritable --handoff) guard-viability: pinned pre-R7-fix"
  echo "   copy CRASHED uncaught -- proving this fixture genuinely catches the"
  echo "   R7-I5(b) regression if the fix is ever reverted"
else
  echo "NOT ok R7-I5(b) (write, unwritable --handoff) guard-viability BLIND: $(cat "$TMP/i5b_write_handoff.pin.err" 2>/dev/null)"
  failx
fi

echo "--- validate: unwritable --out ---"
H="$TMP/i5b_validate.json"
write_real_handoff "$H"
FIXED_ERR="$TMP/i5b_validate.err"
python3 "$IMPL" validate --handoff "$H" --out "$UNWRITABLE_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && ! grep -q "^Traceback" "$FIXED_ERR"; then
  echo "ok R7-I5(b) (validate, unwritable --out) real (fixed) tool: EXIT_USAGE(2), no traceback"
else
  echo "NOT ok R7-I5(b) (validate, unwritable --out) real (fixed) tool: rc=$FIXED_RC stderr=$(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
run_against_pinned validate --handoff "$H" --out "$UNWRITABLE_OUT" >"$TMP/i5b_validate.pin.err" 2>&1
if grep -q "^Traceback" "$TMP/i5b_validate.pin.err" 2>/dev/null; then
  echo "ok R7-I5(b) (validate, unwritable --out) guard-viability: pinned pre-R7-fix"
  echo "   copy CRASHED uncaught -- proving this fixture genuinely catches the"
  echo "   R7-I5(b) regression if the fix is ever reverted"
else
  echo "NOT ok R7-I5(b) (validate, unwritable --out) guard-viability BLIND: $(cat "$TMP/i5b_validate.pin.err" 2>/dev/null)"
  failx
fi

echo "--- resume-check: unwritable --out ---"
H="$TMP/i5b_resume.json"
write_real_handoff "$H"
FIXED_ERR="$TMP/i5b_resume.err"
python3 "$IMPL" resume-check --handoff "$H" --out "$UNWRITABLE_OUT" >"$FIXED_ERR" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && ! grep -q "^Traceback" "$FIXED_ERR"; then
  echo "ok R7-I5(b) (resume-check, unwritable --out) real (fixed) tool: EXIT_USAGE(2), no traceback"
else
  echo "NOT ok R7-I5(b) (resume-check, unwritable --out) real (fixed) tool: rc=$FIXED_RC stderr=$(cat "$FIXED_ERR" 2>/dev/null)"
  failx
fi
run_against_pinned resume-check --handoff "$H" --out "$UNWRITABLE_OUT" >"$TMP/i5b_resume.pin.err" 2>&1
if grep -q "^Traceback" "$TMP/i5b_resume.pin.err" 2>/dev/null; then
  echo "ok R7-I5(b) (resume-check, unwritable --out) guard-viability: pinned pre-R7-fix"
  echo "   copy CRASHED uncaught -- proving this fixture genuinely catches the"
  echo "   R7-I5(b) regression if the fix is ever reverted"
else
  echo "NOT ok R7-I5(b) (resume-check, unwritable --out) guard-viability BLIND: $(cat "$TMP/i5b_resume.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== Top-level dispatch boundary: main() wraps the subcommand table lookup+call in ONE except Exception boundary ==="
# T140 Round 8 review finding R8-I1 (fixed here): the boundary's own catch
# set was WIDENED from `fc_common.SAFE_EXCEPTIONS` to bare `Exception` (see
# handoff.py's own main() comment) -- this static check is updated to match
# the new reality: it now looks for a bare `except Exception as exc:`
# handler (an `ast.Name` node whose `id == "Exception"`, NOT an
# `ast.Attribute` node -- `fc_common.SAFE_EXCEPTIONS` parses as an
# Attribute, `Exception` parses as a bare Name) that still calls the
# minimal-error-doc writer, and ADDITIONALLY confirms `Exception` is never
# accidentally widened all the way to `BaseException` (which would wrongly
# swallow `SystemExit`/`KeyboardInterrupt` too -- section 11.4.6, never
# silently over-widen a fix beyond what was asked).
BOUNDARY_CHECK=$(python3 - "$IMPL" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1])
found = False
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
                            found = True
if found_base_exception:
    print("BASEEXCEPTION")
else:
    print("1" if found else "0")
PYEOF
)
if [ "$BOUNDARY_CHECK" = "1" ]; then
  echo "ok top-level dispatch boundary: main() wraps its table[cmd_name](args) call in"
  echo "   except Exception and calls the minimal-error-doc writer (never BaseException --"
  echo "   SystemExit/KeyboardInterrupt correctly stay uncaught)"
elif [ "$BOUNDARY_CHECK" = "BASEEXCEPTION" ]; then
  echo "NOT ok top-level dispatch boundary OVER-WIDENED to BaseException -- this would"
  echo "     wrongly swallow SystemExit/KeyboardInterrupt too"
  failx
else
  echo "NOT ok top-level dispatch boundary MISSING or malformed"
  failx
fi
LIVE_ROOT="$TMP/live_boundary"
mkdir -p "$LIVE_ROOT/scripts/fastcycle/orchestration" "$LIVE_ROOT/scripts/fastcycle/lib"
cp "$IMPL" "$LIVE_ROOT/scripts/fastcycle/orchestration/handoff.py"
cp "$LIB" "$LIVE_ROOT/scripts/fastcycle/lib/fc_common.py"
python3 - "$LIVE_ROOT/scripts/fastcycle/orchestration/handoff.py" <<'PYEOF'
import sys
p = sys.argv[1]
# T140 Round 8 review finding R8-I1 minor (b): cmd_write's own body now
# opens with the new _reject_non_utf8_cli_string(...) up-front check (see
# handoff.py's own cmd_write comment), so the mutation anchor is updated to
# match -- still fires BEFORE that check (and every other line of
# cmd_write's own body), proving the boundary catches a crash regardless of
# where in the function it originates.
old = "def cmd_write(a):\n    # T140 Round 8 review finding R8-I1 minor (b) (fixed here): checked\n"
new = ("def cmd_write(a):\n"
       "    raise TypeError('MUTATION_LIVE_BOUNDARY_PROOF: forced unanticipated crash')\n"
       "    # T140 Round 8 review finding R8-I1 minor (b) (fixed here): checked\n")
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
  python3 "$LIVE_ROOT/scripts/fastcycle/orchestration/handoff.py" write --item-id NONE --agent-key a1 \
      --alias claude1 --model sonnet --effort high --phase PLAN --handoff "$TMP/live_boundary.handoff.json" \
      --out "$LIVE_OUT" >"$TMP/live_boundary.err" 2>&1
  LIVE_RC=$?
  if [ "$LIVE_RC" = "2" ] && [ -f "$LIVE_OUT" ] && ! grep -q "^Traceback" "$TMP/live_boundary.err" \
      && grep -q "MUTATION_LIVE_BOUNDARY_PROOF" "$TMP/live_boundary.err" \
      && python3 -c "import json,sys; d=json.load(open('$LIVE_OUT')); sys.exit(0 if d.get('internal_error',{}).get('detail','').find('MUTATION_LIVE_BOUNDARY_PROOF')>=0 else 1)"; then
    echo "ok top-level dispatch boundary LIVE PROOF: a forced, genuinely unanticipated"
    echo "   TypeError raised at the very TOP of cmd_write (before ANY of its own"
    echo "   internal try/excepts could ever run) is caught by main()'s own boundary --"
    echo "   rc=2 (never Python's uncaught-exception default of 1), NO traceback on"
    echo "   stderr, and a real --out document naming the real exception was written"
    echo "   -- this is NOT something any of R7-I5's own individual, targeted fixes"
    echo "   above would have caught by themselves"
  else
    echo "NOT ok top-level dispatch boundary LIVE PROOF FAILED: rc=$LIVE_RC out_exists=$([ -f "$LIVE_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/live_boundary.err" 2>/dev/null)"
    failx
  fi
fi

echo
echo "=== Malformed-input fuzz probe: no traceback ever, rc always in {0,1,2}, rc=1 only with an --out file written ==="
H="$TMP/fuzz_base.json"
write_real_handoff "$H"
FUZZ_MUTATIONS=(
  'd["partial_artefacts"] = None'
  'd["partial_artefacts"] = 42'
  'd["partial_artefacts"] = [None]'
  'd["partial_artefacts"] = [42]'
  'd["partial_artefacts"] = [{"path": None}]'
  'd["partial_artefacts"] = [{"path": []}]'
  'd["verified"] = "not-a-list"'
  'd["verified"] = [42]'
  'd["external_deps"] = "not-a-list"'
  'd["pending"] = 42'
  'd["effects_performed"] = None'
  'd["phase"] = 42'
  'd["written_at"] = []'
)
FUZZ_FAIL=0
i=0
for mut in "${FUZZ_MUTATIONS[@]}"; do
  i=$((i + 1))
  f="$TMP/fuzz_$i.json"
  cp "$H" "$f"
  python3 -c "
import json
with open('$f') as fh: d = json.load(fh)
$mut
with open('$f', 'w') as fh: json.dump(d, fh)
"
  for sub in validate resume-check; do
    out="$TMP/fuzz_${i}_${sub}.out.json"
    python3 "$IMPL" "$sub" --handoff "$f" --out "$out" >"$TMP/fuzz_${i}_${sub}.err" 2>&1
    rc=$?
    if grep -q "^Traceback" "$TMP/fuzz_${i}_${sub}.err"; then
      echo "NOT ok fuzz $sub case $i ($mut): TRACEBACK on stderr: $(cat "$TMP/fuzz_${i}_${sub}.err")"
      FUZZ_FAIL=1
      continue
    fi
    case "$rc" in
      0|1|2) : ;;
      *) echo "NOT ok fuzz $sub case $i ($mut): rc=$rc outside {0,1,2}"; FUZZ_FAIL=1; continue ;;
    esac
    if [ "$rc" = "1" ] && [ ! -f "$out" ]; then
      echo "NOT ok fuzz $sub case $i ($mut): rc=1 (a finding) but NO --out was written"
      FUZZ_FAIL=1
      continue
    fi
  done
done
if [ "$FUZZ_FAIL" = "0" ]; then
  echo "ok malformed-input fuzz probe: $i mutations x 2 subcommands (validate/"
  echo "   resume-check) -- zero tracebacks, every rc in {0,1,2}, every rc=1 paired"
  echo "   with a genuinely-written --out document"
else
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R7 REGRESSION GUARD (handoff.py): ALL CHECKS PASS -- R7-I5(a)'s"
  echo "    partial_artefacts shape validation (non-list, wrong-type path,"
  echo "    unreadable path), R7-I5(b)'s write-guard on write/validate/"
  echo "    resume-check (--out AND --handoff), and the ONE top-level main()"
  echo "    dispatch boundary are all load-bearing: reverting any one of them"
  echo "    makes its own matching pinned pre-fix copy either crash uncaught"
  echo "    or silently misbehave, and the malformed-input fuzz probe found"
  echo "    zero tracebacks/bad-rc/silent-loss cases across every adversarial"
  echo "    document tried. ==="
  exit 0
else
  echo "=== R7 REGRESSION GUARD (handoff.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
