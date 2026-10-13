#!/bin/bash
# Purpose : T126 (SpecKit-004 "fast-dev-cycles", User Story 5) RED baseline
#           for `orchestration/handoff.py resume-check` (T134's own, separate,
#           later implementation task), per plan.md T-B05 and contract
#           contracts/agent-registry-and-handoff.md ("Before the resumed
#           agent acts, resume-check re-hashes every external_dep; mismatches
#           list the verified facts that must be re-verified ... and the
#           effects_performed that must not be repeated" -- HO-003).
#
# tasks.md T126's own task line, as committed at HEAD when this test was
# authored (2026-09-30): "RED test
# constitution/scripts/fastcycle/tests/test_resume_revalidate_red.sh (the
# five 'Safe to Resume?' fixtures -- inconsistent internal state, stale
# external dependency, nondeterministic replay, unrecorded external effect,
# inconsistent transition -- each caught; negative control -- the CT-5
# addition: a resume with every dependency unchanged proceeds without
# re-verification)".
#
# THE FIVE FAILURE CLASSES this file's fixtures target come directly from
# research.md DEC-34's own citation: "Safe to Resume?" https://arxiv.org/
# abs/2608.29381 (R5:75) -- "Test matrix includes the five 'Safe to Resume?'
# failure modes (inconsistent internal state, stale external dependency,
# nondeterministic replay, unrecorded external effect, inconsistent
# transition)." The paper gives NO prescriptive fix for these five classes
# (research.md DEC-34: "the paper gives no prescriptive fix, so the
# revalidation design here is original") -- so this file's independently
# DERIVED oracle (below) is this project's OWN original interim contract for
# what a correct `resume-check` must catch, exactly matching the house
# convention already established in fixtures/evidence_ref/README.md and
# test_governance_subset_red.sh's own "UNCONFIRMED... DEFINED here" sections.
#
# THE GAP (verified directly, 2026-09-30 against the current working tree):
# `constitution/scripts/fastcycle/orchestration/` holds exactly one file
# today, `completion_probe.sh` (T122, a SEPARATE, already-landed task) --
# there is NO `handoff.py` of any kind (T133/T134 have not started).
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T126); T134's implementation of `orchestration/handoff.py
# resume-check` is a separate, later task -- this file's author never
# implements it. The independent oracle embedded below (derive_resume_check,
# a fresh Python implementation of the contract's HO-003 rule plus this
# file's own five-class extension, written directly from data-model.md
# section 9.2 / contracts/agent-registry-and-handoff.md / research.md
# DEC-34's cited failure modes, over this test's OWN fixture directory tree
# -- never T134's eventual production code) is a DERIVED oracle per section
# 11.4.245, computed independently of whatever T134 eventually writes; it is
# never imported by, shared with, or otherwise coupled to
# `orchestration/handoff.py` so the two never collapse into one
# producer=verifier pair.
#
# Reuse, not reinvention (section 11.4.227): the merkle-over-sorted-
# (path,content_address)-pairs convention this file's `merkle_over_dir()`
# uses to detect a stale external dependency is the SAME convention already
# established (extending fc_common.py's C-002 canon()/body-hash) in
# test_evidence_ref_red.sh's own `merkle_root()` -- reimplemented
# independently here (never imported), per the same producer!=verifier
# discipline that file already documents for itself.
#
# Wire format (UNCONFIRMED by the contract itself -- DEFINED here,
# binding-if-adopted on T134, exactly per the established house precedent):
# each fixture's handoff.json adds a `phase` tag to individual `verified`
# entries (not part of the canonical Evidence Reference schema in
# data-model.md section 8) so this test's independent oracle can derive
# "the last phase the agent's own verified evidence actually confirmed" for
# the inconsistent-transition check -- a genuinely necessary field for ANY
# implementation of that check, since deriving it from evidence-reference
# ids alone is ambiguous without such a tag. Full rationale for the derived
# `resume_check` result shape ({handoff_id, safe_to_resume_without_
# reverification, unsafe_reasons: [{class, detail}], facts_needing_
# reverification, effects_not_to_repeat}) is documented inline in the
# derive.py heredoc below and in each fixture's scenario.json.
#
# This file's checks, in order:
#   (1) absence check -- orchestration/handoff.py (T133/T134) does not
#       exist yet;
#   (2) two section-11.4.273 control needles (below);
#   (3) the five "Safe to Resume?" failure-class fixtures, each caught, via
#       an independent DERIVED oracle (never T134's not-yet-written code):
#         rr_inconsistent_internal_state    golden-bad  -> UNSAFE (a verified
#             fact's established_at is causally AFTER the handoff's own
#             written_at)
#         rr_stale_external_dependency      golden-bad  -> UNSAFE, names the
#             affected verified fact needing re-verification
#         rr_nondeterministic_replay        golden-bad  -> UNSAFE, names the
#             pending step that cannot be blindly replayed
#         rr_unrecorded_external_effect     golden-bad  -> UNSAFE, names the
#             real effect missing from effects_performed
#         rr_inconsistent_transition        golden-bad  -> UNSAFE, names the
#             skipped phases with no verified evidence
#         rr_negctrl_all_unchanged          negative-control (CT-5, this
#             task's own explicit addition) -> SAFE, zero flags, resume
#             proceeds WITHOUT forced re-verification
#   (4) discrimination check: each golden-bad fixture's expected verdict
#       carries EXACTLY its own target failure class and no other, proving
#       the oracle genuinely discriminates rather than flagging everything
#       (section 11.4.107(10)/11.4.201(1));
#   (5) five paired mutations (one per failure class, this file's own,
#       section 1.1): disabling any ONE of the five checks makes its
#       corresponding fixture wrongly report SAFE -- proving a real
#       meta-test built against these fixtures, once T134 lands, would
#       genuinely catch dropping that check;
#   (6) a forward-compatible real-tool invocation block (dormant today,
#       TOOL_PRESENT=0) that, once `orchestration/handoff.py` lands, drives
#       its real `resume-check` subcommand against every fixture and asserts
#       its exit code (0 ok / 1 hash-mismatch-or-missing-field per the
#       contract's Exit codes section) and JSON output match this file's
#       independently-derived expectation.
#
# Usage : bash test_resume_revalidate_red.sh   Exit 0 = every real assertion
#         below held (both control needles, the absence check, the six
#         fixtures via the derived oracle, the discrimination check, and all
#         five paired mutations).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-30):
#         `orchestration/handoff.py` genuinely does not exist yet (T133/T134
#         are separate, later, not-yet-started tasks) -- this is the T126 RED
#         baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/resume_revalidate"
IMPL="$FC/orchestration/handoff.py"
KNOWN_PRESENT="$FC/orchestration/completion_probe.sh"
DB="$ROOT/docs/workable_items.db"

SCENARIOS="rr_inconsistent_internal_state rr_stale_external_dependency rr_nondeterministic_replay rr_unrecorded_external_effect rr_inconsistent_transition rr_negctrl_all_unchanged"

fail=0
failx() { fail=1; }

# --- section-11.4.273 control needle #1: prove the relative-path mechanism itself works ---
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file inside"
  echo "     the SAME orchestration/ directory ($KNOWN_PRESENT, T122) does not"
  echo "     resolve -- this test's relative-path computation is broken, so"
  echo "     the absence check below proves nothing (section 11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling in orchestration/"
  echo "   (completion_probe.sh, T122) resolves through this test's own"
  echo "   path construction -- the absence check below can be trusted"
fi

# --- section-11.4.273 control needle #2: fixture item_ids must not collide with the live tracker DB ---
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  collide=0
  for scen in $SCENARIOS; do
    item_id=$(python3 -c "import json; print(json.load(open('$FIXDIR/$scen/handoff.json'))['item_id'])" 2>/dev/null)
    if [ -z "$item_id" ]; then
      echo "NOT ok control needle #2 BLIND: could not read item_id from $scen/handoff.json"
      failx
      continue
    fi
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$item_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture item_id '$item_id'"
      echo "     collides with a REAL live-tracker item -- every fixture in this"
      echo "     suite must use ids that do not exist in docs/workable_items.db"
      collide=1
      failx
    fi
  done
  if [ "$collide" = 0 ]; then
    echo "ok control needle #2: none of the six synthetic fixture item_id"
    echo "   values collide with any real item in the live tracker DB"
  fi
else
  echo "NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is"
  echo "     unavailable in this environment -- this is an environment gap,"
  echo "     not a finding"
  failx
fi

# --- (1) Absence check: orchestration/handoff.py ---
ORCH_DIR="$FC/orchestration"
if [ -d "$ORCH_DIR" ]; then
  py_count=$(find "$ORCH_DIR" -maxdepth 1 -name '*.py' | wc -l)
  sh_count=$(find "$ORCH_DIR" -maxdepth 1 -name '*.sh' | wc -l)
  echo "-- $ORCH_DIR exists, holding $py_count *.py + $sh_count *.sh file(s)"
  echo "   right now (T122's completion_probe.sh -- a separate,"
  echo "   already-landed task -- lives here too)"
else
  echo "-- $ORCH_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok orchestration/handoff.py now exists -- T133/T134 have landed. The"
  echo "   forward-compatible invocation checks below will exercise its real"
  echo "   resume-check subcommand for every fixture."
  TOOL_PRESENT=1
else
  echo "NOT ok orchestration/handoff.py is absent -- T133/T134 (plan.md"
  echo "     T-B04/T-B05's implementation tasks, SEPARATE later tasks from"
  echo "     this RED test) have not landed yet. THIS IS THE CORRECT,"
  echo "     EXPECTED T126 RED BASELINE -- the fixtures + independent"
  echo "     derivation below stand as the interim contract T134 must"
  echo "     satisfy to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# --- Fixture files present ---
for scen in $SCENARIOS; do
  for f in handoff.json expected_verdict.json scenario.json; do
    if [ ! -f "$FIXDIR/$scen/$f" ]; then
      echo "NOT ok fixture $scen/$f missing"
      failx
    fi
  done
done
echo "ok all six scenario directories carry handoff.json + expected_verdict.json + scenario.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Independent DERIVED oracle (section 11.4.245): a from-scratch Python
# re-implementation of the contract's HO-003 rule plus this file's own
# five-class extension of the "Safe to Resume?" framework (research.md
# DEC-34), written directly by THIS test's author, over THIS test's own
# fixture directories -- never imported by nor shared with
# orchestration/handoff.py (the tool under test, which does not exist yet).
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import hashlib
import json
import os
import sys

# This test's own interim phase-order definition (UNCONFIRMED by the
# contract, DEFINED here -- see the header comment "Wire format" section).
PHASE_ORDER = ["PLAN", "IMPLEMENT", "VERIFY", "DEPLOY", "DONE"]
TERMINAL_PHASES = {"DONE"}
# Closed keyword set for detecting a nondeterministic pending step (this
# test's own interim definition; a real implementation might instead carry
# an explicit `deterministic: bool` field on each pending entry -- either
# design must catch this fixture).
ND_KEYWORDS = ("llm-generate", "llm-generated", "random", "nondeterministic", "non-deterministic")


def content_address(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def canon(obj):
    """Reuses fc_common.py's own canon() convention (sort_keys, no
    insignificant whitespace, ensure_ascii=False) -- section 11.4.227
    extend-don't-invent -- reimplemented independently rather than
    imported, so this file's oracle never shares code with
    orchestration/handoff.py (the tool under test)."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def merkle_over_dir(root):
    """data-model.md section 8's MerkleRoot convention, reused here (per
    test_evidence_ref_red.sh's own merkle_root() precedent, reimplemented
    independently, section 11.4.227) over a directory tree standing in for
    an external_dep of kind git-tree: sha256 over the sorted (bytewise, by
    path) list of (relative-path, content_address) pairs."""
    pairs = []
    if os.path.isdir(root):
        for dirpath, _dirnames, filenames in os.walk(root):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, root)
                pairs.append((rel.replace(os.sep, "/"), content_address(full)))
    pairs.sort(key=lambda p: p[0].encode("utf-8"))
    body = [[p, c] for p, c in pairs]
    return "sha256:" + hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


def derive_resume_check(fixture_dir, skip_internal_state=False, skip_external_dep=False,
                         skip_nondeterminism=False, skip_unrecorded_effect=False,
                         skip_transition=False):
    """The five "Safe to Resume?" checks (research.md DEC-34), each
    independently disable-able via its skip_* flag so this file's own
    paired-mutation proofs (section below "Paired mutations") can show each
    one is genuinely load-bearing."""
    with open(os.path.join(fixture_dir, "handoff.json"), encoding="utf-8") as fh:
        handoff = json.load(fh)

    reasons = []
    reverify = set()

    # (1) INCONSISTENT INTERNAL STATE: a verified fact's own established_at
    # is causally AFTER the handoff's own written_at (the record could not
    # have known about a fact from its own future), OR the phase is
    # declared terminal while pending work remains outstanding.
    if not skip_internal_state:
        written_at = handoff["written_at"]
        for v in handoff.get("verified", []):
            if v["established_at"] > written_at:
                reasons.append({
                    "class": "inconsistent-internal-state",
                    "detail": ("verified fact %s established_at %s is AFTER the handoff's "
                               "own written_at %s (causally impossible -- the record cannot "
                               "be trusted)") % (v["ref_id"], v["established_at"], written_at),
                })
        if handoff.get("phase") in TERMINAL_PHASES and handoff.get("pending"):
            reasons.append({
                "class": "inconsistent-internal-state",
                "detail": "phase %s is terminal but pending is non-empty" % handoff.get("phase"),
            })

    # (2) STALE EXTERNAL DEPENDENCY: an external_dep's live content_address
    # (recomputed over tree_current/<locator>, standing in for the real
    # target at resume time) no longer matches the recorded one (a commit
    # landed on the branch between crash and resume).
    if not skip_external_dep:
        for dep in handoff.get("external_deps", []):
            if dep.get("kind") == "git-tree":
                current_dir = os.path.join(fixture_dir, "tree_current", dep["locator"])
                live_hash = merkle_over_dir(current_dir)
                recorded = dep["content_address"]
                if live_hash != recorded:
                    reasons.append({
                        "class": "stale-external-dependency",
                        "detail": "external dep %s content_address changed: recorded=%s live=%s" % (
                            dep["locator"], recorded, live_hash),
                    })
                    for ref_id in dep.get("affects_verified", []):
                        reverify.add(ref_id)

    # (3) NONDETERMINISTIC REPLAY: a pending step names a source that
    # cannot be blindly re-executed and trusted to reproduce the same
    # outcome (e.g. an LLM-generated text output).
    if not skip_nondeterminism:
        for step in handoff.get("pending", []):
            text = ((step.get("step") or "") + " " + (step.get("precondition") or "")).lower()
            if any(k in text for k in ND_KEYWORDS):
                reasons.append({
                    "class": "nondeterministic-replay",
                    "detail": ("pending step %r depends on a nondeterministic source and "
                               "must not be blindly replayed") % step.get("step"),
                })

    # (4) UNRECORDED EXTERNAL EFFECT: a real effect happened (per an
    # independently-observable ground-truth source, per the producer!=
    # oracle rule, sections 11.4.240/11.4.245 -- never derived from the
    # handoff record itself) but is absent from effects_performed, so
    # resume could risk repeating it.
    if not skip_unrecorded_effect:
        gt_path = os.path.join(fixture_dir, "ground_truth_effects.json")
        if os.path.isfile(gt_path):
            with open(gt_path, encoding="utf-8") as fh:
                ground_truth = json.load(fh)
            recorded_ids = {e["id"] for e in handoff.get("effects_performed", [])}
            for e in ground_truth:
                if e["id"] not in recorded_ids:
                    reasons.append({
                        "class": "unrecorded-external-effect",
                        "detail": ("effect %s:%s genuinely occurred but is absent from "
                                   "effects_performed -- resume must not risk repeating it") % (
                                       e["kind"], e["id"]),
                    })

    # (5) INCONSISTENT TRANSITION: the recorded current phase is not a
    # valid next state given the phase the agent's own verified evidence
    # last actually confirmed it reached (skips more than one phase step
    # with zero verified evidence for the skipped phases).
    if not skip_transition:
        order = PHASE_ORDER
        verified_phases = [v.get("phase") for v in handoff.get("verified", []) if v.get("phase") in order]
        last_verified_phase = None
        if verified_phases:
            last_verified_phase = max(verified_phases, key=lambda p: order.index(p))
        cur_phase = handoff.get("phase")
        if last_verified_phase and cur_phase in order:
            i_last = order.index(last_verified_phase)
            i_cur = order.index(cur_phase)
            if i_cur > i_last + 1:
                skipped = order[i_last + 1:i_cur]
                reasons.append({
                    "class": "inconsistent-transition",
                    "detail": "phase jumped from %s to %s, skipping %s with no verified evidence for those phases" % (
                        last_verified_phase, cur_phase, ", ".join(skipped)),
                })

    effects_not_to_repeat = [e["id"] for e in handoff.get("effects_performed", [])]

    return {
        "handoff_id": handoff.get("handoff_id"),
        "safe_to_resume_without_reverification": (len(reasons) == 0),
        "unsafe_reasons": reasons,
        "facts_needing_reverification": sorted(reverify),
        "effects_not_to_repeat": effects_not_to_repeat,
    }


def main():
    fixture_dir, out_path = sys.argv[1:3]
    flags = set(sys.argv[3:])
    result = derive_resume_check(
        fixture_dir,
        skip_internal_state=("--skip-internal-state-check" in flags),
        skip_external_dep=("--skip-external-dep-check" in flags),
        skip_nondeterminism=("--skip-nondeterminism-check" in flags),
        skip_unrecorded_effect=("--skip-unrecorded-effect-check" in flags),
        skip_transition=("--skip-transition-check" in flags),
    )
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, sort_keys=True, indent=2)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
PYEOF

# --- Helper: compare derived vs expected (unsafe_reasons compared as a
#     sorted-by-(class,detail) set so entry order never matters) ---
compare_outcome() {
  local derived_path="$1" expected_path="$2"
  python3 -c "
import json, sys
d = json.load(open('$derived_path'))
e = json.load(open('$expected_path'))
def norm_reasons(r):
    return sorted(((x['class'], x['detail']) for x in r))
ok = (d.get('handoff_id') == e.get('handoff_id')
      and d['safe_to_resume_without_reverification'] == e['safe_to_resume_without_reverification']
      and norm_reasons(d['unsafe_reasons']) == norm_reasons(e['unsafe_reasons'])
      and sorted(d['facts_needing_reverification']) == sorted(e['facts_needing_reverification'])
      and sorted(d['effects_not_to_repeat']) == sorted(e['effects_not_to_repeat']))
print('MATCH' if ok else 'MISMATCH derived=%s expected=%s' % (json.dumps(d, sort_keys=True), json.dumps(e, sort_keys=True)))
"
}

echo
echo "=== T126 five 'Safe to Resume?' failure classes + CT-5 negative control, independent DERIVED oracle ==="
for scen in $SCENARIOS; do
  SDIR="$FIXDIR/$scen"
  DERIVED="$TMP/${scen}.derived.json"
  python3 "$TMP/derive.py" "$SDIR" "$DERIVED" >/dev/null
  RESULT=$(compare_outcome "$DERIVED" "$SDIR/expected_verdict.json")
  if [ "$RESULT" = "MATCH" ]; then
    echo "ok $scen: independently-derived resume-check outcome matches expected_verdict.json"
  else
    echo "NOT ok $scen: $RESULT"
    failx
  fi
done

echo
echo "=== Discrimination check (section 11.4.107(10)/11.4.201(1)): each golden-bad fixture flags EXACTLY its own target class; the negative control flags none ==="
disc_fail=0
for scen in $SCENARIOS; do
  TARGET=$(python3 -c "import json; d=json.load(open('$FIXDIR/$scen/scenario.json')); print(d['target_class'] or '')")
  N_REASONS=$(python3 -c "import json; print(len(json.load(open('$FIXDIR/$scen/expected_verdict.json'))['unsafe_reasons']))")
  if [ -n "$TARGET" ]; then
    CLASSES=$(python3 -c "import json; print(','.join(sorted(set(x['class'] for x in json.load(open('$FIXDIR/$scen/expected_verdict.json'))['unsafe_reasons']))))")
    if [ "$N_REASONS" != "1" ] || [ "$CLASSES" != "$TARGET" ]; then
      echo "NOT ok discrimination $scen: expected exactly 1 reason of class"
      echo "     '$TARGET', got $N_REASONS reason(s) of class(es) '$CLASSES'"
      disc_fail=1
      failx
    fi
  else
    if [ "$N_REASONS" != "0" ]; then
      echo "NOT ok discrimination $scen (negative-control): expected zero"
      echo "     unsafe_reasons, got $N_REASONS -- a derivation that flags the"
      echo "     unchanged-dependency fixture is exactly the false-positive"
      echo "     this negative control exists to catch"
      disc_fail=1
      failx
    fi
  fi
done
if [ "$disc_fail" = 0 ]; then
  echo "ok discrimination: every golden-bad fixture flags exactly its own"
  echo "   target failure class and the negative control flags none -- the"
  echo "   oracle genuinely discriminates rather than rubber-stamping every"
  echo "   input identically"
fi

echo
echo "=== CT-5 negative control: rr_negctrl_all_unchanged proceeds SAFE, without forced re-verification ==="
CT5_SAFE=$(python3 -c "import json; print(json.load(open('$FIXDIR/rr_negctrl_all_unchanged/expected_verdict.json'))['safe_to_resume_without_reverification'])")
CT5_REVERIFY=$(python3 -c "import json; print(len(json.load(open('$FIXDIR/rr_negctrl_all_unchanged/expected_verdict.json'))['facts_needing_reverification']))")
if [ "$CT5_SAFE" = "True" ] && [ "$CT5_REVERIFY" = "0" ]; then
  echo "ok CT-5: with every external_dep genuinely unchanged, the oracle"
  echo "   reports safe_to_resume_without_reverification=true and zero facts"
  echo "   needing re-verification -- the check is precise, not maximally"
  echo "   paranoid, so a real implementation does not force expensive"
  echo "   re-verification work on every resume regardless of whether"
  echo "   anything actually changed"
else
  echo "NOT ok CT-5: expected safe=True and zero reverify facts, got"
  echo "     safe=$CT5_SAFE reverify_count=$CT5_REVERIFY"
  failx
fi

echo
echo "=== Paired mutations (section 1.1, one per failure class): disabling any ONE check wrongly reports SAFE ==="

paired_mutation() {
  local label="$1" scen="$2" skip_flag="$3"
  local SDIR="$FIXDIR/$scen"
  local MUT="$TMP/${scen}.mut.json"
  python3 "$TMP/derive.py" "$SDIR" "$MUT" "$skip_flag" >/dev/null
  local MUT_SAFE
  MUT_SAFE=$(python3 -c "import json; print(json.load(open('$MUT'))['safe_to_resume_without_reverification'])")
  local CORRECT_SAFE
  CORRECT_SAFE=$(python3 -c "import json; print(json.load(open('$SDIR/expected_verdict.json'))['safe_to_resume_without_reverification'])")
  if [ "$MUT_SAFE" = "True" ] && [ "$CORRECT_SAFE" = "False" ]; then
    echo "ok mutation ($label): disabling this check wrongly reports SAFE on"
    echo "   $scen (whose correct verdict is UNSAFE) -- proving a real"
    echo "   meta-test built against this fixture, once T134 lands, would"
    echo "   genuinely catch dropping this check"
  else
    echo "NOT ok mutation ($label) FAILED: mutated_safe=$MUT_SAFE"
    echo "     correct_safe=$CORRECT_SAFE (expected mutated=True, correct=False)"
    echo "     -- this fixture would not catch this mutation and needs revising"
    failx
  fi
}

paired_mutation "1/5 drop internal-state check" "rr_inconsistent_internal_state" "--skip-internal-state-check"
paired_mutation "2/5 drop external-dep check" "rr_stale_external_dependency" "--skip-external-dep-check"
paired_mutation "3/5 drop nondeterminism check" "rr_nondeterministic_replay" "--skip-nondeterminism-check"
paired_mutation "4/5 drop unrecorded-effect check" "rr_unrecorded_external_effect" "--skip-unrecorded-effect-check"
paired_mutation "5/5 drop transition check" "rr_inconsistent_transition" "--skip-transition-check"

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# orchestration/handoff.py lands (T133/T134), this block invokes its real
# `resume-check` subcommand for every fixture per contract HO-003 and this
# file's own documented Invocation shape, and asserts (a) its exit code
# matches the contract's Exit codes section (0 ok / 1 hash-mismatch-or-
# missing-field), and (b) its JSON output matches this file's independently-
# derived expectation.
#
# `write` and `verify` (T125/T-B04's own separate scope, per
# test_handoff_red.sh) are NOT exercised here -- this file's scope, per
# T126's own task line, is `resume-check` alone.
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: orchestration/handoff.py resume-check ==="
  for scen in $SCENARIOS; do
    SDIR="$FIXDIR/$scen"
    ACTUAL="$TMP/${scen}.actual_resume_check.json"
    ERR="$TMP/${scen}.actual_resume_check.err"
    python3 "$IMPL" resume-check --handoff "$SDIR/handoff.json" --out "$ACTUAL" >"$ERR" 2>&1
    RC=$?
    EXPECTED_SAFE="$(python3 -c "import json; print(json.load(open('$SDIR/expected_verdict.json'))['safe_to_resume_without_reverification'])")"
    if [ "$EXPECTED_SAFE" = "True" ]; then
      want_rc=0
    else
      want_rc=1
    fi
    if [ ! -f "$ACTUAL" ]; then
      echo "NOT ok $scen: real resume-check invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    RESULT=$(compare_outcome "$ACTUAL" "$SDIR/expected_verdict.json")
    if [ "$RC" = "$want_rc" ] && [ "$RESULT" = "MATCH" ]; then
      echo "ok $scen: real handoff.py resume-check exited $RC as expected and"
      echo "   its outcome matches expected_verdict.json"
    else
      echo "NOT ok $scen: real resume-check invocation rc=$RC (wanted $want_rc), $RESULT"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: orchestration/handoff.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the"
  echo "     overall RED exit below, which is the CORRECT state until T134"
  echo "     lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T134 not yet landed); if you"
  echo "    see this, orchestration/handoff.py must have landed AND every"
  echo "    fixture check passed against the real tool. ==="
else
  echo "=== T126 RED BASELINE CONFIRMED: orchestration/handoff.py does not"
  echo "    exist yet (T133/T134 are separate, later tasks). The five 'Safe"
  echo "    to Resume?' failure-class fixtures + the CT-5 negative control +"
  echo "    the discrimination check + all five paired mutations, all"
  echo "    independently re-derived and self-validated above, are the"
  echo "    interim contract T134 must satisfy to turn this GREEN. ==="
fi

exit $fail
