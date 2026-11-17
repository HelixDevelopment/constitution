# Jev S3/S4 round 3 (CON-299): fixes for the independent review of `c2489197`

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12 |
| Status | evidence (CON-299, In progress; no GO claimed) |
| Evidence class | gate-logic only (stub llmctl, stub curl, fixture rows; §11.4.289(C)(2)). Nothing here is live evidence. |

The round-2 review (NO-GO) found three IMPORTANT source-defects (R2-1, R2-2, R2-3), two minor ones (R2-4, R2-5),
surviving mutants (R2-6: X1, X6, X7, X16, X19), the placeholder trailer (R2-7) and three nits. Every fix was written
test-first: the new tests were run against the round-2 code first (RED) and then against the fixed code (GREEN).
Only stub binaries ran. No real `llmctl`, `systemctl`, network or forge call was made; nothing was pushed.

## RED then GREEN

| Suite | Round-2 code (RED) | Round-3 code (GREEN) | Log |
|---|---|---|---|
| test_s3_bootstrap_honesty.sh (H10, H11) | 106 pass / 6 fail | 112 / 0 | `red_s3.txt`, `green_s3.txt` |
| test_s4_placement.sh (P27 to P32) | 122 pass / 23 fail | 145 / 0 (149 / 0 after the X10/N11/N13 assertions) | `red_s4.txt`, `green_s4.txt` |
| test_jev_status_health.sh (S8) | 36 pass / 6 fail | 42 / 0 | `red_health.txt`, `green_health.txt` |
| test_run_all_leak_detector.sh (L1 to L3) | new test; with the X19-blinded run_all: 4 pass / 5 fail | 9 / 0 | `x19_selftest.txt` |

The S4 RED run used the round-2 `jev-place.sh` (from `git show c2489197:scripts/jev/jev-place.sh`) through the test's
`S4_PLACE_UNDER_TEST` override; the S8 RED run used the round-2 `lib_decide.sh` through `S8_LIB_UNDER_TEST`.
(`lib_assert.sh` clears every `JEV_*` variable, so the overrides use other prefixes.)

## Findings

| id | status | what changed | test |
|---|---|---|---|
| R2-1 | FIXED | The probe signature is a function of a detection record; after stage 3 writes its record the signature is recomputed from THAT record (memoised probes, no extra call) and the stored stage key is re-stamped, so the next run computes the same key whether or not this run started with a record. Root cause of X1 (found while fixing): the signature rows were split with TAB, and `read` collapses empty TAB fields, so every local health row was silently dropped. Rows now use the unit separator `\x1f`. | H10 (fresh state, hosted 200: run 2 and run 3 no-change with record and stamp byte-identical; 200 to 402 and 402 to 200 re-run), H11 (local gateway healthz 200 to 000 re-runs) |
| R2-2 | FIXED | Failed start + failed cleanup stop keeps `{constitution_started:true, leases:[], start_failed, stop_failed}`. Such a set is never joined, never adopted as operator-started (a candidate that already has a set is skipped), its stop is retried on the next acquire, and release stops it. | P27 |
| R2-3 | FIXED | Join re-check is an allow-list: capacity readable, unit `running`/`active`, verdict `fits`/`fits_with_reduced_threads`. Anything else (failed, starting, absent, does_not_fit, undetermined) is refused with event `refused_join` (degraded keeps `refused_degraded`), rc 5, no lease, no cache entry. | P28 |
| R2-4 | FIXED | `Constitution.md` Last modified set to the real UTC time of the edit; Revision stays 96. | grep in this pack |
| R2-5 | FIXED | `jev_settings_wired` matches a PreToolUse command whose command word (after env assignments and an optional `sh`/`bash`/`zsh`/`dash` interpreter, quotes allowed) has basename exactly `jev-gate.sh`. A stale `~/.claude-*` dir counts only with such a real entry. Honest limit: a quoted path that contains a space is not recognised. | S8 |
| R2-6 | FIXED | X1 (H11), X6 (P29: field 22 against an independent python oracle, with a control field), X7 (P30: zombie holder reaped), X16 (S8), X19 (new `test_run_all_leak_detector.sh`: golden-bad leak, golden-good, blinded control). | as listed |
| R2-7 | OPEN, for the lander | See below. History was NOT rewritten. | n/a |
| nit event | FIXED | `write_placement` refuses an `event` outside its closed set (rc 2). | P32 |
| nit RS3 | FIXED | A stop mark without a pid is cleared only by age (stop timeout + 30 s), never as a dead stopper. Documented in the producer header. | P31 |
| nit SC2164 | FIXED | `docs/qa/jev_s3s4_20261112/t4_gate.sh` exits when `cd` fails. This script was edited AFTER its T4 runs were captured; the runs were made with the earlier text (the change only adds `|| exit 1`). `SHA256SUMS` was regenerated for it. | shellcheck |

### R2-7, note for the lander

`dc654757` carries `Roadmap-Item: CON-PENDING-JEV-CONSTITUTION`. Superseded on 2026-11-15 (round 10, review R9-8):
no commit of the series is re-committed or rebuilt (§11.4.113, no history rewrite). The trailers stay as written and the
round-10 mapping note (`docs/qa/jev_s3s4_20261112/round10/README.md`, and CHANGELOG.md) maps `CON-299`,
`CON-PENDING-JEV` and `CON-PENDING-JEV-CONSTITUTION` to the id minted at landing.

## Mutants

42 mutants: the reviewer's 19 (X1 to X19, re-expressed on the round-3 code; X11b adds the verdict closed-set guard
removal paired with X11) and 22 of this round (N1 to N22) on the new logic. Each is an exact single-anchor replacement
(an anchor that does not occur exactly once is reported INVALID, never skipped; none was). The harness is
`mutants.py.txt` in this directory (rename to `.py` to run; kept as text so the full-suite census does not count it); it runs the suite under `nice -n 10` in its own process group, stops at the first
`FAIL - ` line, restores the file with `git checkout --` and refuses to continue unless `git status` is clean.

Result: **41 KILLED, 1 EQUIVALENT, 0 SURVIVED.** Run 1 left 4 survivors: X10, N11, N13 (killed in run 2 after the
assertions of the last test commit were added: the degraded event, the capacity-check refusal, the write_placement
guard) and N4.

N4 (the re-stamp may overwrite a `tainted-retry` stage key) is EQUIVALENT on this code: `stage_taint` is called only
for `provision`, `install-per-agent` and `calibrate-shadow`, never for `detect-models`, so the guard cannot change any
run. It is kept as a defensive guard.

The round-1 reviewer's RM1 to RM17 are covered by the existing suites (round 2 recorded them; this round did not
re-run them). The 20 mutants of the round-1 author are not recorded in detail anywhere this round could read
(UNCONFIRMED); they are not claimed.

| id | mutation | suite | run 1 | run 2 (after the new asserts) | final |
|---|---|---|---|---|---|
| X1 | PROBE_SIG ignores local health endpoints | test_s3_bootstrap_honesty.sh | KILLED |  | KILLED |
| X2 | auth probe memo never hits | test_s3_bootstrap_honesty.sh | KILLED |  | KILLED |
| X3 | PROBE_SIG selects no endpoint | test_s3_bootstrap_honesty.sh | KILLED |  | KILLED |
| X4 | failed stop drops the stop mark | test_s4_placement.sh | KILLED |  | KILLED |
| X5 | failed stop exits 0 | test_s4_placement.sh | KILLED |  | KILLED |
| X6 | proc_start reads field 23 (vsize) not 22 | test_s4_placement.sh | KILLED |  | KILLED |
| X7 | empty-cmdline (zombie) check removed | test_s4_placement.sh | KILLED |  | KILLED |
| X8 | stop mark cleared while the stopper is alive | test_s4_placement.sh | KILLED |  | KILLED |
| X9 | release stops only the first set | test_s4_placement.sh | KILLED |  | KILLED |
| X10 | join skips the degraded re-check | test_s4_placement.sh | SURVIVED | KILLED | KILLED |
| X11 | start failure stored as the verdict | test_s4_placement.sh | KILLED |  | KILLED |
| X11b | verdict closed-set guard removed (paired with X11) | test_s4_placement.sh | KILLED |  | KILLED |
| X12 | llmctl enable sent after a successful start | test_s4_placement.sh | KILLED |  | KILLED |
| X13 | health ts not normalised from ms | test_jev_status_health.sh | KILLED |  | KILLED |
| X14 | only the last attempt counted | test_jev_status_health.sh | KILLED |  | KILLED |
| X15 | wired for any hook event | test_jev_status_health.sh | KILLED |  | KILLED |
| X16 | jev-gate substring match (the round-2 matcher) | test_jev_status_health.sh | KILLED |  | KILLED |
| X17 | cm_jev_wiring: hook = settings file exists | test_jev_status_health.sh | KILLED |  | KILLED |
| X18 | join does not re-register the cache | test_s4_placement.sh | KILLED |  | KILLED |
| X19 | run_all leak detector blinded | test_run_all_leak_detector.sh | KILLED |  | KILLED |
| N1 | probe signature not recomputed after the record is written | test_s3_bootstrap_honesty.sh | KILLED |  | KILLED |
| N2 | stage key not re-stamped after the record is written | test_s3_bootstrap_honesty.sh | KILLED |  | KILLED |
| N3 | signature fields joined with TAB again | test_s3_bootstrap_honesty.sh | KILLED |  | KILLED |
| N4 | re-stamp overwrites a tainted-retry stage | test_s3_bootstrap_honesty.sh | SURVIVED |  | EQUIVALENT (justified below) |
| N5 | failed-start set not saved | test_s4_placement.sh | KILLED |  | KILLED |
| N6 | join query does not exclude start_failed sets | test_s4_placement.sh | KILLED |  | KILLED |
| N7 | acquire never retries the stop of a failed-start set | test_s4_placement.sh | KILLED |  | KILLED |
| N8 | candidate with an existing set is not skipped | test_s4_placement.sh | KILLED |  | KILLED |
| N9 | join allow-list widened to undetermined/does_not_fit | test_s4_placement.sh | KILLED |  | KILLED |
| N10 | join unit-status allow-list removed | test_s4_placement.sh | KILLED |  | KILLED |
| N11 | join proceeds when capacity is unreadable | test_s4_placement.sh | SURVIVED | KILLED | KILLED |
| N12 | stop mark without a pid treated as a dead stopper | test_s4_placement.sh | KILLED |  | KILLED |
| N13 | event closed-set guard removed | test_s4_placement.sh | SURVIVED | KILLED | KILLED |
| N14 | release does not stop a failed-start set | test_s4_placement.sh | KILLED |  | KILLED |
| N15 | failed-start set recorded as not constitution-started | test_s4_placement.sh | KILLED |  | KILLED |
| N16 | successful retry stop does not remove the set | test_s4_placement.sh | KILLED |  | KILLED |
| N17 | matcher: basename anchor loosened (any prefix) | test_jev_status_health.sh | KILLED |  | KILLED |
| N18 | matcher: interpreter prefix dropped | test_jev_status_health.sh | KILLED |  | KILLED |
| N19 | matcher: env-assignment prefix dropped | test_jev_status_health.sh | KILLED |  | KILLED |
| N20 | matcher: trailing word-end anchor dropped | test_jev_status_health.sh | KILLED |  | KILLED |
| N21 | run_all: a leak does not fail the test | test_run_all_leak_detector.sh | KILLED |  | KILLED |
| N22 | run_all: a leaked server is not killed | test_run_all_leak_detector.sh | KILLED |  | KILLED |

## Other checks

All sequential, `nice -n 10`, load average about 17 to 27, on the vehicle tree before the docs commit.

- `tests/jev/run_all.sh` once: `ran 32, failed 0`, rc 0, 50m04s (`run_all.txt`). The log has 4 lines
  `fork: retry: Resource temporarily unavailable` from run_all's own `/proc` scan; bash retried each and no test
  failed. Cause UNCONFIRMED (the user process limit is 123694 and about 7000 threads ran; a cgroup pids limit of the
  session scope is the likely limit but was not read).
- Individual suites: see the RED/GREEN table (`green_*.txt`).
- `shellcheck -S warning` on every changed script plus the jev producers (`shellcheck_r3.txt`): only the 2 SC2034
  in `lib_decide.sh` and the SC2045 in `jev-calibrate.sh`, all present on `c2489197` too. The 2 new test-file
  warnings this round first produced (SC1090, SC2034) were fixed with directives; `t4_gate.sh` SC2164 is gone.
- `scripts/run_full_suite.sh --verify-manifest`: first MANIFEST-MISMATCH for the new test (no manifest row) and for
  the harness file; the row was added with `--generate-manifest` (only that row differs), the harness is kept as
  `mutants.py.txt` (evidence, not a census file), the guide census block was regenerated with `--sync-guide`; then
  `RESULT: MANIFEST-OK`, census total 907 (was 906) (`verify_manifest.txt`).
- `SHA256SUMS` of the pack regenerated over every file (`sha256sum -c` clean).
- Key needle scan (counts only, values read by name in a subshell and never printed) over the whole range patch
  `02c10935..` working tree, this pack included: TYPESAFE, OPENROUTER and LLMCTL key values full 0, 12-character
  prefix 0; positive control `CON-299` 14, negative control 0.

Process note: during this round the shared scratch clone this vehicle's clone borrowed objects from was removed by
someone else; the base objects were re-borrowed read-only from another scratch clone holding `02c10935`
(`git rev-list --objects --missing=print 02c10935..HEAD` reports 0 missing). No live checkout was touched.

## UNCONFIRMED

- What the real `llmctl capacity --json` answers for a profile whose unit is already running. If it answers
  `does_not_fit` for a running unit, a join is refused and the route falls back to cloud (conservative, never a
  join of a dead unit). The stub now reports units it started as running.
- The 20 mutants of the round-1 author are not recorded in detail anywhere this fixer could read; only the round-1
  reviewer's RM1 to RM17 are, and those are covered by the existing suites (round 2 killed RM5, RM11, RM12, RM15).
- Live T3, T4 and T5 were NOT re-captured after round 2 or round 3.
