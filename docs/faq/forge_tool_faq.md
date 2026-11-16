# forge tool FAQ

| Field | Value |
|---|---|
| Revision | 5 |
| Created | 2026-11-12 |
| Last modified | 2026-11-16T19:30:00Z |
| Status | active |
| Status summary | Questions from building and live-probing `scripts/forge/forge.sh` (2026-11-12). |
| Authority | Tool documentation; no new anchor. |
| Issues | none |

Guide: [multiforge_release_guide.md](../guides/multiforge_release_guide.md) · Manual: [forge_tool_manual.md](../manuals/forge_tool_manual.md)

**Why does Codeberg say `releases_disabled`?** The repository's Releases unit is switched off
(`has_releases: false`), so the forge answers 404 to every release URL. Switch it on in the repository
settings, or run `release-ensure ... --enable-releases` (one PATCH, logged, read back, reversible).

**Why is GitVerse `releases_unsupported_or_empty` and not "absent"?** Its release list answers 404
`REPO_NOT_FOUND` while the repository itself answers 200. That cannot be told apart from "no releases
yet" or "releases not supported", so the tool refuses to call it absent. `--try-create-on-ambiguous`
tries the create; only the read-back decides.

**Why does GitVerse show `TAG: present sha=unknown`?** The tag exists (matching-refs finds it), but it is an
annotated tag, GitVerse answers 400 to `git/tags/{sha}`, and the fallback `commits/{tag-object-sha}`
(which normally gives the peeled commit, since 2026-11-16) did not answer with a commit id. The tool never
shows the tag object's own id as if it were the commit.

**Why `NOTE: repo_moved` on GitHub?** The remote URL names `HelixConstitution`; GitHub renamed the
repository to `constitution` and answers 301. The tool follows that one same-origin hop itself (curl
never follows redirects) and uses the canonical name.

**Why is my token ignored and `keys_file_insecure` printed?** The keys file must be a regular file you own
with mode 0600 (`chmod 600 ~/api_keys.sh`); a symlink or a group/other-readable file is never read.

**I set the variable but get `credentials_invalid`.** The value has a character outside
`[A-Za-z0-9._~+/=-]` (a quote, space or newline) or is too long. The tool never sends it, and does not
fall back to another source in its place. Fix the value.

**Can `probe` or `release-get` change anything?** No. They make GET requests only. Only
`release-ensure` without `--dry-run` writes, and only to releases (and, with `--enable-releases`, the
one repository setting).

**Is a GAP a failure I can ignore?** No. A GAP means the state could not be established or a
precondition is missing; it is never counted as success.

**Why did release-ensure end `UNVERIFIED-COMMIT` (exit 5)?** The forge did not report the tag's commit
(for example a GitVerse annotated tag), and nothing else proves the release is on `--sha`. A release
target equal to `--sha` counts only on GitLab, which derives it from the tag, and only for a release that
was there before the run; on GitHub, Gitea, Forgejo, GitVerse and GitFlic the target is just the value
that was sent (`NOTE: target_echo_only`). The verdict is fixed before the first write, so `--dry-run`
says the same as the real run. It is never turned into OK; check the commit on the forge by hand.

**Why does a field show `unsafe` (`request_id=x-request-id=unsafe`, `subject=unsafe`)?** The server sent a
value that holds a token value, or a 12-character part of one (of any host's variable), or characters
outside the safe set. The tool prints `unsafe` instead of that value. The check covers the whole value
and every contiguous 12-character part of it; a server that splits a token into pieces shorter than 12
characters is not caught (see the guide, "One output sanitiser"). Rarely an unrelated value shares 12 characters with a
token by chance; it is shown as `unsafe` too.

**Why `keys_file_unreadable`?** release-ensure checks the notes and the title against every token value
it can know of, including every `*TOKEN` the keys file sets. The keys file did not finish within
`FORGE_KEYS_TIMEOUT` seconds (default 10), so that check would be incomplete and nothing is published.
Read-only commands only warn (`keys_file_incomplete`).

**Why was my notes file refused (`notes_is_credentials_file` / `notes_contain_token` / `notes_not_regular`)?**
The notes file is the keys file or a `.env` (also through a link), or its text (or the title) holds a
token value of any host, or a contiguous 12-character part of one (a token of 8 to 11 characters is
matched whole; a token split into shorter pieces in the notes is not caught). Publishing it would leak the token; only the
variable name is shown. A FIFO, socket or device is refused without being opened (`/dev/null` is
accepted as empty notes).

**Why is the project `.env` not read (`NOTE dotenv_not_trusted`)?** The current directory is a repository
that `forge.sh` does not belong to; its `.env` is not trusted by default. Set `FORGE_ENV_FILE` to use it.

**Why `hosts_file_insecure`?** The hosts map decides which server gets which token. A map that is a
symlink, writable by others, or owned by another user (not root) is refused, and so is a map in a
directory that another user owns or that others can write to (a sticky directory such as `/tmp` is
accepted).

**What does `RESULT: INTERRUPTED` mean?** The run got SIGHUP, SIGINT or SIGTERM (exit 129, 130 or 143); the
running request was stopped and the temporary directory removed. Nothing is known about a write that
was in flight: run `release-get` to see the state.
