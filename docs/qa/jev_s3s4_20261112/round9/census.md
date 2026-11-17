# Round 9 census: "a mark, lease or stamp held across several bounded calls, or a clock read before a wait"

| Field | Value |
|---|---|
| Finding | R8-1 (review of 3bd53782), class enumeration per §11.4.276(C) |
| Producer | scripts/jev/jev-place.sh, frozen in snapshot s3, identical in the final snapshot s4 (sha256 in `frozen_s4.sha256`) |
| Evidence class | gate-logic only (§11.4.289(C)(2)): stub llmctl, hermetic runs, test clock |
| Method | (1) static: every writer of a mark, lease or age stamp and every age decision, read in the source; (2) dynamic: `tests/jev/fixtures/mark_census.py` over the per-process trace the producer writes under `JEV_TEST=1` |

## 1. The class

A record that another process judges by its age is safe only if the time it carries is the time of the risk it
covers. Two shapes break that:

- a mark or lease written once and then held while several bounded calls run (the R8-1 shape: one `stopping` mark for
  several sequential stops, so the later set's mark ages through the earlier stops);
- a clock read before a wait, then used to stamp a record after the wait (the R7-A shape, fixed in round 8).

`MARK_TTL` bounds ONE bounded call plus its record waits. So the invariant checked here is: every mark covers exactly
one bounded `llmctl` call, written immediately before it; and no lease of a process that is inside a bounded call can
expire because of that call's duration.

## 2. Static table (every site in snapshot s3)

| # | Site | Writes / judges | Covers | Verdict |
|---|---|---|---|---|
| S1 | `arm_stop_locked` (called by `stop_turn`) | `stopping` mark, `me_mark` with the current clock | the one `llmctl stop` that `stop_turn` runs next (no other bounded call in between) | one mark, one call |
| S2 | `mark_start_locked` | `starting` mark + the acquire's lease | the one `llmctl start` that follows (the freshness check runs under the same lock, no bounded call in between) | one mark, one call |
| S3 | `finish_start_locked`, released | `stopping` mark | the one `do_stop … release` that follows at once | one mark, one call |
| S4 | `finish_start_locked`, failed | `stopping` mark + `start_failed` | the one `do_stop … cleanup` that follows at once | one mark, one call |
| S5 | `plan_locked` (owed and disposal stops) | NO mark since round 9; lists the stops only | — | the R8-1 site, removed |
| S6 | `release_locked` | NO mark since round 9; lists the stops only | — | the second R8-1 site, removed |
| S7 | `lease_json` | `heartbeat_at` + `heartbeat_mono`, current clock | the lease's TTL | stamped when written |
| S8 | `hb_locked` | refreshes `heartbeat_at` + `heartbeat_mono` | — | stamped when written |
| S9 | `leases_save` (during an acquire) | refreshes the acquiring holder's heartbeat on every registry write | the next registry write of the same acquire | refreshed at every step |
| S10 | `reap_locked`, marks | judges a mark's age with `age_of` at the time of the lock | — | decision at decision time, monotonic |
| S11 | `reap_locked`, leases → `holder_alive` | judges a heartbeat's age with `age_of`; a lease whose holder is named by a LIVE mark is kept (that mark is MARK_TTL-bounded); a dead pid is never kept this way | the bounded call of the marker | decision at decision time, monotonic |
| S12 | `plan_locked`, join | no join in a plan that also stops a set; the join is decided after the stops, on a fresh answer | — | no lease taken before a sequence of stops |
| S13 | stamps of results (`gone.at`, `health.at`, `stop_owed.at`, `stop_failed.at`, `mark_cleared.at`, `started_at`, `evaluated_at`, `stopped_while_held.at`) | written under the lock with the clock read after the lock was taken (`clock_refresh`) | — | stamped when written (round 8), pinned by rows P103 to P110 |

## 3. Members of the class that remain, and why they are harmless

- **A failed release stop keeps our mark while the release goes on to its next stop** (`finish_stop_locked`, kind
  `release`, rc ≠ 0). The mark no longer covers a call in flight: its stop has returned. When it ages past `MARK_TTL`,
  the next release or acquire judges the set again and retries the stop. No live call is exposed.
- **A stop whose result could not be recorded** (every record wait timed out, `stop_turn` returns 4). Same as above: the
  mark is ours, its call has returned, and it expires and is re-judged. The release exits 6.
- **A host without `/proc`**: no monotonic source; every age is judged on wall time (the round-8 rule) and the header
  says so. A wall-clock step can then still expire a mark or lease early or late. Not fixed; a follow-up draft is in
  `item_draft_clock_bootstrap.md` (round 8) and this round's report.

## 4. Dynamic check

`mark_census.py` checks, per process in the trace, that every `llmctl stop <p>` / `llmctl start <p>` runs while `<p>`
carries this process's mark, and that the mark first appeared after this process's previous bounded call. Exit 0 =
clean, 1 = violations (each printed), 2 = BLIND (empty or unreadable trace, or `--needle` without both a checked stop
and a checked start).

Results (gate-logic, stub llmctl, §11.4.289(C)(2); files under `needle/` and `runs/`):

| Producer | Trace | Census result | Probe result |
|---|---|---|---|
| round 8 (`3bd53782`), instrumented copy `needle/r8t` (the round-9 `trace_ev` hook added, no other change) | the reviewer's multi-stop probe `needle/p_multistop_trace.sh` | `processes=4 checked_stops=2 violations=1`: `llmctl stop decide-b` ran under a stopping mark written before an earlier bounded call (exit 1) | `RESULT: LIVE stopper's mark CLEARED early` |
| round 9 | the same probe | `processes=4 checked_stops=2 violations=0` (exit 0) | `RESULT: mark kept` |
| round 9 | the whole round-9 suite, row P107 (`--needle`) | `processes=37 checked_stops=12 checked_starts=4 violations=0` (exit 0, needle satisfied) | — |
| round 8, un-instrumented | row P107 | BLIND (exit 2: no trace written), recorded as a FAIL row, never as clean | — |

The multi-stop probe has no start, so `--needle` on it is BLIND (exit 2) for both producers; the start leg of the
needle is met in row P107, whose trace has 4 checked starts. Row P107 also carries a golden-bad trace (the round-8 shape:
one violation) and a golden-good one (exit 0), and an empty trace is BLIND (exit 2). This census covers the classes in
section 1 only; it is not a claim that no other stale-age path exists.
