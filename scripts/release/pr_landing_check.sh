#!/usr/bin/env bash
# pr_landing_check.sh - derived-file drift checks for the pull-request landing path (CON-443).
#
# Repository path: scripts/release/pr_landing_check.sh
# Test:            tests/release/test_pr_landing_check.sh
# Library:         scripts/release/lib/landing_drift_checks.sh (the same check list and runner that
#                  land_vehicle.sh publish step 6b uses, so both landing paths run the same checks)
#
# WHAT IT DOES
#   A section 11.4.297 pull-request merge lands on main on the forge and never passes through
#   land_vehicle.sh publish, so before 2026-11-16 nothing ran the drift checks (README badge row,
#   env-read allowlist) on that path and a PR could land a stale derived file (the CON-144 /
#   CON-379 symptom class). The merging agent runs this script on the reviewed PR head BEFORE it
#   merges; a non-zero exit means: do not merge.
#     (1) resolve --base (the main the PR merges into) and --head (the reviewed PR head) to commits
#         in --repo; neither is changed;
#     (2) build the landing candidate in a private temporary clone (objects shared read-only through
#         alternates; the --repo repository gets no ref, no object and no config change):
#         a fast-forward when base is an ancestor of head (candidate = head), otherwise the merge
#         commit the forge would make (`git merge-tree --write-tree`, parents base and head); a
#         merge conflict refuses (exit 1); --form ff-only refuses a non-fast-forward;
#     (3) check the candidate out (detached, hooks off) and run every required drift check with
#         --root <temporary clone> (rules in the library header); results go to
#         <evidence-dir>/drift_checks.tsv, the candidate (form, sha, tree, parents) to
#         <evidence-dir>/candidate.txt;
#     (4) remove the temporary clone.
#
# Usage: pr_landing_check.sh --repo DIR --base REV --head REV --evidence-dir DIR [--form auto|ff-only|merge-commit]
#   --form auto (default): fast-forward when possible, else a merge commit; merge-commit always
#   builds a merge commit when base is not head (the forge's "create a merge commit" button).
# Output: progress lines "pr_landing_check: ..." and a last line "RESULT: PASS|FAIL|BLIND".
# Exit: 0 PASS (every required check passed) | 1 FAIL (a check failed, timed out or is missing, a
#   merge conflict, a non-fast-forward under ff-only, the candidate moved or the tree changed) |
#   2 BLIND / usage (a revision does not resolve, no repository, the library is missing).
# Honest boundary (section 11.4.6): the merge candidate is built with git's ort merge; a forge that
# merges with another engine can produce a different tree for the same clean merge (UNCONFIRMED for
# GitHub). The script checks; it does not merge, push or talk to any forge. A merge made without
# running it is not refused by anything in this repository (no CI, section 11.4.156).
set +x +v
set -euo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
unset CDPATH
umask 077
export LC_ALL=C

log() { printf 'pr_landing_check: %s\n' "$*"; }
end() { printf 'RESULT: %s\n' "$1"; exit "$2"; }
blind() { log "ERROR: $*"; end BLIND 2; }
fail() { log "FAIL: $*"; end FAIL 1; }
usage() { awk '/^set \+x \+v/ {exit} NR > 1 {print}' "${BASH_SOURCE[0]}"; exit 0; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="" BASE="" HEAD_REV="" EVIDENCE_DIR="" FORM=auto
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --repo|--base|--head|--evidence-dir|--form)
      [ $# -ge 2 ] && [ -n "$2" ] || blind "option $1 needs a value"
      case "$1" in
        --repo) REPO=$2 ;; --base) BASE=$2 ;; --head) HEAD_REV=$2 ;;
        --evidence-dir) EVIDENCE_DIR=$2 ;; --form) FORM=$2 ;;
      esac
      shift 2 ;;
    *) blind "unknown argument: $1" ;;
  esac
done
[ -n "$REPO" ] && [ -n "$BASE" ] && [ -n "$HEAD_REV" ] && [ -n "$EVIDENCE_DIR" ] \
  || blind "--repo, --base, --head and --evidence-dir are required"
case "$FORM" in auto|ff-only|merge-commit) ;; *) blind "--form must be auto, ff-only or merge-commit" ;; esac
case "$BASE$HEAD_REV" in -*|*[[:space:]]*) blind "a revision must not start with '-' or hold white space" ;; esac
[ -f "$HERE/lib/landing_drift_checks.sh" ] || blind "drift-check library not found: $HERE/lib/landing_drift_checks.sh"
# shellcheck source=scripts/release/lib/landing_drift_checks.sh
. "$HERE/lib/landing_drift_checks.sh" || blind "cannot load the drift-check library"
# shellcheck source=scripts/lib/safe_rm.sh
. "$HERE/../lib/safe_rm.sh" || blind "cannot load scripts/lib/safe_rm.sh"

REPO=$(cd "$REPO" 2>/dev/null && pwd -P) || blind "--repo is not a directory"
GITDIR=$(git -C "$REPO" rev-parse --absolute-git-dir 2>/dev/null) || blind "--repo is not a git repository: $REPO"
rgit() { git --no-pager --no-replace-objects --git-dir="$GITDIR" "$@" 9>&-; }
base=$(rgit rev-parse -q --verify "$BASE^{commit}") || blind "--base does not resolve to a commit: $BASE"
head=$(rgit rev-parse -q --verify "$HEAD_REV^{commit}") || blind "--head does not resolve to a commit: $HEAD_REV"
mkdir -p "$EVIDENCE_DIR" || blind "cannot create the evidence directory"
EVIDENCE_DIR=$(cd "$EVIDENCE_DIR" && pwd -P)

W=$(mktemp -d "${TMPDIR:-/tmp}/prlc.XXXXXX") || blind "cannot create a temporary directory"
: "${W:?}"
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { [ -n "${W:-}" ] && [ -d "$W" ] && safe_rm_rf "$W"; }
trap cleanup EXIT
CL="$W/c"
# a private clone: no checkout yet, objects through alternates (read-only), no hardlinks
git -c core.hooksPath=/dev/null clone -q --shared --no-checkout -- "$REPO" "$CL" 9>&- \
  || blind "cannot create the temporary clone"
g() {
  git --no-pager --no-replace-objects -C "$CL" --git-dir="$CL/.git" --work-tree="$CL" \
    -c core.hooksPath=/dev/null -c advice.detachedHead=false "$@" 9>&-
}
{ g cat-file -e "$base^{commit}" && g cat-file -e "$head^{commit}"; } || blind "the temporary clone cannot read base and head"

form=""
if [ "$base" = "$head" ] || g merge-base --is-ancestor "$base" "$head"; then
  if [ "$FORM" = merge-commit ] && [ "$base" != "$head" ]; then form=merge-commit; else form=fast-forward; fi
else
  [ "$FORM" != ff-only ] || fail "base $base is not an ancestor of head $head (--form ff-only)"
  form=merge-commit
fi
if [ "$form" = fast-forward ]; then
  cand=$head
else
  mt=0; tree=$(g merge-tree --write-tree --no-messages "$base" "$head" 2>/dev/null) || mt=$?
  [ "$mt" -eq 0 ] || { [ "$mt" -eq 1 ] && fail "merge conflict between base $base and head $head"; blind "git merge-tree failed (status $mt)"; }
  tree=${tree%%$'\n'*}
  cand=$(GIT_AUTHOR_NAME=pr_landing_check GIT_AUTHOR_EMAIL=pr-landing-check@invalid \
         GIT_COMMITTER_NAME=pr_landing_check GIT_COMMITTER_EMAIL=pr-landing-check@invalid \
         g commit-tree "$tree" -p "$base" -p "$head" -m "pr_landing_check candidate") \
    || blind "cannot build the merge candidate"
fi
g checkout -q --detach "$cand" || blind "cannot check out the candidate $cand"
printf 'base\t%s\nhead\t%s\nform\t%s\ncandidate\t%s\ncandidate_tree\t%s\ncandidate_parents\t%s\n' \
  "$base" "$head" "$form" "$cand" "$(g rev-parse "$cand^{tree}")" "$(g log -1 --format=%P "$cand")" > "$EVIDENCE_DIR/candidate.txt"
log "base $base, head $head, form $form, candidate $cand"

if LDC_GIT=g LDC_LOG=log LDC_REF=HEAD ldc_run "$CL" "$base" "$cand" "$EVIDENCE_DIR"; then
  log "every required drift check passed (see $EVIDENCE_DIR/drift_checks.tsv)"
  end PASS 0
fi
log "FAIL: derived-file drift checks failed; do not merge (see $EVIDENCE_DIR/drift_checks.tsv)"
end FAIL 1
