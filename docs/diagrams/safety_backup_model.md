# Safety and backup model

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | How the installer protects a project. Reconciled with the final scripts on 2026-10-29; not checked against a live installer run. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | The one-command installer and updater. |
| Issues | none |

```mermaid
flowchart TD
    S["Installer about to modify a file"] --> B["Copy file to .constitution-install-backup/TIMESTAMP/"]
    B --> W["Modify file"]
    W --> V["Deterministic post-verify"]
    V -->|"pass"| OK["Done, nothing pushed"]
    V -->|"fail"| R["exit 5, restore from backup folder by copying files back"]
    S --> G{"Guards"}
    G --> G1["no force-push, no push at all"]
    G --> G2["refuses root unless --yes"]
    G --> G3["no recursive delete; leftovers are moved into the backup"]
    G --> G4["never deletes user files"]
    G --> G5["refuses the constitution repository itself, exit 3"]
    G --> G6["sanitised git environment, URLs redacted"]
```
