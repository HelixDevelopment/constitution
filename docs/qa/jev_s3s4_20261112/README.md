# Jev S3/S4 live runs, 2026-11-12

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-11-12 |
| Last modified | 2026-11-15T17:22:22Z |
| Status | evidence (CON-401, In progress; carried as CON-299 on the vehicle) |
| Host | the reference host (16 CPUs, load average about 30 during the runs) |

Live runs for CON-401 (carried as CON-299 on the vehicle before landing; on `main` CON-299 is another item) (Jev streams S3 and S4, operator decision of 2026-11-12). Every run used the real host, the
real `llmctl` on PATH, the operator's keys file read BY PATH (values never printed; the pack was scanned for every
key value after it was assembled and none is present), and sandbox directories for every Jev state, config,
evidence and provider-cache path. No operator agent home was written: T4 ran with a sandbox `HOME`; the mtimes of
the operator's `~/.claude-shared/settings.json` and `.mcp.json` predate the runs.

The scripts that produced the runs are in this directory (`t3.sh`, `t4.sh`, `t4_gate.sh`, `t5.sh`). Checksums of
every file are in `SHA256SUMS`.

Round 3 (2026-11-12): the fixes for the review of `c2489197` and their RED/GREEN logs and mutant results are in
[`round3/README.md`](round3/README.md). `t4_gate.sh` was edited after the T4 runs were captured (it now exits when `cd`
fails, shellcheck SC2164); the runs were made with the earlier text. `SHA256SUMS` was regenerated for the whole pack.
None of the live runs here was re-captured in round 2 or round 3.

## T3 detection (bootstrap, no consent, no default-on)

`t3_run1..3`: a fresh clone without checked-out submodules. `t3b_run1..3`: the same with `LLMCTL_DIR` and
`CLAUDE_TOOLKIT_DIR` pointing at shared clones of the pinned submodules.

| Run | rc | jev-typesafe | jev-openrouter | Local llmctl endpoint |
|---|---|---|---|---|
| t3 1-3 | 5 | 2xx, reachable, usable | HTTP 402 `no_credit`, reachable=false, usable=false | none (llmctl and claude_toolkit recorded unavailable: no consent to clone) |
| t3b 1-3 | 5 | same | same | none: no decide profile was running (`llmctl decide status`: gateway running, `running: []`) |

The RESULT line in every run: `rc 5: detected, not wired (1 usable endpoint(s), no agent wired ...)`.
The three runs of each variant gave the same record (same ids, classes, reachability and rc).

Correction (round 2, review 2026-11-12 F1): these records were written by the stage-3 code whose cache key held only the
key states. A second bootstrap run then reused the record without probing again, so `no_credit` would have stayed
recorded after credit was added. Fixed in round 2 (the stage key now holds each recorded endpoint's current probe
answer; `tests/jev/test_s3_bootstrap_honesty.sh` H7). The T3 runs were NOT re-captured after the fix.

## T4 default-on in a fresh project, one real gate call

`t4_run1..3`: sandbox `HOME`, `bootstrap.sh --non-interactive --default-on` (rc 0, `install-per-agent: ok wired
agents=all`, consent recorded in `consent.json`), then ONE PreToolUse Bash payload through the hook command the
bootstrap wired (`settings.hooks.json`), twice per run:

| Variant | Environment of the gate | Row written (each run) |
|---|---|---|
| A | the operator session's own `CMA_JEV_ENDPOINT_ID` / `JEV_BASE_URL` (pinned to `jev-openrouter`) | `endpoint: jev-openrouter`, `fallback: endpoint_error`, answer `allow` (fail-open), latency 110-122 ms |
| B | routing from the toolkit's TypeSafe provider pin (`https://api.typesafe.ai`, `TYPESAFE_API_KEY`) | `endpoint: jev-typesafe`, no fallback, answer `allow`, confidence 0.98, `risky_p` 0.05 / 0.05 / 0.06, latency 213-237 ms |

Each run wrote exactly two rows (one per call; `decisions.jsonl`). The verdict was the same in all three runs; the
`risky_p` value differed in the second decimal (the endpoint is a model, its score is not bit-identical).

OMITTED IN REVISION 1 (review 2026-11-12 F4): in all three T4 runs the bootstrap's own `cm_jev_wiring` gate reported
`FAIL rc=1 ... claude: settings.json lacks a PreToolUse hook entry referencing jev-gate.sh` (advisory, in `boot.err`)
right next to `ok wired`. The cause was the gate, not the wiring: it read only `~/.claude/settings.json`, while the
toolkit wired `~/.claude-shared/settings.json` (captured in `settings.hooks.json`). Fixed in round 2 (one resolver for
`cm_jev_wiring` and `jev-status.sh`); the fix is checked by replaying the captured `settings.hooks.json` through the gate
in `tests/jev/test_jev_status_health.sh`. T4 was NOT re-run live after the fix.

FINDING (not fixed here; claude_toolkit is owned elsewhere, the environment is the operator's): sessions that carry
the operator's current environment send every gate call to `jev-openrouter`, which answers 402, and the gate does
not fail over to `jev-typesafe`. Those calls are logged `endpoint_error` and allowed fail-open. The toolkit's
endpoint cache produced by `sync-jev` was empty in the sandbox (`endpoints: []`).

## T5 local placement

`t5_verdict_before.json`: read-only `jev-place.sh verdict --json` before the runs: contract ok, all six
systemone-native decide profiles `fits` (threads 3).

`t5_run1..3`: `jev-place.sh acquire` with `JEV_PLACE_PROFILES=decide-kev-08b`, a lease holder process owned by the
script, then `release`.

| Run | acquire rc | What happened | After release |
|---|---|---|---|
| 1-3 | 5 | `llmctl start decide-kev-08b` failed rc 1: the unit stayed `Starting` (llmctl: "still starting after 20s"; systemd also reported that the unit file had changed on disk and asked for `daemon-reload`). The producer sent one bounded `llmctl stop` (the cleanup added after the first live attempt) and routed to `cloud` | no lease, no running unit, no cache entry |

Instrument defect (review 2026-11-12 F6): the `placement:` line of every `t5_run*/t5.txt` shows only nulls, because
`t5.sh` read the fields at the top level of `placement.json` while they are under `.placement`. The real records are the
`t5_run*/placement.json` files kept next to them. Those records say `verdict: does_not_fit`, reason "no candidate profile
fits or started", although capacity said `fits`: the real cause was the failed start (rc 1). That label was a producer
defect, fixed in round 2 (the verdict now stays the measured `fits`, and `event: start_failed` names what happened;
`tests/jev/test_s4_placement.sh` P26). `t5.sh` now reads `.placement` behind a control needle. T5 was NOT re-captured
after these fixes (no real llmctl call was allowed in round 2).

`t5_unit_journal.txt`: each start stayed in `Starting` for about 83 s with a memory peak near 9 MB (the model never
loaded) and ended with the cleanup TERM.

NOT shown live on this day: a successful local placement, its cache entry at priority 10, and the stop on the last
release. Those paths are covered only by the gate-logic test `tests/jev/test_s4_placement.sh` (stub llmctl,
§11.4.289(C)(2)). Shown live 3/3: a failed start leaves nothing behind and the route falls back.

Not done (operator decision): `daemon-reload` and `reset-failed` of the llmctl units; the unit
`llmctl-llama@decide-kev-08b` is left in `failed` state after the runs.
