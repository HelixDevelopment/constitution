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
| `anchors N` | prints the block of anchor `11.4.N` (`N` or `N.M`), at most 120 lines / 24000 bytes; both the `### §11.4.N —` heading form and the bold `**§11.4.N —` paragraph form are found |
| `gates [list]`, `gates run NAME` | lists `cm_*` gates (mutation tests hidden); runs one with a timeout (`CONSTITUTION_CMD_GATE_TIMEOUT`, default 120 s) |
| `report`/`issue`/`bug`/`task`/`feature TEXT` | delegates to `report_item.sh` (section 11.4.202) |
| `skills [list\|status]` | delegates to `skill_activate.sh` |
| `extensions list\|info\|add\|remove\|enable\|disable\|verify\|lock\|catalog\|wire\|unwire\|doctor\|validate ...` | delegates to the extension engine if installed; otherwise prints `extensions engine not installed`; `extensions update` is not implemented and exits 2 |
| `install-extension SRC` | alias of `extensions add SRC` |
| `jev`, `release-notes`, `help` | decision-layer status, head of the changelog, usage |

## Exit codes

0 ok; 1 failure or not found (doctor: a FAIL line); 2 usage error or rejected argument; 3 the
engine found a delegated tool not installed (`unavailable`) - but a delegated tool's OWN exit
status is passed through unchanged, so a tool can also exit 3 itself; 124 a delegated tool timed out.
Delegated output is capped at 40000 bytes; when cut, the engine prints an explicit
`[truncated: ...]` marker and the exit status is still the tool's real one.

## Security model

No `eval`; the subcommand is an allow-list; the anchor id must match `^[0-9]{1,3}(\.[0-9]+)?$`;
gate names must match `^[a-z0-9_]{1,100}$` (or `CM-...`) and resolve (symlinks followed) inside
`scripts/gates`; extension arguments are matched against a conservative character class; control
characters are refused everywhere; delegated output is size-bounded and run through a
credential-shape redactor (tokens, `Bearer`, `token VALUE`, `api_key: "..."`, case-insensitive `password=`-style assignments).
Extension options are an allow-list per subcommand (`--json`, `--dry-run`; `add` also `--dev`,
`--sha`, `--sha256`); `--root`, `--project-root`, `--yes` and any other `--*` are rejected. `jev`
and `release-notes` take no arguments.

User text reaches the engine through a FILE: the agent writes it with its file-write tool (not the
shell) to `/tmp/constitution_args_<id>.txt` (`<id>` = fresh random 12-hex string, unguessable) and runs
`constitution_cmd.sh --args-file <that path>`. The command line holds only the path, so no shell
ever sees user text and there is no heredoc delimiter to break out of (the earlier fixed-delimiter
heredoc could be ended early by a pasted line equal to the delimiter; that class is removed, and
the suite replays that exact payload as a control needle). The engine accepts only
`<dir>/constitution_args_<id>.txt` with `<dir>` exactly `/tmp` or exactly `$TMPDIR` (absolute and canonical: no extra
path component, no `..`, no `.`/`//`, and `realpath($TMPDIR)` equal to `$TMPDIR`, so a symlinked or relative `$TMPDIR` is not accepted) and `<id>` in `[a-z0-9]{8,64}`. The file is opened relative to a
directory descriptor with `O_NOFOLLOW` (a symlink leaf or symlinked middle directory cannot be followed),
must be a regular file with one hard link, owned by the caller, at most 8001 bytes, with the same
inode as the directory entry, one line, no control or NUL characters; only that verified file is
deleted (through the directory descriptor) after reading (helper `args_file_read.py`). `--stdin` was
removed (nothing used it). The directories are exactly `/tmp` and (when canonical) `$TMPDIR`, on purpose. Known limit: where `/tmp` itself is a symlink (macOS: `/tmp` -> `/private/tmp`) `/tmp` stays accepted as the literal string while a `$TMPDIR` that is, or lies under, a symlink is rejected, so the two are not treated alike; use a canonical `$TMPDIR` there (e.g. `/private/tmp/...`). The helper itself has no environment-controlled test behaviour; the identity check is tested in-process. An agent without a
file-write tool must refuse, never fall back to the shell.
The engine splits the one-line string on blanks itself. Passing text as a double-quoted argument,
as the first version did, is NOT safe and is not used. Residual: an agent without a file-write
tool cannot use this path (UNCONFIRMED which hosts lack one); a local user who can write to the
same temp directory could race the file before the engine reads it (the owner, link and same-inode checks
narrow, not close, a rename swap between the identity check and the unlink (it can only remove a
file with a valid `constitution_args_<id>.txt` name inside the temp directory)).

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
