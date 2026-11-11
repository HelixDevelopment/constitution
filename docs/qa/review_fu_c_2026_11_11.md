# Independent review: follow-up bundle fu_c (CON-186..CON-191) on main fc57ad0c

Reviewer: a fresh independent subagent, not the author (§11.4.142 / §11.4.209 / §11.4.194(6)). Model: Opus 5.5, as the harness reports it. Effort: not reported to me, so I cannot verify it (§11.4.231(F.2)).

How I worked: I cloned `git@github.com:HelixDevelopment/constitution.git` (origin/main = fc57ad0c) into
`/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/rev_fu_c/constitution`,
fetched the bundle as branch `fu_c` and used detached worktrees for the RED run and the mutant runs. Both worktrees are now removed. Nothing was pushed, committed upstream or tagged. In the live checkout I only ran `git remote -v`. The host was busy with other agents' mutation runs; I left those alone.

## Overall verdict: GO-with-follow-ups

Findings: 0 critical, 0 important, 3 minor, 4 nit. Every open finding is minor-class under §11.4.276(G.2) (process-doc or a pre-existing code/doc mismatch outside the diff), and each one has a proposed follow-up below. CON-189's test change is proven: RED on main's suite and GREEN on the bundle's suite, with the same mutants. No gate was weakened and no tracker row was lost.

## Bundle integrity

```
sha256sum fu_c.bundle -> 1b6449d1ab44dd3783b5623b93635601264876b0785c5970ec636b531479d05b  (matches)
git bundle verify fu_c.bundle   (run inside a clone that holds fc57ad0c)
  ... fu_c.bundle is okay
  The bundle contains this ref: a3ad6f4e8774e379624d06e3bc9ec5a80818556f HEAD
  The bundle requires this ref: fc57ad0c69197d47febf020744701ffd04016cad
main..fu_c: a3ad6f4e c57a00e8 4318bd3e 48ebc5f7 (4 commits, as claimed)
```
The bundle's ref is `HEAD`, not `fu_c`; the branch has to be named on fetch. The author did not see the "okay" line only because verify needs the prerequisite fc57ad0c in the repository.

## Checks run this session

| Check | Result |
|---|---|
| `bash tests/test_run_full_suite.sh` on fu_c | `passed=280 failed=0`, rc 0 (3m44s) |
| **RED**: main's tests + the bundle's F47d (Y3) and F47e (Y1) rows, `test_run_full_suite_mutations.sh F47d F47e` | `ok baseline`, `SURVIVED F47d`, `SURVIVED F47e`, `SUMMARY mutants=2 killed=0 survivors=2`, rc 1. This reproduces the reviewer's measurement that the author marked UNCONFIRMED |
| **GREEN**: the bundle's suite, `... F47d F47e Z1 Z2 Z6 Z7` | `ok baseline`, `killed F47d (2)`, `killed F47e (1)`, plus my mutants below; `SUMMARY mutants=7 killed=7 survivors=0`, rc 0 |
| `run_full_suite.sh --verify-manifest` on fu_c | `RESULT: MANIFEST-OK`, census total=879 |
| `workable-items validate` (copy of the DB) | `OK — 191 items, all invariants satisfied` |
| `workable-items diff --issues --fixed` | in sync, 191 vs 191 |
| DB delta main to fu_c, every table | items: 4 rows changed (CON-187, 189, 190, 191); item_history: +5, 0 removed; nothing else changed. CON-186 and CON-188 rows are untouched |
| `cm_gate_env_reads_allowlisted.sh` on fu_c (= main code) | `VERDICT: PASS ... uncovered=0 stale=0 needle=ok`, rc 0, so the gate part of CON-188 N2 is green |
| CON-187 citations | `review_fixu_r3.md` §5 holds F099-4 (carrier match), §6 is the reviewer's class inventory, and the row "433 ... open" is the only open member (this is line 433 of `test_precheck_slicer_red.sh`, not of the review file). N099-6 is present in Issues.md. All accurate |
| Lock vs guide | 55 data rows; last line `# accepted 2026-11-10T23:30:46Z accepted_by=i@mvasic.ru ... rows=55 chain=c7b6cb5288e723f0`; the roster holds only `i@mvasic.ru`. Matches the guide |

## Own mutants (§11.4.194(6)(d)) on `check_known_open`, run against the bundle's suite

| Id | Mutation | Result |
|---|---|---|
| Z1 | `if stale:` -> `if stale > 1:` (a single stale row reads KNOWN-OPEN) | killed (2 failing checks) |
| Z2 | the lookup also matches `ATM-5`, ordered last (an unknown id resolves to an open item) | killed (4) |
| Z6 | `elif r[1] != "Issues":` -> `... and r[0] != "Queued":` (closure decided by status text for a Queued item) | killed (1); only the new ATM-10/Archive row can catch this one |
| Z7' | `for ... in rows:` -> `rows[:-1]` (the last row is skipped) | killed (4) |

Note: my ids clashed with the harness's existing Z7 (and Z4). The harness therefore also ran the existing Z7, which was killed (2), and printed two `Z7` lines; mine is the second one. I did not run Z1/Z2/Z7' against main's suite, so I make no claim about whether they would survive there.

## Per-item verdicts

- **CON-186 (M1-M3): fix confirmed. Closure action owed (finding F-A).** On main, the M1 change (case 11c with Obsolete and Completed rows), the M2 guide rewording and the M3 tracked proposal all landed in 65383536, and review_fixu_fu passed them with GO-with-follow-ups (X1 was killed, and the tracked proposal sha matched). Every follow-up that review raised against them is now carried by CON-189 (F1, Y1), CON-190 (F2, F3, N2) and CON-191 (N3, N4). Still, the item stays `Queued` with the sentence "the item is Queued ... neither PROVISIONAL-DONE nor VERIFIED-DONE". The item needs a status write: Ready for testing (PROVISIONAL-DONE, §11.4.290) with a `**Verification:**` line that cites review_fixu_fu.md GO-with-follow-ups and names CON-189/190/191 as the children carrying its follow-ups. It reaches VERIFIED-DONE once those children are verified. Its body also still describes M2 as "tier instance"; it needs one line saying CON-190 superseded that wording.
- **CON-187 (N4): GO.** The cited inputs exist and are accurate, and no assessment was invented. Queued is the right status (the decision belongs to the CON-099 fixer).
- **CON-188: GO for "no change", with nit F-D.** N1 stays an operator/lander decision. N2's gate is green on fc57ad0c, as measured above. The item text does not record this.
- **CON-189: GO.** Test-first, with the RED reproduced by me and the GREEN measured. The new cases are sound, and both paired mutants and 4 of mine are killed. Nit F-C covers the stale body sentence.
- **CON-190: GO-with-follow-ups.** The per-commit wording now matches the three commit messages. The `instance` label is gone, and the 55-row lock and last acceptor are correct. The new enforcement list overclaims in one place (F-B). It has two smaller wording gaps (F-E).
- **CON-191: GO.** The proposal header says APPLIED in e6b16598 and keeps the original line; CON-187 cites the inputs.

## Findings

- **F-A (minor, process-doc). CON-186 has no closure action.** See CON-186 above. Follow-up: an update of CON-186 to Ready for testing with a provisional verification line, and a note on the superseded "tier instance" text.
- **F-B (minor, process-doc, plus a pre-existing code/doc mismatch; the overclaim is in the new text). "...that the chain is intact and that no other manifest problem exists" is not fully true.** In `main()` the acceptance runs when `accept and not probs and eprobs`. Lock-side problems (`eprobs`) are not refused; the acceptance overwrites them. A lock body edited by hand is rewritten from the manifest. A **symlinked lock is replaced** by a regular file and accepted. Measured in a worktree of fu_c, with the lock replaced by a symlink to an outside copy:
  ```
  --verify-manifest                                -> rc 3, "... full_suite_excluded.lock is a symlink ..."
  --verify-manifest --accept-excluded-change i@mvasic.ru
                                                   -> rc 0, "accepted the excluded set (55 row(s)) as i@mvasic.ru", RESULT: MANIFEST-OK
  ls -l config/full_suite_excluded.lock            -> -rw-rw-r-- (regular file; a new # accepted line appended)
  ```
  This also contradicts guide line 85, which is pre-existing and not in this diff: "A symlink is refused (`--accept-excluded-change` and `--verify-manifest` exit 3...)". That holds for the roster only, not the lock. The impact is low: the replacement shows up in git as a typechange, and the outside target is untouched. What the code really refuses at acceptance time: verify() problems, a roster problem or an id that is not rostered, and broken acceptance lines (`acc_problems`). Follow-up: either reword both guide sentences to state exactly that, or (separate source item, test-first) make `excl_accept` refuse a symlinked lock with exit 3 and add a test case to section 37.
- **F-C (nit, process-doc). Stale body sentences.** CON-189, CON-190 and CON-191 now have Status Ready for testing, but their bodies still say "No fix is claimed: the item is Queued ... neither PROVISIONAL-DONE ...". The appended Fix/Verification lines contradict this. Follow-up: amend the sentence to say it applied at registration.
- **F-D (nit). CON-188 does not record that N2 is resolved.** Add: CON-144 (fc57ad0c) made `CM-GATE-ENV-READS-ALLOWLISTED` PASS with uncovered=0. Only N1 (the CHANGELOG decision) remains open.
- **F-E (nit, process-doc). Two guide sentences say slightly more than the record of 2739c26b.** (1) "The acceptances recorded so far were run by the landing agent". The 2739c26b message only says "relayed by the conductor"; the agent run shows only in Co-Authored-By. (2) "None was typed by the operator in person". The record states this for bdc3ac43 and e6b16598, but 2739c26b says nothing about who ran it. (3) "What the record supports is: the change and the acceptance were made by one agent". Only e6b16598 contains both the change (manifest rows) and the acceptance. 2739c26b and bdc3ac43 only touch the lock. Follow-up: scope the sentences to e6b16598, or say "for 2739c26b the message does not name who ran it".
- **F-F (nit, test hygiene). Mutant id namespace.** The harness has no check for duplicate ids, so a duplicate row runs silently twice. I hit this with Z7. Optional: refuse duplicate ids in `test_run_full_suite_mutations.sh`.
- **F-G (nit). The bundle ref is `HEAD`.** It is fine, but a named ref (`fu_c`) would make `git fetch bundle fu_c` work as described.

No sentence in the changed guide text says verified, independent or human where the record shows only an agent or a relayed order. "genuine operator message" is quoted from the bdc3ac43 message itself.

## Not checked
- The full suite (`run_full_suite.sh --include-heavy`).
- The whole mutation file (only F47d, F47e and my mutants were run).
- Z1, Z2 and Z7' against main's suite.
- The census closure test that CON-188 N2 also names.
