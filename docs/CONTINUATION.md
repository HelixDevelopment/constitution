# CONTINUATION — resume point for a fresh session (type just: `continue`)

| Field | Value |
|---|---|
| Revision | 3 |
| Written | 2026-11-05 (evening, CET), after the CON-031 excluded-list landing |
| Status | active |
| Mandates | §12.10 continuation, §11.4.131 session-resumption file |

## How to resume

A fresh session in `/home/milosvasic/Projects/constitution` that receives the single word `continue` MUST:
1. Read this file, then the memory index (`~/.claude-claude4/projects/-home-milosvasic-Projects-constitution/memory/MEMORY.md`) and `.remember/now.md`.
2. Verify state before believing it (§11.4.6): `git fetch` all remotes, `git rev-parse main`, `git ls-remote <remote> refs/heads/main` for the 8 remotes, `git tag --list 'helixconstitution-v73*'`, and `ListAgents` (agents from an old session are dead after a reboot).
3. Re-dispatch the owed work below, test-first, LIVE, with independent review (§11.4.142/§11.4.209) and land only on GO. Never edit the real checkout for vehicle work; use fresh clones.

## Verified state at write time (revision 3, 2026-11-05 evening)

- `main` = this CONTINUATION commit on top of `1e0c9cbb` (merge of CON-031 excluded list) on all 8 remotes: gitflic, github_helixdevelopment, github_vasic_digital, gitlab_helixdevelopment1, gitlab_vasic_digital, gitverse, m3w, origin. Verify with `git ls-remote`.
- Landed this session: CON-043 (eabcfe0), atm1217 base (7f72395), census-safe (ecfe432), redpin (efe2cc6c), CON-031 excluded list (1e0c9cbb, round 1 GO-with-follow-ups).
- Id ranges: CON-070 is RESERVED for the CON-030 class item; CON-071..CON-091 are taken on main; next free id is CON-092.
- Submodule pins on main: llmctl 391d817, claude_toolkit d3efb3a, containers 5ea870a. The working tree shows ` M submodules/*` drift: NEVER commit it.
- Latest tag: `helixconstitution-v73.3`, PROVISIONAL (§11.4.290). v73.4 is NOT cut. The §11.4.40 full-suite retest has NEVER been run. **The FINAL release is NOT out.** Release checklist: `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/release_readiness.md`.

## In-flight vehicles (not on main; each a clone/branch with a review or fix round pending)

Session dir: `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/` (reports in `scratchpad/*.md`, bundles beside them). Verify each vehicle's head from the clone/branch, do not trust this table.

| Item | State | Report / bundle |
|---|---|---|
| CON-046 | fix round 6, after an operator-approved review-budget extension beyond R_max | `scratchpad/con046_fix_r5_report.md` (latest), `con046_rootcause.md` |
| CON-030 | structural round 3 after gate G3 | `scratchpad/con030_fix_r2_report.md`, `con030_rootcause.md`, `con030_vehicle_report.md` |
| CON-033 | round-2 review pending | `scratchpad/con033_fix_r2_report.md`, `con033_report.md` |
| Ownership wave 2 | round-4 review pending | scratchpad ownership/review reports (see `review_ownership_wave2.md`) |
| Manifest triage | fix round 2 | scratchpad manifest/triage reports, `results.jsonl` |
| atm1217 replacement | NO-GO, reference only, never merge | `scratchpad/atm1217_replacement_report5.md` |

## Operator decisions recorded 2026-11-05

- Census deferral accepted. Podman prune done.
- FINAL QA = agent-roster under a §11.4.271 waiver, authoriser `i@mvasic.ru`, 365-day expiry planned; human manual QA is still OWED.
- CON-031 excluded list: investigate first. `hermetic_lint`: investigate the root cause.
- Token rotation: accept the risk, no rotation.
- `kedge` stays removed (never used, upstream 404, ATM-1164).
- CON-033 refs: create tag `backup/atm1220_r9-held-20261105` on `0558712` and push it to all remotes; delete `wip/review-pending-20261014/atm1220_r9` and `atm1220_r8` ONLY after the merge is confirmed on all 8 remotes.
- Hooks: pin-gate pre-commit after CON-046 GO; destructive-path guard registration is the user's act.

## Operator actions pending (do not do these for them)

- O1: read the diff, then run `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change`.
- O2: CON-091 orphan libs decision.
- O3: missing tool should be FAIL or SKIP.
- O4: override under 60 s.

## Owed work (priority order)

1. Drive each in-flight vehicle to GO and land (independent Opus-xhigh review, merge main, ff-only land, push 8 remotes sequentially, verify `ls-remote`, retire clone with `safe_rm_rf`).
2. Ownership redesign waves 3-7 (memory `project_operator_decisions_2026_11_02.md`; legacy installs via explicit `adopt-install`; C02 stays open).
3. Remaining tracker follow-ups (CON-073..CON-091 and earlier).
4. Release train (§11.4.230(F)): cut v73.4 provisional, run §11.4.40 full retest (default and `--include-heavy`), promote only on pass; tell the operator when FINAL is ready.

## Standing rules to re-apply

§11.4.288 all work on `main` (vehicles ff-only then retired; submodule commit first, parent pointer bump same wave); §11.4.113 never force-push; §11.4.276(G) R_max 5, GO-with-follow-ups for minor-class only; §11.4.289 stubs are unit-class evidence only; §11.4.290 provisional-done labelling; reviewers on Opus-xhigh (Sonnet fallback only with a recorded Opus-unavailability fact); never print secrets; `HOME=$(mktemp -d)` and `${VAR:?}` in scratch scripts; push to the 8 remotes sequentially and verify with `git ls-remote`.
