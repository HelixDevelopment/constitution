#!/bin/bash
# Purpose : T108 (SpecKit-004 "fast-dev-cycles", User Story 4) RED baseline
#           for `context/evidence_ref.py` (T117's own, separate, later
#           implementation task), per plan.md T-E05 and contract
#           contracts/evidence-reference-reverify.md ("Let a later step (or
#           a resumed agent) consume a fact an earlier step verified,
#           re-verifying only when something that fact depends on actually
#           changed -- the Bazel action-digest model applied to agent
#           evidence, R5 rec. 3").
#
# tasks.md T108's own task line, as committed at HEAD when this test was
# authored (2026-09-29): "RED test
# constitution/scripts/fastcycle/tests/test_evidence_ref_red.sh with
# fixtures per contract evidence-reference-reverify (FR-014 two-step
# fixture: unchanged artefact -> no re-verification, changed -> re-
# verification; golden-bad: a reference whose on-target fingerprint
# differs is refused)".
#
# HONEST NOTE (section 11.4.6 -- caught while authoring, not silently
# absorbed): this dispatch's own instructions additionally named a paired
# mutation -- "compare paths instead of content hashes -> the changed-
# artefact fixture FAILs" -- quoting what tasks.md's T108 line contained
# at the MOMENT this dispatch was issued. By the time this file was
# authored, the committed tasks.md T108 line (quoted above, re-verified
# live immediately before writing this comment) no longer carries that
# exact clause -- `git log -S "compare paths instead of content hashes"
# --all` finds no removal commit either, so the most likely explanation is
# a concurrent dispatch's in-place, never-separately-committed edit to
# this heavily-multi-writer-contended line between dispatch time and now
# (this repo runs many parallel tracks against the SAME tasks.md; see the
# T033 entry a few hundred lines above this test's own commit, staged
# concurrently with this very test's authoring). The mutation is
# implemented below regardless (paired mutation 2/2) -- it is real,
# valuable coverage the dispatch asked for -- but is attributed to "this
# dispatch's own instructions," never claimed as a verbatim quote of the
# CURRENT tasks.md text, which would be a checkably false citation. The
# contract's OWN RED-fixtures table (evidence-reference-reverify.md,
# unchanged) separately and independently names its OWN paired mutation
# ("drop the verifier-version component from ER-001") -- that one IS
# still verbatim-quotable from a stable, non-task-line source; see
# paired mutation 1/2 below.
#
# This file's checks, in order:
#   (1) absence check -- context/evidence_ref.py (T117) does not exist yet;
#   (2) three section-11.4.273 control needles (below);
#   (3) the contract's OWN RED-fixtures table, all six rows, via an
#       independent DERIVED oracle (never T117's not-yet-written code):
#         er_unchanged            golden-good  -> REUSED
#         er_changed_input        golden-bad   -> REVERIFY_REQUIRED, names the path
#         er_changed_verifier     golden-bad   -> REVERIFY_REQUIRED, names verifier_version
#         er_changed_target       golden-bad   -> REVERIFY_REQUIRED, names target_fingerprint
#                                                  (T108's own named scenario: "a reference
#                                                  whose on-target fingerprint differs is refused")
#         er_evidence_tampered    golden-bad   -> STALE_EVIDENCE
#         er_negctrl_unrelated_file negative-control -> REUSED (an unrelated file
#                                                  changing must never affect the outcome)
#   (4) ER-005 bonus check (same er_changed_target fixture, --target omitted
#       entirely at consume) -> REVERIFY_REQUIRED ("no reuse on an
#       unobserved target");
#   (5) ER-003 "no silent reuse" check: every REVERIFY_REQUIRED/
#       STALE_EVIDENCE expected_consume.json fixture carries NO `verdict`
#       key; every REUSED one does;
#   (6) self-validation triple discrimination needles (section 11.4.107(10)
#       / 11.4.201(1)): golden-good vs golden-bad vs negative-control must
#       genuinely diverge, never rubber-stamp the same verdict regardless
#       of input;
#   (7) BOTH the contract's own named paired mutation ("drop the
#       verifier-version component from ER-001 => er_changed_verifier
#       returns REUSED") AND this dispatch's own named paired mutation
#       ("compare paths instead of content hashes => the changed-artefact
#       fixture FAILs" -- i.e. er_changed_input wrongly returns REUSED;
#       see the HONEST NOTE above -- not verbatim-quotable from the
#       CURRENT tasks.md T108 line, which no longer carries this clause);
#   (8) a forward-compatible real-tool invocation block (dormant today,
#       TOOL_PRESENT=0) that, once T117 lands, drives the real
#       `consume` subcommand against every fixture and asserts (a) its
#       outcome/changed_components/evidence_hash_ok/verdict-presence match
#       this file's independently-derived expectation, and (b) the T108
#       task text's "assert via a verifier stub that records invocations"
#       requirement: `consume` MUST NEVER invoke the verifier -- proven by
#       pointing EVREF_VERIFIER_MARKER at a fresh temp path (every
#       fixture's verifier.sh writes to it if run) and asserting the
#       marker file does NOT exist after every `consume` call.
#
# THE GAP (verified directly, 2026-09-29 against the current working tree):
# `constitution/scripts/fastcycle/context/` holds exactly one file today,
# `anchor_citations.py` (T039, a SEPARATE, already-landed task) -- there is
# NO `evidence_ref.py` of any kind (T117 has not started).
#
# Producer != Verifier (section 11.4.240): this file is authored at the RED
# step (T108); T117's implementation of `context/evidence_ref.py` is a
# separate, later task -- this file's author never implements it. The
# independent oracle embedded below (derive_consume, a fresh Python
# implementation of contract clauses ER-001/ER-002/ER-005 written directly
# from the contract's own wording, over this test's OWN fixture directory
# tree -- never T117's eventual production code) is a DERIVED oracle per
# section 11.4.245, computed independently of whatever T117 eventually
# writes; it is never imported by, shared with, or otherwise coupled to
# `context/evidence_ref.py` so the two never collapse into one
# producer=verifier pair.
#
# Reuse, not reinvention (section 11.4.227): every `ref.json`'s canonical-
# body / body_hash format is the ALREADY-LANDED, already-established
# `constitution/scripts/fastcycle/lib/fc_common.py` convention (C-002 of
# contracts/common-conventions.md, which every spec-004 tool inherits) --
# this test's control needle #3 below invokes that REAL tool's own
# `body-hash --verify` subcommand live against every fixture `ref.json`, so
# the format-correctness claim is proven by the established tool itself,
# not merely asserted by this file's own reimplementation of the same
# convention (which is used separately, for the Merkle-root/consume-
# semantics oracle -- a DIFFERENT concern from body_hash format).
#
# Wire format (UNCONFIRMED by the contract itself -- DEFINED here,
# binding-if-adopted on T117, exactly per the established house precedent
# in fixtures/verdict_cache/README.md and test_governance_subset_red.sh's
# own "UNCONFIRMED... DEFINED here" section): full rationale + the closed
# `changed_components` vocabulary this file's oracle emits is documented in
# fixtures/evidence_ref/README.md -- read it before touching this file.
#
# section-11.4.273 control needles (this file's own absence/false-anchor
# detection mechanisms):
#   #1 -- before trusting "evidence_ref.py is absent" as a finding, prove
#        the plain `[ -f PATH ]` relative-path check genuinely resolves
#        paths from this script's real location, by first confirming a
#        KNOWN-PRESENT sibling (lib/fc_common.py, used throughout this
#        suite) resolves true through the identical relative-path
#        construction.
#   #2 -- none of this fixture set's six synthetic `ref_id` values collide
#        with any real item in the live tracker DB
#        (docs/workable_items.db), mirroring test_governance_subset_red.sh's
#        own fixture-id-collision precaution -- a future implementer must
#        never be tempted to resolve an evidence reference through the
#        tracker DB by mistake.
#   #3 -- every fixture `ref.json`'s stored `body_hash` genuinely matches
#        its own canonical body, verified LIVE via the REAL, already-landed
#        `fc_common.py body-hash --verify` (not this file's own
#        reimplementation of the same check) -- proving the fixtures are
#        internally self-consistent per the established C-002 convention,
#        not merely self-asserted.
#
# section-11.4.245 (oracle-problem-first / DERIVED oracle): each scenario's
# `expected_consume.json` was hand-computed FIRST (see the Python builder
# transcript this file's author ran interactively while authoring the
# fixtures -- the resulting JSON is what is checked in) and is
# independently RE-DERIVED below by this test's own from-scratch
# `derive_consume()` function (never borrowed from, or shared with, any
# implementation) BEFORE that hand-computed value is trusted -- mirroring
# sibling test_governance_subset_red.sh's derive.py convention exactly.
#
# section-11.4.107(10) self-validation (Principle IV): er_unchanged
# (golden-good) and every one of the four golden-bad fixtures MUST produce
# a DIFFERENT, genuinely-discriminating outcome from each other and from
# er_negctrl_unrelated_file (negative-control) -- proving the derivation,
# and the eventual `consume` check it stands in for, can genuinely tell a
# reusable reference from a stale one, never rubber-stamping every input
# the same way (the section-11.4.201(1) false-positive guard).
#
# Usage : bash test_evidence_ref_red.sh   Exit 0 = every real assertion
#         below held (all three control needles, the absence check, the
#         six-row contract fixture table via the derived oracle, the
#         ER-005 bonus check, the ER-003 no-silent-reuse check, the
#         discrimination needles, and both paired-mutation proofs).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-29):
#         `context/evidence_ref.py` genuinely does not exist yet (T117 is a
#         separate, later, not-yet-started task) -- this is the T108 RED
#         baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/evidence_ref"
IMPL="$FC/context/evidence_ref.py"
FC_COMMON="$FC/lib/fc_common.py"
DB="$ROOT/docs/workable_items.db"

SCENARIOS="er_unchanged er_changed_input er_changed_verifier er_changed_target er_evidence_tampered er_negctrl_unrelated_file"

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

# --- section-11.4.273 control needle #2: fixture ref_ids must not collide with the live tracker DB ---
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  collide=0
  for scen in $SCENARIOS; do
    ref_id=$(python3 -c "import json; print(json.load(open('$FIXDIR/$scen/ref.json'))['ref_id'])" 2>/dev/null)
    if [ -z "$ref_id" ]; then
      echo "NOT ok control needle #2 BLIND: could not read ref_id from $scen/ref.json"
      failx
      continue
    fi
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$ref_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture ref_id '$ref_id' collides"
      echo "     with a REAL live-tracker item -- every fixture in this suite must use"
      echo "     ids that do not exist in docs/workable_items.db"
      collide=1
      failx
    fi
  done
  if [ "$collide" = 0 ]; then
    echo "ok control needle #2: none of the six synthetic fixture ref_id values"
    echo "   collide with any real item in the live tracker DB"
  fi
else
  echo "NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable"
  echo "     in this environment -- this is an environment gap, not a finding"
  failx
fi

# --- section-11.4.273 control needle #3: every ref.json's body_hash genuinely verifies via the REAL fc_common.py ---
if [ ! -f "$FC_COMMON" ]; then
  echo "NOT ok control needle #3 BLIND: fc_common.py absent at $FC_COMMON"
  failx
else
  n3_fail=0
  for scen in $SCENARIOS; do
    if [ ! -f "$FIXDIR/$scen/ref.json" ]; then
      echo "NOT ok control needle #3 BLIND: $scen/ref.json missing"
      n3_fail=1
      failx
      continue
    fi
    if ! python3 "$FC_COMMON" body-hash --doc "$FIXDIR/$scen/ref.json" --verify >/dev/null 2>&1; then
      echo "NOT ok control needle #3 FAILED: $scen/ref.json's stored body_hash does NOT"
      echo "     match its canonical body per the REAL, already-landed fc_common.py --"
      echo "     this fixture desynced from the established C-002 convention"
      n3_fail=1
      failx
    fi
  done
  if [ "$n3_fail" = 0 ]; then
    echo "ok control needle #3: all six ref.json fixtures' body_hash values verify"
    echo "   LIVE against the REAL fc_common.py body-hash --verify (the established"
    echo "   tool, never this file's own reimplementation of the same check)"
  fi
fi

# --- (1) Absence check: context/evidence_ref.py ---
CONTEXT_DIR="$FC/context"
if [ -d "$CONTEXT_DIR" ]; then
  py_count=$(find "$CONTEXT_DIR" -maxdepth 1 -name '*.py' | wc -l)
  echo "-- $CONTEXT_DIR exists, holding $py_count *.py file(s) right now (T039's"
  echo "   anchor_citations.py -- a separate, already-landed task -- lives here too)"
else
  echo "-- $CONTEXT_DIR does not exist at all yet"
fi
if [ -f "$IMPL" ]; then
  echo "ok context/evidence_ref.py now exists -- T117 has landed. The forward-"
  echo "   compatible invocation checks below will exercise it for real against"
  echo "   every fixture's expected_consume.json."
  TOOL_PRESENT=1
else
  echo "NOT ok context/evidence_ref.py is absent -- T117 (plan.md T-E05's"
  echo "     implementation task, a SEPARATE later task from this RED test) has"
  echo "     not landed yet. THIS IS THE CORRECT, EXPECTED T108 RED BASELINE --"
  echo "     the fixtures + independent derivation below stand as the interim"
  echo "     contract T117 must satisfy to turn this GREEN."
  TOOL_PRESENT=0
  failx
fi

# --- Fixture files present ---
for scen in $SCENARIOS; do
  for f in ref.json expected_consume.json scenario.json; do
    if [ ! -f "$FIXDIR/$scen/$f" ]; then
      echo "NOT ok fixture $scen/$f missing"
      failx
    fi
  done
done
echo "ok all six scenario directories carry ref.json + expected_consume.json + scenario.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Independent DERIVED oracle (section 11.4.245): a from-scratch Python
# re-implementation of contract clauses ER-001/ER-002/ER-005, written
# directly by THIS test's author, over THIS test's own fixture directories
# -- never imported by nor shared with context/evidence_ref.py.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import hashlib
import json
import os
import sys


def content_address(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def canon(obj):
    """Reuses fc_common.py's own canon() convention (sort_keys, no
    insignificant whitespace, ensure_ascii=False) -- section 11.4.227
    extend-don't-invent -- reimplemented independently rather than
    imported, so this file's Merkle-root/consume oracle never shares code
    with context/evidence_ref.py (the tool under test)."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def merkle_root(pairs):
    """data-model.md section 0: 'sha256: over the sorted list of (path,
    ContentAddress) pairs ... sorted BYTEWISE by path' -- sorted on the raw
    UTF-8 bytes of the path string, never a locale-dependent str sort
    (C-003; the same class of trap test_core_ondemand_red.sh's own
    negative-control caught for a different comparator, applied here on
    principle even though every path in this fixture set is plain ASCII)."""
    sorted_pairs = sorted(pairs, key=lambda p: p[0].encode("utf-8"))
    body = [[p, c] for p, c in sorted_pairs]
    return "sha256:" + hashlib.sha256(canon(body).encode("utf-8")).hexdigest()


def recompute_input_pairs(scenario_dir, declared_paths):
    pairs = []
    for p in declared_paths:
        full = os.path.join(scenario_dir, p)
        pairs.append((p, content_address(full)))
    return pairs


def derive_consume(scenario_dir, ref, consume_target, drop_verifier_version_mutation=False,
                    paths_only_mutation=False):
    """ER-002: 'Recomputes every component from current bytes / the live
    target. All equal and evidence file hash-matches => REUSED. Any
    difference => REVERIFY_REQUIRED listing the changed components.
    Evidence file missing or altered => STALE_EVIDENCE.'
    ER-005: 'For non-hermetic facts, consume requires --target; absent =>
    REVERIFY_REQUIRED (no reuse on an unobserved target).'
    ER-003: 'consume never returns the old verdict when its outcome is
    REVERIFY_REQUIRED or STALE_EVIDENCE.'

    drop_verifier_version_mutation: the contract's OWN named paired
    mutation ('drop the verifier-version component from ER-001') --
    deliberately WRONG: never compares verifier_version at all.
    """
    changed = []

    # 1. inputs
    declared_paths = ref["inputs"]["paths"]
    if paths_only_mutation:
        # This dispatch's own named paired mutation ("compare paths
        # instead of content hashes") -- deliberately WRONG: compares only
        # the DECLARED PATH SET against itself (what a real "list the
        # files at these paths" call would return -- the same set, since
        # no fixture in this suite adds or removes a declared path), NEVER
        # re-hashing any file's bytes at all. A same-path content change
        # (er_changed_input's whole point) is therefore structurally
        # invisible to this comparison -- it can only ever detect a path
        # being ADDED or REMOVED, never a path's CONTENT changing.
        live_path_set = set(declared_paths)
        if set(declared_paths) != live_path_set:
            changed.append("inputs:<path added/removed, no content check>")
    else:
        # Real ER-002 semantics: recompute a Merkle root over CURRENT
        # bytes at every declared path.
        live_pairs = recompute_input_pairs(scenario_dir, declared_paths)
        live_root = merkle_root(live_pairs)
        if live_root != ref["inputs"]["root"]:
            # Name each differing path individually (contract: "listing
            # the changed components" / "naming that path") by comparing
            # the RECORDED per-path pairs against the recomputed ones --
            # the aggregate root alone cannot name which path changed.
            recorded = {pr["path"]: pr["content_address"] for pr in ref["inputs"]["pairs"]}
            live = dict(live_pairs)
            for p in declared_paths:
                if recorded.get(p) != live.get(p):
                    changed.append("inputs:%s" % p)
            if not changed:
                # Root differs but no single declared pair differs -- still
                # report the root-level divergence honestly rather than
                # silently naming nothing.
                changed.append("inputs:<root-mismatch, no single path named>")

    # 2. verifier_version (ER-001: content address of the verifier script)
    if not drop_verifier_version_mutation:
        verifier_path = os.path.join(scenario_dir, ref["verifier_id"])
        live_verifier_version = content_address(verifier_path)
        if live_verifier_version != ref["verifier_version"]:
            changed.append("verifier_version")

    # 3. target_fingerprint (ER-002 direct comparison; ER-005 absent-target)
    recorded_target = ref["target_fingerprint"]
    if recorded_target != "hermetic":
        if consume_target is None:
            changed.append("target_fingerprint_unobserved")
        elif consume_target != recorded_target:
            changed.append("target_fingerprint")

    # 4. evidence (STALE_EVIDENCE takes priority over REVERIFY_REQUIRED --
    #    a caller must not be told "just re-verify" when the very evidence
    #    backing the OLD verdict has been tampered with; ER-002 lists this
    #    as its own distinct outcome, not merely another changed component)
    evidence_path = os.path.join(scenario_dir, ref["evidence"]["path"])
    if not os.path.exists(evidence_path):
        evidence_hash_ok = False
    else:
        live_evidence_ca = content_address(evidence_path)
        evidence_hash_ok = (live_evidence_ca == ref["evidence"]["content_address"])

    if not evidence_hash_ok:
        outcome = "STALE_EVIDENCE"
        changed_components = ["evidence"]
    elif changed:
        outcome = "REVERIFY_REQUIRED"
        changed_components = changed
    else:
        outcome = "REUSED"
        changed_components = []

    result = {
        "ref_id": ref["ref_id"],
        "outcome": outcome,
        "changed_components": changed_components,
        "evidence_hash_ok": evidence_hash_ok,
    }
    if outcome == "REUSED":
        result["verdict"] = ref["verdict"]
    return result


def main():
    scenario_dir, ref_path, out_path = sys.argv[1:4]
    consume_target = None
    drop_vv = False
    paths_only = False
    i = 4
    while i < len(sys.argv):
        if sys.argv[i] == "--target":
            consume_target = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == "--drop-verifier-version":
            drop_vv = True
            i += 1
        elif sys.argv[i] == "--paths-only":
            paths_only = True
            i += 1
        else:
            i += 1
    with open(ref_path, encoding="utf-8") as fh:
        ref = json.load(fh)
    result = derive_consume(scenario_dir, ref, consume_target,
                             drop_verifier_version_mutation=drop_vv,
                             paths_only_mutation=paths_only)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, sort_keys=True, indent=2)
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
PYEOF

# --- Helper: compare derived vs expected, ignoring the (deliberately
#     absent when non-REUSED) verdict key subtlety by comparing key sets too ---
compare_outcome() {
  local derived_path="$1" expected_path="$2"
  python3 -c "
import json, sys
d = json.load(open('$derived_path'))
e = json.load(open('$expected_path'))
ok = (d['outcome'] == e['outcome']
      and d['changed_components'] == e['changed_components']
      and d['evidence_hash_ok'] == e['evidence_hash_ok']
      and d.get('verdict') == e.get('verdict')
      and ('verdict' in d) == ('verdict' in e))
print('MATCH' if ok else 'MISMATCH derived=%s expected=%s' % (json.dumps(d, sort_keys=True), json.dumps(e, sort_keys=True)))
"
}

echo
echo "=== T108 contract fixture table (six rows), independent DERIVED oracle ==="
for scen in $SCENARIOS; do
  SDIR="$FIXDIR/$scen"
  REF="$SDIR/ref.json"
  EXPECTED="$SDIR/expected_consume.json"
  CONSUME_TARGET=$(python3 -c "
import json
d = json.load(open('$SDIR/scenario.json'))
t = d.get('consume_target')
print(t if t is not None else '')
")
  DERIVED="$TMP/${scen}.derived.json"
  if [ -n "$CONSUME_TARGET" ]; then
    python3 "$TMP/derive.py" "$SDIR" "$REF" "$DERIVED" --target "$CONSUME_TARGET" >/dev/null
  else
    python3 "$TMP/derive.py" "$SDIR" "$REF" "$DERIVED" >/dev/null
  fi
  RESULT=$(compare_outcome "$DERIVED" "$EXPECTED")
  if [ "$RESULT" = "MATCH" ]; then
    echo "ok $scen: independently-derived consume outcome matches expected_consume.json"
  else
    echo "NOT ok $scen: $RESULT"
    failx
  fi
done

echo
echo "=== ER-005 bonus check: er_changed_target with --target OMITTED entirely ==="
SDIR="$FIXDIR/er_changed_target"
DERIVED_ABSENT="$TMP/er_changed_target.absent.derived.json"
python3 "$TMP/derive.py" "$SDIR" "$SDIR/ref.json" "$DERIVED_ABSENT" >/dev/null
RESULT=$(compare_outcome "$DERIVED_ABSENT" "$SDIR/expected_consume_absent_target.json")
if [ "$RESULT" = "MATCH" ]; then
  echo "ok er_changed_target with --target omitted: ER-005's 'absent target => REVERIFY_REQUIRED"
  echo "   (no reuse on an unobserved target)' correctly triggers, naming"
  echo "   target_fingerprint_unobserved -- distinct from a genuine mismatch"
else
  echo "NOT ok er_changed_target(absent target): $RESULT"
  failx
fi

echo
echo "=== ER-003 no-silent-reuse check: verdict key present iff outcome==REUSED ==="
er3_fail=0
for scen in $SCENARIOS; do
  V="$(python3 -c "
import json
d = json.load(open('$FIXDIR/$scen/expected_consume.json'))
print('present' if 'verdict' in d else 'absent')
")"
  O="$(python3 -c "import json; print(json.load(open('$FIXDIR/$scen/expected_consume.json'))['outcome'])")"
  if [ "$O" = "REUSED" ] && [ "$V" != "present" ]; then
    echo "NOT ok $scen: outcome=REUSED but expected_consume.json has NO verdict key"
    er3_fail=1
    failx
  elif [ "$O" != "REUSED" ] && [ "$V" != "absent" ]; then
    echo "NOT ok $scen: outcome=$O but expected_consume.json STILL carries a verdict"
    echo "     key -- ER-003 requires the old verdict be absent on any non-REUSED"
    echo "     outcome (no silent reuse)"
    er3_fail=1
    failx
  fi
done
if [ "$er3_fail" = 0 ]; then
  echo "ok ER-003: every fixture's expected_consume.json carries a verdict key iff,"
  echo "   and only if, its outcome is REUSED"
fi

echo
echo "=== Self-validation discrimination needles (section 11.4.107(10)/11.4.201(1)) ==="
UNCHANGED_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/er_unchanged/expected_consume.json'))['outcome'])")"
NEGCTRL_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/er_negctrl_unrelated_file/expected_consume.json'))['outcome'])")"
BAD_OUTS="$(for s in er_changed_input er_changed_verifier er_changed_target er_evidence_tampered; do
  python3 -c "import json; print(json.load(open('$FIXDIR/$s/expected_consume.json'))['outcome'])"
done)"
disc_fail=0
if [ "$UNCHANGED_OUT" != "REUSED" ]; then
  echo "NOT ok discrimination: er_unchanged (golden-good) must expect REUSED, got $UNCHANGED_OUT"
  disc_fail=1
  failx
fi
if [ "$NEGCTRL_OUT" != "REUSED" ]; then
  echo "NOT ok discrimination: er_negctrl_unrelated_file (negative-control) must"
  echo "     expect REUSED despite the unrelated file's real content change, got"
  echo "     $NEGCTRL_OUT -- a derivation that flags ANY on-disk change under the"
  echo "     scenario directory (rather than only the DECLARED inputs) would fail"
  echo "     this needle, which is exactly the false-positive guard this fixture exists for"
  disc_fail=1
  failx
fi
for o in $BAD_OUTS; do
  if [ "$o" = "REUSED" ]; then
    echo "NOT ok discrimination: a golden-bad fixture unexpectedly expects REUSED"
    disc_fail=1
    failx
  fi
done
if [ "$disc_fail" = 0 ]; then
  echo "ok discrimination: golden-good (REUSED) and negative-control (REUSED despite"
  echo "   an unrelated real change) both diverge correctly from every golden-bad"
  echo "   fixture (none of which expects REUSED) -- the oracle genuinely"
  echo "   discriminates rather than rubber-stamping every input identically"
fi

echo
echo "=== Paired mutation 1/2 (contract's own, verbatim): drop verifier-version -> er_changed_verifier wrongly REUSED ==="
SDIR="$FIXDIR/er_changed_verifier"
MUT1="$TMP/er_changed_verifier.mut_no_vv.json"
python3 "$TMP/derive.py" "$SDIR" "$SDIR/ref.json" "$MUT1" --drop-verifier-version >/dev/null
MUT1_OUT="$(python3 -c "import json; print(json.load(open('$MUT1'))['outcome'])")"
CORRECT_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/er_changed_verifier/expected_consume.json'))['outcome'])")"
if [ "$MUT1_OUT" = "REUSED" ] && [ "$CORRECT_OUT" = "REVERIFY_REQUIRED" ]; then
  echo "ok mutation 1 (drop verifier-version): the mutated derivation wrongly reports"
  echo "   REUSED on er_changed_verifier (whose verifier.sh genuinely changed) while"
  echo "   the correct derivation reports REVERIFY_REQUIRED -- proving a real"
  echo "   meta-test built against this fixture, once T117 lands, would genuinely"
  echo "   catch this exact mutation (ER-001's fixture-table row)"
else
  echo "NOT ok mutation 1 FAILED: mutated=$MUT1_OUT correct=$CORRECT_OUT (expected"
  echo "     mutated=REUSED, correct=REVERIFY_REQUIRED) -- this fixture would not"
  echo "     catch this mutation and needs revising"
  failx
fi

echo
echo "=== Paired mutation 2/2 (this dispatch's own instructions, verbatim at dispatch time -- see the HONEST NOTE at the top of this file): compare paths instead of content hashes -> er_changed_input wrongly REUSED ==="
SDIR="$FIXDIR/er_changed_input"
MUT2="$TMP/er_changed_input.mut_paths_only.json"
python3 "$TMP/derive.py" "$SDIR" "$SDIR/ref.json" "$MUT2" --paths-only >/dev/null
MUT2_OUT="$(python3 -c "import json; print(json.load(open('$MUT2'))['outcome'])")"
CORRECT2_OUT="$(python3 -c "import json; print(json.load(open('$FIXDIR/er_changed_input/expected_consume.json'))['outcome'])")"
if [ "$MUT2_OUT" = "REUSED" ] && [ "$CORRECT2_OUT" = "REVERIFY_REQUIRED" ]; then
  echo "ok mutation 2 (paths instead of content hashes): the mutated derivation"
  echo "   wrongly reports REUSED on er_changed_input (whose input_a.txt genuinely"
  echo "   changed content at the SAME declared path) while the correct derivation"
  echo "   reports REVERIFY_REQUIRED -- proving a real meta-test built against this"
  echo "   fixture, once T117 lands, would genuinely catch this exact mutation"
  echo "   (this dispatch's own paired-mutation instruction -- see the HONEST"
  echo "   NOTE at the top of this file: not verbatim-quotable from the CURRENT"
  echo "   tasks.md T108 line, which a concurrent process has since trimmed)"
else
  echo "NOT ok mutation 2 FAILED: mutated=$MUT2_OUT correct=$CORRECT2_OUT (expected"
  echo "     mutated=REUSED, correct=REVERIFY_REQUIRED) -- this fixture would not"
  echo "     catch this mutation and needs revising"
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# context/evidence_ref.py lands (T117), this block invokes its real
# `consume` subcommand for every fixture per the contract's own documented
# Invocation section, and separately proves `consume` never invokes the
# verifier (T108's "assert via a verifier stub that records invocations"
# requirement) via a real subprocess side-effect marker file every
# fixture's verifier.sh writes to if actually run.
#
# `create` and `reverify` are NOT exercised here -- an honest, explicit gap
# (see fixtures/evidence_ref/README.md's own "What this RED test does NOT
# cover" section): `create`'s exact `--out` byte-for-byte shape (including
# whether `established_at` is caller-supplied or tool-stamped) is
# genuinely UNCONFIRMED by the contract, and building a create-then-
# compare round-trip on top of that ambiguity would risk a spurious FAIL
# unrelated to `consume`'s own (fully-specified) semantics, which is this
# file's actual scope per T108's task line.
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  echo
  echo "=== Real-tool invocation: context/evidence_ref.py consume ==="
  for scen in $SCENARIOS; do
    SDIR="$FIXDIR/$scen"
    MARKER="$TMP/${scen}.verifier_ran_marker"
    rm -f "$MARKER"
    CONSUME_TARGET=$(python3 -c "
import json
d = json.load(open('$SDIR/scenario.json'))
t = d.get('consume_target')
print(t if t is not None else '')
")
    ACTUAL="$TMP/${scen}.actual_consume.json"
    ERR="$TMP/${scen}.actual_consume.err"
    if [ -n "$CONSUME_TARGET" ]; then
      EVREF_VERIFIER_MARKER="$MARKER" python3 "$IMPL" consume --ref "$SDIR/ref.json" --target "$CONSUME_TARGET" --out "$ACTUAL" >"$ERR" 2>&1
    else
      EVREF_VERIFIER_MARKER="$MARKER" python3 "$IMPL" consume --ref "$SDIR/ref.json" --out "$ACTUAL" >"$ERR" 2>&1
    fi
    RC=$?
    EXPECTED_OUT="$(python3 -c "import json; print(json.load(open('$SDIR/expected_consume.json'))['outcome'])")"
    case "$EXPECTED_OUT" in
      REUSED) want_rc=0 ;;
      REVERIFY_REQUIRED|STALE_EVIDENCE) want_rc=1 ;;
      *) want_rc="" ;;
    esac
    if [ -f "$MARKER" ]; then
      echo "NOT ok $scen: real consume invocation ran the verifier (marker file"
      echo "     created) -- ER-002/T108 require consume NEVER invoke the verifier"
      failx
      continue
    fi
    if [ ! -f "$ACTUAL" ]; then
      echo "NOT ok $scen: real consume invocation wrote no --out document -- $(cat "$ERR" 2>/dev/null)"
      failx
      continue
    fi
    RESULT=$(compare_outcome "$ACTUAL" "$SDIR/expected_consume.json")
    if [ "$RC" = "$want_rc" ] && [ "$RESULT" = "MATCH" ]; then
      echo "ok $scen: real evidence_ref.py consume exited $RC as expected, verifier"
      echo "   was never invoked, and its outcome matches expected_consume.json"
    else
      echo "NOT ok $scen: real consume invocation rc=$RC (wanted $want_rc), $RESULT"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: context/evidence_ref.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T117 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T117 not yet landed); if you see"
  echo "    this, context/evidence_ref.py must have landed AND every fixture check"
  echo "    passed against the real tool. ==="
else
  echo "=== T108 RED BASELINE CONFIRMED: context/evidence_ref.py does not exist"
  echo "    yet (T117 is a separate, later task). The six-row contract fixture"
  echo "    table + the ER-005/ER-003 bonus checks + both named paired mutations,"
  echo "    all independently re-derived and self-validated above, are the interim"
  echo "    contract T117 must satisfy to turn this GREEN. ==="
fi

exit $fail
