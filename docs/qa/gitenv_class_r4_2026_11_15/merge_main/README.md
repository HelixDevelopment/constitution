# Git environment class, round 4: merge of origin/main (2026-11-15)

| Field | Value |
|---|---|
| Item | CON-402 round 4 (minted at the landing on main) |
| Status | PROVISIONAL (§11.4.290), evidence class: gate logic plus host behaviour runs |
| Vehicle head before the merge | d098a752 (bundle gitenv_r4.bundle, sha256 738ee076…) |
| Main merged | 464cd498, then 584c287e (installer follow-ups r2), then bcac0882 (tracker data only, 1c100965) |
| Final code head | c85e1908 (this pack is committed on top of it) |

This closes follow-up F1 of the round-4 pack: origin/main is merged into the
vehicle twice, with merges only (no rebase, no force), and every main-only code
member is under the closed-world census.

## Commits

| Commit | What |
|---|---|
| 40b27e65 | merge of 464cd498: six conflicts resolved with both sides kept; 16 main-only members scrubbed; 51 exemption rows; netgate pin regenerated |
| 1dd6800e | census test cases for the merge use their own labels (C2mrg1, C2mrg1b, C2mrg2, C2mrg3) |
| 7f11c449 | merge of 584c287e: one conflict (guide census block, regenerated); tests/install/test_timeout_tty.sh scrubbed |
| 2f5b904b | test_timeout_tty.sh: its timeout-site census no longer follows file names in trailing comments (merge regression, see below) |
| c85e1908 | tag_and_release.sh: scrub moved below `set -u` so that `set +x` / `set -u` stay adjacent (mutant X15 had gone STALE); netgate pin regenerated |

## Conflicts and how both sides were kept

- `docs/guides/full_suite_runner_guide.md`: the census line was regenerated
  with `run_full_suite.sh --sync-guide` (total=926), then `--verify-manifest`
  gave `MANIFEST-OK`.
- `scripts/release/tag_and_release.sh`, `scripts/release/derive_release_facts.sh`,
  `scripts/release_publish_gitea.sh`: main's content kept in full. The vehicle's
  scrub is written as `unset -v GIT_DIR … GIT_INTERNAL_SUPER_PREFIX`, because
  main's network-spawn gate (`tests/release/channel_census.py netgate`) admits
  only that form. The census LEGACY rule accepts `unset -v GIT_DIR`, and the
  byte pin `tests/release/netgate_pin.tsv` was regenerated after the pin diff was
  reviewed (`netgate/pin_diff.txt`: one inserted line per script, and the
  resulting line shifts). On the final head netgate gives `findings=0` and the
  channel lint gives `findings=0` (`netgate/`).
- `scripts/update_constitution.sh`: scrub line placed before
  `HI_SOURCED=0; (return 0 …)`, main's content kept.
- Three tests under `tests/release/`: both sides kept.

## Second regression found by the merge (c85e1908)

A full run of `tests/release/test_release_tooling_mutations.sh` on 2f5b904b
stopped at its 3-hour budget, after 145 of 383 mutants
(`sweep/rtm_full_2f5b904b_timeout10800_names.txt`; the parenthesised FAIL
texts were dropped because they hold fixture credential strings).

- Within that range, one row was not a kill: `FAIL X15 STALE`. X15 replaces
  the adjacent lines `set +x` and `set -u` of tag_and_release.sh as one block,
  and the merge had put the scrub between them.
- The scrub now follows `set -u`, as it already did in the other two release
  scripts.
- The pin diff was exactly the swap of lines 71 and 72 plus the F row
  (`netgate/pin_diff_x15.txt`; removed=3 added=3 analyser_findings=0), and the
  pin was regenerated.
- `STALE_ONLY=1` on c85e1908: all 383 mutants apply, stale=0
  (`sweep/rtm_stale_only_c85e1908.txt`).
- `--only X15`: killed by its property C45 in both sentinel modes
  (`sweep/rtm_only_X15_none.txt`, `sweep/res_c85e1908_x15.tsv`).

## Census accounting (final head)

`census/census_c85e1908.txt`: PASS, `tracked=accounted=6113`, `unclassified=0`,
members=619, hermetic=487, exempt=132, unscrubbed=0. Before the merges the
round-4 head had members=551, hermetic=470, exempt=81.

- 17 main-only members were given the canonical file-level scrub
  (`census/scrubbed_by_merge.txt`).
- 51 rows were added (`census/rows_added_by_merge.tsv`):
  - 49 `pinned-fixture` rows. Each is a closed-round evidence tool that no
    suite or gate runs, and whose sha256 is recorded in its pack's SHA256SUMS
    (and, for some, in `config/full_suite_excluded.lock`). Editing it would
    break that record. Each row states whether a git write is detected.
  - `scripts/release/redact_cut.sh` as `no-git-execution`. It is a sourced
    library that runs no git itself. Its `rc_env_lockdown` drops every `GIT_*`
    name from child environments, its callers scrub first, and its bytes are
    netgate-pinned. It is deliberately not `sourced-library`: under R4-2 that
    reason would require its reader `prescreen13.sh` to be HERMETIC, and an awk
    string there matches as a git call.
  - `tests/release/env_allow.sh` as `no-git-execution`: `GIT_*` names appear
    only as allow-list data.
- `canon` was added to the data extensions. The nine `.canon` files are
  transcripts, and an executable `.canon` with a shebang is still a member
  (case C2mrg1b).

## Regression found by the merge (2f5b904b)

After the second merge, `tests/install/test_timeout_tty.sh` (main-only, from
584c287e) failed with 24 passed and 1 failed. Its static census reported three
extra bare `timeout` sites in `scripts/gates/cm_anchor_record_complete.sh`.

- origin/main alone: 25/0 (`timeout_tty/tty_main_baseline.txt`).
- Chain, measured with a parent-tracking copy of the closure
  (`tools/closure_chain.py.txt`): post_update_hook.sh, then
  cm_full_suite_manifest_complete.sh, then run_full_suite.sh, then
  run_full_suite.py. The git-env scrub note on a code line of
  run_full_suite.py names `scripts/validation/git_env_class_census.py`, so the
  closure followed that file, whose docstring names
  cm_anchor_record_complete.sh. No hop after run_full_suite.py runs anything.
- Stripping the note from the shell files alone does not fix it
  (`timeout_tty/tty_exp_stripped.txt`), because the hop goes through a Python
  file.
- Fix: the closure drops a trailing comment (an unquoted `#` at the start or
  after a blank) before it looks for file names.
- Three new control needles: d.sh, named only in a trailing comment, is not
  followed. lib/f.sh, named before a trailing comment, is followed, and so is
  lib/g.sh, named after a quoted `#`.
- RED: the needles with the old closure make the test BLIND, exit 2
  (`timeout_tty/tty_red_needles.txt`).
- GREEN: 25/0 (`timeout_tty/tty_green1.txt`), and 25/0 again in both sweep
  modes.

## Runs

| Run | Head | Result |
|---|---|---|
| fast tier ×3 (`fast/`) | 7f11c449 | 138 passed, 0 failed, 2 skipped; the three outputs are byte-identical (sha256 f3b07b48…) |
| fast tier ×3 (`fast/`) | 2f5b904b | 138/0/2, byte-identical, the same sha256 f3b07b48… |
| fast tier ×3 (`fast/`) | c85e1908 | 138/0/2, byte-identical, the same sha256 f3b07b48… |
| fast tier ×3 (`fast/`) | 1c100965 (after the tracker-only merge of bcac0882) | 138/0/2, byte-identical, the same sha256 f3b07b48…; census PASS with tracked=accounted=6155 |
| netgate pin + analyser (`netgate/`) | c85e1908 | findings=0 |
| test_tag_and_release, test_channel_census, modes none and both (`sweep/res_c85e1908_release.tsv`) | c85e1908 | rc=0, UNCHANGED, hits=0 |
| reviewer mutants NONE, RV1–RV13 (`mutants/rv_only.tsv`) | 7f11c449 | all KILLED except RV1–RV3 (documented boundary F3); NONE survives as it should |
| own round-4 mutants RV9EQ, M01–M21 (`mutants/m4_*.tsv`) | 7f11c449 | all 22 KILLED (M12, M17 and M21 in a full run) |
| merge mutants MG1–MG9 (`mutants/mg_only.tsv`) | 7f11c449 | all 9 KILLED. MG2's first anchor was wrong (APPLYFAIL); it was fixed and re-run |
| behaviour sweep, sentinel harness, modes none and both (`sweep/`) | 7f11c449 / 2f5b904b | every row UNCHANGED, hits=0; see below |
| `run_full_suite.sh --verify-manifest` (`census/verify_manifest_c85e1908.txt`) | c85e1908 | MANIFEST-OK |

Behaviour sweep, per row:

- Passing in both modes: census_print_sites, make_spawn_sites,
  channel_census_lint, created_at runner `--list`, test_redact_cut,
  test_channel_census, test_derive_release_facts, test_tag_and_release,
  test_publish_gitea, test_land_vehicle, test_sigpipe, test_apply_restore_plan,
  and test_timeout_tty (on the final head).
- apply_restore_plan.sh without arguments exits 2 (usage) in both modes.
- test_release_tooling_mutations: see the second-regression section above.
  The full 383-mutant run did not finish within 3 h (F10).

Excluded from the sweep: the sshd probes (they start a daemon), land_vehicle.sh
itself (it pushes), the release scripts themselves (network and push), and
net_probe.py run directly (it is driven by test_publish_gitea).

The census mutants were run on 7f11c449. The census logic, the census test
and the exemption list are unchanged from there to c85e1908. The changes in
between are tests/install/test_timeout_tty.sh, tag_and_release.sh (one line
moved; it is still HERMETIC) and the netgate pin, and no census mutant targets
any of them. The fast tier on c85e1908 gives the same output hash.
