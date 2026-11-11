## CON-083 — parse_mutation.py had no test; its full-suite excluded note named the wrong importer and a test that does not cover it

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Evidence:** docs/qa/con083_verification_2026_11_05.txt
**Severity:** Medium
**Created-By:** AI (Claude Opus 5.5, CON-031 excluded-list investigation)

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T17:34:07Z
**Reported-By:** AI (Claude Opus 5.5, CON-031 excluded-list investigation)

**What:**
The excluded row of scripts/catalog-engine/lib/parse_mutation.py said: imported by parse_gate.py; tested by scripts/catalog-engine/tests. Measured: parse_gate.py only names it in a comment; scan.py imports it; the only test in scripts/catalog-engine/tests covers parse_gate.py. No runnable manifest unit referenced it. Vehicle commit 4db86ed6 adds scripts/catalog-engine/tests/test_parse_mutation.sh (10/10, 9 of 9 paired mutants killed, 4.7 s; re-run by the reviewer at 5.0 s) and 485c341d corrects the note. The reviewer's own 10 mutants: 3 killed, 7 survive; adopting them is tracked separately (FU-1). Id history (review F2, §11.4.214): first minted in the vehicle as CON-064 (commit e581a31), then CON-070 (commit 35e8d53f), re-minted as CON-083 at landing on main, because main already owns CON-064..CON-082 and CON-070 is reserved for the CON-030 vehicle. Vehicle commits 4db86ed6, 485c341d and 322c25ef name the first ids and are not rewritten (§11.4.113). Authorship (review F10): the code commits 4db86ed6, 485c341d, 322c25ef and the first registration e581a31 were written by Claude Sonnet 5.5; the merge 2595f06e, the evidence files and state records (35e8d53f) and the note corrections cd1e55ee were written by Claude Opus 5.5; the landing re-mint was done by Claude Opus 5.5. Sources (tracked, §11.4.215): docs/qa/con031_excluded_review/excluded_analysis.md, excluded_plan.md and the independent review docs/qa/con031_excluded_review/review_con031_excluded_r1.md (round 1, GO-with-follow-ups).

**Affected scope / file-scope manifest:**
scripts/catalog-engine/lib/parse_mutation.py, scripts/catalog-engine/tests/test_parse_mutation.sh, config/full_suite_manifest.tsv

**Reproduction / context:**
bash scripts/catalog-engine/tests/test_parse_mutation.sh

**Acceptance criteria:**
The test is on main as a default-tier manifest entry, passes, and every paired mutant is killed; the excluded note names scan.py and the test.

## CON-084 — capture_fc_timer_triplet.sh checks the consumer pre-build file before refusing the stand-in-only override, so test (H15) fails in a standalone clone

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Evidence:** docs/qa/con084_reproduction_2026_11_05.txt
**Severity:** Medium
**Created-By:** AI (Claude Opus 5.5, CON-031 excluded-list investigation)
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/con084_reproduction_2026_11_05.txt` — red-command `bash scripts/fastcycle/tests/test_capture_fc_timer_triplet.sh (standalone clone, no consumer pre-build file)` — green-command `the same command on the landed tool, sha256 d4ab4f43 (RED re-run on main efe2cc6c, tool sha256 17ca1cc0)` — env `host, standalone clones of main 7f72395 and efe2cc6c, test file sha256 17161f03` — signature `NOT ok (H15) rc=2: FATAL: pre-build script not found` — updated 2026-11-05T18:46:04Z — by `AI (Claude Opus 5.5, CON-031 landing)`
**Investigation:** root-cause-found-with-evidence — root-cause `the existence check of the consumer pre-build file ran before the refusal of the stand-in-only CAPTURE_TRIPLET_TREE_ROOT override, although the mode is decided from paths alone; moving the refusal first flips (H15) RED to GREEN with nothing else changed` — evidence `docs/qa/con084_reproduction_2026_11_05.txt` — updated 2026-11-05T18:46:04Z — by `AI (Claude Opus 5.5, CON-031 landing)`

RED measured 2026-11-05 on main 7f723954 in a fresh standalone clone: test_capture_fc_timer_triplet.sh check (H15) NOT ok rc=2: FATAL: pre-build script not found: <parent>/device/rockchip/rk3588/tests/pre_build_verification.sh. Root cause: the tool's existence check of the consumer pre-build file ran before the CAPTURE_TRIPLET_TREE_ROOT refusal, though the mode is decided from paths alone. Vehicle commit 322c25ef moves the refusal first; same test, same clone: all checks pass. The independent review re-ran RED on main efe2cc6c (tool sha256 17ca1cc0, rc 1, H15 NOT ok) and GREEN on vehicle cd1e55ee (tool sha256 770c41c9, rc 0, 26 checks ok). The landed tool's GREEN hash is recorded in docs/qa/con084_reproduction_2026_11_05.txt (review F8). Id history (review F2, §11.4.214): first minted in the vehicle as CON-065 (commit e581a31), then CON-071 (commit 35e8d53f), re-minted as CON-084 at landing on main, because main already owns CON-064..CON-082 and CON-070 is reserved for the CON-030 vehicle. Vehicle commits 4db86ed6, 485c341d and 322c25ef name the first ids and are not rewritten (§11.4.113). Authorship (review F10): the code commits 4db86ed6, 485c341d, 322c25ef and the first registration e581a31 were written by Claude Sonnet 5.5; the merge 2595f06e, the evidence files and state records (35e8d53f) and the note corrections cd1e55ee were written by Claude Opus 5.5; the landing re-mint was done by Claude Opus 5.5. Sources (tracked, §11.4.215): docs/qa/con031_excluded_review/excluded_analysis.md, excluded_plan.md and the independent review docs/qa/con031_excluded_review/review_con031_excluded_r1.md (round 1, GO-with-follow-ups).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/capture_fc_timer_triplet.sh

## CON-172 — Operator question: should the codegraph_safe.sh writer default (fkidx1,resolve1) follow the CON-147 Option A runner default (fkidx1,resolve1,resolve2)? (review I6-2)

**Status:** Obsolete (→ Fixed.md)
**Type:** Task
**Evidence:** docs/operator_decisions/2026-11-11_relayed_decisions.md
**Severity:** Low
**Created-By:** Claude Opus 5.5 (fix-vehicle subagent)
**Obsolete-Details:** Since: 2026-11-11T14:49:17Z; Reason: duplicate-of; Superseding-item: CON-211; Triple-check evidence: docs/operator_decisions/2026-11-11_relayed_decisions.md

Parent: CON-031. The round-1 review asked whether Option A covers the writer default; UNCONFIRMED. The default stays fkidx1,resolve1 until a recorded operator decision (section 11.4.66). Round 2 only fixed the comment wording at codegraph_safe.sh line 44. Id history (§11.4.214): minted in the full-suite fix vehicle as CON-117 (the vehicle commits 5a8476e9, 2257bfc2, 49c1c1e7, 6435c2c3 and the round-3 commit name it by that id), re-minted as CON-125 at the round-3 landing preparation because main already owns CON-108..CON-115 (ownership wave 2).

Id history, round 7 (§11.4.214): carried on the full-suite fix vehicle as CON-125, re-minted as CON-155 at the merge of main 2e8cfb90 into the vehicle (2026-11-11), because main already owns CON-116..CON-145 (fixu landing). The vehicle commits and evidence name the earlier ids and are not rewritten (§11.4.113); this note is the map.

Id history, round 8 (§11.4.214): carried on the full-suite fix vehicle as CON-155 (rounds 7-8), re-minted as CON-172 at the merge of main 27dcf518 into the vehicle head 4118f145 (2026-11-11), because main already owns CON-146..CON-162 (fsfix round 6 landing). Map of this re-mint: CON-146..CON-165 -> CON-163..CON-182 (+17, in order). Ids CON-146..CON-165 in the text above this note were written on the vehicle and name the vehicle's items; read them through this map. The text above is kept unchanged, and vehicle commits and evidence are not rewritten (§11.4.113).

Link (section 11.4.214, 2026-11-11, cg117 landing): this question is answered by CON-211 (writer default now follows the registry default fkidx1,resolve1,resolve2). Not closed: the operator decision record this item asks for is UNCONFIRMED; tracked by CON-213.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 3: the 2026-11-06 relayed instruction is confirmed as the section 11.4.66 decision approving the registry-driven writer default (fkidx1,resolve1,resolve2). Closed Obsolete, section 11.4.90 reason duplicate-of, superseding CON-211.

## CON-213 — Link CON-172 to CON-211 (same review question I6-2) and close CON-172 once the operator decision record is confirmed (cg117 review M1)

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Evidence:** docs/operator_decisions/2026-11-11_relayed_decisions.md
**Severity:** Low

Parent: CON-211. Review M1 (process-doc, minor): CON-172 (Queued) asks the same question I6-2 that CON-211 answers, and its text says the default stays fkidx1,resolve1 until a recorded operator decision (section 11.4.66); the tracker holds two contradictory statements. Done at landing: a link line was added to CON-172 and CON-211 (section 11.4.214 link, no close). UNCONFIRMED: whether the relayed 'operator instruction 2026-11-06: investigate and fix on evidence' is the section 11.4.66 decision CON-172 asked for. The lander found no recorded decision in this repository (git grep of docs/ for 2026-11-06 writer/codegraph/I6-2, and the session memory notes: none). Owed: the operator confirms (or records) the decision; then CON-172 is closed Obsolete duplicate-of CON-211 with a pointer. If the operator does not confirm, CON-211's default change needs that decision recorded.

Relayed operator decision, 2026-11-11 (record docs/operator_decisions/2026-11-11_relayed_decisions.md): decision 3: the operator confirmed that the 2026-11-06 relayed instruction is the section 11.4.66 decision. Done: CON-172 closed Obsolete duplicate-of CON-211; CON-211 carries the note. Closed Completed.

## CON-255 — fc_timer_run keeps a caller's ignored INT/QUIT only for the 'SIGINT' trap -p spelling; posix mode prints 'INT' (review R2-F1)

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Evidence:** docs/qa/con033_review/review_con033_r3.md
**Severity:** Medium
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-098, re-minted at the merge of main bdc3ac43 as CON-114 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-122 (main owns up to CON-115); old to new map: CON-098 -> CON-114 -> CON-122. Re-minted again at the merge of main 2e8cfb90 as CON-152 (main owns up to CON-145); old to new map: CON-122 -> CON-152. Re-minted again at the merge of main 27dcf518 as CON-169 (main owns up to CON-162); old to new map: CON-152 -> CON-169. Re-minted again at the merge of main fc57ad0c as CON-200 (main owns up to CON-193); old to new map: CON-169 -> CON-200. Re-minted again at the merge of main b20736f8 as CON-255 (main owns up to CON-248); old to new map: CON-200 -> CON-255.

fc_timer_run compared $(trap -p INT) with "trap -- '' SIGINT" only. In posix mode bash prints "trap -- '' INT", so a caller's ignore was reset. Source: independent review round 2 of vehicle/con033 (scratchpad/review_con033_r2.md, verdict GO-with-follow-ups, section 11.4.276(G.2)). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/timing/fc_timer.sh (fc_timer_run), fc_timer_selftest.sh, fc_timer_selftest_mutations.sh

## CON-256 — store tier: no case kills reviewer mutant RVM-B (ledger_path dropped from _store_tier's paths) (review R2-F2)

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Evidence:** docs/qa/con033_review/review_con033_r3.md
**Severity:** Medium
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-099, re-minted at the merge of main bdc3ac43 as CON-115 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-123 (main owns up to CON-115); old to new map: CON-099 -> CON-115 -> CON-123. Re-minted again at the merge of main 2e8cfb90 as CON-153 (main owns up to CON-145); old to new map: CON-123 -> CON-153. Re-minted again at the merge of main 27dcf518 as CON-170 (main owns up to CON-162); old to new map: CON-153 -> CON-170. Re-minted again at the merge of main fc57ad0c as CON-201 (main owns up to CON-193); old to new map: CON-170 -> CON-201. Re-minted again at the merge of main b20736f8 as CON-256 (main owns up to CON-248); old to new map: CON-201 -> CON-256.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:43Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
Severity important in the review (test-instrumentation): RVM-B survived every suite because the only ledger-owner proofs were the R4-CAP legs, which skip without podman and a root-owned chain. Source: independent review round 2 of vehicle/con033 (scratchpad/review_con033_r2.md, verdict GO-with-follow-ups, section 11.4.276(G.2)). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/review/review_record.py (_store_tier), scripts/fastcycle/tests/test_review_record_store_tier_all_entries_regression.sh, the mutation runner

**Reproduction / context:**
Apply RVM-B (paths = [records_dir]) and run the store-tier suite.

**Acceptance criteria:**
An in-process ledger-owner case kills RVM-B; RVM-B is a runner row and is KILLED on this host.

## CON-257 — review_record suites that skip proof legs print NOTE SKIPPED and exit 0, read as PASS (review R2-F3)

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Evidence:** docs/qa/con033_review/review_con033_r3.md
**Severity:** Medium
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-100, re-minted at the merge of main bdc3ac43 as CON-116 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-124 (main owns up to CON-115); old to new map: CON-100 -> CON-116 -> CON-124. Re-minted again at the merge of main 2e8cfb90 as CON-154 (main owns up to CON-145); old to new map: CON-124 -> CON-154. Re-minted again at the merge of main 27dcf518 as CON-171 (main owns up to CON-162); old to new map: CON-154 -> CON-171. Re-minted again at the merge of main fc57ad0c as CON-202 (main owns up to CON-193); old to new map: CON-171 -> CON-202. Re-minted again at the merge of main b20736f8 as CON-257 (main owns up to CON-248); old to new map: CON-202 -> CON-257.

Constitution 11.4.3 and 11.4.289(E): a suite whose proof legs did not run is not a PASS. This is what hid R2-F2. Source: independent review round 2 of vehicle/con033 (scratchpad/review_con033_r2.md, verdict GO-with-follow-ups, section 11.4.276(G.2)). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
the r2/r3/r4 regression suites, test_review_record_subclause_cases.sh, test_review_record_backfill_evidence_r2_regression.sh, the mutation runner, the sub-clause sweep

## CON-258 — fc_timer mutation FTM-3 is killed by the SigIgn check only on bash 5.2: record it (review R2-F4)

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Evidence:** docs/qa/con033_review/review_con033_r3.md
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-101, re-minted at the merge of main bdc3ac43 as CON-117 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-125 (main owns up to CON-115); old to new map: CON-101 -> CON-117 -> CON-125. Re-minted again at the merge of main 2e8cfb90 as CON-155 (main owns up to CON-145); old to new map: CON-125 -> CON-155. Re-minted again at the merge of main 27dcf518 as CON-172 (main owns up to CON-162); old to new map: CON-155 -> CON-172. Re-minted again at the merge of main fc57ad0c as CON-203 (main owns up to CON-193); old to new map: CON-172 -> CON-203. Re-minted again at the merge of main b20736f8 as CON-258 (main owns up to CON-248); old to new map: CON-203 -> CON-258.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:44Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
bash 5.3.9 keeps a caller's ignore across trap - in an async subshell; bash 5.2 does not. Source: independent review round 2 of vehicle/con033 (scratchpad/review_con033_r2.md, verdict GO-with-follow-ups, section 11.4.276(G.2)). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/timing/fc_timer_selftest_mutations.sh

**Reproduction / context:**
Run FTM-3 on bash 5.3.9 and on podman bash 5.2.x.

**Acceptance criteria:**
The runner's comment states that FTM-3 survives on bash 5.3.9 and fails on 5.2.x, with the measured versions.

## CON-259 — sweep red test: no HUP/INT exit case, no N_ROWS != N_TODO refusal case; two suites missing from SUITES (review R2-F5)

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Evidence:** docs/qa/con033_review/review_con033_r3.md
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-102, re-minted at the merge of main bdc3ac43 as CON-118 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-126 (main owns up to CON-115); old to new map: CON-102 -> CON-118 -> CON-126. Re-minted again at the merge of main 2e8cfb90 as CON-156 (main owns up to CON-145); old to new map: CON-126 -> CON-156. Re-minted again at the merge of main 27dcf518 as CON-173 (main owns up to CON-162); old to new map: CON-156 -> CON-173. Re-minted again at the merge of main fc57ad0c as CON-204 (main owns up to CON-193); old to new map: CON-173 -> CON-204. Re-minted again at the merge of main b20736f8 as CON-259 (main owns up to CON-248); old to new map: CON-204 -> CON-259.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:44Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
Source: independent review round 2 of vehicle/con033 (scratchpad/review_con033_r2.md, verdict GO-with-follow-ups, section 11.4.276(G.2)). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tests/test_sweep_review_record_subclauses_red.sh, scripts/fastcycle/tests/sweep_review_record_subclauses.sh

**Reproduction / context:**
Remove the HUP trap, or the row-count refusal, and run the red test.

**Acceptance criteria:**
Cases for HUP (129), INT (130) and the row-count refusal, each killing a mutant that removes the behaviour; the store-tier and round-budget suites are in SUITES.

## CON-260 — dispatch stamp: reviewer mutant DSM-B (policy precedence swapped) survives all five suites (review R2-F6)

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Evidence:** docs/qa/con033_review/review_con033_r3.md
**Severity:** Low
**Created-By:** Claude

Parent: CON-033 (vehicle/con033). Id history (section 11.4.214): minted in vehicle/con033 as CON-103, re-minted at the merge of main bdc3ac43 as CON-119 (main owned CON-092..CON-107), re-minted again at the merge of main 90efceb8 as CON-127 (main owns up to CON-115); old to new map: CON-103 -> CON-119 -> CON-127. Re-minted again at the merge of main 2e8cfb90 as CON-157 (main owns up to CON-145); old to new map: CON-127 -> CON-157. Re-minted again at the merge of main 27dcf518 as CON-174 (main owns up to CON-162); old to new map: CON-157 -> CON-174. Re-minted again at the merge of main fc57ad0c as CON-205 (main owns up to CON-193); old to new map: CON-174 -> CON-205. Re-minted again at the merge of main b20736f8 as CON-260 (main owns up to CON-248); old to new map: CON-205 -> CON-260.

**Reported-Via:** §11.4.202 reporting directive `task` on 2026-11-05T19:37:45Z
**Reported-By:** Conductor (CON-033 fix round 3 subagent, Opus 5.5)

**What (the report, verbatim):**
The precedence is unchanged from main (pre-existing); round 2 made both channels reach the re-exec. Source: independent review round 2 of vehicle/con033 (scratchpad/review_con033_r2.md, verdict GO-with-follow-ups, section 11.4.276(G.2)). Parent: CON-033 (Roadmap-Item of the CON-033 landing; parent_atm_id stays NULL because the engine sets it only for CON-033-NNN child ids, the same convention as CON-058).

**Affected scope / file-scope manifest:**
scripts/fastcycle/tokens/dispatch_stamp.sh (_fc_tier_check), scripts/fastcycle/tokens/test_dispatch_stamp_class.sh

**Reproduction / context:**
Apply DSM-B and run test_dispatch_stamp_class.sh.

**Acceptance criteria:**
A case sets FC_DISPATCH_TIER_POLICY and the project policy file with conflicting caps and asserts env wins; DSM-B fails it.

