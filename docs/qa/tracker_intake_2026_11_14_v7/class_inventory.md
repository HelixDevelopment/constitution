# Tracker-intake vehicle, round 7: class inventory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14T22:15:00Z |
| Status | active |
| Status summary | The classes behind the round-7 review findings F1 to F3, enumerated before the round-7 fix was closed (section 11.4.276(C)). Each member names the rule that closes it, or the reason it is outside the rule, and its test. |
| Author | round-7 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289) |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [L. The secret-shape class (F1)](#l-the-secret-shape-class-f1)
- [B. The boundary: members outside the rule, with reasons (F1)](#b-the-boundary-members-outside-the-rule-with-reasons-f1)
- [C. The flaky re-mint case (F2)](#c-the-flaky-re-mint-case-f2)
- [V. Reviewer mutants RM1 to RM8 (F3)](#v-reviewer-mutants-rm1-to-rm8-f3)

## How the inventory was built

- Secret shapes: `tools/secret_class_census.py` builds every member of the product key tier x case x
  prefix x key quoting x separator x value quoting x value kind (282718 members), plus the whitespace,
  `--flag`, netrc, XML, URL user-info and HTTP-header members, from fragments at run time, and runs each
  through the SECRET patterns of a given lint. It prints labels only, never a generated string. Its
  control needles (a known member found, a prose line not reported) run first.
- The same census run on the round-6 lint (`red/census_on_r6.txt`) gave gap=67230 fp=2040; on the
  round-7 lint (`runs/census.txt`) gap=0 fp=0. The RED run is the census's own proof that it can see a
  gap (section 11.4.273).
- The leak scan (`tools/leak_scan.py`) loads the lint's patterns at run time and reads every line in its
  NFKC form, as the lint does, so the two scans read one class.

## L. The secret-shape class (F1)

| # | Member | Round-6 result | Round-7 rule | Test (`tests/workable_items/test_intake_lint.sh`) |
|---|---|---|---|---|
| L1 | a strong key joined to a prefix by nothing (`PGPASSWORD=`) | missed | `_KEY_LEAD` allows a letter, digit, `.` or `-` before the key | `shapes pg-joined-prefix`, `export-joined-quoted`; mutant LR1 |
| L2 | a short key (`MYSQL_PWD`, `DB_PASS`, `REDIS_AUTH`, Docker `"auth"`) | missed | `short-key-assign`: after a character that is not a letter or digit, a value with a letter and a digit, never a path | `shapes mysql-pwd`, `db-pass`, `redis-auth`, `docker-auth-json`; `nshapes bypass-word`, `oauth-word`, `pass-test-label`, `auth-letters`, `pwd-path`; mutants LR6, LR7, LR8 |
| L3 | a `--flag` and a value after a space | missed | `password-flag-space`; an upper-case placeholder is not a value | `shapes cli-flag-space`, `cli-flag-token`; `nshapes flag-placeholder`; mutant LR9 |
| L4 | a strong key, whitespace, a value (fish `set -x`) | missed | `password-space` (a letter and a digit) | `shapes fish-set-space`; `nshapes space-letters`, `token-space-generic`; mutant LR14 |
| L5 | netrc `login U password P` | missed | `password-netrc` | `shapes netrc-letters`; mutant LR10 |
| L6 | an XML element named by a key, with or without attributes | missed | `xml-credential-element` (a generic or short key: a letter and a digit) | `shapes xml-element`, `xml-attr-generic`, `xml-short`; `nshapes xml-reference`; mutants LR11, LR12 |
| L7 | a quoted value with a space (a passphrase) | missed | `password-assign-spaced` (strong keys) | `shapes quoted-with-space`; mutant LR13 |
| L8 | a URL user-info password with `/` in it, or an empty user name | missed | `url-userinfo-password` widened; digits before `/` or the end are a port | `shapes url-slash-password`, `url-empty-user`; `nshapes url-port-path`; mutants LR15, LR16, LR17 |
| L9 | full-width `：` / `＝` and full-width letters | missed | every surface read in its NFKC form (`SECRET_NFKC`); the leak scan does the same | `shapes fullwidth-colon`, `fullwidth-letters`; mutant LR2; leak-scan mutant `nfkc_dropped` |
| L10 | a backtick-quoted value or key | missed | backtick in the key and value quotes | `shapes backtick-value`; mutant LR4 |
| L11 | an escaped quote (JSON written inside a string) | missed | `\\?` before each quote | `shapes escaped-json`; mutant LR5 |
| L12 | `api.key`, `oauth_token`, `credentials` | missed | added to the strong key list | `shapes api-key-dot`, `oauth-token`, `credentials-key`; mutants LR18, LR19 |
| L13 | `=>` followed by a short value, a reference or a mask (2040 false positives on the round-6 lint) | reported | a value that starts with `>` is the second half of `=>` | `nshapes fat-arrow-short`, `fat-arrow-reference`; mutant LR3 |

Each new pattern also has one built-in control needle in `selfcheck` (the needle count is checked
against the pattern count, 28).

## B. The boundary: members outside the rule, with reasons (F1)

Counts are the census's boundary members (`MISS-boundary-*`, 5916 in all); the last four rows are
outside the enumerated class and carry no count.

| # | Member | Census count | Reason it is not read |
|---|---|---|---|
| B1 | a letters-only value after a short key (`pass=something`) | 2160 | a short key is also a word in prose and test logs; requiring a digit is the line that keeps the false-positive rate at zero on the 307-item corpus |
| B2 | a quoted or unquoted value with a space after a generic or short key | 3264 | prose (`token = "the one we agreed"`) is indistinguishable from a passphrase without a strong key |
| B3 | a short key with an unquoted colon (`PASS: case_x`) | 162 | the label of every test report line |
| B4 | a letters-only value after a generic key with an unquoted colon (`Token: rotated`) | 144 | prose writes `Token: ...` |
| B5 | whitespace separation after a generic or short key | 96 | `token value` is prose; netrc and `--flag` are read |
| B6 | an XML element named by a generic or short key with a letters-only value | 60 | `<token>example</token>` in documentation |
| B7 | `--token word` / `--pass word` with a letters-only value | 30 | the usage line of a command |
| B8 | a URL user-info password that is digits followed by `/` or the end | (negative) | read as a port (`h:8080/`); a real password of digits only is missed |
| B9 | a key outside the lists (key, pin, sid, cookie) | none | each is a common word; adding one is a later class extension |
| B10 | a value under 8 characters | none | too short to tell from a placeholder |
| B11 | a credential with no key and no vendor prefix | none | no shape to match; vendor prefixes are their own patterns |

## C. The flaky re-mint case (F2)

| # | Member | Finding | Round-7 rule | Evidence |
|---|---|---|---|---|
| C1 | the CON-339 note on the item the vehicle's close rewrote (suite, base item 3) | the engine `close` writes created_at to the current second; the base `add` and the vehicle `close` ran within one second on some runs and in two seconds on others, so the note came and went | the base items get a fixed past created_at (`2026-02-03 04:05:06`) before the vehicle and target copies are made | `runs/created_at_repro.txt`: 10 of 10 closes in the same second left created_at unchanged, 0 of 10 closes in the next second did; the remint suite ran 3 times byte-identical (`runs/remint_suite_*.txt`) |

## V. Reviewer mutants RM1 to RM8 (F3)

Adopted verbatim into `tests/workable_items/test_remint_ids_mutations.sh`; results in
`runs/remint_mutations_rm_first.txt` (RM6 survived) and the full run `runs/remint_mutations.txt` (171 mutants, all killed).

| # | Mutant | Killing case |
|---|---|---|
| RM1 | verify's re-render branch compares the landed body with the vehicle body | the round-6 body cases |
| RM2 | the reopen `Evidence` bullet is not a slot | `R7-F3: verify PASS: the legacy bullets, Evidence included, are engine slots` |
| RM3 | `Obsolete-Details` is not a slot | `R7-F3: verify PASS: the Obsolete-Details line is an engine slot` |
| RM4 | every map pair goes to the rewriter | the R5-2 cases |
| RM5 | a refused plan carries no refusal | the refused-plan cases |
| RM6 | the planner's body-conflict test ignores template meta lines | `R7-F3: a re-render over a target edit of a template meta line is a CONFLICT` (survived the first RM run, `runs/remint_mutations_rm_first.txt`; the review called it equivalent, but a re-render does replace a hand-edited meta line, so the conflict is observable and the case was added) |
| RM7 | a landed body without a heading is not checked | the heading cases |
| RM8 | verify's no-re-render branch ignores template meta lines | `R7-F3: verify FAIL on an altered template meta line when nothing re-renders` |
