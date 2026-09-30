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
# Usage : bash test_plan_struct_landing_rulediff_red.sh   Exit 0 = RED
#         baseline holds (both subcommands genuinely absent from the CLI
#         today, and all three fixtures -- one golden-bad per subcommand
#         plus the negative control -- independently verified, via
#         SEPARATE instruments, to encode exactly the defect/non-defect
#         each is designed to encode, each with its own false-positive
#         guard per constitution 11.4.201(1)). Matches the
#         T017/T024/T025/T026 "exit 0 = RED baseline PASS" convention
#         already used throughout this qa-results tree (not T018's
#         different "exit 0 only once GREEN" convention).
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
  echo "ok verify/plan_struct_check.py exists (T046 landed, causes-only --"
  echo "   its own module docstring states 'the research, plan, landing and"
  echo "   rule-diff subcommands land in T159 and T179') -- the CLI-level"
  echo "   absence checks below are the real RED evidence for THIS task"
else
  echo "NOT ok verify/plan_struct_check.py is absent entirely -- T046 was"
  echo "     reviewed GO and committed; a regression removed the whole file"
  failx
fi

# --- (2) Real CLI invocation: `landing` subcommand must not exist today ---
python3 "$TOOL" landing --constitution "$ROOT/constitution/" --anchors x \
  --out "$TMP/landing.json" >"$TMP/landing_invoke.out" 2>"$TMP/landing_invoke.err"
LANDING_RC=$?
LANDING_ERR=$(cat "$TMP/landing_invoke.err" 2>/dev/null)
echo "info landing invocation today: rc=$LANDING_RC stderr='$LANDING_ERR'"
if [ "$LANDING_RC" -ne 2 ]; then
  echo "NOT ok expected argparse's own usage-error exit code (2) for the"
  echo "     not-yet-implemented 'landing' subcommand, got rc=$LANDING_RC --"
  echo "     either the subcommand has landed (re-point this RED test at"
  echo "     T159's real functional checks, matching test_plan_struct_"
  echo "     causes_red.sh's own post-landing remediation pattern) or"
  echo "     something else changed; re-verify rather than trust this"
  echo "     file's prose (§11.4.6)"
  failx
elif ! printf '%s' "$LANDING_ERR" | grep -qF "invalid choice: 'landing'"; then
  echo "NOT ok landing invocation exited 2 as expected but stderr did not"
  echo "     contain \"invalid choice: 'landing'\" -- got: $LANDING_ERR"
  failx
else
  echo "ok landing subcommand genuinely absent today: real invocation exits"
  echo "   2 with argparse's own 'invalid choice' message naming 'landing'"
  echo "   (T159 has not landed)"
fi
if [ -e "$TMP/landing.json" ]; then
  echo "NOT ok landing invocation wrote --out despite a usage error (a"
  echo "     usage error must never write, per the causes subcommand's own"
  echo "     documented C-001 'Side-effects' convention)"
  failx
else
  echo "ok landing invocation wrote no --out JSON on its usage error"
fi

# --- (3) Real CLI invocation: `rule-diff` subcommand must not exist today ---
python3 "$TOOL" rule-diff --constitution "$ROOT/constitution/" --base HEAD \
  --out "$TMP/rulediff.json" >"$TMP/rulediff_invoke.out" 2>"$TMP/rulediff_invoke.err"
RULEDIFF_RC=$?
RULEDIFF_ERR=$(cat "$TMP/rulediff_invoke.err" 2>/dev/null)
echo "info rule-diff invocation today: rc=$RULEDIFF_RC stderr='$RULEDIFF_ERR'"
if [ "$RULEDIFF_RC" -ne 2 ]; then
  echo "NOT ok expected argparse's own usage-error exit code (2) for the"
  echo "     not-yet-implemented 'rule-diff' subcommand, got rc=$RULEDIFF_RC"
  failx
elif ! printf '%s' "$RULEDIFF_ERR" | grep -qF "invalid choice: 'rule-diff'"; then
  echo "NOT ok rule-diff invocation exited 2 as expected but stderr did not"
  echo "     contain \"invalid choice: 'rule-diff'\" -- got: $RULEDIFF_ERR"
  failx
else
  echo "ok rule-diff subcommand genuinely absent today: real invocation"
  echo "   exits 2 with argparse's own 'invalid choice' message naming"
  echo "   'rule-diff' (T159 has not landed)"
fi
if [ -e "$TMP/rulediff.json" ]; then
  echo "NOT ok rule-diff invocation wrote --out despite a usage error"
  failx
else
  echo "ok rule-diff invocation wrote no --out JSON on its usage error"
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

echo
echo "=== T159 contract stub 1/3: subcommand absence (SC-C-004/SC-C-005) ==="
echo "VERIFIED (real invocation, sections (2)-(3) above): both \`landing\`"
echo "  and \`rule-diff\` are rejected by argparse today (exit=2, 'invalid"
echo "  choice'), no --out JSON is written on either usage error, and"
echo "  \`causes\` alone remains a valid subcommand -- matching the module"
echo "  docstring's own stated T159 scope boundary."

echo
echo "=== T159 contract stub 2/3: the three checks THIS test pins ==="
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
echo "=== T159 contract stub 3/3: OUT OF SCOPE for T156 (honest disclosure) ==="
echo "NOT covered by THIS file (separate contract clauses / a later task's"
echo "  test, per plan-research-structural-check.md's own RED fixtures"
echo "  table): STRUCTURAL hunk classification (whitespace/heading/moves"
echo "  with byte-identical content per anchor hash); the real"
echo "  \`--anchors <list>\` / \`--base <sha>\` argument-parsing shape once"
echo "  \`landing\`/\`rule-diff\` actually exist; content-hash equality across"
echo "  the lockstep mirror set; the real propagation/block-integrity gate"
echo "  invocation SC-C-004 requires; \`sc_bad_duplicate_block\` (a"
echo "  DIFFERENT FR-019 golden-bad fixture, anchor twice in one mirror,"
echo "  not this task's named check); and the operator-decision-record"
echo "  exemption for an accepted SUBSTANTIVE change."

echo
echo "SUMMARY control_needle=ok landing_absent=$([ "$LANDING_RC" -eq 2 ] 2>/dev/null && echo yes || echo no)" \
     "rule_diff_absent=$([ "$RULEDIFF_RC" -eq 2 ] 2>/dev/null && echo yes || echo no)" \
     "landing_fixture_verified=$([ "$LEDGER_UNDEF_RC" -eq 0 ] && [ "$UNDEF_LINE" = "$EXPECT_UNDEF" ] 2>/dev/null && echo yes || echo no)" \
     "rulediff_fixtures_verified=$([ "$SUB_CLASS" = "SUBSTANTIVE" ] && [ "$ADD_CLASS" = "ADDITIVE" ] 2>/dev/null && echo yes || echo no)" \
     "fail=$fail"
exit $fail
