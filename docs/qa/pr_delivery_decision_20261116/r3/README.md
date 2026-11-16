# Round 3 evidence: pull-request delivery vehicle (CON-PENDINGprdecl, CON-PENDINGprgate, CON-PENDINGprauth)

Class: gate-logic and unit (§11.4.289(C)(2)), PROVISIONAL (§11.4.290). Nothing here proves a real pull request.

- `run_gates_r3.sh`: the runner (account names, root and temp paths, times redacted). Run twice into
  separate directories outside the tree with `--changed-since main`; every output byte-identical
  (`hash_compare.txt`). Outputs here are pass 1.
- `account_name_mutation_pass1.txt`, `..._pass2.txt`: full (non-quiet) mutation test of the
  account-name gate, twice, identical after temp-path normalisation: 122 cases, 77 of 77 gate mutants killed.
- `anchor_wired_mutation_pass1.txt`, `..._pass2.txt`: quiet mutation test of the anchor gate, twice.
- `f4_account_outside_corpus.txt`: tracked files outside the gate corpus that hold the account (paths only).
- `red_baseline_round2_gate.txt`: the same mutation test run against the round-2 gate: 22 of the round-3 cases fail (RED before the fix).
