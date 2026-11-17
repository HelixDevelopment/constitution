# land_vehicle.sh review round 6 (structural, §11.4.276(E))

| Field | Value |
|---|---|
| Item | CON-PENDING-LANDER |
| Status | PROVISIONAL (§11.4.290): needs its round-7 independent review |
| Evidence class | gate logic only (§11.4.289 clause C(2)): local bare remotes and fixtures, no real upstream, no network |
| Author | fixer subagent, Opus 5.5; reasoning effort UNKNOWN (not settable or readable on this dispatch path) |
| Base | bundle `land_vehicle_r5.bundle`, head a13919e3 (round 5) |
| Review answered | `review_lander_r5.md`, verdict NO-GO |
| Date | 2026-11-14 |

## Findings and how they are closed

| Finding | What changed | Proof (RED on the old lander, GREEN on round 6) |
|---|---|---|
| R5-C (xtrace and startup channels leak URLs) | `set +x +v` is the first statement; then the script re-runs itself once in a clean `bash --norc --noprofile` with every class-C variable removed (`SHELLOPTS`, `BASHOPTS`, `BASH_ENV`, `ENV`, `PS4`, `BASH_XTRACEFD`, 11 more names, and every exported function: 17 names in all); a leftover member exits 2. Whole class: `env_census.md` | R6-C0 (control: the token is visible to a traced shell), R6-C-shellopts, R6-C-bashenv, R6-C-bashx (108/108/99 token lines on r5, 0 on r6), R6-C4, R6-C4b, R6-C4 control, R6-C5-dashO, R6-C5-bashopts |
| R5-A2 (a folded trailer hides the id) | the commit-object newness check is a case-insensitive substring search over every reachable commit object, not a `^Roadmap-Item:` line match | R6-A2 folded, case, spacing, mention, control |
| R5-A1 (the header claimed folded values are refused; they were kept) | `folded_ri`: a Roadmap-Item line followed by an indented, non-blank line is refused at prepare and at publish (git's own parsing was measured: `git_folding_measurement.txt`) | R6-A1-emptykey, R6-A1-continued, R6-A1p, R6-A1 control; R5-RM08 (a whitespace-only separator is not a fold) |
| R5-B (tracker newness at main only) | tracker-path blobs of main AND of every unpushed vehicle commit are searched, case-insensitively, with any leading zeros. Whole class: `newness_census.md` | R6-B tip, removed, case, case at main, control |
| R5-D (verify trusted the current local main) | `verify` runs `check_state`, requires local main to contain `main_before` and the landed vehicle head, and every remote to hold the landed head (new read-back column `landed_on_remote`) | R6-D1, R6-D2, R6-D2 control, R6-D3 |
| R5-I (SIGPIPE ended the suite) | the R5-N3b FAIL branch no longer pipes `find` into `head` | the full suite against the round-4 lander now ends with a RESULT line (`runs/red_r4_full.log`), not status 141 |
| R5-F (clone-path race) | the clone directory is created with `mkdir`, entered with `cd -P`, its resolved path and inode recorded; `git init .` runs inside it; afterwards the path must still be a directory with the same inode and not a symlink | R6-F (a PATH shim swaps the path for a symlink at `git init`) |
| R5-G (test gaps) | new tests for `url.*.pushInsteadOf`, xtrace and `BASH_ENV`, and a non-UTF-8 commit encoding | R6-G1 (with its control), R6-C-*, R6-G3 (G1 and G3 also pass on r5: they guard, they do not show a defect) |
| R5-H (mutant labels) | `mutant_table.md` now separates KILLED (the outcome differs) from EQUIVALENT-OUTCOME (only the message differs), and reclassifies round 5's F1i and X5 | `mutant_table.md` |

## Honest limits

* A `BASH_ENV` file runs the caller's own code before the lander's first line. The lander
  stops accidental leaks and inherited options; it is not a defence against a hostile
  caller environment.
* Newness member B10 (tracker files of older main commits) is scoped out (`newness_census.md`).
* The clone-path race is shown with a test double for the race (a PATH shim on `git`); the
  real race window was not measured.
* All evidence is local gate-logic evidence. No real upstream was pushed, no network was used.

## Results (this session, captured in `runs/`)

| Run | Lander | Result |
|---|---|---|
| round-6 tests only, RED | round 5 (`land_vehicle_r5.sh`, sha256 a12f02ab…, the reviewed artifact) | pass 15, fail 25 (`runs/red_r6only.log`) |
| round-6 tests only, GREEN | round 6 before the RM08 fix | pass 40, fail 0 (`runs/green_r6only.log`) |
| full suite, GREEN run 1 | round 6 before the RM08 fix | pass 330, fail 1: R5-RM08 found a regression in `folded_ri` (a whitespace-only line was read as a fold); fixed at the root cause, measured against git (`git_folding_measurement.txt`), guarded by mutant M15 |
| full suite, GREEN runs 2, 3, 4 | final round 6 | pass 331, fail 0, each; canonical PASS/FAIL/RESULT hash `1193fecf…2e43` identical in all three (`runs/determinism.txt`; ids, paths and times masked) |
| full suite, RED | round 4 (sha256 e3c86345…eddc6) | pass 235, fail 96, and the suite reaches its RESULT line (R5-I: no SIGPIPE exit) |
| own mutants | final round 6 | 15 mutants: 10 KILLED, 1 EVIDENCE-ONLY, 3 EQUIVALENT-OUTCOME, 1 SURVIVED (equivalent); `mutant_table.md` |
| shellcheck (warning level) | lander and test | 0 findings (`runs/shellcheck.txt`, re-run on the final files) |

Final files: `scripts/release/land_vehicle.sh` sha256
73c902b8a914abc405d7f0de0d56868931fcbc62e2f1459ba5171129665f04d8,
`tests/release/test_land_vehicle.sh` sha256
203d2171c46d9c992e70d66e7cf4948b7ac99b28f5fe6a70466d9964707a12f7. These are the bytes
the GREEN runs 2 to 4 executed. Runs used `systemd-run --user --scope -p TasksMax=1500
nice -n 10`, at most 2 at a time, on local bare remotes under a scratch directory.
