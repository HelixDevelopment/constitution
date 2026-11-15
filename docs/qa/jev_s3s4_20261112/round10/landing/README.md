# Round 10 landing merge: checks on the merged tree

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-15 |
| Last modified | 2026-11-15 |
| Status | evidence (PROVISIONAL, gate-logic class §11.4.289(C)(2)) |

Merge of `main` 2031bc05 into the vehicle at 4f57924a. Conflicts were resolved by `resolve_merge.py`, and the items were minted by `mint.sh`
(the ids are in `mint_ids.txt`). The hermetic runs use bwrap with `--unshare-net`, so they have no network.

- Suites on the merged tree: round 10 52/0, round 9 70/0, round 8 47/0, placement 266/0 (`merged_*.txt`). Round 10, round 9 and
  round 8 give the same normalised verdict sets as before the merge.
- `tests/jev/run_all.sh` ran 40 tests and 3 failed (`merged_runall.txt`): `test_bootstrap_e2e_stub_server.sh`,
  `test_decision_layer_gaps.sh` and `test_detection_matrix.sh`. Each one needs a loopback stub server. The same three
  fail on `main` 2031bc05 under the same runner (`ctlmain_*.txt`), so the failure comes from the runner's lack of network
  and not from the merge. They were not run outside the sandbox, because that would touch the operator's real host. Their
  result outside the sandbox is UNCONFIRMED.
- Gates: index fresh, gate ledger ratchet and covenant propagation 279 to 286 and 291 PASS; bootstrap idempotent GREEN;
  token reduction BLIND (no BEFORE/AFTER harness configured). `cm_jev_detection` and `cm_jev_wiring` are RED because of
  the operator's real host state (the detection record and opencode.json). `main_*.txt` shows the same RED on `main`. On the
  pre-merge vehicle, detection fails the same two clauses. The extra `key` clause is the vehicle's stricter check run
  against an older host record. These are host findings, not tree regressions.
- `scripts/run_full_suite.sh --verify-manifest`: MANIFEST-OK.
