#!/bin/bash
# docs/qa/tracker_intake_2026_11_12_v4/make_evidence.sh -- regenerate the round-4 evidence of the
# tracker-intake vehicle from the current tree (round-3 review M-7: the committed evidence must come
# from the final state, never from an earlier one).
#
# Usage: bash docs/qa/tracker_intake_2026_11_12_v4/make_evidence.sh <workable-items binary> <base rev> \
#             <name>=<target rev>[:no-ff] ...
#   <base rev>      the commit the vehicle branched from (its docs/workable_items.db is the base B)
#   <name>=<rev>    a landing target: its docs/workable_items.db is T; `:no-ff` adds --no-fast-forward
# The vehicle V is the working-tree docs/workable_items.db. Every database comes from git or from the
# working tree, so the run needs no file outside the repository. Run from the repository root.
#
# For each target it writes remint/<name>/: plan.json, plan.txt, map.tsv, replay.txt (or a
# fast-forward note), verify.txt, facts.txt (tools/landing_facts.py), tdiff3.md (tools/tdiff3.py) and
# validate.txt (`workable-items validate` of the landed copy, run inside a scratch merge tree: the
# target's files with the vehicle's changed and added files laid over them, so that the evidence paths
# of both sides resolve). It also writes final_lint.txt (intake_lint.py over the intake batch and the
# touched base items) and decision_record_facts.txt (the R2-1 relationship at 63f80e52, M-10).
# Nothing here writes a tracked database: landings run on copies in a mktemp directory.
# Exit: 0 every step ran (read the RESULT lines for verdicts); 2 usage; 3 a precondition failed.
# Evidence class: gate-logic only (section 11.4.289).
set -u
[ $# -ge 3 ] || { echo "usage: make_evidence.sh <wi> <base rev> <name>=<target rev>[:no-ff] ..." >&2; exit 2; }
WI=${1:?}; BASE=${2:?}; shift 2
D=docs/qa/tracker_intake_2026_11_12_v4
R=scripts/workable-items/remint_ids.py
LINT=scripts/workable-items/intake_lint.py
[ -f "$D/make_evidence.sh" ] || { echo "precondition: run from the repository root" >&2; exit 3; }
[ -x "$WI" ] || { echo "precondition: engine binary not executable" >&2; exit 3; }
git cat-file -e "$BASE:docs/workable_items.db" 2>/dev/null || { echo "precondition: no database at $BASE" >&2; exit 3; }
ROOT=$(pwd)
tmp=$(mktemp -d)
cleanup(){ rm -rf "${tmp:?}"; }
trap cleanup EXIT
INTAKE=$(python3 -I -c 'print(",".join("CON-%03d" % i for i in range(299, 343)))')
git show "$BASE:docs/workable_items.db" > "$tmp/base.db"
V=docs/workable_items.db

{ echo "\$ intake_lint.py --db $V --ids CON-299..CON-342 --prefix CON --require-dup-check --repo-root ."
  python3 -I "$LINT" --db "$V" --ids "$INTAKE" --prefix CON --require-dup-check --repo-root . 2>&1; echo "rc=$?"
  echo "\$ intake_lint.py --db $V --ids CON-046,CON-243,CON-262 --prefix CON --repo-root . --skip-check <format codes>"
  echo "  (base items the vehicle changed; their descriptions predate the section 11.4.148 intake format, so the"
  echo "   format codes SECTIONS, XREF-*, PATH-MISSING, SHARED-PATH and DUP-CHECK are skipped; every other code runs)"
  python3 -I "$LINT" --db "$V" --ids CON-046,CON-243,CON-262 --prefix CON --repo-root . \
    --skip-check SECTIONS,XREF-LABEL,XREF-UNLABELLED,XREF-DANGLING,PATH-MISSING,SHARED-PATH,DUP-CHECK 2>&1; echo "rc=$?"
} > "$D/final_lint.txt"

{ echo "R2-1 relationship, read from docs/workable_items.db at 63f80e52 (round 2 of the vehicle):"
  git show 63f80e52:docs/workable_items.db > "$tmp/r2.db"
  python3 -I - "$tmp/r2.db" <<'PY'
import re, sqlite3, sys
c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
for i, s in c.execute("select atm_id, status from items where atm_id in ('CON-243','CON-262','CON-308') order by atm_id"):
    print("  status %s: %s" % (i, s))
for row in c.execute("select atm_id, reason, superseding_item from obsolete_details where atm_id in ('CON-243','CON-262','CON-308')"):
    print("  obsolete_details %s: %s %s" % row)
for i in ("CON-243", "CON-262", "CON-308"):
    d = c.execute("select description from items where atm_id=?", (i,)).fetchone()[0]
    for s in re.split(r"(?<=\.)\s|\n", d):
        if re.search(r"UNDECIDED|candidate|SAME-DEFECT", s, re.I):
            print("  %s says: %s" % (i, s.strip()))
PY
} > "$D/decision_record_facts.txt"

# the vehicle's changed and added files, laid over a target tree for `validate`
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
  python3 -I "$D/tools/landing_facts.py" --vehicle-db "$V" --landed-db "$landed" --map "$o/map.tsv" > "$o/facts.txt" 2>&1
  echo "rc=$?" >> "$o/facts.txt"
  python3 -I "$D/tools/tdiff3.py" --base "$tmp/base.db" --vehicle "$V" --target "$t" --landed "$landed" \
    --map "$o/map.tsv" > "$o/tdiff3.md" 2>&1
  mt="$tmp/$name.tree"; mkdir -p "$mt"
  git archive "$rev" | tar -x -C "$mt"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    mkdir -p "$mt/$(dirname "$f")"; cp "$f" "$mt/$f"
  done < "$overlay"
  ( cd "$mt" && "$WI" validate --db "$landed" ) > "$o/validate.txt" 2>&1; echo "rc=$?" >> "$o/validate.txt"
  rm -rf "${mt:?}"
done
cd "$ROOT" || exit 3
echo "evidence written under $D"
exit 0
