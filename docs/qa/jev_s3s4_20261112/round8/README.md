# Jev S3/S4 round 8 (CON-PENDING-JEV): fixes for the independent review of `c811d0cd` (NO-GO: R7-A, R7-B, R7-C, R7-D, R7-G)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14 |
| Status | evidence (In progress; no GO claimed; PROVISIONAL) |
| Evidence class | gate-logic only (stub llmctl, a flock gate, an advancing test clock; §11.4.289(C)(2)). Nothing here is live evidence; no local model was started. |

## R7-A: the clock (important, host safety)

Root cause (the reviewer's probes, reproduced here as rows): `jev-place.sh` read `NOW` once at process start, and every
age-bearing field was stamped with it. A starting mark set after a disposal stop and two slow capacity reads (about 43 s
into the acquire) was therefore already as old as `MARK_TTL`, and an observer cleared the mark of a LIVE starter; the
next observation released its lease (`endpoint_gone`), stopped decide-a during its start, and a second session started
decide-c while decide-a was still starting.

Fix: `clock_now` / `clock_refresh` read the clock, and `with_lock` calls `clock_refresh` right after `flock` succeeds,
so every field written or age judged in a locked section uses the time of that section (a lock wait is not counted).
The census showed that every use of `NOW` in the producer is inside a locked section. Test seam (only with
`JEV_TEST=1`): `JEV_NOW_FILE` (an epoch in a file, read on every refresh, advanced by the stub llmctl when a call ends:
`PLACE_CAP_CLOCK_ADD`, `PLACE_START_CLOCK_ADD`, `PLACE_STOP_CLOCK_ADD`), else `JEV_NOW_EPOCH`; an unreadable clock is a
config error (exit 2). The reviewer's FIX1 was used as a hint only; this fix is different (it refreshes every field,
not only `me_mark`).

RED then GREEN (`tests/jev/test_s4_round8.sh`, hermetic, `S4_PLACE_UNDER_TEST`):

| Producer | Result | File |
|---|---|---|
| `c811d0cd` (round 7, sha256 103e0f94…) | pass 28, fail 19 (P91, P92, P93a/b/c/e) | `red_round8_on_c811d0cd.txt` |
| round 8 | pass 47, fail 0 (first run) | `green_round8_first.txt` |
| round 8 (REAL lane of the mutant run) | pass, 197 s | `mutants/REAL_r8.txt` |

Rows: P91 and P92 are the reviewer's `p_markttl_origin.sh` and `p_markttl_concurrent.sh` scaled down (start/stop
timeout 10 s, 1 record retry, lock timeout 1 s, so MARK_TTL is 43 s; stub calls of 9 s and 17 s; REAL clock), each with
control rows proving the scenario was reached (A disposed decide-b, its start is in flight, the observer runs when A's
process is older than MARK_TTL). P93 uses the advancing clock: the mark and lease at t0+100 after a 100 s capacity read,
the mark kept at exactly MARK_TTL of its own age, `started_at`, `health.at`, `evaluated_at`, `start_failed.at`,
`stop_failed.at` at their write times, a lock wait not counted, the seam ignored without `JEV_TEST=1`, an empty clock
file refused.

## R7-C: rows and mutants

| Row | Purpose | Kills |
|---|---|---|
| P94 | reviewer probe F1 (`p_floor_equal.sh`): the floor when the observer's ticket is the newest | OWN01, OWN02 |
| P95 | the start-mark freshness check runs after the reap (CRAFTED state: a stop_owed set holding a lease is not produced by this producer; defence in depth) | OWN03 |
| P96 | a last release during a start does not stop the starting set; its starter stops it | OWN10 |
| P97 | a reused pid (start time differs) is a dead marker; control: a matching start time keeps the mark | OWN07 |
| P98 | a pid-less lease is alive at its TTL and reaped one second later | OWN12 |

Standing mutant set (`mutants.md`, generated): 110 mutants (the round-7 set of 93 rebuilt on the round-8 producer,
OWN01 to OWN12, R8M01 to R8M05 for the clock): 106 killed, 4 equivalent (NM04, OM13, RM09, OWN08; arguments in
`mutants.md`, on code the round-8 diff does not touch), 0 survivors. REAL passed r8, r7, r6 and pl. OWN06 (a mark cleared
AT MARK_TTL) is now killed by P93a. The hermetic refusal guards logged 0 calls.

## R7-B: documents

Corrected: the canon §11.4.291 refinement note in `Constitution.md` (the mark's age counts from its own `at`, stamped
when written; added 2026-11-14), the producer header (MARK TTL paragraph, reap comment), `docs/jev/faq.md` 29,
`docs/jev/troubleshooting.md` (reap row), `docs/jev/governance-guide.md` (start rules), and `groups/` plus
`constitution_index.yaml` regenerated (`checks/gen_check_before.txt`, `checks/gen_check_after.txt`).
Not edited, on purpose: `round7/inventory.md` 109-111 and the round-7 `CHANGELOG.md` entry. The inventory is covered by
`round7/SHA256SUMS` (an edit broke it and was reverted); this README supersedes its sentence "the longest a live marker
can hold its mark": that held only for a mark set at the start of its acquire, until round 8. The CHANGELOG gets a
round-8 entry instead. The `Constitution.md` Revision header is unchanged: the bump is left to the lander.

## R7-D and R7-G

`item_draft_O6-1.md` (CON-PENDING-O6-1) and `note_R7-G.md` (CON-PENDING-DEPS-LLMCTL-REF); no ids minted. O6-1 was not
reproduced in round 8.

## Census of the class

`census_stale_clock.md`: control-needled (positive and negative needles; one blind BRE instrument found and not used).
The producer was the only unsafe site; `bootstrap.sh` and `jev-calibrate.sh` stamp from a start-time clock in the
fail-closed direction (records look older): draft `item_draft_clock_bootstrap.md`, not fixed here (§11.4.293).

## Final checks

`checks/static_summary.txt`: index fresh, gate ledger ratchet, §11.4.282 and §11.4.291 propagation PASS. The manifest
check first failed on the missing row for the new suite (`checks/verify_manifest.txt`); a row was added and the runner
guide census re-synced (`checks/verify_manifest_after.txt`: MANIFEST-OK). Shellcheck (warning and above): 0 on the four
changed shell files. run_all: ran 38, failed 0 (`run_all.txt`, 2002 s, guard log `checks/guard_run_all.log`: 0 refused, 101 loopback curl calls allowed). A first run (`run_all_first_curl_refused.txt`) gave ran 38, failed 3 (`test_bootstrap_e2e_stub_server.sh`, `test_decision_layer_gaps.sh`, `test_detection_matrix.sh`): the guard directory copied from the round-7 reviewer refuses every `curl`, and those three suites probe stub servers on 127.0.0.1 (all 22 lines of `checks/guard_run_all_first.log` are refused loopback calls). The round-7 guard allowed loopback `curl`; `tools/guard_lo_curl.sh.txt` does the same (control needles: a call to example.com refused, rc 126; `curl --version` allowed) and `tools/hrun_g.sh.txt` selects it. The four suites of the mutant run make no `curl` call (their guard logs are empty) and REAL passed them under the strict guard.

## Not done / UNCONFIRMED

- Nothing live: no real llmctl, no real model, no real host pressure (§11.4.289).
- The producer and the test file were frozen for the mutant run (`frozen_at_mutation_start.sha256`); later changes in
  this round were documents, the manifest row and the runner guide only.
- Reasoning effort of this fixer: UNKNOWN (not settable or readable on the dispatch path).
