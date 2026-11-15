#!/bin/sh
# cm_chain_integrity_detects_alteration.sh — CM-CHAIN-INTEGRITY-DETECTS-ALTERATION
# gate (T326).
#
# ── What this gate asserts ───────────────────────────────────────────────────
# It runs the T301 attack corpus through the SHIPPED verifier and asserts what
# the verifier actually returns for each fixture:
#
#   CHAIN-A0  the shipped verifier builds and the corpus generates  (precondition)
#   CHAIN-A1  MUTATION  is DETECTED
#   CHAIN-A2  DELETION  is DETECTED
#   CHAIN-A3  REORDER   is DETECTED
#   CHAIN-A4  a chain that cannot be WALKED returns REFUSE, never PASS (FR-030)
#   CHAIN-A5  an ABSENT store returns REFUSE, never PASS
#   CHAIN-A6  a HEALTHY chain still PASSes                (false-positive guard)
#   CHAIN-A7  the two DOCUMENTED-LIMIT attacks PASS chain-alone
#
# ── Why A6 and A7 are not padding ────────────────────────────────────────────
# A verifier that refused everything would satisfy A1-A5 perfectly and be
# useless. §11.4.201(1): a false refusal is a FAIL-bluff exactly as serious as
# a false pass. A6 is the direct guard.
#
# A7 asserts the two rows the chain alone genuinely CANNOT see — tail
# truncation, and deletion followed by a full re-chain. Both leave a chain that
# is internally perfect: contiguous sequence numbers, every prev_digest
# matching its predecessor. A chain can only ever prove internal consistency;
# it cannot know what it SHOULD have contained. Only the anchor carries that,
# which is why the security lives in the anchor and the window of forgeability
# equals the anchor interval.
#
# So A7 asserts these PASS. Asserting DETECTED would be asserting a falsehood
# and would push someone to "fix" a documented structural limit; asserting
# nothing would let a verifier that refuses everything slip through. The
# anchor-side detection of these two rows is T328's gate, not this one.
#
# ── Why it RUNS rather than greps ────────────────────────────────────────────
# §11.4.227(A): a prose carrier never counts as an implementation, and
# §11.4.108: source-present is not runtime-active. Every verdict below is read
# from a real execution of the built verifier over a real fixture.
#
# ── Reading the verdict STRUCTURALLY ─────────────────────────────────────────
# The verifier's JSON `reason` string quotes verdict words ("chain_alone is
# DETECTED: ..."), so a substring search for DETECTED would match a CARRIER as
# readily as the field (§11.4.201(7)(a)). Verdicts are therefore extracted by
# OBJECT — the verdict belonging to `chain_alone` — and an unreadable
# extraction is reported BLIND, never as a verdict that failed to match.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_chain_integrity_detects_alteration.sh [--module <continuum-root>] [--n N]
#     --n N   corpus size (default 12; structural fixture, not a benchmark)
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   CN-VERDICT / CN-SUMMARY lines. Exit 0 only if nothing FAILed or was BLIND.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Read-only w.r.t. the repository: the verifier binary, the generated corpus
#   and the torn fixture all live inside a mktemp -d removed on exit.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, grep, awk, mktemp, head, tail, cut, wc; `go` (SKIP with reason
#   if absent — an unexecuted verifier has demonstrated nothing).

set -u

GATE_ID=CM-CHAIN-INTEGRITY-DETECTS-ALTERATION
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/chain_control_needle.sh"

MODULE="$SELF_DIR/../../submodules/continuum"
CORPUS_N=12
while [ $# -gt 0 ]; do
    case $1 in
        --module) MODULE=$2; shift 2 ;;
        --n)      CORPUS_N=$2; shift 2 ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

cn_reset
ALL_IDS='CHAIN-A1-MUTATION-DETECTED CHAIN-A2-DELETION-DETECTED CHAIN-A3-REORDER-DETECTED
CHAIN-A4-UNWALKABLE-REFUSES CHAIN-A5-ABSENT-STORE-REFUSES CHAIN-A6-HEALTHY-PASSES
CHAIN-A7-DOCUMENTED-LIMITS-PASS-CHAIN-ALONE'

skip_all() { for _i in $ALL_IDS; do cn_skip "$_i" "$1"; done; }
blind_all() { for _i in $ALL_IDS; do cn_blind "$_i" "$1"; done; }

if [ ! -d "$MODULE" ]; then
    cn_blind CHAIN-A0-VERIFIER-BUILDS "module root not found: $MODULE"
    blind_all 'the verifier could not be located, so nothing was observed'
    cn_summary "$GATE_ID"; exit 1
fi
MODULE=$(CDPATH= cd -- "$MODULE" && pwd)

if ! command -v go >/dev/null 2>&1; then
    cn_skip CHAIN-A0-VERIFIER-BUILDS 'go toolchain absent'
    skip_all 'go toolchain absent: the shipped verifier was NOT executed, so its behaviour was not observed'
    cn_summary "$GATE_ID"; exit $?
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_chain_integrity.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

# ── CHAIN-A0 — build the shipped verifier, generate the shipped corpus ───────
BIN="$TMP/continuum-integrity"
( cd "$MODULE" && go build -o "$BIN" ./cmd/continuum-integrity ) > "$TMP/build.log" 2>&1
BUILD_RC=$?

# The corpus generator is the module's OWN package: this gate builds no second
# corpus of its own, so there is no private fixture that could drift away from
# the contract the module tests against (§11.4.251).
GEN="$TMP/gen"
mkdir -p "$GEN"
cat > "$GEN/go.mod" <<EOF
module chaincorpusgen

go 1.22

require github.com/vasic-digital/continuum v0.0.0

replace github.com/vasic-digital/continuum => $MODULE
EOF
cat > "$GEN/main.go" <<'GEN_EOF'
package main

import (
	"fmt"
	"os"
	"strconv"

	fx "github.com/vasic-digital/continuum/test/fixtures/chain"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: gen <outdir> <n>")
		os.Exit(2)
	}
	n, err := strconv.Atoi(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, "n:", err)
		os.Exit(2)
	}
	if err := fx.Generate(os.Args[1], n); err != nil {
		fmt.Fprintln(os.Stderr, "generate:", err)
		os.Exit(1)
	}
	fmt.Println("CORPUS_OK")
}
GEN_EOF

CORPUS="$TMP/corpus"
( cd "$GEN" && go run . "$CORPUS" "$CORPUS_N" ) > "$TMP/gen.log" 2>&1
GEN_RC=$?

if [ "$BUILD_RC" -ne 0 ] || [ "$GEN_RC" -ne 0 ]; then
    cn_blind CHAIN-A0-VERIFIER-BUILDS \
        "verifier build rc=$BUILD_RC, corpus generation rc=$GEN_RC — nothing was executed. build: $(head -2 "$TMP/build.log" | tr '\n' ' ') gen: $(head -2 "$TMP/gen.log" | tr '\n' ' ')"
    blind_all 'the verifier or corpus could not be produced, so no verdict was observed'
    cn_summary "$GATE_ID"; exit 1
fi
cn_pass CHAIN-A0-VERIFIER-BUILDS "shipped verifier built and the $CORPUS_N-record attack corpus generated from the module's own fixture package"

# ── Structural verdict extraction ────────────────────────────────────────────
# Prints the verdict belonging to a NAMED JSON object, so the verdict words
# quoted inside `reason` strings cannot be mistaken for the field.
_verdict_of_obj() { # <json-file> <object-name>
    awk -v key="\"$2\": {" '
        index($0, key) { inobj = 1; next }
        inobj {
            if (match($0, /"verdict"[ ]*:[ ]*"[A-Z]+"/)) {
                v = substr($0, RSTART, RLENGTH)
                sub(/.*"verdict"[ ]*:[ ]*"/, "", v)
                sub(/"$/, "", v)
                print v
                exit
            }
        }
    ' "$1"
}

# chain_alone's verdict, with a control needle on the reader itself: for
# `chain verify`, chain_plus_anchor is ALWAYS present and ALWAYS SKIP. If the
# reader cannot see that known-present field, an empty chain_alone reading is
# the reader being blind — not the verifier being silent (§11.4.201(7)(b)).
chain_alone_verdict() { # <json-file> -> verdict, or BLIND:<why>
    _needle=$(_verdict_of_obj "$1" chain_plus_anchor)
    if [ -z "$_needle" ]; then
        printf 'BLIND:control needle (chain_plus_anchor.verdict, always present for `chain verify`) unreadable — the JSON reader cannot see through this path\n'
        return 0
    fi
    _v=$(_verdict_of_obj "$1" chain_alone)
    if [ -z "$_v" ]; then
        printf 'BLIND:chain_alone.verdict unreadable although the control needle read %s\n' "$_needle"
        return 0
    fi
    printf '%s\n' "$_v"
}

# assert_fixture <id> <chain-path> <expected> <msg-ok> <msg-bad>
assert_fixture() {
    _id=$1; _path=$2; _want=$3; _ok=$4; _bad=$5
    _out="$TMP/$(printf '%s' "$_id" | tr -c 'A-Za-z0-9' '_').json"
    "$BIN" chain verify --chain "$_path" > "$_out" 2>"$TMP/stderr.log"
    _rc=$?
    _got=$(chain_alone_verdict "$_out")
    case $_got in
        BLIND:*) cn_blind "$_id" "${_got#BLIND:} (verifier rc=$_rc)" ; return ;;
    esac
    if [ "$_got" = "$_want" ]; then
        cn_pass "$_id" "$_ok (chain_alone=$_got, verifier rc=$_rc)"
    else
        cn_fail "$_id" "$_bad — expected chain_alone=$_want, got $_got (verifier rc=$_rc)"
    fi
}

# ── A1-A3 — the three attacks a chain alone genuinely detects ────────────────
assert_fixture CHAIN-A1-MUTATION-DETECTED "$CORPUS/attack_mutation/chain.jsonl" DETECTED \
    'an altered record breaks its successor'"'"'s prev_digest and is DETECTED (FR-009)' \
    'a MUTATED record was not detected: records can be rewritten without the chain noticing'

assert_fixture CHAIN-A2-DELETION-DETECTED "$CORPUS/attack_deletion/chain.jsonl" DETECTED \
    'a deleted record leaves a broken link and is DETECTED (FR-029)' \
    'a DELETED record was not detected: records can be removed without the chain noticing'

assert_fixture CHAIN-A3-REORDER-DETECTED "$CORPUS/attack_reorder/chain.jsonl" DETECTED \
    'reordered records break the walk and are DETECTED (FR-029)' \
    'a REORDERED chain was not detected: the total order is not actually enforced'

# ── A4 — an unwalkable chain REFUSES (FR-030) ────────────────────────────────
# The fixture truncates the LAST record so it is no longer exactly one
# canonical record. The walk cannot complete, so it has decided nothing, and
# "undecided" reported as "intact" is the precise failure FR-030 forbids.
GOOD="$CORPUS/golden_good/chain.jsonl"
TORN="$TMP/torn.jsonl"
GOOD_LINES=$(wc -l < "$GOOD")
if [ "$GOOD_LINES" -lt 2 ]; then
    cn_blind CHAIN-A4-UNWALKABLE-REFUSES "golden-good corpus has only $GOOD_LINES line(s); cannot build a torn fixture"
else
    head -n "$((GOOD_LINES - 1))" "$GOOD" > "$TORN"
    tail -n 1 "$GOOD" | cut -c1-40 >> "$TORN"
    assert_fixture CHAIN-A4-UNWALKABLE-REFUSES "$TORN" REFUSE \
        'a chain that cannot be walked returns REFUSE, not PASS and not a silent zero (FR-030)' \
        'an UNWALKABLE chain did not REFUSE: an undecided walk is being reported as a decided one'
fi

# ── A5 — an absent store REFUSES ─────────────────────────────────────────────
# Wholesale deletion of the store is the loudest tampering there is; reporting
# it as intact because there was nothing left to find would be the worst
# possible false pass.
assert_fixture CHAIN-A5-ABSENT-STORE-REFUSES "$TMP/no_such_chain.jsonl" REFUSE \
    'an ABSENT chain store returns REFUSE: the walk never started, so nothing was verified' \
    'an ABSENT chain store did not REFUSE: wholesale deletion would be reported as clean'

# ── A6 — the false-positive guard ────────────────────────────────────────────
assert_fixture CHAIN-A6-HEALTHY-PASSES "$GOOD" PASS \
    'a healthy chain still PASSes: the verifier does not refuse everything' \
    'a HEALTHY chain did not PASS — a false refusal, and per §11.4.201(1) as serious as a false pass'

# ── A7 — the documented limits, asserted as limits ───────────────────────────
LIMITS_OK=1
LIMITS_DETAIL=''
for f in attack_tail_truncation attack_delete_rechain; do
    o="$TMP/limit_$f.json"
    "$BIN" chain verify --chain "$CORPUS/$f/chain.jsonl" > "$o" 2>/dev/null
    rcf=$?
    v=$(chain_alone_verdict "$o")
    LIMITS_DETAIL="$LIMITS_DETAIL $f=$v(rc=$rcf)"
    case $v in
        PASS) ;;
        BLIND:*) LIMITS_OK=2 ;;
        *) LIMITS_OK=0 ;;
    esac
done
if [ "$LIMITS_OK" = 1 ]; then
    cn_pass CHAIN-A7-DOCUMENTED-LIMITS-PASS-CHAIN-ALONE \
        "tail truncation and deletion+full-re-chain PASS chain-alone, as they must: both leave an internally perfect chain, and only the anchor knows what the chain SHOULD have contained (anchor-side detection is T328's gate) —$LIMITS_DETAIL"
elif [ "$LIMITS_OK" = 2 ]; then
    cn_blind CHAIN-A7-DOCUMENTED-LIMITS-PASS-CHAIN-ALONE "verdict unreadable for a documented-limit fixture —$LIMITS_DETAIL"
else
    cn_fail CHAIN-A7-DOCUMENTED-LIMITS-PASS-CHAIN-ALONE \
        "a documented-limit fixture did not PASS chain-alone —$LIMITS_DETAIL. Either the corpus no longer encodes the measured limit, or the verifier has started refusing chains it cannot fault, which would make every PASS meaningless"
fi

cn_summary "$GATE_ID"
exit $?
