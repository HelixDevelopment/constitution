#!/bin/sh
# SeededDefect D1: drops the SAFE_MARKER output line only (echoes "OTHER
# MARKER" and "EXTRA MARKER" only, per widget.sh's two-word runtime-output
# convention -- see widget.sh's §11.4.273 note). Applied by copying this
# file over a disposable copy's widget.sh (contract CS-001: disposable
# copy, never the real tree). Caught ONLY by gate_marker.sh / gate_marker_dup.sh
# (both grep the RUNTIME OUTPUT for "SAFE MARKER", never this comment).
echo "OTHER MARKER"
echo "EXTRA MARKER"
exit 0
