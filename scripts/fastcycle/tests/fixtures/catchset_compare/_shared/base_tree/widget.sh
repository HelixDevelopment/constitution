#!/bin/sh
# Purpose: toy "under-test" tree file for the T050 catch-set-comparison-harness
# RED fixtures (constitution/scripts/fastcycle/tests/fixtures/catchset_compare/).
# It exists only so the RED test's toy gates (gate_marker.sh, gate_marker_dup.sh,
# gate_extra.sh) have something real to run and check the RUNTIME OUTPUT of,
# and so a SeededDefect can be modelled as "replace this file with one of the
# sibling _shared/patches/*_widget.sh variants" -- never a diff/patch tool
# dependency, just a whole-file swap into a disposable copy (contract clause
# CS-001: disposable copy, real tree untouched).
#
# §11.4.273 note: the echo'd tokens below use a SPACE ("SAFE MARKER") rather
# than the underscore this comment block (and every other comment in this
# fixture set) freely uses when talking ABOUT the marker ("SAFE_MARKER").
# This is deliberate: the gate scripts grep the RUNTIME OUTPUT of this file
# for the space-separated form, so a comment's prose use of the underscored
# identifier can never accidentally satisfy (or corrupt) a gate's check --
# an earlier revision of this fixture set greped SOURCE TEXT for the bare
# underscored token and false-PASSed because the defect patches' own removal
# comments happened to mention the very marker they removed (a carrier
# false-match, §11.4.201(7)(a)).
#
# All three markers present = the clean, unmutated baseline (CS-003 sanity:
# every gate MUST pass against this file, unmodified).
echo "SAFE MARKER"
echo "OTHER MARKER"
echo "EXTRA MARKER"
exit 0
