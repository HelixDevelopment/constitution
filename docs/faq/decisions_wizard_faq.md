# Decisions Wizard FAQ

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-29 |
| Last modified | 2026-10-30T09:00:00Z |
| Status | draft |
| Status summary | Answers taken from `constitution_decisions.sh --help` and a sandbox run on 2026-10-30. |
| Authority | `docs/design/decisions_wizard_plan.md`; §11.4.279 to §11.4.286, §11.4.35. |
| Scope | Questions about the decisions wizard. |
| Issues | none |

**1. Does the wizard exist?** Yes: `scripts/decisions/constitution_decisions.sh` (see the [guide](../guides/decisions_wizard_guide.md)).

**2. Interactive only?** No. On a TTY with no action flag it asks every decision; `--non-interactive` with `--set`, `--answers` or `--import` works without one (exit 2 if there is no TTY and no `--non-interactive`).

**3. Does it call an LLM or the network?** No (`--help`: no network, no LLM). `--plan --probe` may call `llmctl plan --json` (hardware probe, no model start).

**4. Where are decisions stored?** `<project>/.constitution/decisions.yml` plus a managed block in the project's agent-doc files that exist. `--scope user` writes the user file instead.

**5. Can I weaken a constitution rule?** No. A locked rule can only be kept or tightened (exit 4), for example `hosted.enforce=true` is refused.

**6. Does it run the Jev bootstrap?** No. It prints the `bootstrap.sh` command and does not run it.

**7. What if I edit decisions.yml by hand?** The check against `.constitution/decisions.sha256` reports it; `--accept-external-edits` accepts it. Every value is validated regardless.

**8. How do I undo a change?** Backups are in `.constitution-install-backup/<UTC>-decisions/`; or use `--unset KEY` / `--reset`.

**9. Why exit 3 on a project without the submodule?** Writes need an inherited constitution; pass `--inherits PATH` and confirm, or install the constitution first ([installer](../guides/installer_user_guide.md)).

**10. Are there `/…` agent commands?** Proposed only (`scripts/decisions/registry_rows_proposal.yaml`); UNCONFIRMED that any is wired.

**11. Can another process redirect a write while the wizard runs?** Narrowed, not eliminated. Each file is written through a directory descriptor opened before the final checks, so swapping a parent folder for a symlink into another repository is refused or harmless. Still possible for a writer with access to your project at that instant: renaming the validated folder itself into another repository. Do not run the wizard in a tree others write to concurrently.

Related: [guide](../guides/decisions_wizard_guide.md), [tutorial 08](../tutorials/08_decisions_wizard.md).
