#!/usr/bin/env bash
# test_governance_subset_conservative.sh -- T121 review finding regression
# test (SpecKit-004, US4) for context/governance_subset.py.
#
#   G1 (GS-001 "an unresolved input may only WIDEN a selection, never narrow
#     it"): on the tracker-DB path, defect_class and phase are not
#     recoverable and were set to null. A null defect_class made the
#     'critical-invariant-defect' rule silently not match while another rule
#     DID match -- so the selection came out core+{bug-ui anchors} and
#     silently dropped the critical-invariant anchors a real
#     critical_invariant item needs. That is NARROWING. Required now: when a
#     rule's decision depends on an input the tool could not resolve, the
#     selection is SUPERSET_FALLBACK (full corpus) and the unresolved inputs
#     are recorded; `verify` re-derives the same answer.
#   G4 (GS-006 "token figures come from recorded usage"): `measure` summed
#     only the non-null usage fields and called that MEASURED, so a usage
#     document missing output_tokens reported within_bound=true on a
#     partial (under-)count. Required now: a partial usage block is PARTIAL,
#     within_bound stays null unless the partial LOWER BOUND already exceeds
#     the bound (then false is provable), and a non-integer token value is
#     refused (exit 4), never crashed on or coerced.
# Golden-FALSE controls (11.4.201(1)): an item-record item with every input
# resolved keeps its exact narrow selection (no spurious fallback), and a
# complete usage block under the bound still reports within_bound=true.
# Hermetic: builds a throwaway git repo + tracker DB under mktemp.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC="$HERE/.."
GS="$FC/context/governance_subset.py"
CONST=$(cd "$FC/../.." && pwd)            # the constitution submodule root
IDX="$CONST/constitution_index.yaml"
RT="$HERE/fixtures/governance_subset/rule_table.json"
GOOD="$HERE/fixtures/governance_subset/gs_good_bug_ui.json"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "ok   $*"; pass=$((pass+1)); }
bad(){ echo "FAIL $*"; fail=$((fail+1)); }
# jget FILE EXPR: EXPR is a fixed expression literal authored in THIS file
# (never external input), evaluated against the tool's own JSON output.
jget(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(json.dumps(eval(sys.argv[2])))" "$1" "$2"; }

for f in "$GS" "$IDX" "$RT" "$GOOD"; do [ -f "$f" ] || { echo "BLIND: missing $f"; exit 4; }; done

# --- throwaway repo: tracker DB with one Bug item + a diff touching ui/ ---
R="$TMP/repo"; mkdir -p "$R/docs"
ln -s "$CONST" "$R/constitution"
python3 - "$R/docs/workable_items.db" <<'E'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE items(atm_id TEXT, type TEXT, logic_group TEXT)")
c.execute("INSERT INTO items VALUES('FC-GS-DB-001','Bug','presenter-ui')"); c.commit(); c.close()
E
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo a > "$R/base.txt"; git -C "$R" add base.txt; git -C "$R" commit -qm base
mkdir -p "$R/ui"; echo b > "$R/ui/screen.txt"; git -C "$R" add ui/screen.txt; git -C "$R" commit -qm ui
echo '[{"prefix":"ui/","class":"ui"}]' > "$TMP/pcm.json"
BASE=$(git -C "$R" rev-list --max-parents=0 HEAD)

# 1 G1: DB path, diff touches ui, defect_class unrecoverable -> must widen
python3 "$GS" select --config "$RT" --item FC-GS-DB-001 --repo "$R" --index "$IDX" \
  --diff "$BASE..HEAD" --path-class-map "$TMP/pcm.json" --out "$TMP/db_sel.json" >/dev/null 2>"$TMP/err1"
rc=$?
if [ "$rc" -ne 0 ]; then bad "G1 select rc=$rc: $(tail -1 "$TMP/err1")"
else
  fb=$(jget "$TMP/db_sel.json" "d.get('fallback')")
  has239=$(jget "$TMP/db_sel.json" "'11.4.239' in d['selected_anchors']")
  [ "$fb" = '"SUPERSET_FALLBACK"' ] && [ "$has239" = true ] \
    && ok "G1 unresolved defect_class -> SUPERSET_FALLBACK incl. 11.4.239" \
    || bad "G1 DB-path selection narrowed (fallback=$fb, has 11.4.239=$has239)"
  unres=$(jget "$TMP/db_sel.json" "sorted(d.get('unresolved_inputs') or [])")
  echo "$unres" | grep -q defect_class && ok "G1 unresolved_inputs recorded: $unres" \
    || bad "G1 unresolved inputs not recorded (got $unres)"
  # verify must re-derive the identical (widened) answer
  python3 "$GS" verify --selection "$TMP/db_sel.json" >/dev/null 2>"$TMP/err2" \
    && ok "G1 verify re-derives the widened selection (rc=0)" \
    || bad "G1 verify disagrees with select: $(tail -1 "$TMP/err2")"
fi

# 2 golden-FALSE: fully-resolved item-record keeps its narrow 10-anchor selection
python3 "$GS" select --config "$RT" --item FC-GS-SAMPLE-001 --item-record "$GOOD" \
  --index "$IDX" --out "$TMP/good_sel.json" >/dev/null 2>&1
n=$(jget "$TMP/good_sel.json" "len(d['selected_anchors'])" 2>/dev/null); fb=$(jget "$TMP/good_sel.json" "d.get('fallback')" 2>/dev/null)
[ "$n" = 10 ] && [ "$fb" = null ] && ok "fully-resolved item keeps narrow 10-anchor selection" \
  || bad "fully-resolved item changed (n=$n fallback=$fb)"

# 3 G4: usage missing output_tokens + cache fields -> not MEASURED, within_bound null
echo '{"input_tokens": 10}' > "$TMP/u_partial.json"
python3 "$GS" measure --selection "$TMP/good_sel.json" --usage "$TMP/u_partial.json" \
  --bound-tok 100 --out "$TMP/m1.json" >/dev/null 2>&1; rc=$?
st=$(jget "$TMP/m1.json" "d['usage']['status']" 2>/dev/null); wb=$(jget "$TMP/m1.json" "d['within_bound']" 2>/dev/null)
[ "$rc" -eq 0 ] && [ "$st" = '"PARTIAL"' ] && [ "$wb" = null ] \
  && ok "G4 partial usage -> PARTIAL, within_bound null" || bad "G4 partial usage rc=$rc status=$st within_bound=$wb"

# 4 G4: partial lower bound already over the bound -> within_bound false, exit 1
echo '{"input_tokens": 500}' > "$TMP/u_over.json"
python3 "$GS" measure --selection "$TMP/good_sel.json" --usage "$TMP/u_over.json" \
  --bound-tok 100 --out "$TMP/m2.json" >/dev/null 2>&1; rc=$?
wb=$(jget "$TMP/m2.json" "d['within_bound']" 2>/dev/null)
[ "$rc" -eq 1 ] && [ "$wb" = false ] && ok "G4 partial lower bound over bound -> false, rc=1" \
  || bad "G4 partial-over rc=$rc within_bound=$wb"

# 5 G4: non-integer token value -> refused rc=4, no traceback
echo '{"input_tokens":"abc","cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1}' > "$TMP/u_bad.json"
python3 "$GS" measure --selection "$TMP/good_sel.json" --usage "$TMP/u_bad.json" \
  --bound-tok 100 --out "$TMP/m3.json" >/dev/null 2>"$TMP/err3"; rc=$?
if [ "$rc" -eq 4 ] && ! grep -q Traceback "$TMP/err3"; then ok "G4 non-int token value refused rc=4"
else bad "G4 non-int token value rc=$rc ($(grep -c Traceback "$TMP/err3") tracebacks)"; fi

# 6 golden-FALSE: complete usage under the bound -> MEASURED, within_bound true
echo '{"input_tokens":10,"cache_read_input_tokens":5,"cache_creation_input_tokens":0,"output_tokens":3}' > "$TMP/u_ok.json"
python3 "$GS" measure --selection "$TMP/good_sel.json" --usage "$TMP/u_ok.json" \
  --bound-tok 100 --out "$TMP/m4.json" >/dev/null 2>&1; rc=$?
st=$(jget "$TMP/m4.json" "d['usage']['status']" 2>/dev/null); wb=$(jget "$TMP/m4.json" "d['within_bound']" 2>/dev/null)
[ "$rc" -eq 0 ] && [ "$st" = '"MEASURED"' ] && [ "$wb" = true ] \
  && ok "complete usage -> MEASURED, within_bound true" || bad "complete usage rc=$rc status=$st within_bound=$wb"

echo "RESULT: $pass PASS / $fail FAIL"
[ "$fail" -eq 0 ]
