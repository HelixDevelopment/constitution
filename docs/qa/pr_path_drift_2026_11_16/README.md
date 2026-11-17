# Pull-request landing path runs the derived-file drift checks (CON-443, CON-444) — 2026-11-16

| Field | Value |
|---|---|
| Items | CON-443 (PR merge path skipped step 6b), CON-444 (D9-D12 missing, reviewer mutants R01/R02/R03/R07 surviving) |
| Base | main `1dfbb4d19bdd3b3e482d45814a9b9ad831f1c730` |
| Evidence class | gate-logic, host-only (§11.4.289); the check scripts in the D and P cases are unit-class stand-ins, L1 runs the real checks on a clone of this repository |
| State | PROVISIONAL (§11.4.290): fixed in a vehicle, not landed, not independently reviewed, no verification job scheduled; both items stay `In progress` |
| Effort | UNKNOWN (the dispatch path does not report it, §11.4.231(F.2)) |

## What changed

* `scripts/release/lib/landing_drift_checks.sh` (new): the one check list (`DRIFT_CHECKS`: README badge
  row `compute_badges.sh --check`, env-read allowlist `cm_gate_env_reads_allowlisted.sh`) and the one
  runner `ldc_run <root> <base> <head> <evdir>`. Moved out of `land_vehicle.sh` unchanged in behaviour
  (timeout 900 s per check, `FAIL-timeout` on rc 124, `FAIL-script-missing`, dirty-tree and ref-moved
  refusals, `drift_checks.tsv` plus one `drift_<check>.log` per check).
* `scripts/release/land_vehicle.sh`: sources the library at start-up (refuses with exit 2 when it is
  missing); `drift_checks` is now a two-line wrapper around `ldc_run`.
* `scripts/release/pr_landing_check.sh` (new): the PR-side entry point. It builds the candidate the
  merge would produce (fast-forward, or `git merge-tree --write-tree` plus `commit-tree` for a merge
  commit) in a private `clone --shared --no-checkout` clone, checks out the candidate detached and runs
  `ldc_run` on it. `RESULT: PASS` exit 0, `RESULT: FAIL` exit 1, `RESULT: BLIND` exit 2. `--repo` is not
  changed (P12).
* Tests: `tests/release/test_land_vehicle.sh` gains D9-D14b; `tests/release/test_pr_landing_check.sh`
  (new) has P1-P15 and L1. `config/full_suite_manifest.tsv` gains the new test row.

## Reproduction (CON-443), §11.4.292

Command (tool kept here as `tools/repro_pr_path.sh.txt`):
`bash tools/repro_pr_path.sh <clone> <out> stale`. It builds a local bare forge from the clone's main,
pushes a PR branch whose README badge row is stale, and lands it the way a §11.4.297 PR merge lands
(merge commit, second parent = reviewed head, pushed to forge main). No remote outside the scratch
directory is touched.

| Run | Clone at | Control needle (badge check base / PR head) | Result |
|---|---|---|---|
| `red/repro_run1.txt`, `red/repro_run2.txt` | 1dfbb4d1 | 0 / 1 | `RESULT LANDED-STALE` (forge main 79744a48 fails the badge check, rc 1) |
| `green/repro_stale_run1.txt`, `_run2.txt` | 695de4d9 | 0 / 1 | `RESULT REFUSED` (pr_landing_check rc 1, badges FAIL, env PASS) |
| `green/repro_fresh_run1.txt`, `_run2.txt` | 695de4d9 | 0 / 0 | `RESULT LANDED-CLEAN` (golden-FALSE: a fresh row is not refused) |

The control needle proves the instrument can see: the badge check exits 0 on the base and 1 on the
stale head, so a `LANDED-STALE` cannot come from a blind check. The decisive toggle is the presence of
the PR-side check on the same repro: absent gives `LANDED-STALE`, present gives `REFUSED`. Each run was
repeated twice with identical result lines.

Note on the RED log: the line `tools/repro_pr_path.sh: line 23: docs/qa/pr_path_drift_2026_11_16/README.md: No such file or directory`
is expected. On the base the directory does not exist yet, so the `>>` append fails and the `||`
fallback creates the file; the PR change is still made (the commit and both control needles follow).

Root cause: no PR-side entry point ran the step-6b checks; the check list and the runner existed only
inside `land_vehicle.sh publish`.

`red/test_pr_landing_check_absent_script.txt`: the new test run against a repository without
`pr_landing_check.sh` exits 1 (RED before the fix).

## Tests

* Lander drift-only suite (`LANDER_TEST_DRIFT_ONLY=1`): `RESULT pass=30 fail=0` with D1-D14b.
  * D9 timeout (PATH shim proves the 900 s budget is passed and runs a real `timeout` of 2 s),
    D10 a check exiting 2 (BLIND) refuses, D11 main moved during the checks refuses with a clean tree,
    D12 exact `drift_checks.tsv` content plus the per-check log and cwd, D13 missing library refuses at
    start-up, D14/D14b the fast-forward landing path (`--item-id`) refuses on FAIL and lands on PASS,
    with the prepare log asserted to name the fast-forward.
* PR check suite (`RESULT pass=31 fail=0 skip=0`): P1-P15 unit cases (P15: the candidate moved during the checks is refused, the PR binding `LDC_REF=HEAD`) plus L1 (real checks on a clone of this repository: a stale
  anchors row is RED rc 1, the row regenerated with `--print` is GREEN rc 0, control needle on the base first).

## Mutants (§1.1, §11.4.194(6)(d))

`mutants/mutants.tsv` (runner `tools/mutants_con443.py.txt`). The runner copies `scripts/release`,
`scripts/lib` and `tests/release` into a temporary tree, applies one exact-substring change (the
substring must occur once) and runs the suites named in the row. CONTROL (no change) passed first.

| Mutant | Suites | rc | Verdict | Run | Note |
|---|---|---|---|---|---|
| `CONTROL` | lv,pr | lv:0(145s) pr:0(19s) | CONTROL-PASS | run1 |  |
| `L01-no-timeout(R01)` | lv | lv:1(150s) | KILLED | run1 |  |
| `L02-rc2-pass(R02)` | lv,pr | lv:1(141s) pr:1(11s) | KILLED | run1 |  |
| `L03-no-ref-moved(R03)` | lv,pr | lv:1(142s) pr:1(17s) | KILLED | run3 | run1 killed by the lander suite only (pr:0); P15 added; run3 killed by both (D11, P15). |
| `L04-log-discarded(R07)` | lv | lv:1(181s) | KILLED | run1 |  |
| `L05-run-not-in-root(R09)` | lv | lv:1(133s) | KILLED | run1 |  |
| `L06-return-0` | lv,pr | lv:1(23s) pr:1(1s) | KILLED | run1 |  |
| `L07-no-timeout-label` | lv | lv:1(52s) | KILLED | run1 |  |
| `L08-required-head-only` | lv,pr | lv:1(35s) pr:1(4s) | KILLED | run1 |  |
| `L09-untracked-no` | lv,pr | lv:1(41s) pr:1(4s) | KILLED | run1 |  |
| `L10-badges-dropped` | lv,pr | lv:1(9s) pr:1(0s) | KILLED | run1 |  |
| `V01-lander-skips-drift` | lv | lv:1(11s) | KILLED | run1 |  |
| `V02-lander-ref-HEAD` | lv | lv:0(135s) | SURVIVED | run1 | EQUIVALENT-OR-STRICTER: do_publish refuses unless HEAD is the symbolic ref refs/heads/main (land_vehicle.sh do_publish, "clone is not on main") before the checks run, so HEAD and refs/heads/main name the same commit when ldc_run reads LDC_REF; they differ only if a check repoints HEAD, where the mutant refuses (stricter). The pushed commit is $local_main either way. Follow-up CON-PENDING-drift-check-head-repoint. |
| `V03-lander-missing-lib-ok` | lv | lv:1(128s) | KILLED | run1 |  |
| `P01-pr-skips-checks` | pr | pr:1(1s) | KILLED | run1 |  |
| `P02-pr-checks-head-not-candidate` | pr | pr:1(3s) | KILLED | run1 |  |
| `P03-pr-conflict-passes` | pr | pr:1(4s) | KILLED | run1 |  |
| `P04-pr-ff-only-ignored` | pr | pr:1(4s) | KILLED | run1 |  |
| `P05-pr-checkout-head` | pr | pr:1(3s) | KILLED | run1 |  |
| `P06-pr-merge-as-ff` | pr | pr:1(3s) | KILLED | run1 |  |
| `P07-pr-bad-rev-pass` | pr | pr:1(5s) | KILLED | run1 |  |
| `P08-pr-missing-lib-ok` | pr | pr:1(15s) | KILLED | run2 | run1 SURVIVED (the source line `. lib // blind` gives the same BLIND exit 2); P14b added (the refusal must name the missing library path); run2 KILLED by P14b. |
| `CONTROL` | lv,pr | lv:0(164s) pr:0(13s) | CONTROL-PASS | run2 |  |
| `V04-lander-always-merge` | lv | lv:1(157s) | KILLED | run2 | pairs D14: killed by "D14 prepare path". |

Killed: 21 of 22 non-control mutants (2 CONTROL rows, both PASS). Survived: V02, recorded equivalent-or-stricter with its proof in the note column.

Reviewer mutants on the BASE (CON-444 RED): `mutants/base_mutants.tsv` (runner
`tools/base_mutants.py.txt`, run on a checkout at 1dfbb4d1 with that checkout's own drift-only suite).

| Mutant (base 1dfbb4d1) | rc | Verdict |
|---|---|---|
| `CONTROL` | 0 | CONTROL-PASS |
| `R01-no-timeout` | 0 | SURVIVED |
| `R02-rc2-blind-pass` | 0 | SURVIVED |
| `R03-no-main-moved` | 0 | SURVIVED |
| `R07-log-discarded` | 0 | SURVIVED |

All four reviewer mutants survive on the base (RED for CON-444). On the fix they map to L01, L02, L03 and L04 and are all killed.

## Gates (`gates/`)

| Gate | Result |
|---|---|
| `scripts/validation/git_env_class_census.py` | PASS, members=656 unscrubbed=0, control needles seen |
| `scripts/gates/cm_gate_ledger_ratchet.sh` | PASS, unimplemented=394 baseline=394 |
| `run_full_suite.py --verify-manifest` | MANIFEST-OK (after `--sync-guide`, see below) |
| `scripts/gates/cm_gate_env_reads_allowlisted.sh` | PASS, uncovered=0 stale=0 needle=ok |
| `scripts/badges/compute_badges.sh --check` | README badge row matches |

Defect found in the first commit (695de4d9) and fixed in the second: it added the new test to
`config/full_suite_manifest.tsv` but did not regenerate the census block of
`docs/guides/full_suite_runner_guide.md`, so `--verify-manifest` reported MANIFEST-MISMATCH. Control:
the base checkout (1dfbb4d1) reports MANIFEST-OK, so the mismatch came from this change. The
regenerated block changes one count (`sh/entry` 388 to 389, total 957 to 958).

Defect found after the second commit (f1b6c351) and fixed in the third: the evidence copy
`tools/det_runs.sh.txt` kept the exec bit of the helper, so the git-env census counted it as a shell
member and failed it (UNSCRUBBED, its scrub line lacked the canonical trailing `unset _ge_v`). The
census rule is that a `.txt` file is data unless executable. The helper now carries the canonical line
and the copy is mode 644; census PASS, unscrubbed=0.

Tracker: engine `update` for CON-443 and CON-444 (status `In progress`, reproduction and investigation
states recorded), `export --no-formats --out-dir docs`, `validate` OK (443 items), `diff` against
`docs/Issues.md` and `docs/Fixed.md`: in sync.

## Determinism (`suites/det_summary.tsv`, runner `tools/det_runs.sh.txt`)

| Suite | Run 1 | Run 2 | sha256 of the PASS/FAIL/SKIP/RESULT lines |
|---|---|---|---|
| `tests/release/test_land_vehicle.sh` (full) | pass=360 fail=0, 1331 s | pass=360 fail=0, 1750 s | `7e4f6c9b...efad3ee8` in both runs |
| `tests/release/test_pr_landing_check.sh` (with L1) | pass=31 fail=0 skip=0, 59 s | same, 53 s | `c7b78448...361f8177` in both runs |

## Class inventory (§11.4.276(C))

`class_inventory.md`, instrument output `census.txt`. Paths 1-3 (lander fast-forward, lander merge,
PR merge) run the same `ldc_run` with the same list. Path 4 (`tag_and_release.sh`) runs a subset and
path 5 (a hand-typed push) runs nothing; both are recorded in `followups.md`.

## Limits (§11.4.6)

* The PR check is a procedure step, not enforced: a forge merge made without it is not refused by
  anything in this repository (no CI, §11.4.156).
* Whether the forge's merge produces the same tree as `git merge-tree --write-tree` for every PR is
  UNCONFIRMED (no live forge run, by brief rule).
* `tag_and_release.sh` runs only the badge check (follow-up).
* L1 is host-only gate-logic evidence; nothing here is live-class evidence of a forge merge.
* PROVISIONAL; independent review (§11.4.209) is owed before landing.
* The commits carry only `Roadmap-Item: CON-443` and `Co-Authored-By` (the trailer set the brief
  fixes). Edits outside `scripts/release` and `tests/release` (`config/full_suite_manifest.tsv`, the
  regenerated census block in `docs/guides/full_suite_runner_guide.md`, the tracker exports) are the
  registration and generated-regeneration of the new test and the tracker update; no `Out-of-scope:`
  trailer names them (§11.4.293(A)); the reviewer may require one.
