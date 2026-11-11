#!/bin/bash
# fastcycle-timeout-s: 1200
# Purpose : CON-222 / CON-223 regression guard (review fu_b F1, F2; reviewer mutants RV-E, RV-F) for the L29 leg of
#           scripts/fastcycle/tests/test_consumer_required_helper.sh. A host without a usable UTF-8 locale makes L29 a
#           SKIP-with-reason; before CON-222 that SKIP never reached the suite verdict (SUMMARY N pass / 0 fail, exit 0),
#           RV-E (the SKIP counted as a PASS through ok) and RV-F (the SKIP line dropped) survived, and an ambient
#           FC_L29_CANDIDATES value was honoured silently (F2).
# Usage   : bash scripts/fastcycle/tests/test_consumer_required_helper_l29_skip_r1_regression.sh
#           Exit 0 when every check passes, 1 otherwise, 77 (reason=topology_unsupported) when this tree is not a git
#           checkout or sqlite3 is absent (the helper test's Part 3, which holds L29, needs it). Last line: the summary.
# Method  : the REAL helper test, run whole on a COPY of the tracked scripts/ tree and Constitution.md (git ls-files; the checked tree is
#           never changed) with FC_L29_CANDIDATES=zz_ZZ.UTF-8 (a simulated host without such a locale) and
#           FC_HELPER_UNDER_TEST pointing at the copy's unmutated helper (so Part 4, the slow real cycle_report suites,
#           is skipped; it does not touch L29). Control needle: the unmutated copy ends rc 77 with 0 NOT ok lines, the
#           SKIP: L29 line, the override note and a SUMMARY that counts the skip. Paired mutants, each must break that:
#           RV-E and RV-F (verbatim, on the dispatch function), M3 (the final exit ignores the skip count), M4 (no note).
#           One run at a time (about a minute each; host safety). Deletion: safe_rm_rf restricted to the temp root.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CANON="$(cd "$HERE/../../.." && pwd)"
. "$CANON/scripts/lib/safe_rm.sh"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }
command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: sqlite3 is not installed, Part 3 (L29) of the helper test cannot run reason=topology_unsupported"; exit 77; }
git -C "$CANON" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "SKIP: $CANON is not a git checkout, the tracked scripts/ tree cannot be copied reason=topology_unsupported"; exit 77; }
W="$(mktemp -d "${TMPDIR:-/tmp}/l29_skip_r1.XXXXXX")" || { echo "NOT ok mktemp failed"; exit 1; }
export SAFE_RM_ALLOWED_ROOTS="$W"
trap 'safe_rm_rf "${W:?}"' EXIT

T="test_consumer_required_helper.sh"
mkcopy() { # $1 = copy root; copies every tracked file under scripts/ plus Constitution.md (symlinks kept as links)
  ( cd "$CANON" && git ls-files -z -- scripts Constitution.md | xargs -0 cp -P --parents -t "$1" ) 2>/dev/null
}
# the copy root is named "constitution" and carries Constitution.md: the monday_dryrun test derives the canon root
# from that layout (it requires <root>/Constitution.md); measured, a copy without it fails that Part 2 leg.
mkdir -p "$W/base/constitution" && mkcopy "$W/base/constitution" && [ -f "$W/base/constitution/scripts/fastcycle/tests/$T" ] \
  || { echo "NOT ok copy of the tracked scripts/ tree failed (blind)"; exit 1; }

# judge <dir> -> prints a one-line reason and returns 0 when the run shows the honest skipped verdict
judge() {
  local d="$1" o="$1/run.out" rc last
  ( cd "$d" && FC_L29_CANDIDATES=zz_ZZ.UTF-8 FC_HELPER_UNDER_TEST="$d/scripts/fastcycle/tests/lib/consumer_required.sh" \
      nice -n 10 timeout 600 bash "$d/scripts/fastcycle/tests/$T" ) >"$o" 2>&1; rc=$?
  last="$(grep -v '^[[:space:]]*$' "$o" | tail -1)"
  [ "$(grep -c '^NOT ok' "$o")" = 0 ] || { echo "rc $rc; NOT ok lines: $(grep -m2 '^NOT ok' "$o" | cut -c1-160 | tr '\n' ';')"; return 1; }
  [ "$rc" = 77 ] || { echo "rc $rc (want 77); last line [$last]"; return 1; }
  grep -q '^SKIP: L29 .*reason=topology_unsupported$' "$o" || { echo "no SKIP: L29 line"; return 1; }
  grep -Eq '^SUMMARY: [0-9]+ pass / 0 fail / 1 skip \(skipped: L29\)$' "$o" || { echo "SUMMARY does not count the skip: [$(grep '^SUMMARY' "$o")]"; return 1; }
  grep -q '^note: FC_L29_CANDIDATES override in effect: \[zz_ZZ.UTF-8\]' "$o" || { echo "no override note"; return 1; }
  echo "rc 77, $(grep '^SUMMARY' "$o")"; return 0
}

r=$(judge "$W/base/constitution") && ok "control: unmutated copy under a simulated no-locale host: $r" || notok "control (blind): $r"

mut() { # $1 name $2 old $3 new (exactly once in the copy of the helper test)
  local d="$W/m_$1/constitution"
  mkdir -p "$d" && mkcopy "$d" || { notok "mutant $1: copy failed (blind)"; return; }
  python3 -I - "$d/scripts/fastcycle/tests/$T" "$2" "$3" <<'PY' || { notok "mutant $1: edit did not apply (blind)"; return; }
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, "pattern count %d" % s.count(old)
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if r=$(judge "$d"); then notok "mutant $1 SURVIVED ($r)"; else ok "mutant $1 killed ($r)"; fi
  safe_rm_rf "${W:?}/m_$1"
}
mut RV-E_skip_counted_as_pass 'SKIP*) echo "$1"; skipped L29 ;;' 'SKIP*) ok "$1" ;;'
mut RV-F_skip_line_dropped    'SKIP*) echo "$1"; skipped L29 ;;' 'SKIP*) : ;;'
mut M3_exit_ignores_skip      'if [ "$S" -gt 0 ]; then   # CON-222' 'if false; then   # CON-222'
mut M4_no_override_note       'if [ "${FC_L29_CANDIDATES+set}" = set ]; then echo' 'if false; then echo'

echo "=== consumer_required helper L29 skip r1 (CON-222, CON-223): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
