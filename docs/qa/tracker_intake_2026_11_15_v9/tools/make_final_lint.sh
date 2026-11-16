#!/usr/bin/env bash
# docs/qa/tracker_intake_2026_11_15_v9/tools/make_final_lint.sh -- write final_lint.txt: the intake lint
# of the vehicle's own items and of the three base items it changed, with no skip list (round 6, R5-5;
# round 7: the set difference compares like with like, F5).
#
# usage (from the repository root): make_final_lint.sh BASE_DB > docs/qa/tracker_intake_2026_11_15_v9/final_lint.txt
#   BASE_DB  the tracker database of the base commit 02c10935 (`git show 02c10935:docs/workable_items.db`
#            written to a scratch file); it is only read
# Runs, each printed as the argv that runs (placeholders only for the scratch path and the id list):
#   1. the vehicle's own items by id (CON-299..CON-344)
#   2. the same batch selected by its Origin line, with --require-dup-check (the suite's real-DB case)
#   3. the three base items the vehicle changed, no skip list (the headline count)
#   4. the same three items in BASE_DB, no skip list, documents not read
#   5. the same three items in the vehicle database with documents not read (as run 4, round 7, F5)
#   6. the set difference of 5 minus 4: the findings the vehicle brings, like for like (by code, item
#      and detail); the rendered-document findings of run 3 are listed apart, by code and item
# Exit: 0 when every run gave the exit status recorded here (1 and 2 PASS, 3, 4 and 5 FAIL); 1 otherwise.
# Evidence class: gate-logic only (section 11.4.289).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
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
# shellcheck source=../../../../scripts/lib/safe_rm.sh
. scripts/lib/safe_rm.sh || exit 2
tmp=$(mktemp -d) || exit 2
# round 7 (F4): the cleanup goes through safe_rm_rf
trap 'safe_rm_rf "${tmp:?}" || echo "CLEANUP REFUSED: $tmp" >&2' EXIT
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
grep '^FINDING ' "$tmp/out" | LC_ALL=C sort > "$tmp/b"
run 1 "the same three items in the vehicle database, documents not read (like run 4; round 7, F5)" \
  "python3 -I $lint --db $db --ids CON-046,CON-243,CON-262 --prefix CON --repo-root . --no-rendered" -- \
  --db "$db" --ids CON-046,CON-243,CON-262 --prefix CON --repo-root . --no-rendered
grep '^FINDING ' "$tmp/out" | LC_ALL=C sort > "$tmp/vn"
echo "# findings of run 5 that run 4 does not have: the vehicle's own, like for like (R5-5, F5)"
LC_ALL=C comm -23 "$tmp/vn" "$tmp/b" | sed 's/^FINDING /NEW /'
echo "new=$(LC_ALL=C comm -23 "$tmp/vn" "$tmp/b" | wc -l) vehicle=$(wc -l < "$tmp/vn") base=$(wc -l < "$tmp/b")"
echo "# findings of run 3 that run 5 does not have: those read from the rendered documents only"
grep '^FINDING ' "$tmp/veh" | LC_ALL=C sort > "$tmp/v"
LC_ALL=C comm -23 "$tmp/v" "$tmp/vn" | sed 's/^FINDING /RENDERED /'
echo "rendered_only=$(LC_ALL=C comm -23 "$tmp/v" "$tmp/vn" | wc -l)"
exit "$bad"
