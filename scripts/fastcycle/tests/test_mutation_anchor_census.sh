#!/usr/bin/env bash
# =============================================================================
# test_mutation_anchor_census.sh -- tests of tests/check_mutation_anchors.py (carry review round 1, F2).
#
# [AC-real]      the real tree: every anchor of every mutant matches exactly once (exit 0, drift=0, needle=ok).
# [AC-drift-r6]  golden-bad: a replica whose baseline_replay.sh no longer carries R5-F2c's anchor -> exit 1, DRIFT R5-F2c
#                (the exact drift the round-1 review found).
# [AC-drift-cl]  golden-bad: a replica whose fc_supervisor.py no longer carries the cleanup test's mutation-B anchor ->
#                exit 1, DRIFT cleanup-B.
# [AC-blind]     a replica with no runner -> exit 2 (BLIND), never 0 or 1.
# Replicas live in a mktemp directory; the real tree is only read.
# Exit: 0 every case held; 1 otherwise.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
AC="$HERE/check_mutation_anchors.py"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }

out="$(python3 -I "$AC" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && grep -q 'drift=0 needle=ok' <<<"$out"; then ok "[AC-real] $(tail -1 <<<"$out")"; else bad "[AC-real] rc=$rc $(tail -3 <<<"$out" | tr '\n' ' ')"; fi

mkrep() { # $1 name: a replica of cycle/ lib/ tests/
  local r="$WORK/$1"; mkdir -p "$r"
  cp -r "$FC/cycle" "$FC/lib" "$FC/tests" "$r/"
  echo "$r"
}
r="$(mkrep r6)"
python3 -I - "$r/cycle/baseline_replay.sh" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = 'worktree unlock "${_FC_WT_PATH:?}"'
assert t.count(a) == 1
open(p, "w").write(t.replace(a, 'worktree unlock "$_FC_WT_PATH"'))
PY
out="$(python3 -I "$AC" --fc "$r" --tests "$r/tests" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q '^DRIFT R5-F2c:' <<<"$out" && grep -q 'drift=1 ' <<<"$out"; then ok "[AC-drift-r6] $(grep '^DRIFT' <<<"$out" | cut -c1-120)"; else bad "[AC-drift-r6] rc=$rc $(tail -3 <<<"$out" | tr '\n' ' ')"; fi

r="$(mkrep cl)"
python3 -I - "$r/cycle/fc_supervisor.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
a = "    process_ledger(tmpdir, reason, statedir)\n"
assert t.count(a) == 1
open(p, "w").write(t.replace(a, "    process_ledger(tmpdir, reason, statedir=statedir)\n"))
PY
out="$(python3 -I "$AC" --fc "$r" --tests "$r/tests" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -q '^DRIFT cleanup-B:' <<<"$out"; then ok "[AC-drift-cl] $(grep '^DRIFT' <<<"$out" | cut -c1-120)"; else bad "[AC-drift-cl] rc=$rc $(tail -3 <<<"$out" | tr '\n' ' ')"; fi

r="$(mkrep blind)"; rm -f "$r/tests/test_fastcycle_r6_mutations.sh"
out="$(python3 -I "$AC" --fc "$r" --tests "$r/tests" 2>&1)"; rc=$?
if [ "$rc" = 2 ] && grep -q '^BLIND' <<<"$out"; then ok "[AC-blind] a missing runner is BLIND (exit 2)"; else bad "[AC-blind] rc=$rc $out"; fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
