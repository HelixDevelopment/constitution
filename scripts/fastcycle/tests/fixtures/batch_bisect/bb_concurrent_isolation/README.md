# bb_concurrent_isolation

Proves task T056's "two concurrent workers never receive each other's
verdicts" clause. Two separate batches are run CONCURRENTLY (real
background shell processes, real distinct scratch dirs / result stores,
not merely sequential calls dressed up as "concurrent"):

- worker1_batch.json: {chg-A (good), chg-C (bad)} -> expects culprit chg-C
- worker2_batch.json: {chg-B (good)} only -> expects culprit NONE, PASS

The RED test's Section D genuinely launches both as background `sh`
subshells writing to DISTINCT temp result files, waits for both, then
asserts: worker1's result file names chg-C and nothing else; worker2's
result file is a clean PASS with zero culprits; and — the load-bearing
isolation check — worker2's result file NEVER contains the string
"chg-C" and worker1's result file NEVER contains "chg-B" (each worker's
changes never leak into the other's report).
