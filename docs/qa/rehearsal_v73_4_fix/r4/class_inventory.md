# CON-423 r4: class definition and member inventory, revision 2

| Field | Value |
|---|---|
| Item | CON-423 (placeholder id; the lander re-mints) |
| Answers | review round 3 of CON-423 (NO-GO: B1 single-letter runs with other separators, B2 shape-only weak-word paths, B3 invisible characters as content; F1 quadratic split, F2 absolute paths outside --root, F3 look-alikes and trailing placeholders, F4 checks accepts any prose; survivors R10, R12) |
| Rule | section 11.4.276(C) name the class, enumerate every member, close or scope out each; (E)(3) the class recurred, so this round replaces the design |
| Evidence class | gate-logic, PROVISIONAL (section 11.4.289(C)(2), section 11.4.290) |
| Generator | `tests/release/pvl_inventory.py` builds the probe grid from the table below and from the Unicode database of the running Python (Unicode 16.0.0, Python 3.14) |
| Order of work, stated honestly | this revision was written after the checker rewrite and after a first draft of the generator in the same round, not before them; the r3 RED was taken before any code change |

## The class

**A verification-line field value that names no real thing of its kind, yet the checker accepts it.** Round 3 had
the right parts (a token split, a fold, a positive shape for job and target) but applied them in several places with
different inputs: the single-letter join only knew `.` `-` `_` and white space, the invisible-character removal only
knew Cf and four code points, and the shape mode without `--root` trusted any path. Each new separator, each new
invisible character and each weak word inside a path was a new member. Round 4 removes the cause:

1. **ONE scan.** The value is cleaned once (every invisible or non-text character removed: Default_Ignorable_Code_Point,
   and the categories Cc except TAB, Cf, Cs, Co, Cn, Zl, Zp), folded once (NFKD, marks removed, NFKC), and cut once
   into tokens: maximal runs of letters and digits. EVERY other character is a separator; there is no list of
   separators to extend. Every word rule reads that one token stream.
2. **A skeleton per token** for the word rules: decimal digits of any script to ASCII, Latin letters outside ASCII to
   the base letter their Unicode name gives, ligatures and digraphs to their letters, the closed Cyrillic/Greek
   confusables map. Shapes read the raw ASCII, never the skeleton.
3. **Declared scripts.** A letter outside Latin, Cyrillic and Greek is refused in every field; a word that mixes Latin
   with Cyrillic or Greek letters is refused.
4. **Positive shapes** for job and target as before, a new OUTCOME shape for checks (F4), and in shape-only mode a
   path whose words hold a weak word is not an anchor (B2).
5. **Bounded work**: one pass over the value, the separator split is linear (F1), and every lookahead is bounded by
   the longest word (12 letters); a line longer than 4096 characters is refused.

## Character classes (generated; the test compares this list with `pvl_inventory.py --classes` both ways)

Members are counted on Unicode 16.0.0. FLOOR = the count at landing; fewer members is a FAIL (U06 shrinks as Unicode
assigns code points, so its floor is set lower). "Sampled" classes test every Basic Multilingual Plane member and
every 97th (U19) or 997th (U05, U06) of the rest, plus the first and last; U04 every 31st.

| Id | Class | Members | Cases built from each member | Expected |
|---|---|---|---|---|
| U01 | Default_Ignorable_Code_Point (U+00AD, U+034F, U+061C, U+115F..U+1160, U+17B4..U+17B5, U+180B..U+180F, U+200B..U+200F, U+202A..U+202E, U+2060..U+206F, U+3164, U+FE00..U+FE0F, U+FEFF, U+FFA0, U+FFF0..U+FFF8, U+1BCA0..U+1BCA3, U+1D173..U+1D17A, U+E0000..U+E0FFF) | 4174 | `3 pas<c>sed`, `T<c>BD later`, `artifact<c>` as layer, `<c><c><c>` | refused (the character is recorded as removed) |
| U02 | Cf format characters, bidi controls included | 170 | as U01, and `<c> host` as target | refused |
| U03 | Cc control characters except TAB | 64 | as U01 | refused |
| U04 | Cs surrogates | 2048 (68 sampled) | as U01 (unit level only; a database line cannot hold one) | refused |
| U05 | Co private use | 137468 (6533 sampled) | as U01 | refused |
| U06 | Cn unassigned | 819533 (2254 sampled) | as U01 | refused |
| U07 | Zl, Zp | 2 | as U01 | refused |
| U08 | Zs space separators and TAB | 18 | `T<c>B<c>D later` refused; `3<c>passed` and `every<c>host` accepted | separator |
| U09 | variation selectors | 256 | as U01 | refused |
| U10 | tag block U+E0000..U+E007F | 128 | as U01, and `TBD` + tag letters | refused |
| U11 | bidi controls (U+061C, U+200E, U+200F, U+202A..U+202E, U+2066..U+2069) | 12 | as U01, and `<RLO>DBT later` | refused |
| U12 | combining marks Mn Mc Me that are not default-ignorable | 2238 | `T<m>BD later` refused; `3 pas<m>sed` accepted | removed by the fold |
| U13 | fillers and blanks: U+3164, U+115F, U+1160, U+FFA0, U+2800 BRAILLE PATTERN BLANK, U+3000 | 6 | `<c><c><c>`, `<c> host`, `pending<c> host` | refused |
| U14 | compatibility forms of one ASCII letter or digit (full-width, mathematical, enclosed, super/subscript, modifier, Roman numeral one-letter forms) | 1123 | the member in place of its letter in TBD/TODO/TBA/XXX/FIXME + ` later`; 0 forms as `T<0>D<0> later`, 1 forms as `F<1>XME later`; other letters `3 passed <c>` | refused / accepted |
| U15 | full-width and half-width forms U+FF00..U+FFEF | 225 | letters and digits `3 passed <c>` accepted; punctuation `T<c>B<c>D later` refused | per form |
| U16 | enclosed alphanumerics U+2460..U+24FF, U+1F100..U+1F1FF | 360 | `<c><c><c> later` (any), and `⒯⒝⒟ later`, `ⓉⒷⒹ`, squared `TBD` | refused for the three |
| U17 | Latin ligatures and digraphs | 59 | `3 passed <c>` accepted; `ﬁxme later`, `3 passed ﬁxme` refused | per case |
| U18 | decimal digits of other scripts | 670 | `3 passed <c>` refused (not a declared script); zero digits as `T<0>D<0> later` and in a due date | refused |
| U19 | letters whose folded form holds a letter outside Latin, Cyrillic, Greek | 137798 (2045 sampled, at least 3 per script) | `3 passed <c>`, `<c> host` | refused |
| U20 | Latin letters whose folded form is not ASCII (small capitals, strokes, IPA) | 717 | `3 passed <c>` accepted; in place of its base letter in a strong word + ` later` refused | per case |
| U21 | Cyrillic and Greek letters (folded form in one declared non-Latin script) | 1085 | `3 passed <c><c>` accepted; `3 passed x<c>` refused (mixed script); `ТBD later`, `ТОDО later`, `рending x.sh` refused | per case |
| U22 | punctuation and symbols P* S* whose fold holds no letter or digit | 8417 | `T<c>B<c>D later`, `every suite T<c>B<c>D` refused; `3 passed <c> 4 failed` accepted | separator |
| U23 | ASCII punctuation, space, TAB, and the reviewer's r3 separators (`·` `•` `‐` `‑` `‒` `–` `−` `・` `。` `․` `__` `..` `. ` and the rest) | 34 + 28 | each strong word joined by the separator, in checks, target, artifact, job and inside checks; `3 passed<s>4 failed` accepted (except `-` and `—`, the field separators) | refused / accepted |

## Lexical axes (kept from r3, every member has a case in `tests/release/pvl_grid.py`)

| Axis | Members | Rule |
|---|---|---|
| A1 strong word, any position | TBD, TBA, TBC, TODO, FIXME, XXX, UNCONFIRMED and LOREM at the start | rules 3(a), 5 |
| A2 weak word at the start | unknown, pending, none, n/a, na, null, nil, placeholder, dummy, later, soon, eventually, someday, asap; lead-only nobody, nothing, nope, noone, never, maybe | rule 3(b) |
| A3 weak word plus more words | `pending scheduling`, `none assigned` | rule 3(b) |
| A4 weak word glued (any separator now) | `none-yet`, `none/yet`, `pending.sh`, `n.a/n.a`, `to/be/scheduled` | rule 3(b) on the first token, B2 |
| A5 lead phrase | `not applicable`, `no job yet`, `to be done`, `will be scheduled later` | rule 3(b)(c) |
| A6 single-letter run, ANY separator | `T.B.D.`, `T/B/D`, `T,B,D`, `T|B|D`, `T·B·D`, `T•B•D`, `T‐B‐D`, `T B D` | rule 3(a), 5 (B1) |
| A7 digit or underscore glued | `TBD_1`, `TBD1`, `MY_TODO`, `FIXME2` | token parts |
| A8 digit look-alikes | `T0D0`, `F1XME` | 0->o, 1->i reading |
| A9 width and format characters | U01..U15 | the scan (B3) |
| A10 confusable letters | U21 and the map; shapes read ASCII | skeleton |
| A11 combining marks | U12 | the fold |
| A12 wrappers | `[TBD]`, `"TODO"`, `(pending)` | separators |
| A13 templates | `<id>`, `{{job}}`, `${JOB}` | rule 6 |
| A14 punctuation-led | `??? later` | rule 4 |
| A15 empty and punctuation-only | ``, `.`, `-`, `…`, U+3164 alone | rules 1, 2 |
| A16 job names nothing runnable | `later`, `re-run the suite`, `ask the operator` | rule 8 job |
| A17 target names no place | `somewhere`, `the usual` | rule 8 target |
| A18 line-level copies | comment, fence, `provisionalXYZ` | line rules |
| A19 due not a time | events, bad dates, wrong digits | rule 8 due |
| A20 trailing placeholder (F3) | `host later`, `host (pending)`, `host? none`, `host (pending scheduler)` | rule 7 |
| A21 shape-only weak-word path (B2) | `none/yet`, `pending/scheduling`, `none.sh`, `pending.sh`, `sometime/maybe` | rule 3(b), weak path |
| A22 path outside root (F2) | `/etc/passwd`, `docs/..`, the root itself | rule 8 job with --root |
| A23 checks without an outcome (F4) | `foo bar baz`, `limit` | rule 8 checks |
| A24 line length and pathological input (F1) | 40k spaces, `(a` repeated, a 4097-character line | MAX_LINE, linear split, timing test |
| A25 job id key and hex minimum (R10, R12) | `A-1` refused, `AB-1` accepted; a 6-digit hex refused, 7 accepted | rule 8 |

## Scoped out (stated, not closed)

- A value of the right shape that is false (an existing path that is not the job; a job id no scheduler knows). The
  checker proves shape, not truth.
- Without `--root` a path is checked for shape only (`PATHS: shape-only` in the output): `scripts/nonexistent.sh` and
  `ask/operator` are accepted there. CON-423's own job runs the checker with `--root .`, where both are refused.
- A command with an option that does nothing (`git -x`) is accepted as a job anchor; a target that is only a target
  word (`board target`) is accepted.
- Cyrillic and Greek letters outside the closed map are not folded to Latin; a word wholly in Cyrillic or Greek is
  accepted (a statement in those scripts is legitimate), so a lower-case look-alike word that is all Cyrillic and not
  in the map (for example a single `ж`) is accepted.
- `checks` accepts prose that holds an outcome word or a digit; the outcome shape proves the form of a signature, not
  that the signature is real.
- English vocabulary only for the weak and outcome words.

## Golden FALSE kept (section 11.4.201(1))

`checks: none of the mutants survives`, `checks: no pending lock remains`, `checks: no review yet, 3 passed`,
`target: na-west-2 runner`, `XTBD-9 run`, `DRAFTS`, `todolist`, the colon-less canon form, hex-only artifacts,
`gate-logic`, `3 passed œ`, `3 passed тест`, `3 passed · 4 failed`, every real line of the tracker (30 of 30, with
and without `--root`).
