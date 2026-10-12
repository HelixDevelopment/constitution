---
name: label-sync
description: 'Use whenever you dispatch an Agent/Task/subagent, start or name a work stream, or refer to a track/session/agent to the operator — you MUST prefix it with the LIVE §11.4.182 label `(T<N>/<branch> - <alias> - <model> - <effort>)` taken from the label bus (`labelctl label` or the `label_get` MCP tool), never typed from memory. Also use when the operator switches the Claude alias/model/effort, asks "which alias/model is this session on", sees a stale/wrong/`?` label, or asks how labels stay in sync across Claude Code, Codex, Gemini CLI, Qwen Code, OpenCode, Crush, Kimi and Aider.'
version: 1.0.0
---

# label-sync — always-live work-stream labels (§11.4.182)

Every stream, agent, subagent, flow, shell and command shows the same label:

```
(T<N>/<branch> - <alias> - <model> - <effort>)        e.g. (T3/feature/label-sync - claude2 - sonnet - xhigh)
```

The label is **data on a bus**, not text you remember. When the operator switches
the Claude alias, every follower's label changes in the same write. A label you
typed an hour ago may now be wrong. **Read it again each time.**

## The one rule

Before you **dispatch an Agent/Task** or **mention a track/stream/agent to the
operator**, fetch the current label and put it first:

```bash
bash constitution/scripts/label-sync/labelctl.sh label "$LABEL_SYNC_ENTITY_ID"   # an entity you know
bash constitution/scripts/multitrack/track_branch_label.sh                       # this checkout + live session (canonical labeler)
```

or, when the `label-sync` MCP server is attached, call **`label_get`** (by `id`
or by Claude `session_id`) and use the returned `label` verbatim:

```
Agent(description="(T3/feature/label-sync - claude2 - sonnet - xhigh) fix the parser tests", …)
```

Rules that follow from this:

1. **Verbatim.** Do not shorten, reorder, or "fix" a field. A `?` is an honest
   unknown (nothing was derived) — keep it; never replace it with a guess
   (§11.4.6). Report a persistent `?` instead (see troubleshooting).
2. **Fresh.** Re-read after any alias/model/effort change, after resuming a
   session, and before every dispatch in a long conversation.
3. **Prefix, don't paraphrase.** The label is the *first* characters of an
   Agent/Task description and of every operator-facing line that names a stream.
4. **Never invent an entity.** Only register what you really are (see below).

## Reading the bus

| Want | Command / tool |
|---|---|
| my label | `label_get {session_id}` · `labelctl.sh get --id ID --json` |
| everything live | `label_list {}` · `labelctl.sh list --text` |
| only one alias | `label_list {alias:"claude2"}` |
| the operator's active alias | `label_active {}` · `labelctl.sh snapshot \| jq .active` |
| watch live | `labelctl.sh watch --text` (poll or `--socket`) |

`labelctl.sh` builds its Go binary on first use; no manual build.
Details and schemas: `docs/label-sync/CONTRACT.md`. MCP tools: `docs/label-sync/MCP.md`.

## Switching the alias (operator intent)

When the operator says "switch to claude2 / use opus xhigh":

```bash
bash constitution/scripts/label-sync/labelctl.sh switch-alias --alias claude2 --model opus --effort xhigh
```

or MCP `label_switch_alias {alias, model?, effort?}`. State only what you were
told: an unspecified model/effort renders `?` — **do not guess them**. The
switch relabels every *follower* immediately. Non-Claude agents (kimi, opencode,
crush, aider, codex, gemini, qwen) are **not** followers by default — their
alias is their own identity. After switching, re-read your label before the next
dispatch. Full semantics: `references/alias-switching.md`.

## Registering yourself (only when you are not already registered)

Claude Code sessions are registered by the SessionStart hook. Other CLI agents
register through their adapter (`docs/label-sync/ADAPTERS.md`). If neither
exists, the guaranteed path is the supervising wrapper — the operator runs
`scripts/label-sync/adapters/generic/label-agent-run.sh --agent NAME -- <cmd>`.
Via MCP an agent can `label_register` / `label_heartbeat` / `label_done` its own
entity; heartbeat at least every 60 s while working (staleness TTL is 120 s) and
`label_done` when finished. Never register entities on behalf of others.

## Troubleshooting (short)

* **`?` in a field** — nothing could be derived (non-git cwd, unknown model).
  Report it; do not fill it.
* **`[stale]` / state `unknown`** — the owner stopped heartbeating and its pid is
  gone. A heartbeat revives it; staleness never deletes.
* **Old alias after a switch** — that entity has `follow_active=false`
  (per-process truth, e.g. resumed under another alias). Check
  `labelctl.sh get --id ID --json | jq .follow_active`.
* **No bus / exit 2** — `labelctl.sh verify`; exit 2 means *cannot determine*,
  which is never a pass. Details: `references/troubleshooting.md`.

## Honest scope

This skill makes *you* use and respect the label. Delivery of the label into
each agent's UI depends on that agent's capability level
(`docs/label-sync/ADAPTERS.md`: TESTED / SCHEMA-ONLY / UNCONFIRMED). Where an
agent has no hook, the wrapper fallback provides registration but cannot change
the agent's own prompt.
