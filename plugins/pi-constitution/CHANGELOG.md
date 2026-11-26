# pi-constitution — Changelog

All notable changes to the pi-constitution Pi extension are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/)
Types: `Added`, `Changed`, `Fixed`, `Removed`, `Security`

---

## [1.0.0] — 2026-11-25

### Added

- `pi-constitution` Pi extension (schema `pi.extension.v1`)
- `session_start` hook: audits Constitution submodule, governance files, mandate sections
- `tool_call` hook: peer-gates Constitution-relevant bash commands via typed collab packets
- `pi-constitution-doctor` custom tool: on-demand full governance audit with structured result
- Typed collaboration packets: `pi-constitution.collab_question.v1` / `collab_answer.v1`
- Deterministic triage-error codes:
  - `constitution_submodule_missing`
  - `constitution_governance_file_missing`
  - `constitution_mandate_section_missing`
  - `constitution_pointer_stale` (reserved)
- Shame-compatible status via `ctx.ui.setStatus("constitution", ...)` from validated data
- `pi-constitution.audit` and `pi-constitution.triage` custom messages to session transcript
- `plugin.json` manifest, full documentation suite (README, SPEC, INSTALL, USAGE, GOVERNANCE, TROUBLESHOOTING)

### Changed

- Tool name renamed from `pi-constitution:doctor` to `pi-constitution-doctor` (providers reject colons in tool names)

### Governance

- Plugin maintained inside the Constitution submodule per §11.4.26 / §11.4.28 / §11.4.31
- Initial commits (`6e48cb7c`, `273ee624`) pushed to all 10 Constitution remotes before merge to `main` (`ecfb6339`)
- Consuming project (helix/player) submodule pointer bumped to `ecfb6339` in `cf960b7`

---

## [Unreleased]

Nothing yet.

---

## Upgrade notes

### v1.0.0

- Tool name changed from `pi-constitution:doctor` to `pi-constitution-doctor`. Any scripts or configs referencing the old name must be updated.
- No breaking changes to the audit output format or triage codes.
