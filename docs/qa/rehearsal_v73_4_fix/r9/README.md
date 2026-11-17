# CON-PENDINGpvl8 round 9: an allowlist of shapes no reader can hide, confirmed by five readings

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Item | CON-PENDINGpvl8 (placeholder id; tracker item CON-521 on main) |
| Round | 9 (structural, sections 11.4.276(E)(3) and 11.4.250), after the r8 NO-GO review, the fifth NO-GO round of the same class |
| Base | r8 head `529d8903`, range `2ca50ac4..` |
| Class | gate-logic, PROVISIONAL (sections 11.4.289(C)(2), 11.4.290); no live claim |
| Effort | UNKNOWN (not settable or readable on the dispatch path, section 11.4.231(F.2)) |

## What changed and why

Rounds 5 to 8 tried to predict what a Markdown reader would show and refuse a body whose line a reader could hide.
Every review found a body shape the prediction missed. The class (the checker reads a body one way, a reader shows it
another way) was never closed, because the set of shapes that can hide text is open.

Round 9 turns the rule around. A body is accepted only when it is built from a small set of shapes that no reader can
hide or change, and then five real readings must show the line exactly as written. Everything else is refused. This
refuses some harmless bodies; the cost on the real tracker is measured below.

| Layer | Rule | Depends on a reader |
|---|---|---|
| THE BODY | at most 64 KiB; no run of more than 512 characters without ASCII white space; no lone CR; no bidi control (also as a reference); no `:::` line; `<` + letter, `!`, `?` or `/` only inside a simple ```` ``` ```` fence at column 0, and then no `]:` | no |
| THE LINE | one line starts with the prefix at column 0; blank line above and below; at most 4096 characters; after the label only `[A-Za-z0-9 .,;:/@()+=_-]`, the em dash only as ` — `, `_` only between letters or digits, no trailing white space; the label in a line not at column 0 refuses the body | no |
| THE NEAR RULE | the label (also split by a link, image, autolink, emphasis or code span, and through look-alike and invisible characters via `fold()`) anywhere else refuses the body | no |
| THE READERS | markdown-it-py 3.0.0 `commonmark` and `commonmark` + GFM tables and strikethrough, pandoc 3.11 `commonmark`, `gfm` and `markdown-yaml_metadata_block` (the tracker export reader; operator decision 2026-11-17; compared after its smart mapping of `--`, `---`, `...`): exactly one top-level paragraph that is the line as written, only allowlisted tags and attributes, the label nowhere else in the visible text or attributes; missing or untested reader = BLIND | yes |

Removed because the allowlist makes it unnecessary: the token-stream line model, the comment and footnote rules,
the per-token rendered-text comparison (r8 code; their mutants are retired, below).

## Findings of review r8 and where each is closed

| Finding | Where |
|---|---|
| A (class not closed; O59 "equivalent by redundancy" false) | the allowlist above; every layer tested alone in `tests/release/pvl_mutate.py` `api_r9`; O59 retired with its code and its hole tested by R9A59 (label split by a link) |
| B reviewer bodies | `probe_cases_*.txt` (final run with five readings): cases_a 1/24, cases_eq 1/24, cases_c 5/13, cases_rva 0/8, cases_p6 0/6 (accepted/refused). The reviewer tool flags 7 accepted bodies under its `pandoc-md-export` reader; that reader compares without the smart mapping and treats any non-paragraph output elsewhere as raw HTML. Re-judged with the mapping (`adjudicate_probes.txt`, tool `tools/adjudicate.py`, needles `adjudicate_needles.txt`): 7 of 7 show the line exactly and the label nowhere else. Other readers: 0 |
| C fuzz | `fuzz_b.txt` (final): 1377 bodies, 391 accepted, 986 refused (3 more refused than before the fifth reading); every flag (391) is the reviewer's `pandoc-md-export` reader alone; re-judged with the mapping (`adjudicate_fuzz.txt`): 391 of 391 shown exactly; 0 under the other readers (r8: 59) |
| D pandoc `markdown` export reader | CLOSED by the operator decision of 2026-11-17: the export reader is the fifth reading in the checker (`READERS`, `PANDOC_FROM`, `SMART`) and a fourth reader in the blockstate oracle (`tests/release/pvl_blockstate.py`, `readers=4`); when readers disagree the body is refused. Own mutants O105 to O108; `oracle_pandoc_markdown.txt`. The r8 P10 claim (`\iffalse` hides the line) is not reproduced: in HTML the export reader shows the line, and pandoc 3.11 writes `\iffalse` as text in LaTeX too (`iffalse_html.txt`), so P10 is accepted; LaTeX output is not checked (stated limit) |
| E placeholder census | corrected in the guide; `E_placeholder_hidden.txt`; `false_refusal_main.txt`, `false_refusal_fix8.txt` |
| F lazy-continuation hint | the `blank` refusal names the line above or below and says to add a blank line |
| G label without colon | THE NEAR RULE third pattern; own O99 |
| H oracle limits | section Limits below |

## Found during round 9

- **Reader time (DoS).** The r3 reviewer probe `singles20k` (a 20000-character run `a.a.a...`) reached the readers
  because the line-length bound was checked after them; pandoc gfm timed out at 30 s (`red/dos_before.txt`, a reconstruction: the r9 checker with own mutants O102, O103 and O104 applied, then the reviewer's probe_r3; singles20k 30.516 s, TimeoutExpired). Measured
  pandoc gfm time grows faster than the length of one run without white space (4000 characters: 6.73 s; the same text
  in 100-character lines: 0.23 s), and about 17 s per MiB of ordinary text. Fix: the run bound, the line bound before
  the readers, and `MAX_BODY` 64 KiB (the longest real body is 13433 characters, the longest real run 179). After:
  `dos_worst=0.012` s in the reviewer harness, worst 0.068 s in `green/dos_after.txt`. Own mutants O102, O103, O104.
- **Export outputs.** The export writes HTML, a PDF made from HTML, and DOCX. DOCX drops raw TeX
  (`docx_rawtex.txt`); the checker reads HTML only.
- **A second counted line** was refused twice (as the label elsewhere and by the count), so the count branch was dead
  and mutants O61 and R21 survived. The count is now the only rule for it.
- **The reviewer r7 shapes probe** asserted its good line `... -- note a|b` is accepted; `|` is outside THE LINE
  ALPHABET, so the probe stopped before judging its 34 shapes. The harness runs it with that one string changed to
  `a b` (printed as `REV-R7-ADAPTED`).

## Mutants

Final suite runs (`final/suite_run1.txt` on the final code before its commit, `final/suite_run2.txt` on commit 85d8d1a7; each RESULT pass=107 fail=0, each including the P13 mutation run; the two files are byte-identical, sha256 1951ea68756bb509468845be18767bc16b38d223f502ed4eb34537300ffa6665):
`MUTATE total=105 killed=105 survived=0 not_applied=0 retired=47 equivalent=0 retired_fail=0`. 80 own rows; new in
round 9: O90 to O108, R9A01, R9A01b, R9A03, R9A07, R9A08, R9A09, R9A12, R9A59 and the r8 reviewer analogs RVA02,
RVA05, RVA06, RVA10, RVA11. O59 is retired with its code (no equivalent rows remain); the hole it stood for (a label
split by a link) is tested by R9A59. The reviewer harness lists 93 reviewer mutants (`final/reviewer_mutants.txt`:
applies=32, not_applicable=61, fail=0). The quick mutation harness runs no pandoc, so the oracle's export-reader leg
is covered by a hand mutant instead: with the smart expectation removed the oracle goes BLIND on its control needle
(`final/oracle_mutant_no_smart.txt`, rc=2). Earlier mutation runs of this round are kept as `mutate_run1.txt` and
`mutate_run2.txt` (before the fifth reading; 98 rows).

## Real tracker

`false_refusal_main.txt` (main, 491 items) and `false_refusal_fix8.txt` (vehicle, 486 items), final code: 29
provisional items on each, 29 refused on each by r9 and by r8, no verdict changed; grammar-valid lines refused by the
line rules: 0 (of 0 grammar-valid lines; the number does not yet show the rules' cost). Kinds on main: grammar 13,
raw-html 10, blank 4, noline 2.

## Limits (finding H)

- The five readings are the oracle, each to HTML. A body all five show correctly is accepted even if another reader
  (kramdown, a browser's own Markdown) or another output (LaTeX; DOCX is not checked separately) hides it.
- A body is read alone, not inside the exported document that holds many items.
- "Refuse a line where the readers disagree" is read as: the verification line, and the label anywhere, must be
  shown the same by every reading (after the export reader's smart mapping); a body whose other lines are shown
  differently (a line block, a definition list, a span, a subscript elsewhere in the body) is accepted when every
  reading still shows the verification line exactly and the label nowhere else. That reading of the operator
  decision is UNCONFIRMED; 7 probe bodies and 391 fuzz bodies are accepted under it (`final/adjudicate_*.txt`).
- The line-end and line-model harnesses (`pvl_lineend.py`, `pvl_linemodel.py`) still use pandoc `commonmark` only as
  their second reader; the export reader is covered there only through the checker's own confirm step.
- The reader-output allowlist and the visible-text extraction are this checker's own parser of the readers' HTML; a
  reader that writes a tag outside the allowlist is refused, not judged.
- THE NEAR RULE reads with Unicode 17.0 / ICU 78.2; a font or reader with other rules may show a character differently.
- Gate-logic only: the line's job is not run and its counts are not observed.

## Gates and merge test

`gates.txt` (on 85d8d1a7, 2026-11-17T11:18:05Z):

- `--verify-manifest`: `MANIFEST-MISMATCH`, 1 problem: the excluded set differs from the accepted lock by the addition
  of `tests/release/pvl_grid.py` (the expected one; the accept is the lander's, with a rostered reviewer).
- git-env census: PASS, members=666 hermetic=507 exempt=159 unscrubbed=0.
- `CM-GATE-LEDGER-RATCHET`: PASS, unimplemented=394 baseline=394.
- `CM-CONSTITUTION-INDEX-FRESH`: PASS.
- `--sync-guide`: total=977; the working tree was unchanged after it.
- workable-items `validate`: OK, 486 items. `diff`: the database and the Markdown are in sync.

`merge_test.txt`: `git merge --no-ff --no-commit` of this head onto main `ebd8818c` in a separate clone (then
aborted). Conflicts in `config/full_suite_manifest.tsv` (one hunk: the next entry row on each side),
`docs/guides/full_suite_runner_guide.md` (one hunk: the generated census line) and `docs/workable_items.db` (binary).
`docs/Issues.md` and `docs/Issues_Summary.md` merged without conflict.
