# Token harness

## What is measured deterministically (no model call)

| Metric | Tool | Measured |
|---|---|---|
| lean core size | `tiktoken` (`cl100k_base`) | **999 tokens** (limit 3000) |
| catalog size (slim: id, title, one-line description, tags, path) | `tiktoken` | **21,052 tokens** = 4.1% of the 516,424-token monolith (was 46,861 before digests moved to `rules_manifest.json`) |
| `rules_manifest.json` (sha256 + line range; verify/validate only) | `tiktoken` | 26,397 tokens, never loaded by an agent to find a rule |
| largest rule file | `tiktoken` | §11.4.230 = 20,442 tokens |
| per-rule ceiling | `tiktoken` | derived: 5% of monolith (25,821) |
| catalog ceiling | `tiktoken` | derived: 5% of monolith (25,821) |

The literal “catalog ≤5000 tokens” target from the plan is **not met**. Moving the
digests and line ranges out of `catalog.json` (done) cut it from 46,861 to 21,052
tokens, but the 289 ids + one-line descriptions alone measure 6,034 tokens, so the
target is unreachable while every anchor keeps a description (ids only: 1,976).
The enforced budget is the plan's own intent — a full-catalog load must stay a
small fraction of the monolith. Measurements and the decision left open:
`EVIDENCE/DISCREPANCIES.md` D-2.

## Real provider measurement (DONE 2026-10-19)

`progressive/token_harness.py` makes real `claude --print --output-format json`
calls (no simulation, nothing written when a call fails) over the frozen corpus
`EVIDENCE/corpus/corpus.json` (24 prompts derived from `catalog.json`, sha256
recorded). Arms: BEFORE = the monolithic `constitution/CLAUDE.md` appended to
the system prompt; AFTER = `core.md` + `catalog.json`. Measured: aggregate
AFTER/BEFORE = 0.178 (1,274,168 / 7,168,066 tokens), every prompt ≤ 40 %,
answers correct 24/24 (progressive) vs 22/24 (monolith). `cache-proof` shows the
volatile-token mutation collapsing second-run reuse (0.905 → 0.207).

Scope and limits (stated, not hidden): one model (`sonnet`), one host, an
anchor-lookup corpus (it measures what carrying the governance text costs and
whether the right anchor is found — not task quality across every workflow), and
user-level plugins/hooks excluded (`--setting-sources project`).

## Reproduce

```bash
python3 progressive/token_harness.py run
python3 progressive/token_harness.py cache-proof
python3 progressive/validate_tokens.py
python3 progressive/mutation_matrix.py
```
