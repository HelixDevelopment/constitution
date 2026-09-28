# as_bad_unmapped_path (golden-bad, AS-010 / DEC-08)

`src/totally_unmapped_path.sh` is not in ANY gate's `observed_inputs` in
`map.json` -- the map genuinely cannot tell whether it matters. Per AS-010
this makes `determinable=false`: the FULL applicable suite runs (nothing
silently skipped, `skipped=[]`) and `fallback_reason` is the literal
`affected-set undeterminable: <path>` naming the actual unmapped path (never
a generic message). Exit code 4 per the contract's exit-codes clause ("diff
unreadable/undeterminable -> emits full-suite fallback and exits 4 so
callers see BLIND" -- this fixture is the unmapped-path instance of that
same undeterminable class).
