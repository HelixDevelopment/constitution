# CodeGraph — Status

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-05-21 |
| Last modified | 2026-10-05T09:59:56Z |
| Status | active |
| Status summary | Append-only ledger of every CodeGraph-related event across the constitution submodule's consuming projects: npm updates, sync runs, index regenerations, validate runs, HRDs opened/closed against CodeGraph. Per Universal §11.4.80 + §11.4.65 (multi-format export). Both `scripts/codegraph_update.sh` and `scripts/codegraph_sync.sh` append here automatically. R2 (2026-05-22): replaced project-specific `§107` anchor references with the universal `§11.4` covenant anchor to keep this submodule fully decoupled per §11.4.28. R3 (2026-10-05, currency check): backfilled the §11.4.275 EXTENSION history (both 2026-09-25 rounds — the host-adaptive V8 heap-budget fix + §11.4.275(D) benchmark run, and the heap-ceiling correction + CodeGraph MCP wiring + the `serve --mcp` stray-daemon forensic incident) that had landed in `Constitution.md` but was never appended to this ledger; see the `## 2026-10-05` entry below. A handful of earlier `§107` legend entries (2026-09-29) pre-date R2's rename and are left verbatim as the historical record they are. |
| Issues | none |
| Issues summary | — |
| Fixed | (n/a — ledger doc) |
| Continuation | sibling `Status_Summary.md` carries the operator-readable digest per §11.4.53. |

## Table of contents

- [Cadence + automation](#cadence--automation)
- [Event ledger](#event-ledger)

## Cadence + automation

Per §11.4.80, every consuming project MUST run `codegraph_update.sh` at least weekly and `codegraph_sync.sh` after every update + on every meaningful source-change cadence (varies by project). Cadence floor: weekly. Cadence ceiling: per-CI-run.

The scripts append entries below automatically; manual entries are also acceptable when an operator runs the commands directly.

## Event ledger

(events appended below by the automation; newest at the bottom)

## 2026-05-21T05:38:53Z — codegraph update FAILED (§11.4 bluff caught)

- before: `0.6.8`
- target: `0.8.0`
- after:  `unknown` (mismatch — npm exit 0 was bluffing)

## 2026-05-21T05:40:01Z — codegraph rolled back to 0.6.8 (Node-25 incompatibility)

- before: `0.8.0` (installed but non-functional on Node 25.x — engine range  + V8 WASM JIT bug)
- after:  `0.6.8` (last known-working on Node 25.x)
- decision: pin codegraph to 0.6.8 until Node 25 V8 issue is resolved upstream OR operator installs Node 22 LTS alongside
- §11.4 trail: `codegraph_update.sh` correctly caught the failed upgrade via the post-update version check — script working as designed
- follow-up HRD: ENV-CODEGRAPH-NODE25 to track when 0.7+/0.8+ becomes safe again

## 2026-05-21T12:41:31Z — codegraph update FAILED (§11.4 bluff caught)

- before: `0.6.8`
- target: `0.8.0`
- after:  `unknown` (mismatch — npm exit 0 was bluffing)

## 2026-05-21T12:49:03Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T12:51:16Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T14:31:35Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T15:17:07Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T15:21:55Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-21T15:26:34Z — codegraph version check

- current: `0.8.0`
- latest:  `0.8.0`
- action:  **no-op** (already at latest)

## 2026-05-22T08:44:36Z — codegraph version check

- current: `0.9.2`
- latest:  `0.9.2`
- action:  **no-op** (already at latest)

## 2026-05-28T10:21:08Z — codegraph updated

- before: `0.9.4`
- after:  `0.9.6`
- npm command: `npm install -g @colbymchenry/codegraph@0.9.6`

## 2026-05-28T14:26:35Z — codegraph version check

- current: `0.9.6`
- latest:  `0.9.6`
- action:  **no-op** (already at latest)

## 2026-05-29T18:51:55Z — codegraph version check

- current: `0.9.7`
- latest:  `0.9.7`
- action:  **no-op** (already at latest)

## 2026-06-19T06:48:34Z — codegraph version check

- current: `1.0.1`
- latest:  `1.0.1`
- action:  **no-op** (already at latest)

## 2026-06-19T14:07:13Z — codegraph version check

- current: `1.0.1`
- latest:  `1.0.1`
- action:  **no-op** (already at latest)

## 2026-06-19T14:10:20Z — codegraph version check

- current: `1.0.1`
- latest:  `1.0.1`
- action:  **no-op** (already at latest)

## 2026-06-19T14:27:50Z — codegraph version check

- current: `1.0.1`
- latest:  `1.0.1`
- action:  **no-op** (already at latest)

## 2026-06-19T14:32:34Z — codegraph version check

- current: `1.0.1`
- latest:  `1.0.1`
- action:  **no-op** (already at latest)

## 2026-06-28T08:41:49Z — codegraph updated

- before: `1.0.1`
- after:  `1.1.2`
- npm command: `npm install -g @colbymchenry/codegraph@1.1.2`

## 2026-06-28T08:55:56Z — codegraph version check

- current: `1.1.2`
- latest:  `1.1.2`
- action:  **no-op** (already at latest)

## 2026-06-28T10:33:47Z — codegraph version check

- current: `1.1.2`
- latest:  `1.1.2`
- action:  **no-op** (already at latest)

## 2026-06-29T13:44:38Z — codegraph version check

- current: `1.1.3`
- latest:  `1.1.3`
- action:  **no-op** (already at latest)

## 2026-06-29T17:00:30Z — codegraph version check

- current: `1.1.3`
- latest:  `1.1.3`
- action:  **no-op** (already at latest)

## 2026-07-02T05:03:01Z — codegraph updated

- before: `1.1.6`
- after:  `1.2.0`
- npm command: `npm install -g @colbymchenry/codegraph@1.2.0`

## 2026-07-04T23:43:24Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T00:03:06Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T05:47:55Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T05:57:16Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T06:28:49Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T06:46:15Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T06:55:53Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T07:06:09Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T07:15:25Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T07:28:29Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-05T07:58:20Z — codegraph version check

- current: `1.2.0`
- latest:  `1.2.0`
- action:  **no-op** (already at latest)

## 2026-07-17T14:46:51Z — codegraph updated

- before: `1.2.0`
- after:  `1.4.1`
- npm command: `npm install -g @colbymchenry/codegraph@1.4.1`

## 2026-07-17T14:57:14Z — codegraph version check

- current: `1.4.1`
- latest:  `1.4.1`
- action:  **no-op** (already at latest)

## 2026-08-13T07:19:41Z — codegraph version check

- current: `1.5.0`
- latest:  `1.5.0`
- action:  **no-op** (already at latest)

## 2026-08-13T07:47:09Z — codegraph version check

- current: `1.5.0`
- latest:  `1.5.0`
- action:  **no-op** (already at latest)

## 2026-08-13T08:05:01Z — codegraph version check

- current: `1.5.0`
- latest:  `1.5.0`
- action:  **no-op** (already at latest)

## 2026-08-31T14:39:09Z — codegraph version check

- current: `1.6.0`
- latest:  `1.6.0`
- action:  **no-op** (already at latest)

## 2026-08-31T14:53:31Z — codegraph version check

- current: `1.6.0`
- latest:  `1.6.0`
- action:  **no-op** (already at latest)

## 2026-09-01T12:34:39Z — codegraph version check

- current: `1.6.0`
- latest:  `1.6.0`
- action:  **no-op** (already at latest)

## 2026-09-01T15:59:41Z — codegraph version check

- current: `1.6.0`
- latest:  `1.6.0`
- action:  **no-op** (already at latest)

## 2026-09-01T17:18:59Z — codegraph version check

- current: `1.6.0`
- latest:  `1.6.0`
- action:  **no-op** (already at latest)

## 2026-09-29T14:46:47Z — codegraph update FAILED (§107 bluff caught)

- before: `1.6.0`
- target: `1.6.1`
- after:  `1.6.0` (mismatch — npm exit 0 was bluffing)

## 2026-09-29T14:47:30Z — codegraph update FAILED (§107 bluff caught)

- before: `1.6.0`
- target: `1.6.1`
- after:  `1.6.0` (mismatch — npm exit 0 was bluffing)

## 2026-09-29T14:56:33Z — codegraph update FAILED (§107 bluff caught)

- before: `1.6.0`
- target: `1.6.1`
- after:  `1.6.0` (mismatch — npm exit 0 was bluffing)

## 2026-09-29T15:17:33Z — codegraph update FAILED (§107 bluff caught)

- before: `1.6.0`
- target: `1.6.1`
- after:  `1.6.0` (mismatch — npm exit 0 was bluffing)

## 2026-09-29T15:27:35Z — codegraph update FAILED (§107 bluff caught)

- before: `1.6.0`
- target: `1.6.1`
- after:  `1.6.0` (mismatch — npm exit 0 was bluffing)

## 2026-10-05 — §11.4.275 EXTENSION history backfilled (currency check; events below occurred 2026-09-25, logged here retroactively on discovery that this ledger had not recorded them)

Per `constitution/Constitution.md` §11.4.275's own two "EXTENSION landed 2026-09-25" blocks (cited verbatim below, not paraphrased from memory per §11.4.6):

- **§11.4.78 host-adaptive V8 heap budget + §11.4.275(D) benchmark run (round 1, 2026-09-25).** `codegraph_safe.sh`'s single writer entry now computes its Node.js heap budget from measured `MemAvailable` instead of inheriting V8's ~4 GiB stock default, closing a real bulk-index OOM crash (`rc=134`) on this repo's 584K-file/49M-edge tree — landed with 2 new regression tests + live `/proc/<pid>/environ` verification + a zero-regression full-suite comparison (commit `941841d3e7235a081e3199a4d3073b409d41753b`). The §11.4.275(D) deterministic benchmark ran via `constitution/scripts/lumen/lumen_verify.sh`: a pre-declared 13-query golden set, N=3 byte-identical runs, recall 9/11 = 0.818, with the 2 failing/unsupported query classes (`.sh`/`.kt`, unindexed by Lumen's chunker — confirmed via direct `sqlite3` + Lumen's own source) reported honestly and tracked, never averaged away (commit `ac532a21df78a447c2aceec30f63476348e93077`, `docs/research/lumen_benchmark_20260925/RESULTS_v2.md`).
- **§11.4.78 heap ceiling correction + CodeGraph MCP wiring (round 2, 2026-09-25).** The round-1 64 GiB heap cap is corrected — it was an INVENTED ceiling (~25% of this 251 GiB host's RAM), not a derivation of §12.6; fixed to `MemTotal * 60/100` computed fresh every run, the real unweakened §12.6 bound (commit `8a5f47ab2e0e7a05d1c1652ba5a3475751652062`, regression test U46). Separately: `.mcp.json` was found completely EMPTY — CodeGraph had ZERO agent-facing MCP presence in this repository despite its full query toolset. Fixed by registering `.mcp.json`'s `codegraph` server against a new, tested, §11.4.177-decoupled wrapper (`constitution/scripts/codegraph/codegraph_mcp_serve.sh`) that resolves the SAME validated patched runner `codegraph_safe.sh` (never bare stock-on-PATH). A SEPARATE, more serious forensic incident surfaced while building this: `serve --mcp`'s file watcher WRITES (auto-syncs) the database and the server daemonizes past its own parent's death — a manual test spawned a stray daemon that collided with an in-flight bulk `sync`, crashing it with "database is locked" (~85 minutes of progress lost); recovered via a targeted `REINDEX` (3 rows, confirmed non-corrupting) + a bulk `sync` resume. Durable fix: the wrapper now ALWAYS passes `--no-watch`, proven by a real init'd scratch-project DB-mtime check (unchanged after a tracked-file edit with the server running). Six new regression tests landed (`tests/test_codegraph_mcp_serve.sh`), including the incident itself replayed as a repeatable test.
- **Honest boundary** (carried from the anchor text, §11.4.6): `.mcp.json` registration takes effect on a fresh session — the session that landed it could not self-restart to verify the MCP tools are end-to-end callable from inside it; that check remains a tracked §11.4.197 follow-up, not claimed complete here. Gate-code for §11.4.78/§11.4.275's recommended `CM-*` mechanism gates remains owed (§11.4.227(A); see `docs/owed_gate_implementations.md` OWED-GATE-096 through OWED-GATE-105).
