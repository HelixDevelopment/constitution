#!/usr/bin/env bash
# cm_state_fields_anchor_wired.sh — gate CM-STATE-FIELDS-ANCHOR-WIRED
#
# Purpose
#   Proves the §11.4.294 rule (reproduction and investigation states are
#   workable-item fields: every defect item carries a reproduction_state and an
#   investigation_state from closed vocabularies, they gate the lifecycle
#   transitions and the PROVISIONAL-DONE / VERIFIED-DONE levels, a regressed
#   reproduction reopens the item, and every derived document and the
#   external-tracker mirror QUOTE both states from the parent item) is present
#   exactly once, complete, and cross-referenced in BOTH directions across the
#   canon:
#     * Constitution.md        one `### §11.4.294` block carrying the operator
#                              mandate, the two closed vocabularies (six values
#                              each), the nine transition rows T1..T9, the
#                              evidence-or-demotion rule, the applicability
#                              clause, the PROVISIONAL / VERIFIED matrix, the
#                              three reopen situations and their regress lines,
#                              the propagation and mirror contracts, the honest
#                              boundary, every gate token, every escape-hatch
#                              flag, and the citations to the anchors it composes;
#                              ONE SPELLING of every state: the long token
#                              `blocked-no-device-with-recorded-blocker` (the
#                              §11.4.292(B) spelling) is the state; the short
#                              `blocked-no-device` occurs exactly once per block,
#                              in the sentence that declares it an input alias;
#     * the composed anchors   §11.4.34 / .93 / .148 / .290 / .292 each carry a
#                              dated "Refinement note (2026-11-03)" pointing back
#                              at §11.4.294;
#     * the four mirrors       CLAUDE / AGENTS / QWEN / GEMINI each carry exactly
#                              one compact §11.4.294 block-start with both
#                              vocabularies, the two body lines and this gate's
#                              token;
#     * the item template and  scripts/reporting/report_item.sh renders the
#       the two skills         `**Investigation:** not-started` line for a Bug;
#                              the reporting skill documents it; the lifecycle
#                              skill documents both vocabularies and the
#                              transition rows;
#     * generated artefacts    constitution_index.yaml, the group file, the
#                              progressive rule file and catalog;
#     * the seams              the propagation data-pack row, the generated
#                              propagation wrappers, the rule-to-seam binding,
#                              the OWED-GATE-177 / 178 / 179 deferral rows (each
#                              naming a gate the canon block names), and the
#                              post-update hook that runs this gate.
#   It proves the RULE is present and wired. It does NOT prove that any item
#   carries a correct state, that a transition was gated, or that a derived
#   document or the tracker mirror agrees with the database (§11.4.6): those
#   item-level seams are the three deferred gates registered as OWED-GATE-177,
#   OWED-GATE-178 and OWED-GATE-179. Their names are read from the deferral
#   registry, never written in this file: a literal CM- token in a
#   non-mutation-test .sh counts as an implementation site for the
#   §11.4.227(A) ledger, which would turn a deferral into a phantom.
#
# Usage
#   cm_state_fields_anchor_wired.sh [--root <constitution-dir>] [--quiet]
#   cm_state_fields_anchor_wired.sh --help
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
# §11.4.294 is never counted as the block. Before any verdict the extractors
# are run against synthetic documents whose answer is known (positive needle,
# prefix-collision needle, mid-body-citation decoy) and against the real
# neighbouring anchor §11.4.286 in the real files.
#
# Dependencies: bash, awk, grep, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
GATE="CM-STATE-FIELDS-ANCHOR-WIRED"
N=294

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
trap 'rm -rf "${TMP:?}"' EXIT

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
# count_short FILE -> occurrences of the SHORT spelling `blocked-no-device` that are not the
# prefix of the long spelling `blocked-no-device-with-recorded-blocker` (a following `-` means long).
count_short() { grep -o -E 'blocked-no-device([^-]|$)' "$1" | wc -l | tr -d ' '; }

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

NEEDLE_SPELL="$TMP/needle_spell.md"
cat >"$NEEDLE_SPELL" <<'EOF'
long `blocked-no-device-with-recorded-blocker` only here
short `blocked-no-device` here
bare blocked-no-device
EOF
[ "$(count_short "$NEEDLE_SPELL")" = 2 ] || blind "spelling counter missed a known short spelling or counted the long spelling as short"
head -n 1 "$NEEDLE_SPELL" >"$TMP/needle_spell_long.md"
[ "$(count_short "$TMP/needle_spell_long.md")" = 0 ] || blind "spelling counter counted a long-only line as short (negative control)"

CANON="$ROOT/Constitution.md"
[ -f "$CANON" ] || blind "Constitution.md not found under $ROOT"
[ "$(count_heads "$CANON" 286)" = 1 ]             || blind "real-file control needle: expected exactly one §11.4.286 heading in Constitution.md"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    [ -f "$ROOT/$f" ] || continue
    [ "$(count_blockstarts "$ROOT/$f" 286)" = 1 ] || blind "real-file control needle: expected exactly one §11.4.286 block-start in $f"
done

# The closed vocabularies of §11.4.294(A): six reproduction_state values and six investigation_state values.
# ONE SPELLING: the sixth reproduction_state value is the long §11.4.292(B) token; the short form is an input alias.
ALIAS_PHRASE='input alias only: `blocked-no-device`'
RSTATES=(UNSET UNREPRODUCED reproduced-live reproduced-host-fixture not-reproducible-with-evidence blocked-no-device-with-recorded-blocker)
ISTATES=(UNSET not-started in-progress root-cause-found-with-evidence root-cause-unconfirmed closed-no-defect)

# ── 1. canon block ───────────────────────────────────────────────────────────
BLK="$TMP/block$N.txt"
block_of "$CANON" "$N" >"$BLK"
chk "canon: exactly one '### §11.4.$N' heading in Constitution.md" [ "$(count_heads "$CANON" "$N")" = 1 ]
chk "canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)" [ "$(count_blockstarts "$CANON" "$N")" = 1 ]
chk "canon: block is non-empty (heading found)" [ -s "$BLK" ]
HEADLINE="$TMP/headline.txt"; head -n 1 "$BLK" >"$HEADLINE"
chk "canon: heading names 'Reproduction and investigation states'" has "$HEADLINE" "Reproduction and investigation states"
chk "canon: heading names 'workable-item fields'" has "$HEADLINE" "workable-item fields"
chk "canon: heading names 'QUOTE both states'" has "$HEADLINE" "QUOTE both states"
chk "canon: heading carries the mandate date 2026-11-03" has "$HEADLINE" "2026-11-03"

# Required marker phrases (fixed strings) — the rule's load-bearing content.
MARKERS=(
    'the reproduction state and the investigation state of that item'
    'This anchor adds exactly those four'
    '`reproduction_state`'
    '`investigation_state`'
    'NEVER ASSESSED'
    'A value is never typed twice'
    'two sources for one fact'
    'evidence that is gone is not evidence'
    'the state is demoted in the next regeneration'
    '`evidence lost`'
    'no fix against a symptom never observed'
    'a fix before the root cause is investigated is the §11.4.102 violation'
    '`STATE-GATE`'
    'no silent demotion, no free pass'
    'reproduction debt'
    '`UNSET`, permanently'
    'and only the first is contrary evidence'
    'the reproduction regresses'
    '**Reproduction-Regress:**'
    '**Investigation-Regress:**'
    '`INCONSISTENT — red evidence lost`'
    '**Closure-Record:**'
    'A STATE CHANGE IS NOT A STATUS CHANGE'
    'never decides, retypes or defaults a state'
    'it prints `UNCONFIRMED`'
    'numbers-only cell'
    'INDEPENDENT gate'
    'one-way mirror'
    'it never flows back'
    'created=N updated=M failed=0'
    '`repro:<value>`'
    '`investigation:<value>`'
    'Honest boundary'
    'DOES NOT CHANGE'
    'CM-COVENANT-114-294-PROPAGATION'
    'CM-STATE-FIELDS-ANCHOR-WIRED'
    'OWED-GATE-177'
    'OWED-GATE-178'
    'OWED-GATE-179'
    'ONE SPELLING of every state'
    'input alias only: `blocked-no-device`'
)
for m in "${MARKERS[@]}"; do
    chk "canon: block carries marker '$m'" has "$BLK" "$m"
done
for v in "${RSTATES[@]}"; do
    chk "canon: block names reproduction_state value $v" has "$BLK" "\`$v\`"
done
for v in "${ISTATES[@]}"; do
    chk "canon: block names investigation_state value $v" has "$BLK" "\`$v\`"
done
chk "canon: the short spelling blocked-no-device occurs exactly once in the block (the input-alias sentence), never as a state" [ "$(count_short "$BLK")" = 1 ]
for t in T1 T2 T3 T4 T5 T6 T7 T8 T9; do
    chk "canon: block carries transition row $t" has "$BLK" "| $t |"
done
for fl in --fix-without-state --skip-investigation-state --unreproduced-counts-as-verified \
          --state-without-evidence --hand-edit-state-in-derived-doc --tracker-edit-flows-back; do
    chk "canon: block names escape-hatch flag $fl as forbidden" has "$BLK" "$fl"
done
chk "canon: block carries a line-start 'Classification: universal'" has_re "$BLK" '^Classification: universal'
chk "canon: block carries a Canonical authority line" has "$BLK" "**Canonical authority:**"
chk "canon: block carries the non-compliance release-blocker line" has "$BLK" "Non-compliance is a release blocker"

# Cross-references the rule must carry (boundary-safe: §11.4.34 never matches §11.4.340).
for n in 6 15 17 21 33 34 35 69 86 90 93 102 106 112 115 148 149 189 210 227 289 290 292; do
    chk "canon: block cites §11.4.$n" has_re "$BLK" "§11\\.4\\.$n([^0-9]|\$)"
done
chk "canon: block cites §1.1" has_re "$BLK" '§1\.1([^0-9]|$)'

# ── 2. back-pointers: the composed anchors point at §11.4.294 ────────────────
for n in 34 93 148 290 292; do
    RB="$TMP/refined_$n.txt"; block_of "$CANON" "$n" >"$RB"
    chk "refined §11.4.$n: block exists exactly once" [ "$(count_heads "$CANON" "$n")" = 1 ]
    chk "refined §11.4.$n: carries 'Refinement note (2026-11-03)'" has "$RB" "Refinement note (2026-11-03)"
    chk "refined §11.4.$n: refinement note cites §11.4.294" has_re "$RB" "§11\\.4\\.294([^0-9]|\$)"
done

# ── 3. the four context mirrors ──────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    P="$ROOT/$f"
    if [ ! -f "$P" ]; then fail "mirror $f: file missing"; continue; fi
    CB="$TMP/car_$f.txt"; carrier_block "$P" "$N" >"$CB"
    chk "mirror $f: exactly one §11.4.$N block-start" [ "$(count_blockstarts "$P" "$N")" = 1 ]
    for v in "${RSTATES[@]}"; do
        chk "mirror $f: block names reproduction_state value $v" has "$CB" "\`$v\`"
    done
    for v in "${ISTATES[@]}"; do
        chk "mirror $f: block names investigation_state value $v" has "$CB" "\`$v\`"
    done
    chk "mirror $f: block carries the input-alias statement for the short spelling" has "$CB" "$ALIAS_PHRASE"
    chk "mirror $f: the short spelling blocked-no-device occurs exactly once in the block (the input-alias clause), never as a state" [ "$(count_short "$CB")" = 1 ]
    chk "mirror $f: block names the Reproduction: body line" has "$CB" "**Reproduction:**"
    chk "mirror $f: block names the Investigation: body line" has "$CB" "**Investigation:**"
    chk "mirror $f: block names gate $GATE" has "$CB" "$GATE"
    chk "mirror $f: block points at Constitution.md §11.4.$N" has "$CB" "§11.4.$N"
done

# ── 4. item template and the two workable-item skills ────────────────────────
TPL="$ROOT/scripts/reporting/report_item.sh"
if [ -f "$TPL" ]; then
    chk "template: report_item.sh renders the '**Investigation:** not-started' line" has "$TPL" "**Investigation:** not-started"
    chk "template: report_item.sh still renders the '**Reproduction:** none — UNREPRODUCED' line" has "$TPL" "**Reproduction:** none — UNREPRODUCED"
    chk "template: report_item.sh cites §11.4.$N" has "$TPL" "§11.4.$N"
else
    fail "template: scripts/reporting/report_item.sh missing"
fi
SKR="$ROOT/skills/reporting-workable-items/SKILL.md"
if [ -f "$SKR" ]; then
    chk "skill: reporting-workable-items cites §11.4.$N" has "$SKR" "§11.4.$N"
    chk "skill: reporting-workable-items documents the **Investigation:** line" has "$SKR" "**Investigation:**"
    chk "skill: reporting-workable-items names reproduction_state" has "$SKR" "reproduction_state"
else
    fail "skill: skills/reporting-workable-items/SKILL.md missing"
fi
SKL="$ROOT/skills/workable-item-lifecycle/SKILL.md"
if [ -f "$SKL" ]; then
    chk "skill: workable-item-lifecycle cites §11.4.$N" has "$SKL" "§11.4.$N"
    chk "skill: workable-item-lifecycle documents the **Investigation:** line" has "$SKL" "**Investigation:**"
    chk "skill: workable-item-lifecycle documents the Reproduction-Regress: line" has "$SKL" "Reproduction-Regress:"
    chk "skill: workable-item-lifecycle documents the Investigation-Regress: line" has "$SKL" "Investigation-Regress:"
    chk "skill: workable-item-lifecycle documents the Closure-Record: line" has "$SKL" "Closure-Record:"
    for v in "${RSTATES[@]}"; do
        chk "skill: workable-item-lifecycle names reproduction_state value $v" has "$SKL" "\`$v\`"
    done
    for v in "${ISTATES[@]}"; do
        chk "skill: workable-item-lifecycle names investigation_state value $v" has "$SKL" "\`$v\`"
    done
    chk "skill: workable-item-lifecycle carries the input-alias statement for the short spelling" has "$SKL" "$ALIAS_PHRASE"
    chk "skill: workable-item-lifecycle uses the short spelling blocked-no-device exactly once (the input-alias sentence), never as a state" [ "$(count_short "$SKL")" = 1 ]
else
    fail "skill: skills/workable-item-lifecycle/SKILL.md missing"
fi

# ── 5. generated artefacts ───────────────────────────────────────────────────
IDX="$ROOT/constitution_index.yaml"
if [ -f "$IDX" ]; then
    awk -v id="- id: 11.4.$N" '$0 == id { p = 1; print; next } p && /^- id: / { exit } p { print }' "$IDX" >"$TMP/idx.txt"
    chk "index: constitution_index.yaml has an entry for 11.4.$N" [ -s "$TMP/idx.txt" ]
    chk "index: 11.4.$N propagation_gate is CM-COVENANT-114-$N-PROPAGATION" has "$TMP/idx.txt" "propagation_gate: CM-COVENANT-114-$N-PROPAGATION"
    chk "index: 11.4.$N group is workable-items-and-tracking" has "$TMP/idx.txt" "group: workable-items-and-tracking"
    chk "index: 11.4.$N classification is universal" has "$TMP/idx.txt" "classification: universal"
else
    fail "index: constitution_index.yaml missing"
fi
GRP="$ROOT/groups/workable-items-and-tracking.md"
if [ -f "$GRP" ]; then
    chk "group: workable-items-and-tracking.md carries exactly one §11.4.$N block" [ "$(count_heads "$GRP" "$N")" = 1 ]
    block_of "$GRP" "$N" >"$TMP/grp_block.txt"
    chk "group: the §11.4.$N block carries the input-alias statement for the short spelling" has "$TMP/grp_block.txt" "$ALIAS_PHRASE"
    chk "group: the §11.4.$N block uses the short spelling blocked-no-device exactly once (the input-alias sentence), never as a state" [ "$(count_short "$TMP/grp_block.txt")" = 1 ]
else
    fail "group: groups/workable-items-and-tracking.md missing"
fi
chk "progressive: rules/11.4.$N.md exists" [ -s "$ROOT/progressive/rules/11.4.$N.md" ]
if [ -s "$ROOT/progressive/rules/11.4.$N.md" ]; then
    chk "progressive: rules/11.4.$N.md carries the input-alias statement for the short spelling" has "$ROOT/progressive/rules/11.4.$N.md" "$ALIAS_PHRASE"
    chk "progressive: rules/11.4.$N.md uses the short spelling blocked-no-device exactly once (the input-alias sentence), never as a state" [ "$(count_short "$ROOT/progressive/rules/11.4.$N.md")" = 1 ]
fi
CAT="$ROOT/progressive/catalog.json"
if [ -f "$CAT" ]; then
    chk "progressive: catalog.json lists §11.4.$N" has "$CAT" "\"id\":\"§11.4.$N\""
    chk "progressive: catalog.json points at rules/11.4.$N.md" has "$CAT" "\"file\":\"progressive/rules/11.4.$N.md\""
else
    fail "progressive: catalog.json missing"
fi

# ── 6. seams: data-pack row, generated wrappers, seam binding, deferrals, hook ─
PACK="$ROOT/scripts/gates/covenant_propagation_anchors.tsv"
if [ -f "$PACK" ]; then
    chk "seam: propagation data pack has the CM-COVENANT-114-$N-PROPAGATION<TAB>11.4.$N row" \
        awk -F '\t' -v g="CM-COVENANT-114-$N-PROPAGATION" -v a="11.4.$N" '$1 == g && $2 == a { f = 1 } END { exit !f }' "$PACK"
else
    fail "seam: scripts/gates/covenant_propagation_anchors.tsv missing"
fi
chk "seam: generated propagation gate cm_covenant_114_${N}_propagation.sh exists" [ -f "$ROOT/scripts/gates/cm_covenant_114_${N}_propagation.sh" ]
chk "seam: generated propagation mutation test exists" [ -f "$ROOT/scripts/gates/cm_covenant_114_${N}_propagation_mutation_test.sh" ]
BIND="$ROOT/scripts/gates/rule_seam_bindings.tsv"
if [ -f "$BIND" ]; then
    chk "seam: rule_seam_bindings.tsv binds 11.4.$N to a seam" \
        awk -F '\t' -v a="11.4.$N" '$1 == a && $2 != "" && $3 != "" { f = 1 } END { exit !f }' "$BIND"
else
    fail "seam: scripts/gates/rule_seam_bindings.tsv missing"
fi
DEF="$ROOT/scripts/gates/gate_ledger_deferrals.tsv"
if [ -f "$DEF" ]; then
    # Each deferred gate is read from the registry by its id, never written here as a literal:
    # a literal CM- token in a non-mutation-test .sh is counted by the §11.4.227(A) ledger as an
    # implementation site, which would turn the deferral into a phantom IMPLEMENTED.
    for owed in OWED-GATE-177 OWED-GATE-178 OWED-GATE-179; do
        chk "seam: gate_ledger_deferrals.tsv has exactly one $owed row" \
            [ "$(awk -F '\t' -v o="$owed" '$2 == o' "$DEF" | wc -l | tr -d ' ')" = 1 ]
        DG="$(awk -F '\t' -v o="$owed" '$2 == o { print $1; exit }' "$DEF")"
        chk "seam: the $owed deferral names a CM-* gate that the §11.4.$N block names" \
            eval 'case "$DG" in CM-?*) grep -F -q -- "$DG" "$BLK" ;; *) false ;; esac'
    done
else
    fail "seam: scripts/gates/gate_ledger_deferrals.tsv missing"
fi
chk "seam: this gate's paired mutation test exists" [ -f "$ROOT/scripts/gates/cm_state_fields_anchor_wired_mutation_test.sh" ]
HOOK="$ROOT/scripts/post_update_hook.sh"
if [ -f "$HOOK" ]; then
    chk "seam: post_update_hook.sh runs this gate on every pull" has "$HOOK" "cm_state_fields_anchor_wired.sh"
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
