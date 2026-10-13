# T062 render_keys fixture — changed-source toy document

**Revision:** 1
**Last modified:** 2026-09-29T00:00:00Z

This is a small, real toy Markdown document used ONLY as test-fixture data
for T062's RED test (`test_render_keys_red.sh`, scenario
`rk_changed_all_four`). This file's content is real content, byte-for-byte
edited between two baseline renders (v1 → v2) so the test can prove a
genuine content change causes the CURRENT exporter
(`scripts/testing/sync_all_markdown_exports.sh`) to regenerate all three
sibling formats (.html/.pdf/.docx), alongside this file itself as the
source of truth — the §11.4.65 "four formats" (.md + .html + .pdf + .docx).

Marker: RK-CHANGED-V1
