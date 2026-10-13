# disk_tripwire.sh — Companion Guide

**Revision:** 1
**Last modified:** 2026-09-24T11:59:07Z

Source: `constitution/scripts/codegraph/disk_tripwire.sh` (105 lines). Every
statement below cites `disk_tripwire.sh:<line>`.

## Overview

A bulk CodeGraph index grows its SQLite database without bound. On a nearly
full volume that exhausts the disk (header, lines 5-9). `disk_tripwire.sh` is a
watcher that samples the free space of the volume holding the database and,
the moment free space drops below `--min-gib`, sends **SIGSTOP** to the
indexer process — a reversible pause (resume with `kill -CONT <pid>`), never
SIGKILL (lines 7-9, 97-98).

It is started by `codegraph_safe.sh` (header cross-refs, line 30); it can also
be run by hand against an indexer that was started some other way.

## Prerequisites

- `bash`, `df`, `python3` (line 29).
- `codegraph_safe_helper.py` in the same directory — used for the process
  identity check (`HELPER="$HERE/codegraph_safe_helper.py"`, line 35;
  `identity()`, line 67).
- A live indexer PID whose real `/proc` argv is a
  `node … /lib/dist/bin/codegraph.js` process (lines 12-14). A shell whose
  command line merely mentions `codegraph.js` is refused (line 14).

## Usage examples

```sh
# Pause indexer PID 12345 if the DB volume drops below 20 GiB free,
# sampling every 30 s (default).
disk_tripwire.sh --pid 12345 --dir <project_root>/.codegraph \
                 --min-gib 20 --log /path/to/tripwire.log

# Faster sampling
disk_tripwire.sh --pid 12345 --dir <project_root>/.codegraph \
                 --min-gib 50 --interval 5 --log /path/to/tripwire.log

# After a trip: free space, then resume the paused indexer
kill -CONT 12345
```

### Arguments (lines 38-46)

| Flag | Required | Meaning |
|---|---|---|
| `--pid <n>` | yes | Indexer PID. Must be an integer > 1 (lines 51-52) and pass the identity check (lines 69-74). |
| `--dir <path>` | yes | Any path on the DB volume; used as the `df` target. Must exist as a directory (line 59). |
| `--min-gib <n>` | yes | Threshold in GiB, integer, bounded to `[5,500]` (lines 53-57). |
| `--interval <s>` | no | Seconds between samples, positive integer, default `30` (lines 36, 58). |
| `--log <file>` | yes | Append-only log (line 48). On trip, a marker file `<log>.TRIPPED` is created (line 99). |

Any other argument: `disk_tripwire: unknown argument` and exit 2 (line 44).

### Test-only environment variable

`CG_SAFE_TEST_FREE_BYTES` — can only **lower** the measured free bytes:
`avail = min(measured, override)` (lines 19-20, 85-86). It cannot fake extra
space. A non-numeric value is ignored (line 86).

## Exit codes (header lines 22-27, verified against code)

| Code | Meaning | Source |
|---|---|---|
| 0 | Indexer ended (PID gone, zombie `Z`, or dead `X`) with no trip | lines 79-82 |
| 2 | Usage error or refused to arm: missing `--log`, bad/≤1 PID, non-integer or out-of-range threshold, bad interval, missing dir, unknown argument, target is not a codegraph indexer | lines 44, 47, 51-59, 70-73 |
| 3 | PID changed identity while watched (PID reuse) — no signal sent; **also** returned when `kill -STOP` itself fails | lines 90-94, 102-103 |
| 10 | TRIPPED: free < threshold, indexer SIGSTOPped, marker written | lines 96-100 |

Note: the header documents exit 3 only as "pid changed identity"; the code
also uses 3 when the STOP signal fails (line 103).

## Edge cases

- **Missing `--log`** is checked first and writes to stderr only (line 47);
  every later refusal is also appended to the log via `say` (lines 48-59).
- **`--interval 0`** is refused (line 58).
- **`df` output unreadable** (empty or non-numeric): logs
  `WARN df unreadable`, sleeps, retries — does not trip and does not exit
  (line 84).
- **PID reuse:** the identity string captured at arm time (`ID0`, line 69) is
  re-read immediately before signalling; if it differs the script refuses to
  signal and exits 3 (lines 88-93). Identity is only re-checked on the trip
  path, not on every sample (lines 87-89).
- **Process state** is read from field 3 of `/proc/<pid>/stat` after the
  last `) ` so command names with spaces or parentheses do not break parsing
  (lines 61-66).
- A stopped (`T`) indexer is not treated as gone; only `-`, `Z`, `X` end the
  watch (line 79).

## Internal behaviour

1. Parse flags (lines 38-46); validate `--log`, PID, threshold, interval,
   dir (lines 47-59).
2. Capture identity via `python3 codegraph_safe_helper.py identity <pid>`;
   the output must begin with `OK ` (lines 69-74). Log `ARMED …` (line 75).
3. Loop (lines 78-105): read process state; exit 0 if gone. Read
   `df -B1 --output=avail <dir>` (line 83); apply the test override; log
   `avail_bytes=… min_bytes=…` every sample (line 87).
4. If `avail < min_gib × 1073741824` (lines 77, 88): re-check identity, send
   `kill -STOP`, log `TRIPPED …`, touch `<log>.TRIPPED`, exit 10.
5. Otherwise `sleep <interval>` and repeat.

Log line format: `HH:MM:SS <message>` (`date +%T`, line 48).

## Related scripts

| Guide | Relation |
|---|---|
| [codegraph_safe](codegraph_safe.md) | Starts this watcher for index/sync runs |
| [codegraph_safe_helper](codegraph_safe_helper.md) | Provides the `identity` subcommand used here |
| [codegraph_guard](codegraph_guard.md) | Refuses a second writer against a live lock holder |
| [index_watch](index_watch.md) | Progress-proven watchdog for long runs |
| [codegraph_runner_patches](codegraph_runner_patches.md) | Patched runner used for bulk runs |
| [fk_index_patch](fk_index_patch.md) | Runner patcher |
| [fk_cascade_probe](fk_cascade_probe.md) | Bulk-window hazard probe |
| [codegraph_scope_guard](codegraph_scope_guard.md) | Scope proof before "ready" |
| [scope_render](scope_render.md) | Generates the effective scope |
| [codegraph_mcp_probe](codegraph_mcp_probe.md) | MCP reachability probe |
| [lumen_verify](lumen_verify.md) | Semantic-index health check |
| [gen_lumenignore](gen_lumenignore.md) | Semantic-index scope generator |
| [codegraph_lumen_overview](codegraph_lumen_overview.md) | Overview of the indexing tooling |

Tests: the header cites `tests/test_tripwire.sh` (line 30); the file exists
in `scripts/codegraph/tests/`. UNCONFIRMED: its content and coverage were not
read for this guide.

## Last verified

2026-09-24 — read `disk_tripwire.sh` lines 1-105 in full; `bash -n
disk_tripwire.sh` passed. The script was NOT executed (a live indexer holds
the project DB).
