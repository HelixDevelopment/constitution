# CON-030 independent review, round 8 (sections 11.4.142 / 11.4.209 / 11.4.194(6))

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner), round 8 |
| Bundle | `74ce2b36-.../scratchpad/con030_r8/con030_r8.bundle`, sha256 cd255d039125a8d23690f9e2eba3f22118ccd9a3bd9941faa9c8a2f5ee5f35e2 (checked, matches); `git bundle verify`: "is okay" (prerequisites taken from the round-7 reviewer clone); head e5b1a74e, 1 commit on 3b919187 |
| Reviewer | fresh independent subagent on Opus 5.5 (claude-opus-5-5), not the author. Effort is not reported on this dispatch path, so none is claimed (section 11.4.231(F.2)) |
| Sandbox | `74ce2b36-.../scratchpad/rev_con030_r8/` (clone `constitution/` at e5b1a74e; worktree `r7wt/constitution` at 3b919187); `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM`/`TMPDIR`/`GOCACHE` inside the sandbox; HOME not reassigned; nothing pushed; the mutsnap8 shard processes were not touched (logs read only) |
| Verdict | **GO-pending-table**: source GO; 0 blocking findings, 4 nits (minor-class, may ride as follow-ups per section 11.4.276(G.2)); landing waits for the 194-row mutation table (procedure below) |

## Per-finding verdicts on review r7

| r7 | Verdict | Evidence (measured here) |
|---|---|---|
| H1 (RV7c) | **closed** | RED: RV7c against the r7 suite (worktree at 3b919187): `rc=0 failing_checks=0 passed=1172 failed=0` (log `mut/r7/RV7c_drop_last_DI_range_in_fn.log`, sha256 prefix 109a6b4d). GREEN: against the r8 suite: `rc=1 failing_checks=1 passed=1177 failed=1`, failing line `FAIL CON-030 r8 H1: marker_ignorable equals the oracle on every code point ... got '3999 U+E0000(fn=False) ...'` (`mut/r8/RV7c...log`, be0212ef). 3999 = 4096 - 97 Cf members of E0000-E0FFF, correct. RV7c is row 195 of the table, verbatim |
| H2 (table) | **open, pending** (not a code finding) | see "Landing condition" |
| H3 | **closed as tracked** | CON-198 (Bug, Queued, Low, parent CON-030) in Issues.md + Issues_Summary (Bug Queued 57->58, total 195) and in the DB; text matches the r7 measurement, cites the probe sha256, states the impact honestly (no worse than deleting the block; guide line 34 does say a guide with no marker passes) |
| H4 | **closed** | `perl_xcheck` prints exactly one SKIP line with `reason perl_not_installed`, or FAIL under `FSR_REQUIRE_PERL=1`; both paths asserted in the suite with a non-existent command; both ok in my baseline run |
| H5 | **closed** | harness comment labels RV6a/RV6f ADAPTED and RV6b verbatim; row data unchanged |

## Independence of the oracle and the Unicode table

- `ORACLE_DI` literal equals perl 5.40.1 `\p{Default_Ignorable_Code_Point}` (Unicode 15.0.0) - asserted in-suite (ok in my run) and equal to the r7 reviewer's independent perl dump.
- My own fully independent oracle (perl, `[\p{Default_Ignorable_Code_Point}\p{Cf}\p{Zs}\p{XPerlSpace}\x{FFFD}]` over all non-surrogate code points) vs the engine's `marker_ignorable`: engine 4236, perl 4232, engine-only = U+001C..U+001F (Python `str.isspace` counts them, perl does not; the documented definition is `str.isspace`), perl-only = 0; surrogates: 0 ignorable. So the function is right as documented. CPython unicodedata is 16.0.0; no Cf/DI difference to perl 15 showed up except that isspace delta.
- Caveat (N2): the in-suite oracle is independent CODE but the same FORMULA (isspace, U+FFFD, Cf/Zs via the same `unicodedata`, the table); only its DI table is independently anchored (perl). It pins the function against regression, which is what H1 asked; it would not catch a spec error shared by both.

## The fixer's argument that the in-flight shards cover round 8 - evaluated, holds

1. Engine identical: `git diff 3b919187 e5b1a74e -- scripts` empty; sha256 30d19f69... in my clone and in `mutsnap8`.
2. mutsnap8 = 3b919187 exactly for `tests/test_run_full_suite.sh` (8c3984c9...), `tests/test_run_full_suite_mutations.sh` (9211bbeb...), the engine and `scripts/run_full_suite.sh` (sha256 prefixes compared).
3. Table: r8 row ids = r7's 194 ids + `RV7c`, no row text changed (`ids_r7_table.txt` sha256 f8c977e7...); harness logic changed only in comments.
4. Suite diff: every old check still present and equal except the perl table check, now `PASS` iff `perl_di` non-empty and equal, else `FAIL` - a superset of the old FAIL condition. New code adds checks only; no `set -e` (only `set -u`), every new variable is assigned before use, no name reused by later sections, so it cannot end the suite early or change state seen by later checks. The kill criterion (rc != 0 and >= 1 `FAIL ` line) is therefore monotone: a row killed by the old suite is killed by the new one. Residual risk: the self-test flake tracked as CON-197 (non-determinism), not a logic gap.

## My mutants (section 11.4.194(6)(d)), none written by the author

Applied as exact single-occurrence replacements to a copy of the head engine; the whole self-test run against it (`FSR_RUNNER`). Rows: `rev_con030_r8/mut/rows.tsv`.

```
id                          what                                                    r7 suite                   r8 suite
M8a_range_hi_exclusive      lo <= o < hi (drops top of each range, single points)   killed (60)                killed (61)
M8b_isspace_narrowed        c.isspace() -> c in " \t"                               SURVIVED (1172/0)          killed (1)
M8c_category_widened_C      category in (Cf,Zs) -> category[0] == "C"               SURVIVED (1172/0)          killed (1)
M8d_marknorm_raw            GUIDE_MARK_NORM = raw markers (near test never fires)   -                          killed (594)
M8e_near_exact_after_norm   startswith(GUIDE_MARK_NORM) -> == after normalising     -                          killed (4)
M8f_near_excl_stripped      exact-marker exclusion uses l.strip()                   -                          killed (118)
M8g_norm_keeps_FFFD         marker_norm keeps U+FFFD                                killed (24)                killed (24)
RV7c (r7 reviewer)          function drops E0000-E0FFF                              SURVIVED (1172/0)          killed (1)
baseline (unmutated)                                                                -                          passed=1178 failed=0
```

M8b and M8c survive round 7 and die only on section 2e, so the new check is load-bearing beyond RV7c. M8c is behavioural (a private-use or unassigned character before a marker becomes a near-marker, so a legal prose line is refused); M8b looks unreachable through `gov_lines` (VT, FF, U+001C, U+2028 are refused as GovLineError on head and on the mutant; probe in-process), but 2e pins the function anyway.

## New findings (all nit, minor-class under section 11.4.276(G.2); not critical-invariant / security / data-safety / host-safety)

| Id | Severity | finding_layer | What |
|---|---|---|---|
| N1 | nit | process-doc | Guide and test comment: "a function that drops one range fails even when the table constant is right". Not true for the 7 ranges that are entirely Cf (00AD, 061C, 200B-200F, 202A-202E, FEFF, 1BCA0-1BCA3, 1D173-1D17A; measured: 0 non-Cf members each): dropping one is behaviourally equivalent and not detected by 2e (the perl check still pins the constant). Say "a range with members outside Cf / white space" |
| N2 | nit | test-instrumentation | The in-suite oracle shares the engine's formula and `unicodedata`; only the DI table is independently anchored. Optional: when perl is installed, compare `marker_ignorable` with the perl-derived set (as above; expected delta U+001C-001F) |
| N3 | nit | test-instrumentation | The NEG control compares oracle with oracle-minus-range, so it shows the oracle can see a range but not that the BAD comparison path can; RV7c (row 195) covers that path, so low value |
| N4 | nit | test-instrumentation | Adopt M8c (and M8b) as table rows: they survive the round-7 suite and are killed only by 2e |

Not a finding: `perl_xcheck` output loop has no expected-line count, but the function prints a fixed 1 (SKIP/FAIL) or 2 lines and any other line is `ko`.

## Runs on the head (e5b1a74e)

- `bash tests/test_run_full_suite.sh`: `passed=1178 failed=0`, 0 `FAIL ` lines, 9m20s; the 7 r8/G3 lines ok (count 1114112, mismatches 0, NEG 3999, DI = perl 15.0.0, oracle table = perl, two H4 lines); log `rev_con030_r8/logs/r8_base.log` sha256 9cc6c21c79d443ea211d26dbe58c722a7072a61e4166de406ba6f745c3eb2c4e
- `bash scripts/run_full_suite.sh --verify-manifest`: rc 0, `census: ... total=879`, `RESULT: MANIFEST-OK`
- Tracker (built `workable-items` from the head, DB copy): `validate: OK — 197 items, all invariants satisfied` (note: reproduction closure gate not armed); `diff`: `in sync (compared 197 Markdown item(s) against 197 DB item(s))`
- Mutation table: not run by me (shards running; at 14:55: 16/17/16 killed lines, 0 SURVIVED)

## Landing condition (GO-pending-table) - how the lander must verify

1. Each of `74ce2b36-.../scratchpad/logs/mut8_s00.log`, `mut8_s01.log`, `mut8_s02.log` starts with `ok   baseline: unmutated copy passes the self-test` and ends with a `SUMMARY mutants=N killed=N survivors=0 not_applicable=0` line (killed == mutants); `grep -c '^SURVIVED'` is 0 in all three.
2. The union of ids from `grep '^killed' ... | awk '{print $2}' | sort` over the three logs equals exactly the 194 ids of 3b919187's table (`rev_con030_r8/ids_r7_table.txt`, sha256 f8c977e72eb17fadbdc5c4e707081917ddbb181703ce75b50e90afd09fdc22d5): no id missing, none duplicated, and the three N values sum to 194.
3. The shards ran on mutsnap8 = 3b919187 (verified above); re-check its engine sha256 is still 30d19f69... (nothing re-snapshotted mid-run).
4. Row 195 (RV7c) killed on the r8 suite: author's `bash tests/test_run_full_suite_mutations.sh RV7c` (killed, 1 check) and my run (`rc=1 failing_checks=1`); no further run needed.
5. Any SURVIVED or not_applicable row, or a missing/duplicated id: NO-GO, back to the fixer.
