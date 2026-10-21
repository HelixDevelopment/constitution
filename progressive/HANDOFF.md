# HANDOFF

## For consumers: nothing to do

With the submodule present, the surfaces (`surfaces/skills`,
`surfaces/plugins`, `surfaces/.helix/*`, `surfaces/mcp.json.template`) are
discoverable and the server runs from the submodule path. `Constitution.md` is
untouched, so every existing reader keeps working.

## Emergency rollback

```bash
export HELIX_CONSTITUTION_MODE=monolith
```
That restores the exact pre-optimization behaviour: only `Constitution.md` is
used and the generated layer is ignored. No file needs to be reverted.

## Where things live

| Artifact | Path |
|---|---|
| lean core | `constitution/progressive/core.md` |
| catalog | `constitution/progressive/catalog.json` |
| per-anchor rules | `constitution/progressive/rules/<id>.md` |
| generator / validators | `constitution/progressive/*.py` |
| MCP server | `constitution/progressive/mcp_server.py` |
| evidence | `constitution/progressive/EVIDENCE/` |
| plan / matrix / risks | `constitution/progressive/docs/` |

## Items still open

1. Run the AOSP sandbox comparison and record image/SDK hashes (needs a build).
2. Obtain an independent fresh-clone sign-off and commit it under `EVIDENCE/`.
3. Cut the baseline tag for the constitution (naming: the repo's tags are
   `helixconstitution-vNN`, not `v76-baseline`).
