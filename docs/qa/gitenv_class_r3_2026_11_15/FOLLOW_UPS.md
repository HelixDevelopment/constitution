# gitenv-class round 3: follow-up drafts

| Field | Value |
|---|---|
| Created | 2026-11-15 |
| Status | DRAFT tracker text; no tracker row was written by this vehicle (no tracker access in the scratch copy) |
| Roadmap item | CON-402 round 3 |

Drafts for the workable-items tracker, each in the §11.4.148 shape (what, scope, reproduction, acceptance).
None of them is claimed done. FU-1, FU-2, FU-3 and FU-5 are carried from round 2
(`docs/qa/gitenv_class_r2_2026_11_14/FOLLOW_UPS.md`) with the changes noted; FU-4 is closed by this round.

## FU-1 (Task): run the census at the pull seam (carried, unchanged)

The census still runs only from `tests/test_git_env_class.sh`. The round-2 draft stands: a thin
`scripts/gates/cm_*.sh --root` wrapper, its paired mutation test, a STEP 5b entry, a ledger row and a manifest
row. The gate name stays a proposal; it is not minted here and appears in no gate site.

## FU-2 (Task): `group.go` with a reviewed binary rebuild (carried, unchanged)

`scripts/workable-items/cmd/workable-items/group.go` is still the `go-binary-owed` row. The round-2 draft stands.

## FU-3 (note, latent): staged-gitlink readers and `GIT_INDEX_FILE` (carried, unchanged)

## FU-4: closed by this round

The census now covers `scripts/` and `tests/` (universe 1627 files, members 513). The 82 unscrubbed test files
of the round-2 probe are members now and are HERMETIC or rowed.

## FU-5 (Bug, pre-existing): `meta_test_verification.sh` TERM race (carried, unchanged)

The scratch root is made before the traps are installed; the round-2 draft stands.

## FU-6 (Bug, pre-existing): `cm_gitlink_on_remote_mutation_test.sh` exits 1 with no ambient variable

- **What.** On the unchanged tree `005bcfd1`, with no git variable set, the mutation test reports 18 passed and 1
  failed and exits 1 (`ev/red` sentinel line `mode=none rc=1`; round 2 saw the same case 13). This round does
  not change it; the B3 behaviour check compares each mode against the measured no-variable exit instead.
- **Acceptance.** The failing case is root-caused (§11.4.102), fixed or explained, and the test exits 0 on a
  clean tree.

## FU-7 (Bug, pre-existing): `scripts/fastcycle/tests/test_consumer_enumerate_red.sh` does not parse under `sh -n`

- **What.** The file's shebang names `sh`, but `sh -n` fails on the unchanged tree (`244: Syntax error: "("
  unexpected`); it is run with bash.
  The scrub insertion tool parse-checked it with `bash -n` for that reason (`insert_run*.txt`).
- **Acceptance.** Either the shebang names bash, or the file parses under `sh -n`.

## FU-8 (Task): the honest limits of the closed-world census

- **What.** A file that runs git without the letters `git` in its text (a name built at run time) is not a
  member; sourced-library and entry-function-scrub rows rest on a reviewed reading plus the write detector.
  A periodic independent re-read of the rowed files (31 rows today) keeps the rows honest.
- **Acceptance.** A dated re-read record per row, or a decidable check that replaces the reading.

## FU-9 (Bug, pre-existing): `tests/jev/test_detection_matrix.sh` leaves a `jev_server.py` fixture running

- **What.** During the regression run, one `python3 tests/jev/fixtures/jev_server.py 0` process per tree
  outlived the test that started it (start times 03:34:08 on the unchanged tree and 03:34:21 on the fixed tree, both
  inside the run of `tests/jev/test_detection_matrix.sh`; reparented to the user service manager). The test itself
  exited 0 on both trees. The leak is the same on both trees, so this round did not cause it. The two processes
  were stopped by PID after their command lines were checked.
- **Reproduction.** Run the test once with no git variable set, then list `jev_server.py` processes under that tree.
  This is UNCONFIRMED as deterministic: one run per tree was seen.
- **Acceptance.** The test's trap stops every server it starts; a rerun leaves no `jev_server.py` process behind.
