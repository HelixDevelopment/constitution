# Sync-all-upstreams manual — `scripts/sync/sync_all_upstreams.sh`

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T23:30:00Z |
| Status | draft (pending independent review) |
| Status summary | Reference for every option, state, reason, exit code, report field, integration point and safety property of the sync-all-upstreams engine. |
| Authority | Constitution §2.1, §11.4.10, §11.4.37, §11.4.50, §11.4.71, §11.4.84, §11.4.113, §11.4.164, §11.4.233(G), §11.4.263, §11.4.273, §11.4.288(D), §12. The canonical text wins where this manual and the constitution disagree. |
| Scope | Universal (§11.4.17); consumed by reference. |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
| Fixed summary | — |
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
| `--check` | Fetch, report, change nothing else. Exit 3 when something is behind. |
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
| `--timeout S` | Seconds per network git call; on expiry the call's own process group is killed (never pgid ≤ 1, §11.4.263). |
| `--deadline S` | Seconds for the whole run; remaining fetches are skipped and reported. |
| `--max-depth N` | Submodule recursion depth (default 32); cycles are cut. |
| `--out DIR` | Evidence directory; must be outside the project work tree. Default `$XDG_CACHE_HOME/helix_sync_upstreams/<project>-<run-id>/` (`~/.cache` when unset). |
| `--run-id ID` | `[A-Za-z0-9._-]{1,80}`; default `<UTC time>-<pid>`. |
| `--quiet` | Print only repositories that are not current. |
| `--interactive` | Ask on `/dev/tty` before fetching, fast-forwarding and staging pins; default answer no. |
| `--non-interactive` | The flags are the consent (default). |

## Run order

1. **Lock** `<git-common-dir>/helix-sync-upstreams.lock` (`fcntl`; a second run exits 2; the kernel
   drops the lock when a run dies).
2. **Control needle** (§11.4.273): `rev-list --count HEAD ≥ 1` and `HEAD...HEAD == 0 0` on the root. If
   the instrument cannot see that, the run is `BLIND` (exit 2) and no zero is believed.
3. **Discovery**: gitlinks (`git ls-files -s`, mode 160000) of every initialised repository, recursively.
4. **Fetch** (check / apply, not `--no-fetch`): `git fetch --prune --no-recurse-submodules [--tags] --
   <remote>` per remote, in a worker pool.
5. **Measure**: per remote, state of `<remote>/<branch>` against the head before the run; the newest
   upstream main is the target when all remote mains are linearly ordered; per submodule, the pin state.
6. **Integrate** (apply only, pre-order): a parent moves first with `git merge --ff-only <sha>`; each
   clean, initialised child whose checkout equalled the parent's old gitlink then follows the new gitlink
   (`git checkout --quiet --detach <sha>`); with `--advance-pins`, pins at upstream main are checked out
   in the submodule and staged in the parent (`git add -- <path>`).
7. **Evidence** written atomically; verdict printed.

## States and reasons

**Remote state** (`repos[].remotes[].state`): `equal`, `behind`, `ahead`, `diverged` (relative to the head
before the run), `no-main` (the remote has no `<branch>`), `unreachable` (fetch failed or timed out),
`invalid-name` (never passed to git).

**Upstream state** (`upstream_state`): `linear` (one newest main exists), `upstreams-diverged`, `none`.

**Local vs target** (`local_vs_target`): `equal`, `behind`, `ahead`, `diverged`, `no-target`, `unknown`.

**Pin state** (`pin.state`, §11.4.233(G), §11.4.288(D)): `at-main`, `behind-main`, `on-main-not-newest`,
`not-on-main`, `not-on-any-remote`, `unfetchable`, `absent`, `uninitialised`; `pin.checkout` is
`at-pin` or `drifted`.

**Result** (`result`): `current`, `behind`, `updated`, `attention`, `failed`, `not-initialised`.

**Reasons** (any one makes the repository `attention`): `dirty-tree`, `in-progress:<MERGE_HEAD|…>`,
`unreachable:<remote>`, `invalid-remote-name`, `upstreams-diverged`, `root-not-on-<branch>`,
`local-ahead`, `local-diverged`, `pin-unfetchable`, `pin-not-on-any-remote`, `pin-not-on-main`,
`pin-checkout-drifted`, and with `--strict-pins` `pin-absent`, `pin-uninitialised`.

**Actions** (`actions[]`): `fast-forward`, `follow-pin`, `advance-pin`, or `none` with a `why`, for example
`follow-skipped:drifted-or-dirty`, `follow-skipped:submodule-on-branch`, `follow-blocked:new-pin-unfetchable`.

## Exit codes and verdicts

| Exit | Verdict | When |
|---|---|---|
| 0 | `CURRENT` / `APPLIED` | Nothing behind, nothing needs attention. |
| 1 | `FAILED` | An integration step failed. |
| 2 | `BLIND` / usage | Bad arguments, `--out` inside the work tree, lock held, no terminal for `--interactive`, needle failed, evidence not writable. |
| 3 | `UPDATES-AVAILABLE` | Something is behind (check, dry-run, or still behind after apply: a declined prompt, or a pin without `--advance-pins`). |
| 4 | `ATTENTION` | At least one reason above. |

Precedence: `BLIND` > `FAILED` > `ATTENTION` > `UPDATES-AVAILABLE` > `CURRENT`.

## Evidence

`sync_report.json` (schema `helix.sync_upstreams/1`, directory mode 0700): `run_id`, `mode`, `branch`,
`flags`, `consent`, `consent_source`, `root_abs`, `out_dir`, `started`, `ended`, `duration_s`, `jobs`,
`git_calls`, `control_needle`, `verdict`, `exit_code`, `counts`, `repos[]` (path, kind, depth,
initialised, branch, head_before, head_after, target, remotes, upstream_state, local_vs_target, pin,
own_org, result, reasons, actions), `next_steps`, `canonical_sha256`.

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
| `scripts/post_update_hook.sh` STEP 5c | `CONSTITUTION_SYNC_CHECK=offline` (default, `--check --no-fetch`), `fetch` (`--check`), `off`. Read-only; never fails the hook. |
| Scheduling | `scripts/sync/examples/` (not installed). |

## Safety properties

* Every git call passes one allow-list (`check_git_args`) before the single process spawn. Write
  subcommands are exactly `fetch`, `merge --ff-only <sha>`, `checkout --quiet --detach <sha>` and
  `add -- <relative path>`. Refused: push, commit, reset, rebase, `-s ours`, `+refspec`, `--force`,
  transport helpers (`::`), `--upload-pack=`, config writes, remote edits.
* Credentials (§11.4.10): URL userinfo is stripped, token-shaped strings are replaced with `[REDACTED]`,
  git never prompts (`GIT_TERMINAL_PROMPT=0`, ssh `BatchMode=yes`), ambient `GIT_DIR`-class variables
  are dropped.
* Fetched code is never executed; the post-update hook command is printed, not run.
* Integration needs a clean tree and no operation in progress (§11.4.84).
* Bounded: per-call timeout, run deadline, depth limit, `jobs` ceiling ≤ 8 (§12.6, §12.12).

## Tests and gate

`bash tests/sync/run_all.sh` (add `--quick` to skip chaos, performance and mutations). Suites: unit,
integration, end-to-end, full automation (setup and post-update hook), security, stress/chaos,
performance, determinism (N=3), UI (pseudo-terminal), and the engine's paired-mutation suite. The gate
`CM-SYNC-UPSTREAMS-FF-ONLY` checks the allow-list statically (AST) and at runtime, with its own
mutation test.

## Honest boundary

The tests run real git against real bare repositories in scratch directories; no network remote and no
forge is contacted. Behaviour against real forges (ssh keys, rate limits, large repositories) is
UNCONFIRMED until the operator runs it. The engine reports; it does not decide whether a third-party
pin should advance.
