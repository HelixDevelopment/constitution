# Jev Decision Layer — Diagrams

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-10-23 |
| Last modified | 2026-11-17T03:25:18Z |
| Status | active |
| Status summary | Mermaid diagrams: architecture, data flow, bootstrap state machine, failover and placement sequence, the start and its start intent (round 14), routing and consensus sequence. |
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
- [Failover and placement sequence (2026-11-12)](#failover-and-placement-sequence-2026-11-12)
- [The start and its start intent (2026-11-17)](#the-start-and-its-start-intent-2026-11-17)
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
    MCPJ["mcp/templates/jev-decisions.json.tmpl"]
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

## Failover and placement sequence (2026-11-12)

How one decision reaches an endpoint after the S3/S4 changes. The ordered list is the endpoint cache (lower priority first): the local gateway at 10 when a lease is held, then the hosted entries (OpenRouter 30, TypeSafe 40 on the reference host). Whether a failed call moves on to the next entry is decided by the claude_toolkit gate and MCP server, which this repository does not ship; the constitution writes the cache entry, the placement record and the probe classes. Measured 2026-11-12 (T4): a session pinned to OpenRouter (`CMA_JEV_ENDPOINT_ID`) got 402, logged `fallback: endpoint_error` and allowed the call fail-open WITHOUT trying TypeSafe, so the failover branch below is the intended order, not a shown behaviour.

```mermaid
sequenceDiagram
  autonumber
  participant S as Session
  participant P as jev-place.sh
  participant L as llmctl
  participant K as Endpoint cache
  participant G as Toolkit gate / MCP
  participant E1 as llmctl-local (priority 10)
  participant E2 as OpenRouter (30)
  participant E3 as TypeSafe (40)
  S->>P: acquire <holder> --pid <pid>
  P->>L: capacity --json (bounded)
  opt an existing set whose holders were all reaped, constitution-started, and whose own unit is degraded or gone
    P->>L: stop <that profile> (bounded; rc 0 drops the set and its cache entry, a failure keeps stop_owed and is retried)
  end
  alt verdict fits / fits_with_reduced_threads
    P->>L: start <profile> (bounded)
    P->>L: capacity --json again (observation newer than the start)
    P->>K: llmctl-local at priority 10, derived from the lease registry once the unit is read ok
  else does_not_fit or undetermined
    P-->>S: rc 5, placement route cloud (key present) or none
  end
  S->>G: gated tool call
  G->>K: read ordered endpoints
  G->>E1: decision request
  alt 2xx
    E1-->>G: typed answer
  else non-2xx or unreachable (failover NOT shown live; T4 pinned session failed open)
    G->>E2: decision request
    alt 402 no_credit / 429 / error
      G->>E3: decision request
      E3-->>G: typed answer (2xx)
    end
  end
  G-->>S: allow / ask / deny (decisions.jsonl row)
  S->>P: release <holder> (last lease)
  P->>L: stop <profile> (only if the constitution started it; bounded by the start/stop timeout)
  alt stop rc 0
    P->>K: remove llmctl-local
  else stop failed or timed out
    P-->>S: rc 6, set kept (stop_failed); the next release retries
  end
```

## The start and its start intent (2026-11-17)

How `jev-place.sh` starts a model since round 14 (review R13-B1, §11.4.291). The start runs in a start process that exists before the registry write naming it, and that runs llmctl only after that write, so every `llmctl start` that runs is named by a durable start intent. A second acquire (B) judges a dead starter's intent only with an observation taken after the start process and its process group were gone. Gate-logic evidence only (`docs/qa/jev_s3s4_20261112/round14/`): what a real `llmctl start` leaves in another process group or session when its client is killed is UNCONFIRMED.

```mermaid
sequenceDiagram
  autonumber
  participant A as Acquire A (starter)
  participant G as Start process (jev-start-gate.sh)
  participant R as Lease registry (under the lock)
  participant L as llmctl
  participant B as Acquire B
  A->>G: spawn, outside the lock, it waits on a fifo only A writes
  A->>R: one write: set + starting mark + start intent naming A and G (pid, start time)
  alt the mark is refused
    A->>G: no (G exits 79, llmctl never runs)
  else the mark is written
    A->>G: go
    G->>L: exec timeout llmctl start (process group id = G's pid)
    Note over A,G: A SIGKILLed here: G keeps running. A killed before go: G reads end-of-file, exits 79
    B->>R: ticket: which intents' start processes are provably gone now
    B->>L: capacity --json (read after the ticket)
    alt A dead and G (or its group) may still run, or was not gone at B's ticket
      B->>R: intent kept: no adoption, no second start
    else A dead and G gone at B's ticket
      B->>R: set exists -> constitution-started, no set and unit runs -> lease-less constitution-started set with an owed stop, unit absent -> intent removed
    end
    G-->>A: exit code (A alive): A records the result and removes its own intent
  end
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
