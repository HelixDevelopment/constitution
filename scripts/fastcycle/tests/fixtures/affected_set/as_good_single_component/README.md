# as_good_single_component (golden-good, AS-011)

Changes ONLY `src/alpha.sh`. `gate_alpha`'s sole observed input is that path,
so it MUST be selected; the other 4 gates' observed inputs are all
untouched, so they MUST each appear in `skipped` with
`reason_code=NO_OBSERVED_INPUT_CHANGED` (AS-011) -- an exact, re-checkable
skip reason, not a bare "skipped".
