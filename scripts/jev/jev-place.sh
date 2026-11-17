#!/usr/bin/env bash
# jev-place.sh — capacity-gated LOCAL decision-model placement producer (§11.4.291, stream S4, 2026-11-12).
#
# Reads `llmctl capacity --json` under the §11.4.291(C) contract table, keeps a per-user lease set per profile, starts
# the best fitting systemone-native decide profile ON DEMAND (a session acquires a lease), keeps the llmctl-local entry of
# the decision-endpoint cache (priority 10) as a view DERIVED from the lease registry, and stops the model when the LAST
# lease is released (only a model THIS producer started). It never calls `llmctl enable`, `disable`, `switch` or `auto`;
# every llmctl call is time-bounded and none runs while the lease lock is held.
#
# Usage:
#   jev-place.sh verdict  [--json]               placement state + verdict per candidate profile (no start, no stop)
#   jev-place.sh acquire  <holder> [--pid P] [--ttl S]   take a lease; start a fitting profile if none is running
#   jev-place.sh heartbeat <holder>              refresh a lease (exit 3 when the holder holds no lease)
#   jev-place.sh release  <holder>               drop a lease; the last release stops EVERY constitution-started model
#                                                with no lease left (bounded by the start/stop timeout)
#   jev-place.sh reap                            drop leases whose holder pid is dead or whose heartbeat expired
#   jev-place.sh status   [--json]               lease sets + last placement entry + the current route
# Every subcommand reads the capacity answer once (bounded, outside the lock) and records it on the lease sets under the
# lock: verdict, status, heartbeat, reap and release are re-evaluations too (see "Round 6" below). None of them starts or
# stops a model except acquire (start, disposal stop) and release (last-lease stop).
# Exit codes: 0 done; 2 usage / config error / cannot determine (jq absent);
#             3 heartbeat: the holder holds no lease (released, reaped, released because its endpoint is gone, or never
#               taken): the session must not route locally, a lease is never assumed (§11.4.291(J)(1));
#             4 lease lock timeout: no lease taken, the caller falls back. One exception, logged as such: when an
#               `llmctl start` FAILED and its result could not be recorded, the registry may still hold the holder's lease
#               under the starting mark; `release <holder>` removes it (a release of a holder without a lease is harmless);
#             5 no local placement (no fit / undetermined / start refused / join refused / gateway refused): the
#               placement entry names the fallback route (cloud when a non-placeholder hosted key exists, else none);
#             6 release: an `llmctl stop` failed or timed out. The lease set is KEPT (constitution_started, stopping
#               mark, stop_failed {at, rc}); once the stop mark is cleared (stopper process gone, or older than MARK_TTL,
#               see "Round 7") the next release retries the stop, and the next acquire judges the set like any other
#               lease-less set (joined when its unit is `ok`, stopped when it is degraded or gone). Never orphaned.
#               Also when the stop's mark or result could not be recorded (lock timeout). A stop that is NOT run because
#               the set changed before its turn (joined meanwhile, gone, marked by another process; see "Round 9") is not
#               a failure: release exits 0 for it and logs "not run at its turn: <reason>".
# Env (names only):
#   JEV_LLMCTL_BIN (default llmctl), JEV_LLMCTL_TIMEOUT (default 20 s, read calls), JEV_LLMCTL_START_TIMEOUT (default 300 s,
#   start and stop), JEV_PLACE_PROFILES (comma list: candidate order; default = every systemone-native decide profile in
#   llmctl order), JEV_PLACE_MAX (instances to start per acquire, default 1), JEV_LEASE_TTL (default 900 s),
#   JEV_REEVAL_CADENCE (the caller's re-evaluation cadence, consumer DATA, default 300 s; a lease TTL that is not greater
#   than the cadence + the llmctl timeout is a config error and is refused, §11.4.291(J)(1)), JEV_LOCK_TIMEOUT (default
#   10 s), JEV_RECORD_RETRIES (lock waits for the record step after an llmctl start/stop and for the placement record,
#   default 3, at least 1), JEV_PROJECT (the project named in a lease; default the basename of the git top level of the
#   working directory, else null), LLMCTL_TENANT_ID (the tenant key llmctl puts in front of its own unit names),
#   JEV_STATE_DIR / JEV_HOME (state), CMA_PROVIDERS_DIR (endpoint cache dir), LLMCTL_GATEWAY_URL / LLMCTL_CACERT (default
#   from the `llmctl decide status --json` registry, else https://127.0.0.1:8095; https:// only), JEV_NOW_FILE /
#   JEV_NOW_EPOCH (clock seams, ONLY with JEV_TEST=1: an advancing clock read from a file, else a fixed clock; see
#   "THE CLOCK" below), JEV_MONO_FILE (monotonic-clock seam, ONLY with JEV_TEST=1, see "THE MONOTONIC CLOCK"),
#   JEV_TRACE_FILE (ONLY with JEV_TEST=1: a trace of every bounded llmctl call and every registry write, read by the
#   gate-logic census tests/jev/fixtures/mark_census.py).
#
# Round 14 (structural, review of 9442791d: R13-B1; docs/qa/jev_s3s4_20261112/round14/):
# * THE START PROCESS IS NAMED BY THE INTENT, AND IT IS JUDGED, NOT THE STARTER ALONE. Round 13 judged a start intent by
#   its starter (this process) only. A starter SIGKILLed while its bounded `llmctl start` was in flight left that start
#   running (it is not this process's child any more); another acquire read the unit absent, removed the intent, stopped
#   and dropped the set, and the start then brought the unit up with no set, no lease, no owed stop and no intent: the
#   next acquire adopted it as operator-started (a leak). Now every start runs in a GATED start process
#   (scripts/jev/jev-start-gate.sh), spawned before the starting mark: the mark and the start intent written in ONE
#   registry write name that process (child {pid, pid_start}); only then is the gate opened and llmctl run (a starter that
#   dies before it closes the gate: llmctl never runs). The start is IN FLIGHT while the start process lives or its
#   process group has a member (child_running). A dead starter's intent is resolved only with an observation whose ticket
#   was taken AFTER its start process was seen gone (take_ticket_locked records which intents' start processes are gone
#   when the ticket is taken; the capacity answer is read after that), so the state that answer reports is the final
#   state of that start. While the start is in flight, or before such an observation, the intent is kept: it blocks the
#   adoption of the unit as operator-started and a second start, and it outlives any set (a stop that drops the set, a
#   reap that clears the mark). An intent written by a round-13 producer names no start process: it is in flight until
#   it is older than MARK_TTL.
#
# Round 10 (structural, review of 911c5b9a: R9-1 to R9-7; census docs/qa/jev_s3s4_20261112/round10/census.md):
# * ONE OWNERSHIP RULE FOR EVERY RESULT RECORD (R9-1). A start's result (finish_start_locked) and a stop's result
#   (finish_stop_locked) are recorded through ONE reader, set_view, and ONE rule, rule_sole: a result deletes or replaces a
#   set, or writes a new mark on it, only when the set is SOLE (the mark that covered the call is ours, pid AND pid_start,
#   or gone; no other holder has a lease; no other mark is set). Otherwise only this process's own part changes: its
#   own lease is dropped, its own mark cleared, a foreign mark never touched, and the set is kept for its holders (health
#   pending; a gone unit then releases them as endpoint_gone, announced). Before round 10 a failed start replaced the set
#   with leases:[] and a refused start deleted it, so a session that joined after the starter's mark was cleared (a
#   live starter older than MARK_TTL: SIGSTOP, a host suspend) lost its lease without notice, and the model was stopped
#   under it or re-adopted as operator-started. A profile an acquire tried to start is never adopted by that acquire as
#   operator-started. A start whose own lease was released while others hold the set is `handed` to them (not stopped,
#   not placed for this holder).
# * The plan reaps before its gateway write (R9-7); an age whose monotonic time is ahead of the reader is judged on wall
#   time, and a negative wall age is expired (R9-6).
#
# Round 9 (structural, review of 3bd53782: R8-1 to R8-6; census docs/qa/jev_s3s4_20261112/round9/census.md):
# * ONE MARK, ONE BOUNDED CALL (R8-1). A `stopping` mark is written by stop_turn -> arm_stop_locked under the lock
#   IMMEDIATELY before the one `llmctl stop` it covers, never at planning time. plan_locked and release_locked only LIST
#   the stops; each listed set is judged again at its own turn (it must still exist, be constitution-started, hold no
#   lease, carry no mark; a disposal must still be recorded degraded or absent; an owed stop must still carry its failed
#   start or owed stop). A set joined, stopped, marked or observed ok meanwhile is not stopped ("not run at its turn").
#   So MARK_TTL, which bounds ONE bounded call plus its record waits, bounds every mark a live process holds.
# * A STOP NEVER DELETES A LEASED SET (R8-2; round 10 extends the rule to every result record, see above). finish_stop_locked deletes a set on stop rc 0 only when it holds no lease
#   and its mark is ours (pid AND pid_start) or gone. Otherwise the set is KEPT with stopped_while_held {at, mono, leases,
#   kind} and health `pending` at the current observation counter; the next observation that sees the unit absent
#   releases every lease as endpoint_gone (announced, §11.4.291(J)(6)). Another stopper's mark is never cleared.
# * A LEASE IS NOT AGED OUT WHILE ITS OWN ACQUIRE RUNS A BOUNDED CALL (the same class, "a stamp held across bounded
#   calls"). reap_locked keeps a lease whose holder is named by a LIVE mark (that call is MARK_TTL-bounded); a dead pid is
#   never kept this way. During an acquire every registry write also refreshes that holder's heartbeat. An acquire that
#   stops a set takes no join in the same plan: the join is decided after the stops, on a fresh answer.
# * AGES ON A MONOTONIC CLOCK (R8-6), see "THE MONOTONIC CLOCK" below. Every mark carries {at, mono, pid, pid_start,
#   holder}; every lease carries heartbeat_mono.
#
# Round 7 (structural, review of eb29803b: NF-1, NF-2, NF-3; inventory docs/qa/jev_s3s4_20261112/round7/inventory.md):
# * THE WHOLE CONTRACT TABLE (NF-1). capacity_read checks every row of the §11.4.291(C) table (CONTRACT_TABLE: schema,
#   time, every host field, reserve, pressure, llmctl.units[] with profile/status/reasons, fallback, unknown_profiles,
#   degraded, largest_decision_fit) and llmctl's measurement.critical_inputs_unreadable; inst_state checks the
#   per-profile fields (verdict, threads, reasons, headroom). A field that is absent or of the wrong type makes the answer
#   undetermined and names the field: nothing is started on it.
# * ONE FRESHNESS RULE (NF-2). The registry carries a generation counter (`gen`), raised by EVERY write (leases_save);
#   its token is "<gen>:<sha256 of the file>" (the hash also catches a writer that does not know `gen`: a project with an
#   older constitution pin shares the per-user registry). A capacity answer is read after an observation ticket that
#   records the token; it may decide a start only while the token is unchanged. Two seams apply the rule: plan_locked
#   (rc 99: the answer is read again, at most STALE_MAX times, then a plan with joins and stops only; also when the plan's
#   own reap changed the registry) and mark_start_locked, the last step before `llmctl start` (rc 2: the acquire plans
#   again on a fresh answer, at most STALE_MAX times, then no start, reason_code stale_answer). A stop by
#   this acquire, a refused start and a failed start are registry writes too, so the next start is always decided on an
#   answer read after them; a further start (JEV_PLACE_MAX > 1) reads a fresh answer after a ticket. No `llmctl start`
#   follows a registry change without a capacity read in between. A profile is stopped or start-tried at most once per
#   acquire (STOP_TRIED, START_TRIED), so every loop is bounded.
# * MARK TTL AND FLOOR (NF-3). A starting / stopping mark whose process is alive is cleared only once the mark itself
#   (its `at`, stamped when the mark is written, see THE CLOCK, round 8) is older than MARK_TTL = the
#   start/stop timeout + 2 s (timeout's kill-after) + RETRIES x JEV_LOCK_TIMEOUT (the record waits) + 30 s: the longest
#   a live marker holds it, with slack. Clearing a mark also sets the set's health to `pending` at the current observation
#   counter (a floor): an answer read before the clear never judges the set (a start that completed with its record lost
#   is not read as endpoint_gone by an observation that began before it).
# * A FURTHER START NEEDS THE LEASE THIS ACQUIRE TOOK (found while re-deriving NF-2, test P70/P88). With JEV_PLACE_MAX
#   > 1, every further start passes the set this acquire already started to mark_start_locked; when the holder no longer
#   has a lease there (released by a concurrent `release`, or the set dropped), nothing more is started (rc 3). Before
#   round 7 a release between two starts let the second start go ahead for a session that held nothing.
# * THE GATEWAY SCHEME (nit N6-a, a separate item by operator decision N1, NOT changed here): `https://` is matched
#   case-sensitively, so `HTTPS://` is refused (fail-closed; RFC 3986 makes the scheme case-insensitive).
#
# Round 6 (structural, review of 5a9e72be: R5-1, R5-2, R5-14; inventory docs/qa/jev_s3s4_20261112/round6/inventory.md):
# * THE ENDPOINT CACHE IS A DERIVED VIEW (R5-2). The single llmctl-local entry of the per-user endpoint cache is computed
#   at ONE point, derive_cache, which leases_save runs after every write of the lease registry; no other code writes it.
#   It is a function of the registry alone: the entry exists iff the registry holds an https:// gateway and some set
#   holds >= 1 lease, carries no starting / stopping mark and no start_failed / stop_owed record, and its recorded health
#   is `ok`. It names route_pref (the set last placed or joined) when that set is routable, else the model already named
#   when it is still routable, else the first routable set (sorted).
# * HEALTH IS AN OBSERVATION (R5-2). Every subcommand takes an observation ticket under the lock (a counter in obs.seq),
#   reads `llmctl capacity --json` WITHOUT the lock, and records the instance state of every unmarked set under the lock
#   (obs_locked) only when its ticket is newer than the one already recorded on the set, so an older answer never
#   overwrites a newer one. A start that completes records the current counter as the set's floor (state `pending`), so an
#   answer read before the start cannot judge the started set. An undetermined answer records `unknown` (not routable).
#   A held set whose unit is GONE (state absent) has every lease released with reason endpoint_gone (§11.4.291(J)(6));
#   nothing is restarted. A held set whose unit is degraded keeps its leases (the session drains, then releases,
#   §11.4.291(D)(1)) and leaves the cache at once. A route change caused by an observation or a reap is announced and,
#   outside acquire, recorded (event route_changed). The (D)(2) recovery hold window is NOT built: a unit that reads ok
#   again is routed at the next observation.
# * THE RECORD STEP (R5-1). After `llmctl start` returns, its result is recorded under the lock with at most
#   JEV_RECORD_RETRIES lock waits. When every wait expires after a SUCCESSFUL start, the outcome is "lease held, start
#   recorded late": the lease of the holder is in the registry since the start mark, so acquire prints the profile and
#   exits 0; the starting mark is cleared once this process is gone (reap), after which the set is a normal held set that
#   the next observation routes. No further candidate is started after a successful start whose result is not recorded,
#   after a start whose lease was released during the start, or after a failed start whose cleanup stop failed; with
#   JEV_PLACE_MAX > 1 a further start is judged on a FRESH capacity answer read after the previous model is resident. A
#   start mark is refused while ANY set carries a starting or stopping mark, this process's own marks included. The stop
#   record step follows the same retry rule.
# * GATEWAY (R5-14, §11.4.289(I), §11.4.10): only an https:// gateway URL is registered (the key LLMCTL_API_KEY never goes
#   over plain HTTP). An http:// (or malformed) URL from LLMCTL_GATEWAY_URL or the llmctl registry is refused: acquire
#   exits 5 with event gateway_refused and the registry's gateway is cleared (so the derived entry is removed). Applying the
#   default https://127.0.0.1:8095 is logged with its cause.
# * RECORD (R5-3, R5-8): every placement record is written under the lock (bounded retries, else logged "placement record
#   NOT written"; never written unlocked). It carries reason_code, previous {profile, verdict, event, route, evaluated_at},
#   lease {holder, held}, override_id (null: no override path is built) and detection_merged; it is merged into an
#   EXISTING jev-detection.json and a missing one is never created (a fabricated detection record would be a §11.4.279
#   bluff). A lease carries holder, pid, pid_start, heartbeat_at, ttl, project and started_by_this_session.
#
# Round 5 (structural, review R4-1 to R4-3; ground truth docs/qa/jev_s3s4_20261112/round5/ground_truth.md):
# * THE CAPACITY ANSWER (§11.4.291(A)(C), pinned llmctl lib/capacity.sh): a running profile has verdict `running` and is
#   judged by the status of its OWN unit (owner `self`, unit profile = <LLMCTL_TENANT_ID>--<p> or <p>), which is exactly
#   `ok` or `degraded`. Every candidate gets ONE instance state (inst_state):
#     ok        running, own unit ok        -> joined (an existing lease set, also a lease-less constitution-started one)
#                                              or adopted as operator-started (no set); never stopped by an acquire
#     degraded  running, own unit degraded  -> does_not_fit for that instance: never joined or adopted; a lease-less
#                                              constitution-started set is stopped (§11.4.291(D)(1))
#     absent    fits / fits_with_reduced_threads / does_not_fit and no own unit -> a start candidate when it fits and
#                                              the RLIMIT_NPROC headroom and pressure checks pass; a lease-less
#                                              constitution-started set whose unit is gone is stopped and dropped
#     unknown   anything else (verdict undetermined or outside the set, running without an own unit, an own unit next
#               to a non-running verdict, a unit status outside ok/degraded) -> nothing is started, joined or stopped
#   An unlimited RLIMIT_NPROC (rlimit_soft null with a measured thread census) is reported as `nproc_unlimited`, distinct
#   from an unmeasured headroom (`nproc_not_measured`); both stay undetermined (an operator decision is owed, R5-13).
# * NO llmctl CALL UNDER THE LEASE LOCK (R4-3): the capacity answer, the candidate list and the gateway URL are read
#   before the lock; a set that needs an llmctl stop or start is MARKED under the lock (`stopping` / `starting`, naming
#   this process), the call runs with the lock released, and the result is recorded under the lock again. A `starting`
#   mark is cleared like a `stopping` mark (starter gone, or older than MARK_TTL, see "Round 7"). A set that is starting
#   or stopping refuses a new acquire (event refused_starting / refused_stopping, reason_code endpoint_starting /
#   endpoint_stopping, §11.4.291(J)(3)). (The round-5 "read again when the lease file changed" rule is replaced by the
#   round-7 freshness rule.)
# * ONE STOP HELPER (R4-1): every `llmctl stop` (last release, disposal, retry of an owed stop, cleanup after a failed
#   start) goes through do_stop -> finish_stop_locked, which drops the set on success (the derived cache follows) and
#   writes the placement record. After a successful stop the acquire reads the capacity answer again before a start.
# Verdicts (§11.4.291(A)): fits | fits_with_reduced_threads | does_not_fit | undetermined (or null when no capacity
# verdict applies: a join of a running instance, a stop). undetermined is NEVER fits. What HAPPENED is in the separate
# `event` field, closed set: placed | joined | joined_running | no_fit | undetermined | start_failed | start_refused |
# refused_stopping | refused_starting | refused_degraded | refused_join | lease_lock_timeout | stopped | stop_failed |
# endpoint_gone | gateway_refused | route_changed (write_placement refuses any other value).
# Failed start: when `llmctl start` fails (not 75) the producer stops the unit again; when that cleanup stop fails too it
# keeps a set {constitution_started:true, leases:[], start_failed, stop_failed}: never joined, never adopted as
# operator-started and never started again; every later acquire and release retries the stop. A failed disposal stop
# keeps {stop_owed, stop_failed} the same way. A reap alone never stops a model (§11.4.291(J)).
# Stop mark: a mark that names no pid (older state format) is never treated as a dead stopper; it is cleared only when it
# is older than MARK_TTL.
# Holder identity: a --pid holder records its process start time (/proc/<pid>/stat field 22); it is alive while
# /proc/<pid> exists, its start time matches and its cmdline is non-empty (a reused pid is dead). Without /proc the
# holder is alive while `kill -0` succeeds AND its heartbeat is within its TTL. A pid-less holder lives by its TTL.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_decide.sh
. "$SCRIPT_DIR/lib_decide.sh"
# shellcheck source=lib_keys.sh
. "$SCRIPT_DIR/lib_keys.sh"
command -v jq >/dev/null 2>&1 || { echo "jev-place: jq is required (cannot determine)" >&2; exit 2; }

STATE="$(jev_state_dir)"; mkdir -p "$STATE"
LEASES="$STATE/leases.json"; LOCK="$STATE/placement.lock"; PLACEMENT="$STATE/placement.json"; OBSSEQ="$STATE/obs.seq"
DETECTION="$(jev_detection_file)"
CACHE="$(jev_providers_dir)/jev-endpoints.json"
LLMCTL="${JEV_LLMCTL_BIN:-llmctl}"
RTMO="${JEV_LLMCTL_TIMEOUT:-20}"; STMO="${JEV_LLMCTL_START_TIMEOUT:-300}"
TTL_DEFAULT="${JEV_LEASE_TTL:-900}"; LOCK_TMO="${JEV_LOCK_TIMEOUT:-10}"; MAXN="${JEV_PLACE_MAX:-1}"
CADENCE="${JEV_REEVAL_CADENCE:-300}"; RETRIES="${JEV_RECORD_RETRIES:-3}"; STALE_MAX=3
TENANT="${LLMCTL_TENANT_ID:-}"
# round 8 (review R7-A): THE CLOCK. NOW is read again by with_lock each time it takes the lease lock (clock_refresh), so
# every age-bearing field (a mark's `at`, a lease's `heartbeat_at`, `started_at`, `health.at`, `start_failed.at`,
# `stop_failed.at`, `stop_owed.at`, `mark_cleared.at`, `gone.at`, the placement record's `evaluated_at`) is stamped with
# the time it is WRITTEN, and every age (MARK_TTL, a lease TTL) is judged at the time of the decision. Every one of
# them is written or judged under the lock, and no llmctl call runs under it (R4-3), so a locked section is short. Before
# round 8 NOW was read once at process start: a mark set after a disposal stop or a slow capacity read carried an `at`
# that was already old, and an observer cleared the mark of a LIVE starter early (R7-A).
# Test seams (ONLY with JEV_TEST=1, review r6 n6-1): JEV_NOW_FILE (a file holding an epoch, read on EVERY refresh: a
# clock the test advances, e.g. from the stub llmctl during a start), else JEV_NOW_EPOCH (a fixed clock).
clock_now() {
  local t; t="$(date +%s)"
  if [ "${JEV_TEST:-}" = "1" ]; then
    if [ -n "${JEV_NOW_FILE:-}" ]; then t="$(head -c 32 "$JEV_NOW_FILE" 2>/dev/null | tr -dc '0-9')"
    elif [ -n "${JEV_NOW_EPOCH:-}" ]; then t="$JEV_NOW_EPOCH"; fi
  fi
  printf '%s\n' "$t"
}
# round 9 (review R8-6): THE MONOTONIC CLOCK for every age DECISION (a mark's age, a lease heartbeat's age). Wall time
# (`date +%s`) can step (NTP, a manual set), so an age judged on it can expire a live mark or lease early, or keep a dead
# one late. The ages are compared ACROSS processes (one writes a mark, another judges it), so the source must be
# host-wide: /proc/uptime (seconds since boot; it never steps), qualified by the boot id
# (/proc/sys/kernel/random/boot_id), because uptime restarts at a reboot. Every mark and every lease heartbeat carries
# `mono` = "<boot id>:<uptime seconds>" next to the wall `at` / `heartbeat_at` (kept for people and for older readers).
# age_of judges: same boot -> monotonic difference; another boot -> expired (a record from before a reboot is never
# fresh); no `mono` (written by an older producer, or a host without /proc) -> the wall difference, the round-8 rule.
# When /proc gives no boot id or uptime, MONO_TOK is empty and every age is judged on wall time (stated, not hidden).
# Test seams (ONLY with JEV_TEST=1): JEV_MONO_FILE (a file holding the monotonic seconds; boot id "test"); else, when a
# wall seam is set, the monotonic clock FOLLOWS the wall seam (boot id "test"), so a test that advances JEV_NOW_FILE
# advances both. A test that steps only JEV_NOW_FILE with JEV_MONO_FILE set replays an NTP step.
mono_now() { # -> "<boot>:<seconds>" or "" (no monotonic source)
  local b="" u=""
  if [ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_MONO_FILE:-}" ]; then
    u="$(head -c 32 "$JEV_MONO_FILE" 2>/dev/null | tr -dc '0-9')"; [ -n "$u" ] && { printf 'test:%s\n' "$u"; return 0; }
    printf '!unreadable\n'; return 0   # a sentinel: clock_refresh (the caller's shell, not this subshell) exits 2
  fi
  if [ "${JEV_TEST:-}" = "1" ] && { [ -n "${JEV_NOW_FILE:-}" ] || [ -n "${JEV_NOW_EPOCH:-}" ]; }; then printf 'test:%s\n' "$NOW"; return 0; fi
  b="$(tr -dc '0-9a-f-' < /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  u="$(cut -d. -f1 < /proc/uptime 2>/dev/null | tr -dc '0-9' || true)"
  if [ -n "$b" ] && [ -n "$u" ]; then printf '%s:%s\n' "$b" "$u"; else printf '\n'; fi
}
clock_refresh() {
  NOW="$(clock_now)"
  case "$NOW" in ''|*[!0-9]*) echo "jev-place: the clock could not be read (JEV_NOW_FILE unreadable or not an epoch; config error)" >&2; exit 2 ;; esac
  MONO_TOK="$(mono_now)"
  case "$MONO_TOK" in '!'*) echo "jev-place: the monotonic clock could not be read (JEV_MONO_FILE unreadable or not a number; config error)" >&2; exit 2 ;; esac
  MONO_BOOT="${MONO_TOK%%:*}"; MONO_T="${MONO_TOK##*:}"
}
AGE_EXPIRED=1099511627776   # 2^40 s: the age of a record from another boot (always older than any TTL)
# age_of <wall-at> <mono|null|""> -> seconds since the record was written, judged at NOW / MONO_TOK (see above)
age_of() {
  local at="${1:-0}" mo="${2:-}" b t
  case "$at" in ''|*[!0-9]*) at=0 ;; esac
  if [ -n "$MONO_TOK" ] && [ -n "$mo" ] && [ "$mo" != null ]; then
    b="${mo%%:*}"; t="${mo##*:}"
    case "$t" in ''|*[!0-9]*) echo "$AGE_EXPIRED"; return 0 ;; esac
    if [ "$b" != "$MONO_BOOT" ]; then echo "$AGE_EXPIRED"; return 0; fi
    # round 10 (R9-6): a record whose monotonic time is AHEAD of the reader (a corrupted file; containers that share the
    # state dir and the boot id but read a virtualised /proc/uptime) has no usable monotonic age: it is judged on wall
    # time instead, and a wall age that is negative too is expired (never "fresh for ever")
    if [ "$t" -le "$MONO_T" ]; then echo $(( MONO_T - t )); return 0; fi
  fi
  if [ "$at" -gt "$NOW" ]; then echo "$AGE_EXPIRED"; return 0; fi
  echo $(( NOW - at ))
}
clock_refresh
for n in "$RTMO" "$STMO" "$TTL_DEFAULT" "$LOCK_TMO" "$MAXN" "$CADENCE" "$RETRIES"; do case "$n" in ''|*[!0-9]*) echo "jev-place: numeric setting expected, got '$n' (config error)" >&2; exit 2 ;; esac; done
[ "$RETRIES" -ge 1 ] || { echo "jev-place: JEV_RECORD_RETRIES must be at least 1 (config error)" >&2; exit 2; }
# round 7 (NF-3): the longest a LIVE process holds a starting / stopping mark: the bounded llmctl call (STMO + the 2 s
# kill-after of `timeout`) plus every record wait (RETRIES x LOCK_TMO); 30 s of slack on top. A mark older than this
# whose process is still alive is a hung marker and is cleared. Round 9 (R8-1): this bound holds because every mark
# covers exactly ONE bounded call (it is written immediately before it); a mark covering several calls would need N times
# this and was the R8-1 defect.
MARK_TTL=$(( STMO + 2 + RETRIES * LOCK_TMO + 30 ))
log() { printf '[jev-place] %s\n' "$*" >&2; }
WORK="$(mktemp -d)"; trap 'rm -rf "${WORK:?}"' EXIT
US=$'\x1f'
PROJECT="${JEV_PROJECT:-}"
if [ -z "$PROJECT" ] && command -v git >/dev/null 2>&1; then PROJECT="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || true)")"; [ "$PROJECT" != "." ] || PROJECT=""; fi
HOLDER=""            # the holder of the running subcommand (acquire / heartbeat / release), named in the placement record
GW_DEFAULT="https://127.0.0.1:8095"

# trace_ev (ONLY with JEV_TEST=1 and JEV_TRACE_FILE set; round 9, R8-1 census): one line per bounded call and per registry
# write, read by tests/jev/fixtures/mark_census.py (a gate-logic instrument). It never runs in production.
trace_ev() { [ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_TRACE_FILE:-}" ] && printf '%s %s %s\n' "$1" "$$" "$2" >> "$JEV_TRACE_FILE"; return 0; }
bounded() { # bounded <seconds> <out> cmd... -> rc of cmd (124/137 on timeout)
  local t="$1" o="$2" rc=0; shift 2
  trace_ev call "$*"
  timeout --kill-after=2 "$t" "$@" >"$o" 2>"$o.err" </dev/null || rc=$?
  return "$rc"
}

# ---- round 14 (R13-B1): the GATED start process ------------------------------------------------------------------------
# gate_open <profile> (NEVER under the lock: the start process must not inherit the lock descriptor) -> 0 and GATE_PID /
# GATE_PST set: a start process (scripts/jev/jev-start-gate.sh) waits on its gate; 1 (GATE_WHY set): no gate could be
# set up (no /proc/self/fd, no fifo), nothing is started. gate_go runs the start (after the registry write that names
# GATE_PID), gate_cancel closes the gate without a start; exactly one of them follows every successful gate_open.
START_GATE="$SCRIPT_DIR/jev-start-gate.sh"
GATE_PID=""; GATE_PST=""; GATE_FD=""; GATE_FIFO=""; GATE_WHY=""; GATE_N=0
gate_open() {
  local p="$1"
  GATE_PID=""; GATE_PST=""; GATE_WHY=""
  if [ ! -d /proc/self/fd ]; then GATE_WHY="no /proc/self/fd: the start process cannot be gated and named (fail-closed, no start)"; return 1; fi
  [ -r "$START_GATE" ] || { GATE_WHY="the start gate $START_GATE is missing (no start)"; return 1; }
  GATE_N=$((GATE_N+1)); GATE_FIFO="$WORK/start.gate.$GATE_N"
  mkfifo -m 600 "$GATE_FIFO" 2>/dev/null || { GATE_WHY="mkfifo $GATE_FIFO failed (no start)"; return 1; }
  exec {GATE_FD}<>"$GATE_FIFO"
  rm -f -- "${WORK:?}/start.out.went"
  bash "$START_GATE" "$GATE_FIFO" "$WORK/start.out" "$STMO" "$LLMCTL" start "$p" {GATE_FD}>&- </dev/null >/dev/null 2>&1 &
  GATE_PID=$!
  GATE_PST="$(proc_start "$GATE_PID")"
  return 0
}
gate_close_fd() { [ -z "$GATE_FD" ] || exec {GATE_FD}>&-; GATE_FD=""; [ -z "$GATE_FIFO" ] || rm -f -- "$GATE_FIFO"; GATE_FIFO=""; }
gate_cancel() { # the start process exits 79 without running llmctl; waited for, so it never outlives this decision
  [ -n "$GATE_PID" ] || return 0
  printf 'no\n' >&"$GATE_FD" 2>/dev/null || true
  wait "$GATE_PID" 2>/dev/null || true
  gate_close_fd; GATE_PID=""; GATE_PST=""
}
gate_go() { # gate_go <profile> -> the start's exit code (79 mapped to 75 when llmctl never ran: nothing was started)
  local p="$1" rc=0
  trace_ev call "$LLMCTL start $p"
  printf 'go\n' >&"$GATE_FD"
  wait "$GATE_PID" || rc=$?
  gate_close_fd
  if [ ! -e "$WORK/start.out.went" ]; then
    log "the start process of $p (pid $GATE_PID) exited $rc before it ran llmctl (its gate could not be read): nothing was started; recorded as a refused start (rc 75)"
    rc=75
  fi
  GATE_PID=""; GATE_PST=""
  return "$rc"
}
# child_running <pid> <pid_start> -> 0 when the start process named by an intent may still run (the pid with its start
# time lives, or a process of its process group lives); 1 when it is PROVABLY gone. A pid can never be reused while it
# is the id of a live process group, so a pid that names another process (another start time) proves the group gone too.
# Fail-safe: no pid, a pid that is not an integer > 1 (§11.4.263: no group id <= 1 is ever used), or no start time to
# tell a reused pid from ours -> running. Without /proc: kill -0 on the pid and on the group (a reused pid keeps it
# running: stated, never a release of a start that may run).
child_running() {
  local c="$1" cs="${2:-}" cur
  case "$c" in ''|null|*[!0-9]*) return 0 ;; esac
  [ "$c" -gt 1 ] || return 0
  if [ -d /proc/self ]; then
    if [ -d "/proc/$c" ]; then
      [ -n "$cs" ] && [ "$cs" != null ] || return 0
      cur="$(proc_start "$c")"
      if [ -n "$cur" ] && [ "$cur" != "$cs" ]; then return 1; fi
      # the same process: alive, or a zombie whose process group may still hold the running llmctl
      [ -z "$(head -c 64 "/proc/$c/cmdline" 2>/dev/null | tr -d '\0')" ] || return 0
    fi
    kill -0 -- "-$c" 2>/dev/null && return 0
    return 1
  fi
  kill -0 "$c" 2>/dev/null && return 0
  kill -0 -- "-$c" 2>/dev/null && return 0
  return 1
}

# ---- §11.4.291(C) contract table: schema llmctl.capacity/1 -------------------------------------------------
# capacity_read -> writes $WORK/cap.json and prints "ok" or "undetermined<US><reason>". NEVER called under the lock.
capacity_read() {
  local rc=0
  bounded "$RTMO" "$WORK/cap.raw" "$LLMCTL" capacity --json || rc=$?
  case "$rc" in 0|75|3) ;; 124|137) printf 'undetermined%sllmctl capacity timed out after %ss\n' "$US" "$RTMO"; return 0 ;;
    *) printf 'undetermined%sllmctl capacity exit %s (not an answer code 0/75/3)\n' "$US" "$rc"; return 0 ;; esac
  if ! jq -e . "$WORK/cap.raw" >"$WORK/cap.json" 2>/dev/null; then printf 'undetermined%sunparseable capacity output\n' "$US"; return 0; fi
  # llmctl's own failed measurement (measurement.ok false; exit 75 with no profile named): every verdict is undetermined
  if [ "$(jq -r '.measurement.ok == false' "$WORK/cap.json")" = true ]; then
    printf 'undetermined%sllmctl measurement failed: %s\n' "$US" "$(jq -r '.measurement.reason // "no reason given"' "$WORK/cap.json" | tr -d '\037\n')"; return 0
  fi
  # Round 7 (NF-1): EVERY row of the §11.4.291(C) contract table, one check per field (CONTRACT_TABLE below). A required
  # field that is absent, null where a value is required, or outside its set makes the WHOLE answer undetermined (no start).
  # Each check is wrapped in try: a field of the wrong shape (a string where an object is expected) is a failed check,
  # never a jq error read as "no field missing". Per-profile fields (verdict, threads, reasons, headroom) are checked per
  # candidate in inst_state; the unit status VALUE (ok | degraded) is judged per candidate there too (P45).
  local miss crit
  if ! miss="$(jq -r "$CONTRACT_TABLE"' | map(select(.[1] != true) | .[0]) | join(",")' "$WORK/cap.json" 2>/dev/null)"; then
    printf 'undetermined%scontract check failed on the document (not one JSON object)\n' "$US"; return 0
  fi
  if [ -n "$miss" ]; then printf 'undetermined%scontract fields missing or wrong: %s\n' "$US" "$miss"; return 0; fi
  # llmctl's own list of verdict-critical inputs it could not read (non-strict mode leaves measurement.ok true): a value
  # that could not be read is never defaulted (§11.4.291(C), §11.4.6), so any entry makes the answer undetermined
  crit="$(jq -r 'if (.measurement.critical_inputs_unreadable|type) == "array" then (.measurement.critical_inputs_unreadable | map(tostring) | join("; ")) else "" end' "$WORK/cap.json" 2>/dev/null || true)"
  if [ -n "$crit" ]; then printf 'undetermined%sllmctl could not read verdict-critical inputs: %s\n' "$US" "$(printf '%s' "$crit" | tr -d '\037\n')"; return 0; fi
  echo ok
}
# The §11.4.291(C) contract table (schema llmctl.capacity/1) as data: [field, check]. One row per required field of the
# canon table; the host row of the canon table is split into its nine named fields. A check is true when the field is
# present and in its set. load: the three averages are numbers; psi: memory some/full and cpu some are numbers (the inputs
# clause (C) names; null means unread); cgroup: an object (its limits may be null: unlimited); key_variable and
# largest_decision_fit: present, a string or null.
CONTRACT_TABLE='def num(f): (f | type) == "number"; def ok(f): (try (f) catch false) == true;
  [ ["schema",                ok((.schema == "llmctl.capacity/1"))],
    ["time",                  ok(num(.time))],
    ["profiles",              ok(((.profiles | type) == "object"))],
    ["host",                  ok(((.host | type) == "object"))],
    ["host.cpus_online",      ok(num(.host.cpus_online))],
    ["host.mem_total_mb",     ok(num(.host.mem_total_mb))],
    ["host.mem_available_mb", ok(num(.host.mem_available_mb))],
    ["host.usable_mem_mb",    ok(num(.host.usable_mem_mb))],
    ["host.swap_total_mb",    ok(num(.host.swap_total_mb))],
    ["host.swap_free_mb",     ok(num(.host.swap_free_mb))],
    ["host.load",             ok(((.host.load | type) == "object" and num(.host.load["1"]) and num(.host.load["5"]) and num(.host.load["15"])))],
    ["host.psi",              ok(((.host.psi | type) == "object" and num(.host.psi.memory.some) and num(.host.psi.memory.full) and num(.host.psi.cpu.some)))],
    ["host.cgroup",           ok(((.host.cgroup | type) == "object"))],
    ["reserve",               ok(((.reserve | type) == "object"))],
    ["pressure.ok",           ok(((.pressure | type) == "object" and (.pressure.ok | type) == "boolean"))],
    ["pressure.reasons",      ok(((.pressure.reasons | type) == "array"))],
    ["llmctl.units",          ok(((.llmctl.units | type) == "array" and all(.llmctl.units[]; (type == "object") and ((.profile | type) == "string") and ((.status | type) == "string") and ((.reasons | type) == "array"))))],
    ["fallback.recommended",  ok(((.fallback.recommended | type) == "string" and (.fallback.recommended | IN("local", "cloud", "none"))))],
    ["fallback.key_variable", ok(((.fallback | type) == "object" and (.fallback | has("key_variable")) and ((.fallback.key_variable | type) | IN("string", "null"))))],
    ["unknown_profiles",      ok(((.unknown_profiles | type) == "array"))],
    ["degraded",              ok(((.degraded | type) == "boolean"))],
    ["largest_decision_fit",  ok((has("largest_decision_fit") and ((.largest_decision_fit | type) | IN("string", "null"))))] ]'

# candidates: systemone-native decide profiles (decide capacity protocol), in order (JEV_PLACE_PROFILES wins). Sets
# CAND_RC (0 = the list is an answer). A failed `llmctl decide capacity` is an UNDETERMINED list, never "no candidate"
# (R5-7): the caller reports undetermined, never does_not_fit. Call it in the current shell (not in $(...)).
CAND_RC=0
candidates() {
  CAND_RC=0
  if [ -n "${JEV_PLACE_PROFILES:-}" ]; then printf '%s\n' "${JEV_PLACE_PROFILES//,/$'\n'}"; return 0; fi
  bounded "$RTMO" "$WORK/dcap.raw" "$LLMCTL" decide capacity --json || CAND_RC=$?
  [ "$CAND_RC" = 0 ] || return 0
  if ! jq -r '(.decision_instances // {}) | to_entries[] | select(.value.protocol == "systemone-native") | .key' "$WORK/dcap.raw" 2>/dev/null; then
    CAND_RC=65   # an answer that is not JSON is not a list
  fi
  return 0
}

# inst_state <profile> -> "<state><US><verdict><US><threads><US><reason>" from $WORK/cap.json (read ok). state is one of
# ok | degraded | absent | unknown (see the header); verdict is the placement verdict ("" = null for a running instance).
inst_state() {
  local p="$1"
  jev_profile_name_ok "$p" || { printf 'unknown%sundetermined%s0%sinvalid profile name\n' "$US" "$US" "$US"; return 0; }
  jq -r --arg p "$p" --arg tn "$TENANT" '
    def out($s; $v; $t; $r): "\($s)\u001f\($v)\u001f\($t)\u001f\($r | gsub("[\u001f\n\t]"; " "))";
    (if $tn == "" then $p else "\($tn)--\($p)" end) as $key
    | (.profiles[$p] // null) as $e
    | (.host.nproc.headroom // null) as $np
    | [.llmctl.units[]? | select(((.owner // "self") == "self") and ((.profile // "") == $key))] as $own
    | [$own[] | (.status // "")] as $sts
    | if any(.unknown_profiles[]?; . == $p) then out("unknown"; "undetermined"; 0; "unknown profile")
      elif $e == null then out("unknown"; "undetermined"; 0; "profile absent from capacity output")
      elif ($e|type) != "object" or ($e.threads|type) != "number" or ($e.reasons|type) != "array" or ($e.headroom|type) != "object" or ($e.verdict|type) != "string"
        then out("unknown"; "undetermined"; 0; "contract fields of profiles.\($p) missing or wrong: \([(if ($e|type) != "object" then "the entry" else empty end), (if ($e|type) == "object" and ($e.verdict|type) != "string" then "verdict" else empty end), (if ($e|type) == "object" and ($e.threads|type) != "number" then "threads" else empty end), (if ($e|type) == "object" and ($e.reasons|type) != "array" then "reasons" else empty end), (if ($e|type) == "object" and ($e.headroom|type) != "object" then "headroom" else empty end)] | join(","))")
      elif $e.verdict == "running" then
        if ($own | length) == 0 then out("unknown"; "undetermined"; 0; "verdict running but llmctl reports no own unit \($key)")
        elif ($sts | all(. == "ok" or . == "degraded")) | not then out("unknown"; "undetermined"; 0; "unit status \($sts | join(",")) is not ok/degraded")
        elif any($sts[]; . == "degraded") then out("degraded"; "does_not_fit"; 0; "unit degraded: \([$own[] | .reasons[]?] | join("; "))")
        else out("ok"; ""; 0; "running instance, unit status ok") end
      elif ($own | length) > 0 then out("unknown"; "undetermined"; 0; "an own unit \($key) is reported but the verdict is \($e.verdict // "null"), not running")
      elif $e.verdict == "undetermined" then out("unknown"; "undetermined"; 0; "llmctl verdict undetermined: \($e.reasons | join("; "))")
      elif (($e.verdict // "") | IN("fits","fits_with_reduced_threads","does_not_fit")) | not then out("unknown"; "undetermined"; 0; "verdict outside the closed set")
      elif $e.verdict == "does_not_fit" then out("absent"; "does_not_fit"; $e.threads; ($e.reasons | join("; ")))
      elif ($np|type) != "number" then
        # R5-13: llmctl 3.4.1 reports headroom null both when RLIMIT_NPROC is unlimited (rlimit_soft null, census read) and
        # when the census is unreadable (user_threads null); they are different facts, both undetermined here
        (if ((.host.nproc|type) == "object") and (.host.nproc | has("rlimit_soft")) and .host.nproc.rlimit_soft == null
            and ((.host.nproc.user_threads|type) == "number")
         then out("absent"; "undetermined"; $e.threads; "nproc_unlimited: RLIMIT_NPROC is unlimited (measured: rlimit_soft null, \(.host.nproc.user_threads) user threads); whether an unlimited limit admits a start is an operator decision (§11.4.291(C)), so the verdict stays undetermined")
         else out("absent"; "undetermined"; $e.threads; "nproc_not_measured: RLIMIT_NPROC headroom not measured") end)
      elif $np < $e.threads then out("absent"; "does_not_fit"; $e.threads; "nproc headroom \($np) < threads")
      elif .pressure.ok == false then out("absent"; "does_not_fit"; $e.threads; "pressure: \((.pressure.reasons // []) | join("; "))")
      else out("absent"; $e.verdict; $e.threads; ($e.reasons | join("; "))) end' "$WORK/cap.json"
}

hosted_key_var() { local v; for v in TYPESAFE_API_KEY OPENROUTER_API_KEY; do [ "$(key_state "$v" | cut -f1)" = real ] && { echo "$v"; return 0; }; done; return 0; }

# write_placement <profile> <verdict|""> <reason> <route> <started> <threads> <event> [reason_code] (caller holds the lock)
write_placement() {
  local kv code merged=false prev held=false
  kv="$(hosted_key_var)"
  case "$2" in ""|fits|fits_with_reduced_threads|does_not_fit|undetermined) ;; *) log "internal: verdict '$2' outside the closed set"; return 2 ;; esac
  case "${7:-}" in placed|joined|joined_running|no_fit|undetermined|start_failed|start_refused|refused_stopping|refused_starting|refused_degraded|refused_join|lease_lock_timeout|stopped|stop_failed|endpoint_gone|gateway_refused|route_changed) ;;
    *) log "internal: event '${7:-}' outside the closed set"; return 2 ;; esac
  code="${8:-}"
  if [ -z "$code" ]; then
    case "$7" in refused_stopping) code=endpoint_stopping ;; refused_starting) code=endpoint_starting ;; endpoint_gone) code=endpoint_gone ;;
      lease_lock_timeout) code=lease_lock_timeout ;; gateway_refused) code=gateway_refused ;; esac
  fi
  prev="$(jq -c '.placement // {} | {profile, verdict, event, route, evaluated_at}' "$PLACEMENT" 2>/dev/null || echo null)"
  [ -n "$prev" ] || prev=null
  if [ -n "$HOLDER" ] && leases_load | jq -e --arg h "$HOLDER" 'any(.sets[]?.leases[]?; .holder == $h)' >/dev/null 2>&1; then held=true; fi
  if [ -f "$DETECTION" ] && jq -e . "$DETECTION" >/dev/null 2>&1; then merged=true; fi
  jq -nc --arg p "$1" --arg v "$2" --arg r "$3" --arg route "$4" --argjson st "$5" --arg th "${6:-0}" --arg ev "${7:-}" --arg kv "$kv" --argjson now "$NOW" \
     --arg code "$code" --argjson prev "$prev" --arg holder "$HOLDER" --argjson held "$held" --argjson merged "$merged" \
     --slurpfile cap <(jq -c '{host:{mem_total_mb:.host.mem_total_mb, mem_available_mb:.host.mem_available_mb, usable_mem_mb:.host.usable_mem_mb, load:.host.load, nproc_headroom:(.host.nproc.headroom // null), nproc_rlimit_soft:(.host.nproc.rlimit_soft // null)}, reserve:{mem_reserved_mb:.reserve.mem_reserved_mb, cpus_reserved:.reserve.cpus_reserved}, pressure:.pressure, time:.time}' "$WORK/cap.json" 2>/dev/null || echo '{}') \
     '{placement:{profile:(if $p=="" then null else $p end), verdict:(if $v=="" then null else $v end), event:(if $ev=="" then null else $ev end),
                 reason_code:(if $code=="" then null else $code end), reason:$r, route:$route, key_variable:(if $route=="cloud" then $kv else null end),
                 constitution_started:$st, threads:($th|tonumber? // 0),
                 lease:(if $holder=="" then null else {holder:$holder, held:$held} end),
                 override_id:null, override_note:"no override path is built (§11.4.291(A.1) waiver / attestation not implemented); undetermined is never lifted",
                 previous:$prev, detection_merged:$merged,
                 inputs:($cap[0] // {}), source:"llmctl capacity --json (schema llmctl.capacity/1)", evaluated_at:$now}}' > "$WORK/pl.json"
  jev_write_atomic "$PLACEMENT" < "$WORK/pl.json"
  if [ "$merged" = true ]; then
    if jq -c --slurpfile pl "$WORK/pl.json" '. + $pl[0]' "$DETECTION" > "$WORK/det.json" 2>/dev/null; then jev_write_atomic "$DETECTION" < "$WORK/det.json"
    else log "placement entry not merged into $DETECTION (merge failed)"; fi
  fi
}
# record_placement <write_placement args...>: write the record under the lock, with up to RETRIES lock waits; when every
# wait expires the record is logged as NOT written (R5-3). Never written without the lock.
record_placement() {
  local i=0 rc
  while [ "$i" -lt "$RETRIES" ]; do
    rc=0; with_lock write_placement "$@" || rc=$?
    [ "$rc" = 4 ] || return 0
    i=$((i+1))
  done
  log "placement record NOT written: the lease lock could not be taken ($RETRIES waits of ${LOCK_TMO}s); event ${7:-} reason: ${3:-}"
  return 0
}

fallback_route() { if [ -n "$(hosted_key_var)" ]; then echo cloud; else echo none; fi; }
# the route decision traffic takes now: local while the (derived) cache holds an llmctl-local entry, else the fallback
current_route() { if [ -f "$CACHE" ] && jq -e 'any(.endpoints[]?; .provider_id == "llmctl-local")' "$CACHE" >/dev/null 2>&1; then echo local; else fallback_route; fi; }

# gateway_url -> sets GW_URL GW_CA GW_SRC; rc 1 (GW_WHY set) when the URL is refused. NEVER called under the lock (it may
# run `llmctl decide status`). Only https:// is accepted (§11.4.289(I), §11.4.10: the key never goes over plain HTTP).
GW_URL=""; GW_CA=""; GW_SRC=""; GW_WHY=""
gateway_url() {
  local rc=0 line
  if [ -n "${LLMCTL_GATEWAY_URL:-}" ]; then GW_URL="$LLMCTL_GATEWAY_URL"; GW_CA="${LLMCTL_CACERT:-}"; GW_SRC="LLMCTL_GATEWAY_URL"
  else
    bounded "$RTMO" "$WORK/st.raw" "$LLMCTL" decide status --json || rc=$?
    if [ "$rc" != 0 ]; then
      GW_URL="$GW_DEFAULT"; GW_CA=""; GW_SRC="default"
      log "gateway: llmctl decide status exit $rc; default applied: $GW_DEFAULT"
    else
      line="$(jq -r '[.registry.services[]? | select((.labels.kind // "") == "gateway")][0] as $g | if $g == null then "" else "\($g.url // "")\u001f\($g.labels.ca_file // "")" end' "$WORK/st.raw" 2>/dev/null || true)"
      if [ -z "$line" ] || [ -z "${line%%"$US"*}" ]; then
        GW_URL="$GW_DEFAULT"; GW_CA=""; GW_SRC="default"
        log "gateway: no gateway listed in the llmctl registry (or its output is unreadable); default applied: $GW_DEFAULT"
      else
        GW_URL="${line%%"$US"*}"; GW_CA="${line#*"$US"}"; GW_SRC="llmctl decide status registry"
      fi
    fi
  fi
  case "$GW_URL" in
    https://*) jev_check_url "$GW_URL" && return 0
               GW_WHY="the gateway URL from $GW_SRC is malformed"; return 1 ;;
    *) GW_WHY="the gateway URL from $GW_SRC is not https:// (only https is registered: the key LLMCTL_API_KEY never goes over plain HTTP, §11.4.289(I), §11.4.10)"; return 1 ;;
  esac
}

leases_load() { [ -s "$LEASES" ] && jq -e . "$LEASES" >/dev/null 2>&1 && cat "$LEASES" || echo '{"sets":{}}'; }
# leases_gen -> the registry generation: a counter every registry write by this producer increments (0: no registry yet).
leases_gen() { local g; g="$(jq -r '(.gen // 0) | if type == "number" then floor else 0 end' "$LEASES" 2>/dev/null || true)"; case "$g" in ''|*[!0-9]*) echo 0 ;; *) echo "$g" ;; esac; }
# leases_token -> "<gen>:<sha256 of the registry file>" (Round 7, NF-2): THE value the freshness rule compares. The
# generation catches a write that leaves the same bytes (a refused start deleting the set it created: no ABA); the hash
# catches a write by a producer that does not know the generation (the registry is per user and host-level, §11.4.291(J),
# so a project with an older constitution pin writes it too, and keeps `gen` unchanged).
leases_token() {
  local h="none"
  if [ -f "$LEASES" ]; then h="$(sha256sum < "$LEASES" 2>/dev/null | cut -d' ' -f1)"; [ -n "$h" ] || h="unreadable"; fi
  printf '%s:%s\n' "$(leases_gen)" "$h"
}
# leases_save (content on stdin; caller holds the lock): the registry write with the next generation, then THE one cache
# derivation point
# Round 9 (R8-1 class, "a lease held across bounded calls"): during an acquire, EVERY registry write also refreshes the
# heartbeat of the acquire's own holder (ACQ_REFRESH=1, set by `acquire` only), so the session's lease never ages across
# the llmctl calls its own acquire makes (each write follows at most one bounded call); a lease that is gone stays gone.
leases_save() {
  local g; g="$(leases_gen)"
  jq -c --argjson g "$(( g + 1 ))" --arg h "$HOLDER" --arg rf "${ACQ_REFRESH:-0}" --argjson now "$NOW" --arg mo "$MONO_TOK" \
    '.gen = $g | if $rf == "1" and $h != "" then (if (.sets | type) == "object" then .sets |= map_values(if (.leases | type) == "array" then .leases |= map(if .holder == $h then .heartbeat_at = $now | .heartbeat_mono = (if $mo=="" then null else $mo end) else . end) else . end) else . end) else . end' \
    > "$WORK/leases.next" || { log "internal: the lease registry write was not JSON; nothing written"; return 2; }
  jev_write_atomic "$LEASES" < "$WORK/leases.next"
  if [ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_TRACE_FILE:-}" ]; then
    trace_ev save "$(jq -c '(.sets // {}) | if type == "object" then map_values({stopping: (.stopping.pid? // null), starting: (.starting.pid? // null)}) else {} end' "$WORK/leases.next" 2>/dev/null || echo '{}')"
  fi
  derive_cache || log "endpoint cache could not be derived (rc $?)"
}

# derive_cache (caller holds the lock): the llmctl-local entry of the endpoint cache as a pure function of leases.json
# (R5-2). Other entries of the cache (hosted providers written by other tools) are kept. The file is rewritten only when
# the result differs; it is not created when there is nothing to add.
derive_cache() {
  local cur new
  if [ -s "$CACHE" ] && jq -e . "$CACHE" >/dev/null 2>&1; then cur="$(jq -c . "$CACHE")"
  else
    jq -e '[.sets // {} | to_entries[] | select(((.value.leases // [])|length) > 0)] | length > 0' "$LEASES" >/dev/null 2>&1 || return 0
    cur='{"version":1,"generated_at":0,"ttl":300,"endpoints":[]}'
  fi
  new="$(jq -c --argjson c "$cur" '
    ([.sets // {} | to_entries[] | select(((.value.leases // []) | length) > 0 and (.value.stopping // null) == null and (.value.starting // null) == null
        and (.value.start_failed // null) == null and (.value.stop_owed // null) == null and ((.value.health.state // "") == "ok")) | .key] | sort) as $r
    | (.gateway // null) as $g
    | ([$c.endpoints[]? | select(.provider_id == "llmctl-local")] | first // null) as $old
    | (.route_pref // null) as $rp
    | . as $reg
    | (if ($g | type) == "object" and ((($g.url // "") | tostring) | startswith("https://")) and ($r | length) > 0 then
         (if $rp != null and any($r[]; . == $rp) then $rp
          elif $old != null and any($r[]; . == $old.model) then $old.model
          else $r[0] end) as $m
         | {provider_id:"llmctl-local", base_url:$g.url, model:$m, key_var:"LLMCTL_API_KEY", ca_file:($g.ca // ""), priority:10,
            probed_at:($reg.sets[$m].health.at // 0),
            reason:"derived from the lease registry: held, unmarked, unit observed ok (scripts/jev/jev-place.sh derive_cache, §11.4.291)"}
       else null end) as $e
    | $c | .endpoints = (([.endpoints[]? | select(.provider_id != "llmctl-local")] + (if $e == null then [] else [$e] end)) | sort_by(.priority // 100))' "$LEASES")" || return 1
  [ "$new" = "$cur" ] && return 0
  mkdir -p "$(dirname "$CACHE")"
  printf '%s\n' "$new" | jev_write_atomic "$CACHE"
}

proc_start() { # proc_start <pid> -> the process start time (clock ticks since boot, /proc/<pid>/stat field 22) or ""
  local st; st="$(cat "/proc/$1/stat" 2>/dev/null)" || return 0
  st="${st##*) }"   # the comm field may hold spaces and ')': fields after the LAST ") " start at field 3
  # shellcheck disable=SC2086
  set -- $st; printf '%s\n' "${20:-}"
}
ME_START="$(proc_start "$$")"
# me_mark -> a mark naming THIS process: {at (wall), mono, pid, pid_start, holder}. Round 9 (R8-1): a mark is written
# under the lock IMMEDIATELY before the one bounded llmctl call it covers (arm_stop_locked, mark_start_locked,
# finish_start_locked), never at planning time for a later call; `holder` names the session this process acts for
# (reap_locked suspends that holder's lease TTL while the mark is live, see there).
me_mark() { jq -nc --argjson now "$NOW" --arg pid "$$" --arg pst "$ME_START" --arg mo "$MONO_TOK" --arg h "$HOLDER" \
  '{at:$now, mono:(if $mo=="" then null else $mo end), pid:($pid|tonumber), pid_start:($pst|tonumber? // null), holder:(if $h=="" then null else $h end)}'; }
pid_alive() { # pid_alive <pid> <recorded-start|""|null> -> 0 alive, 1 dead, 2 unknown (/proc unavailable)
  local pid="$1" rec="${2:-}" cur
  [ -d /proc/self ] || return 2
  [ -d "/proc/$pid" ] || return 1
  if [ -n "$rec" ] && [ "$rec" != "null" ]; then cur="$(proc_start "$pid")"; [ "$cur" = "$rec" ] || return 1; fi
  # a /proc file reports size 0, so read it: an empty cmdline is a zombie or a kernel thread, not a session holder
  [ -n "$(head -c 64 "/proc/$pid/cmdline" 2>/dev/null | tr -d '\0')" ] || return 1
  return 0
}
pid_dead() { # pid_dead <pid|null|""> <pid_start> -> 0 when a recorded pid is provably gone (reused, a zombie, or kill -0 fails
  # without /proc); 1 when there is no pid or it is alive
  local rc=0
  [ -n "$1" ] && [ "$1" != null ] || return 1
  pid_alive "$1" "${2:-}" || rc=$?
  case "$rc" in 0) return 1 ;; 1) return 0 ;; esac
  kill -0 "$1" 2>/dev/null && return 1
  return 0
}
holder_alive() { # holder_alive <pid> <heartbeat_at> <ttl> [pid_start] [heartbeat_mono]
  local pid="$1" hb="$2" ttl="$3" rc=0
  if [ -n "$pid" ] && [ "$pid" != "null" ]; then
    pid_alive "$pid" "${4:-}" || rc=$?
    case "$rc" in 0) return 0 ;; 1) return 1 ;; esac
    # no /proc: kill -0 cannot tell a reused pid, so the heartbeat TTL bounds the lease as well
    kill -0 "$pid" 2>/dev/null || return 1
  fi
  [ "$(age_of "$hb" "${5:-}")" -le "$ttl" ]
}

reap_locked() { # drops dead holders from every set and clears dead / expired marks (caller holds the lock); never stops a model
  # every loop variable is local: bash scoping is dynamic, so a bare `read pid ttl` here would clear the CALLER's pid/ttl
  local cur out prof h pid hb ttl pst hmo sat smo spid sst arc mk age mh live_h=" "; cur="$(leases_load)"; out="$cur"
  # (1) marks. A `stopping` or `starting` mark is cleared when its process is gone (pid + start time) or the mark is older
  # than MARK_TTL (age_of its own `at` / `mono`, written immediately before the one llmctl call it covers: round 9, R8-1;
  # judged at the time of THIS locked section: round 8, R7-A; monotonic: round 9, R8-6), the longest a LIVE marker can
  # hold it (§11.4.291(J)); the set is then judged like any other set by an observation NEWER than the clearing: round 7
  # (NF-3) records the current observation counter as the set's floor (state pending), as finish_start_locked does, so
  # an answer read before the clearing (it may predate the start the dead marker made) never judges the set (no false
  # endpoint_gone). A mark that is kept is LIVE; the holder it names (the session the marker acts for) is collected.
  while IFS="$US" read -r prof mk sat smo spid sst mh; do
    [ -n "$prof" ] || continue
    # a mark without a pid cannot name a dead process: only its age clears it (review R2 nit RS3)
    arc=0; if [ "$spid" != "null" ] && [ -n "$spid" ]; then pid_alive "$spid" "$sst" || arc=$?; fi
    age="$(age_of "$sat" "$smo")"
    if [ "$arc" = 1 ] || [ "$age" -gt "$MARK_TTL" ]; then
      log "cleared the $mk mark of $prof (its process is gone or the mark is older than ${MARK_TTL}s); the set is judged by the next observation newer than this"
      out="$(jq -c --arg p "$prof" --arg m "$mk" --argjson now "$NOW" --arg mo "$MONO_TOK" --argjson f "$(obs_counter)" \
        '.sets[$p][$m] = null | .sets[$p].mark_cleared = {mark:$m, at:$now, mono:(if $mo=="" then null else $mo end)} | .sets[$p].health = {state:"pending", reason:"\($m) mark cleared; not observed since", seq:$f, at:$now}' <<<"$out")"
    elif [ -n "$mh" ] && [ "$mh" != null ]; then live_h+="$mh "
    fi
  done < <(jq -r '.sets | to_entries[] | .key as $p | .value as $v | ("stopping", "starting") as $m | select(($v[$m] // null) != null)
                  | [$p, $m, ($v[$m].at // 0), ($v[$m].mono // "null"), ($v[$m].pid // "null"), ($v[$m].pid_start // "null"), ($v[$m].holder // "null")] | map(tostring) | join("\u001f")' <<<"$cur")
  # (2) leases. A holder whose pid is dead is dropped. A heartbeat older than the lease TTL drops the lease, EXCEPT while
  # a LIVE mark names the holder (round 9, R8-1 class): this producer is then running a bounded llmctl call FOR that
  # session (its acquire), which cannot heartbeat while it waits, and the suspension ends when the mark ends (its own
  # MARK_TTL bounds it). A dead pid is never suspended.
  while IFS="$US" read -r prof h pid hb ttl pst hmo; do
    [ -n "$prof" ] || continue
    if ! holder_alive "$pid" "$hb" "$ttl" "$pst" "$hmo"; then
      if ! pid_dead "$pid" "$pst"; then
        case "$live_h" in *" $h "*)
          log "lease of holder=$h on $prof: heartbeat older than its TTL, kept while a live mark names the holder (an acquire for it is in flight)"
          continue ;; esac
      fi
      log "reaped dead lease holder=$h profile=$prof"
      out="$(jq -c --arg p "$prof" --arg h "$h" '.sets[$p].leases |= map(select(.holder != $h))' <<<"$out")"
    fi
  done < <(jq -r '.sets | to_entries[] | .key as $p | .value.leases[]? | [$p, (.holder // ""), (.pid // "null"), (.heartbeat_at // 0), (.ttl // 0), (.pid_start // "null"), (.heartbeat_mono // "null")] | map(tostring) | join("\u001f")' <<<"$out")
  [ "$out" = "$cur" ] || printf '%s\n' "$out" | leases_save
}

with_lock() { # with_lock <fn> args... -> rc 4 on lock timeout. The function must not run llmctl (R4-3).
  exec 9>>"$LOCK"
  if ! flock -w "$LOCK_TMO" 9; then exec 9>&-; return 4; fi
  # round 8 (R7-A): the time of THIS locked section, read after the lock is taken (a lock wait is not counted as the
  # time a mark or a lease is written)
  clock_refresh
  local rc=0; "$@" || rc=$?
  flock -u 9; exec 9>&-
  return "$rc"
}

lease_obj_args() { # lease_obj_args <pid> -> the start time of a --pid holder ("" when none / unreadable)
  if [ -n "$1" ]; then proc_start "$1"; fi
}
# lease_json <holder> <pid> <pid_start> <ttl> <started_by_this_session true|false> -> one lease object (R5-8)
lease_json() {
  jq -nc --arg h "$1" --arg pid "$2" --arg pst "$3" --argjson now "$NOW" --argjson ttl "$4" --argjson sb "$5" --arg proj "$PROJECT" \
    --arg mo "$MONO_TOK" '{holder:$h, pid:(if $pid=="" then null else ($pid|tonumber) end), pid_start:($pst|tonumber? // null), heartbeat_at:$now,
      heartbeat_mono:(if $mo=="" then null else $mo end), ttl:$ttl,
      project:(if $proj=="" then null else $proj end), started_by_this_session:$sb}'
}

# ---- observation (R5-2) ----------------------------------------------------------------------------------------------
take_ticket_locked() { # caller holds the lock: next observation ticket + the registry token (leases_token) at that moment
  local c=0
  [ -s "$OBSSEQ" ] && c="$(head -c 32 "$OBSSEQ" | tr -dc '0-9')"
  c=$(( ${c:-0} + 1 ))
  printf '%s\n' "$c" | jev_write_atomic "$OBSSEQ"
  TICKET="$c"; TICKET_GEN="$(leases_token)"; TICKET_GONE="$(intents_gone_now)"
}
# intents_gone_now (caller holds the lock; round 14, review R13-B1) -> one line per start intent whose start can no longer
# bring its unit up NOW: the identity "<profile> <starter pid> <starter start> <start pid> <start start>" (intent_id).
# take_ticket_locked records these lines with the ticket, so the capacity answer read after the ticket was produced after
# that start was over: only such an answer may resolve a dead starter's intent (intents_locked). A start is over when the
# start process the intent names is provably gone (child_running). A round-13 intent names no start process: its bounded
# start is over once the intent is older than MARK_TTL (the longest such a start and its record can take), the one
# age rule left (honest limit: a start that left work behind in its own process group is not seen there).
TICKET_GONE=""
intent_id() { printf '%s %s %s %s %s' "$1" "$2" "$3" "$4" "$5"; }
intents_gone_now() {
  local p ipid ipst iat imo cpid cpst
  while IFS="$US" read -r p ipid ipst iat imo cpid cpst; do
    [ -n "$p" ] || continue
    if [ "$cpid" = null ]; then
      [ "$(age_of "$iat" "$imo")" -gt "$MARK_TTL" ] || continue
    else
      ! child_running "$cpid" "$cpst" || continue
    fi
    intent_id "$p" "$ipid" "$ipst" "$cpid" "$cpst"; printf '\n'
  done < <(jq -r '(.start_intents // {}) | to_entries[] | [.key, (.value.pid // "null"), (.value.pid_start // "null"), (.value.at // 0), (.value.mono // "null"),
                 (.value.child.pid // "null"), (.value.child.pid_start // "null")] | map(tostring) | join("\u001f")' <<<"$(leases_load)")
}
obs_counter() { local c=0; [ -s "$OBSSEQ" ] && c="$(head -c 32 "$OBSSEQ" | tr -dc '0-9')"; echo "${c:-0}"; }
# observe_read -> 0 (OBS_TICKET, OBS_GEN, CAP_ST, CAP_REASON, $WORK/cap.json set) or 4 (lock timeout: nothing read).
# OBS_GEN is the registry token (leases_token) when the ticket was taken: the capacity answer read after it describes that
# registry.
# OBS_GONE (round 14): the start intents whose start was over when the ticket was taken (intents_gone_now); it is set in
# the same step as OBS_TICKET, so it always describes the ticket of the answer in CAP_ST.
OBS_TICKET=""; OBS_GEN=""; CAP_ST=""; CAP_REASON=""; TICKET_GEN=""; OBS_GONE=""
observe_read() {
  TICKET=""; TICKET_GEN=""; TICKET_GONE=""; OBS_GONE=""; with_lock take_ticket_locked || return 4
  OBS_TICKET="$TICKET"; OBS_GEN="$TICKET_GEN"; OBS_GONE="$TICKET_GONE"
  IFS="$US" read -r CAP_ST CAP_REASON < <(capacity_read)
}
# obs_locked (caller holds the lock; OBS_TICKET + CAP_ST from observe_read): records the instance state of every unmarked
# set when this ticket is newer than the recorded one; a held set whose unit is gone has every lease released
# (endpoint_gone, §11.4.291(J)(6)); a lease-less set this producer did not start is forgotten (never stopped).
GONE_WRITTEN=0
# intents_locked (caller holds the lock; round 13, review R12-B1): the START INTENT record. mark_start_locked writes
# .start_intents[<profile>] (a mark naming the starter: pid, pid start time, holder, at, mono) in the SAME registry write
# as the starting mark, before the bounded llmctl start; finish_start_locked removes it (only when it names that same
# process) in the same write as the start result. Unlike the starting mark it lives OUTSIDE the lease set, so another
# process's stop that deletes the set, or a reap that clears the mark by age, never removes it. While an intent exists,
# a running unit of that profile is never adopted as operator-started (plan step D) and no second start is marked
# (mark_start_locked). An intent whose starter is provably dead (pid + start time; without /proc, kill -0) was never
# answered: the start it covers may have brought the unit up. Round 14 (review R13-B1): it is judged ONLY with an
# observation whose ticket was taken after its start was over (the intent identity is in OBS_GONE, recorded by
# take_ticket_locked): the start process survives a SIGKILL of its starter, and an answer read while it runs (or read
# before it brought the unit up) cannot say whether the unit comes up. Until then the intent is KEPT, whatever the sets
# do: it blocks adoption and a second start, and a set dropped meanwhile cannot take it along. Then:
#   a set of the profile exists      -> the set is made constitution-started (its unit may be ours), the intent removed
#   no set, the unit runs (ok or degraded) -> a lease-less constitution-started set with stop_owed is created (the owed
#                                       stop of plan step A, or the next release, stops it), the intent removed
#   no set, the unit is absent       -> nothing was started (or it is gone): the intent is removed
#   no set, the state is unknown     -> the intent is kept (judged by a later observation)
# A LIVE starter's intent is never judged by age (the starting mark is; that is what R12-F1 showed is not enough).
# Honest limit (§11.4.6): a starter killed after its intent was written and before `go` started nothing (its start
# process exits on the closed gate), yet a unit found running then (an operator start meanwhile) is recorded with an
# owed stop, the same ambiguity as a refused start (review R13-F5).
intents_locked() {
  local cur out p ipid ipst iat st v th r f cpid cpst
  cur="$(leases_load)"; out="$cur"
  while IFS="$US" read -r p ipid ipst iat cpid cpst; do
    [ -n "$p" ] || continue
    pid_dead "$ipid" "$ipst" || continue
    case $'\n'"$OBS_GONE"$'\n' in
      *$'\n'"$(intent_id "$p" "$ipid" "$ipst" "$cpid" "$cpst")"$'\n'*) ;;
      *) log "start intent of $p (pid $ipid): its starter is gone, its start process ($cpid) may still run or was not seen gone before this observation; the intent is kept"
         continue ;;
    esac
    if jq -e --arg p "$p" '.sets[$p] != null' <<<"$out" >/dev/null; then
      log "start intent of $p (pid $ipid) was never answered and its starter is gone; the existing set is kept constitution-started (the unit may be one this producer started)"
      out="$(jq -c --arg p "$p" '.sets[$p].constitution_started = true | del(.start_intents[$p])' <<<"$out")"
      continue
    fi
    if [ "$CAP_ST" = ok ]; then IFS="$US" read -r st v th r <<<"$(inst_state "$p")"; else st=unknown; fi
    case "$st" in
      ok|degraded)
        f="$(obs_counter)"
        log "start intent of $p (pid $ipid) was never answered and its starter is gone; the unit runs ($st) with no lease set: it is recorded constitution-started with an owed stop (never adopted as operator-started, §11.4.291(G))"
        out="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson f "$f" --argjson at "${iat:-0}" --arg ipid "$ipid" --arg st "$st" \
          '.sets[$p] = {constitution_started:true, started_at:$at, stopping:null, starting:null, leases:[],
             stop_owed:{at:$now, reason:"the start by pid \($ipid) was never recorded (its starter is gone) and the unit runs (\($st)); a unit this producer may have started is owed a stop"},
             health:{state:"pending", reason:"recovered from an unanswered start intent; not observed since", seq:$f, at:$now}}
           | del(.start_intents[$p])' <<<"$out")" ;;
      absent)
        log "start intent of $p (pid $ipid) was never answered and its starter is gone; no unit runs: the intent is removed"
        out="$(jq -c --arg p "$p" 'del(.start_intents[$p])' <<<"$out")" ;;
      *) log "start intent of $p (pid $ipid): its starter is gone, the unit state is not known now; the intent is kept" ;;
    esac
  done < <(jq -r '(.start_intents // {}) | to_entries[] | [.key, (.value.pid // "null"), (.value.pid_start // "null"), (.value.at // 0),
                 (.value.child.pid // "null"), (.value.child.pid_start // "null")] | map(tostring) | join("\u001f")' <<<"$cur")
  [ "$out" = "$cur" ] && return 0
  out="$(jq -c 'if (.start_intents // null) == {} then del(.start_intents) else . end' <<<"$out")"
  printf '%s\n' "$out" | leases_save
}
# intent_of <profile> -> the pid of a start intent of <profile> ("" when none)
intent_of() { jq -r --arg p "$1" '(.start_intents // {})[$p].pid // "" | tostring' <<<"$(leases_load)"; }
obs_locked() {
  [ -n "$OBS_TICKET" ] || return 0
  intents_locked
  local cur out p st v th r det gone="" newer holders
  declare -A gdet=()
  cur="$(leases_load)"; out="$cur"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$CAP_ST" = ok ]; then IFS="$US" read -r st v th r <<<"$(inst_state "$p")"; else st=unknown; v=undetermined; r="capacity undetermined: ${CAP_REASON:-unread}"; fi
    newer="$(jq -r --arg p "$p" --argjson t "$OBS_TICKET" '((.sets[$p].health.seq // -1) < $t)' <<<"$out")"
    [ "$newer" = true ] || continue
    out="$(jq -c --arg p "$p" --arg s "$st" --arg r "$r" --argjson t "$OBS_TICKET" --argjson now "$NOW" '.sets[$p].health = {state:$s, reason:$r, seq:$t, at:$now}' <<<"$out")"
    if [ "$st" = absent ] && [ "$(jq -r --arg p "$p" '((.sets[$p].leases // []) | length) > 0 and (.sets[$p].start_failed // null) == null and (.sets[$p].stop_owed // null) == null' <<<"$out")" = true ]; then
      det="$r"; [ -n "$det" ] || det="no own unit reported, verdict ${v:-null}"
      holders="$(jq -r --arg p "$p" '[.sets[$p].leases[].holder] | join(",")' <<<"$out")"
      out="$(jq -c --arg p "$p" --arg d "$det" --argjson now "$NOW" '.sets[$p].leases = [] | .sets[$p].gone = {at:$now, detail:$d}' <<<"$out")"
      gone+=" $p"; gdet[$p]="$det|$holders"
    fi
  done < <(jq -r '.sets | to_entries[] | select((.value.stopping // null) == null and (.value.starting // null) == null) | .key' <<<"$cur")
  out="$(jq -c '.sets |= with_entries(select(((.value.leases // []) | length) > 0 or .value.constitution_started == true))' <<<"$out")"
  [ "$out" = "$cur" ] || printf '%s\n' "$out" | leases_save
  for p in $gone; do
    det="${gdet[$p]%|*}"; holders="${gdet[$p]##*|}"
    log "endpoint_gone: the unit of $p is gone ($det); every lease released (holders $holders); route $(current_route); nothing is restarted (§11.4.291(J)(6))"
    write_placement "$p" "" "endpoint_gone: $det" "$(current_route)" "$(jq -r --arg p "$p" '.sets[$p].constitution_started == true' "$LEASES")" 0 endpoint_gone || true
    GONE_WRITTEN=1
  done
}
# finalize_locked <reap 0|1> <record 0|1> (caller holds the lock): reap (optional), observe, and announce a route change;
# record it as route_changed when <record> is 1 (acquire writes its own record) and no endpoint_gone record was written
finalize_locked() {
  local r0 r1; GONE_WRITTEN=0
  r0="$(current_route)"
  [ "$1" = 0 ] || reap_locked
  obs_locked
  r1="$(current_route)"
  if [ "$r0" != "$r1" ]; then
    log "route changed: $r0 -> $r1 (the endpoint cache is derived from the lease registry and the observed unit state, §11.4.291(D)(1)(F))"
    if [ "$2" = 1 ] && [ "$GONE_WRITTEN" = 0 ]; then write_placement "" "" "route_changed: $r0 -> $r1" "$r1" false 0 route_changed || true; fi
  fi
}

cmd_verdict() {
  local json="${1:-}" p line first=1 cst=ok
  candidates > "$WORK/cands"
  [ "$CAND_RC" = 0 ] || cst=undetermined
  if observe_read; then with_lock finalize_locked 1 1 || log "verdict: the observation could not be recorded (lock rc $?)"
  else log "verdict: lease lock timeout; the observation is not recorded"; IFS="$US" read -r CAP_ST CAP_REASON < <(capacity_read); fi
  {
    printf '['
    if [ "$CAP_ST" = ok ]; then
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        line="$(inst_state "$p")"
        [ "$first" = 1 ] || printf ','; first=0
        jq -nc --arg p "$p" --arg l "$line" '($l|split("\u001f")) as $f | {profile:$p, state:$f[0], verdict:(if $f[1] == "" then null else $f[1] end), threads:($f[2]|tonumber? // 0), reason:($f[3] // "")}'
      done < "$WORK/cands"
    fi
    printf ']'
  } > "$WORK/v.json"
  if [ "$json" = "--json" ]; then
    jq -c --arg st "$CAP_ST" --arg r "${CAP_REASON:-}" --arg cs "$cst" --arg crc "$CAND_RC" \
      '{contract:$st, contract_reason:$r, candidates_contract:$cs, candidates_reason:(if $cs == "ok" then "" else "llmctl decide capacity exit \($crc)" end), candidates:.}' "$WORK/v.json"
  else
    [ "$CAP_ST" = ok ] || log "capacity contract: undetermined ($CAP_REASON) - no local start"
    [ "$cst" = ok ] || log "candidate list undetermined: llmctl decide capacity exit $CAND_RC"
    jq -r '.[] | "\(.profile)\t\(.state)\t\(.verdict // "null")\tthreads=\(.threads)\t\(.reason)"' "$WORK/v.json"
  fi
}

# ---- the ONE stop helper (review R4-1, R4-3) -----------------------------------------------------------------------
# finish_stop_locked <profile> <stop-rc> <kind> (caller holds the lock). kind: release | dispose | owed | cleanup.
#   rc 0     : the set is removed (the derived cache follows), placement `stopped`, when it holds no lease and its mark
#              is ours or gone; else it is KEPT (stopped_while_held, health pending; round 9, R8-2, see below).
#   rc != 0  : the model may still run, so the set is KEPT and records stop_failed {at, rc}:
#              release -> the stopping mark (this process) is kept until this process is gone (then a later release
#                         retries; a later acquire judges the lease-less set like any other);
#              dispose -> stopping cleared, stop_owed {at, reason}: never joined, retried by every acquire and release;
#              owed / cleanup -> stopping cleared, the start_failed / stop_owed record stays: never joined, retried.
# ---- THE one ownership rule for a result record (round 10, review of 911c5b9a, R9-1) ------------------------------------
# A result record (finish_start_locked after `llmctl start`, finish_stop_locked after `llmctl stop`) is written against
# the set as it is NOW, under the lock, after a bounded call that ran WITHOUT the lock. While the call ran, the mark that
# covered it may have been cleared (a live marker older than MARK_TTL: SIGSTOP, a host suspend, an overloaded host) and
# another session may have joined the set, marked it, or the set may have been dropped. set_view is the ONE place that
# reads that state; every result site decides from its fields and from nothing else:
#   set_view <json> <profile> <mark starting|stopping> <own holder|""> -> "<claim> <others> <mine> <othermark>"
#     claim     noset | ours (the mark names this process: pid AND pid_start) | gone (the mark is null) | foreign
#     others    leases held by holders other than <own holder> (every lease when <own holder> is empty)
#     mine      1 when <own holder> holds a lease in the set, else 0
#     othermark 1 when the OTHER mark (stopping for a start, starting for a stop) is set, else 0
# THE RULE (rule_sole): a result may DELETE or REPLACE a set, or write a new mark on it, only when the set is SOLE: its
# claim is ours or gone, no other holder has a lease (others 0) and no other mark is set (othermark 0). Otherwise the
# result changes only what is this process's own: it drops this acquire's own lease (start), clears its mark only when
# the claim is ours, never clears or overwrites another process's mark, keeps the set, and when other leases remain sets
# health `pending` at the current observation counter (the set is routed again only after an observation newer than this
# result; a unit that is gone then releases every lease as endpoint_gone, announced, §11.4.291(J)(6)). A set this
# producer started is never handed over as constitution_started:false.
set_view() {
  jq -r --arg p "$2" --arg m "$3" --arg h "$4" --arg pid "$$" --arg pst "$ME_START" '(.sets[$p] // null) as $s
    | if $s == null then "noset 0 0 0"
      else ($s[$m] // null) as $k
      | (if $m == "starting" then "stopping" else "starting" end) as $o
      | (if $k == null then "gone"
         elif (($k.pid // null) | tostring) == $pid and ((($k.pid_start // null) | tostring) == (if $pst == "" then "null" else $pst end)) then "ours"
         else "foreign" end) as $c
      | "\($c) \([($s.leases // [])[] | select($h == "" or .holder != $h)] | length) \(if $h != "" and any(($s.leases // [])[]; .holder == $h) then 1 else 0 end) \(if ($s[$o] // null) != null then 1 else 0 end)"
      end' <<<"$1"
}
# rule_sole <claim> <others> <othermark> -> 0 when the set is SOLE (see THE RULE above)
rule_sole() { case "$1" in ours|gone) ;; *) return 1 ;; esac; [ "$2" = 0 ] && [ "$3" = 0 ]; }
finish_stop_locked() {
  local p="$1" rc="$2" kind="$3" cur ours leased floor claim others mine omark after am
  cur="$(leases_load)"; STOP_RES=""
  # round 9 (R8-1, R8-2), round 10 (R9-1: the same rule as finish_start_locked, through set_view): the result is recorded
  # against the set as it is NOW. The `stopping` mark counts as ours only when it names this process (pid AND start
  # time); a mark cleared meanwhile (this stop outlived MARK_TTL) or taken by another stopper is never cleared or
  # overwritten here. Every lease counts (a stopper holds no lease of the set it stops).
  read -r claim others mine omark <<<"$(set_view "$cur" "$p" stopping "")"
  ours=false; [ "$claim" != ours ] || ours=true
  leased="$others"
  # round 11 (R10-1): a start result recorded AFTER this stop was armed (start_kept.seen_stopping is the very mark this
  # process wrote; a pid+start-time match when this process wrote no mark of its own) may have brought the unit up again
  # after, or while, this stop ran (llmctl may order the two calls either way). Such a set is never SOLE for this result:
  # it is kept constitution-started with stop_owed, and the stop is retried (do_stop, once) or run by the next acquire.
  # rc 75 started nothing and does not count. The record is answered once: seen_stopping moves to answered_stop, so the
  # retried stop (its mark may be byte-equal: same process, same clock reading) is judged on the set as it is then.
  am="${ARMED_MARK[$p]:-}"; [ -n "$am" ] || am=null
  after="$(jq -r --arg p "$p" --argjson am "$am" --arg pid "$$" --arg pst "$ME_START" '(.sets[$p].start_kept // null) as $k
    | if $k == null or ($k.rc // 0) == 75 or ($k.seen_stopping // null) == null then "no"
      elif $am != null then (if $k.seen_stopping == $am then "yes" else "no" end)
      elif (($k.seen_stopping.pid // null) | tostring) == $pid and ((($k.seen_stopping.pid_start // null) | tostring) == (if $pst == "" then "null" else $pst end)) then "yes"
      else "no" end' <<<"$cur")"
  if [ "$after" = yes ] && [ "$leased" = 0 ]; then
    log "llmctl stop $p rc=$rc ($kind), but a start of $p was recorded after this stop was armed (start_kept, rc $(jq -r --arg p "$p" '.sets[$p].start_kept.rc' <<<"$cur")): the unit may be up again, so the set is KEPT constitution-started with an owed stop (never deleted, never handed over)"
    cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson f "$(obs_counter)" --arg ours "$ours" --arg k "$kind" --argjson rc "$rc" \
      '(if $ours == "true" then .sets[$p].stopping = null else . end)
       | .sets[$p].constitution_started = true
       | .sets[$p].start_kept.answered_stop = .sets[$p].start_kept.seen_stopping
       | .sets[$p].start_kept.seen_stopping = null
       | .sets[$p].stop_owed = {at:$now, reason:"a start was recorded after the \($k) stop (rc \($rc)) was armed; the unit may be up again"}
       | (if $rc != 0 then .sets[$p].stop_failed = {at:$now, rc:$rc} else . end)
       | .sets[$p].health = {state:"pending", reason:"a start was recorded after a stop was armed; not observed since", seq:$f, at:$now}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    write_placement "$p" "" "llmctl stop $p rc=$rc ($kind); a start was recorded after this stop was armed: set kept with an owed stop" "$(current_route)" true 0 "$( [ "$rc" = 0 ] && echo stopped || echo stop_failed )"
    STOP_RES=owed_after_start
    return 0
  fi
  if [ "$rc" = 0 ]; then
    if [ "$claim" = noset ]; then
      write_placement "$p" "" "llmctl stop $p rc=0 ($kind); the set was already gone from the registry" "$(current_route)" false 0 stopped
      return 0
    fi
    if rule_sole "$claim" "$others" "$omark"; then
      cur="$(jq -c --arg p "$p" 'del(.sets[$p])' <<<"$cur")"
      printf '%s\n' "$cur" | leases_save
      write_placement "$p" "" "llmctl stop $p rc=0 ($kind)" "$(current_route)" false 0 stopped
      return 0
    fi
    # R8-2: a set that holds a lease (or carries another stopper's mark) is NEVER deleted: deleting it would drop a
    # session's lease without telling it. The unit is stopped, so the set leaves the route at once (health pending at
    # the current observation counter: only an observation newer than this stop judges it; when the unit is absent there
    # every lease is released as endpoint_gone, §11.4.291(J)(6)), and the anomaly is recorded.
    floor="$(obs_counter)"
    log "llmctl stop $p rc=0 ($kind), but the set holds $leased lease(s) or another stopper's mark: the set is KEPT (never deleted with a lease); it is not routed until an observation newer than this stop"
    cur="$(jq -c --arg p "$p" --argjson now "$NOW" --arg mo "$MONO_TOK" --argjson f "$floor" --argjson n "$leased" --arg ours "$ours" --arg k "$kind" \
      '(if $ours == "true" then .sets[$p].stopping = null else . end)
       | .sets[$p].stopped_while_held = {at:$now, mono:(if $mo=="" then null else $mo end), leases:$n, kind:$k}
       | .sets[$p].health = {state:"pending", reason:"stopped (llmctl stop rc 0) while it held \($n) lease(s); not observed since", seq:$f, at:$now}' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    write_placement "$p" "" "llmctl stop $p rc=0 ($kind) while the set held $leased lease(s) or another stopper's mark; set kept, not routed until observed again" "$(current_route)" true 0 stopped
    return 0
  fi
  if [ "$claim" = noset ]; then
    write_placement "$p" "" "llmctl stop $p rc=$rc ($kind; failed or timed out); the set was gone from the registry" "$(current_route)" true 0 stop_failed
    return 0
  fi
  case "$kind" in
    release) cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson rc "$rc" '.sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")" ;;
    dispose) cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson rc "$rc" --arg why "${DISPOSE_WHY[$p]:-disposal}" --arg ours "$ours" \
                 '(if $ours == "true" then .sets[$p].stopping = null else . end) | .sets[$p].stop_owed = {at:$now, reason:$why} | .sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")" ;;
    *)       cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson rc "$rc" --arg ours "$ours" '(if $ours == "true" then .sets[$p].stopping = null else . end) | .sets[$p].stop_failed = {at:$now, rc:$rc}' <<<"$cur")" ;;
  esac
  printf '%s\n' "$cur" | leases_save
  write_placement "$p" "" "llmctl stop $p rc=$rc ($kind; failed or timed out); the set is kept and the stop is retried" "$(current_route)" true 0 stop_failed
}
# arm_stop_locked <profile> <kind> (caller holds the lock; round 9, R8-1) -> 0: the set is marked `stopping` NOW, by this
# process, for the ONE bounded stop that follows at once; 1: not stopped by this turn (the reason is logged). The set is
# judged again here, at its own turn, never by a judgement made before an earlier stop: it must still exist, be
# constitution-started, hold no lease and carry no mark; dispose: still unflagged and recorded degraded or absent; owed:
# still carrying start_failed or stop_owed. A mark is therefore never held across more than one bounded llmctl call.
arm_stop_locked() {
  local p="$1" kind="$2" cur why
  reap_locked
  cur="$(leases_load)"
  why="$(jq -r --arg p "$p" --arg k "$kind" '(.sets[$p] // null) as $s
    | if $s == null then "the set is gone"
      elif ($s.constitution_started // false) != true then "not constitution-started"
      elif (($s.leases // []) | length) > 0 then "it holds \(($s.leases // []) | length) lease(s) now"
      elif ($s.stopping // null) != null then "another process is stopping it"
      elif ($s.starting // null) != null then "another process is starting it"
      elif $k == "dispose" and ((($s.start_failed // null) != null) or (($s.stop_owed // null) != null)) then "it carries a failed start or an owed stop (an owed stop, not a disposal)"
      elif $k == "dispose" and ((($s.health.state // "") | IN("degraded", "absent")) | not) then "its recorded instance state is \($s.health.state // "unobserved") now, not degraded or absent"
      elif $k == "owed" and (($s.start_failed // null) == null and ($s.stop_owed // null) == null) then "it no longer carries a failed start or an owed stop"
      else "" end' <<<"$cur")"
  if [ -n "$why" ]; then log "stop of $p ($kind) not run at its turn: $why"; return 1; fi
  local m; m="$(me_mark)"; ARMED_MARK[$p]="$m"
  cur="$(jq -c --arg p "$p" --argjson m "$m" '.sets[$p].stopping = $m' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}
# stop_turn <profile> <kind> -> 0 stopped, 1 the stop failed, 4 its result or its mark could not be recorded, 5 not run at
# its turn (arm_stop_locked refused). Every planned stop (owed, dispose, release) goes through here: mark at its own turn,
# then the bounded stop. A mark that cannot be taken (lock timeout after RETRIES waits) means no stop.
stop_turn() {
  local p="$1" kind="$2" arc=4 i=0
  while [ "$i" -lt "$RETRIES" ]; do
    arc=0; with_lock arm_stop_locked "$p" "$kind" || arc=$?
    [ "$arc" = 4 ] || break
    i=$((i+1)); log "stop of $p: lock wait $i/$RETRIES for its stopping mark timed out"
  done
  case "$arc" in 0) ;; 4) log "stop of $p ($kind) not run: its stopping mark could not be written (lock timeout)"; return 4 ;; *) return 5 ;; esac
  do_stop "$p" "$kind"
}
# do_stop <profile> <kind> -> 0 stopped, 1 the stop failed, 4 the result could not be recorded (every record wait timed out).
# The set was marked `stopping` (or is a release set) under the lock; the bounded stop itself runs WITHOUT the lock.
do_stop() {
  local p="$1" kind="$2" src=0 frc=4 i=0
  bounded "$STMO" "$WORK/stop.out" "$LLMCTL" stop "$p" || src=$?
  case "$kind:$src" in
    release:0) log "last lease released: llmctl stop $p rc=0" ;;
    release:*) log "stop_failed: llmctl stop $p rc=$src (124/137 = timed out after ${STMO}s); the set is kept, retried by the next release" ;;
    dispose:0) log "disposed $p: llmctl stop rc 0, set removed (not restarted by this acquire)" ;;
    dispose:*) log "disposal stop of $p failed rc=$src (124/137 = timed out after ${STMO}s); the set is kept (stop_owed) and the stop is retried" ;;
    owed:0)    log "retried the cleanup stop of $p (its start or its disposal stop had failed): rc 0, set removed" ;;
    owed:*)    log "retried the cleanup stop of $p (its start or its disposal stop had failed): rc $src; the set is kept and retried again" ;;
    cleanup:0) log "cleanup stop of $p after the failed start: rc 0" ;;
    cleanup:*) log "cleanup stop of $p failed rc=$src; the set is kept (constitution_started, start_failed, stop_failed) and the stop is retried" ;;
  esac
  while [ "$i" -lt "$RETRIES" ]; do
    frc=0; with_lock finish_stop_locked "$p" "$src" "$kind" || frc=$?
    [ "$frc" = 4 ] || break
    i=$((i+1)); log "record step for llmctl stop $p: lock wait $i/$RETRIES timed out"
  done
  if [ "$frc" != 0 ]; then log "the result of llmctl stop $p (rc $src) could not be recorded (lock rc $frc); the stopping mark expires and the next release / acquire re-judges the set"; return 4; fi
  if [ "$STOP_RES" = owed_after_start ]; then
    # round 11 (R10-1): bounded: one owed retry per profile per process; otherwise the next acquire runs it (plan step A)
    case " $OWED_RETRIED " in
      *" $p "*) log "owed stop of $p: already retried by this process; run by the next acquire"; return 1 ;;
    esac
    OWED_RETRIED+=" $p"; log "retrying the stop of $p at once (owed: a start was recorded after this stop was armed)"
    stop_turn "$p" owed; return $?
  fi
  [ "$src" = 0 ]
}

# ---- acquire: plan under the lock, llmctl calls outside it ------------------------------------------------------------
# plan_locked <holder> <pid> <ttl> <gen|""> <nostart 0|1> (caller holds the lock; NO llmctl call). Reads $WORK/cap.json
# (CAP_ST, OBS_TICKET) and $WORK/cands (CAND_RC). Sets: PLAN_STOPS (lines "<profile><US><kind>"; NOT marked: each set
# is marked and judged again at its own turn by stop_turn, round 9), START_CANDS (lines "<profile><US><verdict><US><threads><US><reason>"), BASE_GEN (the registry token the
# start candidates were judged against; empty when there is no start candidate), and the result F_RC / F_OUT plus the
# placement record F_P F_V F_R F_ST F_TH F_EV F_CODE. rc 99: the registry token is not <gen>, the one the capacity
# answer was read against (the caller reads again). <nostart> 1: joins by recorded health and stops only; no adoption and
# no start candidate (the answer could not be read against an unchanged registry, STALE_MAX times).
declare -A DISPOSE_WHY=()
# round 11 (R10-1): the exact stopping mark this process wrote on a set (arm_stop_locked, or finish_start_locked for its
# own release / cleanup stop); finish_stop_locked compares it with a start result recorded meanwhile (start_kept.seen_stopping)
declare -A ARMED_MARK=()
OWED_RETRIED=""; STOP_RES=""; START_WHY=""
STOP_TRIED=""; START_TRIED=""   # profiles this acquire already stopped / tried to start: never stopped / started again by it
plan_locked() {
  local holder="$1" pid="$2" ttl="$3" g0="$4" nostart="${5:-0}" cur pst p jp v th r st hs leased cs lline ref_p="" ref_v="" ref_r="" ref_ev="" any_undet=0 undet_why="" nofit_why="" foreign held=""
  BASE_GEN=""
  # THE freshness rule (round 7, NF-2), first seam: the answer was read against token <gen>; any registry write since
  # (another session's start, stop, join, heartbeat or reap, or this process's own) makes it stale
  if [ -n "$g0" ] && [ "$(leases_token)" != "$g0" ]; then return 99; fi
  PLAN_STOPS=""; START_CANDS=""; F_RC=5; F_OUT=""; F_P=""; F_V="does_not_fit"; F_R="no candidate profile fits"; F_ST=false; F_TH=0; F_EV=no_fit; F_CODE=""
  pst="$(lease_obj_args "$pid")"
  # the reap is a registry write too: a dead holder dropped or a mark cleared after the capacity read makes the answer
  # stale (a cleared mark sets a floor this answer cannot pass, NF-3), so the answer is read again (rc 99) rather than
  # used; with <nostart> 1 (no start can follow) the plan goes on and judges by recorded health only.
  # Round 10 (R9-7): the reap runs BEFORE any other registry write of this plan. Every write of an acquire refreshes the
  # acquiring holder's heartbeat (ACQ_REFRESH), so a write before the reap revived that holder's already-expired lease.
  jp="$(leases_token)"
  reap_locked
  if [ -n "$g0" ] && [ "$(leases_token)" != "$jp" ]; then log "the reap changed the registry after the capacity read; reading it again"; return 99; fi
  # the https gateway read before the lock is part of the registry: the derived cache uses it. Written only when it
  # changed: every write is a new generation, and a write that changes nothing would make a concurrent acquire's answer
  # stale for no reason (round 7)
  cur="$(leases_load)"; jp="$cur"
  cur="$(jq -c --arg u "$GW_URL" --arg ca "$GW_CA" --arg src "$GW_SRC" '.gateway = {url:$u, ca:$ca, source:$src}' <<<"$cur")"
  [ "$cur" = "$jp" ] || printf '%s\n' "$cur" | leases_save
  finalize_locked 0 0
  cur="$(leases_load)"
  # marks set by OTHER processes before this plan (our own marks below are added after this read)
  foreign="$(jq -r '[.sets | to_entries[] | (if (.value.starting // null) != null then "starting" elif (.value.stopping // null) != null then "stopping" else empty end)] | first // ""' <<<"$cur")"
  # (A) owed stops: a failed start whose cleanup stop failed, or a failed disposal stop (never joined; retried)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case " $STOP_TRIED " in *" $p "*) log "owed stop of $p: already tried by this acquire; retried by the next acquire or release"; continue ;; esac
    # round 9 (R8-1): NOT marked here; stop_turn marks the set under the lock right before ITS OWN stop
    PLAN_STOPS+="$p${US}owed"$'\n'
  done < <(jq -r '.sets | to_entries[] | select(((.value.start_failed // null) != null or (.value.stop_owed // null) != null) and (.value.stopping // null) == null and (.value.starting // null) == null and (.value.leases | length) == 0) | .key' <<<"$cur")
  # (B) every existing, unmarked set, judged by its RECORDED health (the observation above, or a newer one): joined when
  # ok; a lease-less constitution-started set whose unit is degraded or gone is stopped (dispose); a set that still has a
  # live lease is never stopped here; nothing is judged or stopped on an undetermined answer or an unknown state.
  local jprofs; jprofs="$(jq -r '.sets | to_entries[] | select((.value.stopping // null) == null and (.value.starting // null) == null and (.value.start_failed // null) == null and (.value.stop_owed // null) == null) | .key' <<<"$cur")"
  if [ -n "$jprofs" ]; then
    while IFS= read -r jp; do
      [ -n "$jp" ] || continue
      hs="$(jq -r --arg p "$jp" '.sets[$p].health.state // "unknown"' <<<"$cur")"
      r="$(jq -r --arg p "$jp" '.sets[$p].health.reason // "not observed"' <<<"$cur")"
      leased="$(jq -r --arg p "$jp" '.sets[$p].leases | length' <<<"$cur")"
      cs="$(jq -r --arg p "$jp" '.sets[$p].constitution_started == true' <<<"$cur")"
      if [ "$hs" = ok ] && [ -n "$PLAN_STOPS" ]; then
        # round 9 (R8-1 class, "a lease held across bounded calls"): this plan also stops a set, so the join is NOT taken
        # now (its lease would age through the stops); the acquire runs the stops, reads a fresh answer and joins then
        log "lease set $jp is joinable; the join is taken after this acquire's stops (a fresh plan)"
        continue
      fi
      if [ "$hs" = ok ]; then
        cur="$(jq -c --arg p "$jp" --arg h "$holder" --argjson l "$(lease_json "$holder" "$pid" "$pst" "$ttl" false)" \
          '.sets[$p].leases = ([.sets[$p].leases[] | select(.holder != $h)] + [$l]) | .route_pref = $p' <<<"$cur")"
        printf '%s\n' "$cur" | leases_save
        F_RC=0; F_OUT="$jp"; F_P="$jp"; F_V=""; F_R="joined an existing lease set ($r)"; F_ST="$cs"; F_TH=0; F_EV=joined
        log "lease joined: holder=$holder profile=$jp ($r)"
        return 0
      fi
      if [ "$leased" = 0 ] && [ "$cs" = true ] && { [ "$hs" = degraded ] || [ "$hs" = absent ]; } && ! case " $STOP_TRIED " in *" $jp "*) true ;; *) false ;; esac; then
        log "disposing $jp: no lease left, constitution-started, instance $hs ($r); bounded llmctl stop outside the lock (marked at its turn)"
        DISPOSE_WHY[$jp]="instance $hs: $r"
        PLAN_STOPS+="$jp${US}dispose"$'\n'
        continue
      fi
      log "refused for $holder: $jp (instance $hs: $r); it keeps its $leased lease(s) and is not stopped; it is not routed"
      if [ -z "$ref_p" ]; then
        ref_p="$jp"; ref_v=undetermined; ref_r="instance $hs: $r"; ref_ev=refused_join
        [ "$hs" != degraded ] || { ref_v=does_not_fit; ref_ev=refused_degraded; }
      fi
    done <<<"$jprofs"
    if [ -n "$ref_p" ]; then
      F_P="$ref_p"; F_V="$ref_v"; F_R="join refused: $ref_r"; F_EV="$ref_ev"
      [ "$ref_ev" != refused_degraded ] || F_R="unit degraded: not joined ($ref_r)"
      log "refused: $ref_p ($ref_r); not joined; fallback route $(fallback_route)"; return 0
    fi
  fi
  # (C) a set another process is starting or stopping refuses this acquire (§11.4.291(J)(3))
  if [ -n "$foreign" ]; then
    F_V=undetermined; F_EV="refused_$foreign"; F_CODE="endpoint_$foreign"
    F_R="endpoint_$foreign: a lease set is $foreign; this acquire is refused and falls back (§11.4.291(J)(3))"
    log "refused ($F_CODE): a lease set is $foreign; fallback route $(fallback_route)"; return 0
  fi
  if [ "$CAP_ST" != ok ]; then
    F_V=undetermined; F_R="$CAP_REASON"; F_EV=undetermined
    log "undetermined ($CAP_REASON): no local start; fallback route $(fallback_route)"; return 0
  fi
  if [ "$CAND_RC" != 0 ]; then
    F_V=undetermined; F_R="candidate list undetermined: llmctl decide capacity exit $CAND_RC (R5-7: never read as no candidate)"; F_EV=undetermined
    log "undetermined: the candidate list could not be read (llmctl decide capacity exit $CAND_RC); no local start; fallback route $(fallback_route)"; return 0
  fi
  if [ "$nostart" = 1 ]; then
    F_V=undetermined; F_EV=undetermined; F_CODE=stale_answer
    F_R="stale_answer: the lease registry changed between the capacity read and the plan $STALE_MAX times in a row; no adoption and no start on an answer that does not describe the registry (§11.4.291(A)(H)); the next evaluation retries"
    log "undetermined (stale_answer): the registry changed during $STALE_MAX consecutive capacity reads; no adoption, no start; fallback route $(fallback_route)"; return 0
  fi
  # (D) adoption first: a candidate llmctl already runs for this user (ok) and that has no set was started by someone
  # else (the operator, or a session outside this registry): join it as NOT constitution-started (never stopped by this
  # producer, §11.4.291(G)(J)); routing adds no resident footprint, so it is preferred over starting another model.
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null && continue
    # round 10 (R9-1): a profile this acquire tried to start is never adopted by it as operator-started
    case " $START_TRIED " in *" $p "*) log "candidate $p: this acquire tried to start it; it is not adopted as operator-started"; continue ;; esac
    # round 11 (R10-1): nor a profile this acquire stopped or disposed: a unit running after this acquire's own stop was
    # started by a start this producer made (the owed stop of its kept set covers it), not by the operator
    case " $STOP_TRIED ${DISPOSED:-} " in *" $p "*) log "candidate $p: this acquire stopped it; a unit running now is not adopted as operator-started"; continue ;; esac
    # round 13 (R12-B1): nor a profile with an unanswered start intent of ANY process: that start may have brought the
    # unit up (a dead starter's intent is turned into an owed stop by intents_locked, never into an adoption)
    if jq -e --arg p "$p" '(.start_intents // {})[$p] != null' <<<"$cur" >/dev/null; then
      log "candidate $p: a start of it by pid $(jq -r --arg p "$p" '.start_intents[$p].pid' <<<"$cur") is in flight (start intent, unanswered); a unit running now is not adopted as operator-started"
      continue
    fi
    IFS="$US" read -r st v th r <<<"$(inst_state "$p")"
    [ "$st" = ok ] || continue
    cur="$(jq -c --arg p "$p" --argjson l "$(lease_json "$holder" "$pid" "$pst" "$ttl" false)" \
      '.sets[$p] = {constitution_started:false, stopping:null, starting:null, leases:[$l]} | .route_pref = $p' <<<"$cur")"
    printf '%s\n' "$cur" | leases_save
    obs_locked   # this answer saw the unit ok: record it on the new set (the derived cache then routes it)
    F_RC=0; F_OUT="$p"; F_P="$p"; F_V=""; F_R="already running (not started by the constitution; $r)"; F_ST=false; F_TH=0; F_EV=joined_running
    log "joined the already-running unit $p (not constitution-started; it is never stopped by this producer)"
    return 0
  done < "$WORK/cands"
  # (E) start candidates (started one by one after this plan, outside the lock)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then log "candidate $p: a lease set already exists (not joinable); skipped"; continue; fi
    case " ${DISPOSED:-} " in *" $p "*) log "candidate $p: stopped by this acquire (hold until the next evaluation, §11.4.291(D))"; held+="$p "; continue ;; esac
    case " $START_TRIED " in *" $p "*) log "candidate $p: its start by this acquire was refused or failed; not started again by it"; continue ;; esac
    lline="$(inst_state "$p")"; IFS="$US" read -r st v th r <<<"$lline"
    case "$st:$v" in
      absent:fits|absent:fits_with_reduced_threads) START_CANDS+="$p$US$v$US$th$US$r"$'\n' ;;
      degraded:*) log "candidate $p: unit degraded ($r); not started a second time, not adopted" ;;
      *) nofit_why="${nofit_why:+$nofit_why; }$p: $r"
         if [ "$v" = undetermined ]; then any_undet=1; undet_why="${undet_why:+$undet_why; }$p: $r"; fi; log "candidate $p: $st/$v ($r)" ;;
    esac
  done < "$WORK/cands"
  # N6-e (round 7): the record carries WHY each candidate is undetermined or does not fit, not only that one is
  if [ "$any_undet" = 1 ]; then F_V=undetermined; F_R="no candidate fits; undetermined: $undet_why"
  elif [ -n "$nofit_why" ]; then F_R="no candidate profile fits: $nofit_why"; fi
  [ -z "$START_CANDS" ] || BASE_GEN="$(leases_token)"
  # a profile this acquire stopped is not restarted by it (no restart loop, §11.4.291(J)(6)): say so in the record
  if [ -n "$held" ]; then F_R="$F_R; held until the next evaluation (stopped by this acquire, never restarted by it): ${held% }"; fi
  return 0
}

# mark_start_locked <profile> <holder> <pid> <pid_start> <ttl> -> 0 marked (set created with a `starting` mark naming this
# process and the holder's lease); 2 STALE: the registry token is not BASE_GEN, the token the capacity answer
# describes (round 7, NF-2: the second and last seam of the freshness rule; the caller reads a fresh answer, it never
# starts on this one); 1 not startable (a set of this profile exists, or ANY set is starting or stopping - this
# process's own marks included, R5-1); 3 RELEASED (round 7, optional 6th argument <held>: the set this acquire already
# started; the holder no longer has a lease there, because it was released or the set was dropped, so this acquire
# starts nothing more - the start-time rule of finish_start_locked (`released`) applied to every further start). The
# release check comes first: it does not depend on the capacity answer, so a release never costs a re-read.
mark_start_locked() {
  local p="$1" held="${6:-}" cur
  reap_locked
  if [ -n "$held" ] && ! jq -e --arg s "$held" --arg h "$2" 'any(.sets[$s].leases[]?; .holder == $h)' <<<"$(leases_load)" >/dev/null; then
    return 3
  fi
  # THE freshness rule at the mark seam: checked AFTER the reap, so a registry write by the reap itself (a dead holder
  # dropped, a dead marker's mark cleared) is a change too
  if [ -z "$BASE_GEN" ] || [ "$(leases_token)" != "$BASE_GEN" ]; then return 2; fi
  cur="$(leases_load)"
  if jq -e --arg p "$p" '.sets[$p] != null' <<<"$cur" >/dev/null; then return 1; fi
  if jq -e 'any(.sets[]?; (.starting // null) != null or (.stopping // null) != null)' <<<"$cur" >/dev/null; then return 1; fi
  # round 13 (R12-B1): an unanswered start intent of this profile (another starter, live or not yet judged) refuses a second start
  if jq -e --arg p "$p" '(.start_intents // {})[$p] != null' <<<"$cur" >/dev/null; then log "candidate $p: a start intent of pid $(intent_of "$p") is unanswered; not started"; return 1; fi
  # round 14 (R13-B1): only a start process that waits on its gate (gate_open, pid + start time known) may be named;
  # without one nothing is marked and nothing is started (fail-closed)
  if [ -z "$GATE_PID" ] || [ -z "$GATE_PST" ]; then log "candidate $p: no gated start process (${GATE_WHY:-its start time is unreadable}); not started"; return 1; fi
  # round 13 (R12-B1): the start intent is written in the SAME registry write as the starting mark (see intents_locked);
  # round 14 (R13-B1): it names the start process (child: pid + start time), so a dead starter's start is judged in flight
  # while that process or its process group lives
  cur="$(jq -c --arg p "$p" --argjson l "$(lease_json "$2" "$3" "$4" "$5" true)" --argjson m "$(me_mark)" \
    --argjson cp "$GATE_PID" --argjson cs "$GATE_PST" \
    '.sets[$p] = {constitution_started:true, started_at:null, stopping:null, starting:$m, leases:[$l]} | .start_intents[$p] = ($m + {child:{pid:$cp, pid_start:$cs}})' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}
# finish_start_locked <profile> <start-rc> -> sets START_RES (caller holds the lock). Round 10 (R9-1): every branch goes
# through set_view and THE RULE (above); a set is deleted, replaced or newly marked only when it is SOLE.
#   placed    rc 0, this acquire's lease is still in the set: the set is a held set (pending until observed)
#   released  rc 0, no lease left and the set is SOLE: marked `stopping` by this process; the caller runs do_stop release
#   handed    rc 0, this acquire's lease is gone but other holders hold the set (or another process marks it): kept for
#             them, never stopped by this acquire; it is not placed for this holder
#   refused   rc 75 (no partial start): a SOLE set is removed; otherwise only this acquire's own lease is dropped and the
#             set is kept (constitution-started: never re-adopted as operator-started)
#   failed    rc other, SOLE: start_failed + a `stopping` mark by this process; the caller runs do_stop cleanup
#   failed_kept rc other, not SOLE: this acquire's lease dropped, the set kept for the others (health pending,
#             start_failed_while_held recorded), no cleanup stop by this acquire (the last release of the set stops it)
finish_start_locked() {
  local p="$1" src="$2" cur floor claim others mine omark m
  cur="$(leases_load)"; m="$(me_mark)"; START_WHY=""
  read -r claim others mine omark <<<"$(set_view "$cur" "$p" starting "$HOLDER")"
  floor="$(obs_counter)"
  if [ "$src" = 0 ] && [ "$claim" != noset ] && [ "$mine" = 1 ]; then
    # floor: an observation whose ticket was taken before this point read the capacity before the start, so it never
    # judges the started set (an absent unit there would otherwise be read as endpoint_gone)
    cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson f "$floor" --arg c "$claim" \
      '(if $c == "ours" then .sets[$p].starting = null else . end) | .sets[$p].started_at = $now | .sets[$p].health = {state:"pending", reason:"started; not observed yet", seq:$f, at:$now} | .route_pref = $p' <<<"$cur")"
    START_RES=placed
  elif [ "$claim" = noset ]; then
    # the set is gone (dropped meanwhile): nobody holds or marks it. 75 started nothing; otherwise the unit may be up and
    # this producer started it, so it is recorded as ours (constitution-started) and stopped by this process
    case "$src" in
      75) START_RES=refused ;;
      0)  cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson m "$m" '.sets[$p] = {constitution_started:true, started_at:$now, starting:null, stopping:$m, leases:[]}' <<<"$cur")"
          START_RES=released ;;
      *)  cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson src "$src" --argjson m "$m" \
            '.sets[$p] = {constitution_started:true, started_at:$now, starting:null, stopping:$m, leases:[], start_failed:{at:$now, rc:$src}}' <<<"$cur")"
          START_RES=failed ;;
    esac
  elif rule_sole "$claim" "$others" "$omark"; then
    # SOLE: no other holder, no other mark; this acquire's own lease (if any) is dropped with the set's new state
    case "$src" in
      0)  cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson m "$m" --arg h "$HOLDER" \
            '.sets[$p] = (.sets[$p] + {constitution_started:true, started_at:$now, starting:null, stopping:$m, leases:[(.sets[$p].leases // [])[] | select(.holder != $h)]})' <<<"$cur")"
          START_RES=released ;;
      75) cur="$(jq -c --arg p "$p" 'del(.sets[$p])' <<<"$cur")"
          START_RES=refused ;;
      *)  cur="$(jq -c --arg p "$p" --argjson now "$NOW" --argjson src "$src" --argjson m "$m" --arg h "$HOLDER" \
            '.sets[$p] = (.sets[$p] + {constitution_started:true, started_at:$now, starting:null, stopping:$m, leases:[(.sets[$p].leases // [])[] | select(.holder != $h)], start_failed:{at:$now, rc:$src}})' <<<"$cur")"
          START_RES=failed ;;
    esac
  else
    # NOT SOLE (R9-1): another holder joined after this process's mark was cleared, or another process marks the set.
    # Only what is ours changes: this acquire's lease is dropped, our mark is cleared only when it is ours, a foreign mark
    # is never touched, and the set is kept.
    # Round 11 (R10-1): the stopping mark seen here is recorded (start_kept.seen_stopping). When no other lease is left
    # (others 0: the only non-sole reason is another process's stopping mark) and this start may have brought the unit up
    # (rc not 75), the set also gets stop_owed: the stopper compares that record with the mark it wrote and keeps the set
    # with an owed stop instead of deleting it (finish_stop_locked), and when the stopper is gone the owed stop is run by
    # the next acquire (plan step A); the set is never routed meanwhile (derive_cache skips stop_owed). Round 11 (R10-3):
    # rc 75 started nothing (no partial start, §11.4.277(E)), so it never makes the set constitution-started; a set made
    # by this acquire's own mark (started_at null) is then constitution-started by nobody (§11.4.291(G)).
    if [ "$others" -gt 0 ]; then START_WHY="the set is held by $others other lease(s)"
    else START_WHY="no other lease holds the set, but another process (pid $(jq -r --arg p "$p" '.sets[$p].stopping.pid // "?"' <<<"$cur")) marks it stopping"; fi
    [ "$omark" = 1 ] && [ "$others" -gt 0 ] && START_WHY="$START_WHY and another process marks it stopping"
    log "the result of llmctl start $p (rc $src) found that $START_WHY (claim $claim): only this acquire's own lease is dropped; the set is kept and is not stopped by this acquire$( [ "$others" = 0 ] && [ "$src" != 75 ] && printf '; it carries an owed stop (stop_owed), run by that stopper or by the next acquire')"
    cur="$(jq -c --arg p "$p" --argjson now "$NOW" --arg mo "$MONO_TOK" --argjson f "$floor" --arg c "$claim" --arg h "$HOLDER" --argjson src "$src" --argjson n "$others" --arg why "$START_WHY" \
      '(.sets[$p].stopping // null) as $seen
       | (if $c == "ours" then .sets[$p].starting = null else . end)
       | (if $src == 75 then .sets[$p].constitution_started = ((.sets[$p].constitution_started == true) and ((.sets[$p].started_at // null) != null))
          else .sets[$p].constitution_started = true end)
       | .sets[$p].leases = [(.sets[$p].leases // [])[] | select(.holder != $h)]
       | .sets[$p].start_kept = {at:$now, mono:(if $mo=="" then null else $mo end), rc:$src, leases:$n, claim:$c, seen_stopping:$seen}
       | (if $n == 0 and $src != 75 then .sets[$p].stop_owed = {at:$now, reason:"llmctl start rc \($src) recorded while \($why); the unit this start may have brought up is owed a stop"} else . end)
       | (if $n > 0 then .sets[$p].health = {state:"pending", reason:"llmctl start rc \($src) recorded while \($n) other lease(s) held the set; not observed since", seq:$f, at:$now} else . end)' <<<"$cur")"
    case "$src" in 0) START_RES=handed ;; 75) START_RES=refused ;; *) START_RES=failed_kept ;; esac
  fi
  case "$START_RES" in released|failed) ARMED_MARK[$p]="$m" ;; esac
  # round 13 (R12-B1): the start is answered in this write: its intent is removed, only when it names THIS process
  cur="$(jq -c --arg p "$p" --arg pid "$$" --arg pst "$ME_START" '((.start_intents // {})[$p] // null) as $i
    | if $i != null and (($i.pid // null) | tostring) == $pid and ((($i.pid_start // null) | tostring) == (if $pst == "" then "null" else $pst end))
      then del(.start_intents[$p]) | (if (.start_intents | length) == 0 then del(.start_intents) else . end) else . end' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}

gw_refuse_locked() { # the refused gateway is cleared from the registry: the derived cache drops the llmctl-local entry
  local cur; cur="$(leases_load)"
  cur="$(jq -c '.gateway = null' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
}

# cmd_acquire: plan -> stops -> starts. Round 7 (NF-2): ONE freshness rule decides every start. A capacity answer is
# read after an observation ticket that records the registry token (leases_token: generation + hash); plan_locked
# (seam 1) and mark_start_locked (seam 2) refuse an answer whose token is not the current one. A stale answer is never
# started on: the first start re-plans on a fresh answer (a join then wins over a start), a further start
# (JEV_PLACE_MAX > 1) reads a fresh answer again. Every registry write is a new token, this process's own included, so a
# stop this acquire made, a refused start and a failed start all lead to a fresh answer before the next start.
# Bounded: STALE_MAX re-reads per plan (then a plan with joins and stops only), STALE_MAX re-plans after a stale mark
# (then no start, reason stale_answer), and a profile is stopped or start-tried at most once per acquire (STOP_TRIED,
# START_TRIED), which bounds the other re-plans.
cmd_acquire() {
  local holder="$1" pid="$2" ttl="$3" rc tries p kind v th r st src started=0 n=0 prof="" pst mrc frc i nostart stale_n=0 replan k
  local out_v="" out_ev="" out_r="" out_p="" out_th=0
  pst="$(lease_obj_args "$pid")"
  if ! gateway_url; then
    log "gateway refused: $GW_WHY; no local placement"
    rc=0; with_lock gw_refuse_locked || rc=$?
    [ "$rc" != 4 ] || log "the refused gateway could not be cleared from the registry (lock timeout); the next acquire retries"
    record_placement "" "" "gateway_refused: $GW_WHY" "$(fallback_route)" false 0 gateway_refused
    return 5
  fi
  candidates > "$WORK/cands"
  DISPOSED=""; STOP_TRIED=""; START_TRIED=""
  while :; do
    tries=0; nostart=0
    while :; do
      observe_read || return 4
      rc=0
      if [ "$nostart" = 0 ]; then with_lock plan_locked "$holder" "$pid" "$ttl" "$OBS_GEN" 0 || rc=$?
      else with_lock plan_locked "$holder" "$pid" "$ttl" "" 1 || rc=$?; fi
      if [ "$rc" = 99 ]; then
        tries=$((tries+1))
        if [ "$tries" -ge "$STALE_MAX" ]; then nostart=1; log "the lease registry changed during $tries consecutive capacity reads; planning joins only (no adoption, no start)"
        else log "the lease registry changed during the capacity read; reading it again ($tries)"; fi
        continue
      fi
      break
    done
    if [ "$rc" = 4 ]; then return 4; fi
    while IFS="$US" read -r p kind; do
      [ -n "$p" ] || continue
      STOP_TRIED+=" $p"
      [ "$kind" != dispose ] || DISPOSED+=" $p"
      stop_turn "$p" "$kind" || true
    done <<<"$PLAN_STOPS"
    if [ "$F_RC" = 0 ]; then
      record_placement "$F_P" "$F_V" "$F_R" "$(current_route)" "$F_ST" "$F_TH" "$F_EV"
      echo "$F_OUT"; return 0
    fi
    replan=0
    if [ -n "$PLAN_STOPS" ]; then
      # a stop by this acquire changed the budget and wrote the registry (its answer is stale, seam 2 would refuse it):
      # plan again on a fresh answer, which can join, or start what the freed budget allows; a profile is stopped at most
      # once per acquire (STOP_TRIED), so this repeats a bounded number of times
      replan=1; log "this acquire stopped a model; reading the capacity answer again (a fresh plan) before any start"
    elif [ -n "$START_CANDS" ]; then
      while IFS="$US" read -r p v th r; do
        [ -n "$p" ] || continue
        [ "$n" -lt "$MAXN" ] || break
        if [ "$n" -gt 0 ]; then
          # a model started by THIS acquire is resident now: the next start is judged on a fresh answer, read after a
          # ticket, so seam 2 can tell when the registry moved after it
          mrc=6; k=0
          while [ "$k" -lt "$STALE_MAX" ]; do
            log "candidate $p: reading a fresh capacity answer (a model started by this acquire is resident now)"
            observe_read || { mrc=4; break; }
            if [ "$CAP_ST" != ok ]; then log "candidate $p: the fresh answer is undetermined ($CAP_REASON); no further start"; mrc=5; break; fi
            IFS="$US" read -r st v th r <<<"$(inst_state "$p")"
            case "$st:$v" in absent:fits|absent:fits_with_reduced_threads) ;; *) log "candidate $p: $st/$v on the fresh answer ($r); not started"; mrc=1; break ;; esac
            BASE_GEN="$OBS_GEN"
            # the 6th argument: the lease this acquire holds is the authority for every further start (rc 3 when gone).
            # Round 14 (R13-B1): the gated start process exists before the mark that names it (gate_open, outside the lock)
            if ! gate_open "$p"; then log "candidate $p: $GATE_WHY"; mrc=1; break; fi
            mrc=0; with_lock mark_start_locked "$p" "$holder" "$pid" "$pst" "$ttl" "$prof" || mrc=$?
            [ "$mrc" = 0 ] || gate_cancel
            [ "$mrc" = 2 ] || break
            k=$((k+1)); log "candidate $p: the registry changed after the fresh capacity read; reading it again ($k)"
          done
          case "$mrc" in
            0) ;;
            1) log "candidate $p: not started (not fitting on the fresh answer, a set exists, or a set is starting/stopping)"; continue ;;
            2) log "candidate $p: the registry kept changing ($STALE_MAX fresh reads, stale_answer); no further start"; break ;;
            3) log "candidate $p: not started: the lease of $holder on $prof, taken by this acquire, is gone (released, or the set was dropped); no further start"; break ;;
            4) log "candidate $p: lease lock timeout; no further start"; break ;;
            *) break ;;
          esac
        else
          # round 14 (R13-B1): the gated start process exists before the mark that names it (gate_open, outside the lock)
          if ! gate_open "$p"; then log "candidate $p: $GATE_WHY"; continue; fi
          mrc=0; with_lock mark_start_locked "$p" "$holder" "$pid" "$pst" "$ttl" || mrc=$?
          [ "$mrc" = 0 ] || gate_cancel
          if [ "$mrc" = 4 ]; then return 4; fi
          if [ "$mrc" = 2 ]; then
            if [ "$stale_n" -ge "$STALE_MAX" ]; then
              log "undetermined (stale_answer): the lease registry changed between the capacity read and the start mark $((stale_n+1)) times; no start by this acquire"
              out_p=""; out_v=undetermined; out_ev=undetermined; out_th=0; F_CODE=stale_answer
              out_r="stale_answer: the lease registry changed between the capacity read and the start mark $((stale_n+1)) times; no start on an answer that does not describe the registry (§11.4.291(A)(H)); the next evaluation retries"
              break
            fi
            stale_n=$((stale_n+1)); replan=1
            log "candidate $p: the lease registry changed after the capacity read (stale answer); planning again on a fresh answer ($stale_n)"
            break
          fi
          # 1: the registry is the one the answer describes (the token is unchanged), so the next candidate is judged
          # on the same answer
          if [ "$mrc" != 0 ]; then log "candidate $p: no longer startable (a set exists or a set is starting/stopping)"; continue; fi
        fi
        # round 14 (R13-B1): the start runs in the start process named by the intent (gate_go: llmctl runs only now)
        src=0; gate_go "$p" || src=$?
        START_RES=""; frc=4; i=0
        while [ "$i" -lt "$RETRIES" ]; do
          frc=0; with_lock finish_start_locked "$p" "$src" || frc=$?
          [ "$frc" = 4 ] || break
          i=$((i+1)); log "record step for llmctl start $p (rc $src): lock wait $i/$RETRIES timed out"
        done
        if [ "$frc" != 0 ]; then
          if [ "$src" = 0 ]; then
            started=1; n=$((n+1)); prof="${prof:-$p}"
            out_p="$prof"; out_v="$v"; out_ev=placed; out_th="$th"
            out_r="lease held, start recorded late: llmctl start $p rc 0; the record step could not take the lock ($RETRIES waits of ${LOCK_TMO}s)"
            log "lease held, start recorded late: llmctl start $p rc 0, but the record step could not take the lease lock ($RETRIES waits of ${LOCK_TMO}s). The lease of $holder is in the registry since the start mark; the starting mark is cleared once this process is gone and the next observation routes the set. No further candidate is started."
            break
          fi
          log "llmctl start $p rc $src: its result could not be recorded ($RETRIES lock waits); the registry may still hold the lease of $holder under the starting mark: release it. No further candidate is started."
          if [ "$n" = 0 ]; then return 4; fi
          break
        fi
        case "$START_RES" in
          placed)
            started=1; n=$((n+1)); prof="${prof:-$p}"
            out_p="$prof"; out_v="$v"; out_ev=placed; out_r="$r"; out_th="$th"
            log "started $p ($v, threads=$th); lease holder=$holder; it is routed once an observation newer than the start reads its unit ok" ;;
          released)
            log "started $p but its lease was released during the start; stopping it again; no further candidate is started"
            do_stop "$p" release || true
            break ;;
          handed)
            # round 10 (R9-1): started, but this acquire's lease is gone and other holders hold the set: kept for them
            log "started $p but its lease was released during the start and $START_WHY: kept, not stopped by this acquire and not placed for $holder; no further candidate is started"
            break ;;
          refused)
            log "llmctl start $p refused (75): does_not_fit"
            START_TRIED+=" $p"
            [ "$out_ev" = start_failed ] || { out_v="does_not_fit"; out_ev="start_refused"; out_r="llmctl start $p refused (75, pressure gate)"; out_p="$p"; out_th="$th"; }
            # the refused start removed its set (a registry write): the next start needs a fresh answer
            if [ "$n" = 0 ]; then replan=1; break; fi ;;
          failed)
            log "llmctl start $p failed rc=$src: $(head -c 300 "$WORK/start.out.err" 2>/dev/null | tr '\n' ' ')"
            START_TRIED+=" $p"
            # the capacity verdict stays what was MEASURED; the failure is the event (review 2026-11-12 F5)
            out_v="$v"; out_ev="start_failed"; out_r="llmctl start $p failed rc=$src"; out_p="$p"; out_th="$th"
            # Live T5 (2026-11-12): llmctl can fail AFTER the unit began starting; the unit was not running before (its
            # state was absent), so this producer started it and stops it again. 75 (no partial start) needs nothing.
            log "start of $p failed after it was requested; stopping it again so no unit is left without a lease"
            if ! do_stop "$p" cleanup; then
              out_r="llmctl start $p failed rc=$src; cleanup stop failed (set kept, stop retried)"
              log "the cleanup stop of $p failed: the model may be resident, so no further candidate is started"
              break
            fi
            if [ "$n" = 0 ]; then replan=1; break; fi ;;
          failed_kept)
            # round 10 (R9-1): the start failed, but other sessions hold the set (they joined after this process's mark
            # was cleared): their leases are kept, the set is judged by the next observation, no cleanup stop here
            log "llmctl start $p failed rc=$src: $(head -c 300 "$WORK/start.out.err" 2>/dev/null | tr '\n' ' ')"
            START_TRIED+=" $p"
            out_v="$v"; out_ev="start_failed"; out_r="llmctl start $p failed rc=$src; $START_WHY: the set is kept (no cleanup stop by this acquire)"; out_p="$p"; out_th="$th"
            break ;;
        esac
      done <<<"$START_CANDS"
    fi
    [ "$replan" = 1 ] || break
  done
  if [ "$started" = 1 ]; then
    # observe the started model(s): the set is routed only after an observation newer than its start (derive_cache)
    if observe_read; then frc=0; with_lock finalize_locked 0 0 || frc=$?; [ "$frc" = 0 ] || log "the observation after the start could not be recorded (lock rc $frc); the next observation routes the set"
    else log "the observation after the start could not take the lock; the next observation routes the set"; fi
    record_placement "$out_p" "$out_v" "$out_r" "$(current_route)" true "$out_th" placed
    echo "$prof"; return 0
  fi
  if [ -n "$out_ev" ]; then F_P="$out_p"; F_V="$out_v"; F_R="$out_r"; F_TH="$out_th"; F_EV="$out_ev"; [ "$out_ev" = undetermined ] || F_CODE=""; fi
  record_placement "$F_P" "$F_V" "$F_R" "$(fallback_route)" false "$F_TH" "$F_EV" "$F_CODE"
  log "no local placement ($F_EV); fallback route $(fallback_route)"; return 5
}

release_locked() {
  local holder="$1" cur prof r0 r1 stops=""
  r0="$(current_route)"
  finalize_locked 1 0
  cur="$(leases_load)"
  cur="$(jq -c --arg h "$holder" '.sets |= map_values(.leases |= map(select(.holder != $h)))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  # EVERY constitution-started set with no lease left (JEV_PLACE_MAX>1 starts several) and no mark is a stop candidate;
  # round 9 (R8-1): it is NOT marked here. stop_turn marks each set under the lock right before ITS OWN stop, outside this
  # section, and judges it again then (a set joined meanwhile keeps running). A set still starting is finished by its
  # starter (it stops it when no lease is left).
  while IFS= read -r prof; do
    [ -n "$prof" ] || continue
    echo "$prof"; stops+=" $prof"
  done < <(jq -r '.sets | to_entries[] | select((.value.leases | length) == 0 and (.value.constitution_started == true) and (.value.stopping // null) == null and (.value.starting // null) == null) | .key' <<<"$cur")
  # an empty set this producer did not start is just forgotten (an operator-started model is never stopped)
  cur="$(jq -c '.sets |= with_entries(select((.value.leases | length) > 0 or .value.constitution_started == true))' <<<"$cur")"
  printf '%s\n' "$cur" | leases_save
  r1="$(current_route)"
  # a route change with no stop to record (the stop writes its own record) is recorded here
  if [ "$r0" != "$r1" ] && [ -z "$stops" ] && [ "$GONE_WRITTEN" = 0 ]; then
    log "route changed: $r0 -> $r1 (release)"
    write_placement "" "" "route_changed: $r0 -> $r1 (release of $holder)" "$r1" false 0 route_changed || true
  fi
}

hb_locked() { # hb_locked <holder> (caller holds the lock) -> 0 refreshed, 3 the holder holds no lease
  local c
  finalize_locked 1 1
  c="$(leases_load)"
  if ! jq -e --arg h "$1" 'any(.sets[]?.leases[]?; .holder == $h)' <<<"$c" >/dev/null; then
    log "heartbeat: holder $1 holds no lease (released, reaped, released because its endpoint is gone, or never taken); route locally only after a new acquire - a lease is never assumed (§11.4.291(J)(1))"
    return 3
  fi
  c="$(jq -c --arg h "$1" --argjson now "$NOW" --arg mo "$MONO_TOK" '.sets |= map_values(.leases |= map(if .holder == $h then .heartbeat_at = $now | .heartbeat_mono = (if $mo=="" then null else $mo end) else . end))' <<<"$c")"
  printf '%s\n' "$c" | leases_save
}

sub="${1:-}"; shift || true
case "$sub" in
  verdict) cmd_verdict "${1:-}" ;;
  acquire)
    holder="${1:-}"; shift || true; pid=""; ttl="$TTL_DEFAULT"
    jev_check_word "$holder" || { echo "jev-place: acquire needs a holder id ([A-Za-z0-9._-]+)" >&2; exit 2; }
    while [ $# -gt 0 ]; do case "$1" in --pid) pid="${2:-}"; shift 2 ;; --ttl) ttl="${2:-}"; shift 2 ;; *) echo "jev-place: unknown arg $1" >&2; exit 2 ;; esac; done
    case "$pid" in *[!0-9]*) echo "jev-place: --pid must be an integer" >&2; exit 2 ;; esac
    case "$ttl" in ''|*[!0-9]*) echo "jev-place: --ttl must be an integer" >&2; exit 2 ;; esac
    # R5-4, §11.4.291(J)(1): a lease must outlive one re-evaluation cycle plus one bounded llmctl call
    if [ "$ttl" -le $(( CADENCE + RTMO )) ]; then
      echo "jev-place: lease TTL ${ttl}s is not greater than the re-evaluation cadence ${CADENCE}s (JEV_REEVAL_CADENCE) + the llmctl timeout ${RTMO}s (JEV_LLMCTL_TIMEOUT): config error, refused (§11.4.291(J)(1))" >&2
      exit 2
    fi
    HOLDER="$holder"; ACQ_REFRESH=1
    rc=0; cmd_acquire "$holder" "$pid" "$ttl" || rc=$?
    if [ "$rc" = 4 ]; then record_placement "" "undetermined" "lease_lock_timeout: no lease taken" "$(fallback_route)" false 0 lease_lock_timeout; log "lease_lock_timeout: no lease taken"; fi
    exit "$rc" ;;
  heartbeat)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: heartbeat needs a holder id" >&2; exit 2; }
    HOLDER="$holder"
    observe_read || { log "heartbeat: lease lock timeout (the heartbeat is not recorded)"; exit 4; }
    rc=0; with_lock hb_locked "$holder" || rc=$?
    [ "$rc" != 4 ] || log "heartbeat: lease lock timeout (the heartbeat is not recorded)"
    exit "$rc" ;;
  release)
    holder="${1:-}"; jev_check_word "$holder" || { echo "jev-place: release needs a holder id" >&2; exit 2; }
    HOLDER="$holder"
    observe_read || { log "release: lock timeout (rc 4)"; exit 4; }
    rc=0; stopprofs="$(with_lock release_locked "$holder")" || rc=$?
    [ "$rc" = 0 ] || { log "release: lock timeout (rc $rc)"; exit "$rc"; }
    rrc=0
    while IFS= read -r stopprof; do
      [ -n "$stopprof" ] || continue
      # a stop can take as long as a start (model unload, unit shutdown): bounded by the START/STOP timeout, not RTMO
      src=0; stop_turn "$stopprof" release || src=$?
      case "$src" in 0|5) ;; *) rrc=6 ;; esac
    done <<< "$stopprofs"
    exit "$rrc" ;;
  reap)
    observe_read || { log "reap: lock timeout (rc 4)"; exit 4; }
    with_lock finalize_locked 1 1 ;;
  status)
    if observe_read; then with_lock finalize_locked 1 1 || log "status: the observation could not be recorded (lock rc $?)"
    else log "status: lease lock timeout; the observation is not recorded"; fi
    if [ "${1:-}" = "--json" ]; then jq -nc --slurpfile l <(leases_load) --slurpfile p <( [ -f "$PLACEMENT" ] && cat "$PLACEMENT" || echo '{}') --arg route "$(current_route)" '{leases:$l[0], placement:($p[0].placement // null), route:$route}'
    else leases_load | jq -r '.sets | to_entries[] | "\(.key): leases=\(.value.leases|length) constitution_started=\(.value.constitution_started) stopping=\(.value.stopping != null) starting=\((.value.starting // null) != null) health=\(.value.health.state // "unobserved")"'
      echo "route: $(current_route)"
      # N6-b (round 7): no placement record yet is a state to report, not a failure (status exits 0)
      if [ -f "$PLACEMENT" ]; then jq -r '.placement | "placement: profile=\(.profile) verdict=\(.verdict) event=\(.event) route=\(.route) reason=\(.reason)"' "$PLACEMENT"
      else echo "placement: none recorded yet"; fi; fi ;;
  ""|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; [ -n "$sub" ] && exit 0 || exit 2 ;;
  enable|disable|switch|auto) echo "jev-place: '$sub' is never run by the constitution (§11.4.291(G))" >&2; exit 2 ;;
  *) echo "jev-place: unknown subcommand '$sub'" >&2; exit 2 ;;
esac
