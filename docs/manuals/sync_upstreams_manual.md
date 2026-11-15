# Sync-all-upstreams manual — `scripts/sync/sync_all_upstreams.sh`

| Field | Value |
|---|---|
| Revision | 9 |
| Created | 2026-11-12 |
| Last modified | 2026-11-15T14:30:00Z |
| Status | draft (pending independent review) |
| Status summary | Reference for every option, state, reason, exit code, report field, integration point and safety property of the sync-all-upstreams engine. |
| Authority | Constitution §2.1, §11.4.10, §11.4.37, §11.4.50, §11.4.71, §11.4.84, §11.4.113, §11.4.164, §11.4.233(G), §11.4.263, §11.4.273, §11.4.288(D), §12. The canonical text wins where this manual and the constitution disagree. |
| Scope | Universal (§11.4.17); consumed by reference. |
| Issues | none |
| Issues summary | — |
| Fixed | revision 8: review round 7 (NO-GO) RV7-1 (a per-git-directory marker state machine: no marker is overwritten or removed by a write that did not create it; a git directory with an unresolved write, a marker or a lock takes no further write; the parent is checked before a pin is advanced), RV7-6 (`cannot take the run lock` for a refused flock); revision 7: review round 6 (NO-GO) RV6-1 (a write refused before git starts leaves no marker; a half-written marker is removed), RV6-2 (a lock-only leftover attributed to the interrupted write, guarded), RV6-3 (a run-lock flock error other than 'held' guarded in both lock paths); revision 6: review round 5; revision 5: review round 4 (NO-GO) RV4-1–RV4-15 (write-time re-read of HEAD, branch and the parent's HEAD-tree gitlink; staged gitlinks reported; linear redaction; capped output; stop signals end in a report, exit 8; askpass and protocol variables pinned or dropped; evidence directory probed before any write; one lock per repository of the tree; unsafe and outside-parent gitlink paths reported) and the false claims of revision 4 corrected; revision 4: review round 3 (NO-GO) F1–F9 (a submodule git cannot read is BLIND and printed under `--quiet`; `head_after` re-read after the whole pass; `--advance-pins` never detaches a branch; userinfo cut to the end of the line, remembered secrets removed anywhere; trace variables dropped; the one signal point checks the child's own group); revision 2: review round 2 (NO-GO) fixes F1–F13, N3; revision 3: review round 2 of the fixes (NO-GO) I-1–I-4, S-1, m-1–m-5, n-1–n-6 |
| Fixed summary | Fetch never deletes or rewrites a ref; no repository hook or fsmonitor runs; every git call declares which exit statuses are an answer, and a call with no answer makes the run BLIND (exit 6; INCONCLUSIVE, exit 5, when it only ran out of time), never "absent" or "clean"; one guarded writer re-checks the tree and ignored files before every move; distinct exit codes 5/6/7. |
| Continuation | — |

Related: [user guide](../guides/sync_upstreams_user_guide.md) · [FAQ](../faq/sync_upstreams_faq.md) ·
[design](../design/sync_all_upstreams_design.md)

## Table of contents

- [Files](#files)
- [Options](#options)
- [Run order](#run-order)
- [States and reasons](#states-and-reasons)
- [Exit codes and verdicts](#exit-codes-and-verdicts)
- [Evidence](#evidence)
- [Integration points](#integration-points)
- [Safety properties](#safety-properties)
- [Tests and gate](#tests-and-gate)
- [Honest boundary](#honest-boundary)

## Files

| Path | Role |
|---|---|
| `scripts/sync/sync_all_upstreams.sh` | Wrapper: `exec python3 -I -B sync_all_upstreams.py "$@"`. |
| `scripts/sync/sync_all_upstreams.py` | The engine (standard library only). |
| `scripts/sync/sync_step_lib.sh` | `sync_step MODE ROOT ENGINE` — the shared step used by `setup.sh` and `post_update_hook.sh`; sets `SYNC_STEP_RC` and `SYNC_STEP_VERDICT`. |
| `scripts/sync/fixture_lib.sh` | Test fixture library (scratch sandboxes of real bare repositories). |
| `scripts/sync/robustness_checks.py`, `scripts/sync/race_git_shim.py`, `scripts/sync/inproc_driver.py` | Robustness checks (`tests/sync/test_robustness.sh`; gate-logic / unit class, local repositories only), the test-only shim that plays a USER acting while a run is in flight (never a stand-in for git), and the test-only driver that runs the real engine module with ONE environment fault (a signal, the clock, the kernel) at a point no outside program can reach in time (round 7). |
| `scripts/sync/examples/` | systemd user service + timer and a cron line. Not installed. |
| `scripts/gates/cm_sync_upstreams_ff_only.sh` (+ `_mutation_test.sh`) | Gate `CM-SYNC-UPSTREAMS-FF-ONLY`. |
| `tests/sync/` | The test suites; `run_all.sh` runs them all. |

## Options

| Option | Effect |
|---|---|
| `--check` | Fetch (which only writes `refs/remotes/<remote>/*`, and with `--tags` new tags), report, change nothing else. Exit 3 when something is behind. |
| `--dry-run` | No fetch, no change: a plan from the refs already present. |
| `--apply` | Fetch, then fast-forward what is allowed (see [Run order](#run-order)). |
| `--no-fetch` | With `--check` or `--apply`: do not fetch (offline). |
| `--root DIR` | Project root; must be a work-tree top level. Default: the top level of the current directory. |
| `--branch NAME` | The trunk name (default `main`). |
| `--tags` | Also fetch tags. |
| `--advance-pins` | With `--apply`: stage own-organisation submodule pins at upstream main (`git add`, never committed). |
| `--advance-third-party` | With `--advance-pins`: third-party pins too. |
| `--strict-pins` | Absent / uninitialised submodules count as attention. |
| `--own-org ORG` | Own organisation (repeatable). Default: `vasic-digital`, `HelixDevelopment`. |
| `--jobs N` | Parallel fetches. Clamped to `1 .. min(8, cpus/2)`. |
| `--timeout S` | Seconds per network git call (a local call gets `max(S, 60)`); on expiry the call's own process group gets SIGTERM, then SIGKILL if it has not ended 5 s later (never pgid ≤ 1, §11.4.263), the pipes are closed and git is reaped with a 5 s limit; it never applies to a write (see `--write-timeout`); a grandchild that escaped the group and still holds a pipe is not waited for (reading stops as soon as git itself has exited). |
| `--deadline S` | Seconds for the whole run; a call that would start after it is not run: a fetch is reported `not-fetched-deadline`, a local call makes its repository `unresolved`. A write never starts after it; a write that started before it is never ended by it. The final head reads still run after it (at most 10 s each). |
| `--write-timeout S` | Seconds a single write (`merge --ff-only`, `checkout --detach`, `add`) may run (default 3600, a positive integer). Neither `--timeout`, `--deadline` nor a stop signal ends a write. Only this limit does: SIGTERM to the write's process group first (git then removes its own lock files), SIGKILL only if it has not ended 30 s later. Such a write is `write-killed:<op>` (FAILED, blocking); the report records the lock files left (`locks_left`) and the next steps print the recovery (see Safety properties). A smudge filter or a very large checkout can need more than the default. |
| `--max-depth N` | Submodule recursion depth (default 32); cycles are cut. |
| `--out DIR` | Evidence directory. It is resolved (symbolic links followed) and must lie outside the project work tree, and it must be writable: it is created and probed with a real temporary file BEFORE anything else happens; either failure is exit 2 with nothing done. Default `$XDG_CACHE_HOME/helix_sync_upstreams/<project>-<run-id>/` (`~/.cache` when unset), checked the same way (a cache directory that is a link into the project is refused; a relative `XDG_CACHE_HOME` or `HOME` without `--out` is refused). A `sync_report.json` or `sync_report.tsv` already there is replaced only when it is a regular file that this engine wrote; anything else (your own file, a symbolic link, a FIFO, a directory) is refused with exit 2 and left as it is. |
| `--run-id ID` | `[A-Za-z0-9._-]{1,80}`; default `<UTC time>-<pid>`. |
| `--quiet` | Print only repositories that are not current (a `blind`, `not-initialised`, `unresolved` or `failed` one included; only `current` rows are left out). |
| `--interactive` | Ask on `/dev/tty` before fetching, fast-forwarding and staging pins; default answer no. |
| `--non-interactive` | The flags are the consent (default). |

## Run order

1. **Lock** `<git-common-dir>/helix-sync-upstreams.lock` of the root (`fcntl`, `O_NOFOLLOW`, non-blocking: a
   second run over the same root exits 7 `LOCKED` and does nothing; the kernel drops the lock when a run dies).
   After discovery (step 3) and BEFORE any fetch or write, the same lock is taken in the git common directory of
   EVERY repository of the tree; a run rooted at a submodule while a whole-tree run holds that submodule (or the
   other way round) exits 7 before it fetches or changes anything.
2. **Control needle** (§11.4.273): `rev-list --count HEAD ≥ 1` and `HEAD...HEAD == 0 0` on the root. If
   the instrument cannot see that, the run is `BLIND` (exit 6) and no zero is believed.
3. **Discovery**: gitlinks (`git ls-files -s`, mode 160000) of every initialised repository, recursively.
   Each gitlink path is probed with ONE `lstat` (the last component is never followed): `absent`,
   `not-a-directory` (a file or a symbolic link), `uninitialised` (a directory without `.git`), `unreadable`, or a
   repository. A repository is accepted only when `git rev-parse --show-toplevel` answers with exactly its own
   path; a `.git` git cannot read (exit 128: a broken `gitdir:` pointer, an unknown repository extension,
   dubious ownership) or a top level that is not its own path (git walked up to the parent) is a NO ANSWER
   (`blind`), never "not initialised"; its subtree is not discovered.
4. **Fetch** (check / apply, not `--no-fetch`), per remote, in a worker pool, exactly
   `git fetch --no-prune --no-prune-tags --no-recurse-submodules --no-auto-gc --no-tags --refmap= --
   <remote> +refs/heads/*:refs/remotes/<remote>/*` (with `--tags` also the NON-forced
   `refs/tags/*:refs/tags/*`). The explicit refspec and the empty `--refmap=` make git ignore every
   configured refspec (a mirror `+refs/*:refs/*` included), so a fetch writes only
   `refs/remotes/<remote>/*` (and, with `--tags`, new tags); it never deletes a ref (`fetch.prune`,
   `fetch.pruneTags`, `remote.*.prune` and `remote.*.tagOpt` are overridden). A branch the remote no
   longer has is read from `FETCH_HEAD`: its stale `refs/remotes/<remote>/<branch>` is kept (never
   deleted by the engine) and reported `upstream-branch-gone:<remote>`; remove it yourself with
   `git remote prune <remote>` when you mean it.
5. **Measure**: per remote, state of `<remote>/<branch>` against the head before the run; the newest
   upstream main is the target when all remote mains are linearly ordered; per submodule, the pin state.
6. **Integrate** (apply only, pre-order; nothing in a tree whose root is not on `<branch>`): before any
   move, the ignored files of the repository are compared with the target tree, and an ignored file the
   move would overwrite or remove (`secret.env` the target now tracks) blocks the move
   (`ignored-file-would-be-overwritten`, the file is kept). A parent moves first with
   `git merge --ff-only <sha>`; each
   clean, initialised child whose checkout equalled the parent's old gitlink then follows the new gitlink
   (`git checkout --quiet --detach <sha>`); a child checked out on a branch is never detached
   (`follow-skipped:submodule-on-branch`, reason `kept-on-branch:follow-pin`); with `--advance-pins`, pins at
   upstream main are checked out in the submodule and staged in the parent (`git add -- <path>`), except in a
   submodule checked out on a local branch, which is never detached either (`advance-skipped:submodule-on-branch`,
   reason `kept-on-branch:advance-pin`). A child whose new pin is not present and cannot be fetched is `failed`
   (`follow-blocked:new-pin-unfetchable`, exit 1) and stays where it was. After the whole pass, HEAD is read
   again in EVERY initialised repository (`head_after`), whatever path the repository took; a head that cannot
   be read then is a no-answer, never a copy of `head_before`.
   Every write (fast-forward, follow, advance) first re-reads, as its LAST checks before git starts: the
   status and in-progress markers, the ignored files, for a pin the parent's index AND its HEAD tree at that
   path (both must still record the gitlink this run discovered), then HEAD (it must be the commit inspection
   read) and the symbolic ref (a fast-forward needs the same branch, a pin write a detached HEAD). Any change
   refuses the write (`blocked:head-changed-before-write`, `blocked:branch-changed-before-write`,
   `blocked:parent-index-changed`; `unresolved:<check>` when a re-read gave no answer). After the write, HEAD
   and the symbolic ref are read again: HEAD not at the target, or a changed branch, is `failed`. A head that
   moved during the run but not to what this run wrote is reported `head-changed-during-run` (attention).
   What remains is the window of a few milliseconds between these reads and git's own ref lock: a change made
   inside it is reported afterwards, not prevented. A submodule that is itself on
   `<branch>` is fast-forwarded like a root; its parent then shows a modified gitlink, which is reported
   (`gitlink-modified:<path>`, attention) and never staged without `--advance-pins`.
7. **Evidence** written atomically; verdict printed.

## States and reasons

**Remote state** (`repos[].remotes[].state`): `equal`, `behind`, `ahead`, `diverged` (relative to the head
before the run), `no-main` (the remote has no `<branch>`), `unreachable` (fetch failed or timed out),
`not-fetched-deadline` (the run deadline passed before its fetch), `not-fetched-interrupted` (a stop signal
arrived before its fetch answered: never `unreachable`), `unknown` (no read of the remote answered),
`invalid-name` (never passed to git).
`fetch` is `ok`, `failed`, `timeout`, `deadline`, `no-answer` (killed by a signal, an undeclared exit status:
the repository is also `blind`) or `tag-rejected` (git refused to move an existing tag that changed upstream;
the branches were fetched, the tag is kept, and the repository needs attention). `fetch_failure` labels a
failed fetch: `timeout`, `deadline`, `refused-by-engine`, `git-not-runnable`, `tag-rejected`, `auth`,
`not-found`, `network`, `other`.

**Upstream state** (`upstream_state`): `linear` (one newest main exists), `upstreams-diverged`, `none`.

**Local vs target** (`local_vs_target`): `equal`, `behind`, `ahead`, `diverged`, `no-target`, `unknown`.

**Pin state** (`pin.state`, §11.4.233(G), §11.4.288(D)): `at-main`, `behind-main`, `on-main-not-newest`,
`not-on-main`, `not-on-any-remote`, `unfetchable`, `absent`, `uninitialised`, `not-a-directory` (a file or a
symbolic link where the submodule should be), `cycle` (the same repository, by its real path, reached a second
time: never inspected twice), `unsafe-path` (a gitlink path the engine will not use: leading `-`, a backslash,
`..`, an absolute path; reported, never omitted), `outside-parent` (a directory on the way to the submodule is a
symbolic link that leaves the parent's work tree; not inspected),
`unreadable` (see Discovery: always a no-answer); `pin.checkout` is
`at-pin` or `drifted`. "On main" means contained in exactly `refs/remotes/<remote>/<branch>` of a
remote that still has `<branch>`; `refs/remotes/<remote>/feature/main` does not count.

**Result** (`result`): `current`, `behind`, `updated`, `attention`, `blind`, `unresolved`, `failed`,
`not-initialised`, `interrupted` (only calls that a stop signal ended or refused). Every git call declares which exit statuses are an answer for it (for example 0 and 1
for `merge-base --is-ancestor`) and, where it reads a value, the shape that value must have. A call that
ends otherwise gives NO ANSWER and is listed in `unresolved: ["<subcommand>:<why>"]`, `why` being
`signal:<n>`, `rc:<n>` (an undeclared exit status), `malformed-output` (exit 0, wrong shape), `refused`,
`not-runnable`, `fetch-head-unreadable`, `output-too-large` (more than 128 MiB on stdout), `interrupted` (a stop
signal), `timeout` or `deadline`; also `lstat:unreadable` (a path or `.git` the
engine could not `lstat`), `rev-parse:not-own-toplevel` and, in `--apply` only, `rev-parse:head-after-not-read`
(defence in depth: the integration pass reads every head, so this entry means the pass did not finish). Such a repository is `blind`, or
`unresolved` when every such call only ran out of time; either way nothing about it is concluded and the
engine writes nothing in it (not even a follow of its parent's new gitlink). `blind` comes before
`failed`: a failure judged on a call that gave no answer is not an answer either. `updated` needs both
heads read and NO blocking reason after the move: a repository that moved (for example it followed its
parent) and is then blocked (its own remote unreachable) is `attention`, with `moved: true` and
`head_after` its real head.

**Reasons** (any one makes the repository `attention`): `dirty-tree`, `in-progress:<MERGE_HEAD|…>` (a marker
the engine cannot read counts as in progress: `<name>?unreadable`),
`unreachable:<remote>`, `invalid-remote-name`, `upstreams-diverged`, `root-not-on-<branch>`,
`no-upstream-<branch>` (no remote has `<branch>`, or there is no remote: never `current`),
`tag-rejected:<remote>`, `local-ahead`, `local-diverged`, `pin-unfetchable`, `pin-not-on-any-remote`, `pin-not-on-main`,
`pin-checkout-drifted`, `head-unreadable` (HEAD could not be read as a full object id: unborn, an error,
empty or odd output; the repository is never integrated), `ignored-file-would-be-overwritten`, `gitlink-modified:<path>`,
`upstream-branch-gone:<remote>`, `kept-on-branch:<follow-pin|advance-pin>` (a submodule on a local branch was
left on it), `gitlink-staged:<path>` (the index records a gitlink for `<path>` that HEAD's tree does not: a pin
someone staged and did not commit, an earlier `--advance-pins` run included; it is never written over and does not
hold back the rest of the repository), `head-changed-during-run`, `write-blocked:<why>`,
`write-killed:<op>`, `write-interrupted-earlier:<op>` with `dirty-tree-since-write-interrupted` /
`in-progress-since-write-interrupted:<name>` (an earlier run's write did not end normally),
`not-followed:update-<none|merge|rebase|command|other>`, always
`pin-not-a-directory`, `pin-cycle`, `pin-unreadable`, `pin-unsafe-path`, `pin-outside-parent`, and with `--strict-pins`
`pin-absent`, `pin-uninitialised`.

**Actions** (`actions[]`): `fast-forward`, `follow-pin`, `advance-pin`, or `none` with a `why`, for example
`follow-skipped:drifted-or-dirty`, `follow-skipped:submodule-on-branch`, `advance-skipped:submodule-on-branch`,
`follow-skipped:index-differs`,
`follow-blocked:new-pin-unfetchable`, `blocked:tree-changed-before-write`, `blocked:parent-index-changed`,
`blocked:head-changed-before-write`, `blocked:branch-changed-before-write`, `interrupted`,
`ignored-file-would-be-overwritten`, `unresolved:<check>` (a re-check before the write gave no answer).

## Exit codes and verdicts

| Exit | Verdict | When |
|---|---|---|
| 0 | `CURRENT` / `APPLIED` | Nothing behind, nothing needs attention. |
| 1 | `FAILED` | An integration step failed, a write was ended by its `--write-timeout` (`write-killed:<op>`), or a run lock could not be opened or taken for a reason that is NOT another run (a read-only git directory: `cannot open the run lock`; a refused flock, for example ENOLCK: `cannot take the run lock`); nothing is fetched or changed in that last case. |
| 2 | usage | Bad arguments; `--out` (or the default evidence directory) inside the work tree, not writable when the run starts, or holding a report file this engine did not write; a relative cache directory; no terminal for `--interactive`. Nothing was done. Evidence that cannot be written at the END of a run (after a write) is exit 1, never 2; every move is then printed. |
| 3 | `UPDATES-AVAILABLE` | Something is behind (check, dry-run, or still behind after apply: a declined prompt, or a pin without `--advance-pins`). |
| 4 | `ATTENTION` | At least one reason above. |
| 5 | `INCONCLUSIVE` | A local git call ran out of time (`--timeout`) or a call would have started after the `--deadline`, and nothing else gave no answer; those repositories are `unresolved`. Re-run with a larger `--timeout` / `--deadline`. |
| 6 | `BLIND` | The control needle failed, the root or its git directory could not be read (also: the start directory holds a `.git` git cannot read, exit 128), a submodule could not be read, or a git call gave no answer for any other reason (killed by a signal, an exit status its call site does not declare, malformed output, refused, not runnable); those repositories are `blind`. Investigate before re-running. |
| 7 | `LOCKED` | Another sync run holds the lock of this root or of a repository of this tree; nothing was fetched or changed. |
| 8 | `INTERRUPTED` | A stop signal (SIGTERM, SIGINT, SIGHUP) arrived. Calls in flight that only read were stopped; a write in flight was finished, never cut (a stop signal never ends a write; only `--write-timeout` does); the heads were read again (at most 10 s each; a second signal stops that too) and the report says what moved. Re-run. |

Precedence: `INTERRUPTED` > `BLIND` > `FAILED` > `INCONCLUSIVE` > `ATTENTION` > `UPDATES-AVAILABLE` > `CURRENT`.
`sync_step_lib.sh` maps 0/3/4/1/5/7/6/8 to `CURRENT`/`UPDATES-AVAILABLE`/`ATTENTION`/`FAILED`/
`INCONCLUSIVE`/`LOCKED`/`BLIND`/`INTERRUPTED`; any other code (2 included) reads as `BLIND`.

## Evidence

`sync_report.json` (schema `helix.sync_upstreams/1`, directory mode 0700): `run_id`, `mode`, `branch`,
`flags`, `consent`, `consent_source`, `root_abs`, `out_dir`, `started`, `ended`, `duration_s`, `jobs`,
`git_calls`, `control_needle`, `verdict`, `exit_code`, `counts`, `repos[]` (path, kind, depth,
initialised, branch, head_before, head_after, target, remotes, upstream_state, local_vs_target, pin,
own_org, ssh, result, reasons, actions, unresolved, ignored_clobber, gitlink_modified), `next_steps`, `canonical_sha256`.

`sync_report.tsv`: one header line
`path kind depth initialised branch head_before head_after target upstream_state local_vs_target pin_state pin_behind_main own_org result reasons remotes`
and one row per repository.

`canonical_sha256` hashes the report without the time-, path- and process-dependent fields
(`started`, `ended`, `duration_s`, run id, output paths, call counts). Identical repository states give
an identical hash (§11.4.50); the test suites check this with N=3 runs.

## Integration points

| Where | How |
|---|---|
| `scripts/setup.sh` | `--sync-upstreams=off|check|apply|ask` or `CONSTITUTION_SYNC_UPSTREAMS`; default `off` (hint only). `ask` → `--interactive`; `check` / `apply` → `--non-interactive`. Only an `apply` failure (or an `apply` run that was interrupted) fails setup. `--check-only` exits before this step. |
| `scripts/post_update_hook.sh` STEP 5c | `CONSTITUTION_SYNC_CHECK=offline` (default, `--check --no-fetch`), `fetch` (`--check`), `off`. Read-only; never fails the hook; `BLIND`, `INCONCLUSIVE` and `INTERRUPTED` are warnings. |
| Scheduling | `scripts/sync/examples/` (not installed). |

## Safety properties

* The engine starts a process at ONE place only (`proc_run_git`), which puts every argument list through
  one allow-list (`check_git_args`) before it starts git, and sends a signal at ONE place only
  (`proc_kill_group`: only the child's OWN group, `os.getpgid(pid) == pid`, and never pgid ≤ 1). Write
  subcommands are exactly the one fetch shape above, `merge --ff-only <sha>`, `checkout --quiet --detach
  <sha>` and `add -- <relative path>`. Refused: push, commit, reset, rebase, `-s ours`, `merge --ff` /
  `--no-ff` / `--squash`, any other refspec, `--prune`, `--force`, transport helpers (`::`),
  `--upload-pack=`, config writes, remote edits.
* Every git call runs as `git -C <repo> -c core.hooksPath=/dev/null -c core.fsmonitor=false -c
  submodule.recurse=false -c gc.auto=0 -c maintenance.auto=false -c merge.autoStash=false -c
  protocol.ext.allow=never -c fetch.prune=false -c fetch.pruneTags=false -c fetch.recurseSubmodules=false
  -c core.askPass= -c credential.interactive=false --no-optional-locks <args>`: no hook (a tracked `.githooks`
  with `core.hooksPath` included) and no fsmonitor of the repository runs. A `-c` pair beats every config file,
  but NOT `GIT_ALLOW_PROTOCOL` or `GIT_ASKPASS` in the environment (measured, git 2.53:
  `docs/qa/sync_upstreams_2026_11_13_r5/ground_truth/`), so the engine drops the first and sets the second
  empty: an `ext::` URL (also one produced by `url.<x>.insteadOf`) is refused whatever the caller's
  environment or the repository's config says.
* Credentials (§11.4.10): URL userinfo is stripped (for every `scheme://` the token runs to the END OF THE
  LINE, with no length limit, and everything up to its LAST `@` goes; a later `@` on the same line removes
  more, never less), the userinfo of every configured remote URL is remembered before the first fetch and
  each remembered piece of 8 characters or more is removed wherever it appears (git stderr that quotes it
  without its URL included), `Authorization:` header values and token-shaped strings are replaced with
  `[REDACTED]`, report KEYS are redacted as well as values, a usage error and an unexpected exception print
  redacted text. No askpass program runs and nothing reads the terminal: `GIT_TERMINAL_PROMPT=0`,
  `GIT_ASKPASS` set EMPTY (it beats `core.askPass`), `core.askPass` pinned empty, `SSH_ASKPASS` dropped and
  `SSH_ASKPASS_REQUIRE=never`, `GCM_INTERACTIVE=never`, `credential.interactive=false`, ssh `BatchMode=yes`,
  every call in a new session without a controlling terminal and with stdin `/dev/null`. A configured
  `credential.helper` still runs (that is how a user authenticates; git runs it even with
  `credential.interactive=false`). Ambient `GIT_DIR`-class variables, `GIT_EXEC_PATH`, `GIT_SSH`,
  `GIT_PROXY_COMMAND`, `GIT_ALLOW_PROTOCOL`, `GIT_PROTOCOL_FROM_USER`, `GIT_SSL_NO_VERIFY`, every `GIT_TRACE*`
  variable (`GIT_TRACE2*` included), `GIT_CURL_VERBOSE`, `GIT_REDACT_COOKIES`, `GIT_CONFIG_PARAMETERS`,
  `GIT_CONFIG_COUNT` and `GIT_CONFIG_KEY_*` / `GIT_CONFIG_VALUE_*` are dropped. `GIT_SSH_COMMAND` from the
  caller's environment is NOT honoured: the engine sets its own (`ssh -o BatchMode=yes -o ConnectTimeout=10`).
  A repository that sets `core.sshCommand` keeps it (`repos[].ssh = "core.sshCommand"`; the call still has no
  terminal and `SSH_ASKPASS_REQUIRE=never`). The full table, with the ground truth of each row, is
  `docs/qa/sync_upstreams_2026_11_13_r5/class_inventory.md`, class (d).
* Fetched code is never executed: no hook or fsmonitor runs, and the post-update hook command is printed,
  not run (a clean/smudge filter or diff driver configured by the user is the stated exception, see below).
* Every merge, checkout and add runs in ONE guarded writer (`write_git`), which first refuses a repository
  that had any call with no answer in this run, then re-reads the status (it must answer and be empty) and
  the in-progress markers, then checks that no ignored file would be overwritten or removed, for a pin
  advance that the parent's index and HEAD tree still record the gitlink this run discovered, then that HEAD
  and the symbolic ref are what inspection read (§11.4.84), and verifies the write afterwards (see Run order).
* What a remote or a repository sends is bounded: a call's stdout is read in 64 KiB pieces up to 128 MiB
  (more is no answer, the call is killed); of stderr only the last 64 KiB is kept, without its partial first
  line; `FETCH_HEAD` is read up to 64 MiB; redaction is linear in the length of the text (measured 2026-11-14 on
  the development host, best of 5: at most 0.037 s for a 256 KiB line and 0.118 s for a 1 MiB line;
  `docs/qa/sync_upstreams_2026_11_13_r5/green/redaction_timing.txt`; other hosts UNCONFIRMED). A line with
  `scheme://` loses everything up to its last `@`, which can remove more than the userinfo (fail-safe). Per-call timeout, run deadline, depth limit, `jobs` ceiling ≤ 8 (§12.6, §12.12).
* Stop signals: SIGTERM, SIGINT and SIGHUP are handled. The handler only sets a flag; a call that only reads is
  stopped (its own process group gets SIGTERM, then SIGKILL after 5 s, §11.4.263), no new call starts, a write in flight is finished, the
  heads are read again and the report is written (exit 8). A second signal also stops those final reads.
  SIGKILL (or the kernel's OOM killer) cannot be handled: a git call in flight then runs on in its own
  session until git's own timeouts end it (the example systemd unit's default `KillMode=control-group` kills
  it with the unit).
* Writes and their limit (review round 6): before each write the engine writes a marker
  `helix-sync-upstreams.write-in-progress` (run id, operation, target) into the repository's git directory and
  removes it when git ended the write with a status. A write is ended only by `--write-timeout`, SIGTERM first
  (measured: git removes `index.lock` on SIGTERM, not on SIGKILL), SIGKILL 30 s later; it is then
  `write-killed:<op>`, FAILED. A marker found by a later run means a write did not end normally (its limit,
  SIGKILL, OOM, power loss): leftovers in that repository are reported `write-interrupted-earlier:<op>`,
  `dirty-tree-since-write-interrupted`, `in-progress-since-write-interrupted:<name>` (blocking, never blamed on
  you); with no leftovers an `--apply` run removes the marker (`notes`: `write-marker-cleared:…`). A git lock
  left on an otherwise clean tree (what a SIGKILLed write leaves: `index.lock`) is such a leftover too. A write
  that cannot start gets no marker, and keeps none (review round 7): no marker is written when a stop signal or
  the run deadline already refuses the write, and the marker is removed again when no git process was started
  (the refusal came a moment later, or git could not be started); a marker that was created but could not be
  written (for example a full disk) is removed again, an earlier run's marker never. Such a write left nothing,
  so your later edits are never reported as its leftovers. Review round 8: the marker of each git directory is a
  state machine for the run (`none`, `write-in-progress`, `cleared`, `write-killed`, `write-interrupted`,
  `earlier-run-marker`). A marker that is already there is never overwritten (it is created exclusively) and
  never removed by a write that did not create it; a write git starts only while the marker on disk carries
  that write's own id. A git directory whose earlier write in the same run was killed or interrupted, or that
  holds a marker of an earlier run, a marker of unknown origin, or a lock (`index.lock` included), takes no
  further write in that run: the write is reported `blocked:earlier-write-unresolved:<state>`,
  `blocked:write-marker-present`, `blocked:in-progress:<name>` or `blocked:write-marker-unwritable`. For
  `--advance-pins` the parent's git directory is checked BEFORE the submodule is moved
  (`blocked:parent-<reason>`), so a sibling whose pin cannot be staged is never moved. Recovery
  of a write-killed repository, printed in the next steps: make sure no git process runs in it; look at
  `git status`; remove a stale `index.lock` only when no git process runs; save what is there with
  `git stash push --include-untracked -m helix-sync-write-killed`; re-run with a larger `--write-timeout`.
* Git locks and half-applied writes (review round 9). Before a write, and before an earlier run's marker is
  removed, the engine checks every lock file the write's own git subcommand takes (measured with git 2.53 by
  tracing the write; `docs/qa/sync_upstreams_2026_11_15_r9/ground_truth/`). `merge --ff-only` takes `index.lock`, `HEAD.lock`,
  `ORIG_HEAD.lock`, `AUTO_MERGE.lock` in the repository's git directory, and `packed-refs.lock`,
  `refs/heads/<branch>.lock` and `reftable/tables.list.lock` in the common directory. `checkout --detach`
  takes the same set without `ORIG_HEAD.lock` and without the branch lock. `add` takes `index.lock` only. In
  a linked worktree the first group is in `<common>/worktrees/<id>/` and the second in the common directory;
  these are reported as `common:<name>`. Measured by planting a stale lock: `HEAD.lock` lets
  `merge --ff-only` and `checkout --detach` rewrite the index and work tree before they fail with status 128,
  and the branch lock does the same to `merge --ff-only`. A stale `packed-refs.lock` or `AUTO_MERGE.lock` does
  not stop git; the engine refuses on them anyway, because a present lock may belong to a git process that is
  running now. The engine now refuses such a write before it
  starts (`blocked:in-progress:<name>`). When a write fails with any status, the engine also compares HEAD
  and the index (`git ls-files -s -z`) with their state before the write. If either changed, it reports
  `write-left-changes:<op>`, FAILED, and keeps the marker (`write-interrupted`). The next run then attributes
  the leftovers to the write, never to you. An earlier marker that cannot be removed (for example the git
  directory is not writable) is kept and reported `write-marker-kept:cannot-remove:<reason>`; it is never
  reported as cleared. A non-regular object at the marker path (FIFO, directory, socket, symbolic link,
  device) is reported `write-marker-path-not-a-file:<kind>`, blocks writes and is never opened, read or
  removed. Every engine read, exclusive create, removal and lock open goes through one path-access layer
  (`path_kind`, `fs_read`, `fs_create_excl`, `fs_remove`, `fs_open_lock`). Reads and the run-lock open use
  `O_NOFOLLOW | O_NONBLOCK` and accept only a regular file (checked again with `fstat` on the open
  descriptor), so a FIFO cannot hang any mode, `--check` included. The exclusive create uses
  `O_EXCL | O_NOFOLLOW`, which never opens an object that is already there. `fs_remove` unlinks regular files
  only.
* Staged gitlinks of the repository being moved (review round 6): a fast-forward or pin write is refused
  (`blocked:gitlink-staged-would-change`) when the index stages a gitlink that differs from HEAD and the
  target commit would change that path; an unanswered read of the staged gitlinks is `unresolved:staged-gitlinks`.
* Submodule update strategy (review round 6): a pin is advanced or followed only for a submodule whose
  `submodule.<name>.update` (read from `.gitmodules` and the repository config) is `checkout`; `none`,
  `merge`, `rebase` or a `!command` give `not-followed:update-<strategy>` (attention) and nothing is checked out.
* Locks: one per repository of the tree (see Run order), never per project only.

## Tests and gate

`bash tests/sync/run_all.sh` (add `--quick` to skip chaos, performance, robustness and mutations).
`tests/sync/test_robustness.sh` (round 5) drives the real engine against real repositories for the
round-4 findings: user commits, branch switches and staged pins made WHILE a run is in flight (a test-only
shim plays the user at a chosen git call), stop signals during a fetch and during a write, a 256 KiB stderr
line and 160 MiB of stderr, every askpass route, `ext::` through the environment and through repository
config, `GIT_PROTOCOL_FROM_USER`, trace variables, header and short-secret redaction, control characters,
blocking reasons, locks (symbolic link, overlapping roots), the evidence directory (unwritable, lost, inside
the tree, relative) and unsafe or outside-parent gitlink paths; `--only a,b` runs named checks. Suites: unit,
integration, end-to-end, full automation (setup and post-update hook), security, stress/chaos,
performance, determinism (N=3), UI (pseudo-terminal), and the engine's paired-mutation suite. The gate
`CM-SYNC-UPSTREAMS-FF-ONLY` checks the engine statically (AST: an import and module-attribute allow-list,
no dynamic access such as `getattr` / `eval`, `subprocess.Popen` and the other spawn names only inside
`proc_run_git` and only called, `os.killpg` only inside `proc_kill_group`, with `pgid` bound once as
`pgid = os.getpgid(p.pid)` and the guard exactly the three terms `isinstance(pgid, int)`, `pgid > 1` and
`pgid == p.pid` joined by `and` (any order, nothing else), the one `Popen` passing
`start_new_session=True`, both functions
referenced exactly once, literal allow-listed arguments and a declared `ok=` tuple at every git call site)
and at runtime (for every argument shape the engine uses: the exact argv with every safe `-c` pair; the
fetch shape; `git_env` drops every config-injecting variable; adversarial credential shapes are redacted;
`proc_run_git` refuses a forbidden shape before any process exists; a table of refused and accepted
shapes, and a call-site oracle table compared with the engine's call sites as a multiset), with its own
mutation test (83 cases). `tests/sync/test_faults.sh` makes every git call of a
full `--apply` run give no answer, one call per run, and checks that the run is `BLIND` and that the
repository concerned (and everything below it) did not move; it also holds every report's `moved` field
against the disk (in the control run the moved set must equal the set of repositories whose HEAD changed; in a
fault run a repository reported as moved must have a changed HEAD); the AST lister inside `tests/sync/test_faults.sh` lists the call sites
from the engine's AST so a new call cannot hide from it. `tests/sync/test_mutations.py` holds the
standing mutant table (the fixers' M-series, the round-2 reviewer's K01–K17 and R1–R6, the round-3 reviewer's
X01–X07 and X02b, verbatim, the round-4 fixer's N01–N25, the round-4 reviewer's V01–V24 and the round-5
fixer's P01–P34; a suite `robustness:<a,b>` runs the named live checks); `--gate-only` and `--no-gate` run the table
against the static gate alone and against the behavioural suites alone. The gate's `--print-sites` prints its
call-site oracle (function, argument list, `ok` set, output shape, meaning of exit 128), which the fault suite
reads to inject the real status 128 at every site.

## Honest boundary

The tests run real git against real bare repositories in scratch directories (`file://` and a loopback
port that refuses); no network remote and no forge is contacted, so this is gate-logic / unit-class
evidence, not proof against a real forge (§11.4.289). A clean or smudge filter or a diff driver the
user configured is not disabled: git runs a clean filter while `status` compares the work tree (so
also during `--check`) and a smudge filter while `checkout` or `merge --ff-only` writes files. A
`textconv`, diff driver or merge driver never runs: the engine runs no diff and a fast-forward merges no
content. A clean or smudge filter is the user's own configuration (fetched content cannot set config), so
a hostile filter is out of scope; the same holds for `remote.<name>.uploadpack` (git honours the repository
value even when a `-c` pair names another program: measured, D24, so it cannot be pinned), `core.gitProxy`
and `credential.helper`, which run as configured, and for `http.sslVerify=false` in the user's config. A
fetch is not limited in the disk it takes (git's own). Evidence directories under `~/.cache/helix_sync_upstreams/` are never pruned by the engine
(open item: retention policy). Ignored files are listed one by one (`git ls-files --others
--ignored`), which costs time in a tree with very many ignored files. A remembered secret shorter than 8
characters is removed only where it appears inside a URL (userinfo) or in a token or header shape, not
when git quotes it alone (a short value would also match ordinary words). A child whose parent moves to a
pin the child cannot fetch is reported `failed` after the parent has already moved; holding the parent
back until every child can follow is an open design question, not implemented. A follow-pin and an advance-pin read
`submodule.<name>.update` (review round 6, see Safety properties). A stdout closed before the run ends (a pipe into `true`)
was measured: no traceback, both report files written, but the exit status is Python's 120 (not one of the
engine's codes; a caller reads it as `BLIND`) with `BrokenPipeError` on stderr (open item `SYNC-R5-OPEN-3`,
`docs/qa/sync_upstreams_2026_11_13_r5/green/sigpipe_probe.txt`). Behaviour against real forges (ssh keys, rate limits, large repositories) is
UNCONFIRMED until the operator runs it. The engine reports; it does not decide whether a third-party
pin should advance.
