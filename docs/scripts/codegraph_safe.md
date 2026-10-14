# codegraph_safe.sh — Companion Guide

**Revision:** 4
**Last modified:** 2026-10-12T14:17:01Z

Source: `constitution/scripts/codegraph/codegraph_safe.sh` (700 lines at the time of this revision, 2026-10-12; it was 567 lines when this guide was first committed (b3a73cf) and 607 at 1c89813).
Every statement below cites `codegraph_safe.sh:<line>`.

NOTE (2026-10-12): every line citation in this guide was RE-DERIVED against the 700-line file by locating the cited statement itself, not by applying a uniform offset. Measured shifts versus the numbers this guide carried before: 0 for the first 100 header lines (the Exit codes header +11), +12 to +13 for lines 100-300, +83 to +98 across `preflight`, +131 to +139 for the runner, ops and bulk path. The citations are valid for this revision only: any later edit of the script shifts them again, so re-derive before relying on one. The `.html`/`.pdf`/`.docx` twins of this guide are NOT regenerated (stale, §11.4.106(E)).

## Known limitation: strict limits-file grammar (2026-10-12)

The limits file is read with a strict line-based grammar, not a YAML parser. Valid-YAML spellings that are NOT recognised and
therefore leave the safe 32 GiB default in force: a space before the colon (`min_mem_avail_gib : 20`), a quoted key
(`"min_mem_avail_gib": 20`), a flow mapping (`{min_mem_avail_gib: 20}`) and a UTF-8 BOM before the key. This fails in the safe
direction (a higher floor, never a lower one); write the key as `min_mem_avail_gib: <integer>` at the start of a line.

Two nearby spellings are REFUSED rather than ignored (exit 6, `PREFLIGHT FAIL memory-floor`), measured 2026-10-12 (review WF31, probe
C1): a value on a continuation line (`min_mem_avail_gib:` followed by a line holding only `20`) is an empty value, and an indented
or TAB-indented key (also a key nested under another key) is a non-top-level key.

Size limits (empty file, more than 64 KiB; exactly 65536 bytes is accepted, 65537 refused) are measured on the file the path
RESOLVES to: a symlink to a regular file is an accepted form, so the size gates follow it (`stat -L`). Before the 2026-10-12 fix
(review WF31 finding S-1) the link itself was measured, so a symlink to an empty or oversize file bypassed both refusals
(a symlink to a multi-gigabyte file would have been read into a shell variable during the memory-safety preflight). The same fix
applies to the `codegraph.db` / `codegraph.db-wal` size used for the free-disk requirement (`db_bytes=`).

## Overview

`codegraph_safe.sh` is the ONLY sanctioned entry point for CodeGraph `init`,
`index` and `sync` (line 3). It exists to make the failure modes of the
2026-09-23 bulk-window incident impossible by construction (lines 5-32):

1. Stock `init`/`index` on a fresh DB drops the FK child-key indexes during
   the bulk window, so `INSERT OR REPLACE` cascades full-scan very large
   tables. Bulk ops run ONLY through the patched runner derived by
   `fk_index_patch.py`, or through stock AFTER `fk_cascade_probe.py` proves
   stock safe. A refused runner is NEVER silently replaced by stock
   (lines 7-11, 542-568).
2. `codegraph … || true` masking — every failure is a non-zero exit (line 12).
3. A stall that looks alive — `index_watch.py` proves progress; a STALL is
   exit 7 (lines 13-14, 186-189).
4. Unbounded DB growth — `disk_tripwire.sh` SIGSTOPs the indexer below
   `--tripwire-min-gib` (exit 8), plus a host preflight (lines 15-16, 182-185,
   297-329).
5. The fix vanishing after an upgrade — the runner is re-derived per stock
   version and its receipt/version checked on every bulk run (lines 17-18,
   424-428).
6. The v1.6.0 stale-lock behaviour (a lock older than 2 minutes deleted
   regardless of holder liveness) — this wrapper checks the lock holder's
   real `/proc` argv and refuses while it lives, whatever the lock's age
   (lines 19-22, 462-509).
7. `sync` on any populated DB used to run stock + foreground with no patches,
   watcher or tripwire. `sync` is now classified BULK vs INCREMENTAL by the
   pending-refs backlog (lines 23-32, 598-618).

**Hard rule:** never run a writer against a project root whose lock holder
is alive. The script enforces this itself (exit 3), but equally never run
stock `codegraph init|index|sync|serve|unlock` by hand on such a root —
that bypasses every check below. `codegraph_guard.sh` refuses tracked
scripts that do so.

## Prerequisites

- `bash`, `flock`, `setsid`, `nohup`, `df`, `python3` (line 114).
- Siblings in the same directory: `codegraph_safe_helper.py`,
  `index_watch.py`, `disk_tripwire.sh`, `fk_index_patch.py`,
  `fk_cascade_probe.py` (lines 114-115, 124-128).
- A stock CodeGraph CLI on `PATH` or in `CODEGRAPH_BIN` (line 129).
- For bulk ops: host headroom as measured by `preflight` (see below).

### Host-adaptive V8 heap budget (added 2026-09-25, BOB-XXX)

`preflight` now also reports a `heap_mb=` line: half of currently-measured
`MemAvailable` (kB, from `/proc/meminfo`), floored at 8192 MiB and capped at
60% of `MemTotal` (the §12.6 ceiling, printed as `heap_cap_mb=`; computed fresh on every run, never a fixed number). The caller (`init`/`index`/`sync`) extracts it and exports
`NODE_OPTIONS=--max-old-space-size=$heap_mb` (additive to any pre-existing
`NODE_OPTIONS`) before launching the detached supervisor, so the indexer
child inherits it. Without this, a stock launch runs on Node's *default*
old-space limit (~4 GiB) regardless of host RAM — on a large repo (584K
files / 49M edges observed) the resolve phase legitimately needs far more
than that and the indexer OOM-aborts (`rc=134`, `FATAL ERROR: Reached heap
limit`) *after* finishing file parsing, discarding the whole bulk run
(reproduced live 2026-09-25; see `docs/codegraph/Status.md`). Never
hardcoded (§12.11) — always derived from the live measurement each run.
Extraction failure (an unreadable/missing `heap_mb=` line) refuses the run
(`die 6`) rather than silently falling back to the stock/unmeasured limit.
Regression-tested: `tests/test_unit_safe.sh` U44 (proportional formula) /
U45 (floor). **Known gap, not fixed in this pass:** the line-number
citations elsewhere in this document (§ headers above referencing specific
`codegraph_safe.sh` line numbers) were NOT re-walked after this ~20-line
insertion and are now stale by that offset for any code below the
insertion point — a pre-existing pattern in this doc (see the sibling
`codegraph_safe_helper.md`'s own disclosed staleness), tracked as owed
follow-up, not silently left unmentioned.

## Usage examples

```sh
# Host check only (no DB touched)
codegraph_safe.sh --project <project_root> preflight

# First full index, detached, return immediately
codegraph_safe.sh --project <project_root> index

# Same, block until the detached run finishes; exit = run result
codegraph_safe.sh --project <project_root> --wait --poll-s 30 index

# Sync; classification decided by the pending-refs backlog
codegraph_safe.sh --project <project_root> sync

# Force the supervised bulk path for sync
codegraph_safe.sh --project <project_root> --bulk sync

# Read-only checks
codegraph_safe.sh --project <project_root> status
codegraph_safe.sh --project <project_root> --expected-count 580000 --tolerance-pct 2 verify

# Remove a lock whose holder is provably dead (decision logged)
codegraph_safe.sh --project <project_root> --reap-dead-lock unlock
```

## Operations (lines 34-36, 571-700)

Exactly one op is allowed (line 275); missing or unknown op → exit 2
(lines 278-279).

| Op | Kind | Behaviour |
|---|---|---|
| `init` | writer | Always bulk. Runner args `init -y -v <P>` (line 649). |
| `index` | writer | Always bulk. Runner args `index -v <P>` (line 650). |
| `sync` | writer | BULK or INCREMENTAL, see classification. Bulk runner args `sync <P>` (line 651). |
| `status` | reader | `lock_check reader`, `/proc` scan (3 tries), then stock `status <P>`; non-zero stock exit → 1 (lines 580-585). |
| `verify` | reader | `lock_check reader`, scan, then `verify_now` (helper `verify` + `scope`) → `VERDICT PASS` 0 / `VERDICT FAIL` 1 (lines 586-590, 529-538). |
| `preflight` | other | Prints measurements; `PREFLIGHT PASS` 0 or exit 6 (lines 573-575). |
| `unlock` | other | Takes the wrapper flock, runs `lock_check unlock` (writer rules); exit 0 when no stale lock remains (lines 576-579). |

Writers first take the wrapper flock, then `lock_check writer`, then the
`/proc` scan (lines 593-595).

## Options (lines 37-62, 250-295)

| Option | Default | Validation / notes |
|---|---|---|
| `--project DIR` | git toplevel of `$PWD`, else `$PWD` (lines 297-299) | must exist (line 300); path containing whitespace → exit 2 for bulk ops (line 653) |
| `--bulk` | off | writer ops only, else exit 2 (lines 290-292); only changes behaviour for `sync` |
| `--pending-threshold N` | `$CG_SAFE_PENDING_BULK_MIN`, else `150000` (line 252) | integer ≥ 1 (lines 284-285) |
| `--patches IDS` | `$CG_SAFE_PATCHES`, else `fkidx1,resolve1` (line 252) | `all` or comma list `[a-z0-9]`, no leading/trailing/double commas (lines 286-289) |
| `--wait` | off | block until the detached bulk run writes its result (lines 681-700) |
| `--poll-s N` | 10 | integer (lines 280-282) |
| `--watch-interval N` | 60 | integer; passed to `index_watch.py` |
| `--stall-min M` | 10 | number, decimals allowed (line 283) |
| `--tripwire-min-gib N` | 20 | integer in `[5,500]` (line 293) |
| `--tripwire-interval N` | 30 | integer |
| `--reap-dead-lock` | off | allow removal of a provably dead lock |
| `--expected-count N` | — | integer (line 294); with `--tolerance-pct P` (number, line 295; default 0 when only N given, line 307) |
| `--status-doc FILE` | `<P>/docs/codegraph/Status.md` (line 305) | absent file → ledger SKIP, run not failed (lines 233-236) |
| `--scope-baseline FILE` | `scope_baseline.txt` beside the script (line 253) | passed to helper `scope` |
| `--scope-exceptions FILE` | `scope_exceptions.txt` beside the script | narrow per-exact-path exceptions for the `secret_named`/`secrets_dir` heuristic classes ONLY (never the credential-CONTENT classes); passed as helper `scope`'s optional 3rd argument at every call-site, including inside `supervise()` via env `CG_SV_SCOPE_EXCEPTIONS`; absent file ⇒ no exceptions (unchanged, strictest posture). See `docs/scripts/codegraph_safe_helper.md`'s `### scope` section for the full mechanism. |
| `-h`, `--help` | — | prints the header, exit 0 (line 273) |

Any other `-…` option → exit 2 (line 274). An option missing its value →
exit 2 (`need`, line 254).

### Patch set (lines 63-68)

Only `fkidx1` and `resolve1` have tests; `lockfix1` and `datafrag1` have none
and are opt-in via `--patches` / `CG_SAFE_PATCHES`. `fkidx1` must be in the
set — the receipt gate requires it, else exit 5 (lines 45-46). The default
runner key is `<version>-fkidx1-resolve1`.

UNCONFIRMED: the receipt check itself (`python3 codegraph_safe_helper.py
receipt`, line 556) was not read; the fkidx1 requirement is stated in the
header only.

### Environment (lines 69-88)

| Variable | Default | Effect |
|---|---|---|
| `CODEGRAPH_BIN` | `codegraph` | stock CLI (line 129) |
| `CG_SAFE_PENDING_BULK_MIN` | 150000 | default sync BULK threshold |
| `CG_SAFE_PATCHES` | `fkidx1,resolve1` | default `--patches` |
| `CG_SAFE_PENDING_PROBE_BUDGET_S` | 30 | wall-clock budget of the pending probe (UNCONFIRMED: consumed inside the helper; not referenced in this script's code) |
| `CG_SAFE_PATCH_TOOL` / `CG_SAFE_PROBE_TOOL` | sibling `fk_index_patch.py` / `fk_cascade_probe.py` | lines 127-128 |
| `CG_SAFE_MIN_THREAD_HEADROOM` | 1024 | preflight thread headroom (line 420) |
| `CG_SAFE_LIMITS_FILE` | `<project>/config/index/writer_limits.yaml` when present | consumer-data limits file; key `min_mem_avail_gib: N` (16 <= N <= 9999) is the ONLY mechanism that can LOWER the MemAvailable floor (the convention path is tracked, reviewable data; `CG_SAFE_LIMITS_FILE` may point at any regular file, including an untracked one outside the project, and lowers it too - loudly, because the resolved path is printed as `min_mem_avail_source=`). Set-but-empty, non-regular (directory, `/dev/null`, FIFO), empty, > 64 KiB, duplicate / indented / nested / empty-valued / non-numeric key => preflight REFUSED (exit 6). `resolve_mem_floor` |
| `CG_SAFE_MIN_MEM_AVAIL_KB` | — | MemAvailable floor in kB, plain decimal (<= 12 digits). May only RAISE the floor above the file / 32 GiB default; a lower value is REFUSED, never ignored (so this knob alone cannot weaken a bulk run). `resolve_mem_floor` |
| `CG_SAFE_TEST_FREE_BYTES` | — | TEST-ONLY, can only lower free bytes (line 386) |
| `CG_SAFE_TEST_MEMAVAIL_KB` | — | TEST-ONLY, can only lower MemAvailable (line 397) |
| `CG_SAFE_TEST_THREADS_USED` | — | TEST-ONLY, can only raise threads used (line 418) |

## Sync classification: BULK vs INCREMENTAL (lines 598-618)

`BULK=1` by default (line 602). For `sync`:

1. `--bulk` given → BULK (`reason=--bulk requested`, line 605).
2. Else helper `dbinfo` must report the DB exists, nodes present, no error
   (lines 607-608). If not → BULK (`reason=database missing, empty or
   unreadable`, line 616).
3. Else helper `pending <P> --threshold N` (line 609):
   - exit 0 → INCREMENTAL (`pending<threshold`, line 611);
   - exit 1 → BULK (`pending>=threshold`, line 612);
   - any other exit → BULK (`pending-probe UNKNOWN`, line 613). UNKNOWN is
     never read as "small".

Every sync prints `sync classification: BULK|INCREMENTAL (reason=…)`. The
header states the pending probe is bounded (an index range read of at most
threshold+1 entries, never `COUNT(*)`, lines 29-31); UNCONFIRMED from this
file — implemented in `codegraph_safe_helper.py`.

**INCREMENTAL path** (lines 620-634): stock `sync <P>` in the foreground
under the held flock, output to `index_runs/sync_<UTC>.log`, last 5 lines
echoed. Non-zero → exit 1. Then helper `verify` + `scope`; ledger entry;
`VERDICT PASS` 0 / `VERDICT FAIL` 1. No preflight, no watcher, no tripwire.

## Bulk path (lines 636-700)

1. `preflight` — FAIL → exit 6 (lines 636-638).
2. `resolve_runner` (lines 542-568): read stock `--version` (none → 5); run
   the patch tool with `--patches <IDS> --print-bin` (or `--print-bin` for
   `all`):
   - exit 0 → runner path must be executable, its parent dir must hold a valid
     `RUNNER_RECEIPT.json` for the stock version, and the runner's
     `--version` must equal stock's; any mismatch → 5;
   - exit 2 → 5 (stock is FORBIDDEN as fallback);
   - exit 3 (patch not needed) → `fk_cascade_probe.py --work-dir
     index_runs/probe --json-out index_runs/probe_verdict.json` must exit 0,
     then the runner is stock; otherwise 5;
   - any other exit → 5.
3. Launch detached: `setsid nohup bash <self> __supervise` with state in
   `CG_SV_*` environment variables (lines 663-667). The caller waits up to
   600 × 0.1 s for the indexer to be identified (lines 674-680).
4. Without `--wait`: exit 0 after launch (lines 681-684). With `--wait`: poll
   every `--poll-s` seconds until `run_<id>.result` exists; exit with the
   `EXIT=` code it records (lines 686-700).

### Supervisor (lines 146-211)

- Starts the runner with the op args, logs to `index_<UTC>.log`, records PIDs.
- Waits up to 300 × 0.1 s for `.codegraph/codegraph.lock` to name a PID whose
  identity check passes; that PID (else the launched PID) is the indexer
  (lines 157-169).
- Arms `index_watch.py` and `disk_tripwire.sh` on the identified indexer
  (lines 170-175); if none identified, logs a WARN and arms neither (line 177).
- While the indexer runs: a `tripwire_<id>.log.TRIPPED` marker → result 8;
  a last watcher line containing ` STALL_` → result 7, indexer left running
  for inspection (lines 179-191).
- On exit: helper `verify` (with the reported `Indexed N files` count and
  stock `status` Files count) + helper `scope`; any non-zero among indexer,
  verify, scope → result 1; ledger append; result written atomically via
  `.tmp` + `mv` (lines 192-216).

## Preflight thresholds (lines 380-460)

| Check | Pass condition |
|---|---|
| Disk | free on `.codegraph` (else project) ≥ max(60 GiB, 2 × (db + wal bytes)) |
| Memory | `MemAvailable` ≥ floor; floor = 32 GiB by default, lowered ONLY via `min_mem_avail_gib` in the limits file, raised via `CG_SAFE_MIN_MEM_AVAIL_KB`; lower bound of any floor 16 GiB (= 2 × the 8192 MiB heap floor, so `heap_mb` ≤ MemAvailable/2 always holds when the check passes). Values are plain decimal (leading zeros are decimal: `010` = 10); anything else is refused (`PREFLIGHT FAIL memory-floor`). With no knob the output is unchanged; with a knob an extra `min_mem_avail_source=` line and a `(floor: …)` suffix appear |
| Threads | `ulimit -u` − threads used by this uid ≥ 1024 (skipped when unlimited) |

Unreadable `df` or `MemAvailable` → FAIL (lines 384, 396).

## Lock handling (lines 462-527)

- No lock file → proceed (line 466).
- Numeric PID > 1 whose helper `identity` begins `OK`:
  - reader op → continue, unless the holder's op is `init|index|sync` → 3
    (lines 476-480);
  - writer / unlock → 3, "whatever the lock's age, it is NOT stale"
    (line 482).
- Holder dead, non-numeric content, PID ≤ 1, or alive-but-not-codegraph →
  stale. Reader: WARN and continue (lines 488-491). Writer without
  `--reap-dead-lock` → 4 (line 494). With it: re-check immediately before
  removal (live → 3), then remove and append a `REAPED` line to
  `index_runs/lock_reap.log` (lines 496-508).
- `/proc` scan via helper `scan` (writer 1 try, reader 3 tries 0.5 s apart)
  → 3 on a live writer (lines 511-521).
- Wrapper flock `.codegraph/.helix_index.flock` taken non-blocking; held by
  another launcher → 3; cannot open → 2 (lines 523-527).

## Exit codes (header lines 94-107)

| Code | Meaning | Source |
|---|---|---|
| 0 | Success / verified / detached launch without `--wait` / `--help` | 260, 443, 448, 454, 458, 499, 545 |
| 1 | Indexer failed, verification FAILED, stock status failed, supervisor ended without result, unreadable result | 453, 459, 496, 502, 554, 560; result 1 at 186-188 |
| 2 | Usage error / unknown op / bad option / flock file unopenable / whitespace path | 242-287, 394, 519 |
| 3 | Live writer (lock holder or `/proc` scan) or wrapper flock held | 348, 351, 369, 387, 395 |
| 4 | Stale lock present, not reaped | 363 |
| 5 | Safe runner unavailable — stock NEVER used as fallback | 415, 423, 426, 428, 430, 433, 436 |
| 6 | Host preflight failed | 444, 507 |
| 7 | STALL detected (via `--wait`) | result written at 175 |
| 8 | Disk tripwire tripped (via `--wait`) | result written at 171 |

Codes 7 and 8 (and a bulk-run 1) reach the caller only through `--wait`,
which exits with the recorded `EXIT=` value (line 700).

## Files written under `<P>/.codegraph/index_runs/`

| File | Written by |
|---|---|
| `index_<UTC>.log` | bulk runner output (line 656) |
| `sync_<UTC>.log` | incremental sync output (line 623) — not listed in the header |
| `run_<id>.pids` | `supervisor=`, `indexer_launch=`, `indexer=`, `watcher=`, `tripwire=` (lines 151-175, 658) |
| `run_<id>.result` | `EXIT=<n>` + summary, atomic (lines 213-216) |
| `watch_<id>.log` | `index_watch.py` output (line 171) |
| `tripwire_<id>.log` (+ `.TRIPPED`) | `disk_tripwire.sh` (line 173) |
| `supervisor_<id>.log` | detached supervisor stdout/stderr (line 668) |
| `lock_reap.log` | reaped-lock decisions (line 506) |
| `probe/`, `probe_verdict.json` | only when the patch tool says NOT_NEEDED (line 563) |

`<id>` is `<UTC>_<pid>` (line 655). `watch_state.json` is deleted before each
bulk launch (line 657). Also created: `<P>/.codegraph/.helix_index.flock`
(line 525).

## Edge cases

- `--bulk` with `init`/`index` is accepted and changes nothing (always bulk).
- `unlock` with a stale lock and no `--reap-dead-lock` → exit 4.
- A missing Status doc is not a failure: `LEDGER: SKIP` (line 234).
- If no indexer identity is observed within 30 s, the run continues with no
  watcher and no tripwire (line 177).

## Related scripts

| Guide | Relation |
|---|---|
| [codegraph_safe_helper](codegraph_safe_helper.md) | `identity`, `scan`, `dbinfo`, `pending`, `verify`, `scope`, `receipt` subcommands |
| [disk_tripwire](disk_tripwire.md) | Free-space watcher armed by the supervisor |
| [index_watch](index_watch.md) | Progress-proven stall detector |
| [fk_index_patch](fk_index_patch.md) | Derives the patched runner |
| [fk_cascade_probe](fk_cascade_probe.md) | Proves stock safe when no patch is needed |
| [codegraph_runner_patches](codegraph_runner_patches.md) | Registered runner patches |
| [codegraph_guard](codegraph_guard.md) | Gate that refuses bypasses of this script |
| [codegraph_scope_guard](codegraph_scope_guard.md) | Scope proof |
| [scope_render](scope_render.md) | Scope generator |
| [codegraph_mcp_probe](codegraph_mcp_probe.md) | MCP reachability probe |
| [lumen_verify](lumen_verify.md) | Semantic-index health check |
| [gen_lumenignore](gen_lumenignore.md) | Semantic-index scope generator |
| [codegraph_lumen_overview](codegraph_lumen_overview.md) | Overview |

## Tests

`tests/test_unit_safe.sh` cases U47-U63 cover the memory floor (limits file, convention path, env raise-only knob, lower bound,
strict grammar, symlinks, size boundary, sanitised echo, real live-writer refusal, symlinked database size). Paired mutations:
`tests/test_memfloor_mutations.sh` applies the single-edit mutants of `tests/test_memfloor_mutate.py` (MF1-MF8, R01-R35 and the
R25 negative control: 44 cases) to a copy of the tooling and requires the named case to turn RED. Run both in a rootless
container; the suite reads a redirected `meminfo` copy so the host's real memory does not matter.

## Last verified

2026-09-24 — read `codegraph_safe.sh` lines 1-561 in full (in slices);
`bash -n codegraph_safe.sh` passed. The script was NOT executed (a live
indexer holds the project DB). Helper subcommand internals were not read.

2026-10-12 — all `codegraph_safe.sh:<line>` citations re-derived against the 700-line file (each cited statement located and read);
the `resolve_mem_floor` section (lines 310-377) and its test cases U47-U63 were read in full. The script was NOT executed outside the
test containers.
