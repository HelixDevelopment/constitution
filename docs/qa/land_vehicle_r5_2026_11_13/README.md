# land_vehicle.sh round 5: evidence

| Field | Value |
|---|---|
| Created | 2026-11-14 |
| Status | fixer evidence, awaiting independent review (no GO is claimed) |
| Lander | `scripts/release/land_vehicle.sh` sha256 `a12f02ab2bbcc17eb8fb0f389c11b527a0662c25ec04b929c7395f6a3fa391f7` (1199 lines) |
| Test | `tests/release/test_land_vehicle.sh` sha256 `80c16d24e26fc9c69ff24db5d0daa1a752ab17cba51be2bb2eb99678362265ac` (1996 lines) |
| Round-4 inputs (RED) | lander `e3c86345401507cf093d56ad311faf78a29ffe9bd7438cd21672ed07247eddc6` (= `c0a3a8bc:scripts/release/land_vehicle.sh`), review `review_land_vehicle_r4.md` (NO-GO, F1-F13) |
| Rule | §11.4.276(C) and (E): the classes were inventoried first (`class_inventory.md`), then closed member by member |

All runs are hermetic. The remotes are local bare repositories only. There is no network: the only ssh remote (S08) uses a fake `GIT_SSH_COMMAND` that prints its arguments and exits 255. No forge was contacted and nothing was force-pushed. The live checkouts were not touched.

Every heavy run ran in its own `systemd-run --user --scope -q -p TasksMax=2000` scope under `nice -n 10`, with at most 2 runs at a time. The host had 16 cores and a load average of 85-90 from other work during the s3 runs and 35-37 during the last s4 runs, so timing is not asserted anywhere.

The final files were run from a frozen snapshot (s4, byte-equal to the committed lander and test: `final/driver.txt`), because bash reads a script while it runs. The earlier snapshot s3 differs only by the 12 lines of R5-N3b in the test; its three green runs (291/0 each, one canonical hash) and its RED run are kept in `final/s3_superseded/`.

## Results (final files)

| Run | Result | Where |
|---|---|---|
| GREEN x3, final test on the final lander | rc=0, pass 292, fail 0, each run | `final/green_run{1,2,3}.log` |
| GREEN determinism | the canonicalised PASS/FAIL/RESULT lines have sha256 `79e8e3d63a23a4a7658ce550efe0b7f5ac2a016f33fbf9a26e8728b40dff3f1b` in all 3 runs | `final/driver.txt`, `final/*.canon` |
| RED, final test on the round-4 lander | rc=1, pass 222, fail 70: 51 are round-5 cases (R5-*); 19 are round-4 cases whose expectations the round-5 fixes changed (SH0, SH1, SH1b, SH2, SH2-R5, S3, S5g-b, X8b x3, U10 x2, V4, U12, V15 x4, V16; V16 because `core.attributesFile` is now pinned, the in-tree case is V16c). The s3 test gave 222/69 on the same lander; the one extra FAIL is R5-N3b | `final/red_round4_lander.log`, `final/s3_superseded/red_round4_lander.log` |
| Own mutants | 61 generated: 55 killed (53 by the assertion on the intended behaviour, 2 by a later check with another message), 6 survived, each with an equivalence proof | `mutant_table.md`, `final/mut/` |
| The 18 reviewer mutants of round 4 (RM*), part of the 61 | 18 applied to the round-5 code (RM05 and RM23 re-expressed, because the lines they mutated changed), 18 killed | `mutant_table.md` (rows RM*) |
| Adversarial scenarios (`tools/scen_r5.sh`, 9 scenarios, 34 checks) | 3 runs, each pass 34, fail 0; identical canonical sha256 `87ebe2b1de2ff54002d7d20d2b656a0f575c859d4722e70500dbeab9355d6de9` | `scen/scen_run{1,2,3}.log` |
| shellcheck 0.11.0, `bash -n` | clean on the lander, the test and the tools | `shellcheck_bashn.txt` |

### Scenarios: what the server-side loggers saw

Each of the 9 bare remotes has a pre-receive hook that logs every ref update (old, new, create/delete/ff/NONFF, the number of push options). Over all 9 scenarios:

- **0 non-fast-forward updates, 0 deletions, 0 updates of a ref other than `refs/heads/main`, 0 tags on any server, 0 credential leaks.** Control: the loggers recorded 44 ref updates, so they were live.
- S04: a hostile global config (`push.default=matching`, `push.followTags=true`, `push.pushOption=FAKEOPT`, `remote.pushDefault`, `push.recurseSubmodules=on-demand`, plus a local tag and an extra branch in the clone). Only `refs/heads/main` was updated, fast-forward, with 0 push options; 0 tags. Control: a plain `git push` with the same config sends the tag.
- S05: a global `remote.github.push` refspec gives rc 2 before any push.
- S06: a diverged gitverse gives "preflight refused 1 remote" and 0 updates.
- S07: a gitflic post-receive hook commits an UNREVIEWED commit into the clone during the pushes. All 9 servers received the checked sha. The moved main reached 0 servers, publish exits 1, and publish again refuses the unreviewed commit.
- S08 leak scan: every remote path contains `FAKETOKEN`, one remote is an ssh URL `lander@FAKETOKEN-ssh.invalid:...`, a remotes line has three fields, one remote is unreadable and one rejects pushes, and verify runs against a mismatching URL. 0 of 13 output and evidence files hold `FAKETOKEN`. Controls: the clone's own git stderr log (`.git/land_git_stderr.log`, mode 0600) holds it once, so the scan can see it; a planted needle is found; a fabricated needle (`ZZNEEDLE-9f3`) is not; the refused remote is named; the bad line is named by number only.
- S09: a tag object as `--head` is refused, with 0 updates.

The first 3 scenario runs (`scen/*_before_s04_control_fix.log`) failed one check: S04's control push gave 0 tags. Measured cause: the control repository did not advertise push options, so the control push itself failed (`fatal: the receiving end does not support push options`, rc 128); the `|| true` had hidden that. The control now advertises push options like the 9 remotes, and its exit status is recorded. The lander-side half of S04 passed in all 6 runs.

## Findings: closure

| Finding | Severity / class | Fix | Tests | Mutants killed |
|---|---|---|---|---|
| F1 R04: the push used the name `main` | important / source-defect | main is read ONCE (`local_main`); both trailer checks run on it; the push sends `<local_main sha>:refs/heads/main`; the read-back compares with `local_main`; main is read again after the read-back, and "clone main moved during publish" exits 1 | R5-K01 (a commit made in the clone during the pushes), SH0 (exactly one push call site, plus the runtime pushed sha), SH1, SH2; scenario S07 | RM01, F1a, F1b |
| F1 R04/K01: WARN laundering | important / source-defect | only a commit that is an ancestor of `refs/land/main_before` (published before prepare) can be a WARN row; every commit after it must carry one real trailer even when a remote already has it | U10, U10b, R5-K01 (second publish) | F1c (F1h is equivalent, see below) |
| F1 R04b: remotes addressed by name | important / source-defect | `assert_remote` runs immediately before EVERY fetch, ls-remote and push: the fetch URLs (`get-url --all`, so `insteadOf` counts), the push URLs (`get-url --push --all`, so `pushurl` and `pushInsteadOf` count) and every `remote.<name>.*` key in any config file against an allow-list. A refusal inside the push loop names the remotes already pushed | R5-R04b, R5-RB (read-back), R5-F1g (a global `insteadOf` at prepare), R5-RM31, V14 | F1d, F1e, F1f, F1g, RM31 |
| F1 R15: the mint commit compared by name only | important / source-defect | ONE raw record (`diff-index --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none`); every check reads the record's blob ids; `write-tree` diffed against the base is compared with the record byte for byte, then the `commit-tree` result again; `update-ref` is a compare-and-swap on the base; afterwards index and work tree must be clean | V15 (two fault modes: `swap`, the content of a listed path is swapped; `extra`, an extra path is staged), V8d | F1i (message-only, see below) |
| F2: an id re-used through an ADDED file | important / source-defect | newness is checked against EVERY blob at main before the mint whose path matches `LANDER_TRACKER_PATHS` (added, modified and untouched files alike), and against every `Roadmap-Item` line of every commit reachable from main or the vehicle; leading zeros are ignored; a file holding a NUL byte is matched by substring (fail closed). The review's optional idea (refuse status `A` while a tracker file exists) was not taken: the full-tree search covers its cases | R5-F2a (the review's case a), R5-F2b (case b), R5-F2c (vehicle trailers), R5-F2z, R5-F2zh, R5-F2n, R5-RM15 | F2a, F2b, F2c, F2z1, F2z2, F2n, RM03, RM15 |
| F3: tag as `--head`; the placeholder passed the real-id check | important / source-defect | `--head` must be a commit object (`cat-file -t`); the head must be among the re-committed commits; a value matching `--placeholder-re` is refused as the mint's id, as `--item-id`, and in every trailer check | R5-F3a, R5-F3b, R5-F3c, R5-F3d, V3b; scenario S09 | F3a, F3b, F3c, F3d |
| F4: `log.showSignature` corrupted re-commits | important / source-defect | no value is read from `git log` any more: every message and header is read with `cat-file`; a re-commit is written with `hash-object -t commit`, copying every header line byte for byte except parents (mapped) and a signature (dropped and recorded); the stored object is post-checked against the original (header lines, message). `log.showSignature=false` is pinned anyway | R5-F4 (a signed commit with `log.showSignature=true` in the caller config), T2, S3, R5-KEEP | E2 (F4 is equivalent, see below) |
| F5: ambient `push.pushOption` | minor / source-defect | `-c push.pushOption=` (an empty value clears the list) on every git call | R5-F5; scenario S04 | F5 |
| F6: an init template could move the checkout | minor / source-defect | `git init --template=`; `GIT_TEMPLATE_DIR` is removed with every other `GIT_*` name; explicit `--git-dir`/`--work-tree` on every call | R5-F6 | F6 |
| F7: `-h` anywhere in argv | minor / source-defect | `-h`/`--help` is help only where an option NAME is expected; every option value must be non-empty, must not start with `-`, and may be given once | R5-F7, U12 | F7 |
| F8: tests pinned the vulnerable form; three defects had no test | minor / test-instrumentation | SH0 and `push_log_clean` now expect `<sha>:refs/heads/main` with the checked sha; R5-K01 ties the pushed sha to the checked one at runtime; each surviving reviewer mutant now has a test (R5-RM02/04/06/08/10/13/15/23/28/31, R5-F2a and R5-F2c for RM03, R5-F9 for RM25); the added-file id, a tag head, `log.showSignature`, `push.pushOption`, the init template and `-h` as a value each have one (R5-F2a, R5-F3a, R5-F4, R5-F5, R5-F6, R5-F7); V15 has a content-swap mode | the RM* rows of `mutant_table.md` | all 18 RM* |
| F9: tracker pattern `*` accepted | nit / source-defect | a pattern must contain `/` and its first component must be a literal name (not `.`): `*`, `docs`, `*/x` and `./x` are refused at start-up; `..` and absolute paths stay refused | R5-F9 | F9, RM25 |
| F10: CON-0100 accepted next to CON-100 | nit / source-defect | the id pattern is the engine's `%s-%03d` form: `^<KEY>-(00[1-9]\|0[1-9][0-9]\|[1-9][0-9]{2,})$`, so `CON-0100`, `CON-07` and `CON-77` are refused wherever an id is read; newness ignores leading zeros | R5-F10, S5g, S5g-b, R5-F2z | F10, F2z1, F2z2 |
| F11: CRLF remotes file gave a misleading message | nit / source-defect | a control character other than TAB (a CR included) is refused with the line number | R5-F11 | F11 |
| F12: the header contradicted the code in 6 places | nit / process-doc | (1) newness: every tracker file at main plus every trailer, as coded; (2) author name, email and date are kept, now true (raw objects); (3) the clone stays in the workdir, now true (F6); (4) `git init` is listed with the pins it really gets (`core.hooksPath`, `core.fsmonitor`, `core.sharedRepository`); (5) the mint and id-verify commands run in the CLEARED environment, stated the same way in both sections; (6) `git interpret-trailers --parse` runs with no repository and no config (`GIT_DIR=/nonexistent`, no global, no system file) | R5-TC (a caller `core.commentChar` and `trailer.*` do not reach the parser) | X6 |
| F13: CR removed before validation | minor / source-defect | the value is validated exactly as git reports it, with no normalisation: a CR anywhere (`CON-9<CR>05`) is refused | R5-F13 | RM05 (F13, the extra control-character check, is equivalent, see below) |

Three members the review did not report were found by the class inventory, measured, and closed:

| New member | Measured | Fix | Tests | Mutants killed |
|---|---|---|---|---|
| N1: merge strategy from config | `pull.twohead=ours` and `branch.main.mergeOptions=-s ours` each made `git merge` drop the vehicle's content while the merge commit had the right parents; `-s ort` on the command line alone does NOT override `branch.main.mergeOptions` | pins `pull.twohead=ort`, `branch.main.mergeOptions=` (empty) and the other `merge.*` keys; `-s ort` on the command line; an independent oracle: the merge tree must equal `git merge-tree --write-tree` run with no global and no system config | R5-N1 (both settings), R5-N1c (a merge driver from the caller config) | N1c, N1d, N1e (N1a and N1b are equivalent: each removes one of two layers) |
| N2: a gitlink change hidden from the mint record | `submodule.<name>.ignore=all` (config or in-tree `.gitmodules`) hid a gitlink change from both `diff-index` and `diff-tree`, so the record and the compare agreed while the commit carried an unrecorded gitlink | `--ignore-submodules=none` on every `diff-index`, `diff-tree` and `status`; `diff.ignoreSubmodules=none` pinned | R5-N2 | N2 |
| N3: a group- or world-readable clone holding the remote URLs | with a global `core.sharedRepository=world`, `git init` gave `.git` 2775 and `config` 664; and a commit WITHOUT a per-call pin gave 13 entries under `.git` with group or other bits | `umask 077`; `core.sharedRepository=false` on `git init` and on every later git call | R5-N3 (`.git` 700, `config` 600), R5-N3b (no entry under `.git` with a group or other bit after prepare: 0 of 78) | N3a, N3b, N3c |

## Mutants

`mutant_table.md` lists all 61 with the first FAIL line that killed each. The generator is `tools/gen_r5mut.py`; `final/mut/index.tsv` holds each mutant's sha256 and `final/mut/diffs/` the diff of each one against the final lander. Each mutant ran through the whole suite in fail-fast mode (`tools/run_mut.sh`): KILLED means an assertion FAIL line (0 harness aborts), SURVIVED means rc 0 with `RESULT ... fail=0`.

- **Which test file.** All 61 mutants ran against snapshot s3 (`final/mut/logs_s3/`, `results_s3_setA.tsv` 35 + `results_s3_setB.tsv` 26). The s3 test differs from the final one only by the 12 lines of R5-N3b inside the round-5 section (same lander). N3c SURVIVED the s3 test (291/0: R5-N3 checks only `.git` and `config`), which is why R5-N3b was added; N3a, N3b and N3c were then run again against the final test (snapshot s4, `final/mut/logs_s4/`, `results_s4_N3.tsv`), where all three are killed (N3c: 64 of 78 entries under `.git` with group or other bits). The table takes N3a-c from s4 and the other 58 from s3. The 6 survivors were then run through the round-5 section of the final test (s4, `LANDER_TEST_R5_ONLY=1`) and passed it (6 runs, each rc 0, pass 80, fail 0; `final/mut/survivors_s4_r5section.tsv`); the round-4 section is byte-identical in s3 and s4, and they had passed it on s3.
- **Message-only kills (2).** F1i (the first mint compare removed): the second compare sees the identical mismatch and refuses with rc 1 before `update-ref`, with a shorter message. X5 (the re-hash of the bundle copy removed): the changed copy is still refused (rc 1) by a later check; a changed copy that passed those checks would have to contain the commit `--head` names, so it would deliver the same content-addressed objects (this relies on SHA-1DC collision resistance).
- **Equivalent survivors (6), each with its proof in the table.** F1h (the WARN row's ancestor check: implied by the trailer check that runs just before it on the same objects), F4 (`log.showSignature`: no git command the lander runs reads it), F13 (the extra control-character check: `ID_RE` is anchored and admits only `A-Z`, `0-9` and `-`), N1a and N1b (each removes one of two layers that each fix the strategy to ort), X4 (`--literal-pathspecs`: no git call passes a pathspec). These are defence in depth; they were kept, not removed.

## Class of each test (§11.4.289)

- The git side is real: git 2.53, nine local bare repositories as remotes with the real names, real client and server hooks (R5-K01, S07, the scenario loggers), real config files and filters (R5-F1g, R5-F4, R5-F5, R5-F6, R5-N1, R5-N2, R5-N3, R5-RM02, R5-RM31, V16), real flock (U11).
- Test doubles (UNIT-CLASS): the fake mint and verify scripts, a fake gpg, the push-recording PATH shim (SH*), the fault-injection shims of V13 and V15, the fake `GIT_SSH_COMMAND` of S08, and the hooks that move the clone during publish (R5-K01, R5-R04b, R5-RB, S07). Those hooks make the race windows deterministic on purpose; whether such a race happens in real use is UNCONFIRMED.
- The suite and the scenarios are gate-logic evidence for the lander. They are not live proof against any hosting platform, and the real workable-items engine was not run in this round.

## UNCONFIRMED / open

- **The window between a check and the use.** `assert_remote` runs immediately before each operation, but git reads its config again for the operation itself, so a writer that changes the clone's config inside that window is not caught (documented in the header as a boundary). Pushing to the URL from `--remotes-file` instead of the name, as the review suggested, would close it for the URL but not for other `remote.<name>.*` keys; it was not done.
- **The round-4 mutant sets were not re-run.** Applied to the round-5 lander, 47 of round 4's 110 producer mutants and 6 of the 13 round-3 reviewer mutants (MR*) still apply as text (the rest no longer match the changed code). They were not run in this round, for time (each takes one fail-fast suite run). Their round-4 results are in `../land_vehicle_r4_2026_11_13/mutant_table.md`.
- **E5 (encodings) has no suite test.** Only the round-4 reviewer's scenario R13 exercised a non-UTF-8 `encoding` header.
- The real workable-items engine was not run this round (round 4's S_A3b and S_A3c did); the mint side of the suite uses fake mint scripts.
- A safety check of the agent harness refused one read-only probe of mine (a `bash -c` loop that matched control-character strings against the id pattern; it contained no removal). It was not retried in any form. The F13 equivalence rests on the regex argument and on the measured fact that the F13 mutant still refuses `CON-9<CR>05` (R5-F13).
- Timing is not asserted: one full suite run took 18-23 minutes (load 35-90).
- TasksMax=2000 per scope; the scopes' `pids.events` were not captured this round, so whether a scope ever reached its limit is UNCONFIRMED (no run failed with a fork error).
- The round-4 commit (`c0a3a8bc`) carries no `Roadmap-Item` trailer, so there was no id of the round-4 series to keep; this round's commit uses the given `Roadmap-Item: CON-PENDING-LANDER`, which matches the lander's default placeholder pattern (checked against `CON-123` as a negative control).

## Reproduce

```
cd <root holding these two files and scripts/lib/{safe_rm.sh,protected_paths.list}>
TMPDIR=<scratch> systemd-run --user --scope -p TasksMax=2000 -- nice -n 10 bash tests/release/test_land_vehicle.sh [<lander>]
LANDER_TEST_R5_ONLY=1 ...    # only the round-5 cases
LANDER_TEST_FAILFAST=1 ...   # stop at the first FAIL (used for the mutants)
bash docs/qa/land_vehicle_r5_2026_11_13/tools/scen_r5.sh <lander> <dir with safe_rm.sh> <scratch root>
bash docs/qa/land_vehicle_r5_2026_11_13/tools/run_mut.sh <snapshot dir> <mutant dir> <out dir> <name>...
```
