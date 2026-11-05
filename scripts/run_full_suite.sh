#!/usr/bin/env bash
# scripts/run_full_suite.sh -- section 11.4.40 full-suite retest runner (wrapper; engine:
# scripts/full_suite/run_full_suite.py, one file, run with python3 -I).
# Full documentation: docs/guides/full_suite_runner_guide.md.
#
# WHAT IS COVERED  Every test entry point of this repository, outside submodule paths, that
#   the manifest config/full_suite_manifest.tsv declares. The CENSUS takes every tracked or
#   untracked-not-ignored file that is named test_*.sh, *_test.sh, *selftest*.sh,
#   run_all.sh, test_*.py, *_test.py, *_test.go, test_*.js, *.test.js, *_test.js, *.spec.js
#   (.mjs/.cjs too) or *.bats, or that is a script (.sh/.bash/.py in any letter case, or no
#   extension with a shell/python shebang, e.g. a smoke check) under a tests/ or test/
#   directory or whose name contains test|mutant|mutation|smoke|selftest (any case), or a
#   .js under a test directory with one of those words. A Go file counts toward its nearest
#   go.mod module (`go test -count=1 ./...`). Every census file needs exactly one manifest
#   row of class entry | member | fixture | excluded. A file without a row, a stale row, a
#   broken rule, a file name with a newline/TAB, not UTF-8 or starting with `#`, a dangling symlink outside fixtures/, an
#   empty ls-files (blind census) or a failed census needle => exit 3, nothing runs.
#   NOT covered: submodule contents.
# EXCLUDED  note `reason: <category>: <why>`, category in helper|library|oracle|fake|gate|
#   tool|data (`helper: sourced by <path>`, checked by the shell model); a test-named file
#   needs `override:`. The set is pinned by config/full_suite_excluded.lock; a change is
#   accepted with --verify-manifest --accept-excluded-change WHO (appended, never replaced, chained);
#   WHO must be an id of the committed config/full_suite_operators.roster, else refused (exit 3).
#   A set last accepted by an id not on that roster ends a run PARTIAL-EXCLUSIONS-UNACCEPTED.
#   Every run lists excluded rows in summary.txt and counts them in the RESULT line.
# MEMBERSHIP  a member must be run by its covered_by entry according to a shell model
#   (lexer + parser + abstract interpreter over executable code; comments, heredoc bodies
#   and quoted text are not code). The model also tracks whether each invocation's exit
#   status reaches a decision (script status, if/while, a reacting && / ||, $? / PIPESTATUS
#   that is used, set -e / pipefail); `! cmd`, an if with only true/:/echo/printf branches and a
#   status only printed or stored unused throw it away; such a member is also run ALONE.
#   Heavy names (mutation mutant mutate chaos stress perf meta_test smoke) are tier heavy
#   unless `override:`; members of heavy entries are heavy.
# RUN_ALL  runall-whole (run once) | runall-quick (default --quick, full without; members
#   that --quick drops are listed SKIPPED-heavy "dropped by --quick of X") | runall-members
#   (default: its default members run alone; full: the run_all once).
# TOPOLOGY  `git submodule status --recursive` is read first; an uninitialised, conflicted,
#   drifted (+) or missing-commit submodule, an unknown flag, an unparseable status line, or a failing status
#   command, is a gap: exit 9 REFUSED-TOPOLOGY, nothing runs, unless
#   --allow-topology-gaps (then PARTIAL-TOPOLOGY, exit 8). Paths are never cut out of the status
#   text (git prints them unquoted): they come from `git ls-files -s -z` (recursive, read as the bytes git
#   gave), and a status line that does not name exactly one of them is the gap "unparseable git submodule
#   status line"; a path containing a newline (git prints it across lines) and a path named by two status
#   lines are gaps of their own. See the guide for preparing a
#   checkout cheaply with `git clone --shared` and local submodule urls.
# IDENTITY  head=<sha12> subs=<hash> dirty=<clean|hash|unknown> is printed, stored in every
#   record and in every RESULT line; a non-empty git status (root or any submodule, untracked
#   included) ends the run PARTIAL-DIRTY-TREE (exit 10), never PASS-FULL.
#   The identity (HEAD of root and submodules, root status) is re-checked before every unit and
#   at the end; any change stops the run and ends FAIL (exit 1). Roster and lock: no symlinks.
# VERDICTS  PASS | FAIL | SKIP(reason) | TIMEOUT | ERROR | SKIPPED-heavy | NOT-RUN.
#   TIMEOUT only from the runner's own timer; 124/137/signal deaths are ERROR. rc 77 is
#   SKIP; a node/bats unit with no such runner installed is SKIP runner_not_installed.
#   rc 0: a structural parser over the last 12 non-empty DISPLAY lines (CR overwrites, ANSI
#   CSI/OSC and control bytes removed). Lines are classified by grammar: summary (whole line
#   covered by counter items, status words, filler, label, trailing comment), TAP `not ok`,
#   headed failure (RESULT|VERDICT|SUMMARY|STATUS|OVERALL|RUN_ALL|TOTAL with a fail word),
#   fail signal (any other fail word), description. TAP / headed failure => FAIL; the LAST
#   summary decides (failed>0, NOT ok N>0, FAIL word => FAIL); a disagreeing earlier summary
#   or a fail signal after it => ERROR; zero tests, inconsistent counts => ERROR; only skips
#   => SKIP; no summary + fail signal => ERROR unparsed_fail_signal; no summary, no signal
#   => PASS verdict_source=exit-code-only (counted and named). A fail word never yields PASS.
#   Crash text (AssertionError, Segmentation fault, command not found, core dumped, Permission
#   denied, Killed) is a fail signal; so is a fail word painted over by a CR progress update.
#   Output over --log-cap-mb (default 64) => ERROR log_overflow; streamed, 1 MiB tail kept.
# ISOLATION  `nice -n 15 ionice -c3`, own session, stdin /dev/null, clean environment
#   (PATH LANG LC_ALL LC_CTYPE TERM USER LOGNAME TZ + --env-extra NAMEs), fresh HOME /
#   TMPDIR / XDG_* per unit, per-unit token; leaked token-holding processes are killed and
#   counted; process-group signals assert pgid > 1 (section 11.4.263); per-unit dirs are
#   removed with safe_rm_rf (section 11.4.287).
# KNOWN  config/full_suite_known_failures.tsv: exact path + signature; recomputed at every
#   report from the current table and the log (sha256 checked).
# RESULTS + RESUME  <out>/results.jsonl (schema fsr/4, hash-chained, seq numbered; a break
#   is exit 2, a torn last line is dropped with a WARN), one log per record, an exclusive
#   lock on <out>/.lock. Reuse key: unit, HEAD sha, tree hash (status, diff, untracked,
#   submodule status+diff recursive, ignored files except __pycache__ *.pyc .pytest_cache
#   qa-results/), runner hash, context hash (manifest + known table + excluded lock bytes).
#   Disagreeing records of one key => NONDETERMINISTIC (worst verdict counts); a resume never
#   upgrades. The chain has no external anchor: a forged record with a recomputed chain is
#   not detected (section 11.4.268(C)).
# OUTPUT  default ${XDG_CACHE_HOME:-$HOME/.cache}/full_suite_runner/<repo>-<sha12>-<tree12>;
#   an --out inside the repository is refused.
# EXIT / RESULT line
#   0 PASS-FULL             every unit run, none skipped, nothing unexplained, no KNOWN
#   1 FAIL                  unexplained FAIL/TIMEOUT/ERROR/NONDETERMINISTIC, tree or identity changed
#   2                       usage, configuration, results-integrity or lock error
#   3 MANIFEST-MISMATCH     census/manifest/rule/excluded-lock problem, blind census, needle
#   4 PARTIAL-NOT-RUN       some units not run (--only, interrupted)
#   5 PARTIAL-DEFAULT-SET   default set clean, heavy units NOT run
#   6 PARTIAL-SKIPS         nothing failed but >=1 unit SKIPPED (listed in summary.txt)
#   7 PASS-FULL-WITH-KNOWN  every unit run, none skipped, every failure matched a KNOWN row
#   8 PARTIAL-TOPOLOGY      run with submodule gaps (--allow-topology-gaps)
#   9 REFUSED-TOPOLOGY      submodule gaps, no --allow-topology-gaps; nothing run
#  10 PARTIAL-DIRTY-TREE    the tree differs from HEAD / the recorded submodule commits
#  11 PARTIAL-EXCLUSIONS-UNACCEPTED  excluded set not accepted by a rostered operator
#   Exits 4-8, 10, 11 end with "-- not a section 11.4.40 full retest". Only exit 0 of a run with
#   --include-heavy is a section 11.4.40 retest.
# USAGE  run_full_suite.sh [--root DIR] [--out DIR] [--timeout SEC] [--include-heavy]
#          [--known FILE] [--manifest FILE] [--rerun-nonpass] [--only REGEX]
#          [--log-cap-mb N] [--env-extra NAME]... [--list] [--allow-topology-gaps]
#          [--verify-manifest [--accept-excluded-change WHO]] [--sync-guide]
#          [--generate-manifest [--write]]
#   --timeout: positive integer seconds per unit (default 900; run_all and Go units 2x).
#   Scratch for per-unit homes: $FULL_SUITE_TMPDIR, else $TMPDIR, else /tmp.
# SELFTEST  bash tests/test_run_full_suite.sh ; paired mutations:
#   bash tests/test_run_full_suite_mutations.sh [ID ...]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
exec python3 -I -B "$HERE/full_suite/run_full_suite.py" "$@"
