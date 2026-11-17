# CON-PENDINGpvl8 round 8: class inventory of "what the checker reads differs from what a reader shows"

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Item | CON-PENDINGpvl8 (placeholder id; tracker item CON-521 on main; earlier commits call it CON-423) |
| Round | 8 (structural, sections 11.4.276(C) and 11.4.250), after the r7 NO-GO review |
| Class | gate-logic, PROVISIONAL (sections 11.4.289(C)(2), 11.4.290); no live claim |
| Effort | UNKNOWN (not settable or readable on the dispatch path, section 11.4.231(F.2)) |

## The class

Review r7 found two new members of one class (F1, F2) and four related minor ones (F3, F4,
F5, F6). The class is: **the checker reads a body one way and a reader shows it another way**.
A body in the class can show a second Verification line, hide or change the counted line, or
add text to it, while the checker accepts it.

Rounds 5 to 7 closed members one at a time. Round 8 lists every member first (section
11.4.276(C)), then closes or scopes out each one. The list comes from three sources, each
measured with a control needle:

1. **Parser rules.** Every rule markdown-it-py 3.0.0 runs in the checker's two readings
   (`commonmark`, and `commonmark` with `table` and `strikethrough` enabled).
   Census: [`census/reader_rules_census.txt`](census/reader_rules_census.txt).
   Positive control: `paragraph` and (GFM) `table` are active. Negative control: `zzq_rule`
   and `linkify` are not.
2. **The HTML5 comment states.** A browser ends a comment at `-->`, `--!>`, `<!-->` and
   `<!--->`; CommonMark ends it only at `-->` (reviewer evidence `probe_bang_html5lib.txt`).
3. **How a person reads a character.** A character can be invisible, a look-alike of a
   letter, or a look-alike of the colon. Round 8 derives this from ICU (UTS #39 skeletons,
   NFKD, case folding, `Default_Ignorable_Code_Point`) instead of a hand-kept list. See
   [dependency_verdict.md](dependency_verdict.md).

RED is the r7 checker (head `3a5b462d`); GREEN is the r8 checker. Every row below has a probe
body in at least one of these places:

- `tools/probe_class_r8.py` (`red/probe_class_r8_on_r7.txt`, `green/probe_class_r8_on_r8.txt`);
- the reviewer's own probes, vendored verbatim (`tests/release/pvl_reviewer/probe_*_r7.py.txt`);
- the generator of `tests/release/pvl_blockstate.py` (contexts, suffixes and reviewer entries named in the row).

## Members

| # | Member | Where a reader differs | r7 (RED) | r8 rule | r8 (GREEN) |
|---|---|---|---|---|---|
| M1 | HTML comment (`html_block`, `html_inline` starting `<!--`) | an HTML5 reader ends the comment at `--!>`, `<!-->` or `<!--->`; the text after it is live markup (`<div hidden>`, `<style>`) | accepted: reviewer `probe_bang` 4 bodies (`bang-block-div-hidden`, `bang-block-style`, `bang-block-oneline`, `bang-after`); blockstate contexts `c-bang-div`, `c-bang-inline` | RAW HTML: every comment refuses the body (the r7 exemption for a complete comment is removed) | refused; reviewer entries `rv7-bang-*` danger 0 |
| M2 | other raw HTML, at any depth (block, inline, inside image alt text or link text) | `hidden`, `display:none`, `<details>`, `<style>` hide or wrap a line | refused at top level; inside image alt text accepted (`probe_class` "F5 raw HTML in image alt"). Review r7 F5 found no reader that shows a different line for it, and neither does the blockstate oracle: so for alt text this row is a narrowing, not a closed bypass | RAW HTML: `_raw_html` walks every token's children | refused; context `img-alt-html`, entry `rv7-img-alt-html` |
| M3 | GFM footnote definition (`[^x]: ...`, the `reference` rule) | a GFM reader moves the text, and lines indented under it, into a footnote; CommonMark reads a link reference definition | "F3 GFM footnote def before line" accepted | FOOTNOTE: a `^` label in the parser's references refuses the body | refused; context `fn-def`, entries `rv7-footnote`, `rv7-footnote-indent` |
| M4 | GFM table (`table` rule) | a delimiter row after the line makes it a table header in GFM; `\| x \|` then `---` is a setext heading in CommonMark and a table in GFM | "F11 GFM table delimiter after line" accepted | the second reading (GFM) must count the same lines and meet every rule | refused; context `gfm-setext-table`, suffix `table-delim`, entry `rv7-gfm-table-header` |
| M5 | GFM strikethrough (`strikethrough` rule) in the counted line | `~~x~~` is struck in GFM, plain in CommonMark | accepted: reviewer `probe_shapes` `strike-gfm` (the r7 oracle checked only that the paragraph starts with the line's text) | EXACT, in the GFM reading | refused; `green/probe_shapes_on_r8.txt` `strike-gfm` |
| M6 | the counted paragraph spans more than one source line (`newline` rule: soft break, hard break; a comment spanning lines; lazy continuation) | a reader shows the next line as part of the counted line (for example a second `checks:` field) | "F11 continuation line appended", "inline comment spans", "hard break then text" accepted | EXACT: the paragraph's map must cover exactly one source line | refused; suffix `cont-fake`, entries `r8-cont-fake`, `r8-comment-spans`, `r8-hardbreak` |
| M7 | inline markup after the label (`escape`, `backticks`, `emphasis`, `link`, `image`, `autolink`, `entity`) | a reader shows other characters than the source holds | "F11 emphasis in note", "F11 entity in note" accepted | EXACT: the rendered text after the label must equal the rest of the source line | refused |
| M8 | the label elsewhere, with invisible characters inside (variation selectors U+FE00 to U+FE0F, CGJ U+034F, Mongolian FVS U+180B, Hangul filler U+3164, other marks and formats) | the reader shows `Verification:`; r7 dropped category Cf only | accepted: reviewer `probe_near` 6 bodies (VS16, VS1, CGJ, FVS1, Hangul filler, combining dot below U+0323). That probe also has r7 accept the M9 rows Cherokee V and Armenian o and the M11 row `&#xFE0F;`: 9 accepted in all (`red/probe_near_on_r7.txt`) | THE NEAR RULE: fold() drops every `Default_Ignorable_Code_Point`, every mark (Mn, Mc, Me), format, surrogate, private-use and unassigned code point, and every control that is not white space | refused; contexts `lbl-vs16`, `lbl-cgj`, `lbl-hangul`, `lbl-mark`, `lbl-code`, entries `rv7-near-*` |
| M9 | the label elsewhere, with look-alike letters (Cyrillic, Cherokee, Armenian, full-width) | the reader shows `Verification`; r7 had a closed list of look-alikes | "letter U+13D9 Cherokee V", "letter U+0585 Armenian o" accepted | fold(): NFKD, then the UTS #39 skeleton and case folding of every part | refused; contexts `lbl-cyr`, `lbl-cherokee` |
| M10 | the label elsewhere, with a look-alike colon (U+2236, U+A789, U+0589, U+02F8) | the reader shows `Verification:` | all four accepted | fold() as M9 (their skeleton is `:`) | refused; context `lbl-ratio` |
| M11 | the label elsewhere, written with a character reference (`&#xFE0F;`, `&#86;`) | the reader decodes the reference | accepted: reviewer `probe_near` row `entity VS16 &#xFE0F;` | fold() decodes references before reading | refused; context `lbl-ref` |
| M12 | a status word with an invisible or look-alike character (`Ready` U+FE0F `for testing`, `In` U+034F `testing`) | the reader shows `Ready for testing`; r7 read another status, so the item was skipped | "status ..." rows read SKIPPED | the status is read with the same fold() | read as provisional; `api_r8` items CON-991, CON-992 |
| M13 | a line holding only white space a CommonMark parser does not treat as blank (U+3000 IDEOGRAPHIC SPACE) | the line is shown as an empty-looking paragraph line | not open on r7 (the r7 line model refused it; 0 danger rows in context `u3000-line`) | EXACT (the map half): without it the r8 checker accepts this body, so it is the witness that the map half is needed | refused; context `u3000-line` |

## The whole grid, RED and GREEN

The final r8 harness (`tests/release/pvl_blockstate.py`, sha256 `c956b3a8...66fb`) was run on
both checkers:

| Checker | Bodies | Accepted | Danger | False refusals | Evidence |
|---|---|---|---|---|---|
| r7 (RED) | 65004 | 8097 | 5669 | 4146 | `red/blockstate_on_r7.txt` |
| r8 (GREEN) | 65004 | 2286 | 0 | 4296 | `green/blockstate_on_r8_run1.txt` |

Where the 5669 r7 danger rows come from:

| Source in the grid | Danger rows on r7 | Member |
|---|---|---|
| suffix `bang-after` (every context, join and line ending) | 894 | M1 |
| suffix `table-delim` | 894 | M4 |
| suffixes `text`, `comment-end` and `cont-fake` (the next line joins the counted paragraph) | 2682 | M6 |
| suffix `lbl-after` (a look-alike label after the line) | 894 | M8 to M11 |
| contexts `lbl-*` with the old suffixes | 216 | M8 to M11 |
| context `c-bang-div` with the old suffixes | 36 | M1 |
| context `fn-def` with the old suffixes | 6 | M3 |
| reviewer entries `rv7-*` and `r8-*` | 47 | M1, M3, M4, M6, M8, M11 |

The `text` and `comment-end` suffixes existed in r7. Their rows are danger now because the r8
oracle needs the paragraph to show exactly the line's text, while the r7 oracle only checked
that it starts with it (M5, M6).

## Scoped out, with the reason

These shapes are outside both readings. For each one, it is stated why no reader shows a
different line from what the checker reads.

| # | Shape | Why it is scoped out | Evidence |
|---|---|---|---|
| S1 | GFM task list (`- [ ] x`) after the line | not a rule in either reading; pandoc gfm renders a checkbox (`input`, `label`) in the list item; the counted line is a top-level paragraph, so it is never inside the list item; nothing is hidden | `pvl_reviewer/changes_r7.tsv` row `task-like` (accepted-dirty, listed); `green/probe_shapes_on_r8.txt` |
| S2 | GFM extended autolink (`www.example.com`) | not a rule in either reading (`linkify` is inactive, negative control above); pandoc gfm makes it a link with the same text | `changes_r7.tsv` row `autolink-www-gfm` (an oracle artifact, listed) |
| S3 | pandoc dialects (fenced divs, attributes, YAML front matter) | read as CommonMark text; when such a block carries the label, ELSEWHERE refuses the body | `green/probe_shapes_on_r8.txt` rows `fenced-div-pandoc`, `frontmatter-yaml` (REFUSE) |
| S4 | readers not on this host (cmark, cmark-gfm, commonmark.js, a browser) | not tried; html5lib stands in for the HTML5 tokenizer of M1 | review r7, Limits |
| S5 | fonts and rendering engines | THE READING is Unicode 17.0's; a font that draws a character differently is not modelled | the checker's docstring, Known limits |

## Narrowings (rules that refuse more than before)

- **M1, every comment.** r7 accepted a complete comment. r8 refuses every comment. The reason:
  whether a comment ends where CommonMark ends it depends on the reader.
  Census: 0 of 486 bodies on main hold `<!--` (`census/tracker_body_census.txt`). The same
  predicate fires on a control string holding a comment. The reviewer's comment probes now read
  as false refusals, listed in `tests/release/pvl_reviewer/changes_r7.tsv`.
- **M6 and M7, the counted line is exact.** Any markup, reference or escape after the label
  refuses the body. A note that needs markup cannot use it.
- **M2, raw HTML in prose.** A placeholder written as `<name>` outside backticks is raw HTML.
  Census: 39 of 486 bodies on main hold one (the same predicate does not fire when the
  placeholder is in backticks). None of them carries a provisional line today, so no current
  verdict changes. The refusal message and the checker's documentation say to write the
  placeholder inside backticks (review r7 F9).

## How the harness can now produce these shapes (review r7 F6)

`tests/release/pvl_blockstate.py` now has:

- contexts `c-bang-*`, `lbl-*`, `fn-def`, `img-alt-html`, `gfm-setext-table` and `u3000-line`;
- suffixes `cont-fake`, `lbl-after`, `bang-after` and `table-delim`;
- reviewer entries `rv7-*` and `r8-*`.

Its oracle reads labels with the reference `fold()` of `scripts/validation/pvl_reading_table.py`,
computed live from ICU. The checker reads them from its embedded table. So the oracle does not
share the checker's code for this step.

The oracle also needs the verification paragraph to show exactly the line's text. Before it
runs, it checks itself on 14 fixed inputs (`ORACLE_SELFTEST`). If one fails, the run is
BLOCKSTATE-BLIND. That self-test is what kills the reviewer mutants R7M13 and R7M14, which
removed two of the oracle's checks.

The markdown-it-py role of the oracle uses the same parser as the checker, as review r7 noted.
pandoc commonmark and pandoc gfm stay the independent readers.
