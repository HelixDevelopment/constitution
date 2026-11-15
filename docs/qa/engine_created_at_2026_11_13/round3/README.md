# Engine created_at vehicle, round 3 (CON-339)

| Field | Value |
|---|---|
| Revision | 2 (round 4: status line records the round-3 review verdict) |
| Created | 2026-11-14 |
| Status | PROVISIONAL. Independent round-3 review: NO-GO (F1 R3G03 and F2 R3S01 important, F3 nit, F4 minor); remediation in `../round4/README.md`; evidence class gate-logic / unit (§11.4.289(C)(2)) |
| Roadmap-Item | CON-PENDING-ENGINE-CREATEDAT |
| Base | `bd0036bd`; round-2 head `e34bf22d`; round-2 review: NO-GO (R2-F1 important, R2-F2 to R2-F5 minor or nit) |
| Round kind | STRUCTURAL (§11.4.276(E)): R2-F1 was the round-1 F1 class again (surviving mutants), so this round closes the class, not the five instances |

Paths written as `<scratch>` stand for the session scratch directory of the run. Nothing here ran against the live
checkout or the real tracker database. Every Go test and every applier case runs on files under a private temporary
directory.

## What changed

No production source changed. The tracked binaries are unchanged (`e048a077…` for both `bin/workable-items` and
`bin/workable-items-linux`), so no rebuild was needed. The changes are tests, the mutation runner, the applier test
suite and documentation.

| File | Change |
|---|---|
| `scripts/workable-items/cmd/workable-items/created_at_r3_test.go` | new: items (a), (b), (c) of R2-F1, and VE03 |
| `docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh` | cases B1 to B4 added (item (d)); 20 cases became 69 |
| `scripts/workable-items/mutation/created_at_r2_mutation_runner.py` | the reviewer's 13 round-2 mutants copied verbatim; 16 new own mutants (MT01 to MT11, MU01 to MU05); MS03 taken out of the EQUIVALENT table; the RR09 wording corrected |
| `config/full_suite_manifest.tsv` | the runner row's tier note (95 mutants, measured time) |
| `round2/README.md`, `round2/class_inventory.md`, `round2/follow_up_register.md`, `round2/tools/rr09_equivalence.go.txt` | R2-F3 corrections and the R2-F4 and R2-F5 follow-ups, in place, revisions bumped |

## Findings of the round-2 review and what this round did

| Finding | Disposition | Where |
|---|---|---|
| R2-F1 (a): every refusal code with and without `--dry-run` | `TestRestoreCreatedAtR3_EveryRefusalSameInDryRun`: 38 cases covering 21 refusal codes, each run as a real run and as a dry run. Both must give the same code, print no `would set` line, and leave the database and the evidence unchanged. `TestRestoreCreatedAtR3_RefusalTableNamesEveryCode` scans the source and finds 23 codes. 21 are in the table and 2 are write-only (`WRITE`, `CONCURRENT-CHANGE`), so the table covers every code. `TestRestoreCreatedAtR3_WriteCodesOnlyInARealRun` shows that those two appear only in a real run and that a dry run never reaches the test seam. | `r3_new_tests_v.txt` |
| R2-F1 (b): the tracker bound under both attestations | `TestRestoreCreatedAtR3_TrackerBoundBothAttestations`: `items-row` and `opened-event`, each at 2000-01-01, at 1 s before the bound, and at the bound, each in a real run and a dry run (kills VM01, VM06) | same |
| R2-F1 (c): identity near-misses | `TestRestoreCreatedAtR3_IdentityNearMiss`: type `bug`, `BUG`, ` Bug`, `Bug `, `Bug<TAB>`; title with one letter's case changed, all upper case, leading space, trailing space, trailing LF. Each runs as a real run and a dry run, plus an exact-copy control that is accepted (kills VM02). Near-miss ids for both the live and the evidence database (lower case, leading and trailing space) are cases of (a). | same |
| R2-F1 (d): applier paths | B1: evidence paths of 1 to 5 components, a control without links for each length, and a symbolic link at every depth pointing inside and outside `--root` (35 cases; kills VS02, VS03). B2: a `--root` through one link and through a chain of two links, a relative `--root`, a trailing slash, a `--root` that is a file, a missing `--root` (kills VS01). B3: missing engine, tracker or plan (exit 3), an unknown argument, an option without a value (exit 2). B4: a PATH-shim `mkdir` that plants the link between the walk and `mkdir`, with a target outside `--root` and a sibling that shares the `--root` prefix, plus a pass-through control; the shim logs every call (kills MS03). | `sh_suite_r3.txt`, `sh_suite_r3_tracked_binary.txt` |
| R2-F1 (e): a fresh mutant run with no non-equivalent survivor | 95 mutants: 35 reviewer (22 from round 1, 13 from round 2, all verbatim) and 60 own. Result: 92 KILLED, 3 SURVIVED, all declared equivalent (RR09, RR13, MS11), 0 stale, 0 build-broken, `unexplained survivors: []`, worktree clean after both shards | `mut_targeted_shard0.txt`, `mut_targeted_shard1.txt`, `r2_mutants_verbatim_check.txt` |
| R2-F2 (VE03) | tested: `TestCON339R3_CloseRefusesUnreadableCreatedAt` builds an items table of the legacy shape with a nullable `created_at` and sets it to NULL. `close` is refused, no row changes and no history row is written. A readable-value control closes and carries the value. VE03 is KILLED. | same |
| R2-F3 (a)-(d) doc overstatement | corrected in place: the round-2 tally reads 62 killed / 3 equivalent / 1 untested (MS03); class 4 says 20 cases, not 19, and names the cases that were missing; RR09's check is called factored, not exhaustive, in the round-2 README, the runner and the tool header; the F7 row says none of A5, A5b, A6b exercised a symlinked `--root` and points here | `../round2/README.md` revision 2 |
| R2-F4 `--root /` | registered as D-08, not changed (it fails closed; the reviewer found it by reading only, and it is UNCONFIRMED until run) | `../round2/follow_up_register.md` |
| R2-F5 empty plan columns | registered as D-09, not changed (the current plan uses `-`) | same |
| out of scope: the fastcycle temporary-directory leak | registered as D-10, not changed (§11.4.293) | same |

## Mutation run (round 3)

Runner: `scripts/workable-items/mutation/created_at_r2_mutation_runner.py --mode targeted`, in two shards (`--shard
0/2`, `1/2`), each in its own disposable worktree. Each worktree holds the uncommitted round-3 tree in a
throwaway detached commit, so the runner's clean-worktree check applies. The runs were under
`systemd-run --user --scope -p TasksMax=1500 nice -n 10`, at load 20 to 46, and took about 88 minutes. Targeted mode
runs `-run '^(TestCON339|TestRestoreCreatedAt)'`, which includes every round-3 test. Both controls (the Go selection
and the shell suite) passed first in each shard.

| Set | Mutants | KILLED | SURVIVED | STALE / BUILD-BROKEN |
|---|---|---|---|---|
| reviewer, round 1 (RM01 to RM07, RR01 to RR15) | 22 | 20 | 2 equivalent: RR09, RR13 | 0 |
| reviewer, round 2 (VM01 to VM07, VE01 to VE03, VS01 to VS03) | 13 | 13 | 0 | 0 |
| own (MR01 to MR33, MS01 to MS11, MT01 to MT11, MU01 to MU05) | 60 | 59 | 1 equivalent: MS11 | 0 |
| total | 95 | 92 | 3 | 0 |

The six survivors R2-F1 named (VM01, VM02, VM06, VS01, VS02, VS03) are killed, and so is MS03. MS03 was in the
EQUIVALENT table in round 2; it is now tested by B4 and killed.

The new own mutants cover the classes the reviewer named, and each is killed:
- MT01 to MT06: letter case and white space in the type, title and id checks.
- MT07 to MT10: a refusal made only in a real run (attest, first event, sidecar, sha256).
- MT11: `close` returns success when the read fails.
- MU01 to MU05: the walk skips the file or the first component; a logical `pwd` for the evidence directory; an
  unresolved `--root`; the prefix check without its slash.

The reviewer's round-2 mutants are copied with old text, new text and intent identical to
`probes/rev2_mutants.py`. Only the file path changes, from repository-relative to the runner's module-relative form.
`r2_mutants_verbatim_check.txt` compares the 13 tuples (all identical) and shows that a one-character change would
be detected.

The equivalence arguments are unchanged and named in the runner: RR13 is the reviewer's control; RR09 is shown by an
argument plus a factored check; MS11 differs only in one extra `mv` error line on stderr. A whole-package (`--mode
full`) re-run was not made in this round, because every non-equivalent mutant is already killed by the targeted
selection.

## Tests

- `go vet ./cmd/workable-items/`: clean (`vet_r3.txt`).
- `gofmt -l`: the new file is clean. The 17 files listed are the same pre-existing files as in round 2
  (`gofmt_l_r3.txt`).
- `go test -count=1 -v ./...`, twice: 790 PASS / 0 FAIL / 6 SKIP each time, with identical verdict sets. All 678
  round-2 verdicts are unchanged. The 118 new verdicts all come from `created_at_r3_test.go`. A control needle shows
  that the comparison reports a fabricated verdict as missing (`go_summary_r3.txt`, `go_verdicts_r3_run*.txt`).
- Applier suite: 69 PASS / 0 FAIL, both with an engine built from the round-3 tree and with the tracked binary.
- `CM-GATE-LEDGER-RATCHET`: unimplemented 394, baseline 394, PASS (`ratchet_tail_r3.txt`).
- `run_full_suite.sh --verify-manifest`: MANIFEST-MISMATCH. The cause is three `scripts/sonarqube/tests/`
  files without a row. That mismatch is pre-existing at base `bd0036bd` (the same three lines are in
  `round2/verify_manifest_r2.txt`) and is outside this vehicle (§11.4.293). No file of this vehicle is reported
  (`verify_manifest_r3.txt`).

## Not shown

- Behaviour on the landed tracker; this is a gate-logic / unit class result only.
- The applier under a real concurrent change: B4 is a deterministic stand-in (a PATH shim), not a race.
- `--root /` (D-08) and empty plan columns (D-09) are registered, not run.
- Byte reproducibility of the tracked binaries across hosts (they were not rebuilt in this round).
- `../SHA256SUMS` (round 1) still lists the round-1 hashes of `../README.md` and `../apply_restore_plan.sh`; round 2
  changed both files and did not regenerate it. It is left as the record of the round-1 snapshot `6fffb942`
  (`git show 6fffb942:<path>` matches it). `../round2/SHA256SUMS` was regenerated over its own file list in this round
  because round 3 corrected those files in place. This directory has its own `SHA256SUMS`.
