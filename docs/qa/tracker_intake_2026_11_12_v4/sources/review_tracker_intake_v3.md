# Independent review: tracker-intake vehicle, round 3

| Field | Value |
|---|---|
| Reviewer | fresh independent reviewer (§11.4.142 / §11.4.209 / §11.4.194(6)(d)); Opus 5.5; reasoning effort not settable or readable on this dispatch path (§11.4.231(F.2)), so no effort is claimed |
| Reviewed | bundle `trackintake_v3.BUaH/tracker_intake_v3.bundle` (sha256 74da84a2…ea1004c), ref `tiv3`, head `53b6d9ed` on base `02c10935`; round-2 head `63f80e52` |
| Prior review | `rev_trackintake_v2.Q8Lr/review_tracker_intake_v2.md` (R2-1 important; R2-2..R2-7 minor; R2-8..R2-11 nit) |
| Date | 2026-11-13 |
| Environment | scratch clone of the bundle; every run under `env -i` and `systemd-run --user --scope -p TasksMax=3000 nice -n 10`, low concurrency; fake data and copies only; no network command, no push, the live checkout not touched |
| Verdict | **NO-GO** |

## 1. Verdict and why

**NO-GO.** Three findings are not minor-class:

- **R3-1 (important).** The documented landing path loses the vehicle's changes to *base* items.
- **R3-2 (important).** The landing path re-points a foreign id in an item title at an unrelated item, and its own oracle cannot see this.
- **R3-3 (important, credential class).** The secret and ephemeral scan reads two of the item's published fields only. §11.4.276(G.2) never treats a credential-class finding as minor-class.

All three hit the same weak point. The round-3 instruments check what the vehicle database *contains*. They do not check what *lands* or what is *published*.

### What the instruments report for each defect

| Defect | `validate` | `remint verify` | `diff` | lint |
|---|---|---|---|---|
| R3-1 (base items lost at landing) | OK, 319 items | PASS, 44/0 | — | no R3-1 finding (49 findings, unrelated) |
| R3-2 (title id re-pointed) | OK | PASS, 44/0 | — | one finding, by accident (§2) |
| R3-3 (credential shape published) | OK | — | in sync | PASS |

### What happens next

The round is past R_max. §11.4.276(E)(3) says the item STOPS here and is escalated to a recorded operator decision. Another same-approach fix round is not the next step. My structural recommendation is in §6.

Several round-3 closures were made one instance at a time, although each was claimed for the whole class (§5). This is the pattern §11.4.276(C)/(E)(2) names.

## 2. Findings

Severity follows §11.4.276(G.2); the layer follows §11.4.235(D). `file:line` refers to the reviewed tree at `53b6d9ed`. "Landed DB" means my simulated landing: `remint plan` → `replay --apply` → engine, onto a copy of the fix227 round-11 database. It has 46 steps, `RESULT: APPLIED`, and is stored at `land/landed.db`.

### R3-1 (important, source-defect): the re-mint landing carries only own items; the vehicle's changes to base items are lost, and every instrument stays green

**Where**

- `scripts/workable-items/remint_ids.py:101-117`: `make_plan` uses `own = v - b`, i.e. ids in the vehicle that are not in the base.
- `:227-285`: `own_rows` and `replay_plan` replay own ids only.
- `:314-348`: `cmd_verify` checks own rows only.
- `docs/guides/remint_ids_guide.md`, steps 1-4 and the "Honest boundary" section: neither mentions changes to items the vehicle did not mint.

**Data.** `dbdiff3.py` (base vs head) shows three base items that the vehicle changed:

| Item | Change in the vehicle | Own ids it now names |
|---|---|---|
| CON-046 | decision-2 restore: description, `body_md`, `reproduction_state` UNREPRODUCED | CON-299 |
| CON-262 | the acceptance carried over from CON-243 (decision 8) | CON-299, CON-308 |
| CON-243 | moved Issues → Fixed, `Obsolete (→ Fixed.md)`, duplicate-of CON-262 (decision 8) | CON-299, CON-308 |

So these base items need two things at landing: their changes applied, and their references to own ids re-minted. The tool does neither.

**Failure scenario.** A lander follows the guide and lands this vehicle after fix227. In the landed DB:

- CON-243 is `Queued` in Issues (description 128 characters).
- CON-262 lacks the carried-over acceptance (2981 characters instead of 4164).
- CON-046 is the 90-character stub with `reproduction_state` UNSET.

So operator decisions 2 and 8 are silently undone. In addition, landed CON-321 (the vehicle's CON-308) still says "CON-243 is closed duplicate-of CON-262" while CON-243 is open. That is the two-open-heads state that R2-1 was raised to remove.

**Instruments.**

- `validate` on the landed DB: `OK — 319 items`.
- `remint_ids.py verify`: `PASS items=44 mismatches=0`.
- The lint on the landed DB: 49 findings. 48 are SHARED-PATH and one is the XREF-UNLABELLED of R3-2. None names R3-1.
- Data mutant DM10c (CON-243 reopened with no note) is also lint-PASS.

Nothing reports the loss.

**Why important.** It silently loses two recorded operator decisions, and the vehicle records both as carried out:

- the decision record (`docs/operator_decisions/2026-11-12_relayed_decisions.md:26`) says "CON-046: description restored by the tracker-intake vehicle";
- the round-3 README `:65-73` describes decision 8 as done. It is not cosmetic. It reverses the R2-1 closure at the moment the vehicle lands.

**Class.** The class is every change the vehicle makes relative to the base, not every id it mints. A structural fix plans from a full row diff (vehicle vs base) of every tracker table. It replays modified base rows through the engine (`update`, `close`, `reopen`, `obsolete-details`), and refuses a row that both the vehicle and the target changed: a three-way conflict that a human resolves. `verify` must then check the base-row changes too.

### R3-2 (important, source-defect): replay scopes the foreign-id set per column, so a foreign id in a title is re-minted onto an unrelated item; `verify` cannot see this because it is the producer re-run

**Where**

- `remint_ids.py:152-157`: the foreign set is built from the `Foreign ids` line of *the text being rewritten*.
- `:242`: `rw = {k: rewrite_text(r[k] or "", m, prefix)[0] for k in TEXT_COLUMNS}` makes one independent call per column, so the title never sees the description's `Foreign ids` line.
- `:326`: `verify` recomputes the expectation with the same `rewrite_text` (producer = oracle, §11.4.249).
- `cmd_rewrite` (`:200-224`) scopes per file. A file that names a foreign id without its own `Foreign ids` line, or a `--foreign` flag, is rewritten (`mut/rm/t2.txt` vs `t1.txt`).

**Data.** Vehicle CON-330 has the title "fix227 CON-310 amendment (vehicle id): …". Its description says "fix227 uses ids CON-300..CON-311 on its own vehicle, so ids written there as CON-310 and CON-311 are NOT the ids minted here". The description keeps CON-310 correctly.

In the landed DB, the same item is CON-343. Its title reads **"fix227 CON-323 amendment"**. Landed CON-323 is the vehicle's own CON-310, "test_custody_sweep_red REAL-STATE block reads stash and worktree state …", an unrelated item. The intended target is fix227's CON-310, "CON-234 follow-up (L7): a remote URL with an ssh user name …", and that id is unchanged in the landed DB.

So the landed title and description of one item now name different items.

**Instruments.** `verify` reports PASS 44/0. It applies the same rewrite to both sides, so the error is equal on both sides by construction. The lint flags the item only by accident: an XREF-UNLABELLED, because the clause shares no word with CON-323's title. A different title wording would pass.

**Why important.** A published reference silently points at the wrong defect, and the landing oracle is structurally blind to it. This is a §11.4.249 producer=oracle collapse on a data-moving tool.

**Structural fix.**

- Compute the foreign set once per *item*, as the union over all its text columns.
- For `rewrite`, refuse an id that the map moves when the file also names the other vehicle, unless the caller declares it.
- Make `verify` independent of `rewrite_text`. For every id token that differs between the vehicle text and the landed text, assert two things: the old id is an own id, and the old id is not foreign anywhere in the item. Alternatively, compare each referenced item's title before and after.

### R3-3 (important, credential class): SECRET and EPHEMERAL scan only `title` + `description`; the state columns and the `body_md` header are published unscanned

**Where**

- `scripts/workable-items/intake_lint.py:373-375`: SECRET reads `r["title"] + "\n" + desc`.
- `:376-383`: EPHEMERAL reads the same fields.
- `load()` (`:468-470`) does not read the `reproduction_*` / `investigation_*` detail columns at all.

**Failure scenario (measured).**

- **DM4b.** I wrote a userinfo URL through the engine (`update --reproduction-red-cmd`, the real write path). The value lands in the column and in `body_md`. `validate` OK, lint PASS.
- **DM5.** I put an AWS-access-key-shaped value in the `body_md` `Created-By` header line. `sync db-to-md` publishes it to `Issues.md`, `diff` reports "in sync", `validate` OK, lint PASS.
- **DM4** and **DM6** put credential-shaped and mktemp-shaped values in a state column only. The lint passes. Engine `validate` happens to fail them, but only because the column no longer matches the body (a desync check, not a secret check).

For the round-3 data itself, my leak scan of the round-3 added lines found 0 hits (§3), so I claim no leak in the shipped data. The defect is the instrument's coverage.

**Why important.** R2-3 / R2-4 asked for the secret and ephemeral classes. Round 3 closed the *patterns*: 18 patterns, each with a positive and a negative needle. The *surface* it closed is two of the item's published fields. A credential that reaches the published tracker through a state line passes every gate. §11.4.276(G.2) rules out minor-class for security and credential findings.

**Structural fix.** Scan the sink:

- the rendered `Issues.md` / `Fixed.md` lines of the selected items, or at least every text column plus `body_md`;
- with one control needle per surface (§11.4.13 / §11.4.68 / §11.4.273(f)).

### Minor-class findings (follow-ups if the operator chooses GO-with-follow-ups after escalation)

#### M-1 (minor, test-instrumentation + process-doc): BODY-SYNC is not class-exhaustive; the README claims it is

`intake_lint.py:230-280` compares the following and nothing else:

- the heading;
- the `Status` prefix;
- the `Reproduction` and `Investigation` lines;
- the presence of `Obsolete-Details`.

**Not compared:** `Type`, `Severity`, `Created-By`, and the *content* of `Obsolete-Details`. Duplicate header keys are accepted, and the first one wins (`hdr.setdefault`, `:261`).

| Mutant | Change | lint | engine `validate` |
|---|---|---|---|
| DM2 | Severity line Critical, column Low | PASS | OK |
| DM3 | Type line Bug, column Task | PASS | OK |
| DM7 | Obsolete item, Obsolete-Details line removed | PASS | OK |
| DM8 | Obsolete-Details names CON-243, column CON-262 | PASS | OK |
| DM1 | second contradicting Status line | PASS | rc 1 (the engine catches it) |

`body_md` is published verbatim (DM5), so DM2, DM3, DM7 and DM8 publish a wrong header to `Issues.md` while every instrument stays green.

README `docs/qa/tracker_intake_2026_11_12_v3/README.md:54` claims R2-5 covers "every way body_md can disagree with the columns". That claim is not true. This is the instance-at-a-time closure §11.4.276(C) forbids.

#### M-2 (minor, test-instrumentation): DUP-HEAD depends on direction and wording

`intake_lint.py:283-294` needs both the literal `UNDECIDED` and "candidate" in one sentence of the *head's* description. `:419-426` reads the chain one step.

All of the following give lint PASS:

- DM9: reverse direction (CON-243 records CON-262);
- DM10: lowercase "undecided";
- DM10b: other wording ("possible second head, open question");
- DM10c: no note at all.

The author's own shape, DMC, is caught. The README (`:152`) discloses "one step", so this is a disclosed heuristic, not a hidden one. But it is the only instrument for §11.4.214(0) in this vehicle, and R3-1 shows the state it misses arising in practice.

My `validate` runs on DM9 and DM10c returned rc 1. That is an artifact of my raw-SQL mutation (the `doc_segments` rows were not moved), not an engine verdict on the reopen.

#### M-3 (minor, source-defect in the instrument): a BLOB `description` gives a traceback with rc 1

`intake_lint.py:686` (the selection, `o in r["description"]`) sits outside the `try` at `:692-699`. DM13b (description stored as a BLOB) fails with `TypeError … line 686`, Python traceback, rc 1. Exit code 1 is the lint's *findings* exit code, so a crash reads as "findings" (§11.4.201(1)).

README `:114` says "any exception in the lint is BLIND … never a traceback". A BLOB `body_md` (DM13) correctly gives BLIND rc 3.

#### M-4 (minor): U+2028 and NUL in title or description are published with every instrument green

`LINE_SEPARATORS` is checked only inside `body_md` header lines (`:252`).

- DM11: U+2028 in the title;
- DM11b: U+2028 in the description;
- DM12: NUL in the description.

All three: lint PASS, `validate` OK, published by `sync db-to-md`.

#### M-5 (minor, source-defect in the tool): `rewrite_text` range edge cases

| Input | Result | Code |
|---|---|---|
| reverse range `CON-7..CON-5` (own ids) | silently not rewritten | `:165-172`: the expansion is empty, so the range is returned unchanged |
| short form `CON-5..7` | becomes `CON-20..7` (a reversed, wrong range) | `:150-151`: the range pattern needs the prefix on both ends, so the token pass rewrites the first id only |
| unbounded range `CON-1..CON-90000000` | `MemoryError`, traceback, rc 1 | `:157`, `:168` |
| non-UTF-8 file | `UnicodeDecodeError`, traceback, rc 1; the guide's exit table says 3 / BLIND | `:214` |

Evidence: `mut/rm/a.txt`, `h.out`, `u.out`.

#### M-6 (minor): replay gives both state blocks one updated_by/at; `verify` does not compare these fields

`remint_ids.py:255-257` takes `who` and `at` from the reproduction fields first and passes them as one `--states-updated-by` / `--states-updated-at`. As a result, the landed CON-336/337 have `investigation_updated_by/at` set to the round-3 reproduction values instead of the round-2 investigation values.

`verify` (`:329-330`) does not compare `*_updated_by/at`. My mutant RC5 (drop `--states-updated-at`) survives the suite. The module docstring says these fields are "replayed … from the source row", which overstates it.

#### M-7 (minor, process-doc): the committed remint evidence is stale

`docs/qa/tracker_intake_2026_11_12_v3/remint/plan.jsonl` has 47 steps, including a `reopen` step: the pre-decision-8 state of CON-308. `replay` on the final head gives 46 steps and no `reopen` (`out/plan_head.jsonl`).

The demo and `replay_apply.txt` were therefore captured against an earlier state of the vehicle database.

#### M-8 (minor, process-doc): the R2-11 class was not applied to the new members

CON-339..CON-342 are `reproduced-host-fixture`, but their `reproduction_env` carries no evidence sha256 (§11.4.294(C)). R2-11 was fixed for CON-336/337 only.

#### M-9 (minor, process-doc): CON-336/337 still cite the v2 `engine_repro.sh`, which hard-codes CON-306

The red commands of CON-336 and CON-337 run `docs/qa/tracker_intake_2026_11_12_v2/engine_repro.sh`. That script hard-codes `--id CON-306` (`:11`, `:20`).

CON-306 is an own id here. After landing on fix227 it is fix227's "release scripts run network commands unbounded when timeout(1) is absent". This is the R2-7(d) instance, unchanged.

The guide (`remint_ids_guide.md:87-91`) says that `engine_repro.sh` "carries no id to rewrite". That is true for the v3 script only.

#### M-10 (minor, process-doc): the decision record reverses the R2-1 relationship and is not updated

`docs/operator_decisions/2026-11-12_relayed_decisions.md:48`, O-1 "why open", says R2-1 found that "CON-243, the head CON-308 had been closed onto, records CON-262 as an open UNDECIDED candidate". R2-1 actually found the reverse: CON-308 was closed onto CON-262, and CON-262 records CON-243 as the candidate.

The "Items changed" field (`:11`) does not list CON-243, CON-262 or CON-308, which revision 2 changed.

#### M-11 (minor): `load()` swallows `obsolete_details` errors

`intake_lint.py:462-466` uses `except sqlite3.Error: pass`. If the table is missing or unreadable, every item looks as if it had no obsolete row. DUP-STATUS and OBSOLETE-STALE then go quiet: a §11.4.201(6) false null, where it should be BLIND.

My mutant LC1 is killed only because the mutated query is wrong for every database. No test gives the lint a database without the table.

#### M-12 (minor, process-doc): the rewrite file list is not mechanical

The guide (`:87`) says "rewrite the live references: … scripts and docs that a reader follows". It gives no instrument and no list. M-9 is a live reference that this rule missed.

#### M-13 (minor, test-instrumentation): untested oracle branches

My code mutants that survive both suites, with observability shown where it matters (§4):

- **LC3** (Obsolete-Details on an open item) and **LC10** (heading id): each check is the *sole* oracle for its condition. DM15 and DM16 are lint FAIL with engine `validate` OK.
- **LC2**: the engine catches the same condition.
- **LC4, LC8, LC9, LC11**: further lint branches with no test.
- **RC1, RC2, RC3**: `verify` checks with no test (`obsolete_details` values, status, the Opened row). These are untested branches of the *landing oracle* itself.
- **RC6** (`assigned_to` dropped) survives, although 31 head items carry an `assigned_to`.
- **RC7**: the `read_map` guard against two old ids sharing one new id is untested.

#### M-14 (nit-to-minor): CON-308's reopen counter was raised by an intake correction

The counter rose because of a correction, not a recurrence (§11.4.55 / §11.4.214 signal). It is lost at re-mint anyway (history is not carried).

### Nits

- **N-1.** The `--dry-run` paths create sqlite `-shm` / `-wal` sidecars next to the database copy. The database bytes stay identical (checked by sha256 before and after). For `docs/workable_items.db` the sidecars are gitignored.
- **N-2.** Shellcheck reports info-level SC1091 / SC2016 only, and nothing at `-S warning`.
- **N-3.** The vehicle carries 21 added lines with absolute home or agent-scratch paths. All are in round-1 captured review logs under `docs/qa/tracker_intake_2026_11_12/sources/`.
  - They are not item text.
  - They are not new in round 3.
  - Under the guide's own rule they are captured evidence, so they are not rewritten.
  - No secret patterns matched them (§4.1, leak scan).
  - Flagged only so that the lander knows.

## 3. Per-finding verdict on R2-1..R2-11

| R2 | Round-2 finding | Round-3 claim | Verdict |
|---|---|---|---|
| R2-1 (important) | CON-308 closed onto one of two open heads | decision 8 carried out through the engine; DUP-HEAD added | **Closed in the vehicle database, reopened at landing (R3-1).** At head: CON-243 closed duplicate-of CON-262, CON-308 duplicate-of CON-262, single open head; lint PASS. In the landed DB, CON-243 is open again. DUP-HEAD is a one-step, wording-dependent heuristic (M-2). |
| R2-2 (minor) | XREF does not see the round-1 I2 instance in CON-332; the README overstates the I2 replay | stricter XREF-LABEL / XREF-UNLABELLED; data fixed | **Closed.** Lint on the v2 DB: 11 findings, including the XREF-LABEL cases; on head: 0. Author mutants O1 and N14 are killed in my re-run (§4.4). I did not re-read every v2 sub-point (§7). |
| R2-3 (minor) | only 1 of SECRET's 9 patterns had a control needle | 18 patterns, each with a positive and a negative needle | **Patterns closed** (author mutant C3 and my LC5 and LC6 are killed by the suite and the built-in needles). **Scan surface open (R3-3).** |
| R2-4 (minor) | EPHEMERAL missed the default `mktemp -d` shape | default and mixed-case shapes, lowercase directory, `/tmp` | **Closed for title and description only.** DM6 (column only) passes the lint (R3-3). |
| R2-5 (minor) | BODY-SYNC one-directional; empty body skipped | both directions; empty body; text before or after; heading, Status, Reproduction, Investigation; separators | **Partially closed.** The class claim "every way body_md can disagree" is not true (M-1). |
| R2-6 (minor) | DUP-SAME-OPEN accepted any id on the line as the head; UNDECIDED path untested | the head is the first id after `of`; DUP-UNDECIDED and DUP-HEAD cases | **Closed for the recorded forms** (author N13 and N14 are killed). DUP-HEAD is a one-step, wording-dependent heuristic (M-2). |
| R2-7 (minor) | the re-mint plan was a list, not mechanical | `remint_ids.py` plus guide plus suite | **Mechanism provided, class not closed.** Base items are lost (R3-1); per-column foreign scoping (R3-2); reverse and short ranges (M-5); the v2 `engine_repro.sh` still names CON-306 (M-9); the rewrite file list is still not mechanical (M-12); the landing oracle has untested branches (M-13). |
| R2-8 (nit) | edge cases of the lint CLI | BLIND for NULL, unknown prefix and crash | **Mostly closed.** A BLOB description still gives a traceback with rc 1 (M-3). Author N20 is killed. |
| R2-9 (nit) | engine `close` rewrites `created_at`; `reopen` keeps `obsolete_details` | four items filed (CON-339..342) and reproduced | **Closed.** All four `engine_repro.sh` probes (G1-G4) reproduce on a head copy (`mut/erepro/run.txt`). The new items' state lines lack a sha256 (M-8). |
| R2-10 (nit) | the suite exits 0 when its own cleanup is refused | fixed; mutant S1 | **Closed.** S1 is killed in my re-run (§4.4). |
| R2-11 (nit) | state lines of CON-336/337 without sha256 | sha256 written through the engine | **Closed for CON-336/337, not for CON-339..CON-342 (M-8).** |

## 4. Evidence

All paths are relative to the review directory `rev_trackintake_v3.p9KP/`.

### 4.1 Commands and results

| Check | Command (abridged) | Result | Evidence |
|---|---|---|---|
| Head `validate` (repo root) | `workable-items validate --db db/head.db` | `OK — 307 items` | `out/validate_head.txt` |
| Head `diff` | `workable-items diff …` | DB and Markdown in sync, 307/307 | `out/diff_head.txt` |
| Exports | `sync db-to-md` into a temporary location, then `cmp` | byte-identical to the committed `Issues.md` / `Fixed.md` | session transcript |
| Lint on head | `intake_lint.py --origin "tracker-intake vehicle 2026-11-12" --require-dup-check --repo-root` | `PASS selected=44 findings=0` | `out/lint_head.txt` |
| Lint on the v2 DB (control) | same | `FAIL selected=40 findings=11` | `out/lint_v2.txt` |
| Lint suite ×2 | `bash tests/workable_items/test_intake_lint.sh` | `pass=143 fail=0`, twice, identical sha256 `779c5ba7…` | `out/lint_suite_r1.txt`, `out/lint_suite_r2.txt` |
| Remint suite ×2 | `bash tests/workable_items/test_remint_ids.sh` | `pass=33 fail=0`, twice, identical sha256 `507a32fc…` | `out/remint_suite_r1.txt`, `out/remint_suite_r2.txt` |
| Pyright | `pyright` on both scripts | 0 errors; needle file: 1 error | `out/pyright.txt`, `out/pyright_needle.txt` |
| Shellcheck | `shellcheck` on the shipped and test scripts | info only; nothing at `-S warning` | `out/shellcheck.txt`, `out/shellcheck_w.txt` |
| Manifest | `--verify-manifest` | `MANIFEST-OK`, total 905 | `out/verify_manifest.txt` |
| Gate-ledger ratchet | `CM-GATE-LEDGER-RATCHET` | PASS (394 = 394) | `out/ratchet.txt` |
| Base vs head diff | `tools/dbdiff3.py` | 44 own (CON-299..342); CON-046 and CON-262 modified; CON-243 moved to Fixed; 3 non-own items name own ids | `out/dbdiff_base_head.txt` |
| Landing simulation | `remint plan` → `replay --apply` onto a copy of `db/fix227_r11.db` | `APPLIED steps=46 items=44` | `land/plan.txt`, `land/replay.txt` |
| Landed `validate` | `workable-items validate --db land/landed.db` | `OK — 319 items` | `land/validate.txt` |
| Landed `verify` | `remint_ids.py verify --map land/map.tsv …` | `PASS items=44 mismatches=0` | `land/verify.txt` |
| Landed lint | as above | `FAIL findings=49`: 48 SHARED-PATH, 1 XREF-UNLABELLED (CON-343 → CON-323) | `land/lint_landed.txt` |
| Landed facts (R3-1, R3-2) | sqlite read-only queries | CON-243 Queued/Issues; CON-262 2981 characters (head 4164); CON-046 90 characters, UNSET; CON-343 title "fix227 CON-323 amendment" | session transcript; `land/landed.db` |
| Dry-run purity | `remint` dry runs and lint on copies; sha256 before and after | database bytes identical; sidecars created (N-1) | `mut/dry2*` |
| Engine reproduction | `engine_repro.sh` (v3) on a head copy | G1-G4 all reproduce | `mut/erepro/run.txt` |
| Leak scan | `tools/leak.py`: 18 secret patterns plus home, scratch and claude-tmp paths over the added lines, with positive and negative control needles | round-3 added lines: 0 hits, needles found. Whole vehicle: 21 added `/home…` lines in `docs/qa/tracker_intake_2026_11_12/sources/` (round-1 review logs, pre-existing in the vehicle); `Issues.md` 36 hits at base and 36 at head (pre-existing); the `intake_lint.py` hit is the EPHEMERAL regex literal (a carrier) | `out/added_r3.txt`, `out/added_all.txt` |
| Working tree | `git -C repo status --porcelain` | clean | session transcript |

### 4.2 Reviewer data mutants (on copies of the head database)

| Id | Mutation | lint | `validate` | Bears on |
|---|---|---|---|---|
| DM0 | control: unmutated copy | PASS | OK | control |
| DMN | needle: AWS-key shape in CON-333 description and body | FAIL (SECRET) | — | control needle |
| DMC | author shape: CON-243 reopened, CON-262 records it as UNDECIDED candidate | FAIL (DUP-HEAD) | — | control |
| DM1 | second contradicting Status line | PASS | rc 1 | M-1 |
| DM2 | Severity line Critical, column Low | PASS | OK | M-1 |
| DM3 | Type line Bug, column Task | PASS | OK | M-1 |
| DM4 | AWS-key shape in `reproduction_env` (column only) | PASS | rc 1 (desync, not secret) | R3-3 |
| DM4b | userinfo URL written through `engine update --reproduction-red-cmd` | PASS | OK | R3-3 |
| DM5 | AWS-key shape in the `body_md` Created-By line; `sync db-to-md` publishes it; `diff` in sync | PASS | OK | R3-3 |
| DM6 | default mktemp path in `reproduction_red_cmd` (column only) | PASS | rc 1 (desync) | R3-3 |
| DM7 | Obsolete CON-308: Obsolete-Details line removed | PASS | OK | M-1 |
| DM8 | Obsolete-Details superseding CON-243, column CON-262 | PASS | OK | M-1 |
| DM9 | reverse direction: CON-243 reopened, records CON-262 as UNDECIDED | PASS | rc 1 (segment artifact) | M-2 |
| DM10 | lowercase "undecided" | PASS | — | M-2 |
| DM10b | other wording | PASS | — | M-2 |
| DM10c | CON-243 reopened, no note | PASS | rc 1 (segment artifact) | M-2, R3-1 |
| DM11 | U+2028 in the title | PASS | OK | M-4 |
| DM11b | U+2028 in the description | PASS | OK | M-4 |
| DM12 | NUL in the description | PASS | OK | M-4 |
| DM13 | `body_md` as a BLOB | BLIND rc 3 (correct) | — | R2-8 |
| DM13b | `description` as a BLOB | traceback, rc 1 | — | M-3 |
| DM14 | Investigation body line contradicts the column | FAIL | rc 1 | LC2 observability |
| DM15 | Obsolete-Details header line on open CON-321 | FAIL | OK | LC3: sole oracle |
| DM16 | heading id CON-321 → CON-320 | FAIL | OK | LC10: sole oracle |

Plus the remint adversarial inputs in `mut/rm/`: reverse range, short form, en-dash and "to" forms, unbounded range, non-UTF-8 file, title with and without a `Foreign ids` line, zero-padded ids (M-5, R3-2).

### 4.3 Reviewer code mutants (my own, not the author's)

`tools/mutlist.jsonl`; results in `out/my_code_mutants.txt`.

- **L-mutants:** the lint suite runs with `--no-selfcheck` and fail-fast, then one control-needle call.
- **R-mutants:** the remint suite runs against the mutated copy.

| Id | Mutation | Suite | Built-in needles | Note |
|---|---|---|---|---|
| LC1 | `obsolete_details` query fails, error swallowed | KILLED | no | killed only because the query is wrong for every database (M-11) |
| LC2 | BODY-SYNC Investigation line not compared | SURVIVED | no | engine catches it (DM14) |
| LC3 | BODY-SYNC Obsolete-Details on an open item off | SURVIVED | no | sole oracle (DM15) |
| LC4 | STATE-PROSE structured Investigation line off | SURVIVED | no | untested branch |
| LC5 | SECRET slack minimum 10 → 50 | KILLED | yes | |
| LC6 | SECRET telegram `AA` → `AB` | KILLED | yes | |
| LC7 | EPHEMERAL `/tmp/` branch broken | KILLED | no | |
| LC8 | `MAX_RANGE` 200 → 11 | SURVIVED | no | no test of a range interior of 12-200 ids |
| LC9 | PATH-MISSING keeps trailing punctuation | SURVIVED | no | the false-positive guard is untested |
| LC10 | BODY-SYNC heading id not compared | SURVIVED | no | sole oracle (DM16) |
| LC11 | EPHEMERAL exemption on any line saying "ephemeral" | SURVIVED | no | the exemption is broadened, untested |
| RC1 | `verify`: `obsolete_details` values not compared | SURVIVED | n/a | landing oracle untested |
| RC2 | `verify`: status not compared | SURVIVED | n/a | landing oracle untested |
| RC3 | `verify`: Opened row not required | SURVIVED | n/a | landing oracle untested |
| RC4 | `rewrite` writes each file before checking the next | KILLED | n/a | |
| RC5 | replay drops `--states-updated-at` | SURVIVED | n/a | M-6 |
| RC6 | replay drops `assigned_to` | SURVIVED | n/a | `verify` would catch it in real use; no fixture has `assigned_to` |
| RC7 | `read_map` accepts two old ids for one new id | SURVIVED | n/a | guard untested |
| RC8 | plan starts at `max(target)` (collides) | KILLED | n/a | |

**Total: 6 of 19 killed, 13 survived.** The survivors are test-instrumentation findings (M-13). None of them changes the verdict on its own.

### 4.4 Author mutants (representative subset, re-run by me at concurrency 1)

**Lint.** Run with `INTAKE_LINT_MUT_ONLY=O1,O4,O6,C3,C8,N5,N13,N14,N20,N24,S1 INTAKE_LINT_MUT_JOBS=1 bash tests/workable_items/test_intake_lint_mutations.sh`.

- Control passes (the unmutated copy passes the suite and its control needles).
- `RESULT: mutants=11 all killed as declared`, exit 0.
- Each mutant was killed by the suite's own cases. The built-in needles also stopped every mutant declared "yes" (O1, O4, O6, C3, C8, N5, N13, N14, N24).
- Evidence: `out/author_mut_lint.txt`.

**Remint.** Full set (R1..R8), run with `WORKABLE_ITEMS=<engine> bash tests/workable_items/test_remint_ids_mutations.sh`.

- Control passes.
- `RESULT: pass=9 fail=0` (control plus 8 mutants, all killed), exit 0.
- Evidence: `out/author_mut_remint.txt`.

**What this shows.** The author's mutants are honest: killed as declared. They do not cover the branches my survivors in §4.3 show, and none of them targets R3-1, R3-2 or R3-3.

## 5. Structural judgment (§11.4.276(C) / (E))

The question is whether round 3 closed the *classes* or more *instances*.

| R2 | Class named in round 2 | What round 3 did | Class-exhaustive? |
|---|---|---|---|
| R2-1 | single-head duplicate closure | fixed the data; added a one-step heuristic | Data yes, instrument no (M-2). The landing path reintroduces the state (R3-1). |
| R2-3 / R2-4 | credentials and scratch paths reaching the tracker | enumerated *patterns* exhaustively | No. The *surfaces* were not enumerated (R3-3). |
| R2-5 | `body_md` vs columns | added checks for the fields named in round 2 | No. Type, Severity, Created-By, Obsolete-Details content and duplicate keys are missing (M-1), contrary to the README claim. |
| R2-7 | a re-mint done by hand | a tool for own ids | No. The class is "every vehicle change lands correctly"; base items (R3-1) and cross-column foreign scoping (R3-2) are outside it. The oracle is the producer re-run (§11.4.249). |
| R2-11 | state lines without sha256 | fixed the two named items | No. Four newer items have the same gap (M-8). |

So the round-3 fixes are largely instance closures labelled as class closures. Under §11.4.276(E)(2) that alone forces a structural round. Under §11.4.276(E)(3) the round budget is spent.

## 6. Recommendation (for the escalation, §11.4.276(E)(3))

The operator's choices under (E)(3) are:

- re-scope via §11.4.148;
- replace via a structural new item;
- a §11.4.271 waiver for residual LOW only. R3-1..R3-3 are not LOW.

My recommendation is a structural replacement of the landing path.

1. **Landing.** Plan from a full three-way row diff (base, vehicle, target) of every tracker table. Replay *all* vehicle changes through the engine: own items, plus modified base items. Refuse a row that both sides changed. Compute the foreign set per item and per document.
2. **Oracle.** Make `verify` independent of the producer. Check every changed id token against the own set and the item-wide foreign set. Check every modified base row against the vehicle's version.
3. **Sink scan.** Run SECRET and EPHEMERAL over the rendered `Issues.md` / `Fixed.md` lines of the selected items, or every text column plus `body_md`, with one control needle per surface.
4. **Small items, done together.** Fix the README / guide claims (M-1, M-9, M-12), the decision record (M-10), the R2-11 class (M-8) and the BLOB traceback (M-3).

The minor findings can be tracked follow-ups if the operator so decides. None of them blocks on its own.

## 7. UNCONFIRMED / UNKNOWN

- **UNCONFIRMED: landing order.** I simulated landing *after* fix227 (target = copy of `db/fix227_r11.db`), as the README plans. The real order, and main's tip `bd0036bd`, were not tested. A landing onto a database that still holds the base versions of CON-046 / CON-243 / CON-262 would lose the same changes (R3-1 depends on the replay scope, not on the target), but I did not run that case.
- **UNCONFIRMED: R2-2's original text.** I re-checked R2-2 against the data the v2 review cites, not against a fresh reading of every v2 sub-point.
- **UNCONFIRMED: Pyright and network.** Pyright ran under `env -i` but without network isolation (`unshare -rn` is not permitted on this host). I cannot assert that the npm CLI made no network call.
- **UNKNOWN: engine `validate` modes.** Whether `validate` compares the Type and Severity header lines in another mode. I ran the default `validate` only; the reproduction closure gate (`states freeze`) is not armed in these databases.
- **UNCONFIRMED: decision 8.** It is relayed, not verbatim (as the vehicle itself states). I did not check its content against the operator.
- **Author mutants.** Only a representative subset was re-run (§4.4), not all 53 lint mutants.
- **DM9 / DM10c `validate` rc 1.** These come from my raw-SQL mutation (`doc_segments` not moved), not from the engine's reopen path.
- **Host load.** Host load was about 40 during the runs. All runs used `nice` and low concurrency, and no timing is claimed.
