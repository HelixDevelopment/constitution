#!/usr/bin/env bash
# cm_provisional_done_anchor_wired.sh — gate CM-PROVISIONAL-DONE-ANCHOR-WIRED
#
# Purpose
#   Proves the §11.4.290 rule (optimistic done with parallel background
#   verification: PROVISIONAL-DONE vs VERIFIED-DONE, automatic non-silent
#   reopen, honest release labelling) is present exactly once, complete, and
#   cross-referenced in BOTH directions across the canon:
#     * Constitution.md        one `### §11.4.290` block carrying the operator
#                              verbatim quote, both state names, the Status
#                              carrier + `Verification:` line, the scheduled-job
#                              rule, the automatic non-silent reopen with its
#                              NOT-contrary-evidence list, the labelling rule,
#                              the release/changelog duty, the honest boundary,
#                              both gate tokens, every escape-hatch flag, and
#                              the citations to the anchors it refines;
#     * the refined anchors    §11.4.15 / .33 / .108 / .123 / .226 each carry a
#                              dated "Refinement note (2026-10-27)" that points
#                              back at §11.4.290;
#     * the four mirrors       CLAUDE / AGENTS / QWEN / GEMINI each carry exactly
#                              one compact §11.4.290 block-start with the state
#                              names and the `Verification:` carrier;
#     * the lifecycle skill    skills/workable-item-lifecycle/SKILL.md;
#     * generated artefacts    constitution_index.yaml, the group file, the
#                              progressive rule file and catalog;
#     * the seams              the propagation data-pack row, the generated
#                              propagation wrappers, and the post-update hook
#                              that runs this gate on every pull.
#   It proves the RULE is present and cross-referenced. It does NOT prove a
#   consuming project's tracker carries the `Verification:` line, that a job is
#   scheduled at marking, or that the automatic reopen executes (§11.4.6): that
#   item-level seam is each consumer's own tracked work.
#
# Usage
#   cm_provisional_done_anchor_wired.sh [--root <constitution-dir>] [--quiet]
#   cm_provisional_done_anchor_wired.sh --help
#   --root defaults to the constitution directory that holds this script.
#
# Exit codes
#   0  PASS    every check passed
#   1  FAIL    at least one check failed (each failure is named on stdout)
#   2  BLIND   the instrument could not be trusted (control needle failed, or
#              Constitution.md is absent); a zero-failure result is never
#              reported from a blind instrument (§11.4.201(6), §11.4.273)
#   64 usage error
#
# Instrument discipline (§11.4.273): block extraction matches STRUCTURE (a
# line-anchored heading), never a bare literal, so a mid-body citation of
# §11.4.290 is never counted as the block. Before any verdict the extractors
# are run against synthetic documents whose answer is known (positive needle,
# prefix-collision needle, mid-body-citation decoy) and against the real
# neighbouring anchor §11.4.286 in the real files.
set -u -o pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
GATE="CM-PROVISIONAL-DONE-ANCHOR-WIRED"

usage() { echo "usage: ${0##*/} [--root <constitution-dir>] [--quiet] | --help" >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; exit 0 ;;
        *) usage ;;
    esac
done
[ -d "$ROOT" ] || { echo "$GATE: BLIND — root is not a directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

TMP="$(mktemp -d)" || { echo "$GATE: BLIND — mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ── extractors ───────────────────────────────────────────────────────────────
# Heading prefix of a canon anchor block. A single variable so the mutation test
# can prove that breaking it turns the verdict BLIND, never a silent PASS.
HEAD_PREFIX='### §11\\.4\\.'

# block_of FILE N -> the canon block of anchor N: its `### §11.4.N` heading through the
# line before the next `### §` / `## ` heading (or EOF).
block_of() {
    awk -v n="$2" -v hp="$HEAD_PREFIX" '
        BEGIN { pat = "^" hp n "( |$)" }
        $0 ~ pat { p = 1; print; next }
        p && (/^### §/ || /^## /) { exit }
        p { print }
    ' "$1"
}
# count_heads FILE N -> number of `### §11.4.N` heading lines (canon form).
count_heads() {
    awk -v n="$2" -v hp="$HEAD_PREFIX" 'BEGIN { pat = "^" hp n "( |$)"; c = 0 } $0 ~ pat { c++ } END { print c }' "$1"
}
# count_blockstarts FILE N -> block-starts of any carrier form: `**§`, `### §`, `- §`.
count_blockstarts() {
    awk -v n="$2" 'BEGIN { pat = "^(\\*\\*|### |- )§11\\.4\\." n "([^0-9]|$)"; c = 0 } $0 ~ pat { c++ } END { print c }' "$1"
}
# carrier_block FILE N -> a mirror block: block-start through the line before the next
# block-start of ANY anchor or `## ` heading (the engine's own end rule).
carrier_block() {
    awk -v n="$2" '
        BEGIN { s = "^(\\*\\*|### |- )§11\\.4\\." n "([^0-9]|$)"; g = "^(\\*\\*|### |- )§11\\.4\\.[0-9]|^## " }
        p && $0 ~ g { exit }
        !p && $0 ~ s { p = 1 }
        p { print }
    ' "$1"
}
has()    { grep -F -q -- "$2" "$1"; }
has_re() { grep -E -q -- "$2" "$1"; }

NPASS=0; NFAIL=0
pass() { NPASS=$((NPASS + 1)); [ "$QUIET" = 1 ] || printf 'PASS  %s\n' "$*"; }
fail() { NFAIL=$((NFAIL + 1)); printf 'FAIL  %s\n' "$*"; }
chk()  { # chk "<label>" <command...>
    local label="$1"; shift
    if "$@"; then pass "$label"; else fail "$label"; fi
}
blind() { echo "$GATE: BLIND — $*" >&2; exit 2; }

# ── control needles: prove the extractors can see, before any verdict ────────
NEEDLE_DOC="$TMP/needle_doc.md"
cat >"$NEEDLE_DOC" <<'EOF'
### §11.4.9990 — needle heading
body has NEEDLE-PHRASE and cites §11.4.9991(A) in a mid-body sentence.
### §11.4.9991 — next heading
other-phrase
EOF
NEEDLE_CAR="$TMP/needle_car.md"
cat >"$NEEDLE_CAR" <<'EOF'
**§11.4.9990 — needle carrier.** NEEDLE-PHRASE here.
A later line cites §11.4.9990(A) mid-sentence and is not a block-start.
**§11.4.9992 — a different anchor.** other-phrase
EOF
[ "$(count_heads "$NEEDLE_DOC" 9990)" = 1 ]      || blind "heading extractor missed a known heading"
[ "$(count_heads "$NEEDLE_DOC" 999)" = 0 ]       || blind "heading extractor prefix-matched 999 against 9990"
[ "$(count_heads "$NEEDLE_DOC" 9991)" = 1 ]      || blind "heading extractor counted a mid-body citation as a heading"
block_of "$NEEDLE_DOC" 9990 >"$TMP/nb.txt"
has "$TMP/nb.txt" "NEEDLE-PHRASE"                 || blind "block extractor did not return the needle block body"
! has "$TMP/nb.txt" "other-phrase"                || blind "block extractor overran into the next anchor"
[ "$(count_blockstarts "$NEEDLE_CAR" 9990)" = 1 ] || blind "carrier extractor missed a known block-start or counted a citation"
[ "$(count_blockstarts "$NEEDLE_CAR" 999)" = 0 ]  || blind "carrier extractor prefix-matched 999 against 9990"
carrier_block "$NEEDLE_CAR" 9990 >"$TMP/nc.txt"
has "$TMP/nc.txt" "NEEDLE-PHRASE"                 || blind "carrier block extractor lost the needle body"
! has "$TMP/nc.txt" "other-phrase"                || blind "carrier block extractor overran into the next anchor"

CANON="$ROOT/Constitution.md"
[ -f "$CANON" ] || blind "Constitution.md not found under $ROOT"
[ "$(count_heads "$CANON" 286)" = 1 ]             || blind "real-file control needle: expected exactly one §11.4.286 heading in Constitution.md"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    [ -f "$ROOT/$f" ] || continue
    [ "$(count_blockstarts "$ROOT/$f" 286)" = 1 ] || blind "real-file control needle: expected exactly one §11.4.286 block-start in $f"
done

# ── 1. canon block ───────────────────────────────────────────────────────────
BLK="$TMP/block290.txt"
block_of "$CANON" 290 >"$BLK"
chk "canon: exactly one '### §11.4.290' heading in Constitution.md" [ "$(count_heads "$CANON" 290)" = 1 ]
chk "canon: exactly one §11.4.290 block-start of any form in Constitution.md (no duplicate form)" [ "$(count_blockstarts "$CANON" 290)" = 1 ]
chk "canon: block is non-empty (heading found)" [ -s "$BLK" ]
HEADLINE="$TMP/headline.txt"; head -n 1 "$BLK" >"$HEADLINE"
chk "canon: heading names PROVISIONAL-DONE" has "$HEADLINE" "PROVISIONAL-DONE"
chk "canon: heading names VERIFIED-DONE" has "$HEADLINE" "VERIFIED-DONE"
chk "canon: heading carries the mandate date 2026-10-27" has "$HEADLINE" "2026-10-27"

# Required marker phrases (fixed strings) — the rule's load-bearing content.
MARKERS=(
    "Until it is proved not done, consider it done"
    "If we encounter issues we shall reopen"
    "PROVISIONAL-DONE"
    "VERIFIED-DONE"
    "done-provisional"
    "**Verification:**"
    "ALREADY scheduled"
    "AUTOMATICALLY"
    "NEVER silent"
    "RED on a pre-fix artifact"
    "NOT contrary evidence"
    "V verified + P provisional"
    "Honest boundary"
    "DOES NOT CHANGE"
    "CM-COVENANT-114-290-PROPAGATION"
    "CM-PROVISIONAL-DONE-ANCHOR-WIRED"
    "BACKGROUND"
    "PARALLEL"
    "never appears in a verified"
    "release notes MUST state"
    "verification OVERDUE"
    "Reopened-Details"
)
for m in "${MARKERS[@]}"; do
    chk "canon: block carries marker '$m'" has "$BLK" "$m"
done
for fl in --provisional-counts-as-verified --skip-verification-job --silent-reopen \
          --hide-provisional-in-changelog --promote-on-timeout --unlabelled-done-count; do
    chk "canon: block names escape-hatch flag $fl as forbidden" has "$BLK" "$fl"
done
chk "canon: block carries a line-start 'Classification: universal'" has_re "$BLK" '^Classification: universal'
chk "canon: block carries a Canonical authority line" has "$BLK" "**Canonical authority:**"
chk "canon: block carries the non-compliance release-blocker line" has "$BLK" "Non-compliance is a release blocker"

# Cross-references the rule must carry (boundary-safe: §11.4.15 never matches §11.4.150).
for n in 1 5 6 7 15 33 34 55 108 115 123 135 189 197 201 226 227 236 262 271; do
    chk "canon: block cites §11.4.$n" has_re "$BLK" "§11\\.4\\.$n([^0-9]|\$)"
done
chk "canon: block cites §7.1"  has_re "$BLK" '§7\.1([^0-9]|$)'
chk "canon: block cites §9"    has_re "$BLK" '§9([^0-9.]|$)'
chk "canon: block cites §12"   has_re "$BLK" '§12([^0-9.]|$)'

# ── 2. back-pointers: the refined anchors point at §11.4.290 ─────────────────
for n in 15 33 108 123 226; do
    RB="$TMP/refined_$n.txt"; block_of "$CANON" "$n" >"$RB"
    chk "refined §11.4.$n: block exists exactly once" [ "$(count_heads "$CANON" "$n")" = 1 ]
    chk "refined §11.4.$n: carries 'Refinement note (2026-10-27)'" has "$RB" "Refinement note (2026-10-27)"
    chk "refined §11.4.$n: refinement note cites §11.4.290" has_re "$RB" "§11\\.4\\.290([^0-9]|\$)"
done

# ── 3. the four context mirrors ──────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    P="$ROOT/$f"
    if [ ! -f "$P" ]; then fail "mirror $f: file missing"; continue; fi
    CB="$TMP/car_$f.txt"; carrier_block "$P" 290 >"$CB"
    chk "mirror $f: exactly one §11.4.290 block-start" [ "$(count_blockstarts "$P" 290)" = 1 ]
    chk "mirror $f: block names PROVISIONAL-DONE" has "$CB" "PROVISIONAL-DONE"
    chk "mirror $f: block names VERIFIED-DONE" has "$CB" "VERIFIED-DONE"
    chk "mirror $f: block names the Verification: carrier" has "$CB" "**Verification:**"
    chk "mirror $f: block names gate CM-PROVISIONAL-DONE-ANCHOR-WIRED" has "$CB" "CM-PROVISIONAL-DONE-ANCHOR-WIRED"
    chk "mirror $f: block points at Constitution.md §11.4.290" has "$CB" "§11.4.290"
done

# ── 4. lifecycle skill ───────────────────────────────────────────────────────
SK="$ROOT/skills/workable-item-lifecycle/SKILL.md"
if [ -f "$SK" ]; then
    chk "skill: workable-item-lifecycle cites §11.4.290" has "$SK" "§11.4.290"
    chk "skill: workable-item-lifecycle names PROVISIONAL-DONE" has "$SK" "PROVISIONAL-DONE"
    chk "skill: workable-item-lifecycle names VERIFIED-DONE" has "$SK" "VERIFIED-DONE"
    chk "skill: workable-item-lifecycle documents the Verification: line" has "$SK" "**Verification:**"
else
    fail "skill: skills/workable-item-lifecycle/SKILL.md missing"
fi

# ── 5. generated artefacts ───────────────────────────────────────────────────
IDX="$ROOT/constitution_index.yaml"
if [ -f "$IDX" ]; then
    awk '/^- id: 11\.4\.290$/ { p = 1; print; next } p && /^- id: / { exit } p { print }' "$IDX" >"$TMP/idx290.txt"
    chk "index: constitution_index.yaml has an entry for 11.4.290" [ -s "$TMP/idx290.txt" ]
    chk "index: 11.4.290 propagation_gate is CM-COVENANT-114-290-PROPAGATION" has "$TMP/idx290.txt" "propagation_gate: CM-COVENANT-114-290-PROPAGATION"
    chk "index: 11.4.290 group is workable-items-and-tracking" has "$TMP/idx290.txt" "group: workable-items-and-tracking"
    chk "index: 11.4.290 classification is universal" has "$TMP/idx290.txt" "classification: universal"
else
    fail "index: constitution_index.yaml missing"
fi
GRP="$ROOT/groups/workable-items-and-tracking.md"
if [ -f "$GRP" ]; then
    chk "group: workable-items-and-tracking.md carries exactly one §11.4.290 block" [ "$(count_heads "$GRP" 290)" = 1 ]
else
    fail "group: groups/workable-items-and-tracking.md missing"
fi
chk "progressive: rules/11.4.290.md exists" [ -s "$ROOT/progressive/rules/11.4.290.md" ]
CAT="$ROOT/progressive/catalog.json"
if [ -f "$CAT" ]; then
    chk "progressive: catalog.json lists §11.4.290" has "$CAT" '"id":"§11.4.290"'
    chk "progressive: catalog.json points at rules/11.4.290.md" has "$CAT" '"file":"progressive/rules/11.4.290.md"'
else
    fail "progressive: catalog.json missing"
fi

# ── 6. seams: data-pack row, generated wrappers, hook binding ────────────────
PACK="$ROOT/scripts/gates/covenant_propagation_anchors.tsv"
if [ -f "$PACK" ]; then
    chk "seam: propagation data pack has the CM-COVENANT-114-290-PROPAGATION<TAB>11.4.290 row" \
        awk -F '\t' '$1 == "CM-COVENANT-114-290-PROPAGATION" && $2 == "11.4.290" { f = 1 } END { exit !f }' "$PACK"
else
    fail "seam: scripts/gates/covenant_propagation_anchors.tsv missing"
fi
chk "seam: generated propagation gate cm_covenant_114_290_propagation.sh exists" [ -f "$ROOT/scripts/gates/cm_covenant_114_290_propagation.sh" ]
chk "seam: generated propagation mutation test exists" [ -f "$ROOT/scripts/gates/cm_covenant_114_290_propagation_mutation_test.sh" ]
chk "seam: this gate's paired mutation test exists" [ -f "$ROOT/scripts/gates/cm_provisional_done_anchor_wired_mutation_test.sh" ]
HOOK="$ROOT/scripts/post_update_hook.sh"
if [ -f "$HOOK" ]; then
    chk "seam: post_update_hook.sh runs this gate on every pull" has "$HOOK" "cm_provisional_done_anchor_wired.sh"
    chk "seam: post_update_hook.sh names the token $GATE" has "$HOOK" "$GATE"
else
    fail "seam: scripts/post_update_hook.sh missing"
fi

# ── verdict ──────────────────────────────────────────────────────────────────
TOTAL=$((NPASS + NFAIL))
if [ "$NFAIL" -eq 0 ]; then
    echo "$GATE: PASS — $NPASS/$TOTAL checks (root: $ROOT)"
    exit 0
fi
echo "$GATE: FAIL — $NFAIL of $TOTAL checks failed (root: $ROOT)"
exit 1
