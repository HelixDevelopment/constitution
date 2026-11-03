# Tutorial 08 - Using the decisions wizard

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T11:30:00Z |
| Status | draft |
| Status summary | Steps follow `constitution_decisions.sh --help`; all five steps and the weakening refusal were run on 2026-10-31 in a throwaway git project; the committed transcript [`docs/qa/decisions_wizard_tutorial_run.txt`](../qa/decisions_wizard_tutorial_run.txt) is the only evidence, nothing else counts (rc 0 for steps 1 to 5, rc 4 for the refusal; `--check` printed `check: OK (2 override(s))`, and after `--reset` the `--import` replay restored `calibration.floor` 0.95). |
| Authority | `docs/design/decisions_wizard_plan.md`. |
| Scope | Record, review and replay decision-model choices for a project. |
| Issues | none |

Prerequisite: a git project with the constitution installed (`submodules/constitution`, or legacy `constitution`).

```bash
D=submodules/constitution/scripts/decisions/constitution_decisions.sh
bash $D --show                                   # 1. see the effective values
bash $D --set layer.mode=shadow --set calibration.floor=0.95 --non-interactive   # 2. record two overrides
bash $D --check                                  # 3. expect: check: OK (2 override(s))
bash $D --export decisions_export.yml            # 4. save them
bash $D --reset && bash $D --import decisions_export.yml --non-interactive        # 5. replay
```

Notes: step 2 prints a backup path and a `bootstrap (printed, NOT run)` line; run that bootstrap yourself if you want it. Step 5 (`--reset` then `--import` of the exported file) was replayed in that sandbox and restored the two overrides; only that one sandbox run was made (one host, no CI). A weakening such as `--set hosted.enforce=true` exits 4. Commit `.constitution/decisions.yml` and the managed doc block; keep `.constitution-install-backup/` out of git.

Related: [guide](../guides/decisions_wizard_guide.md), [FAQ](../faq/decisions_wizard_faq.md), [CI tutorial](04_non_interactive_ci.md).
