# CON-234 round 13 (structural): the network-spawn gate becomes a byte pin plus a positive-shape analyser

| Field | Value |
|---|---|
| Item | CON-234 (vehicle fix227, round 13) |
| Base | `dd095a3f` (round 12, review NO-GO) |
| Date | 2026-11-13 |
| Status | PROVISIONAL (§11.4.290): the independent round-13 review is owed |
| Rounds | past `R_max`, under the standing operator decision of 2026-11-11 (continue until GO; each round past 5 structural, with a fresh fixer and a fresh reviewer); fresh fixer instance |
| Review answered | the round-12 review, NO-GO: F1 critical source-defect (32 oracle-confirmed bypasses), F2 important test-instrumentation (8 of 11 narrowing mutants survived), F3 important process-doc (stated properties the gate does not have); observations O1 to O3. Reviewer file `review_fix227_r12.md`, sha256 `18876cf4e1b27c29af188aaf8083e1cc66f604863332650e025367db9e12c2ac` |
| Release scripts changed | none (the four release files are byte-identical to `dd095a3f`) |

Round 11 decided with regular expressions, round 12 with a parser whose decisions were deny-lists. Both failed
review on the same class: a list of what is bad, over an open language, misses members, and each review found
more. Under §11.4.250 and §11.4.276(E)(3) this round adds no list entries. It changes what the gate decides.

## 1. What changed

- **Layer 1, the byte pin** (`tests/release/netgate_pin.tsv`, 1468 rows: 4 F, 1177 L, 128 S, 14 P, 145 N). `netgate
  --pin TABLE` first compares the bytes of every release file with the reviewed bytes: file sha256 and line count,
  every line's census key and exact-byte sha16, every invocation site with its class, every awk and sed program
  text, every name a script writes. Any unreviewed change is a finding, whatever it is (a trailing space included).
  `netgate` without `--pin` is a usage error (rc 2). `pin-regen` writes the table and refuses (rc 1, nothing written)
  while the analyser has a finding; `pin-diff` prints the line-key diff (never script text) and exits 1 on a
  difference. Part 2d of the channel suite checks that the committed table is exactly what `pin-regen` writes for the
  committed files, in either argument order, with an empty PATH.
- **Layer 2, the positive-shape analyser** (`Parser`, `Gate`). It accepts only what the release files use, and
  every rule names what is allowed: a closed construct set (the parser refuses here-documents, `&`, `coproc`,
  `[[ ]]` outside a closed grammar, arithmetic outside a closed grammar, assigning parameter operators, and the
  rest listed in `threat_model.md` section 3); 25 builtins, each with its own option grammar in `Gate.builtin`;
  interpreters and exec wrappers only when the parsed words equal an entry of `ALLOW_EXEC`; `source` only in the
  exact raw forms of `SOURCE_OK`; awk and sed only when the sha256 of the program is on the P list of the pin; `sort
  -V` only; `sqlite3` only with `-safe` as the first argument; a function defined once, at the top level, before
  every call that can reach it; every written name, in every form the parser records, through one check
  (`check_writes`), which refuses the 38 names of `DANGER_NAMES` (`PATH`, `BASH_ENV`, `ENV`, `CDPATH`, `SHELLOPTS`,
  `BASHOPTS` and the rest; `IFS` only with a value of `IFS_VALUES`), the `LD_` and `GCONV_` prefixes and every name
  off the N list of the pin. The analyser runs alone (`--analyser-only`) on fixtures and mutated copies.
- **Layer 3, the runtime recorders** of the suites, unchanged: every program a test run starts is recorded with its
  arguments and environment. A network namespace was considered and is not available (`threat_model.md` section 4).
- **O2:** a finding, a lint finding and `pin-diff` name a line by its census key (`| key=` followed by 8 hex
  digits), never by its text. Case C53 of the tag, derive and publish suites now expects
  `... | key=483e5249` (the key of `command -p git status`); the channel suite checks the key form and that a fake
  marker on the refused line is not printed, for netgate and for both lint finding kinds.
- **Controls:** 274 control needles in `tests/release/netgate_controls.jsonl` (262 that must be a finding, 12 that
  must pass), in 14 classes (`class_inventory.md`). Section 3.
- **F3:** dated correction notes in `../round12/README.md`, `../round12/threat_model.md` and
  `../round12/class_inventory.md`, and in the header comment of `channel_census.py` (section 6).

The threat model, the layers and what each proves, and the residuals are in `threat_model.md`.

## 2. RED and GREEN

The oracle (`tools/oracle13.py`, adapted from the round-12 reviewer's `oracle.py`; only the gate command line
differs) runs each fixture through the gate with an empty PATH and with a normal PATH, and through real bash 5.3 in
a sandbox where every network program is a local recorder (no network) and, for the gawk cases, a loopback
listener waits. A fixture is a **BYPASS** when the gate returns rc 0 and bash ran a network program without
`rc_net` or the listener got a connection. RED is the round-12 gate (`dd095a3f`), GREEN the round-13 gate of this
commit, with `--pin tests/release/netgate_pin.tsv --analyser-only` (fixtures are not on the pin, so layer 1 alone
would refuse every one of them).

| Fixtures | Rows | Round-12 gate `dd095a3f` (RED) | Round-13 gate (GREEN) |
|---|---|---|---|
| the round-12 reviewer, batch 1 (`cases_r1.json`) | 26 | 22 BYPASS, 2 CAUGHT, 2 NO-LEAK | 25 CAUGHT, 1 NO-LEAK |
| the round-12 reviewer, batch 2 (`cases_r2.json`, `cases_r2b.json`) | 22 | 12 BYPASS, 9 CAUGHT, 1 NO-LEAK | 22 CAUGHT |
| the fixer, round 13 (`cases_r13_all.json`; RED from the five part files) | 85 | 8 BYPASS, 41 CAUGHT, 36 NO-LEAK | 85 CAUGHT |
| all | 133 | 42 BYPASS, 52 CAUGHT, 39 NO-LEAK | 132 CAUGHT, 1 NO-LEAK |

The 48 reviewer rows are 45 fixtures (R06, R07 and R14 are in both of its batches). Round-13 fixtures the round-12 gate passes with a leak or a loopback connection: O01_old_arith_PATH, O02_for_arith_PATH, O09_cond_eq_PATH, O10_cond_v_subscript, O20_arith_name_holds_assignment, O43_subscript_assigns_PATH, O58_fd_name_written_text, O62_awk_pinned_operand_inet.

- The reviewer's 32 bypasses (F1, `oracle/rev_names.txt`): every one is CAUGHT by the round-13 gate.
- The round-12 gate also passes 8 of the fixer's own fixtures with a leak or a loopback connection (O01, O02, O09,
  O10, O20, O43; O58, O62): new members of the classes the review named. All CAUGHT in round 13.
- The NO-LEAK rows of the round-12 gate are fixtures where bash ran no network program in the sandbox (for example
  state changes whose effect needs a second program the fixture does not start). The round-13 gate refuses them
  all: the positive shape refuses them for being outside the grammar, not for being known bad.
- The single NO-LEAK row of round 13 is the reviewer's negative control R92 (a clean script): gate rc 0, no leak.
- Every fixture gives the same gate rc with both PATHs (`gate_rc=x/y` in the tables, equal in every row).

Raw results: `oracle/<gate>.<cases>.txt` (one line per fixture: verdict, gate rc empty/normal PATH, bash rc, leak
count, rc_net count, loopback, first finding) and the fixture bodies in `tools/cases_*.json`.

## 3. Controls, host independence and the class inventory

- `tests/release/netgate_controls.jsonl`, 274 controls: the round-12 reviewer's 45 oracle fixtures (its 48 oracle
  cases; R06, R07 and R14 are in both of its batches) and 12 discriminating fixtures, kept byte for byte except that the oracle placeholders `@PORT@` and `@SB@` of 5 of them (R19, R20, R21, R22, R31) are filled with fixed values (port 9, `/nonexistent/sb`; round-13 review F4); the round-11
  reviewer's 50 fixtures and the 88 controls of the round-12 class inventory, kept from round 12 (7 of the 138 are
  round-12 pass shapes that the positive shape now refuses, renamed `NAME_r12shape`); 72 own fixtures of this round
  (`fixer-r13`: O01-O70, O72 and O73; O71, the same sort property with more options, is an oracle case only); and 7
  controls of the shapes the real scripts use. Part 2c of `tests/release/test_channel_census.sh` runs every one with
  `PATH=/nonexistent` through `netgate --pin PIN --analyser-only` and checks the finding text or the pass: 262
  findings, 12 passes.
- `class_inventory.md` (generated by `make_class_inventory.py`, which exits 1 when a control has no class or two):
  14 classes. Every member of the reviewer's 32 fixtures and of the bodies behind the 8 surviving narrowing
  mutants is a control.
- Golden-FALSE: the four real release files give `NETGATE layer=pin+analyser invocations=128
  network_through_rc_net=51 findings=0`, and `--sites` prints 128 SITE lines, every one in a class of the closed
  set, none a finding. With an empty PATH and with a normal PATH the output is byte-identical
  (`golden_netgate_normalpath.txt`, `golden_netgate_emptypath.txt`; the lint: `lint_normalpath.txt`, `lint_emptypath.txt`).
- The lint (`CENSUS invocations=128 rows=124 secret_lines=13 findings=0`) gives the same result with both PATHs.

## 4. The six suites, twice

| Suite | Run 1 | Run 2 | Same verdict lines (digits normalised) |
|---|---|---|---|
| redact (`test_redact_cut.sh`) | rc 0, pass=435 fail=0, 35s | rc 0, pass=435 fail=0, 58s | yes |
| channel (`test_channel_census.sh`) | rc 0, pass=89 fail=0, 94s | rc 0, pass=89 fail=0, 107s | yes |
| derive (`test_derive_release_facts.sh`) | rc 0, pass=109 fail=0, 80s | rc 0, pass=109 fail=0, 71s | yes |
| publish (`test_publish_gitea.sh`) | rc 0, pass=167 fail=0, 53s | rc 0, pass=167 fail=0, 44s | yes |
| tag (`test_tag_and_release.sh`) | rc 0, pass=310 fail=0, 349s | rc 0, pass=310 fail=0, 268s | yes |
| render (`test_render_release_entry.sh`) | rc 0, pass=19 fail=0, 2s | rc 0, pass=19 fail=0, 2s | yes |

Outputs: `green_<suite>_run1.txt`, `green_<suite>_run2.txt`; summaries `suites_run1.tsv`, `suites_run2.tsv` (rc, seconds, PASS and FAIL counts, RESULT line).

Each run is one sequential pass in a hermetic environment (`env -i`, a fixed PATH with the host's Android SDK
sqlite3 3.50.6, a fresh TMPDIR per suite), under `systemd-run --user --scope -p TasksMax=3000` and `nice -n 10`.
The last column compares the sorted PASS/FAIL/SKIP lines of the two runs with every digit replaced.

## 5. Mutants

The harness `tests/release/test_release_tooling_mutations.sh` carries the round-13 gate block generated by
`tools/mut13.py emit` from one spec (never edited by hand): 104 gate mutants plus one recorded equivalent (PN13).
`STALE_ONLY=1`: 383 apply, 0 stale (`mutations_stale_only_round13.txt`). Each is an `mp` line, so it counts as killed only when its suite fails AND a FAIL
line matches the property it targets.

| Group | Mutants | What they do |
|---|---|---|
| Round-12 gate mutants whose text is unchanged | GN1-GN4, NR1, NR6, NR7, NR10, NR11, NR14, NR17, NR28, NR30 | kept with their round-12 text |
| Round-12 gate mutants re-applied to the round-13 rule that does the same job | GN5, GN6, NR2-NR5, NR8, NR9, NR12, NR13, NR15, NR16, NR18-NR27, NR23b, NR29, NR32, NR33 | the rule changed shape; the property is the same |
| The round-12 reviewer's MR5-MR10, re-applied | MR5x, MR6x, MR7x, MR8x, MR10x, MR10y | each re-applied to the round-13 rule; MR1, MR2, MR3 and MR9 are NR27, NR26, NR23 and NR8 (compgen, mapfile, declare -n, sort long options); MR4 is NR22 |
| The reviewer's MS1, verbatim | MS1 | `-safe` swallowed as the value of `-separator`; killed by the derive suite's C53 (`-safe is not the first argument`), no longer only incidentally by the line-key table |
| Layer 1 | PN1-PN19 (PN13 recorded equivalent) | the pin: trailing space, extra file, missing file, removed or unknown rows, unreadable pin, the regeneration check |
| Layer 2 | AN1-AN42 (AN16 and AN19 not used) | one per analyser rule, each killed by its control needle; AN40-AN42 by the O2 checks |

**Targeted pre-run.** Before the commit every one of the 104 was run alone against its suite in the harness layout
(`tools/prescreen13.sh`, three at a time), on the committed tree: 104 of 104 killed by a FAIL line of their property. Results per mutant, with the first FAIL line:
`mutants_targeted_r13.tsv`; the table with every row: `mutants.md`.

**PN13, recorded equivalent.** PN13 removes the second check in `pin_regen` for a written name of `DANGER_NAMES`.
The analyser reports every such write before `pin_regen` reaches that check, so the check cannot change the result.
The probe `tools/pn13_probe.py` writes one fixture per dangerous name (`PATH`, `BASH_ENV`, `ENV`, `LD_PRELOAD`,
`LD_LIBRARY_PATH`, `GCONV_PATH`, `CDPATH`, `EXECIGNORE`, `BASHOPTS`, and `IFS` with a value off `IFS_VALUES`) and
runs `pin-regen` with the gate and with the mutant, with an empty PATH: 10 of 10 pairs give the same `REFUSED` line with rc 1, no table written (`pn13_probe.txt`).

**NR8 and the control O70.** In the first pre-run NR8 (a long option of sort allowed) survived: the controls that
carry `--compress-program` also carry another option the gate refuses. `O70_sort_long_option_alone` (a long option
with no other operand) was added; the mutant lets O70 and O71 BYPASS in the oracle (O70 leak=1, O71 leak=94;
`oracle/nr8.cases_r13d.txt`), and the control kills it (final pre-run: killed by its property, 2 FAIL lines).

**AN34 and AN37.** The first pre-run also left AN34 (the `GCONV_` prefix rule dropped) and AN37 (an unquoted
here-document body not read) alive: their controls did not tell the rule apart (O59 writes `GCONV_PATH`, which is
also on `DANGER_NAMES`; every here-document is refused anyway, so only the finding for the command substitution in
the body changes). `O72_GCONV_prefix_other` and `O73_heredoc_body_read` were added as controls (`mutants.md`).
The first pre-run (100 mutants; AN40-AN42 and PN19 were added to the spec after it started) is kept as
`mutants_targeted_r13_first.tsv`.

**The standing run.** The whole harness ran on commit A as a transient systemd user service; summary `standing_summary.txt`:

```
DONE head=8e0ef48ba935915e9eada2c355873ec9dc88ff79 rc=1 seconds=28117
RESULT: killed=374 survived=1 equivalent=8 stale=0 control_failures=0 inconclusive=0
verdict_lines=391 controls_pass=8 killed=375 equivalent=8
FAIL and SKIP lines:
FAIL B2 killed, but not by its property /N2/ (FAIL K6 marker with a dirty environment was taken as clean or re-executed: rc=0)
sha256 bb7a9f30f5a31156d3328c240bb11f75fd941181bce4d204a46a47e0727f85a8
```

Full output: `mutations_full_r13.txt`.

`tools/launch_standing13.sh` was changed after commit A and before the launch (commit B carries the change): the
harness HOME is now a `mktemp -d` directory under the run directory, checked non-empty and under it before use
(§11.4.287(C)(2)), instead of `$st/home`. The run above used the changed launcher; the harness and the tree under
test are commit A unchanged.

The summary line `killed=375` counts the `PASS ... killed` lines with a plain grep, which also matches the evidence
text of the recorded equivalent X12 ("X12b removes both and is killed by case 25"); the harness's own `RESULT`
line, `killed=374`, is the count, and 374 lines start `PASS <name> killed`.

**B2, the one mutant not killed by its property.** B2 (round 8) removes the loop guard of `rc_env_clean` in
`scripts/release/redact_cut.sh`, a release library unchanged since `dd095a3f`; it is not a round-13 mutant. Its
property is K8 N2 of `tests/release/test_redact_cut.sh`: the probe `p5.sh` forces the state "dirty" and must end,
under `timeout 30` (124 = an endless loop), with status 4 and the marker argv[0]. In the standing run the redact
suite failed only at K6 (the mutant re-executes a marked process that has a dirty environment, `rc=0`), so the
harness reported "killed, but not by its property /N2/". The cause, found by changing one input at a time
(`b2_investigation/`, commands in `b2_investigation/commands.md`):

- Without the guard the probe re-executes itself without end, and every pass keeps one more descriptor open (the
  process-substitution descriptor of the `exec`; `_rc_env_closefds` runs only in the clean state): 69, 420, 735
  and so on up to 3236 descriptors, sampled every 2 s (`probe_fd_growth.txt`).
- A transient systemd user service gets the default soft `RLIMIT_NOFILE` of 1024 (`DefaultLimitNOFILESoft=1024`);
  a `--scope` keeps the caller's soft limit (524288 here). This standing run was a service; the suite runs of this
  round used `--scope`. The round-12 standing run was a service too, but it stopped after 34 lines, before B2 (O3).
  The earlier B2 results, all "killed by its property (FAIL K8 N2 loop guard: rc 124 ( ))"
  (`mutations.txt` of `../round8/`, `../round9/` and `../round10/`, and `../round12/r11_harness_partial.txt`), come
  from runs whose descriptor limit was not recorded.
- With the soft limit at 1024 the loop reaches it after about 8 s: "redirection error: cannot duplicate fd: Too
  many open files", the `exec` does not run, `shopt -s execfail` keeps the shell, and `rc_env_clean` reaches its
  last line, `return 4`, the status the guard returns. The probe then prints `rc=4` and `a0=rc-clean-env`, which is
  all K8 N2 checks, so the test accepts the mutant.
- The toggle: the mutant probe ends with rc 0 and `rc=4` (K8 N2 passes) at soft limit 1024, in a scope with
  `ulimit -n 1024` and as a transient service, and with rc 124 (K8 N2 fails) at 524288; the unmodified library
  ends with `rc=4` at both (`probe_nofile_toggle.txt`, `probe_service_mutant.txt`, `probe_control_unmutated.txt`).
  The harness itself, `--only B2` on the standing tree: "killed, but not by its property /N2/" twice as a transient
  service, "killed by its property (FAIL K8 N2 loop guard: rc 124 ( ))" twice as a scope (`harness_b2_both.txt`).
- Not the cause: task limits. With TasksMax 4 to 7 forks fail and K8 N2 still fails the mutant
  (`probe_low_tasksmax.txt`); at TasksMax 3000 the loop used at most 9 tasks (`probe_t3000.txt`).
- The repro started before the host reboot (`repro_scope_partial.txt`) was a scope run of the whole harness (it
  set `ONLY=B2` in the environment, which the harness does not read; the option is `--only B2`); the reboot
  stopped it after 314 lines, and its B2 line is "killed by its property".

So the verdict depends on the soft descriptor limit and is the same in every run of one environment; it is not
flaky. It is a test-instrumentation finding against K8 N2 (§11.4.235(D)): its check (status 4 and the marker)
cannot tell the guard from a loop that ends because it ran out of descriptors. The shipped guard is present, and
the unmodified library passes K8 N2 at both limits. It is not fixed in this round: it is outside the round-13
change set, and a fix changes the redact suite, which 155 mutants of the harness run (153 on `redact_cut.sh`, 2 on
`env_census.py`), so their standing results would need a new run. A possible fix, for a tracked follow-up (not
filed by this round): the probe appends one line per start to a file, K8 N2 requires exactly two lines (the guard
refuses on the second pass; the mutant starts more than twice at any limit), and the redact-suite mutants are run
again at both limits.

## 6. F3: corrections of stated properties

The round-12 text is kept and corrected with dated notes (2026-11-13), as round 12 did for round 11:

- `../round12/README.md`: the title and section 1 ("Every command in every context is classified", "a construct the
  parser does not model is a parse error") and the `probe_extra.py` claim "a function named `git`" (R03 to R05).
- `../round12/threat_model.md`: the title, section 2 and the limit in section 4.
- `../round12/class_inventory.md`: K2 "visits every command of every context", K6 "a finding in every form",
  "SUBST_RE is refused in every arithmetic context".
- `tests/release/channel_census.py`: the header no longer says "DEFAULT-DENY ... never a pass"; it describes the
  pin and the positive shapes and states the limits.
- `../round12/SHA256SUMS` is regenerated over the corrected files; the sums before the correction are in
  `round12_sums_before_f3_correction.txt`.

The commit message of `dd095a3f` is not rewritten (§11.4.113); it is corrected here, dated 2026-11-13. Its subject
("the network-spawn gate becomes a default-deny bash parser with no host lookup") and its first bullet ("reads every
command in every context ... A construct it does not model is a parse error, and a parse error is a finding",
"anything else is 'unclassified command (default deny)'") overstate the round-12 gate: it read here-document line
joining, here-documents across `$(` and process substitution inside `[[ ]]` without an error, and its builtin,
local-program and state rules were deny-lists (F1 of the round-12 review, 32 bypasses). "No host lookup" was true.

The round-13 documents state what each layer proves and does not prove (`threat_model.md` section 2) and do not
call the analyser complete: the class inventory says it lists "the members found so far".

## 7. Observations

- **O1 (round budget).** This round is past `R_max` under the standing operator decision of 2026-11-11 (continue
  until GO; every round past 5 structural, with a fresh fixer and reviewer), as relayed in the dispatch brief of
  this round, which names CON-234. The structure is different from rounds 11 and 12 (section 1).
- **O2 (the line text in findings).** Fixed (section 1). Residual: a message still names the offending word, option
  or construct and for a few classes quotes up to 20 to 40 characters of it; `channel_census.py list` prints line
  text (`threat_model.md` section 5).
- **O3 (the round-12 standing run).** The service `fix227-r12-standing-dd095a3f.service` started 18:27:39 CET and
  stopped 19:20:33 CET; the journal records "Consumed 21min 48.314s CPU time over 52min 54.709s wall clock". Who
  stopped it is not recorded (UNCONFIRMED). Its partial output: `r12_standing_summary.txt` (sha256 `1064d4d887b4120995d430479b53dfc635fbe429c9621e7f8c775bbf1f6e89d3`) and `r12_standing_mutations_partial.txt` (sha256 `30b7444fddd9c84f30df0684942283e02632c5cf9306ae7e239b174627536ec1`): 34 PASS lines (8 controls, 26 killed), 0 FAIL lines. It never reached the gate mutants;
  the round-12 code is superseded by this round.

## 8. Other checks

| Check | Result | File |
|---|---|---|
| golden-FALSE, both PATHs | NETGATE layer=pin+analyser invocations=128 network_through_rc_net=51 findings=0 sites=128 findings_lines=0 both_paths=identical | `golden_netgate_*.txt` |
| census lint, both PATHs | CENSUS invocations=128 rows=124 secret_lines=13 findings=0 both_paths=identical | `lint_*.txt` |
| shellcheck -S warning | rc 0; version: 0.11.0 files=12 output_lines=0 | `shellcheck.txt` |
| pyright | 0 errors, 0 warnings, 0 informations | `pyright.txt` |
| `scripts/run_full_suite.sh --verify-manifest` | RESULT: MANIFEST-OK when `verify_manifest.txt` was captured, BEFORE `tools/make_mutants_md.py` was added; on the committed trees of commit A and commit B it is MANIFEST-MISMATCH, exit 3 (that file had no manifest row; round-13 review F1). Corrected in round 14 (the tool is renamed `tools/make_mut_table_md.py`; see `../round14/README.md`) | `verify_manifest.txt` (captured before the last file was added) |
| gate ledger ratchet | LEDGER: unimplemented=394 baseline=394 fails=0 | `gate_ledger_ratchet.txt` |
| LIVE loopback sshd probe (round 11's `probe_sendenv_leak_sshd.sh` on this tree) | SUMMARY cases=36 clean=36 leak=0 blind=0 | `sshd_probe_green_round13.txt` |

## 9. UNCONFIRMED and open

- Who stopped the round-12 standing run (O3).
- Whether `sqlite3 -safe` also covers the dot-commands of a caller's `~/.sqliterc` (sqlite3 reads it unless `-init`
  is given); not tested.
- The analyser's model of bash is checked by 274 controls and the oracle runs, not by a proof (§11.4.118); a
  construct the parser accepts and bash reads differently would be a gap in layer 2, and layer 1 still refuses it
  until a regeneration is reviewed.
- The pin makes a change visible; whether the reviewer of a regeneration reads `pin-diff` is not something the gate
  can check.
- K8 N2 accepts the B2 mutant when the soft descriptor limit is 1024 (section 5); not fixed, and no follow-up item
  was filed by this round (a follow-up draft is filed in round 14: `../round14/followup_k8_n2_nofile.md`). The descriptor limit of the earlier runs that killed B2 by its property (rounds 8 to 11)
  was not recorded.
- Commit A carries the launcher before the HOME change; commit B carries the version the standing run used.
- The independent round-13 review is owed.

## 10. Files

- `README.md`: this file
- `SHA256SUMS`: sha256 of every other file of this directory
- `b2_investigation/`: why B2 was not killed by its property in the standing run: the probes, the harness `--only B2` runs at both descriptor limits, their outputs and `commands.md`
- `checks.tsv`: one line per check above
- `class_inventory.md`: the controls by class (generated)
- `gate_ledger_ratchet.txt`: gate ledger ratchet
- `golden_netgate_emptypath.txt`: the same with PATH=/nonexistent
- `golden_netgate_normalpath.txt`: netgate --pin --sites on the release files, normal PATH
- `lint_emptypath.txt`: census lint, PATH=/nonexistent
- `lint_normalpath.txt`: census lint, normal PATH
- `make_class_inventory.py`: writes class_inventory.md
- `mutants.md`: every mutant: what it breaks, its property, the pre-run and standing-run result
- `mutants_targeted_r13.tsv`: the targeted pre-run on the final tree (one line per mutant)
- `mutants_targeted_r13_first.tsv`: the first targeted pre-run, before the last edits (100 mutants; NR8, AN34, AN37 not killed)
- `mutations_full_r13.txt`: the standing run of the whole harness on commit A
- `mutations_stale_only_round13.txt`: `STALE_ONLY=1` run of the harness
- `oracle/`: RED and GREEN oracle results (`r12.*.txt`, `r13.*.txt`), the mutants on the round-12 gate (`discr.log`, `mr5_mr10.txt`; `d2b_mr2.txt`: MR2 against `D2b_mapfile_C_attached`, from `tools/cases_d2b.json`), NR8 on the gate (`nr8.cases_r13d.txt`), the reviewer's 32 names (`rev_names.txt`)
- `pn13_probe.txt`: the probe behind the PN13 equivalence
- `pyright.txt`: pyright
- `r12_standing_mutations_partial.txt`: O3: the partial output of the round-12 standing run
- `r12_standing_summary.txt`: O3: the summary file of the round-12 standing run, as it was left
- `round12_sums_before_f3_correction.txt`: `../round12/SHA256SUMS` before the F3 notes
- `shellcheck.txt`: shellcheck -S warning
- `sshd_probe_green_round13.txt`: LIVE loopback sshd probe
- `standing_summary.txt`: its summary
- `suites_run1.tsv`: suite summary, run 1
- `suites_run2.tsv`: suite summary, run 2
- `threat_model.md`: goal, failure model, the three layers and what each proves, the positive shapes, residuals
- `tools/`: the scripts and fixture files behind this evidence (oracle, mutant spec, pre-run, probes, runners)
- `verify_manifest.txt`: --verify-manifest
- `green_<suite>_run1.txt`, `green_<suite>_run2.txt`: the six suites, twice

`SHA256SUMS` lists every file of this directory except itself.
