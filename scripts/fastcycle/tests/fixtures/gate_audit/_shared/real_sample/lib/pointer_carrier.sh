#!/usr/bin/env bash
# pointer_carrier.sh — SHARED §11.4.35 pointer-inheritance predicate for the
# CM-COVENANT-114-NNN-PROPAGATION gate family (both the legacy bare-literal
# gates and the newer fence-aware §11.4.227(B) block-integrity gates).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# A §11.4.35 POINTER-INHERITANCE consumer (a governance carrier whose FIRST
# real, non-fenced, line-anchored heading is `## INHERITED FROM ...`) is an
# engine-rules-only mirror that legitimately inherits every universal anchor BY
# POINTER — it deliberately does NOT restate every full anchor block verbatim.
# A propagation gate that FAILs such a carrier for "lacking" an anchor literal
# is a §11.4.201(1) FALSE-POSITIVE refusal (a FAIL-bluff). This helper is the
# single canonical predicate that lets every gate skip a genuine pointer
# consumer — inherited BY REFERENCE (§11.4.28 / §11.4.177), never copied.
#
# It exists to CLOSE the legacy/fence-aware divergence: the fence-aware gates
# (§11.4.230-235) already carried this predicate INLINE; the ~12 older
# bare-literal gates (e.g. cm_covenant_114_213_propagation.sh) never did, so
# they false-positive-refused the four
# constitution/submodules/helix_perf_cache/{CLAUDE,AGENTS,QWEN,GEMINI}.md
# pointer consumers (48 false MISSING lines across the family). Extracting the
# predicate here + sourcing it from both families removes every copy.
#
# ── The predicate (§11.4.201(7)(a) match-structure-not-substring) ────────────
# FENCE-AWARE: a bare `grep -qE '^## INHERITED FROM '` false-MATCHes the "How
# inheritance works" EXAMPLE that the canonical constitution mirrors quote
# INSIDE a fenced ```markdown code block (constitution/CLAUDE.md, GEMINI.md) —
# that fenced text is a CARRIER quoting the heading, never a real pointer
# heading. This predicate tracks fence state (```/~~~ toggles) and only
# recognises `## INHERITED FROM ` OUTSIDE any fence as a genuine pointer. It
# returns 0 (true) iff a real, non-fenced pointer heading exists — otherwise
# non-zero. This is BYTE-IDENTICAL to the awk that shipped inline in the
# fence-aware gates (md5 0a8d485d4587ce104f87ac17e079c1f9 of the function body).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   source "$(dirname "$0")/lib/pointer_carrier.sh"     # from a gate script
#   is_pointer_carrier "<file.md>"   # exit 0 = pointer consumer, 1 = not
#
#   bash lib/pointer_carrier.sh --selftest              # runnable golden test
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   $1 to is_pointer_carrier: path to a governance carrier .md file.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   is_pointer_carrier: exit status only (no stdout). --selftest prints PASS/FAIL.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no device mutation).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, awk. Parses clean under bash -n and sh -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.35 (pointer-inheritance consumers), §11.4.201(1) (false-positive
#   refusal is a FAIL-bluff), §11.4.201(7)(a) (match structure, not substring),
#   §11.4.28 / §11.4.177 (inherited by reference, never copied), §11.4.227(B)
#   (block-integrity gates that ALSO consume this predicate), §11.4.107(10)
#   (self-validated with golden-good + golden-bad-with-carrier fixtures).

# is_pointer_carrier <file> — returns 0 iff <file> carries a real, non-fenced,
# line-anchored `## INHERITED FROM ...` heading (a §11.4.35 pointer consumer).
is_pointer_carrier() {
    awk '
        BEGIN { fenced = 0; found = 0 }
        /^(```|~~~)/ { fenced = !fenced; next }
        !fenced && /^## INHERITED FROM / { found = 1; exit }
        END { exit !found }
    ' "$1"
}

# ── Self-test (§11.4.107(10) / §11.4.224(A)) ─────────────────────────────────
# Runs ONLY when this file is executed directly (not when sourced). Exercises
# the predicate through its REAL invocation path against golden fixtures:
#   golden-good      : a genuine pointer consumer  -> MUST be recognised (exit 0)
#   golden-bad       : a full-restating consumer with the heading only INSIDE a
#                      ```-fenced code block (a CARRIER) -> MUST NOT be recognised
#   negative         : a plain doc with no heading at all -> MUST NOT be recognised
#   golden-bad-midline: heading appears ONLY mid-line inside backticks in prose
#                      (the LIVE constitution/CLAUDE.md §11.4.35 shape) -> MUST NOT
#                      be recognised (guards the `^` line-start anchor)
#   golden-bad-tilde : heading inside a `~~~` fence -> MUST NOT be recognised
#                      (guards ~~~ fence tracking, not just ```)
# A predicate that fails golden-good, or recognises any golden-bad/negative
# decoy, is itself the bluff (§11.4.201(1)/(3) / §11.4.107(10) / §11.4.194(6)(d)).
_pointer_carrier_selftest() {
    local tmp rc fails=0
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    # golden-good: real pointer consumer (heading outside any fence)
    printf '# CLAUDE.md\n\n## INHERITED FROM constitution/CLAUDE.md\n\nEngine rules below.\n' > "$tmp/good.md"
    # golden-bad-with-carrier: heading appears ONLY inside a fenced block
    printf '# Constitution CLAUDE.md\n\nExample of the pointer block:\n\n```markdown\n## INHERITED FROM constitution/CLAUDE.md\n```\n\nFull anchor text follows.\n' > "$tmp/bad_carrier.md"
    # negative control: no pointer heading anywhere
    printf '# Some project doc\n\nNo inheritance heading here.\n' > "$tmp/negative.md"
    # golden-bad MID-LINE-MENTION (§11.4.201(3) decoy — guards the `^` line-start
    # anchor): the heading text appears ONLY mid-line inside backticks in prose,
    # NOT as a line-anchored `## ` heading — exactly the shape LIVE in
    # constitution/CLAUDE.md's §11.4.35 section. A predicate that drops the `^`
    # anchor (bare-substring match) would wrongly recognise this as a pointer
    # consumer -> a full mirror missing an anchor would be silently skipped.
    printf '# Constitution CLAUDE.md\n\nThe pointer form is a `## INHERITED FROM constitution/CLAUDE.md` heading referenced mid-line in prose here.\n\nFull anchor text follows.\n' > "$tmp/bad_midline.md"
    # golden-bad TILDE-FENCED carrier (§11.4.201(3) decoy — guards ~~~ fence
    # tracking): the heading sits inside a `~~~` fenced block (not ```); a
    # predicate that only toggles the fence on ``` would wrongly recognise it.
    printf '# Constitution QWEN.md\n\nExample of the pointer block:\n\n~~~markdown\n## INHERITED FROM constitution/CLAUDE.md\n~~~\n\nFull anchor text follows.\n' > "$tmp/bad_tilde.md"

    if is_pointer_carrier "$tmp/good.md"; then
        echo "PASS golden-good: real pointer consumer recognised"
    else
        echo "FAIL golden-good: real pointer consumer NOT recognised"; fails=$((fails+1))
    fi

    if is_pointer_carrier "$tmp/bad_carrier.md"; then
        echo "FAIL golden-bad: fenced-carrier heading wrongly recognised as pointer"; fails=$((fails+1))
    else
        echo "PASS golden-bad: fenced-carrier heading correctly NOT recognised"
    fi

    if is_pointer_carrier "$tmp/negative.md"; then
        echo "FAIL negative: no-heading doc wrongly recognised as pointer"; fails=$((fails+1))
    else
        echo "PASS negative: no-heading doc correctly NOT recognised"
    fi

    if is_pointer_carrier "$tmp/bad_midline.md"; then
        echo "FAIL golden-bad-midline: mid-line backticked heading wrongly recognised (^ line-start anchor bypassed)"; fails=$((fails+1))
    else
        echo "PASS golden-bad-midline: mid-line backticked heading correctly NOT recognised"
    fi

    if is_pointer_carrier "$tmp/bad_tilde.md"; then
        echo "FAIL golden-bad-tilde: ~~~-fenced heading wrongly recognised (tilde fence not tracked)"; fails=$((fails+1))
    else
        echo "PASS golden-bad-tilde: ~~~-fenced heading correctly NOT recognised"
    fi

    if [ "$fails" -eq 0 ]; then
        echo "pointer_carrier.sh selftest: PASS (5/5)"
        return 0
    fi
    echo "pointer_carrier.sh selftest: FAIL ($fails failing)"
    return 1
}

# Only run the self-test when invoked directly; sourcing must be side-effect-free.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
    case "${1:-}" in
        --selftest) _pointer_carrier_selftest ;;
        *) echo "pointer_carrier.sh: source me, or run with --selftest" >&2; exit 2 ;;
    esac
fi
