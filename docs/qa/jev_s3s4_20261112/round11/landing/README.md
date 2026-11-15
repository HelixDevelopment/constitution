# Round-11 landing: merge of `main` bcac0882 and re-mint of the five Jev items

Evidence class: gate-logic / PROVISIONAL (stubs only, no hosted calls, no credentials).

## What was done

1. `git merge --no-ff origin/main` (main = bcac0882) into the round-10 head aaa2b3b0.
2. The only conflict, `docs/workable_items.db` (binary), was resolved by taking `main`'s database unchanged.
3. The five items the vehicle had minted were minted again on `main`'s database through the engine
   (`scripts/workable-items/bin/workable-items add --prefix CON`, run from the repository root) by `mint.sh`.
   The engine assigned the ids in `mint_ids.txt`. Item CON-401 was then moved to `In progress` with the engine's `update`.
4. `validate` reported OK (370 items). `export --no-formats` regenerated `docs/Issues.md` and
   `docs/Issues_Summary.md` from the database (the round-10 commit had not done this, review finding R10-2).
   `diff` reported the database and the documents in sync. The Fixed documents did not change.
5. The id mentions were rewritten in `CHANGELOG.md`, `docs/jev/governance-guide.md`,
   `docs/qa/jev_s3s4_20261112/README.md` and `docs/qa/jev_s3s4_20261112/round10/README.md` (the last two re-hashed
   under their `SHA256SUMS`). Commit trailers and `round10/landing/mint_ids.txt` were not rewritten.

Replay check: running `mint.sh` on a fresh copy of `main`'s database gives item rows identical to the landed
database (sha256 of the ordered item rows e0284d6be369..., the same for both).

## Id mapping

| Round-10 vehicle id | Item | Id on `main` |
|---|---|---|
| CON-388 | Jev decision layer | CON-401 |
| CON-389 | O6-1 | CON-402 |
| CON-390 | CLOCK-BOOTSTRAP | CON-403 |
| CON-391 | MONO-FALLBACK | CON-404 |
| CON-392 | DEPS-LLMCTL-REF | CON-405 |

CON-299, CON-PENDING-JEV and CON-PENDING-JEV-CONSTITUTION (ids used in earlier trailers and notes) map to CON-401.
The vehicle ids CON-388 to CON-392 were never on `main`; on `main` those numbers belong to other items.
