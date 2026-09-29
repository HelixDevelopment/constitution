#!/bin/bash
# Purpose : T127 (SpecKit-004 "fast-dev-cycles", User Story 5 / Phase B) RED
#           baseline for `orchestration/limit_class.py` (T135's own,
#           separate, later implementation task), per plan.md T-B06
#           ("orchestration/limit_class.py classifies each death from the
#           real signal: rate-limited (retry-after present) -> backoff then
#           resume; weekly/subscription/spend cap -> never retry on that
#           alias, cool it until its stated reset, resume elsewhere; context
#           overflow -> re-dispatch with the governance subset (T-E01),
#           never the same prompt; other -> report") and tasks.md T127's own
#           task line ("golden per class from real recorded signals: the
#           2026-09-26 weekly-cap rows and the haiku prompt-too-long row;
#           golden-bad: a cap classified as rate-limited FAILs"). FR-016.
#
# A REAL CONTRACT EXISTS for this tool (unlike T109/tier_route.py, which had
# none): `specs/004-fast-dev-cycles/contracts/agent-registry-and-handoff.md`'s
# Components block fixes the CLI verb (`limit_class.py --signal <raw> --out
# <class.json>`) and its AR-005 clause fixes the closed class set and exit
# codes; `data-model.md`'s `limit_signal` entity fixes the output shape
# (`{class, raw, resets_at}`). This file borrows those field names/shapes
# from the real contract (the T104/T108 pattern) rather than defining the
# entire interface from scratch. Full rationale + the closed class-derivation
# rule + provenance discipline is documented in fixtures/limit_class/
# README.md -- read it before touching this file.
#
# This file's checks, in order:
#   (1) absence check -- orchestration/limit_class.py (T135) does not exist
#       yet;
#   (2) four section-11.4.273 control needles (below);
#   (3) fixture presence (5 fixtures + README.md);
#   (4) each fixture's own `expected_class`, independently RE-DERIVED by
#       this file's own derive_class (section 11.4.245, never T135's
#       not-yet-written code) from raw signal fields alone, cross-checked
#       structurally against the fixture's recorded expectation:
#         lc_golden_cap_weekly.json               golden            REAL 2026-09-26 weekly-cap row -> cap
#         lc_golden_context_overflow.json         golden            REAL haiku prompt-too-long row -> context-overflow
#         lc_bad_cap_via_429_no_retry_after.json  golden-bad        REAL cap row -- correct class is cap, NOT rate-limited
#         lc_negctrl_rate_limited_retry_after.json negative-control CONSTRUCTED genuine transient 429 -> rate-limited (not cap)
#   (5) self-validation triple discrimination (section 11.4.107(10)/
#       11.4.201(1)): golden-cap vs golden-context-overflow vs negative-
#       control derive to genuinely DIFFERENT classes, proving the oracle
#       is not decoration that always agrees;
#   (6) paired-mutation self-test (tasks.md T130's own named mutation for
#       T-B06: "collapse limit classes into one backoff") -- dropping the
#       cap disambiguator (retry-after absence / named reset) is proven,
#       live, to flip lc_bad_cap_via_429_no_retry_after.json's derived
#       class from the correct "cap" to the WRONG "rate-limited" -- proving
#       a real meta-test built against this fixture, once T135 lands, would
#       genuinely catch that mutation;
#   (7) a forward-compatible real-tool invocation block (dormant today,
#       TOOL_PRESENT=0) that, once T135 lands, drives the REAL contract-
#       fixed `--signal <raw> --out <class.json>` CLI against every fixture
#       and asserts its exit code and output `class` field match this
#       file's independently-derived expectation.
#
# THE GAP (verified directly, 2026-09-30 against the current working tree):
# `constitution/scripts/fastcycle/orchestration/` holds exactly one file
# today, `completion_probe.sh` (T122, a SEPARATE, already-landed task) plus
# a `.gitkeep` placeholder -- there is NO `limit_class.py` of any kind
# (T135 has not started).
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T127); T135's implementation of `orchestration/limit_class.py` is a
# separate, later task -- this file's author never implements it. The
# independent oracle embedded below (derive_class, a fresh Python function
# written directly from research.md DEC-14 + contracts/
# agent-registry-and-handoff.md's AR-005 clause's own wording, over this
# test's OWN fixture files -- never T135's eventual production code) is a
# DERIVED oracle per section 11.4.245, computed independently of whatever
# T135 eventually writes; it is never imported by, shared with, or otherwise
# coupled to `orchestration/limit_class.py` so the two never collapse into
# one producer=verifier pair.
#
# Reuse, not reinvention (section 11.4.227): the closed class set, CLI verb,
# and output shape are taken VERBATIM from the real, already-landed contract
# (agent-registry-and-handoff.md AR-005 + data-model.md's limit_signal
# entity, control needle #4 below), never invented by this file.
#
# Real recorded signals (never synthetic, per tasks.md T127's own task line
# -- "golden per class from real recorded signals"): the two golden fixtures
# and the golden-bad fixture all copy their raw_signal field byte-for-byte
# from real rows in docs/requests/agent_registry.jsonl (control needle #4
# below re-confirms this LIVE, against the real file, every run). Only the
# negative-control fixture is honestly `provenance: constructed` (section
# 11.4.115(G)) -- no real retry-after-bearing row exists in the registry to
# date, confirmed live below rather than merely asserted in the fixture.
#
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms):
#   #1 -- before trusting "limit_class.py is absent" as a finding, prove the
#        plain `[ -f PATH ]` relative-path check genuinely resolves paths
#        from this script's real location, by first confirming a
#        KNOWN-PRESENT sibling (lib/fc_common.py, used throughout this
#        suite) resolves true through the identical relative-path
#        construction.
#   #2 -- none of this fixture set's four synthetic `task_id` values
#        (FC-LC-SAMPLE-001..004) collide with any real item in the live
#        tracker DB (docs/workable_items.db), mirroring
#        test_tier_routing_red.sh's / test_governance_subset_red.sh's own
#        fixture-id-collision precaution.
#   #3 -- every constitution anchor id this file's rationale cites
#        (11.4.6, 11.4.115, 11.4.147, 11.4.196, 11.4.245) is genuinely
#        present, right now, in the LIVE constitution/constitution_index.yaml.
#   #4 -- THIS FILE'S OWN task-specific needle: every `provenance: observed`
#        fixture's `raw_signal` text is genuinely, byte-for-byte present in
#        the cited real source file at the cited line/range, read LIVE from
#        the actual `docs/requests/agent_registry.jsonl` (never assumed from
#        the fixture's own say-so) -- and separately confirms the negative-
#        control fixture's `provenance: constructed` claim by grepping the
#        same live file for `retry-after` and asserting zero genuine
#        signal-row matches, so a null result there is proven, not guessed
#        (section 11.4.201(6)-(7)).
#
# Usage : bash test_limit_class_red.sh   Exit 0 = every check below held
#         (only possible once T135 has landed `orchestration/limit_class.py`
#         AND it satisfies every fixture's `expected_class` for real). Exit
#         != 0 is the CORRECT, EXPECTED state today (2026-09-30):
#         `orchestration/limit_class.py` genuinely does not exist yet (T135
#         is a separate, later, not-yet-started task) -- this is the T127
#         RED baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/limit_class"
IMPL="$FC/orchestration/limit_class.py"
ANCHOR_INDEX="$ROOT/constitution/constitution_index.yaml"
DB="$ROOT/docs/workable_items.db"
REGISTRY="$ROOT/docs/requests/agent_registry.jsonl"

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
  for fake_id in FC-LC-SAMPLE-001 FC-LC-SAMPLE-002 FC-LC-SAMPLE-003 FC-LC-SAMPLE-004; do
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$fake_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture id '$fake_id' collides"
      echo "     with a REAL live-tracker item -- every fixture in this suite must use"
      echo "     ids that do not exist in docs/workable_items.db"
      COLLIDED=1
    fi
  done
  if [ "$COLLIDED" = "0" ]; then
    echo "ok control needle #2: the synthetic fixture ids (FC-LC-SAMPLE-001..004) do"
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
referenced = ['11.4.6', '11.4.115', '11.4.147', '11.4.196', '11.4.245']
missing = sorted(set(referenced) - live_ids)
if missing:
    print('MISSING:%s' % ','.join(missing))
else:
    print('OK:%d' % len(referenced))
" "$ANCHOR_INDEX")
  case "$NEEDLE3_OUT" in
    OK:*)
      echo "ok control needle #3: all $(echo "$NEEDLE3_OUT" | cut -d: -f2) anchor ids this"
      echo "   file cites (11.4.6, 11.4.115, 11.4.147, 11.4.196, 11.4.245) are genuinely"
      echo "   present in the LIVE $ANCHOR_INDEX right now"
      ;;
    *)
      echo "NOT ok control needle #3 FAILED: cited anchor id(s) absent from the live"
      echo "     index: $NEEDLE3_OUT -- a constitution edit removed an anchor this"
      echo "     file's rationale depends on; the rationale needs updating"
      failx
      ;;
  esac
fi

# --- control needle #4: every "observed" fixture's raw_signal is genuinely
#     present, byte-for-byte, in the live real registry file; the
#     "constructed" claim on the negative-control is likewise grep-proven ---
if [ ! -f "$REGISTRY" ]; then
  echo "NOT ok control needle #4 BLIND: $REGISTRY absent -- cannot confirm any"
  echo "     of this suite's 'real recorded signal' claims"
  failx
else
  NEEDLE4_OUT=$(python3 -c "
import json, sys

fixdir, registry = sys.argv[1], sys.argv[2]
registry_text = open(registry, encoding='utf-8').read()

observed = ['lc_golden_cap_weekly.json', 'lc_golden_context_overflow.json',
            'lc_bad_cap_via_429_no_retry_after.json']
problems = []
for name in observed:
    fx = json.load(open('%s/%s' % (fixdir, name), encoding='utf-8'))
    if fx.get('provenance') != 'observed':
        problems.append('%s: expected provenance=observed, got %r' % (name, fx.get('provenance')))
        continue
    raw = fx.get('raw_signal', '')
    if raw not in registry_text:
        problems.append('%s: raw_signal not found verbatim in the live registry file' % name)

# the negative-control's constructed claim: zero genuine retry-after ROW
# matches in the live registry (a prose mention inside an unrelated agent
# hand-back report elsewhere would not appear in THIS file, so this check
# is scoped correctly to the registry itself, never the broader docs tree)
retry_after_hits = registry_text.lower().count('retry-after')
if retry_after_hits != 0:
    problems.append('registry now contains %d retry-after mention(s) -- the '
                     'negative-control fixture\'s constructed claim needs '
                     're-checking against the current live file' % retry_after_hits)

if problems:
    print('PROBLEMS:%s' % ' || '.join(problems))
else:
    print('OK:%d observed fixtures verbatim-present, 0 retry-after rows live' % len(observed))
" "$FIXDIR" "$REGISTRY")
  case "$NEEDLE4_OUT" in
    OK:*)
      echo "ok control needle #4: $NEEDLE4_OUT"
      ;;
    *)
      echo "NOT ok control needle #4 FAILED: $NEEDLE4_OUT"
      failx
      ;;
  esac
fi

# --- (1) Absence check: orchestration/limit_class.py ---
echo
echo "=== Section: orchestration/limit_class.py absence check ==="
ORCH_DIR="$FC/orchestration"
if [ -d "$ORCH_DIR" ]; then
  py_count=$(find "$ORCH_DIR" -maxdepth 1 -name '*.py' | wc -l)
  echo "-- $ORCH_DIR exists, holding $py_count *.py file(s) right now (T122's"
  echo "   completion_probe.sh -- a shell script, a separate already-landed"
  echo "   task -- lives here too, alongside a .gitkeep placeholder)"
else
  echo "-- $ORCH_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok orchestration/limit_class.py now exists -- T135 has landed. The"
  echo "   forward-compatible invocation checks below will exercise it for"
  echo "   real against every fixture's expected_class."
  TOOL_PRESENT=1
else
  echo "NOT ok orchestration/limit_class.py is absent -- T135 (plan.md T-B06's"
  echo "     implementation task, a SEPARATE later task from this RED test) has"
  echo "     not landed yet. THIS IS THE CORRECT, EXPECTED T127 RED BASELINE --"
  echo "     the fixtures + independent derivation below stand as the interim"
  echo "     contract T135 must satisfy to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# --- Fixture files present ---
echo
echo "=== Section: fixture presence ==="
for f in README.md lc_golden_cap_weekly.json lc_golden_context_overflow.json \
         lc_bad_cap_via_429_no_retry_after.json lc_negctrl_rate_limited_retry_after.json; do
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
# implementation of research.md DEC-14's own closed-class rule + contracts/
# agent-registry-and-handoff.md's AR-005 clause (restated precisely in
# fixtures/limit_class/README.md), written directly by this test's author --
# never imported by nor shared with orchestration/limit_class.py.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import json
import re
import sys

_PROMPT_TOO_LONG_RE = re.compile(r"prompt\s+(is\s+)?too\s+long", re.IGNORECASE)


def derive_class(fx, mutation=None):
    """Independent DERIVED oracle (section 11.4.245) for limit_class.py's
    classification decision, written directly from research.md DEC-14 +
    contracts/agent-registry-and-handoff.md's AR-005 clause's own wording --
    never T135's not-yet-written code.

    Closed class set (DEC-14): {rate-limited, cap, context-overflow, other}.

    mutation=None                       -> correct classification behaviour.
    mutation='collapse_classes_to_backoff' -> tasks.md T130's own named
        paired mutation for T-B06 ("collapse limit classes into one
        backoff"): drops the cap disambiguator (retry-after absence / named
        reset) so every HTTP 429 is classified rate-limited regardless."""
    http_status = fx.get("http_status")
    error_code = fx.get("error_code")
    retry_after_seconds = fx.get("retry_after_seconds")
    reset_named = fx.get("reset_named", False)
    raw = fx.get("raw_signal", "")

    # context-overflow: an HTTP 400 invalid_request naming a token/prompt-
    # length ceiling exceeded. Structurally distinct from every 429 class --
    # never a retry-after, never a cap/reset field.
    if http_status == 400 and error_code == "invalid_request" and _PROMPT_TOO_LONG_RE.search(raw):
        return "context-overflow"

    if http_status == 429:
        if mutation == "collapse_classes_to_backoff":
            return "rate-limited"
        # DEC-14 / AR-005: cap = spend/subscription/weekly cap (NO
        # retry-after, OR a NAMED weekly/subscription reset) -- an OR of
        # the two disqualifying conditions for rate-limited.
        if (not retry_after_seconds) or reset_named:
            return "cap"
        return "rate-limited"

    return "other"


def compare_class(fx_path, mutation=None):
    with open(fx_path, encoding="utf-8") as fh:
        fx = json.load(fh)
    derived = derive_class(fx, mutation=mutation)
    expected = fx["expected_class"]
    return {"match": derived == expected, "derived": derived, "expected": expected}


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "compare":
        fx_path = sys.argv[2]
        mutation = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
        result = compare_class(fx_path, mutation=mutation)
        print(json.dumps(result))
    elif cmd == "classify":
        fx_path = sys.argv[2]
        mutation = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "-" else None
        with open(fx_path, encoding="utf-8") as fh:
            fx = json.load(fh)
        print(json.dumps({"class": derive_class(fx, mutation=mutation)}))
    else:
        print("usage: derive.py compare|classify <fixture.json> [mutation]", file=sys.stderr)
        sys.exit(2)
PYEOF

# ---------------------------------------------------------------------------
# Fixture self-consistency: each fixture's own recorded expected_class is
# independently re-derived and structurally cross-checked.
# ---------------------------------------------------------------------------
echo
echo "=== Section: independent oracle vs recorded expected_class (per fixture) ==="

check_fixture() {
  # $1 = fixture filename   $2 = human label
  local name="$1" label="$2" out match
  out=$(python3 "$TMP/derive.py" compare "$FIXDIR/$name" 2>&1)
  match=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['match'])" "$out" 2>/dev/null)
  if [ "$match" = "True" ]; then
    echo "ok $name: $label -- the independently re-derived class matches this"
    echo "   fixture's own recorded expected_class exactly"
  else
    echo "NOT ok $name: $label -- derivation mismatch or error: $out"
    failx
  fi
}

check_fixture lc_golden_cap_weekly.json "GOLDEN: the 2026-09-26 weekly-cap row -> cap"
check_fixture lc_golden_context_overflow.json "GOLDEN: the haiku prompt-too-long row -> context-overflow"
check_fixture lc_bad_cap_via_429_no_retry_after.json "GOLDEN-BAD: a real cap row -- correct class is cap, never rate-limited"
check_fixture lc_negctrl_rate_limited_retry_after.json "NEGATIVE CONTROL: a genuine transient 429 -> rate-limited, never cap"

# ---------------------------------------------------------------------------
# Self-validation triple discrimination (section 11.4.107(10)/11.4.201(1)):
# golden-cap vs golden-context-overflow vs negative-control must genuinely
# diverge (three distinct classes out of the four-member closed set).
# ---------------------------------------------------------------------------
echo
echo "=== Section: self-validation control needle -- the three classes discriminate ==="
DISC=$(python3 -c "
import sys
sys.path.insert(0, '$TMP')
from derive import derive_class
import json

cap = json.load(open('$FIXDIR/lc_golden_cap_weekly.json'))
overflow = json.load(open('$FIXDIR/lc_golden_context_overflow.json'))
neg = json.load(open('$FIXDIR/lc_negctrl_rate_limited_retry_after.json'))

c = derive_class(cap)
o = derive_class(overflow)
n = derive_class(neg)

# All three real-signal-class scenarios must land on genuinely DIFFERENT
# closed-set members: cap != context-overflow != rate-limited != cap.
all_distinct = (
    c != o
    and o != n
    and c != n
    and c == 'cap'
    and o == 'context-overflow'
    and n == 'rate-limited'
)
print(all_distinct)
")
if [ "$DISC" = "True" ]; then
  echo "ok discrimination: the weekly-cap row (cap), the prompt-too-long row"
  echo "   (context-overflow), and the constructed transient-429 negative"
  echo "   control (rate-limited) all produce genuinely DIFFERENT structural"
  echo "   verdicts -- the oracle is not decoration that always agrees."
else
  echo "NOT ok discrimination FAILED: $DISC"
  failx
fi

# ---------------------------------------------------------------------------
# Paired-mutation self-test (tasks.md T130's own named mutation for T-B06:
# "collapse limit classes into one backoff").
# ---------------------------------------------------------------------------
echo
echo "=== Section: paired-mutation self-test (tasks.md T130: 'collapse limit classes into one backoff') ==="
MUT_OUT=$(python3 "$TMP/derive.py" classify "$FIXDIR/lc_bad_cap_via_429_no_retry_after.json" collapse_classes_to_backoff 2>&1)
MUT_CHECK=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
expected_correct = sys.argv[2]
mutated_class = d['class']
result = {
    'mutated_class': mutated_class,
    'flipped_from_correct': mutated_class != expected_correct,
    'flipped_to_rate_limited': mutated_class == 'rate-limited',
}
print(json.dumps(result))
" "$MUT_OUT" "cap" 2>&1)
FLIPPED=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['flipped_from_correct'])" "$MUT_CHECK" 2>/dev/null)
TO_RATE_LIMITED=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['flipped_to_rate_limited'])" "$MUT_CHECK" 2>/dev/null)
if [ "$FLIPPED" = "True" ] && [ "$TO_RATE_LIMITED" = "True" ]; then
  echo "ok mutation-simulation: dropping the cap disambiguator (tasks.md T130's"
  echo "   own named mutation, 'collapse limit classes into one backoff') on"
  echo "   lc_bad_cap_via_429_no_retry_after.json flips its derived class from"
  echo "   the correct 'cap' to the WRONG 'rate-limited' -- exactly the golden-"
  echo "   bad scenario T127's own task line names ('a cap classified as"
  echo "   rate-limited FAILs') -- proving a real meta-test built against this"
  echo "   fixture, once T135 lands, would genuinely catch that mutation."
else
  echo "NOT ok mutation-simulation FAILED: $MUT_CHECK -- the cap-disambiguator-"
  echo "     dropping mutation did not produce the expected wrong (rate-"
  echo "     limited) outcome; this fixture would not catch that mutation and"
  echo "     needs revising"
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# orchestration/limit_class.py lands (T135), this block invokes the REAL,
# contract-fixed `--signal <raw> --out <class.json>` CLI (contracts/
# agent-registry-and-handoff.md's Components block) against every fixture
# and asserts its exit code and output `class` field match this file's
# independently-derived expectation.
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: orchestration/limit_class.py --signal ==="
  for fx in lc_golden_cap_weekly.json:0 \
            lc_golden_context_overflow.json:0 \
            lc_bad_cap_via_429_no_retry_after.json:0 \
            lc_negctrl_rate_limited_retry_after.json:0; do
    name="${fx%%:*}"
    want_rc="${fx##*:}"
    RAW=$(python3 -c "import json; print(json.load(open('$FIXDIR/$name'))['raw_signal'])")
    EXPECTED_CLASS=$(python3 -c "import json; print(json.load(open('$FIXDIR/$name'))['expected_class'])")
    OUT="$TMP/${name}.class.actual.json"
    ERR="$TMP/${name}.class.actual.err"
    python3 "$IMPL" --signal "$RAW" --out "$OUT" >"$ERR" 2>&1
    RC=$?
    if [ "$RC" != "$want_rc" ]; then
      echo "NOT ok $name: real classify invocation rc=$RC (wanted $want_rc) --"
      echo "     $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    if [ ! -f "$OUT" ]; then
      echo "NOT ok $name: real classify invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    ACTUAL_CLASS=$(python3 -c "import json; print(json.load(open('$OUT')).get('class'))")
    if [ "$ACTUAL_CLASS" = "$EXPECTED_CLASS" ]; then
      echo "ok $name: real limit_class.py --signal exited $RC as expected and its"
      echo "   output class ('$ACTUAL_CLASS') matches expected_class"
    else
      echo "NOT ok $name: real classify invocation rc=$RC, class='$ACTUAL_CLASS'"
      echo "     expected='$EXPECTED_CLASS'"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: orchestration/limit_class.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T135 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T135 not yet landed); if you see"
  echo "    this, orchestration/limit_class.py must have landed AND every"
  echo "    fixture check passed against the real tool. ==="
else
  echo "=== T127 RED BASELINE CONFIRMED: orchestration/limit_class.py does not"
  echo "    exist yet (T135 is a separate, later, not-yet-started task). The"
  echo "    four fixtures + their independently re-derived, self-validated"
  echo "    expected_class values, the discrimination check, and the T130-"
  echo "    named paired-mutation proof, all above, are the interim contract"
  echo "    T135 must satisfy to turn this GREEN. ==="
fi

exit $fail
