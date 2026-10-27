# codegraph_launch_class.py — guide

**Revision:** 1
**Last modified:** 2026-10-27T10:05:00Z

Source: `constitution/scripts/codegraph/codegraph_launch_class.py` (476 lines, Python 3 standard library only).
Tests: `constitution/scripts/codegraph/tests/test_codegraph_launch_class.py` (91 table cases) and, through the preflight,
`tests/test_codegraph_mcp_preflight.sh` cases F13-F18; mutants Y12-Y23 of `tests/test_codegraph_mcp_preflight_mutations.sh`
target this file. Citations below are `codegraph_launch_class.py:<line>`.

## Overview

Decides, from the `command` and `args` of an MCP server entry (a `.mcp.json`, a settings file, a user-scope `.claude.json`), what
the entry LAUNCHES (header, lines 5-12). It returns one of three kinds:

| Kind | Meaning |
|---|---|
| `stock` | The stock `@colbymchenry/codegraph`: it opens the index database for writing, runs a file watcher and spawns a daemon, so it is not read-only (measured stall and watchdog kills, see [codegraph_mcp_health](codegraph_mcp_health.md)) |
| `wrapper` | The sanctioned read-only wrapper `codegraph_mcp.sh` with its tooling (`fk_index_patch.py`) beside it |
| `other` | Anything else, including every entry that merely MENTIONS codegraph |

The decision is made on the resolved launch target. It is never a basename test of `command` alone (that misses
`node .../codegraph.js`, `bash -c "codegraph ..."`, `npx @colbymchenry/codegraph`, `env X=1 codegraph ...` and a shim script that
execs codegraph — measured by cases F13/F14 of the preflight test, which were red before this file existed) and never a substring
(a false refusal is a FAIL-bluff, constitution §11.4.201(1)). It is called by `codegraph_mcp_preflight.sh` for P2, P3 and P7.

## Prerequisites

- `python3` with the standard library only (`json`, `os`, `re`, `shlex`, `shutil`, `stat`, `sys`; lines 34-40).
- Read access to the launch target (the file is read, never executed) and, for a bare command name, `PATH`.

## Usage

```sh
python3 codegraph_launch_class.py [--base-dir DIR] -- COMMAND [ARG...]      # prints "<kind>\t<detail>"
```

As a library (what the preflight does):

```python
import codegraph_launch_class as L
kind, detail = L.classify(command, args, base_dir)        # an MCP server entry
kind, detail = L.classify_shell(text, base_dir)           # a shell string, e.g. a settings-file hook `command`
```

| Function | Meaning | Source |
|---|---|---|
| `classify(command, args, base_dir=".")` | Entry classification. `command` must be a non-empty string and `args` a list of strings (or `None`), else `("other", "no launchable command")` | lines 447-455 |
| `classify_shell(text, base_dir=".")` | Classification of the text a shell would run; empty or non-string input gives `("other", "no launchable command")` | lines 439-444 |
| `split_commands(text)` | Quote- and comment-aware split of shell text into simple commands (separators `; & | ( )` and newline; here-document bodies skipped; redirections dropped; no expansion) | lines 83-189 |
| CLI | `--base-dir DIR` (default `.`), then `--`, then the command and its arguments. No command: usage on stderr, exit 2; otherwise one line `kind<TAB>detail`, exit 0 | lines 458-472 |

`base_dir` is the directory relative script paths resolve against; the preflight passes the project directory (for a
`projects.<path>.mcpServers` entry of a user-scope file, `<path>` when it is absolute).

### Examples

All ran on 2026-10-27 (evidence `qa-results/codegraph_followup_20261027/13_classifier_cli_examples.txt`).

| # | Command line after `--` | Output | Status |
|---|---|---|---|
| 1 | `codegraph serve --mcp` | `stock	command word 'codegraph'` | VERIFIED (ran; exit 0) |
| 2 | `env FOO=1 codegraph serve --mcp` | `stock	command word 'codegraph'` | VERIFIED |
| 3 | `timeout 5 codegraph serve` | `stock	command word 'codegraph'` | VERIFIED |
| 4 | `bash -c 'exec codegraph serve --mcp'` | `stock	bash -c string: command word 'codegraph'` | VERIFIED |
| 5 | `npx -y @colbymchenry/codegraph serve --mcp` | `stock	npx package @colbymchenry/codegraph` | VERIFIED |
| 6 | `bun x @colbymchenry/codegraph serve --mcp` | `stock	npx package @colbymchenry/codegraph` | VERIFIED |
| 7 | `node dist/bin/codegraph.js serve --mcp` (file not on disk) | `stock	node script: names codegraph.js (target file not present)` | VERIFIED |
| 8 | `bash <repo>/constitution/scripts/codegraph/codegraph_mcp.sh serve --mcp` | `wrapper	sanctioned codegraph_mcp.sh` | VERIFIED |
| 9 | `bash -c 'echo codegraph'` | `other	no codegraph launch target found` | VERIFIED |
| 10 | `bash -c 'command -v codegraph'` | `other	no codegraph launch target found` | VERIFIED |
| 11 | `node codegraph-viewer.js` | `other	no codegraph launch target found` | VERIFIED |
| 12 | `grep codegraph notes.txt` | `other	no codegraph launch target found` | VERIFIED |
| 13 | `bash` (no script) | `other	no codegraph launch target found` | VERIFIED |
| 14 | no arguments at all | usage line on stderr, exit 2 | VERIFIED (ran; `rc=2`) |

## What it resolves

| Shape | Handling | Source |
|---|---|---|
| Direct name or path whose basename is `codegraph` or `codegraph.js`, and a symlink to one | `stock` | lines 43, 294-295, 389-390 |
| Any file inside a package whose nearest `package.json` has name `@colbymchenry/codegraph` | `stock` (looks up to 8 directories, a file of at most 1 MiB) | lines 244-259, 296-297 |
| A launch target that is NOT on disk but is named `codegraph`/`codegraph.js` | `stock` ("names X (target file not present)"): the entry launches stock codegraph the moment the file appears, so absent is not safe | lines 283-286 |
| Transparent wrappers `env`, `exec`, `command`, `nohup`, `time`, `nice`, `ionice`, `setsid`, `stdbuf`, `timeout`, `sudo` | Peeled: their options (value-taking ones from a table), `VAR=value` words (env) and `timeout`'s duration are skipped and the rest is classified; peeling strictly shrinks the argv so it terminates, and is not depth-limited (test S1A: eight nested `env`) | lines 53-65, 192-235, 382-385 |
| `env -S 'string'`, `env --split-string=...` | The string is split with `shlex` into the command and its arguments | lines 200-213 |
| `command -v NAME` / `command -V` | A lookup, launches nothing: `other` | lines 198-199 |
| Shells `sh bash dash zsh ash ksh` | `-c STRING` is scanned as shell text; otherwise the first non-option argument is a script file read as shell text | lines 391-411 |
| `node`/`nodejs`/`bun` (with optional version suffix such as `node20`) | Value-taking options (`-r`, `--require`, `--import`, `--loader`, ...) skipped; `-e/-p` is `other`; otherwise the script file is classified (a file that is not codegraph and is read as a non-shell is `other`) | lines 47, 51, 416-434 |
| `npx`, `pnpx`, `bunx`, `npm exec|x`, `pnpm dlx|exec`, `yarn dlx|exec`, `bun x` | Package specs (`-p`, `--package[=]`, the first positional, `-c STRING` scanned as shell text) are compared with `@colbymchenry/codegraph` and the bare name `codegraph` (version suffix stripped); `bun x` is handled before the node/bun branch | lines 48-50, 338-373, 412-415 |
| A file (the command itself or a script argument) that starts with a shell shebang (`#!/bin/sh`, `#!/usr/bin/env bash`, ...), or is run through a shell | Read (at most 256 KiB) and scanned as shell text; a stock hit is reported as `shim script NAME -> ...` | lines 262-275, 278-312 |
| Shell text | Each simple command is classified after skipping leading keywords (`if then else elif do while until { } !`) and `VAR=value` assignments | lines 66, 315-328 |

Termination: a visited-file cycle guard (`ctx["seen"]`, line 290) and a depth limit of 12 nested shell/file/`npx -c` hops
(`MAX_DEPTH`, lines 67, 379); the unit test builds a shim cycle and checks that it ends as `other` (O11).

## What it cannot see (static boundary, constitution §11.4.6)

Classified by name only, i.e. usually `other` (header lines 21-30): a compiled launcher whose name is not codegraph; a script of 256 KiB or
more; a script in a non-shell language (python, perl, ...); a launch assembled at run time (variables, `eval`, command
substitution results); an interpreter option that takes a separate value and is not in the tables (the value would be taken
for the script). The threat boundary is ACCIDENTAL misconfiguration, not an adversary assembling a launch to evade a static
reader. The runtime proof that the project's own server is read-only is preflight check P5; there is no runtime proof for
entries in other files. A bare `npx codegraph` is classified `stock` as the conservative default; which npm package that name
would resolve to is UNCONFIRMED (test S4B).

## Outputs and secret hygiene

`detail` is built ONLY from file basenames and constants (`command word 'codegraph'`, `npx package @colbymchenry/codegraph`,
`shim script NAME -> ...`), never from argument or environment values, so a token passed as an argument or `VAR=value` cannot reach a
report (header lines 16-17). Test D01 asserts that, for entries carrying secret-looking arguments and environment values, the detail never contains them while
each is still classified `stock`; the P7 run in `12_p7_shapes.txt` shows the same end to end (0 occurrences of the secret).

## Edge cases

- Malformed input never raises: a non-string, `None` or empty command, a non-list `args`, an `args` list holding a non-string, a `None` `args` (treated as empty), an unbalanced quote in a `-c` string (the parser stops at the quote as bash would refuse the line), `bash -c` with no string, `env`/`timeout` with nothing to run, a directory as the command (tests M01-M08, O15-O17).
- Here-document bodies, `<<<` here-strings and comments are data, not commands; a stock launch AFTER a here-document is still found (tests O0B, O0C, S27, and F18 through the preflight).
- A shim whose body only looks codegraph up (`command -v`, `type`, `which`) or echoes the word is `other` (O0F, O01-O07); a shim that execs another shim that execs codegraph is `stock` (S52).
- A file larger than 256 KiB is not read and is `other` (O13); a non-shell script (python) is not read as shell (O12).
- `codegraph_mcp.sh` is the wrapper only when `fk_index_patch.py` is in its directory (line 298; test W04); a lone copy is `other`.
- A relative path resolves against `base_dir`; a bare command name resolves through `PATH`; a name that resolves to nothing is `other` unless it is named `codegraph`/`codegraph.js` (lines 238-241, 283-287).

## Exit codes (CLI)

| Code | Meaning |
|---|---|
| 0 | A classification line was printed |
| 2 | Usage: no command after `--`, or `--base-dir` without a value |

## Tests and mutation coverage

`test_codegraph_launch_class.py` is a table of 91 cases (ids by family: S01-S52 stock shapes (49), W01-W04 wrapper, O01-O17 and O0B-O0F other (23), M01-M08 malformed input,
H01-H04 hook strings through `classify_shell`, D01 secret hygiene, C01-C02 CLI). The paired mutants Y12-Y23 each reopen one hole in a COPY (substring
detection, no shell `-c`, no wrapper peeling, no node-script reading, no package-runner handling, no shim reading, no
termination guards, no here-document/comment skipping, no not-on-disk `codegraph.js` rule, no genuine-wrapper recognition) and the
named preflight cases must go red; all 23 mutants Y1-Y23 were killed (`SUMMARY mutants=23 killed=23 survivors=0`).

## Related

| File | Relation |
|---|---|
| [codegraph_mcp_preflight](codegraph_mcp_preflight.md) | The only caller (P2, P3, P7) |
| [codegraph_mcp](codegraph_mcp.md) | The wrapper this classifier recognises as `wrapper` |
| [codegraph_mcp_health](codegraph_mcp_health.md) | Has its own user-scope check `H7` that does NOT use this classifier (open, see its Honest boundaries) |
| `tests/test_codegraph_launch_class.py` | 91 table cases |

## Last verified

2026-10-27T09:55:00Z. `python3 tests/test_codegraph_launch_class.py`: `SUMMARY cases=91 failed=0`, exit 0 (`qa-results/codegraph_followup_20261027/09b_classifier_unit_test_final.txt`);
the 14 CLI examples above ran (`13_classifier_cli_examples.txt`); mutation run `08_preflight_mutations_run1.txt`: 23 of 23 killed.
Not measured: statement or branch coverage of the module; behaviour on a launch shape outside the tables (by design `other`).
