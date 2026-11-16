# Sync-all-upstreams FAQ

| Field | Value |
|---|---|
| Revision | 8 |
| Created | 2026-11-12 |
| Last modified | 2026-11-16T09:00:00Z |
| Status | draft (pending independent review) |
| Status summary | Questions raised while designing, building and testing `scripts/sync/sync_all_upstreams.sh`, with the answers the engine gives. |
| Authority | Constitution §11.4.84, §11.4.113, §11.4.233(G), §11.4.288(D). The canonical text wins where this FAQ and the constitution disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | revision 4: review round 3 (NO-GO) F1–F9 (a submodule git cannot read is BLIND and printed under `--quiet`; `head_after` re-read after the whole pass; `--advance-pins` never detaches a branch; userinfo cut to the end of the line, remembered secrets removed anywhere; trace variables dropped; the one signal point checks the child's own group); revision 3: review round 3 fixes (a git call that gives no answer is BLIND, a time-out is INCONCLUSIVE; one spawn and one signal point; one guarded writer; userinfo redaction); revision 2: fetch never deletes, no hooks, INCONCLUSIVE, ignored-file guard, exit codes 5/6/7 |
| Fixed summary | — |
| Continuation | — |

Related: [user guide](../guides/sync_upstreams_user_guide.md) · [manual](../manuals/sync_upstreams_manual.md)

**1. Why does it never use `git pull` or `git submodule update`?**
`pull` can merge or rebase depending on configuration, and `submodule update` can check out commits that
are not on any upstream main. The engine fetches, then moves only with `merge --ff-only <sha>` or a
detached checkout of a commit it has verified, so the result never depends on someone's git config.

**2. My repository says `attention` with `dirty-tree`. What now?**
Commit, stash or discard your changes yourself, then run again. The engine never touches a tree with
local changes (§11.4.84).

**3. It says `upstreams-diverged`.**
Two remotes of that repository have `main` branches that are not ancestors of one another, so there is
no single newest main. Nothing moves. Integrate the remotes by hand (fetch, merge onto the latest main,
push fast-forward to every upstream, §11.4.113), then run again.

**4. Why did my submodule not move after `--apply`?**
Pins you recorded move only with `--advance-pins` (own-organisation submodules) and
`--advance-third-party` (the rest). A clean submodule whose checkout matched its parent's old pin follows
the parent automatically; a dirty or drifted one is left alone and reported
`follow-skipped:drifted-or-dirty`.

**5. Why exit 3 after `--apply`?**
Something is still behind: you answered no to a prompt, or a pin is behind and `--advance-pins` was not
given. Exit 0 means nothing is left behind.

**6. Does it commit the new pins?**
No. It stages them with `git add -- <path>`. Review `git diff --cached` and commit yourself.

**7. Can it leak a token?**
URLs in the report and on screen lose their userinfo (everything up to the last `@` of the line, whatever
its length), the userinfo of every configured remote is remembered and removed wherever it appears again,
token-shaped strings and `Authorization:` values are replaced with `[REDACTED]`, git's trace variables
(`GIT_TRACE*`, `GIT_CURL_VERBOSE`) are dropped, and no askpass program or terminal prompt is used (`GIT_ASKPASS` empty, `core.askPass` empty, no
terminal, `SSH_ASKPASS_REQUIRE=never`). A `credential.helper` you configured still runs: that is how you
authenticate. The security and unit suites
check this with planted tokens of many lengths (control needles prove the planted value would have been
seen). A secret shorter than 8 characters that git prints on its own, without its URL, is not removed. The
engine never prints credentials it did not receive in a URL; it does not read credential stores.

**8. Two runs at once?**
A second run over the same root exits 7 (`LOCKED`) at once. A run over a tree that shares a repository with a
running one (for example one rooted at a submodule of the other) reads first, then exits 7 when it tries to
lock that repository, before it fetches or changes anything. Each lock lives in the repository's git directory
and is released by the kernel when a run ends or dies, so there is no stale lock to clean up.

**9. A remote hangs. Will the run hang?**
No. Each network call has `--timeout` (on expiry its whole process group gets SIGTERM, then SIGKILL 5 s
later) and the run has
`--deadline`. A fetch that times out is reported `unreachable`; a local git call that runs out of time
makes the run `INCONCLUSIVE` (exit 5) and that repository `unresolved`. A git call that gives no answer
for any other reason (killed by a signal, an exit status its call site does not expect, malformed
output) makes the run `BLIND` (exit 6) and that repository `blind`. In both cases the repository is not
moved and nothing is concluded about it. A grandchild that escapes the process group is not waited for
once git itself has exited; a call that times out is reaped with a 5 s limit. A WRITE is different: it is
never ended by `--timeout`, `--deadline` or a stop signal (half a checkout is worse than a late one), only by
`--write-timeout` (default 3600 s; SIGTERM first so git removes its lock files, SIGKILL 30 s later). A
write ended that way is `write-killed:<op>` (FAILED); the next steps print the recovery.

**10. Why is the evidence not in my project?**
So the run never changes your work tree. `--out` inside the work tree is refused (exit 2). An `--out` directory
that already holds a `sync_report.json` or `sync_report.tsv` is used only when that file is a regular file
this engine wrote; your own file of that name, a symbolic link, a FIFO or a directory is refused (exit 2) and
left as it is.

**11. Is it safe to schedule?**
The examples in `scripts/sync/examples/` run `--check` only, which never changes a checkout. Installing
them is your decision; nothing installs them for you.

**12. After a constitution update, does it run the post-update hook?**
No. It prints the command (`next step (never run automatically): …`). Running code that has just been
fetched is your decision.

**13. Can the fetch delete my refs or tags?**
No. The fetch always passes `--no-prune --no-prune-tags --no-tags --refmap=` and the explicit refspec
`+refs/heads/*:refs/remotes/<remote>/*`, so a mirror refspec, `fetch.prune`, `remote.*.prune` or
`remote.*.tagOpt` in your configuration has no effect. A branch deleted upstream is reported
(`upstream-branch-gone:<remote>`) and its stale tracking ref is kept.

**14. Do my repository's hooks run?**
No. Every call passes `-c core.hooksPath=/dev/null -c core.fsmonitor=false`. A clean filter you configured
runs during `git status` (also in `--check`) and a smudge filter while files are written; the tool does not
disable them. Diff, textconv and merge drivers never run: the engine uses no git command that calls them.

**15. A submodule says `blind` and `pin-unreadable`. Why not "not initialised"?**
Its `.git` exists but git cannot read it: a `gitdir:` pointer to a directory that is gone, a repository
extension this git does not know, or a directory git refuses because of its owner. Reading that as "not
initialised" would hide the submodule and everything below it, so the run is `BLIND` (exit 6) and the row is
printed even with `--quiet`. Fix or re-initialise the submodule yourself, then run again.

**16. Is it tested against GitHub or GitLab?**
Not yet. The tests use real git against real bare repositories in scratch directories, without network.
Real forges (ssh keys, rate limits, large repositories) are UNCONFIRMED until run by the operator.

**17. My remotes need my own ssh setup (a key, a port, a jump host). The engine ignores `GIT_SSH_COMMAND`.**
Yes: a `GIT_SSH_COMMAND` from your environment is replaced by the engine's own
(`ssh -o BatchMode=yes -o ConnectTimeout=10`), so a run never waits for a password. Two ways keep your setup:
(a) put it in `~/.ssh/config` (a `Host` entry with `IdentityFile`, `Port`, `ProxyJump`): the engine runs plain
`ssh`, which reads that file; (b) set `core.sshCommand` in the repository (`git -C <repo> config core.sshCommand
"ssh -i ~/.ssh/id_work -o BatchMode=yes"`) or in your global git config: the engine then uses it and reports
`repos[].ssh = "core.sshCommand"` (tests/sync/test_hardening.sh). Keep `-o BatchMode=yes` in it: an ssh you
configure may prompt on its own terminal. Real forges are UNCONFIRMED until the operator runs it (question 16).

**18. Will a run fetch anything if I just pull the constitution?**
No. The defaults are `off` for `scripts/setup.sh` and `offline` (`--check --no-fetch`) for the post-update hook,
so nothing is fetched or changed unless you opt in (`--sync-upstreams=check|apply|ask`,
`CONSTITUTION_SYNC_CHECK=fetch`). This is what the code on this revision does. An operator decision of
2026-11-14 (relayed, not verbatim) moves the defaults to on, online and bounded; that change is tracked as CON-424
and is not made in this revision, so until it lands the answer above stays true.

**19. A run says `write-left-changes:fast-forward` or `blocked:in-progress:HEAD.lock`. What happened?**
A git lock file was left behind, usually by a git process that was killed. `blocked:in-progress:<name>` means
the engine found the lock before the write and did not start it; nothing changed. `write-left-changes:<op>`
means git ended the write with an error after it had already changed the index or HEAD. With git 2.53 a stale
`HEAD.lock` or `refs/heads/<branch>.lock` does exactly this to `merge --ff-only`: the index and work tree are
updated, then the ref update fails with status 128. The engine keeps its marker so the next run attributes
the leftovers to that write, not to you. To recover: make sure no git process runs in that repository, look at
`git status`, save what is there with `git stash push --include-untracked -m helix-sync-write-left-changes`,
remove the lock only after making sure no git process holds it, then run again. The lock sets the engine
checks are listed in the manual (Git locks and half-applied writes).

**20. My repository is on a branch other than main (or a linked worktree). Are the same locks checked?**
Yes. With `--branch <name>` the branch lock checked is `refs/heads/<name>.lock` in the common directory, for
the full name (`feature/x` gives `refs/heads/feature/x.lock`). In a linked worktree the per-worktree locks are
looked for in that worktree's own git directory, not in another worktree's. Both are tested live since review
round 10 (`tests/sync/test_robustness.sh --only branch_lock,wt_param,run_lock,write_race`).

**21. My branch is called `Dev`, or a tag `dev` sits beside branch `dev`. Does the right branch lock get checked?**
Yes, since review round 11. The engine reads the full ref (`git symbolic-ref -q HEAD`, for example
`refs/heads/dev`) and strips `refs/heads/` itself. It never asks git for the short name:
`git symbolic-ref --short` disambiguates and answers `heads/dev` when a tag `refs/tags/dev` or a top-level ref
`refs/dev` exists (measured with git 2.53; a remote named `dev` does not cause it). Case is kept: on branch `Dev`
the lock checked is `refs/heads/Dev.lock`, never `refs/heads/dev.lock`. A `--branch` value that git would refuse
as a ref name (`dev/`, `dev.lock`, `dev..x`, `dev/.x`, `HEAD`, `-dev`, `dev@{1}`, a space or control character)
is a usage error (exit 2) before anything is fetched. `--branch` is ASCII (`[A-Za-z0-9._/-]`); a root branch
with other letters (for example `café`) is read and compared exactly and is never taken as `main`.
On a case-insensitive file system (macOS, Windows defaults) `Dev.lock` and `dev.lock` are one file, so two
branches that differ only in case cannot be told apart there; git itself has the same limit. The tests run on
Linux (case-sensitive) only. Tested live: `tests/sync/test_robustness.sh --only branch_shape,branch_param`.
