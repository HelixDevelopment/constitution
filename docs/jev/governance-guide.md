# Jev Decision-Layer Governance Guide — operating under §11.4.279–§11.4.286

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-07 |
| Last modified | 2026-10-28T19:34:34Z |
| Status | active |
| Status summary | Operator-facing explanation of the Jev decision-layer mandate. Revision 2 corrects the tool surface against the claude_toolkit and llmctl sources. Revision 3 adds the §11.4.291 capacity-aware placement section. |
| Authority | Constitution §11.4.279–§11.4.286 (+ §11.4.231 as amended 2026-10-07). The canonical anchor texts in `Constitution.md` govern; this guide is operator-facing explanation, never a second source of rule text. |
| Scope | Universal (§11.4.17) — inherited by reference (§11.4.28/§11.4.177); every project-specific value below is consumer DATA per §11.4.35. |
| Issues | 3 integration gaps recorded under "Honest limitations" |
| Issues summary | Calibrated thresholds are not consumed by the toolkit gate; gate log rows are not calibratable; the pinned claude_toolkit commit predates the Jev scripts. |
| Fixed | Revision 2: bootstrap reads real llmctl/toolkit surfaces; stamp is byte-stable; pending stamp clears on completion. |
| Fixed summary | See `bootstrap-reference.md`, "Changes from revision 1". |
| Continuation | none |

Related: [bootstrap reference](bootstrap-reference.md) · [user manual](user-manual.md) · [FAQ](faq.md) · [troubleshooting](troubleshooting.md) · [diagrams](diagrams.md)

## Table of contents

- [Purpose](#purpose)
- [What the mandate requires of your project](#what-the-mandate-requires-of-your-project)
- [DATA declarations](#data-declarations-1135)
- [Providers and local instances](#providers-and-local-instances)
- [Wizard reference (summary)](#wizard-reference-summary)
- [Gate reference](#gate-reference)
- [Using a Jev API key (hosted) out of the box](#using-a-jev-api-key-hosted-out-of-the-box)
- [Live validation (2026-10-24)](#live-validation-2026-10-24)
- [Capacity-aware placement](#capacity-aware-placement-114291)
- [Calibration lifecycle](#calibration-lifecycle-1285)
- [Honest limitations](#honest-limitations-read-before-relying-on-the-layer)
- [See also](#see-also)

## Purpose

This guide tells the operator of an incorporating project what the Jev-class decision-layer mandate requires, which values the project must declare as DATA, how the bootstrap wizard and gates fit together, and — honestly — what the layer does NOT prove.

## What the mandate requires of your project

1. **Detect first (§11.4.279).** Before the first generative-LLM invocation of any work item, run decision-model detection (`llmctl decide status --json` + `claude-providers sync-jev`) and persist `jev-detection.json` to your evidence store. Zero endpoints is lawful ONLY with an explicit reasoned absence record — silent absence is a §7.1 bluff.
2. **Wire every detected agent (§11.4.280).** Each detected platform gets the artifacts its mechanics support: hooks (`jev-gate.sh`), MCP registration (`jev_mcp.py`), provider env exports, plugins where a plugin mechanism exists. Coverage gaps are recorded verbatim, never smoothed over.
3. **Run the bootstrap wizard on every constitution update (§11.4.281).** `scripts/jev/bootstrap.sh` is triggered by `scripts/post_update_hook.sh` — guarded, idempotent, deferrable. See [`bootstrap-reference.md`](bootstrap-reference.md).
4. **Use all detected capacity (§11.4.282).** Decision traffic distributes across all available endpoints/instances (local, LAN pins, hosted), bounded by per-profile `parallel` slots and §9/§12 host-safety headroom.
5. **Prove the token reduction (§11.4.283).** Extend your §11.4.141 BEFORE/AFTER harness with a decision-layer arm; pass = AFTER ≤ BEFORE against your declared reduction floor, with ≥1 decision per gated tool-call class in `decisions.jsonl`. `jev-stats.sh` numbers are ESTIMATES, never proof.
6. **Decisions before the ladder (§11.4.284).** Typed decisions (noul/choice/score) never reach a chat-model rung; decision endpoints never appear in chat/provider configurations.
7. **Calibrate before you enforce (§11.4.285).** Shadow-first; your main LLM labels deterministic samples; a question type enforces only after meeting the agreement floor and sample minimum.
8. **Submodules are the canonical install source (§11.4.286).** `submodules/llmctl` + `submodules/claude_toolkit`, pinned in `helix-deps.yaml`; managed-clone fallback at the same pinned refs when submodules were not recursed.

## DATA declarations (§11.4.35)

The constitution encodes policy; your project supplies these values as DATA (record them in your project's own governance file; absent declarations resolve to the defaults shown):

| Declaration | Default when absent | Meaning |
|---|---|---|
| Evidence directory | `<state>/evidence`, i.e. `~/.local/state/jev/evidence` (env `JEV_EVIDENCE_DIR` selects another; `JEV_DETECTION_FILE` selects the detection record alone) | Where `jev-detection.json`, thresholds, and harness artifacts live. Absolute and independent of the working directory: bootstrap, register, status, calibrate and the gates all resolve it through `scripts/jev/lib_decide.sh`. |
| Reduction floor | `AFTER ≤ BEFORE` (never an increase) | The §11.4.283 pass bar for the decision-layer harness arm. The §11.4.141 aggregate bar (AFTER ≤ 40% of BEFORE) is separate and remains in force. |
| Agreement floor | `0.90` (env `JEV_CALIBRATE_FLOOR`) | Per-question-type calibrated LLM-vs-Jev agreement required to enter enforce mode (§11.4.285(C)). |
| Sample minimum | `30` (env `JEV_CALIBRATE_MIN_SAMPLE`) | Minimum labeled shadow decisions per question type before promotion (§11.4.285(C)). |
| Calibration cadence | on demand (`jev-calibrate.sh --now`) | A scheduled cadence is consumer DATA; the bootstrap installs no scheduled entry. |
| Main-LLM alias | none (calibration cannot run; the layer stays in shadow) | The toolkit provider alias used to label calibration samples, at the §11.4.231 lightest-capable tier. Stored as `MAIN_LLM_ALIAS=` in `~/.config/jev/env`. |
| Keys file / llmctl host | — | Credentials and host for detection/provisioning (§11.4.279 Classification). Only variable NAMES are recorded anywhere in this layer. |

## Providers and local instances

Source of truth for the table: claude_toolkit `scripts/providers/jev.json` (commit `bfa667f` of the standalone checkout) and llmctl `docs/decide-gateway.md` / `docs/decision-models.md` (commit `f42bad6`).

| Endpoint | Base URL | Key variable NAME | Models | Priority |
|---|---|---|---|---|
| Local llmctl decide gateway | `https://127.0.0.1:8095` (HTTPS only, local CA) | `LLMCTL_API_KEY` | served profile ids and aliases `jev-latest`, `jev-1.13.0`, `jev-preview`, `llmctl-<profile>` | 10 (preferred) |
| LAN pins | user-declared in the `lan` list of `jev.json` (empty by default) | per pin | per pin | 20 |
| OpenRouter hosted | `https://openrouter.ai/api` | `OPENROUTER_API_KEY` | `typesafe/jev-1.13`, `jev-latest` | 30 |
| TypeSafe hosted | `https://api.typesafe.ai` | `TYPESAFE_API_KEY` | `jev-1.13.0`, `jev-latest` (the live server now resolves `jev-latest` to `jev-1.14.0`; `jev-1.13.0` is still served; the toolkit pin text is stale) | 40 |

- Hosted endpoints are detected from the key variable in the keys file (precedence `JEV_API_KEYS_FILE`, `CMA_KEYS_FILE`, `~/api_keys.sh`) and, since 2026-10-24, proven reachable by one minimal authenticated probe by bootstrap (see `docs/jev/bootstrap-reference.md`); the toolkit's own `sync-jev` makes no network call unless `CMA_JEV_LIVE=1`. `CMA_JEV_PREFER=<provider ids>` promotes ids to the front of the ranked cache.
- The local gateway serves **validated** llmctl decide profiles only. `decide-tiny` has protocol `jev-verdict` and no driver: it cannot serve gateway decisions yet and must not be counted as decision capacity (bootstrap excludes it). Profiles in the shipped catalog (llmctl `models/catalog.json`): `decide-tiny`, `decide-2b`, `decide`, `decide-pro`, `decide-max` (letter-logit readout on llama-server), `decide-nli` (ONNX encoder), and the native `systemone` profiles `decide-julia`, `decide-kev-08b`, `decide-kev-4b`, `decide-kev-9b`, `decide-laya`, `decide-lev`. The native profiles answer only when the gateway runs with `LLMCTL_DECIDE_NATIVE=1`; otherwise `503 not_ready`.
- **Kev and Laya** are therefore supported as llmctl native profiles (`decide-kev-*`, `decide-laya`). Their accuracy is recorded as **unverified** in llmctl's own documentation (no figure recorded for the upstream cards; llmctl ran golden sets for some, others "not run live").
- **Verdict and Strands profiles: UNKNOWN.** No catalog profile or document in llmctl `f42bad6` names either; this guide makes no claim about them.
- Gateway behaviour that bounds a consumer: end-to-end deadline `LLMCTL_DECIDE_TIMEOUT` (8 s default, raised to 120 s by the launcher when a CPU-placed llama decision instance is served), failed-auth throttling (`429`), `529 overloaded`, `422 readout_failed`. The toolkit gate's own curl timeout is `JEV_GATE_TIMEOUT` (2 s default), so a slow CPU engine makes the gate fall back (see limitations).
- Data egress: the gate sends the tool name and tool input (truncated to 12,000 characters) to the selected endpoint. With a hosted endpoint that content leaves the host. `decisions.jsonl` stores only a 16-hex-character hash of it. Choose a local or LAN endpoint when tool inputs must not leave the host.

## Wizard reference (summary)

`scripts/jev/bootstrap.sh` runs 7 stages — detect-tools, provision (llmctl + claude_toolkit), detect-models, install-per-agent, configure, calibrate-shadow, report — interactive on a TTY, automatable with `--non-interactive` + `JEV_BOOTSTRAP_*` env vars, deferrable with `--defer`. Installers, agent-home edits and model downloads each require explicit consent. Full reference: [`bootstrap-reference.md`](bootstrap-reference.md).

## Gate reference

| Gate | Asserts | Paired §1.1 mutation |
|---|---|---|
| `CM-JEV-DETECTION` | `jev-detection.json` exists in the evidence window, parses, schema-valid; absence is reasoned; llmctl/claude_toolkit provenance record (path, ref, source: submodule\|clone\|explicit\|unavailable); capacity section present (§11.4.282). | `cm_jev_detection_mutation_test.sh` fabricates a detection record with llmctl/endpoints absent → MUST FAIL. Fails an empty record that contradicts llmctl's registry (clause 7) and a hosted endpoint with a real key that is not proven reachable (clause 8). `--root <dir>` judges `<dir>/.jev/jev-detection.json`; `JEV_DETECTION_FILE` wins. |
| `CM-JEV-WIRING` | Per detected agent: hook entry, MCP registration, env exports in the launch path, coverage-gap notes; no decision endpoint in any chat-model config (§11.4.284(D)); `jev-thresholds.json` schema-valid when `JEV_MODE=enforce` (§11.4.285(E)). | `cm_jev_wiring_mutation_test.sh` removes one agent's hook block → MUST FAIL naming that agent. |
| `CM-JEV-TOKEN-REDUCTION` | BEFORE/AFTER artifacts exist, parse, differ only in the decision-layer arm, meet the declared floor; ≥1 decision per gated tool-call class; estimates labeled ESTIMATES. | `cm_jev_token_reduction_mutation_test.sh` swaps AFTER for an inflated copy of BEFORE → MUST FAIL. BLIND (rc 2) when no real BEFORE/AFTER pair is configured (`JEV_BEFORE`/`JEV_AFTER` or `<evidence dir>/before.jsonl`+`after.jsonl`); a decision row's class is `.class` else `.question`. |
| `CM-JEV-BOOTSTRAP-IDEMPOTENT` | Post-update hook contains the invocation block; two consecutive non-interactive runs produce identical resulting-state digests; `--defer` stamp semantics; submodule-absent clone fallback pinned. | `cm_jev_bootstrap_idempotent_mutation_test.sh` deletes the hook invocation block → MUST FAIL. |
| `CM-COVENANT-114-{279..286}-PROPAGATION` | Each anchor block-start appears exactly once per governance file, content-identical across the mirror set (§11.4.227(B)). Generated from data-pack rows — never hand-written (§11.4.251). | Paired mutation per propagation-gate convention. |

Runtime kill-switch: `JEV_GATE=off` governs ENFORCEMENT only — detection (§11.4.279) has no kill-switch. Each use is appended to `gate-off.log` and counted by `jev-stats.sh` and `jev-status.sh`.

## Using a Jev API key (hosted) out of the box

1. Put the key in the operator keys file as an exported variable, by the NAME in the provider pin: `export TYPESAFE_API_KEY='...'` in `~/api_keys.sh` (override the file with `JEV_API_KEYS_FILE`, or `CMA_KEYS_FILE`; precedence in that order), mode `0600`.
2. Run `scripts/jev/bootstrap.sh --non-interactive` (the post-update hook runs it only when a pull changes a Jev-layer file, so a key added later is picked up by the next run). The same run: the key is classified (placeholders count as absent, with a reason), the hosted endpoint is recorded with a real authenticated probe (HTTP class only), and `JEV_MODE=shadow` is in force.
3. Shadow versus enforce: shadow serves and logs decisions and blocks nothing; enforce needs a promoted question type, calibrated thresholds and (for any decision model that gates) a fresh `llmctl require-validated` PASS. `bootstrap.sh`, `register.sh` and `jev-status.sh` all call ONE function, `jev_effective_mode` (`scripts/jev/lib_decide.sh`), on every run: enforce only for a base URL that resolves and is loopback everywhere it is found (an unresolvable base is shadow, reason `base-url-unresolved`), a `local-llmctl` endpoint in the detection record, a PROMOTED type with a numeric threshold AND a `require-validated` PASS under `LLMCTL_VALIDATE_STRICT=1` for each decision profile; otherwise shadow with the reason on stderr / in `enforce-deferred` / in `jev-status --json` (`mode_reason`). A stored `enforce` is re-derived and rewritten (env file and MCP `env.JEV_MODE`) on every run, so it is downgraded the moment a condition stops holding; the enforce intent is then lost and `--enforce` is needed again. `jev-status` reports the EFFECTIVE mode (`mode`) and the stored text (`mode_stored`). `JEV_CONFIG_DIR` relocates the config directory (else `$JEV_HOME/.config/jev`, else `$HOME/.config/jev`, one shared derivation for every caller). The wiring gate (clause 6) checks only `promoted`, not `require-validated` (UNCONFIRMED gap, tracked). Hosted endpoints never enforce, so a hosted-only host stays in shadow even with `--enforce` and promoted thresholds. The `JEV_REQUIRE_VALIDATED_CMD` / `JEV_DECISION_PROFILES` overrides count only with `JEV_TEST=1` and are then recorded in the reason and in `jev-status`. Round 5: the three callers no longer supply their own base URL; the shared resolver reads it (env, env file, MCP entry, cache), an unresolvable base is shadow, the detection record must be fresh and its local endpoint must have id `llmctl-<profile>` and a loopback url, and thresholds must lie in (0,1]. UNCONFIRMED: that launched agents source `JEV_MODE` from the env file (nothing in the toolkit does).
4. Key material, stated exactly. This layer's own code (bootstrap, register, status, calibrate, the probe) reads a key at call time by variable NAME and never writes a key value into the detection record, the evidence, the env file or a backup. It does not make plaintext backups of any file it detects as holding key material (`jev_backup_once` refuses them and says so on stderr). Detection works by shape: by key name, by an argument that follows a key flag, and by a credential-shaped URL query (`?key=`, `&token=`, `access_token=`, `api_key=`, `secret=`, `password=`, `auth...=`); a secret stored in any other shape (for example a bare positional argument) is NOT detected, so keep other secrets out of agent configs this layer edits and keeps at most ONE backup (`<file>.prejev.<stamp>`, mode 0600) of any other file it edits. The claude_toolkit is different and is NOT controlled here: its `scripts/jev-setup.sh` (function `_jev_endpoint_env`, present at toolkit `d78c2dd` and later, absent at the pinned `1f6dad3`) sources the keys file and, as measured in the round-6 review (UNCONFIRMED by this change: not re-run against the toolkit here), writes the key VALUE as `TYPESAFE_API_KEY` / `JEV_API_KEY` into `<home>/.mcp.json` of every Claude home, into the Kimi `mcp.json`, and into a third agent configuration. Treat every agent configuration that toolkit wired as key-bearing: keep it out of version control, out of backups you copy elsewhere, and out of shared homes. This is a toolkit-side defect (it should write the variable NAME and let the runtime resolve it); it is tracked for upstream per §11.4.197 and is not fixed by this repository. Which files this layer inspects for a `jev` entry (base URL and mode): `<home>/.mcp.json`, `$HOME/.mcp.json`, `$HOME/.claude-*/.mcp.json`, `$HOME/.claude.json`, `$HOME/.claude-*/.claude.json`, both `$CLAUDE_CONFIG_DIR/.claude.json` and `$CLAUDE_CONFIG_DIR/.mcp.json`, `<home>/.kimi-code/mcp.json`, `$HOME/.kimi-code/mcp.json`, `<home>/mcp.json`. The OpenCode and Pi agent configurations are NOT scanned (explicit gap; UNCONFIRMED whether the toolkit writes a `jev` entry there). `cm_jev_detection` fails when a hosted endpoint with a real key is recorded as not reachable.

## Live validation (2026-10-24)

UNCONFIRMED (review round 1, finding 4): the figures below were reported from a 2026-10-24 run, but no raw files, record ids or producing commands for them are committed in this tree, so they are NOT evidence under §11.4.262 and are kept only as leads for a re-measurement. None of it is a claim about other hosts or models.

- UNCONFIRMED lead, local llmctl: `decide-laya` validate PASS 10/0/0, determinism 3/3; `vision` PASS 38/0/0; `decide-julia` validate FAIL 9/1/0 (model defect: the prompt "The number is 8" was answered odd; not usable); `decide-tiny` UNDETERMINED (protocol `jev-verdict` has no driver). Typed-decision determinism on laya: 3/3 identical. The `noul` type was unreliable on laya (maturity experimental, calibrated=false). Enforcement is not live.
- UNCONFIRMED lead, hosted (TypeSafe): 54 decisions (`jev-latest` and `jev-1.13.0` x yes/no, choice, score x 3 questions x 3 repeats), all HTTP 200 and all agreeing with the known answers; discrete answers identical across repeats; `jev-latest` showed numeric jitter (0.98/0.99); median latency about 170 ms; about 349 tokens per decision. Failure codes: 401 wrong key, 403 empty bearer, 422 malformed, 400 unknown model, unknown type or oversize. Timeout behaviour: UNCONFIRMED. The token-reduction proof was NOT produced (no BEFORE side exists). Shadow gate decisions logged: an rm-like command denied (0.96), a force-push-like command denied at confidence 0.30, `ls` allowed (0.05).
- Findings fixed after this run: externally started decide engines missed (G1), empty record contradicting llmctl (G2), report-stage gates judging a cwd-relative default (G3), token gate GREEN on bundled fixtures (G4), gateway `reachable` claimed from "running", ambient `LLMCTL_DIR` leaking into the test run, wiring gate reading the wrong env directory, hosted `reachable=null` making a GREEN detection vacuous, `--root` missing on `cm_jev_detection`, `.class` versus `.question` in `decisions.jsonl` (the gate now accepts `.class // .question`; the toolkit gate writes `.question` only).

## Capacity-aware placement (§11.4.291)

Added 2026-10-28. A local decision model runs only when the host's live load leaves room for it. The rule text is §11.4.291 in `Constitution.md`; this section explains what it means for an operator.

- **Verdict.** Before a start, before traffic goes to a local instance and at every re-evaluation, each decision profile gets one verdict: `fits`, `fits_with_reduced_threads` (memory fits but fewer CPUs than the profile's cap are left; the reported thread count is what is started) or `does_not_fit` (the names `llmctl capacity --json` uses), or `undetermined`, which the consumer derives when the capacity source gives no usable answer (any exit other than 0, 75 or 3, a timeout, unparseable output, a schema other than `llmctl.capacity/1`, a missing required field, an unknown profile, or an unmeasured `RLIMIT_NPROC` headroom). `undetermined` is never read as `fits`: no local model is started on it.
- **Host reserve.** The model never takes all memory, CPU or threads. The reserve composes rules that already exist (§12.6 memory ceiling, §12.12 thread headroom, §11.4.225 CPU throttle accounting, the §11.4.277(E)(3) start gate); §11.4.291 adds no new number.
- **Override of `undetermined`.** Only per host and profile, by a §11.4.271 waiver or a recorded operator attestation `override: "<id>"` in the placement entry (resolvable and unexpired). It never lifts `does_not_fit` or llmctl's own pressure gate (exit 75). A model the operator started may receive traffic under `undetermined`; that route is recorded and announced.
- **Capacity source.** The canonical source is `llmctl capacity --json` (schema `llmctl.capacity/1`; the contract table is in §11.4.291(C)): `profiles.<p>.verdict`, `threads`, `host` / `reserve` / `pressure` (the measurement), `llmctl.units[].status`, `fallback.recommended` (`local`, `cloud`, `none`) and `fallback.key_variable` (a variable NAME only). Exit 0 fits, 75 a named profile does not fit, 3 a running unit is degraded. The contract was read from an uncommitted llmctl 3.4.0 working tree and one run of it; it is not vendored. The vendored llmctl 3.3.2 has `llmctl decide capacity --json`; it is not purely static (its RAM budget is the smaller of live `MemAvailable` minus 4 GiB and 60% of `MemTotal` minus the reservations of running profiles, and it uses live free VRAM), but it has no PSI, no CPU load, no cgroup limit and no per-profile verdict, so on its own it never yields `fits`.
- **Fallback.** When no profile fits and a non-placeholder hosted key is present (found by variable NAME, never printed), the route is `cloud` and traffic goes to the hosted endpoint (llmctl's own key check is presence-only, so the placeholder check is still applied). Hosted endpoints never enforce, so enforced question types return to shadow. With no key, the route is `none`: the layer records why it has no endpoint and decisions escalate per §11.4.284(C).
- **You are told.** Every change of route prints a notice and writes a `placement` entry in `jev-detection.json` (profile, verdict, reason, inputs, reserve, route `local` / `cloud` / `none`, key variable name only, override id, whether the constitution started the model, lease, previous verdict).
- **On demand only.** Constitution automation may run `llmctl start` after a fitting verdict and `llmctl stop` for a model it started. It stops only on releasing the last lease. It never runs `enable` / `disable`, never creates a boot unit, never runs `switch` or an evicting `auto`, and bounds every llmctl call with a timeout. Starting llmctl at boot stays an operator choice.
- **Degradation.** While a model the sessions route to runs, placement is re-evaluated on a cadence; on degradation the route moves to the fallback first, in-flight requests drain for a bounded, declared time (unfinished ones are re-issued on the new route or escalated, and recorded), then the model is stopped if the constitution started it and this was the last lease.
- **Shared hosts.** Sessions and projects on one host share a profile through a per-user, host-level lease set: a model is stopped only when its last lease is released, dead holders' leases are reaped, operator-started models are never stopped. If the endpoint disappears, every session moves to the fallback with reason `endpoint_gone` and does not restart it in a loop.
- **Not yet built.** No producer of the `placement` record, no lease registry and none of the four mechanism gates (`OWED-GATE-165` to `OWED-GATE-168`) exist yet. Until a live capacity source exists the verdict is `undetermined`, so no local decision model is started by constitution automation; whether that interim effect is wanted is an open operator question.

## Calibration lifecycle (§11.4.285)

1. **Shadow.** The layer starts in `JEV_MODE=shadow`: every decision is appended to `$JEV_STATE_DIR/decisions.jsonl` (state hash only, never raw state); nothing is enforced.
2. **Sample.** On demand, `jev-calibrate.sh` takes a deterministic sample per question type (sorted by timestamp, every k-th row to reach the sample size; default 50, promotion floor 30).
3. **Label.** The project's main LLM (toolkit alias, lightest-capable tier per §11.4.231) labels each sampled decision from the question, its criteria and the recorded state text. The Jev answer is withheld from the labeler so it cannot anchor the label. Parse failures count as `label_error`, never guessed.
4. **Compare.** Agreement per question type + 0.1-wide confidence-bin calibration; recommended threshold = lowest bin whose empirical agreement ≥ floor.
5. **Promote or stay shadow.** Types meeting floor AND sample minimum promote to enforce (`jev-thresholds.json`, atomic write, previous version preserved as `jev-thresholds.<epoch>.json`); types below floor stay in shadow. Demotions revert to shadow loudly.
6. **Recalibrate on change.** Every constitution update (§11.4.281 hook) and every decision-model version change recalibrates affected types before their thresholds remain in force. (Policy text; the scripts do not detect a model-version change by themselves.)

## Honest limitations (read before relying on the layer)

- **Shadow-first means enforcement lags.** Until a question type earns its threshold, its decisions are advisory logs, not blocks.
- **Fail-open by default.** `jev-gate.sh` steps aside (asserts nothing, so the agent's normal permission flow applies) when the endpoint is unset, unreachable or times out, and logs `fallback`. `JEV_GATE_FAIL=closed` makes an unreachable endpoint deny. A deterministic pattern floor (for example `git push --force`, `| sh`) can still escalate to `ask` in enforce mode. Availability of enforcement is an ops property, not a gate guarantee.
- **Estimates vs measured proof.** `jev-stats.sh` savings are ESTIMATES (constants `JEV_EST_INPUT_TOKENS`, `JEV_EST_OUTPUT_TOKENS`); the ONLY compliant token-reduction evidence is the §11.4.283 measured BEFORE/AFTER arm.
- **opencode hook coverage gaps.** opencode plugin hooks do not intercept MCP-tool or subagent calls; the installation record states this verbatim (§11.4.280(C)).
- **Calibration needs question text and state text in `decisions.jsonl`.** At claude_toolkit `bfa667f` the gate logs `question: "gate"`, the answer, `risky_p`, `confidence` and a state hash — no criteria and no state text — so those rows are counted `skipped_uncalibratable` by `jev-calibrate.sh`. Calibration becomes possible once the toolkit logs `criteria` and `state_text` alongside `state_hash`. UNCONFIRMED whether a later toolkit commit does.
- **Calibrated thresholds are not consumed by the toolkit gate.** The gate reads `decisions.lock.json` (`ask_threshold`, `deny_threshold`, written by the toolkit's own `jev-calibrate.sh sweep`) and fixed defaults. A search of claude_toolkit `scripts/` and `docs/` at `bfa667f` finds no reference to `jev-thresholds.json`. `JEV_MODE=enforce` set by hand therefore enforces with the gate's own thresholds regardless of this layer's calibration. UNCONFIRMED whether any component translates between the two files.
- **Pinned toolkit predates the Jev scripts.** `helix-deps.yaml` pins claude_toolkit at `1f6dad3`; that commit contains no `scripts/jev-*` file (measured with `git ls-tree`). Bootstrap against that pin reports "agent wiring skipped: claude_toolkit unavailable" and leaves a pending stamp until the pin moves to a commit that ships them (the standalone checkout `bfa667f` does).
- **The local gateway is HTTPS with a local CA.** The toolkit gate passes `--cacert "$JEV_CA_FILE"` (the operator's environment only; a `ca_file` field inside the detection record is untrusted and is never used on a request that carries a key) and sends the bearer key only over `https://`; llmctl's own docs state that end-to-end handling of the scheme and CA by the toolkit "is not verified in this repository". This guide has not run it live either: UNCONFIRMED.

## See also

- [`bootstrap-reference.md`](bootstrap-reference.md) — stage-by-stage wizard reference, env-var table, deferral semantics.
- [`user-manual.md`](user-manual.md), [`faq.md`](faq.md), [`troubleshooting.md`](troubleshooting.md), [`diagrams.md`](diagrams.md).
- `Constitution.md` §11.4.279–§11.4.286, §11.4.231, §11.4.141, §11.4.35, §11.4.228, §11.4.164/§11.4.26/§11.4.32.
