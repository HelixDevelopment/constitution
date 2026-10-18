# Discrepancies (measured, not guessed)

## D-1 — twin files reference anchors the canon does not define

`AGENTS.md`, `CLAUDE.md`, `QWEN.md` and `GEMINI.md` reference anchor ids that
appear in `Constitution.md` only as cross-references, never as clause
definitions (for example §11.4.206, §9.1.5, §12.8). They are not invented by the
twins — the canon itself cites them — but a reader cannot resolve them.

Recorded, not fixed here: rewriting governance anchors is out of scope for this
delivery and would change rule semantics. The structural check therefore:
1. fails if a twin references an id that appears NOWHERE in the canon;
2. records the 20 defined-but-unmirrored anchors in
   `progressive/twin_exceptions.txt` so the gap stays visible.

## D-2 — the literal “catalog ≤5000 tokens” target is not achievable

One mandatory `sha256` per anchor (289 anchors) costs roughly 35 tokens each in
`cl100k_base` — about 10k tokens for the digests alone, before ids, descriptions,
tags and paths. The measured catalog is 46,861 tokens (9.1% of the 516,424-token
monolith). The enforced budget is the plan's INTENT (a full-catalog load must be
a small fraction of the monolith); the literal number is recorded as not met.

## D-3 — provider measurements absent

No live provider `usage` object was available on this host, so
`test_per_prompt_reduction` and the cache-collapse proof are **UNCONFIRMED**
(exit 3). Nothing in this delivery fabricates them.
