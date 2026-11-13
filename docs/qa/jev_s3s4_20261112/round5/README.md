# Jev S3/S4 round 5 (CON-299): structural fixes for the independent review of `da7d97da` (NO-GO, R4-1 to R4-5, nits N1 and N2, surviving mutants R4M2 and R4M12)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | evidence (CON-299, In progress; no GO claimed) |
| Evidence class | gate-logic only (stub llmctl, stub curl, fixture records, tripwires; §11.4.289(C)(2)). Nothing here is live evidence. |

Round 5 is the last round of `R_max` 5 (§11.4.276), run as a structural round (§11.4.276(E)) by a fresh fixer. The
capacity model shared by the producer and its stub was re-derived from the pinned llmctl source first (`ground_truth.md`,
§11.4.276(B)); every fix was then written test-first: each new or changed test ran against the round-4 code (RED) before
it ran against the round-5 code (GREEN). Every run was hermetic: `env -i`, `PATH=/usr/bin:/bin` (plus the test's own stub
directories), a fresh temporary `HOME`, no key variables, `JEV_HOSTED_PROBE=0`, `GIT_SSH_COMMAND=/bin/false`. No real
`llmctl`, `claude-providers`, `systemctl`, hosted endpoint, network or forge call was made, and nothing was pushed.

Path note (N2): every evidence file of this pack has the operator home directory written as `<HOME>` and the user part of
the session temp path as `-HOME-`. The round-4 files and the earlier `t3*`/`t4*` runs were rewritten the same way in this
round (971 + 319 replacements in 27 files, no other byte changed); `../SHA256SUMS` was regenerated for the files it lists.

## RED then GREEN

| Suite | Round-4 code (RED) | Round-5 code (GREEN) | Log |
|---|---|---|---|
| test_s4_placement.sh, P1 to P48 (real-shape stub) | 205 pass / 48 fail (`da7d97da` worktree, round-5 stub and test) | see the final row | `red_s4.txt` |
| test_s4_placement.sh, P49 (status shows `starting`) | 253 / 1 (round-4 `jev-status.sh`) | see the final row | `red_s4_p49.txt` |
| test_s4_placement.sh, P50 (held degraded set leaves the cache) | 258 / 1 (round-5 producer before the P50 fix) | 259 / 0 | `red_s4_p50.txt`, `green_s4.txt` |
| test_jev_status_health.sh, S10 (wrapper list) | 89 / 21 (round-4 matcher via `S8_LIB_UNDER_TEST`) | 110 / 0 | `red_health.txt`, `green_health.txt` |
| test_tab_fields.sh, F6 (no TAB read site) | 14 / 1 (`JEV_TAB_TREE_UNDER_TEST` = round-4 tree) | 15 / 0 | `red_tab.txt`, `green_tab.txt` |
| test_no_real_tools.sh (new) | 4 / 4 (`NRT_SUITE_DIR` = round-4 `tests/jev`) | 8 / 0 | `red_no_real_tools.txt`, `green_no_real_tools.txt` |

## Findings

| id | status | what changed | test |
|---|---|---|---|
| R4-2 | FIXED (gate-logic) | The capacity model was re-derived from the pinned llmctl (`ground_truth.md`): a unit's status is only `ok` or `degraded`; a running profile has verdict `running`, `threads` 0 and is judged by its OWN unit (owner `self`, tenant-keyed profile). The stub `tests/jev/fixtures/bin-place/llmctl` now builds exactly that answer (pressure reasons on every unit, exit 75 / 3 / 0, `PLACE_GONE` for a crashed unit); `jev-place.sh` classifies every candidate into one instance state `ok` / `degraded` / `absent` / `unknown` (`inst_state`). | S4 P1 to P48 against the real-shape stub (RED 48) |
| R4-1 | FIXED | One stop helper: every `llmctl stop` runs through `do_stop` -> `finish_stop_locked`, which drops the set and normalises the endpoint cache (`cache_normalize`): the single `llmctl-local` entry names a held, routable set or is re-pointed or dropped. Round 5 also found (P50) that a HELD set degraded in the current answer stayed in the cache on the refused path; `plan_locked` now normalises against the not-ok list before it returns (§11.4.291(D)(1)). | S4 P27 to P35, P50; mutants M01, M03, M16, M19 |
| R4-3 | FIXED | No llmctl call runs under the lease lock: capacity, candidates and the gateway URL are read before the lock; a set needing a stop or start is marked (`stopping` / `starting`) under the lock, the call runs unlocked, the result is recorded under the lock. The stub records any call made while the caller holds the lock file open (`LOCKHELD`). `jev-status.sh` shows the `starting` mark. | S4 P38 to P49 (P48 counts LOCKHELD over the whole file, with a control needle); mutant M04, M15 |
| R4-4 | FIXED | The wiring matcher follows a closed list of wrappers (env, exec, command, nice, nohup, time, timeout, sh/bash/zsh/dash with an option cluster containing `c`); `command -v`/`-V` and interpreter noexec never count; the gate message names the recognised forms. | health S10; mutants M02 (R4M12 shape), M10 to M12 |
| R4-5 | FIXED (gate-logic) | `test_review_fixes_r5.sh` reaches a real llmctl only through an explicit `REAL_LLMCTL_BIN`, else an honest SKIP. New `test_no_real_tools.sh`: a static scan of every Jev test (comment lines excluded, two control needles) and a dynamic run of `test_review_fixes_r5.sh` under a decoy user database (a `getent` stub mapping the uid to a decoy home) with tripwires at every real-tool location and on PATH (control: a lookup through the decoy user database does fire). | `test_no_real_tools.sh`; mutant M14 |
| N1 | FIXED | `register.sh` read two rows with `IFS=TAB` (the round-4 entry claimed every site was converted). With today's producers no shift is reachable (two fields, the first never empty); both sites now read `\x1f`, and F6 keeps the convention for every Jev read site. | tab F6; mutant M13 |
| N2 | FIXED | The operator home path is gone from the evidence pack (see the path note). | a recursive search of the pack for the operator's user name: 0 files |

Instruments found broken while testing (each caught by a control or by RED, fixed before use): the stub's jq bound `.key`
on an array (exit 5); the stub and the producer used `(.x.ok // true) == false`, which never fires because `false // true`
is `true` (P47 and the pressure scenarios caught it); a single-file `grep -n` omits the file name, so the comment filter of
the static scans was blind for one file (the planted-file control caught it; the scans use `-H`); a test edit dropped the
final `finish`, so S4 exited 0 with a FAIL (caught by the missing summary line, restored). The mutant M02 survived the
first S10 table: an `-lc` script that is only the gate path also passes the plain file-operand check, so two multi-word
`-lc`/`-ec` rows and two unwired `-lc`/`-ec` rows were added.

## Mutants

19 mutants, applied one at a time (exact-once text replacement) to a copy of the final tree by a scratch driver
(`mutants_r5.py`, copied here as `mutants/mutants_r5.py`; results in `mutants/mutants.tsv`), each target test run hermetically, the file restored afterwards (the copy compared equal to the tree after the
pass). Killed = the test exits non-zero with at least one FAIL. Per-mutant output: `mutants/<id>.out`.

| id | target | test | pass / fail | verdict |
|---|---|---|---|---|
| M01-R4M2 (the reviewer's R4M2 shape: keep the cache entry while ANY set is routable) | jev-place.sh | S4 | 258 / 1 | KILLED |
| M02-R4M12 (the reviewer's R4M12 shape: recurse only on an exact `-c`) | lib_decide.sh | health | 106 / 4 | KILLED |
| M03 single stop helper: no cache normalise after a successful stop | jev-place.sh | S4 | 259 / 0 | EQUIVALENT (probe below) |
| M04 single stop helper: `llmctl stop` runs with the lease lock open | jev-place.sh | S4 | 258 / 1 | KILLED |
| M05 real-shape stub: a started unit reports status `running` | stub llmctl | S4 | 236 / 23 | KILLED |
| M06 real-shape stub: a running profile keeps its `fits` verdict | stub llmctl | S4 | 207 / 52 | KILLED |
| M07 measurement check with `// true` (never fires) | jev-place.sh | S4 | 258 / 1 | KILLED |
| M08 real-shape stub: a crashed unit (`PLACE_GONE`) is still reported | stub llmctl | S4 | 247 / 12 | KILLED |
| M09 a degraded own unit is treated as ok | jev-place.sh | S4 | 226 / 33 | KILLED |
| M10 matcher: `bash -n` counts as running the gate | lib_decide.sh | health | 107 / 3 | KILLED |
| M11 matcher: `command -v` counts as running the gate | lib_decide.sh | health | 108 / 2 | KILLED |
| M12 matcher: `timeout` does not skip its DURATION | lib_decide.sh | health | 105 / 5 | KILLED |
| M13 register.sh reads the MCP mode rows with IFS=TAB again | register.sh | tab | 14 / 1 | KILLED |
| M14 test_review_fixes_r5.sh looks llmctl up through the user database again | test_review_fixes_r5.sh | no_real_tools | 4 / 4 | KILLED |
| M15 jev-status hides the `starting` mark | jev-status.sh | S4 | 258 / 1 | KILLED |
| M16 cache_normalize ignores the not-ok profile list | jev-place.sh | S4 | 258 / 1 | KILLED |
| M17 RLIMIT_NPROC headroom below the start threads is ignored | jev-place.sh | S4 | 258 / 1 | KILLED |
| M18 another tenant's unit of the same profile counts as this user's own | jev-place.sh | S4 | 258 / 1 | KILLED |
| M19 P50 fix removed: a held degraded set stays in the cache | jev-place.sh | S4 | 258 / 1 | KILLED |

Totals: 19 mutants, 18 KILLED, 1 EQUIVALENT (M03), 0 SURVIVED.

M03 probe (`probe_m03.txt`): an instrumented copy of the final `jev-place.sh` writes a line every time `do_stop` is
entered, and a second line when the endpoint cache at that moment still names the set being stopped. On the final code
the S4 suite entered `do_stop` 29 times and the cache named the stopped set 0 times (259 / 0): every path that marks a set
`stopping` has already normalised the cache, so the normalise after a successful stop finds nothing to drop for that set.
Control needle: the same instrumented copy with the release-path `cache_normalize` removed entered `do_stop` 29 times and
found the stopped set in the cache 9 times (257 / 2), so the probe can see the state it reports absent. The post-stop
normalise stays as defence in depth; the equivalence holds for the states the S4 suite reaches, not for every possible
state file.

## Final checks

All on the final tree, hermetic as above, with a guard directory first on PATH whose `curl`, `wget`, `llmctl`,
`claude-providers`, `claude` and `systemctl` refuse (exit 97) and record the call.

| check | result | log |
|---|---|---|
| `tests/jev/run_all.sh` | ran 35, failed 0, rc 0 | `run_all.txt` |
| `tests/jev/test_gate_pairs.sh`, no keys | PASS (4 pairs GREEN+RED), rc 0 | `gate_pairs_nokeys.txt` |
| `tests/jev/test_gate_pairs.sh`, FAKE keys exported and a fake keys file (`JEV_HOSTED_PROBE=0`, unlike round 4) | PASS (4 pairs GREEN+RED), rc 0; 0 fake key values in any output | `gate_pairs_fakekeys.txt` |
| the four `cm_jev_*_mutation_test.sh` (bootstrap_idempotent, detection, token_reduction, wiring) | PASS each, rc 0 | `gate_*_mutation.txt` |
| `scripts/run_full_suite.sh --verify-manifest` | first run MANIFEST-MISMATCH (rc 3: the guide census was stale after the new `test_no_real_tools.sh` row); `--sync-guide` (rc 0) rewrote the census line; re-run MANIFEST-OK (910 rows) | `verify_manifest.txt`, `sync_guide.txt` |
| `scripts/gates/cm_gate_ledger_ratchet.sh` | PASS (unimplemented 394, baseline 394) | `gate_ledger_ratchet.txt` |
| shellcheck, changed shell files | no new code against `da7d97da` (same codes and counts per file); the new test only SC1091, like every sibling run from the repository root | `shellcheck_r5.txt`  **Corrected in round 6 (review R5-9, §11.4.6):** this row is FALSE for `tests/jev/test_s4_placement.sh` (at `da7d97da`: SC1091×1 SC2012×2 SC2015×7 SC2329×3; at the round-5 head: SC1091×1 SC2015×10 SC2016×4 SC2329×3); the comparison was taken against the wrong tree. The per-file delta against the true base `02c10935` is `../round6/shellcheck_delta_vs_02c10935.tsv`. |
| evidence pack scrub | 27 changed files of the pack equal their `da7d97da` text with the two path replacements applied; `SHA256SUMS` checks | `final_checks_summary.txt` |

Guard calls during the final checks: 6, all refused. Attributed by re-running each gate mutation test with its own guard
log: `cm_jev_bootstrap_idempotent_mutation_test.sh` calls `curl --version` once (its mutation I puts the ambient PATH
first on purpose, to prove the gate then reports a blind guard), and `cm_jev_detection_mutation_test.sh` runs the PATH
`llmctl decide status --json` once (one leg runs the gate with `PATH="$SBX/nbin:$PATH"`); the other four calls
are, by subtraction, the two `test_gate_pairs.sh` runs (one of each per run; UNCONFIRMED: not re-run with a separate
log). See "Not done".

## Not done / UNCONFIRMED

- The pinned llmctl was NOT run; the capacity model is read from source (`ground_truth.md`), so the stub's shape is
  gate-logic ground truth, not a captured live answer.
- R4-5: the round-4 review run executed a real llmctl (`require-validated -- no-such-profile-r5` and
  `require-validated no-such-profile-r5`) from the operator's catalogizer checkout. Whether that wrote any llmctl state,
  evidence-log line or validation record is UNCONFIRMED; it was not checked here (the operator's llmctl state was not
  read). A read-only check for the operator: list the modification times of the llmctl state and config directories
  and search the llmctl evidence log for `no-such-profile-r5` (paths per the llmctl documentation).
- Open member of the R4-5 class, NOT fixed in this round (found by the final checks above): the gate mutation test
  `scripts/gates/cm_jev_detection_mutation_test.sh` (and, inferred, `tests/jev/test_gate_pairs.sh`) runs
  `cm_jev_detection.sh` with the caller's PATH after a fixture directory, and the gate by design consults the `llmctl`
  on PATH (`decide status --json`, a read call). On a host with a real llmctl on PATH that call reaches the real tool.
  Both files are unchanged since the base `02c10935`; this round's static scan covers `tests/jev/*.sh` only. Proposed
  follow-up: give every gate-test leg an explicit stub or absent `JEV_LLMCTL_BIN` (the gate's guarded override) or a
  PATH without the caller's directories, and widen the `test_no_real_tools.sh` scan and decoy run to
  `scripts/gates/cm_jev*_mutation_test.sh` and `test_gate_pairs.sh`. The `curl --version` call of mutation I is
  deliberate (it proves the blind-guard verdict) and runs only `--version`.
- G1 (out of scope, the destructive-path guard was not changed): two Write calls of `test_s4_placement.sh` were refused
  as class U because the payload held `eval "$wp"` in one function and `rm -f -- "$STUB_LOG/running.$1"` (a sandbox
  file) in another. The test now uses the stub's `PLACE_GONE` flag instead of deleting. Follow-up item text: "the
  class-U rule of guard-destructive-paths.py refuses a whole payload when an `eval` of a variable and any forced or
  recursive delete appear anywhere in it, even in different functions and with a sandbox-derived target; scope the rule
  to the same simple command or function, or exempt a delete provably under the payload's sandbox variable, and add both
  payload shapes as golden-FALSE fixtures to test_guard_bypasses.py (needs the operator's consent, §11.4.287)".
