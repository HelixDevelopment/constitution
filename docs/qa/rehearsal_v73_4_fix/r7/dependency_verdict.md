# Dependency-existence verdict: markdown-it-py (CON-423 r7, section 11.4.270)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-16 |
| Status | recorded (gate-logic, PROVISIONAL, section 11.4.290) |

## The dependency

Round 7 replaces the hand-written CommonMark line model of
`scripts/validation/check_provisional_verification_lines.py` with a real CommonMark parse:
markdown-it-py, preset `commonmark`. The checker reads which lines start a top-level
paragraph from the parser's token stream. It no longer models fences, HTML blocks, lists,
quotes and lazy continuation itself.

## Verdict on this host: VERIFIED

Evidence, captured on 2026-11-16 on the host that ran round 7:

| Check | Result |
|---|---|
| `dpkg -s python3-markdown-it` | `Status: install ok installed`, `Version: 3.0.0-3build1`, `Source: markdown-it-py`, homepage `https://github.com/executablebooks/markdown-it-py` |
| `python3 -I -c 'import markdown_it; print(markdown_it.__version__)'` | `3.0.0` from `/usr/lib/python3/dist-packages/markdown_it/__init__.py` (Python 3.14.4, isolated mode) |
| `mdurl` (its one runtime dependency) | `0.1.2`, importable under `-I` |
| sha256 of `markdown_it/__init__.py` | `f6fdef083ed7409ba37192d4d85d784fc3bcf0924ef77ad9694a0abbb728707f` |
| sha256 of `markdown_it/rules_block/html_block.py` | `c00f296f7e0bb59af50642004e018a4012065f98d034e930665f54184aaf6f93` |
| control needles | `tests/release/pvl_refreader.py --selftest` prints `REFREADER-SELFTEST mdit=ok pandoc=ok` |

Known behaviour of this version, measured:

- `<!-->` closes an HTML comment at once (CommonMark 0.31).
- The HTML block-name list has 62 names and does not include `search`.

The checker is not affected by either: it refuses every raw HTML block or inline tag
other than a complete comment.

## Elsewhere: UNKNOWN, fail closed

Whether the release environment has this package is UNKNOWN. The checker therefore fails
closed:

- markdown-it-py cannot be imported, or its version is not in `MDIT_TESTED = ("3.0.0",)`:
  - the command line prints `BLIND the CommonMark reader is unavailable: ...` and `VERDICT: BLIND` (exit 2);
  - `check_body` refuses every body with the same reason.
- Both paths are tested by `tests/release/pvl_mutate.py` (`api_r7`: the module with the version or the class
  replaced, and the command line with the import blocked). They are guarded by own mutants O54, O55, O56 and O63.

A new version must be tested before it is added to `MDIT_TESTED`. The test is a run of
`tests/release/test_provisional_verification_lines.sh` with that version, P8c and P8b included.

## The second reader

pandoc 3.11 (`/home/milosvasic/.local/bin/pandoc`, `-f commonmark` and `-f gfm`) renders
every body the checker accepts, in `tests/release/pvl_blockstate.py` and
`tests/release/pvl_lineend.py`. pandoc drops a lone CR, so it is blind to that member. A
control needle proves the blindness, and bodies with a lone CR are judged by markdown-it-py
only. pandoc is a test oracle, not a dependency of the checker.
