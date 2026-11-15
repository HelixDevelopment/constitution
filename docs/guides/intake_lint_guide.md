# Intake lint guide — `intake_lint.py` for a batch of workable items

| Field | Value |
|---|---|
| Revision | 8 |
| Created | 2026-11-13 |
| Last modified | 2026-11-15T19:00:00Z |
| Status | active |
| Status summary | User guide and manual for the read-only content lint of an intake batch of workable items (cross-references, states, sections, secrets, ephemeral locations, duplicates, cited paths). |
| Authority | Constitution §11.4.148, §11.4.214, §11.4.215, §11.4.294, §11.4.10 — the canonical text wins where this guide and the constitution disagree. |
| Scope | Universal (§11.4.17); the id prefix, the database path and the origin text are consumer DATA (§11.4.35). |
| Issues | not yet wired into a seam: the reporting and landing paths and the pre-build sweep do not run it (tracked as an item, see the tracker-intake v2 report) |
| Issues summary | Run it by hand before landing an intake batch. |
| Fixed | round 9 (review r9 F1, F4, F5): the key half of the SECRET rule is a structural classifier, not lists of spellings in each extractor: a key token is split into words (camelCase, snake_case, kebab-case, dots, brackets, letter-digit boundaries) and a head word followed only by non-property words makes it a key, so suffixed, qualified, bracketed and prefix-joined keys are read and property names (password_policy, token_count) are not; the front end also removes combining marks and Hangul fillers, folds Latin small capitals and similar letters by name, and decodes HTML entities, octal escapes and joined string literals, up to three layers; secret-manager references and identifiers are not reported; two mutants that cannot change an answer are listed as equivalent with their evidence; round 8 (review N1, N2, N4, N6): the SECRET rule is rebuilt as a front end (NFKC, format characters removed, Cyrillic and Greek lookalike letters folded, escape and percent decoding), keyed extractors per syntax and one value classifier; quoted values holding a backslash are read again (the round-7 regression), and argument pairs, setter calls, XML key/value attributes, tool short flags, YAML block scalars, pgpass lines, percent-encoded separators and upper-case URL schemes are read; paths, code calls and placeholders are not reported; round 7 (review F1): the secret-shape class is enumerated by a census and closed (prefixes joined by nothing, short keys, backtick and escaped quotes, quoted values with a space, --flag values, netrc, XML elements, URL user-info with a slash or an empty user, the NFKC form; `=>` with a short value no longer reported); round 6 (review R5-3): the keyed-credential shape class (key quoting, every separator, colon values, header keys, URL query and user-info of any length, the Token scheme, references and masks) is SECRET; round 5 (review R4-3, R4-5, R4-6, R4-9): unquoted password assignments and `Authorization: Basic` are SECRET; Unicode format characters (bidi, BOM, soft hyphen, zero-width) are CONTROL-CHAR; ids are ASCII digits only and an id written with other digits is XREF-DANGLING; every location row of an item is linted, not only the first; the database path is quoted in the read-only URI and a non-empty `-wal` sidecar is BLIND; round 4 (review R3-3 and minors): SECRET, EPHEMERAL and CONTROL-CHAR on every surface (every items column, the obsolete_details, operator_block_details and item_history rows, the rendered documents); STATE-EVIDENCE; every engine header key compared; the range-end clause fix; golden-bad needles bound to their own check; round 3 (review R2-2 to R2-8): XREF-UNLABELLED, DUP-HEAD, DUP-UNDECIDED, DUP-STATUS, OBSOLETE-STALE; BODY-SYNC both directions; a crash or a NULL column is BLIND |
| Fixed summary | Revision 8 is round 9; revision 7 round 8; revision 6 round 7; revision 5 round 6; revision 4 round 5; revision 3 round 4; revision 2 round 3; revision 1 the initial creation (round 2). |
| Continuation | — |

## Table of contents

- [Why it exists](#why-it-exists)
- [Run it on an intake batch](#run-it-on-an-intake-batch)
- [Surfaces](#surfaces)
- [Finding codes and how to fix each](#finding-codes-and-how-to-fix-each)
  - [BODY-SYNC header keys](#body-sync-header-keys)
- [Exit codes](#exit-codes)
- [The embedded-id table for a re-mint](#the-embedded-id-table-for-a-re-mint)
- [Skipping a code](#skipping-a-code)
- [Tests](#tests)
- [Honest boundary](#honest-boundary)

## Why it exists

`workable-items validate` and `workable-items diff` prove the closed sets, the description floor and
that the database and the Markdown agree. They do not read what a description says. In the
2026-11-12 tracker-intake review two wrong facts passed both: an item that duplicated an open item
(§11.4.214) and a cross-reference that named an anchor number as if it were an item id. The
reviewer's data mutants M2, M3, M9, M10 and M11 survived the same tools. `intake_lint.py` reads the
text of a selected batch and reports those classes. It never writes; it opens the database
read-only.

## Run it on an intake batch

Select the batch by a phrase every item of it carries (its `Origin:` line), or by ids:

```
python3 -I scripts/workable-items/intake_lint.py --db docs/workable_items.db \
  --origin 'tracker-intake vehicle 2026-11-12' --require-dup-check --repo-root .
python3 -I scripts/workable-items/intake_lint.py --db docs/workable_items.db --ids CON-300,CON-301
```

- `--require-dup-check` demands a `Duplicate check (section 11.4.214): <verdict> ...` line in every
  selected item, verdict from DISTINCT, DISTINCT-but-similar, SAME-DEFECT, UNDECIDED.
- `--repo-root .` turns on PATH-MISSING (every cited `docs/qa/...` or `docs/operator_decisions/...`
  path must exist in the checkout) and the evidence-file checks of STATE-EVIDENCE; the rendered
  documents default to `<repo-root>/docs`.
- `--rendered DIR` scans the rendered `Issues.md`, `Fixed.md`, `Issues_Summary.md` and
  `Fixed_Summary.md` in DIR: the section of each selected item and the summary rows whose id cell
  names it. A selected item that appears in none of them is BLIND. `--no-rendered` skips them (the
  RESULT line says `rendered=none`).
- `--prefix` sets the id prefix; by default it is the most common prefix in the database. A prefix
  no item carries is BLIND: the id checks could not see.

Each finding is one line `FINDING <code> <item> <detail>`, then `RESULT: PASS|FAIL selected=N
findings=N prefix=P`.

## Surfaces

SECRET, EPHEMERAL and CONTROL-CHAR read every text surface of a selected item: the title, the
description, body_md (every line, the header lines included), every other column of `items`
(enumerated from the row, so a new column is read without a code change), the item's
`obsolete_details`, `operator_block_details` and `item_history` rows, and the rendered lines. One
finding per (code, item, pattern) names every surface the pattern was found on, for example
`aws-access-key-id on description,body_md`. The XREF checks read the title, the description and the
state text columns (`reproduction_*`, `investigation_root_cause`).

An item that has more than one row in `items` (one per location) is linted on every row: the first
row is the item, each further row is linted too and its findings are printed with `[<location> row]`
after the detail (round 4 read only the first row, R4-6). A finding a further row shares with the
first is printed once.

An id is `<prefix>-<ASCII digits>`. Python's `\d` also reads fullwidth and other Unicode digits, so
`CON-３` would have read as `CON-3` (R4-5). Such a token is no id of this tracker and no reader can
follow it: it is reported as XREF-DANGLING with `(non-ASCII digits)`.

## Finding codes and how to fix each

| Code | Meaning | Fix |
|---|---|---|
| XREF-DANGLING | an id of this tracker in the title or description does not exist | correct the id, or, if it belongs to another tracker or a vehicle, declare it on a `Foreign ids (<where>): A, B` line |
| XREF-LABEL | `<id> (<label>)`: no significant word of the label is in the target's title, or more than a third of the label's significant words occur nowhere in the target's title or description | the label names a different item or an anchor; fix the id or the label |
| XREF-UNLABELLED | an id of another existing item, written without a label, in a clause that shares no significant word with the target's title (the Duplicate check line and a `Stale obsolete_details row` note are judged by the DUP and OBSOLETE checks instead; a Foreign ids line is never read for references) | add a label `<id> (<what it is>)`, or fix the id |
| FOREIGN-STALE | the `Foreign ids` line declares an id the text never names | drop it from the line |
| STATE-PROSE | a state word in prose, or a hand-written `**Reproduction:**` / `**Investigation:**` line in the description, disagrees with the state column | set the state with the engine flags (`--reproduction-state`, `--investigation-state`); reword prose so it does not restate a state |
| STATE-EVIDENCE | a reproduction state that needs evidence (reproduced-*, not-reproducible-with-evidence) has no evidence path or no 64-hex sha256 in `reproduction_env`; an investigation state that needs evidence (root-cause-found-with-evidence, closed-no-defect) has none; a blocked state has no blocker; with `--repo-root`, the evidence file is missing or its sha256 differs | record the evidence path and its sha256 through the engine flags, or lower the state |
| SECTIONS | a §11.4.148 marker is missing (What, Affected scope, Reproduction / context, Acceptance criteria, Parent / links) | add the section; write `UNKNOWN:` for what is not known |
| BODY-SYNC | body_md is not the engine rendering of its sources: empty, the description not in it, text before or after the rendered parts, the heading, a header line that differs from its source (table below), a key written twice, a key the engine does not write, or a header line that carries a line separator other than a newline | regenerate through the engine; never edit one column by hand |
| SECRET | a credential-shaped string: 17 vendor and header patterns (AWS, GitHub, GitLab, GCP, private-key block, Hugging Face, JWT, Slack, OpenAI/Anthropic, `Authorization: Bearer`/`Token` (20 characters or more) and `Basic`, Stripe, npm, Telegram) and the keyed shapes below, 34 rule names in all. Every surface is read in four views: NFKC with format characters (Cf) removed and Cyrillic and Greek lookalike letters folded to Latin, that view with backslash escapes decoded, that view percent-decoded, and both decoded, so `pass\u200bword`, `p\u0430ssword`, `\u0070assword` and `password%3D` read as `password=`. Keys: strong (password, passwd, passphrase, client secret, secret key, API key, access key, private key, credential(s), auth / access / refresh / bearer / session / API / id / OAuth / app token), generic (secret, token) or short (pwd, pass, auth, only after a character that is not a letter or digit). Syntaxes, one extractor each: URL user-info (any scheme case), a quoted or unquoted assignment (`:=`, `=>`, `:`, `=`; the value may hold a backslash escape or the other quote kind), an argument pair (`define('K', 'v')`, `get('K', 'v')`, `["K", "v"]`), a setter (`setPassword("v")`, `set_api_key('v')`), `--flag v` (space or tab), a tool's short flag (`mysql -pv`, `mysqldump -pv`, `sshpass -p v`, `curl -u u:v`, `--user u:v`), an identifier key and whitespace (`set -x DB_PASSWORD v`, `client_secret v`), netrc, an XML element named by a key, an XML key/value attribute pair (`<add key="Password" value="v"/>`, `<entry key="password">v</entry>`), a YAML block scalar (`password: |` and the next line) and a pgpass line. The value: 8 characters or more; after a generic key with an unquoted colon, after any short key and in a pgpass line it must hold a letter and a digit; never a reference (`$`, `<`, `{`, `%`, `(`, `[`, a double-quoted `$`), a mask, a placeholder (`changeme`, `your_…`, `…_here`), a path, a code call or a dotted name without a digit. The class is enumerated by `docs/qa/tracker_intake_2026_11_15_v8/tools/secret_class_census.py` (317674 members, 0 gaps and 0 false positives against this rule); the members not read, each with its reason (letters-only values after a generic or short key, a value with a space after a generic or short key, `key`/`pin`/`cookie`, values under 8 characters, a short Bearer token, paths, prose words before a value, Armenian and other lookalikes outside the fold, …), are listed in section B of `docs/qa/tracker_intake_2026_11_15_v8/class_inventory.md`; only the rule name is printed | remove it; if it is a real credential, rotate it (§11.4.10) |
| EPHEMERAL | a session-scratchpad path, a `/tmp` path, a mktemp-shaped name (default `tmp.XXXXXXXXXX` in any case, or a mixed-case suffix of four or more characters), a `.bundle` file, a home directory path, a session store directory, or a bare `review_*.md` / `*_lander_items.md` name outside `docs/`, on a line with no `(ephemeral` note | cite the tracked copy under `docs/qa/...`, or note the line `(ephemeral: ...)`; a note covers its own line only |
| CONTROL-CHAR | NUL, a C0 control other than tab and newline, DEL, a C1 control, U+2028, U+2029, or a Unicode format character (category Cf: the bidi overrides and isolates of Trojan Source, the BOM, the soft hyphen, the zero-width characters, the tag characters) on any surface, the earliest one named; a tab or newline in the title | remove the character through the engine (`update`) |
| SHARED-PATH | a file in the Affected scope is also named by an open item outside the batch, and the Duplicate check line does not name that item | compare the two items and name the other item in the Duplicate check line with its verdict |
| DUP-CHECK | (with `--require-dup-check`) the line is missing or the verdict is not in the closed set; (always) a SAME-DEFECT verdict that names no id | add the line; write `SAME-DEFECT of <id>` |
| DUP-SAME-OPEN | the verdict is SAME-DEFECT of X but the item is not closed Obsolete duplicate-of X (the first id after `of` is the head) | close it with `close <id> --status obsolete` and `obsolete-details <id> --reason duplicate-of --superseding <head>` |
| DUP-HEAD | the verdict is SAME-DEFECT of X but X is not a single surviving head: X is itself Obsolete or closed, or X records an open UNDECIDED candidate duplicate (more than one distinct head) | §11.4.214(0): resolve the chain to its head; with more than one head the verdict is UNDECIDED: reopen the item and mint-with-link |
| DUP-UNDECIDED | the verdict is UNDECIDED but names no candidate id, or the item is closed | name the candidates on the line; keep the item open (mint-with-link) |
| DUP-STATUS | the item is Obsolete duplicate-of but its verdict is not SAME-DEFECT | correct the verdict, or reopen the item |
| OBSOLETE-STALE | an `obsolete_details` row on an item that is not Obsolete, with no `Stale obsolete_details row (...)` note that names an existing open item | the engine keeps the row after a reopen (CON-340); write the note naming the open item the item now stands for |
| PATH-MISSING | a cited evidence path does not exist under `--repo-root` | commit the evidence, or correct the path (§11.4.215) |

### BODY-SYNC header keys

| Key | Must equal |
|---|---|
| Status, Type | `**Status:** <status>`, `**Type:** <type>` (always present) |
| Severity, Created-By, Assigned-To | `**<Key>:** <column>` when the column is set; absent when it is empty |
| Reproduction | the engine's line built from the reproduction columns; absent when the state is UNSET |
| Investigation | the engine's line built from the investigation columns; absent when the state is UNSET |
| Obsolete-Details | the item's `obsolete_details` row when the status is Obsolete; absent otherwise |
| Evidence | the evidence path of a closure history row or of the `obsolete_details` row |
| Reopened-Details | the last Reopened history row; a line with no such row is a finding |
| Operator-Block-Details | starts with the WHAT of the item's `operator_block_details` row; a line with no row is a finding |
| Reopens-count | the number of Reopened history rows (legacy key; no current engine path writes it) |

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | no finding (or `--embeddings` printed) |
| 1 | findings |
| 2 | usage error: no selection, an unknown `--skip-check` code, `--repo-root` not a directory |
| 3 | BLIND: database missing or unreadable, a non-empty `-wal` sidecar beside it (checkpoint it first: the read-only open would not see the uncheckpointed rows), a required table missing, no items, an item with a NULL title, description, status or location, a BLOB or other non-text value, a prefix no item carries, an unknown id, an empty selection, a selected item absent from every rendered document, a rendered document missing or unreadable, a built-in control needle failed, or the lint crashed on an input (the exception type is printed, never a traceback) — no verdict is given |

The built-in control needles run on every call: each check must fire on a golden-bad text and stay
silent on golden-good texts; each surface carries a planted secret, ephemeral path and control
character that must be reported with that surface named. A golden-bad needle passes only when the
finding carries the message of the check it is named for: a finding of the same code from a second
check does not count (round 4: the line-separator text was also caught by the Status compare, so the
separator check could be switched off with the needles silent). If a needle fails, the lint cannot
see and says BLIND instead of PASS.

## The embedded-id table for a re-mint

`--embeddings` prints a TSV `item, embedded_id, namespace, count` for the selected items: `own`
(an id of the batch), `main` (an existing item outside the batch), `foreign` (declared on a
`Foreign ids` line), `unknown` (not in the database). A lander that re-mints the batch's ids
(§11.4.214) uses it to find every id to rewrite inside the database. Ids written outside the
database (Markdown exports, commit messages, reports) are not in it; the report that ships the batch
lists those places.

## Skipping a code

`--skip-check SECTIONS,PATH-MISSING` drops those codes from the result. A skipped code must be stated
wherever the result is cited. Use it for legacy items whose old text predates the rules, never to
pass a new batch.

## Tests

- `tests/workable_items/test_intake_lint.sh` (283 cases): golden-good and golden-bad fixture
  databases for every code (with variants for each member of a class), every BODY-SYNC header key in
  both directions, every STATE-EVIDENCE branch, SECRET on every surface kind, a positive and a
  negative needle for each secret pattern, the rendered documents, usage and BLIND exits (a NULL
  column, a BLOB, a missing table, a crash), the embeddings namespaces, three cases that switch a
  check off in a copy and require the built-in needle to name it, and the reviewers' data mutants
  (rounds 1 to 3) plus the I1, I2 and R2-1 replays on a scratch copy of the real database; round 5
  adds the unquoted assignment and Basic credentials, the format characters, the non-ASCII digits, a
  finding on a second location row, the `-wal` sidecar (non-empty: BLIND; empty: read) and a database
  path holding `?` and `#`. It exits 2 when the cleanup of its temp dir is refused. Round 8 runs
  `tests/workable_items/test_secret_shapes.py` first: the shared fixture list
  `tests/workable_items/secret_shape_fixtures.py` (195 rows: the round-8 reviewer's 51 shapes, 52
  lookalikes and 6 backslash values, and the fixer's own rows), each "hit" row with its exact rule list,
  and a check that every keyed rule is reached; the same list is run through the independent leak scan
  `docs/qa/tracker_intake_2026_11_15_v8/tools/leak_scan.py` by its own `leak_scan_test.py`.
- Round 9: the shared fixture list holds 288 rows (the round-9 reviewer's 50 shapes and 20 negatives
  verbatim, and the fixer's own rows). The mutation harness also lists EQUIVALENT mutants: an edit that
  cannot change the lint's answer is not run as a mutant but named with an evidence file made by
  `docs/qa/tracker_intake_2026_11_15_v9/tools/equiv_check.py` (views and rule names compared on every
  census member, every fixture row, 200000 seeded strings and every code point inside and before a key,
  with a control needle that must differ). The harness checks that the edit still matches the lint once
  and that the evidence was made for that exact edit (`EDIT edit_sha256=`), so a later change to the lint
  re-opens the question. RV2 and LR2 are listed so; the counts are in the round-9 evidence pack.
- Round 8: the mutation harness holds 185 mutants (the remapped round-5 to round-7 secret mutants, the
  round-8 reviewer's RL1..RL10, ported, and the R8 mutants of the new engine); the older counts below
  are kept as written.
- `tests/workable_items/test_intake_lint_mutations.sh`: 110 mutants of the lint and of the suite (the
  round-1 and round-2 sets, the round-2 reviewer's code mutants, the round-3 checks, the round-3
  reviewer's LC1..LC11, the round-4 checks, the round-4 reviewer's LV1..LV6, the round-5 checks
  LN1..LN12, and the suite's own cleanup); each must be killed by the
  suite's own cases, and the check mutants declared so also by the built-in control needles.
  `INTAKE_LINT_MUT_JOBS` sets the parallelism (default 3).

## Honest boundary

Evidence class gate-logic only (§11.4.289): the lint proves its decisions on the text it reads. It
does not prove that an item is true, that a duplicate verdict is right, or that the external trackers
match the database. The word-overlap label checks and the shared-path check are heuristics; a pass is
not a review. The duplicate checks read the verdict line and the chain one step; they do not decide
whether two items are the same defect.
