# Provisional verification lines - User Guide

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-11-17 |
| Last modified | 2026-11-17T20:00:00Z |
| Status | active |
| Status summary | How to write the one `**Verification:** provisional` line of a PROVISIONAL-DONE item so the checker accepts it, and what makes the checker refuse a body. |
| Authority | Tool documentation for `scripts/validation/check_provisional_verification_lines.py` (§11.4.18); the rule is §11.4.290; no new anchor and no new CM-* token. |
| Scope | Universal (§11.4.17): any project whose tracker bodies carry §11.4.290 verification lines. |
| Issues | CON-PENDINGpvl8 (rounds 5 to 10 of the checker; evidence under `docs/qa/rehearsal_v73_4_fix/`) |
| Generated twins | .html / .pdf / .docx not generated for this revision (honestly absent, §11.4.106(E)). |

## What it is for

Under §11.4.290 an item in Status `Ready for testing` or `In testing` is PROVISIONAL-DONE. It needs a scheduled
verification job, recorded on exactly one line of its body. The checker reads the tracker database and refuses an
item whose body has no such line, more than one, or a line that is not a sentence of the checker's grammar.

The full grammar is in the checker's docstring (THE GRAMMAR). In short, one line of the form below (the script
`tests/t.sh` is an example; in a real body it must be a file of the checkout):

```text
**Verification:** provisional -- job: bash tests/t.sh -- checks: tests/t.sh pass=3 -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-20
```

Every path, option and target in it must resolve in the checkout. The due date must lie between the item's created
date and today plus the window (60 days by default).

## Run it

```text
python3 -I scripts/validation/check_provisional_verification_lines.py --root . docs/workable_items.db
```

It prints one `FAIL <id> <status>: <reason>` line per refused item, then `CHECKED items=N provisional_status=P ok=K
fail=F` and `VERDICT: PASS|FAIL|BLIND`.

| Exit | Meaning |
|---|---|
| 0 | PASS: every provisional item has one line that is a sentence of the grammar |
| 1 | FAIL: the refused items are listed |
| 2 | BLIND: the database cannot be read, or the parser or the reading table is missing; a zero proves nothing |
| 64 | usage error |

The checker never opens the database in place. It copies the file and its `-wal` and `-journal` first, so no
sidecar appears next to it.

## What makes the checker refuse a body

Round 9 changed the design. The checker no longer tries to work out what a reader would show. It accepts a body only
when the body is built from a small set of shapes that no reader can hide or change, and then five readings by two
independent Markdown libraries confirm the result. Anything outside that set is refused, so some harmless bodies are refused too.

Round 10 adds three checks that run before the line rules, and one that reads the whole exported document:

| Round 10 check | What it refuses |
|---|---|
| THE BODY ALPHABET | Any character other than tab, LF, CR, printable ASCII and four extra characters (`—` U+2014, `§` U+00A7, `→` U+2192, `·` U+00B7), written directly or as a numeric character reference (`&#x7F;`, `&#xFDD0;`, `&#151;` and so on). Look-alike and invisible characters are refused this way as a class. The four extra characters are not letters, marks or controls and do not fold to a letter, digit or colon. Enumerated over all 1112064 code points: 100 are accepted, none outside this set (`docs/qa/rehearsal_v73_4_fix/r10/enum_alphabet.txt`). An emoji shortcode such as `:smile:` is refused because pandoc `gfm` shows it as an emoji. |
| THE STRUCTURE BOUND | More than 8 container markers (`>`, list markers) on one line, more than 6 open `[` in one paragraph, or more than the per-character count bounds. pandoc `markdown` takes time exponential in open `[` (8 open: 0.4 s, 16 open: 9.7 s, 32 open: over 60 s). Every pattern at its bound in a 65 KB body was read in at most 2.34 s on this host (`bound_timing.txt`). This is a measurement on one host, not a proven bound. |
| THE END OF THE BODY | The body followed by a blank line and a probe paragraph must show the probe as its own paragraph to every reader. A body that leaves a fence, comment, HTML block or raw HTML element open is refused. |
| THE DOCUMENT | The tracker's Issues and Fixed documents are built from the database in order. Each segment is followed by a probe paragraph and the whole document is read by every reader. An item, of any status, after which a probe is missing is refused (`DOC-FAIL` for an item that is not provisional); a raw segment that leaves a construct open is reported as `DOC-FAIL ... segment N`. In each document every reader must show the verification line of each provisional item as a paragraph of its own. |

**The body** (these hold before any reader runs):

| Body holds | Why it is refused |
|---|---|
| More than 65536 bytes (64 KiB) | The readers need about 17 seconds per MiB; the longest real body is 13433 bytes. |
| A run of more than 512 characters with no space, tab or line break | pandoc `gfm` slows down sharply on one long unbroken run (4000 characters took 6.7 seconds); the longest real run is 179. |
| A CR that is not followed by LF | pandoc does not end a line at a lone CR, markdown-it does, so the two readers disagree. |
| A bidi control character (U+202A to U+202E, U+2066 to U+2069, U+200E, U+200F, U+061C), also as a character reference | It can reorder what a reader shows, for example a reversed fake label. |
| A line that starts with `:::` | pandoc reads it as a fenced div, which can hide what is inside it. |
| `<` followed by a letter, `!`, `?` or `/`, outside a simple fence | That is raw HTML, an HTML comment or an autolink to some reader. It can hide or wrap a line. Inside a code span it is refused too, see below. |
| The label anywhere else (`Verification:` or `Verification` followed by `provisional`), also split by markup, a link, look-alike or invisible characters | A reader may show it as a second verification line. |

**The line** (the one line that starts with `**Verification:** provisional`):

| Rule | Why |
|---|---|
| It is at most 4096 characters long | Checked before any reader runs. |
| It starts at column 0, not indented, not in a quote or a list item | Otherwise a reader puts it in a code block, a quote or a list. |
| The line above it is blank (or it is the first line), and the line below it is blank (or it is the last line) | Otherwise a reader may join it to the text next to it into one paragraph, or read the two lines as one construct (a table, a heading, a list). Add a blank line. |
| After the label it uses only letters, digits, space and `. , ; : / @ ( ) + = _ -`, the em dash only as ` — `, `_` only between two letters or digits, and no white space at the end | None of these characters starts markup at that place. |

**The readers.** markdown-it-py 3.0.0 (CommonMark 0.30, and CommonMark with GFM tables and strikethrough) and
pandoc 3.11 (`commonmark` and `gfm`, CommonMark 0.31.2, and `markdown-yaml_metadata_block`, the reader the tracker
export uses) must each show exactly one top-level paragraph that is the line as written, must write only plain tags,
and must not show the label anywhere else. A missing or untested reader makes the run BLIND, never a pass. The scope
of this comparison is the verification line and the label: each body is read alone by the five readers, and in the
document check (round 10) only the probe paragraphs and the verification lines are compared. Other text that the
readers show differently is not compared. When the readers show the verification line differently (for example `<!x` or a lowercase `<!doctype html`, which CommonMark 0.31.2 hides and
0.30 does not, or a definition list that only pandoc `markdown` reads and that takes the line as its term), the
body is refused. Other lines may be shown differently (a line block, a span) as long as every reader shows the
verification line exactly and the label nowhere else. The export reader has
smart punctuation on: it shows ` -- ` as an en dash, `---` as an em dash and `...` as an ellipsis, so for that reader
the checker expects the line with those three changes and nothing else.
This check refuses some lines the alphabet allows: pandoc `gfm` turns an email address or a bare URL into a link, so
a line that holds `a@b.c` or `https://x.y` is refused.

## Placeholders: write them as a NAME, or inside a ``` fence

A placeholder such as `<name>` written in plain prose is raw HTML to a reader, and the reader hides it. markdown-it
and pandoc both render `run <version>-x and <real uid> then` as text in which `<version>` and `<real uid>` are gone
(evidence: `docs/qa/rehearsal_v73_4_fix/r9/E_placeholder_hidden.txt`).

Round 9 also refuses a placeholder inside a code span (`` `<name>` ``). The text shows correctly there, but a link
destination or the title of a link definition elsewhere in the body can change which backticks pair, so the checker
does not exempt code spans. That is a deliberate false refusal. Two ways that are accepted:

| Refused | Accepted |
|---|---|
| ``run the job for <name> first`` | `run the job for NAME first` |
| ``run the job for `<name>` first`` | a ```` ```text ```` fence at column 0 that holds the placeholder, closed by ```` ``` ```` |

The fence must open with three backticks and an optional word, at column 0, and close with exactly three backticks.
When the body holds a `<` placeholder, it may not also hold a link definition (`]:`).

## What this costs on the real tracker

Measured on 2026-11-17 against two databases: `main` (sha256 `8e73f353...8453`, 491 items) and the vehicle database
of round 8 (sha256 `d6c29f3b...6ad67`, 486 items). Evidence: `docs/qa/rehearsal_v73_4_fix/r9/false_refusal_main.txt`
and `false_refusal_fix8.txt`.

- **Verdicts.** All 29 provisional items are refused on each database, by round 8 and by round 9 alike. No verdict
  changed.
- **False refusals.** A false refusal here is a body whose verification line is a valid sentence of the grammar but
  which the line rules refuse. There are 0 such bodies on either database. This number is 0 of 0: no line on either
  database is a valid sentence today, so it does not show what the rules will cost.
- **What the rules will cost.** On `main`, 24 provisional bodies carry a line. 14 of them would still be refused after
  their grammar is fixed: 10 for a `<` placeholder (7 of them only inside code spans, CON-185, CON-217, CON-218,
  CON-222, CON-224, CON-235 and CON-236) and 4 because the line is joined to the prose above it (CON-186, CON-189,
  CON-190, CON-191).
- **The earlier census (correction).** Revision 1 of this guide said no body with a raw placeholder carried a
  provisional line. That was wrong (review r8 finding E). On the vehicle database 4 do: CON-144 (`<eval>`, on the line
  above the verification line), CON-211 (`<version>`), CON-216 (`<real uid>` and others) and CON-223 (`<helper>`,
  `<value>`). On `main`, CON-216 and CON-223 still do; CON-211 has the placeholder but no verification line, and CON-144
  has neither. All of them are refused for raw HTML, correctly: the readers hide those placeholders.

## Limits

- **What a pass proves.** A sentence of the grammar can still be false. For example, the script may be real but not
  the right job. The checker runs no process. A pass is gate-logic evidence only (§11.4.289(C)(2)).
- **Readers.** Only the five readings above are checked, each to HTML. The export reader is in scope by an operator
  decision of 2026-11-17 (review r8 finding D). The export also writes DOCX and a PDF made from HTML; those outputs
  are not checked separately. LaTeX output is not checked. A body such as `\iffalse`, blank line, the line, blank
  line, `\fi` is accepted: every reader shows the line in HTML, and pandoc 3.11 also writes `\iffalse` as plain text
  in LaTeX (measured, `iffalse_html.txt` in the evidence), so the earlier claim that this body hides the line is not
  reproduced. Whether other raw TeX can hide a line in a LaTeX output is UNCONFIRMED; the export writes no LaTeX.
- **The document.** Round 10 reads the Issues and Fixed documents as the checker builds them from the database. The
  tracker export (`renderDocument`) may rewrite text differently; that rewrite is not replicated. A segment that ends
  with no blank line is joined to the next by one line break, and the probe sits after a blank line, so a change such
  a join makes to a non-provisional line is not caught; a change to a verification line is caught by the paragraph
  count. cmark-gfm is not run by the checker; it was run once as evidence on the fixture and on `main` and agreed
  (`cmark_gfm_fixture.txt`, `cmark_gfm_main.txt`).
- **Look-alikes without the colon.** `**Verification** job:` and `**Verification -** job:` are still accepted, and a
  label split across two table cells is not detected. Follow-ups (review r9 F7, F8).
- **DOCX and PDF.** The export writes them and they are not read. Follow-up (review r9 F6, operator question).
- **Fonts.** Characters are read as Unicode 17.0 reads them. A font that draws a character differently is not
  modelled.
- **Evidence.** The round 9 evidence is in [docs/qa/rehearsal_v73_4_fix/r9/](../qa/rehearsal_v73_4_fix/r9/README.md),
  round 10 in [docs/qa/rehearsal_v73_4_fix/r10/](../qa/rehearsal_v73_4_fix/r10/README.md). Both are PROVISIONAL
  (§11.4.290).
