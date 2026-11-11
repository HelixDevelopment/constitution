# Independent review: fixu landing (3bd34494, e6b16598, 2e8cfb90)

Reviewer: independent subagent (not the author), §11.4.142 / §11.4.209. Model: Opus 5.5 per the harness.
Effort: not reported to me and not verifiable (§11.4.231(F.2)).
Method: fresh clone of `git@github.com:HelixDevelopment/HelixConstitution.git` in my own scratchpad
(`.../74ce2b36-.../scratchpad/rvfx`), detached at 2e8cfb90; worktrees for main 90efceb8 and for mutants.
Nothing was pushed or tagged; the live checkout was only read.

## Verdict: GO-with-follow-ups

0 critical, 0 important, 4 minor, 2 nit. No finding shows lost work, a weakened gate, or a claim
the evidence does not support.

## What I checked, with results (run in this session)

| Check | Result |
|---|---|
| `run_full_suite.sh --verify-manifest` at 2e8cfb90 | `RESULT: MANIFEST-OK`, census total=869, py/excluded=25, py/member=24 (matches e6b16598 message) |
| Lock rows | 55 data rows, 7 comment lines; new chained line `rows=55 chain=c7b6cb5288e723f0`; earlier acceptance lines unchanged |
| Lock hashes of the two new rows | sha256-16 of the manifest notes (no newline) = `b936cad3425d32bc`, `949a083d5d9e16cd`, same as the lock and the commit message |
| "raises IndexError with no arguments" | reproduced for both helpers (rc=1, IndexError) |
| "invoked by test_resolve1.sh / test_resolve2.sh" | dump: test_resolve1.sh:59, test_resolve2.sh:53; fixture: test_resolve1.sh:65,93,94,103. Coverage stays through those entry tests |
| Merge lock/manifest | lock taken from main (53 rows incl. main's hermetic_lint.py row); manifest is the union (main's 13 rows + vehicle's rows), nothing dropped |
| workable-items `validate` (DB copy) | `OK — 143 items` |
| `diff` DB vs Issues/Fixed | in sync, 143 vs 143; `diff --db-only` passed |
| Ids | CON-001..CON-145, 143 items, no duplicates; gaps CON-048 and CON-070, present identically on main 90efceb8, vehicle 5dc6097e and the merge (pre-existing) |
| Re-mint CON-108..131 -> CON-116..139 | every field equal to the vehicle row except description/body_md/last_modified; description differences are only the id-history note plus id references, and every reference to a vehicle id was moved by +8 (programmatic check over all items and columns; one hit in CON-099 is a historical "CON-100..CON-109" range of the earlier manifest-triage re-mint, correctly not rewritten) |
| Main's CON-001..115 | unchanged except CON-047/089/099; main had not changed those three since merge base bdc3ac43, and merged rows equal the vehicle rows exactly, so nothing of main was lost |
| "16 code comments" re-pointed | 16 lines in 13 files, each +8, no vehicle id left unmapped |
| Review records r1-r3 "copied unchanged" | byte-identical (`cmp`) to the reviewers' scratch files review_fixu.md / review_fixu2.md / review_fixu3.md |
| CON-140..145 | present, Queued, types/severities as the message says; CON-145 confirmed: note says 12 heavy members, 14 rows list it |
| CON-144 reproduction | `cm_gate_env_reads_allowlisted.sh` on 2e8cfb90: uncovered=2 (the two BLK reads), matches envgate_merged.out; record surface host-only with evidence path, consistent with §11.4.294(B) |
| "closure test fails the same way on main and merged" | main 90efceb8: 30 passed, 2 failed (control + N3, uncovered=4); merged: 30 passed, 2 failed (control + N3, uncovered=3). Not a regression of the landing |
| Known-failures table | two CON-047 rows, `reason:rc_3+tracked`; `--check-known-open`: KNOWN-OPEN, both open. jq_regions test rc=3 (52 passed, 5 KNOWN). Closure test now exits 1, so its row does not match and the run fails honestly |
| Allowlist changes | eval rows became content-pinned (`<eval>#sha12`), one added for the CON-121 fix; no row loosened |
| CHANGELOG | the landing adds no CHANGELOG entry (diff vs 90efceb8 is empty); the 231 lines in the merge stat are main's entries relative to the vehicle parent. So the commits make no CHANGELOG claim to overclaim |

## Mutants (§11.4.194(6)(d)), authored by me, against the merged run_full_suite.py, run with `bash tests/test_run_full_suite.sh`

Baseline (unmutated worktree): passed=274 failed=0, rc=0.

| Id | Mutation | Result |
|---|---|---|
| X1 | `check_known_open`: `elif r[1] != "Issues":` -> `elif r[0].startswith("Fixed"):` (staleness from status text instead of location) | **SURVIVED** (274/0) |
| X2 | `match_known`: `if ids != {tid}:` -> `if not ids <= {tid}:` (no tracked token accepted) | killed: `FAIL 11b: rc 3 without any tracked token is not KNOWN` |
| X3 | `match_known`: `if reason != code:` -> `if reason != code and not need_tracked:` (rc 1 accepted under a +tracked row) | killed: `FAIL 11b: rc 1 is never KNOWN under a reason row` |

## Findings

- **M1 (minor, test-instrumentation).** X1 survives: case 11c only uses a closed item whose status starts with "Fixed", so a check that reads closure from status text (and treats an Obsolete / Completed / Implemented item in Fixed.md as open) passes. Add a closed item with status `Obsolete` (location Fixed) to the 11c fixture. Code is the vehicle's CON-047 F047-2 change, carried by the merge.
- **M2 (minor, process-doc).** `docs/guides/full_suite_runner_guide.md` line 83 says the acceptance "was NOT run by an agent: the operator ... runs `--accept-excluded-change i@mvasic.ru`". e6b16598 (like bdc3ac43 and 2739c26b before it) was run by the landing agent on an order relayed by the conductor; the commit states that the agent did not see the operator's message. The commit is honest; the guide is stale and describes a stronger separation than is practised. Either update the guide (agent runs it on a recorded operator order, tier `instance`) or have the operator run it.
- **M3 (minor, process-doc).** The "reviewed proposal resolve1_lock_PROPOSAL_r2.md" that e6b16598 follows is not tracked (§11.4.215). The substance is in the manifest notes and in review_fixu_r2.md slice 13 (GO), so nothing binding is lost, but the cited document cannot be read from the repository.
- **M4 (minor, process).** CON-099 reached GO-with-follow-ups at round 3 with no §11.4.276(E) round-3 convergence assessment recorded. The tracker note says so; record it, or note why it was not needed, before round 4.
- **N1 (nit).** The landing (162 files, new gates, tests and behaviour changes) has no CHANGELOG entry. Whether the project expects one for a fix landing is UNCONFIRMED; noted only.
- **N2 (nit).** main stays red on CM-GATE-ENV-READS-ALLOWLISTED and the census closure test after the landing (as before it, measured). It is tracked as CON-144 (medium) and the merge reduces uncovered from 3 to 2; it should be fixed soon, since a red gate on main hides any new failure of the same gate.

## Not checked

- The vehicle's own code changes in depth (rounds 1-3 reviewed them; I only checked that the merge kept them and changed nothing of main).
- Full-suite run (`run_full_suite.sh --include-heavy`); not run here.
