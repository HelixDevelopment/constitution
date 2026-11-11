# Review: fixu round 3, CON-099 slice only (§11.4.209 independent re-review)

| Field | Value |
|---|---|
| Date | 2026-11-06 |
| Reviewer | independent subagent, model `claude-opus-5-5` (Opus). The dispatch asked for `xhigh`; the effort cannot be read from inside the agent (§11.4.231(F.2)), so it is not claimed |
| Input | `S/fixu3/fixu3.bundle`, sha256 `1e1c65198e2e46f8bfaf7de9b94b5c869b0312118d4e023b24e85d580521fe64` (re-measured, matches), incremental over `351fe277` |
| Head | `5dc6097efdbfad5b6c893f408cfbe0d290bf240c` (verified in the scratch clone) |
| Commits in scope | `ec047648` (test fix for F099-2 and F099-3, manifest row, harness), `5dc6097e` (tracker: CON-124..CON-131, CON-099 note) |
| Prior review | `S/review_fixu2.md` (F099-2 important, F099-3 minor) |
| Evidence dir | `S/rev_fixu3/ev/` (kept); reviewer scripts `S/rev_fixu3/scripts/` (kept) |

`S` = `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad`

## 1. Verdict

| Unit | Verdict | Open findings |
|---|---|---|
| `ec047648`, CON-099 test fix (F099-2, F099-3) | **GO-with-follow-ups** | F099-4, F099-5, F099-6, F099-8 (minor, test-instrumentation), F099-7 (minor, process-doc), nits N099-1..N099-6 |
| `ec047648`, manifest row + guide census | GO | none (one pre-existing stale note, N099-7) |
| `5dc6097e`, tracker | GO | nits N099-8..N099-10 |

Both prior findings are closed. I checked each one RED then GREEN on the same command (section 2). Every new finding is minor-class under §11.4.276(G.2). Each one is test-instrumentation or process-doc, and none of them breaks the proof that this batch's fix is correct (reasoning for F099-4 in section 5). So the slice ends at **GO-with-follow-ups**: each finding becomes a tracked follow-up item, and the slice is not reported as a zero-finding GO.

## 2. Closure of F099-2 and F099-3

The same command (the author's harness `test_precheck_slicer_c2a_mutants.sh`) runs against three versions of the test, using `C2A_TEST_UNDER`:

| Test version | Result | rc | Evidence |
|---|---|---|---|
| head `ec047648` | ok 5 / NOT ok 0 | 0 | `ev/mut_head.out` |
| `6ec2a72b` (the round-2 version, F099-2/3 present) | ok 1 / NOT ok 4 | 1 | `ev/mut_old_6ec2a72b.out` |
| `19b86795` (earlier) | ok 1 / NOT ok 4 | 1 | `ev/mut_old_19b86795.out` |

My results match the author's (`docs/qa/fixu3_round3/f099/mutants_RED_old_test.out`, `mutants_GREEN.out`).

- **F099-2 (carrier):** closed. The shellcheck leg now reads `evidence.findings[]` where `rule == "SC2086"` and `file == "unquoted_var_gate.sh"`. It also requires `verdict == "FAIL"` and `counts.files_linted` to be an int > 0. Stub S1 has SC2086 in another field and in `advisory_findings` (not in `findings`), and it FAILs C2a. So the config echo no longer satisfies the leg.
- **F099-3 (false FAIL without shellcheck):** closed. With `PATH=/usr/bin:/bin` the test passes with a `SKIP: C2a` line, and the parse leg is still required (R1, P4, S9 below). A `command -v shellcheck` cross-check turns a pack skip into a FAIL when shellcheck IS on PATH (P1, S5). This blocks the skip-abuse route.

## 3. Reviewer scenarios against the shipped test (head)

Driver: `scripts/scen.py`. Each scenario runs a scratch copy of `scripts/fastcycle`. Rows marked "stub" are gate-logic stubs (§11.4.289(C)(2)); every other row runs the real pack. Results: `ev/scen_head.tsv`.

| Scenario | What it does | Expected | Result |
|---|---|---|---|
| R0 | real pack, normal env | PASS | PASS 16/0 |
| R1 | real pack, shellcheck off PATH | SKIP+PASS | SKIP+PASS 15/0 |
| R2 | real pack, no session bus (the full-suite default) | FAIL (blind leg, CON-117) | FAIL `parse=True shellcheck=NO` |
| P1 | pack honest-skips although shellcheck is on PATH (**skip abuse**) | FAIL | FAIL "pack skipped shellcheck although it is on PATH" |
| P2 | SC2086 demoted from blocking to advisory | FAIL | FAIL |
| P3 | parse check never fails | FAIL | FAIL `parse=False` |
| P4 | parse check never fails, shellcheck absent | FAIL | FAIL `parse=False shellcheck=SKIP` |
| **P5** | parse check never fails, plus the comment `# syntax error: ...` on the fixture's `if` line | FAIL | **PASS (carrier, F099-4)** |
| F1 | broken `shellcheck` binary first on PATH (**blind leg**) | FAIL | FAIL |
| S1 stub | SC2086 only in another field, and in advisory_findings (**matched in another field**) | FAIL | FAIL |
| S2 stub | SC2086 in the wrong file | FAIL | FAIL |
| S3 stub | `files_linted` 0 with a finding (**files_linted spoof**) | FAIL | FAIL |
| S4 stub | `files_linted` is the string "2" | FAIL | FAIL |
| S5 stub | honest-skip record while shellcheck is on PATH | FAIL | FAIL |
| **S6** stub | parse PASS, but another FAIL entry carries "Syntax error" text | FAIL | **PASS (carrier, F099-4)** |
| S7 stub | good output | PASS | PASS |
| S8 stub | shellcheck verdict PASS with a finding | FAIL | FAIL |
| S9 stub | honest skip, no shellcheck | SKIP+PASS | SKIP+PASS |
| S10 stub | whole-file PASS with no findings, no shellcheck | FAIL | FAIL |

Removed defect: the author's M2 covers this case. I also checked the B2 self-check by hand. With the planted line quoted, `shellcheck -s sh` gives rc 0 and 0 SC2086 lines. The positive needle on the real fixture gives 2 SC2086 lines. So B2 has no carrier: the fixture's comments mention SC2086, but shellcheck does not echo comment lines.

## 4. Reviewer mutants of the test, run through the author's harness

Generator: `scripts/mk_test_mutants.py`. Each replacement must match exactly once, and each one did. Mutant files: `ev/tm/`. Harness runs: `ev/harness_TM*.out`. Scenario kills: `ev/scen_mutants.tsv`.

| Mutant | Change | Author's harness | Killed by (reviewer scenario) | Equivalent on real pack output? |
|---|---|---|---|---|
| TM1 | drop the `command -v` cross-check | **survives 5/0** | P1 (real pack), S5 | no |
| TM2 | drop the file match | **survives 5/0** | S2 (stub only) | yes on today's real pack |
| TM3 | drop the `files_linted > 0` check | **survives 5/0** | S3 (stub only) | yes on today's real pack |
| TM4 | count advisory findings | **survives 5/0** | P2 (real pack), S1 | no |
| TM5 | any PASS counts as SKIP | **survives 5/0** | S10 (stub only) | yes on today's real pack |
| TM6 | drop the verdict check | **survives 5/0** | S8 (stub only) | yes on today's real pack |
| TM7 | a SKIP drops the parse leg | **survives 5/0** | P4 (real pack) | no |
| TM8 | substring match, linted check kept | killed 3/2 | n/a | n/a |

Seven of eight survive the harness. Three of them (TM1, TM4, TM7) are not equivalent: a real pack mutation kills each of them. This is F099-5.

## 5. Findings

Each finding has its §11.4.235(D) layer and its §11.4.276(G.2) severity.

### F099-4 (minor, test-instrumentation): the parse leg is still a carrier match

At `test_precheck_slicer_red.sh:433`:

```
parse_leg = any("syntax error" in e.lower() for e in fails)
```

`fails` is the string form of the evidence of EVERY FAIL check. So the leg is satisfied by any FAIL entry whose text contains the phrase: a shellcheck finding's `text` field, a message, or a fixture comment. It does not need the parse check's own failure for `broken_syntax_gate.sh`. This is the same class as F099-2 (§11.4.201(7)(a), thing vs carrier), now in the sibling leg.

- P5 shows it on the real pack. With the parse check broken and one innocent comment added to the fixture, C2a PASSes.
- S6 shows it with a stub.

Why it is minor and test-instrumentation rather than an important source-defect: on today's real pack output, no other check's evidence carries the phrase. P3 and P4 show that a broken parse check IS caught. So the proof that the CON-099 dash fix works still holds; what is missing is robustness against a future carrier. If the conductor reads this as a source-defect on a proof-of-batch surface, it would not be minor-class. I do not recommend that reading, because of P3 and P4.

**Fix:** select the check whose `check == "parse"`. Require `verdict == "FAIL"`, and require that its `evidence.failures[]` holds an entry with `file == "broken_syntax_gate.sh"` and a case-insensitive "syntax error" message. Add P5 and S6 as harness cases.

### F099-5 (minor, test-instrumentation): the harness does not kill the reviewer's test mutants

Seven of eight reviewer mutants survive (section 4). Under §11.4.276(D), every mutation that survives the reviewer must be adopted and must fail the suite before the next review.

Minimum fix: add real-pack cases P1 (skip with shellcheck on PATH), P2 (SC2086 advisory) and P4 (parse never fails, no shellcheck). These kill TM1, TM4 and TM7. To kill TM2, TM3, TM5 and TM6, add gate-logic stub cases S2, S3, S8 and S10.

### F099-6 (minor, test-instrumentation, §11.4.199(2)): M1, M2 and M4 never prove they reached their precondition

The harness asserts only `FAIL: C2a` plus rc ≠ 0. It never checks that the run reached the state the case is named for.

- **M1 ("blind leg")** blinds the leg indirectly (`env -i`, no bus, relying on open CON-117). I simulated the CON-117 fix (`_runner_env` derives `/run/user/UID`). After that, M1 is no longer blind, C2a passes, and the harness reports a false `FAIL: M1 ... accepted a BLIND shellcheck leg` (4/1, `ev/harness_con117sim.out`). The slicer test itself stays correct, 16/0 (`ev/slicer_con117sim_nobus.out`).
- **When B0 itself fails** (default full-suite isolation, `ev/fsr_head/logs/000001.log`), M1, M2 and M4 are still counted `PASS`. Their FAILs are vacuous there, because the baseline already fails.

**Fix:**
- Blind the leg directly with a gate-logic stub (a `systemd-run` or `shellcheck` stub that fails), and assert `shellcheck=NO` or `files_linted 0` in the output.
- Assert each case's own precondition line.
- When B0 fails, stop the mutant cases, or report them as not-proven instead of ok.

### F099-7 (minor, process-doc): a full-suite verdict changes without a word in the commit, the item note or CON-117

Under the full-suite runner's default isolation (no `XDG_RUNTIME_DIR`, no bus), the results at head are:

- `test_precheck_slicer_red.sh` FAILs (base `351fe277` PASSed it, through the carrier). Evidence: `ev/fsr_head.out`, `ev/fsr_base.out`.
- The new harness FAILs.
- The sibling `test_precheck_shellcheck_red.sh` FAILs (pre-existing).

With `--env-extra XDG_RUNTIME_DIR --env-extra DBUS_SESSION_BUS_ADDRESS`, all three PASS (`ev/fsr_head_bus.out`). The new red is a TRUE red: a blind shellcheck leg is now reported instead of being passed by the config echo, and its cause is the open CON-117. But:

- CON-117's affected list does not name either test.
- Neither the commit message nor the CON-099 note says that the default-runner verdict changes.
- The C2a FAIL message does not say BLIND and does not quote the pack's own skip or error, so the cause takes digging (§11.4.201(5)).

**Fix:** add both tests to CON-117's affected list, record the verdict change in the CON-099 note, and make the C2a FAIL print the shellcheck check's verdict, `files_linted` and any pack error.

### F099-8 (minor, test-instrumentation, host hygiene): an interrupted harness run leaks its temp tree

The harness installs `trap cleanup EXIT` only. Under `sh` (dash), SIGTERM does not run the EXIT trap. Measured: `timeout -s TERM 2` gives rc 124 and leaves `tmp.*/{b0,m1,out}`, 42 MB, after 2 s (`ev/harness_sigterm.out`). A full run copies the 21 MB `scripts/fastcycle` five times. Which signal the full-suite runner sends on its own timeout is UNCONFIRMED (not measured here).

**Fix:** `trap 'cleanup; exit 130' INT; trap 'cleanup; exit 143' TERM` (plus HUP), with a SIGTERM case in the test (compare F120-1 in round 2).

### Nits

- **N099-1:** with shellcheck absent, only M3 runs and the harness exits 0. Consider exit 77 / SKIP with a reason, so a host with no shellcheck does not count as a full harness PASS.
- **N099-2:** `BASEENV` is expanded unquoted, with SC2086 disabled, so it relies on word-splitting. This works for the current values; a value with a space would break it.
- **N099-3:** M2's shellcheck control is negative only. Add the positive needle: the unmodified fixture yields SC2086.
- **N099-4:** the cleanup guard `case $TMP in /*/tmp.*|/*/*.*)` is nearly vacuous, because `*` matches `/` in `case`, so `/*/*.*` matches any absolute path with a dot. Safety actually rests on `mktemp -d` plus `${TMP:?}`, which satisfies §11.4.287(C)(1). §11.4.287(B) prefers `safe_rm_rf`.
- **N099-5:** F099-4's fix should also check that the parse failure names `broken_syntax_gate.sh`, so a parse error in some other file cannot satisfy the leg.
- **N099-6:** under §11.4.276(E)(1), if the conductor counts this as round 3 for CON-099, a recorded convergence assessment is required, and neither the commit nor the CON-099 note has one. F099-4 shows why it matters: it is the same carrier class as F099-2, in the sibling leg. That is exactly what the §11.4.276(C) class inventory exists to catch.

## 6. Class inventory (§11.4.276(C)), done by the reviewer

The class is a substring or carrier match standing in for a structured fact. I grepped every substring and `grep` match in `test_precheck_slicer_red.sh`. The negative needle `zzq_no_such_token_qq` gives 0.

| Line | Match | Carrier risk | Status |
|---|---|---|---|
| 177, 182 | `grep -qF` on the gate's stderr | text from the gate's own argparse/refusal | low, outside this slice |
| 258 (B1) | `grep -qi 'syntax error'` on `sh -n` stderr | `sh -n` prints only its own error | sound |
| 287 (B2) | `grep -q SC2086` on shellcheck stdout | fixture comments mention SC2086, but shellcheck does not echo them (defect-removed run: 0 hits; real: 2) | sound, measured |
| **433** | `"syntax error" in e.lower()` over all FAIL evidence | **yes, F099-4** | **open** |
| 447 | `"not found on PATH" in str(skipped)` | narrow; the cross-check makes abuse fail (P1, S5) | acceptable |
| 566, 582 | `grep -qF "$CHANGE_SHA"` | the SHA is unique | sound |

So 433 is the only open member. Closing it closes the class in this test.

## 7. Manifest row and guide

- The new row `scripts/fastcycle/tests/test_precheck_slicer_c2a_mutants.sh sh member heavy - scripts/fastcycle/tests/run_all.sh` is correct: the tier is heavy and the name contains "mutant".
- It runs inside `run_all.sh`'s loop.
- `--verify-manifest` gives `RESULT: MANIFEST-OK`, census `sh/member=295 total=856`, rc 0 (`ev/verify_manifest_head.out`), and the guide census line matches.
- **N099-7 (pre-existing):** the `run_all.sh` entry note still says "covers 12 heavy member(s)". It was 13 at the base and is 14 now.

## 8. Tracker commit 5dc6097e

- `workable-items validate`: OK, 129 items (`ev/trk_validate.out`).
- `diff`: in sync, 129 vs 129 (`ev/trk_diff.out`).
- `--db-only`: OK (`ev/trk_dbonly.out`).
- db-to-md regenerates `docs/Issues.md` and `docs/Fixed.md` byte-identically (`ev/trk_regen.out`).
- Control needle: a one-line edit of the CON-131 body in a copy is detected as `~ CON-131 body differs`, rc 1 (`ev/trk_diff_needle.out`). The first needle run, without `--fixed`, was refused by the tool. That was my mistake; it is re-run correctly.
- CON-124..CON-131 cover every non-CON-099 finding of review_fixu2 (14 findings, mapped one by one).
- The CON-099 round-3 note is present and accurate, except for what F099-7 asks it to add.
- Nits:
  - **N099-8:** CON-124 cites `scripts/.../test_reopen_rate_red.sh`, an elided path. Give the full path.
  - **N099-9:** the provenance cites untracked scratch reviews. Under §11.4.215, binding review text belongs in the repository; I suggest landing `review_fixu2.md` and this file under `docs/qa/`.
  - **N099-10:** "as for CON-092..123" in the commit message is imprecise. CON-092..CON-107 were re-minted at the CON-031 landing, and CON-108..CON-123 still await re-mint.

## 9. Landing notes (for the conductor, not findings of this slice)

1. **Re-mint required (§11.4.214).** Upstream `github/main` is `2739c26b`, 32 commits ahead of the live checkout's `b939266a`. It already holds `f3751e51`, which owns CON-108..CON-115 with different titles, and `2739c26b` (the excluded lock, 53 rows). So the vehicle's CON-108..CON-131 must be re-minted at landing (CON-116 or the next free id on the landing base), with the old ids recorded in each note. The tracker commit already says the ids will be re-minted.
2. **Merge conflicts.** `git merge-tree` of `github/main` against `fixu3` head reports conflicts in:
   - `docs/Issues.md`
   - `docs/Issues_Summary.md`
   - the full-suite guide census line
   - `docs/workable_items.db` (binary: re-derive it from the DB, never hand-merge)
   - `tests/test_run_full_suite_mutations.sh`

   (`ev/mergetree.out`.) Resolution runs on the §11.4.211 substrate. Regenerate the census and the tracker exports after the merge, and do not pick one side.

## 10. Host safety and disclosures

- No reviewer process is left running (`pgrep -af rev_fixu3`: none). No `/tmp/tmp.*` leak from my runs. The F099-8 leak was produced on purpose inside `S/rev_fixu3/tmp/sigt` and is removed when the clone is retired.
- All deletes used `${VAR:?}`-guarded paths, Python `shutil.rmtree` on paths asserted to sit under the scratch base, or `safe_rm_rf`. `HOME` was never reassigned in my shell: scenarios that needed a clean environment passed an explicit `HOME` to the child through `env`, inside the scratch tree.
- **Disclosure:** I ran `git fetch --dry-run` once on the live checkout. It updated no refs, but it may have written objects under `.git`. Every later upstream fetch went into the scratch clone only. Apart from that, the live checkout was not modified, nothing was committed, and nothing was pushed.

## 11. Not done, or limited

- The full full-suite run was not repeated. I ran the runner on the affected selections, at head with and without bus variables and at base.
- N ≥ 3 determinism repeats (§11.4.50) were not run. The harness at head passed in two separate clean runs (`ev/mut_head.out` 5/0, and the full-suite run with bus variables, `ev/fsr_head_bus.out`). Each scenario row ran once.
- CON-117's fix was simulated in a scratch copy only (`_runner_env` patch). It is not a reviewed fix.
- Only the CON-099 slice and the tracker and manifest rows were reviewed. The other ten tests of CON-099 are untouched by this round and were not re-reviewed.
