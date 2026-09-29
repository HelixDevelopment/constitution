# as_concurrent (AS-014, Edge Case "concurrent changes")

Two independent changes (change-A touching src/alpha.sh, change-B touching
src/beta.sh) run through affected_set.py as if concurrently. Each output
must correctly attribute ONLY its own change's member set -- change-A's
output must select gate_alpha (never gate_beta) and vice versa, proving
verdicts/affected-sets are never swapped between concurrently-processed
changes.
