# cm_gitlink_on_remote — guide

**Revision:** 2
**Last modified:** 2026-10-28

Gate `scripts/gates/cm_gitlink_on_remote.sh` (CM-GITLINK-ON-REMOTE), paired mutation test `scripts/gates/cm_gitlink_on_remote_mutation_test.sh`.

## Why
Review round 1 of the 2026-10-27 constitution landing found three nested gitlinks (claude_toolkit f79d449, docs_chain fdc3676,
token_optimizer a5bd538) that exist on no remote. Root cause: `commit_all.sh` records the commit each nested checkout is on, not the
merge result, so a nested checkout that moved ahead of its published pin (a cascade commit, a local edit) rides into the commit that
records it, and a recursive clone then cannot fetch it. The gate fails exactly that class.

## Verdicts
- PUBLISHED: the commit exists in the nested repository and is contained in a remote-tracking ref `refs/remotes/<R>/*` of a remote R whose URL equals the `.gitmodules` URL of that gitlink. Local tags, local branches and the refs of a foreign or stale remote never count (review round 2, R2-F5; each is a mutation-test case).
- UNPUBLISHED (exit 1): the commit exists, the repository is complete, and no such ref contains it.
- BLIND (exit 2): no nested repository or gitdir, commit object absent, no matching remote-tracking refs (a bare clone keeps remote branches under `refs/heads`; fetch `+refs/heads/*:refs/remotes/origin/*` or use `--online`), or a shallow repository with no containing ref. Never a PASS.
- `--online` ignores the local remote-tracking refs and re-validates against `git ls-remote --heads --tags <url>` (40 s bound): PUBLISHED only when the sha equals a listed tip or is an ancestor of a listed tip whose object is present locally; if some listed tips are not fetched the verdict is BLIND, otherwise UNPUBLISHED.
- `--rev <commit>` judges the gitlinks of that commit (`git ls-tree -r`) instead of the index; a pre-push run should use `--rev HEAD`.

## Honest boundary (section 11.4.6)
Offline, the gate trusts the local remote-tracking refs of the matching remote as of its last fetch: a branch the remote has since lost still counts. Use `--online` (after fetching) for the strong check. The gate is NOT wired into `post_update_hook.sh` (consumer clones leave most nested repositories uninitialised, which would make every pull BLIND) and is not yet bound to a pre-build seam: run it before publishing a commit that records gitlinks: `bash scripts/gates/cm_gitlink_on_remote.sh --root <constitution-root> --rev HEAD --online`.

## Evidence
At the pre-fix tip `ebbace6` the gate reports 3 UNPUBLISHED (the three above) and 24 PUBLISHED; the mutation test proves FAIL for a local-only
nested commit, BLIND for the unprovable cases, and that a gate with the containment test neutered would pass the bad pin.

Revision 2: the mutation test has 17 checks, including a local tag, a local branch, a foreign remote ref, a HEAD-versus-index split, `--online` on an unpublished commit, and mutants (local branches counted as published; `--online` upgrading on any ls-remote output) that each pass the bad pin where the real gate refuses.
