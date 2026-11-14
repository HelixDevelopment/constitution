# Sync-all-upstreams user guide — keep a project and every submodule current, fast-forward only

| Field | Value |
|---|---|
| Revision | 6 |
| Created | 2026-11-12 |
| Last modified | 2026-11-14T18:30:00Z |
| Status | draft (pending independent review) |
| Status summary | Task-oriented guide for `scripts/sync/sync_all_upstreams.sh`: check, apply, interactive use, setup and post-update integration, scheduling. |
| Authority | Constitution §11.4.37, §11.4.71, §11.4.84, §11.4.113, §11.4.164, §11.4.233(G), §11.4.288(D). The canonical text wins where this guide and the constitution disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | revision 4: review round 3 (NO-GO) F1–F9 (a submodule git cannot read is BLIND and printed under `--quiet`; `head_after` re-read after the whole pass; `--advance-pins` never detaches a branch; userinfo cut to the end of the line, remembered secrets removed anywhere; trace variables dropped; the one signal point checks the child's own group); revision 3: review round 3 fixes (a git call that gives no answer is BLIND, a time-out is INCONCLUSIVE; one spawn and one signal point; one guarded writer; userinfo redaction); revision 2: fetch never deletes, no hooks, INCONCLUSIVE, ignored-file guard, exit codes 5/6/7 |
| Fixed summary | — |
| Continuation | — |

Related: [manual](../manuals/sync_upstreams_manual.md) · [FAQ](../faq/sync_upstreams_faq.md) ·
[design](../design/sync_all_upstreams_design.md)

> Path note: `<constitution>` below is where the constitution lives in your project
> (`submodules/constitution` in the standard layout, `constitution` in the legacy one).

## What it does in one paragraph

The tool fetches every remote of your project and of every submodule at every depth. It then tells you,
per repository, whether you are current, behind, ahead or diverged, and whether every recorded
submodule pin is on its upstream `main`. With `--apply` it moves what can move safely: a repository on
`main` with a clean tree is fast-forwarded, and clean submodules follow their parent's new pin. It never
pushes, commits, rebases, resets or forces anything, and it writes JSON and TSV evidence of every run.

## 1. See where you stand (changes nothing)

```bash
bash <constitution>/scripts/sync/sync_all_upstreams.sh --check
```

It fetches and reports. The last three lines are machine-readable:

```text
REPORT_JSON=/home/you/.cache/helix_sync_upstreams/myproj-20261112T230000Z-4242/sync_report.json
CANONICAL_SHA256=…
RESULT: UPDATES-AVAILABLE exit=3
```

Offline (no network, uses the refs you already have): add `--no-fetch`. To plan without fetching and
without changing anything: `--dry-run`.

## 2. Bring everything up to date

```bash
bash <constitution>/scripts/sync/sync_all_upstreams.sh --apply
```

* A repository moves only when it is checked out on `main`, its tree is clean and no merge, rebase,
  cherry-pick, revert or bisect is in progress. Anything else is reported, never touched.
* Submodule pins you recorded in a parent move only with `--advance-pins` (own-organisation submodules;
  add `--advance-third-party` for the rest). The new pin is **staged** (`git add`), never committed:
  review and commit it yourself.
* A submodule that is on a local branch when the run inspects it, and still on it when the write re-checks
  it, is not detached, neither to follow its parent nor by `--advance-pins`. (A branch checked out in the
  few milliseconds between that re-check and git's own write is not detected; the report then shows it.) It is reported `kept-on-branch:follow-pin` or `kept-on-branch:advance-pin` (attention):
  switch it back yourself when you mean it.
* A pin you STAGED yourself in a parent (or one an earlier `--advance-pins` run staged and you have not
  committed yet) is never replaced: it is reported `gitlink-staged:<path>` (attention, exit 4) until you
  commit it, and a further advance of that path is refused (`blocked:parent-index-changed`).
* If the constitution itself moved, the tool prints the `post_update_hook.sh` command for you to run. It
  never runs fetched code.

## 3. Let it ask you first

```bash
bash <constitution>/scripts/sync/sync_all_upstreams.sh --apply --interactive [--advance-pins]
```

It asks on your terminal before fetching, before fast-forwarding and before staging pins. Every
question defaults to **no**; only `y` or `yes` counts. Without a terminal, `--interactive` refuses
(exit 2) rather than guessing.

## 4. During first-time setup

```bash
bash <constitution>/scripts/setup.sh --sync-upstreams=ask      # asks, then syncs
bash <constitution>/scripts/setup.sh --sync-upstreams=check    # non-interactive report only
bash <constitution>/scripts/setup.sh --sync-upstreams=apply    # non-interactive fast-forward
```

The default is `off`, which only prints a hint. The same value can come from the environment:
`CONSTITUTION_SYNC_UPSTREAMS=check`. A sync result never makes setup fail, except when `apply` fails.

## 5. After every constitution pull

`post_update_hook.sh` runs a read-only check (step 5c). By default it is offline
(`CONSTITUTION_SYNC_CHECK=offline`). Set `CONSTITUTION_SYNC_CHECK=fetch` to fetch first, or `off` to
skip it. It prints the verdict and never fails the hook; `BLIND` and `INCONCLUSIVE` are shown as warnings.

## 6. Run it regularly

Examples ship in `<constitution>/scripts/sync/examples/` (a systemd user service and timer, and a cron
line). They run `--check` only and are **not installed** by anything: copying them is your decision.

## Reading the result

| Exit | Verdict | Meaning |
|---|---|---|
| 0 | `CURRENT` / `APPLIED` | Everything is on its upstream main (after `--apply`: everything that could move, moved). |
| 3 | `UPDATES-AVAILABLE` | Something is behind and nothing else needs you. Run `--apply`. |
| 4 | `ATTENTION` | Something needs a human: diverged, ahead, dirty, unreachable remote, a pin not on main, root not on main, a symbolic link or a file where a submodule should be (`pin-not-a-directory`), a submodule left on its branch (`kept-on-branch:…`), an ignored file the move would overwrite, a submodule moved on its own branch (modified gitlink), a branch deleted upstream, a staged pin (`gitlink-staged:…`), a write a re-check refused (`write-blocked:…`), a gitlink path that is unsafe or leads outside its parent. |
| 5 | `INCONCLUSIVE` | A git call ran out of time (`--timeout`, `--deadline`); those repositories are `unresolved` and were not moved. Re-run with more time. On expiry the call's process group gets SIGTERM, then SIGKILL 5 s later, and git is reaped with a 5 s limit; no fixed total is promised for the stop. A write is never ended by these limits or by a stop signal, only by `--write-timeout` (default 3600 s). |
| 1 | `FAILED` | An integration step failed, a write ran past `--write-timeout` (`write-killed:<op>`; the next steps print how to recover), a run lock cannot be opened (not another run: `cannot open the run lock`), or a submodule cannot fetch the pin its parent moved to (`follow-blocked:new-pin-unfetchable`; the submodule stays where it was); the report names it. |
| 2 | usage | Bad arguments; `--out` (or the default evidence directory) inside the work tree after symbolic links are resolved, not writable when the run starts, or holding a report file this engine did not write (or a link, a FIFO); a relative cache directory; `--interactive` without a terminal. Nothing was done. |
| 6 | `BLIND` | The self-check (control needle) failed, or a git call gave no answer for another reason (killed by a signal, an exit status the call does not expect, output of the wrong shape), or a submodule's `.git` cannot be read (a broken `gitdir:` pointer, an unknown repository extension, dubious ownership); the repositories concerned are `blind` and were not moved. |
| 7 | `LOCKED` | Another run holds the lock of this root or of a repository of this tree; nothing was fetched or changed. |
| 8 | `INTERRUPTED` | A stop signal arrived (Ctrl-C at an `--interactive` prompt included: the prompt ends at once). Read-only calls in flight were stopped, a write in flight was finished, and the report says what moved. Re-run. |

Per-repository lines show the path, the result and the reasons, for example
`libs/a   attention   dirty-tree`. With `--quiet` only the `current` lines are left out: a `blind`,
`not-initialised` or `failed` repository is always printed.

What the tool never does: it never deletes a ref or a tag (a branch deleted upstream keeps its
`refs/remotes/<remote>/<branch>`; run `git remote prune <remote>` yourself when you mean it), never runs
a hook or fsmonitor of the repository, and never overwrites an ignored file. The [manual](../manuals/sync_upstreams_manual.md) lists every
reason and every field of the report.
