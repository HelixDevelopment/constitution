# Git environment class, round 4 (2026-11-15)

| Field | Value |
|---|---|
| Item | CON-402 round 4 |
| Status | PROVISIONAL (§11.4.290), evidence class: gate logic plus host behaviour runs |
| Base | bd0036bd (round-3 head 104bc231 was the reviewed artifact) |
| Review answered | rev4 review of r3, verdict NO-GO, findings R4-1 to R4-7 |

## What changed

- R4-1: the census universe is now every tracked file of the tree
  (`git ls-files -z -s`), with closed-world accounting: every tracked entry
  lands in one bucket (gitlink, symlink, absent, binary, data, code,
  unclassified) and the census goes BLIND unless `accounted == tracked` and
  `unclassified == 0`. Test C1d is an independent write instrument (its own
  regex, its own file walk) that fails on any tracked writer that is not a
  census member.
- R4-2: a file that sources a library is HERMETIC only when its own scrub runs
  first; readers of sourced libraries were made hermetic (14 readers).
- R4-3: the preamble that may precede the scrub is anchored: only bare `set`
  option words, `shopt`, `umask`, comments and blank lines. `set -e; git ...`
  and `set -e && git ...` are rejected.
- R4-4: `entry-function-scrub` is checked: the top level mentions no git, the
  entry function is called, the clear runs before any git line inside it.
- R4-5: a list clear counts only when its loop expands to the canonical list
  and is not inside a heredoc or another function.
- R4-6: README and docstring wording for Go: a Go file is a member only when
  the write detector sees a write.
- R4-7 (decision): the three guards `guard-branch-consistency.sh`,
  `guard-track-branch-label.sh`, `guard-work-track-binding.sh` FOLLOW THE
  CALLER. They are hooks that must describe the repository the caller is
  operating on, so a caller's `GIT_DIR` is honoured. They are EXEMPT with the
  new reason `subject-follows-caller`, which FAILs on any detected git write
  (echo/printf-only lines are ignored). The one write path found
  (`git status` refreshing a stale index) now runs as
  `git --no-optional-locks status`; test B4_guard_status proves the plain form
  changes a sentinel repository and the guard does not.
- `GIT_CEILING_DIRECTORIES` stays outside the scrub list (it limits discovery,
  it never redirects it).

## Numbers (fixed tree, this session)

- Census (final head 84c32118): tracked=4672, accounted=4672, universe=1694,
  members=551, hermetic=470, exempt=81, unscrubbed=0, 94 control needles
  (green/census_final.*).
- `tests/test_git_env_class.sh --fast` on a clean worktree of the final head:
  134 passed, 0 failed, 2 skipped, three runs, identical output hash
  e058d4172a92d3998d3abd9233da7c2fca7d675c2d04e193c20a065941bf316f
  (green/final_run1..3.txt; the three earlier runs on 9c73f8da also matched,
  green/test_fast_run1..3.txt). Skips: B1 anchor (continuum submodule absent),
  B1 agent_label (`--fast`).
- RED: the round-4 test on the round-3 head: 98 passed, 32 failed (red/).
- Mutants (mutants/): reviewer RV4, RV4b, RV5, RV6, RV7, RV8, RV8b, RV10, RV11,
  RV12, RV13 KILLED; RV1, RV2, RV3 SURVIVE (documented no-letters boundary);
  RV9's anchor no longer exists, its equivalent RV9EQ (universe cut to
  scripts/ and tests/) KILLED. Own mutants M01 to M21 all KILLED (M17 and M21
  by the behaviour cases B4_guard_status and B4_guard_label in a full run).
  M12 first SURVIVED: the heredoc needle was caught earlier by `names_all`;
  a new needle (a wrapper whose only clear sits in a heredoc, with a
  sourced-library row) now kills it (mutants/m4_m12_final.tsv). NONE (control)
  SURVIVES in both modes.
- Behaviour sweep (sweep/): 333 hermetic members run from the repo root under
  a sentinel `GIT_DIR` + `GIT_INDEX_FILE` and a shim git, fresh HOME each:
  333 UNCHANGED, shim hits 0. 137 hermetic members were not run (host safety,
  sweep/excluded_host_safety.tsv). One member left agent-config links in its
  cwd (sweep/untracked_side_effects.txt, removed afterwards; no git state).
- Regression (regress/): 22 neighbouring suites, round-3 head versus final
  head, identical exit codes and summary lines (one SKIP exit 77 in both:
  consumer layout absent).

## Honest boundary (§11.4.6)

- Universe: tracked files of this repository only. Submodule contents,
  untracked files, binaries and data/template files are not members.
- An extensionless, non-executable file with no shebang is data (fixture
  C2r4b2 documents it).
- Git run without the letters `git` (a name built at run time, base64, read
  from a file) is not detected by any text census.
- ECHO_ONLY treats `echo`/`printf` lines without a pipe, substitution, eval,
  `;`, `&&` or a shell word as non-writing; a write hidden behind a variable
  expansion on such a line is not seen.
- Labeler limit: `scripts/multitrack/track_branch_label.sh` is itself scrubbed,
  so under a caller `GIT_DIR` the label it prints can describe the cwd while the
  guard fallback describes `GIT_DIR`. Tracked as a follow-up.
- `progressive/EVIDENCE/PREFLIGHT_MANIFEST.json` pins hashes of files this
  change touches. It was already stale before this change (see CHANGELOG) and
  no script reads it; it was not regenerated.
- Merge of origin/main (763726e0) was not cheap: 6 conflicting files and 47
  main-only code members that the round-4 census reports UNSCRUBBED
  (merge_preview/). Left as a follow-up, not done here.
- Behaviour sweep excludes members that could signal, push, call a network,
  drive a device or a container (host safety, §12, §11.4.174); the excluded list
  is in sweep/.

## Merge of origin/main

Follow-up F1 is resolved in `merge_main/README.md`: origin/main was merged
twice (464cd498, then 584c287e) with merges only, every main-only code member
is under the census, and two merge regressions were found and fixed.

## Landing on main

The landing on main `e90d4aea` (after CON-401) is recorded in `landing/README.md`: the ten CON-401 code
files were brought under the census (three scrub lines, five rows), with a sentinel RED on main and GREEN
on the landed tree.
