#!/usr/bin/env bash
# docs/qa/tracker_intake_2026_11_14_v6/tools/make_final_lint.sh -- write final_lint.txt: the intake lint
# of the vehicle's own items and of the three base items it changed, with no skip list (round 6, R5-5).
#
# usage (from the repository root): make_final_lint.sh BASE_DB > docs/qa/tracker_intake_2026_11_14_v6/final_lint.txt
#   BASE_DB  the tracker database of the base commit 02c10935 (`git show 02c10935:docs/workable_items.db`
#            written to a scratch file); it is only read
# Runs, each printed as the argv that runs (placeholders only for the scratch path and the id list):
#   1. the vehicle's own items by id (CON-299..CON-344)
#   2. the same batch selected by its Origin line, with --require-dup-check (the suite's real-DB case)
#   3. the three base items the vehicle changed, no skip list (the headline count)
#   4. the same three items in BASE_DB, no skip list, documents not read
#   5. the set difference of 3 minus 4: the findings the vehicle brings (by code, item and detail)
# Exit: 0 when every run gave the exit status recorded here (1 and 2 PASS, 3 and 4 FAIL); 1 otherwise.
# Evidence class: gate-logic only (section 11.4.289).
set -u
base=${1:?usage: make_final_lint.sh BASE_DB}
lint=scripts/workable-items/intake_lint.py
db=docs/workable_items.db
[ -f "$lint" ] && [ -f "$db" ] || { echo "run from the repository root" >&2; exit 2; }
ids=$(seq -f 'CON-%g' 299 344 | paste -sd, -)
bad=0
run() { # run <want-rc> <title> <shown argv> -- <real argv>
  local want=$1 title=$2 shown=$3; shift 4
  echo "# $title"; echo "\$ $shown"
  python3 -I "$lint" "$@" > "$tmp/out" 2>&1; local rc=$?
  cat "$tmp/out"; echo "rc=$rc"
  [ "$rc" = "$want" ] || bad=1
}
# guarded deletes (section 11.4.287, round-8 review N6): safe_rm_rf refuses an empty or protected path
. scripts/lib/safe_rm.sh || { echo "precondition: run from the repository root" >&2; exit 2; }
tmp=$(mktemp -d) || exit 2
trap 'safe_rm_rf "${tmp:?}"' EXIT
run 0 "the vehicle's own items (CON-299..CON-344)" \
  "python3 -I $lint --db $db --ids <CON-299..CON-344> --prefix CON --repo-root ." -- \
  --db "$db" --ids "$ids" --prefix CON --repo-root .
run 0 "the same batch by its Origin line, duplicate-check line required" \
  "python3 -I $lint --db $db --prefix CON --origin 'tracker-intake vehicle 2026-11-12' --require-dup-check --repo-root ." -- \
  --db "$db" --prefix CON --origin "tracker-intake vehicle 2026-11-12" --require-dup-check --repo-root .
run 1 "the three base items the vehicle changed, NO skip list (the headline count; round 6, R5-5)" \
  "python3 -I $lint --db $db --ids CON-046,CON-243,CON-262 --prefix CON --repo-root ." -- \
  --db "$db" --ids CON-046,CON-243,CON-262 --prefix CON --repo-root .
cp "$tmp/out" "$tmp/veh"
run 1 "the same items in the base database (02c10935), no skip list, documents not read (the base renders are not in this tree)" \
  "python3 -I $lint --db <base 02c10935 db> --ids CON-046,CON-243,CON-262 --prefix CON --repo-root . --no-rendered" -- \
  --db "$base" --ids CON-046,CON-243,CON-262 --prefix CON --repo-root . --no-rendered
echo "# findings of run 3 that run 4 does not have (the vehicle's own; R5-5)"
grep '^FINDING ' "$tmp/veh" | sort > "$tmp/v"
grep '^FINDING ' "$tmp/out" | sort > "$tmp/b"
comm -23 "$tmp/v" "$tmp/b" | sed 's/^FINDING /NEW /'
echo "new=$(comm -23 "$tmp/v" "$tmp/b" | wc -l) vehicle=$(wc -l < "$tmp/v") base=$(wc -l < "$tmp/b")"
exit "$bad"
