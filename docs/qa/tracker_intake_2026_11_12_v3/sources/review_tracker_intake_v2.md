# Independent review, round 2: tracker-intake vehicle (head 63f80e52 on 1a307322, base 02c10935)

Reviewer: a fresh independent subagent, Opus 5.5. Effort cannot be set or read on this dispatch path (§11.4.231(F.2)), so no effort level is claimed. The live checkout was not touched: no fetch, no read of its git state.

- Work dir: `rev_trackintake_v2.Q8Lr/` under the scratchpad. The clone is named `constitution`, was made from the bundle, and is on `tiv2`.
- Engine: built from the head tree; sha256 `69cf0f0c…7d27`.
- Environment: every run used `env -i PATH=/usr/bin:/bin` with a literal HOME and TMPDIR inside the work dir, inside `systemd-run --user --scope -p TasksMax=3000` with `nice -n 10`, at most two jobs at a time.
- Every mutant ran on a scratch copy. The clone's working tree is clean at the end (`git status --porcelain`: 0 lines).

## Verdict: NO-GO, one important finding (cheap to fix)

Round 2 closes I2 through I9 and adds a useful lint. It closes I1 by picking one of two open heads, CON-262 over CON-243. That is the open point the fixer asked about. §11.4.214(0) decides it: when the matches resolve to more than one distinct head, the verdict is UNDECIDED (ask, or mint with a link; never guess). The fixer's own data records both heads, and records their merge as UNDECIDED in CON-262. So the shipped closure of CON-308 is a disposition the anchor forbids.

I class it as an important source-defect in tracker data, the vehicle's product. One recorded operator decision or two engine calls fix it (R2-1). Every other finding is minor-class or nit and can be a follow-up, so after R2-1 the verdict would be GO-with-follow-ups.

## Checks run (output captured this session)

| Check | Result |
|---|---|
| bundle | sha256 `0a9b4e3d…2f5b`, matches; `git bundle verify` OK; ref `tiv2` = `63f80e5216751f4f2a6d61081306c54e99af1f21`; commits on 02c10935: 1a307322, 63f80e52; diff: 70 files, +5622/-10 |
| `validate`, head DB (cwd = repo root) | `OK — 303 items, all invariants satisfied` |
| `diff --issues --fixed` | `in sync (303 vs 303)`; the exports regenerated from the DB are byte-identical to the committed ones |
| lint, RED on the 1a307322 DB | 111 findings, the same set as the fixer's `red_lint_on_bundle_head.txt` |
| lint, GREEN on head (`--origin 'tracker-intake vehicle 2026-11-12' --require-dup-check --repo-root .`) | `RESULT: PASS selected=40 findings=0 prefix=CON` |
| `test_intake_lint.sh`, two runs | `pass=47 fail=0` in both. The runs are identical to each other and to the fixer's `runs/suite_run1.txt` |
| `test_intake_lint_mutations.sh`, two runs (670 s, 725 s) | 19 of 19 killed as declared, control PASS. The runs are identical to each other and to the fixer's `runs/mut_run1.txt` |
| `run_full_suite.sh --verify-manifest` | `total=903 … RESULT: MANIFEST-OK` (round 1: 901, so this adds 2 tests) |
| `tests/gates/test_workable_items_db_sidecars_ignored.sh` | `6 passed, 0 failed` |
| shellcheck 0.11.0 (`-x -P SCRIPTDIR`) | 0 findings on each of the 3 new shell files: `test_intake_lint.sh`, `test_intake_lint_mutations.sh`, `engine_repro.sh`. All are new, so the delta is +0. `bash -n` OK |
| Python syntax | `py_compile` OK on all 6 new `.py` files (the `__pycache__` it created in the scratch clone was removed) |
| decision record vs the operator memory file `project_operator_decisions_2026_11_12_night.md` | Decisions 1 to 7 and the 00:34 reminder match one by one. The record says relayed, not verbatim. It omits only the parent pid, which is harmless |
| CON-300 vs the memory file `project_order_sync_all_upstreams_2026_11_12.md` | Faithful. The round-2 change appends the 00:34 reminder, the §11.4.296 relabel and the duplicate check |
| secret scan, my own (18 patterns, each with a planted positive needle) | 0 hits. Scanned: the full text diff 02c10935..tiv2, the strings of the new DB rows, and the raw DB strings |
| CON-333 path leak | 0 of 1063 path lines from the CON-333 scan files appear in the diff or the DB, and 0 distinctive basenames. A planted path was found (positive control); a fabricated one was not (negative control) |
| host paths | 21 added lines carry the operator's home path or the scratchpad session path. All are in copied round-1 logs (`sources/review_retest_items_logs/*.log`), and 110 base files carry the same pattern. Pre-existing, no secret value: a note, not a finding |

## Round-1 findings: status

| # | Round-1 finding | Status at 63f80e52 |
|---|---|---|
| I1 | CON-308 duplicates CON-243 and CON-262 | **Not correctly closed. See R2-1** |
| I2 | "CON-296 (GitHub issues sync)" in CON-300 and CON-332 | Closed in the data: both now cite §11.4.296 as an anchor. The detector only covers part of it (R2-2) |
| I3 | states written in prose | Closed. Columns: CON-308 UNREPRODUCED / not-started; CON-311 UNREPRODUCED / in-progress. Prose reworded; lint STATE-PROSE 0 |
| I4 | false "tracker history" sentence in CON-299 | Closed (the sentence is gone) |
| I5 | CON-333 units and scratch path | Closed. Both units are named, and the scratch location carries an `(ephemeral: …)` note |
| I6 | CON-306 / CON-309 vs CON-092 | Closed. Both carry `DISTINCT-but-similar of CON-092` |
| I7 | width of the summary row | Tracked as CON-335 |
| I8 | decisions not tracked (Jev failover) | Closed. Decision record added; CON-334 tracks the failover fix |
| I9 | history `by=User` | Tracked as CON-336 |
| M4 / M5 | engine fail-open | Tracked as CON-337; reproduced by `engine_repro.sh` |

## Findings

| # | Severity | finding_layer | Finding |
|---|---|---|---|
| R2-1 | **important** | source-defect (tracker data, §11.4.214(0)) | **CON-308 is closed as `duplicate-of` CON-262 although the match has two distinct open heads.** See below. |
| R2-2 | minor | test-instrumentation | XREF does not see the round-1 I2 instance in CON-332, and the README overstates the I2 replay. See below. |
| R2-3 | minor | test-instrumentation | Only one of SECRET's 9 patterns has a control needle. See below. |
| R2-4 | minor | test-instrumentation | EPHEMERAL misses the default `mktemp -d` shape. See below. |
| R2-5 | minor | test-instrumentation | BODY-SYNC is one-directional, and an empty body is skipped. See below. |
| R2-6 | minor | test-instrumentation (plus a pre-existing engine gap) | DUP-SAME-OPEN accepts any id on the line as the head, and the UNDECIDED path is untested. See below. |
| R2-7 | minor | process-doc | The re-mint plan is complete as a list of text files but is not mechanical. See below. |
| R2-8 | nit | test-instrumentation | Edge cases of the lint CLI. See below. |
| R2-9 | nit | pre-existing engine, not this vehicle's code | Engine `close` rewrites `created_at`, and `reopen` leaves the `obsolete_details` row. See below. |
| R2-10 | nit | test-instrumentation | The suite exits 0 when its own cleanup is refused. See below. |
| R2-11 | nit | process-doc (pre-existing schema limit) | The state lines of CON-336 and CON-337 name the evidence path but no sha256. See below. |

### R2-1 (important): CON-308 closed onto one of two open heads

**What the data shows.**

- CON-308's own Duplicate check says it is SAME-DEFECT of CON-262 and adds: "CON-243 names the same run_all.sh behaviour (plus tier awareness) and is a second open head; that CON-243 / CON-262 overlap is pre-existing and its merge stays UNDECIDED".
- CON-262's appended context says: "Candidate duplicate: CON-243 … merge UNDECIDED".
- Neither CON-243 nor CON-262 has an `obsolete_details` row or any duplicate-of link.

**Why this is not allowed.** §11.4.214(0) says: resolve every match to its head and act only on the single survivor; ">1 distinct head ⇒ UNDECIDED (ask / mint-with-link, never guess)". Clause (3) gives the autonomous default as mint-with-link over merge. The fixer acted on one head.

**A correction to round 1.** The round-1 reviewer (I1) offered "close CON-308 as duplicate-of CON-262" as one fix. Under the multi-head rule that option was itself non-compliant, and so was its other option (append the context to CON-262 and do not mint). Both pick a head.

**Harm.** No information is lost: the context sits in CON-262, CON-243 stays open, and CON-308 can be reopened. The defect is a governing-rule violation in shipped tracker data.

**Fix: either one of these.**

(a) Ask the operator (§11.4.66) whether CON-243 and CON-262 describe one defect.
- If yes, record CON-243 → CON-262 as duplicate-of (or the reverse) first. The current CON-308 closure then becomes valid as it stands.
- If CON-243 is DISTINCT, because tier awareness is its real subject, record that on CON-243. The match then has a single head and the closure also stands.

(b) Apply the autonomous default:
- Reopen CON-308. I tested this on a copy (`mut/R1.db`):
  `workable-items reopen --id CON-308 --db <copy> --why design-reconsidered --who AI --when 2026-11-13 --incident docs/qa/tracker_intake_2026_11_12_v2/inventory/repro_I1_I2.txt`
  It returns rc 0, status becomes `Reopened`, the item moves Fixed → Issues, and `validate` is OK.
- Set its Duplicate check to `UNDECIDED; candidate duplicates CON-243, CON-262`, and add the candidate link to CON-243.

Side effects of (b), stated honestly:
- `reopen` adds a Reopened history row, so CON-308's §11.4.55 reopen count goes up for an intake correction rather than a recurrence.
- The `obsolete_details` row stays in place (R2-9).
- Leaving the line at SAME-DEFECT on an open item makes the lint fire DUP-SAME-OPEN, as it should.
- No suite case covers the UNDECIDED verdict today (code mutant C9 survives), so add one in the same fix.

### R2-2 (minor): XREF misses the round-1 CON-332 form

The round-1 CON-332 text was "related CON-296 not a parent", with no label. Running the lint on the 1a307322 DB flags XREF-LABEL only on CON-300; for CON-332 it reports only DUP-CHECK.

On head copies, both of these survive with lint rc 0:
- D3: CON-332 restored to `related CON-296, not a parent`.
- D3b: the wrong label `CON-296 (runner for GitHub issues)`. It passes because a single shared title word ("runner") is enough.

Code mutant C14 (stopword list emptied) also survives.

The suite's "replay I2" inserts a label that the original CON-332 text never had. The README table's "I2 replay … caught yes" is true only for the labelled CON-300 form.

Follow-up: state this scope in the guide and the README. Optionally, flag a `CON-NNN` whose number is a defined anchor number in a sentence that says "anchor" or "rule".

### R2-3 (minor): SECRET control needles cover one pattern of nine

The selfcheck needle and every suite case use only `aws-access-key-id`. Under §11.4.201(7)(b) and §11.4.273(f) a set criterion needs a needle per member. These mutants survive with suite rc 0, cases and shipped alike:
- C3: github-pat minimum length 36 → 40.
- C4: private-key-block pattern broken.
- C11: jwt segments 8 → 80.

There is no GitLab PAT pattern either, so D2 (a GitLab PAT-shaped string in CON-315, built from fragments) survives. This batch includes GitLab-forge items.

The batch data itself is clean: my independent 18-pattern scan found 0 hits.

### R2-4 (minor): EPHEMERAL misses the default `mktemp -d` shape

These survive:
- D1: the default shape `/tmp/tmp.` + a 10-character suffix. The pattern allows a 4 to 6 character suffix and requires an uppercase letter.
- D1b: an all-lowercase 4-character suffix.
- C2: the lower bound changed from 4 to 5 (no case has a 4-character name).

`/tmp` paths are not flagged at all.

### R2-5 (minor): BODY-SYNC checks only one direction

The check is `desc in body`.

D6 adds a contradicting paragraph ("already fixed on main; no work owed") to CON-310's body_md only. After `sync db-to-md`:
- `diff` is in sync;
- `validate` is OK;
- the lint passes;
- the regenerated Issues.md publishes the paragraph.

So the inverse of round-1 M2 survives every instrument.

D5 (an empty body_md) is skipped by the lint, because of the `if r["body"]` guard. `diff` catches it, but only against the committed Markdown: `body differs (md=1155 bytes db=0 bytes)`.

### R2-6 (minor): DUP-SAME-OPEN head check, UNDECIDED untested, engine accepts a dangling superseding id

- D7b: CON-308's superseding item swapped to CON-243. Silent, because any id named on the line counts as the head.
- D8: CON-308 left Obsolete duplicate-of CON-262 while its verdict reads `UNDECIDED; candidates CON-262`. Silent.
- C9: UNDECIDED removed from the closed set. Survives.
- D7a: superseding set to CON-999. The lint catches it, but engine `validate` returns rc 0. That gap is pre-existing in the engine.

### R2-7 (minor): the re-mint plan is not mechanical

The README's list of text files is complete. These gaps remain:

(a) **No mechanism.** The engine has no command that renames an `atm_id`. `update` cannot change the id. `add --id` plus a closure would create duplicates and new history. The remaining path is hand-editing the DB, which needs a recorded decision or a new engine subcommand. The plan does not say which.

(b) **DB locations not listed:**
- `items.atm_id` (40 rows)
- `item_history.atm_id` (79 rows)
- `obsolete_details.atm_id` (CON-308)
- `doc_segments` (40 rows)
- the copy of every description inside `body_md`. `embeddings.tsv` scans only title and description, not `body_md`.

(c) **Binary DB merge not addressed.** The binary `docs/workable_items.db` has to be merged with fix227 and with main `bd0036bd`. The plan does not say:
- which vehicle lands first;
- whether to replay or to regenerate.

`apply_v2.py` refuses to run on any other DB by design, so it cannot serve as a replay tool.

(d) **Files in neither list:**
- `engine_repro.sh` hard-codes CON-306 as its target. CON-306 is also a fix227 id, so after landing the red-command that CON-336 and CON-337 cite would act on a different item (inferred, not run).
- `secret_scan.py` and `secret_scan.txt`.

(e) **`Foreign ids` lines.** The plan does not say whether these lines are kept or stripped after landing. Also, `foreign_ids()` takes only the endpoints of `CON-300..CON-311`: interior ids are not declared foreign. Today no item uses an interior id in the foreign sense (I checked every occurrence in CON-299, CON-329 and CON-330), so the current `embeddings.tsv` is correct. The range form is a latent trap.

### R2-8 (nit): edge cases of the lint CLI

- `--embeddings --skip-check NOPE` exits 0, because the code check runs after the early return.
- There is no BLIND result when `--prefix` matches no id in the DB. `--ids CON-300 --prefix ZZ` reports PASS. On the full batch the run FAILs with 32 findings, but XREF is silently blind.
- These code mutants survive: C6 (prefix auto-detection) and C8 (the `operator_decisions/` branch of PATH-MISSING).

### R2-9 (nit, pre-existing engine): `close` and `reopen` side effects

I reproduced the `close` behaviour on a copy of the 1a307322 DB (`mut/CA.db`): `created_at` went from `2026-11-12 22:48:51` to `2026-11-13 12:20:06`. Between the round-1 and head DBs, the only `created_at` change is CON-308's. No item mentions `created_at`, so this is not filed.

`reopen` leaves the `obsolete_details` row in place (seen on `mut/R1.db`).

File both as follow-ups.

### R2-10 (nit): the suite ignores a refused cleanup

Under `env -i` with HOME unset, `safe_rm_rf` refused the cleanup. That is correct fail-closed behaviour. The suite still printed `pass=47 fail=0`, exited 0, and left its temp directory behind. My recorded runs set a literal HOME.

### R2-11 (nit, pre-existing schema limit): no sha256 in the state lines

The `reproduced-host-fixture` lines of CON-336 and CON-337 name the evidence path but no sha256, because the schema has no sha field. The sha is in `SHA256SUMS` (`fb1eaea4…4866`, which I checked). §11.4.294(C) asks for path plus sha256.

## Reviewer-authored mutants (the author wrote none of these)

### Data mutants

Run by `tools/datamut.py` on copies of the head DB, with the lint run as a gate. Secret-shaped strings are assembled from fragments.

| # | Mutant | Lint | validate | diff | Outcome |
|---|---|---|---|---|---|
| D1 | `/tmp/tmp.` + 10-character mktemp suffix in CON-315 | rc 0 | 0 | 1* | **survives** (R2-4) |
| D1b | all-lowercase 4-character suffix | rc 0 | 0 | 1* | **survives** |
| D2 | GitLab PAT-shaped string | rc 0 | 0 | 1* | **survives** (R2-3) |
| D3 | CON-332 in its round-1 form, `related CON-296` without a label | rc 0 | 0 | 1* | **survives** (R2-2) |
| D3b | wrong label sharing one title word | rc 0 | 0 | 1* | **survives** |
| D4 | SAME-DEFECT verdict on open CON-306 | DUP-SAME-OPEN | 0 | 1* | killed |
| D5 | empty body_md on CON-310 | rc 0 | 0 | 1 (body differs) | lint survives; diff catches it against the committed Markdown |
| D6 | contradiction in body_md only | rc 0 | 0 | 0 after regeneration | **survives everything** (R2-5) |
| D7a | CON-308 superseding → CON-999 | DUP-SAME-OPEN | **0** | 0 | lint kills it; the engine misses it |
| D7b | CON-308 superseding → CON-243 | rc 0 | 0 | 0 | **survives** (R2-6) |
| D8 | Obsolete duplicate-of with the verdict UNDECIDED | rc 0 | 0 | 1* | **survives** |
| D9 | CON-336 `reproduction_evidence` → a missing file | rc 0 | 1 | 1 | engine kills it |
| D10 | CON-311 investigation → root-cause-found-with-evidence with no evidence | rc 0 | 1 | 1 | engine kills it |

\* A diff rc of 1 here only means the committed Markdown is stale. After `sync db-to-md` the diff is in sync; I showed that for D6. For the other rows it is an inference (UNCONFIRMED).

### Code mutants

Run by `tools/codemut.py`: one exact replacement in a copy of `intake_lint.py`, then the suite run once with `--no-selfcheck` and once as shipped.

| # | Mutant | Cases | Needles | Outcome |
|---|---|---|---|---|
| C1 | default `exists()` always true | rc 1 | no | killed (golden-bad PATH-MISSING) |
| C2 | mktemp suffix 4..6 → 5..6 | rc 0 | no | **survives** |
| C3 | github-pat 36 → 40 | rc 0 | no | **survives** |
| C4 | private-key pattern broken | rc 0 | no | **survives** |
| C5 | BODY-SYNC on the first description line only | rc 1 | no | killed (reviewer M2 case) |
| C6 | prefix auto-detection → alphabetically first | rc 0 | no | **survives** |
| C7 | typo in the `obsolete_details` query (error swallowed) | rc 1 | no | killed (fail-closed: CON-308 fires) |
| C8 | PATH-MISSING ignores `operator_decisions/` | rc 0 | no | **survives** |
| C9 | UNDECIDED dropped from the verdict set | rc 0 | no | **survives** |
| C10 | SHARED-PATH ignores `.sh` | rc 1 | yes (BLIND) | killed |
| C11 | jwt segments 8 → 80 | rc 0 | no | **survives** |
| C12 | free-form `Investigation:` check off | rc 1 | no | killed |
| C13 | missing selected ids no longer BLIND | rc 1 | no | killed |
| C14 | stopword list emptied | rc 0 | no | **survives** |

Totals: data 13 mutants (lint kills 2, engine 2 more, 9 lint survivors); code 14 mutants (6 killed, 8 survive).

**The control needles are real.** In the shipped mutation suite, every mutant declared "needle yes" (11 of 19) was stopped with `BLIND: control needle failed` in both of my runs. Direct probes of the shipped lint each exit 3 with a BLIND message:
- missing DB;
- a non-database file;
- an empty file ("no such table");
- a table with no title column;
- an empty selection;
- an unknown `--ids` value.

Their limit is breadth: one golden-bad per code, so SECRET (R2-3) and the 4-character mktemp bound (C2) have no member-level needle.

**Two mistakes in my own instruments, caught and fixed.**
1. Engine `validate` run from the work dir instead of the repo root gave 103 false violations. I re-ran from the repo root with an unmutated control copy, which gave `OK — 303 items`.
2. Reading `$?` after `| tail` gave tail's status. I re-ran the reopen probe with rc captured on its own line (§11.4.273(g)).

## Reproduction (paths under the scratchpad `rev_trackintake_v2.Q8Lr/`)

```
E="env -i PATH=/usr/bin:/bin HOME=/home/milosvasic LANG=C.UTF-8 TMPDIR=$W/tmp XDG_RUNTIME_DIR=/run/user/1000"
S="systemd-run --user --scope -q -p TasksMax=3000 nice -n 10"
cd $W/constitution
$E python3 -I scripts/workable-items/intake_lint.py --db docs/workable_items.db \
   --origin 'tracker-intake vehicle 2026-11-12' --require-dup-check --repo-root .        # GREEN
$E python3 -I scripts/workable-items/intake_lint.py --db $W/r1tree/docs/workable_items.db \
   --origin 'tracker-intake vehicle 2026-11-12' --require-dup-check --repo-root .        # 111 findings
$E $S bash tests/workable_items/test_intake_lint.sh
$E $S bash tests/workable_items/test_intake_lint_mutations.sh
$E $S python3 -I $W/tools/datamut.py $W/db/head_ro.db $W/mut scripts/workable-items/intake_lint.py $W/constitution $W/bin/workable-items
$E $S python3 -I $W/tools/codemut.py $W/constitution $W/cm
$W/bin/workable-items reopen --id CON-308 --db <copy> --why design-reconsidered --who AI \
   --when 2026-11-13 --incident docs/qa/tracker_intake_2026_11_12_v2/inventory/repro_I1_I2.txt
```

Outputs: `out/{suite_r1,suite_r2,mut_r1,mut_r2,datamut.tsv,codemut.tsv,manifest.txt,sidecar.txt}`, `mut/*.log`, `cm/*.log`.

## UNCONFIRMED / UNKNOWN

- Whether CON-243 and CON-262 are one defect. This is the operator decision that would settle R2-1 by option (a).
- Whether `diff` is in sync after regeneration for D1 to D4 and D8. I showed it only for D6.
- How an empty body_md renders after `sync db-to-md` (D5 was not regenerated).
- The CON-333 path count: I loaded 1063 path lines; the fixer's scan reports 1059. The difference of 4 was not reconciled. Both scans find 0 leaks.
- That `engine_repro.sh` acts on a different item after re-mint is an inference; I did not run it.
- Conflicts from merging main `bd0036bd`: not tested, since the vehicle has not merged it.
- From the fixer and not re-checked: whether decisions 5 and 6 were carried out, and whether external trackers mirror these items.
- Reviewer effort: unknown (§11.4.231(F.2)).
