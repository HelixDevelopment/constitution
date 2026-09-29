#!/bin/sh
# SeededDefect D_extra: drops the EXTRA_MARKER output line only (echoes
# "SAFE MARKER" and "OTHER MARKER" only). Caught ONLY by gate_extra.sh
# (greps runtime output for "EXTRA MARKER", never this comment).
echo "SAFE MARKER"
echo "OTHER MARKER"
exit 0
