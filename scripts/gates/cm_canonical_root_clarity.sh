#!/usr/bin/env bash
# cm_canonical_root_clarity.sh — CM-CANONICAL-ROOT-CLARITY gate (§11.4.35).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.35 (Canonical-root inheritance clarity) fixes the DIRECTION of
# inheritance: the constitution submodule's three files
# (`Constitution.md` / `CLAUDE.md` / `AGENTS.md`) ARE the canonical root —
# they are the SOURCE of inheritance and are never themselves consumers —
# while the consuming project's repo-root `CLAUDE.md` is the CONSUMER and
# MUST open with an inheritance pointer back to that root.
#
# The anchor names this gate and states its contract verbatim
# (constitution/Constitution.md, the "Pre-build gate (recommended, per
# consuming project)" block under §11.4.35):
#
#     CM-CANONICAL-ROOT-CLARITY — verifies (a) consumer's CLAUDE.md opens
#     with the inheritance pointer (either @import or
#     `## INHERITED FROM constitution/CLAUDE.md` heading), (b) the
#     constitution submodule's three files are present at the expected path,
#     (c) no `## INHERITED FROM` block in the constitution submodule's own
#     files (those ARE the source-of-truth, not consumers).
#
# This script implements exactly those three invariants. It invents no
# requirement the anchor does not state.
#
# ── Both layouts ────────────────────────────────────────────────────────────
# The pointer may name either checkout path: the standard
# `submodules/constitution/CLAUDE.md` or the legacy `constitution/CLAUDE.md`
# (heading `## INHERITED FROM <path>` or import `@<path>`). In the consumer (a)
# the pointer must name THAT consumer's real path: <path> MUST equal
# <const-dir relative to consumer-root>/CLAUDE.md (a legacy consumer pointing
# at submodules/constitution/CLAUDE.md, or the reverse, is refused). The
# heading may carry trailing text after whitespace ('## INHERITED FROM
# constitution/CLAUDE.md (HelixConstitution submodule)'); an import may name
# any of the three canonical files ('@<rel>/AGENTS.md', '@<rel>/Constitution.md')
# with nothing after it but whitespace. Both
# path forms are refused as live pointers in the canonical root (c).
#
# ── Why (c) matters (the real hole this closes) ─────────────────────────────
# If a canonical-root file ever acquires a live inheritance pointer, the
# inheritance direction silently INVERTS: the source-of-truth starts
# declaring itself a downstream consumer of something else. Every
# "the constitution wins" precedence claim in every consumer then rests on a
# file that says it is inheriting. Nothing else in the corpus checks this —
# the propagation gates check that anchors are PRESENT in the mirrors, never
# that the canonical root has not become a consumer.
#
# ── The CARRIER problem this gate is built around (§11.4.201(7)(a)) ─────────
# `constitution/CLAUDE.md` LEGITIMATELY contains the line
#     ## INHERITED FROM constitution/CLAUDE.md
# inside a ```markdown fenced code block, in its "How inheritance works"
# section: it is DOCUMENTING the pointer a consumer must write. That is a
# CARRIER that MENTIONS the pointer, not a live pointer.
#
# MEASURED FACT (2026-08-23, this corpus): the naive line-anchored query
# `grep -cE '^## INHERITED FROM' constitution/CLAUDE.md` returns **1**; the
# same query run through this gate's fence-stripper returns **0**. A gate
# built on the naive query would therefore REFUSE a perfectly correct
# canonical root — the false-positive refusal §11.4.201(1) classes as a
# FAIL-bluff, exactly as forbidden as a false pass. So every match in this
# gate is taken AFTER fenced code blocks are blanked out.
#
# Blockquoted and indented mentions need no special handling: the `^`
# anchor already excludes `> ## INHERITED FROM` and 4-space-indented forms,
# both of which are quotations, never live headings.
#
# ── The control needle (§11.4.201(7)(b)) ────────────────────────────────────
# Invariant (c) reports an ABSENCE, and a null is not evidence until the
# instrument is proven able to see. Before trusting any zero, this gate runs
# a CLASS-MATCHED needle through the SAME instrument and the SAME path: the
# certified query is a fence-stripped, line-anchored `## `-heading match, so
# the needle is a fence-stripped, line-anchored `## `-heading match for a
# heading known to be present (`^## [A-Z]`), and it MUST return non-zero on
# every audited file. A bare-literal needle would certify only the layers a
# bare literal crosses; this one carries the anchoring AND the fence-stripped
# path, which are the load-bearing features of the real query. A paired
# negative control (a heading string nobody wrote) MUST return zero, so a
# match-everything instrument is caught too. Needle absent ⇒ BLIND (exit 2),
# never a reported absence.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_canonical_root_clarity.sh [--const-dir <dir>] [--consumer-root <dir>]
#                                [--head-lines N] [--quiet]
#   cm_canonical_root_clarity.sh --selftest
#
#     --const-dir <dir>      canonical-root directory holding the three files
#                            (default: CANONICAL_ROOT_DIR env, else this
#                            script's own ../.. — i.e. the constitution
#                            submodule root when the gate runs from
#                            <const>/scripts/gates/).
#     --consumer-root <dir>  consuming project root holding the consumer
#                            CLAUDE.md (default: CONSUMER_ROOT env, else the
#                            project that holds --const-dir, resolved by
#                            scripts/lib/constitution_layout.sh: <root> for
#                            both <root>/submodules/constitution (standard)
#                            and <root>/constitution (legacy); the plain
#                            parent directory only when that lib is absent).
#     --head-lines N         how many leading lines of the consumer CLAUDE.md
#                            count as "opens with" (default 40). The pointer
#                            follows the file's title//description lines in
#                            practice, so "opens with" is a head WINDOW, not
#                            literally line 1.
#     --quiet                suppress per-check PASS lines (FAIL always shown).
#     --selftest             run the golden-good / golden-bad / negative-
#                            control fixture suite against this gate itself
#                            and exit (no real tree is read).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CANONICAL_ROOT_DIR / CONSUMER_ROOT env overrides (flags take precedence).
#   No consuming project's paths are hardcoded — every path is derived from
#   this script's own location or supplied as DATA (§11.4.28 / §11.4.35 /
#   §11.4.177).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL lines on stdout + a final verdict line.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None on the real tree (read-only; no network, no commit, no device).
#   `--selftest` creates and removes its own `mktemp -d` scratch fixtures.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   POSIX sh, awk, grep, sed, mktemp. Parses clean under bash -n AND sh -n
#   (§11.4.67); no arrays, no `[[`, no `mapfile`. No command-less `exec`
#   redirection anywhere (§11.4.67(6)).
#
# ── Cross-references ────────────────────────────────────────────────────────
#   §11.4.35 (this gate's mandate + verbatim contract), §11.4.17 (the
#   universal-vs-project classification §11.4.35 defines the layers for),
#   §11.4.201(1) (a false-positive refusal is a FAIL-bluff — hence the
#   fence-stripper), §11.4.201(7)(a) (carrier vs thing), §11.4.201(7)(b)
#   (control needle before any reported absence), §11.4.201(7)(c) (the path
#   is part of the instrument — no verdict is ever taken from a pipeline's
#   exit status), §11.4.227(A) (a named gate must land a SEAM, not prose),
#   §1.1 (paired mutation: cm_canonical_root_clarity_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — invariants (a), (b), (c) all hold.
#   1 — at least one invariant violated.
#   2 — BLIND / environment error: a required directory or file is
#       unreadable, or the control needle failed (the instrument cannot see,
#       so no absence it reports may be trusted — §11.4.6, never a guessed
#       zero).
#   3 — SKIP: (b) and (c) hold, but (a) is not applicable because the
#       constitution is a STANDALONE checkout (its own git toplevel, no
#       superproject, parent in no git work tree) and no --consumer-root /
#       CONSUMER_ROOT was given. Never reported as PASS (§11.4.1); a (b) or
#       (c) violation in a standalone checkout still exits 1.
#
# Classification: universal (§11.4.17) — no project-specific literal; the
# consuming project supplies --const-dir / --consumer-root as DATA (§11.4.35).

set -u

GATE="CM-CANONICAL-ROOT-CLARITY"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

const_dir="${CANONICAL_ROOT_DIR:-${SELF_DIR}/../..}"
consumer_root="${CONSUMER_ROOT:-}"
head_lines=40
quiet=""
selftest=""

while [ $# -gt 0 ]; do
    case "$1" in
        --const-dir)      const_dir="$2"; shift 2 ;;
        --consumer-root)  consumer_root="$2"; shift 2 ;;
        --head-lines)     head_lines="$2"; shift 2 ;;
        --quiet)          quiet="1"; shift ;;
        --selftest)       selftest="1"; shift ;;
        -h|--help)        sed -n '1,100p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

# ── The fence-stripper (the instrument) ─────────────────────────────────────
# Blanks out every line inside a fenced code block (``` or ~~~, CommonMark:
# up to 3 leading spaces, opening fence >= 3 chars, closing fence same char
# and at least as long). Lines are BLANKED, never deleted, so reported line
# numbers stay true to the source file.
CRC_TMP=""
crc_cleanup() { [ -n "$CRC_TMP" ] && rm -rf "$CRC_TMP"; return 0; }
trap crc_cleanup EXIT
CRC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_crc.XXXXXX")" || {
    echo "${GATE}: BLIND — cannot create scratch dir" >&2; exit 2; }
FENCE_AWK="${CRC_TMP}/strip_fences.awk"
cat > "$FENCE_AWK" <<'AWK_EOF'
BEGIN { infence = 0; fchar = ""; flen = 0 }
{
  line = $0
  probe = line
  sub(/^   ?  ?/, "", probe)
  isfence = 0
  c = ""; n = 0
  if (probe ~ /^```/)      { c = "`"; while (substr(probe, n+1, 1) == "`") n++; isfence = 1 }
  else if (probe ~ /^~~~/) { c = "~"; while (substr(probe, n+1, 1) == "~") n++; isfence = 1 }
  if (isfence) {
    if (infence == 0)                         { infence = 1; fchar = c; flen = n; print ""; next }
    else if (c == fchar && n >= flen)         { infence = 0; fchar = ""; flen = 0; print ""; next }
    else                                      { print ""; next }
  }
  if (infence) { print "" } else { print line }
}
AWK_EOF

# crc_count <file> <ERE> [<max-lines>] -> prints the match count.
# The count is captured into a variable and compared NUMERICALLY; the
# pipeline's own exit status is never used as a verdict (§11.4.201(7)(c) —
# `grep -c` returns 1 on a legitimate zero, and a `| head` would hand back
# the pager's status instead of the matcher's).
crc_count() {
    _f="$1"; _re="$2"; _max="${3:-0}"
    if [ "$_max" -gt 0 ] 2>/dev/null; then
        _n="$(sed -n "1,${_max}p" "$_f" | awk -f "$FENCE_AWK" | grep -cE "$_re")" || _n=0
    else
        _n="$(awk -f "$FENCE_AWK" "$_f" | grep -cE "$_re")" || _n=0
    fi
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    printf '%s\n' "$_n"
}

# crc_hits <file> <ERE> -> prints `lineno:text` for each fence-stripped hit.
crc_hits() {
    awk -f "$FENCE_AWK" "$1" | grep -nE "$2" || true
}

# ── Queries (single definition, used by both the needle and the verdicts) ───
RE_INHERIT_HEADING='^## INHERITED FROM'
RE_INHERIT_IMPORT='^@(submodules/)?constitution/(CLAUDE|AGENTS|Constitution)\.md'
RE_NEEDLE='^## [A-Z]'
RE_NEG_CONTROL='^## ZZ-NEEDLE-NEGATIVE-CONTROL-ABSENT'

CANONICAL_FILES="Constitution.md CLAUDE.md AGENTS.md"

# ── selftest (§11.4.107(10) golden-good / golden-bad / negative control) ────
if [ -n "$selftest" ]; then
    st_rc=0
    st_root="${CRC_TMP}/selftest"
    st_mk() {
        # $1 = fixture name; builds a MINIMAL canonical root + consumer root.
        _d="${st_root}/$1"
        mkdir -p "${_d}/constitution"
        printf '# Constitution\n\n## Purpose\n\nrules\n'       > "${_d}/constitution/Constitution.md"
        printf '# Base AGENTS\n\n## Agent Rules\n\nrules\n'    > "${_d}/constitution/AGENTS.md"
        # canonical CLAUDE.md carries the pointer text ONLY as a fenced
        # carrier — the exact shape the real corpus has.
        {
            printf '# Base CLAUDE\n\n## How Inheritance Works\n\n'
            printf 'A consumer must start with:\n\n'
            printf '```markdown\n## INHERITED FROM constitution/CLAUDE.md\n```\n'
        } > "${_d}/constitution/CLAUDE.md"
        printf '# Consumer\n\n## INHERITED FROM constitution/CLAUDE.md\n\nrules\n' > "${_d}/CLAUDE.md"
        printf '%s\n' "$_d"
    }
    st_run() {
        # $1 = description, $2 = expected outcome (pass|fail), $3 = fixture dir
        _desc="$1"; _want="$2"; _fx="$3"
        "$0" --const-dir "${_fx}/constitution" --consumer-root "${_fx}" --quiet >/dev/null 2>&1
        _got=$?
        if [ "$_want" = "pass" ] && [ "$_got" -eq 0 ]; then
            echo "SELFCHECK OK:   ${_desc} (exit 0 as expected)"
        elif [ "$_want" = "fail" ] && [ "$_got" -ne 0 ]; then
            echo "SELFCHECK OK:   ${_desc} (exit ${_got} as expected)"
        else
            echo "SELFCHECK-FAIL: ${_desc} — expected ${_want}, got exit ${_got}"
            st_rc=1
        fi
    }
    st_expect_exit() {
        # $1 = description, $2 = exact expected exit code, rest = gate args.
        # Distinguishes a real violation (1) from a BLIND refusal (2): a gate
        # that returned 2 where 1 was owed would be hiding a finding behind an
        # instrument complaint, and vice versa.
        _desc="$1"; _want="$2"; shift 2
        "$0" "$@" >/dev/null 2>&1
        _got=$?
        if [ "$_got" -eq "$_want" ]; then
            echo "SELFCHECK OK:   ${_desc} (exit ${_got})"
        else
            echo "SELFCHECK-FAIL: ${_desc} — expected exit ${_want}, got ${_got}"
            st_rc=1
        fi
    }

    # golden-GOOD (the false-positive guard, §11.4.201(1)): a CORRECT tree in
    # which the canonical CLAUDE.md carries the pointer text inside a fence.
    # A fence-blind gate would refuse this. It MUST pass.
    fx_good="$(st_mk good)"
    st_run "golden-good: fenced carrier in canonical root + consumer pointer present" pass "$fx_good"

    # golden-GOOD: heading pointer followed by trailing text (a real consumer
    # shape: '## INHERITED FROM constitution/CLAUDE.md (HelixConstitution submodule)').
    fx_tt="$(st_mk good_trailing)"
    printf '# Consumer\n\n## INHERITED FROM constitution/CLAUDE.md (HelixConstitution submodule)\n\nrules\n' > "${fx_tt}/CLAUDE.md"
    st_run "golden-good: consumer heading pointer with trailing text" pass "$fx_tt"

    # golden-BAD: a near-miss path with trailing text is still refused.
    fx_nm="$(st_mk bad_nearmiss)"
    printf '# Consumer\n\n## INHERITED FROM constitution/CLAUDE.md.bak (old copy)\n\nrules\n' > "${fx_nm}/CLAUDE.md"
    st_expect_exit "golden-bad(a): near-miss path 'constitution/CLAUDE.md.bak (old copy)'" 1 \
        --const-dir "${fx_nm}/constitution" --consumer-root "${fx_nm}" --quiet

    # golden-BAD 1 (invariant c): the SAME pointer, moved OUTSIDE the fence.
    fx_c="$(st_mk bad_c)"
    printf '\n## INHERITED FROM somewhere-upstream\n\nWe now inherit.\n' >> "${fx_c}/constitution/CLAUDE.md"
    st_run "golden-bad(c): live inheritance heading in the canonical root" fail "$fx_c"

    # golden-BAD 1b (invariant c, import form).
    fx_ci="$(st_mk bad_ci)"
    printf '\n@constitution/CLAUDE.md\n' >> "${fx_ci}/constitution/AGENTS.md"
    st_run "golden-bad(c): live @import pointer in the canonical root" fail "$fx_ci"

    # golden-BAD 2 (invariant a): consumer pointer removed. The fixture keeps
    # OTHER anchored headings so the (a) control needle still SEES — otherwise
    # the gate would (correctly) refuse BLIND and this case would prove the
    # blind path instead of the missing-pointer path.
    fx_a="$(st_mk bad_a)"
    printf '# Consumer\n\n## Build Rules\n\nno pointer at all\n\n## Test Rules\n\nmore\n' > "${fx_a}/CLAUDE.md"
    st_run "golden-bad(a): consumer CLAUDE.md has headings but no inheritance pointer" fail "$fx_a"
    st_expect_exit "golden-bad(a) exits 1 (violation), not 2 (blind)" 1 \
        --const-dir "${fx_a}/constitution" --consumer-root "${fx_a}" --quiet

    # golden-BAD 2b (invariant a): pointer present but ONLY inside a fence
    # (a carrier in the consumer is not a live pointer either).
    fx_af="$(st_mk bad_af)"
    {
        printf '# Consumer\n\n## Build Rules\n\nExample of what to write:\n\n'
        printf '```markdown\n## INHERITED FROM constitution/CLAUDE.md\n```\n\n'
        printf '## Test Rules\n\nmore\n'
    } > "${fx_af}/CLAUDE.md"
    st_run "golden-bad(a): consumer pointer exists only as a fenced carrier" fail "$fx_af"
    st_expect_exit "golden-bad(a)-carrier exits 1 (violation), not 2 (blind)" 1 \
        --const-dir "${fx_af}/constitution" --consumer-root "${fx_af}" --quiet

    # BLIND case (§11.4.201(7)(b)): a consumer file with NO anchored heading at
    # all leaves the instrument unable to see, so the gate MUST refuse BLIND
    # (exit 2) rather than report "pointer absent" from a possibly-blind read.
    fx_blind="$(st_mk blind_a)"
    printf 'consumer with no markdown headings whatsoever\n' > "${fx_blind}/CLAUDE.md"
    st_expect_exit "blind(a): needle sees nothing -> exit 2 BLIND, never a reported absence" 2 \
        --const-dir "${fx_blind}/constitution" --consumer-root "${fx_blind}" --quiet

    # golden-BAD 3 (invariant b): a canonical file removed.
    fx_b="$(st_mk bad_b)"
    rm -f "${fx_b}/constitution/AGENTS.md"
    st_run "golden-bad(b): canonical AGENTS.md absent" fail "$fx_b"

    # golden-GOOD (standard layout): canonical root at <root>/submodules/constitution,
    # consumer root DERIVED (no --consumer-root), pointer in either form.
    for _ptr in '## INHERITED FROM submodules/constitution/CLAUDE.md' '@submodules/constitution/CLAUDE.md'; do
        _d="${st_root}/std_$(printf '%s' "$_ptr" | tr -c 'a-zA-Z0-9' _)"
        mkdir -p "${_d}/submodules"
        _fx0="$(st_mk "std_src_$(printf '%s' "$_ptr" | tr -c 'a-zA-Z0-9' _)")"
        mv "${_fx0}/constitution" "${_d}/submodules/constitution"
        printf '# Consumer\n\n%s\n\n## Rules\n\nrules\n' "$_ptr" > "${_d}/CLAUDE.md"
        st_expect_exit "golden-good(std layout, derived consumer root): pointer '${_ptr}'" 0 \
            --const-dir "${_d}/submodules/constitution" --quiet
    done

    # golden-BAD (invariant a, I3): a LEGACY-layout consumer whose pointer names
    # the STANDARD path — the pointer must equal <rel>/CLAUDE.md.
    fx_wp="$(st_mk bad_wrongpath)"
    printf '# Consumer\n\n@submodules/constitution/CLAUDE.md\n\n## Rules\n\nrules\n' > "${fx_wp}/CLAUDE.md"
    st_expect_exit "golden-bad(a): legacy consumer pointer names submodules/constitution/CLAUDE.md" 1 \
        --const-dir "${fx_wp}/constitution" --consumer-root "${fx_wp}" --quiet

    # golden-BAD 1c (invariant c, standard-layout import form).
    fx_cs="$(st_mk bad_cs)"
    printf '\n@submodules/constitution/CLAUDE.md\n' >> "${fx_cs}/constitution/AGENTS.md"
    st_run "golden-bad(c): live @submodules/constitution import in the canonical root" fail "$fx_cs"

    # negative control on the instrument itself: the needle's negative-control
    # query must return ZERO on a file that is otherwise full of headings.
    _neg="$(crc_count "${fx_good}/constitution/CLAUDE.md" "$RE_NEG_CONTROL")"
    if [ "$_neg" -eq 0 ]; then
        echo "SELFCHECK OK:   negative control returns 0 (instrument does not match everything)"
    else
        echo "SELFCHECK-FAIL: negative control returned ${_neg} — instrument matches strings nobody wrote"
        st_rc=1
    fi

    if [ "$st_rc" -eq 0 ]; then
        echo "SELFCHECK: PASS — ${GATE} refuses every golden-bad fixture and refuses none of the golden-good one"
        exit 0
    fi
    echo "SELFCHECK: FAIL — ${GATE} is not a trustworthy instrument; it mints no verdict"
    exit 1
fi

# ── Resolve paths ───────────────────────────────────────────────────────────
if [ ! -d "$const_dir" ]; then
    echo "❌ ${GATE}: BLIND — canonical-root directory not found: ${const_dir}" >&2
    exit 2
fi
const_dir="$(cd "$const_dir" && pwd)"
# Standalone canon checkout (§11.4.201(1)): when the constitution IS the
# repository — its own git toplevel, no superproject, and its parent lies in
# no git work tree — there is no consumer, so (a) is not applicable. Before
# this check the derivation below took the parent directory (a checkout named
# '.../constitution' matched the legacy-layout rule) and FAILED (a) on a
# CLAUDE.md that nobody owes: a false refusal. Detected only when the consumer
# root was NOT supplied explicitly, and only when PROVEN (every git probe must
# answer); any doubt keeps the old behaviour, which fails closed.
# crc_git ARGS — git with every ambient repository-locating GIT_* variable
# scrubbed (the canonical list of scripts/lib/constitution_layout.sh,
# CL_GIT_SCRUB_VARS, carried inline so the gate also works without that lib).
crc_git() {
    ( LC_ALL=C; export LC_ALL
      for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do
          unset "$_v"
      done
      exec git "$@" )
}
standalone=""
if [ -z "$consumer_root" ] && command -v git >/dev/null 2>&1; then
    _sa_ok=1
    _sa_top="$(crc_git -C "$const_dir" rev-parse --show-toplevel 2>/dev/null)" || _sa_ok=0
    _sa_super="$(crc_git -C "$const_dir" rev-parse --show-superproject-working-tree 2>/dev/null)" || _sa_ok=0
    _sa_phys="$(cd "$const_dir" && pwd -P)" || _sa_ok=0
    if [ "$_sa_ok" -eq 1 ] && [ -n "$_sa_top" ] && [ "$_sa_top" = "$_sa_phys" ] && [ -z "$_sa_super" ]; then
        # The parent must be PROVEN outside every work tree: git must fail
        # with 'not a git repository' (any other error, e.g. dubious
        # ownership, is not proof and keeps the consumer audit).
        _sa_perr="$(crc_git -C "$(dirname "$_sa_phys")" rev-parse --show-toplevel 2>&1 >/dev/null)" && _sa_perr=""
        case "$_sa_perr" in
            *"not a git repository"*) standalone="1" ;;
        esac
        # Consumer-shaped layouts are NEVER standalone (a non-git consumer holding the
        # constitution as its own clone at constitution/ or submodules/constitution/ owes
        # a CLAUDE.md; SKIPping it would be a false negative): the parent is named
        # 'submodules', or the parent carries a project marker (a consumer manual,
        # a manifest, a README or a .gitmodules).
        if [ -n "$standalone" ]; then
            _sa_parent="$(dirname "$_sa_phys")"
            if [ "$(basename "$_sa_parent")" = "submodules" ]; then
                standalone=""
            else
                for _m in CLAUDE.md AGENTS.md GEMINI.md QWEN.md .gitmodules helix-deps.yaml README.md; do
                    if [ -e "$_sa_parent/$_m" ]; then standalone=""; break; fi
                done
            fi
        fi
    fi
fi
if [ -z "$consumer_root" ] && [ -z "$standalone" ]; then
    # The ONE layout resolver (standard submodules/constitution + legacy).
    if [ -f "${SELF_DIR}/../lib/constitution_layout.sh" ]; then
        # shellcheck source=../lib/constitution_layout.sh
        . "${SELF_DIR}/../lib/constitution_layout.sh"
        consumer_root="$(cl_project_root_of "$const_dir")" || consumer_root=""
    fi
    [ -n "$consumer_root" ] || consumer_root="$(dirname "$const_dir")"
fi
if [ -z "$standalone" ]; then
    if [ ! -d "$consumer_root" ]; then
        echo "❌ ${GATE}: BLIND — consumer root directory not found: ${consumer_root}" >&2
        exit 2
    fi
    consumer_root="$(cd "$consumer_root" && pwd)"
fi

fail=0

# ── Invariant (b): the three canonical files are present ────────────────────
# Checked FIRST: (c) audits these files, so their absence must be reported as
# a missing file, never silently as "no violations found in zero files".
# NOTE: iteration is over the BASENAME list (no spaces by construction), and
# each path is re-derived from "$const_dir" inside the loop — never over a
# space-joined path list, which would split a directory path containing a
# space and audit the wrong (or no) file while reporting a confident zero.
b_missing=0
present_bases=""
for base in $CANONICAL_FILES; do
    f="${const_dir}/${base}"
    if [ -f "$f" ] && [ -s "$f" ] && [ -r "$f" ]; then
        present_bases="${present_bases}${base} "
    else
        echo "❌ (b) CANONICAL-ROOT-PRESENT: ${f} is missing, empty or unreadable"
        b_missing=$((b_missing + 1))
    fi
done
if [ "$b_missing" -eq 0 ]; then
    [ -n "$quiet" ] || echo "✅ (b) CANONICAL-ROOT-PRESENT: all 3 canonical files present + non-empty under ${const_dir}"
else
    fail=1
fi

# ── Control needle (§11.4.201(7)(b)) — before any absence is trusted ────────
# Class-matched: same fence-stripped path, same line-anchored `## ` heading
# shape as the certified (c) query. Run on every file (c) will audit, plus
# the consumer file (a) will audit.
needle_blind=0
needle_report=""
for base in $present_bases; do
    f="${const_dir}/${base}"
    n="$(crc_count "$f" "$RE_NEEDLE")"
    needle_report="${needle_report}${base}=${n} "
    if [ "$n" -le 0 ]; then
        echo "❌ NEEDLE: fence-stripped anchored-heading query found 0 headings in ${f} — the instrument may be BLIND; refusing to report any absence from it (§11.4.201(7)(b))"
        needle_blind=$((needle_blind + 1))
    fi
done
neg_total=0
for base in $present_bases; do
    f="${const_dir}/${base}"
    nn="$(crc_count "$f" "$RE_NEG_CONTROL")"
    neg_total=$((neg_total + nn))
done
if [ "$neg_total" -ne 0 ]; then
    echo "❌ NEEDLE: negative-control query matched ${neg_total} time(s) — the instrument matches strings nobody wrote"
    needle_blind=$((needle_blind + 1))
fi
if [ "$needle_blind" -ne 0 ]; then
    echo "❌ ${GATE}: BLIND — control needle failed; no absence reported by this run may be trusted" >&2
    exit 2
fi
[ -n "$quiet" ] || echo "✅ NEEDLE: instrument proven to see (${needle_report}) and negative control = 0"

# ── Invariant (c): the canonical root is NOT itself a consumer ──────────────
# A "live pointer" is either form the anchor names in (a) — the
# `## INHERITED FROM` heading or the `@constitution/<file>` import — matched
# line-anchored AFTER fenced code blocks are blanked out, so the corpus's own
# documentation of the pattern is correctly read as a CARRIER, not a pointer.
c_violations=0
for base in $present_bases; do
    f="${const_dir}/${base}"
    rel="$base"
    nh="$(crc_count "$f" "$RE_INHERIT_HEADING")"
    if [ "$nh" -gt 0 ]; then
        crc_hits "$f" "$RE_INHERIT_HEADING" | while IFS= read -r h; do
            echo "❌ (c) CANONICAL-ROOT-NOT-A-CONSUMER: ${rel}:${h} — live '## INHERITED FROM' heading in a canonical-root file (§11.4.35: these ARE the source-of-truth, not consumers)"
        done
        c_violations=$((c_violations + nh))
    fi
    ni="$(crc_count "$f" "$RE_INHERIT_IMPORT")"
    if [ "$ni" -gt 0 ]; then
        crc_hits "$f" "$RE_INHERIT_IMPORT" | while IFS= read -r h; do
            echo "❌ (c) CANONICAL-ROOT-NOT-A-CONSUMER: ${rel}:${h} — live '@constitution/...' import pointer in a canonical-root file"
        done
        c_violations=$((c_violations + ni))
    fi
done
if [ "$c_violations" -eq 0 ]; then
    [ -n "$quiet" ] || echo "✅ (c) CANONICAL-ROOT-NOT-A-CONSUMER: 0 live inheritance pointers across the canonical files (fenced carriers correctly excluded)"
else
    echo "❌ (c) CANONICAL-ROOT-NOT-A-CONSUMER: ${c_violations} live inheritance pointer(s) in the canonical root"
    fail=1
fi

# ── Invariant (a): the consumer opens with the inheritance pointer ──────────
consumer_claude="${consumer_root}/CLAUDE.md"
if [ -n "$standalone" ]; then
    echo "⏭  (a) CONSUMER-POINTER-PRESENT: SKIP — standalone canon checkout (${const_dir} is its own git toplevel, has no superproject, and its parent is in no git work tree): there is no consumer CLAUDE.md to audit; pass --consumer-root to audit one"
elif [ ! -f "$consumer_claude" ] || [ ! -r "$consumer_claude" ]; then
    echo "❌ (a) CONSUMER-POINTER-PRESENT: consumer CLAUDE.md missing or unreadable at ${consumer_claude}"
    fail=1
else
    a_needle="$(crc_count "$consumer_claude" "$RE_NEEDLE")"
    if [ "$a_needle" -le 0 ]; then
        echo "❌ ${GATE}: BLIND — control needle found 0 anchored headings in ${consumer_claude}; refusing to report a pointer absence from a possibly-blind instrument" >&2
        exit 2
    fi
    # The pointer must name THIS consumer's real path to its constitution:
    # <const_dir relative to consumer_root>/CLAUDE.md (a legacy consumer that
    # points at submodules/constitution/CLAUDE.md, or the reverse, points at a
    # file that does not exist there and is refused).
    case "$const_dir" in
        "$consumer_root"/*) a_rel="${const_dir#"$consumer_root"/}" ;;
        *)                  a_rel="$const_dir" ;;
    esac
    a_expect="${a_rel}/CLAUDE.md"
    a_esc="$(printf '%s' "$a_expect" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
    a_rel_esc="$(printf '%s' "$a_rel" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
    # Heading: '## INHERITED FROM <rel>/CLAUDE.md', optionally followed by
    # whitespace and free text (a real consumer writes
    # '## INHERITED FROM constitution/CLAUDE.md (HelixConstitution submodule)').
    # The path must end at whitespace or end-of-line, so '<rel>/CLAUDE.md.bak'
    # or '<rel>/CLAUDE.mdx' is still refused.
    a_head="$(crc_count "$consumer_claude" "^## INHERITED FROM ${a_esc}([[:space:]].*)?\$" "$head_lines")"
    # Import: '@<rel>/{CLAUDE,AGENTS,Constitution}.md' (any canonical file),
    # nothing but whitespace after it.
    a_imp="$(crc_count "$consumer_claude" "^@${a_rel_esc}/(CLAUDE|AGENTS|Constitution)\\.md[[:space:]]*\$" "$head_lines")"
    a_total=$((a_head + a_imp))
    a_any=$(( $(crc_count "$consumer_claude" "$RE_INHERIT_HEADING" "$head_lines") + $(crc_count "$consumer_claude" "^@" "$head_lines") ))
    if [ "$a_total" -gt 0 ]; then
        [ -n "$quiet" ] || echo "✅ (a) CONSUMER-POINTER-PRESENT: ${consumer_claude} opens with the inheritance pointer to ${a_expect} within its first ${head_lines} lines (heading=${a_head} import=${a_imp})"
    elif [ "$a_any" -gt 0 ]; then
        echo "❌ (a) CONSUMER-POINTER-PRESENT: ${consumer_claude} carries an inheritance pointer, but none names this consumer's constitution path — expected '## INHERITED FROM ${a_expect}' or '@${a_expect}' (constitution at ${const_dir})"
        fail=1
    else
        echo "❌ (a) CONSUMER-POINTER-PRESENT: ${consumer_claude} carries no live inheritance pointer in its first ${head_lines} lines — neither a '## INHERITED FROM ${a_expect}' heading nor an '@${a_expect}' import (a fenced example does not count, §11.4.201(7)(a))"
        fail=1
    fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -eq 0 ] && [ -n "$standalone" ]; then
    echo "⏭  ${GATE}: SKIP — (b) and (c) hold; (a) not applicable (standalone canon checkout, no consumer) [const-dir=${const_dir}]"
    exit 3
fi
if [ "$fail" -eq 0 ]; then
    echo "✅ ${GATE}: PASS — (a) consumer pointer present, (b) canonical root present, (c) canonical root is not a consumer [const-dir=${const_dir}]"
    exit 0
fi
echo "❌ ${GATE}: FAIL — see violations above [const-dir=${const_dir} consumer-root=${consumer_root}]"
exit 1
