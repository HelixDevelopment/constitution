# label-sync hooks and wiring

| Field | Value |
|---|---|
| Document | `docs/label-sync/HOOKS.md` |
| Revision | 1 (2026-10-12) |
| Status | implemented and tested on branch `feature/label-sync` (local, unpushed); live delivery inside a real Claude Code session is UNCONFIRMED (see §2) |
| Implements | §11.4.182 (label), §11.4.208 / §11.4.210 (request ledger auto-capture), §11.4.228(D) / §11.4.164 (auto-wiring on pull), §11.4.233 (level-triggered), §11.4.18 (script docs) |
| Builds on | [`CONTRACT.md`](CONTRACT.md) (data contract), [`README.md`](README.md) (core quick start) |
| Code | `scripts/label-sync/hooks/`, `scripts/label-sync/toolkit/`, `scripts/label-sync/install_label_sync.sh` |
| Tests | `scripts/hooks/test_label_sync_hooks.sh` (205 assertions), `scripts/label-sync/prove_hook_mutations.sh` (10 mutants), gate `scripts/gates/cm_label_sync_hooks.sh` |

## Contents

1. [What the hooks do](#1-what-the-hooks-do)
2. [Hook events: CONFIRMED vs UNCONFIRMED](#2-hook-events-confirmed-vs-unconfirmed)
3. [Every hook, event and payload field used](#3-every-hook-event-and-payload-field-used)
4. [The alias-switch signal and the claude toolkit](#4-the-alias-switch-signal-and-the-claude-toolkit)
5. [The request-history ledger](#5-the-request-history-ledger)
6. [The installer](#6-the-installer)
7. [Auto-wiring on constitution pull](#7-auto-wiring-on-constitution-pull)
8. [Rollback](#8-rollback)
9. [Environment variables](#9-environment-variables)
10. [Performance, failure behaviour, limits](#10-performance-failure-behaviour-limits)

## 1. What the hooks do

Claude Code runs a hook script at each lifecycle event and passes it a JSON
document on stdin. The label-sync hooks turn those events into `labelctl` calls
against the shared state directory (CONTRACT §1), so that every session,
subagent and follower shows an always-current label
`(T<N>/<branch> - <alias> - <model> - <effort>)`:

```
SessionStart ──> register session entity (pid, cwd, track/branch/alias/model/effort)
                  └─ resumed under a DIFFERENT alias? -> republish subtree + alias_switch
UserPromptSubmit ─> heartbeat + refresh fields + request-history ledger row (once)
                    + additionalContext = the live label (the model sees it)
PreToolUse Agent|Task ─> register the subagent from the description's label prefix
SubagentStart ──> correlate agent_id with that registration
SubagentStop  ──> subagent done
Stop          ──> session idle; reap never-started subagent registrations
SessionEnd    ──> session + all its entities done; drop hook-private state
PostModelSwitch ─> (opt-in) session model updated at once
```

Every hook is fail-soft: it always exits 0, prints nothing except the one
documented JSON line, and is level-triggered (each hook re-asserts the entities
it needs, so a missed event never leaves a permanent hole).

## 2. Hook events: CONFIRMED vs UNCONFIRMED

Checked 2026-10-12 against the installed Claude Code **2.1.296**
(`~/.local/share/claude/versions/2.1.296`, an ELF binary) in two ways:
(a) the plugin-development documentation on disk
(`.../plugin-dev/skills/hook-development/SKILL.md`), and (b) `strings` over the
binary, reading the built-in hook-event descriptions and the event-name list.
No hook was observed being delivered by a live session (that would have required
editing a real `~/.claude*` settings file, which this stream is forbidden to do).

| Event | Status | Evidence |
|---|---|---|
| `SessionStart` | CONFIRMED (docs + binary) | docs; binary: "When a new session is started — Input … JSON with session start source"; matcher values `startup resume clear compact fork` |
| `UserPromptSubmit` | CONFIRMED (docs + binary); payload field name UNCONFIRMED | binary: "Input to command is JSON with original user prompt text"; the docs call the field `user_prompt`, the field the hooks read is `.prompt // .user_prompt` so either works |
| `PreToolUse` (matcher `Agent\|Task`) | CONFIRMED | already used by `guard-track-branch-label.sh`; payload `tool_name`, `tool_input.description` |
| `SubagentStart` | CONFIRMED in the binary only | binary: "When a subagent (Agent tool call) is started — JSON with agent_id and agent_type"; not in the plugin-dev docs |
| `SubagentStop` | CONFIRMED (docs + binary) | binary: "JSON with agent_id, agent_type, and agent_transcript_path" |
| `Stop` | CONFIRMED | docs + binary |
| `SessionEnd` | CONFIRMED (docs + binary) | binary: "JSON with session end reason" |
| `PostModelSwitch` | CONFIRMED in the binary only (hence opt-in) | binary: "After the session model changes (any cause) — JSON with from_model, to_model, requested_model, source …" |
| `statusLine` (settings key) | CONFIRMED to exist; its schema `{type:"command",command}` is from Claude Code convention | the renderer is another stream's work |
| correlation `tool_use_id` ↔ `agent_id` | UNCONFIRMED | no documentation says the two identify the same dispatch; pairing is oldest-first plus `subagent_type == agent_type` (best effort for parallel dispatches of one type); unpaired entities are cleaned at `Stop`/`SessionEnd` |
| hook `timeout` field (seconds) | CONFIRMED by the plugin-dev docs | the installer writes `"timeout": 5` |
| `additionalContext` output | CONFIRMED | binary strings `hookSpecificOutput` / `additionalContext`; "Exit code 0 - stdout shown to Claude" |

## 3. Every hook, event and payload field used

All scripts live in `scripts/label-sync/hooks/` and share `label-sync-lib.sh`.

| Script | Event / matcher | Payload fields read | Effect |
|---|---|---|---|
| `label-sync-session-start.sh` | `SessionStart` `*` | `session_id`, `cwd`, `source` | `register --kind session` with `--session`, `--cwd`, pid of the owning `claude` process (liveness), fields from the canonical labeler (`scripts/multitrack/track_branch_label.sh`, run with `CLAUDE_CODE_SESSION_ID` exported so its transcript model lookup works). Remembers the registered alias in `hooks/sessions/<sid>.alias`. **Alias change on resume**: if the new derived alias differs from the remembered one, the session is registered non-following (the state layer then republishes every entity of that `session_id` and its descendants, CONTRACT §4.3), the new alias is published as the active alias (`switch-alias`, skipped when `LABEL_SYNC_NO_SWITCH_ON_RESUME=1`), and the session and descendants are set back to follow, so later operator switches relabel them. If the active alias has an empty model and this live session runs under it, the active model is filled from the session (never overwriting an explicit one). Output: `additionalContext` with the label. |
| `label-sync-prompt.sh` | `UserPromptSubmit` | `session_id`, `cwd`, `prompt` | appends the ledger row (§5), `update --state running` with freshly derived fields (re-registers if the entity is missing), outputs `additionalContext` = effective label. |
| `label-sync-agent-register.sh` | `PreToolUse` `Agent\|Task` | `tool_name`, `tool_use_id`, `tool_input.description`, `tool_input.subagent_type`, `tool_input.model`, optional `agent_id` | parses the `(T<N>/<branch> - <alias>[ - <model>[ - <effort>]])` prefix; registers `subagent:<tool_use_id>` under the session, following the session's follow flag; writes a pending file for correlation. Never blocks, prints nothing. **Composition with `guard-track-branch-label.sh`**: the guard (unchanged) blocks unlabelled and stale-alias dispatches; this hook registers only a dispatch the guard will allow, so a refused dispatch never leaves a phantom entity. |
| `label-sync-subagent-start.sh` | `SubagentStart` | `session_id`, `agent_id`, `agent_type` | moves the oldest matching pending registration to `hooks/agentmap/<agent_id>`. |
| `label-sync-subagent-stop.sh` | `SubagentStop` | `session_id`, `agent_id` | `unregister` (state `done`) the correlated entity; no guess when uncorrelated. |
| `label-sync-stop.sh` | `Stop` | `session_id` | session `idle`; unregisters pending registrations never adopted by a `SubagentStart` (denied or never started). |
| `label-sync-session-end.sh` | `SessionEnd` | `session_id`, `reason` | every entity of the session `done`; removes the session's hook-private state. `label-busd` reaps `done` entities after the retention window. |
| `label-sync-model-switch.sh` | `PostModelSwitch` (opt-in) | `session_id`, `to_model` | session `--model` updated at once. |
| `label-sync-alias-switch.sh` | not an event hook (CLI) | args | see §4. |
| `request_history_append.sh` | called by the prompt hook, or run directly | stdin JSON or function args | see §5. |

Hook-private correlation state lives in `$LABEL_SYNC_DIR/hooks/{pending,agentmap,sessions,ledger-last}/` (mode 0700).

## 4. The alias-switch signal and the claude toolkit

`scripts/label-sync/hooks/label-sync-alias-switch.sh <alias> [--model M] [--effort E]`
calls `labelctl switch-alias`. Every follower entity re-renders on the next
snapshot (CONTRACT §4.1). Exit 0 published, 1 rejected, 2 usage / cannot determine.

`scripts/label-sync/toolkit/cma_label_hook.sh` is a **sourceable** wrapper for the
claude-multi-account toolkit. It wraps the two launchers `cma_run` (native
`claudeN`, alias from `$CLAUDE_CONFIG_DIR`) and `cma_run_provider` (provider
alias = the provider id; model = the `CMA_PROVIDER_MODEL` line of that provider's
`.env`, extracted with `sed`, the rest of the file — including API keys — is never
read or printed). On every launch or resume it publishes the alias switch
**before** the real launcher runs, then calls the real launcher with unchanged
arguments, environment and working directory and returns its exit status. A
failure or absence of the label tooling never blocks a launch; on a host with no
built binary it only starts a detached background build.

**Install (text only — this stream does not edit anything under `$HOME`).** Add
one line to `~/.bashrc` (or `~/.zshrc`) **after** the line that sources
`~/.local/share/claude-multi-account/aliases.sh`:

```bash
source /home/<you>/Projects/<project>/submodules/constitution/scripts/label-sync/toolkit/cma_label_hook.sh
```

It is idempotent. If `aliases.sh` is re-sourced later (which redefines the
launchers), call `cma_label_hook_rewrap` or source the file again. To remove it,
delete that line and re-source `aliases.sh`. Limitation: the active alias is
operator-global by design (CONTRACT §4.1), so launching a second terminal under
another alias changes the active alias for every follower.

## 5. The request-history ledger

`request_history_append.sh` is the §11.4.208 auto-capture helper (no earlier
helper existed in the constitution tree). One JSON object per prompt, appended
atomically under `flock`:

```json
{"accepted":"2026-10-12T13:40:58+0200","timezone":"CEST","session_id":"…","prompt":"…verbatim…",
 "prompt_kind":"verbatim","track":"1","alias":"claude2","model":"opus","effort":"UNKNOWN",
 "cwd":"…","source":"label-sync-prompt-hook"}
```

* Unrecoverable fields are the literal `UNKNOWN`, never invented (§11.4.208(A)).
* Location: `$LABEL_SYNC_REQUEST_LEDGER`, else `$CLAUDE_PROJECT_DIR/docs/requests/history.jsonl`
  **only when `docs/requests/` already exists** (the project has declared a
  request-history location); otherwise no ledger is created.
* **Exactly once per prompt:** the same session and prompt text delivered twice
  within `LABEL_SYNC_LEDGER_DEDUPE_MS` (default 2000 ms) is one event (a hook
  registered in two settings files); the same text after the window counts again.
* Optional human-readable twin: if `docs/requests/history.md` contains the line
  `<!-- label-sync:request-history:insert -->`, a newest-first block is inserted
  right after it. The `.html/.pdf/.docx` exports (§11.4.65) remain the project's
  docs-chain job.
* The ledger works with no daemon and no built binary.

## 6. The installer

`scripts/label-sync/install_label_sync.sh` merges the hook entries and the
`statusLine` entry into a target settings file. **Default is `--dry-run`**
(prints a unified diff, writes nothing).

```
install_label_sync.sh [--apply | --dry-run] [--platform claude|all]
    [--scope project|user] [--project-root DIR] [--home DIR | --config-dir DIR | --settings FILE]
    [--constitution-root DIR] [--render-path FILE] [--no-statusline] [--with-model-switch]
    [--uninstall] [--brief]
```

* **Target:** `--scope project` (default) = `<project-root>/.claude/settings.json`, hook
  commands written as `bash "$CLAUDE_PROJECT_DIR/<path>/scripts/label-sync/hooks/…"` when the
  constitution lives inside the project (by reference, never copied, portable across clones);
  `--scope user` = `<config-dir>/settings.json` (`--config-dir`, else `$CLAUDE_CONFIG_DIR`, else
  `<home>/.claude`) with absolute paths; `--home DIR` re-points `$HOME` for tests.
* **Merge rules:** every existing key and hook is preserved; an entry of ours is recognised by
  its script name, de-duplicated and refreshed in place; re-applying yields a byte-identical file
  and no extra backup; a foreign `statusLine` is never clobbered (reported); `PostModelSwitch` is
  wired only with `--with-model-switch`.
* **Safety:** refuses (exit 1) a settings file that is not a valid JSON object and leaves it
  untouched; writes a backup `settings.json.label-sync.bak.<UTC-ts>` before the first change;
  replaces the file atomically; asserts at `--apply` time (exit 2, nothing written) that every hook
  script and the statusLine renderer exist. The renderer path defaults to
  `scripts/label-sync/render/statusline.sh` (written by another stream); `--no-statusline` wires the
  hooks only.
* **`--platform all`** also reports opencode / gemini / qwen as not wired (no Claude-style hook
  interface) — an honest skip.

## 7. Auto-wiring on constitution pull

`scripts/post_update_hook.sh` (§11.4.164) gains **step 4c**. When a pull changes anything under
`scripts/label-sync/` or the labeler, it runs the installer against `$PROJECT_ROOT`:

| `LABEL_SYNC_AUTOWIRE` | Behaviour |
|---|---|
| unset / `dry-run` (default) | `--dry-run --brief`: records what **would** be wired, writes nothing |
| `apply` | writes (with backup), idempotent |
| `off` | skipped |

The existing hook had no apply flag (it always applied); the default for this step is deliberately
non-destructive, and `LABEL_SYNC_AUTOWIRE=apply` is the one switch to wire a consumer
(`LABEL_SYNC_AUTOWIRE=apply bash submodules/constitution/scripts/post_update_hook.sh`).

## 8. Rollback

* Installer: `install_label_sync.sh … --uninstall --apply` removes exactly our hook entries and our
  `statusLine`; or `cp <settings>.label-sync.bak.<ts> <settings>`.
* Kill switch without touching settings: `LABEL_SYNC_DISABLE=1` makes every hook a silent no-op.
* Toolkit: delete the `source …/cma_label_hook.sh` line and re-source `aliases.sh`.
* State: removing `$LABEL_SYNC_DIR` loses only labels, which every hook re-asserts on its next event.

## 9. Environment variables

| Variable | Meaning |
|---|---|
| `LABEL_SYNC_DIR` / `LABEL_SYNC_BIN` / `LABEL_SYNC_LABELER` | state dir / binary cache / labeler (as `labelctl.sh`) |
| `LABEL_SYNC_DISABLE=1` | kill switch |
| `LABEL_SYNC_NO_BUILD=1` | hooks never spawn the background build |
| `LABEL_SYNC_CLAUDE_PID` | override the discovered claude pid (tests) |
| `LABEL_SYNC_NO_SWITCH_ON_RESUME=1` | on an alias-changing resume publish only the subtree, not the global active alias |
| `LABEL_SYNC_REQUEST_LEDGER`, `LABEL_SYNC_LEDGER_DEDUPE_MS` | ledger path, dedupe window |
| `LABEL_SYNC_CTL_TIMEOUT` | optional per-`labelctl` timeout (off by default, see §10) |
| `LABEL_SYNC_HOOK_DEBUG=1`, `LABEL_SYNC_HOOK_STDERR=<file>` | diagnostics to `hooks/debug.log` / hook stderr to a file |
| `LABEL_SYNC_AUTOWIRE` | `dry-run` (default) / `apply` / `off` for `post_update_hook.sh` |

## 10. Performance, failure behaviour, limits

* **Latency** (median of 5, loaded host, load average ≈ 14, 2026-10-12): `Stop` 35 ms, `SubagentStop` 24 ms,
  `PreToolUse` register 60 ms, `UserPromptSubmit` 87 ms, `SessionStart` 115 ms (runs vary ±25 ms with load); bound asserted by the
  suite is 150 ms (`LS_LATENCY_MS`). Rules that keep it there: no external process on the hot path
  that a bash builtin can replace (each spawn cost 15–25 ms here), one `jq` call to parse the payload,
  and **no `timeout(1)` wrapper** — on this host's coreutils `timeout` adds a flat 100 ms to every call;
  the bound comes instead from the 5 s `timeout` the installer writes into settings.json.
* **Bus down / binary missing / state dir unusable / garbage stdin / empty stdin:** exit 0, no output
  (suite section 7). A missing binary starts one detached, niced, rate-limited background build.
* **Limits (§11.4.6):** the `tool_use_id` ↔ `agent_id` correspondence is unconfirmed; the model of a
  background subagent introspecting its own transcript is the labeler's documented open limitation; the
  active alias is operator-global; the `UserPromptSubmit` additionalContext line adds ~25 tokens per
  prompt; live delivery of any hook in a real session was not observed by this stream.
