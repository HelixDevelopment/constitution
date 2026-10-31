# Release publishing guide

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-31 |
| Last modified | 2026-10-31T11:30:00Z |
| Status | draft |
| Status summary | How a tagged release is published to GitHub, GitLab and the private Gitea. Built from the header of `scripts/release_publish_gitea.sh` and its `--help`; no live publish was made for this document. |
| Authority | Tool documentation; no new anchor. §11.4.113 (no force-push), §11.4.10 (credentials), §11.4.201 (a skip is never a success), §11.4.18, §11.4.257 govern. |
| Scope | Operators who cut a `helixconstitution-vN` release. |
| Issues | none |

## Tag rules

- Release tags are named `helixconstitution-vN` or `helixconstitution-vN.M` (the installer and updater pick the newest of these; `-rc` pre-release tags are never chosen by default).
- Use an annotated tag (`git tag -a`). Never retag an existing tag and never force-push (§11.4.113); a mistake is fixed by a new tag.
- Push the tag to every upstream first; the release is created for an existing tag.
- Until the tag is pushed, the installer's default `--ref` and the raw-URL snippets in the [README](../../README.md) have nothing to serve.

## GitHub and GitLab

Use the forge CLIs: `gh release create <TAG> --notes-file <FILE>` for GitHub and `glab release create <TAG> --notes-file <FILE>` for GitLab. These two commands are standard CLI usage and were not run for this guide.

## Gitea (git.m3w.org)

The private `m3w` Gitea has no CLI on our hosts, so `scripts/release_publish_gitea.sh` calls its REST API. It is safe to re-run (last write wins for title, notes and the draft / prerelease flags).

```bash
M3W_GITEA_TOKEN=... scripts/release_publish_gitea.sh --tag helixconstitution-v73 --dry-run
M3W_GITEA_TOKEN=... scripts/release_publish_gitea.sh --tag helixconstitution-v73
```

Options: `--notes-file FILE` or `--generic-notes`, `--title TITLE` (default: the tag), `--base-url URL` (default `https://git.m3w.org`), `--repo OWNER/REPO` (default `Helix/constitution`), `--token-var NAME` (the NAME of the environment variable that holds the token), `--prerelease`, `--draft`, `--dry-run`.

- Notes default to the `CHANGELOG.md` section whose heading is exactly `## TAG` or `## [TAG]`. With no such section the script refuses (exit 3) unless `--notes-file` or `--generic-notes` is given; it never publishes an `[Unreleased]` or `[vNEXT]` section under a tag.
- The token is read from the environment only (never argv, never printed), validated against a strict charset, kept out of child environments and sent through a 0600 curl config; curl runs with `-q`, no redirects and a protocol allow-list. Put the token in the environment by variable name; do not write its value in files or docs.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | published or updated |
| 2 | usage |
| 3 | precondition missing or refused: token variable unset (reported as `SKIPPED-NO-TOKEN`), bad token charset, tag not in local git, `jq` or `curl` missing, no matching changelog section |
| 4 | API or network failure |

`SKIPPED-NO-TOKEN` is never success: a release that was skipped for a missing token is not published (§11.4.201). Honest limit: this guide was written from the script's header and `--help`; a live publish is UNCONFIRMED.

Related: [installer manual](../manuals/installer_manual.md), [troubleshooting](troubleshooting_guide.md).
