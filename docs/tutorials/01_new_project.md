# Tutorial 01 - Add the constitution to a new project

| Field | Value |
|---|---|
| Revision | 3 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T18:00:00Z |
| Status | draft |
| Status summary | Fresh project walkthrough. Reconciled with the final scripts (--help and source) on 2026-10-29; not verified by a live end-to-end install. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Step-by-step tutorial for the installer. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not generated (Markdown-only policy). |

1. Create a git repository.

```bash
mkdir my_project && cd my_project && git init
git commit --allow-empty -m "init"
```

2. Preview the plan.

```bash
curl -fsSL https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh -o install_constitution.sh
bash install_constitution.sh --dry-run --agent none      # add --git-init if the folder is not yet a repository
```

3. Install without an agent.

```bash
bash install_constitution.sh --agent none
```

4. Check the result: `ls submodules/constitution`, `git status`, and the report if you passed `--report-json` (a copy is always in `.constitution-install-backup/<timestamp>/report.json`).
5. If you pass `--agent`, note `--max-budget-usd` is a total cap (default 2, at most 50). Commit the staged changes yourself: `git commit -m "chore: add constitution"` (or pass `--commit on` to have the installer make one local commit). The installer never pushes.

Next: [tutorial 05](05_choosing_agents_and_aliases.md). Back: [FAQ](../faq/installer_faq.md).
