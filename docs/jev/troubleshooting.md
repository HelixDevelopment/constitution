# Jev Decision Layer — Troubleshooting

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-23 |
| Last modified | 2026-10-23T00:00:00Z |
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
- [Status](#status)

## Bootstrap

| Symptom | Cause | Action |
|---|---|---|
| Exits 2 at once, "refusing to hang" | No TTY and no `--non-interactive` | Re-run with `--non-interactive` or from a terminal. |
| Exits 2, "jq is a hard prerequisite" | `jq` not on PATH | Install `jq`, re-run. A pending stamp `missing-prerequisite:jq` was written. |
| Exits 3, "operator-required stop" | A managed clone under `$JEV_BOOTSTRAP_HOME` has local changes | Resolve it by hand (commit, stash or move it), re-run. Nothing was overwritten. |
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

## Status

| Symptom | Cause | Action |
|---|---|---|
| `--json` prints `null` for a section and names a file on stderr | The file exists but is not valid JSON | Fix or remove it; re-run bootstrap to regenerate. |
| "requires jq or python3" (rc 2) | Neither tool is on PATH | Install one. |
