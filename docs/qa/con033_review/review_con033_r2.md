# Independent review: vehicle/con033 (CON-033), round 2 of at most 5

| Field | Value |
|---|---|
| Reviewed range | `origin/main..vehicle/con033`, head `dd8bd9ca4af5ce558fb8d05fb835095ef6c3c7be` (contains main `ecfe432`) |
| Bundle | `con033_r2.bundle`, sha256 `9c66492085cfb677164c4b2a477fde322385055efaff8cb2ba3f27f8809959b0` (re-hashed by the reviewer, matches) |
| Inputs | author report `scratchpad/con033_fix_r2_report.md`; round-1 review `scratchpad/review_con033.md` |
| Reviewer | independent subagent, Opus (model `claude-opus-5-5`); reasoning effort is not reported by this dispatch path, so no effort is claimed (§11.4.231(F.2)) |
| Where | fresh clone `scratchpad/rv033r2.useS/repo` with worktrees `wt_veh` (dd8bd9c) and `wt_main` (ecfe432); every test run under `env -i` with a fresh HOME and TMPDIR inside the scratchpad; the live checkout was only read |
| Host | bash 5.3.9 (host); bash 5.2.15 (debian bookworm-slim) and 5.2.37 (debian trixie-slim) in rootless podman, `--network=none`; load 30 to 40 on 16 CPUs during the runs, 23 GB RAM available |
| Verdict | **GO-with-follow-ups** (§11.4.276(G.2)). Every open finding is minor-class. Landing is blocked only by process steps listed under "Required before landing". |

## Verdict in one paragraph

The round-1 blocker (C1) and every round-1 important finding (I1 to I5, I8) are fixed, and the fixes hold under my own reviewer-authored mutants: the clean-env allowlist and the dotted model read are guarded (DSM-D is killed by the class and r7 suites), the r7 tier rows pass 229/229, `test_dispatch_stamp.sh` passes 295/295 on bash 5.3.9, the literal-free gate passes 34/0, the new store-tier suite kills R4-C, the boundary suite kills RM1 on both sides, and the sweep exits 143 on TERM. The official mutation runner gives 31 of 31 KILLED, rc 0, on this host. I checked the 94 rows the vehicle runner dropped (not 83) one by one: 71 still apply verbatim to the vehicle's code, and all 71 are KILLED by the vehicle's suites on this host; the 23 that no longer apply all target code the owner-only tier model replaced, and every replacement guard has a KILLED row in the ledger; I re-swept on this host the 16 rows whose listed killers are all R4-CAP cases (which skip here), and all 16 are KILLED here by in-process cases. Open findings: one minor source-defect in `fc_timer_run` (posix mode), and test-instrumentation and process-doc follow-ups. The tracker items CON-070..075 cannot land with those ids: live main has moved to `efe2cc6` and holds CON-071..082 (CON-070 is a gap), so the six items must be re-minted through the engine at landing, after the vehicle merges `efe2cc6`.

## Per-slice verdicts (§11.4.235(D))

| Slice | Files | Verdict | Open findings |
|---|---|---|---|
| S1 dispatch stamp | `scripts/fastcycle/tokens/dispatch_stamp.sh`, `test_dispatch_stamp*.sh`, `test_dispatch_stamp_r7_matrix.sh` | GO-with-follow-ups | R2-F6 |
| S2 project literals | `scripts/fastcycle/tokens/transcript_ingest.py` | GO | none |
| S3 review record | `review_record.py`, its suites, the mutation runner, the kill ledger, the sweep and its red test, the analyzer | GO-with-follow-ups | R2-F2, R2-F3, R2-F5, R2-F8 |
| S4 timer | `scripts/fastcycle/timing/fc_timer.sh`, `fc_timer_selftest.sh`, `fc_timer_selftest_mutations.sh` | GO-with-follow-ups | R2-F1 (minor source-defect), R2-F4 |
| S5 manifest | `config/full_suite_manifest.tsv`, `docs/guides/full_suite_runner_guide.md` | GO, pending one reviewer or operator act (see R2-F9) | R2-F9 |
| S6 tracker | `docs/Issues.md`, `docs/Issues_Summary.md`, `docs/workable_items.db` | GO for the content; the ids must be re-minted (R2-F7) | R2-F7 |
| S7 rest of the batch (round-1 scope) | cycle report, anchor citations, token attribution fixtures, metatest, plan-struct, select-sample, gate generator | GO (differential identical to main, see below) | R2-F10 (process-doc) |

## Findings

| Id | Layer | Severity | Slice | Finding | Follow-up |
|---|---|---|---|---|---|
| R2-F1 | source-defect | minor | S4 | `fc_timer_run` compares `trap -p` output with the non-posix string `trap -- '' SIGINT`. In posix mode bash prints `trap -- '' INT`, so the caller's ignore is not seen and the reset is applied. On bash 5.2.15 and 5.2.37 with `POSIXLY_CORRECT=1`, a caller that ignores INT gets a child with SigIgn `0x0` instead of `0x2` (the caller's ignore is lost). bash 5.3.9 keeps `0x2` either way. | Accept both spellings (for example `case "$(trap -p INT)" in "trap -- '' SIGINT"\|"trap -- '' INT") ;; *) _fcr_reset+=(INT);; esac`), and add a posix-mode leg to the selftest. |
| R2-F2 | test-instrumentation | important | S3 | Reviewer mutant RVM-B (`paths = [records_dir, ledger_path]` changed to `paths = [records_dir]`, the dispatch ledger dropped from the store tier) SURVIVES all 10 runner suites and `test_review_record_subclause_cases.sh` on this host. Its only killer is R4-CAP5 ("a ledger owned by the producer uid makes the store instance"), which is skipped here (no all-root-owned chain above TMPDIR). The new in-process store-tier suite covers records-dir entries only and never makes the ledger foreign-owned. This is a second member of the round-1 I4 class (a tier property proven only by environment-dependent R4-CAP cases); round 2 closed the reported member (R4-C) but not the class (§11.4.276(C)). Why test-instrumentation and not a source-defect: the `_store_tier` code is new in this batch (brought over in `8c0b137`; main computes the same thing in `_independence_tier(... + [ctx["ledger_path"]])`), and by reading it includes the ledger. The behaviour is proven by committed machine evidence: R4-CAP5 is the killer in 11 rows of the committed kill ledger, whose `tool_sha256` matches the vehicle's `review_record.py`, so in the sweep's environment R4-CAP5 ran and passed on the unmutated code (control GREEN). What fails here is detection on hosts where the leg skips, which is detection completeness. That RVM-B is killed by R4-CAP5 where it runs is by reading lines 470-480 of the r4 suite; I could not run that leg (it needs an all-root-owned chain above TMPDIR, so `/tmp`, which this review does not use): UNCONFIRMED by execution. If the coordinator reads this as proof-of-batch on a security-relevant surface (the independence tier, §11.4.240), it is not minor-class and blocks until the in-process case lands. | Add an in-process ledger case to `test_review_record_store_tier_all_entries_regression.sh` (injected runner uid, ledger owned by the producer uid, expect `instance` naming the ledger), add RVM-B to the runner, and enumerate every R4-CAP-only property the same way. |
| R2-F3 | test-instrumentation | important | S3 | `test_review_record_gate_authority_r4_regression.sh` (new in the batch) and `test_review_record_subclause_cases.sh` (new) print a `NOTE: ... SKIPPED` line and exit 0 when their capability or ACL legs cannot run. On this host r4 reports `ok 18 / NOT ok 0`, rc 0, with R4-CAP1..7 not run. A runner that reads the exit status counts a suite with skipped proof legs as PASS (§11.4.3, §11.4.289(E)). This is what hid R2-F2. | Count skipped legs and exit with the project's SKIP status (77) or print a machine-readable skip count that the runner and the sweep treat as not-PASS. |
| R2-F4 | test-instrumentation | minor | S4 | Reviewer mutant FTM-3 (reset INT and QUIT unconditionally, the variant the author rejected) passes the selftest's F-A-run-ignored check on the host (bash 5.3.9), because 5.3.9 keeps the caller's ignore after `trap -` in an async subshell. The mutant is killed on 5.2.15 and 5.2.37 (SigIgn `0x0` with the caller ignoring INT). The `trap -p` condition is therefore checked only where the selftest runs on bash 5.2. FTM-4 (no reset) is killed on the host (F-A-run-intquit FAIL). | Assert the computed reset list directly in the selftest, or run the F-A-run legs on a 5.2 shell too. |
| R2-F5 | test-instrumentation | minor | S3 | The sweep's red test covers TERM (S1, exit 143), the empty list (S2) and the default output path (S3). Nothing drives the HUP or INT exits (129, 130) or the `N_ROWS != N_TODO` refusal, so deleting either path keeps the red test green (by reading the test: no case reaches them). The sweep's SUITES also omits the two new suites (store-tier and round-budget boundary), so the ledger never records their kills. | Add cases for HUP, INT and a forced row-count mismatch; add the two suites to the sweep's SUITES when the ledger is next regenerated (CON-072). |
| R2-F6 | test-instrumentation | minor | S1 | Reviewer mutant DSM-B (swap the policy precedence so `$CLAUDE_PROJECT_DIR/docs/context/dispatch_tier_policy.tsv` wins over `FC_DISPATCH_TIER_POLICY`) survives all five dispatch-stamp suites: no case sets both. The precedence is unchanged from main (pre-existing), but round 2 made both channels reach the re-exec. | One case with both set to conflicting caps, asserting the documented order (env first). |
| R2-F7 | process-doc | minor | S6 | Id collision. Live main is now `efe2cc6` (80 items, CON-001..082 with CON-048 and CON-070 unused). The vehicle's CON-070..075 collide with live CON-071..075 and with the CON-070 the CON-030 vehicle holds. Also: the six items have no `parent_atm_id` (main's follow-ups record CON-033 as parent); CON-073 (missing images) and CON-075 (stale mutation anchor) describe defects but are typed Task; CON-071 only tracks this landing and closes with it. | At landing: merge `efe2cc6` into the vehicle, take main's `docs/Issues.md`, `docs/Issues_Summary.md` and `docs/workable_items.db` byte for byte, register the items again through `scripts/reporting/report_item.sh` (with CON-033 as parent), check each against live items first (§11.4.214; none of the six subjects is on live main today), and record the old-to-new id map in the landing commit message, because the messages of `5035395` and `dd8bd9c` carry stale ids. Consider dropping CON-071. |
| R2-F8 | process-doc | minor | S3 | Author report counts: the vehicle runner removed **94** rows, not 83 (114 on main, 20 shared, 11 added); O* and R2-* rows are **44** (24 O, 20 R2), not 38; **9** G-T rows do not apply verbatim, not 6, and three of them (G-T-PATH-PRESENT, G-T-PRODUCER-IS-RUNNER, G-T-PRODUCER-KNOWN) still exist under the same guard name with changed text (their ledger rows are KILLED). | Correct the counts in the landing record. |
| R2-F9 | process-doc | minor | S5 | `--verify-manifest`: main 25 problems, vehicle 26. The only extra is "excluded set differs from the accepted lock (added `scripts/fastcycle/tests/lib/review_record_guard_analyzer.py`, `scripts/fastcycle/tests/sweep_review_record_subclauses.sh`)". Both rows carry a `reason: tool:` justification, which I checked against the files: the analyzer is a library, the sweep is a ~70-minute generator. **Flagged, not run**: closing it needs `--verify-manifest --accept-excluded-change <reviewer>`, an operator or rostered-reviewer act. Live main changed `config/full_suite_manifest.tsv` and the runner guide again in `efe2cc6`, so the merge will need `--sync-guide` again. | Operator or rostered reviewer runs the accept step after the merge with `efe2cc6`. |
| R2-F10 | process-doc | nit | all | `c7fced3`, `26c8280` and `8c0b137` have no `Roadmap-Item:` trailer (§11.4.293(A)); `8c0b137` is authored by `con033 vehicle <con033@invalid>`; the trailer model changes from Sonnet to Opus at `58b90a9`. History is not rewritten (§11.4.113); state it in the landing commit. The ledger header and the generator's header-writing line still name `test_review_record_subclause_sweep.sh` (covered by CON-072). | Landing commit note. |

Observation O1 (no finding, hypothesis refuted). I suspected the mutation runner's `trap '...' EXIT INT TERM` (no `exit`, unchanged from main) could turn an interrupt into a false KILLED. Experiment: an equivalent mutant (a one-word comment change, `EQ-comment`) added to a scratch copy, TERM sent to the runner's bash process during the mutant's suites. Result: the run continued, reported `NOT ok EQ-comment SURVIVED every suite`, rc 1. The suites run inside `$(run_suites ...)`, a subshell that does not receive a signal sent to the parent, and the parent's trap runs only after the subshell returns. A signal to the whole process group kills that subshell, which empties `KILLER` and also yields SURVIVED. Both paths fail safe. The interrupted runner does keep going instead of stopping; that is a pre-existing nit, not filed.

## Verification of the round-1 findings

| Round-1 finding | Status | Evidence (this session, fresh HOME/TMPDIR, bash 5.3.9 unless stated) |
|---|---|---|
| C1 (critical) tier check fails open | Fixed | allowlist now carries `FC_DISPATCH_TIER_POLICY` and `CLAUDE_PROJECT_DIR`; model read is `json_field tool_input model`. `test_dispatch_stamp_class.sh` 33/0 rc 0. Reviewer mutant DSM-D (drop `FC_DISPATCH_TIER_POLICY` from the allowlist) is KILLED by the class suite and the r7 matrix. Census of environment reads in `dispatch_stamp.sh` and `release_prefix.sh`: none outside the allowlist; the old dotted `json_field` call was the only one. |
| I1 r7 matrix red | Fixed | rows T01..T07 reach the five tier-check branches with required stderr text; `test_dispatch_stamp_r7_matrix.sh` 229/229 rc 0. |
| I2 1 of 295 on bash 5.3 | Fixed | probe `{ [[ "" =~ $ITEM_RE ]]; } 2>/dev/null` then `_fc_re_rc=$?`; `test_dispatch_stamp.sh` 295/0 rc 0. Reviewer mutant DSM-E (`_fc_re_rc=0`, an invalid item regex never detected): KILLED by `test_dispatch_stamp.sh`. |
| I3 project literals | Fixed | `cm_core_scripts_project_literal_free_mutation_test.sh` on the vehicle: pass=34 fail=0, CORE-SCRIPTS-LITERAL-FREE: PASS, rc 0 (main: the same). |
| I4 R4-C survives | Fixed for the reported member; class not closed | runner: R4-C KILLED by the store-tier suite. See R2-F2 and R2-F3 for the rest of the class. |
| I5 sweep interrupt / run_all | Fixed | renamed out of the `test_*.sh` glob; HUP/INT/TERM exit 129/130/143; empty list and row-count mismatch refuse; default output is a temp file. Gaps in its red test: R2-F5. |
| I6 RM1 survivor | Fixed | `test_review_record_round_budget_boundary_regression.sh` (B1a/b round 5 under default 5, B2a/b/c round 7 under budget 7 and UNCOVERED under default 5, B3 round 8 refused under 7); runner: both RM1 rows KILLED by it. Reviewer mutant RVM-A (gate budget `> budget + 1`): KILLED by r1. |
| I7 overlap with atm1217-base | Not re-opened | the differential below is identical to main for every shared test. |
| I8 Ctrl-C ignored on bash 5.3 | Fixed, with R2-F1 and R2-F4 | host 5.3.9: default `0x0`, caller ignores INT `0x2`; bookworm 5.2.15 and trixie 5.2.37: `0x0` / `0x2` in normal mode, `0x0` / `0x0` in posix mode (R2-F1). FTM-4 (no reset) KILLED by the selftest; FTM-3 (unconditional reset) passes on 5.3.9, fails on 5.2.x (R2-F4). |
| M1 stray fixture | Fixed (not re-measured beyond the diff list: no `.tmp` path in `git diff --name-status ecfe4325 dd8bd9c`) |
| M2 manifest | Done, one reviewer act left | R2-F9. |
| M3 metadata | Stays, history not rewritten | R2-F10. |
| M4 counts | Corrected in round 2; new count errors in round 2's own report | R2-F8. |
| M5 owed anchors seam | Registered (as CON-070, to be re-minted) | R2-F7. |
| RM2, RM3 | Adopted, KILLED by r4 | runner log. Reviewer mutant RVM-C (`start + count - 1`): KILLED by r4. |
| RM4 | Equivalent, confirmed by reading | `_gate_same_round_conflicts()` runs before the decision phase: different bodies in one (batch key, round) exit 4 (G-G-CONFLICTS), identical bodies merge into one unit, and `_gate_rounds_per_batch()` uses the same `_batch_key`. A live unit and a backfill unit with the same round in one batch cannot both reach the G-V-BACKFILL-SUPERSEDED comparison, so `>` and `>=` cannot differ there. Not confirmed by execution. |
| V3-N8 | KILLED | runner: `V3-N8-binding-bool-round` KILLED by r2. |

## Mutation runner and the 114-to-31 table (open decision)

Official runner on the vehicle (`test_review_record_gate_authority_mutations.sh`, fresh HOME, 1487 s): control GREEN across 10 suites, **31 of 31 KILLED, 0 NOT ok, rc 0**. Killing suite counts: r3 9, r4 9, r2 7, r1 3, round-budget boundary 2, store-tier 1.

Removed rows. Main's table has 114 rows, the vehicle's 31; 20 ids are shared and 11 are new, so **94** rows were removed:

| Group | Removed | Still apply verbatim to the vehicle's code | Do not apply |
|---|---|---|---|
| O* | 24 | 21 | O12, O13, O16 |
| R2-* | 20 | 14 | R2-B3, R2-C1, R2-C4, R2-T1, R2-T2, R2-T3 |
| G-*-off | 45 | 36 | 9 G-T rows (below) |
| V3-N1, V3-N2 | 2 | 0 | both |
| R3-M4, M5, M8 | 3 | 0 | all three |
| Total | 94 | 71 | 23 |

The 71 applicable rows were run through all 11 vehicle suites (the runner's 10 plus `test_review_record_subclause_cases.sh`), fresh HOME and TMPDIR, reniced: **71 of 71 KILLED, 0 SURVIVED, no timeout (no suite rc 124)**. The control row is GREEN on all 11 suites (every rc 0); the worktree is clean at `dd8bd9c` afterwards (`git status --porcelain` empty). Killing suites, counted per row that the suite fails: r3 36, r1 28, r2 21, subclause_cases 15, backfill_evidence_r2 11, r4 7, evidence_hash_r5 6, finding_layer_red 4, round-budget boundary 3, red 1; 34 rows are killed by exactly one suite. Result file `scratchpad/rv033r2.useS/logs/removed71.tsv`, sha256 `e5af0b616458b95459e35b37e759179ed2f43eab5c01ca4afe6d0ff0c734cbf8`. So none of the removed hand rows loses a kill by being dropped from the runner.

The 23 that no longer apply, one by one:
- Tier model rows (O16, R2-T1..T3, R3-M4/M5/M8, V3-N1/N2, and G-T-DIR-OWNER, G-T-GROUP-BIT, G-T-OTHER-BIT, G-T-OWNER-BIT, G-T-PRINCIPAL-CAN-REPLACE, G-T-ROOT): their target code is gone; the owner-only model replaces it with G-T-PATH-OWNER-ONLY, G-T-DIR-FOREIGN-WRITE, G-T-OWNER-ACCEPTABLE, G-T-LOOKUP-DEFAULT, G-T-WALK-CHAIN, G-T-CHAIN-DIR, G-T-DIR-DESCEND, G-T-LEAF-RETURN, G-T-SPLIT, G-T-LEAF-TYPE, G-ACL-NAME and G-SUB-NSS-FILES-ONLY, all KILLED in the ledger.
- G-T-PATH-PRESENT, G-T-PRODUCER-IS-RUNNER, G-T-PRODUCER-KNOWN: the guard names still exist with changed text; their ledger rows are KILLED.
- O12 (backfill history) maps to G-V-BACKFILL-LISTS; O13 (slice coverage) to G-Q-SLICES and G-Q-EVIDENCE-SLICES-GO; R2-B3 to G-R-BINDING-VALID; R2-C1 to G-V-REFUSAL-BLOCKS; R2-C4 to G-V-BACKFILL-BLOCKS. Every one has KILLED ledger rows.
- The data-flow guard G-T-STORE-ALL-ENTRIES has no ledger row by design (data-flow guards are not swept); it is covered by the store-tier suite (R4-C KILLED), but its sibling, the ledger entry of the same `paths` list, is not (R2-F2).

Ledger: 343 rows, 316 KILLED and 27 SURVIVED, every survivor listed in `review_record_equivalent_subclauses.tsv`; `tool_sha256` matches the vehicle's `review_record.py`; `test_review_record_guard_table.sh` rc 0 ("guard meta-check: complete and consistent", GT-REAL ok). 16 KILLED rows list only R4-CAP cases in their killer column. That column holds the FIRST three isolating cases (the header says so; `n` is the full count), and `R4-CAP*` sorts first, so the column alone does not show whether other cases kill them. Because R4-CAP1..7 skip on this host, I re-swept the 16 here (`sweep_review_record_subclauses.sh -j 1 <16 ids>`, no `--out`): **16 of 16 KILLED**, control GREEN with 330 passing checks. A second run with `--out` to a scratch file for two of them shows the killers on this host: G-ACL-NAME#1 by R4-OO and R4-PT (in-process, r4), G-T-LEAF-RETURN#1 by G-T-LEAF-DIR-NO-ACL and G-T-LINK-SPLIT#1 (subclause_cases). G-T-LEAF-RETURN#1 has n=2 in the committed ledger (only R4-CAP4/5) and n=2 here (two different, ACL-dependent cases), so both kills depend on the environment: UNCONFIRMED whether a host with neither a root-owned chain nor working `setfacl` kills it at all. That is the R2-F3 risk again. Conclusion: the decision to replace the hand rows by the sweep is sound for coverage, with R2-F2 as the one gap found.

Reviewer-authored mutants (§11.4.194(6)(d)), all on the vehicle, fresh HOME:

| Id | Mutation | Result |
|---|---|---|
| RVM-A | gate round budget `>` to `> budget + 1` | KILLED (r1) |
| RVM-B | `_store_tier`: ledger dropped from `paths` | **SURVIVED** all 11 suites (R2-F2) |
| RVM-C | subordinate-uid range end `start + count` to `start + count - 1` | KILLED (r4) |
| RVM-E | `_store_tier`: `os.walk` without `onerror` | KILLED (subclause_cases) |
| DSM-B | policy precedence swapped | **SURVIVED** all 5 dispatch-stamp suites (R2-F6) |
| DSM-D | allowlist drops `FC_DISPATCH_TIER_POLICY` | KILLED (class, r7) |
| DSM-E | `_fc_re_rc=0` (invalid regex never detected) | KILLED (test_dispatch_stamp.sh) |
| FTM-3 | unconditional INT/QUIT reset | passes on 5.3.9, fails on 5.2.15 and 5.2.37 (R2-F4) |
| FTM-4 | no reset | KILLED (F-A-run-intquit) |
| EQ-comment | equivalent comment change, runner interrupted by TERM | SURVIVED, rc 1 (O1) |

## Differential (same test, same rc on both trees)

main = worktree of `ecfe432`, vehicle = `dd8bd9c`, fresh HOME and TMPDIR per run.

| Test | main | vehicle |
|---|---|---|
| test_anchor_citations_red | 4 | 4 |
| test_cycle_report_red | 1 | 1 |
| test_fc_commit_stage_timer_red | 1 | 1 |
| test_fc_timer_golden_output | 2 | 2 |
| test_fc_timer_golden_output_r1restart_regression | 0 | 0 |
| test_plan_struct_causes_red | 1 | 1 |
| test_review_record_gate_authority_r1/r2/r3 | 0/0/0 | 0/0/0 |
| test_review_record_red, finding_layer_red | 0, 0 | 0, 0 |
| test_review_record_evidence_hash_r5, backfill_evidence_r2 | 0, 0 | 0, 0 |
| test_select_sample_r5_regression | 1 | 1 |
| test_token_attribution_red | 0 | 0 |
| test_review_record_guard_table | 0 | 0 |
| cm_core_scripts_project_literal_free_mutation_test | 0 (34/0) | 0 (34/0) |
| gate_constitution_generate_no_drift | 0 (no drift) | 0 (no drift, CM-CONSTITUTION-INDEX-FRESH PASS) |

Non-zero rows are the pre-existing standalone-layout failures the round-1 review and the author already recorded (no consumer layout, no constitution index). Vehicle-only suites, all rc 0 on the vehicle: r4 (18/0, with R4-CAP1..7 skipped, R2-F3), store-tier, round-budget boundary, subclause_cases, r7 matrix, sweep red test (author: 11/0). `fc_timer_selftest.sh`: 165 pass / 1 fail, the fail is check 44 (default fingerprint = this checkout's git HEAD), the same check the author reports failing on main; in my scratch copy it fails for the same reason.

## Tracker plan (CON-070..075)

The six items are new (vehicle DB minus main DB = exactly CON-070..075, and no main row changed). Their subjects (owed anchors seam, RM1 landing, ledger regeneration, SPECKIT004 images, kedge ratification, select_sample anchor) do not appear in any live item (searched live `efe2cc6` DB for kedge, mmd-08, select_sample, regenerate_if_stale, SS_N3: no hits). The author's plan (take main's DB and register again, never merge the bytes) is sound. It needs, at landing: the merge of `efe2cc6` first; the §11.4.214 check against whatever CON-030 lands; CON-033 as parent; and the old-to-new id map in the landing commit (R2-F7).

Update at hand-back (coordinator status message, checked read-only in the live checkout): main is now `1e0c9cbb5d26bc6e21e6e09d5b73c9d6e1bebb80`; the highest id in main's `docs/Issues.md` is CON-091; CON-070 has no heading on main and the coordinator says it is reserved for CON-030. So the six vehicle items must be re-minted at CON-092 or above, and the merge target is `1e0c9cbb`, not `efe2cc6`. I did not re-run the differential or the manifest check against `1e0c9cbb` (unfinished, see the hand-back).

## Required before landing (process, not findings)

1. Merge live main `1e0c9cbb` (it contains `efe2cc6`) into the vehicle (expect conflicts in `config/full_suite_manifest.tsv`, `docs/guides/full_suite_runner_guide.md` and the three tracker files); take main's tracker files and re-mint the six items (R2-F7); `--sync-guide`.
2. The excluded-lock acceptance (R2-F9), by the operator or a rostered reviewer.
3. Register R2-F1..R2-F6 as follow-up items with CON-033 as parent (§11.4.276(G.2)).
4. Landing commit records the R2-F8 counts, the R2-F10 attribution note and the id map.

Not done by this review: landing, the excluded-lock acceptance, any edit to the vehicle.
