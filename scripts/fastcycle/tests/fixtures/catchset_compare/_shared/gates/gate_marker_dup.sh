#!/bin/sh
# id: g_marker_dup
# Purpose: toy Gate with IDENTICAL detection logic to gate_marker.sh (also
#          checks the runtime-output token "SAFE MARKER" -- see
#          gate_marker.sh's §11.4.273 note on why this greps runtime output
#          rather than source text) but a DISTINCT gate id -- models a
#          genuine "believed-duplicate" gate for the removal-proof fixtures
#          (cs_negctrl_removal_with_transfer: this gate is the one proposed
#          for removal; cs_bad_removal_no_transfer uses a DIFFERENT gate,
#          see that fixture's README.md).
# Usage: gate_marker_dup.sh <target_file>
# Exit: 0 marker present (PASS); 1 marker absent (FAIL/catch); 2 usage error.
set -u
[ $# -eq 1 ] || { echo "usage: gate_marker_dup.sh <target_file>" >&2; exit 2; }
[ -f "$1" ] || { echo "gate_marker_dup.sh: no such file: $1" >&2; exit 2; }
sh "$1" 2>/dev/null | grep -q "SAFE MARKER" && exit 0
exit 1
