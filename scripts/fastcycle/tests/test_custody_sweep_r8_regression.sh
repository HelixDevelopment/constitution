#!/bin/bash
# Purpose : T140 Round 8 review regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`.
#
# Findings covered, each with a real-tool check on the FIXED tool AND a
# guard-viability check constructed LIVE (a mutated copy that reverts
# JUST the relevant fix back to its pre-R8 shape -- never a checked-in
# pinned pre-R8-fix file, mirroring test_handoff_r8_regression.sh's own
# documented rationale for the same choice):
#
#   R8-I1 -- `main()`'s top-level dispatch boundary previously caught
#     only `fc_common.SAFE_EXCEPTIONS` -- Round 8's own live fuzzer proved
#     `KeyError`/`IndexError`/`AttributeError` still escaped UNCAUGHT
#     (proven live, TWICE independently: (1) reverting THIS round's own
#     `propose_action_for` point-fix (`entry.get(...)` back to
#     `entry["entry_kind"]`) makes `propose` crash with an uncaught
#     `KeyError`; (2) injecting a `KeyError`/`IndexError`/`AttributeError`
#     at the very TOP of `cmd_verify_proposal` crashes uncaught too).
#     Fixed by widening the boundary to bare `Exception` (never
#     `BaseException`).
#   R8-I1(c) -- the `except RuntimeError as exc:` branch (listed BEFORE
#     the widened boundary, its own more-specific clause) used to write
#     NO --out document at all -- fixed to call the SAME minimal-
#     error-doc writer the widened boundary uses.
#   R8-I1(d) -- `_write_dispatch_internal_error_doc`'s own best-effort
#     write was `except OSError` alone -- widened to `Exception`.
#   R8-I2 -- `_selftest_golden_good_scratch_check`'s own scratch-repo git
#     calls silently inherited the CALLING process's own environment
#     (e.g. `GIT_DIR`/`GIT_WORK_TREE` set by a real git hook this tool is
#     invoked from), so `git -C <scratch>` operations were silently
#     redirected onto an unrelated, real host repository instead --
#     mutating ITS `.git/config` and making the selftest wrongly FAIL its
#     own golden-good case. Fixed by threading a fully-sanitized,
#     `_sanitized_scratch_env()`-built environment through EVERY git call
#     this scratch check makes, including `derive_verdict`'s own internal
#     `resolve_live_dirty_state` re-derivation (never just the scratch
#     check's own direct `_run(...)` calls -- a partially-sanitized fix
#     would still leave that internal call chain contaminated).
#
# House style: mirrors test_handoff_r8_regression.sh's own live-mutation
# guard-viability pattern.
#
# Producer != Verifier (section 11.4.240): this file's own assertions were
# derived directly from the Round 8 review's findings text and this
# session's own live reproduction of each one (never imported from, nor
# shared with, custody_sweep.py's own implementation).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC_CANON_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)  # CON-097: canon resolved from this test's own location (three levels up), never as <consumer root>/constitution
FC="$FC_CANON_ROOT/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
CS_FIXDIR="$FC/tests/fixtures/custody_sweep"

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

# ---------------------------------------------------------------------------
# R8-I1 repro (1): reverting this round's OWN point-fix in
# propose_action_for -- entry.get(...) back to entry[...] -- makes propose
# crash with an uncaught KeyError on the OLD, narrower boundary; on a
# SEPARATE copy that keeps the widened `except Exception` boundary but
# ALSO reverts the point-fix, the boundary alone catches it (defense in
# depth: the specific fix AND the general boundary each independently
# close this gap).
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1 repro (1): reverting propose_action_for's entry.get(...) point-fix ==="
cat > "$TMP/inv_missing_kind.json" <<'EOF'
{"entries": [{"existing_backup": {"backup_hash": "abc", "backup_artifact_path": "x.patch"}}]}
EOF
mkdir -p "$TMP/reporoot" && git init --quiet "$TMP/reporoot"

revert_entry_get_point_fix() {
  # $1 = orchestration/custody_sweep.py path
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = '        entry_kind=entry.get("entry_kind"), entry_id=entry.get("entry_id"),\n    )\n    if verdict != "ALLOWED":'
new = '        entry_kind=entry["entry_kind"], entry_id=entry["entry_id"],\n    )\n    if verdict != "ALLOWED":'
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

# (a) point-fix reverted, boundary WIDENED (this round's own state):
#     the widened boundary alone catches it -- defense in depth.
D1="$TMP/r1_boundary_still_widened"
mkdir -p "$D1/orchestration" "$D1/lib"
cp "$IMPL" "$D1/orchestration/custody_sweep.py"
cp "$LIB" "$D1/lib/fc_common.py"
cp "$EXLIB" "$D1/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
revert_entry_get_point_fix "$D1/orchestration/custody_sweep.py"
if [ $? -ne 0 ]; then
  echo "NOT ok R8-I1 repro (1a) mutation anchor not found (content drifted)"
  failx
else
  OUT="$TMP/r1a.out.json"
  ERR="$TMP/r1a.err"
  python3 "$D1/orchestration/custody_sweep.py" propose --inventory "$TMP/inv_missing_kind.json" \
      --repo-root "$TMP/reporoot" --out "$OUT" >"$ERR" 2>&1
  RC=$?
  if [ "$RC" = "2" ] && [ -f "$OUT" ] && ! grep -q "^Traceback" "$ERR" \
      && grep -q "KeyError" "$ERR" \
      && python3 -c "import json,sys; d=json.load(open('$OUT')); sys.exit(0 if d.get('internal_error',{}).get('class')=='KeyError' else 1)"; then
    echo "ok R8-I1 repro (1a): point-fix reverted, widened boundary alone catches the"
    echo "   resulting KeyError -- rc=2, no traceback, --out names KeyError (defense"
    echo "   in depth: the general boundary closes this even without the specific fix)"
  else
    echo "NOT ok R8-I1 repro (1a) FAILED: rc=$RC out_exists=$([ -f "$OUT" ] && echo yes || echo no) stderr=$(cat "$ERR" 2>/dev/null)"
    failx
  fi
fi

# (b) point-fix reverted AND boundary reverted to the R7 (SAFE_EXCEPTIONS)
#     shape: this is the reviewer's OWN exact repro -- an uncaught crash,
#     no --out.
revert_boundary_to_r7_shape() {
  python3 - "$1" <<'PYEOF'
import sys
p = sys.argv[1]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
old = "    except Exception as exc:\n        # T140 Round 7 review, the ONE top-level dispatch boundary"
new = "    except fc_common.SAFE_EXCEPTIONS as exc:\n        # T140 Round 7 review, the ONE top-level dispatch boundary"
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}
D2="$TMP/r1_both_reverted"
mkdir -p "$D2/orchestration" "$D2/lib"
cp "$IMPL" "$D2/orchestration/custody_sweep.py"
cp "$LIB" "$D2/lib/fc_common.py"
cp "$EXLIB" "$D2/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
revert_entry_get_point_fix "$D2/orchestration/custody_sweep.py"
RC1=$?
revert_boundary_to_r7_shape "$D2/orchestration/custody_sweep.py"
RC2=$?
if [ "$RC1" -ne 0 ] || [ "$RC2" -ne 0 ]; then
  echo "NOT ok R8-I1 repro (1b) mutation anchor not found (content drifted)"
  failx
else
  OUT2="$TMP/r1b.out.json"
  ERR2="$TMP/r1b.err"
  rm -f "$OUT2"
  python3 "$D2/orchestration/custody_sweep.py" propose --inventory "$TMP/inv_missing_kind.json" \
      --repo-root "$TMP/reporoot" --out "$OUT2" >"$ERR2" 2>&1
  # T140 Round 10 review, "Recommended root-cause work" item 1: `run_cli_main`
  # now wraps main() in its OWN, OUTER `except Exception` safety net -- see
  # test_handoff_r8_regression.sh's own identically-purposed sibling fix for
  # the full rationale -- so this no longer produces a raw, uncaught
  # Traceback; the still-load-bearing signal is no rich --out doc + the
  # OUTER fallback message.
  if [ ! -f "$OUT2" ] && ! grep -q "^Traceback" "$ERR2" \
      && grep -q "escaped the top-level dispatch entirely" "$ERR2" \
      && grep -q "'entry_kind'" "$ERR2"; then
    echo "ok R8-I1 repro (1b) guard-viability: reverting BOTH the point-fix AND the"
    echo "   boundary reproduces the reviewer's own exact finding -- KeyError escapes"
    echo "   main()'s own boundary entirely, caught only by run_cli_main's OUTER,"
    echo "   tool-agnostic fallback (no rich --out internal-error document written)"
  else
    echo "NOT ok R8-I1 repro (1b) guard-viability BLIND: out_exists=$([ -f "$OUT2" ] && echo yes || echo no) stderr=$(cat "$ERR2" 2>/dev/null)"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# R8-I1 repro (2): {KeyError, IndexError, AttributeError} injected at the
# very TOP of cmd_verify_proposal.
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1 repro (2): {KeyError, IndexError, AttributeError} injected at the top of cmd_verify_proposal ==="
mkdir -p "$TMP/prop_reporoot" && git init --quiet "$TMP/prop_reporoot"
cat > "$TMP/prop.json" <<'EOF'
{"action": "retire", "entry_kind": "worktree", "entry_id": "x", "backup_hash": "z", "backup_artifact_path": "y"}
EOF

inject_and_build() {
  local dir="$1" exc="$2"
  mkdir -p "$dir/orchestration" "$dir/lib"
  cp "$IMPL" "$dir/orchestration/custody_sweep.py"
  cp "$LIB" "$dir/lib/fc_common.py"
  cp "$EXLIB" "$dir/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
  python3 - "$dir/orchestration/custody_sweep.py" "$exc" <<'PYEOF'
import sys
p, exc = sys.argv[1], sys.argv[2]
old = "def cmd_verify_proposal(a):\n"
new = "def cmd_verify_proposal(a):\n    raise %s('R8_TOPINJ_PROOF')\n" % exc
with open(p, encoding="utf-8") as fh:
    c = fh.read()
if c.count(old) != 1:
    sys.exit(1)
c = c.replace(old, new, 1)
with open(p, "w", encoding="utf-8") as fh:
    fh.write(c)
PYEOF
}

for exc in KeyError IndexError AttributeError; do
  D="$TMP/inj_$exc"
  inject_and_build "$D" "$exc"
  if [ $? -ne 0 ]; then
    echo "NOT ok R8-I1 repro (2, $exc) mutation anchor not found (content drifted)"
    failx
    continue
  fi
  OUT="$TMP/inj_${exc}.out.json"
  ERR="$TMP/inj_${exc}.err"
  python3 "$D/orchestration/custody_sweep.py" verify-proposal --proposal "$TMP/prop.json" \
      --repo-root "$TMP/prop_reporoot" --out "$OUT" >"$ERR" 2>&1
  RC=$?
  if [ "$RC" = "2" ] && [ -f "$OUT" ] && ! grep -q "^Traceback" "$ERR" \
      && grep -q "R8_TOPINJ_PROOF" "$ERR" \
      && python3 -c "import json,sys; d=json.load(open('$OUT')); sys.exit(0 if d.get('internal_error',{}).get('class')=='$exc' else 1)"; then
    echo "ok R8-I1 repro (2, $exc) real (fixed) tool: rc=2, no traceback, --out names $exc"
  else
    echo "NOT ok R8-I1 repro (2, $exc) real (fixed) tool FAILED: rc=$RC out_exists=$([ -f "$OUT" ] && echo yes || echo no) stderr=$(cat "$ERR" 2>/dev/null)"
    failx
    continue
  fi

  revert_boundary_to_r7_shape "$D/orchestration/custody_sweep.py"
  if [ $? -ne 0 ]; then
    echo "NOT ok R8-I1 repro (2, $exc) guard-viability: boundary-revert mutation anchor not found"
    failx
    continue
  fi
  OUT2="$TMP/inj_${exc}.r7shape.out.json"
  ERR2="$TMP/inj_${exc}.r7shape.err"
  rm -f "$OUT2"
  python3 "$D/orchestration/custody_sweep.py" verify-proposal --proposal "$TMP/prop.json" \
      --repo-root "$TMP/prop_reporoot" --out "$OUT2" >"$ERR2" 2>&1
  # T140 Round 10 review, "Recommended root-cause work" item 1: see
  # test_handoff_r8_regression.sh's own identically-purposed sibling fix
  # for the full rationale (run_cli_main's OUTER catch now handles this
  # too, so no raw Traceback -- the load-bearing signal is no rich --out
  # doc + the OUTER fallback message).
  if [ ! -f "$OUT2" ] && ! grep -q "^Traceback" "$ERR2" \
      && grep -q "escaped the top-level dispatch entirely" "$ERR2" \
      && grep -Eq "(R8_TOPINJ_PROOF|'R8_TOPINJ_PROOF')" "$ERR2"; then
    echo "ok R8-I1 repro (2, $exc) guard-viability: reverting JUST the boundary's own"
    echo "   catch set back to fc_common.SAFE_EXCEPTIONS makes the SAME injected $exc"
    echo "   escape main()'s own boundary entirely (no rich --out doc; only run_cli_main's"
    echo "   OUTER fallback fires) -- proving the Exception widening genuinely does the work"
  else
    echo "NOT ok R8-I1 repro (2, $exc) guard-viability BLIND: out_exists=$([ -f "$OUT2" ] && echo yes || echo no) stderr=$(cat "$ERR2" 2>/dev/null)"
    failx
  fi
done

# ---------------------------------------------------------------------------
# R8-I1(c): the RuntimeError branch now ALSO writes an --out doc.
# ---------------------------------------------------------------------------
echo
echo "=== R8-I1(c): the RuntimeError branch (--repo-root not a git checkout) now writes --out too ==="
OUT_RTE="$TMP/rte.out.json"
ERR_RTE="$TMP/rte.err"
python3 "$IMPL" inventory --repo-root "$TMP/definitely_not_a_git_checkout_xyz" --out "$OUT_RTE" >"$ERR_RTE" 2>&1
RC_RTE=$?
if [ "$RC_RTE" = "2" ] && [ -f "$OUT_RTE" ] \
    && python3 -c "import json,sys; d=json.load(open('$OUT_RTE')); sys.exit(0 if d.get('internal_error',{}).get('class')=='RuntimeError' else 1)"; then
  echo "ok R8-I1(c): a RuntimeError (not-a-git-checkout refusal) now writes a real --out"
  echo "   document naming RuntimeError, matching every other dispatch-boundary path"
  echo "   in this file -- the audit trail is no longer silently lost for this ONE"
  echo "   exception class"
else
  echo "NOT ok R8-I1(c) FAILED: rc=$RC_RTE out_exists=$([ -f "$OUT_RTE" ] && echo yes || echo no) stderr=$(cat "$ERR_RTE" 2>/dev/null)"
  failx
fi

# ---------------------------------------------------------------------------
# R8-I2: selftest under a victim GIT_DIR/GIT_WORK_TREE -- the victim's OWN
# .git/config MUST be byte-unchanged before vs after, and selftest itself
# MUST correctly pass its own golden-good case (rc=0).
# ---------------------------------------------------------------------------
echo
echo "=== R8-I2: selftest's scratch-repo git calls are fully isolated from an inherited GIT_DIR/GIT_WORK_TREE ==="
mkdir -p "$TMP/victim"
(
  cd "$TMP/victim"
  git init --quiet .
  git config user.email "victim@example.invalid"
  git config user.name "victim"
  echo "hello" > f.txt
  git add f.txt
  git commit --quiet -m "initial"
)
BEFORE_MD5=$(md5sum "$TMP/victim/.git/config" | awk '{print $1}')
mkdir -p "$TMP/goodroot" && git init --quiet "$TMP/goodroot"

SELFTEST_OUT="$TMP/gitdir_selftest.out"
(
  export GIT_DIR="$TMP/victim/.git"
  export GIT_WORK_TREE="$TMP/victim"
  python3 "$IMPL" selftest --repo-root "$TMP/goodroot" --fixtures-dir "$CS_FIXDIR"
) >"$SELFTEST_OUT" 2>&1
SELFTEST_RC=$?
AFTER_MD5=$(md5sum "$TMP/victim/.git/config" | awk '{print $1}')

if [ "$SELFTEST_RC" = "0" ] && [ "$BEFORE_MD5" = "$AFTER_MD5" ] \
    && grep -q "ok proposal_golden_good_verified_hash.json -> ALLOWED" "$SELFTEST_OUT"; then
  echo "ok R8-I2 real (fixed) tool: selftest rc=0 under an inherited victim"
  echo "   GIT_DIR/GIT_WORK_TREE, golden-good case correctly resolves ALLOWED, and the"
  echo "   victim's own .git/config is BYTE-UNCHANGED (md5 $BEFORE_MD5 before and after)"
else
  echo "NOT ok R8-I2 real (fixed) tool FAILED: rc=$SELFTEST_RC before_md5=$BEFORE_MD5"
  echo "   after_md5=$AFTER_MD5"
  sed 's/^/     /' "$SELFTEST_OUT"
  failx
fi

# Guard-viability: on a SEPARATE copy, revert JUST the scratch-env
# threading in _selftest_golden_good_scratch_check back to unsanitized
# `_run(...)` calls (no `env=` kwarg at all, the pre-R8 shape) -- the SAME
# victim-GIT_DIR scenario must now mutate the victim's .git/config again.
#
# CON-402 (audit F3, 2026-11-16): CON-402 added a THIRD, file-level layer -- the canonical git-env scrub at the top of
# custody_sweep.py and of lib/fc_common.py (which it imports) clears GIT_DIR / GIT_WORK_TREE before any code runs.
# Measured on cc51c320 (3/3): with only the in-function layers reverted the victim stays untouched, so this guard
# went BLIND. The faithful pre-R8 revert ($D3) therefore also removes that layer from every copied file; a second
# copy ($D4) reverts ONLY the in-function layers and must keep the victim untouched -- the proof that the file-level
# scrub alone is load-bearing for this scenario. D4 fails if the scrub is removed from BOTH files; one file's scrub
# alone already clears the environment (fc_common.py is imported at start), so the per-file checks D5 / D6 below
# prove that EACH file's scrub alone suffices (CON-451 round 2, review F23-B).
#
# CON-451 round 2 (review F23-A): every measurement below runs on its OWN fresh victim repository (r8i2_run). The
# vector's write is idempotent (git config of the same keys and values), so a second run on a victim that an earlier
# run already wrote shows "no change" whether or not the layer under test is present: the D4 check could not fail.
# The control D4-POL feeds the D4 decision the both-layers-removed mutant and requires "wrote" (the tm1 shape).
#
# r8i2_mutant DIR MODE -- MODE: full (in-function layers reverted, scrub stripped from both files), func (in-function
# layers reverted, scrub kept), func+tool (in-function reverted, scrub stripped from custody_sweep.py only),
# func+lib (same, lib/fc_common.py only), scrub (in-function layers KEPT, scrub stripped from both files)
r8i2_mutant() {
  mkdir -p "$1/orchestration" "$1/lib"
  cp "$IMPL" "$1/orchestration/custody_sweep.py"
  cp "$LIB" "$1/lib/fc_common.py"
  cp "$EXLIB" "$1/lib/fc_entry.py"  # T140 Round 10: fc_entry.py is now a required sibling import
python3 - "$1/orchestration/custody_sweep.py" "$2" "$1/lib/fc_common.py" <<'PYEOF'
import re, sys
p = sys.argv[1]
mode = sys.argv[2]
revert_func = mode in ("full", "func", "func+tool", "func+lib")
strip_files = {"full": (p, sys.argv[3]), "func": (), "func+tool": (p,), "func+lib": (sys.argv[3],),
               "scrub": (p, sys.argv[3])}[mode]
with open(p, encoding="utf-8") as fh:
    c = fh.read()
# Strip every `, env=scratch_env` / `env=scratch_env` kwarg this fix added
# to _run/worktree_dirty_state/derive_verdict calls INSIDE
# _selftest_golden_good_scratch_check ONLY (scoped by the function's own
# unique anchor text -- never touching env= kwargs elsewhere in the file
# that legitimately belong to OTHER, unrelated call sites).
start = c.index("def _selftest_golden_good_scratch_check")
end = c.index("\ndef cmd_selftest(a):")
before, body, after = c[:start], c[start:end], c[end:]
mutated_body = re.sub(r",?\s*env=scratch_env", "", body)
mutated_body = mutated_body.replace("scratch_env = _sanitized_scratch_env()\n    ", "")
if mutated_body == body:
    sys.exit(1)
# T140 Round 15 (round-14 IMPORTANT-2): `_run` itself now strips ambient
# git-redirection variables whenever no explicit env is passed -- a SECOND,
# independent isolation layer that alone neutralises this victim scenario
# (defense-in-depth, measured live: with only the scratch_env threading
# reverted the victim stays untouched). Reverting the pre-R8 shape faithfully
# therefore also reverts that layer to plain ambient inheritance; the
# Round-15 layer is proven load-bearing on its own by
# test_custody_sweep_r15_regression.sh (mutation ME1_inherit_ambient_env).
old_inherit = "    child_env = _targeted_git_env() if env is None else env"
if after.count(old_inherit) + before.count(old_inherit) != 1:
    sys.exit(1)
before = before.replace(old_inherit, "    child_env = env")
if revert_func:
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(before + mutated_body + after)
if strip_files:
    # the CON-402 file-level scrub pair (scripts/validation/git_env_class_census.py, python form): exactly one per
    # file, in the tool AND in the library it imports
    pair = re.compile(r'^import os as _ge_os[^\n]*\nfor _ge_v in "[A-Z_ ]+"\.split\(\): _ge_os\.environ\.pop\(_ge_v, None\)\n', re.M)
    for f in strip_files:
        with open(f, encoding="utf-8") as fh:
            t = fh.read()
        t2, n = pair.subn("", t)
        if n != 1:
            sys.exit(1)
        with open(f, "w", encoding="utf-8") as fh:
            fh.write(t2)
PYEOF
}
r8i2_run() {   # r8i2_run MUTANT_DIR TAG -> prints "wrote" or "clean" (a fresh victim per run); "error" on setup fault
  local v="$TMP/victim_$2" b a
  mkdir -p "$v" && (
    cd "$v" || exit 1
    git init --quiet . && git config user.email "victim@example.invalid" && git config user.name "victim" \
      && echo "hello" > f.txt && git add f.txt && git commit --quiet -m "initial"
  ) >/dev/null 2>&1 || { echo error; return; }
  b=$(md5sum "$v/.git/config" | awk '{print $1}')
  (
    export GIT_DIR="$v/.git"
    export GIT_WORK_TREE="$v"
    python3 "$1/orchestration/custody_sweep.py" selftest --repo-root "$TMP/goodroot" --fixtures-dir "$CS_FIXDIR"
  ) >"$TMP/gitdir_selftest_$2.out" 2>&1
  a=$(md5sum "$v/.git/config" | awk '{print $1}')
  if [ "$b" != "$a" ]; then echo wrote; else echo clean; fi
}
r8_layer() {   # r8_layer NAME MODE WANT(wrote|clean) MESSAGE
  local d="$TMP/r8i2_$1" got
  if ! r8i2_mutant "$d" "$2"; then
    echo "NOT ok R8-I2 $1: mutation anchor not found (content drifted)"
    failx
    return
  fi
  got=$(r8i2_run "$d" "$1")
  if [ "$got" = "$3" ]; then
    echo "ok R8-I2 $1: $4 (victim $got)"
  else
    echo "NOT ok R8-I2 $1: expected the victim $3, got $got -- $4"
    echo "     ($(tail -3 "$TMP/gitdir_selftest_$1.out" 2>/dev/null))"
    failx
  fi
}
# D3: the faithful pre-R8 revert (both layers removed) -- the vector is reached (guard-viability)
r8_layer reverted full wrote "guard-viability: reverting the scratch-env isolation AND the CON-402 scrub makes the SAME victim-GIT_DIR scenario mutate the victim's .git/config again -- the sanitized-environment fix genuinely does the work, never a tautological mutation"
# D4: the CON-402 layer alone (in-function layers reverted, the scrub kept in both files)
r8_layer scrub_only func clean "file-level scrub alone (CON-402 layer): with the in-function isolation reverted but the file-level scrub kept, the victim's .git/config stays byte-unchanged"
# D4-POL: the D4 decision fed the both-layers-removed mutant must report the write (the review's tm1 shape)
r8_layer scrub_only_polarity full wrote "D4 polarity control: the same measurement on a fresh victim with both layers removed sees the write (the D4 check can fail)"
# D5 / D6: one file's scrub alone suffices (F23-B)
r8_layer scrub_lib_only func+tool clean "the scrub of lib/fc_common.py alone (custody_sweep.py's scrub stripped, in-function layers reverted) keeps the victim unchanged"
r8_layer scrub_tool_only func+lib clean "the scrub of custody_sweep.py alone (lib/fc_common.py's scrub stripped, in-function layers reverted) keeps the victim unchanged"
# D7: the in-function layers alone (scrub stripped from both files, in-function layers kept; review F23-C)
r8_layer func_only scrub clean "in-function isolation alone (round-8 scratch_env + round-15 _targeted_git_env, the CON-402 scrub stripped from both files) keeps the victim unchanged"

echo
if [ "$fail" = 0 ]; then
  echo "=== R8 REGRESSION GUARD (custody_sweep.py): ALL CHECKS PASS -- the widened"
  echo "    except Exception dispatch boundary catches KeyError/IndexError/"
  echo "    AttributeError (both the reviewer's own point-fix-revert repro AND a"
  echo "    fresh top-of-handler injection, each proven load-bearing via a live"
  echo "    boundary-revert mutation), the RuntimeError branch now writes --out"
  echo "    too, and the selftest scratch-repo git calls are fully isolated from"
  echo "    an inherited GIT_DIR/GIT_WORK_TREE (proven both positively and via a"
  echo "    live env-sanitization-revert mutation). ==="
  exit 0
else
  echo "=== R8 REGRESSION GUARD (custody_sweep.py): FAILURES ABOVE -- see 'NOT ok' lines. ==="
  exit 1
fi
