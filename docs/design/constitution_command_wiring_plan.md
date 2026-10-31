# /constitution per-agent wiring plan

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-31 |
| Status | investigation only; nothing here is wired by this document |
| Scope | scripts/install_cli_agent_plugins.sh, scripts/post_update_hook.sh (read, not edited) |

## What exists (read from source, this session)

- `post_update_hook.sh` step 4 runs `install_cli_agent_plugins.sh <PROJECT_ROOT>` on every constitution pull (lines ~703-718). It never aborts the hook; a failing installer becomes a WARNING.
- The installer (1) regenerates every registry action for Claude/Gemini/Qwen/Codex, (2) symlinks skills into `<project>/.claude/skills/<name>`, (3) registers the local marketplace and installs the `helix` plugin when the `claude` CLI exists. `link_agent_commands` (line ~194) symlinks `actions/generated/gemini/*.toml` to `<project>/.gemini/commands/`, `qwen/*.toml` to `<project>/.qwen/commands/`, `codex/*.md` to `<project>/prompts/`.
- The constitution row is in `actions/registry.yaml`; generated files exist for codex, gemini and qwen (`constitution.*`, `default-constitution.*`) and `plugins/helix/commands/constitution.md` for Claude Code. The skill is `skills/constitution/SKILL.md`.
- Binaries on this host (`command -v`): claude, opencode, kimi, pi present; gemini, qwen, codex MISSING.

## Per agent

| Agent | What it needs for /constitution | State |
|---|---|---|
| Claude Code | bare `/constitution` = skill link `.claude/skills/constitution`; `/helix:constitution` = plugin command. Both done by the installer. | Mechanism read from source. Skill link absent in this repo checkout (`.claude/skills` does not exist here; this is the hub, not a consumer). Whether bare `/constitution` resolves to the skill: UNCONFIRMED (guide says so too). |
| OpenCode | Nothing generated. Needs a command file (`.opencode/command/constitution.md` or `~/.config/opencode/command/`) or a skill path, plus the same `--args-file` instruction. No generator target exists. | Binary present. No wiring code. Command directory layout UNCONFIRMED (not verified against the installed version). |
| Gemini CLI | `.gemini/commands/constitution.toml` symlink; already done by `link_agent_commands`. The TOML must tell the model to use its file-write tool then run the one command; `{{args}}` is forwarded. | Wiring code exists; binary NOT installed, so end-to-end behaviour UNCONFIRMED. |
| Qwen Code | `.qwen/commands/constitution.toml`, same as Gemini. | Wiring code exists; binary NOT installed; UNCONFIRMED. |
| Codex CLI | `constitution.md` prompt. The installer links it to `<project>/prompts/`; Codex normally reads `~/.codex/prompts`, so the project-relative target may not be discovered. | Binary NOT installed; destination correctness UNCONFIRMED (possible gap). |
| Kimi Code | No generator target, no installer branch. Would need a skill or command file in whatever Kimi reads; layout unknown. `~/.kimi-code/bin/kimi` exists. | UNKNOWN; needs a read of Kimi docs and a live probe. |
| pi | No generator target. pi has `~/.pi/agent/extensions`; an extension or prompt-template route is the likely seam. | UNKNOWN; needs docs read and a live probe. |

## Proposed work (not done)

1. Add generator targets (or documented skill links) for OpenCode, Kimi and pi once their command/skill discovery paths are verified live on this host; keep one registry row as the source.
2. Verify Codex prompt location; if `~/.codex/prompts` is the real path, link there (user scope, opt-in per the label-sync dry-run precedent in step 4d).
3. For gemini/qwen/codex run a live `/constitution status` once the binaries are installed; until then record SKIP `hardware_not_present`-style (tool absent), never PASS.
4. Add a doctor check per wired agent (symlink resolves, file content matches the generated one).
5. All shims already use the `--args-file` mechanism (file-write tool, no shell sees user text); agents without a file-write tool cannot use it and need a documented fallback (`--stdin` through a heredoc with an agent-chosen random delimiter).
