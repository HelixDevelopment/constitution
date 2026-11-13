# Sync-all-upstreams manual — `scripts/sync/sync_all_upstreams.sh`

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-11-12 |
| Last modified | 2026-11-13T12:00:00Z |
| Status | draft (pending independent review) |
| Status summary | Reference for every option, state, reason, exit code, report field, integration point and safety property of the sync-all-upstreams engine. |
| Authority | Constitution §2.1, §11.4.10, §11.4.37, §11.4.50, §11.4.71, §11.4.84, §11.4.113, §11.4.164, §11.4.233(G), §11.4.263, §11.4.273, §11.4.288(D), §12. The canonical text wins where this manual and the constitution disagree. |
| Scope | Universal (§11.4.17); consumed by reference. |
| Issues | none |
| Issues summary | — |
| Fixed | revision 2: review round 2 (NO-GO) fixes F1–F13, N3; revision 3: review round 2 of the fixes (NO-GO) I-1–I-4, S-1, m-1–m-5, n-1–n-6 |
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
| `--timeout S` | Seconds per network git call (a local call gets `max(S, 60)`); on expiry the call's own process group is killed (never pgid ≤ 1, §11.4.263) and the call returns after at most 7 more seconds (2 s to collect its output, then at most 5 s to reap it) even when an escaped grandchild still holds its pipe. |
| `--deadline S` | Seconds for the whole run; a call that would start after it is not run: a fetch is reported `not-fetched-deadline`, a local call makes its repository `unresolved`. |
| `--max-depth N` | Submodule recursion depth (default 32); cycles are cut. |
| `--out DIR` | Evidence directory; must be outside the project work tree. Default `$XDG_CACHE_HOME/helix_sync_upstreams/<project>-<run-id>/` (`~/.cache` when unset). |
| `--run-id ID` | `[A-Za-z0-9._-]{1,80}`; default `<UTC time>-<pid>`. |
| `--quiet` | Print only repositories that are not current. |
| `--interactive` | Ask on `/dev/tty` before fetching, fast-forwarding and staging pins; default answer no. |
| `--non-interactive` | The flags are the consent (default). |

## Run order

1. **Lock** `<git-common-dir>/helix-sync-upstreams.lock` (`fcntl`; a second run exits 7 `LOCKED` and
   does nothing; the kernel drops the lock when a run dies).
2. **Control needle** (§11.4.273): `rev-list --count HEAD ≥ 1` and `HEAD...HEAD == 0 0` on the root. If
   the instrument cannot see that, the run is `BLIND` (exit 6) and no zero is believed.
3. **Discovery**: gitlinks (`git ls-files -s`, mode 160000) of every initialised repository, recursively.
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
   (`follow-skipped:submodule-on-branch`); with `--advance-pins`, pins at upstream main are checked out
   in the submodule and staged in the parent (`git add -- <path>`). A submodule that is itself on
   `<branch>` is fast-forwarded like a root; its parent then shows a modified gitlink, which is reported
   (`gitlink-modified:<path>`, attention) and never staged without `--advance-pins`.
7. **Evidence** written atomically; verdict printed.

## States and reasons

**Remote state** (`repos[].remotes[].state`): `equal`, `behind`, `ahead`, `diverged` (relative to the head
before the run), `no-main` (the remote has no `<branch>`), `unreachable` (fetch failed or timed out),
`not-fetched-deadline` (the run deadline passed before its fetch), `invalid-name` (never passed to git).
`fetch` is `ok`, `failed`, `timeout`, `deadline`, `no-answer` (killed by a signal, an undeclared exit status:
the repository is also `blind`) or `tag-rejected` (git refused to move an existing tag that changed upstream;
the branches were fetched, the tag is kept, and the repository needs attention). `fetch_failure` labels a
failed fetch: `timeout`, `deadline`, `refused-by-engine`, `git-not-runnable`, `tag-rejected`, `auth`,
`not-found`, `network`, `other`.

**Upstream state** (`upstream_state`): `linear` (one newest main exists), `upstreams-diverged`, `none`.

**Local vs target** (`local_vs_target`): `equal`, `behind`, `ahead`, `diverged`, `no-target`, `unknown`.

**Pin state** (`pin.state`, §11.4.233(G), §11.4.288(D)): `at-main`, `behind-main`, `on-main-not-newest`,
`not-on-main`, `not-on-any-remote`, `unfetchable`, `absent`, `uninitialised`; `pin.checkout` is
`at-pin` or `drifted`. "On main" means contained in exactly `refs/remotes/<remote>/<branch>` of a
remote that still has `<branch>`; `refs/remotes/<remote>/feature/main` does not count.

**Result** (`result`): `current`, `behind`, `updated`, `attention`, `blind`, `unresolved`, `failed`,
`not-initialised`. Every git call declares which exit statuses are an answer for it (for example 0 and 1
for `merge-base --is-ancestor`) and, where it reads a value, the shape that value must have. A call that
ends otherwise gives NO ANSWER and is listed in `unresolved: ["<subcommand>:<why>"]`, `why` being
`signal:<n>`, `rc:<n>` (an undeclared exit status), `malformed-output` (exit 0, wrong shape), `refused`,
`not-runnable`, `fetch-head-unreadable`, `timeout` or `deadline`. Such a repository is `blind`, or
`unresolved` when every such call only ran out of time; either way nothing about it is concluded and the
engine writes nothing in it (not even a follow of its parent's new gitlink). `blind` comes before
`failed`: a failure judged on a call that gave no answer is not an answer either. `updated` needs both
heads read.

**Reasons** (any one makes the repository `attention`): `dirty-tree`, `in-progress:<MERGE_HEAD|…>`,
`unreachable:<remote>`, `invalid-remote-name`, `upstreams-diverged`, `root-not-on-<branch>`,
`no-upstream-<branch>` (no remote has `<branch>`, or there is no remote: never `current`),
`tag-rejected:<remote>`, `local-ahead`, `local-diverged`, `pin-unfetchable`, `pin-not-on-any-remote`, `pin-not-on-main`,
`pin-checkout-drifted`, `head-unreadable` (HEAD could not be read as a full object id: unborn, an error,
empty or odd output; the repository is never integrated), `ignored-file-would-be-overwritten`, `gitlink-modified:<path>`,
`upstream-branch-gone:<remote>`, and with `--strict-pins` `pin-absent`, `pin-uninitialised`.

**Actions** (`actions[]`): `fast-forward`, `follow-pin`, `advance-pin`, or `none` with a `why`, for example
`follow-skipped:drifted-or-dirty`, `follow-skipped:submodule-on-branch`, `follow-skipped:index-differs`,
`follow-blocked:new-pin-unfetchable`, `blocked:tree-changed-before-write`, `blocked:parent-index-changed`,
`ignored-file-would-be-overwritten`, `unresolved:<check>` (a re-check before the write gave no answer).

## Exit codes and verdicts

| Exit | Verdict | When |
|---|---|---|
| 0 | `CURRENT` / `APPLIED` | Nothing behind, nothing needs attention. |
| 1 | `FAILED` | An integration step failed. |
| 2 | usage | Bad arguments, `--out` inside the work tree, no terminal for `--interactive`, evidence not writable. |
| 3 | `UPDATES-AVAILABLE` | Something is behind (check, dry-run, or still behind after apply: a declined prompt, or a pin without `--advance-pins`). |
| 4 | `ATTENTION` | At least one reason above. |
| 5 | `INCONCLUSIVE` | A local git call ran out of time (`--timeout`) or a call would have started after the `--deadline`, and nothing else gave no answer; those repositories are `unresolved`. Re-run with a larger `--timeout` / `--deadline`. |
| 6 | `BLIND` | The control needle failed, the root or its git directory could not be read, or a git call gave no answer for any other reason (killed by a signal, an exit status its call site does not declare, malformed output, refused, not runnable); those repositories are `blind`. Investigate before re-running. |
| 7 | `LOCKED` | Another sync run holds the lock; nothing was done. |

Precedence: `BLIND` > `FAILED` > `INCONCLUSIVE` > `ATTENTION` > `UPDATES-AVAILABLE` > `CURRENT`.
`sync_step_lib.sh` maps 0/3/4/1/5/7/6 to `CURRENT`/`UPDATES-AVAILABLE`/`ATTENTION`/`FAILED`/
`INCONCLUSIVE`/`LOCKED`/`BLIND`; any other code (2 included) reads as `BLIND`.

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
| `scripts/setup.sh` | `--sync-upstreams=off|check|apply|ask` or `CONSTITUTION_SYNC_UPSTREAMS`; default `off` (hint only). `ask` → `--interactive`; `check` / `apply` → `--non-interactive`. Only an `apply` failure fails setup. `--check-only` exits before this step. |
| `scripts/post_update_hook.sh` STEP 5c | `CONSTITUTION_SYNC_CHECK=offline` (default, `--check --no-fetch`), `fetch` (`--check`), `off`. Read-only; never fails the hook; `BLIND` and `INCONCLUSIVE` are warnings. |
| Scheduling | `scripts/sync/examples/` (not installed). |

## Safety properties

* The engine starts a process at ONE place only (`proc_run_git`), which puts every argument list through
  one allow-list (`check_git_args`) before it starts git, and sends a signal at ONE place only
  (`proc_kill_group`, never pgid ≤ 1). Write
  subcommands are exactly the one fetch shape above, `merge --ff-only <sha>`, `checkout --quiet --detach
  <sha>` and `add -- <relative path>`. Refused: push, commit, reset, rebase, `-s ours`, `merge --ff` /
  `--no-ff` / `--squash`, any other refspec, `--prune`, `--force`, transport helpers (`::`),
  `--upload-pack=`, config writes, remote edits.
* Every git call runs as `git -C <repo> -c core.hooksPath=/dev/null -c core.fsmonitor=false -c
  submodule.recurse=false -c gc.auto=0 -c maintenance.auto=false -c merge.autoStash=false -c
  protocol.ext.allow=never -c fetch.prune=false -c fetch.pruneTags=false -c fetch.recurseSubmodules=false
  --no-optional-locks <args>`: no hook (a tracked `.githooks` with `core.hooksPath` included) and no
  fsmonitor of the repository runs.
* Credentials (§11.4.10): URL userinfo is stripped, token-shaped strings are replaced with `[REDACTED]`,
  git never prompts (`GIT_TERMINAL_PROMPT=0`, ssh `BatchMode=yes`, every call in a new session without
  a controlling terminal), ambient `GIT_DIR`-class variables are dropped. A repository that sets
  `core.sshCommand` keeps it (`repos[].ssh = "core.sshCommand"`; it still cannot prompt).
* Fetched code is never executed: no hook or fsmonitor runs, and the post-update hook command is printed,
  not run (a clean/smudge filter or diff driver configured by the user is the stated exception, see below).
* Every merge, checkout and add runs in ONE guarded writer (`write_git`), which first refuses a repository
  that had any call with no answer in this run, then re-reads the status (it must answer and be empty) and
  the in-progress markers, then checks that no ignored file would be overwritten or removed, and for a pin
  advance that the parent's index still records the gitlink this run discovered (§11.4.84).
* Bounded: per-call timeout, run deadline (a call that would start after it is not run), depth limit,
  `jobs` ceiling ≤ 8 (§12.6, §12.12); a grandchild that escapes the call's process group delays the
  call's return by at most 7 seconds.

## Tests and gate

`bash tests/sync/run_all.sh` (add `--quick` to skip chaos, performance and mutations). Suites: unit,
integration, end-to-end, full automation (setup and post-update hook), security, stress/chaos,
performance, determinism (N=3), UI (pseudo-terminal), and the engine's paired-mutation suite. The gate
`CM-SYNC-UPSTREAMS-FF-ONLY` checks the engine statically (AST: an import and module-attribute allow-list,
no dynamic access such as `getattr` / `eval`, `subprocess.Popen` and the other spawn names only inside
`proc_run_git` and only called, `os.killpg` only inside `proc_kill_group` under `pgid > 1`, both functions
referenced exactly once, literal allow-listed arguments and a declared `ok=` tuple at every git call site)
and at runtime (for every argument shape the engine uses: the exact argv with every safe `-c` pair; the
fetch shape; `git_env` drops every config-injecting variable; adversarial credential shapes are redacted;
`proc_run_git` refuses a forbidden shape before any process exists; a table of refused and accepted
shapes), with its own mutation test (50 cases). `tests/sync/test_faults.sh` makes every git call of a
full `--apply` run give no answer, one call per run, and checks that the run is `BLIND` and that the
repository concerned (and everything below it) did not move; the AST lister inside `tests/sync/test_faults.sh` lists the call sites
from the engine's AST so a new call cannot hide from it. `tests/sync/test_mutations.py` holds the
standing mutant table (the fixers' M-series, the reviewer's K01–K17 and R1–R6).

## Honest boundary

The tests run real git against real bare repositories in scratch directories (`file://` and a loopback
port that refuses); no network remote and no forge is contacted, so this is gate-logic / unit-class
evidence, not proof against a real forge (§11.4.289). A clean or smudge filter or a diff driver the
user configured is not disabled: git runs a clean filter while `status` compares the work tree (so
also during `--check`) and a smudge filter while `checkout` or `merge --ff-only` writes files. A
`textconv`, diff driver or merge driver never runs: the engine runs no diff and a fast-forward merges no
content. Evidence directories under `~/.cache/helix_sync_upstreams/` are never pruned by the engine
(open item: retention policy). Ignored files are listed one by one (`git ls-files --others
--ignored`), which costs time in a tree with very many ignored files. Behaviour against real forges (ssh keys, rate limits, large repositories) is
UNCONFIRMED until the operator runs it. The engine reports; it does not decide whether a third-party
pin should advance.
