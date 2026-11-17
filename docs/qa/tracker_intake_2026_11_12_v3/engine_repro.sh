#!/bin/bash
# docs/qa/tracker_intake_2026_11_12_v3/engine_repro.sh -- reproduction of four pre-existing engine gaps
# (round-2 review findings R2-9 and R2-6/D7a, and a re-render effect seen while fixing R2-1), on a
# SCRATCH COPY of a workable-items database. Every write goes through the engine; the copy is
# changed, the tracked database is never touched.
#
# Usage: engine_repro.sh <engine binary> <db copy> <open item id> <obsolete item id>
#   <open item id>      an open item of the copy (Issues), used for the close probe (G1)
#   <obsolete item id>  an item of the copy that is Obsolete with an obsolete_details row (G2..G4; G4 runs while it is still Obsolete and restores the superseding id after the probe)
# The ids are arguments, so a re-mint never makes the script act on a different item silently.
# Run from the repository root (the engine resolves --evidence / --incident paths from there).
# Exit: 0 the probes ran (the printed values are the evidence); 2 usage; 3 a precondition failed.
# Evidence class: gate-logic only (section 11.4.289): host-fixture runs of the engine binary.
set -u
WI=${1:?usage: engine_repro.sh <wi> <db copy> <open id> <obsolete id>}
DB=${2:?db copy}
OPEN=${3:?open item id}
OBS=${4:?obsolete item id}
EV=docs/qa/tracker_intake_2026_11_12_v3/README.md
[ -f "$EV" ] || { echo "precondition: run from the repository root ($EV not found)" >&2; exit 3; }
q(){ python3 -I -c 'import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2],sys.argv[3:]).fetchone(); print("|".join(str(x) for x in (r or ())))' "$DB" "$@"; }
hdr(){ python3 -I -c 'import sqlite3,sys,re; b=sqlite3.connect(sys.argv[1]).execute("select body_md from items where atm_id=? order by current_location limit 1",(sys.argv[2],)).fetchone()[0] or ""; print(",".join(re.findall(r"(?m)^\*\*([A-Za-z-]+):\*\*",b.split("\n\n",2)[1] if b.count("\n\n")>=2 else "")))' "$DB" "$1"; }
run(){ local shown="" a; for a in "$@"; do [ "$a" = "$WI" ] && a="<wi>"; [ "$a" = "$DB" ] && a="<db>"; [ ${#a} -gt 80 ] && a="<${#a} chars>"; shown="$shown '$a'"; done
  printf '$%s\n' "$shown"; "$@" >"$DB.out" 2>&1; rc=$?; sed 's/^/  | /' "$DB.out"; printf '  rc=%s\n' "$rc"; }
[ "$(q "select current_location from items where atm_id=? and current_location='Issues'" "$OPEN")" = "Issues" ] || { echo "precondition: $OPEN is not open in the copy" >&2; exit 3; }
[ -n "$(q "select atm_id from obsolete_details where atm_id=?" "$OBS")" ] || { echo "precondition: $OBS has no obsolete_details row" >&2; exit 3; }

echo "== G1 (R2-9): close rewrites created_at"
printf '  created_at before: %s\n' "$(q "select created_at from items where atm_id=?" "$OPEN")"
run "$WI" close "$OPEN" --db "$DB" --status completed --evidence "$EV"
printf '  created_at after:  %s\n' "$(q "select created_at from items where atm_id=? order by current_location limit 1" "$OPEN")"

SUP=$(q "select superseding_item from obsolete_details where atm_id=?" "$OBS")
echo "== G4 (R2-6 D7a): obsolete-details and validate accept a superseding id that does not exist"
NOID=$(python3 -I -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); p=sys.argv[2].rsplit("-",1)[0]; n=max(int(i.rsplit("-",1)[1]) for (i,) in c.execute("select atm_id from items") if i.startswith(p+"-")); print("%s-%03d"%(p,n+500))' "$DB" "$OBS")
printf '  %s exists: %s\n' "$NOID" "$(q "select count(*) from items where atm_id=?" "$NOID")"
run "$WI" obsolete-details "$OBS" --db "$DB" --since 2026-11-13 --reason duplicate-of --superseding "$NOID" --evidence "$EV"
printf '  obsolete_details now: %s\n' "$(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
run "$WI" validate --db "$DB"
echo "  (restore the superseding id $SUP for the later probes)"
run "$WI" obsolete-details "$OBS" --db "$DB" --since 2026-11-13 --reason duplicate-of --superseding "$SUP" --evidence "$EV"
echo "== G2 (R2-9): reopen leaves the obsolete_details row"
printf '  status before: %s; obsolete_details: %s\n' "$(q "select status from items where atm_id=?" "$OBS")" "$(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
run "$WI" reopen --db "$DB" --id "$OBS" --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
printf '  status after: %s; obsolete_details: %s\n' "$(q "select status from items where atm_id=?" "$OBS")" "$(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
printf '  body header keys after reopen: %s\n' "$(hdr "$OBS")"

echo "== G3: update re-renders the body header and drops the Reopened-Details line"
run "$WI" update --db "$DB" --id "$OBS" --description "$(q "select description from items where atm_id=?" "$OBS")
Probe line appended by engine_repro.sh G3."
printf '  body header keys after update: %s\n' "$(hdr "$OBS")"
printf '  reopen history rows kept: %s\n' "$(q "select count(*) from item_history where atm_id=? and event_type like 'Reopen%'" "$OBS")"
printf '  obsolete_details on the Reopened item: %s\n' "$(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
run "$WI" validate --db "$DB"

exit 0
