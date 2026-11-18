# Round 10 of the provisional verification line checker (CON-521, review r9)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Last modified | 2026-11-17 |
| Status | PROVISIONAL (§11.4.290): gate logic only (§11.4.289(C)(2)); nothing here is a live verification |
| Item | CON-521 (placeholder `CON-PENDINGpvl8` until the tracker id is assigned) |
| Review answered | review r9, NO-GO, findings F1 to F9 |
| Checker | `scripts/validation/check_provisional_verification_lines.py` |

## Why round 10 is structural

Review r9 found look-alike labels (F1) and constructs left open into the next item of the exported document (F2), on
top of the r8 classes. The checker had patched these shapes one rule at a time for several rounds (§11.4.250,
§11.4.276(E)). Round 10 replaces that with two class-wide rules and one document-level reading:

| Rule | What it does |
|---|---|
| THE BODY ALPHABET | An allowlist: tab, LF, CR, printable ASCII and four extra characters (U+2014, U+00A7, U+2192, U+00B7). Every other character is refused, written directly or as a numeric character reference. Look-alikes and invisible characters are refused as a class, not one by one. |
| THE STRUCTURE BOUND | At most 8 container markers on a line, at most 6 open `[` in a paragraph, and per-character count bounds, checked before any reader runs. |
| THE END OF THE BODY | Each body followed by a blank line and a probe paragraph must show the probe to every reader. |
| THE DOCUMENT | The Issues and Fixed documents built from the database are read whole, with a probe after each segment, by every reader. An item of any status after which a probe is missing is refused. |

## Findings

| Finding | Round 10 answer | Evidence |
|---|---|---|
| F1 look-alike and invisible labels | THE BODY ALPHABET. Enumerated over all 1112064 code points: 100 accepted, 0 outside ASCII and the four extras, 0 accepted through a numeric reference; 1329 confusables of an ASCII letter, digit or colon, 0 accepted. Needles: `e` accepted, U+00E9 and U+039D refused. The enumeration found that `html.unescape` drops noncharacters and maps `&#x80;` to `&#x9F;` through windows-1252, so numeric references are now decoded the CommonMark way. | `enum_alphabet.txt`, `tools/enum_alphabet.py`, P14 |
| F2 document level | THE END OF THE BODY and THE DOCUMENT. Repros D1 (unclosed fence) and D3 (unclosed comment) and the open `<details>` are refused or reported as `DOC-FAIL`; a verification line that a lazy quote or a setext join absorbs is refused by the paragraph count. cmark-gfm is not run by the checker; it was run as evidence and lists the same open segments on the fixture, and none on `main`. | `cmark_gfm_fixture.txt`, `cmark_gfm_main.txt`, `tools/cmark_gfm_doc.py`, P14 |
| F3 reviewer mutants | RV9M01 to RV9M10 are vendored verbatim in `tests/release/pvl_mutants.tsv` and all are killed; RV9M06, 07 and 10 by new cases in `pvl_r10.py` (RV9M07 also by a quote copy that has no heading id, so only the text check sees it). | `mutate_run*.txt`, `suite_run*.txt` |
| F4 reader denial of service | THE STRUCTURE BOUND. pandoc `markdown` is exponential in open `[` (8 open 0.4 s, 16 open 9.7 s, 32 open over 60 s), so at most 6 may be open in a paragraph. Every pattern at its bound in a 65 KB body read in at most 2.34 s on this host. This is a measurement on one host, not a proven bound; the per-reader timeout stays 30 s. | `bound_timing.txt`, `tools/bound_timing.py` |
| F5 README overstatement | The r9 README carries a dated correction; the guide states the scope actually compared (the verification line and the label, each body alone and in the document check). | `../r9/README.md`, guide |
| F6 DOCX and PDF | Not read. Declared limit; follow-up, operator question. | guide, Limits |
| F7 look-alikes without the colon | `Verifi-cation:` is now refused. `**Verification** job:` and `**Verification -** job:` are still accepted: "verification job" is ordinary prose on `main`. Follow-up. | P14 `F7-hyphen` |
| F8 label split across table cells | Not detected. Follow-up. | guide, Limits |
| F9 subject and trailer | The commit subject names CON-521 and the placeholder `CON-PENDINGpvl8` of the trailer. | commit |

## Runs

All runs are gate logic on this host (§11.4.289(C)(2)); the readers are markdown-it-py 3.0.0 and pandoc 3.11.

| Run | Result | File |
|---|---|---|
| `tests/release/pvl_r10.py` on the round 10 checker (GREEN, before the mutation tells were added) | `R10 cases=84 pass=84 fail=0` | `r10_green.txt` |
| `tests/release/pvl_r10.py` on the round 9 checker (RED) | `R10 cases=58 pass=17 fail=41`; three parts crash because the round 9 checker has no `BODY_EXTRA`, `MAX_DEPTH` or `check_document` | `r10_red_r9checker.txt` |
| Real tracker, `main` ebd8818c (491 items) | `CHECKED items=491 provisional_status=29 ok=0 fail=29`, `DOCUMENT documents=2 segments=491 real=2 other_fail=2` (DOC-FAIL CON-112, CON-113), `VERDICT: FAIL`, 40 s | `main_run_final.txt` |
| Mutation run 1 (snapshot before the round 10 mutation tells) | `total=140 killed=129 survived=8 not_applied=3`: O66, RV9M07, O112, O115, O120, O121, O122 and O128 survived; R9A01b, R9A09 and O91 no longer applied to the round 10 code | `mutate_run1.txt` |
| Answer to run 1 | `pvl_r10.py` part K adds one case per surviving rule (status fold, named reference, bidi reference, end probe of `confirm()`, three `top_paragraphs` cases, structure bound in the document check) and a text-only copy for RV9M07; R9A01b, R9A09 and O91 re-anchored to the current code (their meaning unchanged) | `tests/release/pvl_r10.py`, `tests/release/pvl_mutants.tsv` |
| Mutation run 2, the 11 rows of run 1 | 10 killed, O112 survived (the named-reference case matched a later rule's message); the case now names the source rule and kills O112 (checked by hand on the mutant) | `mutate_run2_survivors.txt` |
| Suite run 1 (final round 10 code before its commit) | `RESULT: pass=109 fail=0`, P13 every mutant killed, `MUTATE total=140 killed=140` needle | `suite_run1.txt` |
| Suite run 2 (commit 4531233a) | byte-identical to run 1, sha256 `bce540caaf2efd427a02d1fffe928b63ee942e917c1e9c60edd27fadb3843cc5` | `suite_run2.txt` |
| Pattern suite (`test_provisional_verification_lines.sh`) on the merged tree | NOT RUN on the merge 3389fbd6 (owed, UNCONFIRMED after the merge); the two suite runs above are on the pre-merge round 10 tree | n/a |
| Merge commit 3389fbd6 (parents 05048e1b and `main` 33b33d26, a merge commit, not a rebase) | 13 files conflicted. Release tooling: `main`'s landed behaviour wins where it contradicts the CON-423 vehicle (draft marker, `--draft` and cut_date, the unified placeholder message, the dry-run exit codes, the 5-field gitea spec with its token variable); the vehicle's probes, fold and bare-date checks are kept; new helper `rc_gitea_token_state` in `redact_cut.sh`; `channels.tsv` merged and lint-clean (147 invocations, 0 findings), `netgate_pin.tsv` regenerated; manifest keeps both rows; the runner guide is regenerated; `docs/workable_items.db` taken from `main` and the Markdown replayed with `sync md-to-db` | `merge/` |
| Gates on the merge, run twice, identical | git-env census PASS unscrubbed 0 (members 669, after the tracked evidence tools were moved out, see Tools); ratchet 394 = baseline; index fresh; `--verify-manifest` MISMATCH exactly the known `pvl_grid.py` excluded-lock difference (NOT accepted, the reviewer decides); engine validate OK 501 items; engine diff in sync | `merge/gates_run1.txt`, `merge/gates_run2.txt` |
| Release tests on the merge | `test_render_release_entry.sh` 159 pass 0 fail; `test_tag_and_release.sh` pass=526 fail=0 rc=0 (a first run under nohup showed pass=520 with 2 SIGHUP cases SKIPPED, rc=77; it is kept as `t_tag_nohup_2skips.txt`, the second run has no skips) | `merge/t_render.txt`, `merge/t_tag.txt` |
| Release mutation suite on the merge | NOT RUN to completion (two runs killed, rc=143, 11 PASS lines before: controls, T2, T3). The remaining mutant rows (DP3, TS4, DR1, CD1, GP21 and others) are owed and UNCONFIRMED after the merge edits | n/a |

### Summary documents (note for the reviewer)

`docs/Issues_Summary.md` and `docs/Fixed_Summary.md` were regenerated with `workable-items export`. The diff against `main` is large (about 566 lines) and engine intrinsic: `sync md-to-db` rewrites 289 `description` values even on `main`'s own pristine DB and Markdown (measured on a copy). `Issues.md` and `Fixed.md` round-trip byte-identically.

## Follow-ups

- F6: DOCX and PDF outputs of the export are not read (operator question, §11.4.66).
- F7: `**Verification** job:` and `**Verification -** job:` are accepted.
- F8: a label split across two table cells is not detected.
- cmark-gfm is not run by the checker (it was run once as evidence).
- The export's `renderDocument` rewrite is not replicated in the document check.
- `main` holds two real export defects: CON-112 and CON-113 (both Queued) hold `</dev/null)`, which pandoc
  `markdown` reads as a raw closing tag; it swallows text up to CON-117's `<tmp>`. They are reported as `DOC-FAIL`.

## Tools

`enum_alphabet.py`, `bound_timing.py` and `cmark_gfm_doc.py` produced the evidence files of the same names. They are
not tracked here: the git-env census treats a tracked script that mentions the tool as a member and flagged the third
one. Their sha256 (kept in the scratch tree): enum_alphabet.py 96bf6d4e9dc1b1404944a66a03693c08824c9fe5ac2915b7a6329a3c29414c7d,
bound_timing.py 8b6ad1a404db47eb4e03c3b919dfc268560831a79b21cd19e6cfa995683245b1, cmark_gfm_doc.py
71129edf96bbe25b5bef8588b5df6361a2ae81f89f10117c200ac399d84b5019. Checksums are in `SHA256SUMS`.
