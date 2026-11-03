# install_agent_label_defs.sh — install label agent types into a project

**Revision:** 2
**Last modified:** 2026-11-03T00:00:00Z
**Authority:** constitution submodule §11.4.182 · §11.4.231(F) · §11.4.164 (post-update registration seam) · §11.4.177 (inherited by reference) · §11.4.18
**Classification:** universal (§11.4.17)

## What it does

Derives the project's (track, branch) set and runs `gen_agent_label_defs.sh`
for each into `<project>/.claude/agents/`:

1. the consumer's `config/multitrack/<host>.yaml` (via `multitrack_config.sh`):
   `track-<N>` ids; a literal `branch:` is used as is, a glob `branch_pattern:`
   is resolved from the HEAD of the track's `mount` checkout; an unresolvable
   track is **reported and skipped, never guessed**;
2. the current checkout's own identity from `track_branch_label.sh` (trunk = T1);
3. with no config at all, only (2). The loader's BUILT-IN default single-track
   config (used when no host config file exists) is not a consumer declaration
   and is ignored (Rev 2, F10).

Track ids are decimal (`track-007` is T7). Two branches of one track that
sanitise to the same type names (for example `Main` and `main`) are a
**COLLISION**: the first is kept, the second is skipped and reported, so reruns
do not flip the files back and forth (Rev 2, F9).

## Usage

```bash
bash constitution/scripts/multitrack/install_agent_label_defs.sh [--project-root DIR]
  [--out-dir DIR] [--models sonnet,opus] [--efforts low,medium,high,xhigh,max]
  [--check] [--dry-run] [--no-prune]
```

Exit codes: `0` ok - `1` drift (`--check`) - `2` usage - `3` a hand-made file
collides (left untouched) - `4` a hand-edited generated file (left untouched) -
`5` internal error - `6` REFUSED: the project root is the filesystem root, the
home directory or an ancestor of it, or the project root or out-dir is (or lies
inside, or contains) a user-level agent config directory (`CLAUDE_CONFIG_DIR`,
`~/.claude`, `~/.claude-*`); nothing is written (Rev 2, F1). A per-track
refusal (3/4) never stops the other tracks.

## Safety

Idempotent. Hand-made agents are never touched. Pruning removes only **genuine
generated** `T<N>-*.md` files whose track/branch is no longer declared AND
whose model and effort are inside this run's `--models` / `--efforts` filter, so
a partial run such as `--models sonnet` never prunes an opus file (Rev 2, F4).
A hand-edited stale file is kept with a WARN; `--no-prune` disables pruning.
Pruning is by (track, sanitised branch). A track that is declared but whose branch
cannot be resolved (mount absent, host mismatch) keeps its files, and with no usable
consumer config nothing is pruned (Rev 3, R2-2). User-level refusal (exit 6) compares
every path after symlink resolution, against `$HOME` or the passwd home when `$HOME`
is empty (Rev 3, R2-1).

## Wiring

`scripts/post_update_hook.sh` (STEP 4f) runs it on **every** constitution pull,
**dry-run by default** (it only reports what it would write or prune). It writes
only with `AGENT_LABEL_DEFS_AUTOWIRE=apply`; `off` skips the step; any other
value is treated as dry-run (Rev 2, F1; the same consent pattern as the
label-sync STEP 4c). Non-fatal: a collision or refusal is a WARNING. Consumers get fresh types on
their next pull; the agent platform loads definitions at session start (a
mid-session type may need a short delay or a restart - UNVERIFIED for
interactive sessions).

## Tests

`test_install_agent_label_defs.sh` (78 cases incl. the hook wiring and its
consent modes in a hermetic fixture constitution); gate `CM-AGENT-TYPE-LABEL`.

**Last verified:** 2026-11-03.
