# baseline_replay.sh and the trusted-parent rule (operator guide)

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-13 |
| Last modified | 2026-10-13 |
| Status | active |
| Applies to | `scripts/fastcycle/cycle/baseline_replay.sh`, `scripts/fastcycle/cycle/fc_supervisor.py safepath` |
| Source | T048 V4 rounds 12–14 (`docs/qa/v4_round6_20261012/`, `docs/qa/v4_round7_20261012/`, `docs/qa/v4_round8_20261013/`) |

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
     primary group, and it is one of your groups. **Not for a directory with an extended ACL** (round 14): with a
     POSIX ACL the group bits shown by `ls` are the ACL *mask*, which carries every named grant —
     `setfacl -m u:bob:rwx DIR` shows as `drwxrwx---+` and lets bob rename and create in DIR. Any `system.*`
     extended attribute (`system.posix_acl_access`, `system.posix_acl_default`, NFSv4 / rich / CIFS ACLs) removes
     the exemption, and so does an extended-attribute list that cannot be read (the check fails closed).

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
| `mode M with an extended ACL (a system.* xattr), or one that could not be read ...` | the group bits are an ACL mask: a named entry may let another user write it | `setfacl -b DIR` (removes the ACL), or `chmod g-w DIR` |
| `not a directory of uid N's alone` | a namespace directory is shared (e.g. `1777`) | pick a `--worktree-root` of yours, mode `0700`/`0755` |
| `a path argument contains a newline` | the shell could not read such a path back unchanged | rename the directory |
| `safepath rmtree ...: refused: ... no final name to act on` | a removal of `X/..` or `.` was asked | name the directory itself |

## Lock files

The replay locks (`FC_REPLAY_LOCK_DIR`, else `XDG_RUNTIME_DIR`, else `/tmp`) are files made `0600`, so another user
cannot OPEN a lock file made by this version (`flock` needs only a read descriptor). A lock file with any group or
other permission bit (versions before round 13 made them `0644`) is **replaced** with a private one while its lock is
held — automatically, nothing to do.

When the lock directory is one other users may create names in (the `/tmp` fallback, mode `1777`), the
per-filesystem lock name (`fc_baseline_replay.fs-<dev>.lock`) is predictable, so anyone could create it first and make
every replay refuse. Such a directory is therefore **not used**: the locks are taken in
`$HOME/.cache/fc_baseline_replay/locks` (created `0700`, proved by the trusted-parent rule). A lock directory that is
yours alone (`$XDG_RUNTIME_DIR`, an `FC_REPLAY_LOCK_DIR` of yours) is used as it is.

What these measures do **not** cover (stated, not closed):

- with no usable `$HOME` (unset, relative, or failing the rule) the shared directory stays in use: a pre-planted lock
  name then makes the replay refuse (BLIND 4) — it never runs without its lock. Remedy: set `FC_REPLAY_LOCK_DIR` or
  `XDG_RUNTIME_DIR` to a directory of yours;
- a user who already holds `LOCK_EX` on an old readable lock file when this version first runs keeps that lock busy
  (the replacement happens only after this replay's own lock succeeds): the replay refuses as "already running";
- lock files are per user: two different users' replays on one file system do not wait for each other.

## Boundary (what the rule cannot see)

- root may do anything; the rule trusts root's directories.
- A FUSE file system mounted with `allow_other` reports the owner and mode its daemon chooses; a daemon run by another
  user can show its directories as yours. Mounting one with `allow_other` needs root's `user_allow_other`.
- Group membership granted outside the group database (a group password with `newgrp`, a setgid program of the
  group, an NSS source `getpwall()` does not enumerate) is not seen; each needs root to set up.
- The group answer is read once per process: the long-lived supervisor does not see a member added to the group
  while it runs (each `safepath` call is a new process and reads it afresh). Adding a member needs root.
- Access granted by mechanisms the mode and the ACL do not show needs root (or root-equivalent capabilities) to set
  up: Linux capabilities (CAP_DAC_OVERRIDE / CAP_FOWNER), id-mapped or bind mounts, immutable / append-only
  attributes (these only restrict). SELinux / AppArmor contexts can only restrict access further, never grant it.
  The full class enumeration, with the reason for each, is in `docs/qa/v4_round8_20261013/CONVERGENCE.md`.
- A replay worktree is first removed **by path** by `git worktree remove -f -f` (git must drop its own
  administrative entry); the path is a directory the replay made itself inside the proved `--worktree-root`. The
  descriptor-based removal (`safepath rmtree`) is the fallback.

## For developers: the census

`scripts/fastcycle/tests/check_safepath_census.py` classifies every path operation of `fc_supervisor.py` and
`baseline_replay.sh` and **fails closed**: an import, an `os` attribute, a shell command word or a git sub-command it
does not model is a violation until it is added to one of its tables with a reason. Its scope is the closed list in
its docstring; `--self-test` prints every form it refuses and accepts. It runs in the suite as `[R12LINT]` and
`[R13CENSUS-self]`.
