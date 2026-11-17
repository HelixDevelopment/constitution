#!/usr/bin/env bash
# Round 13: put the evidence into docs/qa/con227_234_2026_11_11/round13 of a checkout and write mutants.md,
# README.md and SHA256SUMS. Mechanical only (§11.4.274): every number in README.md comes from fill13.py, which
# exits 1 (nothing written) when a file does not support a claim of the draft.
# usage: assemble13.sh REPO STAGE_DIR DRAFTS_DIR PRESCREEN_RESULT_TSV [--standing HARNESS_OUT STANDING_SUMMARY]
#   STAGE_DIR holds the evidence files and the oracle/ and tools/ directories; existing files of the same name in
#   round13 are refused unless --standing is given (then README.md, mutants.md and SHA256SUMS are rewritten and
#   the two standing files are added).
set -euo pipefail
repo=${1:?REPO}; stage=${2:?STAGE_DIR}; drafts=${3:?DRAFTS_DIR}; pre=${4:?PRESCREEN_RESULT_TSV}
standing=0; harness=-; ssum=
if [ "${5:-}" = "--standing" ]; then
  standing=1; harness=${6:?HARNESS_OUT}; ssum=${7:?STANDING_SUMMARY}
fi
r13=$repo/docs/qa/con227_234_2026_11_11/round13
[ -d "$r13" ] || { echo "no round13 directory: $r13" >&2; exit 2; }
if [ "$standing" -eq 0 ]; then
  for f in "$stage"/* "$stage"/.[!.]*; do
    [ -e "$f" ] || continue
    [ ! -e "$r13/$(basename "$f")" ] || { echo "refused: $(basename "$f") already in round13" >&2; exit 1; }
  done
  cp -a "$stage"/. "$r13"/
  cp -p "$pre" "$r13/mutants_targeted_r13.tsv"
else
  cp -p "$harness" "$r13/mutations_full_r13.txt"
  cp -p "$ssum" "$r13/standing_summary.txt"
fi
tools=$r13/tools
# mutants.md: the hand-written head plus the generated table (python -B: no bytecode in the evidence directory)
{ cat "$drafts/mutants_head.md"; printf '\n'
  python3 -I -B "$tools/make_mut_table_md.py" "$tools" \
    "$( [ "$standing" -eq 1 ] && printf '%s' "$r13/mutations_full_r13.txt" || printf '%s' - )" \
    "$r13/mutants_targeted_r13.tsv"; } > "$r13/mutants.md.new"
mv "$r13/mutants.md.new" "$r13/mutants.md"
# README.md and SHA256SUMS must exist when fill13 lists the directory
[ -e "$r13/README.md" ] || : > "$r13/README.md"
[ -e "$r13/SHA256SUMS" ] || : > "$r13/SHA256SUMS"
if [ "$standing" -eq 1 ]; then
  python3 -I -B "$tools/fill13.py" "$r13" "$drafts/README.md" "$r13/README.md.new" --standing
else
  python3 -I -B "$tools/fill13.py" "$r13" "$drafts/README.md" "$r13/README.md.new"
fi
mv "$r13/README.md.new" "$r13/README.md"
# the list is built outside round13: a temporary file inside it would be listed too
sums=$(mktemp)
( cd "$r13" && find . -type f ! -path ./SHA256SUMS -printf '%P\n' | LC_ALL=C sort | while IFS= read -r p; do
    sha256sum -- "$p"; done ) > "$sums"
mv "$sums" "$r13/SHA256SUMS"
chmod 0664 "$r13/SHA256SUMS"
( cd "$r13" && sha256sum --quiet -c SHA256SUMS ) && echo "ASSEMBLED $(wc -l < "$r13/SHA256SUMS") files"
