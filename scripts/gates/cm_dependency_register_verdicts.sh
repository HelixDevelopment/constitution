#!/bin/sh
# =============================================================================
# cm_dependency_register_verdicts.sh — CM-DEPENDENCY-REGISTER-VERDICTS (T232).
#
# ── What this gate asserts (FR-013, FR-015) ─────────────────────────────────
#   DRV-A0  the E6 register and its reader are present            (structural)
#   DRV-A1  the REAL register validates                              (RUNTIME)
#   DRV-A2  GOLDEN-BAD : a verdict outside {VERIFIED,AMBIGUOUS,
#                        UNVERIFIED} is refused, NAMING the entry     (RUNTIME)
#   DRV-A3  GOLDEN-BAD : an empty artifact_url is refused, naming it  (RUNTIME)
#   DRV-A4  GOLDEN-BAD : the NAME-COLLISION fixture resolves
#                        AMBIGUOUS and never VERIFIED                 (RUNTIME)
#   DRV-A5  NEGATIVE CONTROL: an exact name+description match DOES
#                        resolve VERIFIED                             (RUNTIME)
#   DRV-A6  GOLDEN-BAD : an UNVERIFIED verdict worded as a claim of
#                        NON-EXISTENCE is refused (A-011)             (RUNTIME)
#
# ── Why A4 is the golden-BAD the task names ─────────────────────────────────
# 2 of the 21 externally named tools in the Phase-0 census were name
# collisions: a real project carries the name and does an unrelated job. A
# resolver that matched on the name would admit precisely the entries most
# likely to look adoptable, so the collision case is the one the selftest is
# built around.
#
# ── Why A5 exists ───────────────────────────────────────────────────────────
# Without it, A4 is satisfiable by a resolver that answers AMBIGUOUS to
# everything — refusing correct behaviour, which §11.4.201(1) rates exactly as
# seriously as a false pass.
#
# ── Why A6 exists (A-011) ───────────────────────────────────────────────────
# For at least three of the six not-found entries, a real project doing exactly
# the described job exists under a DIFFERENT NAME. "Not found" is therefore an
# absence on one search path, and recording it as non-existence would send the
# next reader to the wrong conclusion.
#
# Usage : cm_dependency_register_verdicts.sh [--register <path>]
# Output: CN-VERDICT / CN-SUMMARY. Exit 0 only when nothing FAILed or was BLIND.
# Deps  : POSIX sh, grep, mktemp. Read-only w.r.t. the repository.
# =============================================================================

set -u

GATE_ID=CM-DEPENDENCY-REGISTER-VERDICTS
SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# Default root = where the gate LIVES (superproject when vendored, else the canon itself), never the directory above the canon.
# shellcheck disable=SC1091
[ -r "$SELF_DIR/../lib/default_scan_root.sh" ] && . "$SELF_DIR/../lib/default_scan_root.sh" && REPO=$(cm_default_scan_root "$SELF_DIR") || REPO=""
# A copy of the gate staged somewhere without scripts/lib (a paired-mutation sandbox) falls back to the legacy
# consumer-layout depth it was staged at.
[ -n "$REPO" ] || REPO=$(CDPATH='' cd -- "$SELF_DIR/../../.." && pwd)
STANDALONE=0   # --standalone-canon: the invocation DECLARES a canon with no consumer (only way to get the honest SKIP)
REGISTER="$REPO/docs/requests/dependency_register.jsonl"
DR="$SELF_DIR/lib/dependency_register.sh"

while [ $# -gt 0 ]; do
    case $1 in
        --register) REGISTER=$2; shift 2 ;;
        --standalone-canon) STANDALONE=1; shift ;;
        -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

_argv_saved=$*; _argc=$#
set --
# shellcheck disable=SC1091
. "$SELF_DIR/lib/chain_control_needle.sh"
if [ "$_argc" -gt 0 ]; then
    # shellcheck disable=SC2086
    set -- $_argv_saved
fi

cn_reset
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cm_drv.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf '$TMP'" EXIT INT TERM

# --- A0 -----------------------------------------------------------------------
a0=0
[ -f "$DR" ] || { cn_fail DRV-A0-SEAM-PRESENT "the E6 reader is absent: $DR"; a0=1; }
REG_SKIP=0
if [ ! -r "$REGISTER" ] && [ "$STANDALONE" -eq 1 ]; then
    REG_SKIP=1
    cn_skip DRV-A0-SEAM-PRESENT "standalone canon DECLARED (--standalone-canon): the E6 register $REGISTER is consumer data and does not exist here (honest SKIP, not a PASS; the fixture checks A2-A6 still ran)"
elif [ ! -r "$REGISTER" ]; then
    cn_fail DRV-A0-SEAM-PRESENT "the E6 register is absent or unreadable: $REGISTER"; a0=1
fi
if [ "$REG_SKIP" -eq 1 ] && [ ! -f "$DR" ]; then
    cn_fail DRV-A0-SEAM-PRESENT "the E6 reader is absent: $DR"; cn_summary "$GATE_ID"; exit $?
elif [ "$REG_SKIP" -eq 1 ]; then
    :
elif [ "$a0" -eq 0 ]; then
    cn_pass DRV-A0-SEAM-PRESENT "reader $DR and register $REGISTER are both present"
else
    cn_summary "$GATE_ID"; exit $?
fi

run_dr() { sh "$DR" "$@" 2>&1; }

# --- A1 the real register validates -------------------------------------------
if [ "$REG_SKIP" -eq 1 ]; then
    cn_skip DRV-A1-REAL-REGISTER-VALID "standalone canon DECLARED: no consumer register to validate (honest SKIP, not a PASS)"
    rc=-1; out=""
else
out=$(run_dr validate "$REGISTER"); rc=$?
fi
if [ "$rc" -eq -1 ]; then
    :
elif [ "$rc" -eq 0 ]; then
    n=$(printf '%s\n' "$out" | grep -Ec '^ok   entry ' || true)
    cn_pass DRV-A1-REAL-REGISTER-VALID "the shipped register validates: $n entry/entries accepted"
else
    cn_fail DRV-A1-REAL-REGISTER-VALID "the shipped register at $REGISTER does NOT validate (rc=$rc): $(printf '%s\n' "$out" | tail -n 3)"
fi

# --- fixtures ------------------------------------------------------------------
BASE="$TMP/base.jsonl"
{
  printf '%s\n' '{"name":"fx-ok","verdict":"VERIFIED","artifact_url":"https://example.invalid/ok","gap_mapping":"G1","capability_status":"SHIPPED","covered_by":""}'
} > "$BASE"

# --- A2 verdict outside the closed set ----------------------------------------
B="$TMP/bad_verdict.jsonl"; cp "$BASE" "$B"
printf '%s\n' '{"name":"fx-bad-verdict","verdict":"PROBABLY","artifact_url":"https://example.invalid/x","gap_mapping":"G1","capability_status":"SHIPPED","covered_by":""}' >> "$B"
out=$(run_dr validate "$B"); rc=$?
named=$(printf '%s\n' "$out" | grep -Ec 'fx-bad-verdict' || true)
if [ "$rc" -ne 0 ] && [ "${named:-0}" -gt 0 ]; then
    cn_pass DRV-A2-VERDICT-CLOSED-SET "a verdict outside the closed set is refused AND the offending entry is named"
elif [ "$rc" -ne 0 ]; then
    cn_fail DRV-A2-VERDICT-CLOSED-SET "refused, but without naming the entry — a bare rejection tells the author nothing about which row to fix"
else
    cn_fail DRV-A2-VERDICT-CLOSED-SET "a verdict outside {VERIFIED,AMBIGUOUS,UNVERIFIED} was accepted"
fi

# --- A3 empty artifact_url -----------------------------------------------------
B2="$TMP/bad_evidence.jsonl"; cp "$BASE" "$B2"
printf '%s\n' '{"name":"fx-no-evidence","verdict":"UNVERIFIED","artifact_url":"","gap_mapping":"G2","capability_status":"UNREACHABLE","covered_by":""}' >> "$B2"
out=$(run_dr validate "$B2"); rc=$?
named=$(printf '%s\n' "$out" | grep -Ec 'fx-no-evidence' || true)
if [ "$rc" -ne 0 ] && [ "${named:-0}" -gt 0 ]; then
    cn_pass DRV-A3-EVIDENCE-FIELD "an empty artifact_url is refused AND the offending entry is named"
else
    cn_fail DRV-A3-EVIDENCE-FIELD "an entry with no evidence field was accepted (rc=$rc) — FR-013 requires a citable artifact or an explicit not-found statement"
fi

# --- A4 / A5 the name-collision golden-bad and its negative control ------------
CAND="$TMP/candidates.tsv"
printf 'fx-collider\ta build-cache proxy for container layers\thttps://example.invalid/collider\n'  > "$CAND"
printf 'fx-exact\ta post-quantum hybrid signature scheme\thttps://example.invalid/exact\n'        >> "$CAND"

out=$(run_dr resolve fx-collider 'a hash-chained tool-call ledger' "$CAND")
amb=$(printf '%s\n' "$out" | grep -Ec 'AMBIGUOUS' || true)
ver=$(printf '%s\n' "$out" | grep -Ec '(^|[^A-Z])VERIFIED' || true)
if [ "${amb:-0}" -gt 0 ] && [ "${ver:-0}" -eq 0 ]; then
    cn_pass DRV-A4-NAME-COLLISION-AMBIGUOUS "a real name paired with a mismatched description resolves AMBIGUOUS, never VERIFIED (FR-015)"
else
    cn_fail DRV-A4-NAME-COLLISION-AMBIGUOUS "the name-collision fixture resolved on the NAME alone (AMBIGUOUS=$amb VERIFIED=$ver): $out"
fi

out=$(run_dr resolve fx-exact 'a post-quantum hybrid signature scheme' "$CAND")
ver=$(printf '%s\n' "$out" | grep -Ec '(^|[^A-Z])VERIFIED' || true)
amb=$(printf '%s\n' "$out" | grep -Ec 'AMBIGUOUS' || true)
if [ "${ver:-0}" -gt 0 ] && [ "${amb:-0}" -eq 0 ]; then
    cn_pass DRV-A5-EXACT-MATCH-VERIFIED "an exact name+description match DOES resolve VERIFIED — the resolver is not an answer-AMBIGUOUS-to-everything engine"
else
    cn_fail DRV-A5-EXACT-MATCH-VERIFIED "an exact match was not resolved VERIFIED (VERIFIED=$ver AMBIGUOUS=$amb): $out — a false refusal is as serious as a false pass (§11.4.201(1))"
fi

# --- A6 non-existence claim ----------------------------------------------------
B3="$TMP/bad_nonexistence.jsonl"; cp "$BASE" "$B3"
printf '%s\n' '{"name":"fx-nonexistence","verdict":"UNVERIFIED","artifact_url":"this project does not exist","gap_mapping":"G2","capability_status":"UNREACHABLE","covered_by":""}' >> "$B3"
out=$(run_dr validate "$B3"); rc=$?
if [ "$rc" -ne 0 ]; then
    cn_pass DRV-A6-ABSENCE-NOT-NONEXISTENCE "an UNVERIFIED entry worded as a claim of non-existence is refused (A-011: it is an absence on one search path)"
else
    cn_fail DRV-A6-ABSENCE-NOT-NONEXISTENCE "a non-existence claim was recorded as evidence — A-011 measured that for at least three of the six not-found entries a real project exists under a different name"
fi

cn_summary "$GATE_ID"
exit $?
