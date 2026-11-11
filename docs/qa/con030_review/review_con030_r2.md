# CON-030 independent review, round 2 (section 11.4.209 / 11.4.142)

| Field | Value |
|---|---|
| Item | CON-030 (full-suite runner: submodule paths cut out of `git submodule status` text) |
| Vehicle | vehicle/con030, head fc7e114f7f3441f9728c7daa2d25083623b3638f, 7 commits over main ecfe432 (da9d425, 364f1c0, 8dde551, 805952e, 993fffb, 11c3c3d, fc7e114) |
| Bundle | con030_r2.bundle, sha256 2f4f0c2b8b5abc24864652b37d4958442db8498b37db8b4f98b3aacda9e16d71 (matched before cloning; `git bundle verify` okay) |
| Round | 2 of at most 5 (section 11.4.276(G)) |
| Reviewer | independent subagent, Opus 5.5 (the dispatch path cannot set or report effort, so no effort is claimed, section 11.4.231(F.2)); not the author |
| Sandbox | fresh clone under the scratchpad: `rv030r2.cNaLMS/` (c = main ecfe432 + bundle, head = worktree fc7e114, r1 = worktree da9d425, trial = merge of the vehicle with current upstream main efe2cc6, upm = worktree of upstream main efe2cc6); HOME and TMPDIR inside the sandbox |
| Real repository | read-only commands only (`GIT_OPTIONAL_LOCKS=0`); index mtime unchanged before and after; nothing written there |
| Verdict | **NO-GO** for the engine slice: one important finding, G3, a regression this change introduced that turns a refused run into a false PASS-FULL (measured end to end). The fix is small (one function plus one test). Every other slice is GO or GO-with-follow-ups. Four landing preconditions (L1 to L4) are process steps for the conductor. |

## Verdict in one paragraph

The round-1 blocker F1 is fixed structurally, not instance by instance: paths now come from `git ls-files -s -z`
(NUL-separated, never quoted), and the human-oriented status line is only matched against that exact set. I
built every path shape I could make with real git (40 submodule paths: parentheses in every position, `=`, `?`,
leading/trailing/double space, TAB, CR, FF, VT, NEL, LS (U+2028), non-ASCII, a non-UTF-8 byte; plus nested,
uninitialised, drifted, conflicted and SHA-256 fixtures and 4 newline-path fixtures). The round-2 engine reads
every one of them whole, except the non-UTF-8 path, which is a pre-existing false refusal that main has too
(G1). The tests drive the real engine against real git repositories: RED on the round-1 engine and on main,
GREEN on the head, and GREEN on a trial merge with current upstream main. On the real repository (32
submodules) the main engine and the head give byte-identical results.

The blocker is G3. The cheap fix for round-1 F8 reads the quick identity into a `dict`, and the root's status
field uses the key `status`, which is also the key of a top-level submodule named `status`. When `git rev-parse
HEAD` fails in that submodule (an unborn HEAD in my fixture), its `?` is overwritten, `ident_unknown()` says
False, and the run ends **PASS-FULL** (rc 0). On main the same fixture ends FAIL (identity unknown, rc 1). The
control, the same break on a submodule named `other`, ends FAIL on the head. So the only cause is the key
collision. The full-suite runner exists to never print a false PASS; a regression that turns a refusal into
PASS-FULL is not minor-class, whatever its reach: a PASS-FULL is the evidence a full-suite retest (section
11.4.40) rests on, and section 11.4.276(G.2) keeps proof-of-batch surfaces out of the minor class. I record it as
important. Its reach is narrow (a top-level submodule named exactly `status` whose HEAD does not resolve; the real
repository has none), which is why the fix is small, not why it can wait. Round 3 can be narrow: fix `ident_unknown` (and the collision in
`ident_fields`/`ident_diff`), add the end-to-end case as a test, re-run the mutants that touch the identity code.

## Per-slice verdicts (section 11.4.235(D))

| Slice | Files | Verdict | Open findings |
|---|---|---|---|
| Engine | scripts/full_suite/run_full_suite.py | **NO-GO** | G3 (important, regression of the F8 fix, false PASS-FULL); G1 (minor, pre-existing); G2 (nit part) |
| Self-test | tests/test_run_full_suite.sh | GO-with-follow-ups | G4 (minor), G12 (nit); the test for G3 belongs to the round-3 engine fix |
| Mutation file | tests/test_run_full_suite_mutations.sh | GO | none; the 8 mutants of the mutation file I re-ran (M30a, M30c, M30n, R2, I1, RA, RB, RF) are all killed; round 3 should add a mutant that restores the `dict` check of G3 |
| Runner header + guide | scripts/run_full_suite.sh, docs/guides/full_suite_runner_guide.md (rev 7) | GO-with-follow-ups | G2 (minor, process-doc: the newline claim is broader than measured) |
| Tracker | docs/Issues.md, docs/Issues_Summary.md, docs/workable_items.db (CON-070) | landing precondition | G5, G6, G7, G8 |
| Commit metadata | trailers of da9d425, 8dde551 | process-doc only | G10, G11 |

## Landing preconditions (process steps for the conductor, not code changes)

- **L1 (G5).** Upstream main moved to efe2cc6 on every remote (redpin landed, CON-071..CON-082). The vehicle is not
  a fast-forward any more. A trial merge (`trial`, commit e81d3381) conflicts only in docs/Issues.md,
  docs/Issues_Summary.md and docs/workable_items.db; the guide and the code merge cleanly. Take main's three
  tracker files and mint CON-070 again through the engine with the explicit reserved id, as efe2cc6 did for
  CON-071..CON-082. Measured on the trial merge: self-test passed=263 failed=0 rc 0, and `--verify-manifest` output
  byte-identical to upstream main's (both sha256 b2ebc902...d600).
- **L2 (G6).** CON-070 is reserved for this vehicle (efe2cc6's message says so). The con033 round-2 bundle
  (vehicle/con033 dd8bd9c) mints CON-070..CON-075, so it collides with this vehicle's CON-070 and with main's
  CON-071..CON-075. That is con033's re-mint, not a defect here; land this vehicle with CON-070 and tell con033.
- **L3 (G8, round-1 F10).** CON-030's reproduction and investigation states are still `UNSET` in the DB. Section
  11.4.294(D) asks for them before the fix counts; the author left this to the conductor because the engine needs
  an evidence path that resolves in the repository. Track the evidence under docs/qa/ (the redpin pattern,
  docs/qa/redpin_review/) and then set `reproduced-host-fixture` with surface `host-only` and
  `root-cause-found-with-evidence`. The decisive experiment exists: the same fixture gives truncated paths and
  bogus gaps on main, describes swallowed on round 1, and whole paths with 0 gaps on round 2 (author's
  diff_fixture.txt, and my class fixture below).
- **L4 (G7).** CON-070's text cites host-local paths (`scratchpad/review_con030.md`,
  `/home/milosvasic/.cache/claude-tmp/c30r2.eVpCZG`). Those do not resolve in a clone (section 11.4.215). When it is
  minted again in L1, cite tracked copies instead and set its parent to CON-030.

## Findings

Severity from the closed set critical / important / minor / nit; layer per section 11.4.235(D).

| Id | Severity | Layer | Where | Finding | New in this round? |
|---|---|---|---|---|---|
| G1 | minor | source-defect | run_full_suite.py, every `decode(errors="replace")` of a path | A submodule path that is not valid UTF-8 (`bad\xffname`) is decoded to U+FFFD, the decoded name does not exist on disk, `git -C` fails, and the run is REFUSED-TOPOLOGY with "recorded commit ... is not in its object store" (rc 9). False refusal, fail-closed direction (section 11.4.201(1)). Main does the same: pre-existing. Same root class as CON-030 (a path is not the bytes git gave). Fix: decode with `surrogateescape` (os.fsdecode) and pass the str back to the OS unchanged. Not in CON-070's list; register it there or as its own item. | pre-existing, not tracked |
| G2 | minor | process-doc | guide rev 7, runner header, docstrings of parse_sub_status and the author report | The texts say a path with a newline "is a gap (fail closed)". Measured counterexample (nlD): submodules `a`, `b` and `a\n <40-hex> b` all at one commit; each fragment of the newline path's status line equals a known path, so it parses as `a` and as `b`: 0 gaps, sub_paths `['a','a','b','b']`, topology counts 4 submodules for 3. The newline submodule is missing from quick_ident: when it is already drifted at the start (which topology reports as a `+` gap, mislabelled `a`, so a run needs `--allow-topology-gaps`), a further HEAD move is not seen by quick_ident (measured), but tree_ident still changes (measured), so I found no wrong PASS. The guide's sentence "Known cases that end this way (fail closed, never a wrong PASS): a path that contains a newline" is therefore not true as written. The other three newline fixtures (nlA/B/C) do give gaps. Fix (cheap): treat any known path containing `\n` as a gap directly, and/or gap on a duplicate path in the parsed set; then the doc claim becomes true. | new |
| G3 | **important** | source-defect (regression of the round-1 F8 fix; evidence surface) | run_full_suite.py:2283-2298, ident_fields / ident_unknown / ident_diff | The root's status field is keyed `status`, the same key as a top-level submodule named `status`. `dict()` keeps the last value, so `ident_unknown()` cannot see a `?` in that submodule's field. Unit level (stk.py, stkq.py): `ident_unknown` False while `"?" in q` (the old check) is True. End to end (drv/e2e_g3.sh): submodules `plain` and `status`, HEAD of `status` made unborn so `rev-parse HEAD` fails there (precondition checked); topology 0 gaps. Main runner: `IDENTITY CHANGED ... RESULT: FAIL`, rc 1. Head runner: `RESULT: PASS-FULL`, rc 0. Control (drv/e2e_g3_ctl.sh), the same break on a submodule named `other`: head `RESULT: FAIL`, rc 1. ident_diff also reports a moved `status` submodule with the root status hash values (detected, but mislabelled). Fix: decide `?` over the list of `<path>=<value>` lines (for example `any(x.rpartition("=")[2] == "?" for x in q.split("\n"))`), and stop keying the root status field with a string a path can be (or compare the two identities line by line, since both use the same `subs` list); add the end-to-end case and its control as tests, and a mutant that restores the dict check. | new |
| G4 | minor | test-instrumentation | tests/test_run_full_suite.sh | Six of my eight reviewer mutants survive the suite, and none is equivalent (section 11.4.194(6)(d)): RV1 (drop `rest.endswith(")")`) and RV2 (drop `d and`) make a false gap on a describe-less ` ` line (`x (yz` / `x ()` with `x` also known, drv/rv12_disc.py); RV4 (drop the `.git` check) makes `known_sub_paths()` run away, 1311 git calls on one fixture (logs/rv4_probe.txt); RV7 (`splitlines()` in ident_fields) names a CR-class path wrong in IDENTITY CHANGED; RV3 and RV8 survive because no test starts a run whose identity already holds `?` (the same gap is on main: RV3mU and RV3mE survive there), which is the gap G3 went through. RV3/RV8 are covered by the round-3 G3 test; the other four need table rows or exact-set asserts. All six fail closed or affect messages and cost, not a verdict, so they can follow (minor). | new |
| G9 | nit | source-defect (class inventory) | scripts/deps_manifest/helix_deps_manifest.py:318-325 | Reads `.gitmodules` with `git config --get-regexp` text, `splitlines()`, a regex and `.strip()`, so a path with leading/trailing space, a CR-class character or a newline is read wrong. Same class as CON-070's members, not listed there. Add it to CON-070. | new |
| G10 | nit | process-doc | trailers of da9d425 and 8dde551 | `Co-Authored-By: Claude Sonnet 5.5`, while the work ran on Opus 5.5 (the author says so). History is not rewritten; record the correction in the landing merge message. | known (author flagged) |
| G11 | nit | process-doc | merges 364f1c0, 11c3c3d, revert 993fffb | No `Roadmap-Item:` trailer (section 11.4.293(A)). The fix also touches the guide and the runner header, which are outside CON-030's declared file-scope manifest, with no `Out-of-scope:` trailer; both are the runner's own documentation, so the reason is `fix-gate-or-test`-adjacent at most. Record both in the landing merge message. | new |
| G12 | nit | test-instrumentation | tests/test_run_full_suite.sh | Three shapes are checked only by me, not by the suite: a nested uninitialised path with parentheses (`nest (ed)/in (ner)`), a real-git `U` line on a spaced path (`con (flict) )`), and a real SHA-256 superproject (the suite has a 64-hex table row only). All three are correct on the head (fixtures st3, u4, s256). | new |

G5..G8 are the landing preconditions L1..L4 above.

## Required for GO (round 3)

1. G3: `ident_unknown()` must see every `?` field, whatever the submodule is called; `ident_fields()`/`ident_diff()`
   must not merge a submodule `status` with the root status field. Tests: the end-to-end case of drv/e2e_g3.sh (a
   submodule `status` whose HEAD does not resolve) must end FAIL, with its control (`other`); a mutant that puts
   the `dict` check back must be killed.
2. Re-run the identity mutants (I1, RV3, RV8 and the new one) on the fixed engine.
3. Section 11.4.276(E)(3): round-1 F8 (nit) and G3 (important) are one class, in-band keys and sentinels in the
   flat `<path>=<value>` identity string, so round 3 is a structural round, not another patch on the string. The
   quick identity is in memory only (built at line 2265, read at 3152, 3216-3218 and 3280-3283, never persisted),
   so the replacement is cheap: let `quick_ident()` return an ordered tuple of `(path, value)` pairs with the root
   fields under names a path cannot be (or in a separate field), compare the tuples, test `?` over the values,
   and diff by position (both identities use the same `subs0` list). Enumerate the consumers again after the
   change (today they are the lines listed above).

Follow-ups that may stay open (minor/nit, section 11.4.276(G.2)): G1, G2, G4, G9, G12; the process notes G10 and G11
go in the landing merge message. Fixing G2's doc sentence (or the two-line duplicate/newline gap) in the same round
is cheap and would make the guide true.

## Round-1 findings: status

| Round 1 | Status in round 2 | Evidence |
|---|---|---|
| F1 (important, regression: describe with `(`/`)` swallowed into the path) | fixed, structurally | class fixture: all 40 path shapes whole on head (cls_head.json); main 24 gaps, round 1 17 gaps on the same fixture; describes `heads/feat(x)`, `v1(beta)`, `v2)`, `(v3`, `heads/a)b(c`, `v9~1` all parsed |
| F2 (`splitlines()` splits on CR, FF, VT, NEL, LS ...) | fixed | `cr\rx`, `ff\x0cx`, `vt\x0bx`, `nel\x85x`, `ls\u2028x` whole on head; round 1 lost all five |
| F3 (false claim "git cannot record a newline") | fixed, but the replacement claim is too broad | see G2 |
| F4 (`submodule_paths()` split by whitespace) | fixed | head `submodule_paths` equals the 40-path known set exactly on the class fixture |
| F5 (class members in other tools) | registered as CON-070, not fixed (scope) | G9 adds one member; L1/L4 for the registration |
| F6 (reviewer mutants RA, RB, RF survived) | fixed | RA, RB, RF killed here (Mutants) |
| F7 (new gap undocumented) | fixed | runner header + guide rev 7 |
| F8 (in-band sentinels in the quick identity) | fixed for `?` and `=` in a path, but the fix introduced a new collision that gives a false PASS-FULL | G3 (important) |
| F9 (unused argument, shim-only test, mutant naming) | fixed | real-git newline fixture in the suite; header note on mutant ids |
| F10 (reproduction/investigation states) | not done (left to the conductor) | L3 |
| F11 (old mutant R2 survived: ignored file written by a suite) | fixed | R2 killed here (2 FAIL lines) |

## Class enumeration (section 11.4.276(C)), real git

One superproject with 40 initialised submodules plus nested, uninitialised, drifted, conflicted and SHA-256
fixtures, all built with real git (drv/mkfix.sh, drv/mknl.py). git itself refused to record `crt\r` (trailing CR)
and `?` alone as paths, so those two are not reachable. Result per engine (sub_paths contains the path whole):

| Path shapes | main ecfe432 | round 1 da9d425 | round 2 fc7e114 |
|---|---|---|---|
| `(`, `()`, `(x)`, `)`, `=`, `=b`, `a=`, `k=v`, `par(1)`, `q?`, `status`, `plainf` | whole | whole | whole |
| `  two`, ` (a)`, ` lead`, `a\tb`, `a  b`, `a (b c)`, `a (b) (c)`, `a b c`, `b (c`, `sub dir`, `trail `, `tt\t`, `x (`, `x ()`, `x (xyz)`, `x )`, `ünï cødé` | not whole | whole | whole |
| `cr\rx`, `ff\x0cx`, `vt\x0bx`, `nel\x85x`, `ls\u2028x` | not whole | lost (splitlines) | whole |
| `plainb` (describe `heads/feat(x)`), `plainc` (`v2)`), `plaind`, `plaine`, `plaint` (`v1(beta)`) | whole | path swallows the describe (F1) | whole |
| `bad\xffname` (not UTF-8) | false gap | false gap | false gap (G1) |
| nested uninitialised `nest (ed)/in (ner)`, drifted `dr (ift)` (describe `heads/w(x)`), conflicted `con (flict) )` | cut | drifted path swallows `(heads/w(x))`, nested path cut to `nest (ed)/in` | whole, right gap kind |
| SHA-256 superproject (`plaint`, `sub dir`, `x (xyz)`) | paths cut, 2 false gaps | `plaint (v1(beta))` swallowed, 1 false gap | whole, 0 gaps |
| newline paths nlA, nlB, nlC | silent, wrong paths | at least one gap each | at least one gap each |
| newline path nlD (fragments equal known paths) | silent | silent | silent, duplicates (G2) |

End to end through `scripts/run_full_suite.sh` on a 32-submodule copy of the class shapes: head PASS-FULL with
`gaps=0`; round 1 REFUSED-TOPOLOGY with 10 gaps. Non-UTF-8 path alone: REFUSED-TOPOLOGY rc 9 on main and on head
(G1). Plain control: PASS-FULL on both.

## Section 11.4.289 (tests drive the real engine)

The new CON-030 checks import the real engine file and run it against repositories made with real git (`git
submodule add`, `update-index --cacheinfo`, a hand-written `.gitmodules` for the newline path). The precondition checks assert
that git itself printed the describe shapes before the engine is judged. The parse table and the shim test are
gate-logic unit checks on top, labelled as such. No stub stands in for git in any check that claims a path is read
whole.

## RED before, GREEN after

| Run | Result | Log sha256 |
|---|---|---|
| head tests on the head engine | passed=263 failed=0, rc 0 | 27ede160...79b4 |
| head tests on the round-1 engine (da9d425) | passed=253 failed=10, rc 1; all 10 failures are CON-030 r2 checks; the precondition checks and R2b pass | 2d437b99...3030 |
| head tests on the main engine (ecfe432) | passed=248 failed=15, rc 1; all 15 failures are CON-030 checks | 2b196017...7097 |
| trial merge (vehicle + upstream main efe2cc6), its own tests | passed=263 failed=0, rc 0 | see Evidence |

The author's RED/GREEN log hashes match the values in their report.

## Mutants

Driver drv/mymut.sh applies one row to a copy of the engine (the anchor must occur exactly once), runs the head
suite with `FSR_RUNNER` pointing at the copy, and counts a mutant killed only on a non-zero exit with at least one
`FAIL` line. Every shard first ran the unmutated copy (baseline ok in each shard). All 111 author anchors and my 8
apply exactly once on the head engine. Host load was about 35 to 45 on 16 cores, so I re-ran a subset of the
author's mutants (shard 3 was stopped by me after M30a and M30c to free CPU; its rc 15 is that stop).

Mutants of the mutation file re-run here (the author's, plus R2, RA, RB, RF from round 1):

| Id | Change | Result |
|---|---|---|
| M30a | sub_paths back to `split()` | killed (7 FAIL) |
| M30c | topology back to `split()` | killed (8 FAIL) |
| M30n | `ident_unknown` back to `"?" in q` | killed (2 FAIL) |
| R2 | drop the end-of-run tree check (round-1 survivor, F11) | killed (2 FAIL, R2b) |
| I1 | unit-site identity check `if False:` | killed (3 FAIL) |
| RA | only 40-hex shas (round-1 survivor, F6) | killed (1 FAIL) |
| RB | keep `-` lines in sub_paths (round-1 survivor, F6) | killed (1 FAIL) |
| RF | `.strip()` the parsed path (round-1 survivor, F6) | killed (3 FAIL) |

Reviewer mutants written for this round (the author did not write them):

| Id | Change | Result | Reading |
|---|---|---|---|
| RV1 | drop `and rest.endswith(")")` | SURVIVED | not equivalent: false gap on a describe-less ` ` line `x (yz` with `x` known (drv/rv12_disc.py); G4 |
| RV2 | drop `d and` (empty describe) | SURVIVED | not equivalent: false gap on a describe-less ` ` line `x ()` with `x` known; G4 |
| RV3 | `ident_unknown` returns False | SURVIVED | the suite never runs a start identity that already holds `?` (qid equal to qid0); the same gap exists on main (RV3mU and RV3mE below). This gap is why G3 was not caught. The G3 control case kills it (measured: with RV3 applied, the control run ends PASS-FULL rc 0 instead of FAIL, logs/e2e_g3_ctl_rv3.txt) |
| RV4 | recurse into every gitlink, `.git` or not | SURVIVED | not equivalent: inside an empty gitlink directory `git ls-files -s -z` prints the gitlink itself as `./`, so without the check the recursion runs away until the path is too long. Measured on fixture st3: 1306 bogus `.../in (ner)/./` entries, 1311 git calls, 5.8 s for one call (logs/rv4_probe.txt). The verdicts stay right, which is why the suite passes; the cost does not. Nit: assert the exact `known_sub_paths()` set on a fresh clone and on a nested uninitialised path (G4, G12) |
| RV5 | `rfind(" (")` to `find(" (")` | killed (5 FAIL) | |
| RV6 | `submodule_paths` strips the value | killed (1 FAIL) | |
| RV7 | `ident_fields` uses `splitlines()` | SURVIVED | not equivalent: a CR-class path is named wrong in IDENTITY CHANGED (`x` for `cr\rx`), and an exotic path `p=?\rz` reads as unknown (measured in-process); message-level, nit (G4) |
| RV8 | `ident_diff` drops the `?` clause | SURVIVED | the IDENTITY CHANGED message would no longer name a field that is `?` at both ends (on the control case head prints `other ? -> ?`; main, which lacks the clause, prints an empty name). Same root gap as RV3; a test on the G3 control message kills it. Nit (G4) |
| RV3mU | main engine: unit-site `or "?" in qid` dropped | SURVIVED on main's own suite (239/0) | pre-existing test gap |
| RV3mE | main engine: end-site `or "?" in qid` dropped | SURVIVED on main's own suite (239/0) | pre-existing test gap |


## Differential on the real repository (read-only)

`/home/milosvasic/Projects/constitution`, 32 submodules, `GIT_OPTIONAL_LOCKS=0`. Main engine and head engine:
sub_paths, topology (n=32, 0 gaps), submodule_paths (27), quick_ident fields: byte-identical (both sha256
9a921bf6...d7dab9; `known` = 32 paths, 0.35 s). `--verify-manifest`: rc 3 and the same 25 problems on both, stdout
and stderr byte-identical (086214c2...b8517d / 4790be15...fcf). The real index mtime did not change. The porcelain
count was 1 before and after (an entry already there before my reads; these reads write nothing).

## Other users of the same git output (census)

Other `git submodule status` users in the tree pass a fixed path, so the path is not parsed from the text. Most
`ls-files -s` users read only the sha. The one new member is G9 (helix_deps_manifest.py). The members already in
CON-070 were not re-measured beyond what the author reported.

## Evidence (this session, under rv030r2.cNaLMS/)

| File (under rv030r2.cNaLMS/) | What | sha256 |
|---|---|---|
| logs/green_head.log | head suite on head engine, passed=263 failed=0 rc 0 | 27ede160be0ef0b9af7f590a86ffcbb7377533098d6098811554000e3b0979b4 |
| logs/red_head_on_r1.log | head suite on round-1 engine, passed=253 failed=10 rc 1 | 2d437b99d9f6e5bfeb0e3bb8e4e6ef45721ac150694afe5cf14ef8a1c7e23030 |
| logs/red_head_on_main.log | head suite on main engine, passed=248 failed=15 rc 1 | 2b1960171b05e94dc21a4b1554dd4c9f6dc707788a0e7664e245f8c210097887 |
| logs/selftest_trial_merged.log | trial merge (vehicle + efe2cc6) own suite, passed=263 failed=0 rc 0 | 94d01b73311fac9d0dcab14820f17dfd8ddcf438579a77f884fa52ace30c1eaf |
| logs/trial_merge.log | trial merge conflicts: 3 tracker files only | 0092e33932b63645851a7ab27718fe7df301357f3826b44a004297f0b3cb8191 |
| exp/cls/status.txt | real `git submodule status --recursive` of the class fixture | 1a9ba8bf48abdc9f270e2c5990612dcb1c948f9ea57d6ed12b9f267e01f8f9b4 |
| logs/cls_c.json / cls_r1.json / cls_head.json | class fixture probe, main / round 1 / head | 6f58a9f80716c0bf48c627801e881da07ff4470bb35de9903a9bc7b17bfc8766 / b0266b0a3c5cb8442f8c4831d08e729d458f40ac3ba50e0f2c077a9fcaf3df98 / c4c0c972229aac7abff195cc026053706a218181532d9f54cba0b54abe44afcf |
| logs/fx_nlD_head.json | newline path nlD on head: 0 gaps, sub_paths a,a,b,b | e05611f6f8b6162521ddc096d7a730cb36a0c40e1a2ca55df038ad033f27ed61 |
| logs/nlD_move_head.txt | nlD: HEAD move of the newline submodule, quick_ident vs tree_ident | 5b4324de92a70e0af824f2ff5953199ffec2bd11f17116102000347346ea2f7d |
| logs/fx_nlA_head.json / fx_nlB_head.json / fx_nlC_head.json | newline paths nlA/B/C on head: gaps present | 9d8fdb2b04f23315a6d4e78510756b29e5e4ce719d6c0e8f2e4a005f45d5999a / e265d1456774187e7a63ee1b426e7a6bcf490832f2fa27045e6de6ac6c2d0b5a / 4fc36c3f328ce5ed33128b5874986537e1bd5bd56ab1119df11a95584de2a9ec |
| logs/fx_s256_root_head.json / fx_st3_root_head.json / fx_u4_root_head.json | SHA-256, nested/drifted, real `U` fixtures on head | f9e73e3d6fd8b0f127977efe0c49eaa8c28e40f6f065bee1d096b35b0958799d / 1f683453b0238d9e8f27d183433c5c1de76b5782c52ae3a44baa43a26eec526e / 8232c46b47cbd1cdadd5a7a29ad8dff3068d3145be2a2278925435558516fc51 |
| logs/fx_*_r1.json, logs/fx_*_c.json | the same fixtures on round 1 and on main | s256 r1 e16bbf31...def2, st3 r1 1727ebd7...ef1b, u4 r1 ab9db02b...bbb9, s256 main 1e39f2ba...feea, st3 main 8dda20a3...efcb2, u4 main 9e001149...19c2 |
| logs/stk_head.txt / stk_c.txt | `status` key collision (G3) | 5df2a9e8f2653b79a489dcfcfd2fafda16f8f2d08e0d93fda2c59a440e41e084 / 8bd307ccfaf36d6e6476e61ebd6949b8a5159c6c8985d8558da5b2d876597441 |
| logs/rv12_disc.txt | discriminating inputs for surviving RV1/RV2 (G4) | 1bbf350e1af09f720a51733240c0297e4d8e73d11593a0e228733e4058b42509 |
| exp/e2e_cls_head/run.log / e2e_cls_r1/run.log | end to end, 32 class-shape submodules: head PASS-FULL gaps=0 / round 1 REFUSED-TOPOLOGY | 7aefdadba9afdc2cf75a99cd68981ed33a4938085d314875e446e7e78ac5a862 / 4fed8839cdf62151d82c3fb7b24eb53147c64dd5cee0535a52448625648b5f23 |
| exp/e2e_u8_c/run.log / e2e_u8_head/run.log | non-UTF-8 path: REFUSED-TOPOLOGY on main and head (G1) | 5fd0e26f10830c5d5ee9f8102e20ce6424678de92b8d604ba13db87f46b354de / de9317e0b1a5b266c7385cd73617ccbbec2c67625405060c09f09fa1ea297525 |
| exp/e2e_pl_c/run.log / e2e_pl_head/run.log | plain control: PASS-FULL on both | deacee19c982e0cdca483be38fd627a5642f3ce3265cb3287fcb8feb907a3144 / a190f2fee559d3078b45712fcccc7324e4966d641331110b02fe990fe7d23e16 |
| logs/real_main.json / real_head.json | real repository differential, identical | 9a921bf6128c0e5422a67413c2b019a8c0055f09711be7a0737eded7d7c6dab9 (both) |
| logs/vm_c.out+err / vm_head.out+err | `--verify-manifest` on the real repository, identical | 086214c2206ddbbd6fe4761b2f55d91e5816b13f49a872a864c82e3b65b8517d / 4790be1500aaebfd6e40672eb605a84fef87eb9f1d3db1998fc95cac38b5efcf (both engines) |
| logs/vmt_trial.out / vmt_upm.out | `--verify-manifest` on the trial merge and on upstream main, identical | b2ebc9023878ef7ffe31aeb73ede9281bf1e1ee997ab368878c29f41ecffd600 (both) |
| drv/probe.py, mkfix.sh, mknl.py, stk.py, nlmove.py, rv12_disc.py, e2e.sh, realdiff.py, mymut.sh | reviewer drivers | 4130931a...c82f, 220967da...b4c6, cd8f75a3...eea5, 6155f066...3913, 56483765...58df, 65b41dd2...5422, bbaa339d...23cb, db4da283...35573b1, a5400f06...10d7 |
| drv/rv_mutants.tsv / rv_main_mutants.tsv / all_mutants.tsv | reviewer mutants (head / main engine) and the combined row file (111 author rows + 8 reviewer rows) | ad46041e017c6c20607d80857b5bd31941171331aaa7b4b2fc67671f379573a1 / 79fed3852eb66dfa1879a2ac858202850e05a4e4efc91775f5441d8c2da18159 / ca5431bf40ff5f17639458cac8f7a7b52ae6e0787104543648c5c1a3160dccb7 |
| drv/e2e_g3.sh, logs/e2e_g3.txt | G3 end to end: main runner FAIL rc 1, head runner PASS-FULL rc 0 | 48e1ab1f0286ee84a4cfd5190a7b43d9f39fe5202563c83287bcdb2d0e682298, 5580dae0e9756f1f0cd04e72286df39bec0b2fea38e26daa5c25a531b93fd356 |
| exp/e2e_g3_c/run.log / e2e_g3_head/run.log | the two runs | f67323fc284cafffb379fb14de2bd4602edd83d6f665be65325e8ac89b08e77c / 690233305e2db4e66d01d647995f669b80efc8884012092e94bf2480cd78c2af |
| drv/e2e_g3_ctl.sh, logs/e2e_g3_ctl.txt, exp/e2e_g3ctl_head/run.log | G3 control (`other`): head FAIL rc 1 | fd667051411295c249fcc251123da2bb55fb89b93cfb85d2252fcb07798efe6d, 503e1cf89fa884b6151c3ea1924af20cff6a53abc9835c202bcefe006dcb39cf, 977e20a8249d7e6b58cd11283bc8b9a784b11862ca813b2e4ede3f2ad6132c6a |
| logs/mut_s1.log | RV1, RV2, RV3, RV4: all SURVIVED (baseline ok) | d1b322fabdb2af302aa130768a5c20d362f9b92537152ad40d0022970d9fb4df |
| logs/mut_s2.log | RV5, RV6 killed; RV7, RV8 SURVIVED (baseline ok) | 87b55430681d2b7a616d3458e947aac1e162b7a624a2bb6475328e827d193a02 |
| logs/mut_s3.log | M30a, M30c killed; then stopped by me (rc 15) | 3a8ea29e16e382497205373eecbd24e046c591e3379a052447201d459835c893 |
| logs/mut_s4.log | R2, I1, M30n, RA, RB, RF killed (6/6, baseline ok) | 5b8240acd947d30b4f77199968b0b8fd618e372d1de8b047907d55eaab595bc7 |
| logs/mut_s5_main.log | main engine with main's suite: RV3mU, RV3mE SURVIVED (baseline ok) | bc8706c0c11ec53b1c2ec86d4c162e44a0145916838b1a641d9a5b2be163cfc7 |
| logs/rv4_probe.txt, logs/rv12_disc.txt | surviving-mutant effects (RV4 runaway, RV1/RV2 false gaps) | cfbd281088013ce2e47c92988617dd91d356da4dd4a25a2aaf3053113bc84fc5, 1bbf350e1af09f720a51733240c0297e4d8e73d11593a0e228733e4058b42509 |
| logs/e2e_g3_ctl_rv3.txt | the G3 control case on an RV3-mutated copy: PASS-FULL rc 0 (so the control kills RV3) | a48fc409db25d6f1dbe58b03c17b53941f579772f314164a03a993dbe0b2a916 |
| drv/stkq.py, logs/stkq_head.txt | G3 unit level with an unborn HEAD: topology 0 gaps, `status=?` masked | 3240dae1e6e8a9a2c63b996bda6b5202c0e33e55f9ab797452287c1bcf7caa65, dcf39b87799ff2ffbdc930c6abbf628c7fcc19dfd677239c798026c45416533f |
