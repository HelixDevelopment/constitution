# CON-030 vehicle report
Vehicle: /home/milosvasic/.cache/claude-tmp/con030v.xJXMAR/c  branch vehicle/con030  HEAD da9d4253c40a75ea1c4d2d2b8176933221616150 (parent main ef18fea)
Bundle: /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/../con030.bundle (ef18fea..vehicle/con030, 1 commit). Not pushed.
Files: scripts/full_suite/run_full_suite.py, tests/test_run_full_suite.sh, tests/test_run_full_suite_mutations.sh (3 files, +91/-10).
Evidence logs: con030_red_section.log, con030_green_section.log, con030_mut_final.log, con030_mut_first_run.log (this dir).
RED (unfixed engine, section harness): passed=1 failed=5; spaced -> ['sub'] + bogus gap, e2e rc 9.
GREEN (fixed): 246/246 full test_run_full_suite.sh (earlier test version, baseline main 239/239); final test file (247) passes as the unmutated baseline of the mutation harness.
Mutants M30a-M30d: killed 4/4 (final run); first run had M30b SURVIVE (fixed by adding the ident_diff round-trip check).
