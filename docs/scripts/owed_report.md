# owed_report — guide

**Revision:** 1
**Last modified:** 2026-09-24T19:08:01Z

Source: `constitution/scripts/codegraph/owed_report.py` (130 lines).
Citations below are `owed_report.py:<line>`.

## Overview

A generated, read-only report of which governed indexing tools still lack
tests or a §11.4.18 companion guide (header lines 1-15). The constitution
states the rule "a tool lacking its own tests or its guide MUST NOT be pointed
at a live index" but does not list which tools currently lack them; a prose
list would go stale, so this tool derives the answer from the file tree on
every run (lines 4-7).

It is informational by default (exit 0) and becomes blocking only with
`--strict` (line 126).

## Prerequisites

- `python3`, standard library only (line 14, import on line 24).
- Read access to the constitution root (default: two directories above the
  script, line 88).

## Usage

```sh
python3 scripts/codegraph/owed_report.py                 # text table
python3 scripts/codegraph/owed_report.py --json          # machine-readable
python3 scripts/codegraph/owed_report.py --strict        # exit 1 if anything is owed
python3 scripts/codegraph/owed_report.py --root <constitution dir>
```

| Flag | Meaning | Source |
|---|---|---|
| `--root ROOT` | Constitution root to scan (default: two levels above the script). | lines 88-89 |
| `--json` | Print JSON instead of the table. | lines 90, 117-118 |
| `--strict` | Exit 1 when at least one tool owes something. | lines 91, 126 |
| `-h`, `--help` | argparse help (first line of the module docstring is the description). | line 87 |

## Inputs

The file tree under `--root` only (nothing on stdin, no environment
variables read in the source).

**Tool discovery** (lines 43-53, extensions line 26, skip list line 28):

| Kind | Files considered |
|---|---|
| `tool` | `scripts/codegraph/*.sh`, `*.py`, `*.js` |
| `runner_patch` | `scripts/codegraph/runner_patches/*.py`, except `__init__.py` and `common.py` |
| `tool` | `scripts/lumen/*.sh`, `*.py` |

Regular files only; the result is sorted by relative path (lines 38, 53).

**Test attribution** (lines 56-83, 100-107). A tool counts as tested when a
file under `<tooldir>/tests/` (recursive; `fixtures` and `__pycache__`
directories excluded, line 60; only `.sh .py .js .bats`, line 27; files that
fail to read as UTF-8 are skipped, lines 68-69) either:

1. is named `test_<stem>.<ext>`, `test_<stem>_mutate.<ext>`,
   `test_<stem>_mutations.<ext>` or `t_<stem>.<ext>` (`name_matches`, lines
   80-83); or
2. contains the tool's exact file name (runner patches: the stem, i.e. the
   patch id, line 106) bounded by non-identifier characters. The lookbehind
   also rejects `.` and `-` before the token, and a file name may not be
   followed by `.<alnum>` (e.g. `x.js.bak` does not match) (lines 74-77).

For runner patches the tests directory is `scripts/codegraph/tests`
(`tooldir` on line 50).

**Guide attribution** (lines 108-112): the first existing file among
`docs/scripts/<stem>.md` and `docs/scripts/<file name>.md`. Only file
existence is checked (`os.path.isfile`), not the guide's content.

## Outputs

`owed` for a row is `["tests"]` when no test matched, plus `["guide"]` when no
guide file exists (line 113).

Text mode (lines 119-125): a header row `TOOL KIND TESTS GUIDE`, one row per
tool with `yes`/`NO` columns and a trailing `  OWED: tests, guide` when
something is owed, then `owed: <n> of <total> tool(s)`.

`--json` (lines 117-118): `{"root", "tools", "owed_count"}` printed with
`indent=1, sort_keys=True`; each tool row has `path`, `kind`, `tested`,
`tests`, `guide`, `owed` (line 114).

## Exit codes

| Code | Meaning | Source |
|---|---|---|
| 0 | Report produced (also when tools owe something, unless `--strict`) | line 126 |
| 1 | `--strict` and at least one tool owes tests or a guide | line 126 |
| 2 | argparse usage error (unknown argument) | argparse default; confirmed below |
| 3 | REFUSED: root is not a directory, or no tool was discovered | lines 31-33, 94-98 |

Exit 3 on an empty scan is deliberate: a blind scan must never read as
"nothing owed" (header lines 11-12, refusal text on line 98).

## Edge cases

- **Test evidence is textual.** Attribution by tool name (rule 2 above)
  searches the whole text of each test file, so a mention in a comment also
  counts (line 107). The tool proves a reference exists, not that the test
  executes the tool.
- **Guide evidence is existence only** (line 110); an empty or stale guide
  file clears the `guide` debt.
- **Tests are cached per tool directory** (lines 100-105), so
  `scripts/codegraph` and its `runner_patches` share one scan.
- `scripts/lumen` tests are read from `scripts/lumen/tests` (line 45,
  `read_tests(root, tooldir)` on line 105).
- The test-file header (`tests/test_owed_report.py`, line 13) and this
  tool's own header (line 15) cite a `test_owed_report_mutations.sh`;
  UNCONFIRMED whether it exists: `ls tests | grep -i owed` on the verification
  date listed only `test_owed_report.py`.

## Internal behaviour

`main()` (line 86): parse flags, refuse on a missing root (lines 94-95),
`discover()` (line 96), refuse when nothing was found (lines 97-98), then per
tool compute the stem, load that directory's tests once, match, look up the
guide, and append a row (lines 100-114). Nothing is ever written; the only
file operations are `os.listdir`, `os.walk`, `os.path.isfile` and read-mode
`open`.

## Related

| Guide / file | Relation |
|---|---|
| [codegraph_guard](codegraph_guard.md) | Sibling gate in the same tool set |
| [codegraph_safe_helper](codegraph_safe_helper.md) | One of the tools this report covers |
| [codegraph_mcp_probe](codegraph_mcp_probe.md) | One of the tools this report covers |
| [resolve1](resolve1.md), [resolve2](resolve2.md), [lockfix1](lockfix1.md), [datafrag1](datafrag1.md) | Runner patches covered as kind `runner_patch` |
| [gen_lumenignore](gen_lumenignore.md), [lumen_verify](lumen_verify.md) | `scripts/lumen` tools covered |
| `scripts/codegraph/tests/test_owed_report.py` | The unit tests for this tool |

## Last verified

2026-09-24T19:08:01Z — ran from `scripts/codegraph`:

- `python3 tests/test_owed_report.py` twice: both `Ran 12 tests ... OK`, exit 0.
- `python3 owed_report.py --strict >/dev/null; echo $?` printed `1` (tools
  were still owed at that time).
- `python3 owed_report.py --root /nonexistent_zz` printed
  `REFUSED: root is not a directory: /nonexistent_zz`, exit 3.
- `python3 owed_report.py --root <empty dir>` printed the `no governed
  indexing tool discovered` refusal, exit 3.
- `python3 owed_report.py --bogus` exit 2.
- `python3 owed_report.py --json` top-level keys: `owed_count`, `root`,
  `tools`; row keys `guide kind owed path tested tests`.
