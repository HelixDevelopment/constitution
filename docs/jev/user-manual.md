# Jev Decision Layer — User Manual

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-23 |
| Last modified | 2026-10-23T00:00:00Z |
| Status | active |
| Status summary | Task-oriented operating manual: set up, run, read status, calibrate, switch endpoints, turn it off. |
| Authority | Constitution §11.4.279–§11.4.286. The canonical anchor texts and the scripts govern where this document and they disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
| Fixed summary | — |
| Continuation | none |

Related: [governance guide](governance-guide.md) · [bootstrap reference](bootstrap-reference.md) · [diagrams](diagrams.md)

## Table of contents

- [1. What you get](#1-what-you-get)
- [2. Prerequisites](#2-prerequisites)
- [3. First setup](#3-first-setup)
- [4. Choosing and adding endpoints](#4-choosing-and-adding-endpoints)
- [5. Reading status](#5-reading-status)
- [6. Shadow mode and enforce mode](#6-shadow-mode-and-enforce-mode)
- [7. Calibrating](#7-calibrating)
- [8. Routing and voting across several endpoints](#8-routing-and-voting-across-several-endpoints)
- [9. Using it from an agent](#9-using-it-from-an-agent)
- [10. Turning it off, and removing it](#10-turning-it-off-and-removing-it)
- [11. Where things live](#11-where-things-live)

## 1. What you get

A decision stage that answers typed questions (allow/ask/deny choice, yes/no probability) before a generative model is used. It is wired into each agent as a PreToolUse hook and an MCP server. It starts in shadow mode: it logs what it would have decided and blocks nothing. Architecture: [diagrams](diagrams.md#architecture).

## 2. Prerequisites

| Need | Why | Check |
|---|---|---|
| `jq` | the wizard and status script parse JSON | `command -v jq` |
| `git` | managed-clone fallback | `command -v git` |
| claude_toolkit checkout that contains `scripts/jev-setup.sh` | per-agent wiring, gate, MCP server | `ls <checkout>/scripts/jev-setup.sh` |
| llmctl checkout (for local models) | local decide gateway and profiles | `llmctl decide status --json` |
| A key variable for a hosted endpoint, only if you use one | `OPENROUTER_API_KEY` or `TYPESAFE_API_KEY` in your keys file | the NAME must be set; never paste the value anywhere |

UNKNOWN: which claude_toolkit commit your `helix-deps.yaml` pins ships the Jev scripts. At pin `1f6dad3` it does not (see the [governance guide](governance-guide.md#honest-limitations-read-before-relying-on-the-layer)).

## 3. First setup

```bash
# 1. See what the wizard would do. No network, no edits without consent.
bash scripts/jev/bootstrap.sh --non-interactive
#    (add --allow-clone to let it clone/fetch llmctl and claude_toolkit when submodules are absent)

# 2. Read the result.
bash scripts/jev/jev-status.sh

# 3. Apply agent wiring once you have read the audit lines (backups are made).
bash scripts/jev/bootstrap.sh --non-interactive --yes --agent claude
```

On a terminal, omit `--non-interactive` and answer the prompts. Both installers and agent-home edits default to "no". If you cannot run it now: `bash scripts/jev/bootstrap.sh --defer`; the pending state shows in `jev-status.sh`.

## 4. Choosing and adding endpoints

The toolkit ranks endpoints local gateway (priority 10), LAN pins (20), OpenRouter (30), TypeSafe (40). Run `claude-providers sync-jev` to refresh the ranking after changing keys or models; `CMA_JEV_PREFER=<ids>` forces an order.

### Local llmctl gateway (loopback)

```bash
llmctl decide capacity           # which profiles fit this host
llmctl models download decide-tiny   # network, sha256-verified (about 0.5 GiB)
llmctl start decide-tiny             # or: llmctl decide scale decide-tiny 1
llmctl decide serve                  # HTTPS gateway, default port 8095
llmctl decide serve --status
claude-providers sync-jev
```

- The gateway needs its bearer key and a local CA; the key's variable NAME is `LLMCTL_API_KEY`. `llmctl decide key show --yes-print` prints it deliberately — do not run that in scripts or logs.
- Native profiles (`decide-kev-*`, `decide-laya`, `decide-julia`, `decide-lev`) are served only when the gateway runs with `LLMCTL_DECIDE_NATIVE=1`.
- A CPU-only engine can take longer than the gate's 2-second curl timeout (`JEV_GATE_TIMEOUT`). Raise it, or accept that slow calls fall back (fail-open).
- Verdict and Strands profiles: UNKNOWN, not present in llmctl `f42bad6`.

### Hosted

Set the key in your keys file under `OPENROUTER_API_KEY` or `TYPESAFE_API_KEY`, then `claude-providers sync-jev`. Detection needs only the variable to be non-empty; no network call is made unless `CMA_JEV_LIVE=1`. Remember that the gate sends the tool name and input (up to 12,000 characters) to the endpoint.

### LAN

Add an entry to the `lan` list of the toolkit's `providers/jev.json` (or point `CMA_JEV_PINS_FILE` at your copy). The entry format is not documented in this repository: UNKNOWN beyond the `hosted` entries' shape.

## 5. Reading status

```bash
bash scripts/jev/jev-status.sh          # human sections
bash scripts/jev/jev-status.sh --json   # {version, detection, thresholds, bootstrap:{stamp,pending}, mode (effective), mode_stored, mode_reason, test_override}
bash scripts/jev/jev-status.sh --no-validate   # or JEV_STATUS_NO_VALIDATE=1: do NOT run llmctl require-validated; a stored enforce then reports mode unknown (reason validation-skipped)
```

Sections: Mode, Endpoints (as last recorded, not live), Tools (provenance), Thresholds, Evidence log (decision count, kill-switch uses), Bootstrap (stamp, pending and why). For savings estimates use the toolkit's `jev-stats.sh [--days N] [--json]`; those numbers are ESTIMATES.

## 6. Shadow mode and enforce mode

- Shadow (`JEV_MODE=shadow`, default): the gate asks the endpoint, logs, and passes everything through.
- Enforce (`JEV_MODE=enforce`): the gate emits allow/ask/deny. The bootstrap and `register.sh` write `enforce` only when a PROMOTED type, a FRESH detection record with a local llmctl endpoint (id `llmctl-<profile>`, loopback url), a base URL that resolves and is loopback in every place it is stored, and a fresh `require-validated` PASS all hold (re-checked on every run, so a stored `enforce` is downgraded when they stop holding); `jev-status` runs the REAL `llmctl require-validated` (up to 60 s per profile) unless `--no-validate`; no decide-* profile has ever been run against a real model, so enforcement is not claimed live; setting the variable by hand skips that check and the gate then uses its own thresholds (`JEV_GATE_THRESHOLD` 0.8 deny, `JEV_RISKY_THRESHOLD` 0.7 ask, or the toolkit's `decisions.lock.json`).
- Kill-switch: `JEV_GATE=off` passes every call through and records the use in `gate-off.log`.
- Fail-closed: `JEV_GATE_FAIL=closed` denies when the endpoint is unreachable. Default is fail-open.

## 7. Calibrating

```bash
# Add your main LLM alias to the env file once:
echo 'MAIN_LLM_ALIAS=<alias>' >> ~/.config/jev/env
bash scripts/jev/jev-calibrate.sh --dry-run      # report only, writes nothing
bash scripts/jev/jev-calibrate.sh --now --alias <alias>
```

Output: per question type, `n`, agreement, recommended threshold, promoted or not, with the reason. Thresholds are written atomically to `~/.config/jev/jev-thresholds.json` (mirrored to the evidence dir, `~/.local/state/jev/evidence` by default); the previous file is kept as `jev-thresholds.<epoch>.json`. Rows that lack question text, criteria and state text are counted as skipped and never labeled blind. Today's gate rows lack them; see the limitation in the governance guide. The labeling command can be replaced with `JEV_CALIBRATE_ALIAS_CMD`.

## 8. Routing and voting across several endpoints

Copy the toolkit's `scripts/providers/jev-routes.json.template` to a path you own and point `JEV_ROUTES_FILE` at it. Each route key is a `decision_type` you pass to `jev_ask`. Without `min_agreement` a route is ordered failover (first candidate that answers with enough confidence). With it, two candidates must give the same answer, each at least `min_confidence`; otherwise the result is marked `degraded:true`. See the [sequence diagram](diagrams.md#routing-and-consensus-sequence).

## 9. Using it from an agent

- MCP tools: `jev_ask`, `jev_models`, `jev_stats_summary`, `jev_recommend_tier` (advisory). There is no `jev_score` tool.
- The hook needs no action: it runs on tool calls the agent gates.
- Coverage gaps are real: opencode does not gate MCP-tool or subagent calls; pi has no verified hook mechanism.

## 10. Turning it off, and removing it

| Goal | Command |
|---|---|
| Pause enforcement for this session | `JEV_GATE=off` (logged) |
| Stay in shadow | `JEV_MODE=shadow` |
| Stop the post-update hook from running the wizard | create `.jev/bootstrap.disabled` (logged), or set `CONSTITUTION_JEV_HOOK=off` |
| Remove agent wiring | claude_toolkit `scripts/jev-setup.sh --uninstall` (deliberate, logged operator act; restores from the backups) |

## 11. Where things live

`~/.local/state/jev/` (decisions, stamp, pending, gate-off log) · `~/.config/jev/` (env, thresholds) · `~/.local/state/jev/evidence/` (detection record, thresholds mirror; `JEV_EVIDENCE_DIR` selects another place; never the current directory) · `~/.local/share/claude-multi-account/providers/jev-endpoints.json` (ranked cache) · `~/.local/share/helix/` (managed clones).
