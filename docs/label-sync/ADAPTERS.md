# label-sync CLI-agent adapters

| Field | Value |
|---|---|
| Document | `docs/label-sync/ADAPTERS.md` |
| Revision | 4 (2026-10-15) — re-review 3: a signal is forwarded only after the child reports ready (USR1), so it can no longer be lost in the fork window (§5); revision 3 (2026-10-14) — re-review: a signal in the spawn window reaches the agent (§5); revision 2 (2026-10-14) — second-review fixes: exact rollback + idempotency from existing configs, 0600 backups without duplicates, quoted/encoded paths, metacharacter refusal, option-value check, wrapper signal handling (§4, §5) |
| Status | implemented and tested on branch `feature/label-sync` (local, unpushed); capability level per agent below — read it before relying on an agent |
| Implements | §11.4.182 (label), §11.4.228 (cross-agent extension lifecycle: detect, wire, self-validate, idempotent, dry-run), §11.4.164, §11.4.233 (level-triggered), §11.4.18 |
| Code | `scripts/label-sync/adapters/` (lib, per-agent adapters, `install_adapters.sh`, `_edit_config.py`) |
| Tests | `adapters/tests/test_adapters.sh` (hermetic, 191 assertions, measured 2026-10-15), `adapters/tests/test_real_agents.sh` (real agents, 17 checks), `scripts/label-sync/prove_adapter_mutations.sh` (32 mutants), gate `scripts/gates/cm_label_sync_adapters.sh` |
| Builds on | [`CONTRACT.md`](CONTRACT.md), [`HOOKS.md`](HOOKS.md) (Claude Code), [`RENDERERS.md`](RENDERERS.md) |

## Contents

1. [What an adapter does](#1-what-an-adapter-does)
2. [Detection on this host and capability levels](#2-detection-on-this-host-and-capability-levels)
3. [Per-agent mechanism, evidence and gaps](#3-per-agent-mechanism-evidence-and-gaps)
4. [Install, dry-run, rollback](#4-install-dry-run-rollback)
5. [The guaranteed fallback: the generic wrapper](#5-the-guaranteed-fallback-the-generic-wrapper)
6. [Identity model, environment, privacy](#6-identity-model-environment-privacy)
7. [Where the label is shown](#7-where-the-label-is-shown)
8. [UNCONFIRMED items](#8-unconfirmed-items)

## 1. What an adapter does

Each adapter turns *that agent's own* lifecycle signal into label-bus calls
(register / heartbeat / done, CONTRACT §2.2). One shared library
(`adapters/lib/adapter_lib.sh`) holds all logic; the per-agent scripts only
translate a native payload. Properties common to all of them:

* **Level-triggered (§11.4.233):** every call re-asserts the whole entity
  (heartbeat of an unknown entity registers it), so a missed start event never
  loses a label.
* **Fail-soft:** exit 0 always (in Kimi/Crush/Gemini a non-zero/2 exit would
  *block* the agent); an unusable bus is silently tolerated
  (`LABEL_SYNC_ADAPTER_DEBUG=1` logs to `$LABEL_SYNC_DIR/adapters/debug.log`).
* **Secret-safe (§11.4.10):** only session id, cwd, model and state cross into
  the bus. Prompts, tool inputs, command lines and messages are never parsed;
  tests plant canary strings in them and assert they never reach the state dir.
* **Honest fields:** model/effort the agent did not report are `?`. The Claude
  session's model/effort are **never** borrowed (the derive step is overridden;
  mutant B2 proves the test catches that).
* **Track/branch** come from the canonical labeler (`scripts/multitrack/track_branch_label.sh`)
  run on the agent's cwd.

## 2. Detection on this host and capability levels

Detection (2026-10-12, `command -v <bin>` and `<bin> --version`):

| Agent | Installed | Version | Config file the installer edits |
|---|---|---|---|
| Claude Code | yes | 2.1.296 | not here — `scripts/label-sync/install_label_sync.sh` (HOOKS stream, [`HOOKS.md`](HOOKS.md)) |
| Kimi Code CLI | yes | 2.1.1 | `~/.kimi-code/config.toml` |
| OpenCode | yes | 1.18.30 | `~/.config/opencode/opencode.json` |
| Crush | yes | v0.91.2 | `~/.config/crush/crush.json` |
| Aider | yes | 0.86.2 | `~/.aider.conf.yml` |
| Codex CLI | **no** | — | `~/.codex/config.toml` |
| Gemini CLI | **no** | — | `~/.gemini/settings.json` |
| Qwen Code | **no** | — | `~/.qwen/settings.json` |
| Cursor (CLI agent) | **no** | — | none (wrapper only) |

Capability vocabulary (closed, §11.4.228(A)(1) spirit):

* **TESTED** — the REAL agent binary was run and its own mechanism fired the
  adapter, producing the expected bus state. Evidence: `adapters/tests/test_real_agents.sh`.
* **SCHEMA-ONLY** — the config was validated by the agent's own validator/parser
  or against its own on-disk schema, but the agent was not observed firing it.
* **UNCONFIRMED** — the agent is not installed here (or has no documented
  mechanism); adapter scripts exist from the upstream documentation as
  remembered and were **never run against the real agent**. Never read as
  working. The generic wrapper is the guaranteed path.

| Adapter / signal | Level | How determined |
|---|---|---|
| **kimi** — `SessionStart`, `UserPromptSubmit` hooks | **TESTED** | real `kimi -p` (2.1.1) in a sandbox HOME fired both hooks; entity `kimi-session_…` appeared with `alias=kimi`, `model` = what kimi reported; `kimi doctor config` accepts the installed `config.toml` (evidence: `test_real_agents.sh`) |
| kimi — `Stop`, `SessionEnd`, `SubagentStart`, `SubagentStop` | **SCHEMA-ONLY** | event names + strict hook schema (`event/matcher/command/timeout`) validated by `kimi doctor config`; the four events did not fire in the sandbox run (no working model endpoint); handlers tested against hand-built payloads only |
| **opencode** — plugin load, `session.created`, `session.deleted` | **TESTED** | real `opencode serve` in a sandbox: plugin loaded, `POST /session` fired `session.created` → entity `running`; `DELETE /session/:id` fired `session.deleted` → `done`; `opencode debug config` resolves the plugin entry (evidence: `test_real_agents.sh`) |
| opencode — `session.idle`, `session.updated`, `chat.message` (real model id) | **SCHEMA-ONLY** | hook names/shapes taken from the installed `@opencode-ai/plugin` type declarations; not fired by a real turn (needs an LLM); exercised with synthetic events through the real module |
| **crush** — `PreToolUse` hook (the only event Crush supports) | **TESTED** | real `crush run` against a local fake OpenAI endpoint issued an `ls` tool call; the hook fired and registered `crush-<session>` `running`; `crush.json` validates against the output of `crush schema` (evidence: `test_real_agents.sh`) |
| **aider** — launch/exit via `aider-labelled.sh` | **TESTED** | real aider 0.86.2 ran under the wrapper: entity registered with `--model` shown, `done` after exit (evidence: `test_real_agents.sh`) |
| aider — idle heartbeat via `--notifications-command` | **SCHEMA-ONLY** | aider's own `--verbose` config dump shows it parsed `notifications`/`notifications_command` from the installed `.aider.conf.yml`; the notification was never observed firing (it did not fire in `--message` mode) |
| **codex** — `notify` program | **UNCONFIRMED** | Codex not installed; payload shape from upstream docs as remembered; fallback: wrapper (`label-agent-run.sh`) |
| **gemini** — `hooks` in `settings.json` | **UNCONFIRMED** | Gemini CLI not installed; event names and `hooks` schema as remembered; fallback: wrapper (`label-agent-run.sh`) |
| **qwen** — `hooks` in `settings.json` | **UNCONFIRMED** | Qwen Code not installed; assumed Gemini-fork hook compatibility; fallback: wrapper (`label-agent-run.sh`) |
| **cursor** — no adapter | **UNCONFIRMED** | no Cursor CLI on this host and no mechanism verified; wrapper only (`label-agent-run.sh`) |
| **generic wrapper** (`label-agent-run.sh`) with any command | **TESTED** | exit codes 0/3/127, TERM forwarding (143), done-after-exit, fail-soft bus, no argument recording (hermetic); and with real aider (above). **Not run with** Codex/Gemini/Qwen/Cursor binaries (absent) — it is agent-agnostic by construction, not by observation (evidence: `test_adapters.sh`, `test_real_agents.sh`) |

## 3. Per-agent mechanism, evidence and gaps

### Kimi Code CLI — `adapters/kimi/kimi-hook.sh`
Mechanism (read from the installed binary's config schema and confirmed by a real
run): `[[hooks]]` tables in `config.toml`, each `event`, optional `matcher`,
`command`, `timeout` (1–600 s); unknown keys are rejected (`strict`). Events:
`PreToolUse PostToolUse PostToolUseFailure PermissionRequest PermissionResult
UserPromptSubmit Stop StopFailure Interrupt SessionStart SessionEnd SubagentStart
SubagentStop PreCompact PostCompact Notification`. The hook receives ONE JSON
document on stdin (snake_case: `hook_event_name session_id cwd client_type model
source …`; a real capture is in the test). Exit 2 blocks, so the adapter always
exits 0. Mapping: SessionStart/UserPromptSubmit → running, Stop → idle,
SessionEnd/SubagentStop → done, SubagentStart → child `subagent` entity.
Gap: no effort concept; two concurrent same-name subagents share one entity.

### OpenCode — `adapters/opencode/label-sync.mjs`
Mechanism: a plugin module listed in `opencode.json` `plugin` (`file://` URL; no
copy, §11.4.228(B)(2)); default export `{id, server}`; hooks `event` and
`chat.message`. The plugin runs inside the opencode process, so the entity pid is
opencode's own (never stale while it lives). Child sessions (`parentID`) become
`subagent` entities. Gap: the plugin is loaded lazily on first server use.
Note both `opencode.json` and `opencode.jsonc` exist on this host: the installer
edits `opencode.json` only (strict JSON — a file with comments is refused as
invalid, never rewritten) and leaves `opencode.jsonc` alone.

### Crush — `adapters/crush/crush-hook.sh`
Mechanism: `hooks.PreToolUse[]` in `crush.json` (`name`, `matcher`, `command`,
`timeout`); env `CRUSH_SESSION_ID CRUSH_CWD …` plus a JSON envelope on stdin; exit
0 + JSON stdout, exit 2 blocks the tool call, exit 49 halts the turn. The adapter
prints the decision-free `{"version":1}` and exits 0. Gap (structural): Crush has
no session start/end event — the entity appears on the first tool call, is kept
alive by its pid (nearest ancestor named `crush`) and goes stale on TTL after
exit; it is never marked `done`. Model/effort are not in the payload.

### Aider — `adapters/aider/aider-notify.sh`, `aider-labelled.sh`
Aider has no hooks; its only lifecycle signal is `--notifications-command` ("run
when waiting for the user"). `aider-labelled.sh` is the supervising wrapper
(registers, passes `--notifications --notifications-command`, unregisters) and
reads `--model` for display. Without the wrapper, the config-file path
(`~/.aider.conf.yml`) creates the entity on the first notification only.

### Codex, Gemini CLI, Qwen Code — UNCONFIRMED
* `codex/codex-notify.sh`: `~/.codex/config.toml` `notify = ["bash", "<script>"]`;
  Codex passes one JSON argument; handled type `agent-turn-complete`.
* `gemini/gemini-hook.sh`, `qwen/qwen-hook.sh`: `hooks` map in `settings.json`
  (`{"matcher":"*","hooks":[{"type":"command","command":…}]}` per event:
  SessionStart, BeforeAgent, AfterAgent, SessionEnd); hook stdout `{}`.
These are written from memory of the upstream documentation. If a real agent
disagrees, the wrapper still works; fix the adapter and promote the row.

### Cursor
No documented hook mechanism was verified and no binary is installed: wrapper only.

## 4. Install, dry-run, rollback

```bash
bash scripts/label-sync/adapters/install_adapters.sh --list            # detection table
bash scripts/label-sync/adapters/install_adapters.sh                   # DRY-RUN (default): writes nothing
bash scripts/label-sync/adapters/install_adapters.sh --apply           # wire every DETECTED agent
bash scripts/label-sync/adapters/install_adapters.sh --apply --agents kimi,crush
bash scripts/label-sync/adapters/install_adapters.sh --apply --remove # rollback of the managed wiring
bash scripts/label-sync/adapters/install_adapters.sh --home /tmp/h --agents kimi,opencode,crush,aider,codex,gemini,qwen --apply   # test mode
```

Contract (§11.4.228(D)(4,5)): idempotent (second `--apply` is byte-identical and
writes no backup); **refuses** an existing file that is not valid JSON/TOML/YAML
(exit 1, file untouched, no backup); **never clobbers** a user's own setting
(codex `notify`, aider `notifications-command` already set ⇒ `conflict`, exit 1);
backs up to `<cfg>.label-sync.bak.<UTC>` before every change — created `0600`
from birth (`O_EXCL`, whatever the umask or the config's own mode: a kimi config
may hold an `api_key`) and NEVER a second copy of identical bytes, so apply /
remove cycles leave at most two backups per file; writes atomically; follows a
symlinked config to its target; new files are `0600`; `--home DIR` pins every
path under DIR and ignores `$HOME/$XDG_*`, so tests cannot touch the real home.
Exit: 0 ok · 1 refused · 2 cannot determine (never a pass). A value option
given last without its value (`--home`, `--agents`) is exit 2 (it used to loop
forever).

**Idempotent from EXISTING files, exact rollback (revision 2).** A second
`--apply` is byte-identical also when the configs existed before (it used to
add a blank line and a new backup on every run). `--apply --remove` restores
the ORIGINAL BYTES: in TOML/YAML the managed block, delimited by
`# >>> label-sync adapters … >>>` / `# <<< label-sync adapters <<<`, records the
separator newlines it inserted (`# label-sync-sep: pre=N post=M`) and removal
takes back exactly those; a JSON config is restored from the backup whose
parsed content equals the un-wired result (ignoring the `$schema` the installer
itself added for opencode); a config the installer CREATED is deleted again.
Hook commands are shell-quoted (`shlex`) so a constitution path with spaces
works, the opencode plugin URL is percent-encoded, and an adapters directory
containing `$`, a backquote, `"`, `\` or a newline is refused (exit 2) — such a
character would be interpreted when the hook command runs.
`post_update_hook.sh` step 4d runs this installer when adapter files change,
DRY-RUN by default (`LABEL_SYNC_ADAPTERS=apply` writes, `off` skips; HOOKS.md §7).

What each `--apply` writes (abridged):

```toml
# ~/.kimi-code/config.toml          (6 events: SessionStart UserPromptSubmit Stop SessionEnd SubagentStart SubagentStop)
[[hooks]]
event = "SessionStart"
command = "bash <constitution>/scripts/label-sync/adapters/kimi/kimi-hook.sh"
timeout = 10
```
```json
// ~/.config/opencode/opencode.json
{ "plugin": ["file://<constitution>/scripts/label-sync/adapters/opencode/label-sync.mjs"] }
// ~/.config/crush/crush.json
{ "hooks": { "PreToolUse": [ { "name": "label-sync", "command": "bash <…>/crush/crush-hook.sh", "timeout": 10 } ] } }
```
```yaml
# ~/.aider.conf.yml
notifications: true
notifications-command: "bash <constitution>/scripts/label-sync/adapters/aider/aider-notify.sh"
```

## 5. The guaranteed fallback: the generic wrapper

For any agent — installed or not, hook-capable or not:

```bash
bash scripts/label-sync/adapters/generic/label-agent-run.sh --agent codex --model gpt-5 -- codex "fix the tests"
```

It registers a `session` entity (alias = agent name unless `--alias`), supervises
the child **without exec** (exact exit code, never a process group — §11.4.263),
and marks the entity `done` at exit. Signals (revision 2, review-2 findings B
and F):

* the agent starts with DEFAULT `SIGINT`/`SIGQUIT` — `( trap - INT QUIT; exec
  "$@" ) <&0 &`; a plain `&` child of a non-interactive bash inherits them
  IGNORED, so a terminal Ctrl-C did not stop the agent (measured `SigIgn` 0x6
  before, 0x0 after); its stdin is the wrapper's;
* `TERM`/`HUP` are forwarded to the one child; `INT`/`QUIT` are forwarded ONLY
  when the child is not in the terminal's foreground process group — otherwise
  the tty already delivered them, and forwarding would make one Ctrl-C two;
* the traps are installed BEFORE the entity is registered: a signal that
  arrives while registering is remembered, the wrapper exits 128+N through its
  cleanup (the entity ends `done`) and the agent is never started — it used to
  die with the default action and leave a `running` ghost entity.
* a signal that lands AFTER the "signalled while registering" check but
  before the child is READY is remembered and forwarded to that ONE child pid
  once the child reports ready (re-review finding 7; test-only seam
  `LABEL_SYNC_TEST_MODE=1` + `LABEL_AGENT_RUN_TEST_SIGNAL_BEFORE_SPAWN`).
  READY (revision 4, re-review 3): the forked child is a bash subshell that
  carries the wrapper's trap handlers until bash resets them, and a signal
  forwarded in that window was caught and dropped — measured 11 of 300 seam
  runs (and 3 of 100 in the suite) where the TERM was lost and the agent ran to
  completion with exit 0. The child now resets its traps, sends `USR1` to the
  wrapper and only then `exec`s the agent; nothing is forwarded before that
  `USR1`. Measured after the fix: 300 of 300. Tests: the 100-run spawn loop and
  the 100-run fast-exit status loop (a `USR1` interrupts the wrapper's `wait`,
  which is repeated while the child lives). Mutants C11, C13, C14.

A parent that itself ignores `SIGINT` (e.g. a job started in the background of
a non-interactive shell) passes that on to the wrapper — no shell can reset a
signal ignored on entry; the tests start their pty with
`env --default-signal=INT,QUIT` to model an interactive terminal.
Command arguments are never recorded. The child inherits `LABEL_SYNC_ENTITY_ID`
so agent-side hooks update the *same* entity. For a plain command/flow without
agent identity use `render/labelrun`. If the bus is unusable the command still
runs and its exit code still returns.

## 6. Identity model, environment, privacy

* **Alias = the agent's own name** (`kimi`, `opencode`, …), `follow_active=false`:
  an operator's Claude alias switch does *not* relabel a Kimi session (CONTRACT
  §4.2, per-process truth). Opt in per process: `LABEL_SYNC_FOLLOW_ACTIVE=1`;
  rename: `LABEL_SYNC_AGENT_ALIAS=my-kimi`.
* Entity id: `<agent>-<sanitised session id>` (`[A-Za-z0-9._-]`, ≤64 chars, long
  ids get a checksum tail so distinct ids stay distinct).
* Env: `LABEL_SYNC_DIR LABEL_SYNC_DISABLE=1 (kill switch) LABEL_SYNC_ENTITY_ID
  LABEL_SYNC_AGENT_PID LABEL_SYNC_ADAPTER_DEBUG LABEL_SYNC_LABELCTL LABEL_SYNC_BIN
  LABEL_SYNC_LABELER`.
* `labelctl` auto-builds its Go binary on first use; hooks use the cached binary.

## 7. Where the label is shown

Adapters *publish*; they do not paint inside a third-party agent's UI (none of
Kimi/OpenCode/Crush/Aider exposes a hook for us to draw the label in its own
screen). Everything that is not Claude Code is visible through the bus
renderers: `render/watch-labels.sh`, terminal title / tmux status / shell
prompt integration, `labelctl list/watch` ([`RENDERERS.md`](RENDERERS.md)), and
the `label-sync` MCP server ([`MCP.md`](MCP.md)) for agents that can use MCP tools.

## 8. UNCONFIRMED items

1. Codex `notify` payload and Gemini/Qwen hook schema (agents absent).
2. Whether Qwen Code is hook-compatible with Gemini CLI.
3. Kimi `Stop/SessionEnd/Subagent*`, OpenCode `session.idle/updated/chat.message`,
   Aider idle notification: never observed firing from the real agent.
4. Cursor: no verified mechanism.
5. Behaviour of any adapter after the agent's own upgrade changes a hook schema
   (the real-agent test is the detector; run it after upgrading an agent).
6. Aider side effect observed while testing: on a first run it opened a browser
   at the release-notes URL (`--yes` accepts the prompt). The test harness now
   sets `BROWSER=/bin/true` and `--no-show-release-notes`; the **installed**
   adapter does not change that aider behaviour.
