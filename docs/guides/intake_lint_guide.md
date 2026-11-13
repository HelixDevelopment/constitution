# Intake lint guide — `intake_lint.py` for a batch of workable items

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T12:30:00Z |
| Status | active |
| Status summary | User guide and manual for the read-only content lint of an intake batch of workable items (cross-references, states, sections, secrets, ephemeral locations, duplicates, cited paths). |
| Authority | Constitution §11.4.148, §11.4.214, §11.4.215, §11.4.294, §11.4.10 — the canonical text wins where this guide and the constitution disagree. |
| Scope | Universal (§11.4.17); the id prefix, the database path and the origin text are consumer DATA (§11.4.35). |
| Issues | not yet wired into a seam: the reporting and landing paths and the pre-build sweep do not run it (tracked as an item, see the tracker-intake v2 report) |
| Issues summary | Run it by hand before landing an intake batch. |
| Fixed | initial creation |
| Fixed summary | — |
| Continuation | — |

## Table of contents

- [Why it exists](#why-it-exists)
- [Run it on an intake batch](#run-it-on-an-intake-batch)
- [Finding codes and how to fix each](#finding-codes-and-how-to-fix-each)
- [Exit codes](#exit-codes)
- [The embedded-id table for a re-mint](#the-embedded-id-table-for-a-re-mint)
- [Skipping a code](#skipping-a-code)
- [Tests](#tests)
- [Honest boundary](#honest-boundary)

## Why it exists

`workable-items validate` and `workable-items diff` prove the closed sets, the description floor and
that the database and the Markdown agree. They do not read what a description says. In the
2026-11-12 tracker-intake review two wrong facts passed both: an item that duplicated an open item
(§11.4.214) and a cross-reference that named an anchor number as if it were an item id. The
reviewer's data mutants M2, M3, M9, M10 and M11 survived the same tools. `intake_lint.py` reads the
text of a selected batch and reports those classes. It never writes; it opens the database
read-only.

## Run it on an intake batch

Select the batch by a phrase every item of it carries (its `Origin:` line), or by ids:

```
python3 -I scripts/workable-items/intake_lint.py --db docs/workable_items.db \
  --origin 'tracker-intake vehicle 2026-11-12' --require-dup-check --repo-root .
python3 -I scripts/workable-items/intake_lint.py --db docs/workable_items.db --ids CON-300,CON-301
```

- `--require-dup-check` demands a `Duplicate check (section 11.4.214): <verdict> ...` line in every
  selected item, verdict from DISTINCT, DISTINCT-but-similar, SAME-DEFECT, UNDECIDED.
- `--repo-root .` turns on PATH-MISSING: every cited `docs/qa/...` or `docs/operator_decisions/...`
  path must exist in the checkout.
- `--prefix` sets the id prefix; by default it is the most common prefix in the database.

Each finding is one line `FINDING <code> <item> <detail>`, then `RESULT: PASS|FAIL selected=N
findings=N prefix=P`.

## Finding codes and how to fix each

| Code | Meaning | Fix |
|---|---|---|
| XREF-DANGLING | an id of this tracker in the title or description does not exist | correct the id, or, if it belongs to another tracker or a vehicle, declare it on a `Foreign ids (<where>): A, B` line |
| XREF-LABEL | `<id> (<label>)`: no significant word of the label is in the target's title | the label names a different item or an anchor; fix the id or the label |
| FOREIGN-STALE | the `Foreign ids` line declares an id the text never names | drop it from the line |
| STATE-PROSE | a state word in prose, or a hand-written `**Reproduction:**` / `**Investigation:**` line in the description, disagrees with the state column | set the state with the engine flags (`--reproduction-state`, `--investigation-state`); reword prose so it does not restate a state |
| SECTIONS | a §11.4.148 marker is missing (What, Affected scope, Reproduction / context, Acceptance criteria, Parent / links) | add the section; write `UNKNOWN:` for what is not known |
| BODY-SYNC | the description is not contained in body_md | regenerate through the engine; never edit one column by hand |
| SECRET | a credential-shaped string; only the pattern name is printed | remove it; if it is a real credential, rotate it (§11.4.10) |
| EPHEMERAL | a session-scratchpad path, a mktemp-shaped directory, a `.bundle` file or a bare `review_*.md` name, on a line with no `(ephemeral` note | cite the tracked copy under `docs/qa/...`, or note the line `(ephemeral: ...)`; a note covers its own line only |
| SHARED-PATH | a file in the Affected scope is also named by an open item outside the batch, and the Duplicate check line does not name that item | compare the two items and name the other item in the Duplicate check line with its verdict |
| DUP-CHECK | (with `--require-dup-check`) the line is missing or the verdict is not in the closed set | add the line |
| DUP-SAME-OPEN | the verdict is SAME-DEFECT but the item is not closed Obsolete duplicate-of the named id | close it with `close <id> --status obsolete` and `obsolete-details <id> --reason duplicate-of --superseding <head>`; if more than one head is possible, the verdict is UNDECIDED |
| PATH-MISSING | a cited evidence path does not exist under `--repo-root` | commit the evidence, or correct the path (§11.4.215) |

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | no finding (or `--embeddings` printed) |
| 1 | findings |
| 2 | usage error: no selection, an unknown `--skip-check` code, `--repo-root` not a directory |
| 3 | BLIND: database missing or unreadable, no items, an unknown id, an empty selection, or a built-in control needle failed — no verdict is given |

The built-in control needles run on every call: each check must fire on a golden-bad text and stay
silent on golden-good texts. If one fails, the lint cannot see and says BLIND instead of PASS.

## The embedded-id table for a re-mint

`--embeddings` prints a TSV `item, embedded_id, namespace, count` for the selected items: `own`
(an id of the batch), `main` (an existing item outside the batch), `foreign` (declared on a
`Foreign ids` line), `unknown` (not in the database). A lander that re-mints the batch's ids
(§11.4.214) uses it to find every id to rewrite inside the database. Ids written outside the
database (Markdown exports, commit messages, reports) are not in it; the report that ships the batch
lists those places.

## Skipping a code

`--skip-check SECTIONS,PATH-MISSING` drops those codes from the result. A skipped code must be stated
wherever the result is cited. Use it for legacy items whose old text predates the rules, never to
pass a new batch.

## Tests

- `tests/workable_items/test_intake_lint.sh`: golden-good and golden-bad fixture databases for every
  code, usage and BLIND exits, the embeddings namespaces, and the reviewer's data mutants plus the I1
  and I2 replays on a scratch copy of the real database.
- `tests/workable_items/test_intake_lint_mutations.sh`: code mutants of the lint; each must be killed
  by the suite's own cases, and the check mutants also by the control needles.

## Honest boundary

Evidence class gate-logic only (§11.4.289): the lint proves its decisions on the text it reads. It
does not prove that an item is true, that a duplicate verdict is right, or that the external trackers
match the database. The word-overlap label check and the shared-path check are heuristics; a pass is
not a review.
