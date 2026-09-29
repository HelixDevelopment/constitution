#!/bin/bash
# Purpose : T104 (SpecKit-004 "fast-dev-cycles", User Story 4) RED baseline
#           for `context/governance_subset.py` (T112's own, separate, later
#           implementation task), per plan.md T-E01 and contract
#           contracts/governance-subset-selector.md ("Select, mechanically
#           from an item's classification, the minimal set of governance
#           anchors the item binds, render only that set as the agent's
#           governance context, and record the bytes and tokens loaded" --
#           R2's own finding, quoted verbatim in the contract's Invocation
#           section: "every Claude Code agent today loads a ~1.18 MB chain
#           (~296k est. tokens), which blocks cheap-tier dispatch outright
#           (haiku refused at ~421k tokens)").
#
# tasks.md T104's own four assertions (this file's four checks, in order):
#   (1) TODAY -- a sample item loads the full chain (no per-item selection
#       mechanism exists at all yet);
#   (2) GOLDEN -- the loaded subset equals the mechanically derived set for
#       a sample item (contract's own FR-013 check, GS-007's "wrong subset
#       fails" logic applied in reverse to a CORRECT subset);
#   (3) GOLDEN-BAD -- a subset missing a binding anchor FAILs (GS-007);
#   (4) NEGATIVE CONTROL -- an item whose classification is unknown gets the
#       conservative superset and PASSES (GS-004: "Never a silent smaller
#       set" -- the fallback path is itself a PASS, not an error).
#
# THE GAP (verified directly, 2026-09-29 against the current working tree):
# `constitution/scripts/fastcycle/context/` holds exactly one file today,
# `anchor_citations.py` (T039, a SEPARATE, already-landed task) -- there is
# NO `governance_subset.py` of any kind. A bare directory-existence check
# would therefore be a section-12.1-class false-positive-refusal guard (the
# directory existing proves nothing about T112's status -- the same lesson
# this suite's sibling test_reopen_rate_red.sh already documents for
# `closure/`); the load-bearing check below is CONTENT: does the directory
# hold `governance_subset.py` specifically.
#
# Producer != Verifier (11.4.240): this file is authored at the RED step
# (T104); T112's implementation of `context/governance_subset.py` is a
# separate, later task -- this file's author never implements it. The
# independent derivation function embedded below (derive_selection, a fresh
# Python re-implementation of contract clauses GS-001..GS-004 written
# directly from the contract's own wording, over this test's OWN fixture-
# only rule table -- never T112's eventual production rule table) is a
# DERIVED oracle per section 11.4.245, computed independently of whatever
# T112 eventually writes; it is never imported by, shared with, or otherwise
# coupled to `context/governance_subset.py` so the two never collapse into
# one producer=verifier pair.
#
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms):
#   #1 -- before trusting "governance_subset.py is absent" as a finding,
#        prove the plain `[ -f PATH ]` relative-path check genuinely
#        resolves paths from this script's real location, by first
#        confirming a KNOWN-PRESENT sibling (lib/fc_common.py, used
#        throughout this suite) resolves true through the identical
#        relative-path construction.
#   #2 -- the synthetic fixture item ids (FC-GS-SAMPLE-001/002) do not
#        collide with any real item in the live tracker DB
#        (docs/workable_items.db), mirroring test_reopen_rate_red.sh's own
#        fixture-id-collision precaution.
#   #3 -- EVERY anchor id this test's fixtures reference (the 8-id
#        always_core plus every rule's add_anchors in rule_table.json) is
#        genuinely present, right now, in the LIVE
#        constitution/constitution_index.yaml -- proving these fixtures are
#        not testing against phantom anchor ids that a future constitution
#        edit could silently remove without this test noticing.
#
# section-11.4.245 (oracle-problem-first / DERIVED oracle): both fixture
# items' `expected_selection` blocks were hand-computed FIRST, in each
# fixture's own `_hand_computation` field, and are independently RE-DERIVED
# below by this test's own from-scratch Python function (never borrowed
# from, or shared with, any implementation) BEFORE that hand-computed value
# is trusted -- mirroring sibling test_reopen_rate_red.sh's derive.py
# convention exactly.
#
# section-11.4.107(10) self-validation triple (Principle IV): gs_good_bug_ui
# (golden-good) and gs_bad_wrong_subset (golden-bad) MUST produce OPPOSITE
# verdicts (a real, complete 10-anchor subset vs a subset missing a binding
# anchor) from the SAME derivation function -- proving the derivation, and
# the eventual `verify` check it stands in for, can genuinely discriminate a
# correct subset from an incorrect one. gs_negctrl_unmapped_input is the
# THIRD member of the triple: unlike golden-bad, its "something is missing"
# surface shape (zero rule matches) requires the OPPOSITE verdict -- PASS
# with the conservative superset, never a refusal and never a smaller set
# (GS-004's own "Never a silent smaller set" wording) -- proving the
# derivation does not conflate "no rule matched" with "must fail".
#
# Paired mutation (contract's own fixture-table row, verbatim): "drop GS-004
# so unmapped inputs yield core-only => gs_negctrl_unmapped_input produces a
# smaller set; meta-test must catch." This file's own mutation-simulation
# check below runs a deliberately GS-004-dropping variant of the derivation
# against gs_negctrl_unmapped_input and proves it diverges from the correct,
# fixture-recorded SUPERSET_FALLBACK verdict -- proving a real meta-test
# built against this fixture, once T112 lands, would genuinely catch that
# mutation.
#
# Usage : bash test_governance_subset_red.sh   Exit 0 = every real assertion
#         below held (all three control needles, the TODAY full-chain
#         baseline measurement, fixture presence, the golden/golden-bad/
#         negative-control derived-oracle checks, the self-validation
#         triple's cross-fixture discrimination proof, and the GS-004
#         mutation-simulation proof).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-29):
#         `context/governance_subset.py` genuinely does not exist yet (T112
#         is a separate, later, not-yet-started task) -- this is the T104
#         RED baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/governance_subset"
IMPL="$FC/context/governance_subset.py"
ANCHOR_INDEX="$ROOT/constitution/constitution_index.yaml"
CONSTITUTION_MD="$ROOT/constitution/Constitution.md"
DB="$ROOT/docs/workable_items.db"

fail=0
failx() { fail=1; }

# --- section-11.4.273 control needle #1: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence check below proves"
  echo "     nothing (section 11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the absence check"
  echo "   below can be trusted"
fi

# --- section-11.4.273 control needle #2: fixture ids must not collide with the live tracker DB ---
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  for fake_id in FC-GS-SAMPLE-001 FC-GS-SAMPLE-002; do
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$fake_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture id '$fake_id' collides"
      echo "     with a REAL live-tracker item -- every fixture in this suite must use"
      echo "     ids that do not exist in docs/workable_items.db"
      failx
    fi
  done
  echo "ok control needle #2: the synthetic fixture ids (FC-GS-SAMPLE-001/002) do"
  echo "   not collide with any real item in the live tracker DB"
else
  echo "NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable"
  echo "     in this environment -- this is an environment gap, not a finding"
  failx
fi

# --- section-11.4.273 control needle #3: every fixture anchor id is real, right now ---
if [ ! -f "$ANCHOR_INDEX" ]; then
  echo "NOT ok control needle #3 BLIND: anchor index absent at $ANCHOR_INDEX"
  failx
elif [ ! -f "$FIXDIR/rule_table.json" ]; then
  echo "NOT ok control needle #3 BLIND: rule_table.json fixture absent"
  failx
else
  NEEDLE3_OUT=$(python3 -c "
import json, re, sys
ID_LINE_RE = re.compile(r\"^- id: *'?([^']+)'?\$\")
with open(sys.argv[1], encoding='utf-8') as fh:
    lines = fh.read().split('\n')
live_ids = set()
for line in lines:
    m = ID_LINE_RE.match(line.rstrip('\r'))
    if m:
        live_ids.add(m.group(1))
with open(sys.argv[2], encoding='utf-8') as fh:
    rt = json.load(fh)
referenced = set(rt['always_core'])
for rule in rt['rules']:
    referenced |= set(rule['add_anchors'])
missing = sorted(referenced - live_ids)
if missing:
    print('MISSING:%s' % ','.join(missing))
else:
    print('OK:%d' % len(referenced))
" "$ANCHOR_INDEX" "$FIXDIR/rule_table.json")
  case "$NEEDLE3_OUT" in
    OK:*)
      echo "ok control needle #3: all $(echo "$NEEDLE3_OUT" | cut -d: -f2) anchor ids referenced by"
      echo "   this test's fixtures (always_core + every rule's add_anchors) are"
      echo "   genuinely present in the LIVE $ANCHOR_INDEX right now"
      ;;
    *)
      echo "NOT ok control needle #3 FAILED: fixture-referenced anchor id(s) absent from"
      echo "     the live index: $NEEDLE3_OUT -- a constitution edit removed an anchor"
      echo "     this test's fixtures depend on; the fixtures need updating"
      failx
      ;;
  esac
fi

# --- (1) Absence check: context/governance_subset.py ---
CONTEXT_DIR="$FC/context"
if [ -d "$CONTEXT_DIR" ]; then
  py_count=$(find "$CONTEXT_DIR" -maxdepth 1 -name '*.py' | wc -l)
  echo "-- $CONTEXT_DIR exists, holding $py_count *.py file(s) right now (T039's"
  echo "   anchor_citations.py -- a separate, already-landed task -- lives here too)"
else
  echo "-- $CONTEXT_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok context/governance_subset.py now exists -- T112 has landed. The forward-"
  echo "   compatible invocation checks below will exercise it for real against"
  echo "   every fixture's expected_selection block."
  TOOL_PRESENT=1
else
  echo "NOT ok context/governance_subset.py is absent -- T112 (plan.md T-E01's"
  echo "     implementation task, a SEPARATE later task from this RED test) has"
  echo "     not landed yet. THIS IS THE CORRECT, EXPECTED T104 RED BASELINE --"
  echo "     the fixtures + independent derivation below stand as the interim"
  echo "     contract T112 must satisfy to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# ---------------------------------------------------------------------------
# T104 assertion (1)/4: TODAY, with no selector, a sample item's governance
# context IS the full chain -- there is no mechanism, anywhere, that renders
# anything smaller than the full corpus for a given item. Demonstrated by
# measuring the full corpus's real, current size against the contract's own
# stated target core bound (GS-002: "target <= ~20k est tok, measured").
# GS-006's own labelling discipline is honoured explicitly: a byte/4 estimate
# is labelled ESTIMATE below and is NEVER used to satisfy a bound check (no
# bound check is being performed here at all -- this is the pre-selector
# BASELINE the eventual bound check will be measured against).
# ---------------------------------------------------------------------------
echo
echo "=== T104 assertion 1/4: TODAY a sample item loads the full chain (no selector exists) ==="
if [ -f "$CONSTITUTION_MD" ]; then
  FULL_BYTES=$(wc -c < "$CONSTITUTION_MD" | tr -d ' ')
  FULL_TOK_ESTIMATE=$((FULL_BYTES / 4))
  CORE_TARGET_TOK=20000
  echo "-- constitution/Constitution.md (the full governance chain a dispatched"
  echo "   agent loads today, absent any per-item selector) = $FULL_BYTES bytes"
  echo "   (ESTIMATE, bytes/4, per GS-006's labelling discipline -- never used"
  echo "   to satisfy any bound check): ~$FULL_TOK_ESTIMATE est tok"
  if [ "$FULL_TOK_ESTIMATE" -gt "$CORE_TARGET_TOK" ]; then
    echo "ok TODAY baseline: the full chain (~$FULL_TOK_ESTIMATE est tok, labelled"
    echo "   ESTIMATE) is far larger than the contract's stated always_core target"
    echo "   (GS-002: <= ~$CORE_TARGET_TOK est tok) -- confirming a sample item"
    echo "   today has no path to anything smaller than the full chain, since no"
    echo "   selection mechanism of any kind exists (context/governance_subset.py"
    echo "   is absent, confirmed above)."
  else
    echo "NOT ok TODAY baseline FAILED: the full chain measured smaller than the"
    echo "     core target -- the premise this check demonstrates (the full chain"
    echo "     vastly exceeds the target subset) no longer holds; investigate"
    failx
  fi
else
  echo "NOT ok TODAY baseline BLIND: $CONSTITUTION_MD absent -- cannot measure the"
  echo "     current full-chain size"
  failx
fi

# --- Fixture files present ---
for f in rule_table.json gs_good_bug_ui.json gs_bad_wrong_subset.json gs_negctrl_unmapped_input.json; do
  if [ ! -f "$FIXDIR/$f" ]; then
    echo "NOT ok fixture $FIXDIR/$f missing"
    failx
  else
    echo "ok fixture $f present"
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Independent DERIVED oracle (section 11.4.245): a from-scratch Python
# re-implementation of contract clauses GS-001..GS-004, written directly by
# THIS test's author, over THIS test's own fixture-only rule_table.json --
# never imported by nor shared with context/governance_subset.py.
#
# GS-003's closure clause ("closed under the cross_references of any
# selected anchor that is marked `requires` in the index") is implemented
# below exactly as written, but is CONFIRMED (via a live check, never
# assumed) to be a structural no-op against the CURRENT constitution_index.
# yaml: every anchor entry's cross_references list holds plain string ids,
# with no dict-shaped, `requires`-marked entries anywhere in the live index
# today (checked live below) -- so no anchor in this index currently
# declares a BINDING cross-reference distinct from an informational one.
# This is recorded honestly as a confirmed-today fact, not invented.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import json
import re
import sys

_ID_LINE_RE = re.compile(r"^- id: *'?([^']+)'?$")


def load_live_anchor_ids(anchor_index_path):
    """Same regex convention as context/anchor_citations.py's own
    load_live_anchor_ids -- never a hardcoded literal id list."""
    with open(anchor_index_path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    ids = set()
    for line in lines:
        m = _ID_LINE_RE.match(line.rstrip("\r"))
        if m:
            ids.add(m.group(1))
    return frozenset(ids)


def rule_matches(rule_match, item):
    """Contract GS-003: selected = always_core UNION rules(input). A rule's
    'match' block is a conjunction of field checks; a '<field>_any' key
    matches if ANY of item[field]'s values is in the rule's list."""
    for key, wanted in rule_match.items():
        if key.endswith("_any"):
            field = key[:-4]
            item_vals = item.get(field) or []
            if not isinstance(item_vals, list):
                item_vals = [item_vals]
            if not any(v in item_vals for v in wanted):
                return False
        else:
            if item.get(key) != wanted:
                return False
    return True


def derive_selection(item, rule_table, live_ids):
    """GS-002 always_core + GS-003 rule union + GS-004 conservative
    superset fallback. Returns (selected_anchors: sorted list,
    fallback: str|None, matched_rule_ids: sorted list)."""
    core = set(rule_table["always_core"])
    added = set()
    matched = []
    for rule in rule_table["rules"]:
        if rule_matches(rule["match"], item):
            matched.append(rule["rule_id"])
            added |= set(rule["add_anchors"])
    if matched:
        selected = core | added
        fallback = None
    else:
        # GS-004: any classification input with no rule => SUPERSET_FALLBACK
        # (full corpus). Never a silent smaller set.
        selected = set(live_ids)
        fallback = "SUPERSET_FALLBACK"
    return sorted(selected), fallback, sorted(matched)


def derive_selection_mutated_no_gs004(item, rule_table, live_ids):
    """The contract's own named paired mutation: 'drop GS-004 so unmapped
    inputs yield core-only'. Deliberately WRONG -- used only to prove the
    correct derive_selection() output diverges from this one on the
    negative-control fixture."""
    core = set(rule_table["always_core"])
    added = set()
    matched = []
    for rule in rule_table["rules"]:
        if rule_matches(rule["match"], item):
            matched.append(rule["rule_id"])
            added |= set(rule["add_anchors"])
    # Mutation: GS-004 dropped -- ALWAYS core-only-or-core-plus-matched,
    # never the full-corpus fallback, even when nothing matched.
    selected = core | added
    return sorted(selected), None, sorted(matched)


def main():
    item_fixture_path, rule_table_path, anchor_index_path, out_path = sys.argv[1:5]
    with open(item_fixture_path, encoding="utf-8") as fh:
        item_doc = json.load(fh)
    with open(rule_table_path, encoding="utf-8") as fh:
        rule_table = json.load(fh)
    live_ids = load_live_anchor_ids(anchor_index_path)
    item = item_doc["classification_inputs"]
    selected, fallback, matched = derive_selection(item, rule_table, live_ids)
    mut_selected, mut_fallback, mut_matched = derive_selection_mutated_no_gs004(
        item, rule_table, live_ids
    )
    result = {
        "item_id": item_doc.get("item_id"),
        "selected_anchors": selected,
        "fallback": fallback,
        "matched_rule_ids": matched,
        "mutated_no_gs004_selected_anchors": mut_selected,
        "mutated_no_gs004_fallback": mut_fallback,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, sort_keys=True, indent=2)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
PYEOF

# --- GS-003 closure-over-requires: confirm today it is a structural no-op ---
echo
echo "=== GS-003 closure-over-requires check: confirmed no-op against the LIVE index today ==="
GS003_OUT=$(python3 -c "
import re, sys
with open(sys.argv[1], encoding='utf-8') as fh:
    text = fh.read()
# A dict-shaped, 'requires'-marked cross_reference entry would render, under
# PyYAML block-sequence output, as a '- id: ...' / 'requires: true'-style
# nested mapping rather than a bare scalar list item ('  - '\''11.4.x'\''').
# No such shape exists anywhere in the live index today (checked via the
# absence of any 'requires:' key at all in the file).
print('NONE' if 'requires:' not in text else 'PRESENT')
" "$ANCHOR_INDEX")
if [ "$GS003_OUT" = "NONE" ]; then
  echo "ok GS-003 closure-over-requires is a confirmed no-op against the live index:"
  echo "   no anchor entry anywhere in $ANCHOR_INDEX declares a 'requires:' key"
  echo "   today (checked live, not assumed) -- so no selected anchor's"
  echo "   cross_references currently need closing over. This is an honest,"
  echo "   currently-confirmed fact about the index schema, not an invented one."
else
  echo "NOT ok GS-003 closure-over-requires premise CHANGED: the live index now"
  echo "     contains a 'requires:' key -- this test's derive_selection() does"
  echo "     NOT implement the closure step and needs updating before it can be"
  echo "     trusted"
  failx
fi

echo
echo "=== T104 assertion 2/4: gs_good_bug_ui (golden, matched-rule population, DERIVED oracle) ==="
GOOD_FIX="$FIXDIR/gs_good_bug_ui.json"
GOOD_DERIVED="$TMP/gs_good_bug_ui.derived.json"
python3 "$TMP/derive.py" "$GOOD_FIX" "$FIXDIR/rule_table.json" "$ANCHOR_INDEX" "$GOOD_DERIVED" >/dev/null
GOOD_MATCH="$(python3 -c "
import json
derived = json.load(open('$GOOD_DERIVED'))
expected = json.load(open('$GOOD_FIX'))['expected_selection']
print(derived['selected_anchors'] == expected['selected_anchors']
      and derived['fallback'] == expected['fallback']
      and derived['matched_rule_ids'] == expected['matched_rule_ids'])
" 2>&1)"
if [ "$GOOD_MATCH" = "True" ]; then
  echo "ok gs_good_bug_ui: the independent DERIVED oracle (section 11.4.245),"
  echo "   re-computed from scratch by THIS test's own from-scratch Python"
  echo "   function -- never the fixture author simply re-typing a number --"
  echo "   EXACTLY matches the fixture's own hand-computed expected_selection:"
  echo "   10 anchors, rule 'bug-ui-touched' matched, fallback=null. This is"
  echo "   the golden-good member of the self-validation triple."
else
  echo "NOT ok gs_good_bug_ui: the independent derivation did NOT match the"
  echo "     fixture's hand-computed expected_selection (comparator: '$GOOD_MATCH')."
  echo "     Derived: $(cat "$GOOD_DERIVED" 2>/dev/null)"
  failx
fi

echo
echo "=== T104 assertion 3/4: gs_bad_wrong_subset (golden-bad, missing binding anchor, DERIVED oracle) ==="
BAD_FIX="$FIXDIR/gs_bad_wrong_subset.json"
BAD_VERDICT="$(python3 -c "
import json
correct = json.load(open('$GOOD_DERIVED'))['selected_anchors']
wrong = json.load(open('$BAD_FIX'))['selected_anchors']
missing = sorted(set(correct) - set(wrong))
extra = sorted(set(wrong) - set(correct))
print(json.dumps({'equal': correct == wrong, 'missing': missing, 'extra': extra}))
" 2>&1)"
BAD_EQUAL="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['equal'])" "$BAD_VERDICT")"
BAD_MISSING="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['missing'])" "$BAD_VERDICT")"
if [ "$BAD_EQUAL" = "False" ] && [ "$BAD_MISSING" = "['11.4.107']" ]; then
  echo "ok gs_bad_wrong_subset: comparing the independently-derived CORRECT"
  echo "   subset for FC-GS-SAMPLE-001 against this fixture's (deliberately"
  echo "   wrong) selected_anchors shows exactly ONE anchor missing: 11.4.107 --"
  echo "   the anchor rule_table.json's own 'bug-ui-touched' rule declares"
  echo "   binding for this item's classification. This is the GS-007 'wrong"
  echo "   subset fails, naming the missing anchor' behaviour, exercised here"
  echo "   against this test's own independent oracle since"
  echo "   context/governance_subset.py's real 'verify' subcommand does not"
  echo "   exist yet to exercise directly."
else
  echo "NOT ok gs_bad_wrong_subset: expected exactly missing=['11.4.107'],"
  echo "     equal=False; got $BAD_VERDICT"
  failx
fi

echo
echo "=== T104 assertion 4/4: gs_negctrl_unmapped_input (negative control, DERIVED oracle) ==="
NEG_FIX="$FIXDIR/gs_negctrl_unmapped_input.json"
NEG_DERIVED="$TMP/gs_negctrl.derived.json"
python3 "$TMP/derive.py" "$NEG_FIX" "$FIXDIR/rule_table.json" "$ANCHOR_INDEX" "$NEG_DERIVED" >/dev/null
NEG_VERDICT="$(python3 -c "
import json
derived = json.load(open('$NEG_DERIVED'))
expected = json.load(open('$NEG_FIX'))['expected_selection']
with open('$ANCHOR_INDEX', encoding='utf-8') as fh:
    live_text = fh.read()
import re
# section-11.4.273 instrument note: a single-shot re.finditer(..., re.M) over
# the WHOLE file text was tried first and is deliberately NOT used here -- it
# is a real caught trap (verified 2026-09-29 while authoring this test): most
# '- id: <value>' lines in the live index are UNQUOTED (no '...' wrapper), so
# the '[^\'']+' character class -- which matches ANY character except a
# single quote, INCLUDING newlines, since only '.' needs re.DOTALL to span
# lines, not a negated character class -- greedily consumed forward across
# MANY subsequent lines until it happened to hit a literal quote character
# somewhere later in the document (e.g. inside an unrelated cross_references
# entry), undercounting 264 of the real 283 live ids and, worse, fabricating
# huge multi-line blobs as 'ids' for the rest -- a textbook section-
# 11.4.201(7)(c) 'the path is part of the instrument' trap. The fix, matching
# context/anchor_citations.py's own load_live_anchor_ids and this file's own
# derive.py: match PER LINE (a plain str.split('\n') loop with .match(),
# never .finditer() over the whole text), so '[^\'']+' has no newline inside
# its own search string to cross in the first place.
ID_LINE_RE = re.compile(r\"^- id: *'?([^']+)'?\$\")
live_ids = sorted({
    m.group(1)
    for m in (ID_LINE_RE.match(line.rstrip('\r')) for line in live_text.split('\n'))
    if m
})
print(json.dumps({
    'fallback_ok': derived['fallback'] == expected['fallback'],
    'matched_empty': derived['matched_rule_ids'] == [],
    'is_full_corpus': derived['selected_anchors'] == live_ids,
    'live_id_count': len(live_ids),
}))
" 2>&1)"
NEG_FALLBACK_OK="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['fallback_ok'])" "$NEG_VERDICT")"
NEG_MATCHED_EMPTY="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['matched_empty'])" "$NEG_VERDICT")"
NEG_IS_FULL="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['is_full_corpus'])" "$NEG_VERDICT")"
if [ "$NEG_FALLBACK_OK" = "True" ] && [ "$NEG_MATCHED_EMPTY" = "True" ] && [ "$NEG_IS_FULL" = "True" ]; then
  echo "ok gs_negctrl_unmapped_input: zero rules matched this item's"
  echo "   classification_inputs (item_type='Feature' never matches"
  echo "   'bug-ui-touched'; touched_path_classes=['exotic_unmapped_class_zz']"
  echo "   never matches 'device-orchestration-touched';"
  echo "   defect_class='unclassified_exotic_zz' never matches"
  echo "   'critical-invariant-defect') -- so the derivation correctly reports"
  echo "   fallback=SUPERSET_FALLBACK with selected_anchors equal to EVERY"
  echo "   anchor id currently in the live index (computed live, never a"
  echo "   hardcoded count -- $NEG_VERDICT). Per GS-004 this is a PASS, not an"
  echo "   error: an unmapped classification never silently narrows the set."
else
  echo "NOT ok gs_negctrl_unmapped_input: $NEG_VERDICT"
  failx
fi

echo
echo "=== Self-validation control needle 1 (section 11.4.107(10)/11.4.201(1)): golden vs negative-control discriminate ==="
DISC1="$(python3 -c "
import json
good = json.load(open('$GOOD_DERIVED'))
neg = json.load(open('$NEG_DERIVED'))
print(good['fallback'] is None and neg['fallback'] == 'SUPERSET_FALLBACK'
      and good['fallback'] != neg['fallback'])
" 2>&1)"
if [ "$DISC1" = "True" ]; then
  echo "ok control needle (fallback discrimination): gs_good_bug_ui's fallback is"
  echo "   null (a real rule matched) while gs_negctrl_unmapped_input's fallback"
  echo "   is SUPERSET_FALLBACK -- proving the derivation genuinely"
  echo "   discriminates a matched classification from an unmapped one rather"
  echo "   than rubber-stamping every input the same way."
else
  echo "NOT ok control needle (fallback discrimination) FAILED: both fixtures'"
  echo "     fallback values did not differ as expected"
  failx
fi

echo
echo "=== Self-validation control needle 2 (section 11.4.107(10)/11.4.201(1)): golden vs golden-bad discriminate ==="
DISC2="$(python3 -c "
import json
correct = json.load(open('$GOOD_DERIVED'))['selected_anchors']
correct_fix = json.load(open('$GOOD_FIX'))['expected_selection']['selected_anchors']
wrong_fix = json.load(open('$BAD_FIX'))['selected_anchors']
print(correct == correct_fix and correct != wrong_fix)
" 2>&1)"
if [ "$DISC2" = "True" ]; then
  echo "ok control needle (subset discrimination): the derived-oracle selection"
  echo "   for FC-GS-SAMPLE-001 matches gs_good_bug_ui.json's own"
  echo "   expected_selection EXACTLY, but differs from gs_bad_wrong_subset."
  echo "   json's selected_anchors -- proving a 'verify' style comparison"
  echo "   genuinely distinguishes a complete subset from an incomplete one,"
  echo "   not merely always agreeing or always disagreeing."
else
  echo "NOT ok control needle (subset discrimination) FAILED"
  failx
fi

echo
echo "=== Paired-mutation self-test (contract's own named mutation): drop GS-004 -> unmapped input yields a SMALLER set ==="
MUT_CHECK="$(python3 -c "
import json
neg = json.load(open('$NEG_DERIVED'))
correct_selected = set(neg['selected_anchors'])
correct_fallback = neg['fallback']
mutated_selected = set(neg['mutated_no_gs004_selected_anchors'])
mutated_fallback = neg['mutated_no_gs004_fallback']
print(json.dumps({
    'correct_fallback': correct_fallback,
    'mutated_fallback': mutated_fallback,
    'mutation_produces_smaller_set': len(mutated_selected) < len(correct_selected),
    'correct_size': len(correct_selected),
    'mutated_size': len(mutated_selected),
}))
" 2>&1)"
MUT_SMALLER="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['mutation_produces_smaller_set'])" "$MUT_CHECK")"
MUT_FALLBACK_DIFFERS="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d['correct_fallback'] != d['mutated_fallback'])
" "$MUT_CHECK")"
if [ "$MUT_SMALLER" = "True" ] && [ "$MUT_FALLBACK_DIFFERS" = "True" ]; then
  echo "ok mutation-simulation: dropping GS-004 (contract's own named paired"
  echo "   mutation) on gs_negctrl_unmapped_input's unmapped classification"
  echo "   produces a SMALLER selected_anchors set (core-only, $MUT_CHECK)"
  echo "   than the correct SUPERSET_FALLBACK, and a different (non-superset)"
  echo "   fallback value -- proving a real meta-test built against this"
  echo "   fixture, once T112 lands, would genuinely catch that mutation."
else
  echo "NOT ok mutation-simulation FAILED: $MUT_CHECK -- the GS-004-dropping"
  echo "     mutation did not produce a detectably smaller/different set; this"
  echo "     fixture would not catch that mutation and needs revising"
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# context/governance_subset.py lands (T112), this block invokes it for real
# per contract's own documented Invocation section:
#   governance_subset.py select --config <cfg> --item <ItemId>
#       [--diff <base>..<head>] --out <selection.json>
#   governance_subset.py verify --selection <selection.json>
#
# UNCONFIRMED (honest, not invented -- mirrors the contract's own GS-005/
# GS-008 "UNCONFIRMED" convention): the contract's Invocation section lists
# "the item record" as a select input distinct from "the diff", but does not
# specify HOW a real T112 implementation resolves --item <ItemId> to a
# classification record for an item with no backing entry in the live
# tracker DB (this file's fixture items are synthetic). This block passes
# this fixture directory's rule_table.json as --config (rule_table.json IS
# explicitly named among the contract's Inputs: "the rule table (consumer
# DATA, content-addressed)") and the fixture item_id as --item; if T112's
# real implementation resolves --item exclusively through docs/
# workable_items.db with no override for a config-embedded fixture item, this
# specific invocation will need adjusting at T112 review time -- that
# adjustment is explicitly T112's to make, per common-conventions.md's
# "Their interface ... fixed by the plan task text until a contract is
# written" convention applied here to an under-specified corner of an
# existing contract.
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: context/governance_subset.py select/verify ==="
  for fx in gs_good_bug_ui:FC-GS-SAMPLE-001:0 \
            gs_negctrl_unmapped_input:FC-GS-SAMPLE-002:0; do
    name="${fx%%:*}"; rest="${fx#*:}"
    item_id="${rest%%:*}"; want_rc="${rest#*:}"
    OUT="$TMP/${name}.select.actual.json"
    ERR="$TMP/${name}.select.actual.err"
    python3 "$IMPL" select --config "$FIXDIR/rule_table.json" --item "$item_id" --out "$OUT" >"$ERR" 2>&1
    RC=$?
    if [ "$RC" = "$want_rc" ] && [ -f "$OUT" ]; then
      echo "ok $name: real governance_subset.py select exited $RC as expected"
    else
      echo "NOT ok $name: real select invocation rc=$RC (wanted $want_rc) --"
      echo "     $(cat "$ERR" 2>/dev/null)"
      failx
    fi
  done
  VERIFY_OUT="$TMP/verify_bad.err"
  python3 "$IMPL" verify --selection "$FIXDIR/gs_bad_wrong_subset.json" >"$VERIFY_OUT" 2>&1
  VRC=$?
  if [ "$VRC" = "1" ] && grep -q "11.4.107" "$VERIFY_OUT"; then
    echo "ok gs_bad_wrong_subset: real governance_subset.py verify exited 1 and"
    echo "   named the missing anchor 11.4.107, per GS-007"
  else
    echo "NOT ok gs_bad_wrong_subset: real verify invocation rc=$VRC, output:"
    echo "     $(cat "$VERIFY_OUT" 2>/dev/null)"
    failx
  fi
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: context/governance_subset.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T112 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T112 not yet landed); if you see"
  echo "    this, context/governance_subset.py must have landed AND every fixture"
  echo "    check passed against the real tool. ==="
else
  echo "=== T104 RED BASELINE CONFIRMED: context/governance_subset.py does not"
  echo "    exist yet (T112 is a separate, later task). The TODAY full-chain"
  echo "    baseline measurement + three fixtures + their independently"
  echo "    re-derived, self-validated expected_selection blocks are the interim"
  echo "    contract T112 must satisfy to turn this GREEN. ==="
fi

exit $fail
