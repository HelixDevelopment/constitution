# redpin vehicle report (class: default-tier test builds its RED artifact from `git show HEAD:`)

- Vehicle: branch `vehicle/redpin` from main `8e496db`, in clone `/home/milosvasic/.cache/claude-tmp/redpin.dbLTap/repo` (the real repo was not edited)
- Head: `2ca4d1b47f0391888b02ff052e4c47d237a95672` (one commit on top of 8e496db)
- Bundle: `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/redpin.bundle`, sha256 `cc4d30561be7ceb3b4d40358f0ea06f71a0100690819e6874fa40e901c714f59`, range `8e496db..vehicle/redpin`, head `refs/heads/vehicle/redpin`
- Not pushed. No submodule drift (`git status --ignore-submodules=none` lists no submodule). Trailers: `Roadmap-Item: redpin-class (id pending registration)`, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Model: Opus 5.5 (claude-opus-5-5). Effort: not settable or readable from inside this run, so it is reported as `?`.

## 1. Census (control-needled)
The detector is embedded in `tests/test_no_head_red_builder.sh`. It flags a shell `git show|cat-file -p|cat-file blob` read of a `HEAD[~^..]:` revision whose output is written to a file. It flags the Python equivalent the same way.

- Positive control: all 5 known instances at 8e496db are flagged.
- Negative control: a fabricated revision token is not flagged.

Census on the vehicle tree: 676 test files scanned. No HEAD-built RED artifact remains outside PENDING.

Instances found on main 8e496db:
- `scripts/multitrack/test_multitrack_orchestrator_reconcile.sh`, `..._reconcile_rc.sh`, `..._sessions_argparse.sh`, `..._sessions_pid_status.sh` and `..._supervisor_wiring.sh` (the 5 known instances). All are fixed here.
- `tests/gates/test_oracle_ratchet_and_consumer_skips.sh` is still a HEAD builder on main. It is owned by the CON-043 round-2 vehicle, which pins it (`RED_PIN=ca88eda...`), so I did not touch it. It sits in the guard's PENDING list and is reported as a NOTE.
- `tests/layout/test_layout_mutations.sh` uses `PRE_REV=a0609ec^`. That revision is already pinned, so it is legitimate and not flagged.

## 2. Reproduce, root cause, fix

RED on main 8e496db, on a committed tree (evidence files are `scratchpad/redpin_red_*.out`):
```
reconcile:     FATAL: extracted HEAD copy does not contain the expected pre-fix 'exp=val($0,"expires")' construct (rc 94)
reconcile_rc:  same FATAL (rc 94)
argparse:      FAIL: RED(bash|sh): expected the pre-fix copy to be timeout-killed (rc=124), got rc=2 (rc 1)
pid_status:    FATAL: no outer project root (rc 90)
supervisor:    FATAL: required file not found: <bare parent dir>/scripts/multitrack/rb05_fixtures/mock_claude.sh (rc 91)
```

Root cause, measured: each test extracted its "pre-fix" artifact with `git show HEAD:<path>`. On any committed tree that copy already contains the fix, so the RED leg cannot go RED. That gives rc 94 for the two reconcile tests and rc 1 for argparse, where the guard already exits cleanly with rc 2. pid_status and supervisor_wiring also hard-fail when there is no outer consumer project root or RB-05 mock. That second failure is environmental, and it sits on top of the same HEAD-built RED.

All five fixes are in commit 55998fb, so the pin is its parent: `RED_PIN=e60cbde2e33e7d0542a937331763f6be7e739c9a`.

Fix (same pattern as CON-043 round 2):
- Each RED artifact is extracted at `RED_PIN`.
- A missing pin fails closed with rc 93 (the shallow-clone case).
- The pinned copy must have the pre-fix shape and must lack the fix needle; otherwise rc 94.
- The current artifact must carry the fix needle (control check).
- `RED_MODE` now defaults to `both`, so one default run proves both RED and GREEN.

Per-test notes:
- argparse: the RED oracle checks at run time whether the shell survives `shift 2`. dash aborts on the fatal `shift` with no guard message; bash loops until the timeout (rc 124).
- pid_status and supervisor_wiring: when the RB-05 mock is not reachable they SKIP honestly with rc 77 and `reason=rb05_mock_absent`. `MT_TEST_MOCK_CLAUDE` overrides the lookup.
- supervisor_wiring no longer resolves the project root as the bare parent directory. That old behaviour wrote evidence into `/home/milosvasic/Projects/qa-results`.
- pid_status: C3 sourcing is fixed under dash. A no-argument `shift` in sourced `multitrack_sessions.sh` is fatal there, so the test now sources with a `help` argument.

GREEN on the committed vehicle tree, final run after the commit content was frozen:
```
orchestrator_reconcile     standalone rc=0 | with mock rc=0  RED_MODE=both  PASS=16 FAIL=0 SKIP=0
orchestrator_reconcile_rc  standalone rc=0 | with mock rc=0  RED_MODE=both  PASS=34 FAIL=0 SKIP=0
sessions_argparse          standalone rc=0 | with mock rc=0  RED_MODE=both  PASS=46 FAIL=0 SKIP=0   (also run under bash: PASS=46)
sessions_pid_status        standalone rc=77 SKIP ... reason=rb05_mock_absent | with mock rc=0  PASS=25 FAIL=0
supervisor_wiring          standalone rc=77 SKIP ... reason=rb05_mock_absent | with mock rc=0  PASS=31 FAIL=0
```
"With mock" means `MT_TEST_MOCK_CLAUDE` pointed at a scratch copy of the consumer's `rb05_fixtures/mock_claude.sh`. The consumer project was not modified.

## 3. Paired mutations: `scripts/multitrack/test_multitrack_redpin_mutations.sh`
Each guard gets four legs, each in a `git clone --shared` scratch tree:
- control (rc 0);
- fix removed by a behavioural mutation (rc not in {0,77} and at least one `FAIL: GREEN`);
- RED_PIN pointed back at HEAD (rc 94);
- pin absent (rc 93).

```
with mock:    PASS=20 FAIL=0 SKIP=0   (124 s)
  e.g. orchestrator_reconcile fix removed: rc=1, 6 behavioural GREEN failures; sessions_argparse: 30; sessions_pid_status: 3; supervisor_wiring: 6; reconcile_rc: 9
without mock: PASS=12 FAIL=0 SKIP=2 rc=0  (pid_status, supervisor_wiring legs SKIP reason=rb05_mock_absent)
```

## 4. Census guard and its paired mutation
`tests/test_no_head_red_builder.sh` (1.2 s):
```
PASS: detector golden-TRUE: all 8 builder lines flagged
PASS: detector golden-FALSE: none of 13 compare/restore/pinned/marked lines flagged
PASS: detector python: HEAD blob read flagged, pinned read not flagged
PASS: positive control: all 5 known instances at 8e496db are flagged
PASS: negative control: a fabricated revision token is not flagged
PASS: census: 676 test files scanned, no HEAD-built RED artifact outside PENDING
NOTE: pending tests/gates/test_oracle_ratchet_and_consumer_skips.sh (CON-043 round 2 vehicle ...)
PASS=6 FAIL=0 SKIP=0
```
A legitimate HEAD read can carry the marker `# redpin: not-a-red-builder <reason>`.

`tests/test_no_head_red_builder_mutations.sh` (5.6 s):
```
PASS: control: unmutated guard passes in the scratch clone
PASS: never-match mutant killed (rc=1): golden-TRUE and the positive control fail
PASS: ignore-write mutant killed (rc=1): golden-FALSE fails
PASS: new-builder mutant killed (rc=1): the census names the added line
PASS=4 FAIL=0 SKIP=0
```

## 5. Manifest
Three rows were added in sorted position:
- `test_multitrack_redpin_mutations.sh`: heavy, bash.
- `test_no_head_red_builder.sh`: default, bash.
- `test_no_head_red_builder_mutations.sh`: default, bash, with an `override:` note because its name looks heavy and its measured run time is 5.6 s.

The runner guide's census block was re-synced (`--sync-guide`, one line). `run_full_suite.py` is untouched.

```
main 8e496db (fresh shared clone): RESULT: MANIFEST-MISMATCH (25 problem(s); nothing was run)
vehicle 2ca4d1b:                   RESULT: MANIFEST-MISMATCH (25 problem(s); nothing was run)   -- identical problem set (diffed)
```
The full suite was not run.

Parse checks: `sh -n` and `bash -n` are clean on the 5 sh tests, and `bash -n` is clean on the 3 new bash tests. `shellcheck -S error` exits 0 on all 8.

## Follow-ups (not done here)
1. Register a Roadmap id for this class and replace the placeholder trailer.
2. Run the §11.4.209 independent review (Opus xhigh). It is OWED and was not run by this vehicle.
3. Product defect: `scripts/multitrack/multitrack_sessions.sh` `main()` does `shift 2>/dev/null || true`. With no arguments, that aborts under dash (the `shift` special builtin is fatal), so usage is never printed. Needs a reproduction under §11.4.292 and then a fix.
4. Vendor the RB-05 mock (`rb05_fixtures/mock_claude.sh`, which today lives only in the consumer project) into the constitution, so the two SKIP tests and two mutation legs run standalone.
5. Same environment-dependency class, out of scope: `scripts/multitrack/test_multitrack_sessions_balance_autoselect.sh` (rc 90, "no outer project root") and `scripts/multitrack/test_multitrack_monday_dryrun.sh` (rc 91, mock not found). Both should become honest SKIP 77.
6. Clean up pollution from the old supervisor_wiring evidence path: `/home/milosvasic/Projects/qa-results` exists. I left it alone because it is outside the vehicle and deleting it needs the operator's decision.
7. Remove the PENDING entry for `tests/gates/test_oracle_ratchet_and_consumer_skips.sh` from the census guard once CON-043 lands. The guard will then fail if it is still a HEAD builder.
8. Land on main with an ff-only merge after review, and retire `vehicle/redpin` (§11.4.288).
