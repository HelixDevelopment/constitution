# Tracker-intake vehicle, round 8: class inventory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T14:00:00Z |
| Status | active |
| Status summary | The classes behind the round-8 review findings N1 to N4 and N6, enumerated before the round-8 fix was closed (section 11.4.276(C)). Each member names the rule that closes it, or the reason it is outside the rule, and its test. |
| Author | round-8 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289) |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [L. The secret-shape class (N1, N2)](#l-the-secret-shape-class-n1-n2)
- [B. The boundary: members outside the rule, with reasons](#b-the-boundary-members-outside-the-rule-with-reasons)
- [V. Reviewer mutants (N3)](#v-reviewer-mutants-n3)
- [D. Guarded deletes and printed fragments (N6)](#d-guarded-deletes-and-printed-fragments-n6)

## How the inventory was built

- The round-7 lint was a list of regular expressions, one per syntax. Round 8 replaced it (section
  11.4.276(E), replace, do not layer) by three stages in `scripts/workable-items/intake_lint.py`:
  1. a front end, `secret_views`: NFKC, removal of format characters (category Cf), a fold of Cyrillic
     and Greek lookalike letters to Latin, a view with backslash escapes decoded and a view with
     percent-encoding decoded; each stage has a switch (`SECRET_STRIP_FORMAT`, `SECRET_FOLD`,
     `SECRET_DECODE_ESCAPES`, `SECRET_DECODE_PERCENT`) that a mutant turns off;
  2. keyed extractors (`KEYED_EXTRACTORS`), one per syntax, each yielding a key tier (strong, generic,
     short) and a candidate value;
  3. one value classifier, `credential_value`, that decides whether the candidate is a value
     (length, a letter and a digit where the tier needs it, never a reference, mask, placeholder, path
     or code expression).
- `tests/workable_items/secret_shape_fixtures.py` is the shared fixture list: the reviewer's 51
  credential shapes and 52 benign lookalikes and 6 backslash values (round-8 review probes), verbatim,
  plus the fixer's own rows (one positive and one negative per new rule and per front-end stage, and
  the rows the reviewer mutants need, and six rows added for the four own-mutant survivors of the first harness run). 195 rows; each "hit" row carries its exact rule list
  (`EXPECT_RULES`, frozen), each "miss" row names its section-B reason or `negative`.
- `tests/workable_items/test_secret_shapes.py` runs the list through the lint (labels only); the lint
  suite runs it first. On the round-7 lint it reports 76 failures (`red/shapes_on_v7.txt`).
- `tools/leak_scan.py` is a second, independent implementation (it imports nothing from the lint: a
  token window after a credential word, its own fold table and its own decoders). `tools/leak_scan_test.py`
  runs the same fixture list through it: every "hit" row must be found (0 missed); miss rows it reports
  are counted as leads, not judged. This answers the review's point that the round-7 leak scan imported
  the lint's own patterns as its only oracle.
- `tools/secret_class_census.py` generates the product key tier x case x prefix x key quoting x
  separator x value quoting x value kind, now with backslash values, plus the members of every round-8
  syntax (argument pair, setter, XML attribute pair and entry, short flags, YAML block scalars, pgpass,
  percent-encoded separators, URL scheme case, format characters and lookalikes in a key): 317674
  members. Round-8 lint: gap=0 fp=0 (`runs/census_*.txt`); round-7 lint: gap=24733 fp=23078
  (`red/census_on_v7.txt.gz`), which is the census's own proof that it sees a gap (section 11.4.273).
  It prints labels only, never a generated string.

## L. The secret-shape class (N1, N2)

| # | Member | Round-7 result | Round-8 rule | Tests |
|---|---|---|---|---|
| L1 | a quoted value that holds a backslash (`"ab\x…"`, JSON `\\`, `é`, `\t`, `\/`; review N1, a round-7 regression) | missed | `_QVAL` reads an escape sequence as part of the value; the escape view decodes it | `rv-bs-*` (6), `own-bs-*` (7); mutant R8-7 |
| L2 | `define('DB_PASSWORD','…')`, `getenv`/`.get(key, default)`, a JSON array pair | missed | `argument-pair` (`_x_argument_pair`) | `rv-pos-php-define`, `rv-pos-getenv-default-*`, `rv-pos-env-json-array`, `own-argpair-*`; mutants R8-8, R8-9 |
| L3 | `setPassword("…")`, `set_api_key('…')` | missed | `setter-call` (`_x_setter`) | `rv-pos-setter-java`, `own-setter-*`; mutants R8-10, R8-11 |
| L4 | .NET `<add key="Password" value="…"/>`, `<param name=… value=…>`, `<entry key=…>…</entry>` | missed | `xml-attribute-pair` (`_x_xml_attr`); the entry's closing tag must close the element | `rv-pos-dotnet-appsettings`, `rv-pos-xml-entry-key`, `own-xmlattr-*`; mutants R8-12, R8-13, R8-14 |
| L5 | `mysql -pVALUE`, `mysqldump -p…`, `sshpass -p VALUE`, `curl --user u:…` | missed | `short-flag-value` (`_x_short_flag`); `-P` (port) is case-sensitive | `rv-pos-mysql-p-joined`, `rv-pos-sshpass-p`, `rv-pos-curl-u`, `own-shortflag-*`, `own-r818-port`, `own-r818-port-letters`; mutants R8-15 to R8-18 |
| L6 | a YAML block scalar (`|`, `>`, with `-`, `+` or a digit) | missed | `yaml-block-scalar` (`_x_yaml_block`), every key tier | `rv-pos-yaml-*`, `own-yaml-*`; mutants R8-19, R8-20 |
| L7 | a pgpass line `host:port:db:user:password`, `*` fields | missed | `pgpass-line` (`_x_pgpass`, a whole line; the value needs a letter and a digit) | `rv-pos-pgpass-line`, `own-pgpass-*`; mutants R8-21, R8-22 |
| L8 | `%3D` / `%3A%20` separators and a percent-encoded key | missed | the percent view of the front end | `rv-pos-urlencoded-eq`, `own-pct-*`, `own-r834-escape-then-percent`, `own-r834-json-escape-then-percent` (percent decoding of the escape view); mutants R8-4, R8-34 |
| L9 | an upper- or mixed-case URL scheme (`HTTPS://u:p@h`) | missed | `url-userinfo-password` case-insensitive | `rv-pos-url-upper-scheme`, `own-url-*`; mutant R8-23 |
| L10 | lookalike letters in a key (Cyrillic, Greek), mathematical and circled letters | missed | the fold table (`_FOLD`) after NFKC | `rv-pos-homoglyph-cyrillic-a`, `rv-pos-math-bold-key`, `rv-pos-circled-letters`, `own-greek-omicron`, `own-cyrillic-upper`; mutants R8-2, R8-5 |
| L11 | a format character inside a key (zero-width space, joiner, soft hyphen, bidi override, BOM, tag characters) | CONTROL-CHAR only | the Cf strip of the front end; SECRET is reported as well, and the leak scan reads the same way | `rv-pos-zwsp-inside-key`, `rv-pos-soft-hyphen-key`, `rv-pos-tag-char-key`, `own-zwnj-key`, `own-bidi-key`, `own-bom-key`; mutant R8-1 |
| L12 | an escaped key (`"password"`) and escaped JSON in a string | missed | the escape view | `own-escaped-key`, `rv-pos-json-escaped-colon`, `own-lr5-double-escaped`; mutants R8-3, R8-6, LR5 |
| L13 | a tab between a key and its value (`DB_PASSWORD<TAB>v`, `--password<TAB>v`) | read, no case (RL5 survived) | `password-space` and `password-flag-space` read `[ \t]` | `own-rl5-tab-space`, `own-rl5-tab-flag`; mutant RL5 |
| L14 | a multi-part key and whitespace (`client_secret VALUE`) | missed | `password-space` reads an identifier key (multi-part, or upper-case longer than 3) | `own-space-multipart`, `own-space-upper`; mutant R8-30 |
| L15 | a value with the other quote kind inside, or `#`, `$` or `>` as the first character (`='$…'`, `=>` with a long value) | missed | the value classifier: a single-quoted `$` literal is a value, `=>` is a separator | `rv-pos-value-*`, `own-lr3-redirect` (an unquoted value starting with `>` is a shell redirect); mutants R8-29, LR3 |
| L16 | code, placeholders and paths that the round-7 lint reported (review N4) | reported | `_CODE_CALL`, `_CODE_ATTR` (a dotted name with no digit), the placeholder words and `your_`/`my_` prefixes, `_PATH` | `own-code-*`, `own-placeholder-*`, `own-path-dot`, and the 52 `rv-neg-*`; mutants R8-24 to R8-28 |

## B. The boundary: members outside the rule, with reasons

Counts are the census's boundary members of the round-8 lint (`MISS-boundary-*`); rows without a count
are outside the enumerated product and carry a fixture row instead.

| # | Member | Census count | Fixture | Reason it is not read |
|---|---|---|---|---|
| B1 | a letters-only value after a short key (`pass=something`), and after a generic or short key in an argument pair, XML attribute pair or YAML block (`boundary-letters`) | 2160 + 240 | `rv-pos-pwd-letters-only` | a short or generic key is also a word in prose and test logs; requiring a digit keeps the false-positive rate at zero on the 309-item corpus |
| B2 | a quoted value with a space after a generic or short key | 3264 | | prose (`token = "the one we agreed"`) is indistinguishable from a passphrase without a strong key |
| B3 | a short key with an unquoted colon (`PASS: case_x`), also percent-encoded | 333 | | the label of every test report line |
| B4 | a letters-only value after a generic key with an unquoted colon (`Token: rotated`) | 144 | `rv-pos-token-letters-colon` | prose writes `Token: ...` |
| B5 | whitespace separation after a generic or short key | 108 | | `token value` is prose; netrc, `--flag` and identifier keys are read |
| B6 | an XML element named by a generic or short key with a letters-only value | 60 | | `<token>example</token>` in documentation |
| B7 | `--token word` / `--pass word` with a letters-only value | 30 | | the usage line of a command |
| B8 | a URL user-info password that is digits followed by `/` or the end of the line | (negative) | | read as a port (`h:8080/`); digits before `@` are read (`rv-pos-url-digits-pw`) |
| B9 | a key outside the lists (`key`, `pin`, `sid`, `cookie`) | none | `rv-pos-key-word`, `rv-pos-pin-key`, `rv-pos-cookie-session` | each is a common word; adding one is a later class extension (follow-up) |
| B10 | a value under 8 characters | none | `rv-pos-value-7-chars` | too short to tell from a placeholder |
| B11 | a credential with no key and no vendor prefix | none | | no shape to match |
| B12 | `Authorization: Bearer` with a token under 20 characters | none | `rv-pos-bearer-short` | the `bearer-token` rule keeps its floor of 20 token characters; a shorter bearer value is rare and a placeholder (`Bearer TOKEN_HERE`) is common |
| B13 | a path after a strong or generic key (`password: "/run/secrets/db1"`) | 23040 | `own-path-quoted` | a path names where the secret lives, not the secret (review N4) |
| B14 | a capitalised prose word, whitespace, a value (`Password reset2026 works`) | none | `own-space-title-prose` | only an identifier key (multi-part or upper case) is read with whitespace |
| B15 | an argument pair whose second argument is a message (`t('password', 'Enter the code')`) | none | `own-argpair-message` | a value with a space is not read after a pair; translation calls are common |
| B16 | a builder method named by a key (`builder.password("…")`) | none | `own-setter-builder` | only `set` + key is a setter; a method named `password` is also a getter in many APIs |
| B17 | `mysql -p` followed by a space and a word (`mysql -u root -p app_database`) | 1 | `own-shortflag-mysql-prompt` | mysql reads `-p` alone as a prompt; the next word is the database name |
| B18 | a lookalike letter outside the fold table (Armenian `օ`) | none | `own-armenian-lookalike` | the fold covers Cyrillic and Greek (the confusable sets seen in practice); the CONTROL-CHAR rule does not cover letters; extension is a follow-up |
| B19 | a double-quoted value that starts with `$` (`"$Qz7…"`) | none | `own-dollar-literal-dq` | in a shell a double-quoted `$` is an expansion, so it reads as a reference; a single-quoted one is a literal and is read (L15) |
| B20 | a letters-only pgpass password | 2 | | a colon-separated line of words is a time stamp or a log field, not a pgpass line |

## V. Reviewer mutants (N3)

See the README section "Tests and mutants" for the verdict of each mutant in this run.

| Mutant | What it removes | Case that kills it |
|---|---|---|
| RL1 | the views (the raw text searched) | every front-end row (`own-zwnj-key`, `rv-pos-fullwidth-equals`, …) |
| RL2 | the short key `auth` (verbatim) | `own-auth-ld`, the `short-key-assign` needles |
| RL3 | the space requirement of `password-assign-spaced` (negative case) | `own-rl3-no-space`: exact rule list without the spaced rule |
| RL4 | the XML closing-tag match (negative case) | `own-rl4-xml-mismatch`, `own-xmlattr-entry-mismatch` |
| RL5 | the tab separator | `own-rl5-tab-space`, `own-rl5-tab-flag` |
| RL6 | the letter requirement (negative case) | `own-rl6-digits-colon`, `-flag`, `-xml` |
| RL7 | the URL x-mask exclusion (negative case) | `own-rl7-url-xmask-upper`, `own-url-xmask` |
| RL8 | the `--flag` boundary (negative case) | `own-rl8-joined-dashes` |
| RL9 | the minimum length 8 | every `V8` row (8 characters) |
| RL10 | the report of more than one rule per surface (negative case) | `own-rl10-two-rules`, `own-rl10-three-rules`: exact rule lists |
| RR3 | a close counts as a re-render | `check_body: a close counts as a re-render` (suite of `remint_ids.py`) |
| RR4 | the Evidence meta line in the template prefixes | `is_slot: the Evidence meta line is a template line` |
| RR5 | the `## ID. title` heading as a slot | `is_slot: the '## ID. title' heading form is a slot` |

RL1 and RL3 to RL10 mutated round-7 regular expressions that round 8 replaced, so their text no longer
exists; they are ported onto the same rule of the round-8 code (recorded in the header of
`tests/workable_items/test_intake_lint_mutations.sh`). RR1 to RR9 are adopted verbatim.

The first full harness run of round 8 left four of the fixer's own mutants alive: LR3, LR5, R8-18 and
R8-34 (`runs/lint_mutations_first_run.txt`). None was equivalent: each changed the lint's answer on a
surface the fixtures did not hold. Six rows were added (`own-lr3-redirect`, `own-lr5-double-escaped`,
`own-r818-port`, `own-r818-port-letters`, `own-r834-escape-then-percent`,
`own-r834-json-escape-then-percent`), and the four were re-run (`runs/lint_mutations_survivors_rerun.txt`).

## D. Guarded deletes and printed fragments (N6)

| # | Member | Fix |
|---|---|---|
| D1 | bare `rm -rf` in `tracker_intake_2026_11_12_v4/make_evidence.sh` (2), `_v5/make_evidence.sh` (2), `_v5/engine_repro_check.sh` (1), `_14_v6/tools/make_final_lint.sh` (1), `_14_v6/tools/simulate_landing.sh` (2) | `safe_rm_rf` from `scripts/lib/safe_rm.sh`; the packs' `SHA256SUMS` lines for these files are refreshed |
| D2 | the leak scans of v5, v6 and v7 printed the first 6 characters of a match (`prefix=…`) | the tools print kind and length only; the 127 `prefix=` fields in their committed run files are replaced by `prefix=<redacted by round 8, review N6>`; the packs' sums are refreshed |
| D3 | the v7 leak scan loaded the lint's own patterns | it can no longer load them from the round-8 lint (it reports BLIND, exit 3): it is a record of round 7, run against the round-7 lint; round 8 uses the independent `tools/leak_scan.py` |
