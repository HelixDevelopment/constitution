# Jev Decision Layer — Troubleshooting

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-10-23 |
| Last modified | 2026-11-13T17:36:01Z |
| Status | active |
| Status summary | Symptom, cause, action, and the command that shows which it is. |
| Authority | Constitution §11.4.279–§11.4.286. The canonical anchor texts and the scripts govern where this document and they disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
| Fixed summary | — |
| Continuation | none |

Related: [governance guide](governance-guide.md) · [bootstrap reference](bootstrap-reference.md) · [diagrams](diagrams.md)

## Table of contents

- [Bootstrap](#bootstrap)
- [Detection](#detection)
- [Gate and MCP](#gate-and-mcp)
- [Calibration](#calibration)
- [Hosted credit and failover](#hosted-credit-and-failover)
- [Placement](#placement)
- [Status](#status)

## Bootstrap

| Symptom | Cause | Action |
|---|---|---|
| Exits 2 at once, "refusing to hang" | No TTY and no `--non-interactive` | Re-run with `--non-interactive` or from a terminal. |
| Exits 2, "jq is a hard prerequisite" | `jq` not on PATH | Install `jq`, re-run. A pending stamp `missing-prerequisite:jq` was written. |
| Exits 3, "operator-required stop" | A managed clone under `$JEV_BOOTSTRAP_HOME` has local changes | Resolve it by hand (commit, stash or move it), re-run. Nothing was overwritten. |
| Exits 5, `RESULT rc 5: no usable decision endpoint` | Every detected endpoint was probed and answered non-2xx or was unreachable | Read the `WARNING:` lines and `jev-status.sh` "Endpoint health": `no_credit` (HTTP 402) means add credit on that provider; `401`/`403` means the key is refused; `rate_limited` (429) means wait. A local `llmctl-*` endpoint that is unreachable means no gateway runs (see Placement below). |
| Exits 5, `RESULT rc 5: detected, not wired` | Endpoints exist but no agent is wired: no consent, or a placeholder key so default-on did not engage | Run `bootstrap.sh --default-on` with a real key in the keys file, or `--yes`. The log line `default-on not engaged: <why>` names the reason. |
| `RESULT rc 0: detected, NOT wired - the operator opted out` | `$JEV_CONFIG_DIR/wiring.disabled` exists or `JEV_WIRING=off` | Intended. Remove the marker to wire again. Nothing is served while opted out. |
| Wiring reads `not wired` although `jev-gate.sh` appears in `settings.json` | The command mentions the gate without running it: as an assignment value (`X=/x/jev-gate.sh`), in a comment, as an argument of another command (`echo /x/jev-gate.sh`), as a renamed file (`jev-gate.sh.disabled`), or with an unterminated quote | Wiring is decided structurally: a PreToolUse hook command counts only when one of its simple commands runs a file named exactly `jev-gate.sh`, directly, through `env`/`exec`, through `sh`/`bash`/`zsh`/`dash`, or through such an interpreter's `-c` script (3 levels deep). Variables, `$(...)`, aliases and a script fed on stdin are not expanded. Point the command at the gate itself. |
| Post-update hook prints `jev-bootstrap: rc 5 ...` | Same as the two rc 5 rows above | It is a warning, not a deferral; the pull completed. |
| Stage 2 shows `source=unavailable`, pending `provision requires consent` | Cloning is consent-gated; the default (and the post-update hook) never touches the network | Re-run with `--allow-clone` (or `--yes`), or provide `LLMCTL_DIR` / `CLAUDE_TOOLKIT_DIR`, or recurse submodules (`git submodule update --init submodules/llmctl submodules/claude_toolkit`), re-run. |
| Stage 2 `source=unavailable` with reason `git clone failed` | Offline, no SSH key, or host unreachable | Fix access and re-run; the stage is retried automatically (it is never cached as done). |
| Stage 2 shows `ref_status=pin-not-reachable` | The manifest ref is not in that clone | `git -C <clone> fetch`, or fix the ref in `helix-deps.yaml`. |
| Stage 4 `skipped toolkit-unavailable` | The toolkit checkout has no `scripts/jev-setup.sh` (true at pin `1f6dad3`) | Move the pin to a toolkit commit that ships the Jev scripts, or point `CLAUDE_TOOLKIT_DIR` at one. |
| Stage 4 `pending-consent` | Agent homes not allowed to be edited | Read the printed audit lines, then re-run with `--yes`. |
| Stage 4 `failed jev-setup rc=N` | The toolkit installer refused or failed | Run `jev-setup.sh --check --agents <agent>` and read its output; rc 3 means consent was missing. |
| Pending stamp does not clear | The last run recorded outstanding reasons | `jev-status.sh` prints the reason; resolve it and re-run — a clean run removes the file. |
| Second run rewrites files | A managed file was hand-edited, or an input changed | Check which stage printed `running`; its inputs differ. Delete `bootstrap.stamp` only to force a full re-evaluation. |

## Detection

| Symptom | Cause | Action |
|---|---|---|
| `endpoints: []` with a reason | No decide profile running and no cache entries | Lawful (§11.4.279(B)). Start a profile (`llmctl start decide-tiny`, `llmctl decide serve`) or add a hosted key, then `claude-providers sync-jev` and re-run. |
| `reachable=null` on a cache entry | The cache records resolution, not a probe | Probe with `CMA_JEV_LIVE=1 claude-providers sync-jev` (this contacts the provider), or call `jev_models`. |
| `reachable=false` on `llmctl-<profile>` | The profile runs but the gateway does not | `llmctl decide serve --status`, then `llmctl decide serve`. |
| Native profile `decide-kev-*` answers 503 | Gateway started without `LLMCTL_DECIDE_NATIVE=1` | Restart the gateway with it set. |
| Downloaded a profile but still no endpoint | Download does not start it | Start it, then re-run bootstrap. |

## Gate and MCP

| Symptom | Cause | Action |
|---|---|---|
| Rows show `fallback":"timeout"` | `JEV_GATE_TIMEOUT` (2 s) shorter than the engine's latency | Raise it, or use a faster profile. On CPU the gateway budget can be 120 s. |
| Rows show `endpoint_error` | Endpoint unset or unreachable; TLS or CA problem on `https://` | Check `JEV_BASE_URL`, `JEV_CA_FILE`, and that the key variable NAME in `JEV_KEY_VAR` is set; `curl --cacert` the `/healthz` path by hand. |
| HTTP 401 / 429 from the gateway | Missing or wrong bearer key; repeated failures are throttled | Check `JEV_KEY_VAR` names a set variable. Do not print its value. |
| HTTP 422 `readout_failed` | The model did not answer an option letter | Not retryable for that input; reword the question or use another profile. |
| Nothing is blocked | Mode is shadow, or `JEV_GATE=off` | `jev-status.sh` shows the mode; `gate-off.log` shows kill-switch uses. |
| opencode does not gate an MCP or subagent call | Platform limitation | Recorded in `~/.config/opencode/jev-coverage-gaps.md`. |
| `jev_ask` returns `isError` | Endpoint unreachable or key unresolved | Same checks as `endpoint_error`; the server never hangs. |
| Route result has `degraded:true` | No candidate met `min_confidence`, or candidates disagreed | Inspect the candidates; the answer returned is the highest-priority live one. |

## Calibration

| Symptom | Cause | Action |
|---|---|---|
| "nothing calibratable" (rc 1) | Rows lack question, criteria and state text | Needs a logging schema that records them (governance guide, limitations). |
| rc 2 "no label command" | No `JEV_CALIBRATE_ALIAS_CMD` and no toolkit alias file | Set the command, or install the toolkit aliases. |
| Many `label_errors` | The labeling reply was not JSON `{"label": …}` | Counted, never guessed; use a command that emits bare JSON. UNCONFIRMED how a given alias formats replies. |
| Type stays shadow with `insufficient-sample` | Fewer labeled rows than `JEV_CALIBRATE_MIN_SAMPLE` | Collect more shadow decisions. |
| A type was DEMOTED | It was promoted before and now misses the floor | Intended; it reverts to shadow. The previous file is `jev-thresholds.<epoch>.json`. |

## Hosted credit and failover

| Symptom | Cause | Action |
|---|---|---|
| OpenRouter shows `reachable=false usable=false class=no_credit` | The key is valid but the account has no credit (HTTP 402) | Add credit, then re-run the bootstrap: it re-probes every endpoint of the previous record before it decides whether the detection stage changed, so the record is rewritten to `2xx` (and to `no_credit` again if credit runs out). `bash scripts/jev/jev-probe.sh` only checks the endpoint (exit 0 on 2xx); it does not rewrite the record, and `jev-status.sh` makes no probe at all. Until the credit is there, gate calls sent to that endpoint are NOT moved to another one: measured 2026-11-12 (T4, `docs/qa/jev_s3s4_20261112/README.md`), a gate pinned to `jev-openrouter` logged `fallback: endpoint_error` and allowed the call (fail-open) without trying `jev-typesafe`. Point the session at a working endpoint (`CMA_JEV_ENDPOINT_ID`, `JEV_BASE_URL`) until then. |
| Decisions keep going to a hosted endpoint although a local model fits | The local gateway entry is absent from the endpoint cache | `bash scripts/jev/jev-place.sh status`. Since round 6 (2026-11-13) the `llmctl-local` entry (priority 10) is DERIVED from the lease registry at every registry write: it is present only while a set holds a lease, carries no `starting`/`stopping` mark, no failed start and no owed stop, and its own unit was read `ok` by an observation newer than its start (`status` shows `health`). Right after a start the entry appears at the observation that follows it. The toolkit's `claude-providers sync-jev` rewrites the cache and may drop that entry (integration point, owned by claude_toolkit). |
| Failover order looks wrong | The cache order (priority, lower first) is read by the claude_toolkit gate and MCP server; whether a failed call moves on to the next entry is the toolkit's behaviour, and the T4 run above showed a pinned session that did not | Inspect `~/.local/share/claude-multi-account/providers/jev-endpoints.json` and the gate rows (`jev-status.sh` "Endpoint health" counts each attempt). This repository writes the local entry only. |

## Placement

| Symptom | Cause | Action |
|---|---|---|
| `jev-place.sh acquire` exits 5, verdict `undetermined` | `llmctl capacity --json` answered outside the contract (wrong schema, a required field of the §11.4.291(C) table absent or of the wrong type, `measurement.critical_inputs_unreadable` non-empty, timeout, unmeasured RLIMIT_NPROC headroom; round 7 checks every row of the table and the reason names the field) | The reason is in `placement.json` and on stderr. Undetermined never starts a model. |
| Exits 5, `does_not_fit` | Not enough RAM/CPU with the host reserve kept, pressure high, or the unit is degraded | Wait or free resources; the route is `cloud` with a hosted key, else `none`. |
| Exits 4, `lease_lock_timeout` | Another session holds the placement lock | Retry; no lease was taken. |
| `release` exits 6, `stop_failed` | The last release's `llmctl stop` failed or ran past `JEV_LLMCTL_START_TIMEOUT` | The model may still run, so the lease set is kept (`constitution_started`, `stop_failed {at, rc}`) and the cache entry stays. The next `release` retries the stop once the stop mark is cleared (the stopper process has exited, or the mark is older than `MARK_TTL` = the start/stop timeout + 2 s + `JEV_RECORD_RETRIES` × `JEV_LOCK_TIMEOUT` + 30 s, round 7; before round 7 it was the stop timeout + 30 s, which could clear the mark of a live stopper still waiting for its record lock); an `acquire` meanwhile joins the running model. |
| `acquire` logs `disposing <p>: no lease left, constitution-started, ...` | Every holder of a model this producer started was reaped, and the next acquire found its own unit `degraded` (llmctl reports a unit status of only `ok` or `degraded`) or gone (no own unit in the capacity answer). A lease-less set whose unit is `ok` is joined again, never stopped | The acquire stops that model (bounded `llmctl stop`), drops the set and its cache entry, and does not restart the profile in the same call; the next acquire evaluates it afresh. If the stop fails the set is kept as `stop_owed` + `stop_failed`, is never joined, and every later acquire and release retries the stop. A set that still has a live lease is never stopped this way, and a reap alone never stops a model. |
| `placement.json` shows `event: start_failed` with `verdict: fits` | Capacity said the profile fits, but `llmctl start` failed | The verdict is what was measured; the event is what happened. See the next row for the measured cause. |
| Exits 5 with `llmctl start <p> failed rc=1 ... still starting after 20s ... never answered .../health` | The unit was started but its start gate or model load did not finish in llmctl's own wait (measured 2026-11-12 on the reference host at load average about 30 on 16 CPUs: the unit sat in `Starting` for about 83 s with a 9 MB memory peak, so the model never loaded) | `jev-place.sh` sends one bounded `llmctl stop <p>` for a profile it asked to start, so no unit is left running without a lease, and routes to `cloud`/`none`. The unit then shows `failed`; that record is left for the operator. Retry when the host is quieter. |
| `llmctl` warns that the unit file `changed on disk` and asks for `daemon-reload` | The unit file was rewritten outside this run (seen 2026-11-12) | The constitution never runs `daemon-reload`; the operator decides. |
| A decide unit was already running before `acquire` | Someone else started it | It is joined with `constitution_started=false`: it is never started again and the last release never stops it. llmctl 3.4.1 reports a unit status of only `ok` or `degraded`; a degraded unit is neither joined nor started again. "Starting" is the producer's own mark: while any set carries a `starting` or `stopping` mark a new acquire is refused (`refused_starting` / `refused_stopping`, reason code `endpoint_starting` / `endpoint_stopping`) and no second start is made. |
| `acquire` logs `endpoint_gone: the unit of <p> is gone ...` and exits 5 | A held set's own unit disappeared (crashed, or stopped outside the producer) | Every lease of that set is released (the holders are named), the route moves to the fallback, and the producer does not restart the profile in the same call (no restart loop, §11.4.291(J)(6)); a constitution-started set is disposed with one bounded `llmctl stop`. The next acquire evaluates the profile afresh. A session whose lease was released gets exit 3 from `heartbeat` and must `acquire` again. |
| Verdict `undetermined`, reason_code `stale_answer` | The lease registry changed (another session started, stopped, joined or released) between this acquire's capacity read and its plan, or between the plan and the start mark, `STALE_MAX` (3) times in a row | Round 7 freshness rule: a start is decided only on a capacity answer read after the last registry change (token = generation + sha256 of `leases.json`). A stale answer is read again; after 3 stale reads the acquire starts nothing and routes to the fallback. Retry later; it is a sign of heavy contention, not a fault. |
| `acquire` logs `candidate <p>: not started: the lease of <holder> on <q>, taken by this acquire, is gone` | With `JEV_PLACE_MAX` > 1, the lease this acquire took on its first start was released (or the set dropped) before the next start | Round 7: a further start needs the lease this acquire took; nothing more is started. Expected when a `release` runs concurrently. |
| `reap` logs `cleared the starting mark of <p> ...` and the set is not routed yet | The starter died (or its mark is older than `MARK_TTL`); round 7 sets the set's health to `pending` at the current observation counter (a floor) | The set is judged by the next observation that begins after the clear; an older capacity answer can never mark it gone. Run `status` or the next `acquire`. |
| `heartbeat` exits 3 | The holder holds no lease (released, reaped, released because its endpoint is gone, or never taken) | A lease is never assumed: route locally only after a new `acquire`. |
| `acquire` exits 2: `lease TTL ... is not greater than the re-evaluation cadence` | `--ttl` (or `JEV_LEASE_TTL`) is not greater than `JEV_REEVAL_CADENCE` (default 300 s) + `JEV_LLMCTL_TIMEOUT` (default 20 s) | A config error (§11.4.291(J)(1)): raise the TTL or lower the cadence. |
| `acquire` exits 5 with event `gateway_refused` | The gateway URL (from `LLMCTL_GATEWAY_URL`, the llmctl registry, or the default) is not `https://` or is malformed | Only `https://` is registered: the key `LLMCTL_API_KEY` never goes over plain HTTP. When no gateway is listed, or `llmctl decide status` fails, the default `https://127.0.0.1:8095` is applied and logged. |
| Log `placement record NOT written: the lease lock could not be taken ...` | Every one of `JEV_RECORD_RETRIES` (default 3) lock waits for the placement record expired | The record is never written without the lock; the next run writes a fresh one. |
| Log `lease held, start recorded late: ...`, exit 0 | `llmctl start` succeeded but its record step could not take the lock | The lease is in the registry since the start mark; no further candidate is started by that acquire; the set is routed at the next observation once the starter process is gone. |
| Verdict `undetermined`, reason `nproc_unlimited: RLIMIT_NPROC is unlimited ...` | `ulimit -u` is unlimited (llmctl reports `rlimit_soft` null) | Measured, not missing; whether an unlimited limit admits a start is an operator decision (§11.4.291(C), §11.4.66), so no start until then. `nproc_not_measured` means the headroom could not be read. |
| Verdict `undetermined`, reason `candidate list undetermined: llmctl decide capacity exit <n>` | The candidate list could not be read | Never read as "no candidate"; no local start. |
| `llmctl-onnx@decide-nli` is `failed` | Its start gate (`svc_hook.sh gate`) refused with exit 75 under memory pressure four times and hit the start limit (measured 2026-11-12 on the reference host) | This is an operator-enabled unit; the constitution does not restart it. `systemctl --user reset-failed llmctl-onnx@decide-nli` and start it by hand when pressure is low, if you want it. |

## Status

| Symptom | Cause | Action |
|---|---|---|
| `--json` prints `null` for a section and names a file on stderr | The file exists but is not valid JSON | Fix or remove it; re-run bootstrap to regenerate. |
| "requires jq or python3" (rc 2) | Neither tool is on PATH | Install one. |
| `mode_reason` is `base-url-unresolved`, `hosted-or-non-loopback-base-url(<source>)`, `detection-record-stale-or-undated`, `no-qualifying-local-llmctl-endpoint(...)`, `validation-skipped`, `invalid-profile-name` or `...;override-ignored(JEV_TEST!=1)` | respectively: no base URL anywhere (set a loopback `JEV_BASE_URL`); a hosted base in `<source>` = process env, env file, MCP entry or cache `endpoints[0]`; the record is older than `JEV_DETECTION_MAX_AGE` or has no numeric `generated_at` (re-run detection); no `local-llmctl` endpoint with id `llmctl-<profile>` and a loopback url; `--no-validate` was used; a dash-leading profile name; a test override set without `JEV_TEST=1` | Fix the named condition and re-run `bootstrap.sh --enforce` or `register.sh`. |
| Env file says `JEV_MODE=enforce` but `jev-status` says `Mode: shadow` | The effective mode is re-derived by `jev_effective_mode` (promoted type, local llmctl endpoint, loopback base URL, fresh `require-validated` PASS); one no longer holds. `mode_reason` in `--json` names it | Fix the named condition, then run `bootstrap.sh --enforce` (or `register.sh`) again; the next run rewrites the env file and MCP `env.JEV_MODE` accordingly. |
