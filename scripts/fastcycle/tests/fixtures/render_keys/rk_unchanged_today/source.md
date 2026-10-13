# T062 render_keys fixture — unchanged-source toy document

**Revision:** 1
**Last modified:** 2026-09-29T00:00:00Z

This is a small, real toy Markdown document used ONLY as test-fixture data
for T062's RED test (`test_render_keys_red.sh`, scenario
`rk_unchanged_today`). It is never edited by that scenario — only its
mtime is touched, never its bytes — to prove the CURRENT exporter
(`scripts/testing/sync_all_markdown_exports.sh`) re-renders it anyway,
because its freshness check today compares mtimes only (`[ "$md" -nt
"$html" ]`), never content.

Marker: RK-UNCHANGED-V1
