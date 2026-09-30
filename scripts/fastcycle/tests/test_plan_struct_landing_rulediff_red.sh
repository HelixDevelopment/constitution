#!/bin/bash
# Purpose : T156 (SpecKit-004 "fast-dev-cycles", User Story 7) RED baseline
#           for the `landing` and `rule-diff` subcommands of
#           `plan_struct_check.py`, per contract
#           plan-research-structural-check.md's SC-C-004 (FR-019) and
#           SC-C-005 (FR-022), plan.md's T-G01/T-G02.
#
# tasks.md:502 (T156): "RED test constitution/scripts/fastcycle/tests/
#   test_plan_struct_landing_rulediff_red.sh (golden-bad: a rule naming a
#   gate with no seam and no ledger deferral FAILs `landing`; golden-bad:
#   a diff changing an existing rule's substance is classified
#   non-structural and FAILs `rule-diff`; negative control: an additive
#   anchor extension PASSes) (plan T-G01, T-G02; FR-019, FR-022, SC-008)".
#
# THE GAP (verified directly, 2026-09-30): plan_struct_check.py exists
# (T046 landed, GO-reviewed) but implements ONLY the `causes` subcommand --
# the module's own docstring states: "the `research`, `plan`, `landing` and
# `rule-diff` subcommands land in T159 and T179". Invoking the contract's
# own documented CLI shape for `landing`/`rule-diff` against today's tool
# (reproduced live below, never assumed -- constitution 11.4.6):
#   $ python3 .../plan_struct_check.py landing --constitution constitution/ \
#       --anchors x --out /tmp/x.json
#   usage: plan_struct_check.py [-h] {causes} ...
#   plan_struct_check.py: error: argument cmd_name: invalid choice: 'landing'
#     (choose from causes)
#   rc=2
# (`rule-diff` behaves identically, substituting its own name).
#
# THE CONTRACT (specs/004-fast-dev-cycles/contracts/
# plan-research-structural-check.md, read in full before writing this file):
#   Invocation:
#     $FC/verify/plan_struct_check.py landing   --constitution constitution/ \
#       --anchors <list> --out <landing.json>      # T-G01, T-G02
#     $FC/verify/plan_struct_check.py rule-diff --constitution constitution/ \
#       --base <sha> --out <rule_diff.json>          # T-G01 (FR-022)
#   SC-C-004 (landing, FR-019): "For each new or changed anchor: exactly one
#     block-start per governance file, content-hash equality across the
#     lockstep mirror set, propagation gate passes (§11.4.227(B)); the
#     existing propagation and block-integrity checks are invoked, not
#     reimplemented."
#   SC-C-005 (rule substance, FR-022): "Emits the diff of every changed
#     existing anchor body; each hunk is tagged ADDITIVE (pure insertion),
#     STRUCTURAL (whitespace/heading/moves with byte-identical content per
#     anchor hash), or SUBSTANTIVE; any SUBSTANTIVE ⇒ exit 1 unless an
#     operator decision record for that anchor is referenced."
#   Exit codes: 0 all checks pass; 1 any structural violation (listing
#     each); 2 usage; 3 needle; 4 document unreadable.
#
# "NO SEAM AND NO LEDGER DEFERRAL" -- WHERE THIS COMES FROM (not invented,
# constitution 11.4.6): T156's own task line names exactly the §11.4.227(A)
# mechanism this repository ALREADY ships as
# `constitution/scripts/gates/gate_ledger.sh` (its own header: "every CM-*
# token NAMED in the governance corpus [is] either IMPLEMENTED ... or
# covered by a REGISTERED DEFERRAL row ... Tokens satisfying NEITHER are
# UNIMPLEMENTED"). SC-C-004's own words -- "the existing propagation and
# block-integrity checks are invoked, not reimplemented" -- establish that
# the FUTURE `landing` subcommand (T159) is expected to invoke exactly this
# class of existing mechanism rather than re-derive it; this file's own
# independent verifier therefore calls the REAL, already-shipped
# `gate_ledger.sh` DIRECTLY -- a genuinely SEPARATE tool from
# `plan_struct_check.py` (Producer != Verifier, constitution 11.4.240) -- to
# prove, today, that a fictional gate token invented for this fixture and
# occurring nowhere else in this repository (grep-verified below, zero
# hits) is mechanically UNIMPLEMENTED against the REAL implementation tree
# (`constitution/scripts/fastcycle`) with an empty deferrals registry, and
# genuinely flips to DEFERRED once its deferral is registered (a
# false-positive guard, constitution 11.4.201(1) -- proving this instrument
# genuinely distinguishes the two states rather than always reporting
# UNIMPLEMENTED regardless of input).
#
# "RULE-DIFF SUBSTANCE CLASSIFICATION" -- a second, self-contained Python
# instrument (`classify_diff`, embedded below -- NOT plan_struct_check.py
# and NOT gate_ledger.sh) using stdlib `difflib.SequenceMatcher` opcodes
# over two file bodies: any `delete`/`replace` opcode (existing wording
# removed or reworded) ⇒ SUBSTANTIVE; only `insert`/`equal` opcodes
# (nothing existing removed or reworded) ⇒ ADDITIVE; identical bodies ⇒
# UNCHANGED. This is a deliberately NARROW reading of SC-C-005's three-way
# tag set -- it does NOT attempt STRUCTURAL classification (whitespace /
# heading / moves with byte-identical content per anchor hash is a
# SEPARATE, later T159 concern, not one of T156's two named checks) --
# honestly disclosed, never silently assumed covered (constitution 11.4.6).
#
# Producer != Verifier (constitution 11.4.240): this file is authored at
# the RED step (T156); T159's implementation of `plan_struct_check.py
# landing` and `rule-diff` is a LATER, SEPARATE task -- this file's author
# never implements it. Both independent instruments used to validate this
# file's own fixtures (`gate_ledger.sh`, already shipped and already tested
# elsewhere in this suite, and the embedded `classify_diff` heredoc) are
# genuinely SEPARATE from `plan_struct_check.py` -- exactly the role
# test_plan_struct_causes_red.sh's own `register_audit` instrument already
# plays for its sibling `causes` subcommand.
#
# SCOPE NOTE (this task's own hard scope limit): every fixture used below
# is constructed IN-PROCESS, at runtime, inside a `mktemp -d` scratch
# directory -- no fixture file is added anywhere under version control by
# this task; this script is the ONLY new file. The one exception the
# §11.4.227(A) mechanism itself requires -- `gate_ledger.sh`'s own
# tracked-ness resolution REFUSES (BLIND, exit 2) to scan an `--impl-dir`
# that is not inside a real git repository (verified live during authoring;
# a plain `mktemp -d` scratch directory is NOT inside a repository and
# trips this refusal) -- is satisfied by pointing it at the REAL,
# already-committed `constitution/scripts/gates` tree as the scanned
# implementation directory (a read-only scan; nothing is written there),
# which is exactly where a genuine seam for a newly-recommended gate token
# would be expected to live, and demonstrably does not contain this
# fixture's fictional token (grep-verified below).
#
# SELF-MATCH FOOTGUN, FOUND AND FIXED WHILE AUTHORING THIS FILE (constitution
# §11.4.196(D)/§12.12/§11.4.201(7)(a) -- a carrier that MENTIONS a token is
# not the thing itself): `gate_ledger.sh`'s own documented canonical scan
# root is `constitution/scripts` in general, and this file's FIRST draft
# pointed the landing instrument at `constitution/scripts/fastcycle` (the
# `$FC` variable already in scope) -- which recursively includes THIS VERY
# TEST SCRIPT under `fastcycle/tests/`. Because this script's own source
# necessarily contains the literal fixture gate token (as fixture data, in
# variable assignments and echo lines), it would itself satisfy
# `gate_ledger.sh`'s boundary-anchored `grep` for that token the moment this
# file is `git add`ed and therefore counted TRACKED -- silently flipping the
# golden-bad fixture's expected UNIMPLEMENTED verdict to a false
# IMPLEMENTED once this script is staged (the exact carrier-vs-thing
# footgun this project's own §11.4.201(7)(a) anchor describes, discovered
# here empirically via the broad repo-wide sanity grep below, not assumed).
# Fixed by scanning `constitution/scripts/gates` instead -- a real,
# git-tracked directory that structurally cannot contain this test script
# (it lives under `fastcycle/tests/`, a sibling subtree) and is exactly
# where a genuine gate seam would be expected to live.
#
# §11.4.273 control needle (for this file's own path-resolution mechanism):
# before trusting any "absent" finding below, this file first proves its
# own relative-path construction genuinely resolves two KNOWN-PRESENT
# siblings -- `lib/fc_common.py` (the same needle
# test_plan_struct_causes_red.sh uses) and `../gates/gate_ledger.sh` (the
# independent landing-instrument this file depends on) -- through the SAME
# construction used for the real assertions later in this file.
#
# Usage : bash test_plan_struct_landing_rulediff_red.sh   Exit 0 = GREEN
#         (POST-T159 REMEDIATION, matching test_plan_struct_causes_red.sh's
#         own post-landing remediation pattern named in this file's header
#         above): sections (2)-(3) now invoke the REAL, landed `landing`/
#         `rule-diff` subcommands against real repository data and assert a
#         genuine decided verdict + well-formed --out JSON (T159 landed --
#         see the module docstring of plan_struct_check.py), while every
#         fixture design and independent-instrument cross-check below --
#         one golden-bad per subcommand plus the negative control,
#         independently verified via SEPARATE instruments (gate_ledger.sh;
#         an embedded difflib classifier) to encode exactly the defect/
#         non-defect each is designed to encode, each with its own
#         false-positive guard per constitution 11.4.201(1) -- is preserved
#         UNCHANGED from this file's original RED-baseline authoring.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
TOOL="$FC/verify/plan_struct_check.py"
GATE_LEDGER="$ROOT/constitution/scripts/gates/gate_ledger.sh"

fail=0
failx() { fail=1; }

TMP=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# --- §11.4.273 control needle: prove the relative-path mechanism itself
#     resolves BOTH siblings this file depends on ---
for needle in "$FC/lib/fc_common.py" "$GATE_LEDGER"; do
  if [ ! -f "$needle" ]; then
    echo "NOT ok control needle failed: a KNOWN-PRESENT sibling file"
    echo "     ($needle) does not resolve -- this test's relative-path"
    echo "     computation is broken, so every finding below proves nothing"
    echo "     (§11.4.273)"
    failx
  else
    echo "ok control needle: known-present sibling $needle resolves through"
    echo "   this test's own path construction -- the checks below can be"
    echo "   trusted"
  fi
done

# --- (1) Tool existence (informational -- T046 already landed) ---
if [ -f "$TOOL" ]; then
  echo "ok verify/plan_struct_check.py exists (T046 landed causes; T159"
  echo "   (this task) adds landing/rule-diff -- research/plan remain T179's"
  echo "   own separate scope, per its own module docstring) -- the"
  echo "   CLI-level checks below are the real evidence for THIS task"
else
  echo "NOT ok verify/plan_struct_check.py is absent entirely -- T046 was"
  echo "     reviewed GO and committed; a regression removed the whole file"
  failx
fi

# --- (2) Real CLI invocation: `landing` subcommand now exists (T159 landed) -- REMEDIATED from
#     this file's own original RED-baseline absence check (which asserted rc=2 "invalid choice")
#     to a genuine verdict check, per this task's own explicit instruction: adjust ONLY the
#     absence assertions to GREEN verdict assertions, minimally, preserving every fixture design
#     and independent-instrument cross-check above/below unchanged. Real anchor §11.4.230 is
#     used (a REAL, already-landed anchor with a REAL registered
#     CM-COVENANT-114-230-PROPAGATION wrapper) -- this is a genuine smoke test against REAL data,
#     not a re-run of the synthetic golden-bad-landing fixture above (which already independently
#     proved the UNIMPLEMENTED/DEFERRED distinction via the real gate_ledger.sh directly, and
#     stays completely untouched). §11.4.230's own recommended gates are honestly, currently
#     UNIMPLEMENTED (gate-code explicitly deferred as separate work items per its own text) --
#     the assertion below therefore accepts EITHER a real decided verdict (rc=0 clean, or rc=1
#     naming a real violation), never a specific one, so this test does not silently start
#     failing the moment a real gate lands or a deferral is registered (§11.4.6: asserting a
#     status this file has not independently verified would itself be a guess).
python3 "$TOOL" landing --constitution "$ROOT/constitution/" --anchors 11.4.230 \
  --out "$TMP/landing.json" >"$TMP/landing_invoke.out" 2>"$TMP/landing_invoke.err"
LANDING_RC=$?
LANDING_ERR=$(cat "$TMP/landing_invoke.err" 2>/dev/null)
echo "info landing invocation today: rc=$LANDING_RC stderr='$LANDING_ERR'"
if [ "$LANDING_RC" -eq 0 ] || [ "$LANDING_RC" -eq 1 ]; then
  echo "ok landing subcommand exists and returned a genuine decided verdict"
  echo "   (rc=$LANDING_RC -- 0=clean or 1=violation(s) named; never argparse's"
  echo "   'invalid choice' usage error 2, never needle-failure 3, never BLIND 4)"
else
  echo "NOT ok landing invocation against a REAL anchor (§11.4.230) did not"
  echo "     return a decided verdict (0 or 1) -- got rc=$LANDING_RC; either the"
  echo "     subcommand is not landed as expected, or it could not produce an"
  echo "     honest verdict against real repository data -- stderr: $LANDING_ERR"
  failx
fi
if [ ! -s "$TMP/landing.json" ]; then
  echo "NOT ok landing invocation wrote no (or an empty) --out JSON despite a"
  echo "     decided verdict (rc=$LANDING_RC) -- a real verdict must always be"
  echo "     written on exit 0/1 (the causes subcommand's own documented"
  echo "     C-001 'Side-effects' convention)"
  failx
elif ! python3 -c "
import json, sys
with open('$TMP/landing.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc.get('schema') == 'plan-struct-landing/v1', doc.get('schema')
assert isinstance(doc.get('anchors'), list) and len(doc['anchors']) == 1, doc.get('anchors')
assert doc['anchors'][0]['anchor'] == '11.4.230', doc['anchors'][0]
assert doc['anchors'][0]['found'] is True, doc['anchors'][0]
assert isinstance(doc.get('violations'), list), doc.get('violations')
" 2>"$TMP/landing_json_check.err"; then
  echo "NOT ok landing --out JSON did not carry the expected schema/shape for"
  echo "     anchor 11.4.230 -- $(cat "$TMP/landing_json_check.err" 2>/dev/null)"
  failx
else
  echo "ok landing --out JSON carries schema plan-struct-landing/v1, one"
  echo "   anchor result for the requested 11.4.230, found=true, and a"
  echo "   well-formed violations list"
fi

# --- (3) Real CLI invocation: `rule-diff` subcommand now exists (T159 landed) -- REMEDIATED
#     from this file's own original RED-baseline absence check to a genuine verdict check, same
#     minimal-edit rule as (2) above. `--base HEAD` diffs the current Constitution.md against
#     itself (before == after byte-for-byte), which is DETERMINISTICALLY exit 0 with zero hunks
#     regardless of real corpus content -- a safe, real-data smoke test with a guaranteed outcome
#     (the negative-control "UNCHANGED" case the embedded classify_diff instrument below already
#     independently proves, exercised here through the real CLI + real git integration instead).
python3 "$TOOL" rule-diff --constitution "$ROOT/constitution/" --base HEAD \
  --out "$TMP/rulediff.json" >"$TMP/rulediff_invoke.out" 2>"$TMP/rulediff_invoke.err"
RULEDIFF_RC=$?
RULEDIFF_ERR=$(cat "$TMP/rulediff_invoke.err" 2>/dev/null)
echo "info rule-diff invocation today: rc=$RULEDIFF_RC stderr='$RULEDIFF_ERR'"
if [ "$RULEDIFF_RC" -eq 0 ]; then
  echo "ok rule-diff subcommand exists and returned the deterministically"
  echo "   correct verdict (rc=0, no violations) for --base HEAD against the"
  echo "   current, byte-identical Constitution.md"
else
  echo "NOT ok rule-diff invocation with --base HEAD (before == after, must"
  echo "     be a guaranteed clean verdict) did not return rc=0 -- got"
  echo "     rc=$RULEDIFF_RC -- stderr: $RULEDIFF_ERR"
  failx
fi
if [ ! -s "$TMP/rulediff.json" ]; then
  echo "NOT ok rule-diff invocation wrote no (or an empty) --out JSON despite"
  echo "     a decided rc=0 verdict"
  failx
elif ! python3 -c "
import json
with open('$TMP/rulediff.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc.get('schema') == 'plan-struct-rule-diff/v1', doc.get('schema')
assert doc.get('hunks') == [], doc.get('hunks')
assert doc.get('violations') == [], doc.get('violations')
" 2>"$TMP/rulediff_json_check.err"; then
  echo "NOT ok rule-diff --out JSON did not carry the expected zero-hunks/"
  echo "     zero-violations shape for --base HEAD -- $(cat "$TMP/rulediff_json_check.err" 2>/dev/null)"
  failx
else
  echo "ok rule-diff --out JSON carries schema plan-struct-rule-diff/v1 with"
  echo "   zero hunks and zero violations for the identical --base HEAD"
  echo "   comparison"
fi

# ---------------------------------------------------------------------------
# Independent instrument A (landing): the REAL, already-shipped
# constitution/scripts/gates/gate_ledger.sh -- genuinely SEPARATE from
# plan_struct_check.py (Producer != Verifier, §11.4.240) -- proving a
# fictional gate token this fixture invents is genuinely UNIMPLEMENTED (no
# seam anywhere in the real implementation tree, no ledger deferral) and
# genuinely DEFERRED once its deferral is registered (false-positive guard,
# §11.4.201(1)).
# ---------------------------------------------------------------------------
NEEDLE_GATE="CM-T156-FIXTURE-NEEDLE-BAD"
GATES_DIR="$ROOT/constitution/scripts/gates"

# Sanity: the fictional token must occur nowhere in the REAL directory this
# instrument is about to scan for a seam -- else the fixture would not be
# testing an absent seam at all. Deliberately scoped to $GATES_DIR, NOT the
# whole repository: this script's OWN source necessarily mentions the token
# (as fixture data, below), and a whole-repo sweep would self-match THIS
# FILE once it is tracked -- the exact carrier-vs-thing footgun this file's
# own header section discusses (constitution §11.4.201(7)(a)), found while
# authoring this file and fixed by narrowing the scan target instead of the
# sanity check's scope (§11.4.6 -- fix the instrument, not the symptom).
if grep -rq -- "$NEEDLE_GATE" "$GATES_DIR" 2>/dev/null; then
  echo "NOT ok fixture gate token $NEEDLE_GATE already occurs somewhere"
  echo "     under $GATES_DIR -- pick a different, genuinely unused token"
  failx
else
  echo "ok fixture gate token $NEEDLE_GATE occurs nowhere under"
  echo "   $GATES_DIR today (grep-verified) -- the fixture genuinely tests"
  echo "   an absent seam, not an accidental real one"
fi

cat >"$TMP/landing_anchor.md" <<EOF
### §11.4.900 -- T156 RED-fixture anchor (never a real anchor; synthetic)

Recommended gate \`$NEEDLE_GATE\` MUST assert the T156 fixture condition.
EOF

printf '# T156 RED-fixture deferrals registry (empty -- no row for %s)\n' \
  "$NEEDLE_GATE" >"$TMP/landing_deferrals_empty.tsv"
printf '%s\tATM-T156-FIXTURE\tRED-fixture-only, never a real deferral\n' \
  "$NEEDLE_GATE" >"$TMP/landing_deferrals_with_entry.tsv"

# golden-bad-landing: no seam (real $GATES_DIR tree, no hit possible) +
# empty deferrals registry => UNIMPLEMENTED.
bash "$GATE_LEDGER" generate "$GATES_DIR" "$TMP/landing_deferrals_empty.tsv" \
  "$TMP/landing_anchor.md" >"$TMP/ledger_undeferred.out" 2>"$TMP/ledger_undeferred.err"
LEDGER_UNDEF_RC=$?
UNDEF_LINE=$(grep -F "$NEEDLE_GATE" "$TMP/ledger_undeferred.out" 2>/dev/null)
EXPECT_UNDEF=$(printf '%s\tUNIMPLEMENTED\t-' "$NEEDLE_GATE")
if [ "$LEDGER_UNDEF_RC" -eq 0 ] && [ "$UNDEF_LINE" = "$EXPECT_UNDEF" ]; then
  echo "ok golden-bad-landing independently confirmed via the REAL,"
  echo "   already-shipped gate_ledger.sh: a rule naming gate $NEEDLE_GATE"
  echo "   with NO seam anywhere in the real $GATES_DIR tree and NO"
  echo "   ledger-deferral row is mechanically UNIMPLEMENTED today --"
  echo "   exactly the defect the future \`landing\` subcommand must flag"
  echo "   (contract SC-C-004, exit 1, naming the gate)"
else
  echo "NOT ok golden-bad-landing: expected gate_ledger.sh generate to"
  echo "     report '$EXPECT_UNDEF' (rc=0), got rc=$LEDGER_UNDEF_RC"
  echo "     line='$UNDEF_LINE' -- stderr:"
  echo "     $(cat "$TMP/ledger_undeferred.err" 2>/dev/null)"
  failx
fi

# false-positive guard: registering the SAME gate's deferral must flip the
# SAME instrument's verdict to DEFERRED -- proving it distinguishes the two
# states rather than always reporting UNIMPLEMENTED.
bash "$GATE_LEDGER" generate "$GATES_DIR" "$TMP/landing_deferrals_with_entry.tsv" \
  "$TMP/landing_anchor.md" >"$TMP/ledger_deferred.out" 2>"$TMP/ledger_deferred.err"
LEDGER_DEF_RC=$?
DEF_LINE=$(grep -F "$NEEDLE_GATE" "$TMP/ledger_deferred.out" 2>/dev/null)
EXPECT_DEF=$(printf '%s\tDEFERRED\tATM-T156-FIXTURE' "$NEEDLE_GATE")
if [ "$LEDGER_DEF_RC" -eq 0 ] && [ "$DEF_LINE" = "$EXPECT_DEF" ]; then
  echo "ok false-positive guard (§11.4.201(1)): registering the SAME gate's"
  echo "   deferral (a real §11.4.227(A) ledger row, ATM-T156-FIXTURE) flips"
  echo "   the SAME instrument's verdict to DEFERRED -- this instrument"
  echo "   genuinely distinguishes 'no seam, no deferral' from 'no seam,"
  echo "   WITH a registered deferral'; it does not merely always report"
  echo "   UNIMPLEMENTED regardless of input"
else
  echo "NOT ok false-positive guard failed: expected '$EXPECT_DEF' (rc=0)"
  echo "     once the deferral is registered, got rc=$LEDGER_DEF_RC"
  echo "     line='$DEF_LINE' -- stderr:"
  echo "     $(cat "$TMP/ledger_deferred.err" 2>/dev/null)"
  failx
fi

# ---------------------------------------------------------------------------
# Independent instrument B (rule-diff): a self-contained, embedded Python
# instrument (NOT plan_struct_check.py, NOT gate_ledger.sh) classifying a
# before/after body pair via stdlib difflib.SequenceMatcher opcodes --
# deliberately narrow (see header): any delete/replace opcode => SUBSTANTIVE;
# only insert/equal opcodes => ADDITIVE; identical bodies => UNCHANGED.
# STRUCTURAL classification is explicitly OUT OF SCOPE for T156's two named
# checks (honest disclosure, §11.4.6).
# ---------------------------------------------------------------------------
classify_diff() {
  python3 - "$1" "$2" <<'PY'
import difflib
import sys


def classify(before, after):
    b = before.splitlines()
    a = after.splitlines()
    if a == b:
        return "UNCHANGED"
    sm = difflib.SequenceMatcher(a=b, b=a, autojunk=False)
    saw_delete_or_replace = False
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag in ("delete", "replace"):
            saw_delete_or_replace = True
    return "SUBSTANTIVE" if saw_delete_or_replace else "ADDITIVE"


with open(sys.argv[1], encoding="utf-8") as fh:
    before_text = fh.read()
with open(sys.argv[2], encoding="utf-8") as fh:
    after_text = fh.read()
print(classify(before_text, after_text))
PY
}

cat >"$TMP/rulediff_sub_before.md" <<'EOF'
### §11.4.901 -- T156 RED-fixture anchor (rule-diff substantive; synthetic)

The gate MUST refuse a claim whose only support is an uncited signal.
EOF

cat >"$TMP/rulediff_sub_after.md" <<'EOF'
### §11.4.901 -- T156 RED-fixture anchor (rule-diff substantive; synthetic)

The gate SHOULD refuse a claim whose only support is an uncited signal.
EOF

cat >"$TMP/rulediff_add_before.md" <<'EOF'
### §11.4.902 -- T156 RED-fixture anchor (rule-diff additive; synthetic)

The gate MUST refuse a claim whose only support is an uncited signal.
EOF

cat >"$TMP/rulediff_add_after.md" <<'EOF'
### §11.4.902 -- T156 RED-fixture anchor (rule-diff additive; synthetic)

The gate MUST refuse a claim whose only support is an uncited signal.

Extension (synthetic, T156 fixture only): the gate additionally records the
refusal reason in the evidence chain.
EOF

# golden-bad-rulediff-substantive: an existing rule's wording changed
# (MUST -> SHOULD), nothing else -- classified SUBSTANTIVE.
SUB_CLASS=$(classify_diff "$TMP/rulediff_sub_before.md" "$TMP/rulediff_sub_after.md" 2>"$TMP/classify_sub.err")
if [ "$SUB_CLASS" = "SUBSTANTIVE" ]; then
  echo "ok golden-bad-rulediff-substantive independently confirmed:"
  echo "   changing an existing rule's wording (MUST -> SHOULD, nothing"
  echo "   else) is classified SUBSTANTIVE by this file's own embedded"
  echo "   classifier -- exactly the defect the future \`rule-diff\`"
  echo "   subcommand must catch (contract SC-C-005: any SUBSTANTIVE"
  echo "   => exit 1)"
else
  echo "NOT ok golden-bad-rulediff-substantive: expected classification"
  echo "     SUBSTANTIVE, got '$SUB_CLASS' -- stderr:"
  echo "     $(cat "$TMP/classify_sub.err" 2>/dev/null)"
  failx
fi

# negative control: only a new paragraph appended, the existing sentence
# untouched -- classified ADDITIVE.
ADD_CLASS=$(classify_diff "$TMP/rulediff_add_before.md" "$TMP/rulediff_add_after.md" 2>"$TMP/classify_add.err")
if [ "$ADD_CLASS" = "ADDITIVE" ]; then
  echo "ok negative control confirmed: an additive anchor extension (a new"
  echo "   paragraph appended, the existing sentence untouched) is"
  echo "   classified ADDITIVE by the SAME embedded classifier -- once T159"
  echo "   lands, this is the case \`rule-diff\` must PASS (contract"
  echo "   SC-C-005: only SUBSTANTIVE hunks fail)"
else
  echo "NOT ok negative control FAILED: expected classification ADDITIVE"
  echo "     for a pure-append diff, got '$ADD_CLASS' -- stderr:"
  echo "     $(cat "$TMP/classify_add.err" 2>/dev/null)"
  failx
fi

# false-positive guard (§11.4.201(1)): an identical before/after pair must
# classify UNCHANGED, never SUBSTANTIVE (nor ADDITIVE) -- proving the
# classifier does not spuriously flag a no-op diff.
NOOP_CLASS=$(classify_diff "$TMP/rulediff_sub_before.md" "$TMP/rulediff_sub_before.md" 2>"$TMP/classify_noop.err")
if [ "$NOOP_CLASS" = "UNCHANGED" ]; then
  echo "ok false-positive guard: an identical before/after pair classifies"
  echo "   UNCHANGED, never SUBSTANTIVE -- the classifier does not"
  echo "   spuriously flag a no-op diff as the defect it exists to catch"
else
  echo "NOT ok false-positive guard failed: identical before/after pair"
  echo "     classified '$NOOP_CLASS', expected UNCHANGED"
  failx
fi


# ---------------------------------------------------------------------------
# REVIEW-ROUND-1 REMEDIATION (I1, independent §11.4.209 Opus-xhigh review of T159): every
# golden-bad / negative-control fixture ABOVE was, until now, only fed to the INDEPENDENT
# instrument (gate_ledger.sh; the embedded classify_diff() heredoc) -- never to
# plan_struct_check.py's own `landing`/`rule-diff` subcommands themselves, so a mutation that
# neutered THIS TOOL's own decision logic (e.g. forcing `rc = 0` unconditionally, or dropping a
# violation class) would have left every assertion above GREEN. This section closes that gap: it
# builds fully self-contained, isolated "fake constitution" fixture trees (own git repo, own
# scripts/gates/ tree -- touching nothing under the real, tracked constitution/ checkout) and
# feeds them to the REAL `plan_struct_check.py landing`/`rule-diff` CLI, asserting the CORRECT
# exit code + --out JSON shape for each -- then, as this task's own instruction requires,
# demonstrates the strengthening directly: a throwaway MUTATED COPY of the tool (never the
# tracked file) with its own exit-code computation forced to 0 is proven to WRONGLY pass the
# SAME golden-bad fixture the real tool correctly fails, showing this section's own assertions
# are exactly what would have caught that class of regression.
# ---------------------------------------------------------------------------

echo
echo "=== I1 remediation: real end-to-end \`landing\` CLI over an isolated fixture ==="

FAKECONST_L="$TMP/fakeconst_landing"
mkdir -p "$FAKECONST_L/scripts/gates"
cp "$GATE_LEDGER" "$FAKECONST_L/scripts/gates/gate_ledger.sh"
cat >"$FAKECONST_L/Constitution.md" <<EOF
### §11.4.988 -- T156 real-CLI landing fixture anchor (never a real anchor; synthetic)

Recommended gate \`$NEEDLE_GATE\` MUST hold.
EOF
: >"$FAKECONST_L/scripts/gates/gate_ledger_deferrals.tsv"
: >"$FAKECONST_L/scripts/gates/covenant_propagation_anchors.tsv"
(
  cd "$FAKECONST_L" \
    && git init -q \
    && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" \
    && git add -A \
    && git commit -q -m "v1: golden-bad-landing real-CLI fixture (isolated, never pushed)"
) >"$TMP/fakeconst_landing_git.log" 2>&1
FAKECONST_L_INIT_RC=$?
if [ "$FAKECONST_L_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated landing fixture tree -- see"
  echo "     $TMP/fakeconst_landing_git.log"
  failx
fi

# --- golden-bad-landing, REAL CLI: no seam anywhere in this isolated tree, no deferral, no
#     registered propagation wrapper -- BOTH gate_unimplemented AND (B3) propagation_gate_not_registered
python3 "$TOOL" landing --constitution "$FAKECONST_L" --anchors 988 \
  --out "$TMP/fake_landing_bad.json" >"$TMP/fl_bad.out" 2>"$TMP/fl_bad.err"
FL_BAD_RC=$?
if [ "$FL_BAD_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/fake_landing_bad.json', encoding='utf-8') as fh:
    doc = json.load(fh)
codes = sorted(v['code'] for v in doc['violations'])
assert 'gate_unimplemented' in codes, doc['violations']
assert 'propagation_gate_not_registered' in codes, doc['violations']
" 2>"$TMP/fl_bad_check.err"; then
  echo "ok golden-bad-landing REAL CLI: \`landing\` itself (not merely the independent"
  echo "   gate_ledger.sh instrument) exits 1 against the isolated fixture, naming BOTH"
  echo "   gate_unimplemented (the needle gate, no seam/no deferral) AND (B3, review round 1)"
  echo "   propagation_gate_not_registered (no wrapper registered for anchor 988 at all)"
else
  echo "NOT ok golden-bad-landing REAL CLI FAILED: expected rc=1 with both"
  echo "     gate_unimplemented and propagation_gate_not_registered violations --"
  echo "     got rc=$FL_BAD_RC, check error: $(cat "$TMP/fl_bad_check.err" 2>/dev/null)"
  failx
fi

# --- negative control, REAL CLI: SAME fixture, now with the needle gate's deferral registered
#     AND a real propagation wrapper registered+present+exiting 0 -- `landing` itself must
#     genuinely flip to a clean rc=0, proving it does not always report FAIL regardless of input.
printf '%s\tATM-T156-FIXTURE-CLI\tRED-fixture-only, never a real deferral\n' "$NEEDLE_GATE" \
  >"$FAKECONST_L/scripts/gates/gate_ledger_deferrals.tsv"
cat >"$FAKECONST_L/scripts/gates/cm_fake_988_propagation.sh" <<'EOF'
#!/usr/bin/env bash
# T156 real-CLI fixture wrapper -- a synthetic stand-in for a genuinely-propagated anchor,
# always exits 0 regardless of its --root/--quiet args. NEVER a real
# CM-COVENANT-114-<N>-PROPAGATION gate.
exit 0
EOF
printf 'CM-FAKE-988-PROPAGATION\t11.4.988\n' >"$FAKECONST_L/scripts/gates/covenant_propagation_anchors.tsv"
( cd "$FAKECONST_L" && git add -A ) >"$TMP/fakeconst_landing_git2.log" 2>&1

python3 "$TOOL" landing --constitution "$FAKECONST_L" --anchors 988 \
  --out "$TMP/fake_landing_good.json" >"$TMP/fl_good.out" 2>"$TMP/fl_good.err"
FL_GOOD_RC=$?
if [ "$FL_GOOD_RC" -eq 0 ] && python3 -c "
import json
with open('$TMP/fake_landing_good.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [], doc['violations']
prop = doc['anchors'][0]['propagation']
assert prop['registered'] is True, prop
assert prop['rc'] == 0, prop
gates = doc['anchors'][0]['gates']
assert any(g['status'] == 'DEFERRED' for g in gates), gates
" 2>"$TMP/fl_good_check.err"; then
  echo "ok negative control (landing, REAL CLI): once the needle gate's deferral is"
  echo "   registered AND a real, present, exit-0 propagation wrapper is registered for"
  echo "   anchor 988, \`landing\` itself genuinely reports a clean rc=0 -- it does not"
  echo "   always report a violation regardless of input"
else
  echo "NOT ok negative control (landing, REAL CLI) FAILED: expected a clean rc=0 once"
  echo "     the deferral + wrapper are registered -- got rc=$FL_GOOD_RC, check error:"
  echo "     $(cat "$TMP/fl_good_check.err" 2>/dev/null)"
  failx
fi

# --- mutation-catching proof (I1's own explicit instruction): a throwaway MUTATED COPY of the
#     tool (never the tracked file) with cmd_landing's own exit-code computation forced to 0
#     unconditionally is proven to WRONGLY pass the SAME golden-bad fixture the golden-bad-landing
#     assertion above correctly failed -- demonstrating this section's own [ "$FL_BAD_RC" -eq 1 ]
#     assertion is exactly what would catch this exact class of regression.
# A copy of the tool dropped bare into $TMP breaks its own `sys.path` wiring to the sibling
# `../lib/fc_common.py` module (plan_struct_check.py resolves that path relative to its OWN
# `__file__`) -- so the mutated copy lives under its own `verify/` subdirectory alongside a
# SYMLINKED `lib/` pointing at the real, unmutated `constitution/scripts/fastcycle/lib/`,
# reproducing the exact sibling layout the tool's own import expects.
MUT_LANDING_ROOT="$TMP/mut_landing_root"
mkdir -p "$MUT_LANDING_ROOT/verify"
ln -s "$FC/lib" "$MUT_LANDING_ROOT/lib"
MUT_LANDING="$MUT_LANDING_ROOT/verify/plan_struct_check.py"
cp "$TOOL" "$MUT_LANDING"
python3 - "$MUT_LANDING" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
needle = (
    '    if violations and all(v["code"] == "propagation_gate_blind" for v in violations):\n'
    '        rc = 4\n'
    '    else:\n'
    '        rc = 1 if violations else 0\n'
)
if needle not in src:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
mutated = src.replace(
    needle,
    '    rc = 0  # I1 MUTATION (throwaway copy): force-pass regardless of violations\n',
    1,
)
if mutated == src:
    print("MUTATION-DID-NOT-CHANGE-FILE", file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(mutated)
PY
MUT_L_PREP_RC=$?
if [ "$MUT_L_PREP_RC" -ne 0 ]; then
  echo "NOT ok could not prepare the landing mutation fixture (cmd_landing's own"
  echo "     exit-code computation text has changed shape -- update this mutation"
  echo "     test's anchor text to match)"
  failx
else
  python3 "$MUT_LANDING" landing --constitution "$FAKECONST_L" --anchors 988 \
    --out "$TMP/fake_landing_mut.json" >"$TMP/fl_mut.out" 2>"$TMP/fl_mut.err"
  FL_MUT_RC=$?
  if [ "$FL_MUT_RC" -eq 0 ]; then
    echo "ok mutation-catching proof (landing): a throwaway mutated copy that forces"
    echo "   rc=0 unconditionally WRONGLY passes the SAME golden-bad fixture the real"
    echo "   tool (rc=$FL_BAD_RC) correctly failed -- proving the real-CLI assertion"
    echo "   above is exactly what would catch this exact regression class (I1)"
  else
    echo "NOT ok mutation-catching proof (landing) FAILED: expected the mutated copy"
    echo "     to wrongly report rc=0, got rc=$FL_MUT_RC -- the mutation did not take"
    echo "     effect as designed"
    failx
  fi
fi

echo
echo "=== I1 remediation: real end-to-end \`rule-diff\` CLI over an isolated fixture ==="

FAKECONST_R="$TMP/fakeconst_ruledif"
mkdir -p "$FAKECONST_R"
(
  cd "$FAKECONST_R" \
    && git init -q \
    && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture"
) >"$TMP/fakeconst_ruledif_git_init.log" 2>&1
FAKECONST_R_INIT_RC=$?
if [ "$FAKECONST_R_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated rule-diff fixture tree -- see"
  echo "     $TMP/fakeconst_ruledif_git_init.log"
  failx
fi

cat >"$FAKECONST_R/Constitution.md" <<'EOF'
### §11.4.989 -- T156 real-CLI rule-diff fixture anchor (never a real anchor; synthetic)

The gate MUST refuse a claim whose only support is an uncited signal.
EOF
( cd "$FAKECONST_R" && git add -A && git commit -q -m "v1: base" ) >"$TMP/rd_commit_v1.log" 2>&1
V1=$(cd "$FAKECONST_R" && git rev-parse HEAD)

sed -i 's/MUST refuse/SHOULD refuse/' "$FAKECONST_R/Constitution.md"
( cd "$FAKECONST_R" && git add -A && git commit -q -m "v2: substantive reword" ) >"$TMP/rd_commit_v2.log" 2>&1
V2=$(cd "$FAKECONST_R" && git rev-parse HEAD)

# --- golden-bad-rulediff-substantive, REAL CLI: v1 -> v2 reworded an existing sentence
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V1" \
  --out "$TMP/rd_bad.json" >"$TMP/rd_bad.out" 2>"$TMP/rd_bad.err"
RD_BAD_RC=$?
if [ "$RD_BAD_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/rd_bad.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'substantive_change', 'anchor': '11.4.989'}], doc['violations']
assert doc['hunks'][0]['classification'] == 'SUBSTANTIVE', doc['hunks']
assert doc['hunks'][0]['exempted'] is None, doc['hunks']
" 2>"$TMP/rd_bad_check.err"; then
  echo "ok golden-bad-rulediff-substantive REAL CLI: \`rule-diff\` itself exits 1,"
  echo "   naming substantive_change for 11.4.989, un-exempted"
else
  echo "NOT ok golden-bad-rulediff-substantive REAL CLI FAILED: got rc=$RD_BAD_RC,"
  echo "     check error: $(cat "$TMP/rd_bad_check.err" 2>/dev/null)"
  failx
fi

# --- I4 remediation, REAL CLI: the SAME substantive hunk, now exempted via a REFERENCED
#     operator decision record -- rc=0, and the hunk's own JSON entry names the reference used.
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V1" \
  --operator-decisions "11.4.989=DEC-T156-FIXTURE-CLI" \
  --out "$TMP/rd_exempt.json" >"$TMP/rd_exempt.out" 2>"$TMP/rd_exempt.err"
RD_EXEMPT_RC=$?
if [ "$RD_EXEMPT_RC" -eq 0 ] && python3 -c "
import json
with open('$TMP/rd_exempt.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [], doc['violations']
assert doc['hunks'][0]['exempted'] == 'DEC-T156-FIXTURE-CLI', doc['hunks']
" 2>"$TMP/rd_exempt_check.err"; then
  echo "ok I4 remediation REAL CLI: an --operator-decisions"
  echo "   11.4.989=DEC-T156-FIXTURE-CLI reference exempts the SAME substantive hunk"
  echo "   (rc=0) and the exempted hunk's own JSON entry names the decision reference"
  echo "   used, never merely implying exemption by omission"
else
  echo "NOT ok I4 remediation REAL CLI FAILED: got rc=$RD_EXEMPT_RC, check error:"
  echo "     $(cat "$TMP/rd_exempt_check.err" 2>/dev/null)"
  failx
fi

# --- I4 usage-error guard, REAL CLI: a BARE anchor number with no referenced decision record
#     MUST be refused (exit 2), never silently accepted as if it were a valid exemption.
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V1" \
  --operator-decisions "11.4.989" \
  --out "$TMP/rd_bare.json" >"$TMP/rd_bare.out" 2>"$TMP/rd_bare.err"
RD_BARE_RC=$?
if [ "$RD_BARE_RC" -eq 2 ]; then
  echo "ok I4 usage-error guard REAL CLI: a bare --operator-decisions anchor with no"
  echo "   referenced decision record is refused (rc=2), never silently accepted"
else
  echo "NOT ok I4 usage-error guard REAL CLI FAILED: expected rc=2 for a bare"
  echo "     anchor number, got rc=$RD_BARE_RC"
  failx
fi

# --- append-only extension: v2 -> v3, purely additive (nothing existing removed/reworded)
cat >>"$FAKECONST_R/Constitution.md" <<'EOF'

Extension (synthetic, real-CLI fixture): the gate additionally records the refusal reason.
EOF
( cd "$FAKECONST_R" && git add -A && git commit -q -m "v3: additive extension" ) >"$TMP/rd_commit_v3.log" 2>&1
V3=$(cd "$FAKECONST_R" && git rev-parse HEAD)

# --- negative-control-rulediff, REAL CLI: v2 -> v3 only appended, existing sentence untouched
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V2" \
  --out "$TMP/rd_add.json" >"$TMP/rd_add.out" 2>"$TMP/rd_add.err"
RD_ADD_RC=$?
if [ "$RD_ADD_RC" -eq 0 ] && python3 -c "
import json
with open('$TMP/rd_add.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [], doc['violations']
assert doc['hunks'][0]['classification'] == 'ADDITIVE', doc['hunks']
" 2>"$TMP/rd_add_check.err"; then
  echo "ok negative-control-rulediff REAL CLI: an additive anchor extension classifies"
  echo "   ADDITIVE and \`rule-diff\` itself reports rc=0"
else
  echo "NOT ok negative-control-rulediff REAL CLI FAILED: got rc=$RD_ADD_RC, check"
  echo "     error: $(cat "$TMP/rd_add_check.err" 2>/dev/null)"
  failx
fi

# --- false-positive guard (UNCHANGED), REAL CLI, isolated fixture: --base v3 against the
#     current (still v3) on-disk file is byte-identical -- deterministically rc=0, zero hunks.
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V3" \
  --out "$TMP/rd_noop.json" >"$TMP/rd_noop.out" 2>"$TMP/rd_noop.err"
RD_NOOP_RC=$?
if [ "$RD_NOOP_RC" -eq 0 ] && python3 -c "
import json
with open('$TMP/rd_noop.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['hunks'] == [], doc['hunks']
assert doc['violations'] == [], doc['violations']
" 2>"$TMP/rd_noop_check.err"; then
  echo "ok false-positive guard REAL CLI (isolated fixture): --base == current on-disk"
  echo "   file classifies zero hunks, rc=0"
else
  echo "NOT ok false-positive guard REAL CLI (isolated fixture) FAILED: got"
  echo "     rc=$RD_NOOP_RC, check error: $(cat "$TMP/rd_noop_check.err" 2>/dev/null)"
  failx
fi

# --- v3 -> v4: anchor 989 REMOVED entirely (replaced by an unrelated anchor 990)
cat >"$FAKECONST_R/Constitution.md" <<'EOF'
### §11.4.990 -- T156 real-CLI fixture anchor after removal (synthetic, unrelated)

Nothing relevant to anchor 989 lives here any more.
EOF
( cd "$FAKECONST_R" && git add -A && git commit -q -m "v4: anchor 989 removed" ) >"$TMP/rd_commit_v4.log" 2>&1
V4=$(cd "$FAKECONST_R" && git rev-parse HEAD)

# --- golden-bad-anchor-removed (B2), REAL CLI: v3 -> v4 deleted the WHOLE anchor
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V3" \
  --out "$TMP/rd_removed.json" >"$TMP/rd_removed.out" 2>"$TMP/rd_removed.err"
RD_REMOVED_RC=$?
if [ "$RD_REMOVED_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/rd_removed.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'anchor_removed', 'anchor': '11.4.989'}], doc['violations']
assert doc['removed_anchors'] == [{'anchor': '11.4.989', 'exempted': None}], doc['removed_anchors']
assert doc['new_anchors'] == ['11.4.990'], doc['new_anchors']
" 2>"$TMP/rd_removed_check.err"; then
  echo "ok golden-bad-anchor-removed REAL CLI (B2, review round 1): \`rule-diff\`"
  echo "   itself exits 1 naming anchor_removed for 11.4.989, un-exempted, and reports"
  echo "   11.4.990 as a new anchor informationally"
else
  echo "NOT ok golden-bad-anchor-removed REAL CLI FAILED: got rc=$RD_REMOVED_RC,"
  echo "     check error: $(cat "$TMP/rd_removed_check.err" 2>/dev/null)"
  failx
fi

# --- B2 exemption, REAL CLI: the SAME removed anchor, now exempted via a referenced decision
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R" --base "$V3" \
  --operator-decisions "11.4.989=DEC-T156-REMOVAL-CLI" \
  --out "$TMP/rd_removed_exempt.json" >"$TMP/rd_removed_exempt.out" 2>"$TMP/rd_removed_exempt.err"
RD_REMOVED_EXEMPT_RC=$?
if [ "$RD_REMOVED_EXEMPT_RC" -eq 0 ] && python3 -c "
import json
with open('$TMP/rd_removed_exempt.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [], doc['violations']
assert doc['removed_anchors'] == [{'anchor': '11.4.989', 'exempted': 'DEC-T156-REMOVAL-CLI'}], doc['removed_anchors']
" 2>"$TMP/rd_removed_exempt_check.err"; then
  echo "ok B2 exemption REAL CLI: an --operator-decisions reference exempts a removed"
  echo "   anchor exactly like a SUBSTANTIVE hunk (rc=0), the removed_anchors entry"
  echo "   naming the decision reference used"
else
  echo "NOT ok B2 exemption REAL CLI FAILED: got rc=$RD_REMOVED_EXEMPT_RC, check"
  echo "     error: $(cat "$TMP/rd_removed_exempt_check.err" 2>/dev/null)"
  failx
fi

# --- mutation-catching proof (rule-diff): a throwaway MUTATED COPY forcing cmd_rule_diff's own
#     exit-code computation to 0 unconditionally is proven to WRONGLY pass the golden-bad-
#     rulediff-substantive fixture the real tool correctly failed.
# Same sibling-`lib/`-preserving layout as the landing mutation above (a bare copy in $TMP would
# break the tool's own `sys.path` wiring to `../lib/fc_common.py`).
MUT_RULEDIFF_ROOT="$TMP/mut_rulediff_root"
mkdir -p "$MUT_RULEDIFF_ROOT/verify"
ln -s "$FC/lib" "$MUT_RULEDIFF_ROOT/lib"
MUT_RULEDIFF="$MUT_RULEDIFF_ROOT/verify/plan_struct_check.py"
cp "$TOOL" "$MUT_RULEDIFF"
python3 - "$MUT_RULEDIFF" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    lines = fh.readlines()
start = end = None
for i, line in enumerate(lines):
    if line.startswith("def cmd_rule_diff("):
        start = i
    elif start is not None and line.startswith("def ") and i > start:
        end = i
        break
if start is None:
    print("CMD-RULE-DIFF-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
if end is None:
    end = len(lines)
target_idx = None
for i in range(start, end):
    if lines[i].strip() == "rc = 1 if violations else 0":
        target_idx = i
        break
if target_idx is None:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
lines[target_idx] = "    rc = 0  # I1 MUTATION (throwaway copy): force-pass regardless of violations\n"
with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(lines)
PY
MUT_R_PREP_RC=$?
if [ "$MUT_R_PREP_RC" -ne 0 ]; then
  echo "NOT ok could not prepare the rule-diff mutation fixture (cmd_rule_diff's own"
  echo "     exit-code computation text has changed shape -- update this mutation"
  echo "     test's anchor text to match)"
  failx
else
  python3 "$MUT_RULEDIFF" rule-diff --constitution "$FAKECONST_R" --base "$V1" \
    --out "$TMP/rd_mut.json" >"$TMP/rd_mut.out" 2>"$TMP/rd_mut.err"
  RD_MUT_RC=$?
  if [ "$RD_MUT_RC" -eq 0 ]; then
    echo "ok mutation-catching proof (rule-diff): a throwaway mutated copy that forces"
    echo "   rc=0 unconditionally WRONGLY passes the SAME golden-bad-rulediff-substantive"
    echo "   fixture the real tool (rc=$RD_BAD_RC) correctly failed -- proving the"
    echo "   real-CLI assertion above is exactly what would catch this regression (I1)"
  else
    echo "NOT ok mutation-catching proof (rule-diff) FAILED: expected the mutated copy"
    echo "     to wrongly report rc=0, got rc=$RD_MUT_RC -- the mutation did not take"
    echo "     effect as designed"
    failx
  fi
fi

# ---------------------------------------------------------------------------
# REVIEW-ROUND-3 REMEDIATION (independent §11.4.209 Opus-xhigh review round 2 of T159): two
# BLOCKING findings (NB1 dotted-anchor collision; NB2 §12/Appendix-absorbing block boundary) plus
# two IMPORTANT findings (NI1 undisclosed §1-§10/preamble/§12+ blindness; NI2 paragraph-level
# reflow/mid-sentence-insertion classification) plus one MINOR (m1 self-contradictory em-dash
# comment). Per this task's own TDD instruction, the PRE-round-3 defect behind NB1 and NB2 was
# first reproduced and CONFIRMED against a byte-for-byte extraction of the pre-round-3 code
# (Producer != Verifier, constitution 11.4.240 -- run in a scratch verification script, never
# committed) BEFORE the fix landed; sections below re-exercise the SAME repro cases through the
# REAL, now-fixed `plan_struct_check.py` CLI, each with its own throwaway-mutated-copy
# catch-proof (never the tracked file) demonstrating these exact assertions are what would catch
# a regression back to the pre-round-3 behaviour.
# ---------------------------------------------------------------------------

echo
echo "=== REVIEW ROUND 3: NB1 (dotted anchor §11.4.N.X keyed distinct from its own parent) ==="

FAKECONST_NB1="$TMP/fakeconst_nb1"
mkdir -p "$FAKECONST_NB1"
( cd "$FAKECONST_NB1" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" ) >"$TMP/fakeconst_nb1_git_init.log" 2>&1
FAKECONST_NB1_INIT_RC=$?
if [ "$FAKECONST_NB1_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated NB1 fixture tree -- see"
  echo "     $TMP/fakeconst_nb1_git_init.log"
  failx
fi

cat >"$FAKECONST_NB1/Constitution.md" <<'EOF'
### §11.4.991 -- NB1 real-CLI fixture parent anchor (never a real anchor; synthetic)

The parent gate MUST hold.

### §11.4.991.A -- NB1 real-CLI fixture DOTTED child anchor (never a real anchor; synthetic)

The child gate MUST refuse a claim whose only support is an uncited signal.
EOF
( cd "$FAKECONST_NB1" && git add -A && git commit -q -m "v1: base (parent + dotted child)" ) \
  >"$TMP/nb1_commit_v1.log" 2>&1
NB1_V1=$(cd "$FAKECONST_NB1" && git rev-parse HEAD)

sed -i 's/MUST refuse/MAY refuse/' "$FAKECONST_NB1/Constitution.md"
( cd "$FAKECONST_NB1" && git add -A && git commit -q -m "v2: dotted child reworded" ) \
  >"$TMP/nb1_commit_v2.log" 2>&1

# --- golden-bad-NB1-reword, REAL CLI: rewording ONLY the dotted child must be detected, keyed
#     distinctly from its own untouched parent -- reproduced BROKEN pre-fix (verified separately,
#     never committed): the pre-round-3 regex keyed both "991" and "991.A" under the SAME bare
#     number "991", silently absorbing the child's own heading into its parent's occurrence list.
python3 "$TOOL" rule-diff --constitution "$FAKECONST_NB1" --base "$NB1_V1" \
  --out "$TMP/nb1_reword.json" >"$TMP/nb1_reword.out" 2>"$TMP/nb1_reword.err"
NB1_REWORD_RC=$?
if [ "$NB1_REWORD_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/nb1_reword.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'substantive_change', 'anchor': '11.4.991.A'}], doc['violations']
assert doc['hunks'] == [{'anchor': '11.4.991.A', 'classification': 'SUBSTANTIVE', 'exempted': None}], doc['hunks']
" 2>"$TMP/nb1_reword_check.err"; then
  echo "ok golden-bad-NB1-reword REAL CLI: rewording a genuine DOTTED sub-anchor"
  echo "   (11.4.991.A) is detected as substantive_change, correctly keyed distinctly from"
  echo "   its own untouched parent 11.4.991 (which reports no violation at all)"
else
  echo "NOT ok golden-bad-NB1-reword REAL CLI FAILED: got rc=$NB1_REWORD_RC, check error:"
  echo "     $(cat "$TMP/nb1_reword_check.err" 2>/dev/null)"
  failx
fi

# --- mutation-catching proof (NB1a, dotted capture): a throwaway copy of the tool with
#     `_ANCHOR_NUM_FRAGMENT` reverted to the pre-round-3 bare-digit-only form is proven to
#     MISATTRIBUTE the SAME reword to the WRONG anchor (its parent "11.4.991", not the actual
#     "11.4.991.A") -- confirmed empirically (never assumed, constitution 11.4.6) that this
#     specific mutation, layered UNDER this task's OTHER fix (compare every occurrence, NB1b
#     below), still detects a change occurred but reports it against the wrong anchor, which is
#     itself the exact operator-facing defect this remediation exists to close.
MUT_NB1A_ROOT="$TMP/mut_nb1a_root"
mkdir -p "$MUT_NB1A_ROOT/verify"
ln -s "$FC/lib" "$MUT_NB1A_ROOT/lib"
MUT_NB1A="$MUT_NB1A_ROOT/verify/plan_struct_check.py"
cp "$TOOL" "$MUT_NB1A"
python3 - "$MUT_NB1A" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
needle = '_ANCHOR_NUM_FRAGMENT = r"[0-9]+[A-Za-z]*(?:\\.[A-Za-z0-9]+)*"'  # fix round 4 (M-R4-2): letter-suffix admitted
if needle not in src:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
mutated = src.replace(
    needle,
    '_ANCHOR_NUM_FRAGMENT = r"[0-9]+"  # NB1a MUTATION (throwaway copy): revert to pre-round-3 bare-digit-only capture',
    1,
)
if mutated == src:
    print("MUTATION-DID-NOT-CHANGE-FILE", file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(mutated)
PY
MUT_NB1A_PREP_RC=$?
if [ "$MUT_NB1A_PREP_RC" -ne 0 ]; then
  echo "NOT ok could not prepare the NB1a mutation fixture (the _ANCHOR_NUM_FRAGMENT literal"
  echo "     has changed shape -- update this mutation test's anchor text to match)"
  failx
else
  python3 "$MUT_NB1A" rule-diff --constitution "$FAKECONST_NB1" --base "$NB1_V1" \
    --out "$TMP/nb1a_mut.json" >"$TMP/nb1a_mut.out" 2>"$TMP/nb1a_mut.err"
  MUT_NB1A_RC=$?
  if [ "$MUT_NB1A_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/nb1a_mut.json', encoding='utf-8') as fh:
    doc = json.load(fh)
codes = [(v['code'], v['anchor']) for v in doc['violations']]
assert ('substantive_change', '11.4.991.A') not in codes, doc['violations']
assert any(c == 'substantive_change' and a == '11.4.991' for c, a in codes), doc['violations']
" 2>"$TMP/nb1a_mut_check.err"; then
    echo "ok mutation-catching proof (NB1a, dotted capture): the throwaway copy with the"
    echo "   pre-round-3 bare-digit capture reports the SAME reword against the WRONG anchor"
    echo "   (11.4.991, its parent) instead of the real anchor (11.4.991.A) the fixed tool"
    echo "   (rc=$NB1_REWORD_RC above) correctly named -- proving the golden-bad-NB1-reword"
    echo "   assertion above is exactly what would catch this misattribution regression"
  else
    echo "NOT ok mutation-catching proof (NB1a) FAILED: expected the mutated copy to"
    echo "     misattribute the reword to anchor 11.4.991, got rc=$MUT_NB1A_RC, check error:"
    echo "     $(cat "$TMP/nb1a_mut_check.err" 2>/dev/null)"
    failx
  fi
fi

# --- golden-bad-NB1-delete, REAL CLI: the SAME dotted child anchor deleted outright -- must be a
#     real, reported anchor_removed for 11.4.991.A specifically, its untouched parent 11.4.991
#     reporting no violation at all.
cat >"$FAKECONST_NB1/Constitution.md" <<'EOF'
### §11.4.991 -- NB1 real-CLI fixture parent anchor (never a real anchor; synthetic)

The parent gate MUST hold.
EOF
( cd "$FAKECONST_NB1" && git add -A && git commit -q -m "v3: dotted child deleted" ) \
  >"$TMP/nb1_commit_v3.log" 2>&1
NB1_V2=$(cd "$FAKECONST_NB1" && git log --format=%H | sed -n '2p')

python3 "$TOOL" rule-diff --constitution "$FAKECONST_NB1" --base "$NB1_V2" \
  --out "$TMP/nb1_delete.json" >"$TMP/nb1_delete.out" 2>"$TMP/nb1_delete.err"
NB1_DELETE_RC=$?
if [ "$NB1_DELETE_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/nb1_delete.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'anchor_removed', 'anchor': '11.4.991.A'}], doc['violations']
assert doc['removed_anchors'] == [{'anchor': '11.4.991.A', 'exempted': None}], doc['removed_anchors']
" 2>"$TMP/nb1_delete_check.err"; then
  echo "ok golden-bad-NB1-delete REAL CLI: deleting a genuine DOTTED sub-anchor (11.4.991.A)"
  echo "   outright is detected as anchor_removed, keyed distinctly from its own untouched"
  echo "   parent 11.4.991"
else
  echo "NOT ok golden-bad-NB1-delete REAL CLI FAILED: got rc=$NB1_DELETE_RC, check error:"
  echo "     $(cat "$TMP/nb1_delete_check.err" 2>/dev/null)"
  failx
fi

echo
echo "=== REVIEW ROUND 3: NB1b (rule-diff compares EVERY occurrence of a shared anchor key) ==="

FAKECONST_NB1B="$TMP/fakeconst_nb1b"
mkdir -p "$FAKECONST_NB1B"
( cd "$FAKECONST_NB1B" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" ) >"$TMP/fakeconst_nb1b_git_init.log" 2>&1
FAKECONST_NB1B_INIT_RC=$?
if [ "$FAKECONST_NB1B_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated NB1b fixture tree -- see"
  echo "     $TMP/fakeconst_nb1b_git_init.log"
  failx
fi

cat >"$FAKECONST_NB1B/Constitution.md" <<'EOF'
### §11.4.992 -- NB1b real-CLI fixture FIRST occurrence (never a real anchor; synthetic)

The first gate MUST hold.

### §11.4.992 -- NB1b real-CLI fixture SECOND occurrence (genuine duplicate; synthetic)

The second gate MUST refuse a claim whose only support is an uncited signal.
EOF
( cd "$FAKECONST_NB1B" && git add -A && git commit -q -m "v1: two genuine occurrences of the SAME anchor number" ) \
  >"$TMP/nb1b_commit_v1.log" 2>&1
NB1B_V1=$(cd "$FAKECONST_NB1B" && git rev-parse HEAD)

sed -i 's/MUST refuse/MAY refuse/' "$FAKECONST_NB1B/Constitution.md"
( cd "$FAKECONST_NB1B" && git add -A && git commit -q -m "v2: SECOND occurrence reworded" ) \
  >"$TMP/nb1b_commit_v2.log" 2>&1

# --- golden-bad-NB1b, REAL CLI: a reword landing ONLY on the SECOND genuine occurrence of a
#     duplicated anchor number must still be detected -- the pre-round-3 code compared ONLY
#     `occ[0]` of each shared key, making a change to any LATER occurrence invisible.
python3 "$TOOL" rule-diff --constitution "$FAKECONST_NB1B" --base "$NB1B_V1" \
  --out "$TMP/nb1b_reword.json" >"$TMP/nb1b_reword.out" 2>"$TMP/nb1b_reword.err"
NB1B_REWORD_RC=$?
if [ "$NB1B_REWORD_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/nb1b_reword.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'substantive_change', 'anchor': '11.4.992', 'occurrence': 1}], doc['violations']
" 2>"$TMP/nb1b_reword_check.err"; then
  echo "ok golden-bad-NB1b REAL CLI: a reword landing ONLY on the SECOND genuine occurrence"
  echo "   of duplicated anchor 11.4.992 is detected (occurrence=1), never silently missed"
else
  echo "NOT ok golden-bad-NB1b REAL CLI FAILED: got rc=$NB1B_REWORD_RC, check error:"
  echo "     $(cat "$TMP/nb1b_reword_check.err" 2>/dev/null)"
  failx
fi

# --- mutation-catching proof (NB1b, every-occurrence comparison): a throwaway copy reverted to
#     comparing ONLY occ[0] of each shared key is proven to WRONGLY report a clean rc=0 for the
#     SAME reword the golden-bad-NB1b assertion above correctly caught.
MUT_NB1B_ROOT="$TMP/mut_nb1b_root"
mkdir -p "$MUT_NB1B_ROOT/verify"
ln -s "$FC/lib" "$MUT_NB1B_ROOT/lib"
MUT_NB1B="$MUT_NB1B_ROOT/verify/plan_struct_check.py"
cp "$TOOL" "$MUT_NB1B"
python3 - "$MUT_NB1B" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
needle = "        b_list = before_blocks[n]\n        a_list = after_blocks[n]\n"
if needle not in src:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
mutated = src.replace(
    needle,
    "        b_list = before_blocks[n][:1]  # NB1b MUTATION (throwaway copy): revert to occ[0]-only\n"
    "        a_list = after_blocks[n][:1]  # NB1b MUTATION (throwaway copy): revert to occ[0]-only\n",
    1,
)
if mutated == src:
    print("MUTATION-DID-NOT-CHANGE-FILE", file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(mutated)
PY
MUT_NB1B_PREP_RC=$?
if [ "$MUT_NB1B_PREP_RC" -ne 0 ]; then
  echo "NOT ok could not prepare the NB1b mutation fixture (the b_list/a_list assignment"
  echo "     literal has changed shape -- update this mutation test's anchor text to match)"
  failx
else
  python3 "$MUT_NB1B" rule-diff --constitution "$FAKECONST_NB1B" --base "$NB1B_V1" \
    --out "$TMP/nb1b_mut.json" >"$TMP/nb1b_mut.out" 2>"$TMP/nb1b_mut.err"
  MUT_NB1B_RC=$?
  if [ "$MUT_NB1B_RC" -eq 0 ]; then
    echo "ok mutation-catching proof (NB1b, every-occurrence comparison): a throwaway copy"
    echo "   comparing only occ[0] of each shared key WRONGLY reports a clean rc=0 for the"
    echo "   SAME reword-to-the-second-occurrence the real tool (rc=$NB1B_REWORD_RC above)"
    echo "   correctly caught -- proving the golden-bad-NB1b assertion above is exactly what"
    echo "   would catch this regression"
  else
    echo "NOT ok mutation-catching proof (NB1b) FAILED: expected the mutated copy to wrongly"
    echo "     report rc=0, got rc=$MUT_NB1B_RC -- the mutation did not take effect as designed"
    failx
  fi
fi

echo
echo "=== REVIEW ROUND 3: NB2 (a block ends at any top-level '## ' or non-anchor '### §' heading, never only the next §11.4.N anchor) ==="

# --- golden-bad-NB2, REAL CLI, REAL DATA (read-only -- nothing written under the tracked
#     constitution/ checkout): §11.4.170 is the LAST §11.4.N anchor before the real corpus's own
#     "## §12. Host-session safety ..." section begins -- pre-round-3, its own block absorbed the
#     ENTIRE §12 section PLUS both Appendices (confirmed separately, never committed, via a
#     byte-for-byte extraction of the pre-round-3 boundary logic), silently misattributing 4 of
#     its own 6 `gate_unimplemented` violations to gates that actually belong to §12
#     (CM-COVENANT-12-11-PROPAGATION, CM-COVENANT-12-12-PROPAGATION, CM-MAXRES-DYNAMIC-BUILD,
#     CM-NPROC-HEADROOM-CHECK). The fixed tool must report ONLY §11.4.170's own two real gates.
python3 "$TOOL" landing --constitution "$ROOT/constitution/" --anchors 11.4.170 \
  --out "$TMP/nb2_landing.json" >"$TMP/nb2_landing.out" 2>"$TMP/nb2_landing.err"
NB2_LANDING_RC=$?
if python3 -c "
import json
with open('$TMP/nb2_landing.json', encoding='utf-8') as fh:
    doc = json.load(fh)
gates = sorted(g['gate'] for g in doc['anchors'][0]['gates'])
leaked_s12_gates = {'CM-COVENANT-12-11-PROPAGATION', 'CM-COVENANT-12-12-PROPAGATION',
                     'CM-MAXRES-DYNAMIC-BUILD', 'CM-NPROC-HEADROOM-CHECK'}
assert not (leaked_s12_gates & set(gates)), gates
assert 'CM-COVENANT-114-170-PROPAGATION' in gates, gates
" 2>"$TMP/nb2_landing_check.err"; then
  echo "ok golden-bad-NB2 REAL CLI (real corpus data, read-only): anchor §11.4.170's own"
  echo "   extracted block no longer absorbs any of §12's own gates -- its own reported"
  echo "   gate set names ONLY anchors genuinely belonging to §11.4.170 itself"
else
  echo "NOT ok golden-bad-NB2 REAL CLI FAILED: anchor 11.4.170's own reported gate set still"
  echo "     leaks a gate belonging to a different, unrelated numbered section -- check error:"
  echo "     $(cat "$TMP/nb2_landing_check.err" 2>/dev/null)"
  failx
fi

# --- mutation-catching proof (NB2): a throwaway copy reverted to stopping a block ONLY at the
#     next §11.4.N anchor (dropping the top-level-'## '/non-anchor-'### §' boundary entirely) is
#     proven to WRONGLY re-absorb §12's own gates into anchor 170's own block, against the SAME
#     real, read-only corpus data.
MUT_NB2_ROOT="$TMP/mut_nb2_root"
mkdir -p "$MUT_NB2_ROOT/verify"
ln -s "$FC/lib" "$MUT_NB2_ROOT/lib"
MUT_NB2="$MUT_NB2_ROOT/verify/plan_struct_check.py"
cp "$TOOL" "$MUT_NB2"
python3 - "$MUT_NB2" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
needle = (
    '        if _TOP_LEVEL_SECTION_RE.match(line) or (\n'
    '                _H3_SECTION_ANY_RE.match(line) and not _ANCHOR_BLOCK_START_RE.match(line)):\n'
    '            boundaries.append(i)\n'
)
if needle not in src:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
mutated = src.replace(
    needle,
    '        pass  # NB2 MUTATION (throwaway copy): revert -- never add a section-heading boundary\n',
    1,
)
if mutated == src:
    print("MUTATION-DID-NOT-CHANGE-FILE", file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(mutated)
PY
MUT_NB2_PREP_RC=$?
if [ "$MUT_NB2_PREP_RC" -ne 0 ]; then
  echo "NOT ok could not prepare the NB2 mutation fixture (the boundary-collection literal has"
  echo "     changed shape -- update this mutation test's anchor text to match)"
  failx
else
  python3 "$MUT_NB2" landing --constitution "$ROOT/constitution/" --anchors 11.4.170 \
    --out "$TMP/nb2_mut.json" >"$TMP/nb2_mut.out" 2>"$TMP/nb2_mut.err"
  MUT_NB2_RC=$?
  MUT_NB2_ERR=$(cat "$TMP/nb2_mut.err" 2>/dev/null)
  # NOTE: self_check_landing() (run BEFORE --constitution is ever read) itself now embeds the
  # SAME NB2 needle fixture (anchors 902/903), so this specific mutation is caught even EARLIER
  # than reaching the real corpus -- the self-check's own exit 3, never a clean rc=0 nor a
  # leaked-gate --out JSON, is the observed catch (defense-in-depth: the control needle fires
  # before real data is ever touched, exactly as constitution 11.4.201/11.4.273 intends).
  case "$MUT_NB2_ERR" in
    *"self-check FAILED (NB2, review round 3)"*) MUT_NB2_CAUGHT=1 ;;
    *) MUT_NB2_CAUGHT=0 ;;
  esac
  if [ "$MUT_NB2_RC" -eq 3 ] && [ "$MUT_NB2_CAUGHT" -eq 1 ] && [ ! -s "$TMP/nb2_mut.json" ]; then
    echo "ok mutation-catching proof (NB2): the throwaway copy reverted to stopping a block"
    echo "   ONLY at the next §11.4.N anchor is caught by self_check_landing()'s OWN NB2"
    echo "   needle fixture (rc=3, no --out JSON written) BEFORE even reaching the real"
    echo "   corpus -- an even earlier catch than the golden-bad-NB2 real-data assertion"
    echo "   above, proving this regression class cannot pass silently either way"
  else
    echo "NOT ok mutation-catching proof (NB2) FAILED: expected the mutated copy to fail"
    echo "     self_check_landing()'s own NB2 needle (rc=3, no --out written), got"
    echo "     rc=$MUT_NB2_RC, stderr: $MUT_NB2_ERR"
    failx
  fi
fi

echo
echo "=== REVIEW ROUND 3: NI2 (paragraph-level reflow vs. a real mid-sentence content change) ==="

FAKECONST_NI2="$TMP/fakeconst_ni2"
mkdir -p "$FAKECONST_NI2"
( cd "$FAKECONST_NI2" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" ) >"$TMP/fakeconst_ni2_git_init.log" 2>&1
FAKECONST_NI2_INIT_RC=$?
if [ "$FAKECONST_NI2_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated NI2 fixture tree -- see"
  echo "     $TMP/fakeconst_ni2_git_init.log"
  failx
fi

cat >"$FAKECONST_NI2/Constitution.md" <<'EOF'
### §11.4.993 -- NI2 real-CLI fixture anchor (never a real anchor; synthetic)

The system MUST always validate every input
before it is processed by any downstream consumer.
EOF
( cd "$FAKECONST_NI2" && git add -A && git commit -q -m "v1: base" ) >"$TMP/ni2_commit_v1.log" 2>&1
NI2_V1=$(cd "$FAKECONST_NI2" && git rev-parse HEAD)

# --- golden-bad-NI2-insert, REAL CLI: a bare "NOT" line inserted BETWEEN the two existing lines
#     of the hard-wrapped sentence, inverting its meaning -- must be SUBSTANTIVE, never the
#     false-negative ADDITIVE the pre-round-3 line-only classifier produced (confirmed separately,
#     never committed, via a byte-for-byte extraction of the pre-round-3 classify_diff()).
cat >"$FAKECONST_NI2/Constitution.md" <<'EOF'
### §11.4.993 -- NI2 real-CLI fixture anchor (never a real anchor; synthetic)

The system MUST always validate every input
NOT
before it is processed by any downstream consumer.
EOF
python3 "$TOOL" rule-diff --constitution "$FAKECONST_NI2" --base "$NI2_V1" \
  --out "$TMP/ni2_insert.json" >"$TMP/ni2_insert.out" 2>"$TMP/ni2_insert.err"
NI2_INSERT_RC=$?
if [ "$NI2_INSERT_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/ni2_insert.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['hunks'][0]['classification'] == 'SUBSTANTIVE', doc['hunks']
assert doc['violations'] == [{'code': 'substantive_change', 'anchor': '11.4.993'}], doc['violations']
" 2>"$TMP/ni2_insert_check.err"; then
  echo "ok golden-bad-NI2-insert REAL CLI: a mid-sentence 'NOT' line inserted between two"
  echo "   existing hard-wrapped lines (inverting the sentence's meaning) classifies"
  echo "   SUBSTANTIVE -- never the false-negative ADDITIVE a purely line-level classifier"
  echo "   would report"
else
  echo "NOT ok golden-bad-NI2-insert REAL CLI FAILED: got rc=$NI2_INSERT_RC, check error:"
  echo "     $(cat "$TMP/ni2_insert_check.err" 2>/dev/null)"
  failx
fi

# --- negative-control-NI2-rewrap, REAL CLI: the SAME base paragraph purely re-wrapped (identical
#     words, a different line-break point, nothing else changed) must classify STRUCTURAL --
#     never the false-positive SUBSTANTIVE the pre-round-3 line-only classifier produced.
cat >"$FAKECONST_NI2/Constitution.md" <<'EOF'
### §11.4.993 -- NI2 real-CLI fixture anchor (never a real anchor; synthetic)

The system MUST always validate every input before it is
processed by any downstream consumer.
EOF
python3 "$TOOL" rule-diff --constitution "$FAKECONST_NI2" --base "$NI2_V1" \
  --out "$TMP/ni2_rewrap.json" >"$TMP/ni2_rewrap.out" 2>"$TMP/ni2_rewrap.err"
NI2_REWRAP_RC=$?
if [ "$NI2_REWRAP_RC" -eq 0 ] && python3 -c "
import json
with open('$TMP/ni2_rewrap.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['hunks'] == [{'anchor': '11.4.993', 'classification': 'STRUCTURAL', 'exempted': None}], doc['hunks']
assert doc['violations'] == [], doc['violations']
" 2>"$TMP/ni2_rewrap_check.err"; then
  echo "ok negative-control-NI2-rewrap REAL CLI: purely re-wrapping an unchanged paragraph"
  echo "   (identical words, different line-break point) classifies STRUCTURAL (reported as"
  echo "   a hunk, but NEVER a violation, rc=0) -- never the false-positive SUBSTANTIVE a"
  echo "   purely line-level classifier would report"
else
  echo "NOT ok negative-control-NI2-rewrap REAL CLI FAILED: got rc=$NI2_REWRAP_RC, check error:"
  echo "     $(cat "$TMP/ni2_rewrap_check.err" 2>/dev/null)"
  failx
fi

# --- mutation-catching proof (NI2): a throwaway copy of the classifier reverted to raw-line
#     granularity (fix round 4: every hard-wrapped RAW line its own logical unit, continuation
#     lines no longer joined) is proven to WRONGLY invert the results above -- caught by the
#     self-check's own NI2 needle before --base is read.
MUT_NI2_ROOT="$TMP/mut_ni2_root"
mkdir -p "$MUT_NI2_ROOT/verify"
ln -s "$FC/lib" "$MUT_NI2_ROOT/lib"
MUT_NI2="$MUT_NI2_ROOT/verify/plan_struct_check.py"
cp "$TOOL" "$MUT_NI2"
python3 - "$MUT_NI2" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()
# FIX ROUND 4: classify_diff() is now the logical-unit design; the NI2-equivalent regression is
# "every RAW hard-wrapped line is its own unit" (continuation lines no longer joined), which
# re-creates BOTH NI2 defects (mid-sentence NOT insert => a clean unit insert, ADDITIVE; a pure
# rewrap => changed units, not STRUCTURAL).
needle = (
    "            open_unit[3] = open_unit[3] + \" \" + stripped  # hard-wrapped continuation line\n"
    "            continue\n"
)
if needle not in src:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr)
    sys.exit(1)
mutated = src.replace(
    needle,
    "            pass  # NI2 MUTATION (throwaway copy): revert to raw-line units, no continuation join\n",
    1,
)
if mutated == src:
    print("MUTATION-DID-NOT-CHANGE-FILE", file=sys.stderr)
    sys.exit(1)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(mutated)
PY
MUT_NI2_PREP_RC=$?
if [ "$MUT_NI2_PREP_RC" -ne 0 ]; then
  echo "NOT ok could not prepare the NI2 mutation fixture (classify_diff()'s own paragraph-tier"
  echo "     literal has changed shape -- update this mutation test's anchor text to match)"
  failx
else
  python3 "$MUT_NI2" rule-diff --constitution "$FAKECONST_NI2" --base "$NI2_V1" \
    --out "$TMP/ni2_mut_rewrap.json" >"$TMP/ni2_mut_rewrap.out" 2>"$TMP/ni2_mut_rewrap.err"
  MUT_NI2_REWRAP_RC=$?
  MUT_NI2_REWRAP_ERR=$(cat "$TMP/ni2_mut_rewrap.err" 2>/dev/null)
  # $FAKECONST_NI2/Constitution.md is currently the rewrap variant (last written above). NOTE:
  # self_check_rule_diff() (run BEFORE --base is ever read) itself now embeds the SAME two NI2
  # needles (mid-sentence insertion + pure rewrap), so reverting classify_diff()'s own
  # paragraph-level tier is caught even EARLIER, by the self-check's own rc=3 exit, before this
  # specific fixture's --base is ever diffed -- the SAME defense-in-depth catch pattern as NB2.
  case "$MUT_NI2_REWRAP_ERR" in
    *"self-check FAILED (NI2, review round 3)"*) MUT_NI2_CAUGHT=1 ;;
    *) MUT_NI2_CAUGHT=0 ;;
  esac
  if [ "$MUT_NI2_REWRAP_RC" -eq 3 ] && [ "$MUT_NI2_CAUGHT" -eq 1 ] && [ ! -s "$TMP/ni2_mut_rewrap.json" ]; then
    echo "ok mutation-catching proof (NI2): the throwaway copy reverted to a raw-line-only"
    echo "   difflib pass (skipping the paragraph tier entirely) is caught by"
    echo "   self_check_rule_diff()'s OWN NI2 needle fixture (rc=3, no --out JSON written)"
    echo "   BEFORE even diffing this section's own isolated fixture -- an even earlier catch"
    echo "   than the negative-control-NI2-rewrap real-data assertion above"
  else
    echo "NOT ok mutation-catching proof (NI2) FAILED: expected the mutated copy to fail"
    echo "     self_check_rule_diff()'s own NI2 needle (rc=3, no --out written), got"
    echo "     rc=$MUT_NI2_REWRAP_RC, stderr: $MUT_NI2_REWRAP_ERR"
    failx
  fi
fi

echo
echo "=== REVIEW ROUND 3: NI3 test-coverage gaps (c) -- CLI-level anchor_not_found / duplicate_block_in_corpus / propagation_gate_blind (exit 4) ==="

# --- (c-i) anchor_not_found, REAL CLI, real corpus data (read-only): a requested anchor that
#     genuinely does not exist in Constitution.md at all.
python3 "$TOOL" landing --constitution "$ROOT/constitution/" --anchors 11.4.999999999 \
  --out "$TMP/ni3_notfound.json" >"$TMP/ni3_notfound.out" 2>"$TMP/ni3_notfound.err"
NI3_NOTFOUND_RC=$?
if [ "$NI3_NOTFOUND_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/ni3_notfound.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'anchor_not_found', 'anchor': '11.4.999999999'}], doc['violations']
assert doc['anchors'] == [{'anchor': '11.4.999999999', 'found': False, 'gates': [], 'propagation': None}], doc['anchors']
" 2>"$TMP/ni3_notfound_check.err"; then
  echo "ok CLI-level anchor_not_found (NI3(c)): requesting a genuinely nonexistent anchor"
  echo "   against real corpus data reports anchor_not_found, rc=1, found=false"
else
  echo "NOT ok CLI-level anchor_not_found (NI3(c)) FAILED: got rc=$NI3_NOTFOUND_RC, check error:"
  echo "     $(cat "$TMP/ni3_notfound_check.err" 2>/dev/null)"
  failx
fi

# --- (c-ii) duplicate_block_in_corpus, REAL CLI, isolated fixture: the SAME anchor number
#     genuinely appears TWICE as an H3 block-start.
FAKECONST_NI3DUP="$TMP/fakeconst_ni3dup"
mkdir -p "$FAKECONST_NI3DUP/scripts/gates"
cp "$GATE_LEDGER" "$FAKECONST_NI3DUP/scripts/gates/gate_ledger.sh"
: >"$FAKECONST_NI3DUP/scripts/gates/gate_ledger_deferrals.tsv"
: >"$FAKECONST_NI3DUP/scripts/gates/covenant_propagation_anchors.tsv"
cat >"$FAKECONST_NI3DUP/Constitution.md" <<'EOF'
### §11.4.994 -- NI3(c) duplicate-block fixture, FIRST occurrence (never a real anchor; synthetic)

First gate `CM-SELFCHECK-NI3-DUP-1` MUST hold.

### §11.4.994 -- NI3(c) duplicate-block fixture, SECOND occurrence (genuine duplicate; synthetic)

Second gate `CM-SELFCHECK-NI3-DUP-2` MUST hold.
EOF
( cd "$FAKECONST_NI3DUP" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" && git add -A \
    && git commit -q -m "v1: duplicate block fixture" ) >"$TMP/ni3dup_git.log" 2>&1
NI3DUP_INIT_RC=$?
if [ "$NI3DUP_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated NI3(c) duplicate-block fixture tree -- see"
  echo "     $TMP/ni3dup_git.log"
  failx
fi
python3 "$TOOL" landing --constitution "$FAKECONST_NI3DUP" --anchors 994 \
  --out "$TMP/ni3_dup.json" >"$TMP/ni3_dup.out" 2>"$TMP/ni3_dup.err"
NI3_DUP_RC=$?
if [ "$NI3_DUP_RC" -eq 1 ] && python3 -c "
import json
with open('$TMP/ni3_dup.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert {'code': 'duplicate_block_in_corpus', 'anchor': '994', 'count': 2} in doc['violations'], doc['violations']
" 2>"$TMP/ni3_dup_check.err"; then
  echo "ok CLI-level duplicate_block_in_corpus (NI3(c)): a genuinely duplicated (non-dotted)"
  echo "   anchor number reports duplicate_block_in_corpus with count=2, via the REAL landing"
  echo "   CLI (distinct from this file's own NB1 anchor_occurrence_count_changed, which is a"
  echo "   rule-diff BEFORE-vs-AFTER concept, not landing's own single-snapshot concept)"
else
  echo "NOT ok CLI-level duplicate_block_in_corpus (NI3(c)) FAILED: got rc=$NI3_DUP_RC, check"
  echo "     error: $(cat "$TMP/ni3_dup_check.err" 2>/dev/null)"
  failx
fi

# --- (c-iii) propagation_gate_blind / overall exit 4, REAL CLI, isolated fixture: an anchor with
#     NO gate tokens named in its own body at all (so zero gate_unimplemented/gate_status_unknown
#     violations) but WITH a registered propagation wrapper that exits an UNUSUAL code (neither 0
#     PASS nor 1 FAIL) -- the ONLY violation for this anchor is then propagation_gate_blind, so
#     the OVERALL verdict must be honestly BLIND (exit 4), --out still written.
FAKECONST_NI3BLIND="$TMP/fakeconst_ni3blind"
mkdir -p "$FAKECONST_NI3BLIND/scripts/gates"
cp "$GATE_LEDGER" "$FAKECONST_NI3BLIND/scripts/gates/gate_ledger.sh"
: >"$FAKECONST_NI3BLIND/scripts/gates/gate_ledger_deferrals.tsv"
cat >"$FAKECONST_NI3BLIND/Constitution.md" <<'EOF'
### §11.4.995 -- NI3(c) propagation_gate_blind fixture (never a real anchor; synthetic; no gate
tokens named in this body at all).

### §11.4.996 -- NI3(c) fixture sibling anchor (synthetic; exists ONLY so gate_ledger.sh's own
corpus-wide scan finds at least one real CM- token somewhere, avoiding its OWN separate
"zero CM- tokens extracted from corpus" BLIND refusal -- anchor 995's own extracted block above
still names none, which is the actual condition this fixture tests).

Gate `CM-SELFCHECK-NI3-BLIND-SIBLING` MUST hold.
EOF
cat >"$FAKECONST_NI3BLIND/scripts/gates/cm_fake_995_propagation.sh" <<'EOF'
#!/usr/bin/env bash
# NI3(c) fixture wrapper -- exits an UNUSUAL code (neither 0 PASS nor 1 FAIL) regardless of args.
exit 77
EOF
printf 'CM-FAKE-995-PROPAGATION\t11.4.995\n' >"$FAKECONST_NI3BLIND/scripts/gates/covenant_propagation_anchors.tsv"
( cd "$FAKECONST_NI3BLIND" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" && git add -A \
    && git commit -q -m "v1: propagation_gate_blind fixture" ) >"$TMP/ni3blind_git.log" 2>&1
NI3BLIND_INIT_RC=$?
if [ "$NI3BLIND_INIT_RC" -ne 0 ]; then
  echo "NOT ok could not git-init the isolated NI3(c) propagation_gate_blind fixture tree --"
  echo "     see $TMP/ni3blind_git.log"
  failx
fi
python3 "$TOOL" landing --constitution "$FAKECONST_NI3BLIND" --anchors 11.4.995 \
  --out "$TMP/ni3_blind.json" >"$TMP/ni3_blind.out" 2>"$TMP/ni3_blind.err"
NI3_BLIND_RC=$?
if [ "$NI3_BLIND_RC" -eq 4 ] && [ -s "$TMP/ni3_blind.json" ] && python3 -c "
import json
with open('$TMP/ni3_blind.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert doc['violations'] == [{'code': 'propagation_gate_blind', 'anchor': '11.4.995', 'gate': 'CM-FAKE-995-PROPAGATION', 'rc': 77}], doc['violations']
" 2>"$TMP/ni3_blind_check.err"; then
  echo "ok CLI-level propagation_gate_blind / overall exit 4 (NI3(c)): an anchor whose ONLY"
  echo "   violation is a propagation wrapper exiting an unusual code reports the honest"
  echo "   BLIND verdict (rc=4), --out still written with BLIND: true (fc_common.cmd_emit's"
  echo "   own convention)"
else
  echo "NOT ok CLI-level propagation_gate_blind / overall exit 4 (NI3(c)) FAILED: got"
  echo "     rc=$NI3_BLIND_RC, check error: $(cat "$TMP/ni3_blind_check.err" 2>/dev/null)"
  failx
fi

echo
echo "=== FIX ROUND 4: I-R4-2 / I-R4-3 (logical-unit classifier) -- real CLI, isolated fixture ==="

# Every case below was run against the PRE-round-4 (review round 3, whole-paragraph-join)
# classifier FIRST and reproduced the reviewer's exact wrong verdicts (constitution 11.4.6): the
# three I-R4-2 cases returned STRUCTURAL (rc=0, a real structural edit silently passed) and the
# three I-R4-3 cases returned SUBSTANTIVE (rc=1, a legitimate pure append false-refused).
FAKECONST_R4="$TMP/fakeconst_r4"
mkdir -p "$FAKECONST_R4"
( cd "$FAKECONST_R4" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" ) >"$TMP/fakeconst_r4_git_init.log" 2>&1 \
  || { echo "NOT ok could not git-init the isolated fix-round-4 fixture tree"; failx; }

r4_base() {
  cat <<'EOF'
### §11.4.997 -- fix-round-4 real-CLI fixture anchor (never a real anchor; synthetic)

The gate MUST refuse a claim.

- (A) rule
  - exception applies ONLY in test
- MUST do X
- NOT Y

| a | b |
|---|---|
| 1 | 2 |

```yaml
parent:
  child: 1
```
EOF
}
r4_base >"$FAKECONST_R4/Constitution.md"
( cd "$FAKECONST_R4" && git add -A && git commit -q -m "v1: base" ) >"$TMP/r4_commit_v1.log" 2>&1
R4_V1=$(cd "$FAKECONST_R4" && git rev-parse HEAD)

R4_FAILS=0
# r4_case <name> <expected-classification> <expected-rc> <python-transform-of-base>
r4_case() {
  local name=$1 want_cls=$2 want_rc=$3 transform=$4
  r4_base | python3 -c "import sys; t=sys.stdin.read(); $transform; sys.stdout.write(t)" \
    >"$FAKECONST_R4/Constitution.md"
  if cmp -s <(r4_base) "$FAKECONST_R4/Constitution.md"; then
    echo "NOT ok fix-round-4 case $name: the transform did not change the fixture (test bug)"
    R4_FAILS=$((R4_FAILS + 1)); failx; return
  fi
  python3 "$TOOL" rule-diff --constitution "$FAKECONST_R4" --base "$R4_V1" \
    --out "$TMP/r4_$name.json" >"$TMP/r4_$name.out" 2>"$TMP/r4_$name.err"
  local rc=$?
  if [ "$rc" -eq "$want_rc" ] && python3 -c "
import json
with open('$TMP/r4_$name.json', encoding='utf-8') as fh:
    doc = json.load(fh)
assert [h['classification'] for h in doc['hunks']] == ['$want_cls'], doc['hunks']
" 2>"$TMP/r4_${name}_check.err"; then
    echo "ok fix-round-4 REAL CLI case $name: classified $want_cls, rc=$rc"
  else
    echo "NOT ok fix-round-4 REAL CLI case $name: expected $want_cls rc=$want_rc, got rc=$rc --"
    echo "     $(cat "$TMP/r4_${name}_check.err" "$TMP/r4_$name.err" 2>/dev/null | tail -3)"
    R4_FAILS=$((R4_FAILS + 1)); failx
  fi
}
# I-R4-2: real structural edits that ALSO involve whitespace -- must be SUBSTANTIVE (rc=1).
r4_case unnest     SUBSTANTIVE 1 "t=t.replace('  - exception applies', '- exception applies')"
r4_case yamldedent SUBSTANTIVE 1 "t=t.replace('  child: 1', 'child: 1')"
r4_case mergeitems SUBSTANTIVE 1 "t=t.replace('- MUST do X\n- NOT Y', '- MUST do X - NOT Y')"
# I-R4-3: pure appends inside an existing paragraph -- must be ADDITIVE (rc=0).
r4_case rowappend  ADDITIVE    0 "t=t.replace('| 1 | 2 |\n', '| 1 | 2 |\n| 3 | 4 |\n')"
r4_case itemappend ADDITIVE    0 "t=t.replace('- NOT Y\n', '- NOT Y\n- (C) must Z\n')"
r4_case sentappend ADDITIVE    0 "t=t.replace('refuse a claim.\n', 'refuse a claim.\nIt additionally logs the refusal.\n')"
# Cross-checks: NI2 (still guarded by its own fixture above) re-proven on THIS fixture's shapes,
# plus round 4's own confirmed-good combined rewrap+real-change case.
r4_case ni2insert  SUBSTANTIVE 1 "t=t.replace('The gate MUST refuse a claim.', 'The gate MUST\nNOT\nrefuse a claim.')"
r4_case ni2rewrap  STRUCTURAL  0 "t=t.replace('The gate MUST refuse a claim.', 'The gate MUST\nrefuse a claim.')"
r4_case rewrapchg  SUBSTANTIVE 1 "t=t.replace('The gate MUST refuse a claim.', 'The gate MAY\nrefuse a claim.')"
# Adversarial extras: a new top-level bullet inserted between a rule and its nested qualifier
# re-parents the qualifier (SUBSTANTIVE); a consistent 2->4-space re-indent of the nested
# qualifier keeps its depth (STRUCTURAL); new words continuing an UNFINISHED sentence are
# SUBSTANTIVE (they can qualify it) -- never ADDITIVE.
r4_case reparent   SUBSTANTIVE 1 "t=t.replace('- (A) rule\n', '- (A) rule\n- (B) new rule\n')"
r4_case reindent   STRUCTURAL  0 "t=t.replace('  - exception applies', '    - exception applies')"
r4_case unfinished SUBSTANTIVE 1 "t=t.replace('- MUST do X\n', '- MUST do X\n  unless it is a test.\n')"

# --- mutation-catching proofs (fix round 4): throwaway copies (never the tracked file) with
#     each fix reverted are caught by self_check_rule_diff()'s OWN new fix-round-4 needles
#     (rc=3, no --out written) -- i.e. BEFORE --base is ever read.
r4_mutation() {
  local label=$1 expect_msg=$2 py_needle=$3 py_repl=$4
  local root="$TMP/mut_r4_$label"
  mkdir -p "$root/verify"; ln -s "$FC/lib" "$root/lib"
  cp "$TOOL" "$root/verify/plan_struct_check.py"
  if ! python3 - "$root/verify/plan_struct_check.py" "$py_needle" "$py_repl" <<'PY'
import sys
path, needle, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, encoding="utf-8").read()
if src.count(needle) != 1:
    print("MUTATION-ANCHOR-NOT-FOUND-OR-AMBIGUOUS", file=sys.stderr); sys.exit(1)
open(path, "w", encoding="utf-8").write(src.replace(needle, repl, 1))
PY
  then
    echo "NOT ok could not prepare fix-round-4 mutation $label (anchor text changed shape)"
    failx; return 1
  fi
  r4_base >"$FAKECONST_R4/Constitution.md"
  python3 "$root/verify/plan_struct_check.py" rule-diff --constitution "$FAKECONST_R4" \
    --base "$R4_V1" --out "$TMP/r4_mut_$label.json" >/dev/null 2>"$TMP/r4_mut_$label.err"
  local rc=$?
  if [ "$rc" -eq 3 ] && grep -qF "$expect_msg" "$TMP/r4_mut_$label.err" \
      && [ ! -s "$TMP/r4_mut_$label.json" ]; then
    echo "ok mutation-catching proof ($label): reverting the fix is caught by the self-check"
    echo "   needle ('$expect_msg', rc=3, no --out written)"
    return 0
  fi
  echo "NOT ok mutation-catching proof ($label): expected rc=3 + '$expect_msg', got rc=$rc --"
  echo "     $(cat "$TMP/r4_mut_$label.err" 2>/dev/null | tail -2)"
  failx; return 1
}
# I-R4-2 regression: re-introduce round 3's whole-document word-stream STRUCTURAL shortcut.
r4_mutation IR42 "self-check FAILED (I-R4-2, fix round 4)" \
  '    if _unit_skeleton(a_units) == _unit_skeleton(b_units):
        return "STRUCTURAL"
' \
  '    if " ".join(before_text.split()) == " ".join(after_text.split()):  # I-R4-2 MUTATION
        return "STRUCTURAL"
'
MUT_R4_IR42_OK=$?
# I-R4-3 regression: a tail-append inside an existing unit no longer counts as additive.
r4_mutation IR43 "self-check FAILED (I-R4-3, fix round 4)" \
  '    if before_unit[0] != after_unit[0] or before_unit[0] not in ("prose", "li"):
        return False
' \
  '    return False  # I-R4-3 MUTATION
'
MUT_R4_IR43_OK=$?

echo
echo "=== FIX ROUND 4: I-R4-1 (an EXEMPTED occurrence-count change is still recorded) + M-R4-1 ==="
FAKECONST_R41="$TMP/fakeconst_r41"
mkdir -p "$FAKECONST_R41"
cat >"$FAKECONST_R41/Constitution.md" <<'EOF'
### §11.4.998 -- I-R4-1 fixture anchor (never a real anchor; synthetic)

The 998 rule MUST hold.
EOF
( cd "$FAKECONST_R41" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" && git add -A && git commit -q -m v1 ) \
  >"$TMP/r41_git.log" 2>&1
R41_V1=$(cd "$FAKECONST_R41" && git rev-parse HEAD)
cat >>"$FAKECONST_R41/Constitution.md" <<'EOF'

### §11.4.998 -- a SECOND block for the same anchor (substantive override; synthetic)

The 998 rule is now OPTIONAL.
EOF
# control: NOT exempted -> violation, and the count change is ALSO recorded with exempted=null.
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R41" --base "$R41_V1" \
  --out "$TMP/r41_plain.json" >/dev/null 2>"$TMP/r41_plain.err"
R41_PLAIN_RC=$?
if [ "$R41_PLAIN_RC" -eq 1 ] && python3 -c "
import json
doc = json.load(open('$TMP/r41_plain.json', encoding='utf-8'))
assert doc['violations'] == [{'code': 'anchor_occurrence_count_changed', 'anchor': '11.4.998', 'before_count': 1, 'after_count': 2}], doc['violations']
assert doc['occurrence_count_changes'] == [{'anchor': '11.4.998', 'before_count': 1, 'after_count': 2, 'removed_occurrences': [], 'added_occurrences': [1], 'exempted': None}], doc['occurrence_count_changes']
" 2>"$TMP/r41_plain_check.err"; then
  echo "ok I-R4-1 control REAL CLI: an unexempted occurrence-count change is a violation AND is"
  echo "   recorded in occurrence_count_changes with exempted=null"
else
  echo "NOT ok I-R4-1 control REAL CLI: rc=$R41_PLAIN_RC -- $(cat "$TMP/r41_plain_check.err" 2>/dev/null)"
  failx
fi
# golden-bad-I-R4-1 (the reviewer's exact repro): EXEMPTED -> rc=0 but the entry and its decision
# reference MUST be visible in --out (pre-round-4: DEC-Y appeared ZERO times in the output).
python3 "$TOOL" rule-diff --constitution "$FAKECONST_R41" --base "$R41_V1" \
  --operator-decisions "11.4.998=DEC-Y" --out "$TMP/r41_exempt.json" >/dev/null 2>"$TMP/r41_exempt.err"
R41_EXEMPT_RC=$?
if [ "$R41_EXEMPT_RC" -eq 0 ] && [ "$(grep -o 'DEC-Y' "$TMP/r41_exempt.json" | wc -l)" -ge 1 ] && python3 -c "
import json
doc = json.load(open('$TMP/r41_exempt.json', encoding='utf-8'))
assert doc['violations'] == [], doc['violations']
assert doc['occurrence_count_changes'] == [{'anchor': '11.4.998', 'before_count': 1, 'after_count': 2, 'removed_occurrences': [], 'added_occurrences': [1], 'exempted': 'DEC-Y'}], doc['occurrence_count_changes']
" 2>"$TMP/r41_exempt_check.err"; then
  echo "ok golden-bad-I-R4-1 REAL CLI: an EXEMPTED occurrence-count change exits 0 but stays"
  echo "   visible in --out with its decision reference (exempted='DEC-Y'), never silently vanishing"
else
  echo "NOT ok golden-bad-I-R4-1 REAL CLI: rc=$R41_EXEMPT_RC -- $(cat "$TMP/r41_exempt_check.err" 2>/dev/null)"
  failx
fi
# mutation-catching proof (I-R4-1): a throwaway copy that drops the audit-trail append again.
MUT_R41_ROOT="$TMP/mut_r41"; mkdir -p "$MUT_R41_ROOT/verify"; ln -s "$FC/lib" "$MUT_R41_ROOT/lib"
cp "$TOOL" "$MUT_R41_ROOT/verify/plan_struct_check.py"
python3 - "$MUT_R41_ROOT/verify/plan_struct_check.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
needle = "            occurrence_count_changes.append({\n"
if s.count(needle) != 1:
    print("MUTATION-ANCHOR-NOT-FOUND", file=sys.stderr); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(needle, "            (lambda _e: None)({  # I-R4-1 MUTATION\n", 1))
PY
python3 "$MUT_R41_ROOT/verify/plan_struct_check.py" rule-diff --constitution "$FAKECONST_R41" \
  --base "$R41_V1" --operator-decisions "11.4.998=DEC-Y" --out "$TMP/r41_mut.json" >/dev/null 2>&1
MUT_R41_RC=$?
if [ "$MUT_R41_RC" -eq 0 ] && ! grep -q 'DEC-Y' "$TMP/r41_mut.json"; then
  echo "ok mutation-catching proof (I-R4-1): the throwaway copy that drops the record exits 0 with"
  echo "   ZERO trace of DEC-Y -- exactly the silent-exemption defect golden-bad-I-R4-1 catches"
else
  echo "NOT ok mutation-catching proof (I-R4-1): mutated copy rc=$MUT_R41_RC, DEC-Y count"
  echo "     $(grep -o 'DEC-Y' "$TMP/r41_mut.json" 2>/dev/null | wc -l) (expected rc=0 and 0)"
  failx
fi

# M-R4-1: two occurrences Alpha/Beta, the FIRST deleted -> only the count change is reported,
# never a bogus substantive_change against the untouched surviving Beta.
FAKECONST_M41="$TMP/fakeconst_m41"; mkdir -p "$FAKECONST_M41"
cat >"$FAKECONST_M41/Constitution.md" <<'EOF'
### §11.4.990 -- Alpha occurrence (synthetic)

Alpha body MUST hold.

### §11.4.990 -- Beta occurrence (synthetic)

Beta body MUST hold.
EOF
( cd "$FAKECONST_M41" && git init -q && git config user.email t156@example.invalid \
    && git config user.name "T156 fixture" && git add -A && git commit -q -m v1 ) >"$TMP/m41_git.log" 2>&1
M41_V1=$(cd "$FAKECONST_M41" && git rev-parse HEAD)
cat >"$FAKECONST_M41/Constitution.md" <<'EOF'
### §11.4.990 -- Beta occurrence (synthetic)

Beta body MUST hold.
EOF
python3 "$TOOL" rule-diff --constitution "$FAKECONST_M41" --base "$M41_V1" \
  --out "$TMP/m41.json" >/dev/null 2>"$TMP/m41.err"
M41_RC=$?
if [ "$M41_RC" -eq 1 ] && python3 -c "
import json
doc = json.load(open('$TMP/m41.json', encoding='utf-8'))
assert doc['hunks'] == [], doc['hunks']
assert [v['code'] for v in doc['violations']] == ['anchor_occurrence_count_changed'], doc['violations']
assert doc['occurrence_count_changes'][0]['removed_occurrences'] == [0], doc['occurrence_count_changes']
" 2>"$TMP/m41_check.err"; then
  echo "ok M-R4-1 REAL CLI: deleting the FIRST of two occurrences reports only the count change"
  echo "   (removed_occurrences=[0]); the untouched surviving occurrence is correctly paired by content"
else
  echo "NOT ok M-R4-1 REAL CLI: rc=$M41_RC -- $(cat "$TMP/m41_check.err" 2>/dev/null)"
  failx
fi

# M-R4-3: landing reads gate tokens from EVERY occurrence of a duplicated anchor (the NI3(c)
# duplicate fixture's SECOND block names CM-SELFCHECK-NI3-DUP-2, previously never checked).
if python3 -c "
import json
doc = json.load(open('$TMP/ni3_dup.json', encoding='utf-8'))
gates = sorted(g['gate'] for g in doc['anchors'][0]['gates'])
assert gates == ['CM-SELFCHECK-NI3-DUP-1', 'CM-SELFCHECK-NI3-DUP-2'], gates
" 2>"$TMP/m43_check.err"; then
  echo "ok M-R4-3 REAL CLI: landing reports gates named in EVERY occurrence of a duplicated anchor"
  M43_OK=0
else
  echo "NOT ok M-R4-3 REAL CLI: $(cat "$TMP/m43_check.err" 2>/dev/null)"
  M43_OK=1; failx
fi

echo
echo "=== FIX ROUND 5: I-R5-1 trailing '---' separator move / I-R5-2 blockquote / M-R5-1..3 ==="
# Every case below was run against the PRE-round-5 classifier FIRST (constitution 11.4.6) and
# reproduced the reviewer's exact wrong verdicts: sepmove / realcommit -> SUBSTANTIVE rc=1 (a false
# refusal of a pure new-anchor insertion); bqunnest / bqyamldedent -> STRUCTURAL rc=0 (a false
# PASS); htmlwrap -> ADDITIVE rc=0 (a rule hidden from rendered output passed as additive);
# setextunder -> ADDITIVE rc=0; occreorder -> two SUBSTANTIVE hunks at the wrong occurrences.
R5_FAILS=0
# r5_run <name> <base-file> <after-file> <python-assertion-over-doc> <expected-rc>
r5_run() {
  local name=$1 base=$2 after=$3 check=$4 want_rc=$5
  local d="$TMP/fakeconst_r5_$name"
  mkdir -p "$d"
  cp "$base" "$d/Constitution.md"
  ( cd "$d" && git init -q && git config user.email t156@example.invalid \
      && git config user.name "T156 fixture" && git add -A && git commit -q -m v1 ) \
    >"$TMP/r5_${name}_git.log" 2>&1 || { echo "NOT ok r5 $name: git init failed"; R5_FAILS=$((R5_FAILS+1)); failx; return; }
  local base_sha; base_sha=$(cd "$d" && git rev-parse HEAD)
  cp "$after" "$d/Constitution.md"
  if cmp -s "$base" "$after"; then
    echo "NOT ok r5 $name: base and after are identical (test bug)"; R5_FAILS=$((R5_FAILS+1)); failx; return
  fi
  python3 "$TOOL" rule-diff --constitution "$d" --base "$base_sha" --out "$TMP/r5_$name.json" \
    >"$TMP/r5_$name.out" 2>"$TMP/r5_$name.err"
  local rc=$?
  if [ "$rc" -eq "$want_rc" ] && python3 -c "
import json
doc = json.load(open('$TMP/r5_$name.json', encoding='utf-8'))
$check
" 2>"$TMP/r5_${name}_check.err"; then
    echo "ok fix-round-5 REAL CLI case $name: rc=$rc, assertion held"
  else
    echo "NOT ok fix-round-5 REAL CLI case $name: expected rc=$want_rc, got rc=$rc --"
    echo "     $(cat "$TMP/r5_${name}_check.err" "$TMP/r5_$name.err" 2>/dev/null | tail -3)"
    R5_FAILS=$((R5_FAILS + 1)); failx
  fi
}
r5_pair() {  # r5_pair <name> <python-transform-of-base> <assertion> <rc>  (base = $R5_BASE_FILE)
  local name=$1 transform=$2 check=$3 want_rc=$4
  python3 -c "import sys; t=open('$R5_BASE_FILE', encoding='utf-8').read(); $transform; sys.stdout.write(t)" \
    >"$TMP/r5_${name}_after.md"
  r5_run "$name" "$R5_BASE_FILE" "$TMP/r5_${name}_after.md" "$check" "$want_rc"
}

# I-R5-1 (mandatory): the file's own anchor-separator convention -- a NEW anchor inserted between
# an existing anchor's text and that anchor's own trailing '---'. The existing anchor's own text is
# byte-unchanged; the separator merely moved into the new anchor's block.
R5_BASE_FILE="$TMP/r5_base.md"
cat >"$R5_BASE_FILE" <<'EOF'
### §11.4.981 -- round-5 separator fixture anchor (synthetic)

The 981 rule MUST hold for every candidate.

---

### §11.4.982 -- round-5 following anchor (synthetic)

The 982 rule MUST hold.
EOF
r5_pair sepmove \
  "t=t.replace('for every candidate.\n\n---\n', 'for every candidate.\n\n### §11.4.983 -- new anchor inserted before 981s separator (synthetic)\n\nThe 983 rule MUST hold.\n\n---\n')" \
  "assert doc['violations'] == [], doc['violations']
assert doc['hunks'] == [], doc['hunks']
assert doc['new_anchors'] == ['11.4.983'], doc['new_anchors']" 0
# false-positive guards the OTHER way: a genuine reword of 981 alongside the separator move is
# still SUBSTANTIVE (the fix strips only punctuation, never rule text).
r5_pair sepmovereword \
  "t=t.replace('The 981 rule MUST hold', 'The 981 rule MAY hold').replace('for every candidate.\n\n---\n', 'for every candidate.\n\n### §11.4.983 -- new (synthetic)\n\nThe 983 rule.\n\n---\n')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1
# a mid-body thematic break removed between two unchanged paragraphs is punctuation-only.
cat >"$TMP/r5_midbreak_base.md" <<'EOF'
### §11.4.984 -- round-5 mid-body break fixture (synthetic)

Paragraph one MUST hold.

---

Paragraph two MUST hold.
EOF
python3 -c "import sys; t=open('$TMP/r5_midbreak_base.md').read(); sys.stdout.write(t.replace('\n---\n\n', ''))" \
  >"$TMP/r5_midbreak_after.md"
r5_run midbreak "$TMP/r5_midbreak_base.md" "$TMP/r5_midbreak_after.md" \
  "assert [h['classification'] for h in doc['hunks']] == ['STRUCTURAL'], doc['hunks']" 0

# I-R5-1 REAL end-to-end regression: the exact real commit pair 91aa99d~1 -> 91aa99d, which ONLY
# appends a brand-new §11.4.192 (verified: the pre-existing §11.4.191's own text is unchanged; its
# trailing '---' moved into §11.4.192's block). Pre-round-5 this reported substantive_change on
# §11.4.191 (rc=1). Read-only against the real history: both blobs are copied into an isolated tree.
R5_REAL="$ROOT/constitution"
if git -C "$R5_REAL" cat-file -e 91aa99d~1:Constitution.md 2>/dev/null \
    && git -C "$R5_REAL" cat-file -e 91aa99d:Constitution.md 2>/dev/null; then
  git -C "$R5_REAL" show 91aa99d~1:Constitution.md >"$TMP/r5_real_before.md"
  git -C "$R5_REAL" show 91aa99d:Constitution.md >"$TMP/r5_real_after.md"
  r5_run realcommit "$TMP/r5_real_before.md" "$TMP/r5_real_after.md" \
    "assert not [v for v in doc['violations'] if v.get('anchor') == '11.4.191'], doc['violations']
assert not [h for h in doc['hunks'] if h['anchor'] == '11.4.191'], doc['hunks']
assert doc['violations'] == [], doc['violations']
assert '11.4.192' in doc['new_anchors'], doc['new_anchors']" 0
else
  echo "SKIP fix-round-5 realcommit: commit 91aa99d is not reachable in $R5_REAL (shallow/partial"
  echo "     clone) -- the synthetic sepmove case above covers the same shape (constitution 11.4.3)"
fi

# I-R5-2: blockquote content gets the SAME fine-grained unit treatment as unquoted content.
R5_BASE_FILE="$TMP/r5_bq_base.md"
cat >"$R5_BASE_FILE" <<'EOF'
### §11.4.985 -- round-5 blockquote fixture (synthetic)

> - (A) rule
>   - exception applies ONLY in test
> - (B) rule two
>
> ```yaml
> parent:
>   child: 1
> ```
EOF
r5_pair bqunnest "t=t.replace('>   - exception', '> - exception')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1
r5_pair bqyamldedent "t=t.replace('>   child: 1', '> child: 1')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1
r5_pair bqdepth "t=t.replace('> - (B) rule two', '> > - (B) rule two')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1
r5_pair bqappend "t=t.replace('> - (B) rule two\n', '> - (B) rule two\n> - (C) rule three\n')" \
  "assert [h['classification'] for h in doc['hunks']] == ['ADDITIVE'], doc['hunks']" 0
r5_pair bqrewrap "t=t.replace('> - (B) rule two', '> - (B) rule\n>   two')" \
  "assert [h['classification'] for h in doc['hunks']] == ['STRUCTURAL'], doc['hunks']" 0

# M-R5-1: wrapping an existing rule in a multi-line HTML comment hides it from rendered output.
R5_BASE_FILE="$TMP/r5_html_base.md"
cat >"$R5_BASE_FILE" <<'EOF'
### §11.4.986 -- round-5 html-comment fixture (synthetic)

The 986 rule MUST hold.

The 986 second rule MUST hold.
EOF
r5_pair htmlwrap "t=t.replace('The 986 rule MUST hold.\n', '<!--\nThe 986 rule MUST hold.\n-->\n')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1
r5_pair htmlwrapblank "t=t.replace('The 986 rule MUST hold.\n', '<!--\n\nThe 986 rule MUST hold.\n\n-->\n')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1
r5_pair htmlsingle "t=t + '\n<!-- editorial note, single line (synthetic) -->\n'" \
  "assert [h['classification'] for h in doc['hunks']] == ['ADDITIVE'], doc['hunks']" 0
# M-R5-3 (setext half): a bare '---' directly under an existing paragraph turns it into a heading.
r5_pair setextunder "t=t.replace('The 986 rule MUST hold.\n', 'The 986 rule MUST hold.\n---\n')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']" 1

# I-R5F-1 (final adjudicated fix, T159 fix-loop cap): a column-0 blockquote inserted BETWEEN a
# parent bullet and its nested child terminates the list in rendered Markdown, so the child is no
# longer nested -- a real list-scope transfer. Pre-fix: ADDITIVE rc=0 (false PASS, a regression
# introduced by round 5's quote-context tracking); post-fix: SUBSTANTIVE rc=1.
R5_BASE_FILE="$TMP/r5_bqinsert_base.md"
cat >"$R5_BASE_FILE" <<'EOF'
### §11.4.988 -- round-5-final quote-insert fixture (synthetic)

- (A) Gates MUST refuse unverified claims.
  - Exception: applies ONLY in test fixtures.
EOF
r5_pair bqinsertscope \
  "t=t.replace('claims.\n  - Exception', 'claims.\n\n> Note: see elsewhere.\n\n  - Exception')" \
  "assert [h['classification'] for h in doc['hunks']] == ['SUBSTANTIVE'], doc['hunks']
assert doc['violations'] != [], doc['violations']" 1

# M-R5-2: occurrences reordered AND one of them appended to -- the reviewer's exact [A,B,G] ->
# [B,A,G+" Extra."] repro. True state: A and B unchanged, G gained an ADDITIVE append.
cat >"$TMP/r5_occ_base.md" <<'EOF'
### §11.4.987 -- occurrence A (synthetic)

Alpha body MUST hold.

### §11.4.987 -- occurrence B (synthetic)

Beta body MUST hold.

### §11.4.987 -- occurrence G (synthetic)

Gamma body MUST hold.
EOF
cat >"$TMP/r5_occ_after.md" <<'EOF'
### §11.4.987 -- occurrence B (synthetic)

Beta body MUST hold.

### §11.4.987 -- occurrence A (synthetic)

Alpha body MUST hold.

### §11.4.987 -- occurrence G (synthetic)

Gamma body MUST hold. Extra.
EOF
r5_run occreorder "$TMP/r5_occ_base.md" "$TMP/r5_occ_after.md" \
  "assert doc['hunks'] == [{'anchor': '11.4.987', 'classification': 'ADDITIVE', 'exempted': None, 'occurrence': 2}], doc['hunks']
assert doc['violations'] == [], doc['violations']" 0

# mutation-catching proofs (fix round 5): throwaway copies with each fix reverted are caught by
# self_check_rule_diff()'s OWN new round-5 needles (rc=3, no --out written).
r5_mutation() {
  local label=$1 expect_msg=$2 py_needle=$3 py_repl=$4
  local root="$TMP/mut_r5_$label"
  mkdir -p "$root/verify"; ln -s "$FC/lib" "$root/lib"
  cp "$TOOL" "$root/verify/plan_struct_check.py"
  if ! python3 - "$root/verify/plan_struct_check.py" "$py_needle" "$py_repl" <<'PY'
import sys
path, needle, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, encoding="utf-8").read()
if src.count(needle) != 1:
    print("MUTATION-ANCHOR-NOT-FOUND-OR-AMBIGUOUS", file=sys.stderr); sys.exit(1)
open(path, "w", encoding="utf-8").write(src.replace(needle, repl, 1))
PY
  then
    echo "NOT ok could not prepare fix-round-5 mutation $label (anchor text changed shape)"
    failx; return 1
  fi
  python3 "$root/verify/plan_struct_check.py" rule-diff --constitution "$FAKECONST_R4" \
    --base "$R4_V1" --out "$TMP/r5_mut_$label.json" >/dev/null 2>"$TMP/r5_mut_$label.err"
  local rc=$?
  if [ "$rc" -eq 3 ] && grep -qF "$expect_msg" "$TMP/r5_mut_$label.err" \
      && [ ! -s "$TMP/r5_mut_$label.json" ]; then
    echo "ok mutation-catching proof ($label): reverting the fix is caught by the self-check"
    echo "   needle ('$expect_msg', rc=3, no --out written)"
    return 0
  fi
  echo "NOT ok mutation-catching proof ($label): expected rc=3 + '$expect_msg', got rc=$rc --"
  echo "     $(cat "$TMP/r5_mut_$label.err" 2>/dev/null | tail -2)"
  failx; return 1
}
r5_base_restore() { r4_base >"$FAKECONST_R4/Constitution.md"; }
r5_base_restore
r5_mutation IR51strip "self-check FAILED (I-R5-1, fix round 5)" \
  '        end = _strip_trailing_separator(lines, line_idx, end)
' \
  '        pass  # I-R5-1 MUTATION
'
MUT_R5_STRIP_OK=$?
r5_mutation IR51break "self-check FAILED (I-R5-1, fix round 5)" \
  '            if _THEMATIC_BREAK_RE.match(line):
' \
  '            if False:  # I-R5-1 MUTATION
'
MUT_R5_BREAK_OK=$?
r5_mutation IR52 "self-check FAILED (I-R5-2, fix round 5)" \
  '        if _BLOCKQUOTE_RE.match(line):
' \
  '        if False:  # I-R5-2 MUTATION
'
MUT_R5_BQ_OK=$?

echo
echo "=== T159 contract stub 1/5: subcommands GREEN against real data (SC-C-004/SC-C-005) ==="
echo "VERIFIED (real invocation, sections (2)-(3) above -- REMEDIATED post-"
echo "  landing from this file's own original RED-baseline absence check,"
echo "  per this task's own minimal-edit instruction): both \`landing\` and"
echo "  \`rule-diff\` now exist, accept their real --anchors/--base argument"
echo "  shapes, and return a genuine decided verdict + well-formed --out"
echo "  JSON against REAL repository data (a real anchor's real ledger/"
echo "  propagation-gate state; the real, byte-identical current"
echo "  Constitution.md diffed against itself via --base HEAD)."

echo
echo "=== T159 contract stub 2/5: the three checks THIS test pins ==="
echo "VERIFIED (independent instruments, sections above -- Producer !="
echo "  Verifier, §11.4.240; each with its own §11.4.201(1) false-positive"
echo "  guard): (a) a rule naming a gate with no real seam and no"
echo "  §11.4.227(A) ledger-deferral row is mechanically UNIMPLEMENTED"
echo "  today, via the REAL gate_ledger.sh (golden-bad-landing); (b) the"
echo "  SAME gate, once its deferral is registered, is mechanically"
echo "  DEFERRED, not UNIMPLEMENTED (the guard); (c) a diff that reworks an"
echo "  existing rule's wording is classified SUBSTANTIVE (golden-bad-"
echo "  rulediff); (d) a diff that only appends a new clause, leaving every"
echo "  existing sentence untouched, is classified ADDITIVE (the negative"
echo "  control); (e) an identical before/after pair classifies UNCHANGED,"
echo "  never SUBSTANTIVE (the guard)."

echo
echo "=== T159 contract stub 3/5: OUT OF SCOPE for T156/T159 (honest disclosure) ==="
echo "NOT covered by THIS file (separate contract clauses / a later task's"
echo "  test, per plan-research-structural-check.md's own RED fixtures"
echo "  table): STRUCTURAL hunk classification BEYOND pure whitespace/paragraph"
echo "  reflow (heading-FORMAT normalization e.g. '###' <-> '**...**', and true"
echo "  line MOVES ACROSS non-adjacent paragraphs -- the shipped classifier's"
echo "  STRUCTURAL tier, extended in review round 3 (NI2) to also cover pure"
echo "  paragraph rewrap + paragraph-boundary (blank-line) reflow, still does"
echo "  NOT cover these two; see classify_diff()'s own docstring for this"
echo "  honestly-disclosed narrower scope); full mirror-set content-hash"
echo "  equality beyond the invoked per-anchor propagation-gate wrapper's own"
echo "  result (landing genuinely invokes cm_covenant_114_<N>_propagation.sh"
echo "  when one is registered for the requested anchor); \`sc_bad_duplicate_block\`"
echo "  (a DIFFERENT FR-019 golden-bad fixture, anchor twice in one MIRROR file,"
echo "  not this task's named check -- distinct from this file's own"
echo "  anchor_occurrence_count_changed, which is a genuine duplicate WITHIN"
echo "  Constitution.md itself, review round 3, NB1)."
echo "NI1 (review round 3, HONEST DISCLOSURE, independent §11.4.209 Opus-xhigh"
echo "  review round 2): BOTH \`landing\` and \`rule-diff\` are scoped, TODAY, to"
echo "  §11.4.N-numbered anchors ONLY -- §1 through §10 (INCLUDING §9.2's own"
echo "  force-push-authorization language), the §11.4 preamble text itself, and"
echo "  §12 onward are NOT currently monitored for substantive changes by"
echo "  either subcommand. A rewording of, say, §9.2's 'MUST be authorized' to"
echo "  'MAY be skipped' is invisible to \`rule-diff\` today -- a KNOWN,"
echo "  DELIBERATELY DISCLOSED gap (see plan_struct_check.py's own module"
echo "  docstring for the identical disclosure), never silently assumed closed."

echo
echo "=== T159 contract stub 4/5: REVIEW ROUND 1 REMEDIATION (B1/B2/B3/I1/I2/I3/I4) ==="
echo "VERIFIED (real end-to-end CLI invocations against isolated fixture"
echo "  trees, plus a throwaway-mutated-copy catch-proof, sections above --"
echo "  I1): (B1) a mid-body citation bullet and a sub-clause heading naming"
echo "  an anchor from inside a DIFFERENT anchor's own block are proven, via"
echo "  self_check_landing()'s own decoy fixture, to NEVER be mistaken for a"
echo "  new block-start; (B2) deleting a WHOLE existing anchor is a real,"
echo "  reported \`anchor_removed\` violation, exempt-able the SAME way as a"
echo "  SUBSTANTIVE hunk; (B3) an anchor with NO registered propagation"
echo "  wrapper is a real, reported \`propagation_gate_not_registered\`"
echo "  violation -- \`landing\` can no longer exit clean purely because"
echo "  nothing was wired for the requested anchor; (I2) classify_diff()'s"
echo "  own docstring now explicitly discloses that an ADDITIVE verdict is"
echo "  purely mechanical and never implies a semantic override embedded in"
echo "  new text is safe; (I3) a pure trailing/internal-whitespace reflow"
echo "  now classifies STRUCTURAL, never a false-positive SUBSTANTIVE; (I4)"
echo "  --operator-decisions now takes REFERENCED <anchor>=<decision-record>"
echo "  pairs (a bare anchor number is a usage error, exit 2), and every"
echo "  exempted hunk/removed-anchor's own --out JSON entry names the"
echo "  decision reference used, never merely implying exemption by"
echo "  omission -- all exercised here via the REAL \`landing\`/\`rule-diff\`"
echo "  CLI against fully isolated, self-contained fixture trees, with a"
echo "  throwaway mutated-copy proof (never the tracked file) demonstrating"
echo "  these exact new assertions are what catch a force-pass regression."

echo
echo "=== T159 contract stub 5/5: REVIEW ROUND 3 REMEDIATION (NB1/NB2/NI1/NI2/m1) ==="
echo "VERIFIED (real end-to-end CLI invocations against isolated fixture trees"
echo "  plus, for the two BLOCKING findings NB1/NB2, real read-only invocations"
echo "  against the ACTUAL corpus data, each with a throwaway-mutated-copy"
echo "  catch-proof, sections above): (NB1) an anchor's own key is now its FULL"
echo "  dotted identifier (e.g. '11.4.991.A' genuinely distinct from its own"
echo "  parent '11.4.991'), a reword or outright deletion of a dotted anchor is"
echo "  detected and correctly attributed, and EVERY genuine occurrence of a"
echo "  shared anchor key is compared (not merely occ[0]) -- a reword landing"
echo "  ONLY on a SECOND genuine occurrence of a duplicated anchor number is"
echo "  detected, and a change in the NUMBER of occurrences itself is its own"
echo "  \`anchor_occurrence_count_changed\` violation; (NB2) an anchor's own"
echo "  block now ends at the next top-level '## ' heading OR the next"
echo "  non-anchor numbered '### §' heading, in ADDITION to the next §11.4.N"
echo "  anchor -- proven directly against the REAL corpus: §11.4.170's own"
echo "  block no longer absorbs any of §12's own gates; (NI1) the pre-existing"
echo "  §1-§10/preamble/§12+ blindness is now explicitly, prominently disclosed"
echo "  in this stub 3/5 section above AND in plan_struct_check.py's own"
echo "  module docstring, never silently assumed covered; (NI2) classify_diff()"
echo "  now additionally compares at PARAGRAPH granularity -- a single word"
echo "  inserted mid-sentence (splitting an existing hard-wrapped line into an"
echo "  extra one) is detected as SUBSTANTIVE, never the false-negative ADDITIVE"
echo "  a purely line-level classifier reports, and a pure paragraph re-wrap"
echo "  (identical words, different line-break point) classifies STRUCTURAL,"
echo "  never the false-positive SUBSTANTIVE a purely line-level classifier"
echo "  reports; (m1) the regex-boundary comment's own self-contradictory"
echo "  '\"--\" (space, em-dash, space)' wording is corrected to consistently"
echo "  describe the real Unicode em-dash character the code has always"
echo "  required. (NI3, best-effort coverage additions, sections above):"
echo "  (a) a GENUINE bold-paragraph-form heading (not merely the H3 form every"
echo "  other needle exercises) is proven recognised by self_check_landing()'s"
echo "  own new anchor-904 needle; (c) real CLI-level assertions now cover"
echo "  anchor_not_found (against real corpus data), duplicate_block_in_corpus"
echo "  (a genuinely duplicated non-dotted anchor), the propagation_gate_blind /"
echo "  overall exit-4 BLIND path (a wrapper exiting an unusual code), and a"
echo "  STRUCTURAL hunk (the NI2 rewrap fixture above, at CLI level); (d) the"
echo "  sub-clause-heading self-check decoy now uses the REAL em-dash byte,"
echo "  matching the actual real-corpus false-positive shape it guards against,"
echo "  never the weaker plain-ASCII '--' an earlier draft used. NOT addressed"
echo "  this round (honest disclosure, time-bounded per this task's own"
echo "  instruction): a dedicated mutation-catching CLI proof for EACH of these"
echo "  four NI3 sub-items specifically (they are covered by real-CLI/self-check"
echo "  assertions, not by their own throwaway-mutated-copy catch-proof the way"
echo "  NB1/NB2/NI2 above are)."

echo
echo "=== T159 contract stub 6/6: FIX ROUND 4 REMEDIATION (I-R4-1/I-R4-2/I-R4-3 + M-R4-1/2/3) ==="
echo "VERIFIED (real end-to-end CLI invocations against isolated fixture trees, each"
echo "  reviewer repro confirmed FAILING against the pre-round-4 classifier first, plus"
echo "  throwaway-mutated-copy catch-proofs): (I-R4-1) an EXEMPTED occurrence-count change"
echo "  is recorded in --out occurrence_count_changes with its decision reference, never"
echo "  silently discarded; (I-R4-2/I-R4-3) classify_diff() is now a LOGICAL-UNIT diff"
echo "  (list items / table rows / headings / fence+code lines / prose runs, nesting depth"
echo "  and code indent part of each unit's identity, word-level tail-append detection"
echo "  within a unit) -- un-nesting, YAML dedent inside a fence and merging two list items"
echo "  are SUBSTANTIVE; appending a table row, a list item or a sentence is ADDITIVE; NI2's"
echo "  mid-sentence insert stays SUBSTANTIVE and its pure rewrap STRUCTURAL; (M-R4-1)"
echo "  duplicate occurrences are paired by content; (M-R4-2) letter-suffixed and H3"
echo "  sub-clause headings are parsed correctly (self_check_landing needles); (M-R4-3)"
echo "  landing checks gates named in EVERY occurrence. HONEST BOUNDARY: a sentence inserted"
echo "  BETWEEN two existing sentences of one paragraph, or words continuing an unfinished"
echo "  sentence, classify SUBSTANTIVE by design (conservative); see classify_diff()."

echo
echo "=== T159 contract stub 7/7: FIX ROUND 5 REMEDIATION (I-R5-1/I-R5-2 + M-R5-1/2/3) ==="
echo "VERIFIED (real end-to-end CLI invocations against isolated fixture trees, each reviewer"
echo "  repro confirmed FAILING against the pre-round-5 code first, plus throwaway-mutated-copy"
echo "  catch-proofs through self_check_rule_diff()'s own round-5 needles): (I-R5-1) a new anchor"
echo "  inserted before an existing anchor's trailing '---' leaves that anchor UNCHANGED, incl. the"
echo "  REAL commit pair 91aa99d~1 -> 91aa99d (rc=0, no hunk on 11.4.191); (I-R5-2) un-nest /"
echo "  YAML dedent / quote-depth change INSIDE a blockquote are SUBSTANTIVE, an append inside one"
echo "  ADDITIVE, a rewrap STRUCTURAL; (M-R5-1) an HTML-comment wrap is SUBSTANTIVE; (M-R5-2) the"
echo "  [A,B,G] -> [B,A,G+Extra] repro reports ONE ADDITIVE hunk at occurrence 2; (M-R5-3, setext"
echo "  half) a '---' under a paragraph is SUBSTANTIVE. HONEST BOUNDARY: an unfenced 4-space"
echo "  indented code block dedent is NOT modeled (latent false-PASS-capable, zero real instances);"
echo "  see classify_diff() boundaries (5)-(8)."

echo
echo "SUMMARY control_needle=ok landing_functional=$([ "$LANDING_RC" -eq 0 -o "$LANDING_RC" -eq 1 ] 2>/dev/null && echo yes || echo no)" \
     "rule_diff_functional=$([ "$RULEDIFF_RC" -eq 0 ] 2>/dev/null && echo yes || echo no)" \
     "landing_fixture_verified=$([ "$LEDGER_UNDEF_RC" -eq 0 ] && [ "$UNDEF_LINE" = "$EXPECT_UNDEF" ] 2>/dev/null && echo yes || echo no)" \
     "rulediff_fixtures_verified=$([ "$SUB_CLASS" = "SUBSTANTIVE" ] && [ "$ADD_CLASS" = "ADDITIVE" ] 2>/dev/null && echo yes || echo no)" \
     "landing_real_cli_verified=$([ "$FL_BAD_RC" -eq 1 ] && [ "$FL_GOOD_RC" -eq 0 ] && [ "$FL_MUT_RC" -eq 0 ] 2>/dev/null && echo yes || echo no)" \
     "rulediff_real_cli_verified=$([ "$RD_BAD_RC" -eq 1 ] && [ "$RD_EXEMPT_RC" -eq 0 ] && [ "$RD_ADD_RC" -eq 0 ] && [ "$RD_REMOVED_RC" -eq 1 ] && [ "$RD_MUT_RC" -eq 0 ] 2>/dev/null && echo yes || echo no)" \
     "nb1_verified=$([ "$NB1_REWORD_RC" -eq 1 ] && [ "$MUT_NB1A_RC" -eq 1 ] && [ "$NB1_DELETE_RC" -eq 1 ] && [ "$NB1B_REWORD_RC" -eq 1 ] && [ "$MUT_NB1B_RC" -eq 0 ] 2>/dev/null && echo yes || echo no)" \
     "nb2_verified=$([ -n "$NB2_LANDING_RC" ] && [ "$MUT_NB2_RC" -eq 3 ] 2>/dev/null && echo yes || echo no)" \
     "ni2_verified=$([ "$NI2_INSERT_RC" -eq 1 ] && [ "$NI2_REWRAP_RC" -eq 0 ] && [ "$MUT_NI2_REWRAP_RC" -eq 3 ] 2>/dev/null && echo yes || echo no)" \
     "ni3_verified=$([ "$NI3_NOTFOUND_RC" -eq 1 ] && [ "$NI3_DUP_RC" -eq 1 ] && [ "$NI3_BLIND_RC" -eq 4 ] 2>/dev/null && echo yes || echo no)" \
     "r4_verified=$([ "$R4_FAILS" -eq 0 ] && [ "$MUT_R4_IR42_OK" -eq 0 ] && [ "$MUT_R4_IR43_OK" -eq 0 ] && [ "$R41_PLAIN_RC" -eq 1 ] && [ "$R41_EXEMPT_RC" -eq 0 ] && [ "$MUT_R41_RC" -eq 0 ] && [ "$M41_RC" -eq 1 ] && [ "$M43_OK" -eq 0 ] 2>/dev/null && echo yes || echo no)" \
     "r5_verified=$([ "$R5_FAILS" -eq 0 ] && [ "$MUT_R5_STRIP_OK" -eq 0 ] && [ "$MUT_R5_BREAK_OK" -eq 0 ] && [ "$MUT_R5_BQ_OK" -eq 0 ] 2>/dev/null && echo yes || echo no)" \
     "fail=$fail"
exit $fail
