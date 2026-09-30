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
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
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
  if [ ! -f "$OUT2" ] && grep -q "^Traceback" "$ERR2" && grep -q "KeyError: 'entry_kind'" "$ERR2"; then
    echo "ok R8-I1 repro (1b) guard-viability: reverting BOTH the point-fix AND the"
    echo "   boundary reproduces the reviewer's own exact finding -- KeyError crashes"
    echo "   uncaught, rc=1 (Python's own default), no --out written"
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
  if [ ! -f "$OUT2" ] && grep -q "^Traceback" "$ERR2" \
      && grep -Eq "^${exc}: (R8_TOPINJ_PROOF|'R8_TOPINJ_PROOF')\$" "$ERR2"; then
    echo "ok R8-I1 repro (2, $exc) guard-viability: reverting JUST the boundary's own"
    echo "   catch set back to fc_common.SAFE_EXCEPTIONS makes the SAME injected $exc"
    echo "   crash uncaught -- proving the Exception widening genuinely does the work"
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
D3="$TMP/r8i2_reverted"
mkdir -p "$D3/orchestration" "$D3/lib"
cp "$IMPL" "$D3/orchestration/custody_sweep.py"
cp "$LIB" "$D3/lib/fc_common.py"
python3 - "$D3/orchestration/custody_sweep.py" <<'PYEOF'
import re, sys
p = sys.argv[1]
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
with open(p, "w", encoding="utf-8") as fh:
    fh.write(before + mutated_body + after)
PYEOF
if [ $? -ne 0 ]; then
  echo "NOT ok R8-I2 guard-viability: env-strip mutation anchor not found (content drifted)"
  failx
else
  # Reset the victim repo's config to a known-clean baseline before the
  # SECOND (unsanitized-copy) run, so this check measures ONLY that run's
  # own effect, never residue from the first (fixed-tool) run above.
  (
    cd "$TMP/victim"
    git config --unset core.hooksPath 2>/dev/null
    git config user.email "victim@example.invalid"
    git config user.name "victim"
    git config --unset commit.gpgsign 2>/dev/null
  )
  BEFORE_MD5_2=$(md5sum "$TMP/victim/.git/config" | awk '{print $1}')
  SELFTEST_OUT2="$TMP/gitdir_selftest_reverted.out"
  (
    export GIT_DIR="$TMP/victim/.git"
    export GIT_WORK_TREE="$TMP/victim"
    python3 "$D3/orchestration/custody_sweep.py" selftest --repo-root "$TMP/goodroot" --fixtures-dir "$CS_FIXDIR"
  ) >"$SELFTEST_OUT2" 2>&1
  AFTER_MD5_2=$(md5sum "$TMP/victim/.git/config" | awk '{print $1}')
  if [ "$BEFORE_MD5_2" != "$AFTER_MD5_2" ]; then
    echo "ok R8-I2 guard-viability: reverting the scratch-env isolation makes the SAME"
    echo "   victim-GIT_DIR scenario mutate the victim's .git/config AGAIN (md5"
    echo "   $BEFORE_MD5_2 -> $AFTER_MD5_2) -- proving the sanitized-environment fix"
    echo "   genuinely does the work, never a tautological mutation"
  else
    echo "NOT ok R8-I2 guard-viability BLIND: victim .git/config unchanged even with the"
    echo "     env-sanitization stripped ($(cat "$SELFTEST_OUT2" 2>/dev/null | tail -5))"
    failx
  fi
fi

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
