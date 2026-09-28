# mr_flip_patch (control needle: different mutation)

get asks about a DIFFERENT mutation patch (mutation_patch_v2.diff, a genuinely different defect proof, mutation_id=M-002) than the one put stored a verdict for (mutation_patch.diff, M-001). Proves the cache is keyed per-mutation, not merely per-gate -- two different mutations of the same gate must never share a cached verdict.

**Expected:** `MISS`
