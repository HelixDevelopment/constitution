#!/usr/bin/env bash
# cm_constitution_index_fresh.sh -- CM-CONSTITUTION-INDEX-FRESH, the BUILD-path stage of the
# constitution index-regeneration seam (T048 round-4 review, R4-01).
#
# constitution_index.yaml records generated_from.source_sha256, and anchor_citations.py refuses an
# index whose checksum differs from Constitution.md (E_INDEX_SHA_MISMATCH, exit 4, BLIND). 59 of the
# last 60 commits that touched Constitution.md left the index stale. The commit path regenerates it
# (scripts/anchors/index_commit_seam.sh, run by the commit wrapper's cascade) and the post-update
# hook checks it on every pull; this gate is the pre-build backstop: it FAILs while the committed
# index or any groups/*.md differs from a fresh `constitution_generate.py check` against
# Constitution.md (a stale checksum is drift too, because the generated index records it).
#
# Usage: cm_constitution_index_fresh.sh [--root DIR] [--quiet]
#   --root   constitution root (default: two levels above this script)
# Exit: 0 fresh, 1 stale/drift (names the regenerate command), 2 BLIND (source/generator absent).
# Paired §1.1 mutation: cm_constitution_index_fresh_mutation_test.sh.
set -uo pipefail
GATE="CM-CONSTITUTION-INDEX-FRESH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "$GATE: --root needs a value" >&2; exit 2; }; ROOT=$2; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    *) echo "$GATE: unknown argument: $1" >&2; exit 2 ;;
  esac
done
SOURCE="$ROOT/Constitution.md"
GEN="$ROOT/scripts/anchors/constitution_generate.py"
command -v python3 >/dev/null 2>&1 || { echo "$GATE: BLIND -- python3 not usable" >&2; exit 2; }
[ -f "$SOURCE" ] || { echo "$GATE: BLIND -- $SOURCE is missing" >&2; exit 2; }
[ -f "$GEN" ] || { echo "$GATE: BLIND -- generator $GEN is missing" >&2; exit 2; }
rc=0
out=$(python3 "$GEN" check --source "$SOURCE" --groups-dir "$ROOT/groups" --index-out "$ROOT/constitution_index.yaml" 2>&1) || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "$GATE: FAIL -- constitution_index.yaml / groups/*.md do not match a fresh generation from $SOURCE (rc=$rc):"
  printf '%s\n' "$out" | head -n 20 | sed 's/^/  /'
  # V5 N3: name the generator's own `generate` (the command the commit seam prints). regenerate_if_stale.sh is
  # NOT a repair here: it compares only the checksum, so for a hand-edited groups/*.md it answers "fresh ...
  # nothing to do" while this gate stays red. `generate` rewrites the index AND every group from the source.
  echo "  regenerate in the constitution checkout and commit the result: python3 $GEN generate --source $SOURCE --groups-dir $ROOT/groups --index-out $ROOT/constitution_index.yaml"
  exit 1
fi
[ "$QUIET" -eq 1 ] || printf '%s\n' "$out"
echo "$GATE: PASS -- the index and groups match a fresh generation from Constitution.md"
exit 0
