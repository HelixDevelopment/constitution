# Full-suite retest runner (§11.4.40)

| Field | Value |
|---|---|
| Revision | 13 |
| Created | 2026-11-03 |
| Last modified | 2026-11-11 (CON-030 round 7: the near-marker test is one class (white space, Cf, Zs, Default_Ignorable_Code_Point, U+FFFD) over the whole line, and the legal prose is listed; previously, CON-030 round 6: near-markers (trailing text, invisible leading characters) refused; every guide-marker variant pinned by an enumerated matrix; symlinked guide refused, file mode kept; merged with main 9cd7cacd, which brings its revision 8 (Go offline classification)) |
| Status | draft; CON-030 review round 5 (Opus) and round 6 returned NO-GO; this revision is CON-030 round 7, run past R_max by the standing operator decision of 2026-11-10 ("Keep running rounds until GO is reached!", section 11.4.276(E)(3)); independent review owed (section 11.4.142) |
| Script | `scripts/run_full_suite.sh` (engine `scripts/full_suite/run_full_suite.py`, one file, run with `python3 -I`) |
| Manifest | `config/full_suite_manifest.tsv` |
| Excluded lock | `config/full_suite_excluded.lock` |
| Operator roster | `config/full_suite_operators.roster` (one operator, by operator decision of 2026-11-04: the operator's git identity) |
| Known failures | `config/full_suite_known_failures.tsv` |
| Self-test | `bash tests/test_run_full_suite.sh`; paired mutations `bash tests/test_run_full_suite_mutations.sh` |

## What is covered, exactly

The runner covers the test entry points that a **census** finds and the **manifest** declares. Nothing else.

- Census: every tracked or untracked-not-ignored file outside submodule paths that is
  - named `test_*.sh`, `*_test.sh`, `*selftest*.sh`, `run_all.sh`, `test_*.py`, `*_test.py`, `*_test.go`, `test_*.js`, `*.test.js`, `*_test.js`, `*.spec.js` (also `.mjs` and `.cjs`) or `*.bats`, or
  - a script (`.sh`, `.bash` or `.py`, any letter case) that lives under a `tests/` or `test/` directory, or whose name contains `test`, `mutant`, `mutation`, `smoke` or `selftest` (any case), or
  - a `.js` file under a test directory whose name contains one of those words, or
  - a file with no extension and a shell or python shebang that lives under a test directory or whose name contains one of those words (for example `tools/smoke_check`).
  A Go test file counts toward its nearest `go.mod` module, which runs as `go test -count=1 ./...`.
- A file name with a TAB or with a character that ends, overwrites or splits a line in some reader (any C0 control but TAB, so LF and CR too; DEL; any C1 control, NEL included; U+2028 and U+2029), a file name that is not UTF-8 (the manifest is UTF-8 text), a file name that starts with `#` (a manifest line that starts with `#` is a comment), and a dangling symlink outside a `fixtures/` directory, are census problems (exit 3), each named as such (the character by its code point, for example `U+000D (CR)`). A dangling symlink inside `fixtures/` is listed and needs a fixture row.
- One reader reads every governance file: the manifest, the known-failures table, the excluded lock, the operator roster and this guide's census block. It splits on `\n` only, drops the CR of a CRLF line end (a CRLF file is still read), and refuses any other of the characters above inside a line, naming the file, the line and the character: the manifest and the lock exit 3, the known-failures table exits 2, a roster with such a line names nobody (every acceptance is refused, exit 3; a run ends exit 11). A NEL, a line separator or a bare CR inside a committed `#` comment line can therefore never make an operator id that `git show` displays as part of the comment count (CON-030 round 4, review r3 H2).
- Every message on stdout and stderr and every line of `summary.txt` goes through one escaping function: those characters are written as `\r`, `\n`, `\xNN` or `\uNNNN`, a byte that is not UTF-8 as `\xNN`, and a TAB is kept. The non-UTF-8 bytes are decoded first and the characters escaped after that, so surrogates that together hold the bytes of a NEL or a line separator are escaped too (review r4 K3). A path git gives (a submodule path in a `TOPOLOGY GAP` line), the root path or any other text can therefore never start, overwrite or forge a line such as `RESULT:` (review r3 H3). A literal backslash is not escaped, so `\r` in a message can also be a path that holds a backslash and an `r`.
- Positive control: if `git ls-files` lists nothing, the census is blind and the runner stops (exit 3).
- Before anything else the census function runs on a built-in fixture (the needle) with one known file per rule (shell, python, Go, JavaScript, bats, extension-less smoke), decoys and a submodule path. If it does not return exactly the expected set, the runner stops with exit 3.
- Every census file needs exactly one manifest row. A file without a row, a row without a file, or a row that breaks a rule stops the runner with exit 3 and `RESULT: MANIFEST-MISMATCH`; nothing runs.
- Not covered: the contents of submodules (each owns its suites).

`bash scripts/run_full_suite.sh --verify-manifest` prints the census by kind and class. The line below is generated; `--verify-manifest` refuses when it is stale. The block is found by its marker LINES: a line that is exactly `<!-- census:begin -->` and, after it, a line that is exactly `<!-- census:end -->`; a marker quoted inside other text is text. Two begin or end lines, an end line before the begin line, a begin line or an end line alone, or a NEAR-MARKER stop `--verify-manifest` and `--sync-guide` with exit 3 and nothing is written (review r4 K1, review r5 F1). A near-marker is a line that is not exactly a marker but starts with one once every IGNORABLE character is removed from the whole line and the markers are compared the same way (review r5 F3; one class since review r6 G3). The ignorable characters are: white space (Python `str.isspace`, which includes every space separator, category Zs), every format character (category Cf, for example U+200B, U+FEFF, U+2060, U+00AD, U+0600, U+FFF9), every Default_Ignorable_Code_Point (the table in the engine, the same as Perl's Unicode 15.0.0 data; it adds characters that are not Cf, for example U+034F, U+FE0F, U+180B, U+3164, U+115F, U+FFA0, U+FFF0), and U+FFFD, which is how a byte that is not UTF-8 is read. So white space around a marker, a trailing ` (generated)`, and an invisible or ignorable character before, inside or after a marker all make a near-marker. These stay legal prose and are text, not markers: a marker inside other visible text (backticks as in this paragraph, a sentence before it such as `see <!-- census:begin -->`), a line whose first visible character is anything else (`x<!-- census:begin -->`), a marker in upper case, a marker written with full-width brackets (U+FF1C, U+FF1E), and any visible character in the marker's place. The self-test generates the cells from these classes (representative code points of each class, before, inside and after each marker, on the begin line, the end line and both) and compares the table with Perl's when Perl is installed. To quote a marker in prose, put it inside other text, for example in backticks as in this paragraph; such a line is text. A block whose lines differ in any way from the one generated census line (a stale line, an extra line, an empty block) is stale. A guide with no marker line at all has no block, and the check passes. `--sync-guide` keeps the guide's file mode, and refuses (exit 3, nothing written) when the guide is a symbolic link, because the rewrite would replace the link with a regular file (review r5 F9). `--sync-guide` rewrites only the lines between the markers and copies every other byte unchanged (a CRLF line end, a byte that is not UTF-8); when it cannot read the guide (a refused character) it says which and exits 3 with `RESULT: GUIDE-NOT-SYNCED` (review r4 K2). `--verify-manifest` also runs the plan check of both modes, so a manifest that a run would refuse (two units shown with the same text) is not reported `MANIFEST-OK` (review r4 K9).

<!-- census:begin -->
census (generated by `bash scripts/run_full_suite.sh --sync-guide`; do not edit by hand): go/entry=5 js/excluded=5 py/entry=10 py/excluded=25 py/fixture=14 py/member=24 runall/entry=9 sh/entry=349 sh/excluded=25 sh/fixture=111 sh/member=301 total=878
<!-- census:end -->

## Manifest classes

| Class | Meaning |
|---|---|
| `entry` | run as a unit (runner `bash`, `sh`, `python3`, `node`, `bats`, `go-test`, or one of the three run_all runners) |
| `member` | run through its `covered_by` entry; also run alone when that entry throws its exit status away (below) |
| `fixture` | a file under `fixtures/` that matches a rule but is not a test; never run |
| `excluded` | a census file that is not a test; never run; see the next section |

Rules the runner checks:

- A `member` must really be run by its `covered_by` entry. This is decided by a shell model of the entry: a lexer, a parser and an abstract interpreter that follow literal values, variables, arrays, `for` lists, functions, `$(...)`, `source`, and the `bash` / `sh` / `python3` invocations in executable code. Comments, heredoc bodies and quoted text are not code. Names are never matched against the text of the file.
- The same model records whether each invocation's exit status reaches a decision: the script's own exit status, an `if` or `while` condition, a `&&` / `||` that reacts to it, `$?` or `PIPESTATUS` read by the next command, a bare `exit` / `return` next, or `set -e` (`set -o pipefail` for the left side of a pipe). It is thrown away by `|| true`, `|| :`, `|| echo ...`, a following unrelated command, a loop body, a background `&`, a non-assignment `$(...)`, the left side of a pipe without pipefail, a `! cmd` outside an `if` / `while` condition, an `if` whose every branch is only `true` / `:` / `echo` / `printf` (for example `if bash t; then :; fi`), and a `$?` / `PIPESTATUS` that is only printed or only stored in variables that no later command of the same list uses outside `echo` / `printf` (for example `bash t; rc=$?; exit 0`). A member whose status is thrown away at least once is planned as an extra unit and runs alone, so its own verdict counts; the summary counts these units.
- A heavy-looking name (`mutation`, `mutant`, `mutate`, `chaos`, `stress`, `perf`, `meta_test`, `smoke`) has tier `heavy` unless the row carries an `override:` note. A member of a heavy entry is heavy.

`run_all.sh` runners:

| Runner | Default mode | Full mode |
|---|---|---|
| `runall-whole` | run once | run once |
| `runall-quick` | `run_all.sh --quick` | `run_all.sh` |
| `runall-members` | run_all not run; its default members run alone | run_all once |

`runall-quick` is accepted only when the model, run with `--quick`, shows that every heavy member is dropped. In default mode each dropped member is listed as `SKIPPED-heavy` with the reason `heavy_excluded (dropped by --quick of <run_all>)`, and `--list` prints it.

Regenerate after adding or removing tests: `bash scripts/run_full_suite.sh --generate-manifest --write` (existing rows are kept; new helper-like files get an `UNREVIEWED` excluded row that must be given a reason by hand), then `--sync-guide`, then review the diff. When the census has a problem (for example a file name with a NEL), `--generate-manifest` names it, prints `RESULT: MANIFEST-NOT-GENERATED` and exits 3 without writing or printing a manifest, so a manifest never leaves a census file out silently (review r4 K12).

## Excluded rows

An excluded row's note is `reason: <category>: <why>`. The category is one of a closed list:

| Category | Meaning |
|---|---|
| `helper` | sourced by a test; the text must be `sourced by <path>` and the shell model of `<path>` must source the file |
| `library` | shared code imported by tests, never run on its own |
| `oracle` | a reference implementation or analyzer the tests call |
| `fake` | a stand-in program the tests launch (a fake server, a recording stub) |
| `gate` | a gate or check run by the pre-build sweep, not by this runner |
| `tool` | an operator tool or probe that is not a test |
| `data` | input data with a script extension |

A file whose name matches a test pattern can be excluded only with `override: reason: <category>: <why>`.

The reviewed set is pinned by `config/full_suite_excluded.lock`: one line per excluded path with the sha256 (16 hex) of its note, under `# accepted <time> accepted_by=<operator> set=<hash> rows=<n> chain=<hash>` lines. `chain` is the sha256 (16 hex) of the previous line's chain (zeros for the first chained line), the time, the operator, the set hash and the row count; a rewritten, reordered or deleted acceptance line breaks it (exit 3), and once a chained line exists every later line must be chained. Older lines without `chain=` are read as unchained history. `--verify-manifest` (and every run) refuses with exit 3 when the lock is absent while rows are excluded, when a row is added, removed or has a changed note, or when the lock body does not match its last `accepted` line. An operator accepts a reviewed change with `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change "<operator-id>"`; this appends an `accepted` line, it never replaces the earlier ones, and it is refused while any other manifest problem exists. The id must be listed in `config/full_suite_operators.roster` (one `id<TAB>who` line per operator), and the roster must be tracked and equal to HEAD; otherwise the acceptance is refused (exit 3) and nothing is appended. A run whose excluded set was last accepted by an id that is not on the committed roster ends `PARTIAL-EXCLUSIONS-UNACCEPTED` (exit 11), never green; `--verify-manifest` still exits 0 when the structure is consistent and prints a `NOTE:` line naming the acceptor. `summary.txt` prints the last acceptor. The lock bytes are part of the resume key. Every run lists the excluded rows in `summary.txt` and names their count in the RESULT line.

At this revision the 44 excluded rows were recategorised by the author and accepted as `fsr-r4-author (pending independent review)`. That acceptance is the author's own. By operator decision (2026-11-04) the roster holds one operator, the operator's own git identity (`i@mvasic.ru`), committed on the operator's instruction. What the runner enforces is only that the id given to `--accept-excluded-change` is on the committed roster; it cannot tell who typed the command. The acceptances recorded so far (2739c26b, bdc3ac43, e6b16598) were run by the landing agent on an order relayed by the conductor, and each commit message says so (in e6b16598 the agent states it did not see the operator's own message); none was typed by the operator in person (review fixu M2). The achieved separation is therefore `instance`: a recorded order, an agent run, and a roster id. A run of this repository ends `PARTIAL-EXCLUSIONS-UNACCEPTED` (exit 11) until the last acceptor on the lock is a rostered id.

The roster and the lock must be regular committed files. A symlink is refused (`--accept-excluded-change` and `--verify-manifest` exit 3; a run with a symlinked roster ends exit 11): the target of a committed symlink can be edited outside the repository with no trace in git history (review r5 R5-2).

Honest limit (§11.4.240(F)): on a single-uid host the roster and the chain stop a careless or self-named acceptance and make every edit visible in git history; they do not prove that a human typed the command. Anyone who can run the command can type a rostered id, and anyone who can edit the lock can recompute the chain. The achieved separation is `instance`, not `capability`.

## Topology preflight

Before a run starts, `git submodule status --recursive` is read. An uninitialised submodule (`-`), a submodule with merge conflicts (`U`), a drifted submodule (`+`: checked out at another commit than the superproject records), a submodule whose recorded commit is not in its object store, an unknown status flag, an unparseable status line, and a failing `git submodule status` (fail closed) are gaps. The submodule paths are never cut out of the status text, which git prints unquoted (CON-030): they come from `git ls-files -s -z` (the gitlinks of the root and, recursively, of every checked-out submodule), and each status line must read as `<flag><sha> <one of those paths>`, optionally followed by ` (<describe>)` on a ` ` or `+` line. A path with a space, a TAB, a CR, a leading or trailing space, `(`, `)`, `?`, `=` or bytes that are not UTF-8 is read whole (as the bytes git gave), and so is a describe such as `heads/feat(x)` or `v1(beta)`. A status line that does not name exactly one known path is the gap `unparseable git submodule status line (...)`; a ` `/`+` line without a describe whose text is both a known path and a known path plus a describe (for example `x (y)` when both `x` and `x (y)` are submodules) ends this way. A known path that contains a newline (possible only with a hand-written `.gitmodules`; git prints it across lines) is always the gap `submodule path contains a newline ...`, whatever its fragments parse as, and a path named by more than one status line is the gap `submodule <path> is named by more than one status line` (a newline path whose fragments each equal a known path, measured in review round 2, ends with both). These cases fail closed: never a wrong PASS. With any gap the runner refuses (exit 9, `RESULT: REFUSED-TOPOLOGY`) and runs nothing, because suites that need submodule content would fail for the checkout, not for the code. `--allow-topology-gaps` runs anyway and labels the result `PARTIAL-TOPOLOGY` (exit 8). The summary line `topology: layout=... submodules=N gaps=K` reports whether the root is a standalone checkout or a submodule inside a consumer.

Preparing a full checkout cheaply, without copying object stores:

```
git clone --shared <existing-clone> <dir>          # objects shared with the existing clone
cd <dir>
git config submodule.<name>.url <existing-clone>/.git/modules/<name>   # per submodule, local source
git -c protocol.file.allow=always submodule update --init --recursive
```

## Dirty tree and identity

The runner records the identity of the code that ran: `head=<HEAD sha 12> subs=<hash of the commits the submodules are checked out at> dirty=<clean | hash | unknown>`. It is printed at the start, in `summary.txt`, in every result record (`ident`) and at the end of every RESULT line. The tree is dirty when `git status --porcelain --untracked-files=all --ignore-submodules=none` of the root, or of any submodule (recursive), is not empty: a modified or untracked file, or a modified or drifted submodule. A failing git status reads as `dirty=unknown`. A dirty run still runs (useful while developing) but ends `PARTIAL-DIRTY-TREE` (exit 10), never `PASS-FULL` or `PASS-FULL-WITH-KNOWN`, and `summary.txt` lists each difference. Ignored files are not counted as dirty; they are hashed into the tree hash (resume key) only, so a unit that reads an ignored file (a local cache, an `.env`) is not caught by this check.

The identity is verified during the run as well, not only at the start (review r5 R5-1). Before every unit that is run, and once more at the end, the runner reads HEAD of the root and of every initialised submodule the sha256 of the root `git status --porcelain -z` and a fingerprint of the generated command sets (`plugins/helix/commands`, `plugins/helix/README.md` and `actions/generated`, under the root and under `constitution/`: every entry's path, type, inode, mtime, size and content or link target), and at the end the full identity again; the identity is read again after every unit as well (WIT-C02, merged from main in CON-030 round 5). Any difference from the start (a concurrent pull or checkout in the same tree, a unit that checks out a branch or commits, a unit that leaves a file behind) stops the run before the next unit, lists `IDENTITY CHANGED before unit <id>` or `IDENTITY CHANGED at the end of the run` in `summary.txt`, and ends `RESULT: FAIL (identity changed during the run ...)`, exit 1. No unit after the change is run, so no record names the start HEAD for code that did not have it. A git failure in this check reads as a change (fail closed). The quick identity is a structure held in memory only (CON-030 round 3): one `(path, value)` pair per HEAD in a fixed order, the root under no path at all, and a separate root status field; an unknown value is not a string, so no submodule name (`status`, `.`, `?`, `k=v`, ...) can be read as a field or as unknown. `IDENTITY CHANGED` names a submodule as `submodule '<path>'` (the path in Python repr, so a CR or a non-UTF-8 byte is shown exactly) and the root fields as `root HEAD`, `root status` and `generated sets`. An entry of a generated set that cannot be read makes that field unknown, which stops the run like a change. Limit: a change that is made and reverted inside one unit is not seen; the check costs about 0.5 s per unit on this repository with 32 initialised submodules (measured 2026-11-04).

If a recorded submodule commit is missing from the local source (`fatal: ... not our ref` or `did not contain <sha>`), fetch it from the real upstream (`git -C <dir>/<path> fetch origin <sha>`) or report the gap; never point the submodule at another commit to make the preflight pass.

## Verdicts

`PASS`, `FAIL`, `SKIP(reason)`, `TIMEOUT`, `ERROR`, plus `SKIPPED-heavy` (heavy unit, not run in default mode) and `NOT-RUN` (filtered by `--only` or interrupted).

- `TIMEOUT` only when the runner's own timer fired. A suite's own exit 124 or 137, or a death by signal, is `ERROR` with the reason.
- `SKIP`: exit 77, a SKIP decision of the summary parser, or a `node` / `bats` unit whose runner is not installed (`SKIP runner_not_installed`), or a Go unit whose module dependency is not in the module cache (`SKIP network_unreachable_external`, see below). Never counted as PASS: a run with any SKIP ends `PARTIAL-SKIPS` (exit 6) or a worse result, never `PASS-FULL`.
- Exit 0 otherwise: the summary parser reads the last 12 non-empty display lines of the log.
  - Display lines first: CRLF is trimmed, a CR progress overwrite is reduced to what the terminal last shows, ANSI CSI / OSC / DCS escapes and other control bytes are removed.
  - Each line is classified by grammar, not by its first word. A **summary line** is one whose whole text is covered by counter items (`key=N`, `key: N`, `N word`, `word N`, `NOT ok N`, `N of T`, `out of T`, `1..N`), status words (`PASS`, `OK`, `FAIL`, `SKIP`, ...), filler words (`all`, `of`, `tests`, `summary`, ...), punctuation, an optional `name:` label, and an optional trailing comment (`(...)`, `[...]`, `; ...`, ` -- ...`) that may only add a skip or fail word. A TAP `not ok` line (not `# TODO` / `# SKIP`) is a **TAP failure**. A `RESULT:`, `VERDICT:`, `SUMMARY:`, `STATUS:`, `OVERALL:`, `RUN_ALL:` or `TOTAL:` line with a fail word is a **headed failure**. Any other line with a fail-class word (`fail*`, `error*`, `fatal`, `panic`, `traceback`, `not ok`, a cross mark) is a **fail signal**, unless it starts like a passing check (`PASS`, `ok`, `[PASS]`, a tick) and its fail words are only in parentheses or quotes or carry no number. Everything else is description and is never counted.
  - Decision: a TAP failure or a headed failure anywhere in the window is FAIL. Otherwise the LAST summary line decides: `failed>0`, `NOT ok N>0` or a fail status word is FAIL; an earlier summary that disagrees, a fail signal after the last summary, or a SKIP line after a PASS summary is `ERROR conflicting_summary` / `fail_signal_after_summary`; more passed+failed+skipped than the total is `ERROR inconsistent_counts`; zero tests is `ERROR zero_tests`; a summary with only skips, or a skip word and no passes, is SKIP (`suite_reported_skip`, `all_skipped`, or the `reason=` given). With no summary line, a fail signal is `ERROR unparsed_fail_signal`; a last line that starts with `SKIP` is SKIP.
  - Crash text is a fail signal too (decided conservatively, review r4 F5): `AssertionError`, `Segmentation fault`, `command not found`, `core dumped`, `Permission denied`, and bash's own `Killed` (case-sensitive, at line start or after a pid). With no summary such a unit is `ERROR unparsed_fail_signal`; after the last summary it is `ERROR fail_signal_after_summary`; before the last summary it is description, as every fail signal is. A word painted over by a CR progress update is still a fail signal (F4): any such line in the window makes a PASS summary `ERROR`. Measured on the author's round-4 run (316 logs, 176 PASS): re-judging every log with the round-5 parser changed 0 verdicts (control needle: a synthetic `passed=3 failed=0` + `Segmentation fault` log did change).
  - Go units read `ok` / `FAIL` lines; a module with no `ok` line is `ERROR zero_tests`.
- Exit 0 with no summary line and no fail signal is PASS with `verdict_source=exit-code-only`; these are counted and listed separately and named in the RESULT line.
- Output beyond `--log-cap-mb` (default 64 MiB) is `ERROR log_overflow`. Output is streamed to the log through a pipe; only the last 1 MiB is kept in memory for the parser.

## Preparing Go units (module cache)

Go units run with `GOPROXY=off`, `GOFLAGS=-mod=readonly` and the host `GOMODCACHE`, so a module that is not already in the cache cannot be fetched during the run. The runner does not predict this before the run: every Go unit RUNS, and only a unit that FAILED is examined, from its own `go test` output (Go is the oracle; there is no pre-run probe, no cache-path computation, and, with the default environment, nothing is written into the repository under test; see the `--env-extra` row below). The FAIL becomes `SKIP network_unreachable_external` (`verdict_source=go-test-output`) only when ALL of these hold:

- the unit exited 1, its output was not cut (the log is under the tail limit), and the unit's module has no `vendor/` directory at all (with or without `vendor/modules.txt`; decided fail-closed in review round 5, G4-1);
- the unit really ran with the runner's offline policy (`GOPROXY=off`, `GOFLAGS=-mod=readonly`, read from the environment the unit was started with, not from a constant);
- every non-empty output line belongs to a closed grammar: `go: downloading <mod> <ver>`, `[<file>:<l>:<c>: ][<mod>@<ver>: ]module lookup disabled by GOPROXY=off` (module mode and workspace mode), the graph-level abort `go: <mod>@<ver>: module lookup disabled by GOPROXY=off`, `FAIL<TAB><pkg> [setup failed]`, a `# <pkg>` header, passing `ok` lines, `[no test files]` lines, and a bare `FAIL`;
- at least one lookup-disabled line AND at least one failing package (`[setup failed]`) or graph-level abort.

Any other line (a real test failure, a compile error, `missing go.sum entry`, `go.mod requires go >= ...`, a GOPRIVATE network error) keeps the unit a FAIL. The progress line names the modules Go tried to fetch, as `go_test_needs_network: <mod>@<ver> ...`, and the prepare command.

Measured with Go 1.26.8 (tests/test_run_full_suite_go.sh, one fixture per axis; tests/test_run_full_suite_go_mutations.sh, one paired mutant per axis):

| Axis | Measured behaviour under the runner policy | Verdict |
|---|---|---|
| dependency not in the cache | `go: downloading` + lookup disabled | SKIP |
| go.sum gap (no go.sum, `/go.mod` line only), cached or not | `missing go.sum entry` (a repository defect: every clone fails) | FAIL |
| go.sum with the zip line only, cache empty | lookup disabled (the go.sum gap behind it is hidden; honest limit) | SKIP |
| `replace` to a cached version with a go.sum gap | `missing go.sum entry` | FAIL |
| `replace` to an uncached version, complete go.sum | lookup disabled, the replacement named | SKIP |
| build-tag-only imports (also host `GOFLAGS=-tags=...`, which the unit env replaces) | the unit's own result | PASS / FAIL as Go reports |
| mixed: one package needs the network, another fails a test or does not compile | the failing package's own lines | FAIL |
| workspace (`go.work`), module not cached or checksum not in go.work.sum | `<file>:l:c: mod@ver: module lookup disabled` | SKIP |
| `vendor/` present with `vendor/modules.txt` | ignored under `-mod=readonly`; the module is in the repository; not reclassified, the log says why | FAIL |
| `vendor/` present WITHOUT `vendor/modules.txt` | under `-mod=readonly` Go reaches the module lookup; plain `go test` (default mode) fails offline with `inconsistent vendoring` (measured, Go 1.26.8, review round 4 G4-1), a repository defect; not reclassified (fail-closed), the log says why | FAIL |
| `go 1.99` in go.mod | `go.mod requires go >= 1.99` | FAIL |
| a `toolchain` line alone, a retracted version | Go does not consult them here | PASS |
| a nested module (its own go.mod) | excluded from `./...` | not part of the unit |
| host `GOPROXY=file://...`, `GOSUMDB` / `GONOSUMDB` in the HOST environment | not passed to the unit; the unit env sets the policy variables | as above |
| `--env-extra GOSUMDB` / `GONOSUMDB` (named on purpose) | reaches the unit. Measured (review round 3, workspace without a checksum, cache full): the unit can PASS and Go writes `go.work.sum` into the repository under test, and the runner's identity guard then stops the run (`IDENTITY CHANGED`). Do not pass these for go-test units. The other privacy variables that `go help environment` / `go help private` document, `GOPRIVATE` (which also sets the `GONOPROXY` and `GONOSUMDB` defaults), `GONOPROXY` and `GOINSECURE`, reach the unit the same way when named; their effect on writes into the repository is UNCONFIRMED (not measured). `GONOSUMCHECK` is not a variable `go help environment` documents on Go 1.26.8 (checked in review round 5; control needle: `GONOSUMDB` and `GOINSECURE` are found in the same output). Whether the same unit passes with network for a private module is UNCONFIRMED (CON-173) | PASS, then the run stops |
| malformed go.mod | the parse error | FAIL |

`network_unreachable_external` is the closest code in the §11.4.69 closed reason set; there is no code for "dependency not in the offline cache". It is true here (the module must come from the network, which the runner makes unreachable on purpose), but it does not say "cache", so read the progress line for the module name.

Prepare the cache once per host, with network, before the run:

```
for m in $(awk -F'\t' '$5=="go-test"{print $1}' config/full_suite_manifest.tsv); do go -C "$m" mod download; done
```

This writes into the host `GOMODCACHE`, and also into the module directory when its `go.sum` is incomplete (`go mod download` then adds the missing lines to `<module>/go.sum`; check `git status` afterwards and commit or drop that change on purpose). Its effect is that later runs on this host find the modules; a host that skips this step gets honest SKIPs, never PASSes, for those units. A failed lookup leaves only lock files in the cache, so a SKIPped run does not half-fill it.

After preparing the cache, start a fresh run: use a new `--out` directory (or remove the default one). A resumed run keeps the recorded SKIP, and `--rerun-nonpass` reports the SKIP-then-PASS pair as `NONDETERMINISTIC`.

## Isolation

Each unit runs as `nice -n 15 ionice -c3 <runner> <path> [args]` in its own session, stdin `/dev/null`, with a clean environment: only `PATH LANG LC_ALL LC_CTYPE TERM USER LOGNAME TZ` come from the caller, plus any name given with `--env-extra NAME`. `HOME`, `TMPDIR` and the four `XDG_*` directories point into a fresh per-unit directory; `FULL_SUITE_UNIT_TOKEN` is a random per-unit token. Go units also get a fresh `GOCACHE`, the host `GOMODCACHE`, `GOFLAGS=-mod=readonly`, `GOPROXY=off`, `GOTOOLCHAIN=local`, `GOTELEMETRY=off`. Results record the variable names, never values.

After a unit ends (on timeout: SIGTERM to its process group, SIGKILL after 10 s; the group id is checked to be an integer greater than 1 and not the runner's own group, §11.4.263), every own-uid process whose environment still holds the token is killed and counted as leaked.

## Known failures

`config/full_suite_known_failures.tsv` lists OPEN failures only: path, signature (a literal substring of the unit log, or `reason:<code>`), tracked id, note. A failure is KNOWN only on an exact path match AND a matching signature. KNOWN is recomputed at every report from the CURRENT table and the unit log, and only when the log still has the sha256 recorded when it was written; an edited log is never matched. At this revision the table has two rows, `tests/gates/test_gate_env_census_jq_regions.sh` and `tests/gates/test_gate_env_census_closure.sh`, each with signature `reason:rc_3+tracked` and tracked as CON-047 (exit 3 means no FAIL and only the KNOWN-FAIL cases pinned to CON-047, and the unit log must name `[tracked CON-047]` and no other tracked id; exit 1 still fails the run). Every other failure fails the run. A run whose only failures are KNOWN ends `PASS-FULL-WITH-KNOWN` (exit 7), never `PASS-FULL`.

## Results file and resume

`<out>/results.jsonl`, schema `fsr/4` (adds `ident`). Each record carries a sequence number and the sha256 of the previous line (a hash chain from a zero genesis). A broken chain, a gap, a duplicate sequence number or an invalid record (a verdict outside the closed set included) stops the runner (exit 2, "results integrity"); a torn LAST line (no newline, from an interrupted write) is dropped with a WARN. Each record has its own log file `logs/NNNNNN.log`. An exclusive lock on `<out>/.lock` stops a second runner on the same output directory (exit 2).

A record is reused only when its key matches: the unit's key, which is the structure (path, arguments) and never a joined text (CON-030 round 4, review r3 H1: a Go module in a directory named `x/run_all.sh --quick` was resumed from the record of `x/run_all.sh` run with `--quick`), HEAD sha, working-tree hash, runner hash, and a context hash of the manifest bytes, the known-failures table bytes and the excluded-lock bytes. The working-tree hash covers git status, `git diff HEAD`, untracked file names and contents, the status and diff of every submodule (recursively), and the names and content hashes of the ignored files of the root (not of the ignored files inside a submodule, see Limits), except `__pycache__/`, `*.pyc`, `.pytest_cache/` and `qa-results/` (suites write evidence there). A resume never upgrades a verdict: when several records of one key disagree, the unit is `NONDETERMINISTIC` and the worst verdict counts. `--rerun-nonpass` re-runs recorded FAIL, TIMEOUT, ERROR and SKIP units. The context hash does not cover `--timeout`, the names and values of `--env-extra` variables, or the caller environment the runner passes on: a resume with a different value of such a variable reuses the record (review r4 K4, tracked as CON-194; first minted as CON-148, then CON-165 and CON-188, on this vehicle, re-minted per section 11.4.214). Use a new `--out` when you change them.

## Usage

```
bash scripts/run_full_suite.sh --verify-manifest    # census + manifest + excluded-lock check only
bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change "<reviewer>"
bash scripts/run_full_suite.sh --sync-guide         # rewrite the census line of this guide
bash scripts/run_full_suite.sh --list               # plan for the default mode, with the reason of every skip
bash scripts/run_full_suite.sh                      # default set (heavy units not run)
bash scripts/run_full_suite.sh --include-heavy      # full set: the §11.4.40 retest
bash scripts/run_full_suite.sh --allow-topology-gaps   # run on a checkout with submodule gaps (PARTIAL-TOPOLOGY)
bash scripts/run_full_suite.sh --only REGEX --timeout 300 --log-cap-mb 64
bash scripts/run_full_suite.sh --rerun-nonpass
```

Output goes to `${XDG_CACHE_HOME:-$HOME/.cache}/full_suite_runner/<repo>-<sha12>-<tree12>` unless `--out` is given; an `--out` inside the repository is refused. Progress: `wc -l <out>/results.jsonl` and the per-unit lines on stdout; final report in `<out>/summary.txt`.

Two units shown with the same text (for example that module next to `x/run_all.sh` run with `--quick`; the shown text is the path, then a space and the arguments) are refused before anything runs (exit 3, `plan: two different units are both shown as ...`), because every message, `--only` filter and summary line would name both. Rename one of the paths. Two units with one key are refused the same way.

## Exit status and RESULT line

| Exit | RESULT | Meaning |
|---|---|---|
| 0 | `PASS-FULL` | every unit ran, none skipped, nothing failed, no KNOWN failure |
| 1 | `FAIL` | an unexplained FAIL, TIMEOUT, ERROR or NONDETERMINISTIC unit, the repository tree changed during the run, or the identity changed during the run (HEAD of the root or of a submodule moved, or the root status changed) |
| 2 | | usage, configuration, results-integrity or lock error |
| 3 | `MANIFEST-MISMATCH` | census and manifest disagree, a rule is broken, the excluded set is not accepted, the census is blind, or the census needle failed |
| 4 | `PARTIAL-NOT-RUN` | some units did not run (`--only`, interrupted) |
| 5 | `PARTIAL-DEFAULT-SET` | the default set is clean but heavy units did not run |
| 6 | `PARTIAL-SKIPS` | every unit ran and none failed, but at least one SKIPPED; the SKIPs are listed in summary.txt |
| 7 | `PASS-FULL-WITH-KNOWN` | every unit ran, none skipped, every failure matched an open row of the known-failures table |
| 8 | `PARTIAL-TOPOLOGY` | the run had submodule gaps, allowed by `--allow-topology-gaps` |
| 9 | `REFUSED-TOPOLOGY` | submodule gaps and no `--allow-topology-gaps`; nothing was run |
| 10 | `PARTIAL-DIRTY-TREE` | the tree differs from HEAD or the recorded submodule commits; the code that ran is not the commit |
| 11 | `PARTIAL-EXCLUSIONS-UNACCEPTED` | the excluded set was last accepted by an id that is not on the committed operator roster |

Exits 4 to 8, 10 and 11 end with `-- not a section 11.4.40 full retest`. Precedence: identity changed, FAIL, tree changed, topology gaps, not run, default set, skips, dirty tree, unaccepted exclusions, KNOWN, PASS-FULL; every RESULT line carries the identity. Only exit 0 from a run with `--include-heavy` is a §11.4.40 full-suite retest.

## Limits

- The shell model is an approximation of bash. It does not follow `eval`, aliases, namerefs, indirect expansion, or command names computed at run time; such an entry needs its members declared as entries instead. A step budget stops a runaway loop with a parse error (exit 3). A `while read f; do bash "$f"; done` loop is modelled with an unknown `f`, and the model records the bogus path `.` for it; a member invoked only that way does not verify (fail closed).
- The status model is conservative in one direction only: when it cannot tell, it treats the status as thrown away and runs the member alone (an extra run, never a missed failure). It does not track `wait $!`. A status stored in a variable counts as decided when any later command of the same list uses the variable outside `echo` / `printf`; a use that decides nothing (`[ $rc -ne 0 ] && echo bad`), a use in another list (an outer scope, after a function return) and an assignment chain (`fail=$rc`, never used) are counted as decided, so these shapes can still hide a failure.
- `verdict_source=exit-code-only` PASS units still allow `PASS-FULL`; they are counted and named, not hidden.
- The parser reads the last 12 display lines; a summary printed earlier and followed by more than 11 lines of output is not seen, and such a unit is labelled `exit-code-only` (or `ERROR` if a fail word is in those lines).
- The hash chain detects an edited, deleted, reordered or hand-appended record. A forger who appends a record and recomputes the chain from it is not detected: the chain has no external anchor (§11.4.268(C)). Keep `--out` where only the runner writes.
- The checkout's preflight does not check for a local `main` branch; units that need one (tests/install) fail for the checkout (review r4 F10).
- `qa-results/` is not part of the tree hash, so a change there does not invalidate a resume record.
- Ignored files are listed and hashed in the root only. A suite that writes an ignored file inside a submodule during the run is not seen by the tree-changed check (it can end `PASS-FULL`), and a change of the ignored files inside a submodule does not change the resume key (review r3 H4; tracked as CON-192; first minted as CON-146, then CON-163 and CON-186, on this vehicle, re-minted per section 11.4.214).
- Every file read in the engine carries a class comment (`# io: gov`, `write` or `not-gov`); a self-test lint fails when a read has none, or when a governance reader reads its file itself instead of through the one reader. The lint follows a bare `open(...)` and method calls named `splitlines`, `readlines`, `readline`, `read_text` and `read_bytes`, and requires the five governance readers (`read_manifest`, `load_known`, `read_excl_lock`, `read_roster`, `guide_parse`) to read through the one reader; a governance file read elsewhere under a `not-gov` class, or through `os.open`, `io.open` or `codecs.open`, is not seen by it (review r4 K10).
- Leak detection depends on the token staying in the environment; a process that cleared its environment and left the group is not found.
- A test can still pass while testing nothing; the runner checks what ran and what it reported, not the strength of each test.
