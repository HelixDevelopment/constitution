#!/usr/bin/env bash
# cm_oracle_strategy_named_and_independent.sh — CM-ORACLE-STRATEGY-NAMED-AND-
# INDEPENDENT gate (anchor §11.4.245).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.245 mandates that every test FIRST identify its ORACLE — the
# mechanism deciding PASS vs FAIL for the input it drives — drawn from a
# CLOSED 7-member strategy set: SPECIFIED, DERIVED, METAMORPHIC,
# GOLDEN-MASTER/CHARACTERIZATION, INVARIANT, STATISTICAL, HUMAN ("NO other
# classes"). Authoring a test WITHOUT naming its oracle strategy produces the
# "test agrees with code" anti-pattern: a test that asserts whatever the code
# under test happens to produce, so it passes as long as the code produces
# ANYTHING, never catching a wrong output.
#
# This gate is the HARD-GATED, LITERAL-CHECKABLE half of the anchor: it walks
# Python test-function definitions and FAILs when a test has no oracle-
# strategy annotation, OR when the annotated value is not one of the closed
# seven (a typo'd / invented strategy name is caught too, per the anchor's
# "NO other classes").
#
# ── Convention (this is the machine-checkable contract, documented here
#    because no such convention pre-existed in the corpus) ──────────────────
# Every `def test_*(` / `async def test_*(` function MUST carry, either as a
# trailing/preceding `#`-comment within 3 lines of the `def` line, OR as a
# line inside the function's own docstring, the pattern:
#
#     oracle: <STRATEGY>
#
# (case-insensitive on both "oracle" and the strategy token; hyphens and
# underscores are interchangeable — "GOLDEN-MASTER" and "GOLDEN_MASTER" are
# the same closed-set member). <STRATEGY> MUST be one of:
#     SPECIFIED | DERIVED | METAMORPHIC | GOLDEN_MASTER | CHARACTERIZATION |
#     INVARIANT | STATISTICAL | HUMAN
#
# ── Deliberate scope (honest, stated tradeoff — §11.4.6) ────────────────────
# This gate verifies the anchor's NAMED-strategy invariant (a literal,
# mechanically-checkable presence-and-closed-set-membership check). It does
# NOT verify STRUCTURAL INDEPENDENCE (that the oracle's source of expected
# value is genuinely different from the code under test) — proving that is a
# semantic / data-flow property this text scanner cannot honestly claim to
# decide. It also does NOT verify that a paired §1.1 mutation flips the
# oracle (§11.4.245's third reviewer-verification item) — that is a runtime
# property of the test suite, not a static-source property. Both remaining
# invariants stay §11.4.194/§11.4.142 human/reviewer territory, never
# silently assumed satisfied by this gate's PASS.
#
# Function-boundary detection is indentation-based (POSIX-portable awk, no
# AST parser) — a bounded heuristic that assumes conventional PEP-8-style
# indentation; a test function using tabs-and-spaces inconsistently could, in
# principle, mis-detect its own boundary. This limitation is documented, not
# silent (§11.4.6).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_oracle_strategy_named_and_independent.sh [--root <dir>] [--quiet]
#     --root <dir>   scan root (default: $ORACLE_GUARD_ROOT or the gate-location default: superproject if vendored as a submodule, else the canon repo itself)
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     -h|--help      print this header
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   ORACLE_GUARD_ROOT      default scan root (else --root, else the gate-location default, see scripts/lib/default_scan_root.sh)
#   ORACLE_GUARD_GLOB      -iname glob for candidate test files
#                           (default: "*test*.py")
#   ORACLE_GUARD_EXCLUDE   space-separated dir-name globs to prune
#                          (default: ".git node_modules vendor .venv
#                           __pycache__ scripts/gates out build dist")
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-violation evidence line (file:line of the `def test_...` + reason:
#   missing annotation vs. unknown strategy value) + a final verdict.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no test is ever executed — the
#   scanner only reads source text).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, awk (POSIX-portable). Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.245 (the anchor enforced — the closed 7-member oracle-strategy
#   set), §11.4.201(1)/(7)(a) (false-positive refusal is a FAIL-bluff; match
#   structure not substring), §11.4.6 (honest documented bounded limitation),
#   §11.4.28/§11.4.35 (project-agnostic, env-var-driven), §1.1 (paired
#   mutation: cm_oracle_strategy_named_and_independent_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (every test function names a valid closed-set oracle strategy,
#       or SKIP: no candidate test files / no test functions found).
#   1 — FAIL (a test function has no oracle annotation, or an unknown one).
#   2 — environment / argument error.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT"
ANCHOR="11.4.245"

root="${ORACLE_GUARD_ROOT:-}"   # empty => resolved from the gate location after arg parsing (lib/default_scan_root.sh), NOT from cwd
glob="${ORACLE_GUARD_GLOB:-*test*.py}"
quiet=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root) root="$2"; shift 2 ;;
        --glob) glob="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) sed -n '1,90p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

if [ -z "$root" ]; then
    # shellcheck source=/dev/null
    . "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/default_scan_root.sh" 2>/dev/null \
        && root="$(cm_default_scan_root "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)")"
    [ -n "$root" ] || { echo "${GATE}: cannot resolve a default scan root from the gate location; pass --root" >&2; exit 2; }
fi

[ -d "$root" ] || { echo "${GATE}: scan root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

excludes="${ORACLE_GUARD_EXCLUDE:-.git node_modules vendor .venv __pycache__ scripts/gates out build dist}"

prune_expr=()
for ex in $excludes; do
    case "$ex" in
        */*) prune_expr+=(-path "*/${ex}" -o -path "*/${ex}/*" -o) ;;
        *)   prune_expr+=(-name "$ex" -o) ;;
    esac
done
if [ "${#prune_expr[@]}" -gt 0 ]; then
    unset 'prune_expr[${#prune_expr[@]}-1]'
fi

mapfile -d '' -t files < <(
    if [ "${#prune_expr[@]}" -gt 0 ]; then
        find "$root" -type d \( "${prune_expr[@]}" \) -prune -o -type f -iname "$glob" -print0
    else
        find "$root" -type f -iname "$glob" -print0
    fi
)

if [ "${#files[@]}" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no candidate test files under scan (root=$root, glob=$glob)"
    exit 0
fi

AWK_SCRIPT='
BEGIN {
    split("SPECIFIED DERIVED METAMORPHIC GOLDEN_MASTER CHARACTERIZATION INVARIANT STATISTICAL HUMAN", ok_arr, " ")
    for (n = 1; n in ok_arr; n++) ok[ok_arr[n]] = 1
}
{ lines[NR] = $0 }
END {
    total = NR
    for (i = 1; i <= total; i++) {
        line = lines[i]
        if (match(line, /^[ \t]*(async[ \t]+)?def[ \t]+test_[A-Za-z0-9_]*[ \t]*\(/)) {
            indent = 0
            while (indent + 1 <= length(line)) {
                c = substr(line, indent + 1, 1)
                if (c == " " || c == "\t") indent++
                else break
            }
            fend = total + 1
            for (k = i + 1; k <= total; k++) {
                kl = lines[k]
                if (kl ~ /^[ \t]*$/) continue
                kindent = 0
                while (kindent + 1 <= length(kl)) {
                    c = substr(kl, kindent + 1, 1)
                    if (c == " " || c == "\t") kindent++
                    else break
                }
                if (kindent <= indent) { fend = k; break }
            }
            found = 0
            bad_val = ""
            # ── (1) BACKWARD bounded scan for a PRECEDING annotation ────────
            # Bounded by: at most 3 lines back, AND NEVER crossing a blank
            # line or another def/class boundary. Without this boundary a
            # naive "scan the preceding N lines" search can bleed BACKWARD
            # into a PRIOR test functions own body and pick up ITS oracle
            # annotation as if it belonged to THIS function -- a real
            # cross-contamination false-negative (§11.4.201 PASS-bluff)
            # caught and fixed during this gates own smoke-testing.
            back_limit = i - 3
            if (back_limit < 1) back_limit = 1
            for (k = i - 1; k >= back_limit; k--) {
                kl = lines[k]
                if (kl ~ /^[ \t]*$/) break
                if (kl ~ /^[ \t]*(async[ \t]+)?def[ \t]/) break
                if (kl ~ /^[ \t]*class[ \t]/) break
                if (match(kl, /[Oo][Rr][Aa][Cc][Ll][Ee][ \t]*:[ \t]*[A-Za-z_-]+/)) {
                    m = substr(kl, RSTART, RLENGTH)
                    cp = index(m, ":")
                    val = substr(m, cp + 1)
                    gsub(/^[ \t]+/, "", val)
                    gsub(/[ \t]+$/, "", val)
                    val = toupper(val)
                    gsub(/-/, "_", val)
                    if (val in ok) { found = 1 } else { bad_val = val }
                    break
                }
            }
            # ── (2) FORWARD scan within THIS functions own body [i, fend) ──
            # Safe by construction: bounded to this function own extent,
            # can never see a prior functions content.
            if (!found) {
                for (k = i; k < fend; k++) {
                    kl = lines[k]
                    if (match(kl, /[Oo][Rr][Aa][Cc][Ll][Ee][ \t]*:[ \t]*[A-Za-z_-]+/)) {
                        m = substr(kl, RSTART, RLENGTH)
                        cp = index(m, ":")
                        val = substr(m, cp + 1)
                        gsub(/^[ \t]+/, "", val)
                        gsub(/[ \t]+$/, "", val)
                        val = toupper(val)
                        gsub(/-/, "_", val)
                        if (val in ok) { found = 1; bad_val = "" } else { bad_val = val }
                        break
                    }
                }
            }
            if (!found) {
                if (bad_val != "") {
                    print i "\tUNKNOWN_STRATEGY:" bad_val "\t" line
                } else {
                    print i "\tMISSING\t" line
                }
            }
        }
    }
}
'

violations=0
for f in "${files[@]}"; do
    # NOTE: unlike gate 1 (dangerous call-site detection), this gate's entire
    # mechanism IS the comment/docstring annotation -- stripping comment-only
    # lines here would destroy the very signal being searched for. Feed the
    # raw file content to the awk scanner directly.
    hits="$(awk "$AWK_SCRIPT" "$f" 2>/dev/null || true)"
    [ -n "$hits" ] || continue
    while IFS=$'\t' read -r lineno reason defline; do
        [ -n "$lineno" ] || continue
        violations=$(( violations + 1 ))
        case "$reason" in
            UNKNOWN_STRATEGY:*)
                strat="${reason#UNKNOWN_STRATEGY:}"
                echo "❌ ${GATE}: FAIL — ${f}:${lineno}: oracle strategy '${strat}' is not in the closed 7-member set (§${ANCHOR})"
                ;;
            *)
                echo "❌ ${GATE}: FAIL — ${f}:${lineno}: no oracle-strategy annotation found (§${ANCHOR})"
                ;;
        esac
        echo "   ${defline# }"
    done <<< "$hits"
done

echo "======================================================================"
if [ "$violations" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${violations} test function(s) with no valid closed-set oracle-strategy annotation (§${ANCHOR})"
    exit 1
fi
echo "✅ ${GATE}: PASS — every scanned test function names a valid closed-set oracle strategy (§${ANCHOR})"
exit 0
