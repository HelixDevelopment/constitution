# Independent review: vehicle/redpin, round 2 of 5

| Field | Value |
|---|---|
| Subject | vehicle/redpin head `ce775c90779b11776df1f22c104481a477954e90`: `2ca4d1b` (round 1), `d0b4527` (merge of main `7f72395`), `e2bc751` (round-2 fix), `74ec842`, `ce775c9` (tracker CON-064/065) |
| Bundle | `redpin_r2.bundle`, sha256 `9fc4c30af1fca8243e6b11ea562dcc8c6c57afe2ae335537c76bdaf15a8a8f4f` (checked), `git bundle verify` OK, prerequisite `7f72395` |
| Main used | `7f72395` (the vehicle's merge base) and, after the coordinator's message, `ecfe4325dc449a0e0593d0d1afa177bfb7f63987` (census-safe landed), fetched read-only from the local canonical checkout |
| Anchors | §11.4.142 / §11.4.209 review, §11.4.276(G) round budget (round 2 of 5), §11.4.235(D) per-slice verdict, §11.4.54 id uniqueness |
| Reviewer | independent subagent, model Opus (claude-opus-5-5); effort cannot be set or read on this dispatch path, so none is claimed (§11.4.231(F.2)) |
| Sandbox | throwaway root `/home/milosvasic/.cache/claude-tmp/rvr2.szvAmF` (mktemp -d, HOME and TMPDIR inside it, removed after the review with safe_rm_rf) |
| Evidence | `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/review_redpin_r2_evidence/` (`SHA256SUMS` inside) |

## Verdict

This review covers two slices, so the verdict is recorded per slice (§11.4.235(D)).

| Slice | Commits | Verdict |
|---|---|---|
| A. Code and tests | `e2bc751`, `74ec842`, the merge `d0b4527` | **GO-with-follow-ups** |
| B. Tracker | `ce775c9` | **NO-GO** |
| Landing on main `ecfe432` | the whole vehicle | **NO-GO until R1 is done** |

**Slice A.** Both blocking findings of round 1 are fixed:

- F1: the census guard passes on its own committed tree.
- F2: the RED legs no longer depend on what else runs on the host.

The 8 round-1 detector shapes are adopted as mutation legs and every one is killed. Every finding still open in slice A is minor or nit. Under §11.4.276(G.2) the code loop ends here, and those findings become tracked follow-up items.

**Slice B.** Main `ecfe432` landed after this vehicle was cut, and it already owns CON-064 to CON-069. The vehicle's CON-064 (dash `shift`) and CON-065 (vendor the RB-05 mock) reuse two ids that main holds for different items. That violates §11.4.54 and makes the merge conflict in the database (finding R2-1, important). The tracker commit must be redone.

**R1 (required before landing).** On top of `ecfe432`:

1. Merge `ecfe432` into the vehicle.
2. Take main's `docs/workable_items.db`, `docs/Issues.md` and `docs/Issues_Summary.md`.
3. Re-mint the two items through the engine as the next free ids. At `ecfe432` those are CON-070 and CON-071; re-check at landing in case main moves again.
4. Regenerate the Issues documents from the database. No hand edits.
5. Regenerate the runner-guide census line with `--sync-guide`. I measured 821.

Commit `ce775c9` stays in history; no history is rewritten (§11.4.113). The re-mint commit should say that it supersedes the ids `ce775c9` named.

The check of R1 is narrow:

- engine `validate` and `diff`;
- the ids are unique against main;
- census line 821;
- the manifest problem set equals `ecfe432`'s.

That check does not re-open slice A.

## What I verified, and the results

All runs are from a fresh clone, on the committed tree. HOME and TMPDIR point into the sandbox.

### V1. F1: the census guard passes on its committed tree

`bash tests/test_no_head_red_builder.sh` exits 0 with `PASS=6 FAIL=0`:

- 681 files scanned;
- the positive control flags all 5 instances at `8e496db`;
- the negative control flags nothing.

`tests/test_no_head_red_builder_mutations.sh` gives `PASS=13 FAIL=0` (36 s wall time, under CPU pressure of about 46 to 56 %).

On the throwaway merge with `ecfe432` both results are the same: rc 0, 681 files, and 13/0.

Evidence: `census.out`, `census_mut.out`, `merge_census.out`, `merge_census_mut.out`.

### V2. F2: the RED legs are carrier-immune

I started a carrier process whose command line reads `claude -p redpin-carrier ... --output-format stream-json` and contains the build token. With it running, both pid_status and supervisor_wiring pass every leg, with and without the RED phase.

| Carrier set-up | pid_status (RED / all) | supervisor_wiring (RED / all) |
|---|---|---|
| One carrier | 12/0, 14/0 | 9/0, 23/0 |
| Four carriers (worker cap) | 12/0, 14/0 | 9/0, 23/0 |

My mutant `m_block` deletes the `CARRIER_IMMUNE` block, which restores the pre-RB-02 patterns. It is killed:

- pid_status: FAIL 6, with RED(C2) "recorded pid () ..." and RED(C3) "live_count ... got 0";
- supervisor_wiring: FAIL 3, with `spawn_rc=2`.

Evidence: `carrier1.summary`, `carrier4w.summary`, `car1b_*`, `car4w_*`.

### V3. RED before, GREEN after, same command

**GREEN after.** The five tests at head pass:

| Test | Count |
|---|---|
| orchestrator_reconcile | 16/0 |
| orchestrator_reconcile_rc | 34/0 |
| sessions_argparse | 46/0 |
| sessions_pid_status | 25/0 |
| supervisor_wiring | 31/0 |

- Under `sh` (dash) with the mock: all rc 0.
- Under `bash` with the mock: all rc 0.
- Without the mock: the three non-mock tests are rc 0, and the two mock tests are rc 77 with the reason `rb05_mock_absent`.

On the merge with `ecfe432`, with the mock, all five are rc 0 with the same counts.

**RED before.** With the pre-fix artifacts in place, every test exits rc 1. Each count includes the one control leg that reports the pre-fix artifact; every other failure is a behavioural GREEN failure, not a setup error:

| Test | FAIL count (m0 and both, control leg included) |
|---|---|
| orchestrator_reconcile | 7 |
| orchestrator_reconcile_rc | 13 |
| sessions_argparse | 31 |
| sessions_pid_status | 9 |
| supervisor_wiring | 10 |

Evidence: `head_*.summary`, `head_*_*.out`, `redbefore.summary`, `redbefore_*.out`, `merge_mock.summary`.

### V4. The 8 round-1 shapes are adopted

The census mutation test carries a leg for each of the 8 shapes I reported in round 1:

- `r1-option`, `r1-at-alias`, `r1-fd1`, `r1-two-step`, `r1-rev-parse`, `r1-archive`, `r1-py-fstring`, `r1-untracked`.

Each mutant is killed, and the census names the added line. It also has the `own-file` leg, the round-1 F1 regression. This satisfies §11.4.276(D) for the round-1 mutants.

### V5. rc 77 semantics, and how the runner judges them

`scripts/multitrack/test_multitrack_redpin_mutations.sh` has two outcomes:

- With the mock: `PASS=27 FAIL=0`, rc 0.
- Without the mock: `PASS=12 FAIL=0 SKIP=3`, rc 77, with the trailing line `SKIP: 3 leg group(s) skipped reason=rb05_mock_absent`.

The runner's `judge()` maps each case this way:

- rc 77 becomes `SKIP` with reason `rb05_mock_absent`;
- rc 0 with the mock becomes `PASS`;
- rc 93 becomes `FAIL rc_93`.

Round-1 F4 is fixed, but its fix has no regression guard; see R2-6.

Evidence: `redpin_mut_mock.out`, `redpin_mut_nomock.out`, `rm3_judge.out`.

### V6. F9: deletes go through safe_rm_rf

The five tests remove `$WORK` through `bash -c '. safe_rm.sh && safe_rm_rf "${2:?}"'`, which also works when the test runs under dash. After every run in this review, the sandbox TMPDIR held only the directory of the layout test that was running at that moment: no `mt_*` and no `redpin*` directory was left behind.

### V7. F5: UNIT-CLASS labelling

pid_status and supervisor_wiring now state in their headers that verdicts produced through the RB-05 mock are UNIT-CLASS (§11.4.289).

### V8. F6, F7, F8, F10

- **F6:** the report's attribution of outside writes is corrected.
- **F7:** `e2bc751`, `74ec842` and `ce775c9` carry `Roadmap-Item: CON-054`. CON-054 was registered on main in `eabcfe0`. `2ca4d1b` keeps its placeholder, which is history and correctly not rewritten.
- **F8:** `CTRL_REV` is the full 40-character sha.
- **F10:** the runner guide now states that the default tier needs full history. On a shallow clone the tests fail closed with rc 93, and the census fails closed with rc 1, because the positive control's revision is unreachable.

### V9. Manifest problems

| Tree | Problems |
|---|---|
| Vehicle at `7f72395` base | 26 problems, identical to main `7f72395` |
| Main `ecfe432` | 25 problems |
| Throwaway merge of the vehicle with `ecfe432` | 25 problems, identical to `ecfe432` |

After `--sync-guide` on the merge, the census line is `total=821`: `ecfe432` has 818, and the vehicle adds 3.

Evidence: `vm_*.sorted`, `vm2_merge.sorted`, `vm2_main2.sorted`, `merge_syncguide.out`.

### V10. Main's new env gate stays green on the merge

`CM-GATE-ENV-READS-ALLOWLISTED` gives `VERDICT: PASS` with the same counts on `ecfe432` and on the merge:

- gates=187, reads=170, guarded=54, allowlisted=116;
- uncovered=0, stale=0, needle=ok.

### V11. The merge `d0b4527` dropped nothing

`git diff 8e496db 2ca4d1b` and `git diff 7f72395 d0b4527` differ only in the generated census line and in blob hashes. There are no conflict markers in the tree.

### V12. Tracker through the engine (apart from the collision)

- `validate` passes.
- `diff` and `sync db-to-md` are byte-identical to the committed documents.
- Only the 2 new items were added.
- CON-047 and CON-048 were not reused.

The collision with main is R2-1.

### V13. Parse and lint

- `sh -n` and `bash -n` are clean on the five tests.
- `bash -n` is clean on the other four changed scripts.
- `shellcheck -S error` exits 0 on all nine.

### V14. Out-of-scope edit

`tests/layout/test_generator_atomic.sh` changes only by a trailing comment. With the comment stripped, the file is byte-identical to main.

The commit carries the `Out-of-scope:` trailer with the reason `fix-gate-or-test` (§11.4.293(A)).

## Findings

| Id | Severity | Layer | Slice | Summary |
|---|---|---|---|---|
| R2-1 | important | process-doc | B | CON-064/065 collide with main `ecfe432` |
| R2-2 | minor | test-instrumentation | A | third self-carrier: TMPDIR inside `tests/` |
| R2-3 | minor | test-instrumentation | A | surviving reviewer mutant RM-1 (census file filter) |
| R2-4 | minor | test-instrumentation | A | 18 runner-run sh/py units outside the census scope |
| R2-5 | minor | test-instrumentation, process-doc | A | 25 detector blind-spot shapes; header overclaims Python |
| R2-6 | minor | test-instrumentation | A | surviving reviewer mutant RM-3 (F4 fix revert) |
| R2-7 | minor | process-doc | B | CON-064 body is short of §11.4.148 / §11.4.292 |
| R2-8 | nit | process-doc | A | RM-2: worker half of `CARRIER_IMMUNE` is an equivalent mutant |
| R2-9 | nit | test-instrumentation | A | carrier control needle is tautological |
| R2-10 | nit | process-doc | A | stale "measured 5.6 s" manifest note |
| R2-11 | nit | test-instrumentation | A | carrier is visible host-wide for about 40 s |

### R2-1. Tracker ids collide with main

**Severity:** important. **Layer:** process-doc (§11.4.54, §11.4.214 never-reuse). **Slice:** B.

At `ecfe432` the ids already belong to other items:

- `CON-064` is "CON-047 census FU-1 (R3-1, R3-2) ...".
- `CON-065` is "CON-047 census FU-2 ...".
- CON-066 to CON-069 are also taken.

The vehicle's `ce775c9` uses the same ids for different items. The database rows show it directly: the `items` table holds `CON-064|CON-047 census FU-1 ...` on main and `CON-064|multitrack_sessions.sh: 'shift ...` on the vehicle.

A test merge of `ecfe432` into the vehicle conflicts in four files:

- `docs/Issues.md`;
- `docs/Issues_Summary.md`;
- `docs/workable_items.db` (binary);
- the generated census line of `docs/guides/full_suite_runner_guide.md`.

The minting itself was correct when it was made, because main was then at `7f72395`. The collision comes from concurrent landing. The general lesson is to mint ids after the final merge of main, at landing time (§11.4.288(B)(3)).

The only references to the two ids are in the tracker files and in the subject of `ce775c9`. No code or comment cites them.

**Fix:** R1 above.

Evidence: `merge_ecfe432.out`, `con_ids_collision.txt`.

### R2-2. Third self-carrier of the census guard

**Severity:** minor. **Layer:** test-instrumentation. **Slice:** A.

This is the same class as round-1 F1, now appearing for the third time.

The guard writes its `ctrl_*.sh` positive-control copies into `$S`, and only then builds the census list. When TMPDIR points to a non-ignored directory under `tests/` in the checkout, the census scans its own control copies. It then flags 7 lines and exits rc 1. I reproduced this with `TMPDIR=tests/tmpx`.

The default TMPDIR does not trigger it, so the default tier is green.

**Fix:** build the census list before writing the controls, exclude `$S` from the list, or refuse a scratch directory inside `$ROOT`. Add a leg that runs the guard with TMPDIR inside `tests/`.

Evidence: `selfscan_tmpdir.out`.

### R2-3. Surviving reviewer mutant RM-1: the census file filter

**Severity:** minor. **Layer:** test-instrumentation. **Slice:** A.

RM-1 deletes the `|_mutation_test\.sh$` alternative from the census `grep -E` filter. The mutant survives the whole census mutation suite with 13/0, while the scanned set shrinks from 681 to 489 files.

I then appended a builder line to `scripts/gates/cm_agent_type_label_mutation_test.sh`:

- the unmutated guard catches it, rc 1, naming line 298;
- the RM-1 guard passes it, rc 0, with 489 files.

Under §11.4.276(D), adopt RM-1 as a leg: a builder appended to a `scripts/gates/*_mutation_test.sh` must be named.

Evidence: `rm1_demo.out`, `rm_census_scope_mutsuite.out`.

### R2-4. Census scope is narrower than the runner's census

**Severity:** minor. **Layer:** test-instrumentation. **Slice:** A.

18 shell and Python units that the full-suite runner runs are never scanned by the guard. The guard's name filter misses these patterns:

- `*_test.sh` suffix files, for example the five `scripts/gates/covenant_propagation_*_test.sh` files;
- `*_selftest*.sh` files;
- `prove_*mutations.sh` files under `scripts/label-sync/`;
- other names, such as `meta_test_inheritance.sh` and `progressive/mutation_matrix.py`.

Any of them could gain a HEAD-built RED artifact without the census noticing.

**Fix:** scan the runner's own census set, the same file list `--verify-manifest` uses, instead of a second name filter.

Evidence: `manifest_units_outside_census.lst` (28 entries: 18 sh/py, plus 5 js and 5 Go package directories, which are out of language).

### R2-5. Detector blind spots: the class is still closed one instance at a time

**Severity:** minor. **Layer:** test-instrumentation, plus process-doc for the header. **Slice:** A.

I wrote 25 new probe shapes, all different from the 8 of round 1. The detector, extracted byte-identical from the committed heredoc, misses all 25. It flags both positive controls and does not flag the negative control.

Shapes that the header's "NOT covered" list does not declare:

- process substitution executed or copied: `bash <(git show HEAD:..)`, `cp <(..)`, `. <(..)`;
- defaulted revisions: `"${RED_REV:-HEAD}:x"`, `REV=${REV:-HEAD}`;
- the index form: `git show :path`;
- an implicit HEAD: `rev=$(git log -1 --format=%H)`;
- the moving refs `main:` and `origin/main:`, which fail in exactly the same way once the fix lands;
- `git checkout HEAD --` and `git restore --source=HEAD`;
- `git worktree add ... HEAD~1`;
- a heredoc body;
- a git wrapper function or variable (`gitc`, `"$GIT"`);
- `HEAD@{0}`;
- a prefix redirect: `> f git show HEAD:x`;
- `cat-file --textconv`;
- Python `shell=True` strings and `os.system`;
- Python string concatenation: `"HEAD" + ":" + p`.

Header line 19 says "Python tests: any show/cat-file HEAD blob read". Three of my shapes contradict that claim, so line 19 overclaims.

No such shape is live today. My own broad scan of the whole tree, with a control, finds 3 hits, and none of them builds a RED artifact.

The round-2 fix closed exactly the 8 named shapes. That is the instance-at-a-time closure §11.4.276(C) warns about.

**Recommended structural follow-up:** invert the default. Flag every HEAD-relative, moving-ref or index read of a blob or tree in a test, whether or not it is written to a file. The existing reason-carrying opt-out marker then covers compare-only reads. Correct the header to list the real limits.

If this class comes back in a later round, it is a reappearing finding, and §11.4.276(E) would force a structural round.

Evidence: `shapes_probe.tsv`, `shapes/`, `alltree.hits`.

### R2-6. Surviving reviewer mutant RM-3: the F4 fix has no guard

**Severity:** minor. **Layer:** test-instrumentation. **Slice:** A.

RM-3 deletes the `if [ "$SKIP" -gt 0 ] ... exit 77` block from the redpin mutation suite, which reverts the round-1 F4 fix. I ran the mutant without the mock. Its output is `PASS=12 FAIL=0 SKIP=3` with rc 0.

The runner's real `judge()` returns `('PASS', '', 'summary', {'p': 12, 'f': 0, 's': 3})` for it. The unmutated suite gets `('SKIP', 'rb05_mock_absent', 'exit-code', None)`. The run-level `PARTIAL-SKIPS` counts unit-level SKIPs only. So the revert silently turns three skipped leg groups back into a PASS, and nothing catches it.

**Fix:** adopt RM-3 as a leg. Run the suite with the mock absent and assert rc 77 and the trailing `reason=` line.

Evidence: `rm3_mutant_nomock.out`, `rm3_judge.out`.

### R2-7. CON-064 body is short of §11.4.148 and §11.4.292

**Severity:** minor. **Layer:** process-doc. **Slice:** B.

This should be folded into R1.

- CON-064 has no acceptance section and no reproduction section.
- Its `reproduction_state` and `investigation_state` are both `UNSET`. Yet the dash `shift` defect was reproduced live: under dash, the no-argument call prints nothing, while bash prints the usage text.
- Its body cites `scratchpad/review_redpin.md`, a path outside the repository and not durable (§11.4.215).
- `item_history` attributes both items to `User`.
- The author's report says the items were created through `report_item.sh`, but CON-064's shape does not match that path.

**Fix:** when re-minting, fill the reproduction record with an in-repository evidence path, add the acceptance criteria, and record the real creator.

Evidence: `c64_sh.out`, `c64_bash.out`.

### R2-8. RM-2: the worker half of `CARRIER_IMMUNE` is an equivalent mutant

**Severity:** nit. **Layer:** process-doc. **Slice:** A.

`m_worker` restores the worker pattern to the pre-RB-02 default and keeps the build half. It passes every leg, with one carrier and with four carriers. The reason is that sessions passes its own live-worker count, so the worker pattern is not on this path.

The block comment says the worker half is needed, which overclaims. Either reword the comment or drop that half.

Evidence: `car1b_mworker_*`, `car4w_mworker_*`.

### R2-9. The carrier control needle is tautological

**Severity:** nit. **Layer:** test-instrumentation. **Slice:** A.

In the redpin mutation suite, the control that proves the carrier is visible reuses the same `_bw` token it is checking for. Prove visibility with an independent read instead, for example `pgrep -f` of the real pre-RB-02 build pattern.

### R2-10. Stale manifest timing note

**Severity:** nit. **Layer:** process-doc. **Slice:** A.

The manifest row of the census mutation test says `override: fast (measured 5.6 s ...)`. I measured 36 s wall time, although that was under CPU pressure (load about 33 on 16 CPUs). Record the figure together with the load it was measured under.

### R2-11. The carrier is visible host-wide

**Severity:** nit. **Layer:** test-instrumentation. **Slice:** A.

For about 40 s the carrier process is visible to every bare-`pgrep` guard on the host. It could make another session's guard count it.

**Fix:** if `unshare --pid --fork --map-root-user` is available, run the carrier inside its own PID namespace, or keep its lifetime as short as possible.

## Observation outside the vehicle's scope (not a finding against it)

**O1.** `tests/layout/test_generator_atomic.sh` failed in my first vehicle run, with `PASS=55 FAIL=2`, rc 1, in 11 m 56 s. The two failures are SIGTERM legs:

- `(4) staging left after SIGTERM (had 6)`;
- `(10e) TERM at mid_commit lost files or left staging`.

On main `7f72395`, run concurrently, leg (4) passed. The vehicle's change to this file is comment-only (V14), and the generator and its inputs are unchanged. So the same behaviour gave different verdicts, which means these legs are nondeterministic on this host.

The cause is UNCONFIRMED. CPU contention is a hypothesis only: CPU pressure was about 56 % avg10 at the time.

Results of the comparison runs:

| Run | Result |
|---|---|
| Vehicle, first run | `PASS=55 FAIL=2`, rc 1, 11 m 56 s |
| Main `7f72395`, concurrent | `PASS=57 FAIL=0`, rc 0, 11 m 09 s |
| Vehicle, re-run of the same committed file | `PASS=57 FAIL=0`, rc 0, 9 m 16 s; both SIGTERM legs passed |

The same file on the same tree therefore gave both verdicts. The nondeterminism is shown on the vehicle itself, and these runs do not implicate the vehicle.

This should be a tracked item through §11.4.202, outside this vehicle (§11.4.293(A)).

Evidence: `gen_atomic.out`, `gen_atomic_main.out`, `gen_atomic_rerun.out`.

## Required for landing

1. **R1 / R2-1:** re-mint the two tracker items on top of `ecfe432` through the engine, as described in the verdict. Fold in R2-7.

## Follow-ups (§11.4.276(G.2))

Register these as tracked items:

- R2-2: the self-carrier with TMPDIR inside `tests/`, plus a leg for it.
- R2-3: adopt RM-1 as a leg.
- R2-4: scan the runner's census set.
- R2-5: invert the detector's default and correct the header.
- R2-6: adopt RM-3 as a leg.
- R2-8 to R2-11: the nits.

## Reviewer mutants written in this round (not written by the author)

| Mutant | Change | Result |
|---|---|---|
| `m_block` | delete the `CARRIER_IMMUNE` block | killed (pid_status FAIL 6, supervisor FAIL 3) |
| RM-1 | drop `\|_mutation_test\.sh$` from the census filter | survived 13/0; misses a gate mutation-test builder (R2-3) |
| RM-2 (`m_worker`) | restore only the worker pattern | equivalent (R2-8) |
| RM-3 | delete the SKIP-to-77 block | survived; judged PASS (R2-6) |
| 25 shape probes | new builder shapes `n1` to `n25` | all missed (R2-5) |

## Not claimed

- I did not run the whole full suite.
- The ids CON-070 and CON-071 are the next free ids at `ecfe432` only. Main may move again before landing.
- Whether `ecfe432` has been pushed to every upstream was not checked; it is UNCONFIRMED.
- The cause of O1 is UNCONFIRMED.
- Behaviour on other hosts was not measured.
