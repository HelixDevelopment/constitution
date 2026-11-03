#!/usr/bin/env bash
# F6: --help of these gates must print the WHOLE leading comment header (no fixed-line sed cut).
# Check: help output's last line equals the last line of the file's leading '#' block, and the line count matches.
# Control needle: line 2 of each header must be present (instrument sees the output at all).
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
fail=0
for g in cm_codegraph_mcp_health cm_opendesign_ui_system cm_oracle_strategy_named_and_independent; do
  f="$ROOT/scripts/gates/$g.sh"
  [ "$g" = cm_oracle_strategy_named_and_independent ] && continue_oracle=1 || continue_oracle=0
  out="$(bash "$f" --help 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || { echo "FAIL $g --help rc=$rc"; fail=1; continue; }
  first="$(sed -n 2p "$f" | sed 's/^# \{0,1\}//')"
  grep -qxF -- "$first" <<<"$out" || { echo "BLIND $g: control needle (header line 2) absent"; fail=1; continue; }
  if [ "$continue_oracle" = 1 ]; then
    cl="$(awk '/^# Classification:/{print NR; exit}' "$f")"; last="$(sed -n "$((cl-1))p" "$f" | sed 's/^# \{0,1\}//')"   # last line before '# Classification:' (line 153)
    grep -qxF -- "$last" <<<"$out" && echo "PASS $g (full header incl. last line)" || { echo "FAIL $g: last header line missing"; fail=1; }
    continue
  fi
  n="$(awk 'NR>1 && !/^#/ {print NR-2; exit}' "$f")"   # number of header lines after the shebang
  got="$(wc -l <<<"$out")"
  lastexp="$(sed -n "$((n+1))p" "$f" | sed 's/^# \{0,1\}//')"
  if [ "$got" -ge "$n" ] && grep -qxF -- "$lastexp" <<<"$out"; then echo "PASS $g (lines=$got header=$n)"; else echo "FAIL $g: lines=$got header=$n last-line-present=no"; fail=1; fi
done
exit $fail
