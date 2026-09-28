#!/bin/bash
# T043 round-2 review finding N2 (§11.4.135/§11.4.43/§1.1): permanent
# regression guard for the orphan-`git worktree`-leak defect found+fixed in
# `cycle/baseline_replay.sh`'s `do_one_replay()` -- commit `bd9ff47`.
#
# ROOT CAUSE (recap): `cleanup()` is invoked via `trap cleanup EXIT`, and
# every early `return 4` in `do_one_replay()` pops that function's OWN
# `local` variables BEFORE the EXIT trap fires in the (sub)shell that is
# exiting -- so a `cleanup()` that referenced those locals directly crashed
# with "unbound variable" under `set -u`, pre-empting the real
# `git worktree remove --force` / `rm -rf` and silently leaking the
# worktree. The FIX bakes `repo_root`/`wt_path` into the trap command
# STRING at `trap` REGISTRATION time via `printf %q` (shell-safe quoting
# for any path, including one containing a literal `'`, closing round-2's
# finding N1 -- an earlier fix attempt that hand-wrapped the values in
# single quotes instead of using `%q` still leaked on a quote-containing
# path).
#
# THIS FILE proves, with real scratch-git-repo runs against a
# `git worktree list --porcelain` count (never trusting an assumed count),
# BOTH that the CURRENT (fixed) script genuinely does not leak on the
# mismatched-tree early-return path AND on a quote-containing
# --worktree-root, AND -- the §1.1 paired-mutation half -- that reverting
# the fix to the ORIGINAL buggy trap-registration form makes this SAME
# test genuinely FAIL (proving the test catches the regression it exists
# to catch, not merely agreeing with whatever the code currently does).
#
# Producer!=Verifier (§11.4.240): authored by the conductor closing a
# review finding against code it did not originally implement without
# independent review of its own construction; this file's own author is
# NOT the implementer of `do_one_replay()`'s original (pre-bd9ff47) code.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
REAL_SCRIPT="$FC/cycle/baseline_replay.sh"

fail=0
failx() { fail=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- §11.4.273 control needle: prove `git worktree list --porcelain | grep -c
# "^worktree "` genuinely counts what it claims to count, before trusting any
# count derived from it below. ---
NEEDLE_REPO="$WORK/needle_repo"
mkdir -p "$NEEDLE_REPO"
git -C "$NEEDLE_REPO" init -q
git -C "$NEEDLE_REPO" config user.email t@t.t
git -C "$NEEDLE_REPO" config user.name t
echo x > "$NEEDLE_REPO/f.txt"
git -C "$NEEDLE_REPO" add f.txt
git -C "$NEEDLE_REPO" commit -q -m c1
BASE_COUNT="$(git -C "$NEEDLE_REPO" worktree list --porcelain | grep -c '^worktree ')"
if [ "$BASE_COUNT" != "1" ]; then
  echo "NOT ok control needle: a freshly-init'd single-commit repo reports"
  echo "   worktree count=$BASE_COUNT, expected exactly 1 (the main worktree"
  echo "   itself) -- the counting instrument is not trustworthy; every"
  echo "   leak-check below proves nothing (§11.4.273)"
  failx
else
  git -C "$NEEDLE_REPO" worktree add --detach --quiet "$WORK/needle_wt" >/dev/null 2>&1
  AFTER_ADD="$(git -C "$NEEDLE_REPO" worktree list --porcelain | grep -c '^worktree ')"
  git -C "$NEEDLE_REPO" worktree remove --force "$WORK/needle_wt" >/dev/null 2>&1
  if [ "$AFTER_ADD" = "2" ]; then
    echo "ok control needle: worktree-count instrument correctly reports 1"
    echo "   for a bare repo and 2 after a real 'worktree add' -- trustworthy"
  else
    echo "NOT ok control needle: adding one real worktree did not move the"
    echo "   count from 1 to 2 (got $AFTER_ADD) -- instrument not trustworthy"
    failx
  fi
fi
rm -rf "$WORK/needle_wt" 2>/dev/null

# --- shared fixture repo for both leak-repro cases below ---
REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
echo hello > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" commit -q -m c1
SHA="$(git -C "$REPO" rev-parse HEAD)"
WRONG_TREE="0000000000000000000000000000000000dead"

# run_case SCRIPT WTROOT LABEL
# Runs SCRIPT's `replay` subcommand against the mismatched-tree early-return
# path with --worktree-root WTROOT, and prints the pre/post worktree count +
# leftover-dir listing. Returns 0 if clean (no leak AND the expected exit
# code), 1 otherwise.
#
# Sets three globals for the CALLER to inspect the SPECIFIC failure shape
# (T043 round-3 review finding F1, fixed 2026-09-28): a failure with NO
# count-change and NO leftover directory is a DIFFERENT-reason failure (e.g.
# an unrelated exit-code mismatch), never itself proof of "this reproduces
# THE LEAK" -- case 3 below now checks RUN_CASE_IS_LEAK specifically rather
# than treating run_case's overall non-zero return as sufficient evidence of
# a leak, closing the bluff-gate shape the review found (a mutant failing
# for ANY unrelated reason could previously have been misreported as "the
# mutation reproduces the leak").
RUN_CASE_IS_LEAK=0
RUN_CASE_STDERR=""
run_case() {
  script="$1"; wtroot="$2"; label="$3"
  mkdir -p "$wtroot"
  before="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')"
  bash "$script" replay \
    --commit "$SHA" --tree "$WRONG_TREE" \
    --repo-root "$REPO" --worktree-root "$wtroot" \
    --gate-cmd true --cold-runs 1 --warm-runs 1 \
    --out "$WORK/out_${label}.json" >/dev/null 2>"$WORK/stderr_${label}.log"
  rc=$?
  after="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')"
  leftover="$(find "$wtroot" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  RUN_CASE_STDERR="$(cat "$WORK/stderr_${label}.log" 2>/dev/null)"
  if [ "$after" != "$before" ] || [ "$leftover" != "0" ]; then
    RUN_CASE_IS_LEAK=1
  else
    RUN_CASE_IS_LEAK=0
  fi
  # clean up any real leak so the NEXT case (possibly against the SAME repo)
  # starts from a known-clean state regardless of this case's own verdict.
  if [ "$after" != "$before" ]; then
    for d in "$wtroot"/*; do
      [ -d "$d" ] || continue
      git -C "$REPO" worktree remove --force "$d" >/dev/null 2>&1
    done
    rm -rf "$wtroot"
  fi
  if [ "$rc" = 4 ] && [ "$RUN_CASE_IS_LEAK" = 0 ]; then
    echo "ok $label: exit=$rc (expect 4) worktree-count $before -> $after (unchanged) leftover-dirs=$leftover -- no leak"
    return 0
  else
    echo "NOT ok $label: exit=$rc (expect 4) worktree-count $before -> $after leftover-dirs=$leftover leak=$RUN_CASE_IS_LEAK"
    echo "   -- stderr:"
    sed 's/^/     /' "$WORK/stderr_${label}.log"
    return 1
  fi
}

echo
echo "=== case 1: CURRENT (fixed) script, plain --worktree-root ==="
run_case "$REAL_SCRIPT" "$WORK/wtroot1" "fixed_plain" || failx

echo
echo "=== case 2: CURRENT (fixed) script, --worktree-root containing a literal single quote (N1) ==="
run_case "$REAL_SCRIPT" "$WORK/wt'quote'1" "fixed_quote" || failx

# --- §1.1 paired mutation: revert the fix to the ORIGINAL buggy form and
# prove THIS SAME test genuinely fails against it. ---
echo
echo "=== case 3 (paired mutation, §1.1): reverting the trap-registration fix must make this SAME test FAIL ==="
MUTANT="$WORK/baseline_replay_mutant.sh"
cp "$REAL_SCRIPT" "$MUTANT"
python3 - "$MUTANT" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
fixed_block = '''  cleanup() {
    local rr="$1" wp="$2"
    git -C "$rr" worktree remove --force "$wp" >/dev/null 2>&1
    rm -rf "$wp" 2>/dev/null
  }
  local _cleanup_trap_cmd
  printf -v _cleanup_trap_cmd 'cleanup %q %q' "$repo_root" "$wt_path"
  trap "$_cleanup_trap_cmd" EXIT'''
buggy_block = '''  local cleanup_done=0
  cleanup() {
    if [ "$cleanup_done" = 0 ]; then
      cleanup_done=1
      git -C "$repo_root" worktree remove --force "$wt_path" >/dev/null 2>&1
      rm -rf "$wt_path" 2>/dev/null
    fi
  }
  trap cleanup EXIT'''
assert fixed_block in src, "mutation anchor (the fixed cleanup()/trap block) not found -- baseline_replay.sh has changed shape, update this mutation's anchor string"
assert src.count(fixed_block) == 1, "mutation anchor is not unique in the file"
src = src.replace(fixed_block, buggy_block, 1)
# the success-path explicit call also needs reverting to match (no positional args)
src = src.replace('cleanup "$repo_root" "$wt_path"\n  trap - EXIT', 'cleanup\n  trap - EXIT', 1)
open(path, "w", encoding="utf-8").write(src)
PYEOF
MUTANT_OUT="$WORK/mutant_case_output.log"
if [ $? != 0 ]; then
  echo "NOT ok mutation construction failed (see python traceback above) -- cannot verify this test catches the regression"
  failx
else
  bash -n "$MUTANT" 2>/dev/null || { echo "NOT ok mutant script has a syntax error"; failx; }
  # T043 round-3 review finding F1 (fixed 2026-09-28): a mutant failing for
  # SOME reason is not, by itself, proof it reproduces THE LEAK this test
  # guards against -- a mutant that happened to fail for an unrelated cause
  # (a different exit code, a transient error) would previously have been
  # misreported as "the mutation reproduces the leak" too, since run_case's
  # overall non-zero return conflated every failure shape. Now requires
  # SPECIFICALLY: RUN_CASE_IS_LEAK=1 (a real count-change or leftover
  # directory, set by run_case above) AND the exact "unbound variable"
  # stderr signature the ORIGINAL bug produced (see round-1's own
  # forensics) -- both together, never either alone.
  run_case "$MUTANT" "$WORK/wtroot_mutant" "mutant" >"$MUTANT_OUT" 2>&1
  MUTANT_STDERR="$RUN_CASE_STDERR"
  if [ "$RUN_CASE_IS_LEAK" = 1 ] && printf '%s' "$MUTANT_STDERR" | grep -q "unbound variable"; then
    echo "ok mutation check: reverting the fix DOES reproduce the leak (worktree"
    echo "   count changed or a directory was left behind) WITH the exact"
    echo "   original 'unbound variable' crash signature -- this test genuinely"
    echo "   catches the regression it guards, not merely agreeing with"
    echo "   whatever the current code happens to do"
    sed 's/^NOT ok/    (expected leak) NOT ok/' "$MUTANT_OUT"
  else
    echo "NOT ok mutation check: reverting the fix did not reproduce a genuine"
    echo "   leak WITH the original crash signature (leak=$RUN_CASE_IS_LEAK,"
    echo "   'unbound variable' in stderr=$(printf '%s' "$MUTANT_STDERR" | grep -q "unbound variable" && echo yes || echo no))"
    echo "   -- this test would not reliably have caught the original"
    echo "   regression; see $MUTANT_OUT for the full run_case output"
    cat "$MUTANT_OUT"
    failx
  fi
fi

# --- F3a (T043 round-3 review): a SECOND, N1-SPECIFIC paired mutation --
# reverts ONLY the printf-%q shell-safe-quoting improvement (keeping the
# rest of the N1 fix: cleanup() taking positional args, no cleanup_done
# guard) back to the naive hand-single-quoted trap-registration form that
# round-2 proved leaks on a quote-containing path but NOT on a plain one.
# This makes N1's OWN fix self-proven by an in-file mutation, rather than
# relying only on case 2 passing against the CURRENT code (which proves the
# fix works, but not on its own that a REGRESSION to the pre-N1 hand-quoted
# form would be CAUGHT). ---
echo
echo "=== case 4 (N1-specific paired mutation, §1.1): reverting ONLY the %q shell-safe-quoting fix must leak on a quote-containing path but NOT on a plain one ==="
MUTANT_N1="$WORK/baseline_replay_mutant_n1.sh"
cp "$REAL_SCRIPT" "$MUTANT_N1"
python3 - "$MUTANT_N1" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
qsafe_form = '''  local _cleanup_trap_cmd
  printf -v _cleanup_trap_cmd 'cleanup %q %q' "$repo_root" "$wt_path"
  trap "$_cleanup_trap_cmd" EXIT'''
handquoted_form = '''  trap "cleanup '$repo_root' '$wt_path'" EXIT'''
assert src.count(qsafe_form) == 1, "N1 mutation anchor (the printf %%q trap-registration block) not found -- update this mutation's anchor string"
src = src.replace(qsafe_form, handquoted_form, 1)
open(path, "w", encoding="utf-8").write(src)
PYEOF
if [ $? != 0 ]; then
  echo "NOT ok N1-specific mutation construction failed -- cannot verify N1's fix is self-proven"
  failx
else
  bash -n "$MUTANT_N1" 2>/dev/null || { echo "NOT ok N1 mutant script has a syntax error"; failx; }
  N1_PLAIN_OUT="$WORK/mutant_n1_plain.log"
  run_case "$MUTANT_N1" "$WORK/wtroot_mutant_n1_plain" "mutant_n1_plain" >"$N1_PLAIN_OUT" 2>&1
  N1_PLAIN_LEAK="$RUN_CASE_IS_LEAK"
  N1_QUOTE_OUT="$WORK/mutant_n1_quote.log"
  run_case "$MUTANT_N1" "$WORK/wt_mutant_n1_quote'x" "mutant_n1_quote" >"$N1_QUOTE_OUT" 2>&1
  N1_QUOTE_LEAK="$RUN_CASE_IS_LEAK"
  if [ "$N1_PLAIN_LEAK" = 0 ] && [ "$N1_QUOTE_LEAK" = 1 ]; then
    echo "ok N1-specific mutation check: the hand-quoted form is clean on a"
    echo "   PLAIN path (leak=$N1_PLAIN_LEAK) but genuinely leaks on a"
    echo "   quote-containing path (leak=$N1_QUOTE_LEAK) -- exactly matching"
    echo "   round-2's own finding, proving the %q fix is what closes this"
    echo "   SPECIFIC gap, not merely correlated with some other change"
  else
    echo "NOT ok N1-specific mutation check: expected plain-path leak=0 and"
    echo "   quote-path leak=1, got plain=$N1_PLAIN_LEAK quote=$N1_QUOTE_LEAK"
    echo "   -- see $N1_PLAIN_OUT / $N1_QUOTE_OUT"
    failx
  fi
fi

echo
if [ "$fail" = 0 ]; then
  echo "SUMMARY: all worktree-cleanup regression checks PASS (fixed script clean on all real-path cases, both the full-revert and N1-specific mutants genuinely leak in exactly the shape expected)"
else
  echo "SUMMARY: worktree-cleanup regression check FAILED -- see NOT ok lines above"
fi
exit $fail
