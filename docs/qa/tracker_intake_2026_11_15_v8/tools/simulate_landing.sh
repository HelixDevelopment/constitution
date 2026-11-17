#!/bin/bash
# docs/qa/tracker_intake_2026_11_15_v8/tools/simulate_landing.sh -- the round-8 landing simulations of the
# tracker-intake vehicle: the landing loop of docs/qa/tracker_intake_2026_11_12_v5/make_evidence.sh, on
# the round-8 tree, writing docs/qa/tracker_intake_2026_11_15_v8/remint/<name>/.
#
# Usage (from the repository root): bash docs/qa/tracker_intake_2026_11_15_v8/tools/simulate_landing.sh \
#             <workable-items binary> <base rev> <name>=<target rev>[:no-ff] ...
#   <base rev>      the commit the vehicle branched from (its docs/workable_items.db is the base B)
#   <name>=<rev>    a landing target: its docs/workable_items.db is T; `:no-ff` adds --no-fast-forward
# The vehicle V is the working-tree docs/workable_items.db. For each target it writes plan.json,
# plan.txt, map.tsv, replay.txt (or a fast-forward note), verify.txt, facts.txt, tdiff3.md and
# validate.txt (`workable-items validate` of the landed copy inside a scratch merge tree: the target's
# files with the vehicle's changed and added files laid over them). facts.txt and tdiff3.md come from
# the round-5 tools (docs/qa/tracker_intake_2026_11_12_v5/tools/landing_facts.py and tdiff3.py), used
# unchanged. Nothing here writes a tracked database: every landing runs on a copy in a mktemp directory.
# Exit: 0 every step ran (read the RESULT lines for verdicts); 2 usage; 3 a precondition failed.
# Evidence class: gate-logic only (section 11.4.289).
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
set -u
[ $# -ge 3 ] || { echo "usage: simulate_landing.sh <wi> <base rev> <name>=<target rev>[:no-ff] ..." >&2; exit 2; }
WI=${1:?}; BASE=${2:?}; shift 2
D=docs/qa/tracker_intake_2026_11_15_v8
T5=docs/qa/tracker_intake_2026_11_12_v5/tools
R=scripts/workable-items/remint_ids.py
[ -f "$D/tools/simulate_landing.sh" ] && [ -f "$T5/landing_facts.py" ] || { echo "precondition: run from the repository root" >&2; exit 3; }
[ -x "$WI" ] || { echo "precondition: engine binary not executable" >&2; exit 3; }
git cat-file -e "$BASE:docs/workable_items.db" 2>/dev/null || { echo "precondition: no database at $BASE" >&2; exit 3; }
# shellcheck source=../../../../scripts/lib/safe_rm.sh
. scripts/lib/safe_rm.sh || { echo "precondition: scripts/lib/safe_rm.sh not loadable" >&2; exit 3; }
tmp=$(mktemp -d) || exit 3
# round 7 (F4): every delete goes through safe_rm_rf, which refuses an empty, relative or protected path
cleanup(){ safe_rm_rf "${tmp:?}" || echo "CLEANUP REFUSED: $tmp" >&2; }
trap cleanup EXIT
git show "$BASE:docs/workable_items.db" > "$tmp/base.db"
V=docs/workable_items.db
overlay=$(mktemp "$tmp/overlay.XXXXXX")
{ git diff --name-only --diff-filter=d "$BASE"; git ls-files --others --exclude-standard; } | sort -u > "$overlay"
for spec in "$@"; do
  name=${spec%%=*}; rev=${spec#*=}; ff=""
  case "$rev" in *:no-ff) rev=${rev%:no-ff}; ff=--no-fast-forward ;; esac
  case "$name" in ''|*[!a-z0-9_-]*) echo "usage: target name must be [a-z0-9_-]+: $name" >&2; exit 2 ;; esac
  git cat-file -e "$rev:docs/workable_items.db" 2>/dev/null || { echo "precondition: no database at $rev" >&2; exit 3; }
  o="$D/remint/$name"; mkdir -p "$o"
  t="$tmp/$name.target.db"; git show "$rev:docs/workable_items.db" > "$t"
  echo "target $name: $(git rev-parse "$rev")${ff:+ ($ff)}" > "$o/target.txt"
  python3 -I "$R" plan --vehicle-db "$V" --base-db "$tmp/base.db" --target-db "$t" --out "$o/plan.json" \
    --map-out "$o/map.tsv" --prefix CON --repo-root . $ff > "$o/plan.txt" 2>&1
  echo "rc=$?" >> "$o/plan.txt"
  landed="$tmp/$name.landed.db"
  if grep -q 'mode=FAST-FORWARD' "$o/plan.txt"; then
    cp "$V" "$landed"
    echo "FAST-FORWARD: the landed database is the vehicle database; no step to replay" > "$o/replay.txt"
  else
    cp "$t" "$landed"
    python3 -I "$R" replay --plan "$o/plan.json" --apply --engine "$WI" --db "$landed" > "$o/replay.txt" 2>&1
    echo "rc=$?" >> "$o/replay.txt"
  fi
  python3 -I "$R" verify --plan "$o/plan.json" --vehicle-db "$V" --base-db "$tmp/base.db" --target-db "$t" \
    --db "$landed" > "$o/verify.txt" 2>&1; echo "rc=$?" >> "$o/verify.txt"
  python3 -I "$T5/landing_facts.py" --vehicle-db "$V" --landed-db "$landed" --map "$o/map.tsv" > "$o/facts.txt" 2>&1
  echo "rc=$?" >> "$o/facts.txt"
  python3 -I "$T5/tdiff3.py" --base "$tmp/base.db" --vehicle "$V" --target "$t" --landed "$landed" \
    --map "$o/map.tsv" > "$o/tdiff3.md" 2>&1
  mt="$tmp/$name.tree"; mkdir -p "$mt"
  git archive "$rev" | tar -x -C "$mt"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    mkdir -p "$mt/$(dirname "$f")"; cp "$f" "$mt/$f"
  done < "$overlay"
  ( cd "$mt" && "$WI" validate --db "$landed" ) > "$o/validate.txt" 2>&1; echo "rc=$?" >> "$o/validate.txt"
  safe_rm_rf "${mt:?}" || { echo "precondition: cleanup of $mt refused" >&2; exit 3; }
done
echo "landing simulations written under $D/remint"
exit 0
