#!/bin/sh
# gate_d_new.sh — toy gate for T054's gate_order fixtures.
# Always PASSes when run. Deliberately has ZERO rows in
# ../history/prebuild_sections.tsv -- tests contract clause AS-013 / DEC-10's
# "new gates at the median rate" default: a gate with no historical fail_rate
# must be assigned the MEDIAN observed fail_rate/mean_cost across the OTHER
# gates (here: median of [0.0 (a), 0.4 (b), 8.0 (c)] = 0.4), NOT zero and NOT
# the maximum -- so it ranks tied with gate_b_moderate, strictly below
# gate_c_planted_fail and strictly above gate_a_reliable.
echo "gate_d_new: checked (no history yet, first appearance)"
exit 0
