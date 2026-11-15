#!/usr/bin/env bash
# inventory.sh W BASE_ROOT NEW_ROOT — the class inventory of README section 5, written to W/final: shenum rows
# (shenum_{base,new}.tsv), scanner findings (sigscan_{base,new}.txt), the cross-check of the two instruments
# (xcheck_{base,new}.txt) and the counts table (inventory_counts.md). Exit 0 when both cross-checks PASS.
set -u
W="${1:?W}"; BASE="${2:?BASE_ROOT}"; NEW="${3:?NEW_ROOT}"; F="$W/final"
F6="scripts/install_constitution.sh scripts/update_constitution.sh scripts/install_cli_agent_plugins.sh scripts/install_action_prefix.sh scripts/portable_symlink_lib.sh scripts/lib/constitution_layout.sh"
rc=0
for side in base new; do
  if [ "$side" = base ]; then R="$BASE"; else R="$NEW"; fi
  # shellcheck disable=SC2086  # F6 is a deliberate word list
  (cd "$R" && python3 -I "$W/tools/sigscan.py" --allow-func hi_text_filter,hi_scrub,hi_mark_hash,hi_newest_tag $F6) >"$F/sigscan_$side.txt" 2>&1
  src=$?   # status read on its own line, before any other expansion (section 11.4.273(g))
  echo "$side $(git -C "$R" rev-parse --short HEAD) sigscan rc=$src findings=$(grep -c . "$F/sigscan_$side.txt")"
  # shellcheck disable=SC2086
  python3 -I "$W/tools/xcheck.py" "$W" "$R" $F6 >"$F/xcheck_$side.txt" 2>&1
  xrc=$?
  echo "$side xcheck rc=$xrc $(tail -1 "$F/xcheck_$side.txt")"
  tail -1 "$F/xcheck_$side.txt" | grep -qx 'XCHECK PASS' || rc=1
  : >"$F/shenum_$side.tsv"
  for f in $F6; do (cd "$R" && "$W/tools/shenum/shenum" "$f") >>"$F/shenum_$side.tsv"; done
done
python3 -I "$W/tools/inventory_counts.py" "$F" >"$F/inventory_counts.md"
cat "$F/inventory_counts.md"
exit "$rc"
