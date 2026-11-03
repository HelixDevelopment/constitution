# Decision flow

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-30T09:00:00Z |
| Status | draft |
| Status summary | Wizard flow from `constitution_decisions.sh --help` (exit codes, refusals, backups) plus the installer's `--decision-layer` choice. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | Decisions wizard and installer decision-layer option. |
| Issues | none |

```mermaid
flowchart TD
    A["constitution_decisions.sh"] --> B{"action flag?"}
    B -->|none and TTY| C["ask every decision on /dev/tty"]
    B -->|none and no TTY| X2["exit 2"]
    B -->|--show --check --plan| R["read only"]
    B -->|--set --unset --reset --import --answers| V["validate against catalogue"]
    C --> V
    V -->|locked rule weakened, unknown key, secret-like value, tampered| X4["exit 4 refused"]
    V -->|no inherited constitution or path outside project| X3["exit 3"]
    V -->|lock held| X5["exit 5"]
    V -->|ok| BK["backup to .constitution-install-backup/UTC-decisions"]
    BK --> W["write .constitution/decisions.yml and managed doc block"]
    W --> P["print bootstrap command, not run"]
```

```mermaid
flowchart TD
    Q["installer --decision-layer"] -->|off default| N["nothing"]
    Q -->|shadow| B1["scripts/jev/bootstrap.sh --non-interactive"]
    Q -->|enforce| B2["bootstrap.sh --non-interactive --enforce"]
```

See [guide](../guides/decisions_wizard_guide.md).
