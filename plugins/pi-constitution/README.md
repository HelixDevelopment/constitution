# pi-constitution — Pi extension for the Helix Constitution

**Status:** active · **Version:** 1.0.0 · **Schema:** `pi.extension.v1` · **Owner:** HelixDevelopment / Constitution submodule

Binds the Helix Constitution governance layer (Constitution.md / CLAUDE.md /
AGENTS.md, consumed via the Constitution git submodule) into the Pi coding
agent. Every Pi session starts with a Constitution governance audit, and any
Constitution-relevant operation is peer-gated before execution so governance
drift cannot happen silently.

---

## Table of contents

- [What it does](#what-it-does)
- [Architecture](#architecture)
- [Install (consuming project)](#install-consuming-project)
- [Configure Pi (config + manifest)](#configure-pi-config--manifest)
- [Usage](#usage)
- [Command reference](#command-reference)
- [Events & hooks](#events--hooks)
- [Typed collaboration packets](#typed-collaboration-packets)
- [Governance & Constitution compliance](#governance--constitution-compliance)
- [File layout](#file-layout)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)
- [Related docs](#related-docs)

---

## What it does

| Hook / tool | What happens |
|---|---|
| `session_start` | Audits the Constitution submodule (`submodules/constitution`), verifies all three governance files (`Constitution.md`, `CLAUDE.md`, `AGENTS.md`) are present, checks that the four mandated sections (§11.4.26, §11.4.28, §11.4.31, §11.4.32) are referenced across those files, emits a shame-compatible status line from validated data, and reports each failure as a deterministic triage-error code. |
| `tool_call` | Intercepts bash commands that reference the Constitution submodule or governance files. If the submodule is absent, peer-gates via a typed `pi-constitution.collab_question.v1` / `collab_answer.v1` packet before allowing the operation — no silent bypass, no governance drift. |
| `pi-constitution-doctor` (custom tool) | On-demand full Constitution governance audit: submodule presence, HEAD, governance files, mandate sections, per-issue structured result. |

---

## Architecture

```
Pi session
  ├── session_start  ──► auditConstitution()
  │                        ├─ submodule present?
  │                        ├─ governance files present?
  │                        └─ mandate sections referenced?
  │                        └─ emit pi.agent_status.v1 (validated data)
  │                        └─ triage-error per failure (deterministic code)
  │
  ├── tool_call (bash) ──► guardConstitutionOps()
  │                        └─ cmd touches constitution?
  │                          └─ submodule missing?
  │                            └─ collab_question.v1 → peer gate
  │
  └── custom tool: pi-constitution-doctor
                        └─ full audit → structured result
```

Design principles (from [best-practices-pi-extension]):

1. **Typed boundary first** — every cross-boundary payload (collab question/answer, audit result, status) is a typed JSON schema validated before use. No raw dict/string poking.
2. **Shame-compatible status** — completion is rendered from validated data, not model prose. Status carries a first-class `answer`, `verified[]`, and local proof whose text contains each command/result pair.
3. **Peer-gated bidirectional loops** — the collaboration loop is not closed from the sender side. A typed JSON packet is asked, the typed answer is validated against the original question (`question_id`, `allowed_answers`, `response_schema`), and the peer acceptance receipt is kept.
4. **Failures routed through triage-error** — deterministic catalog codes (`constitution_submodule_missing`, `constitution_governance_file_missing`, `constitution_mandate_section_missing`, `constitution_pointer_stale`), never bare timeouts or "NEEDS_ATTENTION".
5. **No silent bypass** — any operation touching Constitution governance that cannot be validated is blocked pending explicit peer confirmation.

---

## Install (consuming project)

### Prerequisites

- Pi coding agent installed and running (`pi` on PATH)
- The consuming project has the Constitution submodule added at `submodules/constitution`

### Step 1 — Add the Constitution submodule

```sh
git submodule add git@github.com:HelixDevelopment/constitution.git submodules/constitution
git submodule update --init submodules/constitution
```

Per §11.4.26, before any edit to Constitution governance, fetch + pull all remotes:

```sh
git -C submodules/constitution fetch --all
git -C submodules/constitution pull --ff-only origin main
```

### Step 2 — Install the Pi extension

From the consuming project root:

```sh
# Option A: symlink (recommended — single source of truth in the submodule)
ln -s submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts

# Option B: copy (independent snapshot; must be re-synced on each Constitution bump)
cp submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts
```

### Step 3 — Register in Pi config

Add the extension to Pi's extension list. Edit `~/.pi/agent/settings.json` (or use `pi config`):

```json
{
  "extensions": [
    "pi-constitution"
  ]
}
```

Or via the Pi CLI:

```sh
pi install pi-constitution
```

### Step 4 — Verify

Restart Pi, then run:

```sh
pi-constitution-doctor
```

You should see a full green audit: submodule present, all governance files present, all four mandate sections referenced.

---

## Configure Pi (config + manifest)

### Pi manifest (`~/.pi/agent/settings.json`)

The extension is auto-discovered from `~/.pi/agent/extensions/`. No additional manifest entry is required beyond the `extensions` array listing `pi-constitution`.

### Project-level integration (`.specify/integrations/pi.manifest.json`)

If the consuming project tracks a Pi integration manifest, add:

```json
{
  "integration": "pi",
  "version": "1.0.0",
  "files": {
    "submodules/constitution/plugins/pi-constitution/plugin.json": "...",
    "submodules/constitution/plugins/pi-constitution/pi-constitution.ts": "..."
  }
}
```

### Extension hooks (`.specify/extensions.yml`)

If the project uses Spec Kit extension hooks, register pi-constitution:

```yaml
hooks:
  after_constitution:
    - extension: pi-constitution
      command: pi-constitution-doctor
      enabled: true
      optional: false
      priority: 5
      description: Verify Constitution governance after any constitution change
      condition: null
```

---

## Usage

### Automatic (session_start)

No action required. On every Pi session start, `pi-constitution` audits the Constitution binding and prints a status line. Example output:

```
## pi-constitution audit
- Submodule: present
- Submodule HEAD: ecfb6339
- Governance Constitution.md: present
- Governance CLAUDE.md: present
- Governance AGENTS.md: present
- Mandate §11.4.26: present (Constitution.md, CLAUDE.md, AGENTS.md)
- Mandate §11.4.28: present (Constitution.md, CLAUDE.md, AGENTS.md)
- Mandate §11.4.31: present (Constitution.md, CLAUDE.md, AGENTS.md)
- Mandate §11.4.32: present (Constitution.md, CLAUDE.md, AGENTS.md)

Constitution governance is healthy.
```

If issues are found, each is reported as a triage-error code with a `next_command`:

```
- [constitution_submodule_missing] Constitution submodule not found at submodules/constitution. Run: git submodule update --init submodules/constitution
```

### On-demand: `pi-constitution-doctor`

Run a full governance audit at any time:

```sh
# Via Pi custom tool
pi-constitution-doctor
```

The tool returns a structured result:

| Field | Meaning |
|---|---|
| `plugin` | `pi-constitution` |
| `version` | `1.0.0` |
| `submodulePresent` | boolean |
| `submoduleHead` | short SHA or null |
| `errorCount` | number of issues |
| `verifiedCount` | number of passing checks |
| `errors[]` | `{ code, message }` per issue |
| `governanceFiles` | `{ file: { present, path } }` |
| `mandateSections` | `{ section: { present, foundIn[] } }` |
| `verified[]` | human-readable passing checks |

### Guarded operations

Any bash command that references `submodules/constitution`, `Constitution.md`, `CLAUDE.md`, `AGENTS.md`, or `pi-constitution` is intercepted. If the submodule is missing, Pi prompts:

> Constitution submodule missing — proceed anyway (risking governance drift)?
> [SUFFICIENT / NEEDS_FIX]

Answer `SUFFICIENT` to proceed, `NEEDS_FIX` to abort.

---

## Command reference

### `pi-constitution-doctor`

| Property | Value |
|---|---|
| Name | `pi-constitution-doctor` |
| Label | Constitution Doctor |
| Description | Full Constitution governance audit |
| Parameters | `{ detail?: boolean }` |
| Exposure | direct |
| Errors | `isError: true` when any governance issue is found |

### Lifecycle events

| Event | Handler | Purpose |
|---|---|---|
| `session_start` | `auditConstitution` | Audit Constitution binding at session start |
| `tool_call` | `guardConstitutionOps` | Peer-gate Constitution-relevant bash commands |

---

## Events & hooks

### `session_start` payload

The handler receives Pi's `SessionStartEvent` (`{ type: "session_start", reason }`) and `ExtensionContext` (`{ cwd, ui, ... }`). It:

1. Computes `cPath = <cwd>/submodules/constitution`
2. Runs `test -d <cPath>` — if absent, records `constitution_submodule_missing`
3. Runs `git -C <cPath> rev-parse HEAD` — records submodule HEAD
4. `cat`s each of `Constitution.md`, `CLAUDE.md`, `AGENTS.md` — records presence
5. Scans each governance file for the four mandate sections — records coverage
6. Calls `ctx.ui.setStatus("constitution", ...)` with validated data
7. Sends a `pi-constitution.audit` custom message to the session transcript
8. Sends a `pi-constitution.triage` custom message per error (deterministic code)

### `tool_call` result

Returns `{ block: true, reason }` when:
- The command references Constitution governance AND
- The submodule is absent AND
- The peer does not confirm via `ctx.ui.confirm(...)`

Returns `undefined` (allow) otherwise.

---

## Typed collaboration packets

Per [best-practices-pi-extension] rule 4, collaboration is peer-gated with typed JSON packets.

### Question packet (`pi-constitution.collab_question.v1`)

```json
{
  "schema": "pi-constitution.collab_question.v1",
  "question_id": "constitution-<timestamp>",
  "triage": {
    "code": "constitution_submodule_missing",
    "layer": "extension",
    "cause": "Constitution submodule not present at submodules/constitution; cannot safely run: <cmd>"
  },
  "question": "Constitution submodule is missing. Proceed with the operation anyway (risking governance drift), or abort and bind the submodule first?",
  "required_response_schema": "pi-constitution.collab_answer.v1",
  "allowed_answers": ["SUFFICIENT", "NEEDS_FIX"]
}
```

### Answer packet (`pi-constitution.collab_answer.v1`)

```json
{
  "schema": "pi-constitution.collab_answer.v1",
  "question_id": "constitution-<timestamp>",
  "answer": "SUFFICIENT",
  "reason": "user confirmed proceeding despite missing submodule"
}
```

Validation: the answer must match the original `question_id`, use an `allowed_answers` value, and conform to `required_response_schema`. A valid answer with the wrong `question_id` or widened `allowed_answers` is invalid data, not dissent.

---

## Governance & Constitution compliance

This plugin lives **inside the Constitution submodule** per Constitution §11.4.26 / §11.4.28 / §11.4.31.

### Change workflow (§11.4.26)

Every change to this plugin follows the Constitution-Submodule Update Workflow:

1. **Fetch + pull all remotes** inside `submodules/constitution` before editing
2. **Commit inside the submodule** on a `task/` branch (never direct to `main`)
3. **Validate** — run `meta_test_inheritance.sh`, check for merge-conflict markers, verify cross-references
4. **Push to ALL upstreams** — a commit on one upstream but not others is a §11.4.26 violation
5. **Merge to `main`** via `--no-ff`
6. **Push `main` to ALL upstreams**
7. **Bump the consuming project's submodule pointer** in the same change-window

### Classification (§11.4.17)

Universal — the Pi binding for the Constitution governance layer belongs in the constitution submodule, not in any consuming project's local files. Never edit this plugin directly in a consuming project; edit it in the Constitution submodule and propagate via submodule commit.

### Dependency manifest (§11.4.31)

The pi-constitution plugin has no own-org submodule dependencies (`helix-deps.yaml` would carry `deps: []`).

---

## File layout

```
plugins/pi-constitution/
├── plugin.json          # Pi extension manifest (schema pi.extension.v1)
├── pi-constitution.ts   # Extension implementation (entry point + hooks + doctor tool)
├── README.md            # This file — user-facing guide
├── SPEC.md              # Technical specification (types, schemas, contracts)
├── INSTALL.md           # Step-by-step installation for consuming projects
├── USAGE.md             # Usage examples and workflows
├── GOVERNANCE.md        # Constitution §11.4 compliance traceability
├── TROUBLESHOOTING.md   # Common issues and remediation
└── CHANGELOG.md         # Per-release change notes
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `pi.cwd is not a function` | Extension used removed API | Use `ctx.cwd` (string property on ExtensionContext) — see `pi-constitution.ts` |
| Tool name rejected by provider | Colon in tool name | Tool names allow only `[a-zA-Z0-9_-]` — `pi-constitution-doctor`, not `pi-constitution:doctor` |
| Extension fails to load | Syntax/import error | Check `pi --help` for "Failed to load extension" errors; fix imports from `@earendil-works/pi-coding-agent` |
| `session_start` silent | Extension not registered | Ensure `pi-constitution.ts` is in `~/.pi/agent/extensions/` and listed in settings `extensions` |
| `pi-constitution-doctor` not found | Tool not registered | Restart Pi after installing; verify `pi list` shows the extension |
| Guard prompt never appears | Command doesn't match patterns | Ensure the command string contains `submodules/constitution`, `Constitution.md`, `CLAUDE.md`, `AGENTS.md`, or `pi-constitution` |
| Submodule missing at session start | Not initialized | Run `git submodule update --init submodules/constitution` |

---

## Changelog

### v1.0.0 (2026-11-25)

- Initial release of pi-constitution Pi extension
- `session_start` audit of Constitution submodule + governance files + mandate sections
- `tool_call` peer-gating for Constitution-relevant bash commands
- `pi-constitution-doctor` custom tool with structured result
- Typed collaboration packets (`collab_question.v1` / `collab_answer.v1`)
- Deterministic triage-error codes for all failure modes
- Shame-compatible `pi.agent_status.v1` from validated data

---

## Related docs

- [SPEC.md](./SPEC.md) — technical specification (types, schemas, contracts)
- [INSTALL.md](./INSTALL.md) — step-by-step installation for consuming projects
- [USAGE.md](./USAGE.md) — usage examples and workflows
- [GOVERNANCE.md](./GOVERNANCE.md) — Constitution §11.4 compliance traceability
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) — common issues and remediation
- [CHANGELOG.md](./CHANGELOG.md) — per-release change notes
- [Constitution extensions catalogue](../docs/extensions/EXTENSIONS_CATALOG.md) — all shipped extensions
- [Extensions guide](../docs/guides/extensions_guide.md) — installing and managing extensions
- [Extensions manual](../docs/manuals/extensions_manual.md) — command reference and rules
- [best-practices-pi-extension](/home/milosvasic/.pi/agent/skills/best-practices-pi-extension/SKILL.md) — Pi extension authoring rules
