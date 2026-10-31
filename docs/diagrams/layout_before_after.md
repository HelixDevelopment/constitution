# Layout before and after

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | Legacy and standard consumer layouts. Reconciled with the final scripts on 2026-10-29; not checked against a live installer run. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | The one-command installer and updater. |
| Issues | none |

```mermaid
flowchart LR
    subgraph Legacy["Legacy layout (still supported)"]
        L1["project/"] --> L2["constitution/ (submodule)"]
        L1 --> L3["CLAUDE.md points at constitution/"]
    end
    subgraph Standard["Standard layout (new installs)"]
        S1["project/"] --> S2["submodules/constitution/ (submodule)"]
        S1 --> S3["CLAUDE.md points at submodules/constitution/"]
    end
    Legacy -->|"migration with backups, via agent prompt or manual steps"| Standard
```

The installer does not move a legacy submodule by itself; it prints the plan and hands the migration to the setup prompt.
