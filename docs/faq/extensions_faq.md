# Extensions FAQ

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
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

**12. Is it safe with two projects sharing one constitution?** Locks serialise them, but one project's `remove` deletes a tree another project's lock still names.

**13. What are the known limits?** The engine is experimental, dormant and not independently GO'd. Unfixed: F-1 and F-2 (a project can remove a shared tree it did not install, via a copied lock or another root), S2 (copy race, caught afterwards by the digest check), no reference counting. See the [manual](../manuals/extensions_manual.md#known-limits-added-in-round-12-not-fixed). The ownership redesign is a tracked release-2 item.

Related: [guide](../guides/extensions_guide.md), [manual](../manuals/extensions_manual.md), [troubleshooting](../guides/troubleshooting_guide.md).
