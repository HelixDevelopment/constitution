#!/usr/bin/env bash
# cm_first_refusal_observed.sh — FR-022 FIRST-REFUSAL gate (§11.4.115(F)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.115(F): "a guard never observed FAILing on the genuinely-broken
# artifact is unvalidated instrumentation and mints no verdicts." A gate that
# has never been seen to REFUSE might be structurally incapable of refusing —
# its PASS is then indistinguishable from a tautology, and counting it is a
# §11.4 PASS-bluff at the instrumentation layer.
#
# This gate enforces the consequence: a gate token NEWLY BOUND to a seam
# contributes NO PASS to any suite result until the first-refusal registry
# `gate_first_refusal.tsv` carries a row for it whose evidence path resolves
# to a NON-EMPTY recorded RED run.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_first_refusal_observed.sh --token CM-FOO [--token CM-BAR ...]
#   cm_first_refusal_observed.sh --tokens-file <newline-delimited-file>
#   cm_first_refusal_observed.sh --selftest
#
#   Options:
#     --token <TOK>       a gate token newly bound to a seam (repeatable).
#     --tokens-file <f>   file of such tokens, one per line; `#` comments and
#                         blank lines ignored. Combinable with --token.
#     --registry <f>      first-refusal registry (default:
#                         <root>/scripts/gates/gate_first_refusal.tsv).
#     --root <dir>        constitution root (default: two dirs above this
#                         script). Only used to locate the default registry.
#     --repo-root <dir>   root the registry's relative paths resolve against
#                         (default: the parent of <root>).
#     --quiet             suppress the per-token accept lines.
#     --selftest          run the §11.4.107(10) golden-TRUE / golden-FALSE
#                         self-validation of THIS gate and exit.
#     -h|--help           print this header.
#
# ── The token set is DATA, never invented ────────────────────────────────────
# The gate REFUSES to run with an empty token set (exit 2) rather than
# reporting a vacuous PASS over zero tokens. A gate that passes because it was
# asked about nothing is the §11.4.201-class bluff this file exists to stop;
# the consuming project supplies its newly-bound set per §11.4.35.
#
# ── Refusal conditions (each names itself) ───────────────────────────────────
#   NO-ROW            the token has no row in the registry at all.
#   EVIDENCE-EMPTY    the evidence field is missing, blank, or the explicit
#                     `PENDING-FIRST-REFUSAL` sentinel.
#   EVIDENCE-ABSENT   the evidence path does not resolve to a file.
#   EVIDENCE-ZERO     the evidence file resolves but is zero bytes.
#   MUTATION-ABSENT   the cited paired-mutation path does not resolve — the
#                     validator the row claims produced the RED is not there,
#                     so the row's own provenance is unverifiable.
# An absent observation is NEVER upgraded into "unobserved but acceptable"
# (§11.4.201(6): a quiet zero is not evidence; §11.4.6: no guessing).
#
# ── Fail-closed ──────────────────────────────────────────────────────────────
# An unreadable registry is BLIND (exit 2), never an empty registry that
# silently refuses or silently passes (§11.4.252).
#
# ── HONEST BOUNDARY (§11.4.6) — do not overstate this gate ───────────────────
# This gate proves a first-refusal record EXISTS, RESOLVES and is NON-EMPTY —
# exactly the FR-022 contract. It does NOT and CANNOT verify that the cited
# file genuinely transcribes a RED run: authenticity of the evidence is the
# job of the task that RUNS the mutation and records the row (§11.4.115(F)
# harness-written verdicts). Nor does it prove the gate is well-calibrated —
# oracle strength stays §1.1 / §11.4.107(10) territory.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0  every supplied token has an observed first refusal — their PASSes count.
#   1  at least one token has not been observed refusing — its PASS does not
#      count.
#   2  BLIND (unreadable registry, empty token set, bad argument).
#
# Classification: universal (§11.4.17) — no project literal; the consuming
# project supplies its registry path, repo root and token set as DATA
# (§11.4.35).
#
# Cross-references: §11.4.115(F), §11.4.201(1)/(6), §11.4.107(10), §11.4.252,
# §11.4.6, §11.4.35, §1.1.

set -u

GATE="CM-FIRST-REFUSAL-OBSERVED"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# verdict-affecting ambient overrides are guarded (11.4.201(6)-(8)): honoured only under HELIX_TEST_MODE=1 (+ temp path for paths)
_ge_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/../lib/gate_env_override.sh"
# shellcheck source=/dev/null
if [ -r "$_ge_lib" ]; then . "$_ge_lib"; else cm_gate_env_set() { printf -v "$1" '%s' "$3"; [ -z "${!2:-}" ] || echo "gate_env_override: ignoring $2 (guard lib missing: fail closed)" >&2; }; fi
cm_gate_env_set root CONSTITUTION_ROOT "$(cd "${here}/../.." && pwd)" path   # which canon is checked; --root stays honoured
repo_root=""
registry=""
quiet=""
selftest=""
tokens=""

while [ $# -gt 0 ]; do
    case "$1" in
        --token)       tokens="${tokens}$2
"; shift 2 ;;
        --tokens-file)
            [ -r "$2" ] || { echo "${GATE}: BLIND — tokens-file not readable: $2" >&2; exit 2; }
            tokens="${tokens}$(grep -v '^[[:space:]]*#' -- "$2" | sed '/^[[:space:]]*$/d')
"; shift 2 ;;
        --registry)    registry="$2"; shift 2 ;;
        --root)        root="$2"; shift 2 ;;
        --repo-root)   repo_root="$2"; shift 2 ;;
        --quiet)       quiet="1"; shift ;;
        --selftest)    selftest="1"; shift ;;
        -h|--help)     sed -n '1,80p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -d "$root" ] || { echo "${GATE}: BLIND — root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"
[ -n "$registry" ]  || registry="${root}/scripts/gates/gate_first_refusal.tsv"
[ -n "$repo_root" ] || repo_root="$(cd "${root}/.." && pwd)"

# evaluate_token <token> <registry> <repo-root>
#   prints "<VERDICT>\t<token>\t<detail>"; returns 0 accept, 1 refuse.
evaluate_token() {
    _et_tok="$1"; _et_reg="$2"; _et_repo="$3"

    _et_row="$(grep -v '^[[:space:]]*#' -- "$_et_reg" \
               | awk -F'\t' -v t="$_et_tok" '$1==t{print; exit}')"
    if [ -z "$_et_row" ]; then
        printf 'REFUSE\t%s\tNO-ROW: no first-refusal record in %s — this gate has never been observed refusing, so its PASS does not count (§11.4.115(F))\n' "$_et_tok" "$_et_reg"
        return 1
    fi

    _et_mut="$(printf '%s' "$_et_row" | awk -F'\t' '{print $2}')"
    _et_ev="$(printf '%s' "$_et_row"  | awk -F'\t' '{print $3}')"

    case "$_et_ev" in
        ""|PENDING-FIRST-REFUSAL)
            printf 'REFUSE\t%s\tEVIDENCE-EMPTY: evidence field is blank or PENDING-FIRST-REFUSAL — an absent observation is not an observation (§11.4.201(6))\n' "$_et_tok"
            return 1 ;;
    esac

    case "$_et_mut" in
        /*) _et_mut_abs="$_et_mut" ;;
        *)  _et_mut_abs="${_et_repo}/${_et_mut}" ;;
    esac
    if [ ! -f "$_et_mut_abs" ]; then
        printf 'REFUSE\t%s\tMUTATION-ABSENT: cited paired mutation does not resolve: %s\n' "$_et_tok" "$_et_mut_abs"
        return 1
    fi

    case "$_et_ev" in
        /*) _et_ev_abs="$_et_ev" ;;
        *)  _et_ev_abs="${_et_repo}/${_et_ev}" ;;
    esac
    if [ ! -f "$_et_ev_abs" ]; then
        printf 'REFUSE\t%s\tEVIDENCE-ABSENT: recorded RED evidence does not resolve: %s\n' "$_et_tok" "$_et_ev_abs"
        return 1
    fi
    if [ ! -s "$_et_ev_abs" ]; then
        printf 'REFUSE\t%s\tEVIDENCE-ZERO: recorded RED evidence is zero bytes: %s\n' "$_et_tok" "$_et_ev_abs"
        return 1
    fi

    printf 'ACCEPT\t%s\tfirst refusal observed; evidence: %s\n' "$_et_tok" "$_et_ev_abs"
    return 0
}

if [ -n "$selftest" ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    sc_fails=0
    sc_repo="$tmp/repo"; mkdir -p "$sc_repo/m"
    : > "$sc_repo/m/mut.sh"
    printf 'RED transcript: gate refused as expected\n' > "$sc_repo/m/red.log"
    : > "$sc_repo/m/empty.log"

    _sc() { # _sc <name> <expected-rc> <registry> <token>
        "${BASH_SOURCE[0]:-$0}" --registry "$3" --repo-root "$sc_repo" --token "$4" --quiet >/dev/null 2>&1
        _sc_rc=$?
        if [ "$_sc_rc" -ne "$2" ]; then
            echo "SELFCHECK-FAIL: $1 — expected rc=$2, got rc=$_sc_rc" >&2
            sc_fails=$((sc_fails + 1))
        fi
    }

    printf 'CM-GT\tm/mut.sh\tm/red.log\n'   > "$tmp/r_gt.tsv"
    printf 'CM-GF\tm/mut.sh\t\n'            > "$tmp/r_blank.tsv"
    printf 'CM-GF\tm/mut.sh\tPENDING-FIRST-REFUSAL\n' > "$tmp/r_pending.tsv"
    printf 'CM-GF\tm/mut.sh\tm/nope.log\n'  > "$tmp/r_absent.tsv"
    printf 'CM-GF\tm/mut.sh\tm/empty.log\n' > "$tmp/r_zero.tsv"
    printf 'CM-GF\tm/gone.sh\tm/red.log\n'  > "$tmp/r_nomut.tsv"
    printf '# comment only\n'               > "$tmp/r_norow.tsv"
    printf 'CM-GT\tm/mut.sh\tm/red.log\nCM-GT2\tm/mut.sh\tm/red.log\n' > "$tmp/r_two.tsv"

    # golden-TRUE: a resolving, non-empty evidence path lets the PASS count.
    _sc "golden-TRUE observed-first-refusal"          0 "$tmp/r_gt.tsv"      CM-GT
    # golden-FALSE set: every refusal condition must actually refuse.
    _sc "golden-FALSE EVIDENCE-EMPTY (blank field)"   1 "$tmp/r_blank.tsv"   CM-GF
    _sc "golden-FALSE EVIDENCE-EMPTY (PENDING)"       1 "$tmp/r_pending.tsv" CM-GF
    # Hazard surfaced by this gate's own paired mutation test: the sentinel
    # must be rejected by MEANING, not by the accident that no file of that
    # name exists. Plant a real, non-empty file literally named
    # PENDING-FIRST-REFUSAL and require the refusal to hold anyway.
    printf 'a real non-empty file merely named like the sentinel\n' > "$sc_repo/PENDING-FIRST-REFUSAL"
    _sc "golden-FALSE PENDING sentinel even when it RESOLVES" 1 "$tmp/r_pending.tsv" CM-GF
    _sc "golden-FALSE EVIDENCE-ABSENT"                1 "$tmp/r_absent.tsv"  CM-GF
    _sc "golden-FALSE EVIDENCE-ZERO (zero-byte)"      1 "$tmp/r_zero.tsv"    CM-GF
    _sc "golden-FALSE MUTATION-ABSENT"                1 "$tmp/r_nomut.tsv"   CM-GF
    _sc "golden-FALSE NO-ROW"                         1 "$tmp/r_norow.tsv"   CM-GF
    # negative control (§11.4.201(1)): the gate must NOT block indiscriminately
    # — two fully-evidenced rows both accept in one run.
    "${BASH_SOURCE[0]:-$0}" --registry "$tmp/r_two.tsv" --repo-root "$sc_repo" \
        --token CM-GT --token CM-GT2 --quiet >/dev/null 2>&1
    rc_two=$?
    if [ "$rc_two" -ne 0 ]; then
        echo "SELFCHECK-FAIL: negative control — two fully-evidenced tokens were REFUSED (rc=$rc_two); the gate blocks indiscriminately (§11.4.201(1) false-positive refusal)" >&2
        sc_fails=$((sc_fails + 1))
    fi
    # BLIND: unreadable registry is exit 2, never a silent pass or refuse.
    "${BASH_SOURCE[0]:-$0}" --registry "$tmp/does_not_exist.tsv" --repo-root "$sc_repo" \
        --token CM-GT --quiet >/dev/null 2>&1
    rc_blind=$?
    if [ "$rc_blind" -ne 2 ]; then
        echo "SELFCHECK-FAIL: unreadable registry returned rc=$rc_blind, expected BLIND rc=2 (§11.4.252 fail-closed)" >&2
        sc_fails=$((sc_fails + 1))
    fi
    # BLIND: an empty token set must refuse to run, never pass vacuously.
    "${BASH_SOURCE[0]:-$0}" --registry "$tmp/r_gt.tsv" --repo-root "$sc_repo" --quiet >/dev/null 2>&1
    rc_empty=$?
    if [ "$rc_empty" -ne 2 ]; then
        echo "SELFCHECK-FAIL: empty token set returned rc=$rc_empty, expected BLIND rc=2 — a vacuous PASS over zero tokens is a bluff" >&2
        sc_fails=$((sc_fails + 1))
    fi

    if [ "$sc_fails" -ne 0 ]; then
        echo "❌ ${GATE}: SELFCHECK-FAIL — ${sc_fails} self-validation case(s) wrong; this gate mints no verdict" >&2
        exit 1
    fi
    echo "✅ ${GATE}: SELFCHECK PASS — golden-TRUE accepts; blank/PENDING/absent/zero-byte evidence and absent mutation and absent row all REFUSE (the PENDING sentinel refuses even when a real file of that name resolves); two evidenced tokens both accept (no indiscriminate refusal); unreadable registry and empty token set are BLIND"
    exit 0
fi

[ -r "$registry" ] || { echo "${GATE}: BLIND — first-refusal registry not readable: $registry (§11.4.252 fail-closed — refusing rather than treating a missing registry as 'nothing to check')" >&2; exit 2; }

tokens="$(printf '%s' "$tokens" | sed '/^[[:space:]]*$/d')"
if [ -z "$tokens" ]; then
    echo "${GATE}: BLIND — no gate tokens supplied; refusing to report a vacuous PASS over an empty set (supply --token / --tokens-file, §11.4.35 the set is consumer DATA)" >&2
    exit 2
fi

refused=0
checked=0
while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    checked=$((checked + 1))
    line="$(evaluate_token "$tok" "$registry" "$repo_root")"
    st=$?
    if [ "$st" -ne 0 ]; then
        refused=$((refused + 1))
        printf '%s\n' "$line"
    else
        [ -n "$quiet" ] || printf '%s\n' "$line"
    fi
done <<EOF
$tokens
EOF

if [ "$refused" -ne 0 ]; then
    echo "❌ ${GATE}: FAIL — ${refused}/${checked} newly bound gate(s) have NOT been observed refusing; their PASS does not count until a first-refusal row with resolving, non-empty RED evidence lands (FR-022 / §11.4.115(F))"
    exit 1
fi
echo "✅ ${GATE}: PASS — all ${checked} supplied gate token(s) carry an observed first refusal with resolving, non-empty recorded RED evidence"
exit 0
