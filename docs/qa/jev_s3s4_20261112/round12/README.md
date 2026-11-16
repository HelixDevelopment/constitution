# Jev S3/S4 round 12: fixes for the review of a1eeb0d7

| Field | Value |
|---|---|
| Item | CON-423 (Jev S3/S4); the other four Jev items are CON-424 to CON-427 (`landing/mint_ids.txt`) |
| Review | `review_jev_r11.md`, NO-GO, findings R11-A to R11-G |
| Base | `main` at `09d3ad2f`, merged into the vehicle |
| Author | a fresh structural fixer instance (Opus; effort UNKNOWN, it cannot be set or read on this dispatch path, §11.4.231(F.2)) |
| Evidence class | gate-logic (§11.4.289(C)(2)): a hermetic bwrap runner, the stub llmctl, no network. This shows that the producer DECIDES correctly; it does NOT show that a local model runs. PROVISIONAL (§11.4.290) |
| Independent review | owed (§11.4.142 / §11.4.209); nothing here is GO |

## Findings and what changed

| Finding | Change | Evidence |
|---|---|---|
| R11-A | The round-11 tool copies (`hrun.sh.txt`, `jobs_final.sh.txt`, `runmut11.sh.txt`, `runsuite.sh.txt`) and the round-8 and round-9 `.txt` copies are now mode 644, so they are data by extension. Content is unchanged, so the hashes in the older SHA256SUMS still hold. The round-12 tool copies are mode 644 too | `runs/git_env_census_head.txt` |
| R11-B | The three exemption rows whose reason was "not executable" are removed. They are not needed now that the files are 644 | `config/git_env_class_exemptions.tsv` |
| R11-C | The blanket `rc` and `ls` data extensions are removed. A file under `docs/qa/` counts as data only by its shape: an exit-code file of one integer line from 0 to 255, or a listing whose every line has the `ls -l` shape. A file is never data by shape if it is executable or if it names `git` or `GIT_`. Rows C2rc1 to C2rc15 are in `tests/test_git_env_class.sh`. CM1 and CM3 are RED on the round-11 census and GREEN now; CM2 stays killed; CM4 to CM8 are killed | `runs/census_rows_RED_on_a1eeb0d7_census.txt`, `runs/census_rows_GREEN_head.txt`, `runs/census_mut12.tsv`, `mutants.md` |
| R11-G | Rows R12-1 and R12-2 hold the lease lock across every record wait of a stop. The release exits 6 and keeps the set, and an acquire starts no further candidate. Each row has a golden-FALSE or control partner. X06 is RED on both rows. A lock-timeout sweep of all 24 lock sites adds R12-3 to R12-5 | `lock_timeout_census.md`, `runs/lock_census.txt`, `runs/mut_X06_r12.txt` |
| R11-D | R12-6 to R12-9 kill X05, X10, X04 and X08. X01, X02, X03 and X07 have equivalence arguments, and X11 is an honest non-equivalent survivor. `write_census.py` is closed-world (R12-11) | `mutants.md` |
| R11-E | `Constitution.md` Revision is 97: `main` has 96, and the vehicle's 98 never landed | `Constitution.md` header |
| R11-F | A three-process model check runs 60 interleavings (R12-10, `tests/jev/test_s4_round12_mc.sh`). It found **R12-F1** (below) | `runs/r12mc_head_discovery_R12-F1.txt` |

## Finding R12-F1 (open, not fixed)

Found by R12-10 on its first run at the round-12 head, in 2 of the 60 orders: `starCA` and `straCA`.

The sequence:

1. Process A's slow start returns. Its mark was judged expired, because the row advances the clock past the mark's
   lifetime while the start is gated; this stands for a start that outlived its own bound.
2. Before A records its start, process B's dispose-stop records its result and deletes the set.
3. A third acquire, C, now sees a running unit with no set. It joins it as operator-started ("joined the
   already-running unit").
4. A's start record then makes the set constitution-started again. The cleanup leaves no unit and no set, and in every
   order a running unit is held or owed a stop.

So the finding is a window in which a constitution-started unit is treated as operator-owned. In that window C would
never stop it.

What R12-10 does about it:

- It ASSERTS the safety properties it can show for all 60 orders: held or owed, and a clean final state.
- It PINS the adoption list as a characterisation row. That row is not a pass of the "nothing is adopted" property.

The fix needs a change to the producer, which is outside this round's scope. Two candidate approaches:

- keep a record of the in-flight start that outlives the set deletion;
- refuse adoption while a recent dispose of the profile is unanswered.

The §11.4.291 refinement note in `Constitution.md` names the finding. It is filed through the engine as **CON-428**
(Bug, UNREPRODUCED: gate-logic only, not on a live host; `landing/mint_r12f1.sh`, `landing/mint_r12f1_ids.txt`).

## Runs at the round-12 head (each 0 failures)

| Suite | Passes | Note |
|---|---|---|
| r12 `tests/jev/test_s4_round12.sh` | 62 | R12-1 to R12-9, R12-11 to R12-13 |
| r12mc `tests/jev/test_s4_round12_mc.sh` | 6 | R12-10, with the R12-F1 characterisation row |
| r11 | 59 | |
| r10 | 52 | |
| r9 | 70 | |
| r8 | 47 | |
| r7 | 157 | |
| r6 | 183 | |
| placement | 266 | |

Other checks at the head:

- git-env census: PASS, members=652 hermetic=497 exempt=155 unscrubbed=0 (`runs/git_env_census_head.txt`).
- `tests/test_git_env_class.sh`: passed=157 failed=0 skipped=1.
- `tests/test_full_suite_manifest_gate_git_env.sh`: passed=14 failed=0.
- `--verify-manifest`: MANIFEST-OK.
- Index freshness: PASS.
- Gate-ledger ratchet: PASS (394 = 394).
- Propagation gates 279 to 286 and 291: PASS.
- Engine `validate`: OK (393 items).
- Engine `diff`: in sync (`runs/engine_final.txt`, `runs/gates_final.txt`).

At most 2 suites ran at a time, under `systemd-run --user --scope -p TasksMax=2000` and `nice -n 10`.

Earlier runs are kept as found:

- `runs/r12_head_R12-5_wrong_assertion.txt`: R12-5 first asserted a placement record that the producer, correctly,
  cannot write without the lock. The assertion was corrected to the logged unwritten record and an unchanged
  `placement.json`.
- `runs/r12mc_head_discovery_R12-F1.txt`: the run that found R12-F1.

## Follow-ups

- R12-F1 (CON-428): fix it in the producer.
- X11 and Y12: rows for their three-process windows (`mutants.md`).
- Rows that time out the lock at the seven sites in `lock_timeout_census.md` that no row covers yet.
- The `(top level)` attribution of write_census line 1446, which is the dispatcher, reported under `hb_locked`.

## Files

- `tools/*.txt`: the scratch tools, copied as data with mode 644.
- `runs/`: run outputs and `results.tsv`.
- `landing/`: the mint records (the five Jev items, and CON-428).
- `SHA256SUMS`: covers every file in this directory except itself.
- The pack index `../README.md` changed in round 12: the Jev ids were moved to CON-423 to CON-427, and a link list for
  rounds 4 to 12 was added. So its line in `../SHA256SUMS` is re-hashed. No other line of that file changed.
