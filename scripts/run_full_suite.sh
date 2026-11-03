#!/usr/bin/env bash
# scripts/run_full_suite.sh -- section 11.4.40 full-suite retest runner (wrapper; engine:
# scripts/full_suite/run_full_suite.py, run with python3 -I).
#
# WHAT IS COVERED  Every test entry point of this repository, outside submodules/ and other
#   submodule paths, that the declared manifest config/full_suite_manifest.tsv lists. The
#   CENSUS takes every tracked or untracked-not-ignored file whose basename is test_*.sh,
#   *_test.sh, *selftest*.sh, run_all.sh, test_*.py, *_test.py or *_test.go (a Go file is
#   accounted to its nearest go.mod module, run as `go test -count=1 ./...`). Every census
#   file MUST have exactly one manifest row (class entry | member | fixture); a census file
#   without a row, a stale row, or a row that breaks a rule => exit 3, nothing runs. The
#   census function itself is checked first on a built-in fixture with one known file per
#   pattern plus decoys and a submodule path (control needle); a mismatch is exit 3.
#   NOT covered: submodule contents (each submodule owns its own suites), gate scripts that
#   are not themselves test files (cm_*.sh gates run through their selftests / mutation
#   tests and the pre-build sweep), files whose name fits none of the patterns above.
# UNITS  entry rows run as units. A member row runs only through its covered_by entry, so
#   nothing runs twice. run_all.sh rows declare how they run:
#     runall-whole    run once in both modes (no heavy members)
#     runall-quick    default mode `bash run_all.sh --quick`, full mode without --quick;
#                     the manifest check proves the heavy members are named only inside the
#                     --quick-guarded append
#     runall-members  default mode: the run_all is NOT run (it would run heavy members);
#                     its default members run alone. Full mode: the run_all runs once.
#   Heavy units (tier heavy: mutation / mutant / mutate / chaos / stress / perf names, and
#   their members) run only with --include-heavy and are recorded SKIPPED-heavy otherwise.
# VERDICTS  PASS | FAIL | SKIP(reason) | TIMEOUT | ERROR | SKIPPED-heavy | NOT-RUN
#   TIMEOUT  only when the runner's own timer fired (elapsed reached --timeout).
#   ERROR    rc 124/137 or any signal death without the runner's timer (killed_by_signal_N,
#            rc_137_without_runner_timeout), rc 126/127 (could not execute).
#   SKIP     rc 77, or rc 0 with a terminal (last non-empty) line VERDICT|RESULT|...: SKIP
#            (exact token; SKIPPED / SKIPPING do not count). SKIP is never PASS.
#   rc 0 otherwise: the last counts line within the last 8 non-empty log lines decides
#            (pass/passed/ok/killed, fail/failed/failures/errors/survivors, skip/skipped,
#            total/cases/checks/tests/ran as key=N, key: N, "N passed", "failed N",
#            "ran N"): failed>0 => FAIL; zero checks => FAIL; only skips => SKIP; else PASS
#            (verdict_source=summary). A terminal RESULT/VERDICT FAIL => FAIL. Go: `ok` /
#            `FAIL` lines. No recognised summary => PASS with verdict_source=exit-code-only,
#            counted and listed separately in the summary and the RESULT line.
#   other non-zero rc => FAIL.
# ISOLATION  each unit: `nice -n 15 ionice -c3 <runner> <path> [args]`, cwd = root (Go:
#   the module dir), own session/process group, stdin /dev/null, CLEAN environment: only
#   PATH LANG LC_ALL LC_CTYPE TERM USER LOGNAME TZ are passed from the caller (plus names
#   given with --env-extra NAME), HOME / TMPDIR / XDG_{CONFIG,CACHE,DATA,STATE}_HOME point
#   into a fresh per-unit directory, FULL_SUITE_UNIT_TOKEN is a random per-unit token; Go
#   units add GOCACHE (fresh), GOMODCACHE (host value), GOFLAGS=-mod=readonly, GOPROXY=off,
#   GOTOOLCHAIN=local, GOTELEMETRY=off. Variable NAMES are recorded, values never printed.
#   After the unit (and on timeout: SIGTERM then SIGKILL to the group after 10 s, pgid > 1
#   asserted, section 11.4.263) every own-uid process whose environment still carries the
#   token is killed and counted as leaked. Limit: a process that cleared its environment
#   and left the group is not found. The per-unit directory is removed with safe_rm_rf.
# KNOWN  --known FILE (default config/full_suite_known_failures.tsv): TAB rows
#   path, signature, tracked_id, note. A FAIL/TIMEOUT/ERROR is KNOWN only when its path is
#   EXACTLY a row's path and the signature matches (a literal substring of the unit log,
#   or `reason:<code>` equal to the verdict reason). KNOWN is listed, never hidden, and
#   does not fail the run. Only OPEN failures belong in the table.
# RESUME  records are keyed by (unit = path + args, HEAD sha, working-tree hash, runner
#   hash). The tree hash covers git status, git diff HEAD and untracked file contents, so
#   a dirty or different tree re-runs. Invalid / truncated results.jsonl lines are counted
#   and ignored (their unit re-runs). --rerun-nonpass re-executes recorded FAIL / TIMEOUT /
#   ERROR / SKIP units.
# OUTPUT  <out>/results.jsonl, <out>/logs/NNNN.log, <out>/summary.txt. Default out:
#   ${XDG_CACHE_HOME:-$HOME/.cache}/full_suite_runner/<repo>-<sha12>-<tree12>; an --out
#   inside the repository is refused.
# EXIT / RESULT line
#   0 RESULT: OK-FULL              every unit run (--include-heavy), nothing unexplained
#   1 RESULT: FAIL                 an unexplained FAIL/TIMEOUT/ERROR, or the tree changed
#   2                              usage or configuration error
#   3 RESULT: MANIFEST-MISMATCH    census != manifest, a rule broken, or the census needle failed
#   4 RESULT: PARTIAL              some units not run (--only, interrupted)
#   5 RESULT: OK-DEFAULT-SET-ONLY  default set clean, heavy units NOT run: not a
#                                  section 11.4.40 full retest (use --include-heavy)
# USAGE  run_full_suite.sh [--root DIR] [--out DIR] [--timeout SEC] [--include-heavy]
#          [--known FILE] [--manifest FILE] [--rerun-nonpass] [--only REGEX]
#          [--env-extra NAME]... [--list] [--verify-manifest] [--generate-manifest [--write]]
#   --timeout: positive integer seconds per unit (default 900; run_all and Go units 2x).
#   Scratch for per-unit homes: $FULL_SUITE_TMPDIR, else $TMPDIR, else /tmp.
# SELFTEST  bash tests/test_run_full_suite.sh ; paired mutations:
#   bash tests/test_run_full_suite_mutations.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
exec python3 -I -B "$HERE/full_suite/run_full_suite.py" "$@"
