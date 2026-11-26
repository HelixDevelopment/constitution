# pi-constitution — Troubleshooting

**Version:** 1.0.0 · **Audience:** operators and developers diagnosing pi-constitution issues

Common problems, their causes, and remediation steps.

---

## Table of contents

- [Extension fails to load](#extension-fails-to-load)
- [session_start is silent](#session_start-is-silent)
- [pi-constitution-doctor not found](#pi-constitution-doctor-not-found)
- [Guard prompt never appears](#guard-prompt-never-appears)
- [Guard prompt blocks everything](#guard-prompt-blocks-everything)
- [Submodule missing at session start](#submodule-missing-at-session-start)
- [Triage error: constitution_submodule_missing](#triage-error-constitution_submodule_missing)
- [Triage error: constitution_governance_file_missing](#triage-error-constitution_governance_file_missing)
- [Triage error: constitution_mandate_section_missing](#triage-error-constitution_mandate_section_missing)
- [Doctor reports unhealthy but files exist](#doctor-reports-unhealthy-but-files-exist)
- [Provider rejects tool name](#provider-rejects-tool-name)
- [Extension not in pi list](#extension-not-in-pi-list)
- [Symlink broken after Constitution bump](#symlink-broken-after-constitution-bump)
- [Getting help](#getting-help)

---

## Extension fails to load

### Symptom

`pi --help` or `pi list` shows:
```
Failed to load extension "/home/milosvasic/.pi/agent/extensions/pi-constitution.ts": <error>
```

### Causes & fixes

| Cause | Fix |
|---|---|
| Syntax or import error in `pi-constitution.ts` | Run `pi --help` to see the full error; fix the TypeScript; the file must import only from `@earendil-works/pi-coding-agent` |
| File not in extensions directory | Ensure `~/.pi/agent/extensions/pi-constitution.ts` exists |
| Not listed in settings `extensions` | Add `"pi-constitution"` to `~/.pi/agent/settings.json` extensions array, or use `pi config` |
| Pi needs restart | Restart Pi after installing or modifying the extension |

### Verification

```sh
ls -la ~/.pi/agent/extensions/pi-constitution.ts
pi --help   # should NOT show "Failed to load extension" for pi-constitution
pi list     # should list pi-constitution among extensions
```

---

## session_start is silent

### Symptom

No Constitution audit appears when starting a Pi session.

### Causes & fixes

| Cause | Fix |
|---|---|
| Extension not loaded | See "Extension fails to load" above |
| session_start handler threw silently | Check Pi logs/errors; the handler wraps `pi.exec` in try/catch but `ctx.ui.setStatus` may throw in non-TUI modes |
| Running in print/JSON mode | `ctx.ui` methods may be limited in `print`/`json` modes; audit still runs but status line may not render |

### Verification

Start Pi and check the transcript for a `pi-constitution.audit` custom message, or run:
```sh
pi-constitution-doctor
```

---

## pi-constitution-doctor not found

### Symptom

`pi-constitution-doctor` is not recognized as a tool/command.

### Causes & fixes

| Cause | Fix |
|---|---|
| Extension not loaded | Tool is registered only when the extension loads; see "Extension fails to load" |
| Tool name typo | Correct name is `pi-constitution-doctor` (dashes only, no colon) |
| Pi not restarted after install | RegisterTool takes effect on extension load; restart Pi |

### Verification

```sh
pi-constitution-doctor   # should return a full audit report
```

---

## Guard prompt never appears

### Symptom

A bash command touching `submodules/constitution` runs without the peer-gate confirmation, even when the submodule is missing.

### Causes & fixes

| Cause | Fix |
|---|---|
| Command string doesn't match any pattern | The guard intercepts commands containing `submodules/constitution`, `Constitution.md`, `CLAUDE.md`, `AGENTS.md`, or `pi-constitution`. If your command uses a different path or variable, it won't be intercepted |
| Submodule is present | The guard only activates when `test -d submodules/constitution` fails; if the submodule exists, no gate is needed |
| Non-bash tool | The guard only handles `bash` tool calls; `read`, `edit`, `write` are not intercepted |

### Verification

```sh
# With submodule missing:
git -C submodules/constitution pull   # should trigger the confirm dialog
```

---

## Guard prompt blocks everything

### Symptom

Every Constitution-relevant command is blocked by the peer-gate dialog.

### Cause

The submodule is missing or the `test -d` check fails.

### Fix

Initialize the submodule:

```sh
git submodule update --init submodules/constitution
```

Then verify:
```sh
test -d submodules/constitution && echo "present"
pi-constitution-doctor   # should be all green
```

The guard will stop blocking once the submodule exists.

---

## Submodule missing at session start

### Symptom

`session_start` reports `constitution_submodule_missing`.

### Fix

```sh
git submodule update --init submodules/constitution
```

Then check the submodule is at a known HEAD:
```sh
git -C submodules/constitution rev-parse --short HEAD
```

---

## Triage error: constitution_submodule_missing

### Symptom

```
- [constitution_submodule_missing] Constitution submodule not found at submodules/constitution. Run: git submodule update --init submodules/constitution
```

### Fix

```sh
git submodule add git@github.com:HelixDevelopment/constitution.git submodules/constitution
git submodule update --init submodules/constitution
git -C submodules/constitution fetch --all
git -C submodules/constitution pull --ff-only origin main
```

---

## Triage error: constitution_governance_file_missing

### Symptom

```
- [constitution_governance_file_missing] Governance file missing: submodules/constitution/CLAUDE.md
```

### Fix

The named governance file is absent from the Constitution submodule. Restore it from upstream:

```sh
git -C submodules/constitution fetch --all
git -C submodules/constitution checkout main -- <missing-file>
# or if the file was deleted upstream:
git -C submodules/constitution pull --ff-only origin main
```

Then verify:
```sh
pi-constitution-doctor
```

---

## Triage error: constitution_mandate_section_missing

### Symptom

```
- [constitution_mandate_section_missing] Mandate section §11.4.26 not found in any governance file
```

### Fix

The mandate section is not referenced in `Constitution.md`, `CLAUDE.md`, or `AGENTS.md`. This is a Constitution content issue, not a plugin issue. Add the section reference to the appropriate governance file in the Constitution submodule, commit, push to all remotes, and bump the consumer pointer.

---

## Doctor reports unhealthy but files exist

### Symptom

`pi-constitution-doctor` reports errors even though you can see the files on disk.

### Causes & fixes

| Cause | Fix |
|---|---|
| Running from wrong directory | `ctx.cwd` is the Pi session's cwd; ensure you're in the project root that contains `submodules/constitution` |
| Submodule not initialized | `git submodule update --init submodules/constitution` |
| File permissions | Ensure the governance files are readable: `ls -la submodules/constitution/Constitution.md` |
| Stale submodule pointer | The parent's gitlink points to an old HEAD; run `git submodule update --remote submodules/constitution` |

---

## Provider rejects tool name

### Symptom

LLM provider returns: `Function at index N has an invalid name: "pi-constitution:doctor". Only a-z, A-Z, 0-9, underscores, and dashes are allowed.`

### Cause

The tool name contained a colon (`:`). Providers restrict tool names to `[a-zA-Z0-9_-]`.

### Fix

The extension was fixed in v1.0.0 to use `pi-constitution-doctor` (dashes). Ensure you're running the latest version:

```sh
git -C submodules/constitution pull --ff-only origin main
# re-copy or re-symlink the extension file
```

---

## Extension not in pi list

### Symptom

`pi list` does not show `pi-constitution`.

### Fix

Pi discovers extensions from `~/.pi/agent/extensions/`. Ensure the file is there:

```sh
ls ~/.pi/agent/extensions/pi-constitution.ts
```

Then check settings:
```sh
# ~/.pi/agent/settings.json should include:
# "extensions": ["pi-constitution"]
```

Restart Pi.

---

## Symlink broken after Constitution bump

### Symptom

After `git submodule update` to a new Constitution HEAD, the symlink target changed or the path is different.

### Fix

Symlinks are relative to `~/.pi/agent/extensions/`, not to the submodule. If you used a relative symlink like `submodules/constitution/plugins/...` it will break because it's resolved from `~/.pi/agent/extensions/`, not from the project root.

**Fix:** Use an absolute symlink or copy:

```sh
# Absolute symlink
ln -sf /abs/path/to/project/submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts

# Or copy (independent snapshot)
cp submodules/constitution/plugins/pi-constitution/pi-constitution.ts \
    ~/.pi/agent/extensions/pi-constitution.ts
```

---

## Getting help

1. Run `pi-constitution-doctor` — it gives a structured, machine-readable audit
2. Check the transcript for `pi-constitution.audit` and `pi-constitution.triage` custom messages
3. Verify the extension loads: `pi --help` should not show "Failed to load extension" for pi-constitution
4. Verify all Constitution remotes are in sync: `git -C submodules/constitution fetch --all` then compare `git rev-parse <remote>/main` across remotes
