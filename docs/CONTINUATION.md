# CONTINUATION — resume point for a fresh session (type just: `continue`)

| Field | Value |
|---|---|
| Revision | 4 |
| Written | 2026-11-18, after the 2026-11-17 merge-all landing (lander subagent) |
| Status | active |
| Mandates | §12.10 continuation, §11.4.131 session-resumption file |

## How to resume

A fresh session in `/home/milosvasic/Projects/constitution` that receives the single word `continue` MUST:
1. Read this file, then the memory index (`~/.claude-claude4/projects/-home-milosvasic-Projects-constitution/memory/MEMORY.md`) and `.remember/now.md`.
2. Verify state before believing it (§11.4.6): `git fetch` all remotes, `git rev-parse main`, `git ls-remote <remote> refs/heads/main` for the 8 remotes, `git tag --list 'helixconstitution-v73*'`, and `ListAgents` (agents from an old session are dead after a reboot).
3. Re-dispatch the owed work below, test-first, LIVE, with independent review (§11.4.142/§11.4.209) and land only on GO. Never edit the real checkout for vehicle work; use fresh clones.

## State at write time (revision 4, 2026-11-18) — re-verify, do not trust

- Operator decision 2026-11-17: merge ALL open PRs into `main` with merge commits, PROVISIONAL (§11.4.290), unresolved findings filed as tracked follow-ups. Done: no PR is open on GitHub (`gh pr list --state open` returned an empty list).
- Merged that wave (merge commit; second parent = reviewed head): #17 03e6645e, #23 61d943d7, #19 60df07ef, #22 d6b1b5d7, #21 68af5edb, #18 dfa9c494, #24 e5db4a1c (killpg allow markers), #25 0d9bfff6 (sync round 14), #26 6f71546e (release-prep fix 3), #27 41b6b7b4 (CON-521 checker r10), #28 e0755689 (CON-402 fallout r5), then the tracker follow-ups PR (this revision).
- Tracker: 563 items; follow-up notes on CON-456, 391, 450, 519, 453, 046, 521, 513, 433, 381, 409, 382, 015, 016, 512; new items CON-585..CON-598. Next free id is CON-599.
- Latest tag `helixconstitution-v73.3` (PROVISIONAL). v73.4 is NOT cut. The §11.4.40 full-suite retest has NEVER been run.

## Owed (from the merge-all wave; details in the tracker notes named above)

1. INCONCLUSIVE runs: `tests/sync/test_faults.sh` timed out at 900 s; the release mutation run and the #17 full mutation run were not executed.
2. Merge resolutions not independently reviewed: the `census.py` union in #28 and the netgate pin regenerated with `pin-regen` in #26.
3. CON-521 checker over main's tracker: 30 provisional items, 16 ok, 14 fail (bodies to fix).
4. Codeberg is not in `LANDER_REMOTES` (land_vehicle.sh contract says nine names; adding it is a contract change, CON-409 note).
5. Fixer trees with no READY marker, not landed (scratch under `/mnt/DATA1TB/claude-work/scratch/`): `fix_con453_r2_20261117T124929` (CON-453 r2, evidence only), `jev_r15.KAuC` (Jev r15, uncommitted changes on top of the r14 pack), `fx046r12.KQXD` (CON-046 r12), intake r12 (no tree found).
6. Release train (§11.4.230(F)): cut v73.4 PROVISIONAL after the above, then the §11.4.40 retest.

## Older state (revision 3, 2026-11-05) — kept for reference, mostly superseded

### Verified state at write time (revision 3, 2026-11-05 evening)

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
