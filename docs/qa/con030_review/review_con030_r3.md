# CON-030 independent review, round 3 (section 11.4.209 / 11.4.142)

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner: submodule paths cut out of `git submodule status` text), round 3 = the structural round of section 11.4.276(E)(3) |
| Vehicle | vehicle/con030, head 34f62dbfbb68b6a1c7d218341dfa638fac33a333; round-3 commits 94c734cb (merge main efe2cc6, tracker taken from main), f6567349 (engine, tests, guide rev 8, runner header, docs/qa/con030_review/), 9c9e9d67 (Q1..Q13, duplicate-id refusal), 34f62dbf (tracker) |
| Bundle | con030_r3.bundle, sha256 5fbdfbdd07741552c74c5a21ee35742db1a3190125e18e1c8b1ad9e55aa75858 (matched before cloning; range efe2cc6c..vehicle/con030) |
| Round | 3 of at most 5 (section 11.4.276(G)) |
| Reviewer | independent subagent, Opus 5.5 (the dispatch path cannot set or report effort, so no effort is claimed, section 11.4.231(F.2)); not the author |
| Sandbox | `scratchpad/rv030r3.1XCVj7/` (c = clone of the real repository + the bundle; worktrees head = 34f62dbf, r2 = 94c734cb (round-2 engine), m = efe2cc6c (main the vehicle forked from), mb = b939266a (current main), mutw = detached 34f62dbf for the mutants, land = trial merge); HOME, TMPDIR and git config inside the sandbox (`GIT_CONFIG_NOSYSTEM=1`) |
| Author clone | `scratchpad/c30r3.9Nxkdw/c`: read only (its logs only); its four mutation shards were not touched |
| Verdict | **NO-GO** for the engine slice. The G3 structural replacement is right and every class member the author listed is fixed and tested (RED on main and on round 2, GREEN on round 3). But the class-exhaustive claim does not hold: two further members of the same class, both pre-existing on main and both missed by the round-3 enumeration, give a false PASS-FULL (H1, also under `--include-heavy`, so a false section 11.4.40 retest) and an operator-authority bypass that survives a visual review of the committed roster (H2). Section 11.4.276(E)(3): same-class findings, two of them not minor, reappear after the structural round. |

## Verdict in one paragraph

The structural fix of G3 is correct. `QuickIdent(heads, status)` keeps the root status in its own field and the
heads as ordered `(path, value)` pairs, so no path can be read as a key and no value as a sentinel: the reviewer's
end-to-end fixture (submodules `plain` and `status`, HEAD of `status` unborn) now ends `RESULT: FAIL` rc 1 like its
control `other`; round 2 ended PASS-FULL rc 0. Every class member the author enumerated (cases 0 and A to J of
docs/qa/con030_review/con030_class_repro.sh) I re-ran on three engines with real git: all are wrong on main and on
round 2 and right on round 3. The self-test gives `passed=300 failed=0` on the head and fails 24 checks on the
round-2 engine and 38 on main. The landing merge with current main b939266a conflicts only in the three tracker
files, as expected, and `--verify-manifest` on the trial merge is identical to main's.

The class claim is the problem. Round 3 was the structural round precisely so that the whole class (in-band keys,
sentinels, delimiters, line splitting and framing in the engine) would be enumerated once. My own enumeration found
two members the author did not list. **H1**: the unit id is `path + " " + " ".join(args)`, and it is the resume
key; a Go module in a directory named `run_all.sh --quick` next to `run_all.sh` gets the same id as the
`runall-quick` unit, is "resumed" from that unit's PASS record and never runs. The run ends PASS-FULL rc 0 in
default mode, and also in `--include-heavy` mode when that run reuses an `--out` that a default run wrote (measured;
the record keeps `path` and `args`, but `key_ok` compares only the joined id). **H2**: `read_roster` uses
`str.splitlines()` in universal-newline text mode, the very splitting round 3 removed from the manifest, known and
lock readers. A committed roster line `# former operator, removed<NEL>eve<TAB>...` shows as one comment line in
`git show` but makes `eve` an operator: `--accept-excluded-change eve` is accepted and the run ends PASS-FULL with
"EXCLUDED set last accepted_by: eve" (NEL, LS and CR all measured; control with a space: refused). A third,
minor member, **H3**, is new exposure from round 3 itself: CR paths are now listed (round 2 refused them with rc 3),
but unit ids are printed raw, so a test path that holds `\rRESULT: PASS-FULL ...` forges RESULT lines on the
terminal and puts a forged PASS-FULL line, and no real RESULT line, into summary.txt (the exit code and the last
RESULT line stay correct). Outside the class I also measured **H4** (pre-existing): a suite that writes an
ignored file inside a submodule is not seen by the tree-changed check (PASS-FULL rc 0; the same write at the root
ends FAIL rc 1); that is coverage, not encoding, and belongs in its own item.

## Per-slice verdicts (section 11.4.235(D))

| Slice | Files | Verdict | Open findings |
|---|---|---|---|
| Engine | scripts/full_suite/run_full_suite.py | **NO-GO** | H1 (important), H2 (important), H3 (minor, treated as not minor-class, see below); H4 is out of scope (new item) |
| Self-test | tests/test_run_full_suite.sh | GO-with-follow-ups | H6 (minor: two non-equivalent reviewer mutants survive); the tests for H1..H3 belong to the engine fix; otherwise every round-2 requirement is covered (G3 e2e pair, QuickIdent unit, G1, G2, G12 fixtures, class cases) |
| Mutation file | tests/test_run_full_suite_mutations.sh | GO-with-follow-ups | the duplicate-id refusal works (measured: exit 2 in 0 s naming `G3D`, before the baseline; the committed table plus my six rows has 0 duplicate ids); every row I ran applies; add RW3 and RW6 (H6) with the tests that kill them |
| Runner header + guide | scripts/run_full_suite.sh, docs/guides/full_suite_runner_guide.md (rev 8) | GO-with-follow-ups | G2 is now true (measured); line 139 says the tree hash covers "the names and content hashes of ignored files", which holds for the root only (H4) |
| Tracker | docs/Issues.md, docs/Issues_Summary.md, docs/workable_items.db | landing precondition | see Landing plan; H5 (nit) |
| Commit metadata | trailers | process-doc only | G10, G11 carried into the landing merge message; f6567349 carries `Roadmap-Item: CON-030` and two `Out-of-scope` trailers |

## Findings

Severity from the closed set critical / important / minor / nit; layer per section 11.4.235(D).

| Id | Severity | Layer | Where | Finding | Pre-existing? |
|---|---|---|---|---|---|
| H1 | **important** | source-defect (class member: in-band delimiter in a key; proof-of-batch surface) | run_full_suite.py:2388 `uid = path + ("" if not args else " " + " ".join(args))`; resume key `key_ok` at 3240 compares `o["unit"] == u["id"]` only | Two different units (path `x/run_all.sh` with args `["--quick"]`, and path `x/run_all.sh --quick` with no args) get one id. Fixture (drv/uid_collision.sh, real git, real `go test`): `x/run_all.sh` (runall-quick) next to a Go module in `x/run_all.sh --quick` whose test fails. `--list` shows `RUN x/run_all.sh --quick` twice; the run prints `[1/2] PASS x/run_all.sh --quick`, `[2/2] resumed x/run_all.sh --quick (PASS)`, `RESULT: PASS-FULL` rc 0; one record only. Control (module dir `x/gomod`): FAIL rc 1. `--include-heavy` alone is correct (runall has no args there), but a heavy run that reuses an `--out` written by a default run resumes the Go unit from the runall-quick record: `RESULT: PASS-FULL` rc 0, a false section 11.4.40 full retest (logs/uid_crossmode.txt; fresh `--out` control: FAIL rc 1). Main efe2cc6 does the same. Fix shape: a structured key (`(path, tuple(args))`, records already carry `path` and `args`), and `plan()` refusing two units with one key. | yes (main efe2cc6) |
| H2 | **important** | source-defect (class member: universal-newline line splitting; security surface, operator authority, section 11.4.240) | run_full_suite.py:2041-2042, `read_roster`: `open(path, errors="replace")` + `fh.read().splitlines()` | `str.splitlines()` also splits on NEL (U+0085), LS (U+2028), CR and others; text mode also turns a CR into `\n`. A committed roster whose third line is `# former operator, removed<SEP>eve<TAB>not an operator` reads as ids `['alice', 'eve']`. `git show HEAD:config/...roster` displays it as one comment line (NEL: `removedeve`, LS: `removed eve`, CR: `removedeve`). `--verify-manifest --accept-excluded-change eve` rc 0, then the run `RESULT: PASS-FULL` with `EXCLUDED set last accepted_by: eve`. Control (a plain space instead of the separator): ids `['alice']`, accept refused rc 3. Same on main. This is the CR/universal-newline member round 3 fixed in the manifest, known-failures and lock readers (`newline=""` + `split("\n")`) and missed here. Fix: the same reader, plus refusing any control or line-separator character in a roster line. | yes (main efe2cc6) |
| H3 | minor (treated as **not** minor-class, see note) | source-defect (class member: output framing; evidence file) | every `out("[%d/%d] ... %s" % (..., u["id"]))` (3270-3299) and the summary lines (3341: `lines.append(... u["id"] ...)`), written raw to stdout and summary.txt | Round 3 makes CR paths runnable (round 2 refused them with rc 3), but ids are printed without escaping (`shown()` escapes only non-UTF-8 bytes). Fixture (drv/cr_forge.sh): directory `tests/x\rRESULT: PASS-FULL (every unit run, none skipped) /` holding a failing suite. rc 1, the last RESULT line is the real `RESULT: FAIL`, grep counts one RESULT line; but split on CR (a terminal, or any universal-newline reader) shows two forged `RESULT: PASS-FULL` lines before it, and summary.txt read in Python text mode holds exactly one RESULT line, the forged PASS-FULL (summary.txt never holds the real RESULT). No in-repo program reads summary.txt or the RESULT lines except the tests (grep). Note: the exit code and the final RESULT line are right, so I grade it minor; but summary.txt is the run's evidence file (section 11.4.262), so I do not count it as minor-class under section 11.4.276(G.2) (conservative default, section 11.4.235(D)). The verdict does not depend on this. Fix: one escaping function for every path, id, label and gap on output (escape CR, LF, other C0/C1 and line separators), or refuse such names in the census. | new exposure in round 3 |
| H4 | important | source-defect (coverage, **outside** the declared class) | run_full_suite.py:2950-2971 `tree_state`: `git ls-files -o -i` runs in the root only; the `subs` record holds submodule status and diff, not ignored files | A suite that writes an ignored file inside a submodule during the run is not detected: submodule `lib` ignores `out/`, the suite writes `lib/out/x`, `--include-heavy` ends `RESULT: PASS-FULL` rc 0; the same write at the root (`out/x`, ignored by the root) ends `TREE CHANGED ... RESULT: FAIL` rc 1 (drv/ign_sub.sh, logs/ign_sub.txt). Main does the same. The guide (line 139) says the tree hash covers "the names and content hashes of ignored files" without saying root only, and the same gap means a resume key does not change when a submodule's ignored files change. Not an encoding or framing member, so it is outside CON-030's class and scope: register it as its own item (section 11.4.276(E)(2)); it does not block CON-030. | yes (main efe2cc6) |
| H6 | minor | test-instrumentation (section 11.4.194(6)(d), 11.4.276(D)) | tests/test_run_full_suite.sh | Two of my six new mutants survive the full self-test and neither is equivalent; each turns a refused run into PASS-FULL, measured end to end on the mutated engine. **RW3** (`quick_ident` hashes the root `git status` output even when git fails, instead of `None`): two units on a clean tree, unit 1 makes `.git/index` unreadable, unit 2 restores it; head stops before unit 2 with `IDENTITY CHANGED ... root status e3b0c44298fc -> ?` (rc 2, fail closed), the mutant runs both units and ends `RESULT: PASS-FULL` rc 0, because the hash of a failing status's empty output equals the hash of a clean tree's (drv/status_fail_midrun.sh). Only the QuickIdent unit test guards the root-status `None`, and nothing makes `git status` fail inside `quick_ident`. **RW6** (`uid = path`): a runall that passes with `--quick` and fails in full; a default run writes `--out D`, then `--include-heavy` reuses D; head runs the full runall and ends FAIL rc 1, the mutant resumes it from the `--quick` record and ends PASS-FULL rc 0 (drv/rw6_crossmode.sh). No test runs a heavy run over a default run's records. RW6 is the regression guard H1's fix needs anyway. | test gap |
| H5 | nit | process-doc (tracker) | docs/workable_items.db, CON-070 | CON-070 names its parent only in its description ("parent: CON-030"); the column `parent_atm_id` is empty. The engine has no flag that sets it (`add`/`update` help), and no item in the DB uses the column today, so prose is the project's present practice; L4 of review r2 asked for the parent. CON-070 also has no `created_by` (CON-071..CON-082 carry `Conductor`). Both can be set when CON-070 is minted again at landing (`--created-by`); the parent column needs an engine follow-up or an explicit decision that prose suffices. | n/a |

Nits seen and not worth a finding: `shown()` cannot distinguish a literal backslash path from an escaped `\xNN`
byte (messages only); `guide_check` rewrites CRLF to LF; the unframed concatenation of several submodules'
status in the `subs` record of `tree_state` can collide only for a tree that is already dirty (never PASS-FULL).

## Class enumeration (section 11.4.276(C)), my own, real git

I listed every in-band key, sentinel, delimiter, line split and framing site in the engine (`splitlines()`,
`split(...)`, string joins used as keys, `%s` concatenations hashed or parsed back, `startswith("#")`,
`errors="replace"`, markers and sentinels), then tested each that could matter.

| # | Site | Round-3 state | Evidence |
|---|---|---|---|
| 1 | submodule paths from `git submodule status` (CON-030 itself) | fixed: paths from `git ls-files -s -z`, line matched against the known set | case 0: main rc 9, round 3 rc 0 PASS-FULL |
| 2 | quick identity (G3, F8) | fixed: `QuickIdent` | case A + e2e: round 2 rc 0, round 3 rc 1 (status and other) |
| 3 | `?`+path "no module" sentinel in the Go census | fixed: removed | case B: `[?mod][plainmod]` (main/r2 only `[plainmod]`) |
| 4 | `tree_state` records, run-context hash | fixed: `hrec` length framing, prefix-free tags | case C: collision False; non-UTF-8 symlink target hashed (main/r2: collision True, UnicodeEncodeError) |
| 5 | `<absent>` file marker | fixed: `None` | case I: collision False |
| 6 | CR / universal-newline splitting of manifest, known table, excluded lock | fixed: `newline=""` + `split("\n")` + `crlf_line` | case E: verify rc 0 (r2: rc 3 "want 7 TAB columns") |
| 7 | `#` path vs the comment marker | fixed: named census problem | case D |
| 8 | non-UTF-8 test file name | fixed: named census problem (was dropped silently) | case J: rc 3 naming `\xff` (main/r2: rc 0) |
| 9 | non-UTF-8 submodule path (G1) | fixed: `os.fsdecode` | case F: rc 0 PASS-FULL (main/r2 rc 9) |
| 10 | newline path, path named twice (G2) | fixed: newline gap + duplicate gaps, `sub_paths` dedup | case G: newline gap + two duplicate gaps, `[a, b]` (main/r2: n=4, `[a, b, b]`) |
| 11 | **unit id `path + " " + args` as the resume key** | **not fixed** | **H1** |
| 12 | **operator roster `splitlines()`** | **not fixed** | **H2** |
| 13 | **raw ids and labels on output** | **not fixed; newly reachable** | **H3** |
| 14 | excluded-lock `"\0malformed"` key | fail closed | by reading |
| 15 | `acc_chain` `"%s|%s|%s|%s|%s"` | fields constrained by `ACC_RE` (`\S+`, hex, digits); unkeyed by design | by reading |
| 16 | `excl_set_hash` `"%s\t%s\n"` | injective because the census refuses TAB and newline names | by reading |
| 17 | results.jsonl `bytes.splitlines()` | safe: `json.dumps` escapes CR and LF | by reading |
| 18 | `tree_ident` subs hash (`splitlines` + `strip` + `sorted`), `sed` displaypath prefix, sentinels `nogit`/`unknown`/`clean` | secondary to `QuickIdent` (the decision); dirty list only for a dirty tree; sentinels in distinct value spaces | by reading |
| 19 | `"160000 " in git ls-files -s` | a false hit only reads submodules when there are none | by reading |
| 20 | `judge` rc 77 last line via `splitlines()` | suite output; SKIP is never PASS | by reading |
| 21 | `load_known` `errors="replace"` | the census refuses non-UTF-8 names, so no table path can need them | by reading |

## Round-2 findings: status

| Id | Round-2 severity | Status at round 3 | How checked |
|---|---|---|---|
| G1 | minor | fixed | case F rc 0; test `G1: a clean checkout with a non-UTF-8 submodule path runs` (fails on r2) |
| G2 | minor | fixed; guide rev 8 line 91 now true | case G; test `r3 G2` (fails on r2) |
| G3 | important | fixed structurally | e2e pair rerun; QuickIdent unit test; mutants G3D, RW1-RW3 (see Mutants) |
| G4 | minor | RV1..RV8 adopted; RV4 by the exact `known_sub_paths` set | RV rows 162-169 present; RV4 run (see Mutants) |
| G5 (L1) | landing | done for efe2cc6 (94c734cb); again needed for b939266a | trial merge below |
| G6 (L2) | landing | CON-070 still free on main b939266a (main's CON ids end at CON-091, none is CON-070) | DB query |
| G7 (L4) | landing | CON-070 cites tracked copies only | DB body |
| G8 (L3) | landing | CON-030 states set through the engine (history row 90), evidence resolves, sha256 1520da66...ba9a matches | DB + `sha256sum` |
| G9 | nit | added to CON-070 as member (7), marked UNCONFIRMED (not measured) | DB body |
| G10, G11 | nit | for the landing merge message | commit trailers |
| G12 | nit | fixed: nested `nest (ed)/in (ner)`, real `U` on `con (flict) )`, SHA-256 superproject are tests | self-test lines 466-470 `ok` |

## RED before, GREEN after

| Engine | Self-test (head's tests, FSR_RUNNER) | Class repro driver (cases 0, A..J) |
|---|---|---|
| main efe2cc6 | rc 1, passed=262 failed=38 | 0 rc 9; A status rc 1 (empty diff label), other rc 1; B, C (collision + crash), D, E (rc 3), F (rc 9), G, I, J (rc 0) wrong |
| round 2 94c734cb | rc 1, passed=276 failed=24 (every new round-3 check) | as main, except 0 rc 0 and A status rc 0 PASS-FULL (the G3 regression) |
| round 3 34f62dbf | rc 0, passed=300 failed=0, no SKIP line | all right (table above) |

H1, H2 and H3 are wrong on all three engines (H3 is unreachable on main and round 2, which refuse CR paths).

## Mutants

**My sample: 24 mutants, run by me in this session** with the committed harness, in two shards of 12 in the
`mutw` worktree (detached 34f62dbf; the six RW rows appended at lines 186-191, nothing else changed). Each shard
first passed its unmutated baseline (`ok baseline: unmutated copy passes the self-test`). Kill rule of the harness:
the self-test exits non-zero AND prints at least one `FAIL ` line.

| Shard | Mutants | Result (SUMMARY line) |
|---|---|---|
| A | G3D, RV4, Q1, Q2, Q3, Q4, Q5, Q6, Q7, Q8, Q9, Q10 | `mutants=12 killed=12 survivors=0 not_applicable=0` |
| B | Q5k, Q5x, Q5c, Q11, Q12, Q13, RW1, RW2, RW3, RW4, RW5, RW6 | `mutants=12 killed=9 survivors=3 not_applicable=0` |

Failing checks per killed mutant: G3D 4, RV4 3, Q1 1, Q2 1, Q3 2, Q4 1, Q5 3, Q6 2, Q7 1, Q8 1, Q9 2, Q10 2,
Q5k 1, Q5x 1, Q5c 1, Q11 3, Q12 2, Q13 1, RW1 1, RW2 3, RW5 1. Survivors: RW3, RW4, RW6.

My six new mutants (drv/rw_mutants.tsv), each aimed at the identity or framing code:

| Id | Mutation | Result |
|---|---|---|
| RW1 | `ident_unknown` stops checking `q.status is None` | killed (1 check: the QuickIdent unit test only) |
| RW2 | the root status value becomes the constant `"s"` | killed (3 checks) |
| RW3 | the root status is hashed even when `git status` fails (no `None`) | **SURVIVED**, not equivalent: end-to-end probe gives a false PASS-FULL (H6) |
| RW4 | `hrec` frames an absent record as `tag0:` (same as a present empty record) instead of `tag-;` | **SURVIVED**, equivalent by reasoning, not by a test: the records tree_state hashes are never empty when present, and an absent known table or excluded lock leads to the same decision as an empty one. Round 4 either adds a test that tells absent from empty or records this equivalence in the mutation file |
| RW5 | the duplicate-path check fires only for status flag `" "` | killed (1 check) |
| RW6 | `uid = path` (args dropped from the unit id) | **SURVIVED**, not equivalent: end-to-end probe gives a false PASS-FULL (H6) |

End-to-end probes for the two survivors (real git, real suites, run on head and on the mutated engine):

- RW3 (drv/status_fail_midrun.sh): head prints `IDENTITY CHANGED before unit tests/a/test_2.sh: root status
  e3b0c44298fc -> ?; no further unit is run` and exits 2 with no RESULT line. That is fail closed and correct, not
  a finding. The mutant runs both units and ends `RESULT: PASS-FULL` rc 0. The precondition was measured:
  `git status` with the unreadable index exits 128.
- RW6 (drv/rw6_crossmode.sh): head's heavy run over the default run's `--out` runs `x/run_all.sh` in full and
  ends `RESULT: FAIL` rc 1. The mutant prints `[1/1] resumed x/run_all.sh (PASS)` and ends `RESULT: PASS-FULL`
  rc 0.

**Author shards (read only, never touched).** Read at 2026-11-05 22:30 CET. All four pids (501756, 501792,
501842, 501874) were still alive, their command lines naming `tests/test_run_full_suite_mutations.sh`. Load
average was 17.4. Each shard passed its baseline. 89 mutants have FINISHED, all killed; none SURVIVED and none
was not applicable. 45 are UNFINISHED. Only finished mutants count as evidence.

| Shard | Finished (killed) | Unfinished |
|---|---|---|
| 0 | M6 M12 M17 M21 M26 M30 M34 R3 X1 X9 V4 V8 E1 E5 S4 T3 O2 D1 S5 Y1 W2 I1 (22) | L2 M30c M30g M30k RF RV2 RV6 Q2 Q5k Q7 Q11 (11) |
| 1 | M1 M7 M14 M18 M22 M27 M31 M35 R4 X3 V1 V5 V9 E2 S1 K1 C1 O5 D2 S6 Y2 W3 (22) | I2 Z4 M30d M30h M30l G3D RV3 RV7 Q3 Q5x Q8 Q12 (12) |
| 2 | M2 M10 M15 M19 M24 M28 M32 R1 R5 X4 V2 V6 V10 E3 S2 T1 C2 O7 D3 S7 Y3 W4 (22) | I3 Z7 M30e M30i RA G3R RV4 RV8 Q4 Q5c Q9 Q13 (12) |
| 3 | M3 M11 M16 M20 M25 M29 M33 R2 R6 X5 V3 V7 V11 E4 S3 T2 C3 O9 D4 S8 W1 W5 L1 (23) | M30a M30f M30j RB RV1 RV5 Q1 Q5 Q6 Q10 (10) |

Of the round-3 rows, only I1 and L1 have finished in the author's run. G3D, RV4, Q1..Q13 are unfinished there
and established only by my sample above. G3R, RV1-RV3, RV5-RV8, M30a-l, I2, I3, L2, Z4, Z7, RA, RB and RF are not
established by anyone in this session.

## Landing plan (trial measured, not landed)

1. Upstream main is b939266a (efe2cc6..b939266a: 11 commits, CON-031 landing, section 11.4.296 cascade,
   continuation doc). Trial merge of 34f62dbf with b939266a (`land`, commit 553f7bd1, throwaway):
   conflicts only in docs/Issues.md, docs/Issues_Summary.md and docs/workable_items.db;
   docs/guides/full_suite_runner_guide.md merges cleanly (main changed only the generated census line, which
   matches the merged tree: no stale-guide problem). `--verify-manifest` on the trial merge: rc 3 with 3
   problems, identical to main b939266a's own run (the two census files without a row and the excluded-lock
   difference are main's). On efe2cc6 the head and main both give the same 25 problems (identical).
2. Take main's three tracker files. Main's CON-030 has `reproduction_state` and `investigation_state` UNSET and
   has no CON-070, so **both** must be applied again through the engine, not only CON-070. Measured on the trial:
   `add Bug Medium --id CON-070 --title ... --description ... --created-by ...` rc 0; `update --id CON-030
   --reproduction-state reproduced-host-fixture --reproduction-surface host-only --reproduction-evidence
   docs/qa/con030_review/con030_reproduction_2026_11_05.txt --investigation-state root-cause-found-with-evidence
   --investigation-evidence ... --states-updated-by ...` rc 0; `validate` OK, 90 items; `sync db-to-md` rc 0;
   `diff --issues docs/Issues.md --fixed docs/Fixed.md` in sync (main now has Fixed items, so `--fixed` is needed).
   Regenerate docs/Issues_Summary.md from `export`. Use the same root-cause text as 34f62dbf, a real
   `--created-by`, and (H5) the parent if the engine gains a way to set it.
3. Not before the engine slice reaches GO. The landing merge message carries G10, G11 and the round-3 trailers.

## Required for GO (round 4)

Section 11.4.276(E)(3): the structural round left two non-minor members of its own class (H1, H2), so round 4
is a structural round again, by a fresh fixer instance, re-running (C) over the whole engine. If round 4 does
not reach GO, round 5 is the recorded operator decision (re-scope, replace, or waive residual LOW only); the
operator may also take that decision now. What would end the class instead of patching members:

1. One reader for every governance table and file the engine reads (manifest, known table, excluded lock,
   roster, guide): bytes or `newline=""`, split on `\n` only, CRLF tolerated, and any other C0/C1 control or
   Unicode line separator in a line refused by name. A lint-style test enumerates every `open(` / `read` /
   `splitlines` in the engine and fails when one bypasses it (with a control needle, section 11.4.273).
2. Structured keys: a unit's key is `(path, tuple(args))` end to end (plan, records, resume, nondeterminism
   grouping); `plan()` refuses two units with one key. Test: the H1 fixture in default mode and the cross-mode
   case, with the `x/gomod` control.
3. One output-escaping function for every path, id, label and gap written to stdout, stderr or summary.txt
   (H3), or refuse CR and other control characters in census names (then the guide line 26 changes).
4. Tests for H2 with NEL, LS and CR and the plain-space control; mutants that restore `splitlines()` in
   `read_roster`, the joined uid and the raw output must be killed.
5. Register H4 as its own item (coverage of ignored files inside submodules; guide line 139), outside CON-030.
6. Adopt RW3 and RW6 verbatim (section 11.4.276(D)) with tests that kill them. For RW3: a run on a clean tree
   whose first unit makes the index unreadable must stop fail-closed. For RW6: a heavy run over a default run's
   `--out`. Either record RW4 as equivalent with its reasoning, or add a test that tells an absent record from
   an empty one. Then run the whole mutation file to the end. The author run that was still going at review
   time does not count for its unfinished rows.

## Evidence (this session, under rv030r3.1XCVj7/)

Sandbox: `scratchpad/rv030r3.1XCVj7/`. Every run used `HOME=$R/home TMPDIR=$R/tmp GIT_CONFIG_NOSYSTEM=1`, and each
fixture is a fresh real-git repository built under `$R/tmp`. Hashes are the first 16 hex digits of the sha256.

| What | File | sha256 (16) |
|---|---|---|
| Self-test on head (rc 0, passed=300 failed=0, 0 SKIP lines) | logs/selftest_on_head.log | 31eba27982dfa590 |
| Self-test, head's tests against the round-2 engine (rc 1, 276/24) | logs/selftest_on_r2.log | efd633a5218c2f86 |
| Self-test, head's tests against the main efe2cc6 engine (rc 1, 262/38) | logs/selftest_on_m.log | 37362a5155879abc |
| Summary of the three runs | logs/selftests_summary.txt | 30a70f9e37700719 |
| Driver for the three self-test runs | drv/selftests.sh | a349cfae39b2a75c |
| Class repro (docs/qa/con030_review/con030_class_repro.sh) on head / round 2 / main | logs/repro_head.txt, logs/repro_r2.txt, logs/repro_m.txt | 5369649e019f8a6c, 0e2ceeeffc165491, 8c6e0bbbc63c7bf9 |
| G3 end-to-end pair (status / other) on three engines | logs/e2e_g3_rerun.txt (drv/e2e_g3.sh, drv/e2e_g3_ctl.sh) | 60176ef28521c031 (48e1ab1f0286ee84, fd667051411295c2) |
| Duplicate mutant-id refusal (exit 2 naming G3D) | logs/dupchk.txt | 13e9469194198b37 |
| H1 default mode + control | logs/uid_collision.txt (drv/uid_collision.sh) | 32beb9886254dea2 (06babca0144d17db) |
| H1 `--include-heavy`, fresh out (correct) | logs/uid_collision_heavy.txt (drv/uid_collision_heavy.sh) | 1c9444a6e2d5c427 (df372e40920904c0) |
| H1 cross-mode (heavy run reusing a default `--out`: false PASS-FULL) | logs/uid_crossmode.txt | 06236621d4b53505 |
| H2 roster NEL / LS / CR + space control | logs/roster_split.txt (drv/roster_split.sh) | bd557f3cf392b608 (e29b017ef8de1a56) |
| H3 CR-forged RESULT lines | logs/cr_forge.txt (drv/cr_forge.sh) | 24da30b6d55b0fb6 (5237a1250bc5831e) |
| H4 ignored file in a submodule + root control | logs/ign_sub.txt (drv/ign_sub.sh) | e77e3600ee496156 (0588354be227047b) |
| H6 / RW3 probe | logs/status_fail_midrun.txt (drv/status_fail_midrun.sh) | dd49b99b8d702513 (9ac1abb4fe0fc3e5) |
| H6 / RW6 probe | logs/rw6_crossmode.txt (drv/rw6_crossmode.sh) | f7fddd25a85ba117 (3ea1e83951fd7571) |
| My mutation shards | logs/mut/shardA.log, logs/mut/shardB.log; per-mutant logs logs/mut/per/ (drv/mutshard.sh, drv/rw_mutants.tsv) | 4a8ae99566f19d25, f98500ca109b8ed3 (2d8efa1969fd2daa, 2275839ff87f02c3) |
| `--verify-manifest`: head and main efe2cc6 (identical, 25 problems) | logs/head_verify_manifest.txt, logs/m_verify_manifest.txt | 0b13a27e75e52d97 (both) |
| `--verify-manifest`: trial merge and main b939266a (3 problems each) | logs/land_verify_manifest.txt, logs/mb_verify_manifest.txt | 05f91489c50744d7, 8613dee76137c8a6 (the problem sets are identical; the files differ only in the tree path) |
| Landing trial merge (conflict list) | logs/landing_trial.txt | a5f138107f5e45df |
| Landing re-mint trial (add CON-070, update CON-030, validate, sync, diff) | logs/landing_remint_trial.txt | 62936fd018d36015 |

A note on the instrument (section 11.4.273). I never read a zero or an empty result as absence without a
control. Every finding fixture has a control that takes the opposite path:

- H1: `x/gomod`, which FAILs.
- H2: a plain space, which is refused.
- H3: grep finds the real RESULT line.
- H4: the same write at the root, which FAILs.
- RW3: head stops.
- RW6: head FAILs.
