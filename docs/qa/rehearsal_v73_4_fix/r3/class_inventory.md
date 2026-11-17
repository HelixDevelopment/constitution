# CON-423 r3: class definition and member inventory (written before the code change)

| Field | Value |
|---|---|
| Item | CON-423 (placeholder id; the Jev r12 bundle mints the same ids, the lander re-mints) |
| Answers | REVIEW_CON-423_r2.md, sha256 37fc72c50daa423818817a73c5caf473843ccb47772c49066b369d6a6cdd4950 (NO-GO, B2 blocking) |
| Rule | section 11.4.276(C) name the class, enumerate every member, close or scope out each; (E)(3) round 3 is structural |
| Evidence class | gate-logic, PROVISIONAL (section 11.4.289(C)(2), section 11.4.290) |

## The class

**A verification-line field value that names no real thing of its kind, yet the checker accepts it.**
The thing a field must name: `job` a runnable verification job, `checks` a runtime signature, `layer` an evidence
class, `target` the place the job runs, `artifact` a fingerprint or ref of the fix, `due` a due time.

Round 2 closed this class with a deny-list of exact words. A deny-list cannot close it: every new spelling, every
extra word after a weak word and every look-alike letter is a new member. Round 3 replaces the scheme:

1. **Positive shape** for `job` and `target` (they now have to name something of their kind, as `layer`, `artifact`
   and `due` already did). `checks` stays free text by design (real signatures are prose, for example
   "real-tree census byte-identical across census variants"); it is protected by rules 2 to 4 only. This limit is
   stated, not hidden.
2. **Leading-word rule per field** instead of whole-value matching.
3. **Token split** on every non-alphanumeric character and at letter/digit boundaries, plus the join of runs of
   single letters (`T.B.D.`, `T B D`, `t_b_d`), before any word comparison.
4. **Fold** before every check: NFKD, combining marks removed, NFKC, format characters removed, then a confusables
   map (Cyrillic and Greek letters that look like Latin ones become the Latin letter).

## Member inventory (axes; every member has at least one grid case in tests/release/pvl_grid.py)

| # | Axis | Members (examples) | Closed by |
|---|---|---|---|
| A1 | strong placeholder word, any position | TBD, TBA, TBC, TODO, FIXME, XXX (capitals inside, any case at the start), UNCONFIRMED and LOREM at the start | rule 3 tokens, strong set |
| A2 | weak word at the start | unknown, pending, none, n/a, na, null, nil, placeholder, dummy, later, soon, eventually, someday, asap | rule 2, per field |
| A3 | weak word plus more words | `pending scheduling`, `none assigned`, `unknown host thing`, `later today` | rule 2 (whole first token) |
| A4 | weak word glued to more words | `none-yet`, `pending_scheduling`, `not-applicable` (all parts alphabetic, the compound is the whole value or a bracketed note follows) | rule 2, first part of an all-alphabetic compound; golden FALSE `unknown-id-only table gives rc 1` (CON-189, a statement) |
| A5 | lead phrase | `not applicable`, `not yet`, `not scheduled`, `not known`, `not available`, `not assigned`; `no job yet`; `to be done`, `will be scheduled later`, `shall/should/would be ...` | rule 2 (`not`/`no` refused at the start of job, target, artifact; in checks only `not` + a closed list) |
| A6 | punctuation-split acronym | `T.B.D.`, `T-B-D`, `T_B_D`, `T. B. D.`, `t.b.d` | rule 3 join of single letters |
| A7 | digit or underscore glued | `TBD_1`, `TBD1`, `TBD-1`, `MY_TODO`, `2DRAFT` (render), `FIXME2` | rule 3 split |
| A8 | digit look-alikes inside a word | `T0D0`, `F1XME`, `TB0` is not a member | rule 3: a token whose 0 and 1 read as O and I spells a strong word |
| A9 | width and format characters | full-width `ＴＢＤ`, `T<U+200B>BD`, `T<U+200D>BD` | rule 4 NFKC and Cf removal (round 2, kept) |
| A10 | confusable letters | Cyrillic `ТBD`, `ТОDО`, Greek `ΤΒΔ` is not a member (Δ is not D), Cyrillic `хxx`, `рending`, `nоne`; and the reverse: a look-alike of a SHAPE word (`һоѕt`, `сommit`, `tеsts/x.sh`) must not satisfy the shape | rule 4 confusables map for the word checks; shapes read ASCII without the map |
| A11 | combining marks | `T̈BD`, `pénding` | rule 4 NFKD + Mn removal |
| A12 | wrappers | `[TBD]`, `"TODO"`, `(pending)`, `*none*`, `` `TBD` `` | openers stripped before rule 2 (round 2, kept) |
| A13 | templates | `<id>`, `{{job}}`, `${JOB}` | template rule (round 2, kept) |
| A14 | punctuation-led | `??? later`, `--- later`, `–– later`, `?? x` (a leading `…` folds to dots, which are stripped as edge punctuation, so `… later` is refused by A2 instead) | new: the first token must hold a letter or digit |
| A15 | empty and punctuation-only | ``, `.`, `-`, `?`, `…` | round 2, kept |
| A16 | job names nothing runnable | `later`, `re-run the suite`, `re-run DRAFTS check`, `lorem ipsum dolor`, a homoglyph path `tеsts/x.sh` | rule 1: a path (existing under `--root`), a command with an option or path argument, or a job id `<KEY>-<digits>` |
| A17 | target names no place | `lorem ipsum dolor`, `somewhere`, `the usual` | rule 1: a target word (host, board, device, container, runner, vm, emulator, image, sandbox, scratch, server, machine, checkout, clone, worktree, repo, repository, remote, cluster, ci) |
| A18 | line-level copies | a line in an HTML comment (N1), a fenced line (round 2), `provisionalXYZ` prefix glued to text (N3) | comment blocks skipped; the prefix needs a word boundary |
| A19 | due not a time | round 2 axes (events, bad calendar dates, wrong digits, years outside 2000-2099) | round 2, kept |

## Scoped out (stated, not closed)

- A value that has the right shape but is false (a path that exists but is not the job, a job id that no scheduler
  knows, a target word that is not where the job runs). The checker proves shape, not truth.
- `checks` has no positive shape (see rule 1). A prose value with no placeholder word, for example `foo bar baz`,
  is accepted in `checks`.
- Without `--root` a path is checked for its shape only; the output says so on a `PATHS:` line.
- Look-alikes outside the map (Armenian, Cherokee, mathematical letters that NFKC does not fold, other digits than
  0 and 1). The map is a small closed table, not the whole Unicode confusables data.
- A `<KEY>-<digits>` job id cannot be told apart from a tracker id (`CON-423`).
- English vocabulary only: a Serbian or Russian target word (`хост`) is folded and then not in the target list, so it
  is refused (the conservative direction).

## Golden FALSE kept (section 11.4.201(1))

`checks: none of the mutants survives`, `checks: no pending lock remains`, `target: na-west-2 runner`, `XTBD-9 run`,
`re-run TBDX_case suite` (now with a path), `DRAFTS`, `todolist`, a trailing `UNCONFIRMED` qualifier, the colon-less
canon form, hex-only artifacts, `gate-logic`.
