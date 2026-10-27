# status_summary_archive.py — Companion Guide

**Revision:** 2
**Last modified:** 2026-10-27T13:40:00Z

Source: `constitution/scripts/amendment_log/status_summary_archive.py`.
Test: `constitution/scripts/amendment_log/tests/test_status_summary_archive.sh`.
Independent proof helper: `constitution/scripts/amendment_log/tests/independent_lossless_rebuild.py` (imports nothing from the tool).

## Overview

Constitution §11.4.61(A) defines the `Status summary` row of a governance file's metadata table as a **one-line
current-state hook**. For months every amendment appended a paragraph to that single table cell instead, so the
preamble of `CLAUDE.md`, `AGENTS.md` and `Constitution.md` (everything before the first `## ` heading, which every
`head`, nested-memory load and quick read pays) grew to 133–159 KB each, 98 % of it that one cell
(measured 2026-10-27, ATM-1380). `QWEN.md` (133457 bytes) and `GEMINI.md` (114572 bytes) carried the same cell and were
moved the same way the same day (job 2): the five carriers are now 887 / 887 / 1505 / 883 / 914 bytes.

This tool moves the **older** entries of the cell into an on-demand Markdown archive, losslessly, and leaves in the
cell the newest entry plus one pointer sentence. Nothing is deleted; the archive is the verbatim text, one entry per
paragraph, newest first.

## Prerequisites

- `python3`, standard library only (run here with Python 3.13.13; other versions were not tested).
- A carrier whose preamble holds exactly one line starting `| Status summary | ` and ending ` |`.

## Usage

```sh
cd constitution

# Move everything after the newest entry out of the cell, bump Revision + Last modified, verify.
python3 scripts/amendment_log/status_summary_archive.py archive \
    --carrier CLAUDE.md --archive docs/amendment-log/status-summary-claude.md --bump-revision

# Show what would move, change nothing
python3 scripts/amendment_log/status_summary_archive.py archive --carrier CLAUDE.md \
    --archive docs/amendment-log/status-summary-claude.md --dry-run

# Re-check an existing pair (cell compact, pointer present, archive figures match its entries)
python3 scripts/amendment_log/status_summary_archive.py verify \
    --carrier CLAUDE.md --archive docs/amendment-log/status-summary-claude.md
```

The five repository archives are `docs/amendment-log/status-summary-{claude,agents,constitution,qwen,gemini}.md`
(`QWEN.md` -> `status-summary-qwen.md`, `GEMINI.md` -> `status-summary-gemini.md`; same command, nothing special-cased).

## What it does, step by step

1. `find_cell` — exactly one `| Status summary | … |` row in the preamble (it stops at the first `## `, so the
   look-alike example row that sits lower in `Constitution.md` is never touched); otherwise exit 2.
2. `split_body` — the **newest entry** is the text up to the first ` Prior: ` or ` Prior round: ` marker (the marker
   needs a leading space, so `(Prior: …)` inside parentheses is not a boundary). Everything after it is the moved
   text; an existing pointer sentence is cut off first.
3. `split_entries` — the moved text is split at every marker into entries and re-joined with one space; the result
   must equal the moved text byte for byte, otherwise exit 2 (a silent loss is impossible).
4. New entries are **prepended** to the entries already in the archive (newest first); the archive header figures
   (`Entries`, `Bytes of moved text`, `sha256 of moved text`) are recomputed.
5. The archive is written first, the carrier second (both atomically: temp file + rename), then `verify` runs.

## Independent proof helper

`tests/independent_lossless_rebuild.py` re-derives the lossless claim from bytes without importing the tool:

```sh
python3 -I scripts/amendment_log/tests/independent_lossless_rebuild.py <pre-change-carrier> <post-change-carrier> <archive>
python3 -I scripts/amendment_log/tests/independent_lossless_rebuild.py --figures-only <post-change-carrier> <archive>
```

Full mode: (1) the pre-change `| Status summary |` row equals `| Status summary | ` + kept text + one space + the archive
entries joined with one space + ` |`, byte for byte (bytes and sha256 printed); (2) every other line is unchanged except
`Revision` (+1 when it changed) and `Last modified`; (3) the archive header figures re-compute from its entries; (4) a
one-byte corruption of the middle entry is rejected by the very functions that decide (1) and (3). `--figures-only` runs
(3), (4) and the compact-cell check. Exit 0 all passed, 1 a check failed, 2 usage or format error. Measured 2026-10-27 on the
real move: QWEN.md row 133088 bytes sha256 `909426ee...0d18` rebuilt identical, GEMINI.md row 114174 bytes sha256
`c33c2b5e...cb48` rebuilt identical, both with Revision +1 and no other line changed.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | archive done (or already compact: nothing to move) / verify passed |
| 1 | `verify` failed; each failed check is printed (`cell is not compact`, `no pointer`, `pointer does not name the archive`, `archive missing`, `figure mismatch`, `entry does not start with a Prior marker`) |
| 2 | usage or format error: no or several Status summary rows, row not ending ` |`, empty newest entry, nothing older to archive, archive without entry markers, non-reversible split |

## Rotation workflow (when the cell grows again)

New amendments belong in `constitution/CHANGELOG.md`, not in the cell. If a release process still prepends a new
entry (`NEW. Prior: <old newest> Older entries of this cell …`), run `archive` again: the old newest entry moves to
the top of the archive, the new text stays as the one-line hook, `Revision` of the archive is incremented.

## Guards around it

- Parent repository `scripts/context_footprint.sh --check-budget` measures the preamble of the five files listed in its
  `PREAMBLE_FILES` array and fails when it exceeds the ratchet rows `constitution/<file>#preamble` in
  `docs/context/context_budget.conf` (CLAUDE / AGENTS / Constitution 1000 / 1000 / 1700 bytes after the 2026-10-27 move,
  was 140000 / 133300 / 157600; QWEN / GEMINI 1000 / 1000, measured 883 / 914). A row in the conf is DEAD unless the
  file is also in `PREAMBLE_FILES`: the array decides what is measured (the parent test proves it with a root where only
  the QWEN, or only the GEMINI, preamble grows).
- Parent test `scripts/testing/test_context_footprint_preamble.sh` (64 checks) proves the ratchet fails on a grown
  preamble and on a reverted fix, that `verify` fails on a corrupted, pointer-less or re-inlined cell, that the archive
  figures re-compute independently, and that each of the five carriers is covered (per-file mutants, only-QWEN and
  only-GEMINI growth roots).
- This tool's own test (39 checks) is listed above: 16 on a synthetic carrier (5 paired mutants of the tool), 5 on the
  independent helper (golden-good, six negative fixtures, two usage/format errors, 4 paired mutants of the helper) and
  9 per real carrier for `QWEN.md` and `GEMINI.md` (verify, independent figure re-computation, the §11.4.290 anchor
  block-start intact and outside the preamble, idempotent re-run, five corruption mutants applied to copies).

## Honest limits

- The tool proves the **move** is lossless and ordered; it does not judge which text deserves to stay in the cell.
- Every ` Prior: ` / ` Prior round: ` with a leading space is an entry boundary, including one that is merely quoted
  in prose; the archive then holds that fragment as its own paragraph. The text is still verbatim and in order, so the
  byte-identity proof holds; only the paragraph split is cosmetic.
- QWEN.md and GEMINI.md were moved on 2026-10-27 (job 2, operator: "fix it properly so no loss happens of any kind or the
  corruption") with the unchanged tool; they now have ratchet rows. The pre-move carriers are not tracked, so the
  full-mode independent proof (below) was run once against the pre-move bytes and its output is kept as evidence under
  `qa-results/j2_qwen_gemini_preamble/` of the parent repository (gitignored; the pre-change files and their sha256 are
  there); afterwards only the figures-only mode and the tool's `verify` can be repeated.
- The archive files are plain Markdown and are linked from the `CHANGELOG.md` entry of 2026-10-27; `README.md` names
  `docs/` only as a directory and does not link `CHANGELOG.md` with a Markdown link, so a README-to-archive link path
  does not exist yet (the §11.4.212 reachability gate is a registered deferral, not implemented; UNCONFIRMED whether
  the README owner wants a link). No HTML, PDF or DOCX twin is produced (`formats_export` is false).

## Cross-references

Constitution §11.4.61(A) (the cell is a one-line hook), §11.4.18 (script documentation), §11.4.224 / §1.1 (test first,
paired mutation), §11.4.273 (control needles), §11.4.141 / §11.4.198 (token efficiency); parent `docs/context/CONTEXT_BUDGET.md`,
`docs/scripts/context_footprint.md`.
