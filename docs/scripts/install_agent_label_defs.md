# install_agent_label_defs.sh — install label agent types into a project

**Revision:** 4
**Last modified:** 2026-11-03T22:06:31Z
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

## Refusals added in review rounds 3 and 4, and known limits

- `--out-dir /` (also `//`, `///`, `/.`, `/..`) and the project root `/` are refused with exit 6: the filesystem root counts as an ancestor of the home directory and of every protected directory.
- The system directories of `scripts/lib/protected_paths.list` are refused as project root or out-dir (`/bin /boot /dev /etc /lib* /opt /proc /root /run /sbin /srv /sys /usr`: the directory and anything inside it; `/var /home /mnt /media /snap /tmp /Users`: the directory itself only, because ordinary projects live below them). Unit tests pin both lists (I17f/g), refuse every absolute entry of that file as an out-dir except `/Users`, which does not exist on Linux (I17e), refuse a child of every strict entry (I17h) and every exact-only entry itself (I17i), and accept a child of every exact-only entry (I17j). The check is one-directional: a new entry added to `protected_paths.list` and not mirrored here fails I17e; a list here is not checked against that file in the other direction.
- Paths are canonicalised in pure bash with a flag-less `readlink`, never with `realpath -m` (review round 4, R4-1: BSD/macOS `realpath` has no `-m`, and busybox fails the same way, so `..` was left unresolved and `--out-dir "$HOME/x/../.claude/agents"` was accepted and written). `.`, `..`, `//` and every ordinary symlink on the path are resolved; a symlink is followed before a following `..`, as the kernel does (tested by I22 and I23a, reviewer mutant RV7). When a symlink on the path cannot be read, the run is refused with exit 6 ("cannot canonicalise"), never guessed. Tested with failing `realpath` and `readlink` stubs first on PATH (I19).
- Per-process links are NOT resolved (review round 5, R5-1): a symlink located under `/proc` (`/proc/self`, `/proc/thread-self`, `/proc/<pid>/cwd`, `root`, `exe`, `fd/*`, ...) or at `/dev/fd`, `/dev/stdin`, `/dev/stdout` or `/dev/stderr` means something different in every process, and a `readlink` in a child process answers for that child, so a following `..` could leave `/proc` and reach `~/.claude/agents`. Any path through such a link is refused with exit 6, even where it would land somewhere harmless. As a second, independent check, the longest prefix of the path that can be entered is resolved by the kernel (`cd -P` in a subshell) and must equal the pure-bash result for the same prefix, otherwise exit 6. Tested by I21 (including the reviewer's NON-dry `/proc/self/cwd/../../../<home>/.claude/agents` from `~/a/b`), I23c-g and gate mutants R20-R22.
- A project root that exists but cannot be entered (for example `chmod 000`) and is not a system or user-level directory stops with exit 2 and writes nothing (I24, reviewer mutant RV5).
- Prefix siblings are not confused with the protected directory: `/usrx`, `/optimum` and `~/.claudeless` are accepted (I17k-m).
- Known limits (honest residuals): a bind mount of a user config directory is invisible to the symlink-resolving refusal (UNCONFIRMED by experiment); the refusal runs once before generation, so a path component swapped for a symlink between the check and the write (check-to-write race) is not caught; `$XDG_CONFIG_HOME/claude` and other platforms' user directories are not protected; the comparison is case-sensitive, so on a case-insensitive file system (the macOS default) `~/.CLAUDE/agents` is not refused. These two (XDG/other platforms, case-insensitive file systems) are tracked as follow-up work, not fixed in this change.
- A `branch_pattern:` track whose mount HEAD does not match the pattern (for example `feature/*` with the mount on `hotfix/x`) is now reported and treated as unresolved: no files for the HEAD's branch are generated and the track's existing files are kept (review round 3, R3-5; test I20).
- Open operator question (§11.4.66): everything under `/root` is refused, so the root user cannot install into a project below its own home, while a normal user can (review round 4 ruling).
