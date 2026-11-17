# Independent re-review, CON-046 round 3 (vehicle/con046)

| Field | Value |
|---|---|
| Reviewed head | 0b79d0c0d44d9422f8fd6e2f1f8dd2616e11850a (parent 4402ae8 = merge of main 8e496db) |
| Bundle | con046_r3.bundle, range origin/main..vehicle/con046 |
| Reviewer | independent subagent, Opus 5.5; effort not settable or readable on this dispatch path (11.4.231(F.2)), so no effort is claimed |
| Round | 3 of 5 (11.4.276(G)) |
| Method | read-only; every probe in throwaway copies under `scratchpad/rv046r3.FmfeWC/` with `HOME=$(mktemp -d)`, `${VAR:?}`-guarded deletes; no clone modified; no secret-named variable printed |
| Verdict | **NO-GO**: 1 important finding (R3-I1, source-defect, the same waiver-lifetime class as R2-I1), plus minor and nit findings |
| CON-046 | stays open as defensive hardening (11.4.115(G)); consistent in report, commit message and header |

## 1. What was checked and what held

### R2-I1 replay through the real hook: FIXED for single-parent commits
Real submodule (`git submodule`-style clone at `sub`), hook symlinked into `.git/hooks/pre-commit`, sequence: reviewed rollback B->A with a new waiver row (WAIVED, rc 0), forward A->B without moving the checkout (rc 0), then a snapshot commit.

| Snapshot form | Head gate | Old gate 2fbbf3d (RED control) |
|---|---|---|
| `commit -a` | rc 1, pin stays B, reason "waiver row already in the base commit" | rc 0, pin A (downgrade landed) |
| `add -A` + commit | rc 1, pin B | (not rerun) |
| `commit --amend -a` | rc 1, pin B | (not rerun) |
| `commit -- <paths>` | rc 1, pin B | (not rerun) |

Evidence: `rv046r3_p1.out`, `rv046r3_p1_red.out` (the first RED attempt ran without the hook because `git show >` drops the exec bit; git printed "hook was ignored"; re-run after `chmod +x`).

### Prior findings status

| Prior | Status at 0b79d0c | Evidence |
|---|---|---|
| R2-I1 waiver persists in HEAD | FIXED for the HEAD case; the class is NOT closed (R3-I1 below) | p1, p7, p7b, p8 |
| R2-m1 shallow forward refused | FIXED (forward checked first; T1 rc 0) | p4 T1 |
| R2-m2a index unreadable | FIXED (mode 000 -> BLIND rc 2) | p3 R7 |
| R2-m2b diff exit ignored | FIXED (PIPESTATUS checked) | read + p3 |
| R2-m3 authoriser check weaker than stated | FIXED: `--author` and `-c user.name` both compared (W-B, W-B2 refused), NFC+casefold in python3 | p2 |
| R2-m4 `CON-NNN` hard-coded | FIXED (`item_prefix` from base config, validated) | p5 K4 |
| R2-m5 surviving reviewer mutants | FIXED for the five r2 mutants (in the 44) | suite |
| R2-m6 hook-level RED / real submodule | FIXED (Part 3 real worktree submodule + persist replay) | suite Part 3 |
| R2-n1 help range | FIXED (help prints 73 lines, whole header) | read |
| R2-n2 sentinel in message | FIXED (real rc and shallow flag printed) | p4 T2/T4 |
| R2-n3 CRLF | FIXED (CRLF vector 1/1, named) | vector |
| R2-n4 env list | FIXED (`git rev-parse --local-env-vars`, keeps CONFIG_PARAMETERS/COUNT) | read |
| R2-n5 awk `-v` escapes | FIXED (ARGV) but see R3-n1 (numeric compare) | p2 W-E |
| R2-n7, n9 | FIXED | shellcheck, read |
| R2-n11 lazy fetch | FIXED in code (`GIT_NO_LAZY_FETCH=1`), not tested (R3-m3, RV7) | read |

### Decision table, independent fixtures (p4): all correct
T1 shallow provable forward -> ok rc 0; T2 shallow, relation hidden -> BLIND rc 2 naming shallow; T3 new object absent -> BLIND; T4 complete history with a deleted intermediate object -> BLIND (rc 128/128, shallow=false); T5 `replace --graft` -> still FAIL (replace refs ignored); T6 symlinked submodule -> BLIND; T7 `--root` subdir with `diff.relative=true` -> FAIL, and T7b the real hook from a subdir -> refused; T8 FAIL + BLIND in one commit -> exit 1; T9 both pins at the shallow boundary -> BLIND. Wrong-read probes (p3): color forced, `diff.external`, `noprefix`, `quotePath`, `renames=copies`, `mnemonicPrefix`, `GIT_EXTERNAL_DIFF`, `submodule.recurse` + `submodule.sub.ignore=all`, commit-graph, superproject `blob:none` partial clone: all still FAIL the downgrade. Exception: legacy grafts (R3-m1).

### Other checks
- python3 absent from PATH: waiver not honoured, FAIL rc 1 ("python3 missing"), not fail-open (W-F). python3 that always exits 1: FAIL (W-F2, but misleading message, R3-n4).
- `--amend` honesty: env names in the hook are identical for `commit` and `--amend` (p6), so the documented "cannot see --amend" limitation is true; `--base REV` works (`--base HEAD^` catches W-C).
- Config read from the BASE commit, not the index: duplicate key, unknown key, bad prefix, out-of-range `max_waiver_days`, unreadable (tree) config each disable waivers only, with a named reason (p5 K1-K5 on the real gate).
- Env reads (`cm_gate_env_reads_allowlisted.sh`): main 8e496db gates=187 reads=170 uncovered=2; head gates=188 reads=170 uncovered=2, so the new gate adds no env read. Note: that gate's VERDICT is FAIL on main and head alike, because of the same 2 pre-existing uncovered `eval` reads in `cm_geo_substitute_anchor_wired.sh:320` and `cm_state_fields_anchor_wired.sh:405`; not introduced by this change, but main is not green on this gate.
- Gate ledger ratchet: unimplemented 394 = baseline 394, PASS on main and head.
- Evidence for both and for the `--amend` hook environment: `rv046r3_envledger_p6.out`.
- `bash -n` clean, shellcheck info-level only.
- 11.4.250 tower check: no tower. `--no-relative` and a bash empty-authoriser check were removed when they became equivalent; the read path is one decision table with one BLIND exit. Agrees with the author's "replaced, not layered" claim for the read class. The waiver lifetime class is where a new rule was layered (novelty on top of binding + expiry), and it is still leaking (R3-I1).
- Trailer `Co-Authored-By: Claude Opus 5.5` present.
- Full paired mutation suite: see section 4.

## 2. Findings

### R3-I1 important (finding_layer: source-defect): a waiver row consumed on a branch is "new" again when that branch is integrated, so it silently permits a later downgrade of the same pin; the header claim is false for merges and squashes

The novelty rule compares the row with the waiver file of ONE base commit (the hook's HEAD). It does not ask whether the row was ever consumed in history. On branch X: reviewed rollback B->A with row R (WAIVED), then X is moved forward A->B without moving the submodule checkout (the incident precondition: the pin advances, the checkout stays at A). On `main`, R is not in HEAD's waiver file, so any integration that stages X's waiver file makes R "new" again, and the stale checkout (A) is picked up by `commit -a`:

| Integration (single worktree, real hook) | Result |
|---|---|
| conflicted `git merge X`, concluded with `commit -a` | WAIVED, merge commit lands pin A (p7) |
| `git merge --squash X` + `commit -a` | WAIVED, pin A on main (p7b, p8) |
| `git merge --no-commit --no-ff X` + `commit -a` | WAIVED, pin A on main (p8) |
| control: same sequence without R | FAIL |

p8 is a natural single-worktree sequence (no checkout moved by hand; the forward on X is index-only, which is what a merge or pull that does not run `git submodule update` does). The header lines 46-47 ("a row committed with an earlier rollback cannot permit a later downgrade of the same pin") are false for these paths.

Bound: the row must still be inside its expiry window (at most today + `max_waiver_days`, default 30) at the time of reuse. That limits the window; it does not make the downgrade visible, and the gate reports it as a reviewed waiver.

Why important and not minor: it is the same class as R2-I1 and round-1 I-3/I-4 (a waiver valid more broadly than the one event it was reviewed for), the protected property is the incident itself (a stale checkout silently rolling a pin back), and the gate's own text claims the case is closed. Under 11.4.276(E) this is a reappearing class with a non-minor member at round 3+, so the next round should be structural.

Instance-level fixes do not close it. I tried the obvious one (also count rows in `MERGE_HEAD`'s waiver file as old): it closes the real-merge and `--no-commit` cases but not `--squash`, which leaves no `MERGE_HEAD` (p8 with `fixlay`). Cherry-pick of the rollback commit and leftover rows (R3-m2) are further members.

Suggested class-level replacement (prototype, NOT a patch for the author to copy unreviewed): bind each row to the base commit it was reviewed against, as a 7th field, and drop the novelty rule. A row then waives exactly one transition in exactly one commit on top of exactly one parent, which is what the header means. I prototyped it in a scratch copy (`rv046r3_p9_bind_prototype.diff`, 2 changed lines + 1 removed line): B1 legitimate rollback WAIVED, R2-I1 snapshot refused; B2 leftover row bound to an older HEAD refused; B3 natural squash integration refused (`rv046r3_p9_bind_prototype.out`). Not checked in the prototype: amend flows, cherry-pick, the 7-field form in the test vector, and the case where a row bound to the current HEAD is left in the worktree with no commit in between (that one would still be honoured).

### R3-m1 minor (source-defect): legacy `info/grafts` in the submodule turns a downgrade into DIVERGED (WARN, exit 0), and it lands through the real hook

`GIT_NO_REPLACE_OBJECTS=1` disables replace refs but not the legacy grafts file. With `<sub gitdir>/info/grafts` listing B as parentless, `is-ancestor A B` returns 1 both ways, the submodule is not shallow, and the gate reports `WARN ... DIVERGED`, exit 0; the real hook commits pin A (p3 R1, p3b). The header says the read ignores replace refs; grafts are the same wrong-read class member beside them, missed by the class inventory (11.4.276(C)). Fix checked in a scratch copy of the gate with `GIT_GRAFT_FILE=/dev/null` added to `sg()`: the same fixture gives head gate WARN rc 0, fixed copy FAIL rc 1 (`rv046r3_p3c_graftfix.out`; git-level check in p3b). Grafts are deprecated in git 2.53 (git prints the hint), so the reach is small.

### R3-m2 minor (process-doc, same class as R3-I1): a leftover row in the worktree is picked up by a later snapshot commit

A row written into the waiver file and never committed (an abandoned rollback) is staged by a later `add -A` (untracked file) or `commit -a` (tracked file) and waives the stale-checkout downgrade in that snapshot (W-A1, W-A3 WAIVED; W-A2 untracked + `commit -a` refused). The row is visible in that commit's diff, so this is less silent than R3-I1, but the snapshot author did not intend it. Base-commit binding closes it whenever any commit happened in between (B2). Until then, document it.

### R3-m3 minor (test-instrumentation): 7 reviewer-written mutants survive the author's suite (11.4.194(6)(d))

All seven are killed by small fixtures against the real gate (`rv046r3_killers.sh`, `rv046r3_p5.out`), so the gate is right and the suite is missing the case.

| Mutant | Change | Killer fixture (real -> mutant) |
|---|---|---|
| RV1 | base config unreadable treated as absent | K1 base config is a tree: real FAIL (waivers disabled) -> mutant WAIVED |
| RV2 | base waiver file unreadable ignored | K2 base waiver file is a tree: FAIL -> WAIVED |
| RV3 | duplicate config key allowed | K3: FAIL -> WAIVED |
| RV4 | `item_prefix` not validated | K4 `item_prefix=C.N`: FAIL -> WAIVED |
| RV5 | 365 cap removed | K5 `max_waiver_days=400`, expiry +45: FAIL -> WAIVED |
| RV6 | "path is not its own repository" check removed | K6 no `.git`, parent holds the commits, B->S: BLIND -> PASS (silent) |
| RV7 | `GIT_NO_LAZY_FETCH=1` removed | no fixture (lazy fetch is untested; the author's report says so) |

The author harness run with RV1-RV7 added: `rv046r3_rv_mutants.out` (vector unchanged, all 7 SURVIVED).

### Nits
- R3-n1 (source-defect): the awk filter compares `$1==p` with ARGV values, which gawk compares numerically when both look numeric (strnum). A row for path `10` or `010` waives a gitlink at `1e1` (W-E; control `1e2` refused). Fix: `$1""==p""` (and the same for old/new). Reach is tiny.
- R3-n2 (source-defect): `--amend` can strip or change the waiver of an already-waived commit unchecked (W-C), and a WARN move followed by an amend to an ancestor of the parent pin lands an unwaived downgrade against the real parent (W-D). Both are the documented `--amend` limitation; `--base HEAD^` catches W-C. Worth one line each in the NOT ENFORCED block.
- R3-n3 (process-doc): the commit message says "--no-relative is passed", but the gate no longer passes it (0 occurrences); the author's report says it was dropped as an equivalent mutant. The commit message is wrong, the code and report agree.
- R3-n4 (source-defect): any python3 exit 1, including an uncaught exception, is reported as "authoriser ... is the committer or author (producer cannot self-waive)" (W-F2). Safe, but the message is wrong; reserve rc 1 for the self case and map everything else to "authoriser check failed".
- R3-n5 (source-defect): GNU `date -d` and `readlink -f` are required; on a system without them the waiver is refused or the hook prints SKIP. Fail-safe, undocumented.
- R3-n6 (process-doc): `--waivers FILE` turns novelty off (documented); with base binding this nit disappears.
- Observation, not a finding: a python3 planted earlier in PATH that consumes stdin and exits 0 would pass the authoriser check (W-F3 was refused only because the fake did not read stdin, so `pipefail` saw SIGPIPE 141). The producer controls the environment and can skip hooks anyway; state the threat model (accident guard, not an adversary guard) in the header if it is not there.

## 3. Classification and verdict

| ID | Severity | finding_layer | Blocks |
|---|---|---|---|
| R3-I1 | important | source-defect | yes |
| R3-m1 | minor | source-defect | no (minor-class) |
| R3-m2 | minor | process-doc | no |
| R3-m3 | minor | test-instrumentation | no |
| R3-n1, n2, n4, n5 | nit | source-defect | no |
| R3-n3, n6 | nit | process-doc | no |

Verdict: **NO-GO**. R3-I1 is not minor-class (important, in the protected property, and it falsifies a header claim). Everything else could ride as follow-ups. Round 4 of 5 should be structural (11.4.276(E)): a fresh fixer, re-derive the waiver lifetime as one rule (one row = one transition, one commit, one parent), replace the novelty rule rather than add MERGE_HEAD/squash special cases, and enumerate the class members explicitly: linear snapshot, merge, conflicted merge, squash, `--no-commit` merge, cherry-pick, rebase/replay, amend, leftover worktree row. Add `GIT_GRAFT_FILE=/dev/null`, string comparison in awk, and the K1-K6 killers.

## 4. Full paired mutation suite (author's, unmodified, at 0b79d0c)

Run in a throwaway worktree of the bundle with `HOME=$(mktemp -d)`: 44 mutants killed, 0 survived, 0 `BAD` lines (the suite prints `BAD classification` when the gate vector differs from `want`, line 151, and none was printed), Part 3 hook end-to-end: plain downgrade rc 1, forward rc 0, real-submodule worktree forward rc 0 / downgrade rc 1, persist replay snapshot rc 1 pin B, layout SKIP rc 0; `exit=0`, elapsed 1618 s (the author reported 22 m 20 s; host load differs). Evidence `rv046r3_full_suite.out`. This matches the author's claim. The seven reviewer mutants in section 2 (R3-m3) are outside these 44 and survive them.

## 5. Evidence (all under the scratchpad directory)
- `rv046r3_p1.out`, `rv046r3_p1_red.out`: R2-I1 replay, head vs old gate.
- `rv046r3_p2.out`: waiver lifetime / identity probes W-A..W-F.
- `rv046r3_p3.out`, `rv046r3_p3b.out`, `rv046r3_p3c_graftfix.out`: wrong-read probes, grafts, grafts fix at gate level.
- `rv046r3_p4.out`: decision table T1-T9.
- `rv046r3_p5.out`, `rv046r3_killers.sh`: killers for RV1-RV6.
- `rv046r3_rv_mutants.out`: author harness with RV1-RV7.
- `rv046r3_p7.out`, `rv046r3_p7_merge.sh`, `rv046r3_p7_fixcheck.out`, `rv046r3_p7b_squash.out`: merge and squash reuse; MERGE_HEAD candidate.
- `rv046r3_p8.out`, `rv046r3_p8_natural.sh`: natural single-worktree squash and `--no-commit` reuse, original gate and MERGE_HEAD candidate.
- `rv046r3_p9_bind.sh`, `rv046r3_p9_bind_prototype.diff`, `rv046r3_p9_bind_prototype.out`: base-commit binding prototype.
- `rv046r3_full_suite.out`: the author's full mutation suite.
- `rv046r3_envledger_p6.out`: env-reads and ledger gates on main and head; hook env names for `commit` vs `commit --amend`.
