# Multi-forge release guide (scripts/forge/forge.sh)

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T17:49:00Z |
| Status | active, PROVISIONAL: the read paths are LIVE-proven on all six forges (evidence below); every WRITE path (create, update, `--enable-releases`) is proven on the loopback fixture only and is LIVE-UNPROVEN until the first real cut |
| Status summary | How to check and create the platform release of a tag on GitHub, GitLab, Codeberg (Forgejo), git.m3w.org (Gitea), GitFlic and GitVerse with one tool, API keys only. |
| Authority | Tool documentation; no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.113 (never force), §11.4.201 / §11.4.273 (instrument honesty), §11.4.289 (test classes), §11.4.18 / §11.4.257 govern. |
| Scope | Operators and agents who publish a `helixconstitution-vN` release, and any consumer project that pushes to the same forges. |
| Issues | Codeberg repository has its Releases unit off; GitVerse release API answers 404 for an existing repository (see "Forge notes"). |

## What the tool does

`scripts/forge/forge.sh` is one entry point for the release APIs of every forge this project pushes to.
It talks REST over `curl` to all six; it never runs `gh` or `glab` (the existing
`scripts/release/tag_and_release.sh` keeps its own `gh` and `glab` legs). It never creates, moves or
deletes a tag (tags arrive by `git push`), never deletes a release, never pushes, never forces.

| Command | Network | What it answers |
|---|---|---|
| `detect` | none | which provider, host, repository and API base the hosts map gives for a remote |
| `probe` | GET only | HTTP status and JSON key NAMES of the repository, release list and tag list |
| `repo-exists` | GET | `REPO_STATE: exists`, or a GAP / API reason |
| `tag-get --tag T` | GET | `TAG: present sha=<commit>` / `sha=unknown` / `TAG: absent` |
| `release-get --tag T` | GET | `RELEASE: present id=... prerelease=... draft=... tag_ok=... target=...` / `RELEASE: absent` / GAP |
| `release-ensure --tag T --sha S --notes-file F` | GET, then POST/PATCH/PUT | creates the release if absent and READS IT BACK; keeps a matching one; refuses a differing one unless `--update` |

Every run ends with `RESULT: <WORD>`, before it `REASON: <code>` when there is one. Exit 0 OK, 1 FAIL,
2 USAGE, 3 GAP, 4 API, 5 UNVERIFIED-COMMIT (release-ensure only: see "Writing a release"), and
129 / 130 / 143 INTERRUPTED (HUP / INT / TERM: the running `curl` is stopped, the temporary directory
removed, and the run ends at once with `REASON: interrupted` and `RESULT: INTERRUPTED`). The full list is in the [manual](../manuals/forge_tool_manual.md).

## Quick start

```sh
# which forge is this remote? (no network)
scripts/forge/forge.sh detect --remote github

# read-only: is the tag there, and what is its release state?
scripts/forge/forge.sh tag-get     --remote codeberg --tag helixconstitution-v73.3
scripts/forge/forge.sh release-get --remote m3w      --tag helixconstitution-v73.3

# a dry run of the write: GETs only, prints the ACTION it would take
scripts/forge/forge.sh release-ensure --remote gitlab --tag helixconstitution-v73.4 \
  --sha "$(git rev-list -n1 helixconstitution-v73.4)" --notes-file entry.md --prerelease --dry-run
```

`--remote NAME` reads the URL of a git remote of the current repository; `--url URL` takes one directly
(ssh, scp form `git@host:path`, or https without any userinfo).

## Credentials

The tool needs a token only to write. It looks for the variable NAMES the hosts map lists for the host,
first usable value wins, in this order:

1. the process environment;
2. the operator keys file `FORGE_KEYS_FILE` (default `~/api_keys.sh`). It must be a regular file of
   this user with mode 0600 or stricter; otherwise it is not read and the warning `keys_file_insecure`
   is printed. It is sourced in a short-lived child shell that prints exactly one variable into a pipe;
3. the project `.env` (`FORGE_ENV_FILE`, default `<repository root>/.env`), parsed and never executed
   (`KEY=value`, optional `export`; a value wholly in single or double quotes is unquoted, an unquoted
   value loses a trailing ` # comment`, and a final CR is removed), with the same file check. The default is used only when `forge.sh` itself lies inside the
   repository of the current directory; in a foreign repository the `.env` is not read and
   `NOTE dotenv_not_trusted` is printed (give `FORGE_ENV_FILE` to use it on purpose).

A placeholder (empty, shorter than 8 characters, one repeated character, `changeme`, `xxx`, `<...>`,
`your-...`, `todo`, `dummy`, ...) counts as absent. A value with characters outside
`[A-Za-z0-9._~+/=-]` is `credentials_invalid` and stops the search: a lower source is never used in
its place. Missing for a write: `GAP credentials_absent:<NAMES>`. The output shows only where a token
came from (`AUTH: env:GITHUB_TOKEN`), never a value.

| Host | Provider | Token variable names (in order) |
|---|---|---|
| github.com | github | `GITHUB_TOKEN`, `GH_TOKEN` |
| gitlab.com | gitlab | `GITLAB_TOKEN` |
| codeberg.org | gitea (Forgejo) | `CODEBERG_GITEA_TOKEN`, `CODEBERG_TOKEN` |
| git.m3w.org | gitea | `M3W_GITEA_TOKEN` |
| gitflic.ru | gitflic | `GITFLIC_TOKEN` |
| gitverse.ru | gitverse | `GITVERSE_TOKEN` |

The map is DATA in `config/forge/hosts.tsv`; a host without a row is `GAP unknown_forge`, never guessed.

Trust boundary: the map decides which API origin receives which token, so whoever can edit it can send a
token anywhere. `FORGE_HOSTS_FILE` (default the tracked `config/forge/hosts.tsv`) is therefore refused
(`USAGE hosts_file_insecure`) when it is a symlink, writable by others, or owned by a user other than you
or root; an API base must be `https://host[:port][/path]` with no userinfo and a port in 1..65535
(`hosts_file_invalid`). The DIRECTORY that holds the map is checked too: it must be yours or root's and not
writable by others, unless it has the sticky bit (as `/tmp`: only the owner may then replace the file).
Point `FORGE_HOSTS_FILE` only at a file you control.

How the token is protected (the rules of the fix227 release tooling): the script first re-executes
itself with an EMPTY environment and rebuilds it positively (PATH, HOME, locale, TMPDIR, SSH agent;
token and `FORGE_*` names only as unexported shell variables), so no child process inherits a token,
an `xtrace`/`allexport` option, `BASH_ENV` or an unrelated secret. The token reaches `curl` as a header
line of a config read from STANDARD INPUT (`curl -K -`), never on an argv, in a URL, in a file or in a
child environment. `curl` follows no redirect, speaks https only, runs inside `timeout` (process-group
kill), and its own error text is never printed; the token is sent only to the origin of the API base
in the hosts map. With `FORGE_TRACE_PEER=1` every answer also prints a `PEER:` line (method, path,
status, resolved IP and port, HTTP version, curl's `ssl_verify_result`, sha256 and subject of the leaf
certificate, and the provider request id header when one is sent; an id outside a safe character set
is printed as `unsafe`); every `probe` line carries the same fields.

One output sanitiser (`lib/common.sh` `fg_scrub`, review finding R2-I2): EVERY line the tool prints
(stdout lines, the `REASON` line and every stderr message) passes through it. It knows every candidate
token value: the token in use, every `*TOKEN` variable of the environment, every name of EVERY hosts-map
row and every `*TOKEN` name the keys file sets (read from the keys file), and the names of the `.env`
files (parsed). A word that holds the whole value (a value of 8 to 11 characters is matched whole), or
any contiguous 12-character part of it, is printed as `unsafe` (`request_id=x-request-id=unsafe`); the
server-supplied PEER fields (request id, certificate subject, peer IP and port) are also replaced before
they are formatted. A server that reflects a token, or a contiguous piece of 12 or more characters of
it, in a request-id header or a JSON key name therefore shows `unsafe` there. A multi-line message is
scrubbed line by line. Honest boundary: a piece shorter than 12 characters of a longer token is not
caught. A server that deliberately splits a token into pieces of 11 characters or fewer (for example as
several JSON key names, or as dot-separated parts of one request id) gets those pieces printed, and the
token can be rebuilt from the output; an 11-character prefix printed anywhere is likewise not caught
(review round 3: Z1, Z2, mutant W18). Only an origin that already holds the token can do this, and
`live_probe.sh` uses the same window, so its leak check has the same boundary. False positive,
stated honestly: an unrelated string that happens to share 12 characters with a token is also shown as
`unsafe` (the tests use token values that share no 12 characters with the fixture commit id for that
reason).

## Writing a release

```sh
scripts/forge/forge.sh release-ensure --remote m3w --tag T --sha S --notes-file entry.md --prerelease
```

Before any request is written, the notes file and the title are checked: a notes file that IS the keys
file, the `.env` the search uses or the `.env` of the current repository (also through a symlink or a
hard link) is `USAGE notes_is_credentials_file`; a notes file that is not a regular file (a FIFO, a
socket or a device; only `/dev/null` is accepted, as empty notes) is `USAGE notes_not_regular`, refused
without opening it; notes over 1000000 bytes are `USAGE notes_too_large` (the read stops after
1000001 bytes); notes or a title holding any candidate token value of ANY host (the same set as the
sanitiser above, a 12-character part included) are `USAGE notes_contain_token` /
`title_contains_token`, naming the variable only. When the keys file cannot be read to its end within
`FORGE_KEYS_TIMEOUT`, that set is incomplete and release-ensure stops with `GAP keys_file_unreadable`
(the read-only commands print the warning `keys_file_incomplete` and go on). The scanned copy is what is
sent: the tool writes the checked text to its private directory and sends that copy, so a notes file
changed on disk during the run changes nothing.

Order: the repository must answer 200; the tag must be ON the forge and point at `--sha`
(`tag_absent_on_forge` / `tag_sha_mismatch` otherwise); then the release:

- absent: POST, then a READ-BACK that must show the release with this tag, not a draft, the requested
  pre-release flag where the forge has one, and the commit where the forge reports one
  (`ACTION: created`, `READBACK: ok`). A create the forge accepted but the read-back cannot confirm is
  `FAIL readback_mismatch`;
- present and matching: `ACTION: kept` (idempotent, a re-run is safe);
- present and different: `FAIL present_mismatch`, unless `--update` (PATCH/PUT, then the read-back).

A value the forge does not report is never claimed: `NOTE: prerelease_unverified`,
`NOTE: target_unverified` (the target the forge reports is not a commit id, for example the branch name
the live GitHub release of v73.3 carries; the tag's commit was checked instead), `NOTE: tag_sha_unverified`, `NOTE: prerelease_unsupported` (GitLab has no flag).

OK needs a checked commit, decided BEFORE the first write from read-only state only (review finding
R2-I1), so a real run and its `--dry-run` give the same verdict:

- (a) the tag's commit, as the forge reports it, equals `--sha`; or
- (b) the release was already present, its target is a commit id equal to `--sha`, AND the forge derives
  that target from the tag. Only GitLab does (`commit.id` of a release is the commit the forge resolves
  from the tag). GitHub documents `target_commitish` as "unused if the Git tag already exists", Gitea,
  Forgejo and GitVerse store it as it was sent, and for GitFlic it is UNCONFIRMED whether `commitId` is
  derived (not live-proven), so on those forges a target equal to `--sha` is only an echo of a request
  field and proves nothing: `NOTE: target_echo_only`.

A read-back after the tool's own write never raises the verdict: the tool sent the target itself, so
reading it back is not evidence. When neither (a) nor (b) holds, every release-ensure path,
`--dry-run` included, ends `RESULT: UNVERIFIED-COMMIT` (exit 5, `REASON: commit_unverified`), never OK.
There is no flag to turn it into OK: check the commit by hand.

Every path of release-ensure that can end OK, with the source of its verified commit:

| Path | Lines printed | Verified commit from |
|---|---|---|
| present and matching | `ACTION: kept` | (a), or (b) on GitLab |
| present, differing, `--update` | `ACTION: updated`, `READBACK: ok` | (a), or (b) on GitLab (decided before the PATCH/PUT) |
| absent, created | `ACTION: created`, `READBACK: ok` | (a) only |
| create answered "exists" (422 `already_exists`), then matching | `ACTION: kept` | (a) only (the state was read after a write) |
| `--enable-releases`, then created | `ACTION: releases-enabled`, `ACTION: created` | (a) only |
| `--try-create-on-ambiguous` (GitVerse) | `ACTION: created` | (a) only |
| `--dry-run` of any of these | `ACTION: would-...` | the same rule as the real run |

All of them end in one function, `fg_end_ensure` in `forge.sh`, the only `fg_end OK` of release-ensure
(test S1 in `tests/forge/test_forge_gitverse.sh` counts it). The other `fg_end OK` calls of `forge.sh`
belong to the read-only commands `detect`, `probe`, `repo-exists`, `tag-get` and `release-get`.

GitHub hides drafts from the get-by-tag call: after a 404 the first page of the release list (100
items) is searched for a draft of the tag (`NOTE: draft_found`, then the draft is a mismatch);
`NOTE: draft_lookup_unavailable` / `draft_lookup_first_page_only` say when that search could not be
complete. A 422 on create counts as "exists" only when the answer says `already_exists`.

## Forge notes (measured 2026-11-12, read-only)

| Forge | Note |
|---|---|
| GitHub | `HelixDevelopment/HelixConstitution` answers 301 to `HelixDevelopment/constitution`; the tool follows that ONE same-origin hop itself and prints `NOTE: repo_moved canonical=...`. |
| GitLab | A release is addressed by its tag (dots included); no pre-release flag. |
| Codeberg | The repository's Releases unit is OFF (`has_releases: false`), so every release URL answers 404: `GAP releases_disabled`. `--enable-releases` makes the one reversible settings change `PATCH /repos/{o}/{r} {"has_releases":true}`, logs `NOTICE: enabling the Releases unit`, reads it back (`FAIL enable_releases_not_confirmed` if it did not take), then continues. Undo: repository Settings, Units, Releases. |
| git.m3w.org | Gitea; full read path proven (release, tag, target commit). |
| GitFlic | No get-by-tag: release and tag lookups page through the lists (50 per page, at most `FORGE_GITFLIC_MAX_PAGES`, default 20; reaching the cap is `GAP readback_page_cap`, never "absent"). gitflic.ru allows about 500 requests per hour. |
| GitVerse | `GET .../releases` answers 404 `REPO_NOT_FOUND` for a repository that answers 200: indistinguishable from "no release" or "unsupported", so it is `GAP releases_unsupported_or_empty`, never "absent" and never success. `--try-create-on-ambiguous` attempts the create, and only the read-back decides. `git/tags/{sha}` and `/tags` answer 400, so an annotated tag's commit cannot be read: `TAG: present sha=unknown`. |

## Evidence

- LIVE, read-only (GET only, real forges, re-run 2026-11-12 after the round-2 fixes):
  [docs/qa/multiforge_2026_11_12/](../qa/multiforge_2026_11_12/) holds one probe output per upstream
  (each answer with its `PEER:` line: resolved IP and port, certificate sha256 and subject, request id),
  `readpaths.txt` (tag-get and release-get of `helixconstitution-v73.3` on all eight upstreams of the six
  forges; the `vasic_digital_github` mirror answers 404, `GAP not_accessible`), `summary.tsv`,
  `leak_check.txt` (no token value in any of the files listed there, with positive and negative
  controls) and `SHA256SUMS`. Produced by
  `scripts/forge/live_probe.sh docs/qa/multiforge_2026_11_12 --tag helixconstitution-v73.3`.
- Gate-logic / unit (§11.4.289(C)(2)): `tests/forge/test_forge_*.sh` against a loopback fixture server
  (`tests/forge/fixtures/forge_fixture_server.py`). They prove how the tool decides on given answers,
  including every write path; they do not prove that a real forge accepts a write.
- Paired mutations: `tests/forge/test_forge_mutations.sh` (77 mutants: 18 own; 16 of the 18 of the
  independent review of 2026-11-12 (N02 and N03 are equivalent); 10 for the round-2 fixes (R03 is retired,
  its successor is T01); 15 of the 16 of the review of round 2 (X07 is equivalent); 18 for the round-3
  fixes. The reasons are in the script header; each mutant must make its test file fail).
- `live_probe.sh` itself is tested hermetically (tests LP1 to LP3 in `test_forge_credentials.sh`: a copy
  of the tree probing the loopback fixture; a stub `forge.sh` that prints the token must be caught and
  its files removed; a stub that prints nothing must be reported blind). Each run of `live_probe.sh`
  writes `tool_fingerprint.txt` (commit, whether `scripts/forge` was modified, sha256 of every file of
  `scripts/forge`), and its leak check proves each file with its own control needle (`RESULT:`, the
  summary header, the fingerprint's file list) before it trusts a zero.

## Honest limits

- Every write path (create, update, `--enable-releases`, `--try-create-on-ambiguous`) is LIVE-UNPROVEN:
  no forge was written to while building this tool. The first real cut is the first live proof.
- Release assets (`--asset`) are not implemented (usage error).
- The tool is not yet wired into `scripts/release/tag_and_release.sh`; the proposal is
  [docs/release/multiforge_p4_patch_proposal.md](../release/multiforge_p4_patch_proposal.md).
- GitVerse release support is unknown (see the table); Codeberg needs the Releases unit switched on.
- The leaf-certificate fields (`cert_sha256`, `subject`) are parsed from curl's `%{certs}` text. The
  parser is unit-tested with a real self-signed test certificate made by `openssl` in a crafted file of
  the same layout (test G16), because the loopback fixture has no TLS; that the real curl output has
  that layout is shown only by the live evidence above.
- GitFlic: whether a release's `commitId` is derived from the tag is UNCONFIRMED, so it is not used as
  proof of the commit (rule (b) above); a live read-only check would be needed to change that.
- A signal that arrives while the keys file is still being read ends the run at once with
  `RESULT: INTERRUPTED`; the child shell that reads the keys file then ends on its own within
  `FORGE_KEYS_TIMEOUT` seconds.
