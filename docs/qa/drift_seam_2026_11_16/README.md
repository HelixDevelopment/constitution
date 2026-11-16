# Drift seam, tripwire T4 and scanner e2e topology fix (2026-11-16)

Source: pre-release audit of main 09d3ad2f (findings F5, F6, F7, F10). Base of this fix: main
cc51c320 (all five upstreams equal at fetch time). Evidence class: gate-logic / host
(§11.4.289(C)(2)); no live landing or push was made. Status: PROVISIONAL.

## Reproduction (§11.4.292)

| Finding | On cc51c320 | Evidence |
|---|---|---|
| F5 env-allowlist gate stale=2 uncovered=1 | NOT reproducible: `cm_gate_env_reads_allowlisted.sh` PASS 3/3 (uncovered=0 stale=0). Repaired by 1c248515 (PR-0 v3, config/gate_env_allowlist.tsv). | `red/f5_gate_on_cc51c320_{1,2,3}.txt` |
| F6 README badge row stale | NOT reproducible: `compute_badges.sh --check` rc 0, `test_static_badges.sh` pass=64 fail=0. Repaired by 1c248515. | console only (this README) |
| F5/F6 class cause | Reproduced: `land_vehicle.sh` neither names nor runs the two checks; drift cases D1-D8 against the unchanged lander: 13 of 16 checks FAIL. | `red/lv_drift_orig.txt` |
| F7 tripwire T4 | Reproduced 3/3 on TMPDIR=/mnt/DATA1TB (695 GiB free): `RESULT T4 FAIL ... rc=0 state=-` (identical sha256). | `red/f7_{1,2,3}.txt` |
| F10 scanner e2e opt-in leg | Reproduced 3/3: `FAIL e2e canon: opt-in includes third_party:true submodules`, superspec/open_design not checked out. | `red/f10_{1,2,3}.txt` |

Root causes, by toggle:
- F7: the threshold is fixed at 400 GiB; free space on the df target decides the verdict. The fixed
  test derives the threshold from the measured free space; on the same host it trips 3/3
  (`green/t4_final_*.txt`, df at run time in `green/df_at_run.txt`).
- F10: the e2e legs need a populated third_party:true submodule. With superspec empty the three legs
  are SKIP (`green/f10_unpop_1.txt`); with one fake unannotated test file placed in the empty
  `submodules/superspec` of a scratch copy (gate-logic toggle, never committed) all three legs run and
  pass (`toggle/f10_pop_toggle.txt`).
- F5/F6 class: nothing at the landing seam ran the two checks. With step 6b D1-D8 pass 16/16
  (`green/lv_drift_1.txt`).

## Changes

- `scripts/release/land_vehicle.sh`: prepare prints both checks; publish step 6b runs them before any
  remote is touched (required when the script is in main_before or local main; missing script,
  non-zero exit, timeout 900 s, dirtied clone or moved main refuse, exit 1, nothing pushed;
  `drift_checks.tsv`).
- `tests/release/test_land_vehicle.sh`: drift cases D1-D8 (`LANDER_TEST_DRIFT_ONLY=1`).
- `scripts/codegraph/tests/test_tripwire.sh` T4: threshold from measured free space on the first df
  target with 5..498 GiB free; needles: logged avail_bytes within 2 GiB of an independent df, logged
  min_bytes equal to the derived threshold; honest SKIP when no target fits.
- `scripts/gates/scanner_gate_false_positive_repairs_test.sh`: e2e canon legs SKIP
  (topology_unsupported) without a populated superspec/open_design.

## Mutants

`mutants/round1.tsv` (lander LV1-LV10, scanner SC1, tripwire TW1-TW3 against the first T4 version),
`mutants/round2.tsv` (TW1-TW4 against the final T4). Every lander and scanner mutant is killed. In
round 1, TW1 (fixed 400) and TW3 (threshold below free space) survived because the first T4 version
clamped a tiny df target (4 GiB free) to the lower bound 5; the final T4 refuses clamped targets and
checks the logged min_bytes, and round 2 kills TW1-TW4. The runner is stored as
`mutants/run_mut.py.txt` (evidence text, not executed from the tree; run a copy with
`python3 -I run_mut.py <repo root> <out dir>`).

Known survivors by design (not run): a mutant that makes the T4 candidate search never match, and a
mutant that forces the scanner precondition to "not populated", both turn the case into a SKIP and
the suite still exits 0. A SKIP is not a failure (§11.4.3); see `followups.md`.

## Reruns (twice, hash compared)

- `test_tripwire.sh` full: SUMMARY cases=6 failed=0, both runs equal on RESULT/SUMMARY lines.
- `scanner_gate_false_positive_repairs_test.sh`: RESULT 88 ok, 0 failed, 2 skipped, both runs equal
  on ok/FAIL/SKIP/RESULT lines (the timing line of the performance case excluded).
- `test_land_vehicle.sh` full: RESULT pass=346 fail=0, both runs equal on PASS/FAIL/SKIP/RESULT lines
  (sha256 224a13a4...ba5ac).
- Also on the final tree: `--verify-manifest` MANIFEST-OK; git-env census PASS (unscrubbed=0);
  ledger ratchet PASS (unimplemented=394 baseline=394); env-allowlist gate PASS (uncovered=0 stale=0);
  `compute_badges.sh --check` rc 0; engine validate OK (399 items) and diff in sync; index-fresh gate PASS.

## Limits

- The pull-request landing path does not pass through `land_vehicle.sh`; the step-6b checks do not
  run there (followup CON-PENDING-pr-path-drift-seam).
- The drift checks run code from the vehicle being landed (the same trust as the derived-file steps
  the lander already prints).
- T4 picks a df target outside the test work dir when that dir has more than 498 GiB free; the
  tripwire only reads df there.
