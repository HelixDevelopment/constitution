# label-sync renderers

| Field | Value |
|---|---|
| Document | `docs/label-sync/RENDERERS.md` |
| Revision | 1 (2026-10-12) |
| Status | implemented and tested on branch `feature/label-sync` (local, unpushed); zsh + fish integrations written but NOT executed (UNCONFIRMED, see §9) |
| Implements | §11.4.182 (label shown everywhere, real-time, always in sync), §11.4.116, §11.4.18 |
| Code | `scripts/label-sync/render/` |
| Consumes | `docs/label-sync/CONTRACT.md` (state dir, `snapshot.json`, `seq`, follow rules, stale rule) |

The renderers DISPLAY the labels the label-sync core computes. They never
compute a label themselves: every value shown is read from `snapshot.json` (the
atomically replaced view) or, when no snapshot exists, derived by the canonical
labeler `scripts/multitrack/track_branch_label.sh` and marked `[derived:...]`.
Unknown is printed as `?`, never guessed (§11.4.6). Switching the alias
(`labelctl switch-alias`) rewrites the snapshot in the same transaction, so the
very next render of every follower shows the new alias — no renderer caches it
(the one exception is the optional 5 s cache of the DERIVED fallback, §3).

**This document gives install instructions as TEXT only.** Nothing in this
repository edits `~/.bashrc`, `~/.zshrc`, `~/.config/fish`, `~/.tmux.conf`,
`~/.claude*/settings.json` or any file outside the repo; an installer is a
separate stream's job (§11.4.164 / §11.4.228). Replace `<C>` below with the
absolute path of the constitution checkout (`…/constitution` or
`…/submodules/constitution`).

## 1. Files

| File | Role |
|---|---|
| `render/lib.sh` | shared helpers (state dir, snapshot lookup, safe OSC title emitter) — sourced |
| `render/statusline.sh` | Claude Code `statusLine` command |
| `render/title.sh` | set the terminal title (OSC 0) from the snapshot or a text |
| `render/shell-integration.bash` / `.zsh` / `.fish` | prompt-time title + PS1 segment; registers the shell and each command |
| `render/shell-hook.sh` | the single background worker behind the three integrations (owns the secret policy) |
| `render/tmux-status.sh` | label for tmux `status-right` / `status-left` |
| `render/labelrun` | wrapper registering a command/flow entity around any command |
| `render/watch-labels.sh` | live operator table of all entities, grouped by alias |
| `render/prove_mutations.sh` | §1.1 paired-mutation proof (8 mutants) |
| `render/tests/test_render.sh` | the test suite (78 cases) |
| `scripts/gates/cm_label_sync_render.sh` (+ `_mutation_test.sh`) | `CM-LABEL-SYNC-RENDER` gate |

## 2. Claude Code statusLine (`statusline.sh`)

Prints ONE line, always exit 0, stderr silent:

```
(T3/main - claude2 - sonnet - xhigh)            live reading from the snapshot
(T3/main - claude2 - sonnet - xhigh) [stale]    entity stopped heartbeating (CONTRACT §6)
(T3/main - claude2 - sonnet - xhigh) [done]     session was unregistered
(T4/x - claude7 - opus - high) [derived:no-state]   no snapshot: derived from the live process
(T?/? - ? - ? - ?) [no-session]                 state exists, no entity for this session
(T?/? - ? - ? - ?) [no-state]                   no readable snapshot (bus/state down) and no labeler answer
```

Install (text; per Claude config dir, i.e. once per alias that should show it —
the script itself is alias-agnostic because the snapshot already carries each
session's own alias):

```json
{ "statusLine": { "type": "command", "command": "bash <C>/scripts/label-sync/render/statusline.sh" } }
```

The session is found by the `session_id` field of the stdin JSON (entities
registered with `labelctl register --kind session --session <id>`; the SessionStart
hook stream registers them). Cost: one `jq` fork on the snapshot; measured
average 30–49 ms per call on a host at load average ~20 (`METRIC statusline_avg_ms`
in the test output; asserted < 100 ms). The derived fallback additionally forks
the labeler (bounded by `timeout 1`) and is cached 5 s per session
(`LABEL_SYNC_STATUSLINE_CACHE_TTL`, `0` = off, `LABEL_SYNC_STATUSLINE_DERIVE=0` =
never derive). Environment: `LABEL_SYNC_DIR`, `LABEL_SYNC_LABELER`,
`LABEL_SYNC_CACHE_DIR`.

## 3. Terminal title (`title.sh`) and shell integration

`title.sh [--text T | --entity ID | --session SID] [--sink FILE] [--passthrough]`
emits OSC 0 (`ESC ] 0 ; <text> BEL`). Safe by construction:

* all control characters are stripped from the text (a branch name can never
  inject an escape sequence);
* **non-tty safe**: with no `--sink`, bytes go to stdout/stderr ONLY if that fd is
  a tty; otherwise nothing is written and the exit code is 0;
* `TERM=dumb` → no-op;
* **tmux**: plain OSC is accepted by tmux (it sets the pane title; with
  `set -g set-titles on` + `set-titles-string '#T'` the outer terminal title
  follows). `--passthrough` additionally wraps it in tmux's DCS passthrough
  (`ESC P tmux ; ESC <seq with ESC doubled> ESC \`) — needs
  `set -g allow-passthrough on`;
* **GNU screen** (`$STY` set): the window-name sequence `ESC k … ESC \` is added.

### bash — `shell-integration.bash`

Add to `~/.bashrc` (text only, nothing edits it for you):

```bash
source <C>/scripts/label-sync/render/shell-integration.bash
# optional: show the label in the prompt too
# LABEL_SYNC_PS1=1 source <C>/scripts/label-sync/render/shell-integration.bash
```

What it does, and what it costs (measured, `tests/test_render.sh`, `METRIC` lines):

| Path | Cost | Bound asserted |
|---|---|---|
| prompt, `seq` unchanged | one builtin `read` + string compare, no fork: ~170–220 µs per prompt | < 5 ms |
| prompt, `seq` changed | one `jq` fork + (only if the label text changed) one title write: ~8–12 ms | < 100 ms |
| per command (DEBUG trap) | a function call, ~70–100 µs | < 2 ms |
| registration / heartbeat / unregister | detached background process (`setsid`, `( … & )`); the prompt never waits | — |
| state dir missing/unusable | prompt hook returns rc 0 immediately, no output | < 100 ms |

* the shell is registered as a `shell` entity (`id = shell-<host>-<pid>-<epoch>`,
  exported as `LABEL_SYNC_SHELL_ID` so `labelrun` and child tools nest under it),
  heartbeated every `LABEL_SYNC_HEARTBEAT` s (default 30) and unregistered on exit;
* the first command of each prompt cycle is registered as a `command` entity,
  rate-capped by `LABEL_SYNC_CMD_MIN_INTERVAL` (default 1 s), ended at the next
  prompt (or at shell exit);
* title/PS1 refresh happens only when the `seq` file changed (alias switch,
  any entity change) — `LABEL_SYNC_TITLE_SINK=FILE` redirects title bytes (tests);
* existing `PROMPT_COMMAND` (string or array), `DEBUG` and `EXIT` traps are chained,
  and sourcing twice is a no-op.

### zsh / fish — UNCONFIRMED

`shell-integration.zsh` (precmd/preexec/zshexit via `add-zsh-hook`) and
`shell-integration.fish` (`fish_prompt` / `fish_preexec` / `fish_exit` events) mirror
the bash behaviour and call the same `shell-hook.sh`. They were written against
the documented hook APIs but **not executed**: neither zsh nor fish is installed
on the host that built them (§9). Validate with `zsh -n` / `fish -n` and one manual
prompt cycle before relying on them.

### What is recorded about a command (secret policy)

`shell-hook.sh` is the one place that decides. The command text is read from
**STDIN only** (never an argument, so it is in no process listing). Recorded in the
entity's `source` field, exactly: `shell-integration:argv0=<argv0>:h=<digest>` where

* `argv0` = basename of the first word after any leading `VAR=value` assignments,
  restricted to `[A-Za-z0-9._+-]`, max 40 chars; a quoted assignment or an
  unparseable word gives `?` (fail closed);
* `digest` = first 12 hex chars of `sha256(SALT + full text)`; `SALT` is a per-shell
  random value exported only in the shell's environment, never written to disk,
  so the digest cannot be brute-forced from the state files — it only lets one
  shell recognise repeats.

No argument value, environment value, or command text is ever stored
(`tests/test_render.sh` C5–C6c plant `--token=…`, `PASSWORD=…` and an env-prefix
secret and grep `events.jsonl`, `snapshot.json`, `fold.json`). No repo-wide
command-redaction convention exists (`credential_scan_lib.sh` scans files, not
shell input), so the conservative argv0+digest rule is used.

## 4. tmux (`tmux-status.sh`)

Add to `~/.tmux.conf` (text only):

```tmux
set -g status-interval 1
set -g status-right '#(<C>/scripts/label-sync/render/tmux-status.sh --pane-pid #{pane_pid} --kind shell) '
# titles: let the pane title (set by the shell integration's OSC) reach the outer terminal
set -g set-titles on
set -g set-titles-string '#T'
# only if you use title.sh --passthrough:
# set -g allow-passthrough on
```

`--pane-pid` matches the shell entity registered with `--pid $$` (the shell
integrations do this); alternatives: `--entity ID`, `--session SID`, `--active`
(prints `alias model effort`). Unknown → `?`. `#` in the label is replaced by `_` so
the output can never be parsed as a tmux format/style (tested). GNU screen: the
title sequences above are emitted automatically; for a hardstatus line use
`backtick 1 1 1 <C>/scripts/label-sync/render/tmux-status.sh --pane-pid $$` style
polling (untested).

## 5. `labelrun`

```
labelrun [--kind command|flow] [--name NAME] -- cmd [args...]
```

Registers an entity under `$LABEL_SYNC_SHELL_ID` (or `$LABEL_SYNC_PARENT_ID`) and
the current `CLAUDE_CODE_SESSION_ID`, prints `labelrun: <label> <name>` on stderr
**only when stderr is a tty**, runs the command without `exec` (so it can clean
up), passes stdin/stdout/stderr through, propagates the exit code exactly
(0, 7, 127 not found, 143 for SIGTERM — tested), forwards SIGTERM/SIGINT/SIGHUP to
the single child pid it started (never a process group, §11.4.263) and marks the
entity `done` on every exit path. Fail-soft: if labelctl/state is unusable the command
still runs and its exit code is still propagated. A SIGKILL'd `labelrun` cannot
clean up; its entity goes stale on TTL (it carries labelrun's own pid, so it is
never stale while running). Command arguments are never recorded or printed.

## 6. `watch-labels.sh`

`watch-labels.sh [--once] [--interval-ms N] [--iterations N] [--timeout-s N] [--kind K]`
polls `seq` (no daemon needed) and, on change, clears (only on a tty) and redraws
a table: header `seq / active alias+model+effort / entity count`, then one group
per alias (`== alias: claude2 (3)`), one row per entity `id kind state label [stale]`.

## 7. Verification

```bash
bash scripts/label-sync/render/tests/test_render.sh          # 78 cases, ~10 s
bash scripts/label-sync/render/prove_mutations.sh            # 8 mutants, ~2 min, all must be KILLED
bash scripts/gates/cm_label_sync_render.sh                   # CM-LABEL-SYNC-RENDER
bash scripts/gates/cm_label_sync_render_mutation_test.sh     # gate's own paired mutation test
```

Run niced and one at a time on a loaded host (§12.6/§12.8). The tests use a temp
`LABEL_SYNC_DIR`, start/stop their own `label-busd`, and never write under `~/.claude*`.

## 8. Behaviour guarantees covered by tests

Alias switch changes the next statusline/title output (A2, C4); bus/state down →
rc 0 and an honest `?` + marker (A6, A7); staleness marker appears and clears on
heartbeat (A9); non-tty and `TERM=dumb` write nothing (B3, B4); escape injection
stripped (B2); unchanged `seq` does not rewrite the title (C3); no secret reaches
the state files (C6); prompt overhead bounds (C8); fail-soft with unusable state
(C9); `labelrun` exit-code, signal, cleanup, stdin and banner behaviour (D1–D11).

## 9. Honest boundary / UNCONFIRMED (§11.4.6)

* **Claude Code statusLine stdin schema — UNCONFIRMED against the docs.** The
  Claude Code documentation was not found in this host's plugin cache. The script
  reads only `session_id`, `workspace.current_dir` and `cwd` (defensively; anything
  missing is ignored and non-JSON input still exits 0). Verify the field names
  against the installed Claude Code version before relying on session matching.
* **zsh and fish integrations — written, not executed** (neither shell is
  installed on the build host).
* **tmux and GNU screen paths — not executed against a real tmux server** (tmux is
  not installed; the OSC/DCS byte sequences are asserted, the tmux behaviour is
  taken from its documentation). screen is installed but was not driven.
* The bash integration was exercised via a scripted shell calling the hook functions
  directly (a real interactive `PROMPT_COMMAND` cycle was not driven).
* The derived fallback labeler runs in the status line's cwd with the session id
  exported; its `<model>` for native aliases comes from the session transcript and
  may be `?` (the labeler's own honest limit, §11.4.182(5)).
* Terminal titles can be set only by a process attached to the terminal: the
  statusLine command runs with piped stdout, so titles come from the shell
  integration, not from `statusline.sh`.
