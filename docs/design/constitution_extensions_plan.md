# Constitution extensions and the `/constitution` command family — plan

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T16:00:00Z |
| Status | draft plan (nothing below is implemented or verified yet) |
| Status summary | Plan derived from two read-only investigations (internal inventory, external SpecKit / agent-format research). Implementation, live tests and release follow. |
| Authority | §11.4.228 (extension lifecycle), §11.4.272 (on-demand activation), §11.4.164 (auto-propagation), §11.4.74 (extend, do not reimplement), §11.4.289 (live evidence) |
| Scope | extensions system, `/constitution` and `/helix:constitution`, per-agent wiring, installer integration |
| Issues | none |

## 1. Goal

Make the constitution usable from inside any CLI agent through a command (`/constitution`, `/helix:constitution`), and let it grow through **extensions** installed under its own `extensions/` directory and bound to the tools and utilities it already ships. The model is SpecKit's extensions, hardened for our rules (pinned shas, consent, no code run at install, live evidence).

## 2. Facts the plan stands on

Internal (read from this repository; test pass state unconfirmed):

- `/helix:<name>` commands are generated from `actions/registry.yaml` by `scripts/generate_agent_prefix_commands.sh` (Claude `.md`, Gemini/Qwen `.toml`, Codex `.md`). There is no `constitution` action, skill or command yet. A new registry row plus regeneration adds it.
- `skills/` holds 10 skills; `scripts/skill_activation/` is the §11.4.272 engine. `skills/jev-decision-layer/EXTENSION_SOURCE.yaml` is the only provenance file in the §11.4.228(B) shape.
- `scripts/extensions/` holds only the SpecKit/Superpowers bridge. `docs/extensions/EXTENSIONS_CATALOG.md` and the compatibility matrix required by §11.4.228(B)(3)/(C) do not exist.
- Two seams link skills to different places (`<root>/skills` from `post_update_hook.sh`, `<root>/.claude/skills` from `install_cli_agent_plugins.sh`). This must be unified.
- OpenCode, Gemini and Qwen skill wiring is missing (§11.4.228(D)(2) unmet). `scripts/label-sync/adapters/*` already holds multi-agent config writing and is reused.

External (primary sources cited in the research report; unconfirmed items listed in section 9):

- SpecKit extensions: `extension.yml` (schema 1.0), installed under `.specify/extensions/<ext>/`, CLI `specify extension add|remove|list|info|update|enable|disable`, catalog JSON with sha256 and trust tiers (`install_allowed`).
- Claude Code plugin components are always namespaced (`/helix:constitution`). A bare `/constitution` exists only as a user- or project-scope skill or command, so we ship a thin project-scope `constitution` skill that delegates to the engine.
- The common denominator across agents is `<dir>/<name>/SKILL.md`. Per-agent shims (md/toml) are rendered from it.

## 3. Design

### 3.1 Layout

```
extensions/                      (inside the constitution; tracked bundled extensions)
  <id>/
    extension.yml                manifest (strict YAML subset, unknown keys rejected)
    commands/<name>/SKILL.md     command carrier (rendered into per-agent shims)
    skills/ mcp/ hooks/ templates/ tools/ scripts/
    CHECKSUMS.sha256
  _installed/<id>/               user-installed extensions (git-ignored via the submodule's info/exclude, so the submodule stays clean)
docs/extensions/EXTENSIONS_CATALOG.md   generated catalog + per-platform compatibility matrix
<consumer>/.constitution/extensions.lock.yml   tracked in the consumer repo: id, version, source, git sha, content sha256, enabled
```

### 3.2 Manifest (SpecKit superset)

`extension.id` (`^[a-z0-9-]+$`), strict semver `version`, `source {git, sha, sha256}`, `trust_tier`, `requires {constitution_version, extensions, tools, anchors}`, `provides {commands, skills, mcp, hooks, templates, tools_bindings, config}`, `capabilities` (what it may touch, shown at consent), per-platform `compatibility {status: SUPPORTED|UNTESTED|UNSUPPORTED|CONFIG-ONLY, min_version, evidence}`.

### 3.3 Security model (all enforced by the engine, each with a test)

1. Install is copy or symlink only; **no code from the extension runs at install**.
2. Pinned by 40-hex git sha plus content sha256, recorded in the lock file; an unpinned source needs a recorded §11.4.271 waiver.
3. Strict schema, unknown keys rejected, every path contained inside the extension root (no `..`, no absolute, no symlink escape).
4. Capability declaration is shown and consent is recorded; hooks and MCP servers default to disabled until `enable`.
5. No secrets in manifests (env var names only).
6. Atomic staged install with rollback; verify-after-install by re-reading the installed tree and comparing hashes (§11.4.200).
7. Deletes only through `safe_rm_rf` (§11.4.287); revocation list in the catalog is honoured on `verify`.

### 3.4 Command family

Registry row `constitution` generates `/helix:constitution` (and the `default-` alias). A project-scope skill `skills/constitution/SKILL.md`, linked into `.claude/skills/constitution`, provides bare `/constitution`. Other agents get rendered shims (OpenCode `.opencode/commands/`, Gemini/Qwen TOML, pi prompts, Codex skills, Kimi `/skill:`).

Subcommands (all handled by one engine script reading `$ARGUMENTS`): `status`, `update`, `doctor`, `extensions list|info|add|update|remove|enable|disable|verify|lock|catalog|wire|unwire`, `install-extension`, `anchors <N>`, `gates`, `report|issue|bug|task|feature` (reusing `scripts/reporting/report_item.sh`, §11.4.202), `note|reminder|critical|important|background`, `jev`, `skills`, `release-notes`, `help`.

### 3.5 Binding to existing tools

An extension's `tools_bindings` maps a command or hook to an existing utility by stable name (for example `workable-items`, `report_item.sh`, `skill_activation`, `label-sync`), never by copying it (§11.4.74). The engine refuses a binding whose target does not resolve.

### 3.6 Token discipline

Extensions are inactive by default; `/constitution` itself is a thin skill; activation goes through the §11.4.272 engine; the skill-surface budget gate must stay green with the new skill.

## 4. Workstreams (fan-out, disjoint file ownership)

| ID | Work | Owns | Depends on |
|---|---|---|---|
| E1 | Extension engine: strict manifest parser, schema validator, lock file, staged atomic install/remove/enable/disable/verify/doctor, security checks, catalog reader | `scripts/constitution_ext/*`, `tests/extensions/*` | none |
| E2 | `/constitution` command family: registry row, engine dispatcher, skill, generated shims, per-agent wiring (OpenCode, Gemini, Qwen, Kimi, pi, Codex), unify the two skill-link seams | `actions/registry.yaml`, `skills/constitution/*`, `plugins/helix/*`, `scripts/install_cli_agent_plugins.sh`, `scripts/post_update_hook.sh` | E1, and W1 finished (it edits the same scripts) |
| E3 | Reference extensions: `hello-example` (test vehicle), `speckit-bridge` (wraps `scripts/extensions/`), `jev-decision-layer` registered by reference | `extensions/*` | E1 |
| E4 | Catalog and compatibility matrix generator, liveness probes, CM gates with paired mutation tests, post-update hook extension class | `docs/extensions/*`, `scripts/gates/cm_extension_*` | E1, E2 |
| E5 | Installer integration: `--extensions`, ask the user in the curl installer, update script keeps extensions consistent | `scripts/install_constitution.sh`, `scripts/update_constitution.sh` | W2 finished, E1 |
| E6 | Docs: README section, guide, manual, FAQ, tutorials, diagrams, CHANGELOG | docs, README | E1-E5 |
| E7 | Independent Opus review (every change), reviewer-authored mutations | none | each stream |
| E8 | Live verification and release (GitHub, GitLab and Gitea CLIs) | none | all |

## 5. Test types required (real evidence; doubles only as labelled unit-class)

Unit, integration (real git, real `git submodule add`), e2e (the real installer and engine in a throwaway project), security (path traversal, symlink escape, hostile manifests, unknown keys, sha mismatch, revoked extension, injection in args), chaos (kill mid-install, then re-run recovers, rollback leaves no partial state), stress (many extensions, many repeated runs), performance (install and list time budgets), idempotency, determinism (three identical runs), paired §1.1 mutation per gate, and **live agent tests**: `claude plugin validate`, and a real headless `/constitution status` through an installed agent with a hard budget cap (otherwise recorded as an honest SKIP with reason, never a stand-in).

## 6. Order of work

1. Now (no file conflicts): E1 engine and its tests.
2. After W1 and W2 land and are reviewed: release 1 (installer, `latest.md`, layout hardening, Gitea publisher).
3. Then E2, E3, E5 in parallel with E4, then E6, then reviews and live verification, then release 2.

## 7. Risks and how they are handled

- Same-file edits between streams: ownership table above, conductor commits.
- A bare `/constitution` can collide with a user command of the same name: documented precedence, `doctor` detects it.
- Token burn: extensions inactive by default; no LLM call in any install path.
- Corrupting a consumer: all writes backed up first, atomic, verified, reversible; nothing is pushed by the tooling.

## 8. Definition of done

Engine and commands implemented, every test type green with captured output, independent Opus review GO, live evidence recorded (or honest SKIP), docs and README updated, release 2 tagged and published to GitHub, GitLab and Gitea.

## 9. Unconfirmed items carried from the research

SpecKit version read; per-agent command directories for Gemini, OpenCode, Kimi, Qwen (Markdown versus TOML); Kimi and pi paths; Cursor and Codex MCP details; Aider; the Claude marketplace schema; whether a Claude Code build ships its own `/constitution`. Each is verified on this host during implementation or recorded as UNCONFIRMED.


## Round 6 note (E1, structural)

R22 is now an allow-list; wire builds one private staged copy of the locked tree (single O_NOFOLLOW read, hashes from the bytes read), runs the checks and renders snapshots from that copy and publishes by atomic rename; verify re-derives everything from the locked tree; the consent carries a whole-tree digest for extensions with hooks, MCP servers or executables; the journal records the staged object identity so rollback removes only what it created. See scripts/constitution_ext/README.md rev 7.

## Round 7 note (E1, last round; allow-lists replace deny-lists)

Class inventory written down before the fix (each class is closed by an allow-list or a structural rule, never by adding names):

| Class | What was open | Closure |
|---|---|---|
| A. What a launched program reads from its environment | Unbounded set (OPENSSL_CONF, KRB5_CONFIG, GLIBC_TUNABLES, LOCPATH, ...); a deny-list can never be complete | Env names must match an inert-suffix allow-list minus loader patterns, in the file and in `env_vars`; others need `capabilities.shell` and are tagged `env-code:` in the consent; values carry no path separator (URLs only for `*_URL`/`*_ENDPOINT`); `--opt=a=b` parts are all checked |
| B. Shape of an MCP server entry | Entries without `command` (http/sse/ws, headers, url) were never looked at | Document shape allow-list (`mcpServers` only); entry is stdio or remote; remote needs matching `provides.mcp` (transport http, same name, network host) and `capabilities.network`; header values are env references; consent lists server keys, endpoints and header names |
| C. Selecting the project to change | Implicit walk up from the cwd followed symlinked ancestors into a foreign project | No cwd search at all; implicit root only from the engine's own location; discovered project must equal the cwd's git top level before any writing command |
| D. Ambiguous JSON | Duplicate keys, last one wins | Refused at the one JSON entry point |
| E. Tree copy | Symlinked directories copied as empty directories; no bounds | Symlinked dir refused; file/byte/per-file/dir/depth limits |
| F. Catalog grammar | `revoked[].version` any string | semver or `*` |

Reviewer mutants RM1-RM5 are in `tests/extensions/test_mutations.sh` (rows `R7 RM1`..`R7 RM5`) with the new rules' own mutants.


## Round 9 note (E1, structural: a journal acts only on what it can prove it owns)

Class: a recovery or cleanup path that renames or deletes a path taken from journal content or from a name pattern. Census (control-needled: `os.rename` 4 hits, an absent needle 0 hits) of every rename, delete and unlink in the engine, and the proof each one now has:

| Site | Proof before acting |
|---|---|
| add rollback (`rm_tree(final)`) | identity recorded by the add journal (device, inode, mtime), compared with the tree at `final` |
| remove rollback (rename trash to `final`) and remove completion (delete trash) | NEW: the remove journal records the identity of `final` before the rename; the trash is touched only when both ends sit directly in `_installed`, the name is a trash name, it is a directory of this user and its identity equals the journal's. Otherwise it is left in place and reported; an old journal with no identity is treated the same way |
| `.staging-*` sweep | dead pid, shape, and NEW: owned by this user |
| `.trash-*` sweep | never deleted by name (only the journal that names it may act) |
| temp files, wire stage directories, wire temp shims | dead pid, shape, owner, and for shims the managed-by marker or the engine-computed link text |
| commit journal (`deletes`) | ids validated, deleted only when absent from the lock |
| `cmd_remove` (rename to trash, `rm_tree`, lock entry, record) | Round 10 (F1): refused unless the id is in THIS project's lock; the tree is moved only when its digest equals the sha256 the lock pinned, otherwise only the lock entry goes and the tree is left (with a note); `update`, `enable`, `disable`, `wire`, `unwire` never touch `_installed/<id>` for an id absent from the lock (enable/wire refuse, disable/unwire act on this project's wiring only) |
| `cmd_add` rollback and the add journal | Round 10 (F2): the add journal is HMAC-signed with the project's state key; an unsigned or forged one is left in place, reported, and add/remove/lock/enable/disable refuse while it is present (a bad journal is never overwritten) |
| `_installed` / `extensions/` as symlinks | Round 10 (A4): every mutating command refuses when either is a symlink, not a directory, or not owned by the user, before any sweep |
| `.staging-*` sweep | also live-pid check (`_alive`), regression test added (m10) |
| state record deletion after an unproven trash | Round 10: the record stays with the trash that was left in place |
| snapshot garbage collection, `_work`, wire stage | paths built from validated names under this project's own state or the engine's own working directory |

Copy: `_copy_tree` re-checks the opened descriptor (regular file, one link, same device and inode as the `lstat`), closing the window between `lstat` and `open`. Test infrastructure: `new_sandbox` resolves the sandbox with `realpath`, so a symlinked or `..`-containing `TMPDIR` no longer changes compared paths. Honest boundary: identity is device, inode and mtime of a directory; it proves "the same directory that was moved", not that its content is unchanged.


## Round 10 note (F1, structural: an act on the shared `_installed` root needs proof that THIS project owns the target)

Class: a command that renames, deletes or sweeps under the shared `extensions/_installed` root on the strength of a name, without proof from this project's own records. Census re-derived by hand (control-needled: `os.rename` 4 hits, `os.unlink` 11 hits, `rm_tree` 12 hits, an absent needle 0): the table above lists every site. Design decision for trees shared by several projects: ownership is "the id is in this project's lock AND the tree's digest equals the lock's pinned sha256". No per-root reference count is kept (the root is git-ignored and re-installable, so a deleted tree is reported by the other project's `verify` with the exact reinstall command). Remaining limit: two projects that locked byte-identical content share one tree; removing it from one makes the other's `verify` report it missing. `_copy_tree` is the only read of the source whose bytes are installed; `file_hashes(srcdir)` reads the source earlier only to validate and pin it.


## Round 11 note (F3 remove needs this checkout's own record, F4 the remove journal is signed)

F3 (high): the lock is committed, so a project can hold a copy of another project's lock whose tree digest matches the shared tree; round 10's ownership proof (id in lock AND digest equal) was therefore satisfied by a copy, and `remove` deleted the other project's tree. `cmd_remove` now also requires a valid HMAC-signed local state record for the id (the record is never committed and is keyed by this checkout's own key); a missing or invalid record, or a missing key, refuses with exit 3 and leaves the tree and the lock. A lock-vs-record field difference does not by itself refuse here (it is reported by `verify`). F4 (medium): the remove journal is HMAC-signed with the same scheme as the add journal (the MAC is domain-separated by the op, so an add MAC is not a remove MAC); an unsigned or forged remove journal is left in place with a warning and add/remove refuse while it is present. Not done (UNCONFIRMED as needed): refusing removal while another project's live wiring points at the shared tree; the root keeps no registry of projects, so this is not cheaply detectable and is documented as a remaining limit. Existing tests that handwrote unsigned remove journals now sign them with `sign_journal` (lib.sh). Tests: `test_round11.sh`, unit `test_f4_*`, mutants `E1r11 F3`, `E1r11 F4` (two rows).
