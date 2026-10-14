#!/usr/bin/env bash
# covenant_propagation_mutation_engine.sh — SHARED §1.1 paired-mutation ENGINE
# for the CM-COVENANT-114-<N>-PROPAGATION gate family.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves a CM-COVENANT-114-<N>-PROPAGATION gate is NOT a bluff gate under the
# §11.4.227(B) anchor-block-integrity contract (block-starts, not bare
# literals; exactly-once; lockstep-identical BY FULL BLOCK CONTENT, not just
# the heading line) AND under the §11.4.35 pointer-inheritance carve-out —
# INCLUDING that the pointer predicate is FENCE-AWARE.
#
# As with the gate engine, every per-anchor mutation test performs the
# IDENTICAL experiment and differs ONLY in the gate name + anchor number, so
# per §11.4.251 the harness lives ONCE here and each
# `cm_covenant_114_<N>_propagation_mutation_test.sh` is a thin wrapper.
#
# ── The fixtures (throwaway mktemp corpora — the REAL repo is never mutated) ─
#   1. MISSING         — a carrier carrying only a mid-body CITATION of the
#                        anchor (no line-anchored block-start) -> gate MUST
#                        FAIL (§11.4.201(7)(a) structure-not-substring).
#   2. DUPLICATED      — one carrier carries the same block-start line TWICE
#                        -> gate MUST FAIL (the F7-class duplication the
#                        legacy bare-literal-presence gates could not see).
#   3. DIVERGENT-HEAD  — every carrier has exactly one block-start, but one
#                        carrier's HEADING line differs byte-for-byte
#                        -> gate MUST FAIL (§11.4.157 lockstep).
#   4. DIVERGENT-BODY  — heading lines byte-identical, one carrier's BODY line
#                        differs -> gate MUST FAIL. A heading-only hash would
#                        miss this entirely; the engine hashes the FULL block.
#   5. FENCE-MISSING   — a real-mirror-shaped carrier that LOST its block but
#                        still carries the FENCED "How inheritance works"
#                        EXAMPLE quoting `## INHERITED FROM ...` -> gate MUST
#                        FAIL with MISSING, NOT a false POINTER-INHERITANCE-SKIP.
#   6. POINTER-OK      — clean fleet PLUS a nested genuine (unfenced) §11.4.35
#                        pointer carrier with ZERO blocks -> gate MUST PASS
#                        (the §11.4.201(1) false-positive-refusal guard, and
#                        the negative control proving fixture 5's fence
#                        awareness did not regress the real carve-out).
#   7. CLEAN           — every carrier carries exactly one byte-identical
#                        full block -> gate MUST PASS (golden-FALSE control:
#                        an untouched clean corpus must NOT be refused).
#   8. ANCHOR-BOUNDARY — every carrier carries the correct block PLUS a
#                        DECOY block-start for a strictly-longer anchor number
#                        sharing this anchor's digits as a prefix (e.g. the
#                        anchor's own digits followed by one more digit)
#                        -> gate MUST PASS (proves the `([^0-9]|$)` boundary:
#                        a prefix-sharing sibling anchor is never counted as
#                        a duplicate of this one).
#   9-18. COMPACT-INDEX + H2-BOUNDARY (added with the 2026-10-14 engine change
#         that lets a one-line compact index entry `- §N … [full → <path>]`
#         stand in for the full block, and ends a block at a `## ` heading).
#         Each case names the engine mutant it kills (ME1..ME6, reviewer-
#         authored in round 2 of the remedy batch atm-prebuild-remedy-const;
#         applied verbatim by covenant_propagation_engine_compact_mutation_test.sh):
#      9  COMPACT-OK             valid target, one block            -> PASS
#     10  COMPACT-MISSING-TARGET  target file absent                 -> FAIL
#     11  COMPACT-DUP-TARGET      target holds the block TWICE, the
#                                 second copy under a `## Relocated`
#                                 heading (the real 11.4.162 shape)  -> FAIL (ME1)
#     12  COMPACT-TAMPERED        target block body differs          -> FAIL
#     13  COMPACT-DOTDOT          pointer `../x` escapes the root    -> FAIL (ME2)
#     14  COMPACT-TRAILER-BAD     mirror-only trailer after compact  -> FAIL (ME3)
#     15  COMPACT-TRAILER-OK      same trailer in every carrier      -> PASS (ME3)
#     16  H2-BOUNDARY             consumer-only `## ` section after
#                                 the block in one carrier           -> PASS (ME4)
#     17  COMPACT-NOT-BULLET      `[full → …]` on a bold block-start,
#                                 not a `- §` compact line           -> FAIL (ME5)
#     18  COMPACT-AT-CARRIER      pointer names another carrier file
#                                 (would make lockstep a tautology)  -> FAIL (ME6)
# The pair only proves the gate genuine if it BOTH fails on every planted
# violation AND passes on every clean/honestly-exempt fixture — the §1.1
# discriminator.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   . "<gates-dir>/lib/covenant_propagation_mutation_engine.sh"
#   covenant_propagation_mutation_main <GATE-NAME>
#
# The engine resolves <GATE-NAME> -> anchor number + the sibling gate script
# path from the DATA PACK `covenant_propagation_anchors.tsv`; it never guesses.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned). No
#   network, no commit, NO mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script + data pack. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.227(B), §11.4.201(1)/(7)(a), §11.4.157,
#   §11.4.35, §11.4.251 (one engine, not 29 forks), §11.4.28 (gate driven via
#   --root, no hardcoded paths).
#
# ── Exit codes (returned to the wrapper) ─────────────────────────────────────
#   0 — the gate FAILs on every planted violation (fixtures 1-5, 10-14, 17,
#       18) AND PASSes on every honest/clean fixture (6-9, 15, 16) — the §1.1
#       proof holds.
#   1 — the gate did not FAIL on a planted violation, or did not PASS on a
#       clean/honestly-exempt fixture.
#   2 — environment error (gate script or data pack missing / unbound name).
#
# Classification: universal (§11.4.17).

_cpme_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

covenant_propagation_mutation_main() {
    local GATE="${1:?covenant_propagation_mutation_main: <gate-name> required}"
    local gates_dir="${_cpme_lib_dir}/.."
    local pack="${COVENANT_PROPAGATION_ANCHORS:-${gates_dir}/covenant_propagation_anchors.tsv}"
    local ANCHOR GATE_SH slug rc=0

    [ -r "$pack" ] || { echo "META: data pack missing: $pack" >&2; return 2; }
    ANCHOR="$(awk -F'\t' -v g="$GATE" '/^#/{next} NF>=2 && $1==g {print $2; found=1; exit} END{exit !found}' "$pack" || true)"
    [ -n "${ANCHOR:-}" ] || { echo "META: gate ${GATE} is not bound to an anchor in ${pack}" >&2; return 2; }

    # gate script name is derived from the anchor number, e.g. 11.4.239 ->
    # cm_covenant_114_239_propagation.sh
    slug="$(printf '%s' "$ANCHOR" | sed 's/^11\.4\.//')"
    GATE_SH="${gates_dir}/cm_covenant_114_${slug}_propagation.sh"
    [ -f "$GATE_SH" ] || { echo "META: gate script missing: $GATE_SH" >&2; return 2; }

    local TMP
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_${slug}_mut.XXXXXX")" || return 2
    # shellcheck disable=SC2064  # TMP is expanded now on purpose: the RETURN trap must remove this call's own dir
    trap "rm -rf '$TMP'" RETURN

    note() { echo "$@"; }
    expect_fail() { # $1=desc  $2..=command
        local desc="$1"; shift
        if "$@" >/dev/null 2>&1; then
            echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
            rc=1
        else
            echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
        fi
    }
    expect_pass() { # $1=desc  $2..=command
        local desc="$1"; shift
        if "$@" >/dev/null 2>&1; then
            echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
        else
            echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false alarm!)"
            rc=1
        fi
    }

    echo "======================================================================"
    echo "§1.1 paired-mutation meta-test for ${GATE} (anchor §${ANCHOR})"
    echo "fixtures under: $TMP"
    echo "======================================================================"

    local BLOCK_LINE BODY_LINE c
    BLOCK_LINE="**§${ANCHOR} — canonical fixture block-start (identical across every carrier).**"
    BODY_LINE="Fixture body line carrying the mandate's substantive text, identical across every carrier."

    _cpme_seed_fleet() { # $1=dir
        mkdir -p "$1"
        for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
            printf '%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" > "$1/$c"
        done
    }

    # --- MUTATION 1: MISSING — mid-body citation only, no block-start ---
    local MUT_MISSING="$TMP/mut_missing"
    _cpme_seed_fleet "$MUT_MISSING"
    printf 'This section composes with §%s(A) as a mid-body citation only.\n' "$ANCHOR" > "$MUT_MISSING/CLAUDE.md"
    expect_fail "MISSING (mid-body citation is not a block-start)" \
        bash "$GATE_SH" --root "$MUT_MISSING" --quiet

    # --- MUTATION 2: DUPLICATED — one carrier has the block-start twice ---
    local MUT_DUP="$TMP/mut_dup"
    _cpme_seed_fleet "$MUT_DUP"
    printf '%s\n%s\n\n%s\n%s\n' "$BLOCK_LINE" "$BODY_LINE" "$BLOCK_LINE" "$BODY_LINE" > "$MUT_DUP/AGENTS.md"
    expect_fail "DUPLICATED (one carrier carries the block twice, F7-class)" \
        bash "$GATE_SH" --root "$MUT_DUP" --quiet

    # --- MUTATION 3: DIVERGENT-HEAD — one carrier's heading line differs ---
    local MUT_DIV_HEAD="$TMP/mut_divergent_head"
    _cpme_seed_fleet "$MUT_DIV_HEAD"
    printf '**§%s — a DIFFERENT (divergent) heading than its siblings.**\n%s\n' "$ANCHOR" "$BODY_LINE" > "$MUT_DIV_HEAD/QWEN.md"
    expect_fail "DIVERGENT-HEAD (one carrier's heading line differs, §11.4.157 lockstep)" \
        bash "$GATE_SH" --root "$MUT_DIV_HEAD" --quiet

    # --- MUTATION 4: DIVERGENT-BODY — headings identical, BODY line differs ---
    local MUT_DIV_BODY="$TMP/mut_divergent_body"
    _cpme_seed_fleet "$MUT_DIV_BODY"
    printf '%s\nA COMPLETELY DIFFERENT body line than every other carrier — same heading, divergent content.\n' \
        "$BLOCK_LINE" > "$MUT_DIV_BODY/GEMINI.md"
    expect_fail "DIVERGENT-BODY (identical heading, divergent body — the body-drift class)" \
        bash "$GATE_SH" --root "$MUT_DIV_BODY" --quiet

    # --- MUTATION 5: FENCE-MISSING — block lost, fenced inheritance EXAMPLE remains ---
    local MUT_FENCE="$TMP/mut_fence_missing"
    _cpme_seed_fleet "$MUT_FENCE"
    cat > "$MUT_FENCE/CLAUDE.md" <<'FENCE_EOF'
## How inheritance works

A consuming project's root `CLAUDE.md` MUST start with a clearly-marked
inheritance pointer:

```markdown
## INHERITED FROM constitution/CLAUDE.md

All rules in `constitution/CLAUDE.md` (and the `constitution/Constitution.md`
it references) apply unconditionally. The project-specific rules below
extend them.
```

Claude Code supports the `@path/to/file` import syntax natively.
FENCE_EOF
    expect_fail "FENCE-MISSING (block lost, only the fenced inheritance EXAMPLE remains)" \
        bash "$GATE_SH" --root "$MUT_FENCE" --quiet

    # --- FIXTURE 6: POINTER-OK — clean fleet + nested genuine pointer carrier ---
    local POINTER_FLEET="$TMP/prop_pointer_ok"
    _cpme_seed_fleet "$POINTER_FLEET"
    mkdir -p "$POINTER_FLEET/nested_submodule"
    printf '## INHERITED FROM constitution/CLAUDE.md\n\nAll rules apply unconditionally. Engine-rules-only mirror, zero restated anchor blocks.\n' \
        > "$POINTER_FLEET/nested_submodule/CLAUDE.md"
    expect_pass "POINTER-OK (nested §11.4.35 pointer carrier with zero blocks -> honest SKIP, not FAIL)" \
        bash "$GATE_SH" --root "$POINTER_FLEET" --quiet

    # --- FIXTURE 7: CLEAN (golden-FALSE control — untouched corpus must PASS) ---
    local CLEAN_FLEET="$TMP/prop_clean"
    _cpme_seed_fleet "$CLEAN_FLEET"
    expect_pass "clean fleet (exactly-once + byte-identical full-block everywhere)" \
        bash "$GATE_SH" --root "$CLEAN_FLEET" --quiet

    # --- FIXTURE 8: ANCHOR-BOUNDARY — a prefix-sharing DECOY anchor must not count ---
    # Proves the `([^0-9]|$)` boundary in the block-start regex: a strictly
    # longer sibling anchor whose digits START with this anchor's digits (e.g.
    # 11.4.<N>0) is a DIFFERENT anchor and must never be counted as a second
    # block-start for this one (that would be a false DUPLICATED refusal —
    # the §11.4.201(1) FAIL-bluff class).
    local DECOY_FLEET="$TMP/prop_decoy"
    mkdir -p "$DECOY_FLEET"
    for c in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
        printf '%s\n%s\n\n**§%s0 — a DIFFERENT, strictly-longer sibling anchor sharing this one'"'"'s digits as a prefix.**\nDecoy body line.\n' \
            "$BLOCK_LINE" "$BODY_LINE" "$ANCHOR" > "$DECOY_FLEET/$c"
    done
    expect_pass "ANCHOR-BOUNDARY (prefix-sharing decoy anchor §${ANCHOR}0 is not a duplicate)" \
        bash "$GATE_SH" --root "$DECOY_FLEET" --quiet

    # --- FIXTURES 9-18: COMPACT-INDEX equivalence + H2 block boundary ---------
    # A compact carrier is CLAUDE.md holding ONE line `- §N … [full → <path>]`;
    # the other carriers hold the full block. The pointed-to file is NOT a
    # carrier (its basename is not one of the four carrier names).
    local COMPACT_LINE TRAILER FULLDOC_HEAD OTHER_BLOCK
    COMPACT_LINE="- §${ANCHOR} — compact index entry for the fixture block [full → docs/full_anchors.md] · refs: §1.1 §${ANCHOR}"
    TRAILER="Mirror-resident trailer paragraph that follows the block."
    FULLDOC_HEAD="# Full anchor blocks (fixture index document)"
    OTHER_BLOCK="**§11.4.9999 — an unrelated later block in the full document.**"
    _cpme_full_doc() { # $1=file  $2=body line (default BODY_LINE)  $3=copies (1|2)
        local body="${2:-$BODY_LINE}" copies="${3:-1}"
        mkdir -p "$(dirname "$1")"
        {
            printf '%s

%s
%s

---

%s
Unrelated body.
' "$FULLDOC_HEAD" "$BLOCK_LINE" "$body" "$OTHER_BLOCK"
            if [ "$copies" = 2 ]; then
                printf '
---


## Relocated by a compaction tool

%s
%s
' "$BLOCK_LINE" "$body"
            fi
        } > "$1"
    }
    _cpme_compact_fleet() { # $1=dir  — 3 full carriers + compact CLAUDE.md
        mkdir -p "$1"
        for c in AGENTS.md QWEN.md GEMINI.md; do
            printf '%s
%s
' "$BLOCK_LINE" "$BODY_LINE" > "$1/$c"
        done
        printf '%s
' "$COMPACT_LINE" > "$1/CLAUDE.md"
    }

    local F9="$TMP/cmp_ok"
    _cpme_compact_fleet "$F9"; _cpme_full_doc "$F9/docs/full_anchors.md"
    expect_pass "COMPACT-OK (compact entry -> single valid full block, compared via the target)" \
        bash "$GATE_SH" --root "$F9" --quiet

    local F10="$TMP/cmp_missing"
    _cpme_compact_fleet "$F10"
    expect_fail "COMPACT-MISSING-TARGET (pointed-to file absent -> compact hash kept -> DIVERGENT)" \
        bash "$GATE_SH" --root "$F10" --quiet

    local F11="$TMP/cmp_dup_target"
    _cpme_compact_fleet "$F11"; _cpme_full_doc "$F11/docs/full_anchors.md" "$BODY_LINE" 2
    expect_fail "COMPACT-DUP-TARGET (target carries the block twice, real 11.4.162 relocation shape; kills ME1)" \
        bash "$GATE_SH" --root "$F11" --quiet

    local F12="$TMP/cmp_tampered"
    _cpme_compact_fleet "$F12"; _cpme_full_doc "$F12/docs/full_anchors.md" "A TAMPERED body line in the pointed-to full block."
    expect_fail "COMPACT-TAMPERED (target block body differs from the full carriers)" \
        bash "$GATE_SH" --root "$F12" --quiet

    local F13="$TMP/cmp_dotdot/fleet"
    _cpme_compact_fleet "$F13"
    printf '%s
' "- §${ANCHOR} — compact index entry for the fixture block [full → ../full_outside.md] · refs: §1.1" > "$F13/CLAUDE.md"
    _cpme_full_doc "$TMP/cmp_dotdot/full_outside.md"
    expect_fail "COMPACT-DOTDOT (pointer escapes the root via '..' even though the outside target is valid; kills ME2)" \
        bash "$GATE_SH" --root "$F13" --quiet

    local F14="$TMP/cmp_trailer_bad"
    _cpme_compact_fleet "$F14"; _cpme_full_doc "$F14/docs/full_anchors.md"
    printf '%s
%s
' "$COMPACT_LINE" "$TRAILER" > "$F14/CLAUDE.md"
    expect_fail "COMPACT-TRAILER-BAD (a trailer only the compact carrier has is compared and diverges; kills ME3)" \
        bash "$GATE_SH" --root "$F14" --quiet

    local F15="$TMP/cmp_trailer_ok"
    mkdir -p "$F15"
    for c in AGENTS.md QWEN.md GEMINI.md; do
        printf '%s
%s
%s
' "$BLOCK_LINE" "$BODY_LINE" "$TRAILER" > "$F15/$c"
    done
    printf '%s
%s
' "$COMPACT_LINE" "$TRAILER" > "$F15/CLAUDE.md"
    _cpme_full_doc "$F15/docs/full_anchors.md"
    expect_pass "COMPACT-TRAILER-OK (target block + the shared trailer equals every full carrier; kills ME3)" \
        bash "$GATE_SH" --root "$F15" --quiet

    local F16="$TMP/h2_boundary"
    _cpme_seed_fleet "$F16"
    printf '%s
%s

## A consumer-only project section

Project-specific text the other carriers do not carry.
' \
        "$BLOCK_LINE" "$BODY_LINE" > "$F16/AGENTS.md"
    expect_pass "H2-BOUNDARY (a consumer-only '## ' section after the block is not part of the block; kills ME4)" \
        bash "$GATE_SH" --root "$F16" --quiet

    local F17="$TMP/cmp_not_bullet"
    _cpme_compact_fleet "$F17"; _cpme_full_doc "$F17/docs/full_anchors.md"
    printf '**§%s — a bold block-start that merely mentions [full → docs/full_anchors.md]**
' "$ANCHOR" > "$F17/CLAUDE.md"
    expect_fail "COMPACT-NOT-BULLET (only a '- §N' compact line may delegate; a bold block-start may not; kills ME5)" \
        bash "$GATE_SH" --root "$F17" --quiet

    local F18="$TMP/cmp_at_carrier"
    _cpme_compact_fleet "$F18"
    printf '%s
' "- §${ANCHOR} — compact index entry pointing at a sibling carrier [full → AGENTS.md] · refs: §1.1" > "$F18/CLAUDE.md"
    expect_fail "COMPACT-AT-CARRIER (a pointer to another carrier would compare a block with itself; kills ME6)" \
        bash "$GATE_SH" --root "$F18" --quiet

    echo "======================================================================"
    if [ "$rc" -eq 0 ]; then
        echo "✅ META PASS: ${GATE} is a genuine (non-bluff) gate"
    else
        echo "❌ META FAIL: ${GATE} failed the §1.1 discriminator"
    fi
    echo "======================================================================"
    return "$rc"
}
