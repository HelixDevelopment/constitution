#!/bin/sh
# Toy gate for T055 fixtures: always FAIL, no I/O side effects on any
# shared path. Independent (disjoint write set). Deliberately planted so
# the gs_good_independent_determinism/ verdict SET is not all-PASS
# (a determinism check that only ever sees uniform PASS would be a weaker
# oracle -- a verdict-set with a mixed PASS/FAIL population is the
# stronger, more honest determinism proof).
echo "gate_fail_c: deliberate FAIL" >&2
exit 1
