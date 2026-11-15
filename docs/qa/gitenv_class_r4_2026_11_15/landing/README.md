# Git environment class: landing on main e90d4aea (2026-11-15)

| Field | Value |
|---|---|
| Item | CON-402 (minted at the landing on main) |
| Status | PROVISIONAL (§11.4.290); evidence class: gate logic plus host-fixture runs (§11.4.289), no live-target proof |
| Base | main `e90d4aea` (CON-401, security scripts), landed after the vehicle's base `bcac0882` |
| Reviewed head | `fd799642` (review r4, GO-with-follow-ups) |
| Producer | Claude Opus 5.5 (lander subagent); effort not settable on this dispatch path, not claimed |

Scratch paths in these files are shown as `<scratch>` and temp dirs as `<tmp>`.

## Why this pack exists

CON-401 landed on main after the vehicle's base, so its ten code files were not under the closed-world
census. On the merged tree the census reported `FAIL - members=629 hermetic=487 exempt=132
unscrubbed=10`. The landing brings them under the census the same way the vehicle's own merges of main
did (commit `40b27e65`):

- the canonical scrub line, placed right after the `set` line in the preamble, in the three files that
  run git: `scripts/security/history_secret_scan.sh`, `tests/security/test_history_secret_scan.sh`,
  `tests/security/test_security_scripts_mutations.sh`;
- five rows in `config/git_env_class_exemptions.tsv`: `tests/security/fixtures/` (fixture-tree) and
  `no-git-execution` for `forge_branch_protect.sh`, `github_actions_inventory_disable.sh` and their two
  tests (git appears only as forge names; they call forge APIs and gh, never git).

After the change: `PASS - members=629 hermetic=490 exempt=139 unscrubbed=0`, unclassified=0.

## RED on main, GREEN on the landed tree

`docs/qa/gitenv_class_2026_11_14/tools/sentinel_run.sh.txt` builds a fresh sentinel repository and runs
the script with the ambient variable aimed at it.

| Run | Tree | Mode | Exit | Sentinel |
|---|---|---|---|---|
| `red_hss` | main `e90d4aea` | GIT_DIR | 1 | CHANGED (sentinel HEAD moved, index has 3 entries) |
| `green_hss_git_dir` | landed tree | GIT_DIR | 0 | UNCHANGED |
| `green_hss_both` | landed tree | GIT_DIR + GIT_INDEX_FILE | 0 | UNCHANGED |
| `green_hss_none` | landed tree | none (control) | 0 | UNCHANGED |

The GREEN records show `repo_head=e90d4aea` because they ran on the uncommitted landing tree on top of
main; the tree is the one committed as the landing commit.

So `tests/security/test_history_secret_scan.sh` on main wrote into a foreign repository under an
ambient `GIT_DIR`, the defect class CON-402 closes. Security suites on the landed tree: history 45/45,
forge 168/168, actions 44/44; the mutation suite result is in the landing commit message.

## Squash proof

The vehicle touched 1488 paths (`git diff --name-only bcac0882 fd799642`). Against the reviewed head
`fd799642`, `LC_ALL=C git diff --stat fd799642 <landing> -- <path>` is empty for 1471 of them. The other 17
were named before the check: the 11 files carrying the placeholder, the four packs' SHA256SUMS, and the two
shared files (`config/full_suite_manifest.tsv`, union with main's rows; `docs/guides/full_suite_runner_guide.md`,
3-way merged, only the generated census line differs). For the 11 placeholder files, reversing the
substitution (CON-402 back to the placeholder, the "minted" notes back to the placeholder notes), dropping the
five new exemption rows and the "Landing on main" section gives byte-identical files. Positive controls: the
same diff of the 1471 paths against the base `bcac0882` shows 1471 files changed; a throwaway commit with one
byte appended to one of them shows 1 file changed.
