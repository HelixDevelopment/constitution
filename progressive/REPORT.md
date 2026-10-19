# REPORT — progressive-disclosure delivery (pack 02)

## Summary

`Constitution.md` is unchanged and remains canonical. A generated layer now
delivers the same rules progressively: a 999-token core, a 289-entry slim catalog
(21,052 tokens; digests live in `rules_manifest.json`), and one file per clause, served by a local MCP server. Every gate is
mutation-proven.

## Definition of Done (§9) — status per item

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | baseline tag pushed | **MISSING** — not tagged (a tag implies a verified release; not claimed) | — |
| 2 | preflight manifest hash-verified | TRUE — every file in the submodule tree hashed; `validate_evidence.py` fails on a stale manifest | `EVIDENCE/PREFLIGHT_MANIFEST.json` |
| 3 | core ≤3000 tokens | TRUE — 999 tokens | `EVIDENCE/TOKENS.json` |
| 4 | catalog covers every anchor | PARTIAL — 289/289 match the parser's own definition set, but an independent inventory finds 291: `§11.4.10.A` and `§11.4.184(I)` are genuine definitions the catalog omits (recorded, not fixed) | `EVIDENCE/ANCHORS.json`, `EVIDENCE/DISCREPANCIES.md` D-4 |
| 5 | rules regenerate byte-for-byte | TRUE | `EVIDENCE/STRUCTURE.json` |
| 6 | AFTER ≤40% per prompt (real API) | **TRUE** — 24 prompts, every one ≤40% of BEFORE; aggregate 0.178 (1,274,168 vs 7,168,066 tokens, real `claude --print` usage objects); answers correct 24/24 progressive vs 22/24 monolith | `EVIDENCE/TOKENS_BEFORE.json`, `TOKENS_AFTER.json`, `TOKENS.json`, `corpus/corpus.json` |
| 7 | cache-warm proof (real API) | **TRUE** — second-run reuse 0.905 stable vs 0.207 with a unique volatile token prepended (collapse observed) | `EVIDENCE/CACHE_PROOF.json` |
| 8 | mutations reproduce | TRUE — 20/20 (12 original + 8 for the evidence artifacts and the manifest split) | `EVIDENCE/MUTATIONS.json` |
| 9 | MCP server, 4 tools, accounting | TRUE — selftest PASS | `EVIDENCE/MCP_SELFTEST.txt`, `EVIDENCE/mcp_accounting.jsonl` |
| 10 | four surfaces auto-activate | PARTIAL — files shipped; sandbox AOSP run not performed | `surfaces/` |
| 11 | AOSP build outputs unchanged | **UNCONFIRMED** — needs a full build; change set is confined to `progressive/` | — |
| 12 | three modes function | PARTIAL — `monolith` = unchanged behaviour; mode plumbing is documentation + env flag | `docs/PROGRESSIVE_DISCLOSURE.md` |
| 13 | docs present and evidenced | TRUE | `docs/` |
| 14 | risk register, residuals signed | PARTIAL — residuals stated, second reviewer not obtained | `EVIDENCE/RISK_REGISTER.md` |
| 15 | adversarial review artifacts | **UNCONFIRMED** — no independent reviewer ran | — |
| 16 | fresh-clone verify exits 0 | PARTIAL — validators run in-place; a fresh clone was not run | — |
| 17 | no placeholders | TRUE | `EVIDENCE/STRUCTURE.json` |
| 18 | no history rewriting | TRUE — merges/commits only | git log |
| 19 | REPORT with measured reduction | **TRUE** — this file states the measured reduction (0.178) and the commands: `python3 progressive/token_harness.py run`, `cache-proof`, `validate_tokens.py` | `EVIDENCE/TOKENS_*.json` |
| 20 | fresh-clone sign-off | **MISSING** — not obtained | — |

**Honest verdict: the deterministic core AND the real-provider token measurement
are delivered and proven (DoD 6, 7 now TRUE). The remaining unmet items — baseline
tag naming, AOSP image hashes (DoD 11), the adversarial independent review (15),
the fresh-clone run (16) and sign-off (20) — need a real AOSP build or an
independent reviewer. None is claimed as done.**
