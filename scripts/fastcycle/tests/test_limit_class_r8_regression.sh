#!/bin/bash
# Purpose : T140 Round 8 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/limit_class.py`.
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check constructed LIVE (a mutated copy that reverts
# JUST the `place` dispatch boundary's own catch set back to the Round 7
# shape, `except fc_common.SAFE_EXCEPTIONS` -- never a checked-in pinned
# pre-R8-fix file, mirroring test_handoff_r8_regression.sh's own
# documented rationale for the same choice):
#
#   R8-I1 -- `main()`'s TWO top-level dispatch boundaries (`place` and
#     `classify`) previously caught only `fc_common.SAFE_EXCEPTIONS` --
#     Round 8's own live fuzzer proved `KeyError`/`IndexError`/
#     `AttributeError`/`RecursionError` still escaped UNCAUGHT through
#     both. Fixed by widening both boundaries to bare `Exception` (never
#     `BaseException`).
#   R8-I1(d) -- `_write_dispatch_internal_error_doc`'s own best-effort
#     write was `except fc_common.SAFE_EXCEPTIONS` alone -- widened to
#     `Exception`, matching the sibling tools' own identical fixes.
#
# House style: mirrors test_handoff_r8_regression.sh's own live-mutation
# guard-viability pattern, applied to this file's `place` dispatch path
# (the one the T140 Round 8 review's own R8 task brief names for this
# tool).
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 8 review's findings text and this
# session's own live reproduction of each one (never imported from, nor
# shared with, limit_class.py's own implementation).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/limit_class.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R8 regression guard: control needle -- fixed tool + lib both exist ==="
for p in "$IMPL" "$LIB"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib both resolve"
fi

# A minimal, valid `place` fixture every injection sub-case below re-uses
# (the injected exception fires BEFORE any of cmd_place's own logic ever
# reads it).
cat > "$TMP/fx.json" <<'EOF'
{"live_agents": 1, "aliases": [{"alias": "claude1", "kind": "native", "operational": true, "near_cap": false}]}
EOF

# ---------------------------------------------------------------------------
# R8-I1: injected {KeyError, IndexError, AttributeError, RecursionError} at
# the very TOP of cmd_place -- before ANY of its own internal
# try/excepts could ever run -- is caught by main()'s widened `place`
# boundary; a SEPARATE live-mutated copy that reverts JUST that boundary's
# own catch set back to `fc_common.SAFE_EXCEPTIONS` crashes UNCAUGHT on
# the SAME injected exception.
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1: {KeyError, IndexError, AttributeError, RecursionError} injected at the top of cmd_place ==="

inject_and_build() {
  local dir="$1" exc="$2"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/limit_class.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 - "$dir/orchestration/limit_class.py" "$exc" <<'PYEOF'
import sys
p, exc = sys.argv[1], sys.argv[2]
old = "def cmd_place(a):\n"
new = "def cmd_place(a):\n    raise %s('R8_TOPINJ_PROOF')\n" % exc
with open(p, encoding="utf-8") as fh:
    c = fh.read()
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

revert_place_boundary_to_r7_shape() {
  # Reverts ONLY the `place` dispatch's own bare `except Exception as
  # exc:` (the R8-I1 boundary) back to the narrower Round 7 shape,
  # leaving `classify`'s own boundary + every other R8 fix untouched.
  #
  # T140 Round 9/9b review (anchor updated here): the `place` branch was
  # restructured to close R9b-I1 (argument-parser construction/parsing
  # now live INSIDE this same try, plus a new `except SystemExit: raise`
  # clause between the try body and this except clause) -- the anchor
  # text below is updated to match the NEW source shape; the mutation's
  # OWN intent (widen-back-to-SAFE_EXCEPTIONS) is unchanged.
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = ("            return cmd_place(place_args)\n"
       "        except SystemExit:\n")
new_marker_ok = c.count(old) == 1
old2 = "            raise\n        except Exception as exc:\n"
if not new_marker_ok or c.count(old2) != 1:
    sys.exit(1)
c = c.replace(old2, "            raise\n        except fc_common.SAFE_EXCEPTIONS as exc:\n", 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

for exc in KeyError IndexError AttributeError RecursionError; do
  D="$TMP/inj_$exc"
  if ! inject_and_build "$D" "$exc"; then
    echo "NOT ok R8-I1 ($exc) mutation anchor not found (content drifted)"
    failx
    continue
  fi
  OUT="$TMP/inj_${exc}.out.json"
  ERR="$TMP/inj_${exc}.err"
  python3 "$D/orchestration/limit_class.py" place --fixture "$TMP/fx.json" --out "$OUT" >"$ERR" 2>&1
  RC=$?
  if [ "$RC" = "2" ] && [ -f "$OUT" ] && ! grep -q "^Traceback" "$ERR" \
      && grep -q "R8_TOPINJ_PROOF" "$ERR" \
      && python3 -c "import json,sys; d=json.load(open('$OUT')); sys.exit(0 if d.get('internal_error',{}).get('class')=='$exc' else 1)"; then
    echo "ok R8-I1 ($exc) real (fixed) tool: rc=2, no traceback, --out written naming $exc"
  else
    echo "NOT ok R8-I1 ($exc) real (fixed) tool FAILED: rc=$RC out_exists=$([ -f "$OUT" ] && echo yes || echo no) stderr=$(cat "$ERR" 2>/dev/null)"
    failx
    continue
  fi

  if ! revert_place_boundary_to_r7_shape "$D/orchestration/limit_class.py"; then
    echo "NOT ok R8-I1 ($exc) guard-viability: boundary-revert mutation anchor not found (content drifted)"
    failx
    continue
  fi
  OUT2="$TMP/inj_${exc}.r7shape.out.json"
  ERR2="$TMP/inj_${exc}.r7shape.err"
  rm -f "$OUT2"
  python3 "$D/orchestration/limit_class.py" place --fixture "$TMP/fx.json" --out "$OUT2" >"$ERR2" 2>&1
  # T140 Round 10 review, "Recommended root-cause work" item 1: `run_cli_main`
  # now wraps main() in its OWN, OUTER `except Exception` safety net -- see
  # test_handoff_r8_regression.sh's own identically-purposed sibling fix for
  # the full rationale. Reverting JUST the place boundary's own catch set no
  # longer produces a raw, uncaught Python Traceback (the OUTER run_cli_main
  # catch now handles it too); the still-load-bearing, distinguishing signal
  # is that ONLY the widened boundary writes the rich --out internal-error
  # document -- the outer fallback writes none at all.
  if [ ! -f "$OUT2" ] && ! grep -q "^Traceback" "$ERR2" \
      && grep -q "escaped the top-level dispatch entirely" "$ERR2" \
      && grep -Eq "(R8_TOPINJ_PROOF|'R8_TOPINJ_PROOF')" "$ERR2"; then
    echo "ok R8-I1 ($exc) guard-viability: reverting JUST the place boundary's own catch"
    echo "   set back to fc_common.SAFE_EXCEPTIONS makes the SAME injected $exc escape"
    echo "   the place boundary entirely -- no rich --out internal-error document is"
    echo "   written (only run_cli_main's OUTER, tool-agnostic fallback fires instead)"
    echo "   -- proving the Exception widening genuinely does the work, never a"
    echo "   tautological mutation"
  else
    echo "NOT ok R8-I1 ($exc) guard-viability BLIND: out_exists=$([ -f "$OUT2" ] && echo yes || echo no) stderr=$(cat "$ERR2" 2>/dev/null)"
    failx
  fi
done

echo
if [ "$fail" = 0 ]; then
  echo "=== R8 REGRESSION GUARD (limit_class.py): ALL CHECKS PASS -- the widened"
  echo "    except Exception place-dispatch boundary catches KeyError/IndexError/"
  echo "    AttributeError/RecursionError, proven load-bearing via a live"
  echo "    boundary-revert mutation on each. ==="
  exit 0
else
  echo "=== R8 REGRESSION GUARD (limit_class.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
