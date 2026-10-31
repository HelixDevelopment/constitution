# Known full-suite failures carried into v73

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-31 |
| Status | investigation record; not linked from any index yet |
| Source | CHANGELOG.md v72.2, known imperfection 6 (41 failing entries of the §11.4.40 run) |
| Base | main at 9d78ce7 (merge of origin/main), working tree with the fixes named below |

Ranking: impact first (false refusal of a correct tree, then real defect), then effort. "PROVEN" means reproduced in this session with the command shown; anything else is marked UNCONFIRMED.

## Fixed in this pass (pending review, not committed)

| Item | Root cause | Evidence |
|---|---|---|
| CM-CANONICAL-ROOT-CLARITY | PROVEN. In a standalone canon checkout named `.../constitution`, `cl_project_root_of` matched the legacy-layout rule and took the parent directory as the consumer, so invariant (a) audited a `CLAUDE.md` nobody owes (false refusal, §11.4.201(1)). | Before: `(a) ... consumer CLAUDE.md missing ... at /home/milosvasic/Projects/CLAUDE.md`, rc=1. After: `(a) ... SKIP — standalone canon checkout`, rc=3; (b)/(c) still enforced. Paired mutation test adds G6, M11–M14. |

## Fixed upstream by another session (not by this pass)

- CM-KILLPG-PGID-GUARD (commits 180f7ef, 5bdc833).
- CM-CLI-AGENT-PLUGINS-WIRED invariant 9 (the hook calls `run_step install_action_plugins`; the old check matched only a bare call) and the `register.sh` mode.

## Remaining

| Rank | Item | Root cause | Status | Effort |
|---|---|---|---|---|
| 1 | `scripts/anchors/tests` (24 of 61 fail) | The tests use cwd-relative paths such as `constitution/Constitution.md`, i.e. they assume they run from a consumer root. From the canon root: 24 failed, 37 passed. From a scratch dir holding a `constitution` symlink to the canon: 1 failed, 60 passed. | PROVEN | 1–2 h (resolve paths from `__file__` in 9 files; the `location` assertions also embed the `constitution/` prefix, so it needs care) |
| 2 | `test_wiring_audit_us4.py::test_control_needles_pass_selftest` | Fails even from the consumer-shaped cwd. | UNCONFIRMED | unknown |
| 3 | CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT, CM-DANGEROUS-COMBINATION-FAIL-CLOSED (and other scanners) | Default scan root is `..` relative to the CWD. Run from the canon root it scans the whole parent directory (every sibling project), so findings may come from other repositories and the run takes many minutes. The CHANGELOG's "real canon defect" classification for these two is UNCONFIRMED until each is re-run with `--root .`. | Default-root behaviour PROVEN (source line `root="${..._ROOT:-..}"`); findings UNCONFIRMED | 1 h to decide the default (gate design question, §11.4.66) |
| 4 | CM-CLI-AGENT-PLUGINS-WIRED invariant 6 | `skills/constitution/` (added in a0609ec) has no `register.sh`. New since the v72.2 list. | PROVEN (gate output) | small, but owned by the constitution-cmd work |
| 5 | `tests/test_cli_agent_plugins.sh` | An installed skill is a copy, not a symlink (CHANGELOG). | UNCONFIRMED here (portable symlink files are being changed by another session) | unknown |
| 6 | CM-INSTRUMENT-TRAP-SCAN (BLIND), CM-CONTROL-NEEDLE-REQUIRED, CM-CONTINUUM-RESUME-ENGINE-PRESENT, CM-RULE-BINDS-TO-SEAM, CM-UNREFERENCED-GATE-BOUND-OR-RETIRED, CM-MUTATION-SCORE-ON-DIFF, CM-GIT-HOOKS-INSTALLED, CM-OPENDESIGN-UI-SYSTEM mutation test, CM-CODEGRAPH-MCP-HEALTH (+ mutation test) | Not root-caused. | UNCONFIRMED | unknown, each |
| 7 | nine `tests/jev` scripts | Appear to read the host toolkit MCP configuration. | UNCONFIRMED | unknown |
| 8 | Consumer-layout gates: bridge-layer presence, escape ratchet, dependency-register verdicts, mechanism-observed-refusing, zero-findings sweep and ratchet, version-increment-on-deploy, healthcheck ports, first-refusal, Jev detection, Jev token-reduction, nested-markdown-fence leak | Need consumer data or layout. The fix applied to CM-CANONICAL-ROOT-CLARITY (honest SKIP when standalone is proven) is the likely pattern, gate by gate. | UNCONFIRMED per gate | 0.5–1 h each |
