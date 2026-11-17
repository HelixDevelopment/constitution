# CON-423 r5: evidence table

All runs were made on 2026-11-16 in a scratch clone on one host, Python 3.14.4, Unicode 16.0.0, pandoc 3.11, on
commit 8a546620 (the evidence commit adds only this directory). Evidence class: gate-logic, PROVISIONAL
(section 11.4.289(C)(2)). Every number below was read from the file named in its row. Logs name scratch paths
(`/mnt/DATA1TB/claude-work/...`); these are not credentials. Words such as `password` in the redact and tag logs are
test-case names over FAKE values, as in the committed r4 logs.

| Claim | Result | File |
|---|---|---|
| P0: fixture and oracle self-checks | fixture 12 checks, 0 wrong; oracle golden line accepted, 13 golden-bad lines refused. A mutated oracle that accepts everything reports `wrong=13`; a fixture without `tests/dir.sh` reports `wrong=1` (both run once by hand, not part of the suite) | `evidence/run1/suite_provisional_verification_lines.log` |
| Case grid | 220 cases, 159 refused, 61 accepted, 0 mismatches between API, command line and oracle | `evidence/harness/grid.txt` |
| Closed-world property test (seed 290423) | 3000 sentences, 18000 perturbations, checker and oracle agree on all 18000 (682 accepted) | `evidence/harness/property.txt` |
| Line model (L1, L4) | 47 cases, 0 mismatches, pandoc 3.11 cross-check 0 mismatches | `evidence/harness/linemodel.txt` |
| Inventory of the complement (P4) | 12 classes, 7803310 members, 0 mismatches, the whole code space (1114112 code points); no member floor, so the count does not depend on the Unicode version. One G01 member is accepted by the grammar and needled: `job: bash tests/t.sh -k case12; python3 -I tests/p.py .` | `evidence/harness/inventory.txt` |
| Work bound | 129 cases, worst 0.078 s, limit 1.00 s | `evidence/harness/timing.txt` |
| Reviewer probes r3, r3b, r4 run verbatim | 322 cases: 289 kept, 33 narrowed (each listed with its reason in `tests/release/pvl_reviewer/changes.tsv`), 0 unexplained, 0 reversed; separator classes 700 cases, 0 accepted; DoS worst 0.000 s | `evidence/harness/reviewer_probes.txt` |
| Reviewer mutants (56: R1-R22, X1-X12, N01-N22) | 12 apply (5 on this suite's files, 7 on release tooling, named by those suites), 44 NOT-APPLICABLE with covering cases. The r4 survivors N02 N04 N06 N07 N08 N10 N14 N17 N18 and the questioned N03 N22 are among the 44: their mutated code no longer exists. They are NOT claimed killed; the classes they named are covered by the cases in `mutants_map.tsv` | `evidence/harness/reviewer_mutants.txt` |
| Paired mutants (30 own O01-O30 + R15 R19 R21 N15 N16) | unmutated control passes every kill harness; 35 of 35 killed, 0 survived, 0 not applied | `evidence/harness/mutate.txt` |
| Release-tooling mutants R17, R18 (run as RT17, RT18 with `--only`) | both killed by their property, control passes. The full mutation suite (296 mutants) did NOT finish inside a 1700 s bound: 9 controls and 4 mutants passed before the timeout (rc 124); it is not claimed run. X8 to X12 are only shown to be NAMED by their suites (P12); they were not run separately in this round | `evidence/harness/release_tooling_mutation_RT17.txt`, `..._RT18.txt`, `evidence/harness/release_tooling_mutations_full_timeout.txt` |
| Real tracker database, `--root .` | 407 items, 29 in a provisional status, 0 accepted, 29 refused, exit 1. The brief expected 30; 29 were measured. The refusal is honest: the lines are prose, outside the grammar. The items are not rewritten or demoted (operator decision); `tracker/mint_at_landing.json` CON-PENDING-noscheduler lists them | `evidence/real_db_verdicts.txt`, `evidence/run1/checker_realdb_root.txt` |
| Every suite of the round, run twice (run1, run2) | tag 455/0, redact 445/0, publish 170/0, census 99/0, derive 109/0, render 96/0, checker suite 59/0; pin-diff (removed 0, added 0, findings 0), netgate (146 invocations, 0 findings), ratchet (unimplemented 394 = baseline), index fresh, git-env census (653 members, 0 unscrubbed), engine validate (407 items OK), diff (in sync), export (four derived files EQUAL) | `evidence/run1/rc.txt`, `evidence/run2/rc.txt` |
| `--verify-manifest` | rc 3, exactly one problem: `note changed ['tests/release/pvl_grid.py']`. The lock is NOT accepted (brief) | `evidence/run1/verify_manifest.txt` |
| run1 and run2 are the same | 17 files compared: 16 byte-identical, 1 identical after normalisation (the tag suite's /proc race lines, counted); engine directory differs only in the run path in `export.txt`. Control needle: one seeded PASS to FAIL change is caught (`bad=1`) | `evidence/compare.txt`, `evidence/compare_engine.txt`, `evidence/compare_needle.txt`, `review_bin/compare_runs.py.txt` |
| The checker suite with `PVL_EVIDENCE` | first run: 59 pass, 1 fail (P2 counts: the test's expected count line was wrong, 13/12/11 for a database of 12 rows; corrected to 12/11/1/10 by counting the rows, the checker unchanged); both later runs 59/0 | `evidence/suite_pvl_with_evidence_before_p2_count_fix.log` |

## Honest limits

- A value inside the grammar can still be false (a real script that is not the right job, a count that will not be
  observed); the checker runs no process.
- A selector, option or env value is accepted when the script merely mentions it.
- No device-class target registry exists in this repository, so every board, device, container, vm and runner target
  is refused until one is added.
- The review mutants that target removed code are NOT-APPLICABLE, not killed; their equivalence is not claimed.
- Order of work: the class definition and grammar (`class_inventory.md`) were committed before the code (652023e8);
  the "Changes after the code" section lists what moved after measurement.
