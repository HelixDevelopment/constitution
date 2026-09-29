#!/bin/bash
# Purpose : pin kill_tree()'s OWN pid-<=1 guard at BOTH the TERM stage and the KILL stage,
#           INDEPENDENT of whatever descendants() itself would or would not filter. That
#           regression coverage is the sibling test_foundational_mutations_descendants_filter.sh,
#           which exercises descendants() directly with NO involvement of kill_tree() (11.4.115(F),
#           11.4.201). This file used to extract descendants()+kill_tree() TOGETHER and drive them
#           through a `ps` fixture; that made it a COMBINED test of the two functions' cooperating
#           behaviour, and each function's own guard silently masked a regression in the OTHER one:
#           once descendants() started filtering pid<=1 out of its own output (fixing a real,
#           host-wide SIGTERM/SIGKILL hazard -- a poisoned fake `ps` line for pid 1, a universal
#           host ancestor, ballooned the transitive closure to ~905 of the host's ~907 real
#           processes), pid 1 never reached kill_tree()'s guard through the combined fixture at
#           all, so a mutation that weakens kill_tree()'s OWN `-gt 1` check (M7) stopped being
#           caught here even though the mutated line never runs correctly on its own (measured: the
#           mutation's own driver-fixture kept passing with the weakened guard once the closure fix
#           landed). This split makes each function's guard independently provable again.
# Technique: extract ONLY kill_tree()'s body (sed, anchored on its own standalone closing brace --
#           the range is robust to the M7 sed mutation itself, which only edits an interior
#           comparison, never a brace line) from the unit under test; define OUR OWN stand-in
#           descendants() that unconditionally prints four fixed candidates -- "1", "0", "-1", and a
#           real fake pid RP -- bypassing ANY closure-membership filtering entirely, so kill_tree's
#           guard checks are exercised no matter what descendants() itself does or does not filter;
#           source a log-only `kill` (never sends a real signal -- 11.4.263, 11.4.273) ahead of the
#           extracted kill_tree() in the SAME shell (`bash -c '. shim; . funcs; kill_tree ...'`),
#           then call kill_tree directly and inspect the log.
# Safety  : the fake root/descendant value RP is kernel.pid_max + 303, so it can never name a real
#           process even if the log-only kill shim were bypassed by accident.
# Usage   : bash test_foundational_mutations_kill_tree.sh   Exit 0 = all assertions hold.
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
  # Unconditional stand-in (11.4.273): ALWAYS the same four candidates regardless of \$1 -- "1" and
  # "0" (numeric, so they reach kill_tree's "-gt 1" comparisons), "-1" (non-numeric under the
  # project's shell-integer convention, so it should never even reach a comparison), and a real
  # fake pid RP (the positive control -- kill_tree MUST still signal an actual descendant). No
  # closure-membership filtering happens here at all -- that is the OTHER function's job, tested in
  # isolation by the sibling test_foundational_mutations_descendants_filter.sh.
  printf '1\n0\n-1\n%s\n' "$RP"
}
kill() { printf '%s\n' "\$*" >>"$tmp/kill.log"; case "\$1" in -0) return 1 ;; *) return 0 ;; esac; }
EOF

: >"$tmp/kill.log"
bash -c '. "$1"; . "$2"; kill_tree "$3"' bash "$tmp/shim.sh" "$tmp/funcs.sh" "$RP"

if grep -qx -- "-s TERM 1" "$tmp/kill.log"; then echo "NOT ok kill_tree TERM-signals pid 1"; failx
else echo "ok kill_tree never TERM-signals pid 1"; fi
if grep -qx -- "-s KILL 1" "$tmp/kill.log"; then echo "NOT ok kill_tree KILL-signals pid 1"; failx
else echo "ok kill_tree never KILL-signals pid 1"; fi
if grep -qx -- "-s TERM 0" "$tmp/kill.log"; then echo "NOT ok kill_tree TERM-signals pid 0"; failx
else echo "ok kill_tree never TERM-signals pid 0"; fi
if grep -qx -- "-s KILL 0" "$tmp/kill.log"; then echo "NOT ok kill_tree KILL-signals pid 0"; failx
else echo "ok kill_tree never KILL-signals pid 0"; fi
if grep -qx -- "-s TERM -1" "$tmp/kill.log"; then echo "NOT ok kill_tree TERM-signals pid -1"; failx
else echo "ok kill_tree never TERM-signals pid -1"; fi
if grep -qx -- "-s KILL -1" "$tmp/kill.log"; then echo "NOT ok kill_tree KILL-signals pid -1"; failx
else echo "ok kill_tree never KILL-signals pid -1"; fi
if grep -qx -- "-s TERM $RP" "$tmp/kill.log"; then echo "ok kill_tree TERM-signals the real descendant"
else echo "NOT ok kill_tree did not TERM-signal $RP"; failx; fi
if grep -qx -- "-s KILL $RP" "$tmp/kill.log"; then echo "ok kill_tree KILL-signals the real descendant"
else echo "NOT ok kill_tree did not KILL-signal $RP"; failx; fi

exit $fail
