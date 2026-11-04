# baseline_replay.sh and the trusted-parent rule (operator guide)

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-10-13 |
| Last modified | 2026-11-04 |
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
     **Boundary (stated, not closed):** the ACL is consulted only to withhold this group exemption. A directory
     whose mode shows NO group/other write bit is trusted on its mode bits alone. That is sound for POSIX ACLs and
     rich ACLs (the kernel keeps the group bits equal to the mask of every named grant, shown by [R14ACL-masknow])
     and for a Linux NFS server (it stores NFSv4 ACLs as POSIX ACLs). A remote NFSv4 / SMB server that does NOT keep
     its mode attribute in step with its ACL can grant another user write on a directory whose mode reads `0700`;
     this rule cannot see that. Refusing every directory that carries `system.nfs4_acl` would refuse every NFSv4
     home directory (the client lists that name on every object), so it is not done; keep the replay's directories
     on a local file system, or on a server whose mode bits reflect its ACLs.

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

The replay locks (`FC_REPLAY_LOCK_DIR`, else `/tmp` — see below) are files made `0600`, so another user
cannot OPEN a lock file made by this version (`flock` needs only a read descriptor). A lock file with any group or
other permission bit (versions before round 13 made them `0644`) is **replaced** with a private one while its lock is
held — automatically, nothing to do.

When the lock directory is one other users may create names in (the `/tmp` fallback, mode `1777`), the
per-filesystem lock name (`fc_baseline_replay.fs-<dev>.lock`) is predictable, so anyone could create it first and make
every replay refuse. Such a directory is therefore **not used**: the locks are taken in
`<home>/.cache/fc_baseline_replay/locks` (created `0700`, proved by the trusted-parent rule), where `<home>` is your
home directory **from the password database** (`getent passwd $(id -u)`), never the environment's `$HOME`: two
replays of the same user must find the same lock file whatever environment each runs in (cron, `env -i`, a
sudo-preserved environment — round 14 read `$HOME`, and two replays with different `$HOME` ran at once). For the same
reason `$XDG_RUNTIME_DIR` is no longer a default (cron does not set it). If that directory cannot be used (an untrusted
home, a shared directory made there, an I/O error) the replay **refuses** (exit 4) rather than lock elsewhere. A lock
directory that is yours alone (an `FC_REPLAY_LOCK_DIR` of yours) is used as it is.

Upgrade window: a replay of an older version (locks in `$XDG_RUNTIME_DIR` or `$HOME/.cache/...`) and one of this
version running at the same moment do not see each other's per-filesystem lock — finish or stop older replays before
the first run of this version. (The per-repository lock, in the repository's git directory, is unchanged and still
excludes them.)

What these measures do **not** cover (stated, not closed):

- with no home directory in the password database for your uid (or a relative one) the shared directory stays in
  use: a pre-planted lock name then makes the replay refuse (BLIND 4) — it never runs without its lock. Remedy: set
  `FC_REPLAY_LOCK_DIR` to a directory of yours;
- two replays given different `FC_REPLAY_LOCK_DIR` values are two lock domains (your explicit choice) and do not wait
  for each other on the per-filesystem lock;
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

## Stop signals in front of the exec (ATM-1220)

`replay`, `replay-sample` and `selfcheck` start in the caller's bash, check their arguments, and then `exec` into the
process supervisor. A stop signal (HUP, INT, QUIT, TERM) sent to the tool's pid in that short stretch could be lost:
bash drops an INT that arrives while it waits for a foreground child that then exits normally, and an INT caught by a
trap just before `exec` disappears with the old process image. The replay then ran to the end and exited 0. Measured
before the fix: about 0.16% of INTs, about 6% of 40-INT sweeps (`[R7N6SWEEP]`).

What the tool does now:

- Before its first foreground child, the caller's bash reads its own signal mask (builtin `read` of
  `/proc/self/status`). If HUP, INT, QUIT and TERM are not all blocked, it runs one probe
  `env --block-signal=HUP,INT,QUIT,TERM true` in the background (waited with `wait`, which a trapped stop interrupts at
  once) and then re-executes itself through `env --block-signal=HUP,INT,QUIT,TERM`. HUP, INT and TERM that arrive
  after the probe stay pending and are handled by the supervisor (exit 128+N); one that arrives before the re-exec ends
  the tool with 128+N or with the signal itself. QUIT is different, see the QUIT limit below.
- The worker and every gate run with these signals unblocked (the supervisor resets the mask). `[R7N6BLK]` checks both
  sides, with an empty caller mask and with a caller that blocks only INT.
- **Degraded mode.** If `env` has no `--block-signal` (GNU coreutils older than 8.31), the tool still runs, with the
  earlier trap-only protection, and prints one line on stderr starting `baseline_replay: WARNING: DEGRADED stop
  protection`. In that mode the rare lost stop described above is still possible. Install an `env` that supports
  `--block-signal` to remove it. `[R7N6BLKDEG]` checks this path. The warning is written after SIGPIPE is ignored, so a
  closed stderr reader does not kill the tool (`[R7N6R4-deadpipe]`). The same warning, with the words "still unblocked
  after the re-exec", appears if `env` accepts `--block-signal` but does not block, or if the caller set
  `_FC_BR_STOPS_BLOCKED=1` itself (`[R7N6R4-liar]`).

Limits:

- **Argument checks run with stops pending.** `cd`, `dirname`, `sed`, `git rev-parse --git-common-dir` and the
  `_fc_safe` path checks run before the exec. A stop sent to the tool's pid already waited for such a child to finish
  (bash runs a trap only after the foreground child exits). A Ctrl-C sent to the whole process group used to end a hung
  child at once; it now waits until the child ends, because the child inherits the blocked mask (measured with a 3 s
  child: 0.8 s before, 3.0 s now). If one of these checks hangs, only SIGKILL ends it. No timeout bounds these checks
  yet (tracked as an ATM-1220 follow-up).
- **QUIT is not fully protected.** Bash ignores QUIT in its own process. A QUIT is therefore lost in two short
  windows that no shell code can close: from the tool's start until its first QUIT trap (bash start-up and the mask
  read), and inside the re-executed bash from its start until bash ignores QUIT (bash start-up discards a pending
  QUIT). The QUIT trap is kept until the `exec` (since round 4), so the gap between the probe and the `exec` no longer
  loses it. Measured with 120 QUITs at random instants 0-300 ms after start, the gate sleeping 3 s: 1 lost (sent 2 ms
  after start, still in the first bash); the 76ac981 code lost 3 of 120 (2, 2 and 17 ms), the code before ATM-1220
  9 of 120. `[R7N6QUIT-probe]` (QUIT during the probe gives 131) and `[R7N6QUIT-child]` (QUIT while the re-executed
  bash waits for a child ends the run as a stop) check the covered parts.
- **`freeze` is not covered.** It never execs into the supervisor, so nothing would unblock its stops. It keeps the
  default dispositions, and a stop that lands while it waits for a child can still be dropped by bash.

## Test-host limits and the measured r6 paired-mutation run (carry review round 2)

These are limits of the test hosts, not of the tool. They are stated so a red or SKIP in the suites is read correctly.

- **`env` wrapper reopens closed fds (uutils coreutils).** `baseline_replay.sh` execs the supervisor through
  `env --block-signal=INT`. Where `env` is uutils coreutils (a Rust binary; measured 0.8.0), it re-opens a closed fd
  0-2 on `/dev/null` before it execs, so a caller's closed stream never reaches the supervisor through that entry
  (`sys.stdout` is a `/dev/null` wrapper, not `None`). Since ATM-1220 the caller-side bash also re-executes itself
  through `env --block-signal=HUP,INT,QUIT,TERM` (see the section above), so on such a host the closed stream is
  already `/dev/null` in the caller's own argument checks. The stream matrix probes this with the same wrapper and counts
  its `closed-*` cells (`closed-out`, `closed-err`, `closed-both`, `dead-out-closed-err`, `closed-in`) as SKIP
  `[reason=topology_unsupported]` instead of passing them on a null cell. `[R8FDS]` calls the supervisor directly and
  still drives genuinely closed fds on every host. On such a host the paired mutants that live on the closed-fd
  branches (V4R7-N2, V4R8-1a, V4R10-RV3-12, V4R10-M9) cannot be observed and the r6 runner reports them as survivors:
  that is the instrument being blind, not the product being wrong (UNCONFIRMED on a host with GNU `env`).
- **uid / ACL rows.** The foreign-uid rows are SKIPped where AppArmor restricts unprivileged user namespaces
  (`kernel.apparmor_restrict_unprivileged_userns=1`); the cause is printed on each SKIP and the suite SUMMARY carries
  `skip=`.
- **Measured full r6 paired-mutation run on the carry (reviewer, round 2; 6090 s): pass 372, fail 26.** The 26 are:
  19 survivors on rows that SKIP for the uid / ACL cause above (V4R11-M6, V4R11-M16, V4R12-RV5-02, V4R12-M1, M4, M5, M8,
  M14, M15, V4R13-M19, V4R14-M1, M2, M4 to M10), 2 blind controls (control-r12, control-r14: their unmutated case is one
  of those skipped rows), 4 closed-* survivors (the `env` cause above, confirmed), and 1 survivor CARRY-F1-M1 (fixed:
  the row now points at the static order check `[CARRY-F1-order]`, which catches it). Whether the 19 and the 2 pass on
  a host that allows unprivileged user namespaces is UNCONFIRMED.
- **Standard-fd repair access mode.** The repaired fds are asserted to be `O_RDWR` (`[R8FDS]` probe modes,
  `[CARRY-F1-accmode]` behaviour test: writes to 1 and 2 and a read of 0 succeed).
