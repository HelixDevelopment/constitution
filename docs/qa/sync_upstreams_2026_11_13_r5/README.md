# Sync-all-upstreams — round-5 evidence (CON-PENDING-SYNC-UPSTREAMS)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14 |
| Status | PROVISIONAL (pending the round-5 independent review); not VERIFIED-DONE |
| Status summary | Round-5 structural fix of the round-4 review (NO-GO, RV4-1 to RV4-15). Evidence class: gate-logic / unit class per §11.4.289 (local `file://` bare repositories, loopback ports, a git shim that plays the user; no forge, no network). |
| Issues | open items listed below |
| Fixed | RV4-1 to RV4-9 fixed, RV4-10 scoped out and tracked, RV4-11 to RV4-15 fixed or documented (table below) |

## Contents

| Path | What it is |
|---|---|
| `class_inventory.md` | The structural class inventory: (a) user state that changes between inspection and the write, (b) streams and resources a remote can supply, (c) process lifecycle under signals, (d) environment and configuration rows with their ground truth. Every row names its closure and the test or mutant that proves it. |
| `ground_truth/` | git 2.53 precedence experiments D1–D22 (`git_precedence_experiments.py`, run twice: `run1.txt` = `run2.txt`) and D23/D24 (`git_uploadpack_experiment.py`, run twice, identical). |
| `red/red_robustness_r4_engine.txt` | RED: the new live suite `tests/sync/test_robustness.sh` against the ROUND-4 engine: PASS 43 FAIL 43. |
| `red/red_<mutant>_<check>.txt` | RED of each new check on its mutant (M53, V04, P05, P14, P24, P27, P29, P33); the GREEN twin is `green/green_<mutant>_<check>.txt` where one was recorded. |
| `green/` | GREEN: every suite twice on the round-5 engine (`run1/`, `run2/`, `compare.txt`), the mutation tables, the redaction timing and the SIGPIPE probe. |
| `redaction_timing.py` | Measures `redact()` on 256 KiB and 1 MiB lines (RV4-3). |
| `SHA256SUMS` | sha256 of every file in this directory. |

## Findings of review round 4 and their status

| Finding | Status | Where |
|---|---|---|
| RV4-1 write-time TOCTOU | Fixed: `write_git` re-reads, as its last checks before git starts, the status, the in-progress markers, the ignored files, for a pin the parent's index AND its HEAD tree, then HEAD and the symbolic ref; after the write HEAD and the ref are read again. A blocked write is a reason (`write-blocked:<why>`, attention). The window of milliseconds between the last read and git's own ref lock remains and is stated, never claimed closed. | class (a) a1–a6; robustness `race_*`; unit `RoundFive` |
| RV4-2 staged gitlinks | Fixed: reported `gitlink-staged:<path>` (attention); never written over (write step 3). Decision 2026-11-14: a stage equal to the submodule's checkout is not re-advanced either (it is the reviewer's P32 case), so after `--advance-pins` a check reports attention until the user commits the pin; ui 4, security 3 and hardening M67 expect that. | a7; robustness `staged_gitlink` |
| RV4-3 quadratic redaction | Fixed: `_strip_line` is linear; measured best of 5: ≤ 0.037 s for 256 KiB, ≤ 0.118 s for 1 MiB (`green/redaction_timing.txt`). "Bounded" wording corrected. | unit equivalence fuzz (4000 cases) + linearity test |
| RV4-4 unbounded output | Fixed: capped streaming reader (stdout cap, stderr tail), `output-too-large` is a no-answer; reading stops once git itself has exited (an escaped grandchild holding a pipe is not waited for). | b1–b10; robustness `huge_stderr`, `long_line` |
| RV4-5 signals | Fixed: SIGTERM/SIGINT/SIGHUP stop read-only calls (process group killed through `proc_kill_group`, pgid > 1 and the child's own group, §11.4.263), a write in flight is finished, heads are re-read, a report is written, exit 8 `INTERRUPTED`; a second signal hard-stops. | c1–c7; robustness `sigterm_*`, `sigint_fetch` |
| RV4-6 askpass | Fixed: `GIT_ASKPASS` set empty (it beats `core.askPass`), `core.askPass=` pinned, `SSH_ASKPASS_REQUIRE=never`, `credential.interactive=false`. A configured `credential.helper` still runs (stated). | class (d); robustness `askpass` |
| RV4-7 protocol env | Fixed: `GIT_ALLOW_PROTOCOL` and `GIT_PROTOCOL_FROM_USER` dropped; precedence re-derived (D1–D24). D24: a `-c remote.<n>.uploadpack=` pair does not override a repository value, so `uploadpack` in the repository config is a stated boundary (like `core.sshCommand`). | class (d); robustness `ext_env`, `protocol_from_user` |
| RV4-8 `--out` | Fixed: resolved, must be outside the tree, created and probed with a real temporary file before anything else (exit 2, nothing done); the default is checked the same way; evidence that cannot be written after a write is exit 1, never 2. | robustness `out_unwritable`, `out_lost`, `default_out*` |
| RV4-9 behavioural kills | See the mutation section below. | `green/mutants_*` |
| RV4-10 `update=none` | Scoped out, tracked as `SYNC-R5-OPEN-1`. | a14 |
| RV4-11 overlapping roots | Fixed: one lock per repository of the tree, taken after discovery and before any fetch or write. | robustness `lock_overlap` |
| RV4-12 default out dir | Fixed: the default is checked like `--out`; a relative cache directory is refused. | robustness `default_out*` |
| RV4-13 unsafe gitlink paths | Fixed: `pin-unsafe-path`. | robustness `unsafe_path` |
| RV4-14 `GIT_SSH_COMMAND` | Documented: not honoured from the caller's environment (the engine sets its own); a repository `core.sshCommand` is kept and reported. | manual, credentials |
| RV4-15 repositories outside the root | Fixed: `pin-outside-parent` (the parent of the gitlink path is resolved, so a symbolic link as the last component is still `pin-not-a-directory`). | robustness `outside_parent` |

## Mutation testing (RV4-9 and this round's own mutants)

`tests/sync/test_mutations.py` holds 189 mutants: the 155 of earlier rounds and the reviewer's, plus 34 written in
this round (P01–P34, one per closure this round adds). A mutant counts as killed only when a listed suite FAILs on
the mutated copy; every suite runs against the copy, never the real tree.

| Run | Result | File |
|---|---|---|
| Full table, all 189 (tests as they stood at the start of the run) | killed 178, equivalent 1 (M37), survived 10: M53, V04, V16, P05, P14, P24, P27, P29, P33, P34 | `green/mutants_full_189.txt` |
| The 10 survivors, after the checks below were added | killed 10 of 10 | `green/mutants_survivors_rerun.txt` |
| The RV4-9 list without the static gate (`--no-gate`), plus P34 | killed 9 of 10 named (V01, V02, V04, V08, V09, V13, V17, V18, V22); V16 and P34 survive | `green/mutants_rv4_9_no_gate.txt` |

What each survivor showed, and the check that now kills it (RED on the mutant, GREEN on the real engine; files in
`red/` and `green/`):

- M53 (waiting for an escaped grandchild's stderr): the chaos case timed git out, so the wait was never reached.
  New `escaped_after_exit`: git exits while a grandchild in its own session holds stderr; the run must end in
  seconds.
- V04 (`Authorization:` values not redacted): the old check was a FALSE NULL, because the engine never prints a
  fetch's stderr. New `auth_header`: a smudge filter that fails during a merge prints the header, which reaches
  `actions[].error`, with a control needle on its own line.
- P05 (a head moved by someone else reported as this run's update): `race_control` checked only that the user's
  commit was kept. New `race_other` asserts `head-changed-during-run` and `changed_by_other` (a `--check` run
  cannot see it: it re-reads no head).
- P14 (new calls after a stop not refused): a call started after the stop is killed at once, before the shim can
  log it, so the report's `git_calls` is compared with the calls the shim saw (`no_new_call`; P14 started 27,
  the shim saw 23).
- P24 (the evidence directory not probed): `makedirs` already failed for a missing child; the new case passes an
  existing directory that cannot be written, with a writable control.
- P27 (per-repository lock without `O_NOFOLLOW`): `lock_symlink` now plants the link at a submodule's lock too.
- P29 (a relative cache directory accepted): from inside the tree the inside-the-tree check refused it anyway; the
  new case runs from a directory outside the tree, with an absolute-cache control.
- P33 (final reads after a stop not capped): new `final_cap`; the shim makes every `rev-parse` started after the
  stop hang 45 s; the real engine ends in about 22 s, P33 in about 92 s.
- V16 (`SSH_ASKPASS` kept) and P34 (`core.askPass=` not pinned): behaviourally EQUIVALENT while the other askpass
  closures hold (ground truth D12/D13 and D9: git does not fall back once `GIT_ASKPASS` is set empty). They are
  killed only by the static gate, which requires both. This is stated, not claimed as a behavioural kill.

The full 189-mutant table was not re-run after the new checks were added; the 10 survivors were. The new checks only
add assertions to existing check functions or add new ones, so a mutant killed in the full run is not affected.
UNCONFIRMED: the full table on the final tree.

## Documentation claims corrected

"git never prompts" (wrapper header, engine docstring, FAQ 7, CHANGELOG round-1 text kept as history, corrected in the round-5 entry) · "Bounded" (design) · "within 7 more seconds" (user guide exit 5, FAQ 9) · "never detached" (user guide) · FAQ 8 "the second exits 7" · "one fcntl lock per project" (design, wrapper header) · "`--out` must be outside the work tree" (user guide exit 2, now with resolution, the writable probe and the default) · the `ext::` guarantee (manual, class (d)) · "a 256 KiB line takes milliseconds" (manual, replaced by the measured figure). Hostile clean/smudge filters and diff drivers are stated as a boundary (manual, design, engine docstring).

## Open items (tracked, not fixed in round 5)

- `SYNC-R5-OPEN-1`: a follow-pin does not read `submodule.<name>.update=none` (RV4-10).
- `SYNC-R5-OPEN-3`: a stdout closed before the run ends gives Python's exit 120 (no traceback, reports written, `BrokenPipeError` on stderr); a caller reads 120 as BLIND. Measured, `green/sigpipe_probe.txt`.
- `SYNC-R5-OPEN-4`: the INTERRUPTED branches added to `setup.sh` (exit 8 fails the sync step) and `post_update_hook.sh` (warned like BLIND) have no test, and neither has the exit-8 mapping in `sync_step_lib.sh` (`INTERRUPTED`); the engine's exit 8 itself is tested (`sigterm_*`, `sigint_fetch`).
- Outside this vehicle: `CM-KILLPG-PGID-GUARD` (§11.4.263) still PASSes on the round-3 reviewer mutant X04 (`pgid > 1 or True`); only this vehicle's gate refuses it. Tracked as an item for the general gate.
- Operator question, defaults NOT changed: `setup.sh --sync-upstreams` defaults to `off` and `post_update_hook.sh` STEP 5c to `offline` (`--check --no-fetch`). Should either default change? Operator decision (§11.4.66).
- Carried from round 4: a child that cannot follow its parent's new pin is `failed` after the parent moved (hold-back is an open design question); evidence directories have no retention; behaviour against real forges is UNCONFIRMED.

## Merge note

The vehicle branch `vehicle/sync-upstreams-r5` merged `main` at `bd0036bd` (merge commit `b652a293`) before the round-5 work. Conflicts in `CHANGELOG.md` (1 hunk) and `README.md` (2 hunks) were resolved as a
union (no side dropped, no `-s ours`); the merge changed no file under `scripts/sync/` or `tests/sync/`.
