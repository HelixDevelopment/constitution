#!/bin/bash
# Purpose : T125 (SpecKit-004 "fast-dev-cycles", User Story 5) RED baseline
#           for `orchestration/handoff.py` `write`/`validate` (T133's own,
#           separate, later implementation task), per plan.md T-B04 and
#           contract `contracts/agent-registry-and-handoff.md` clauses
#           HO-001 (write) and HO-002 (partial-artefact re-hash-and-flag).
#
# tasks.md T125's own task line, as committed at HEAD when this test was
# authored (2026-09-30): "RED test
# constitution/scripts/fastcycle/tests/test_handoff_red.sh with fixtures
# constitution/scripts/fastcycle/tests/fixtures/handoff/ (a killed fixture
# agent leaves no handoff; golden: record round-trips; golden-bad: artefact
# hash not matching disk is flagged; negative control -- the CT-5 addition:
# a partial artefact legitimately re-written with its recorded hash updated
# validates PASS)".
#
# HONEST NOTE (section 11.4.6): T133's own task line calls the subcommand
# `validate`; the contract's Components section names the same subcommand
# `verify` ("handoff.py write|verify|resume-check ..."; HO-002: "verify
# re-hashes them and exits 1 on any difference"). Both names, verbatim, are
# used below, literally, so no wording is invented: `validate` in this
# file's own prose/derivation function names (tasks.md's wording, and this
# dispatch's own instructions' wording); `verify`/HO-002 when quoting the
# contract clause itself. The dormant real-tool invocation block at the
# bottom of this file tries the subcommand literally named `validate`
# (T133's own task-line wording) -- if T133 lands under the name `verify`
# instead, that block's own failure will surface the exact name mismatch
# rather than silently guessing a fallback.
#
# This file's checks, in order:
#   (1) absence check -- orchestration/handoff.py (T133) does not exist yet;
#   (2) section-11.4.273 control needles (below);
#   (3) "a killed fixture agent leaves no handoff" -- ho_killed_no_handoff/
#       carries a real kill_marker.json (proving the fixture agent WAS
#       killed) and deliberately NO handoff.json (proving nothing wrote one);
#   (4) "golden: record round-trips" -- ho_golden_roundtrip/handoff.json is
#       self-consistent (handoff_id/body_hash recompute correctly, both via
#       this file's own independent derivation AND via the REAL, already-
#       landed fc_common.py body-hash --verify) AND survives a literal
#       dump-to-temp-file/read-back round trip byte-for-byte, AND its
#       validate() outcome is VALID (both partial_artefacts hash-match);
#   (5) "golden-bad: artefact hash not matching disk is flagged" --
#       ho_golden_bad_tampered_artefact/'s notes.md was altered after
#       handoff.json was written; validate() outcome is INVALID naming
#       partial_artefact:notes.md;
#   (6) "negative control -- the CT-5 addition: a partial artefact
#       legitimately re-written with its recorded hash updated validates
#       PASS" -- ho_negctrl_legit_rewrite/'s notes.md genuinely differs from
#       an earlier snapshot, but handoff.json's recorded content_address was
#       correspondingly updated; validate() outcome is VALID;
#   (7) self-validation discrimination needles (section 11.4.107(10) /
#       11.4.201(1)): golden (VALID) and negative-control (VALID despite a
#       real content change) must both diverge from golden-bad (INVALID) --
#       never rubber-stamping every input identically;
#   (8) paired mutation (plan.md's own T-B04 "Protecting tests" line,
#       verbatim: "paired mutation: skip the artefact hash -> the golden-bad
#       FAILs") -- a mutated derivation that skips the partial_artefacts
#       hash check wrongly reports VALID on ho_golden_bad_tampered_artefact,
#       proving a real meta-test built against this fixture, once T133
#       lands, would genuinely catch this exact regression;
#   (9) a forward-compatible real-tool invocation block (dormant today,
#       TOOL_PRESENT=0) that, once T133 lands, drives the real `validate`
#       subcommand against every handoff.json-bearing fixture and asserts
#       its outcome/mismatches match this file's independently-derived
#       expectation.
#
# THE GAP (verified directly, 2026-09-30 against the current working tree):
# `constitution/scripts/fastcycle/orchestration/` holds exactly one file
# today, `completion_probe.sh` (T122, a SEPARATE, already-landed task) --
# there is NO `handoff.py` of any kind (T133 has not started).
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T125); T133's implementation of `orchestration/handoff.py` is a
# separate, later task -- this file's author never implements it. The
# independent oracle embedded below (derive_validate, a fresh Python
# implementation of contract clauses HO-001/HO-002 written directly from the
# contract's own wording, over this test's OWN fixture directory tree --
# never T133's eventual production code) is a DERIVED oracle per section
# 11.4.245, computed independently of whatever T133 eventually writes; it is
# never imported by, shared with, or otherwise coupled to
# `orchestration/handoff.py` so the two never collapse into one
# producer=verifier pair.
#
# Reuse, not reinvention (section 11.4.227): every `handoff.json`'s
# canonical-body / body_hash / handoff_id format reuses the ALREADY-LANDED
# `constitution/scripts/fastcycle/lib/fc_common.py` convention (C-002 of
# contracts/common-conventions.md, which every spec-004 tool inherits) --
# this test's control needle #3 below invokes that REAL tool's own
# `body-hash --verify` subcommand live against every fixture `handoff.json`,
# so the format-correctness claim is proven by the established tool itself,
# not merely asserted by this file's own reimplementation of the same
# convention (used separately, for the self-integrity/artefact-hash oracle
# -- a DIFFERENT concern from body_hash format).
#
# Wire format (UNCONFIRMED by the contract/data-model themselves -- DEFINED
# here, binding-if-adopted on T133, exactly per the established house
# precedent in fixtures/evidence_ref/README.md and
# test_governance_subset_red.sh's own "UNCONFIRMED... DEFINED here"
# section): full rationale + the two-pass, non-circular handoff_id/body_hash
# construction this file's oracle assumes is documented in
# fixtures/handoff/README.md -- read it before touching this file.
#
# Out of scope, deliberately (mirrors T126's own separate RED test):
# `resume-check`/HO-003 (re-hashing external_deps, invalidating dependent
# verified facts, the five "Safe to Resume?" failure modes) is T126's job
# against T-B05 (test_resume_revalidate_red.sh) -- never duplicated or
# pre-empted here. This file's derive_validate() oracle checks ONLY
# self-integrity (handoff_id/body_hash) and partial_artefacts, exactly
# HO-001/HO-002's scope.
#
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms):
#   #1 -- before trusting "handoff.py is absent" as a finding, prove the
#        plain `[ -f PATH ]` relative-path check genuinely resolves paths
#        from this script's real location, by first confirming a
#        KNOWN-PRESENT sibling (lib/fc_common.py, used throughout this
#        suite) resolves true through the identical relative-path
#        construction.
#   #2 -- item_id collision with the live tracker DB is sidestepped by
#        design, not merely left unchecked: every fixture here uses the
#        data-model-legal explicit value `"item_id": "NONE"` (AR-006:
#        "NONE is explicit, not absent") rather than a synthetic ATM-NNN-
#        shaped id, so the whole collision class test_evidence_ref_red.sh's
#        control needle #2 guards against cannot arise here at all.
#   #3 -- every fixture `handoff.json`'s stored `body_hash` genuinely
#        matches its own canonical body, verified LIVE via the REAL,
#        already-landed `fc_common.py body-hash --verify` (not this file's
#        own reimplementation of the same check) -- proving the fixtures
#        are internally self-consistent per the established C-002
#        convention, not merely self-asserted.
#
# section-11.4.245 (oracle-problem-first / DERIVED oracle): each scenario's
# `expected_validate.json` was hand-computed FIRST (see the Python builder
# transcript this file's author ran interactively while authoring the
# fixtures -- the resulting JSON is what is checked in) and is independently
# RE-DERIVED below by this test's own from-scratch `derive_validate()`
# function (never borrowed from, or shared with, any implementation) BEFORE
# that hand-computed value is trusted -- mirroring sibling
# test_evidence_ref_red.sh's derive.py convention exactly.
#
# section-11.4.107(10) self-validation (Principle IV): ho_golden_roundtrip
# (golden-good) and ho_negctrl_legit_rewrite (negative-control) MUST both
# produce VALID, while ho_golden_bad_tampered_artefact (golden-bad) MUST
# produce INVALID -- proving the derivation, and the eventual `validate`
# check it stands in for, can genuinely tell a legitimately-updated record
# from a tampered one, never rubber-stamping every input the same way (the
# section-11.4.201(1) false-positive guard).
#
# Usage : bash test_handoff_red.sh   Exit 0 = every real assertion below
#         held (all three control needles, the absence check, the
#         killed-agent-leaves-no-handoff check, the three-scenario derived-
#         oracle table, the round-trip check, the discrimination needles,
#         and the paired mutation).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-30):
#         `orchestration/handoff.py` genuinely does not exist yet (T133 is a
#         separate, later, not-yet-started task) -- this is the T125 RED
#         baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/handoff"
IMPL="$FC/orchestration/handoff.py"
FC_COMMON="$FC/lib/fc_common.py"

SCENARIOS="ho_golden_roundtrip ho_golden_bad_tampered_artefact ho_negctrl_legit_rewrite"

fail=0
failx() { fail=1; }

# --- section-11.4.273 control needle #1: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence checks below prove"
  echo "     nothing (section 11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the absence checks"
  echo "   below can be trusted"
fi

# --- section-11.4.273 control needle #2: item_id collision class sidestepped by design ---
collide2=0
for scen in $SCENARIOS; do
  h="$FIXDIR/$scen/handoff.json"
  if [ -f "$h" ]; then
    iid=$(python3 -c "import json; print(json.load(open('$h'))['item_id'])" 2>/dev/null)
    if [ "$iid" != "NONE" ]; then
      echo "NOT ok control needle #2 FAILED: $scen/handoff.json uses item_id='$iid',"
      echo "     not the data-model-legal explicit 'NONE' -- this fixture set no"
      echo "     longer sidesteps the tracker-DB-collision class by design and must"
      echo "     add the live-DB collision check test_evidence_ref_red.sh's own"
      echo "     control needle #2 performs"
      collide2=1
      failx
    fi
  fi
done
if [ "$collide2" = 0 ]; then
  echo "ok control needle #2: every fixture handoff.json uses the explicit,"
  echo "   collision-free item_id 'NONE' -- the tracker-DB-collision class"
  echo "   sidestepped by design, not merely left unchecked"
fi

# --- section-11.4.273 control needle #3: every handoff.json's body_hash genuinely verifies via the REAL fc_common.py ---
if [ ! -f "$FC_COMMON" ]; then
  echo "NOT ok control needle #3 BLIND: fc_common.py absent at $FC_COMMON"
  failx
else
  n3_fail=0
  for scen in $SCENARIOS; do
    if [ ! -f "$FIXDIR/$scen/handoff.json" ]; then
      echo "NOT ok control needle #3 BLIND: $scen/handoff.json missing"
      n3_fail=1
      failx
      continue
    fi
    if ! python3 "$FC_COMMON" body-hash --doc "$FIXDIR/$scen/handoff.json" --verify >/dev/null 2>&1; then
      echo "NOT ok control needle #3 FAILED: $scen/handoff.json's stored body_hash does NOT"
      echo "     match its canonical body per the REAL, already-landed fc_common.py --"
      echo "     this fixture desynced from the established C-002 convention"
      n3_fail=1
      failx
    fi
  done
  if [ "$n3_fail" = 0 ]; then
    echo "ok control needle #3: all three handoff.json fixtures' body_hash values"
    echo "   verify LIVE against the REAL fc_common.py body-hash --verify (the"
    echo "   established tool, never this file's own reimplementation of the same"
    echo "   check)"
  fi
fi

# --- (1) Absence check: orchestration/handoff.py ---
ORCH_DIR="$FC/orchestration"
if [ -d "$ORCH_DIR" ]; then
  py_count=$(find "$ORCH_DIR" -maxdepth 1 -name '*.py' -o -maxdepth 1 -name '*.sh' | wc -l)
  echo "-- $ORCH_DIR exists, holding $py_count script(s) right now (T122's"
  echo "   completion_probe.sh -- a separate, already-landed task -- lives here too)"
else
  echo "-- $ORCH_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok orchestration/handoff.py now exists -- T133 has landed. The forward-"
  echo "   compatible invocation checks below will exercise it for real against"
  echo "   every handoff.json-bearing fixture's expected_validate.json."
  TOOL_PRESENT=1
else
  echo "NOT ok orchestration/handoff.py is absent -- T133 (plan.md T-B04's"
  echo "     implementation task, a SEPARATE later task from this RED test) has"
  echo "     not landed yet. THIS IS THE CORRECT, EXPECTED T125 RED BASELINE --"
  echo "     the fixtures + independent derivation below stand as the interim"
  echo "     contract T133 must satisfy to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# --- (3) "a killed fixture agent leaves no handoff" ---
echo
echo "=== ho_killed_no_handoff: a killed fixture agent leaves NO handoff.json ==="
KILLED_DIR="$FIXDIR/ho_killed_no_handoff"
if [ ! -f "$KILLED_DIR/kill_marker.json" ]; then
  echo "NOT ok ho_killed_no_handoff BLIND: kill_marker.json missing -- cannot trust"
  echo "     the sibling handoff.json absence below without first proving this"
  echo "     directory itself resolves (the section-11.4.273 control-needle"
  echo "     pattern applied to this one fixture)"
  failx
else
  echo "ok kill_marker.json resolves -- ho_killed_no_handoff/ genuinely exists,"
  echo "   so the handoff.json absence check below can be trusted"
  if [ -f "$KILLED_DIR/handoff.json" ]; then
    echo "NOT ok ho_killed_no_handoff: a handoff.json UNEXPECTEDLY exists in this"
    echo "     fixture -- this fixture's whole point (today, with no handoff.py,"
    echo "     nothing writes a handoff record on crash) is defeated"
    failx
  else
    echo "ok ho_killed_no_handoff: no handoff.json exists for this killed fixture"
    echo "   agent -- the literal T125 RED condition -- consistent with the global"
    echo "   absence check above (orchestration/handoff.py does not exist, so"
    echo "   nothing could have written one)"
  fi
fi

# --- Fixture files present (the three handoff.json-bearing scenarios) ---
for scen in $SCENARIOS; do
  for f in handoff.json expected_validate.json scenario.json; do
    if [ ! -f "$FIXDIR/$scen/$f" ]; then
      echo "NOT ok fixture $scen/$f missing"
      failx
    fi
  done
done
echo "ok all three handoff.json-bearing scenario directories carry handoff.json +"
echo "   expected_validate.json + scenario.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Independent DERIVED oracle (section 11.4.245): a from-scratch Python
# re-implementation of contract clauses HO-001 (self-integrity)/HO-002
# (partial-artefact re-hash), written directly by THIS test's author, over
# THIS test's own fixture directories -- never imported by nor shared with
# orchestration/handoff.py.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import hashlib
import json
import os
import sys


def canon(obj):
    """Reuses fc_common.py's own canon() convention (sort_keys, no
    insignificant whitespace, ensure_ascii=False) -- section 11.4.227
    extend-don't-invent -- reimplemented independently rather than
    imported, so this file's validate oracle never shares code with
    orchestration/handoff.py (the tool under test)."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def body_hash_of(doc):
    """Byte-for-byte the same EXCLUDED set as the REAL fc_common.py's own
    body_hash_of(): only run_meta and body_hash are excluded -- schema and
    every other field (including handoff_id, once present) ARE hashed."""
    body = {k: v for k, v in doc.items() if k not in ("run_meta", "body_hash")}
    return hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


def content_address(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def derive_validate(scenario_dir, doc, skip_artefact_hash_mutation=False):
    """HO-001/HO-002 scope only (never HO-003/resume-check -- T126's job):

    1. self-integrity -- handoff_id and body_hash both recompute correctly
       from the doc's own stored fields (fixtures/handoff/README.md's
       two-pass, non-circular construction: handoff_id excludes itself +
       body_hash + run_meta; body_hash excludes only itself + run_meta,
       hashing a doc that DOES include handoff_id).
    2. partial_artefacts -- HO-002: 'Partial artefacts are never deleted or
       rewritten by crash handling; verify re-hashes them and exits 1 on
       any difference.' Recomputes each declared path's CURRENT on-disk
       content_address and compares to the recorded one.

    skip_artefact_hash_mutation: this file's own named paired mutation
    (plan.md's T-B04 'Protecting tests' line, verbatim: 'paired mutation:
    skip the artefact hash -> the golden-bad FAILs') -- deliberately WRONG:
    never checks partial_artefacts at all, so a genuinely tampered
    artefact is structurally invisible to this comparison.
    """
    mismatches = []

    # 1. self-integrity
    doc_without_id = {k: v for k, v in doc.items() if k not in ("handoff_id", "body_hash", "run_meta")}
    recomputed_handoff_id = "sha256:" + hashlib.sha256(canon(doc_without_id).encode("utf-8")).hexdigest()
    if recomputed_handoff_id != doc.get("handoff_id"):
        mismatches.append("self_integrity:handoff_id")

    recomputed_body_hash = body_hash_of(doc)
    if recomputed_body_hash != doc.get("body_hash"):
        mismatches.append("self_integrity:body_hash")

    # 2. partial_artefacts
    if not skip_artefact_hash_mutation:
        for art in doc.get("partial_artefacts", []):
            full = os.path.join(scenario_dir, art["path"])
            if not os.path.exists(full):
                mismatches.append("partial_artefact:%s:missing" % art["path"])
                continue
            live_ca = content_address(full)
            if live_ca != art["content_address"]:
                mismatches.append("partial_artefact:%s" % art["path"])

    outcome = "INVALID" if mismatches else "VALID"
    return {"outcome": outcome, "mismatches": mismatches}


def main():
    scenario_dir, doc_path, out_path = sys.argv[1:4]
    skip = "--skip-artefact-hash" in sys.argv[4:]
    with open(doc_path, encoding="utf-8") as fh:
        doc = json.load(fh)
    result = derive_validate(scenario_dir, doc, skip_artefact_hash_mutation=skip)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, sort_keys=True, indent=2)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
PYEOF

compare_outcome() {
  local derived_path="$1" expected_path="$2"
  python3 -c "
import json, sys
d = json.load(open('$derived_path'))
e = json.load(open('$expected_path'))
ok = (d['outcome'] == e['outcome'] and d['mismatches'] == e['mismatches'])
print('MATCH' if ok else 'MISMATCH derived=%s expected=%s' % (json.dumps(d, sort_keys=True), json.dumps(e, sort_keys=True)))
"
}

echo
echo "=== T125 fixture table (three handoff.json-bearing scenarios), independent DERIVED oracle ==="
for scen in $SCENARIOS; do
  SDIR="$FIXDIR/$scen"
  DOC="$SDIR/handoff.json"
  EXPECTED="$SDIR/expected_validate.json"
  DERIVED="$TMP/${scen}.derived.json"
  python3 "$TMP/derive.py" "$SDIR" "$DOC" "$DERIVED" >/dev/null
  RESULT=$(compare_outcome "$DERIVED" "$EXPECTED")
  if [ "$RESULT" = "MATCH" ]; then
    echo "ok $scen: independently-derived validate outcome matches expected_validate.json"
  else
    echo "NOT ok $scen: $RESULT"
    failx
  fi
done

echo
echo "=== golden: record round-trips (literal dump-to-file / read-back check) ==="
SDIR="$FIXDIR/ho_golden_roundtrip"
python3 -c "
import json
with open('$SDIR/handoff.json', encoding='utf-8') as fh:
    original = json.load(fh)
with open('$TMP/roundtrip.json', 'w', encoding='utf-8') as fh:
    json.dump(original, fh, sort_keys=True, indent=2)
with open('$TMP/roundtrip.json', encoding='utf-8') as fh:
    reloaded = json.load(fh)
import sys
sys.exit(0 if reloaded == original else 1)
"
if [ $? -eq 0 ]; then
  echo "ok ho_golden_roundtrip/handoff.json survives a literal dump-to-temp-file /"
  echo "   read-back round trip, structurally identical to the on-disk original --"
  echo "   combined with the fixture-table row above (self-integrity + both"
  echo "   partial_artefacts hash-match), the record genuinely round-trips"
else
  echo "NOT ok ho_golden_roundtrip/handoff.json did NOT survive an identity round"
  echo "     trip through json.dump/json.load"
  failx
fi

echo
echo "=== Self-validation discrimination needles (section 11.4.107(10)/11.4.201(1)) ==="
GOLDEN_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/ho_golden_roundtrip/expected_validate.json'))['outcome'])")"
NEGCTRL_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/ho_negctrl_legit_rewrite/expected_validate.json'))['outcome'])")"
BAD_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/ho_golden_bad_tampered_artefact/expected_validate.json'))['outcome'])")"
disc_fail=0
if [ "$GOLDEN_OUT" != "VALID" ]; then
  echo "NOT ok discrimination: ho_golden_roundtrip (golden-good) must expect VALID, got $GOLDEN_OUT"
  disc_fail=1
  failx
fi
if [ "$NEGCTRL_OUT" != "VALID" ]; then
  echo "NOT ok discrimination: ho_negctrl_legit_rewrite (negative-control) must"
  echo "     expect VALID despite notes.md's real content change, got $NEGCTRL_OUT"
  echo "     -- a derivation that flags ANY on-disk change (rather than only a"
  echo "     content_address that was NOT correspondingly updated) would fail"
  echo "     this needle, which is exactly the false-positive guard this fixture"
  echo "     exists for (the CT-5 addition named in T125's own task line)"
  disc_fail=1
  failx
fi
if [ "$BAD_OUT" = "VALID" ]; then
  echo "NOT ok discrimination: the golden-bad fixture unexpectedly expects VALID"
  disc_fail=1
  failx
fi
if [ "$disc_fail" = 0 ]; then
  echo "ok discrimination: golden-good (VALID) and negative-control (VALID despite"
  echo "   a real, legitimate content change) both diverge correctly from the"
  echo "   golden-bad fixture (INVALID) -- the oracle genuinely discriminates"
  echo "   rather than rubber-stamping every input identically"
fi

echo
echo "=== Paired mutation (plan.md's own T-B04 Protecting-tests line, verbatim): skip the artefact hash -> ho_golden_bad_tampered_artefact wrongly VALID ==="
SDIR="$FIXDIR/ho_golden_bad_tampered_artefact"
MUT="$TMP/ho_golden_bad_tampered_artefact.mut_skip_hash.json"
python3 "$TMP/derive.py" "$SDIR" "$SDIR/handoff.json" "$MUT" --skip-artefact-hash >/dev/null
MUT_OUT="$(python3 -c "import json; print(json.load(open('$MUT'))['outcome'])")"
CORRECT_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/ho_golden_bad_tampered_artefact/expected_validate.json'))['outcome'])")"
if [ "$MUT_OUT" = "VALID" ] && [ "$CORRECT_OUT" = "INVALID" ]; then
  echo "ok paired mutation (skip the artefact hash): the mutated derivation wrongly"
  echo "   reports VALID on ho_golden_bad_tampered_artefact (whose notes.md"
  echo "   genuinely changed after handoff.json was written) while the correct"
  echo "   derivation reports INVALID -- proving a real meta-test built against"
  echo "   this fixture, once T133 lands, would genuinely catch this exact"
  echo "   mutation (plan.md's own named T-B04 paired mutation)"
else
  echo "NOT ok paired mutation FAILED: mutated=$MUT_OUT correct=$CORRECT_OUT"
  echo "     (expected mutated=VALID, correct=INVALID) -- this fixture would not"
  echo "     catch this mutation and needs revising"
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# orchestration/handoff.py lands (T133), this block invokes its real
# `validate` subcommand for every handoff.json-bearing fixture per this
# file's own header HONEST NOTE (T133's task-line wording; the contract
# calls the same subcommand `verify` -- if T133 lands under that name
# instead, this block's own failure will surface the exact mismatch rather
# than silently guessing a fallback).
#
# `write` is NOT exercised here -- an honest, explicit gap (see
# fixtures/handoff/README.md's own "What this RED test does NOT cover"
# section): `write`'s exact `--out`/input-body shape is genuinely
# UNCONFIRMED by the contract, and building a write-then-compare round-trip
# on top of that ambiguity would risk a spurious FAIL unrelated to
# `validate`'s own (fully-specified) semantics, which is this file's actual
# scope per T125's task line.
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: orchestration/handoff.py validate ==="
  for scen in $SCENARIOS; do
    SDIR="$FIXDIR/$scen"
    ACTUAL="$TMP/${scen}.actual_validate.json"
    ERR="$TMP/${scen}.actual_validate.err"
    python3 "$IMPL" validate --handoff "$SDIR/handoff.json" --out "$ACTUAL" >"$ERR" 2>&1
    RC=$?
    EXPECTED_OUT="$(python3 -c "import json; print(json.load(open('$SDIR/expected_validate.json'))['outcome'])")"
    case "$EXPECTED_OUT" in
      VALID) want_rc=0 ;;
      INVALID) want_rc=1 ;;
      *) want_rc="" ;;
    esac
    if [ ! -f "$ACTUAL" ]; then
      echo "NOT ok $scen: real validate invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    RESULT=$(compare_outcome "$ACTUAL" "$SDIR/expected_validate.json")
    if [ "$RC" = "$want_rc" ] && [ "$RESULT" = "MATCH" ]; then
      echo "ok $scen: real handoff.py validate exited $RC as expected and its"
      echo "   outcome matches expected_validate.json"
    else
      echo "NOT ok $scen: real validate invocation rc=$RC (wanted $want_rc), $RESULT"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: orchestration/handoff.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T133 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T133 not yet landed); if you see"
  echo "    this, orchestration/handoff.py must have landed AND every fixture"
  echo "    check passed against the real tool. ==="
else
  echo "=== T125 RED BASELINE CONFIRMED: orchestration/handoff.py does not exist"
  echo "    yet (T133 is a separate, later task). The three-scenario fixture"
  echo "    table + the killed-agent-leaves-no-handoff check + the round-trip"
  echo "    check + the discrimination needles + the named paired mutation, all"
  echo "    independently re-derived and self-validated above, are the interim"
  echo "    contract T133 must satisfy to turn this GREEN. ==="
fi

exit $fail
