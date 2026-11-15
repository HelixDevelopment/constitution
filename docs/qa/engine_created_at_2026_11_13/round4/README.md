# Engine created_at vehicle, round 4 (CON-339)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Status | PROVISIONAL (independent round-4 review not yet done); evidence class gate-logic / unit (§11.4.289(C)(2)) |
| Roadmap-Item | CON-PENDING-engine-r4 |
| Base | `bd0036bd`; round-3 head `50b4863f`; round-3 review: NO-GO (F1 R3G03 and F2 R3S01 important, F3 R3G06 nit, F4 R3G10 / R3S02 / R3S05 minor) |
| Round kind | STRUCTURAL (§11.4.276(E)): F1 and F2 are the round-2 class again (a comparison or a path guard whose own tests cannot fail), so this round enumerates the class and tests every member |

Paths written as `<scratch>` stand for the session scratch directory of the run. Nothing here ran against the live
checkout or the real tracker database. Every Go test and every applier case runs on files under a private temporary
directory.

## What changed

| File | Change |
|---|---|
| `scripts/workable-items/cmd/workable-items/created_at_r4_test.go` | new: the comparison census, two boundary tables, R3G10, R3G06, R3G09 |
| `docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh` | production: two new BLIND checks (see "Defects found") |
| `docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh` | cases B5 to B7 added; 69 cases became 100 |
| `scripts/workable-items/mutation/created_at_r2_mutation_runner.py` | the reviewer's 13 round-3 mutants copied verbatim; 27 new own mutants (MV01 to MV19, MW01 to MW08); a new outcome CENSUS-ONLY |
| `config/full_suite_manifest.tsv` | the runner row's tier note (135 mutants, measured time) |
| `round2/class_inventory.md`, `round3/README.md` | status lines now record the round-3 verdict; revisions bumped |
| `scripts/workable-items/bin/.source.sha256` | re-recorded for the current source (see "Build") |

No Go production source changed. The tracked binaries were rebuilt with the reproducibility flags and their
sha256 is unchanged (see "Build"). The production change is the applier, `apply_restore_plan.sh`.

## Findings of the round-3 review and what this round did

| Finding | Disposition | Where |
|---|---|---|
| F1 (R3G03): `s == *value` widened to `s <= *value` survived | Killed by the reviewer's own probe shape (evidence Opened 09:59:10, items 09:59:45, `--value 09:59:30`: EVIDENCE-DOES-NOT-ATTEST in a real run and a dry run, database unchanged) and by the rest of the attestation table below. The sibling `r.created == *value` loop has the same cells. The class is every comparison in the command: see "The comparison class". | `TestRestoreCreatedAtR4_AttestationBoundaries` |
| F2 (R3S01): `continue` -> `break` on an empty path component survived | Killed by B5: one case per path shape (empty components, `.` components, triple slashes, a link at each depth, loops, dangling links, a destination that is a directory or a FIFO, and the shapes that do not end in a file name). Every blind case must exit 3, never run the engine, leave the tracker unchanged and leave the trees of the root and of the outside directory exactly as they were. | `sh_suite_r4.txt` |
| F3 (R3G06): sidecar threshold `> 0` -> `> 8` | Killed: `-wal` and `-journal` of 0, 1, 8 and 9 bytes; 0 is accepted, the rest give EVIDENCE-WAL. | `TestRestoreCreatedAtR4_SidecarSizeBoundary` |
| F4 (R3G10): CR in `--reason` | Killed: a reason with a carriage return is refused; a control without CR is accepted. | `TestRestoreCreatedAtR4_ReasonCarriageReturn` |
| F4 (R3S02): engine `-x` -> `-e` | Killed: a mode-0644 copy of the engine gives BLIND exit 3, "engine not executable", the engine is never run. | B6 |
| F4 (R3S05): `mv` -> `cp` | Killed: after a successful extraction the root holds exactly the evidence directory and the evidence file, in a dry run and with `--apply`. | B7 |
| R3G09, called equivalent by the review | Not equivalent and now killed: `openDB` rebuilds the items table only when a column is missing (`db.go`), so a legacy table whose `representation` column has no NOT NULL keeps a NULL value. The test builds that table and requires the row to be found with and without `--representation section`. | `TestRestoreCreatedAtR4_NullRepresentationLegacyRow` |
| Nit: `round2/class_inventory.md` said "independent review pending" | Corrected (revision 3), and the same in `round3/README.md` (revision 2). | |
| Full-mode tally | Reported below. | `mut_full_shard0.txt`, `mut_full_shard1.txt` |

## The comparison class (F1)

`TestRestoreCreatedAtR4_ComparisonCensus` parses `restore_created_at.go` with `go/parser` and lists, in
`restoreCreatedAtCmd` and `parseStoredTime`, every binary comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`), every time
ordering call (`Before`, `After`, `Equal`, `Compare`) and every `switch` with a tag. MEASURED: 61 occurrences of 32
distinct forms. The list must equal a declared table in both directions, and every table row names the tests that
cover it; every named test must exist. The instrument is control-needled: on a synthetic source with every
operator kind it finds each one and ignores a function outside the census, it finds `s == *value` in the real
source (positive control) and does not find `s <= *value` (negative control).

The census reads source text, so it fails on any change to a listed comparison whether or not behaviour changes.
Counting that as a kill would be a change detector, not a test. The runner names it in `CENSUS_TESTS` and reports a
mutant failed by it alone as CENSUS-ONLY, counted like a survivor: it must be declared EQUIVALENT with an argument.

Boundary tables, each cell a real run and a dry run with the database and the evidence compared before and after:

- Attestation, for both sources (`items-row` and `opened-event`, the other source at 09:59:02): the value equal
  (accepted), one second before, one second after, strictly between two recorded values (both orders, and the
  reviewer's probe), outside below, outside above; when both sources are equal, `items-row` is named.
- Validation: the first history row (59 / 00 / 01 seconds around it), the earliest-row selection (an earlier row
  bounds, a later row does not, a tie), the tracker lower bound (one second inside, at, one second outside), and the
  current value (one second earlier accepted, equal is `already`, one second later is refused as LATER).

Out of the census, stated rather than implied: `checkEvidencePath` (`evidence.go`, shared with other commands) and
the SQL predicates. Their comparisons are covered by the round-2 and round-3 tests, not by this table.

## Defects found in the applier (path-shape class, F2)

Writing B5 found four defects the round-3 tests did not cover. Each was reproduced RED on the round-3 applier first
(`sh_red_r4_round3_applier.txt`, 91 PASS / 9 FAIL; the first probe of the path shapes, the reviewer's
`sh_probe.sh` with more cases, is kept as `sh_probe_r4.sh.txt` with its output on the round-3 applier in
`sh_probe_red_r4_round3_applier.txt`):

- `evidence_file` of `.`, `x/.` or `x/`: `mktemp` and `mv` work on a directory and a temporary file is left behind
  (B5-dot, B5-dir-dot, B5-dir-slash, B5-newdir-dot; the tree of the root changed).
- `x/snap.db/`: a directory is created (B5-file-slash).
- a destination that is an existing directory: the run writes into it (B5-dest-is-dir).
- a destination that is a FIFO: the FIFO is replaced and the run ends with exit 0 (B5-dest-is-fifo).

Fix, two checks in `apply_restore_plan.sh`: the last component must be a file name (`''`, `.`, `*/`, `*/.` are
BLIND), and an existing entry that is not a regular file is BLIND. The other failures on the round-3 applier
(B5-newdir-slash, B5-empty-evidence-file) were still BLIND there, by another check; they fail only the reason
assertion. After the fix: 100 PASS / 0 FAIL with the tree-built engine and with the tracked binary.

The shape cases also assert the BLIND reason (`must end in a file name`). For `.` and for an empty
`evidence_file`, a later check (the entry is a directory, or the directory is outside `--root`) would also stop the
row, so MW04 and MW05 are killed by that reason assertion, not by a different outcome. MW03 is killed by
B5-newdir-dot, which leaves a temporary file behind without the check.

## Mutation run (round 4)

Runner: `scripts/workable-items/mutation/created_at_r2_mutation_runner.py --mode full`, in two shards (`--shard
0/2`, `1/2`), each in its own disposable worktree holding the uncommitted round-4 tree in a throwaway detached
commit (the runner's clean-worktree check applies). The runs were under `systemd-run --user --scope -p TasksMax=2000
nice -n 10`, at load 29 to 46, and took 60 minutes (21:25 to 22:25 CET). Full mode runs the whole Go package for
every Go mutant, and the whole applier suite for every applier mutant. Both controls (the whole package and the
shell suite) passed first in each shard. Worktree clean after each shard: True.

| Set | Mutants | KILLED | not killed (all declared EQUIVALENT) |
|---|---|---|---|
| reviewer, round 1 (RM01 to RM07, RR01 to RR15) | 22 | 20 | RR09 (CENSUS-ONLY), RR13 (SURVIVED) |
| reviewer, round 2 (VM01 to VM07, VE01 to VE03, VS01 to VS03) | 13 | 13 | 0 |
| reviewer, round 3 (R3G01 to R3G11, R3S01 to R3S06, the 13 of the review) | 13 | 13 | 0 |
| own (MR01 to MR33, MS01 to MS11, MT01 to MT11, MU01 to MU05) | 60 | 59 | MS11 (SURVIVED) |
| own, round 4 (MV01 to MV19, MW01 to MW08) | 27 | 24 | MV12, MV17, MV19 (CENSUS-ONLY) |
| total | 135 | 129 | 6 |

STALE 0, BUILD-BROKEN 0, `unexplained survivors: []` in both shards (`mut_full_shard0.txt`, `mut_full_shard1.txt`).

The reviewer's 13 round-3 tuples are copied with name, old text, new text and intent identical to
`probes/rev3_mutants.py` (sha256 `c8a7a62d…ca06db4`); `r3_mutants_verbatim_check.txt` shows 0 differing tuples
and that a one-character change would be detected.

The six not killed, and why each is equivalent (each argument is in the runner's EQUIVALENT table):

- RR13: the reviewer's own control (`evAbs + ""` is `evAbs`).
- RR09: the round-trip format check is redundant with the fixed-width regexp and `time.Parse`, shown by the
  reviewer's 103,000,000-input sweep in round 3; it is now CENSUS-ONLY because the census lists that comparison.
- MS11: a failed `git show` still ends in exit 3 with nothing written; only an extra `mv` line on stderr differs
  (measured by the reviewer in round 3).
- MV12 (`ht.After(first)` -> `!ht.Before(first)`): differs only on a tie, where both choose a row with the same
  time, so the bound is the same value.
- MV17 (`newT.After(curT)` -> `!newT.Before(curT)`): differs only when the value equals the current one, and that
  case returns `already` earlier in the function.
- MV19 (`Size() > 0` -> `>= 1`): `Size()` is an `int64`, so the predicates are the same.

Earlier runs of this round, kept as evidence of how the result was reached:

- `mut_new_targeted_first_go.txt`, `mut_new_targeted_first_sh.txt`: the first targeted run of the 40 new mutants.
  MW03, MW04 and MW05 survived. That led to the reason assertions and the `newdir/.` and `newdir/` cases in B5.
  In that run the census still counted as a killer, so MV12, MV17 and MV19 were reported KILLED; that is why the
  runner now has the CENSUS-ONLY outcome.
- `mut_recheck_mw03_mw05.txt`: MW03, MW04, MW05 KILLED after that change. `mut_recheck_census_only.txt`: MV12,
  MV17, MV19 CENSUS-ONLY and R3G06 KILLED by `TestRestoreCreatedAtR4_SidecarSizeBoundary` as well as the census.

After the full run, one comment-only edit was made to the header of `created_at_r4_test.go`
(`r4_test_comment_only_diff.txt`); the go test runs below used the edited file.

## Tests

- `go vet ./...`: rc=0 (`vet_r4.txt`).
- `gofmt -l`: the new file is clean. The 17 files listed are the same pre-existing files as in round 3
  (`gofmt_l_r4.txt`).
- `go test -count=1 -v ./...`, twice: 877 PASS / 0 FAIL / 6 SKIP each time, with identical verdict sets. All 796
  round-3 verdicts are unchanged. The 87 new verdicts all come from `created_at_r4_test.go`. A control needle shows
  that the comparison reports a fabricated verdict as missing (`go_summary_r4.txt`, `go_verdicts_r4_run*.txt`,
  `r4_new_tests_v.txt`).
- Applier suite: 100 PASS / 0 FAIL, with an engine built from the round-4 tree (`sh_suite_r4.txt`) and with the
  tracked binary (`sh_suite_r4_tracked_binary.txt`); the two verdict lists are byte-identical. On the round-3
  applier: 91 PASS / 9 FAIL (`sh_red_r4_round3_applier.txt`).
- `CM-GATE-LEDGER-RATCHET`: unimplemented 394, baseline 394, PASS (`ratchet_tail_r4.txt`).
- `run_full_suite.sh --verify-manifest`: MANIFEST-MISMATCH, the same three `scripts/sonarqube/tests/` rows as at
  base `bd0036bd` and in round 3; no file of this vehicle is reported (`verify_manifest_r4.txt`).

## Build

No Go production file changed (`git diff --name-only 50b4863f -- scripts/workable-items/cmd ':!*_test.go'` is
empty). Two rebuilds with `GOEXPERIMENT=nodwarf5 go build -trimpath -buildvcs=false -ldflags=-buildid=` give
`e048a077db3dfcda380ac8cf77bef223db15570b63c6bc9152c171a3dda3d93d`, the same as both tracked binaries, which are
unchanged. `bin/.source.sha256` is re-recorded (`d5077943…` -> `ff62d935…`): its formula includes test files, and
it had been stale since round 3 added `created_at_r3_test.go` (`build_facts_r4.txt`).

## Not shown

- Behaviour on the landed tracker; this is a gate-logic / unit class result only.
- The applier under a real concurrent change: B4 is a deterministic stand-in (a PATH shim), not a race.
- `--root /` (D-08) and empty plan columns (D-09) are registered, not run. D-10 (the fastcycle temporary-directory
  leak) is registered, not changed.
- Byte reproducibility of the tracked binaries across hosts: the rebuild ran on one host.
- `../SHA256SUMS` (round 1) still records the round-1 snapshot, as round 3 stated. `../round2/SHA256SUMS` and
  `../round3/SHA256SUMS` were regenerated over their own file lists, because this round changed files they list.
