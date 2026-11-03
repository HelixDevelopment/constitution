#!/usr/bin/env bash
# cm_repro_first_anchor_wired.sh — gate CM-REPRO-FIRST-ANCHOR-WIRED
#
# Purpose
#   Proves the §11.4.292 rule (reproduce first: every issue being fixed is
#   REPRODUCED LIVE before any cause hypothesis is acted on or any fix is
#   written; closed-vocabulary reproduction record; RED-before / GREEN-after on
#   one command, one target and one symptom signature; root cause proven;
#   deterministic live coverage test; a fix under blocked reproduction lands
#   only as PROVISIONAL-DONE labelled UNREPRODUCED) is present exactly once,
#   complete, and cross-referenced in BOTH directions across the canon:
#     * Constitution.md        one `### §11.4.292` block carrying the operator
#                              mandate, the four-value closed result
#                              vocabulary, both item labels, the
#                              `Reproduction:` carrier and its template
#                              default, every required evidence field, the
#                              RED/GREEN pairing key, the blocked-reproduction
#                              clause, the not-reproducible clause, the
#                              investigation and live-coverage clause, the
#                              honest boundary, every gate token, every
#                              escape-hatch flag, and the citations to the
#                              anchors it composes;
#     * the composed anchors   §11.4.43 / .115 / .146 / .199 each carry a dated
#                              "Refinement note (2026-11-03)" pointing back at
#                              §11.4.292;
#     * the four mirrors       CLAUDE / AGENTS / QWEN / GEMINI each carry exactly
#                              one compact §11.4.292 block-start with the four
#                              result values, the `Reproduction:` carrier, the
#                              UNREPRODUCED label and this gate's token;
#     * the item template      scripts/reporting/report_item.sh renders the
#                              `**Reproduction:** none — UNREPRODUCED` line for a
#                              Bug; both workable-item skills document the
#                              `Reproduction:` field and its closed vocabulary;
#     * generated artefacts    constitution_index.yaml, the group file, the
#                              progressive rule file and catalog;
#     * the seams              the propagation data-pack row, the generated
#                              propagation wrappers, the rule-to-seam binding,
#                              the OWED-GATE-174 deferral row, and the
#                              post-update hook that runs this gate on every pull.
#   It proves the RULE is present and wired. It does NOT prove that any item
#   carries a correct record, that a reproduction was live, or that a RED/GREEN
#   pair matches (§11.4.6): that item-level seam is the deferred gate registered
#   as OWED-GATE-174. Its CM- name is read from gate_ledger_deferrals.tsv, never
#   written in this file: the §11.4.227(A) ledger counts a literal CM- token in a
#   non-mutation-test .sh as an implementation site.
#
# Usage
#   cm_repro_first_anchor_wired.sh [--root <constitution-dir>] [--quiet]
#   cm_repro_first_anchor_wired.sh --help
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
# §11.4.292 is never counted as the block. Before any verdict the extractors
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
GATE="CM-REPRO-FIRST-ANCHOR-WIRED"
N=292

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

# The closed result vocabulary of §11.4.292(B) — exactly four values.
VOCAB=(reproduced-live reproduced-host-fixture not-reproducible-with-evidence blocked-no-device-with-recorded-blocker)

# ── 1. canon block ───────────────────────────────────────────────────────────
BLK="$TMP/block$N.txt"
block_of "$CANON" "$N" >"$BLK"
chk "canon: exactly one '### §11.4.$N' heading in Constitution.md" [ "$(count_heads "$CANON" "$N")" = 1 ]
chk "canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)" [ "$(count_blockstarts "$CANON" "$N")" = 1 ]
chk "canon: block is non-empty (heading found)" [ -s "$BLK" ]
HEADLINE="$TMP/headline.txt"; head -n 1 "$BLK" >"$HEADLINE"
chk "canon: heading names 'Reproduce first'" has "$HEADLINE" "Reproduce first"
chk "canon: heading names REPRODUCED LIVE" has "$HEADLINE" "REPRODUCED LIVE"
chk "canon: heading names UNREPRODUCED" has "$HEADLINE" "UNREPRODUCED"
chk "canon: heading carries the mandate date 2026-11-03" has "$HEADLINE" "2026-11-03"

# Required marker phrases (fixed strings) — the rule's load-bearing content.
MARKERS=(
    'critical and absolute first priority'
    'reproduce the reported symptom LIVE'
    'wait until the record exists'
    '`reproduced-live`'
    '`reproduced-host-fixture`'
    '`not-reproducible-with-evidence`'
    '`blocked-no-device-with-recorded-blocker`'
    'There is no fifth result'
    '`REPRODUCED`'
    '`UNREPRODUCED`'
    '`host-only`'
    '`live-target`'
    '**Reproduction:**'
    '**Reproduction:** none — UNREPRODUCED'
    'exact command'
    'captured RED output'
    'environment / build id'
    'board serial'
    'fixture sha256'
    'symptom signature'
    'UNCONFIRMED: <reason>'
    'RED BEFORE, GREEN AFTER'
    'SAME recorded command'
    'SAME target identity'
    'SAME symptom signature'
    'promote nothing'
    'CANNOT reach VERIFIED-DONE while `UNREPRODUCED`'
    'only as PROVISIONAL-DONE'
    'blocker record'
    'positive control needle'
    'no fix is written against the unobserved symptom'
    'established as FACT'
    'decisive experiment'
    'LIVE coverage test'
    'deterministic'
    '`host-substitute`'
    'Honest boundary'
    'DOES NOT CHANGE'
    'CM-COVENANT-114-292-PROPAGATION'
    'CM-REPRO-FIRST-ANCHOR-WIRED'
    'OWED-GATE-174'
)
for m in "${MARKERS[@]}"; do
    chk "canon: block carries marker '$m'" has "$BLK" "$m"
done
for fl in --fix-before-reproduce --skip-live-reproduction --hypothesis-as-root-cause \
          --unreproduced-counts-as-verified --green-without-red --green-on-other-signature \
          --host-fixture-as-live --blocked-means-verified --fix-unobserved-symptom --unlabelled-unreproduced; do
    chk "canon: block names escape-hatch flag $fl as forbidden" has "$BLK" "$fl"
done
chk "canon: block carries a line-start 'Classification: universal'" has_re "$BLK" '^Classification: universal'
chk "canon: block carries a Canonical authority line" has "$BLK" "**Canonical authority:**"
chk "canon: block carries the non-compliance release-blocker line" has "$BLK" "Non-compliance is a release blocker"

# Cross-references the rule must carry (boundary-safe: §11.4.3 never matches §11.4.35).
for n in 3 6 7 15 21 33 34 35 43 50 90 102 108 111 114 115 123 135 146 199 200 201 226 227 242 262 267 273 289 290; do
    chk "canon: block cites §11.4.$n" has_re "$BLK" "§11\\.4\\.$n([^0-9]|\$)"
done
chk "canon: block cites §1.1" has_re "$BLK" '§1\.1([^0-9]|$)'
chk "canon: block cites §7.1" has_re "$BLK" '§7\.1([^0-9]|$)'

# ── 2. back-pointers: the composed anchors point at §11.4.292 ────────────────
for n in 43 115 146 199; do
    RB="$TMP/refined_$n.txt"; block_of "$CANON" "$n" >"$RB"
    chk "refined §11.4.$n: block exists exactly once" [ "$(count_heads "$CANON" "$n")" = 1 ]
    chk "refined §11.4.$n: carries 'Refinement note (2026-11-03)'" has "$RB" "Refinement note (2026-11-03)"
    chk "refined §11.4.$n: refinement note cites §11.4.292" has_re "$RB" "§11\\.4\\.292([^0-9]|\$)"
done

# ── 3. the four context mirrors ──────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    P="$ROOT/$f"
    if [ ! -f "$P" ]; then fail "mirror $f: file missing"; continue; fi
    CB="$TMP/car_$f.txt"; carrier_block "$P" "$N" >"$CB"
    chk "mirror $f: exactly one §11.4.$N block-start" [ "$(count_blockstarts "$P" "$N")" = 1 ]
    for v in "${VOCAB[@]}"; do
        chk "mirror $f: block names result $v" has "$CB" "\`$v\`"
    done
    chk "mirror $f: block names the Reproduction: carrier" has "$CB" "**Reproduction:**"
    chk "mirror $f: block names the UNREPRODUCED label" has "$CB" "UNREPRODUCED"
    chk "mirror $f: block names gate $GATE" has "$CB" "$GATE"
    chk "mirror $f: block points at Constitution.md §11.4.$N" has "$CB" "§11.4.$N"
done

# ── 4. item template and workable-item skills carry the Reproduction field ───
TPL="$ROOT/scripts/reporting/report_item.sh"
if [ -f "$TPL" ]; then
    chk "template: report_item.sh renders the '**Reproduction:** none — UNREPRODUCED' line" has "$TPL" "**Reproduction:** none — UNREPRODUCED"
    chk "template: report_item.sh cites §11.4.$N" has "$TPL" "§11.4.$N"
else
    fail "template: scripts/reporting/report_item.sh missing"
fi
for sk in reporting-workable-items workable-item-lifecycle; do
    SK="$ROOT/skills/$sk/SKILL.md"
    if [ ! -f "$SK" ]; then fail "skill: skills/$sk/SKILL.md missing"; continue; fi
    chk "skill: $sk cites §11.4.$N" has "$SK" "§11.4.$N"
    chk "skill: $sk documents the **Reproduction:** field" has "$SK" "**Reproduction:**"
    chk "skill: $sk names the UNREPRODUCED label" has "$SK" "UNREPRODUCED"
    for v in "${VOCAB[@]}"; do
        chk "skill: $sk names result $v" has "$SK" "\`$v\`"
    done
done

# ── 5. generated artefacts ───────────────────────────────────────────────────
IDX="$ROOT/constitution_index.yaml"
if [ -f "$IDX" ]; then
    awk -v id="- id: 11.4.$N" '$0 == id { p = 1; print; next } p && /^- id: / { exit } p { print }' "$IDX" >"$TMP/idx.txt"
    chk "index: constitution_index.yaml has an entry for 11.4.$N" [ -s "$TMP/idx.txt" ]
    chk "index: 11.4.$N propagation_gate is CM-COVENANT-114-$N-PROPAGATION" has "$TMP/idx.txt" "propagation_gate: CM-COVENANT-114-$N-PROPAGATION"
    chk "index: 11.4.$N group is testing-and-tdd" has "$TMP/idx.txt" "group: testing-and-tdd"
    chk "index: 11.4.$N classification is universal" has "$TMP/idx.txt" "classification: universal"
else
    fail "index: constitution_index.yaml missing"
fi
GRP="$ROOT/groups/testing-and-tdd.md"
if [ -f "$GRP" ]; then
    chk "group: testing-and-tdd.md carries exactly one §11.4.$N block" [ "$(count_heads "$GRP" "$N")" = 1 ]
else
    fail "group: groups/testing-and-tdd.md missing"
fi
chk "progressive: rules/11.4.$N.md exists" [ -s "$ROOT/progressive/rules/11.4.$N.md" ]
CAT="$ROOT/progressive/catalog.json"
if [ -f "$CAT" ]; then
    chk "progressive: catalog.json lists §11.4.$N" has "$CAT" "\"id\":\"§11.4.$N\""
    chk "progressive: catalog.json points at rules/11.4.$N.md" has "$CAT" "\"file\":\"progressive/rules/11.4.$N.md\""
else
    fail "progressive: catalog.json missing"
fi

# ── 6. seams: data-pack row, generated wrappers, seam binding, deferral, hook ──
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
    # The deferred gate is read from the registry by its id, never written here as a literal:
    # a literal CM- token in a non-mutation-test .sh is counted by the §11.4.227(A) ledger as an
    # implementation site, which would turn the deferral into a phantom IMPLEMENTED.
    chk "seam: gate_ledger_deferrals.tsv has exactly one OWED-GATE-174 row" \
        [ "$(awk -F '\t' '$2 == "OWED-GATE-174"' "$DEF" | wc -l | tr -d ' ')" = 1 ]
    DG="$(awk -F '\t' '$2 == "OWED-GATE-174" { print $1; exit }' "$DEF")"
    chk "seam: the OWED-GATE-174 deferral names a CM-* gate that the §11.4.$N block names" \
        eval 'case "$DG" in CM-?*) grep -F -q -- "$DG" "$BLK" ;; *) false ;; esac'
else
    fail "seam: scripts/gates/gate_ledger_deferrals.tsv missing"
fi
chk "seam: this gate's paired mutation test exists" [ -f "$ROOT/scripts/gates/cm_repro_first_anchor_wired_mutation_test.sh" ]
HOOK="$ROOT/scripts/post_update_hook.sh"
if [ -f "$HOOK" ]; then
    chk "seam: post_update_hook.sh runs this gate on every pull" has "$HOOK" "cm_repro_first_anchor_wired.sh"
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
