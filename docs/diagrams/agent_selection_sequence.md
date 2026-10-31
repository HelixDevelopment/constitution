# Agent selection and headless run

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | Sequence of agent detection, questions and the headless run. Reconciled with the final scripts on 2026-10-29; not checked against a live installer run. |
| Authority | Documentation only; no new anchor. §11.4.258 (diagrams) governs. |
| Scope | The one-command installer and updater. |
| Issues | none |

```mermaid
sequenceDiagram
    participant U as User
    participant I as install_constitution.sh
    participant D as Detection (no LLM calls)
    participant A as Agent (claude, kimi, opencode, pi)
    U->>I: run installer
    I->>D: look for claude, aliases, kimi, opencode, pi, aider and others
    D-->>I: list with version and status
    I->>U: numbered menu and questions with safe defaults
    U-->>I: agent, model, effort, budget, timeout, consents
    I->>A: headless run with prompt from latest.md under timeout
    A-->>I: stream of events
    I->>I: success only if final result event has is_error false
    opt follow-ups on and previous success
        I->>A: resume same session, same cwd and env
        A-->>I: result event
    end
    I->>I: deterministic post-verify
    I-->>U: summary and report JSON path
```

Only the Claude family (native and provider aliases), kimi, opencode and pi are the headlessly drivable agents (only unit-class tested; provider aliases, kimi, opencode and pi are UNCONFIRMED against a live run); other detected agents are listed detect-only and refused as `--agent`.
