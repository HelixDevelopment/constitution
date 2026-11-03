# Full-suite retest runner (§11.4.40)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-03 |
| Status | draft; independent review owed (§11.4.142) |
| Script | `scripts/run_full_suite.sh` |
| Self-test | `bash tests/test_run_full_suite.sh` |

## What it does

Runs every suite of the repository strictly one at a time (`nice -n 15`, `ionice -c3`, per-suite timeout, fresh temporary `HOME`, own log) and records one verdict per suite from the suite's own exit code or terminal line.

Enumerated: `tests/*/run_all.sh`, `tests/**/test_*.sh`, `scripts/gates/*_selftest.sh` (default set) and `scripts/gates/cm_*_mutation_test.sh` (heavy set: listed as `SKIPPED-heavy`, reason `heavy_excluded`, run only with `--heavy`). Note that a `test_*.sh` under a directory that also has a `run_all.sh` may run twice (once alone, once through `run_all.sh`); the runner does not de-duplicate.

## Verdicts

`PASS`, `FAIL`, `SKIP(reason)`, `TIMEOUT`, `ERROR` (plus `SKIPPED-heavy` for the unrun heavy set). SKIP (exit 77, or exit 0 with a terminal `VERDICT|RESULT: SKIP` line) is never counted as PASS and does not fail the run. Exit 124/137 is TIMEOUT, 126/127 is ERROR, any other non-zero is FAIL.

## Usage

```
bash scripts/run_full_suite.sh                 # default set, out = .full_suite_out/<HEAD sha>
bash scripts/run_full_suite.sh --list          # enumerate only
bash scripts/run_full_suite.sh --heavy         # include mutation suites
bash scripts/run_full_suite.sh --only REGEX --timeout 300
bash scripts/run_full_suite.sh --rerun-nonpass # re-run recorded FAIL/TIMEOUT/ERROR
```

Re-running with the same `--out` and the same HEAD resumes: suites already recorded for that sha are skipped. Progress: `wc -l <out>/results.jsonl`, `tail <out>/run.log` if the run was started with output redirected there, final report in `<out>/summary.txt`.

## Known failures

A FAIL/TIMEOUT/ERROR whose path (or CM-NAME for `cm_*` gates) occurs literally in `docs/design/known_failures_v73.md` is flagged KNOWN (`"known":true`), listed in the summary and not counted toward a non-zero exit. The match is coarse and literal; whether the documented cause is the cause of a given run is UNCONFIRMED until read.

## Exit status

0 when no unexplained FAIL/TIMEOUT/ERROR; 1 otherwise; 2 on a usage error.
