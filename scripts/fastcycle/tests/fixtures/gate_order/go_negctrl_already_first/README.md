# go_negctrl_already_first (negative control)

Own `affected.json` (NOT the shared one) declares `gate_c_planted_fail`
**already first** in section order (`c, a, b, d`), using the SAME toy gates
and the SAME `../_shared/history/prebuild_sections.tsv` history.

The §11.4.201(1) false-positive guard: `--order history-cost` still ranks
`gate_c_planted_fail` first by fail_rate/mean_cost — reordering is a NO-OP
here since the declared order already matches the ranked order. The tool
MUST still produce the correct, correctly-labelled result (execution order
first = `gate_c_planted_fail`, verdict FAIL) — proving the ordering
mechanism is not merely "always report whatever is declared first" nor
doing anything vacuous; it genuinely ranks by history every time, and in
this case the ranked order happens to coincide with the declared order.
