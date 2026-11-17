#!/bin/bash
# docs/qa/tracker_intake_2026_11_12_v5/engine_repro.sh -- reproduction of the engine gaps filed by the
# tracker intake (the fail-open and attribution probes F1-F3 of the v2 script, and the G1-G4 probes of
# the v3 script), on a SCRATCH COPY of a workable-items database. Every write goes through the engine;
# the copy is changed, the tracked database is never touched.
#
# Usage: HELIX_RELEASE_PREFIX=<prefix> engine_repro.sh <engine binary> <db copy> <open item id> \
#             <obsolete item id> <probe item id>
#   <open item id>      an open item of Type Task, closed by the G1 probe (`close --status completed` is the
#                       Task closure; a Bug refuses it, section 11.4.33, and G1 would not run)
#   <obsolete item id>  an Obsolete item of the copy with an obsolete_details row (G2..G4; G4 runs while
#                       it is still Obsolete and restores the superseding id after the probe)
#   <probe item id>     an open item of Type Task other than <open item id>, used by F1 and F4 (the engine
#                       prints the Type in every update line, so another Type changes the output)
#   HELIX_RELEASE_PREFIX  must equal the prefix of the three ids: the engine mints the F2 item's id from
#                       it (unset, the prefix comes from the directory name and the output differs)
# These preconditions are checked; a failed one exits 3 and names it (round-4 review R4-8: the recorded
# red commands carry them, so a re-run reproduces the evidence exactly).
# The ids are arguments and the output prints them as <open>, <obsolete>, <probe>, <superseding>,
# <absent>, <added>; any other id of the copy prints as <other id>. A re-mint therefore never makes the
# script act on a different item, and the captured output carries no tracker id (round-3 review M-9).
# Run from the repository root (the engine resolves --evidence / --incident paths from there).
# Exit: 0 the probes ran (the printed values are the evidence); 2 usage; 3 a precondition failed.
# Evidence class: gate-logic only (section 11.4.289): host-fixture runs of the engine binary.
set -u
usage='usage: HELIX_RELEASE_PREFIX=<prefix> engine_repro.sh <wi> <db copy> <open id> <obsolete id> <probe id>'
[ $# -eq 5 ] || { echo "$usage" >&2; exit 2; }
WI=${1:?}; DB=${2:?}; OPEN=${3:?}; OBS=${4:?}; PROBE=${5:?}
EV=docs/qa/tracker_intake_2026_11_12_v5/engine_repro.sh
[ -f "$EV" ] || { echo "precondition: run from the repository root ($EV not found)" >&2; exit 3; }
[ -x "$WI" ] || { echo "precondition: engine binary not executable" >&2; exit 3; }
[ -f "$DB" ] && [ -w "$DB" ] || { echo "precondition: db copy not found or not writable" >&2; exit 3; }
[ "$OPEN" != "$PROBE" ] || { echo "precondition: <open item id> and <probe item id> must differ" >&2; exit 3; }
PFX=${OPEN%-*}
[ "${HELIX_RELEASE_PREFIX:-}" = "$PFX" ] || { echo "precondition: HELIX_RELEASE_PREFIX must be set to $PFX, the prefix of the ids (the engine mints the F2 item's id from it)" >&2; exit 3; }
q(){ python3 -I -c 'import sqlite3,sys; r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2],sys.argv[3:]).fetchone(); print("|".join(str(x) for x in (r or ())))' "$DB" "$@"; }
SUP=$(q "select superseding_item from obsolete_details where atm_id=?" "$OBS")
NOID=$(python3 -I -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); p=sys.argv[2]; n=max(int(i.rsplit("-",1)[1]) for (i,) in c.execute("select atm_id from items") if i.startswith(p+"-")); print("%s-%03d"%(p,n+500))' "$DB" "$PFX")
ADDED=""
# every id is printed as a placeholder: the known ones by role, any other one as <other id>
sub(){ python3 -I -c '
import re,sys
p,m=sys.argv[1],{}
for k,v in zip(sys.argv[2::2],sys.argv[3::2]): m.setdefault(k,v)  # the first role wins
rx=re.compile(r"(?<![\w-])"+re.escape(p)+r"-\d+\b")
for line in sys.stdin: sys.stdout.write(rx.sub(lambda k: m.get(k.group(0),"<other id>"),line))
' "$PFX" "$OPEN" "<open>" "$OBS" "<obsolete>" "$PROBE" "<probe>" "${SUP:-none}" "<superseding>" "$NOID" "<absent>" "${ADDED:-none}" "<added>"; }
hdr(){ python3 -I -c 'import sqlite3,sys,re; b=sqlite3.connect(sys.argv[1]).execute("select body_md from items where atm_id=? order by current_location limit 1",(sys.argv[2],)).fetchone()[0] or ""; print(",".join(re.findall(r"(?m)^\*\*([A-Za-z-]+):\*\*",b.split("\n\n",2)[1] if b.count("\n\n")>=2 else "")))' "$DB" "$1"; }
run(){ local shown="" a rc; for a in "$@"; do [ "$a" = "$WI" ] && a="<wi>"; [ "$a" = "$DB" ] && a="<db>"; [ ${#a} -gt 80 ] && a="<${#a} chars>"; shown="$shown '$a'"; done
  printf '$%s\n' "$shown" | sub; "$@" >"$DB.out" 2>&1; rc=$?; sed 's/^/  | /' "$DB.out" | sub; printf '  rc=%s\n' "$rc"; }
say(){ printf '%s\n' "$*" | sub; }
[ "$(q "select current_location from items where atm_id=? and current_location='Issues'" "$OPEN")" = "Issues" ] || { echo "precondition: <open item id> is not open in the copy" >&2; exit 3; }
[ "$(q "select current_location from items where atm_id=? and current_location='Issues'" "$PROBE")" = "Issues" ] || { echo "precondition: <probe item id> is not open in the copy" >&2; exit 3; }
[ -n "$SUP" ] || { echo "precondition: <obsolete item id> has no obsolete_details row" >&2; exit 3; }
for r in OPEN PROBE; do
  [ "$(q "select type from items where atm_id=?" "${!r}")" = Task ] || { echo "precondition: <$(echo "$r" | tr 'A-Z' 'a-z') item id> must be of Type Task (got $(q "select type from items where atm_id=?" "${!r}"))" >&2; exit 3; }
done
case "$(q "select status from items where atm_id=?" "$OBS")" in Obsolete*) ;; *) echo "precondition: <obsolete item id> is not Obsolete in the copy" >&2; exit 3 ;; esac
echo "== preconditions: HELIX_RELEASE_PREFIX=$PFX; <open> and <probe> are open items of Type Task; <obsolete> is Obsolete with an obsolete_details row"

echo "== F1 (review M4): update --status with values outside the closed set"
for st in Done Bogus; do
  run "$WI" update --db "$DB" --id "$PROBE" --status "$st"
  say "  status after: $(q "select status from items where atm_id=?" "$PROBE")"
done
echo "== F2 (review M5): add with a type outside the closed set"
before=$(q "select count(*) from items")
ids_before=$(q "select group_concat(atm_id, ' ') from items")
run "$WI" add Story Low --db "$DB" --title "repro type probe" --description "a probe item for the type closed set check only" --created-by Conductor
ADDED=$(python3 -I -c 'import sqlite3,sys; old=set(sys.argv[2].split()); new=sorted({i for (i,) in sqlite3.connect(sys.argv[1]).execute("select atm_id from items")}-old); print(new[0] if len(new)==1 else "")' "$DB" "$ids_before")
say "  items before: $before; after: $(q "select count(*) from items")"
if [ -n "$ADDED" ]; then say "  added item (id|type|created_by): $(q "select atm_id, type, created_by from items where atm_id=?" "$ADDED")"; else say "  no new item was added"; fi
echo "== F3 (review I9): history attribution of the add above"
say "  history Opened row (atm_id|by): $(q "select atm_id, by from item_history where event_type='Opened' and atm_id=? order by id desc limit 1" "${ADDED:-none}")"
echo "== F4 control: a closed-set value is accepted and changes the row"
run "$WI" update --db "$DB" --id "$PROBE" --status "In progress"
say "  status after: $(q "select status from items where atm_id=?" "$PROBE")"

echo "== G1 (review R2-9): close rewrites created_at"
ca0=$(q "select created_at from items where atm_id=?" "$OPEN")
say "  created_at before: $ca0"
run "$WI" close "$OPEN" --db "$DB" --status completed --evidence "$EV"
ca1=$(q "select created_at from items where atm_id=? order by current_location limit 1" "$OPEN")
say "  created_at after:  $ca1"
if [ "$ca0" = "$ca1" ]; then say "  created_at changed by close: no"; else say "  created_at changed by close: yes"; fi
echo "== G4 (review R2-6 D7a): obsolete-details and validate accept a superseding id that does not exist"
say "  $NOID exists: $(q "select count(*) from items where atm_id=?" "$NOID")"
run "$WI" obsolete-details "$OBS" --db "$DB" --since 2026-11-13 --reason duplicate-of --superseding "$NOID" --evidence "$EV"
say "  obsolete_details now: $(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
run "$WI" validate --db "$DB"
say "  (restore the superseding id $SUP for the later probes)"
run "$WI" obsolete-details "$OBS" --db "$DB" --since 2026-11-13 --reason duplicate-of --superseding "$SUP" --evidence "$EV"
echo "== G2 (review R2-9): reopen leaves the obsolete_details row"
say "  status before: $(q "select status from items where atm_id=?" "$OBS"); obsolete_details: $(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
run "$WI" reopen --db "$DB" --id "$OBS" --why design-reconsidered --who AI --when 2026-11-13 --incident "$EV"
say "  status after: $(q "select status from items where atm_id=?" "$OBS"); obsolete_details: $(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
say "  body header keys after reopen: $(hdr "$OBS")"
echo "== G3: update re-renders the body header and drops the Reopened-Details line"
run "$WI" update --db "$DB" --id "$OBS" --description "$(q "select description from items where atm_id=?" "$OBS")
Probe line appended by engine_repro.sh G3."
say "  body header keys after update: $(hdr "$OBS")"
say "  reopen history rows kept: $(q "select count(*) from item_history where atm_id=? and event_type like 'Reopen%'" "$OBS")"
say "  obsolete_details on the Reopened item: $(q "select reason, superseding_item from obsolete_details where atm_id=?" "$OBS")"
run "$WI" validate --db "$DB"
rm -f "${DB:?}.out"
exit 0
