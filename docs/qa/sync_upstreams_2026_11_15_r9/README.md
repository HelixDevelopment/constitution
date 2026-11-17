# Sync-all-upstreams, review round 9 fixes (RV8-1 to RV8-4) — evidence

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15 |
| Status | PROVISIONAL (§11.4.290): fixes made, own runs below; independent review of round 9 still owed |
| Roadmap item | CON-PENDING-sync-r8 |
| Evidence class | gate-logic / unit class (§11.4.289(C)(2)): local `file://` bare repositories, real git 2.53, an in-process fault driver for the environment (signal, foreign lock, foreign object at the marker path). Forge behaviour is UNCONFIRMED |
| Fixer | fresh structural fixer (round 9, §11.4.276(E): re-derive ground truth, enumerate the class, replace rather than layer), model Opus 5.5, effort UNKNOWN (not settable or readable on this dispatch path) |

## Table of contents

- [Ground truth](#ground-truth)
- [What changed](#what-changed)
- [Class inventory](#class-inventory)
- [RED and GREEN](#red-and-green)
- [Mutants](#mutants)
- [Suite runs](#suite-runs)
- [Honest limits](#honest-limits)

## Ground truth

Two instruments, two different facts (git 2.53):

- Which lock files each write TAKES: `ground_truth/git_lock_probe.sh` (strace of `openat`, output
  `git_lock_probe.out`). `merge --ff-only`: `index.lock`, `HEAD.lock`, `ORIG_HEAD.lock`, `AUTO_MERGE.lock`,
  `packed-refs.lock`, `refs/heads/<branch>.lock` (and `objects/maintenance.lock`). `checkout --detach`:
  `index.lock`, `HEAD.lock`, `AUTO_MERGE.lock`, `packed-refs.lock`. `add`: `index.lock`. Linked worktree:
  the first four in `<common>/worktrees/<id>/`, `packed-refs.lock` and the branch lock in the common dir.
  These are the engine's lock sets (minus `objects/maintenance.lock`, see the limits), plus
  `reftable/tables.list.lock` from `reftable_probe.out`.
- What a STALE lock does to the write: `ground_truth/git_lock_matrix.py` plants each candidate and runs the
  write exactly as the engine does (`git_argv`), output `git_lock_matrix.out` (columns: rc, HEAD moved,
  status after, lock left). Refused: `index.lock` (merge rc 1, checkout and add rc 128, nothing changed),
  `ORIG_HEAD.lock` (merge rc 128, nothing changed), `HEAD.lock` (merge AND checkout rc 128 with `M  f`: the
  index and work tree were rewritten, HEAD not moved: the half-write of RV8-1), the branch lock (merge rc 128,
  `M  f`, also in a linked worktree, which confirms the reviewer's UNCONFIRMED case). Reftable
  `tables.list.lock`: rc 128, clean tree. NOT refused: a stale `packed-refs.lock` or `AUTO_MERGE.lock` (rc 0,
  the lock left in place); `config.lock`, `objects/maintenance.lock`, `shallow.lock`, `refs/heads/other.lock`
  (rc 0). In a linked worktree `<common>/HEAD.lock` is not touched (golden-FALSE).
- Decision: the engine refuses on every lock the write TAKES, including `packed-refs.lock` and
  `AUTO_MERGE.lock`, which git itself tolerates when stale. A present lock may belong to a git process that is
  running now; refusing is the conservative choice (§11.4.201(4)). The cost: a truly stale lock of those two
  blocks a write git would have completed; the report names the lock.

## What changed

`scripts/sync/sync_all_upstreams.py`:

- Lock sets as data, per git subcommand (`OP_GIT`, `GITDIR_LOCKS`, `COMMON_LOCKS`), from the ground truth;
  `lock_paths(gitdir, common, branch)` resolves them, common-dir entries labelled `common:<name>`.
  `in_progress` checks every one of them, and so do step 1 of `write_git`, `gitdir_write_block` (site
  registered at inspection; an unregistered git dir is never written) and the earlier-marker clean-up (RV8-1).
- `end_write(..., settled)`: a write git answered with a failure is "settled" only when HEAD and the index
  (`ls-files -s -z`) equal their state before the write (`write_settled`). Otherwise the marker is kept
  (`write-interrupted`), the action is `write-left-changes:<op>`, the repository FAILED, and a recovery hint
  is printed (RV8-1).
- One path-access layer (`path_kind`, `fs_read`, `fs_create_excl`, `fs_remove`, `fs_open_lock`,
  `fs_probe_dir`, `fs_ensure_dir`, `fs_write_atomic`, `fs_open_tty`). Reads open
  `O_NOFOLLOW | O_NONBLOCK` and require `S_ISREG` on the open descriptor; a FIFO, directory, socket, link or
  device at the marker path is `write-marker-path-not-a-file:<kind>`, blocks writes and is never opened or
  removed (RV8-2, RV8-4). `fs_remove` never raises; an earlier marker that cannot be removed is
  `write-marker-kept:cannot-remove:<reason>` (the reviewer's UNCONFIRMED EACCES case: r8 crashed with an
  internal `PermissionError`, `red/red_r8_marker_unremovable.txt`).
- `errno` is a module-level import.

Gate `scripts/gates/cm_sync_upstreams_ff_only.sh`: `errno` and `stat` modules and the new exact names
(`os.O_CLOEXEC`, `os.O_NONBLOCK`, `os.fstat`, `errno.errorcode(.get)`, `stat.S_IS*`) allow-listed; the new
read `write_settled ['ls-files', '-s', '-z'] ok=(0,)` added to the call-site oracle. Meta-test: five cases
re-anchored to `index_gitlinks`' new form (same meaning), two new cases (`STAT-NAME-UNLISTED`,
`ERRNO-ALIASED`), 93 cases.

Tests: `tests/sync/test_unit.py` class `RoundNine` and updated earlier classes; robustness checks
`lock_matrix`, `worktree_locks`, `marker_kind` (fifo, dir, symlink, dangling, socket × check/apply/dry-run,
bounded at 60 s), `lock_kind`, `half_write` (via the driver fault `lockspawn:<lock>:<site>`), `marker_vanish`
(driver fault `vanish-<site>`, for W03), `earlier_lock` (for W01), `marker_unremovable`. Docs: manual
(Git locks and half-applied writes), guide exit table, FAQ question 19.

## Class inventory

`class_inventory_write_paths.py` (AST, control-needled): rules R1–R4 of round 8 plus R5 (every filesystem
operation only inside `path_kind` / `kind_of_mode` / `fs_*`, exemptions stated in its header), R6 (lock sets
cover every write subcommand; `in_progress` uses `lock_paths`), R7 (`end_write` takes `settled`; the clear is
guarded by `settled` and the marker's write id). Round 9 engine: SEES, 0 violations
(`inventory/inventory_r9.txt`). Round 8 engine: SEES, 29 violations (`inventory/inventory_on_r8.txt`).

## RED and GREEN

- RED on the r8 engine (`red/`): new robustness checks PASS 175 FAIL 123 (lock_matrix 48/116 failed,
  worktree 4/24, marker_kind 39/75 with the FIFO cases at the 60 s bound, lock_kind 3/15, half_write 9/23,
  earlier_lock 20/26; marker_vanish 0/19, expected: r8's code is right there and only W03 breaks it);
  marker_unremovable crashes; unit PASS 91 FAIL 30 (some only because the new functions are absent).
- GREEN: unit 121/0 (`green/green_unit.txt`); the full robustness suite on the final engine 703/0
  (`runs/full_robustness.txt`). `green/green_new_checks_1.txt` (298/0) predates the `write_settled`
  simplification and is superseded by the full run. `green/green_half_write_u17fix.txt`: half_write 29/0
  after the U17 tightening.

## Mutants

`mutants/mut_full.txt`: 301 mutants, killed 300, equivalent 1 (M37, existing entry with its proof),
survived 0, harness errors 0. New: reviewer W01–W10 (W01–W03 and W05, W07–W10 verbatim; W04, W06
re-anchored, same meaning) and own U01–U18. Re-anchored, same meaning: M70, X06, N01, V05, V07, V13, P24,
P27, RR38, Q05, Q09, RV6F, S02, S03, S09, S10, RV7E, T02, T13. U17 first survived (`mutants/mut_new_ids.txt`):
`half_write` asserted only "not exit 0", while the mutant gives exit 4 (attention) instead of 1 (FAILED);
the check now requires exit 1 and `result == "failed"` (killed, `mutants/mut_u17.txt`). Note:
`mutants/mut_new_ids.txt` ran while the gate still failed on the new code, so its three kills "by gate"
(X06, N01, N10) are not evidence; the full run (after the gate fix) is.

## Suite runs

- `tests/sync/run_all.sh --quick` three times (`runs/quick_*.txt`): RUN_ALL: PASS each; unit 121, integration
  149, e2e 24, full-automation 34, security 83, determinism 15, ui 26, hardening 119; the sorted 450 verdict
  lines, timings stripped, hash to `13017d506d142e531594b5f0d7bfb36d31670184339a0e6ae9e578602ed02706` in
  all three.
- Full suites: robustness 703/0, chaos 58/0, perf 13/0 (call budget unchanged), faults 21/0.
- Gate PASS (`runs/gate_standalone.txt`); meta-test PASS 93 cases (`runs/gate_meta.txt`).
- `run_full_suite.sh --sync-guide` rc 0, no file changed; `--verify-manifest`: MANIFEST-OK.
- Found while running: the first three quick runs FAILED on the gate (new imports and names not
  allow-listed, new call site not in the oracle). The 48-mutant run and the first full mutation run were
  therefore invalid for "gate" kills; the full run was stopped, the gate fixed, and everything re-run.

## Honest limits

- A failed write that changed the work tree but neither the index nor HEAD is not detected
  (`write_settled` compares HEAD and the index only); git's measured half-writes change the index.
- `fs_remove`: a race between its `lstat` and `unlink` (an object swapped in between) is narrowed, not closed.
- The reftable lock is covered by unit tests only (no reftable fixture in the live checks).
- `config.lock`, `objects/maintenance.lock`, `shallow.lock` are not checked (measured: no effect on these writes).
- `marker_vanish` is a mutant-killer only (r8 already behaved right there).
- R5 of the class inventory is not part of the gate; adding it to `CM-SYNC-UPSTREAMS-FF-ONLY` is a follow-up.
- Default modes (`scripts/setup.sh`, the post-update hook) are unchanged.
- Round 9 exceeds the §11.4.276 ceiling; the operator decision on record says rounds continue until GO.
