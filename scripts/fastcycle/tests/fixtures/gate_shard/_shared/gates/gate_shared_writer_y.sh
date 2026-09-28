#!/bin/sh
# Toy gate for T055 golden-bad fixture (gs_bad_shared_temp_split/): the
# other half of the planted shared-temp-file pair -- see
# gate_shared_writer_x.sh for the full rationale. Same mutable path,
# different content, so a race (if the shard split incorrectly) is
# detectable as interleaved/lost lines.
#
# $1 (required): the shared temp path to append to.
if [ -z "${1:-}" ]; then
    echo "gate_shared_writer_y: missing required shared-path argument" >&2
    exit 2
fi
echo "y" >> "$1"
exit 0
