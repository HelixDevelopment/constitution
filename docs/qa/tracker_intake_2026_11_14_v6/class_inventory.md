# Tracker-intake vehicle, round 6: class inventory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14T18:40:00Z |
| Status | active |
| Status summary | The classes behind the round-5 findings R5-1 to R5-4, enumerated before the round-6 fix was written (section 11.4.276(C)). Each member names the rule that closes it and its test. |
| Author | round-6 fixer, Claude Opus 5.5 (subagent of the conductor); effort UNKNOWN (not reported by the dispatch path) |
| Evidence class | gate-logic only (section 11.4.289) |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [U. Every unit a merge can write, body_md included (R5-1)](#u-every-unit-a-merge-can-write-body_md-included-r5-1)
- [P. Refusals of a path that names a moved id (R5-2)](#p-refusals-of-a-path-that-names-a-moved-id-r5-2)
- [L. Keyed credential shapes (R5-3)](#l-keyed-credential-shapes-r5-3)
- [V. Reviewer mutants (R5-4)](#v-reviewer-mutants-r5-4)

## How the inventory was built

- Units: the 38 `items` columns (`V_UNITS` in `scripts/workable-items/remint_ids.py`, which verify
  checks against `pragma table_info(items)`), plus every writer of `body_md` in the engine source
  (`scripts/workable-items/cmd/workable-items/`): read in `mutate.go` (update, close), `obsolete.go`
  (obsolete-details), the reopen path, `canonicalizeStateLines` and `ensureTrailingNewline`.
- Refusals: every `refuse(` call in `make_plan` whose text names a moved id.
- Credential shapes: key name (strong: password, passwd, passphrase, client secret, secret key, API key,
  access key, private key, auth / access / refresh / bearer / session token; generic: secret, token)
  x key quoting (none, `"`, `'`) x key prefix (none, `_`, `-`) x separator (`:=`, `=>`, `:`, `=`) x value
  quoting (quoted, unquoted) x value kind (literal, reference, mask), plus the header forms, the URL query
  and the URL user-info. False positives were measured on the vehicle's tracker database (307 items,
  838061 characters): every widened candidate gave 0 hits except the URL user-info form, which hit only
  CON-330's example (rewritten in this round). Control needle: the same corpus holds "token" 59 times,
  "secret" 12 times and "password" once, none followed by a separator.

## U. Every unit a merge can write, body_md included (R5-1)

| # | Unit | Writer | Round-6 rule | Test |
|---|---|---|---|---|
| U1 | the six update columns other than description | `update --<col>`, body kept, heading replaced for `--title`, Status line canonicalised | only the changed columns are passed; `--description` only when the vehicle changed it | `R5-1: a field-only merge passes no --description`, `R5-1: the step passes no --description` |
| U2 | description | `update --description` re-renders body_md from the template | passed only when the vehicle changed it | the round-4 landing cases |
| U3 | body_md text outside the engine slots, changed by the target | none (not a column the planner sees) | a re-render (close, or update with `--description`) over such a body is a CONFLICT, resolvable with `--resolve` | `R5-1: a re-render of a body the target changed outside the slots is a CONFLICT`, `R5-1: --resolve vehicle of the body conflict`, `R5-1: --resolve target of the body conflict`, `R5-1: verify FAIL: a re-render replaced the target's authored body` |
| U4 | body_md heading | `--title` | verify: the heading names the landed title | `R5-1: verify FAIL on a heading that does not name the landed title` |
| U5 | body_md Status line | status, close, reopen | verify: a Status line names the landed status | `R5-1: verify FAIL on a Status line that does not name the landed status` |
| U6 | Reproduction / Investigation lines | `canonicalizeStateLines` | slots: excluded from the kept-text comparison | the state-block landing cases |
| U7 | Reopened-Details and its bullets | reopen | slots | the reopen landing cases |
| U8 | Obsolete-Details line | obsolete-details | slots | `R5-1: verify compares the body although the target changed obsolete_details` |
| U9 | Evidence line | close | slot of the template | the close landing cases |
| U10 | trailing newline | `ensureTrailingNewline` | normalised before comparison | all body comparisons |
| U11 | authored text in an untouched base item | none | verify compares the landed body with the vehicle body exactly | `R5-1: verify FAIL on lost authored text when the target left the item alone`, `R5-1: the authored lines are in the landed body` |
| U12 | created_at | close rewrites it (CON-339, engine defect) | KNOWN line, never a pass | `verify: the close rewriting created_at is KNOWN` |
| U13 | the body's Severity, Type, Created-By and Assigned-To lines after a field-only `update` of that flag | engine defect: all four stay stale (`runs/engine_field_repro.txt`; the review had probed `--severity` only) | not fixed here; filed as CON-343 (owed item 2). The planner replays the vehicle's field-only update through the same command, so the landed line is as stale as the vehicle's, and verify compares the two bodies | `verify FAIL: the engine's stale Severity line` |

## P. Refusals of a path that names a moved id (R5-2)

| # | Member | Round-6 rule | Test |
|---|---|---|---|
| P1 | an evidence path names an id that does not move (identity map, FAST-FORWARD) | not refused | `R5-2: FAST-FORWARD: a base path naming an own id that does not move is not refused`, `R5-2: --no-fast-forward with an identity map is not refused either` |
| P2 | an evidence path names an id that moves | refused | `R5-2: the same path is refused when the id moves` |
| P3 | a refused plan | the plan file is still written, mode REFUSED, no steps; replay refuses it | `R5-2: the refused plan is written` |

## L. Keyed credential shapes (R5-3)

Pattern names are those of `SECRET_PATTERNS` in `scripts/workable-items/intake_lint.py`. "Suite" is
`tests/workable_items/test_intake_lint.sh` (`secrets`, `shapes`, `nshapes`); "LS" is the mutant in
`tests/workable_items/test_intake_lint_mutations.sh` that removes the rule.

| # | Member | Pattern | Positive | Negative | Mutant |
|---|---|---|---|---|---|
| L1 | quoted value, any separator, plain key (`password = '...'`) | password-assign | `secrets` | `secrets` (7 characters) | LN5 class |
| L2 | quoted value after a quoted key (JSON `"password": "..."`, Python dict) | password-assign | json-quoted-key, python-dict | mask-x | LS1 |
| L3 | quoted value after `:` (YAML `api_key: "..."`) | password-assign | `secrets` | — | LS2 |
| L4 | quoted value after `=>` | password-assign | apikey-fat-arrow | — | LS9 |
| L5 | unquoted value after `=` (env file, `DB_PASSWORD=...`) | password-assign-unquoted | `secrets`, refresh-token-env | `secrets` (7 characters) | LN4 |
| L6 | unquoted value after `:=` | password-assign-unquoted | passphrase-walrus | — | LS10 |
| L7 | URL query (`?access_token=...`) | password-assign-unquoted | url-query-token | — | — |
| L8 | unquoted value after `:`, strong key (YAML, `X-Api-Key:` header) | password-colon-unquoted | yaml-unquoted-password, yaml-unquoted-api-key, yaml-quoted-key, x-api-key-header, x-auth-token-header, access-key-colon, private-key-colon, secret-key-colon | prose-password, not-a-key, passwordless | LS3, LS11 |
| L9 | unquoted value after `:`, generic key (`token:`, `secret:`): a letter and a digit required | secret-colon-unquoted | `secrets` | `secrets` (letters only), prose-token | LS4 |
| L10 | a reference value (`$VAR`, `<x>`, `{x}`, `%X%`) | every keyed pattern | — | reference-env, reference-angle | LN5 |
| L11 | a masked value (`*`, `x`, `.`, `#`, `-` only) | every keyed pattern | — | mask-stars, mask-x | LS5, LS12 |
| L12 | URL user-info password of any length | url-userinfo-password | url-short-password, `secrets` | url-masked-userinfo, `secrets` (`$` reference) | LS6, LS7 |
| L13 | `Authorization: Bearer` / `Token` | bearer-token | authorization-token, `secrets` | `secrets` | LS8 |
| L14 | `Authorization: Basic` | basic-auth | `secrets` | `secrets` | LN6 |

Not in the class (honest boundary, section 11.4.6): a letters-only value after a generic key and a colon
(`token: abcdefgh`), a key name outside the lists above (`key=`, `pin=`), a value shorter than eight
characters, and a credential written without any key. The leak scan of this evidence pack
(`tools/leak_scan.py`) loads the lint's patterns at run time, so the two scans read one class.

## V. Reviewer mutants (R5-4)

The round-5 reviewer's ten mutants and the inverse of the R5-1 fix are rows ROV1..ROV10 and ROVFIX of
`tests/workable_items/test_remint_ids_mutations.sh`. ROV3 is the clause without its line continuation;
the others are verbatim. The killing cases of the seven survivors are in `test_remint_ids.sh`, marked
`round 6 (R5-4)`: ROV2 a non-ASCII-digit id on a plan whose refusals were removed, ROV3 and ROV10 a type or
title change of the referenced item, ROV4 a plain close followed by obsolete details with another
evidence path, ROV5 a base Foreign line the vehicle drops, ROV6 a wrong landed triple_check_evidence,
ROV7 ids of four and five digits in the Rewriter.
