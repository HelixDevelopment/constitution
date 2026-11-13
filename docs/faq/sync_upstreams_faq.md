# Sync-all-upstreams FAQ

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T23:30:00Z |
| Status | draft (pending independent review) |
| Status summary | Questions raised while designing, building and testing `scripts/sync/sync_all_upstreams.sh`, with the answers the engine gives. |
| Authority | Constitution §11.4.84, §11.4.113, §11.4.233(G), §11.4.288(D). The canonical text wins where this FAQ and the constitution disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
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
URLs in the report and on screen lose their userinfo, token-shaped strings are replaced with
`[REDACTED]`, and git is told never to prompt. The security suite checks this with a planted token. The
engine never prints credentials it did not receive in a URL; it does not read credential stores.

**8. Two runs at once?**
The second exits 2 (lock held). The lock lives in the repository's git directory and is released by the
kernel when a run ends or dies, so there is no stale lock to clean up.

**9. A remote hangs. Will the run hang?**
No. Each network call has `--timeout` (its whole process group is killed on expiry) and the run has
`--deadline`. The remote is reported `unreachable`.

**10. Why is the evidence not in my project?**
So the run never changes your work tree. `--out` inside the work tree is refused (exit 2).

**11. Is it safe to schedule?**
The examples in `scripts/sync/examples/` run `--check` only, which never changes a checkout. Installing
them is your decision; nothing installs them for you.

**12. After a constitution update, does it run the post-update hook?**
No. It prints the command (`next step (never run automatically): …`). Running code that has just been
fetched is your decision.

**13. Is it tested against GitHub or GitLab?**
Not yet. The tests use real git against real bare repositories in scratch directories, without network.
Real forges (ssh keys, rate limits, large repositories) are UNCONFIRMED until run by the operator.
