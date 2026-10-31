# Mode detection (ADD, UPDATE, LEGACY)

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | How the installer decides what to do in a project. Reconciled with the final scripts on 2026-10-29; not checked against a live installer run. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | The one-command installer and updater. |
| Issues | none |

```mermaid
stateDiagram-v2
    [*] --> Inspect
    Inspect --> ADD: no constitution found
    Inspect --> UPDATE: submodules/constitution exists
    Inspect --> LEGACY: ./constitution exists
    Inspect --> Blocked: not a git repo, dirty paths, or the project is the constitution repo itself
    ADD --> Verify: submodule added, setup.sh run
    UPDATE --> Verify: update_constitution.sh fast-forward
    LEGACY --> Verify: migration handed to agent or manual steps printed
    Verify --> [*]: exit 0
    Blocked --> [*]: exit 3
```

Both layouts are supported by every script; `submodules/constitution` is the standard for new installs.
