# Jev Decision-Layer Governance Guide — operating under §11.4.279–§11.4.286

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-07 |
| Last modified | 2026-10-23T00:00:00Z |
| Status | active |
| Status summary | Operator-facing explanation of the Jev decision-layer mandate. Revision 2 corrects the tool surface against the claude_toolkit and llmctl sources. |
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
| Evidence directory | `.jev/` (env `JEV_EVIDENCE_DIR`) | Where `jev-detection.json`, thresholds, and harness artifacts live. |
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
| TypeSafe hosted | `https://api.typesafe.ai` | `TYPESAFE_API_KEY` | `jev-1.13.0`, `jev-latest` | 40 |

- Hosted endpoints are detected from the PRESENCE of the key variable in the keys file; no network call is made unless `CMA_JEV_LIVE=1`. `CMA_JEV_PREFER=<provider ids>` promotes ids to the front of the ranked cache.
- The local gateway serves **validated** llmctl decide profiles only. Profiles in the shipped catalog (llmctl `models/catalog.json`): `decide-tiny`, `decide-2b`, `decide`, `decide-pro`, `decide-max` (letter-logit readout on llama-server), `decide-nli` (ONNX encoder), and the native `systemone` profiles `decide-julia`, `decide-kev-08b`, `decide-kev-4b`, `decide-kev-9b`, `decide-laya`, `decide-lev`. The native profiles answer only when the gateway runs with `LLMCTL_DECIDE_NATIVE=1`; otherwise `503 not_ready`.
- **Kev and Laya** are therefore supported as llmctl native profiles (`decide-kev-*`, `decide-laya`). Their accuracy is recorded as **unverified** in llmctl's own documentation (no figure recorded for the upstream cards; llmctl ran golden sets for some, others "not run live").
- **Verdict and Strands profiles: UNKNOWN.** No catalog profile or document in llmctl `f42bad6` names either; this guide makes no claim about them.
- Gateway behaviour that bounds a consumer: end-to-end deadline `LLMCTL_DECIDE_TIMEOUT` (8 s default, raised to 120 s by the launcher when a CPU-placed llama decision instance is served), failed-auth throttling (`429`), `529 overloaded`, `422 readout_failed`. The toolkit gate's own curl timeout is `JEV_GATE_TIMEOUT` (2 s default), so a slow CPU engine makes the gate fall back (see limitations).
- Data egress: the gate sends the tool name and tool input (truncated to 12,000 characters) to the selected endpoint. With a hosted endpoint that content leaves the host. `decisions.jsonl` stores only a 16-hex-character hash of it. Choose a local or LAN endpoint when tool inputs must not leave the host.

## Wizard reference (summary)

`scripts/jev/bootstrap.sh` runs 7 stages — detect-tools, provision (llmctl + claude_toolkit), detect-models, install-per-agent, configure, calibrate-shadow, report — interactive on a TTY, automatable with `--non-interactive` + `JEV_BOOTSTRAP_*` env vars, deferrable with `--defer`. Installers, agent-home edits and model downloads each require explicit consent. Full reference: [`bootstrap-reference.md`](bootstrap-reference.md).

## Gate reference

| Gate | Asserts | Paired §1.1 mutation |
|---|---|---|
| `CM-JEV-DETECTION` | `jev-detection.json` exists in the evidence window, parses, schema-valid; absence is reasoned; llmctl/claude_toolkit provenance record (path, ref, source: submodule\|clone\|explicit\|unavailable); capacity section present (§11.4.282). | `cm_jev_detection_mutation_test.sh` fabricates a detection record with llmctl/endpoints absent → MUST FAIL. |
| `CM-JEV-WIRING` | Per detected agent: hook entry, MCP registration, env exports in the launch path, coverage-gap notes; no decision endpoint in any chat-model config (§11.4.284(D)); `jev-thresholds.json` schema-valid when `JEV_MODE=enforce` (§11.4.285(E)). | `cm_jev_wiring_mutation_test.sh` removes one agent's hook block → MUST FAIL naming that agent. |
| `CM-JEV-TOKEN-REDUCTION` | BEFORE/AFTER artifacts exist, parse, differ only in the decision-layer arm, meet the declared floor; ≥1 decision per gated tool-call class; estimates labeled ESTIMATES. | `cm_jev_token_reduction_mutation_test.sh` swaps AFTER for an inflated copy of BEFORE → MUST FAIL. |
| `CM-JEV-BOOTSTRAP-IDEMPOTENT` | Post-update hook contains the invocation block; two consecutive non-interactive runs produce identical resulting-state digests; `--defer` stamp semantics; submodule-absent clone fallback pinned. | `cm_jev_bootstrap_idempotent_mutation_test.sh` deletes the hook invocation block → MUST FAIL. |
| `CM-COVENANT-114-{279..286}-PROPAGATION` | Each anchor block-start appears exactly once per governance file, content-identical across the mirror set (§11.4.227(B)). Generated from data-pack rows — never hand-written (§11.4.251). | Paired mutation per propagation-gate convention. |

Runtime kill-switch: `JEV_GATE=off` governs ENFORCEMENT only — detection (§11.4.279) has no kill-switch. Each use is appended to `gate-off.log` and counted by `jev-stats.sh` and `jev-status.sh`.

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
- **The local gateway is HTTPS with a local CA.** The toolkit gate passes `--cacert "$JEV_CA_FILE"` and sends the bearer key only over `https://`; llmctl's own docs state that end-to-end handling of the scheme and CA by the toolkit "is not verified in this repository". This guide has not run it live either: UNCONFIRMED.

## See also

- [`bootstrap-reference.md`](bootstrap-reference.md) — stage-by-stage wizard reference, env-var table, deferral semantics.
- [`user-manual.md`](user-manual.md), [`faq.md`](faq.md), [`troubleshooting.md`](troubleshooting.md), [`diagrams.md`](diagrams.md).
- `Constitution.md` §11.4.279–§11.4.286, §11.4.231, §11.4.141, §11.4.35, §11.4.228, §11.4.164/§11.4.26/§11.4.32.
