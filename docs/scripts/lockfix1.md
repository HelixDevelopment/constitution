# lockfix1 (runner patch) — guide

**Revision:** 1
**Last modified:** 2026-09-26T13:50:00Z

Source: `constitution/scripts/codegraph/runner_patches/lockfix1.py` (73 lines). A **module driven by
`fk_index_patch.py`**, not a command. Citations are `lockfix1.py:<line>` unless another file is named. Machinery guide:
[fk_index_patch](fk_index_patch.md).

## FINDING FIRST: this patch has no behavioural test

No file under `scripts/codegraph/tests/` exercises lockfix1's runtime behaviour (no test contains
`__helixLockOwnerIsCodegraph`, and none builds a runner with lockfix1 and inspects a lock). The tree mentions the id
only in selection arguments (`tests/test_bulk_classify_mutate.py`, `tests/test_mcp_readonly_mutate.py`,
`tests/test_unit_safe.sh`) and `codegraph_safe.sh` (lines 63-68) states it has zero tests, which is why the wrapper does
not use it by default (`--patches fkidx1,resolve1`). `owed_report.py` reports "tested" only because the id is named.
Everything below is traced from source and from the ad hoc scratch checks recorded under Usage; nothing was run
against the real runner.

## Overview

Stock CodeGraph 1.6.0 `FileLock.acquire` (`lib/dist/utils.js`) treats a `.codegraph/codegraph.lock` whose mtime is older
than `STALE_TIMEOUT_MS` (2 minutes) as stale **whatever the recorded PID is** and unlinks it, and nothing refreshes the
mtime (docstring lines 3-9). A second `sync`/`index`/`init`/`serve` started more than two minutes into a long index
therefore deletes the live lock and writes the database concurrently.

lockfix1 removes the age clause. A lock is honoured only if its PID is an integer > 1, the process is alive (vendor
`isProcessAlive`, `kill(pid, 0)`) **and** `/proc/<pid>/cmdline` contains `codegraph`; a recycled PID that now belongs to
an unrelated program is treated as stale (lines 11-16, 36-38, 40-56).

A rejected alternative is recorded in the source (lines 18-22): refreshing the lock mtime from a timer, because the
vendor's own comments say parse/store/resolve spans block the event loop for minutes.

## Prerequisites

Reads `lib/dist/utils.js` from the package. Python stdlib plus `runner_patches/common.py`. Default-set patch
(`runner_patches/__init__.py:17`), applied second.

## Usage

Only through `fk_index_patch.py` (see the parent guide for flags):

```sh
python3 scripts/codegraph/fk_index_patch.py --patches lockfix1 --dst <scratch dir>
```

`NOT RUN` in this form (copies the 282 MB package). Checks that were run, all in a scratch directory holding only a copy of
stock 1.6.0 `utils.js`:

- `VERIFIED (ran: lockfix1.plan(FileView(scratch)); saw: APPLIED, anchors 'class FileLock {' and 'FileLock.acquire
  age-override condition', detail owner_identity_check "/proc/<pid>/cmdline contains 'codegraph'")`.
- `VERIFIED (ran: node --check on the planned utils.js with the system node v24.18.0; saw: exit 0; control: node --check
  on a deliberately broken file exits 1 with SyntaxError)`.
- `VERIFIED (ran: the injected helper extracted from the planned text and run under node; saw, for the
  process's own PID with "codegraph" in its argv: true; without it: false; PID 1: false; PID 999999 (no such process):
  false; the string '5': false)`. This confirms the identity test and the `pid <= 1` / non-integer refusals (helper
  lines 42-55).

## Behaviour (source-traced)

`plan(view)` (lines 59-73):

1. If the age-based condition anchor (line 36) is absent **and** `class FileLock` is present, `STALE_TIMEOUT_MS` is gone
   and `isProcessAlive(pid)` is present, the patch reports NOT_NEEDED (lines 61-65).
2. Otherwise, if the helper marker `__helixLockOwnerIsCodegraph` is present, Refuse: `source is ALREADY patched`
   (lines 66-67).
3. `replace_once` on `class FileLock {`: inserts the helper function before the class (line 68).
4. `replace_once` on `if (lockAge < FileLock.STALE_TIMEOUT_MS && !isNaN(pid) && this.isProcessAlive(pid)) {`: replaced by
   `if (!isNaN(pid) && pid > 1 && this.isProcessAlive(pid) && __helixLockOwnerIsCodegraph(pid)) {` (lines 36-38, 69).

Helper semantics (lines 40-56):

| Situation | Helper returns |
|---|---|
| Not an integer, or `<= 1` | `false` (lock is stale) |
| `/proc/self/cmdline` absent (no procfs) | `true` — owner cannot be disproven, never steal the lock |
| `/proc/<pid>/cmdline` unreadable with ENOENT | `false` — owner exited |
| Unreadable with any other error | `true` — keep the lock |
| Readable | `true` iff the command line contains `codegraph` |

Honest boundary stated in source (lines 24-27): the lock file stores only a PID, so a lock written by a codegraph on
another host over a shared filesystem is judged against the local PID table, exactly like stock; only the age override is
removed.

Observed limitation (from the helper text, not run): the identity test is a substring match on `codegraph` anywhere in the
command line, so any live process with that word in its arguments (an editor opened on a codegraph path, for example)
keeps a lock alive. The check is deliberately biased towards never stealing.

## Edge cases

All `VERIFIED (ran: planning against a scratch copy of stock 1.6.0 utils.js)`:

| Condition | Result |
|---|---|
| Stock 1.6.0 | APPLIED (2 anchors) |
| Plan again on the already-patched text | **Refuse**: `lockfix1: source is ALREADY patched — --src must be the pristine package` |
| `STALE_TIMEOUT_MS` and the age clause gone (upstream fixed) | NOT_NEEDED: `utils.js FileLock no longer has an age-based stale override (STALE_TIMEOUT_MS gone, PID liveness still checked)` |
| `class FileLock {` renamed | **Refuse**: `lockfix1: anchor 'class FileLock {' occurs 0x in lib/dist/utils.js (expected exactly 1) — upstream shape changed, re-derive the patch` |

Interaction: `mcpro1` also edits `utils.js` (`FileLock.acquire`/`release`) and is exclusive with every other patch, so the two
can never be combined (`runner_patches/__init__.py:31-34`).

## Related scripts

[fk_index_patch](fk_index_patch.md), siblings [fkidx1](fkidx1.md), [datafrag1](datafrag1.md), [resolve1](resolve1.md),
[resolve2](resolve2.md), [mcpro1](mcpro1.md) (which removes lock acquisition entirely), [codegraph_safe](codegraph_safe.md)
(declines it by default until tests exist), [owed_report](owed_report.md).

## Last verified

2026-09-26, scratch copy of stock 1.6.0 `utils.js` only; the real runner cache and every `.codegraph` were untouched.
