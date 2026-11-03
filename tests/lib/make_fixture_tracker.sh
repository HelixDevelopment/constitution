#!/usr/bin/env bash
# make_fixture_tracker.sh -- build a REAL workable-items tracker (SQLite) in a
# FIXTURE consumer project, for tests that need docs/workable_items.db
# (fastcycle select_sample S5/S6, reopen_rate control needle #2).
#
# Documentation (§11.4.18)
#   Purpose : the canon checkout ships no tracker DB, so the fastcycle tests
#             that read <ROOT>/docs/workable_items.db could not be genuinely
#             exercised. This helper makes a consumer-shaped fixture project
#             whose DB is created by the REAL engine (scripts/workable-items,
#             built with `go build`) -- no mocks (§11.4.289). Only the
#             history timestamps are then set with sqlite3 so the scenario is
#             deterministic (the engine stamps "today"); the engine's own
#             `validate` must still accept the DB (the helper fails otherwise).
#   Usage   : tests/lib/make_fixture_tracker.sh [FIXTURE_DIR]
#             FIXTURE_DIR must not exist or be empty; default is a fresh
#             mktemp -d (under $TMPDIR). Caller removes it (use
#             ${VAR:?}-guarded rm).
#   Output  : stdout = exactly one line, the absolute DB path
#             (<FIXTURE_DIR>/docs/workable_items.db). Evidence on stderr.
#   Layout  : <FIXTURE_DIR>/constitution -> symlink to this checkout (the
#             consumer layout the fastcycle tests resolve: ROOT/constitution/
#             scripts/fastcycle); <FIXTURE_DIR>/docs/workable_items.db;
#             <FIXTURE_DIR>/bin/workable-items (built engine);
#             <FIXTURE_DIR>/evidence/<id>/ev.log (closure evidence).
#   Seed    : 17 items (ATM-601..607, 700, 951..958, 960): Bug/Task/Feature closed
#             via `workable-items close`, retroactive-registration rows,
#             a Reopened row and a post-2026-08-23 closure (ATM-960).
#   Exit    : 0 ok; 2 prerequisite missing (go, sqlite3); 3 engine failure.
#   Run the tests against it:
#     bash <FIXTURE_DIR>/constitution/scripts/fastcycle/tests/<test>.sh
#     (invoke THROUGH the symlink so the test's ROOT is the fixture).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
command -v go >/dev/null 2>&1 || { echo "make_fixture_tracker: go missing" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || { echo "make_fixture_tracker: sqlite3 missing" >&2; exit 2; }
FIX="${1:-}"
if [ -z "$FIX" ]; then FIX="$(mktemp -d)"; fi
if [ -e "$FIX" ] && [ -n "$(ls -A "$FIX" 2>/dev/null)" ]; then
  echo "make_fixture_tracker: $FIX is not empty" >&2; exit 2
fi
mkdir -p "$FIX/docs" "$FIX/bin" "$FIX/evidence" || exit 2
FIX="$(cd "$FIX" && pwd)"
ln -s "$REPO" "$FIX/constitution" || exit 2
WI="$FIX/bin/workable-items"
DB="$FIX/docs/workable_items.db"
( cd "$REPO/scripts/workable-items" && nice -n 15 go build -o "$WI" ./cmd/workable-items ) >&2 || { echo "make_fixture_tracker: go build failed" >&2; exit 3; }

# id|type|closure_date|retro(1 = Opened->closure gap 10s, else 3 days)
SEED='ATM-951|Bug|2026-08-20|1
ATM-952|Bug|2026-08-19|1
ATM-953|Bug|2026-07-28|0
ATM-954|Bug|2026-08-10|0
ATM-955|Bug|2026-08-05|0
ATM-956|Bug|2026-07-20|0
ATM-957|Bug|2026-07-10|0
ATM-958|Bug|2026-06-30|0
ATM-603|Task|2026-07-20|0
ATM-602|Task|2026-07-15|0
ATM-601|Task|2026-07-10|0
ATM-604|Task|2026-06-20|0
ATM-605|Task|2026-06-10|0
ATM-606|Task|2026-06-05|0
ATM-607|Task|2026-08-01|1
ATM-700|Feature|2026-07-05|0
ATM-960|Task|2026-08-25|0'
while IFS='|' read -r id typ cdate retro; do
  "$WI" add "$typ" medium --db "$DB" --id "$id" --title "fixture $id" \
    --description "fixture item $id for fastcycle real-db tests (seeded)" >/dev/null || { echo "add $id failed" >&2; exit 3; }
  mkdir -p "$FIX/evidence/$id"; echo "evidence $id" > "$FIX/evidence/$id/ev.log"
  case "$typ" in Bug) st=fixed;; Task) st=completed;; *) st=implemented;; esac
  "$WI" close "$id" --db "$DB" --status "$st" --evidence "$FIX/evidence/$id/ev.log" >/dev/null 2>"$FIX/close.err" \
    || { echo "close $id failed: $(tail -2 "$FIX/close.err")" >&2; exit 3; }
  if [ "$retro" = 1 ]; then oc="$cdate 11:59:50"; else oc="$cdate 12:00:00"; fi
  if [ "$retro" != 1 ]; then oc="$(date -u -d "$cdate 12:00:00 -3 days" '+%Y-%m-%d %H:%M:%S')"; fi
  sqlite3 "$DB" "UPDATE item_history SET on_date='$cdate', created_at='$cdate 12:00:00' WHERE atm_id='$id' AND event_type IN ('Fixed','Implemented','Completed');
                 UPDATE item_history SET on_date=substr('$oc',1,10), created_at='$oc' WHERE atm_id='$id' AND event_type='Opened';" || exit 3
done <<<"$SEED"
# a Reopened row inside the window
sqlite3 "$DB" "INSERT INTO item_history(atm_id,event_type,by,on_date,reason,created_at) VALUES('ATM-954','Reopened','AI','2026-08-12','fixture reopen','2026-08-12 09:00:00');" || exit 3
if ! "$WI" validate --db "$DB" >&2; then echo "make_fixture_tracker: engine validate rejects the seeded DB" >&2; exit 3; fi
echo "make_fixture_tracker: items=$(sqlite3 "$DB" 'select count(*) from items') history=$(sqlite3 "$DB" 'select count(*) from item_history') ids=$(sqlite3 "$DB" "select group_concat(atm_id,',') from items")" >&2
echo "$DB"
