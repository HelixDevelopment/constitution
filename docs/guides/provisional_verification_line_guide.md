# Provisional verification lines - User Guide

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Last modified | 2026-11-17T00:00:00Z |
| Status | active |
| Status summary | How to write the one `**Verification:** provisional` line of a PROVISIONAL-DONE item so the checker accepts it, and what makes the checker refuse a body. |
| Authority | Tool documentation for `scripts/validation/check_provisional_verification_lines.py` (§11.4.18); the rule is §11.4.290; no new anchor and no new CM-* token. |
| Scope | Universal (§11.4.17): any project whose tracker bodies carry §11.4.290 verification lines. |
| Issues | CON-PENDINGpvl8 (rounds 5 to 8 of the checker; evidence under `docs/qa/rehearsal_v73_4_fix/`) |
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

The checker reads the body with markdown-it-py 3.0.0 twice: as CommonMark, and as CommonMark with GFM tables and
strikethrough. It refuses the whole body, not only the line, when a reader could show a different line from the one
it counted.

| Body holds | Why it is refused |
|---|---|
| Any raw HTML, HTML comments included, at any depth | Raw HTML can hide or wrap a line (`hidden`, `display:none`, `<style>`). An HTML5 reader ends a comment at `--!>` or `<!-->`, where CommonMark does not. |
| A GFM footnote definition (`[^x]: ...`) | A GFM reader moves its text into a footnote. |
| Markup, a character reference or an escape after the label, or a line that continues the paragraph | The line must be shown exactly as written, as one paragraph of one source line. |
| The label anywhere else, also inside code, link titles or another paragraph | Whether a reader shows that text as a second verification line depends on the reader. |
| The label written with look-alike or invisible characters (`Ⅴerification:`, a variation selector inside the word) | The checker reads characters as a person reads them: the Unicode confusable skeleton, NFKD, case folding. Invisible characters are read as nothing. |

## Placeholders: write them inside backticks

A placeholder such as `<name>` or `<path>` written in plain prose is raw HTML to a Markdown reader. A body that
holds one is refused, even when the verification line itself is clean. Write the placeholder inside backticks:

| Refused | Accepted |
|---|---|
| `run the job for <name> first` | ``run the job for `<name>` first`` |

The refusal message says the same: ``write a placeholder such as <name> inside backticks (`<name>`) so a reader shows it as text``.

On 2026-11-17, 39 of the 486 bodies on `main` held a placeholder outside backticks. None of them carried a
provisional line, so no current verdict changed.

## Limits

- **What a pass proves.** A sentence of the grammar can still be false. For example, the script may be real but not
  the right job. The checker runs no process. A pass is gate-logic evidence only (§11.4.289(C)(2)).
- **Readers.** Only the two readings above are modelled. Other dialects are read as CommonMark text, for example
  pandoc fenced divs or kramdown attributes.
- **Fonts.** Characters are read as Unicode 17.0 reads them. A font that draws a character differently is not
  modelled.
- **Evidence.** The round 8 evidence is in [docs/qa/rehearsal_v73_4_fix/r8/](../qa/rehearsal_v73_4_fix/r8/README.md).
  It is PROVISIONAL (§11.4.290).
