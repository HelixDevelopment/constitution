# Follow-ups proposed by the drift-seam fix (2026-11-16)

Placeholders only (`CON-PENDING-*`); the lander re-mints them through the engine (§11.4.202,
§11.4.214). Dedupe was done against `docs/workable_items.db` at cc51c320 (searches on title for
tripwire, third_party, superspec, badge, allowlist, drift).

| Placeholder | Type | Proposal | Dedupe result |
|---|---|---|---|
| (none, link) | - | Audit F5 (stale env-allowlist rows HI_I/HI_U, uncovered XDG0) is a recurrence of CON-144 (Ready for testing, not terminal): LINK only, no reopen (§11.4.214 open-original). The symptom itself was already repaired on main by 1c248515 (PR-0 v3); this change adds the missing landing seam. | CON-144 (link), CON-188 (same symptom class, Queued: link) |
| (none, link) | - | Audit F6 (stale README badge row) duplicates the badge part of CON-379 (Queued): LINK. Symptom repaired by 1c248515; the seam is this change. | CON-379 (link) |
| CON-PENDING-pr-path-drift-seam | Task | The pull-request landing path (§11.4.297, GitHub merges such as PR #7 to #11) does not pass through `land_vehicle.sh publish`, so the new step-6b drift checks do not run there. Commit 1c248515 says the consumer kit's `pr_ci_green.sh` runs both checks; that tool is not in this repository (UNCONFIRMED here). Decide whether the repository needs its own PR-side check entry point. | no hit |
| CON-PENDING-tripwire-t4 | Bug | Audit F7: `test_tripwire.sh` T4 hard-coded `--min-gib 400` and failed on a volume with more than 400 GiB free. Fixed in this change (threshold from measured free space, df target chosen from candidates, control needle on the logged avail_bytes, honest SKIP when no candidate fits). Same class as CON-166 (host-reading test, test_unit_safe), different file. | UNDECIDED vs CON-166: mint with a candidate-duplicate link to CON-166 (§11.4.214(3) default) |
| CON-PENDING-scanner-e2e-topology | Bug | Audit F10: `scanner_gate_false_positive_repairs_test.sh` e2e canon opt-in leg FAILed when superspec/open_design are not checked out. Fixed in this change: the three canon legs are SKIP (topology_unsupported) without a populated third-party submodule. | no exact hit; related CON-103 (superspec topology guard): link |
| CON-PENDING-t4-skip-mutant | Task | Mutant TW-skip (candidate selection never matches) turns T4 into a SKIP and the suite still exits 0: a SKIP is not a failure by design. A consumer of the suite that needs T4 to run must read the `RESULT T4 SKIP` line. Decide whether the codegraph suite should fail on an unexpected SKIP. | no hit |
