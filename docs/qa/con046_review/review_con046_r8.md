# Independent review: CON-046 round 8 (CON-146), CM-SUBMODULE-PIN-NOT-DOWNGRADED

| Field | Value |
|---|---|
| Subject | `scripts/gates/cm_submodule_pin_not_downgraded.sh`, its hook `scripts/hooks/pre-commit-submodule-pin-not-downgraded`, the mutation test, member generator, inventory and `members_eq.tsv` |
| Bundle | `con046_r8.bundle`, sha256 244ebdea...ae51, head eca2f4f1 (`vehicle/con046r7`), prerequisite main 2e8cfb90 |
| Reviewer | independent subagent. Did not author the change. |
| Model | Opus 5.5 (`claude-opus-5-5`) |
| Effort | not verifiable through the Agent-tool dispatch path (§11.4.231(F.2)) |
| Date | 2026-11-11 |
| Verdict | **NO-GO** |

## 1. Setup and integrity

- I cloned into my own scratch directory (`.../74ce2b36-.../scratchpad/rv8/base` and the worktree `rv8/head` at eca2f4f1). I fetched the prerequisite 2e8cfb90 read-only from the GitHub mirror, and its tip there is 2e8cfb90. Nothing was pushed or tagged, and `/home/milosvasic/Projects/constitution` was not touched.
- `docs/qa/con046_review/r8_runs/SHA256SUMS`: every entry OK.
- The author's runs 1-3 on 5834ce3d each report `mutants: 408 (killed 377, survived 0, equivalent-with-proof 30, inconclusive 0)` with lint findings 0. Commits 5834ce3d..eca2f4f1 change only docs, run evidence and the tracker db.
- Host facts: git 2.53.0. The default `date` is uutils coreutils 0.8.0 (`/usr/bin/date -> ../lib/cargo/bin/coreutils/date`). GNU date 9.7 is at `/usr/bin/gnudate`.

## 2. Round-7 items

| Item | Status | Evidence |
|---|---|---|
| R7-1 (`core.commitGraph=false`) | CLOSED | p_graph_missing, N=3: DOWNGRADE=2 (BLIND), CTL=1, NOGRAPH=2. A mutant without `-c core.commitGraph=false` gives a WARN. My two extra shapes: PROMISOR gives BLIND on both the real gate and the no-graph mutant. ALTGRAPH (commit-graph in an alternate, commit M deleted): the real gate gives BLIND, the no-graph mutant gives FAIL (N=3, `rv8/out/p_r8_store.out`). |
| R7-2 (probes adopted) | CLOSED | The four probes are byte-identical (sha256) to the round-7 reviewer originals. |
| R7-3 (RV7-01..05) | CLOSED | All five are killed in runs 1-3. |
| `need` corrections I085, I085b, I144b | SOUND | The shallow branch falls through to `[ "$kidsrc" = ok ] \|\| return 2`. A says-spent waiver is still refused. When the git-dir check is dropped, the toplevel check (I145) catches it (SUBBROKEN fixture). |
| Date-skew INCONCLUSIVE | SOUND as built | The selftest-date-skew and judge unit checks print ok in all runs. See F3 for the date-implementation gap. |
| Merge of main 2e8cfb90 | SOUND | The merge commit 122fc249 has parents 420551e4 and 2e8cfb90. The diff from main touches only con046 files, the tracker docs/db, one manifest row and one guide line. Tracker: CON-146 and CON-147 exist in `docs/workable_items.db`, the max CON id is 147, CON-108/109 are distinct items, and no id collides. |
| Generated members (118 viable) | Ledger regenerates byte-identical (LEDGER-MATCH, 118 rows) | Coverage gaps are in F5. |

## 3. Reviewer-authored mutants (§11.4.194(6)(d))

Each mutant was run against the suite with `GATE_UNDER_TEST=<mutant>` (Part 1 classify vector plus Part 3 hook), once per mutant, under uutils date. Logs are in `rv8/runs/`.

| Mutant | Change | Suite result | My probe |
|---|---|---|---|
| RV8-01 | line 200 `f(i.strip())==f(a)` -> `f(i)==f(a)` | **SURVIVED** (rc 0) | NBSPTRAIL=0, NBSPLEAD=0: the self-waive is accepted, which is fail-open |
| RV8-02 | line 198 `a!=a.strip()` -> `a!=a.strip(" \t\n")` | **SURVIVED** (rc 0) | AUTHUSPACE=0: an authoriser "me"+U+3000 is accepted, where the real gate gives 1 |
| RV8-03 | line 151 `-gt 0` -> `-ge 0` (a member the generator never emits, see F5) | killed (LEV=0/0 vs 2/1) | - |
| RV8-04 | `blob()` `cat-file blob ... \|\| return 2` -> `\|\| return 1` | killed (KCONF, CHILDTREE, K13TELL, K10LAZY) | - |
| control REAL | unchanged gate, uutils date | rc 0 | all probes 1 |
| control REALGNU | unchanged gate, GNU date first on PATH | rc 0 (the classify vector equals `want`) | - |

So 2 of my 4 mutants survive the suite, and both are fail-open on the authorisation surface.

## 4. Attack on the 13 equivalence claims in `members_eq.tsv`

The probe is `rv8/probes/p_r8_eq.sh`. It uses real git and real date tools, with fixture "true downgrade + one waiver row". Run N=3 with identical results. A mutant that exits 0 (WAIVED) where the real gate exits 1 is fail-open.

| Claim | Result |
|---|---|
| gen-strip-38f694f31b (identity: lstrip only) | **FALSE.** With NBSPTRAIL the real gate gives 1, the mutant 0. The claim "git var strips whitespace from both ident fields" holds only for ASCII. Git keeps a trailing or leading U+00A0 in ident names (checked with od). |
| gen-strip-a8ce0752e7 (identity: rstrip only) | **FALSE.** With NBSPLEAD the mutant gives 0. |
| gen-rxq-9efb96babf (year `{4}` -> `{4,}`) | **FALSE under GNU date**, which is the date the gate header names as its dependency. YEAR5GNU (`max_waiver_days=365`, expiry `<this year>9-01-01`): the mutant gives 0. GNU date 9.7 round-trips five-digit years (10000-01-01, 20265-01-01, 99999-12-31). A string like `20269-01-01` passes both the lexicographic expiry compare (`> today`) and the horizon compare (`< 2027-...`). With the default 30 days the same thing happens whenever the horizon crosses into the next year (December). Under uutils date (YEAR5UU) the mutant gives 1, which is why the suite's proof passes on this host. |
| hand proof eq-expiry-regex-dropped (whole regex dropped) | **FALSE under GNU date** (YEAR5GNU = 0). The round-7 note "GNU date 9.x rejects five-digit years, measured on this host" in fact measured uutils. |
| other expiry members (`^`, `$`, month/day `{2,}`) | Hold, including under GNU date: the round-trip output is canonical, so these loosened forms are refused anyway. |
| gen-andor-5d778c1c49 (need argc) | holds |
| gen-rxq-1faaa1a2b7 (`{0,3}` days) | holds (`-le 365` refuses) |
| gen-strip-99db10f56c, gen-strip-7144af3e42 (truthiness halves) | hold |
| gen-pybool-6ef1faee03 | holds. A brute force over all code points finds no non-C character whose `f()` is empty. |
| gen-andor-2468ed98ae (V28) | exit-equivalent. An empty `subp` is BLINDed by the next symlink check. |

Totals: 3 of the 13 generated claims are false, plus 1 hand-written proof. All four are fail-open on the authorisation and expiry surface, and the suite counts them as "equivalent-with-proof".

## 5. Findings

| # | Severity | finding_layer | Finding |
|---|---|---|---|
| F1 | important | source-defect (it invalidates proof-of-batch evidence) | Three `members_eq.tsv` claims are false (gen-strip-38f694f31b, gen-strip-a8ce0752e7, gen-rxq-9efb96babf), and all three are fail-open. The suite's "equivalent-with-proof 30" count includes them, so the "survived 0" headline overstates what is killed. |
| F2 | important | source-defect | The hand-written proof `eq-expiry-regex-dropped` (mutation test around line 1531) is false under GNU date. The round-7 claim that GNU date was measured is wrong: the measurement was uutils. |
| F3 | important | source-defect | The suite does not pin or require a date implementation. Every date-dependent verdict and proof on this host runs under uutils, while the gate header says the gate depends on GNU date. A suite run cannot show which date it ran under. |
| F4 | important | source-defect | The reviewer mutants RV8-01 and RV8-02 survive the suite. `pr_identpad` (around line 819) and the authoriser-form fixtures use ASCII padding only, and there is no non-ASCII whitespace fixture (NBSP, U+3000) for either the identity or the authoriser. The gate itself handles these cases correctly; the guard set cannot see them. |
| F5 | minor | test-instrumentation | The member generator's CMP regex `(?<!\[)\[ ([^\]]*?) \](?!\])` skips any single-bracket test that contains `]`. Lines 151 and 300 therefore get no CMP/ANDOR members, although the docstring promises "every operator of a single-bracket test". The `[[ ... ]]` string compares (`<`, `>`, `!=` in the expiry and horizon checks) are outside the generated operator set. RV8-03 shows the line-151 member is killed by LEV, so this is a coverage-claim defect, not a live hole. |
| F6 | nit | test-instrumentation | ALTGRAPH: a store whose ancestry the commit-graph could decide now gives BLIND (conservative, acceptable). The cost of the no-graph walk on very large submodules is not measured (UNCONFIRMED). |
| F7 | process note (no severity) | process-doc | This is round 8. §11.4.276(G) sets `R_max` to 5 (6-7 only by a recorded operator decision naming the item). I did not find such a decision in the bundle, so whether it exists is UNCONFIRMED. If it does not exist, the next step is the (E)(3) operator escalation, not round 9 under the same approach. |

Counts: 0 critical, 4 important, 1 minor, 1 nit (plus 1 process note).

## 6. Per-slice verdict

| Slice | Verdict |
|---|---|
| Gate source (`cm_submodule_pin_not_downgraded.sh`, `sg()` change) | GO on behaviour. All my probes classify correctly under both date implementations, and REAL plus REALGNU match `want`. |
| Hook | GO (Part 3 passes for REAL and REALGNU) |
| Mutation test, equivalence ledger, generator (proof-of-batch stack) | **NO-GO** (F1-F4 are important) |
| Tracker and merge | GO |

The overall verdict is **NO-GO**, because important source-defect findings sit on the proof stack (§11.4.235(D), §11.4.276(G): important findings are never minor-class).

## 7. Recommended remedies (class-wide, not instance)

1. Withdraw the three false generated claims and the false hand proof. Make the four mutants killed members, each with a fixture that kills it.
2. Add non-ASCII whitespace fixtures (U+00A0 and U+3000, leading and trailing) for both the identity and the authoriser. Enumerate the Unicode `Zs` class with a control needle rather than picking single characters.
3. Make the suite pin the date implementation: assert GNU date and print the version in the run record, or run every date proof under both implementations and record both. Add a five-digit-year fixture (YEAR5GNU shape) to the classify vector.
4. Fix the generator's bracket regex so tests containing `]` are covered, and extend the operator set to `[[ ]]` string compares, or state that the class is narrower.
5. Re-validate every remaining `members_eq` argument against both date implementations and against non-ASCII input before calling it equivalent.

## 8. Evidence (sha256)

All paths are under `/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/74ce2b36-bc1b-48fc-b31c-c523fed7b15e/scratchpad/rv8/`.

| File | sha256 |
|---|---|
| probes/p_r8_eq.sh | 0f33ac3eeb3f76f56ff63b3da09607734e44875d280f85b035767007ad23b0cb |
| probes/p_r8_store.sh | d4c77e949655388d56445ceaac7a6a1f7f76813811f019fa948f0daf9d4f8d56 |
| probes/nograph_gate.sh | 53c86003db9a499f3a7bd6a2475d811d6e4532795ba077ef941e40c3b65a48b8 |
| out/p_r8_eq.out | 537695a1bf8e127313aff78be98c2da04e45ee09753b45f8939ede66316fb583 |
| out/p_r8_store.out | e8fbdff84507a8d2a177e348b5ce089b56e265a23fb4133803cf9211490029c6 |
| out/members.now | 8c2cd88eea2188be9f71f606328003e3ccd2c39f4354ce10963daf6233af1385 |
| mut/REAL.sh | 43edf892e6234163b01c1c472e549e5ab002c12d4dc5db163d1dcc9f8a0c3f4d |
| mut/RV8-01.sh | f6d577797d272ca7e9dd35bbfbb6bd4e21b7d3238186f1838e4c9775207161c9 |
| mut/RV8-02.sh | 9b4da1627586de499f4d4d25b1a9a7dbc42e8c8a7bf4d17d051be657d1b84e67 |
| mut/RV8-03.sh | e6f525d208f6b814443a1105695ec4860fd3e1f887a411a9e6de995306b61e14 |
| mut/RV8-04.sh | d9e1f30979c41d11ec2d73b3799981b19bebd3abfe055b0857c34f800b01395e |
| mut/eqh-expiry-regex-dropped.sh | 687866d992056e8943fdfc02faf816cbad659ceeeb4639c8d57abd701bae8a43 |
| runs/REAL.log | 0271235ad0e3ffcda2d9ae5de4ef9a252453224b9aa99be11bd8f76ad61d0a28 |
| runs/REALGNU.log | 9c185e3f4d4ac0c8cec1a2f57403c20f14b07dc13338e1349461d46881fb589d |
| runs/RV8-01.log | 3a917f0c62e09556f90ce0d43ba07e735cfd76479d2d55a2e1f10174c44fb278 |
| runs/RV8-02.log | 007c0b6b864bf3e15eff6aea6d979c77af05495675469132c4a448a1215dfed4 |
| runs/RV8-03.log | a3e788ecc6e865c51248718661f3fac5d8ad243027a61a55a39f7dde233a64cf |
| runs/RV8-04.log | 816bfd53d925d6bc073ac9660c39e21cab18a5f96fb1785d42b8d973a592f7d6 |

Honest limits:
- My suite runs are Part 1 plus Part 3 only, through `GATE_UNDER_TEST`. I did not re-run the full 408-mutant Part 2 (about 90 min); I relied on the author's runs 1-3 for it.
- Each mutant ran once against the suite. The probes ran N=3.
