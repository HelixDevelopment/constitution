# CON-PENDINGpvl8 round 8: the checker reads characters and comments as a person and a browser read them

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Item | CON-PENDINGpvl8 (placeholder id; tracker item CON-521 on main; earlier commits call it CON-423, which collides with main's unrelated CON-423) |
| Round | 8 (structural, sections 11.4.276(C) and 11.4.250), after the r7 NO-GO review |
| Base | r7 head `3a5b462d`, merged with `origin/main` `2ca50ac4` (merge, not rebase) |
| Class | gate-logic, PROVISIONAL (sections 11.4.289(C)(2), 11.4.290); no live claim |
| Effort | UNKNOWN (not settable or readable on the dispatch path, section 11.4.231(F.2)) |

## What changed and why

Review r7 (NO-GO) found two important members of one class and eight minor or nit findings. The class is: the
checker reads a body one way and a reader shows it another way. Rounds 5 to 7 closed such members one at a time.
Round 8 lists every member first, then closes or scopes out each one:
[class_inventory.md](class_inventory.md). No rule was added on top of the r7 rules for one shape; three r7 rules
were replaced:

- **Comments.** r7 exempted a complete comment. An HTML5 reader ends a comment at `--!>`, `<!-->` or `<!--->`,
  where CommonMark does not, so what a comment covers depends on the reader. r8 refuses every comment, like any
  other raw HTML, at any depth (also inside image alt text and link text).
- **How a person reads a character.** r7 dropped format characters (category Cf) and mapped a hand-kept list of
  Cyrillic and Greek look-alikes. r8 reads every character through one table, `fold()`, built from ICU 78.2 /
  Unicode 17.0: default-ignorable code points, marks, format, unassigned, private-use and control characters are read
  as nothing; every other character is decomposed with NFKD and read through the UTS #39 confusable skeleton and case
  folding. The table is embedded in the checker and checked by its sha256; a broken table makes the run BLIND.
  The generator is `scripts/validation/pvl_reading_table.py`: [dependency_verdict.md](dependency_verdict.md).
- **The reader model.** r7 read the body as CommonMark only. r8 reads it twice with markdown-it-py 3.0.0:
  CommonMark, and CommonMark with GFM tables and strikethrough. Both readings must count the same line and meet every
  rule. A GFM footnote definition refuses the body. The counted line must be shown exactly as written: one paragraph,
  one source line, and the rendered text after the label equal to the source.

The user guide is [docs/guides/provisional_verification_line_guide.md](../../../guides/provisional_verification_line_guide.md).

## Findings of review r7 and where each is closed

RED is the r7 checker; GREEN is the r8 checker; each pair was run with the same command.

| Finding | RED (on r7) | Fix | GREEN (on r8) |
|---|---|---|---|
| F1 HTML5 comment ends | `red/probe_bang_on_r7.txt`: the reviewer's 4 hiding bodies accepted (and the plain-comment control); `red/f1_suite_rows_on_r7.txt`: `F1ROWS rc=0 accepted=CON-016,CON-022,CON-023` | every comment is raw HTML | `green/probe_bang_on_r8.txt`: all 6 refused (the plain-comment control is a listed false refusal); `green/f1_suite_rows_on_r8.txt`: `accepted=CON-016 refused=CON-022,CON-023`; suite P2 rows CON-022 and CON-023; `api_r8` CON-971, CON-972 |
| F2 invisible characters in a label | `red/probe_near_on_r7.txt`: 9 accepted (the plain and ZWJ controls refused) | `fold()` from ICU (THE NEAR RULE) | `green/probe_near_on_r8.txt`: 14 refused; `api_r8` CON-973, CON-974, CON-977, CON-978; suite P11 `probes_r7` |
| F3 the reader model | `red/probe_class_r8_on_r7.txt`: "F3 GFM footnote def before line" and "F11 GFM table delimiter after line" accepted | the GFM reading; the footnote rule | `green/probe_class_r8_on_r8.txt`; `api_r8` CON-982, CON-983, CON-989; blockstate contexts `fn-def`, `gfm-setext-table`, suffix `table-delim` |
| F4 the closed look-alike list | `red/probe_class_r8_on_r7.txt`: 4 colon look-alikes, Cherokee V, Armenian o and a combining dot below accepted | the UTS #39 skeleton from ICU, every code point | `green/probe_class_r8_on_r8.txt`: `open=0`; `green/fold_all.txt`: 1112063 code points, 0 mismatches, control seen; suite P8d, P9 |
| F5 raw HTML in image alt text | `red/probe_class_r8_on_r7.txt`: "F5 raw HTML in image alt" accepted (harmless in every reader, a narrowing) | raw HTML is found at any depth | `api_r8` CON-984; context `img-alt-html` |
| F6 the generator could not produce F1 or F2 | the r8 harness on the r7 checker: `red/blockstate_on_r7.txt`, `danger=5669` of 65004 bodies | 128 contexts (r7: 111), 13 suffixes (r7: 9), 36 reviewer entries (r7: 16); the oracle reads labels with the ICU reference `fold()` and checks itself on 14 inputs | `green/blockstate_on_r8_run1.txt` and `run2`: `danger=0` |
| F7 surviving reviewer mutants | review r7 mutant table: R7M03 to R7M07 and R7M12 to R7M14 survived, R7M08 was killed only through a FIFO side effect | see Mutants below | `mutate_run2.txt`: every applying mutant killed; `hotjournal.txt`: the hot-journal case alone kills R7M08 |
| F8 the `pvl_grid` lock note | the note claimed fences and HTML comments; `census/pvl_grid_needles.txt` counts 0 such cases | the note in `config/full_suite_manifest.tsv` now says what the grid holds | the excluded row is not in the accepted lock yet and needs a rostered accept (Open questions) |
| F9 placeholders in prose | 39 of 486 bodies on main hold one (`census/tracker_body_census.txt`) | the refusal message and the guide say to write a placeholder inside backticks | the raw-HTML refusal message; the guide's section "Placeholders" |
| F10 a symlink across file systems | not exercised | suite step P4d: the database on another file system than the link, with a live writer | P4d in `suite_run1.txt` and `suite_run2.txt` |

## Mutants

- **Own** (`tests/release/pvl_mutants.tsv`): 64 rows, each killed. O64 to O86 are new in round 8.
- **Retired** (`tests/release/pvl_mutants_retired.tsv`): 20 rows. Round 8 added O37, O43, O44, O45, O47, O49 and
  O58, whose code was replaced, and O50 and O60, re-minted as O88 and O89 on the r8 text. Every run proves the old
  text occurs 0 times.
- **Equivalent** (`tests/release/pvl_mutants_equivalent.tsv`): 4 rows, O48, O59, O88 and O89, reported as
  survivors, never counted as killed. Each row carries its argument.
  - O59 is new. It survived run 1 (`mutate_run1.txt`). It removes the attribute texts (link targets, titles, image
    text) from the rendered-text check. On the counted line, any link, image or autolink already fails the exact rule
    with the same reason. Elsewhere, the source-line check runs first and covers those texts. The code is kept as
    defence in depth.
  - `tools/survivor_search.py` (`survivor_search.txt`) found no telling body for any of the four: 0 of 336 label
    placements and 0 of 86672 blockstate bodies. Its control, own mutant O77, has telling bodies (30 and 9132), so
    the search can see one.
- **Reviewer**: 26 apply to this suite and are killed: R15, R19, R21, N15, N16, RV01, RV02, RV03, RV05, RV06, RV08,
  RV09, RV10, RV12, RW01, RW02, RW08, RW09, R7M05 to R7M09, R7M11, R7M14 and R7M15.
- **Review r7 F7, one by one.**
  - R7M03 (greedy comment pattern), R7M04 (`skip_label` threshold), R7M12 (no NFKC in `has_label`) and R7M13
    (oracle prefix check): their code is gone in round 8, so they are not applicable. Each has a map row in
    `tests/release/pvl_reviewer/mutants_map.tsv` that names the cases covering the property instead.
  - R7M05 (a version prefix `3.` accepted): killed by `api`; markdown-it-py 3.0.1 gives BLIND.
  - R7M06 (copy budget per file): killed by the `api_r8` case where each file fits the budget and the two together
    do not.
  - R7M07 (change detection off): killed by the `api_r8` case where the database changes during every copy.
  - R7M08 (`-journal` not copied): killed by the `api_r8` hot-journal case, not only through the FIFO.
    `hotjournal.txt`: the database alone holds 334 rows of the open transaction; the checker reads 400 committed
    rows; the mutant is BLIND.
  - R7M14 (oracle attribute check removed): killed by the oracle self-test (blockstate BLIND).
- **Run 1** (`mutate_run1.txt`): `MUTATE total=91 killed=90 survived=1`, the survivor O59. **Run 2**
  (`mutate_run2.txt`): after O59 moved to the equivalent table.

## Reviewer material vendored verbatim

`tests/release/pvl_reviewer/` holds files byte-equal to the r7 review material:

- `mutants_r7.tsv`, equal to the review's `reviewer_mutants_r7.tsv` (sha256 `b53515c8...739e`, listed in the
  review's SHA256SUMS);
- `probe_bang_r7.py.txt`, `probe_near_r7.py.txt` and `probe_shapes_r7.py.txt`, equal to the reviewer's
  `tools/probe_bang.py`, `tools/probe_near.py` and `tools/probe_shapes.py` (sha256 `36ddd329...55c4`,
  `698d236d...3bba`, `7066f88c...710e`; the review's SHA256SUMS covers its outputs, not its tools).

`changes_r7.tsv` is this round's own list of every reviewer probe body whose verdict changed in round 8, with the
reason.

## Runs

All runs were made on 2026-11-17 under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`, one heavy job at a
time.

The runs below were made on the merged tree `a86caff2` (round 8 `fc41cc75` merged with `origin/main` `2ca50ac4`).

- `suite_run1.txt` and `suite_run2.txt` (`tests/release/test_provisional_verification_lines.sh`): each ends
  `RESULT: pass=107 fail=0`, exit 0. P4d ran (a second file system was found); it did not SKIP.
- `compare.txt`: the two suite runs are byte-identical, and so are `green/blockstate_on_r8_run1.txt` and
  `green/blockstate_on_r8_run2.txt` (`danger=0 accepted=2286 refused=62718 false_refusals=4296`). A control copy
  with one changed line is seen as different.
- `suite_premerge.txt`: the same suite on `fc41cc75`, before the merge: `RESULT: pass=107 fail=0`.
- `mutate_run2.txt` (`tests/release/pvl_mutate.py`): `MUTATE total=90 killed=90 survived=0 not_applied=0
  retired=20 equivalent=4 retired_fail=0`.
- `verify_manifest.txt` (`scripts/run_full_suite.sh --verify-manifest`): `MANIFEST-MISMATCH`, 1 problem. The
  excluded row `tests/release/pvl_grid.py`, added by this vehicle, is not in the accepted lock yet; round 8 corrected
  its note (F8). `verify_manifest_simulated.txt`: an accept, SIMULATED in a throwaway copy that was then deleted,
  gives `MANIFEST-OK`. It was never committed; the real accept is the lander's (Open questions).
- `gates.txt`, on `a86caff2`:
  - git-env census: PASS, `unscrubbed=0`. `tests/release/pvl_blockstate.py` got a justified row in
    `config/git_env_class_exemptions.tsv`: its only git word is the comment "GitHub and extension syntax".
  - `CM-GATE-LEDGER-RATCHET`: PASS, `unimplemented=394 baseline=394`.
  - `CM-CONSTITUTION-INDEX-FRESH`: PASS.
  - `--sync-guide`: `total=977`; the runner guide is unchanged.
  - workable-items `validate`: OK, 486 items. `diff`: the database and the Markdown are in sync.

## Limits

- **Evidence class.** gate-logic only (section 11.4.289(C)(2)). It proves the checker decides correctly on the bodies
  listed. It does not prove that the provisional items on the real tracker are verified.
- **Scope.** The harnesses enumerate listed members and their cross product. No proof is claimed over every
  CommonMark or GFM document.
- **Readers.** markdown-it-py 3.0.0 makes the decision; pandoc 3.11 (commonmark and gfm) is the independent reader
  of the harnesses. html5lib was used only in the reviewer's evidence for the comment ends (`probe_bang_html5lib.txt`).
  cmark, cmark-gfm, commonmark.js and a browser are not tried (class inventory S4).
- **Characters.** Characters are read as Unicode 17.0 reads them. A font that draws a character differently is not
  modelled (S5). A character with no ASCII skeleton is read as itself.
- **ICU.** It is needed only to rebuild or check the table and by the harnesses. It is present on this host only
  (libicu78 78.2); elsewhere those steps are BLIND.
- **False refusals.** In the blockstate grid they rose from 4146 (the r7 checker, on the r8 grid) to 4296. All are
  in the safe direction. Every comment and every placeholder outside backticks is now refused.
- **Equivalent mutants.** O48, O59, O88 and O89 are argued equivalent and searched, not proved.
- **P4d** is a coverage extension (review r7 F10). It was not RED on r7.

## Open questions for the operator

1. **Lock.** Accept the excluded row `tests/release/pvl_grid.py` with its corrected note
   (`scripts/run_full_suite.sh --verify-manifest --accept-excluded-change <rostered id>`). The lander does this with
   a rostered id; this fixer does not accept on anyone's behalf.
2. **False refusals.** Is refusing every comment acceptable? 0 of 486 bodies on main hold one today.
3. **ICU on the release host.** The checker itself does not need ICU. Only rebuilding the table does.
