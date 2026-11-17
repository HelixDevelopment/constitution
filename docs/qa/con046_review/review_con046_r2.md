# Independent re-review, round 2: vehicle/con046 (CM-SUBMODULE-PIN-NOT-DOWNGRADED)

| Field | Value |
|---|---|
| Reviewed | bundle con046_r2.bundle, head 2fbbf3d397b4f3da36c257fe3cbfe221e3644990, parent 8afca2f, base feacc507 |
| Files | scripts/gates/cm_submodule_pin_not_downgraded.sh, ..._mutation_test.sh, scripts/hooks/pre-commit-submodule-pin-not-downgraded |
| Round | 2 of at most 5 (11.4.276(G)); prior round NO-GO (review_con046.md) |
| Reviewer | independent subagent, Opus 5.5; reasoning effort not settable or readable on this dispatch path (11.4.231(F.2)), so no effort is claimed |
| Mode | read-only. Fresh throwaway clone of the live repo plus the bundle under the scratchpad (rv046r2.kApnyL); HOME from mktemp in every run; vehicle clone never opened; live repo still clean at ef18fea |
| Tooling | git 2.53.0, GNU bash 5.3.9, GNU date, shellcheck present |
| Verdict | **NO-GO** (1 important finding, R2-I1; everything else minor or nit) |

## Merge onto current main
main moved feacc50 -> ef18fea; that commit touches only `tests/gates/test_gate_env_overrides_guarded.sh`. `git merge-tree --write-tree main bundle/vehicle/con046` exits 0 (no conflict), and a throwaway merge commit was made. On the merged tree: `cm_gate_ledger_ratchet.sh` PASS `unimplemented=394 baseline=394`, the same as main. `cm_gate_env_reads_allowlisted.sh` FAILs on main AND on the merge with the same `uncovered=2` (cm_geo_substitute_anchor_wired.sh:320, cm_state_fields_anchor_wired.sh:405). That failure already exists on main and this change does not cause it: gates go 187 -> 188, reads stay 170, so the new gate adds no environment reads.

## Prior findings: re-verified with my own probes
| Prior | Status | Evidence (this session) |
|---|---|---|
| I-1 worktree false refusal | FIXED | N1, a linked worktree with a REAL submodule (`git submodule update --init` in the worktree, gitdir `.git/worktrees/wt/modules/sub`), through the real hook. New gate: forward `commit -a` rc=0, downgrade rc=1. OLD gate, same hook: forward refused BLIND rc=1 (RED). probe2 E7 now gives FAIL, not BLIND. Hook env captured: GIT_DIR + GIT_INDEX_FILE (N13), which matches the author's WT fixture. |
| I-2 ancestry rc / shallow fail-open | FIXED | P4 missing intermediate object: BLIND rc=2 (was PASS). P5 shallow beyond the boundary: BLIND rc=2 (was PASS). E6 incident replay with a shallow fetch: the pin bump is now refused (BLIND), so the later snapshot commit has nothing to downgrade. Residual in R2-m1. |
| I-3 expiry not validated | FIXED | Refused: never, 9999, 2999, N/A, permanent, x, 2026-12, 2026-11-9, ' 2999-01-01', 2026-13-45, 2026-2-1, 2027-02-29, 2100-02-29, 0000-00-00, 2026-11-31, yesterday. Accepted: 2028-02-29 and today (inclusive). Residual: no upper bound on the expiry date (R2-I1). |
| I-4 producer-controlled waiver | FIXED to the minimum asked | Untracked file ignored (P3). Authoriser equal to the committer is refused (name, email, ASCII case). Junk item refused. The header states what is not enforced. Residuals: R2-I1 (my round-1 "read it from the index" fix does not make a waiver single-commit) and R2-m3. |
| M-1 non-ASCII path | FIXED | P7 `sübmod` forward PASS; N7 `my sub dir` through the hook: downgrade rc=1, forward rc=0. |
| M-2 symlinked root | FIXED | P6 PASS rc=0. |
| M-3 consumer layout | FIXED | Consumer repo with `constitution/scripts/...` and the hook symlinked: doc commit PASS, consumer gitlink downgrade FAIL. |
| M-4 scope text | FIXED | The header lists --no-verify, plumbing, merge (auto and ff-only), cherry-pick, revert, rebase, split and moved downgrades. |
| M-5 reviewer mutants | FIXED | R1-R5 each have a fixture; author mutants killed. |
| M-6 11.4.287 hygiene | FIXED (one letter-level nit, R2-n9) | |
| M-7 BLIND message | FIXED (wording nit R2-n2) | Each BLIND names its cause and a fix. |
| M-9 diverged move | FIXED | DIVERGED=0/1 (a WARN line, exit 0). |
| Help range (N-4) | REGRESSED to a nit | R2-n1 |

Author's paired test re-run: the vector matches `want` exactly, 21/21 mutants killed, the real-hook line passes, rc=0, 2m13s (rv046r2_author_mutation.out).

## Findings

### R2-I1 important (source-defect): a waiver stays valid in HEAD and silently allows a later downgrade of the same kind as the incident; the header says it is single-commit
The header says the waiver file is "read from the git INDEX (so it must be STAGED in the same, reviewable commit)". It is not tied to one commit. The index contains HEAD, so a waiver row committed earlier counts for every later commit until its expiry, and expiry has no upper bound (`2999-01-01` is accepted and is also the author's own WAIVED fixture). Measured through the real hook:
1. A reviewed rollback B->A is committed together with a waiver `sub A ops 2999-01-01 CON-046`.
2. The pin is moved forward again to B.
3. The checkout is left at A (the checkout that made the rollback stays there, which is what happened in the incident), and a snapshot `git commit -a` is made that stages only `notes`.

Result: rc=0, the pin goes back to A, and the only output is `WAIVED sub 29ad6e6 -> b77a1bd (waiver from index ...)`. That is the same snapshot-over-stale-checkout downgrade this gate exists to stop. 11.4.271(A) allows a waiver for ONE candidate; here one reviewed rollback becomes a licence for that (path, sha) for centuries. This is the same class as round-1 I-3 and I-4 (a waiver that lasts longer than the event it was reviewed for), so the class is still not closed (11.4.276(C)). My round-1 suggestion caused part of this: reading the waiver from the index was necessary but not enough.

Fix, one rule, no stacked special cases:
- (a) Make the waiver single-use. A row counts only if it is absent from `HEAD:.submodule_pin_waivers`, or, for amend safety, absent from the version recorded when the old pin was committed. Alternatively, bind the row to the transition (path, old_sha, new_sha) AND cap the expiry window (consumer DATA, for example 30 days).
- (b) Either way, correct the header so it states the real lifetime.
- (c) Add a fixture: a waiver committed earlier must not cover a later commit.

### R2-m1 minor (source-defect): in a shallow submodule, a forward bump that can be proven is refused as BLIND
N2: depth-3 clone, pin c4 -> c5. `merge-base --is-ancestor c4 c5` = 0, so the bump is proven forward. The gate still tests only new->old first (rc 1), sees that the clone is shallow, and returns BLIND rc=2. Once old is proven to be an ancestor of new, new cannot be an ancestor of old, so this is a false refusal (11.4.201(1)). Fix by reordering the decision, with no added layer: forward proven -> ok; downgrade proven -> FAIL or waiver; not shallow -> WARN diverged; otherwise BLIND. No live submodule is shallow today (measured in round 1).

### R2-m2 minor (source-defect): two fail-open paths when the gate is run directly (the hook path is not affected)
- (a) The index cannot be read: with `GIT_INDEX_FILE=<garbage>`, git prints `fatal: ... index file smaller than expected` and the gate then prints `PASS (0 staged gitlink change(s) inspected)` rc=0. The exit status of the `git diff` in the process substitution is never checked. That is a §11.4.201(6) false null, and the header's "never a pass" covers only the BLIND cases it lists.
- (b) `--root <subdir>` together with `diff.relative=true`: the staged downgrade disappears from the output and the gate says PASS rc=0. Without `diff.relative` it says BLIND with the wrong cause ("checkout missing").

Fix: read the diff into a file, BLIND if git's exit status is not 0, normalise `--root` with `rev-parse --show-toplevel`, and add `--no-relative`. Matters for the owed `--range` / pre-push seam.

### R2-m3 minor (source-defect / claim): the authoriser-versus-committer check is weaker than stated
- "case-insensitive" does not hold in the C/POSIX locale for non-ASCII names. N6, with committer `Милош Васић` (the real committer name in this repo): under `LC_ALL=C` the authoriser `МИЛОШ ВАСИЋ` is WAIVED; under C.utf8 and en_GB.utf8 it is refused.
- No normalisation: ` prod` (leading space) and `<prod@x>` are WAIVED through the hook.
- The author identity is not compared: authoriser = author `prod` with committer `GIT_COMMITTER_NAME=bot` is WAIVED through the hook.

The header already says "a producer can still name a second identity", so this is a speed bump. But the explicit "case-insensitive" claim is false in one locale. Fix: fold case under a UTF-8 locale (or state the limit), trim whitespace and `<>`, and also compare `git var GIT_AUTHOR_IDENT`.

### R2-m4 minor (source-defect / claim): the waiver item key is fixed to `CON-NNN`, but the gate and hook are called universal and supported when vendored
The hook explicitly supports the consumer `constitution/` layout, and the gate says "Classification: universal". A consumer cannot cite its own item id: `CAT-046` is refused (N4). Per the §11.4.54 extension the key is consumer DATA. Fix: read the key from consumer config (`id_prefix`) or accept `^[A-Z]{2,}-[0-9]+$`, and document which.

### R2-m5 minor (test-instrumentation): five reviewer-written mutants survive the author's suite (11.4.194(6)(d))
Run in the author's own harness with only the mutant list replaced (rv046r2_reviewer_mutants.out). Killer fixtures are in rv046r2_killers.sh / .out:

| Mutant | What it changes | Killer fixture | real gate | mutant |
|---|---|---|---|---|
| RM1 | drop the "committer identity unresolvable" guard | `user.useConfigOnly` with no name | FAIL | WAIVED |
| RM2 | drop `--ignore-submodules=none` | `diff.ignoreSubmodules=all`, and `.gitmodules ignore=all` | FAIL | PASS (0 inspected) |
| RM3 | drop `--no-renames` | a file renamed to a 4-word name in the same commit as the downgrade (fewer words make it crash with `$2: unbound variable`, rc 1) | FAIL | PASS, misparse |
| RM4 | `NF==5` -> `NF>=5` | 6-field row | refused | WAIVED |
| RM5 | first invalid row aborts the waiver search | invalid row then valid row | WAIVED | FAIL (fail-safe direction) |

The real gate handles all five correctly; the suite just does not prove it. RM2 and RM3 guard fail-open paths, so their fixtures matter most.

### R2-m6 minor (process-doc / test-instrumentation): the hook-level RED was never shown; the worktree fixture is not a real submodule
`GATE_UNDER_TEST` does not reach Part 3, because the hook resolves the gate next to itself, so the "RED against the old gate" run (con046_r2_RED_oldgate.out) still shows the hook line passing. Part 3's worktree submodule is an embedded repository copied with `cp -a`. A real submodule in a worktree has its gitdir under `.git/worktrees/<wt>/modules`. N1 supplies the missing RED to GREEN on the real layout (old forward rc=1 BLIND, new rc=0). Add that layout to Part 3, and let Part 3 run against an older gate, for example by copying the hook next to the gate under test.

### Nits
- R2-n1: `-h` prints lines 2-40, but the header runs to line 51, so the help leaves out the NOT ENFORCED block, Usage and Exit.
- R2-n2: in the shallow case the BLIND message prints the internal sentinel `merge-base rc=99`, while git returned 1. For a non-shallow repo with a missing object it suggests `fetch --unshallow`, which git rejects on a complete repository.
- R2-n3: a CRLF waiver row is refused with `tracked item 'CON-046' does not match CON-NNN`. The `\r` is invisible in that message; either strip CR or name it.
- R2-n4: `sg()` strips a hand-written subset of git's local environment variables. The canonical list is `git rev-parse --local-env-vars`, keeping GIT_CONFIG_PARAMETERS/COUNT as git itself does for submodules. Missing from the subset: GIT_IMPLICIT_WORK_TREE, GIT_GRAFT_FILE, GIT_NO_REPLACE_OBJECTS, GIT_REPLACE_REF_BASE, GIT_SHALLOW_FILE, GIT_CONFIG. git did not export any of them in the cases measured (N13). Using the canonical list removes a hand-kept list.
- R2-n5: `awk -v p=` processes backslash escapes, so a path containing `\` can never match its waiver row (fail-safe), and a waiver for `sub` would also match a path `s\ub`. Use `ENVIRON`.
- R2-n6: `9999-12-31` is refused only because GNU date cannot parse it, so the refusal is accidental. `2999-01-01` is accepted (see R2-I1).
- R2-n7: shellcheck SC2010 in the test (`ls | grep` to find the symlink).
- R2-n8: when the gate is missing, the hook prints SKIP and exits 0. That is honest, but a symlink-installed hook whose gate later disappears becomes unguarded with only a stderr line. This is a design choice; noted only.
- R2-n9: the test runs `rm -f "$r/sub/.git/objects/${B:0:2}/${B:2}"` with bare `$r` and `$B`. The delete is not recursive, but 11.4.287(C)(1) asks for `${VAR:?}`.
- R2-n10: a partial commit (`git commit -- <paths>`) needs the waiver file in the pathspec. That fits the design but is not documented.
- R2-n11: in a partial-clone submodule, merge-base may lazily fetch from the network, which contradicts "no network". Setting `GIT_NO_LAZY_FETCH=1` in `sg` would prevent it.

## Heuristic-tower check (11.4.250)
No tower. The BLIND causes (no checkout, wrong toplevel, old or new object missing, merge-base rc not 0/1, rc 1 in a shallow clone) are one decision table on one question: can ancestry be decided? The `cat-file` checks only make the messages more specific; merge-base would return 128 anyway. `sg()` is a real fix for the actual cause (inherited GIT_DIR), not a workaround. Two places could be simpler: R2-m1 (put forward first, which also removes a false refusal) and R2-n4 (use git's own variable list). R2-I1 needs ONE rule, not more checks.

## Does the gate claim more than it enforces?
- Accurate: the CON-046 status (defensive hardening, stays open, the real tool UNREPRODUCED); the unguarded commit paths; the hook not installed; the waiver not conforming to 11.4.271; no roster; the tracked item not checked to exist.
- Over-claims:
  - "STAGED in the same, reviewable commit" (R2-I1).
  - "case-insensitive" (R2-m3, C locale).
  - "BLIND ... never a pass" when the index cannot be read (R2-m2, direct invocation only).
  - "universal" while `CON-NNN` is hard-coded (R2-m4).
  - The author report's "RED demonstrated against the OLD gate" covers Part 1 only (R2-m6).
- CON-046 must stay open. Nothing here reproduces the real Auto-commit tool (11.4.115(G), 11.4.292(D)).

## Evidence files (scratchpad)
- rv046r2_author_mutation.out
- rv046r2_probe.out (prior probe set 1, re-run)
- rv046r2_probe2.out (prior hook end-to-end, re-run)
- rv046r2_probe3.sh / rv046r2_probe3.out (N1-N13)
- rv046r2_reviewer_mutants.out
- rv046r2_killers.sh / rv046r2_killers.out
- rv046r2_waiver_persist.out (R2-I1 replay, re-captured against gate head 2fbbf3d: `waiver changed vs HEAD: no`, then `WAIVED ...`, rc=0, pin back to A; the SHAs differ from the p5 run quoted above because the fixture was rebuilt)
- throwaway trees under rv046r2.kApnyL/, including p5 and p7 (the R2-I1 replays) and p6 (the consumer layout)
