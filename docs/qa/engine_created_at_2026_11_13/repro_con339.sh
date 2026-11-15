#!/bin/bash
# docs/qa/engine_created_at_2026_11_13/repro_con339.sh -- reproduction of CON-339 (the workable-items
# engine rewrites items.created_at) on a SCRATCH COPY of a workable-items database. Every write goes
# through the engine binary given as the first argument; the tracked database is never touched.
#
# Usage: repro_con339.sh <engine binary> <db copy> <open item id> <control item id> <evidence file>
#   <open item id>     an item open in Issues; leg C1 closes it (Obsolete, valid for every Type)
#   <control item id>  another open item; leg C0 changes its title in place (a write that keeps the row)
#   <evidence file>    a non-empty file the engine accepts as closure evidence (resolved from $PWD)
# Legs:
#   N   control needles: the instrument reads a known created_at (positive) and finds no row for an
#       id that cannot exist (negative); a needle that fails makes the run BLIND (exit 3)
#   C0  in-place control: `update --title` must leave created_at unchanged (the instrument can see
#       "unchanged" as unchanged; without it a preserved value proves nothing)
#   C1  `close`: created_at before and after
#   S1  `sync db-to-md` then `sync md-to-db` of the same documents: how many rows change created_at
# Exit: 0 every leg preserved created_at; 1 at least one leg rewrote it (RED); 2 usage;
#       3 precondition failed or a control needle failed (BLIND).
# Evidence class: gate-logic (section 11.4.289): host runs of the real engine binary on a real
# SQLite copy; no mocks.
set -u
[ $# -eq 5 ] || { echo 'usage: repro_con339.sh <wi> <db copy> <open id> <control id> <evidence file>' >&2; exit 2; }
WI=${1:?}; DB=${2:?}; OPEN=${3:?}; CTRL=${4:?}; EV=${5:?}
[ -x "$WI" ] || { echo "precondition: engine binary not executable: $WI" >&2; exit 3; }
[ -f "$DB" ] && [ -w "$DB" ] || { echo "precondition: db copy not found or not writable: $DB" >&2; exit 3; }
[ -s "$EV" ] || { echo "precondition: evidence file missing or empty: $EV" >&2; exit 3; }
[ "$OPEN" != "$CTRL" ] || { echo "precondition: <open item id> and <control item id> must differ" >&2; exit 3; }
q(){ python3 -I -c 'import sqlite3,sys
r=sqlite3.connect(sys.argv[1]).execute(sys.argv[2],sys.argv[3:]).fetchall()
print("\n".join("|".join(str(x) for x in row) for row in r))' "$DB" "$@"; }
sha(){ sha256sum "$DB" | cut -c1-64; }
TMPD=$(mktemp -d) || exit 3
trap 'rm -rf "${TMPD:?}"' EXIT
rc_all=0

echo "engine: $(sha256sum "$WI" | cut -c1-64)"
echo "db sha256 at start: $(sha)"
echo "== N control needles"
pos=$(q "select created_at from items where atm_id=? and current_location='Issues'" "$OPEN")
neg=$(q "select created_at from items where atm_id=?" "NOSUCH-999999999")
echo "  positive (created_at of the open item): '${pos}'"
echo "  negative (an id that cannot exist): '${neg}'"
case "$pos" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) : ;;
  *) echo "BLIND: the positive needle did not read a stored timestamp" >&2; exit 3 ;;
esac
[ -z "$neg" ] || { echo "BLIND: the negative needle found a row" >&2; exit 3; }

echo "== C0 in-place control: update --title keeps the row"
c0_before=$(q "select created_at from items where atm_id=? and current_location='Issues'" "$CTRL")
"$WI" update --db "$DB" --id "$CTRL" --title "$(q "select title from items where atm_id=? and current_location='Issues'" "$CTRL") (repro C0)" >"$TMPD/c0.out" 2>&1
c0_rc=$?
c0_after=$(q "select created_at from items where atm_id=? and current_location='Issues'" "$CTRL")
echo "  rc=$c0_rc created_at before='$c0_before' after='$c0_after'"
if [ "$c0_rc" -ne 0 ] || [ -z "$c0_before" ] || [ "$c0_before" != "$c0_after" ]; then
  sed 's/^/  | /' "$TMPD/c0.out"
  echo "BLIND: the in-place control did not keep created_at, so a kept value proves nothing" >&2
  exit 3
fi

echo "== C1 close"
c1_before=$pos
"$WI" close "$OPEN" --db "$DB" --status obsolete --evidence "$EV" >"$TMPD/c1.out" 2>&1
c1_rc=$?
sed 's/^/  | /' "$TMPD/c1.out"
c1_after=$(q "select created_at from items where atm_id=? and current_location='Fixed'" "$OPEN")
lm_after=$(q "select last_modified from items where atm_id=? and current_location='Fixed'" "$OPEN")
echo "  rc=$c1_rc created_at before='$c1_before' after='$c1_after' (last_modified after='$lm_after')"
if [ "$c1_rc" -ne 0 ] || [ -z "$c1_after" ]; then
  echo "BLIND: close did not run or the closed row is missing" >&2; exit 3
fi
if [ "$c1_before" = "$c1_after" ]; then echo "  C1 VERDICT preserved"; else echo "  C1 VERDICT REWRITTEN"; rc_all=1; fi

echo "== S1 sync db-to-md then md-to-db (same documents)"
q "select atm_id||'@'||current_location||'@'||representation, created_at from items order by 1" >"$TMPD/s1_before.txt"
"$WI" sync db-to-md --db "$DB" --out-issues "$TMPD/Issues.md" --out-fixed "$TMPD/Fixed.md" >"$TMPD/s1a.out" 2>&1
s1a_rc=$?
"$WI" sync md-to-db --db "$DB" --issues "$TMPD/Issues.md" --fixed "$TMPD/Fixed.md" >"$TMPD/s1b.out" 2>&1
s1b_rc=$?
q "select atm_id||'@'||current_location||'@'||representation, created_at from items order by 1" >"$TMPD/s1_after.txt"
sed 's/^/  | /' "$TMPD/s1b.out"
python3 -I -c '
import sys
a=dict(l.rstrip("\n").split("|",1) for l in open(sys.argv[1]) if l.strip())
b=dict(l.rstrip("\n").split("|",1) for l in open(sys.argv[2]) if l.strip())
same=[k for k in a if k in b and a[k]==b[k]]
chg=[k for k in a if k in b and a[k]!=b[k]]
print("  rows before %d, after %d, common %d, created_at unchanged %d, changed %d" % (len(a),len(b),len(set(a)&set(b)),len(same),len(chg)))
for k in sorted(chg)[:3]: print("  e.g. %s: %s -> %s" % (k,a[k],b[k]))
sys.exit(1 if chg else 0)' "$TMPD/s1_before.txt" "$TMPD/s1_after.txt"
s1_rc=$?
echo "  db-to-md rc=$s1a_rc md-to-db rc=$s1b_rc"
[ "$s1a_rc" -eq 0 ] && [ "$s1b_rc" -eq 0 ] || { echo "BLIND: the sync legs did not run" >&2; exit 3; }
if [ "$s1_rc" -eq 0 ]; then echo "  S1 VERDICT preserved"; else echo "  S1 VERDICT REWRITTEN"; rc_all=1; fi

echo "db sha256 at end: $(sha)"
if [ "$rc_all" -eq 0 ]; then echo "RESULT: created_at preserved by every leg"; else echo "RESULT: created_at REWRITTEN (CON-339 reproduced)"; fi
exit "$rc_all"
