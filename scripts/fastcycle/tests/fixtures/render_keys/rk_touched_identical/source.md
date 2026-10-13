# T062 render_keys fixture — touched-but-identical toy document

**Revision:** 1
**Last modified:** 2026-09-29T00:00:00Z

This is a small, real toy Markdown document used ONLY as test-fixture data
for T062's RED test (`test_render_keys_red.sh`, scenario
`rk_touched_identical`). Its bytes are NEVER edited by that scenario — only
its mtime is touched (via `touch`) — so the test can prove, by a real
`sha256sum` comparison before and after the touch, that mtime and content
are genuinely DISTINGUISHABLE on this host: the file's mtime changes while
its content stays byte-identical. This is the underlying mechanism a
content-addressed key (T-C12) relies on to correctly report "no render
needed" for exactly this case, in direct contrast to
`rk_unchanged_today/`'s proof that the CURRENT, mtime-only freshness check
wastefully re-renders it.

Marker: RK-TOUCHED-V1
