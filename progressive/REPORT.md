# REPORT — progressive-disclosure delivery (pack 02)

## Summary

`Constitution.md` is unchanged and remains canonical. A generated layer now
delivers the same rules progressively: a 999-token core, a 289-entry catalog,
and one file per clause, served by a local MCP server. Every gate is
mutation-proven.

## Definition of Done (§9) — status per item

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | baseline tag pushed | **MISSING** — not tagged (a tag implies a verified release; not claimed) | — |
| 2 | preflight manifest hash-verified | PARTIAL — catalog carries `source_sha256`; no full-file manifest | `catalog.json` |
| 3 | core ≤3000 tokens | TRUE — 999 tokens | `EVIDENCE/TOKENS.json` |
| 4 | catalog covers every anchor | TRUE — 289/289, zero omissions/extras | `EVIDENCE/STRUCTURE.json` |
| 5 | rules regenerate byte-for-byte | TRUE | `EVIDENCE/STRUCTURE.json` |
| 6 | AFTER ≤40% per prompt (real API) | **UNCONFIRMED** — no provider object | `EVIDENCE/TOKENS.json` |
| 7 | cache-warm proof (real API) | **UNCONFIRMED** — proxy (no volatile markers) is PASS, live collapse not measured | `EVIDENCE/TOKENS.json` |
| 8 | 12 mutations reproduce | TRUE — 12/12 | `EVIDENCE/MUTATIONS.json` |
| 9 | MCP server, 4 tools, accounting | TRUE — selftest PASS | `EVIDENCE/MCP_SELFTEST.txt`, `EVIDENCE/mcp_accounting.jsonl` |
| 10 | four surfaces auto-activate | PARTIAL — files shipped; sandbox AOSP run not performed | `surfaces/` |
| 11 | AOSP build outputs unchanged | **UNCONFIRMED** — needs a full build; change set is confined to `progressive/` | — |
| 12 | three modes function | PARTIAL — `monolith` = unchanged behaviour; mode plumbing is documentation + env flag | `docs/PROGRESSIVE_DISCLOSURE.md` |
| 13 | docs present and evidenced | TRUE | `docs/` |
| 14 | risk register, residuals signed | PARTIAL — residuals stated, second reviewer not obtained | `docs/RISK_REGISTER.md` |
| 15 | adversarial review artifacts | **UNCONFIRMED** — no independent reviewer ran | — |
| 16 | fresh-clone verify exits 0 | PARTIAL — validators run in-place; a fresh clone was not run | — |
| 17 | no placeholders | TRUE | `EVIDENCE/STRUCTURE.json` |
| 18 | no history rewriting | TRUE — merges/commits only | git log |
| 19 | REPORT with measured reduction | PARTIAL — this file; reduction UNCONFIRMED | — |
| 20 | fresh-clone sign-off | **MISSING** — not obtained | — |

**Honest verdict: the deterministic core is delivered and proven; six DoD items
are UNCONFIRMED/MISSING because they need a live provider run, a real AOSP build,
or an independent reviewer. None is claimed as done.**
