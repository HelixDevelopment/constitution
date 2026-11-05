# CONTINUATION — resume point for a fresh session (type just: `continue`)

| Field | Value |
|---|---|
| Revision | 1 |
| Written | 2026-11-05 (CET), before an operator-requested host reboot |
| Status | active |
| Mandates | §12.10 continuation, §11.4.131 session-resumption file |

## How to resume

A fresh session in `/home/milosvasic/Projects/constitution` that receives the single word `continue` MUST:
1. Read this file, then the memory index (`~/.claude-claude2/projects/-home-milosvasic-Projects-constitution/memory/MEMORY.md`) and `.remember/now.md`.
2. Verify state before believing it (§11.4.6): `git fetch` all remotes, `git rev-parse main`, `git ls-remote <remote> refs/heads/main` for the 8 remotes, `git tag --list 'helixconstitution-v73*'`, and `ListAgents` (all agents from the old session are dead after a reboot).
3. Re-dispatch the owed work below, test-first, LIVE, with independent review (§11.4.142/§11.4.209) and land only on GO.

## Verified state at write time

- Real repo `main` = `1644f06` (oracle wave b3) on all 8 remotes: gitflic, github_helixdevelopment, github_vasic_digital, gitlab_helixdevelopment1, gitlab_vasic_digital, gitverse, m3w, origin (verified with `git ls-remote`; this CONTINUATION commit comes after it).
- Submodule pins on `main`: `llmctl` f39ff09 (5 remotes: github/gitlab vasic-digital, gitflic, gitverse, codeberg), `claude_toolkit` 268ddf4 (4 remotes), `containers` 5ea870a.
- Working tree always shows ` M submodules/claude_toolkit|containers|llmctl` (pre-existing local pointer drift). NEVER commit those three entries.
- Latest tag/release: `helixconstitution-v73.3`, a PROVISIONAL pre-release (§11.4.290). **The FINAL release is NOT out. Not every workable item is done.** Tell the operator when it is.
- Oracle-ratchet baseline `config/oracle_ratchet_baseline.txt` = 64 entries, ALL in the three frozen RED-evidence files under `submodules/llmctl/specs/009-jev-decision-models/evidence/p1-red-original/harness/py/` (`n_tests.py` 29, `test_d16_d32.py` 20, `test_defects_d01_d15.py` 15). Non-frozen debt is zero.

## Unlanded vehicles (work done, NOT on main) — also pushed as branches `wip/continue-20261105/<name>` to all 8 remotes

| Vehicle | Local clone (on disk) | Head | State |
|---|---|---|---|
| census follow-ups | `~/.cache/claude-tmp/tmp.EP8YhTHVJ2/c`, branch `vehicle/census-followups` | 0e4b197 (on merge of main 006da9f) | Author evidence: jq-region suite 47/0, closure test 31/0, allowlist gate PASS uncovered=0, census byte-identical (1581 rows). Delta review (CON-017 + 2 allowlist rows) was RUNNING and did not report. NEXT: re-run delta review; on GO merge current `main` (1644f06) into it, land ff-only, push to 8 remotes, verify, retire. |
| ownership wave 1 | `~/.cache/claude-tmp/tmp.5klGZMMcWm/c`, branch `vehicle/ownership-wave1` | 2ad4d66 (on 265f019) | `scripts/constitution_ext/wiring_ledger.py` fixes F1-F5 + `docs/design/extension_engine_ownership_redesign.md` rev 2. Author: 162/0 tests, 25/25 mutants killed. Rollback-limited re-review was RUNNING and did not report. NEXT: re-review; on GO merge `main`, land, push, verify, retire; then waves 2-7. |
| atm1217 replacement | `~/.cache/claude-tmp/atm1217rep.8jTn/c`, branch `vehicle/atm1217-replace` | f26ae1a | NO-GO at round 5. Per operator decision: baseline-delta ABANDONED, whole-file kept. Kept only as a reference; do NOT merge. Base commits c67292d and 013514e live only on `wip/review-pending-20261014/atm1217-*` branches. |

Landed scratch clones that can be deleted (use a `${VAR:?}`-guarded path / `safe_rm_rf`, §11.4.287): `~/.cache/claude-tmp/b3.sUar`, `al.V6Hb8I`, `agm.YIe172`, and the oracle-wave a1/b1/b2 clones.

## Owed work (priority order)

1. Land the census and ownership vehicles above (independent GO first).
2. Full-suite triage (agent `affbe31…` completed earlier; its hand-back is in the old session): add the 19 manifest rows so `scripts/run_full_suite.sh --verify-manifest` reports MANIFEST-OK, triage the 138 default-run failures (author's UNCONFIRMED classification: ~15 install tests fail only for lack of a local `main`, ~54 fastcycle tests assume the consumer layout, a few canon defects, 19 deliberate RED tests, Go tests with GOPROXY=off). Then ASK the operator to re-run `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change "i@mvasic.ru"` (acceptance is theirs).
3. Ownership redesign waves 2-7 (decisions D1-D6 in memory `project_operator_decisions_2026_11_02.md`).
4. Register follow-ups in the tracker (ticket key CON, `docs/Issues.md`, `docs/workable_items.db`, via the engine, not by hand): atm1217 redirect-target class (`echo 'touch M' >> /dev/stdin`, `>> "$0"` credited by the delta check); census `BASH` misses (line continuation after a builtin, quote-spliced name) and string-literal false positives; census blind spots (jq program produced by sed then run later; `bash -c` with an inner single quote inside double quotes); `replica_for` symlink-write guard; ownership F6 items (TOCTOU only narrowed, refs never pruned, gc/doctor handling of `X.refs`); frozen-evidence exclusion gate change (checked-in per-file list, closed class set, git blob sha voiding the entry on mismatch, no globs, count monotone-nonincreasing, proof no runner executes them); `# basis:` line not gate-enforced; CON-033 closure.
5. Continuous release train (§11.4.230(F)): cut v73.4 provisional (changelog, tag, push to all remotes, GitHub/GitLab/Gitea releases), run the §11.4.40 full retest (default and `--include-heavy`) on a properly initialised checkout, promote to production only on a pass.

## Open operator questions (do not decide for them)

- Land the two atm1217 base commits (c67292d, 013514e) separately, or leave them on the `wip/` branches?
- Accept excluding the three frozen RED-evidence files via the gate change in item 4, rather than annotating them?
- Disk is 99% full (19 GB free of 1.8 TB); `~/.cache/claude-tmp` holds ~567 GB of mostly leftover scratch. Cleanup needs the operator's permission.

## Standing rules to re-apply

§11.4.288 all work on `main` (vehicles ff-only then retired; submodule commit first, parent pointer bump same wave); §11.4.113 never force-push; §11.4.276(G) R_max 5, GO-with-follow-ups for minor-class only; §11.4.289 stubs are unit-class evidence only; §11.4.290 provisional-done labelling; reviewers on Opus-xhigh (Sonnet fallback only with a recorded Opus-unavailability fact — the oracle wave b2/b3 reviews ran on Sonnet 5.5 WITHOUT such a record; flag it); never print secrets; HOME=$(mktemp -d) and `${VAR:?}` in scratch scripts; push parent via `scratchpad/push_main2.sh` pattern (8 remotes, background + verify with `git ls-remote`).
