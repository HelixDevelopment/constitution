# Jev Decision Layer — Diagrams

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-23 |
| Last modified | 2026-10-23T00:00:00Z |
| Status | active |
| Status summary | Four Mermaid diagrams: architecture, data flow, bootstrap state machine, routing and consensus sequence. |
| Authority | Constitution §11.4.279–§11.4.286. The scripts and the claude_toolkit / llmctl sources govern wherever a diagram simplifies. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
| Fixed summary | — |
| Continuation | none |

Related: [governance guide](governance-guide.md) · [bootstrap reference](bootstrap-reference.md) · [user manual](user-manual.md)

## Table of contents

- [Architecture](#architecture)
- [Data flow of one gated tool call](#data-flow-of-one-gated-tool-call)
- [Bootstrap state machine](#bootstrap-state-machine)
- [Routing and consensus sequence](#routing-and-consensus-sequence)

## Architecture

Who owns what: the constitution owns policy, the bootstrap/status/calibration scripts and the declarations; claude_toolkit owns the per-agent gate, MCP server and endpoint cache; llmctl owns local models and the HTTPS decide gateway.

```mermaid
flowchart LR
  subgraph CONST["constitution (this repo)"]
    BS["scripts/jev/bootstrap.sh"]
    ST["scripts/jev/jev-status.sh"]
    CAL["scripts/jev/jev-calibrate.sh"]
    SK["skills/jev-decision-layer"]
    MCPJ["mcp/jev-decisions.json"]
  end
  subgraph TK["claude_toolkit"]
    SETUP["jev-setup.sh"]
    GATE["jev-gate.sh (PreToolUse)"]
    MCP["jev_mcp.py (stdio MCP)"]
    PROV["claude-providers sync-jev"]
    CACHE[("jev-endpoints.json")]
  end
  subgraph LL["llmctl"]
    GW["llmctl decide serve :8095 (HTTPS)"]
    PROF["decide profiles: decide-tiny ... decide-kev-* decide-laya"]
  end
  subgraph HOSTED["hosted systemone"]
    OR["OpenRouter"]
    TS["TypeSafe"]
  end
  AG["coding agent (claude, kimi, pi, opencode)"]
  BS --> SETUP
  BS --> PROV
  BS --> GW
  PROV --> CACHE
  SETUP --> GATE
  SETUP --> MCP
  AG --> GATE
  AG --> MCP
  GATE --> GW
  GATE --> OR
  GATE --> TS
  MCP --> GW
  MCP --> OR
  MCP --> TS
  GW --> PROF
  CAL -. reads .-> LOG[("decisions.jsonl")]
  GATE --> LOG
  ST -. reads .-> LOG
```

## Data flow of one gated tool call

Endpoint choice comes from the ranked cache at launch (local gateway first). The bearer key is resolved by variable NAME at call time and sent only over `https://`.

```mermaid
flowchart TD
  A["agent proposes a tool call"] --> B{"JEV_GATE=off?"}
  B -- yes --> B1["log to gate-off.log, pass through"]
  B -- no --> C["parse hook event, truncate state to 12000 chars, hash it"]
  C --> D["deterministic risk floor (pattern match)"]
  D --> E{"JEV_BASE_URL set?"}
  E -- no --> E1["log fallback endpoint_error, pass through (floor may ask in enforce)"]
  E -- yes --> F["POST /v1/systemone: choice gate + noul risky"]
  F --> G{"reply within JEV_GATE_TIMEOUT?"}
  G -- no --> G1{"JEV_GATE_FAIL=closed?"}
  G1 -- yes --> G2["deny"]
  G1 -- no --> G3["log fallback, pass through"]
  G -- yes --> H["map answer: deny / ask / allow, floor only escalates"]
  H --> I["append row to decisions.jsonl (state hash, never raw state)"]
  I --> J{"JEV_MODE=enforce?"}
  J -- no --> J1["shadow: pass through, decision only logged"]
  J -- yes --> J2["emit permissionDecision allow / ask / deny"]
```

## Bootstrap state machine

States are the stage results of `bootstrap.sh`. `no-change` is a per-stage outcome when the input digest equals the stamp.

```mermaid
stateDiagram-v2
  [*] --> Preflight
  Preflight --> Refused: no TTY and no --non-interactive (rc 2)
  Preflight --> Refused: jq missing (rc 2)
  Preflight --> Deferred: --defer (rc 0)
  Preflight --> Provision
  Provision --> OperatorStop: managed clone has local changes (rc 3)
  Provision --> DetectModels
  DetectModels --> InstallPerAgent
  InstallPerAgent --> PendingConsent: wiring needs consent
  InstallPerAgent --> Configure: wired, already wired, or toolkit unavailable
  PendingConsent --> Configure
  Configure --> CalibrateShadow
  CalibrateShadow --> Report
  Report --> Complete: nothing outstanding, pending file removed
  Report --> CompleteWithPending: reasons recorded in bootstrap.pending
  Deferred --> [*]
  Refused --> [*]
  OperatorStop --> [*]
  Complete --> [*]
  CompleteWithPending --> [*]
```

## Routing and consensus sequence

Applies to the MCP tool `jev_ask` when `decision_type` names a route in `JEV_ROUTES_FILE`. Without `min_agreement` a route is ordered failover; with it, two live candidates must agree.

```mermaid
sequenceDiagram
  autonumber
  participant Ag as Agent
  participant M as jev_mcp.py
  participant C1 as Candidate 1 (for example local gateway)
  participant C2 as Candidate 2 (for example OpenRouter)
  Ag->>M: jev_ask(state, question, options, decision_type)
  M->>M: load route from JEV_ROUTES_FILE
  alt no route for decision_type
    M->>C1: POST /v1/systemone (single configured endpoint)
    C1-->>M: typed answer
    M-->>Ag: answer, probabilities, confidence
  else route without min_agreement
    M->>C1: POST /v1/systemone
    alt answer present and confidence >= min_confidence
      C1-->>M: typed answer
      M-->>Ag: answer from candidate 1
    else failure or low confidence
      M->>C2: POST /v1/systemone
      C2-->>M: typed answer
      M-->>Ag: answer, or degraded:true with the best live answer
    end
  else route with min_agreement
    M->>C1: POST /v1/systemone
    C1-->>M: answer 1
    M->>C2: POST /v1/systemone
    C2-->>M: answer 2
    alt two answers equal and both >= min_confidence
      M-->>Ag: agreement:true, confidence = min of the two
    else
      M-->>Ag: degraded:true, agreement:false, highest-priority live answer
    end
  end
```

In the code at claude_toolkit `bfa667f` the candidates are queried sequentially, and with `min_agreement` set every candidate is consulted before the agreement check. The numeric value of `min_agreement` is not compared against anything in that code; only whether it is set matters. When no candidate is reachable the tool returns an error result, never a hang.
