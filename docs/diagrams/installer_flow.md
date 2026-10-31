# Installer flow

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | End-to-end flow of the curl-installer. Reconciled with the final scripts on 2026-10-29; not checked against a live installer run. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | The one-command installer and updater. |
| Issues | none |

```mermaid
flowchart TD
    A["curl -fsSL RAW_URL piped to bash"] --> B["main runs as last line of the script"]
    B --> C["Preflight: git repo, clean paths, upstream reachable, 1 GiB disk, bash 4.4+"]
    C -->|blocked| X3["exit 3 precondition blocked"]
    C --> D{"Mode detection"}
    D -->|"none present"| E["ADD: git submodule add submodules/constitution"]
    D -->|"submodules/constitution present"| F["UPDATE: run update_constitution.sh"]
    D -->|"legacy ./constitution present"| G["LEGACY: explain, do not move automatically"]
    E --> H["checkout ref, submodule update, run setup.sh"]
    F --> I["fast-forward to target ref, post-update hook"]
    G --> J["hand migration to agent prompt or print manual steps"]
    H --> K{"Agent selected?"}
    I --> K
    J --> K
    K -->|"none"| N["Post-verify, deterministic, no LLM"]
    K -->|"agent"| L["Run agent headlessly with latest.md prompt"]
    L -->|"result is_error true"| X4["exit 4 agent run failed"]
    L --> M{"Follow-ups on?"}
    M -->|"yes and previous success"| M2["resume same session"]
    M -->|"no"| N
    M2 --> N
    N -->|"fail"| X5["exit 5 verification failed"]
    L -->|"opencode or pi exit 0, unverifiable"| X6["exit 6 agent success UNVERIFIED"]
    N -->|"pass"| O["write report JSON, exit 0"]
```

Reading notes: the installer never pushes; every file it modifies is first copied
into `.constitution-install-backup/<timestamp>/` (see [safety model](safety_backup_model.md)).
