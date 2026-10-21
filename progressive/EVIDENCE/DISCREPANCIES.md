# Discrepancies (measured, not guessed)

All token figures are `tiktoken` `cl100k_base` counts taken on 2026-10-19 from the
files named; commands are in `progressive/REPORT.md` and reproducible with the
validators.

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

## D-2 — the literal "catalog ≤5000 tokens" target is NOT met; the cause is the id+description+path+title+tags contract, not the digests

The earlier wording of this entry ("arithmetically impossible because of one
sha256 per entry") was a design choice presented as arithmetic. It has been
tested:

| Measured artifact | Tokens |
|---|---|
| old `catalog.json` (per-entry sha256 + line range inline) | 46,861 |
| new slim `catalog.json` (id, title, one-line description, tags, path) | 21,052 |
| `rules_manifest.json` (sha256 + line range per rule; read only by verify/validate) | 26,397 |
| 289 sha256 digests alone, one per line | 11,733 |
| 289 ids + one-line descriptions + paths (nothing else) | 9,376 |
| 289 ids + one-line descriptions | 6,034 |
| 289 ids alone | 1,976 |
| `Constitution.md` (monolith) | 516,424 |

Moving the digests and line ranges into `rules_manifest.json` was feasible
without breaking `mcp_server.py` search/load/list/verify, the validators, the
surfaces or the `core.md` references, and was implemented in `generate_split.py`
(`catalog.json` schema_version 2, `rules_manifest.json` schema_version 1).
Result: the always-loadable layer-2 file fell from 46,861 to 21,052 tokens
(55.1 % smaller; 4.1 % of the monolith). The literal 5,000 is still not met:
even ids + one-line descriptions alone cost 6,034 tokens, above 5,000, so the
target cannot be reached while the catalog carries a description per anchor.
It can only be reached by dropping descriptions (ids only = 1,976), which would
remove the text `search_constitution` ranks on. That trade is an operator
decision and is not made here.

The enforced budget is the plan's INTENT, tightened from 10 % to 5 % of the
monolith (limit 25,821; measured 21,052). The literal number is recorded as not
met.

## D-3 — provider measurements absent — RESOLVED 2026-10-19

The earlier statement ("no live provider `usage` object was available on this
host") was FALSE: `claude --print --output-format json` returns one. The
measurements now exist — `TOKENS_BEFORE.json`, `TOKENS_AFTER.json`,
`CACHE_PROOF.json` (see `REPORT.md` DoD 6 and 7). Remaining honest limits are
listed in `docs/TOKEN_HARNESS.md`.

## D-4 — two genuine clause definitions are absent from the catalog

`gen_evidence.py` inventories `Constitution.md` with its own regexes (it does not
import `generate_split.py`). It finds 291 definitions; `catalog.json` holds 289.
Exactly two ids are only in the independent inventory, none only in the catalog:

| Id | Line | Definition form | Why the catalog misses it |
|---|---|---|---|
| `§11.4.10.A` | 753 | heading `### §11.4.10.A — Pre-store credential leak audit` | `generate_split.py` `CLAUSE_RE` accepts only digits after `§` and a space/dash next, so the `.A` suffix fails the match |
| `§11.4.184(I)` | 10300 | bold line `**§11.4.184(I) — HawkScan (DAST) + OWASP ZAP …**` | `BOLD_RE` requires a dash right after the digits, so `(I)` fails the match |

Consequence: the two parent clauses absorb the sub-clause text. `§11.4.10` is
catalogued as lines 711–821 but spans 711–752 once `§11.4.10.A` is a definition;
`§11.4.184` is catalogued as 10298–10317 but spans 10298–10299 once
`§11.4.184(I)` is a definition. No hash differs where the ranges agree
(`hash_mismatches_with_equal_range` is empty). Recorded, not fixed: changing the
parser changes rule-file boundaries and every dependent hash, and the choice of
whether sub-clause suffixes are separate anchors is a governance decision.

## D-5 — the 8 line-start tokens are references, not definitions (verified)

An earlier analysis reported 8 line-start tokens absent from the catalog: `§1.1`
`§107` `§11.4.21.2` `§11.4.64` `§12.7` `§12.8` `§2` `§3.4`. The independent
inventory classifies every line that begins with `§<id>` (after optional
indentation/bullet) and is not a heading or bold-line definition. All 8 ids
occur only that way, and none is defined anywhere in `Constitution.md`:

| Id | Line(s) | Form |
|---|---|---|
| `§11.4.21.2` | 1356 | wrapped-paragraph continuation |
| `§2` | 2208 | wrapped-paragraph continuation |
| `§1.1` | 2538, 5383, 7068, 7307 | continuation (2538, 5383, 7068) and list item (7307) |
| `§12.7` | 5478 | list item |
| `§12.8` | 5479, 9983 | list item (5479), continuation (9983) |
| `§3.4` | 5482 | wrapped-paragraph continuation |
| `§11.4.64` | 6061 | wrapped-paragraph continuation |
| `§107` | 7308 | list item |

Verdict: mid-text references. There is no genuine omission among them; the only
genuine omissions are the two in D-4. The ids `§1.1`, `§2`, `§3.4`, `§12.7`,
`§12.8`, `§107`, `§11.4.21.2` and `§11.4.64` are cited by the canon but have no
definition in it, the same class as D-1.
