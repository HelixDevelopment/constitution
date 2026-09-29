#!/bin/sh
# gate_c_planted_fail.sh — toy gate for T054's gate_order fixtures (the PLANTED
# failing gate, plan T-C04 / contract AS-013 / task text: "a planted failing
# gate placed last in section order is reported first").
#
# Declared LAST in _shared/affected.json's members array (section/declared
# order: a, b, d, c). Historically HIGH fail_rate (4/5 = 0.8) AND cheap
# (mean_cost ~100ms per ../history/prebuild_sections.tsv) -> the HIGHEST
# fail_rate/mean_cost ratio of the 4 toy gates (8.0, vs b/d at 0.4 and a at
# 0.0). Under `--order history-cost` (descending fail_rate/mean_cost) this
# gate MUST be the one gate_runner.sh executes/reports FIRST, despite being
# declared last.
#
# Genuinely FAILs on every real invocation (never a stub) -- this is the
# real defect the RED test's golden fixture expects gate_runner.sh to find.
echo "gate_c_planted_fail: FAIL -- planted defect (intentional, fixture-only)" >&2
exit 1
