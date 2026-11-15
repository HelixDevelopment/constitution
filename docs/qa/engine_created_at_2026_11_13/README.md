# CON-339 evidence: the engine keeps `items.created_at`, and `restore-created-at` repairs rows it rewrote

| Field | Value |
|---|---|
| Revision | 1 |
| Last modified | 2026-11-13T21:44:03Z |
| Item | CON-339 (workable-items engine defect); commit trailer `Roadmap-Item: CON-PENDING-ENGINE-CREATEDAT` |
| Base | `bd0036bd` (main at the time of the work) |
| Status | PROVISIONAL (§11.4.290): gate-logic / unit class evidence on the real engine binary and real SQLite databases (copies of committed tracker databases and test fixtures, §11.4.289(C)); not independently reviewed yet (§11.4.142); the restore plan was NOT applied to the real tracker |
| Operator decision | 2026-11-13, interactive: add the engine-side restore path now, so the created_at of CON-243 and CON-308 can be restored through the engine and never by hand (§11.4.93) |

All runs on 2026-11-13 on this host, in a scratch clone of the repository; the real tracker (`docs/workable_items.db`
of the working checkout) was never opened. In the captured files `<scratch>` stands for the session scratch
directory and `<tmpdir>` for the host temporary directory; those path prefixes are the only edit made to the
captured output.

## Reproduction record (§11.4.292)

**Reproduction:** reproduced-host-fixture — surface `host-only` (the engine is a host CLI; real code, real input) —
command `bash docs/qa/engine_created_at_2026_11_13/repro_con339.sh scripts/workable-items/bin/workable-items <copy of
git show bd0036bd:docs/workable_items.db> CON-243 CON-244 docs/qa/engine_created_at_2026_11_13/repro_con339.sh` —
RED `red_repro_con339.txt` — engine `9edd2dc3dfe33dd33ad4583256bd8c96650cf7edd01b77da5022d701f2a70e2c` (the tracked
binary at `bd0036bd`) — target: a copy of the committed database, sha256
`117126b045a86f4387e3092836867e0dd82b6fa17676e23098ca81c70b2fcbf4` — symptom signature `C1 VERDICT REWRITTEN`
(close) and `created_at unchanged 0, changed 263` (sync md-to-db) — control needles: an `update --title` on the
same row keeps created_at (in-place control), a known-present created_at is read, an impossible id reads empty.

The promoting GREEN uses the same script on the same copy with the fixed engine (`toggle_experiment_run.txt`, leg
`full-fix`: `C1 VERDICT preserved`, `created_at unchanged 263, changed 0`).

**Investigation:** root-cause-found-with-evidence. Two writers deleted an `items` row and inserted it again without
the `created_at` column, so the column default `datetime('now')` stamped the write time:

- `closeCmd` (`crud.go`): `close` deletes the Issues row and inserts the Fixed row;
- `replaceDocument` (`db.go`, called by `sync md-to-db`): deletes every row of a document and inserts them all again.

Decisive experiment (`toggle_experiment.sh`, output `toggle_experiment_run.txt`): three builds of the same source
tree, each run through the same repro script on fresh copies of the same database:

| Build | close (C1) | sync md-to-db (S1) |
|---|---|---|
| base (`bd0036bd` source) | REWRITTEN | REWRITTEN |
| close fix only | preserved | REWRITTEN |
| full fix | preserved | preserved |

Each fix site toggles exactly its own leg, so the two sites are the cause and the only cause the two legs see.

## Files

| File | What it is |
|---|---|
| `repro_con339.sh` | the reproduction (C0 in-place control, C1 close, S1 sync round trip; exit 1 when created_at was rewritten) |
| `toggle_experiment.sh` | the decisive experiment (three builds through `repro_con339.sh`) |
| `restore_plan.tsv` | the restore plan for CON-243 and CON-308, as data (value, evidence commit, path, sha256, attesting row, reason, id per landing) |
| `apply_restore_plan.sh` | applies the plan through `restore-created-at`: extracts each evidence database with `git show`, checks its sha256, runs the engine (dry run by default, `--apply` to write) |
| `landing_demo.sh` | what the tracker-intake landing oracle (`remint_ids.py verify`, shipped by the vehicle `b48091ea`) reports before and after the plan, on copies only |
| `red_repro_con339.txt` | RED: the tracked engine rewrites created_at on close and on a sync round trip (exit 1) |
| `red_go_tests_base.txt` | RED: the new property tests run against the base source: `TestCON339_CreatedAtPreservedByEveryMutatingCommand` (subtests close-fixed, close-obsolete, close-completed, sync-roundtrip), `TestCON339_MDToDBMoveAcrossDocumentsKeepsCreatedAt`, `TestCON339_CommandEnumerationGuard`, `TestCON339_ItemsWriteSitesCarryCreatedAt` FAIL |
| `red_restore_tests_base_compile.txt` | RED: the restore and snapshot tests do not compile against the base source (the functions do not exist) |
| `toggle_experiment_run.txt` | the decisive experiment, `TOGGLE RESULT: matches`, exit 0 |
| `go_verdicts_base.txt` | Go suite verdicts on the base source: 573 PASS, 0 FAIL, 6 SKIP |
| `go_verdicts_run1.txt`, `go_verdicts_run2.txt`, `go_summary.txt` | Go suite after the change, twice: `go vet` exit 0; each run 636 PASS, 0 FAIL, 6 SKIP (642 verdicts); the two verdict sets are byte-identical (sha256 `152cd673…`); all 579 base verdicts are present unchanged, 63 are new |
| `mutation_run1.txt` | paired mutation runner, first full run: 25 killed, 2 mutants did not compile (test-harness defect in the mutant text, fixed) |
| `mutation_run1b_two_rewritten.txt` | the two rewritten mutants: both killed |
| `mutation_run2.txt` | second full clean run: unmutated control PASS, 27 of 27 mutants killed, exit 0 (about 17 minutes; the first run took about 23) |
| `states_mutation_run.txt` | the existing engine mutation runner (`states_mutation_runner.py`) on the changed source: control PASS, 19 of 19 killed, exit 0 |
| `landing_demo_run.txt` | `landing_demo.sh` on copies (see the next section), `RESULT: OK`, exit 0 |
| `shipped_binary_us3_test.txt` | `scripts/fastcycle/tests/test_shipped_workable_items_us3_red.sh` against the rebuilt tracked binary: all hold |
| `sidecars_test.txt` | the tracked-database sidecar test: 6 passed, 0 failed |
| `ratchet_tail.txt` | `scripts/gates/cm_gate_ledger_ratchet.sh`: unimplemented 394 = baseline 394, PASS (no new gate name) |
| `verify_manifest_before.txt`, `verify_manifest_after.txt` | `bash scripts/run_full_suite.sh --verify-manifest` before and after adding the manifest row for the new runner: the new runner's row is the only difference; three problems for `scripts/sonarqube/tests/test_registry_login*.sh` are pre-existing at `bd0036bd` and outside this change |
| `sync_guide.txt` | `bash scripts/run_full_suite.sh --sync-guide` (census total 901 to 902) |
| `gofmt_l.txt` | `gofmt -l` of the engine after the change; the same list as on the base source (no new unformatted file; `db.go` was already unformatted at the base, and its `gofmt -d` hunk set is unchanged) |
| `shellcheck.txt` | shellcheck 0.11.0 on the four scripts above: clean |
| `build_facts.txt` | how the tracked binaries were rebuilt, their sha256, the new `bin/.source.sha256`, and the `.comment` of the old and new binaries |
| `SHA256SUMS` | sha256 of every file in this directory except itself |

## The restore plan and what the landing oracle reports

The plan restores two rows:

| Item (vehicle id) | Value | Attested by |
|---|---|---|
| CON-243 | `2026-11-11 15:34:35` | `item_history` id 455 (`Opened`) in `git show bd0036bd:docs/workable_items.db` (sha256 `117126b0…`). The items row there holds `2026-11-11 15:38:57`, a stamp of an earlier `sync md-to-db` (the second site of this defect), 4 min 22 s after the item was opened; the engine refuses that value because it is later than the item's first history row |
| CON-308 | `2026-11-12 22:48:51` | the items row (Issues, section) in `git show 1a307322:docs/workable_items.db` (sha256 `6854c6a1…`); its `Opened` history row holds the same time. The vehicle `b48091ea` holds `2026-11-13 13:56:42`, the time its close rewrote the value |

`landing_demo.sh` runs three legs on copies (output `landing_demo_run.txt`):

| Leg | `verify` before the plan | after the plan | `validate` after |
|---|---|---|---|
| FF: fast-forward landing (the landed database is the vehicle's) | PASS, known 0 | FAIL by design: 3 mismatches (rows CON-243 and CON-308, and table `item_history`, which gained the two audit rows) | OK, 307 items |
| R-OLD: replay onto `bd0036bd` with the old engine | PASS, known 46 | PASS, known 46 | OK, 307 items |
| R-NEW: replay onto `bd0036bd` with the new engine | PASS, known 45 | PASS, known 46 | OK, 307 items |

A second application of the plan writes nothing (`already`) in both replay legs. A control in the FF leg asks the
engine to set CON-243 to the target's own `15:38:57` and is refused `[VALUE-AFTER-FIRST-EVENT]`, exit 1.

**Why the count does not go down to 44.** `remint_ids.py verify` counts, in a replay landing, one KNOWN line per own
item whose created_at differs from the vehicle (44 own items get the replay time; this is the re-mint design, not
this defect), one per base item whose created_at differs from the target (CON-243, only when the replayed close
rewrote it, so 1 with the old engine and 0 with the new one), and one for CON-308's lifecycle history (history is not
carried, M-14). So: old engine 44 + 1 + 1 = 46, new engine 44 + 0 + 1 = 45. The plan does not bring either value
back to the one the oracle compares against, because those values are themselves rewritten: the target's CON-243
value `15:38:57` is the md-to-db stamp, and the vehicle's CON-308 value `13:56:42` is the close stamp. After the plan
CON-243 holds its Opened time and differs from the target again (counted again: 46 in both legs), and CON-308 still
differs from the vehicle (still counted). The oracle labels both as before ("close rewrites it", "replay time"),
which is now misleading; `remint_ids.py` lives on the vehicle, not on this base, so recognising the restore audit
row there is a follow-up for the lander. Carrying the other 43 own items' vehicle times with `restore-created-at`
(the vehicle database as evidence) might lower the count further; that was not tried.

**Order on a fast-forward landing.** A fast-forward `verify` demands the landed database equal the vehicle row for
row, including `item_history`. Run `verify` first, then the plan.

**How the lander applies it** (from the repository root, after the landing and its `verify`):

```bash
bash docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh \
  --engine scripts/workable-items/bin/workable-items --db docs/workable_items.db --landing main          # dry run
bash docs/qa/engine_created_at_2026_11_13/apply_restore_plan.sh \
  --engine scripts/workable-items/bin/workable-items --db docs/workable_items.db --landing main --apply
scripts/workable-items/bin/workable-items validate --db docs/workable_items.db
```

`--landing fix227` takes the ids of the replay landing onto fix227 (CON-308 becomes CON-321; UNCONFIRMED, see
below). The script extracts the evidence databases to `docs/qa/engine_created_at_2026_11_13/evidence/` (mode 0600,
about 1.3 MB each); they can be re-created at any time with `git show`, so committing them is the lander's decision.
The audit history row names the evidence path, its sha256, the attesting row and the reason, and the reason names
the commit the evidence comes from.

## UNCONFIRMED

- The fix227 landing (`fed933c0`) was not reproduced: that commit and its database are not in this clone. The
  `id_fix227` column comes from the mapping in the r4 README (own CON-299..342 to CON-312..355).
- Byte reproducibility across hosts: the previous tracked binary (`9edd2dc3`) was linked with ALT Sisyphus gcc
  15.3.1; this host has Ubuntu gcc 15.2.0 and rebuilds the base source to a different hash (`a3d7a6c3`, measured in
  `toggle_experiment_run.txt`). The new binary (`f6555769`) is reproducible on this host (two builds, one hash).
- Readers of `created_at` outside the engine (`scripts/fastcycle/closure/reopen_rate.py`, `escape_classify.py`,
  `scripts/fastcycle/cycle/cycle_report.py`, `select_sample.py`) were not examined; whether they read this column of
  this database is not known. The engine itself does not render created_at into the Markdown documents.

## Honest limits

- The engine cannot prove that an evidence file is the committed database it claims to be; it checks the sha256 the
  caller names and records it in the audit row.
- `restore-created-at` changes one row at a time and only to an earlier value that a separate database records.
  It does not repair the 226 of 263 rows at `bd0036bd` whose created_at is later than their first `item_history`
  row (measured: 222 hold `2026-11-11 15:38:57`, 4 hold `2026-11-11 15:34:52`, two batch times that fit earlier
  document rebuilds; the cause of each row was not traced); that is a separate decision, drafted as a tracked item
  in `round2/follow_up_register.md`. Restoring CON-243 alone makes this set non-uniform: CON-242 and CON-244, opened
  in the same second (`15:34:35`), keep `15:38:57` (also drafted there).
- Found by the round-1 independent review (pre-existing on the base `bd0036bd` as well): an unchanged
  `db-to-md` then `md-to-db` round trip rewrites `description` on 38 rows (replaced with different text, for example
  CON-030, CON-246) and sets `severity` to NULL on 3 rows (CON-266, CON-267, CON-268, `Low` to NULL). That is silent
  data loss on every round trip; drafted as a tracked item in `round2/follow_up_register.md`; not fixed here.
- `apply_restore_plan.sh` applies the plan row by row, one engine call and one transaction per row; with a wrong
  database the rows before the failing one stay applied and the script exits 1. It is not atomic across rows.
- Not part of this change and found while working on it (each a candidate item): `group set --item`, `repair-bodies`,
  `version-tags` and `sync md-to-db` write no history rows; `close` drops `forensic_anchor`, `closure_criteria`,
  `composes_with`, `parent_atm_id`, `session_ref` and `version_tags`; `sync md-to-db` drops `destination`,
  `logic_group`, `parent_atm_id`, `session_ref`, `version_tags` and resets `last_modified`; `subtask add` and
  `subtask status` are not dispatched by `main()`; the vehicle `b48091ea` has duplicated `Obsolete` history rows
  (ids 592/593, 614/615, 616/617); the compare-and-set clause of `restore-created-at` is not exercised under real
  concurrency by any test.

## Round 2

The round-1 review returned NO-GO (F1 to F8). The round-2 fixes, their RED and GREEN logs, the mutation runs and the
follow-up register are in `round2/` (start with `round2/README.md`).
