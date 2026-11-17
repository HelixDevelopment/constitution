# CON-046 review, round 5 of 5 (final round of the 11.4.276(G) budget): vehicle/con046

| Field | Value |
|---|---|
| Subject | bundle `con046_r5.bundle`, range ecfe432..vehicle/con046, head 870ddf24b5c3efdfde49d84654ef6872db0e0e7a |
| Reviewer | independent review agent (11.4.142 / 11.4.209), model claude-opus-5-5. The reasoning effort was not reported to me, so I do not claim xhigh (11.4.231(F.2)) |
| Verdict | **NO-GO.** There is one blocking finding, R5-1 (important, source-defect, proof-of-batch). Every other finding is minor-class |
| Why it blocks | Six of my nine mutants survive the author's full suite: NM1–NM5 and NM9 (section 5). Each one restores a defect that the gate header says the gate prevents. This is the same class as round-4 M-4, so it is a reappearing finding (11.4.276(E)(1)). Round 5 is `R_max`, so under 11.4.276(E)(3) the item stops and goes to a recorded operator decision (section 10) |
| What is right | On every probe I ran, the gate's runtime behaviour matches its header, with one exception: A3, the textconv leak (minor). The round-4 fixes (M-4 killers, M-1, M-2, N-4) and the RED and GREEN results reproduce. What fails is the proof, not the behaviour |
| Landing | Not landed, nothing pushed, no hook installed anywhere. All work was done in a fresh clone with a sandbox HOME and TMPDIR |

## 1. Setup and integrity

All paths below are under `R=/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv046r5.FRc3WD` (it is also recorded in `scratchpad/.rv046r5_root`).
- `R/repo` is a clone of the bundle at vehicle/con046. It holds my untracked harness copies in `scripts/gates/rv_*.sh`.
- `R/repo_static` is a clean clone used for the static gates.
- `R/r4/gate_r4.sh` is the round-4 gate, taken from 93de0fe.
- HOME is `R/home` and TMPDIR is `R/tmp`.

The sha256 of the gate (a1bdc35a…aa16), the test (51254b30…70b8) and the hook (95fa276c…f598) match the author's `scratchpad/con046r5/full_try1_sha256.txt`.

`.submodule_pin_gate.conf` was named in the brief, but it is **not in the tree** at 870ddf2. The gate reads it from the base commit, so the defaults apply (max_waiver_days 30, item_prefix CON). This is an observation, not a defect.

## 2. RED, GREEN, static gates

- **RED.** I ran the new test against the round-4 gate (`GATE_UNDER_TEST=R/r4/gate_r4.sh`). It exited 1 after 149 s.
  - Four tokens differ from want:
    - TREEMISS 0/A/missing/0 (want 1/B/missing/1)
    - SHALLOWSUP 0/A/true/0 (want 1/B/true/1)
    - STASH 1/B/kept (want 0/A/kept)
    - N4INDEX 0,0 (want 0,1)
  - The hook end-to-end line is unchanged.
  - This reproduces the author's `red_r5_new_test_vs_r4_gate.out`.
  - File: `R/out/red_vs_r4.out`.
- **GREEN, Part 1.** The vector equals want in three independent runs:
  - the author's full run;
  - my m31–m72 run;
  - my NM run.

  All three are byte-identical, which gives N=3 for the Part 1 vector (11.4.50). Part 3 (the hook end to end) is identical in all three runs. My m31–m72 run exited 0.
- **shellcheck 0.11.0 `-S warning`:** clean on all three files. `bash -n` is OK.
- **Env-reads gate** (`R/out/envledger.out`). Both revisions PASS with uncovered=0:

  | Revision | gates | reads |
  |---|---|---|
  | head | 188 | 170 |
  | ecfe432 | 187 | 170 |

- **Ledger ratchet:** PASS on both revisions, unimplemented 394 = baseline 394.

## 3. Mutants m31–m72, completed by the reviewer

I ran m31–m72 myself with MUT_JOBS=4 on an untracked copy of the test. The copy adds only MUT_FROM/MUT_TO filtering and copies the vectors out. Part 1 and Part 3 ran in full.

- Log: `R/out/suite_m31_72.out`
- Vectors: `R/out/mut31_72/`

This run duplicates m31–m32 from the author's run. The author's own full run also finished after hand-back: 72/72 killed, exit 0, 1814 s (`scratchpad/con046r5/green_full_r5_try1.out`). Each of m31–m72 therefore has two independent kill results.

Columns: **m** is the mutant number, **killed by** is the token that changed (want → got).

| m | Mutant | Killed by |
|---|---|---|
| 31 | RM8-scope-branches-only | K8TAG 1/B→0/A, K14WT 1/B→0/A, K10LAZY …/1→…/0 |
| 32 | RM9-super-replace-honoured | K9REPL 1/B→0/A |
| 33 | RM10-super-lazy-fetch | K10LAZY 1/absent/absent/1→1/absent/present/0 |
| 34 | RM11-spent-ignores-path | K11PATH 0/A→1/B |
| 35 | RM12-spent-ignores-old | K12OLD 0/A→1/B |
| 36 | RM13-spent-cannot-tell-is-unspent | K13TELL 1/B→0/A (also CHILDTREE, BADREF, K10LAZY, TREEMISS, SHALLOWSUP) |
| 37 | RM14-single-worktree | K14WT 1/B→0/A |
| 38 | M1-tree-missing-is-absent | TREEMISS 1/B/missing/1→0/A/missing/0 |
| 39 | M1-shallow-superproject-unchecked | SHALLOWSUP 1/B/true/1→0/A/true/0 |
| 40 | M2-stash-counted | STASH 0/A/kept→1/B/kept |
| 41 | N4-head-always-excluded | N4INDEX 0,1→0,0 |
| 42 | waiver-ignores-old-sha | OLDBIND, K12OLD |
| 43 | waiver-ignores-new-sha | WRONGSHA |
| 44 | waiver-ignores-path | TWOSUB, NUMPATH, K11PATH |
| 45 | R3n1-numeric-compare | NUMPATH |
| 46 | RM4-extra-fields | FIELDS8 |
| 47 | six-field-rows | FIELDS8 |
| 48 | RM5-first-bad-row-aborts | DUPROW 0→1 |
| 49 | cr-not-named | CRLF 1/1→1/0 |
| 50 | waiver-from-worktree | UNTRACKED |
| 51 | waiver-ignores-expiry | EXPIRED |
| 52 | expiry-boundary | TODAY |
| 53 | expiry-format-unchecked | BADEXP (7th) |
| 54 | horizon-unchecked | BADEXP (6th), HORIZON, CONF |
| 55 | horizon-boundary | HORIZON 0,1→1,1 |
| 56 | item-format-unchecked | NOTRACK, PREFIX, BADITEM |
| 57 | item-prefix-hardcoded | PREFIX 0,1,1→1,0,1 |
| 58 | config-from-index | CONF 0,1→0,0, KCONF |
| 59 | config-error-ignored | BADCONF 1,0→0,0, KCONF |
| 60 | RV1-config-unreadable-as-absent | KCONF (1st) |
| 61 | RV3-duplicate-key-allowed | KCONF (2nd) |
| 62 | RV4-prefix-unvalidated | KCONF (3rd) |
| 63 | RV5-365-cap-removed | KCONF (4th) |
| 64 | RM1-ident-guard | IDENT 1→0 |
| 65 | self-authoriser-allowed | SELFAUTH 1,1→0,0, AUTHNORM |
| 66 | R3n4-failure-reported-as-self | PYFAIL 1/1/0→1/0/1 |
| 67 | no-casefold-no-nfc | SELFAUTH 1,1→1,0, AUTHNORM |
| 68 | casefold-without-nfc | AUTHNORM (6th) |
| 69 | authoriser-form-unchecked | AUTHNORM (1st, 2nd) |
| 70 | empty-authoriser-allowed | NOAUTH 1→0 |
| 71 | author-not-compared | AUTHNORM (3rd, 4th) |
| 72 | help-truncated | HELP 2→0 |

**Result: 42 of 42 killed, no SURVIVED line, no "produced no vector", exit 0, 1514 s.** The Part 1 vector equals want, and Part 3 (the hook end to end) is unchanged: `plain downgrade rc=1 forward rc=0 downgrade-after rc=1; real-submodule worktree forward rc=0 downgrade rc=1; persist rollback rc=0 fwd rc=0 snapshot rc=1 pin=B; layout-skip rc=0`.

M-4 is closed. Each of RM8–RM14 is killed by the killer the round-4 review named, and K8TAG, K14WT, K9REPL, K11PATH, K12OLD, K13TELL and K10LAZY each kill at least one RM mutant. RM8 is killed by K8TAG, K14WT and K10LAZY, as the author reported. Every row above also matches the author's run.

## 4. The round-5 fixes, checked one by one

- **M-1 (missing tree object).** `blob()` now runs `cat-file -e <c>^{tree}` first and returns rc 2 when the tree is missing.
  - TREEMISS gives 1/B/missing/1, and mutant m38 is killed.
  - My control NM7, which uses `cat-file -e "$1"` without `^{tree}`, is not killed by any of my probes (none of them removes a tree). The author's suite kills it (TREEMISS 1/B/missing/1→0/A/missing/0).
- **M-1 (shallow superproject).**
  - The case where the superproject IS shallow is proven: SHALLOWSUP=1/B/true/1, and m39 is killed.
  - The case where the shallow state is **unknown** is NOT proven. The header claims it ("or its shallow state is unknown"). The real gate does refuse it: KNM2=1/1, using a fake git that answers `unknown`. But mutant NM2 (`!= false` changed to `= true`) survives the author's suite. This is part of R5-1.
- **M-2 (stash).** STASH=0/A/kept passes: stash push, then `stash apply --index`, then `commit -a` is WAIVED while refs/stash stays. Mutant m40 is killed.
  - Side effect: the exclusion also hides commits that are reachable only as **ancestors** of refs/stash. See A2 / R5-4: round 4 refused there, round 5 waives.
- **N-4.** N4INDEX=0,1, and m41 is killed: HEAD is excluded only when `diff --cached --quiet` says the index is HEAD's tree.
  - Two members of the N-4 class are unproven or leak:
    - the `--ignore-submodules=none` flag is load-bearing but no fixture proves it (NM1 survives; R5-1);
    - `diff` honours textconv drivers (A3, R5-3).
- **Residual list.** The `reset --soft HEAD~2 && commit -a` idiom is listed with its mitigation. RESETSQ=0,0,0/A pins it, and the hook comment names it. Two residuals are missing from the header and from CON-070: A1 (R5-5) and A2 (R5-4).
- **Fidelity of the K8–K14 adoption.** The author's fixtures repeat the round-4 reviewer's `p7_killers.sh` step by step; only the helper names differ.

## 5. Adversarial mutants written by the reviewer (11.4.194(6)(d))

Each mutant changes exactly one line and passes `bash -n`.
- Seds: `R/nm/NM*.sed`
- Mutated gates: `R/nm/NM*.sh`
- My killer fixtures: `R/probes/killers.sh` (self-contained, with real submodules, a layout copy of the gate and hook, and the sandbox HOME/TMPDIR)
- The author's suite (Part 1 classify) run against each mutant:
  - harness `R/repo/scripts/gates/rv_nm_harness.sh`, MUT_JOBS=2
  - log `R/out/nm_author_suite.out`
  - vectors `R/out/nm_author_suite/`
- My fixtures run against each mutant: `R/out/killers_nm.out`
- My fixtures on the real gate: `R/out/killers_real.out`
- My fixtures on the round-4 gate: `R/out/killers_r4.out`

The real gate gives KNM1=1,1 KNM2=1/1,0 KNM3=1/B,1/B KNM4=0/A,1/B KNM5=1/B,1/B KNM6=0,1 KNM9=0/A. Each of these matches the header's claimed behaviour.

| Mutant | One-line change (gate line) | Defect it restores | Author's suite | My fixtures |
|---|---|---|---|---|
| NM1 | line 195: drop `--ignore-submodules=none` from the N-4 diff | `diff.ignoreSubmodules=all` (user config) or `submodule.<name>.ignore=all` (a committed `.gitmodules` setting) makes an index that differs from HEAD only in a gitlink read as "index is HEAD's tree". The reviewed rollback R is then dropped as a spender, and the same row waives a second time. In a gate about gitlinks, this is the most likely index shape | **SURVIVED** | killed: KNM1 1,1→0,1 |
| NM2 | line 196: `!= false` → `= true` | an unknown shallow state (old git, a rev-parse error, empty output) is read as deep, so hidden same-parent commits are not looked for | **SURVIVED** | killed: KNM2 1/1→0/0 |
| NM3 | line 199: `for(i=2;i<=NF;i++)` → `i<=2` | only first parents count, so a merge with base as its **second** parent no longer spends the row. The header claims "(first or second, so a merge with base_sha as second parent counts)" | **SURVIVED** | killed: KNM3 1/B→0/A |
| NM4 | line 209: drop `$3""==n""` | a sibling commit on the same parent carrying a DIFFERENT transition (same path, old and base, another new sha) counts as a spender. The result is a false refusal of a legitimate rollback (11.4.201(1)). The class twin RM11 (path) and RM12 (old) were adopted in round 5; this third conjunct was not | **SURVIVED** | killed: KNM4 0/A→1/B |
| NM5 | line 209: spent awk without `-F'\t'` (whitespace split) | a spender row whose authoriser has a space ("Ops Team", or any human first and last name) splits to NF>7, so it is not seen. The second landing is WAIVED. Two-word authorisers are the normal case | **SURVIVED** | killed: KNM5 1/B→0/A |
| NM6 | line 195: drop `--cached` (compares the worktree, not the index) | judges the wrong tree | killed (AMEND 0,0,1,2→1,0,1,2) | killed: KNM6 0,1→1,0 |
| NM7 (control) | line 143: `cat-file -e "$1"` instead of `"$1^{tree}"` | a missing tree reads as "absent" again (the M-1 leak) | killed (TREEMISS 1/B/missing/1→0/A/missing/0) | not killed (no probe of mine removes a tree) |
| NM8 (control) | line 197: `--all --exclude=refs/stash` (the exclude comes after `--all`, so it does nothing) | the stash is counted again (M-2) | killed (STASH 0/A/kept→1/B/kept) | killed: A2STASHANC 0,0/A→0,1/B |
| NM9 | line 209: `NF==7` → `NF>=7` | a sibling row with an 8th field (a row that could never waive) counts as a spender, giving a false refusal | **SURVIVED** | killed: KNM9 0/A→1/B |

My fixtures (in `killers.sh`), each with its control value:
- **KNM1:** `--base P`, HEAD = R, and the index = R's tree plus a forward change of a second submodule. Run once with `diff.ignoreSubmodules=all` and once without.
- **KNM2:** a fake `git` on PATH that answers `unknown` to `--is-shallow-repository`, then the real git.
- **KNM3:** a `commit-tree` merge M that carries the row, with P as its second parent, then with P as its first parent.
- **KNM4:** a sibling on P whose row has another new sha, then one with the same new sha.
- **KNM5:** the round-3 squash shape with authoriser `Ops Team`, then with `ops`.
- **KNM6:** the index equals R's tree with an unstaged edit, then a staged edit with the worktree restored.
- **KNM9:** a sibling row with an 8th field.

## 6. Adversarial behaviour probes on the real gate

All three probes run with rows of the form path, old, new, authoriser, expiry, item and base-sha: one transition, one commit, one parent.

- **A1: a spender behind a per-worktree ref of ANOTHER worktree** (`refs/worktree/*`, `refs/bisect/*`; `refs/rewritten/*` during `rebase -r` belongs to the same family but I did not run it).
  - Result: A1WTREF=0/A/vis0, 0/A/vis0, then the control 1/B/vis1 with `refs/heads/keep`.
  - `rev-list --all` does not see another worktree's per-worktree refs, so the redo on P is WAIVED.
  - The round-4 gate behaves the same way, so this is not a regression. But it is a residual that neither the header nor CON-070 lists. The header says "every worktree's HEAD", which is accurate and incomplete.
  - Possible fixes: run the rev-list from each `git worktree list` path, or resolve `worktrees/<id>/refs/...`.
  - Finding R5-5.
- **A2: a spender reachable only as an ancestor of refs/stash.** The sequence: R committed, a stash made on top of R, then `reset --hard HEAD~1`. R is now reachable only through `refs/stash^1`.
  - Result: A2STASHANC=0,0/A/vis0, so round 5 WAIVES the redo. The round-4 gate refused it (0,1/B).
  - This is new in round 5: `--exclude=refs/stash` removes the whole ref, ancestors included.
  - The header's reason, "a stash is never a commit on a line of work", is true of the stash's W/I/U commits and false of their parents.
  - The effect is the same harm class as the intended reset+redo and the "reflog only" residual: `git stash branch` can bring R back beside R'.
  - A narrower option: drop only the stash commits (`git rev-list -g refs/stash`, plus `^2` and `^3`) from the candidate list instead of the whole ref.
  - Finding R5-4.
- **A3: a textconv driver defeats the N-4 test.** The setup: `.git/info/attributes` has `notes diff=same`, and `diff.same.textconv = sh -c 'echo same' --`. The index differs from HEAD R only in `notes`.
  - `git diff --cached --quiet HEAD` returns **0**, the gate in `--base P` mode excludes HEAD, and it **WAIVES**.
  - Controls:
    - with `diff.external` set, diff returns 1 and the gate refuses;
    - `--no-textconv --no-ext-diff` returns 1;
    - plumbing `diff-index --cached --quiet` returns 1;
    - without the attributes, diff returns 1 and the gate refuses.
  - So the round-5 claim "HEAD is excluded only when the index IS HEAD's tree" is false whenever a textconv driver maps two contents to the same text.
  - A realistic accidental case is a sqlite dump textconv on a tracked `.db`, where the bytes change but the dump stays the same (for example after VACUUM). This repository tracks `docs/workable_items.db`.
  - Fix: use `git diff-index --cached --quiet --ignore-submodules=none <c> --`, or compare `write-tree` against `<c>^{tree}`.
  - The round-4 gate always excluded HEAD, so this is not a regression; it is a leak in the new fix.
  - Finding R5-3.

## 7. Class inventory (11.4.276(C)) for spent(), blob() and the N-4 and shallow lines

Every load-bearing conjunct and flag, with the fixture that falsifies it. "author" means a mutant in the 72 is killed. "reviewer" means only my fixture kills it. "none run" means not mutated in this round; there the expected killer is UNCONFIRMED.

| Conjunct / flag | Falsified by |
|---|---|
| `GIT_NO_LAZY_FETCH` / `GIT_NO_REPLACE_OBJECTS` / `GIT_GRAFT_FILE` on pg | author: RM10/K10LAZY, RM9/K9REPL, m30/GRAFT |
| blob `^{tree}` check | author: m38/TREEMISS (control NM7 also killed by TREEMISS) |
| blob rc 1 vs rc 2 | author: CHILDTREE, UNREAD (m28) |
| N-4 `--cached` | author: AMEND (NM6) |
| N-4 `--ignore-submodules=none` | **reviewer only (NM1/KNM1)** |
| N-4 `--quiet` | none run. Removing it makes diff return 0 always, which is the same as N4-head-always-excluded (m41/N4INDEX) |
| N-4 textconv | **not falsifiable with the current code; it leaks (A3)** |
| shallow `= true` | author: m39/SHALLOWSUP |
| shallow `unknown` | **reviewer only (NM2/KNM2)** |
| `--exclude=refs/stash` | author: m40/STASH (control NM8 also killed by STASH) |
| `--all` / no `--single-worktree` | author: RM8, RM14 |
| `--parents` | none run (UNCONFIRMED). Expected to be killed by the many spender tokens (SNAP, SQUASHSAME, …), because no parents means no kids |
| awk `$1 != h` | author: m26 spent-head-counted, m41 |
| awk second-parent loop `i<=NF` | **reviewer only (NM3/KNM3)** |
| shallow → return 2 / rev-list error → return 2 | author: m39, m29 |
| unreadable waiver → return 2 | author: RM13/K13TELL |
| spent awk `-F'\t'` | **reviewer only (NM5/KNM5)** |
| spent awk `NF==7` | **reviewer only (NM9/KNM9)** |
| spent awk path / old / new / base | author: RM11, RM12, m27 (base); **new: reviewer only (NM4/KNM4)** |

There are six "reviewer only" rows. This shows that round 5 adopted the instances the round-4 review named and did not enumerate the class. That is exactly the instance-at-a-time root cause 11.4.276(C) names.

## 8. Findings

| ID | Severity | finding_layer | Minor-class (11.4.276(G.2)) | Summary |
|---|---|---|---|---|
| R5-1 | important | source-defect (proof-of-batch, 11.4.235(D) / 11.4.194(6)(d)) | no, blocks GO | Six reviewer mutants survive the author's full suite: NM1–NM5 and NM9 (`R/out/nm_author_suite.out`: exit 1, six `SURVIVED` lines, 837 s). The three controls NM6–NM8 are killed. Each restores a defect the header says is prevented: the N-4 ignore flag, the unknown shallow state, the second-parent spender, the new-sha match (a false refusal), the tab field split (two-word authorisers), and `NF==7` (an 8-field row, a false refusal). The class inventory (section 7) was not done. The runtime behaviour is right, which is why this is important and not critical. It is a reappearing finding of the round-4 M-4 class (11.4.276(E)(1)) |
| R5-3 | minor | source-defect | yes | A3: a textconv driver makes `diff --cached --quiet` read a different index as HEAD's tree, so in `--base` mode HEAD is excluded and the row waives again. Fix: plumbing `diff-index --cached --quiet --ignore-submodules=none`, or a tree-id compare. Not a regression from round 4 |
| R5-4 | minor | process-doc (optional source refinement) | yes | A2: `--exclude=refs/stash` also hides ancestors of the stash. Round 5 waives a redo that round 4 refused. The header's reason is inaccurate, and the residual is not listed |
| R5-5 | minor | process-doc | yes | A1: a spender behind another worktree's per-worktree refs (`refs/worktree/*`, `refs/bisect/*`; `refs/rewritten/*` UNCONFIRMED) is invisible. It is missing from the residual list and from CON-070 |
| R5-6 | nit | process-doc | yes | Gate header line 26 ("A `--range A..B` mode … is a FOLLOW-UP (not built)") and the residual paragraph do not name CON-070. The author acknowledges this |
| R5-7 | nit | process-doc | yes | The CON-070 text omits the A1 and A2 residuals |
| R5-8 | nit | process-doc (landing note) | yes | Merging onto the current main efe2cc6c conflicts in `docs/Issues.md`, `docs/Issues_Summary.md` and `docs/workable_items.db` (`git merge-tree` rc=1; the gate, test and hook merge cleanly; `R/out/mergetree_efe2cc6.out`). Landing must regenerate the tracker through the workable-items engine, never by hand. **CON-070 is still free on main efe2cc6c**: main carries CON-064..069, then CON-071..082, because redpin re-minted around it, so no id collision is measured. Re-check the id at landing |
| R5-9 | nit | process-doc | yes | Only one mutant run per mutant from the author (11.4.50). My m31–m72 run is the second; Part 1 now has N=3 identical runs |

Observation, not a finding: refusing all waivers in a shallow superproject is broader than necessary, but it is honest and fails closed (11.4.201(4)).

## 9. CON-070 and landing

- **The id is free as of efe2cc6c.** Main jumps from CON-069 to CON-071.
- **The landing conflicts only in the tracker files.** The merge must regenerate them through the engine (validate and diff).
- **One header line should name CON-070.**
- **CON-070 should also list A1 and A2.**

## 10. Verdict and operator decision (11.4.276(E)(3) at `R_max` = 5)

The verdict is NO-GO. The item stops here and is not run as round 6 under the same approach. It needs a recorded operator decision (11.4.66), parked per 11.4.101 while the loop continues other work.

I did not check whether this repository declares an `E_ext` (UNCONFIRMED). Without a declaration it is 0, so no automatic extension cycle exists.

Options:

1. **Extend `R_max` to 6 for CON-046** (11.4.276(G): only by a recorded operator decision naming the item). This is my recommendation, because the work is mechanical. Round 6 would:
   - adopt KNM1–KNM5 and KNM9 from `R/probes/killers.sh` into the suite vector, and NM1–NM9 verbatim into Part 2 (NM6–NM8 as controls);
   - do the class inventory of section 7, with one falsifying fixture per conjunct, including `--parents` and `--quiet`;
   - fix A3 with plumbing;
   - optionally narrow the stash exclusion (A2);
   - write the A1/A2 residuals and the CON-070 reference into the header and CON-070;
   - be reviewed once more.
2. **Re-scope (11.4.148).** Land the gate as it is, because its behaviour is proven by the reviewer's captured probes (`R/out/killers_real.out`). R5-1 would be recorded as a test-instrumentation follow-up. I do not take that reading myself: 11.4.235(D) names a surviving reviewer mutant as a source-defect. Only an operator decision can take it.
3. **Replace (11.4.276(E)(3)).** Build the CON-070 `--range` landing seam as the structural answer, and keep this pre-commit gate as the accident guard it is.
4. **A §11.4.271 waiver is not eligible.** R5-1 is important, not residual LOW.

CON-046 itself stays OPEN and UNREPRODUCED for the real tool in every option (§11.4.292(D)).

## 11. Evidence

All files are under `R/out/`:
- `red_vs_r4.out`
- `suite_m31_72.out` and `mut31_72/`
- `nm_author_suite.out` and `nm_author_suite/`
- `killers_real.out`, `killers_r4.out`, `killers_nm.out`
- `envledger.out`
- `mergetree_efe2cc6.out`

Probes, mutants and the round-4 gate:
- `R/probes/killers.sh`, `R/probes/vdiff.py`
- `R/nm/NM1..NM9.{sed,sh}`
- `R/r4/gate_r4.sh`

The author's evidence is in `scratchpad/con046r5/`.
