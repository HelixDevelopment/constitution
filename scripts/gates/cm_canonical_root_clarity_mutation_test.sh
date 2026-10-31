#!/usr/bin/env bash
# cm_canonical_root_clarity_mutation_test.sh — §1.1 paired-mutation meta-test
# for CM-CANONICAL-ROOT-CLARITY (§11.4.35).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-CANONICAL-ROOT-CLARITY is not a bluff gate: that it REFUSES when
# the §11.4.35 invariant is genuinely broken, and does NOT refuse when it is
# genuinely held.
#
# ── This mutation is NOT a tautology (§11.4.115(F)) ─────────────────────────
# A mutation whose diff only DELETES the literal strings the gate greps for is
# a refused tautology — it proves only that grep finds what is there. Every
# mutation below instead breaks the REAL invariant:
#
#   M1  ADDS a live `## INHERITED FROM` heading to a canonical-root file.
#       Nothing is deleted. The canonical root now declares itself a
#       downstream consumer — the exact inheritance-direction inversion
#       §11.4.35 exists to forbid.
#   M2  ADDS a live `@constitution/...` import pointer to a canonical-root
#       file (the second pointer form §11.4.35(a) names). Nothing deleted.
#   M3  MOVES the consumer's pointer from live text INTO a fenced code block.
#       The literal string the gate greps for is STILL PRESENT in the file,
#       byte-for-byte — only its STRUCTURE changed from a live pointer to a
#       carrier. A substring-matching gate would still pass; a
#       structure-matching gate must refuse. This is the sharpest of the
#       three, because a string-deletion tautology cannot express it.
#   M4  REMOVES one canonical file (invariant b).
#   M5  ADDS a live `@submodules/constitution/...` import (the standard-
#       layout pointer form) to a canonical-root file. Nothing deleted.
#   M6  STANDARD LAYOUT, consumer root DERIVED (no --consumer-root): the
#       consumer's pointer is demoted to a fenced carrier. Proves the gate
#       audits the REAL consumer (<root>, not <root>/submodules) in that layout:
#       a gate that derived the wrong root would refuse for the wrong reason,
#       which G4 below rules out.
#
# ── The false-positive guard runs too (§11.4.201(1)) ────────────────────────
# G1 asserts the gate PASSES a correct fixture whose canonical CLAUDE.md
# carries the pointer text inside a fence — the real corpus's own shape
# (constitution/CLAUDE.md documents the pointer in a ```markdown block). A
# gate that refused this would be a FAIL-bluff, as forbidden as a pass-bluff.
# G2 asserts the gate refuses BLIND (exit 2) rather than reporting a false
# absence when its control needle cannot see.
# G4 asserts a correct STANDARD-layout tree (<root>/submodules/constitution,
# consumer root derived, pointer `@submodules/constitution/CLAUDE.md`) PASSES.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_canonical_root_clarity_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes fixture trees under $TMPDIR (trap-cleaned on EXIT).
#   NEVER mutates the real canonical root or the real consumer tree — every
#   mutation is applied to a COPY, so a crashed run cannot leave the live
#   governance files altered (§9.2).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, mktemp, sed, the sibling cm_canonical_root_clarity.sh.
#   Parses clean under bash -n AND sh -n (§11.4.67).
#
# ── Cross-references ────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.35, §11.4.115(F) (no string-deletion
#   tautologies), §11.4.201(1) (false-positive refusal is a FAIL-bluff),
#   §11.4.201(7)(a)/(b) (carrier vs thing; control needle).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected verdict.
#   1 — at least one sub-case produced the wrong verdict (bluff or false alarm).
#   2 — environment error (the gate script is missing).
#
# Classification: universal (§11.4.17).

set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="${SELF_DIR}/cm_canonical_root_clarity.sh"
[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_crc_mut.XXXXXX")" || exit 2
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0

# mk <name> -> builds a CORRECT fixture (canonical root + consumer) and
# prints its path. The canonical CLAUDE.md deliberately mirrors the real
# corpus: the pointer text appears ONLY inside a fenced block, as documentation.
mk() {
    _d="${TMP}/$1"
    mkdir -p "${_d}/constitution"
    printf '# Constitution\n\n## Purpose\n\nUniversal rules.\n\n## Scope\n\nAll consumers.\n' \
        > "${_d}/constitution/Constitution.md"
    printf '# Base AGENTS\n\n## Agent Rules\n\nRules.\n\n## Testing\n\nMore rules.\n' \
        > "${_d}/constitution/AGENTS.md"
    {
        printf '# Base CLAUDE\n\n## How Inheritance Works\n\n'
        printf 'A consuming project root CLAUDE.md must start with:\n\n'
        printf '```markdown\n'
        printf '## INHERITED FROM constitution/CLAUDE.md\n\n'
        printf 'All rules apply unconditionally.\n'
        printf '```\n\n'
        printf '## Development Principles\n\nNo bluff.\n'
    } > "${_d}/constitution/CLAUDE.md"
    {
        printf '# Consumer CLAUDE\n\n'
        printf '## INHERITED FROM constitution/CLAUDE.md\n\n'
        printf 'All rules in constitution/CLAUDE.md apply unconditionally.\n\n'
        printf '## Project Overview\n\nProject-specific rules.\n'
    } > "${_d}/CLAUDE.md"
    printf '%s\n' "$_d"
}

run_gate() {
    _fx="$1"
    "$GATE" --const-dir "${_fx}/constitution" --consumer-root "${_fx}" --quiet >/dev/null 2>&1
}

expect_exit() {
    _desc="$1"; _want="$2"; _fx="$3"
    run_gate "$_fx"
    _got=$?
    if [ "$_got" -eq "$_want" ]; then
        echo "META OK:   ${_desc} (exit ${_got})"
    else
        echo "META FAIL: ${_desc} — expected exit ${_want}, got ${_got}"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-CANONICAL-ROOT-CLARITY (§11.4.35)"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- G1. FALSE-POSITIVE GUARD: correct tree, fenced carrier present -> PASS --
FX_GOOD="$(mk good)"
expect_exit "G1 golden-good: correct tree (canonical pointer text only as a fenced carrier)" 0 "$FX_GOOD"

# --- M1. ADD a live inheritance heading to a canonical file -----------------
FX_M1="$(mk mut1)"
{
    printf '\n## INHERITED FROM some-upstream/CLAUDE.md\n\n'
    printf 'This canonical file now claims to inherit from something else.\n'
} >> "${FX_M1}/constitution/CLAUDE.md"
expect_exit "M1 mutation: canonical root gains a LIVE '## INHERITED FROM' heading" 1 "$FX_M1"

# --- M2. ADD a live @import pointer to a canonical file ---------------------
FX_M2="$(mk mut2)"
printf '\n@constitution/CLAUDE.md\n' >> "${FX_M2}/constitution/AGENTS.md"
expect_exit "M2 mutation: canonical root gains a LIVE '@constitution/...' import" 1 "$FX_M2"

# --- M3. STRUCTURE-ONLY mutation: consumer pointer becomes a carrier --------
# The literal '## INHERITED FROM constitution/CLAUDE.md' is STILL in the file
# (verified below); only its structure changed. A substring gate passes here;
# a structure gate must refuse. This is the anti-tautology case.
FX_M3="$(mk mut3)"
{
    printf '# Consumer CLAUDE\n\n'
    printf '## Project Overview\n\n'
    printf 'Here is the pointer a consumer is supposed to write:\n\n'
    printf '```markdown\n'
    printf '## INHERITED FROM constitution/CLAUDE.md\n'
    printf '```\n\n'
    printf '## Build Rules\n\n...but this file never actually writes it live.\n'
} > "${FX_M3}/CLAUDE.md"
_m3_literal_still_present="$(grep -c 'INHERITED FROM constitution/CLAUDE.md' "${FX_M3}/CLAUDE.md" 2>/dev/null)" || _m3_literal_still_present=0
if [ "$_m3_literal_still_present" -gt 0 ]; then
    echo "META OK:   M3 precondition — the grepped literal is STILL present (${_m3_literal_still_present} hit); only its structure changed, so this is not a string-deletion tautology"
else
    echo "META FAIL: M3 precondition — the literal was removed; this mutation would be a string-deletion tautology (§11.4.115(F))"
    rc=1
fi
expect_exit "M3 mutation: consumer pointer demoted from live text to fenced carrier" 1 "$FX_M3"

# --- M4. REMOVE a canonical file (invariant b) ------------------------------
FX_M4="$(mk mut4)"
rm -f "${FX_M4}/constitution/Constitution.md"
expect_exit "M4 mutation: canonical Constitution.md removed" 1 "$FX_M4"

# --- G2. BLIND guard: instrument cannot see -> exit 2, never a false absence -
FX_G2="$(mk blind)"
printf 'a consumer file with no markdown headings at all\n' > "${FX_G2}/CLAUDE.md"
expect_exit "G2 blind guard: needle sees nothing -> BLIND refusal, not a reported absence" 2 "$FX_G2"

# --- M5. ADD a live standard-layout @import pointer to a canonical file -----
FX_M5="$(mk mut5)"
printf '\n@submodules/constitution/CLAUDE.md\n' >> "${FX_M5}/constitution/CLAUDE.md"
expect_exit "M5 mutation: canonical root gains a LIVE '@submodules/constitution/...' import" 1 "$FX_M5"

# mk_std <name> -> moves a correct fixture into the STANDARD layout
# (<root>/submodules/constitution) with the standard-layout pointer.
mk_std() {
    _s="$(mk "$1")"
    mkdir -p "${_s}/submodules"
    mv "${_s}/constitution" "${_s}/submodules/constitution"
    printf '# Consumer\n\n@submodules/constitution/CLAUDE.md\n\n## Project Overview\n\nrules\n' > "${_s}/CLAUDE.md"
    printf '%s\n' "$_s"
}
expect_exit_std() {
    _desc="$1"; _want="$2"; _fx="$3"
    "$GATE" --const-dir "${_fx}/submodules/constitution" --quiet >/dev/null 2>&1
    _got=$?
    if [ "$_got" -eq "$_want" ]; then
        echo "META OK:   ${_desc} (exit ${_got})"
    else
        echo "META FAIL: ${_desc} — expected exit ${_want}, got ${_got}"
        rc=1
    fi
}

# --- G4. FALSE-POSITIVE GUARD, standard layout, derived consumer root ------
FX_G4="$(mk_std std_good)"
expect_exit_std "G4 golden-good: standard layout, consumer root derived, @submodules import" 0 "$FX_G4"

# --- M6. standard layout: consumer pointer demoted to a fenced carrier -----
FX_M6="$(mk_std mut6)"
printf '# Consumer\n\n## Project Overview\n\n```markdown\n@submodules/constitution/CLAUDE.md\n```\n\n## Build\n\nrules\n' > "${FX_M6}/CLAUDE.md"
expect_exit_std "M6 mutation: standard layout, consumer pointer demoted to a fenced carrier" 1 "$FX_M6"

# M7 (I3): a LEGACY-layout consumer whose pointer names the STANDARD path —
# the pointer must equal <rel(consumer_root, const_dir)>/CLAUDE.md.
FX_M7="$(mk mut7)"
printf '# Consumer\n\n@submodules/constitution/CLAUDE.md\n\n## Project Overview\n\nrules\n' > "${FX_M7}/CLAUDE.md"
expect_exit "M7 mutation: legacy consumer points at @submodules/constitution/CLAUDE.md (wrong path)" 1 "$FX_M7"

# M8 (I3): a STANDARD-layout consumer whose pointer names the LEGACY path.
FX_M8="$(mk_std mut8)"
printf '# Consumer\n\n## INHERITED FROM constitution/CLAUDE.md\n\n## Project Overview\n\nrules\n' > "${FX_M8}/CLAUDE.md"
expect_exit_std "M8 mutation: standard consumer points at constitution/CLAUDE.md (wrong path)" 1 "$FX_M8"

# --- G5. FALSE-POSITIVE GUARD: heading pointer with trailing text ----------
# The real consumer shape (helix_code/CLAUDE.md line 12):
#   '## INHERITED FROM constitution/CLAUDE.md (HelixConstitution submodule)'
FX_G5="$(mk good_trailing)"
printf '# Consumer\n\n## INHERITED FROM constitution/CLAUDE.md (HelixConstitution submodule)\n\n## Project Overview\n\nrules\n' > "${FX_G5}/CLAUDE.md"
expect_exit "G5 golden-good: heading pointer followed by trailing text" 0 "$FX_G5"

# M9: the SAME trailing-text shape, but the path is the WRONG layout.
FX_M9="$(mk mut9)"
printf '# Consumer\n\n## INHERITED FROM submodules/constitution/CLAUDE.md (HelixConstitution submodule)\n\n## Project Overview\n\nrules\n' > "${FX_M9}/CLAUDE.md"
expect_exit "M9 mutation: trailing-text pointer names the wrong layout path" 1 "$FX_M9"

# M10: the path glued to more characters ('CLAUDE.md.bak') is not the pointer.
FX_M10="$(mk mut10)"
printf '# Consumer\n\n## INHERITED FROM constitution/CLAUDE.md.bak (old)\n\n## Project Overview\n\nrules\n' > "${FX_M10}/CLAUDE.md"
expect_exit "M10 mutation: near-miss path 'constitution/CLAUDE.md.bak (old)'" 1 "$FX_M10"

# --- Standalone canon checkout (no consumer exists) -------------------------
# When the constitution IS the repository (its own git toplevel, no
# superproject, parent not inside any work tree), there is no consumer: (a) is
# not applicable and must be an honest SKIP (exit 3), never a FAIL (a false
# refusal is a FAIL-bluff, §11.4.201(1)) and never a PASS (§11.4.1).
# mk_sa <name> -> a correct canonical root that is a standalone git repo named
# 'constitution' whose parent holds NO CLAUDE.md (the exact real-tree shape).
mk_sa() {
    _s="$(mk "$1")"
    rm -f "${_s}/CLAUDE.md"
    ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
      git -C "${_s}/constitution" init -q ) || { echo "META: git init failed" >&2; exit 2; }
    printf '%s\n' "$_s"
}
expect_exit_derived() {
    _desc="$1"; _want="$2"; _cd="$3"; shift 3
    "$GATE" --const-dir "$_cd" --quiet "$@" >/dev/null 2>&1
    _got=$?
    if [ "$_got" -eq "$_want" ]; then
        echo "META OK:   ${_desc} (exit ${_got})"
    else
        echo "META FAIL: ${_desc} — expected exit ${_want}, got ${_got}"
        rc=1
    fi
}
if ( unset GIT_DIR GIT_WORK_TREE; git -C "$TMP" rev-parse --show-toplevel ) >/dev/null 2>&1; then
    echo "META FAIL: fixture dir $TMP lies inside a git work tree; standalone cases cannot be built honestly"
    rc=1
else
    # G6 golden-SKIP: standalone canon, consumer root DERIVED -> exit 3.
    FX_G6="$(mk_sa sa_good)"
    expect_exit_derived "G6 standalone canon checkout, no consumer -> SKIP (a), exit 3" 3 "${FX_G6}/constitution"
    _g6_out="$("$GATE" --const-dir "${FX_G6}/constitution" 2>&1)"
    case "$_g6_out" in
        *"(a) CONSUMER-POINTER-PRESENT: SKIP"*) echo "META OK:   G6 output states the (a) SKIP reason" ;;
        *) echo "META FAIL: G6 output carries no '(a) ... SKIP' reason line"; rc=1 ;;
    esac
    # M11: standalone canon still FAILs when (c) is violated (SKIP never hides (b)/(c)).
    FX_M11="$(mk_sa sa_mut_c)"
    printf '\n## INHERITED FROM some-upstream/CLAUDE.md\n\nx\n' >> "${FX_M11}/constitution/CLAUDE.md"
    expect_exit_derived "M11 mutation: standalone canon gains a live pointer -> exit 1, not SKIP" 1 "${FX_M11}/constitution"
    # M12 golden-TRUE: explicit --consumer-root is always audited, even for a standalone canon.
    FX_M12="$(mk_sa sa_explicit)"
    printf '# Consumer\n\n## Build Rules\n\nno pointer\n' > "${FX_M12}/CLAUDE.md"
    expect_exit_derived "M12 explicit --consumer-root on a standalone canon, pointer missing -> exit 1" 1 \
        "${FX_M12}/constitution" --consumer-root "${FX_M12}"
    # M13 golden-TRUE: a nested clone inside a CONSUMER git repo (not a
    # registered submodule) is a consumer, not standalone -> missing pointer FAILs.
    FX_M13="$(mk_sa sa_nested)"
    ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; git -C "${FX_M13}" init -q ) || rc=1
    printf '# Consumer\n\n## Build Rules\n\nno pointer\n' > "${FX_M13}/CLAUDE.md"
    expect_exit_derived "M13 nested clone inside a consumer repo, pointer missing -> exit 1" 1 "${FX_M13}/constitution"
    # M14 golden-TRUE: same nested clone, consumer CLAUDE.md absent -> exit 1 (never SKIP).
    FX_M14="$(mk_sa sa_nested_nofile)"
    ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; git -C "${FX_M14}" init -q ) || rc=1
    expect_exit_derived "M14 nested clone inside a consumer repo, consumer CLAUDE.md absent -> exit 1" 1 "${FX_M14}/constitution"
fi

# --- G3. the gate's own selftest suite must be green ------------------------
if "$GATE" --selftest >/dev/null 2>&1; then
    echo "META OK:   G3 the gate's own --selftest fixture suite is green"
else
    echo "META FAIL: G3 the gate's own --selftest fixture suite is NOT green"
    rc=1
fi

echo "----------------------------------------------------------------------"
if [ "$rc" -eq 0 ]; then
    echo "META: PASS — CM-CANONICAL-ROOT-CLARITY refuses every planted violation and refuses no correct fixture"
    exit 0
fi
echo "META: FAIL — CM-CANONICAL-ROOT-CLARITY produced at least one wrong verdict"
exit 1
