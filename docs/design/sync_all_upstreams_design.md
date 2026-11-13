# Sync-all-upstreams design — fetch every remote of a project tree, fast-forward only

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-11-12 |
| Last modified | 2026-11-13T00:00:00Z |
| Status | draft (pending independent review) |
| Status summary | Design of `scripts/sync/sync_all_upstreams.sh`: one read-mostly engine that fetches every remote of a project and of every submodule recursively, integrates only by fast-forward, reports pin state, and writes machine evidence; wired into setup.sh (interactive and non-interactive) and post_update_hook.sh (check only). |
| Authority | Constitution §2.1, §11.4.26, §11.4.32, §11.4.36, §11.4.37, §11.4.71, §11.4.84, §11.4.113, §11.4.164, §11.4.233(G), §11.4.288(D), §12 — the canonical text wins where this document and the constitution disagree. |
| Scope | Universal (§11.4.17); consumed by reference. |
| Issues | none |
| Issues summary | — |
| Fixed | revision 3: review round 3 fixes (a git call that gives no answer is BLIND, a time-out is INCONCLUSIVE; one spawn and one signal point; one guarded writer; userinfo redaction); revision 2: fetch never deletes, no hooks, INCONCLUSIVE, ignored-file guard, exit codes 5/6/7 |
| Fixed summary | — |
| Continuation | — |

## Operator order

2026-11-12 22:26, relayed by the conductor (BACKGROUND, CRITICAL): regularly fetch and pull the latest
changes from all upstreams and all submodules, fully recursively, and incorporate that into every
first-time init / setup mechanism (with full interactivity) for new and existing projects, with tests of
every supported type, live and deterministic, with machine-produced evidence.

## What exists (inventory, measured on 02c10935)

| Mechanism | What it does | What it does NOT do |
|---|---|---|
| `install_upstreams.sh` (+ `upstreams/*.sh`) | Configures every declared upstream as a git remote (§11.4.36); naming by URL (§11.4.111). | Fetch or integrate anything. |
| `scripts/install_constitution.sh` | Interactive (`/dev/tty`) or `--non-interactive` first-time install / update of the constitution submodule; runs `setup.sh`; gate `CM-INSTALLER-NO-PUSH-NO-FORCE` holds it to an allow-list. | Touch any other submodule or the project's own remotes. |
| `scripts/update_constitution.sh` | Fetch + fast-forward-only update of the constitution submodule only; stages the gitlink; runs the post-update hook. | Any other submodule, nested submodules, the project root. |
| `scripts/setup.sh` | One-time wiring (hooks, post-update propagation) of a consuming project. Non-interactive. | Fetching; it has no prompt. |
| `scripts/post_update_hook.sh` | §11.4.164 propagation after a constitution pull; STEP 5b hub gates on every pull. | Any upstream state report. |
| `scripts/jev/bootstrap.sh` | §11.4.281 decision-layer wizard (interactive + `--non-interactive`). | Not related to repository sync; left unchanged. |
| `scripts/deps_manifest/*`, `find_constitution.sh` | Manifest verification (§11.4.31); locating the constitution. | Fetching. |

## Gaps

1. No mechanism fetches **all** remotes of the project root **and** of every submodule at every depth.
2. Nothing reports, per repository, ahead / behind / diverged / unreachable state for every remote,
   nor the §11.4.233(G) pin classes (absent, uninitialised, unfetchable) together with the
   §11.4.288(D) condition "recorded gitlink is on upstream main".
3. No first-time setup path offers a sync; no recurring check exists; no machine evidence of a sync.

## The new mechanism

`scripts/sync/sync_all_upstreams.sh` (wrapper) runs `scripts/sync/sync_all_upstreams.py`
(`python3 -I`, one file, standard library only).

* **Modes** (exactly one is required): `--dry-run` (no fetch, no change: plan from the refs already
  present), `--check` (fetch, report, change nothing else; exit 3 when anything is behind),
  `--apply` (fetch, then fast-forward). `--no-fetch` turns `--check` into an offline check.
* **Discovery**: gitlinks (`git ls-files -s`, mode 160000) of every initialised repository,
  recursively, cycle- and depth-bounded (`--max-depth`, default 32).
* **Fetch**: exactly `git fetch --no-prune --no-prune-tags --no-recurse-submodules --no-auto-gc --no-tags
  --refmap= -- <remote> +refs/heads/*:refs/remotes/<remote>/*` per remote (with `--tags` also the
  non-forced `refs/tags/*:refs/tags/*`): the explicit refspec and empty `--refmap=` override every
  configured refspec and prune setting, so a fetch never deletes or rewrites a ref outside
  `refs/remotes/<remote>/*`; a branch deleted upstream is read from `FETCH_HEAD` and reported, its stale
  tracking ref kept. Every git call carries `-c core.hooksPath=/dev/null -c core.fsmonitor=false` and the
  other safe pairs (`git_argv`), so no repository hook or fsmonitor runs. Bounded by `--timeout` per call, `--deadline` per run and a worker pool
  of `--jobs` (default and ceiling derived from the CPU count, never above 8; §12.6 / §12.12).
* **Integration** (`--apply` only, pre-order: a parent moves first; each clean, initialised child
  whose checkout equalled the parent's old gitlink then follows the parent's new gitlink with
  `git checkout --detach <sha>`; a dirty or drifted child is left alone and reported
  `follow-skipped:drifted-or-dirty`):
  a repository checked out on `main` with a clean tree fast-forwards with `git merge --ff-only <sha>`
  onto the newest upstream main (all remote mains must be linearly ordered, otherwise
  `upstreams-diverged` and nothing moves). Submodule pins move only with `--advance-pins`
  (own-org only unless `--advance-third-party`): `git checkout --detach <sha>` in the clean submodule,
  then `git add -- <path>` in the parent (staged, never committed). Never push, commit, force, reset,
  rebase, `-s ours`, `--prune` or a refspec other than its own: every git call goes through one allow-listed wrapper that refuses
  anything else (gate `CM-SYNC-UPSTREAMS-FF-ONLY`).
* **Preconditions** per repository (§11.4.84): a dirty tree, an in-progress merge / rebase /
  cherry-pick / revert / bisect, an `index.lock`, or an ignored file the target tree would overwrite
  blocks integration of that repository only. A git call that gives no answer makes the repository `unresolved`: it is never moved. Every call
  site declares the exit statuses that are answers (`ok`) and, where it reads output, the shape it expects
  (`want`); a signal, an undeclared status (126, 127, 128, ...) or output of the wrong shape is no answer
  and makes the run `BLIND`; a call that only ran out of time (`--timeout`, `--deadline`) makes it
  `INCONCLUSIVE`. A repository whose judgement rests on a call without an answer is `blind`, never `failed`.
* **Lock**: one `fcntl` lock per project (`<git-common-dir>/helix-sync-upstreams.lock`); a second run
  exits 7 (`LOCKED`). The kernel releases the lock when a run dies, so no stale lock exists.
* **Evidence**: `sync_report.json` (schema `helix.sync_upstreams/1`) and `sync_report.tsv` in `--out`
  (default under `$XDG_CACHE_HOME`), with run id, per-repository before/after SHAs, timestamps,
  exit codes, a §11.4.273 control needle, and `canonical_sha256` over the time-free part, which is
  identical for identical repository states (§11.4.50).
* **Credentials** (§11.4.10): URLs are logged with userinfo removed, git stderr is redacted, git never
  prompts (`GIT_TERMINAL_PROMPT=0`, ssh `BatchMode=yes`), ambient `GIT_DIR`-class variables are dropped.
* **Never executes fetched code**: after a constitution pin advances it prints the
  `post_update_hook.sh` command for the user instead of running it.
* **Exit codes**: 0 current / applied, 1 an integration step failed, 2 usage, 3 updates available
  (check, dry-run, or still behind after apply), 4 attention needed (diverged, unreachable, dirty, pin not
  on main, not on main, ignored file in the way, modified gitlink, branch gone upstream), 5 INCONCLUSIVE
  (a git call ran out of time), 6 BLIND (control needle failed, or a git call gave no answer for another
  reason), 7 LOCKED. Precedence: BLIND > FAILED >
  INCONCLUSIVE > ATTENTION > UPDATES-AVAILABLE > CURRENT.

## Integration

* `setup.sh --sync-upstreams=off|check|apply|ask` (default `off`, which only prints a hint): `ask`
  runs the engine's interactive wizard (`--interactive`, prompts on `/dev/tty`); `check` / `apply`
  run it with `--non-interactive`. A sync result never makes setup fail except an `apply` failure (1).
* `post_update_hook.sh` STEP 5c: `CONSTITUTION_SYNC_CHECK=offline` (default: `--check --no-fetch`),
  `fetch` (`--check`), `off`. Read-only; the verdict is printed (BLIND and INCONCLUSIVE as warnings);
  it never fails the hook.
* Scheduling: `scripts/sync/examples/` carries a systemd user service + timer and a cron line;
  nothing is installed.

## Honest boundary (§11.4.6)

Live evidence is real git against real bare repositories in scratch directories; no network remote and
no forge is contacted by the tests. Behaviour against real forges (ssh keys, rate limits) is
UNCONFIRMED until run by the operator; the tests are gate-logic / unit-class evidence (§11.4.289). A
user-configured clean filter runs during `git status` (so also in `--check`) and a smudge filter during a
checkout or merge; the tool does not disable them. Diff, textconv and merge drivers never run: the engine
calls no git command that uses them (the gate refuses `diff`, `show`, `log`, `cat-file` and the other verbs
that could). Evidence retention (how long reports are kept) is an open item. The
engine reports; it does not decide whether a third-party
pin should advance.
