# mr_flip_gate_script (control needle: gate script itself changed)

get asks with gate_script_v2.sh's real sha256 (a genuinely different gate implementation) instead of gate_script.sh's. A real code edit to the gate under test invalidates every cached mutation verdict for it -- proven here by a real, differently-behaving toy gate script, not a placeholder filename change.

**Expected:** `MISS`
