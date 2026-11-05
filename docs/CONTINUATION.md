# CONTINUATION — resume point for a fresh session (type just: `continue`)

| Field | Value |
|---|---|
| Revision | 2 |
| Written | 2026-11-05 (CET), before an operator-requested host reboot |
| Status | active |
| Mandates | §12.10 continuation, §11.4.131 session-resumption file |

## How to resume

A fresh session in `/home/milosvasic/Projects/constitution` that receives the single word `continue` MUST:
1. Read this file, then the memory index (`~/.claude-claude4/projects (or .claude-claude2)/-home-milosvasic-Projects-constitution/memory/MEMORY.md`) and `.remember/now.md`.
2. Verify state before believing it (§11.4.6): `git fetch` all remotes, `git rev-parse main`, `git ls-remote <remote> refs/heads/main` for the 8 remotes, `git tag --list 'helixconstitution-v73*'`, and `ListAgents` (all agents from the old session are dead after a reboot).
3. Re-dispatch the owed work below, test-first, LIVE, with independent review (§11.4.142/§11.4.209) and land only on GO.

## Verified state at write time (revision 2, 2026-11-05 14:30 CET, before a second operator-requested reboot)

- `main` = this CONTINUATION commit on top of `cb31e32` (CON-034..046 registration) on all 8 remotes: gitflic, github_helixdevelopment, github_vasic_digital, gitlab_helixdevelopment1, gitlab_vasic_digital, gitverse, m3w, origin. Verify with `git ls-remote`.
- Submodule pins on `main`: llmctl 391d817, claude_toolkit d3efb3a, containers 5ea870a. Working tree always shows ` M submodules/*` drift: NEVER commit it.
- Latest tag: `helixconstitution-v73.3`, PROVISIONAL (§11.4.290). **The FINAL release is NOT out; not every workable item is done.** Tell the operator when it is.
- Oracle-ratchet baseline = 64 entries, all in 3 frozen RED-evidence files under `submodules/llmctl/specs/009-jev-decision-models/evidence/p1-red-original/harness/py/`.
- All agents were stopped before this reboot (the weekly API limit had killed three earlier; they were respawned and then stopped on purpose). Nothing is running.

## Unlanded work (NOT on main). Every item is a branch `wip/continue-20261105b/<name>` on all 8 remotes AND a clone on disk

| Item | Branch / clone | Head | State |
|---|---|---|---|
| Census safe-part | `wip/continue-20261105b/census-safe`; clone `~/.cache/claude-tmp/censafe.3dfZ/c` (`vehicle/census-safe`) | dbe1b65 on cb31e32 | 4 commits: CON-015/016, extra jq-region tests, 2 allowlist rows, closure N3-negative as KNOWN-FAIL (CON-047). Author: jq-region 38/0, closure 30 pass + 1 known-fail (exit 3), allowlist gate PASS uncovered=0. Allowlist mutation test (~10 min) was still running and unfinished (so far F4/N3a/N3b killed). Opus review started, was stopped, NOT done. NEXT: Opus-xhigh review, run mutation test, on GO merge main, land ff-only, push, verify. CON-017 (0e4b197) and rewrite 94a1d28 stay OUT. Bundle: session scratchpad `census_safe.bundle`, report `scratchpad/census_safe_report.md`. |
| Manifest + triage | `wip/continue-20261105b/manifest-triage`; clone `~/.cache/claude-tmp/mt.b8Df3W/c` (`vehicle/manifest-triage`) | c1ac3a1 | Manifest rows added (author claims MANIFEST-OK, census 841): UNVERIFIED by me. The ~138-failure triage is NOT finished (a full-suite run was in progress, results in scratchpad `results.jsonl`/`fullsuite_*.log`). Never run `--accept-excluded-change` (operator's act). |
| Ownership wave 2 round 2 | `wip/continue-20261105b/ownership-wave2-r2`; clone `<scratchpad>/w2r2.fv9mI4/c` (`vehicle/ownership-wave2`) | 6b7462a (WIP snapshot, unreviewed) | Round 1 was commit 96574e3 (NO-GO, findings in `scratchpad/review_ownership_wave2.md`). Round 2 in progress: adopt-install command, honest refusal, keep C02 open (lint F5, per-suite before/after tree check, convert 3 installer suites to throwaway copies), F3/F4/F6/F7/F8, design doc rev 4. Uncommitted edits were snapshotted in 6b7462a. |
| atm1217 replacement | clone `~/.cache/claude-tmp/atm1217rep.8jTn/c` f26ae1a | | NO-GO, reference only, never merge. |

Session scratchpad: `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/` (reports, reviews, bundles). It survives reboot but `/tmp` does not.

## Owed work (priority order)

1. Land census safe-part, then manifest/triage, then ownership wave 2 (each: independent Opus-xhigh review, GO, merge main, ff land, push 8 remotes, verify `ls-remote`, retire clone with `safe_rm_rf`).
2. After MANIFEST-OK lands, ASK the operator to run `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change "i@mvasic.ru"`.
3. Ownership redesign waves 3-7 (decisions in memory `project_operator_decisions_2026_11_02.md`; new answers: legacy installs via explicit `adopt-install`; C02 stays open).
4. Remaining tracker follow-ups CON-034..047 (CON-047 is the census N3 false positive; structural fix: judge only jq's program operand). CON-033 closure.
5. Continuous release train (§11.4.230(F)): cut v73.4 provisional, run §11.4.40 full retest (default and `--include-heavy`), promote only on pass.

## Open operator questions (do not decide for them)

- Land the two atm1217 base commits (c67292d, 013514e) separately, or leave them on the `wip/` branches?
- Accept excluding the three frozen RED-evidence files via the gate change in item 4, rather than annotating them?
- Disk is ~98% full (40 GB free of 1.8 TB); `~/.cache/claude-tmp` holds ~567 GB of mostly leftover scratch. Cleanup needs the operator's permission.

## Standing rules to re-apply

§11.4.288 all work on `main` (vehicles ff-only then retired; submodule commit first, parent pointer bump same wave); §11.4.113 never force-push; §11.4.276(G) R_max 5, GO-with-follow-ups for minor-class only; §11.4.289 stubs are unit-class evidence only; §11.4.290 provisional-done labelling; reviewers on Opus-xhigh (Sonnet fallback only with a recorded Opus-unavailability fact — the oracle wave b2/b3 reviews ran on Sonnet 5.5 WITHOUT such a record; flag it); never print secrets; HOME=$(mktemp -d) and `${VAR:?}` in scratch scripts; push parent via `scratchpad/push_main2.sh` pattern (8 remotes, background + verify with `git ls-remote`).
