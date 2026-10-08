#!/bin/bash
# T043 round-2 review finding N2 (§11.4.135/§11.4.43/§1.1): permanent
# regression guard for the orphan-`git worktree`-leak defect found+fixed in
# `cycle/baseline_replay.sh`'s `do_one_replay()` -- commit `bd9ff47`.
#
# ROOT CAUSE (recap, rounds 1-2): `cleanup()` was invoked via `trap cleanup
# EXIT`, and every early `return 4` in `do_one_replay()` popped that
# function's `local` variables BEFORE the EXIT trap fired, so the trap crashed
# with "unbound variable" and leaked the worktree; round 2's fix baked the paths
# into the trap string with `printf %q` (N1: also for a quote-carrying path).
#
# T048 restart round 3 (STRUCTURAL): the trap is gone. Cleanup is two layers:
#   (1) the WORKER removes its own worktree on every return path of
#       do_one_replay() (_fc_wt_cleanup; the paths live in globals that outlive
#       the body, so the round-2 class cannot recur); and
#   (2) the SUPERVISOR (cycle/fc_supervisor.py) removes any worktree still
#       listed in its ledger after the worker is gone -- the path every stop of
#       the tool takes (the stop matrix in test_baseline_replay_r2_findings.sh
#       guards that layer with a quote+space worktree root on every row).
# THIS FILE proves, on the mismatched-tree early-return path (real scratch
# repos, a control-needled `git worktree list --porcelain` count): the current
# script leaks nothing with a plain and with a quote-carrying --worktree-root,
# and layer (1) did the work (the supervisor's recovery message is ABSENT). The
# §1.1 paired mutations: (A) without layer (1) the supervisor's recovery message
# appears (and layer (2) still removes the worktree -- also with a quote in the
# path); (B) without either layer the worktree genuinely leaks.
#
# Producer!=Verifier (§11.4.240): authored by the conductor closing a
# review finding against code it did not originally implement without
# independent review of its own construction; this file's own author is
# NOT the implementer of `do_one_replay()`'s original (pre-bd9ff47) code.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
REAL_SCRIPT="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"

fail=0
failx() { fail=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export FC_REPLAY_LOCK_DIR="$WORK/locks"
mkdir -p "$FC_REPLAY_LOCK_DIR"

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
RUN_CASE_RECOVERED=0
run_case() {
  script="$1"; wtroot="$2"; label="$3"
  mkdir -p "$wtroot"
  before="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')"
  bash "$script" replay \
    --commit "$SHA" --tree "$WRONG_TREE" \
    --repo-root "$REPO" --worktree-root "$wtroot" \
    --min-free-kb 0 --gate-cmd true --cold-runs 1 --warm-runs 1 \
    --out "$WORK/out_${label}.json" >/dev/null 2>"$WORK/stderr_${label}.log"
  rc=$?
  after="$(git -C "$REPO" worktree list --porcelain | grep -c '^worktree ')"
  leftover="$(find "$wtroot" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
  RUN_CASE_RECOVERED=0
  grep -q "supervisor: removed the worktree" "$WORK/stderr_${label}.log" 2>/dev/null && RUN_CASE_RECOVERED=1
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
  if [ "$rc" = 4 ] && [ "$RUN_CASE_IS_LEAK" = 0 ] && [ "$RUN_CASE_RECOVERED" = 0 ]; then
    echo "ok $label: exit=$rc (expect 4) worktree-count $before -> $after (unchanged) leftover-dirs=$leftover -- no leak, removed by the worker itself"
    return 0
  else
    echo "NOT ok $label: exit=$rc (expect 4) worktree-count $before -> $after leftover-dirs=$leftover leak=$RUN_CASE_IS_LEAK supervisor-recovered=$RUN_CASE_RECOVERED (the worker did not clean up after itself)"
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

# --- §1.1 paired mutations against a throwaway replica (cycle/ + lib/), so the
# script's own $FC/lib resolution and its fc_supervisor.py are the replica's ---
# mk_mutant NAME PYTHON-REPLACEMENTS... : builds $WORK/mut_NAME/cycle/baseline_replay.sh
mk_mutant() {
  local name="$1"; shift
  local root="$WORK/mut_$name"
  mkdir -p "$root"
  cp -r "$FC/cycle" "$root/cycle"; cp -r "$FC/lib" "$root/lib"
  [ -n "${FC_BR_UNDER_TEST:-}" ] && cp "$FC_BR_UNDER_TEST" "$root/cycle/baseline_replay.sh"
  python3 - "$root" "$@" <<'PYEOF'
import os, sys
root, pairs = sys.argv[1], sys.argv[2:]
for i in range(0, len(pairs), 3):
    rel, old, new = pairs[i], pairs[i + 1], pairs[i + 2]
    path = os.path.join(root, rel)
    src = open(path).read()
    n = src.count(old)
    if n != 1:
        sys.stderr.write("mutation anchor matched %d times in %s: %r\n" % (n, rel, old[:80]))
        sys.exit(3)
    open(path, "w").write(src.replace(old, new, 1))
PYEOF
}

echo
echo "=== case 3 (paired mutation A, §1.1): without the worker's own cleanup the supervisor must step in (recovery message), and still leak nothing -- also on a quote-carrying path ==="
if mk_mutant A cycle/baseline_replay.sh $'  _do_one_replay_body "$@"\n  local rc=$?\n  _fc_wt_cleanup\n' $'  _do_one_replay_body "$@"\n  local rc=$?\n'; then
  for wtr in "$WORK/wtroot_mutA" "$WORK/wt_mutA'quote x"; do
    run_case "$WORK/mut_A/cycle/baseline_replay.sh" "$wtr" "mutantA" >"$WORK/mutA.log" 2>&1
    if [ "$RUN_CASE_RECOVERED" = 1 ] && [ "$RUN_CASE_IS_LEAK" = 0 ]; then
      echo "ok mutation A check ($wtr): the worker's cleanup is load-bearing (this test sees its absence: supervisor-recovered=1) and the supervisor's ledger layer removed the worktree (no leak)"
    else
      echo "NOT ok mutation A check ($wtr): recovered=$RUN_CASE_RECOVERED leak=$RUN_CASE_IS_LEAK -- either the test cannot tell who cleaned up, or the supervisor's ledger layer failed on this path"
      cat "$WORK/mutA.log"
      failx
    fi
  done
else
  echo "NOT ok mutation A could not be built (anchor drifted)"; failx
fi

echo
echo "=== case 4 (paired mutation B, §1.1): without BOTH layers the worktree must genuinely leak ==="
if mk_mutant B cycle/baseline_replay.sh $'  _do_one_replay_body "$@"\n  local rc=$?\n  _fc_wt_cleanup\n' $'  _do_one_replay_body "$@"\n  local rc=$?\n' \
     cycle/fc_supervisor.py $'    process_ledger(tmpdir, reason)\n' $'    pass\n'; then
  run_case "$WORK/mut_B/cycle/baseline_replay.sh" "$WORK/wtroot_mutB" "mutantB" >"$WORK/mutB.log" 2>&1
  if [ "$RUN_CASE_IS_LEAK" = 1 ]; then
    echo "ok mutation B check: with neither cleanup layer the worktree leaks (leak=1) -- the leak check is real"
  else
    echo "NOT ok mutation B check: no leak observed with both cleanup layers removed -- the leak check proves nothing"
    cat "$WORK/mutB.log"
    failx
  fi
else
  echo "NOT ok mutation B could not be built (anchor drifted)"; failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "SUMMARY: all worktree-cleanup regression checks PASS (the worker removes its own worktree on plain and quote-carrying paths; mutation A shows the supervisor layer steps in, mutation B shows a genuine leak)"
else
  echo "SUMMARY: worktree-cleanup regression check FAILED -- see NOT ok lines above"
fi
exit $fail
