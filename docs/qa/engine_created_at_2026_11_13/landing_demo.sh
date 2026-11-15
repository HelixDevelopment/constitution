#!/bin/bash
# docs/qa/engine_created_at_2026_11_13/landing_demo.sh -- STEP 5 of CON-339: what the tracker-intake landing
# oracle (remint_ids.py verify, shipped by the vehicle b48091ea) reports before and after the restore plan,
# on COPIES only. The real tracker is never opened.
#
# Legs (each on a fresh copy):
#   FF        copy of the vehicle database (a fast-forward landing): verify, then apply the plan, validate,
#             verify again (shows why verify runs BEFORE the restore on a fast-forward landing)
#   R-OLD     copy of the target, replayed with the OLD engine: verify; then the plan applied with the NEW
#             engine, validate, verify again (a landing done before this fix, repaired after it)
#   R-NEW     copy of the target, replayed with the NEW engine: verify; plan; validate; verify again
#
# Usage: landing_demo.sh <tree> <vehicle db> <base db> <target db> <ff plan.json> <replay plan.json>
#                        <old engine> <new engine> <repo>
#   <tree>  a checkout of the vehicle (contains scripts/workable-items/remint_ids.py and the closure evidence);
#           the evidence databases are extracted into it by apply_restore_plan.sh (--root <tree> --repo <repo>)
# Exit: 0 every step ran and every leg's last validate is OK; 1 a step failed; 2 usage; 3 BLIND (missing input).
set -u
[ $# -eq 9 ] || { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
TREE=${1:?}; V=${2:?}; B=${3:?}; T=${4:?}; FFP=${5:?}; RP=${6:?}; OLD=${7:?}; NEW=${8:?}; REPO=${9:?}
HERE=$(cd "$(dirname "$0")" && pwd) || exit 3
for f in "$V" "$B" "$T" "$FFP" "$RP" "$TREE/scripts/workable-items/remint_ids.py"; do
  [ -f "$f" ] || { echo "BLIND: not found: $f" >&2; exit 3; }
done
for e in "$OLD" "$NEW"; do [ -x "$e" ] || { echo "BLIND: engine not executable: $e" >&2; exit 3; }; done
W=$(mktemp -d) || exit 3
trap 'rm -rf -- "${W:?}"' EXIT
fail=0
echo "inputs:"
for f in "$V" "$B" "$T" "$OLD" "$NEW" "$TREE/scripts/workable-items/remint_ids.py" "$HERE/restore_plan.tsv"; do
  echo "  $(sha256sum "$f" | cut -c1-64)  ${f##*/}"
done
remint() { ( cd "$TREE" && python3 -I scripts/workable-items/remint_ids.py "$@" ); }
verify() { # <plan> <db> <label>
  remint verify --plan "$1" --vehicle-db "$V" --base-db "$B" --target-db "$T" --db "$2" >"$W/$3.verify" 2>&1
  local rc=$?
  echo "  verify[$3] exit=$rc $(grep '^RESULT:' "$W/$3.verify")"
  grep '^MISMATCH' "$W/$3.verify" | sed 's/^/    /'
  grep '^KNOWN' "$W/$3.verify" | grep -E 'CON-243|CON-308' | sed 's/^/    /'
  echo "    KNOWN lines by kind: own created_at=$(grep -c '^KNOWN .* created_at: replay time' "$W/$3.verify")" \
       "base created_at=$(grep -c '^KNOWN CON-[0-9]* created_at: landed' "$W/$3.verify")" \
       "lifecycle history=$(grep -c '^KNOWN .*lifecycle history rows' "$W/$3.verify")" \
       "body_md=$(grep -c '^KNOWN .*body_md not compared' "$W/$3.verify")"
}
validate() { # <db> <label>
  ( cd "$TREE" && "$NEW" validate --db "$1" ) >"$W/$2.validate" 2>&1
  local rc=$?
  echo "  validate[$2] exit=$rc $(tail -1 "$W/$2.validate")"
  return $rc
}
created() { # <db> <id>...
  local db=$1; shift
  for i in "$@"; do
    printf '    %s created_at=%s\n' "$i" \
      "$(python3 -I -c 'import sqlite3,sys; c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True); print(",".join(r[0] for r in c.execute("select created_at from items where atm_id=?",(sys.argv[2],))))' "$db" "$i")"
  done
}
plan() { # <db> <engine> <label> [--dry-run]
  local mode=--apply
  [ "${4:-}" = --dry-run ] && mode=""
  bash "$HERE/apply_restore_plan.sh" --engine "$2" --db "$1" --landing main --root "$TREE" --repo "$REPO" $mode \
    >"$W/$3.plan" 2>&1
  local rc=$?
  sed 's/^/    /' "$W/$3.plan"
  echo "  apply_restore_plan[$3] exit=$rc"
  return $rc
}

echo "===== FF (fast-forward: the landed database is a copy of the vehicle)"
cp -- "$V" "$W/ff.db" && chmod 0644 "$W/ff.db" || exit 3
created "$W/ff.db" CON-243 CON-308
verify "$FFP" "$W/ff.db" ff-before
echo "  dry run of the plan (extracts the evidence databases, runs every check, writes nothing):"
plan "$W/ff.db" "$NEW" ff-dry --dry-run || fail=1
created "$W/ff.db" CON-243 CON-308
echo "  control: the target's own CON-243 value (2026-11-11 15:38:57, also recorded by the evidence items row)"
echo "  is later than the item's first history row and must be refused (dry run, before the plan, so only that guard can refuse):"
ev243=$(awk -F'\t' '$1=="CON-243"{print $8}' "$HERE/restore_plan.tsv")
sha243=$(awk -F'\t' '$1=="CON-243"{print $7}' "$HERE/restore_plan.tsv")
( cd "$TREE" && "$NEW" restore-created-at --db "$W/ff.db" --id CON-243 --value "2026-11-11 15:38:57" \
    --evidence "$ev243" --evidence-sha256 "$sha243" --reason "control: later than the first event" --dry-run ) \
  >"$W/ff.control" 2>&1
rc=$?
sed 's/^/    /' "$W/ff.control"
echo "  control exit=$rc (want 1, refused [VALUE-AFTER-FIRST-EVENT])"
grep -q 'refused \[VALUE-AFTER-FIRST-EVENT\]' "$W/ff.control" && [ "$rc" = 1 ] || fail=1
plan "$W/ff.db" "$NEW" ff || fail=1
created "$W/ff.db" CON-243 CON-308
validate "$W/ff.db" ff || fail=1
verify "$FFP" "$W/ff.db" ff-after

for leg in OLD NEW; do
  eng=$OLD; [ "$leg" = NEW ] && eng=$NEW
  echo "===== R-$leg (replay onto a copy of the target with the $leg engine, then the plan with the NEW engine)"
  cp -- "$T" "$W/r$leg.db" && chmod 0644 "$W/r$leg.db" || exit 3
  remint replay --plan "$RP" --apply --engine "$eng" --db "$W/r$leg.db" >"$W/r$leg.replay" 2>&1
  rc=$?
  echo "  replay exit=$rc $(grep '^RESULT:' "$W/r$leg.replay")"
  [ "$rc" = 0 ] || { fail=1; continue; }
  created "$W/r$leg.db" CON-243 CON-308
  verify "$RP" "$W/r$leg.db" "r$leg-before"
  plan "$W/r$leg.db" "$NEW" "r$leg" || fail=1
  created "$W/r$leg.db" CON-243 CON-308
  validate "$W/r$leg.db" "r$leg" || fail=1
  verify "$RP" "$W/r$leg.db" "r$leg-after"
  echo "  second apply (idempotence):"
  plan "$W/r$leg.db" "$NEW" "r$leg-again" || fail=1
done
echo "RESULT: $([ "$fail" = 0 ] && echo OK || echo FAIL)"
exit "$fail"
