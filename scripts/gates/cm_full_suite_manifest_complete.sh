#!/usr/bin/env bash
# cm_full_suite_manifest_complete.sh — gate CM-FULL-SUITE-MANIFEST-COMPLETE
#
# Purpose
#   Proves the full-suite manifest (config/full_suite_manifest.tsv) of a repository's COMMITTED tree
#   (HEAD) still matches its test census: every census file has exactly one row, no row is stale,
#   the runner guide's census block is current and the excluded set is the reviewed one. It does
#   this by running the repository's OWN runner, `scripts/run_full_suite.sh --verify-manifest`,
#   never a second census of its own (§11.4.227: one detector, not two that can drift apart).
#
#   Why it exists (forensic, measured 2026-11-13): commit ff539dc8 added three census files
#   (scripts/sonarqube/tests/test_registry_login*.sh) without running
#   `--generate-manifest --write`; five later commits edited them and main bd0036bd ended
#   `--verify-manifest` with `RESULT: MANIFEST-MISMATCH (3 problem(s); nothing was run)`. The same
#   class was measured before as CON-086 (25 and 26 missing rows on main, 2026-11-05). The runner
#   already refused a full run; nothing refused the commit or the pull. This gate is that seam: it
#   is run by scripts/post_update_hook.sh (step 5b) against the constitution on every pull.
#
# What is judged: HEAD, never the working tree
#   The gate exports HEAD into a private temporary repository (objects borrowed read-only through
#   an alternates file, index from `git read-tree`, files from `git checkout-index`) and runs the
#   runner that HEAD carries against that export. The census and the manifest therefore come from
#   one snapshot: a fresh checkout of HEAD. Uncommitted edits, staged changes and untracked files
#   are NOT judged; when there are any, the gate says so in a NOTE line (it does not change the
#   verdict). Judge a change by committing it first.
#
# Verdict
#   0 PASS   the runner verified HEAD's manifest (`RESULT: MANIFEST-OK`, a census total above
#            zero) AND every member of the control needle below was seen.
#   1 FAIL   the committed tree is wrong: the runner reported a MANIFEST problem (a census file
#            without a row, a stale row, a stale guide census block, an excluded-set difference or
#            any other `MANIFEST:` line, all printed), or it refused HEAD's manifest itself
#            (`RESULT: MANIFEST-MISMATCH (manifest line N: duplicate path ...)`, a wrong column
#            count, an unreadable governance line, an unreadable excluded lock; the runner's own
#            words are printed), or HEAD carries the runner but no manifest. The fix command is printed.
#   2 BLIND  the instrument cannot be trusted or HEAD cannot be judged: HEAD has a manifest but no
#            runner, the root is not the top of a git work tree or has no commit, the export failed,
#            the runner ended with an unexpected exit code, without a RESULT line, or with a refusal
#            this gate does not know (for example `census instrument blind: ...`), the census total
#            is zero, or a member of the control needle was not seen. A zero-problem answer is
#            never reported from a blind instrument (§11.4.201(6), §11.4.273).
#   3 SKIP   nothing inspected: HEAD (or, with no usable commit, the directory) has neither the
#            runner nor a manifest.
#   64       usage error.
#   The runner is run with `bash`, so its executable bit does not matter; a runner that is absent
#   from HEAD while HEAD has a manifest is BLIND.
#
# Control needle (§11.4.273(f): every member of the FAIL set)
#   Before HEAD is judged, the SAME runner (HEAD's) is pointed at two throwaway git repositories.
#   The first has a tracked census file without a row, a row whose file does not exist, an
#   excluded row without an accepted lock and a stale guide census block; the runner MUST report
#   all four exact `MANIFEST:` lines and exit 3. The second has a duplicated manifest row; the
#   runner MUST refuse it with `RESULT: MANIFEST-MISMATCH (manifest line N: duplicate path ...)`
#   and this gate's own classifier MUST read that as a committed-manifest defect. A runner (or a
#   classifier) that would miss any member is caught here and the gate ends BLIND, never PASS.
#
# Honest boundary (§11.4.6)
#   It proves HEAD's manifest matches the census as HEAD's runner computes it. It does not run any
#   test, does not prove a row's class (entry, member, fixture, excluded) is the right one beyond
#   the runner's own rules, does not judge uncommitted work, and does not stop a commit by itself:
#   it reports at the pull seam. The export follows `.gitattributes` of HEAD but not the caller's
#   global or system git configuration (no user filters, no autocrlf) nor the caller's default
#   attributes and ignore files (XDG and system), so it is the committed bytes as the repository
#   itself declares them. The runner's git calls get the same private environment. The note about
#   uncommitted work reads the inspected repository as its owner configured it, so the caller's
#   ignore files may change that note (never the verdict).
#
# Usage
#   cm_full_suite_manifest_complete.sh [--root <repo-dir>] [--quiet]
#   cm_full_suite_manifest_complete.sh --help
#   --root defaults to the constitution directory that holds this script; it must be the top of a
#   git work tree (a submodule checkout or a linked worktree is fine).
#
# Side effects: a trap-cleaned temp dir and nothing else, apart from trace output the caller asks
#   for (GIT_TRACE* variables are not cleared; git writes those files where the caller says). Round 1 claimed "the inspected
#   repository is only read" and was wrong under an ambient GIT_DIR or GIT_INDEX_FILE (a pre-commit
#   hook receives them): its own `git init`/`git add`/`git commit` calls then wrote into whatever
#   repository those variables named. This gate therefore first clears the caller's
#   repository-locating git variables (list below), reads the inspected repository only through
#   `git rev-parse`, `git cat-file` and one `git status` with optional locks and fsmonitor off
#   (never a porcelain `git diff`, which rewrites the index of a repository with a stat-dirty
#   file even with --no-optional-locks), and builds every repository it writes to under its own
#   temp dir. That no repository outside the temp dir is written is checked by
#   tests/test_full_suite_manifest_gate_git_env.sh (a sentinel repository named by every one of
#   those variables stays byte-identical) and by the read-only cases of the paired mutation test
#   (the whole fixture, and the index of a fixture with a stat-dirty file).
# Dependencies: bash, git, python3 (through the runner), grep, sed, mktemp. Classification: universal (§11.4.17).
set -u -o pipefail
export LC_ALL=C

# Clear the caller's git variables that relocate a repository or change what git reads (F8).
# Derived from `git help git` (git 2.53.0), section "The Git Repository" (ten of its twelve: the two
# discovery limits GIT_CEILING_DIRECTORIES and GIT_DISCOVERY_ACROSS_FILESYSTEM are the caller's to
# keep, round 2 of the gitenv-class review, F1; every git call here names its repository with -C), plus the
# internal locators git exports to hooks (GIT_PREFIX, GIT_SHALLOW_FILE, GIT_GRAFT_FILE,
# GIT_QUARANTINE_PATH, GIT_INTERNAL_SUPER_PREFIX; the CL_GIT_SCRUB_VARS family of
# scripts/lib/constitution_layout.sh), the object-view variables (GIT_REPLACE_REF_BASE,
# GIT_NO_REPLACE_OBJECTS, GIT_ATTR_SOURCE), the template directory of `git init`, the config
# sources (GIT_CONFIG, GIT_CONFIG_GLOBAL, GIT_CONFIG_SYSTEM, GIT_CONFIG_NOSYSTEM,
# GIT_CONFIG_PARAMETERS and GIT_CONFIG_COUNT; without GIT_CONFIG_COUNT the GIT_CONFIG_KEY_<n> /
# GIT_CONFIG_VALUE_<n> pairs are ignored, `git help config`) and the global pathspec magic
# (GIT_*_PATHSPECS; every git call below passes --literal-pathspecs, which git refuses next to
# any of them).
_git_scrub=(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_INDEX_VERSION GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
    GIT_DEFAULT_HASH GIT_DEFAULT_REF_FORMAT GIT_PREFIX
    GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX
    GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_ATTR_SOURCE GIT_TEMPLATE_DIR
    GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_CONFIG_PARAMETERS
    GIT_CONFIG_COUNT GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS
    GIT_ICASE_PATHSPECS)
for _v in "${_git_scrub[@]}"; do unset "$_v"; done
unset _v

GATE="CM-FULL-SUITE-MANIFEST-COMPLETE"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
QUIET=0
RUNNER_REL="scripts/run_full_suite.sh"
MANIFEST_REL="config/full_suite_manifest.tsv"

usage() { echo "usage: ${0##*/} [--root <repo-dir>] [--quiet] | --help" >&2; exit 64; }
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"; exit 0 ;;
        *) usage ;;
    esac
done
say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
blind() { echo "$GATE: BLIND — $*"; exit 2; }
oneline() { tail -n "${2:-3}" "$1" 2>/dev/null | tr '\n' ' '; }

[ -d "$ROOT" ] || blind "root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd -P)" || blind "cannot enter the root"

# rgit: read-only git on the inspected repository. pgit <dir>: git on a private repository of this
# gate, with no global or system configuration (no user hooks, filters, templates or autocrlf) and
# none of the caller's DEFAULT git files either: GIT_CONFIG_GLOBAL=/dev/null does not stop git from
# reading $XDG_CONFIG_HOME/git/attributes and .../ignore (the defaults of core.attributesFile and
# core.excludesFile) or the system attributes file, so pgit, the export, the needle and the runner
# get an empty private XDG config home ($XDG0, set once the temp dir exists), GIT_ATTR_NOSYSTEM=1
# and both files pointed at /dev/null (review round 2, N1).
rgit() { git --literal-pathspecs --no-optional-locks -c core.fsmonitor=false -C "$ROOT" "$@"; }
pgit() { XDG_CONFIG_HOME="$XDG0" GIT_ATTR_NOSYSTEM=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git --literal-pathspecs -c core.hooksPath=/dev/null -c core.attributesFile=/dev/null -c core.excludesFile=/dev/null -C "$1" "${@:2}"; }
# penv: the same private environment for a git or runner process that pgit cannot wrap.
penv() { env XDG_CONFIG_HOME="$XDG0" GIT_ATTR_NOSYSTEM=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "$@"; }

# disk_skip <reason>: with no commit to read, SKIP when the directory has neither file, else BLIND.
disk_skip() {
    if [ ! -e "$ROOT/$RUNNER_REL" ] && [ ! -e "$ROOT/$MANIFEST_REL" ]; then
        echo "$GATE: SKIP — $ROOT has neither $RUNNER_REL nor $MANIFEST_REL (nothing inspected)"
        exit 3
    fi
    blind "$1"
}

command -v git >/dev/null 2>&1 || disk_skip "git not found"
TOP="$(rgit rev-parse --show-toplevel 2>&1)" || disk_skip "$ROOT is not a git work tree: $(printf '%s' "$TOP" | tail -n 1)"
TOP="$(cd "$TOP" 2>/dev/null && pwd -P)" || disk_skip "cannot resolve the top of the work tree of $ROOT"
[ "$TOP" = "$ROOT" ] || disk_skip "$ROOT is not the top of its git work tree ($TOP is); point --root at the repository's top"
COMMIT="$(rgit rev-parse --verify -q 'HEAD^{commit}')" || disk_skip "$ROOT has no commit (HEAD is unborn): there is no committed tree to judge"
SHORT="${COMMIT:0:12}"

# presence in HEAD: <rel> -> blob | other | absent
in_head() {
    local t
    t="$(rgit cat-file -t "$COMMIT:$1" 2>/dev/null)" || { echo absent; return; }
    [ "$t" = blob ] && echo blob || echo other
}
r_in="$(in_head "$RUNNER_REL")"; m_in="$(in_head "$MANIFEST_REL")"
if [ "$r_in" = absent ] && [ "$m_in" = absent ]; then
    echo "$GATE: SKIP — HEAD $SHORT of $ROOT has neither $RUNNER_REL nor $MANIFEST_REL (nothing inspected)"
    exit 3
fi
[ "$r_in" = blob ] || blind "HEAD $SHORT has $MANIFEST_REL but no runner file $RUNNER_REL ($r_in): the census cannot be checked"
if [ "$m_in" != blob ]; then
    echo "$GATE: FAIL — HEAD $SHORT of $ROOT carries $RUNNER_REL but no $MANIFEST_REL ($m_in): the runner refuses every full run."
    echo "  fix: bash scripts/run_full_suite.sh --generate-manifest --write && bash scripts/run_full_suite.sh --sync-guide,"
    echo "       review the rows and commit them"
    exit 1
fi

TMP="$(mktemp -d)" || blind "mktemp failed"
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [ -n "${TMP:-}" ] && [ -d "${TMP:?}" ] && rm -rf -- "${TMP:?}"; }
trap cleanup EXIT
XDG0="$TMP/xdg"
mkdir "$XDG0" || blind "cannot create the private XDG config home"

# note_uncommitted: say (never judge) that the working tree or index differs from HEAD. It reads
# ONE `git status` with optional locks off. It must not use a porcelain `git diff` against the
# work tree: that refreshes, i.e. rewrites, the inspected repository's index whenever a tracked
# file is stat-dirty, even with --no-optional-locks (measured with git 2.53.0); `git status`
# honours --no-optional-locks and writes nothing. Format: `XY <path>\0`, plus `<origin>\0` after
# a rename or copy; X is index vs HEAD, Y is work tree vs index, `??` is untracked.
note_uncommitted() {
    local staged=no unstaged=no untracked=no rec skip=0 x y
    if ! rgit status --porcelain=v1 -z --untracked-files=normal --ignore-submodules=dirty >"$TMP/status.z" 2>/dev/null; then
        staged=unknown; unstaged=unknown; untracked=unknown
    else
        while IFS= read -r -d '' rec; do
            if [ "$skip" = 1 ]; then skip=0; continue; fi
            x="${rec:0:1}"; y="${rec:1:1}"
            case "$x$y" in
                '??') untracked=yes; continue ;;
                '!!') continue ;;
            esac
            [ "$x" = ' ' ] || staged=yes
            [ "$y" = ' ' ] || unstaged=yes
            case "$x" in R|C) skip=1 ;; esac
        done <"$TMP/status.z"
    fi
    if [ "$staged$unstaged$untracked" != nonono ]; then
        say "$GATE: NOTE: the work tree differs from HEAD $SHORT (staged: $staged, unstaged: $unstaged, untracked: $untracked); those changes were NOT judged — commit them to have them judged"
    fi
}

# ---- export HEAD -------------------------------------------------------------------------------
S="$TMP/head"
FMT="$(rgit rev-parse --show-object-format 2>/dev/null)" || FMT=sha1
OBJ="$(rgit rev-parse --path-format=absolute --git-path objects 2>"$TMP/objpath.err")" || blind "cannot locate the object directory of $ROOT: $(oneline "$TMP/objpath.err" 1)"
[ -d "$OBJ" ] || blind "object directory of $ROOT is not a directory: $OBJ"
penv git init -q --template= --object-format="$FMT" "$S" >"$TMP/export.log" 2>&1 || blind "export: git init failed: $(oneline "$TMP/export.log")"
printf '%s\n' "$OBJ" >"$S/.git/objects/info/alternates" || blind "export: cannot write the alternates file"
{ pgit "$S" read-tree "$COMMIT^{tree}" && pgit "$S" checkout-index -a -f && pgit "$S" update-ref HEAD "$COMMIT"; } >>"$TMP/export.log" 2>&1 \
    || blind "export of HEAD $SHORT failed: $(oneline "$TMP/export.log")"
RUNNER="$S/$RUNNER_REL"
[ -f "$RUNNER" ] || blind "export of HEAD $SHORT has no runner file $RUNNER_REL"

# runrun <root> <log> [args]: run HEAD's runner against <root>; sets RC.
runrun() {
    local r="$1" log="$2"; shift 2
    [ $# -gt 0 ] || set -- --verify-manifest
    RC=0
    penv TMPDIR="$TMP" bash "$RUNNER" --root "$r" "$@" >"$log" 2>&1 || RC=$?
}
# fatal_of <log>: the runner's refusal text inside `RESULT: MANIFEST-MISMATCH (<text>)`, if any.
fatal_of() { sed -n 's/^RESULT: MANIFEST-MISMATCH (\(.*\))$/\1/p' "$1" | tail -n 1; }
# classify_fatal <text>: "fail" when the refusal is about the committed manifest or excluded lock,
# "blind" for every other refusal (an instrument failure, or one this gate does not know).
classify_fatal() {
    case "$1" in
        "manifest missing: "*|"manifest: "*|"excluded lock: "*) echo fail ;;
        "manifest line "*)
            local n="${1#manifest line }"; n="${n%%:*}"
            case "$n" in ''|*[!0-9]*) echo blind ;; *) echo fail ;; esac ;;
        *) echo blind ;;
    esac
}

# ---- control needle: every member of the FAIL set must be seen ---------------------------------
N="$TMP/needle"
mkdir -p "$N/tests/a" "$N/docs/guides" || blind "cannot build the needle fixture"
penv git init -q --template= "$N" >/dev/null 2>&1 || blind "git init failed for the needle fixture"
for _n in listed excluded; do printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' >"$N/tests/a/test_needle_$_n.sh"; done
pgit "$N" add -A >/dev/null 2>&1 || blind "git add failed in the needle fixture"
runrun "$N" "$TMP/needle_gen.log" --generate-manifest --write
[ "$RC" = 0 ] || blind "control needle: the runner could not generate a manifest for a two-file fixture (rc $RC): $(oneline "$TMP/needle_gen.log")"
cp -a "$N" "$TMP/needle_dup" || blind "cannot copy the needle fixture"
# needle: one row turned excluded (no lock is accepted) and one row added for a file that does not
# exist; needle_dup: the listed file's row written twice.
python3 -I - "$N/$MANIFEST_REL" "$TMP/needle_dup/$MANIFEST_REL" <<'PY' || blind "control needle: the generated manifest does not have the expected rows"
import sys
listed = "tests/a/test_needle_listed.sh\tsh\tentry\tdefault\tbash\t-\tauto\n"
excl = "tests/a/test_needle_excluded.sh\tsh\tentry\tdefault\tbash\t-\tauto\n"
s = open(sys.argv[1], encoding="utf-8").read()
if s.count(listed) != 1 or s.count(excl) != 1:
    sys.exit(1)
d = s + listed
s = s.replace(excl, "tests/a/test_needle_excluded.sh\tsh\texcluded\t-\t-\t-\toverride: reason: tool: control needle\n")
s += "tests/a/test_needle_stale.sh\tsh\tentry\tdefault\tbash\t-\tauto\n"
open(sys.argv[1], "w", encoding="utf-8").write(s)
open(sys.argv[2], "w", encoding="utf-8").write(d)
PY
printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' >"$N/tests/a/test_needle_unlisted.sh"
printf '# guide\n\n<!-- census:begin -->\nneedle: not the census line\n<!-- census:end -->\n' >"$N/docs/guides/full_suite_runner_guide.md"
pgit "$N" add -A >/dev/null 2>&1 || blind "git add failed in the needle fixture"
runrun "$N" "$TMP/needle_verify.log"
[ "$RC" = 3 ] || blind "control needle: the runner exited $RC on the needle fixture (want 3): $(oneline "$TMP/needle_verify.log")"
for _want in \
    "MANIFEST: census file without manifest row: tests/a/test_needle_unlisted.sh" \
    "MANIFEST: stale manifest row (no such test file / module): tests/a/test_needle_stale.sh" \
    "MANIFEST: excluded set (1 row(s)) is not accepted: $N/config/full_suite_excluded.lock is absent; review the rows and run --verify-manifest --accept-excluded-change <reviewer>" \
    "MANIFEST: docs/guides/full_suite_runner_guide.md: census block is stale (run --sync-guide)"; do
    grep -qxF -- "$_want" "$TMP/needle_verify.log" || blind "control needle: the runner did not report '${_want#MANIFEST: }'; it cannot be trusted to see that problem: $(oneline "$TMP/needle_verify.log")"
done
grep -q '^RESULT: MANIFEST-MISMATCH ' "$TMP/needle_verify.log" || blind "control needle: no MANIFEST-MISMATCH result line on the needle fixture"
runrun "$TMP/needle_dup" "$TMP/needle_dup.log"
_fm="$(fatal_of "$TMP/needle_dup.log")"
case "$RC:$_fm" in
    "3:manifest line "*": duplicate path tests/a/test_needle_listed.sh") : ;;
    *) blind "control needle: the runner did not refuse a duplicated manifest row (rc $RC, want 3 and 'manifest line N: duplicate path ...'): $(oneline "$TMP/needle_dup.log")" ;;
esac
[ "$(classify_fatal "$_fm")" = fail ] || blind "control needle: this gate's classifier did not read a duplicated row as a committed-manifest defect"
say "$GATE: control needle seen (missing row, stale row, unaccepted excluded set, stale guide block, duplicated row)"

# ---- HEAD --------------------------------------------------------------------------------------
LOG="$TMP/verify.log"
runrun "$S" "$LOG"
note_uncommitted
total="$(sed -n 's/^census: .* total=\([0-9][0-9]*\)$/\1/p' "$LOG" | tail -n 1)"
case "$RC" in
    0)
        grep -qxF 'RESULT: MANIFEST-OK' "$LOG" || blind "runner exit 0 without 'RESULT: MANIFEST-OK': $(oneline "$LOG")"
        [ -n "$total" ] && [ "$total" -gt 0 ] || blind "runner reported MANIFEST-OK on a census total of '${total:-none}' (a blind census is not a complete manifest)"
        grep '^NOTE: ' "$LOG" | while IFS= read -r l; do say "$GATE: ${l//"$S/"/}"; done
        echo "$GATE: PASS — $ROOT (HEAD $SHORT): manifest matches the census ($total census file(s))"
        exit 0 ;;
    3) : ;;
    *) blind "runner exit $RC on HEAD $SHORT (want 0 or 3): $(oneline "$LOG" 5)" ;;
esac
grep -q '^RESULT: MANIFEST-MISMATCH ' "$LOG" || blind "runner exit 3 without a MANIFEST-MISMATCH result: $(oneline "$LOG" 5)"

fix_text() {
    echo "  fix: bash scripts/run_full_suite.sh --generate-manifest --write && bash scripts/run_full_suite.sh --sync-guide,"
    echo "       review the new rows, commit them with the test files; a duplicated row or a row with the wrong column"
    echo "       count is fixed by hand in $MANIFEST_REL; an excluded-set change needs the operator's"
    echo "       --verify-manifest --accept-excluded-change <rostered id>"
}
problems=0
while IFS= read -r line; do
    problems=$((problems + 1))
    p="${line#MANIFEST: }"
    echo "$GATE: FAIL — ${p//"$S/"/}"
done < <(grep '^MANIFEST: ' "$LOG")
if [ "$problems" -gt 0 ]; then
    echo "$GATE: FAIL — $ROOT (HEAD $SHORT): $problems manifest problem(s) in the committed tree."
    fix_text
    exit 1
fi
fatal="$(fatal_of "$LOG")"
fatal="${fatal//"$S/"/}"
[ -n "$fatal" ] || blind "runner reported MANIFEST-MISMATCH on HEAD $SHORT without a MANIFEST: line or a readable reason: $(oneline "$LOG" 5)"
if [ "$(classify_fatal "$fatal")" = fail ]; then
    echo "$GATE: FAIL — $ROOT (HEAD $SHORT): the runner refused the committed manifest: RESULT: MANIFEST-MISMATCH ($fatal)"
    fix_text
    exit 1
fi
blind "the runner refused HEAD $SHORT for a reason that is not a manifest defect: RESULT: MANIFEST-MISMATCH ($fatal)"
