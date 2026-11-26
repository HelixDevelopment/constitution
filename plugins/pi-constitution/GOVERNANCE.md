# pi-constitution — Constitution Compliance Traceability

**Version:** 1.0.0 · **Classification:** universal (per §11.4.17) · **Owner:** Constitution submodule

This document traces every rule this plugin implements or complies with, to the
Constitution anchor that mandates it. It is the compliance record for auditors
and reviewers.

---

## Table of contents

- [Classification](#classification)
- [§11.4.26 — Constitution-Submodule Update Workflow](#11426--constitution-submodule-update-workflow)
- [§11.4.28 — Submodules-As-Equal-Codebase](#11428--submodules-as-equal-codebase)
- [§11.4.31 — Submodule-Dependency-Manifest](#11431--submodule-dependency-manifest)
- [§11.4.32 — Post-Constitution-Pull Validation](#11432--post-constitution-pull-validation)
- [§11.4.17 — Universal-vs-Project Classification](#11417--universal-vs-project-classification)
- [§11.4.2 — Recorded-Evidence Requirement](#1142--recorded-evidence-requirement)
- [§11.4.6 — Honest Limits](#1146--honest-limits)
- [Traceability matrix](#traceability-matrix)

---

## Classification

**Universal.** The pi-constitution Pi extension is a binding for the Constitution
governance layer itself. Per §11.4.17, universal additions belong in the
constitution submodule; project-specific clauses belong in the consuming project.
This plugin is therefore maintained exclusively inside
`submodules/constitution/plugins/pi-constitution/` and never in a consuming
project's local tree.

---

## §11.4.26 — Constitution-Submodule Update Workflow

**Anchor:** Mandates fetch+pull before editing, commit inside submodule, push to
all upstreams, merge to main, bump consumer pointer, post-merge validation.

| Requirement | Plugin compliance | Evidence |
|---|---|---|
| Fetch + pull all remotes before edit | Plugin commits follow this workflow; documented in GOVERNANCE + INSTALL | `git log` on `plugins/pi-constitution/` shows task-branch commits pushed to all remotes before main merge |
| Commit inside submodule first | All plugin changes committed inside `submodules/constitution` | `plugins/pi-constitution/*` files are under `submodules/constitution/` |
| Push to ALL upstreams | Verified: all 10 Constitution remotes received `ecfb6339` on `main` | Remote tracking confirmed at `ecfb6339` for codeberg, gitflic, github_helixdevelopment, github_vasic_digital, gitlab_helixdevelopment1, gitlab_vasic_digital, gitverse, m3w, origin, upstream |
| Merge to main via --no-ff | Both plugin commits merged to main with `--no-ff` | `git log --oneline` shows merge commits `b8650530` and `ecfb6339` |
| Bump consumer pointer in same window | Player repo bumped submodule pointer to `ecfb6339` in commit `cf960b7` | Player `git log` shows `cf960b7 build(submodules): bump constitution submodule to ecfb6339` |
| Post-merge validation | `pi-constitution-doctor` run after every merge; all checks green | Doctor output verified healthy at `ecfb6339` |

---

## §11.4.28 — Submodules-As-Equal-Codebase

**Anchor:** Submodules are treated as equal codebases; changes propagate through
submodule commits first.

| Requirement | Plugin compliance | Evidence |
|---|---|---|
| Submodule is an equal codebase | `plugins/pi-constitution/` is a full Pi extension with manifest, implementation, docs, tests | Complete extension tree under `submodules/constitution/plugins/pi-constitution/` |
| Changes propagate through submodule commits | Plugin committed on task branch inside submodule, pushed, merged, then consumer pointer bumped | `6e48cb7c` → `b8650530` (merge) → `ecfb6339` (main on all remotes) → player `cf960b7` |
| No nesting of own-org repos | Plugin has no submodules of its own | `plugins/pi-constitution/.gitmodules` does not exist |

---

## §11.4.31 — Submodule-Dependency-Manifest

**Anchor:** Every owned submodule ships a `helix-deps.yaml` declaring its deps.

| Requirement | Plugin compliance | Evidence |
|---|---|---|
| Ship `helix-deps.yaml` | pi-constitution has no own-org submodule dependencies (`deps: []`) | The Constitution submodule root ships `helix-deps.yaml`; pi-constitution is a plugin directory within it, not a separate submodule |
| Manifest is the bridge | No nested dependencies to bridge | N/A — no deps |

---

## §11.4.32 — Post-Constitution-Pull Validation

**Anchor:** After any constitution pull, run full-project + recursive validation.

| Requirement | Plugin compliance | Evidence |
|---|---|---|
| Validation sweep available | `pi-constitution-doctor` provides the Constitution-specific portion of the sweep | Doctor checks submodule presence, governance files, mandate sections |
| Failures are directed | Each triage error names the code, message, and next command | Triage messages include `details.code`, `details.message`, `details.nextCommand` |
| Failures block canonical treatment | `session_start` status reflects unhealthy state; peer gate blocks operations | `ctx.ui.setStatus("constitution", "Constitution: N issue(s)")`; `tool_call` returns `block: true` |

---

## §11.4.17 — Universal-vs-Project Classification

**Anchor:** Only universal additions belong in the constitution submodule.

| Classification | Reasoning |
|---|---|
| Universal | The Pi binding for Constitution governance is a universal concern: every project that consumes the Constitution via Pi benefits from the same audit + guard behavior |
| Not project-specific | No FUSE-player-specific logic; no music-player domain knowledge; purely governance plumbing |

---

## §11.4.2 — Recorded-Evidence Requirement

**Anchor:** Every claim of working/passing/verified must cite machine-created, machine-verifiable evidence.

| Claim | Evidence |
|---|---|
| "Constitution governance is healthy" | `pi-constitution-doctor` structured result: `errorCount: 0`, `verifiedCount: 8`, all governance files present, all mandate sections present |
| "Submodule present at HEAD ecfb6339" | `git rev-parse HEAD` output captured in `structuredContent.submoduleHead` |
| "All 10 remotes have ecfb6339" | `git fetch --all` + `git rev-parse <remote>/main` confirmed `ecfb6339` for every remote |

---

## §11.4.6 — Honest Limits

**Anchor:** Document what is NOT proven, with no escape hatches.

| What is proven | What is NOT proven | Notes |
|---|---|---|
| Submodule is present on disk | Submodule content matches upstream tip exactly | Drift between `gitlink` and submodule HEAD is covered by `CM-DEPENDENCY-POINTER-PREFLIGHT-FAIL-CLOSED` (§11.4.233(G)), not by this plugin |
| Governance files exist | Governance file content is correct | Content correctness is the Constitution maintainer's responsibility; this plugin only checks presence + mandate-section references |
| Mandate sections are referenced | Mandate sections are correctly implemented | Reference ≠ implementation quality |
| `pi-constitution-doctor` passes | The extension itself is bug-free | The extension is a thin audit layer; bugs in it would produce false negatives/positives |
| All 10 remotes have ecfb6339 on main | All remotes are reachable / writable | Pushes were confirmed; read access after push is assumed |

No `--skip-*` flags exist. No escape hatch.

---

## Traceability matrix

| Constitution anchor | Anchor title | Plugin file(s) | Compliance evidence |
|---|---|---|---|
| §11.4.2 | Recorded-evidence requirement | `pi-constitution.ts` (audit + sendMessage) | `pi-constitution.audit` / `pi-constitution.triage` custom messages |
| §11.4.6 | Honest limits | `GOVERNANCE.md` (this file, §Honest Limits) | Limits table above |
| §11.4.17 | Universal-vs-project classification | `GOVERNANCE.md` (Classification) | Universal classification justified |
| §11.4.26 | Submodule update workflow | `INSTALL.md` (Workflow), `USAGE.md` (Workflow 2) | Documented 7-step workflow |
| §11.4.28 | Submodules as equal codebase | `plugins/pi-constitution/` (full extension tree) | Extension is self-contained within submodule |
| §11.4.31 | Dependency manifest | `plugins/pi-constitution/` (`deps: []`) | No own-org submodule deps |
| §11.4.32 | Post-pull validation | `pi-constitution-doctor` | Doctor runs the Constitution-specific validation sweep |
