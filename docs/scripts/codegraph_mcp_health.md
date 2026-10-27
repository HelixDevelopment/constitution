# codegraph_mcp_health — guide

**Revision:** 3
**Last modified:** 2026-10-27T11:40:00Z

Source: `constitution/scripts/codegraph/codegraph_mcp_health.py` (696 lines), gate wrapper
`constitution/scripts/gates/cm_codegraph_mcp_health.sh` (65 lines), paired mutation test
`constitution/scripts/gates/cm_codegraph_mcp_health_mutation_test.sh`. Citations are by check id (`H1`..`H9`) and heal action
(`A1`..`A4`) because the tool prints them as stable `HEALTH <id>` / `HEAL <action>` lines.

Revision 3 (2026-10-27) adds, below, the measured behaviour of the stock daemon with and without `CODEGRAPH_NO_WATCH=1`, the
refined root cause (a quadratic ignore matcher fed by git-ignored seeds), the operator instructions for a user-scope stock entry
(documented, not applied), the registration patch set for the gate, the scope-data-file finding, and corrects the "Honest
boundaries" section (the preflight launch-target check now exists). Evidence for every figure added in Revision 3 is under
`qa-results/codegraph_followup_20261027/` and `qa-results/codegraph_register_20261027/` of the reference consumer; each section
names its files.

## Overview

A dependency-free (Python stdlib) probe that answers one question with captured evidence and never from configuration alone: will
an agent platform that spawns this project's declared `codegraph` MCP server get a working session right now? It performs the
real round trip (spawn the exact `.mcp.json` command with the project as cwd, `initialize`, `tools/list`, `codegraph_status`,
optionally a known-symbol search with a fabricated-symbol negative control), and around it checks the failure classes that
actually broke the server. With `--heal` it repairs only the classes that are provably safe to repair; everything else is
reported, never papered over.

### The incident that defines it (2026-10-27)

The agent platform reported `Failed to reconnect to codegraph: MCP error -32000: Connection closed`. Two independent causes were
measured, neither was noticed by any gate:

| Cause | Evidence (reference consumer's pack `qa-results/codegraph_fix_20261027/`) | Check that now sees it |
|---|---|---|
| **A. Upstream shape drift.** The npm package moved 1.6.0 to 1.6.2; the read-only runner patch ([mcpro1](mcpro1.md)) anchored on the 1.6.0 code and refused (`anchor ... occurs 0x`); the sanctioned wrapper exited 5 in 0.11 s with an empty stdout, so the client saw EOF. | `rc2_project_mcp_wrapper/`, `20_baseline_tests_RED_on_1.6.2.txt` | H3 (the refusal, named) and H8 (the client-visible EOF) |
| **B. A stock `serve --mcp` daemon blocked on a very large tree.** `codegraph_status` took 82-85 s, the daemon log held 615 `Main thread unresponsive ... killing the wedged process` watchdog kills before this investigation (about one restart per six minutes until 2026-10-19; four more were induced by the investigation's own reproductions), and every kill lands 60.08 s after the matching `Listening` line. | `rc1_stock_serve_mcp/`, `92_stock_cmd_after_reindex.txt`, `93_stock_daemon_startup_profile.txt`, `94_stock_daemon_main_thread_profile.txt` | H6 (evidence) and H7 (the stock entry in a user-scope config) |

**Cause B, root-caused 2026-10-26 with a captured CPU profile.** A stock daemon was started with the documented diagnostic switch
`CODEGRAPH_NO_WATCHDOG=1` so the 60 s liveness watchdog (#850) could not kill it, and the node inspector was attached to its live main
thread. A passive 12 s profile, taken 6.5 minutes after the start, put 95.5 % of the self time in the `ignore` package (gitignore
matching) and the call chain was `catchUpSync` > `lease.ready` > `activate` > `cg.watch()` > `FileWatcher.start` >
`refreshWatchTree` > `walk` (recursive, synchronous) > `shouldIgnoreDir` > `ignore`. The file watcher's initial directory walk runs
on the main thread, applies the project's include/exclude rules to every directory of a 586,673-file tree, and was
still running after 6.5 minutes with no event-loop turn observed (the main thread at 100 % CPU, `writer.pid` still `ready:false`, an
inspector `Runtime.evaluate` that timed out, the `codegraph_status` call never answered within 360 s). The watchdog fires at 60 s, so the daemon is killed before it ever serves a request, and the next client
spawns a new one: a crash loop. The read-only wrapper never reaches this code, because its patched `startWatching` and `catchUpSync`
are no-ops ([mcpro1](mcpro1.md)).

An earlier hypothesis, that the blocking work was the catch-up synthesis with `synthesis_pending=1`, was **refuted by the same
experiment**: after the reindex finished (`synthesis_pending=0`, index current) the stock command reproduced the identical
behaviour (kill at +60.08 s, status after 82 s, one tool listed instead of eight). The trigger is the tree size and the include/exclude
rule count, not the index state. The tool reports the watchdog evidence (H6) and the stock-entry exposure (H7); the fix for a project
is to declare the sanctioned wrapper at project scope, which takes precedence over a user-scope stock entry.

## The stock `serve --mcp` entry: measured mitigations, refined root cause, supported path (Revision 3)

Everything in this section was measured on 2026-10-27 on the reference consumer (CodeGraph 1.6.2, 1,032,717 tracked files, 205,986
tracked directories counting ancestors). Evidence directory: `qa-results/codegraph_followup_20261027/`. The stock daemon runs were
executed against a reflink copy of the live database (`CODEGRAPH_DIR` pointed at a scratch directory; the live index was
byte-unchanged afterwards) inside a transient cgroup (`MemoryMax=24G`, `MemorySwapMax=0`, `CPUQuota=400%`), never against the live
index.

### Experiment: does `CODEGRAPH_NO_WATCH=1` make the stock daemon usable?

Files: `30_stock_E0_control`, `31_stock_E1_nowatch`, `33_stock_experiments_summary.tsv`. Same driver, same index copy, only the
environment differs.

| Measure | E0 stock default | E1 stock + `CODEGRAPH_NO_WATCH=1` |
|---|---|---|
| Window observed | 207.3 s | 164.1 s |
| `initialize` answered | 0.16 s | 0.18 s |
| Tools listed | 1 (`codegraph_explore`) | 1 (`codegraph_explore`) |
| `codegraph_status` answered at | 90.3 s | 111.8 s |
| Status text | `Changes since index: unknown (measurement timed out)` | the same text |
| Known-symbol search | `7 found`, at 153.1 s | `7 found`, at 115.6 s |
| Fabricated-symbol search (negative control) | `No results found`, at 207.1 s | a queue-busy message after a 45 s wait, no answer |
| Watchdog-kill lines in `daemon.log` | 2 | 0 |
| `watcher disabled` log lines | 0 | 1 |
| Database descriptor modes seen | `r`, `rw` | `r`, `rw` |
| Files created in the index directory | `daemon.pid`, `writer.pid` | `codegraph.lock`, `daemon.pid`, `writer.pid` |
| WAL after the run | 0 bytes | 20,632 bytes |
| Peak RSS of one pid | 2,381 MB | 2,966 MB |

Readings, each tied to the table:

1. `CODEGRAPH_NO_WATCH=1` removes the watchdog kill loop in this window (2 kills to 0). The source agrees with the mechanism: the
   switch is honoured in `FileWatcher.start()` at `sync/watcher.js:354` (`watchDisabledReason`), which returns before
   `buildScopeIgnore` (line 360) and before `refreshWatchTree()` (line 370), so the blocking walk never runs.
2. It does NOT make the stock entry safe or fast. The daemon still opens the database read-write, still takes
   `codegraph.lock`, still grew the WAL, answered `codegraph_status` later (111.8 s) than the default run, left the negative
   control unanswered behind its write queue, and held about 3 GB of resident memory. A stock daemon is a writer by design; the
   read-only guarantee exists only in the sanctioned wrapper ([mcpro1](mcpro1.md)).
3. Therefore `CODEGRAPH_NO_WATCH=1` is a PARTIAL mitigation (it stops the kill loop and nothing else) and is documented as such.
   The only configuration that was measured working end to end for an agent is the sanctioned wrapper: H8 of the gate recorded
   `initialize` 0.3 s, `tools/list` 14.3 to 16.6 s with 8 tools, 26 to 29 s total over the runs of 2026-10-27
   (`qa-results/codegraph_register_20261027/11_live_health_gate.txt`, `qa-results/codegraph_followup_20261027/20_health_now.txt`).
   The stock default lists 1 tool where the wrapper lists 8.

### Refined root cause of cause B

Files: `14_walk_bench*.json`, `15_tracked_dir_count.txt`, `16_ignore_scaling_bench.tsv`, `17_scope_matcher_rule_counts.json`,
`18_git_ignored_untracked_dirs.txt`, `19_synth_*`, `35_walk_bench_summary.tsv`, plus the CPU profile
`qa-results/codegraph_fix_20261027/94_stock_daemon_main_thread_profile.txt` (12.06 s, 7,364 samples; 86.2 % at
`ignore/index.js:508`, 9.0 % at `_t:674`, 0.3 % at `_test:632`).

- `buildScopeIgnore` (`extraction/index.js:841-851`) builds one matcher from the 80 built-in patterns, the root `.gitignore` and
  `.git/info/exclude`, then calls `rootMatcher.add(...)` once for every entry of `git ls-files -z -o -i --exclude-standard
  --directory` (`listGitIgnoredDirectories`, line 367). On this tree that is 18,914 rules, of which 18,467 (97.6 %) are those seeds
  and 447 are the residual patterns. The count moves with the tree (18,922 in a later run of the same bench).
- The cost of one `ignores()` call grows with the rule count. Measured microseconds per call by rule count (`16_`): 0 rules 1.3,
  50 rules 6.0, 100 rules 11.3, 200 rules 21.6, 400 rules 65.3, 800 rules 256.7, 1600 rules 537.6.
- `FileWatcher.refreshWatchTree()` (`sync/watcher.js:428-472`) is a synchronous recursive walk that calls
  `shouldIgnoreDir` (line 725, `ignoreMatcher.ignores(rel + '/')`) for every directory, resolves symlinks and reads every
  directory on the main thread. Measured on the real tree: a 240 s capped run did not finish; it had visited 49,110 directories
  (7,754 pruned), made 56,894 `ignores()` calls at 4.13 ms per call, with 98.0 % of the time in `ignore` and 1.8 % in
  filesystem calls. A projection of the full walk time from that rate is 1,007 s, UNCONFIRMED because the run did not complete.
- The effect does not depend on this repository. A synthetic repository with N ignored-untracked directory entries (reproducer:
  the extract-and-run scripts embedded in the upstream bug report): N=6,000 gives 6,081 rules, 12,001 directories, 18,002 calls and a
  6.3 s walk; N=18,000 gives 18,081 rules, 36,001 directories, 54,002 calls and a 68.7 s walk, which is longer than the 60 s
  watchdog (`mcp/liveness-watchdog.js`, `DEFAULT_WATCHDOG_TIMEOUT_MS = 60_000`). The watchdog cannot defer to disk progress here,
  because the walk writes nothing (`progressPaths` are the database and its `-wal`).
- Upstream report, not sent anywhere: `qa-results/codegraph_followup_20261027/upstream_bug_report_filewatcher_refreshWatchTree.md`.
  Owed upstream: a matcher that does not scan 18,914 rules per directory, a walk that yields to the event loop, and anchored seeds
  (next paragraph). None of it can be fixed in this repository.

### Do the project's include/exclude rules fix the stock daemon on this tree?

Files: `14_walk_bench_sim_exclude.json`, `14_walk_bench_candidate.json`, `35_walk_bench_summary.tsv`,
`scope_candidate/`. A standalone driver ran the engine's own `buildScopeIgnore` and a replica of the walk, with a project
`codegraph.json` exclude list placed in front of the matcher.

| Case | Patterns placed in front | Matcher build | Walk | Directories visited | Build + walk |
|---|---|---|---|---|---|
| baseline (no project config) | 0 | 9.3 s | 240.0 s, did not finish | 49,110 | not finished |
| 182 patterns (the intent recorded in the dead `.codegraph/config.json`) | 182 | 9.6 s | 63.1 s | 11,747 | 72.7 s |
| derived candidate | 256 | 9.1 s | 51.9 s | 9,682 | 61.0 s |

Reading: the exclusion rules cut the walk by at least a factor of four in directories, but build plus walk stays at or above the
60 s watchdog budget (72.7 s and 61.0 s), because the 9.1 to 9.6 s matcher build and the per-call cost of the 18,914-rule matcher
are unchanged. So project configuration alone is NOT a supported fix for the stock daemon on a tree of this size. Caveat: these are
replica measurements of the engine's functions in a standalone process; the effect on a real daemon with the candidate config in
place was not measured and is UNCONFIRMED. The only config file CodeGraph 1.6.2 reads for a project is `<root>/codegraph.json`
(from the installed loader); `.codegraph/config.json` is dead configuration for this version.

### Operator instructions for a user-scope stock entry (documented, NOT applied by any tool or agent)

Finding (P7 of [codegraph_mcp_preflight](codegraph_mcp_preflight.md), H7 of this tool): the operator's `/home/milos/.claude.json`
holds a top-level `mcpServers.codegraph` entry `{"type": "stdio", "command": "codegraph", "args": ["serve", "--mcp"]}`. It is the
only stock entry found across the `~/.claude*` configurations. These tools never edit that file. Manual steps:

1. Preferred: delete the top-level `mcpServers.codegraph` key from `/home/milos/.claude.json`, leaving every other server as it is.
   Every project that carries the constitution declares the sanctioned wrapper in its own `.mcp.json`
   (`bash constitution/scripts/codegraph/codegraph_mcp.sh`, project as working directory); a user-scope entry cannot name a
   per-project path, so a user-scope replacement would bind to one project and is not recommended.
2. Only if a stock entry has to stay for some project that has no project-scope declaration: add
   `"env": {"CODEGRAPH_NO_WATCH": "1"}` to that entry. This is the partial mitigation measured above (kill loop gone, still a
   writer, still about 3 GB, status about 112 s). Record the reason next to the entry.
3. Make the client re-read its configuration: start a new session, or reconnect the server with `/mcp`. Which of the two re-reads
   a user-scope file is UNCONFIRMED; a new session is the certain one.
4. Verify with captured output, not by looking at the file:
   `bash constitution/scripts/codegraph/codegraph_mcp_preflight.sh --project <project>` (P7 must read PASS) and
   `python3 constitution/scripts/codegraph/codegraph_mcp_health.py --project <project> --probe-symbol <a known symbol>`
   (H7 must read PASS, H8 must read PASS with the fabricated symbol not found).

### A second defect found while measuring: unanchored and file-valued seeds

Files: `36_seed_anchoring_probe.js` and `.txt`, `37_seed_anchoring_impact.js`, `37_ab_*`, `38_index_impact_of_unanchored_seeds.txt`.
`buildScopeIgnore` turns every git-reported ignored-untracked entry into the rule `entry + '/'` (`extraction/index.js:367`,
`entry.endsWith('/') ? entry : entry + '/'`). A single-segment rule with a trailing slash matches at any depth, and an ignored
FILE becomes a directory rule. Probe: a repository with `.gitignore` `/out/` and a tracked `src/out/a.c`: git does not ignore it,
the engine's `ScopeIgnore.ignores('src/out/')` returns true. Census on the real tree: git reports 18,473 entries (file 18_ counts
18,467 in the matcher build; the 6-entry difference is not explained, UNCONFIRMED), of which 2,776 are directories and 15,697
(85 %) are files or symlinks rewritten into directory rules; 39 entries are single-segment (13 directories, 26 files). A/B run of the
engine's own function with and without the seeds (B = same code in a process with no `git` on `PATH`, 447 rules): of 8,926 tracked
files that sit under a nested directory named like a seeded entry, 8,345 are ignored only because of the seeds (7,898 under
`kernel`, 447 under `cmd`, for example `docs_chain/cmd/docs_chain/main.go`) and 581 are dropped in both. Effect on the LIVE index
is UNCONFIRMED: a read-only open found 5,701 of the 8,345 seed-only files present in the live index (586,673 file rows), so the
seeds did not remove all of them from it; why is not established. Reported in the upstream bug report; not fixable here.

## Prerequisites

- `python3`, standard library only. Linux `/proc` (process identity, descriptor scan); behaviour elsewhere is UNCONFIRMED:.
- For H3/A3: the sanctioned wrapper `codegraph_mcp.sh` and `fk_index_patch.py` beside the tool.
- A project that declares a `codegraph` server in `.mcp.json`, or has a `.codegraph/` index (otherwise exit 3, nothing to inspect).
- Optional pin file: `config/index/codegraph.pin` of the consumer project; its first non-comment line is `version=X.Y.Z`. The pin
  is consumer DATA (§11.4.35), never a constitution literal.

## Usage

```sh
codegraph_mcp_health.py [--project DIR] [--mcp-json FILE] [--expect-version V | --pin FILE]
    [--probe-symbol NAME] [--heal] [--no-roundtrip] [--timeout-init S] [--timeout-list S] [--timeout-call S]
    [--wal-warn-mb N] [--wal-fail-gib N] [--window-h N] [--wedge-s N] [--json]
```

| Flag | Default | Meaning |
|---|---|---|
| `--project DIR` | cwd | Project root; its `.mcp.json` and `.codegraph/` are inspected |
| `--mcp-json FILE` | `<project>/.mcp.json` | Server declaration to probe |
| `--expect-version V` / `--pin FILE` | pin file if present | Version the runner patch was proven against; a mismatch with the first `codegraph` on PATH is a FAIL (H2) |
| `--probe-symbol NAME` | none | After `codegraph_status`, search for a known symbol AND a fabricated one; the fabricated one must return nothing |
| `--heal` | off | Run the A1..A4 repairs below, then a fresh re-check; the verdict is the re-check, never the repair |
| `--no-roundtrip` | off | Skip H8 (diagnostics and heal only); the gate refuses this flag |
| `--timeout-init` / `--timeout-list` / `--timeout-call` | 30 / 60 / 180 s | Wait limit for each response, not a total |
| `--wal-warn-mb` / `--wal-fail-gib` | 1024 MiB / 20 GiB | H5 thresholds |
| `--window-h` | 24 | Look-back window for H6 evidence |
| `--wedge-s` | 120 | A4: seconds a `writer.pid` may stay `ready:false` before the daemon counts as wedged |
| `--json` | off | Adds one JSON object as the last output line |

## Checks

Each prints `HEALTH <id> PASS|FAIL|WARN|SKIP <text>`; the last line is `SUMMARY fail=N warn=M`.

| Id | Asserts | FAIL / WARN condition |
|---|---|---|
| H1 | The project declares a `codegraph` server; prints the exact command and args that will be spawned | none declared (FAIL) |
| H2 | Effective `codegraph` on PATH equals the pin; duplicate installs on PATH are listed | version mismatch (FAIL); a second install on PATH (WARN, e.g. the standalone 1.6.0 behind the npm 1.6.2) |
| H3 | The wrapper's `--dry-run` resolves a receipt-valid read-only runner for the INSTALLED version | a REFUSED patch (FAIL, names the anchor); a live writer makes it BUSY (WARN, exit 4) |
| H4 | Lock, `writer.pid`, `daemon.pid`, `daemon.sock` are judged by the holder's real `/proc/<pid>/cmdline`, never by pid existence alone | stale files (WARN); a live non-codegraph pid does not make a lock live |
| H5 | WAL size against the thresholds (the 81 GB WAL class of 2026-09) | over warn (WARN), over fail (FAIL) |
| H6 | Watchdog-kill loop in `daemon.log` and kernel OOM kills of node/codegraph inside the window | WARN at 3 or more watchdog kills in the window, or any node/codegraph OOM kill (attribution to CodeGraph is not established by the check); SKIP when the kernel journal is unreadable (no evidence either way, not a PASS) |
| H7 | User-scope stock `codegraph serve --mcp` entries (`~/.claude.json`, `$CLAUDE_CONFIG_DIR/.claude.json`) | an entry found (WARN); the tool never edits those files. Limits of the current implementation are listed under "Honest boundaries" (a regex over the joined argv, an unreadable or invalid file is skipped silently) |
| H8 | The real round trip, and that the session left no writer/daemon artifacts behind | EOF/timeout/empty tool list/search that matches anything/created files (FAIL) |
| H9 | Index schema version against the installed software, `index_state`, `synthesis_pending` (read-only open) | index schema newer than the installed software (FAIL); older schema, owed index work, no index or an unreadable index (WARN) |

H8 is the load-bearing one: a server that exits early, hangs after `initialize`, returns an empty tool list, or answers any
search with a match is a FAIL here even when every static check passed. A search probe whose fabricated needle also matches is
reported as FAIL, because a null from a blind instrument and a null from a clean index look the same (§11.4.273).

## Heal actions (`--heal`)

Idempotent, reversible, logged to `<project>/.codegraph/index_runs/health_heal.log`. A heal never edits `~/.claude.json`, never
deletes the database, never writes a database that has a live holder.

| Action | What it does | Refuses when |
|---|---|---|
| A1 | Moves provably-stale lock/pid/socket files aside into `.codegraph/index_runs/health_reaped_<timestamp>/` (holder dead, or alive but not a codegraph process) | the holder is a live codegraph process: kept, never killed |
| A2 | `wal_checkpoint(TRUNCATE)` when the WAL is over the warn threshold, then re-reads the size to prove it shrank | any process holds the database open, or the writer flock `.codegraph/.helix_index.flock` is taken |
| A3 | (Re)builds the read-only runner when missing or stale | the patch is REFUSED: reported `NEEDS-PATCH-UPDATE`, the stock server is never substituted |
| A4 | Stops an identity-verified wedged daemon: SIGTERM, SIGKILL after 15 s; the pid is validated as an int greater than 1 first (§11.4.263) | identity not verified, or `writer.pid` is not `ready:false` past `--wedge-s` |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No FAIL |
| 1 | At least one FAIL |
| 2 | Usage error or cannot determine (BLIND) |
| 3 | Nothing to inspect: no codegraph server declared and no index. A SKIP, never a PASS |
| 4 | BUSY: a live writer (a legitimate `sync`) holds the index, so the round trip could not run. No verdict, never a PASS and never a FAIL |

## The gate: `CM-CODEGRAPH-MCP-HEALTH`

`scripts/gates/cm_codegraph_mcp_health.sh` runs the tool and maps its verdict onto the gate convention (0 PASS, 1 FAIL, 2 BLIND,
3 SKIP). It refuses `--heal` and `--no-roundtrip` (exit 2): a gate measures, it never repairs and never skips the round trip. A
PASS needs the tool to exit 0 AND explicit `HEALTH H1 PASS` and `HEALTH H8 PASS` lines; a tool that exits 0 without having
round-tripped is BLIND, not healthy. Tool exit 3 and exit 4 map to gate SKIP (3), so a legitimate sync is never a false-positive
FAIL (§11.4.201(1)). `CG_HEALTH_TOOL` overrides the tool path (the mutation test points it at a mutated copy).

Paired mutation test (`cm_codegraph_mcp_health_mutation_test.sh`), run in a scratch tree, never against a live index:

| Part | Content | Result of the recorded run |
|---|---|---|
| 1 gate fixtures | HEALTHY and two controls, STALE-LOCK-DEAD, LOCK-LIVE-NON-CODEGRAPH (rc 0); ANCHOR-DRIFT, MISSING-WRAPPER, VERSION-PIN-MISMATCH, SERVER-EXITS-EARLY, SERVER-HANGS-AFTER-INIT, SERVER-EMPTY-TOOLS, SEARCH-MATCHES-ANYTHING, WRAPPER-WRITES-DAEMON-FILE (rc 1); TOOL-EXITS-0-WITHOUT-ROUNDTRIP, GATE-REFUSES-HEAL, GATE-REFUSES-NO-ROUNDTRIP (rc 2); BUSY, NOTHING-DECLARED (rc 3) | every fixture classified as stated |
| 1b tool level | WAL oversize FAIL / small PASS; heal reaps a dead lock and a pid-reuse lock, keeps a live codegraph holder, checkpoints (WAL 3118872 to 0 bytes) and skips the checkpoint with a holder, never fakes a pass under anchor drift | all as stated |
| 2 mutants | M1..M10 (tool: empty tools accepted, init failure downgraded, pin ignored, liveness by pid only, reap without liveness, WAL never fails, checkpoint despite holder, created files unchecked, negative control dropped, drift not reported) and G1..G3 (gate: round-trip evidence not required, BUSY read as PASS, heal allowed) | every mutant killed |

Instrument lesson recorded while building it (§11.4.273): a mutant first applied through the wrong environment knob (the tool
under test was not the one being mutated) survived for the wrong reason; the harness now passes the mutated copy through the knob
the case kind actually reads.

## Edge cases

- A legitimate `sync` is running: the tool exits 4 (gate SKIP). It does not stop, kill or race the writer. Re-run after the
  writer exits.
- The declared server is the stock `serve --mcp` (as in a user-scope `~/.claude.json` entry): H7 reports the entry as a WARN.
  Removing such an entry (or, as a partial measure only, adding `CODEGRAPH_NO_WATCH=1`) is a recommendation to the operator; the
  tool never edits it. The exact steps and their measured effect are in the Revision 3 section above.
- A project with no `.mcp.json` and no index: exit 3.
- A runner patch REFUSED after an upstream bump: H3 FAIL naming the anchor and `--heal` reports `NEEDS-PATCH-UPDATE`. The fix is a
  proven new shape in [mcpro1](mcpro1.md), not a fall back to the stock server.

## Related scripts

[codegraph_mcp](codegraph_mcp.md) (the sanctioned wrapper this probes), [mcpro1](mcpro1.md), [fk_index_patch](fk_index_patch.md),
[codegraph_mcp_probe](codegraph_mcp_probe.md) (the generic MCP client), [codegraph_mcp_preflight](codegraph_mcp_preflight.md),
[codegraph_launch_class](codegraph_launch_class.md) (the launch-target classifier the preflight uses),
[codegraph_scope_guard](codegraph_scope_guard.md) (the scope proof that needs the scope data file),
[codegraph_safe](codegraph_safe.md) (the single writer entry).

## Registering the gate so the §11.4.227(A) ratchet counts it (Revision 3: patches prepared, NOT applied)

State measured 2026-10-27: `CM-CODEGRAPH-MCP-HEALTH` is named in no governance file, bound by no seam, and its gate file and
mutation test are untracked, so the ratchet does not see it. Three patch files were built against the current files and verified
(`patch --dry-run` applies each cleanly: `qa-results/codegraph_register_20261027/20_patch_dry_run.txt`). Nothing was applied;
the files are owned by other work and the constitution holds a staged merge.

| Patch | What it does |
|---|---|
| `02_post_update_hook_step5c.patch` | adds `validate_codegraph_mcp()` as STEP 5c of `scripts/post_update_hook.sh` and `run_step validate_codegraph_mcp`. It names the token in a comment and in `tok="CM-CODEGRAPH-MCP-HEALTH"`, runs the preflight only when `$PROJECT_ROOT/.mcp.json` exists, and maps the gate verdict 0 PASS, 1 FAIL to ERROR, 3 SKIP to a warning, anything else to a BLIND warning |
| `01_rule_seam_bindings_row.patch` | appends the row `11.4.275<TAB>commit<TAB>CM-CODEGRAPH-MCP-HEALTH` to `scripts/gates/rule_seam_bindings.tsv` (not edited: another agent holds that file) |
| `03_constitution_names_gate_in_11.4.275.patch` | names `CM-CODEGRAPH-MCP-HEALTH` once in the §11.4.275 block of `Constitution.md` and in the four mirrors (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`, `GEMINI.md`) |

No new row is needed in `gate_ledger_deferrals.tsv` (an implemented gate is not a deferral) nor in `wiring_seam_files.tsv`
(`post_update_hook.sh` is already a declared `commit` seam file there). The existing deferral rows for
`CM-CODE-INDEX-AGENT-ACCESSIBLE` and `CM-CODEGRAPH-UPGRADE-PROBE-GATED` are untouched: this work does not claim them implemented.

Verification in scratch trees only (the real tree was not modified; `wiring_sweep_result.tsv` md5 identical before and after):

- Ledger (`21_ledger_scratch_validate.sh`, output `21_ledger_scratch_validate.txt`, `fail=0`): the control scratch ledger equals the
  real one on token and status for all 669 rows (UNIMPLEMENTED 395, IMPLEMENTED 151, DEFERRED 123). With patch 03 applied and the
  gate untracked the token reads UNIMPLEMENTED and the unimplemented count rises 395 to 396. With the gate file and its mutation
  test tracked it reads IMPLEMENTED (site: the gate file) and the count returns to 395. The mutation (token removed from the gate
  and its test) returns it to UNIMPLEMENTED, 396.
- FR-019 wiring sweep (`22_fr019_scratch_validate.sh`, output `22_fr019_scratch_validate.txt`, `fail=0`, run with `--no-write`):
  with the real hook the gate is listed UNBOUND (UNBOUND=39); with patch 02 it is bound (UNBOUND=38); a hook whose only mention is
  a comment (M1) and a hook with the basename renamed on non-comment lines (M2) both return to 39. The sweep exit code stays 2
  throughout because 38 other gates are UNBOUND, which is pre-existing.

Rules for applying the patches, each measured:

1. Stage the gate file, its mutation test, patch 02 and patch 03 in ONE commit. A scratch run with the hook stanza tracked and the
   gate file untracked made the ledger report IMPLEMENTED through `scripts/post_update_hook.sh`: the ratchet advanced on a gate
   nobody could run from a clean clone. (The same effect is already visible in the real ledger for
   `CM-PROVISIONAL-DONE-ANCHOR-WIRED`.) Apply patch 02 before patch 01, because the binding row cites the gate the hook runs.
2. Wiring the stanza makes every constitution pull run a live round trip of about 27 s, and the severity mapping FAIL to ERROR
   makes the hook fail while the user-scope stock entry exists (P7 FAIL today). Whether the hook should fail or warn is an operator
   decision; the patch ships the strict mapping.
3. Do not wire the preflight or this gate into `pre_build_verification.sh`: a build gate that depends on a live agent platform is
   the false-refusal class of §11.4.201(1).
4. Separate observation, not caused by this work: the real ledger currently counts 395 UNIMPLEMENTED against the baseline 394, so
   `gate_ledger.sh check` reports LEDGER-FAIL; the extra entry is `CM-COVENANT-114-290-PROPAGATION`, whose gate file
   (`cm_covenant_114_290_propagation.sh`) is untracked. Also, `gate_ledger.sh` picks the reported implementation site with
   `grep -rlE ... | head -1` and no sort, so that column depends on directory order (status columns do not).

## The scope data file (`config/index/scope.yaml`)

The file named in the dispatching brief does not exist in this repository and is not a name any constitution script, document or
earlier evidence uses: `scope_render.py --scope <file> --root <root>` and `codegraph_scope_guard.py --scope <file> --root <root>`
take any path, the template documents the conventional `<root>/codegraph.scope.yaml`, and `config/index/` holds only
`codegraph.pin`. The consumer has neither `codegraph.scope.yaml` nor a root `codegraph.json`; its live index (586,673 files indexed
of 1,032,717 tracked) was built with the engine's zero-configuration defaults, and the intended scope survives only in the dead
`.codegraph/config.json` (182 exclude patterns, 45 include globs). So the scope guard cannot run for this project because the
project owes a scope DATA file (§11.4.78(7)-(10), §11.4.275), not because a file is misplaced.

A candidate was derived mechanically (not applied, not tracked): `qa-results/codegraph_followup_20261027/scope_candidate/`
(`derive_candidate.py` reads the dead config, keeps 165 of the 182 patterns that still match tracked paths and drops 17, and
`scope_render.py` renders 256 exclude patterns). It declares `accepted_count: 0` on purpose: the guard fails until the operator
accepts a measured count. Operator decisions the candidate cannot make: whether `scrcpy` (Genymobile) counts as own or
third-party, whether `milos85vasic` is an own organisation, and the accepted file count with its tolerance. The candidate's effect
on the stock daemon is the replica measurement above, not a result.

## Honest boundaries

- It proves that the declared server answers a real round trip now and that its failure classes are visible; it does not prove
  every answer correct (§11.4.275) and it does not repair upstream code.
- The gate is not yet counted by the §11.4.227(A) ratchet and not bound to any seam: the registration patches above are prepared
  and verified in scratch trees, not applied.
- `codegraph_mcp_preflight.sh` now resolves the launch target of each declared server. Its tests F13 and F14 were RED before the
  preflight change of 2026-10-27 because the check did not exist (the tests were written first; the implementation was never
  made); they are GREEN now, with 18 of 18 preflight cases, 91 of 91 classifier cases and 23 of 23 mutants killed (see
  [codegraph_mcp_preflight](codegraph_mcp_preflight.md) and [codegraph_launch_class](codegraph_launch_class.md)).
- OPEN, same weakness class as the one the preflight fix removed: `check_user_scope()` in `codegraph_mcp_health.py` (H7) tests a
  regex over the joined argv, skips a configuration file it cannot read or parse without reporting it (an unreadable file reads as
  "no stock entry", the false-null of §11.4.201(6)), treats any entry whose argv mentions `codegraph_mcp.sh` anywhere as the
  sanctioned wrapper, and echoes the first three argv tokens into its output. It was not modified; P7 of the preflight is the
  classifier-based check and the supported one.
- OPEN: the preflight's P7 scans only `$HOME/.claude.json` and the current `CLAUDE_CONFIG_DIR`; a bare `npx codegraph` is
  classified as stock although which package it resolves is UNCONFIRMED; the classifier is static and classifies by name only a
  compiled launcher, a script of 256 KiB or more, a script in a non-shell language and a launch assembled at run time (its full
  list is in [codegraph_launch_class](codegraph_launch_class.md), "What it cannot see").
- OPEN: the root causes in the engine (an 18,914-rule matcher scanned per directory, a synchronous main-thread walk, unanchored
  and file-valued seeds) are upstream defects; this repository can only avoid them by using the sanctioned wrapper.
- OPEN: no project scope data file exists for the consumer (previous section).
- OPEN, cause UNCONFIRMED: in the session that produced Revision 3 the platform reported `codegraph` as failed to connect
  (`-32000: Connection closed`); whether that was the user-scope stock entry could not be established from inside the session.
- Pre-existing and unchanged: the wrapper leaves empty `cg_mcp_err.*` files behind (`codegraph_mcp.sh:54` trap, `:140` exec).

## Last verified

2026-10-27 (CodeGraph 1.6.2, npm `latest`; Revision 3 additions, evidence under `qa-results/codegraph_followup_20261027/` and
`qa-results/codegraph_register_20261027/` of the reference consumer):
- `VERIFIED (ran: the real gate and the tool against the live project; saw: H1 PASS, H2 WARN (two installs, 1.6.0 and 1.6.2), H3 to H5 PASS (WAL 0 MiB, db 43.8 GiB), H6 WARN (4 watchdog kills in 24 h) and PASS (0 OOM kills), H7 WARN (user-scope stock entry), H8 PASS (0.3 to 0.4 s initialize, 14.3 to 16.6 s tools/list, 8 tools, 26 to 29 s total), H9 PASS (index complete, schema v11), gate PASS, exit 0)`.
- `VERIFIED (ran: two stock daemons on a reflink copy of the live index, E0 default and E1 with CODEGRAPH_NO_WATCH=1; saw: kills 2 versus 0, status answered at 90.3 s versus 111.8 s, E1 still a read-write writer with codegraph.lock and 20,632 WAL bytes, E1 negative control unanswered behind a queue-busy message, peak RSS 2,381 versus 2,966 MB)`.
- `VERIFIED (ran: a standalone bench of the engine's own buildScopeIgnore plus a replica of the watcher walk on the real tree, and a synthetic repository; saw: 18,914 rules (97.6 % seeds), 4.13 ms per call with 98.0 % in ignore, a 240 s capped real walk unfinished at 49,110 directories, synthetic N=18,000 walk 68.7 s over the 60 s watchdog)`.
- `VERIFIED (ran: the three registration patches with patch --dry-run against the current files, and two scratch-tree validations; saw: all three apply; ledger S0 to S5 fail=0; FR-019 sweep control UNBOUND=39, patched 38, both mutations back to 39; wiring_sweep_result.tsv md5 unchanged)`.
- `NOT VERIFIED: the registration patches were not applied to the real files; the candidate scope file was not applied; the effect of the candidate scope or of CODEGRAPH_NO_WATCH=1 on a real daemon serving a real agent session was not measured beyond the two experiments above; H7's own weaknesses are open.`

2026-10-26 (CodeGraph 1.6.2, npm `latest`):
- `VERIFIED (ran: bash constitution/scripts/gates/cm_codegraph_mcp_health_mutation_test.sh; saw: 41 "ok" lines, 0 "BAD", "META PASS", EXIT=0)`, run again after the SIGPIPE-safe rewrite of the grep sites.
- `VERIFIED (ran: the real gate against the live project while a sync held the writer slot; saw: H3 BUSY WARN, exit 4, gate SKIP)`.
- `VERIFIED (ran: the exact .mcp.json command driven by a scripted MCP client before the reindex started; saw: initialize 0.57 s, 8 tools, query for a known symbol returned "Search Results (5 found)", exit 0)`.
- `VERIFIED (ran: the tool with --probe-symbol on the live project after the reindex finished (586,673 files, 14,934,852 nodes, 49,695,129 edges, synthesis_pending=0); saw: H1 H3 H4 H5 H8 H9 PASS, H8 = initialize 0.3 s, tools/list 14.4 s (8 tools), known symbol found, fabricated symbol not found, exit 0, SUMMARY fail=0 warn=2)`.
- `VERIFIED (ran: the real gate on the same project after four stock-daemon reproductions; saw: H6 WARN "4 daemon watchdog kills in the last 24h", H7 WARN for the user-scope stock entry, "CM-CODEGRAPH-MCP-HEALTH: PASS", exit 0)` — H6 counts every watchdog kill in the window whatever its origin, so deliberate reproductions show up as evidence, as designed.
- `VERIFIED (ran: the exact user-scope command `codegraph serve --mcp` through a scripted MCP client after the reindex; saw: kill 60.08 s after start, status after 82.1 s, tools/list returned 1 tool, the same as before the reindex)` — the stock entry is NOT fixed by the reindex; only the sanctioned wrapper path is.
- `VERIFIED (ran: a node-inspector CPU profile of a live stock daemon started with CODEGRAPH_NO_WATCHDOG=1; saw: 95.5 % self time in the gitignore matcher under FileWatcher.start > refreshWatchTree > walk, after 6.5 minutes)`.
- Evidence: the reference consumer's pack `qa-results/codegraph_fix_20261027/` (files 84 to 95); this guide's claims do not depend on it.
