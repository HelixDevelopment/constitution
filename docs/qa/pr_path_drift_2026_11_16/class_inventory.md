# Landing-path class inventory (CON-443, §11.4.276(C)) — 2026-11-16

Class: every path that moves `main` on an upstream of THIS repository. Required step set: the
derived-file drift checks of `scripts/release/lib/landing_drift_checks.sh` (README badge row
`compute_badges.sh --check`, env-read allowlist `cm_gate_env_reads_allowlisted.sh`) on the landing
candidate before main moves.

Instrument: `git grep -nE 'git[^|;]* push|send-pack|:refs/heads/main|gh pr merge|merge --ff-only|update-ref refs/heads/main'`
over `scripts/` (tests, fixtures and `*_test.sh` excluded), every hit read by hand
(`census.txt`). Positive control: `scripts/release/land_vehicle.sh` and
`scripts/release/tag_and_release.sh` are found (both known to push main). Negative control: a
fabricated token `zzq-nonexistent-landing-token` returns 0 files. Paths that exist only outside
the repository (forge buttons, a hand-typed `git push`) are added from the procedure text
(§11.4.297, §11.4.113), because no grep can see them.

| # | Path | Moves upstream main? | Drift step set | Status after this change |
|---|---|---|---|---|
| 1 | `land_vehicle.sh publish`, integration fast-forward (step 5, `--item-id` path) | yes | both checks, shared runner | COVERED (D14, D14b; the prepare log is asserted to name the fast-forward. Before D14 this row was NOT covered: every other D fixture lands through the merge path) |
| 2 | `land_vehicle.sh publish`, integration merge commit (step 5, `--mint-cmd` path) | yes | both checks, same code path as 1 (`do_publish` has one call) | COVERED (D1-D13; every one of those fixtures lands through the mint path, so through a merge commit) |
| 3 | §11.4.297 pull-request merge on the forge (merge commit or fast-forward) | yes | before: none; now `pr_landing_check.sh` (shared runner) run by the merging agent | COVERED BY PROCEDURE, NOT ENFORCED: nothing in this repository can stop a forge merge made without running it (no CI, §11.4.156); P1-P15, L1 |
| 4 | `tag_and_release.sh` (pushes `SHA:refs/heads/main` with the tag when a remote main is an ancestor of SHA) | yes, when SHA is ahead | badge check only (`compute_badges.sh --check`, skippable with `--no-badge-check`); env-read allowlist NOT run | GAP, scoped out of CON-443 (another script, its own suite); follow-up `CON-PENDING-tag-release-drift-set` |
| 5 | a hand-typed `git push <remote> main` by a lander | yes | none (no tool) | GAP by construction; the procedure is land_vehicle.sh or a PR; recorded, no mechanism added |
| 6 | `scripts/fastcycle/consumers/migrate.sh` push | consumer repositories, not this one | n/a | OUT OF CLASS |
| 7 | `scripts/multitrack/multitrack_constitution_sync.sh` `merge --ff-only` | local consumer checkout, no push | n/a | OUT OF CLASS |
| 8 | `scripts/gates/cm_anchor_record_complete.sh` push | a scratch bare repository inside a gate fixture | n/a | OUT OF CLASS |

Every other hit is a comment, a deny pattern (`install_constitution.sh`, `guard-forbidden-commands.sh`),
a printed plan (`release_tag.sh`, `forge_branch_protect.sh`) or a test (listed in `census.txt`).
Same step set: rows 1, 2 and 3 call the same function `ldc_run` with the same `DRIFT_CHECKS` list
(one definition); row 4 runs a subset; row 5 runs nothing.
