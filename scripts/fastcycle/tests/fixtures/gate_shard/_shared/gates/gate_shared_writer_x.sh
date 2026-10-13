#!/bin/sh
# Toy gate for T055 golden-bad fixture (gs_bad_shared_temp_split/): writes
# a line to a MUTABLE SHARED temp path also written by
# gate_shared_writer_y.sh. If these two gates ever ran in DIFFERENT shards
# concurrently, this append is a data race (lost update / interleaved
# lines) -- exactly the "planted section pair sharing a temp file" the
# T-C05 contract (plan.md line 819) requires gate_runner.sh to detect from
# the two gates' declared write-sets and force into ONE shard.
#
# $1 (required): the shared temp path to append to.
if [ -z "${1:-}" ]; then
    echo "gate_shared_writer_x: missing required shared-path argument" >&2
    exit 2
fi
echo "x" >> "$1"
exit 0
