# label-sync MCP server (`label-mcp`)

| Field | Value |
|---|---|
| Document | `docs/label-sync/MCP.md` |
| Revision | 3 (2026-10-14) — re-review: the consumer entry is launched through `sh` and finds the project root from ANY start directory; the prover reports a non-compiling mutant as UNDETERMINED (exit 2). Revision 2 — explicit alias pins, 4 MiB line cap, no guessed `type`, consumer-resolvable path |
| Status | implemented and tested on branch `feature/label-sync` (local, unpushed) |
| Implements | §11.4.182 (label), §11.4.116 (bus), §11.4.228(D) (MCP registration seam), §11.4.18 |
| Code | `scripts/label-sync/mcp/label-mcp/` (Go, stdlib only) + launcher `scripts/label-sync/mcp/label-mcp.sh` |
| Config | `mcp/label-sync-mcp.json` |
| Tests | `scripts/label-sync/mcp/label-mcp/server_test.go` (`go test -race`), mutation proof `scripts/label-sync/mcp/prove_mcp_mutations.sh` (14 mutants, each killed by a `--- FAIL:` line), gate `scripts/gates/cm_label_sync_mcp.sh` |

## What it is

A Model Context Protocol server (protocol `2024-11-05`, JSON-RPC 2.0, one JSON
document per line on stdin/stdout) that lets **any MCP-capable agent** read and
drive the label bus. It is compiled into the label-sync Go module so it calls the
*same* `internal/state` code `labelctl` uses — CLI and MCP cannot disagree.

## Run / register

```bash
bash scripts/label-sync/mcp/label-mcp.sh          # builds when missing/stale, then execs the server
```

`mcp/label-sync-mcp.json` follows the repo's MCP-config convention
(`mcp/scheduled-work-mcp.json`): `{"mcpServers":{"label-sync":{"command":"scripts/label-sync/mcp/label-mcp.sh", ...}}}`.
The path is relative to the CONSTITUTION root; `post_update_hook.sh` step 3
rewrites it for the consumer to `<constitution-dir-relative-to-project>/scripts/…`
(e.g. `constitution/…` or `submodules/constitution/…`; absolute when the
constitution lives outside the project). The entry carries `command`, `args`,
`env` — the shape this repository documents for Claude Code `.mcp.json`
(`submodules/polyscreen-mcp/README.md`); the earlier `"type": "command"` was a
guess and is removed.

**Measured by the third (re-)review with Claude Code 2.1.300 and an isolated
`CLAUDE_CONFIG_DIR`:** the client spawns the `command` relative to the
directory IT was started in — started in `<project>/sub/deeper`, a
project-relative command failed with `ENOENT` (posix_spawn) — and
`${CLAUDE_PROJECT_DIR}` is NOT expanded inside `.mcp.json`. So a relative path
alone works only when Claude Code starts at the project root. Step 3 therefore
writes the consumer entry as

    "command": "sh",
    "args": ["-c", "<walk up from $PWD to the directory holding <prefix>; cd there; exec \"$0\" \"$@\">",
             "<prefix>/scripts/label-sync/mcp/label-mcp.sh", <original args...>]

which starts the server from any directory inside the project and fails
loudly (`label-sync MCP launcher: <prefix> not found above <dir>`, exit 127)
outside it; an absolute constitution path (outside the project) is written
as is. Proven by `scripts/hooks/test_label_sync_hooks.sh` §20 (R3): the merged
entry is executed from `<project>/sub/deeper`, from the root and from `/`.
That Claude Code itself then starts this `sh` entry from a sub-directory was
NOT re-measured with the client after the change (the suite replays the spawn,
not the client). Whether it honours `autoApprove`/`disabled`/`description` is
**UNCONFIRMED** (not documented here).
`autoApprove` is limited to the read-only tools (`label_get`, `label_list`,
`label_active`); the mutating tools prompt the operator.
`post_update_hook.sh` / the §11.4.228(D)(3) MCP-registration seam merges this file
into each detected platform (the wiring is owned by the HOOKS stream).

State dir: `LABEL_SYNC_DIR` (default `$HOME/.local/state/constitution-label-sync`, CONTRACT §1).

## Tools

| Tool | Arguments | Result |
|---|---|---|
| `label_get` | `id` **or** `session_id` | the entity JSON incl. `label`; `session_id` returns the session entity (else first match); neither / unknown → `isError` |
| `label_list` | `kind?`, `alias?` (EFFECTIVE alias) | `{seq, entities[]}`; invalid `kind` → `isError` |
| `label_switch_alias` | `alias` (required), `model?`, `effort?` | `{alias,model,effort,seq}`; appends an `alias_switch` event, followers relabel in the same write; empty alias → `isError`, nothing logged |
| `label_register` | `id`, `kind` (required); `parent_id session_id pid cwd track branch alias model effort follow_active state source` | the registered entity (label rendered); `follow_active` defaults to `true` WITHOUT an `alias` and to `false` WITH one (an explicit alias pins; only alias-less roots follow the active context, CONTRACT §4.2); an explicit `follow_active` wins; bad kind/state, or a pid outside 0..4194304 (`MaxPID`) → `isError` |
| `label_heartbeat` | `id`, `state?` | refreshed entity; unknown id → `isError` |
| `label_done` | `id` | entity with `state=done`; unknown id → `isError` |
| `label_active` | — | `{alias,model,effort,switched_at,seq}` (empty alias when none) |

Tool failures are **tool results with `isError:true`** and a plain message
(MCP convention), not JSON-RPC errors. An unusable state dir yields
`isError:true` "cannot determine …" while `initialize`/`ping`/`tools/list` keep
working (2 is never a pass, §11.4.6).

## Protocol behaviour (all covered by tests)

| Case | Behaviour |
|---|---|
| `initialize` | `protocolVersion:"2024-11-05"` whatever the client asked, `capabilities.tools`, `serverInfo{name:"label-mcp",version}` |
| notification (no `id`) | never answered (`notifications/initialized`, unknown ones too) |
| unknown method (request) | `-32601` |
| malformed JSON line | `-32700` with `id:null`; the server keeps serving |
| not a JSON-RPC 2.0 request | `-32600` |
| `tools/call` unknown tool / malformed params | `-32602` |
| batch (array) | answered as an array; invalid items answered individually |
| ids | numbers and strings echoed verbatim |
| ordering | pipelined requests keep **read-after-write** order: a mutating tool (`label_register/heartbeat/done/switch_alias`, any batch) starts only after every earlier request finished; reads start after the latest earlier mutation and run concurrently with each other. Responses are emitted in request order |
| long lines | up to 4 MiB per request line (300 KB tested); a longer line is DISCARDED while reading (memory stays bounded — a 150 MB line used to cost 566 MB RSS) and answered with ONE `-32600` "request line too large"; the next line is served |
| stdin EOF | every in-flight call is answered, then exit 0 |
| stdout | JSON-RPC only; diagnostics on stderr |

## Honest limits

* **Verified:** the protocol and every tool against a real process boundary
  (`TestBinaryStdio`) and under `-race`. **Not verified:** attachment inside a real
  Claude Code / other agent's MCP client (the host's agents were not driven
  through MCP; only a faithful hand-rolled client was).
* `label_register` over MCP trusts the caller; there is no auth (local stdio only).
* Registered entities need a heartbeat (TTL 120 s) or they render `[stale]`; a
  turn-based agent cannot keep a timer, so update EVENT-DRIVEN (register at
  start, heartbeat when a unit of work starts/ends, done at the end) and accept
  `[stale]` between events (skills/label-sync/SKILL.md).
