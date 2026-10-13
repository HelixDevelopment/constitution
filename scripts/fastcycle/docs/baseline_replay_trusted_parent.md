# baseline_replay.sh and the trusted-parent rule (operator guide)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-13 |
| Last modified | 2026-10-13 |
| Status | active |
| Applies to | `scripts/fastcycle/cycle/baseline_replay.sh`, `scripts/fastcycle/cycle/fc_supervisor.py safepath` |
| Source | T048 V4 rounds 12–13 (`docs/qa/v4_round6_20261012/`, `docs/qa/v4_round7_20261012/`) |

## What the rule is

Every directory `baseline_replay.sh` creates, writes into or removes outside its own private temporary directory
goes through ONE implementation: `fc_supervisor.py safepath` (`_fc_safe` in the script). A path is accepted only
when every directory on it, from `/` down, and every symbolic link followed on the way:

1. is owned by **root or by you** (the effective uid), and
2. cannot be written by another user:
   - writable by every user: only with the **sticky bit** (`/tmp`, mode `1777`);
   - writable by its **group**: only when that group holds **nobody but you** — your own user-private group (the
     `umask 002` default on RHEL/Fedora-style hosts gives repositories `0775` directories in it). "Nobody but you"
     is read from the group database: the group's member list names nobody else, no other account has it as its
     primary group, and it is one of your groups.

A directory the replay uses as a **namespace** (`--worktree-root`, its `replay-logs`, the run-log directories, the
temp and state directories) must in addition be **yours alone**: owned by you and not writable by others (the
user-private-group exception above applies; a sticky shared directory does not — others may create names in it).

## What happens when a directory fails the rule

The replay stops with **BLIND, exit 4**, before it creates anything there. Two lines are printed on stderr:

```
fc_supervisor safepath mkdir: refused: /work/shared: mode 775: writable by group 10, which has a member other than
this user or is not one of this user's groups (remedy: chmod g-w, or use a directory outside it) (the trusted-parent rule)
baseline_replay: BLIND: replay: cannot create --worktree-root /work/shared/repo/.fc_worktrees, or it is not a
directory of this user's alone under a trusted chain (the trusted-parent rule; the reason is above)
```

| Refusal says | Meaning | Remedy |
|---|---|---|
| `owned by uid N (neither root nor this user ...)` | another user owns a directory on the path: they may rename what is in it | use a directory outside it |
| `writable by every user without the sticky bit` | mode `xx7` without `t` | `chmod o-w DIR` (or `chmod +t DIR`) |
| `writable by group G, which has a member other than this user ...` | a shared group may write it | `chmod g-w DIR`, or use a directory outside it |
| `not a directory of uid N's alone` | a namespace directory is shared (e.g. `1777`) | pick a `--worktree-root` of yours, mode `0700`/`0755` |
| `a path argument contains a newline` | the shell could not read such a path back unchanged | rename the directory |
| `safepath rmtree ...: refused: ... no final name to act on` | a removal of `X/..` or `.` was asked | name the directory itself |

## Lock files

The replay locks (`FC_REPLAY_LOCK_DIR`, else `XDG_RUNTIME_DIR`, else `/tmp`) are files made `0600`: a lock file
another user can open lets that user hold the lock forever (`flock` needs only a read descriptor). A lock file
readable by others (versions before round 13 made them `0644`) is **replaced** with a private one while its lock is
held — automatically, nothing to do.

## Boundary (what the rule cannot see)

- root may do anything; the rule trusts root's directories.
- A FUSE file system mounted with `allow_other` reports the owner and mode its daemon chooses; a daemon run by another
  user can show its directories as yours. Mounting one with `allow_other` needs root's `user_allow_other`.
- Group membership granted outside the group database (a group password with `newgrp`, a setgid program of the
  group, an NSS source `getpwall()` does not enumerate) is not seen; each needs root to set up.
- A replay worktree is first removed **by path** by `git worktree remove -f -f` (git must drop its own
  administrative entry); the path is a directory the replay made itself inside the proved `--worktree-root`. The
  descriptor-based removal (`safepath rmtree`) is the fallback.

## For developers: the census

`scripts/fastcycle/tests/check_safepath_census.py` classifies every path operation of `fc_supervisor.py` and
`baseline_replay.sh` and **fails closed**: an import, an `os` attribute, a shell command word or a git sub-command it
does not model is a violation until it is added to one of its tables with a reason. Its scope is the closed list in
its docstring; `--self-test` prints every form it refuses and accepts. It runs in the suite as `[R12LINT]` and
`[R13CENSUS-self]`.
