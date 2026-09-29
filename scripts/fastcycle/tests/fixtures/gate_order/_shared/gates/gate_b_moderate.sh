#!/bin/sh
# gate_b_moderate.sh — toy gate for T054's gate_order fixtures.
# Always PASSes when run. Historically moderate fail_rate (see
# ../history/prebuild_sections.tsv): 1 fail out of 5 historical runs →
# fail_rate = 0.2, moderate mean_cost. Ranks BELOW gate_c_planted_fail on
# fail_rate/mean_cost but ABOVE gate_a_reliable and gate_d_new (median rate).
echo "gate_b_moderate: checked (currently clean)"
exit 0
