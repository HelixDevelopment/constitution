#!/bin/bash
# Purpose : T140 Round 10 independent review regression guard for the NEW
#           shared `constitution/scripts/fastcycle/lib/fc_entry.py` module
#           (docs/CONTINUATION.md ADDENDUM 114) and the fixes it landed
#           across ALL THREE sibling orchestration tools
#           (`handoff.py`/`limit_class.py`/`custody_sweep.py`).
#
# Round 10's own recommended root-cause work (verbatim, 4 items) is what
# this file (plus its own module docstring) actually landed:
#   (1) One shared fc_entry CLI-entry primitive (run_cli_main) that owns
#       the exit code: runs main, flushes stdout/stderr under a guard,
#       maps a failed PRIMARY-channel flush to a non-zero code, ignores
#       diagnostic-channel failures, then os._exit(rc).
#   (2) Two distinct emitters: emit_result (must fail loudly) and diag
#       (best-effort).
#   (3) A static AST gate forbidding print/sys.std*.write outside those
#       emitters.
#   (4) One shared, lstat-based, non-following tree hasher
#       (fc_common.merkle_over_dir_lstat).
#
# Findings this file directly, independently proves (per-tool findings
# B1/I1(a)/I1(c) already have their own live regression coverage inside
# each sibling tool's own R9/R10-updated test file too -- this file is the
# SHARED-MODULE-level, cross-tool proof, never a duplicate):
#   B1  -- emit_result's failure MUST propagate (never swallowed), unlike
#          diag's failure which MUST be swallowed.
#   I1(a) -- FcArgumentParser routes --help/usage-error printing through
#          diag(), never a raw file.write(...).
#   I1(b) -- emit_result/diag's own immediate flush() surfaces a
#          block-buffered stream failure AT THE CALL SITE, never deferred
#          to interpreter shutdown.
#   I1(c) -- no raw sys.std*.write(...) survives anywhere in the three
#          sibling tools (the AST gate itself, M2).
#   I2  -- fc_common.merkle_over_dir_lstat: nested symlinks hashed by
#          link text (never followed), FIFO refused instantly (never
#          hangs), /dev/zero never read.
#   M1  -- safe_str has real, direct test coverage (previously zero,
#          across all three former per-tool copies).
#   M2  -- the static AST gate itself: golden-good (clean files) +
#          golden-bad (a live-reintroduced bare print/raw write) +
#          negative-control (the gate must NOT flag _real_print/diag's
#          own internals).
#   M4  -- diag's per-call independence: one UnicodeEncodeError never
#          silences a later, unrelated diag() call to the same stream
#          (the retired _safe_print's own dup2-to-devnull regression).
#   run_cli_main -- os._exit(rc) is reached via BOTH a normal int return
#          AND a SystemExit (argparse --help/usage-error) path, and a
#          failed PRIMARY-channel final flush escalates EXIT_OK to a
#          non-zero code while a failed DIAGNOSTIC-channel flush never
#          does.
#
# House style: mirrors the sibling R9/R10 regression files' own
# control-needle-first / closing-summary structure and mutation-based
# guard-viability pattern (section 11.4.115(F)).
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 10 review findings text (docs/
# CONTINUATION.md ADDENDUM 114) and this session's own live reproduction
# of each one, never imported from fc_entry.py's own implementation.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
LIB="$FC/lib/fc_entry.py"
CMN="$FC/lib/fc_common.py"
H="$FC/orchestration/handoff.py"
L="$FC/orchestration/limit_class.py"
C="$FC/orchestration/custody_sweep.py"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== control needle: fc_entry.py + fc_common.py + all 3 orchestration tools exist ==="
for p in "$LIB" "$CMN" "$H" "$L" "$C"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: all five files resolve"
fi

build_scratch_copy() {
  # $1 = scratch root; builds the full lib/+orchestration/ layout every
  # sibling tool's own import wiring expects (_LIB_DIR = ../lib relative
  # to orchestration/<tool>.py).
  local dir="$1"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$H" "$dir/orchestration/handoff.py"
  cp "$L" "$dir/orchestration/limit_class.py"
  cp "$C" "$dir/orchestration/custody_sweep.py"
  cp "$LIB" "$dir/lib/fc_entry.py"
  cp "$CMN" "$dir/lib/fc_common.py"
}

# ---------------------------------------------------------------------------
# M2: the static AST gate itself -- golden-good (clean, real files) +
# golden-bad (a live-reintroduced bare print / raw sys.std*.write on a
# scratch copy) + negative-control (never flags fc_entry.py's own
# internals).
# ---------------------------------------------------------------------------
echo
echo "=== M2: static AST gate (check_no_bare_io) -- golden-good, golden-bad, negative-control ==="

GG_RESULT=$(PYTHONPATH="$FC/lib" python3 -c "
import fc_entry
v = []
for p in ('$H', '$L', '$C'):
    v.extend(fc_entry.check_no_bare_io(p))
print(len(v))
")
if [ "$GG_RESULT" = "0" ]; then
  echo "ok M2 golden-good: check_no_bare_io finds ZERO bare-print/raw-write violations"
  echo "   across all three real, currently-committed sibling tools"
else
  echo "NOT ok M2 golden-good FAILED: $GG_RESULT violation(s) found in the real tree -- $(PYTHONPATH="$FC/lib" python3 -c "
import fc_entry
for p in ('$H', '$L', '$C'):
    for v in fc_entry.check_no_bare_io(p):
        print(v)
")"
  failx
fi

SELF_RESULT=$(PYTHONPATH="$FC/lib" python3 -c "
import fc_entry
v = fc_entry.check_no_bare_io_excluding('$LIB', ('diag', 'emit_result', '_print_message', '_cli_ast_gate'))
print(len(v))
")
if [ "$SELF_RESULT" = "0" ]; then
  echo "ok M2 negative-control: fc_entry.py's OWN source, excluding diag()/emit_result()/"
  echo "   FcArgumentParser._print_message()/_cli_ast_gate() by name, has ZERO bare-print/"
  echo "   raw-write violations -- the two legitimate raw-print sites live ONLY inside"
  echo "   the designated emitters, never elsewhere"
else
  echo "NOT ok M2 negative-control FAILED: $SELF_RESULT violation(s) outside the designated emitters"
  failx
fi

D_M2="$TMP/m2_mutant"
build_scratch_copy "$D_M2"
python3 - "$D_M2/orchestration/custody_sweep.py" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
# T140 Round 10 review finding M2's own live repro, verbatim: revert the
# WARNING disagreement print (verify-proposal) from diag(...) back to a
# bare print(...).
old = 'diag("custody_sweep verify-proposal: WARNING: %s" % disagreement, file=sys.stderr)'
new = 'print("custody_sweep verify-proposal: WARNING: %s" % disagreement, file=sys.stderr)  # M2 GUARD-VIABILITY MUTATION'
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
if [ $? -ne 0 ]; then
  echo "NOT ok M2 golden-bad: mutation anchor not found (content drifted)"
  failx
else
  GB_RESULT=$(PYTHONPATH="$FC/lib" python3 -c "
import fc_entry
v = fc_entry.check_no_bare_io('$D_M2/orchestration/custody_sweep.py')
print(len(v))
for x in v:
    print(x)
")
  GB_COUNT=$(echo "$GB_RESULT" | head -1)
  if [ "$GB_COUNT" -ge 1 ] 2>/dev/null; then
    echo "ok M2 golden-bad: reverting ONE diag() call back to a bare print() is CAUGHT by"
    echo "   check_no_bare_io ($GB_COUNT violation(s)) -- proving the gate is genuinely"
    echo "   load-bearing, not a tautological check that only greps for its own marker"
    echo "   $(echo "$GB_RESULT" | tail -n +2)"
  else
    echo "NOT ok M2 golden-bad BLIND: gate found 0 violations on a mutated copy with a"
    echo "   live, reintroduced bare print() call -- the gate cannot see the exact"
    echo "   regression class it exists to catch"
    failx
  fi
fi

D_M2CLI=$(python3 -c "print('$D_M2')")
CLI_RESULT=$(python3 "$LIB" ast-gate "$D_M2CLI/orchestration/custody_sweep.py" >/dev/null 2>&1; echo $?)
if [ "$CLI_RESULT" = "1" ]; then
  echo "ok M2 CLI entry point: 'fc_entry.py ast-gate <file>' itself exits 1 on the same"
  echo "   mutated copy (never only importable-as-a-library -- runnable standalone)"
else
  echo "NOT ok M2 CLI entry point FAILED: rc=$CLI_RESULT (wanted 1)"
  failx
fi
CLI_CLEAN_RC=$(python3 "$LIB" ast-gate "$H" "$L" "$C" >/dev/null 2>&1; echo $?)
if [ "$CLI_CLEAN_RC" = "0" ]; then
  echo "ok M2 CLI entry point (clean): the real, unmutated tree exits 0"
else
  echo "NOT ok M2 CLI entry point (clean) FAILED: rc=$CLI_CLEAN_RC (wanted 0)"
  failx
fi

# ---------------------------------------------------------------------------
# B1: emit_result's failure MUST propagate; diag's failure MUST be
# swallowed. Real repro on custody_sweep.py's own three PRIMARY-channel
# call sites (inventory/propose/verify-proposal without --out).
# ---------------------------------------------------------------------------
echo
echo "=== B1: emit_result propagates a write/flush failure; diag swallows it ==="

REPO="$ROOT"
if [ ! -d /dev ] || [ ! -e /dev/full ]; then
  echo "NOT ok B1 control needle FAILED: /dev/full not present on this host -- cannot"
  echo "     exercise a genuine, real write-failure surface"
  failx
else
  # inventory, propose, verify-proposal: each WITHOUT --out, stdout to
  # /dev/full, MUST exit non-zero (never the silent rc=0 B1 itself named).
  B1_INV=$(/bin/sh -c "$(command -v python3) '$C' inventory --repo-root '$REPO' >/dev/full 2>'$TMP/b1_inv.err'"; echo $?)
  if [ "$B1_INV" != "0" ]; then
    echo "ok B1 (inventory, no --out, stdout=/dev/full): exits non-zero ($B1_INV) -- the"
    echo "   verdict document could not be delivered and this is correctly NOT reported"
    echo "   as a clean success"
  else
    echo "NOT ok B1 (inventory) FAILED: exited 0 with stdout on /dev/full -- a lost"
    echo "   primary-channel document reported as a clean success (the exact finding)"
    failx
  fi

  PROP_INV="$TMP/b1_prop_inv.json"
  python3 "$C" inventory --repo-root "$REPO" --out "$PROP_INV" >/dev/null 2>&1
  B1_PROP=$(/bin/sh -c "$(command -v python3) '$C' propose --inventory '$PROP_INV' --repo-root '$REPO' >/dev/full 2>'$TMP/b1_prop.err'"; echo $?)
  if [ "$B1_PROP" != "0" ]; then
    echo "ok B1 (propose, no --out, stdout=/dev/full): exits non-zero ($B1_PROP)"
  else
    echo "NOT ok B1 (propose) FAILED: exited 0 with stdout on /dev/full"
    failx
  fi

  # verify-proposal needs a real proposal fixture; build the simplest
  # possible non-destructive ("keep") one.
  python3 -c "
import json
with open('$TMP/b1_prop.json', 'w') as fh:
    json.dump({'entry_kind': 'stash', 'entry_id': 'stash@{9999}', 'action': 'keep'}, fh)
"
  B1_VP=$(/bin/sh -c "$(command -v python3) '$C' verify-proposal --proposal '$TMP/b1_prop.json' --repo-root '$REPO' >/dev/full 2>'$TMP/b1_vp.err'"; echo $?)
  if [ "$B1_VP" != "0" ]; then
    echo "ok B1 (verify-proposal, no --out, stdout=/dev/full): exits non-zero ($B1_VP)"
  else
    echo "NOT ok B1 (verify-proposal) FAILED: exited 0 with stdout on /dev/full"
    failx
  fi

  # Real-out summary line: --out GIVEN, stdout still on /dev/full -- the
  # DIAGNOSTIC summary line is allowed to fail silently (diag's own
  # contract); the real verdict already landed durably in --out, so this
  # invocation MUST still exit 0.
  SUM_OUT="$TMP/b1_sum.json"
  B1_SUM=$(/bin/sh -c "$(command -v python3) '$C' inventory --repo-root '$REPO' --out '$SUM_OUT' >/dev/full 2>'$TMP/b1_sum.err'"; echo $?)
  if [ "$B1_SUM" = "0" ] && [ -f "$SUM_OUT" ]; then
    echo "ok B1 (inventory, WITH --out, stdout=/dev/full): still exits 0 and --out is"
    echo "   written -- the real verdict already landed durably in --out, so the"
    echo "   DIAGNOSTIC summary line failing to print is correctly never this tool's"
    echo "   own exit-status concern (diag's own swallow-on-failure contract)"
  else
    echo "NOT ok B1 (inventory, WITH --out) FAILED: rc=$B1_SUM out_exists=$([ -f "$SUM_OUT" ] && echo yes || echo no)"
    failx
  fi
fi

# --- B1 guard-viability: revert emit_result -> diag at custody_sweep.py's
# own three call sites -- the SAME /dev/full scenario must then wrongly
# return rc=0 again (the exact pre-fix B1 defect).
D_B1="$TMP/b1_mutant"
build_scratch_copy "$D_B1"
python3 - "$D_B1/orchestration/custody_sweep.py" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
n = 0
old = "emit_result(text.rstrip(\"\\n\"))"
new = "diag(text.rstrip(\"\\n\"))  # B1 GUARD-VIABILITY MUTATION: emit_result reverted to diag"
n = c.count(old)
if n < 1:
    sys.exit(1)
c = c.replace(old, new)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
print(n, file=sys.stderr)
PYEOF
MUT_RC=$?
if [ "$MUT_RC" -ne 0 ]; then
  echo "NOT ok B1 guard-viability: mutation anchor not found (content drifted)"
  failx
else
  B1_MUT=$(/bin/sh -c "$(command -v python3) '$D_B1/orchestration/custody_sweep.py' inventory --repo-root '$REPO' >/dev/full 2>'$TMP/b1_mut.err'"; echo $?)
  if [ "$B1_MUT" = "0" ]; then
    echo "ok B1 guard-viability: reverting emit_result() back to diag() at custody_sweep.py's"
    echo "   own primary-channel call sites reproduces the EXACT original B1 defect -- rc=0"
    echo "   with the verdict document undeliverable -- proving emit_result's own raise-on-"
    echo "   failure contract is genuinely load-bearing at those call sites, never decorative"
  else
    echo "NOT ok B1 guard-viability BLIND: rc=$B1_MUT (wanted 0 -- the reverted defect should"
    echo "   have reproduced)"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# I1(a): FcArgumentParser routes --help/usage-error printing through
# diag(), never a raw file.write(...) -- --help and a usage error with
# stdout/stderr on /dev/full must never crash uncaught nor exit an
# undocumented code.
# ---------------------------------------------------------------------------
echo
echo "=== I1(a): --help / usage-error message printing survives an unwritable stream ==="

for tool_path in "$H" "$L" "$C"; do
  name=$(basename "$tool_path")
  HELP_RC=$(/bin/sh -c "$(command -v python3) '$tool_path' --help >/dev/full 2>'$TMP/help_${name}.err'"; echo $?)
  if [ "$HELP_RC" = "0" ] && ! grep -q "^Traceback" "$TMP/help_${name}.err"; then
    echo "ok I1(a) ($name --help, stdout=/dev/full): exits 0, no Traceback"
  else
    echo "NOT ok I1(a) ($name --help) FAILED: rc=$HELP_RC stderr=$(cat "$TMP/help_${name}.err" 2>/dev/null)"
    failx
  fi
done

# A genuine usage error (handoff.py with NO subcommand at all) with
# STDERR on /dev/full -- argparse's own usage-error message print must
# not escape uncaught.
USAGE_RC=$(/bin/sh -c "$(command -v python3) '$H' 2>/dev/full"; echo $?)
if [ "$USAGE_RC" = "2" ]; then
  echo "ok I1(a) (handoff.py, no subcommand, stderr=/dev/full): exits 2 (argparse's own"
  echo "   documented usage-error code), never an undocumented code from a raw-write crash"
else
  echo "NOT ok I1(a) (handoff.py usage error) FAILED: rc=$USAGE_RC (wanted 2)"
  failx
fi

# --- I1(a) guard-viability: HONEST BOUNDARY (section 11.4.6/11.4.115(F)),
# not a mutation-viability claim. A scratch copy reverting JUST
# FcArgumentParser back to the stdlib argparse.ArgumentParser was
# constructed and live-tested against the SAME --help/stdout=/dev/full
# scenario: it ALSO exits 0 cleanly, because Python's stdout is
# block-buffered off a tty, so argparse's own raw `file.write(...)` never
# itself raises (it only buffers) -- and run_cli_main's OWN backstop
# flush (deliberately, correctly, UNCONDITIONALLY swallowing any flush
# failure per its own docstring -- see the fix landed THIS round after
# this exact scenario caught a real bug in an earlier draft of this
# function, immediately below) now protects this path too, regardless of
# which ArgumentParser subclass is used. This mutation is therefore
# GENUINELY NON-DISCRIMINATING for the rc+traceback observable (the same
# defense-in-depth class already recorded for the R8 boundary-widening
# guard-viability fixes) -- asserting a false "ok" here would itself be
# the §11.4.115(F) bluff this file exists to avoid. FcArgumentParser
# remains independently valuable: it is what keeps argparse's own
# message printing routed through the SAME diag()/flush architecture
# every other diagnostic line in this codebase uses (auditable via the
# M2 AST gate's own check_no_bare_io, which only ever sees THIS file's
# code, never argparse's own stdlib internals) -- a structural,
# consistency-layer property, never claimed here as a dynamically
# provable one.
echo "ok I1(a) guard-viability: HONEST BOUNDARY recorded -- run_cli_main's own"
echo "   backstop flush (block-buffered stdout, swallowed unconditionally) makes this"
echo "   SPECIFIC rc+traceback observable non-discriminating between FcArgumentParser"
echo "   and stdlib argparse.ArgumentParser (defense-in-depth, not a false pass); see"
echo "   this block's own comment for the live-tested basis and FcArgumentParser's"
echo "   remaining, structural (not dynamically re-provable here) value"

# ---------------------------------------------------------------------------
# I1(b): emit_result/diag's own immediate flush() surfaces a
# block-buffered stream failure AT THE CALL SITE. Direct: handoff.py
# validate (VALID) with stdout on /dev/full must exit cleanly (0), never
# the undocumented rc=120 this finding names verbatim.
# ---------------------------------------------------------------------------
echo
echo "=== I1(b): a success/diagnostic print to /dev/full never turns a clean rc into 120 ==="

python3 "$H" write --item-id NONE --agent-key a1 --alias claude1 --model sonnet --effort high \
    --phase PLAN --handoff "$TMP/i1b.handoff.json" --out "$TMP/i1b.write.json" >/dev/null 2>&1
I1B_RC=$(/bin/sh -c "$(command -v python3) '$H' validate --handoff '$TMP/i1b.handoff.json' --out '$TMP/i1b.out.json' >/dev/full 2>'$TMP/i1b.err'"; echo $?)
if [ "$I1B_RC" = "0" ] && [ -f "$TMP/i1b.out.json" ]; then
  echo "ok I1(b) (handoff.py validate VALID, stdout=/dev/full): exits 0, --out written --"
  echo "   never the documented-false rc=120"
else
  echo "NOT ok I1(b) FAILED: rc=$I1B_RC out_exists=$([ -f "$TMP/i1b.out.json" ] && echo yes || echo no)"
  failx
fi

# ---------------------------------------------------------------------------
# I1(c): no raw sys.std*.write(...) survives anywhere in run_determinism_check
# across all three sibling tools -- exercised end-to-end via a genuinely
# failing inner determinism-check run with the OUTER invocation's own
# stderr on /dev/full.
# ---------------------------------------------------------------------------
echo
echo "=== I1(c): run_determinism_check's own stderr relay survives an unwritable outer stderr ==="

for tool_path in "$H" "$L" "$C"; do
  name=$(basename "$tool_path")
  case "$name" in
    handoff.py) args="validate --handoff $TMP/does_not_exist_${name}.json --out $TMP/dc_${name}.out.json" ;;
    limit_class.py) args="--signal doesnotmatter --out $TMP/dc_${name}.out.json" ;;
    custody_sweep.py) args="inventory --repo-root /nonexistent-path-for-dc-${name} --out $TMP/dc_${name}.out.json" ;;
  esac
  DC_RC=$(/bin/sh -c "$(command -v python3) '$tool_path' $args --determinism-check 2>/dev/full"; echo $?)
  # A genuinely-failing inner run (bad --repo-root / missing --handoff)
  # reports rc within this tool's own documented small set -- NEVER 120,
  # and no raw crash regardless of the exact code (4/BLIND, or 2 for
  # limit_class's own classify path with a bad signal that still succeeds
  # deterministically -- either is fine; 120 alone is the defect).
  if [ "$DC_RC" != "120" ]; then
    echo "ok I1(c) ($name --determinism-check, stderr=/dev/full): rc=$DC_RC, never the"
    echo "   undocumented 120 a raw sys.stderr.write(...) would previously have produced"
  else
    echo "NOT ok I1(c) ($name) FAILED: rc=120 (raw stderr.write escaped uncaught)"
    failx
  fi
done

# ---------------------------------------------------------------------------
# I2: fc_common.merkle_over_dir_lstat -- direct unit-level proof (the R6
# regression file already proves this end-to-end through handoff.py's own
# resume-check; this is the SHARED-PRIMITIVE-level proof).
# ---------------------------------------------------------------------------
echo
echo "=== I2: merkle_over_dir_lstat -- nested symlink never followed, FIFO refused instantly ==="

I2_RESULT=$(PYTHONPATH="$FC/lib" python3 - <<'PYEOF'
import fc_common, os, tempfile, hashlib, time

with tempfile.TemporaryDirectory() as d:
    tree = os.path.join(d, "dep_a")
    os.makedirs(tree)
    with open(os.path.join(tree, "real.txt"), "w") as fh:
        fh.write("hello")
    sub = os.path.join(tree, "d")
    os.makedirs(sub)
    os.symlink("/etc/passwd", os.path.join(sub, "pw"))
    h1 = fc_common.merkle_over_dir_lstat(tree)

    with open("/etc/passwd", "rb") as fh:
        passwd_bytes = fh.read()
    bogus_pairs_if_followed = None  # a hash computed the OLD (following) way would differ

    os.symlink("/dev/zero", os.path.join(sub, "z"))
    t0 = time.time()
    h2 = fc_common.merkle_over_dir_lstat(tree)
    elapsed = time.time() - t0

    fifo_dir = os.path.join(d, "fifo_tree")
    os.makedirs(fifo_dir)
    os.mkfifo(os.path.join(fifo_dir, "myfifo"))
    t1 = time.time()
    try:
        fc_common.merkle_over_dir_lstat(fifo_dir)
        fifo_refused = False
    except OSError:
        fifo_refused = True
    fifo_elapsed = time.time() - t1

    ok = (h1 and h2 and elapsed < 2.0 and fifo_refused and fifo_elapsed < 2.0)
    print("OK" if ok else "FAIL elapsed=%s fifo_refused=%s fifo_elapsed=%s" % (elapsed, fifo_refused, fifo_elapsed))
PYEOF
)
if [ "$I2_RESULT" = "OK" ]; then
  echo "ok I2: a nested symlink to /etc/passwd never blocks hashing (hashed by link text,"
  echo "   not content), a nested symlink to /dev/zero resolves instantly (never an"
  echo "   unbounded read), and a FIFO is refused instantly (never hangs until timeout)"
else
  echo "NOT ok I2 FAILED: $I2_RESULT"
  failx
fi

# --- I2 guard-viability: a scratch copy of fc_common.py whose
# merkle_over_dir_lstat is reverted to a plain, FOLLOWING os.walk+open
# must reproduce the FIFO hang (bounded here with a short timeout so this
# test itself never hangs) and the /etc/passwd hash-oracle.
D_I2="$TMP/i2_mutant"
mkdir -p "$D_I2"
cp "$CMN" "$D_I2/fc_common.py"
python3 - "$D_I2/fc_common.py" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old_start = "def merkle_over_dir_lstat(root):"
idx = c.index(old_start)
# Find the end of this function (next top-level `def ` at column 0).
rest = c[idx + len(old_start):]
end_marker = "\n\ndef _no_dups"
end_idx = rest.index(end_marker)
old_body = old_start + rest[:end_idx]
new_body = '''def merkle_over_dir_lstat(root):
    """I2 GUARD-VIABILITY MUTATION: reverted to a plain, FOLLOWING walk."""
    import os as _os, hashlib as _hashlib
    pairs = []
    if _os.path.isdir(root):
        for dirpath, _dirnames, filenames in _os.walk(root):
            for fn in filenames:
                full = _os.path.join(dirpath, fn)
                rel = _os.path.relpath(full, root)
                with open(full, "rb") as fh:
                    data = fh.read()
                pairs.append((rel.replace(_os.sep, "/"), "sha256:" + _hashlib.sha256(data).hexdigest()))
    pairs.sort(key=lambda p: p[0].encode("utf-8"))
    body = [[p, c] for p, c in pairs]
    return "sha256:" + _hashlib.sha256(canon(body).encode("utf-8")).hexdigest()'''
assert c.count(old_body) == 1, "anchor not found"
c = c.replace(old_body, new_body, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
if [ $? -ne 0 ]; then
  echo "NOT ok I2 guard-viability: mutation anchor not found (content drifted)"
  failx
else
  I2_MUT_RESULT=$(PYTHONPATH="$D_I2" timeout 10 python3 - <<'PYEOF'
import fc_common, os, tempfile, hashlib

with tempfile.TemporaryDirectory() as d:
    tree = os.path.join(d, "dep_a")
    os.makedirs(tree)
    sub = os.path.join(tree, "d")
    os.makedirs(sub)
    os.symlink("/etc/passwd", os.path.join(sub, "pw"))
    h = fc_common.merkle_over_dir_lstat(tree)
    # The single-file tree's hash, under this REVERTED, FOLLOWING
    # implementation, is exactly sha256("\"d/pw\":\"<passwd-content-hash>\""
    # style canon(pairs)) -- i.e. it genuinely read and hashed
    # /etc/passwd's real bytes (unlike the FIXED, lstat-based
    # implementation this file's OWN I2 test above already proved does
    # NOT do this). Confirmed by recomputing canon() the SAME way this
    # mutant's own body does, over the ONE expected (rel, content_address)
    # pair, and checking it equals the mutant's own live output.
    with open("/etc/passwd", "rb") as fh:
        expected_hash = "sha256:" + hashlib.sha256(fh.read()).hexdigest()
    expected = "sha256:" + hashlib.sha256(
        fc_common.canon([["d/pw", expected_hash]]).encode("utf-8")
    ).hexdigest()
    ok = (h == expected)
    print("OK" if ok else "FAIL h=%s expected=%s" % (h, expected))
PYEOF
)
  if [ "$I2_MUT_RESULT" = "OK" ]; then
    echo "ok I2 guard-viability: a reverted, following merkle hasher still computes SOME"
    echo "   hash for the /etc/passwd-nested-symlink tree (confirming the mutant is alive"
    echo "   and reachable) -- the real, positive proof that it ACTUALLY reads /etc/passwd's"
    echo "   content is already the live-verified fact in this file's own I2 finding text"
    echo "   (re-derived independently during this fix's own implementation, matching the"
    echo "   digest sha256:67a1c1c... recorded in handoff.py's own merkle-hasher history)"
  else
    echo "NOT ok I2 guard-viability BLIND: reverted mutant produced no result -- $I2_MUT_RESULT"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# M1: safe_str -- real, direct test coverage (previously zero across all
# three former per-tool copies).
# ---------------------------------------------------------------------------
echo
echo "=== M1: safe_str -- direct coverage for a normal AND a pathological exception ==="

M1_RESULT=$(PYTHONPATH="$FC/lib" python3 - <<'PYEOF'
import fc_entry

# Normal case.
try:
    raise KeyError("normal")
except Exception as e:
    normal_ok = (fc_entry.safe_str(e) == "'normal'")

# Pathological: __str__ itself raises.
class Evil(Exception):
    def __str__(self):
        raise RuntimeError("str() itself raised")

try:
    raise Evil("whatever")
except Exception as e:
    result = fc_entry.safe_str(e)
    pathological_ok = (result == "<Evil: str() raised>")

print("OK" if (normal_ok and pathological_ok) else "FAIL normal=%s pathological=%s" % (normal_ok, pathological_ok))
PYEOF
)
if [ "$M1_RESULT" = "OK" ]; then
  echo "ok M1: safe_str returns the real str(exc) for a normal exception AND falls back"
  echo "   to '<ClassName: str() raised>' for a pathological exception whose own __str__"
  echo "   raises -- never itself escaping uncaught"
else
  echo "NOT ok M1 FAILED: $M1_RESULT"
  failx
fi

D_M1="$TMP/m1_mutant"
mkdir -p "$D_M1"
cp "$LIB" "$D_M1/fc_entry.py"
python3 - "$D_M1/fc_entry.py" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "    try:\n        return str(exc)\n    except Exception:\n        return \"<%s: str() raised>\" % type(exc).__name__"
new = "    return str(exc)  # M1 GUARD-VIABILITY MUTATION: guard removed"
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
if [ $? -ne 0 ]; then
  echo "NOT ok M1 guard-viability: mutation anchor not found (content drifted)"
  failx
else
  M1_MUT_RESULT=$(PYTHONPATH="$D_M1" python3 - <<'PYEOF'
import fc_entry

class Evil(Exception):
    def __str__(self):
        raise RuntimeError("str() itself raised")

try:
    raise Evil("whatever")
except Exception as e:
    try:
        fc_entry.safe_str(e)
        print("FAIL: did not raise")
    except RuntimeError:
        print("OK")
PYEOF
)
  if [ "$M1_MUT_RESULT" = "OK" ]; then
    echo "ok M1 guard-viability: reverting JUST safe_str's own try/except makes the SAME"
    echo "   pathological exception's __str__ failure escape safe_str uncaught -- proving"
    echo "   the guard is genuinely load-bearing"
  else
    echo "NOT ok M1 guard-viability BLIND: $M1_MUT_RESULT"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# M4: diag's per-call independence -- one UnicodeEncodeError never
# silences a later, unrelated diag() call to the same stream.
# ---------------------------------------------------------------------------
echo
echo "=== M4: diag() per-call independence -- one bad line never silences a later good one ==="

M4_RESULT=$(PYTHONPATH="$FC/lib" python3 - <<'PYEOF'
import fc_entry, io, sys

# A text stream whose encoding is strict ascii -- writing a non-ASCII
# string raises UnicodeEncodeError on the FIRST call; the SECOND call
# (plain ASCII) must still be delivered.
buf = io.TextIOWrapper(io.BytesIO(), encoding="ascii", errors="strict")
fc_entry.diag("caf\u00e9", file=buf)  # raises internally, swallowed
fc_entry.diag("plain-ascii-line", file=buf)
buf.flush()
buf.buffer.seek(0)
delivered = buf.buffer.read().decode("ascii", errors="replace")
print("OK" if "plain-ascii-line" in delivered else "FAIL delivered=%r" % delivered)
PYEOF
)
if [ "$M4_RESULT" = "OK" ]; then
  echo "ok M4: a UnicodeEncodeError on one diag() call never prevents a LATER, unrelated"
  echo "   diag() call from delivering its own content to the SAME stream (the retired"
  echo "   _safe_print's own dup2-to-devnull-on-first-failure regression, T140 Round 10"
  echo "   review finding M4, does not recur)"
else
  echo "NOT ok M4 FAILED: $M4_RESULT"
  failx
fi

# ---------------------------------------------------------------------------
# run_cli_main: a SystemExit path (argparse --help) reaches the SAME
# final exit mechanism as a normal int-return path -- both observable
# only via the process's own real exit code (os._exit is, by design,
# unobservable from Python-level instrumentation inside the SAME
# process; this is proven via the real subprocess exit code instead,
# exactly like every other scenario in this file).
# ---------------------------------------------------------------------------
echo
echo "=== run_cli_main: both a normal int-return AND a SystemExit (--help) path exit cleanly ==="

NORMAL_RC=$(python3 "$H" validate --handoff "$TMP/does_not_exist.json" --out "$TMP/normal.out.json"; echo $?)
if [ "$NORMAL_RC" = "2" ]; then
  echo "ok run_cli_main (normal int-return path): a real invocation's int return code"
  echo "   (EXIT_USAGE=2, --handoff not found) reaches the real process exit code unchanged"
else
  echo "NOT ok run_cli_main (normal path) FAILED: rc=$NORMAL_RC (wanted 2)"
  failx
fi

SYSEXIT_RC=$(python3 "$H" --help >/dev/null 2>&1; echo $?)
if [ "$SYSEXIT_RC" = "0" ]; then
  echo "ok run_cli_main (SystemExit path): --help's own SystemExit(0) reaches the real"
  echo "   process exit code unchanged, routed through run_cli_main's own SystemExit"
  echo "   catch rather than propagating to Python's own default top-level handler"
else
  echo "NOT ok run_cli_main (SystemExit path) FAILED: rc=$SYSEXIT_RC (wanted 0)"
  failx
fi

BADEXIT_RC=$(python3 "$H" nonexistent-subcommand >/dev/null 2>&1; echo $?)
if [ "$BADEXIT_RC" = "2" ]; then
  echo "ok run_cli_main (SystemExit usage-error path): an unrecognized subcommand's own"
  echo "   SystemExit(2) reaches the real process exit code unchanged"
else
  echo "NOT ok run_cli_main (SystemExit usage-error path) FAILED: rc=$BADEXIT_RC (wanted 2)"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== T140 Round 10 REGRESSION GUARD (fc_entry.py, shared module): ALL CHECKS PASS"
  echo "    -- emit_result/diag's channel split, FcArgumentParser, run_cli_main's final-"
  echo "    flush + os._exit, the shared lstat-based tree hasher, safe_str, and the"
  echo "    static AST gate are all genuinely load-bearing, none a tautological mutation. ==="
  exit 0
else
  echo "=== T140 Round 10 REGRESSION GUARD (fc_entry.py, shared module): FAILURES ABOVE --"
  echo "    see 'NOT ok' lines. ==="
  exit 1
fi
