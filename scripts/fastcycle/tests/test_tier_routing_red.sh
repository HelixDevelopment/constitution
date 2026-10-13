#!/bin/bash
# Purpose : T109 (SpecKit-004 "fast-dev-cycles", User Story 4 / Phase E) RED
#           baseline for `context/tier_route.py` (T118's own, separate,
#           later implementation task), per plan.md T-E06 ("per task class
#           with a deterministic verifier, start at the lightest tier that
#           fits the window ... escalate one tier on verifier failure;
#           calibrate on recorded outcomes; reviews are hard-excluded") and
#           tasks.md T109's own task line ("golden-bad: a review routed to
#           a cheaper tier is refused; golden: a verifier failure escalates
#           one tier; negative control: a class without a deterministic
#           verifier is never routed down"). SC-005, FR-023.
#
# NO CONTRACT FILE EXISTS for this tool. contracts/common-conventions.md's
# own "Tool map" section lists `$FC/context/tier_route.py (T-E06)` among the
# tools with "no contract in this directory ... Their interface, output and
# RED fixtures are fixed by the plan task text until a contract is written."
# Unlike T104/T108's sibling RED tests (which borrowed CLI verb names and
# field shapes from a REAL contract file, and only DEFINED the
# under-specified corners), THIS file defines the entire interface -- verb
# name included -- from plan.md T-E06 + tasks.md T109/T118's wording alone.
# Full rationale + the tier ladder + the closed wire-format vocabulary this
# file's oracle uses is documented in fixtures/tier_route/README.md -- read
# it before touching this file.
#
# CONSTITUTIONAL CONSTRAINT (binding on this test's own design, not merely
# on T118 -- read before touching this file): section 11.4.231 clause (E)
# is a HARD PIN -- code reviews (and section 11.4.211 merge-conflict
# resolution) MUST ALWAYS run on the Opus model at xhigh effort, NEVER
# tiered down by ANY mechanism, regardless of the reviewed change's
# apparent simplicity. tier_route.py's whole selection logic must NEVER be
# allowed to route a code-review-class task at all -- reviews stay outside
# its scope entirely, not merely defaulted to the top tier WITHIN it. This
# file's golden-bad fixture (tr_bad_review_routed_cheap.json) and its
# discriminator (tr_negctrl_no_verifier.json, which likewise has no
# deterministic verifier but is NOT a review and therefore is NOT refused)
# exist specifically to prove that distinction is real, not decorative.
#
# This file's checks, in order:
#   (1) absence check -- context/tier_route.py (T118) does not exist yet;
#   (2) four section-11.4.273 control needles (below);
#   (3) fixture presence (4 fixtures + README.md);
#   (4) each fixture's own `expected_route` block, independently
#       RE-DERIVED by this file's own derive_route (section 11.4.245,
#       never T118's not-yet-written code) from raw fixture fields alone,
#       cross-checked structurally against the fixture's recorded
#       expectation:
#         tr_golden_escalation.json          golden            escalate exactly one rung on a single failure
#         tr_golden_double_escalation.json   golden (bonus)     escalate exactly one rung per failure, across two failures
#         tr_bad_review_routed_cheap.json    golden-bad         a review-class task is refused outright, zero tiers considered
#         tr_negctrl_no_verifier.json        negative-control   a non-review, no-verifier class PASSES at the safe default, never refused, never routed below default
#   (5) self-validation triple discrimination (section 11.4.107(10)/
#       11.4.201(1)): golden vs golden-bad vs negative-control derive to
#       genuinely DIFFERENT structural verdicts, proving the oracle is not
#       decoration that always agrees or always disagrees;
#   (6) paired-mutation self-test (tasks.md T111's own named mutation for
#       T-E06: "route reviews by cost") -- dropping the is_review_class
#       hard-exclusion is proven, live, to flip tr_bad_review_routed_cheap.
#       json's derived verdict from refused=true to refused=false with a
#       final_tier strictly cheaper than the real, live-checked designated
#       review tier (opus) -- proving a real meta-test built against this
#       fixture, once T118 lands, would genuinely catch that mutation;
#   (7) a forward-compatible real-tool invocation block (dormant today,
#       TOOL_PRESENT=0) that, once T118 lands, drives THIS FILE'S OWN
#       provisional `route --fixture <path> --out <path>` CLI (defined in
#       fixtures/tier_route/README.md, binding-if-adopted, adjustable at
#       T118 review time if T118 chooses a different shape) against every
#       fixture and asserts its exit code and output match this file's
#       independently-derived expectation.
#
# THE GAP (verified directly, 2026-09-29 against the current working tree):
# `constitution/scripts/fastcycle/context/` holds exactly one file today,
# `anchor_citations.py` (T039, a SEPARATE, already-landed task) -- there is
# NO `tier_route.py` of any kind (T118 has not started).
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T109); T118's implementation of `context/tier_route.py` is a
# separate, later task -- this file's author never implements it. The
# independent oracle embedded below (derive_route, a fresh Python function
# written directly from plan.md T-E06 + research.md DEC-28's own wording,
# over this test's OWN fixture files -- never T118's eventual production
# code) is a DERIVED oracle per section 11.4.245, computed independently of
# whatever T118 eventually writes; it is never imported by, shared with, or
# otherwise coupled to `context/tier_route.py` so the two never collapse
# into one producer=verifier pair.
#
# Reuse, not reinvention (section 11.4.227): the golden-bad fixture's
# "cheaper than the designated review tier" claim is proven against the
# REAL, already-landed `$FC/review/review_record.py`'s own
# `DESIGNATED_TIER = "opus"` / `DESIGNATED_EFFORT = "xhigh"` module-level
# constants (control needle #4 below), never asserted from this file's own
# say-so -- reviews already have their own separate, pinned mechanism
# (review_record.py's RB-004 refusal), and this file proves tier_route.py
# must stay out of that mechanism's way entirely, never re-implement it.
#
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms):
#   #1 -- before trusting "tier_route.py is absent" as a finding, prove the
#        plain `[ -f PATH ]` relative-path check genuinely resolves paths
#        from this script's real location, by first confirming a
#        KNOWN-PRESENT sibling (lib/fc_common.py, used throughout this
#        suite) resolves true through the identical relative-path
#        construction.
#   #2 -- none of this fixture set's four synthetic `task_id` values
#        (FC-TR-SAMPLE-001..004) collide with any real item in the live
#        tracker DB (docs/workable_items.db), mirroring
#        test_governance_subset_red.sh's own fixture-id-collision
#        precaution.
#   #3 -- every constitution anchor id this file's rationale cites
#        (11.4.209, 11.4.211, 11.4.231 -- the review-tier pin and its
#        multi-track-parallelism host anchor) is genuinely present, right
#        now, in the LIVE constitution/constitution_index.yaml.
#   #4 -- review_record.py's real DESIGNATED_TIER/DESIGNATED_EFFORT module-
#        level constants are read LIVE from its actual source text (a
#        targeted regex over the real file, never a hardcoded literal
#        assumption) and confirmed to equal "opus"/"xhigh" -- the fact this
#        file's golden-bad fixture and its mutation-simulation check both
#        depend on to call `final_tier="sonnet"` genuinely "cheaper" than
#        the real, current designated review tier.
#
# Usage : bash test_tier_routing_red.sh   Exit 0 = every check below held
#         (only possible once T118 has landed `context/tier_route.py` AND
#         it satisfies every fixture's `expected_route` for real). Exit != 0
#         is the CORRECT, EXPECTED state today (2026-09-29): `context/
#         tier_route.py` genuinely does not exist yet (T118 is a separate,
#         later, not-yet-started task) -- this is the T109 RED baseline,
#         not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/tier_route"
IMPL="$FC/context/tier_route.py"
ANCHOR_INDEX="$ROOT/constitution/constitution_index.yaml"
REVIEW_RECORD="$FC/review/review_record.py"
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
  for fake_id in FC-TR-SAMPLE-001 FC-TR-SAMPLE-002 FC-TR-SAMPLE-003 FC-TR-SAMPLE-004; do
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$fake_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture id '$fake_id' collides"
      echo "     with a REAL live-tracker item -- every fixture in this suite must use"
      echo "     ids that do not exist in docs/workable_items.db"
      COLLIDED=1
    fi
  done
  if [ "$COLLIDED" = "0" ]; then
    echo "ok control needle #2: the synthetic fixture ids (FC-TR-SAMPLE-001..004) do"
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
referenced = ['11.4.209', '11.4.211', '11.4.231']
missing = sorted(set(referenced) - live_ids)
if missing:
    print('MISSING:%s' % ','.join(missing))
else:
    print('OK:%d' % len(referenced))
" "$ANCHOR_INDEX")
  case "$NEEDLE3_OUT" in
    OK:*)
      echo "ok control needle #3: all $(echo "$NEEDLE3_OUT" | cut -d: -f2) anchor ids this"
      echo "   file cites (11.4.209, 11.4.211, 11.4.231) are genuinely present in the"
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

# --- control needle #4: review_record.py's real DESIGNATED_TIER/EFFORT constants ---
if [ ! -f "$REVIEW_RECORD" ]; then
  echo "NOT ok control needle #4 BLIND: $REVIEW_RECORD absent -- cannot confirm the"
  echo "     real designated review tier this file's golden-bad fixture depends on"
  failx
else
  NEEDLE4_OUT=$(python3 -c "
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
tier_m = re.search(r'^DESIGNATED_TIER\s*=\s*\"([^\"]+)\"', text, re.MULTILINE)
eff_m = re.search(r'^DESIGNATED_EFFORT\s*=\s*\"([^\"]+)\"', text, re.MULTILINE)
if not tier_m or not eff_m:
    print('ABSENT')
else:
    print('TIER=%s EFFORT=%s' % (tier_m.group(1), eff_m.group(1)))
" "$REVIEW_RECORD")
  if [ "$NEEDLE4_OUT" = "TIER=opus EFFORT=xhigh" ]; then
    echo "ok control needle #4: review_record.py's real, live DESIGNATED_TIER/"
    echo "   DESIGNATED_EFFORT constants ARE \"opus\"/\"xhigh\" right now -- the"
    echo "   golden-bad fixture's + mutation-simulation check's \"cheaper than the"
    echo "   designated review tier\" claim is genuinely grounded, not assumed"
  else
    echo "NOT ok control needle #4 FAILED: review_record.py's real constants read"
    echo "     as '$NEEDLE4_OUT' -- expected TIER=opus EFFORT=xhigh; this file's"
    echo "     golden-bad fixture / README.md need updating to match"
    failx
  fi
fi

# --- (1) Absence check: context/tier_route.py ---
echo
echo "=== Section: context/tier_route.py absence check ==="
CONTEXT_DIR="$FC/context"
if [ -d "$CONTEXT_DIR" ]; then
  py_count=$(find "$CONTEXT_DIR" -maxdepth 1 -name '*.py' | wc -l)
  echo "-- $CONTEXT_DIR exists, holding $py_count *.py file(s) right now (T039's"
  echo "   anchor_citations.py -- a separate, already-landed task -- lives here too)"
else
  echo "-- $CONTEXT_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok context/tier_route.py now exists -- T118 has landed. The forward-"
  echo "   compatible invocation checks below will exercise it for real against"
  echo "   every fixture's expected_route block."
  TOOL_PRESENT=1
else
  echo "NOT ok context/tier_route.py is absent -- T118 (plan.md T-E06's"
  echo "     implementation task, a SEPARATE later task from this RED test) has"
  echo "     not landed yet. THIS IS THE CORRECT, EXPECTED T109 RED BASELINE --"
  echo "     the fixtures + independent derivation below stand as the interim"
  echo "     contract T118 must satisfy to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# --- Fixture files present ---
echo
echo "=== Section: fixture presence ==="
for f in README.md tr_golden_escalation.json tr_golden_double_escalation.json \
         tr_bad_review_routed_cheap.json tr_negctrl_no_verifier.json; do
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
# implementation of plan.md T-E06's own three-clause routing rule (restated
# precisely in fixtures/tier_route/README.md), written directly by this
# test's author -- never imported by nor shared with context/tier_route.py.
#
# refusal_reason is compared by PRESENCE-SHAPE only (both null, or both
# non-null), never by exact string equality: the exact wording is a
# documentary quotation of plan.md/common-conventions.md's own terms (see
# each fixture's expected_route.refusal_reason), not something this oracle
# independently re-derives word-for-word -- honestly labelled here rather
# than silently claimed as a full independent derivation of free text.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import json
import sys


def derive_route(fx, mutation=None):
    """Independent DERIVED oracle (section 11.4.245) for tier_route.py's
    routing decision, written directly from plan.md T-E06 + research.md
    DEC-28's own wording -- never T118's not-yet-written code.

    mutation=None                    -> correct routing behaviour.
    mutation='route_reviews_by_cost' -> tasks.md T111's own named paired
        mutation for T-E06: drops the is_review_class hard-exclusion so a
        review falls through to ordinary (no-verifier-class) routing like
        any other task class."""
    ladder = fx["ladder"]
    is_review = fx.get("is_review_class", False)

    if is_review and mutation != "route_reviews_by_cost":
        return {
            "refused": True,
            "refusal_reason": "review-class task hard-excluded from tier routing",
            "route_sequence": [],
            "escalations": 0,
            "final_tier": None,
        }

    if not fx.get("has_deterministic_verifier", False):
        default_tier = fx.get("default_tier", "sonnet")
        return {
            "refused": False,
            "refusal_reason": None,
            "route_sequence": [default_tier],
            "escalations": 0,
            "final_tier": default_tier,
        }

    start = fx["min_fitting_tier"]
    cur_idx = ladder.index(start)
    seq = []
    escalations = 0
    for attempt in fx["attempts"]:
        tier = attempt["tier"]
        if ladder.index(tier) != cur_idx:
            raise ValueError(
                "attempt tier %r is not the current ladder rung %r -- "
                "escalation skipped a rung" % (tier, ladder[cur_idx])
            )
        seq.append(tier)
        if attempt["verifier_result"] == "pass":
            return {
                "refused": False,
                "refusal_reason": None,
                "route_sequence": seq,
                "escalations": escalations,
                "final_tier": tier,
            }
        escalations += 1
        cur_idx += 1
        if cur_idx >= len(ladder):
            raise ValueError(
                "ladder exhausted -- explicitly out of scope for this "
                "fixture set, see fixtures/tier_route/README.md"
            )
    raise ValueError(
        "attempts sequence never reached pass or exhaustion -- malformed fixture"
    )


def _shape_match(derived, expected):
    return (
        derived["refused"] == expected["refused"]
        and derived["route_sequence"] == expected["route_sequence"]
        and derived["escalations"] == expected["escalations"]
        and derived["final_tier"] == expected["final_tier"]
        and (derived["refusal_reason"] is None) == (expected["refusal_reason"] is None)
    )


def compare_route(fx_path, mutation=None):
    with open(fx_path, encoding="utf-8") as fh:
        fx = json.load(fh)
    derived = derive_route(fx, mutation=mutation)
    expected = fx["expected_route"]
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
        result = compare_route(fx_path, mutation=mutation)
        print(json.dumps(result))
    elif cmd == "route":
        fx_path = sys.argv[2]
        mutation = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
        with open(fx_path, encoding="utf-8") as fh:
            fx = json.load(fh)
        print(json.dumps(derive_route(fx, mutation=mutation)))
    else:
        print("usage: derive.py compare|route <fixture.json> [mutation]", file=sys.stderr)
        sys.exit(2)
PYEOF

# ---------------------------------------------------------------------------
# Fixture self-consistency: each fixture's own recorded expected_route is
# independently re-derived and structurally cross-checked.
# ---------------------------------------------------------------------------
echo
echo "=== Section: independent oracle vs recorded expected_route (per fixture) ==="

check_fixture() {
  # $1 = fixture filename   $2 = human label
  local name="$1" label="$2" out match
  out=$(python3 "$TMP/derive.py" compare "$FIXDIR/$name" 2>&1)
  match=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['match'])" "$out" 2>/dev/null)
  if [ "$match" = "True" ]; then
    echo "ok $name: $label -- the independently re-derived route matches this"
    echo "   fixture's own recorded expected_route exactly (structural shape:"
    echo "   refused, route_sequence, escalations, final_tier)"
  else
    echo "NOT ok $name: $label -- derivation mismatch or error: $out"
    failx
  fi
}

check_fixture tr_golden_escalation.json "GOLDEN: a single verifier failure escalates exactly one rung"
check_fixture tr_golden_double_escalation.json "GOLDEN (bonus): escalation is one rung PER failure, never a jump to the top"
check_fixture tr_bad_review_routed_cheap.json "GOLDEN-BAD: a review-class task is refused outright"
check_fixture tr_negctrl_no_verifier.json "NEGATIVE CONTROL: a non-review, no-verifier class PASSES at the safe default"

# ---------------------------------------------------------------------------
# Self-validation triple discrimination (section 11.4.107(10)/11.4.201(1)):
# golden vs golden-bad vs negative-control must genuinely diverge.
# ---------------------------------------------------------------------------
echo
echo "=== Section: self-validation control needle -- golden/golden-bad/negative-control discriminate ==="
DISC=$(python3 -c "
import sys
sys.path.insert(0, '$TMP')
from derive import derive_route
import json

golden = json.load(open('$FIXDIR/tr_golden_escalation.json'))
bad = json.load(open('$FIXDIR/tr_bad_review_routed_cheap.json'))
neg = json.load(open('$FIXDIR/tr_negctrl_no_verifier.json'))

g = derive_route(golden)
b = derive_route(bad)
n = derive_route(neg)

# golden reaches a real (non-refused) tier via escalation from the lightest
# fitting tier; golden-bad is refused outright; negative-control reaches a
# real (non-refused) tier at the safe default with ZERO escalation and
# WITHOUT ever being routed to the lightest tier. All three combinations
# must genuinely differ from one another in at least one structural field.
all_distinct = (
    g != b
    and b != n
    and g != n
    and b['refused'] is True
    and g['refused'] is False
    and n['refused'] is False
    and n['route_sequence'] != g['route_sequence']
)
print(all_distinct)
")
if [ "$DISC" = "True" ]; then
  echo "ok discrimination: golden (escalated, refused=false), golden-bad"
  echo "   (refused=true), and negative-control (default tier, refused=false,"
  echo "   never escalated) all produce genuinely DIFFERENT structural"
  echo "   verdicts -- the oracle is not decoration that always agrees."
else
  echo "NOT ok discrimination FAILED: $DISC"
  failx
fi

# ---------------------------------------------------------------------------
# Paired-mutation self-test (tasks.md T111's own named mutation for T-E06:
# "route reviews by cost").
# ---------------------------------------------------------------------------
echo
echo "=== Section: paired-mutation self-test (tasks.md T111: 'route reviews by cost') ==="
MUT_OUT=$(python3 "$TMP/derive.py" route "$FIXDIR/tr_bad_review_routed_cheap.json" route_reviews_by_cost 2>&1)
MUT_CHECK=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
designated_tier = sys.argv[2]
result = {
    'now_refused': d['refused'],
    'final_tier': d['final_tier'],
    'flipped_from_refused_to_routed': d['refused'] is False,
    'landed_below_designated_tier': (d['final_tier'] is not None and d['final_tier'] != designated_tier),
}
print(json.dumps(result))
" "$MUT_OUT" "opus" 2>&1)
FLIPPED=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['flipped_from_refused_to_routed'])" "$MUT_CHECK" 2>/dev/null)
BELOW_DESIGNATED=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['landed_below_designated_tier'])" "$MUT_CHECK" 2>/dev/null)
if [ "$FLIPPED" = "True" ] && [ "$BELOW_DESIGNATED" = "True" ]; then
  MUT_FINAL_TIER="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['final_tier'])" "$MUT_OUT")"
  echo "ok mutation-simulation: dropping the is_review_class hard-exclusion"
  echo "   (tasks.md T111's own named mutation, 'route reviews by cost') on"
  echo "   tr_bad_review_routed_cheap.json flips its derived verdict from"
  echo "   refused=true to refused=false, landing at final_tier=$MUT_FINAL_TIER --"
  echo "   strictly cheaper than the real, live-checked designated review tier"
  echo "   ('opus', control needle #4) -- proving a real meta-test built"
  echo "   against this fixture, once T118 lands, would genuinely catch that"
  echo "   mutation."
else
  echo "NOT ok mutation-simulation FAILED: $MUT_CHECK -- the review-hard-"
  echo "     exclusion-dropping mutation did not produce a detectably worse"
  echo "     (routed, below-designated-tier) outcome; this fixture would not"
  echo "     catch that mutation and needs revising"
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# context/tier_route.py lands (T118), this block invokes THIS FILE'S OWN
# provisional `route --fixture <fixture.json> --out <route.json>` CLI
# (fixtures/tier_route/README.md -- binding-if-adopted, adjustable at T118
# review time if T118 chooses a different verb/shape, mirroring
# common-conventions.md's own "no contract exists; fixed by task text"
# convention applied here one level further up than T104/T108's own
# UNCONFIRMED corners).
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: context/tier_route.py route ==="
  for fx in tr_golden_escalation.json:0 \
            tr_golden_double_escalation.json:0 \
            tr_bad_review_routed_cheap.json:1 \
            tr_negctrl_no_verifier.json:0; do
    name="${fx%%:*}"
    want_rc="${fx##*:}"
    OUT="$TMP/${name}.route.actual.json"
    ERR="$TMP/${name}.route.actual.err"
    python3 "$IMPL" route --fixture "$FIXDIR/$name" --out "$OUT" >"$ERR" 2>&1
    RC=$?
    if [ "$RC" != "$want_rc" ]; then
      echo "NOT ok $name: real route invocation rc=$RC (wanted $want_rc) --"
      echo "     $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    if [ ! -f "$OUT" ]; then
      echo "NOT ok $name: real route invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    EXPECTED=$(python3 -c "import json; print(json.dumps(json.load(open('$FIXDIR/$name'))['expected_route']))")
    RESULT=$(python3 -c "
import json, sys
actual = json.load(open(sys.argv[1]))
expected = json.loads(sys.argv[2])
match = (
    actual.get('refused') == expected['refused']
    and actual.get('route_sequence') == expected['route_sequence']
    and actual.get('escalations') == expected['escalations']
    and actual.get('final_tier') == expected['final_tier']
    and (actual.get('refusal_reason') is None) == (expected['refusal_reason'] is None)
)
print('MATCH' if match else 'MISMATCH: actual=%r expected=%r' % (actual, expected))
" "$OUT" "$EXPECTED")
    if [ "$RESULT" = "MATCH" ]; then
      echo "ok $name: real tier_route.py route exited $RC as expected and its"
      echo "   output matches expected_route"
    else
      echo "NOT ok $name: real route invocation rc=$RC, $RESULT"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: context/tier_route.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T118 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T118 not yet landed); if you see"
  echo "    this, context/tier_route.py must have landed AND every fixture check"
  echo "    passed against the real tool. ==="
else
  echo "=== T109 RED BASELINE CONFIRMED: context/tier_route.py does not exist"
  echo "    yet (T118 is a separate, later task). The four fixtures + their"
  echo "    independently re-derived, self-validated expected_route blocks, the"
  echo "    discrimination check, and the T111-named paired-mutation proof, all"
  echo "    above, are the interim contract T118 must satisfy to turn this"
  echo "    GREEN. ==="
fi

exit $fail
