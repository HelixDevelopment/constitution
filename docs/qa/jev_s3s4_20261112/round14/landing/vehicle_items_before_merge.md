# The six Jev vehicle items as rendered by the engine at the vehicle head 9442791d, before the merge with main

These sections are copied verbatim from `docs/Issues.md` at the round-13 vehicle head `9442791d` (rendered by the
workable-items engine from the vehicle's `docs/workable_items.db`). `main` (ebd8818c) holds different items under the
ids CON-423 to CON-428, so the merge takes main's database and these six items are NOT in it. The lander re-mints them
through the engine (`workable-items add`, then `update` for the reproduction and investigation states), never by a
hand-edited database. Until then the vehicle's text cites them by the placeholders below:

| Old id (vehicle) | Placeholder | Item |
|---|---|---|
| CON-423 | CON-PENDINGjev1 | Jev S3/S4 (the vehicle's umbrella item) |
| CON-424 | CON-PENDINGjev2 | O6-1, intermittent failure of tests/jev/test_review_fixes_r2.sh P2 |
| CON-425 | CON-PENDINGjev3 | CLOCK-BOOTSTRAP, process-start clock after long work |
| CON-426 | CON-PENDINGjev4 | MONO-FALLBACK, wall-time ages where no monotonic source exists |
| CON-427 | CON-PENDINGjev5 | DEPS-LLMCTL-REF, stale llmctl ref in helix-deps.yaml |
| CON-428 | CON-PENDINGjev6 | R12-F1, adoption after a dispose deleted the set before a slow start was recorded (with R12-B1 and R13-B1) |

Inside the sections below the ids are the OLD ones, as the engine rendered them; the machine-produced landing files of
rounds 12 and 13 (`../../round12/landing/`, `../../round13/landing/`) also keep the old ids, as recorded at the time.

## CON-423 — Jev S3/S4: honest bootstrap exit codes, default-on wiring, capacity-gated local placement, per-endpoint calibration, status control view

**Status:** In progress
**Type:** Task
**Severity:** High

What: Jev streams S3 and S4 under the operator decision of 2026-11-12 (default-on wiring when a non-placeholder key is present, opt-out marker, reversible). S3: reachable means a 2xx answer only (402 is no_credit, unusable); bootstrap exits 5 for "detected, not wired" and for "no usable endpoint", rc 0 only with nothing detected or with an explicit operator opt-out; post_update_hook STEP 4e runs bootstrap with --default-on. S4: scripts/jev/jev-place.sh capacity-gated placement producer (§11.4.291: contract-checked verdicts, leases with lock, stop only what it started on the last release, never enable/disable/switch/auto, cleanup stop after a failed start, already-running units joined and never stopped); jev-calibrate.sh per (endpoint, model) thresholds and MAIN_LLM_ALIAS discovery; jev-status.sh health, calibration age, consent, wiring, placement and leases.
Scope: scripts/jev/{bootstrap,jev-place,jev-calibrate,jev-status,jev-probe,lib_keys}.sh, scripts/post_update_hook.sh, scripts/gates/cm_jev_detection.sh, tests/jev, docs/jev, dated notes on §11.4.279/.280/.281/.282/.291.
Reproduction: before the change a 402 hosted endpoint was recorded reachable=true and bootstrap printed "detect-models: ok" with rc 0 (RED baselines in the test suite: test_s3_bootstrap_honesty.sh, test_hosted_key_discovery.sh K2).
Acceptance: jev test suite green; 20 reviewer-style mutants killed; live T3 (detection) and T4 (default-on fresh project, one real gate call, one TypeSafe row) 3/3; live T5 local placement success still owed (0/3 on 2026-11-12, host load); independent review.
UNKNOWN: whether the toolkit (claude_toolkit, owned elsewhere) will fail over from a no-credit endpoint; it does not today (T4 variant A).
Ids: this item was carried on the vehicle as CON-299 (rounds 1 to 7), CON-PENDING-JEV (rounds 8 to 10) and, in the trailer of dc654757, CON-PENDING-JEV-CONSTITUTION. main minted CON-299 for another item (land_vehicle lander), so this item is minted anew at landing (§11.4.54, §11.4.214). The round-10 landing pack (never landed) minted it as CON-388 on the vehicle database; main then minted CON-388 to CON-400 for other items, so it was minted again at the round-11 landing. The round-11 landing pack (never landed) minted it as CON-412 on f67d926c; main then minted CON-412 to CON-422 for other items, so it was minted again at the round-12 landing on 09d3ad2f. Commit trailers are not rewritten; the mapping note is in CHANGELOG.md and docs/qa/jev_s3s4_20261112/round10/README.md.
Status: rounds 1 to 12 of independent review; the round-12 head is gate-logic evidence only (§11.4.289(C)(2)), PROVISIONAL (§11.4.290); live acceptance (T5 local placement) is open.

## CON-424 — Intermittent failure of tests/jev/test_review_fixes_r2.sh P2 (bootstrap row), root cause UNKNOWN

**Status:** Queued
**Type:** Bug
**Severity:** Medium
**Reproduction:** none — UNREPRODUCED — updated 2026-11-16T08:57:10Z — by `jev-r12-fixer`
**Investigation:** not-started — updated 2026-11-16T08:57:10Z — by `jev-r12-fixer`

What: P2 of tests/jev/test_review_fixes_r2.sh failed once in a full run during Jev round 6 and has not been seen again; round 7 added an instrument (keep_bs_evidence keeps bs.out/err, gate.out, status.json, cap.json and the rc). Reproduction: 12 of 12 standalone repetitions and every run_all run passed (round 7); not reproduced in rounds 8 to 10. Next: run P2 in a loop under normal host load (at least 50 runs) and keep every instrument dump of a failure. Acceptance: a captured failing run with the instrument output, a root cause shown by a decisive experiment (§11.4.292(G)) and a RED-to-GREEN row, or closure as not-reproducible with the attempts and a control needle. Draft: docs/qa/jev_s3s4_20261112/round8/item_draft_O6-1.md (was CON-PENDING-O6-1).

## CON-425 — Jev bootstrap.sh and jev-calibrate.sh stamp record times with the process-start clock after long work

**Status:** Queued
**Type:** Bug
**Severity:** Low
**Reproduction:** none — UNREPRODUCED — updated 2026-11-16T08:57:10Z — by `jev-r12-fixer`
**Investigation:** root-cause-unconfirmed — updated 2026-11-16T08:57:10Z — by `jev-r12-fixer`

What: scripts/jev/bootstrap.sh and scripts/jev/jev-calibrate.sh read the clock once at process start and stamp generated_at, probed_at, pending_at, first_created and calibrated_at with it after long work (probes). The error makes records look older (fail-closed for freshness checks); no unsafe effect is known. Fix: stamp each field at write time. Found by the Jev round-8 census (census_stale_clock.md). Draft: docs/qa/jev_s3s4_20261112/round8/item_draft_clock_bootstrap.md (was CON-PENDING-CLOCK-BOOTSTRAP).

## CON-426 — Jev placement: ages on wall time where no monotonic source exists (decide fail-closed or a visible warning)

**Status:** Queued
**Type:** Task
**Severity:** Low

What: scripts/jev/jev-place.sh judges mark and lease ages on a monotonic clock (boot id and uptime) where /proc provides one; a host without readable /proc, and records written by an older producer without mono, are judged on wall time, so a wall-clock step can expire a live mark or lease early or keep a dead one late. Acceptance: an operator decision (§11.4.66) between refusing local placement on such a host (fail closed to the fallback route) and keeping the wall-time rule with a visible warning in status; either way status --json names the clock source in use (monotonic or wall) and a test pins it. Draft: docs/qa/jev_s3s4_20261112/round9/item_draft_mono_fallback.md (was CON-PENDING-MONO-FALLBACK).

## CON-427 — helix-deps.yaml llmctl ref is stale: records 3877467 while the recorded gitlink is 391d8177

**Status:** Queued
**Type:** Task
**Severity:** Low

What: helix-deps.yaml records llmctl ref 3877467 with the comment 'pinned sha = the recorded gitlink', but the recorded gitlink is 391d8177. The Jev round-7 reviewer measured (read-only) that 3877467 is an ancestor of 391d8177, 10 commits apart, with lib/ and bin/ identical, so the comment is false and the ref is stale. Fix: one manifest line plus the README sentence (not the same commit; same lib/bin), re-measured before the change. Note: docs/qa/jev_s3s4_20261112/round8/note_R7-G.md (was CON-PENDING-DEPS-LLMCTL-REF).

## CON-428 — Jev placement: a third acquire adopts a constitution-started unit as operator-started after a dispose deleted its set before a slow start was recorded (R12-F1)

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `docs/qa/jev_s3s4_20261112/round13/runs/r13_RED_base_r12.txt` — red-command `S4_PLACE_UNDER_TEST=<round-12 jev-place.sh> bash tests/jev/test_s4_round13.sh (rows R13-1 kill=k)` — green-command `bash tests/jev/test_s4_round13.sh (rows R13-1 kill=k)` — env `hermetic bwrap runner, stub llmctl tests/jev/fixtures/bin-place, flock gate tests/jev/fixtures/bin-flockgate; gate-logic, not a live llmctl (section 11.4.289(C)(2))` — signature `orders starCA, starAC, straCA with the starter SIGKILLed at its record lock call: 'joined the already-running unit' logged, and after the cleanup running=[decide-a] with sets={} (stops 1, starts 1)` — updated 2026-11-16T14:43:42Z — by `jev-r13-fixer`
**Investigation:** root-cause-found-with-evidence — root-cause `the in-flight start lived only in the set's starting mark; a dispose that deleted the set erased the only record that a start was running, so a third acquire saw a running unit with no set and adopted it; with the starter dead nothing recorded the start again. Decisive experiment: with a start intent that outlives the set (round 13), adoption is refused (R13-2c) and the CONTROL without the intent adopts the same unit` — evidence `docs/qa/jev_s3s4_20261112/round13/runs/final1_r13.txt` — updated 2026-11-16T17:30:14Z — by `jev-r13-fixer`

What: in a three-process interleaving, a third acquire treats a constitution-started local decision model as operator-started. Sequence: acquire A's slow start returns (its starting mark already judged expired); acquire B's dispose-stop records its result and deletes the set before A records the start; acquire C sees a running unit with no set and joins it as operator-started ('joined the already-running unit'); A's later record makes the set constitution-started again. In that window C would never stop the unit. Found by R12-10 in orders starCA and straCA of 60 (docs/qa/jev_s3s4_20261112/round12/README.md, runs/r12mc_head_discovery_R12-F1.txt). Reproduction: gate-logic only (stub llmctl, hermetic runner), not on a live host, so the state is UNREPRODUCED under section 11.4.292. In every order a running unit stays held or owed a stop and the cleanup leaves nothing running. Fix (producer change, open): keep a record of an in-flight start that survives the set deletion, or refuse adoption while a recent dispose of the profile is unanswered. Acceptance: R12-10's pinned adoption list becomes empty and is asserted empty, RED on the current producer.
