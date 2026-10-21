#!/usr/bin/env bash
# cm_ledger_row_typed_from_closed_vocabulary.sh
#   — CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY gate
# (§11.4.266(B) — every claim-vs-reality ledger row carries a bluff type drawn
# from the SEVEN-member closed vocabulary; an ad-hoc type FAILs.)
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.266(B) fixes the vocabulary verbatim and constitutionally:
#
#     green-but-broken · coverage-theater · rubber-stamp-verified ·
#     stubbed-core · doc-vs-code-drift · config-present-but-unwired ·
#     byte-identical-fork
#
# and states it is "CLOSED for typing purposes and EXTENSIBLE only by an
# explicit, visible amendment; an un-typeable finding is an honest tracked GAP
# (§11.4.6 / §11.4.197), never an invented type." §11.4.266(C) explains WHY the
# typing is mandatory rather than cosmetic: the type is the ROUTING KEY to the
# anchor that owns that bluff class's counter-gate, so an untyped or ad-hoc
# row silently fails to reach any counter at all.
#
# This gate reads each ledger row's TYPE COLUMN — structurally, by resolved
# header name, never by scanning the row for a substring (§11.4.201(7)(a)) —
# and asserts the cell is exactly one closed-set member.
#
# ── Honest boundary (§11.4.6) ────────────────────────────────────────────────
#   * STRICT match. The cell is trimmed and case-folded, and NOTHING else:
#     `Stubbed-Core` passes, `stubbed_core` / `stubbed core` / `stubbedcore`
#     do NOT. §11.4.266(B) mandates a CLOSED vocabulary precisely to prevent
#     ad-hoc drift, and silently folding punctuation variants would re-open
#     the drift it closes — the same strict-token reasoning `CM-BADGE-CLOSED-
#     COLOR-VOCABULARY` applies to `brightgreen`.
#   * This gate judges the TYPE of rows that ARE present. It does NOT judge
#     whether the ledger is COMPLETE (that is CM-CLAIM-REALITY-LEDGER-COMPLETE)
#     nor whether each row's challenge passes (that is
#     CM-UNCHALLENGED-CAPABILITY-BLOCKS-RELEASE). With no ledger present there
#     is nothing to type, so this gate PASSes vacuously and says so — presence
#     is the sibling gate's mandate, and refusing here would be the
#     §11.4.201(1) false-positive this corpus forbids.
#   * A ledger present in neither supported tabular form is BLIND (exit 2), a
#     refusal to guess — never a green.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_ledger_row_typed_from_closed_vocabulary.sh [--root <dir>]
#                                                 [--ledger <path>] [--quiet]
#     --root <dir>     project root (default: $CONSUMER_ROOT or ".").
#     --ledger <path>  ledger location, relative to --root unless absolute
#                       (default: $CLAIM_LEDGER or docs/claim_reality_ledger.tsv).
#                       Location is consumer DATA per §11.4.35.
#     --quiet          suppress per-row OK lines (FAIL lines + summary always
#                       shown).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-row OK/FAIL lines naming the offending capability and its bad type,
#   a SUMMARY line, and a final PASS/FAIL banner.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). The control needle uses its own mktemp scratch.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk, sed, tr. Sources lib_claim_ledger.sh (same directory). Parses
#   clean under `bash -n` (§11.4.67).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.266(B)(C) (this gate's mandate), §11.4.201(7)(a) structure-not-
#   substring, §11.4.201(7)(b) control needle, §11.4.201(1) no false-positive
#   refusal, §11.4.35 (ledger location is consumer DATA), §1.1 (paired mutation
#   test cm_ledger_row_typed_from_closed_vocabulary_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — no ledger present (vacuous), or every present row carries a closed-set
#       bluff type.
#   1 — at least one row is untyped, or typed outside the closed vocabulary,
#       or the ledger has no resolvable type column at all.
#   2 — BLIND / environment error (root absent, ledger unreadable, ledger in an
#       unsupported form, or the parser could not be proven to see).
#
# Classification: universal (§11.4.17).

# `-e` deliberately omitted — see lib_claim_ledger.sh's identical note: the
# per-row walk must complete so the operator gets every offending row, not the
# first one.
set -u
set -o pipefail

GATE="CM-LEDGER-ROW-TYPED-FROM-CLOSED-VOCABULARY"
ANCHOR="11.4.266"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# The seven-member closed set, verbatim from §11.4.266(B).
CLOSED_TYPES="green-but-broken
coverage-theater
rubber-stamp-verified
stubbed-core
doc-vs-code-drift
config-present-but-unwired
byte-identical-fork"

root="${CONSUMER_ROOT:-.}"
ledger_rel="${CLAIM_LEDGER:-docs/claim_reality_ledger.tsv}"
quiet=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)   root="$2"; shift 2 ;;
        --ledger) ledger_rel="$2"; shift 2 ;;
        --quiet)  quiet="1"; shift ;;
        -h|--help) sed -n '1,80p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

lib="${here}/lib_claim_ledger.sh"
[ -f "$lib" ] || { echo "${GATE}: BLIND — lib_claim_ledger.sh not found at $lib" >&2; exit 2; }
# shellcheck source=lib_claim_ledger.sh
. "$lib"

[ -d "$root" ] || { echo "${GATE}: BLIND — project root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

case "$ledger_rel" in
    /*) ledger="$ledger_rel" ;;
    *)  ledger="${root}/${ledger_rel}" ;;
esac

# §11.4.201(7)(b): prove the instrument SEES before any absence is reported.
if ! cl_control_needle; then
    echo "${GATE}: BLIND — control needle failed: the ledger parser could not read a known-good fixture through this same path; no absence reported from here would be evidence (§11.4.201(7)(b))" >&2
    exit 2
fi

if [ ! -e "$ledger" ]; then
    echo "${GATE}: no ledger at ${ledger} — nothing to type (CM-CLAIM-REALITY-LEDGER-COMPLETE governs the ledger's EXISTENCE) — SKIP-vacuous"
    echo "${GATE}: PASS — 0 row(s) present, vacuously compliant (§${ANCHOR})"
    exit 0
fi
[ -r "$ledger" ] || { echo "${GATE}: BLIND — ledger exists but is not readable: $ledger" >&2; exit 2; }

fmt="$(cl_format "$ledger")"
case "$fmt" in
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

rows="$(cl_rows "$ledger")"
header="$(printf '%s\n' "$rows" | awk 'NR==1{print; exit}')"
if [ -z "$header" ]; then
    echo "${GATE}: BLIND — ledger ${ledger} parsed to zero lines although its format resolved to '${fmt}' (parser saw a known-good needle, so this is an unexpected shape)" >&2
    exit 2
fi

type_idx="$(cl_col_index "$header" bluff_type type)"
if [ -z "$type_idx" ]; then
    echo "${GATE}: FAIL ledger='${ledger}' reason=NO_TYPE_COLUMN header='${header}'"
    echo "${GATE}: SUMMARY ledger=${ledger} rows=0 fail=1"
    echo "${GATE}: FAIL — the ledger names no bluff-type column, so every row is untyped; §${ANCHOR}(B) requires each row carry a type from the closed vocabulary (name a column 'bluff_type' or 'type')" >&2
    exit 1
fi
cap_idx="$(cl_col_index "$header" capability claim)"

total=0
fails=0
rownum=1

while IFS= read -r row; do
    rownum=$((rownum + 1))
    [ -n "$row" ] || continue
    total=$((total + 1))

    raw="$(cl_field "$row" "$type_idx")"
    cap="$(cl_field "$row" "$cap_idx")"
    [ -n "$cap" ] || cap="<row ${rownum}>"
    norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

    if [ -z "$norm" ]; then
        fails=$((fails + 1))
        echo "${GATE}: FAIL capability='${cap}' reason=UNTYPED_ROW"
        continue
    fi
    # here-string, not `printf | grep -q` (SIGPIPE x pipefail class, §11.4.276(C); bounded payload, defensive hardening)
    if grep -qxF -- "$norm" <<<"$CLOSED_TYPES"; then
        [ -n "$quiet" ] || echo "${GATE}: OK capability='${cap}' bluff_type='${norm}'"
        continue
    fi
    fails=$((fails + 1))
    echo "${GATE}: FAIL capability='${cap}' bluff_type='${raw}' reason=TYPE_OUTSIDE_CLOSED_VOCABULARY"
done < <(printf '%s\n' "$rows" | awk 'NR>1')

echo "${GATE}: SUMMARY ledger=${ledger} rows=${total} fail=${fails}"

if [ "$fails" -gt 0 ]; then
    echo "${GATE}: FAIL — ${fails}/${total} ledger row(s) carry no closed-vocabulary bluff type; the closed set is: $(printf '%s' "$CLOSED_TYPES" | tr '\n' ' ')(§${ANCHOR}(B))" >&2
    exit 1
fi

echo "${GATE}: PASS — all ${total} ledger row(s) typed from the closed vocabulary (§${ANCHOR}(B))"
exit 0
