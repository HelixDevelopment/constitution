# Jev S3/S4 round 13: fixes for the review of c0455825

| Field | Value |
|---|---|
| Item | CON-423 (Jev S3/S4); the finding R12-F1 is CON-428. CON-424 to CON-427 are unchanged (`../round12/landing/mint_ids.txt`) |
| Review | `review_jev_r12.md`, NO-GO, findings R12-B1 to R12-B3, R12-M1 to R12-M3, R12-N1 and R12-N2 |
| Base | the round-12 vehicle `c0455825`, merged (merge, not rebase) onto `main` at `bbdf4ac1` |
| Author | a fresh structural fixer instance (§11.4.276(E)(3)); Opus; effort UNKNOWN (it cannot be set or read on this dispatch path, §11.4.231(F.2)) |
| Evidence class | gate-logic (§11.4.289(C)(2)): a hermetic bwrap runner, the stub llmctl, no network. This shows that the producer DECIDES correctly; it does NOT show that a local model runs. PROVISIONAL (§11.4.290) |
| Independent review | owed (§11.4.142 / §11.4.209); nothing here is GO |

## Findings and what changed

| Finding | Change | Evidence |
|---|---|---|
| R12-B1 | Reproduced first (§11.4.292) with the reviewer's experiment, on the merged head: in `starCA` and `starAC` with the starter A SIGKILLed at its record lock call, C adopts the unit and after the cleanup `running=[decide-a] sets={}` (one start, one stop). Fixed by a START INTENT (below). The experiment ships as `tests/jev/test_s4_round13.sh` R13-1 (the kill orders `starCA`, `starAC`, `straCA`, `aAstrC`, each also without the kill), plus R13-2 (the intent on crafted registries). RED on the round-12 producer (20 failures, among them the leak in `starCA`, `starAC` and `straCA`), GREEN at the head | `runs/repro_r12b1_merged_head.txt`, `runs/exp_r12b1_fixed_head.txt`, `runs/r13_RED_base_r12.txt`, `runs/final*_r13.txt` |
| R12-B2 | The shape rule's "never data if it names git" check now uses the member detector's own definition (`MENTION`: case-insensitive, letter boundary only). The `.rc` integer, the `total N` header and every listing line use ASCII digits and spaces (`re.ASCII`). Every place the two definitions differed was measured, not argued (table below). Rows C2rc16 to C2rc27; selftest shapes added. A test defect found on the way (rows C2rc21 and C2rc22 were empty fixtures) is described in `mutants.md` | `runs/enum_defs.tsv`, `runs/cmut_CR12_round12_census.txt` (the round-12 census: 8 failures), `runs/final*_census.txt`, `mutants.md` |
| R12-B3 | R13-3 runs a failing owed retry for real: inside a release stop (the release exits 6 and keeps the set; golden-FALSE: the retry succeeding exits 0) and inside a failed start's cleanup stop (no further candidate starts; CONTROL: with the retry succeeding the next candidate starts). R08 is killed by both rows | `runs/mut_R08_owed_retry_fail_is_success_r13.txt` |
| R12-M1 | R13-4: the release's first arm lock wait times out, the second succeeds; the release stops the unit and exits 0. R01 is killed | `runs/mut_R01_arm_no_retry_r13.txt` |
| R12-M2 | R13-5: a refused start (rc 75) recorded under another live process's stopping mark, with no other lease, gets no owed stop and runs no stop; CONTROL: rc 1 in the same place gets an owed stop. R06 SURVIVED that row: the set there is made by the acquire's own mark, and the next observation drops it with or without `stop_owed`. R13-5c (crafted: the set is already constitution-started) is where the rule is visible, and it kills R06 (`mutants.md`) | `runs/probe5_R06.txt`, `runs/probe5c_R06.txt`, `runs/mut_R06_stopowed_for_rc75_r13.txt` |
| R12-M3 | CMR1, CMR2 and CMR3 are killed. CMR1 and CMR3 are first killed by the census's own built-in control needles (BLIND on every row); with those needles switched off (`_noST`) the test rows still kill them: C2rc16 to C2rc18 (CMR1), C2rc20 (CMR3), and C2rc19 kills CMR2. CMR4 (a whitespace-tolerant `.rc`) survives and is judged harmless (`mutants.md`) | `runs/cmut_*.txt` |
| R12-N1 | The round-12 README now names the first final r12 run (61 passes, 1 failure: R12-12's trailing-space assertion) among the runs kept as found | `../round12/README.md` |
| R12-N2 | The account of R12-F1 now states the crash consequence, in the vehicle's documents: `../round12/README.md` (correction paragraph), this README, `CHANGELOG.md`, and CON-428 through the engine. The §11.4.291 note in `Constitution.md` was NOT edited (see "Open questions") | |

## The start intent (R12-B1)

The defect: an in-flight start was recorded only in the set's `starting` mark. A dispose that deleted the set also
deleted the only record that a start was running, so a later acquire saw a running unit with no set and adopted it as
operator-started. If the starter then died before recording its start, nothing made the set constitution-started
again, and the unit ran with no set, no lease and no owed stop.

The fix, in `scripts/jev/jev-place.sh`:

1. `mark_start_locked` writes `.start_intents[<profile>]` (the same mark: pid, pid start time, holder, time) in the
   same registry write that creates the set and its starting mark, before `llmctl start` runs. It refuses to start a
   profile that already has an unanswered intent.
2. `finish_start_locked` removes the intent in the same write that records the result, and only when the intent names
   this process (pid and pid start time). It never removes another process's intent.
3. Adoption (plan step D) never adopts a running unit whose profile has an unanswered intent.
4. `intents_locked`, called from every observation (`obs_locked`, used by acquire, release, heartbeat, status, reap),
   recovers the intent of a DEAD starter (pid gone, or pid reused with another start time): if a set exists it is made
   constitution-started; if no set exists and the unit runs (`ok` or `degraded`) a constitution-started set with an
   owed stop is made, and the next acquire, or the release itself, runs that stop through the existing owed-stop path;
   if the unit is absent the intent is removed; if the capacity answer is not known now the intent is kept.

A crash between the start and its record is therefore recoverable: the intent outlives the set and the process, and
the owed-stop path stops the unit. R13-1 shows it for the three orders that leaked, and the same orders without the
kill stay clean.

Honest limits (§11.4.6): the rows cover the orders listed, one profile and the stub llmctl. A live intent never
expires by age: a starter that hangs without dying blocks a second start and adoption of that profile until it exits
(the start itself is bounded by `JEV_LLMCTL_START_TIMEOUT`). A pid reused by an unrelated process with the same start
time is not distinguishable (the same limit as every other mark).

## R12-B2: where the two definitions differed

Measured by `tools/enum_defs.py.txt`, which calls both census modules' real functions (`runs/enum_defs.tsv`). Round 12
called these texts data by shape although the member detector counts them as git mentions; the head calls none of them
data:

| Class | Probes |
|---|---|
| case | `GIT` only (the reviewer's hostile `${G,,}` line), `Git=1`, `gIt` |
| left boundary | `x_git`, `1git` (`\b` sees no boundary there; MENTION only looks for a letter) |
| right boundary | `gitx`, `github`, `git_dir` (MENTION has no right boundary) |
| Unicode case folding | dotless `ı` and dotted `İ` (Python's case-insensitive match folds them to `i`) |
| non-ASCII digits and spaces | `١٢` as an exit status, `total ٨`, a link count `١`, U+2003 and U+00A0 between listing fields |

One change goes the other way: `AGIT_X` was refused in round 12 (the bare `GIT_` alternative) and is data by shape now.
That is consistent, because MENTION does not count `AGIT_X` as a mention, so the member detector never sees it either.

## Runs

| Suite | Pass 1 (pass/fail, time) | Pass 2 | Verdict hash, pass 1 = pass 2 |
|---|---|---|---|
| `tests/jev/test_s4_round13.sh` | 76/0, 202s | 76/0, 278s | `77c9bb24fc487ef9` |
| `test_s4_round12.sh` | 62/0, 87s | 62/0, 116s | `9fad63f28421873a` |
| `test_s4_round12_mc.sh` | 6/0, 1308s | 6/0, 1766s | `3f9a9e8f44be23a1` |
| `test_s4_round11.sh` | 59/0, 403s | 59/0, 499s | `01cee5c32dc49563` |
| `test_s4_round10.sh` | 52/0, 63s | 52/0, 69s | `cd699d069898311a` |
| `test_s4_round9.sh` | 70/0, 71s | 70/0, 81s | `2969ffcee2f5fc5c` |
| `test_s4_round8.sh` | 47/0, 181s | 47/0, 186s | `744b675dfd416578` |
| `test_s4_round7.sh` | 157/0, 268s | 157/0, 347s | `f8f0a34496a7a7ce` |
| `test_s4_round6.sh` | 183/0, 419s | 183/0, 462s | `127bf351b7adf1e7` |
| `test_s4_placement.sh` | 266/0, 372s | 266/0, 427s | `6f4d98964cb9f4f7` |
| `tests/test_git_env_class.sh` | 169/0, 161s | 169/0, 159s | `8bf908d709137139` |
| `tests/test_full_suite_manifest_gate_git_env.sh` | 14/0, 123s | 14/0, 128s | `ab590dba24848c9d` |

Each suite ran twice (outputs `runs/final1_<key>.txt` and `runs/final2_<key>.txt`) under the hermetic runner
(`tools/runsuite.sh.txt`); the verdict hash is `tools/norm.sh.txt` over the verdict lines (test numbers, paths and
digits normalised). The real-tree census in C1: PASS, universe 1888, 652 members. Gates (`tools/gates.sh.txt`, twice,
`runs/gates_1.txt` and `runs/gates_2.txt`): index freshness, gate-ledger ratchet (unimplemented 394 = baseline 394),
propagation of §11.4.279 to §11.4.286 and §11.4.291, `--verify-manifest` and engine validate / diff.

The manifest gate first reported `MANIFEST-MISMATCH`: the new test file had no manifest row, and after the row the
runner guide's generated census block was stale. Both were regenerated by the runner itself (`--generate-manifest
--write`, `--sync-guide`), as in round 12; `config/full_suite_manifest.tsv` gains one row. The suite runs above
were made before that regeneration; the census suite and the manifest-gate suite, which read the tree, were run once
more on the final tree (`runs/final3_census.txt`, `runs/final3_manifestgate.txt`; census 169/0, manifest gate 14/0, verdict hashes equal to runs 1 and 2: 8bf908d709137139 and ab590dba24848c9d).

Earlier runs kept as found: `runs/r13_RED_base_r12.txt` (RED on the round-12 producer, 20 failures),
`runs/r13_GREEN_try4.txt` (the first full GREEN, 72 passes, before R13-5c and R13-2h were added).

## Open questions

1. `Constitution.md` §11.4.291, the refinement note (line 12754 at this head), still reads "that model check found one
   open window (a third acquire treats as operator-started a unit whose set a disposer deleted after a slow start
   returned and before it was recorded; finding R12-F1 ...)". After round 13 that text is stale: it omits the crash
   consequence (a running unit left with no set when the starter dies) and the round-13 change. Per the brief it was
   NOT edited, and its Revision stays 97. Whether and how it is amended, with the matching carriers, is an operator
   decision.
2. All evidence is host-fixture gate-logic evidence with a stub llmctl (§11.4.289); no live llmctl run was made.
   CON-428 is therefore PROVISIONAL, not verified.
3. The ids CON-423 to CON-428 are kept. The rehearsal bundle uses the same ids, so whichever lands second re-mints
   them through the engine.
4. Two judgements a reviewer should check: F15 judged equivalent (a foreign intent carrying this acquire's own start
   time reads as a reused pid; F15b, the non-equivalent form, is killed by R13-2h) and CMR4 judged harmless.
5. A live start intent never expires by age: a starter that hangs without dying blocks a second start and adoption of
   that profile until it exits (bounded by the start timeout). Whether an age rule is wanted is open; adding one would
   reopen the race this round closes.
6. `tests/jev/test_s4_round12_mc.sh` was not re-run against the round-12 producer this round; the RED for R12-B1 is
   shown by R13-1 (`runs/r13_RED_base_r12.txt`).

## Files

- `tests/jev/test_s4_round13.sh`: rows R13-1 to R13-5c (with R13-2h).
- `tools/*.txt`: the scratch tools, copied as data with mode 644 (the reviewer's experiment is `tools/exp_r12f1_kill.sh.txt`).
- `runs/`: run outputs and `results.tsv`.
- `landing/`: the CON-428 engine update and the engine's validate / export / diff output.
- `mutants.md`: every mutant, its result and, for the survivor, the argument.
- `SHA256SUMS`: covers every file in this directory except itself.
