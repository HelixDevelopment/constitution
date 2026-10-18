---
name: helix-constitution
description: Load any Helix Constitution rule on demand (progressive disclosure). Use when a task touches governance, anti-bluff evidence, review rules, host safety, credentials, or token efficiency, or when an anchor id (§11.4.N) is mentioned.
---

# Helix Constitution (3-level progressive disclosure)

## Level 1 — metadata (always loaded)

| Need | Tool |
|---|---|
| find a rule by topic | `search_constitution(query)` |
| read one rule verbatim | `load_rule(anchor_id)` |
| enumerate anchors | `list_anchors(tag?)` |
| prove a rule file is untampered | `verify_anchor(anchor_id)` |

## Level 2 — body (loaded on invocation)

1. Search first: `search_constitution("<topic>")` → anchor ids.
2. Load only the hit you need: `load_rule("§11.4.141")`.
3. Quote the anchor id and the file path `constitution/progressive/rules/<id>.md`.
4. Never read `Constitution.md` in full when an anchor id is known.

## Level 3 — just-in-time files

- `constitution/progressive/core.md` — lean core (always loaded).
- `constitution/progressive/catalog.json` — searchable index.
- `constitution/progressive/rules/<id>.md` — one file per anchor.
- `constitution/Constitution.md` — canonical full text (fallback, unmodified).

## Double-load guard

If the plugin `helix-constitution` is active (`HELIX_CONSTITUTION_PLUGIN=1`), this
skill defers: it makes no tool calls of its own, because the plugin wraps the same
server.
