# pi-constitution — Usage Guide

**Version:** 1.0.0 · **Audience:** developers and operators using pi-constitution in daily Pi sessions

This guide covers day-to-day usage: what happens automatically, how to run
on-demand audits, how guarded operations work, and example workflows.

---

## Table of contents

- [Automatic behavior (session_start)](#automatic-behavior-session_start)
- [On-demand audit: pi-constitution-doctor](#on-demand-audit-pi-constitution-doctor)
- [Guarded operations](#guarded-operations)
- [Example workflows](#example-workflows)
- [Reading the audit output](#reading-the-audit-output)
- [Reading triage messages](#reading-triage-messages)

---

## Automatic behavior (session_start)

Every time a Pi session starts, `pi-constitution` runs automatically. You do not
need to invoke anything.

### What it checks

| Check | What it means |
|---|---|
| Submodule present | `submodules/constitution` exists on disk |
| Submodule HEAD | The git commit the submodule points to |
| Governance files | `Constitution.md`, `CLAUDE.md`, `AGENTS.md` all present |
| Mandate sections | §11.4.26, §11.4.28, §11.4.31, §11.4.32 referenced across governance files |

### What it emits

1. A status line via `ctx.ui.setStatus("constitution", ...)` — shown in Pi's footer/status bar
2. A `pi-constitution.audit` custom message in the session transcript — full structured report
3. A `pi-constitution.triage` custom message per issue — deterministic triage code + next command

### Example healthy output

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

### Example unhealthy output

```
## pi-constitution audit
- Submodule: MISSING
- Governance Constitution.md: MISSING
- Governance CLAUDE.md: MISSING
- Governance AGENTS.md: MISSING
- Mandate §11.4.26: MISSING
- Mandate §11.4.28: MISSING
- Mandate §11.4.31: MISSING
- Mandate §11.4.32: MISSING

### Errors (4)
- [constitution_submodule_missing] Constitution submodule not found at submodules/constitution. Run: git submodule update --init submodules/constitution
```

---

## On-demand audit: pi-constitution-doctor

Run a full governance audit at any time during a session:

```sh
pi-constitution-doctor
```

### With detail flag

```sh
pi-constitution-doctor --detail
```

The tool returns:
- A human-readable formatted report (same format as session_start)
- A `structuredContent` block with machine-readable fields for scripts

### When to run it

- After bumping the Constitution submodule pointer
- Before committing changes to Constitution governance files
- When you suspect governance drift (submodule pointer out of sync)
- As a pre-flight check before pushing Constitution changes

---

## Guarded operations

Any bash command that references Constitution governance is intercepted by the
`tool_call` hook. Patterns that trigger interception:

| Pattern | Example |
|---|---|
| `submodules/constitution` | `git -C submodules/constitution pull` |
| `Constitution.md` | `cat submodules/constitution/Constitution.md` |
| `CLAUDE.md` | `edit submodules/constitution/CLAUDE.md` |
| `AGENTS.md` | `grep "§11.4" submodules/constitution/AGENTS.md` |
| `pi-constitution` | `cat plugins/pi-constitution/pi-constitution.ts` |

### When the submodule is present

The command runs normally — no interruption.

### When the submodule is missing

Pi shows a confirmation dialog:

> Constitution submodule missing — proceed anyway (risking governance drift)?
> Command: `git -C submodules/constitution pull`
>
> [SUFFICIENT] [NEEDS_FIX]

- **SUFFICIENT** — proceed with the command (governance drift risk accepted)
- **NEEDS_FIX** — abort; the command is blocked

### Why this exists

Per Constitution §11.4.26, no Constitution governance change may proceed without
the submodule being at upstream tip. The guard prevents accidental operations on
a missing or stale submodule that would silently corrupt the governance binding.

---

## Example workflows

### Workflow 1: Daily work (nothing to do)

Just start Pi. `session_start` audits the binding automatically. If everything
is green, continue working.

### Workflow 2: Bumping the Constitution submodule

```sh
# 1. Fetch + pull all Constitution remotes (§11.4.26 §1)
git -C submodules/constitution fetch --all
git -C submodules/constitution pull --ff-only origin main

# 2. Verify the binding is still healthy
pi-constitution-doctor

# 3. Make your changes inside the submodule (on a task/ branch)
git -C submodules/constitution checkout -b task/my-change
# ... edit files ...
git -C submodules/constitution add .
git -C submodules/constitution commit -m "feat: ..."

# 4. Push to all Constitution remotes (§11.4.26 §4)
git -C submodules/constitution push origin task/my-change
# ... push to all other remotes ...

# 5. Merge to Constitution main
git -C submodules/constitution checkout main
git -C submodules/constitution merge --no-ff task/my-change
git -C submodules/constitution push origin main
# ... push main to all remotes ...

# 6. Bump the consuming project's pointer (§11.4.26 §7)
git add submodules/constitution
git commit -m "build(submodules): bump constitution submodule to <new-head>"
git push origin main
```

### Workflow 3: Recovering from a missing submodule

```sh
# Pi session_start reports: constitution_submodule_missing
# The guard blocks any constitution-relevant command

# Initialize the submodule
git submodule update --init submodules/constitution

# Verify
pi-constitution-doctor

# Now constitution-relevant commands work again
```

### Workflow 4: Peer-gated command (submodule missing)

```sh
# You run: git -C submodules/constitution pull
# Pi intercepts: submodule is missing
# Pi prompts: proceed anyway?

# You choose NEEDS_FIX → command aborts
# You initialize the submodule, then retry
git submodule update --init submodules/constitution
git -C submodules/constitution pull  # now succeeds without interception
```

---

## Reading the audit output

The `pi-constitution.audit` custom message contains:

| Section | Contents |
|---|---|
| Header | `## pi-constitution audit` |
| Submodule | `present` or `MISSING` |
| HEAD | Short SHA (first 12 chars) |
| Governance files | `present` or `MISSING` per file |
| Mandate sections | `present (file1, file2)` or `MISSING` per section |
| Errors | Numbered list with triage codes and messages |
| Footer | `Constitution governance is healthy.` or issue count |

---

## Reading triage messages

Each `pi-constitution.triage` custom message has:

| Field | Meaning |
|---|---|
| `content` | Human-readable: `Constitution triage: <code> — <message>` |
| `details.code` | Deterministic triage code |
| `details.layer` | Always `"extension"` |
| `details.cause` | Root cause explanation |
| `details.nextCommand` | Suggested remediation command |

Example:
```
Constitution triage: constitution_governance_file_missing — Governance file missing: submodules/constitution/CLAUDE.md
```

Remediation: restore the missing governance file in the Constitution submodule,
commit, push to all remotes, then bump the consuming project's pointer.
