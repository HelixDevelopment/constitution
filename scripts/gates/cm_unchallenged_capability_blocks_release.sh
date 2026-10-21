#!/usr/bin/env bash
# cm_unchallenged_capability_blocks_release.sh
#   — CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE gate
# (§11.4.266(D) — a claim-vs-reality ledger row whose challenge is ABSENT,
# NEVER EXECUTED, or has NO VERDICT for the release-candidate artifact
# fingerprint blocks the release exactly as a FAILING challenge does.)
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.266(D) is verbatim and unqualified: "a capability with no passing
# challenge is a release blocker. A ledger row whose challenge is absent,
# never executed, or executed only against a stale artifact fingerprint blocks
# the release exactly as a FAILING challenge does — this is the §11.4.135 /
# §11.4.236 absence-blocks-as-FAIL semantics applied to the claim side, and it
# is the reason the ledger is a gate rather than a document."
#
# This gate walks every ledger row and, for each, resolves its CHALLENGE cell
# structurally (by resolved header name, never by substring — §11.4.201(7)(a))
# and requires a verdict record for THAT challenge at THE candidate artifact
# fingerprint whose value is PASS. Anything less blocks.
#
# ── Fail-closed by design, and why that is not a false positive ──────────────
# An ABSENT verdict store, a verdict for a STALE fingerprint, and a verdict
# that was never written are all the SAME verdict from this gate: BLOCK. That
# is the anchor's own rule, not this gate's invention — §11.4.266(D) makes
# absence block "exactly as a FAILING challenge does". A gate that passed a
# row because its evidence could not be found would be the §11.4.201(6)
# false-null this corpus forbids.
#
# ── Honest boundary (§11.4.6) ────────────────────────────────────────────────
#   * NO ledger present -> vacuous PASS. Whether every advertised capability
#     HAS a row is CM-CLAIM-REALITY-LEDGER-COMPLETE's mandate, not this one's;
#     refusing here would be the §11.4.201(1) false-positive refusal.
#   * NO candidate fingerprint supplied while a ledger IS present -> BLIND
#     (exit 2). This gate cannot know which artifact is the release candidate,
#     and inventing one would be exactly the §11.4.6 guess that makes a
#     fingerprint-keyed verdict meaningless.
#   * This gate proves each row HAS a fresh passing challenge. It does NOT
#     prove the challenge is STRONG (oracle strength stays §11.4.245 +
#     §11.4.107(10) + §1.1), and it does NOT judge the row's bluff type (that
#     is CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_unchallenged_capability_blocks_release.sh
#       [--root <dir>] [--ledger <path>] [--verdicts <path>]
#       [--candidate-fingerprint <fp>] [--quiet]
#     --root <dir>                 project root (default: $CONSUMER_ROOT or ".").
#     --ledger <path>              default $CLAIM_LEDGER or
#                                   docs/claim_reality_ledger.tsv.
#     --verdicts <path>            default $CLAIM_VERDICTS or
#                                   docs/claim_reality_verdicts.tsv; a
#                                   header-bearing table with columns
#                                   challenge / fingerprint / verdict.
#     --candidate-fingerprint <fp> the release candidate's artifact
#                                   fingerprint (or $CANDIDATE_FINGERPRINT).
#     --quiet                      suppress per-row OK lines.
#   Every path and the fingerprint source are consumer DATA per §11.4.35.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-row OK/FAIL lines naming the capability and the blocking reason, a
#   SUMMARY line, and a final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). The control needle uses its own mktemp scratch.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk, sed, tr. Sources lib_claim_ledger.sh (same directory). Parses
#   clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.266(D) (this gate's mandate), §11.4.135 / §11.4.236 (absence blocks
#   as a FAIL — the semantics this applies to the claim side),
#   §11.4.115(F) (verdicts are machine-written and fingerprint-keyed),
#   §11.4.201(1)(6)(7) (no false-positive refusal, no false null, structure not
#   substring), §1.1 (paired mutation test
#   cm_unchallenged_capability_blocks_release_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — no ledger present (vacuous), or every row has a PASS verdict at the
#       candidate fingerprint.
#   1 — at least one row is blocked (challenge absent / no verdict for the
#       candidate / verdict not PASS), or the ledger has no challenge column.
#   2 — BLIND / environment error (root absent, unreadable or unsupported
#       ledger or verdict store, missing candidate fingerprint, or the parser
#       could not be proven to see).
#
# Classification: universal (§11.4.17).

# `-e` deliberately omitted — the per-row walk must complete so the operator
# sees EVERY blocking row, not merely the first (§11.4.234(D)).
set -u
set -o pipefail

GATE="CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE"
ANCHOR="11.4.266"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Placeholder cells that mean "no challenge", normalised lower-case.
CHALLENGE_PLACEHOLDERS="-
--
n/a
na
none
nil
tbd
todo
?
pending"

root="${CONSUMER_ROOT:-.}"
ledger_rel="${CLAIM_LEDGER:-docs/claim_reality_ledger.tsv}"
verdicts_rel="${CLAIM_VERDICTS:-docs/claim_reality_verdicts.tsv}"
candidate="${CANDIDATE_FINGERPRINT:-}"
quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)     root="$2"; shift 2 ;;
        --ledger)   ledger_rel="$2"; shift 2 ;;
        --verdicts) verdicts_rel="$2"; shift 2 ;;
        --candidate-fingerprint) candidate="$2"; shift 2 ;;
        --quiet)    quiet="1"; shift ;;
        -h|--help) sed -n '1,90p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

lib="${here}/lib_claim_ledger.sh"
[ -f "$lib" ] || { echo "${GATE}: BLIND — lib_claim_ledger.sh not found at $lib" >&2; exit 2; }
# shellcheck source=lib_claim_ledger.sh
. "$lib"

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$root" "$1" ;; esac; }
ledger="$(abspath "$ledger_rel")"
verdicts="$(abspath "$verdicts_rel")"

# §11.4.201(7)(b): prove the instrument SEES before reporting any absence.
if ! cl_control_needle; then
    echo "${GATE}: BLIND — control needle failed: the ledger parser could not read a known-good fixture through this same path; no absence reported from here would be evidence (§11.4.201(7)(b))" >&2
    exit 2
fi

if [ ! -e "$ledger" ]; then
    echo "${GATE}: no ledger at ${ledger} — no claim rows to challenge (CM-CLAIM-REALITY-LEDGER-COMPLETE governs the ledger's EXISTENCE) — SKIP-vacuous"
    echo "${GATE}: PASS — 0 row(s) present, vacuously compliant (§${ANCHOR})"
    exit 0
fi
[ -r "$ledger" ] || { echo "${GATE}: BLIND — ledger exists but is not readable: $ledger" >&2; exit 2; }

lfmt="$(cl_format "$ledger")"
case "$lfmt" in
    tsv|md) : ;;
    empty)
        echo "${GATE}: ledger ${ledger} holds no eligible rows — SKIP-vacuous"
        echo "${GATE}: PASS — 0 row(s) present, vacuously compliant (§${ANCHOR})"
        exit 0
        ;;
    *)
        echo "${GATE}: BLIND — ledger ${ledger} is in neither supported tabular form (tab-separated or markdown pipe table); this gate refuses to guess a column layout (§11.4.6)" >&2
        exit 2
        ;;
esac

lrows="$(cl_rows "$ledger")"
lhdr="$(printf '%s\n' "$lrows" | awk 'NR==1{print; exit}')"
[ -n "$lhdr" ] || { echo "${GATE}: BLIND — ledger ${ledger} parsed to zero lines although its format resolved to '${lfmt}'" >&2; exit 2; }

ch_idx="$(cl_col_index "$lhdr" challenge challenge_id challenge_ref challenge_reference)"
cap_idx="$(cl_col_index "$lhdr" capability claim)"
if [ -z "$ch_idx" ]; then
    echo "${GATE}: FAIL ledger='${ledger}' reason=NO_CHALLENGE_COLUMN header='${lhdr}'"
    echo "${GATE}: SUMMARY ledger=${ledger} rows=0 fail=1"
    echo "${GATE}: FAIL — the ledger names no challenge column, so no row can be shown to have a passing challenge; §${ANCHOR}(D) blocks (name a column 'challenge')" >&2
    exit 1
fi

data_rows="$(printf '%s\n' "$lrows" | awk 'NR>1 && NF')"
if [ -z "$data_rows" ]; then
    echo "${GATE}: ledger ${ledger} has a header but 0 data rows — SKIP-vacuous"
    echo "${GATE}: PASS — 0 row(s) present, vacuously compliant (§${ANCHOR})"
    exit 0
fi

# A candidate fingerprint is REQUIRED once real rows exist: without it the
# fingerprint-keyed freshness check is meaningless, and inventing one would be
# the §11.4.6 guess. BLIND, never a green.
if [ -z "$candidate" ]; then
    echo "${GATE}: BLIND — ledger has rows but no release-candidate artifact fingerprint was supplied; pass --candidate-fingerprint <fp> or set CANDIDATE_FINGERPRINT (§11.4.6 — this gate will not invent the candidate identity)" >&2
    exit 2
fi

# ---- verdict store -------------------------------------------------------
verdict_rows=""
v_ch_idx=""; v_fp_idx=""; v_vd_idx=""
verdicts_state="present"
if [ ! -e "$verdicts" ]; then
    verdicts_state="absent"
else
    [ -r "$verdicts" ] || { echo "${GATE}: BLIND — verdict store exists but is not readable: $verdicts" >&2; exit 2; }
    vfmt="$(cl_format "$verdicts")"
    case "$vfmt" in
        tsv|md)
            vrows="$(cl_rows "$verdicts")"
            vhdr="$(printf '%s\n' "$vrows" | awk 'NR==1{print; exit}')"
            [ -n "$vhdr" ] || { echo "${GATE}: BLIND — verdict store ${verdicts} parsed to zero lines although its format resolved to '${vfmt}'" >&2; exit 2; }
            v_ch_idx="$(cl_col_index "$vhdr" challenge challenge_id challenge_ref challenge_reference)"
            v_fp_idx="$(cl_col_index "$vhdr" fingerprint artifact_fingerprint candidate_fingerprint)"
            v_vd_idx="$(cl_col_index "$vhdr" verdict result status)"
            if [ -z "$v_ch_idx" ] || [ -z "$v_fp_idx" ] || [ -z "$v_vd_idx" ]; then
                echo "${GATE}: BLIND — verdict store ${verdicts} lacks one of the required columns challenge/fingerprint/verdict (header='${vhdr}'); this gate refuses to guess which column is which (§11.4.6)" >&2
                exit 2
            fi
            verdict_rows="$(printf '%s\n' "$vrows" | awk 'NR>1 && NF')"
            ;;
        empty) verdicts_state="empty" ;;
        *)
            echo "${GATE}: BLIND — verdict store ${verdicts} is in neither supported tabular form (tab-separated or markdown pipe table) (§11.4.6)" >&2
            exit 2
            ;;
    esac
fi
if [ "$verdicts_state" != "present" ]; then
    echo "${GATE}: NOTE verdict store ${verdicts} is ${verdicts_state} — every row therefore has NO verdict for the candidate; §${ANCHOR}(D) makes that block exactly as a FAILing challenge does"
fi

# lookup_verdict <challenge> -> the verdict cell for (challenge, candidate), or
# empty when no such record exists. STRUCTURAL: whole-cell equality on the
# resolved challenge + fingerprint columns, so neither a fingerprint mentioned
# in another row's free-text cell nor one in an inert comment can satisfy a row.
lookup_verdict() {
    local want_ch="$1"
    [ -n "$verdict_rows" ] || { printf ''; return 0; }
    printf '%s\n' "$verdict_rows" | awk -F '\t' \
        -v ci="$v_ch_idx" -v fi="$v_fp_idx" -v vi="$v_vd_idx" \
        -v wc="$want_ch" -v wf="$candidate" '
        {
            c = (ci <= NF ? $ci : "")
            f = (fi <= NF ? $fi : "")
            v = (vi <= NF ? $vi : "")
            if (c == wc && f == wf) { printf "%s", v; found = 1; exit }
        }
        END { if (!found) printf "" }'
}

total=0
fails=0
rownum=1

while IFS= read -r row; do
    rownum=$((rownum + 1))
    [ -n "$row" ] || continue
    total=$((total + 1))

    ch="$(cl_field "$row" "$ch_idx")"
    cap="$(cl_field "$row" "$cap_idx")"
    [ -n "$cap" ] || cap="<row ${rownum}>"
    ch_norm="$(printf '%s' "$ch" | tr '[:upper:]' '[:lower:]')"

    # here-string, not `printf | grep -q` (SIGPIPE x pipefail class, §11.4.276(C); bounded payload, defensive hardening)
    if [ -z "$ch_norm" ] || grep -qxF -- "$ch_norm" <<<"$CHALLENGE_PLACEHOLDERS"; then
        fails=$((fails + 1))
        echo "${GATE}: FAIL capability='${cap}' reason=CHALLENGE_ABSENT challenge='${ch}'"
        continue
    fi

    vd="$(lookup_verdict "$ch")"
    if [ -z "$vd" ]; then
        fails=$((fails + 1))
        echo "${GATE}: FAIL capability='${cap}' challenge='${ch}' reason=NO_VERDICT_FOR_CANDIDATE fingerprint='${candidate}'"
        continue
    fi
    vd_norm="$(printf '%s' "$vd" | tr '[:upper:]' '[:lower:]')"
    if [ "$vd_norm" != "pass" ]; then
        fails=$((fails + 1))
        echo "${GATE}: FAIL capability='${cap}' challenge='${ch}' reason=CHALLENGE_NOT_PASS verdict='${vd}'"
        continue
    fi
    [ -n "$quiet" ] || echo "${GATE}: OK capability='${cap}' challenge='${ch}' verdict='${vd}' fingerprint='${candidate}'"
done < <(printf '%s\n' "$data_rows")

echo "${GATE}: SUMMARY ledger=${ledger} verdicts=${verdicts} candidate=${candidate} rows=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} advertised capability row(s) have no PASSing challenge at the release-candidate fingerprint; §${ANCHOR}(D) blocks the release exactly as a FAILing challenge does" >&2
    exit 1
fi

echo "${GATE}: PASS — all ${total} ledger row(s) carry a PASS verdict at candidate fingerprint ${candidate} (§${ANCHOR}(D))"
exit 0
