# Jev S3/S4 round 6 (CON-299): structural fixes for the independent review of `5a9e72be` (NO-GO, R5-1 to R5-14, nits N5-2 and N5-3, surviving reviewer mutant RM13)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | evidence (CON-299, In progress; no GO claimed) |
| Evidence class | gate-logic only (stub llmctl, stub curl, fixture records, tripwires; §11.4.289(C)(2)). Nothing here is live evidence. |

## Why there is a round 6

`R_max` for this item is 5 (§11.4.276) and round 5 ended without GO. Under the standing operator decision recorded on
2026-11-11 (review rounds past `R_max` = 5 continue until GO, each with a fresh structural fixer and a fresh
reviewer), this round was run by a fresh fixer as a structural round (§11.4.276(E)): class inventory first
(`inventory.md`, §11.4.276(C)), then RED tests, then the fixes. That standing decision is the §11.4.276(E)(3) operator
decision for this item.

Every run was hermetic: bwrap with the real home hidden and no network, `env -i`, a decoy `HOME`, fake keys only,
`JEV_HOSTED_PROBE=0`, `GIT_SSH_COMMAND=/bin/false`, and a guard directory first on PATH whose `llmctl`,
`claude-providers`, `curl` (except loopback), `ssh`, `gh`, `glab` and `systemctl` refuse and record the call. No real
`llmctl`, hosted endpoint, network or forge call was made, and nothing was pushed. Paths: `<W>` is the scratch work
directory, `<HOME>` the operator home, `-HOME-` the user part of the session temp path.

## RED then GREEN

RED first, on the round-5 producer (`5a9e72be`, sha256 `4c689f83…`) with the FINAL round-6 test file, then GREEN on
the round-6 producer:

| File | Round-5 producer (RED) | Round-6 producer (GREEN) |
|---|---|---|
| `tests/jev/test_s4_round6.sh` (183 rows) | 96 pass / 87 fail (`red_final_round6_on_r5.txt`) | 183 pass / 0 fail (both suite passes, below) |
| `tests/jev/test_no_real_tools.sh` N3 (R5-11) | 10 pass / 1 fail (`red_n3_gate_pairs_on_r5.txt`) | 11 pass / 0 fail (`green_n3_gate_pairs_r6.txt`) |

On the round-5 producer P51d shows the reported defect directly: with `JEV_PLACE_MAX=2` and a record step that cannot
take the lock, the round-5 producer started decide-b after decide-a (`got [0 decide-b 2]`). P68 to P71 fail there as
well (no observation tickets, no start floor, no mark refusal for a later-marked stopping set, no stop on a failed fresh
answer). `red_s4_round6_on_r5_earlier_test_version.txt` is the RED of an earlier, shorter version of the same file
(85 / 75), kept for the record.

## Findings

| Finding | What changed | Tests |
|---|---|---|
| R5-1 no start after a start | After `llmctl start` rc 0 whose record step cannot take the lock, the loop ends ("lease held, start recorded late", rc 0). A further candidate is judged only on a FRESH capacity answer read after the first model is resident, and a failed fresh read ends the loop (a failed read leaves the pre-start answer in `cap.json`, so the stop is load-bearing). `mark_start_locked` refuses while any set, this process's own included, is starting or stopping, also a mark taken after this acquire planned. | P51, P51b, P51c, P51d, P64, P65, P70, P71 |
| R5-2 cache as a derived view | One writer of the `llmctl-local` entry, `derive_cache`, run by every `leases_save`; observation tickets (only a newer ticket records health); a start floor (an answer read before a start never judges the started set). `cache_register` and `cache_normalize` removed. | P52, P53, P55 (42-cell table, oracle reads the stub), P58, P68, P69 |
| R5-14 https only | Default `https://127.0.0.1:8095`; a non-https registry URL or `LLMCTL_GATEWAY_URL` is refused (`gateway_refused`); the default applied is logged. | P54 (status rc ≠ 0, no gateway listed, http registry URL, http override) |
| R5-3 | The placement record retries the lock and logs "NOT written"; never written unlocked. | P63 |
| R5-4 | `--ttl` / `JEV_LEASE_TTL` must exceed cadence + llmctl timeout (exit 2). | P56 |
| R5-5 | A heartbeat from a holder with no lease exits 3. | P57 |
| R5-6 | Canon codes `endpoint_stopping`, `endpoint_gone`; a gone endpoint releases every lease, records `endpoint_gone` with a detail, nothing is restarted. | P58, P28, P34 |
| R5-7 | An unreadable candidate list is `undetermined`. | P59 |
| R5-8 | Placement record fields `previous`, `lease`, `override_id`, `detection_merged`; lease fields `project`, `started_by_this_session`. | P60 |
| R5-9 | Round-5 shellcheck claim corrected; per-file delta vs the true base `02c10935` in `shellcheck_delta_vs_02c10935.tsv` (shellcheck 0.11.0). | — |
| R5-10 | Governance guide, troubleshooting, diagrams and user manual updated; two factual canon notes (below). | `cm_constitution_index_fresh.sh` PASS |
| R5-11 | Gate tests name a nonexistent `JEV_LLMCTL_BIN`, so no leg falls back to a PATH `llmctl`. | `test_no_real_tools.sh` N3 |
| R5-12 | `bash -s jev-gate.sh` is not wiring. | P62, `matcher_probe_r5.txt` / `matcher_probe_r6.txt` |
| R5-13 | Unlimited `RLIMIT_NPROC` is the reason code `nproc_unlimited` (asserted as a code, not a word of the prose). | P61 |
| N5-2 | The stub makes a non-running profile `does_not_fit` under host pressure, as the pinned llmctl does. | P66 |
| N5-3 | Covered by the §11.4.291 note. | — |

## Mutants

All 15 reviewer mutants (RM01 to RM14, plus RM15 rebuilt on the round-6 producer: the reviewer's fix-direction probe)
and 16 own mutants (OM01 to OM16) were run under the same hermetic harness through `S4_PLACE_UNDER_TEST`, first against
`test_s4_round6.sh`, then against `test_s4_placement.sh` only when the mutant survived the first file. Totals: 29 killed,
2 proven equivalent (RM09, OM13), 0 survivors. Two double mutants are controls for the equivalence and kill arguments.

The full table with the decisive rows is `mutants/table.md`; per-mutant outputs are `mutants/snapshot_*.txt` (tests
frozen in a snapshot while 30 mutants ran) and `mutants/final_*.txt` (the final test file, for the mutants that
survived the snapshot and got a new test: OM02, OM03, OM12, OM16, plus RM15 and the control OM02x).

How the five snapshot survivors were closed:

- OM02 (`break` → `continue` after the late record): with the default `JEV_PLACE_MAX=1` the max check ends the loop too,
  so the mutant was unobservable. P51d repeats the late-record shape with `JEV_PLACE_MAX=2` and asserts decide-b is never
  considered; killed. Control OM02x (OM02 plus OM03) is killed with a second start.
- OM03 (no mark check in `mark_start_locked`): the plan step (C) already refuses marks seen at plan time. P70 makes a
  concurrent `release` mark decide-a stopping while the acquire reads its fresh answer for decide-b (event-triggered on
  the stub log, not a fixed delay); killed.
- OM12 (`nproc_unlimited` reported as `nproc_not_measured … was unlimited`): P61 matched the word `unlimited` in the
  prose, a substring oracle. It now asserts the reason code; killed.
- OM16 (no stop on an undetermined fresh answer): no test failed the second read only. The stub gained a file knob
  (`PLACE_CAP_RC_FILE`) and P71 fails the fresh read after the start of decide-a; without the stop the mutant starts
  decide-b on the stale pre-start answer; killed.
- OM13 (map entry `refused_stopping) code=endpoint_stopping` removed): equivalent. The only site that yields
  `refused_stopping` / `refused_starting` sets `F_CODE="endpoint_$foreign"` itself. Control OM13x (both removed) is
  killed by P58.
- RM09 (derive_cache drops `stopping == null`): equivalent over every reachable registry state. Every writer that sets
  `stopping` does it on a set with no lease (`plan_locked` owed and dispose, `finish_start_locked` released and failed,
  `release_locked`), and every writer that adds a lease excludes a stopping set (the (B) join selects unmarked sets, the
  (D) adoption and `mark_start_locked` only create absent sets); all writes run under the lease lock. A lease on a
  stopping set is never produced, so the dropped term never changes the cache. It is not killable without a hand-written
  registry.

Instrument note (P41): the snapshot runs used the old P41 bound (the heartbeat must finish within 1 s). In round 6 the
heartbeat also takes an observation, and at host load ~35 to 40 it took 2 s with no lock held, a false FAIL seen under
RM02, RM04, RM05 and RM12. Each of those mutants has an independent killing row (P24, P31, P20, P30). P41 now bounds the
wait by the lock timeout (`< 4 s` with a 4 s lock timeout and an 8 s stop or start), which is what separates "waited for
the lock" from "did not". The table marks those rows as the instrument fault.

Invalid runs: an earlier batch of mutant runs read `test_s4_round6.sh` while it was being edited (bash reads a script
incrementally), so some failed with a syntax error. They are recorded in `mutants/INVALID_aborted_runs.tsv` and were
not counted; all 30 were rerun against the frozen snapshot.

## Final checks

Both suite passes ran on the final tree, one after the other, in one `systemd-run --user --scope -p TasksMax=3000` job under `nice -n 10`, each step through the hermetic harness. The sha256 of `tests/jev/*.sh`, the placement stub and `scripts/jev/*.sh` was taken before pass A and compared after pass B (`suites/tree_hash_final.txt`; the job printed TREE-UNCHANGED).

Pass A (`suites/passA/`):

| Step | rc | Time | Result |
|---|---|---|---|
| run_all | 0 | 1278s | ran 36, failed 0 |
| gate_pairs_nokeys | 0 | 91s | [test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent) |
| gate_pairs_fakekeys | 0 | 140s | [test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent) |
| fake key values in output | — | — | 0 |
| gate_bootstrap_idempotent_mutation | 0 | 70s | [mutation:bootstrap] PASS: cm_jev_bootstrap_idempotent.sh genuinely discriminates (GREEN genuine / RED mutated) |
| gate_detection_mutation | 0 | 8s | [mutation:detection] PASS: cm_jev_detection.sh genuinely discriminates (GREEN genuine / RED mutated) |
| gate_token_reduction_mutation | 0 | 2s | [mutation:token] PASS: cm_jev_token_reduction.sh genuinely discriminates (GREEN genuine / RED mutated) |
| gate_wiring_mutation | 0 | 2s | [mutation:wiring] PASS: cm_jev_wiring.sh genuinely discriminates (GREEN genuine / RED mutated) |
| test_s4_placement | 0 | 255s | # test_s4_placement.sh: pass=265 fail=0 skip=0 |
| test_s4_round6 | 0 | 340s | # test_s4_round6.sh: pass=183 fail=0 skip=0 |
| test_jev_status_health | 0 | 7s | # test_jev_status_health.sh: pass=110 fail=0 skip=0 |
| test_tab_fields | 0 | 5s | # test_tab_fields.sh: pass=15 fail=0 skip=0 |
| test_no_real_tools | 0 | 146s | # test_no_real_tools.sh: pass=11 fail=0 skip=0 |

Pass B (`suites/passB/`):

| Step | rc | Time | Result |
|---|---|---|---|
| run_all | 0 | 1704s | ran 36, failed 0 |
| gate_pairs_nokeys | 0 | 128s | [test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent) |
| gate_pairs_fakekeys | 0 | 110s | [test_gate_pairs] PASS (4 pairs GREEN+RED, propagation data pack + wrappers consistent) |
| fake key values in output | — | — | 0 |
| gate_bootstrap_idempotent_mutation | 0 | 72s | [mutation:bootstrap] PASS: cm_jev_bootstrap_idempotent.sh genuinely discriminates (GREEN genuine / RED mutated) |
| gate_detection_mutation | 0 | 8s | [mutation:detection] PASS: cm_jev_detection.sh genuinely discriminates (GREEN genuine / RED mutated) |
| gate_token_reduction_mutation | 0 | 2s | [mutation:token] PASS: cm_jev_token_reduction.sh genuinely discriminates (GREEN genuine / RED mutated) |
| gate_wiring_mutation | 0 | 2s | [mutation:wiring] PASS: cm_jev_wiring.sh genuinely discriminates (GREEN genuine / RED mutated) |
| test_s4_placement | 0 | 330s | # test_s4_placement.sh: pass=265 fail=0 skip=0 |
| test_s4_round6 | 0 | 470s | # test_s4_round6.sh: pass=183 fail=0 skip=0 |
| test_jev_status_health | 0 | 8s | # test_jev_status_health.sh: pass=110 fail=0 skip=0 |
| test_tab_fields | 0 | 7s | # test_tab_fields.sh: pass=15 fail=0 skip=0 |
| test_no_real_tools | 0 | 170s | # test_no_real_tools.sh: pass=11 fail=0 skip=0 |

Guard logs: every recorded call is `curl-loopback` (in `run_all`, requests to the fixture HTTP server on 127.0.0.1; in the gate pairs, the bootstrap mutation test and `test_no_real_tools`, one `curl --version` capability probe each, which the guard passes and logs); 0 refused calls to `llmctl`, `claude-providers`, non-loopback `curl`, `ssh`, `gh`, `glab` or `systemctl` in either pass. The `guard=` column counts loopback lines.

Static checks on the final tree (`checks/fin_*.txt`; re-run after the CHANGELOG entry and this README were written, with the same results, `checks/post_*_after_changelog.txt`): `verify-manifest` MANIFEST-OK (911 files); `cm_constitution_index_fresh.sh` PASS (no drift) and the index regeneration check PASS; `CM-GATE-LEDGER-RATCHET` PASS (unimplemented 394 = baseline 394, 0 fails). shellcheck 0.11.0, per file against the true base `02c10935`: `shellcheck_delta_vs_02c10935.tsv`; `jev-place.sh` adds only SC1091 (source not followed), the round-6 test file SC1090, SC1091, SC2015 ×4 and SC2034; `shellcheck -S error` exits 0 on `jev-place.sh`, the placement stub, `test_s4_placement.sh` and `test_s4_round6.sh`.

## Canon notes flagged for the independent review

Two factual notes were added to `Constitution.md`, each headed "Refinement note (2026-11-13, factual ... flagged for
independent review)". The normative text of §11.4.282 and §11.4.291 is unchanged.

- §11.4.282: the endpoint cache is a derived view of the lease registry, updated at the next observation; there is no
  re-evaluation cadence and no session caller yet, so "decision traffic goes first to the live-fitting local
  instances" holds only as of the last observation (review R5-10).
- §11.4.291: the pinned llmctl 3.4.1 reports a unit as `ok` or `degraded` only, and a running profile with verdict
  `running`; "starting" is the producer's own mark, not an llmctl state; a gone unit releases every lease
  (`endpoint_gone`); the clause (C) sentence that schema 1 does not carry the `RLIMIT_NPROC` headroom is stale, since
  3.4.1 emits `host.nproc.headroom` (nit N5-3).

`constitution_index.yaml` and three `groups/*.md` files were regenerated (`cm_constitution_index_fresh.sh` PASS). The
index drift was already present at `5a9e72be`; the base `02c10935` was clean.

## Deviations from the canon wording

See `inventory.md`, section "Deviations": disposal of a lease-less owned set instead of silent removal; the non-canon
reason code `endpoint_starting`; the placement entry is merged only into an existing detection record; a failed start
that could not be recorded returns 4 and may leave a lease; the (D) cadence, the drain before the last stop and the
(D)(2) hold window are not built; no session calls `acquire` / `heartbeat` / `release` today.

## Not done / UNCONFIRMED

- No session calls `acquire`, `heartbeat` or `release` today, so the lease registry, the derived cache and the placement
  record are exercised only by the tests.
- The §11.4.291(D) re-evaluation cadence, the drain before the last stop and the (D)(2) hold window are not built.
- Whether routing through the per-user cache in the claude_toolkit is lease-gated is UNCONFIRMED (not read in this round).
- No tracked item for the session-side integration was filed; the live tracker was not touched. That is owed to the
  lander.
- The R2-7 placeholder trailer of `dc654757` (`CON-PENDING-JEV-CONSTITUTION`) is left unchanged for the lander.
- Nothing live was captured: no real `llmctl`, gateway, hosted endpoint, device or model ran. Every result here is
  gate-logic class (§11.4.289(C)(2)); the decision layer's status stays "gate logic proven, behaviour not live-proven".
- The two canon notes above need the independent review before they are accepted.
