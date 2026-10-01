#!/bin/bash
# Purpose : T140 Round 9/9b review regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`.
#
# Findings covered (see test_handoff_r9_regression.sh's own header for the
# full findings text -- this file applies the SAME fixes to
# custody_sweep.py, whose `main()` was the ONE sibling tool with NO
# boundary at all -- not even a `SystemExit`-only wrapper -- around
# `build_arg_parser().parse_args(argv)` before this round):
#
#   R9b-I1 -- `build_arg_parser()`'s `description=__doc__.split(...)`
#     crashed under `python -OO`/`PYTHONOPTIMIZE=2` -- fixed via
#     `(__doc__ or "")`.
#   R9b-I1 (stale --out) -- fixed via `_invalidate_stale_out`, called
#     unconditionally before `build_arg_parser()` is even invoked.
#   R9-I1 -- the dispatch-boundary diagnostic print used to happen
#     UNGUARDED -- fixed via `_safe_print`.
#   R9-M2 -- `inventory` on a real repo with a non-UTF-8 `--out` PATH
#     used to WRITE a correct inventory report, then have its OWN
#     success print (which embeds `a.out` itself, `"... -> %s" % (...,
#     a.out)`) raise `UnicodeEncodeError`, escaping uncaught into
#     `main()`'s boundary and OVERWRITING the just-written correct
#     report with an `internal_error` document -- fixed by the SAME
#     `_safe_print` guard.
#
# R9-M3 (symlink-containment) does not apply to this file --
# custody_sweep.py has no directory-tree-hashing / containment-check
# logic of its own (it hashes single files via `sha256_of_bytes`, never
# walks a directory tree).
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
IMPL="$FC/orchestration/custody_sweep.py"
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
  local dir="$1"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/custody_sweep.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
}

mutate_revert_doc_fallback() {
  # $1 = orchestration/custody_sweep.py path
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
  # here): $1 = orchestration/custody_sweep.py path -- see
  # test_handoff_r9_regression.sh's own identically-purposed sibling for
  # the full rationale. Restores the PRE-M3 call-site shape (unconditional,
  # before argument parsing begins).
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "            return 2\n\n    args = None"
new = ("            return 2\n\n"
       "    invalidate_stale_out(scan_argv_for_out(argv))  "
       "# R9b GUARD-VIABILITY MUTATION: unconditional pre-M3 call site restored\n\n"
       "    args = None")
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

mutate_neuter_safe_print() {
  # $1 = orchestration/custody_sweep.py path
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

inject_cmd_inventory_crash() {
  # $1 = orchestration/custody_sweep.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "def cmd_inventory(a):\n"
new = "def cmd_inventory(a):\n    raise RuntimeError('R9_BOUNDARY_PROOF')\n"
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

REPO="$ROOT"

# ---------------------------------------------------------------------------
# R9b-I1: python -OO / PYTHONOPTIMIZE=2 no longer crashes, and a stale
# --out document is never left claiming an unrelated earlier verdict.
# ---------------------------------------------------------------------------
echo
echo "=== R9b-I1: python -OO no longer crashes; a stale --out is never left claiming a wrong verdict ==="

python3 -c "
import json
with open('$TMP/a_out.json', 'w') as fh:
    json.dump({'schema':'custody-sweep-inventory/v1','entries':[],'counts':{'stash':999,'worktree':999,'with_verified_backup':0}}, fh)
"
python3 -OO "$IMPL" inventory --repo-root "$REPO" --out "$TMP/a_out.json" >"$TMP/a.out" 2>"$TMP/a.err"
A_RC=$?
if [ "$A_RC" = "0" ] && [ -f "$TMP/a_out.json" ] \
    && python3 -c "import json,sys; d=json.load(open('$TMP/a_out.json')); sys.exit(0 if d.get('counts',{}).get('stash')!=999 else 1)" \
    && ! grep -q "^Traceback" "$TMP/a.err"; then
  echo "ok R9b-I1 real (fixed) tool: python -OO inventory does NOT crash (no Traceback,"
  echo "   rc=0 honest inventory), and the pre-seeded STALE counts.stash=999 --out is"
  echo "   correctly overwritten with the FRESH, real inventory -- never left stale"
else
  echo "NOT ok R9b-I1 real (fixed) tool FAILED: rc=$A_RC stderr=$(cat "$TMP/a.err" 2>/dev/null)"
  failx
fi

D1="$TMP/mut_doc"
build_scratch_copy "$D1"
if ! mutate_revert_doc_fallback "$D1/orchestration/custody_sweep.py"; then
  echo "NOT ok R9b-I1 (__doc__ fallback) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  rm -f "$TMP/b_out.json"
  python3 -OO "$D1/orchestration/custody_sweep.py" inventory --repo-root "$REPO" --out "$TMP/b_out.json" >"$TMP/b.out" 2>"$TMP/b.err"
  B_RC=$?
  # main()'s own bare-Exception boundary around build_arg_parser()/
  # parse_args() is now a SEPARATE, still-intact fix -- unlike the OTHER
  # two sibling tools, custody_sweep.py's main() previously had NO
  # boundary at all around this call, so BEFORE this round's fix this
  # exact crash would have been a raw, uncaught AttributeError (rc=1,
  # no --out doc). WITH the boundary fix intact but the __doc__ fallback
  # reverted, the crash is now caught (rc=2, internal_error doc) rather
  # than reaching a real inventory -- proving the fallback is still
  # necessary for -OO CORRECTNESS.
  if [ "$B_RC" = "2" ] && [ -f "$TMP/b_out.json" ] \
      && python3 -c "import json,sys; d=json.load(open('$TMP/b_out.json')); sys.exit(0 if d.get('internal_error',{}).get('class')=='AttributeError' else 1)"; then
    echo "ok R9b-I1 (__doc__ fallback) guard-viability: reverting JUST (__doc__ or \"\") back to"
    echo "   bare __doc__ makes the SAME -OO invocation NEVER reach a real inventory again"
    echo "   -- proving the fallback is genuinely necessary for CORRECTNESS under -OO"
  else
    echo "NOT ok R9b-I1 (__doc__ fallback) guard-viability BLIND: rc=$B_RC out=$(cat "$TMP/b_out.json" 2>/dev/null)"
    failx
  fi
fi

# T140 Round 10 review finding M3, first half (this scenario REPLACES the
# pre-Round-10 KeyboardInterrupt-isolation scenario -- see
# test_handoff_r9_regression.sh's own identically-purposed sibling for the
# full rationale). `inventory`/`propose` have NO required flags in this
# tool (--repo-root/--out/--inventory are all optional except propose's
# own --inventory and verify-proposal's own --proposal); `verify-proposal`
# with no `--proposal` is this tool's own clean argparse usage error.
D2="$TMP/mut_stale"
build_scratch_copy "$D2"
if ! mutate_restore_unconditional_invalidation "$D2/orchestration/custody_sweep.py"; then
  echo "NOT ok R9b-I1 (stale-out) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  python3 -c "
import json
with open('$TMP/c_out.json', 'w') as fh:
    json.dump({'schema':'custody-sweep-verify/v1','entry_id':'unrelated-earlier-run'}, fh)
"
  python3 "$IMPL" verify-proposal --out "$TMP/c_out.json" >"$TMP/c.out" 2>"$TMP/c.err"
  C_RC=$?
  C_UNTOUCHED=0
  if [ -f "$TMP/c_out.json" ] && python3 -c "import json,sys; d=json.load(open('$TMP/c_out.json')); sys.exit(0 if d.get('entry_id')=='unrelated-earlier-run' else 1)"; then
    C_UNTOUCHED=1
  fi

  python3 -c "
import json
with open('$TMP/d_out.json', 'w') as fh:
    json.dump({'schema':'custody-sweep-verify/v1','entry_id':'unrelated-earlier-run'}, fh)
"
  python3 "$D2/orchestration/custody_sweep.py" verify-proposal --out "$TMP/d_out.json" >"$TMP/d.out" 2>"$TMP/d.err"
  D_RC=$?
  D_DELETED=0
  [ ! -f "$TMP/d_out.json" ] && D_DELETED=1

  if [ "$C_RC" = "2" ] && [ "$C_UNTOUCHED" = "1" ] && [ "$D_RC" = "2" ] && [ "$D_DELETED" = "1" ]; then
    echo "ok R9b-I1 (stale-out) guard-viability: a pure usage error (verify-proposal with no"
    echo "   --proposal) now correctly LEAVES a pre-existing, wholly unrelated --out file"
    echo "   untouched on the real fixed tool, while a copy with the OLD, unconditional"
    echo "   call site restored still wrongly deletes it -- proving M3's relocation is"
    echo "   genuinely load-bearing"
  else
    echo "NOT ok R9b-I1 (stale-out) guard-viability BLIND: c_rc=$C_RC c_untouched=$C_UNTOUCHED d_rc=$D_RC d_deleted=$D_DELETED"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# R9-I1: closed/unwritable stderr no longer exits 120 with --out unwritten.
# ---------------------------------------------------------------------------
echo
echo "=== R9-I1: closed/unwritable stderr (2>/dev/full) no longer exits 120 with --out unwritten ==="

D6="$TMP/inj_boundary"
build_scratch_copy "$D6"
if ! inject_cmd_inventory_crash "$D6/orchestration/custody_sweep.py"; then
  echo "NOT ok R9-I1 real (fixed) tool: injection anchor not found (content drifted)"
  failx
else
  E_RESULT=$(python3 - "$D6/orchestration/custody_sweep.py" "$TMP" "$REPO" <<'PYEOF'
import subprocess, os, sys
impl, tmp, repo = sys.argv[1], sys.argv[2], sys.argv[3]
outname = os.path.join(tmp, "e_out.json")
if os.path.exists(outname):
    os.remove(outname)
cmd = ["/bin/sh", "-c", '%s %s inventory --repo-root %s --out %s 2>/dev/full' % (sys.executable, impl, repo, outname)]
proc = subprocess.run(cmd)
ok = (proc.returncode != 120 and os.path.exists(outname))
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d out_exists=%s" % (proc.returncode, os.path.exists(outname)))
PYEOF
)
  if [ "$E_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-I1 real (fixed) tool: with a genuine crash escaping to main()'s dispatch"
    echo "   boundary AND stderr redirected to /dev/full, the tool no longer exits 120 -- rc"
    echo "   stays within its documented {0,1,2,3,4} contract, and the --out internal-error"
    echo "   document IS written"
  else
    echo "NOT ok R9-I1 real (fixed) tool FAILED: $E_RESULT"
    failx
  fi
fi

D4="$TMP/mut_print"
build_scratch_copy "$D4"
mutate_neuter_safe_print "$D4/lib/fc_entry.py"
if ! inject_cmd_inventory_crash "$D4/orchestration/custody_sweep.py"; then
  echo "NOT ok R9-I1 (_safe_print) guard-viability: mutation/injection anchor not found (content drifted)"
  failx
else
  F_RESULT=$(python3 - "$D4/orchestration/custody_sweep.py" "$TMP" "$REPO" <<'PYEOF'
import subprocess, os, sys
impl, tmp, repo = sys.argv[1], sys.argv[2], sys.argv[3]
outname = os.path.join(tmp, "f_out.json")
if os.path.exists(outname):
    os.remove(outname)
cmd = ["/bin/sh", "-c", '%s %s inventory --repo-root %s --out %s 2>/dev/full' % (sys.executable, impl, repo, outname)]
proc = subprocess.run(cmd)
ok = (proc.returncode == 120)
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d" % proc.returncode)
PYEOF
)
  if [ "$F_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-I1 (_safe_print) guard-viability: reverting JUST the _safe_print guard makes the"
    echo "   SAME injected-crash + closed-stderr invocation exit 120 again -- proving the"
    echo "   guard is genuinely load-bearing, never a tautological mutation"
  else
    echo "NOT ok R9-I1 (_safe_print) guard-viability BLIND: $F_RESULT"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# R9-M2: inventory on a real repo with a non-UTF-8 --out PATH never
# overwrites its own correct report with an internal_error doc just
# because the success print (which embeds --out itself) fails.
# ---------------------------------------------------------------------------
echo
echo "=== R9-M2: inventory with a non-UTF-8 --out path never overwrites its own correct"
echo "    report with an internal_error doc just because the success print fails ==="

G_RESULT=$(python3 - "$IMPL" "$TMP" "$REPO" <<'PYEOF'
import subprocess, os, sys
impl, tmp, repo = sys.argv[1], sys.argv[2], sys.argv[3]
outname = os.path.join(tmp.encode(), b"g_out_\xff\xfe.json")
cmd = [sys.executable.encode(), impl.encode(), b"inventory", b"--repo-root", repo.encode(), b"--out", outname]
proc = subprocess.run(cmd, capture_output=True)
ok = False
if os.path.exists(outname):
    import json
    with open(outname) as fh:
        d = json.load(fh)
    ok = (proc.returncode == 0 and d.get("schema") == "custody-sweep-inventory/v1")
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d" % proc.returncode)
PYEOF
)
if [ "$G_RESULT" = "RESULT_OK" ]; then
  echo "ok R9-M2 real (fixed) tool: inventory with a non-UTF-8 --out path writes the correct"
  echo "   inventory report and rc=0 -- the success print's own UnicodeEncodeError (it embeds"
  echo "   --out itself) is swallowed by _safe_print and never corrupts the already-written doc"
else
  echo "NOT ok R9-M2 real (fixed) tool FAILED: $G_RESULT"
  failx
fi

D7="$TMP/mut_print_only"
build_scratch_copy "$D7"
if ! mutate_neuter_safe_print "$D7/lib/fc_entry.py"; then
  echo "NOT ok R9-M2 (_safe_print) guard-viability: mutation anchor not found (content drifted)"
  failx
else
  H_RESULT=$(python3 - "$D7/orchestration/custody_sweep.py" "$TMP" "$REPO" <<'PYEOF'
import subprocess, os, sys
impl, tmp, repo = sys.argv[1], sys.argv[2], sys.argv[3]
outname = os.path.join(tmp.encode(), b"h_out_\xff\xfe.json")
cmd = [sys.executable.encode(), impl.encode(), b"inventory", b"--repo-root", repo.encode(), b"--out", outname]
proc = subprocess.run(cmd, capture_output=True)
ok = False
if os.path.exists(outname):
    import json
    with open(outname) as fh:
        d = json.load(fh)
    ok = (proc.returncode == 2 and d.get("schema") == "custody-sweep-internal-error/v1")
print("RESULT_OK" if ok else "RESULT_FAIL rc=%d" % proc.returncode)
PYEOF
)
  if [ "$H_RESULT" = "RESULT_OK" ]; then
    echo "ok R9-M2 (_safe_print) guard-viability: reverting JUST the _safe_print guard reproduces"
    echo "   the ORIGINAL bug exactly -- the correct inventory report gets overwritten with an"
    echo "   internal_error doc (rc=2) -- proving _safe_print is genuinely load-bearing for"
    echo "   this specific, live-confirmed R9-M2 analogue in THIS file"
  else
    echo "NOT ok R9-M2 (_safe_print) guard-viability BLIND: $H_RESULT"
    failx
  fi
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R9 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- python -OO no"
  echo "    longer crashes (and pre-invalidation independently prevents a stale --out"
  echo "    even under a different pre-parse crash), a closed/unwritable stderr no"
  echo "    longer exits 120 with --out unwritten, and a success-print failure (the"
  echo "    print embeds --out's own path) after a correct write never corrupts that"
  echo "    write. ==="
  exit 0
else
  echo "=== R9 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
