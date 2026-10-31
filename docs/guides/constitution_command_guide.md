# The /constitution command family

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-31 |
| Status | active (release 2, workstream E2) |
| Engine | `scripts/constitution_cmd/constitution_cmd.sh` |

## Contents

- [What it is](#what-it-is)
- [How each agent reaches it](#how-each-agent-reaches-it)
- [Subcommands](#subcommands)
- [Exit codes](#exit-codes)
- [Security model](#security-model)
- [Troubleshooting](#troubleshooting)
- [Honest boundaries](#honest-boundaries)

## What it is

One engine script reads the user's arguments and dispatches to an allow-listed subcommand. The
engine does almost no work itself: it detects the constitution layout (both `submodules/constitution`
and the legacy `constitution`) through `scripts/lib/constitution_layout.sh`, prints read-only
diagnostics, and delegates everything else to the existing tools (`update_constitution.sh`,
`reporting/report_item.sh`, `skill_activation/skill_activate.sh`, `constitution_ext/constitution_ext.sh`).
It never reimplements them.

## How each agent reaches it

| Agent | Entry | Source |
|---|---|---|
| Claude Code, bare | `/constitution` | project-scope skill `skills/constitution/SKILL.md`, linked into `.claude/skills/constitution` |
| Claude Code, namespaced | `/helix:constitution` (also `/helix:default-constitution`) | generated `plugins/helix/commands/constitution.md` |
| Gemini CLI, Qwen Code | `/constitution` | generated `actions/generated/{gemini,qwen}/constitution.toml` |
| Codex CLI | `/constitution` | generated `actions/generated/codex/constitution.md` |

The generated files come from the registry row `CONSTITUTION` in `actions/registry.yaml` via
`bash scripts/generate_agent_prefix_commands.sh`; never edit them by hand. Per-agent installation
of the shims is owned by `scripts/install_cli_agent_plugins.sh` (not changed here).

## Subcommands

| Command | What it does |
|---|---|
| `status` | layout, constitution dir, project root, pinned commit, latest LOCAL release tag, Jev state |
| `update [--check\|--dry-run] [--ref REF]` | delegates to `update_constitution.sh`; `--check` is the default; never applies |
| `doctor` | read-only: layout, registry row, shims, regeneration drift, skill link, hooks, name collisions |
| `anchors N` | prints the block of anchor `11.4.N` (`N` or `N.M`), at most 120 lines / 24000 bytes |
| `gates [list]`, `gates run NAME` | lists `cm_*` gates (mutation tests hidden); runs one with a timeout (`CONSTITUTION_CMD_GATE_TIMEOUT`, default 120 s) |
| `report`/`issue`/`bug`/`task`/`feature TEXT` | delegates to `report_item.sh` (section 11.4.202) |
| `skills [list\|status]` | delegates to `skill_activate.sh` |
| `extensions list\|info\|add\|update\|remove\|enable\|disable\|verify\|lock\|catalog\|wire\|unwire\|doctor\|validate ...` | delegates to the extension engine if installed; otherwise prints `extensions engine not installed` |
| `install-extension SRC` | alias of `extensions add SRC` |
| `jev`, `release-notes`, `help` | decision-layer status, head of the changelog, usage |

## Exit codes

0 ok; 1 failure or not found (doctor: a FAIL line); 2 usage error or rejected argument; 3 a
delegated tool is not installed (reported as `unavailable`); 124 a delegated tool timed out.

## Security model

No `eval`; the subcommand is an allow-list; the anchor id must match `^[0-9]{1,3}(\.[0-9]+)?$`;
gate names must match `^[a-z0-9_]{1,100}$` (or `CM-...`) and resolve (symlinks followed) inside
`scripts/gates`; extension arguments are matched against a conservative character class; control
characters are refused everywhere; delegated output is size-bounded and run through a
credential-shape redactor (tokens, `Bearer`, `*TOKEN*=`-style assignments). Pass user text as ONE
quoted argument - the engine splits a lone string on blanks itself and never lets the shell see it.

## Troubleshooting

- `/constitution` not offered in Claude Code: run `/constitution doctor` (or the engine directly);
  a `WARN skills-link` means `.claude/skills/constitution` is missing. Use `/helix:constitution`
  meanwhile.
- `WARN collision`: a user-defined command of the same name exists; the host decides precedence.
  Use `/helix:constitution`, which is always unambiguous.
- `WARN drift`: regenerate with `bash scripts/generate_agent_prefix_commands.sh`.
- exit 3: the delegated tool is not part of this checkout yet; update the constitution.

## Honest boundaries

- UNCONFIRMED: whether a given Claude Code version resolves bare `/constitution` to the project
  skill rather than to another source with the same name; the skill is the documented mechanism and
  `doctor` reports collisions it can see on disk only.
- `update --check` delegates to a script that itself fetches remotes; this engine adds no network
  code but cannot make that fetch offline.
- `gates run` executes a repository gate script; gates are intended to be read-only but the engine
  cannot prove that for an arbitrary gate.
- Delegation tests use recording stubs (unit class); they prove argv, not that the delegated tool
  works (section 11.4.289).
