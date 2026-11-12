# CON-030 independent review, round 4 (section 11.4.209 / 11.4.142)

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner: submodule paths cut out of `git submodule status` text, widened in round 3 to the class of in-band keys, sentinels, delimiters, line splitting and framing in the engine); round 4 = structural round (section 11.4.276(E)(3)) |
| Vehicle | vehicle/con030, head 6a64583129da6c9ac97c6079db8cd1131d05725a; round-4 commits adfd96fa (merge main bdc3ac43), 87cd467e (engine, tests, guide rev 9, wrapper header), 6a645831 (tracker) |
| Bundle | the fixer's hand-back was lost in the host reboot, so I made the bundle from the author clone myself: `rv030r4.enJNzd/con030_r4_reviewed.bundle`, sha256 f1e4bca26656f9cf8ba849a1d4e3b54f350f454024b3e8e31afca5d9c272782c, range bdc3ac43..vehicle/con030, head 6a645831 |
| Round | 4 of at most 5 (section 11.4.276(G)) |
| Reviewer | independent subagent, Opus 5.5, not the author; the brief asked for xhigh effort, the dispatch path does not report effort to the agent, so no effort is claimed (section 11.4.231(F.2)) |
| Sandbox | `scratchpad/rv030r4.enJNzd/` (c = clone + bundle; worktrees head = 6a645831, r3 = 34f62dbf (round-3 engine), m = bdc3ac43 (main the vehicle merged), mb = 90efceb8 (live main), mutw = detached 6a645831 + my mutant rows, land = trial merge onto 90efceb8). git config isolated with `GIT_CONFIG_GLOBAL=<sandbox>/home/gitconfig GIT_CONFIG_NOSYSTEM=1` and `TMPDIR` inside the sandbox; `HOME` was never reassigned |
| Author clone | `scratchpad/c30r4.wY7Whz/c`: read only. It holds uncommitted round-4 work (CON-109 in the tracker files, the widened class sweep, the author report with a placeholder), so it is NOT retired by me |
| Verdict | **NO-GO**. Every round-3 finding is closed RED to GREEN with the round-3 reviewer's own commands, the self-test and the author's whole mutation table hold (150 of 150 killed, twice), and the structural design (one reader, structured key, one escape) is right. Three things block GO: (1) one more member of the declared class is open (K1: the guide's census markers are found by substring, so `--sync-guide` deletes prose; data-safety surface, so not minor-class); (2) four of my eight reviewer mutants survive the whole self-test (M1, M2, M5, M6: `err()` escaping, the guide's GovLineError path, the per-line summary, the census line-breaker refusal), each on a mechanism this round added, so this batch's fixes are not yet proven (section 11.4.235(D) proof-of-batch, not minor-class); (3) the landing onto live main is a semantic merge into the very structure this round built (K5). Round 5 is a targeted round, not a forced structural one: every in-class finding is minor severity (section 11.4.276(E)(3) needs at least one non-minor). |

## Verdict in one paragraph

The round-4 design closes the three round-3 class members at their root. `gov_lines()` is now the only reader of
the manifest, the known table, the excluded lock, the operator roster and the guide; it splits on LF only, keeps
CRLF readable and refuses NEL, LS, PS, VT, FF, bare CR and the other C0/C1 controls by name. A unit's identity is
the tuple `(path, tuple(args))` in `plan()`, in the records and in `rec_matches()`, and `plan()` refuses two units
with one key or one display id. Every terminal and `summary.txt` line goes through `esc_out()`. I re-ran the
round-3 reviewer drivers unchanged on three engines: on round 3 and on main the H1 fixture ends PASS-FULL rc 0
(default and cross-mode), a NEL/LS/CR in a roster comment makes `eve` an operator and the run ends PASS-FULL
"accepted_by: eve", and a CR test name forges RESULT lines; on the head the H1 run is refused rc 3 naming both
units, the roster is refused naming the character, and the CR name is refused rc 3. The head's self-test gives
343/0 (0 SKIP), and the same tests fail 28 checks on the round-3 engine and 61 on main, exactly as the author
reported. Both author mutation runs killed all 150 rows of the table; of my own eight mutants, four are killed
(RX3, RX4, RX7, RX8) and four survive (RX1, RX2, RX5, RX6), and I measured a reachable effect for each survivor
(a raw CR on stderr, a false MANIFEST-OK on a stale guide, a collapsed terminal summary, a wrong census message
plus a NEL name written into the manifest). On the real trees (the vehicle and live
main) `--verify-manifest`, `--list` and `--list --include-heavy` are byte-identical between the head engine, the
round-3 engine and live main's engine. What is still open: (K1) the guide census markers are found with
`text.index()` anywhere in the text, so a prose line that quotes `<!-- census:begin -->` before the real block
makes `--sync-guide` delete everything in between, rc 0, after which `--verify-manifest` says MANIFEST-OK
(measured on head and main); that is an in-band sentinel read by substring, the shape the class names, missed
by the author's sweep and by my round-3 enumeration. Landing (K5): live main moved 59 commits, and WIT-C02 on
main added a `gen=` field to the old text quick identity plus an after-unit check `"?" in qid`; the trial merge
conflicts in the engine, the self-test and the mutation table, and the after-unit check merges cleanly but means
something else on a `QuickIdent`. Outside the class I measured K4 (pre-existing): a resume reuses a PASS across a
different `--env-extra` value or a smaller `--timeout` (false PASS-FULL rc 0; fresh control FAIL rc 1).

## Per-slice verdicts (section 11.4.235(D))

| Slice | Files | Verdict | Open findings |
|---|---|---|---|
| Engine | scripts/full_suite/run_full_suite.py | **NO-GO** | K1 (minor, data-safety surface: not minor-class); K2 (minor); K12 (minor); K3 (nit); K9 (nit); K4 is outside the class (own item) |
| Self-test | tests/test_run_full_suite.sh | **NO-GO** | M1, M2, M5, M6: four of my eight reviewer mutants survive the whole self-test, each on a mechanism this round added, so this batch's fixes are not yet proven (section 11.4.235(D) proof-of-batch); K10 (nit: lint scope wording); tests for K1/K2/K3/K12 belong to the engine fix |
| Mutation table | tests/test_run_full_suite_mutations.sh | **NO-GO** until the four surviving reviewer rows are added verbatim and killed (section 11.4.276(D)); the author's 150 rows: GO (both runs killed all 150) | M1, M2, M5, M6 (adopt RX1, RX2, RX5, RX6) |
| Guide | docs/guides/full_suite_runner_guide.md (rev 9) | GO-with-follow-ups | K8 (nit: Status cell stale); line 28 claim tied to K3; resume section must state K4 |
| Wrapper | scripts/run_full_suite.sh (header only) | GO | none |
| Tracker | docs/Issues.md, docs/Issues_Summary.md, docs/workable_items.db | NO-GO for landing as is | K6 (id collision with live main), K11 (nits) |
| Review evidence | docs/qa/con030_review/ | GO-with-follow-ups | K7 (uncommitted report with a placeholder, uncommitted sweep widening) |

## Findings

| Id | Severity | Layer | Where | What, measured |
|---|---|---|---|---|
| K1 | minor (data-safety surface, so **not** minor-class, section 11.4.276(G.2)) | source-defect; class member: in-band sentinel found by substring in a governance file | run_full_suite.py:1919-1922 `guide_check`: `a = text.index(GUIDE_BEGIN)`, `b = text.find(GUIDE_END, a)` | Guide with a prose line ``The block starts at a line `<!-- census:begin -->` ...``, then a prose line, then the real stale block: `--verify-manifest` rc 3 "stale"; `--sync-guide` rc 0 rewrites from the quoted marker to the real end marker: 6 lines deleted, the prose line "IMPORTANT PROSE THAT MUST SURVIVE" gone, then `--verify-manifest` rc 0 MANIFEST-OK. Same on main (pre-existing). Uncommitted prose in the guide is lost without a warning. Fix: a marker is a whole line (`line == GUIDE_BEGIN` from `gov_lines()`); exactly one begin line and one end line after it, else refuse naming the line numbers. Driver drv/guide_marker_quoted.sh |
| K2 | minor (minor-class) | source-defect (a maintenance command reports success it did not perform, section 11.4.201) | run_full_suite.py:3268 `guide_check(root, rows, fix=True)` result ignored | New in round 4: a guide holding a NEL in prose and a stale block: `--sync-guide` rc 0 prints the census line and writes nothing; `--verify-manifest` then rc 3 (fail closed). On round 3 the same command rewrote the block (r3 read the guide in text mode, where NEL is not a newline). The missing-end-marker case was already ignored on round 3. Fix: return the problem and exit 3. Driver drv/sync_guide_nel.sh |
| K3 | nit | source-defect; class member: output framing | run_full_suite.py `esc_out`: `LINE_BREAKERS.sub(...)` runs before the `surrogateescape` / `backslashreplace` round trip | Unit probe: `esc_out("\udcc2\udc85")` returns a raw `\x85` (NEL), `esc_out("x\udce2\udc80\udca8y")` a raw U+2028. No reachable path found: a name decoded with one `os.fsdecode()` call never holds the surrogates of a valid UTF-8 sequence, and the engine joins decoded parts with `/`, a space or a TAB. Guide line 28 ("written as `\r`, `\n`, `\xNN` ...") is then not strictly true. Fix: do the round trip first, then substitute. logs/esc_out_probe.txt |
| K4 | important (for its own item) | source-defect, **outside** the declared class (resume-context completeness, like round-3 H4) | run_full_suite.py:3320-3323 `ctx` = hash of manifest, known table and lock only; `--env-extra` names, their values, the caller environment kept by `ENV_BASE` and `--timeout` are not in the key | Fixture test passes only when `FOO=1`. Run 1 `FOO=1 --env-extra FOO` PASS-FULL; run 2 `FOO=0 --env-extra FOO` same `--out`: "resumed (PASS)", PASS-FULL rc 0; run 3 without `--env-extra`: PASS-FULL rc 0; control `FOO=0` fresh `--out`: FAIL rc 1. Same on main. A 3 s unit recorded with `--timeout 60` is resumed by `--timeout 1` (PASS-FULL rc 0; fresh control TIMEOUT, rc 1). Register as its own item; at least add it to the guide's resume section and Limits now. Drivers drv/envextra_resume.sh, drv/timeout_resume.sh |
| K5 | important (landing) | landing / merge-conflict resolution (section 11.4.211) | trial merge of 6a645831 onto live main 90efceb8 | Conflicts: docs/Issues.md, docs/Issues_Summary.md, docs/workable_items.db, run_full_suite.py (1 hunk: `quick_ident`'s return), test_run_full_suite.sh (1 hunk: main's section 38 WIT-C02 tests), test_run_full_suite_mutations.sh (2 hunks: header, main's G1-G4 RMb rows). Main's WIT-C02 (6c7bc578, 6eecc963) appended `gen=<fingerprint>` to the text quick identity and added an after-unit check. That check (`qid = quick_ident(...)  # RULE:C02-after-unit` / `if qid != qid0 or "?" in qid:`) merges WITHOUT a conflict marker; on a `QuickIdent` `"?" in qid` is true only when the status field equals `"?"`, and round 4 writes `None` for an unknown status, so the unknown half of that check is silently lost. Main's `gen_fingerprint` also raises UnicodeEncodeError on a non-UTF-8 entry name (unit probe on the live-main engine; end-to-end effect UNMEASURED), the Q13 shape, and frames its records with spaces. Round 5 must port `gen` into `QuickIdent` as its own field (`None` for unknown, paths through `os.fsencode`, records through `hrec`), use `ident_unknown()` in the after-unit check, keep main's section-38 tests and re-anchor G1-G4 RMb |
| K6 | minor (landing) | process-doc / tracker (section 11.4.54) | tracker | Round 4 registered H4 as CON-108 (committed) and the tree_ident sites as CON-109 (uncommitted); live main already has CON-108 (ownership F1) and CON-109 (WIT-C02); its highest CON id is 115. Re-mint both through the workable-items engine after the merge (next free ids), never reuse; CON-070 is still free on main |
| K7 | minor | process-doc | author clone, uncommitted | `docs/qa/con030_review/con030_author_report_r4.md` (untracked) still contains `MUTATION_RESULTS_PLACEHOLDER` and names "this report's commit", which does not exist; the widened `con030_class_sweep_r4.py` and CON-109 are uncommitted. Commit them in round 5, the mutation section filled from the author's logs (both runs: 150 of 150 killed) |
| K8 | nit | process-doc (section 11.4.44) | guide line 8 | The Status cell still describes the runner's earlier review round 5 and "narrow round 6", not CON-030 round 4 |
| K9 | nit | source-defect (fail closed) | run_full_suite.py `--verify-manifest` path | On the H1 fixture `--verify-manifest` says MANIFEST-OK (rc 0) while a run is refused by `plan()` (rc 3). Nothing runs, so no false PASS; the pre-flight answer differs from the run's. Run the `plan()` key checks in verify too |
| K10 | nit | test-instrumentation (honest limit wording) | test_run_full_suite.sh:1434 `fsr_io_lint`, guide Limits | The lint enforces `gov_lines()` for the five named reader functions; a governance file read elsewhere under a `not-gov` label, or through `os.open` / `io.open` / `codecs.open` (the lint only follows a bare `open` name and attribute calls named in its IO set), is not seen. The guide says "calls named `open`"; say "a bare `open(...)`" and name the five readers |
| K11 | nit | process-doc (sections 11.4.15, 11.4.16) | tracker | CON-109 (uncommitted) is typed Task but describes a defect (an identity hash that can collide): Bug. CON-030 is Queued while rounds are running (In progress) |
| K12 | minor (minor-class) | source-defect (a maintenance command reports a success it did not fully perform, section 11.4.201; the K2 shape) | run_full_suite.py `--generate-manifest --write` | New in round 4. A test file whose name holds a NEL or LS: head writes the manifest WITHOUT that file ("1 row"), rc 0, no warning; `--verify-manifest` and the run then refuse rc 3 naming the character (fail closed, no false PASS). On round 3, main bdc3ac43 and live main 90efceb8 the same command wrote the name into the manifest ("2 rows") and the run went ahead (rc 10, the probe leaves the regenerated manifest uncommitted). Fix: refuse (exit 3) naming the file, as verify does. Driver drv/rx6_census_nel.sh, logs/rx6_census_nel.txt plus tmp_probe g.log files (retired) |
| M1 | minor (proof-of-batch: **not** minor-class) | source-defect (section 11.4.235(D): a proving guard of this batch whose reviewer mutant survives) | `err()` escaping, no test | RX1 (`err()` writes `msg` raw) survives the whole self-test. Reachable: an uninitialised submodule whose path is `s\rRESULT: PASS-FULL (forged)` makes the TOPOLOGY line on stderr carry a raw CR (head: 0 raw CR bytes on stderr, RX1: 1; rc 9 on both). On a terminal that is the round-3 H3 forgery on stderr. Add a test that greps a raw CR (or any `LINE_BREAKERS` character) in stderr for a CR-named path |
| M2 | minor (proof-of-batch: not minor-class) | source-defect (section 11.4.235(D)) | `guide_check` GovLineError path, no test | RX2 (`guide_check` returns `None` on GovLineError) survives. Measured on a mutant copy of the head engine: a guide holding a NEL in prose and a stale census block gives `--verify-manifest` rc 0 **MANIFEST-OK**; head gives rc 3 naming the guide. A regression here is a false OK on a stale guide. Test: the drv/sync_guide_nel.sh fixture, verify must be rc 3 |
| M5 | minor (proof-of-batch: not minor-class) | source-defect (section 11.4.235(D)) | terminal summary written line by line, no layout test | RX5 (`out("\n".join(summ))`) survives. Measured: the terminal output of a one-unit run drops from 25 to 7 lines; the whole summary body becomes one 1588-byte line holding 18 escaped `\n`; the `RESULT:` line itself stays at a line start. Test: the terminal summary has one line per summary entry (for example `members also run alone` and `EXCLUDED` start lines) |
| M6 | minor (proof-of-batch: not minor-class) | source-defect (section 11.4.235(D)) | census bad-name check uses `LINE_BREAKERS`, no NEL/LS test | RX6 (the census check narrowed to C0 + DEL) survives: verdict-equivalent at run time (rc 3 on both, because `gov_lines()` then refuses the written manifest), but verify names "census file without manifest row" instead of the refusal of the character, and `--generate-manifest --write` writes 2 rows (the NEL name goes into the manifest) instead of 1. Test: a NEL and an LS file name; verify must name the character, and generate must not write the name |

Process note for the next fixer, not a finding against the vehicle: the author's scratch `runmut.sh` exports
`HOME="$W/home"` (guarded by `${1:?}`); the dispatch rule is never to reassign HOME. Isolating git with
`GIT_CONFIG_GLOBAL` and `GIT_CONFIG_NOSYSTEM=1` was enough for every run in this review.

## Class enumeration (section 11.4.276(C)), my own

The author's sweep (`con030_class_sweep_r4.py`, shapes A readers, B joined-text identities, C output; `SITES
A=33 B=12 C=61 controls=ok`) is correct as far as it goes: I re-read each B site and agree with every
classification in the author report. What the three shapes do not cover is a sentinel or marker matched by
substring inside a governance text (shape D). I searched the engine for `in text`, `.index(`, `.find(`,
`startswith(`, `endswith(` and `" in "` over governance or child text:

| # | Site | State | Evidence |
|---|---|---|---|
| D1 | guide `census:begin` / `census:end` found by `text.index` / `text.find` | **open: K1** | drv/guide_marker_quoted.sh |
| D2 | `"/fixtures/" in "/" + f` (four sites) | benign: a containment test on a path | author table, re-read |
| D3 | `"160000 " in git ls-files -s` | a false hit only reads submodules when there are none (round-3 #19) | re-read |
| D4 | `"?" in qid` (after-unit check, live main only) | becomes wrong on a `QuickIdent` at the merge: K5 | land/ line 3444 |
| D5 | excluded-lock `startswith("#")` comment marker, `# accepted` lines | whole-line, after `gov_lines()` | re-read |
| D6 | KNOWN signature matched against the unit log tail | pre-existing substring match of a log line; the known table's own sha256 check binds it to one log (round-3 X3); outside this class (a matcher, not a framing) | re-read |

Shapes A to C, re-checked: every governance read goes through `gov_lines()` (the lint result `problems=0` on the
head, and both control needles caught); the unit key is the tuple at every site I found (`plan`, `rec_key`,
`rec_matches`, nondeterminism grouping); `out()`, `err()` and `summary.txt` escape (K3 is the one ordering gap).
The two `tree_ident` `splitlines()` sites are class members at not-governance sites with no verdict effect by
reading (QuickIdent and tree_state decide); registering them as their own item (CON-109, to be re-minted, K6) is
right.

## Round-3 findings: status

| Id | Round-3 severity | Status at round 4 | How checked |
|---|---|---|---|
| H1 | important | **fixed** | drv/uid_collision.sh, drv/uid_crossmode.sh (round-3 drivers, unchanged): r3 and main PASS-FULL rc 0 (default and heavy reusing D); head default rc 3 "two different units are both shown as 'x/run_all.sh --quick'", heavy reusing D rc 1 FAIL; control module dir `gomod` FAIL rc 1 on all three |
| H2 | important | **fixed** | drv/roster_split.sh: NEL, LS, CR on r3 and main: ids `['alice', 'eve']`, accept by eve rc 0, run PASS-FULL "accepted_by: eve"; head: ids `[]`, accept refused rc 3 naming the character, run rc 3; plain-space control: `['alice']`, eve refused rc 3 on all three |
| H3 | minor (not minor-class) | **fixed** (refusal of CR names, plus escaping) | drv/cr_forge.sh: r3 forged two PASS-FULL lines on the terminal and one in summary.txt; head rc 3, one real RESULT line |
| H4 | important (outside) | registered (CON-108, id collides on live main: K6); guide line 189 states the limit | tracker + guide |
| H5 | nit | done: CON-070 re-added with `--created-by`; parent in prose (the tracker's parent column is only set by the section 11.4.149 sub-task commands, so "no parent flag" for a top-level item is right) | DB + subtask.go header |
| H6 / RW3 | minor | **fixed**: test kills RW3; head rc 2 "IDENTITY CHANGED before unit tests/a/test_2.sh: root status e3b0c44298fc -> ?" | drv/status_fail_midrun.sh |
| H6 / RW6 | minor | **fixed** (re-anchored to the tuple; killed in both author runs) | drv/rw6_crossmode.sh: default rc 0, heavy reusing D rc 1 on head |
| H6 / RW4 | minor | resolved by a direct `hrec()` test: `None`, `b""` and no record give three different hashes | self-test check present, passes on head |

## RED before, GREEN after

| Engine | Self-test (head's tests, FSR_RUNNER) | Round-3 reviewer drivers |
|---|---|---|
| head 6a645831 | rc 0, passed=343 failed=0, 0 SKIP | GREEN (table above) |
| round 3 34f62dbf | rc 1, passed=315 failed=28, 0 SKIP | RED: H1, H1 cross-mode, H2 x3, H3 |
| main bdc3ac43 | rc 1, passed=282 failed=61, 0 SKIP | RED: the same |

The counts equal the author's (`selftest_r4tests_on_{head,r3,main}.log`: 343/0, 315/28, 282/61).

Real trees, `python3 -I <engine> --root <tree>`, output sha256 (16):

| Mode | tree head: engines head / r3 / live main | tree live main 90efceb8: engines head / r3 / live main |
|---|---|---|
| `--verify-manifest` | rc 0, 3a7b96df10716f29 for all three | rc 0, b35efaf84354182f for all three |
| `--list` | 634c735ae384f7dc for all three (602 lines; the author's hash) | f78fa3d8021133a6 for all three (612 lines) |
| `--list --include-heavy` | 5dacdad68a4d0188 for all three (the author's hash) | 63f7ac3091c1318d for all three |

## Mutants (section 11.4.194(6)(d))

Author table: `logs/auth_mut1_killed.txt` and `logs/auth_mut2_killed.txt` (from the author clone's two full runs)
each list 150 killed ids, byte-identical to the 150 ids of the table on the head (`logs/head_mut_ids.txt`,
sha256 1d51ba806c554609 for all three). No survivor, no not-applicable row.

Mine (`drv/rx_mutants.tsv`, run through the head's own mutation harness on a detached copy of 6a645831,
`drv/run_rx.sh`, two shards, each with the harness's unmutated baseline first: "ok baseline: unmutated copy passes
the self-test"):

| Row | Mutation | Result | Reachable effect (measured on a mutant copy of the head engine) |
|---|---|---|---|
| RX1 | `err()` writes `msg` instead of `esc_out(msg)` | **SURVIVED** | CR-named uninitialised submodule: stderr 1 raw CR byte (head 0), the TOPOLOGY line ends `s^MRESULT: PASS-FULL (forged)`; rc 9 both (logs/rx1_stderr_cr.txt) |
| RX2 | `guide_check` returns `None` on GovLineError | **SURVIVED** | NEL in guide prose + stale block: `--verify-manifest` rc 0 MANIFEST-OK; head rc 3 (logs/rx2_guide_nel.txt) |
| RX3 | `read_roster` returns `(set(), None)` on error | killed (4 failing checks) | |
| RX4 | unit display id = path only (`uid = path`) | killed (3 failing checks) | |
| RX5 | terminal summary as one `out("\n".join(summ))` | **SURVIVED** | 25 terminal lines become 7; one 1588-byte line with 18 escaped `\n`; RESULT line intact (logs/rx5_summary.txt) |
| RX6 | census bad-name check narrowed to `[\x00-\x1f\x7f]` | **SURVIVED** | NEL/LS name: verify says "census file without manifest row" instead of naming the character; generate writes 2 rows instead of 1; run still rc 3 (logs/rx6_census_nel.txt) |
| RX7 | `rec_matches` also accepts a display-id match | killed (1 failing check) | |
| RX8 | `esc_out` without the surrogate round trip | killed (1 failing check) | |

Shard summaries: `mutants=4 killed=2 survivors=2` in each (mut1: RX1-RX4, mut2: RX5-RX8), harness exit 1 on both
because of the survivors. Per section 11.4.276(D) the four surviving rows are to be adopted VERBATIM into
`tests/test_run_full_suite_mutations.sh`, each with the killing test named in M1, M2, M5, M6, and each observed
to fail the suite before the round-5 review is dispatched.

## Landing plan (sections 11.4.288, 11.4.297, 11.4.211)

1. Round 5 works on the vehicle after merging live main 90efceb8 into it (merge, never rebase), with the
   conflict resolution on the section 11.4.211 substrate. In the engine: `QuickIdent` gains a `gen` field;
   `gen_fingerprint()` returns `None` for unknown, reads paths as bytes (`os.fsencode`) and frames records with
   `hrec`; the after-unit check uses `ident_unknown()`; `ident_diff()` and `ident_label()` name the field. Keep
   main's section-38 tests, re-anchor G1-G4 and RMb, and add a non-UTF-8 entry name under a generated set.
2. Fix K1, K2, K12, K3 (and K9 if cheap) with RED-first tests; add a mutant per fix. Adopt RX1, RX2, RX5 and
   RX6 verbatim into the mutation table with the killing tests of M1, M2, M5, M6, and record each one failing the
   suite before the fix-side test lands (section 11.4.276(D)). K1 and K2/K12 share a shape with the sentinel and
   success-report members: run the class sweep once more over every `--sync-guide` / `--generate-manifest` /
   `--write` path and every marker found in governance text, not only the reported sites.
3. Tracker: take main's three tracker files, then re-apply the CON-030 states and re-mint the H4 item and the
   tree_ident item through the workable-items engine with new ids; type the tree_ident item Bug; register K4 as
   its own item.
4. Commit the author report (K7) with the mutation numbers filled in and this review copied to
   `docs/qa/con030_review/`.
5. Re-run the whole self-test on the merged head and on main, the whole mutation table to the end, and the
   real-tree comparison on the merged tree; then the round-5 review. Landing on main goes through the section
   11.4.297 pull-request path that is now on main.

Round budget (section 11.4.276(G)): this is round 4; round 5 is `R_max` (default and hard ceiling 5). If round 5
does not reach GO, the item stops and goes to a recorded operator decision (section 11.4.276(E)(3)); a round 6 or
7 needs a recorded operator decision naming CON-030. The brief relays an operator ruling "keep running rounds
until GO"; whether it is recorded as such a decision is UNCONFIRMED from here, so the conductor should record it
(verbatim, naming the item) before dispatching a round 6, never treat the relay as the record.

## Evidence (this session, under rv030r4.enJNzd/)

sha256 (first 16 hex) of each file:

| File | sha256-16 | What |
|---|---|---|
| con030_r4_reviewed.bundle | f1e4bca26656f9cf | the reviewed bundle (full: f1e4bca26656f9cf8ba849a1d4e3b54f350f454024b3e8e31afca5d9c272782c), head 6a645831 |
| logs/engine_r4.diff | 3c735b1cce6c9f98 | engine diff bdc3ac43..6a645831 |
| logs/tests_r4.diff | 45184611af01ddf5 | test diff bdc3ac43..6a645831 |
| logs/findings.txt | 659fc4870cb91c75 | round-3 reviewer drivers on head / r3 / main (H1, H1 cross-mode, H2, H3, RW3, RW6) |
| logs/selftests_summary.txt | 6d181f64628d1235 | head 343/0, r3 315/28, main 282/61, 0 SKIP each |
| logs/selftest_on_head.log | 3d56abf7371e7e7d | |
| logs/selftest_on_r3.log | e980435c8b0e43fc | |
| logs/selftest_on_m.log | 732cc53bfd64421c | |
| logs/real_trees.txt | eb018f54520da3ae | real-tree verify / list / list-heavy hashes, both trees, three engines |
| logs/guide_marker_quoted.txt | 6a19bd38a83ec57d | K1 |
| logs/sync_guide_nel.txt | 5cbf662a1ffa73d0 | K2 |
| logs/esc_out_probe.txt | 938fa20cc36fbe8d | K3 |
| logs/envextra_resume.txt | 2db53e31f993139f | K4 (env-extra) |
| logs/timeout_resume.txt | 4c87ac26801cf118 | K4 (timeout) |
| logs/land_merge.txt | 2a8e0f29abe3c034 | K5 trial merge onto 90efceb8 |
| logs/genfp_probe.txt | 8dc40f3f3cb29654 | K5 `gen_fingerprint` UnicodeEncodeError on a non-UTF-8 name (live-main engine) |
| logs/rx6_census_nel.txt | 23a7017e12aee0b7 | K12 and M6 |
| logs/rx1_stderr_cr.txt | 04167a8dcb92a045 | M1 |
| logs/rx2_guide_nel.txt | 08d1d621ad2ceb9e | M2 |
| logs/rx5_summary.txt | cb283d15db2515b7 | M5 |
| logs/mut1.log, logs/mut2.log | (text quoted above) | reviewer mutant shards |
| logs/auth_mut1_killed.txt, auth_mut2_killed.txt, head_mut_ids.txt | 1d51ba806c554609 (all three) | author mutant runs vs the table |
| drv/rx_mutants.tsv | c04487182247126b | reviewer mutant rows RX1-RX8 |

The drivers (drv/*.sh) are kept with the logs. The clone `c/` with its worktrees (head, r3, m, mb, mutw, land),
the probe fixtures and the mutant engine copies (tmp_probe, tmp_mut1, tmp_mut2) are retired after this review;
the trial merge in `land/` is aborted first. The author clone `c30r4.wY7Whz/c` is left untouched.
