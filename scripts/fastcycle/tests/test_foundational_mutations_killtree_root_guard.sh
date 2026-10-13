#!/bin/bash
# Purpose : pin kill_tree()'s OWN ROOT-argument guard chain -- the case-based numeric check
#           (`case $r in ''|*[!0-9]*) return 0 ;; esac`) AND the `[ "$r" -gt 1 ] || return 0` line
#           right after it -- DIRECTLY, by calling kill_tree() with the ROOT ($1) itself set to a
#           pathological value (1, 0, -1), never merely as one of the DESCENDANT pids it later
#           iterates over. The sibling test_foundational_mutations_kill_tree.sh already pins the
#           per-descendant `[ "$p" -gt 1 ]` guard inside kill_tree's two for-loops (M7/M11) by
#           calling kill_tree with a real fake ROOT (always > 1) and stubbing descendants() to hand
#           back 1/0/-1/RP as candidate DESCENDANTS -- but that test NEVER calls kill_tree with
#           root=1, root=0, or root=-1 itself, so it cannot see a regression in the guard that
#           decides whether kill_tree does ANYTHING AT ALL for a pathological caller-supplied root
#           (11.4.115(F): each guard needs its OWN independent regression coverage, the way
#           descendants()'s closure-membership filter got its own split test rather than staying
#           combined with kill_tree's).
# Root cause reproduced (T014 round-11, IMPORTANT-3): weakening `[ "$r" -gt 1 ] || return 0` to
#           `[ "$r" -gt 0 ] || return 0` survives test_foundational_mutations_kill_tree.sh AND
#           test_foundational_mutations_descendants_filter.sh undetected, because neither ever
#           drives kill_tree's OWN root argument through the 0/1 boundary this guard exists to
#           enforce -- and D6 in test_run_all.sh cannot catch it either, because the roots it
#           supplies come from `jobs -rp`, which in practice is always > 1 (a live PID never below
#           the shell's own PGID), so it never exercises the boundary this guard is FOR. This file
#           closes that gap by calling kill_tree DIRECTLY with root=1 (the exact value the weakened
#           `-gt 0` guard admits that the correct `-gt 1` guard blocks), root=0, and root=-1, and
#           asserting ZERO kill invocations occur for any of the three -- proving the guard blocks
#           pathological/degenerate roots on its own, independent of whatever guarantee `jobs -rp`
#           happens to provide in practice.
# Technique: extract ONLY kill_tree()'s body (sed, anchored on its own standalone closing brace --
#           same range as the sibling test_foundational_mutations_kill_tree.sh) from the unit under
#           test; define OUR OWN stand-in descendants() that unconditionally hands back a single
#           real fake descendant candidate RP regardless of the root it was called with -- so IF a
#           broken root guard ever let kill_tree proceed past it, that would become directly
#           OBSERVABLE (a logged, never-sent, kill.log entry for RP) instead of silently doing
#           nothing (which would make a bypass indistinguishable from a working guard); source a
#           log-only `kill` (never sends a real signal -- 11.4.263, 11.4.273) ahead of the extracted
#           kill_tree() in the SAME shell (`bash -c '. shim; . funcs; kill_tree ...'`), call
#           kill_tree directly with each pathological root in turn, and assert its kill.log stays
#           empty every time.
# Safety  : the fake descendant candidate RP is kernel.pid_max + 303, so it can never name a real
#           process even if the log-only kill shim were bypassed by accident.
# Usage   : bash test_foundational_mutations_killtree_root_guard.sh   Exit 0 = all assertions hold.
here=$(cd "$(dirname "$0")" && pwd)
unit="$here/test_foundational_mutations.sh"
[ -f "$unit" ] || { echo "NOT ok test_foundational_mutations.sh missing"; exit 1; }
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }

sed -n '/^kill_tree() {/,/^}$/p' "$unit" >"$tmp/funcs.sh"
[ -s "$tmp/funcs.sh" ] || { echo "NOT ok extraction produced nothing (needle failed, 11.4.273)"; exit 1; }
grep -q '^kill_tree() {' "$tmp/funcs.sh" || { echo "NOT ok extraction missing kill_tree()"; exit 1; }
grep -q '^descendants() {' "$tmp/funcs.sh" && { echo "NOT ok extraction pulled in the real descendants() too (range mismatch -- would defeat the stub)"; exit 1; }

PM=$(cat /proc/sys/kernel/pid_max 2>/dev/null); case $PM in ''|*[!0-9]*) echo "SKIP pid_max_unreadable"; exit 0 ;; esac
RP=$((PM + 303))

cat >"$tmp/shim.sh" <<EOF
# shellcheck disable=SC2317  # invoked by the sourced unit
descendants() {
  # Unconditional stand-in (11.4.273): always answers with a real fake descendant candidate RP,
  # regardless of \$1 (the root kill_tree was called with -- this test drives it with 1/0/-1). A
  # correctly-guarded kill_tree() for a pathological root MUST return before ever reaching this
  # call -- so this stub existing at all is what would let a broken root guard's bypass become
  # OBSERVABLE (a logged kill.log entry for RP), never a real host-wide signal, if the guard ever
  # let it through.
  printf '%s\n' "$RP"
}
kill() { printf '%s\n' "\$*" >>"$tmp/kill.log"; case "\$1" in -0) return 1 ;; *) return 0 ;; esac; }
EOF

check_root() { # root
  : >"$tmp/kill.log"
  bash -c '. "$1"; . "$2"; kill_tree "$3"' bash "$tmp/shim.sh" "$tmp/funcs.sh" "$1"
  if [ -s "$tmp/kill.log" ]; then
    echo "NOT ok kill_tree(root=$1) signalled something (root guard bypassed):"
    sed 's/^/    /' "$tmp/kill.log"
    failx
  else
    echo "ok kill_tree(root=$1) signals nothing (root guard holds)"
  fi
}

# §11.4.273 control needle for this file's own extraction+shim+invocation pipeline (T014 round-12
# IMPORTANT finding): every check_root call above proves ONLY that kill.log stayed empty -- and an
# empty result is unproven absence unless this exact pipeline is FIRST shown able to produce a
# non-empty result. Reproduced live before writing this fix: inject a syntax error into kill_tree()
# so the extracted function is never even defined ("kill_tree: command not found") -- every
# check_root call above still prints "ok ... (root guard holds)" and the whole file exits 0, a
# complete pass-bluff for an entirely different failure (the guard was never exercised at all,
# because kill_tree itself never ran). The sibling test_foundational_mutations_kill_tree.sh already
# avoids this exact trap (it positively asserts its fake descendant RP IS signalled); this file
# needs the same positive control on ITS OWN root argument, run BEFORE the pathological-root
# absence checks (needle-before-absence-check, the same ordering needle_control() uses elsewhere).
VALID_ROOT=$((RP - 1))   # non-pathological (> 1), guaranteed nonexistent (still > pid_max)
check_root_valid() {
  : >"$tmp/kill.log"
  bash -c '. "$1"; . "$2"; kill_tree "$3"' bash "$tmp/shim.sh" "$tmp/funcs.sh" "$VALID_ROOT"
  if grep -q '^-s TERM ' "$tmp/kill.log" && grep -q '^-s KILL ' "$tmp/kill.log"; then
    echo "ok kill_tree(root=$VALID_ROOT) signals the real fake descendant (positive control: extraction+shim+invocation pipeline genuinely works)"
  else
    echo "NOT ok kill_tree(root=$VALID_ROOT) signalled NOTHING for a genuinely valid root -- the extraction/shim/invocation pipeline is broken, so every 'guard holds' verdict above proves nothing (11.4.273 control needle failed)"
    sed 's/^/    /' "$tmp/kill.log"
    failx
  fi
}

check_root_valid
check_root 1
check_root 0
check_root -1

exit $fail
