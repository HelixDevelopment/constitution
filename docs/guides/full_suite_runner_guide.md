# Full-suite retest runner (§11.4.40)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-03 |
| Last modified | 2026-11-03 |
| Status | draft; review round 1 returned NO-GO (F1-F15), this revision is the round-2 fix; independent review owed (§11.4.142) |
| Script | `scripts/run_full_suite.sh` (engine `scripts/full_suite/run_full_suite.py`) |
| Manifest | `config/full_suite_manifest.tsv` |
| Known failures | `config/full_suite_known_failures.tsv` |
| Self-test | `bash tests/test_run_full_suite.sh`; paired mutations `bash tests/test_run_full_suite_mutations.sh` |

## What is covered, exactly

The runner covers the test entry points that a **census** finds and the **manifest** declares. Nothing else.

- Census: every tracked or untracked-not-ignored file outside submodule paths whose basename is `test_*.sh`, `*_test.sh`, `*selftest*.sh`, `run_all.sh`, `test_*.py`, `*_test.py` or `*_test.go`. A Go test file counts toward its nearest `go.mod` module, which runs as `go test -count=1 ./...`.
- Before anything else the census function runs on a built-in fixture with one known file per pattern, decoys and a submodule path. If it does not return exactly the expected set, the runner stops with exit 3 (the instrument cannot see).
- Every census file needs exactly one manifest row. A file without a row, a row without a file, or a row that breaks a rule stops the runner with exit 3 and `RESULT: MANIFEST-MISMATCH`; nothing runs.
- Not covered: the contents of submodules (each owns its suites), gate scripts that are not test files (the `cm_*.sh` gates run through their selftests and mutation tests and through the pre-build sweep), and any file whose name fits none of the patterns.

`bash scripts/run_full_suite.sh --verify-manifest` prints the census by kind and class. Measured on this tree (2026-11-03): `go/entry=5 py/entry=7 py/member=24 runall/entry=9 sh/entry=300 sh/fixture=3 sh/member=280 total=628`.

## Manifest classes

| Class | Meaning |
|---|---|
| `entry` | run as a unit (runner `bash`, `sh`, `python3`, `go-test`, or one of the three run_all runners) |
| `member` | run only through its `covered_by` entry, never on its own, so nothing runs twice |
| `fixture` | a file under `fixtures/` that matches a pattern but is not a test; never run |

Rules the runner checks: every `member` is really run by its `covered_by` entry (named by stem, or matched by the run_all's own-directory `test_*` glob, minus files named on a `continue` line); a heavy-looking name (`mutation`, `mutant`, `mutate`, `chaos`, `stress`, `perf`) has tier `heavy` unless the row carries an `override:` note; a member of a heavy entry is heavy.

`run_all.sh` runners:

| Runner | Default mode | Full mode |
|---|---|---|
| `runall-whole` | run once | run once |
| `runall-quick` | `run_all.sh --quick` | `run_all.sh` |
| `runall-members` | run_all not run; its default members run alone | run_all once |

`runall-quick` is accepted only when the manifest check proves every heavy member is named only inside the `--quick`-guarded array append. This tree has one (`tests/extensions/run_all.sh`; its `test_integration.sh` is declared heavy by override because `--quick` drops it). `tests/install/run_all.sh` and `tests/prompts/run_all.sh` take `--quick` but still run gate mutation tests, and `tests/decisions/run_all.sh` has no `--quick`, so those are `runall-members`.

Regenerate after adding or removing tests: `bash scripts/run_full_suite.sh --generate-manifest --write` (curated rows are kept), then review the diff.

## Verdicts

`PASS`, `FAIL`, `SKIP(reason)`, `TIMEOUT`, `ERROR`, plus `SKIPPED-heavy` (heavy unit, not run in default mode) and `NOT-RUN` (filtered by `--only` or interrupted).

- `TIMEOUT` only when the runner's own timer fired. A suite's own exit 124 or 137, or a death by signal (for example an OOM kill at 0 s), is `ERROR` with the reason.
- `SKIP`: exit 77, or exit 0 with a terminal (last non-empty) line `VERDICT|RESULT|RUN_ALL|STATUS|SUMMARY: SKIP` (exact token). Never counted as PASS.
- Exit 0 otherwise: the suite's own summary decides. The last counts line within the last 8 non-empty log lines is read (`passed=N failed=M`, `PASS=N FAIL=M`, `N passed, M failed`, `ran N, failed M`, `cases=N failed=M`, `killed=N survivors=M` and similar). `failed>0` is FAIL; zero checks is FAIL; only skips is SKIP. A terminal `RESULT: FAIL` is FAIL. Go units read `ok` / `FAIL` lines.
- Exit 0 with no recognised summary is PASS with `verdict_source=exit-code-only`; these are counted and listed separately and named in the RESULT line.

## Isolation

Each unit runs as `nice -n 15 ionice -c3 <runner> <path> [args]` in its own session, stdin `/dev/null`, with a clean environment: only `PATH LANG LC_ALL LC_CTYPE TERM USER LOGNAME TZ` come from the caller, plus any name given with `--env-extra NAME`. `HOME`, `TMPDIR` and the four `XDG_*` directories point into a fresh per-unit directory; `FULL_SUITE_UNIT_TOKEN` is a random per-unit token. Go units also get a fresh `GOCACHE`, the host `GOMODCACHE`, `GOFLAGS=-mod=readonly`, `GOPROXY=off`, `GOTOOLCHAIN=local`, `GOTELEMETRY=off`. Results record the variable names, never values.

After a unit ends (on timeout: SIGTERM to its process group, SIGKILL after 10 s; the group id is checked to be greater than 1, §11.4.263), every own-uid process whose environment still holds the token is killed and counted as leaked. Limit: a process that cleared its environment and left the group is not found.

## Known failures

`config/full_suite_known_failures.tsv` lists OPEN failures only: path, signature (a literal substring of the unit log, or `reason:<code>`), tracked id, note. A failure is KNOWN only on an exact path match AND a matching signature. It is derived from `docs/design/known_failures_v73.md`, which has no open failing suite at revision 1, so the table is empty and every failure fails the run.

## Resume

Records are keyed by unit (path plus arguments), HEAD sha, a working-tree hash (git status, `git diff HEAD`, untracked file contents) and a hash of the runner. A different commit, a dirty or changed tree, or a changed runner re-runs. Invalid or truncated `results.jsonl` lines are counted and ignored, and their units re-run. `--rerun-nonpass` re-runs recorded FAIL, TIMEOUT, ERROR and SKIP units.

## Usage

```
bash scripts/run_full_suite.sh --verify-manifest    # census + manifest check only
bash scripts/run_full_suite.sh --list               # plan for the default mode
bash scripts/run_full_suite.sh                      # default set (heavy units not run)
bash scripts/run_full_suite.sh --include-heavy      # full set: the §11.4.40 retest
bash scripts/run_full_suite.sh --only REGEX --timeout 300
bash scripts/run_full_suite.sh --rerun-nonpass
```

Output goes to `${XDG_CACHE_HOME:-$HOME/.cache}/full_suite_runner/<repo>-<sha12>-<tree12>` unless `--out` is given; an `--out` inside the repository is refused. Progress: `wc -l <out>/results.jsonl` and the per-unit lines on stdout; final report in `<out>/summary.txt`.

## Exit status and RESULT line

| Exit | RESULT | Meaning |
|---|---|---|
| 0 | `OK-FULL` | every unit ran (full mode), nothing unexplained |
| 1 | `FAIL` | an unexplained FAIL, TIMEOUT or ERROR, or the repository tree changed during the run |
| 2 | | usage or configuration error |
| 3 | `MANIFEST-MISMATCH` | census and manifest disagree, a rule is broken, or the census needle failed |
| 4 | `PARTIAL` | some units did not run (`--only`, interrupted); not a §11.4.40 retest |
| 5 | `OK-DEFAULT-SET-ONLY` | the default set is clean but heavy units did not run; not a §11.4.40 retest |

Only exit 0 from a run with `--include-heavy` is a §11.4.40 full-suite retest.

## Limits

- The summary recognisers cover the forms used in this repository; a new form yields `exit-code-only`, which is labelled, not hidden.
- Reading only the last 8 lines means a summary printed earlier and followed by more than 8 lines of output is not seen.
- Membership of a run_all is checked by name or glob in its text, not by running it; a run_all that builds names in a way the check cannot see needs a curated row.
- Leak detection depends on the token staying in the environment.
