# Trust model

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
| Status | draft |
| Status summary | Who is trusted for what, and the opt-outs. Derived from the headers of setup.sh and the hooks on 2026-10-29. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | Helix Constitution installer, updater and extensions. |
| Issues | none |

```mermaid
flowchart TD
    T1["You run curl | bash"] -->|"trusts the server; read the script first"| I["installer"]
    I -->|"sanitised git env, redacted URLs, no push"| S["submodule checkout"]
    P["git pull / submodule update"] --> HK["installed hook (self-contained copy)"]
    HK --> C1{"autoPropagate off?<br/>git config constitution.autoPropagate false<br/>or CONSTITUTION_AUTO_PROPAGATE=off"}
    C1 -->|yes| W["print manual command, run nothing"]
    C1 -->|no| C2{"new commit full hex id AND reachable from submodule origin default branch AND not a downgrade?"}
    C2 -->|no| W
    C2 -->|yes| R["run post_update_hook.sh of the NEW commit (fetched code)"]
    G["setup.sh hooks dir"] -->|"machine-wide or outside project"| RF["refused unless --allow-global-hooks-path"]
```

The hooks execute code that was just fetched, on purpose (§11.4.164 auto-propagation); the checks above bound it. `setup.sh` itself runs the checkout's hook without those checks (you are running it by hand). A branch switch through git's own submodule recursion runs no hook at all.
