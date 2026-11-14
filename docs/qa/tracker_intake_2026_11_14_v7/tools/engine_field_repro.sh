#!/usr/bin/env bash
# docs/qa/tracker_intake_2026_11_14_v7/tools/engine_field_repro.sh -- reproduce, on a scratch copy of a
# workable-items database, whether a field-only `update` of the engine leaves the body line of that field
# stale (owed item 2 of the round-5 review, and its sibling flags, UNCONFIRMED there).
#
# usage: engine_field_repro.sh ENGINE SOURCE_DB WORKDIR
#   ENGINE     the workable-items binary
#   SOURCE_DB  a database to copy (it is only read; the copy is written)
#   WORKDIR    an empty scratch directory; the copy and nothing else is written there
# For each of --severity, --type, --created-by and --assigned-to the script adds one item (`add Task
# Medium`, created by probe-opener, assigned to probe-owner, so every field has a body line to drift), runs a field-only update of that one flag, and prints the column value and the body line that names it.
# A line reads STALE when the body still shows the old value, SYNCED when it shows the new one, and
# ABSENT when the body has no line for that field (a probe defect here, since every field is set at add).
# Exit: 0 the probe ran (whatever it found); 2 usage; 3 a control needle failed (the column did not take
# the new value, so the probe could not see the body either way).
# Evidence class: gate-logic only (section 11.4.289): a scratch copy and the real engine binary.
set -u
eng=${1:?usage: engine_field_repro.sh ENGINE SOURCE_DB WORKDIR}
src=${2:?usage: engine_field_repro.sh ENGINE SOURCE_DB WORKDIR}
wd=${3:?usage: engine_field_repro.sh ENGINE SOURCE_DB WORKDIR}
[ -d "$wd" ] && [ -z "$(ls -A "$wd")" ] || { echo "WORKDIR must be an empty directory" >&2; exit 2; }
db="$wd/probe.db"
cp -- "$src" "$db" || exit 2
q() { # q <sql>: one query on the copy, read-only, through python3 (sqlite3 is not on every PATH)
  python3 -I -c 'import sqlite3, sys, urllib.parse
c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(sys.argv[1]), uri=True)
for r in c.execute(sys.argv[2]): print("|".join("" if v is None else str(v) for v in r))' "$db" "$1"; }
echo "engine sha256: $(sha256sum "$eng" | cut -d' ' -f1)"
echo "source sha256: $(sha256sum "$src" | cut -d' ' -f1)"
probe() { # probe <flag> <column> <body label> <new value>
  local flag=$1 col=$2 label=$3 new=$4 id old line got
  out=$("$eng" add Task Medium --db "$db" --prefix CON --created-by probe-opener --assigned-to probe-owner --title "engine field probe $flag" \
        --description "A scratch probe item for the field-only update of $flag; never landed." 2>&1) || { echo "$out"; exit 3; }
  id=$(printf '%s\n' "$out" | grep -o 'CON-[0-9][0-9]*' | head -1)
  [ -n "$id" ] || { echo "no id in: $out"; exit 3; }
  old=$(q "select $col from items where atm_id='$id'")
  "$eng" update --db "$db" --id "$id" --location Issues "--$flag=$new" >/dev/null 2>&1 || { echo "update --$flag refused"; exit 3; }
  got=$(q "select $col from items where atm_id='$id'")
  [ "$got" = "$new" ] || { echo "control needle FAILED: column $col reads '$got', want '$new'"; exit 3; }
  line=$(q "select body_md from items where atm_id='$id'" | grep -m1 -F "**$label:**")
  if [ -z "$line" ]; then v=ABSENT
  elif printf '%s' "$line" | grep -qF -- "$new"; then v=SYNCED
  elif printf '%s' "$line" | grep -qF -- "$old"; then v=STALE
  else v="OTHER"; fi
  printf '%s %s: column %s -> %s; body line: %s\n' "$v" "--$flag" "${old:-<empty>}" "$got" "${line:-<none>}"
}
probe severity severity Severity High
probe type type Type Bug
probe created-by created_by Created-By probe-author
probe assigned-to assigned_to Assigned-To probe-assignee
