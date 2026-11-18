# CON-402 fallout round 5: landing merge with main e5db4a1c (PROVISIONAL)

Lander resolution of the merge of main e5db4a1c into the round-5 bundle head
23bedfa2 (bundle sha256 c5f3f175...). Gate-logic, host-only evidence.

## scripts/validation/git_env_class_census.py

Two conflict hunks, resolved as a union of both rounds:

- needles(): main's R11-C `.rc` / `.ls` shape checks are kept and the round-5
  direct checks (8) are kept; the count is `len(cases) + 15 + len(shapes)`.
- main(): main's `shaped_data(...)` data rule decides `lang`, then the round-5
  rule sets aside only a non-code file or a native executable with a NUL byte as
  binary (round-5 R4-3). Main's earlier unconditional NUL skip was already
  removed by the round-5 change and the auto-merge kept that removal.

## Tracker

The vehicle DB went through a Markdown re-parse (501 rows differ from the base
e3c5a558: descriptions cut to the title, 17 parent ids dropped; the CON-456
data-loss class). That re-parse is NOT replayed. The scratch vehicle DB was
rebuilt as the base plus only the three intended paragraph edits (CON-251,
CON-450, CON-451 descriptions), with body_md set to the engine's own render, and
replayed through the engine onto main's DB:
plan own=0 base_changes=3 steps=3; verify PASS; validate OK 549; diff in sync.
Main's parent link CON-251 -> CON-033 is kept.

Files: remint_plan.txt, remint_replay.txt, remint_verify.txt.

The full-suite guide census is main's, re-synced with --sync-guide.
