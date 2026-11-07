#!/usr/bin/env bash
# cm_release_gate_anchor_wired.sh — gate CM-RELEASE-GATE-ANCHOR-WIRED
#
# Purpose
#   Proves the §11.4.298 rule ("Release gate per product": a deployable build is deployed or
#   tagged only after a full, deterministic LIVE run of every existing test on connected target
#   hardware of its product and a §11.4.293 comparison against the build that hardware carried
#   before; a product without connected hardware or without a baseline is BLOCKED, never green)
#   is present exactly once, complete, and cross-referenced in BOTH directions across the canon:
#     * Constitution.md        one `### §11.4.298` block carrying the forensic note, the seven
#                              clauses (A)..(G), the closed four-value gate-state table, the
#                              honest boundary, every gate token, every escape-hatch flag and
#                              the citations to the anchors it composes;
#     * the composed anchor    §11.4.293 carries a dated "Refinement note (2026-11-07, release
#                              gate)" pointing back at §11.4.298 and stating the one amended
#                              point of its clause (F);
#     * the four mirrors       CLAUDE / AGENTS / QWEN / GEMINI each carry exactly one compact
#                              §11.4.298 block-start with the four gate states, the per-product
#                              rule, the connected-hardware rule and the gate token;
#     * generated artefacts    constitution_index.yaml, the group file, the progressive rule
#                              file and catalog;
#     * the seams              the propagation data-pack row, the generated propagation
#                              wrappers, the rule-to-seam binding, the OWED-GATE-185 deferral
#                              row (naming a gate the canon block names) and the post-update
#                              hook that runs this gate.
#   It proves the RULE is present and wired. It does NOT prove that any build was run on
#   hardware, compared, gated or reported (§11.4.6): that item-level seam is the deferred gate
#   registered as OWED-GATE-185, implemented by the consuming project. Its name is read from the
#   deferral registry, never written in this file: a literal CM- token of another gate in a
#   non-mutation-test .sh counts as an implementation site for the §11.4.227(A) ledger, which
#   would turn a deferral into a phantom. No product or device name appears in this file.
#
# Usage
#   cm_release_gate_anchor_wired.sh [--root <constitution-dir>] [--quiet]
#   cm_release_gate_anchor_wired.sh --help
#   --root defaults to the constitution directory that holds this script.
#
# Exit codes
#   0  PASS    every check passed
#   1  FAIL    at least one check failed (each failure is named on stdout)
#   2  BLIND   the instrument could not be trusted (control needle failed, or
#              Constitution.md is absent); a zero-failure result is never reported
#              from a blind instrument (§11.4.201(6), §11.4.273)
#   64 usage error
#
# Instrument discipline (§11.4.273): block extraction matches STRUCTURE (a line-anchored
# heading), never a bare literal, so a mid-body citation of §11.4.298 is never counted as
# the block. Before any verdict the extractors are run against synthetic documents whose
# answer is known (positive needle, prefix-collision needle, mid-body-citation decoy) and
# against the real neighbouring anchor §11.4.286 in the real files.
#
# Dependencies: bash, awk, grep, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
GATE="CM-RELEASE-GATE-ANCHOR-WIRED"
N=298

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
# names_cm_gate_in_block TOKEN -> true when TOKEN is a CM-* gate name that the canon block ($BLK) names
names_cm_gate_in_block() { case "$1" in CM-?*) grep -F -q -- "$1" "$BLK" ;; *) false ;; esac; }
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

# The seven clause headings of §11.4.298, (A) to (G).
CLAUSES=(
    '**(A) SCOPE: EVERY DEPLOYABLE BUILD, EVERY DEPLOYMENT, EVERY TAG.**'
    '**(B) THE LIVE RUN: EVERY EXISTING TEST, ON CONNECTED TARGET HARDWARE.**'
    '**(C) PER PRODUCT.**'
    '**(D) THE GATE STATE — closed set, four values.**'
    '**(E) RECONCILIATION WITH §11.4.293(F) AND WITH A CONSUMER'"'"'S DEV-TAG RULE.**'
    '**(F) THE RECORD AND THE REPORT.**'
    '**(G) WHAT THIS ANCHOR DOES NOT CHANGE.**'
)

# ── 1. canon block ───────────────────────────────────────────────────────────
BLK="$TMP/block$N.txt"
block_of "$CANON" "$N" >"$BLK"
chk "canon: exactly one '### §11.4.$N' heading in Constitution.md" [ "$(count_heads "$CANON" "$N")" = 1 ]
chk "canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)" [ "$(count_blockstarts "$CANON" "$N")" = 1 ]
chk "canon: block is non-empty (heading found)" [ -s "$BLK" ]
HEADLINE="$TMP/headline.txt"; head -n 1 "$BLK" >"$HEADLINE"
chk "canon: heading names 'Release gate per product'" has "$HEADLINE" "Release gate per product"
chk "canon: heading names 'connected target hardware'" has "$HEADLINE" "connected target hardware"
chk "canon: heading names 'is BLOCKED, never green'" has "$HEADLINE" "is BLOCKED, never green"
chk "canon: heading carries the mandate date 2026-11-07" has "$HEADLINE" "2026-11-07"

for c in "${CLAUSES[@]}"; do
    chk "canon: block carries clause heading $c" has "$BLK" "$c"
done

# The four rows of the closed gate-state table, each at a line start.
for st in RELEASABLE BLOCKED-NO-HARDWARE BLOCKED-NO-BASELINE REFUSED-REGRESSED; do
    chk "canon: gate-state table has a row for \`$st\`" has_re "$BLK" "^\\| \`$st\` \\|"
done
chk "canon: gate-state table has exactly four state rows" \
    [ "$(grep -c -E '^\| `(RELEASABLE|BLOCKED-NO-HARDWARE|BLOCKED-NO-BASELINE|REFUSED-REGRESSED)` \|' "$BLK")" = 4 ]

# Required marker phrases (fixed strings) — the rule's load-bearing content. The long markers at the end of the list are
# whole sentences with their neighbours, so a word inserted inside a rule (an exception, a weaker condition) turns the gate red.
MARKERS=(
    'an image or build may be deployed or tagged only after full deterministic LIVE testing on connected target hardware'
    'a baseline PASS that becomes INCONCLUSIVE, SKIPPED or absent counts as a regression'
    'and its text names no product and no device'
    'Those texts are not restated here'
    'no anchor makes the §11.4.293 verdict the condition of a DEPLOYMENT'
    'This anchor adds exactly those'
    'A DEPLOYABLE BUILD is every artifact a consuming project produces to run on its target hardware'
    'the project declares its artifact kinds as DATA'
    'A DEPLOYMENT is any act that puts a deployable build anywhere other than the test hardware of its own live run'
    'A TAG is any tag that names the build'
    'with "flashed" read as "installed on the target and verified there"'
    'executes every existing test of the product'"'"'s suite'
    'a subset, a spot check or the tests touched by the change is not this run'
    'that is connected to the harness while the run executes and is identified by the identity read from the target at run time'
    'An emulator, a simulator, a host-only run, a replayed or copied record, or a run on hardware of another product is never this run'
    'and absent is not PASS'
    'no existing test is dropped, skipped or quarantined out of the comparison'
    'A PRODUCT is each distinct deliverable the consuming project declares as DATA'
    'The gate is evaluated for every product separately'
    'never stand for another, even when the products share code or a build'
    'needs the state `RELEASABLE` for every product it covers'
    'There is no fifth state and no default state'
    'a product with no live-run record is `BLOCKED-NO-HARDWARE`'
    'Only `RELEASABLE` is green'
    'never as passed, provisional or skipped'
    'never by a substitute target'
    'This anchor amends §11.4.293(F) at exactly one point'
    'gets no tag of any class'
    'keeps the §11.4.293(F) allowance'
    'and that build is never deployed'
    'it tags a build only after the live run'
    'needs its own recorded operator decision'
    'one machine-written gate record per product it covers'
    'state each product'"'"'s state first'
    'is refused for that product'
    '§11.4.293 keeps every clause except the one point of clause (E)'
    'A `RELEASABLE` state does not prove a build correct'
    'Honest boundary'
    'it cannot see which hardware a consumer has connected'
    'CM-COVENANT-114-298-PROPAGATION'
    'CM-RELEASE-GATE-ANCHOR-WIRED'
    'OWED-GATE-185'
    'OWED-GATE-176'
    '| `RELEASABLE` | the live run of clause (B) completed on connected hardware of the product AND its §11.4.293 verdict against the product'"'"'s baseline is `NO-WORSE-PROVEN` | allowed, subject to every other seam | allowed, subject to every other seam | allowed |'
    '| `BLOCKED-NO-HARDWARE` | no target hardware of the product was connected and identified for the live run, or the run did not complete on it | refused | refused | refused |'
    '| `BLOCKED-NO-BASELINE` | the live run completed and the §11.4.293 verdict is `INCOMPARABLE-BASELINE-MISSING` | refused | refused | only as §11.4.293(F) states, the blocker stated first |'
    '| `REFUSED-REGRESSED` | the live run completed and the §11.4.293 verdict is `REGRESSED` | refused | refused | only as §11.4.293(F) states, the regressions stated first |'
    'A product'"'"'s first deployable build has no previous build and so no baseline: it stays `BLOCKED-NO-BASELINE` (no deployment, no release tag) until the operator records how a first baseline is accepted (OPERATOR-DECISION-REQUIRED, §11.4.66); this anchor decides nothing about it.'
)
for m in "${MARKERS[@]}"; do
    chk "canon: block carries marker '$m'" has "$BLK" "$m"
done
for fl in --deploy-without-live-run --tag-without-live-run --emulator-counts-as-target --partial-suite-release \
          --reuse-other-product-verdict --no-hardware-is-skip --deploy-blocked-product --release-covers-blocked-product; do
    chk "canon: block names escape-hatch flag $fl as forbidden" has "$BLK" "$fl"
done
chk "canon: block carries a line-start 'Classification: universal'" has_re "$BLK" '^Classification: universal'
chk "canon: block carries a Canonical authority line" has "$BLK" "**Canonical authority:**"
chk "canon: block carries the non-compliance release-blocker line" has "$BLK" "Non-compliance is a release blocker"

# Cross-references the rule must carry (boundary-safe: §11.4.6 never matches §11.4.66).
for n in 6 17 35 40 50 66 108 114 115 118 135 151 185 200 227 236 248 251 262 264 289 290 292 293; do
    chk "canon: block cites §11.4.$n" has_re "$BLK" "§11\\.4\\.$n([^0-9]|\$)"
done
chk "canon: block cites §1.1" has_re "$BLK" '§1\.1([^0-9]|$)'

# ── 2. back-pointer: the composed anchor points at §11.4.298 ─────────────────
REFINED_IDS="293"
for n in $REFINED_IDS; do
    RB="$TMP/refined_$n.txt"; block_of "$CANON" "$n" >"$RB"
    chk "refined §11.4.$n: block exists exactly once" [ "$(count_heads "$CANON" "$n")" = 1 ]
    chk "refined §11.4.$n: carries 'Refinement note (2026-11-07, release gate)'" has "$RB" "Refinement note (2026-11-07, release gate)"
    chk "refined §11.4.$n: refinement note cites §11.4.298" has_re "$RB" "§11\\.4\\.298([^0-9]|\$)"
done
RB293="$TMP/refined_293.txt"
chk "refined §11.4.293: the note states the one amended point" has "$RB293" "amends clause (F) at exactly one point"
chk "refined §11.4.293: the note names 'no tag of any class'" has "$RB293" "gets no tag of any class"
chk "refined §11.4.293: the note keeps the other clauses" has "$RB293" "clauses (A) to (E) and (G) are unchanged"

# ── 3. the four context mirrors ──────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    P="$ROOT/$f"
    if [ ! -f "$P" ]; then fail "mirror $f: file missing"; continue; fi
    CB="$TMP/car_$f.txt"; carrier_block "$P" "$N" >"$CB"
    chk "mirror $f: exactly one §11.4.$N block-start" [ "$(count_blockstarts "$P" "$N")" = 1 ]
    chk "mirror $f: block names the four gate states" has "$CB" "\`RELEASABLE\` (live run complete and \`NO-WORSE-PROVEN\`), \`BLOCKED-NO-HARDWARE\`, \`BLOCKED-NO-BASELINE\`, \`REFUSED-REGRESSED\`"
    chk "mirror $f: block names the connected-hardware rule" has "$CB" "connected while the run executes and identified from the target"
    chk "mirror $f: block names the per-product rule" has "$CB" "one product's verdict never stands for another"
    chk "mirror $f: block names the one-point amendment of §11.4.293(F)" has "$CB" "no tag of any class without the live run"
    chk "mirror $f: block names the first-build rule" has "$CB" "a first build has no baseline and stays \`BLOCKED-NO-BASELINE\`"
    chk "mirror $f: block names gate $GATE" has "$CB" "$GATE"
    chk "mirror $f: block points at Constitution.md §11.4.$N" has "$CB" "[\`Constitution.md\`](Constitution.md) §11.4.$N"
done

# ── 4. generated artefacts ───────────────────────────────────────────────────
IDX="$ROOT/constitution_index.yaml"
if [ -f "$IDX" ]; then
    awk -v id="- id: 11.4.$N" '$0 == id { p = 1; print; next } p && /^- id: / { exit } p { print }' "$IDX" >"$TMP/idx.txt"
    chk "index: constitution_index.yaml has an entry for 11.4.$N" [ -s "$TMP/idx.txt" ]
    chk "index: 11.4.$N propagation_gate is CM-COVENANT-114-$N-PROPAGATION" has "$TMP/idx.txt" "propagation_gate: CM-COVENANT-114-$N-PROPAGATION"
    chk "index: 11.4.$N group is project-lifecycle-and-release" has "$TMP/idx.txt" "group: project-lifecycle-and-release"
    chk "index: 11.4.$N classification is universal" has "$TMP/idx.txt" "classification: universal"
else
    fail "index: constitution_index.yaml missing"
fi
GRP="$ROOT/groups/project-lifecycle-and-release.md"
if [ -f "$GRP" ]; then
    chk "group: project-lifecycle-and-release.md carries exactly one §11.4.$N block" [ "$(count_heads "$GRP" "$N")" = 1 ]
else
    fail "group: groups/project-lifecycle-and-release.md missing"
fi
chk "progressive: rules/11.4.$N.md exists" [ -s "$ROOT/progressive/rules/11.4.$N.md" ]
CAT="$ROOT/progressive/catalog.json"
if [ -f "$CAT" ]; then
    chk "progressive: catalog.json lists §11.4.$N" has "$CAT" "\"id\":\"§11.4.$N\""
    chk "progressive: catalog.json points at rules/11.4.$N.md" has "$CAT" "\"file\":\"progressive/rules/11.4.$N.md\""
else
    fail "progressive: catalog.json missing"
fi

# ── 5. seams: data-pack row, generated wrappers, seam binding, deferral, hook ─
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
    OWED_IDS="OWED-GATE-185"
    for owed in $OWED_IDS; do
        chk "seam: gate_ledger_deferrals.tsv has exactly one $owed row" \
            [ "$(awk -F '\t' -v o="$owed" '$2 == o' "$DEF" | wc -l | tr -d ' ')" = 1 ]
        DG="$(awk -F '\t' -v o="$owed" '$2 == o { print $1; exit }' "$DEF")"
        chk "seam: the $owed deferral names a CM-* gate that the §11.4.$N block names" names_cm_gate_in_block "$DG"
    done
else
    fail "seam: scripts/gates/gate_ledger_deferrals.tsv missing"
fi
chk "seam: this gate's paired mutation test exists" [ -f "$ROOT/scripts/gates/cm_release_gate_anchor_wired_mutation_test.sh" ]
HOOK="$ROOT/scripts/post_update_hook.sh"
if [ -f "$HOOK" ]; then
    chk "seam: post_update_hook.sh runs this gate on every pull" has "$HOOK" "cm_release_gate_anchor_wired.sh"
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
