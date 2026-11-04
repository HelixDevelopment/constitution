#!/usr/bin/env bash
# scripts/run_full_suite.sh -- section 11.4.40 full-suite retest runner (wrapper; engine:
# scripts/full_suite/run_full_suite.py, one file, run with python3 -I).
# Full documentation: docs/guides/full_suite_runner_guide.md.
#
# WHAT IS COVERED  Every test entry point of this repository, outside submodule paths, that
#   the manifest config/full_suite_manifest.tsv declares. The CENSUS takes every tracked or
#   untracked-not-ignored file that is named test_*.sh, *_test.sh, *selftest*.sh,
#   run_all.sh, test_*.py, *_test.py or *_test.go, or that is a script (.sh/.bash/.py in any
#   letter case, or no extension with a shell/python shebang) under a tests/ or test/
#   directory or whose name contains test|mutant|mutation|smoke|selftest (any case). A Go
#   file counts toward its nearest go.mod module (`go test -count=1 ./...`). Every census
#   file needs exactly one manifest row of class entry | member | fixture | excluded
#   (excluded: not a test; note `reason: <why>`). A file without a row, a stale row, a
#   broken rule, a file name with a newline/TAB, a dangling symlink outside fixtures/, an
#   empty ls-files (blind census) or a failed census needle => exit 3, nothing runs.
#   NOT covered: submodule contents.
# MEMBERSHIP  a member must be run by its covered_by entry according to a shell model
#   (lexer + parser + abstract interpreter over executable code; comments, heredoc bodies
#   and quoted text are not code). `reason: helper, sourced by <path>` is checked the
#   same way. Heavy names (mutation mutant mutate chaos stress perf meta_test smoke) are
#   tier heavy unless `override:`; members of heavy entries are heavy.
# RUN_ALL  runall-whole (run once) | runall-quick (default --quick, full without; members
#   that --quick drops are listed SKIPPED-heavy "dropped by --quick of X") | runall-members
#   (default: its default members run alone; full: the run_all once).
# VERDICTS  PASS | FAIL | SKIP(reason) | TIMEOUT | ERROR | SKIPPED-heavy | NOT-RUN.
#   TIMEOUT only from the runner's own timer; 124/137/signal deaths are ERROR. rc 77 is
#   SKIP. rc 0: a structural summary parser over the last 8 non-empty lines (word signals
#   RESULT|VERDICT|RUN_ALL|STATUS|SUMMARY|OVERALL : or =, count bindings key=N, key: N,
#   N word, word N, N of M); failed>0 / FAIL word / NOT ok => FAIL; conflict, zero tests,
#   inconsistent counts => ERROR; only skips => SKIP; no summary => PASS with
#   verdict_source=exit-code-only (counted and named). Output over --log-cap-mb
#   (default 64) => ERROR log_overflow; output is streamed, a 1 MiB tail kept.
# ISOLATION  `nice -n 15 ionice -c3`, own session, stdin /dev/null, clean environment
#   (PATH LANG LC_ALL LC_CTYPE TERM USER LOGNAME TZ + --env-extra NAMEs), fresh HOME /
#   TMPDIR / XDG_* per unit, per-unit token; leaked token-holding processes are killed and
#   counted; process-group signals assert pgid > 1 (section 11.4.263); per-unit dirs are
#   removed with safe_rm_rf (section 11.4.287).
# KNOWN  config/full_suite_known_failures.tsv: exact path + signature; recomputed at every
#   report from the current table and the log (sha256 checked).
# RESULTS + RESUME  <out>/results.jsonl (schema fsr/3, hash-chained, seq numbered; a break
#   is exit 2, a torn last line is dropped with a WARN), one log per record, an exclusive
#   lock on <out>/.lock. Reuse key: unit, HEAD sha, tree hash (status, diff, untracked,
#   submodule status+diff recursive, ignored files except __pycache__ *.pyc .pytest_cache
#   qa-results/), runner hash, context hash (manifest + known table bytes). Disagreeing
#   records of one key => NONDETERMINISTIC (worst verdict counts); a resume never upgrades.
# OUTPUT  default ${XDG_CACHE_HOME:-$HOME/.cache}/full_suite_runner/<repo>-<sha12>-<tree12>;
#   an --out inside the repository is refused.
# EXIT / RESULT line
#   0 PASS-FULL            every unit run, none skipped, nothing unexplained
#   1 FAIL                 unexplained FAIL/TIMEOUT/ERROR/NONDETERMINISTIC, or tree changed
#   2                      usage, configuration, results-integrity or lock error
#   3 MANIFEST-MISMATCH    census/manifest/rule problem, blind census, or needle failed
#   4 PARTIAL-NOT-RUN      some units not run (--only, interrupted)
#   5 PARTIAL-DEFAULT-SET  default set clean, heavy units NOT run
#   6 PARTIAL-SKIPS        nothing failed but >=1 unit SKIPPED (listed in summary.txt)
#   Exits 4-6 end with "-- not a section 11.4.40 full retest". Only exit 0 of a run with
#   --include-heavy is a section 11.4.40 retest.
# USAGE  run_full_suite.sh [--root DIR] [--out DIR] [--timeout SEC] [--include-heavy]
#          [--known FILE] [--manifest FILE] [--rerun-nonpass] [--only REGEX]
#          [--log-cap-mb N] [--env-extra NAME]... [--list] [--verify-manifest]
#          [--sync-guide] [--generate-manifest [--write]]
#   --timeout: positive integer seconds per unit (default 900; run_all and Go units 2x).
#   Scratch for per-unit homes: $FULL_SUITE_TMPDIR, else $TMPDIR, else /tmp.
# SELFTEST  bash tests/test_run_full_suite.sh ; paired mutations:
#   bash tests/test_run_full_suite_mutations.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
exec python3 -I -B "$HERE/full_suite/run_full_suite.py" "$@"
