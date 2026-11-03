#!/usr/bin/env bash
# test_fastcycle_real_db.sh -- run the fastcycle tracker-DB-dependent tests
# against a REAL workable-items tracker DB (§11.4.289: real engine binary, real
# SQLite file, no mocks), and prove S5/S6/S3 and reopen_rate "control needle #2"
# are genuinely exercised (known_failures_v73.md row 11).
#
# Documentation (§11.4.18)
#   What it does : 1. tests/lib/make_fixture_tracker.sh builds the engine with
#                     go and seeds a fixture consumer project under mktemp.
#                  2. Prints DB evidence (row counts, ids ATM-953/ATM-603).
#                  3. Runs scripts/fastcycle/tests/test_select_sample_r5_regression.sh
#                     and test_reopen_rate_red.sh THROUGH the fixture's
#                     constitution symlink (their ROOT is then the fixture, so
#                     docs/workable_items.db resolves); no test file is edited.
#                  4. Asserts rc=0 AND the specific "ok" lines for S3, S5, S6
#                     and control needle #2 (a SKIP/absence is not a pass).
#                  5. Paired mutations: (M1) the DB emptied of rows, (M2) the DB
#                     replaced by garbage bytes -> the suites MUST then FAIL
#                     and S5/S6 must report NOT ok.
#   Usage        : bash tests/gates/test_fastcycle_real_db.sh
#   Exit         : 0 all assertions held; 1 any failed; 2 prerequisite missing
#                  (go, sqlite3 -- honest SKIP, never a pass).
#   Duration     : a few minutes (the select_sample suite runs its own mutations).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
command -v go >/dev/null 2>&1 && command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: go or sqlite3 missing (not a pass)"; exit 2; }
fail=0
ok()  { echo "ok   $*"; }
bad() { echo "NOT ok $*"; fail=1; }
FIX="$(mktemp -d)"
cleanup() { [ -n "${FIX:-}" ] && [ -d "$FIX" ] && rm -rf "${FIX:?}"; }
trap cleanup EXIT
FX="$FIX/p"
DB="$(nice -n 15 bash "$REPO/tests/lib/make_fixture_tracker.sh" "$FX" 2>"$FIX/mk.err")" || { cat "$FIX/mk.err"; bad "fixture build failed"; exit 1; }
[ "$DB" = "$FX/docs/workable_items.db" ] && [ -s "$DB" ] || { bad "helper printed unexpected DB path: $DB"; exit 1; }
nitems=$(sqlite3 "$DB" 'select count(*) from items'); nhist=$(sqlite3 "$DB" 'select count(*) from item_history')
echo "EVIDENCE db=$DB items=$nitems item_history=$nhist"
echo "EVIDENCE ATM-953: $(sqlite3 "$DB" "select i.type,i.status,h.event_type,h.on_date from items i join item_history h using(atm_id) where atm_id='ATM-953' and h.event_type='Fixed'")"
echo "EVIDENCE ATM-603: $(sqlite3 "$DB" "select i.type,i.status,h.event_type,h.on_date from items i join item_history h using(atm_id) where atm_id='ATM-603' and h.event_type='Completed'")"
echo "EVIDENCE rows after 2026-08-23: $(sqlite3 "$DB" "select count(*) from item_history where on_date>'2026-08-23'")  engine: $("$FX/bin/workable-items" validate --db "$DB" 2>&1 | tail -1)"
[ "$nitems" -ge 15 ] && [ "$nhist" -ge 30 ] && ok "fixture DB is populated by the real engine (items=$nitems history=$nhist)" || bad "fixture DB too small"

T="$FX/constitution/scripts/fastcycle/tests"
run_suites() { # $1 = fixture root, $2 = out prefix
  nice -n 15 bash "$1/constitution/scripts/fastcycle/tests/test_select_sample_r5_regression.sh" >"$2.ss" 2>&1; echo $? >"$2.ss.rc"
  nice -n 15 bash "$1/constitution/scripts/fastcycle/tests/test_reopen_rate_red.sh" >"$2.rr" 2>&1; echo $? >"$2.rr.rc"
}
echo "=== real DB: run both suites ==="
run_suites "$FX" "$FIX/real"
[ "$(cat "$FIX/real.ss.rc")" = 0 ] && ok "select_sample suite rc=0 ($(grep -c '^ok' "$FIX/real.ss") ok lines, $(grep -c '^NOT ok' "$FIX/real.ss") NOT ok)" || bad "select_sample suite rc=$(cat "$FIX/real.ss.rc")"
[ "$(cat "$FIX/real.rr.rc")" = 0 ] && ok "reopen_rate suite rc=0" || bad "reopen_rate suite rc=$(cat "$FIX/real.rr.rc")"
for pat in '^ok S3 live experiment: deleted [1-9][0-9]* future rows' '^ok S5 live as-of 2026-08-23: usable taken/available' '^ok S6 as-of 07-20 derives the needle' ; do
  l="$(grep -E "$pat" "$FIX/real.ss" | head -1)"; [ -n "$l" ] && ok "genuinely exercised: ${l#ok }" || bad "missing line /$pat/"
done
l="$(grep -E '^ok control needle #2' "$FIX/real.rr" | head -1)"; [ -n "$l" ] && ok "genuinely exercised: ${l#ok }" || bad "reopen_rate needle#2 line missing"
grep -q 'SKIPPED' "$FIX/real.rr" && bad "reopen_rate reports a SKIPPED needle" || ok "no SKIPPED needle in reopen_rate output"

mutate() { # $1 name, $2 sql-or-garbage mode
  local M="$FIX/m_$1"; mkdir -p "$M/docs" && ln -s "$REPO" "$M/constitution" && cp "$DB" "$M/docs/workable_items.db" || { bad "mutation $1 setup"; return; }
  case "$2" in
    empty)   sqlite3 "$M/docs/workable_items.db" "DELETE FROM item_history; DELETE FROM items;" ;;
    garbage) head -c 4096 /dev/urandom >"$M/docs/workable_items.db" ;;
  esac
  run_suites "$M" "$FIX/mut_$1"
  local rc="$(cat "$FIX/mut_$1.ss.rc")"
  if [ "$rc" != 0 ] && grep -qE '^NOT ok S5' "$FIX/mut_$1.ss" && grep -qE '^NOT ok S6|^NOT ok S3' "$FIX/mut_$1.ss"; then
    ok "mutation $1 killed: select_sample rc=$rc, S5 and S6/S3 report NOT ok"
  else bad "mutation $1 SURVIVED (rc=$rc) -- the test does not depend on the real DB"; fi
  if [ "$1" = garbage ]; then
    [ "$(cat "$FIX/mut_$1.rr.rc")" != 0 ] && grep -q '^NOT ok control needle #2' "$FIX/mut_$1.rr" && ok "mutation $1 killed: reopen_rate needle #2 NOT ok" || bad "mutation $1 SURVIVED in reopen_rate needle #2"
  fi
}
echo "=== paired mutations ==="
mutate empty empty
mutate garbage garbage
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit "$fail"
