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

Run the dispatcher with the user's arguments as ONE quoted argument (never splice user text into a
shell command line):

```
bash submodules/constitution/scripts/constitution_cmd/constitution_cmd.sh "<arguments>"
```

Legacy layout: `constitution/scripts/constitution_cmd/constitution_cmd.sh`. When the constitution
is the project root: `scripts/constitution_cmd/constitution_cmd.sh`.

With no arguments run `help`. Subcommands: `status`, `update` (check only), `doctor`, `anchors N`,
`gates [list|run NAME]`, `report|issue|bug|task|feature TEXT`, `skills [list|status]`,
`extensions ...`, `install-extension SRC`, `jev`, `release-notes`, `help`.

Rules: relay the output; never invent status the engine did not print (section 11.4.6). Exit 2 =
rejected argument, exit 3 = a delegated tool is not installed (say so, do not work around it).
Guide: `docs/guides/constitution_command_guide.md`.
