# as_determinism

Runs affected_set.py TWICE against the identical change and asserts the two
output files are byte-identical (or at minimum produce the identical
`body_hash`/`members`/`skipped` triple) -- no run-order or hash-map
iteration nondeterminism leaking into the emitted affected-set.
