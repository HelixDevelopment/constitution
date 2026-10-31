#!/usr/bin/env bash
# tests/layout/test_canonical_root_layout.sh — CM-CANONICAL-ROOT-CLARITY in BOTH
# layouts: the default consumer root is derived correctly (never
# <project>/submodules), and an inheritance pointer to either path is accepted
# in the consumer while a live pointer of either form in the canonical root is
# still refused.
# Usage: bash tests/layout/test_canonical_root_layout.sh
LT_SUITE="canonical_root_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

mkfx() { # mkfx DIR REL CONSUMER_POINTER_LINE
    local d="$1" rel="$2" ptr="$3"
    mkdir -p "$d/$rel/scripts/gates" "$d/$rel/scripts/lib"
    cp "$LAYOUT_SRC_ROOT/scripts/gates/cm_canonical_root_clarity.sh" "$d/$rel/scripts/gates/"
    [ -f "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" ] && \
        cp "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh" "$d/$rel/scripts/lib/"
    printf '# Constitution\n\n## Purpose\n\nrules\n' > "$d/$rel/Constitution.md"
    printf '# Base AGENTS\n\n## Agent Rules\n\nrules\n' > "$d/$rel/AGENTS.md"
    printf '# Base CLAUDE\n\n## How\n\n```markdown\n## INHERITED FROM submodules/constitution/CLAUDE.md\n@submodules/constitution/CLAUDE.md\n```\n' > "$d/$rel/CLAUDE.md"
    printf '# Consumer\n\n%s\n\n## Project\n\nrules\n' "$ptr" > "$d/CLAUDE.md"
}
gate() { bash "$1/scripts/gates/cm_canonical_root_clarity.sh" --quiet "${@:2}" >/dev/null 2>&1; }

for rel in submodules/constitution constitution; do
    tag="[$rel]"
    for ptr in "## INHERITED FROM $rel/CLAUDE.md" "@$rel/CLAUDE.md"; do
        d="$LT_SB/c $(printf '%s%s' "$rel" "$ptr" | tr -c 'a-zA-Z0-9' _)"
        mkfx "$d" "$rel" "$ptr"
        gate "$d/$rel"; rc=$?
        lt_check "$tag default consumer root + pointer '$ptr' -> PASS (rc=$rc)" test "$rc" -eq 0
    done
    d="$LT_SB/cbad $(printf '%s' "$rel" | tr / _)"
    mkfx "$d" "$rel" "## INHERITED FROM $rel/CLAUDE.md"
    printf '\n@submodules/constitution/CLAUDE.md\n' >> "$d/$rel/AGENTS.md"
    gate "$d/$rel"; rc=$?
    lt_check "$tag live '@submodules/constitution/...' import in the canonical root -> exit 1 (rc=$rc)" test "$rc" -eq 1
    d="$LT_SB/cbad2 $(printf '%s' "$rel" | tr / _)"
    mkfx "$d" "$rel" "## Not a pointer"
    gate "$d/$rel"; rc=$?
    lt_check "$tag consumer without pointer -> exit 1 (rc=$rc)" test "$rc" -eq 1
done

# I3: the pointer must name THIS consumer's real path to its constitution.
xp() { case "$1" in constitution) printf 'submodules/constitution' ;; *) printf 'constitution' ;; esac; }
for rel in submodules/constitution constitution; do
    other="$(xp "$rel")"
    for ptr in "## INHERITED FROM $other/CLAUDE.md" "@$other/CLAUDE.md" "## INHERITED FROM elsewhere/CLAUDE.md" "## INHERITED FROM $rel/AGENTS.md"; do
        d="$LT_SB/x $(printf '%s%s' "$rel" "$ptr" | tr -c 'a-zA-Z0-9' _)"
        mkfx "$d" "$rel" "$ptr"
        gate "$d/$rel"; rc=$?
        lt_check "[$rel] consumer pointer '$ptr' names the WRONG path -> exit 1 (rc=$rc)" test "$rc" -eq 1
    done
    d="$LT_SB/xs $(printf '%s' "$rel" | tr / _)"
    mkfx "$d" "$rel" "## INHERITED FROM $rel/CLAUDE.md   "
    gate "$d/$rel"; rc=$?
    lt_check "[$rel] exact pointer with trailing spaces -> PASS (rc=$rc)" test "$rc" -eq 0
done

# I-2 (round 2): a heading pointer followed by trailing text, as in a real
# consumer (helix_code/CLAUDE.md: '## INHERITED FROM constitution/CLAUDE.md
# (HelixConstitution submodule)'), and @-imports of the other two canonical
# files are accepted; a near-miss path is still refused.
for rel in submodules/constitution constitution; do
    other="$(xp "$rel")"
    for ptr in "## INHERITED FROM $rel/CLAUDE.md (HelixConstitution submodule)" \
               "## INHERITED FROM $rel/CLAUDE.md	— tab then text" \
               "@$rel/AGENTS.md" "@$rel/Constitution.md"; do
        d="$LT_SB/t $(printf '%s%s' "$rel" "$ptr" | tr -c 'a-zA-Z0-9' _)"
        mkfx "$d" "$rel" "$ptr"
        gate "$d/$rel"; rc=$?
        lt_check "[$rel] consumer pointer '$ptr' -> PASS (rc=$rc)" test "$rc" -eq 0
    done
    for ptr in "## INHERITED FROM $other/CLAUDE.md (HelixConstitution submodule)" \
               "## INHERITED FROM $rel/CLAUDE.md.bak (old)" "## INHERITED FROM $rel/CLAUDE.mdx" \
               "## INHERITED FROM $rel/CLAUDE.md(no space)" "@$other/AGENTS.md" "@$rel/README.md" \
               "@$rel/AGENTS.md trailing"; do
        d="$LT_SB/tb $(printf '%s%s' "$rel" "$ptr" | tr -c 'a-zA-Z0-9' _)"
        mkfx "$d" "$rel" "$ptr"
        gate "$d/$rel"; rc=$?
        lt_check "[$rel] near-miss consumer pointer '$ptr' -> exit 1 (rc=$rc)" test "$rc" -eq 1
    done
done

# Fail-closed (a) : with NO --standalone-canon declaration the gate audits a consumer, so a
# parent WITHOUT any CLAUDE.md (or without a pointer) is a FAIL, never an auto-detected
# standalone SKIP; the SKIP exists only when the invocation DECLARES --standalone-canon.
for rel in submodules/constitution constitution; do
    d="$LT_SB/sa $(printf '%s' "$rel" | tr / _)"
    mkfx "$d" "$rel" "## INHERITED FROM $rel/CLAUDE.md"
    rm -f "$d/CLAUDE.md"
    gate "$d/$rel"; rc=$?
    lt_check "[$rel] no consumer CLAUDE.md and no declaration -> exit 1 fail-closed (rc=$rc)" test "$rc" -eq 1
    gate "$d/$rel" --standalone-canon; rc=$?
    lt_check "[$rel] --standalone-canon declared -> exit 3 SKIP (rc=$rc)" test "$rc" -eq 3
    printf '# readme\n' > "$d/README.md"
    gate "$d/$rel"; rc=$?
    lt_check "[$rel] README.md next to the checkout does not make it standalone -> exit 1 (rc=$rc)" test "$rc" -eq 1
done

G="$LAYOUT_SRC_ROOT/scripts/gates/cm_canonical_root_clarity.sh"
lt_check "gate --selftest green" bash "$G" --selftest
lt_check "gate parses under sh -n" sh -n "$G"
lt_check "paired mutation test green" bash "$LAYOUT_SRC_ROOT/scripts/gates/cm_canonical_root_clarity_mutation_test.sh"
lt_summary
