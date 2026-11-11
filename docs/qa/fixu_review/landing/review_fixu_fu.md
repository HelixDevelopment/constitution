# Independent review: fixu landing follow-ups 65383536 (CON-186..CON-188) on main 9cd7cacd

Reviewer: independent subagent, not the author (§11.4.142 / §11.4.209). Model: Opus 5.5 according to the harness.
Effort: not reported to me and not verifiable (§11.4.231(F.2)).
Method: fresh clone of `git@github.com:HelixDevelopment/HelixConstitution.git` (origin/main = 9cd7cacd) in my own
scratchpad (`/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/rv/repo`),
bundle fetched (sha256 ae4b0b95...b9 matched; head 653835364f7a), detached worktrees for mutants, base and head DB.
Nothing pushed or tagged; the live checkout was only read (`git remote -v`). Worktrees removed with `git worktree remove`.

## Verdict: GO-with-follow-ups

0 critical, 0 important, 3 minor, 4 nit. Nothing lost, no gate weakened; every number in the commit message reproduced.

## Checks run in this session

| Check | Result |
|---|---|
| Unmutated `bash tests/test_run_full_suite.sh` at 65383536 | passed=276 failed=0 (the 4 new 11c lines ok) |
| Mutant X1 (`elif str(r[0]).startswith("Fixed"):`) | killed: passed=274 failed=2, exactly the two new 11c assertions (ATM-8 Obsolete, ATM-9 Completed). Matches the commit message |
| `--verify-manifest` at head | `RESULT: MANIFEST-OK`, census total=878 |
| `workable-items validate` (in a worktree, so evidence paths resolve) | base 9cd7cacd: OK 183 items; head: OK 186 items |
| `diff --issues --fixed` / `diff --db-only` | head in sync, 186 vs 186; db-only passed |
| DB delta base -> head, every table, row sets | items +3 (CON-186..188), item_history +3 (Opened), doc_segments +3, sqlite_sequence advanced; **0 rows removed or changed in any table** (no history text touched) |
| Ids | 186 items, no duplicates, max CON-188, gaps CON-048 and CON-070 only (pre-existing) |
| New items | Task / Queued / Low, location Issues, reproduction and investigation UNSET; Issues_Summary Queued 108->111, total 181->184 (DB: 184 in Issues) |
| M3 tracked files | `docs/qa/fixu_review/resolve1_lock_PROPOSAL_r2.md` sha256 245559d4... = scratchpad original `013b6b97.../scratchpad/fixu2/resolve1_lock_PROPOSAL_r2.md`; `docs/qa/fixu_review/landing/review_fixu_landing.md` sha256 880349de... = `013b6b97.../scratchpad/review_fixu_landing.md`. The proposal names b936cad3425d32bc / 949a083d5d9e16cd (line 38), as e6b16598 says |
| M4 | CON-187 writes no assessment and says UNKNOWN; nothing invented. CON-099 already carried the N099-6 note; CON-187 adds the acceptance |

## Own mutants of check_known_open (§11.4.194(6)(d)), not written by the author

| Id | Mutation | Result |
|---|---|---|
| Y1 | `elif r[1] != "Issues":` -> `elif r[1] == "Fixed":` (any other location read as open) | survived 276/0. Equivalent on a schema DB (`CHECK (current_location IN ('Issues','Fixed'))`, schema.sql:85); the test fixture DB has no such constraint. Nit |
| Y3 | drop `stale += 1` in the `r is None` (unknown id) branch | **survived 276/0**. Real: with a table holding only an unknown id, head prints `STALE ATM-77 ...` then `RESULT: KNOWN-STALE`, the mutant prints the STALE line and `RESULT: KNOWN-OPEN` (rc 0). 11c always pairs the unknown id with a closed one, so rc 1 comes from ATM-6 |
| Y4 | lookup `WHERE atm_id LIKE 'ATM-%'` (wrong item resolved) | killed 271/5 |

Mutant diffs and logs: `.../74ce2b36-.../scratchpad/rv/mut_{X1,Y1,Y3,Y4}.{diff,log}`.

## Findings

- **F1 (minor, test-instrumentation).** Y3 survives: no 11c case has an unknown id as the only stale row, so "unknown id counts as stale" is not pinned by its exit code. Add a `--known` table with only `ATM-77` and assert rc 1 and `RESULT: KNOWN-STALE`; adopt Y3 as a paired mutant. Pre-existing gap in the same fixture M1 extended, not introduced here.
- **F2 (minor, process-doc).** The new guide sentence says the three acceptances 2739c26b, bdc3ac43, e6b16598 "were run by the landing agent on an order relayed by the conductor, and each commit message says so". bdc3ac43's message says "Operator acceptance, genuine user message 2026-11-05 20:41 CET ... run by the landing agent on that order": an agent run, but on a user message, not a conductor relay. Only 2739c26b and e6b16598 say "relayed by the conductor". Reword per commit.
- **F3 (minor, process-doc).** "The achieved separation is therefore `instance`". In e6b16598 the same landing agent replaced the two manifest rows and then ran the acceptance of that change; under §11.4.240(F) `instance` means a verifier instance separate from the producer. What the record supports is: the change and the acceptance run by one agent, on a recorded operator order, with a roster id. Name it so, or record why `instance` applies (the prior review M2 suggested the label, so this is a correction of that suggestion too).
- **N1 (nit).** Y1 is equivalent only because of the schema CHECK; fixture DBs lack it. Optional: a fixture row with another location, or a note that the location set is closed by the schema.
- **N2 (nit).** The edited guide paragraph still opens "At this revision the 44 excluded rows ... accepted as fsr-r4-author"; the lock now has 55 rows and its last acceptor is `i@mvasic.ru` (2026-11-10). Also "What the runner enforces is only that the id ... is on the committed roster" undersells the other refusals (roster tracked, equal to HEAD, not a symlink; chain intact; no other manifest problem); "it checks the id, not who typed it" is the accurate point.
- **N3 (nit).** The tracked proposal still says "Status: PROPOSAL. Not applied in any tracked tree"; it was applied by e6b16598. A one-line header note (applied in e6b16598, kept as the record §11.4.215) would stop it misleading.
- **N4 (nit).** CON-187 says the round-3 inputs are not recoverable "from the tracker text alone". They are in tracked files: `docs/qa/fixu_review/review_fixu_r3.md` §5 (F099-4 same carrier class as F099-2), §6 (reviewer class inventory, line 433 the only open member) and N099-6. CON-187 should cite them so the fixer's assessment can be written from them.

## Not checked

- Full-suite run (`run_full_suite.sh --include-heavy`).
- Whether `(atm_id, current_location)` as primary key can hold one id in both locations; `fetchone()` would then pick one row arbitrarily. Not in this change's scope.
