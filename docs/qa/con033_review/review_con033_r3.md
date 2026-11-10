# Independent review: vehicle/con033 (CON-033), round 3 of at most 5 (delta review)

| Field | Value |
|---|---|
| Subject | bundle `con033_r3.bundle` (`git bundle verify`: "is okay"), head `2ba4fed38edde0ff7816e957b7d536562a910069` (`refs/heads/vehicle/con033`); delta `b3cecf7c..2ba4fed3` (3 commits, 23 files, +1169 / -389); full range `main..vehicle/con033` is 16 commits on base `9eea893` |
| Reviewer | independent subagent, not the author; Opus 5.5; reasoning effort not readable on this dispatch path (§11.4.231(F.2)) |
| Host | bash 5.3.9; Python 3 (system); load 2 at start, 21 to 35 during the run (other agents); 16 CPUs |
| Work area | clones and mirrors under `scratchpad/rv033r3.z6Hx` (retired after the review), `HOME` and `TMPDIR` inside it; live checkout not touched; nothing pushed. Probes, mutants and every log cited here are kept in `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/review_con033_r3_evidence/` (`SHA256SUMS`, 82 files) |
| Verdict | **NO-GO** for the vehicle. Slice S3 has two important findings (R3-F1, R3-F2) in the same class as R2-F2, so the class recurs across rounds 2 and 3 with non-minor members. Under §11.4.276(E) round 4 must be a STRUCTURAL round for that class. The other slices are GO or GO-with-follow-ups. |

## Verdict in one paragraph

Every round-2 finding R2-F1 to R2-F6 is closed. I reproduced each one RED on the round-2 tree and GREEN on this tree. RVM-B is now killed by the new in-process ledger-owner case, and the official mutation runner kills all 33 of its mutations. Skip semantics are honest: a suite with skipped proof legs exits 77, the runner and the sweep exit 77 with `control_proof_legs_skipped`, and the ledger header records `control_skipped_suites`. But my behavioural differential over 22 of the 27 "equivalent" sub-clauses refutes one of them, G-T-DOT#1. Its mutant makes the path tier answer `capability` for a symlink whose real target is world-writable, and it survives all 11 suites. My own store-tier mutant RVR3b also survives all 11 suites and also answers `capability` where the real code answers `instance`. Both are the R2-F2 class: capability-tier mutants that no suite on this host kills. That is a recurrence with non-minor members, so the next round must be structural and not another point fix.

## Per-slice verdicts (§11.4.235(D))

| Slice | Round-3 files | Verdict | Open findings |
|---|---|---|---|
| S1 dispatch stamp | `test_dispatch_stamp_class.sh` (+22) | GO-with-follow-ups | R3-F3 (minor), R3-F7 (minor), O3 (minor, pre-existing) |
| S3 review record | `review_record.py` (one `# guard:` tag), store-tier, skip-status, r2/r3/r4, subclause-cases and backfill suites; mutation runner; sweep and its red test; analyzer docstring; guard table; kill ledger | **NO-GO** | R3-F1 (important), R3-F2 (important), R3-F4 (minor), R3-F5 (minor) |
| S4 timer | `fc_timer.sh`, `fc_timer_selftest.sh`, `fc_timer_selftest_mutations.sh` | GO (timer mutation runner in the consumer layout: control ok, 45 mutants killed, `ALL KILLED`, rc 0, 2561 s) | none (O4 is a note) |
| S5 manifest | `config/full_suite_manifest.tsv` (+1 row), guide census | GO, pending the excluded-lock acceptance (unchanged from R2-F9) | none new |
| S6 tracker | `docs/Issues.md`, `docs/Issues_Summary.md`, `docs/workable_items.db` | GO-with-follow-ups; ids must be re-minted by the lander | R3-F6 (minor) |
| S2, S7 | not touched in round 3 | unchanged from round 2 (GO) | none |

## Findings

| Id | Layer | Severity | Slice | Finding | Follow-up |
|---|---|---|---|---|---|
| R3-F1 | source-defect: the batch's own proof is invalid (§11.4.235(D)) | important | S3 | The equivalence claim for **G-T-DOT#1** (`comp == '.'` in `_resolution_chain`) is false. The listed reason says "treating '.' as a lookup re-stats the current directory … a trailing '.' leaves the same directory leaf". It misses one effect: the mutant sets `cur` to the string `…/X/.`, and the `..` that follows takes `os.path.dirname("…/X/.")`, which is `…/X`, not the parent. Probe `probe/eqdot2.py`: a symlink `link -> X/./../tgt`, with `X/tgt` at 0644 and `tgt` (the file the kernel opens, `realpath` confirms it) at 0666. The original answers `('instance', '…/tgt is group- or other-writable')`. The mutant answers **`('capability', None)`**, an unsound capability verdict. Probe `probe/eqdot.py`: 6 of 21 links differ at the tier level (`X/./../tgt` and `X/././../tgt` for X in 755, 777 and 1777). The other direction is a false refusal: the original says `capability` and the mutant says `instance`, "does not resolve". All 11 runner/sweep suites give the control's statuses on the mutant (`s11_veh_DOT.log`: ten suites rc 0 and r4 rc 77, the same as the control). The ledger row says `SURVIVED 0`, and the guard table accepts it only because the equivalents file holds a reason. The row came in with `8c0b137e` and is in the batch range (it is not on main). | Add a `_path_tier` case next to the G-T-DOTDOT#1 case (`test_review_record_subclause_cases.sh` line 624) that covers both directions: the unsafe one (`X/./../tgt`, with `X/tgt` owner-only and the real target foreign-writable, must be `instance`) and the false-refusal one. Delete the G-T-DOT#1 row from the equivalents file, regenerate the ledger, and add a reviewer differential like this one to the runner. |
| R3-F2 | source-defect: a reviewer-authored mutation survives (§11.4.194(6)(d), §11.4.235(D)) | important | S3 | My reviewer mutant **RVR3b**, `paths = [records_dir, os.path.realpath(ledger_path) if ledger_path else ledger_path]`, resolves the ledger before the tier. That skips the edge from the directory that holds a ledger symlink. It survives all 11 suites (`s11_veh_RVR3b.log`, the same statuses as the control). Differential `probe/rvr3_diff.py`: a ledger symlink inside a 0775 directory gives `instance` ("directory … writable by others …") in the real code and **`capability`** in the mutant. The R2-F2 fix (cases L1/L2/L3/D1) covers ledger OWNERSHIP, not the directory that holds a ledger LINK. My first variant, RVR1 (`os.path.dirname(ledger_path)`), is killed by the store-tier suite. | Add an L4 case: a ledger symlink in a group-writable directory must be `instance`. Also cover a symlink in a group-writable directory for a records-tree entry, if no case does that yet. |
| R3-F3 | test-instrumentation | minor | S1 | Reviewer mutant **DSM-H**: `${FC_DISPATCH_TIER_POLICY:-}` changed to `${FC_DISPATCH_TIER_POLICY+x}`. With `FC_DISPATCH_TIER_POLICY` set but empty, the project policy file is skipped and the built-in table applies. Differential: 'sonnet medium' with the project file capping `simple` at sonnet/low gives rc 2 from the real hook (refused, project file applied) and rc 0 from the mutant (allowed). `test_dispatch_stamp_class.sh` reports 34/1 on the mutant, but the one failure is the M8 meta-mutant reporting "SURVIVED" because its anchor text no longer matches the mutated hook. That is a wrong-reason kill, and every behavioural assertion passes. The other dispatch suites on full mirrors (control vs DSM-H, mutant applied at line 890, confirmed by `diff`): `test_dispatch_stamp.sh` 295/0 on both; `test_dispatch_stamp_r4_regression.sh` 13 ok on both; `test_dispatch_stamp_r5_regression.sh` 63/0 on both; `test_dispatch_stamp_r6_mutations.sh` prints SKIP (no consuming superproject in a mirror) on both. So DSM-H survives every dispatch suite on behaviour. This is the same class as R2-F6 (policy-precedence coverage), so the class recurs, but every member is minor. | One case: `FC_DISPATCH_TIER_POLICY=` (set, empty) plus a project file must apply the project file. |
| R3-F4 | test-instrumentation | minor | S3 | Kill-ledger noise. `pass_ids` normalises only `/tmp/\S+`, and round 3 swept with `TMPDIR` under `~/.cache/claude-tmp`. 264 of the 316 KILLED rows now carry `/home/milosvasic/.cache/claude-tmp/…` text in "first isolating cases", against 0 in round 2. For 290 of the 316 rows `n_isolating_cases` rose, by up to 9, from PASS lines that differ only by a temp path. Example: the G-T-DOTDOT#1 row lists three `test_review_record_red.sh` "record file was written (…tmp…)" lines and not its real killer. STATUS is unaffected (it is decided by rc against the control's rc). No KILLED row depends on noise alone as far as the listed three cases show, but the guard table's `n >= 1` "measured isolating case" check can now be met by noise. The fixture also leaks the operator's username and session directory names (no credential). | Normalise the realpath of `$TMPDIR` and `$HOME` in `pass_ids`, regenerate the ledger, and add a red-test case where a PASS line differs only by the temp path. |
| R3-F5 | process-doc | minor | S3 | The G-E-HASH-SHAPE#2 reason ("G-E-HASH-MATCH#2 refuses it with the same (None, None)") is false at the function level. Evidence text with a NUL (`"a\x00b"`) and a non-hex sha makes the mutant raise `ValueError` from `os.path.realpath`, where the original returns `(None, None)` (24 of 306 inputs differ). At the CLI the outcome is the same: `cmd_gate` returns 4 for an inadmissible record and `main` returns 4 for an internal error. The claim holds on exit status, not on its stated reason. The original code also raises the same `ValueError` for a NUL evidence name with a well-formed sha, giving exit 4 with an "internal error" message instead of a refusal reason. That is pre-existing; it is not a bypass, because exit 4 is not-PASS. | Correct the reason text. Optionally refuse a NUL in an evidence name before `realpath`, so the message names the record. |
| R3-F6 | process-doc | minor | S6 | Tracker. The vehicle DB is main `b939266a`'s DB (89 items, max CON-091, CON-048 and CON-070 unused, no main row changed) plus 14 new rows, CON-092..105, and 14 history rows. They do not collide with `b939266a`; the lander re-mints anyway. Still open from R2-F7/R2 "required before landing" item 3: every new row has `parent_atm_id` empty. Note that main has 0 items with a parent, so the "main's follow-ups record CON-033 as parent" premise of round 2 is not met on main either. CON-098..103 record R2-F1..F6, which this round closes. They are Queued, and the author lists their closure as OWED. Bugs are stored at Medium (the author reports passing Low); I did not investigate the engine. | At landing: close CON-098..103 with this review as evidence, or do not register them. Set parents per the tracker convention, or record that the convention is "no parent". |
| R3-F7 | test-instrumentation | minor | S1 (and repo-wide) | The R2-F3 fix covers the review-record suites only, but the class "a suite prints SKIP and exits 0" has more members (§11.4.276(C): name the class, enumerate every member). Census `probe/skipexit0.py` over 1193 tracked `.sh` files (an `echo SKIP` line not carrying `exit 77`, followed within 3 lines by `exit 0`). Controls: the fixed r4 suite is found by the first, looser pass and dropped by the refined pass; r6 is found by both. The census finds 11 sites in 8 files on the vehicle and 11 on main `b939266a`, so none is new. One of them, `scripts/fastcycle/tokens/test_dispatch_stamp_r6_mutations.sh:137`, is in a file the vehicle changed (+210 lines in the range) and is a full-suite manifest `entry`. It exits 0 when there is no consuming superproject (measured: rc 0, "no mutant result is claimed"), so a standalone run counts it as PASS (§11.4.289(E)). The others are `test_io_trace_fork_cwd_and_faccessat_r2_regression.sh`, `test_precheck_shellcheck_red.sh`, `test_guard_branch_consistency.sh`, `test_guard_work_track_binding.sh` (2), `test_multitrack_redpin_mutations.sh`, `test_multitrack_work_binding_submodule_db.sh` (2) and `tests/action_prefix/test_subsystem_shortcuts.sh` (2). | Change `exit 0` to `exit 77` in r6, the one file inside this vehicle. Register the other 10 sites as one class item on main (this is pre-existing debt, so do not fix it silently here). |

Class recurrence (§11.4.276(C)/(E)): R2-F2 (RVM-B survives, important), then R3-F2 (RVR3b survives, important), then R3-F1 (G-T-DOT#1 survives and is wrongly listed equivalent, important). All three are "a capability-tier or path-resolution mutant that no suite on this host kills". Two of the three arise only because the r4 CAP legs cannot run on this host. All three are non-minor, so round 4 must be STRUCTURAL for this class: a fresh fixer instance; re-derive ground truth from the kernel's path-resolution semantics (§11.4.276(B)); enumerate every sub-clause and composition of `_resolution_chain`, `_owner_only_error`, `_path_tier` and `_store_tier`, plus reviewer-style refactor mutants (realpath first, dirname, drop an edge, reorder the walk), and kill each one or prove it equivalent with a recorded behavioural differential, never by reading (§11.4.276(C)/(D), §11.4.250). R3-F3 recurs from R2-F6 and R3-F7 recurs from R2-F3. Every member of those two classes is minor (and R3-F7's members are pre-existing on main), so no structural requirement follows from them.

## Verification of the round-2 findings (my own RED/GREEN)

| Round-2 id | RED (round-2 tree `b3cecf7c` or `dd8bd9ca`) | GREEN (this tree) | Closed |
|---|---|---|---|
| R2-F1 posix `trap -p` spelling | bash 5.2.15 / 5.2.37 with `POSIXLY_CORRECT=1` (rootless podman): the round-2 code gives the child SigIgn `0x0` when the caller ignores INT/QUIT (the ignore is lost) | the same probes give `0x2` / `0x6` / `0x4` (the ignore is kept); host 5.3.9 shows no difference by design | yes |
| R2-F2 RVM-B survives | pre tree: RVM-B passes the store-tier suite 7/0 | veh tree: the L1/L2/L3 cases FAIL on RVM-B. Official runner (`mutrunner_veh.log`): `ok RVM-B-store-tier-ledger-dropped KILLED by test_review_record_store_tier_all_entries_regression.sh (rc 1, control 0)`, likewise RVM-B2 | yes (class recurs, see R3-F1/F2) |
| R2-F3 skipped legs read as PASS | pre r4: rc 0, "NOTE: no writable directory with an all-root-owned chain…", `ok 18 / NOT ok 0` | veh r4: 8 `SKIP: R4-CAP-needle … R4-CAP7` lines, `== Skipped proof legs: 8 ==`, `SKIP reason=proof_legs_skipped`, rc 77. `test_review_record_skip_status_red.sh` 8/0 (K1-K4, M1-M4); my runner mutants RNR-1 (`if false` for the skip exit) killed by M1 (rc 0, want 77) and RNR-2 (`want` compared to 0) killed by M2 (rc 77, want 1) | yes |
| R2-F4 FTM-3 survives on 5.3.9 | round-2 selftest passes FTM-3 on the host | F-A-run-resets kills FTM-3 (`timermut_veh.log`: `FTM-3 killed … FAIL[149]: F-A-run-resets`). My call-site variant (`_fcr_reset+=(INT QUIT)` instead of calling the helper) passes the veh selftest on 5.3.9 (169/0), and it is behaviourally equivalent there (5.3.9 keeps the caller's ignore after `trap -`); it is killed on 5.2.15. On 5.3.9 the reset list is checked white-box only. | yes (O4) |
| R2-F5 sweep red-test gaps | veh red test against the round-2 sweep: 14/2 (S6, S7 fail; S4 and S5 pass, they pin behaviour that already worked) | veh: 16/0. My sweep mutants: SWP-1 (worker counts any non-zero rc as red) killed by S7 (rc 77, want 1); SWP-2 (`run_all` stops at the first non-zero rc) killed by S6 (rc 1, want 77); SWP-3 (skip exit 77 becomes 0) killed by S6 (rc 0, want 77) | yes |
| R2-F6 DSM-B survives | round-2 class test on a DSM-B hook: 33/0 (survives) | round-3 class test: 34/1 ("policy precedence (rc=2, want 0: env must win)"), a behavioural kill. My DSM-F (env file must exist) is killed by the M6 effectiveness check. My DSM-H survives behaviourally (R3-F3) | yes (R3-F3 opened) |

Author OWED items I closed: `test_review_record_guard_table.sh` on the new ledger gives `ok GT-REAL` plus GB1..GB11, rc 0. The official runner finished: 33 KILLED, 0 NOT ok, `SKIP reason=control_proof_legs_skipped`, rc 77, 1040 s.

## The r4 capability-leg gap (control_proof_legs_skipped)

- The R4-CAP legs need podman unshare, a subordinate-uid range, and a writable directory with an all-root-owned chain above `TMPDIR`. On this host podman unshare works and the range is `100000:65536`. The legs are skipped only because my `TMPDIR` must live in the session scratchpad, whose chain runs through `/home/milosvasic`. With `TMPDIR=/tmp` they could run. I did not use `/tmp` (session rule).
- Are the "34 mutants that only those legs catch" exercised elsewhere?
  - I could not reproduce the figure 34: UNCONFIRMED.
  - Measured: the 24 round-2 ledger rows whose isolating cases named an R4-CAP leg are all KILLED in the round-3 ledger without the CAP legs.
  - The round-3 sweep (343 sub-clauses, CAP legs skipped) leaves only the 27 listed equivalents surviving.
  - Every one of the 33 runner mutations is killed with r4 at 77. R3-M1 is killed by r4's non-CAP legs: rc 1 against control 77.
  - So no analyzer sub-clause depends on the CAP legs today.
- The gap is real for reviewer-style mutants, though: RVM-B in round 2 was caught only by R4-CAP5, and R3-F2 (RVR3b) is not caught by any non-CAP leg.
- Assessment: on its own, the skip is an honest, tracked follow-up and not a blocker. It needs a CAP-leg run where a root-owned chain is available: the conductor or operator with `TMPDIR=/tmp`, or a host with the legs enabled.
- It does not offset R3-F1/R3-F2, which are measured with the non-CAP suites, and the structural round should include one CAP-leg run as evidence.

## Equivalence spot-check (behavioural differential, not reading)

Harness `probe/eqdiff.py`, `probe/eqdot.py` and an inline evidence probe. Each mutant is built by the analyzer's own `mutate` command. The original and the mutant are loaded in one process, and each guard's function is driven over a crafted grid that compares return values and exception types.

Positive controls (ledger KILLED) all differ on the same harness:
- G-CF-MARKER-MATCH#4: 360 inputs differ.
- G-NL-NONE-BOOL#2: 2 inputs differ.
- G-E-HASH-SHAPE#1: 44 inputs differ.
- G-T-DOTDOT#1: 4 of 21 targeted links differ.

| Claim | Inputs | Differing | Result |
|---|---|---|---|
| G-CF-LOCATED#1, #2, #3; G-CF-MARKER-MATCH#1, #2, #3 | 75 500 each (finding × marker grid, markers dicts only as `already_fixed_markers` filters them) | 0 | holds |
| G-NL-NONE-BOOL#1 | 18 | 0 | holds |
| G-FL-ABSENT#2, G-FL-CLOSED-SET#1 | 32 each | 0 | holds |
| G-T-OWNER-DECLARED#1 | 88 | 0 | holds |
| G-T-PRODUCER-DECLARED#1 | 11 | 0 | holds |
| G-SV-ABSENT#1, G-SV-GO-SLICE-FINDING#1 | 198 each | 0 | holds |
| G-RV-ABSENT#1 | 6 | 0 | holds |
| G-E-NAMED#2, G-E-COMMONPATH#1 | 306 each | 0 | holds |
| G-E-REGULAR#1, G-E-SELF-CITATION#1, G-E-OWN-REALPATH#1 | 120 each | 0 | holds |
| G-E-SELF-CHECK-ON#1 | 120 | 10 | holds at the CLI: the only differing inputs are a record citing itself with the sha of its own bytes, which a real record cannot carry (a fixed point) |
| G-E-HASH-SHAPE#2 | 306 | 24 | holds at the CLI on exit status (4 either way); the stated reason is wrong (R3-F5) |
| **G-T-DOT#1** | 187 grid + 21 targeted links | 29 (reason text) / **6 at the tier level** | **REFUTED** (R3-F1) |

Not checked behaviourally: G-A-BINDING-EQUAL#4, G-D-LIVE-REVIEWED#1, G-V-LISTS#1, G-FL-ABSENT#1 and G-R-BATCH-CHANGES-OK#3. Each of their claims rests on what the callers pass, so it needs a CLI-level differential. That is owed, as part of the structural round.

## Reviewer-authored mutants per touched component (§11.4.194(6)(d))

| Component | Mutant (mine) | Result |
|---|---|---|
| store tier (`review_record.py`) | RVR1 `os.path.dirname(ledger_path)` | killed (store-tier suite) |
| store tier | RVR3b `realpath(ledger_path)` | **survives** (R3-F2) |
| path tier (equivalence claim) | G-T-DOT#1 differential | **survives, claim refuted** (R3-F1) |
| mutation runner | RNR-1 (skip exit disabled), RNR-2 (`want` compared to 0) | both killed (skip-status M1, M2) |
| sweep | SWP-1, SWP-2, SWP-3 | all killed (red test S7, S6, S6) |
| dispatch stamp class test | DSM-F (env file must exist), DSM-H (`+x`) | DSM-F killed (M6 check); DSM-H survives behaviourally (R3-F3) |
| timer | RT1 (only `INT` spelling), RT2 (only `SIGQUIT` spelling), RT4 (reset only the first listed signal) | all killed (F-A-run-resets, F-A-run-resets-posix, F-A-run-intquit) |
| timer | RT3 (no reset in the stdin-closed branch) | equivalent, measured on 5.3.9 and 5.2.15: with stdin closed the child does not ignore INT/QUIT even without the reset |
| skip-status / manifest / tracker | no executable logic changed beyond the rows | n/a (manifest checked with `--verify-manifest`) |

## Notes and observations

- O1 (manifest, S5).
  - Vehicle `--verify-manifest`: rc 3, 1 problem (the excluded set differs from the accepted lock: `check_safepath_census.py`, `foreign_uid_cause.sh`, `review_record_guard_analyzer.py`, `sweep_review_record_subclauses.sh` added). Census total 856. The new row for `test_review_record_skip_status_red.sh` is present.
  - Live main `b939266a` itself has 3 problems: two census files without a manifest row (`scripts/gates/cm_covenant_114_296_propagation_mutation_test.sh` and `scripts/gates/cm_github_issues_source_anchor_wired_mutation_test.sh`, from `090e8062`) and its own lock difference.
  - The merge onto `b939266a` inherits main's two missing rows. That is main's defect; register it on main, and do not fix it silently in this vehicle.
- O2 (process).
  - The vehicle base is `9eea893`, and live main is `b939266a` (it contains `090e8062`, §11.4.296). A merge of `b939266a` is needed before landing.
  - Trailers: `Roadmap-Item: CON-033` and `Co-Authored-By` are on `ccdfd98e`, `70daed68` and `2ba4fed3`, and the author is the operator identity.
  - The R2-F10 history notes still belong in the landing commit message.
- O3 (S1, pre-existing, minor). The class test's "unreadable policy file fails closed" case sets no `FC_DISPATCH_ITEM_ID_RE`, so the real hook returns rc 2 for the item-prefix reason. Under DSM-F the same case still returns 2 for that reason, while with the regex set DSM-F returns rc 0. The assertion passes for the wrong reason; only the M6 stderr check catches DSM-F.
- O4 (S4). On bash 5.3.9 the INT/QUIT reset is verified white-box only (F-A-run-resets reads the helper's list). The end-to-end SigIgn checks discriminate only on bash 5.2. This is acceptable and documented; a 5.2 container leg in the selftest would make it end to end.
- O5 (harness side effect, mine). Importing `review_record.py` from the `wt_veh` scratch worktree wrote an ignored `__pycache__` there. This is a scratch clone, not the live checkout, and it is retired with the work area.

## Required before landing (process, not findings)

1. Fix R3-F1 and R3-F2 in a STRUCTURAL round 4 (§11.4.276(E)), with the class inventory described above.
2. Fold in R3-F3 to R3-F7 as follow-ups or fixes (R3-F7: fix r6 in the vehicle, register the other 10 sites on main).
3. Merge `b939266a` (merge, never rebase).
4. Re-mint the tracker ids on the live DB, close CON-098..103 with evidence, and set parents per the convention.
5. Re-run `--verify-manifest`, then do the operator or reviewer act for the excluded lock (R2-F9, still open).
6. Run the CAP legs once where a root-owned chain is available.
7. Put the R2-F10 note in the landing commit message.
