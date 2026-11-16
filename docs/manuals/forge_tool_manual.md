# forge tool manual: commands, outputs, reasons, exit codes, files

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T17:49:00Z |
| Status | active, PROVISIONAL (write paths LIVE-UNPROVEN) |
| Status summary | Reference for `scripts/forge/forge.sh` and `scripts/forge/live_probe.sh`; the §11.4.18 companion of both. |
| Authority | Tool documentation; no new anchor and no new CM-* token. §11.4.10, §11.4.113, §11.4.201, §11.4.273, §11.4.289, §11.4.18 govern. |
| Scope | Universal (§11.4.17): any project that pushes to these forges supplies its own `config/forge/hosts.tsv` as DATA. |
| Issues | none |

Guide: [multiforge_release_guide.md](../guides/multiforge_release_guide.md). FAQ: [forge_tool_faq.md](../faq/forge_tool_faq.md).

## Files

| File | Role |
|---|---|
| `scripts/forge/forge.sh` | entry point: argument and remote parsing, hosts map, command flow, read-back |
| `scripts/forge/lib/common.sh` | clean re-exec of the environment, the one output sanitiser (`fg_scrub`), output and exit helpers, validators |
| `scripts/forge/lib/credentials.sh` | token discovery (env, keys file, project .env), placeholder and charset rules, the set of every candidate token value (`fg_secrets_load`) |
| `scripts/forge/lib/http.sh` | the one HTTP client (curl, config on stdin, pin, timeouts, status-only errors) |
| `scripts/forge/providers/{github,gitlab,gitea,gitflic,gitverse}.sh` | one file per API family (contract in the header of `gitea.sh`) |
| `scripts/forge/live_probe.sh OUT_DIR [--tag T]` | LIVE read-only probe of every `upstreams/*.sh` remote (and, with `--tag`, tag-get + release-get into `readpaths.txt`), with a token-leak check and SHA256SUMS |
| `config/forge/hosts.tsv` | DATA: host, provider, API base, token variable names, note (TAB-separated) |
| `tests/forge/test_forge_*.sh`, `tests/forge/lib.sh`, `tests/forge/fixtures/` | gate-logic / unit tests, loopback fixture server, curl recorder; paired mutations |

## Options

| Option | Commands | Meaning |
|---|---|---|
| `--remote NAME` / `--url URL` | all | the remote (exactly one of them) |
| `--tag T` | tag-get, release-get, release-ensure | `[A-Za-z0-9][A-Za-z0-9._-]*`, no `..`, at most 128 characters |
| `--sha S` | release-ensure | full 40-character lower-case commit id the tag must point at |
| `--notes-file F` | release-ensure | release body (raw text, at most 1000000 bytes; a regular file, or `/dev/null` for empty notes); refused when it is the keys file or a `.env`, or when it (or `--title`) holds a candidate token value of any host (a 12-character part included) |
| `--title T` | release-ensure | default: the tag; at most 200 characters |
| `--prerelease` | release-ensure | ask for a pre-release where the forge has the flag |
| `--update` | release-ensure | change a differing existing release (otherwise FAIL `present_mismatch`) |
| `--dry-run` | release-ensure | GETs only; prints `ACTION: would-create` / `would-update` / `would-enable-releases` |
| `--enable-releases` | release-ensure (gitea) | switch the Releases unit on when it is off (one reversible PATCH, read back) |
| `--try-create-on-ambiguous` | release-ensure (gitverse) | try the create when the release list answers the ambiguous 404 |
| `--asset` | - | not implemented: USAGE |

Environment (all optional): `FORGE_HOSTS_FILE` (must be yours or root's, not a symlink, not writable by
others; its directory yours or root's and not writable by others unless sticky), `FORGE_KEYS_FILE`, `FORGE_ENV_FILE` (the default `<repository root>/.env` is read only when
`forge.sh` lies inside that repository; otherwise `NOTE dotenv_not_trusted`), `FORGE_HTTP_TIMEOUT`
(seconds, default 60), `FORGE_KEYS_TIMEOUT` (default 10), `FORGE_GITFLIC_MAX_PAGES` (default 20),
`FORGE_TRACE_PEER=1` (print a `PEER:` line per answer),
`FORGE_TEST_ALLOW_HTTP_LOOPBACK=1` (tests only: allows a `http://127.0.0.1:<port>` API base).

## Output lines (stdout)

`PROVIDER:`, `HOST:`, `REPO:`, `API:`, `TOKEN_VARS:` (detect) · `AUTH: env:NAME | keys_file:NAME | dotenv:NAME | none` ·
`REPO_STATE: exists` · `TAG: present sha=<40 hex> | present sha=unknown | absent` ·
`RELEASE: present id=<id> prerelease=<true|false|unknown> draft=<...> tag_ok=<yes|no> target=<40 hex|unknown>` ·
`RELEASE: absent` · `ACTION: created | kept | updated | releases-enabled | would-create | would-update | would-enable-releases` ·
`READBACK: ok` · `PROBE: <name> status=<code> peer=<ip>:<port> http=<v> tls_verify=<n> cert_sha256=<hex|none> subject=<s|none> request_id=<header>=<id>|none object keys=<JSON key names>` ·
`PEER: <METHOD> <path> status=<code> <the same peer fields>` (only with `FORGE_TRACE_PEER=1`; ids outside `[A-Za-z0-9._:-]` print as `unsafe`) ·
`NOTE: repo_moved canonical=<o/r> | prerelease_unverified |
prerelease_unsupported | target_unverified | target_echo_only | tag_sha_unverified | draft_unverified | draft_found | draft_lookup_unavailable | draft_lookup_first_page_only` ·
`REASON: <code>` · `RESULT: OK | FAIL | USAGE | GAP | API | UNVERIFIED-COMMIT | INTERRUPTED` (always last).
Messages and warnings go to stderr as `forge: ...`. Every line, stdout and stderr, passes the one
sanitiser `fg_scrub`, line by line: a word holding a candidate token value of any host (8 to 11
characters: matched whole), or a contiguous 12-character part of one, is printed as `unsafe` (pieces
shorter than 12 characters of a longer token are NOT caught, so a server that deliberately splits a token
can get it printed; see the guide) (a word that only shares 12 characters with a token by chance is also shown as
`unsafe`). `target_echo_only`: the release target equals `--sha`, but this forge stores the target it
was sent, so it does not show where the tag points.

## Exit codes and reasons

| Exit | RESULT | Reasons |
|---|---|---|
| 0 | OK | - |
| 1 | FAIL | `readback_mismatch`, `present_mismatch`, `tag_sha_mismatch`, `enable_releases_not_confirmed` |
| 2 | USAGE | (none), `hosts_file_invalid`, `hosts_file_insecure`, `not_implemented`, `install_broken`, `notes_is_credentials_file`, `notes_not_regular`, `notes_too_large`, `notes_contain_token`, `title_contains_token` |
| 3 | GAP | `credentials_absent:<NAMES>`, `credentials_invalid:<NAME>`, `unknown_forge`, `not_accessible`, `releases_disabled`, `releases_unsupported_or_empty`, `tag_absent_on_forge`, `readback_page_cap`, `environment_unverifiable`, `tool_missing`, `tmp_unavailable`, `keys_file_unreadable` (release-ensure: the keys file was not read to its end within `FORGE_KEYS_TIMEOUT`, so the notes could not be checked against every token) |
| 4 | API | `auth_failed`, `redirect_refused`, `unexpected_status_<code>`, `unsafe_id`, `network_<timeout|dns|refused|tls|protocol|other>` |
| 5 | UNVERIFIED-COMMIT | `commit_unverified`: release-ensure (real run and `--dry-run` alike) found no proof, before its first write, that the release is on `--sha`: neither the tag's commit nor, on GitLab only, the derived commit of a release already present (guide, "Writing a release") |
| 129 / 130 / 143 | INTERRUPTED | `interrupted`: SIGHUP / SIGINT / SIGTERM, at any point of the run (also while the keys file is read); curl stopped, temporary directory removed |

A caller reads the exit code and the `RESULT`/`REASON` lines, never a platform's own success text
(§11.4.200(2)). A GAP is never a success (§11.4.201).

## Hosts map format

TAB-separated, `#` comments. Columns: `host` (lower case), `provider` (`github|gitlab|gitea|gitflic|gitverse`),
`api_base` (`https://host[:port][/path]`, no userinfo, port 1..65535), `token_vars` (comma list of names matching
`[A-Z][A-Z0-9_]*TOKEN`), `note`. The whole file is validated on every run; a bad row or a duplicate
host is `USAGE hosts_file_invalid` with the line number (never the value). The file is the trust
boundary of the tool (it decides where each token goes): a symlink, a file writable by others, or one
owned by another user (not root), or a file in a directory owned by another user or writable by others
(not sticky), is `USAGE hosts_file_insecure`.

## live_probe.sh

`scripts/forge/live_probe.sh OUT_DIR [--tag T]` parses (never sources) every `upstreams/*.sh`
`export UPSTREAMABLE_REPOSITORY="<url>"` line and runs `forge.sh probe --url <url>` for each, GETs only,
with `FORGE_TRACE_PEER=1`. With `--tag` it also runs `tag-get` and `release-get` of T on every upstream
into `readpaths.txt`. It writes `<upstream>.txt` (output and `# rc=`), `summary.tsv`,
`tool_fingerprint.txt` (commit, `scripts_forge_dirty: yes|no`, sha256 of every file of `scripts/forge`),
`leak_check.txt` (the list of scanned files) and `SHA256SUMS`. The leak check builds the SAME value set
as the sanitiser (`lib/credentials.sh` `fg_secrets_load`: all hosts-map names, the environment, the keys
file, the `.env` files) and feeds each value's 12-character parts to `grep -F -f` through a pipe (never
an argv, never a file); it has the same 12-character boundary as the sanitiser. It first proves the instrument PER FILE: each file must show its own known
string (`RESULT:`; the summary header; `scripts/forge/forge.sh` in the fingerprint) and must not show a
random one, and `PEER` must appear in at least one file. A keys file that cannot be read to its end, or
a missing control, makes the check blind (exit 1). Any hit removes the outputs and exits 1. Exit 0
means every probe RAN; what each forge answered is in the files.

## Limits

Write paths are tested against the loopback fixture only (LIVE-UNPROVEN). No asset upload. Not wired into
`tag_and_release.sh` (proposal: [multiforge_p4_patch_proposal.md](../release/multiforge_p4_patch_proposal.md)).
Linux `/proc` is required (without it: `GAP environment_unverifiable`). Needs `bash`, `curl`, `jq`,
`timeout`, `git`.
