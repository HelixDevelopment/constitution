#!/usr/bin/env bash
# index_commit_seam.sh -- the COMMIT-path stage of the constitution index-regeneration seam (R4-01).
#
# Why it exists: constitution_index.yaml records generated_from.source_sha256, the sha256 of the
# Constitution.md it was generated from, and anchor_citations.py refuses a stale index
# (E_INDEX_SHA_MISMATCH, exit 4, BLIND). 59 of the last 60 commits that touched Constitution.md left
# the index stale because nothing on the amendment path regenerated it. regenerate_if_stale.sh does
# the regeneration; THIS script is the stage a commit wrapper runs on the constitution work tree
# AFTER it has staged the change set and BEFORE `git commit` (commit_all.sh's submodule cascade calls
# it), so an amendment cannot be committed together with a stale index.
#
# What it does:
#   1. BLIND (exit 4) unless --root is a git work tree whose Constitution.md is tracked;
#   2. when the working-tree index is stale against the working-tree Constitution.md, runs
#      regenerate_if_stale.sh (which rewrites constitution_index.yaml + groups/*.md atomically);
#   2b. runs the generator's own drift check (`constitution_generate.py check`, the SAME check the
#      CM-CONSTITUTION-INDEX-FRESH gate runs; ~0.03 s measured on the real tree) on the working-tree
#      outputs, because regenerate_if_stale.sh --check compares ONLY the checksum, so a hand-edited
#      groups/*.md next to a fresh checksum would otherwise be staged as if generated; drift -> exit 3,
#      nothing staged;
#   3. checks the pair that WILL be committed: sha256 of the STAGED Constitution.md must equal the
#      working-tree index's source_sha256. When it does not (e.g. Constitution.md has unstaged
#      edits, so the commit would carry the old text with an index for the new one) it stages
#      NOTHING and exits 3, naming the disagreement;
#   4. stages ONLY constitution_index.yaml and groups/*.md (never anything else) and re-verifies the
#      staged pair from the index (`git show :...`), exit 3 if it still disagrees.
#   Group sibling exports (.html/.pdf/.docx) are not produced here (a separate exporter owns them).
#
# Usage: index_commit_seam.sh --root DIR
# Exit codes: 0 fresh, or regenerated and staged; 2 usage; 3 the staged pair disagrees or the
# regeneration failed (nothing the caller should commit); 4 BLIND.
# Test-only: INDEX_COMMIT_SEAM_REGEN / INDEX_COMMIT_SEAM_GEN override the paths of regenerate_if_stale.sh / constitution_generate.py.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGEN="${INDEX_COMMIT_SEAM_REGEN:-$HERE/regenerate_if_stale.sh}"
GEN="${INDEX_COMMIT_SEAM_GEN:-$HERE/constitution_generate.py}"
ROOT=""
GROUP_PATHSPEC=':(glob)groups/*.md'

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "index_commit_seam: --root needs a value" >&2; exit 2; }; ROOT=$2; shift 2 ;;
    -h|--help) sed -n '2,34p' "$0" >&2; exit 2 ;;
    *) echo "index_commit_seam: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || { echo "index_commit_seam: --root is required" >&2; exit 2; }

for dep in git sha256sum python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "index_commit_seam: BLIND -- required dependency '$dep' not usable" >&2; exit 4; }
done
[ -f "$REGEN" ] || { echo "index_commit_seam: BLIND -- $REGEN is missing" >&2; exit 4; }
if [ "$(git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  echo "index_commit_seam: BLIND -- $ROOT is not a git work tree" >&2; exit 4
fi
TOP=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) || TOP=""
if [ -z "$TOP" ] || [ "$(cd "$ROOT" && pwd -P)" != "$(cd "$TOP" && pwd -P)" ]; then
  echo "index_commit_seam: BLIND -- $ROOT is not the top of its own work tree (pass the constitution checkout itself)" >&2; exit 4
fi
if ! git -C "$ROOT" cat-file -e :Constitution.md 2>/dev/null; then
  echo "index_commit_seam: BLIND -- Constitution.md is not tracked in $ROOT" >&2; exit 4
fi

# generated_from.source_sha256 of an index given on stdin (empty when absent); same bounded block
# rule as regenerate_if_stale.sh and anchor_citations.py.
index_sha_of() {
  python3 -c '
import re, sys
inside = False
for line in sys.stdin.read().split("\n"):
    if re.match(r"^generated_from:\s*$", line):
        inside = True
        continue
    if inside:
        if not line.startswith((" ", "\t")):
            break
        m = re.match(r"^\s+source_sha256:\s*'"'"'?([0-9a-f]{64})'"'"'?\s*$", line)
        if m:
            print(m.group(1))
            break
'
}

if ! bash "$REGEN" --root "$ROOT" --check >/dev/null 2>&1; then
  out=$(bash "$REGEN" --root "$ROOT" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "index_commit_seam: regenerate_if_stale.sh failed (rc=$rc); do not commit:" >&2
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    exit 3
  fi
  printf '%s\n' "$out"
  regenerated=1
else
  regenerated=0
fi

# Drift check beyond the checksum: the committed outputs must equal a fresh generation from the working-tree
# Constitution.md (a hand-edited groups/*.md with a fresh checksum passes regenerate_if_stale.sh --check).
[ -f "$GEN" ] || { echo "index_commit_seam: BLIND -- generator $GEN is missing" >&2; exit 4; }
drift_rc=0
drift_out=$(python3 "$GEN" check --source "$ROOT/Constitution.md" --groups-dir "$ROOT/groups" --index-out "$ROOT/constitution_index.yaml" 2>&1) || drift_rc=$?
if [ "$drift_rc" -ne 0 ]; then
  echo "index_commit_seam: the index/groups DRIFT from a fresh generation of Constitution.md (generator check rc=$drift_rc) although the checksum matches -- a generated file was hand-edited; nothing was staged. Regenerate: python3 $GEN generate --source $ROOT/Constitution.md --groups-dir $ROOT/groups --index-out $ROOT/constitution_index.yaml" >&2
  printf '%s\n' "$drift_out" | head -n 10 | sed 's/^/  /' >&2
  exit 3
fi

staged_src=$(git -C "$ROOT" show :Constitution.md | sha256sum | cut -c1-64)
wt_idx=$(index_sha_of < "$ROOT/constitution_index.yaml")
if [ "$staged_src" != "$wt_idx" ]; then
  echo "index_commit_seam: the STAGED Constitution.md (sha256 $staged_src) and the index (source_sha256 ${wt_idx:-<absent>}) disagree -- Constitution.md has changes that are not staged. Stage it (or revert the unstaged edit) and run again; nothing was staged." >&2
  exit 3
fi
if ! git -C "$ROOT" add -A -- constitution_index.yaml "${GROUP_PATHSPEC}"; then
  echo "index_commit_seam: git add of the index/groups failed; do not commit" >&2; exit 3
fi
staged_idx=$(git -C "$ROOT" show :constitution_index.yaml 2>/dev/null | index_sha_of)
if [ "$staged_idx" != "$staged_src" ]; then
  echo "index_commit_seam: after staging, the staged index (source_sha256 ${staged_idx:-<absent>}) still disagrees with the staged Constitution.md ($staged_src); do not commit" >&2
  exit 3
fi
if [ "$regenerated" -eq 1 ]; then
  echo "staged: constitution_index.yaml and groups/*.md regenerated for Constitution.md $staged_src (group .html/.pdf/.docx exports are NOT regenerated here)"
else
  echo "fresh: the staged index matches the staged Constitution.md ($staged_src)"
fi
exit 0
