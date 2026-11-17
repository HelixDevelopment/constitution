# CON-423 r4: structural fix of review r3 B1, B2, B3 (evidence)

| Field | Value |
|---|---|
| Item | CON-423 (placeholder id; the lander re-mints) |
| Answers | review round 3 of CON-423 (NO-GO; blocking B1 single-letter runs with other separators, B2 shape-only weak-word paths, B3 invisible characters as content; also F1 quadratic split, F2 absolute paths outside --root, F3, F4, survivors R10, R12). No review text file exists; the dispatch brief carries the summary. |
| Base | fix_rehearsal_v73_4_r3.bundle (sha256 20eb0fb5f4ef476779494ca88c0def1acfa6fbbc24756f9725ffc785e2b0a29f, head 662edb3e), merged with origin main 9f9f808b (merge commit 3e1d18eb, merge, no rebase) |
| Evidence class | gate-logic, PROVISIONAL (section 11.4.289(C)(2), section 11.4.290). No live claim. |
| Model / effort | Opus 5.5 / effort UNKNOWN |
| Round | 4 of the CON-423 review loop; section 11.4.276(E)(3) structural round (the class recurred in r3) |

## What changed

- `scripts/validation/check_provisional_verification_lines.py`: the word rules are rebuilt on ONE scan of the value
  (`clean`, then `scan`): every invisible or non-text character is removed and recorded (Default_Ignorable_Code_Point
  and the categories Cc except TAB, Cf, Cs, Co, Cn, Zl, Zp), one fold (a one-character compatibility fold, NFKD, marks
  removed, NFKC), one token split where every character that is not a letter or digit separates. Every word rule
  (lead, inside, single-letter runs, end, note) reads that token stream; a token skeleton (other-script decimal digits,
  Latin base letters from the Unicode name, ligatures, the closed look-alike map) feeds the word rules only. New:
  letters outside Latin, Cyrillic and Greek are refused, a word mixing Latin with Cyrillic or Greek is refused, a value
  holding an invisible character is refused (B3), a weak word inside a path is no job anchor without `--root` (B2),
  a run of single letters is joined across ANY separator (B1), trailing placeholders and placeholder notes (F3), an
  outcome shape for `checks` (F4), `--root` paths must lie inside the real root and not be the root (F2), a linear
  separator split and a 4096-character line cap (F1), every lookahead bounded by 12 letters.
- `tests/release/pvl_inventory.py` (new): the character-class generator. 23 classes from `class_inventory.md`, each
  enumerated from the Unicode database of the running Python with a member floor; 75231 cases; plus the fold-closure
  sweep over every code point. `tests/release/pvl_timing.py` (new): the work bound (98 cases, limit 1 s each).
- `tests/release/pvl_grid.py`: r4 cases (B1 to B3, F1 to F4, R10, R12, the survivors' cases), a second checker run with
  `--root` for the path cases, and a fixed sample of the inventory (cached per work directory). 733 cases.
- `tests/release/test_provisional_verification_lines.sh`: P7 needles for r4 and the sample; P8 own mutants O01 to O42
  for the rebuilt checker (O04 dropped with its code, see below); P11 the reviewer's R1 to R22 (R17, R18 belong to the
  render suite) and X1 to X7; P12 the full inventory, the class-list comparison with `class_inventory.md` and two
  mutants of the generator; P13 the timing bound and the quadratic-split mutant.
- Tracker: CON-423's job text runs the checker with `--root .` (engine edit, copy first; `tracker/job_migration/`).
  `docs/Issues.md` and `docs/Issues_Summary.md` re-exported (`logs/export_r4.txt`).
- `config/full_suite_manifest.tsv`: two member rows (the generator and the timing tool, invoked by the test) and the
  pvl_grid.py note. `docs/guides/full_suite_runner_guide.md`: census block regenerated (`--sync-guide`). The excluded
  lock is NOT accepted (brief): `--verify-manifest` reports exactly one problem, `note changed
  ['tests/release/pvl_grid.py']`.

## Removed code (section 11.4.124)

The r4 draft repeated the invisible-character removal after NFKC. Own mutant O04 (drop the repeat) survived; the cause
was measured, not assumed: no code point's fold holds an invisible character (every one of 1114112 code points,
`FOLD-CLOSURE ... folds_to_invisible=0`). The repeat was dead code written in this same round; it was removed, and the
fold-closure sweep is now part of P12 so a Unicode change that makes it live again fails the test.

## Order of work, stated honestly

The brief asked for `class_inventory.md` rev 2 FIRST. It was written after the checker rewrite and after a first draft
of the generator, in the same round. The RED runs were taken on the r3 checker before any change.

## Evidence (files under logs/ unless named otherwise)

See `evidence.md` for the claim-by-claim table. Proposed follow-ups (P1-P6, none filed) are in `followups.md`. `SHA256SUMS` lists every file in this directory.
