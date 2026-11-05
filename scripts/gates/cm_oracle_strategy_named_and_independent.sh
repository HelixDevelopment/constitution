#!/usr/bin/env bash
# cm_oracle_strategy_named_and_independent.sh — CM-ORACLE-STRATEGY-NAMED-AND-
# INDEPENDENT gate (anchor §11.4.245).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.245 mandates that every test FIRST identify its ORACLE — the
# mechanism deciding PASS vs FAIL for the input it drives — drawn from a
# CLOSED 7-member strategy set: SPECIFIED, DERIVED, METAMORPHIC,
# GOLDEN-MASTER/CHARACTERIZATION, INVARIANT, STATISTICAL, HUMAN ("NO other
# classes"). Authoring a test WITHOUT naming its oracle strategy produces the
# "test agrees with code" anti-pattern: a test that asserts whatever the code
# under test happens to produce, so it passes as long as the code produces
# ANYTHING, never catching a wrong output.
#
# This gate is the HARD-GATED, LITERAL-CHECKABLE half of the anchor: it walks
# Python test-function definitions and FAILs when a test has no oracle-
# strategy annotation, OR when the annotated value is not one of the closed
# seven (a typo'd / invented strategy name is caught too, per the anchor's
# "NO other classes").
#
# ── Convention (this is the machine-checkable contract, documented here
#    because no such convention pre-existed in the corpus) ──────────────────
# Every `def test_*(` / `async def test_*(` function MUST carry, either as a
# trailing/preceding `#`-comment within 3 lines of the `def` line, OR as a
# line inside the function's own docstring, the pattern:
#
#     oracle: <STRATEGY>
#
# (case-insensitive on both "oracle" and the strategy token; hyphens and
# underscores are interchangeable — "GOLDEN-MASTER" and "GOLDEN_MASTER" are
# the same closed-set member). <STRATEGY> MUST be one of:
#     SPECIFIED | DERIVED | METAMORPHIC | GOLDEN_MASTER | CHARACTERIZATION |
#     INVARIANT | STATISTICAL | HUMAN
#
# ── Deliberate scope (honest, stated tradeoff — §11.4.6) ────────────────────
# This gate verifies the anchor's NAMED-strategy invariant (a literal,
# mechanically-checkable presence-and-closed-set-membership check). It does
# NOT verify STRUCTURAL INDEPENDENCE (that the oracle's source of expected
# value is genuinely different from the code under test) — proving that is a
# semantic / data-flow property this text scanner cannot honestly claim to
# decide. It also does NOT verify that a paired §1.1 mutation flips the
# oracle (§11.4.245's third reviewer-verification item) — that is a runtime
# property of the test suite, not a static-source property. Both remaining
# invariants stay §11.4.194/§11.4.142 human/reviewer territory, never
# silently assumed satisfied by this gate's PASS.
#
# Function-boundary detection is indentation-based (POSIX-portable awk, no
# AST parser) — a bounded heuristic that assumes conventional PEP-8-style
# indentation; a test function using tabs-and-spaces inconsistently could, in
# principle, mis-detect its own boundary. This limitation is documented, not
# silent (§11.4.6).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_oracle_strategy_named_and_independent.sh [--root <dir>] [--quiet]
#     --root <dir>   scan root (default: $ORACLE_GUARD_ROOT or the gate-location default: superproject if vendored as a submodule, else the canon repo itself)
#     --quiet        suppress per-file PASS lines (FAIL lines always shown)
#     --include-third-party
#                    also scan third-party / separate-repository trees (opt-in;
#                    default prunes them, see "Scope" below)
#     --strict       legacy absolute mode: every unannotated test function FAILs (no baseline
#                    needed). Also ORACLE_GUARD_STRICT=1. Used by fixtures/mutation tests.
#     --baseline <f> ratchet baseline file (default: <root>/config/oracle_ratchet_baseline.txt,
#                    or $ORACLE_GUARD_BASELINE -- the env form is honoured ONLY with HELIX_TEST_MODE=1 and a path under the temp root; the verdict line prints baseline= and overrides=)
#     --adopt-new-files --reason "<text>"  add baseline entries ONLY for files without one (never raises/lowers an existing entry; audited append to config/oracle_ratchet_adoptions.log; no --reason = refused rc=2)
#     --exclusions <f>  frozen-evidence exclusion list (default: <root>/config/oracle_frozen_evidence_exclusions.tsv; absent = none).
#                    TAB columns `path class blob-id reason`, header `# ceiling: N` REQUIRED. See "Frozen-evidence exclusions" below.
#     --write-baseline  create the baseline from the current counts, or LOWER an existing one
#                    (refuses, rc=1, when any file's count is above its baseline)
#     --base <ref>   git ref the NEW/MODIFIED-function check diffs against. Default (and the ONLY
#                    ceiling): the OLDEST merge-base of HEAD with @{upstream} or any remote-tracking
#                    <remote>/main|master (multi-upstream: remotes may be github_x etc.). --base may only be
#                    that base or OLDER (an ancestor of HEAD not newer than it); anything newer, or
#                    unresolvable, is refused (rc 2). There is NO environment override (ORACLE_GUARD_BASE is
#                    ignored with a note). With no remote main sharing history with HEAD the check is
#                    BLIND (rc 2), never a sliding HEAD~1. --adopt-new-files forbids --base entirely and
#                    refuses any file whose unannotated functions are NEW/MODIFIED relative to the base.
#                    The effective base is printed in the verdict line (base=<sha12>), with the remote ref that selected it
#                    (via=<ref>) and rule3=evaluated|skipped (skipped = not a git tree: the new/modified-function check did not run).
#     -h|--help      print this header
#
# ── Ratchet mode (default; operator decision 2026-11-01) ────────────────────
# Brownfield adoption (§11.4.66/§11.4.224(E), the CM-ZERO-FINDINGS-MONOTONE-RATCHET pattern): a checked-in
# baseline `<relative-path><TAB><count>` records, per file, how many test functions lack a valid oracle
# annotation. Rules, each independent:
#   (1) a file whose live unannotated count is ABOVE its baseline (absent file = 0) FAILs;
#   (2) a count BELOW the baseline passes and prints how to lower it (`--write-baseline`) -- the baseline
#       may only decrease; a baseline entry for a vanished file gets the same note;
#   (3) every NEW or MODIFIED test function (added lines of `git diff <base>` -- committed since the base,
#       staged and unstaged -- plus every line of an untracked file) MUST carry a valid annotation, even
#       when its file has baseline slack; UNTOUCHED legacy tests are never failed by (3) (golden-FALSE);
#   (4) a MISSING or malformed baseline is a config error (rc=2, "BLIND"), never a silent pass;
#   (5) outside a git repository (3) cannot be evaluated and is reported as SKIPPED, not passed.
# Deletion-only hunks (F2): a hunk that only deletes lines adds no function and is ignored, EXCEPT when the removed
# lines contain an `oracle:` annotation and no `def test` -- the annotation was stripped from a function that stays,
# so the neighbouring function counts as MODIFIED and must be annotated again.
# Honest limit (F4): rule (3) diffs the scanned repo only; it cannot see INSIDE an own-org submodule's
# contents (a gitlink bump shows as one changed line), so new/modified test functions in a baseline-covered
# submodule are held only by that submodule's own ratchet/count rule (1), not by rule (3). Every adoption log
# line carries `limit=submodule_contents_not_diffed`. Content pushed to the upstream main is trusted by the
# adoption base (it was reviewed at push time); only unpushed/uncommitted content is checked.
# Annotation zone (delta review 2026-11-03): above a def only comment-only/decorator lines at the def own
# indentation count; the trailing `# oracle:` of the previous function last body line never annotates the next def.
# Honest limit: a pure `git mv` of a test file (rule 3 sees every line as new in the new path) needs
# --adopt-new-files --reason "..." to carry the old count over; the ratchet never follows renames by itself.
# Honest limit: a legacy function edited without annotation is "modified" and must be annotated; a baseline
# raised by hand is only caught by review/VCS history (stateless check, like the zero-findings ratchet).
#
# ── Frozen-evidence exclusions (CON-043, operator decision 2026-11-05) ──────
# Some test-named files are archived RED evidence that can no longer run and that no runner executes (e.g. the p1-red-original
# harness inside a submodule). Annotating them would falsify the archive; carrying them in the ratchet baseline hides them.
# A checked-in list (ratchet mode only; --strict ignores it) excludes them from the scan under these rules, each independent:
#   (1) a LITERAL repository-relative file path per entry: a glob character (* ? [ ] { }), an absolute path, a `..` or `.`
#       segment (incl. a leading `./` or a trailing `/.`), `//`, a trailing slash, or a duplicate is a malformed list => BLIND
#       (rc 2); each entry has EXACTLY 4 TAB-separated non-empty columns (a doubled, leading or trailing TAB is BLIND, never
#       collapsed); an unreadable list, or a list path that is not a regular file, is BLIND;
#   (2) class from the CLOSED set {frozen-red-evidence}; anything else => BLIND;
#   (3) the entry records the git blob id of the frozen file as the repository that OWNS it computes it (40-hex sha1 or 64-hex
#       sha256): `git -C <file's directory> hash-object --path=<name> <name>`, i.e. with that repository's object format and
#       checkout filters (core.autocrlf, eol, ident), the id `git status` compares and `git ls-tree` shows; independent of the
#       caller's cwd. When the file's current id differs, or it is not a regular file, or it cannot be hashed, the entry is
#       VOIDED: the file is scanned again AND the gate FAILs naming the entry (raising the baseline cannot hide it); a vanished
#       file is only a stale note (an uninitialised submodule looks the same, so the note does not demand removal);
#       --write-baseline and --adopt-new-files REFUSE (rc 1, reason=exclusions_voided) while an entry is voided or over the
#       ceiling, so they never print PASS after a FAIL line;
#   (4) the header `# ceiling: N` is required (else BLIND) and the entry count may not exceed it (FAIL); the ceiling may only
#       be lowered (stateless like the baseline: a hand-raised ceiling is caught by review/VCS history only);
#   (5) that no runner executes a listed file is NOT decided by the gate: tests/gates/test_oracle_frozen_exclusions.sh proves it
#       for the shipped list. The gate does not read the blob contents, so it cannot tell that bytes still "are" frozen
#       evidence; the blob id only proves they are the bytes that were reviewed when the entry was written.
#
# ── Scope: third-party trees are pruned by default (triage 2026-10-31) ──────
# Only trees the scanned repository does not own are pruned (operator decision
# 2026-11-01): every helix-deps.yaml dep marked `third_party: true` (its `path:`
# or `submodules/<name>`), resolved by scripts/lib/third_party_prune.sh, plus
# the directory names `third_party` and `site-packages`. `.gitmodules` paths
# are NOT pruned: own-org submodules are scanned. Unsafe manifest paths are
# dropped, never interpreted. Opt back in with --include-third-party or
# ORACLE_GUARD_INCLUDE_THIRD_PARTY=1 (the default prune list below still
# applies; ORACLE_GUARD_EXCLUDE is additive to the manifest-derived prune).
#
# ── Annotation grammar (closed; prose is never an annotation) ───────────────
# A line is an annotation ONLY when `oracle:` begins the comment or docstring
# text — start of line, or right after `#` / an opening triple quote — and the
# strategy token is followed by end of line, `#`, a closing triple quote, `(`,
# `;` or `,`. Prose such as "Independent oracle: raw grep" or "The oracle: the
# reference output ..." is therefore NOT parsed as the (unknown) strategy
# RAW / THE; it is simply not an annotation.
#
# ── Environment overrides (§11.4.28/§11.4.35 — project-agnostic) ────────────
#   ORACLE_GUARD_ROOT      default scan root (else --root, else the gate-location default, see scripts/lib/default_scan_root.sh)
#   ORACLE_GUARD_GLOB      -iname glob for candidate test files
#                           (default: "*test*.py")
#   ORACLE_GUARD_INCLUDE_THIRD_PARTY  1 = same as --include-third-party
#   ORACLE_GUARD_EXCLUDE   space-separated dir-name globs to prune
#                          (default: ".git node_modules vendor .venv
#                           __pycache__ scripts/gates out build dist
#                           third_party site-packages")
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-violation evidence line (file:line of the `def test_...` + reason:
#   missing annotation vs. unknown strategy value) + a final verdict.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only; no network, no commit, no test is ever executed — the
#   scanner only reads source text).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, find, awk (POSIX-portable). Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.245 (the anchor enforced — the closed 7-member oracle-strategy
#   set), §11.4.201(1)/(7)(a) (false-positive refusal is a FAIL-bluff; match
#   structure not substring), §11.4.6 (honest documented bounded limitation),
#   §11.4.28/§11.4.35 (project-agnostic, env-var-driven), §1.1 (paired
#   mutation: cm_oracle_strategy_named_and_independent_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — PASS (strict: every test function names a valid closed-set oracle strategy; ratchet: no file
#       above its baseline and no new/modified unannotated function), or SKIP: no candidate test files and
#       no voided exclusion (decided before the rule-3 base, so a missing remote main or a bad --base does not change it).
#   1 — FAIL (strict: a test function has no/unknown annotation; ratchet: above baseline, or a new/modified
#       function unannotated, or a frozen-evidence exclusion voided / over its ceiling, or --write-baseline or
#       --adopt-new-files refused, incl. reason=exclusions_voided).
#   2 — environment / argument error, or BLIND: ratchet baseline missing/malformed, frozen-evidence exclusion list
#       malformed/unreadable (reason=exclusions_malformed), no non-sliding base (reason=no_nonsliding_base), or a
#       refused --base (verdict FAIL, reason=base_not_older_than_nonsliding_base).
#   A final `ORACLE-VERDICT<TAB>PASS|FAIL|BLIND|SKIP<TAB>mode=...` line is machine-readable.
#
# ── The basis line (CON-044): deliberately NOT enforced ─────────────────────
# Some annotations carry a separate comment line `# basis: <text>` stating where the expected value comes from.
# That line is NOT part of this gate's annotation grammar and is NOT enforced. Measured facts (base feacc507, scan
# scope = own-org submodules included, which is why the llmctl numbers matter; §11.4.273 control-needled):
#   - `# basis:` is defined in no anchor, guide or doc (§11.4.245 requires a NAMED strategy and leaves independence
#     to the reviewer). It IS used: 115 lines in 8 files under submodules/llmctl/tests/py (llmctl oracle waves b2/b3,
#     2026-11-05), always as a free-text line ABOVE a bare `# oracle: X`. The other 554 of the 669 annotations use
#     `# oracle: X (reason)`, the justification in the parenthetical.
#   - ORDER MATTERS with the gate's 3-line window: the basis line goes ABOVE the oracle line. `# basis:` then
#     `# oracle: X` then up to two decorators then `def` PASSes; `# oracle: X` then `# basis:` then two decorators
#     then `def` FAILs, because the basis line uses a window slot.
# Why it is not enforced:
#   (b) the gate can check only that the text is PRESENT, not that it is TRUE or independent of the code under test
#       (§11.4.245 independence stays §11.4.194/§11.4.142 reviewer territory), so a presence-only check would reward
#       filler text, the "presence >= 1" pattern §11.4.227 warns against;
#   (c) a MANDATORY basis line would fail the 554 parenthetical-form annotations and would need a baseline or grammar
#       decision. An either-form rule ("justification as parenthetical OR as basis line") would fail none of the 669
#       today, but it is still presence-only, so (b) applies to it too.
# Whether to enforce it (and in which form) remains an operator decision (§11.4.66); if so, define the grammar in the
# anchor first, then extend this gate.
# Pinned by the mutation test (section 8): an annotation without a basis line PASSes; the llmctl form (basis above a
# bare oracle) PASSes; a lone `# basis:` line, with or without a strategy token, is NOT an annotation; oracle-above-basis
# with two decorators FAILs; gate variants that require a basis line, accept `basis` as an oracle keyword, or reject
# an annotation preceded by a basis line are killed.
#
# Classification: universal (§11.4.17) — no project-specific literal.

set -uo pipefail

GATE="CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT"
ANCHOR="11.4.245"

# verdict-affecting ambient overrides are guarded (11.4.276 r8): honoured only under HELIX_TEST_MODE=1 (+ temp path for paths)
_ge_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/gate_env_override.sh"
# shellcheck source=/dev/null
if [ -r "$_ge_lib" ]; then . "$_ge_lib"; else cm_gate_env_set() { printf -v "$1" '%s' "$3"; [ -z "${!2:-}" ] || echo "gate_env_override: ignoring $2 (guard lib missing: fail closed)" >&2; }; fi
cm_gate_env_set root ORACLE_GUARD_ROOT "" path   # ambient root guarded (an empty dir would SKIP); empty => resolved from the gate location after arg parsing (lib/default_scan_root.sh), NOT from cwd; --root stays honoured
cm_gate_env_set glob ORACLE_GUARD_GLOB "*test*.py" value
quiet=0
strict="${ORACLE_GUARD_STRICT:-0}"
cm_gate_env_set baseline ORACLE_GUARD_BASELINE "" path
base_ref=""            # --base only; NO environment override exists (round 3, I2): an ambient variable must never turn a FAIL into a PASS
[ -z "${ORACLE_GUARD_BASE:-}" ] || echo "${GATE}: note: ORACLE_GUARD_BASE is ignored (no environment override of the diff base exists; use --base with an older ancestor)" >&2
write_baseline=0
excl_file=""            # --exclusions only (CON-043); default <root>/config/oracle_frozen_evidence_exclusions.tsv
adopt_new=0
adopt_reason=""
adopt_reason_given=0
include_tp="${ORACLE_GUARD_INCLUDE_THIRD_PARTY:-0}"

while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || { echo "${GATE}: $1 requires a value" >&2; exit 2; }; root="$2"; shift 2 ;;
        --glob) [ $# -ge 2 ] || { echo "${GATE}: $1 requires a value" >&2; exit 2; }; glob="$2"; shift 2 ;;
        --quiet) quiet=1; shift ;;
        --strict) strict=1; shift ;;
        --baseline) [ $# -ge 2 ] || { echo "${GATE}: $1 requires a value" >&2; exit 2; }; baseline="$2"; shift 2 ;;
        --base) [ $# -ge 2 ] || { echo "${GATE}: $1 requires a value" >&2; exit 2; }; base_ref="$2"; shift 2 ;;
        --exclusions) [ $# -ge 2 ] || { echo "${GATE}: $1 requires a value" >&2; exit 2; }; excl_file="$2"; shift 2 ;;
        --write-baseline) write_baseline=1; shift ;;
        --adopt-new-files) adopt_new=1; shift ;;
        --reason) adopt_reason="${2-}"; adopt_reason_given=1; shift 2 || shift ;;
        --include-third-party) include_tp=1; shift ;;
        -h|--help) sed -n "1,$(awk '/^# Classification:/{print NR; exit}' "$0")p" "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

if [ "$adopt_new" = 1 ]; then
    _r="${adopt_reason//[[:space:]]/}"
    if [ "$adopt_reason_given" != 1 ] || [ -z "$_r" ] || [[ "$adopt_reason" == *$'\t'* ]] || [[ "$adopt_reason" == *$'\n'* ]]; then
        echo "${GATE}: --adopt-new-files requires a non-empty single-line --reason \"<text>\"; refused" >&2; exit 2
    fi
    if [ -n "$base_ref" ]; then
        echo "${GATE}: --adopt-new-files cannot be combined with --base (adoption always uses the non-sliding base); refused" >&2; exit 2
    fi
    if [ "$write_baseline" = 1 ] || [ "$strict" = 1 ]; then
        echo "${GATE}: --adopt-new-files cannot be combined with --write-baseline or --strict; refused" >&2; exit 2
    fi
elif [ "$adopt_reason_given" = 1 ]; then
    echo "${GATE}: --reason is only valid with --adopt-new-files" >&2; exit 2
fi

if [ -z "$root" ]; then
    # shellcheck source=/dev/null
    . "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/default_scan_root.sh" 2>/dev/null \
        && root="$(cm_default_scan_root "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)")"
    [ -n "$root" ] || { echo "${GATE}: cannot resolve a default scan root from the gate location; pass --root" >&2; exit 2; }
fi

[ -d "$root" ] || { echo "${GATE}: scan root not found: $root" >&2; exit 2; }
root="$(cd "$root" && pwd)"

cm_gate_env_set excludes ORACLE_GUARD_EXCLUDE ".git node_modules vendor .venv __pycache__ scripts/gates out build dist third_party site-packages" value
if [ "$include_tp" != 1 ]; then
    # shellcheck source=/dev/null
    tp_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../lib/third_party_prune.sh"
    [ -r "$tp_lib" ] && . "$tp_lib" 2>/dev/null || tp_lib=""
fi

prune_expr=()
for ex in $excludes; do
    case "$ex" in
        */*) prune_expr+=(-path "*/${ex}" -o -path "*/${ex}/*" -o) ;;
        *)   prune_expr+=(-name "$ex" -o) ;;
    esac
done
# third-party prune: root-anchored (see cm_third_party_prune_find_expr)
if [ "$include_tp" != 1 ] && [ -n "${tp_lib:-}" ]; then
    cm_third_party_prune_find_expr "$root"
fi
if [ "${#prune_expr[@]}" -gt 0 ]; then
    unset 'prune_expr[${#prune_expr[@]}-1]'
fi

mapfile -d '' -t files < <(
    if [ "${#prune_expr[@]}" -gt 0 ]; then
        find "$root" -type d \( "${prune_expr[@]}" \) -prune -o -type f -iname "$glob" -print0
    else
        find "$root" -type f -iname "$glob" -print0
    fi
)

# ── frozen-evidence exclusions (CON-043) -------------------------------------------------------------------
# Placed BEFORE the rule-3 base resolution (fix round 2, F2): it reads no rule-3 data, and the "no candidate files" SKIP
# right after it must not depend on a remote main or a valid --base (exit code 0 documented below).
declare -A excl_sha=() excl_voided=()
excl_n=0; excl_ceiling=""; excl_active=0; excl_voided_n=0; excl_applied=0; excl_stale=0
is_glob() { case "$1" in *'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*) return 0 ;; esac; return 1; }
excl_class_ok() { case "$1" in frozen-red-evidence) return 0 ;; esac; return 1; }
excl_sha_ok() { [ "$1" = "$2" ]; }
excl_over_ceiling() { [ "$1" -gt "$2" ]; }
excl_empty_field() { case "$1" in *$'\t\t'*|$'\t'*|*$'\t') return 0 ;; esac; return 1; }
excl_unreadable() { [ ! -r "$1" ]; }
excl_refuse_write() { [ "$excl_voided_n" -gt 0 ]; }
# The id git itself compares (fix round 2, F3): computed by the repository that OWNS the file (`-C` its directory), with
# that repository's object format (sha1 or sha256) and checkout filters (core.autocrlf, eol, ident: `--path`), exactly
# like `git status`. Never in the caller's cwd, never on raw bytes. $1 = absolute directory, $2 = file name in it.
excl_blob_id() { git -C "$1" hash-object --path="$2" -- "$2" 2>/dev/null; }
excl_blind() { echo "⚠ ${GATE}: BLIND — malformed frozen-evidence exclusion list ${excl_file}: $1" >&2; printf 'ORACLE-VERDICT\tBLIND\tmode=ratchet\treason=exclusions_malformed\n'; exit 2; }
if [ "$strict" != 1 ]; then
    [ -n "$excl_file" ] || excl_file="$root/config/oracle_frozen_evidence_exclusions.tsv"
    if [ -e "$excl_file" ] && [ ! -f "$excl_file" ]; then excl_blind "the list path exists but is not a regular file"; fi
    if [ -f "$excl_file" ]; then
        excl_unreadable "$excl_file" && excl_blind "the list is unreadable (permissions)"
        excl_active=1
        while IFS= read -r eline || [ -n "$eline" ]; do
            case "$eline" in
                '# ceiling: '*) [ -z "$excl_ceiling" ] || excl_blind "duplicate ceiling header"
                    excl_ceiling="${eline#\# ceiling: }"
                    [[ "$excl_ceiling" =~ ^(0|[1-9][0-9]*)$ ]] || excl_blind "ceiling is not a non-negative integer: '$excl_ceiling'"
                    continue ;;
                ''|'#'*) continue ;;
            esac
            # strict TAB split (F9): IFS whitespace would collapse an empty field, so a doubled/leading/trailing TAB is refused first
            excl_empty_field "$eline" && excl_blind "entry '${eline%%$'\t'*}' has an empty TAB-separated field"
            IFS=$'\t' read -r -a ef <<<"$eline"; excl_nf="${#ef[@]}"
            ep="${ef[0]}"; ecls="${ef[1]:-}"; esha="${ef[2]:-}"
            if [ "$excl_nf" -ne 4 ]; then excl_blind "entry '$ep' needs exactly 4 TAB-separated columns (path class blob-sha reason), has $excl_nf"; fi
            if is_glob "$ep"; then excl_blind "glob character in path '$ep'"; fi
            case "$ep" in /*|*/|../*|*/../*|*/..|..|./*|*/./*|*//*|*/.|.) excl_blind "path '$ep' is not a normalised literal repository-relative file" ;; esac
            excl_class_ok "$ecls" || excl_blind "class '$ecls' of '$ep' is not in the closed set {frozen-red-evidence}"
            [[ "$esha" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || excl_blind "blob id of '$ep' is not 40 (sha1) or 64 (sha256) lowercase hex"
            [ -z "${excl_sha[$ep]+x}" ] || excl_blind "duplicate entry '$ep'"
            excl_sha["$ep"]="$esha"; excl_n=$(( excl_n + 1 ))
        done < "$excl_file"
        [ -n "$excl_ceiling" ] || excl_blind "missing required header '# ceiling: N'"
        for ep in "${!excl_sha[@]}"; do
            if [ -L "$root/$ep" ] || { [ -e "$root/$ep" ] && [ ! -f "$root/$ep" ]; }; then excl_voided["$ep"]="not a regular file"
            elif [ ! -e "$root/$ep" ]; then excl_stale=$(( excl_stale + 1 )); echo "⚠ ${GATE}: stale exclusion entry ${ep}: no such file under the scan root (an uninitialised submodule, or the file was removed: then remove the entry and lower the ceiling)"
            else
                cur_sha="$(excl_blob_id "$root/$(dirname -- "$ep")" "$(basename -- "$ep")" || true)"
                if excl_sha_ok "$cur_sha" "${excl_sha[$ep]}"; then excl_applied=$(( excl_applied + 1 ))
                else excl_voided["$ep"]="blob id ${cur_sha:-unreadable} != recorded ${excl_sha[$ep]}"; fi
            fi
        done
        excl_voided_n="${#excl_voided[@]}"
        for ep in "${!excl_voided[@]}"; do
            echo "❌ ${GATE}: FAIL — frozen-evidence exclusion VOIDED for ${ep}: ${excl_voided[$ep]} (the file is scanned again; a frozen file must not change)"
        done
        if excl_over_ceiling "$excl_n" "$excl_ceiling"; then
            echo "❌ ${GATE}: FAIL — ${excl_n} exclusion entries exceed the ceiling ${excl_ceiling} (the count may only decrease)"
            excl_voided_n=$(( excl_voided_n + 1 ))
        fi
    fi
fi

# a voided exclusion must FAIL even when no file is left to scan (e.g. the frozen path became a dangling symlink)
if [ "${#files[@]}" -eq 0 ] && [ "$excl_voided_n" -eq 0 ]; then
    echo "⏭ ${GATE}: SKIP — topology_unsupported: no candidate test files under scan (root=$root, glob=$glob)"
    printf 'ORACLE-VERDICT\tSKIP\treason=topology_unsupported\n'
    exit 0
fi
# F8: --write-baseline / --adopt-new-files never print PASS after an exclusion FAIL line: they refuse, the files untouched
if { [ "$write_baseline" = 1 ] || [ "$adopt_new" = 1 ]; } && excl_refuse_write; then
    _m="$([ "$adopt_new" = 1 ] && echo adopt || echo write-baseline)"
    echo "❌ ${GATE}: FAIL — ${_m} refused: ${excl_voided_n} voided/over-ceiling frozen-evidence exclusion problem(s); fix the list first (baseline not written)"
    printf 'ORACLE-VERDICT\tFAIL\tmode=%s\treason=exclusions_voided\tvoided=%s\n' "$_m" "$excl_voided_n"
    exit 1
fi



AWK_SCRIPT='
BEGIN {
    split("SPECIFIED DERIVED METAMORPHIC GOLDEN_MASTER CHARACTERIZATION INVARIANT STATISTICAL HUMAN", ok_arr, " ")
    for (n = 1; n in ok_arr; n++) ok[ok_arr[n]] = 1
}
{ sub(/\r$/, ""); lines[NR] = $0 }
# Closed annotation grammar: returns the UPPER-CASED token of a line that IS an
# annotation, else "". `oracle:` must open the comment/docstring text (line
# start, or right after `#` / quote characters) and the token must be followed
# by end of line, `#`, a quote, `(`, `;` or `,` -- so prose such as
# "Independent oracle: raw grep" or "The oracle: the reference ..." is not one.
# A line may sit in the annotation zone ABOVE a def only if it is a comment-only or decorator line
# at the def own indentation (anything else is the last code line of a PRIOR block: its trailing
# `# oracle:` belongs to that block, never to the next function).
function lead(raw,   n, c) {
    n = 0
    while (n + 1 <= length(raw)) { c = substr(raw, n + 1, 1); if (c == " " || c == "\t") n++; else break }
    return n
}
function above_ok(raw, di) {
    if (raw !~ /^[ \t]*[#@]/) return 0
    return lead(raw) == di
}
function annot(raw,   l, m, i, rest) {
    l = tolower(raw)
    if (!match(l, /(^|#)[ \t]*["\047]*[ \t]*oracle[ \t]*:[ \t]*[a-z_-]+([ \t]*[(#;,"\047]|[ \t]*$)/)) return ""
    m = substr(raw, RSTART, RLENGTH)
    i = index(tolower(m), "oracle")
    rest = substr(m, i + 6)
    sub(/^[ \t]*:[ \t]*/, "", rest)
    match(rest, /^[A-Za-z_-]+/)
    rest = toupper(substr(rest, RSTART, RLENGTH))
    gsub(/-/, "_", rest)
    return rest
}
END {
    total = NR
    while (chg != "" && (getline rl < chg) > 0) { split(rl, rr, " "); nr++; rs[nr] = rr[1] + 0; re[nr] = rr[2] + 0 }
    for (i = 1; i <= total; i++) {
        line = lines[i]
        if (match(line, /^[ \t]*(async[ \t]+)?def[ \t]+test_[A-Za-z0-9_]*[ \t]*\(/)) {
            indent = 0
            while (indent + 1 <= length(line)) {
                c = substr(line, indent + 1, 1)
                if (c == " " || c == "\t") indent++
                else break
            }
            fend = total + 1
            for (k = i + 1; k <= total; k++) {
                kl = lines[k]
                if (kl ~ /^[ \t]*$/) continue
                kindent = 0
                while (kindent + 1 <= length(kl)) {
                    c = substr(kl, kindent + 1, 1)
                    if (c == " " || c == "\t") kindent++
                    else break
                }
                if (kindent <= indent) { fend = k; break }
            }
            found = 0
            bad_val = ""
            # (1) BACKWARD bounded scan for a PRECEDING annotation (<= 3 lines, never crossing a blank
            # line or another def/class boundary -- otherwise it bleeds into a PRIOR test function body
            # and picks up ITS annotation: a real cross-contamination PASS-bluff caught in this gate own
            # smoke-testing).
            back_limit = i - 3
            if (back_limit < 1) back_limit = 1
            for (k = i - 1; k >= back_limit; k--) {
                kl = lines[k]
                if (!above_ok(kl, indent)) break
                val = annot(kl)
                if (val != "") {
                    if (val in ok) { found = 1 } else { bad_val = val }
                    break
                }
            }
            # (2) FORWARD scan within THIS function own body [i, fend): can never see a prior function.
            if (!found) {
                for (k = i; k < fend; k++) {
                    kl = lines[k]
                    val = annot(kl)
                    if (val != "") {
                        if (val in ok) { found = 1; bad_val = "" } else { bad_val = val }
                        break
                    }
                }
            }
            if (!found) {
                isnew = "OLD"
                # extent = def line .. last NON-BLANK body line (trailing blank lines belong to no function, so a
                # blank line added between two tests never marks the earlier one as modified)
                lastnb = i
                for (k = fend - 1; k > i; k--) if (lines[k] !~ /^[ \t]*$/) { lastnb = k; break }
                # the 3-line window ABOVE the def (same bounds as the backward annotation scan: stops at a blank line,
                # another def or a class) belongs to this function: replacing/removing an annotation there modifies it
                wstart = i
                for (k = i - 1; k >= back_limit; k--) {
                    kl = lines[k]
                    if (!above_ok(kl, indent)) break
                    wstart = k
                }
                for (q = 1; q <= nr; q++) if (rs[q] <= lastnb && re[q] >= wstart) { isnew = "NEW"; break }
                if (bad_val != "") print i "\tUNKNOWN_STRATEGY:" bad_val "\t" isnew "\t" line
                else print i "\tMISSING\t" isnew "\t" line
            }
        }
    }
}
'

# ── changed-line ranges for the NEW/MODIFIED-function check (ratchet mode only) ─────────────────────────
chg_master="$(mktemp)"; : "${chg_master:?}"
chg_one="$(mktemp)"; : "${chg_one:?}"
trap 'rm -f -- "${chg_master:?}" "${chg_one:?}"' EXIT
diff_state="SKIPPED (not a git work tree)"
nsb_via="none"
if [ "$strict" != 1 ] && [ "$write_baseline" != 1 ] && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Non-sliding base (F2 + round 3 I3): the merge-base of HEAD with a remote main. Candidates are
    # @{upstream} PLUS EVERY remote-tracking `<remote>/main` and `<remote>/master` (a §2.1 multi-upstream
    # checkout names its remotes github_x, gitlab_y, ... and has no `origin`). Rule: of all candidate
    # merge-bases take the OLDEST (the one with the largest `<mb>..HEAD` range): the most conservative,
    # it checks the most unpushed content and an upstream that is ahead cannot hide commits that another
    # upstream has not received. Empty commits cannot move it. If NO candidate resolves (no remote main, a
    # shallow clone that cannot reach a merge-base) there is no sound base: the new/modified-function check
    # is BLIND (rc 2), never a silent HEAD~1.
    head_sha="$(git -C "$root" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null || true)"
    nsb=""; best=-1
    cands="@{upstream}"
    cands="$cands $(git -C "$root" for-each-ref --format='%(refname)' 'refs/remotes/*/main' 'refs/remotes/*/master' 2>/dev/null | tr '\n' ' ')"
    for _u in $cands; do
        git -C "$root" rev-parse --verify -q "${_u}^{commit}" >/dev/null 2>&1 || continue
        _mb="$(git -C "$root" merge-base HEAD "$_u" 2>/dev/null || true)"; [ -n "$_mb" ] || continue
        _n="$(git -C "$root" rev-list --count "${_mb}..HEAD" 2>/dev/null || echo 0)"
        if [ "$_n" -gt "$best" ]; then best="$_n"; nsb="$_mb"; nsb_via="$_u"; fi
    done
    if [ -z "$nsb" ]; then
        echo "❌ ${GATE}: BLIND — no non-sliding base: no remote main/master ref (@{upstream}, <remote>/main, <remote>/master) shares history with HEAD (shallow clone? no remote fetched?); fetch a remote main and re-run. A sliding HEAD~1 is never substituted" >&2
        printf 'ORACLE-VERDICT\tBLIND\tmode=%s\treason=no_nonsliding_base\n' "$([ "$adopt_new" = 1 ] && echo adopt || echo ratchet)"; exit 2
    fi
    if [ -n "$base_ref" ]; then
        # --base may only be STRICTER (older): an ancestor of HEAD that is not newer than the non-sliding base.
        _bs="$(git -C "$root" rev-parse --verify -q "${base_ref}^{commit}" 2>/dev/null || true)"
        if [ -z "$_bs" ] || ! git -C "$root" merge-base --is-ancestor "$_bs" HEAD 2>/dev/null \
           || ! git -C "$root" merge-base --is-ancestor "$_bs" "$nsb" 2>/dev/null; then
            echo "❌ ${GATE}: --base '${base_ref}' refused: it must resolve, be an ancestor of HEAD, and be the non-sliding base (${nsb:0:12}) or OLDER; a newer base would hide commits" >&2
            printf 'ORACLE-VERDICT\tFAIL\tmode=ratchet\treason=base_not_older_than_nonsliding_base\n'; exit 2
        fi
        base_ref="$_bs"
    else
        base_ref="$nsb"
    fi
    if git -C "$root" rev-parse --verify -q "${base_ref}^{commit}" >/dev/null 2>&1; then
        # F2: a deletion-only hunk (`+st,0`) adds no function, so it is NOT itself a new/changed test; but
        # if the removed lines carry an `oracle:` annotation and no `def test` (the annotation was stripped
        # from a function that stays), the neighbouring function IS modified: mark new-file lines st..st+1.
        git -C "$root" -c core.quotepath=off diff -U0 --no-color --no-ext-diff --relative "$base_ref" -- . 2>/dev/null | awk '
            function flush() {
                if (pend && delann && !deldef) printf "%s\t%d\t%d\n", pf, pst, pst + 1
                pend = 0; delann = 0; deldef = 0
            }
            /^\+\+\+ / { flush(); f = substr($0, 5); if (f == "/dev/null") f = ""; else sub(/^b\//, "", f); next }
            /^--- / { next }
            /^diff / { flush(); next }
            /^@@ / {
                flush()
                if (f != "" && match($0, /\+[0-9]+(,[0-9]+)?/)) {
                    t = substr($0, RSTART + 1, RLENGTH - 1); n = split(t, a, ",")
                    st = a[1] + 0; ln = (n > 1) ? a[2] + 0 : 1
                    if (ln > 0) printf "%s\t%d\t%d\n", f, st, st + ln - 1
                    else { pend = 1; pf = f; pst = (st < 1 ? 1 : st) }
                }
                next
            }
            /^-/ && pend {
                if (tolower($0) ~ /oracle[ \t]*:/) delann = 1
                if ($0 ~ /^-[ \t]*(async[ \t]+)?def[ \t]+test/) deldef = 1
            }
            END { flush() }' >> "$chg_master"
        git -C "$root" -c core.quotepath=off ls-files --others --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' u; do
            printf '%s\t1\t2147483647\n' "$u" >> "$chg_master"
        done
        diff_state="evaluated against ${base_ref:0:12} (+ untracked)"
    else
        echo "❌ ${GATE}: BLIND — base '${base_ref}' does not resolve" >&2; exit 2
    fi
fi

declare -A cnt=() hitsby=() newcnt=()
violations=0; new_viol=0; new_out=""
for f in "${files[@]}"; do
    rel="${f#"$root"/}"
    if [ "$excl_active" = 1 ] && [ -n "${excl_sha[$rel]+x}" ] && [ -z "${excl_voided[$rel]+x}" ]; then continue; fi
    : > "$chg_one"
    if [ -s "$chg_master" ]; then
        awk -F'\t' -v p="$rel" '$1 == p { print $2, $3 }' "$chg_master" > "$chg_one"
    fi
    hits="$(awk -v chg="$chg_one" "$AWK_SCRIPT" "$f" 2>/dev/null || true)"
    [ -n "$hits" ] || continue
    n=0; newn=0; text=""
    while IFS=$'\t' read -r lineno reason isnew defline; do
        [ -n "$lineno" ] || continue
        n=$(( n + 1 ))
        case "$reason" in
            UNKNOWN_STRATEGY:*)
                msg="❌ ${GATE}: FAIL — ${f}:${lineno}: oracle strategy '${reason#UNKNOWN_STRATEGY:}' is not in the closed 7-member set (§${ANCHOR})" ;;
            *)
                msg="❌ ${GATE}: FAIL — ${f}:${lineno}: no oracle-strategy annotation found (§${ANCHOR})" ;;
        esac
        text+="${msg}"$'\n'"   ${defline# }"$'\n'
        if [ "$isnew" = NEW ]; then
            newn=$(( newn + 1 ))
            new_viol=$(( new_viol + 1 ))
            new_out+="❌ ${GATE}: FAIL — ${f}:${lineno}: NEW or MODIFIED test function without a valid oracle annotation (§${ANCHOR}; untouched legacy tests are exempt)"$'\n'
        fi
    done <<< "$hits"
    cnt["$rel"]=$n
    newcnt["$rel"]=$newn
    hitsby["$rel"]="$text"
    violations=$(( violations + n ))
done

if [ "$strict" = 1 ]; then
    for rel in "${!cnt[@]}"; do printf '%s' "${hitsby[$rel]}"; done
    echo "======================================================================"
    if [ "$violations" -gt 0 ]; then
        echo "❌ ${GATE}: FAIL — ${violations} test function(s) with no valid closed-set oracle-strategy annotation (§${ANCHOR})"
        printf 'ORACLE-VERDICT\tFAIL\tmode=strict\tunannotated=%s\n' "$violations"
        exit 1
    fi
    echo "✅ ${GATE}: PASS — every scanned test function names a valid closed-set oracle strategy (§${ANCHOR})"
    printf 'ORACLE-VERDICT\tPASS\tmode=strict\tunannotated=0\n'
    exit 0
fi

# ── ratchet mode ───────────────────────────────────────────────────────────────────────────────────────
[ -n "$baseline" ] || baseline="$root/config/oracle_ratchet_baseline.txt"
declare -A base=()
have_base=0
if [ -f "$baseline" ]; then
    have_base=1
    while IFS=$'\t' read -r bp bc extra; do
        case "$bp" in ''|'#'*) continue ;; esac
        if [ -z "$bc" ] || [ -n "$extra" ] || ! [[ "$bc" =~ ^[0-9]+$ ]] || [ -n "${base[$bp]+x}" ]; then
            echo "⚠ ${GATE}: BLIND — malformed or duplicate baseline line in ${baseline}: '${bp}'" >&2
            printf 'ORACLE-VERDICT\tBLIND\tmode=ratchet\treason=baseline_malformed\n'
            exit 2
        fi
        base["$bp"]="$bc"
    done < "$baseline"
elif [ "$write_baseline" != 1 ]; then
    [ "$adopt_new" != 1 ] || { echo "❌ ${GATE}: --adopt-new-files needs an existing baseline (${baseline}); refused" >&2; printf 'ORACLE-VERDICT\tFAIL\tmode=adopt\treason=baseline_missing\n'; exit 2; }
    echo "⚠ ${GATE}: BLIND — ratchet baseline not found: ${baseline} (create it with --write-baseline, or pass --strict); a missing baseline is never a pass" >&2
    printf 'ORACLE-VERDICT\tBLIND\tmode=ratchet\treason=baseline_missing\n'
    exit 2
fi

if [ "$adopt_new" = 1 ]; then
    # Narrow adoption: ONLY files with no baseline entry gain one (at today's count). Existing entries are never
    # raised and never lowered; any existing entry whose live count exceeds it refuses the whole adoption.
    up=0; added=0; total_added=0
    declare -A newent=()
    for rel in "${!cnt[@]}"; do
        if [ -n "${base[$rel]+x}" ]; then
            if [ "${cnt[$rel]}" -gt "${base[$rel]}" ]; then up=$((up+1)); echo "❌ ${GATE}: adoption refused: existing entry ${rel} has ${cnt[$rel]} > ${base[$rel]}" >&2; fi
        elif [ "${newcnt[$rel]:-0}" -gt 0 ]; then
            up=$((up+1)); echo "❌ ${GATE}: adoption refused: ${rel} has ${newcnt[$rel]} NEW or MODIFIED unannotated test function(s) relative to ${base_ref}; annotate them (adoption is for legacy files only)" >&2
        elif [ "${cnt[$rel]}" -gt 0 ]; then
            newent["$rel"]="${cnt[$rel]}"; added=$((added+1)); total_added=$((total_added+cnt[$rel]))
        fi
    done
    if [ "$up" -gt 0 ]; then printf 'ORACLE-VERDICT\tFAIL\tmode=adopt\treason=existing_entry_would_raise_or_new_function_unannotated\n'; exit 1; fi
    if [ "$added" -eq 0 ]; then
        echo "✅ ${GATE}: nothing to adopt (no file without a baseline entry has unannotated tests)"
        printf 'ORACLE-VERDICT\tPASS\tmode=adopt\tfiles=0\tadded=0\tbase=%s\n' "${base_ref:0:12}"; exit 0
    fi
    tmp="$(mktemp "${baseline}.XXXXXX")"; : "${tmp:?}"
    {
        echo "# oracle_ratchet_baseline.txt -- CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (§11.4.245) monotone-decreasing ratchet."
        echo "# Format: <path relative to scan root><TAB><count of test functions lacking a valid oracle annotation>. May only DECREASE."
        echo "# Lower with: bash scripts/gates/cm_oracle_strategy_named_and_independent.sh --write-baseline"
        echo "# New files adopted only via: --adopt-new-files --reason \"<text>\" (audited in config/oracle_ratchet_adoptions.log)"
        { for rel in "${!base[@]}"; do printf '%s\t%s\n' "$rel" "${base[$rel]}"; done
          for rel in "${!newent[@]}"; do printf '%s\t%s\n' "$rel" "${newent[$rel]}"; done; } | LC_ALL=C sort
    } > "$tmp" && mv -f -- "$tmp" "$baseline"
    printf '%s\tfiles=%s\tadded=%s\treason=%s\tbase=%s\tlimit=submodule_contents_not_diffed\n' "$(date -u +%F)" "$added" "$total_added" "$adopt_reason" "$(git -C "$root" rev-parse --short=12 "$base_ref" 2>/dev/null || echo none)" \
        >> "$(dirname -- "$baseline")/oracle_ratchet_adoptions.log"
    echo "✅ ${GATE}: adopted ${added} new file(s), ${total_added} unannotated test function(s) into ${baseline}"
    printf 'ORACLE-VERDICT\tPASS\tmode=adopt\tfiles=%s\tadded=%s\n' "$added" "$total_added"
    exit 0
fi

if [ "$write_baseline" = 1 ]; then
    up=0
    for rel in "${!cnt[@]}"; do
        [ "$have_base" = 1 ] || break   # creating a fresh baseline: nothing to raise
        b="${base[$rel]:-0}"
        if [ "${cnt[$rel]}" -gt "$b" ]; then up=$((up+1)); echo "❌ ${GATE}: refuse to RAISE baseline: ${rel} has ${cnt[$rel]} > ${b}" >&2; fi
    done
    if [ "$up" -gt 0 ]; then printf 'ORACLE-VERDICT\tFAIL\tmode=write-baseline\n'; exit 1; fi
    mkdir -p "$(dirname -- "$baseline")"
    tmp="$(mktemp "${baseline}.XXXXXX")"; : "${tmp:?}"
    {
        echo "# oracle_ratchet_baseline.txt -- CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (§11.4.245) monotone-decreasing ratchet."
        echo "# Format: <path relative to scan root><TAB><count of test functions lacking a valid oracle annotation>. May only DECREASE."
        echo "# Lower with: bash scripts/gates/cm_oracle_strategy_named_and_independent.sh --write-baseline"
        for rel in "${!cnt[@]}"; do printf '%s\t%s\n' "$rel" "${cnt[$rel]}"; done | LC_ALL=C sort
    } > "$tmp" && mv -f -- "$tmp" "$baseline"
    echo "✅ ${GATE}: baseline written: ${baseline} (total ${violations})"
    printf 'ORACLE-VERDICT\tPASS\tmode=write-baseline\tunannotated=%s\n' "$violations"
    exit 0
fi

# rule 3 = the NEW/MODIFIED-function check; a non-git tree cannot evaluate it, so say so in the verdict (F4)
case "$diff_state" in SKIPPED*) rule3=skipped ;; *) rule3=evaluated ;; esac
over=0
for rel in "${!cnt[@]}"; do
    b="${base[$rel]:-0}"
    if [ "${cnt[$rel]}" -gt "$b" ]; then
        over=$(( over + 1 ))
        printf '%s' "${hitsby[$rel]}"
        echo "❌ ${GATE}: FAIL — ${rel}: ${cnt[$rel]} unannotated test function(s) exceeds baseline ${b} (the ratchet only decreases)"
    fi
done
printf '%s' "$new_out"
lower=0
for rel in "${!base[@]}"; do
    c="${cnt[$rel]:-0}"
    if [ "$c" -lt "${base[$rel]}" ]; then
        lower=$(( lower + 1 ))
        [ "$quiet" = 1 ] || echo "ℹ ${GATE}: ${rel}: ${c} < baseline ${base[$rel]} -- lower the baseline with --write-baseline"
    fi
done
# M4 (round 3): a baseline entry whose file no longer exists is STALE SLACK (e.g. after a rename + adopt the old
# path keeps its count). Reported always (not hidden by --quiet); --write-baseline prunes it.
stale=0
for rel in "${!base[@]}"; do
    if [ -z "${cnt[$rel]+x}" ] && [ ! -e "$root/$rel" ]; then
        stale=$(( stale + 1 ))
        echo "⚠ ${GATE}: stale baseline entry ${rel} (count ${base[$rel]}): the file no longer exists; prune it with --write-baseline"
    fi
done
echo "======================================================================"
echo "${GATE}: ratchet total=${violations} files_over_baseline=${over} new_or_modified_unannotated=${new_viol} lowerable=${lower} stale_entries=${stale} excluded=${excl_applied} new-function-check: ${diff_state}"
excl_tail="excluded=${excl_applied}	voided=${excl_voided_n}	exclusion_entries=${excl_n}"
if [ "$over" -gt 0 ] || [ "$new_viol" -gt 0 ] || [ "$excl_voided_n" -gt 0 ]; then
    echo "❌ ${GATE}: FAIL — ${over} file(s) above baseline, ${new_viol} new/modified unannotated test function(s), ${excl_voided_n} voided/over-ceiling exclusion problem(s) (§${ANCHOR})"
    printf 'ORACLE-VERDICT\tFAIL\tmode=ratchet\tover=%s\tnew=%s\t'"${excl_tail}"'\trule3=%s\tvia=%s\tbaseline=%s\toverrides=%s\tbase=%s\n' "$over" "$new_viol" "$rule3" "$nsb_via" "$baseline" "${CM_GATE_OVERRIDES_HONOURED:-none}" "${base_ref:0:12}"
    exit 1
fi
echo "✅ ${GATE}: PASS — no file above its baseline and no new/modified test function lacks an oracle annotation (§${ANCHOR})"
printf 'ORACLE-VERDICT\tPASS\tmode=ratchet\tunannotated=%s\t'"${excl_tail}"'\trule3=%s\tvia=%s\tbaseline=%s\toverrides=%s\tbase=%s\n' "$violations" "$rule3" "$nsb_via" "$baseline" "${CM_GATE_OVERRIDES_HONOURED:-none}" "${base_ref:0:12}"
exit 0
