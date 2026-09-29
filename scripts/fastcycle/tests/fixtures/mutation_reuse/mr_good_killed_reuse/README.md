# mr_good_killed_reuse (golden-good)

Everything (patch, gate script, observed inputs, tool versions) is byte-identical between the `put` (verdict=KILLED) and the subsequent `get`. DEC-23: a KILLED verdict under an unchanged key MUST be reused, never re-run.

**Expected:** `HIT`
