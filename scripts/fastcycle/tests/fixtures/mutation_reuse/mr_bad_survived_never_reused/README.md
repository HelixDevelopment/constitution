# mr_bad_survived_never_reused (golden-bad)

Every key component is byte-identical between `put` (verdict=SURVIVED) and `get`, exactly like mr_good_killed_reuse -- but the stored verdict is SURVIVED, not KILLED. DEC-23: 'reuse KILLED only (SURVIVED is always re-examined)' -- a SURVIVED verdict must NEVER be servable by get, regardless of key match. The generic key-diff loop in the RED test's Section B would wrongly predict HIT here (the keys DO match); this scenario is asserted by name, separately, exactly as T051's vc_admission_skip_never_cached fixture is (§11.4.273: caught by running the real rule, not by assuming every unchanged-key fixture behaves the same).

**Expected:** `MISS`
