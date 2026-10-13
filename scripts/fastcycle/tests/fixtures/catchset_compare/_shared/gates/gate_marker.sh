#!/bin/sh
# id: g_marker
# Purpose: toy Gate for the T050 catch-set-comparison-harness RED fixtures.
#          FAILs (exit 1) iff the literal token SAFE MARKER (space-separated,
#          never appearing that way in any comment/prose in this fixture set
#          -- see the §11.4.273 control-needle note below) is absent from
#          $1's RUNTIME OUTPUT (executes $1, greps its stdout); PASSes
#          (exit 0) otherwise. Used as "the one gate that catches defect D1"
#          across multiple fixtures (cs_good_equal, cs_bad_dropped_gate,
#          cs_bad_overeager_skip, cs_bad_stale_cache,
#          cs_negctrl_removal_with_transfer, cs_negctrl_old_missed).
#
# §11.4.273 forensic note (found authoring this fixture set, 2026-09-28):
# an EARLIER version of this gate grepped $1's SOURCE TEXT for the bare
# token "SAFE_MARKER" -- but every defect-patch file's own comment header
# names the marker it removes ("drops SAFE_MARKER only"), so the gate
# false-PASSed against a patch that had genuinely removed the marker's
# `echo` line: a textbook carrier false-match (grep matched the comment
# PROSE describing the removal, not the removed thing itself). Fixed by
# (a) grepping RUNTIME OUTPUT instead of source (comments are never
# executed, so they can never leak into stdout), and (b) using the
# two-word form "SAFE MARKER" (space, not underscore) in the actual echo'd
# payload below and in widget.sh/defect_d1_widget.sh, so the word this gate
# searches for never collides with the underscored identifier
# ("SAFE_MARKER") every comment in this fixture set freely uses in prose.
# Usage: gate_marker.sh <target_file>
# Exit: 0 marker present (PASS); 1 marker absent (FAIL/catch); 2 usage error.
set -u
[ $# -eq 1 ] || { echo "usage: gate_marker.sh <target_file>" >&2; exit 2; }
[ -f "$1" ] || { echo "gate_marker.sh: no such file: $1" >&2; exit 2; }
sh "$1" 2>/dev/null | grep -q "SAFE MARKER" && exit 0
exit 1
