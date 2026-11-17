# Candidate tracker items found while fixing NEW-1..NEW-5 (PREPARED, NOT REGISTERED)

Mint ids via the workable-items engine (next free CON-312+ after fix227 lands). Do not hand-edit the DB.
Placeholder trailer used on the fix commit: `Roadmap-Item: CON-PENDING-RETEST`.
Work dir of the fixer: path in <scratchpad>/rtfix_dir.txt (logs under o/).

## C-1 — 58 fastcycle tests resolve the canon as `$ROOT/constitution` (clone-name dependency)
- Type: Bug (test defect), Severity: Low, Status: Queued
- Description: 58 files under scripts/fastcycle/tests read canon files through `$ROOT/constitution/...`
  where ROOT is four directories above the test. That only works when the canon checkout directory is named
  `constitution` and sits directly under the consumer root. The canon tree is always `$FC/../..`
  (two above scripts/fastcycle). Fixed in this change for test_tool_deferral_red and test_custody_sweep_red
  only (the NEW-1/NEW-2 units); the other files are untouched.
- Reproduction: UNREPRODUCED as a failure (every measured clone was named `constitution`); census only:
  `grep -l '\$ROOT/constitution' scripts/fastcycle/tests/*.sh | wc -l` -> 58 on 02c10935.
- Investigation: root-cause-found-with-evidence (path arithmetic), not-started for the fix.

## C-2 — scripts/fastcycle/tests/run_all.sh counts rc 77 (SKIP) as FAIL
- Type: Bug, Severity: Medium, Status: Queued
- Description: run_all.sh treats every non-zero exit as FAIL. The units fixed here now exit 77 with a
  `reason=topology_unsupported` last line in canon-alone layout, so run_all.sh reports them as FAIL while
  scripts/run_full_suite.sh (which runs members alone) reports SKIP. run_all.sh should report SKIP with
  the reason and not fail on 77 (section 11.4.3 / 11.4.69).
- Reproduction: pre-existing behaviour read from the script; not run as a batch here (host load).
- Related: CON-092, CON-098.

## C-3 — test_anchor_citations_red: the post-needle synthetic sections never run on canon-alone
- Type: Bug (test defect), Severity: Low, Status: Queued
- Description: after this change the test SKIPs (77) as a whole when there is no consumer superproject or
  the superproject is provably another consumer. The synthetic sections after the needle do not depend on
  consumer data and could still run (section-level skip, CON-092 class).

## C-4 — test_custody_sweep_red REAL-STATE block reads stash/worktree state of the consumer root
- Type: Task, Severity: Low, Status: Queued
- Description: informational block reads `git stash list` / worktree state at ROOT; in canon-alone it reads
  whatever repository (if any) is above the clone. Output is informational only; classify or scope it.

## C-5 — fastcycle tests that still skip the WHOLE test on missing consumer data (CON-092 class)
- Units: test_2nd_display_triage*, test_heartbeat_liveness*, test_core_ondemand* use `fc_require_consumer`
  (whole-test skip). Already tracked by CON-092/CON-093; listed here only so the lander can link it.

## C-6 — test_triple_harness_red: the leftover harness work dir after a full run (temp-dir leak)
- Type: Bug (test infra), Severity: Low, Status: Queued
- Description: after one full GREEN run of test_triple_harness_red.sh (rc 0, 245 s, 2026-11-12) one dir
  `tmp.XXXXXXXXXX` holding only `golden-bad` and an empty `out` was left in TMPDIR. lib/triple_harness.sh
  removes that dir in its EXIT trap, so the harness process ended without running that trap (a SIGKILL is
  the likely case; `out` exists, so it ended after a tool run started). When and by which section of the
  test: UNCONFIRMED (the rig's `gone`/watchdog SIGKILLs are candidates). Fix direction: the test that SIGKILLs a unit removes that
  unit's TMPDIR itself (give the unit its own TMPDIR and delete it), never leaving it to the unit.
- The full-suite runner measures the same class: on fc57ad0c (retest_fc57/keep/results.jsonl)
  test_check_deps `leaked=6` and test_triple_harness_red `leaked=4`; on 02c10935 with this change
  test_check_deps again `leaked=6` (pre-existing, unchanged by the rig fix).
- Reproduction: reproduced-host-fixture once (dir removed by the fixer with a guarded rm after recording).
- Investigation: in-progress (cause class known, the exact sender not identified).

## C-7 — sigwin_check.sh: an empty rig result was reported as `got ''` (fixed here, listed for traceability)
- Fixed in this change (NEW-4): the driver now records `NO-RESULT rig-rc=<rc>` instead of an empty string.
