# as_bad_stale_map (golden-bad, AS-003)

`map_stale.json`'s `gate_alpha` entry has `content_hash` deliberately set to
64 zero characters -- guaranteed NOT to equal the real, freshly-computed
sha256 of `_shared/gates/gate_alpha.sh`. AS-003: "the map is invalid
(-> undeterminable) if any gate script's content address differs from the
one it was traced with." The tool MUST detect this by RE-HASHING the real
gate script at invocation time and comparing -- never merely trusting the
map's stored hash -- and fall back to the full suite with
determinable=false.
