# Tracker-intake vehicle, round 11: class inventory

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-11-16 |
| Last modified | 2026-11-16T22:30:00Z |
| Status | active |
| Status summary | The classes behind the round-10 review findings (secret shapes closed one at a time, surviving reviewer mutants, the supersede check split between plan and verify, a plan made against an old main), listed before the round-11 fix was closed (section 11.4.276(C)). Round 11 replaces the per-shape rules with ONE shared primitive and names each member by dimension. |
| Author | round-11 structural fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289); PROVISIONAL |

## Table of contents

- [Why round 11 is structural](#why-round-11-is-structural)
- [K. The shared primitive](#k-the-shared-primitive)
- [S. Spelling dimension](#s-spelling-dimension)
- [E. Encoding dimension](#e-encoding-dimension)
- [L. Layout dimension](#l-layout-dimension)
- [V. Value dimension](#v-value-dimension)
- [N. Negatives and the boundary](#n-negatives-and-the-boundary)
- [M. Mutant classes](#m-mutant-classes)
- [R. Re-mint classes](#r-re-mint-classes)
- [O. Members outside the class, stated](#o-members-outside-the-class-stated)

## Why round 11 is structural

Rounds 8 to 10 closed the secret class one shape at a time, in two separate readers (the lint's named
extractors and the leak scan's token window). Each round's reviewer found new shapes (round 10, `red/r10review_probe_r10_reviewer.txt`: 25 lint
misses, 23 scan misses, and two scan false positives, `bypass=...` and `secretary=...`, from the
scan's substring window). Two readers of the same class drift: a shape fixed in one was not fixed in the
other. Round 11 moves the keyword reading into one module, `scripts/workable-items/secret_canon.py`,
used by both the lint and the leak scan, and reads every input through one pipeline:

1. decode every layer to a fixpoint (dimension E);
2. fold to one canonical spelling (dimension S);
3. split into words, join up to `JOIN_MAX` parts, match the joined form against the vocabulary
   (dimension S);
4. find the value after the key by layout (dimension L);
5. decide by the value's shape (dimension V).

Each reader keeps its own value-SHAPE detectors that need no keyword (vendor token formats, URL
user-info, private-key armour, pgpass lines in the scan; the named extractors in the lint), so a shape
is still read by two different pieces of code where the shape itself carries the evidence. The
keyword reading is shared on purpose: the review asked for one rule set so the two readers can no
longer disagree.

## K. The shared primitive

| Row | Part | Code | Pinned by |
|---|---|---|---|
| K1 | decoding to a fixpoint, at most `SECRET_LAYERS` layers on top, at most `SECRET_MAX_VIEWS` views | `canonical_views()` | canon contracts; census CLASS E* |
| K2 | the fold (NFKC, NFD, marks and fillers dropped, Mc as one placeholder letter, confusables, Latin by name) | `fold()`, `_fold_char()` | census CLASS S* |
| K3 | words and joining (camelCase, single-letter runs, up to 4 parts) | `words()`, `key_spans()` | census CLASS S1, S2 |
| K4 | the vocabulary tiers (strong, short, generic, numeric) and the lookalike wildcard | `word_tier()`, `_wild()` | census CLASS S3 to S8 |
| K5 | the layout reader | `_value_after()`, `_record_hits()`, `_tool_hits()`, URL, XML | census CLASS L* |
| K6 | the value classifier | `credential_value()` | census CLASS V*, N* |

## S. Spelling dimension

| Row | Member | Rule |
|---|---|---|
| S1 | separators between the letters of a key (`p_a_s_s`, `p.a.s.s`, `p a s s`) | runs of 3 or more single letters squashed (`SQUASH_MIN`) |
| S2 | a key split into words (`pass_word`, `pass word`, `mot de passe`, `PassWord`) | joined over up to `JOIN_MAX` parts; camelCase split |
| S3 | case (`PASSWORD`, `PaSsWoRd`) | lower-cased after the fold |
| S4 | confusable letters (Cyrillic, Greek, Coptic, Cherokee, Armenian, Lisu, fullwidth) | `_CONF`, `_SKELETON`, NFKC |
| S5 | marks inside a key (Mn, Me, Cf, fillers) | dropped |
| S6 | spacing marks (Mc) standing for a letter | one placeholder letter `MC_MARK`, read by the wildcard |
| S7 | one stand-in letter in a long key | `_wild()`; at least half of the letters ASCII |
| S8 | the key in another language (multilingual strong list) | `_STRONG_RAW` |

## E. Encoding dimension

| Row | Member | Decoder |
|---|---|---|
| E1 | `\uXXXX`, `\U`, `\u{}`, `\x`, `\x{}`, `\N{NAME}`, octal, `%uXXXX`, CSS `\H ` | `_ESC` |
| E2 | percent layers of any depth | `_PCT`, fixpoint |
| E3 | HTML entities, with or without `;`, named or numeric | `html.unescape` |
| E4 | quoted-printable soft breaks | `_QP` |
| E5 | joined literals (`"pa" + "ss"`, `..`, `||`, `&`, `~`) | `_JOIN` |
| E6 | hex runs in place | `_HEX` |
| E7 | base32 runs | `_B32` |
| E8 | base64 and URL-safe base64 runs that decode to printable text | `_blob()` |
| E9 | NUL characters between letters | removed |
| E10 | a layer inside a layer (any order of E1 to E8) | the fixpoint |

## L. Layout dimension

| Row | Member | Rule |
|---|---|---|
| L1 | `=`, `:`, `:=`, `::=`, `?=`, `+=`, `!=`, `=>`, `==` | `_AFTER` |
| L2 | R arrows `<-`, `<<-` | `_AFTER` |
| L3 | fullwidth `＝` and `：` | `_AFTER` |
| L4 | quoted values with string prefixes `b r u f` and backslash escapes | `_AFTER` |
| L5 | a YAML block indicator or a line break before the value | `_LINEBREAK_VALUE` |
| L6 | `${X:-V}` defaults | `_DEFAULT_EXP` |
| L7 | a setter call `set_password("V")`, `put(...)`, `with(...)` | `_SETTER_BEFORE` |
| L8 | a bare space after an identifier-shaped strong key, a `--flag`, a `set`/`export` command, a directive at line start | space rules |
| L9 | a table row `\| password \| V \|` | the `\|` operator, space tier |
| L10 | a record `{"name": "password", "value": "V"}` | `_record_hits()` |
| L11 | tool forms (curl -u, mysql -p, sshpass, IDENTIFIED BY, htpasswd, openssl pass:, redis-cli -a, docker login -p, mongo -p, netrc, Authorization, pgpass) | `_TOOL_FORMS` |
| L12 | URL user-info | `_URL` |
| L13 | XML elements and `key=`/`name=`/`id=` attributes (the closing tag must match) | `_XML_EL`, `_XML_ATTR` |
| L14 | a `make` `!=` shell assignment | the command is scanned |
| L15 | a triple-quoted or parenthesised literal | the quote readers |
| L16 | the key after a qualifier (`db_password`, `PGPASSWORD`, `client_secret`) | `STRONG_SUFFIX`, `_QUAL_KEY` |

## V. Value dimension

| Row | Member | Verdict |
|---|---|---|
| V1 | length 8 to 4096 | in range is read |
| V2 | masks, placeholders, paths, references (`$X`, `${X}`, `%(x)s`, `@Annot(`, vault and file schemes) | not a value |
| V3 | a single-quoted `$Literal` (shell keeps it literal) | a value |
| V4 | a value starting with `- < > { [ ( \|` | not a value |
| V5 | spaces inside a value | only quoted, strong, after an assignment or `:` |
| V6 | short and generic keys | need a letter plus a digit or a special character; identifiers, tickets and versions are not values |
| V7 | the space tier | needs a letter and a digit |
| V8 | a secret-store reference by name (`kms:DB_PASSWORD`, `k8s:DB_PASSWORD`) | not a value: the shape `scheme:UPPER_NAME` (`_REF_NAME`), not a list of schemes |
| V9 | an identifier after a short or generic key (`case_one_a1b2`, `test_login_2fa`, `lint_suite_2`) | not a value: lower-case alphanumeric parts with at least one word part of three letters (`_IDENT`); a random mixed string (`zq7_k9w2x`) has no such part and is read |

## N. Negatives and the boundary

| Row | Member | Verdict |
|---|---|---|
| N1 | a keyword as a substring of another word (`bypass`, `secretary`, `passage`, `compass`) | not a key: words are matched whole, after the fold |
| N2 | a meta tail (`password_policy`, `token_hash`, `password_sha256`) | not a key: an attached word after the key cancels it unless it is in `TAIL_OK`, a number or a version |
| N3 | a negative qualifier (`public_key`, `primary_key`, `cache_key`) | not a key (`KEY_NEGATIVE`) |
| N4 | prose (`the password is changed`) | no assignment, no value |
| N5 | the reviewer's 25 round-10 negatives | 0 reported (fixture module `secret_shape_fixtures_r11.py`) |
| N6 | a count after a kind name (`gcp-api-key 24, private-key 12`) | not a key: a number separated by a space never joins the key (`key_spans`); an attached number (`api_key_24`, `key24`) still does |
| N7 | a URL user-info placeholder (`https://<user>:<password>@<host>`) | not a value: the URL reader applies `is_placeholder()` and skips values starting with `$ { < [ (`, in the shared reader and in the scan's own URL detector |
| N8 | a short key attached to a word that makes an English word (`byPass`, `oAuth`, `bypwd`, `BYPWD`) | not a key (`SHORT_JOIN_NEGATIVE`, ported from the round-10 lint, lost in the round-11 rewrite and found by the census); `dbPass`, `by_pass` and `ldappwd` are keys |
| N9 | the suffix rules (`dbpassword`, `ldappwd`) on a form joined across parts (`x bypwd` read as `xbypwd`) | not a key: the suffix rules read one written word only |
| N10 | a short key, a colon and an unquoted value (`PASS: case_one`, `pw: see below`) | a label, the census boundary B; quoted, or after `=` and the other operators, it is read |

## M. Mutant classes

| Row | Class | Treatment |
|---|---|---|
| M1 | a reviewer mutant whose target text exists in the round-11 code | adopted verbatim into the harness; must be KILLED, or proven equivalent with a recorded run |
| M2 | a reviewer mutant whose target text the round-11 rewrite removed (v10 scan `window_hits`, v10 lint per-shape knobs moved into the shared module) | STALE as written; its INTENT is ported to the same knob in `secret_canon.py` and that port must be KILLED |
| M3 | own mutants, one per shared-primitive part (K1 to K6) | must be KILLED |
| M4 | a mutant of the shared module that one reader's own fixtures do not reach (found in the scan harness run of 2026-11-16: 16 canon mutants survived the scan fixtures) | the shared module's contract suite is the oracle of both readers: the scan harness runs it on the mutated copy after its own fixtures and names the killing oracle; a mutant no contract kills gets a contract (K6c: K6-version now checks versions past the length floor) |

## R. Re-mint classes

| Row | Member | Treatment |
|---|---|---|
| R1 | plan and verify reading the supersede backing by two different checks | one check, `dup_rule_errors()`, used by both |
| R2 | `--supersede VID=VID` with a SAME-DEFECT verdict | covered by the one check; witness `runs/rma_witness.txt` of the round-10 review |
| R3 | the shared-path basename minimum, the closed-target count, the bare target-own form, a target-own id the target lacks | each with its own failing test (RM-e, RM-f, RM-g, RM-j) |
| R4 | a plan made against an old main | re-planned against the current origin main; dedupe verdicts per section 11.4.214 |

## O. Members outside the class, stated

- A credential with no key word and no known vendor shape (a bare random string on its own line) is
  not read by either reader. It cannot be told apart from an identifier or a hash without context.
- A key built at run time (`k = "pass" + suffix`) is not read: the key is not in the text.
- A value shorter than 8 characters is not read (a mask and a placeholder can be that short).
- Encodings outside E1 to E10 (gzip, encryption, a custom alphabet) are not read.
- The evidence for every row is gate-logic (section 11.4.289): fixtures and generated members, never a
  live leak.
