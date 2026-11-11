# Independent §11.4.142 / §11.4.209 review: fsfix6 bundle (round 6 of CON-146 / CON-147 / CON-158)

| Field | Value |
|---|---|
| Bundle | `fsfix6.bundle`, sha256 `b1d7279c99022ff839b18853f5b10514215763bafc99a6140139b69d63b9e347` (measured, matches) |
| Head | `e4fd10b0823ef0eb9a0e5d3a9d23248b47a03ab7`; prerequisite `2e8cfb90` fetched from the GitHub remote (the local checkout did not hold it). Round-6 delta over `a7d4369e`: merge `4003395b` plus 5 commits. |
| Reviewer | Claude Opus 5.5, dispatched as a subagent. I cannot set or read the reasoning effort from inside a subagent, so no `xhigh` claim is made (§11.4.231(F.2) gap). |
| Clone | fresh clone of the local repo plus the bundle, in my own scratchpad (`.../74ce2b36-.../scratchpad/rev6x/c`). Nothing was pushed or tagged. The real checkout was not touched. Each mutant ran in its own throwaway `git archive` copy, deleted afterwards. |
| Host | load 7 at the start, 17 to 21 later (other work on the host). One heavy suite ran at a time, except the deliberate load run below. |
| Evidence | `.../74ce2b36-.../scratchpad/rev6x/ev/` (meta regression runs) and `.../rev6x/mut/` (driver `run.sh`, mutant table `muts.tsv`, per-mutant outputs) |

## Verdict: GO-with-follow-ups. 0 critical, 0 important, 3 minor, 4 nit

Every round-5 finding that blocked (N1, N2, N3) is closed, and I measured each closure. M1, M2, n1 and n2 are closed too. All findings below are `test-instrumentation` or `process-doc` at severity `minor` or `nit`. None is a `source-defect`. Under §11.4.276(G.2) each minor finding becomes a tracked follow-up item. This is not a zero-finding GO.

## What I ran

| Check | Result |
|---|---|
| Merge `4003395b` | `git show --cc`: the only lines the merge itself adds are re-mint text edits and renamed `docs/qa` paths. No conflict markers anywhere in the tree (`git grep`). |
| Re-mint CON-116..128 -> CON-146..158 | DB: 156 items = 143 on main + 13. The rows CON-1..145 are byte-identical to main's DB (type, status, title, description, body, both states). Each of the 13 new rows equals its round-5 source row (type, status, title, both states, signature). Every new row carries the "Vehicle ids before re-mint" alias line with both earlier maps. No `CON-108..128` reference is left in the changed code. |
| `workable-items validate` (DB copy) | `OK — 156 items` (closure gate not armed, as before) |
| `diff --issues --fixed` | in sync, 156 vs 156 |
| `sync db-to-md` into scratch, then `cmp` | Issues.md and Fixed.md byte-identical |
| meta regression, 3 runs | run 1 rc 0 `pass=75 fail=0` (min run time 0.915 s); run 2 rc 0 75/0 (0.814 s); run 3 **under load** (12 busy-loop processes added on 16 CPUs) rc 0 75/0 (2.547 s). No BLIND note, no `NOT ok`. TMPDIR empty after each run. No process left over. |
| Reviewer mutants R1b (INT and HUP), R2, R3, R4, R5b, R7 | each caught in all three runs, on the axis it attacks: R1b `tmp=1 end=sig=2` / `sig=1`; R2 `rc=0`; R3, R4, R7 `rc=0 msg=0 stop=0`; R5b `end=exit=143` against the SINT pin `exit=130`. |
| `test_enumerate_decision_mutants.sh` | `pass=13 fail=0`; `--list` gives 115 mutants (meta 60, host_guard 46, host_report 9) |
| r22 (`bash`), via my driver's control leg | `pass=90 fail=0`; EP2V and EP2M present and green |
| host_guard_red (`sh`) | `SUMMARY pass=140 fail=0` |
| host_report r1 (`sh`) | `pass=45 fail=0` |

I did not run the full census (60 meta mutants at about 90 s each), and I did not run the full suite.

## The four round-6 fixes

- **N1 (determinism).** Signals now follow observed events: the sigwait gate's marker during the control run, and an `rm` shim's marker during cleanup. Run time is the minimum of three runs. A G-TERM or G-KILL sweep in which fewer than 7 of 14 stops landed is BLIND and is re-run once. The verdict no longer depends on timing. I confirmed this under a load that tripled the run time.
- **N2 (bounded waits).** Every meta-test run uses `timeout -k 5 120`. In `sigrun.py`, `p.wait(timeout=30)` is followed by `killpg(SIGKILL)`; leftover processes in the session are counted (`left=`) and killed; `nomark` and `timeout` are BLIND and repeated once. `wait_gone` is capped at 20 s. Only the sweep's `timeout -s TERM d` has no `-k`, and that is safe: the only window in which the meta-test ignores TERM is the bounded `rm`.
- **N3 (completeness).** Fixtures B12 to B16 were added, the signal pins are separate (143, 130, 129), and SCLEAN_INT and SCLEAN_HUP are new. The census found 15 more survivors (DP14 capture redirects, DP15 stop-on-failure), and the `diag=` and `stop=` fields now kill them. My own mutants of meta decision points the census does not generate were all killed (see below).
- **M1 (index-only stash).** `stash_index_unpatched` and the new refusal, which names the index content, are correct and fail closed: `None` is refused too. EP2V pins the message, and EP2M is the paired mutant. The restorability oracle still covers the non-empty-patch case independently (`custody_sweep.py` around line 1890).
- **M2 (four-word boundary).** The comments are now accurate, and `Max processes 5 6` -> `N=5` is pinned (H1 is killed per the evidence file).
- **n1, n2.** Each fixture gets its own `mktemp` directory. The `SCLEAN` label is fixed.

## The six equivalence claims, attacked

| Key | Claim | My check | Holds? |
|---|---|---|---|
| a9660ab8f6d8 | drop `[ -e "$s" ] \|\| continue` | The DP2 guard means the glob always matches. A dangling entry linked as a dangling link looks the same to the gate as an absent one: `run_verification.sh` only tests `[[ -d ]]` and `ls -la x/ && [ -f x/... ]`, and both fail for a dangling link. The gate has no `-L`, `-h` or directory listing. | yes |
| 847a5641fe46, cb285f234139, f879040bebc6 | `-lt 1` -> `-le 1` in the three floor lines | The values differ only at 1, where both leave 1. There is no `set -e` (checked). Each line is followed by an unconditional statement (`clamp`, `clamp`, then `printf`, `exit 0`), so its exit status is never read. | yes |
| 4eb93adc66ab | drop `[ -n "${W:-}" ]` in cleanup | `[ -d "" ]` is false. The EXIT trap is installed only after `W=$(mktemp -d ...)` succeeded, so `W` is never unset there. | yes |
| 7730ca956e9c | drop `[ -d "${W}" ]` in cleanup | `W` is a `mktemp -d` path. `rm -rf` of a missing path is a no-op, and bash keeps the exit status the script was leaving with when the EXIT trap returns normally. An empty `W` is still caught by the kept `-n`. | yes |

## Reviewer-authored mutants (§11.4.194(6)(d)): 13 run. 7 killed, 2 equivalent (Y3, Y7). 3 survive in code this round did not change (Y4 to Y6). 2 survive in the changed `stash_index_unpatched` (Y12, Y14): the verdict is unchanged, only the message differs.

| # | Target | Mutation | Census generates it? | Result |
|---|---|---|---|---|
| Y1 | host_guard | drop `[ -n "$psout" ] \|\| thr=""` (empty `ps` output counted as one thread) | no | KILLED (host_guard_red 139/1) |
| Y2 | host_guard awk | `print $3` -> `print $4` (hard limit instead of soft) | no (there is no awk field operator) | KILLED (135/5) |
| Y3 | host_guard | `[ -r "$_lim_file" ]` -> `[ -e ...]` | no | survived; **equivalent**: for an unreadable file, `awk ... 2>/dev/null` yields an empty value and the same `ulimit -u` fallback |
| Y4 | host_report `probe_thread_headroom` | `per_job = headroom + 1` -> `headroom` | no (outside the declared scope) | SURVIVED r1 (45/0) |
| Y5 | host_report `probe_thread_headroom` | `headroom = ulim - thr` -> `- 1` | no | SURVIVED r1 |
| Y6 | host_report `probe_thread_headroom` | `if ulim is None or thr is None` -> `if ulim is None` (TypeError when the thread count is unreadable) | no | SURVIVED r1 |
| Y7 | host_report `_read_ulimit_threads` | ignore the `ps` rc | no | survived; effectively equivalent (a failed `ps` gives empty output, then `int("")` raises ValueError, giving None) |
| Y8 | meta | control `if bash gate` -> `if ! bash gate` | no (`drop_bang` only removes a `!`) | KILLED (51/24) |
| Y9 | meta mutation 2 | `c.replace(old, "")` -> `c.replace(old, "", 0)` (weakening becomes a no-op) | no | KILLED (57/18) |
| Y10 | meta | `head -5` -> `head -0` (mutation-1 diagnostic hidden) | no | KILLED (71/4) |
| Y12 | custody `stash_index_unpatched` | `rc == 1: return True` -> `return None` (a determined fact reported as undeterminable) | no | **SURVIVED r22 (90/0)** |
| Y13 | custody `stash_index_unpatched` | compare `^1` with the stash tree instead of `^2` | no | KILLED (EP2V) |
| Y14 | custody `stash_index_unpatched` | final `return None` -> `return False` (a git failure reads as "no index content") | no | **SURVIVED r22 (90/0)**. No fixture makes `git diff ^1 ^2` fail. The verdict is still covered by the stale-backup refusal, so this survivor is about the message, not about safety. |

Y4 to Y6 are in `probe_thread_headroom`. This vehicle did not change that function (`git diff up fsfix6 -- host_report.py` has one hunk, in `_read_nproc_soft`), so these survivors are not regressions of this round. `test_host_limits_red.sh`, which asserts `returned_n` and the reason, SKIPs outside a consumer layout ("consumer-project files absent", `topology_unsupported`). Even there, Y4 and Y5 would give the same `N=1`, so it would not separate them.

## Findings

### m1: minor, process-doc (CON-158). "Every decision point" overstates the census's reach

The CON-158 body and commit `02e681a6` say the census "enumerates every decision point of meta_test_verification.sh" and "closes the class". The tool's own docstring is accurate: it uses a closed list of single-edit operators. What it actually covers is every decision point those operators match.

Y1, Y2, Y8, Y9 and Y10 are real decision-point mutants that the operators do not generate: negating a bare `if cmd; then`, changing an awk field, making a `str.replace` count zero, `head -N`, and dropping a `|| assignment`. All five happen to be killed by the existing tests, so nothing is unguarded today. But "survived=0" proves only "no operator-generated survivor", not completeness.

Fix: reword the tracker text and the commit-derived docs to "every decision point matched by the closed operator list". Optionally add operators for `if`-condition negation and awk `$N` shifts.

### m2: minor, test-instrumentation (CON-146). `stash_index_unpatched`'s True/None distinction is not pinned (Y12 survives)

EP2V checks that the refusal message contains "index (staged) content". A mutant that reports a determined index difference as `None` (undeterminable) still passes. The message then says `index_unpatched=None` for a fact git answered, and M1 was precisely about the refusal naming its real cause. The verdict is unchanged (REFUSED either way), so this is not a safety defect.

Fix: in EP2V, also assert `index_unpatched=True`. Optionally add a fixture where git cannot answer (for example a PATH shim for `git diff --quiet ... ^2` returning 128) and assert `=None`. Y14 is in the same spot and also survived. With it, a git failure reads as `False` ("no index content"). The stash is still refused through the stale-backup check, but the refusal no longer names the index. A git-failure fixture (a PATH shim that returns 128) would kill both Y12 and Y14.

### m3: minor, test-instrumentation (pre-existing, outside this round; CON-147 neighbourhood). `probe_thread_headroom`'s arithmetic and its `thr is None` guard have no canon-runnable test

Y4, Y5 and Y6 survive the only test that runs in a canon checkout. Y6 turns an unreadable thread count into an uncaught TypeError in `host_report.py limits`. The source is correct today. Register a follow-up: a canon fixture that pins `thread_headroom`, `threads_per_job_probed` and `reason=unmeasured` when `FC_GUARD_THREADS` is unset and `ps` fails. Optionally widen the census's host_report scope from `_read_nproc_soft` to the probe.

### n1: nit. The census can report KILLED on any non-zero exit, and its timeout kill misses `timeout`'s own process groups

`run_bounded` kills the session's process group on timeout. GNU `timeout`, which the meta regression uses, puts itself in a new process group, so after a KILLED-TIMEOUT its children can keep running for up to 125 s into the next mutant's run. Their stdout is redirected to files, so the census pipe does not hang. This affects host load and overlap only.

### n2: nit. The ledger can rot in one direction

A ledger entry is STALE only when its key is no longer generated. An entry whose mutant is later KILLED, so its equivalence proof is now false, is silently accepted. Flag "ledger key KILLED" as stale too.

### n3: nit. `stash_index_unpatched` uses porcelain `git diff --quiet`

It is subject to repository config such as `diff.ignoreSubmodules` and external diff drivers. Plumbing (`git diff-tree --quiet ^1 ^2`) would be config-independent. The restorability oracle still refuses the same stashes, so only the message precision is at stake.

### n4: nit, process-doc

The 13 vehicle items are `Queued` while fix rounds run on them. This is unchanged from round 5, so it is not a regression. Consider `In progress` for the three under active fix (CON-146, 147, 158).

## Not re-verified

- The author's full census run 2 (`killed=109 survived=0 equivalent=6`). I ran `--list` and the fast guard only.
- The author's RED runs (they are in the evidence file; I did not re-run the round-5 test with the R mutants).
- No full-suite run, and no run on a real tree with initialised submodules.
