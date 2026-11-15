#!/usr/bin/env bash
# cm_anchor_record_complete_mutation_test.sh — paired §1.1 mutation for T327
# (task T331), covering gate CM-ANCHOR-RECORD-COMPLETE.
#
# ── What this proves ─────────────────────────────────────────────────────────
# T331: "defaults `anchor_strength` to `mechanism` with no probe evidence, and
#        separately drops `entry_count`, asserting the gate FAILs on each."
#
# A gate's passes do not count until a mutation has been OBSERVED making it
# fail (§11.4.115(F)). This script mutates the SHIPPED mechanism — not the
# gate, and not the gate's fixtures — in an OUT-OF-REPO COPY (§11.4.84), and
# asserts the gate turns red for the RIGHT check.
#
# ── The two mutations ────────────────────────────────────────────────────────
#   M1  pkg/anchor/strength.go — ProbeStrength's nil-probe branch returns
#       {PASS, mechanism} instead of {SKIP, unknown}: the strongest claim is
#       now the DEFAULT, reached with no probe behind it. This is the exact
#       theatre §11.4.6 forbids ("policy-forbidden is not mechanically-
#       prevented"), and the gate must catch it.
#         MUST flip to FAIL : A2_unprobed_strength_is_unknown
#                             A9_unprobed_mechanism_refused
#         MUST remain PASS  : A8_probe_verified_mechanism_accepted
#       That last one is the point of the specificity assertion: a mutation
#       that reddened the whole gate would be indistinguishable from one that
#       broke it, and a gate that refuses everything is useless (§11.4.201(1)).
#
#   M2  pkg/anchor/anchor.go — Validate stops refusing EntryCount <= 0, so an
#       anchor may be recorded with no count. head_digest alone makes WHOLESALE
#       DELETION silent (there is no head left to compare), and the count is
#       what turns that silence into a detected absence.
#         MUST flip to FAIL : A12b_missing_entry_count_refused
#                             A5a_missing_entry_count_refused
#         MUST remain PASS  : A12a_complete_record_accepted
#                             A12c_missing_head_digest_refused
#
# ── Why this is not a tautology (§11.4.115(F)) ───────────────────────────────
# Neither mutation deletes a string the gate greps for. Both change BEHAVIOUR:
# M1 changes what the seam WRITES into an anchor record, M2 changes what the
# shipped validator ACCEPTS. The gate notices because it reads the record and
# drives the validator, not because a literal vanished.
#
# ── Anti-bluff on the mutation itself ────────────────────────────────────────
#   * every mutation is applied to a COPY under mktemp -d; the repository is
#     never written to, and that is proven by a checksum of the source tree
#     taken before and after the whole run;
#   * a mutation whose diff changed NOTHING is refused as a tautology (the
#     checksum of the copy must move, and the mutated text must be present);
#   * the BASELINE must be green before any mutation is applied — a mutation
#     test run against a red baseline proves nothing;
#   * restoration is verified by checksum, and the final run re-proves the gate
#     green on the restored tree.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_anchor_record_complete_mutation_test.sh [--engine <dir>] [--gate <path>]
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS | 1 FAIL (a mutation did NOT make the gate fail, or flipped the
#                    wrong check) | 4 REFUSE (could not decide — never 0)
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, go, jq, git, sed, sha256sum. Any absent -> REFUSE.
# ─────────────────────────────────────────────────────────────────────────────

set -u

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
NAME="CM-ANCHOR-RECORD-COMPLETE mutation test (T331)"
engine=""
gate=""

while [ $# -gt 0 ]; do
    case "$1" in
        --engine) engine="${2:-}"; shift 2 ;;
        --engine=*) engine="${1#--engine=}"; shift ;;
        --gate) gate="${2:-}"; shift 2 ;;
        --gate=*) gate="${1#--gate=}"; shift ;;
        -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
        *) echo "$NAME: unknown argument: $1" >&2; exit 4 ;;
    esac
done

gates_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -n "$engine" ] || engine="${gates_dir}/../../submodules/continuum"
[ -n "$gate" ] || gate="${gates_dir}/cm_anchor_record_complete.sh"

warn() { echo "$@" >&2; }
fail_count=0
note() { echo "$@"; }
bad()  { warn "❌ $*"; fail_count=$((fail_count + 1)); }
good() { echo "✅ $*"; }

refuse() {
    warn "🛑 REFUSE   ${NAME}: $*"
    warn "   Nothing was decided. This is not a pass (§11.4.201(6))."
    exit 4
}

for tool in go jq git sed sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || refuse "required tool '$tool' is not on PATH"
done
[ -x "$gate" ] || refuse "the gate under test is not executable at '$gate'"
[ -d "$engine" ] || refuse "engine root '$engine' does not exist"
engine_abs=$(CDPATH= cd -- "$engine" && pwd) || refuse "engine root could not be resolved"

tmp=$(mktemp -d 2>/dev/null) || refuse "could not create a temporary working directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

# Checksum over every Go file's path AND content. Filenames in this module carry
# no whitespace (asserted below), so xargs is safe here.
tree_sum() {
    ( cd "$1" && find . -type f -name '*.go' | sort | xargs sha256sum ) 2>/dev/null | sha256sum | cut -d' ' -f1
}

ws=$(find "$engine_abs" -type f -name '* *' 2>/dev/null | head -1)
[ -z "$ws" ] || refuse "the engine tree contains a path with whitespace ('$ws'); the checksum instrument used here would be unreliable, so it refuses rather than report a number it cannot stand behind"

src_sum_before=$(tree_sum "$engine_abs")
[ -n "$src_sum_before" ] || refuse "the source-tree checksum instrument returned nothing — it is blind, so 'the repo was not written to' could not be proven"

echo "──────────────────────────────────────────────────────────────────────"
echo "${NAME}"
echo "  gate   : ${gate}"
echo "  engine : ${engine_abs}"
echo "  source tree sha256(go files): ${src_sum_before}"
echo "──────────────────────────────────────────────────────────────────────"

cp -a "$engine_abs" "${tmp}/engine" || refuse "could not copy the engine out of the repo"
cp -a "$engine_abs" "${tmp}/pristine" || refuse "could not take a pristine reference copy"
copy_sum_before=$(tree_sum "${tmp}/engine")
[ "$copy_sum_before" = "$src_sum_before" ] || refuse "the out-of-repo copy does not match the source (${copy_sum_before} vs ${src_sum_before}); mutating it would not be mutating the code under test"
good "out-of-repo copy is byte-faithful to the source (§11.4.84 — the repo itself is never touched)"

run_gate() {
    # run_gate <label>; sets GATE_RC and writes ${tmp}/<label>.out
    rg_label="$1"
    "$gate" --engine "${tmp}/engine" --quiet >"${tmp}/${rg_label}.out" 2>"${tmp}/${rg_label}.err"
    GATE_RC=$?
}

verdict_of() {
    # verdict_of <label> <check-id> -> PASS|FAIL|SKIP|ABSENT
    vo_line=$(grep -m1 "^RESULT $2 " "${tmp}/$1.out" 2>/dev/null)
    if [ -z "$vo_line" ]; then
        echo ABSENT
    else
        echo "$vo_line" | awk '{print $3}'
    fi
}

# --- baseline ---------------------------------------------------------------
run_gate baseline
base_rc=$GATE_RC
if [ "$base_rc" -ne 0 ]; then
    warn "$(cat "${tmp}/baseline.err")"
    refuse "the BASELINE gate run exited ${base_rc} on the unmutated copy; a mutation test against a red baseline proves nothing"
fi

# Control needle (§11.4.201(7)(b)): before any "this check FAILed" or "this
# check is absent" claim, prove the RESULT parser can see a line at all.
needle=$(grep -c '^RESULT ' "${tmp}/baseline.out")
rc=$?
if [ "$rc" -ne 0 ] || [ "$needle" -lt 1 ]; then
    refuse "control needle failed: the RESULT parser found 0 lines in a gate run that emits them, so it is blind and every verdict claim below would be unfounded"
fi
good "baseline is GREEN (exit 0) and the RESULT parser sees ${needle} verdict lines"

assert_flip() {
    # assert_flip <label> <check-id> <expected-verdict> <why>
    af_v=$(verdict_of "$1" "$2")
    if [ "$af_v" = "$3" ]; then
        good "  $2 = $3 ($4)"
    else
        bad "  $2 = ${af_v}, expected $3 ($4)"
    fi
}

# --- M1: strength defaults to `mechanism` with no probe evidence ------------
echo "── M1: ProbeStrength(nil) returns {PASS, mechanism} instead of {SKIP, unknown}"
sed -i 's|return StrengthResult{SKIP, StrengthUnknown, ErrNoProbe.Error()}|return StrengthResult{PASS, StrengthMechanism, ErrNoProbe.Error()}|' \
    "${tmp}/engine/pkg/anchor/strength.go"
rc=$?
[ "$rc" -eq 0 ] || refuse "M1 could not be applied (sed exit $rc)"
m1_sum=$(tree_sum "${tmp}/engine")
if [ "$m1_sum" = "$copy_sum_before" ]; then
    refuse "M1 changed nothing — a mutation whose diff is empty is a refused tautology (§11.4.115(F))"
fi
grep -qF 'return StrengthResult{PASS, StrengthMechanism, ErrNoProbe.Error()}' "${tmp}/engine/pkg/anchor/strength.go"
rc=$?
[ "$rc" -eq 0 ] || refuse "M1 did not land: the mutated text is absent from the copy"

run_gate m1
m1_rc=$GATE_RC
if [ "$m1_rc" -ne 0 ]; then
    good "M1 makes the gate FAIL (exit ${m1_rc}) — the gate catches an unprobed 'mechanism' default"
else
    bad "M1 did NOT make the gate fail (exit ${m1_rc}); the gate would accept an anchor claiming mechanical protection with no probe behind it"
fi
assert_flip m1 A2_unprobed_strength_is_unknown FAIL "the seam now writes 'mechanism' where the probe never ran"
assert_flip m1 A9_unprobed_mechanism_refused FAIL "the validator now accepts 'mechanism' against a probe that never ran"
assert_flip m1 A8_probe_verified_mechanism_accepted PASS "specificity: the false-positive guard must SURVIVE the mutation, or the gate has merely gone red everywhere"

rm -rf "${tmp}/engine" && cp -a "${tmp}/pristine" "${tmp}/engine" || refuse "M1 could not be restored"
restored=$(tree_sum "${tmp}/engine")
[ "$restored" = "$copy_sum_before" ] || bad "M1 restoration is not byte-identical to the baseline copy (${restored} vs ${copy_sum_before})"

# --- M2: entry_count is dropped from the completeness rule ------------------
echo "── M2: Validate stops refusing an anchor with no entry_count"
sed -i 's|if a.EntryCount <= 0 {|if false { // MUTATION T331-M2: entry_count completeness dropped|' \
    "${tmp}/engine/pkg/anchor/anchor.go"
rc=$?
[ "$rc" -eq 0 ] || refuse "M2 could not be applied (sed exit $rc)"
m2_sum=$(tree_sum "${tmp}/engine")
if [ "$m2_sum" = "$copy_sum_before" ]; then
    refuse "M2 changed nothing — a mutation whose diff is empty is a refused tautology (§11.4.115(F))"
fi

run_gate m2
m2_rc=$GATE_RC
if [ "$m2_rc" -ne 0 ]; then
    good "M2 makes the gate FAIL (exit ${m2_rc}) — the gate catches a record that may omit entry_count"
else
    bad "M2 did NOT make the gate fail (exit ${m2_rc}); an anchor with no entry_count would be accepted, and wholesale deletion would be silent"
fi
assert_flip m2 A12b_missing_entry_count_refused FAIL "the shipped validator now accepts a record with no entry_count"
assert_flip m2 A5a_missing_entry_count_refused FAIL "the read seam no longer refuses FOR THAT REASON"
assert_flip m2 A12a_complete_record_accepted PASS "specificity: a complete record must still be accepted"
assert_flip m2 A12c_missing_head_digest_refused PASS "specificity: the head_digest half of the rule is untouched"

rm -rf "${tmp}/engine" && cp -a "${tmp}/pristine" "${tmp}/engine" || refuse "M2 could not be restored"
restored=$(tree_sum "${tmp}/engine")
[ "$restored" = "$copy_sum_before" ] || bad "M2 restoration is not byte-identical to the baseline copy (${restored} vs ${copy_sum_before})"

# --- restored tree must be green again -------------------------------------
run_gate restored
r_rc=$GATE_RC
if [ "$r_rc" -eq 0 ]; then
    good "the restored copy is GREEN again (exit 0) — the red runs above were caused by the mutations, not by the harness"
else
    bad "the restored copy is NOT green (exit ${r_rc}); the mutation runs cannot be attributed to the mutations"
fi

# --- the repository itself must be untouched -------------------------------
src_sum_after=$(tree_sum "$engine_abs")
if [ "$src_sum_after" = "$src_sum_before" ]; then
    good "the in-repo engine tree is byte-identical to how it started (${src_sum_after})"
else
    bad "the in-repo engine tree CHANGED during this run (${src_sum_before} -> ${src_sum_after})"
fi

echo "──────────────────────────────────────────────────────────────────────"
if [ "$fail_count" -ne 0 ]; then
    echo "❌ ${NAME}: FAIL — ${fail_count} assertion(s) did not hold"
    exit 1
fi
echo "✅ ${NAME}: PASS — both mutations were OBSERVED making CM-ANCHOR-RECORD-COMPLETE fail, each flipping its own named check while the false-positive guards survived"
exit 0
