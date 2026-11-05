# Extensions FAQ

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-11-05T18:00:00Z |
| Status | draft |
| Status summary | Engine (E1) implemented with its own tests; experimental, dormant, not independently GO'd (rounds 10 and 11 fixes landed, round 11 fixes and the round 12 A3 staging-pid fix (c252eed) pending independent re-review). `/constitution extensions ...` delegates to it (`constitution_cmd.sh`; `install-extension` maps to `add`); installer and post-update-hook wiring of extensions is UNCONFIRMED; shim formats other than Claude are UNCONFIRMED against live agents. Written 2026-10-29 from `constitution_ext.sh --help` and `scripts/constitution_ext/README.md`. |
| Authority | Tool documentation for `scripts/constitution_ext/`; design in `docs/design/constitution_extensions_plan.md`. §11.4.228, §11.4.272, §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Questions about installing and managing constitution extensions. |
| Issues | none |

**1. Does installing an extension run its code?** No. Install copies files only; git clones run with hooks disabled, symlinks off and filters neutralised.

**2. Why does `add` ask for a hash?** Pins: a local directory needs `--sha256` (run `validate` to print it); a git source needs a 40-hex `--sha` and `--sha256`. Without a pin you must pass a recorded `--waiver-id` (refused if it looks like a token).

**3. Why does `verify` fail in a fresh clone?** Local state records are git-ignored, so each enabled entry must be re-consented with `enable <id> --yes`. Also `_installed/` is git-ignored: reinstall with the pins in the lock.

**4. What does `enable` do?** Records consent and marks hooks/MCP enabled in the lock. It does not register them in any agent configuration; that is not implemented yet.

**5. Which agents are supported?** `wire --agent` knows claude, opencode, gemini, qwen, pi. Only the Claude layout follows documented behaviour; the rest are UNCONFIRMED against live agents.

**6. A command body uses `!{...}` or `@path`. Why was it refused?** Agent-side constructs must be declared under `capabilities.agent_shell` / `reads_files`; detection is lexical.

**7. My private git repo will not clone.** Your global git config and credential helpers are ignored (R15). Use SSH keys; `SSH_AUTH_SOCK` is kept.

**8. An install was interrupted.** Re-run any command: the journal is rolled forward or back. If it does not validate, nothing is touched until you inspect and delete it.

**9. Can I remove a bundled extension?** No; `remove` only deletes installed ones. Use `disable`.

**10. Is there a `/constitution` slash command?** Planned (design plan), not landed: UNCONFIRMED.

**11. Exit codes?** 0 ok, 1 failure, 2 usage, 3 refused by policy, 5 verification failed.

**12. Is it safe with two projects sharing one constitution?** Locks serialise them. Since ownership wave 2 (E01), `remove` needs this checkout's signed install fact, which only `add` writes (or `adopt-install`, typed by an operator at a terminal); a project that only copied the lock and ran `enable` is refused. A byte copy of a whole checkout still carries the fact (CON-070), and there is no reference counting yet, so a project that did install the tree can still remove it while another project uses it.

**12a. `remove` says this checkout holds no install fact, but I did install it.** Installs made before install facts existed have none. An operator at a terminal runs `adopt-install <id> --waiver-id <ticket-or-decision-id>` and types the id at the prompt; it checks the lock entry, the local state record and the tree digest first and never replaces an existing fact. There is no non-interactive form (`--yes` is refused): the prompt is meant to keep automation from attesting an install.

**13. What are the known limits?** The engine is experimental, dormant and not independently GO'd. F-1 is narrowed (a copied lock plus `enable` no longer lets `remove` delete a shared tree; a byte copy of a checkout still can, CON-070); F-2 is addressed by the root-bound install fact; unfixed: S2 (copy race, caught afterwards by the digest check) and no reference counting. See the [manual](../manuals/extensions_manual.md#known-limits-added-in-round-12-not-fixed).

Related: [guide](../guides/extensions_guide.md), [manual](../manuals/extensions_manual.md), [troubleshooting](../guides/troubleshooting_guide.md).
