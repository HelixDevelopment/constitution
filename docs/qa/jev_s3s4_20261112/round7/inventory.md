# CON-299 S3/S4 round 7 — class inventory (§11.4.276(C))

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | active |
| Status summary | Every member of the classes the round-6 review (of `eb29803b`) named, re-derived from the code: the (C) contract table field by field (NF-1), every path from a capacity read to `llmctl start` (NF-2), every place a mark is cleared (NF-3). Each row names the code site and the test row that covers it. |

Producer: `scripts/jev/jev-place.sh` (round-7 working tree). Line numbers are those of the round-7 commit. Evidence class
for every row below: gate-logic against the stub llmctl `tests/jev/fixtures/bin-place/llmctl` (§11.4.289(C)(2)). No live
llmctl, gateway, hosted endpoint or model ran in this round. Races are replayed in a fixed order by the test seam
`tests/jev/fixtures/bin-flockgate/flock` (pause or SIGKILL one jev-place process at its N-th flock call), never by sleeping.

## Class 1 — NF-1: the §11.4.291(C) contract table

Rule now: `capacity_read` (line 190) checks the whole table, held as data in `CONTRACT_TABLE` (one row per required field
of the canon table; the canon `host` row is split into its nine named fields), plus llmctl's own
`measurement.critical_inputs_unreadable`. `inst_state` checks the per-profile fields. Every check is wrapped in `try`, so
a field of the wrong shape is a failed check, never a jq error read as "nothing missing". An absent field, a `null` where
a value is required, or a value outside its set makes the WHOLE answer `undetermined`; the reason names the field; nothing
is started on it.

The test field list in `test_s4_round7.sh` P72 is written from the canon table (`Constitution.md` §11.4.291(C)), not from
the producer: one case per field, absent, and (where a type is defined) of a wrong type. Each case asserts rc 5, zero
`llmctl start`, verdict `undetermined` and a reason that names the field. Controls: the complete document fits and
starts once, both raw and through the computed stub.

| Canon row | Fields checked (`CONTRACT_TABLE` row / `inst_state`) | Absent | Wrong type | Mutant |
|---|---|---|---|---|
| schema | `schema == "llmctl.capacity/1"` | P72 | P72 (other value) | CT01 |
| time | `time` number | P72 | P72 | CT02 |
| profiles | `profiles` object | P72 | P72 | CT03 |
| host | `host` object; `cpus_online`, `mem_total_mb`, `mem_available_mb`, `usable_mem_mb`, `swap_total_mb`, `swap_free_mb` numbers; `load` {1,5,15} numbers; `psi` {memory.some, memory.full, cpu.some} numbers; `cgroup` object | P72 (each) | P72 (each) | CT04 to CT13 |
| reserve | `reserve` object | P72 | P72 | CT14 |
| pressure | `pressure.ok` boolean, `pressure.reasons` array | P72 | P72 | CT15, CT16 |
| llmctl.units[] status | array of objects with string `profile`, string `status`, array `reasons` | P72 | P72 (each member) | CT17 |
| fallback.recommended | string in {local, cloud, none} | P72 | P72 (out of set) | CT18 |
| fallback.key_variable | present, string or null | P72 | P72 | CT19 |
| unknown_profiles | array | P72 | P72 | CT20 |
| degraded | boolean | P72 | P72 | CT21 |
| largest_decision_fit | present, string or null | P72 | P72 | CT22 |
| profiles.<p>.verdict | in the closed set (inst_state) | P72 | P72 | NM11 |
| profiles.<p>.threads | number (inst_state) | P72 | P72 | NM12 |
| profiles.<p>.reasons | array (inst_state) | P72 | P72 | NM13 |
| profiles.<p>.headroom | object or number (inst_state) | P72 | P72 | NM14 |
| (llmctl) measurement.critical_inputs_unreadable | non-empty array → undetermined | P72 | — | NM10 |
| (producer) pressure guard | `pressure.ok:false` with verdict `fits` is `does_not_fit` | P72 (VM01 row) | — | VM01 |

The reason codes `nproc_unlimited` / `nproc_not_measured` (round 6, R5-13) are unchanged; N6-e: the specific reason of
an undetermined or not-fitting candidate is now carried into the placement record (P85, mutants NM23, NM24).

## Class 2 — NF-2: every path from a capacity read to `llmctl start`

Rule now (ONE freshness rule): a start is decided only on a capacity answer read after the last write of the lease
registry. `leases_save` raises the registry's generation counter `gen` on every write; the token (`leases_token`, line
383) is `"<gen>:<sha256 of leases.json>"`. The capacity answer is read after an observation ticket that records the
token (`take_ticket_locked`, `OBS_GEN`). Two seams compare it:

- Seam 1, `plan_locked` (line 659, and line 673 after the plan's own reap): token changed → rc 99, the answer is read
  again (at most `STALE_MAX` = 3 times), then a plan with joins and stops only (`stale_answer`, no adoption, no start).
- Seam 2, `mark_start_locked` (line 799), the last step before `llmctl start`: token changed → rc 2, the acquire plans
  again on a fresh answer (at most `STALE_MAX` times), then no start (`stale_answer`).

The generation part catches an ABA write (a failed start cleaned up leaves the same bytes except `gen`); the hash part
catches a writer that does not know `gen` (a project with an older constitution pin sharing the per-user registry).
A hash-only token would fail the ABA case only if the bytes were equal, and they never are, because `gen` is a field
inside the hashed file: so the hash-only mutant NM04 is equivalent (see `mutants.md`); the generation counter is kept
because it makes the ABA argument independent of where `gen` is stored.

Every path from a capacity read to `llmctl start` (`cmd_acquire`, lines 851–1005):

| # | Path | What guarantees a fresh answer before the start | Test rows | Mutants |
|---|---|---|---|---|
| 1 | First plan → start of the first candidate | ticket + read → seam 1 (plan) → seam 2 (mark) | P73, P74, P75, P75b, P77 | NM01, NM02, NM03, NM05, NM26, VM10 |
| 2 | The plan's own reap changed the registry | seam 1 after the reap (line 673): rc 99, read again | P77, P78 | NM02 |
| 3 | This acquire stopped a model (owed stop, disposal) | the stop is a registry write; `replan=1`, full re-plan on a fresh answer (line 891) | P81a, P86 | NM06 |
| 4 | Start refused (75) with no model started yet | the refused set is removed (a write); `replan=1` (line 975) | P81b | NM07, NM17 |
| 5 | Start failed, cleanup stop sent, no model started yet | cleanup stop is a write; `replan=1` (line 989) | P81c | NM07, NM18 |
| 6 | A further start (`JEV_PLACE_MAX` > 1) | ticket + fresh read per candidate (lines 903–915), `BASE_GEN=OBS_GEN`, seam 2; and the lease this acquire took must still be held (rc 3, line 795) | P87, P88, P70 (round 6) | NM19, NM20, NM26, OM03 |
| 7 | Refused / failed start after a model was already started | next iteration is path 6 (fresh read) | P81 (inventory property) | NM07 |
| 8 | Stale answer at the plan, `STALE_MAX` times | plan with joins and stops only, no start | P82b | NM21, NM15 |
| 9 | Stale answer at the mark, `STALE_MAX` times | no start, reason `stale_answer` | P82 | NM22 |
| 10 | `n == 0` and the mark refused because a set exists or a set is marked (rc 1) | the token was equal at that mark (checked first), so the next candidate on the same answer is judged on an unchanged registry; its own mark checks the token again | P76, P83 | VM13, NM16 |

Property test P81 (inventory): in the stub's call log, no `llmctl start` follows another start or a stop without a
`llmctl capacity` call in between, across a refused start, a failed start with cleanup, and a disposal stop.

Bounds: every loop is bounded (`STALE_MAX` re-reads per plan, `STALE_MAX` re-plans after a stale mark, a profile is
stopped (`STOP_TRIED`) or start-tried (`START_TRIED`) at most once per acquire). Mutants NM06, NM07, NM21, NM22 remove one
bound each.

Honest boundary (§11.4.6): the rule covers every writer of the lease registry, which is every constitution writer on the
host (shared per user). A model started OUTSIDE the registry (an operator `llmctl start`, another tool) changes the host
without changing the token; that case is covered only by llmctl's own start gate (exit 75 under pressure, P81b), not by
the token. The window between the mark and `llmctl start` (llmctl is never called under the lease lock, R4-3) still
exists; a second session that reads its answer in that window sees the `starting` mark in the registry (the token
changed at the mark), so it plans again.

## Class 3 — NF-3: every place a mark is cleared

| Site | Clears | Floor set | Test rows | Mutants |
|---|---|---|---|---|
| `reap_locked` (lines 466–479) | `starting` / `stopping` mark of a dead process (pid + start time), or older than `MARK_TTL` | `health = {state: pending, seq: obs_counter}` | P78 (dead starter), P79 (live starter kept until `MARK_TTL`, cleared one second later) | NM08, NM09, VM06 |
| `finish_start_locked` (line 820) | `starting` after `llmctl start` | `health = pending` at `obs_counter` (round 6) | P51, P64, P69 (round 6) | OM-series (round 6) |
| `finish_stop_locked` | `stopping` (set removed, or kept with `stop_failed`) | set removed or `stop_failed` kept (no routing) | P21, P22, P33, P40 | RM05 |

`MARK_TTL` (line 173) = start/stop timeout + 2 s (`timeout --kill-after`) + `JEV_RECORD_RETRIES` × `JEV_LOCK_TIMEOUT`
(the record waits after the start) + 30 s: the longest a live marker can hold its mark, with slack. Before round 7 it
was the stop timeout + 30 s, which could clear the mark of a live starter still waiting for its record lock.

## Other findings

| Finding | Change | Test rows |
|---|---|---|
| T6-1 (VM01, VM06, VM07, VM13; VM10 to decide) | rows written for each; VM10 is now the plan's freshness check and is killed | P72 (VM01 row), P79 (VM06), P80 (VM07), P76 (VM13), P77 (VM10) |
| T6-2 (P5 timing) | P5 waits for the stub's `cap.done` marker instead of a timing window | `test_s4_placement.sh` P5 |
| O6-1 | instrument: on a P1/P2 failure the bootstrap's rc and stderr tail are printed and the run's files are kept | `test_review_fixes_r2.sh` P1/P2; control run with a forced failing bootstrap |
| N6-a | NOT changed (a separate item by operator decision N1); noted in the producer header and the docs | — |
| N6-b | `status` with no record exits 0 and says "placement: none recorded yet" | P84 |
| N6-c | the §11.4.282 note gains the https-gateway condition (additive sentence) | — |
| N6-e | the record carries the specific reason (undetermined and does_not_fit) | P85 |
| Found in round 7 | a further start without the lease this acquire took (round 6 P70 was timing-dependent) | P88, P70 |

## Deviations from the canon wording (unchanged from round 6, still disclosed)

Disposal of a lease-less owned set instead of silent removal; the non-canon reason code `endpoint_starting`; the placement
entry is merged only into an existing detection record; a failed start that could not be recorded returns 4 and may leave
a lease; the (D) cadence, the drain before the last stop and the (D)(2) hold window are not built; no session calls
`acquire` / `heartbeat` / `release` today. New in round 7: the reason code `stale_answer` (not in the canon list) for an
answer that could not be read against an unchanged registry.
