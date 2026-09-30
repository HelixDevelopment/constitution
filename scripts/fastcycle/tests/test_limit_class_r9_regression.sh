#!/bin/bash
# Purpose : T140 Round 9/9b review regression guard for
#           `constitution/scripts/fastcycle/orchestration/limit_class.py`.
#
# Findings covered (see test_handoff_r9_regression.sh's own header for the
# full findings text -- this file applies the SAME fixes to limit_class.py's
# two entry points, `classify` and `place`):
#
#   R9b-I1 -- `build_arg_parser()`'s (classify's own parser)
#     `description=__doc__.split(...)` crashed under `python -OO`/
#     `PYTHONOPTIMIZE=2` -- fixed via `(__doc__ or "")`.
#     (`build_place_arg_parser` uses a literal `description=` string, was
#     never affected by this specific repro, but its own dispatch
#     boundary is STILL widened defensively -- see limit_class.py's own
#     R9b-I1 comment on that branch.)
#   R9b-I1 (stale --out) -- fixed via `_invalidate_stale_out`, called
#     unconditionally before EITHER of this file's two argument parsers
#     runs.
#   R9-I1 -- every dispatch-boundary diagnostic print (BOTH `place`'s own
#     and `classify`'s own) used to happen UNGUARDED -- fixed via
#     `_safe_print`, identical mechanism to `handoff.py`'s own sibling
#     fix (this file imports/duplicates no code from that file --
#     section 11.4.227 reuse-the-PATTERN, per this file's own established
#     per-file-primitive convention -- but the FIX is mechanically
#     identical and independently verified here).
#
# HONEST BOUNDARY (section 11.4.6): unlike `handoff.py`'s `validate`
# (whose stdout success print embeds the raw `--handoff` PATH, giving a
# direct R9-M2 repro via a non-UTF-8 path), `classify`'s own success
# print (`"limit_class: classified as %s (resets_at=%s)"`) embeds only
# the derived CLASS LABEL and `resets_at` -- both always clean ASCII
# strings this tool itself constructs, never caller-controlled raw text
# -- so no analogous "write succeeds, then a DIFFERENT print of the SAME
# raw value corrupts the good write" repro exists for `classify` today.
# (A `--signal` containing invalid UTF-8 bytes instead makes the WRITE
# ITSELF raise `UnicodeEncodeError` -- caught by cmd_classify's own
# pre-existing `except fc_common.SAFE_EXCEPTIONS`, never reaching
# `main()`'s boundary at all -- verified live below as an existing,
# unrelated-to-R9 safety property, not claimed as an R9-M2 regression
# check.) R9-I1's shared `_safe_print` mechanism is still verified below
# via the SAME genuine boundary-crash-injection technique
# test_handoff_r9_regression.sh uses, which exercises the identical code
# path R9-M2 would use if a repro existed.
#
# R9-M3 (symlink-containment) does not apply to this file -- limit_class.py
# has no directory-tree-hashing / containment-check logic of its own.
#
# House style: mirrors test_handoff_r9_regression.sh's own control-needle-
# first / closing-summary structure and mutation-based guard-viability
# pattern.
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 9/9b review findings text (docs/
# CONTINUATION.md ADDENDUM 107 + 108) and this session's own live
# reproduction of each one.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/limit_class.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
FIXTURE="$FC/tests/fixtures/alias_spread/as_golden_spread.json"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R9 regression guard: control needle -- fixed tool + lib + fixture all exist ==="
for p in "$IMPL" "$LIB" "$FIXTURE"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib + fixture all resolve"
fi

build_scratch_copy() {
  local dir="$1"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/limit_class.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
}

mutate_revert_doc_fallback() {
  # $1 = orchestration/limit_class.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = 'description=(__doc__ or "").split("\\n\\n")[0])'
new = 'description=__doc__.split("\\n\\n")[0])'
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

mutate_disable_stale_invalidation() {
  # T140 Round 10: _invalidate_stale_out's implementation now lives in
  # lib/fc_entry.py (shared, as invalidate_stale_out) -- $1 = lib/fc_entry.py
  # path (was: orchestration/limit_class.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = 'def invalidate_stale_out(out_path):\n    """Remove any EXISTING'
new = 'def invalidate_stale_out(out_path):\n    return  # R9 GUARD-VIABILITY MUTATION: pre-invalidation disabled\n    """Remove any EXISTING'
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

mutate_restore_unconditional_invalidation() {
  # T140 Round 10 review finding M3, first half, guard-viability (fixed
  # here): $1 = orchestration/limit_class.py path -- see
  # test_handoff_r9_regression.sh's own identically-purposed sibling for
  # the full rationale. Restores the PRE-M3 call-site shape (unconditional,
  # before argv[0]=="place" dispatch / classify's own parsing) -- the SAME
  # single call site covers BOTH `place` and `classify` in this file
  # (module docstring), so this one restoration exercises the usage-error
  # scenario for `classify` (this test's own scenario below).
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "            return EXIT_USAGE\n\n    # T136: dispatch to `place`"
new = ("            return EXIT_USAGE\n\n"
       "    invalidate_stale_out(scan_argv_for_out(argv))  "
       "# R9b GUARD-VIABILITY MUTATION: unconditional pre-M3 call site restored\n\n"
       "    # T136: dispatch to `place`")
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

mutate_neuter_safe_print() {
  # $1 = orchestration/limit_class.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = ('    stream = kwargs.get("file", sys.stdout)\n'
       '    try:\n'
       '        _real_print(*args, **kwargs)\n'
       '        stream.flush()\n'
       '    except Exception:\n'
       '        pass\n')
new = '    _real_print(*args, **kwargs)  # R9 GUARD-VIABILITY MUTATION: guard removed\n'
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

inject_cmd_classify_crash() {
  # $1 = orchestration/limit_class.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "def cmd_classify(a):\n"
new = "def cmd_classify(a):\n    raise RuntimeError('R9_BOUNDARY_PROOF')\n"
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

inject_cmd_place_crash() {
  # $1 = orchestration/limit_class.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "def cmd_place(a):\n"
new = "def cmd_place(a):\n    raise RuntimeError('R9_BOUNDARY_PROOF')\n"
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

# ---------------------------------------------------------------------------
# R9b-I1: python -OO / PYTHONOPTIMIZE=2 no longer crashes on classify, and
# a stale --out document is never left claiming an unrelated earlier verdict.
# ---------------------------------------------------------------------------
echo
echo "=== R9b-I1: python -OO (classify) no longer crashes; a stale --out is never left ==="

python3 -c "
import json
with open('$TMP/a_out.json', 'w') as fh:
    json.dump({'class':'cap','raw':'stale','resets_at':'UNKNOWN'}, fh)
"
python3 -OO "$IMPL" --signal "HTTP 429 retry-after: 30" --out "$TMP/a_out.json" >"$TMP/a.out" 2>"$TMP/a.err"
A_RC=$?
if [ "$A_RC" = "0" ] && [ -f "$TMP/a_out.json" ] \
    && python3 -c "import json,sys; d=json.load(open('$TMP/a_out.json')); sys.exit(0 if d.get('class')=='rate-limited' and d.get('raw')=='HTTP 429 retry-after: 30' else 1)" \
    && ! grep -q "^Traceback" "$TMP/a.err"; then
  echo "ok R9b-I1 real (fixed) tool: python -OO classify does NOT crash (no Traceback,"
  echo "   rc=0 honest classification), and the pre-seeded STALE 'raw':'stale' --out is"
  echo "   correctly overwritten with the FRESH, real classification -- never left stale"
else
  echo "NOT ok R9b-I1 real (fixed) tool FAILED: rc=$A_RC $(cat "$TMP/a_out.json" 2>/dev/null) stderr=$(cat "$TMP/a.err" 2>/dev/null)"
  failx
fi

D1="$TMP/mut_doc"
build_scratch_copy "$D1"
mutate_revert_doc_fallback "$D1/orchestration/limit_class.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9b-I1 (__doc__ fallback) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  rm -f "$TMP/b_out.json"
  python3 -OO "$D1/orchestration/limit_class.py" --signal "HTTP 429 retry-after: 30" --out "$TMP/b_out.json" >"$TMP/b.out" 2>"$TMP/b.err"
  B_RC=$?
  # This mutation only reverts the classify parser's own __doc__ fallback
  # (main()'s own bare-Exception boundary around build_arg_parser()/
  # parse_args() is a SEPARATE, still-intact fix), so the crash is now
  # CAUGHT and reported as a usage error (rc=2) rather than a raw
  # traceback -- proving the fallback is still necessary for classify to
  # ever REACH a real classification under -OO (never a tautological
  # mutation: this assertion fails on the real, unmutated tool, which DOES
  # reach a real classification).
  if [ "$B_RC" = "2" ] && [ -f "$TMP/b_out.json" ] \
      && python3 -c "import json,sys; d=json.load(open('$TMP/b_out.json')); sys.exit(0 if d.get('internal_error',{}).get('class')=='AttributeError' else 1)"; then
    echo "ok R9b-I1 (__doc__ fallback) guard-viability: reverting JUST (__doc__ or \"\") back to"
    echo "   bare __doc__ makes the SAME -OO invocation NEVER reach a real classification again"
    echo "   -- proving the fallback is genuinely necessary for CORRECTNESS under -OO"
  else
    echo "NOT ok R9b-I1 (__doc__ fallback) guard-viability BLIND: rc=$B_RC out=$(cat "$TMP/b_out.json" 2>/dev/null)"
    failx
  fi
fi

# T140 Round 10 review finding M3, first half (this scenario REPLACES the
# pre-Round-10 KeyboardInterrupt-isolation scenario -- see
# test_handoff_r9_regression.sh's own identically-purposed sibling for the
# full rationale). `classify` requires `--signal`, so a bare `--out X`
# with no `--signal` is a clean argparse usage error (rc=2).
D2="$TMP/mut_stale"
build_scratch_copy "$D2"
mutate_restore_unconditional_invalidation "$D2/orchestration/limit_class.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9b-I1 (stale-out) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  python3 -c "
import json
with open('$TMP/c_out.json', 'w') as fh:
    json.dump({'class':'cap','raw':'unrelated-earlier-run','resets_at':'UNKNOWN'}, fh)
"
  python3 "$IMPL" --out "$TMP/c_out.json" >"$TMP/c.out" 2>"$TMP/c.err"
  C_RC=$?
  C_UNTOUCHED=0
  if [ -f "$TMP/c_out.json" ] && python3 -c "import json,sys; d=json.load(open('$TMP/c_out.json')); sys.exit(0 if d.get('raw')=='unrelated-earlier-run' else 1)"; then
    C_UNTOUCHED=1
  fi

  python3 -c "
import json
with open('$TMP/d_out.json', 'w') as fh:
    json.dump({'class':'cap','raw':'unrelated-earlier-run','resets_at':'UNKNOWN'}, fh)
"
  python3 "$D2/orchestration/limit_class.py" --out "$TMP/d_out.json" >"$TMP/d.out" 2>"$TMP/d.err"
  D_RC=$?
  D_DELETED=0
  [ ! -f "$TMP/d_out.json" ] && D_DELETED=1

  if [ "$C_RC" = "2" ] && [ "$C_UNTOUCHED" = "1" ] && [ "$D_RC" = "2" ] && [ "$D_DELETED" = "1" ]; then
    echo "ok R9b-I1 (stale-out) guard-viability: a pure usage error (no --signal) now"
    echo "   correctly LEAVES a pre-existing, wholly unrelated --out file untouched on the"
    echo "   real fixed tool, while a copy with the OLD, unconditional call site restored"
    echo "   still wrongly deletes it -- proving M3's relocation is genuinely load-bearing"
  else
    echo "NOT ok R9b-I1 (stale-out) guard-viability BLIND: c_rc=$C_RC c_untouched=$C_UNTOUCHED d_rc=$D_RC d_deleted=$D_DELETED"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# R9-I1: a closed/unwritable stderr no longer escapes uncaught, for BOTH
# of this file's two dispatch boundaries (classify + place).
# ---------------------------------------------------------------------------
echo
echo "=== R9-I1: closed/unwritable stderr (2>/dev/full) no longer exits 120, classify + place ==="

for BRANCH in classify place; do
  D6="$TMP/inj_${BRANCH}"
  build_scratch_copy "$D6"
  if [ "$BRANCH" = "classify" ]; then
    inject_cmd_classify_crash "$D6/orchestration/limit_class.py"
  else
    inject_cmd_place_crash "$D6/orchestration/limit_class.py"
  fi
  if [ $? -ne 0 ]; then
    echo "NOT ok R9-I1 ($BRANCH) real (fixed) tool: injection anchor not found (content drifted)"
    failx
    continue
  fi

  if [ "$BRANCH" = "classify" ]; then
    ARGS="--signal HTTP_429 --out $TMP/e_${BRANCH}_out.json"
  else
    ARGS="place --fixture $FIXTURE --out $TMP/e_${BRANCH}_out.json"
  fi
  rm -f "$TMP/e_${BRANCH}_out.json"
  E_RESULT=$(python3 - "$D6/orchestration/limit_class.py" "$TMP" "$BRANCH" "$FIXTURE" <<'PYEOF'
import subprocess, os, sys
impl, tmp, branch, fixture = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
outname = os.path.join(tmp, "e_%s_out.json" % branch)
if branch == "classify":
    args = "--signal HTTP_429 --out %s" % outname
else:
    args = "place --fixture %s --out %s" % (fixture, outname)
cmd = ["/bin/sh", "-c", '%s %s %s 2>/dev/full' % (sys.executable, impl, args)]
proc = subprocess.run(cmd)
ok = (proc.returncode != 120 and os.path.exists(outname))
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d out_exists=%s" % (proc.returncode, os.path.exists(outname)))
PYEOF
)
  if [ "$E_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-I1 ($BRANCH) real (fixed) tool: with a genuine crash escaping to main()'s"
    echo "   dispatch boundary AND stderr redirected to /dev/full, the tool no longer exits"
    echo "   120, and the --out internal-error document IS written"
  else
    echo "NOT ok R9-I1 ($BRANCH) real (fixed) tool FAILED: $E_RESULT"
    failx
    continue
  fi

  mutate_neuter_safe_print "$D6/lib/fc_entry.py"
  if [ $? -ne 0 ]; then
    echo "NOT ok R9-I1 ($BRANCH) guard-viability: mutation anchor not found (content drifted)"
    failx
    continue
  fi
  rm -f "$TMP/f_${BRANCH}_out.json"
  F_RESULT=$(python3 - "$D6/orchestration/limit_class.py" "$TMP" "$BRANCH" "$FIXTURE" <<'PYEOF'
import subprocess, os, sys
impl, tmp, branch, fixture = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
outname = os.path.join(tmp, "f_%s_out.json" % branch)
if branch == "classify":
    args = "--signal HTTP_429 --out %s" % outname
else:
    args = "place --fixture %s --out %s" % (fixture, outname)
cmd = ["/bin/sh", "-c", '%s %s %s 2>/dev/full' % (sys.executable, impl, args)]
proc = subprocess.run(cmd)
ok = (proc.returncode == 120)
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d" % proc.returncode)
PYEOF
)
  if [ "$F_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-I1 ($BRANCH) guard-viability: reverting JUST the _safe_print guard makes the"
    echo "   SAME injected-crash + closed-stderr invocation exit 120 again -- proving the"
    echo "   guard is genuinely load-bearing, never a tautological mutation"
  else
    echo "NOT ok R9-I1 ($BRANCH) guard-viability BLIND: $F_RESULT"
    failx
  fi
done

# ---------------------------------------------------------------------------
# Documented, honestly-verified NON-finding: a non-UTF-8 --signal fails
# CLOSED at the write site (fc_common.SAFE_EXCEPTIONS), never reaches
# main()'s boundary at all -- confirms this file has no R9-M2-shaped gap
# for classify (see the file header's own HONEST BOUNDARY note).
# ---------------------------------------------------------------------------
echo
echo "=== Honest boundary check: non-UTF-8 --signal fails closed at the write site, never main()'s boundary ==="
G_RESULT=$(python3 - "$IMPL" "$TMP" <<'PYEOF'
import subprocess, os, sys
impl, tmp = sys.argv[1], sys.argv[2]
outname = os.path.join(tmp.encode(), b"g_out.json")
sig = b"HTTP 429 " + b"\xff\xfe" + b" retry-after: 30"
cmd = [sys.executable.encode(), impl.encode(), b"--signal", sig, b"--out", outname]
proc = subprocess.run(cmd, capture_output=True)
ok = (proc.returncode == 2 and not os.path.exists(outname) and b"cannot write" in proc.stderr)
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d out_exists=%s stderr=%r" % (proc.returncode, os.path.exists(outname), proc.stderr))
PYEOF
)
if [ "$G_RESULT" = "RESULT_OK" ]; then
  echo "ok honest-boundary: a non-UTF-8 --signal is refused at the write site itself (rc=2,"
  echo "   no --out written, diagnosable 'cannot write' message) -- confirms no doc is EVER"
  echo "   written for this scenario, so there is no good doc for a later print to corrupt,"
  echo "   and this file genuinely has no R9-M2 analogue for classify (as documented above)"
else
  echo "NOT ok honest-boundary FAILED (this file's own assumption about its lack of an R9-M2"
  echo "   analogue no longer holds -- investigate): $G_RESULT"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R9 REGRESSION GUARD (limit_class.py): ALL CHECKS PASS -- python -OO (classify)"
  echo "    no longer crashes (and pre-invalidation independently prevents a stale --out"
  echo "    even under a different pre-parse crash), a closed/unwritable stderr no longer"
  echo "    exits 120 on EITHER dispatch boundary (classify or place), and the honest"
  echo "    absence of an R9-M2 analogue for this file is confirmed rather than assumed. ==="
  exit 0
else
  echo "=== R9 REGRESSION GUARD (limit_class.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
