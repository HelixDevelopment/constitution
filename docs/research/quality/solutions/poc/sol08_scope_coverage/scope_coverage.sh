#!/usr/bin/env bash
# SOL-08 — tracker scope-coverage gate.
# Corpus 3 measured: ~80% of a workspace's commit volume (≈11,000 of 13,704
# submodule commits, including its single largest repo at 2,790 commits) ran
# UNTRACKED beside an exemplary tracker that held 15 items for all of it.
# No existing anchor checks this axis — every anchor assumes the work IS in the
# tracker's scope. This gate declares the repo set independently (the M2/R3.1
# required-set pattern applied to REPOS) and measures per-repo linkage.
#
# Usage: scope_coverage.sh <workspace-dir> <manifest.tsv> <item-id-ere> <min-pct>
# Exit: 0 clean | 1 findings | 2 blind
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
WS="${1:?workspace}"; MF="${2:?manifest}"; IDRE="${3:?id-regex}"; MIN="${4:?min-pct}"
[ -d "$WS" ] || { echo "BLIND: workspace $WS absent"; exit 2; }
[ -r "$MF" ] || { echo "BLIND: manifest $MF unreadable"; exit 2; }

# Discover git repos (depth<=2). POSIX walk, no find -newermt class instruments.
repos=""
for d in "$WS"/* "$WS"/*/*; do
  [ -d "$d/.git" ] && repos="$repos $d"
done
n=0; for r in $repos; do n=$((n+1)); done
if [ "$n" -eq 0 ]; then
  echo "BLIND-OR-EMPTY: zero git repos discovered under $WS — nothing was measured, so nothing is proven"
  exit 2
fi

FINDINGS=0
for r in $repos; do
  rel="${r#"$WS"/}"
  row=$(awk -F'\t' -v p="$rel" '$1==p{print; exit}' "$MF")
  if [ -z "$row" ]; then
    echo "UNREGISTERED-REPO: $rel exists on disk but is absent from the scope manifest — its work is invisible to the tracker by construction"
    FINDINGS=$((FINDINGS+1)); continue
  fi
  cls=$(printf '%s' "$row" | cut -f2)
  case "$cls" in
    EXEMPT:*)
      echo "EXEMPT: $rel (${cls#EXEMPT:}) — enumerated honest gap, not measured";;
    TRACKED)
      total=$(git -C "$r" rev-list --no-merges --count HEAD 2>/dev/null || echo 0)
      if [ "${total:-0}" -eq 0 ]; then
        echo "EMPTY-REPO: $rel has zero commits — nothing to measure (reported, not passed silently)"
        continue
      fi
      refd=$(git -C "$r" log --no-merges --format='%s' | grep -cE -- "$IDRE" || true)
      pct=$(( refd * 100 / total ))
      if [ "$pct" -lt "$MIN" ]; then
        echo "LOW-COVERAGE: $rel — $refd/$total non-merge commits reference a tracked item (${pct}% < ${MIN}%)"
        FINDINGS=$((FINDINGS+1))
      else
        echo "COVERED: $rel — $refd/$total (${pct}%)"
      fi;;
    *)
      echo "MANIFEST-ERROR: $rel class '$cls' not in {TRACKED, EXEMPT:<reason>}"
      FINDINGS=$((FINDINGS+1));;
  esac
done

echo "SCOPE-COVERAGE: repos=$n findings=$FINDINGS min=${MIN}%"
[ "$FINDINGS" -eq 0 ]
