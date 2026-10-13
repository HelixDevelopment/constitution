# fixtures/limit_class/ — T127 self-validation fixtures

Fixture convention for `constitution/scripts/fastcycle/orchestration/limit_class.py`
(plan.md T-B06; tasks.md T127/T135; research.md DEC-14; contracts/
agent-registry-and-handoff.md AR-005; FR-016). Task T127 (`tasks.md`) writes
ONLY this RED test + these fixtures; the tool itself is T135, a later,
separate task (Producer != Verifier, §11.4.240 — this file's author never
implements `limit_class.py`).

**A real contract DOES exist for this tool** (unlike T109/tier_route.py):
`specs/004-fast-dev-cycles/contracts/agent-registry-and-handoff.md`'s AR-005
clause + Components block fix the CLI verb (`limit_class.py --signal <raw>
--out <class.json>`), the closed class set, and the exit codes. This fixture
set borrows those field names/shapes from the real contract (T104/T108
pattern) rather than defining the entire interface from scratch (the T109/
tier_route.py pattern, which had no contract at all).

## The classification rule this fixture set encodes (from research.md DEC-14
## + contracts/agent-registry-and-handoff.md AR-005 + data-model.md's
## `limit_signal` entity, restated precisely, never invented)

Closed class set (four members, DEC-14's own words): `{rate-limited
(retry-after present) | cap (spend/subscription/weekly cap: no retry-after,
or a named weekly/subscription reset) | context-overflow (prompt too long) |
other}`.

1. **`context-overflow`** — the raw signal is an HTTP 400 `invalid_request`
   whose text names a token/prompt-length ceiling being exceeded ("prompt
   (is) too long ... N tokens > M maximum"). Structurally distinct from every
   other class: no HTTP 429, no `retry-after`, no cap/reset wording anywhere.
   Handling (AR-005 / plan T-B06): re-dispatch with the governance subset
   (DEC-12), **never** with the same prompt.
2. **`cap`** — an HTTP 429 that is EITHER missing a `retry-after` header OR
   carries a NAMED weekly/subscription reset instant (DEC-14's own
   disambiguator, stated as an OR of the two conditions). Handling: **never**
   retry on that alias; rebind the resume to an operational alias
   (§11.4.196 native-first order) and mark the alias cooled until its stated
   reset.
3. **`rate-limited`** — an HTTP 429 that carries a `retry-after` header AND
   no named weekly/subscription reset (the genuine transient/short-window
   case). Handling: backoff honouring `retry-after`, then resume on the same
   or another alias.
4. **`other`** — none of the above structurally matches; the classifier
   still emits a verdict (never refuses to classify) per the contract's exit
   code 1 note ("signal unparseable ... class `other` emitted with the raw
   signal").

## Layout

Five self-contained fixtures, one JSON file each, `schema:
"limit-class-fixture/v1"`:

| Fixture | Kind | What it proves |
|---|---|---|
| `lc_golden_cap_weekly.json` | golden | T127's own named golden scenario: the 2026-09-26 weekly-cap incident — a REAL row from `docs/requests/agent_registry.jsonl` — classifies as `cap`, never `rate-limited` |
| `lc_golden_context_overflow.json` | golden | T127's own named golden scenario: the haiku prompt-too-long incident — a REAL row from `docs/requests/agent_registry.jsonl`, corroborated by a second, independently-real occurrence captured 2026-09-30 by this project's own T114 dispatch — classifies as `context-overflow` |
| `lc_bad_cap_via_429_no_retry_after.json` | golden-bad | T127's own named golden-bad scenario ("a cap classified as rate-limited FAILs"): a second REAL row from the SAME 2026-09-26 weekly-cap incident, proving that a plausible mutation (ignore the retry-after/reset disambiguator, call every 429 `rate-limited`) mis-derives it |
| `lc_negctrl_rate_limited_retry_after.json` | negative-control | discriminator against the two `cap` fixtures above: an HTTP 429 that DOES carry a short `retry-after` and NO named reset classifies as `rate-limited`, proving the correct rule does not collapse every 429 into `cap` (the mirror-image failure mode of the golden-bad fixture). **Honestly `provenance: constructed`** — grep-verified (§11.4.115(G)): no real `retry-after`-bearing row exists anywhere in `docs/requests/agent_registry.jsonl` as of this dispatch. |

## Wire format (fixed by the real contract — `class.json`'s shape per
## `data-model.md`'s `limit_signal` entity: `{class, raw, resets_at}`)

Each fixture's `expected_class` field is one of the four closed-set string
literals above (hyphenated exactly as the contract spells them:
`"rate-limited"`, `"cap"`, `"context-overflow"`, `"other"`). This suite's
`derive_class` (embedded in `test_limit_class_red.sh`, never imported by nor
shared with the not-yet-existing `orchestration/limit_class.py`, section
11.4.245) is the DERIVED oracle every fixture's own `expected_class` is
independently re-verified against before that value is trusted for anything
downstream (mirroring `test_tier_routing_red.sh`'s `derive_route` /
`test_governance_subset_red.sh`'s `derive_selection` precedent exactly).

The forward-compatible CLI this suite's "real-tool invocation" block
exercises once T135 lands: `orchestration/limit_class.py --signal <raw>
--out <class.json>` — the REAL, contract-fixed verb (not speculative, unlike
T109/tier_route.py's provisional verb). Output shape `{class: str, raw: str,
resets_at: str|"UNKNOWN"}` per `data-model.md`'s `limit_signal` entity.

## Provenance discipline (section 11.4.115(G) / section 11.4.6 — CONSTRUCTED
## reproductions never silently pass as OBSERVED ones)

Three of the five fixtures carry `provenance: "observed"` (their `raw_signal`
is copied byte-for-byte from a real, cited row in `docs/requests/
agent_registry.jsonl` or, for the context-overflow corroborating signal, from
`specs/004-fast-dev-cycles/tasks.md` / `docs/CONTINUATION.md` / `docs/
requests/history.md`). The negative-control fixture is honestly
`provenance: "constructed"` — no real `retry-after`-bearing 429 row exists
in this project's registry to date (confirmed by a `grep -i retry-after`
control needle in the test script itself, not merely asserted here); the
field shape it constructs (a `retry-after` seconds header on a 429) is the
standard, well-established Anthropic API rate-limit convention this
project's own constitution already cites (§11.4.187/§11.4.196(B) captured
429 signature; research.md DEC-14's own cited source, Anthropic rate limits,
R5:97) — never fabricated at random.
