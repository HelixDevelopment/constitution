# Extension lifecycle

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
| Status | draft |
| Status summary | States of an extension in the engine (experimental, dormant, not independently GO'd; rounds 10 and 11 fixes landed, round 11 fixes and the round 12 A3 staging-pid fix (c252eed) pending independent re-review). From the engine README; UNCONFIRMED against a live agent. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | Helix Constitution installer, updater and extensions. |
| Issues | none |

```mermaid
stateDiagram-v2
    [*] --> Source: validate prints sha256
    Source --> Staged: add (pin or waiver, consent, lock, journal)
    Staged --> Installed: rename into _installed
    Installed --> Enabled: enable (consent recorded)
    Enabled --> Wired: wire --agent A
    Wired --> Enabled: unwire
    Enabled --> Installed: disable
    Installed --> [*]: remove
    Staged --> [*]: crash, next run rolls back
    Installed --> Revoked: catalog revokes id
    Revoked --> Installed: wire and enable refused (exit 3)
```

Bundled extensions cannot be removed, only disabled. `verify` exits 5 on any problem.
