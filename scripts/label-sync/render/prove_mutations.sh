#!/usr/bin/env bash
# scripts/label-sync/render/prove_mutations.sh
#
# Purpose : §1.1 paired-mutation proof for the label-sync RENDERERS. Copies the
#           render dir to a SCRATCH dir, applies ONE mutant per copy, runs
#           tests/test_render.sh against the copy and REQUIRES it to FAIL; a
#           control run of the unmutated copy REQUIRES it to pass. A surviving
#           mutant means the tests do not guard that behaviour.
#           Mutants: statusline_ignores_snapshot | title_not_refreshed_on_seq |
#           labelrun_swallows_exit | shell_records_full_command | title_keeps_control_chars |
#           statusline_drops_stale_marker | tmux_keeps_hash | labelrun_no_unregister
# Usage   : bash scripts/label-sync/render/prove_mutations.sh [--only <mutant>]
# Inputs  : none (reads the render dir next to this script).
# Outputs : one line per mutant KILLED / SURVIVED / NOT-APPLIED, then a summary.
# Exit    : 0 every mutant killed and control green | 1 a mutant survived or the
#           control failed | 2 environment (no jq/go, copy failure, a mutation
#           that did not change its file) — never a pass.
# Side-effects: temp dir under $TMPDIR (trap-removed); each test run uses its own
#           temp state dir. Never edits the real tree. Heavy (each run ~30-60 s):
#           run niced, one at a time (§12.6/§12.8).
# Deps    : bash, jq, go, sed, cmp, mktemp, timeout.
# Cross-refs: §1.1, §11.4.107(10), §11.4.201, §11.4.18, tests/test_render.sh.
# Classification: universal (§11.4.17).
set -uo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEST="$SELF/tests/test_render.sh"
command -v jq >/dev/null 2>&1 && command -v go >/dev/null 2>&1 || { echo "prove_mutations: jq/go missing" >&2; exit 2; }
ONLY=""; [ "${1:-}" = "--only" ] && ONLY="${2:-}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/render_mut.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

# name|file|sed-expression (must change the file)
MUTANTS=(
  'statusline_ignores_snapshot|statusline.sh|s|if \[ "\$status" = "ok" \] \&\& \[ -n "\$text" \]; then|if false; then|'
  'title_not_refreshed_on_seq|shell-integration.bash|s|\[ "\$s" != "\$__ls_seen_seq" \]|false|'
  'labelrun_swallows_exit|labelrun|s|^exit "\$rc"$|exit 0|'
  'shell_records_full_command|shell-hook.sh|s|^    text=""$|    :|;s|argv0=\${argv0}:h=\${h}"|argv0=${argv0}:h=${h}:cmd=${text}"|'
  'title_keeps_control_chars|lib.sh|s|local text="\${1//\[\[:cntrl:\]\]/}"|local text="$1"|'
  'statusline_drops_stale_marker|statusline.sh|s|if \$e.stale then " \[stale\]" elif|if false then " [stale]" elif|'
  'tmux_keeps_hash|tmux-status.sh|s|printf .%s\\n. "\${out//#/_}"|printf "%s\\n" "${out}"|'
  'labelrun_no_unregister|labelrun|s|^cleanup() { \[ "\$registered" = 1 \] \&\& .*$|cleanup() { return 0; }|'
)

run_tests() { RENDER_DIR="$1" nice -n 10 timeout 300 bash "$TEST" >"$2" 2>&1; }

fail=0; killed=0; total=0
CTL="$TMP/control"; mkdir -p "$CTL" && cp -R "$SELF/." "$CTL/" || exit 2
if run_tests "$CTL" "$TMP/control.log"; then echo "CONTROL   unmutated copy: tests PASS"
else echo "CONTROL   FAILED — unmutated tests do not pass"; grep -E '^FAIL' "$TMP/control.log" | head; exit 1; fi

for m in "${MUTANTS[@]}"; do
  name="${m%%|*}"; rest="${m#*|}"; file="${rest%%|*}"; expr="${rest#*|}"
  [ -z "$ONLY" ] || [ "$ONLY" = "$name" ] || continue
  total=$((total+1))
  d="$TMP/$name"; mkdir -p "$d" && cp -R "$SELF/." "$d/" || exit 2
  cp "$d/$file" "$d/$file.orig"
  sed -i "$expr" "$d/$file" || exit 2
  if cmp -s "$d/$file" "$d/$file.orig"; then echo "NOT-APPLIED $name — sed did not change $file"; exit 2; fi
  rm -f "$d/$file.orig"
  if run_tests "$d" "$TMP/$name.log"; then
    echo "SURVIVED  $name — tests still pass with the mutation"; fail=1
  else
    echo "KILLED    $name  ($(grep -c '^FAIL' "$TMP/$name.log") failing case(s): $(grep '^FAIL' "$TMP/$name.log" | head -2 | cut -c1-70 | tr '\n' ';'))"; killed=$((killed+1))
  fi
done
echo "SUMMARY   $killed/$total mutants killed"
[ "$fail" -eq 0 ] && [ "$killed" -eq "$total" ]
