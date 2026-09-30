#!/bin/bash
# Purpose : T140 Round 9/9b review regression guard for
#           `constitution/scripts/fastcycle/orchestration/handoff.py`.
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check constructed LIVE (a mutated copy that reverts
# JUST the one fix under test, on a checked-out COPY of the currently-
# fixed source -- no pinned pre-R9-fix commit is referenced, following
# the SAME live-mutation pattern test_handoff_r8_regression.sh's own
# "LIVE PROOF" sections already use):
#
#   R9b-I1 -- `build_arg_parser()`'s `description=__doc__.split(...)`
#     crashed with an uncaught AttributeError under `python -OO`/
#     `PYTHONOPTIMIZE=2` (docstrings are stripped from compiled bytecode
#     at that optimization level, so `__doc__` is `None`), BEFORE any of
#     `main()`'s own dispatch boundary could run -- fixed via
#     `(__doc__ or "").split(...)`.
#   R9b-I1 (stale --out) -- a crash reaching `main()` BEFORE a fresh
#     document is written for THIS invocation (the `-OO` crash above, or
#     any other pre-parse failure) used to leave a STALE, unrelated
#     earlier `--out` document in place, silently indistinguishable from
#     a genuine fresh result -- fixed via `_invalidate_stale_out`,
#     called unconditionally, before `build_arg_parser()` is even
#     invoked, so a stale doc is removed EVEN WHEN the crash happens
#     before argument parsing can determine anything else.
#   R9-I1 -- every dispatch-boundary diagnostic print used to happen
#     UNGUARDED -- a closed/unwritable stderr (`2>/dev/full`) made the
#     print itself raise, escaping the boundary uncaught and exiting 120
#     (outside this tool's documented {0,1,2} contract) with the --out
#     document NEVER written -- fixed via `_safe_print`.
#   R9-M2 -- `validate` on a non-UTF-8 `--handoff` path used to WRITE a
#     correct VALID report, then have its OWN stdout success print raise
#     `UnicodeEncodeError` on the path's embedded lone surrogates, which
#     escaped uncaught into `main()`'s boundary and OVERWROTE the
#     just-written correct report with an `internal_error` document --
#     fixed by the SAME `_safe_print` guard (R9-I1's fix closes this too,
#     since the print can no longer raise and escape).
#   R9-M3 -- `resume-check`'s lexical (`os.path.normpath`-based)
#     containment check on `external_deps[].locator` never resolved
#     symlinks, so a locator whose lexical form stayed inside
#     `tree_current/` but was actually a SYMLINK pointing outside it
#     (e.g. `tree_current/lnk -> /etc`) sailed through unchanged, and
#     `_merkle_over_dir` then walked the symlink's real target (arbitrary
#     host filesystem) until a filesystem error -- fixed by additionally
#     resolving with `os.path.realpath` and re-checking containment.
#
# House style: mirrors test_handoff_r8_regression.sh's own control-needle-
# first / closing-summary structure.
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 9/9b review findings text (docs/
# CONTINUATION.md ADDENDUM 107 + 108) and this session's own live
# reproduction of each one (never imported from, nor shared with,
# handoff.py's own implementation).
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

echo "=== R9 regression guard: control needle -- fixed tool + lib both exist ==="
for p in "$IMPL" "$LIB"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib both resolve"
fi

build_scratch_copy() {
  # $1 = destination dir
  local dir="$1"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/handoff.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
}

mutate_revert_doc_fallback() {
  # $1 = orchestration/handoff.py path -- reverts R9b-I1's `(__doc__ or
  # "")` fix back to the pre-fix bare `__doc__.split(...)`, leaving EVERY
  # other R9/R9b fix in the file untouched.
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

mutate_restore_unconditional_invalidation() {
  # T140 Round 10 review finding M3, first half, guard-viability (fixed
  # here): $1 = orchestration/<tool>.py path. Restores the PRE-M3 call
  # SITE shape -- `invalidate_stale_out(scan_argv_for_out(argv))` called
  # UNCONDITIONALLY at the top of main(), BEFORE argument parsing even
  # begins -- leaving invalidate_stale_out's OWN implementation (now in
  # lib/fc_entry.py, untouched) exactly as-is. This is the call-site
  # shape M3 proved wrongly deletes a caller's pre-existing, wholly
  # UNRELATED --out file on a PURE usage error (module docstring: "invalidate
  # only happens once the tool is confident it's about to genuinely
  # attempt the operation").
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "            return EXIT_USAGE\n\n    table = {"
new = ("            return EXIT_USAGE\n\n"
       "    invalidate_stale_out(scan_argv_for_out(argv))  "
       "# R9b GUARD-VIABILITY MUTATION: unconditional pre-M3 call site restored\n\n"
       "    table = {")
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
  # path (was: orchestration/handoff.py path -- reverts R9b-I1's stale-doc fix
  # by making `_invalidate_stale_out` an unconditional no-op (an early
  # `return` before its own body runs), leaving EVERY other R9/R9b fix
  # (including the __doc__.split() fix itself) untouched.
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

mutate_neuter_safe_print() {
  # $1 = orchestration/handoff.py path -- reverts R9-I1's/R9-M2's fix by
  # making `_safe_print` call the real `print()` completely unguarded
  # (no try/except at all), leaving EVERY other R9/R9b fix untouched.
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

mutate_disable_symlink_check() {
  # $1 = orchestration/handoff.py path -- reverts R9-M3's fix by forcing
  # the realpath-based containment condition to never fire (`if False:`),
  # leaving the LEXICAL (normpath) check and EVERY other R9/R9b fix
  # untouched -- restores the exact pre-fix behaviour for a symlink whose
  # lexical form passes but whose real target escapes.
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = ('                real_current_dir = os.path.realpath(current_dir)\n'
       '                real_containment_root = os.path.realpath(containment_root)\n'
       '                if (real_current_dir != real_containment_root\n'
       '                        and not real_current_dir.startswith(real_containment_root + os.sep)):\n')
new = ('                real_current_dir = os.path.realpath(current_dir)\n'
       '                real_containment_root = os.path.realpath(containment_root)\n'
       '                if False:  # R9 GUARD-VIABILITY MUTATION: symlink check disabled\n')
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

# A minimal, valid --handoff record fixture (validate's own precondition).
# Generated via the REAL `write` subcommand (never a hand-computed hash --
# `fc_common.body_hash_of` returns a BARE hex digest, no "sha256:" prefix,
# unlike `handoff_id`'s own convention; using the real tool's own write
# path avoids re-deriving that convention by hand and getting it wrong).
build_valid_handoff_fixture() {
  # $1 = destination path
  python3 "$IMPL" write --item-id ATM-1 --agent-key k1 --alias claude1 \
      --model sonnet --effort high --phase PLAN \
      --handoff "$1" --out "$TMP/_valid_fixture_write_out.json" >/dev/null 2>&1
}

# A deliberately TAMPERED --handoff record (body_hash mismatch -> INVALID).
build_tampered_handoff_fixture() {
  # $1 = destination path
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
doc['body_hash'] = 'sha256:TAMPERED'
with open('$1', 'w') as fh:
    fh.write(canon(doc) + '\n')
"
}

# ---------------------------------------------------------------------------
# R9b-I1: python -OO / PYTHONOPTIMIZE=2 no longer crashes, and a stale
# --out document is never left claiming an unrelated earlier verdict.
# ---------------------------------------------------------------------------
echo
echo "=== R9b-I1: python -OO no longer crashes; a stale --out is never left claiming a wrong verdict ==="

build_tampered_handoff_fixture "$TMP/tampered.json"

# --- real (fixed) tool under -OO -------------------------------------------
python3 -c "
import json
with open('$TMP/a_out.json', 'w') as fh:
    json.dump({'schema':'handoff-validate/v1','outcome':'VALID','mismatches':[],'body_hash':'stale-from-an-unrelated-earlier-run'}, fh)
"
python3 -OO "$IMPL" validate --handoff "$TMP/tampered.json" --out "$TMP/a_out.json" >"$TMP/a.out" 2>"$TMP/a.err"
A_RC=$?
if [ "$A_RC" = "1" ] && [ -f "$TMP/a_out.json" ] \
    && python3 -c "import json,sys; d=json.load(open('$TMP/a_out.json')); sys.exit(0 if d.get('outcome')=='INVALID' else 1)" \
    && ! grep -q "^Traceback" "$TMP/a.err"; then
  echo "ok R9b-I1 real (fixed) tool: python -OO validate on a tampered handoff does NOT crash"
  echo "   (no Traceback, rc=1 honest INVALID), and the pre-seeded STALE 'VALID' --out is"
  echo "   correctly overwritten with the FRESH, real INVALID verdict -- never left stale"
else
  echo "NOT ok R9b-I1 real (fixed) tool FAILED: rc=$A_RC out_exists=$([ -f "$TMP/a_out.json" ] && echo yes || echo no) stderr=$(cat "$TMP/a.err" 2>/dev/null)"
  failx
fi

# --- guard-viability: revert (__doc__ or "") -> __doc__ --------------------
# NOTE: point 1 of this round's fix (parser construction/parsing now
# lives INSIDE main()'s own Exception boundary) means reverting ONLY the
# __doc__ fallback no longer produces a raw, uncaught Traceback -- the
# AttributeError is now CAUGHT by that wider boundary (a genuine,
# correct improvement: defense-in-depth). What it STILL proves is that,
# WITHOUT the __doc__ fallback, the real verdict is NEVER computed under
# -OO -- --out ends up an `internal_error` document (class=AttributeError)
# instead of the correct INVALID verdict this tampered fixture must
# produce -- proving the __doc__ fallback is genuinely necessary for
# CORRECTNESS under -OO, distinct from the boundary's own necessity for
# SAFETY (never a tautological mutation: this assertion fails on the
# real, unmutated tool, which DOES reach the correct INVALID verdict).
D1="$TMP/mut_doc"
build_scratch_copy "$D1"
mutate_revert_doc_fallback "$D1/orchestration/handoff.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9b-I1 (__doc__ fallback) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  rm -f "$TMP/b_out.json"
  python3 -OO "$D1/orchestration/handoff.py" validate --handoff "$TMP/tampered.json" --out "$TMP/b_out.json" >"$TMP/b.out" 2>"$TMP/b.err"
  B_RC=$?
  if [ "$B_RC" = "2" ] && [ -f "$TMP/b_out.json" ] \
      && python3 -c "import json,sys; d=json.load(open('$TMP/b_out.json')); sys.exit(0 if d.get('schema')=='handoff-internal-error/v1' and d.get('internal_error',{}).get('class')=='AttributeError' else 1)"; then
    echo "ok R9b-I1 (__doc__ fallback) guard-viability: reverting JUST (__doc__ or \"\") back to"
    echo "   bare __doc__ makes the SAME -OO invocation NEVER reach the real INVALID verdict"
    echo "   again (caught by the wider boundary as an internal_error/AttributeError instead) --"
    echo "   proving the fallback is genuinely necessary for CORRECTNESS, never a tautological mutation"
  else
    echo "NOT ok R9b-I1 (__doc__ fallback) guard-viability BLIND: rc=$B_RC out=$(cat "$TMP/b_out.json" 2>/dev/null) stderr=$(cat "$TMP/b.err" 2>/dev/null)"
    failx
  fi
fi

# --- guard-viability: M3's relocation of invalidate_stale_out -------------
# T140 Round 10 review finding M3, first half (this scenario REPLACES the
# pre-Round-10 KeyboardInterrupt-isolation scenario, which tested a
# property M3 deliberately changed: pre-invalidation used to run
# UNCONDITIONALLY at the top of main(), before ANY argument parsing --
# M3 moved it so it runs ONLY inside the exception-handling path, right
# before a fresh internal-error doc is about to be written, specifically
# so that a PURE, legitimate usage error never deletes a caller's
# pre-existing, wholly UNRELATED --out file merely because a command line
# was typed (module docstring: "invalidation only happens once the tool
# is confident it's about to genuinely attempt the operation"). A
# `KeyboardInterrupt` reaching `build_arg_parser()` now correctly no
# longer triggers invalidation at all (that BaseException is caught by
# NEITHER main()'s own `except Exception` NOR run_cli_main's own
# SystemExit/Exception-only catches) -- a real, INTENDED narrowing of
# scope, not a regression; this scenario instead directly exercises
# M3's own headline property.
D2="$TMP/mut_stale"
build_scratch_copy "$D2"
mutate_restore_unconditional_invalidation "$D2/orchestration/handoff.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9b-I1 (stale-out) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  # FIXED tool: `validate` with NO `--handoff` at all is a pure, clean
  # argparse usage error (rc=2) -- it must NEVER touch a pre-existing,
  # wholly unrelated --out file.
  python3 -c "
import json
with open('$TMP/c_out.json', 'w') as fh:
    json.dump({'schema':'handoff-validate/v1','outcome':'VALID','mismatches':[],'body_hash':'unrelated-earlier-run'}, fh)
"
  python3 "$IMPL" validate --out "$TMP/c_out.json" >"$TMP/c.out" 2>"$TMP/c.err"
  C_RC=$?
  C_UNTOUCHED=0
  if [ -f "$TMP/c_out.json" ] && python3 -c "import json,sys; d=json.load(open('$TMP/c_out.json')); sys.exit(0 if d.get('body_hash')=='unrelated-earlier-run' else 1)"; then
    C_UNTOUCHED=1
  fi

  # MUTATED tool (pre-M3 call-site shape restored -- invalidation
  # unconditional, before parsing): the SAME pure usage error now WRONGLY
  # deletes the pre-existing, unrelated --out file.
  python3 -c "
import json
with open('$TMP/d_out.json', 'w') as fh:
    json.dump({'schema':'handoff-validate/v1','outcome':'VALID','mismatches':[],'body_hash':'unrelated-earlier-run'}, fh)
"
  python3 "$D2/orchestration/handoff.py" validate --out "$TMP/d_out.json" >"$TMP/d.out" 2>"$TMP/d.err"
  D_RC=$?
  D_DELETED=0
  [ ! -f "$TMP/d_out.json" ] && D_DELETED=1

  if [ "$C_RC" = "2" ] && [ "$C_UNTOUCHED" = "1" ] && [ "$D_RC" = "2" ] && [ "$D_DELETED" = "1" ]; then
    echo "ok R9b-I1 (stale-out) guard-viability: T140 Round 10 review finding M3 (fixed"
    echo "   here) moved pre-invalidation OUT of main()'s unconditional top-of-function"
    echo "   call site into the exception-handler path only -- a PURE usage error"
    echo "   (validate with no --handoff) now correctly LEAVES a pre-existing, wholly"
    echo "   unrelated --out file untouched on the real fixed tool (rc=2, file"
    echo "   unchanged), while a copy with the OLD, unconditional call site restored"
    echo "   still wrongly deletes it (rc=2, file gone) -- proving M3's relocation is"
    echo "   genuinely load-bearing, never a tautological mutation"
  else
    echo "NOT ok R9b-I1 (stale-out) guard-viability BLIND: c_rc=$C_RC c_untouched=$C_UNTOUCHED d_rc=$D_RC d_deleted=$D_DELETED"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# R9-I1 + R9-M2: a closed/unwritable stderr no longer escapes uncaught
# (rc != 120, --out is written), and a stdout print failure AFTER a
# correct document was already written never corrupts that document.
#
# The scenario driving the boundary (never merely a malformed --handoff
# path, which cmd_validate refuses EARLY on its own without ever
# attempting a write at all, before main()'s own dispatch boundary is
# even reached -- proven not to exercise this class live, this round):
# a real, injected exception at the TOP of cmd_validate (the SAME
# technique test_handoff_r8_regression.sh's own "LIVE PROOF" sections
# already use), guaranteeing the crash reaches main()'s boundary and its
# --out-writing internal-error path, regardless of any earlier per-field
# validation this file's own cmd_validate performs.
# ---------------------------------------------------------------------------
echo
echo "=== R9-I1: closed/unwritable stderr (2>/dev/full) no longer exits 120 with --out unwritten ==="

inject_cmd_validate_crash() {
  # $1 = destination orchestration/handoff.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "def cmd_validate(a):\n"
new = "def cmd_validate(a):\n    raise RuntimeError('R9_BOUNDARY_PROOF')\n"
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

build_valid_handoff_fixture "$TMP/e_h.json"

D6="$TMP/inj_boundary"
build_scratch_copy "$D6"
inject_cmd_validate_crash "$D6/orchestration/handoff.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9-I1 real (fixed) tool: injection anchor not found (content drifted)"
  failx
else
  E_RESULT=$(python3 - "$D6/orchestration/handoff.py" "$TMP" <<'PYEOF'
import subprocess, os, sys
impl, tmp = sys.argv[1], sys.argv[2]
badname = os.path.join(tmp, "e_h.json")
outname = os.path.join(tmp, "e_out.json")
if os.path.exists(outname):
    os.remove(outname)
cmd = ["/bin/sh", "-c", '%s %s validate --handoff %s --out %s 2>/dev/full' % (sys.executable, impl, badname, outname)]
proc = subprocess.run(cmd)
ok = (proc.returncode != 120 and os.path.exists(outname))
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d out_exists=%s" % (proc.returncode, os.path.exists(outname)))
PYEOF
)
  if [ "$E_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-I1 real (fixed) tool: with a genuine crash escaping to main()'s dispatch"
    echo "   boundary AND stderr redirected to /dev/full, the tool no longer exits 120 -- rc"
    echo "   stays within its documented {0,1,2} contract, and the --out internal-error"
    echo "   document IS written (never lost to a diagnostic-print failure)"
  else
    echo "NOT ok R9-I1 real (fixed) tool FAILED: $E_RESULT"
    failx
  fi
fi

# --- guard-viability: neuter _safe_print ------------------------------------
D4="$TMP/mut_print"
build_scratch_copy "$D4"
mutate_neuter_safe_print "$D4/lib/fc_entry.py"
inject_cmd_validate_crash "$D4/orchestration/handoff.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9-I1 (_safe_print) guard-viability: mutation/injection anchor not found (content drifted)"
  failx
else
  # NOTE: this mutated copy still benefits from the SEPARATE,
  # independently-landed "write --out BEFORE the diagnostic print" fix
  # (point 4 of this round's own prescription -- the doc write in
  # main()'s except-clause is a plain code-ordering change, not part of
  # `_safe_print` itself), so the doc-write survives even with
  # `_safe_print` neutered -- correctly proving those two fixes are
  # BOTH genuinely independent contributors, never that either is
  # decorative. What `_safe_print`'s OWN guard uniquely controls is the
  # EXIT CODE staying within this tool's documented {0,1,2} contract --
  # asserted here -- rather than doc presence, which R9-M2's own
  # guard-viability check immediately above already isolates precisely
  # (there, the ONLY write attempt genuinely depends on `_safe_print`
  # itself, since cmd_validate's success path writes via a DIFFERENT
  # code path that a NEUTERED _safe_print, still reverted here, cannot
  # protect once its own crash reaches main()'s boundary and calls
  # _write_dispatch_internal_error_doc a SECOND time, overwriting the
  # first, correct write).
  F_RESULT=$(python3 - "$D4/orchestration/handoff.py" "$TMP" <<'PYEOF'
import subprocess, os, sys
impl, tmp = sys.argv[1], sys.argv[2]
badname = os.path.join(tmp, "e_h.json")
outname = os.path.join(tmp, "f_out.json")
if os.path.exists(outname):
    os.remove(outname)
cmd = ["/bin/sh", "-c", '%s %s validate --handoff %s --out %s 2>/dev/full' % (sys.executable, impl, badname, outname)]
proc = subprocess.run(cmd)
ok = (proc.returncode == 120)
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d out_exists=%s" % (proc.returncode, os.path.exists(outname)))
PYEOF
)
  if [ "$F_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-I1 (_safe_print) guard-viability: reverting JUST the _safe_print guard (bare,"
    echo "   unprotected print()) makes the SAME injected-crash + closed-stderr invocation"
    echo "   exit 120 again (outside this tool's documented {0,1,2} contract) -- proving the"
    echo "   guard is genuinely load-bearing for the exit-code half of this finding, never a"
    echo "   tautological mutation (the doc-presence half is isolated precisely by R9-M2's own"
    echo "   guard-viability check above, on a scenario where ONLY _safe_print protects the write)"
  else
    echo "NOT ok R9-I1 (_safe_print) guard-viability BLIND: $F_RESULT"
    failx
  fi
fi

echo
echo "=== R9-M2: validate on a non-UTF-8 --handoff path never overwrites its own correct"
echo "    VALID report with an internal_error doc just because the success print fails ==="

build_valid_handoff_fixture "$TMP/valid_src.json"

G_RESULT=$(python3 - "$IMPL" "$TMP" <<'PYEOF'
import subprocess, os, sys
impl, tmp = sys.argv[1], sys.argv[2]
with open(os.path.join(tmp, "valid_src.json"), "rb") as fh:
    content = fh.read()
badname = os.path.join(tmp.encode(), b"g_h_\xff\xfe.json")
with open(badname, "wb") as fh:
    fh.write(content)
outname = os.path.join(tmp.encode(), b"g_out.json")
cmd = [sys.executable.encode(), impl.encode(), b"validate", b"--handoff", badname, b"--out", outname]
proc = subprocess.run(cmd, capture_output=True)
ok = False
if os.path.exists(outname):
    import json
    with open(outname) as fh:
        d = json.load(fh)
    ok = (proc.returncode == 0 and d.get("outcome") == "VALID")
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d" % proc.returncode)
PYEOF
)
if [ "$G_RESULT" = "RESULT_OK" ]; then
  echo "ok R9-M2 real (fixed) tool: validate on a non-UTF-8 --handoff path writes the correct"
  echo "   VALID report and rc=0 -- the stdout success print's own UnicodeEncodeError is"
  echo "   swallowed by _safe_print and never corrupts the already-written correct doc"
else
  echo "NOT ok R9-M2 real (fixed) tool FAILED: $G_RESULT"
  failx
fi

# A SEPARATE scratch copy with ONLY _safe_print neutered (no cmd_validate
# injection -- R9-M2 needs the REAL validate logic to run and succeed,
# producing a genuine correct VALID doc, before the print fails; D4 above
# has cmd_validate unconditionally raising for the R9-I1 boundary check
# and would never reach that success path at all).
D7="$TMP/mut_print_only"
build_scratch_copy "$D7"
mutate_neuter_safe_print "$D7/lib/fc_entry.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9-M2 (_safe_print) guard-viability: mutation anchor not found (content drifted)"
  failx
  H_RESULT="RESULT_FAIL mutation-anchor-not-found"
else
H_RESULT=$(python3 - "$D7/orchestration/handoff.py" "$TMP" <<'PYEOF'
import subprocess, os, sys
impl, tmp = sys.argv[1], sys.argv[2]
with open(os.path.join(tmp, "valid_src.json"), "rb") as fh:
    content = fh.read()
badname = os.path.join(tmp.encode(), b"h_h_\xff\xfe.json")
with open(badname, "wb") as fh:
    fh.write(content)
outname = os.path.join(tmp.encode(), b"h_out.json")
cmd = [sys.executable.encode(), impl.encode(), b"validate", b"--handoff", badname, b"--out", outname]
proc = subprocess.run(cmd, capture_output=True)
ok = False
if os.path.exists(outname):
    import json
    with open(outname) as fh:
        d = json.load(fh)
    ok = (proc.returncode == 2 and d.get("schema") == "handoff-internal-error/v1")
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d" % proc.returncode)
PYEOF
)
fi
if [ "$H_RESULT" = "RESULT_OK" ]; then
  echo "ok R9-M2 (_safe_print) guard-viability: reverting JUST the _safe_print guard (the SAME"
  echo "   mutation as the R9-I1 check above, on a print-only-neutered copy) reproduces the"
  echo "   ORIGINAL bug exactly on this DIFFERENT scenario too -- the correct VALID report"
  echo "   gets overwritten with an internal_error doc (rc=2) -- proving _safe_print is the"
  echo "   SAME genuinely load-bearing fix for both findings"
else
  echo "NOT ok R9-M2 (_safe_print) guard-viability BLIND: $H_RESULT"
  failx
fi

# ---------------------------------------------------------------------------
# R9-M3: resume-check refuses a symlink escaping tree_current/, before
# any filesystem access outside its own declared scope.
# ---------------------------------------------------------------------------
echo
echo "=== R9-M3: resume-check refuses a symlink escaping tree_current/ (lexically-safe, really outside) ==="

mkdir -p "$TMP/sym/tree_current"
ln -sfn /etc "$TMP/sym/tree_current/lnk"
python3 -c "
import hashlib, json
def canon(o):
    return json.dumps(o, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)
pre = {
  'schema': 'fastcycle-handoff/v1',
  'agent_key': 'k1', 'item_id': 'ATM-1', 'alias': 'claude1', 'model': 'sonnet', 'effort': 'high',
  'phase': 'PLAN', 'verified': [], 'pending': [], 'partial_artefacts': [],
  'external_deps': [{'kind': 'git-tree', 'locator': 'lnk', 'content_address': 'sha256:deadbeef'}],
  'effects_performed': [], 'written_at': '2026-01-01T00:00:00Z', 'time_source': 'event_occurred',
}
handoff_id = 'sha256:' + hashlib.sha256(canon(pre).encode()).hexdigest()
doc = dict(pre); doc['handoff_id'] = handoff_id
body = {k: v for k, v in doc.items() if k not in ('run_meta', 'body_hash')}
doc['body_hash'] = 'sha256:' + hashlib.sha256(canon(body).encode()).hexdigest()
with open('$TMP/sym/h.json', 'w') as fh:
    fh.write(canon(doc) + '\n')
"

python3 "$IMPL" resume-check --handoff "$TMP/sym/h.json" --out "$TMP/sym/out.json" >"$TMP/sym.out" 2>"$TMP/sym.err"
if [ -f "$TMP/sym/out.json" ] && grep -q "resolves OUTSIDE its own tree_current/ scope via a SYMLINK" "$TMP/sym/out.json" \
    && ! grep -q '"class":"unverifiable-external-dependency"' "$TMP/sym/out.json"; then
  echo "ok R9-M3 real (fixed) tool: resume-check refuses the symlink-escaping locator BEFORE"
  echo "   _merkle_over_dir ever opens a single file under /etc -- 'malformed-external-dependency',"
  echo "   never the honest-but-unintended 'unverifiable-external-dependency' PermissionError path"
else
  echo "NOT ok R9-M3 real (fixed) tool FAILED: $(cat "$TMP/sym/out.json" 2>/dev/null)"
  failx
fi

# --- guard-viability: disable the realpath re-check -------------------------
D5="$TMP/mut_symlink"
build_scratch_copy "$D5"
mutate_disable_symlink_check "$D5/orchestration/handoff.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R9-M3 guard-viability: mutation anchor not found (content drifted)"
  failx
else
  python3 "$D5/orchestration/handoff.py" resume-check --handoff "$TMP/sym/h.json" --out "$TMP/sym/out2.json" >"$TMP/sym2.out" 2>"$TMP/sym2.err"
  if [ -f "$TMP/sym/out2.json" ] && grep -q '"class": *"unverifiable-external-dependency"' "$TMP/sym/out2.json" \
      && grep -q "PermissionError" "$TMP/sym/out2.json"; then
    echo "ok R9-M3 guard-viability: reverting JUST the realpath containment re-check makes the"
    echo "   SAME symlink-escaping locator sail through the lexical check again, and"
    echo "   _merkle_over_dir walks into /etc until PermissionError (the ORIGINAL bug) --"
    echo "   proving the realpath re-check is genuinely load-bearing, never a tautological mutation"
  else
    echo "NOT ok R9-M3 guard-viability BLIND: $(cat "$TMP/sym/out2.json" 2>/dev/null)"
    failx
  fi
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R9 REGRESSION GUARD (handoff.py): ALL CHECKS PASS -- python -OO no longer"
  echo "    crashes (and the pre-invalidation step independently prevents a stale --out"
  echo "    even under a DIFFERENT pre-parse crash), a closed/unwritable stderr no longer"
  echo "    exits 120 with --out unwritten, a stdout-print failure after a correct write"
  echo "    never corrupts that write, and resume-check refuses a symlink escaping"
  echo "    tree_current/ before touching anything outside it. ==="
  exit 0
else
  echo "=== R9 REGRESSION GUARD (handoff.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
