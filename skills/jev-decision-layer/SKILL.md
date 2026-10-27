---
name: jev-decision-layer
description: >-
  Jev-class decision layer (§11.4.279–§11.4.286): offload typed decisions
  (noul/choice/score) to decision models through the systemone wire format
  (hosted TypeSafe or OpenRouter, or the local llmctl decide gateway) BEFORE any
  generative-LLM tier is consulted. Shadow-first, calibration-earned enforcement.
  Consult this skill whenever a judgment is expressible as a typed decision.
compatibility:
  # §11.4.228 closed vocabulary
  SUPPORTED:
    - claude-code      # PreToolUse hook (jev-gate.sh) + MCP jev registration
    - kimi             # config.toml [[hooks]] + MCP registration
    - pi               # package note + MCP registration (documented fallback)
    - opencode         # plugin hook + mcp entry — PARTIAL coverage, see limitations
---

# Jev decision layer

## What it is

A routing stage of small decision models (Jev class) behind the systemone wire
format (`POST /v1/systemone`). Typed judgments (allow/ask/deny choice, yes/no
probability, numeric score) are answered by a decision model in milliseconds
instead of by a generative LLM call. Endpoints, in the toolkit's default
priority order: the local llmctl decide gateway (HTTPS, default port 8095,
bearer key whose variable NAME is `LLMCTL_API_KEY`), LAN pins, OpenRouter, TypeSafe hosted.

## When you MUST consult it (§11.4.284 pre-ladder rule)

Before invoking any generative-LLM tier for a judgment that is expressible as a
typed decision, call the decision layer first:

- MCP server `jev` (declaration `mcp/jev-decisions.json`, implemented by
  claude_toolkit `scripts/jev_mcp.py`). Tools: `jev_ask` (choice when `options`
  are given, otherwise a yes/no probability; optional `decision_type` selects a
  route in `JEV_ROUTES_FILE` for failover or multi-candidate voting),
  `jev_models`, `jev_stats_summary`, and `jev_recommend_tier` (ADVISORY model-tier
  pick; never enforced). There is no `jev_score` tool in the current server;
  numeric scoring is available through the gateway's `score` question type, not
  through this MCP server.
- the wired `jev-gate.sh` PreToolUse hook (automatic on gated tool calls).

Only work that survives this stage — genuinely generative work — enters the
§11.4.231 model ladder. The ladder is unchanged; decision models are not a
rung and are never chat models.

## Modes

- **shadow** (default, `JEV_MODE=shadow`): decisions are logged to
  `decisions.jsonl` (state hash only, never raw state) and never enforced.
- **enforce**: only after calibration — a question type enters enforce mode
  when its LLM-labeled agreement meets the project floor (default 0.90) over
  the minimum sample (default 30), per `jev-thresholds.json` (§11.4.285).

## Status and proof

- `bash scripts/jev/jev-status.sh` (or the `/jev-status` action) — endpoints as
  last recorded, wiring, mode, thresholds, pending state.
- Token-reduction claims require the measured BEFORE/AFTER harness
  (§11.4.283); `jev-stats` figures are ESTIMATES.

## Honest limitations (never claim otherwise — §7.1)

- **opencode coverage gap**: the plugin hook intercepts direct tool calls only;
  MCP-tool calls and subagent calls bypass the gate on that platform.
- **fail-open by default**: if the decision endpoint is unreachable, the gate
  hook steps aside (no decision asserted) and logs `fallback`. `JEV_GATE_FAIL=closed`
  makes an unreachable endpoint deny instead. Absence of endpoints is lawful only
  with a reasoned `jev-detection.json` record (§11.4.279(B)).
- **advisory in shadow**: in `shadow` mode no decision blocks anything.
- **calibration inputs**: decisions logged by the gate today carry a hash, not the
  question text or state, so they cannot be calibrated until the logging schema
  records them (see `docs/jev/governance-guide.md`).
- **consent-gated provisioning**: `scripts/jev/bootstrap.sh` never clones, fetches or installs without consent (`--allow-clone`, `--yes`, `--install-tools`); the default run, including the post-update hook, is network-free and records what it could not do.
- Never disable gates silently; uninstall is a deliberate logged operator act
  (`jev-setup.sh --uninstall`).
