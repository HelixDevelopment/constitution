# mr_negctrl_mtime_only (negative control)

put and get carry the SAME observed_input.txt content-sha256 but DIFFERENT recorded_mtime timestamps. DEC-23's key formula (mirroring T051's VC-002) is content-addressed, not mtime-addressed -- an mtime-only difference must NOT force a re-run. Proves the key builder does not accidentally over-invalidate on a non-semantic field.

**Expected:** `HIT`
