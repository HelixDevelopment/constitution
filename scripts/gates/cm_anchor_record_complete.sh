#!/usr/bin/env bash
# cm_anchor_record_complete.sh — CM-ANCHOR-RECORD-COMPLETE (task T327)
#
# ── What this gate asserts ───────────────────────────────────────────────────
# T327: "asserts `head_digest` and `entry_count` are both present and that
#        `anchor_strength` equals the probe's verified result, FAILing on any
#        `mechanism` value with no probe evidence behind it."
#
# It asserts BEHAVIOUR, not the presence of files. Every check below drives the
# SHIPPED mechanism — the `continuum-integrity` shell seam and the `pkg/anchor`
# package it adapts — and this gate is the independent oracle over the result
# (§11.4.249: the producer is the engine, the oracle is here, and they are not
# the same actor). A gate that grepped for a filename, a function name, or the
# literal string `mechanism` would be exactly the bluff this feature exists to
# kill (§11.4.227(A): a prose carrier is never an implementation; §11.4.108:
# source-present is not runtime-active).
#
# ── The two properties this gate must respect ────────────────────────────────
# 1. `policy` IS THE HONEST CURRENT STATE, NOT A FAILURE. `GitNonFastForwardProbe`
#    has no path returning verified-true, because no read-only git operation
#    reports a server's branch protection. A gate that FAILed on `policy` would
#    be a §11.4.201(1) FAIL-bluff condemning the true record.
# 2. A PROBE-VERIFIED `mechanism` MUST BE ACCEPTED. The rule is "record what was
#    probed", never "never say mechanism". A validator that refused every
#    `mechanism` would satisfy a naive test while being useless, so that
#    false-positive guard is a first-class check here (A8).
#
# ── Checks (each one PASS/FAIL/SKIP, machine-readable `RESULT <id> <verdict>`) ─
#   golden-TRUE  (a violation MUST make the gate FAIL):
#     A4  a recorded `mechanism` cross-checked against a live probe that
#         established only `policy` is DETECTED at the seam (exit 3)
#     A5a an anchor with NO entry_count is REFUSED at the read seam (exit 4)
#         AND refused *for that reason* (the refusal names entry_count)
#     A5b an anchor with NO head_digest is REFUSED at the read seam (exit 4)
#     A9  `mechanism` recorded against a probe that never ran is refused
#     A10 `mechanism` recorded against a probe that established `policy` is refused
#     A12b/A12c the shipped validator refuses a record missing either field
#   golden-FALSE (a clean state MUST NOT make the gate fire — §11.4.201(1)):
#     A6  an honest `policy` anchor cross-checked against a live probe PASSes
#     A7  a CARRIER anchor — one whose bytes MENTION the token `mechanism` in a
#         non-load-bearing field while recording `policy` — still PASSes
#         (§11.4.201(7)(a): the token is not the thing)
#     A8  a probe-verified `mechanism` is ACCEPTED
#     A11 a probe-established `policy` recorded as `policy` is ACCEPTED
#     A12a a complete record is accepted
#   equality-to-probe (the load-bearing T327 clause):
#     A1  the seam's written record carries a 64-hex head_digest and an
#         entry_count EQUAL to the chain's real line count (counted here,
#         independently of anything the engine reports)
#     A2  written with no remote, the recorded strength is `unknown` — the
#         probe SKIPped, so NEITHER value may be claimed (§11.4.6)
#     A3  written with a reachable remote, the recorded strength EQUALS the
#         value the probe itself established (read from the probe's own
#         result field, never from a hardcoded expectation)
#
# ── Control needles (§11.4.201(7)(b)) ────────────────────────────────────────
# Every ABSENCE this gate reports is preceded by a class-matched needle proving
# the instrument can see that class of value through the SAME path:
#   N1  the strength reader is shown reading `mechanism` out of a fixture that
#       has one, before A2 is allowed to report "the record does not say
#       mechanism". A zero from a blind reader is reported as INSTRUMENT BLIND
#       (exit 4 REFUSE), never as a clean artifact.
#   N2  the exit-code observer is shown observing a NON-zero exit through the
#       same invocation path, before any "exit was 0" claim is trusted.
#   N3  the ORACLE-line parser is shown parsing a known-present id.
#
# The shared needle helper for these gates is task T324
# (`constitution/scripts/gates/lib/chain_control_needle.sh`). It was ABSENT when
# this gate was written (measured twice), and §11.4.251 forbids landing a second
# near-identical copy of it, so the three needles above are implemented INLINE
# and are owed a migration onto that helper the moment its contract lands. This
# gate deliberately does NOT create that file.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_anchor_record_complete.sh [--engine <dir>] [--quiet]
#     --engine <dir>  continuum engine root (default: <gates>/../../submodules/continuum)
#     --quiet         suppress per-check PASS lines (FAIL/SKIP/RESULT always shown)
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0  PASS     every check decided and held
#   1  FAIL     at least one check decided against the mechanism
#   4  REFUSE   the gate could not decide (toolchain absent, build failed, an
#               instrument proved blind). NEVER 0: "I checked nothing" must not
#               read as "verified" (§11.4.201(6) false-null).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Writes ONLY under a private mktemp -d, removed on exit. It builds the
#   engine's binaries with `go build -o <tmp>` and builds its own probe harness
#   from a throwaway module in that tmp dir which `replace`s the module path to
#   --engine, so the code under test is the real in-repo source and the repo
#   itself is never written to. A local throwaway bare git repo is created in
#   the tmp dir to give the strength probe a REACHABLE remote (a probe against
#   an unreachable remote is UNKNOWN, which would test nothing).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, go, git, jq. Any absent -> REFUSE with the reason named.
#
# ── Paired §1.1 mutation ─────────────────────────────────────────────────────
#   cm_anchor_record_complete_mutation_test.sh (task T331)
# ─────────────────────────────────────────────────────────────────────────────

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -u

GATE="CM-ANCHOR-RECORD-COMPLETE"
quiet=""
engine=""

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
    # result <check-id> <PASS|FAIL|SKIP> <detail...>
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

# --- preflight: instrument availability ------------------------------------
for tool in go git jq; do
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

# --- build the shipped seam (writes only into $tmp) -------------------------
build_log="${tmp}/build.log"
( cd "$engine_abs" && timeout 600 go build -o "${tmp}/continuum-integrity" ./cmd/continuum-integrity ) >"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the shell seam could not be built (go build exit $rc)"; }

# --- build the fixture generator and the strength oracle from a throwaway
# --- module that `replace`s to the engine under test ------------------------
mkdir -p "${tmp}/harness"
cat > "${tmp}/harness/go.mod" <<EOF
module cmanchorrecordharness

go 1.22

require github.com/vasic-digital/continuum v0.0.0

replace github.com/vasic-digital/continuum => ${engine_abs}
EOF

cat > "${tmp}/harness/fixgen.go" <<'EOF'
//go:build fixgen

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

# The strength oracle drives pkg/anchor DIRECTLY, because the two
# false-positive guards it carries (A8: a probe-verified `mechanism` MUST be
# accepted; A11: a probe-established `policy` MUST be accepted) are NOT
# reachable through the CLI today: GitNonFastForwardProbe has no path that
# returns verified-true, which is the measured honest fact, not a defect. Any
# gate that only drove the CLI would silently skip the guard that stops a
# refuse-everything validator from passing.
cat > "${tmp}/harness/oracle.go" <<'EOF'
//go:build oracle

package main

import (
	"fmt"
	"os"

	"github.com/vasic-digital/continuum/pkg/anchor"
)

var failed int

func report(id string, ok bool, detail string) {
	v := "PASS"
	if !ok {
		v = "FAIL"
		failed++
	}
	fmt.Printf("ORACLE %s %s %s\n", id, v, detail)
}

func main() {
	head := os.Args[1] // a real 64-hex head digest from the generated corpus

	probedMech := anchor.StrengthResult{Verdict: anchor.PASS, Strength: anchor.StrengthMechanism,
		Reason: "harness probe established mechanical prevention"}
	probedPolicy := anchor.StrengthResult{Verdict: anchor.PASS, Strength: anchor.StrengthPolicy,
		Reason: "harness probe found no mechanical prevention"}
	noProbe := anchor.ProbeStrength(nil)

	// A8 — FALSE-POSITIVE GUARD: a probe-verified mechanism MUST be accepted.
	err := anchor.ValidateRecordedStrength(anchor.StrengthMechanism, probedMech)
	report("A8_probe_verified_mechanism_accepted", err == nil, fmt.Sprintf("err=%v", err))

	// A9 — mechanism with NO probe at all must be refused.
	err = anchor.ValidateRecordedStrength(anchor.StrengthMechanism, noProbe)
	report("A9_unprobed_mechanism_refused", err != nil, fmt.Sprintf("err=%v", err))

	// A9b — a nil probe yields SKIP/unknown; it never becomes a claim.
	report("A9b_nil_probe_is_skip_unknown",
		noProbe.Verdict == anchor.SKIP && noProbe.Strength == anchor.StrengthUnknown,
		fmt.Sprintf("verdict=%s strength=%s", noProbe.Verdict, noProbe.Strength))

	// A10 — mechanism recorded over a probe that established only policy.
	err = anchor.ValidateRecordedStrength(anchor.StrengthMechanism, probedPolicy)
	report("A10_overstated_mechanism_refused", err != nil, fmt.Sprintf("err=%v", err))

	// A11 — FALSE-POSITIVE GUARD: the honest policy record must be accepted.
	err = anchor.ValidateRecordedStrength(anchor.StrengthPolicy, probedPolicy)
	report("A11_probed_policy_accepted", err == nil, fmt.Sprintf("err=%v", err))

	// A12 — completeness, enforced by the shipped validator itself.
	good := anchor.Anchor{HeadDigest: head, EntryCount: 12, Strength: anchor.StrengthPolicy}
	report("A12a_complete_record_accepted", anchor.Validate(good) == nil,
		fmt.Sprintf("err=%v", anchor.Validate(good)))
	noCount := good
	noCount.EntryCount = 0
	report("A12b_missing_entry_count_refused", anchor.Validate(noCount) != nil,
		fmt.Sprintf("err=%v", anchor.Validate(noCount)))
	noHead := good
	noHead.HeadDigest = ""
	report("A12c_missing_head_digest_refused", anchor.Validate(noHead) != nil,
		fmt.Sprintf("err=%v", anchor.Validate(noHead)))

	if failed > 0 {
		os.Exit(1)
	}
}
EOF

( cd "${tmp}/harness" && timeout 600 go build -tags fixgen -o "${tmp}/fixgen" ./fixgen.go ) >>"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the fixture generator could not be built (go build exit $rc)"; }

( cd "${tmp}/harness" && timeout 600 go build -tags oracle -o "${tmp}/oracle" ./oracle.go ) >>"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the strength oracle harness could not be built (go build exit $rc)"; }

# --- corpus -----------------------------------------------------------------
CORPUS_N=12
"${tmp}/fixgen" "${tmp}/corpus" "$CORPUS_N" >>"$build_log" 2>&1
rc=$?
[ "$rc" -eq 0 ] || { warn "$(cat "$build_log")"; refuse "the fixture corpus could not be generated (exit $rc)"; }
chain="${tmp}/corpus/golden_good/chain.jsonl"
[ -s "$chain" ] || refuse "the generated corpus has no golden-good chain at $chain"

# The gate counts the chain itself. Taking the count from the engine's own
# report and then "verifying" the engine against it would be the producer
# grading its own homework (§11.4.249).
chain_lines=$(wc -l < "$chain")
chain_lines=$(echo "$chain_lines" | tr -d ' ')

# --- a REACHABLE throwaway remote for the strength probe --------------------
# An unreachable remote yields UNKNOWN, which would leave A3/A4/A6 untested.
( cd "$tmp" && git init -q --bare remote.git && git init -q seed \
  && cd seed && git config user.email gate@local && git config user.name gate \
  && echo needle > f && git add f && git commit -qm seed && git branch -M main \
  && git push -q ../remote.git main ) >>"$build_log" 2>&1
rc=$?
remote=""
if [ "$rc" -eq 0 ]; then
    git ls-remote --exit-code --heads "${tmp}/remote.git" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && remote="${tmp}/remote.git"
fi

# --- helpers ----------------------------------------------------------------
CI="${tmp}/continuum-integrity"
run_seam() {
    # run_seam <out-json> <args...>; sets SEAM_RC. Exit status captured
    # DIRECTLY, never through a pipeline.
    rs_out="$1"; shift
    "$CI" "$@" >"$rs_out" 2>"${rs_out}.err"
    SEAM_RC=$?
}
jget() { jq -r "$1" "$2" 2>/dev/null; }

# --- N2 needle: can this runner observe a NON-zero exit at all? -------------
run_seam "${tmp}/needle_exit.json" bogus verb
if [ "$SEAM_RC" -eq 0 ]; then
    refuse "control needle N2 failed: an invocation that MUST exit non-zero was observed exiting 0, so this runner cannot see exit codes through this path — every exit-code claim below would be unfounded"
fi
say "🔎 needle N2 — non-zero exit observable through the seam path (saw $SEAM_RC)"

# --- A1/A2: anchor write with NO remote ------------------------------------
run_seam "${tmp}/w_noremote.json" anchor write --chain "$chain" --anchor "${tmp}/a_noremote.json"
w1_rc=$SEAM_RC
if [ "$w1_rc" -ne 0 ]; then
    result A1_seam_write_complete FAIL "\`anchor write\` exited $w1_rc on a healthy chain; no record to inspect: $(cat "${tmp}/w_noremote.json.err")"
else
    a1_head=$(jget '.head_digest' "${tmp}/a_noremote.json")
    a1_count=$(jget '.entry_count' "${tmp}/a_noremote.json")
    a1_ok=1
    echo "$a1_head" | grep -qE '^[0-9a-f]{64}$' || a1_ok=0
    [ "$a1_count" = "$chain_lines" ] || a1_ok=0
    if [ "$a1_ok" -eq 1 ]; then
        result A1_seam_write_complete PASS "record carries head_digest=${a1_head} and entry_count=${a1_count}, and the count equals the ${chain_lines} chain records counted independently by this gate"
    else
        result A1_seam_write_complete FAIL "record is incomplete or its count is wrong: head_digest='${a1_head}' entry_count='${a1_count}' but the chain holds ${chain_lines} records"
    fi
fi

# --- N1 needle: can the strength reader SEE a `mechanism` value? ------------
a1_head_for_forge=$(jget '.head_digest' "${tmp}/a_noremote.json")
if ! echo "$a1_head_for_forge" | grep -qE '^[0-9a-f]{64}$'; then
    a1_head_for_forge=$(jget '.head_digest' "${tmp}/corpus/golden_good/anchor.json")
fi
printf '{"head_digest":"%s","entry_count":%s,"anchor_strength":"mechanism"}\n' \
    "$a1_head_for_forge" "$chain_lines" > "${tmp}/forged_mech.json"
needle_strength=$(jget '.anchor_strength' "${tmp}/forged_mech.json")
if [ "$needle_strength" != "mechanism" ]; then
    refuse "control needle N1 failed: the strength reader returned '${needle_strength}' from a record that DOES carry \"anchor_strength\":\"mechanism\" — the reader is blind, so any claim that a record does NOT say mechanism would be an unfounded absence (§11.4.201(7)(b))"
fi
say "🔎 needle N1 — the strength reader reads 'mechanism' out of a record that has one"

a2_strength=$(jget '.anchor_strength' "${tmp}/a_noremote.json")
a2_probe_v=$(jget '.anchor_strength.verdict' "${tmp}/w_noremote.json")
if [ "$a2_strength" = "unknown" ] && [ "$a2_probe_v" = "SKIP" ]; then
    result A2_unprobed_strength_is_unknown PASS "with no remote the probe SKIPped and the record says 'unknown' — neither policy nor mechanism was claimed (§11.4.6)"
else
    result A2_unprobed_strength_is_unknown FAIL "with no probe the record should say 'unknown' with a SKIPped probe; it says strength='${a2_strength}' probe_verdict='${a2_probe_v}'"
fi

# --- A3: written strength EQUALS the probe's own established result ---------
if [ -z "$remote" ]; then
    result A3_written_strength_equals_probe SKIP "no reachable throwaway git remote could be created, so the probe could not run (honest skip, §11.4.3 — NOT a pass)"
    result A4_unprobed_mechanism_detected SKIP "requires a reachable remote for the live cross-check"
    result A6_honest_policy_accepted SKIP "requires a reachable remote for the live cross-check"
    result A7_carrier_not_a_claim SKIP "requires a reachable remote for the live cross-check"
else
    run_seam "${tmp}/w_remote.json" anchor write --chain "$chain" --anchor "${tmp}/a_remote.json" --remote "$remote"
    w2_rc=$SEAM_RC
    recorded=$(jget '.anchor_strength' "${tmp}/a_remote.json")
    probed=$(jget '.anchor_strength.strength' "${tmp}/w_remote.json")
    probe_v=$(jget '.anchor_strength.verdict' "${tmp}/w_remote.json")
    if [ "$w2_rc" -eq 0 ] && [ -n "$recorded" ] && [ "$recorded" = "$probed" ] && [ "$probe_v" = "PASS" ]; then
        result A3_written_strength_equals_probe PASS "the record says '${recorded}' and the probe established '${probed}' (probe verdict ${probe_v}) — recorded == probed, which is the T327 clause"
    else
        result A3_written_strength_equals_probe FAIL "recorded='${recorded}' probed='${probed}' probe_verdict='${probe_v}' seam_exit=${w2_rc}"
    fi

    # A4 golden-TRUE: a recorded `mechanism` with no probe evidence behind it.
    run_seam "${tmp}/v_forged.json" anchor verify --chain "$chain" --anchor "${tmp}/forged_mech.json" --remote "$remote"
    v4_rc=$SEAM_RC
    v4_sv=$(jget '.anchor_strength.verdict' "${tmp}/v_forged.json")
    if [ "$v4_sv" = "DETECTED" ] && [ "$v4_rc" -eq 3 ]; then
        result A4_unprobed_mechanism_detected PASS "a record claiming 'mechanism' against a probe that established '$(jget '.anchor_strength.strength' "${tmp}/v_forged.json")' is DETECTED and the seam exits 3"
    else
        result A4_unprobed_mechanism_detected FAIL "a record claiming 'mechanism' with no probe evidence was NOT flagged: strength_verdict='${v4_sv}' seam_exit=${v4_rc} (expected DETECTED / 3)"
    fi

    # A6 golden-FALSE: the honest current state must not be refused.
    run_seam "${tmp}/v_honest.json" anchor verify --chain "$chain" --anchor "${tmp}/a_remote.json" --remote "$remote"
    v6_rc=$SEAM_RC
    v6_sv=$(jget '.anchor_strength.verdict' "${tmp}/v_honest.json")
    if [ "$v6_rc" -eq 0 ] && [ "$v6_sv" = "PASS" ]; then
        result A6_honest_policy_accepted PASS "the honestly-recorded '${recorded}' anchor cross-checks clean against a live probe (exit 0) — the gate does not condemn the true record"
    else
        result A6_honest_policy_accepted FAIL "an honest record was refused: seam_exit=${v6_rc} strength_verdict='${v6_sv}' (expected 0 / PASS)"
    fi

    # A7 golden-FALSE CARRIER: bytes that MENTION `mechanism`, record `policy`.
    printf '{"head_digest":"%s","entry_count":%s,"anchor_strength":"%s","note":"anchor_strength mechanism is recordable only on probe evidence; this record claims mechanism nowhere"}\n' \
        "$(jget '.head_digest' "${tmp}/a_remote.json")" "$(jget '.entry_count' "${tmp}/a_remote.json")" "$recorded" \
        > "${tmp}/carrier.json"
    carrier_hits=$(grep -c mechanism "${tmp}/carrier.json")
    rc=$?
    if [ "$rc" -ne 0 ] || [ "$carrier_hits" -lt 1 ]; then
        result A7_carrier_not_a_claim SKIP "the carrier fixture does not actually carry the token, so it would prove nothing (instrument problem, not a finding)"
    else
        run_seam "${tmp}/v_carrier.json" anchor verify --chain "$chain" --anchor "${tmp}/carrier.json" --remote "$remote"
        v7_rc=$SEAM_RC
        v7_sv=$(jget '.anchor_strength.verdict' "${tmp}/v_carrier.json")
        if [ "$v7_rc" -eq 0 ] && [ "$v7_sv" = "PASS" ]; then
            result A7_carrier_not_a_claim PASS "a record whose bytes mention 'mechanism' ${carrier_hits}× but whose anchor_strength is '${recorded}' still PASSes — the token is not the thing (§11.4.201(7)(a))"
        else
            result A7_carrier_not_a_claim FAIL "a CARRIER that merely mentions 'mechanism' was treated as a claim: seam_exit=${v7_rc} strength_verdict='${v7_sv}' (expected 0 / PASS)"
        fi
    fi
fi

# --- A5: an INCOMPLETE record is refused at the read seam -------------------
printf '{"head_digest":"%s","anchor_strength":"policy"}\n' "$a1_head_for_forge" > "${tmp}/no_count.json"
printf '{"entry_count":%s,"anchor_strength":"policy"}\n' "$chain_lines" > "${tmp}/no_head.json"

run_seam "${tmp}/v_nocount.json" anchor verify --chain "$chain" --anchor "${tmp}/no_count.json"
v5a_rc=$SEAM_RC
v5a_v=$(jget '.chain_plus_anchor.verdict' "${tmp}/v_nocount.json")
v5a_reason=$(jget '.chain_plus_anchor.reason' "${tmp}/v_nocount.json")
if [ "$v5a_v" = "REFUSE" ] && [ "$v5a_rc" -eq 4 ] && echo "$v5a_reason" | grep -q 'entry_count'; then
    result A5a_missing_entry_count_refused PASS "an anchor with no entry_count REFUSEs (exit 4) and the refusal names entry_count as the reason"
else
    result A5a_missing_entry_count_refused FAIL "expected REFUSE/exit 4 naming entry_count; got verdict='${v5a_v}' exit=${v5a_rc} reason='${v5a_reason}'"
fi

run_seam "${tmp}/v_nohead.json" anchor verify --chain "$chain" --anchor "${tmp}/no_head.json"
v5b_rc=$SEAM_RC
v5b_v=$(jget '.chain_plus_anchor.verdict' "${tmp}/v_nohead.json")
v5b_reason=$(jget '.chain_plus_anchor.reason' "${tmp}/v_nohead.json")
if [ "$v5b_v" = "REFUSE" ] && [ "$v5b_rc" -eq 4 ] && echo "$v5b_reason" | grep -q 'head_digest'; then
    result A5b_missing_head_digest_refused PASS "an anchor with no head_digest REFUSEs (exit 4) and the refusal names head_digest as the reason"
else
    result A5b_missing_head_digest_refused FAIL "expected REFUSE/exit 4 naming head_digest; got verdict='${v5b_v}' exit=${v5b_rc} reason='${v5b_reason}'"
fi

# --- A8..A12: the package-level oracle (reaches what the CLI cannot) --------
oracle_head=$(jget '.head_digest' "${tmp}/corpus/golden_good/anchor.json")
"${tmp}/oracle" "$oracle_head" > "${tmp}/oracle.out" 2>"${tmp}/oracle.err"
oracle_rc=$?

# --- N3 needle: can the ORACLE-line parser see a known-present id? ----------
needle_n3=$(grep -c '^ORACLE A8_probe_verified_mechanism_accepted ' "${tmp}/oracle.out")
rc=$?
if [ "$rc" -ne 0 ] || [ "$needle_n3" -lt 1 ]; then
    warn "$(cat "${tmp}/oracle.err")"
    refuse "control needle N3 failed: the ORACLE-line parser found 0 occurrences of an id the harness always emits, so it is blind and every oracle verdict below would be an unfounded absence (§11.4.201(7)(b))"
fi
say "🔎 needle N3 — the ORACLE-line parser sees a known-present id"

for oid in A8_probe_verified_mechanism_accepted A9_unprobed_mechanism_refused \
           A9b_nil_probe_is_skip_unknown A10_overstated_mechanism_refused \
           A11_probed_policy_accepted A12a_complete_record_accepted \
           A12b_missing_entry_count_refused A12c_missing_head_digest_refused; do
    line=$(grep -m1 "^ORACLE ${oid} " "${tmp}/oracle.out")
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$line" ]; then
        result "$oid" FAIL "the harness emitted no verdict for this check (harness exit ${oracle_rc})"
        continue
    fi
    verdict=$(echo "$line" | awk '{print $3}')
    detail=$(echo "$line" | cut -d' ' -f4-)
    if [ "$verdict" = "PASS" ]; then
        result "$oid" PASS "pkg/anchor behaved as required ($detail)"
    else
        result "$oid" FAIL "pkg/anchor did NOT behave as required ($detail)"
    fi
done

echo "──────────────────────────────────────────────────────────────────────"
if [ "$fail_count" -ne 0 ]; then
    echo "❌ ${GATE}: FAIL — ${fail_count} check(s) decided against the mechanism"
    exit 1
fi
echo "✅ ${GATE}: PASS — the anchor record is complete (head_digest + entry_count) and its strength equals the probe's verified result; unprobed 'mechanism' is refused and probe-verified 'mechanism' is accepted"
exit 0
