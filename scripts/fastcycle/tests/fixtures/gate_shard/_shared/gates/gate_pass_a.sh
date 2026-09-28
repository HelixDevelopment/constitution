#!/bin/sh
# Toy gate for T055 (test_gate_shard_red.sh) fixtures: always PASS, no I/O
# side effects on any shared path. Used in gs_good_independent_determinism/
# and gs_negctrl_disjoint_temp/ as an independent (non-write-set-overlapping)
# gate.
exit 0
