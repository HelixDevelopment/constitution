#!/bin/bash
# Purpose : prove descendants()'s closure-membership filter (the trailing
#           `&& q ~ /^[0-9]+$/ && q + 0 > 1` clause) is load-bearing DIRECTLY -- i.e. WITHOUT going
#           through kill_tree() at all. kill_tree() has its OWN independent `-gt 1` guard (pinned
#           in isolation by the sibling test_foundational_mutations_kill_tree.sh, which stubs
#           descendants() out entirely -- 11.4.115(F)), and that guard silently PAPERS OVER a
#           regression here: with the closure-membership filter removed, descendants() puts pid 1
#           back into its output, but kill_tree()'s own "-gt 1" check still correctly refuses to
#           signal it -- so a combined test (calling kill_tree() and observing its kill log) cannot
#           tell the two functions' guards apart, and a regression in EITHER one alone goes
#           uncaught (measured directly: the pre-split combined test still passed with this exact
#           filter stripped). This file is the missing, independent regression coverage for that
#           filter -- the fix that stopped a poisoned fake `ps` line for pid 1 (a universal host
#           ancestor) from ballooning the transitive closure to ~905 of the host's ~907 real
#           processes (real, host-wide SIGTERM/SIGKILL traffic on every run of the r8b D6 case,
#           before the fix).
# Technique: extract ONLY descendants() (sed, from its own opening line up to but excluding the
#           NEXT function's opening line -- descendants() has no standalone closing brace of its
#           own, its body ends inline on the same source line as the closing quote of the awk
#           program) from the unit under test; source a shim `ps` fabricating a fixture where pid
#           "1" is a child of a real fake root RP (the same fixture shape the original combined
#           test used); call descendants() directly and assert "1" is absent from its output while
#           RP (self-inclusive by design -- the closure always contains its own seed) is present.
# Safety  : the fake root RP is kernel.pid_max + 303, so it can never name a real process. The real
#           `ps -eo pid=,ppid=` output is never consulted -- the fixture fully shadows `ps`
#           regardless of the args descendants() passes it (11.4.263, 11.4.273).
# Usage   : bash test_foundational_mutations_descendants_filter.sh   Exit 0 = all assertions hold.
here=$(cd "$(dirname "$0")" && pwd)
unit="$here/test_foundational_mutations.sh"
[ -f "$unit" ] || { echo "NOT ok test_foundational_mutations.sh missing"; exit 1; }
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fail=0
failx() { fail=1; [ -z "$FC_TEST_FAILFAST" ] || exit 1; }

sed -n '/^descendants() {/,/^kill_tree() {/p' "$unit" | sed '$d' >"$tmp/funcs.sh"
[ -s "$tmp/funcs.sh" ] || { echo "NOT ok extraction produced nothing (needle failed, 11.4.273)"; exit 1; }
grep -q '^descendants() {' "$tmp/funcs.sh" || { echo "NOT ok extraction missing descendants()"; exit 1; }
grep -q '^kill_tree() {' "$tmp/funcs.sh" && { echo "NOT ok extraction pulled in kill_tree() too (range mismatch)"; exit 1; }

PM=$(cat /proc/sys/kernel/pid_max 2>/dev/null); case $PM in ''|*[!0-9]*) echo "SKIP pid_max_unreadable"; exit 0 ;; esac
RP=$((PM + 303))

cat >"$tmp/shim.sh" <<EOF
# shellcheck disable=SC2317  # invoked by the sourced unit
ps() {
  # Fabricated fixture (11.4.273), the same shape as the forensic incident: pid RP's "parent" is
  # this shell (\$\$); pid "1" is fabricated as RP's own child so it lands inside descendants(RP)
  # IF the closure-membership filter is missing or weakened. Real \`ps -eo pid=,ppid=\` output is
  # never consulted -- the function is fully shadowed regardless of the args descendants() passes it.
  printf '%s %s\n1 %s\n' "$RP" "\$\$" "$RP"
}
EOF

out=$(bash -c '. "$1"; . "$2"; descendants "$3"' bash "$tmp/shim.sh" "$tmp/funcs.sh" "$RP")

if printf '%s\n' "$out" | grep -qx '1'; then echo "NOT ok descendants() includes pid 1 in the closure (regression: the ballooning-closure hazard)"; failx
else echo "ok descendants() excludes pid 1 from the closure"; fi
if printf '%s\n' "$out" | grep -qx "$RP"; then echo "ok descendants() includes the real root $RP (self-inclusive by design)"
else echo "NOT ok descendants() did not include $RP (needle failed -- the fixture did not exercise the closure at all)"; failx; fi

exit $fail
