# Setup prompt rotation

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | State of docs/prompts/setup when a new prompt is rotated in. Reconciled with the final scripts on 2026-10-29; not checked against a live installer run. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | The one-command installer and updater. |
| Issues | none |

```mermaid
stateDiagram-v2
    [*] --> Stable: latest.md plus numbered history
    Stable --> DryRun: rotate_setup_prompt.sh NAME --dry-run
    DryRun --> Stable: plan printed, zero writes
    Stable --> Rotating: rotate_setup_prompt.sh NAME
    Rotating --> Refused: collision or dirty state
    Refused --> Stable: nothing changed
    Rotating --> Rotated: latest.md renamed to NN_NAME.md, new content becomes latest.md
    Rotated --> Stable
```

NN is the highest existing numeric prefix plus one, zero-padded to two digits (three after 99). `01_old.md` and `02_middle.md` are never modified.
