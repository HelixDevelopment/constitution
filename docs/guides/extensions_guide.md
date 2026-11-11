# Extensions Guide - installing and managing constitution extensions

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
| Status | draft |
| Status summary | Engine (E1) implemented with its own tests; experimental, dormant, not independently GO'd (rounds 10 and 11 fixes landed, round 11 fixes and the round 12 A3 staging-pid fix (c252eed) pending independent re-review). `/constitution extensions ...` delegates to it (`constitution_cmd.sh`; `install-extension` maps to `add`); installer and post-update-hook wiring of extensions is UNCONFIRMED; shim formats other than Claude are UNCONFIRMED against live agents. Written 2026-10-29 from `constitution_ext.sh --help` and `scripts/constitution_ext/README.md`. |
| Authority | Tool documentation for `scripts/constitution_ext/`; design in `docs/design/constitution_extensions_plan.md`. §11.4.228, §11.4.272, §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Operators who add, verify and wire extensions with `scripts/constitution_ext/constitution_ext.sh`. |
| Issues | none |

> Status: experimental, dormant, not independently GO'd (rounds 10 and 11 fixes landed, round 11 fixes and the round 12 A3 staging-pid fix (c252eed) pending independent re-review). The `/constitution` command exists and `/constitution extensions ...` delegates to this engine (`install-extension` maps to `add`); installer integration of extensions and post-update wiring are UNCONFIRMED. Everything below is the engine's own CLI.

See also the [extensions catalogue](../extensions/EXTENSIONS_CATALOG.md) (every shipped extension, provenance, per-platform compatibility).

## What an extension is

A directory with an `extension.yml` manifest (strict YAML subset, unknown keys rejected), optional `commands/<name>/SKILL.md`, skills, MCP, hooks, templates, tools, and a `CHECKSUMS.sha256`. Bundled ones live in `<constitution>/extensions/<id>/`; ones you install go to `<constitution>/extensions/_installed/<id>/` (git-ignored through the checkout's `info/exclude`). The consumer's project tracks `.constitution/extensions.lock.yml`.

## Safety in one paragraph

No code from an extension is executed at install (copy only). Sources are pinned (`--sha256`, plus a 40-hex `--sha` for git) or need a recorded `--waiver-id`. Capabilities are shown and consent recorded; hooks and MCP stay disabled until `enable`. Paths are contained, symlinks and special files refused, secrets in manifests refused. Installs are staged, journaled and atomic; an interrupted run is rolled back or forward on the next one. Git clones ignore your global git config. See the [lifecycle diagram](../diagrams/extension_lifecycle.md).

## Everyday commands

```bash
E=submodules/constitution/scripts/constitution_ext/constitution_ext.sh   # legacy layout: constitution/scripts/...
bash $E list                      # bundled + installed, lock state
bash $E validate ./my_ext         # prints the content sha256
bash $E --dry-run add ./my_ext --sha256 <hash>
bash $E add ./my_ext --sha256 <hash>      # asks for consent on /dev/tty
bash $E enable my_ext             # records consent; hooks/MCP marked enabled in the lock
bash $E wire my_ext --agent claude        # claude|opencode|gemini|qwen|pi|all
bash $E verify                    # exit 5 on any problem
bash $E doctor
bash $E unwire my_ext --agent all; bash $E disable my_ext; bash $E remove my_ext
```

`--root DIR` and `--project-root DIR` select the constitution and the project (defaults: `$CONSTITUTION_DIR`, the script's own location, `constitution/` or `submodules/constitution/` above the cwd; the git superproject). `--json` for machine output; `--dry-run` writes nothing. Git sources need `--sha` AND `--sha256`. `CONSTITUTION_EXT_NO_TTY=1` forbids the consent prompt (use `--yes` deliberately).

## Wiring per agent

`wire` materialises a command as: Claude `.claude/skills/<name>` (symlink), OpenCode `.opencode/commands/<name>.md`, Gemini `.gemini/commands/<name>.toml`, Qwen `.qwen/commands/<name>.toml`, pi `.pi/prompts/<name>.md`. Only the Claude layout follows documented behaviour; the others are UNCONFIRMED against live agents. Wiring entries are project-relative, so the lock and wiring file can be committed.

## Fresh clones

`extensions.state/` is local and git-ignored, so `verify` exits 5 until each enabled entry is re-consented (`enable <id> --yes`). That is by design.

## Ownership ledger (ownership redesign, wave 1)

Status: PROVISIONAL, foundation only. `scripts/constitution_ext/wiring_ledger.py` is tested but NOT yet called by the installer, the post-update hook or `constitution_ext.sh`; nothing you run today changes behaviour. Design: [extension_engine_ownership_redesign.md](../design/extension_engine_ownership_redesign.md) sections 5 and 9.

The rule: the constitution treats a file, link or JSON entry in your project as its own only when (1) `.constitution/wiring.json` (tracked) has a row for it, (2) the local, git-ignored `.constitution/extensions.state/wiring.local.json` carries this checkout's HMAC signature for that row and the row names this constitution root, and (3) the item on disk still matches the row's fingerprint. Anything else is reported (`consumer-owned`, `other-checkout`, `diverged`) and never replaced or deleted. The ledger stores paths and digests only.

```
W="python3 -I scripts/constitution_ext/wiring_ledger.py --project . --root <constitution>"
$W inventory                          # read-only: what looks constitution-made
$W adopt                              # adopts NOTHING (decision D6); use --adopt all-matching or --only PATH
$W backup --path .claude/settings.json --path .claude/skills/x
$W rollback --backup .constitution-install-backup/<UTC>-wiring
$W status | $W classify --path P | $W record ... | $W forget --id ID
$W refs add|remove|count|list --id EXT --record-digest D   # extensions/_installed/<id>.refs, flock-protected
```

Exit 0 ok, 3 refused (nothing changed). `rollback` restores backed-up files byte-for-byte, restores both ledger files, drops rows created after the backup and unlinks a link made since only while it still matches its row; changed items are listed under `left_alone`. Rollback means "back to the backup": a backed-up path whose current content was written after the backup (for example a file you put where our link was) gets the backed-up content again, so copy anything you want to keep before you roll back. A backed-up file whose path now holds a link we did not record is refused (exit 3, nothing changed). Tests: `tests/extensions/test_wiring_ledger.sh` and the paired mutations in `test_wiring_ledger_mutations.sh`.

## Known limits

The engine is experimental and dormant and has not been independently reviewed to a GO. Known, unfixed ownership limits (shared-tree removal after re-consent with a copied lock, records not bound to the constitution root, a directory-swap race in the tree copy, no reference counting) are listed in the [manual](../manuals/extensions_manual.md#known-limits-added-in-round-12-not-fixed). Do not share one constitution root between projects you do not control.

Next: [manual](../manuals/extensions_manual.md), [FAQ](../faq/extensions_faq.md), [tutorial 07](../tutorials/07_installing_an_extension.md), [troubleshooting](troubleshooting_guide.md).
