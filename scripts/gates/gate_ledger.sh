#!/usr/bin/env bash
# gate_ledger.sh — §11.4.227(A) named-gate LEDGER + monotone-decrease ratchet.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.227(A) requires every `CM-*`-class token NAMED in the governance
# corpus to be, at every build, either IMPLEMENTED (the token appears
# STRUCTURALLY inside a real executable gate site — never a prose carrier,
# §11.4.201(7)(a)) or covered by a REGISTERED DEFERRAL row pointing at a
# tracked follow-up item. Tokens satisfying NEITHER are "UNIMPLEMENTED" —
# legal silent debt is CLOSED: the unimplemented COUNT is a checked-in,
# MONOTONE-DECREASING ratchet (day-one baseline = the count measured at
# landing, so the ledger is GREEN on arrival and can only shrink from there —
# the §11.4.135-ratchet pattern applied to gate custody instead of test
# coverage). A gate NAME that vanishes from the corpus without an explicit
# removal citation FAILs (closes the delete-the-name-to-lower-the-count
# gaming channel; a genuine repeal, e.g. the §11.4.166 precedent, stays legal
# via the citation).
#
# Per §11.4.227(A): "an anchor's done state is its SEAM landing, not its
# TEXT landing" — this tool measures the SEAM (does an executable gate site
# exist / is the debt registered), never the prose.
#
# ── Structure-not-substring (§11.4.201(7)(a)) ───────────────────────────────
# An "implementation" is the gate's literal CM- token found INSIDE an
# executable `*.sh` file under the implementation tree (every real gate site
# in this corpus assigns its own name to a `GATE=` variable or an echoed
# string — a load-bearing, structural occurrence, not a passing mention).
# A `*.md` file (or any non-`.sh` file) that merely MENTIONS the token is a
# CARRIER and MUST NOT count as an implementation. A `*_mutation_test.sh`
# sibling that references the SAME token as the gate it tests is likewise
# excluded from counting as the implementation site (it is the gate's own
# §1.1 mutation harness, not the gate) — only a NON-mutation-test `.sh` hit
# counts as IMPLEMENTED.
#
# ── Tracked-ness: an UNTRACKED file is not an implementation site ────────
# A `.sh` file that exists only in the working tree — never `git add`ed — is
# NOT an implementation site, because a fresh clone of the repository does not
# contain it. Counting one moves the §11.4.227(A) monotone-decrease ratchet on
# local-only state that nobody else can reproduce: a PHANTOM ADVANCE, and
# exactly the bluff shape the ratchet exists to prevent (§11.4/§11.4.1 at the
# measurement layer, §11.4.201(6) — a working-tree grep and a repository are
# not the same instrument).
#
# Forensic FACT (measured 2026-08-23 on this corpus, the defect that motivated
# this clause): two never-committed files under `scripts/gates/` minted one
# `IMPLEMENTED` row, and the ledger reported `unimplemented=418 baseline=419`
# — a ratchet ADVANCE — while a fresh clone measured 419. The scan was a bare
# filesystem `grep` with ZERO git-awareness (`git ` occurred 0 times in this
# file; control needle: `UNIMPLEMENTED`=16, `grep`=18, negative control 0).
#
# So every candidate hit is additionally filtered by TRACKED-NESS, resolved
# from the repository that OWNS the scanned path (`rev-parse --show-toplevel`
# on `<impl-dir>`, never a hardcoded project path — §11.4.177/§11.4.28 keep
# this engine project-agnostic and consumer-inherited BY REFERENCE).
#
#   * TRACKED  = present in that repository's INDEX (`git ls-files` /
#                `--error-unmatch` semantics). A tracked file that is merely
#                MODIFIED still counts — excluding it would be a
#                §11.4.201(1) false-positive refusal, a FAIL-bluff of the same
#                severity as the phantom advance. Only genuinely untracked
#                files are dropped.
#   * A `git status --porcelain | grep '^??'` parse is NEVER used: status
#     COLLAPSES an untracked directory into a single entry (measured on this
#     corpus: 10 status entries vs 34 real files), so it under-reports.
#   * NESTED repositories are honoured: a hit the outer `ls-files` does not
#     list is re-resolved against its OWN owning repository before being
#     declared untracked, so a gate living inside a nested submodule is not
#     falsely dropped.
#
# HONEST BOUNDARY (§11.4.6): "tracked" here means INDEX-tracked, not
# HEAD-committed. A staged-but-uncommitted file counts, and is likewise absent
# from a fresh clone until pushed; staging is the deliberate act this engine
# treats as the tracking boundary, matching the conventional meaning of
# "tracked". A consumer whose gate sites are GENERATED at build time and
# deliberately gitignored would see them stop counting under this rule; that
# case is a §11.4.66 operator decision (commit the generated wrappers, or
# register their deferral), never a silent re-loosening of this filter.
# Measured on this corpus at landing: 313 tracked + 4 untracked = 317 `.sh`
# on disk, ZERO ignored — the generated propagation wrappers ARE committed, so
# this filter changes no legitimate classification here.
#
# ── The `--` footgun this tool avoids (§11.4.201(7)(c) — the path is part of
#     the instrument) ─────────────────────────────────────────────────────
# `grep -rlE --include='*.sh' -- "$g" "$IMPL"` MUST keep every OPTION
# (`--include=...`) BEFORE the `--` end-of-options marker. Reordering so `--`
# precedes `--include` silently turns `--include` into a FILENAME argument
# and the include-filter stops matching real gate sites — the exact class of
# confident-wrong-answer-without-crashing this project's own §11.4.201(7)(c)
# anchor describes (first caught inside this tool's SOL-05 proof-of-concept
# ancestor's own RED->GREEN loop).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   gate_ledger.sh generate <impl-dir> <deferrals-tsv> <corpus-file> [<corpus-file> ...]
#       -> emits a ledger TSV on stdout: `<gate>\t<STATUS>\t<evidence>`
#          STATUS in {IMPLEMENTED, DEFERRED, UNIMPLEMENTED}.
#
#   gate_ledger.sh check <ledger-file> <baseline-file> <prev-names-file> [<removals-tsv>]
#       -> ratchet + vanished-name checks; prints a summary line; exit 0/1/2.
#
#   gate_ledger.sh selfcheck <scratch-impl-dir>
#       -> control-needle + golden-good/golden-bad/deferred self-test of this
#          tool itself (§11.4.201(7)(b) — a null result is not evidence until
#          the instrument is proven to see).
#
#   gate_ledger.sh nongate-entries
#       -> prints the REGISTERED NON-GATE entries (one path-suffix per
#          line) that are excluded from the §11.4.227(A) gate-count
#          denominator, so every enumerator (this tool's own generate
#          scan, the FR-019 wiring sweep, any future counter) consumes
#          ONE registry instead of re-deriving the list. Exit 0.
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   <impl-dir>       tree scanned recursively for `*.sh` gate sites (this
#                    project's canonical scan root is `constitution/scripts`
#                    — gate implementations are NOT confined to
#                    `scripts/gates/`; several live under `scripts/hooks/`,
#                    `scripts/multitrack/`, `scripts/doc_integrity/wire/`,
#                    `scripts/helix_code/`, and `scripts/`, so a scan
#                    confined to `scripts/gates/` alone would UNDER-COUNT
#                    implementations and inflate the unimplemented figure —
#                    a false-FAIL of the exact §11.4.201(1) class this
#                    project forbids).
#   <deferrals-tsv>  `<gate>\t<tracked-item-id>[\t<note>]` rows, one per
#                    registered deferral. May be empty (header-only or
#                    zero-byte) — an empty registry is a HONEST statement
#                    that no deferral has yet been registered, not a defect.
#   <corpus-file>    one or more governance files to extract `CM-*` tokens
#                    from. This project's canonical corpus is
#                    `constitution/Constitution.md` — the anchor's own
#                    source-of-truth location per every existing
#                    `cm_covenant_*_propagation.sh` gate's documented
#                    convention; the four mirror files (CLAUDE/AGENTS/QWEN/
#                    GEMINI.md) restate the SAME anchors and are the concern
#                    of the SEPARATE anchor-block-integrity gates
#                    (§11.4.227(B)), not this ledger.
#
# ── Non-gate entries: the §11.4.227(A) gate-count DENOMINATOR ───────────────
# Not every `*.sh` file living in a gate directory IS a gate. Three classes
# routinely sit beside real gates and MUST NOT participate in the count:
#   * LIBRARIES sourced by real gates (they carry the shared engine, not a
#     verdict — a gate token appearing inside one is the library's own
#     template/placeholder text, never that gate's implementation site);
#   * GENERATORS that emit gate files (the generator is build tooling, not a
#     gate — it names tokens in the wrappers it writes);
#   * pointer/carrier helpers that hold a LITERAL placeholder spelling of a
#     token family (e.g. a `...-NNN-...` form) purely as documentation.
#
# Counting any of these as an implementation site is precisely the
# §11.4.201(7)(a) CARRIER miscount this tool exists to prevent: the file
# MENTIONS the token, it does not IMPLEMENT it. The exclusion filter already
# skipped non-`.sh` files and `*_mutation_test.sh` siblings; this registry
# closes the remaining hole for non-gate `.sh` entries.
#
# The registry is DATA (§11.4.35 / §11.4.28 — a consuming project supplies
# its own): the built-in default below is overridable by pointing
# `GATE_LEDGER_NONGATE_FILE` at a newline-delimited file of path-suffixes.
# An override path that cannot be read is a REFUSAL, never a silently empty
# registry (§11.4.252 fail-closed, §11.4.6 no-guessing) — a blind-empty
# registry would silently restore the carrier miscount.
#
# Entries are matched as PATH SUFFIXES so the registry is stable no matter
# which ancestor directory the caller passes as `<impl-dir>` (§11.4.111
# resolve-by-stable-name, not by a caller-relative accident).
#
# REGISTERED != RETIRED. These files are NOT deleted, NOT retired and NOT
# deprecated by this registry (§11.4.124 investigate-before-remove): they
# remain fully live, sourced and executed exactly as before. They stop being
# COUNTED, and nothing else.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   generate: TSV ledger on stdout.
#   check:    per-violation lines + `LEDGER: unimplemented=N baseline=B fails=F`
#             summary; exit 1 if fails>0.
#   selfcheck: SELFCHECK-FAIL lines + exit 2/1 on any self-test failure;
#              `SELFCHECK: PASS ...` + exit 0 when the instrument is proven
#              sound.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only). `selfcheck` creates + removes its own `mktemp -d`
#   scratch tree; it never touches the caller-supplied `<impl-dir>`.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, POSIX grep + sed + awk + cut + sort. Parses clean under `bash -n`
#   (§11.4.67).
#
# ── Cross-references ────────────────────────────────────────────────────────
#   §11.4.227(A) (this ledger's mandate), §11.4.201(7)(a)/(b)/(c) (structure-
#   not-substring, control needle, the-path-is-part-of-the-instrument),
#   §11.4.135 (the monotone-decrease-ratchet pattern this reuses),
#   §11.4.6 (no-guessing — an unresolvable file is BLIND, exit 2, never a
#   guessed zero), §11.4.66/§11.4.122 (brownfield-adoption + exclusion
#   decisions stay operator-owned DATA, never invented by this tool), §1.1
#   (paired mutation — name a new gate with no implementation and no
#   deferral -> `check` FAILs; register its deferral -> `check` PASSes).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   generate: 0 on a non-empty ledger; 2 on BLIND (unreadable input / zero
#             tokens extracted from a non-empty corpus — the corpus needs a
#             control needle before an empty extraction is trusted).
#   check:    0 — ratchet holds, no vanished-name violation.
#             1 — ratchet exceeded and/or a vanished name lacks a citation.
#             2 — BLIND (an input file could not be read).
#   selfcheck: 0 — PASS; 1 — a golden fixture misclassified; 2 — the
#              control needle itself failed (the instrument is BLIND).
#
# Classification: universal (§11.4.17) — no project-specific literal; the
# consuming project supplies its own impl-dir / deferrals-tsv / corpus paths
# and baseline snapshot as DATA per §11.4.35.

for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -u

SELF="$0"
TOOL="gate_ledger.sh"

usage() {
    sed -n '1,77p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Non-gate registry (§11.4.227(A) denominator; see the header section) ────
# One path-SUFFIX per line. Default = this corpus's four measured non-gate
# entries; override with GATE_LEDGER_NONGATE_FILE (consumer DATA, §11.4.35).
NONGATE_DEFAULT="gates/lib/covenant_propagation_engine.sh
gates/lib/covenant_propagation_mutation_engine.sh
gates/lib/pointer_carrier.sh
gates/covenant_propagation_wrappers_generate.sh"

# nongate_entries: prints the registered non-gate path-suffixes, one per line.
# Fail-CLOSED on an unreadable override (§11.4.252) — never a blind-empty
# registry, which would silently restore the carrier miscount.
nongate_entries() {
    if [ -n "${GATE_LEDGER_NONGATE_FILE:-}" ]; then
        if [ ! -r "$GATE_LEDGER_NONGATE_FILE" ]; then
            echo "BLIND: GATE_LEDGER_NONGATE_FILE=${GATE_LEDGER_NONGATE_FILE} is unreadable — refusing rather than counting with an empty non-gate registry (§11.4.252/§11.4.6)" >&2
            exit 2
        fi
        grep -v '^[[:space:]]*#' -- "$GATE_LEDGER_NONGATE_FILE" | sed '/^[[:space:]]*$/d'
        return 0
    fi
    printf '%s\n' "$NONGATE_DEFAULT"
}

# is_nongate <path>: exit 0 when <path> is a REGISTERED non-gate entry, i.e.
# it equals a registered suffix or ends with `/`+suffix. Suffix matching keeps
# the registry stable across whichever ancestor dir is passed as <impl-dir>
# (§11.4.111). Boundary-anchored on `/` so `xpointer_carrier.sh` can never
# be mistaken for `pointer_carrier.sh`.
NONGATE_CACHE=""
NONGATE_CACHED=0
is_nongate() {
    if [ "$NONGATE_CACHED" -eq 0 ]; then
        NONGATE_CACHE="$(nongate_entries)" || exit 2
        NONGATE_CACHED=1
    fi
    _ing_path="$1"
    while IFS= read -r _ing_e; do
        [ -n "$_ing_e" ] || continue
        if [ "$_ing_path" = "$_ing_e" ]; then return 0; fi
        case "$_ing_path" in
            */"$_ing_e") return 0 ;;
        esac
    done <<EOF
$NONGATE_CACHE
EOF
    return 1
}

# ── Tracked-ness filter (git-awareness; see the header section) ───────────
# Populated by `generate` via resolve_tracked_set() before any hit is
# classified. Empty/unset outside `generate`, which never calls is_tracked().
IMPL_NOSLASH=""
IMPL_TOP=""
IMPL_PREFIX=""
TRACKED_SET=""
TRACKED_NL="
"

# resolve_tracked_set <impl-dir>: resolve the repository OWNING <impl-dir> and
# snapshot its index entries for that subtree, as repo-relative paths.
#
# Fail-CLOSED (§11.4.252 / §11.4.6 / §11.4.201): git missing, the path not
# inside a repository, or an unresolvable index query is a REFUSAL (BLIND,
# exit 2) — never a silent fallback. The two silent fallbacks are BOTH
# forbidden and the refusal is chosen over either:
#   * counting EVERY file would restore the phantom-advance defect verbatim;
#   * counting NOTHING would flip every gate to UNIMPLEMENTED at once — a mass
#     ratchet FAIL on a healthy corpus, the more dangerous direction because it
#     buries a real signal under hundreds of false ones (§11.4.201(1)).
# A refusal states the unresolvable condition and produces no number at all,
# which is the only honest third answer.
resolve_tracked_set() {
    _rts_impl="$1"

    if ! command -v git >/dev/null 2>&1; then
        echo "BLIND: git is not available on PATH — tracked-ness of the gate sites under ${_rts_impl} cannot be resolved, and this tool refuses to count either every file (restores the phantom-advance defect) or none (mass false ratchet advance), §11.4.252/§11.4.6" >&2
        exit 2
    fi

    IMPL_NOSLASH="${_rts_impl%/}"
    [ -n "$IMPL_NOSLASH" ] || IMPL_NOSLASH="/"

    IMPL_TOP="$(git -C "$_rts_impl" rev-parse --show-toplevel 2>/dev/null)" || IMPL_TOP=""
    if [ -z "$IMPL_TOP" ]; then
        echo "BLIND: impl-dir ${_rts_impl} is not inside a git repository — tracked-ness is unresolvable there, so this tool refuses rather than counting untracked working-tree files as implementations (§11.4.227(A) phantom advance) or counting none (§11.4.201(1) mass false refusal). Scan a real checkout, or \`git init\` the tree under test." >&2
        exit 2
    fi

    IMPL_PREFIX="$(git -C "$_rts_impl" rev-parse --show-prefix 2>/dev/null)" || IMPL_PREFIX=""

    if ! _rts_list="$(git -C "$_rts_impl" ls-files --full-name -- . 2>/dev/null)"; then
        echo "BLIND: \`git ls-files\` failed for ${_rts_impl} (repository ${IMPL_TOP}) — the tracked set is unresolvable and this tool refuses to guess it, §11.4.6" >&2
        exit 2
    fi

    # Control needle (§11.4.201(7)(b)) — a NULL is not evidence until the
    # instrument is proven able to see through the SAME path.
    #
    # An empty tracked set alongside `.sh` files on disk has two REAL causes,
    # and neither is a defect: a genuinely fresh repository (nothing staged
    # anywhere), or a subtree whose every `.sh` file is genuinely new. Both are
    # determinate answers — every gate there is honestly UNIMPLEMENTED, because
    # a fresh clone would contain none of those files. REFUSING on either would
    # be a §11.4.201(1) FALSE-POSITIVE refusal, which is a FAIL-bluff of the
    # same severity as the phantom advance this filter prevents.
    #
    # So the needle LICENSES the zero rather than second-guessing it: the same
    # `ls-files`, on the same repository, is asked whether it can see ANY entry
    # at all. A successful probe — whether it returns entries (instrument
    # demonstrably sees) or none (repository demonstrably empty) — makes the
    # subtree zero real evidence. Only a probe that FAILS leaves the zero
    # unresolvable, and that is refused (never silently trusted, §11.4.6).
    if [ -z "$_rts_list" ] && [ -n "$(find "$_rts_impl" -name '*.sh' -type f -print -quit 2>/dev/null)" ]; then
        if ! _rts_needle="$(git -C "$IMPL_TOP" ls-files 2>/dev/null)"; then
            echo "BLIND: repository-wide \`git ls-files\` probe failed for ${IMPL_TOP} — the empty tracked set under ${_rts_impl} cannot be licensed as a real absence; refusing rather than guessing (§11.4.6/§11.4.201(7)(b))" >&2
            exit 2
        fi
        if [ -n "$_rts_needle" ]; then
            echo "NOTE: zero tracked files under ${_rts_impl}; control needle licenses it — the repository ${IMPL_TOP} index IS readable and non-empty, so every gate site in that subtree is genuinely untracked (§11.4.201(7)(b))" >&2
        else
            echo "NOTE: zero tracked files under ${_rts_impl}; control needle licenses it — the repository ${IMPL_TOP} index is readable and genuinely EMPTY (nothing staged anywhere), §11.4.201(7)(b)" >&2
        fi
    fi

    TRACKED_SET="${TRACKED_NL}${_rts_list}${TRACKED_NL}"
    return 0
}

# is_tracked <hit-path>: exit 0 when the grep hit is a TRACKED file.
# <hit-path> is the path exactly as grep printed it, i.e. the `<impl-dir>`
# argument followed by the file's subpath, so the repo-relative name is pure
# string surgery — no per-hit `realpath`, no per-hit subprocess on the fast
# path. Quoted expansions keep glob metacharacters in filenames literal.
is_tracked() {
    _it_p="$1"
    _it_sub="${_it_p#"$IMPL_NOSLASH"}"
    _it_sub="${_it_sub#/}"
    _it_rel="${IMPL_PREFIX}${_it_sub}"
    case "$TRACKED_SET" in
        *"${TRACKED_NL}${_it_rel}${TRACKED_NL}"*) return 0 ;;
    esac

    # MISS — before declaring the file untracked, honour NESTED repositories:
    # the outer `ls-files` deliberately does not list files inside a submodule,
    # so a gate living in one would otherwise be falsely dropped
    # (§11.4.201(1)). Re-resolve against the file's OWN owning repository.
    # Only reached for genuine misses, so the cost stays off the fast path.
    _it_dir="${_it_p%/*}"
    [ "$_it_dir" != "$_it_p" ] || _it_dir="."
    _it_base="${_it_p##*/}"
    _it_own="$( (cd "$_it_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || true )"
    if [ -n "$_it_own" ] && [ "$_it_own" != "$IMPL_TOP" ]; then
        if (cd "$_it_dir" 2>/dev/null && git ls-files --error-unmatch -- "./${_it_base}" >/dev/null 2>&1); then
            return 0
        fi
    fi
    return 1
}

MODE="${1:-}"
if [ -z "$MODE" ]; then
    usage >&2
    exit 2
fi
shift

# extract_names: reads corpus bytes on stdin, prints one CM-* token per line,
# de-duplicated, sorted. Trailing punctuation (a token immediately followed
# by `.`/`,`/`:`/`;`/`)` in prose, e.g. "... per CM-EXAMPLE-GATE.") is
# stripped so the SAME gate is not double-counted under two spellings.
extract_names() {
    grep -ohE 'CM-[A-Z0-9][A-Z0-9-]*' | sed -E 's/[-.,:;)]+$//' | sort -u
}

case "$MODE" in
generate)
    IMPL="${1:?generate: <impl-dir> required}"; shift
    DEF="${1:?generate: <deferrals-tsv> required}"; shift
    if [ "$#" -lt 1 ]; then
        echo "${TOOL}: generate requires >=1 <corpus-file>" >&2
        exit 2
    fi
    for f in "$@"; do
        [ -r "$f" ] || { echo "BLIND: cannot read corpus file $f" >&2; exit 2; }
    done
    [ -d "$IMPL" ] || { echo "BLIND: impl-dir $IMPL absent" >&2; exit 2; }
    [ -r "$DEF" ] || { echo "BLIND: deferrals-tsv $DEF absent" >&2; exit 2; }

    # Resolve the OWNING repository's tracked set once, before any hit is
    # classified (see the tracked-ness header section). Refuses on BLIND.
    resolve_tracked_set "$IMPL"

    names="$(cat -- "$@" | extract_names)"
    if [ -z "$names" ]; then
        echo "BLIND-OR-EMPTY: zero CM- tokens extracted from corpus [$*] — needle the corpus (or the extractor) before trusting this as a real absence, §11.4.201(7)(b)" >&2
        exit 2
    fi

    while IFS= read -r g; do
        [ -n "$g" ] || continue
        # STRUCTURE match: options precede `--` (§11.4.201(7)(c)); real gate
        # sites are recursively discovered anywhere under IMPL (not confined
        # to a single subdirectory, per the ── Inputs ── note above).
        #
        # BOUNDARY-ANCHORED, never a bare substring (§11.4.201(7)(a) applied
        # to THIS tool's own instrument, not only to the corpus): a bare
        # `grep -E -- "$g"` would let a SHORTER gate name false-match as a
        # SUBSTRING of a longer one that shares its prefix. Forensic FACT
        # (found LIVE while generating this tool's own first real-corpus
        # ledger): the corpus occasionally cites several sibling propagation
        # gates compactly as one slash-joined literal (a single anchor-number
        # of the form NNN, joined to its siblings MMM/PPP/... by `/`, all
        # sharing one `-PROPAGATION` suffix at the end of the group). The
        # token extractor legitimately stops at the `/` (outside the
        # `[A-Z0-9-]` class), so it emits a spurious bare `CM-COVENANT-114-
        # <NNN>` token for the FIRST member of the group — missing its own
        # `-PROPAGATION` suffix. Without boundary anchoring that spurious
        # bare token would then substring-match INSIDE the real gate site's
        # `GATE="CM-COVENANT-114-<NNN>-PROPAGATION"` assignment line and be
        # misclassified IMPLEMENTED. The boundary class `[^A-Z0-9-]` on both
        # sides (or start/end of line) requires the matched token NOT be
        # immediately followed/preceded by more
        # `[A-Z0-9-]` characters, so the spurious bare `CM-COVENANT-114-<NNN>`
        # can never match inside its own strictly-longer, correctly-suffixed
        # `CM-COVENANT-114-<NNN>-PROPAGATION` sibling.
        hits="$(grep -rlE --include='*.sh' -- "(^|[^A-Z0-9-])${g}([^A-Z0-9-]|\$)" "$IMPL" 2>/dev/null | grep -v '_mutation_test\.sh$')"
        # §11.4.227(A) denominator: drop REGISTERED NON-GATE entries
        # (libraries / generators / pointer-carriers). They MENTION the token,
        # they do not IMPLEMENT it — counting one is the §11.4.201(7)(a)
        # carrier miscount. Registered != retired: the files stay live.
        gate_hits=""
        while IFS= read -r _h; do
            [ -n "$_h" ] || continue
            is_nongate "$_h" && continue
            # Tracked-ness (git-awareness): an untracked working-tree file is
            # not an implementation site — a fresh clone does not have it, so
            # counting it is a §11.4.227(A) PHANTOM RATCHET ADVANCE. A tracked
            # but MODIFIED file still counts (§11.4.201(1)).
            is_tracked "$_h" || continue
            gate_hits="${gate_hits}${_h}
"
        done <<EOF
$hits
EOF
        hit="$(printf '%s\n' "$gate_hits" | head -1)"
        if [ -n "$hit" ]; then
            printf '%s\tIMPLEMENTED\t%s\n' "$g" "$hit"
            continue
        fi
        if [ -s "$DEF" ] && cut -f1 "$DEF" | grep -qx -- "$g"; then
            tracked="$(awk -F'\t' -v g="$g" '$1==g{print $2; exit}' "$DEF")"
            printf '%s\tDEFERRED\t%s\n' "$g" "${tracked:-UNKNOWN-TRACKED-ITEM}"
            continue
        fi
        printf '%s\tUNIMPLEMENTED\t-\n' "$g"
    done <<< "$names"
    ;;

check)
    LEDGER="${1:?check: <ledger-file> required}"
    BASE="${2:?check: <baseline-file> required}"
    PREV="${3:?check: <prev-names-file> required}"
    REM="${4:-}"
    for f in "$LEDGER" "$BASE" "$PREV"; do
        [ -r "$f" ] || { echo "BLIND: cannot read $f" >&2; exit 2; }
    done

    fails=0

    count="$(awk -F'\t' '$2=="UNIMPLEMENTED"{n++} END{print n+0}' "$LEDGER")"
    baseline_raw="$(cat -- "$BASE")"
    baseline="$(printf '%s' "$baseline_raw" | tr -d '[:space:]')"
    if ! printf '%s' "$baseline" | grep -qE '^[0-9]+$'; then
        echo "LEDGER-FAIL: baseline file $BASE does not contain a bare non-negative integer (got: '${baseline_raw}')"
        fails=$((fails + 1))
        baseline=0
    fi

    if [ "$count" -gt "$baseline" ]; then
        echo "LEDGER-FAIL: ratchet violated — unimplemented=${count} exceeds checked-in baseline=${baseline} (a CM-* gate was named with neither an implementation nor a registered deferral; land the gate, register its deferral against a tracked item, or this is a §11.4.227(A) violation)"
        fails=$((fails + 1))
    fi

    while IFS= read -r g; do
        [ -n "$g" ] || continue
        if ! cut -f1 "$LEDGER" | grep -qx -- "$g"; then
            cited=0
            if [ -n "$REM" ] && [ -r "$REM" ]; then
                if cut -f1 "$REM" | grep -qx -- "$g"; then
                    cited=1
                fi
            fi
            if [ "$cited" -eq 0 ]; then
                echo "LEDGER-FAIL: gate ${g} vanished from the corpus with no removal citation in ${REM:-<none supplied>} (silent deletion would game the monotone-decrease ratchet — cite the removal, e.g. a §11.4.166-class repeal, or restore the gate)"
                fails=$((fails + 1))
            fi
        fi
    done < "$PREV"

    echo "LEDGER: unimplemented=${count} baseline=${baseline} fails=${fails}"
    [ "$fails" -eq 0 ] || exit 1
    exit 0
    ;;

nongate-entries)
    # Read-only registry accessor: the ONE place any enumerator (this tool's
    # own generate scan, the FR-019 wiring sweep, any future counter) reads
    # the §11.4.227(A) non-gate exclusion set from, instead of re-deriving it.
    nongate_entries
    exit 0
    ;;

selfcheck)
    IMPL_UNUSED="${1:-}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    # Scratch impl trees are real (throwaway) REPOSITORIES: `generate` resolves
    # tracked-ness from the repo owning <impl-dir> (see the tracked-ness header
    # section), so a bare mktemp dir would be an honest BLIND refusal, not a
    # usable fixture. `git add` (index) is the tracking boundary — no commit is
    # needed, and none is made.
    _sc_repo() {   # _sc_repo <dir> [--no-add]
        _scr_d="$1"; shift 2>/dev/null || true
        git -C "$_scr_d" init -q >/dev/null 2>&1 || {
            echo "SELFCHECK-FAIL: could not \`git init\` scratch repo $_scr_d — the tracked-ness fixtures cannot be built" >&2
            exit 2
        }
        if [ "${1:-}" != "--no-add" ]; then
            git -C "$_scr_d" add -A >/dev/null 2>&1 || {
                echo "SELFCHECK-FAIL: could not stage scratch repo $_scr_d" >&2
                exit 2
            }
        fi
    }

    # ── control needle (§11.4.201(7)(b)) ────────────────────────────────────
    # A synthetic corpus with exactly one known-present gate token MUST be
    # extracted before any zero-extraction result elsewhere is trusted as a
    # true absence rather than a blind instrument.
    needle_corpus="$tmp/needle_corpus.md"
    printf 'Prose citing gate `CM-NEEDLE-CONTROL-TEST` inside a sentence, never a block-start.\n' > "$needle_corpus"
    needle_names="$(extract_names < "$needle_corpus")"
    if ! printf '%s\n' "$needle_names" | grep -qx 'CM-NEEDLE-CONTROL-TEST'; then
        echo "SELFCHECK-FAIL: control needle CM-NEEDLE-CONTROL-TEST was NOT extracted — the token extractor itself is BLIND" >&2
        exit 2
    fi

    # ── golden-good: a real .sh implementation classifies IMPLEMENTED ───────
    good_impl="$tmp/impl_good"; mkdir -p "$good_impl"
    cat > "$good_impl/cm_selftest_good.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-GOOD"
echo "$GATE: PASS"
exit 0
SH
    chmod +x "$good_impl/cm_selftest_good.sh"
    _sc_repo "$good_impl"
    good_def="$tmp/deferrals_empty_good.tsv"; : > "$good_def"
    good_corpus="$tmp/good_corpus.md"
    printf 'Gate `CM-SELFTEST-GOOD` protects the good path.\n' > "$good_corpus"
    good_out="$("$SELF" generate "$good_impl" "$good_def" "$good_corpus")"
    if ! printf '%s\n' "$good_out" | grep -qE '^CM-SELFTEST-GOOD[[:space:]]+IMPLEMENTED'; then
        echo "SELFCHECK-FAIL: golden-good gate CM-SELFTEST-GOOD (real .sh site present) was NOT classified IMPLEMENTED" >&2
        printf '%s\n' "$good_out" >&2
        exit 1
    fi

    # ── golden-bad: a prose-only CARRIER (a .md mentioning the token, no
    #    real .sh site) MUST classify UNIMPLEMENTED, never IMPLEMENTED —
    #    proves structure-not-substring (§11.4.201(7)(a)) actually holds.
    bad_impl="$tmp/impl_bad"; mkdir -p "$bad_impl"
    printf 'CM-SELFTEST-BAD is mentioned here, in a doc, never in an executable script.\n' > "$bad_impl/prose_carrier.md"
    _sc_repo "$bad_impl"
    bad_def="$tmp/deferrals_empty_bad.tsv"; : > "$bad_def"
    bad_corpus="$tmp/bad_corpus.md"
    printf 'Gate `CM-SELFTEST-BAD` protects the bad path.\n' > "$bad_corpus"
    bad_out="$("$SELF" generate "$bad_impl" "$bad_def" "$bad_corpus")"
    if ! printf '%s\n' "$bad_out" | grep -qE '^CM-SELFTEST-BAD[[:space:]]+UNIMPLEMENTED'; then
        echo "SELFCHECK-FAIL: golden-bad gate CM-SELFTEST-BAD (prose-only carrier, zero real .sh sites) was NOT classified UNIMPLEMENTED — a carrier is being counted as an implementation (§11.4.201(7)(a) violated)" >&2
        printf '%s\n' "$bad_out" >&2
        exit 1
    fi

    # ── negative control: a mutation-test-only reference (no real impl)
    #    MUST ALSO classify UNIMPLEMENTED — the mutation harness is not the
    #    gate.
    mut_impl="$tmp/impl_mutonly"; mkdir -p "$mut_impl"
    cat > "$mut_impl/cm_selftest_mutonly_mutation_test.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-MUTONLY"
echo "mutation test for $GATE"
SH
    chmod +x "$mut_impl/cm_selftest_mutonly_mutation_test.sh"
    _sc_repo "$mut_impl"
    mut_def="$tmp/deferrals_empty_mut.tsv"; : > "$mut_def"
    mut_corpus="$tmp/mut_corpus.md"
    printf 'Gate `CM-SELFTEST-MUTONLY` protects the mutation-only path.\n' > "$mut_corpus"
    mut_out="$("$SELF" generate "$mut_impl" "$mut_def" "$mut_corpus")"
    if ! printf '%s\n' "$mut_out" | grep -qE '^CM-SELFTEST-MUTONLY[[:space:]]+UNIMPLEMENTED'; then
        echo "SELFCHECK-FAIL: a gate present ONLY inside its own *_mutation_test.sh (no real implementation) was NOT classified UNIMPLEMENTED" >&2
        printf '%s\n' "$mut_out" >&2
        exit 1
    fi

    # ── deferred classification: a registered deferral (no impl) -> DEFERRED
    defr_impl="$tmp/impl_defr"; mkdir -p "$defr_impl"
    _sc_repo "$defr_impl"
    defr_def="$tmp/deferrals_one.tsv"
    printf 'CM-SELFTEST-DEFERRED\tTRACKED-ITEM-EXAMPLE-123\n' > "$defr_def"
    defr_corpus="$tmp/defr_corpus.md"
    printf 'Gate `CM-SELFTEST-DEFERRED` protects the deferred path.\n' > "$defr_corpus"
    defr_out="$("$SELF" generate "$defr_impl" "$defr_def" "$defr_corpus")"
    if ! printf '%s\n' "$defr_out" | grep -qE '^CM-SELFTEST-DEFERRED[[:space:]]+DEFERRED'; then
        echo "SELFCHECK-FAIL: a gate with a registered deferral (no implementation) was NOT classified DEFERRED" >&2
        printf '%s\n' "$defr_out" >&2
        exit 1
    fi

    # ── non-gate registry: golden-BAD (exclusion is LOAD-BEARING) ──────────
    #    A token whose ONLY `.sh` occurrence is inside a REGISTERED non-gate
    #    entry (a sourced library / a generator / a pointer-carrier) MUST
    #    classify UNIMPLEMENTED — the file MENTIONS the token, it does not
    #    IMPLEMENT it (§11.4.201(7)(a) / §11.4.227(A) denominator).
    ng_impl="$tmp/impl_nongate"; mkdir -p "$ng_impl/gates/lib"
    cat > "$ng_impl/gates/lib/pointer_carrier.sh" <<'SH'
#!/usr/bin/env bash
# library sourced by real gates; names the token only as placeholder text
PLACEHOLDER="CM-SELFTEST-NONGATE-ONLY"
SH
    chmod +x "$ng_impl/gates/lib/pointer_carrier.sh"
    _sc_repo "$ng_impl"
    ng_def="$tmp/deferrals_empty_ng.tsv"; : > "$ng_def"
    ng_corpus="$tmp/ng_corpus.md"
    printf 'Gate `CM-SELFTEST-NONGATE-ONLY` is named in the corpus.\n' > "$ng_corpus"
    ng_out="$("$SELF" generate "$ng_impl" "$ng_def" "$ng_corpus")"
    if ! printf '%s\n' "$ng_out" | grep -qE '^CM-SELFTEST-NONGATE-ONLY[[:space:]]+UNIMPLEMENTED'; then
        echo "SELFCHECK-FAIL: a gate token present ONLY inside a REGISTERED non-gate entry (gates/lib/pointer_carrier.sh) was NOT classified UNIMPLEMENTED — a library/generator carrier is inflating the implemented count (§11.4.227(A) denominator wrong)" >&2
        printf '%s\n' "$ng_out" >&2
        exit 1
    fi

    # ── non-gate registry: golden-TRUE (must NOT over-fire) ────────────────
    #    A token implemented by a REAL gate MUST stay IMPLEMENTED even when a
    #    registered non-gate entry ALSO mentions it. A false-positive refusal
    #    here is a FAIL-bluff of the same severity as a false pass
    #    (§11.4.201(1)).
    ng2_impl="$tmp/impl_nongate_neg"; mkdir -p "$ng2_impl/gates/lib"
    cat > "$ng2_impl/gates/lib/pointer_carrier.sh" <<'SH'
#!/usr/bin/env bash
PLACEHOLDER="CM-SELFTEST-NONGATE-BOTH"
SH
    cat > "$ng2_impl/gates/cm_selftest_nongate_both.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-NONGATE-BOTH"
echo "$GATE: PASS"
exit 0
SH
    chmod +x "$ng2_impl/gates/lib/pointer_carrier.sh" "$ng2_impl/gates/cm_selftest_nongate_both.sh"
    _sc_repo "$ng2_impl"
    ng2_def="$tmp/deferrals_empty_ng2.tsv"; : > "$ng2_def"
    ng2_corpus="$tmp/ng2_corpus.md"
    printf 'Gate `CM-SELFTEST-NONGATE-BOTH` is named in the corpus.\n' > "$ng2_corpus"
    ng2_out="$("$SELF" generate "$ng2_impl" "$ng2_def" "$ng2_corpus")"
    if ! printf '%s\n' "$ng2_out" | grep -qE '^CM-SELFTEST-NONGATE-BOTH[[:space:]]+IMPLEMENTED'; then
        echo "SELFCHECK-FAIL: a gate token WITH a real gate site was classified non-IMPLEMENTED because a registered non-gate entry also mentions it — the exclusion is over-firing (§11.4.201(1) false-positive refusal)" >&2
        printf '%s\n' "$ng2_out" >&2
        exit 1
    fi
    if ! printf '%s\n' "$ng2_out" | grep -qE 'cm_selftest_nongate_both\.sh$'; then
        echo "SELFCHECK-FAIL: the IMPLEMENTED evidence path for CM-SELFTEST-NONGATE-BOTH is not the real gate site — the non-gate entry is still being cited as evidence" >&2
        printf '%s\n' "$ng2_out" >&2
        exit 1
    fi

    # ── tracked-ness: golden-BAD (an UNTRACKED gate site MUST NOT count) ───
    #    A `.sh` gate site present in the working tree but never `git add`ed is
    #    NOT an implementation: a fresh clone does not contain it, so counting
    #    it moves the §11.4.227(A) ratchet on unreproducible local-only state
    #    (the PHANTOM ADVANCE this filter exists to prevent).
    ut_impl="$tmp/impl_untracked"; mkdir -p "$ut_impl"
    cat > "$ut_impl/cm_selftest_untracked.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-UNTRACKED"
echo "$GATE: PASS"
exit 0
SH
    chmod +x "$ut_impl/cm_selftest_untracked.sh"
    _sc_repo "$ut_impl" --no-add          # repo exists; the gate file is NOT staged
    ut_def="$tmp/deferrals_empty_ut.tsv"; : > "$ut_def"
    ut_corpus="$tmp/ut_corpus.md"
    printf 'Gate `CM-SELFTEST-UNTRACKED` is named in the corpus.\n' > "$ut_corpus"
    ut_out="$("$SELF" generate "$ut_impl" "$ut_def" "$ut_corpus")"
    if ! printf '%s\n' "$ut_out" | grep -qE '^CM-SELFTEST-UNTRACKED[[:space:]]+UNIMPLEMENTED'; then
        echo "SELFCHECK-FAIL: an UNTRACKED .sh gate site was counted as IMPLEMENTED — a fresh clone does not contain it, so the §11.4.227(A) ratchet would advance on unreproducible local-only state (phantom advance)" >&2
        printf '%s\n' "$ut_out" >&2
        exit 1
    fi

    # ── tracked-ness: golden-TRUE (a TRACKED gate site MUST still count) ───
    #    The converse of the fixture above, on a byte-identical gate file: the
    #    ONLY difference is `git add`. Without this the filter would be proven
    #    only to EXCLUDE, never to still INCLUDE (§11.4.201(1)).
    tr_impl="$tmp/impl_tracked"; mkdir -p "$tr_impl"
    cat > "$tr_impl/cm_selftest_untracked.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-UNTRACKED"
echo "$GATE: PASS"
exit 0
SH
    chmod +x "$tr_impl/cm_selftest_untracked.sh"
    _sc_repo "$tr_impl"                   # SAME file, staged
    tr_out="$("$SELF" generate "$tr_impl" "$ut_def" "$ut_corpus")"
    if ! printf '%s\n' "$tr_out" | grep -qE '^CM-SELFTEST-UNTRACKED[[:space:]]+IMPLEMENTED'; then
        echo "SELFCHECK-FAIL: a TRACKED .sh gate site (byte-identical to the untracked fixture, differing only by \`git add\`) was NOT classified IMPLEMENTED — the tracked-ness filter is over-firing (§11.4.201(1) false-positive refusal)" >&2
        printf '%s\n' "$tr_out" >&2
        exit 1
    fi

    # ── tracked-ness: golden-TRUE (a tracked-but-MODIFIED site still counts) ─
    #    Only genuinely UNTRACKED files are dropped. A tracked file with local
    #    edits is still in the index and still ships from a clone; excluding it
    #    would be a FAIL-bluff of the same severity as the phantom advance.
    md_impl="$tmp/impl_modified"; mkdir -p "$md_impl"
    cat > "$md_impl/cm_selftest_modified.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-MODIFIED"
echo "$GATE: PASS"
exit 0
SH
    chmod +x "$md_impl/cm_selftest_modified.sh"
    _sc_repo "$md_impl"
    printf '# locally modified after staging — still tracked\n' >> "$md_impl/cm_selftest_modified.sh"
    md_def="$tmp/deferrals_empty_md.tsv"; : > "$md_def"
    md_corpus="$tmp/md_corpus.md"
    printf 'Gate `CM-SELFTEST-MODIFIED` is named in the corpus.\n' > "$md_corpus"
    md_out="$("$SELF" generate "$md_impl" "$md_def" "$md_corpus")"
    if ! printf '%s\n' "$md_out" | grep -qE '^CM-SELFTEST-MODIFIED[[:space:]]+IMPLEMENTED'; then
        echo "SELFCHECK-FAIL: a TRACKED-but-MODIFIED .sh gate site was NOT classified IMPLEMENTED — only genuinely untracked files may be dropped (§11.4.201(1))" >&2
        printf '%s\n' "$md_out" >&2
        exit 1
    fi

    # ── tracked-ness: BLIND (a NON-REPOSITORY scan root MUST refuse) ───────
    #    Tracked-ness is unresolvable outside a repository. The tool refuses
    #    (exit 2) rather than silently counting everything (restores the
    #    phantom-advance defect) or counting nothing (a mass false ratchet
    #    advance — the more dangerous direction).
    nr_impl="$tmp/impl_nonrepo"; mkdir -p "$nr_impl"
    cat > "$nr_impl/cm_selftest_nonrepo.sh" <<'SH'
#!/usr/bin/env bash
GATE="CM-SELFTEST-NONREPO"
SH
    chmod +x "$nr_impl/cm_selftest_nonrepo.sh"   # deliberately NOT a repository
    nr_def="$tmp/deferrals_empty_nr.tsv"; : > "$nr_def"
    nr_corpus="$tmp/nr_corpus.md"
    printf 'Gate `CM-SELFTEST-NONREPO` is named in the corpus.\n' > "$nr_corpus"
    if nr_out="$("$SELF" generate "$nr_impl" "$nr_def" "$nr_corpus" 2>/dev/null)"; then
        echo "SELFCHECK-FAIL: generate on a NON-REPOSITORY scan root exited 0 instead of refusing — tracked-ness is unresolvable there and a silent fallback restores the phantom-advance defect (§11.4.252 fail-closed)" >&2
        printf '%s\n' "$nr_out" >&2
        exit 1
    fi

    # ── check-mode golden-true/golden-false ─────────────────────────────────
    # golden-TRUE: ratchet holds (count == baseline), no vanished name -> PASS
    ck_ledger="$tmp/ck_ledger.tsv"
    printf 'CM-A\tUNIMPLEMENTED\t-\nCM-B\tIMPLEMENTED\t/x\n' > "$ck_ledger"
    ck_base="$tmp/ck_baseline.txt"; printf '1\n' > "$ck_base"
    ck_prev="$tmp/ck_prev.txt"; printf 'CM-A\nCM-B\n' > "$ck_prev"
    if ! "$SELF" check "$ck_ledger" "$ck_base" "$ck_prev" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-TRUE check fixture (count==baseline, no vanished name) did NOT pass — false-positive refusal (§11.4.201(1))" >&2
        exit 1
    fi

    # golden-FALSE (ratchet exceeded): baseline=0, one UNIMPLEMENTED -> FAIL
    ck_base2="$tmp/ck_baseline2.txt"; printf '0\n' > "$ck_base2"
    if "$SELF" check "$ck_ledger" "$ck_base2" "$ck_prev" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-FALSE check fixture (ratchet exceeded) PASSED — the ratchet is not load-bearing" >&2
        exit 1
    fi

    # golden-FALSE (vanished name, no citation): prev names CM-A, CM-B, CM-C
    # but the ledger + no removals file only has CM-A/CM-B -> FAIL
    ck_prev2="$tmp/ck_prev2.txt"; printf 'CM-A\nCM-B\nCM-C\n' > "$ck_prev2"
    if "$SELF" check "$ck_ledger" "$ck_base" "$ck_prev2" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-FALSE check fixture (vanished name CM-C, no removal citation) PASSED" >&2
        exit 1
    fi

    # golden-TRUE (vanished name WITH citation) -> PASS
    ck_removals="$tmp/ck_removals.tsv"; printf 'CM-C\trepealed-example\n' > "$ck_removals"
    if ! "$SELF" check "$ck_ledger" "$ck_base" "$ck_prev2" "$ck_removals" >/dev/null 2>&1; then
        echo "SELFCHECK-FAIL: golden-TRUE check fixture (vanished name WITH a removal citation) did NOT pass" >&2
        exit 1
    fi

    echo "SELFCHECK: PASS — control needle sees; golden-good IMPLEMENTED; golden-bad prose-carrier UNIMPLEMENTED; mutation-test-only reference UNIMPLEMENTED; registered non-gate entry does NOT mint IMPLEMENTED, and does NOT suppress a real gate site; registered-deferral DEFERRED; untracked gate site NOT counted while the byte-identical TRACKED one IS, and a tracked-but-modified site still counts; a non-repository scan root REFUSES rather than mis-counting; check-mode ratchet + vanished-name golden-TRUE/golden-FALSE pairs all correct"
    exit 0
    ;;

*)
    usage >&2
    exit 2
    ;;
esac
