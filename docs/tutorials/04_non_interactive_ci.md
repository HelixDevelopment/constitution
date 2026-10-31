# Tutorial 04 - Non-interactive and CI use

| Field | Value |
|---|---|
| Revision | 4 |
| Created | 2026-10-29 |
| Last modified | 2026-10-31T11:30:00Z |
| Status | draft |
| Status summary | Running without a TTY. Reconciled with the final scripts (--help and source) on 2026-10-29; not verified by a live end-to-end install. |
| Authority | Tool documentation for `scripts/install_constitution.sh` and `scripts/update_constitution.sh`; no new anchor. §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Step-by-step tutorial for the installer. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not generated (Markdown-only policy). |

1. Pin a ref and skip the agent.

```bash
# works only after the release is pushed and tagged (see the README Availability note); v73 is a placeholder number until that tag exists
curl -fsSL https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh | bash -s -- --non-interactive --agent none --ref helixconstitution-v73 --report-json install_report.json
```

2. Branch on the exit code: 0 ok, 1 failure, 2 usage or no terminal, 3 precondition, 4 agent, 5 verification, 6 agent success unverified (`opencode`/`pi`; only with an agent) (130 / 143 interrupted). With `--agent none` exit 6 cannot occur.
3. Upload `install_report.json` as an artifact. Never print secrets in CI logs.
4. Needs bash 4.4+ and git on the runner; the clone is blobless, so the runner needs network access to the upstream (or pass `--upstream-url` with a mirror). Do not set `GIT_SSH_COMMAND` for the installer: it is not inherited; use `~/.ssh/config`.
5. Use `--upstream gitlab` (or another key) if GitHub is unreachable from your runner.

Note: this repository mandates no hosted CI for itself (§11.4.156); this tutorial is for consumers who run their own automation. Back: [manual](../manuals/installer_manual.md).
