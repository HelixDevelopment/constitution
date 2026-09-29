# mr_one_input_changed (primary FR-006/plan-T-C07 case)

put stores a KILLED verdict against observed_input.txt's real sha256. get asks with observed_input_flipped.txt's sha256 instead (one byte of the gate's observed input genuinely changed). Task line: 'changing one gate input re-runs that gate's mutations' -- this is that case, literally.

**Expected:** `MISS`
