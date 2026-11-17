# Independent review: vehicle/con046 (CM-SUBMODULE-PIN-NOT-DOWNGRADED)

| Field | Value |
|---|---|
| Reviewed | bundle con046.bundle, head 8afca2f070cf1e83f4dfd8639d245bf881c21ffd, base feacc507 |
| Files | scripts/gates/cm_submodule_pin_not_downgraded.sh, ..._mutation_test.sh, scripts/hooks/pre-commit-submodule-pin-not-downgraded |
| Reviewer | independent subagent, Opus 5.5; reasoning effort not settable or readable on this dispatch path (11.4.231(F.2)), so no effort is claimed |
| Mode | read-only; vehicle clone untouched (cmp: bundle files identical to vehicle clone); all runs in a throwaway clone under the scratchpad (rv046.gUoARj), HOME from mktemp per run |
| Tooling | git 2.53.0, GNU bash 5.3.9, GNU Awk 5.3.2 |
| Verdict | **NO-GO** (4 important findings; 11.4.276(G.2): important is never minor-class) |

## What holds (captured this session)

- Author's paired mutation test re-run: real gate vector `DOWN=1 NOCHANGE=0 DIVERGED=0 FORWARD=0 WAIVED=0 EXPIRED=1 NOTRACK=1 BLIND=2 UNRELATED=0 WRONGSHA=1`, 7/7 mutants killed, rc=0 (`rv046_author_mutation.out`).
- Incident replay end to end with the hook really installed (real `git submodule add`, symlink per the hook's own instructions, pin B, checkout moved to ancestor A): `git commit -a` refused (rc=1, pin stays B); `git add -A && git commit` refused; legitimate forward bump allowed; `--no-verify` bypasses as documented (`rv046_probe2.out` E1-E4).
- BLIND is never read as a pass by the hook: `exec bash gate` returns 2, git refuses the commit (E7). Exit precedence FAIL over BLIND.
- Robust to user config: `color.ui=always`, `color.diff=always`, `diff.relative=true`, `core.quotePath=false`, `diff.ignoreSubmodules=all`, `submodule.recurse=true`, `.gitmodules ignore=all` all still FAIL a staged downgrade (rc=1).
- Unborn HEAD with a new gitlink: PASS. Two downgrades with a waiver for one: FAIL. Deleted gitlink, gitlink-to-file typechange, new gitlink: PASS (documented).
- Ledger: `cm_gate_ledger_ratchet.sh` PASS `unimplemented=394 baseline=394` at both head and base feacc50. The name has 0 hits in Constitution.md / AGENTS.md (positive needle `CM-GATE-LEDGER-RATCHET` = 1 hit), so the ledger is unaffected, as the author said.
- Live repo (read-only): `core.hooksPath` unset, no pre-commit hook installed, all 27 submodules checked out at their pins, none shallow, no non-ASCII paths, `git worktree` in use (a vehicle worktree exists).

## Findings

### I-1 important (source-defect): every gitlink change is refused (BLIND) when committing from a linked worktree
Git exports `GIT_DIR` and `GIT_INDEX_FILE` to the pre-commit hook in a linked worktree (captured: `GIT_DIR=.../super/.git/worktrees/wt`). The gate's `git -C "$sub" ...` calls inherit `GIT_DIR`, so the submodule's commits are looked up in the superproject worktree's object store and the gate reports BLIND. Measured: in a worktree, a legitimate FORWARD bump (`9b1d6cc -> 98bbdd8`, `merge-base --is-ancestor old new` = yes) PASSes when the gate is run directly (rc=0) and is refused through the hook (BLIND, commit rc=1). This is an 11.4.201(1) false refusal on exactly the 11.4.288(D) parent-pointer bump, in the vehicle form (worktree) 11.4.288(B) uses, and the only way out is `--no-verify`, which 11.4.234(B) forbids as routine.
Fix: run every submodule call with the hook environment removed (`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX -u GIT_COMMON_DIR git -C "$sub" ...`), keep it for the root `diff --cached` (needed for `commit -a`'s temporary index). Add an end-to-end hook fixture in a linked worktree (forward passes, downgrade fails); the suite currently never runs the hook at all.

### I-2 important (source-defect): ancestry the gate cannot see is reported as "not a downgrade" (fail-open)
`merge-base --is-ancestor` returns 0 / 1 / 128; the gate treats every non-zero as "ok (not a downgrade)".
- Missing intermediate commit object: merge-base rc=128 ("could not parse commit"), gate prints `ok ... (not a downgrade)`, PASS rc=0 (P4).
- Shallow submodule, ancestor beyond the shallow boundary: gate PASS (P5).
- Incident shape with a shallow pin fetch (E6, hook installed): checkout at A, upstream advances, `git fetch --depth 1` then the pin is bumped to B without moving the checkout, then a snapshot `git commit -a`: the hook prints `ok sub 98bbdd8 -> 9b1d6cc (not a downgrade)` and the downgrade to A lands (commit rc=0).
The header and the commit message say BLIND is "never a pass" when the gate cannot judge; these paths contradict that. Fix: capture the rc; 0 = ancestor, 1 = not ancestor only when `rev-parse --is-shallow-repository` is false, anything else BLIND. Add the missing-object and shallow fixtures. (No live submodule is shallow today and no constitution script uses shallow submodule fetches; measured, needle-checked.)

### I-3 important (source-defect): expiry is not validated; elapsed or garbage expiries are accepted
The awk test `$4>=t` is a plain string comparison with no format check. Measured accepted (gate rc=0, WAIVED) on 2026-11-05: `never`, `9999`, `2999`, `N/A`, `permanent`, `x`, `2026-13-45`, and elapsed but unpadded dates `2026-2-1` and `2026-11-1`. Only values sorting below "2" or with a leading space were refused. A waiver with a non-date expiry is valid forever, which 11.4.271(C) rules out. Fix: require `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` and a `date -d` round trip equal to the input, else refuse; add the fixtures above.

### I-4 important (source-defect): the waiver is a producer-controlled bypass (authoriser only non-empty, untracked file honoured)
Answer to the brief's question: the authoriser is checked ONLY for non-empty. Measured: authoriser equal to the committer (`prod`) is accepted; free-text `looks fine` with tracked item `x` is accepted; an UNTRACKED `.submodule_pin_waivers` in the worktree root is honoured (WAIVED, `ls-files` says not tracked). Combined with I-3, any producer (an agent, or the unidentified auto-commit tool) can silently and permanently neutralise the gate with no review trail. The header cites 11.4.271 and calls the waiver "11.4.271-style", but 11.4.271(B) requires a rostered authoriser that is never the producer and (D) a real tracked item. No roster exists in this repo (searched), so full (B) is not available; minimum fix: read waivers from the index (`git show :.submodule_pin_waivers`) so a waiver must be staged in the same, reviewed commit; refuse an authoriser equal to the committer identity; require the tracked item to match the item-id pattern; state in the header what of 11.4.271 is NOT enforced and link `CM-WAIVER-ROSTERED-EXPIRY-TRACKED` (owed).

### M-1 minor: non-ASCII submodule path is refused (BLIND) on a forward bump
`--raw` output C-quotes the path (`"s\303\274bmod"`), so `$root/$path` does not exist. Fix: parse `git diff --cached --raw -z`. No such path in this repo today.

### M-2 minor: symlinked `--root` refuses a forward bump (BLIND)
`cd "$2" && pwd` keeps the logical path, `rev-parse --show-toplevel` returns the physical one. The hook passes a physical path, so only direct invocations are hit. Fix: compare against `pwd -P`.

### M-3 minor: the hook is constitution-layout only; installed in a consumer it blocks every commit
The hook runs `$root/scripts/gates/...` of the repository being committed. In a consumer layout (`constitution/scripts/...`) a plain doc commit with no gitlinks was refused (`No such file or directory`, 0 commits). The gate header says "universal". Fix: resolve the gate relative to the hook's own real path.

### M-4 minor (process-doc): scope text omits the unguarded commit paths
Measured with a marker hook (plain commit = 1 run, positive control): `git merge` auto-commit, `cherry-pick`, `revert` and `rebase` do NOT run pre-commit; a downgrade made on a vehicle branch landed on main through both `merge --ff-only` and a true merge (E5). Under 11.4.288(B)(3) vehicles land by ff-only merge from scratch clones that have no hook, so the main landing path is unguarded. Per-commit index diffs also miss a downgrade split across commits or combined with a path move (delete + add are both skipped by the mode check, measured separately). The header names only `--no-verify` and plumbing. Fix: list these paths in the header and the fix report; register a follow-up for a `--range A..B` mode for a pre-push / landing seam.

### M-5 minor (test-instrumentation): reviewer mutants survive the suite
Run against the author's own harness (`rv046_reviewer_mutants.out`), all six survived:
- R1 drop the two `cat-file -e` presence checks: SURVIVED. Killer fixture written: new pin object absent; real gate BLIND rc=2, R1 mutant PASS rc=0.
- R2 waiver ignores authoriser (`$3!=""` removed): SURVIVED (no empty-authoriser fixture).
- R3 waiver ignores path (`$1==p` removed): SURVIVED (single submodule in every fixture).
- R4 expiry-day boundary (`>=` to `>`): SURVIVED (no fixture on today's date).
- R5 BLIND outranks FAIL: SURVIVED (no mixed fixture).
- R6 drop the toplevel check: SURVIVED, but near-equivalent (cat-file then fails in the superproject's store).
Add fixtures for R1-R5 and hook-level fixtures (I-1, E1).

### M-6 minor (test-instrumentation): 11.4.287(C) hygiene in the mutation test
`tmp="$(mktemp -d)"` is not checked non-empty before `export HOME="$tmp/home"` ((C)(2)); `rm -rf "$r/sub/.git"` expands a bare variable ((C)(1) requires `${r:?}`). No harm path was found (the trap uses `${tmp:?}`), but the rule is explicit.

### M-7 minor: BLIND message gives neither cause nor remedy; BLIND has no waiver path
The message merges four causes (no checkout, wrong toplevel, old object missing, new object missing) and says only "cannot judge". 11.4.201(5) asks for the resolved evidence and 11.4.234(D) for a remediation path (for example `git submodule update --init <path>` or a fetch). With no waiver for BLIND, `--no-verify` is the only way past.

### M-8 minor (process-doc): test-first order not followed
Disclosed by the author (gate written before the test, 11.4.224(A)); RED evidence is post hoc. Recorded, not fixable retroactively.

### M-9 minor (follow-up): sideways (diverged) moves pass silently
A diverged move can drop the old pin's commits as surely as an ancestor move. Suggest a WARN line; reachability from upstream main stays the owed `CM-SUBMODULE-POINTER-ON-MAIN` (OWED-GATE-151).

### Nits
- N-1 exit 2 means both BLIND and usage error.
- N-2 `seq=0` unused in the mutation test; `$1!~/^#/` is redundant.
- N-3 fix report's "Still pending: M submodules/containers" is stale: measured now, containers checkout = pin 5ea870a, status clean.
- N-4 `-h` prints internal lines 29-30.
- N-5 expiry semantics (valid through the expiry day) undocumented.
- N-6 the gate is not referenced from canon or any guide; consider citing it from the 11.4.288(D) area when the text is next edited.

## Honesty of scope claims
- Accurate: the tool that made the "Auto-commit" commits is unidentified, the gate is not proven to catch it, the hook is not installed, `--no-verify` bypasses, the ledger is unaffected.
- Inaccurate: "BLIND ... never a pass" (I-2); "11.4.271-style" waiver (I-4, I-3); "universal" for the hook (M-3); scope omits merge/cherry-pick/revert/rebase/ff-landing (M-4).
- CON-046 status: this is defensive hardening for a mechanism reproduced as a host fixture (E1), not a fix of the unidentified tool; per 11.4.115(G) / 11.4.292(D) the item stays open (UNREPRODUCED for the real tool) and must not be closed on this change.

## Evidence files (scratchpad)
rv046_author_mutation.out, rv046_probe.sh / rv046_probe.out, rv046_probe2.sh / rv046_probe2.out, rv046_reviewer_mutants.out; throwaway trees under rv046.gUoARj/.
