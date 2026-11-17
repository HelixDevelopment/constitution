# Tracker-intake vehicle, round 10: class inventory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-16 |
| Last modified | 2026-11-16T09:00:00Z |
| Status | active |
| Status summary | The classes behind the round-9 review findings R9-1 to R9-4 (secret lookalikes, the "word" meta word, unpinned front-end knobs), listed before the round-10 fix was closed (section 11.4.276(C)). Each member names the rule that closes it, or the reason it is outside the rule, and the test that pins it. |
| Author | round-10 structural fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289); PROVISIONAL |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [L. The secret-shape class, round-10 members (R9-1, R9-2)](#l-the-secret-shape-class-round-10-members-r9-1-r9-2)
- [B. The boundary after round 10](#b-the-boundary-after-round-10)
- [V. Reviewer and own mutants (R9-3)](#v-reviewer-and-own-mutants-r9-3)
- [E. Equivalent mutants, with evidence](#e-equivalent-mutants-with-evidence)
- [S. The independent leak scan](#s-the-independent-leak-scan)
- [P. Cost](#p-cost)

## How the inventory was built

- The class is "a credential written in a form the lint does not read". Round 9 named its members by
  the reviewer's 40 positives, so its census reported gap=0 over the classes it listed and stayed blind
  to the rest (review R9-1). Round 10 names the class by the ways a form can differ from the plain
  `key=value` line, and enumerates each way over every key, letter or layer depth, not by example:
  (a) how the key is SPELLED (split words, stand-in letters, confusables, other languages, marks);
  (b) how the text is ENCODED (escapes of every form, percent and entity layers of any depth, base64);
  (c) how the pair is LAID OUT (table rows, `set` statements, R arrows, triple quotes, parenthesised and
  joined literals, `type=` attributes); (d) what the VALUE is (identifiers, colons, tickets, versions,
  references, digests).
- The front end (`secret_views()` in `scripts/workable-items/intake_lint.py`) now decodes to a FIXPOINT
  (every transform applied again until the text stops changing, at most `SECRET_FIXPOINT_STEPS`), adds
  a base64 view, folds a confusable skeleton (Coptic, Cherokee, Armenian, Lisu letters that look Latin),
  drops spacing marks (Mc) with the other marks, and adds a multilingual lexicon
  (`NATIVE_STRONG_HEADS`, 29 words) to the strong heads. "word" is no longer a meta word (R9-2).
- `tools/secret_class_census.py` (copied from round 9 and extended by `members_r10()`) generates the
  members of L36 to L52 below, tags each with its row, and prints one `CLASS` line per row. A row with
  no member is BLIND (exit 3), so a count of zero can never read as "no gap".
- `probes/probe_v9_reviewer.py` is the round-9 reviewer's probe (40 positives, 25 negatives, fake
  values built from fragments). Its RED on the round-9 head is `red/probe_v9_reviewer_on_v9.txt`
  (lint_miss=18, scan_miss=12).

## L. The secret-shape class, round-10 members (R9-1, R9-2)

| Row | Member | Round 9 | Round 10 rule | Tests |
|---|---|---|---|---|
| L36 | split heads: `pass_word`, `pass-word`, `pass.word`, `PASS WORD`, `mot de passe` | missed ("word" a meta word) | `SECRET_SPLIT_HEADS`; "word" removed from `META_WORDS` | census CLASS L36 (members=48 hit=24 gap=0 fp=0); `r10-own-*`; mutants XL3, R10-5 |
| L37 | stand-in letters in a head: at most half of the letters | 3 of 5 allowed (XL4) | `_like()`: `2 * odd <= len(h)`, heads of 5 or more letters | contracts C2 to C4; census CLASS L37 (members=286 hit=177 gap=0 fp=0); XL4, XL4b, XL5 |
| L38 | an identifier-shaped value after a strong key (`dbpass_prod2`) | read only after a generic key | `credential_value`: the identifier exclusion only after short and generic keys | contract C7; census CLASS L38 (members=6 hit=3 gap=0 fp=0); XL6 |
| L39 | a colon inside a value (`Qz7k:Wm4Rt9p`) | read as a reference | a reference URI needs `/` or `#` | contract C7; census CLASS L39 (members=4 hit=2 gap=0 fp=0); XL9 |
| L40 | escapes on any letter of the key: `\u{70}`, `\U00000070`, `\x{70}`, `\x70`, octal | partly | `_ESC` reads brace, long and hex escapes | census CLASS L40 (members=48 hit=48 gap=0 fp=0); R10-9, R10-10 |
| L41 | base64 of a whole assignment (padded, unpadded, URL-safe) | missed | `SECRET_DECODE_BASE64` (`_v_base64`) | census CLASS L41 (members=11 hit=9 gap=0 fp=0); R10-2 |
| L42 | percent and entity layers past the closure depth, an entity without `;`, a named entity | missed past depth 3 | the fixpoint view; `_v_entities` uses `html.unescape` and gives a view only when it changes the text | contracts C5, C8; census CLASS L42 (members=13 hit=13 gap=0 fp=0), `entity *`; R10-1, R10-20, XL13 port |
| L43 | confusable letters in place (one per position, lower and upper case) | missed outside the fold | the skeleton fold (`_SKELETON`) | census CLASS L43 (members=35 hit=35 gap=0 fp=0); R10-7 |
| L44 | the key in another language (Serbian, Russian and 27 others) | missed | `NATIVE_STRONG_HEADS` added to the strong heads | contract C6; census CLASS L44 (members=261 hit=116 gap=0 fp=0); R10-6 |
| L45 | a markdown table row `\| password \| V \|` | missed | rule `table-row-pair` (line rule) | census CLASS L45 (members=27 hit=9 gap=0 fp=0); R10-11 |
| L46 | a Tcl or Expect `set password V` | missed | rule `set-command` (line rule) | census CLASS L46 (members=9 hit=6 gap=0 fp=0); R10-12 |
| L47 | the R arrows `<-` and `<<-` | missed | `_SEP_Q` | census CLASS L47 (members=4 hit=4 gap=0 fp=0); R10-17 |
| L48 | a TOML triple-quoted value, a parenthesised literal, literals joined across a newline | missed | `SECRET_TRIPLE_QUOTES`, `SECRET_PAREN_LITERAL`, the join across `\s` | census CLASS L48 (members=16 hit=16 gap=0 fp=0), `paren *`, `join *`; R10-3, R10-4, R10-16 |
| L49 | HTML `<input type="password" value=…>` | missed | `type` among the attribute keys | census CLASS L49 (members=4 hit=2 gap=0 fp=0); R10-19 |
| L50 | a ticket id, a version, a secret-store reference after a key | (lookalikes) | `_TICKET_VALUE`, `_VERSION_VALUE`, `_REF_SCHEME` are not values | contract C7; census CLASS L50 (members=22 hit=0 gap=0 fp=0), `version *`, `ref-scheme *`; R10-13 to R10-15 |
| L51 | a digest property of the credential (`password_sha256=…`) | reported | `sha256` and the other digests are meta words | census CLASS L51 (members=21 hit=0 gap=0 fp=0); R10-18 |
| L52 | spacing marks (Mc) inside a key (Devanagari, Bengali vowel signs) | missed | Mc dropped with Mn and Me | census CLASS L52 (members=6 hit=6 gap=0 fp=0); R10-8 |

## B. The boundary after round 10

Rows B1 to B39 of rounds 8 and 9 hold unchanged. New rows:

| Row | Member | Verdict | Reason |
|---|---|---|---|
| B40 | the four round-9 reviewer negatives the lint reports (n04 `credentials: aws-profile-prod2`, n06 `pin=2026`, n18 a UUID session, n19 a cookie value) | reported (kept as hit rows) | each is a value after a key word that names a credential; reading them as clean needs knowledge of the value's meaning, which a shape rule cannot have. Kept visible as rows B41 to B44 so silencing one is a reviewed edit |
| B41 | `credentials: <identifier>` | reported | a strong key; the identifier exclusion stays off for strong keys (XL6) |
| B42 | `pin=<4 digits>` | reported | a PIN is digits |
| B43 | `session=<uuid>` | reported | a session id is a credential |
| B44 | `cookie=<value>` | reported | a cookie value is a credential |
| B45 | the independent scan's three-layer closure | removed | on every shared fixture row and on the reviewer probe the closure found nothing the fixpoint did not, so its mutants could not be killed (`runs/scanmut_1.txt`, 10 survivors); replaced by the fixpoint alone, each decoding of the fixpoint mutated (`runs/scanmut_2.txt`) |

## V. Reviewer and own mutants (R9-3)

- Reviewer lint mutants XL2, XL3, XL4, XL5, XL6, XL9 and the XL13 port are in the lint harness
  (`tests/workable_items/test_intake_lint_mutations.sh`) and must be KILLED; XL2, XL4, XL5 and XL13 are
  pinned by function contracts (`tests/workable_items/test_secret_frontend.py`, C1 to C9), because no
  fixture row reaches the knob they change. C9 holds three closure witnesses (found by
  `tools/equiv_check.py`-style fuzzing): with the 3-layer closure removed the lint misses them, so the
  closure is load-bearing (`runs/equiv_CLOSURE0.txt`: hit_differences=36) and OL9 and R8-34 are killed.
- Result (`runs/lint_mutations_1.txt` to `_3.txt`): 247 mutants, 3 equivalent, all killed as declared. XL13 changed in shape: round 10 gates the entity view on
  `html.unescape` changing the text, so the port removes that gate.
- Own mutants R10-1 to R10-20, one per part round 10 added.
- Scan mutants: 61 in `tools/leak_scan_mutations.py`, including `r10_*` and `fix_*` (one per decoding of
  the fixpoint). Result (`runs/leak_scan_mutations_1.txt`): mutants=61 bad=0.

## E. Equivalent mutants, with evidence

| Id | Edit | Evidence |
|---|---|---|
| XL12 | U+3164 dropped from `_FILLERS` | `runs/equiv_XL12.txt`: NFKC folds U+3164 to U+1160, which stays a filler |
| RV2 | the escape view without NFKC | `runs/equiv_RV2.txt` |
| LR2 | `SECRET_NFKC` off | `runs/equiv_LR2.txt` |

## S. The independent leak scan

`tools/leak_scan.py` reads the same classes by its own code (no import of the lint): the fixpoint of
five decodings, its own confusable fold, the native word list, split words, the `set` reading, a whole
colon value, and a skip for digest and property tails. Its own specification rows (`SCAN_POSITIVE`,
`SCAN_NEGATIVE` in `tools/leak_scan_test.py`) gained four rows that kill the hex-escape, `set`, and
digest-tail mutants.

## P. Cost

Measured by `tools/time_lint.py` (output `runs/lint_cost.txt`; the round-9 lint is `git show 8f688bf1:scripts/workable-items/intake_lint.py`), best of 3 wall-clock runs on a shared host under load about 35: the round-10 lint against the round-9 lint (HEAD 8f688bf1) on the 413 shared fixture texts (0.131 ms against 0.108 ms per text), 400 prose lines (0.206 against 0.215 ms) and two 40,000-character lines (82 against 101 ms per line). The round-10 lint is therefore within about 1.2x of round 9 on these inputs. The round-9 review note R9-12 (about 7x slower than round 8, 5.38 s against 0.79 s on a 40k-character line) was measured on an input this pack does not have; it is not reproduced here and stays UNCONFIRMED for that input. The cost is linear in the line length on the two long lines measured. Census run time (`runs/census_1.txt`, 319,279 members): all 17 round-10 classes gap=0 fp=0.
