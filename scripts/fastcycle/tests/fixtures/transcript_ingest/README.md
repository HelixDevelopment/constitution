# Fixtures: transcript_ingest (T020, plan T-A06)

RED-set fixtures for `constitution/scripts/fastcycle/tests/test_token_attribution_red.sh`
(T020). Guards T036 (`$FC/tokens/dispatch_stamp.sh`) and T038
(`$FC/tokens/transcript_ingest.py`) — neither exists yet; this test and its
fixtures are written and observed to fail against that absence (§11.4.224,
common-conventions.md C-005). Producer≠Verifier (§11.4.240): this directory
and the test script are the RED artefact only; `dispatch_stamp.sh` and
`transcript_ingest.py` are separate, later, implementation tasks owned by
other agents.

## Real-schema provenance (§11.4.6 — nothing here is invented)

Every field shape below was read from this project's OWN live Claude Code
transcripts on 2026-09-28 (session `8824e088-62a6-4d4f-9f6c-2320055ad033` and
sibling sessions under `~/.claude-claude5/projects/-mnt-track1-atmosphere-t1/`),
never assumed:

- Top-level (non-sidechain) transcript records: `parentUuid`, `isSidechain`,
  `type` (`user`|`assistant`|...), `uuid`, `timestamp`, `sessionId`, `message`.
  An `assistant` record's `message` carries `model`, `id`, `type`, `role`,
  `stop_reason`, `content`, and (when the API call actually returned) a
  `usage` object with `input_tokens`, `output_tokens`,
  `cache_creation_input_tokens`, `cache_read_input_tokens` (plus
  provider-internal fields such as `output_tokens_details`,
  `server_tool_use`, `cache_creation`, `service_tier`, `iterations`, `speed`
  — irrelevant to token attribution and omitted from these minimal
  fixtures).
- A rate-limited/rejected turn's `message.usage` is present with EVERY count
  explicitly `0` (captured verbatim: session `0099c079-62e3-4846-a2a6-eacb7d42a85c`,
  line 49, `error: "rate_limit"`, `isApiErrorMessage: true`,
  `apiErrorStatus: 429`, all four usage counts `0`) — this is the REAL
  shape `missing_usage_block/usage_present_zero.jsonl` is modelled on: a
  genuinely-zero, fully-instrumented turn, never to be confused with a turn
  that carries no `usage` key at all.
- Async agent dispatch: the PARENT transcript's dispatching `assistant`
  turn contains a `tool_use` content block (`type: "tool_use"`, `name:
  "Agent"`, `input: {description, prompt}`); the immediately-following
  `user` turn (the tool result) carries `toolUseResult: {isAsync: true,
  status: "async_launched", agentId, description, resolvedModel,
  outputFile, ...}` (captured verbatim from a genuine live async dispatch,
  agentId `a3769936d2ace3124`, session `8824e088-62a6-4d4f-9f6c-2320055ad033`,
  2026-09-28 — the SAME real payload shape `scripts/hooks/
  test_agent_registry_dispatch_writer_red.sh`'s own A8 case is built from,
  cited there as agentId `ac39c9d3e8933edd3`, 2026-09-27).
- **Real captured dispatch `description` today carries NO `item=<ATM-nnnn>`
  token anywhere** — verbatim captured example (session
  `8824e088-62a6-4d4f-9f6c-2320055ad033`, `toolUseResult.description`):
  `"(T1/main - claude5 - sonnet - high) T018 RED test review_record"`. This
  is the direct evidence behind property (a) in the test.
- Subagent transcript on-disk convention: `<CLAUDE_CONFIG_DIR>/projects/
  <project-slug>/<parent_session_id>.jsonl` (the parent/CLI transcript)
  alongside `<parent_session_id>/subagents/agent-<agentId>.jsonl` (the
  subagent's OWN transcript) — directly observed via
  `<repo>/../.../tasks/<agentId>.output` symlinks resolving to exactly that
  path. A subagent transcript record carries `agentId` directly (not only
  derivable from the file name) plus `isSidechain: true` and (for its first
  `user` record) `promptId`. This is the real join key `transcript_ingest.py`
  (T038)'s "session→agent→item" keying (plan.md T-A06) needs: `sessionId`
  (session) → `agentId` (agent, matching both the subagent record's own
  field AND the parent's `toolUseResult.agentId` AND the
  `agent-<agentId>.jsonl` filename) → the `item=<ATM-nnnn>` token embedded
  in the parent's stamped `description` (item, once T036/T037 land).

## Fixture map

| Path | Property under test | Shape |
|---|---|---|
| `cache_hits/session.jsonl` | cache-hit tokens are counted, not dropped | one `user` turn + two `assistant` turns: turn 1 is cache-cold (`cache_creation_input_tokens=1200`, `cache_read_input_tokens=0`), turn 2 is a genuine cache HIT reading the same 1200 tokens back (`cache_read_input_tokens=1200`) |
| `missing_usage_block/usage_absent.jsonl` | a turn with NO `usage` key MUST be reported missing/`UNMEASURED` (common-conventions.md term), never coerced to 0 | `assistant` `message` object has no `"usage"` key at all |
| `missing_usage_block/usage_present_zero.jsonl` | negative control (§11.4.201(6) false-null guard, C-004 control needle) — a genuinely-zero, fully-instrumented turn MUST NOT be reported missing | `assistant` `message.usage` present, all four counts explicitly `0` (modelled on the real rate-limited-turn shape above) |
| `subagent_attribution/parent_session.jsonl` + `subagent_attribution/parent_session/subagents/agent-fixturet020attr01.jsonl` | a subagent's token usage attributes to its parent dispatch's item | parent dispatches with `description` containing `item=ATM-9999` (the future T036-stamped tag) and `toolUseResult.agentId = "fixturet020attr01"`; the subagent transcript (real on-disk path convention) carries the SAME `agentId` and its own real usage (`cache_read_input_tokens=500`, `cache_creation_input_tokens=8000`) |
| `credential_leak/session.jsonl` | a planted secret-shaped string in message content never reaches the telemetry DB (§11.4.10) | `user`+`assistant` turns whose text embeds the literal marker `FASTCYCLE-T020-PLANTED-MARKER-7f3a9c2e1b8d4f6091ab34cd`, clearly labelled synthetic; a genuine `usage` block accompanies the assistant turn so the fixture also exercises normal ingest |

## Credential-scanner safety (verified, not assumed)

Every fixture file above was scanned with this repository's OWN
`helix_cred_scan_file` (`constitution/scripts/hooks/credential_scan_lib.sh`)
before being checked in, with a positive control run first (a synthetic
`AKIA`-shaped AWS key, confirmed CAUGHT) proving the scanner instrument was
alive for that run — all six fixture files scanned clean. The planted marker
in `credential_leak/session.jsonl` deliberately avoids every keyword the
scanner's `HELIX_CRED_VALUE_PATTERN` matches (`password|passwd|secret|
api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret` adjacent to
`:`/`=`) and every literal prefix it matches (`AKIA`, `ghp_`, `gho_`,
`github_pat_`, `xox[baprs]-`, `sk-`, `AIza`, `-----BEGIN ... PRIVATE
KEY-----`) — it is a synthetic marker STRING representing "sensitive
message-body content that must never reach a metrics-only DB", not a
credential-SHAPED assignment the scanner is designed to catch (that is a
different, already-covered feature).
