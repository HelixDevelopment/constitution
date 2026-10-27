# cm_gitlink_on_remote — guide

**Revision:** 1
**Last modified:** 2026-10-28

Gate `scripts/gates/cm_gitlink_on_remote.sh` (CM-GITLINK-ON-REMOTE), paired mutation test `scripts/gates/cm_gitlink_on_remote_mutation_test.sh`.

## Why
Review round 1 of the 2026-10-27 constitution landing found three nested gitlinks (claude_toolkit f79d449, docs_chain fdc3676,
token_optimizer a5bd538) that exist on no remote. Root cause: `commit_all.sh` records the commit each nested checkout is on, not the
merge result, so a nested checkout that moved ahead of its published pin (a cascade commit, a local edit) rides into the commit that
records it, and a recursive clone then cannot fetch it. The gate fails exactly that class.

## Verdicts
- PUBLISHED: the commit exists in the nested repository and some `refs/remotes/*` ref or tag contains it.
- UNPUBLISHED (exit 1): the commit exists, the repository is complete, and no remote ref or tag contains it.
- BLIND (exit 2): no nested repository or gitdir, commit object absent, no remote refs fetched, or a shallow repository with no
  containing ref (a shallow clone cannot prove absence; deepen with `git fetch --unshallow` or use `--online`). Never a PASS.
- `--online` upgrades a non-PUBLISHED gitlink to PUBLISHED when its sha is the tip of a remote ref (`git ls-remote`, 40 s bound).

## Honest boundary (section 11.4.6)
A TAG counts as published although a purely local tag would too: the offline check cannot tell a fetched tag from a locally created one;
`--online` or the review's `ls-remote` is the stronger proof. The gate is NOT wired into `post_update_hook.sh` (consumer clones leave most
nested repositories uninitialised, which would make every pull BLIND); run it before publishing a commit that records gitlinks:
`bash scripts/gates/cm_gitlink_on_remote.sh --root <constitution-root>`.

## Evidence
At the pre-fix tip `ebbace6` the gate reports 3 UNPUBLISHED (the three above) and 24 PUBLISHED; the mutation test proves FAIL for a local-only
nested commit, BLIND for the unprovable cases, and that a gate with the containment test neutered would pass the bad pin.
