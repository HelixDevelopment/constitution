# label-sync renderers

| Field | Value |
|---|---|
| Document | `docs/label-sync/RENDERERS.md` |
| Revision | 2 (2026-10-12) — FIX-B1: strict sanitiser, argv0-only secret policy, Ctrl-C reaches labelrun's child, `$_`/errexit-safe hooks, no salt, derived-binding adaptation |
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
| `render/lib.sh` | shared helpers (state dir, snapshot lookup, safe OSC title emitter, THE output sanitiser `ls_sanitize`) — sourced |
| `render/statusline.sh` | Claude Code `statusLine` command |
| `render/title.sh` | set the terminal title (OSC 0) from the snapshot or a text |
| `render/shell-integration.bash` / `.zsh` / `.fish` | prompt-time title + PS1 segment; registers the shell and each command |
| `render/shell-hook.sh` | the single background worker behind the three integrations (owns the secret policy) |
| `render/tmux-status.sh` | label for tmux `status-right` / `status-left` |
| `render/labelrun` | wrapper registering a command/flow entity around any command |
| `render/watch-labels.sh` | live operator table of all entities, grouped by alias |
| `render/prove_mutations.sh` | §1.1 paired-mutation proof (23 mutants) |
| `render/tests/test_render.sh` | the test suite (165 cases) |
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
average 30–47 ms per call on this host at load average ~20 (`METRIC
statusline_avg_ms`; test A4 asserts the average of 20 calls is < 100 ms with
`label-busd` running — an average, not a per-call worst case). Every printed
byte passes `ls_sanitize` (§3.1). The derived fallback additionally forks
the labeler (bounded by `timeout 1`) and is cached 5 s per session
(`LABEL_SYNC_STATUSLINE_CACHE_TTL`, `0` = off, `LABEL_SYNC_STATUSLINE_DERIVE=0` =
never derive). Environment: `LABEL_SYNC_DIR`, `LABEL_SYNC_LABELER`,
`LABEL_SYNC_CACHE_DIR`.

## 3. Terminal title (`title.sh`) and shell integration

`title.sh [--text T | --entity ID | --session SID] [--sink FILE] [--passthrough]`
emits OSC 0 (`ESC ] 0 ; <text> BEL`). Safe by construction:

* the text passes `ls_sanitize` (§3.1) — no branch name, alias or label can
  inject an escape sequence, under any locale;
* **non-tty safe**: with no `--sink`, bytes go to stdout/stderr ONLY if that fd is
  a tty; otherwise nothing is written and the exit code is 0;
* `TERM=dumb` → no-op;
* **tmux**: plain OSC is accepted by tmux (it sets the pane title; with
  `set -g set-titles on` + `set-titles-string '#T'` the outer terminal title
  follows). `--passthrough` additionally wraps it in tmux's DCS passthrough
  (`ESC P tmux ; ESC <seq with ESC doubled> ESC \`) — needs
  `set -g allow-passthrough on`;
* **GNU screen** (`$STY` set): the window-name sequence `ESC k … ESC \` is added.

### 3.1 The output sanitiser (`lib.sh` `ls_sanitize` / `ls_sanitize_into`)

ONE function, used by every output path: statusline (live and derived), title
and the PS1 segment, tmux-status, watch-labels (every line; inside jq every
field additionally loses C0/C1 code points so a value cannot split a row),
the `labelrun` banner and `shell-hook.sh` diagnostics. It works on BYTES under a
function-local `LC_ALL=C`, so the result does not depend on the caller's locale
(the old `[[:cntrl:]]` filter let the UTF-8 C1 controls `c2 9d` (OSC) and `c2 9b`
(CSI) through under `LC_ALL=C`). It removes C0 `0x01–0x1f` (incl. ESC, BEL, CR,
LF, TAB), DEL, C1 `U+0080–U+009F`, the bidi controls `U+200E U+200F
U+202A–U+202E U+2066–U+2069 U+061C`, and every byte that is not part of a
well-formed UTF-8 sequence — sequence by sequence, so a removal can never join
two bytes into a new C1. Output is capped (512 bytes by default; 256 for titles,
1024 per watch row) on a character boundary. Pure bash, no fork. Tested byte-exact
under `LC_ALL=C` and `C.utf8` with `ESC ]0;`, `ESC ]52;`, CSI, C1, NUL, bidi, DEL,
invalid UTF-8 and a 100 000-character value, on every renderer (G1–G9).

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
| prompt, `seq` unchanged | one builtin `read` + string compare, no fork: measured 0.29–0.72 ms average per prompt (load average ~20) | < 5 ms (C8) |
| prompt, `seq` changed | one `jq` fork + (only if the label text changed) one title write: measured 7.9–29 ms average | < 100 ms (C8b) |
| per command (DEBUG trap) | two function calls, plus a builtin `type -t` for the first command of a cycle: measured 0.08–0.17 ms | < 2 ms (C8c) |
| registration / heartbeat / unregister | detached background process (`setsid`, `( … & )`); the prompt never waits | — |
| state dir missing/unusable | prompt hook returns rc 0 immediately, no output (median of 3 runs) | < 100 ms (C9b) |

The ranges are the spread over this session's runs on a loaded host; a
single run prints them as `METRIC` lines.

* the shell is registered as a `shell` entity (`id = shell-<host>-<pid>-<epoch>`,
  `<host>` reduced to `[A-Za-z0-9.-]` so the id always matches the CONTRACT id
  grammar; exported as `LABEL_SYNC_SHELL_ID` so `labelrun` and child tools nest
  under it), heartbeated every `LABEL_SYNC_HEARTBEAT` s (default 30) and
  unregistered on exit;
* **binding** (CONTRACT rev 2 §4.2): the shell is registered with `--derive`. Only
  a shell running inside a real Claude alias environment (`CLAUDE_CONFIG_DIR`
  basename `.claude-<alias>`) is PINNED to that alias; every other terminal is
  registered with `--follow-active true` and therefore shows whatever
  `labelctl switch-alias` last set (C11, C12, C13 — C13 uses a labeler that
  always reports an alias, and the plain terminal still follows);
* the first command of each prompt cycle is registered as a `command` entity,
  rate-capped by `LABEL_SYNC_CMD_MIN_INTERVAL` (default 1 s), ended at the next
  prompt (or at shell exit);
* title/PS1 refresh happens **at the next prompt** after the `seq` file changed
  (alias switch, any entity change): an alias switched while a long command runs
  appears when that command returns, not before — `LABEL_SYNC_TITLE_SINK=FILE`
  redirects title bytes (tests);
* existing `PROMPT_COMMAND` (string or array), `DEBUG` and `EXIT` traps are chained
  — the previous ones still run (G22, G22b, G23, G23b) — and sourcing twice is a
  no-op. bash unsets the DEBUG trap while a file is `source`d (unless `set -T`),
  so a pre-existing DEBUG trap cannot be read at source time: an **interactive**
  shell therefore installs the DEBUG hook at its **first prompt** (from top-level
  `PROMPT_COMMAND` code), where it sees and chains your trap (G22b, real
  interactive bash on a pty). In a **script**, the hook is installed at source
  time and an earlier DEBUG trap is chained only under `set -T` (G22); otherwise
  it is replaced — set it after sourcing. A chained user trap that itself runs
  commands changes `$_` (that is the user trap's own effect);
* hook hygiene: the DEBUG trap is installed as `__ls_debug "$_"` and ends with
  `: "$1"`, so the user's `$_` is unchanged (G20); every hook returns 0 and
  survives `set -eu` with a missing state dir (G21) — bash itself restores `$?`
  around `PROMPT_COMMAND` (measured), so the prompt's `$?` is unaffected;
* nothing secret is exported (no salt, G30).

### zsh / fish — UNCONFIRMED

`shell-integration.zsh` (precmd/preexec/zshexit via `add-zsh-hook`) and
`shell-integration.fish` (`fish_prompt` / `fish_preexec` / `fish_exit` events) mirror
the bash behaviour and call the same `shell-hook.sh`. They were written against
the documented hook APIs but **not executed**: neither zsh nor fish is installed
on the host that built them (§9). Validate with `zsh -n` / `fish -n` and one manual
prompt cycle before relying on them.

### What is recorded about a command (secret policy — ARGV0-ONLY)

The command **text never leaves the shell**: it is not an argument, not piped,
not hashed, not stored. Recorded in the entity's `source` field, exactly:
`shell-integration:argv0=<argv0>`, decided in two independent layers:

1. **in the user's shell** (`__ls_argv0` in bash, `whence` in zsh, `type -q` in
   fish): the first word after any leading `VAR=value` assignments is passed on
   ONLY if the shell resolves it as a command — alias, keyword, function, builtin
   or file. A pasted token or a password typed as the first word is not a
   command, so it becomes `?`. Quoted or expanded words also become `?`. The
   resolved name is handed to `shell-hook.sh` as `--argv0 NAME` (so a resolvable
   command NAME is visible in that background process's argv; nothing else is);
2. **in `shell-hook.sh`** (backstop): basename, charset `[A-Za-z0-9._+-]`, max 40
   chars, and redaction to `?` of credential-shaped words (`ghp_ gho_ ghu_ ghs_
   ghr_ github_pat_ glpat- xox[abprs]- AKIA ASIA sk- sk_live_ sk_test_ rk_live_`,
   and any ≥ 24-character `[A-Za-z0-9+/=]` word containing a digit) — even if a
   function or alias happens to be named like one.

Tested with FAKE tokens as the first word (G10: none reaches `events.jsonl`,
`snapshot.json`, `fold.json`, `base.json`; all eight recorded as `?`; a real
function is recorded — the positive control), the backstop alone (G11), and the
original argument/env-prefix secrets (C5–C6c). The earlier salted digest was
removed (review finding 7): nothing consumed it, and its salt had to be exported
to every child process. No repo-wide command-redaction convention exists
(`credential_scan_lib.sh` scans files, not shell input).

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
**only when stderr is a tty** (sanitised), runs the command without `exec` (so it
can clean up), passes stdin/stdout/stderr through, propagates the exit code exactly
(0, 7, 127 not found, 130 SIGINT, 143 SIGTERM — tested) and marks the entity
`done` on every exit path.

**Signals.** A child started with `&` by a non-interactive bash inherits SIGINT
and SIGQUIT *ignored*; labelrun therefore starts it through
`env --default-signal=INT,QUIT` (probed at run time; fallback `perl` resetting
`$SIG{INT,QUIT}` — written, NOT exercised on this host, where `env` supports the
option; if neither exists the child keeps the inherited dispositions and
`LABEL_SYNC_DEBUG=1` says so). SIGTERM and SIGHUP are forwarded to the single
child pid (validated > 1, never a process group, §11.4.263). SIGINT/SIGQUIT are
forwarded **unless** the child is in the terminal's foreground process group — a
terminal Ctrl-C has then already reached it, and forwarding would interrupt it
twice. Tested: `kill -INT <labelrun>` ends `sleep 4` in tens of ms with exit 130
(D12; labelrun started with default dispositions, as an interactive shell
starts a job — a labelrun itself started with `&` by a non-interactive shell
has SIGINT ignored on entry, which no bash program can trap); a Ctrl-C typed on a
pty reaches the child exactly once (D13); a `kill -INT <labelrun>` sent from
outside while the child is in the terminal's foreground group is NOT forwarded
(D13b) — the cost of never double-interrupting: use SIGTERM, or Ctrl-C, there. The command must be an executable
program (env execs it); a pure bash builtin is run directly instead. Fail-soft: if labelctl/state is unusable the command
still runs and its exit code is still propagated. A SIGKILL'd `labelrun` cannot
clean up; its entity goes stale on TTL (it carries labelrun's own pid, so it is
never stale while running). Command arguments are never recorded or printed.

## 6. `watch-labels.sh`

`watch-labels.sh [--once] [--interval-ms N] [--iterations N] [--timeout-s N] [--kind K]`
polls `seq` (no daemon needed) and, on change, clears (only on a tty) and redraws
a table: header `seq / active alias+model+effort / entity count`, then one group
per alias (`== alias: claude2 (3)`), one row per entity `id kind state label [stale]`.
Every line is sanitised (§3.1); a newline inside a stored value cannot forge a row (G6c).

## 7. Verification

```bash
bash scripts/label-sync/render/tests/test_render.sh          # 165 cases (needs jq, go, python3; script(1) optional)
bash scripts/label-sync/render/prove_mutations.sh            # 23 mutants + control, all must be KILLED
bash scripts/gates/cm_label_sync_render.sh                   # CM-LABEL-SYNC-RENDER: 0 pass | 1 fail | 2 cannot determine
bash scripts/gates/cm_label_sync_render_mutation_test.sh     # gate's own paired mutation test (10 mutants + exit-2 case)
```

Run niced and one at a time on a loaded host (§12.6/§12.8). The tests use a temp
`LABEL_SYNC_DIR`, start/stop their own `label-busd`, and never write under `~/.claude*`.
The gate reports **exit 2 (cannot determine) when jq, go or python3 is missing**
— never a pass; `--structural-only` prints `PASS (STRUCTURAL ONLY — runtime
behaviour NOT verified)`.

## 8. Behaviour guarantees covered by tests

Alias switch changes the next statusline/title output (A2, C4); bus/state down →
rc 0 and an honest `?` + marker (A6, A7); staleness marker appears and clears on
heartbeat (A9); non-tty and `TERM=dumb` write nothing (B3, B4); escape injection
stripped (B2, G1–G9 for every output path under two locales); unchanged `seq`
does not rewrite the title (C3); no secret reaches the state files (C6, G10, G11);
prompt overhead bounds (C8); fail-soft with unusable state (C9); real alias env
pins, plain terminal follows (C11–C13); id grammar (C14); `labelrun` exit-code,
signal, cleanup, stdin and banner behaviour (D1–D13b); `$_`, `set -eu`, trap and
`PROMPT_COMMAND` chaining (G20–G23); nothing secret exported (G30). The byte
checker used by G1–G9 is itself control-needled first (G0): a `grep -P` byte
probe on this host was found BLIND to `c2 9d` and is therefore not used.

## 9. Honest boundary / UNCONFIRMED (§11.4.6)

* **Claude Code statusLine stdin schema — UNCONFIRMED against the docs.** The
  Claude Code documentation was not found in this host's plugin cache. The script
  reads only `session_id`, `workspace.current_dir` and `cwd` (defensively; anything
  missing is ignored and non-JSON input still exits 0). Verify the field names
  against the installed Claude Code version before relying on session matching.
* **zsh and fish integrations — written, not executed** (neither `zsh` nor `fish`
  is installed on this host: `command -v zsh fish` prints nothing). Their argv0
  resolution (`whence`, `type -q`), the removed digest and the host-id fix mirror
  the bash code but are UNCONFIRMED until run.
* **labelrun's perl fallback** (for an `env` without `--default-signal`) is
  written but not exercised here.
* **tmux and GNU screen paths — not executed against a real tmux server** (tmux is
  not installed; the OSC/DCS byte sequences are asserted, the tmux behaviour is
  taken from its documentation). screen is installed but was not driven.
* The bash integration was exercised via a scripted shell calling the hook functions
  directly (a real interactive `PROMPT_COMMAND` cycle was not driven).
* The derived fallback labeler runs in the status line's cwd with the session id
  exported; its `<model>` for native aliases comes from the session transcript and
  may be `?` (the labeler's own honest limit, §11.4.182(5)).
* Terminal titles can be set only by a process attached to the terminal: the
  statusLine command runs with piped stdout, so the title of a terminal running
  Claude Code comes from the shell integration (at its next prompt), never from
  `statusline.sh`.
* The statusline latency bound is an AVERAGE over 20 calls with `label-busd`
  up (A4), measured on this host only; no per-call worst case is claimed.
