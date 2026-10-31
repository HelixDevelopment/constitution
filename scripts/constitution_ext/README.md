# constitution_ext — extension engine

| Field | Value |
|---|---|
| Revision | 9 |
| Created | 2026-10-29T00:00:00Z |
| Last modified | 2026-10-30T00:00:00Z |
| Status | draft (workstream E1 of docs/design/constitution_extensions_plan.md) |
| Status summary | Engine and its test suites implemented; not yet wired into `/constitution`, the installer or the post-update hook (E2, E5). |
| Authority | docs/design/constitution_extensions_plan.md §3, §5, §8 |
| Scope | scripts/constitution_ext/*, tests/extensions/* |
| Issues | see "Honest limits" |

## Files

| File | Role |
|---|---|
| `constitution_ext.sh` | Bash entry point and the user documentation (`--help` prints its Usage block). Checks for python3 >= 3.8 and execs the engine with `python3 -I`. |
| `ext_engine.py` | All commands, the manifest schema, security rules R1-R22, lock/wiring/catalog state, the local state record, journal + recovery. |
| `ext_yaml.py` | Strict parser and deterministic emitter for a restricted YAML subset (no PyYAML/yq dependency). |

## Layout

```
<root>/extensions/<id>/                bundled (tracked in the constitution)
<root>/extensions/_installed/<id>/     installed by `add`; excluded through the checkout's info/exclude
<project>/.constitution/extensions.lock.yml      tracked by the consumer
<project>/.constitution/extensions.wiring.yml    shims created by `wire`; project-relative, safe to commit
<project>/.constitution/extensions.catalog.json  imported catalog (revocations honoured)
<project>/.constitution/extensions.audit.log     one JSON line per real change (timestamps)
<project>/.constitution/extensions.txn           journal; present only while a transaction is in flight
<project>/.constitution/extensions.state/        LOCAL, git-ignored: key (0600), one HMAC record per lock entry,
                                                 wiring.json (HMAC record of the wiring entries this checkout made)
<project>/.constitution/.gitignore               generated: extensions.txn, *.tmp-*, extensions.state/
```

The engine maintains `<project>/.constitution/.gitignore` idempotently (it only appends missing
lines). The lock, wiring file, catalog and audit log stay trackable.

## Transactions

`add`: take the lock (below) → re-check every precondition under it → validate in place (local
dirs) or in a hardened staging clone (git) → consent → copy into
`_installed/.staging-<pid>-<8hex>/tree` (regular single-link files and dirs only, modes 0644/0755,
written with `O_EXCL|O_NOFOLLOW`) → write `CHECKSUMS.sha256` → re-verify the staged digest →
journal (`op`, `id`, `final`, `sha256`, signed state record) → `rename` into place (an `OSError`
here drops the journal and fails cleanly) → lock + state record → drop journal → verify again.
`remove`: unwire → journal (`aux` = `_installed/.trash-<pid>-<8hex>`) → `rename` into trash →
lock + delete the state record → `safe_rm_rf` → drop journal.
`enable`, `disable` and `lock` write the lock and the changed state records through a `commit`
journal, so an interrupted run rolls the records forward when the lock already matches.

Locking (R13): every command that reads or writes state takes an exclusive `flock` on the project
directory and on the constitution root directory (which exists even before `<root>/extensions/`
does) for the whole run; `add` takes it before any check, so two
concurrent `add`s of the same id serialise and the second one sees the first one's result.

Recovery (R7, R12) runs under the lock, only from a journal that validates: `final` must be exactly
`<root>/extensions/_installed/<id>` (id matching the id rule), a remove's `aux` must be a
`.trash-<pid>-<8hex>` directory name in `_installed/`, and the journal must be a JSON object.
An interrupted `add` is rolled back (its tree deleted) only when the lock has no entry for the id;
when the lock has the id with the journal's `sha256`, the state record is rolled forward; when the
lock has the id with a DIFFERENT sha256, nothing is deleted and a warning is printed. An interrupted
`remove` is rolled back (trash renamed back) when the lock still has the id, completed otherwise.
A journal that does not validate is never acted on: a loud WARNING is printed, nothing is deleted
or renamed, and `add`/`remove` refuse until a person inspects and deletes it. Staging/trash
directories are cleaned only when their name matches the strict pattern, they are real directories
(not symlinks) and their owning pid is dead.

## Security rules added by the 2026-10-29 review (R11-R19)

| Rule | What it enforces |
|---|---|
| R11 | Every wiring-file entry is validated before any shim is touched: `root` and `path` must be normalised project-relative paths (an absolute path is the old, non-portable format and is refused with a message to delete the entry and wire again), `path` must equal the shim path for its agent, `root` and command (command matching the id rule), `root` and the shim directory must resolve inside the project, a Claude link text must be the relative path from the shim's directory to the consented snapshot `.constitution/extensions.snapshots/<id>/<command>/<sha256>` recorded in the entry (I2; the old format, a link to the bundled or installed `<tree>/commands/<command>` with no sha256, is still accepted so it can be unwired, and `verify` flags it), a file entry needs a sha256. An invalid entry makes `unwire`, `remove`, `disable`, `wire` and `verify` refuse (exit 5) and touch nothing. `wire --target` must resolve inside the project, no parent of a shim may resolve outside it, and a recorded shim edited after wiring is never overwritten (exit 3). |
| R12 | Journal validation (see Recovery). Round-1 review of E1: the rename that rolls back an interrupted remove is itself bounded (both ends directly inside `_installed`, the trash a real directory of this user, never a link); a tree copy stops reading at the per-file and tree caps even when a file grows during the copy. |
| R13 | One exclusive lock for the whole command (see Locking). |
| R14 | Trees: any `.git` path component at any depth (case-insensitive) is refused, as is any directory holding `HEAD` + `config` + `objects/` (a bare repository); files with more than one hard link are refused; more than 2000 directories are refused. For git sources the clone's `.git` is removed from the staged copy only after checkout. |
| R15 | Every git call runs with a minimal environment (only PATH, HOME, TMPDIR, SSH_AUTH_SOCK, SYSTEMROOT kept; every `GIT_*` dropped; `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`) and `-c core.hooksPath=/dev/null -c core.symlinks=false -c core.fsmonitor=false -c core.attributesFile=/dev/null` plus a protocol allow-list (file, https, ssh; `ext` never). Before checkout the clone gets `.git/info/attributes` = `* -filter -text -ident -diff -merge -export-subst -working-tree-encoding`. A commit containing a symlink (mode 120000) or a submodule (160000) is refused before checkout. Consequence: the user's global git config, `GIT_SSH_COMMAND` and credential helpers configured there are NOT used for clones. |
| R16 | Source URLs: only `https://`, `ssh://`, `file://` and `git@host:path`; no `::` transport helpers; no userinfo except a plain ssh user name (`ssh://git@host/...`); no secret-shaped value. Applies to catalog release URLs too. A local source path that looks like a secret is refused before anything is written. |
| R17 | Local state record (see below). |
| R18 | State files (lock, wiring, catalog, key, records, audit log, `.gitignore`, `info/exclude`) are read and written with `O_NOFOLLOW`; `.constitution/` and `extensions.state/` must be real directories. |
| R19 | Test seams (`CONSTITUTION_EXT_TEST_MODE`/`_KILL_AT` kill points, `CONSTITUTION_EXT_CONSTITUTION_VERSION`) are inert unless `CONSTITUTION_EXT_TEST_NONCE` (32-128 hex) equals the content of `<parent of the project>/.constitution-ext-test-nonce`, a 0600 file owned by the user. Outside such a sandbox `CONSTITUTION_EXT_CONSTITUTION_VERSION` is refused with a loud warning (exit 3). |
| R20 | Wiring provenance. `wire` writes `extensions.state/wiring.json`: the entries it created, HMAC-signed with the R17 key. An entry is acted on (overwritten by `wire`, deleted by `unwire`/`remove`/`disable`) only when it is in that signed record, or it is a Claude symlink (its text is engine-computed, R11, so unlinking it never deletes user content), or the file it names carries the marker line `# managed-by: constitution_ext id=<id> command=<cmd>` that the engine writes into every file shim. An entry that is none of these and whose file still has the recorded sha256 is UNBOUND: the command refuses (exit 5) and touches nothing, and `verify` reports it. A record that fails its HMAC binds nothing and is reported by `verify`. This closes the forged-entry attack (a committed or merged wiring file naming the user's own `.opencode/commands/x.md` with its real hash, which `unwire` would otherwise delete). Entries whose id is not in the lock are reported by `verify`. |
| R21 | Agent-side constructs in every file an agent can see: every file below `commands/<name>/` (a Claude link exposes the whole directory, not only `SKILL.md`) and each skill file. Shell execution: `!{...}`, `` !`...` ``, and a front-matter key `allowed-tools` or `hooks` (compared after lower-casing and removing `-` and `_`, so `allowed_tools`, `Allowed-Tools` count; nested keys count too). File injection: `@{...}` and every `@` at the start of a token that is followed by a non-space character (`@path`, `@~/x`, `(@x`, `"@x`, `@mention`, `@decorator`): the class is defined by the token boundary, not by what follows, because the agent's own parsing rules for `@` are not documented. Only an `@` inside a word (an e-mail address, `a@b`) and an `@` followed by whitespace or the end of the text do not count. The test enumerates every ASCII non-word prefix plus tab, newline, NBSP, U+3000 and U+201C against 13 targets in 3 wrappers, with control needles. Each file that uses one must belong to a command or skill listed under `capabilities.agent_shell` / `capabilities.reads_files`. The scan fails closed: a file that is not UTF-8, cannot be read, is a symlink, FIFO or other non-regular file, or lives in an unreadable directory is a refusal, never skipped. Front matter is parsed, not matched: a file whose text (after leading whitespace) starts with `---` must open with an exact `---` first line, close with an exact `---` line, contain no byte-order mark and no carriage return in the block, and parse in the strict YAML subset (no quoted or complex keys, no flow mappings); anything else is refused, so a key cannot hide behind a spelling the agent accepts (CRLF, BOM, `"allowed-tools"`, `{allowed-tools: ...}`, `? allowed-tools`, a lone CR that turns a comment into a line break). `validate`/`add`, `enable`, `wire`, `verify` and `lock` (enabled bundled entries) apply it; `wire` renders shims through the same front-matter reader. Declared constructs are shown at consent as `agent-shell:<name>` / `reads-files:<name>` with a note. |
| R22 | MCP launch commands and server entries (round 7: allow-lists only). The MCP file must be `{"mcpServers": {<key>: <entry>}}` and nothing else (parsed, duplicate keys refused, nesting at most 64, at most 64 launchers and 16 KiB of argv). An entry is exactly one of: (a) **stdio**, it has `command`; without `capabilities.shell` for the server it may carry only the keys `command`, `args`, `env`, `cwd`, `type`, `transport`, `description`, `timeout`, `disabled`, `name` (any launcher-like key such as `run`, `script`, `argv`, `exec` is refused), `type`/`transport` must be `stdio`, and it never carries an endpoint key (`url`, `headers`, `endpoint`, ...), shell consent or not; it may start only a regular file inside the extension (relative path with `/`) or one of `python3`, `node`, `ruby`, `perl` with allow-listed options and a regular in-tree file as first operand (an in-tree file is a real file reached through real directories: a symlink on the way, or a directory where a file is needed, is refused); arguments are plain tokens, and neither an argument nor any `=`-separated part of an `--opt=value` may be absolute, `~`-relative or contain `..`; (b) **remote**, it has no `command`: keys only `type`, `transport`, `url`, `headers`, `description`, `timeout`, `disabled`, `name`; `type` http, sse or streamable-http; `url` is `https://host[:port]/path` without userinfo, query or fragment; that `host[:port]` must be listed in the `provides.mcp[].network` of the same-named server (whose `transport` is `http`) AND in `capabilities.network`; every header value is `${NAME}` (optionally `Bearer ${NAME}` or `Basic ${NAME}`) with `NAME` in the server's `env_vars`. `capabilities.shell` never admits a remote entry; every other shape (no `command` and no `url`, non-object entries, other top-level keys) is refused. **Environment names** are an allow-list of names inert by construction: a name must end in `_KEY`, `_TOKEN`, `_URL`, `_ENDPOINT`, `_REGION`, `_MODEL`, `_ID`, `_NAME`, `_HOST`, `_PORT`, `_PROJECT` or `_WORKSPACE` and must not be a loader, runtime-option or configuration-file name (`LD_*`, `OPENSSL_*`, `GLIBC_*`, `NODE_*`, `PYTHON*`, `PATH`, `DOCKER_*`, ... case-insensitive); every other name, in the file's `env` and in the manifest's `env_vars`, is refused unless `capabilities.shell` lists the server, and then it is in the consent list as `env-code:<NAME>`. A value is a `${NAME}` reference or a plain token without a path separator; only a `*_URL` / `*_ENDPOINT` name may hold an `http(s)://` URL. `cwd` must be a directory inside the extension; `envFile` needs `capabilities.shell`. Shells, wrappers, package runners, other interpreters, inline code, PATH programs and absolute paths are refused unless `capabilities.shell` lists the server. A secret-looking key or value anywhere in MCP, hook or config JSON is refused like in manifests, and argv is redacted in consent output, lock and `info`. The consent list names every server key (`mcp-server:`), every remote endpoint (`mcp-endpoint:`) and header name (`mcp-header:`). For an extension with hooks, MCP servers or `capabilities.executes` the consent also carries `tree-sha256:<hex>` over every file of the EXTENSION tree: a change to any file inside it that a launch can load (for example `mcp/server.js`) changes the consent. It does NOT cover what a launched program reads from outside the tree (system libraries, configuration reached by an absolute path, the user's environment); R22 keeps such reads out by refusing absolute paths and non-inert environment names, and a server declared in `capabilities.shell` is outside that promise. |
| I2 (round 5) | A Claude shim is a link to a snapshot copy of the command directory, `.constitution/extensions.snapshots/<id>/<command>/<sha256>`, never to the live extension tree. `wire` computes the digest before its checks, copies the directory to a temporary name, and renames it into place only when the copy, the recorded digest and the source digest all match; an existing snapshot is reused only when it is still intact. A later change of the bundled or installed tree therefore does not reach the agent until `wire` runs again, and `wire` re-runs every check first. `verify` reports a changed or missing snapshot and an old-format live link. Unused snapshots are removed by `wire` and `unwire`. Snapshots are tracked (not git-ignored) so a clone's links resolve; their temporary names are ignored. |
| I3 (round 5) | Read-only commands (`list`, `info`, `verify`, `validate`) never recover or delete: they report a pending journal (NOTE) or an invalid one (WARNING) and change nothing. A mutating command does not collect staging directories while the journal is invalid. A `.trash-*` directory is deleted or restored only by the journal that names it; any other trash directory is left in place with a NOTE (on a shared root it may belong to another project's interrupted `remove`). |
| R23 | Root and project discovery (round 7). The constitution root is found only (1) with `--root`, (2) from `CONSTITUTION_DIR`, or (3) from the place the engine itself lives: `<root>/scripts/constitution_ext` next to a `Constitution.md` (the real path is used). The current directory is NEVER searched: there is no walk up from it, so a symlinked ancestor can no longer lead to a foreign project; without any of the three the command exits 3 and says to pass `--root`. A project that was discovered (no `--project-root`) must be the git top level of the current directory (real paths compared) before any command that can write is allowed to start; otherwise exit 3 with nothing written. `--project-root` is the operator's explicit choice and is not second-guessed. |
| M1-M5 (round 5) | M1: every byte the engine prints passes one output sink that escapes control, bidi (U+202E), C1 (U+009B) and other non-printing characters except newline and tab. M2: the rendered Gemini/Qwen shim is scanned again for R21 constructs (for example `!$ARGUMENTS` that becomes `!{{args}}`), and wire refuses an undeclared one. M3: a `lock` that leaves entries for re-consent says `lock PARTIALLY written` and exits 3; `lock written:` is printed only when every entry was refreshed. M4: copied and hashed files are opened with `O_NOFOLLOW` and `O_NONBLOCK` and checked to be regular after opening, so a file swapped for a FIFO cannot block the copy. M5: JSON nested too deeply (catalog, journal, wiring record, state record, MCP file) is a reasoned refusal, not a crash. |
| Other | `wire` refuses an extension revoked by the imported catalog (exit 3) and one whose capabilities changed since consent (exit 5), like `enable` does. A git source pinned with `--sha` also needs `--sha256` (the content digest `validate` prints) or a `--waiver-id`. `--waiver-id` values that look like a token (known prefixes, secret patterns, or 20+ characters mixing cases and digits) are refused (exit 2), because the id is written to the tracked lock and audit log. URLs with a credential-like query parameter (`token`, `access_token`, `key`, `password`, `sig`, ...) are refused; every URL in an error or dry-run message is redacted (userinfo and query values become `<redacted>`). Every state file (lock, wiring, catalog, audit log, journal, `.gitignore`, key, wiring record) is checked BEFORE any change: a symlink or other non-regular file makes the command exit 5 with nothing changed. The consent capability list is always printed on stderr, so `--json` cannot hide it; it starts with the trust tier (`builtin`, or the catalog's/`community`) and the waiver id (or `none`) the grant is made under, and then lists, besides the capabilities, every MCP launch argv (`mcp-command:<server>=["prog","arg"]`, and `mcp-command:<server>/<json path>=...` for commands inside the MCP file), every env var name (manifest `env_vars` and the keys of `env` mappings in the MCP file), `shell:<server>`, and `sha256:<relpath>=<hex>` for every bound file: hook scripts, MCP files, `capabilities.executes` files and every file below a command or skill listed in `agent_shell`/`reads_files`. A change to any of these is a change of the consent list: `verify` fails, `wire` refuses, and `enable` asks again. The interactive prompt opens `/dev/tty` unbuffered and accepts only `y` or `yes`. `verify` escapes lock values (`disp()`) before printing them. |
| R2/R3 | Names and string values containing C0/C1 controls, Unicode format characters (Cf: bidi overrides, zero-width joiners, so ZWJ emoji sequences are refused), line/paragraph separators, surrogates or private-use characters are refused; refused values are escaped (`\uXXXX`) when displayed. Integers are capped at 18 digits and semver parts at 9 digits. A manifest may declare `trust_tier` only as `community`; the tier shown by `info` is assigned by the engine (`builtin` for bundled) or by the catalog (`vetted`/`community`). |

## Local state record (R17) and its limits

On every change the engine writes `<project>/.constitution/extensions.state/<id>.json`: the lock
entry plus an HMAC-SHA256 over it with a random per-project key (`extensions.state/key`, mode 0600,
directory 0700). Both are git-ignored. `verify` compares each lock entry with its record and exits 5
naming the differing field (`enabled`, `consent`, `waiver_id`, `source`, ...), a record that fails
its HMAC, a missing record or a missing key. `enable` refuses (exit 5) over a tampered entry but
re-consents when the record is merely missing (fresh clone); `wire` refuses on any mismatch; `lock`
does not refresh a mismatched bundled entry; `disable` still disables but does not sign the
tampered entry.

Bound content (I3): when a constitution update changes an ENABLED bundled extension so that its
consent list differs (a new MCP command, a changed hook script, a changed exposed shell command) or
it no longer passes R21/R22, `lock` refuses to refresh that entry (exit 3, naming `enable <id>`) and
still writes the others; `verify` and `wire` fail until `enable <id>` shows the new list and records a
new consent together with the new sha256 and version. A disabled bundled entry is refreshed by
`lock` as before (`enable` checks it). An installed extension's tree can never change in place: a
different digest is a verify failure, and a new version is installed with `remove` + `add`.

The lock records a local source as `source: {kind: dir, base: project, location: <path relative to
the project>}` when the directory is inside the project, so the lock stays portable; a directory
outside the project is recorded with `base: absolute` and its absolute path. URLs use `base: url`.

## Clones and committed wiring

Wiring entries and Claude link texts are project-relative, so the lock and wiring file can be
committed. In a fresh clone (tested: wire, commit, `git clone --recurse-submodules`, then commands in
the clone):

- `extensions.state/` is git-ignored, so the clone has no records: `verify` exits 5 until each
  enabled entry is re-consented with `enable <id> --yes` (R17, by design). Bundled extensions then
  verify (exit 0).
- `_installed/` is git-ignored too, so installed trees are absent: `verify` and `enable` say so with
  an actionable message (the tree is missing because `_installed/` is git-ignored; reinstall with the
  pins in the lock, and the number of wired shims that point at it). The dangling Claude link is not
  reported as "outside the project".
- `unwire --agent all` and `disable` work in the clone (exit 0): Claude links are recognised by their
  engine-computed text, and file shims by the managed-by marker the engine wrote into them (the clone
  has no signed wiring record). Wiring files written by an older engine version (absolute paths) are
  refused with a message to delete the entry and wire again.

Honest boundary (UNCONFIRMED threat model): a user who can write both the tracked lock and the
local state directory can forge both (the key sits next to the records). The record protects
against a lock edited elsewhere and merged in (a pull request, a copied file), not against the
local user. A change to the tracked lock in a pull request remains the review signal. A fresh clone
has no records, so `verify` fails until each entry is re-consented.

## Catalogs

`catalog FILE` validates and imports. Revocations of the previously imported catalog are KEPT
(merged) unless `--replace` is passed, which drops them with a warning. If the previously imported
catalog cannot be read, the import refuses (exit 5), because its revocations could not be kept;
`--replace` imports anyway with a warning. A corrupt or invalid imported catalog makes every command
that reads it fail cleanly (exit 5) instead of crashing. Validation: `latest` must be a semantic
version listed in `releases`; `description`/`repository` must be strings and `tags` a list of tags.

## YAML subset versus YAML 1.1

The engine's parser deliberately refuses plain scalars and keys that a YAML 1.1 reader (for
example PyYAML) would not read as the same string: octal/hex/binary/underscore/sexagesimal numbers,
floats (`1.0`, `.inf`, `.nan`), `yes/no/on/off/y/n` and case variants, timestamps (`2026-10-29`),
`=`, `<<` and a leading `+`. Quote such values (`"yes"`, `"1.0"`). Semantic versions such as
`1.2.3` stay strings. The emitter quotes or refuses the same set, so a lock written by the engine
reads the same in both parsers.

## What `verify` checks (exit 5 on any problem)

Per-file `CHECKSUMS.sha256` (installed trees), the tree digest against the lock, manifest version
against the lock, tree containment rules, catalog revocation, capabilities against the recorded
consent (enabled extensions), the lock's `components` against its `enabled` flag (a lock that
claims hooks/MCP enabled on a disabled extension fails), the lock entry against its local state
record (R17), the wiring file's validity (R11, even with an empty lock), and every wired shim's
link target or hash (a wired file must be a regular file, not a symlink).

## Content digest

`sha256` over the canonical `CHECKSUMS.sha256` text (`<sha256>  <relpath>\n` per regular file,
sorted by path bytes, the CHECKSUMS file itself excluded). File modes are not part of the digest.

## Honest limits (UNCONFIRMED / not done)

- `enable` records hooks/MCP as enabled in the lock; it does not register hooks or MCP servers in
  any agent configuration. That materialisation belongs to E2/E4 and is not implemented here.
- Per-agent shim formats: Claude (`.claude/skills/<name>` symlink) follows the documented skill
  layout; OpenCode Markdown commands, Gemini TOML (`{{args}}`), Qwen TOML and pi prompts were
  written from the research report (inv_e) and are UNCONFIRMED against live agents (Qwen Markdown
  versus TOML is an open question there). No live agent test was run by E1.
- Symlinks inside an extension are refused outright (stricter than "no escape").
- `--dev` (and any local) sources record a project-relative location when inside the project; a
  directory outside the project is still recorded as an absolute path (`base: absolute`), which is
  not portable.
- R20 binding: the managed-by marker is plain text, so an attacker who can write both the shim file
  and the wiring file can mark a file as engine-made; the binding protects a user's own command file
  that does not carry the marker. A user who edits a wired shim but keeps the marker line loses the
  edit only if it also keeps the recorded sha256 (an edited file no longer matches and is left alone,
  W2).
- R21 shell/file-injection detection inside a body is lexical (front matter is parsed). The key
  `hooks` in front matter is treated as shell: UNCONFIRMED whether any agent honours it there; it is
  refused unless declared because a false positive is the safe direction. Exposed command
  directories must contain UTF-8 text only (a binary asset there is refused); markdown that starts
  with a `---` horizontal rule and has no front matter is refused as unterminated front matter.
- R22 is a static allow-list check of the declared launch argv; it does not inspect what a permitted
  in-tree program does when it runs (the tree digest in the consent only makes any change visible and
  re-consented). A program with `capabilities.shell` declared is outside the allow-list by consent.
  MCP files in other formats (YAML, TOML) are refused rather than parsed. Package runners (`npx`,
  `uvx`, `pipx`, `bunx`, `pnpm dlx`), other interpreters and PATH programs are refused without
  `capabilities.shell`. The allow-listed interpreters and their option sets are a fixed list: an
  interpreter outside it is refused (fail closed), not recognised by family. UNCONFIRMED: that every
  allowed option set is complete for each interpreter version in use. The code-bearing env name
  list is a pattern list and not complete (env names must also be listed in `env_vars`).
- I2: a snapshot is a copy made when `wire` runs; a non-risky content change in the extension tree
  (no new capability) is picked up by `lock` (exit 0) and reaches the agent at the next `wire`, without
  a new consent, by design: consent binds capabilities and the content of risky commands
  (`agent_shell`/`reads_files`), not every byte. Anyone who can write the project's
  `.constitution/extensions.snapshots/` can change what the agent sees; `verify` detects it (digest),
  nothing prevents it. Links wired by an older engine version still point into the live tree until
  `wire` runs again; `verify` reports each one. The post-update hook does not yet run `verify`/`lock`/
  `wire` after a constitution pull (owned by workstream W1, requested).
- I3: if a project's state (journal) is lost while its `remove` was interrupted, the trash directory
  it left is never deleted automatically; it is reported by every later mutating command and must be
  deleted by hand after checking that no journal names it.
- M1 escapes what the engine prints; it cannot escape what a wired shim later shows inside an agent.
- R21 detection is lexical. UNCONFIRMED from the repository's documentation: whether Claude Code
  skills and OpenCode commands actually execute `` !`...` `` or expand `@path` / honour
  `allowed-tools` when invoked through these shims (only Gemini CLI `!{...}` / `@{...}` is described,
  in docs/research/action_prefix_system/RESEARCH.md §1.2). The engine treats all of them as
  capabilities regardless; live agent behaviour was not tested. Constructs hidden by encodings the
  agent might decode, or other agent syntaxes not listed above, are not detected.
- Constitution version comes from `git describe --match 'helixconstitution-v*'`
  (`CONSTITUTION_EXT_CONSTITUTION_VERSION` is a test-only override, R19); without a version, an
  extension that declares `requires.constitution_version` is refused.
- Several projects sharing one constitution root share `_installed/`; the lock on
  `<root>/extensions/` serialises them, but one project's `remove` deletes the tree another
  project's lock still names (that project's `verify` then reports "tree missing").
- Git clones ignore the user's global git configuration (R15), so private repositories that need a
  credential helper configured there cannot be cloned; use SSH keys (`SSH_AUTH_SOCK` is kept).
- Single-file unlinks of shims use `os.unlink`; only recursive deletes go through `safe_rm_rf`.
- `wire` writes a `wire` journal naming its planned shims before creating any temporary link or file;
  a run killed between creating `<shim>.tmp-<pid>-<hex>` and renaming it leaves that file, and the
  next command removes it only when that pid is gone, the file belongs to the current user and it is
  a link with an engine-computed text or a file carrying the managed-by marker. A journal written by
  an older engine version, or a temporary file created by a crash before this journal existed, is not
  covered.
- `--project-root` equal to `--root` is refused (exit 3); it used to block on its own second lock.
- The check-to-use window between validation and copy is narrowed (O_NOFOLLOW, lstat), not closed.
- Catalogs are plain JSON; no signature verification.
- Mutation coverage (`tests/extensions/test_mutations.sh`): the special-file rule (R2-special) has
  no mutation row, because a FIFO in a test tree would hang the copy step under the mutated engine;
  the rule is covered by the security suite only. Rules with two enforcement layers are mutated in
  both layers at once, so the run proves the pair is load-bearing, not each layer alone.
  Rows for the 2026-10-29 review round: the reviewer's mutants M01, M03, M12, M13, M15, M16, M17,
  M20, M24 and M26 and own mutants of R4-git-content-pin, R5-wire-consent, R5-consent-visible,
  R9-wire-revocation, R11-relative, the relative link text, R13 root lock, R16 query/redact/waiver,
  R18-upfront, R20 (marker, MAC, signed, refuse) and R21 (each detector, declared, enable, wire);
  `test_provenance.sh` is the suite that kills them.
  Rows for review round 3 (this revision): every new R21/R22 branch (fail-closed scan, exposed
  directory, front-matter rules, MCP command form, shell, inline code, arguments, JSON), the consent
  binding (MCP argv, env names, shell, sha256 of bound files), `lock` re-consent, trust tier and waiver
  display, m1, m2, the wire-journal cleanup (owner, marker, live owner, journal validation) and the
  catalog fail-closed import. The reviewer's 32 round-3 mutants (N01-N32) are replayed separately by
  their own script; the killing tests are in `test_unit.py` and `test_security.sh`.
  Rows for review round 6 (structural): the R22 allow-list branches (keys, program, interpreter option and operand, plain tokens, env names, cwd/envFile, secrets, bounds, both layers), the whole-tree consent digest, the staged copy (wire checks and snapshots come from the copy; copy compared with the lock), verify re-derivation (wiring digest, link text, shim re-render and rescan), revocation by semver and by digest, journal identity (rollback only of the object the journal created), temp-file liveness and lstat, the snapshots-directory check and the lone-CR rule.
  Rows for review round 5: B1 (the at-token class and the widened lookbehind), every R22 class
  branch (shell name class, value-taking short option, stop option, code subcommand, `--opt value`,
  code URL, code env, env-code consent in both layers), M1 sink, M2 rendered rescan, M3 message, M4
  `O_NONBLOCK` and post-open regular check, M5 RecursionError, I3 (read-only, bad journal, trash
  kept) and I2 (snapshot intact, snapshot matches the checked content, garbage collection, verify of
  snapshot and of old-format links, temporary cleanup, link to the live tree, snapshot never made).
  The reviewer's round-4 mutants (X01-X25) are replayed separately by their own script.
  Concurrency (R13) is killed only probabilistically: the B3 attack races concurrent adds over
  several rounds; a mutant that drops the lock could in principle survive a lucky run.
- `test_cli.sh` (auto-root layouts) copies the repository engine, not `$CONSTITUTION_EXT_ENGINE`,
  so it cannot kill a mutation; no mutation row relies on it.

## Tests

`bash tests/extensions/run_all.sh` (unit, cli, security, e2e, determinism, attacks, provenance,
integration, chaos, stress/perf, mutations). `--quick` runs the first seven. `test_provenance.sh`
replays the forged-wiring attack, the clone flow, revocation in `wire`, the agent-construct rules and
the reviewer's surviving mutants. `test_attacks.sh` replays every
attack class of the 2026-10-29 security review through the real CLI.

## Round 7 notes (E1, last round of the review budget)

- Duplicate keys in any JSON file the engine reads (MCP file, catalog, state records) are refused.
- `catalog` refuses a `revoked[].version` that is neither semver nor `*`.
- `wire` and every other tree copy refuse symlinked directories (as `verify` does) and enforce the file-count, byte, per-file,
  directory-count and depth limits.
- Tests need a `Constitution.md` in the engine copy and the clone on branch `main` (guarded in `test_integration.sh`).
- Honest limits: a header value or env value `${NAME}` may reference any variable name; the consent shows names, not values.
  The tree digest covers the extension tree only. UNCONFIRMED: other MCP file dialects (for example `servers` instead of
  `mcpServers`) are refused, not translated.
