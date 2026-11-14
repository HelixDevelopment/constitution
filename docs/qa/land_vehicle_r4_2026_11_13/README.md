# land_vehicle.sh round 4: evidence

| Field | Value |
|---|---|
| Created | 2026-11-13 |
| Status | fixer evidence, awaiting independent review (no GO is claimed) |
| Lander | `scripts/release/land_vehicle.sh` sha256 `e3c86345401507cf093d56ad311faf78a29ffe9bd7438cd21672ed07247eddc6` |
| Test | `tests/release/test_land_vehicle.sh` sha256 `04761ac6c747b0239be1e6645ada152289d5e2e6df5ead3f18fff5bb077229e4` |
| Round-3 inputs (RED) | lander `74ca0500…`, test `1bf0f5d9…` |
| Reviewer harness used | `rv_lander_r3.KLlS`: `scen/scen.sh` sha256 `c301ac00…` (copied unchanged as `tools/reviewer_scen.sh`), `mut/my_mutants.py` `b96f705e…` (13 MR* ported as `tools/reviewer_mutants_r4.py`) |

All runs are hermetic. The remotes are local bare repositories only. There is no network (S_A19 uses 127.0.0.1:9, which refuses at once) and no forge write. The live checkouts were not touched. Nothing was force-pushed.

Every run ran in its own `systemd-run --user --scope -p TasksMax=3000` scope under `nice -n 10`, one run at a time. Every driver run records the scope's `pids.events max`; it stayed 0->0 for all 3+1+123 runs.

## Results (final files)

| Run | Result | Where |
|---|---|---|
| GREEN x3, final test on the round-4 lander | rc=0, pass 203, fail 0, each run | `final/green_run{1,2,3}.log` |
| GREEN determinism | the canonicalised PASS/FAIL/RESULT lines have sha256 `4347e44651edffe9…` in all 3 runs | `final/driver.txt`, `final/*.canon` |
| RED, final test on the round-3 lander | rc=1, pass 160, fail 43 (only round-4 tests fail) | `final/red_round3_lander.log` |
| Producer mutants | 110 generated, 110 killed, 0 survived | `final/mut_producer/` |
| Reviewer mutants (MR*) | 13 generated, 13 killed, 0 survived | `final/mut_reviewer/` |
| shellcheck 0.11.0, `bash -n` | clean on both files | `shellcheck_bashn.txt` |
| Reviewer scenarios (unchanged scen.sh, 24 scenarios) | all ran (rc=0); outcomes below | `scen/` |

The producer set has 110 mutants: the 85 from round 3 (11 ported because their code moved: PUSH_NEW, M05, M16, X08, N01, N15, N26, Y06, Y20, Y21, Y22) and 25 new round-4 mutants, Z01-Z25. In the reviewer set, MR05 and MR21 were ported because round 4 split their line. All 123 kills are assertion FAILs at a named test; there were 0 harness aborts. `mutant_table.md` lists every mutant with the test that killed it.

An earlier complete run (`run1_before_v8d_v16/`) used the test before V8d, V14, V15 and V16 existed. It killed 106 of 110 producer mutants and 13 of 13 reviewer mutants. Its 4 survivors were Z09, Z14, Z20 and Z23, and each now has a test:

| Survivor | Test added | How |
|---|---|---|
| Z09 | V8d | a deleted file inside LANDER_TRACKER_PATHS |
| Z14 | V14 | a bad name in LANDER_REMOTES |
| Z20 | V15 | a fault-injection shim that stages an extra file just before the mint commit |
| Z23 | V16 | a real git clean filter from global config that strips the id from the staged blob |

All four were re-run against the new tests and killed (`logs/quick_Z*.log`), and the whole final run above includes them.

## Findings: closure

| Finding | Fix | Tests / evidence |
|---|---|---|
| R3-1 credential leak (malformed remotes line echoed) | messages give only the line number; the URL and the line text are never printed | V1 (URL-only line, 3-field line, URL as name, token count 0), V1e; S_A6 leak_in_output=0; S_A19 leak 0/0; mutant Z12 |
| R3-2 inherited git env | the git env is scrubbed before the first git call (fixed list, `GIT_CONFIG_KEY_*`/`VALUE_*`, `GIT_PUSH_OPTION_*`, `GIT_TRACE*`, every `git rev-parse --local-env-vars` name, CDPATH) | V2a-V2g, each with a control needle; S_A28/S_A29/S_A30 (victim repo, worktree and index unchanged); Z01-Z04 |
| R3-3 mint id must be new; token boundaries | the id must be absent from the HEAD blob of every modified tracker file and present as a token in the staged blob; a binary file uses a fail-closed substring match; only A/M on LANDER_TRACKER_PATHS, regular mode; the commit's name-status must equal the recorded one | V3a-V3e, V8a-V8d, V15, V16; S_A3 (rc=1); S_A3b (iii) "CON-001 already appears … not new"; MR03 and MR12 killed; Z08-Z11, Z19, Z20, Z22, Z23 |
| R3-3 real-engine wrapper | the header documents a `sed -n 's/^add: created \(CON-[0-9][0-9]*\) .*/\1/p'` wrapper and says to use a DB copy only | S_A3c: real engine on a DB copy, rc=0, id CON-166, mint commit `M docs/wi.db`; an engine failure (description below the engine's floor) gives an empty last line and rc=1 "did not print an id" (`scen/S_A3c_probe_desc_too_short.log`); source DB sha256 unchanged before and after every run |
| R3-4 header claim; per-remote range | header corrected; a placeholder commit already on some main now gives WARN rows (`publish_warnings.tsv`, a `## warnings` section in publish.md) and does not refuse, so mirrors can still converge | V4 (8 WARN rows, tsv shape), U10; Z18, Z25; S_A11b converges 9/9 |
| R3-5 lock fd | every git child, the mint and verify run with `9>&-` | V5 (fake gpg children, lock free); S_A7 (4 gpg children, 0 hold the lock); Z05 |
| R3-6 follow-tags | the push uses `-c push.followTags=false -c push.recurseSubmodules=no … --no-follow-tags` | V6, SH0 (exact text); S_A8 (0/9 remotes got the tag); Z06 |
| R3-7 untracked files | publish uses `status --porcelain --untracked-files=all` | V7; S_A9 rc=2; Z07, MR05 |
| R3-8 mint name-status | recorded in `mint_changes.tsv` and `mint_commit.txt`; changes outside the tracker paths are refused | V8a-V8d, V8c-T1; S_A21 rc=1 (deletion refused); Z08, Z09, Z22 |
| T-1 kill MR01/02/03/04/08/12/21/22 | tests V9a-V9e, V3c, V3d, V1 | all 13 MR* killed |
| T-2 U11b lock text | the label prints the sorted pair | U11b; MR09 |
| R3-9 option-like --workdir | `--workdir` starting with '-' is refused; `cd --`; CDPATH is unset | V11 ('-' with an OLDPWD decoy, '-Pzz', CDPATH decoy); S_A10; Z16, Z17 |
| R3-10 remote names, dangling symlink, raw rc | names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$` (remotes file and LANDER_REMOTES); a URL starting with '-' is refused; a dangling symlink at the clone path is refused (exit 2); an EXIT trap maps any status outside 0-3 to 1 with a message | V1d, V1e, V14, V12, V13 (fault shim: exit 1, not 128); S_A5, S_A15; Z13-Z15, Z21, Z24 |
| T-3 INT/TERM traps | the test traps INT and TERM | test header |
| T-4 shim records send-pack and aliases | the recording shim logs push, send-pack, http-push and aliases | SH1/SH2 |

Kept unchanged: exactly one push call site (SH0 with a control needle), never force, preflight before any push, per-remote read-back (S_A14: a server post-receive rewind gives FAIL, rc=1), and resumable pushes (S_A1: 8/9, then preflight refuses, then resume gives 9/9 with the concurrent commit kept).

S_A1 and S_A8 print "non-plain: 9" because the reviewer's shim compares each push argv with the round-3 form. Round 4 adds `--no-follow-tags`, so all 9 differ by design. SH0 pins the new exact text.

## Class of each test (§11.4.289)

- The git side is real: git 2.53, nine local bare repositories as remotes with the real names, real client and server hooks (S_A14, V9d), real flock (U11b, S_A26), real config and filters (V2e/f, V6, V7, V16, S_A8, S_A9, S_A23).
- Test doubles (UNIT-CLASS): the fake mint scripts, a fake gpg (V5, S_A7), the push-recording PATH shim, the fault-injection shims of V13 and V15, and the reviewer's pre-push trigger in S_A1.
- The suite is gate-logic evidence for the lander. It is not live proof against any hosting platform; no forge was contacted.
- S_A3b and S_A3c are the only runs of the real workable-items engine binary (scratch build of 2026-11-10). They ran on a copy of the DB inside the seed repository. The source DB sha256 `27f579ee…` was unchanged before and after.

## UNCONFIRMED / open

- `push.pushOption` from ambient config is not neutralised (`GIT_PUSH_OPTION_*` is cleared, config is not). No test covers it.
- A mint that updates only the SQLite `-wal`/`-shm` sidecars changes no tracked file and is refused (fail closed). Whether the real engine ever leaves its change only in the WAL was not measured; S_A3c's mint commit did modify `docs/wi.db`.
- The presence check is a token match on the staged blob. For a binary SQLite file, an id stored next to digits in the page bytes could make the presence check refuse a real mint (false refusal, fail closed). This was not observed; S_A3b and S_A3c found CON-166.
- The S_A3c failure probe with a valid description and a missing DB: the engine created a new DB and printed an id; the lander refused it by path policy (A docs/absent.db). Whether the engine's id in that case is meaningful was not examined.
- V15 and V16 (and the Z20/Z23 kills) rely on a fault-injection shim (V15) and an ambient clean filter (V16). These are constructed preconditions, not a reproduction of a seen incident.
- Header wording nit, not fixed (a comment change would invalidate every run above): the HOOKS section (line 147) says the mint and id-verify commands "run in the caller's environment", while the ENVIRONMENT section (lines 107-108) correctly says they inherit the CLEARED environment. The code does the latter. Fix the sentence in the next round.
- The suite took 305-445 s per run on a host with load 27-37 from other work. Timing is not asserted.

## Reproduce

```
cd <root holding these two files and scripts/lib/{safe_rm.sh,protected_paths.list}>
TMPDIR=<scratch> systemd-run --user --scope -p TasksMax=3000 -- nice -n 10 bash tests/release/test_land_vehicle.sh
TMPDIR=<scratch> systemd-run --user --scope -p TasksMax=3000 -- nice -n 10 \
  bash docs/qa/land_vehicle_r4_2026_11_13/tools/driver_r4.sh <root> <round3 lander> <outdir>
```
