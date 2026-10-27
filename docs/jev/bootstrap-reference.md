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
| Edit agent configuration under the home (`claude_toolkit scripts/jev-setup.sh --agents … --yes`; the claude_toolkit makes its own backups; this repository's own edits keep at most one `*.prejev.<timestamp>` copy per file, mode 0600, and none for a file holding key material) | `--yes`, `JEV_BOOTSTRAP_CONSENT=1`, or interactive `y` |
| Download a decision profile (`llmctl models download <profile>`; network, verified by sha256) | `JEV_BOOTSTRAP_DOWNLOAD_PROFILE=<profile>` or interactive `y` |

## Stage-by-stage

### 1/7 detect-tools

Requires `jq` (JSON parsing). Without it the wizard writes a pending stamp (`missing-prerequisite:jq`) and exits 2. Records which of `jq curl git make` are present. Interactive only: asks whether to clone/fetch (network), whether to run the tool installers, and whether agent homes may be edited (all default N).

### 2/7 provision

For each of `llmctl` and `claude_toolkit`, in priority order: (a) `LLMCTL_DIR` / `CLAUDE_TOOLKIT_DIR` if set and a directory; (b) a non-empty `submodules/<tool>` checkout; (c) an existing managed clone in `$JEV_BOOTSTRAP_HOME/<tool>` (used as-is, with `ref_status: not-synced-no-consent`, unless clone consent is given, in which case it is fetched); (d) with clone consent only, a new managed clone from the `ssh_url` recorded in `helix-deps.yaml`. A managed clone with local changes stops the wizard (exit 3). A clone is checked out at the manifest `ref`; if that ref cannot be checked out the provenance says `pin-not-reachable` and the clone stays on its head (no silent claim of a pin). A tool that cannot be provisioned (no consent, failed clone, git absent) is recorded as `source: unavailable` with a non-empty `reason`, not as an error. A stage that ends with an unavailable tool (and an install-per-agent or calibration stage that fails) is stored in the stamp as `tainted-retry`, so the next run retries it instead of reporting `no-change`. Provenance per tool: `path`, `ref`, `source` (`explicit|submodule|clone|unavailable`), `installer`, `head`, `ref_status`.

### 3/7 detect-models

Reads, read-only: `llmctl decide status --json` (which decide profiles are running, whether the gateway runs), `llmctl decide capacity --json` (slots per instance) and the toolkit's endpoint cache (`$CMA_PROVIDERS_DIR/jev-endpoints.json`, refreshed first with `claude-providers sync-jev --quiet`). Writes `jev-detection.json` to the evidence store. A running decide profile becomes endpoint `llmctl-<profile>` (`source: local-llmctl`, `reachable` = the gateway is running). A cache entry becomes `source: toolkit-cache` with `reachable: null`, because the cache records resolution, not a probe. With zero endpoints the file carries an explicit `reason`. The stage digest includes the live llmctl status and the cache contents, so starting a model later makes the next run re-detect.

**Gateway URL and reachability (2026-10-24).** The local gateway URL is taken, in order, from a URL in `.gateway.detail`, llmctl's registry entry of kind `gateway`, `.gateway.base_url`, `LLMCTL_ENDPOINT`, `LLMCTL_DECIDE_PORT` (the two env names are carried over from the live-validation patch and are UNCONFIRMED against the llmctl docs), and only then llmctl's documented default `https://127.0.0.1:8095`. `reachable` is PROBED (`GET <url>/healthz`, CA from the registry's `ca_file` label or `LLMCTL_CACERT`): `reachable_basis` is `probe`, or `llmctl-status-not-running` (false, not probed) or `probe-unavailable` (no curl, null). "llmctl says running" is never recorded as reachable.

**Externally started decide engines.** llmctl's `.profiles[].running` means scheduler-managed. Decide services that llmctl's registry lists healthy with `labels.kind == decide` are also detected (`url_basis: llmctl-registry-health`), once per profile.

**No-driver profiles.** A profile whose `decision_instances.<p>.protocol` is `jev-verdict` (for example `decide-tiny`) has no driver yet, cannot serve gateway decisions, and is never recorded as an endpoint or counted in `capacity`; the detection `reason` names it.

**Hosted keys: use the key out of the box.** The pins file (`CMA_JEV_PINS_FILE`, else `<claude_toolkit>/scripts/providers/jev.json`; when neither is available the documented built-in defaults are used and `key_discovery.pins_source` says `builtin-default`, so key discovery never depends on the toolkit checkout) names the key variables (`TYPESAFE_API_KEY`, `OPENROUTER_API_KEY`, and `LLMCTL_API_KEY` for the local gateway). Each is read BY NAME inside a subshell: first the process environment, then the keys file, chosen by precedence `JEV_API_KEYS_FILE`, then `CMA_KEYS_FILE` (the claude_toolkit name), then `~/api_keys.sh`. A value shorter than 16 characters, a known dummy (`x`, `changeme`, `your-key-here`, `<...>` and similar) or one repeated character is a PLACEHOLDER and counts as absent, with an explicit reason in `key_discovery.vars[]`; the value is never printed or stored. A real key for a hosted pin (https only) yields an endpoint `hosted-<name>` (`source: environment` when the key came from the process environment, `source: api-keys-file` when it came from the keys file, `key_var` NAME, `url` from the pin) after ONE minimal authenticated probe (`POST <base_url><systemone_path>` with a single harmless `noul` question; the key goes to curl on stdin, never argv). Only the HTTP status class is recorded in `auth_status_class` (`2xx`, `401`, `403`, `other`, `timeout`); `reachable` is true when the server answered and false on timeout. Endpoints that the toolkit cache already lists with a `key_var` holding a real key are probed the same way, so `reachable=null` remains only for keyless or placeholder entries. `JEV_HOSTED_PROBE=0` disables probing (reachable stays null and `cm_jev_detection` clause 8 then fails while a real key is present). `key_discovery` always reports the keys file path, whether it exists (`keys_file_present`), its real mode and every variable NAME with its state. A keys file readable by group or world gives a warning (`chmod 600`) and `key_discovery.perms_warning: true`. This is the only network access of a default run, and it happens only when the operator has put a real key in place.

**Cache directory.** `claude-providers sync-jev` ignores `CMA_PROVIDERS_DIR` and writes under `$HOME/.local/share/claude-multi-account/providers`; bootstrap reads the newer of that file and `$CMA_PROVIDERS_DIR/jev-endpoints.json`.

### 4/7 install-per-agent

Runs `claude_toolkit scripts/jev-setup.sh --check --agents <csv|all>` (read-only audit). If it is clean the stage reports `already-wired`. If not and consent is absent, the findings are printed, the stage reports `pending-consent` and the pending stamp says so. With consent it runs `jev-setup.sh --agents <csv|all> --yes`; a non-zero exit is reported as `failed` and left pending. If the toolkit checkout lacks `scripts/jev-setup.sh` the stage reports `skipped toolkit-unavailable`. The standalone fallback `skills/jev-decision-layer/register.sh` is NOT run by the wizard; run it by hand only on a host without the toolkit, and never against a home that `jev-setup.sh` manages (they write different files).

### 5/7 configure

Creates the `decisions.jsonl` scaffold and writes `~/.config/jev/env` with `JEV_MODE=<shadow|enforce>` if absent. The mode is NOT written "if absent": on EVERY run it is re-derived by the shared `jev_effective_mode` (`scripts/jev/lib_decide.sh`, the same function `register.sh` and `jev-status.sh` call) and the env file is rewritten atomically when it differs, so a stored `enforce` is DOWNGRADED when its conditions stop holding (enforce intent is kept only while `JEV_MODE=enforce` is stored; after a downgrade `--enforce` is needed again). Enforce needs ALL of (round 5, review r4): enforce requested or stored; a base URL that RESOLVES and is loopback everywhere it is found (the single resolver `jev_base_verdict` reads the process `JEV_BASE_URL`, the env file `JEV_BASE_URL=`, the MCP entry `env.JEV_BASE_URL` and the ranked cache `endpoints[0].base_url`; ANY non-loopback value, or NO value at all, is shadow with reason `hosted-or-non-loopback-base-url(<source>)` or `base-url-unresolved`: fail closed, an empty base is never treated as loopback); a detection record that is FRESH (`generated_at` numeric, not more than one hour in the future, age at most `JEV_DETECTION_MAX_AGE`, default 604800 s; the clock and age knobs `JEV_NOW_EPOCH` / `JEV_DETECTION_MAX_AGE` are honoured ONLY with `JEV_TEST=1`, otherwise ignored and the reason carries `;override-ignored(JEV_TEST!=1)`; otherwise `detection-record-stale-or-undated`) with at least one QUALIFYING local endpoint (source `local-llmctl`, id `llmctl-<profile>` with a profile name matching `^[A-Za-z0-9][A-Za-z0-9._-]*$`, and a LOOPBACK `url`; an endpoint with any other id or a non-loopback url is ignored, so `https://evil.example` never enforces; none left gives `no-qualifying-local-llmctl-endpoint(...)`); at least one PROMOTED per-type threshold (`promoted == true` and a numeric `threshold` in (0,1]) in `$JEV_CONFIG_DIR` or `$JEV_EVIDENCE_DIR`; and a fresh `LLMCTL_VALIDATE_STRICT=1 llmctl require-validated <profile>` PASS (up to 60 s each) for every qualifying profile. A dash-leading profile name is refused (`invalid-profile-name`) so it can never be read as an option. MEASURED (round 6, pinned llmctl f42bad6, `lib/validate.sh`): `require-validated` takes EXACTLY ONE argument; `llmctl require-validated -- bogus-x` prints `usage: llmctl require-validated <profile>` and exits 2, while `llmctl require-validated bogus-x` reaches the profile lookup (`unknown profile: bogus-x`, exit 2). The earlier `--` form could therefore never produce a PASS and is gone. `JEV_SKIP_VALIDATION=1` (used by `jev-status.sh --no-validate`) never yields enforce: the result is shadow with reason `validation-skipped`. Otherwise the mode is shadow and `enforce-deferred` records the reason. The `JEV_REQUIRE_VALIDATED_CMD` and `JEV_DECISION_PROFILES` overrides are honoured ONLY with `JEV_TEST=1` (tests); then the reason carries `;test-override(JEV_TEST=1)` (and `jev-status --json` has `test_override: true` plus a WARNING line); without `JEV_TEST=1` they are ignored and the reason carries `;override-ignored(JEV_TEST!=1)`. UNCONFIRMED: launched agents read `JEV_MODE` from `~/.config/jev/env`; nothing in the claude_toolkit sources that file into an agent's environment, so the env-file text is a record, and the MCP entry `env.JEV_MODE` is the only value an agent is known to receive. A freshly detected hosted key therefore runs in SHADOW immediately: decisions are served and logged, nothing is blocked.

### 6/7 calibrate-shadow

With `--enforce`, no thresholds yet, and `MAIN_LLM_ALIAS=` set in the env file, runs `scripts/jev/jev-calibrate.sh --now --alias <alias>`. Otherwise reports that shadow mode logs decisions and enforcement needs calibration.

### 7/7 report

Runs `cm_jev_detection`, `cm_jev_wiring` and `cm_jev_token_reduction` when present, in advisory mode (never blocks), against THIS run's detection file (`JEV_DETECTION_FILE`), with `scripts/jev/jev-probe.sh` as the replayable probe. Each result is printed truthfully: `PASS`, `BLIND` (rc 2: no verdict possible, for example no real BEFORE/AFTER pair for the token gate) or `FAIL rc=N` with the first failing line. `cm_jev_bootstrap_idempotent` is not run from here because it executes bootstrap; the log line says so. Then the wizard writes the stamp and either writes `bootstrap.pending` (with the accumulated reasons) or removes it.

## Time limits and rerunning a recorded gate

The external calls this wizard and the detection gate make carry timeouts (not every possible step is claimed bounded; provisioning `git clone`/`fetch` is consent-gated and its bound is UNCONFIRMED): sourcing the keys file by `JEV_KEYS_FILE_TIMEOUT` (default 5 s; a timeout reads as an absent key with the reason), the detection gate's `llmctl decide status`/`capacity` calls by `JEV_TOOL_TIMEOUT` (a timeout is a NOTE, never a pass), `llmctl`/`claude-providers` calls by `JEV_TOOL_TIMEOUT` (default 30 s; a model download by `JEV_DOWNLOAD_TIMEOUT`, 1800 s), each report-stage gate by `JEV_GATE_TIMEOUT` (default 60 s, reported as `TIMEOUT`), probes by `JEV_PROBE_TIMEOUT` (curl `--max-time`). A timed-out tool is named in the log and in the detection `reason`; bootstrap continues. The wiring gate walks only the agent config homes (`~/.claude`, `~/.kimi-code`, `~/.pi`, `~/.config/opencode`, the jev config dir), at most 4 levels deep, never the whole `$HOME`.

To reproduce the report-stage result of a recorded gate exactly as bootstrap ran it (the detection gate needs the replayable probe, otherwise it is RED by design):

```
JEV_PROBE_CMD=<constitution>/scripts/jev/jev-probe.sh JEV_DETECTION_FILE=<evidence dir>/jev-detection.json JEV_CONFIG_DIR=<config dir> JEV_EVIDENCE_DIR=<evidence dir> bash <constitution>/scripts/gates/cm_jev_detection.sh
```

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
| `JEV_EVIDENCE_DIR` | `<state>/evidence` (`~/.local/state/jev/evidence`) | Evidence store for `jev-detection.json`, thresholds, harness artifacts. Selects the detection record (`JEV_DETECTION_FILE` overrides that one file). Absolute; never the working directory. |
| `JEV_STATE_DIR` | `~/.local/state/jev` | Runtime state: `decisions.jsonl`, stamp, pending file. |
| `JEV_CONFIG_DIR` | `~/.config/jev` | `env` file and `jev-thresholds.json`. |
| `CMA_PROVIDERS_DIR` | `~/.local/share/claude-multi-account/providers` | Adds ONE cache candidate to read; the toolkit itself always writes under `$HOME/.local/share/claude-multi-account/providers`, which is always read too. |
| `JEV_CONSTITUTION_ROOT` | derived from the script location | Root used to find `helix-deps.yaml` and `submodules/`. |
| `JEV_NOW_EPOCH` | `date +%s` | Deterministic-clock seam for tests: honoured ONLY with `JEV_TEST=1` in bootstrap, calibrate, register and the resolver alike; otherwise ignored. |
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

## Key-send allowlist (provider pins) and the `refused` class

A key is sent only to an `https` URL whose origin AND key-variable name match a provider pin (`JEV_PINS_FILE`, else `CMA_JEV_PINS_FILE`, else the claude_toolkit `scripts/providers/jev.json`, else the builtin `typesafe` and `openrouter` rows), with the URL path at or below the pin's base path. Userinfo, queries, fragments, `..` segments, plain `http` and any unpinned host are refused: the probe prints `refused`, exits 2 and starts no `curl`; the bootstrap records `auth_status_class=refused` with `reachable=null`. `curl` runs with `--proto =https --proto-redir =https`. Further rules (review round 2): percent-encoded dot, slash, backslash and control segments (`%2e`, `%2f`, `%5c`, `%00`-`%1f`, any case) are refused; an explicit `:443` equals the pinned origin; when several pins share one origin, any pin whose key variable and base path both match allows the request. **CA trust:** a request that carries a key uses system trust, or the file named by the operator's `JEV_CA_FILE` environment variable; the detection record's per-endpoint `ca_file` is UNTRUSTED input and is never passed to `--cacert` on a keyed request (it is honoured only by the unkeyed local `llmctl-*` `/healthz` probe, where no key travels). **Unkeyed probes (review round 3):** `jev-probe.sh` performs a plain GET (with `--proto =http,https`) only when the URL's host is loopback by an anchored authority parse (`jev_url_host_class`: userinfo, backslash, `%`, whitespace and control characters, and a port outside 1..65535 make a URL `invalid`; `[` `]` are allowed because `[::1]` is a valid loopback host, and `{ } ..;` are rejected only by `_jev_split_url` on the KEYED path, not by `jev_url_host_class`; so `http://127.0.0.1:80@evil.example/`, `http://[::1]@evil.example/` and `http://localhost:1@evil.example/` are refused) or when its origin is a provider pin. The record's own `id` (`llmctl-*`) is NOT trusted to widen that; any other record URL exits 2 without starting `curl`. A LAN (non-loopback) llmctl endpoint is therefore no longer probed unkeyed. Every `curl` call starts with `-q` (no `.curlrc`) and carries `--globoff`. **Pins:** when bootstrap falls back to the builtin pins it unsets `JEV_PINS_FILE` and `CMA_JEV_PINS_FILE`, so a child never sees an allowlist different from bootstrap's own. **Registry classification:** the detection gate and bootstrap share `scripts/jev/lib_decide.sh`; a registry service is classified by `labels.profile`, else its name, and a `jev-verdict` profile is never usable capacity.


**Round 6 (review r5).** One config-dir derivation (`jev_config_dir`: `JEV_CONFIG_DIR`, else `$JEV_HOME/.config/jev`, else `$HOME/.config/jev`) is used by `register.sh`, `bootstrap.sh`, `jev-status.sh`, `jev-calibrate.sh` and the resolver. Env files are read like a shell sources them: the LAST assignment wins, an optional `export ` is accepted, one level of quotes is stripped, and for `JEV_BASE_URL` ANY non-loopback occurrence, or a value needing shell expansion, gives shadow. The resolver also reads the toolkit MCP locations (`$JEV_HOME/.mcp.json`, `$HOME/.mcp.json`, `$HOME/.claude-*/.mcp.json`, `~/.claude.json`), read-only; any hosted URL there gives shadow (`...(mcp-entry)`), and an unparseable file with no readable URL fails closed (`...(mcp-unparseable)`). Stage 5 rewrites the MCP `env.JEV_MODE` of the primary `.mcp.json` jev entry together with the env file; `jev-status` reports `mcp_mode_mismatch`.

**Round 7 (review r6, structural).** ONE resolver, `scripts/jev/lib_decide.sh`, derives every path: `jev_home`, `jev_state_dir`, `jev_config_dir`, `jev_evidence_dir` (default `<state>/evidence`, absolute), `jev_detection_file`, `jev_thresholds_candidates`, `jev_decisions_file`, `jev_bootstrap_home`, `jev_toolkit_dir`, `jev_providers_dir`, `jev_aliases_file`, `jev_default_cache_file`. bootstrap, register, status, calibrate and the `cm_jev_*` gates call it and derive nothing themselves; `tests/jev/test_review_fixes_r6.sh` scans for any remaining independent derivation (a deliberate fixture layout carries a `# jev-path-ok: <reason>` marker). The old behaviour (evidence under the current directory, `.jev/`) is gone: a run from another directory used to see a different detection record. Stage 5 rewrites `JEV_MODE` in EVERY `jev` entry of the covered MCP file set (see the governance guide, item 4 of the key-handling section, for the exact list and the OpenCode/Pi gap) and writes through the resolved link target, so a symlinked file stays a symlink. Env-file and MCP files are read for every `JEV_BASE_URL=` occurrence (including `declare -x`, `A=1; JEV_BASE_URL=` and commented lines); an unparseable cache or MCP file fails closed; `TYPESAFE_BASE_URL` is read like `JEV_BASE_URL`. `register.sh` refuses a value containing shell-active characters (`;`, `$(`, backquote, spaces) for the home, toolkit, base URL, model and CA-file inputs.
