# Extensions Manual - commands, layout, rules, limits

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
| Status | draft |
| Status summary | Engine (E1) implemented with its own tests; experimental, dormant, not independently GO'd (rounds 10 and 11 fixes landed, round 11 fixes and the round 12 A3 staging-pid fix (c252eed) pending independent re-review). `/constitution extensions ...` delegates to it (`constitution_cmd.sh`; `install-extension` maps to `add`); installer and post-update-hook wiring of extensions is UNCONFIRMED; shim formats other than Claude are UNCONFIRMED against live agents. Written 2026-10-29 from `constitution_ext.sh --help` and `scripts/constitution_ext/README.md`. |
| Authority | Tool documentation for `scripts/constitution_ext/`; design in `docs/design/constitution_extensions_plan.md`. §11.4.228, §11.4.272, §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Reference for `scripts/constitution_ext/constitution_ext.sh`. |
| Issues | none |

Source of truth: `constitution_ext.sh --help` and `scripts/constitution_ext/README.md` (rules R1 to R22). Requires bash, python3 3.8+ (stdlib only) and git.

## Synopsis

```text
constitution_ext.sh [--root DIR] [--project-root DIR] [--json] [--dry-run] <command> [args]
```

| Command | Purpose |
|---|---|
| `validate <dir>` | check a manifest and tree; print the content sha256 |
| `list` / `info <id>` | bundled and installed extensions with lock state / manifest summary, capabilities, lock entry, wiring |
| `add <source> [--sha SHA] [--sha256 H] [--dev] [--waiver-id ID] [--yes]` | install from a local directory (pin `--sha256`) or git URL/repo (pin `--sha` 40-hex AND `--sha256`); unpinned needs `--waiver-id` |
| `remove <id> [--yes]` | unwire and delete an installed extension (never a bundled one) |
| `enable <id> [--yes]` / `disable <id>` | record consent and mark enabled / unwire commands and mark disabled |
| `verify [<id>]` | recompute checksums, compare with the lock, catalog revocations, consented capabilities, wired shims |
| `lock` | write or refresh the lock (bundled hashes only; never launders a changed installed tree) |
| `doctor` | environment, layout, exclude, lock, journal, wiring, per-extension verify |
| `catalog <file> [--replace]` | validate and import a JSON catalog; previous revocations are kept unless `--replace` |
| `wire [<id>] --agent A [--target DIR]` / `unwire` | create / remove shims, A = claude, opencode, gemini, qwen, pi, all |

Exit codes: 0 ok, 1 failure, 2 usage, 3 precondition or refused by policy, 5 verification failed.

## Layout

```text
<root>/extensions/<id>/                      bundled, tracked in the constitution
<root>/extensions/_installed/<id>/           installed by add; git-ignored via info/exclude
<project>/.constitution/extensions.lock.yml  tracked by the consumer
<project>/.constitution/extensions.wiring.yml  shims made by wire; project-relative
<project>/.constitution/extensions.catalog.json  imported catalog
<project>/.constitution/extensions.audit.log   one JSON line per real change
<project>/.constitution/extensions.txn       journal; only while a transaction is in flight
<project>/.constitution/extensions.state/    LOCAL, git-ignored: key (0600), HMAC records
```

## Transactions, locking, recovery

`add` is staged, journaled and renamed into place with rollback on the next run; `remove` renames into a trash directory first. Every command takes an exclusive `flock` on the project directory and the constitution root. Recovery acts only on a journal that validates; one that does not validate is never acted on, `add`/`remove` refuse and a person must inspect it. Details: README of the engine, section Transactions.

## Security rules (summary)

R1-R10 manifest/tree/consent/pin rules; R11 wiring-file validation; R13 locking; R14 tree limits (no `.git`, no bare repos, no hard links, at most 2000 directories); R15 scrubbed git environment and protocol allow-list (file, https, ssh); R16 URL rules (no `::` helpers, no credentials, no secret-shaped values); R17 HMAC state records; R19 test seams inert outside a nonce sandbox; R20 wiring provenance (signed record or managed-by marker); R21 agent-side constructs (`!{...}`, `` !`...` ``, `allowed-tools`, `@{...}`, `@path`) must be declared as capabilities. Full table: `scripts/constitution_ext/README.md`.

## YAML subset

Plain scalars a YAML 1.1 reader would reinterpret (octal/hex numbers, floats, `yes/no/on/off`, timestamps, `=`, `<<`) are refused; quote them. Semantic versions stay strings.

## Honest limits (UNCONFIRMED / not done)

- `enable` records hooks and MCP as enabled in the lock; it does not register them in any agent configuration (not implemented).
- Per-agent shim formats other than Claude are UNCONFIRMED against live agents; no live agent test was run.
- Whether Claude Code skills or OpenCode commands execute `` !`...` `` or honour `allowed-tools` through these shims is UNCONFIRMED.
- A user able to write both the tracked lock and the local state directory can forge both; the records protect against a lock edited elsewhere and merged in, not against the local user.
- Catalogs are plain JSON; no signature verification.
- Sharing limit: byte-identical content locked by two projects (or a cloned lock) shares one tree under `_installed/`; `remove` by one project moves that tree, so the other project's `verify` then reports it missing. A tree with different content under the same id is left in place and only the removing project's lock entry is dropped.
- `remove` refuses ids that are not in this project's lock and ids for which this checkout has no valid HMAC-signed state record (a cloned lock is not proof of installation); the add and remove journals are HMAC-signed; symlinked or foreign shared directories are refused (checked against `ext_engine.py` `cmd_remove`, `RULE:F1-lock-membership`, `F3-own-record`, `F2-journal-mac`, `F4-remove-journal-mac`; the symlinked/foreign-shared-dir refusal itself was not re-read line by line here: UNCONFIRMED).

### Known limits added in round 12 (not fixed)

- **F-1 (known, not fixed).** `remove` can delete a shared tree after `enable` re-consent in a second clone that holds a copied lock: `enable` writes a signed state record for any id present in the lock, and `remove` accepts that record as proof of ownership.
- **F-2 (known, not fixed).** A state record / `add` journal is not bound to the constitution root. A project that installed the id under another root can therefore remove a shared tree with an identical digest.
- **S2 (known, not fixed).** A parent-directory swap during `_copy_tree` can make the copy read outside content; it is caught afterwards by the pinned-digest check, not prevented.
- **No reference counting.** `remove` by one project breaks another project's `verify` on the shared tree.
- Status: the engine is experimental and dormant, and has NOT been independently reviewed to a GO. No GO is claimed. The ownership redesign (an "installed by this checkout" marker set only by `add`, bound to the root realpath and the tree identity, never by `enable`) is a tracked release-2 item.

Related: [guide](../guides/extensions_guide.md), [FAQ](../faq/extensions_faq.md), [lifecycle diagram](../diagrams/extension_lifecycle.md).
