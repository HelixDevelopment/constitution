# Jev Bootstrap Wizard Reference — `scripts/jev/bootstrap.sh` (§11.4.281)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-07 |
| Last modified | 2026-10-23T00:00:00Z |
| Status | active |
| Status summary | Operator reference for the 7-stage wizard, aligned with the script's actual stages, flags, env and exit codes. |
| Authority | Constitution §11.4.281 (bootstrap wizard + post-update auto-trigger), §11.4.286 (install mechanism), §11.4.285 (calibration entry). The anchor texts govern; this document is the operator reference. |
| Scope | Universal (§11.4.17) — all host/project specifics are flags, env vars, or consumer DATA (§11.4.35). |
| Issues | none open in this document |
| Issues summary | — |
| Fixed | Revision 2 corrected the stage list (revision 1 described a different 7-stage split than the script ran). |
| Fixed summary | See "Changes from revision 1". |
| Continuation | none |

Related: [governance guide](governance-guide.md) · [user manual](user-manual.md) · [troubleshooting](troubleshooting.md) · [diagrams](diagrams.md)

## Table of contents

- [Invocation](#invocation)
- [Exit codes](#exit-codes)
- [Consent boundaries](#consent-boundaries)
- [Stage-by-stage](#stage-by-stage)
- [Environment variables](#environment-variables)
- [Files written](#files-written)
- [Deferral semantics](#deferral-semantics)
- [Idempotency contract](#idempotency-contract)
- [Changes from revision 1](#changes-from-revision-1)

## Invocation

```
bootstrap.sh [--non-interactive] [--defer] [--enforce] [--yes] [--allow-clone]
             [--install-tools]
             [--agent <csv>|all] [--llmctl-ref <ref>] [--toolkit-ref <ref>]
             [--report-json PATH]
```

Interactive when attached to a terminal (prompts on stderr, answers read from `/dev/tty`); automatable with `--non-interactive` plus env overrides. The wizard runs once per invocation. Every stage prints `[jev-bootstrap N/7] <stage>: <result>` to stderr; `--report-json PATH` additionally appends one JSON object per stage.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Completed. Degraded states (no endpoints, wiring awaiting consent, toolkit unavailable) are reported on stderr and recorded in the pending stamp; they are not errors. |
| 2 | Cannot determine / cannot proceed: no TTY without `--non-interactive` (never hangs), usage error, or a hard prerequisite (`jq`) is absent. A 2 is never a pass. |
| 3 | Operator-required stop: a managed clone has local changes. Nothing is overwritten. |

## Consent boundaries

Nothing in this table happens without an explicit yes.

| Action | How consent is given |
|---|---|
| Provision: `git clone` / `fetch` / `checkout` of llmctl and claude_toolkit into `$JEV_BOOTSTRAP_HOME` (network, out-of-tree write) | `--allow-clone`, `--yes`, `JEV_BOOTSTRAP_ALLOW_CLONE=1`, `JEV_BOOTSTRAP_CONSENT=1`, or interactive `y`. Without it nothing touches the network: a tool not already present is recorded `source: unavailable` with a reason, the pending stamp says `provision requires consent`, and the exit code stays 0. The post-update hook therefore stays network-free by default. |
| Run the tools' own installers (llmctl `make install` links `bin/llmctl` into `$PREFIX/bin`; claude_toolkit `scripts/install.sh` links scripts into `~/.local/bin`, edits shell rc files, runs `npm install`, and may `git pull` a sibling checkout) | `--install-tools`, `JEV_BOOTSTRAP_INSTALL_TOOLS=1`, or interactive `y` |
| Edit agent configuration under the home (`claude_toolkit scripts/jev-setup.sh --agents … --yes`; backups `*.prejev.<timestamp>` are made first) | `--yes`, `JEV_BOOTSTRAP_CONSENT=1`, or interactive `y` |
| Download a decision profile (`llmctl models download <profile>`; network, verified by sha256) | `JEV_BOOTSTRAP_DOWNLOAD_PROFILE=<profile>` or interactive `y` |

## Stage-by-stage

### 1/7 detect-tools

Requires `jq` (JSON parsing). Without it the wizard writes a pending stamp (`missing-prerequisite:jq`) and exits 2. Records which of `jq curl git make` are present. Interactive only: asks whether to clone/fetch (network), whether to run the tool installers, and whether agent homes may be edited (all default N).

### 2/7 provision

For each of `llmctl` and `claude_toolkit`, in priority order: (a) `LLMCTL_DIR` / `CLAUDE_TOOLKIT_DIR` if set and a directory; (b) a non-empty `submodules/<tool>` checkout; (c) an existing managed clone in `$JEV_BOOTSTRAP_HOME/<tool>` (used as-is, with `ref_status: not-synced-no-consent`, unless clone consent is given, in which case it is fetched); (d) with clone consent only, a new managed clone from the `ssh_url` recorded in `helix-deps.yaml`. A managed clone with local changes stops the wizard (exit 3). A clone is checked out at the manifest `ref`; if that ref cannot be checked out the provenance says `pin-not-reachable` and the clone stays on its head (no silent claim of a pin). A tool that cannot be provisioned (no consent, failed clone, git absent) is recorded as `source: unavailable` with a non-empty `reason`, not as an error. A stage that ends with an unavailable tool (and an install-per-agent or calibration stage that fails) is stored in the stamp as `tainted-retry`, so the next run retries it instead of reporting `no-change`. Provenance per tool: `path`, `ref`, `source` (`explicit|submodule|clone|unavailable`), `installer`, `head`, `ref_status`.

### 3/7 detect-models

Reads, read-only: `llmctl decide status --json` (which decide profiles are running, whether the gateway runs), `llmctl decide capacity --json` (slots per instance) and the toolkit's endpoint cache (`$CMA_PROVIDERS_DIR/jev-endpoints.json`, refreshed first with `claude-providers sync-jev --quiet`). Writes `jev-detection.json` to the evidence store. A running decide profile becomes endpoint `llmctl-<profile>` (`source: local-llmctl`, `reachable` = the gateway is running). A cache entry becomes `source: toolkit-cache` with `reachable: null`, because the cache records resolution, not a probe. With zero endpoints the file carries an explicit `reason`. The stage digest includes the live llmctl status and the cache contents, so starting a model later makes the next run re-detect.

### 4/7 install-per-agent

Runs `claude_toolkit scripts/jev-setup.sh --check --agents <csv|all>` (read-only audit). If it is clean the stage reports `already-wired`. If not and consent is absent, the findings are printed, the stage reports `pending-consent` and the pending stamp says so. With consent it runs `jev-setup.sh --agents <csv|all> --yes`; a non-zero exit is reported as `failed` and left pending. If the toolkit checkout lacks `scripts/jev-setup.sh` the stage reports `skipped toolkit-unavailable`. The standalone fallback `skills/jev-decision-layer/register.sh` is NOT run by the wizard; run it by hand only on a host without the toolkit, and never against a home that `jev-setup.sh` manages (they write different files).

### 5/7 configure

Creates the `decisions.jsonl` scaffold and writes `~/.config/jev/env` with `JEV_MODE=<shadow|enforce>` if absent. `--enforce` without calibrated thresholds is downgraded to shadow and `enforce-deferred` is recorded.

### 6/7 calibrate-shadow

With `--enforce`, no thresholds yet, and `MAIN_LLM_ALIAS=` set in the env file, runs `scripts/jev/jev-calibrate.sh --now --alias <alias>`. Otherwise reports that shadow mode logs decisions and enforcement needs calibration.

### 7/7 report

Runs `cm_jev_detection`, `cm_jev_wiring` and `cm_jev_token_reduction` when present, in advisory mode (result printed, never blocks). `cm_jev_bootstrap_idempotent` is not run from here because it executes bootstrap; the log line says so. Then the wizard writes the stamp and either writes `bootstrap.pending` (with the accumulated reasons) or removes it.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `JEV_BOOTSTRAP_NON_INTERACTIVE` | unset | Same as `--non-interactive`. |
| `JEV_BOOTSTRAP_DEFER` | unset | Same as `--defer`. |
| `JEV_BOOTSTRAP_CONSENT` | unset | Same as `--yes`. |
| `JEV_BOOTSTRAP_ALLOW_CLONE` | unset | Same as `--allow-clone`. |
| `JEV_BOOTSTRAP_INSTALL_TOOLS` | unset | Same as `--install-tools`. |
| `JEV_BOOTSTRAP_DOWNLOAD_PROFILE` | unset | Profile to download when no endpoint exists and it fits `llmctl decide capacity`. |
| `JEV_BOOTSTRAP_MODE` | `shadow` | `shadow` or `enforce`; same as `--enforce` when `enforce`. |
| `JEV_BOOTSTRAP_AGENTS` | `all` | Same as `--agent`; a comma list of `claude,kimi,pi,opencode` or `all`. |
| `JEV_BOOTSTRAP_HOME` | `~/.local/share/helix` | Root for the managed-clone fallback. |
| `LLMCTL_DIR` / `CLAUDE_TOOLKIT_DIR` | unset | Explicit existing checkouts; highest provisioning priority. |
| `JEV_EVIDENCE_DIR` | `.jev` | Evidence store for `jev-detection.json`, thresholds, harness artifacts. |
| `JEV_STATE_DIR` | `~/.local/state/jev` | Runtime state: `decisions.jsonl`, stamp, pending file. |
| `JEV_CONFIG_DIR` | `~/.config/jev` | `env` file and `jev-thresholds.json`. |
| `CMA_PROVIDERS_DIR` | `~/.local/share/claude-multi-account/providers` | Where the toolkit writes `jev-endpoints.json`. |
| `JEV_CONSTITUTION_ROOT` | derived from the script location | Root used to find `helix-deps.yaml` and `submodules/`. |
| `JEV_NOW_EPOCH` | `date +%s` | Deterministic-clock seam for tests. |
| `JEV_CALIBRATE_MIN_SAMPLE` | `30` | Promotion floor per question type (§11.4.285(C)). |
| `JEV_CALIBRATE_FLOOR` | `0.90` | Agreement floor. |
| `JEV_CALIBRATE_ALIAS_CMD` | toolkit alias via `cma_run_provider` | Label command template (tests stub this). |
| `JEV_MODE` | `shadow` | Runtime mode read by hooks/MCP. |
| `JEV_GATE` | `on` | Runtime kill-switch for ENFORCEMENT only; detection has none. |
| `CONSTITUTION_JEV_HOOK` | `on` | Consumer-emergency opt-out of the post-update hook invocation. |

All of these hold names or non-secret settings. No variable in this layer carries a secret; key variables are referenced by NAME (`LLMCTL_API_KEY`, `OPENROUTER_API_KEY`, `TYPESAFE_API_KEY`).

## Files written

| File | Content |
|---|---|
| `$JEV_EVIDENCE_DIR/jev-detection.json` | Endpoints, absence reason, capacity, tool provenance (replaced atomically). |
| `$JEV_STATE_DIR/bootstrap.stamp` | Per-stage digests; keeps its first `created_at`; rewritten only when a digest changes. |
| `$JEV_STATE_DIR/bootstrap.pending` | Present while the bootstrap is deferred or incomplete; removed by a fully completed run. |
| `$JEV_STATE_DIR/tools.provenance.json` | Inner body of `tools{…}`. |
| `$JEV_STATE_DIR/decisions.jsonl` | Shadow log scaffold (appended by the gate; never truncated here). |
| `$JEV_STATE_DIR/enforce-deferred` | Present while `--enforce` was downgraded. |
| `$JEV_CONFIG_DIR/env` | `JEV_MODE=…` (and `MAIN_LLM_ALIAS=…` if the operator adds it). |

## Deferral semantics

- `--defer` writes `bootstrap.pending` and exits 0; `jev-status.sh` shows it. Deferral is bounded and logged: the pending state stays visible until a run completes with nothing outstanding, which removes the file.
- A run that completes but leaves work for the operator (consent not given, toolkit unavailable, a downloaded profile not yet started) also writes `bootstrap.pending` with the reasons and still exits 0.
- Post-update-hook opt-outs: `.jev/bootstrap.disabled` marker file (logged, never silent) and `CONSTITUTION_JEV_HOOK=off` for consumer emergencies. Any bootstrap failure inside the hook degrades to `--defer`.

## Idempotency contract

Every stage computes a digest of its inputs and compares it with `bootstrap.stamp`. A second run with unchanged inputs prints `no-change` for each stage and rewrites nothing: the stamp is byte-stable because it keeps its first `created_at` and carries no per-run timestamp. Successful runs are byte-identical; a run whose stage ended unavailable or failed is deliberately not cached. A run that changes the world converges in at most two runs: after consent-gated wiring succeeds, stage 4 re-evaluates once more (its audit output changed) and stage 7 follows; the third run is all `no-change`. The deterministic-clock seam `JEV_NOW_EPOCH` makes digests and detection files reproducible in tests.

## Detection record contract (producer side)

`jev-detection.json` as written by stage 3: `capacity.instances` and `capacity.decision_instances` are equal numbers (plus `parallel_total`); `tools.<t>.source` is one of `submodule|clone|explicit|unavailable` and `unavailable` always carries `reason`; `endpoints[].reachable` is `true|false|null` (`null` = not probed); an endpoint with a URL carries `url`; local endpoints add `reachable_basis: llmctl-status-claim` and `url_basis` (`llmctl-status-detail` or `llmctl-default-port`); toolkit-cache endpoints keep `reachable: null` with `reachable_basis: resolution-only`. The end-to-end test `tests/jev/test_detection_producer_gate_e2e.sh` runs the real wizard and then `scripts/gates/cm_jev_detection.sh` on its output.

## Changes from revision 1

Defects found while porting, all corrected in the scripts:

1. The revision-1 reference described one 7-stage split and the script ran another; this document now follows the script.
2. Local endpoint detection parsed `llmctl plan --json` as an array of `{id,model,parallel}`; the real `decision_instances` is an object keyed by profile name and is a capacity report ("nothing reserved"). Detection now uses `llmctl decide status --json` for what is running.
3. The toolkit cache was read from the wrong directory and with the wrong field names; it is `$CMA_PROVIDERS_DIR/jev-endpoints.json` with `provider_id/base_url/model/key_var`.
4. `llmctl download` does not exist; the command is `llmctl models download <profile>`, and the download is now consent-gated instead of automatic.
5. `jev-setup.sh --agent … --home …` passed a non-existent flag and swallowed the toolkit's refusal (it requires consent, exit 3) while logging "wired agent". Wiring now uses `--agents … --yes` with consent and reports the real exit code.
6. Tool installers ran automatically and silently; they are now consent-gated, and the toolkit installer path is `scripts/install.sh` (revision 1 looked for a top-level `install.sh`, which does not exist).
7. `bootstrap.stamp` carried a per-run `created_at`, so the "byte-stable" claim could not hold; it now keeps its first value.
8. `bootstrap.pending` was never removed after a successful run; it is now.
9. `declare -A` (bash 4 only) was replaced with temp files so the script parses on bash 3.2 (§11.4.67).
10. The python3 fallback JSON escaper appended a newline; the wizard now treats `jq` as a hard prerequisite rather than carrying a second parser.
11. The managed-clone URL was hardcoded to one organization; it now comes from `helix-deps.yaml` `ssh_url`.
12. A pinned ref that failed to check out was silently ignored; it is now recorded as `pin-not-reachable`.
13. The stage-3 digest ignored live endpoint state, so a model started later was never re-detected; it now includes it.
14. The double invocation described in the review brief (interactive then non-interactive) is not in `bootstrap.sh`. The script runs the wizard once. In `scripts/post_update_hook.sh` (snapshot) the TTY branch calls `bootstrap.sh || bootstrap.sh --defer` — the second call runs only if the first fails — and the non-TTY branch calls `bootstrap.sh --non-interactive || bootstrap.sh --defer`. Whether that is correct is the hook's decision; this file does not duplicate it.
