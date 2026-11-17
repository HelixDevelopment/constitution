# CON-046 review, round 6 of 6 (operator-extended budget; R_max reached): vehicle/con046 at 349f9a12

| Field | Value |
|---|---|
| Reviewer | independent (not the author); Opus; §11.4.142 / §11.4.209 / §11.4.194(6)(d) |
| Date | 2026-11-05T22:16+01:00 |
| Subject | bundle `S/con046_r6.bundle`, head 349f9a124bce64dbe294a4129772ed68740d8ad4, sha256 227f9c1d…cfa (both verified), on top of main b939266a |
| Verdict | **NO-GO.** One blocking finding, R6-1 (important, source-defect, proof-of-batch, reappearing): reviewer mutants V22 and V17 fail OPEN on header-stated guarantees and survive the author's full suite. R6-2 (9 more non-equivalent survivors, minor by impact but proof-of-batch) also stands. Every round-5 finding is closed as stated (R5-1's nine mutants are killed, R5-3 RED/GREEN reproduced), but R5-1's CLASS recurs (§11.4.276(E)(1)). At R_max the item stops for a recorded operator decision (§11.4.276(E)(3)) |
| Behaviour | the real gate answered every reviewer probe correctly; no behaviour defect found this round |
| Hook install | safe in the do-no-harm sense; NOT cleared by this review (section 7) |

## 1. Setup and integrity

- Reviewer: independent (not the author), Opus, §11.4.142 / §11.4.209. Reasoning effort is not readable from this dispatch path; no effort is claimed beyond the dispatch request (§11.4.231(F.2)).
- Workspace R = `S/scratchpad/rv046r6.8sUslJ` (S = `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46`). HOME = R/home, TMPDIR = R/tmp. The live checkout was not modified, the author's clone `con046r6.rsPwJR` was not touched (only its two `.out` files were read), nothing was pushed, and no hook was installed anywhere (every hook run below is a symlink inside a throwaway repo under R/tmp).
- Bundle `S/con046_r6.bundle`: sha256 `227f9c1d2b80c7d57534d190cef5d88df61b6ef0c47de7696cf5de8b85e49cfa` (matches the brief); `git bundle verify` after cloning: complete history; head `349f9a124bce64dbe294a4129772ed68740d8ad4` (matches).
- Live main fetched into R/repo as `refs/remotes/live/main` = `b939266a`. `bdc3ac43` is not an ancestor of that main in my fetch, so it plays no role.
- Files under review (sha256 at head): gate `scripts/gates/cm_submodule_pin_not_downgraded.sh` (298 lines, `314d4500…07cf`), test `…_mutation_test.sh` (658 lines, `4c34285d…a14`), hook `scripts/hooks/pre-commit-submodule-pin-not-downgraded` (unchanged since round 5, `95fa276c…598`).

## 2. RED / GREEN, static gates, author runs

- **R5-3 RED -> GREEN, my own probe** (`R/probes/killers_r5.sh`, `R/out/killers_on_r5.out`, `R/out/killers_on_r6.out`): A3TEXTCONV is `0/0` on the round-5 gate (`R/r5/gate_r5.sh`, sha `a1bdc35a…`, the round-5 file) — the row WAIVES again after a textconv driver hides the index difference — and `0/1` on the round-6 gate (refuses). In the same fixture the porcelain `git diff --cached --quiet` still returns 0, which proves the textconv condition was really present (positive control). Every other value of my round-5 killers is identical on r5 and r6 (KNM1=1,1 KNM2=1/1,0 KNM3=1/B,1/B KNM4=0/A,1/B KNM5=1/B,1/B KNM6=0,1 KNM9=0/A A1WTREF=0/A/vis0,0/A/vis0,1/B/vis1 A2STASHANC=0,0/A/vis0): no regression.
- **Static** (`R/out/static.out`, clean clone R/repo_static): env-reads gate PASS (gates=188 reads=170 uncovered=0 needle=ok); ledger ratchet PASS (unimplemented 394 = baseline 394); shellcheck 0.11.0 `-S warning` clean on all three files (control needle: a temp file with an unused variable gives SC2034, rc 1); `bash -n` OK on all three.
- **Author full run 1** (read-only from `con046r6.rsPwJR/full_r6_run1.out`): mutants 125, 125 `killed` lines, 0 `SURVIVED`, 0 `no vector`, hook end-to-end line OK, `exit=0 secs=4205 head=349f9a12`. Control needles: `ok mutant NM5-spent-whitespace-split killed` counts 1; a fabricated mutant name counts 0.
- **Author run 2**: Part 1 vector written (identical tokens to `want`), mutants still running when this review was written; not counted.
- **My run, Part 1** (`R/out/vecs/real.vec`): the real vector equals the 119-token `want` string. With the author's run 1 this is N = 2 identical Part-1 runs on head 349f9a12 (§11.4.50 asks for 3; run 2 is the third when it finishes).
## 3. The round-5 findings, closed or not (my own RED/GREEN)

| Round-5 finding | Status in round 6 | Evidence (mine) |
|---|---|---|
| R5-1 (important): NM1–NM5, NM9 survived; no class inventory | **The instances are closed. The class is NOT closed (see R6-1, R6-2).** | My harness ran NM1–NM9 (verbatim from my round-5 seds, NM6 adapted to `diff-index --quiet`) against the author's suite: all 9 killed (`R/out/rv_mutants.out`). NM1 is killed by KNM1GM, NM2 by KNM2, NM3 by KNM3, NM4 by KNM4, NM5 by KNM5, NM6 by AMEND/N4INDEX/KNM6, NM7 by TREEMISS, NM8 by STASH/A2STASHANC, NM9 by KNM9 (`R/out/vecs/NM*.vec`). The author's report now has a 117-row guard inventory. |
| R5-3 (minor): textconv hid an index difference from N-4 | **Closed.** | RED on the r5 gate: A3TEXTCONV `0/0` (waives). GREEN on the r6 gate: `0/1` (refuses). The porcelain diff still returns 0 in the same fixture, so the condition was really present (section 2). |
| R5-4 (minor, doc): ancestors of refs/stash are hidden | **Closed.** | Gate header lines 89–91 name it; the CON-083 text names it (needle "ancestor of refs/stash" = 1, fabricated needle = 0); fixture A2STASHANC pins the waive (`0,0/A/vis0`). |
| R5-5 (minor, doc): another worktree's per-worktree refs are invisible | **Closed.** | Header lines 92–94; the CON-083 text names `refs/worktree/*` and `refs/bisect` (needles = 1 each); fixture A1WTREF. |
| R5-6 (nit): header did not name the follow-up | **Closed in substance; landing nit remains (R6-5).** | Header line 27 names CON-083. On main b939266a, CON-083 is a different, Completed item, so the id has to be re-minted at landing. |
| R5-7 (nit): follow-up text omitted A1/A2 | **Closed.** | The CON-083 text (`R/out/con083_text.md`) names A1, A2 and RESETSQ. |
| R5-8 (nit, landing) | **Re-measured, carried (R6-5).** | `git merge-tree` of the vehicle onto b939266a: rc 1, conflicts in `config/full_suite_manifest.tsv`, `docs/Issues.md`, `docs/Issues_Summary.md`, `docs/guides/full_suite_runner_guide.md`, `docs/workable_items.db`. The gate, test and hook merge cleanly (`R/out/mergetree_b939266a.out`). |
| R5-9 (nit): one run per mutant | **Partly closed (R6-6).** | Part 1: N = 2 identical (author run 1 + mine). Mutants: NM1–NM9 now N = 2 (author run 1 + mine); author run 2 not finished. |

## 4. Reviewer-authored mutants (§11.4.194(6)(d)), run against the author's own suite

I wrote 30 mutants the author did not write: V01–V29 without V04 and V23 (27 on the gate) and HK30–HK32 (3 on the hook). Each changes exactly one line and passes `bash -n`. They ran together with NM1–NM9 in one harness: the author's test unchanged in Parts 1 and 3, with Part 2 replaced by a loop over my seds. MUT_JOBS was 3 (`R/repo/scripts/gates/rv_r6_harness.sh`, generated by `R/mkharness.py`). Result: `mutants: 39`, 26 killed, 13 SURVIVED, 0 "no vector", `exit=1 secs=2394 head=349f9a12`. The only BAD lines are the 13 survivors, and the hook end-to-end line has the expected values. Control needles: the nine NM mutants are killed, so the harness can kill. Every survivor's copied vector is byte-identical to `real.vec`, and every killed mutant's vector differs (`R/out/vecs/`).

**Killed (26):** HK30 hook-ignores-gate-exit, HK31 hook-no-readlink, HK32 hook-drops-GIT_INDEX_FILE, NM1–NM9, V01 unknown-arg-exits-1, V03 env-keeps-GIT_DIR, V05 mergehead-wrong-ref, V06 blob-cat-p, V09 conf-seen-no-space, V10 waivers-from-head, V11 author-is-committer, V14 n4-hx-is-base, V15 spent-hides-remotes (only incidentally: by K10LAZY alone), V21 horizon-minus-1, V24 forward-args-swapped, V25 meta-colon-kept, V26 blind-exits-1, V27 dstat-wrong-index.

**Survived (13).** For each survivor I ran a behaviour probe on the real gate AND on the mutant gate (`R/probes/probes_r6.sh`, `R/probes/probe_kv29b.sh`, `R/probes/probe_v28.sh`; matrix `R/out/probes_matrix.out`, `R/out/probe_kv29b.out`, `R/out/probe_v28.out`). In the matrix every probe flips ONLY for its own mutant. This proves 12 survivors are not equivalent:

| Mutant | Guard (gate line) | Real gate | Mutant | Restored defect | Header / inventory claim |
|---|---|---|---|---|---|
| V22 sub-shallow-unknown-is-complete | 288 `[ "$shallow" = false ]` | KV22 `2/1` (BLIND, "cannot be decided") | `0/0` (WARN, exit 0) | a diverged-looking move in a submodule whose shallow state is unknown passes instead of BLIND: **fail-open** on the core verdict | header 41–44 ("WARN … in a complete history", BLIND for "shallow or incomplete"); inventory G111. Submodule-side twin of NM2 |
| V17 spent-fileless-kid-ends-scan | 221 `[ "$rc" = 0 ] \|\| continue` -> `return 1` | KV17 `1/B` (redo refused) | `0/A` (redo WAIVED) | a child of the base WITHOUT a waiver file, listed before the spender (newer commit first in rev-list order), ends the scan: the same transition lands a second time (the incident class). **fail-open** | header 56–61 (spent by ANY other commit on a ref); inventory G62 marks this line `eq`, but only DELETING the line is equivalent; `return 1` is not |
| V16 spent-hides-notes | 211 `--exclude=refs/notes/*` added | KVREFS notes `1/B` | `0/A` | a spender reachable from a refs/notes ref is not counted; fail-open, contrived (a note ref does not normally hold a line of work) | header 57 ("notes refs") |
| V19 base-mismatch-aborts-rows | 239 `continue` -> `return 1` | KV19 `0/A` | `1/B` | a stale row for the same transition (bound to an older base) above a valid row refuses the valid one: **false refusal** on the documented recovery path (header 72–73: redo on a new parent) | inventory G78 "every row is tried"; pinned only at the rc-3 site (DUPROW/RM5) |
| V20 bad-expiry-aborts-rows | 240 `continue` -> `return 1` | KV20 `0/A` | `1/B` | a row with a bad expiry above a valid row refuses it: false refusal | inventory G78 |
| V18 comment-hash-anywhere | 234 `$1!~/^#/` -> `/#/` | KV18 `0` (path `a#b` waived) | `1` | a gitlink path containing `#` can never be waived: false refusal | header 52 (only a FIRST field starting with `#`), the round-6 header sentence itself |
| V07 conf-days-max-99 | 175 regex `{0,2}` -> `{0,1}` | KV365 `0/A` | `1/B` | `max_waiver_days` 100..365 disables every waiver: false refusal with a misleading message | header 104 ("integer 1..365") |
| V08 conf-days-365-exclusive | 175 `-le 365` -> `-lt 365` | KV365 `0/A` | `1/B` | the stated inclusive upper bound 365 disables every waiver | header 104 |
| V13 casefold-to-lower | 193 `casefold()` -> `lower()` | KV13 `1/B` (committer `Strauss`, authoriser `STRAUß`, refused) | `0/A` | self-waive through a casefold-only equivalence (fail-open, needs deliberate spelling) | header 98–99 ("NFC + casefold") |
| V12 authoriser-only-Cc | 192 `startswith("C")` -> `=="Cc"` | KV12 `1/B` (authoriser `o<U+200B>ps`, committer `ops`, refused) | `0/A` | self-waive with a format character (fail-open, deliberate) | header 98 says "control characters" only; the code rejects every Unicode C* category, so the header understates what the code does and nothing pins the wider rule |
| V29 python-not-isolated | 247 `python3 -I -c` -> `python3 -c` | KV29B `1/1,1/1` (refused with and without a hostile `PYTHONPATH`) | `1/1,0/0` | a `sitecustomize.py` on PYTHONPATH rewrites `unicodedata.normalize` and the self-waive passes (fail-open, needs a hostile environment) | not in header or inventory (hardening the code has and nothing pins). Note: on this host `sys` and `unicodedata` are BUILTIN modules, so planting `unicodedata.py` in the cwd is NOT a killer (KV29PLANT is `1/1` on both); only the start-up hook path is |
| V02 help-exits-1 | 137 `exit 0` -> `exit 1` | KV02 `0` | `1` | `-h` exits 1 | no claim (HELP checks the text only) |
| V28 missing-checkout-no-empty-check | 270 `[ -z "$subp" ] \|\|` dropped | absent/file/mode000/emptydir = `2/1 2/1 2/1 2/0` | identical | none found | **equivalent**: `cd` fails exactly when `git -C` does. Not a finding |

## 5. Findings

| Id | Severity | finding_layer | Minor-class? | Text |
|---|---|---|---|---|
| R6-1 | **important** | source-defect (proof-of-batch, §11.4.235(D) / §11.4.194(6)(d)) | **no, blocks GO** | Two reviewer mutants that fail OPEN on guarantees the header states survive the author's full suite: **V22** (unknown submodule shallow state turns BLIND into WARN, exit 0) and **V17** (a waiver-less sibling commit ends the spent scan, so a reviewed rollback re-lands on the same parent; inventory row G62 wrongly marked `eq`). The runtime behaviour of the real gate is right in both cases (KV22, KV17), which is why this is important and not critical. **Reappearing finding (§11.4.276(E)(1))**: V22 is the submodule member of NM2's class (shallow state unknown), and round 5 named that class. |
| R6-2 | minor by impact | source-defect (proof-of-batch) | **no** (§11.4.276(G.2) excludes the proof-of-batch surface) | Nine more non-equivalent reviewer mutants survive: V07, V08, V18, V19, V20 (false refusals against stated bounds or rules), V16 (contrived fail-open), V12, V13, V29 (authoriser self-waive hardening; outside the header's declared ACCIDENT threat model, header lines 19–20 and 107–110). Each has a ready killing probe (section 4). Listed apart from R6-1 so that an operator re-scope can treat it differently. |
| R6-3 | nit | test-instrumentation | yes | V02: the `-h` exit status is not asserted (no header claim). |
| R6-4 | nit | process-doc | yes | Header line 98 says "control characters", but the code rejects every Unicode C* category (format, private-use, surrogate, unassigned). State the real rule, or narrow the code. |
| R6-5 | nit | process-doc (landing) | yes | (a) Follow-up id CON-083 collides on main b939266a: CON-083 there is a Completed item (parse_mutation.py test), and CON-070..091 are taken. Re-mint to CON-092 or higher through the engine and update gate header line 27 and the tracker text (the author acknowledges this). (b) The 5 conflicting files (section 3, R5-8) must be regenerated through the workable-items engine and the manifest tooling, never edited by hand. (c) `--verify-manifest` on the vehicle gives rc 3 with 25 problems, none about this gate; on main b939266a it gives 3 different problems. The author's "equal to main" held only against the older base. Re-check after the merge. |
| R6-6 | nit | process-doc | yes | §11.4.50: Part 1 is N = 2 (author run 1 + mine); author run 2 had not finished (its file holds only the Part-1 vector, identical). `docs/qa/con046_review/` carries the reviews of rounds 2–5 but not the round-1 review `review_con046.md`. |

**Structural recurrence (§11.4.276(E)): YES.** One class has now appeared in three consecutive rounds: *a guard the header (or the author's own inventory) claims, or a member of a claimed guard class, with no fixture that kills a reviewer-authored mutant.* It was round-4 M-4, then round-5 R5-1 (6 of 9 reviewer mutants survived), and now round-6 R6-1/R6-2: 12 of my 26 non-equivalent gate mutants (V01–V29) survive.

The round-6 inventory works at ROW granularity: one guard line, one mutant. The survivors sit at MEMBER level inside rows the inventory marks covered:

| Inventory row | Uncovered member | Mutant |
|---|---|---|
| G30 | the 100..365 range and the inclusive 365 | V07, V08 |
| G40 | non-Cc C* categories | V12 |
| G41 | casefold vs lower | V13 |
| G56 | the notes namespace, and remotes, which are covered only incidentally | V16, V15 |
| G75 | `#` anywhere vs leading `#` | V18 |
| G78 | 9 of the 10 `continue` sites | V19, V20 |
| G111 | `unknown` vs `true` | V22 |

One survivor (V17) sits in a row the inventory marks equivalent (G62), where the equivalence was judged for one mutation of the line, not for the line's behaviour.

So the round-5 instruction (§11.4.276(C): enumerate the class on its first instance) was followed at line level, but not at member level.

## 6. Per-slice verdicts

| Slice | Verdict | Why |
|---|---|---|
| Gate `cm_submodule_pin_not_downgraded.sh` | **NO-GO (unproven, behaviour correct)** | Every behaviour probe this round gives the right answer on the real gate: 13 probes plus KV29B, V28 shapes, my round-5 killer set and A3TEXTCONV. I found no behaviour defect. It is not proven-correct per §11.4.235(D) while R6-1/R6-2 stand. |
| Mutation test `…_mutation_test.sh` | **NO-GO** | R6-1, R6-2 (and R6-3). The fix is mechanical: each non-equivalent survivor has a killing probe in `R/probes/probes_r6.sh` / `probe_kv29b.sh`, proven by the matrix (it flips only for its own mutant). |
| Hook `pre-commit-submodule-pin-not-downgraded` | **GO in isolation** | Unchanged since round 5. Reviewer mutants HK30–HK32 are killed, and Part 3 end to end is right (downgrade rc 1, forward rc 0, real-submodule worktree, persist/snapshot, layout SKIP). It only runs the gate, so its use follows the gate decision. |
| Tracker / docs / manifest | **GO-with-follow-ups** | R5-4/5/7 are closed. R6-5 and R6-6 are landing work only. |

**Overall: NO-GO.** R6-1 is important and a reappearing finding. This is round 6 = `R_max` (operator-extended), so §11.4.276(E)(3) applies: the item STOPS here (no round 7 under this approach) and needs a recorded operator decision. No §11.4.271 waiver is eligible for R6-1, because it is important, not residual LOW. Options, the operator's to take:

1. **Re-scope (§11.4.148):** land the gate and hook as defensive hardening on the behaviour evidence (`R/out/probes_matrix.out` and the reviewer probes of rounds 5–6), with R6-1/R6-2 as a tracked test-instrumentation follow-up. As in round 5, I do not take that reading myself, because §11.4.235(D) names a surviving reviewer mutant a source-defect. Only an operator decision can take it.
2. **Replace via a new structural item** with a fresh budget, whose first act adopts the 11 killing probes verbatim (they kill all 12 survivors; KV365 kills both V07 and V08) (KV17ORDER, KV22SUBUNKNOWN, KVREFS-notes, KV19STALEFIRST, KV20BADEXPFIRST, KV18HASHMID, KV365, KV13SHARPS, KV12ZWSP, KV29B, KV02HELP) and redoes the inventory at MEMBER level: every alternative value or site inside each guard, and an equivalence judged per behaviour, not per mutation.

## 7. Is the hook safe to install?

**Safe in the sense of doing no harm, but NOT cleared by this review.**

What makes it safe in that sense:
- The hook only `exec`s the read-only gate. The gate uses plumbing, takes no lock, and writes nothing.
- It fails closed on BLIND (exit 2).
- It prints an honest SKIP when its gate is missing.
- On every probe I ran, the real gate decided correctly, with no unintended false refusal and no fail-open.
- The documented residuals (RESETSQ, FETCH_HEAD squash, A1, A2, notes and others) remain as stated in the header.

Why it is not cleared: GO is not reached, and installation is an operator-consent act under the §11.4.276(E)(3) decision. If the operator installs it as an accident guard now, I measured nothing that would break a normal commit flow. It would ship with a test suite that does not yet kill 12 reviewer mutants.

## 8. Evidence (all under R = `S/scratchpad/rv046r6.8sUslJ`)

- Harness and result: `R/repo/scripts/gates/rv_r6_harness.sh` (untracked, generated by `R/mkharness.py`); `R/out/rv_mutants.out` (sha256 `86f26685ea08853c8c5be978027d19b265675c3feb44d9e15a086fac5105c85d`); vectors `R/out/vecs/*.vec`; mutant seds `R/vm/*.sed`.
- Probes:
  - `R/probes/probes_r6.sh` (`ed4df88b…d6ba8`), `R/probes/probe_kv29b.sh` (`dd7be3d7…a57dc`), `R/probes/probe_v28.sh` (`ea45bea7…df6a5`);
  - mutant gate copies `R/mg/*.sh`;
  - matrix `R/out/probes_matrix.out` (`48c14484…401670`), `R/out/probe_kv29b.out` (`91b55099…a6a7`), `R/out/probe_v28.out` (`93bb26f0…d87`).
- Round-5 RED/GREEN: `R/probes/killers_r5.sh`, `R/r5/gate_r5.sh`, `R/out/killers_on_r5.out`, `R/out/killers_on_r6.out`.
- Static, merge and manifest: `R/out/static.out`, `R/out/mergetree_b939266a.out`, `R/out/verify_manifest.out`, `R/out/verify_manifest_main.out`.
- Author runs, read only: `S/scratchpad/con046r6.rsPwJR/full_r6_run1.out` (complete) and `…/full_r6_run2.out` (Part 1 only at review time).
