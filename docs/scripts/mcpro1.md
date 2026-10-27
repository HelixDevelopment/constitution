# mcpro1 (runner patch) — guide

**Revision:** 2
**Last modified:** 2026-10-26T20:57:00Z

Source: `constitution/scripts/codegraph/runner_patches/mcpro1.py` (233 lines). A **module driven by
`fk_index_patch.py`**, not a command. Citations are `mcpro1.py:<line>` unless another file is named (Revision 2 added shape B, see below; the shape-A line citations in the
anchor table are unchanged because shape B was appended after them). Machinery guide:
[fk_index_patch](fk_index_patch.md).

## Overview

`mcpro1` builds a **READ-ONLY CodeGraph runner for MCP serving**. It is never used for `init`, `index` or `sync`. It exists
because stock 1.6.0 `codegraph serve --mcp` is not read-only (docstring lines 3-14):

1. `mcp/engine.js` runs `catchUpSync()` (`cg.sync()`, a write path) at startup and starts a file watcher; only the watcher
   has an env kill switch.
2. Every `DatabaseConnection.open()` runs migrations, `healBulkNodeLoad`, `healBulkSecondaryIndexes` (DDL: recreates
   deliberately dropped bulk indexes) and `healOversizedWal`.
3. `FileLock.acquire()` treats a lock older than 2 minutes as stale whatever the holder PID, so an MCP server started next to
   a live bulk indexer can steal its lock and sync concurrently.
4. The default mode spawns a detached daemon per project (pid/log/socket files plus up to 16 workers that each run the heal-
   writing open).

The patch makes the runner **incapable** of mutating a project, unconditionally (no environment gate, so a missing or typoed
variable cannot re-enable a writer; lines 16-17). Eight anchors, five files (lines 59-123, 144-161):

| Anchor | File | Effect |
|---|---|---|
| `DatabaseConnection.open(dbPath)` | `lib/dist/db/index.js` | Opens with `createDatabase(dbPath, {readOnly: true})`, `PRAGMA query_only=ON`, no migration, no heal; throws if the database is missing or its schema version is older than this build's (never migrates); the stock body is kept, unreachable, as `helixLegacyOpen` (lines 60-83) |
| `DatabaseConnection.initialize(dbPath)` | same | Throws: a read-only runner never creates a database (lines 84-89) |
| `FileLock.acquire()` | `lib/dist/utils.js` | Prints a notice and throws; no lock is ever taken and no lock file is unlinked (lines 91-99) |
| `FileLock.release()` | same | No-op, never unlinks (lines 100-105) |
| `MCPEngine.startWatching()` | `lib/dist/mcp/engine.js` | No-op plus one stderr notice containing `read-only` (lines 106-113) |
| `MCPEngine.catchUpSync()` | same | No-op (lines 114-119) |
| `daemonOptOutSet()` | `lib/dist/mcp/index.js` | Always returns true: direct mode, no daemon, no daemon files (lines 120, 138-142) |
| CLI allowlist before `new commander_1.Command()` | `lib/dist/bin/codegraph.js` | Only no-args, `--version`/`-V`/`-v`, `--help`/`-h`/`help`, `status`, and `serve` with `--mcp` run; anything else prints a refusal and exits **78** before it can open, lock or delete anything (lines 121-136) |

The source records a measured hazard behind the allowlist (lines 27-30): without it the CLI `index` subcommand on this runner
deleted the database, because `removeDatabaseFiles` runs before `initialize()` throws. Layering (lines 32-35): the CLI
allowlist is the first line, the read-only open / no-op sync / no-daemon are the operational lines for the MCP server, and the
`initialize`/`FileLock` throws are second-line guards for paths that bypass the CLI.

## Two code shapes: A (CodeGraph 1.6.0) and B (CodeGraph >= 1.6.2) — added in Revision 2

Why this exists (incident 2026-10-27, `/mcp` showed `Failed to reconnect to codegraph: MCP error -32000: Connection closed`).
The eight anchors above were written against 1.6.0. The npm package was upgraded to 1.6.2 and nothing re-proved the patch, so
the builder refused (`mcpro1: anchor 'DatabaseConnection.open -> read-only, no migrate/heal' occurs 0x`), the sanctioned
wrapper [codegraph_mcp](codegraph_mcp.md) exited 5 in 0.11 s with an EMPTY stdout, and the MCP client reported a closed
connection. Fail-closed worked as designed; what was missing was a gate that notices the refusal before an operator does (see
[codegraph_mcp_health](codegraph_mcp_health.md)).

`plan()` recognises the shape from `lib/dist/db/index.js`: exactly one `static open(dbPath, options = {}) {` means shape B
(`mcpro1.py:209`), anything else is planned as shape A and refused by the exactly-once anchors if it matches neither
(fail-closed). Shape B keeps every shape-A guarantee and swaps/adds anchors (eleven anchors, five files; the recorded plan for the
installed 1.6.2 is in the reference consumer's evidence pack, `79_mcpro1_plan_current_shapeB.json`):

| Shape-B anchor | File | Effect |
|---|---|---|
| `static open(dbPath, options = {})` (`:163`) | `lib/dist/db/index.js` | 1.6.2 has a native `readOnly` option; the wrapper forces `readOnly: true` for every caller, then still refuses a schema older than this build (never migrates) |
| `catchUpSync(afterReopen = false)` (`:181`) | `lib/dist/mcp/engine.js` | No-op (the signature changed in 1.6.2) |
| `function makeFallbackEngine(root)` (`:187`) | `lib/dist/mcp/index.js` | Returns the read-only fallback engine only; never a writable one |
| `const writerRoot = resolveDaemonRoot(this.projectPath);` (`:193`) | `lib/dist/mcp/index.js` | `writerRoot = null`: 1.6.2 `startDirect()` otherwise claims the project's writer slot (`.codegraph/writer.pid`) |
| `new engine_1.MCPEngine({ queryPool: true, ... })` (`:197`) | `lib/dist/mcp/index.js` | Builds only `MCPEngine({ readOnly: true })`: no watcher, no catch-up sync, no query pool |

The other six anchors (`initialize`, `FileLock.acquire/release`, `startWatching`, `daemonOptOutSet`, the CLI allowlist) are shared
with shape A.

How the watcher is armed on shape B (read from the 1.6.2 source, then proven by mutant M5): `MCPEngine.startWatching()`
(`mcp/engine.js`) only creates the project lease through `acquireProject`. The lease's `activate()`
(`mcp/project-lifecycle.js`) is the code that calls `cg.watch()`, prints `File watcher active` and then `cg.sync()`; it runs
lazily from `lease.ready()`, and the only caller of `ready()` is `catchUpSync()`. The engine's own `readOnly` option
short-circuits both methods natively. The hole is therefore closed by three independent layers (patched `startWatching`, patched
`catchUpSync`, the read-only engine), and the M5 mutant reverts all three before the watcher log reappears. A first attempt that
reverted only the watcher method, then the watcher plus the engine option and the write-lock throw, left the mutant alive for
the right reason: each of those leaves a layer in place, which is why a single-layer mutant on this shape is an equivalent
mutant and must not be accepted as a "killed" proof. Evidence: `75_`/`76_mcpro1_M5_probe*.txt` (survivors),
`77_mcpro1_M5_shapeB_fixed.txt` (killed).

## Prerequisites

Reads `db/index.js`, `utils.js`, `mcp/engine.js`, `mcp/index.js` and `bin/codegraph.js` from the package. Python stdlib plus
`runner_patches/common.py`. The package must be pristine.

Registry properties (`runner_patches/__init__.py:17-19,24-25,31-34`): mcpro1 is **OPT_IN** (never in the default set) and
**EXCLUSIVE** (refused if combined with any other patch). Its runner key is therefore `<version>-mcpro1`, which identifies the
read-only runner exactly. The runner cache already holds one, `~/.cache/helix/codegraph_runner/1.6.0-mcpro1` (directory
listing seen 2026-09-26; contents not opened).

## Usage

Only through `fk_index_patch.py`; in practice through `codegraph_mcp.sh`, which builds and verifies it with
`--patches mcpro1 --print-bin` (`codegraph_mcp.sh:58`, see [codegraph_mcp](codegraph_mcp.md)):

```sh
python3 scripts/codegraph/fk_index_patch.py --patches mcpro1 --dst <scratch dir>
```

- `NOT RUN` in that form (copies the 282 MB package). Read-only planning was run:
  `VERIFIED (ran: fk_index_patch.plan_all(<stock 1.6.0>, ["mcpro1"]); saw: APPLIED, 8 anchors, 5 files, detail mode
  "unconditional read-only (no env gate)", exclusive true, opt_in true, daemon "never", watcher "never", catch_up_sync
  "never")`.
- `VERIFIED (ran: fk_index_patch.py --patches mcpro1,fkidx1 machinery via runner_patches.load; saw: Refuse "patch 'mcpro1' is
  exclusive ... cannot be combined with: fkidx1", exit 2)` (parent guide, Example 6).
- `VERIFIED (ran: tests/test_mcp_readonly.sh with TMPDIR set to a scratch directory; saw: SUMMARY cases=13 failed=0, exit
  0)`. This builds the `--patches mcpro1` runner in its own workdir and exercises it on fixture projects only.

## What the test proves (`tests/test_mcp_readonly.sh`, header lines 3-25)

Each check that claims "nothing changed" also runs the same instrument against the **stock** runner as a control, so a green
result is shown able to see a change:

R1 builder exit 0, runner present, receipt lists the anchors; R2 the RO runner answers `tools/call` on a drifted fixture; R3
every descriptor on `codegraph.db` is `O_RDONLY` (stock: read-write); R4 logical DB hash and main file unchanged after a
session on a drifted tree (stock changes); R5 a dropped bulk index stays dropped (stock recreates it); R6 no watcher/auto-sync
even without `CODEGRAPH_NO_WATCH` (stock reports active); R7 a planted stale lock file is untouched (stock removes it); R8
builder fail-closed on shape mismatch: exit 2 and no runner directory; R9 the RO runner refuses `codegraph sync` (exit 78;
database and planted lock untouched); R10 it refuses `codegraph index`; R11 no detached daemon even with
`CODEGRAPH_NO_DAEMON=0` (stock leaves `daemon.log`); R12 node-level: `FileLock.acquire` throws and never unlinks a stale lock;
R13 registry: registered, selectable, not in the default set, exclusive with writer patches; R14 (Revision 2) a live RO MCP
session never creates `.codegraph/writer.pid`, `daemon.pid` or `daemon.sock` (control: the stock runner does create `writer.pid`, so
the instrument is shown able to see a slot). R8 uses a version-aware regex for the `catchUpSync` definition line so its
shape-mismatch mutation is not vacuous on shape B. The test unsets ambient
`CODEGRAPH_*` env so the instrument cannot be steered from outside (`test_mcp_readonly.sh:21`).
`tests/test_mcp_readonly_mutations.sh` applies the mutants of `test_mcp_readonly_mutate.py` to a scratch COPY and requires the named
R-cases to turn FAIL. Since Revision 2 each mutant carries per-shape edits (`{shape: (edits, expected-FAIL list)}`; `*` = shape
independent) and the harness reads the installed package's shape itself; a mutant with no variant for the shape under test exits 3 and is
reported `N/A`, never counted as killed. M11 is shape-B only (the writer slot, expected R14). On shape B, M8 expects only R10 because
`codegraph sync` is still refused by the second-line `FileLock.acquire` throw even with the allowlist off.

## Behaviour (source-traced)

`plan(view)` (`mcpro1.py:202-233`; the shape-A path is unchanged in behaviour): Refuse `mcpro1: <file> is ALREADY patched` if the marker `helix-mcpro1` occurs in any of the five
files (lines 145-147); then eight `replace_once` edits, each failing closed (exit 2, no runner) if its anchor is not found
exactly once. There is no NOT_NEEDED path. Because it edits `db/index.js` and `utils.js`, the same files touched by `fkidx1`
and `lockfix1`, it must never be combined with them (enforced by EXCLUSIVE).

## Edge cases

- Read-only runner asked to `init`/`index`/`sync`/`uninit`/`unlock`/`upgrade`: refuses with exit 78 (R9, R10 VERIFIED above for
  `sync` and `index`; other subcommands are refused by the same allowlist logic, lines 125-135, not individually run).
- Database with an older schema than the runner's build: throws `helix-mcpro1: schema vN is older than vM; a read-only runner
  cannot migrate` (lines 60-83; source-traced, not run).
- A project whose index is out of date: the read-only server answers from what is on disk and never catches up (R4/R6).
- Anything other than `serve --mcp`, `status`, `--version`, `--help` fails by design; for indexing use the writer runner
  through [codegraph_safe](codegraph_safe.md).

## Related scripts

[fk_index_patch](fk_index_patch.md), [codegraph_mcp](codegraph_mcp.md) (builds/verifies this runner and serves MCP),
[codegraph_mcp_preflight](codegraph_mcp_preflight.md), [codegraph_mcp_probe](codegraph_mcp_probe.md), siblings
[fkidx1](fkidx1.md), [lockfix1](lockfix1.md), [datafrag1](datafrag1.md), [resolve1](resolve1.md), [resolve2](resolve2.md).

## Last verified

2026-09-26: `tests/test_mcp_readonly.sh` 13/13 PASS with a scratch `TMPDIR`; real runner cache listing unchanged. `tests/test_mcp_readonly_mutations.sh`:
mutants=10 killed=10 survivors=0.

2026-10-26 (Revision 2, CodeGraph 1.6.2 installed and the npm `latest`):
- `VERIFIED (ran: fk_index_patch.plan_all(<installed 1.6.2>, ["mcpro1"]); saw: status APPLIED, anchors 11, files 5, detail shape "B (>=1.6.2: native readOnly open, writer-slot + writable-engine paths closed)")`.
- `VERIFIED (ran: tests/test_mcp_readonly.sh, R1,R3,R5,R6,R7,R9..R14 via the mutation harness baseline; saw: every RESULT line PASS, including R14 with its stock control)`.
- `VERIFIED (ran: tests/test_mcp_readonly_mutations.sh, all mutants; saw: SUMMARY mutants=11 killed=11 survivors=0 not_applicable=0, EXIT=0)`; the previous run of the same harness (single-layer M5) had mutants=11 killed=10 survivors=1, recorded as the equivalent-mutant defect fixed above.
- `VERIFIED (ran: the exact .mcp.json command, bash constitution/scripts/codegraph/codegraph_mcp.sh with cwd = the project, driven by a scripted MCP client; saw: initialize in 0.57 s, 8 tools in tools/list, a real query for a known symbol returning "Search Results (5 found)", exit 0, peak RSS 2.59 GB)`.
- Not covered: shapes other than A and B (refused by design); a future 1.6.x that keeps the shape-B signatures but moves the watcher arming (the M5 mutant would then need re-deriving); behaviour on non-Linux hosts.

