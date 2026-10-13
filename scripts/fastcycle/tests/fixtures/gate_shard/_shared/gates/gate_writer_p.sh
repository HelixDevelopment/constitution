#!/bin/sh
# Toy gate for T055 negative-control fixture (gs_negctrl_disjoint_temp/):
# writes to $1 only. Used paired with gate_writer_q.sh, each given a
# DIFFERENT temp path -- disjoint write sets -- to prove the sharder does
# NOT over-eagerly co-schedule every pair of gates into one shard (the
# false-positive guard for the golden-bad case in gs_bad_shared_temp_split/,
# per §11.4.201(1)).
if [ -z "${1:-}" ]; then
    echo "gate_writer_p: missing required path argument" >&2
    exit 2
fi
echo "p" >> "$1"
exit 0
