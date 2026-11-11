# Independent review of fixu fix round 2 (§11.4.209 / §11.4.142)

| Field | Value |
|---|---|
| Reviewed | bundle `scratchpad/fixu2/fixu2.bundle`, head `351fe27726db57f1f27652a0d99de46a051049cd`, 12 commits on `270e4867` (base `bdc3ac43`) |
| Prior review | `scratchpad/review_fixu.md` (round 1) |
| Reviewer | independent subagent, Opus; effort requested xhigh, not readable from inside the dispatch (§11.4.231(F.2)), so not claimed |
| Date | 2026-11-06 |
| Workspace | scratch clones under `scratchpad/rev_fixu2/` (retired at the end); evidence kept in `scratchpad/rev_fixu2/ev/`, reviewer scripts in `scratchpad/rev_fixu2/scripts/` |
| Live checkout | `/home/milosvasic/Projects/constitution` was not modified; nothing was committed or pushed; a copy of its DB was read once (item 11) |
| Clean environment used | `env -i PATH=/usr/bin:/bin HOME=<ev>/tmp TMPDIR=<ev>/tmp` unless stated |

All paths below that start with `ev/` are under
`/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rev_fixu2/ev/`.

## 1. Verdict per item

| # | Commit | Item / prior finding | Verdict | Open findings |
|---|---|---|---|---|
| 1 | faf05f06 | CON-117, CON-110 F110-1..3 | GO-with-follow-ups | F117-1 |
| 2 | 95ba8919 | CON-109 F109-1..3 | GO-with-follow-ups | F109-4, N109-1 |
| 3 | 9dc91300 | CON-120 (F-PRE-1) | GO-with-follow-ups | F120-1, N120-1..3 |
| 4 | 785ad987 | CON-121 (F-PRE-2) | GO-with-follow-ups | F121-1, F121-2 |
| 5 | 5c2433cd | CON-089 F089-1 | GO | none |
| 6 | 6ec2a72b | CON-099 F099-1 | **NO-GO** | F099-2 (important), F099-3 |
| 7 | 39911199 | CON-114 F114-1 | GO | none |
| 8 | e3226527 | CON-108 N108-1 | GO | none |
| 9 | 74f1f128 | CON-112 F112-1 | GO | none |
| 10 | 1b0b3813 | CON-113 F113-1 | GO-with-follow-ups | F113-2, F113-3, N113-1 |
| 11 | a9d853fc | CON-047 F047-1, F047-2 | GO-with-follow-ups | F047-3, F047-4, N047-1, N047-2 |
| 12 | 351fe277 | tracker (T-1, T-2, CON-120..123) | GO | none (CON-099 note to be updated with item 6) |
| 13 | (not committed) | lock proposal `resolve1_lock_PROPOSAL_r2.md` (P-1, P-2) | GO | none |
| 14 | 95ba8919, faf05f06 | manifest rows for the two new tests | GO | none |

Round verdict: **NO-GO for item 6 only.** Every other item is GO or GO-with-follow-ups, decided per
slice as §11.4.235(D) requires. Item 6 does not block the other slices.

Why item 6 is NO-GO and not GO-with-follow-ups (the layer decision, recorded by the reviewer as
§11.4.235(D) requires): the artifact this item ships IS the test `test_precheck_slicer_red.sh`, and
the commit's headline claim, "C2a requires both the parse-error and the shellcheck leg", is false for
the shellcheck leg (F099-2): the leg matches a configuration string, not a finding. The test also
turns red on a host where shellcheck is not on PATH, where the base passed (F099-3). The shipped
artifact behaves wrong in the way the fix says it no longer does, so I record F099-2 as a
`source-defect` of this item, severity `important`, which is never minor-class (§11.4.276(G.2)). If
the conductor reads it as `test-instrumentation` instead, the verdict becomes GO-with-follow-ups; I do
not recommend that reading, because the fix would then be closed on a claim the reviewer disproved.
The repair is small (section 3, F099-2 and F099-3).

## 2. Closure of the round-1 findings

| Prior finding | Closed? | Evidence (same command, base then head) |
|---|---|---|
| F110-1 empty `XDG_RUNTIME_DIR` | yes | persistent-launch test: base SKIP 77, head PASS (`ev/pl_base_emptyxdg.out`, `ev/pl_head_emptyxdg.out`) |
| F110-2 foreign bus only | yes | base FAIL rc 1, head SKIP 77 naming the socket (`ev/pl_base_foreign.out`, `ev/pl_head_foreign.out`); foreign XDG with a live standard bus: head PASS (`ev/pl_head_foreign_stdlive.out`) |
| F110-3 inline derivation | yes | derivation moved into `scripts/lib/user_bus_env.sh`; unset case PASS on both (`ev/pl_*_unset.out`) |
| F109-1 symlinked canon path | yes | meta-test C6/C7, round-1 fixture C5: base TOTAL=2 dev=0, head TOTAL=3 dev=1 (`ev/rf_base.out`, `ev/rf_head.out`) |
| F109-2/3 SKIP reason aggregation | yes | meta-test against the base aggregator 9/3, head 12/0 (`ev/rsd_baseagg.out`, `ev/rsd_head.out`) |
| F-PRE-1 supervisor sleep leak | yes | wiring test head 26/0; head test with the base product 23/3 (f3 x3) (`ev/sw_head_green.out`, `ev/sw_sw_red.out`); direct probe: base TERM and HUP orphan the sleep, head TERM/INT/HUP leave none (`ev/watch_sig_probe.out`) |
| F-PRE-2 sqlite3 CLI dependency | yes | `test_reopen_rate_red.sh` base rc 1, head rc 0 (`ev/rr_base.out`, `ev/rr_head.out`); see F121-1 for a new gap |
| F089-1 unwritable TMPDIR | yes | base writes under `/` and fails rc 1, head stops with "mktemp -d failed" rc 2 (`ev/lum_base_rotmp.out`, `ev/lum_head_rotmp.out`); normal TMPDIR PASS, TMPDIR left empty (`ev/lum_head_ok.out`) |
| F099-1 C2a accepted either leg | **partly** | the parse leg is now required (author's no-lower mutant killed); the shellcheck leg is a carrier match (F099-2) |
| F114-1 liveness cases | yes | head 42/0; noF, nox, w mutants each 41/1 (`ev/sa_head.out`, `ev/sa_mut_*.out`) |
| N108-1, F112-1 | yes | doc-only; census re-run `SUMMARY mutants=393 equivs=3 cleanup=3 pairs=420 drift=0 needle=ok` |
| F113-1 eval row per file | yes | a second eval appended to `safe_rm.sh`: base VERDICT PASS, head UNCOVERED `<eval>#b1e750228c4a` rc 1 (`ev/ge_sneak_base.out`, `ev/ge_sneak_head.out`); live gate PASS on both (`ev/ge_head.out`, `ev/ge_base.out`); the gate's mutation test at head ends `META PASS ... kills every mutant`, rc 0, with the new "pinned eval row covers its own eval" (rc 0) and "second eval in the same file is uncovered" (rc 1) cases and M13 killed (`ev/ge_mut_head.out`) |
| F047-1 reason row matched any rc 3 | yes | head self-test against the base runner: 246/6 (11b own-token case and five 11c checks fail); head GREEN 252/0 (`ev/fs_red.out`, `ev/fs_green.out`). The author's GREEN has 253 checks; the one extra is "P8: js unit runs under node", which needs node on PATH and is not on `/usr/bin:/bin` here, so the difference is environmental |
| F047-2 no stale-row check | yes, with a gap | `--check-known-open` exists and works on a checkpointed DB; WAL gap F047-3 |
| T-1, T-2 tracker | yes | `workable-items validate`: OK, 121 items; `diff`: in sync, 121 vs 121; 28 cited evidence paths for CON-108 and later all resolve (`ev/trk_validate.out`, `ev/trk_diff.out`) |
| P-1 missing `--sync-guide` | yes | rehearsed at head 351fe277: after step 1 two problems, after `--sync-guide` one (the lock difference) (`ev/prop2_v1.out`, `ev/prop2_v2.out`) |
| P-2 row count | yes | head lock 52 rows, last acceptance `rows=52`, so 52 -> 54 is right; the "IndexError with no arguments" claim reproduced for both helpers (`ev/prop_noarg_*.err`) |

## 3. New findings

Severity is from {critical, important, minor, nit}; layer from §11.4.235(D).

| Id | Severity | Layer | Item | Finding |
|---|---|---|---|---|
| F099-2 | important | source-defect (of the test this item ships) | 6 | C2a's shellcheck leg is a carrier match |
| F099-3 | minor | source-defect (regression of the same test) | 6 | false FAIL when shellcheck is not on PATH |
| F117-1 | minor | test-instrumentation | 1 | two helper mutants survive the unit test |
| F109-4 | minor | test-instrumentation | 2 | the `unstated` branch has no discriminating case |
| N109-1 | nit | process-doc | 2 | comment says the sed reads the reason "the same way the runner reads it" |
| F120-1 | minor | test-instrumentation | 3 | no test sends SIGINT or SIGHUP |
| N120-1..3 | nit | source / test | 3 | small windows, see text |
| F121-1 | minor | test-instrumentation | 4 | the `immutable=1` needle is blind to rows in the WAL |
| F121-2 | minor | test-instrumentation | 4 | the DB fallback fires whenever the consumer DB is absent |
| F113-2 | minor | source-defect (gate) | 10 | the eval pin covers the first physical line only |
| F113-3 | minor | process-doc | 10 | "each eval needs its own row" is false for an identical copy; one live row already covers two statements |
| N113-1 | nit | test-instrumentation | 10 | no indented-eval fixture |
| F047-3 | minor | source-defect (runner) | 11 | `--check-known-open` reads `immutable=1` and misses a closure that is still in the WAL |
| F047-4 | minor | test-instrumentation | 11 | reviewer mutants FM6 (foreign-only token) and FM3 (unreadable DB) survive the self-test |
| N047-1 | nit | process-doc | 11 | the RED count in the commit message does not match a run of the committed test |
| N047-2 | nit | source | 11 | a DB with an `items` table but no `current_location` column raises an uncaught error |

### F099-2 (important): C2a's shellcheck leg matches the pack's configuration, not a finding

`sc_leg = any("SC2086" in e for e in fails)` searches the FAIL entries of the pack output. Every
shellcheck FAIL entry the pack prints also carries its `severity_floor.blocking_info_rules`
configuration, which lists `SC2086`. So the leg is satisfied by the config text (§11.4.201(7)(a),
the thing versus a carrier that mentions it).

Measured:
- In the clean environment the pack's shellcheck check is BLIND (systemd-run finds no user bus,
  `files_linted: 0`), yet C2a passes (`ev/precheck_c2a_sc.json`).
- Mutant: remove the planted SC2086 defect from the fixture. C2a still PASSes, without the bus and
  with `XDG_RUNTIME_DIR` set (with the bus: 2 files linted, 4 findings, none SC2086). Only B2 catches
  the mutant (`ev/ps_mut_nodefect_envi.out`, `ev/ps_mut_nodefect_bus.out`,
  `ev/precheck_c2a_sc_nodefect*.json`).

Fix: match the finding records only (rule code in a finding's own `code` field), and require
`files_linted > 0` before reading an absence or a presence; add the no-defect mutant to the test.

### F099-3 (minor): false FAIL when shellcheck is not on PATH

With `PATH=/usr/bin:/bin` (shellcheck lives in `~/.local/bin` on this host): base rc 0, head rc 1
(`has_lint=NO parse=True shellcheck=False`). The pack itself reports the shellcheck check as PASS with
`mode: skipped` ("shellcheck not found on PATH (11.4.3 honest skip)") (`ev/ps_base_nosc.out`,
`ev/ps_head_nosc.out`, `ev/precheck_c2a_nosc.json`). The full-suite runner passes the caller's PATH
through, so the test is red or green depending on the operator's PATH. Same class as F-PRE-2 and
CON-123 (a tool on PATH decides the verdict). Fix: when the pack reports the shellcheck check as an
honest skip, C2a records the shellcheck leg as SKIP with that reason and requires the parse leg only.

### F117-1 (minor): two `user_bus_env.sh` mutants survive the unit test

- ub_rv1: the derived branch no longer exports `XDG_RUNTIME_DIR`. Unit test 9/0
  (`ev/ub_rv1.out`); the persistent-launch test kills it ("systemctl --user does not answer", rc 1,
  `ev/pl_mut_rv1_unset.out`).
- ub_rv2: `-S` becomes `-e` in the inherited-XDG branch. Unit test 9/0 (`ev/ub_rv2.out`). Whether the
  integration test kills it is UNCONFIRMED (not run).

Fix: a unit case that reads `XDG_RUNTIME_DIR` from a child after sourcing (catches rv1), and a case
with a regular file named `bus` in the inherited directory (catches rv2).

### F109-4 (minor) and N109-1 (nit)

- F109-4: mutant rs_rv1 (`*" "*|unstated)` becomes `*" "*)`) survives the meta-test 12/0 and prints
  `reason=unstated` as if it were a shared reason code (`ev/rsd_rs_rv1.out`). Add a meta-test case where
  every member SKIPs without a reason. Mutant rs_rv2 (toplevel check replaced by `true`) is killed by C6
  (`ev/rsd_rs_rv2.out`).
- N109-1: the sed takes the last "reason" occurrence on the line; the runner's `judge()` takes the
  first (`re.search`). The comment "the same way the runner reads it" is not exact.

### F120-1 (minor) and N120-1..3 (nits)

- F120-1: the TERM path is tested (f3); INT and HUP are not. Mutant noint (INT trap removed) orphans
  the sleep on SIGINT and survives the wiring test (`ev/watch_sig_probe.out`). Add an f3 variant per
  signal. Note that a daemon launched with `nohup` ignores HUP on entry, so a trap on HUP cannot be set
  there (POSIX); the probe launches with default dispositions.
- N120-1: between `sleep "$_iv" &` and `_sup_sleep_pid=$!` a signal finds no pid to kill.
- N120-2: the foreground `sleep 1` fallback is not covered by the stop path.
- N120-3: f3 reads the children list once; a race with the child start is possible (UNCONFIRMED).

Head `test_multitrack_supervisor.sh` RED_MODE=1 7/0 and GREEN 10/0.

### F121-1 (minor): the `immutable=1` needle is blind to rows that are still in the WAL

`test_reopen_rate_red.sh` needle #2 opens `file:...?mode=ro&immutable=1`. `immutable` tells SQLite
the file cannot change, so it ignores the `-wal` file. A colliding row inserted with
`wal_autocheckpoint=0` and the writer still open is seen by a normal read-only reader, but the needle
reports CLEAN and the test rc 0 (`ev/rr_mut_wal_only.out`). After a checkpoint the needle reports HIT,
rc 1 (`ev/rr_mut_wal_after_checkpoint.out`). The tracker DB is in WAL mode. Fix: open with `immutable=1`
only when no non-empty `-wal` exists; otherwise copy the DB and its `-wal` to a temp directory and read
the copy (keeps the working tree free of side files, which is why `immutable` was chosen).

### F121-2 (minor): the standalone-DB fallback fires too broadly

`[ -f "$DB" ] || [ ! -f "$ROOT/constitution/docs/workable_items.db" ] || DB=...` switches to the
canon DB whenever the consumer DB is absent, not only for a standalone canon checkout. A consumer whose
own DB is missing is then checked against the canon's DB without saying so. Print which DB was read,
and switch only when `$ROOT` is the canon itself.

### F113-2 (minor): the eval pin covers the first physical line only

The census walks physical lines and hashes `raw_lines[ln - 1].strip()`. An eval whose argument goes on
to a continuation line is pinned by its first line; the continuation can be edited to evaluate
anything without changing the hash. Fixture: line 2 `eval "A=\$DEMO_E1" \`, line 3
`"B=\$GITHUB_ISSUES_FORCE_PASS"`, row hashed on line 2: gate PASS (`ev/ge_probe_cont.out`). Exposure
today: none of the nine pinned eval lines ends with a backslash (checked, all nine located by hash), so
this is latent. Fix: hash the full logical statement (join continuation lines, and multi-line quoted
arguments) and add the continuation fixture.

### F113-3 (minor, process-doc): one row can cover several statements

The allowlist header says "the row covers that eval statement only and a new or edited eval needs its
own row"; the census docstring says "each eval needs its own row". The census keys rows by
`(var, kind)`, so an identical copy of a reviewed eval in the same file shares the row (fixture
`ev/ge_probe_dup.out`: PASS). Live instance: `scripts/gates/cm_scope_and_image_noworse_anchor_wired.sh`
lines 340 and 348 are identical and covered by one row `<eval>#bea59a1ee0f8`. The risk is low (the text
is the reviewed text), but the documented guarantee is wrong. Either reword ("covers this eval text in
this file") or add the line number to the key.

### N113-1 (nit)

Own mutant: hash the line without `.strip()`. The self-test fixtures have no indentation, so the
mutation test does not kill it; the live gate does (seven rows go UNCOVERED, rc 1,
`ev/ge_nostrip_live.out`; fixture `ev/ge_nostrip_indent.out` rc 1). Add an indented-eval fixture so
the self-test kills it too. The author's mutant M13 is killed (`ev/ge_mut_head.out`).

### F047-3 (minor): `--check-known-open` misses a closure that is still in the WAL

`check_known_open` opens the DB with `mode=ro&immutable=1`. Measured on a copy of the head DB: close
CON-047 (`status='Fixed (→ Fixed.md)'`, `current_location='Fixed'`) with `wal_autocheckpoint=0` and the
writer open; a normal read-only reader sees the closure; `--check-known-open` prints `RESULT:
KNOWN-OPEN`, rc 0. After a checkpoint: `KNOWN-STALE`, rc 1 (`ev/kopen_wal.out.walonly`,
`ev/kopen_wal.out.ckpt`; script `scripts/kopen_wal.py`). The function's contract is "never a clean 0"
on a state it cannot see; this is a clean 0 on a state it did not see (§11.4.201(6) false-null).
Exposure is transient (a writer must hold the WAL open, or crash): a copy of the live DB taken during
this review had an empty `-wal` and both readers agreed (89 items).

### F047-4 (minor): two reviewer mutants survive the full-suite self-test

The head code is correct in both cases; the tests do not cover them.

- FM6: `if ids != {tid}:` becomes `if len(ids) != 1:`. With this mutant, a unit whose only
  `[tracked ...]` token names another item is attributed to the row: a direct call of the real
  `match_known` gives `'ATM-5'` for the log `KF [tracked ATM-6]` under a row for ATM-5. Head gives `''`
  (`ev/fs_fm6_probe.out`). The self-test passes 252/0 (`ev/fs_fm6.out`). This is the F047-1 scenario
  once CON-047's own cases are gone and another item's case remains. 11b has an own-token case, a mixed
  case and an untagged case, but no foreign-only case. Add one.
- FM3: the "cannot read" branch of `check_known_open` returns 0 instead of 2. Self-test 252/0
  (`ev/fs_fm3.out`). On a real non-database file, head exits 2 and the mutant exits 0, printing BLIND
  and then a clean exit (`ev/kopen_bad_head.out`, `ev/kopen_bad_fm3.out`). 11c covers an empty DB and an
  absent DB but not an unreadable one. Add one.

The author's F47a, F47b and F47c are killed (`docs/qa/fixu2_round2/f047/f047_runner_mutants.out`).

### N047-1, N047-2 (nits)

- N047-1: the commit message says "RED 244/1 before the change". Running the committed head test
  against the base runner gives 246/6 (`ev/fs_red.out`): the 11b own-token case and five 11c checks
  fail. The author's number was probably taken before 11c was written; state which test version the
  RED count belongs to.
- N047-2: the BLIND guard catches a missing `items` table, but a table without `current_location` or
  `status` raises an uncaught `sqlite3.OperationalError` inside the loop. It fails closed (non-zero),
  but not with the documented exit 2.

## 4. Class recurrences (§11.4.276(C), (E))

| Class | Members this round | Earlier members | Note |
|---|---|---|---|
| `immutable=1` SQLite reader blind to the WAL | F121-1 (`test_reopen_rate_red.sh:137`), F047-3 (`run_full_suite.py:2913`) | the repo already recorded this lesson: `scripts/codegraph/tests/test_mcp_readonly.sh:28` ("the earlier immutable=1 reader was WAL-blind"); two pre-existing readers remain in `scripts/codegraph/tests/test_resolve1_equiv_real.js:21` and `test_resolve2_probe.js:15` | Both new members were introduced in this round. The fixer should enumerate all four (`git grep -n 'immutable=1'`) and fix or scope out each, per §11.4.276(C). |
| a signal matched through a carrier that mentions it | F099-2 (SC2086 in config text) | F047 / F099 class of round 1 | Same shape as round 1: a match on text that names the thing. |
| a tool on PATH decides the verdict | F099-3 | F-PRE-2 (sqlite3 CLI), CON-123 | The fix for F-PRE-2 removed one member; F099-1 added another. |
| a signal path with no test | F120-1 (INT, HUP) | round-1 F-PRE-1 | TERM is now tested; INT and HUP are not. |

Under §11.4.276(E), two findings that share a class force a structural round only when at least one
of them is non-minor. The WAL class has two minor members, so no structural round is forced. The
carrier class has one important member (F099-2), but only one member this round, so the trigger does
not fire either. I still recommend the fixer handles each class as a class.

## 5. Mutants run by the reviewer

| Mutant | Target | Result | Evidence |
|---|---|---|---|
| ub_rv1, ub_rv2 | `user_bus_env.sh` | both survive the unit test; rv1 killed by the integration test | `ev/ub_rv*.out`, `ev/pl_mut_rv1_unset.out` |
| rs_rv1 | ruler aggregator `unstated` branch | survives 12/0 | `ev/rsd_rs_rv1.out` |
| rs_rv2 | ruler toplevel check | killed 11/1 | `ev/rsd_rs_rv2.out` |
| nokill (author) | wiring test | killed 23/3 | `ev/sw_sw_nokill.out` |
| noint | supervisor INT trap | survives; orphans the sleep on SIGINT | `ev/watch_sig_probe.out` |
| collide, blind (author) | reopen_rate needle | killed, rc 1 each | `ev/rr_mut_collide.out`, `ev/rr_mut_blind.out` |
| wal | reopen_rate needle | survives (CLEAN, rc 0) | `ev/rr_mut_wal_only.out` |
| no-defect | precheck fixture | survives C2a (only B2 catches it) | `ev/ps_mut_nodefect_*.out` |
| noF, nox, w (author) | skill liveness | killed 41/1 each | `ev/sa_mut_*.out` |
| sneak eval | env-read gate | killed at head, survives at base | `ev/ge_sneak_*.out` |
| no-strip | eval hash | killed by the live gate, not by the self-test | `ev/ge_nostrip_*.out` |
| continuation, duplicate | eval pin | not detected (F113-2, F113-3) | `ev/ge_probe_cont.out`, `ev/ge_probe_dup.out` |
| M13 (author) | eval pin per file | killed | `ev/ge_mut_head.out` |
| WAL closure | `--check-known-open` | not detected (F047-3) | `ev/kopen_wal.out.*` |
| FM6 `ids != {tid}` -> `len(ids) != 1` | `match_known` | survives 252/0 (F047-4) | `ev/fs_fm6.out`, `ev/fs_fm6_probe.out` |
| FM3 BLIND-on-unreadable returns 0 | `check_known_open` | survives 252/0 (F047-4) | `ev/fs_fm3.out`, `ev/kopen_bad_*.out` |

## 6. Host safety and test doubles

- Every process I signalled was one I started, checked by cmdline first, and signalled by a single
  pid greater than 1 (§11.4.263). One base-product SIGINT probe timed out and left my own daemon and
  sleep (token 771332216835); I checked both cmdlines and killed each by pid; none remain.
- Pre-existing orphans, NOT mine and NOT touched: 103 `sleep 998721`, `sleep 998722`, `sleep 998723`
  processes, parent `systemd --user` (pid 2441, re-parented), started 2026-11-05 between 16:55 and
  20:19, before this round's commits. Their tokens match the pre-fix wiring test (`99872` + iteration),
  so they look like leftovers of the CON-120 defect itself (UNCONFIRMED). The operator may want to
  remove them; I had no instruction to signal processes I did not start.
- Test doubles (§11.4.289): the wiring test's spawn legs use a mock claude (pre-existing, unit-class);
  the f2/f3 orphan evidence uses a real supervisor daemon. The env-read gate fixtures and the full-suite
  11b/11c fixtures are gate-logic fixtures (§11.4.289(C)(2)); none of them is cited as live evidence.
  `fake_ollama.py` stays registered as excluded unit-class.
- Deletes used `safe_rm_rf`; `HOME` was never reassigned in my shell (child processes got a scratch
  `HOME` through `env -i`).

## 7. What I did not re-run

- The real ruler suite under the clean environment: I read the author's evidence
  (`docs/qa/fixu2_round2/f109/ruler_suite_envi.out`, TOTAL=21 PASS=19 FAIL=0 SKIP=2) but did not re-run
  it, because the host load was high (load average about 20 on 16 CPUs).
- The ub_rv2 mutant against the integration test.
- Step 4 of the lock proposal with a rehearsal roster (the author did it; steps 1 to 3 reproduce at the
  final head).

## 8. Summary for the conductor

- Land items 1 to 5 and 7 to 14 (GO or GO-with-follow-ups); register the follow-ups listed in section 3.
- Do not count CON-099 F099-1 closed: fix F099-2 and F099-3 in the same test (match finding records,
  require files_linted > 0, honour the pack's honest skip), then re-review that slice.
- 6ec2a72b sits in the middle of the linear branch, so the later GO commits cannot land without it.
  Two ways that keep `main` honest (§11.4.288, §11.4.113, never a history rewrite): add the F099-2 /
  F099-3 fix as a further commit on the vehicle and land after its re-review, or land the branch
  together with a commit that reverts 6ec2a72b, then redo F099-1. Landing 6ec2a72b alone as is would
  make `test_precheck_slicer_red.sh` red wherever shellcheck is not on PATH (F099-3).
- Treat the `immutable=1` WAL blindness as a class (F121-1, F047-3 and the two codegraph readers).
