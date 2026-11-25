# pi-constitution — Pi extension for the Helix Constitution

Binds the Helix Constitution governance layer (Constitution.md / CLAUDE.md /
AGENTS.md, consumed via the Constitution git submodule) into Pi.

## What it does

- **session_start**: audits the Constitution submodule (`submodules/constitution`),
  verifies all governance files (`Constitution.md`, `CLAUDE.md`, `AGENTS.md`) are
  present, checks that the mandate sections (§11.4.26, §11.4.28, §11.4.31,
  §11.4.32) are referenced, and emits a shame-compatible `pi.agent_status.v1`
  payload from validated data.
- **tool_call**: intercepts commands that reference the Constitution submodule or
  governance files; if the submodule is absent, it peer-gates via a typed
  `pi-constitution.collab_question.v1` / `collab_answer.v1` packet before allowing
  the operation (no silent bypass).
- **custom tool `pi-constitution:doctor`**: on-demand full governance audit with
  a structured result and per-issue triage-error codes.

## Install (consuming project)

1. Add the Constitution submodule (done once per project):

   ```sh
   git submodule add git@github.com:HelixDevelopment/constitution.git submodules/constitution
   git submodule update --init submodules/constitution
   ```

2. Install the Pi extension. From the consuming project root:

   ```sh
   ln -s submodules/constitution/plugins/pi-constitution ~/.pi/agent/extensions/pi-constitution.ts
   # or copy the file:
   cp submodules/constitution/plugins/pi-constitution/pi-constitution.ts ~/.pi/agent/extensions/pi-constitution.ts
   ```

3. Restart Pi. The extension auto-loads on `session_start`.

## Usage

- `pi-constitution-doctor` — run a full Constitution governance audit.
- Any bash command touching `submodules/constitution`, `Constitution.md`,
  `CLAUDE.md`, or `AGENTS.md` is guarded: if the submodule is missing, Pi
  prompts via a typed collaboration packet before proceeding.

## Governance

This plugin lives **inside the Constitution submodule** per
Constitution §11.4.26 / §11.4.28. Changes to it are committed inside the
submodule, pushed to all Constitution upstreams, then the consuming project
bumps its submodule pointer in the same change-window. Never edit this plugin
directly in a consuming project — edit it in the Constitution submodule and
propagate via submodule commit.

## Files

| File | Purpose |
|---|---|
| `plugin.json` | Pi extension manifest (schema `pi.extension.v1`) |
| `pi-constitution.ts` | Extension implementation (Entry point + hooks) |
| `README.md` | This file |
