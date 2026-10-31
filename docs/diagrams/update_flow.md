# Update flow

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
| Status | draft |
| Status summary | How `update_constitution.sh` decides. Reconciled with its --help on 2026-10-29. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | Helix Constitution installer, updater and extensions. |
| Issues | none |

```mermaid
flowchart TD
    A["update_constitution.sh [--check|--dry-run]"] --> B["find submodule + project (either layout)"]
    B --> C{"local changes or project is the constitution?"}
    C -->|yes| X3["exit 3 blocked"]
    C --> D["git fetch --quiet --tags on every remote"]
    D -->|"all fetches fail"| X3
    D --> E{"HEAD on a remote branch or remote tag?"}
    E -->|no| X3
    E --> F["target: --ref, else newest helixconstitution-vN tag on a remote, else origin/main"]
    F --> G{"target vs HEAD"}
    G -->|"equal or behind"| OK["already up to date, exit 0"]
    G -->|diverged| X3
    G -->|"fast-forward"| H{"--check?"}
    H -->|yes| Q["print UPDATE_AVAILABLE=yes, exit 0"]
    H -->|no| I["checkout target (detached)"]
    I --> J["post_update_hook.sh with CONSTITUTION_JEV_HOOK=off (skip: --no-hook)"]
    J -->|fail| X1["exit 1"]
    J --> K["print before/after sha + changelog delta; stage gitlink; commit only with --commit"]
```

`--check` and `--dry-run` still fetch; they never move HEAD or touch the project.
