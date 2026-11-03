# install_agent_label_defs.sh — install label agent types into a project

**Revision:** 1
**Last modified:** 2026-10-15T00:00:00Z
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
3. with no config at all, only (2).

## Usage

```bash
bash constitution/scripts/multitrack/install_agent_label_defs.sh [--project-root DIR]
  [--out-dir DIR] [--models sonnet,opus] [--efforts low,medium,high,xhigh,max]
  [--check] [--dry-run] [--no-prune]
```

Exit codes: `0` ok - `1` drift (`--check`) - `2` usage - `3` a hand-made file
collides (left untouched) - `4` a hand-edited generated file (left untouched) -
`5` internal error. A refusal never stops the other tracks.

## Safety

Idempotent. Hand-made agents are never touched. Pruning removes only **genuine
generated** `T<N>-*.md` files whose track/branch is no longer declared (a
hand-edited stale file is kept with a WARN); `--no-prune` disables it.

## Wiring

`scripts/post_update_hook.sh` (STEP 4c) runs it on **every** constitution pull
(idempotent, non-fatal: a collision is a WARNING). Consumers get fresh types on
their next pull; the agent platform loads definitions at session start (a
mid-session type may need a short delay or a restart - UNVERIFIED for
interactive sessions).

## Tests

`test_install_agent_label_defs.sh` (43 cases incl. the hook wiring in a hermetic
fixture constitution); gate `CM-AGENT-TYPE-LABEL`.

**Last verified:** 2026-10-15.
