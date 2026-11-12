# Jev Decision Layer — Troubleshooting

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-23 |
| Last modified | 2026-11-12T17:44:39Z |
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
| Decisions keep going to a hosted endpoint although a local model fits | The local gateway entry is absent from the endpoint cache | `bash scripts/jev/jev-place.sh status`; an `acquire` adds `llmctl-local` at priority 10. The toolkit's `claude-providers sync-jev` rewrites the cache and may drop that entry (integration point, owned by claude_toolkit). |
| Failover order looks wrong | The cache order (priority, lower first) is read by the claude_toolkit gate and MCP server; whether a failed call moves on to the next entry is the toolkit's behaviour, and the T4 run above showed a pinned session that did not | Inspect `~/.local/share/claude-multi-account/providers/jev-endpoints.json` and the gate rows (`jev-status.sh` "Endpoint health" counts each attempt). This repository writes the local entry only. |

## Placement

| Symptom | Cause | Action |
|---|---|---|
| `jev-place.sh acquire` exits 5, verdict `undetermined` | `llmctl capacity --json` answered outside the contract (wrong schema, missing field, timeout, unmeasured RLIMIT_NPROC headroom) | The reason is in `placement.json` and on stderr. Undetermined never starts a model. |
| Exits 5, `does_not_fit` | Not enough RAM/CPU with the host reserve kept, pressure high, or the unit is degraded | Wait or free resources; the route is `cloud` with a hosted key, else `none`. |
| Exits 4, `lease_lock_timeout` | Another session holds the placement lock | Retry; no lease was taken. |
| `release` exits 6, `stop_failed` | The last release's `llmctl stop` failed or ran past `JEV_LLMCTL_START_TIMEOUT` | The model may still run, so the lease set is kept (`constitution_started`, `stop_failed {at, rc}`) and the cache entry stays. The next `release` retries the stop once the stop mark is cleared (the stopper process has exited, or the mark is older than the stop timeout + 30 s); an `acquire` meanwhile joins the running model. |
| `placement.json` shows `event: start_failed` with `verdict: fits` | Capacity said the profile fits, but `llmctl start` failed | The verdict is what was measured; the event is what happened. See the next row for the measured cause. |
| Exits 5 with `llmctl start <p> failed rc=1 ... still starting after 20s ... never answered .../health` | The unit was started but its start gate or model load did not finish in llmctl's own wait (measured 2026-11-12 on the reference host at load average about 30 on 16 CPUs: the unit sat in `Starting` for about 83 s with a 9 MB memory peak, so the model never loaded) | `jev-place.sh` sends one bounded `llmctl stop <p>` for a profile it asked to start, so no unit is left running without a lease, and routes to `cloud`/`none`. The unit then shows `failed`; that record is left for the operator. Retry when the host is quieter. |
| `llmctl` warns that the unit file `changed on disk` and asks for `daemon-reload` | The unit file was rewritten outside this run (seen 2026-11-12) | The constitution never runs `daemon-reload`; the operator decides. |
| A decide unit was already running before `acquire` | Someone else started it | It is joined with `constitution_started=false`: it is never started again and the last release never stops it. A unit still `starting` is neither started nor claimed. |
| `llmctl-onnx@decide-nli` is `failed` | Its start gate (`svc_hook.sh gate`) refused with exit 75 under memory pressure four times and hit the start limit (measured 2026-11-12 on the reference host) | This is an operator-enabled unit; the constitution does not restart it. `systemctl --user reset-failed llmctl-onnx@decide-nli` and start it by hand when pressure is low, if you want it. |

## Status

| Symptom | Cause | Action |
|---|---|---|
| `--json` prints `null` for a section and names a file on stderr | The file exists but is not valid JSON | Fix or remove it; re-run bootstrap to regenerate. |
| "requires jq or python3" (rc 2) | Neither tool is on PATH | Install one. |
| `mode_reason` is `base-url-unresolved`, `hosted-or-non-loopback-base-url(<source>)`, `detection-record-stale-or-undated`, `no-qualifying-local-llmctl-endpoint(...)`, `validation-skipped`, `invalid-profile-name` or `...;override-ignored(JEV_TEST!=1)` | respectively: no base URL anywhere (set a loopback `JEV_BASE_URL`); a hosted base in `<source>` = process env, env file, MCP entry or cache `endpoints[0]`; the record is older than `JEV_DETECTION_MAX_AGE` or has no numeric `generated_at` (re-run detection); no `local-llmctl` endpoint with id `llmctl-<profile>` and a loopback url; `--no-validate` was used; a dash-leading profile name; a test override set without `JEV_TEST=1` | Fix the named condition and re-run `bootstrap.sh --enforce` or `register.sh`. |
| Env file says `JEV_MODE=enforce` but `jev-status` says `Mode: shadow` | The effective mode is re-derived by `jev_effective_mode` (promoted type, local llmctl endpoint, loopback base URL, fresh `require-validated` PASS); one no longer holds. `mode_reason` in `--json` names it | Fix the named condition, then run `bootstrap.sh --enforce` (or `register.sh`) again; the next run rewrites the env file and MCP `env.JEV_MODE` accordingly. |
