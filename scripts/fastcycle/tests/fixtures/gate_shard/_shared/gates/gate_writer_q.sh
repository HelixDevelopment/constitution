#!/bin/sh
# Toy gate for T055 negative-control fixture -- see gate_writer_p.sh for
# the full rationale. Writes to $1 only, given a DIFFERENT path than
# gate_writer_p.sh in gs_negctrl_disjoint_temp/config.json.
if [ -z "${1:-}" ]; then
    echo "gate_writer_q: missing required path argument" >&2
    exit 2
fi
echo "q" >> "$1"
exit 0
