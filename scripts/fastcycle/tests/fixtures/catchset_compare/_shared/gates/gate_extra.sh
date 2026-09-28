#!/bin/sh
# id: g_extra
# Purpose: toy Gate for the T050 catch-set-comparison-harness RED fixtures.
#          FAILs (exit 1) iff the runtime-output token "EXTRA MARKER" (see
#          gate_marker.sh's §11.4.273 note: this greps $1's EXECUTED stdout,
#          never its source text, so a comment mentioning the underscored
#          identifier "EXTRA_MARKER" in prose can never false-match) is
#          absent from $1's output; PASSes (exit 0) otherwise. Used as
#          (a) "the gate whose own mutation no other survivor catches" in
#          cs_bad_removal_no_transfer, and (b) "the extra catcher NEW gains
#          over OLD" in cs_negctrl_gained_catch.
# Usage: gate_extra.sh <target_file>
# Exit: 0 marker present (PASS); 1 marker absent (FAIL/catch); 2 usage error.
set -u
[ $# -eq 1 ] || { echo "usage: gate_extra.sh <target_file>" >&2; exit 2; }
[ -f "$1" ] || { echo "gate_extra.sh: no such file: $1" >&2; exit 2; }
sh "$1" 2>/dev/null | grep -q "EXTRA MARKER" && exit 0
exit 1
