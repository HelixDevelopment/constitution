# pi-constitution — Installation Guide

**Version:** 1.0.0 · **Audience:** operators adding pi-constitution to a consuming Pi project

This guide walks through installing the pi-constitution Pi extension into a project
that already consumes the Constitution as a git submodule.

---

## Table of contents

- [Prerequisites](#prerequisites)
- [Step 1 — Constitution submodule](#step-1--constitution-submodule)
- [Step 2 — Install the extension file](#step-2--install-the-extension-file)
- [Step 3 — Register in Pi settings](#step-3--register-in-pi-settings)
- [Step 4 — Project integration manifest](#step-4--project-integration-manifest)
- [Step 5 — Extension hooks (optional)](#step-5--extension-hooks-optional)
- [Step 6 — Verify](#step-6--verify)
- [Offline / air-gapped install](#offline--air-gapped-install)
- [Uninstall](#uninstall)
- [Upgrading](#upgrading)

---

## Prerequisites

- Pi coding agent installed (`pi` on PATH)
- A git project (the consuming project)
- The Constitution submodule URL: `git@github.com:HelixDevelopment/constitution.git`

---

## Step 1 — Constitution submodule

Add the Constitution as a submodule at the standard path:

```sh
cd /path/to/consuming/project

git submodule add git@github.com:HelixDevelopment/constitution.git submodules/constitution
git submodule update --init submodules/constitution
```

Per Constitution §11.4.26 §1, fetch + pull all remotes before any edit:

```sh
git -C submodules/constitution fetch --all
git -C submodules/constitution pull --ff-only origin main
```

Verify the submodule is at a known HEAD:

```sh
git -C submodules/constitution rev-parse --short HEAD
# expect something like: ecfb6339
```

Record this in `.gitmodules` — the `submodules/constitution` entry should already
be present from `git submodule add`.

---

## Step 2 — Install the extension file

From the consuming project root, link or copy the extension into Pi's extensions
directory:

```sh
# Option A: symlink (recommended — single source of truth in the submodule)
ln -s submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts

# Option B: copy (independent snapshot; re-copy on each Constitution bump)
cp submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts
```

Verify the file is in place:

```sh
ls -la ~/.pi/agent/extensions/pi-constitution.ts
```

### Why symlink?

The plugin's canonical source lives in the Constitution submodule. A symlink keeps
one source of truth: when the Constitution is bumped to a new HEAD with plugin
updates, the symlink automatically reflects them. A copy must be re-copied manually.

---

## Step 3 — Register in Pi settings

Pi auto-discovers extensions in `~/.pi/agent/extensions/`. Add `pi-constitution`
to the active extensions list.

### Via `pi config` (TUI)

```sh
pi config
```

Navigate to the extensions section and enable `pi-constitution`.

### Via settings.json (direct)

Edit `~/.pi/agent/settings.json`:

```json
{
  "extensions": [
    "pi-constitution"
  ]
}
```

If other extensions are already listed, append:

```json
{
  "extensions": [
    "existing-extension",
    "pi-constitution"
  ]
}
```

### Via CLI

```sh
pi install pi-constitution
```

Restart Pi for the extension to load.

---

## Step 4 — Project integration manifest (optional)

If the consuming project tracks a `.specify/integrations/pi.manifest.json`, add the
plugin files so the integration record reflects the binding:

```json
{
  "integration": "pi",
  "version": "1.0.0",
  "installed_at": "2026-11-25T00:00:00.000000+00:00",
  "files": {
    "submodules/constitution/plugins/pi-constitution/plugin.json": "pi.extension.v1 manifest",
    "submodules/constitution/plugins/pi-constitution/pi-constitution.ts": "extension implementation"
  }
}
```

---

## Step 5 — Extension hooks (optional)

If the project uses Spec Kit extension hooks via `.specify/extensions.yml`, register
pi-constitution to run after constitution changes:

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

## Step 6 — Verify

Restart Pi, then run the doctor tool:

```sh
pi-constitution-doctor
```

Expected output (all green):

```
## pi-constitution-doctor Audit Results

**Constitution governance is healthy.**

| Check | Status |
|---|---|
| Submodule | present |
| Submodule HEAD | ecfb63395d06 |
| Governance Constitution.md | present |
| Governance CLAUDE.md | present |
| Governance AGENTS.md | present |
| Mandate §11.4.26 | present (Constitution.md, CLAUDE.md, AGENTS.md) |
| Mandate §11.4.28 | present (Constitution.md, CLAUDE.md, AGENTS.md) |
| Mandate §11.4.31 | present (Constitution.md, CLAUDE.md, AGENTS.md) |
| Mandate §11.4.32 | present (Constitution.md, CLAUDE.md, AGENTS.md) |
```

Also verify `session_start` fired: on next Pi start, look for a `pi-constitution.audit`
custom message in the transcript.

---

## Offline / air-gapped install

If the machine has no network access to GitHub:

```sh
# On a networked machine, bundle the plugin:
tar czf pi-constitution-bundle.tar.gz \
    submodules/constitution/plugins/pi-constitution/

# Transfer the bundle to the air-gapped machine, then:
mkdir -p ~/.pi/agent/extensions
tar xzf pi-constitution-bundle.tar.gz -C /tmp
cp /tmp/submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts
```

The Constitution submodule itself must also be available locally (via a bundled
clone or `git bundle`).

---

## Uninstall

```sh
# Remove the extension file
rm ~/.pi/agent/extensions/pi-constitution.ts

# Remove from settings
# Edit ~/.pi/agent/settings.json and drop "pi-constitution" from extensions

# Remove project manifest entry (if added)
# Edit .specify/integrations/pi.manifest.json

# Remove hook entry (if added)
# Edit .specify/extensions.yml
```

Restart Pi. The extension will no longer load.

---

## Upgrading

When the Constitution submodule is bumped to a new HEAD containing plugin changes:

```sh
cd /path/to/consuming/project

# Fetch + pull Constitution (per §11.4.26)
git -C submodules/constitution fetch --all
git -C submodules/constitution pull --ff-only origin main

# If using symlink: nothing to do — symlink follows the submodule
# If using copy: re-copy the updated file
cp submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts

# Bump the submodule pointer in the consuming project
git add submodules/constitution
git commit -m "build(submodules): bump constitution submodule to <new-head>"
```

Restart Pi after upgrading.
