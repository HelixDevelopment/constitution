# CON-299 S3/S4 round 6 — class inventory (§11.4.276(C))

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | active |
| Status summary | Every member of the classes the round-5 review (of `5a9e72be`) named, mapped to the code site and the test row that covers it. |

Producer: `scripts/jev/jev-place.sh` (round-6 working tree). Line numbers are those of the round-6 commit. Evidence class
for every row below: gate-logic against the stub llmctl `tests/jev/fixtures/bin-place/llmctl` (§11.4.289(C)(2)); no
live llmctl was run in this round.

## Class 1 — R5-2: the endpoint cache must be a view of the lease registry, not a second state

Rule now: the `llmctl-local` entry of the endpoint cache is written at ONE point, `derive_cache`, which `leases_save`
runs after every write of `leases.json`. Routable = holds a lease, no `starting` / `stopping` mark, no `start_failed`,
no `stop_owed`, and `health.state == "ok"` recorded by an observation (ticket) newer than the set's start floor.
`cache_register` and `cache_normalize` are removed (`grep -c 'cache_register\|cache_normalize' jev-place.sh` = 0).

Every writer of `leases.json` (all go through `leases_save`, so every one re-derives the cache):

| Site (function) | What it writes | Covered by |
|---|---|---|
| `reap_locked` | dead holders dropped; `stopping`/`starting` marks cleared (`mark_cleared`) | P52, P55 (reap column), P11, P30, P31, P42 |
| `obs_locked` | `health` per unmarked set; gone set: leases released, `gone {at, detail}`; lease-less non-constitution sets forgotten; records only when its ticket is newer than the recorded one | P53, P55, P58, P28 (gone), P34 (gone), P68 (an older, slower answer never overwrites a newer observation; own mutant OM07) |
| `finish_stop_locked` (ok / failed) | set removed, or kept with `stop_failed` / `stop_owed` | P21, P22, P33, P40, P55 |
| `plan_locked` (gateway save, owed stops, join, dispose, adoption) | `.gateway`, stop marks, a joined lease, an adopted set | P25, P35, P38, P39, P54, P55 |
| `mark_start_locked` | new set with `starting` mark + the holder's lease | P41, P51, P64 |
| `finish_start_locked` | mark cleared, `health {state: pending, seq: floor}`, or released / refused / failed | P18, P26, P27, P51, P64, P69 (start floor: an answer read before the start never marks the set gone; own mutant OM08) |
| `gw_refuse_locked` | `.gateway = null` | P54 |
| `release_locked` (3 writes) | lease dropped, stop marks, forget | P21, P23, P40, P55 |
| `hb_locked` | `heartbeat_at` | P16, P57, P55 |

Subcommands × transitions: P55 runs every subcommand (`acquire`, `heartbeat`, `release`, `reap`, `status`, `verdict`)
after a setup acquire followed by each transition (`none`, `degraded`, `gone`, `pressure`, `capfail`, `dead` holder,
`recover` from degraded): 7 × 6 = 42 cells. After each cell it checks that the cache holds `llmctl-local` iff the
registry holds a lease set whose unit the STUB reports ok (an oracle independent of the producer's `health` field), and
that the read-only subcommands sent no `llmctl start` / `stop`; three control needles prove the oracle accepts a correct
entry and flags an entry naming an unheld set and a missing entry. Transitions involving a stop or a failed stop are
covered by the rows listed in the table above (P21, P22, P33, P40), not by P55.

## Class 2 — R5-1: no start after a start; the record step has one explicit rule

| Path in `cmd_acquire` start loop | Rule | Covered by |
|---|---|---|
| second candidate (`n > 0`) | a FRESH `llmctl capacity` answer is read first; only `absent:fits*` is started; undetermined fresh answer ends the loop (a failed read leaves the pre-start answer in `cap.json`, so the break is load-bearing) | P64, P71, mutant OM16 |
| mark lock timeout | `n = 0` → rc 4, else no further start | P13, P63 |
| `mark_start_locked` refuses while ANY set (own marks included) is starting / stopping, also a mark taken after this acquire planned | no second start | P41, P70, mutant OM03 |
| record step after `llmctl start` (rc 0) cannot take the lock after `JEV_RECORD_RETRIES` waits | "lease held, start recorded late", rc 0, loop ENDS (`break`) | P51, P51c, P51d (`JEV_PLACE_MAX=2`; with the default 1 the max check also ends the loop), mutant OM02 (the reviewer's RM15 fix-direction probe) |
| record step after a failed start cannot take the lock | logged; rc 4 when nothing was started; loop ends | P63 |
| released during the start | stop it again, loop ends | P41 |
| failed start whose cleanup stop also failed | loop ends | P65, P27, P36 |

## Class 3 — R5-14 / R5-6 / R5-3 / R5-4 / R5-5 / R5-7 / R5-8 / R5-13: single-site defects

| Finding | Site | Covered by | Mutant |
|---|---|---|---|
| R5-14 https only; default applied is logged | `gateway_url` (`GW_DEFAULT`, `case "$GW_URL"`); `derive_cache` requires an `https://` gateway object | P54 (failure-path: status rc ≠ 0, no gateway listed, http registry URL, http `LLMCTL_GATEWAY_URL`) | RM13, OM04 |
| R5-6 canon reasons | `write_placement` code map (`endpoint_stopping`, `endpoint_starting`, `endpoint_gone`, `lease_lock_timeout`, `gateway_refused`); `obs_locked` gone path releases leases and fills the detail | P58, P28 (gone rows), P34 (gone) | OM09, OM13 (equivalent: the one event site that yields `refused_stopping` / `refused_starting` sets `F_CODE` itself; control OM13x, both sites removed, is killed by P58), OM15 |
| R5-3 record on lock timeout | `record_placement` (retries, then logs NOT written; never unlocked) | P63 | OM11, OM14 |
| R5-4 TTL > cadence + llmctl timeout | main, `acquire` | P56, P16 | OM06 |
| R5-5 heartbeat with no lease | `hb_locked` return 3 | P57, P41 | OM05 |
| R5-7 unreadable candidate list | `candidates` (`CAND_RC`), `plan_locked` | P59 | OM10 |
| R5-8 record fields; detection merge | `write_placement` (`previous`, `lease`, `override_id`, `detection_merged`), `lease_json` (`project`, `started_by_this_session`) | P60 | — (field presence asserted by P60) |
| R5-13 unlimited nproc | `inst_state` | P61 (asserts the reason CODE, not a word of the prose) | OM12 |
| R5-12 matcher | `lib_decide.sh _jev_cmd_runs_gate` | P62, `matcher_probe_r5.txt` / `matcher_probe_r6.txt` | — |
| R5-11 gate legs reach the PATH llmctl | `cm_jev_detection_mutation_test.sh`, `test_gate_pairs.sh` (`JEV_LLMCTL_BIN` set to a nonexistent path) | `test_no_real_tools.sh` N3 (RED `red_n3_gate_pairs_on_r5.txt`, GREEN `green_n3_gate_pairs_r6.txt`) with its control | — |

## Class 4 — llmctl call sites (all bounded, all outside the lock: P43, P48, P67)

| Call | Site | Bound |
|---|---|---|
| `llmctl capacity --json` | `capacity_read` | `JEV_LLMCTL_TIMEOUT` (20 s) |
| `llmctl decide capacity --json` | `candidates` | `JEV_LLMCTL_TIMEOUT` |
| `llmctl decide status --json` | `gateway_url` | `JEV_LLMCTL_TIMEOUT` |
| `llmctl start <p>` | `cmd_acquire` (one site) | `JEV_LLMCTL_START_TIMEOUT` (300 s) |
| `llmctl stop <p>` | `do_stop` (one site) | `JEV_LLMCTL_START_TIMEOUT` |

`enable`, `disable`, `switch`, `auto` exit 2 and are never sent (P14).

## Class 5 — defaults and knobs

| Knob | Default | Check | Row |
|---|---|---|---|
| `JEV_LEASE_TTL` / `--ttl` | 900 | integer; `> JEV_REEVAL_CADENCE + JEV_LLMCTL_TIMEOUT` else exit 2 | P56 |
| `JEV_REEVAL_CADENCE` | 300 | integer at startup | P56 |
| `JEV_RECORD_RETRIES` | 3 | integer ≥ 1 at startup | P51, P63 |
| `JEV_LOCK_TIMEOUT` | 10 | — | P13 |
| `JEV_LLMCTL_TIMEOUT` / `JEV_LLMCTL_START_TIMEOUT` | 20 / 300 | — | P22, P36 |
| `JEV_PLACE_MAX` | 1 | — | P23, P34, P64 |
| `JEV_PROJECT` | basename of `git rev-parse --show-toplevel` | — | P60 |
| `LLMCTL_GATEWAY_URL` / `LLMCTL_CACERT` | registry, else `https://127.0.0.1:8095` | https only | P54 |

## Deviations from the canon wording, flagged for the independent review

1. A lease-less constitution-started set whose unit is absent is DISPOSED by the next acquire with one bounded
   `llmctl stop` (idempotent on a gone unit) rather than silently forgotten; §11.4.291(J)(3) says the set "is removed".
   Reason: the producer cannot prove the unit is really gone from one capacity answer, and a stop of a gone unit is
   harmless, while a forgotten running unit would be an orphan.
2. `endpoint_starting` is a reason code this producer uses for `refused_starting`; it is not named in canon (canon
   names `endpoint_stopping` and `endpoint_gone`).
3. The detection record is never fabricated: the placement entry is merged only into an existing, valid
   `jev-detection.json` (`detection_merged` true/false); §11.4.291(F) says the entry is written there.
4. A failed start whose result could not be recorded returns 4 while a lease written by the start mark may remain in
   the registry; the log says so and `release` cleans it.
5. The (D) re-evaluation cadence, the drain before the last stop and the (D)(2) hold window are not built; a degraded
   held set leaves the cache at the next observation, not on a timer, and its lease is kept for the caller to drain and
   release.
6. No session calls `acquire` / `heartbeat` / `release` today; whether routing through the per-user cache is
   lease-gated in the claude_toolkit is UNCONFIRMED.
