# Progressive disclosure — architecture and migration

## Three layers

1. **Core (`core.md`, 999 tokens)** — covenant, pointers, cross-cutting
   invariants. This is the only constitution text loaded up front.
2. **Catalog (`catalog.json`)** — one entry per anchor: id, title, one-line
   description, tags, rule path. Never loaded in full by an agent; queried
   through the MCP server. Digests and line ranges live in `rules_manifest.json`,
   read only by `verify_anchor` and the validators.
3. **Rules (`rules/<id>.md`, 289 files)** — the exact clause text, generated from
   `Constitution.md`, loaded by id.

## Meta-tools

`search_constitution`, `load_rule`, `list_anchors`, `verify_anchor` — served by
`progressive/mcp_server.py` over stdio. Local and offline.

## Modes

| `HELIX_CONSTITUTION_MODE` | Behaviour |
|---|---|
| `progressive` (default) | core + on-demand rules |
| `dual` | core + full text available |
| `monolith` | exact pre-optimization behaviour (`Constitution.md` only) |

## Consumer migration

Nothing is required: when the submodule is present, the surfaces
(`surfaces/skills`, `surfaces/plugins`, `surfaces/.helix`, `surfaces/mcp.json.template`)
are discoverable and the server runs from the submodule path. A consumer that
wants the old behaviour sets `HELIX_CONSTITUTION_MODE=monolith`.

## Double-loading

The skill and the plugin wrap the same server. `HELIX_CONSTITUTION_PLUGIN=1`
makes the skill defer so the tools are never registered twice.
