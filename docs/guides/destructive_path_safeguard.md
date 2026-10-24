# Destructive-Path Safeguard — keep an empty variable from deleting a home directory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-23 |
| Last modified | 2026-10-23T08:00:00Z |
| Status | active |
| Status summary | How to register and use the PreToolUse guard `scripts/hooks/guard-destructive-paths.py` and the runtime helper `scripts/lib/safe_rm.sh`, what they block, what they cannot see, and how to test them. |
| Authority | Constitution §11.4.287. The canonical text in `Constitution.md` wins over this guide. |
| Scope | Universal (§11.4.17). Paths below are examples; the consumer supplies its own protected children and allowed roots. |
| Issues | none |
| Issues summary | — |
| Fixed | — |
| Fixed summary | — |
| Continuation | — |

Related: [manual](../manuals/destructive_path_safeguard_manual.md) (install, classes, escape hatch, `safe_rm_rf` configuration, troubleshooting, decision-flow diagram) · [FAQ](../faq/destructive_path_safeguard_faq.md)

## Table of contents

1. [Why it exists](#1-why-it-exists)
2. [What the guard blocks](#2-what-the-guard-blocks)
3. [Register the guard](#3-register-the-guard)
4. [Use the runtime helper](#4-use-the-runtime-helper)
5. [Script rules](#5-script-rules)
6. [Test it](#6-test-it)
7. [What it cannot see](#7-what-it-cannot-see)

## 1. Why it exists

On 2026-10-23 a review subagent ran a scratch script of the shape `W="$2"; export HOME="$W/home"; rm -rf "$HOME"` with empty arguments. `$W` was empty, `$HOME` became `/home`, and a recursive delete ran with the operator's rights until a timeout stopped it. One empty variable became an unbounded delete, and no rule refused it. Two layers now do.

## 2. What the guard blocks

| Class | Shape | Overridable |
|---|---|---|
| P | A recursive delete, `chmod -R`, `chown -R`, `find -delete` or `rsync --delete` aimed at the root, a system directory, `/home`, a user home, `$HOME`, `~`, an ancestor of `$HOME` or a protected child of it | Never. The allow marker does not downgrade it. |
| H | `HOME` reassigned from an unguarded expansion, then a recursive delete under it (the incident) | Yes, with `# guardrails:allow <reason>` |
| V | A recursive delete of a variable derived from an unguarded positional parameter | Yes, with `# guardrails:allow <reason>` |

A variable counts as guarded by `${VAR:?msg}`, by a `[ -n "$VAR" ] || exit` test, or by a literal or `mktemp` assignment. Unparsable input is allowed with a warning, because a guard that blocks on its own parse failure blocks all work.

## 3. Register the guard

The guard reads the Claude Code hook JSON on stdin; exit 0 allows, exit 2 blocks and prints the reason. Add it to the consumer's `settings.json` (shown, not applied by the constitution; editing a user's settings needs that user's consent):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "python3 -I /path/to/constitution/scripts/hooks/guard-destructive-paths.py" }
        ]
      }
    ]
  }
}
```

Check it is live with a probe that must exit 2: pipe `{"tool_name":"Bash","tool_input":{"command":"<recursive delete of /home>"}}` into the command above.

## 4. Use the runtime helper

```bash
. /path/to/constitution/scripts/lib/safe_rm.sh
safe_rm_rf "${WORKDIR:?}/build"      # refuses empty, relative, system, home, ancestor-of-HOME and shallow targets
SAFE_RM_ALLOWED_ROOTS="$TMP_ROOT" safe_rm_rf "$TMP_ROOT/case1"   # optional second barrier
```

It returns 2 and deletes nothing on any refusal, and it validates every argument before deleting the first. `SAFE_RM_MIN_DEPTH` (default 3) sets the shallowest path it accepts.

## 5. Script rules

1. Expand a variable that names a path to delete as `"${VAR:?message}"`. An empty variable is still set, so `set -u` is not enough.
2. Never reassign `HOME` from an expansion that can be empty. A test that needs a fake home creates it with `mktemp -d` and checks it.
3. A test that deletes anything runs inside a sandbox whose root it created.
4. A brief for a subagent that may write scratch scripts states rules 1 to 3.
5. A block by the guard is a defect in the script. Fix the script; do not look for a way around the guard.

## 6. Test it

```bash
bash scripts/hooks/test_guard_destructive_paths.sh   # 62 cases, two paired mutations
bash scripts/lib/test_safe_rm.sh                     # 138 cases, one paired mutation, fake HOME in a sandbox
bash scripts/gates/cm_guard_class_p_not_overridable.sh
bash scripts/gates/cm_guard_class_p_not_overridable_mutation_test.sh
```

Measured 2026-10-23: 62 passed and 0 failed, 32 passed and 0 failed; the mutation test reports every mutant caught.

## 7. What it cannot see

The guard is a text scan, not a security boundary. It cannot see a command built at run time from a decoded string, a downloaded script, a binary, or a language runtime deleting through its own API. It does not replace file-system permissions, backups (§9.2) or the host-safety rules (§12). `safe_rm_rf` protects only the calls routed through it.
