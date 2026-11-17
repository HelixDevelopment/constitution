# CON-423 r4: evidence table

All runs were made on 2026-11-16 in a scratch clone on one host, with Python 3.14 and Unicode 16.0.0. Evidence class:
gate-logic, PROVISIONAL (section 11.4.289(C)(2)). Every number below was read from the file named in its row. The
logs name scratch paths (`/mnt/DATA1TB/claude-work/...`), as the r3 logs do; these are not credentials.

RED means the r3 checker (`logs/red/` and `red/checker_r3.py` in the work directory). That checker's sha256 is
627a3b3cbdee9edec72a8e48d35d364d1ec4a9effd4bb40aac84eb1fc013cc1f, the same as `git show
662edb3e:scripts/validation/check_provisional_verification_lines.py`. GREEN means the r4 checker of this commit.

| Claim | RED (r3 checker) | GREEN (r4 checker) | File |
|---|---|---|---|
| Final grid, 733 cases | 193 mismatches | 0 mismatches | `logs/red/grid_733_on_r3.txt`, `logs/green/grid_733_on_r4.txt` |
| Reviewer probe r3 (168 cases, `probe_r3.py`) | 39 mismatches | 2 mismatches (`git -x`, `board target`; stated limits) | `logs/red/probe_r3.txt`, `logs/reviewer_probe_r3_on_r4.txt` |
| B1: reviewer separator-class probe (700 cases) | 575 accepted | 0 accepted | `logs/red/probe_r3b.txt`, `logs/reviewer_probe_r3b_on_r4.txt` |
| B2: shape-only weak-word paths in the same probe | accepted (`None`) | refused; only `scripts/nonexistent.sh` and `ask/operator` stay accepted without `--root` (stated limit; CON-423's job uses `--root .`) | same files |
| F1: work bound (98 cases, limit 1 s) | worst 13.300 s (SLOW) | worst 0.171 s | `logs/red/timing_r3.txt`, suite line P13 in `logs/run2/suite_provisional_verification_lines.log` |
| B3 and the character classes: inventory, 23 classes, 75231 cases | 49646 mismatches; FOLD-CLOSURE BLIND | 0 mismatches, 0 below floor; FOLD-CLOSURE code_points=1114112 folds_to_invisible=0 | `logs/red/inventory_on_r3.txt`, `logs/green/inventory_r4.txt` |
| The r4 suite run against the r3 checker (`PVL_SCRIPT`) | pass=89 fail=60 | pass=148 fail=0 | `logs/red/pvl_suite_r4_on_r3.log`, `logs/run2/...`, `logs/run3/...` |
| Own mutants O01-O42 (O04 removed with its dead code) | - | 41 of 41 caught (suite P8) | `mutants/suite_mutant_lines_run2.txt` |
| Reviewer mutants R1-R22 and X1-X7 in the suite | - | 27 of 27 caught (R1-R16, R19-R22, X1-X7; R1-R8, R11, X4-X6 are ports) | `mutants/suite_mutant_lines_run2.txt` |
| Reviewer R17 and R18 (render) | - | both KILLED | `mutants/reviewer_R17_R18_render.txt` |
| The reviewer's `mutants_r3.py`, run verbatim on r4 | - | 13 KILLED (R9, R10, R12-R22); 9 STALE (their target code was rewritten; ported versions above) | `mutants/reviewer_mutants_r3_on_r4.txt` |
| Separate prober (59 mutants, grid only) | - | 59 of 59 KILLED | `mutants/prober_mut4_grid.txt`, `review_bin/mut4.py.txt`, `review_bin/mut4.tsv.txt` |
| Generator self-checks (P12): renamed class, floor above members | - | both caught | suite lines P12 |
| Quadratic-split mutant (P13) | - | caught (split40k 12.38 s) | suite line P13 |
| Every suite of the round, run twice (run2, run3) | - | tag 455/0, redact 445/0, publish 170/0, census 99/0, checker 148/0, render 96/0, derive 109/0; pin-diff, netgate, ratchet (394 = baseline), index fresh, git-env census (646 members, 0 unscrubbed), real DB 30/30 with and without `--root`, engine validate, diff, export all rc 0 | `logs/run2/rc.txt`, `logs/run3/rc.txt` |
| `--verify-manifest` | - | rc 3, exactly one problem: `note changed ['tests/release/pvl_grid.py']`. The lock is NOT accepted (brief) | `logs/run2/verify_manifest.txt` |
| run2 and run3 are the same | - | 14 files byte-identical; 3 identical after normalisation; engine directory identical; 0 bad. The tag suite has a /proc race (P6 in followups.md): 91 and 72 noise lines are dropped and counted. A control needle (a seeded PASS to FAIL change) is caught | `logs/compare_2_3.txt`, `logs/compare_2_3_engine.txt`, `review_bin/compare_runs.py.txt` |
| A comment-only edit of the suite header after run3 | - | the suite was rerun on the edited file: pass=148 fail=0 | `logs/suite_pvl_after_header_comment_fix.log` |

The tools used in this round (probes, prober, compare) are in `review_bin/`, saved as `.txt`. Their sha256 values are
in `review_bin/SHA256SUMS`.
