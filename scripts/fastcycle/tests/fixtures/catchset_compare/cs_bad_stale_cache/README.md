# Fixture: cs_bad_stale_cache (golden-bad)

Contract row 5 (of the fixtures table): "NEW cache returns old PASS for D's
catcher | golden-bad | exit 1 (proves FR-007 errors surface here too)".

- Both configs' manifests list `[g_marker, g_noop]` (identical to
  `cs_bad_overeager_skip` in this respect).
- `stale_cache.json` records that NEW's run of `g_marker` for D1 is served
  from a CACHED verdict computed against the CLEAN (unmutated) tree
  (`PASS`), instead of a fresh execution against the D1-mutated copy (which
  the RED test independently verifies would FAIL/catch, by actually running
  `g_marker` against a mutated disposable copy).
- Expected: same `lost=1`/exit-1/named-D1 outcome as the two sibling
  golden-bad fixtures, but reached via the verdict-cache path (FR-007)
  rather than the affected-set (T-C03) or manifest-membership path.
