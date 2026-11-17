# Release tooling: GitLab pre-release marking (glpre) and retest statement key (reltpl), 2026-11-15

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Items | CON-416, CON-417 |
| Base | `main` at bcac0882 |
| Evidence class | gate-logic / unit class (§11.4.289(C)): stub glab, stub forges, host fixtures. PROVISIONAL (§11.4.290). Nothing here is live evidence of a GitLab release or of a release cut. |

## What

Two small vehicles, re-applied by hand onto the landed fix227 release tooling. Their bundles were based on 02c10935, which `main` had moved past.

1. **glpre** (vehicle `gitlab_prerelease.bundle`, head ed50c71e, review round 1 GO-with-follow-ups), in `scripts/release/tag_and_release.sh`:
   - On a `--prerelease` run, the GitLab leg prefixes the release name with `PROVISIONAL pre-release: `, never twice.
   - The description starts with one fixed PROVISIONAL line.
   - Every create passes `--no-update`.
   - An optional `--gitlab-released-at ISO8601` becomes `--released-at`.
   - The release is read back with `glab api --hostname H`, through `nt` (the timeout wrapper).
   - Unmarked or unparsable read-back is a FAIL; a read-back that fails or shows a different upcoming state is a GAP.
   - Server text is never printed raw.
   - The census rows and the netgate pin are updated; the pin was regenerated only after reading `runs/glpre_pin_diff.txt`.
2. **reltpl** (vehicle `release_template_amend.bundle`, head bb45b401):
   - New manual key `retest_statement` in `docs/release/helixconstitution-v73.4_entry.template.md`. It replaces the fixed sentence "has never run on this candidate".
   - `scripts/release/render_release_entry.py` refuses with exit 3 any value that does not start with `PASS-FULL`, `PARTIAL-TOPOLOGY`, `FAIL` or `NOT RUN`.
   - The template no longer says that (L1), (L6) or (L7) "ride open", nor that the decision "relaxes … (L7)". It now says that an open (L7) entry blocks a release of every class, that the release does not conform to (F.3)(2) for those entries, and that the operator decision is "an override of the rule, not a conforming waiver of (L7)".
   - `docs/release/README.md` revision 4 lists the key.

## Why

- **glpre:** GitLab has no pre-release flag, so a `--prerelease` cut published to GitLab looked like a final release.
- **reltpl:** the template asserted the retest had never run, whatever the facts were. It also called a decision that overrides (F.3)(2) a waiver of (L7), which §11.4.230(E.3) says cannot be waived.

## Limits (stated, not hidden)

- **Native `--prerelease` on GitLab is not possible.** glab 1.129.0 `release create --help` offers only `--no-update` and `-D/--released-at` (`runs/glab_release_create_help_flags.txt`). The release is marked by its title, its description and, with a date, the Upcoming Release badge.
- **No live GitLab run was made** (no release, no push, no glab against a real forge). The behaviour of GitLab's `released_at` and `upcoming_release` is UNCONFIRMED.
- **The create call is not pinned to a host** (only the read-back uses `--hostname`). A create and a read-back on different hosts give a GAP, never a false MARKED.
- **The renderer checks the verdict token only**, not the base, tier or log that should follow it.
- **The corrected waiver draft** (`waiver_v734.draft.corrected_copy.md`, diff in `runs/waiver_copy.diff`) is a copy in this evidence pack only. No waiver is recorded.
- **Not run:** the full mutation suite (about 8 h), the full default and heavy suite (`scripts/run_full_suite.sh` without `--verify-manifest`), and any live release.

## Results (all on this branch, scratch clone)

| Run | Result |
|---|---|
| glpre RED: `test_tag_and_release.sh` with the new cases on the unchanged script | pass=352 fail=35 (`runs/glpre_red.log`). Some GL6 usage cases pass before the change; they are regression guards. |
| Baseline: `test_tag_and_release.sh` on `main` | pass=313 fail=0 (`runs/tar_main_baseline.log`) |
| glpre GREEN | tag_and_release pass=388 fail=0; channel_census pass=99 fail=0 |
| reltpl RED / GREEN | pass=25 fail=12, then pass=37 fail=0. With the real facts of bcac0882 against tag v73.3: pass=38 fail=0 (`runs/reltpl_*`). |
| Every `tests/release` suite on the final tree (`suites/`) | tag_and_release 388/0, channel_census 99/0, redact_cut 435/0, land_vehicle 331/0, derive_release_facts 109/0, publish_gitea 167/0, render_release_entry 37/0. The redact_cut log is kept as a summary only, because its fixtures contain fake token-shaped strings. |
| New mutants GP1–GP21 (`mp`, each must be killed by its own GL case) | 21/21 killed by their property (`mutants/new/`) |
| New mutants RV1–RV4 (renderer verdict check) | 4/4 killed by their property |
| Sample of 44 existing mutants, stratified by source with seed 20261115 (`mutants/sample/sample.list`) | 44/44 killed. The V4 log is kept as a summary only. |
| `STALE_ONLY=1` over all 408 mutant lines | stale=0 |
| Harness control (`--only control`, 8 sources) | 8/8 pass (`runs/mut_control.log`) |
| `scripts/run_full_suite.sh --verify-manifest` | MANIFEST-OK; no test file was added |
| `cm_gate_ledger_ratchet`, `cm_constitution_index_fresh` | PASS, PASS |
| `scripts/fastcycle/tests/run_all.sh` (taken as the "fast tier"; that reading is UNCONFIRMED) | 177 run, 101 failed (`runs/fastcycle_run_all.summary.txt`). This branch changes nothing under `scripts/fastcycle`. Four of the failing tests, run on a base worktree at bcac0882, fail there too (`runs/fastcycle_base_probe.txt`). The first failure, a control needle that needs `specs/004-fast-dev-cycles/contracts/`, points to the suite expecting a consumer checkout. The full log (900 KB) is kept outside the repository. |

The mutant runner is `mutants/runmut.sh.txt`: two at a time, waiting while the 1-minute load is at 60 or above, under `systemd-run --user --scope -p TasksMax=2000` and `nice -n 10`.
