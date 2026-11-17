#!/bin/bash
# engine fail-open reproduction (M4, M5, I9) on a scratch copy of the vehicle DB.
# Usage: engine_repro.sh <engine binary> <db copy>. Prints <wi> and <db> for the two paths.
set -u
WI=${1:?engine binary}; DB=${2:?db copy}
q(){ python3 -I -c 'import sqlite3,sys; print("|".join(str(x) for x in (sqlite3.connect(sys.argv[1]).execute(sys.argv[2]).fetchone() or ())))' "$DB" "$1"; }
run(){ local shown=""; for a in "$@"; do [ "$a" = "$WI" ] && a="<wi>"; [ "$a" = "$DB" ] && a="<db>"; shown="$shown '$a'"; done
  printf '$%s\n' "$shown"; "$@" >"$DB.out" 2>&1; rc=$?; sed 's/^/  | /' "$DB.out"; printf '  rc=%s\n' "$rc"; }
echo "== M4: update --status with values outside the closed set"
for st in Done Bogus; do
  run "$WI" update --db "$DB" --id CON-306 --status "$st"
  printf '  status after: %s\n' "$(q "select status from items where atm_id='CON-306'")"
done
echo "== M5: add with a type outside the closed set"
run "$WI" add Story Low --db "$DB" --title "repro type probe" --description "a probe item for the type closed set check only" --created-by Conductor
printf '  newest item: %s\n' "$(q "select atm_id, type, created_by from items order by rowid desc limit 1")"
echo "== I9: history attribution of the add above"
printf '  history Opened row (atm_id|by): %s\n' "$(q "select atm_id, by from item_history where event_type='Opened' order by id desc limit 1")"
echo "== control: a closed-set value is accepted and changes the row"
run "$WI" update --db "$DB" --id CON-306 --status "In progress"
printf '  status after: %s\n' "$(q "select status from items where atm_id='CON-306'")"
