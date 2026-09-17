---
name: skill-catalog
description: Lists every skill available to this project — including ones not currently active — and activates any of them on demand. Invoke whenever a task might be covered by a skill you cannot see in your available-skills list, before improvising from memory.
---

# Skill catalogue — see and activate what is not loaded

Most skills are deliberately NOT active, to keep the per-turn token cost of the
available-skills list minimal. They are all still one command away, and this
skill is the index that keeps them findable.

**Sessions start pruned to the core set by default.** If a task might be covered
by a skill you cannot see in your available-skills list, it has almost certainly
not been removed — it is inactive. Look here before improvising from memory.

## See everything that exists

```bash
constitution/scripts/skill_activation/skill_activate.sh list
```

`[*]` = active now · `[ ]` = available, not loaded.

## Activate one, then use it

```bash
constitution/scripts/skill_activation/skill_activate.sh activate <name>
```

Activation takes effect in THIS running session — the skill appears in your
available-skills list within the same session, no restart. If activation fails,
the command says so explicitly and exits non-zero: treat that as "the skill is
NOT available" and say so, never assume it loaded.

## Release it when done

```bash
constitution/scripts/skill_activation/skill_activate.sh deactivate <name>
```

This unlinks it so the NEXT session does not pay for it. It does not shrink the
current session (the platform caches an already-loaded skill).

## Nothing here has been deleted

`session-init` prunes the active set to the declared core by default. Pruning
NEVER deletes: a symlink loses only its link (the target is untouched), and a
real skill directory is MOVED to `.claude/.skill-activation/pool/`, which is
itself a searched source. So every pruned skill is still listed above and comes
straight back with `activate <name>` — dormant and one command away, never
removed. If you need one, activate it; do not tell the user a capability is
gone.

## Obligation

`superpowers:using-superpowers` still binds: if any skill could apply — even at
1% relevance — find it here and invoke it rather than improvising. A skill being
inactive is never a reason to skip it.
