# codegraph_mcp_preflight.sh — guide

**Revision:** 2
**Last modified:** 2026-10-27T10:05:00Z

Source: `constitution/scripts/codegraph/codegraph_mcp_preflight.sh` (255 lines) and, since Revision 2, the launch-target
classifier `constitution/scripts/codegraph/codegraph_launch_class.py` (see [codegraph_launch_class](codegraph_launch_class.md)).
Tests: `constitution/scripts/codegraph/tests/test_codegraph_mcp_preflight.sh` (cases F1-F18),
`tests/test_codegraph_launch_class.py` (91 table cases) and the mutation harness
`tests/test_codegraph_mcp_preflight_mutations.sh` (mutants Y1-Y23, table in `tests/test_codegraph_mcp_preflight_mutate.py`).
Citations below are `codegraph_mcp_preflight.sh:<line>` unless another file is named.

## Overview

A pre-flight check that answers, with evidence and without touching the project's index, "can an agent safely use
the CodeGraph MCP server here?" (header, lines 5-20). It runs seven numbered checks and prints one line per check:

| Id | What it checks | Source |
|---|---|---|
| P1 | `.mcp.json` declares a `codegraph` server whose command is the sanctioned `codegraph_mcp.sh` (executable, with `fk_index_patch.py` beside it) and whose arguments are only `serve --mcp [--project DIR]` | lines 68-101 |
| P2 | No OTHER `.mcp.json` server entry launches the stock `codegraph` — judged by what the entry LAUNCHES (see the classifier guide), not by the basename of `command` | lines 102-112 |
| P3 | Optional settings files carry no stock-codegraph hook or `mcpServers` entry, both classified by launch target. Runs only when `--settings` is given | lines 115-149 |
| P7 | The user-scope configs `$HOME/.claude.json` and `$CLAUDE_CONFIG_DIR/.claude.json` launch no stock codegraph (top-level `mcpServers` and every `projects.<path>.mcpServers`), any server named `codegraph` there is the sanctioned wrapper, and a present file that is not valid JSON is a FAIL | lines 151-210 |
| P4 | The wrapper resolves a receipt-valid `mcpro1` runner for a throwaway fixture (may build it into the runner cache) | lines 224-230 |
| P5 | A fixture query is answered end to end through the wrapper AND the server holds the database read-only (descriptor modes read from `/proc` by the probe) | lines 231-240 |
| P6 | The real project has an index; a live writer on it is a WARN, any other refusal is a FAIL | lines 243-253 |

Output order is P1, P2, [P3], P7, P4, P5, P6, then `SUMMARY` (P7 is printed before P4 because the user-scope scan runs before
the fixture is built; the numbering is by check, not by position).

The real project is only ever `stat`-ed and passed to `codegraph_mcp.sh --dry-run`, which reads `/proc` and the lock
file but never opens the database and never runs `codegraph` (header lines 19-20). The fixture for P4/P5 is created
in a temporary directory with the pristine package (lines 213-222). P7 reads the two user-scope files read-only and never
echoes an argument or environment value (see Edge cases).

## Prerequisites

- `bash`, `python3` (standard library only; the embedded programs run as `python3 -I -B`), `git`, `sed`, `mktemp`.
  The header also lists "a pristine codegraph 1.6.x package" (line 26): the fixture is indexed with
  `$HELIX_CODEGRAPH_SRC/bin/codegraph init` (lines 213-222).
- Files beside the script: `codegraph_launch_class.py` (imported by P2, P3, P7 — a missing file makes those three Python
  programs fail at import), `codegraph_mcp.sh`, `codegraph_mcp_probe.py`, `fk_index_patch.py` (lines 47, 92, 213).
- Linux `/proc` (through the wrapper and the probe).
- `--project` must be an existing directory (line 45).

## Usage

```sh
codegraph_mcp_preflight.sh [--project DIR] [--mcp-json FILE] [--settings FILE]...
codegraph_mcp_preflight.sh -h | --help
```

| Argument | Meaning | Source |
|---|---|---|
| `--project DIR` | Project to check. Default `$PWD`. Must exist, otherwise exit 2 (`project directory not found`) | lines 35, 38, 45 |
| `--mcp-json FILE` | `.mcp.json` to inspect. Default `<project>/.mcp.json`. The path is opened as given (relative to the current directory, not to the project) | lines 39, 46 |
| `--settings FILE` | A settings file for P3. Repeatable. Without it P3 does not run and no `P3` line is printed | lines 40, 115 |
| `-h`, `--help` | Print lines 2-32 of the script (the header block, 31 lines) and exit 0 | line 41 |
| anything else | `unknown argument: <arg>` on stderr, exit 2. A flag without its value prints `usage: --<flag> ...` and exits 2 | lines 38-42 |

### Examples

All rows ran on 2026-10-27 (host `/mnt/track1/atmosphere-t1`, scratch `TMPDIR`); evidence under
`qa-results/codegraph_followup_20261027/`.

| # | Command | Status |
|---|---|---|
| 1 | `codegraph_mcp_preflight.sh --help` | VERIFIED (ran; printed 31 lines, the last being the closing `# ====` rule of the header; exit 0) |
| 2 | `--bogus`, `--settings` with no value, `--project /nonexistent_dir_x` | VERIFIED (ran; stderr `unknown argument: --bogus`, `usage: --settings FILE`, `project directory not found`; exit 2 each) |
| 3 | `codegraph_mcp_preflight.sh --project /mnt/track1/atmosphere-t1 --settings .claude/settings.local.json` (the real project; evidence file `11_preflight_real_project.txt`) | VERIFIED (ran; `P1 PASS` -> `.../constitution/scripts/codegraph/codegraph_mcp.sh`, `P2 PASS` (0 other entries), `P3 PASS`, `P7 FAIL /home/milos/.claude.json: mcpServers server 'codegraph' launches the stock codegraph, which opens the index for writing (command word 'codegraph')`, `P4 PASS ... (1.6.2-mcpro1)`, `P5 PASS`, `P6 PASS index present, no live writer, runner valid`, `SUMMARY fail=1 warn=0`, exit 1) |
| 4 | The user-scope shapes of P7 (evidence file `12_p7_shapes.txt`, fixture `HOME` per row, `CLAUDE_CONFIG_DIR` empty, fixture build disabled with `HELIX_CODEGRAPH_FIXTURE_BIN=/bin/false` so each run is fast) | VERIFIED (ran; see the table under Edge cases) |
| 5 | Correct wiring on a throwaway fixture project, empty project, live writer, settings hooks, runner variants | VERIFIED by `tests/test_codegraph_mcp_preflight.sh` cases F1-F12 (`09_preflight_F1-F18_FULL_GREEN.txt`: `SUMMARY cases=18 failed=0`) |

## Inputs

| Input | Effect | Source |
|---|---|---|
| `HELIX_CODEGRAPH_SRC` | Pristine package used for the fixture. Default: `python3 -c 'import fk_index_patch as m; print(m.default_src())'` run from the script directory | line 213 |
| `HELIX_CODEGRAPH_FIXTURE_BIN` | Binary used to `init` the fixture. Default `$SRC/bin/codegraph`. Header: "tests: the fixture writer" | lines 22, 214, 218 |
| `HELIX_CODEGRAPH_RUNNER_DIR` | Runner cache used by the wrapper (see the wrapper's guide) | header line 22 |
| `HELIX_CODEGRAPH_MCP_RUNNER` | Read by the wrapper the script calls; pins a runner (tests F6/F10/F11 use it) | via `codegraph_mcp.sh:55` |
| `HOME`, `CLAUDE_CONFIG_DIR` | P7 reads `$HOME/.claude.json` and `$CLAUDE_CONFIG_DIR/.claude.json` (each only when set and present; two paths that resolve to one file count once). Unset or empty = not scanned | lines 160-167 |
| `TMPDIR` | Where the temp directory `cg_mcp_pf.XXXXXX` is created | line 50 |

## Outputs

- stdout: one line per check, `PREFLIGHT <id> <PASS|FAIL|WARN> <text>` (line 49), in the order P1, P2, [P3], P7, P4,
  P5, P6, then `SUMMARY fail=<N> warn=<M>` (line 254).
- stderr: usage and argument errors only.

## Exit codes

| Code | Meaning | Source |
|---|---|---|
| 0 | No check failed (`FAILS == 0`); WARN lines do not affect the code | lines 49, 255 |
| 1 | At least one `FAIL` line | line 255 |
| 2 | Usage: unknown argument, missing flag value, or project directory not found | lines 38-42, 45 |

## Edge cases

- **`.mcp.json` problems fail P1 and P2 together**: missing file, invalid JSON, or no `mcpServers` object print a
  `P1 FAIL` and a `P2 FAIL` and skip the rest of the file check (lines 59-67).
- **How P1 finds the wrapper:** if the command's basename is `bash`, `sh` or `env` and there are arguments, the first
  argument is treated as the script and the rest as its arguments; a relative script path is joined to the project
  directory; the path is resolved with `realpath` (lines 68-77, 87). This is why this repository's own entry
  (`command: bash`, `args: [constitution/scripts/codegraph/codegraph_mcp.sh]`) passes (example 3). P1 itself still looks only at
  the entry NAMED `codegraph`; every other entry is P2's.
- **P1 allows only `serve`, `--mcp`, `--project DIR`, `--project=DIR`** as arguments; anything else is reported as
  `argument 'x' is not allowed` (lines 94-100; test F4 with `index`). The `--project` value is not checked.
- **P1 reports at most one of three wrapper problems** (wrong basename, not executable, no `fk_index_patch.py`
  beside it) because they are an `if/elif` chain (lines 88-93); argument problems are added to that reason.
- **P2 judges what an entry LAUNCHES, not its name** (changed in Revision 2; the old basename comparison missed five
  shapes, test F14 recorded `res=ppppp`). Every other server entry goes through `codegraph_launch_class.classify(command, args, project)`;
  an entry is flagged only when the classifier returns `stock`. Flagged shapes include `node .../dist/bin/codegraph.js`,
  `bash -c "codegraph serve --mcp"`, `npx @colbymchenry/codegraph`, `env X=1 codegraph ...` and a shell shim whose body
  execs codegraph. NOT flagged (false-positive guards, test F15): `grep codegraph`, `node codegraph-viewer.js`, a package such
  as `@other/codegraph-ui`, the sanctioned wrapper registered under a second name, a shim that never launches codegraph, a
  shim cycle. The detail text in the FAIL line is built only from file basenames and constants, so a secret passed as an
  argument cannot appear in it.
- **P3 only runs with `--settings`,** and looks at (a) every `command` value found anywhere under the file's `hooks` key,
  classified as a shell string (`classify_shell`) — so a hook that merely mentions `mcp__codegraph__codegraph_explore` in
  its MATCHER, or runs `echo codegraph`, is NOT flagged any more, while a hook running an absolute-path `codegraph` is
  (test F18); and (b) every `mcpServers` entry, classified by launch target like P2 (test F16). A nonexistent settings file is skipped silently and P3
  PASSes (line 132-133); an unparsable file is a P3 FAIL (line 134-135). **Behaviour change versus Revision 1:** the old P3
  flagged any hook string containing `codegraph` (case-insensitive) and not `codegraph_mcp`, including matcher strings.
- **P7 (new in Revision 2) reads the user-scope configs.** For each of `$HOME/.claude.json`, `$CLAUDE_CONFIG_DIR/.claude.json` that
  exists (`lexists`, de-duplicated by `realpath`): the top-level `mcpServers` (classified relative to the project) and every
  `projects.<path>.mcpServers` (classified relative to `<path>` when it is an absolute path, else the project). Each
  entry that is a JSON object is classified by launch target. Verdicts, measured on fixture `HOME` files
  (`12_p7_shapes.txt`):

  | Shape in `.claude.json` | P7 result |
  |---|---|
  | `{}` | PASS (1 file, 0 server entries) |
  | `codegraph` = `bash <abs>/codegraph_mcp.sh` (the wrapper) | PASS (1 file, 1 server entry) |
  | `codegraph` = `codegraph serve --mcp` with an `env` secret | FAIL `... server 'codegraph' launches the stock codegraph ... (command word 'codegraph')`; the secret string does not appear in the output (0 occurrences) |
  | server `viewer` = `bash -c "exec codegraph serve --mcp"` | FAIL `... server 'viewer' ... (bash -c string: command word 'codegraph')` |
  | `projects["/some/where"].mcpServers.cg` = `npx -y @colbymchenry/codegraph ...` | FAIL `projects[/some/where].mcpServers server 'cg' ... (npx package @colbymchenry/codegraph)` |
  | `codegraph` = `{type: http, url: ...}` (no command) | FAIL `... is not the sanctioned codegraph_mcp.sh wrapper (no launchable command)` |
  | `codegraph` = `"junk"` (not an object) | FAIL `... is not the sanctioned codegraph_mcp.sh wrapper (entry is not an object)` |
  | `other` = `"junk"`, `x` = `5`, `projects["/p"]` = `"junk"` | PASS (2 server entries inspected; the non-object project value is skipped; no traceback) |
  | truncated JSON | FAIL `<file> is not valid JSON (Expecting property name enclosed in double quotes at line 1 column 17) — it cannot be shown clean` |
  | `fs` = `node server.js` | PASS |

  No scanned file present (neither variable set to a directory holding one) prints `P7 PASS no user-scope .claude.json present
  (HOME and CLAUDE_CONFIG_DIR checked) — nothing to inspect`. A file that cannot be read for another reason is
  `P7 FAIL <file> is unreadable (<ExceptionName>) — it cannot be shown clean`.
- **P7 sees only the two files above.** A session started with a different `CLAUDE_CONFIG_DIR` has its own `.claude.json`, which
  this run does not read unless that variable points at it. Measured 2026-10-27 across all `~/.claude*` directories of this host:
  exactly one stock `codegraph` entry exists, in `/home/milos/.claude.json`; none in the other alias directories. A future entry
  in another alias directory would not be seen by a run that does not point `CLAUDE_CONFIG_DIR` there.
- **P4/P5 need a fixture.** If `$FIXBIN` is not executable or `init` fails, only `P5 FAIL fixture could not be
  created with <bin> (init failed: ...)` is printed and P4 is not printed (lines 218-222). If the package cannot be
  found, `SRC` is empty and `FIXBIN` becomes `/bin/codegraph` (lines 213-214).
- **P4 passes only if the wrapper's dry-run exits 0 and `runner_key` ends in `-mcpro1`** (lines 224-228). A
  receipt-valid runner is not proof of working: P5 is the check that catches a runner that passes P4 but launches
  the stock writer or fails its session (tests F10, F11).
- **P5 requires every observed database descriptor to be read-only and at least one to exist** (`modes and all(m == "r")`,
  lines 236-237).
- **P6 with a live writer is a WARN (exit stays 0) by design** (line 248); the wrapper's stderr is cut to 220 bytes
  (line 248), and any other wrapper exit is a FAIL (line 249).
- **Temp files.** The script removes its own directory on exit (line 50, checked: no `cg_mcp_pf.*` left over). It does
  NOT remove the empty `cg_mcp_err.XXXXXX` file that the wrapper leaves behind when it starts the server (Finding 3).

## Findings (things in the tool or its tests that do not match)

**Resolved in Revision 2 (2026-10-27):**

1. **RESOLVED — the test file expected features the source did not have.** `tests/test_codegraph_mcp_preflight.sh` asserted a
   P7 check (case F13) and P2 classification "by the RESOLVED launch target" (case F14); neither existed (the string `P7` occurred
   only in the test file, P2 compared basenames). Root cause: the two features were specified in the tests by the commit that added
   the script (`b3a73cf`) and never implemented — the basename test was the only stock detection anywhere. Fixed at the cause:
   the shared classifier `codegraph_launch_class.py` (P2, P3, P7), a new P7 block, and tests F15-F18 for the false-positive and
   edge-case sides. RED/GREEN evidence: the new cases against the PREVIOUS (HEAD) script fail F13, F14, F16, F17, F18 and pass F15
   (`06_RED_new_cases_vs_HEAD_preflight.txt`); the current script passes all 18 (`09_preflight_F1-F18_FULL_GREEN.txt`:
   `SUMMARY cases=18 failed=0`, exit 0).
2. **RESOLVED — the mutation harness could not run.** It requires the baseline suite to pass first
   (`test_codegraph_mcp_preflight_mutations.sh`); with F13/F14 failing it stopped with `BASELINE FAILED (rc=1)` and applied no
   mutant. After Finding 1 the baseline passes; the harness now carries 23 mutants and all are killed
   (`08_preflight_mutations_run1.txt`: `SUMMARY mutants=23 killed=23 survivors=0`, exit 0).
4. **RESOLVED — `--help` printed code.** The header block ends at line 32; `--help` used to print lines 2-26 and so ended with four
   lines of shell code. The range is now `sed -n '2,32p'` (line 41); measured: 31 lines, the last is the closing `# ====` rule.

**Still open:**

3. **F7 depends on path length (unchanged code, not re-derived).** P6 cuts the wrapper's stderr with `head -c 220` (bytes, line 248); the
   wrapper's message contains an em dash (`—`, three bytes) right after the database path, so with a 168- or 169-byte path the
   cut can land inside that character and the test's `grep` reports `binary file matches`. The arithmetic and the 168-byte
   observation are from Revision 1; line 248 is unchanged, and F7 passed at the scratch `TMPDIR` length used on 2026-10-27
   (`09_preflight_F1-F18_FULL_GREEN.txt`). Whether the 169-byte case fails was never run.
5. **Undocumented side effect (header omission).** The header's "Side effects" (line 25) omits the leftover empty `cg_mcp_err.*` file
   (cause in `codegraph_mcp.sh:54,140`: a trap-removed file whose process is replaced by `exec`). Re-measured 2026-10-27: 351 such empty files had
   accumulated in the scratch `TMPDIR` after the test and mutation runs of this session, and a single run of example 3 created one
   more (timestamp 14:53:47 +05). Not changed here.
6. **P7 and the other user-scope scans share the static boundary.** The classifier is a static reader (see its guide); a launch
   assembled at run time, a compiled launcher not named codegraph, a script of 256 KiB or more or a non-shell script is
   classified by name only. P5 is the runtime proof for the project's own server; there is no runtime proof for entries in other
   files. The related `H7` check in `codegraph_mcp_health.py` (`check_user_scope()`) is a separate implementation that was NOT
   given the classifier: it matches a regex over the joined argv, skips invalid JSON silently and prints the first three argv
   words; see [codegraph_mcp_health](codegraph_mcp_health.md), Honest boundaries.

## Internal behaviour

1. Parse arguments; resolve the project; default `.mcp.json` (lines 35-47).
2. Create the temp directory and its EXIT trap (line 50).
3. P1/P2: an embedded Python program parses the JSON (never greps it), imports the classifier and prints one line per check; the
   shell reads them through a process substitution so the FAIL/WARN counters survive (a piped `while` would lose them,
   comment on line 114).
4. P3 (only with `--settings`): a second embedded Python program (lines 116-147).
5. P7: a third embedded Python program over the user-scope files (lines 154-209).
6. Build the fixture project and index it with the pristine package's `init -y` (lines 213-222).
7. P4: `codegraph_mcp.sh --project <fixture> --dry-run`; P5: `codegraph_mcp_probe.py --bin <wrapper> --project
   <fixture> --query compute_total` and a Python assertion over its JSON (lines 223-241).
8. P6: `stat` the real database; if present, `codegraph_mcp.sh --project <project> --dry-run` (lines 244-253).
9. Print `SUMMARY` and exit `0` iff no FAIL (lines 254-255).

## Related

| File | Relation |
|---|---|
| [codegraph_launch_class](codegraph_launch_class.md) | The classifier P2, P3 and P7 call; defines what "launches the stock codegraph" means and what it cannot see |
| [codegraph_mcp](codegraph_mcp.md) | The wrapper this script exercises (P4, P5, P6) |
| [codegraph_mcp_probe](codegraph_mcp_probe.md) | MCP client that produces the JSON P5 asserts on |
| [codegraph_mcp_health](codegraph_mcp_health.md) | Live health check (H1-H9) with its own user-scope check H7; carries the measured stock-daemon mitigation table |
| `fk_index_patch.py` | Builds/finds the `mcpro1` runner; also gives the default package source (line 213) |
| `tests/test_codegraph_mcp_preflight.sh` | Cases F1-F18 |
| `tests/test_codegraph_launch_class.py` | 91 classifier table cases |
| `tests/test_codegraph_mcp_preflight_mutations.sh`, `..._mutate.py` | Mutants Y1-Y23 against a copy of the script and the classifier |
| [owed_report](owed_report.md) | Reports whether this tool has tests and a guide |

## Last verified

2026-10-27T09:55:00Z. Commands run and results (captured under `qa-results/codegraph_followup_20261027/`):

- `bash tests/test_codegraph_mcp_preflight.sh`: `SUMMARY cases=18 failed=0`, exit 0 (`09_preflight_F1-F18_FULL_GREEN.txt`; F13-F18 fail on the Revision-1 script, `06_RED_new_cases_vs_HEAD_preflight.txt`).
- `python3 tests/test_codegraph_launch_class.py`: `SUMMARY cases=91 failed=0`, exit 0 (`09b_classifier_unit_test_final.txt`).
- `bash tests/test_codegraph_mcp_preflight_mutations.sh`: baseline 18 cases PASS, `SUMMARY mutants=23 killed=23 survivors=0`, exit 0 (`08_preflight_mutations_run1.txt`).
- Direct runs: `--help`, three usage errors, the real project with `--settings` (P7 FAIL on the real `/home/milos/.claude.json`, everything else PASS, `11_preflight_real_project.txt`) and ten P7 shapes (`12_p7_shapes.txt`).

Not verified: the 169-byte path case of Finding 3; behaviour on a host whose `HOME` or `CLAUDE_CONFIG_DIR` holds a `.claude.json` over 256 KiB
is not special-cased (the file is read whole by `json.loads`); a runtime proof for any user-scope entry (there is none by design).
