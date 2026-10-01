#!/bin/bash
# Purpose : T140 Round 8 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/handoff.py`.
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check constructed LIVE (a mutated copy that reverts
# JUST the boundary's own catch set back to the Round 7 shape, `except
# fc_common.SAFE_EXCEPTIONS`, never a checked-in pinned pre-R8-fix file --
# no such commit exists yet to extract one from at authoring time, so this
# file follows the SAME live-mutation pattern the R7 regression files'
# own "LIVE PROOF" sections already use, applied here as the genuine
# guard-viability check rather than a supplementary confirmation):
#
#   R8-I1 -- `main()`'s top-level dispatch boundary previously caught only
#     `fc_common.SAFE_EXCEPTIONS` (TypeError/ValueError/OSError/
#     OverflowError) -- Round 8's own live fuzzer (5,000 random-field-
#     mutation variants) proved `KeyError`/`IndexError`/`AttributeError`/
#     `RecursionError` still escaped UNCAUGHT through that boundary.
#     Fixed by widening the boundary to bare `Exception` (never
#     `BaseException` -- `SystemExit`/`KeyboardInterrupt` must stay
#     uncaught).
#   R8-I1(b) -- `write` with a non-UTF-8 `--handoff` path used to write
#     the handoff RECORD file successfully, then choke writing the
#     REPORT (`--out`) document (which embeds the raw path as a JSON
#     string field) and report the whole command as FAILED -- a real
#     success reported as a failure. Fixed by refusing UP FRONT, before
#     any write of any kind.
#   R8-I1(e) -- `resume-check`'s `external_deps[].locator` was joined
#     onto `tree_current/` WITHOUT sanitizing it first -- an absolute
#     locator (or a `..`-escaping relative one) let this tool inspect
#     ARBITRARY host filesystem paths outside its own dependency-tree
#     scope. Fixed by a containment check (via `os.path.normpath`)
#     BEFORE any filesystem access is attempted.
#
# House style: mirrors test_handoff_r7_regression.sh's own control-needle-
# first / closing-summary structure; the "LIVE PROOF" mutation pattern is
# reused verbatim from that same file's own top-level-dispatch-boundary
# section, since R8-I1 IS that same boundary, further widened.
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 8 review's findings text and this
# session's own live reproduction of each one (never imported from, nor
# shared with, handoff.py's own implementation).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/handoff.py"
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

# A minimal, valid --handoff record fixture every injection sub-case below
# re-uses (validate's own precondition -- the injected exception fires
# BEFORE any of cmd_validate's own field-by-field logic ever reads it, so
# its exact contents are irrelevant to what is being proven here, only its
# existence-and-parseability is).
python3 -c "
import hashlib, json
def canon(o):
    return json.dumps(o, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)
pre = {
  'schema': 'fastcycle-handoff/v1',
  'agent_key': 'k1', 'item_id': 'ATM-1', 'alias': 'claude1', 'model': 'sonnet', 'effort': 'high',
  'phase': 'PLAN', 'verified': [], 'pending': [], 'partial_artefacts': [], 'external_deps': [],
  'effects_performed': [], 'written_at': '2026-01-01T00:00:00Z', 'time_source': 'event_occurred',
}
handoff_id = 'sha256:' + hashlib.sha256(canon(pre).encode()).hexdigest()
doc = dict(pre); doc['handoff_id'] = handoff_id
body = {k: v for k, v in doc.items() if k not in ('run_meta', 'body_hash')}
doc['body_hash'] = hashlib.sha256(canon(body).encode()).hexdigest()
with open('$TMP/h.json', 'w') as fh:
    fh.write(canon(doc) + '\n')
"

# ---------------------------------------------------------------------------
# R8-I1: injected {KeyError, IndexError, AttributeError, RecursionError} at
# the very TOP of cmd_validate -- before ANY of its own internal
# try/excepts (or ANY per-field check the up-front shape check performs)
# could ever run -- is caught by main()'s widened boundary; a SEPARATE
# live-mutated copy that reverts JUST the boundary's own catch set back to
# `fc_common.SAFE_EXCEPTIONS` crashes UNCAUGHT on the SAME injected
# exception, proving the widening genuinely does the work (never a
# tautological mutation that only removes the string a static check
# greps for).
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1: {KeyError, IndexError, AttributeError, RecursionError} injected at the top of cmd_validate ==="

inject_and_build() {
  # $1 = source dir to write into, $2 = exception class name
  local dir="$1" exc="$2"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/handoff.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 - "$dir/orchestration/handoff.py" "$exc" <<'PYEOF'
import sys
p, exc = sys.argv[1], sys.argv[2]
old = "def cmd_validate(a):\n"
new = "def cmd_validate(a):\n    raise %s('R8_TOPINJ_PROOF')\n" % exc
with open(p, encoding="utf-8") as fh:
    c = fh.read()
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

revert_boundary_to_r7_shape() {
  # $1 = orchestration/handoff.py path -- reverts ONLY main()'s bare
  # `except Exception as exc:` (the R8-I1 boundary) back to the narrower
  # Round 7 shape `except fc_common.SAFE_EXCEPTIONS as exc:`, leaving
  # EVERY other R8 fix in the file untouched.
  #
  # T140 Round 9/9b review (anchor updated here): main()'s own body was
  # restructured to close R9b-I1 (argument-parser construction/parsing
  # now live INSIDE this same try, `args`/`cmd_name` resolve via local
  # vars rather than `args.cmd_name` directly) -- the anchor text below
  # is updated to match the NEW source shape; the mutation's OWN intent
  # (widen-back-to-SAFE_EXCEPTIONS) is unchanged.
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = ("        args = build_arg_parser().parse_args(argv)\n"
       "        cmd_name = args.cmd_name\n"
       "        return table[cmd_name](args)\n"
       "    except Exception as exc:\n")
new = ("        args = build_arg_parser().parse_args(argv)\n"
       "        cmd_name = args.cmd_name\n"
       "        return table[cmd_name](args)\n"
       "    except fc_common.SAFE_EXCEPTIONS as exc:\n")
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
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
  python3 "$D/orchestration/handoff.py" validate --handoff "$TMP/h.json" --out "$OUT" >"$ERR" 2>&1
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

  # Guard-viability: SAME injected exception, on a SEPARATE copy whose
  # boundary is reverted to the R7 shape -- must crash uncaught.
  if ! revert_boundary_to_r7_shape "$D/orchestration/handoff.py"; then
    echo "NOT ok R8-I1 ($exc) guard-viability: boundary-revert mutation anchor not found (content drifted)"
    failx
    continue
  fi
  OUT2="$TMP/inj_${exc}.r7shape.out.json"
  ERR2="$TMP/inj_${exc}.r7shape.err"
  rm -f "$OUT2"
  python3 "$D/orchestration/handoff.py" validate --handoff "$TMP/h.json" --out "$OUT2" >"$ERR2" 2>&1
  # KeyError's own __str__ quotes its single argument (`KeyError:
  # 'R8_TOPINJ_PROOF'`); every other exception class here does not
  # (`IndexError: R8_TOPINJ_PROOF`) -- match EITHER shape rather than
  # assume one, never a tautological mutation-detection false-negative.
  # T140 Round 10 review, "Recommended root-cause work" item 1: `run_cli_main`
  # now wraps main() in its OWN, OUTER `except Exception` safety net (see
  # fc_entry.run_cli_main's own docstring) -- so reverting JUST main()'s own
  # internal boundary back to fc_common.SAFE_EXCEPTIONS no longer produces a
  # raw, uncaught Python Traceback (the OUTER run_cli_main catch now handles
  # it too) -- the genuinely DISTINGUISHING, still-load-bearing signal is
  # that main()'s OWN widened boundary is what writes the RICH --out
  # internal-error document naming the exact exception class (via
  # `_write_dispatch_internal_error_doc`); the OUTER run_cli_main fallback
  # has no access to `out_path`/`cmd_name` at all, so it can only ever emit
  # its own GENERIC diagnostic with NO --out document written. Asserting
  # "no --out AND the generic outer-boundary message (never a raw
  # Traceback, never the tool-specific per-subcommand message)" is still a
  # genuine, non-tautological guard-viability proof of main()'s OWN
  # widening, even though the process itself no longer crashes uncaught.
  if [ ! -f "$OUT2" ] && ! grep -q "^Traceback" "$ERR2" \
      && grep -q "escaped the top-level dispatch entirely" "$ERR2" \
      && grep -Eq "(R8_TOPINJ_PROOF|'R8_TOPINJ_PROOF')" "$ERR2"; then
    echo "ok R8-I1 ($exc) guard-viability: reverting JUST the boundary's own catch set back"
    echo "   to fc_common.SAFE_EXCEPTIONS makes the SAME injected $exc escape main()'s OWN"
    echo "   boundary entirely -- no rich --out internal-error document is written (only"
    echo "   run_cli_main's OUTER, tool-agnostic fallback fires instead) -- proving the"
    echo "   Exception widening genuinely does the work, never a tautological mutation"
  else
    echo "NOT ok R8-I1 ($exc) guard-viability BLIND: out_exists=$([ -f "$OUT2" ] && echo yes || echo no) stderr=$(cat "$ERR2" 2>/dev/null)"
    failx
  fi
done

# ---------------------------------------------------------------------------
# R8-I1(b): write with a non-UTF-8 --handoff path
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1(b): write with a non-UTF-8 --handoff path refuses UP FRONT, never write-then-report-failure ==="
B_RESULT=$(python3 - "$IMPL" "$TMP" <<'PYEOF'
import subprocess, os, sys
impl, tmp = sys.argv[1], sys.argv[2]
badname = os.path.join(tmp.encode(), b"handoff_\xff\xfe.json")
outname = os.path.join(tmp.encode(), b"b_out.json")
cmd = [sys.executable.encode(), impl.encode(),
       b"write", b"--item-id", b"ATM-1", b"--agent-key", b"k1", b"--alias", b"claude1",
       b"--model", b"sonnet", b"--effort", b"high", b"--phase", b"PLAN",
       b"--handoff", badname, b"--out", outname]
proc = subprocess.run(cmd, capture_output=True)
ok = (proc.returncode == 2 and not os.path.exists(badname) and not os.path.exists(outname)
      and b"Traceback" not in proc.stderr and b"refused" in proc.stderr)
sys.stderr.write(proc.stderr.decode(errors="replace"))
print("RESULT_OK" if ok else "RESULT_FAIL")
PYEOF
true 2>"$TMP/b_repro.err")
if [ "$B_RESULT" = "RESULT_OK" ]; then
  echo "ok R8-I1(b): a non-UTF-8 --handoff path is refused BEFORE any write is attempted --"
  echo "   neither the handoff record NOR the --out report was written, no traceback,"
  echo "   the stderr message names the refusal explicitly (never a silent or"
  echo "   write-then-report-failure split)"
else
  echo "NOT ok R8-I1(b) FAILED: result=$B_RESULT stderr=$(cat "$TMP/b_repro.err" 2>/dev/null)"
  failx
fi

# ---------------------------------------------------------------------------
# R8-I1(e): resume-check locator path-traversal
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1(e): resume-check refuses an absolute/escaping external_deps[].locator before any filesystem access ==="
for locator_case in 'abs:/etc' 'dotdot:../../../../etc'; do
  label="${locator_case%%:*}"
  locator="${locator_case##*:}"
  python3 -c "
import hashlib, json
def canon(o):
    return json.dumps(o, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)
pre = {
  'schema': 'fastcycle-handoff/v1',
  'agent_key': 'k1', 'item_id': 'ATM-1', 'alias': 'claude1', 'model': 'sonnet', 'effort': 'high',
  'phase': 'PLAN', 'verified': [], 'pending': [], 'partial_artefacts': [],
  'external_deps': [{'kind': 'git-tree', 'locator': '$locator', 'content_address': 'sha256:deadbeef'}],
  'effects_performed': [], 'written_at': '2026-01-01T00:00:00Z', 'time_source': 'event_occurred',
}
handoff_id = 'sha256:' + hashlib.sha256(canon(pre).encode()).hexdigest()
doc = dict(pre); doc['handoff_id'] = handoff_id
body = {k: v for k, v in doc.items() if k not in ('run_meta', 'body_hash')}
doc['body_hash'] = hashlib.sha256(canon(body).encode()).hexdigest()
with open('$TMP/e_${label}.json', 'w') as fh:
    fh.write(canon(doc) + '\n')
"
  OUT="$TMP/e_${label}.out.json"
  python3 "$IMPL" resume-check --handoff "$TMP/e_${label}.json" --out "$OUT" >"$TMP/e_${label}.err" 2>&1
  RC=$?
  if [ -f "$OUT" ] && grep -q "resolves OUTSIDE its own tree_current" "$OUT" 2>/dev/null; then
    echo "ok R8-I1(e) (locator=$label): resume-check refuses the escaping locator, names it in"
    echo "   unsafe_reasons, never touches the filesystem outside its own scope (rc=$RC)"
  else
    echo "NOT ok R8-I1(e) (locator=$label) FAILED: rc=$RC $(cat "$OUT" 2>/dev/null)"
    failx
  fi
done

echo
if [ "$fail" = 0 ]; then
  echo "=== R8 REGRESSION GUARD (handoff.py): ALL CHECKS PASS -- the widened"
  echo "    except Exception dispatch boundary catches KeyError/IndexError/"
  echo "    AttributeError/RecursionError (proven load-bearing via a live"
  echo "    boundary-revert mutation), write's non-UTF-8 --handoff path"
  echo "    refuses up front with no write-then-report-failure split, and"
  echo "    resume-check refuses an absolute or ..-escaping locator before"
  echo "    any filesystem access is attempted. ==="
  exit 0
else
  echo "=== R8 REGRESSION GUARD (handoff.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
