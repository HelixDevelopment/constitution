# Token harness

## What is measured deterministically (no model call)

| Metric | Tool | Measured |
|---|---|---|
| lean core size | `tiktoken` (`cl100k_base`) | **999 tokens** (limit 3000) |
| catalog size | `tiktoken` | **46,861 tokens** = 9.1% of the 516,424-token monolith |
| largest rule file | `tiktoken` | §11.4.230 = 20,442 tokens |
| per-rule ceiling | `tiktoken` | derived: 5% of monolith (25,821) |
| catalog ceiling | `tiktoken` | derived: 10% of monolith (51,642) |

The literal “catalog ≤5000 tokens” target from the plan is **arithmetically
impossible** with one mandatory `sha256` per anchor (289 × ~35 tokens for the
digests alone). The enforced budget is the plan's own intent — a full-catalog
load must stay a small fraction of the monolith. This is recorded as a deviation,
not hidden.

## What requires a live provider call (UNCONFIRMED here)

`test_per_prompt_reduction` and the cache-warm collapse proof need real provider
`usage` objects for a frozen corpus. This host produced none, so the harness
reports **UNCONFIRMED** (exit 3) and never a PASS. To complete it:

1. Freeze the corpus (≥20 prompts) under `progressive/EVIDENCE/corpus/`.
2. Run the monolith path → `TOKENS_BEFORE.json` (per prompt + total).
3. Run the progressive path → `TOKENS_AFTER.json`.
4. `validate_tokens.py` then asserts `after ≤ 0.40 × before` for every prompt.

## Reproduce

```bash
python3 progressive/validate_tokens.py
python3 progressive/mutation_matrix.py
```
