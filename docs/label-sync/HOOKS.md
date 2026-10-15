# label-sync hooks and wiring

| Field | Value |
|---|---|
| Document | `docs/label-sync/HOOKS.md` |
| Revision | 4 (2026-10-14) — re-review: errexit inside every post-update step, MCP launcher walks up to the project root, `<synthetic>` never a model, tree-keyed binary staleness; revision 3 (2026-10-14) — second-review fixes, see [§12](#12-second-review-fixes-revision-3); revision 2 (2026-10-12) — independent-review fixes (findings 1–11), see [§11](#11-review-findings-addressed-revision-2) |
| Status | implemented and tested on branch `feature/label-sync` (local, unpushed); live delivery inside a real Claude Code session is UNCONFIRMED (see §2) |
| Implements | §11.4.182 (label), §11.4.208 / §11.4.210 (request ledger auto-capture), §11.4.228(D) / §11.4.164 (auto-wiring on pull), §11.4.233 (level-triggered), §11.4.18 (script docs) |
| Builds on | [`CONTRACT.md`](CONTRACT.md) (data contract), [`README.md`](README.md) (core quick start) |
| Code | `scripts/label-sync/hooks/`, `scripts/label-sync/toolkit/`, `scripts/label-sync/install_label_sync.sh` |
| Tests | `scripts/hooks/test_label_sync_hooks.sh` (506 assertions), `scripts/label-sync/prove_hook_mutations.sh` + table `scripts/label-sync/hook_mutants.py` (57 mutants; a kill needs a `❌ FAIL` assertion line, else UNDETERMINED, exit 2), gate `scripts/gates/cm_label_sync_hooks.sh` |

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
11. [Review findings addressed (revision 2)](#11-review-findings-addressed-revision-2)
12. [Second-review fixes (revision 3)](#12-second-review-fixes-revision-3)

## 1. What the hooks do

Claude Code runs a hook script at each lifecycle event and passes it a JSON
document on stdin. The label-sync hooks turn those events into `labelctl` calls
against the shared state directory (CONTRACT §1), so that every session,
subagent and follower shows an always-current label
`(T<N>/<branch> - <alias> - <model> - <effort>)`:

```
SessionStart ──> register session entity PINNED to the alias this process runs under
                  (pid, cwd, track/branch/alias/model/effort; resumed under another
                  alias => re-pinned; its alias-less subtree follows it)
UserPromptSubmit ─> heartbeat + refresh fields + request-history ledger row (once)
                    + additionalContext = the live label (the model sees it)
PreToolUse Agent|Task ─> register the subagent from the description's label prefix
SubagentStart ──> pair agent_id with the ONE same-type registration (ambiguous => none)
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
binary, reading the hook-input object literals the binary builds
(`hook_event_name:"…", <fields>`). No hook was observed being delivered by a
live session (that would have required editing a real `~/.claude*` settings
file, which this stream is forbidden to do).

| Event | Status | Evidence |
|---|---|---|
| `SessionStart` | CONFIRMED (docs + binary) | binary builds `{…,hook_event_name:"SessionStart",source,agent_type,model,session_title}`; matcher values `startup resume clear compact fork`. The **`model` key is CONFIRMED**; its value format is UNCONFIRMED, so only a string is used (mapped to `opus/sonnet/haiku/fable`), anything else is ignored |
| `UserPromptSubmit` | CONFIRMED (docs + binary), field **`prompt` CONFIRMED** | binary builds `{…,hook_event_name:"UserPromptSubmit",prompt,session_title}` — the field is `prompt` (the docs' `user_prompt` is still accepted as a fallback). There is **no prompt id** in the payload (the hook's own `toolUseID` is a fresh random UUID that is not passed in) |
| `PreToolUse` (matcher `Agent\|Task`) | CONFIRMED | binary: `{…,hook_event_name:"PreToolUse",tool_name,tool_input,tool_use_id}`; already used by `guard-track-branch-label.sh` |
| `SubagentStart` | CONFIRMED in the binary only | binary: `{…,hook_event_name:"SubagentStart",agent_id,agent_type}` with `toolUseID: <fresh randomUUID>` — **it carries no reference to the dispatch's `tool_use_id`** |
| `SubagentStop` | CONFIRMED (docs + binary) | binary: `{…,"SubagentStop",agent_id,agent_transcript_path,agent_type,…}` |
| `Stop` | CONFIRMED | docs + binary |
| `SessionEnd` | CONFIRMED (docs + binary) | binary: "JSON with session end reason" |
| `PostModelSwitch` | CONFIRMED in the binary only (hence opt-in) | binary: "After the session model changes (any cause) — JSON with from_model, to_model, requested_model, source …" |
| `statusLine` (settings key) | CONFIRMED to exist; its schema `{type:"command",command}` is from Claude Code convention | the renderer is another stream's work |
| correlation `tool_use_id` ↔ `agent_id` | **CONFIRMED NOT AVAILABLE** | SubagentStart's id is random (above). Pairing therefore uses `agent_type` only: exactly ONE pending registration of that type ⇒ paired; two or more ⇒ **ambiguous, nothing is paired** (no guess) — see §3 |
| hook `timeout` field (seconds) | CONFIRMED by the plugin-dev docs | the installer writes `"timeout": 5` (an operator's own value is kept on refresh) |
| `additionalContext` output | CONFIRMED | binary strings `hookSpecificOutput` / `additionalContext`; "Exit code 0 - stdout shown to Claude" |
| same command in user AND project scope | CONFIRMED to fire twice | Claude Code de-duplicates only textually identical commands; the installer's user-scope (absolute) and project-scope (`$CLAUDE_PROJECT_DIR`) commands differ, so both fire. The hooks are idempotent under double firing (§3) and the installer refuses to wire the second scope without `--allow-both-scopes` (§6) |

## 3. Every hook, event and payload field used

All scripts live in `scripts/label-sync/hooks/` and share `label-sync-lib.sh`.

**Ids from stdin.** `session_id`, `agent_id` and `tool_use_id` become file names under
`$LABEL_SYNC_DIR/hooks/` and entity ids, so each is accepted only if it matches
`^[A-Za-z0-9_-]{1,128}$` — checked inside `jq` on the raw JSON string with `\A…\z`
anchors (Oniguruma's `^`/`$` are line anchors, and bash would silently turn
`"a\u0000b"` into the valid-looking `ab`). A payload with any unsafe id, or with no
session id at all, makes the hook a silent no-op. No hook removes a stdin-derived
path recursively: SessionEnd unlinks the regular files of its own fixed layout one
by one and `rmdir`s the directory.

**Binding (CONTRACT rev 2 §4.2).** A session is registered **pinned** to the alias the
canonical labeler derives from this process (`CLAUDE_CONFIG_DIR`): two terminals on
two aliases each keep their own label in the statusline **and in the
`additionalContext` line the model sees**, through any number of `alias_switch`
events. A labelled subagent pins its own (guard-validated) triple; an alias-less one
inherits its session's binding. Only an alias-less ROOT entity follows the operator's
active context. **No hook reads or writes `active.json`.**

| Script | Event / matcher | Payload fields read | Effect |
|---|---|---|---|
| `label-sync-session-start.sh` | `SessionStart` `*` | `session_id`, `cwd`, `source`, `model` | `register --kind session` with `--session`, `--cwd`, the pid of the owning `claude` process, track/branch/alias/model/effort from the canonical labeler (`scripts/multitrack/track_branch_label.sh`, run with `CLAUDE_CODE_SESSION_ID` exported), `--follow-active false` when an alias was derived. A string `model` in the payload wins over the labeler's transcript lookup. Resumed under another alias ⇒ simply re-pinned; the core re-renders the subtree. Output: `additionalContext` with the label `register` printed. |
| `label-sync-prompt.sh` | `UserPromptSubmit` | `session_id`, `cwd`, `prompt` | ledger row (§5, opt-in); ONE `update --state running` that re-asserts the derived fields **and the pinned binding** (`--alias A --follow-active false`); re-registers if the entity is missing; `additionalContext` = the effective label `update` printed. |
| `label-sync-agent-register.sh` | `PreToolUse` `Agent\|Task` | `tool_name`, `tool_use_id`, `tool_input.description`, `tool_input.subagent_type`, `tool_input.model`, optional `agent_id` | parses the `(T<N>/<branch> - <alias>[ - <model>[ - <effort>]])` prefix; registers `subagent:<tool_use_id>` under the session (or under the PAIRED subagent when the payload's `agent_id` belongs to one — a nested dispatch); writes `pending/<sid>/<tool_use_id>` (entity id, subagent_type). Keyed by `tool_use_id`, so a double delivery is one registration; an absent id gets a deterministic hash, never a time-based one. Never blocks, prints nothing. **Composition with `guard-track-branch-label.sh`**: the guard (unchanged) blocks unlabelled and stale-alias dispatches; this hook registers only a dispatch the guard will allow. |
| `label-sync-subagent-start.sh` | `SubagentStart` | `session_id`, `agent_id`, `agent_type` | candidates = pending registrations whose `subagent_type` equals `agent_type` (an empty type on either side matches): exactly one ⇒ `agentmap/<agent_id>` (entity id, session id); **two or more ⇒ AMBIGUOUS: nothing is paired**; an `agent_id` already paired ⇒ no-op (double delivery never re-pairs). |
| `label-sync-subagent-stop.sh` | `SubagentStop` | `session_id`, `agent_id` | `unregister` (state `done`) the paired entity; an unpaired/ambiguous agent changes nothing. |
| `label-sync-stop.sh` | `Stop` | `session_id` | session `idle`; unregisters every pending (never paired) registration — this is where AMBIGUOUS registrations end. A busy writer lock (exit 2) ends the hook at once. |
| `label-sync-session-end.sh` | `SessionEnd` | `session_id`, `reason` | every entity of the session `done`; drops the session's pending files and agentmap entries. |
| `label-sync-model-switch.sh` | `PostModelSwitch` (opt-in) | `session_id`, `to_model`, `transcript_path` | session `--model` updated at once AND recorded in `hooks/modelswitch/<sid>` as `<model> <transcript byte size> <transcript path>`: every later prompt / re-asserting hook keeps the switched model until an assistant entry APPENDED AFTER that offset shows the model actually answering (then the record is dropped); a `"model":"<synthetic>"` entry (written by the client for API errors, `isApiErrorMessage`) is never that proof, and the labeler skips it too (re-review finding 4). The transcript's last assistant entry predates the switch, so without the record the next prompt undid it (review-2 finding 3). An unknown transcript keeps the record until the next `SessionStart` (with a model), switch or `SessionEnd`. |
| `label-sync-alias-switch.sh` | not an event hook (CLI) | args | see §4. |
| `request_history_append.sh` | called by the prompt hook, or run directly | stdin JSON or function args | see §5. |

Hook-private correlation state lives in `$LABEL_SYNC_DIR/hooks/{pending,agentmap,ledger-last}/` (mode 0700).

**Parallel same-type dispatches and `Stop` — what is KNOWN and what is NOT (review-2 finding 15).**

| Question | Status | Basis |
|---|---|---|
| Does `SubagentStart` carry the dispatch's `tool_use_id`? | **KNOWN: no** | binary 2.1.296: its `toolUseID` is a fresh random UUID (§2) |
| Can two concurrently pending dispatches of the SAME `subagent_type` be told apart at `SubagentStart`? | **KNOWN: not from the payload** | only `agent_type` correlates; ≥ 2 candidates ⇒ nothing is paired (never a guess) |
| What an unpaired registration shows | **KNOWN (tested, §14)** | `running` with its correct label until `Stop`/`SessionEnd` marks it `done`; a wrong pairing would mark the WRONG dispatch done — an unpaired one is merely late |
| Does `SubagentStop` fire for a subagent that is cancelled / errors / is killed? | **UNKNOWN** | not observed in a live session; if it does not, the entity stays `running` until `Stop` / `SessionEnd` / the stale sweeper (CONTRACT §6) |
| Does `Stop` fire before BACKGROUND subagents finish? | **UNKNOWN** | not observed; `Stop` only unregisters PENDING (never-started) dispatches, so an adopted, still-running subagent is left alone either way |
| Order of `SubagentStart` for N parallel dispatches vs their `PreToolUse` order | **UNKNOWN** | no ordering guarantee is documented; the hooks do not rely on one |
| Are two hook invocations for the same event serialised? | **UNKNOWN** | the hooks assume NOT: pairing runs under `flock` and every write is idempotent (§14) |

Nothing in this table was observed in a live Claude Code session (§2); every
UNKNOWN row is a candidate for a recorded observation, not a guess.

## 4. The alias-switch signal and the claude toolkit

`scripts/label-sync/hooks/label-sync-alias-switch.sh <alias> [--model M] [--effort E]`
calls `labelctl switch-alias`. Every alias-less FOLLOWER entity re-renders on the next
snapshot (CONTRACT §4.1). Sessions are not affected: they are pinned to their own
alias (§3). Exit 0 published, 1 rejected, 2 usage / cannot determine.

`scripts/label-sync/toolkit/cma_label_hook.sh` is a **sourceable** wrapper for the
claude-multi-account toolkit. It wraps the two launchers `cma_run` (native
`claudeN`, alias from `$CLAUDE_CONFIG_DIR`) and `cma_run_provider` (provider
alias = the provider id; model = the `CMA_PROVIDER_MODEL` line of that provider's
`.env`, extracted with `sed`, the rest of the file — including API keys — is never
read or printed). On every launch or resume it publishes the alias switch
**before** the real launcher runs, then calls the real launcher with unchanged
arguments, environment and working directory and returns its exit status. A
failure or absence of the label tooling never blocks a launch; on a host with no
built binary it only starts a detached background build. It probes the toolkit
with `typeset -f` (in zsh, `declare -F` would declare a FLOAT parameter); zsh is
not installed on the reference host, so the zsh path is UNCONFIRMED by execution.

**Sessions keep their own label — tested.** Suite section 13 launches terminal A
(claude1) and terminal B (claude2) through this wrapper, then publishes five alias
switches (claude3, claude1, claude2+sonnet, deepseek, claude4): after each one,
A's entity, A's statusline and A's `additionalContext` show claude1 and B's show
claude2, A's alias-less subagent shows claude1, and an alias-less root follower
shows the last switch.

**Install (text only — this stream does not edit anything under `$HOME`).** Add
one line to `~/.bashrc` (or `~/.zshrc`) **after** the line that sources
`~/.local/share/claude-multi-account/aliases.sh`:

```bash
source /home/<you>/Projects/<project>/submodules/constitution/scripts/label-sync/toolkit/cma_label_hook.sh
```

It is idempotent. If `aliases.sh` is re-sourced later (which redefines the
launchers), call `cma_label_hook_rewrap` or source the file again. To remove it,
delete that line and re-source `aliases.sh`.

## 5. The request-history ledger

`request_history_append.sh` is the §11.4.208 auto-capture helper. One JSON object per
prompt, appended under an `flock` held in the state dir (never next to the ledger):

```json
{"accepted":"2026-10-12T13:40:58+0200","timezone":"CEST","session_id":"…","prompt":"…",
 "prompt_kind":"verbatim","prompt_bytes":12,"prompt_sha256":"…","redactions":0,
 "track":"1","alias":"claude2","model":"opus","effort":"UNKNOWN","cwd":"…","source":"label-sync-prompt-hook"}
```

* **Opt-in only.** The ledger exists only where `LABEL_SYNC_REQUEST_LEDGER` names it
  (relative ⇒ against `$CLAUDE_PROJECT_DIR`), or where
  `install_label_sync.sh --request-ledger PATH` wrote that variable into the settings'
  `env`. An existing `docs/requests/` directory no longer creates one (it used to,
  which gave projects with their own `request_history.md` a divergent second ledger,
  one per worktree).
* **Secrets are redacted before the append (§11.4.10).** GitHub
  (`ghp_ gho_ ghu_ ghs_ ghr_ github_pat_`), GitLab (`glpat-`), Slack (`xox?-`), AWS key
  ids (`AKIA`/`ASIA`), `sk-…` API keys, PEM `PRIVATE KEY` blocks, and
  `password|passwd|pwd|secret|client_secret|token|api_key|access_key|private_key = value`
  pairs become `[REDACTED:<kind>]`; `redactions` records how many, and the row is then
  `prompt_kind: "verbatim-redacted"`. §11.4.208 mandates storing the text, so the rest
  is kept verbatim: **a ledger inside the repository is committed by any `git add .`
  wrapper** — the installer warns when the path is tracked-and-not-ignored (§6).
* **Large prompts are never lost.** The text never travels as a command argument
  (Linux refuses one argument ≥ 128 KiB with E2BIG — a 131072-byte prompt used to be
  dropped silently with exit 0). A prompt over 65536 characters is not even copied into
  a shell variable: `jq -j` streams it from the payload into a 0600 temp file in the
  state dir; smaller ones reach the row builder through a pipe. ONE `perl` process
  (core `Digest::SHA`) redacts, hashes, de-duplicates, appends and updates the
  markdown twin. Measured through the real hook via a pipe (2026-10-12, load ≈ 12):
  131072 B in 175 ms, 1 MiB in 242 ms, 8 MiB in 1448 ms — all byte-identical (sha256).
* **Failure is never silent.** If the append fails, a row with `prompt: null`,
  `prompt_kind: "lost"`, `prompt_sha256`, `prompt_bytes` and `reason` is appended
  instead; `$LABEL_SYNC_DIR/hooks/ledger-failures.count` is incremented; with
  `LABEL_SYNC_DEBUG=1` a line reaches the hook's stderr. No redactor (`perl` absent)
  ⇒ `prompt_kind: "withheld"` (the text is never written unredacted). Above
  `LABEL_SYNC_LEDGER_MAX_BYTES` (default 16 MiB) ⇒ `prompt_kind: "oversize"`, text not
  stored, hash and size are.
* **Exactly once per delivery:** the same session + prompt sha256 within
  `LABEL_SYNC_LEDGER_DEDUPE_MS` (default 2000 ms) is one event (a hook wired in two
  settings files); the dedupe state holds the hash, never the text; different sessions
  never de-duplicate each other. **Limit (§11.4.6):** the payload carries no prompt id
  (§2), so an operator genuinely re-sending the identical prompt inside the window is
  recorded once.
* **Markdown twin (optional, bounded).** If `history.md` next to the ledger contains
  `<!-- label-sync:request-history:insert -->`, a newest-first block is inserted after
  it — at most `LABEL_SYNC_LEDGER_MD_PROMPT_MAX` bytes of text (default 4096, then a
  pointer to the jsonl row), and the twin is no longer rewritten once it exceeds
  `LABEL_SYNC_LEDGER_MD_MAX` bytes (default 1 MiB; counted in
  `ledger-md-skipped.count`). The jsonl is append-only.
* The `.html/.pdf/.docx` exports (§11.4.65) remain the project's docs-chain job. The
  ledger works with no daemon and no built binary.

## 6. The installer

`scripts/label-sync/install_label_sync.sh` merges the hook entries and the
`statusLine` entry into a target settings file. **Default is `--dry-run`**
(prints a unified diff, writes nothing).

```
install_label_sync.sh [--apply | --dry-run] [--platform claude|all]
    [--scope project|user] [--project-root DIR] [--home DIR | --config-dir DIR | --settings FILE]
    [--constitution-root DIR] [--render-path FILE] [--no-statusline] [--force-statusline]
    [--with-model-switch] [--request-ledger PATH] [--other-settings FILE]... [--allow-both-scopes]
    [--uninstall] [--brief]
```

* **Target:** `--scope project` (default) = `<project-root>/.claude/settings.json`, hook
  commands written as `bash "$CLAUDE_PROJECT_DIR/<path>/scripts/label-sync/hooks/…"` when the
  constitution lives inside the project (by reference, never copied); `--scope user` =
  `<config-dir>/settings.json` (`--config-dir`, else `$CLAUDE_CONFIG_DIR`, else `<home>/.claude`)
  with absolute paths; `--home DIR` re-points `$HOME` for tests.
* **Merge rules:** every existing key and hook is preserved; an entry of ours is recognised by
  its script name, de-duplicated and refreshed in place — **keeping an operator's `timeout`, any
  extra keys and a leading `VAR=value …` command prefix**; re-applying yields a byte-identical
  file and no extra backup; a foreign `statusLine` is never clobbered nor removed by
  `--uninstall`; `PostModelSwitch` only with `--with-model-switch`.
* **statusLine in project scope needs `--force-statusline`:** project settings take
  precedence over every contributor's personal statusLine, so without the flag the hooks are
  wired and the statusLine is left alone (warning). User scope wires it normally.
* **Both scopes:** if the OTHER scope (default: the user settings for `--scope project`; the
  project's `settings.json`/`settings.local.json` for `--scope user` when a project root is
  given; or explicit `--other-settings FILE`) already carries label-sync hooks, every hook would
  fire twice: dry-run warns, `--apply` is refused (exit 2) unless `--allow-both-scopes`.
* **`--request-ledger PATH`** writes `env.LABEL_SYNC_REQUEST_LEDGER` (the §5 opt-in) and warns
  when PATH is inside a git work tree and not git-ignored. `--uninstall` leaves `env` alone.
* **Safety:** refuses (exit 1) a settings file that is not a valid JSON object; refuses (exit 2)
  a constitution/renderer path containing `$` `` ` `` `"` `\` or a newline — inside the
  double-quoted hook command they would be INTERPRETED (`$(…)` executed) when the hook runs;
  takes an `flock` on the settings directory for the whole read-modify-write
  (`LABEL_SYNC_INSTALL_LOCK_WAIT`, default 10 s, then exit 2); writes a backup
  `settings.json.label-sync.bak.<UTC-ts>` before the first change; writes a temp file next to the
  REAL file (a symlinked `settings.json` stays a symlink, its target is written) seeded with
  `cp -p` so the mode is preserved, then `mv`; asserts at `--apply` time (exit 2, nothing written)
  that every hook script (incl. `label-sync-model-switch.sh` with `--with-model-switch`) and the
  statusLine renderer exist.
* **`--platform all`** also reports opencode / gemini / qwen as not wired (no Claude-style hook
  interface) — an honest skip.

## 7. Auto-wiring on constitution pull

`scripts/post_update_hook.sh` (§11.4.164) has **step 4c**. When a pull changes anything under
`scripts/label-sync/` or the labeler, it runs the installer against `$PROJECT_ROOT`:

| `LABEL_SYNC_AUTOWIRE` | Behaviour |
|---|---|
| unset / `dry-run` (default) | `--dry-run --brief`: records what **would** be wired, writes nothing |
| `apply` | writes (with backup), idempotent; hooks only — the statusLine is project scope and needs `--force-statusline`, i.e. a manual installer run |
| `off` | skipped |

Step 4c never returns non-zero (an installer refusal is a WARNING), and step 4 (git hooks)
no longer aborts the run before it: the hooks directory is asked from git
(`git rev-parse --path-format=absolute --git-path hooks`, which is correct for worktrees and
submodule checkouts and honours `core.hooksPath`), a non-git root is a warning, and only real
git hook names are installed — `guard-*.sh` and `test_*.sh` from `scripts/hooks/` are never
copied into `.git/hooks`. (Steps 4b and earlier are owned by other streams; see §11 for the
one that can still abort the script.)

**Revision 4 (review-2 C, D, E, L; re-review 1, 3, 11).** Every step of
`post_update_hook.sh` runs through `run_step`, which runs the step in a
subshell under `set -e` — errexit is ACTIVE for every command inside the step.
(Revision 3 called the step as `"$fn" || rc=$?`, which turns errexit OFF for
everything inside it: a changed skill whose `ln` failed with `Permission denied`
printed "Linked", "completed successfully" and exit 0 with no link — re-review
finding 1.) The FIRST failing command ends the step; the step's WARNINGS and
ERRORS come back to the hook through a private temp dir; a step that ends
non-zero is recorded as an ERROR — the hook exits 1 and the summary says
"completed with errors" — and the next step still runs. `exit` and an unset
variable (`set -u`) inside a step end only that step; a SIGNAL can still end
the whole hook (nothing in-process can contain it). The stricter run exposed
one step that ended early: step 5 used to stop after the FIRST broken script
(`bash -n … | while` returns non-zero under `pipefail`); it now reports every
broken script. An unparseable consumer `.mcp.json` is left untouched with a
warning. Test-only fault seams, honoured ONLY with
`POST_UPDATE_HOOK_TEST_MODE=1`: `POST_UPDATE_HOOK_FAULT_STEP=<step>` (the real
step runs, then its status is forced to 97) and `POST_UPDATE_HOOK_FAULT_EXIT=<step>`
(the step's subshell runs `exit 7`). Suite §20 and §22 assert all of this,
including a real mid-step failure (a consumer `skills/` directory of mode 555).

Step 3 rewrites an MCP config path that exists only under the constitution
(e.g. `scripts/label-sync/mcp/label-mcp.sh`) to
`<constitution-dir-relative-to-project>/<path>` (absolute when the
constitution lives outside the project). Because Claude Code spawns the
command relative to the directory it was started in (measured by the
re-review with Claude Code 2.1.300; `${CLAUDE_PROJECT_DIR}` is not expanded in
`.mcp.json`), a relative entry is wrapped in `sh -c` that walks up from `$PWD`
to the directory holding the vendored constitution, `cd`s there and `exec`s the
server — see MCP.md. **Step 4d**
runs `scripts/label-sync/adapters/install_adapters.sh` when adapter files changed:

| `LABEL_SYNC_ADAPTERS` | Behaviour |
|---|---|
| unset / `dry-run` (default) | records what would be wired into the USER's agent configs; writes nothing |
| `apply` | wires the detected agents (backup, exact rollback, see ADAPTERS.md §4) |
| `off` | skipped |

Step 5 also syntax-checks every changed `scripts/label-sync/**/*.sh` (they were classified as
label-sync changes and skipped).

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
| `LABEL_SYNC_HOOK_LOCK_TIMEOUT` | writer-lock wait per `labelctl` call from a hook (default `500ms`) |
| `LABEL_SYNC_REQUEST_LEDGER` | the ledger path (opt-in; relative ⇒ against `$CLAUDE_PROJECT_DIR`) |
| `LABEL_SYNC_LEDGER_DEDUPE_MS`, `LABEL_SYNC_LEDGER_MAX_BYTES`, `LABEL_SYNC_LEDGER_MD_MAX`, `LABEL_SYNC_LEDGER_MD_PROMPT_MAX` | dedupe window (2000), oversize bound (16 MiB), twin rewrite bound (1 MiB), twin excerpt (4096) |
| `LABEL_SYNC_CTL_TIMEOUT` | optional per-`labelctl` `timeout(1)` (off by default, see §10) |
| `LABEL_SYNC_DEBUG=1` | hook stderr passes through (lost/withheld ledger rows are reported there) |
| `LABEL_SYNC_HOOK_DEBUG=1`, `LABEL_SYNC_HOOK_STDERR=<file>` | diagnostics to `hooks/debug.log` / hook stderr to a file |
| `LABEL_SYNC_INSTALL_LOCK_WAIT` | installer: seconds to wait for the settings-dir lock (10) |
| `LABEL_SYNC_AUTOWIRE` | `dry-run` (default) / `apply` / `off` for `post_update_hook.sh` |
| `LABEL_SYNC_ADAPTERS` | `dry-run` (default) / `apply` / `off` for `post_update_hook.sh` step 4d (CLI-agent adapters) |

Removed in revision 2: `LABEL_SYNC_NO_SWITCH_ON_RESUME` (hooks no longer publish an alias
switch on resume — the session simply re-pins).

## 10. Performance, failure behaviour, limits

* **Latency** (median of 5, loaded host, load average ≈ 12, 2026-10-12, suite section 8):
  `UserPromptSubmit` 100 ms, `SessionStart` 75 ms, `PreToolUse` register 58 ms, `Stop` 42 ms,
  `SubagentStop` 34 ms; runs vary ±40 ms with load; the bound asserted by the suite is 150 ms
  (`LS_LATENCY_MS`). Since revision 3 the bound is LOAD-AWARE: it is applied to the wall-clock
  median on an uncontended host exactly as before; only when CPU contention is MEASURED during
  the run (the suite's own cgroup was throttled — `nr_throttled` grew — or cpu PSI `some avg10`
  ≥ 10) is it applied to the hooks' CPU time (user+sys of the hook and all children) instead,
  and the PASS line says so (review-2 finding L: 3 latency failures under a CPU-limited
  scope). Measured 2026-10-14 (uncontended): prompt 112 ms, SessionStart 94 ms, register
  72 ms, Stop 56 ms, SubagentStop 36 ms. One profiled `UserPromptSubmit` (timestamped xtrace, 88 ms): labeler 22 ms,
  flock + perl row builder 20 ms, `labelctl update` 8 ms, payload `jq` 6 ms, `cat` 5 ms. Rules
  that keep it there: no external process a builtin can replace; one `jq` for the payload;
  `register`/`update` print the rendered label, so no separate `labelctl label`; the
  binary-staleness `find` runs at most once per 60 s; **no `timeout(1)` wrapper** (on this host's
  coreutils it adds a flat 100 ms) — the outer bound is the 5 s `timeout` in settings.json.
* **Writer lock:** every `labelctl` call from a hook passes `--lock-timeout 500ms`; a busy lock
  (exit 2) ends the hook (no retry/re-register). Measured with the lock held by another
  process: `UserPromptSubmit` 599 ms, `Stop` 552 ms (was 3.7 s with the core's 2 s default).
  The `labelctl` child is waited for synchronously, so a hook killed mid-call leaves no
  `labelctl` behind beyond that bound (asserted 1.2 s after a SIGTERM).
* **Bus down / binary missing / state dir unusable / garbage stdin / empty stdin / unsafe id:**
  exit 0, no output (suite sections 7 and 12). A missing binary starts one detached, niced,
  rate-limited background build.
* **Limits (§11.4.6):** parallel same-type subagent dispatches stay unpaired until Stop/SessionEnd
  (§3); a genuinely identical prompt re-sent within 2 s is recorded once (§5); the model of a
  background subagent introspecting its own transcript is the labeler's documented open
  limitation; the `UserPromptSubmit` additionalContext line adds ~25 tokens per prompt; live
  delivery of any hook in a real session was not observed by this stream.

## 11. Review findings addressed (revision 2)

The independent review of revision 1 returned NO-GO. Each finding was reproduced with a failing
test BEFORE the fix (suite sections named), then fixed:

| # | Finding | RED evidence | Fix |
|---|---|---|---|
| 1 | the GLOBAL active alias overwrote each session's alias — terminal A on claude1 showed (and injected into its model) claude2 | §13: A's entity/statusline/additionalContext showed claude2, then every later switch | sessions pinned to the derived alias; prompt hook re-asserts it in its one update; hooks never touch `active.json` |
| 2 | prompts ≥ 128 KiB silently dropped from the ledger (E2BIG) | §15: 131072 B / 1 MiB / 8 MiB ⇒ 0 rows, exit 0; 8 MiB took 3.4–7.1 s | no argv, no shell copy for large prompts; one perl process; `lost`/`withheld`/`oversize` rows + counter + stderr |
| 3 | path traversal via `session_id` / `agent_id` (`rm -rf` of a stdin path) | §12: a SessionEnd with `../../../victim/keep` DELETED that directory; a SubagentStop deleted a file | ids validated in jq (`\A…\z`); no recursive removal of stdin-derived paths |
| 4 | parallel same-type dispatches paired with the wrong registration | §14: an unpaired agent's SubagentStop marked the wrong dispatch `done` | ≥ 2 candidates ⇒ not paired (documented) |
| 5 | user + project scope ⇒ every hook fires twice | §14: two pending files for one dispatch | pending keyed by `tool_use_id`; repeated SubagentStart is a no-op; installer refuses the second scope (§18) |
| 6 | `post_update_hook.sh` aborted before step 4c in a worktree; copied non-hooks into `.git/hooks` | §17: exit 1, step 4c never ran | `--git-path hooks`, never non-zero, only git hook names |
| 7 | ledger auto-created from `docs/requests/`; prompts (with secrets) committed | §2/§15: ledger appeared without opt-in; tokens stored verbatim | opt-in only; redaction with count; installer `--request-ledger` + tracked-path warning |
| 8 | installer: customisation dropped, symlink replaced, mode changed, missing model-switch accepted, `$(…)` in path, project statusLine override, no lock | §18 | all fixed as listed in §6 |
| 9 | a stuck writer lock delayed a prompt by seconds | §13b: 3.7 s with the lock held | `--lock-timeout 500ms`; no retry on exit 2 |
| 10 | six reviewer mutants survived | — | killed; `hook_mutants.py` now holds 36 mutants incl. one per new mechanism |
| 11 | docs/limits | binary re-read | §2 CONFIRMED/UNCONFIRMED updated; SessionStart `model` used; zsh `declare -F` fixed; twin bounded; dedupe limit documented |

**Not fixed here (owned elsewhere):** `post_update_hook.sh` step 4b (`install_action_plugins`)
still returns 1 when its installer is missing, which under `set -e` would abort the script
before step 4c; that step belongs to another stream.

## 12. Second-review fixes (revision 3)

| # | Finding | Fix | Test |
|---|---|---|---|
| 1 | a branch named `fix(ui)` (legal) made every parser drop the alias: the session followed the ACTIVE alias, `--derive` exited 2, SessionStart still said "pinned" | the canonical labeler maps `)` and ` - ` (and line controls) in a field to `_`, exactly like `label.Compose`; SessionStart says "pinned" only when an alias was derived, else "follows the operator's active alias" | §19: `fix(ui)`, `q"uote`, unicode, 200-char branch; alias-less session wording |
| 2 | gate exit PASS when jq/go/python3 absent; suite exit 2 reported as FAIL | `CM-LABEL-SYNC-HOOKS` exits 2 (CANNOT DETERMINE) for both | meta-test cases 14-16 |
| 3 | `PostModelSwitch` undone by the next prompt | switch record + transcript offset (§3) | §19 F3 |
| 10 | the `"` escape in `ls_emit_context` untested (mutant B2 survived) | test with branch `q"uote` | §19 F10 + mutant `emit_context_no_quote_escape` |
| 13 | one binary cache for every checkout | per-checkout key + `.source-commit` (CONTRACT §7) | §21 |
| 15 | parallel same-type pairing / Stop semantics UNCONFIRMED | known/unknown table (§3) | — (documentation) |
| C/D/E/L | post-update aborts, unresolvable MCP path, adapters never wired, label-sync scripts not syntax-checked, latency asserts not load-aware | §7 revision 3, §10 | §20, §8 |

