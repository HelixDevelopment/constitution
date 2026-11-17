# CON-046 review, structural round CON-108 (round 1 of a fresh budget; 7th review overall): uncommitted working tree

| Field | Value |
|---|---|
| Subject | **No new bundle exists.** The structural agent left its work UNCOMMITTED in the scratch clone `S/con046r7.M4TsIX/repo` (branch `vehicle/con046r7`, HEAD `bdc3ac43`; the index still holds the round-6 files, the working tree holds the round-7 files). I froze the four files (section 1). The last bundle reviewed is `con046_r6.bundle`, head `349f9a124bce64dbe294a4129772ed68740d8ad4`, sha256 `227f9c1d2b80c7d57534d190cef5d88df61b6ef0c47de7696cf5de8b85e49cfa` (round 6) |
| Reviewer | independent review agent (§11.4.142 / §11.4.209), model claude-opus-5-5. The dispatch did not report the reasoning effort to me, so I do not claim xhigh (§11.4.231(F.2)) |
| Verdict | **NO-GO.** Four blocking findings. R7-1 (important, source-defect, real behaviour): a true downgrade passes as WARN, exit 0, when the submodule has a commit-graph and an incomplete object store; the header promises BLIND. R7-2 (important, source-defect, proof-of-batch): all three of the inventory's "UNCONFIRMED-equivalent" claims are false, and one of them, the back member of the decide line, fails OPEN on a true downgrade. R7-7 (important, source-defect, proof-of-batch): the suite's verdict depends on the calendar day; a run that crosses midnight reports every later mutant killed, so a real survivor would be hidden. R7-8 (important): the submitted suite is RED on its own subject even on a single day, with 4 equivalence proofs failing and 16 dynamic-lint findings. R7-3 (fresh member-level survivors) also rules out GO-with-follow-ups, because it sits on the proof-of-batch surface (§11.4.276(G.2)) |
| What is right | The round-6 instances are closed. The eleven adopted killers are in the suite, and all twelve round-6 survivors plus NM1 are killed in a same-day run (run2). R6-3 and R6-4 are fixed. The static inventory lint and its control needle work. The equivalence-proof check is honest: it refuses the four proofs whose control needle sees nothing. 13 of the 17 proofs pass on a single day. `bash -n` and shellcheck are clean. The hook is unchanged and is installed nowhere |
| Review file name | The dispatch asked for `S/review_con046_r5.md`. That file already holds the round-5 review (23 303 bytes, 2026-11-05). I did not overwrite it (§9.2): this review is `S/review_con046_r7.md` |

## 1. Finding the subject, setup and integrity

The dispatch said the structural agent finished before a host reboot and its hand-back was lost. What exists:

- Bundles in the session root: `con046.bundle` to `con046_r6.bundle`. There is **no** `con046_r7.bundle` and no round-7 fix report (`S/con046_fix_r6_report.md` is the newest).
- The structural clone `S/con046r7.M4TsIX/repo`: branch `vehicle/con046r7`, HEAD `bdc3ac43`, a `main` commit (it is an ancestor of live `main` 90efceb8, 59 commits behind it; it is NOT a descendant of the round-6 head 349f9a12). The round-6 gate / test / hook are STAGED in the index as new files on top of it, and the round-7 versions are in the working tree; the inventory is a new untracked file. So the round-7 work exists only as **uncommitted working-tree files on persistent disk** (`~/.cache`), and nothing of CON-046 is on live `main` yet.
- The agent's evidence directory `S/con046r7_evidence/`: `redgreen_old_r6_test.log`, `redgreen_new_test.log`, `verify_manifest.txt`. The agent's two full runs were in `/dev/shm/con046r7` and were lost at the reboot (tmpfs); the transcript (`S/../tasks/a5f09546d39c39978.output`, read only by grep / tail) ends with "Waiting for full run 1."

Frozen subject (`R/subject/`, R = `S/rv046r7.tMNcDq`), sha256:

| File | sha256 | Note |
|---|---|---|
| `scripts/gates/cm_submodule_pin_not_downgraded.sh` | `1abac16eb810ea7a8057189d1aeaf9e2f181cb7d4ce9f31acfb44545f3c33c83` | 300 lines; header text only changed vs round 6 (CON-083 to CON-109, Unicode category C wording, inventory pointer) |
| `scripts/gates/cm_submodule_pin_not_downgraded_mutation_test.sh` | `01c5e3c26a5bd43ddd476e5509425221f8ed3f55097244916e9204647f5a72cb` | 1488 lines; 280 registered mutants / proofs (round 6: 125) |
| `scripts/gates/cm_submodule_pin_not_downgraded_inventory.tsv` | `66b3e7152d3c8a5686fbe9212d1276a8362e7a26847316ab7a3cf3279c4f10f8` | new, 214 rows; need: both 41, ch 80, fo 46, fr 36, none 11 |
| `scripts/hooks/pre-commit-submodule-pin-not-downgraded` | `95fa276c0724083d3d09690913b06539b42799b80f5f00985e835433497f1598` | unchanged since round 6 |
| `structural_wt_vs_r6_index.patch` (working tree vs index) | `99f0a7ffffbcf7e9f09c89d7af2bc3ee880c8db23d9b3cfecd5bf5c68c486ac9` | |
| `R/out/subject.tar` (the frozen copy) | `f77451f6f939c0539a1608d3c07b489980b76c40dc39f0c61ba1deb333fe693c` | |

Static checks (`R/out/static.out`): `bash -n` rc 0 and `shellcheck -S warning` rc 0 on all three scripts; control needle (a file with an unused variable) rc 1, as it must be.

Safety: every probe of mine runs in its own `mktemp -d` root under my TMPDIR, sets `GIT_CONFIG_GLOBAL` inside that root and never reassigns HOME, and cleans up with `rm -rf "${t:?}"`. The author's suite (run unmodified) sets `HOME="$tmp/home"` inside its own process after checking that `$tmp` is a non-empty directory from `mktemp -d`, and its EXIT trap is `rm -rf "${tmp:?}"`; that is the §11.4.287(C)(2) shape. Live checkout `/home/milosvasic/Projects/constitution`: clean, on `main` at `90efceb8`, no `core.hooksPath` (local or global), no non-sample hook. I modified and committed nothing there and installed the hook nowhere. Host: 16 CPUs, 30 GiB RAM, load 17 to 21 during the runs (mine at `nice` 10 to 15, at most 6 + 2 jobs).

## 2. RED / GREEN

The author's surviving evidence (`S/con046r7_evidence/`):

| File | sha256 (prefix) | What it is |
|---|---|---|
| `redgreen_old_r6_test.log` | `5f532f11...` | RED. The ROUND-6 suite, run on the 13 round-6 reviewer mutants. 12 SURVIVE (V07, V08, V12, V13, V16, V17, V18, V19, V20, V22, V28, V29); only NM1 is killed. This reproduces the round-6 review. |
| `redgreen_new_test.log` | `54b05903...` | GREEN for the instances. The ROUND-7 suite, filtered to the same 13: `mutants: 13 (killed 12, survived 1)`. V28 survives here because in the full suite it is the `eqp` `eq-V28-...`, not a plain mutant. Filtering also empties the lint's registry (`registered 0`, 341 L4 findings, `BAD lint control needle`), so this file is not a GREEN of the whole suite (R7-6). |
| `verify_manifest.txt` | `628d12c9...` | `RESULT: MANIFEST-OK`, census total 854, on the vehicle's old base (R7-5) |

My run of the full round-7 suite (run1, section 4): Part 1's vector is byte-identical to the author's (`diff` of the `gate vector:` lines, empty), and it equals the suite's `want` (no `BAD classification` line). The real gate's vector carries all eleven adopted round-6 killers (I did not re-check each value against the round-6 review's own measurement): `KV365=0/A`, `KV12ZWSP=1/B`, `KV13SHARPS=1/B`, `KVREFS=1/B,1/B,1/B`, `KV17ORDER=1/B/yfirst`, `KV18HASHMID=0`, `KV19STALEFIRST=0/A`, `KV20BADEXPFIRST=0/A`, `KV22SUBUNKNOWN=2/1,0/1`, `KV29B=1/1,1/1`, `KV02HELP=0`.

## 3. The round-6 findings, closed or not

| Finding | Status | Evidence |
|---|---|---|
| R6-1 (V22, V17 survive, fail-open) | **instances closed; class recurs** | Killed in run2 (same day): `V22-sub-shallow-unknown-is-complete` and `V17-spent-fileless-kid-ends-scan` (by KV22SUBUNKNOWN and KV17ORDER). The class (a member of a guard with no killing fixture, wrongly marked equivalent) recurs one member to the left on the same decide line: R7-2, I158a / I158b, where one member fails open on a downgrade |
| R6-2 (nine more survivors) | **instances closed; class recurs** | Killed in run2: V07, V08, V12, V13, V16, V18, V19, V20, V29. V28 is an `eqp` and its proof passes in run2. The class recurs below the lint's granularity: R7-3 |
| R6-3 (V02, `-h` exit status) | **closed**; sibling recurs as a nit | `KV02HELP=0` is in the vector. The `--help` alternative of the same `case` pattern is unasserted (RV7-05) |
| R6-4 (header says "control characters") | **fixed** | Header lines 98 to 99 now name the full Unicode category C set (Cc, Cf, Cs, Co, Cn), which is what the code checks |
| R6-5 (ids, generated files, manifest) | **(a) recurs; (b), (c) open until the landing** | CON-083 was re-minted to CON-108 / CON-109, which collide on live `main` (R7-5) |
| R6-6 (N = 2 runs) | **recurs** | One full run exists (mine). The author's were lost on tmpfs (R7-6) |

## 4. My runs of the author's suite (frozen subject, unmodified unless stated)

| Run | Scope | When | Result |
|---|---|---|---|
| run1 | the full suite, `MUT_JOBS=6` | 2026-11-10 23:10 to 2026-11-11 00:53 (6195 s), **crossed midnight** | exit 1. `mutants: 280 (killed 263, survived 0, equivalent-with-proof 0)`; all 17 eqp mutants reported "the suite kills it, so it is NOT equivalent"; `lint dynamic ... findings 33`; Part 3 right. Log `R/out/run1.log`, sha256 `ef1ad253...` |
| run2 | `MUT_ONLY` = NM1, the 11 round-6 V mutants, all 17 `eq-` proofs | 2026-11-11 00:53 to 01:04 (637 s), one calendar day | exit 1. `mutants: 29 (killed 12, survived 0, equivalent-with-proof 13)`. All 17 eqp mutants: "whole-suite vector equals the real gate's". Probe level: 13 pass; 4 fail with control = real (`eq-unchanged-entry-dropped` and the three UNCONFIRMED). Log `R/out/run2.log`, sha256 `773a1963...` |
| run3 | `MUT_ONLY` = the 16 mutants of the non-proof dynamic-lint rows; a scratch copy of the test whose EXIT trap also copies `dirs.tsv` out (the only change, `R/run3/`) | 2026-11-11 01:05 to 01:11 (363 s), one calendar day | exit 0, `mutants: 16 (killed 16, survived 0, equivalent-with-proof 0)`. Directions (`R/out/run3keep/dirs.tsv`): 12 `-` (killed, but no item's exit code changed, so the kill came from a count or message field), 3 `ch`, and `usage-argc-off-by-one` `ch,fr`. The author's lint, extracted unchanged and run three times on this `dirs.tsv` (identical output), reproduces all 16 findings (`R/out/run3_lint16.out`). Log `R/out/run3.log`, sha256 `68f34654...` |

Part 1 is identical in all three runs and equals `want`. Run1 versus run2 is the polarity proof for R7-7: the same files, the same suite and the same 17 mutants give "NOT equivalent" in run1 and "equals the real gate's" in run2. The only difference is that run1's jobs ran after midnight. Run1's kill count is therefore no evidence for any mutant classified after 00:00. That is about the last 128 of 280 (the tally at 00:08 had 152 done), so I do not cite run1 for kills, except for the indexes run2 or run3 re-measured. No full run of this suite has been GREEN, and none has run on a single calendar day.


## 5. R7-1: a true downgrade passes as WARN when the submodule has a commit-graph (real git, no double)

Gate lines 284 to 293 (the decide block):

```
sg -C "$sub" merge-base --is-ancestor "$osha" "$nsha" 2>/dev/null; fwd=$?
...
sg -C "$sub" merge-base --is-ancestor "$nsha" "$osha" 2>/dev/null; back=$?
if [ "$back" = 0 ]; then ... FAIL / WAIVED
elif [ "$fwd" = 1 ] && [ "$back" = 1 ] && [ "$shallow" = false ]; then ... WARN ... DIVERGED (exit 0)
else blindmsg ... "cannot be decided" (exit 2)
```

The header (lines 41 to 43) promises BLIND when "ancestry cannot be decided (a shallow or incomplete submodule where neither direction is proven)", and the suite's `MISSINGMID=2` fixture proves it, but only for an object store WITHOUT a commit-graph.

Measured on git 2.53.0 (`R/probes/p_graph_missing.sh`, output `R/out/p_graph_missing.out`, three identical runs). Submodule history A <- M <- T; a commit-graph is written while only A exists (`commit-graph write --reachable`, which is also what `git gc` does by default); the loose object of M is then removed, so the object store is incomplete while both pins exist and the repository is not shallow. The base pins T, A is staged: the truth is a downgrade.

| Shape | gate exit / FAIL / WARN / "cannot be decided" | raw `merge-base --is-ancestor A T` |
|---|---|---|
| DOWNGRADE (graph, M missing) | **0 / 0 / 1 / 0**: WARN "DIVERGED", exit 0 | rc **1**, stderr `error: Could not read <M>` |
| CTL (graph, M present) | 1 / 1 / 0 / 0: FAIL, as it must be | rc 0 |
| NOGRAPH (no graph, M missing; the suite's MISSINGMID shape) | 2 / 0 / 0 / 1: BLIND | rc 128 |

Root cause: with generation numbers available, git's reachability walk (`repo_is_descendant_of` / `can_all_from_reach`) reports a commit it cannot read as "not reachable" (rc 1) and only prints the error, where the walk without a graph dies with rc 128. The gate throws stderr away, so it sees `fwd=1 back=1 shallow=false`, takes the DIVERGED branch and prints a false "neither is an ancestor" WARN with exit 0. The other direction (`is-ancestor T A`) returns 1 with no error at all, because T is not in the graph and the generation cut-off answers without a walk.

A fix direction, measured (`R/probes/p_commitgraph_off.sh`, `R/out/p_commitgraph_off.out`, N = 3 identical): with `git -c core.commitGraph=false merge-base --is-ancestor`, both directions return 128 on the same store (default: 1 with an `error:` line, and 1 silently), so the existing `else` branch would give BLIND. Capturing stderr and treating any `error:` output as undecidable is the other option. The killing fixture is the DOWNGRADE row above (`MISSINGMID` plus one `commit-graph write --reachable` before the later commits). `rev-list --all --parents`, the walk the spent check uses, returns 128 on the same store with or without the graph, so the spent check fails safe there (measured in the submodule store; I did not build the superproject variant).

Severity **important**, finding_layer **source-defect** (the shipped gate's own behaviour contradicts its header on a fail-open path). Not critical: it needs an incomplete object store (pruned alternates of a `--reference` / `--shared` clone, a corrupted or hand-edited store), and the header's threat model is an accident guard. This defect is not new in this round (the decide lines are unchanged since round 6); no earlier review and no fixture found it.

## 6. R7-2: all three "UNCONFIRMED-equivalent" claims are false (the mutants are not equivalent)

The redesign's acceptance (CON-108) says "every equivalent mutant has a passing differential proof", and the lint's dynamic part accepts a `need none` row only once its proof has passed. For the three rows the inventory itself calls "UNCONFIRMED-equivalent", the suite does NOT pass the proof: in run1 the author's own control needle gives the same probe output as the real gate (I021: `[down:1,div:0/1,fwd:0]` on all three gates; I158a and I158b: `[div:0/1,down:1,fwd:0,divmiss:2/0]` on all three), so the eqp check and the lint mark them `did not pass`. That part of the mechanism is honest; this probe uses no dates, so it is not affected by R7-7. What the suite cannot say is whether the claims are true. They are not: each of the three mutants changes the gate's behaviour on an input that the author's probe never feeds:

| Inventory row | Proof (author's probe) | Why the probe is blind | My probe, result (N = 3 identical) |
|---|---|---|---|
| I021 keep-list `GIT_CONFIG_PARAMETERS\|GIT_CONFIG_COUNT) ;;`, need `ch`, proof `eq-UNCONFIRMED-config-params-unset` | `pr_cfgparams`: `core.abbrev`, `diff.ignoresubmodules` through the two channels | inert keys: no key it passes can change a verdict | `R/probes/p_safedir.sh` (real git, no double): a checkout owned by another user (git's own `GIT_TEST_ASSUME_DIFFERENT_OWNER=1`) with `safe.directory=*` given on the command line, the `git -c safe.directory=... commit` shape. Real gate: forward 0, downgrade 1. The eq mutant: **2 / 2** ("not a repository", false BLIND on both). Control without safe.directory: 2 / 2 on every gate |
| I158a decide `fwd` member, need `none`, proof `eq-UNCONFIRMED-diverged-fwd-member-dropped` | `pr_decide`: real-git shapes only | with real git 2.53 both directions run the same code path, so the two rcs never differ outside {0, 1} | `R/probes/p_decide_oneway.sh`: a gate-logic double (§11.4.289(C)(2)), a `git` wrapper that kills ITSELF with SIGKILL for one `merge-base --is-ancestor` pair (rc 137, the OOM-kill / timeout shape) and passes every other call to the real git. FWDKILLFWD (true forward bump, fwd killed): real **2** BLIND, mutant **0** WARN |
| I158b decide `back` member, need `none`, proof `eq-UNCONFIRMED-diverged-back-member-dropped` | same | same | DOWNKILLBACK (true DOWNGRADE, back killed): real **2** BLIND, mutant **0** WARN "DIVERGED": **fail-open on a downgrade**. CTL (no kill): 1 on every gate |

This is the standard the author applied themselves one member to the right on the same line: I158c (the shallow member) is killed by KV22SUBUNKNOWN, which uses exactly such a `git` wrapper (`$tmp/fk22/git`). I158a/b were left "UNCONFIRMED-equivalent" with "no shape found". So round 6's R6-1 class (a member of a claimed guard class with no killing fixture) recurs on the sibling members of the same line, and one of them fails open.

Severity **important**, finding_layer **source-defect (proof-of-batch, §11.4.235(D) / §11.4.194(6)(d))**. Each of the three mutants keeps the suite's vector equal to the real gate's: they survive Part 1 and Part 3, as my standalone runs show (`R/out/rv/`, I158a and I158b, before midnight). Each one is not equivalent. So the batch is not proven correct. The author's "no shape found" was an absence of search: the shapes exist, and one of them fails OPEN on a downgrade. Reappearing (§11.4.276(E)(1)). The real gate's behaviour on all three shapes is right, which is why this is important and not critical. The fix is mechanical: add the three probes' shapes as fixtures, turn the three rows to `need fr` (I021) / `need ch` (I158a) / `need fo` (I158b) with these mutants, and tighten `pr_cfgparams` so that the differential proof feeds a config key that matters.

## 7. R7-3: fresh reviewer mutants on members below the lint's floor (§11.4.194(6)(d))

The lint counts a line's members as 1 + its `&&` / `||` joins (shell) or 1 + its ` or ` / ` and ` joins (python) (test lines 567 to 570). It cannot see a member inside a `case` alternation, inside a regex quantifier, or in the choice of a method. The lint says so itself ("The lint is a FLOOR, not a proof of completeness", test lines 556 to 557). I wrote five one-line mutants exactly there, ran each through the author's UNMODIFIED suite with `GATE_UNDER_TEST` (`R/probes/run_rv_mutant.sh`: Part 1 vector vs `want` plus Part 3; harness controls: the real gate SURVIVES with rc 0 and no BAD line, and the author's own `item-digits-loosened` sed is KILLED with rc 1 and a `BAD classification` line), and wrote a killing probe for each (`R/probes/p_safedir.sh`, `R/probes/p_rv7_fresh.sh`; N = 3 identical runs each).

Probe outputs read `rc/n`: the gate's exit status and the number of matching lines (BLIND lines for `p_safedir`, `WAIVED` lines for ITEM / SELF, help lines for HELP).

| Mutant (gate line, one-line sed) | Inventory row that should own it | Author's full suite with `GATE_UNDER_TEST` | Killing probe, real gate vs mutant (N = 3 identical) | Impact on the shipped behaviour |
|---|---|---|---|---|
| RV7-01, line 148: keep-list `GIT_CONFIG_PARAMETERS\|GIT_CONFIG_COUNT)` becomes `GIT_CONFIG_PARAMETERS)` | I021 (one row for both alternatives; its only fr/fo mutant removes the whole keep-list and is the false eq claim of R7-2) | **SURVIVED**, rc 0, 0 BAD lines, 327 s | `p_safedir.sh`, `safe.directory=*` passed through `GIT_CONFIG_COUNT` / `KEY_0` / `VALUE_0` in a foreign-owned checkout: real forward 0/0, downgrade 1/0; mutant forward **2/1**, downgrade **2/1** | false BLIND (exit 2) on every commit made that way; no fail-open |
| RV7-02, line 148: the same alternation becomes `GIT_CONFIG_COUNT)` | I021 | **SURVIVED**, rc 0, 0 BAD, 328 s | same probe, `git -c safe.directory=* commit` (GIT_CONFIG_PARAMETERS, the common form): real 0/0 and 1/0; mutant **2/1** and **2/1** | false BLIND on every `git -c safe.directory=...` commit in a foreign-owned checkout |
| RV7-03, line 245: item regex `[0-9]{3,}` becomes `[0-9]{3}` | I115 (need `both`; satisfied by `item-digits-loosened` (fo) and `item-always-bad` (fr), neither of which touches the upper bound) | **SURVIVED**, rc 0, 0 BAD, 225 s | `p_rv7_fresh.sh` ITEM4 (a valid row whose item is `CON-1234`): real 0/1 (WAIVED); mutant **1/0** (FAIL "does not match CON-NNN"). ITEM3 control 0/1 on both | false refusal of every valid waiver whose item has 4 or more digits, which the header (line 97: "3+ digits") allows. A consumer whose tracker is past 999 could not waive at all (commits on live `main` already cite ids such as `ATM-1809`) |
| RV7-04, line 194: `a!=a.strip()` becomes `a!=a.lstrip()` | I066 / I067 (one row per line segment; `authoriser-form-unchecked` drops the whole whitespace test) | **SURVIVED**, rc 0, 0 BAD, 225 s | SELFTRAIL (the authoriser is the committer's own name plus one trailing space): real 1/0 (row refused: "surrounding whitespace"); mutant **0/1** (WAIVED). SELFLEAD control: 1/0 on both | the header (line 98: "no leading/trailing whitespace") is broken, and the producer can self-waive a downgrade by padding their own name with a trailing space (fail-open on the self-waive ban). The header's threat model is ACCIDENT (lines 19 to 20 and 107 to 110), as for round 6's V12 / V13 / V29 |
| RV7-05, line 139: `-h\|--help)` becomes `-h)` | I013 (`help-truncated` and `V02-help-exits-1` both use `-h` only) | **SURVIVED**, rc 0, 0 BAD, 150 s | HELPLONG: real 0/126 (126 help lines); mutant **2/1** (usage error). HELPSHORT control 0/126 on both | `--help` (accepted by the code, not in the usage line 114, which shows `[-h]`) exits 2 with a usage error. No header claim; same class as R6-3 (KV02HELP asserts `-h` only) |

Harness controls, same runner, same frozen suite: the real gate SURVIVES (rc 0, 0 BAD, 208 s), and the author's own `item-digits-loosened` sed applied as a standalone mutant (`CTLK`) is KILLED (rc 1, one `BAD classification` line, 205 s). The two eq mutants of R7-2 (I158a and I158b, as standalone files) also survive the suite (rc 0, 205 s and 207 s), as their `need none` rows say they must; what kills them is only my probe.

What the five have in common is what the round-6 review asked the structural round to remove (R6-2, and option 2 of its section 6: "redoes the inventory at MEMBER level: every alternative value or site inside each guard"). The inventory is per line SEGMENT, and a row's `need` is met by ANY one mutant in each direction. So the second alternative of a `case` pattern, the upper bound of a quantifier, the trailing half of `strip()` and the long form of an option are not members anywhere, and the lint cannot count them (it splits only at `&&` / `||` / ` or ` / ` and `). The redesign closed round 6's twelve instances, but the class is still open below the lint's granularity. Individually RV7-01 to RV7-04 are minor by impact and RV7-05 is a nit. Together they are a §11.4.235(D) proof-of-batch finding: non-equivalent reviewer mutants that the author's full suite cannot kill. §11.4.276(G.2) therefore keeps them out of `GO-with-follow-ups`. Each one has a ready killing probe in `R/probes/` that flips only for its own mutant.

Equivalence claims I did not refute. Of the 17 `eqp` proofs, I refuted three (R7-2). I read six of the other fourteen and found no counterexample: `eq-idpy-len-dropped` (the printf always yields five NUL-separated fields, and bash variables cannot hold a NUL), `eq-idpy-strip-and-dropped` (casefold and NFC never map a non-empty string to an empty one), `eq-blob-absent-as-empty` (the only caller treats an empty blob as "no matching row"), `eq-expiry-regex-dropped` (GNU date 9.x rejects five-digit years, `+` signs and the other forms I tried, measured on this host; `...T00` and a trailing space round-trip to a different string), and `eq-site-spent-aborts` / `eq-site-cannottell-aborts` (`spent` is keyed on `(path, old, new, base)`, not on the row, and "cannot tell" is commit-wide, so every later candidate row gives the same answer; only the last WHY text can differ). That is analysis, not a probe. I did not examine the other eight.

## 8. R7-4: the dynamic lint's zero has no control needle (CON-108 acceptance "control needles for every zero")

The static lint has a control needle (test lines 646 to 652: a broken inventory must give L1, L3 and L5 findings). The dynamic lint (`lint dynamic`, run once after Part 2, test line 1451) has none. Measured (lint extracted from the test unchanged and run standalone on a directions file in which every registered mutant is observed only as `ch`): the real lint gives **findings 123** (rc 1, one `DYN ... need` line per row whose fo / fr direction is uncovered); a lint mutant with `if not wantd<=got:` turned into `if False:` gives **findings 0** (rc 0). Nothing in the suite would notice that mutant, and the same holds for the proof check on test lines 635 to 636. Severity **minor**, finding_layer **test-instrumentation**; it is an unmet acceptance item of CON-108 and should be fixed with the next round (a known-bad directions file must give a DYN finding, as the static needle does for L1 / L3 / L5).

## 9. R7-5: landing nits (ids, base, manifest)

- **Item ids collide again (R6-5(a) recurs).** In the clone's tracker, CON-108 is this structural round and CON-109 is the `--range` follow-up, and the gate header cites CON-109. On live `main` 90efceb8, CON-108 is "ownership F1 ..." and CON-109 is "WIT-C02 ...", both Queued, and the highest CON id is 115. Re-mint both through the workable-items engine on top of current `main` (CON-116 or higher at the time of writing) and update the gate header, the inventory header and the tracker text. Never renumber the existing main items (§11.4.54).
- **Base.** The vehicle's HEAD `bdc3ac43` is 59 commits behind live `main`. The landing must merge onto the latest `main` and fast-forward (§11.4.113 / §11.4.288(B)(3)). The generated files of R6-5(b) must be regenerated through their tools, never by hand.
- **Manifest.** The author's `verify_manifest.txt` says `RESULT: MANIFEST-OK` with census total 854, measured against the old base. Re-run `--verify-manifest` after the merge (R6-5(c)).

Severity **nit**, finding_layer **process-doc (landing)**.

## 10. R7-6: the round's work is not committed, and no full run of the suite has a valid result

- The round-7 files exist only as uncommitted working-tree changes in `S/con046r7.M4TsIX/repo`, on top of an index that still holds the round-6 files. There is no bundle and no commit. One `git checkout -- .` or one cleanup of the scratch tree would lose the whole round. **Commit it on the vehicle now** and write `con046_r7.bundle`.
- The author's two full runs were on tmpfs and were lost at the reboot. The author's surviving GREEN evidence (`redgreen_new_test.log`) is a filtered run of the 13 round-6 reviewer mutants. In that run the lint has no registry (`registered 0`, 341 L4 findings, and the lint control needle reports BAD), and V28 survives because outside the full run it is not an `eqp`. It is a valid instance check, but it is not a GREEN of the suite.
- CON-108's acceptance asks for "the full mutation file runs twice with identical counts and zero unexplained survivors". No full run of this suite has a valid result. My full run (run1) crossed midnight and is void for kills after 00:00 (R7-7). Run2 and run3 are targeted same-day runs. §11.4.50 needs N = 3 for a PASS. The next round must produce the runs on persistent disk (`~/.cache`, never `/dev/shm`) and keep their logs with sha256.

Severity **minor**, finding_layer **process-doc**. The loss risk is real: the only copy of a whole round sits uncommitted in a scratch clone.

## 11. R7-7: the suite's verdict depends on the calendar day (a run across midnight hides survivors)

Test lines 29 and 30 compute `d10`, `d30`, `d31`, `d45` and `today` ONCE, when the suite starts. `got`, the real gate's vector, is computed a few minutes later (line 642). The fixtures run inside every later job, and the gate judges each one against its own `date` at run time:

- `TODAY` (line 68) is a row expiring on `$today`. After midnight it is expired: 0 becomes 1.
- `HORIZON` (lines 74 and 75) has `$d30` accepted and `$d31` refused. After midnight, `$d31` is the gate's today + 30, so it is inside the limit: the second item, 1, becomes 0.
- `CONFZERO` (line 221) has `max_waiver_days=0` with a `$today` expiry, so it flips as well.

So every job classified after 00:00 produces a vector different from `got`, whatever the mutant does. Three things follow:

- (a) **A surviving mutant is reported "killed".** The instrument fails open, so a real survivor is hidden.
- (b) Every eqp mutant is reported "NOT equivalent" (a false RED).
- (c) In the dynamic lint, those jobs get `fr` (from TODAY) and `fo` (from HORIZON) from the calendar alone. Any `need` row they belong to is then satisfied by the date, not by the mutant.

Measured: run1 against run2 (section 4) is the polarity flip. The same 17 mutants were "NOT equivalent" after midnight and "equal to the real gate's" on one day; nothing else changed. Exposure: a full run takes about 100 minutes on this host at `MUT_JOBS=6` (run1: 6195 s), so any full run started after about 22:15 local time is affected.

Fix direction: compute every date-dependent fixture inside the job that uses it, and compute `got` in the same way. Record the date when `got` is computed and when each job starts and ends. A job whose date differs from `got`'s is INCONCLUSIVE and re-run, never "killed". A paired mutant for the test itself: move the start date one day back through a `date` wrapper on `PATH` for the jobs only; the fixed suite must report INCONCLUSIVE, not killed.

Severity **important**, finding_layer **source-defect (proof-of-batch, §11.4.235(D))**: the proving instrument can report a survivor as killed. It is also a §11.4.50 determinism defect.

## 12. R7-8: the submitted suite is RED on its own subject, even on one day

The structural agent's two full runs were lost (R7-6), so nobody saw this suite's result before this review. On the frozen subject:

- **Four equivalence proofs fail their own control needle** (run2, one day). `eq-unchanged-entry-dropped`: `pr_unchanged` has no fixture in which only the OLD mode is a gitlink, so its control (`[ "$nm" = 160000 ]`, the `om` check dropped) gives the same output as the real gate (`[same:0/(0 staged,wtonly:0/(0 staged,down:1]` on all three). The claim itself may be true; it is unproven. The other three are the UNCONFIRMED rows of R7-2, which are false.
- **16 dynamic-lint findings that are not proof failures.** I re-measured them on one day (run3, section 4) and all 16 reproduce. All 16 mutants are killed, but for 12 of them no item's exit code changes: the kill comes from a count or message field. The lint's `vdir` (test lines 654 to 675) compares only the exit code (the first `/` field of each item), so it records those 12 as no change. That gives ten `need ch` rows reporting "no mutant changed the vector" (I010, I017b, I031, I045b, I073, I125, I130, I143, I149, I159), and three `need fo` rows observing `-` (I145, I150b, I151b). Two further rows have a direction, just not the claimed one: I006 and I007 (`need both`) show only `ch,fr`, and for I146b (`need fo`) `symlink-unchecked` shows only `ch`. So `vdir` must either count a count-only change as `ch` (the suite does kill on it), or these rows' `need` claims are wrong. For the six rows that claim a fail-open form (I006, I007, I145, I146b, I150b, I151b), no registered mutant shows one. Either a member is untested or the claim is false, and the round must find out which; I did not.

CON-108's acceptance ("zero unexplained survivors", "every equivalent mutant has a passing differential proof", "an independent Opus review returns GO") is therefore unmet in the submitted state, independently of R7-1 to R7-3. Severity **important**, finding_layer **source-defect (proof-of-batch)** for the unproven equivalence and the unmet `need` rows, and **test-instrumentation** for the lint semantics.

## 13. R7-9: one full run needs about 22 GiB of temporary disk

Part 2 keeps every finished job's fixture tree (about 80 MiB each) until the suite exits. Measured peak of run1's temp tree: **22 192 MiB** (`R/out/run1_peak_tmp.txt`, sampled every 60 s). The host's root file system was 98 % used during the run, with 27 GiB at the lowest point I read. Two full runs in parallel, as CON-108 asks, would have needed about 44 GiB. Fix: delete `$tmp/j$n` as soon as `$tmp/j$n.res` is written; only the `.res` file is read later (test lines 1432 to 1439). Severity **minor**, finding_layer **test-instrumentation** (host safety, §12.9).

## 14. Per-slice verdicts

| Slice | Verdict | Why |
|---|---|---|
| Gate `cm_submodule_pin_not_downgraded.sh` | **NO-GO** | R7-1 is a behaviour defect of the real gate on a fail-open path: a true downgrade gives WARN with exit 0 under a commit-graph plus an incomplete object store. On every other shape I measured, the real gate gives the right answer: p_safedir, p_decide_oneway (BLIND under one-way kills), p_rv7_fresh, the CTL rows. The fix is a few lines in the decide block, plus one fixture. |
| Mutation test `..._mutation_test.sh` + inventory | **NO-GO** | R7-2 (three false eq claims; all three "UNCONFIRMED-equivalent" rows are false), R7-3 (five member-level survivors), R7-7 (the verdict depends on the calendar day; a survivor can be reported killed), R7-8 (the suite is RED on its own subject on one day: 4 proofs fail their needle, 16 dynamic-lint findings), R7-4 (the dynamic lint has no needle), R7-9 (about 22 GiB of temp disk per run). The round-6 instances are closed (section 3). |
| Hook `pre-commit-submodule-pin-not-downgraded` | **GO in isolation** | Byte-identical to round 6. Part 3 in run1 and run2: plain downgrade rc 1, forward rc 0, downgrade-after rc 1, a real-submodule worktree forward 0 / downgrade 1, persist rollback 0 / fwd 0 / snapshot 1, and a layout SKIP (rc 0) with the honest "gate not found beside this hook" message |
| Tracker / docs / manifest | **GO-with-follow-ups** | R7-5 (ids, base, manifest) and R7-6 (commit, runs) are landing and process work. |

**Overall: NO-GO.** This is round 1 of CON-108's fresh budget (§11.4.276(A): `R_max` 5 by default), so the loop continues, as the operator ruled. What the next round must do, in order:

1. **Commit the round-7 work and write the bundle before anything else** (R7-6).
2. **Fix R7-1 in the gate, test first.** Add the `MISSINGMID` plus `commit-graph write --reachable` fixture. It must give BLIND on the fixed gate and WARN (exit 0) on the current gate (RED observed first, §11.4.115). Then pick a fix: `-c core.commitGraph=false` on the two `is-ancestor` calls (measured here: rc 128 both ways on that store), or capture stderr and treat any `error:` output as undecidable. Re-check `rev-list --all` in the superproject variant of the same store.
3. **Adopt my four probe scripts verbatim (§11.4.194(6)(d)); together they kill the eight mutants and expose R7-1**: `p_safedir` (I021, RV7-01, RV7-02), `p_decide_oneway` (I158a, I158b), `p_rv7_fresh` (RV7-03, RV7-04, RV7-05) and `p_graph_missing` (R7-1). Turn I021 / I158a / I158b into killed rows (`need fr` / `ch` / `fo` as measured), and add the five fresh mutants to the registry.
4. **Retire the "UNCONFIRMED-equivalent" category.** All three such claims in this round were false, and the suite could not pass any of their proofs (its control needle saw nothing). A probe that never feeds the member's input can neither prove nor refute equivalence, so an eq claim must carry a stated argument for why no input reaches the member. An eq mutant whose argument is "no shape found" must stay a SURVIVOR until it is killed or proven. Make `pr_cfgparams` feed a key that matters (`safe.directory`).
5. **Close the class mechanically, not by hand (§11.4.274).** This class has come back three times (R5, R6-1/R6-2, R7-2/R7-3), and each time a reviewer found members below the granularity of the hand-written rows. Generate the member mutants with a script that enumerates every alternative of every `case` pattern, every regex quantifier and character class, every `strip` / `lstrip` / `rstrip` choice and every `&&` / `||` / ` or ` / ` and ` operand, and make the lint count those members. The hand-written rows then explain why each member has the direction it has. This is the structural move that ends the per-round discovery. Without it, the next reviewer will find the next layer.
6. **Fix the date dependence (R7-7), test first.** Compute every date fixture, and `got`, inside the job that uses it; record the date at `got` and at each job's start and end; a job whose date differs from `got`'s is INCONCLUSIVE and re-run, never "killed". Prove it with the paired `date`-wrapper mutant of section 11.
7. **Make the suite GREEN on its own subject (R7-8).** Give `pr_unchanged` a fixture in which only the OLD mode is a gitlink, so `eq-unchanged-entry-dropped` has a working needle. Decide what the dynamic lint measures: either `vdir` records a count-only or message-only change as `ch` (the suite already kills on it), or the ten `need ch` rows and the `need fo` / `need both` rows are rewritten to what the mutants show. For each of the six rows that claim a fail-open form (I006, I007, I145, I146b, I150b, I151b), add a mutant that shows the fail-open form or withdraw the claim with a reason.
8. Delete each job's fixture tree once its `.res` file is written (R7-9).
9. Add the dynamic-lint needle (R7-4), re-mint the ids, merge onto current `main` (R7-5), and run the full suite three times on persistent disk, each on one calendar day, with identical counts (R7-6).

§11.4.276(E)(1): the finding class is reappearing. If round 3 of this budget still has a same-class survivor, the structural round of (E)(2) is forced. Steps 4 and 5 are that move, made early.

## 15. Is the hook safe to install?

The same answer as round 6: **it does no harm, but this review does not clear it.** The hook only `exec`s the read-only gate, and it fails closed on BLIND. R7-1 is a fail-OPEN case of the gate (an accident guard that misses one downgrade shape); it never breaks a normal commit. The false-BLIND mutants of R7-3 are mutants, not the shipped gate. Installing it is an operator-consent act, and nothing in this review installs it anywhere (checked: no `core.hooksPath`, local or global, and no non-sample hook in the live checkout).

## 16. Evidence (R = `S/rv046r7.tMNcDq`, S = the session scratchpad of the dispatch)

| Path | What it shows |
|---|---|
| `R/out/subject.tar` (`f77451f6...`), `R/subject/` | the frozen round-7 files (sha256 in section 1) |
| `R/out/static.out` | `bash -n`, shellcheck, control needle |
| `R/out/run1.log`, `R/out/run1.sha` | my full run of the author's suite; it crossed midnight (sections 4 and 11) |
| `R/out/run2.log` (`773a1963...`) | the same-day targeted run: round-6 instances killed, 13 of 17 proofs pass, 4 fail their needle (sections 3, 4 and 12) |
| `R/out/run3.log` (`68f34654...`), `R/out/run3keep/dirs.tsv`, `R/out/run3_lint16.out` | the same-day run of the 16 dynamic-lint mutants, their directions, and the author's lint run three times on them (section 12) |
| `R/out/run1_peak_tmp.txt` | peak temp tree of run1, 22 192 MiB (section 13) |
| `R/out/p_graph_missing.out`, `R/out/p_commitgraph_off.out` | R7-1 and its measured fix direction (N = 3) |
| `R/out/p_decide_realgit.out` | real git gives no asymmetric rc 128 on the decide pair (why `pr_decide` is blind) |
| `R/out/p_safedir.out`, `R/out/p_decide_oneway.out` | R7-2 refutations (N = 3), and RV7-01 / RV7-02 |
| `R/out/p_rv7_fresh.out` | RV7-03, RV7-04, RV7-05 (N = 3) |
| `R/out/p_lint_dynamic_needle.out` | R7-4 (N = 3) |
| `R/out/rv/summary.txt`, `R/out/rv/*.log` | each reviewer mutant through the unmodified suite, plus the REAL / CTLK controls |
| `R/out/mut_order.txt`, `R/probes/partial_tally.sh` | the run order of the 280 registered mutants, used to read run1's per-mutant results |
| `R/probes/*.sh`, `R/mg/*.sh` | every probe and every mutant file, ready to adopt |
| `S/con046r7_evidence/` | the author's surviving evidence (section 2) |

None of my probes reassigns HOME. Each one uses its own `mktemp -d` root with `GIT_CONFIG_GLOBAL` inside it, and removes it with `rm -rf "${t:?}"`.
