# Independent re-review, CON-046 round 4 (structural), vehicle/con046

| Field | Value |
|---|---|
| Reviewed head | 93de0fef4f0563402dd12b00a156e85cbdbcaf44 (parent 0b79d0c); file sha256 equal to the author's `final_sha256.txt` (gate 2e4239a1…, test a619655a…, hook ff0433bf…) |
| Bundle | con046_r4.bundle (origin/main..vehicle/con046) |
| Current main | origin/main = 7f72395 (fetched 2026-11-05); `git merge vehicle/con046` onto it in a throwaway clone is clean, and the diff against main is the same 3 files (+645 lines) |
| Reviewer | independent subagent, Opus 5.5. Effort cannot be set or read on this dispatch path (11.4.231(F.2)), so no effort level is claimed |
| Round | 4 of 5, structural (11.4.276(E)) |
| Method | Read-only. Every probe ran in a throwaway clone under `R = scratchpad/rv046r4.CjTUj5/` with a fresh `HOME`, `${VAR:?}` guards and `mktemp -d` fixtures. No real repository was modified; the one `git fetch origin` in the real checkout updated remote-tracking refs only. No secret-named variable was printed |
| Verdict | **NO-GO** (one blocking finding, M-4; everything else is minor-class). The round-5 work is mechanical, see section 5 |
| CON-046 | Stays open as defensive hardening (11.4.115(G)); the report, the commit message and the header agree on this |

## 1. The new rule, checked independently

The structural change replaces the novelty rule with one rule. A 7-field row `(path, old, new, authoriser, expiry, item, base)` waives the transition only when all of these hold:
- the commit is made on top of `base` (full SHA, compared as a string);
- no MERGE_HEAD is present;
- no other ref-reachable commit (other than HEAD) has `base` as a parent and carries the same `(path, old, new, base)` row.

What this buys, and why the R3-I1 class is closed in its harmful form: in hook mode the base is HEAD, which is the parent of the commit being created (except with `--amend`, see N-3). So every commit the hook WAIVES lands exactly the reviewed `(path, old -> new)` on exactly the reviewed parent. A row can no longer authorise a downgrade on a parent it was not reviewed for. That was the R3-I1 shape (merge or squash onto a MOVED main) and the R2-I1 shape (snapshot on a later commit).

Every leak I could still produce (M-1 to M-3) re-lands the reviewed transition on the reviewed parent a second time, when the first commit is not visible in local refs. That harm is much narrower than R3-I1: the final pin is one the authoriser approved for that parent, and the gate prints a WAIVED line.

### Class members: my own fixtures through `git commit`, with the real hook and a real submodule (`R/probes/p9.out`, `p1.out`, `p4.out`, `p5.out`, `p6.out`)
| Member | Result at head |
|---|---|
| Legitimate reviewed rollback | WAIVED, pin A |
| R2-I1 snapshot after a rollback and an index-only forward | refused, pin B |
| Conflicted merge, main moved | refused, pin B |
| Squash, main moved / main unmoved | refused / refused (spent) |
| `--no-commit --no-ff` merge, vehicle branch deleted while the merge is open | refused (MERGE_HEAD) |
| 6-field and 8-field rows | refused |
| Leftover row bound to an older HEAD / to the current HEAD | refused / WAIVED (documented residual) |
| Base field abbreviated, `HEAD`, upper-case, or with a trailing space | refused |
| Spender on a lightweight tag, or on an annotated tag (branch deleted) | refused (tags are in `--all`) |
| Spender is the detached HEAD of another worktree | refused |
| MERGE_HEAD in ANOTHER worktree, legitimate rollback here | WAIVED (MERGE_HEAD is per worktree, correct) |
| Refs that point to a tree and to a blob (as git.git's `v2.6.11-tree` does) | `rev-list --all` rc 0, legitimate rollback WAIVED (no false BADREF) |
| python3 exit-code table (a fake python3 that reads stdin and exits N) | 0 → waived; 10 → "self-waive"; 3 → "empty/whitespace/<>/control"; 1, 2, 4, 127 → "authoriser check failed (python3 rc N)". Real python3 with an invalid UTF-8 authoriser → rc 4 (the exception path), "check failed" |
| `cherry-pick --continue` after a conflict | runs the hook (1 hook line) |
| `GIT_GRAFT_FILE=/dev/null`, string-compare awk (`$i""==b""`) | present on every object-reading call (`sg`, `pg`); the awk compares as strings, so a numeric-looking SHA cannot match by numeric equality |

These results agree with the author's inventory. The RED claim also reproduces: the new suite run against the r3 gate (`GATE_UNDER_TEST`) exits 1 with a different vector, "BAD classification" and "BAD hook end-to-end" (`R/red_vs_r3.out`, 130 s).

## 2. Findings

### M-4 IMPORTANT (source-defect, proof of this batch): 6 of 7 reviewer mutants of the new history search survive the author's suite
I wrote seven mutants of the code this round added (RM8 to RM14). I ran them as Part 2 of the author's own test, with Part 1 and Part 3 unchanged (`R/mutsuite/scripts/gates/rv_mutants_test.sh`, output `R/rv_mutants.out`, 394 s). Part 1's vector matched `want` and Part 3 passed. Six of the seven mutants **SURVIVED**:

| Mutant | Change | Author's suite | My killer fixture (real gate → mutant) |
|---|---|---|---|
| RM8 | `rev-list --branches` instead of `--all` | **SURVIVED** | spender only on a tag: 1/B → 0/A; spender on a detached worktree HEAD: 1/B → 0/A |
| RM9 | superproject replace refs honoured (`pg()` without `GIT_NO_REPLACE_OBJECTS`) | **SURVIVED** | `git replace --graft R` (R made parentless): 1/B → 0/A |
| RM10 | superproject lazy fetch on (`pg()` without `GIT_NO_LAZY_FETCH`) | **SURVIVED** | blob:none partial superproject: real = refused "unreadable", blob still absent; mutant = blob fetched, refused for "spent" instead |
| RM11 | spent check ignores the path | **SURVIVED** | sibling on P carrying a row for `sub2` with the same SHAs: 0/A (waived) → 1/B (false refusal) |
| RM12 | spent check ignores the old SHA | **SURVIVED** | sibling on P carrying a row with another old SHA: 0/A → 1/B (false refusal) |
| RM13 | a spent check that "cannot tell" is treated as unspent | killed | sibling whose waiver path is a tree: 1/B → 0/A |
| RM14 | `--single-worktree --all` | **SURVIVED** | spender is the detached HEAD of another worktree: 1/B → 0/A |

The gate itself is correct on all seven properties. Against the real gate my seven killers give the expected vector (`R/probes/p7_killers.sh`, `p7_killers.out`), and three runs produced identical vectors (`R/probes/p7_killers_determinism.out`, compared byte for byte). But the batch's proving suite does not establish these properties. Why that blocks:
- The header's rule claims "a commit reachable from a ref (`git rev-list --all`, all worktrees)". RM8 and RM14 show the suite never exercises a non-branch ref or another worktree's HEAD.
- RM11 and RM12 show it never checks that the spent predicate is narrow enough. That is the 11.4.201(1) false-refusal side of the very rule this round introduced.
- 11.4.235(D) puts this in the source-defect layer explicitly: "a proving guard … whose reviewer-authored mutation survives per §11.4.194(6)(d) means the source is NOT proven-correct". 11.4.276(D) requires every reviewer-surviving mutation to be adopted verbatim and to fail the suite before the next review.
- This is a proof-of-batch surface, so 11.4.276(G.2) does not let it ride as a minor-class follow-up.

Severity is important, not critical: the runtime behaviour is right, and the fix is to adopt fixtures that already exist.

If the operator reads M-4 as test-instrumentation, the verdict becomes GO-with-follow-ups. That reading would treat the behaviour as already proven by the reviewer's own captured killers. I do not take it, because 11.4.235(D) names exactly this case.

### M-1 minor (source-defect): the spent search fails OPEN when the spender's tree is unreadable, and on a shallow superproject
`blob()` returns 1 ("absent") whenever `rev-parse <commit>:.submodule_pin_waivers` fails. That also happens when the commit's TREE object is missing. The author closed the blob case (CHILDTREE, rc 2 "unreadable") but not the tree case.

Measured (`R/probes/p3.out`):

| Spender R | Result |
|---|---|
| present | refused |
| tree object removed | **WAIVED, pin A** |
| waiver blob removed | refused, "unreadable" |

The same shape appears on a shallow superproject where R is a shallow boundary. R's parent is hidden, so R is not seen as a child of P: **WAIVED**, where the full clone refuses (`R/probes/p2.out`, SHALLOW-SUPER vs FULL-SUPER).

Both cases read "cannot tell" as "not spent". That goes against 11.4.201(4), and against the gate's own BLIND-on-shallow rule for submodules.

Fix (small, class level):
- Treat a missing tree as rc 2: check `pg cat-file -e "$k^{tree}"` before the path lookup.
- Refuse waivers when `pg rev-parse --is-shallow-repository` is true.

The harm is bounded as in section 1 (same transition, same parent). I recommend fixing it in round 5 rather than as a follow-up, because the gate is a fail-closed guard.

### M-2 minor (source-defect, false refusal, 11.4.201(1)): a stash of a staged rollback "spends" its own row
`refs/stash` is in `rev-list --all`. Both the stash commit and its index commit have HEAD as a parent and carry the staged row.

| Sequence | Result |
|---|---|
| staged rollback, `git stash push`, `git stash apply --index`, `commit -a` | **refused**, "waiver row already spent by commit eaccc692b7cc on the same parent" (that SHA is the stash) |
| the same with `stash pop` (refs/stash dropped) | WAIVED |

Evidence: `R/probes/p1.out`. This is new in round 4, because the r3 gate had no history search. The message does not name the way out (`git stash drop`).

Fix: `pg rev-list --exclude=refs/stash --all --parents` (`--exclude` must come before `--all`). A stash commit is never a commit on a line of work. Alternatively, name the stash in the message.

### M-3 minor (process-doc): the residual list is narrower than the measured residual set, and its most natural member is not named
Header lines 57-60 name "reachable only from a reflog (after `reset`, or a deleted branch)". The measured residual is wider. In each case below the first commit is invisible to local refs, so the row waives the same transition on the same parent again; each case is WAIVED and the pin lands at A:
- **`git reset --soft HEAD~2 && git commit -a`** over [reviewed rollback, index-only forward], with the checkout still stale. This is the common local-squash idiom: the forward is dropped and A lands (`R/probes/p8.out`). With plain `git commit` instead of `-a`, the result is pin B, which is correct. This is the incident shape (a stale checkout picked up by `commit -a`), and it is reported as WAIVED, not FAIL.
- A squash from `FETCH_HEAD` only (vehicle in another clone, never a local ref), main unmoved (`p2.out`). With `origin/X` kept as a remote-tracking ref it is refused.
- A removed worktree whose HEAD was the spender; a spender reachable only from a note (`p1.out`).
- `git merge --no-commit --no-ff X`, then `git merge --quit` (MERGE_HEAD gone, single-parent commit), with the vehicle deleted (`p1.out` MERGEQUIT-del). With the vehicle kept, the spent check refuses it. So a documented git command bypasses the MERGE_HEAD clause, and the only protection left there is the spent check.

State these in the header and in the hook comment, in particular the `reset --soft HEAD~N && commit -a` idiom and its mitigation (commit without `-a`, or run `git submodule update` first). No code change is needed.

### Nits
- **N-1 (process-doc)**: "spent by the FIRST such commit" is not what the code does. Any other ref-reachable child of the base that carries the row counts, including merge commits that have the base as second parent and stash commits. After a later copy S exists, re-judging the first commit R with `--base HEAD^` refuses R too (`p4.out` P4d). This is conservative; the header should say "any other commit".
- **N-2 (process-doc)**: the not-guarded list says a CLEAN rebase runs no hook. A conflicted `rebase --continue` does not run pre-commit either (measured: 0 hook lines, `p4.out`), while `cherry-pick --continue` does. The header and the hook comment should say "rebase (clean or after a conflict)".
- **N-3 (process-doc)**: with `--amend`, the row must be bound to the commit being amended (HEAD), while the waived commit's parent is HEAD^, not the row's base. The WAIVED line then says "bound to parent X" where X is not the parent, and a later `--base HEAD^` re-check of that commit refuses it (`p6.out`). The general `--amend` limitation covers this, but the rule sentence "that parent is base_sha" is false for amend; add one line.
- **N-4 (source-defect)**: HEAD is excluded from spenders on the assumption that the judged index is HEAD's tree. In `--base` mode, on an index that is not HEAD's tree, the original commit escapes as "HEAD". Same index: WAIVED with HEAD = R, FAIL with HEAD = main (`p10.out`). This needs a deliberately built index. Exclude HEAD only when `write-tree` equals `HEAD^{tree}`, or state the assumption.
- **N-5 (process-doc)**: header line 82 says "every git call runs with GIT_NO_LAZY_FETCH=1 …". Two calls do not: `rev-parse --show-toplevel` and `rev-parse --local-env-vars`. This is harmless (neither reads objects); say "every object read".
- **N-6 (perf, no defect)**: the spent search captures `rev-list --all --parents` into a bash variable and then pipes it to awk. Measured:

  | Repository | Measurement |
  |---|---|
  | this repository's clone, 27 top-level submodules initialised, 1176 commits | gate 0.13-0.35 s with no gitlink change; 0.24-0.27 s for an unwaived downgrade; 0.27-0.50 s for a waived one (`R/perf/`) |
  | a 73 082-commit history | the search alone takes 2.24 s (rev-list 0.83 s, max RSS 75 MB) |

  A kernel-size history would take tens of seconds, but only on a commit that carries a valid row. Piping rev-list straight into awk would remove the copy; optional.

### Classification
| ID | Severity | finding_layer | Blocks GO |
|---|---|---|---|
| M-4 | important | source-defect (proof-of-batch, 11.4.235(D)) | yes |
| M-1 | minor | source-defect | no (fix recommended in round 5) |
| M-2 | minor | source-defect | no |
| M-3 | minor | process-doc | no |
| N-1, N-2, N-3, N-5 | nit | process-doc | no |
| N-4 | nit | source-defect | no |
| N-6 | nit | process-doc (perf note) | no |

## 3. Environment, ledger, hygiene
- `cm_gate_env_reads_allowlisted.sh`:

  | Revision | gates | reads | uncovered |
  |---|---|---|---|
  | head | 188 | 170 | 2 |
  | main 7f72395 | 187 | 170 | 2 |

  The 2 uncovered reads are the same pre-existing `eval` reads on both (`cm_geo_substitute_anchor_wired.sh:320`, `cm_state_fields_anchor_wired.sh:405`). The gate's VERDICT line is FAIL on main and head alike because of those 2; this change did not introduce them.
- `cm_gate_ledger_ratchet.sh`: unimplemented 394 = baseline 394, PASS on head and on main.
- `bash -n` is clean on all three files, and shellcheck `-S warning` reports nothing. The trailers `Roadmap-Item: CON-046` and `Co-Authored-By: Claude Opus 5.5` are present.
- Evidence: `R/envledger.out`.

## 4. The author's suite, run by me
- `cm_submodule_pin_not_downgraded_mutation_test.sh` at head, `MUT_JOBS=4`, fresh HOME (`R/full_suite.out`):
  - **61 of 61 mutants killed**, no BAD line;
  - the gate vector equals `want`;
  - hook end-to-end line: plain downgrade rc 1, forward rc 0, downgrade-after rc 1; real-submodule worktree forward rc 0, downgrade rc 1; persist rollback rc 0, forward rc 0, snapshot rc 1 with pin B; layout-skip rc 0 with an honest SKIP;
  - **exit 0, 1882 s** (host load average about 33).
- RED reproduction against the r3 gate: exit 1 (`R/red_vs_r3.out`).
- My reviewer mutants inside the author's harness: 1 of 7 killed, 6 SURVIVED (`R/rv_mutants.out`, see M-4).

## 5. What round 5 needs (all small)
1. **M-4 (blocking):**
   - Add the seven killer fixtures from `R/probes/p7_killers.sh` (K8TAG, K14WT, K9REPL, K10LAZY, K11PATH, K12OLD, K13TELL) to the suite's fixture vector.
   - Add RM8 to RM14 verbatim to Part 2. The sed expressions are in `R/mutsuite/scripts/gates/rv_mutants_test.sh`. RM14 must place `--single-worktree` before `--all`, otherwise it is an equivalent mutant.
   - Show each mutant killed, and record the adoption (11.4.276(D)).
2. **M-1:**
   - Make a missing tree read as "unreadable" (rc 2), and refuse waivers in a shallow superproject.
   - Add p3 treemissing and p2 SHALLOW-SUPER as fixtures, each with a mutant that removes the new check.
3. **M-2:** add `--exclude=refs/stash` before `--all`, with fixture P1a (stash apply --index must be WAIVED) and a mutant that drops the exclusion.
4. **Documentation:** M-3, N-1, N-2, N-3, N-5. N-4 and N-6 are optional.

## 6. Does the class still recur? (for the operator's 11.4.276(E)(3) view)
The harmful R3-I1 form does not recur: a row waives only on the parent it names. What remains is a property of any LOCAL pre-commit check, not a rule defect. The hook cannot see commits outside local refs (reflog-only commits, FETCH_HEAD, other clones, removed worktrees). So the same reviewed transition can be re-landed on the same parent, as in M-3.

The structural alternative that closes this is a landing-seam range check: `--range A..B` run by the ff-only landing script or a pre-receive or pre-push seam on `main`'s first-parent history. It would judge each landed commit against its first parent and refuse a waived commit whose (row, parent) already occurs on `main`. It depends only on `main`'s history, not on local ref visibility.

The header already lists `--range` as a follow-up that is not built. I recommend keeping it as a tracked follow-up item rather than spending round 5 on it, because the residual harm is bounded (an authoriser-approved pin on the approved parent, with a visible WAIVED line).

## 7. Evidence (all under R = /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv046r4.CjTUj5)
| Path | Contents |
|---|---|
| `full_suite.out` | the author's suite, my run (61/61, exit 0, 1882 s) |
| `rv_mutants.out`, `mutsuite/` | RM8 to RM14 in the author's harness (6 survived) |
| `probes/p7_killers.sh`, `p7_killers.out`, `p7_killers_determinism.out` | killers on the real gate and on each mutant; determinism re-runs |
| `probes/p1.out` to `p10.out`, with scripts `p1.sh` to `p10.sh` and the shared `lib.sh` | the class and attack probes through the real hook with a real submodule |
| `red_vs_r3.out` | the new suite against the r3 gate (RED) |
| `envledger.out` | env-read allowlist and ledger ratchet, head and main |
| `perf/` | timing on this repository's clone and on a 73k-commit history |
| `lay/`, `lay3/`, `mutlay/` | head, r3 and mutant layouts |
