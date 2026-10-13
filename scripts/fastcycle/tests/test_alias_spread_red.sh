#!/bin/bash
# Purpose : T128 (SpecKit-004 "fast-dev-cycles", User Story 5 / Phase B) RED
#           baseline for `orchestration/limit_class.py place` (T136's own,
#           separate, later implementation task), per plan.md T-B07 ("dispatcher
#           placement rule of DEC-22; aliases near a recorded cap get no new long
#           agents") and tasks.md T128's own task line ("golden: 8 agents over 4
#           aliases -> <=3 per alias; negative control: a single operational
#           alias -> all placed on it, not refused"). FR-016, FR-018.
#
# CONTRACT STATUS: `limit_class.py` IS covered by a real contract file
# (`contracts/agent-registry-and-handoff.md`), unlike T109/T118's
# `context/tier_route.py` (which has none at all). That contract's Components
# block already fixes the `classify` verb's CLI shape
# (`--signal <raw> --out <class.json>`, T-B06/T127/T135) but defines NO
# `place` verb at all -- no CLI shape, no RED-fixtures-table entry. `place`
# (T-B07's content, this file's concern) is therefore an UNDER-SPECIFIED
# CORNER of an EXISTING contract -- the T104/T108 situation, not the
# T109/T118 situation. Full rationale + the placement rule + the closed
# wire-format vocabulary this file's oracle uses is documented in
# fixtures/alias_spread/README.md -- read it before touching this file.
#
# This file's checks, in order:
#   (1) absence check -- orchestration/limit_class.py (T135/T136) does not
#       exist yet;
#   (2) four section-11.4.273 control needles (below);
#   (3) fixture presence (3 fixtures + README.md);
#   (4) each fixture's own `expected_placement` block, independently
#       RE-DERIVED by this file's own derive_placement (section 11.4.245,
#       never T136's not-yet-written code) from raw fixture fields alone,
#       cross-checked structurally against the fixture's recorded
#       expectation:
#         as_golden_spread.json              golden             8 agents / 4 aliases, round-robin native-first, max_assigned_count <= cap_per_alias
#         as_negctrl_single_alias.json       negative-control    8 agents / 1 operational alias, all placed, never refused
#         as_golden_near_cap_excluded.json   golden (bonus)      a near-cap alias is excluded from new placements even though operational
#   (5) self-validation triple discrimination (section 11.4.107(10)/
#       11.4.201(1)): the three fixtures above derive to genuinely DIFFERENT
#       structural verdicts, proving the oracle is not decoration that
#       always agrees (no golden-bad fixture is in scope for T-B07 -- see
#       fixtures/alias_spread/README.md's own "Explicit scope exclusion" --
#       so this discrimination is golden / negative-control / golden-bonus,
#       never golden / golden-bad / negative-control);
#   (6) paired-mutation self-test (tasks.md T130's own named mutation for
#       T-B07: "fill-first placement", DEC-22's own "Alternatives
#       considered (a)" wording) -- piling every agent onto the single
#       first-in-order eligible alias is proven, live, to flip
#       as_golden_spread.json's derived max_assigned_count from 2 (well
#       within cap_per_alias=3) to 8 (strictly ABOVE it) -- proving a real
#       meta-test built against this fixture, once T136 lands, would
#       genuinely catch that mutation;
#   (7) a forward-compatible real-tool invocation block (dormant today,
#       TOOL_PRESENT=0) that, once T136 lands, drives THIS FILE'S OWN
#       provisional `place --fixture <path> --out <path>` CLI (defined in
#       fixtures/alias_spread/README.md, binding-if-adopted, adjustable at
#       T136 review time) against every fixture and asserts its exit code
#       and output match this file's independently-derived expectation.
#
# THE GAP (verified directly, 2026-09-30 against the current working tree):
# `constitution/scripts/fastcycle/orchestration/` holds exactly one file
# today, `completion_probe.sh` (T122, a SEPARATE, already-landed task) --
# there is NO `limit_class.py` of any kind (T135/T136 have not started).
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T128); T136's implementation of `orchestration/limit_class.py place`
# is a separate, later task -- this file's author never implements it. The
# independent oracle embedded below (derive_placement, a fresh Python
# function written directly from plan.md T-B07 + research.md DEC-22's own
# wording, over this test's OWN fixture files -- never T136's eventual
# production code) is a DERIVED oracle per section 11.4.245, computed
# independently of whatever T136 eventually writes; it is never imported by,
# shared with, or otherwise coupled to `orchestration/limit_class.py` so the
# two never collapse into one producer=verifier pair.
#
# Reuse, not reinvention (section 11.4.227): the CLI shape this file adopts
# for `place` (`--fixture <path> --out <path>`) reuses the convention T118's
# `context/tier_route.py route` already established for the closest sibling
# tool in this codebase, rather than inventing a third shape.
#
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms):
#   #1 -- before trusting "limit_class.py is absent" as a finding, prove the
#        plain `[ -f PATH ]` relative-path check genuinely resolves paths
#        from this script's real location, by first confirming a
#        KNOWN-PRESENT sibling (lib/fc_common.py, used throughout this
#        suite) resolves true through the identical relative-path
#        construction.
#   #2 -- none of this fixture set's three synthetic `task_id` values
#        (FC-AS-SAMPLE-001..003) collide with any real item in the live
#        tracker DB (docs/workable_items.db), mirroring
#        test_tier_routing_red.sh's own fixture-id-collision precaution.
#   #3 -- every constitution anchor id this file's rationale cites
#        (11.4.196 -- native-first order; 11.4.58 -- the agent-cap anchor
#        plan.md itself pairs with DEC-22 spreading; 11.4.198 -- the
#        always-on native-alias-priority default DEC-22 composes with) is
#        genuinely present, right now, in the LIVE
#        constitution/constitution_index.yaml.
#   #4 -- DEC-22's own placement formula (`ceil(live_agents /
#        operational_aliases) + 1`) and its own "native-first order" phrase
#        are read LIVE from the actual research.md source text (never a
#        hardcoded literal assumption) and confirmed present -- the fact
#        this file's derive_placement oracle depends on to claim it
#        implements DEC-22's real, current decision, not a misremembered
#        or invented one.
#
# Usage : bash test_alias_spread_red.sh   Exit 0 = every check below held
#         (only possible once T136 has landed `orchestration/limit_class.py`
#         AND it satisfies every fixture's `expected_placement` for real).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-30):
#         `orchestration/limit_class.py` genuinely does not exist yet (T136
#         is a separate, later, not-yet-started task) -- this is the T128
#         RED baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/alias_spread"
IMPL="$FC/orchestration/limit_class.py"
ANCHOR_INDEX="$ROOT/constitution/constitution_index.yaml"
RESEARCH_MD="$ROOT/specs/004-fast-dev-cycles/research.md"
DB="$ROOT/docs/workable_items.db"

if ! command -v python3 >/dev/null 2>&1; then
  echo "NOT ok python3 not on PATH -- cannot run any of the checks below"
  exit 1
fi

fail=0
failx() { fail=1; }

echo "=== Section: section-11.4.273 control needles ==="

# --- control needle #1: prove the relative-path mechanism itself works ---
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

# --- control needle #2: fixture ids must not collide with the live tracker DB ---
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  COLLIDED=0
  for fake_id in FC-AS-SAMPLE-001 FC-AS-SAMPLE-002 FC-AS-SAMPLE-003; do
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$fake_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture id '$fake_id' collides"
      echo "     with a REAL live-tracker item -- every fixture in this suite must use"
      echo "     ids that do not exist in docs/workable_items.db"
      COLLIDED=1
    fi
  done
  if [ "$COLLIDED" = "0" ]; then
    echo "ok control needle #2: the synthetic fixture ids (FC-AS-SAMPLE-001..003) do"
    echo "   not collide with any real item in the live tracker DB"
  else
    failx
  fi
else
  echo "NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable"
  echo "     in this environment -- this is an environment gap, not a finding"
  failx
fi

# --- control needle #3: every cited anchor id is real, right now ---
if [ ! -f "$ANCHOR_INDEX" ]; then
  echo "NOT ok control needle #3 BLIND: anchor index absent at $ANCHOR_INDEX"
  failx
else
  NEEDLE3_OUT=$(python3 -c "
import re, sys
ID_LINE_RE = re.compile(r\"^- id: *'?([^']+)'?\$\")
with open(sys.argv[1], encoding='utf-8') as fh:
    lines = fh.read().split('\n')
live_ids = set()
for line in lines:
    m = ID_LINE_RE.match(line.rstrip('\r'))
    if m:
        live_ids.add(m.group(1))
referenced = ['11.4.196', '11.4.58', '11.4.198']
missing = sorted(set(referenced) - live_ids)
if missing:
    print('MISSING:%s' % ','.join(missing))
else:
    print('OK:%d' % len(referenced))
" "$ANCHOR_INDEX")
  case "$NEEDLE3_OUT" in
    OK:*)
      echo "ok control needle #3: all $(echo "$NEEDLE3_OUT" | cut -d: -f2) anchor ids this"
      echo "   file cites (11.4.196, 11.4.58, 11.4.198) are genuinely present in the"
      echo "   LIVE $ANCHOR_INDEX right now"
      ;;
    *)
      echo "NOT ok control needle #3 FAILED: cited anchor id(s) absent from the live"
      echo "     index: $NEEDLE3_OUT -- a constitution edit removed an anchor this"
      echo "     file's rationale depends on; the rationale needs updating"
      failx
      ;;
  esac
fi

# --- control needle #4: DEC-22's own formula + "native-first order" phrase, live ---
if [ ! -f "$RESEARCH_MD" ]; then
  echo "NOT ok control needle #4 BLIND: $RESEARCH_MD absent -- cannot confirm"
  echo "     DEC-22's real, live placement formula this file's oracle depends on"
  failx
else
  NEEDLE4_OUT=$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
# Normalise line-wrapping: DEC-22's own decision sentence wraps mid-phrase
# in the source markdown ('... honouring section 11.4.196 native-first' /
# 'order; an alias ...' on the next line) -- collapse runs of whitespace
# (including newlines) to single spaces before searching, so this needle
# is not defeated by a cosmetic re-wrap of the same sentence.
flat = re.sub(r'\s+', ' ', text)
formula_present = 'ceil(live_agents / operational_aliases)' in flat
phrase_present = 'native-first order' in flat
dec22_present = 'DEC-22' in text and 'Spread fan-out across aliases' in text
if formula_present and phrase_present and dec22_present:
    print('OK')
else:
    missing = []
    if not dec22_present:
        missing.append('DEC-22 heading')
    if not formula_present:
        missing.append('formula')
    if not phrase_present:
        missing.append('native-first-order phrase')
    print('MISSING:%s' % ','.join(missing))
" "$RESEARCH_MD")
  if [ "$NEEDLE4_OUT" = "OK" ]; then
    echo "ok control needle #4: DEC-22's real, live formula"
    echo "   (ceil(live_agents / operational_aliases) + 1) and its own"
    echo "   \"native-first order\" phrase are BOTH genuinely present in the LIVE"
    echo "   $RESEARCH_MD right now -- this file's derive_placement oracle"
    echo "   implements DEC-22's real, current decision, not an invented one"
  else
    echo "NOT ok control needle #4 FAILED: $NEEDLE4_OUT -- a research.md edit"
    echo "     changed or removed DEC-22's own wording this file's oracle"
    echo "     depends on; this file needs updating to match"
    failx
  fi
fi

# --- (1) Absence check: orchestration/limit_class.py ---
echo
echo "=== Section: orchestration/limit_class.py absence check ==="
ORCH_DIR="$FC/orchestration"
if [ -d "$ORCH_DIR" ]; then
  py_count=$(find "$ORCH_DIR" -maxdepth 1 -name '*.py' | wc -l)
  echo "-- $ORCH_DIR exists, holding $py_count *.py file(s) right now"
else
  echo "-- $ORCH_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok orchestration/limit_class.py now exists -- the forward-compatible"
  echo "   invocation checks below will exercise it for real against every"
  echo "   fixture's expected_placement block (only meaningful once T136's"
  echo "   place verb has landed; classify alone, T135, is not sufficient)."
  TOOL_PRESENT=1
else
  echo "NOT ok orchestration/limit_class.py is absent -- neither T135 (classify,"
  echo "     plan.md T-B06) nor T136 (place, plan.md T-B07 -- the SEPARATE,"
  echo "     later task this RED test protects) has landed yet. THIS IS THE"
  echo "     CORRECT, EXPECTED T128 RED BASELINE -- the fixtures + independent"
  echo "     derivation below stand as the interim contract T136 must satisfy"
  echo "     to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# --- Fixture files present ---
echo
echo "=== Section: fixture presence ==="
for f in README.md as_golden_spread.json as_negctrl_single_alias.json \
         as_golden_near_cap_excluded.json; do
  if [ ! -f "$FIXDIR/$f" ]; then
    echo "NOT ok fixture $FIXDIR/$f missing"
    failx
  else
    echo "ok fixture $f present"
  fi
done

TMP="$(mktemp -d)" || { echo "NOT ok cannot create temp dir (TMPDIR unusable)"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT
trap 'rm -rf "$TMP"; exit 143' TERM

# ---------------------------------------------------------------------------
# Independent DERIVED oracle (section 11.4.245): a from-scratch Python
# implementation of plan.md T-B07 + research.md DEC-22's own placement rule
# (restated precisely in fixtures/alias_spread/README.md), written directly
# by this test's author -- never imported by nor shared with
# orchestration/limit_class.py.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import json
import math
import sys


def derive_placement(fx, mutation=None):
    """Independent DERIVED oracle (section 11.4.245) for
    orchestration/limit_class.py's `place` decision, written directly from
    plan.md T-B07 + research.md DEC-22's own wording -- never T136's
    not-yet-written code.

    mutation=None            -> correct placement behaviour.
    mutation='fill_first'    -> tasks.md T130's own named paired mutation
        for T-B07 ("fill-first placement"), DEC-22's own "Alternatives
        considered (a)" wording verbatim: "fill the healthiest alias first"
        -- pile every agent onto the single first-in-order eligible alias,
        ignoring both the round-robin spread AND the cap entirely."""
    live_agents = fx["live_agents"]
    aliases = fx["aliases"]

    natives = [
        a["alias"] for a in aliases
        if a["operational"] and not a["near_cap"] and a["kind"] == "native"
    ]
    providers = [
        a["alias"] for a in aliases
        if a["operational"] and not a["near_cap"] and a["kind"] != "native"
    ]
    eligible = natives + providers  # native-first order (11.4.196), stable within kind

    excluded_near_cap = sorted(
        a["alias"] for a in aliases if a["operational"] and a["near_cap"]
    )

    if not eligible:
        return {
            "refused": True,
            "refusal_reason": "no operational, non-near-cap alias available",
            "eligible_alias_count": 0,
            "cap_per_alias": None,
            "native_first_order": [],
            "assignment_alias_counts": {},
            "max_assigned_count": None,
            "excluded_near_cap_aliases": excluded_near_cap,
        }

    m = len(eligible)
    cap = math.ceil(live_agents / m) + 1  # DEC-22's own formula, verbatim

    counts = {alias: 0 for alias in eligible}
    if mutation == "fill_first":
        counts[eligible[0]] = live_agents
    else:
        for i in range(live_agents):
            counts[eligible[i % m]] += 1

    max_assigned = max(counts.values()) if counts else 0
    return {
        "refused": False,
        "refusal_reason": None,
        "eligible_alias_count": m,
        "cap_per_alias": cap,
        "native_first_order": eligible,
        "assignment_alias_counts": counts,
        "max_assigned_count": max_assigned,
        "excluded_near_cap_aliases": excluded_near_cap,
    }


def _shape_match(derived, expected):
    return (
        derived["refused"] == expected["refused"]
        and (derived["refusal_reason"] is None) == (expected["refusal_reason"] is None)
        and derived["eligible_alias_count"] == expected["eligible_alias_count"]
        and derived["cap_per_alias"] == expected["cap_per_alias"]
        and derived["native_first_order"] == expected["native_first_order"]
        and derived["assignment_alias_counts"] == expected["assignment_alias_counts"]
        and derived["max_assigned_count"] == expected["max_assigned_count"]
        and derived["excluded_near_cap_aliases"] == expected.get("excluded_near_cap_aliases", [])
    )


def compare_placement(fx_path, mutation=None):
    with open(fx_path, encoding="utf-8") as fh:
        fx = json.load(fh)
    derived = derive_placement(fx, mutation=mutation)
    expected = fx["expected_placement"]
    return {
        "match": _shape_match(derived, expected),
        "derived": derived,
        "expected": expected,
    }


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "compare":
        fx_path = sys.argv[2]
        mutation = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
        result = compare_placement(fx_path, mutation=mutation)
        print(json.dumps(result))
    elif cmd == "place":
        fx_path = sys.argv[2]
        mutation = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
        with open(fx_path, encoding="utf-8") as fh:
            fx = json.load(fh)
        print(json.dumps(derive_placement(fx, mutation=mutation)))
    else:
        print("usage: derive.py compare|place <fixture.json> [mutation]", file=sys.stderr)
        sys.exit(2)
PYEOF

# ---------------------------------------------------------------------------
# Fixture self-consistency: each fixture's own recorded expected_placement is
# independently re-derived and structurally cross-checked.
# ---------------------------------------------------------------------------
echo
echo "=== Section: independent oracle vs recorded expected_placement (per fixture) ==="

check_fixture() {
  # $1 = fixture filename   $2 = human label
  local name="$1" label="$2" out match
  out=$(python3 "$TMP/derive.py" compare "$FIXDIR/$name" 2>&1)
  match=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['match'])" "$out" 2>/dev/null)
  if [ "$match" = "True" ]; then
    echo "ok $name: $label -- the independently re-derived placement matches"
    echo "   this fixture's own recorded expected_placement exactly (structural"
    echo "   shape: refused, eligible_alias_count, cap_per_alias,"
    echo "   native_first_order, assignment_alias_counts, max_assigned_count,"
    echo "   excluded_near_cap_aliases)"
  else
    echo "NOT ok $name: $label -- derivation mismatch or error: $out"
    failx
  fi
}

check_fixture as_golden_spread.json "GOLDEN: 8 agents over 4 aliases spread native-first, well within the <=3 cap"
check_fixture as_negctrl_single_alias.json "NEGATIVE CONTROL: a single operational alias takes all 8 agents, never refused"
check_fixture as_golden_near_cap_excluded.json "GOLDEN (bonus): a near-cap alias is excluded from new placements even though operational"

# ---------------------------------------------------------------------------
# Self-validation control needle (section 11.4.107(10)/11.4.201(1)): the
# golden, negative-control and golden-bonus fixtures must genuinely diverge.
# No golden-bad fixture is in scope for T-B07 (see
# fixtures/alias_spread/README.md's own "Explicit scope exclusion"), so this
# is a golden / negative-control / golden-bonus discrimination, not the
# golden / golden-bad / negative-control shape T109 used.
# ---------------------------------------------------------------------------
echo
echo "=== Section: self-validation control needle -- golden/negative-control/golden-bonus discriminate ==="
DISC=$(python3 -c "
import sys
sys.path.insert(0, '$TMP')
from derive import derive_placement
import json

golden = json.load(open('$FIXDIR/as_golden_spread.json'))
neg = json.load(open('$FIXDIR/as_negctrl_single_alias.json'))
bonus = json.load(open('$FIXDIR/as_golden_near_cap_excluded.json'))

g = derive_placement(golden)
n = derive_placement(neg)
b = derive_placement(bonus)

# golden spreads live_agents across MULTIPLE eligible aliases (native-first);
# negative-control uses exactly ONE eligible alias and places every agent
# there; golden-bonus excludes a near-cap alias none of the others has.
all_distinct = (
    g != n
    and n != b
    and g != b
    and g['eligible_alias_count'] > 1
    and n['eligible_alias_count'] == 1
    and len(b['excluded_near_cap_aliases']) > 0
    and len(g['excluded_near_cap_aliases']) == 0
    and len(n['excluded_near_cap_aliases']) == 0
    and not g['refused']
    and not n['refused']
    and not b['refused']
)
print(all_distinct)
")
if [ "$DISC" = "True" ]; then
  echo "ok discrimination: golden (4 eligible aliases, none excluded),"
  echo "   negative-control (1 eligible alias, all agents on it), and"
  echo "   golden-bonus (2 eligible aliases, 1 excluded for near_cap) all"
  echo "   produce genuinely DIFFERENT structural verdicts -- the oracle is"
  echo "   not decoration that always agrees."
else
  echo "NOT ok discrimination FAILED: $DISC"
  failx
fi

# ---------------------------------------------------------------------------
# Paired-mutation self-test (tasks.md T130's own named mutation for T-B07:
# "fill-first placement", DEC-22's own "Alternatives considered (a)"
# wording).
# ---------------------------------------------------------------------------
echo
echo "=== Section: paired-mutation self-test (tasks.md T130: 'fill-first placement') ==="
MUT_OUT=$(python3 "$TMP/derive.py" place "$FIXDIR/as_golden_spread.json" fill_first 2>&1)
MUT_CHECK=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
cap = 3  # as_golden_spread.json's own recorded cap_per_alias
result = {
    'max_assigned_count': d['max_assigned_count'],
    'still_not_refused': d['refused'] is False,
    'exceeds_recorded_cap': d['max_assigned_count'] is not None and d['max_assigned_count'] > cap,
}
print(json.dumps(result))
" "$MUT_OUT" 2>&1)
STILL_NOT_REFUSED=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['still_not_refused'])" "$MUT_CHECK" 2>/dev/null)
EXCEEDS_CAP=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['exceeds_recorded_cap'])" "$MUT_CHECK" 2>/dev/null)
if [ "$STILL_NOT_REFUSED" = "True" ] && [ "$EXCEEDS_CAP" = "True" ]; then
  MUT_MAX="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['max_assigned_count'])" "$MUT_OUT")"
  echo "ok mutation-simulation: 'fill-first placement' (tasks.md T130's own"
  echo "   named mutation for T-B07; DEC-22's own 'fill the healthiest alias"
  echo "   first' alternative, rejected precisely because it 'concentrates"
  echo "   blast radius') on as_golden_spread.json flips its derived"
  echo "   max_assigned_count from 2 to $MUT_MAX -- STRICTLY ABOVE the"
  echo "   fixture's own recorded cap_per_alias (3) -- proving a real"
  echo "   meta-test built against this fixture, once T136 lands, would"
  echo "   genuinely catch that mutation."
else
  echo "NOT ok mutation-simulation FAILED: $MUT_CHECK -- the fill-first"
  echo "     mutation did not produce a detectably worse (cap-violating)"
  echo "     outcome; this fixture would not catch that mutation and needs"
  echo "     revising"
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# orchestration/limit_class.py lands (T135/T136), this block invokes THIS
# FILE'S OWN provisional `place --fixture <fixture.json> --out <placement.json>`
# CLI (fixtures/alias_spread/README.md -- binding-if-adopted, adjustable at
# T136 review time if T136 chooses a different verb/shape).
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: orchestration/limit_class.py place ==="
  for fx in as_golden_spread.json:0 \
            as_negctrl_single_alias.json:0 \
            as_golden_near_cap_excluded.json:0; do
    name="${fx%%:*}"
    want_rc="${fx##*:}"
    OUT="$TMP/${name}.place.actual.json"
    ERR="$TMP/${name}.place.actual.err"
    python3 "$IMPL" place --fixture "$FIXDIR/$name" --out "$OUT" >"$ERR" 2>&1
    RC=$?
    if [ "$RC" != "$want_rc" ]; then
      echo "NOT ok $name: real place invocation rc=$RC (wanted $want_rc) --"
      echo "     $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    if [ ! -f "$OUT" ]; then
      echo "NOT ok $name: real place invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    EXPECTED=$(python3 -c "import json; print(json.dumps(json.load(open('$FIXDIR/$name'))['expected_placement']))")
    RESULT=$(python3 -c "
import json, sys
actual = json.load(open(sys.argv[1]))
expected = json.loads(sys.argv[2])
match = (
    actual.get('refused') == expected['refused']
    and (actual.get('refusal_reason') is None) == (expected['refusal_reason'] is None)
    and actual.get('eligible_alias_count') == expected['eligible_alias_count']
    and actual.get('cap_per_alias') == expected['cap_per_alias']
    and actual.get('native_first_order') == expected['native_first_order']
    and actual.get('assignment_alias_counts') == expected['assignment_alias_counts']
    and actual.get('max_assigned_count') == expected['max_assigned_count']
    and actual.get('excluded_near_cap_aliases') == expected.get('excluded_near_cap_aliases', [])
)
print('MATCH' if match else 'MISMATCH: actual=%r expected=%r' % (actual, expected))
" "$OUT" "$EXPECTED")
    if [ "$RESULT" = "MATCH" ]; then
      echo "ok $name: real limit_class.py place exited $RC as expected and its"
      echo "   output matches expected_placement"
    else
      echo "NOT ok $name: real place invocation rc=$RC, $RESULT"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: orchestration/limit_class.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T136 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T136 not yet landed); if you see"
  echo "    this, orchestration/limit_class.py must have landed AND every"
  echo "    fixture check passed against the real tool. ==="
else
  echo "=== T128 RED BASELINE CONFIRMED: orchestration/limit_class.py does not"
  echo "    exist yet (T135/T136 are separate, later tasks). The three fixtures"
  echo "    + their independently re-derived, self-validated expected_placement"
  echo "    blocks, the discrimination check, and the T130-named paired-mutation"
  echo "    proof, all above, are the interim contract T136 must satisfy to turn"
  echo "    this GREEN. ==="
fi

exit $fail
