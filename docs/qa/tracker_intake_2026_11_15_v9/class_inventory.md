# Tracker-intake vehicle, round 9: class inventory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T20:00:00Z |
| Status | active |
| Status summary | The classes behind the round-9 review findings F1 to F5, enumerated before the round-9 fix was closed (section 11.4.276(C)). Each member names the rule that closes it, or the reason it is outside the rule, and its test. |
| Author | round-9 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289) |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [L. The secret-shape class, round-9 members (F1, F5)](#l-the-secret-shape-class-round-9-members-f1-f5)
- [B. The boundary after round 9](#b-the-boundary-after-round-9)
- [V. Reviewer and own mutants (F4)](#v-reviewer-and-own-mutants-f4)
- [E. Equivalent mutants, with evidence](#e-equivalent-mutants-with-evidence)
- [R. Landing reconciliation (F2, F3)](#r-landing-reconciliation-f2-f3)

## How the inventory was built

- The round-8 lint matched the KEY of a keyed credential against lists of spellings written into each
  extractor's regular expression. Every spelling outside the lists was a silent miss: the round-9
  reviewer's probe (`red/probe_r9_on_v8.txt`) shows 36 of 50 credential shapes missed and 4 of 20
  lookalikes reported. Round 9 keeps the three stages of round 8 and REPLACES the key half of stage 2
  (section 11.4.276(E)): every extractor now yields a key TOKEN, and one classifier, `key_tier()`,
  splits the token into words and decides the tier from them (head words, qualifiers, property words;
  see the comment block above `STRONG_HEADS` in `scripts/workable-items/intake_lint.py`). The front end
  gained the removal of combining and enclosing marks and Hangul fillers, a Latin-by-name fold, and a
  closure of up to three decoding layers (escapes, octal, percent, HTML entities, joined literals).
- `tools/secret_class_census.py` (copied from round 8 and extended by `members_r9()`) adds the
  dimensions the reviewer's shapes showed missing; its docstring lists them. The census's own RED is
  `red/census_r9_on_v8.txt` (the round-9 census run on the round-8 lint).
- `tests/workable_items/secret_shape_fixtures.py` holds the round-9 reviewer's 50 shapes (`r9-pos-*`)
  and 20 lookalikes (`r9-neg-*`) verbatim, every earlier row, and 21 adopted rows (`r9-adopt-*`, one per
  reviewer witness and one per own mutant that needed a case, the lint's or the independent scan's). 288 rows; run alone the module checks
  its own invariants (labels once, every hit row with its `EXPECT_RULES` tuple, every miss row with a
  reason, the reviewer lists at their verbatim sizes).

## L. The secret-shape class, round-9 members (F1, F5)

The rows L1 to L16 of round 8 (`../tracker_intake_2026_11_15_v8/class_inventory.md`) still hold; their
fixtures are unchanged. Round 9 adds:

| # | Member | Round-8 result | Round-9 rule | Tests |
|---|---|---|---|---|
| L17 | a key with a suffix after the head (`DB_PASSWORD_PROD`, `API_KEY_V2`, `password2`, `SECRET_KEY_BASE`) | missed | `key_tier()`: a head word followed only by non-property words | `r9-pos-p01`, `p02`; census `suffix *` |
| L18 | a property suffix that makes a non-key (`password_policy`, `token_count`, `passwordless`) | (not read, by luck) | `META_WORDS`, `SUFFIX_HEADS` needs the head at the word end | `r9-neg-n13`, `n17`; census `suffix-neg *` |
| L19 | a string prefix before the value quote (`b"…"`, `f'…'`, `r"…"`) | missed | the value quote may carry a string prefix | `r9-pos-p03` to `p05`; census `strprefix *` |
| L20 | string concatenation of a value (`"ab" "cd"`, `+`, `.`, `\|\|`) | missed | front end: joined-literals view (`SECRET_JOIN_LITERALS`) | `r9-pos-p06`, `p07` |
| L21 | encoding layers on the key: HTML entities, a double percent layer, an octal escape, an escaped full-width letter | missed | front end: a closure of up to `SECRET_VIEW_LAYERS` (3) decoding layers | `r9-pos-p16` to `p19`, `p43`; `r9-adopt-rv2-*`, `r9-adopt-r834-*`; census `layer *` |
| L22 | invisible marks inside a key (combining marks, U+034F, variation selectors, a Hangul filler) | missed | front end: NFKD, then marks (Mn, Me) and fillers removed (`SECRET_STRIP_MARKS`) | `r9-pos-p20` to `p22`; census `invisible *` |
| L23 | Latin lookalikes (Latin alpha, small capitals) and letters the fold does not know (Armenian, Cherokee) | missed | the Latin-by-name fold (`SECRET_FOLD_LATIN_NAMES`); one unknown non-ASCII letter may stand for one letter of a long head (`SECRET_WILDCARD`) | `r9-pos-p23` to `p26`; census `lookalike-latin *`; closes round-8 B18 |
| L24 | camelCase short keys (`userPass`, `adminPwd`) and the English words that join a short key (`byPass`, `oAuth`) | missed / not read | the camel split and `SHORT_JOIN_NEGATIVE` | `r9-pos-p14`, `p15`; census `camel-short *` |
| L25 | bracket keys (`config[password]`), dot-joined and prefix-joined heads (`api.key`, `PGPASSWORD`) | partly missed | the key token admits brackets and dots; `SUFFIX_HEADS` | `r9-pos-p47`; `r9-adopt-lr1-*`, `lr19-*` |
| L26 | qualified keys (signing, encryption, master, account key) and the non-credential qualifiers (public key, page token) | missed / not read | `KEY_QUALIFIERS`, `KEY_NEGATIVE`, `TOKEN_QUALIFIERS`, `TOKEN_NEGATIVE` | `r9-pos-p13`, `p28` to `p30`; `r9-adopt-ol4-public-key`, `ol1-*`; census `qualified *`, `qualified-neg *` |
| L27 | bare short keys (`key`, `session`, `cookie`) and the numeric `pin` | B9 (outside) | `SHORT_HEADS`, `NUMERIC_HEADS`; closes round-8 B9 | census `short-bare *`, `pin *`; `r9-adopt-rv10-*`, `r85-*` |
| L28 | more tool flags (openssl `-pass`, redis-cli `-a`, docker login `-p`, htpasswd `-b`, mongo `-p`, gpg `--passphrase`) | missed | the tool-flag extractor | `r9-pos-p10` to `p12`, `p33`, `p41`, `p50`; census `tool *`, `shortflag *` |
| L29 | a quoted value after whitespace (SQL `IDENTIFIED BY '…'`, `WITH PASSWORD '…'`) | missed | the quoted-after-whitespace extractor | `r9-pos-p08`, `p09`; census `space-quoted *` |
| L30 | the Authorization header with any scheme, and a 16-character bearer token | missed | `authorization-header` (`_x_authorization`): any scheme but Basic, a value of 8 characters with a letter and a digit; a Bearer or Token value of 20 or more stays the `bearer-token` rule's | `r9-pos-p31`, `p32`; census `authz *`; closes round-8 B12 |
| L31 | a tab inside a value | (read) | a tab ends a value: a table cell, not a credential (review RV12) | `r9-adopt-rv12-tab-inside-value`; `r9-pos-p46` (tab as separator); census `tab-in-value *` |
| L32 | secret-manager references (`vault:…`, `ref+…://`, `@Microsoft.KeyVault(…)`, SOPS `ENC[…]`) and identifier values (`lint_suite_2`) (F5) | reported | `credential_value`: a reference or an identifier is not a value | `r9-neg-n01` to `n05`, `n20`, `n03`; census `reference *`, `identifier *` |
| L33 | a value of exactly 8 characters after a short key (the length boundary) | (read) | unchanged; the census now has the member (review RV4) | `r9-adopt-rv4-short-key-length-8`; census `len8 *` |
| L34 | escaped quotes in a plain string, a backtick escape before the close (`\"…\"`, `` `\q…\` ``) | read | the quoted-value grammar; LR5 is killed by these rows | `r9-adopt-lr5-*` |
| L35 | the independent leak scan's own reading (F1 D3): a qualifier glued before `token`/`secret` (`PGid_token`) and a decomposed letter that folds to another Latin letter (`pέssword`) | missed by the scan, reported by the lint | `tools/leak_scan.py`: `glued` and a widened `_one_odd`; its mutation harness remapped (10 stale mutants) and extended to 50 | `r9-adopt-ol1-*`, `r9-adopt-scan-*`; `runs/leak_scan_mutations_*.txt` |

## B. The boundary after round 9

Round-8 rows B1 to B8, B10, B11, B13 to B17, B19 and B20 hold unchanged; their reasons are in the round-8
inventory. B9 (bare short keys), B12 (a short Bearer token) and B18 (lookalikes outside the fold) are closed by
L27, L30 and L23; a Bearer value under 8 characters, or without a letter and a digit, stays outside
(B10). The census counts of the boundary
members of the round-9 lint are in `runs/census_1.txt` (`miss_boundary=`); the expected verdict of
every boundary member is written in the census next to its label.

## V. Reviewer and own mutants (F4)

The mutant lists, with one line each, are the arrays in `tests/workable_items/test_intake_lint_mutations.sh`
and `tests/workable_items/test_remint_ids_mutations.sh`; the verdict of every mutant is in
`runs/lint_mutations_full.txt` and `runs/remint_mutations_full.txt`.

- Reviewer round 9: RV1 to RV20 (lint), RW1 to RW8 (re-mint), adopted verbatim where their text still
  exists and ported onto the same rule of the round-9 code otherwise (the harness entry says so).
- Earlier reviewers' RL1 to RL10, RR1 to RR9 and the older sets are kept.
- Own mutants of round 9: OL1 to OL16 (lint) and OR1 to OR17 (re-mint), one per new rule or branch.
- Stale mutants: the harness's own stale check reads only plain single-quoted entries; it missed eight
  `$'...'` entries whose text round 9 replaced (LN4, LS11, LR1, LR3, LR4, LR6, LR18, LR19). They are
  remapped onto the round-9 code, each on the same idea as before.
- RV2, RV12 and RW3, which the reviewer reported alive: RV12 is killed by `r9-adopt-rv12-*`; RW3 by two
  new cases of the re-mint suite (`R9-RW3: verify reads both ends of an item's foreign range as foreign`,
  and the same for `--foreign`), with a control; RV2 is now equivalent, see section E.
- RW6 (width fixed at 2), called equivalent for unpadded ids by the reviewer, is killed: two cases of the
  re-mint suite mint under a prefix whose ids are one and three digits wide.
- LR5 survived the first full run of round 9 and was not equivalent (`runs/equiv_LR5.txt`: 14 differing
  corpus members); the two `r9-adopt-lr5-*` rows kill it.
- OR1, OR11, OR12 and OR14 survived the first full re-mint run of round 9 (`red/remint_mutations_or_survivors.txt`:
  204 mutants, 4 FAIL). OR1 was equivalent on the suite's one supersede case, whose superseded id is the
  vehicle's last own id (minting it too changes no other id); OR11, OR12 and OR14 had no case that edits
  the plan after it was made. Five new cases of the re-mint suite (a supersede of a middle own id, and three
  plans edited after `plan`) kill all four (`runs/remint_mutations_or_rerun.txt`). The other 200 verdicts are
  those of the full run; the full harness was not run again with the five new cases (they only add kills).

## E. Equivalent mutants, with evidence

An equivalent mutant is not run; it is listed in the harness's `equivalent` array with its evidence
file. The harness checks that the edit still matches the code once and that the evidence was made for
that exact edit (for the lint, an `EDIT edit_sha256=` line), so a later change re-opens the question.

| Mutant | Why it cannot change the answer | Evidence |
|---|---|---|
| RV2 (escape view without NFKC) | `_clean()` applies NFKD, removes marks and applies NFKC to every view; NFKD(NFKC(s)) = NFKD(s), so the NFKC before `_clean` is absorbed. The reviewer's witness (an escaped full-width key) is the fixture `r9-adopt-rv2-escaped-fullwidth-key` and is reported by the lint with and without the edit | `runs/equiv_RV2.txt`: views and rule names equal on 2742618 strings (census, fixtures, 200000 seeded strings, every code point inside and before a key); control needle ok |
| LR2 (SECRET_NFKC off) | the same identity for the first view | `runs/equiv_LR2.txt`, same corpus, control needle ok |
| RW2 (collision with a target id not refused) | every new id is `start + k` with `start` above the highest target id of the prefix, and a target key equal to a new id would match the prefix with the same number | `runs/equiv_RW2.txt`: `tools/equiv_rw2.py` runs the tool's own three lines on 200000 random cases, no collision; its control (`+ 0`) collides |

Honest limit: an equivalence on a finite corpus is evidence, not proof; for RV2 and LR2 the argument is
the normalization identity, for RW2 the arithmetic argument in the tool's docstring.

## R. Landing reconciliation (F2, F3)

| # | Member | Fix | Test |
|---|---|---|---|
| R1 | a vehicle item that the target already holds (vehicle CON-339 = main CON-313) is minted again | `remint_ids.py plan --supersede VEHICLE=TARGET`: the vehicle id lands on the target item, no row is minted, every reference is rewritten | re-mint suite `--supersede` cases; mutants OR1 to OR4, OR14 |
| R2 | a target text that names a vehicle id that will be re-bound by the landing (main CON-313 says "CON-339") | XREF-REBOUND and XREF-SUPERSEDED are refusals of the plan; `--annotate-foreign TID` appends a Foreign ids line to the target item that declares the named id foreign, and the refusal no longer applies | re-mint suite; mutants OR5, OR6, OR7, OR10, OR13, OR17 |
| R3 | the vehicle's Duplicate check lines were written against the base, not the target | `--dup-resolution FILE`: one verdict per (vehicle item, target item) pair that shares a path; DISTINCT, DISTINCT-but-similar or UNDECIDED with a reason that names no id; the plan appends the landing checks to the Duplicate check line | re-mint suite; mutants OR8, OR9, OR11, OR15, OR16; `remint/dup_resolution_*.tsv` |
| R4 | the landing simulation linted the vehicle database, not the landed one | `tools/simulate_landing.sh` lints the landed database over the landed ids (`landed_lint.txt`, must PASS); the supersede targets and annotated items are main's own items, so their findings are compared with the same lint on the unlanded target and only a finding the landing adds counts (`landed_touched_lint.txt`: `NEW=0`; a lint run with no RESULT line makes it BLIND) | `remint/main_*/landed_lint.txt`, `landed_touched_lint.txt` |
| R5 | SHARED-PATH against other open items | kept as a real check (two open items naming one file is information a lander needs): the landed item's Duplicate check line must name the other item, which the landing checks of R3 do; the check is not weakened | the lint suite's SHARED-PATH cases; `landed_lint.txt` PASS |
