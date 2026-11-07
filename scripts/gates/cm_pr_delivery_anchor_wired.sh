#!/usr/bin/env bash
# cm_pr_delivery_anchor_wired.sh — gate CM-PR-DELIVERY-ANCHOR-WIRED
#
# Purpose
#   Proves the §11.4.297 rule ("Pull-request delivery": a project that declares it by a
#   recorded operator decision delivers each task on one task branch with one pull request
#   per task id, assigned to its configured reviewers and read back, self-reviewed on the
#   platform and merged by its author agent unless the project configures a human merge gate,
#   only after its source-correctness GO and only in a form that keeps every reviewed commit on
#   `main`, read back and then retired;
#   evidence it cites resolves from its head tree; a submodule change lands as its own pull
#   request before the parent pin bump with mirror parity read back; enforcement claims carry
#   ENFORCED, PROVISIONAL or UNCONFIRMED) is present exactly once, carries its load-bearing
#   phrases, matches its pinned text (section 0: the canon block, the mirror block and the three
#   refinement notes, each note as its whole paragraph, each pinned by the sha256 of its text without whitespace), and is cross-referenced in BOTH
#   directions across the canon:
#     * Constitution.md        one `### §11.4.297` block carrying the forensic order, the
#                              nine clauses (A)..(I) with the three amendment points
#                              (A.1)..(A.3) of §11.4.288, the honest boundary, every gate
#                              token, every escape-hatch flag and the citations to the
#                              anchors it composes;
#     * the composed anchors   §11.4.288 / .292 / .293 each carry a dated "Refinement note
#                              (2026-11-07)" pointing back at §11.4.297 (the §11.4.288 note
#                              states the three amendment points and nothing more);
#     * the four mirrors       CLAUDE / AGENTS / QWEN / GEMINI each carry exactly one compact
#                              §11.4.297 block-start with the landing forms, the self-review,
#                              the human merge gate, the reviewer key,
#                              the parity words, the enforcement words and both gate tokens;
#     * generated artefacts    constitution_index.yaml, the group file, the progressive rule
#                              file and catalog;
#     * the seams              the propagation data-pack row, the generated propagation
#                              wrappers, the rule-to-seam binding, the OWED-GATE-182..184
#                              deferral rows (each naming a gate the canon block names), the
#                              account-name gate with its mutation test, and the post-update
#                              hook that runs both gates.
#   It proves the RULE is present and wired. It does NOT prove that any pull request was opened,
#   reviewed, read back, landed or retired, or that any mirror holds a commit (§11.4.6): those
#   item-level seams are the deferred gates registered as OWED-GATE-182..184, implemented by the
#   consuming project. Their names are read from the deferral registry, never written in this
#   file: a literal CM- token of another gate in a non-mutation-test .sh counts as an
#   implementation site for the §11.4.227(A) ledger, which would turn a deferral into a phantom.
#   No account name appears in this file; account names are consumer DATA (§11.4.297(D)).
#
# Usage
#   cm_pr_delivery_anchor_wired.sh [--root <constitution-dir>] [--quiet]
#   cm_pr_delivery_anchor_wired.sh --help
#   --root defaults to the constitution directory that holds this script.
#   --print-digests prints the current text digests in the form of the PIN_ lines of section 0 and exits 0
#   (used to re-pin after a reviewed text change; it checks nothing).
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
# heading), never a bare literal, so a mid-body citation of §11.4.297 is never counted as
# the block. Before any verdict the extractors are run against synthetic documents whose
# answer is known (positive needle, prefix-collision needle, mid-body-citation decoy) and
# against the real neighbouring anchor §11.4.286 in the real files.
#
# Dependencies: bash, awk, grep, mktemp, sha256sum or shasum. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
PRINT=0
GATE="CM-PR-DELIVERY-ANCHOR-WIRED"
# The account-name gate's token is read from that gate's own GATE= line at run time, so this file names only its
# own token and the §11.4.227(A) ledger attributes the account-name gate to its real site, never to this file.
NAMEGATE_FILE="scripts/gates/cm_pr_delivery_account_name_free.sh"
N=297

usage() { echo "usage: ${0##*/} [--root <constitution-dir>] [--quiet] | --print-digests | --help" >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        --print-digests) PRINT=1; shift ;;
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
NAMEGATE=""
[ -f "$ROOT/$NAMEGATE_FILE" ] && NAMEGATE="$(sed -n 's/^GATE="\(CM-[A-Z0-9-]*\)"$/\1/p' "$ROOT/$NAMEGATE_FILE" | head -n 1)"
NAMEGATE="${NAMEGATE:-<account-name gate token unreadable>}"
[ "$(count_heads "$CANON" 286)" = 1 ]             || blind "real-file control needle: expected exactly one §11.4.286 heading in Constitution.md"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    [ -f "$ROOT/$f" ] || continue
    [ "$(count_blockstarts "$ROOT/$f" 286)" = 1 ] || blind "real-file control needle: expected exactly one §11.4.286 block-start in $f"
done

# ── 0. text pins: the whole wording of each rule text, not only its markers ───
# The marker list proves that load-bearing phrases are present; it cannot see a sentence added between them (an
# exception, a weaker condition, a duty no marker spans: audit 2 of 2026-11-07 kept every marker and weakened the text
# in 27 of 30 ways). Each rule text below is therefore pinned by the sha256 of its text with all whitespace removed: ANY
# change of wording turns this gate red until its pin is updated here, a reviewed edit of this file in the same
# commit as the text (--print-digests prints the current values). A whitespace-only change keeps the pin. A pin
# proves that the text is the reviewed text; it says nothing about whether that text is right. A refinement note is
# pinned as its whole paragraph (the lines between two blank lines or headings around the marker line), so a sentence
# added on the line after the note, or on the line before it, with no blank line between, is pinned text too (audit 3
# of 2026-11-07, B1: a pin of the marker line alone let a continuation line through).
PIN_CANON='f492ef1638ead21cc17a199082323b414e11b5079efe1918372a2ad6e4ea4287'       # the §11.4.297 block of Constitution.md
PIN_CARRIER='37e69a1012661856a78c6ff421163e1ce12bf6f8e79501bed098c8c47809b4fb'     # the §11.4.297 block of each mirror (CLAUDE.md, AGENTS.md, QWEN.md, GEMINI.md)
PIN_NOTE_288='9bd14bfd64117be09395b474610cce5ed7fb6287a18b3d3605d5f3168cad0352'    # the paragraph of the "Refinement note (2026-11-07)." of §11.4.288
PIN_NOTE_292='f42431ef5888ffbda7c5aa4fa41a0ed7ce6e6a909e1511e159f9690cc4d82d56'    # the paragraph of the "Refinement note (2026-11-07)." of §11.4.292
PIN_NOTE_293='58cc6e8b8fc88f53b733c5e3183da26ae7e735c3f3c5bb1033f183c8f70634db'    # the paragraph of the "Refinement note (2026-11-07)." of §11.4.293
command -v sha256sum >/dev/null 2>&1 && SHA=(sha256sum) || { command -v shasum >/dev/null 2>&1 && SHA=(shasum -a 256); } || blind "sha256sum or shasum is needed for the text pins"
# digest -> the sha256 of stdin with every blank, tab and newline removed (so a whitespace-only change, also one that
# splits or joins words, keeps the digest; any other change of the text alters it)
digest() { awk '{ for (i = 1; i <= NF; i++) printf "%s", $i }' | "${SHA[@]}" | awk '{ print $1 }'; }
[ "$(printf 'a  b\n\tc \n' | digest)" = "$(printf 'abc' | digest)" ] || blind "pin digest control needle: a whitespace-only change altered the digest"
[ "$(printf 'a b c' | digest)" != "$(printf 'a b d' | digest)" ]      || blind "pin digest control needle: a changed word kept the digest"
# note_para MARKER -> the whole paragraph of stdin (the lines between two blank lines or headings) of every line that
# holds MARKER (a fixed string)
note_para() {
    awk -v m="$1" 'function flush() { if (hit) printf "%s", buf; buf = ""; hit = 0 }
        /^[ \t]*$/ || /^#/ { flush(); next }
        { buf = buf $0 "\n"; if (index($0, m)) hit = 1 }
        END { flush() }'
}
[ "$(printf 'intro\n\nlead-in\n**N (x).** first\ncontinued\n\nlater\n### h\nnext\n' | note_para '**N (x).**')" = "$(printf 'lead-in\n**N (x).** first\ncontinued')" ] \
    || blind "note paragraph control needle: the paragraph of a note was not read whole (lead-in and continuation line), or a neighbouring paragraph was read"
pin_chk() { # pin_chk <label> <pinned digest> <text file>
    local cur=""
    [ -s "$3" ] && cur="$(digest <"$3")"
    if [ -n "$cur" ] && [ "$cur" = "$2" ]; then pass "$1"; else fail "$1"; printf '      pinned %s, now %s\n' "$2" "${cur:-<no text>}"; fi
}
note_pin() { case "$1" in 288) printf '%s' "$PIN_NOTE_288" ;; 292) printf '%s' "$PIN_NOTE_292" ;; 293) printf '%s' "$PIN_NOTE_293" ;; esac; }
block_of "$CANON" "$N" >"$TMP/pin_canon.txt"
for n in 288 292 293; do block_of "$CANON" "$n" | note_para '**Refinement note (2026-11-07).**' >"$TMP/pin_note_$n.txt"; done
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do [ -f "$ROOT/$f" ] && carrier_block "$ROOT/$f" "$N" >"$TMP/pin_car_$f.txt"; done
if [ "$PRINT" = 1 ]; then
    printf "PIN_CANON='%s'\n" "$(digest <"$TMP/pin_canon.txt")"
    for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do [ -f "$TMP/pin_car_$f.txt" ] && printf "PIN_CARRIER='%s'  # %s\n" "$(digest <"$TMP/pin_car_$f.txt")" "$f"; done
    for n in 288 292 293; do printf "PIN_NOTE_%s='%s'\n" "$n" "$(digest <"$TMP/pin_note_$n.txt")"; done
    exit 0
fi
pin_chk "pinned: the §11.4.$N block of Constitution.md matches PIN_CANON" "$PIN_CANON" "$TMP/pin_canon.txt"
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    [ -f "$ROOT/$f" ] || continue
    pin_chk "pinned: mirror $f §11.4.$N block matches PIN_CARRIER" "$PIN_CARRIER" "$TMP/pin_car_$f.txt"
done
for n in 288 292 293; do
    pin_chk "pinned: the §11.4.$n refinement note (2026-11-07) matches PIN_NOTE_$n" "$(note_pin "$n")" "$TMP/pin_note_$n.txt"
done

# The nine clause headings of §11.4.297, (A) to (I), and the three amendment points of (A).
CLAUSES=(
    '**(A) DECLARATION, AND THE RECONCILIATION WITH §11.4.288.**'
    '**(B) ONE TASK, ONE BRANCH, ONE PULL REQUEST.**'
    '**(C) SELF-REVIEW AND MERGE BY THE AUTHOR AGENT, UNLESS A HUMAN MERGE GATE IS CONFIGURED; READ BACK, THEN RETIRED.**'
    '**(D) REVIEWERS: A CONFIGURED LIST, REQUESTED AND READ BACK, NEVER NAMED HERE.**'
    '**(E) EVIDENCE A REVIEWER CAN RESOLVE.**'
    '**(F) SUBMODULE PULL REQUESTS, THE PIN BUMP AND MIRROR PARITY.**'
    '**(G) ENFORCEMENT WORDS.**'
    '**(H) GATES, TESTS AND PAIRED MUTATIONS.**'
    '**(I) WHAT THIS ANCHOR DOES NOT CHANGE.**'
    '(A.1) NECESSITY.'
    '(A.2) THE MERGE IS THE LANDING.'
    '(A.3) THE LANDING FORM.'
)

# ── 1. canon block ───────────────────────────────────────────────────────────
BLK="$TMP/block$N.txt"
block_of "$CANON" "$N" >"$BLK"
chk "canon: exactly one '### §11.4.$N' heading in Constitution.md" [ "$(count_heads "$CANON" "$N")" = 1 ]
chk "canon: exactly one §11.4.$N block-start of any form in Constitution.md (no duplicate form)" [ "$(count_blockstarts "$CANON" "$N")" = 1 ]
chk "canon: block is non-empty (heading found)" [ -s "$BLK" ]
HEADLINE="$TMP/headline.txt"; head -n 1 "$BLK" >"$HEADLINE"
chk "canon: heading names 'Pull-request delivery'" has "$HEADLINE" "Pull-request delivery"
chk "canon: heading names 'one pull request per task id at a time'" has "$HEADLINE" "one pull request per task id at a time"
chk "canon: heading names 'no account is named in this constitution'" has "$HEADLINE" "no account is named in this constitution"
chk "canon: heading names 'self-reviewed on the platform by its author agent'" has "$HEADLINE" "self-reviewed on the platform by its author agent"
chk "canon: heading names 'where the project configures a human merge gate'" has "$HEADLINE" "where the project configures a human merge gate"
chk "canon: heading carries the mandate date 2026-11-07" has "$HEADLINE" "2026-11-07"

for c in "${CLAUSES[@]}"; do
    chk "canon: block carries clause heading $c" has "$BLK" "$c"
done

# Required marker phrases (fixed strings) — the rule's load-bearing content. The long markers at the end of the list are
# whole sentences with their neighbours, so a word inserted inside a rule (an exception, a weaker condition) turns the gate red.
MARKERS=(
    'except the project-specific parts (the account names of assignees and reviewers)'
    'no account name enters this constitution'
    'the agent that creates a pull request self-reviews it (real review comments in the pull request) and then merges it'
    'the author agent of a pull request reviews and merges it, unless the project configures a human merge gate'
    'a delivery mode a consuming project selects only by a recorded operator decision'
    'in ONE tracked configuration file'
    'the landing form (`ff-only` or `merge-commit`)'
    'the merger (`author-agent` by default, or `human`, a human merge gate, clause (C)(2))'
    '`off`, `expected` = warn and write an audit line, `enforced` = refuse'
    'An unknown key or a value outside its closed set makes the delivery refuse before anything is committed'
    'Without the declaration, §11.4.288 applies as written'
    'AMENDS §11.4.288 at exactly three points'
    'every other sentence of §11.4.288 binds such a project unchanged'
    'is the recorded necessity of §11.4.288(B)(2)'
    'It legitimises no other vehicle'
    'is the landing step of §11.4.288(B)(1)'
    'Against §11.4.288(B)(1), which lets no approval wait hold a GO'"'"'d change off `main`, this point admits exactly two: an approval the project configures as required (condition (f) of clause (C)(2)) and, under a human merge gate, the merge by the human merger.'
    'it is never parked silently'
    'whose second parent is the reviewed head'
    'A squash merge and a rebase merge are FORBIDDEN'
    'with a plain value: one or more item ids'
    'and nothing else on that line'
    'the delivery refuses before anything is staged'
    'one task branch named `<prefix>/<id>-<slug>`'
    '`Multi-Task-Reason:`'
    'is reused for every later commit of that task'
    'and one open pull request against the base at a time: after that pull request has landed and its branch is retired and pruned (clause (C)(4)), a later commit of the same task id opens a new task branch and a new pull request.'
    'For a submodule pull request clause (F)(2) keeps the task branch until the parent pull request that records it has landed, so a delete-at-merge option is never used there, even on a single declared upstream.'
    'the pull request stays open (the refusal never closes it, and once it is reported as this point requires, merge condition (c) of clause (C)(2) holds for that account)'
    'the delivery refuses and lists those commits'
    'A detached `HEAD` is refused'
    'the remote tip is read with `git ls-remote`'
    'a push tool'"'"'s exit status is not evidence'
    'Opening is idempotent'
    'land one at a time in a recorded order'
    'merge, never rebase, never force'
    'The commit and publish steps of the delivery tooling never merge, close, force-push or delete'
    'under a human merge gate no agent and no tool takes it'
    'it reads the whole diff of the head it will merge and posts a review on that pull request'
    'every finding is a review comment anchored to the diff line it concerns'
    'A review with no reading record'
    'it is never posted through another account to obtain an approval'
    'The self-review is read back from the platform'
    'it is never the source-correctness GO'
    'the producer never gates its own change'
    'By default the merger is the author agent, which owns the merge process'
    '(a) the source-correctness GO is recorded, as a record the merger reads, for exactly the head being merged'
    'the merge call pins the reviewed head where the platform offers it'
    'A project configures a HUMAN MERGE GATE (merger `human`)'
    'no agent presses a merge button or calls a merge interface of the hosting platform'
    'so the source-correctness GO of §11.4.288 stays merge condition (a)'
    'is not a reviewer assignment and never counts as one'
    'the state merged, the merge commit id and the form check'
    'the task branch is KEPT'
    'only when its head is an ancestor of `main` on every declared upstream'
    '`git fetch --prune`'
    'is not given new work until that branch is pruned'
    'without the read-back is a bluff'
    'one list per repository where the repositories differ'
    '`pr_reviewers` is the default'
    'an absent key never means "no reviewers"'
    'no environment variable or command-line switch replaces or empties it'
    'This constitution names no account'
    'the hosting platform refuses a review request from the author'
    'no reviewer is possible'
    'an assignment counts only when the platform shows it'
    'is reported with the platform'"'"'s own text'
    'never removes the account from the list'
    'is never worked around by requesting another account'
    'cited by a repository-relative path'
    '`git show <head>:<path> | sha256sum`'
    'is INCONCLUSIVE for that pull request, never PASS'
    'it never replaces it'
    'standing list of tool-written paths'
    'with the reason `generated-regeneration`'
    'No fifth reason is added to §11.4.293(A)(4)'
    'is an INTERPRETATION of §11.4.293(A)(4), stated here as one and not an amendment of it'
    'a row written or edited by hand, and any other path, is never `generated-regeneration`'
    'on a task branch with the same name as the parent'"'"'s'
    'The submodule pull request lands first'
    'only after the submodule pull request is read back as merged'
    'A merge on the hosting platform moves `main` on that host only'
    '`PRESENT` (it contains the pinned commit), `MIRROR-LAG <tip>` (it does not) or `UNREACHABLE`'
    'only when every declared upstream reads `PRESENT`'
    '"pushed to all upstreams" is never written without the per-upstream read-back'
    '`ENFORCED` (the mechanism exists at the repository'"'"'s `HEAD` and runs by default on the delivery path)'
    '`PROVISIONAL` (it exists only as a staged patch or a draft, or has run only against stubs'
    '`UNCONFIRMED` (it is implemented nowhere'
    'These words are not item statuses'
    'No text calls a branch protected on the hosting platform unless the platform'"'"'s protection read-back records it'
    'a test double is legal here because the test proves the tooling'"'"'s own logic'
    'a scan proving that the commit and publish steps hold no merge, close, force-push or delete call'
    'and any merge call under a human merge gate'
    'that was merged without a source-correctness GO recorded for the merged head'
    'while the remote base tip was not an ancestor of the merged head'
    'a merge without a recorded GO for the merged head, a merge on a stale base'
    'A stub run is `PROVISIONAL` evidence of the tooling'
    'read at run time from the consumer'"'"'s own configuration and never stored here'
    '`SKIP` (exit 3) when no consumer list exists'
    'never a substitute for the source-correctness GO'
    'A project without the declaration keeps §11.4.288 as written'
    'Honest boundary'
    'CM-COVENANT-114-297-PROPAGATION'
    'CM-PR-DELIVERY-ANCHOR-WIRED'
    'OWED-GATE-182'
    'OWED-GATE-183'
    'OWED-GATE-184'
    'It merges only when all of these are read back: (a) the source-correctness GO is recorded, as a record the merger reads, for exactly the head being merged (a GO for an earlier head, a GO that cannot be read, or no GO refuses the merge); (b) its self-review of that head is on the platform with every finding answered; (c) the reviewer requests of clause (D) are shown by the platform, or a refused reviewer is reported under clause (D)(4); (d) the head on the platform equals the reviewed head (a head that moved after the self-review or the GO is reviewed again first, and the merge call pins the reviewed head where the platform offers it); (e) the serial order of clause (B)(5) admits it; (f) every approval the project configures as required is present; (g) the remote base tip, fetched right before the merge, is an ancestor of the reviewed head (when the base has moved, it is merged into the task branch under clause (B)(5) and the new head is reviewed again first). It merges only in the declared form of point (A.3).'
    'then no agent presses a merge button or calls a merge interface of the hosting platform: the author agent self-reviews, reports the pull request ready with (a) to (g) read back, and the human merger lands it.'
    '(A.3) THE LANDING FORM. The landing is a fast-forward of `main` to the reviewed head (the form of §11.4.288(B)(3)) or a merge commit on `main` whose first parent is the previous `main` tip and whose second parent is the reviewed head.'
    'the task branch is deleted locally and on every upstream that holds it only when its head is an ancestor of `main` on every declared upstream (the §11.4.288(B)(4) count is zero). A platform option that deletes the branch at merge time is used only when the platform is the only declared upstream; otherwise the branch is deleted after the parity read-back of clause (F)(4), never at merge time. A task id whose merged branch'
    '(A.1) NECESSITY. The declared decision is the recorded necessity of §11.4.288(B)(2) for every task branch the delivery tooling creates; its identifier in the configuration is the record. It legitimises no other vehicle.'
    '(A.2) THE MERGE IS THE LANDING. The merge of a pull request that holds its source-correctness GO (§11.4.288 Terms), made under clause (C) by its author agent after the read-back self-review or, where the project configures a human merge gate, by the human merger, is the landing step of §11.4.288(B)(1). It adds no wait beyond the merge conditions of clause (C)(2): no manual QA, no open hardening item and no approval beyond what the project configures as required holds a GO'"'"'d pull request open. A pull request whose GO is older than the declared merge window is reported as stale in every report until it lands or is closed; it is never parked silently.'
    'A review with no reading record (an approval alone, a bare "looks good" or an empty body) is not a self-review. A platform that refuses an approval by the author records the self-review as a comment review; it is never posted through another account to obtain an approval. The self-review is read back from the platform (the review entry, the head commit id it names and its comments) before the merge.'
    'It is the author'"'"'s own multi-pass check (§11.4.92) made visible in the pull request: it is never the source-correctness GO, which stays the independent review of §11.4.142 / §11.4.209 / §11.4.235 (§11.4.240: the producer never gates its own change), and it never replaces the configured reviewers of clause (D).'
    'In both forms the reviewed head already contains the remote base tip (merge condition (g) of clause (C)(2)), so the content that lands is the content that was reviewed and tested, as §11.4.288(B)(3) requires; a merge commit made on a stale base is not this form.'
)
for m in "${MARKERS[@]}"; do
    chk "canon: block carries marker '$m'" has "$BLK" "$m"
done
chk "canon: block names gate $NAMEGATE" has "$BLK" "$NAMEGATE"
for fl in --squash-merge-OK --rebase-merge-OK --merge-without-GO --merge-on-stale-base --merge-without-self-review --self-review-is-the-GO \
          --agent-merges-under-human-gate --merge-moved-head --multi-task-branch --annotated-roadmap-item \
          --skip-push-readback --skip-reviewer-readback --drop-refused-reviewer --reviewer-names-in-constitution \
          --evidence-outside-repo-OK --delete-branch-before-parity --pin-before-submodule-merge \
          --claim-mirror-parity-without-readback --claim-server-side-protection; do
    chk "canon: block names escape-hatch flag $fl as forbidden" has "$BLK" "$fl"
done
chk "canon: block carries a line-start 'Classification: universal'" has_re "$BLK" '^Classification: universal'
chk "canon: block carries a Canonical authority line" has "$BLK" "**Canonical authority:**"
chk "canon: block carries the non-compliance release-blocker line" has "$BLK" "Non-compliance is a release blocker"

# Cross-references the rule must carry (boundary-safe: §11.4.6 never matches §11.4.66).
for n in 6 17 35 66 92 113 142 181 188 202 209 227 233 235 240 273 288 289 290 292 293 296; do
    chk "canon: block cites §11.4.$n" has_re "$BLK" "§11\\.4\\.$n([^0-9]|\$)"
done
chk "canon: block cites §1.1" has_re "$BLK" '§1\.1([^0-9]|$)'
chk "canon: block cites §2.1" has_re "$BLK" '§2\.1([^0-9]|$)'
chk "canon: block cites §9.2" has_re "$BLK" '§9\.2([^0-9]|$)'

# ── 2. back-pointers: the composed anchors point at §11.4.297 ────────────────
for n in 288 292 293; do
    RB="$TMP/refined_$n.txt"; block_of "$CANON" "$n" >"$RB"
    chk "refined §11.4.$n: block exists exactly once" [ "$(count_heads "$CANON" "$n")" = 1 ]
    chk "refined §11.4.$n: carries 'Refinement note (2026-11-07)'" has "$RB" "Refinement note (2026-11-07)"
    chk "refined §11.4.$n: refinement note cites §11.4.297" has_re "$RB" "§11\\.4\\.297([^0-9]|\$)"
done
RB288="$TMP/refined_288.txt"
chk "refined §11.4.288: the note states 'it amends this anchor at exactly three points'" has "$RB288" "it amends this anchor at exactly three points"
chk "refined §11.4.288: the note forbids squash and rebase landings" has "$RB288" "never a squash or rebase merge"
chk "refined §11.4.288: the note keeps every other sentence binding" has "$RB288" "binds such a project unchanged"
chk "refined §11.4.288: the note names the author agent's read-back self-review" has "$RB288" "by its author agent after a read-back self-review"
chk "refined §11.4.288: the note names the human merge gate" has "$RB288" "where the project configures a human merge gate"
chk "refined §11.4.288: the note requires the reviewed head to contain the base tip" has "$RB288" "and the reviewed head contains the base tip as (B)(3) requires"
chk "refined §11.4.288: the note names the two waits (B)(1) otherwise forbids" has "$RB288" 'that step admits exactly two waits that the "no approval wait" of (B)(1) otherwise forbids: an approval the project configures as required (merge condition (f) of §11.4.297(C)(2)) and, under a human merge gate, the human merger'"'"'s merge;'
chk "refined §11.4.293: the note adds no fifth reason" has "$TMP/refined_293.txt" "gains no fifth"
chk "refined §11.4.293: the note states the generated-regeneration reading as an interpretation" has "$TMP/refined_293.txt" "is an interpretation of (A)(4), stated as one in §11.4.297(E)(3), not an amendment"

# ── 3. the four context mirrors ──────────────────────────────────────────────
for f in CLAUDE.md AGENTS.md QWEN.md GEMINI.md; do
    P="$ROOT/$f"
    if [ ! -f "$P" ]; then fail "mirror $f: file missing"; continue; fi
    CB="$TMP/car_$f.txt"; carrier_block "$P" "$N" >"$CB"
    chk "mirror $f: exactly one §11.4.$N block-start" [ "$(count_blockstarts "$P" "$N")" = 1 ]
    chk "mirror $f: block names the two landing forms" has "$CB" "landing form (\`ff-only\` or \`merge-commit\`)"
    chk "mirror $f: block forbids squash and rebase landings" has "$CB" "never a squash or rebase merge"
    chk "mirror $f: block names the author agent's self-review and merge" has "$CB" "The author agent self-reviews the pull request on the platform"
    chk "mirror $f: block names the human merge gate" has "$CB" "under a human merge gate only the human merger merges"
    chk "mirror $f: block names the GO and base-tip merge conditions" has "$CB" "once the GO for that exact head, the self-review, the reviewer read-back, an unmoved head that contains the base tip"
    chk "mirror $f: block names the configured approvals among the merge conditions" has "$CB" "the serial order and every approval the project configures as required are read back"
    chk "mirror $f: headline merges only after the source-correctness GO" has "$CB" "only after its source-correctness GO and only in a form that keeps every reviewed commit on \`main\`"
    chk "mirror $f: block says one open pull request per task id at a time" has "$CB" "= one open pull request at a time;"
    chk "mirror $f: block keeps the submodule branch until the parent lands" has "$CB" "landed first, its branch kept until the parent lands;"
    chk "mirror $f: block names the default reviewer key" has "$CB" "default key \`pr_reviewers\`"
    chk "mirror $f: block says the reviewers are never named here" has "$CB" "never named here"
    chk "mirror $f: block names the parity words" has "$CB" "(\`PRESENT\`, \`MIRROR-LAG <tip>\`, \`UNREACHABLE\`)"
    chk "mirror $f: block names the enforcement words" has "$CB" "\`ENFORCED\`, \`PROVISIONAL\` or \`UNCONFIRMED\`"
    chk "mirror $f: block names gate $GATE" has "$CB" "$GATE"
    chk "mirror $f: block names gate $NAMEGATE" has "$CB" "$NAMEGATE"
    chk "mirror $f: block points at Constitution.md §11.4.$N" has "$CB" "[\`Constitution.md\`](Constitution.md) §11.4.$N"
done

# ── 4. generated artefacts ───────────────────────────────────────────────────
IDX="$ROOT/constitution_index.yaml"
if [ -f "$IDX" ]; then
    awk -v id="- id: 11.4.$N" '$0 == id { p = 1; print; next } p && /^- id: / { exit } p { print }' "$IDX" >"$TMP/idx.txt"
    chk "index: constitution_index.yaml has an entry for 11.4.$N" [ -s "$TMP/idx.txt" ]
    chk "index: 11.4.$N propagation_gate is CM-COVENANT-114-$N-PROPAGATION" has "$TMP/idx.txt" "propagation_gate: CM-COVENANT-114-$N-PROPAGATION"
    chk "index: 11.4.$N group is git-and-data-safety" has "$TMP/idx.txt" "group: git-and-data-safety"
    chk "index: 11.4.$N classification is universal" has "$TMP/idx.txt" "classification: universal"
else
    fail "index: constitution_index.yaml missing"
fi
GRP="$ROOT/groups/git-and-data-safety.md"
if [ -f "$GRP" ]; then
    chk "group: git-and-data-safety.md carries exactly one §11.4.$N block" [ "$(count_heads "$GRP" "$N")" = 1 ]
else
    fail "group: groups/git-and-data-safety.md missing"
fi
chk "progressive: rules/11.4.$N.md exists" [ -s "$ROOT/progressive/rules/11.4.$N.md" ]
CAT="$ROOT/progressive/catalog.json"
if [ -f "$CAT" ]; then
    chk "progressive: catalog.json lists §11.4.$N" has "$CAT" "\"id\":\"§11.4.$N\""
    chk "progressive: catalog.json points at rules/11.4.$N.md" has "$CAT" "\"file\":\"progressive/rules/11.4.$N.md\""
else
    fail "progressive: catalog.json missing"
fi

# ── 5. seams: data-pack row, generated wrappers, seam binding, deferrals, hook ─
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
    # The deferred gates are read from the registry by their ids, never written here as literals:
    # a literal CM- token in a non-mutation-test .sh is counted by the §11.4.227(A) ledger as an
    # implementation site, which would turn the deferral into a phantom IMPLEMENTED.
    for owed in OWED-GATE-182 OWED-GATE-183 OWED-GATE-184; do
        chk "seam: gate_ledger_deferrals.tsv has exactly one $owed row" \
            [ "$(awk -F '\t' -v o="$owed" '$2 == o' "$DEF" | wc -l | tr -d ' ')" = 1 ]
        DG="$(awk -F '\t' -v o="$owed" '$2 == o { print $1; exit }' "$DEF")"
        chk "seam: the $owed deferral names a CM-* gate that the §11.4.$N block names" names_cm_gate_in_block "$DG"
    done
else
    fail "seam: scripts/gates/gate_ledger_deferrals.tsv missing"
fi
chk "seam: this gate's paired mutation test exists" [ -f "$ROOT/scripts/gates/cm_pr_delivery_anchor_wired_mutation_test.sh" ]
chk "seam: the account-name gate exists" [ -f "$ROOT/scripts/gates/cm_pr_delivery_account_name_free.sh" ]
chk "seam: the account-name gate declares its token on a GATE= line" eval 'case "$NAMEGATE" in CM-?*) true ;; *) false ;; esac'
chk "seam: the account-name gate's paired mutation test exists" [ -f "$ROOT/scripts/gates/cm_pr_delivery_account_name_free_mutation_test.sh" ]
HOOK="$ROOT/scripts/post_update_hook.sh"
if [ -f "$HOOK" ]; then
    chk "seam: post_update_hook.sh runs this gate on every pull" has "$HOOK" "cm_pr_delivery_anchor_wired.sh"
    chk "seam: post_update_hook.sh names the token $GATE" has "$HOOK" "$GATE"
    chk "seam: post_update_hook.sh runs the account-name gate on every pull" has "$HOOK" "cm_pr_delivery_account_name_free.sh"
    chk "seam: post_update_hook.sh names the token $NAMEGATE" has "$HOOK" "$NAMEGATE"
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
