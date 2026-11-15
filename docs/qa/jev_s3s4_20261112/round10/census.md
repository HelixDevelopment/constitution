# Round 10 census: every lease-set write that records the result of a long operation (R9-1)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15T17:19:38Z |
| Status | active |
| Scope | `scripts/jev/jev-place.sh` at the round-10 commit; class of the round-9 review finding R9-1 |
| Evidence class | gate-logic (§11.4.289(C)(2)), PROVISIONAL |

## The class (named once)

A function that runs after a long operation outside the lock (an `llmctl start`, an `llmctl stop`, a capacity read)
and then, under the lock, writes or deletes a lease set from that operation's result. While the operation ran, the
registry may have changed: another session joined the set, another process marked it, the set was dropped, or the
writer's own mark was cleared (it is older than MARK_TTL while its writer is alive, for example after SIGSTOP or a host
suspend). Round 9 judged ownership in `finish_stop_locked` only. `finish_start_locked` replaced the set with
`leases:[]` on a failed start and deleted it on rc 75, so a lease taken in that window was lost or the model was
orphaned (§11.4.291(J)).

## The rule, one helper

`set_view <json> <profile> <mark> <own holder>` reads, in one place, four facts about a set: the claim on the
writer's mark (`noset`, `gone`, `ours` by pid AND pid_start, `foreign`), the number of leases of OTHER holders, whether
the writer's own holder still has a lease, and whether the OTHER kind of mark is set. `rule_sole` is the one rule: a
result may delete or replace a set, or write a new mark on it, only when the claim is `ours` or `gone` and there is no
other lease and no other mark. Otherwise only what is the writer's own changes: its own lease is dropped, its own mark is
cleared when it is still ours, a foreign mark is never touched, and the set is kept (constitution-started) for its
holders, with health `pending` so it is not routed until an observation newer than the result.

## Enumeration (control needle: the grep for `leases_save` returns 19 call sites; every function below holds one)

Found with `grep -n '^[a-z_]*() {' scripts/jev/jev-place.sh` and `grep -n leases_save`, read line by line.

| Site | Long operation whose result it records | Disposition in round 10 |
|---|---|---|
| `finish_start_locked` | `llmctl start` | REWRITTEN on `set_view` + `rule_sole` (placed / released / handed / refused / failed / failed_kept). P115a to P115g |
| `finish_stop_locked` | `llmctl stop` | UNIFIED on `set_view` + `rule_sole` (round 9 had its own ownership check) |
| `arm_stop_locked` | none: it runs at its own turn, after `reap_locked`, and marks only a set with no lease and no mark | unchanged; the reap-first order is now pinned by P118 (mutant R9-04) |
| `plan_locked` (joins, owed and dispose plans) | the capacity read | guarded by the freshness token (rc 99); R9-7: the reap now runs before the gateway write, P121 |
| adoption in `plan_locked` (D) | the capacity read | writes only a set that does not exist; round 10 also skips a profile this acquire tried to start (P115g) |
| `obs_locked` | the capacity read | guarded by ticket and floor; acts only on unmarked sets; drops leases only when the unit is observed gone (`endpoint_gone`, a real observation, not a stale result) |
| `mark_start_locked` | the capacity read | the freshness seam (rc 2 on a stale token) |
| `reap_locked`, `release_locked`, `hb_locked` | none (no long operation between read and write under one lock hold) | unchanged; R9-2 and R9-5 (TTL suspension by a live mark) pinned by P116 and P117 |
| `gw_refuse_locked` | the gateway probe | writes only `.gateway`, never a lease set |
| the record-late path (a result that cannot be recorded after RETRIES lock waits) | `llmctl start` / `stop` | writes nothing; the next writer judges the set |

## Honest boundary (§11.4.6)

This census covers the class above in the round-10 producer only. It is not a claim that every result path of every
future change is covered; a new long operation added to the producer must be added to this table and to the rule.
