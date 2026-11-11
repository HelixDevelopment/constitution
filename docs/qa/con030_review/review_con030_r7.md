# CON-030 independent review, round 7 (sections 11.4.142 / 11.4.209 / 11.4.194(6))

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner), round 7; vehicle items CON-070, CON-194..CON-197 |
| Bundle | `con030_r7/con030_r7.bundle`, sha256 7135b9cd2b372c8cc08475d623123b648d3fbca1a684c3c72c2cbae6caf7269a (checked, matches); `git bundle verify`: "is okay" (prerequisites 64ac151d, fc57ad0c fetched from the github_helixdevelopment remote); head 3b919187, 29 commits over main fc57ad0c (ancestor checked) |
| Reviewer | fresh independent subagent on Opus 5.5 (claude-opus-5-5), not the author. Effort is not reported on this dispatch path, so none is claimed (section 11.4.231(F.2)) |
| Sandbox | `74ce2b36-.../scratchpad/rev_con030_r7/` (clone in `constitution/`), `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM`/`TMPDIR`/`GOCACHE` inside the sandbox; HOME not reassigned; nothing pushed; the author's mutsnap8 shard processes were not touched. My run was interrupted once by a network outage (EAI_AGAIN); the background test processes survived and completed, results below are from complete runs |
| Verdict | **NO-GO**: 1 important (reviewer mutant survives on the proving guard, with a measured bad effect), 1 important (evidence, carried: mutation table pending), 1 minor, 2 nit |

## Verdict in one paragraph

The round-7 class rule is real progress: the DEFAULT_IGNORABLE table equals perl's `\p{Default_Ignorable_Code_Point}` (Unicode 15.0.0), the drop-Zs equivalence holds, the self-test (1172/0), Go suite (80/0) and Go mutation test (18/18) reproduce, 7 of my 8 own mutants are killed, and my 23-case adversarial CLI probe found no exotic-invisible / non-UTF-8 / BOM / CRLF / end-marker way to get MANIFEST-OK on a hidden stale block or to delete prose, inside the declared class. But one of my mutants, which narrows the range the function USES (not the table constant), survives the whole self-test and lets a stale block hidden behind U+E0100 (variation selector 17) report MANIFEST-OK. The generated class claims "a table narrowed by one range ... fails cells here"; it samples no code point of several ranges and the perl cross-check inspects only the constant. This is exactly the r6 G1/G2 pattern (proof-of-batch guard gap), so it blocks. The full 194-row mutation table is still pending.

## Findings

| Id | Severity | finding_layer | Where | What, measured |
|---|---|---|---|---|
| H1 (RV7c) | important (reviewer mutant surviving on this batch's proving guard, sections 11.4.194(6)(d), 11.4.235(D); same class as r6 G1/G2) | source-defect (test gap) | `marker_ignorable`; self-test section 2d | Mutant: `for lo, hi in DEFAULT_IGNORABLE))` -> `for lo, hi in DEFAULT_IGNORABLE[:-1]))` (drops E0000-E0FFF only inside the function). Survives: `passed=1172 failed=0`. Cause: (a) the 30 generated code points sample no member of E0100-E01EF (Mn, only reachable through the DI clause; the sampled U+E0001 is Cf and is removed by the Cf clause anyway), nor of 17B4-17B5, 1BCA0-1BCA3, 1D173-1D17A; (b) the perl check compares the constant `DEFAULT_IGNORABLE`, not what `marker_ignorable` returns. Effect, measured on the mutant (probe7_RV7c.txt, sha256 fb621e9c...): `lead_VS17_UE0100 verify rc=0 ok=True`, `lead_VS256_UE01EF verify rc=0 ok=True` (head: rc 3). Fix proposal: assert `marker_ignorable(chr(c))` over ALL code points against the oracle set (perl's DI set union Cf union isspace union U+FFFD; cheap, about 1.1M calls), or at minimum generate cells from lo and hi of every table range; adopt RV7c verbatim as a mutation row |
| H2 (= r6 G5, carried) | important (evidence for landing) | test-instrumentation | mutation table | Author states the 194-row run is in progress (3 shards, ~7.5 h). Not complete, so not evidence; must finish with all killed, plus RV7c, before GO |
| H3 | minor (minor-class: guide census-sync check; not critical-invariant / security / data-safety / host-safety; a further member at the edge of r6 G3) | source-defect | `marker_ignorable` scope; guide_parse docstring | Characters that render blank or look identical but are NOT Default_Ignorable still hide a stale block (head, probe7_head.txt sha256 73ca19c8...): `lead_braille_blank_U2800 verify rc=0 ok=True`, `homoglyph_cyr_es` (Cyrillic U+0441 for "c" in both markers) `rc=0 ok=True`, `lead_U1D159_Mn rc=0 ok=True`. The docstring scopes its claim to "invisible or ignorable", and deleting the block passes by design (guide line 34), so the practical bypass is no worse than deletion. Proposed tracked follow-up: either add U+2800 / non-DI blank glyphs and a confusable skeleton (UTS #39) to the near test, or record an operator decision (section 11.4.66) that the guide must carry a block (which closes deletion, homoglyph and blank-glyph routes at once) |
| H4 | nit | test-instrumentation | self-test 2d perl check | When perl is absent the table cross-check prints `SKIP` and the suite still passes; then only the 30 sampled points pin the table. Acceptable as an honest SKIP; the H1 all-code-point check would remove the dependency |
| H5 | nit | process-doc | mutation rows RV6a, RV6f | Recorded as "adopted verbatim", but the r6 anchors (`marker_lead`, `startswith((GUIDE_BEGIN, GUIDE_END))`) no longer exist; the rows are faithful re-expressions on the new code, not verbatim. Say "adapted" |

## Prior findings (review r6), checked on the head

| r6 | Status | Evidence |
|---|---|---|
| G1 RV6f (end near-marker) | closed | `end_in` / `end_after` cells; author RED/GREEN files (survive on 10ad4e05, killed 14); my own end-side mutant RV7f (end near only when exactly equal) killed (2 checks); CLI probe `end_near_after_prose` rc 3, unchanged, prose kept |
| G2 RV6a (narrow Cf) | closed | U+2060/U+00AD lead cells plus generated Cf cells; RV6a killed (8) per author file |
| G3 (class) | closed for the Default_Ignorable / Cf / white space / U+FFFD class, except the H1 guard gap; residual non-DI members are H3 | probe: U+E0100, U+E01EF, U+E0041, NUL, DEL, ESC, U+0080, `\xff`, truncated `\xc3`, surrogate bytes, literal U+FFFD, trailing `\xff`, BOM at file start, CRLF + ZWSP all rc 3 and byte-identical after `--sync-guide` |
| G4 RV6b (mode) | closed | 644 and 755 cases; my RV7g (`mode & 0o644`) killed (1) |
| G5 table | open (H2) | |
| G6 CON-195 flake | tracked as CON-197 (re-minted), open | tracker |
| G7 K5 `rm -rf` | closed | `con030_r6_k5_nonutf8_red_green.sh` now uses `safe_rm_rf "${w:?}"` and leaves the directory in place when refused |

Drop-Zs equivalence (author's claim), verified independently: `python3 -c` over all code points: 17 Zs characters, none with `isspace()` false. Equivalent under CPython's `str.isspace` definition.

DEFAULT_IGNORABLE, verified independently with perl 5.40.1 (Unicode 15.0.0): `AD-AD 34F-34F 61C-61C 115F-1160 17B4-17B5 180B-180F 200B-200F 202A-202E 2060-206F 3164-3164 FE00-FE0F FEFF-FEFF FFA0-FFA0 FFF0-FFF8 1BCA0-1BCA3 1D173-1D17A E0000-E0FFF`, identical to the engine table. (CPython's unicodedata here is 16.0.0; DI did not change for these ranges as far as I checked, UNCONFIRMED for every 16.0 addition.)

## Runs on the head (3b919187)

- `bash tests/test_run_full_suite.sh`: `passed=1172 failed=0`, rc 0, 0 `FAIL ` lines, 582 `r7 near class` ok lines, `ok CON-030 r7 G3: DEFAULT_IGNORABLE equals perl's ... (Unicode 15.0.0)`; log sha256 92e7f99a367f9cea2be3e88e8b325aee8e3319f54cd7d64418f580b51e69314b
- `bash tests/test_run_full_suite_go.sh`: `SUMMARY pass=80 fail=0`, rc 0; log sha256 626392fd...
- `bash tests/test_run_full_suite_go_mutations.sh`: `SUMMARY mutants=18 killed=18 survivors=0 not_applicable=0`, rc 0 (Python DeprecationWarning about `"\."` in the harness, carried nit for main); log sha256 aaf2f3f0...
- Tracker (built `workable-items` from the head): `validate: OK — 196 items, all invariants satisfied`; `diff`: `in sync (compared 196 ... 196)`. main fc57ad0c has 191 items; head = 191 + CON-070 + CON-194..197; CON-192/193 on the head carry main's titles; CON-197 description keeps its full "Id history" chain
- 194-row mutation table: NOT run by me (author's shards running; not touched)

## My mutants (section 11.4.194(6)(d)), none written by the author

Applied as exact single-occurrence replacements to a copy of the head engine, then the head's whole self-test run against it (`FSR_RUNNER`). Rows in `rev_con030_r7/mut/rows.tsv`, logs and diffs `mut/<id>.log|.diff`, results sha256 f248b708...

```
BASE rc=0 failing_checks=0 last=passed=1172 failed=0
RV7a_strip_lead_only rc=1 failing_checks=184          # marker_norm strips only leading ignorables      killed
RV7b_drop_FFFD rc=1 failing_checks=24                 # U+FFFD (non-UTF-8 byte) not ignorable           killed
RV7c_drop_last_DI_range_in_fn rc=0 failing_checks=0   # function ignores E0000-E0FFF                    SURVIVED (H1)
RV7d_fix_ignores_parse_problem rc=1 failing_checks=540 # --sync-guide path swallows a near-marker refusal killed
RV7e_no_symlink_refusal rc=1 failing_checks=3         # sync writes through a symlink                   killed
RV7f_end_near_exact_only rc=1 failing_checks=2        # end near-marker only when exactly equal          killed
RV7g_mode_masked rc=1 failing_checks=1                # kept mode masked with 0o644                     killed
RV7h_no_crlf_for_new_line rc=1 failing_checks=1       # new block line loses the CR of a CRLF guide      killed
```

RV7a/RV7b overlap the author's R7e/R7c in intent; RV7c..RV7h are distinct.

## Adversarial guide inputs on the head (probe7_head.txt, sha256 73ca19c886cb007de32ac8334f6b2a06480045693d0a87060780ed5668ec477e)

```
control_stale_exact          verify rc=3 ok=False | sync rc=0 unchanged=False prose_kept=True
lead_VS17_UE0100             verify rc=3 ok=False | sync rc=3 unchanged=True prose_kept=True
lead_VS256_UE01EF            verify rc=3 ok=False | sync rc=3 unchanged=True prose_kept=True
lead_tag_UE0041              verify rc=3 ok=False | sync rc=3 unchanged=True prose_kept=True
lead_braille_blank_U2800     verify rc=0 ok=True  | sync rc=0 unchanged=True prose_kept=True   (H3)
lead_NUL / lead_DEL / lead_ESC / lead_C1_U0080      rc=3, unchanged, prose kept
lead_ff_byte / lead_trunc_c3 / lead_surrogate_bytes / lead_literal_FFFD / trail_ff_byte   rc=3, unchanged
homoglyph_cyr_es             verify rc=0 ok=True  | sync rc=0 unchanged=True                  (H3)
crlf_exact                   verify rc=3 | sync rc=0, rewritten, CRLF kept
crlf_lead_zwsp               verify rc=3 | sync rc=3 unchanged, CRLF kept
lead_U1D159_Mn               verify rc=0 ok=True                                             (H3)
lead_UFFFC / lead_combining_U0332  verify rc=0 ok=True   (visible glyphs: prose, not findings)
bom_file_start_line1 / end_near_after_prose / begin_twice_one_hidden   rc=3, unchanged, prose kept
```

No case deleted prose; every refusal left the file byte-identical.

## Needed for GO

1. H1: make the guard pin the function, not only the constant (all-code-point oracle comparison, or cells from every range's endpoints); observe RV7c fail the suite, adopt it as a row.
2. H2: complete the full mutation table (194 rows + RV7c), all killed.
3. H3, H4, H5 may ride as tracked follow-ups under section 11.4.276(G.2).
