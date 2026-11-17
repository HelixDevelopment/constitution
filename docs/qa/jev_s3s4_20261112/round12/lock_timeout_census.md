# Lock-timeout sweep census, jev-place.sh, round 12

| Field | Value |
|---|---|
| Finding | R11-G (review_jev_r11.md): reviewer mutant X06 survived every suite, because no row timed out the lock on the record step of a stop |
| Instrument | `tools/lock_census.py.txt` (a copy of the scratch instrument), run on `scripts/jev/jev-place.sh` at the round-12 head |
| Output | `runs/lock_census.txt` |
| Evidence class | gate-logic (§11.4.289(C)(2)); PROVISIONAL |

## How the census works

The instrument lists every call of `with_lock` (a lease-lock section) and of `observe_read` (it takes the lock through
`with_lock`) in the producer. For each call it names the enclosing function and the code that runs when the call fails.
A line that starts with `}` ends a function, so the calls of the top-level dispatcher are reported as `(top level)`.

It runs three control needles before it reports a count:

- it must find the definition of `with_lock`;
- it must find the `do_stop` record call (`with_lock finish_stop_locked`);
- it must not find a fabricated function name.

If any needle fails, it reports BLIND and prints no count.

Result at the head: all three needles OK, 24 sites.

## Sites and the rows that time out their lock

Some rows run the producer with the lease lock held by an outside holder (`holdlock`). That is a subshell that takes the
lock and keeps it until the row frees it. Other rows use the round-6 to round-8 timeout setups. "Not timed out by a row"
means no row holds the lock at that site. The table then gives the code's handling as read, and records the gap. It
never claims coverage that does not exist.

| Line | Function | Entry | On failure | Row that times out this lock |
|---|---|---|---|---|
| 447 | record_placement | with_lock | `rc` kept, returned | round6 P63 (placement record under a lock timeout) |
| 667 | observe_read | with_lock | return 4 | through its callers: R12-5 (heartbeat, release, acquire), placement P13 |
| 720 | cmd_verdict | observe_read, with_lock | logged ("the observation could not be recorded"), exit unchanged | not timed out by a row (read only: a verdict that cannot be recorded is logged, never reported as recorded) |
| 889 | stop_turn | with_lock (arm) | `arc`, stop not run | R12-3 (release: exit 6, no stop, unit kept) |
| 912 | do_stop | with_lock (record) | retried JEV_RECORD_RETRIES times, then 4 | R12-1 (release exits 6), R12-2 (acquire starts no further candidate), R12-4 (first wait times out, second succeeds); kills X06 |
| 1201 | cmd_acquire | with_lock (gateway refuse) | `rc` | not timed out by a row |
| 1211 | cmd_acquire | observe_read | return 4 | R12-5, placement P13 (lease_lock_timeout) |
| 1213, 1214 | cmd_acquire | with_lock (plan) | `rc` (4: lease_lock_timeout) | placement P13 |
| 1250 | cmd_acquire | observe_read (per candidate) | `mrc=4`, loop ends | not timed out by a row |
| 1256, 1269 | cmd_acquire | with_lock (mark start) | `mrc`, no start | not timed out by a row |
| 1289 | cmd_acquire | with_lock (record start) | `frc`, retried | round6 P51 (a lock timeout on the record step of a successful start) |
| 1352 | cmd_acquire | observe_read, with_lock | logged, `frc` | not timed out by a row (read only: logged) |
| 1421, 1422 | (top level) heartbeat | observe_read, with_lock | exit 4 | R12-5 |
| 1428, 1429 | (top level) release | observe_read, with_lock | exit 4 | R12-5 |
| 1440, 1441 | (top level) reap | observe_read, with_lock | exit 4 | not timed out by a row |
| 1443 | (top level) status | observe_read, with_lock | logged | not timed out by a row (read only: logged) |

## Honest boundary

This census lists the lock sites. It does not prove that each failure branch is correct. For the seven table rows marked "not
timed out by a row", the handling was read from the code only, and no row exercises it. All seven are on the
`cmd_acquire`, `cmd_verdict`, `reap` and `status` paths. On each of them a failure ends without a start or a stop, or
is logged.

Rows for those sites are a tracked follow-up (`round12/README.md`, "Follow-ups"). R11-G asked for the record step of the
stop, and that step is covered by R12-1, R12-2 and R12-4.
