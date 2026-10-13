#!/bin/bash
# Purpose : T140 Round 7 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`
#           -- this IS the "propose-covering test file" the Round 7 resume
#           brief asked to be found or created (none existed before this
#           file: `test_custody_sweep_red.sh` is an absence-check-only RED
#           baseline that never exercises the real tool's live behaviour,
#           and `test_custody_sweep_r6_regression.sh` covers
#           `verify-proposal`/`inventory` but never `propose`'s own
#           `--inventory` malformed-shape handling).
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check that the CHECKED-IN pinned pre-R7-fix copy
# (extracted from this submodule's own HEAD commit
# 898051ce1347221de06b3d0b2c27b005c8f61e42 -- verified, at authoring time,
# to be the exact commit immediately before this Round 7 fix landed, via
# `git status --short` showing only these three orchestration/*.py files
# as uncommitted changes at the moment of extraction) genuinely reproduces
# the pre-fix defect (crashes uncaught, or -- for R7-I6 -- silently fails
# a case the fix makes pass):
#
#   R7-I3 -- `propose` crashes on EVERY class of malformed `--inventory`:
#     missing file (the `open()` call used to sit OUTSIDE any try),
#     non-dict top-level value, non-list `entries`, a non-dict entry, a
#     non-dict `existing_backup`, and a `backup_artifact_path` that is a
#     JSON list (the R6-I3(2) crash class, never closed for `--inventory`).
#   R7-I4 -- `derive_verdict` crashes on an unreadable-but-existing
#     `backup_artifact_path`, and on an `entry_id` that is a JSON int or
#     contains an embedded NUL byte (both fed straight into a real `git`
#     subprocess argv element).
#   R7-I6 -- `selftest`'s own golden-good fixture used to depend on a REAL
#     worktree (`a17eb3df7db2f148a`) that this session legitimately
#     removed; the fix makes that ONE case fully self-contained (a
#     throwaway scratch git repo), never depending on any specific real
#     worktree existing in whichever repo this tool is run against.
#   Top-level dispatch boundary -- `main()` now wraps EVERY subcommand
#     dispatch in ONE `except fc_common.SAFE_EXCEPTIONS` boundary that
#     still writes an honest (if minimal) --out document and returns
#     EXIT_USAGE(2) on a genuinely unanticipated crash, rather than
#     letting Python's own default exit code 1 escape (colliding with
#     this tool's own REFUSED/finding exit code).
#   Malformed-input fuzz probe -- a battery of adversarial `--inventory`/
#     `--proposal` documents (missing keys, wrong types, deeply nested
#     garbage, empty file, binary garbage) asserting: no traceback ever
#     appears on stderr, rc is always in {0,1,2,3,4}, and rc=1 (a genuine
#     finding: REFUSED, or a proposal/expected_verdict disagreement) only
#     ever occurs together with a verdict/output file having genuinely
#     been written -- never a silent crash-with-nothing-written.
#
# House style: mirrors test_custody_sweep_r6_regression.sh's own
# control-needle-first / real-tool-then-pinned-copy / closing-summary
# structure exactly (same repo layout helpers, same run_against_pinned()
# two-directory scratch convention).
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 7 review's findings text and this
# session's own live reproduction of each one (never imported from, nor
# shared with, custody_sweep.py's own implementation).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/custody_sweep"
PINDIR="$FIXDIR/_pinned"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
PINNED="$PINDIR/custody_sweep_pre_r7_fix.py"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== R7 regression guard: control needle -- fixtures + fixed tool + pinned copy all exist ==="
for p in "$IMPL" "$LIB" "$PINNED" \
         "$FIXDIR/cs_r7_inventory_nondict.json" \
         "$FIXDIR/cs_r7_inventory_entries_nonlist.json" \
         "$FIXDIR/cs_r7_inventory_entry_nondict.json" \
         "$FIXDIR/cs_r7_inventory_backup_nondict.json" \
         "$FIXDIR/cs_r7_inventory_backup_path_list.json"; do
  if [ ! -f "$p" ]; then
    echo "NOT ok control needle FAILED: $p not found"
    failx
  fi
done
if [ "$fail" = 0 ]; then
  echo "ok control needle: implementation + lib + pinned pre-R7-fix copy + all five new fixtures resolve"
fi

run_against_pinned() {
  # $1..$N = argv for the pinned copy; writes to stdout/stderr as invoked
  # (identical two-directory scratch convention to
  # test_custody_sweep_r6_regression.sh's own run_against_pinned()).
  mkdir -p "$TMP/orchestration_scratch" "$TMP/lib"
  cp "$PINNED" "$TMP/orchestration_scratch/custody_sweep.py"
  cp "$LIB" "$TMP/lib/fc_common.py"
  cp "$EXLIB" "$TMP/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 "$TMP/orchestration_scratch/custody_sweep.py" "$@"
}

echo
echo "=== R7-I3: propose crashes on every class of malformed --inventory ==="

echo "--- missing --inventory file ---"
FIXED_OUT="$TMP/r73_missing.json"
python3 "$IMPL" propose --inventory "$TMP/definitely_does_not_exist.json" --out "$FIXED_OUT" \
    >"$TMP/r73_missing.err" 2>&1
FIXED_RC=$?
if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/r73_missing.err"; then
  echo "ok R7-I3 (missing file) real (fixed) tool: propose fails closed with EXIT_USAGE (2),"
  echo "   writes no --out, no traceback -- $(cat "$TMP/r73_missing.err")"
else
  echo "NOT ok R7-I3 (missing file) real (fixed) tool: rc=$FIXED_RC out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r73_missing.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/r73_missing.pin.json"
run_against_pinned propose --inventory "$TMP/definitely_does_not_exist.json" --out "$PIN_OUT" \
    >"$TMP/r73_missing.pin.err" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R7-I3 (missing file) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
  failx
elif grep -q "^Traceback" "$TMP/r73_missing.pin.err" 2>/dev/null; then
  echo "ok R7-I3 (missing file) guard-viability: pinned pre-R7-fix copy CRASHED uncaught"
  echo "   (Traceback in stderr, no --out written) -- proving this fixture genuinely"
  echo "   catches the R7-I3 regression if the fix is ever reverted"
else
  echo "NOT ok R7-I3 (missing file) guard-viability BLIND: $(cat "$TMP/r73_missing.pin.err" 2>/dev/null)"
  failx
fi

for case in inventory_nondict:nondict inventory_entries_nonlist:entries-nonlist \
            inventory_entry_nondict:entry-nondict inventory_backup_nondict:backup-nondict \
            inventory_backup_path_list:backup-path-list; do
  fname="cs_r7_${case%%:*}.json"
  label="${case##*:}"
  echo "--- $label ($fname) ---"
  FIXED_OUT="$TMP/r73_${label}.json"
  python3 "$IMPL" propose --inventory "$FIXDIR/$fname" --out "$FIXED_OUT" \
      >"$TMP/r73_${label}.err" 2>&1
  FIXED_RC=$?
  if [ "$FIXED_RC" = "2" ] && [ ! -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/r73_${label}.err"; then
    echo "ok R7-I3 ($label) real (fixed) tool: propose fails closed with EXIT_USAGE (2),"
    echo "   writes no --out, no traceback -- $(cat "$TMP/r73_${label}.err")"
  else
    echo "NOT ok R7-I3 ($label) real (fixed) tool: rc=$FIXED_RC out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r73_${label}.err" 2>/dev/null)"
    failx
  fi
  PIN_OUT="$TMP/r73_${label}.pin.json"
  run_against_pinned propose --inventory "$FIXDIR/$fname" --out "$PIN_OUT" \
      >"$TMP/r73_${label}.pin.err" 2>&1
  if [ -f "$PIN_OUT" ]; then
    echo "NOT ok R7-I3 ($label) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
    echo "     document instead of crashing/failing"
    failx
  elif grep -q "^Traceback" "$TMP/r73_${label}.pin.err" 2>/dev/null; then
    echo "ok R7-I3 ($label) guard-viability: pinned pre-R7-fix copy CRASHED uncaught"
    echo "   (Traceback in stderr, no --out written) -- proving this fixture genuinely"
    echo "   catches the R7-I3 regression if the fix is ever reverted"
  else
    echo "NOT ok R7-I3 ($label) guard-viability BLIND: $(cat "$TMP/r73_${label}.pin.err" 2>/dev/null)"
    failx
  fi
done

echo
echo "=== R7-I4: derive_verdict crashes on unreadable backup / int|NUL entry_id ==="

# A real scratch --repo-root with a real, real-hashed backup file, used by
# all three R7-I4 sub-cases below (unreadable / int entry_id / NUL byte
# entry_id) -- never a checked-in placeholder hash (section 11.4.245: the
# oracle re-derives, it never trusts a stored value).
R74_ROOT="$TMP/r74_repo"
mkdir -p "$R74_ROOT"
# resolve_repo_root() requires a genuine .git to exist at --repo-root
# (cmd_verify_proposal's own precondition, checked BEFORE derive_verdict
# ever runs) -- a plain scratch directory with no .git raises a
# RuntimeError there, never reaching the R7-I4 code paths this section
# means to exercise, so R74_ROOT is a real (if otherwise-empty) git repo.
git init --quiet "$R74_ROOT"
echo "real backup content" > "$R74_ROOT/real_backup.patch"
R74_HASH=$(python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$R74_ROOT/real_backup.patch")

echo "--- unreadable-but-existing backup_artifact_path ---"
touch "$R74_ROOT/unreadable_backup.patch"
chmod 000 "$R74_ROOT/unreadable_backup.patch"
cat > "$TMP/r74_unreadable.json" <<EOF
{"entry_kind": "worktree", "entry_id": "some_id", "action": "retire",
 "backup_hash": "0000000000000000000000000000000000000000000000000000000000000000",
 "backup_artifact_path": "unreadable_backup.patch"}
EOF
FIXED_OUT="$TMP/r74_unreadable.json.out"
python3 "$IMPL" verify-proposal --proposal "$TMP/r74_unreadable.json" --repo-root "$R74_ROOT" --out "$FIXED_OUT" \
    >"$TMP/r74_unreadable.err" 2>&1
FIXED_RC=$?
# We run as a NON-root user here (verified live: `chmod 000` genuinely
# denies read on this host); if this ever runs as root (where a mode-000
# file is still readable), skip this ONE sub-case honestly rather than
# fabricate a result (section 11.4.3 -- never silently pass/fail on a
# precondition that did not hold).
if [ ! -r "$R74_ROOT/unreadable_backup.patch" ]; then
  if [ -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/r74_unreadable.err"; then
    echo "ok R7-I4 (unreadable backup) real (fixed) tool: writes a real --out verdict"
    echo "   (never crashes uncaught) -- $(cat "$FIXED_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("verdict"), d.get("verdict_detail"))' 2>/dev/null)"
  else
    echo "NOT ok R7-I4 (unreadable backup) real (fixed) tool: rc=$FIXED_RC out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r74_unreadable.err" 2>/dev/null)"
    failx
  fi
  PIN_OUT="$TMP/r74_unreadable.pin.json"
  run_against_pinned verify-proposal --proposal "$TMP/r74_unreadable.json" --repo-root "$R74_ROOT" --out "$PIN_OUT" \
      >"$TMP/r74_unreadable.pin.err" 2>&1
  if [ -f "$PIN_OUT" ]; then
    echo "NOT ok R7-I4 (unreadable backup) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
    failx
  elif grep -q "^Traceback" "$TMP/r74_unreadable.pin.err" 2>/dev/null && grep -q "PermissionError" "$TMP/r74_unreadable.pin.err" 2>/dev/null; then
    echo "ok R7-I4 (unreadable backup) guard-viability: pinned pre-R7-fix copy CRASHED"
    echo "   uncaught with a real PermissionError -- proving this fixture genuinely"
    echo "   catches the R7-I4 regression if the fix is ever reverted"
  else
    echo "NOT ok R7-I4 (unreadable backup) guard-viability BLIND: $(cat "$TMP/r74_unreadable.pin.err" 2>/dev/null)"
    failx
  fi
else
  echo "SKIP R7-I4 (unreadable backup): running as a user for whom chmod 000 does not deny"
  echo "   read (likely root) -- this sub-case's own precondition does not hold on this"
  echo "   host, honestly skipped rather than fabricated (section 11.4.3)"
fi
chmod 644 "$R74_ROOT/unreadable_backup.patch"

echo "--- entry_id is a JSON int ---"
# entry_kind MUST be "stash" here, deliberately -- NOT "worktree":
# resolve_live_dirty_state's WORKTREE branch only ever compares entry_id
# against OTHER worktrees' own string entry_ids via a plain `!=` (which
# never raises on a str-vs-int comparison, it is simply always True), so a
# non-string entry_id there degrades harmlessly to a "not found" REFUSED
# with NO crash, never exercising the real R7-I4 defect. The STASH branch
# is the one that feeds `entry_id` DIRECTLY into a real
# `subprocess.run(["git", ..., entry_id], ...)` argv element -- verified
# live at authoring time: the pinned pre-R7-fix copy crashes uncaught here
# with entry_kind=stash, and does NOT crash (silently REFUSES) with
# entry_kind=worktree for the identical entry_id value.
cat > "$TMP/r74_int_entry_id.json" <<EOF
{"entry_kind": "stash", "entry_id": 1, "action": "retire",
 "backup_hash": "$R74_HASH", "backup_artifact_path": "real_backup.patch"}
EOF
FIXED_OUT="$TMP/r74_int_entry_id.out.json"
python3 "$IMPL" verify-proposal --proposal "$TMP/r74_int_entry_id.json" --repo-root "$R74_ROOT" --out "$FIXED_OUT" \
    >"$TMP/r74_int_entry_id.err" 2>&1
if [ -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/r74_int_entry_id.err"; then
  echo "ok R7-I4 (int entry_id) real (fixed) tool: writes a real --out verdict (never crashes)"
  echo "   -- $(cat "$FIXED_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("verdict"), d.get("verdict_detail"))' 2>/dev/null)"
else
  echo "NOT ok R7-I4 (int entry_id) real (fixed) tool: out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r74_int_entry_id.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/r74_int_entry_id.pin.json"
run_against_pinned verify-proposal --proposal "$TMP/r74_int_entry_id.json" --repo-root "$R74_ROOT" --out "$PIN_OUT" \
    >"$TMP/r74_int_entry_id.pin.err" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R7-I4 (int entry_id) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
  failx
elif grep -q "^Traceback" "$TMP/r74_int_entry_id.pin.err" 2>/dev/null && grep -qi "TypeError" "$TMP/r74_int_entry_id.pin.err" 2>/dev/null; then
  echo "ok R7-I4 (int entry_id) guard-viability: pinned pre-R7-fix copy CRASHED uncaught"
  echo "   with a real TypeError from subprocess.run -- proving this fixture genuinely"
  echo "   catches the R7-I4 regression if the fix is ever reverted"
else
  echo "NOT ok R7-I4 (int entry_id) guard-viability BLIND: $(cat "$TMP/r74_int_entry_id.pin.err" 2>/dev/null)"
  failx
fi

echo "--- entry_id contains an embedded NUL byte ---"
# Same entry_kind="stash" reasoning as the int-entry_id case immediately
# above.
python3 -c "
import json
d = {'entry_kind': 'stash', 'entry_id': 'bad\x00id', 'action': 'retire',
     'backup_hash': '$R74_HASH', 'backup_artifact_path': 'real_backup.patch'}
with open('$TMP/r74_nul_entry_id.json', 'w') as fh:
    json.dump(d, fh)
"
FIXED_OUT="$TMP/r74_nul_entry_id.out.json"
python3 "$IMPL" verify-proposal --proposal "$TMP/r74_nul_entry_id.json" --repo-root "$R74_ROOT" --out "$FIXED_OUT" \
    >"$TMP/r74_nul_entry_id.err" 2>&1
if [ -f "$FIXED_OUT" ] && ! grep -q "^Traceback" "$TMP/r74_nul_entry_id.err"; then
  echo "ok R7-I4 (NUL entry_id) real (fixed) tool: writes a real --out verdict (never crashes)"
  echo "   -- $(cat "$FIXED_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("verdict"), d.get("verdict_detail"))' 2>/dev/null)"
else
  echo "NOT ok R7-I4 (NUL entry_id) real (fixed) tool: out_exists=$([ -f "$FIXED_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/r74_nul_entry_id.err" 2>/dev/null)"
  failx
fi
PIN_OUT="$TMP/r74_nul_entry_id.pin.json"
run_against_pinned verify-proposal --proposal "$TMP/r74_nul_entry_id.json" --repo-root "$R74_ROOT" --out "$PIN_OUT" \
    >"$TMP/r74_nul_entry_id.pin.err" 2>&1
if [ -f "$PIN_OUT" ]; then
  echo "NOT ok R7-I4 (NUL entry_id) guard-viability FAILED: pinned pre-R7-fix copy WROTE an --out"
  failx
elif grep -q "^Traceback" "$TMP/r74_nul_entry_id.pin.err" 2>/dev/null && grep -qi "ValueError" "$TMP/r74_nul_entry_id.pin.err" 2>/dev/null; then
  echo "ok R7-I4 (NUL entry_id) guard-viability: pinned pre-R7-fix copy CRASHED uncaught"
  echo "   with a real ValueError (embedded null byte) -- proving this fixture genuinely"
  echo "   catches the R7-I4 regression if the fix is ever reverted"
else
  echo "NOT ok R7-I4 (NUL entry_id) guard-viability BLIND: $(cat "$TMP/r74_nul_entry_id.pin.err" 2>/dev/null)"
  failx
fi

echo
echo "=== R7-I6: selftest's golden-good case is fully self-contained ==="
FIXED_SELFTEST_OUT="$TMP/r76_selftest.out"
python3 "$IMPL" selftest --repo-root "$ROOT/constitution" >"$FIXED_SELFTEST_OUT" 2>&1
FIXED_SELFTEST_RC=$?
if [ "$FIXED_SELFTEST_RC" = "0" ] && grep -q "ok proposal_golden_good_verified_hash.json -> ALLOWED" "$FIXED_SELFTEST_OUT"; then
  echo "ok R7-I6 real (fixed) tool: selftest rc=0, golden-good fixture resolves ALLOWED"
  echo "   via a self-contained scratch repo -- never depends on a17eb3df7db2f148a"
  echo "   (or any other specific real worktree) existing in this repo"
else
  echo "NOT ok R7-I6 real (fixed) tool: selftest rc=$FIXED_SELFTEST_RC, output:"
  sed 's/^/     /' "$FIXED_SELFTEST_OUT"
  failx
fi
# Guard-viability: the PINNED pre-R7-fix copy's own selftest, run against
# THIS repo's CURRENT (post-cleanup) real worktree state, still reads the
# checked-in fixture's own entry_id and therefore still reproduces the
# R7-I6 defect (a17eb3df7db2f148a genuinely no longer resolves) -- proving
# this is a genuine before/after divergence, not a coincidence of this
# particular host's state at authoring time.
PIN_SELFTEST_OUT="$TMP/r76_selftest.pin.out"
run_against_pinned selftest --repo-root "$ROOT/constitution" --fixtures-dir "$FIXDIR" >"$PIN_SELFTEST_OUT" 2>&1
PIN_SELFTEST_RC=$?
if [ "$PIN_SELFTEST_RC" != "0" ] && grep -q "NOT ok proposal_golden_good_verified_hash.json -> REFUSED, expected ALLOWED" "$PIN_SELFTEST_OUT"; then
  echo "ok R7-I6 guard-viability: pinned pre-R7-fix copy's selftest genuinely FAILS"
  echo "   the golden-good case (rc=$PIN_SELFTEST_RC) on THIS repo's current, real"
  echo "   worktree state -- proving this fixture genuinely catches the R7-I6"
  echo "   regression if the self-contained scratch-repo fix is ever reverted"
else
  echo "NOT ok R7-I6 guard-viability BLIND: pinned copy's selftest rc=$PIN_SELFTEST_RC"
  echo "     (expected a golden-good REFUSED failure on this host's current state):"
  sed 's/^/     /' "$PIN_SELFTEST_OUT"
  failx
fi

echo
echo "=== Top-level dispatch boundary: main() wraps EVERY subcommand in ONE except Exception boundary ==="
# T140 Round 8 review finding R8-I1 (fixed here): the boundary's own catch
# set was WIDENED from `fc_common.SAFE_EXCEPTIONS` to bare `Exception` (see
# custody_sweep.py's own main() comment) -- this static control needle
# (mirrors R6-I2-sibling's own static needle pattern) is updated to match
# the new reality: it now looks for a bare `except Exception as exc:`
# handler (an `ast.Name` node whose `id == "Exception"`, NOT an
# `ast.Attribute` node -- `fc_common.SAFE_EXCEPTIONS` parses as an
# Attribute, `Exception` parses as a bare Name) that still calls the
# minimal-error-doc writer, and ADDITIONALLY confirms `Exception` is never
# accidentally widened all the way to `BaseException` (which would wrongly
# swallow `SystemExit`/`KeyboardInterrupt` too -- section 11.4.6, never
# silently over-widen a fix beyond what was asked). The `except
# RuntimeError as exc:` handler listed BEFORE this boundary (its own,
# MORE SPECIFIC clause, unaffected by this widening -- Python tries
# handlers in source order) is deliberately not asserted on here; this
# check is scoped to the boundary this round's own review named.
BOUNDARY_CHECK=$(python3 - "$IMPL" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read(), filename=sys.argv[1])
found_main_boundary = False
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
                    # matches `except Exception as exc:`
                    if isinstance(h.type, ast.Name) and h.type.id == "Exception":
                        calls_writer = any(
                            isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                            and "internal_error" in n.func.id
                            for n in ast.walk(h)
                        )
                        if calls_writer:
                            found_main_boundary = True
if found_base_exception:
    print("BASEEXCEPTION")
else:
    print("1" if found_main_boundary else "0")
PYEOF
)
if [ "$BOUNDARY_CHECK" = "1" ]; then
  echo "ok top-level dispatch boundary: main() wraps its subcommand dispatch in"
  echo "   except Exception and calls the minimal-error-doc writer (never"
  echo "   BaseException -- SystemExit/KeyboardInterrupt correctly stay uncaught)"
elif [ "$BOUNDARY_CHECK" = "BASEEXCEPTION" ]; then
  echo "NOT ok top-level dispatch boundary OVER-WIDENED to BaseException -- this would"
  echo "     wrongly swallow SystemExit/KeyboardInterrupt too"
  failx
else
  echo "NOT ok top-level dispatch boundary MISSING or malformed"
  failx
fi
# Live proof: dispatch a subcommand whose handler is forced (via a small
# monkeypatch on a private copy) to raise a SAFE_EXCEPTIONS member AFTER
# its own internal try/excepts would have already handled every KNOWN
# case -- proving the boundary genuinely catches something none of the
# individual per-site fixes above would have.
LIVE_BOUNDARY_ROOT="$TMP/live_boundary"
mkdir -p "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/orchestration" "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/lib"
cp "$IMPL" "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/orchestration/custody_sweep.py"
cp "$LIB" "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/lib/fc_common.py"
cp "$EXLIB" "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
python3 - "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/orchestration/custody_sweep.py" <<'PYEOF'
import sys
p = sys.argv[1]
old = "def cmd_inventory(a):\n    root = resolve_repo_root(a.repo_root)\n"
new = ("def cmd_inventory(a):\n"
       "    raise TypeError('MUTATION_LIVE_BOUNDARY_PROOF: forced unanticipated crash')\n"
       "    root = resolve_repo_root(a.repo_root)\n")
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
  python3 "$LIVE_BOUNDARY_ROOT/scripts/fastcycle/orchestration/custody_sweep.py" inventory --repo-root "$ROOT/constitution" --out "$LIVE_OUT" \
      >"$TMP/live_boundary.err" 2>&1
  LIVE_RC=$?
  if [ "$LIVE_RC" = "2" ] && [ -f "$LIVE_OUT" ] && ! grep -q "^Traceback" "$TMP/live_boundary.err" \
      && grep -q "MUTATION_LIVE_BOUNDARY_PROOF" "$TMP/live_boundary.err" \
      && python3 -c "import json,sys; d=json.load(open('$LIVE_OUT')); sys.exit(0 if d.get('internal_error',{}).get('detail','').find('MUTATION_LIVE_BOUNDARY_PROOF')>=0 else 1)"; then
    echo "ok top-level dispatch boundary LIVE PROOF: a forced, genuinely unanticipated"
    echo "   TypeError raised at the very TOP of cmd_inventory (before ANY of its own"
    echo "   internal try/excepts could ever run) is caught by main()'s own boundary --"
    echo "   rc=2 (never Python's uncaught-exception default of 1), NO traceback on"
    echo "   stderr, and a real --out document naming the real exception was written"
    echo "   -- this is NOT something any of R7-I3/I4/I6's own individual, targeted"
    echo "   fixes above would have caught by themselves"
  else
    echo "NOT ok top-level dispatch boundary LIVE PROOF FAILED: rc=$LIVE_RC out_exists=$([ -f "$LIVE_OUT" ] && echo yes || echo no) stderr=$(cat "$TMP/live_boundary.err" 2>/dev/null)"
    failx
  fi
fi

echo
echo "=== Malformed-input fuzz probe: no traceback ever, rc always in {0,1,2,3,4}, rc=1 only with an --out file written ==="
FUZZ_INVENTORY_DOCS=(
  'null'
  'true'
  '42'
  '3.5'
  '"just a string"'
  '[]'
  '{}'
  '{"entries": null}'
  '{"entries": 42}'
  '{"entries": [null, true, 42, 3.5, "x", [], {}]}'
  '{"entries": [{"existing_backup": null}]}'
  '{"entries": [{"existing_backup": 42}]}'
  '{"entries": [{"entry_kind": null, "existing_backup": {"backup_hash": "x", "backup_artifact_path": "y"}}]}'
  '{"entries": [{"entry_kind": 42, "existing_backup": {"backup_hash": "x", "backup_artifact_path": "y"}}]}'
)
FUZZ_FAIL=0
i=0
for doc in "${FUZZ_INVENTORY_DOCS[@]}"; do
  i=$((i + 1))
  f="$TMP/fuzz_inv_$i.json"
  printf '%s' "$doc" > "$f"
  out="$TMP/fuzz_inv_$i.out.json"
  python3 "$IMPL" propose --inventory "$f" --out "$out" >"$TMP/fuzz_inv_$i.err" 2>&1
  rc=$?
  if grep -q "^Traceback" "$TMP/fuzz_inv_$i.err"; then
    echo "NOT ok fuzz propose --inventory case $i ($doc): TRACEBACK on stderr: $(cat "$TMP/fuzz_inv_$i.err")"
    FUZZ_FAIL=1
    continue
  fi
  case "$rc" in
    0|1|2|3|4) : ;;
    *) echo "NOT ok fuzz propose --inventory case $i ($doc): rc=$rc outside {0,1,2,3,4}"; FUZZ_FAIL=1; continue ;;
  esac
  if [ "$rc" = "1" ] && [ ! -f "$out" ]; then
    echo "NOT ok fuzz propose --inventory case $i ($doc): rc=1 (a finding) but NO --out was written"
    FUZZ_FAIL=1
    continue
  fi
done
FUZZ_PROPOSAL_DOCS=(
  'null'
  '[]'
  '{"action": null}'
  '{"action": 42, "entry_kind": "worktree", "entry_id": "x"}'
  '{"action": "retire", "entry_kind": "worktree", "entry_id": "x", "backup_hash": 42, "backup_artifact_path": "y"}'
  '{"action": "retire", "entry_kind": "worktree", "entry_id": "x", "backup_hash": "z", "backup_artifact_path": [1,2]}'
)
j=0
for doc in "${FUZZ_PROPOSAL_DOCS[@]}"; do
  j=$((j + 1))
  f="$TMP/fuzz_prop_$j.json"
  printf '%s' "$doc" > "$f"
  out="$TMP/fuzz_prop_$j.out.json"
  python3 "$IMPL" verify-proposal --proposal "$f" --repo-root "$ROOT/constitution" --out "$out" \
      >"$TMP/fuzz_prop_$j.err" 2>&1
  rc=$?
  if grep -q "^Traceback" "$TMP/fuzz_prop_$j.err"; then
    echo "NOT ok fuzz verify-proposal case $j ($doc): TRACEBACK on stderr: $(cat "$TMP/fuzz_prop_$j.err")"
    FUZZ_FAIL=1
    continue
  fi
  case "$rc" in
    0|1|2|3|4) : ;;
    *) echo "NOT ok fuzz verify-proposal case $j ($doc): rc=$rc outside {0,1,2,3,4}"; FUZZ_FAIL=1; continue ;;
  esac
  if [ "$rc" = "1" ] && [ ! -f "$out" ]; then
    echo "NOT ok fuzz verify-proposal case $j ($doc): rc=1 (a finding) but NO --out was written"
    FUZZ_FAIL=1
    continue
  fi
done
if [ "$FUZZ_FAIL" = "0" ]; then
  echo "ok malformed-input fuzz probe: $((i + j)) adversarial propose/verify-proposal"
  echo "   documents -- zero tracebacks, every rc in {0,1,2,3,4}, every rc=1 paired"
  echo "   with a genuinely-written --out document"
else
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R7 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- R7-I3's full"
  echo "    propose malformed-input validation, R7-I4's derive_verdict"
  echo "    unreadable-backup/int-entry_id/NUL-entry_id fail-closed fixes,"
  echo "    R7-I6's self-contained selftest golden-good scratch repo, and the"
  echo "    ONE top-level main() dispatch boundary are all load-bearing:"
  echo "    reverting any one of them makes its own matching pinned pre-fix"
  echo "    copy either crash uncaught or silently misbehave, and the"
  echo "    malformed-input fuzz probe found zero tracebacks/bad-rc/silent-loss"
  echo "    cases across every adversarial document tried. ==="
  exit 0
else
  echo "=== R7 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
