---
name: constitution
description: >-
  Helix Constitution command family. Use for "/constitution" or when the user wants constitution
  status, an update check, a doctor diagnosis, an anchor's text, a gate listing or run, a bug/task/
  issue/feature report, skill or extension management, or release notes. A thin skill: it only
  delegates to the dispatcher script and relays its output.
compatibility:
  # section 11.4.228 closed vocabulary
  SUPPORTED:
    - claude-code      # bare /constitution via this project-scope skill; /helix:constitution via the plugin
  UNTESTED:
    - opencode
    - gemini
    - qwen
    - codex
    - kimi
    - pi
---

# /constitution

Pass the user's arguments in a FILE so no shell ever sees the user's text (a heredoc has a
delimiter a pasted payload could contain; a file has none).

1. With your FILE-WRITE tool (not the shell), write the arguments, verbatim, on one line, into a new
   file `/tmp/constitution_args_<id>.txt`, where `<id>` is a fresh random 12-character lowercase-hex
   string (the engine accepts only `[a-z0-9]{8,64}`; make it unguessable, do not reuse an id).
   With no arguments write `help`.
2. Run exactly this command (the path is the only variable part; it contains no user text):

```
bash submodules/constitution/scripts/constitution_cmd/constitution_cmd.sh --args-file /tmp/constitution_args_<id>.txt
```

The engine deletes the file after reading it. The directory is hard-coded to `/tmp` (or exactly
`$TMPDIR` when that is where you wrote the file); any other directory, `..`, symlink, hard link,
non-regular or foreign-owned file is refused (exit 2). If you have NO file-write tool, refuse:
tell the user this command cannot run safely from this agent, and do NOT fall back to putting the
text on a shell command line, in a heredoc or in quotes. Never put the arguments on the command line, in a
heredoc or inside quotes.

Legacy layout: `constitution/scripts/constitution_cmd/constitution_cmd.sh`. When the constitution
is the project root: `scripts/constitution_cmd/constitution_cmd.sh`.

With no arguments run `help`. Subcommands: `status`, `update` (check only), `doctor`, `anchors N`,
`gates [list|run NAME]`, `report|issue|bug|task|feature TEXT`, `skills [list|status]`,
`extensions ...`, `install-extension SRC`, `jev`, `release-notes`, `help`.

Rules: relay the output; never invent status the engine did not print (section 11.4.6). Exit 2 =
rejected argument, exit 3 = a delegated tool is not installed or itself exited 3 (say so, do not work
around it); other codes are the delegated tool's own status.
Guide: `docs/guides/constitution_command_guide.md`.
