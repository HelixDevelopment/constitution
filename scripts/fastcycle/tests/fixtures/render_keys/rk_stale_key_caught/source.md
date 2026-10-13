# T062 render_keys fixture — stale-key toy document (golden-bad)

**Revision:** 1
**Last modified:** 2026-09-29T00:00:00Z

This is a small, real toy Markdown document used ONLY as test-fixture data
for T062's RED test (`test_render_keys_red.sh`, scenario
`rk_stale_key_caught`). This file's content starts at v1 (matching
`key_v1.json`'s recorded content-hash), is then genuinely edited to v2, but
the recorded key sidecar is deliberately left un-updated (simulating the
exact defect T-C12's freshness gate must catch: "a twin whose source
changed but whose key was not updated"). The (currently absent)
`docs/render_keys.py check` subcommand must, once T-C12 lands, recompute the
CURRENT key from these real v2 bytes, compare it against the stale recorded
key, and refuse/flag the mismatch.

Marker: RK-STALE-V1
