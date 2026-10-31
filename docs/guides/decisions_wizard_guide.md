# Decisions Wizard Guide

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T11:30:00Z |
| Status | draft |
| Status summary | Reconciled on 2026-10-30 with the landed `scripts/decisions/constitution_decisions.sh --help` and a read-only sandbox run (`--show`, `--set`, `--check`). Not verified by a live Jev run; `bootstrap.sh` is never run by the wizard. |
| Authority | Tool documentation for `scripts/decisions/constitution_decisions.sh`; plan in `docs/design/decisions_wizard_plan.md`. §11.4.279 to §11.4.286, §11.4.35, §11.4.10, §11.4.18 govern. |
| Scope | Operators who record decision-model choices (Jev decision layer and other decision models) for a project or a user. |
| Issues | The `/jev_decisions`-style agent commands are a registry-row proposal (`scripts/decisions/registry_rows_proposal.yaml`), not wired: UNCONFIRMED that any agent command exists. |

## What it does

Records decision-model choices as LOCAL PROJECT OVERRIDES that inherit from the constitution (§11.4.35). Output: `<project>/.constitution/decisions.yml` plus a marker-delimited block in the project's `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `QWEN.md` (only files that already exist). A locked constitution rule can only be kept or tightened; a weakening override is refused. It makes no network call, calls no LLM, never edits `settings.json` and never runs `scripts/jev/bootstrap.sh` (it prints the command instead).

## Commands

```bash
D=submodules/constitution/scripts/decisions/constitution_decisions.sh   # legacy layout: constitution/scripts/decisions/...
bash $D                                  # on a TTY: asks every decision (answers read from /dev/tty)
bash $D --show [--json]                  # effective values and where each comes from
bash $D --check                          # verify the file is untampered and consistent
bash $D --plan [--probe]                 # what would be done
bash $D --set layer.mode=shadow --set calibration.floor=0.95 --non-interactive
bash $D --unset calibration.floor
bash $D --reset
bash $D --answers FILE | --import FILE   # replay saved answers
bash $D --export FILE|-  [--force-export]
```

Other flags (from `--help`): `--project-root DIR`, `--scope project|user`, `--doc FILE` (repeatable), `--dry-run`, `--non-interactive`, `--accept-external-edits`, `--accept-env`, `--inherits PATH`, `--version`.

- `--accept-env` takes consents and layer mode from `JEV_BOOTSTRAP_*` environment variables; without it they are ignored with a note.
- `--inherits PATH` records or accepts an inherited constitution path. Needed with explicit confirmation for a project that has neither `submodules/constitution` nor `./constitution`, or for the HOME directory. Writes otherwise need a git repository root that holds an inherited constitution (both layouts work).
- `--force-export` lets `--export` replace an existing file (a backup is taken first); `--export` never writes into `.git/` or `.constitution/` or outside the project.
- `--scope user` writes the user file (`$CONSTITUTION_DECISIONS_USER_FILE`, else under `$XDG_CONFIG_HOME`), its lock and its `.decisions-backup/`; this is the only write outside the project.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | done (including no change) |
| 1 | internal failure |
| 2 | usage, or no TTY without `--non-interactive` |
| 3 | precondition: bad project root, `python3` or PyYAML missing, path outside the project, symlinked target, write target inside a submodule / another repository / the inherited constitution, no inherited constitution |
| 4 | refused: unknown key, weakening of a locked rule, a NEW contradiction, a secret-like value, a tampered file, broken markers |
| 5 | another run holds the lock |

## Observed in a sandbox (2026-10-30, re-run 2026-10-31)

Only the committed transcript [`docs/qa/decisions_wizard_tutorial_run.txt`](../qa/decisions_wizard_tutorial_run.txt) (2026-10-31, one throwaway project, `submodules/constitution` a symlink to the checkout) is evidence; the values quoted below are from the earlier 2026-10-30 run, which has no committed transcript, and are UNCONFIRMED until compared with it.

In a throwaway git project with an empty `submodules/constitution` directory: `--show` listed 20 keys all `[constitution]` (for example `layer.mode shadow`, `calibration.floor 0.9`, `hosted.enforce false`, `llmctl.validate_strict true`); `--set layer.mode=shadow --set calibration.floor=0.95 --non-interactive` printed a note to add `.constitution-install-backup/` to `.gitignore`, `backup: .constitution-install-backup/<UTC>-decisions`, `written: .constitution/decisions.yml`, `written: CLAUDE.md` and the `bootstrap (printed, NOT run): ...` line; the file held only `calibration.floor: 0.95` and `layer.mode: shadow` under `schema_version: 1` and `inherits: submodules/constitution`; `--set hosted.enforce=true` printed `refused: hosted.enforce is locked by the constitution to false; a local override may not weaken it`; `--check` printed `check: OK (2 override(s))`. The refusal's exit status was not captured separately; `--help` documents 4.

## Files and backups

| Path | Content |
|---|---|
| `.constitution/decisions.yml` | only the overridden keys, sorted, no timestamps |
| `.constitution/decisions.sha256` | hash of the last written file; detects hand edits (provenance, not a defence against an attacker) |
| `.constitution/.decisions.lock` | lock; a second concurrent writer exits 5 |
| `.constitution-install-backup/<UTC>-decisions/` | copy of every file a run is about to change; the newest `CONSTITUTION_DECISIONS_BACKUP_KEEP` (default 20) are kept per location |
| managed block in `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `QWEN.md` | between `BEGIN` / `END constitution-decisions` markers; text outside is never touched |

Key catalogue, locked rules (for example `hosted.enforce`, `keys.discovery_consent`, `llmctl.validate_strict`, `proof.token_reduction_arm`) and precedence (constitution < user file < project file < `JEV_BOOTSTRAP_*` env < `--answers` < `--set`): see the [plan](../design/decisions_wizard_plan.md), section 4. The plan records an open conflict: `layer.mode=off` against §11.4.279(E).

## Safety

Destructive-path rules of §11.4.287 apply to the script; a secret-shaped value is refused and never echoed; unknown keys are shown as `key#<hash prefix>`. Env names only are read; values are never printed.

See the [decision flow diagram](../diagrams/decision_flow.md), the [FAQ](../faq/decisions_wizard_faq.md) and [tutorial 08](../tutorials/08_decisions_wizard.md).
