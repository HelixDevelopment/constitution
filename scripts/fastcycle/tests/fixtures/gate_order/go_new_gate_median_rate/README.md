# go_new_gate_median_rate (control needle: DEC-10 "new gates at the median rate")

Own `affected.json` with only 3 members declared (`a, d, c`, `gate_b_moderate`
deliberately EXCLUDED from this scenario) against the SAME
`../_shared/history/prebuild_sections.tsv`. `gate_d_new` has ZERO rows in
the history log.

Contract AS-013 / plan.md DEC-10: "new gates at the median rate" — a gate
with no historical fail_rate/mean_cost entry must NOT be treated as rate=0
(which would tie it with `gate_a_reliable`, the lowest-ranked gate) NOR as
the maximum observed rate (which would rank it ABOVE `gate_c_planted_fail`,
the genuinely highest-ranked gate) — it must land at the MEDIAN.

**Honest scope gap (documented, not silently resolved — mirrors T051's
VC-003/VC-004 disclosure pattern):** the contract text does not specify the
POPULATION the median is computed over (every gate in the full historical
log, vs only the gates-with-history present in THIS run's `members`). This
fixture is deliberately constructed so gate_d_new ranks strictly BETWEEN
gate_a_reliable and gate_c_planted_fail under EITHER reasonable
interpretation:
- median of {a=0.0, b=0.0004, c=0.008} (whole log) = 0.0004
- median of {a=0.0, c=0.008} (only this run's other history'd members) = 0.004

Both values satisfy `0.0 < median < 0.008`, so `expected.json` asserts only
the RELATIVE ordering (`execution_order == [c, d, a]`), never a specific
numeric ratio — the real implementation's exact population choice is owed
to T070 ("Implement fail-fast ordering in gate_runner.sh ... until T054 is
GREEN", plan T-C04), not silently picked here.
