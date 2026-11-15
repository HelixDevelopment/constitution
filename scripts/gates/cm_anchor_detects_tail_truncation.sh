#!/usr/bin/env bash
# cm_anchor_detects_tail_truncation.sh — CM-ANCHOR-DETECTS-TAIL-TRUNCATION (T328)
#
# ── What this gate asserts ───────────────────────────────────────────────────
# T328: "asserts chain-alone PASS **and** chain-plus-anchor DETECTED on the
#        truncated fixture, and asserts the lagging-anchor negative control
#        still PASSes so the gate cannot false-refuse a healthy chain."
#
# The PAIR of verdicts is the whole point. Tail truncation leaves behind a
# structurally VALID chain — contiguous sequence numbers, every prev_digest
# matching its predecessor — so chain-alone verification PASSes it, and that
# PASS is a MEASURED FACT, not a defect to be fixed. Only the external record of
# the expected head and entry count catches it. Asserting both halves together
# is therefore the evidence that the ANCHOR, and not the chain, carries this
# property; a gate that asserted only "DETECTED somewhere" could not tell which
# layer did the work.
#
# ── The false-refusal half is equally load-bearing ───────────────────────────
# A LAGGING anchor — one taken when the chain was shorter, with valid appends
# since — is HEALTHY. A head-digest-EQUALITY check collapses the lagging anchor
# and the truncated chain into one verdict, condemning healthy work; that is a
# §11.4.201(1) FAIL-bluff exactly as serious as a false pass, because it teaches
# people to ignore the verifier, which is how a real detection later gets waved
# through. So the negative control is a hard assertion here, not a comment.
#
# ── Checks (machine-readable `RESULT <id> <verdict>` lines) ──────────────────
#   golden-TRUE  (the property this gate exists to prove):
#     B1  truncated fixture: chain_alone   == PASS      (chain alone is blind)
#     B2  truncated fixture: chain_plus_anchor == DETECTED, seam exits 3
#     B3  both halves are present as DISTINCT fields and actually DIFFER here
#   golden-FALSE (a clean state MUST NOT make the gate fire — §11.4.201(1)):
#     B4  lagging-anchor negative control: BOTH halves PASS, seam exits 0
#     B5  golden-good (anchor == chain exactly): BOTH halves PASS, seam exits 0
#     B7  CARRIER: the seam's own usage text contains the literal `DETECTED`,
#         yet a structural read of the negative-control run yields PASS — the
#         token is not the thing (§11.4.201(7)(a)). A gate that grepped the
#         stream for `DETECTED` would fire on a healthy chain.
#   corpus honesty:
#     B6  the OBSERVED verdicts match the fixture corpus's own DECLARED intent
#         (`chain_alone_detects` / `anchor_detects` in intent.json), so a corpus
#         that silently stopped being a truncation cannot pass vacuously
#
# ── Control needles (§11.4.201(7)(b)) ────────────────────────────────────────
#   N1  the verdict reader is shown reading `DETECTED` through the SAME jq path
#       (out of the truncation report) BEFORE B4/B5 are allowed to report that
#       the healthy runs carry no DETECTED. A zero from a blind reader is
#       reported as INSTRUMENT BLIND (exit 4 REFUSE), never as a clean result.
#   N2  the runner is shown observing a NON-zero exit through the same
#       invocation path before any "exit was 0" claim is trusted.
#
# The shared needle helper for these gates is task T324
# (`constitution/scripts/gates/lib/chain_control_needle.sh`). It was ABSENT when
# this gate was written (measured), and §11.4.251 forbids landing a second
# near-identical copy, so both needles are INLINE here and are owed a migration
# onto that helper once its contract lands. This gate does NOT create that file.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_anchor_detects_tail_truncation.sh [--engine <dir>] [--quiet]
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS | 1 FAIL | 4 REFUSE (could not decide — never 0, §11.4.201(6))
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes ONLY under a private mktemp -d, removed on exit. Builds the engine's
#   seam with `go build -o <tmp>` and its fixture generator from a throwaway
#   module in that tmp dir which `replace`s the module path to --engine, so the
#   code under test is the real in-repo source and the repo is never written to.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, go, jq. Any absent -> REFUSE with the reason named.
#
# ── Paired §1.1 mutation ─────────────────────────────────────────────────────
#   cm_anchor_detects_tail_truncation_mutation_test.sh (task T332)
# ─────────────────────────────────────────────────────────────────────────────

set -u

GATE="CM-ANCHOR-DETECTS-TAIL-TRUNCATION"
quiet=""
engine=""

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
while [ $# -gt 0 ]; do
    case "$1" in
        --engine) engine="${2:-}"; shift 2 ;;
        --engine=*) engine="${1#--engine=}"; shift ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
        *) echo "$GATE: unknown argument: $1" >&2; exit 4 ;;
    esac
done

gates_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -z "$engine" ]; then
    engine="${gates_dir}/../../submodules/continuum"
fi

say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@" >&2; }

fail_count=0
result() {
    r_id="$1"; r_v="$2"; shift 2
    echo "RESULT $r_id $r_v"
    case "$r_v" in
        PASS) say "✅ PASS     $r_id — $*" ;;
        FAIL) warn "❌ FAIL     $r_id — $*"; fail_count=$((fail_count + 1)) ;;
        SKIP) warn "⚠️  SKIP     $r_id — $*" ;;
    esac
}

refuse() {
    echo "RESULT gate REFUSE"
    warn "🛑 REFUSE   ${GATE}: $*"
    warn "   The gate decided NOTHING. This is not a pass (§11.4.201(6))."
    exit 4
}

for tool in go jq; do
    command -v "$tool" >/dev/null 2>&1 || refuse "required tool '$tool' is not on PATH, so the mechanism could not be exercised"
done
[ -d "$engine" ] || refuse "engine root '$engine' does not exist"
[ -f "${engine}/go.mod" ] || refuse "engine root '$engine' carries no go.mod"
[ -f "${engine}/cmd/continuum-integrity/main.go" ] || refuse "the shell seam cmd/continuum-integrity is absent from '$engine'"
engine_abs=$(CDPATH= cd -- "$engine" && pwd) || refuse "engine root '$engine' could not be resolved"

tmp=$(mktemp -d 2>/dev/null) || refuse "could not create a temporary working directory"
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "──────────────────────────────────────────────────────────────────────"
echo "${GATE} — engine: ${engine_abs}"
echo "──────────────────────────────────────────────────────────────────────"

build_log="${tmp}/build.log"
( cd "$engine_abs" && timeout 600 go build -o "${tmp}/continuum-integrity" ./cmd/continuum-integrity ) >"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the shell seam could not be built (go build exit $rc)"; }

mkdir -p "${tmp}/harness"
cat > "${tmp}/harness/go.mod" <<EOF
module cmanchortruncationharness

go 1.22

require github.com/vasic-digital/continuum v0.0.0

replace github.com/vasic-digital/continuum => ${engine_abs}
EOF

cat > "${tmp}/harness/fixgen.go" <<'EOF'
package main

import (
	"fmt"
	"os"
	"strconv"

	fx "github.com/vasic-digital/continuum/test/fixtures/chain"
)

func main() {
	n, err := strconv.Atoi(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := fx.Generate(os.Args[1], n); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
EOF

( cd "${tmp}/harness" && timeout 600 go build -o "${tmp}/fixgen" . ) >>"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the fixture generator could not be built (go build exit $rc)"; }

# The corpus's negative control anchors at entry 6, so the golden-good chain
# must be longer than that for "the chain grew by valid appends" to be a real
# lagging anchor rather than an exact match.
CORPUS_N=12
"${tmp}/fixgen" "${tmp}/corpus" "$CORPUS_N" >>"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the fixture corpus could not be generated (exit $rc)"; }

TRUNC="${tmp}/corpus/attack_tail_truncation"
NEG="${tmp}/corpus/negative_control_lagging_anchor"
GOOD="${tmp}/corpus/golden_good"
for d in "$TRUNC" "$NEG" "$GOOD"; do
    [ -s "${d}/chain.jsonl" ] || refuse "the corpus member $(basename "$d") has no chain.jsonl"
    [ -s "${d}/anchor.json" ] || refuse "the corpus member $(basename "$d") has no anchor.json"
done

# The truncated chain must actually be SHORTER than what its anchor recorded,
# otherwise the fixture is not a truncation and every assertion below would
# pass vacuously.
trunc_lines=$(wc -l < "${TRUNC}/chain.jsonl"); trunc_lines=$(echo "$trunc_lines" | tr -d ' ')
trunc_anchored=$(jq -r '.entry_count' "${TRUNC}/anchor.json" 2>/dev/null)
neg_lines=$(wc -l < "${NEG}/chain.jsonl"); neg_lines=$(echo "$neg_lines" | tr -d ' ')
neg_anchored=$(jq -r '.entry_count' "${NEG}/anchor.json" 2>/dev/null)
if ! [ "$trunc_lines" -lt "$trunc_anchored" ] 2>/dev/null; then
    refuse "the truncation fixture is not truncated: chain holds ${trunc_lines} records and its anchor recorded ${trunc_anchored} — nothing below would be testing truncation"
fi
if ! [ "$neg_lines" -gt "$neg_anchored" ] 2>/dev/null; then
    refuse "the negative control is not a LAGGING anchor: chain holds ${neg_lines} records and its anchor recorded ${neg_anchored} — the false-positive guard would be vacuous"
fi
say "🔎 fixtures — truncation: ${trunc_lines} records vs anchor ${trunc_anchored}; lagging control: ${neg_lines} records vs anchor ${neg_anchored}"

CI="${tmp}/continuum-integrity"
run_seam() {
    rs_out="$1"; shift
    "$CI" "$@" >"$rs_out" 2>"${rs_out}.err"
    SEAM_RC=$?
}
jget() { jq -r "$1" "$2" 2>/dev/null; }

# --- N2 needle: is a NON-zero exit observable through this path at all? -----
run_seam "${tmp}/needle_exit.json" bogus verb
if [ "$SEAM_RC" -eq 0 ]; then
    refuse "control needle N2 failed: an invocation that MUST exit non-zero was observed exiting 0, so this runner cannot see exit codes and every exit-code claim below would be unfounded"
fi
say "🔎 needle N2 — non-zero exit observable through the seam path (saw $SEAM_RC)"

# --- the truncation run -----------------------------------------------------
run_seam "${tmp}/trunc.json" anchor verify --chain "${TRUNC}/chain.jsonl" --anchor "${TRUNC}/anchor.json"
t_rc=$SEAM_RC
t_ca=$(jget '.chain_alone.verdict' "${tmp}/trunc.json")
t_cpa=$(jget '.chain_plus_anchor.verdict' "${tmp}/trunc.json")

# --- N1 needle: can the verdict reader SEE a DETECTED through this jq path? -
# This must run BEFORE B4/B5 report that the healthy runs carry no DETECTED.
if [ "$t_cpa" != "DETECTED" ]; then
    # Not yet a refusal: it may be the finding B2 exists to make. Prove the
    # reader is not blind by reading a field that is always populated.
    probe_field=$(jget '.command' "${tmp}/trunc.json")
    if [ "$probe_field" != "anchor verify" ]; then
        warn "$(cat "${tmp}/trunc.json.err")"
        refuse "control needle N1 failed: the verdict reader could not read even the always-present .command field out of the seam's report (got '${probe_field}'), so it is blind and no verdict below can be trusted"
    fi
    say "🔎 needle N1 — the verdict reader is live (read .command='${probe_field}'); the absent DETECTED below is a FINDING, not blindness"
else
    say "🔎 needle N1 — the verdict reader reads 'DETECTED' out of the truncation report through the same jq path used for the healthy runs"
fi

if [ "$t_ca" = "PASS" ]; then
    result B1_truncation_chain_alone_pass PASS "chain-alone verification PASSes the truncated chain — the measured fact that a truncated prefix is still a structurally valid chain (this PASS is not a defect)"
else
    result B1_truncation_chain_alone_pass FAIL "chain-alone reported '${t_ca}' on the truncated fixture; expected PASS, because truncation leaves a valid chain and chain-alone cannot see it"
fi

if [ "$t_cpa" = "DETECTED" ] && [ "$t_rc" -eq 3 ]; then
    result B2_truncation_chain_plus_anchor_detected PASS "chain-plus-anchor DETECTED the truncation and the seam exits 3: $(jget '.chain_plus_anchor.reason' "${tmp}/trunc.json")"
else
    result B2_truncation_chain_plus_anchor_detected FAIL "chain-plus-anchor reported '${t_cpa}' with seam exit ${t_rc}; expected DETECTED / 3 — the anchor comparison is the ONLY layer that catches truncation, so this is the property failing"
fi

has_ca=$(jq -e 'has("chain_alone")' "${tmp}/trunc.json" >/dev/null 2>&1; echo $?)
has_cpa=$(jq -e 'has("chain_plus_anchor")' "${tmp}/trunc.json" >/dev/null 2>&1; echo $?)
if [ "$has_ca" -eq 0 ] && [ "$has_cpa" -eq 0 ] && [ "$t_ca" != "$t_cpa" ]; then
    result B3_two_distinct_results PASS "both halves are reported as distinct fields and they differ here (chain_alone=${t_ca}, chain_plus_anchor=${t_cpa}) — the pair is the evidence that the ANCHOR carries this property"
else
    result B3_two_distinct_results FAIL "the two halves are not separately reported or do not differ: has_chain_alone=${has_ca} has_chain_plus_anchor=${has_cpa} chain_alone='${t_ca}' chain_plus_anchor='${t_cpa}'"
fi

# --- the LAGGING-ANCHOR negative control (false-positive guard) -------------
run_seam "${tmp}/neg.json" anchor verify --chain "${NEG}/chain.jsonl" --anchor "${NEG}/anchor.json"
n_rc=$SEAM_RC
n_ca=$(jget '.chain_alone.verdict' "${tmp}/neg.json")
n_cpa=$(jget '.chain_plus_anchor.verdict' "${tmp}/neg.json")
if [ "$n_ca" = "PASS" ] && [ "$n_cpa" = "PASS" ] && [ "$n_rc" -eq 0 ]; then
    result B4_lagging_anchor_negative_control PASS "a chain that merely grew by valid appends since its anchor verifies clean both ways (exit 0) — the gate cannot false-refuse a healthy chain (§11.4.201(1))"
else
    result B4_lagging_anchor_negative_control FAIL "a HEALTHY lagging-anchor chain was refused: chain_alone='${n_ca}' chain_plus_anchor='${n_cpa}' exit=${n_rc} (expected PASS/PASS/0). A head-digest equality check produces exactly this FAIL-bluff."
fi

# --- golden-good: anchor and chain match exactly ---------------------------
run_seam "${tmp}/good.json" anchor verify --chain "${GOOD}/chain.jsonl" --anchor "${GOOD}/anchor.json"
g_rc=$SEAM_RC
g_ca=$(jget '.chain_alone.verdict' "${tmp}/good.json")
g_cpa=$(jget '.chain_plus_anchor.verdict' "${tmp}/good.json")
if [ "$g_ca" = "PASS" ] && [ "$g_cpa" = "PASS" ] && [ "$g_rc" -eq 0 ]; then
    result B5_golden_good_clean PASS "the untampered chain with its exact anchor verifies clean both ways (exit 0)"
else
    result B5_golden_good_clean FAIL "the untampered chain was not clean: chain_alone='${g_ca}' chain_plus_anchor='${g_cpa}' exit=${g_rc}"
fi

# --- B6: observed verdicts vs the corpus's own DECLARED intent -------------
t_decl_chain=$(jq -r '.chain_alone_detects' "${TRUNC}/intent.json" 2>/dev/null)
t_decl_anchor=$(jq -r '.anchor_detects' "${TRUNC}/intent.json" 2>/dev/null)
n_decl_anchor=$(jq -r '.anchor_detects' "${NEG}/intent.json" 2>/dev/null)
b6_ok=1
[ "$t_decl_chain" = "false" ] || b6_ok=0
[ "$t_decl_anchor" = "true" ] || b6_ok=0
[ "$n_decl_anchor" = "false" ] || b6_ok=0
# and the observation must agree with the declaration
[ "$t_ca" = "PASS" ] || b6_ok=0
[ "$t_cpa" = "DETECTED" ] || b6_ok=0
[ "$n_cpa" = "PASS" ] || b6_ok=0
if [ "$b6_ok" -eq 1 ]; then
    result B6_observed_matches_declared_intent PASS "the corpus declares truncation as chain_alone_detects=false/anchor_detects=true and the negative control as anchor_detects=false, and every observation agrees — the fixtures cannot pass vacuously"
else
    result B6_observed_matches_declared_intent FAIL "observation and declared intent disagree: truncation declared chain_alone_detects=${t_decl_chain} anchor_detects=${t_decl_anchor} (observed ${t_ca}/${t_cpa}); negative control declared anchor_detects=${n_decl_anchor} (observed ${n_cpa})"
fi

# --- B7: the CARRIER guard (§11.4.201(7)(a)) -------------------------------
"$CI" >"${tmp}/usage.out" 2>"${tmp}/usage.err"
usage_hits=$(cat "${tmp}/usage.out" "${tmp}/usage.err" | grep -c 'DETECTED')
rc=$?
if [ "$rc" -ne 0 ] || [ "$usage_hits" -lt 1 ]; then
    result B7_carrier_token_is_not_the_thing SKIP "the seam's usage text no longer carries the literal 'DETECTED', so this carrier fixture would prove nothing (instrument note, not a finding)"
else
    neg_stream_hits=$(cat "${tmp}/neg.json" "${tmp}/neg.json.err" | grep -c 'DETECTED')
    if [ "$n_cpa" = "PASS" ]; then
        result B7_carrier_token_is_not_the_thing PASS "the seam's own usage text carries the literal 'DETECTED' ${usage_hits}× while the structural read of the healthy lagging run yields PASS (its stream carries the literal ${neg_stream_hits}×) — this gate reads the field, not the token (§11.4.201(7)(a))"
    else
        result B7_carrier_token_is_not_the_thing FAIL "the carrier check cannot be evaluated because the healthy lagging run did not read PASS (got '${n_cpa}') — see B4"
    fi
fi

echo "──────────────────────────────────────────────────────────────────────"
if [ "$fail_count" -ne 0 ]; then
    echo "❌ ${GATE}: FAIL — ${fail_count} check(s) decided against the mechanism"
    exit 1
fi
echo "✅ ${GATE}: PASS — the anchor DETECTS tail truncation that chain-alone PASSes, and the lagging-anchor negative control still verifies clean"
exit 0
