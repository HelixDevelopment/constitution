# Installer SIGPIPE, review round 2 (CON-PENDING-INSTALLER-SIGPIPE)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14 |
| Status | fix on `vehicle/installer-sigpipe-r2`, PROVISIONAL (independent review owed) |
| Evidence class | gate-logic / unit only (§11.4.289): constructed marks and fixtures fed to the real functions, no remote, no agent, no network |
| Base | `main` bd0036bd (standalone vehicle, F7) |
| Commits | 6f28765c (round 1, re-based on `main`), 58815d75 (round-2 fix), 1914a91b (repair of the no-push gate, section 9), a5ee2ab4 (the `test_round8` chaos-loop hardening, a separate commit, section 13), the commit that adds this directory |
| Supersedes | `../README.md` for every claim that differs; the round-1 document is kept unchanged as the record |

## Contents

- [1. What this round does](#1-what-this-round-does)
- [2. The round-1 findings and where each is closed](#2-the-round-1-findings-and-where-each-is-closed)
- [3. Scope](#3-scope)
- [4. Measured facts the rules rest on](#4-measured-facts-the-rules-rest-on)
- [5. Class inventory](#5-class-inventory)
- [6. One rule per class](#6-one-rule-per-class)
- [7. Same output before and after](#7-same-output-before-and-after)
- [8. Mutants](#8-mutants)
- [9. The no-push gate after round 2](#9-the-no-push-gate-after-round-2)
- [10. Suite runs](#10-suite-runs)
- [11. Performance of hi_push_changed](#11-performance-of-hi_push_changed)
- [12. Landing order](#12-landing-order)
- [13. F9: the test_round8 chaos loop](#13-f9-the-test_round8-chaos-loop)
- [14. Cross-check against the review's alternative patch](#14-cross-check-against-the-reviews-alternative-patch)
- [15. Honest limits](#15-honest-limits)
- [16. Files in this directory](#16-files-in-this-directory)

## 1. What this round does

The round-1 review returned NO-GO. Its deciding finding (F1, critical) was that the Z fail-closed check, which
round 1 had changed from a pipe to a here-string, fails OPEN when bash cannot write the temporary file it keeps a
here-string in. This is the structural round of §11.4.276(E): first a class inventory of every bash feature in the
six install files that can silently change what a check decides, then one rule per class (not one fix per site),
then a deny-by-default scanner and behavioural tests under the conditions that trigger each class.

The round-2 fix commit (58815d75) was not run through the repository's own no-push gate
(`CM-INSTALLER-NO-PUSH-NO-FORCE`), and that gate fails on it with 18 findings. A third commit (1914a91b) repairs
the installer, the updater and the gate; section 9 records the findings, the cause of each and the repair. Every
measurement in sections 5, 7, 8 and 10 was taken again on 1914a91b.

The five classes:

| Class | What can silently change a decision |
|---|---|
| (a) | no writable temporary file: here-strings and here-documents are skipped, status 1 |
| (b) | the caller's shell state: `BASH_COMPAT`, `POSIXLY_CORRECT`, `SHELLOPTS`, `BASHOPTS`, `CDPATH`, `GLOBIGNORE`, `TMOUT`, old bash versions |
| (c) | `pipefail` with a reader that exits before its input ends: the writer dies of SIGPIPE (141) and a match reads as no match |
| (d) | `set -e` switched off inside a function that is called as a condition (`f || x`, `if f`) |
| (e) | large input: anything that changes behaviour above a size (here-string storage, pipe buffers, argument limits) |

## 2. The round-1 findings and where each is closed

| ID | Severity, layer | Finding | Closure in round 2 | Evidence |
|---|---|---|---|---|
| F1 | critical, source-defect, introduced | Z check `grep -q '^Z ' <<<"$b"$'\n'"$a"` fails open when the here-string cannot be stored | Rule (a): no here-string anywhere. The Z check is `hi_has_line_prefix "$b$nl$a" 'Z '`, a test inside the shell over both marks. | `test_sigpipe.sh` section 3: Z in the before-marks only, the after-marks only and both, in three temporary-file conditions and three sizes; mutants N01, RM08, RM16 and the in-test mutants Z-here-string, Z-reads-before-only |
| F2 | critical by the caller's rule, source-defect, pre-existing | the R/L/N/V loops of `hi_push_changed` end in `done <<<"$x"` and skip their body when the here-string cannot be stored: a push reads as no push | Rule (a). The marks are split once with `hi_split_lines` (no temporary file) and every loop runs over the array. | section 3 (moved ref, changed L line, removed remote, re-pointed url, in every condition); mutants N02, N14, N15 and the in-test mutant loop-here-string |
| F3 | important, source-defect, introduced | the other new here-string sites, `hi_verify` failing open | Rule (a) at every site, including sites the review did not list (section 5: 12 here-strings and 4 here-documents in the base installer, 2 here-strings in the base updater, 1 here-document in the action-prefix installer, all removed) | `inventory/sigscan_new.txt` (0 findings). Section 4 of `test_sigpipe.sh` runs the replacements at the `hi_verify`, `hi_layout`, `hi_upstream_ok` and `hi_resolve_ref_in` sites (`hi_legacy_path_in`, `hi_has_line_prefix`, `hi_line_in`, `hi_upstream_ok`, `hi_resolve_ref_in`, `hi_on_remote`) and the updater's hook probe (`up_hook_declares_project_root`) under the three conditions; the other rewritten sites are covered by the scan and the existing suites only (section 15) |
| F4 | minor, test-instrumentation | the behavioural cases used only `b == a`; RM08 died only on an exact-string anchor; no test of the no-temporary-file condition | 15 cases from both sides (Z before only, after only, both; M lines that differ) at 0 and 200 tail lines under `normal`, `notemp50` and `notemp44`, and 4 of them at 2000 tail lines (about 136 KB per mark) under `normal` and `notemp50` | RM08 and RM16 now die in section 3 (behaviour), see section 8 |
| F5 | minor, test-instrumentation | the static scanner saw two spellings (`| grep -q`, `| grep --quiet`) | a token-level, deny-by-default scanner: a pipe into anything that is not a known whole-input reader is a finding; 42 control needles (every reviewer spelling, here-strings, here-documents, unknown readers, and the safe forms that must not be flagged) | section 1 of `test_sigpipe.sh`; the mutants RM09, RM10, RM11 and RM17 (which survived round 1), RM12 to RM15 (which round 1 caught only by behaviour) and N07 to N11 die in section 1 |
| F6 | minor, process-doc | the two libraries the CLI installer sources were not in the inventory; the temporary-file boundary was not stated | both libraries are in the inventory and in the scan list (section 5); the boundary is measured per bash version (section 4) | `inventory/inventory_counts.md`, `compare/herestring_storage.txt` |
| F7 | minor, process-doc | the head was based on the unlanded sync vehicle | re-based on `main` bd0036bd: commit 6f28765c is the round-1 fix applied to `main` (with its manifest row and the regenerated guide census line); landing order in section 12 | `landing/trial_merge.txt` |
| F8 | nit | `hi_upstream_ok "$v" ||{`; the scanner printed the line with quotes stripped | `hi_upstream_ok "$v" || {`; the scanner prints the original line | section 1 check "printed with the original line" |
| F9 | minor, test-instrumentation, pre-existing | the `test_round8` re-run race | hardened in a separate commit (a5ee2ab4, on the conductor's instruction): after each signalled run the chaos loop drains the installer's whole session, treats a git `index.lock` that no live process holds as a refused re-run, and signals only the installer's own group. The test-level race itself is UNREPRODUCED. No tracked item found (section 13) | `tr8/`, `f9/f9_search.txt` |

The review's two separately measured facts are kept: the `test_lock` stale-poll fix of round 1 stays (it is in
6f28765c, `tests/install/test_lock.sh`), and the `test_agent` check "timeout honoured (<20 s)" is a wall-clock
check that is sensitive to host load and fails on the base and the head alike; it is not touched (section 10 records
whether it failed in these runs).

## 3. Scope

The six files whose behaviour this item governs:

| File | Why it is in scope |
|---|---|
| `scripts/install_constitution.sh` | the installer (sources no other file) |
| `scripts/update_constitution.sh` | the updater (shares the `hi_shell_state` block with the installer) |
| `scripts/install_cli_agent_plugins.sh` | the CLI plugin installer, runs under `set -euo pipefail` |
| `scripts/install_action_prefix.sh` | the action-prefix installer, runs under `set -euo pipefail` |
| `scripts/portable_symlink_lib.sh` | sourced by the CLI installer (F6) |
| `scripts/lib/constitution_layout.sh` | sourced by the CLI installer when present (F6) |

## 4. Measured facts the rules rest on

Here-string storage, bash 3.2.57 excluded (it cannot run the installer, item 5 below). Size is the length of the
word in bytes; bash adds one newline, so the stored document is one byte longer. `pipe` means bash kept the
here-string in a pipe, `file` means it needed a temporary file (`compare/herestring_storage.txt`, produced by
`tools/bash_facts.sh`):

| bash | 4095 | 4096 | 8190 | 8191 | 8192 | 16384 | 65536 | 131072 | BASH_COMPAT=50, 100 | BASH_COMPAT=50, 102400 |
|---|---|---|---|---|---|---|---|---|---|---|
| 5.0.17 | file | file | file | file | file | file | file | file | file | file |
| 5.1.4 | pipe | pipe | pipe | pipe | file | file | file | file | pipe | file |
| 5.1.16 | pipe | pipe | pipe | pipe | file | file | file | file | pipe | file |
| 5.2.15 | pipe | pipe | pipe | pipe | file | file | file | file | file | file |
| 5.2.26 | pipe | pipe | pipe | pipe | file | file | file | file | file | file |
| 5.2.37 | pipe | pipe | pipe | pipe | file | file | file | file | file | file |
| 5.3.9 (host) | pipe | pipe | pipe | pipe | file | file | file | file | file | file |

Other facts, each measured in this round:

1. With `BASH_COMPAT=50` (or lower), bash 5.2 and later use a temporary file at every size. bash 5.1.4 and 5.1.16
   still keep a SMALL here-string in a pipe with `BASH_COMPAT=50`, which bash's own `COMPAT` text does not say;
   the tests therefore use a 100 KB here-string as the control needle for "no temporary file" (it needs a file on
   every version), and print the small-needle result as information only.
2. "No temporary file" is produced with `(trap '' XFSZ; ulimit -f 0; BASH_COMPAT=50 ...)`: bash then prints
   `cannot create temp file for here-document: File too large`, does not run the command, and returns 1, on every
   version measured (`compare/notemp_emulation.txt`). Under that condition the base `--help` and `--print-snippets`
   printed only that message (no help text, no snippets) and exited 0; the head printed the full text
   (`compare/base_notemp_help.txt`).
3. `shopt -u compat44` (any `compatNN`) sets `BASH_COMPAT` on bash 5.0 and later, so the reset unsets
   `BASH_COMPAT` again at its end (mutants N21, N21t).
4. bash 5.0 and older in posix mode reject `<(...)` while PARSING. Under `POSIXLY_CORRECT=1` the base installer
   failed on bash 3.2.57 and 5.0.17 with `syntax error near unexpected token '<'`, and on the host with
   `incomplete script (truncated download?)` (exit 2). Round 2 resets the shell state before the first function
   that contains `<(` is parsed (`compare/old_bash_version_gate.txt`, `compare/caller_shell_compare_host.txt`).
5. On bash 3.2.57 the new installer prints its own version message (`bash 4.4 or newer is required`, exit 3)
   with and without `POSIXLY_CORRECT=1`; the base printed a syntax error under `POSIXLY_CORRECT=1`.
6. Process substitution uses `/dev/fd`; where `/dev/fd` is missing, bash makes a FIFO in `TMPDIR`, which can fail
   for the same reason a here-string file can. `hi_plumbing_ok` reads one line through `<(...)` before anything
   is changed and refuses with exit 3 when that fails (mutant N06).
7. `[[ -v assoc[$k] ]]` expands the subscript twice on bash 5.0 and 5.1 and on any bash with a compatibility
   level of 51 or lower, so a key that contains `$(...)` is run as a command. The code uses `${rb[$k]+x}` (one
   expansion). Mutant N23 shows the difference: killed on bash 5.0.17 in the normal condition and on the host
   under `notemp50` (section 8).
8. awk compares two values that both look like numbers as numbers: the base `awk -v n="$ref" '$1 == n'` picks
   tag `1.0` for the ref `1.00` with gawk, mawk and busybox awk (`compare/awk_strnum.txt`). Round 2 compares the
   strings in the shell; this is an incidental fix, its reachability is low (it needs numeric tag names).
9. `shopt -u a unknown b` (and `shopt -s`) with one name the running bash does not know: the known names still
   change, the unknown name is skipped, the status is 1. Measured on 3.2.57, 5.0.17, 5.1.4, 5.1.16, 5.2.15,
   5.2.26, 5.2.37 and the host 5.3.9, with a control call of known names only (status 0)
   (`compare/reset_facts.txt`, `tools/reset_facts.sh`). So `hi_reset_shell_state` can change every option in one
   `shopt -u` call and one `shopt -s` call on every version, which the no-push gate can read (section 9).
10. `unset POSIXLY_CORRECT` turns posix mode off on every version above, whether posix mode came from
    `set -o posix`, from `POSIXLY_CORRECT=1` in the environment or from `SHELLOPTS=posix`; without the `unset`
    (control) posix mode stays on. This is why mutant N22t is equivalent (section 8).

## 5. Class inventory

Two independent instruments over the six files, base bd0036bd and head 1914a91b:

- `shenum` (Go, `mvdan.cc/sh/v3` v3.13.1, a real bash parser): one row per pipeline, here-string, here-document,
  process substitution, `set`/`shopt` call, version-dependent construct, pattern match, function called as a
  condition, and declaration that masks a substitution's status. It rebuilds offline to the same binary
  (`tools/shenum_main.go.txt`, sha256 in `SHA256SUMS`).
- `sigscan` (Python, a bash tokenizer, the same rules as the scanner in `test_sigpipe.sh`).

For every file the multiset of pipe readers found by `shenum` equals the one found by `sigscan`
(`inventory/xcheck_base.txt`, `inventory/xcheck_new.txt`, both `XCHECK PASS`). Every file also has a control
needle: `test_sigpipe.sh` appends one known early-exit line to a copy of each file and requires exactly one finding
at that line.

Counts, base → head (`inventory/inventory_counts.md`; one value means unchanged):

| file | HERESTR | HEREDOC | PIPE | EARLY | READER | PROCSUB | SETOPT | VERS | PATMATCH | FUNCCOND | DECLSUB | PARSEERR |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `scripts/install_constitution.sh` | 12 -> 0 | 4 -> 0 | 75 -> 56 | 20 -> 0 | 15 | 14 -> 15 | 2 -> 10 | 3 -> 4 | 122 -> 137 | 229 -> 238 | 0 | 0 |
| `scripts/update_constitution.sh` | 2 -> 0 | 0 | 17 -> 12 | 8 -> 0 | 3 | 2 -> 3 | 1 -> 9 | 3 | 41 -> 46 | 49 -> 52 | 0 | 0 |
| `scripts/install_cli_agent_plugins.sh` | 0 | 0 | 6 -> 4 | 2 -> 0 | 0 | 0 | 1 -> 5 | 0 | 6 -> 8 | 13 | 0 | 0 |
| `scripts/install_action_prefix.sh` | 0 | 1 -> 0 | 2 | 0 | 0 | 0 | 1 -> 5 | 1 | 4 | 2 | 0 | 0 |
| `scripts/portable_symlink_lib.sh` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `scripts/lib/constitution_layout.sh` | 0 | 0 | 2 | 0 | 0 | 0 | 6 | 0 | 10 | 14 | 0 | 0 |

Columns: HERESTR and HEREDOC (class a and e), PIPE (pipelines with two or more stages), EARLY (a pipe reader that
can exit before its input ends, class c), READER (a pipe reader the tool cannot classify, read by hand), PROCSUB,
SETOPT and PATMATCH (class b), VERS (constructs that differ between bash versions), FUNCCOND and DECLSUB (class d),
PARSEERR (the parser was blind on the file: 0 everywhere).

Hand triage of what is left:

- EARLY is 0 in every file. The 18 READER rows of the head are all calls of four functions that read their whole
  input: `hi_text_filter` (python `sys.stdin.buffer.read()`, or `tr`), `hi_scrub` (`sed` without `q`),
  `hi_mark_hash` (`sort | sha256sum`, or `cat >/dev/null` when no tool exists) and `hi_newest_tag`
  (`awk | grep -E | sort | tail`). These four are the scanner's allow list.
- FUNCCOND (class d) matters only in the two files that use `set -e`: `install_cli_agent_plugins.sh` and
  `install_action_prefix.sh`; the installer runs `set -u -o pipefail` and the updater `set -uo pipefail`, so
  errexit is never on in them. In the CLI installer, `regen_commands`, `link_skills`, `link_agent_commands` and
  `wire_prompt_hook` are called as `f || rc=1`; each now checks every step that matters (round 2 added the count
  of skill and command links that could not be created, mutants N12 and N13). The one unchecked step is the
  removal of a dangling link (`rm -f "$stale"`), a clean-up whose failure leaves a dangling link and changes no
  decision. In the action-prefix installer, `merge_with_jq` and `merge_with_python` are called as `f || exit 1`;
  every step in them is joined with `&&` or ends in `|| return 1`, and the last command's status is the result.
- DECLSUB is 0: no `local x="$(...)"` hides a status in any of the six files.

## 6. One rule per class

| Class | Rule | Where it is enforced |
|---|---|---|
| (a) | No here-string and no here-document in the six files. Membership, prefix and field tests run inside the shell (`hi_split_lines`, `hi_read_fields`, `hi_has_line_prefix`, `hi_line_in`, `hi_strip_lead`); fixed text (help, upstream table, agent table) is a single-quoted literal; the installer's stream parser is the inline literal `python3 -I -c '...'` (the no-push gate accepts only a literal program, section 9) and the action-prefix merge program runs as `python3 -c "$prog"`; both have stdin closed. | scanner, section 1 of `test_sigpipe.sh` |
| (b) | `hi_reset_shell_state`, one text in all four scripts, runs when the script is RUN (a sourced copy keeps the caller's shell) and before the first function with `<(...)` is parsed; it returns every option a caller can hand down to bash's defaults (one deliberate exception, `patsub_replacement`, section 15). `hi_plumbing_ok` refuses (exit 3) where process substitution cannot work. | section 2 (block identical in four files, reset position, nine hostile settings give the clean output) |
| (c) | No pipe into a reader that can exit before its input ends: command output is captured, then tested in the shell. The scanner is deny-by-default: an unknown reader is a finding. | section 1 |
| (d) | In the two `set -e` scripts, a function called as a condition checks each step that matters and counts failures; it does not rely on errexit. | section 7 (read-only `.claude/skills`: exit 1, every failure counted) |
| (e) | Every split and compare is in the shell and has no size limit; `hi_push_changed` first skips, with a pattern, the lines whose kind cannot be the one a loop reads, so its cost is about one field split per line. | section 3 at 2000 tail lines (about 136 KB per mark); mutant N30 |

## 7. Same output before and after

Every here-document of the base became a single-quoted literal. `tools/byte_identity.sh` compares base and head
(`compare/byte_identity.txt`):

```
SAME     install_constitution.sh --help (output and exit status)    9041 bytes
SAME     install_constitution.sh --version (output and exit status) 35 bytes
SAME     install_constitution.sh --print-snippets (output and exit status) 636 bytes
SAME     install_constitution.sh hi_upstream_table (library mode)   1267 bytes
SAME     install_constitution.sh hi_agent_table (library mode)      196 bytes
SAME OUTPUT install_constitution.sh hi_parse_stream Python program  text differs in 1 line(s); output and exit status equal on all 23 fixtures
         -pat = re.compile(r'"api_?[eE]rror_?[sS]tatus"\s*:\s*429')
         +pat = re.compile(r"\"api_?[eE]rror_?[sS]tatus\"\s*:\s*429")
SAME     install_action_prefix.sh merge_with_python program         2914 bytes
exit=0
## control needle: one character changed in the new help text, one in the action-prefix program, and the
## installer's hi_parse_stream program reports rate_limited=2 (all three must show DIFFERS)
DIFFERS  install_constitution.sh --help (output and exit status)    base 9041 bytes, new 9041 bytes
SAME     install_constitution.sh --version (output and exit status) 35 bytes
SAME     install_constitution.sh --print-snippets (output and exit status) 636 bytes
SAME     install_constitution.sh hi_upstream_table (library mode)   1267 bytes
SAME     install_constitution.sh hi_agent_table (library mode)      196 bytes
DIFFERS  install_constitution.sh hi_parse_stream Python program     text differs and the output differs on 6 of 23 fixtures: fixed_03.jsonl, fixed_04.jsonl, fixed_05.jsonl, fixed_06.jsonl, fixed_18.jsonl, random_1.jsonl
         -pat = re.compile(r'"api_?[eE]rror_?[sS]tatus"\s*:\s*429')
         +pat = re.compile(r"\"api_?[eE]rror_?[sS]tatus\"\s*:\s*429")
         -        if pat.search(line): rl = 1
         +        if pat.search(line): rl = 2
DIFFERS  install_action_prefix.sh merge_with_python program         base 2914 bytes, new 2915 bytes
         -import json, os, re, secrets, sys
         +import json, os, re, secrets, sys 
exit=1
RESULT: PASS (every item SAME or SAME OUTPUT; the three control changes DIFFER)
```

`SAME OUTPUT` (the installer's stream parser): the program text differs in one line, because the program is now a
single-quoted shell literal, which cannot hold `'`; the regular expression is written with double quotes and
escaped inner quotes, the same pattern. Old and new program give the same output and exit status on 23 stream
fixtures (19 written by hand, 4 random).

Control needle, three changes in a copy of the head: one character of the help text, one in the action-prefix
program, and the stream parser reporting `rate_limited` 2 instead of 1. All three items must show DIFFERS, and they
do (same file, second block; the changed parser differs on 6 of the 23 fixtures).

Caller shell (`tools/caller_shell_compare.sh`, `compare/caller_shell_compare_host.txt`): for `--version`, `--help`
and `--print-snippets`, under each of nine inherited settings (`POSIXLY_CORRECT=1`, `SHELLOPTS=posix`,
`SHELLOPTS=noglob:nounset`, `SHELLOPTS=errexit`, `BASHOPTS=nocasematch:extglob:failglob:nullglob`, `BASH_COMPAT=44`,
`CDPATH=/nonexistent`, `GLOBIGNORE=*`, `TMOUT=1`; the same list as section 2 of `test_sigpipe.sh`) and under "no
temporary file", the head prints exactly what a clean run prints. The base differed under `POSIXLY_CORRECT=1` and `SHELLOPTS=posix` (exit 2, "incomplete
script"), and under "no temporary file" printed no help text and no snippets on standard output (only
bash's error message on standard error), still with exit status 0.

## 8. Mutants

Each mutant is one textual change to a copy of the tree; `test_sigpipe.sh` runs on the copy; a mutant is KILLED
when a check fails. RM01 to RM17 are the reviewer's mutants, rebuilt from the review text; N01 to N30 are new.
Runner: `tools/kill_table_runner.py` (anchors are checked to occur exactly once; a control run with no mutation
must pass first). Host bash 5.3.9 unless the bash column says otherwise. Sections of `test_sigpipe.sh`: 1 static
scan, 2 shell state, 3 `hi_push_changed`, 4 other helpers, 6 data-only ref names, 7 CLI link failures.

| ID | Mutation | bash | Verdict | Section | First failing check |
|---|---|---|---|---|---|
| RM01 | hi_layout gitlink check back to `\| grep -q` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM02 | hi_verify legacy-path check back to the double pipe | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM03 | hi_resolve_ref_in tag lookup back to `\| awk ... exit` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM04 | updater registered-submodule check back to `\| grep -q` | host | KILLED | 1 | static scan of `scripts/update_constitution.sh` (scan exit 1) |
| RM05 | updater hook capability probe back to `head \| grep -qE` | host | KILLED | 1 | static scan of `scripts/update_constitution.sh` (scan exit 1) |
| RM06 | CLI plugin check back to `claude plugin list \| grep -q` | host | KILLED | 1 | static scan of `scripts/install_cli_agent_plugins.sh` (scan exit 1) |
| RM07 | hi_upstream_ok back to `\| grep -qxF` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM08 | Z check reads the before-marks only | host | KILLED | 3 | normal, 0 tail lines: control needle and all 15 cases |
| RM09 | hi_layout check as `\| LC_ALL=C grep -q` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM10 | `\| grep -m1 . >/dev/null` added to hi_resolve_ref_in | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM11 | CLI plugin check as `\|& grep -q` | host | KILLED | 1 | static scan of `scripts/install_cli_agent_plugins.sh` (scan exit 1) |
| RM12 | Z check as `\| command grep -q` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM13 | R membership as `\| command grep -qxF` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM14 | L membership as `\| command grep -qxF` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM15 | N membership as `\| command grep -qxF` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| RM16 | Z check moved after the M-line comparison | host | KILLED | 3 | normal, 0 tail lines: control needle and all 15 cases |
| RM17 | updater hook probe as `\| egrep -q` | host | KILLED | 1 | static scan of `scripts/update_constitution.sh` (scan exit 1) |
| N01 | Z check as a here-string | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N02 | after-marks split by a here-string loop | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N03 | hi_upstream_ok through a here-document | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N04 | reset call removed (installer) | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N05 | reset call moved after the first <( (installer) | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N06 | installer no longer checks process substitution | host | KILLED | 2 | the installer refuses (exit 3) when process substitution does not work |
| N07 | hi_layout check as `\| fgrep -q` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N08 | hi_layout check as `\| \grep -q` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N09 | legacy-path check as `\| egrep -qv` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N10 | hi_resolve_ref_in through `\| head -n 1` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N11 | hi_upstream_ok through `\| sed -n ...q` | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N12 | CLI no longer counts a link it could not create | host | KILLED | 7 | read-only .claude/skills: exit 1, every failure counted and warned, nothing linked |
| N13 | CLI ignores failed links in its exit status | host | KILLED | 7 | read-only .claude/skills: exit 1, every failure counted and warned, nothing linked |
| N14 | R pre-filter keeps only a bare R | host | KILLED | 3 | normal, 0 tail lines: control needle and all 15 cases |
| N15 | before-marks pre-filter drops U | host | KILLED | 3 | normal, 0 tail lines: control needle and all 15 cases |
| N16 | hi_read_fields keeps trailing blanks | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N17 | hi_split_lines without set -f (globbing on) | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N18 | hi_line_in matches a substring | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N19 | hi_has_line_prefix matches anywhere | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N20 | hi_legacy_path_in without the submodules/ exclusion | host | KILLED | 4 | normal: installer helpers |
| N21 | reset no longer unsets BASH_COMPAT at its end | host | KILLED | 2 | hi_reset_shell_state in scripts/update_constitution.sh is identical to the installer's |
| N22 | reset leaves posix mode on | host | KILLED | 2 | hi_reset_shell_state in scripts/update_constitution.sh is identical to the installer's |
| N23 | R membership via [[ -v assoc[key] ]] | host | KILLED | 6 | notemp50: unchanged marks with command text read as unchanged, a moved ref as moved |
| N24 | hi_on_remote stops at the first remote commit that does not contain it | host | KILLED | 4 | normal: installer helpers |
| N25 | updater hook regex not anchored | host | KILLED | 4 | normal: updater up_hook_declares_project_root agrees with the regex it replaces |
| N26 | CLI reset call removed | host | KILLED | 2 | scripts/install_cli_agent_plugins.sh: reset called in run mode, right before set -euo pipefail |
| N27 | installer resets even when sourced | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N28 | hi_upstream_ok as a here-string | host | KILLED | 1 | static scan of `scripts/install_constitution.sh` (scan exit 1) |
| N29 | updater copy of hi_has_line_prefix matches anywhere | host | KILLED | 2 | the hi_shell_state block is identical in the installer and the updater |
| N30 | before-marks cut at 8 KiB (class e) | host | KILLED | 3 | normal, 200 tail lines: control needle and all 15 cases |
| N23 | R membership via [[ -v assoc[key] ]] | host | KILLED | 6 | notemp50: unchanged marks with command text read as unchanged, a moved ref as moved |
| N23 | R membership via [[ -v assoc[key] ]] | 5.0.17 | KILLED | 6 | normal: unchanged marks with command text read as unchanged, a moved ref as moved |

47 mutants, 47 killed on every bash they ran on (`kill/kill_table.tsv`, `kill/kill_table_n23.tsv`; anchors: `kill/anchors.txt`).

Twins. Several main mutants die in section 2 on a structural check ("the block is identical in the installer and
the updater"), which is not a test of behaviour. Each twin applies the same change to EVERY copy of the shared
block, so the identity check passes and only behaviour can kill it; the twins run to the end (`--no-stop`), and
the section column lists every section with a failure.

| ID | Mutation | bash | Verdict | Sections with a FAIL (FAIL lines) | First failing check |
|---|---|---|---|---|---|
| N04t | reset call removed (installer and updater) | host | KILLED | 2,8 (4 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [], first <( [76] |
| N05t | reset call moved after the first <( (installer and updater) | host | KILLED | 2 (2 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [78], first <( [75] |
| N16t | hi_read_fields keeps trailing blanks (both copies) | host | KILLED | 5 (1 FAIL) | 2500 comparisons, no mismatch |
| N17t | hi_split_lines without set -f (both copies) | host | KILLED | 5 (1 FAIL) | 2500 comparisons, no mismatch |
| N18t | hi_line_in matches a substring (both copies) | host | KILLED | 4,5 (4 FAIL) | normal: installer helpers |
| N19t | hi_has_line_prefix matches anywhere (both copies) | host | KILLED | 4,5 (4 FAIL) | normal: installer helpers |
| N21t | reset no longer unsets BASH_COMPAT (all four copies) | host | KILLED | 2 (1 FAIL) | hi_reset_shell_state undoes what a caller changed (options, BASH_COMPAT, CDPATH, GLOBIGNORE, TMOUT) |
| N22t | reset leaves posix mode on (all four copies) | host | SURVIVED: EQUIVALENT (section 4, fact 10) | 8 |  |
| N27t | installer and updater reset even when sourced | host | KILLED | 2,8 (5 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [], first <( [76] |
| N22u | reset leaves posix mode on: POSIXLY_CORRECT kept AND posix dropped from set +o (all four copies) | host | KILLED | 2 (2 FAIL) | hi_reset_shell_state undoes what a caller changed (options, BASH_COMPAT, CDPATH, GLOBIGNORE, TMOUT) |
| N04t | reset call removed (installer and updater) | host (second twin run) | KILLED | 2,8 (4 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [], first <( [76] |
| N04t | reset call removed (installer and updater) | 5.0.17 (second twin run) | KILLED | 2,8 (4 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [], first <( [76] |
| N05t | reset call moved after the first <( (installer and updater) | host (second twin run) | KILLED | 2 (2 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [78], first <( [75] |
| N05t | reset call moved after the first <( (installer and updater) | 5.0.17 (second twin run) | KILLED | 2 (3 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [78], first <( [75] |
| N27t | installer and updater reset even when sourced | host (second twin run) | KILLED | 2,8 (5 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [], first <( [76] |
| N27t | installer and updater reset even when sourced | 5.0.17 (second twin run) | KILLED | 2,8 (5 FAIL) | scripts/install_constitution.sh: HI_SOURCED line [45], reset call [], first <( [76] |

N22t is EQUIVALENT, not a test gap: it drops `posix` from the reset's `set +o` list, but the reset also runs
`unset POSIXLY_CORRECT`, and that alone turns posix mode off on every version measured, whichever of the three
ways turned it on (section 4, fact 10; `compare/reset_facts.txt`). The twin N22u removes both, so the reset really
leaves posix mode on; it must die, and the table above shows whether it did.

Three main mutants that die first on a section-2 check were also run to the end (`--no-stop`, `kill/kill_table_nostop.tsv`): N04 KILLED, sections 2,8 (4 FAIL); N05 KILLED, sections 2 (2 FAIL); N26 KILLED, sections 2,7 (2 FAIL).

## 9. The no-push gate after round 2

`CM-INSTALLER-NO-PUSH-NO-FORCE` (`scripts/gates/cm_installer_no_push_no_force.sh`) checks that the installer and
the updater cannot push, force, rewrite history or run dynamic code. Its four checks, as its own header names them:
(a) structure and allow-lists over every command the lexer finds (external commands with their argument shapes,
listed `sed`/`awk` programs, literal Python programs only, file-changing commands only as exact pairs); (b) the
case labels of `hi_gx_check`; (c) a raw line denylist (`push`, `--force`, `reset`, `eval`, ...) over the text with
comments and message carriers removed; (d) a runtime check with a fake `git`. Round 2's fix commit was not run
through it. Each commit's own gate, run on a full `git archive` of that commit with the
installer and updater of that commit (`gate/gate_by_commit.txt`, `tools/gate_by_commit.sh`; the base passing is
the control needle):

| Commit | Subject | Gate result | Exit |
|---|---|---|---|
| bd0036bd | fix(sonarqube): validate user and password separately, no IFS splitting of secrets (round-5 review I-1) | PASS | 0 |
| 6f28765c | fix(install): no pipe into an early-exit reader under pipefail (SIGPIPE 141 read as no match); test_lock stale-poll race | PASS | 0 |
| 58815d75 | fix(install): review round 2: one rule per class, no temporary-file or caller-shell dependency at any decision, deny-by-default scanner | FAIL (18 finding(s)) | 1 |
| 1914a91b | fix(install): round 2 left the no-push gate red on its own files (18 findings); literal shopt calls, inline Python literal, printed-literal mask in the raw scan | PASS | 0 |

The 18 findings on 58815d75, their cause and the repair in 1914a91b:

| Findings | Check | Lines (installer, updater) | Cause | Repair |
|---|---|---|---|---|
| 4 | (a) command not on the allow-list: `shopt -u "$o"`, `shopt -s "$o"` | 67, 69; 75, 77 | `hi_reset_shell_state` changed bash options in a loop over a variable; (a) allows a command only when it can read its words | one `shopt -u` call and one `shopt -s` call with the option names written out, in all four copies (section 4, fact 9 shows this behaves like the loop on every version). The gate now treats `shopt` like the commands that change files: allowed only as these two exact calls, option lists included |
| 2 | (a) `python -c` with a non-literal program; the program is not a literal | 571 | the stream parser's program was in a variable | the program is an inline single-quoted literal; same output on 23 fixtures (section 7) |
| 4 | (a) awk program not on the allow-list | 598, 618; 633, 634 | four awk programs that round 2 added (`NR == 1`, the upstream-table reader, `NR <= 10`, `NR <= 20`) | added to the program allow-list; five entries that no longer occur in either file removed |
| 8 | (c) forbidden: `push` | 188, 193, 199, 201, 202, 204, 205, 210 | round 2 moved the `--help` text out of a quoted here-document, which (c) skips as data, into multi-line `printf` literals; (c) then read the help lines that mention push as code | the printed-literal mask below |

The printed-literal mask. Before the raw scan, the gate blanks the text of a multi-line `printf` or `echo`
argument (newlines kept, so line numbers stay), but only when two independent views agree: the lexer sees a simple
command whose first word is `printf` or `echo` and an argument made only of single-quoted parts and backslash
escapes that spans lines; and, on that argument's first line, only `printf`/`echo`, options and one-line
single-quoted words come before it. What the printed text feeds is still checked by (a): the same literal piped
into `bash` or `sh`, or written to a `.sh` file, is refused by (a) while (c) alone masks it, and the help-text
shape passes (`gate/printed_literal_feeds.txt`, `tools/gate_feed_probe.py`).

Control needles (if one fails, the gate prints BLIND and exits 2). For the raw scan alone, 8 texts it must still
flag: a multi-line literal that is not printed (an assignment), code after a printed literal on its last line, a
`printf` line inside a double-quoted string, the same inside an unquoted here-document, a double-quoted multi-line
`printf` argument (two forms: double-quoted format, single-quoted format), a `printf` that does not start its line
(`true; printf ...`), and a literal after `echo` when `echo` is not the command (`ssh h \` then `echo '...'` on the
next line: ssh joins its arguments into a remote command line); and 3 texts it must not flag (the help-text shape,
an `echo` literal sent to standard error, a literal that contains `'\''`). For the full scan: `shopt -s
expand_aliases` must be a finding, and an exact sanctioned `shopt -u extglob` and the help-text shape must pass.

Mutants of the mask and of the `shopt` rule (`tools/gate_mask_mutants.py.txt`, run as `python3 -I`; one change to a copy of the gate, the
gate run on the head's installer and updater; KILLED means the gate did not PASS):

| ID | Mutation | First run | Second run (two needles added) |
|---|---|---|---|
| control | unmutated copy | PASS | PASS |
| GM1 | mask any command's multi-line literal (no printf/echo condition) | SURVIVED | KILLED (BLIND) |
| GM2 | mask to the end of the literal's last line | KILLED (BLIND) | KILLED (BLIND) |
| GM3 | mask any multi-line word (no all-literal check) | SURVIVED | KILLED (BLIND) |
| GM4 | no line check (PRINT_HEAD) on the literal's first line | KILLED (BLIND) | KILLED (BLIND) |
| GM5 | double-quoted parts count as literal | SURVIVED | KILLED (BLIND) |
| GM6 | the mask is not applied (raw scan reads the original text) | KILLED (BLIND) | KILLED (BLIND) |
| GM7 | shopt dropped from the exact-pair commands (any shopt allowed as a safe builtin) | KILLED (BLIND) | KILLED (BLIND) |

Second run: 7 of 7 mutants killed; the control (unmutated copy) PASS.

The first run left GM1, GM3 and GM5 alive (`gate/gate_mask_mutants_run1.tsv`, written down from that run before the
tool overwrote its file). Cause: the needle for a double-quoted multi-line argument also had a double-quoted format
string, which the first-line check rejects first, so the all-literal check (GM3) and the double-quote check (GM5)
were never reached; and no needle had a multi-line literal after `echo` in a command whose first word is not
`printf`/`echo` (GM1). The two needles with a single-quoted format and with `ssh` were added; the second run kills
all seven (`gate/gate_mask_mutants.tsv`).

The gate's own meta-test (`scripts/gates/cm_installer_no_push_no_force_mutation_test.sh`), with eight new cases:
SP-G1 (golden-FALSE: the help-text shape with `push`, `--force` and `reset` words passes) and SP-M1 to SP-M7 (a
multi-line literal that is not printed, code after a printed literal, a printf line inside a double-quoted string,
the sanctioned `shopt -s` call with one more option, `shopt` outside the reset, a changed `hi_version_of` awk
program, and the stream parser importing `os`; each must fail): `META PASS: CM-INSTALLER-NO-PUSH-NO-FORCE kills every mutant (218 cases)` (`gate/mutation_test.txt`).

Not done here: the gate checks for stale allow-list entries only in `EXEMPT` and `DYN_NAME_EXEMPT`; `PROGS`,
`EXT_EXACT` and `GX_EXACT` have no such check, which is how five stale awk entries survived. A follow-up.

## 10. Suite runs

All runs on frozen clones of 1914a91b, one at a time per lane, under
`systemd-run --user --scope -p TasksMax=2000` and `nice -n 10`; host load average was between 6 and 24 (1-minute average, sampled every 5 minutes, `runs/load.log`) during the
runs, so wall times are informative only. The same runs on 58815d75 were stopped when the gate failure (section 9)
was found; their logs are kept in `runs/superseded_58815d75/` and are not counted here. They also showed a cluster
that is not explained by the gate: in two of those five `run_all.sh` runs, installer runs exited 3 where the tests expected 0: 5 checks in
`agent_unit_fake` of `runall_5.2.37_r2`, and 22 checks in `integration`, `agent_unit_fake` and `self-guard` of
`runall_host_r3`, each with its follow-on failures (`runs/superseded_58815d75/exit3_census.txt`,
`tools/exit3_census.py`). The suites keep the installer's error text only in some places. Where they do (three
times, all in `runall_host_r3`) it reads `[constitution] ERROR: less than 1 GiB free on the project filesystem`:
the installer's own free-space check in `main` (the same line is in the base bd0036bd), which runs before anything
is changed and before the plan and the report are written. For those three runs the cause is a nearly full file system, not the change. The file
system that holds the sandboxes is shared with other jobs on the host and was 99 % full when the re-run started;
its free space was not sampled during the superseded runs. For the other exit-3 checks no error text was kept, so their cause
is UNCONFIRMED; they have the same shape (exit 3, no plan, no report). To catch a repeat, the re-run on 1914a91b
had a sentinel beside lane B (`tools/exit3_sentinel.sh`): once a minute it recorded a host sample (load, free
space, processes, threads, available memory) and ran the head's installer in a fresh project against a local
upstream (a dry run, every fifth time a real install), keeping the whole output of any run that did not exit 0. Result: 195 probes from 2026-11-14T06:42:27Z to 2026-11-14T10:05:01Z (156 dry-run, 39 install); the sentinel wrote no end line: it stopped at the same time as lane B (its last probe 2026-11-14T10:05:01Z, the last write to lane B's run-3 log 2026-11-14T10:06:04Z), when the agent session that started both had been ended; every probe exited 0. Free space on that file system during the re-run: between 22.5 GiB (2026-11-14T09:32:45Z) and 32.3 GiB; load between 6 and 23; below 1 GiB in 0 of 195 samples (`runs/sentinel.tsv`, `runs/host_samples.tsv`).

`tests/install/test_sigpipe.sh`, three runs per bash:

| bash | run 1 | run 2 | run 3 |
|---|---|---|---|
| 5.0.17 | PASS 67 FAIL 0, rc 0, 149 s | PASS 67 FAIL 0, rc 0, 141 s | PASS 67 FAIL 0, rc 0, 152 s |
| 5.1.4 | PASS 67 FAIL 0, rc 0, 114 s | PASS 67 FAIL 0, rc 0, 104 s | PASS 67 FAIL 0, rc 0, 113 s |
| 5.1.16 | PASS 67 FAIL 0, rc 0, 96 s | PASS 67 FAIL 0, rc 0, 94 s | PASS 67 FAIL 0, rc 0, 99 s |
| 5.2.15 | PASS 67 FAIL 0, rc 0, 89 s | PASS 67 FAIL 0, rc 0, 89 s | PASS 67 FAIL 0, rc 0, 95 s |
| 5.2.26 | PASS 67 FAIL 0, rc 0, 148 s | PASS 67 FAIL 0, rc 0, 147 s | PASS 67 FAIL 0, rc 0, 145 s |
| 5.2.37 | PASS 67 FAIL 0, rc 0, 91 s | PASS 67 FAIL 0, rc 0, 99 s | PASS 67 FAIL 0, rc 0, 99 s |
| 5.3.9 (host) | PASS 67 FAIL 0, rc 0, 93 s | PASS 67 FAIL 0, rc 0, 84 s | PASS 67 FAIL 0, rc 0, 86 s |

Every run reports the same counts: yes, PASS 67 FAIL 0.

`tests/install/run_all.sh --quick` (the whole installer suite), three runs per bash, in `env -i` with
`HOME=/nonexistent-home`:

| bash | run | result | seconds | no-push gate, its meta-test | `test_agent` "timeout honoured (< 20 s)" |
|---|---|---|---|---|---|
| 5.3.9 (host) | 1 | RUN_ALL: PASS | 2521 | PASS, META PASS | ok |
| 5.2.37 | 1 | RUN_ALL: PASS | 2560 | PASS, META PASS | ok |
| 5.3.9 (host) | 2 | RUN_ALL: PASS | 2387 | PASS, META PASS | ok |
| 5.2.37 | 2 | RUN_ALL: PASS | 2373 | PASS, META PASS | ok |
| 5.3.9 (host) | 3 | RUN_ALL: PASS | 2268 | PASS, META PASS | ok |
| 5.2.37 | 3 | not finished: the agent session that ran lane B was ended (weekly API limit) during this run; 0 FAIL lines up to then, suites finished: test_unit, test_integration (`runs/runall_5.2.37_r3.partial.log`); not counted | | | |

Per-suite PASS/FAIL counts of every run: `runs/runall_per_suite_counts.txt`; the full log is kept only for a run that failed.
The per-suite counts are the same in every run.

Short suites that cover the other changed files, three runs per bash:

| suite | bash | run 1 | run 2 | run 3 |
|---|---|---|---|---|
| `test_cli_agent_plugins` | host | rc 0, 40 s; == cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) == | rc 0, 37 s; == cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) == | rc 0, 38 s; == cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) == |
| `test_cli_agent_plugins` | 5.2.37 | rc 0, 37 s; == cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) == | rc 0, 40 s; == cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) == | rc 0, 41 s; == cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) == |
| `test_install_cli_agent_plugins_ownership` | host | rc 0, 548 s; PASS H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix) | rc 0, 479 s; PASS H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix) | rc 0, 486 s; PASS H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix) |
| `test_install_cli_agent_plugins_ownership` | 5.2.37 | rc 0, 404 s; PASS H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix) | rc 0, 481 s; PASS H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix) | rc 0, 489 s; PASS H3 installer ignores ambient HELIX_ACTION_OUT_ROOT (prefix) |
| `test_action_prefix_grammar` | host | rc 0, 31 s; RESULT: PASS=166 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T081105Z_3815476) | rc 0, 30 s; RESULT: PASS=166 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T084216Z_3098508) | rc 0, 29 s; RESULT: PASS=166 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T091505Z_3093182) |
| `test_action_prefix_grammar` | 5.2.37 | rc 0, 24 s; RESULT: PASS=166 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T082626Z_1111638) | rc 0, 30 s; RESULT: PASS=166 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T085843Z_1058192) | rc 0, 29 s; RESULT: PASS=166 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T093147Z_1370019) |
| `meta_test_action_prefix_grammar` | host | rc 0, 442 s; META RESULT: PASS=6 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T081136Z_3871536/meta) | rc 0, 431 s; META RESULT: PASS=6 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T084246Z_3180492/meta) | rc 0, 436 s; META RESULT: PASS=6 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T091535Z_3170741/meta) |
| `meta_test_action_prefix_grammar` | 5.2.37 | rc 0, 404 s; META RESULT: PASS=6 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T082650Z_1135870/meta) | rc 0, 422 s; META RESULT: PASS=6 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T085913Z_1136959/meta) | rc 0, 421 s; META RESULT: PASS=6 FAIL=0  (evidence: <scratch>/ev2.SZvM/coA/qa-results/action_prefix/20261114T093216Z_1427510/meta) |
| `test_setup_prompt_round4` | host | rc 0, 7 s; PASS M-8 STEP3 picks v10 (not v11-rc1) | rc 0, 5 s; PASS M-8 STEP3 picks v10 (not v11-rc1) | rc 0, 6 s; PASS M-8 STEP3 picks v10 (not v11-rc1) |
| `test_setup_prompt_round4` | 5.2.37 | rc 0, 6 s; PASS M-8 STEP3 picks v10 (not v11-rc1) | rc 0, 5 s; PASS M-8 STEP3 picks v10 (not v11-rc1) | rc 0, 5 s; PASS M-8 STEP3 picks v10 (not v11-rc1) |

Changed paths in the frozen clone after each pass (the meta-test restores what it mutates): host r1 0, 5.2.37 r1 0, host r2 0, 5.2.37 r2 0, host r3 0, 5.2.37 r3 0.

## 11. Performance of hi_push_changed

One run per size, host load about 80, informative only, never a verdict (`perf/perf_push_changed.txt`). `b == a`,
n R lines per mark:

| n | bytes per mark | base, reflog fetch count 1 (skip path) | head, skip path | base, fetch count 0 (membership path) | head, membership path |
|---|---|---|---|---|---|
| 200 | 14 362 | 324 ms | 140 ms | 7 156 ms | 129 ms |
| 2 000 | 144 962 | 835 ms | 1 663 ms | 56 672 ms | 1 879 ms |
| 20 000 | 1 468 962 | 11 451 ms | 14 526 ms | not measured (stopped after about 3 minutes) | 15 662 ms |

On the skip path the head is slower (about 2 times at 2000 lines). On the membership path the base runs one grep
over the whole mark per R line (quadratic); the head is linear.

## 12. Landing order

A trial merge of the sync vehicle (b5a1815a) into this vehicle at 1914a91b (`landing/trial_merge.txt`,
`tools/trial_merge.sh`, in a throwaway clone): the sync vehicle conflicts with `main` in `CHANGELOG.md` and
`README.md` whether or not this vehicle has landed (control merge onto bd0036bd alone); this vehicle touches neither
file. The one conflict this vehicle adds is the generated census line in `docs/guides/full_suite_runner_guide.md`;
`bash scripts/run_full_suite.sh --sync-guide` regenerates it, whichever side is taken. `tests/install/test_unit.sh`
and `config/full_suite_manifest.tsv` merge without conflict; `docs/guides/installer_user_guide.md`, which 1914a91b
changes, is not touched by the sync vehicle. Either order works: whichever vehicle lands second merges `main` (never
rebases) and regenerates the census line. `--verify-manifest` reports the same three problems on both sides: three
`scripts/sonarqube/tests/` files without a manifest row, which come from `main`: bd0036bd alone reports the same
three (`landing/manifest_verify_base.txt`).

The first run of `tools/trial_merge.sh` listed `README.md` as a conflict this vehicle adds. Cause: the script sorted
the path lists in the session's locale and `comm` (uutils) refused the order, so the list difference was wrong. The
script now sorts and compares in the C locale and checks that the added list and the control list together give
back every unmerged path; the run above passes that check.

## 13. F9: the test_round8 chaos loop

**Hardening, in its own commit a5ee2ab4** (on the conductor's instruction; the round-1 review rated F9 minor,
test-instrumentation, pre-existing). In the I-1 chaos loop of `tests/install/test_round8.sh` an update run is cut by
SIGINT or SIGTERM and a clean re-run must then converge. Two ways the re-run can start too early were named: a
process of the killed run still holding the run lock (exit 3), and git cut while it held `index.lock`. A separate
agent proposed a change to the loop (`tr8/other_agent/proposed_test_round8.diff`). The commit is that proposal with
three defects found in it and fixed before landing:

| # | Defect in the proposal | RED on the proposal | Change in a5ee2ab4 |
|---|---|---|---|
| 1 | its lock probe `find /proc/[0-9]*/fd ... \| grep -q .` read find's exit status; find exits non-zero when one `/proc/<pid>/fd` cannot be read (another user's process), so under the file's `pipefail` every lock read as stale, a lock held open included | 3 of 3 (`tr8/red_proposed_probe_pipe_form.txt`) | find's output is captured, then tested (rule (c) of section 6, applied to the test) |
| 2 | it waited on the process GROUP (`kill -0 -- -PGID`); a member in a group of its own inside the killed session (uutils `timeout` makes one) is invisible to that probe | the group drain reported "drained" (rc 0) with a live `timeout` and `sleep` in their own group (`tr8/red_group_drain_misses_own_group_member.txt`) | `drain_session`: waits, bounded to 30 s, until `ps -s SID` lists no process of the installer's session |
| 3 | it signalled `-PGID` whatever the group was; a pgid read before `setsid` ran would be the test's own group | not seen: 0 of 200 probes at 0.05 s, host load about 27 (`tr8/pgid_before_setsid_probe.txt`) | the signal goes only to the installer's own group (pgid == pid) |

What the loop does with a stale lock: git creates `index.lock` before it installs its cleanup handler, so a signal
in that window leaves a lock that no process holds (the other agent's strace trial, `tr8/other_agent/git_lock_race_1.jsonl`:
handled arm: lock left in 0 of 8, none arm: lock left in 0 of 8, window arm: lock left in 7 of 8). The re-run must then refuse loudly (`index.lock` in its output) and leave the gitlink unchanged; the
lock is removed as git's message says, and the next re-run must converge.

The test-level race itself is **UNREPRODUCED**: the unchanged test passed in 20 of 20 runs of the other agent
(`tr8/other_agent/base20_results.txt`, each `round8: PASS 86 FAIL 0`). The git window and the session member in a
group of its own are measured. This is hardening, not the fix of an observed failure.

Control needles, run in every chaos run and by `tools/tr8_needles.sh` alone (a lock held by a live process is not
reported, the same lock closed is; a session whose leader is gone is not drained while a member lives, also when
that member has a group of its own; it is drained once the members are gone):

| bash | run 1 | run 2 | run 3 |
|---|---|---|---|
| host | PASS 5 FAIL 0 | PASS 5 FAIL 0 | PASS 5 FAIL 0 |
| 5.0.17 | PASS 5 FAIL 0 | PASS 5 FAIL 0 | PASS 5 FAIL 0 |
| 5.2.37 | PASS 5 FAIL 0 | PASS 5 FAIL 0 | PASS 5 FAIL 0 |

Own mutants of the lock probe and of `drain_session` (`tools/tr8_mutants.py.txt`, run as `python3 -I`; a control run on the unmutated file
must pass first, every anchor occurs exactly once):

| ID | Mutation | host | 5.0.17 | 5.2.37 | First failing needle (host) |
|---|---|---|---|---|---|
| TM1 | probe back to the proposed pipe form (status of find \| grep -q . under pipefail) | KILLED | KILLED | KILLED | stale-lock probe: a lock held open by a live process is not reported (expected [] got [.git/index.lock]) |
| TM2 | probe never reports a lock | KILLED | KILLED | KILLED | stale-lock probe: the same lock, closed, is reported (expected [.git/index.lock] got []) |
| TM3 | -lname replaced by -name (fd links never match) | KILLED | KILLED | KILLED | stale-lock probe: a lock held open by a live process is not reported (expected [] got [.git/index.lock]) |
| TM4 | held/stale test inverted | KILLED | KILLED | KILLED | stale-lock probe: a lock held open by a live process is not reported (expected [] got [.git/index.lock]) |
| TM5 | probe reads only its own descriptors | KILLED | KILLED | KILLED | stale-lock probe: a lock held open by a live process is not reported (expected [] got [.git/index.lock]) |
| TM6 | lock search uses a wrong file name | KILLED | KILLED | KILLED | stale-lock probe: the same lock, closed, is reported (expected [.git/index.lock] got []) |
| TM7 | reported path not made relative to P | KILLED | KILLED | KILLED | stale-lock probe: the same lock, closed, is reported (expected [.git/index.lock] got [<scratch>/tr8/session/m.host.TEye/tm.fa39__4d/needle_lock/.git/index.lock]) |
| TM8 | drain_session never waits (returns 0 at once) | KILLED | KILLED | KILLED | drain_session: leader gone, two members alive -> not drained after 1 s |
| TM9 | drain_session never reports a drained session | KILLED | KILLED | KILLED | drain_session: every member gone -> drained |
| TM10 | drain_session back to the process-group probe of the proposal | KILLED | KILLED | KILLED | drain_session: only the member in a group of its own alive -> not drained after 1 s |
| TM11 | drain_session lists the leader pid instead of the session | KILLED | KILLED | KILLED | drain_session: leader gone, two members alive -> not drained after 1 s |
| TM12 | drain_session uses a ps selector this ps does not have (blind ps) | KILLED | KILLED | KILLED | drain_session: leader gone, two members alive -> not drained after 1 s |

12 mutants on 3 bash versions: every one killed.

The pgid == pid guard is inline in the loop and has no needle of its own. `CM-INSTALLER-NO-PUSH-NO-FORCE` passes on
the change (`tr8/gate_no_push_on_the_change.txt`) and shellcheck reports the same warning set before and after
(`tr8/shellcheck_warnings_*.txt`).

Runs on frozen clones of a5ee2ab4, under the same scope, `nice` and `env -i` as section 10; host load average
between 11 and 34 (`tr8/runs/load.log`). `tests/install/test_round8.sh` alone (the chaos loop included):

| bash | run | exit status | result | seconds |
|---|---|---|---|---|
| 5.3.9 (host) | 1 | 0 | round8: PASS 91 FAIL 0 | 263 |
| 5.3.9 (host) | 2 | 0 | round8: PASS 91 FAIL 0 | 261 |
| 5.3.9 (host) | 3 | 0 | round8: PASS 91 FAIL 0 | 254 |
| 5.2.37 | 1 | 0 | round8: PASS 91 FAIL 0 | 238 |
| 5.2.37 | 2 | 0 | round8: PASS 91 FAIL 0 | 245 |
| 5.2.37 | 3 | 0 | round8: PASS 91 FAIL 0 | 239 |

`tests/install/run_all.sh --quick` (it runs `test_round8` with its chaos loop):

| bash | run | result | seconds | `test_round8` in this run | `test_agent` "timeout honoured (< 20 s)" |
|---|---|---|---|---|---|
| 5.3.9 (host) | 1 | RUN_ALL: PASS | 2579 | PASS 91 FAIL 0 | ok |
| 5.3.9 (host) | 2 | RUN_ALL: PASS | 2305 | PASS 91 FAIL 0 | ok |
| 5.2.37 | 1 | RUN_ALL: PASS | 3010 | PASS 91 FAIL 0 | ok |
| 5.2.37 | 2 | RUN_ALL: PASS | 2451 | PASS 91 FAIL 0 | ok |

Per-suite counts: `tr8/runs/runall_per_suite_counts.txt`; the full log is kept only for a run that failed.

The other suites are unchanged by a5ee2ab4, which touches `tests/install/test_round8.sh` only; their runs on
1914a91b in section 10 stand. The sync vehicle (section 12) does not touch `test_round8.sh`.

**Tracked item.** Searched at bd0036bd: `docs/`, `CHANGELOG.md`, `README.md` (tracked text) and
`docs/workable_items.db` (titles and descriptions), for `test_round8`, `round8`, `re-run race`, `rerun race`,
`timeout --foreground`, `SIGTERM chaos`, `installer flake`, `git lock`, `index.lock`, `process group`, `flake`,
`re-run` and the item name. Positive control: CON-110 is found. Result: **not found**. Near hits are different
issues: CON-127 (`test_round8_git_env`: a fixture copy lacks `.gitignore`) and CON-110 (`timeout --foreground` on
budget expiry signals only the engine, not its git children). Script and output: `f9/`. Recommendation to the
conductor: file the re-run race as its own item. Because the race is UNREPRODUCED, the hardening above can carry
that item only to PROVISIONAL-DONE labelled UNREPRODUCED (§11.4.292(D)), never to verified, until a live reproduction
of the race exists.

## 14. Cross-check against the review's alternative patch

The review proposed an alternative fix of `hi_push_changed` (`altpatch/review_alt_patch.diff`): the Z check as a
test inside the shell (`[[ "$nl$b$nl$a$nl" == *"${nl}Z "* ]]`), the membership checks as shell patterns, and the
loops fed by process substitution instead of here-strings. The conductor asked for it to be applied. Its intent is
already in the head and the patch was **not applied as written** (decision under §11.4.101, reported to the
conductor):

- the Z check at the head is `hi_has_line_prefix "$b$nl$a" 'Z '`, which is the same test (`altpatch/alt_patch_vs_head_source.txt`;
  `hi_has_line_prefix` is `[[ "$nl$1" == *"$nl$2"* ]]`); the `hi_verify` site uses `hi_legacy_path_in`, a test
  inside the shell as well. `grep -n '<<<'` finds 8 lines in the head installer, all comments; the same grep finds 18 lines in the base.
- the loops: the alternative's `< <(printf ...)` needs `/dev/fd` or a named pipe, a second dependency of the same
  kind as the temporary file of class (a); the head splits the marks once with `hi_split_lines` (no file, no pipe,
  no subprocess) and loops over the array.

Measured with the review's own probes on both:

- the review's edge-case comparison (`probes/edge_marks_diff.sh`, 12 cases): alternative against the head, 0
  differences; alternative against a negative-control installer (the head with the after-marks removed from the Z
  check, `altpatch/negative_control_installer.diff`), 1 difference, the case `Z_in_after_only`, so the comparison
  can see a change of that check (`altpatch/edge_marks_alt_vs_*.txt`).
- the review's RED/GREEN harness (`probes/repro_harness.sh`) on the head gives the same result in every leg as the
  review's run on the alternative (`altpatch/repro_harness_head.txt`, `altpatch/review_repro_harness_alt.txt`).
- the review's no-temporary-file probes (`probes/ctr/repro_tmp.sh`, `probes/ctr/control_same.sh`) on round 1, the
  head and the alternative, with `BASH_COMPAT=50` and temporary files made unwritable by `ulimit -f 0`
  (`tools/notemp_run.sh`, `altpatch/notemp_r1_head_alt.txt`):

| bash | installer | condition | here-string readable (needle) | Z refused, 4 sizes | moved ref seen | changed L seen | unchanged marks proceed |
|---|---|---|---|---|---|---|---|
| host | round 1 (6f28765c) | temporary file writable | yes | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| host | round 1 (6f28765c) | no temporary file | no | 0 of 4 | 0 of 4 | 0 of 4 | 3 of 3 |
| host | head (1914a91b) | temporary file writable | yes | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| host | head (1914a91b) | no temporary file | no | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| host | review's alternative | temporary file writable | yes | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| host | review's alternative | no temporary file | no | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| 5.2.37 | round 1 (6f28765c) | temporary file writable | yes | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| 5.2.37 | round 1 (6f28765c) | no temporary file | no | 0 of 4 | 0 of 4 | 0 of 4 | 3 of 3 |
| 5.2.37 | head (1914a91b) | temporary file writable | yes | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| 5.2.37 | head (1914a91b) | no temporary file | no | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| 5.2.37 | review's alternative | temporary file writable | yes | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |
| 5.2.37 | review's alternative | no temporary file | no | 4 of 4 | 4 of 4 | 4 of 4 | 3 of 3 |

  Round 1 misses the Z line, the moved ref and the changed L line when no temporary file can be written; the head
  and the alternative see all of them, and leave unchanged marks alone. The here-string needle says "no" in the
  no-temporary-file rows, so the condition was really in force.

A first run of the head under that condition lost its output: its stdout went to a regular file, which `ulimit -f 0`
also refuses. It is kept as a record of the instrument error (`altpatch/repro_harness_head_notemp50.INVALID.txt`
and its note) and is replaced by the run above, whose output went to a pipe.

## 15. Honest limits

1. **Real bash 4.4: UNCONFIRMED.** No bash 4.4 binary or image is on this host and nothing was pulled. Versions
   run: 3.2.57 (version gate only), 5.0.17, 5.1.4, 5.1.16, 5.2.15, 5.2.26, 5.2.37 and the host 5.3.9, each copied
   from an image already on the host (`bash_sources.txt`). `BASH_COMPAT=44` on a newer bash changes some behaviour (the
   `notemp44` condition) but not the parser, so it is an emulation, not bash 4.4.
2. **"No temporary file" is emulated with `ulimit -f 0`.** bash then fails to write the file (EFBIG) and reports
   `cannot create temp file for here-document`, the same message and the same skipped command the reviewer measured
   with read-only directories and a full tmpfs on round 1. Read-only directories and ENOSPC were not re-run in this
   round (no containers were started).
3. **What the reset cannot undo:** `BASH_ENV` and exported functions run before the first line of a script; the
   options `noexec` and `onecmd` stop a script before the reset could matter. The block comment of `hi_shell_state`
   says so. A bash option added after 5.3 is not in the reset list until someone adds it; the nine hostile settings
   the test applies are listed in section 7.
4. **C locale.** The two new helpers `hi_legacy_path_in` and the updater's `up_hook_declares_project_root` set
   `local LC_ALL=C`, so their bracket expressions do not depend on the caller's locale (`hi_restore_rel` already did
   so in the base). No other helper changes the locale.
5. **Rewritten sites without a no-temporary-file run of their own.** Installer: `hi_sanitize_url`,
   `hi_is_constitution_repo`, `hi_holder_alive`, `hi_stop_agent`, `hi_staged_only_gitlink`, `hi_gitlink_of`,
   `hi_gitlink_committed`, `hi_symlinked_parent`, `hi_restore_rel`, `hi_version_of`, `hi_detect_agents`,
   `hi_parse_args`, `hi_resolve_ref`; updater: the registered-submodule check, the pending-update display,
   `up_gitlink_of` and the log and changelog display; CLI installer: the plugin check. They now contain no
   here-string, no here-document and no early-exit reader (scanner), and the existing suites in section 10 run them
   in the normal condition only.
6. **The scanner's allow list is a point of trust.** Four functions are accepted as whole-input readers because their
   bodies were read by hand (section 5). A change to one of their bodies is not re-checked by the scanner.
7. **`test_round8` writes a git shim with `#!/bin/bash`.** When `run_all.sh` runs under bash 5.2.37 on `PATH`, that
   shim still runs the host bash 5.3.9; everything else follows `PATH`.
8. **`test_agent` "timeout honoured (<20 s)"** is a wall-clock check; the reviewer measured that it fails on the base
   and the head alike under load. Section 10 records the result of every run; the check is not changed.
9. **Python isolation.** The installer's three Python programs (the URL text filter, the stream parser and the
   uuid fallback) and the updater's one program run as `python3 -I -c '...'` with the program written inline as a
   single-quoted literal (the stream parser became one in 1914a91b, section 9). The action-prefix installer's merge
   program runs as `python3 -c "$prog"`, without `-I`, exactly as the base ran it with `python3 -` (no `-I` either);
   the commit message of 58815d75 says "the Python helpers run as `python3 -I -c`", which is true for the installer
   and the updater only. Adding `-I` there is a separate hardening, not done here.
10. **Performance:** on the path where every R line is skipped, the head is slower than the base (section 11). One
    run per size under load; not a verdict.
11. **Mutant coverage by version:** the full kill table ran on the host bash 5.3.9; N23 and three twins also ran on
    bash 5.0.17. The other mutants were not run on every version; `test_sigpipe.sh` itself ran three times on
    every version (section 10).
12. **Evidence class:** gate-logic and unit only (§11.4.289). No installer run against a real remote, no agent run.
    The fix is PROVISIONAL until an independent review returns GO.
13. **Not linked from the main README.** Neither round links this directory from `README.md` or `CHANGELOG.md`;
    this vehicle leaves both files alone so that it does not conflict with the sync vehicle (section 12). The link
    and the changelog entry belong to the landing step.
14. **CLI clean-up step:** `link_agent_commands` does not check the removal of a dangling link it owns
    (`rm -f "$stale"`); a failure leaves the dangling link and changes no decision.
15. **`patsub_replacement` is turned off,** which is not bash 5.2's default (on): with it off, `&` in the
    replacement of `${x//pattern/replacement}` is a literal `&` on every version, as in bash 5.0 and 5.1. The six
    files have 9 pattern substitutions, all in the installer, and none has `&` in it (`compare/patsub_amp_scan.txt`,
    `tools/amp_scan.py`, with a positive and a negative control), so the setting changes no output. The code
    comment "to bash's defaults" is imprecise for this one option and is left as is in this round.
16. **The printed-literal mask of the no-push gate (section 9)** blanks only a multi-line `printf` or `echo`
    argument made of single-quoted parts and backslash escapes, whose first line passes the line check. A
    double-quoted or one-line argument is still read by the raw scan, and so is any literal that is not printed.
    What a printed literal feeds (a pipe into `bash`, a `.sh` file) is checked by (a), not by (c); the four shapes
    of `gate/printed_literal_feeds.txt` were probed, not every shape.
17. **Stale allow-list entries:** the no-push gate reports stale entries only for `EXEMPT` and `DYN_NAME_EXEMPT`.
    `PROGS`, `EXT_EXACT` and `GX_EXACT` have no such check (five stale awk programs were removed by hand in
    1914a91b). A follow-up, not done here.
18. **The exit-3 cluster of the superseded runs (section 10):** the cause is measured for the three runs whose
    error text was kept (less than 1 GiB free); for the other exit-3 checks it is UNCONFIRMED. The sentinel samples
    one installer run per minute and one host sample per minute; a full disk that lasts less than a minute can fall
    between two samples.
19. **The sentinel was a third process beside the two heavy lanes**: one installer run a minute, a few seconds each
    (`runs/sentinel.tsv`, column `secs`). It adds a little load to lane B's wall times, which are informative only.
20. **The `test_round8` hardening (a5ee2ab4) does not reproduce the race it guards against.** The test-level
    re-run race is UNREPRODUCED (section 13); what is measured is git's lock window and a session member in a group
    of its own. The pgid == pid guard has no needle; the lock probe and `drain_session` have needles and twelve
    mutants, run on three bash versions only (5.3.9, 5.0.17, 5.2.37).
21. **`drain_session` needs a `ps` that selects by session** (`ps -s`, procps-ng 4.0.4 here). A `ps` without it
    prints nothing, which reads as "drained"; the first needle then fails instead of passing silently (mutant TM12).
    The probe reads `/proc/<pid>/fd` and therefore sees only processes of the same user; another user's process
    holding the sandbox's `index.lock` is not a case the sandbox can produce.
22. **The review's alternative patch was not applied as written** (section 14): its Z check and membership tests
    are in the head already, its process-substitution loops were not taken. The two were compared with the review's
    own probes, under the `ulimit -f 0` emulation (not with read-only directories, item 2).
23. **Lane B's last run (5.2.37, run 3) did not finish:** the agent session that ran it was ended (weekly API limit)
    during the run. It is shown as not finished and not counted (section 10). On a5ee2ab4, `run_all.sh --quick`
    ran twice per bash (section 13).

## 16. Files in this directory

| Path | What it is |
|---|---|
| `README.md` | this document |
| `SHA256SUMS` | sha256 of every other file |
| `altpatch/*` (10 files) | section 14: the review's alternative patch against the head |
| `bash_sources.txt` | where each bash copy came from, with its sha256 |
| `compare/*` (5 files) | section 4 facts, produced by tools/bash_facts.sh |
| `compare/byte_identity.txt` | section 7 |
| `compare/caller_shell_compare_host.txt` | section 7, caller shell |
| `compare/patsub_amp_scan.txt` | section 15, item 15 |
| `compare/reset_facts.txt` | section 4, facts 9 and 10 |
| `f9/f9_search.sh`, `f9/f9_search.txt` | section 13 |
| `gate/*` (5 files) | section 9 |
| `inventory/inventory_counts.md` | the counts table of section 5 |
| `inventory/shenum_base.tsv`, `inventory/shenum_new.tsv` | the AST inventory rows (base and head) |
| `inventory/shenum_rebuild.txt` | offline rebuild of shenum, identical binary |
| `inventory/sigpipe_check_rebuild.txt` | the template build equals tests/install/test_sigpipe.sh |
| `inventory/sigscan_base.txt`, `inventory/sigscan_new.txt` | scanner findings (base: 49, head: 0) |
| `inventory/xcheck_base.txt`, `inventory/xcheck_new.txt` | cross-check of the two instruments |
| `kill/*` (11 files) | section 8 (tsv: one row per mutant; log: the same rows with the control run) |
| `landing/manifest_verify.txt` | run_full_suite.sh --verify-manifest on the fix commit |
| `landing/manifest_verify_base.txt` | run_full_suite.sh --verify-manifest on main bd0036bd alone |
| `landing/trial_merge.txt` | section 12 |
| `perf/perf_push_changed.txt` | section 11 |
| `runs/host_samples.tsv` | host samples of the sentinel, one per minute |
| `runs/lane_a.log`, `runs/lane_b.log`, `runs/lane_c.log` | lane logs (start, end, exit status of every run) |
| `runs/load.log` | host load samples |
| `runs/runall_5.2.37_r3.partial.log`, `runs/runall_per_suite_counts.txt` | run_all.sh results |
| `runs/sentinel.tsv` | the exit-3 sentinel beside lane B (section 10) |
| `runs/sigpipe_*` (21 files) | test_sigpipe.sh output, one file per bash and run |
| `runs/superseded_58815d75/*` (73 files) | the runs on 58815d75, stopped and not counted (section 10) |
| `short/short_*` (30 files) | short-suite output, one file per suite, bash and run |
| `tools/*` (33 files) | the scripts that produced this directory (renamed so that the suite census does not count them as tests) |
| `tr8/gate_no_push_on_the_change.txt` | CM-INSTALLER-NO-PUSH-NO-FORCE on the working tree with the change |
| `tr8/mutants_*` (6 files) | section 13: mutants TM1 to TM12 (tsv: one row per mutant; log: with the control run) |
| `tr8/needles_*` (9 files) | section 13: the control needles, three runs per bash |
| `tr8/other_agent/*` (6 files) | the other agent's proposal and trials (unchanged except paths) |
| `tr8/pgid_before_setsid_probe.txt` | section 13: could the loop read the test's own group as the installer's |
| `tr8/red_group_drain_misses_own_group_member.txt`, `tr8/red_proposed_probe_pipe_form.txt` | section 13: the RED runs on the proposal (its lock probe, its group drain) |
| `tr8/runs/*` (10 files) | section 13: test_round8.sh alone and run_all.sh --quick on the test_round8 commit |
| `tr8/shellcheck_warnings_after.txt`, `tr8/shellcheck_warnings_before.txt` | shellcheck warnings of test_round8.sh before and after the change (the same set) |
