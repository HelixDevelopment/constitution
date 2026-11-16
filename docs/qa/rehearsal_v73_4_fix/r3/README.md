# CON-423 r3: structural fix of review r2 B2 (evidence)

| Field | Value |
|---|---|
| Item | CON-423 (placeholder id; Jev r12 mints the same ids, the lander re-mints) |
| Answers | REVIEW_CON-423_r2.md sha256 37fc72c50daa423818817a73c5caf473843ccb47772c49066b369d6a6cdd4950 (NO-GO, B2) |
| Base | fix_rehearsal_v73_4_r2.bundle head 7b8e99de (origin main bbdf4ac1 is its ancestor, no merge needed) |
| Evidence class | gate-logic, PROVISIONAL (section 11.4.289(C)(2), section 11.4.290). No live claim. |
| Model / effort | Opus 5.5 / effort UNKNOWN |

## What changed

- `scripts/validation/check_provisional_verification_lines.py`: the deny-list scheme is replaced (section 11.4.276(E)(3)).
  Positive shapes for `job` (a path, existing under `--root` when given; a command with an option or path; a job id
  `<KEY>-<digits>`) and `target` (a target word); a leading-word rule per field; tokens split on punctuation,
  underscores and letter/digit boundaries, runs of single letters joined, 0/1 read as o/i; fold NFKD, marks removed,
  NFKC, Cf removed, Cyrillic/Greek look-alike map (shapes read ASCII without the map). HTML comment blocks skipped
  (N1); the prefix needs a boundary (N3). New `--root DIR` option and a `PATHS:` output line.
- `scripts/release/render_release_entry.py`: the same look-alike map and fold; docstring says "ASCII letter" (N2).
- `tests/release/pvl_grid.py`: the 74 reviewer probe cases (3 recorded expectation changes), the fixer's per-axis
  cases; grid now 433 cases. `tests/release/test_provisional_verification_lines.sh`: P8 one paired mutant per rule,
  P10 `--root`, P11 reviewer mutants X1/X2/X3/X7 verbatim, X4/X5/X6 ported. `tests/release/test_render_release_entry.sh`:
  MY_TODO, 2DRAFT, Cyrillic/Greek/combining-mark cases, a map-equality check, X8/X9 verbatim and R1-R4.
- Tracker: CON-159 to CON-162 job text now names the guard path (engine edit; tracker/). Issues.md and
  Issues_Summary.md re-exported.
- `config/full_suite_manifest.tsv`: the pvl_grid.py note describes the new content. The excluded lock is NOT
  accepted (brief): `--verify-manifest` gives MANIFEST-MISMATCH with exactly one problem, `note changed
  ['tests/release/pvl_grid.py']` (logs/verify_manifest_r3.txt). The lock hashes the note, not the file bytes.
- `config/git_env_class_exemptions.tsv`: one `no-git-execution` row for the checker (its COMMANDS list holds the word
  git; it runs no process). Run 1 failed the census without it (logs/run1_pre_census_fix/).

## Evidence

- class_inventory.md: the class and every member axis, written before the code change.
- RED: logs/pvl_grid_red_r3.txt (86 mismatches on the r2 checker), logs/pvl_red_r3.log (new suite on the r2
  checker: pass=59 fail=55), logs/render_red_r3.log (pass=86 fail=10). GREEN: logs/render_green_r3.log (96/0).
- Reviewer tools on r3: logs/reviewer_probe_pvl2_on_r3.txt (74 cases, 1 mismatch = the recorded change
  job_DRAFTS, now refused for its shape), logs/reviewer_mutants_on_r3.txt (9 KILLED, X4-X6 STALE, ported in P11).
  Tool copies: tools/reviewer_*.txt.
- mutants/mutants_r3.md: reviewer and own mutant table (48 checker + 4 render own mutants).
- logs/run2 and logs/run3: every suite twice (tools/run_all_r3.sh.txt). All rc 0 except verify_manifest rc 3 (the
  pending lock acceptance). logs/run2_vs_run3_cmp.txt: 22 files byte-identical; 3 differ only in run directory
  paths (engine/export.txt), wall-clock seconds (channel_census L5, tag_and_release C35) and the count of stderr
  noise lines `/proc/<pid>/cmdline: No such file` of tag_and_release C49 (pre-existing: r2 logs had 69). Suite
  totals equal: tag 455/0, redact 445/0, publish 170/0, census 99/0, checker 114/0, render 96/0, derive 109/0;
  pin-diff 0/0/0, netgate 0 findings, ratchet unimplemented=394 baseline=394, index fresh PASS, git-env census PASS,
  engine validate OK 392, diff in sync, export EQUAL x4, checker on the real DB 30/30 (shape-only and --root .).
- erratum_n4.md (N4), followups.md (I1, F1 operator question, id collision).
