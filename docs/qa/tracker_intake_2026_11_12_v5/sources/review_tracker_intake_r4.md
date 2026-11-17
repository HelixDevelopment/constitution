# Independent review: tracker-intake vehicle, round 4

| Field | Value |
|---|---|
| Reviewer | fresh independent reviewer (§11.4.142 / §11.4.209 / §11.4.194(6)(d)); Opus 5.5; reasoning effort is not settable or readable on this dispatch path (§11.4.231(F.2)), so no effort is claimed |
| Reviewed | bundle `trackintake_v4.tSh8/tracker_intake_v4.bundle`, sha256 `12c20c9969c3a98442f1e1aff768219ade167f74f18891dbb53a2881083f5149` (re-computed, matches); ref `tiv4`, head `b48091ea375fcc9dfd61f062f97e51d3966cd49a`; requires `02c10935`; round-3 head `53b6d9ed` |
| Prior review | `rev_trackintake_v3.p9KP/review_tracker_intake_v3.md` (NO-GO: R3-1, R3-2, R3-3 important; M-1..M-14 minor; N-1..N-3 nits) |
| Landing targets | fix227 round 11 head `fed933c0` (`fix227_r11_out.Lu7X/fix227_r11.bundle`); bare main `bd0036bd` |
| Date | 2026-11-13 |
| Environment | full (non-shallow) clone in a new mktemp root under the scratchpad; every tool run under `env -i PATH=/usr/bin:/bin HOME=<root>/home` and `systemd-run --user --scope -p TasksMax=3000 nice -n 10`, two workers at most; engine binary built from the reviewed source; tracker data changed only through the engine and only on copies; fake values only; no network command, no push, no install; the live checkout was not touched |
| Evidence class | gate-logic (§11.4.289): the real workable-items engine on scratch copies and fixture databases. Nothing here is a live landing |
| Verdict | **NO-GO** |

## Contents

1. [Verdict and why](#1-verdict-and-why)
2. [Findings](#2-findings)
3. [Closure of the round-3 findings](#3-closure-of-the-round-3-findings)
4. [Landing simulations](#4-landing-simulations)
5. [Data integrity](#5-data-integrity)
6. [Suites, static checks, secrets](#6-suites-static-checks-secrets)
7. [Reviewer mutants](#7-reviewer-mutants)
8. [Probes](#8-probes)
9. [UNCONFIRMED / UNKNOWN](#9-unconfirmed--unknown)

## 1. Verdict and why

**NO-GO.** Two findings are important and neither is minor-class under §11.4.276(G.2):

- **R4-1 (important, source-defect).** When the vehicle and the target changed *different* columns of one base item, the plan reports a safe MERGE, the replay applies it, and the landed row has lost or corrupted the target's change. The new `verify` oracle catches this. But see R4-2: the line that catches it is untested.
- **R4-2 (important, test-instrumentation; source-defect under §11.4.235(D) for the oracle members).** 7 of my 8 code mutants of `remint_ids.py` survive the author's suite, including the `verify` comparison that is the only catch for R4-1. The README closes M-13 as "every surviving reviewer mutant adopted and killed". That is true for the round-3 instances (RC1..RC7), not for the class "untested planner and oracle branches".

R4-3 (lint credential and display-control pattern gaps) is minor in severity, but it touches the security surface, so §11.4.276(G.2) does not let it ride as a follow-up.

**What is right in round 4.** The real landings are correct:

- the fix227 replay lands own 44 as CON-299..342 → CON-312..355 with every base change carried;
- main is a FAST-FORWARD;
- my independent oracle passes both;
- the author's committed `map.tsv` is byte-identical to mine.

R3-1, R3-2 and R3-3 are closed for the shapes they were raised on. The round-4 database change is engine-only and in sync. No secret value is published.

The NO-GO is about the landing *tool* as a reusable instrument. Its MERGE path is wrong, and the oracle and planner branches that guard it are not pinned by tests. The next landing (fix227 first, then any later vehicle) is exactly where those branches run.

**Next round.** The relayed 2026-11-11 decision says rounds continue until GO and every round past R_max 5 is a structural round. That decision names CON-030, CON-033 and CON-046. That it covers this vehicle is the author's reading, not re-checked here (§9). A structural fix for R4-1 is small and is outlined in §2.

## 2. Findings

### R4-1 (important, source-defect): a MERGE writes columns the vehicle did not change

**Rule claimed.** `class_inventory.md` A7: "changes on disjoint columns with no lifecycle change are merged and reported as MERGE". A1: "every update that touches a field also passes `--description`". A4: one `update` per state block.

**What the code does.** In `make_plan`, for a merged base item:

- `scripts/workable-items/remint_ids.py:610` sets `desc_src = v if "description" in dv else t`;
- `:611` then runs the chosen text through the *vehicle's* re-mint map;
- `:612` always passes `--description`.

`block_steps` (`:432-447`) passes *every* column of a state block from V.

So a MERGE writes values the vehicle never changed. There are two members of the class.

| Member | Probe | Target change (engine `update` on a T copy) | Vehicle change | Plan | Replay | Landed | `verify` |
|---|---|---|---|---|---|---|---|
| (a) target text re-pointed through the vehicle map | `probes/p02_target_desc_rewrite/` | CON-100 description gains "see CON-305 for the related target item" (CON-305 is a fix227 item) | CON-100 severity | `MERGE CON-100 … (disjoint columns)`, rc 0 | APPLIED 69 | description now says "see **CON-318**": T's reference re-pointed at the vehicle's re-minted CON-305 | FAIL, 1 mismatch (`:964`) |
| (b) whole state block overwrites T's block column | `probes/p03_block_disjoint_columns/` | CON-085 `reproduction_signature` | CON-085 `reproduction_env` | `MERGE CON-085 … (disjoint columns)`, rc 0 | APPLIED 69 | `reproduction_signature` is V's (= base) value; T's change is lost | FAIL, 1 mismatch (`:964`) |

Member (a) is realistic, not contrived. fix227 owns CON-299..CON-311, which is exactly the range this vehicle re-mints. Any fix227 edit to a base item that names one of fix227's own new items, merged with a vehicle edit to the same item, is re-pointed at an unrelated item.

The real fix227 landing has no MERGE (every base change is `target=-`), so it is not affected today.

**Impact.**

- The planner states a landing is safe when it is not.
- Only `verify` stops it, at `:964`, and R4-2 / RV1 shows that a mutant deleting that check passes the whole suite.
- With RV1 applied, both probes give `verify` PASS 48/0 on the corrupted landing (`probes/p09_survivor_nonequivalence/RV1_verify_p0{2,3}_*.txt`).

Tracker data integrity is a data-safety surface, so this is not minor-class.

**Structural fix (suggestion, not a requirement).**

- Never run T-originated text through the vehicle map. Pass `--description` only when V changed it; if the engine needs it for a body re-render, pass T's text verbatim.
- Treat any change to the *same state block* on both sides as a CONFLICT, or build the block argv from T's values for the columns V did not change.
- Add the p02 and p03 shapes as suite cases, so that RV1 dies.

### R4-2 (important, test-instrumentation; source-defect under §11.4.235(D) for RV1, RV4, RV6): 7 of 8 reviewer mutants of `remint_ids.py` survive

Each mutant is one exact replacement in a copy. The author's suite was run against the copy with FAILFAST (`tools/rvmut.py`, results in `out/rvmut.tsv`, per-mutant output in `mut/<id>/suite.txt`). Unmutated controls pass.

| Id | Mutation | Suite | Non-equivalence |
|---|---|---|---|
| RV1 | `verify`: the target-compare for columns V did not change disabled (`:963-964`) | SURVIVED 138/0 | shown: p02 and p03 corruption reads PASS 48/0 |
| RV2 | plan: merged base item always takes V's description (`:610`) | SURVIVED | shown: `p09/RV2_p02/` lands a different description (T's added line lost) |
| RV3 | rewrite: tight en dash no longer a range (`:211`) | SURVIVED | shown: `p09/RV3_rewrite_d.txt` rewrites a partly-moved `CON-290–CON-305` (`replaced=1`) where the original REFUSES (`p04/out_d.txt`) |
| RV4 | `verify`: own-item `created_at` drift not reported as KNOWN (`:997`) | SURVIVED | shown: fix227 `verify` known 46 → 2, still PASS (`p09/RV4_verify_fix227.txt`). The honest "not carried" disclosure disappears and no test notices |
| RV5 | `verify`: base `created_at` drift without a closure becomes KNOWN (`:974`) | SURVIVED | argued from code only; no engine path changes `created_at` without a close, so not shown on a reachable state (§9) |
| RV6 | `verify`: base `body_md` comparison off (`:967`) | SURVIVED | argued from code only; not shown (§9) |
| RV7a | plan: V lifecycle + T change no longer a CONFLICT (`:597`) | SURVIVED | shown: `probes/p12_rv7a_lifecycle_conflict/`. T changes CON-243 severity while V closes CON-243. Original: `CONFLICT … NOT-LANDABLE`, rc 1. Mutant: `MERGE CON-243`, rc 0 |
| RV7b | plan: T lifecycle + V change no longer a CONFLICT | KILLED | — |

**Why important.** `verify` is the proving guard of every landing; §11.4.249 and the README name it as the separate oracle. §11.4.194(6)(d) and §11.4.235(D): a proving guard whose reviewer mutant survives is unvalidated, and the source it guards is not proven correct. That is a proof-of-batch surface, so the finding is not minor-class.

The planner members (RV2, RV3, RV7a) are the M-13 class "untested branches", closed per instance again: the README row for M-13 lists the round-3 mutants as killed, and they are; the class is not.

**Fix.** Adopt RV1..RV7a. For RV5 and RV6, add a fixture or record honest equivalence reasoning. Run a class sweep: one mutant per `bad.append` / `known.append` in `verify`, and one per branch of `make_plan`'s conflict and merge logic.

### R4-3 (minor severity, source-defect; security surface, therefore not minor-class under §11.4.276(G.2)): lint pattern gaps for credential and display-control shapes

`probes/p06_lint_coverage_gaps/run.py` adds each fake string to CON-300's description through the engine on a copy, re-renders, and lints the 44 own ids. Two positive controls are FAIL as expected: a quoted password, and BEL (`\x07`).

| Case | Lint |
|---|---|
| unquoted assignment `DB_PASSWORD=fake…` | PASS, 0 findings |
| `Authorization: Basic <base64>` | PASS, 0 findings |
| bidi overrides (U+202E, U+2066..U+2069) | PASS, 0 findings |
| BOM U+FEFF and soft hyphen U+00AD | PASS, 0 findings |
| zero-width space inside an id | FAIL, 1 finding (caught by another check) |

Causes:

- the password pattern in `SECRET_PATTERNS` (`intake_lint.py:135-154`) needs quotes, and there is no Basic-auth pattern;
- `CONTROL_CHAR` (`:172`) has no bidi, BOM or soft-hyphen code points.

Bidi overrides make published Markdown display text other than what it contains (the "Trojan Source" class). That matters for a review-carrying tracker.

**Latent.** My own 20-pattern scan, with its needles, finds 0 hits in the database surfaces, the rendered documents and the round-4 added lines (§6).

### R4-4 (minor, source-defect; minor-class): spaced en dash and worded partly-moved ranges are rewritten token by token

The guide and README (M-5) say partly-moved ranges and en-dash ranges are refused. In `probes/p04_worded_ranges/`:

| Form | Result |
|---|---|
| `CON-290..CON-305` | REFUSED |
| `CON-290–CON-305` (tight en dash) | REFUSED |
| `CON-290 – CON-305` (spaced en dash) | rewritten, `replaced=1`: the end id only, so the range now spans unrelated items |
| `CON-290 to CON-305` | rewritten, `replaced=1` (`class_inventory.md` B11 documents "to" as mapped per id) |

The spaced form is not documented. The refusal logic and the per-token logic disagree on one semantic shape.

**Latent.** A scan of every tracked file in the vehicle (round-1 captured sources excluded) and of the head and fix227 databases finds no such range (`probes/p04_worded_ranges/live_scan.txt`). Its 10 hits are fix227 em-dash title separators ("CON-300 — CON-234"), not ranges, inside target text that the landing does not rewrite.

### R4-5 (minor, source-defect; minor-class): non-ASCII digits are accepted as own ids

The engine accepts `CON-３４３`, `CON-34٣`, `CON-343​` and `con-343` as ids, and `validate` says OK with them (`probes/p08_unicode_ids/out.txt`). This is engine debt, out of this vehicle's scope.

The planner's own-id pattern uses Unicode `\d`, so a fullwidth own id is mapped (`CON-３４４ → CON-357`). `verify` then fails closed: 1 `body_md` mismatch. Document rewriting refuses the fullwidth id (`p04/out_g.txt`).

The failure mode is a refused landing, not silent corruption. Use `[0-9]` / `re.ASCII` and refuse non-ASCII ids at plan time.

### R4-6 (minor, test-instrumentation; minor-class): two lint mutants survive

`probes/p11_lint_survivors/`:

- **LV4.** Lines after a non-item `## ` heading are attributed to the previous item. With a fake home path under "## Reviewer notes" after CON-300's section, the original gives PASS 0 findings, the mutant FAIL `EPHEMERAL CON-300`. The attribution reset is untested.
- **LV6.** Dedup in `load()` removed. With a two-row CON-300 made by the engine's `sync md-to-db` from a fixture document pair, the original lints only the first location row (Fixed) and misses the fake path in the Issues row; the mutant finds it (`lv6_con300.txt`: 6 vs 7 findings). The original's "first location only" scan is therefore a small coverage gap of its own. The engine's `validate` rejects that particular state (`lv6_validate.txt`: a Fixed row with non-terminal status), so reachability on a validate-clean database is UNCONFIRMED (§9).

### R4-7 (nit, process-doc): `final_lint.txt` shows a command that does not run

The evidence header shows `--ids CON-299..CON-342` and a skip list "XREF-*". The lint takes a comma list, not a range. `make_evidence.sh` passes an expanded list and skips SECTIONS, XREF-LABEL, XREF-UNLABELLED, XREF-DANGLING, PATH-MISSING, SHARED-PATH and DUP-CHECK. The capture is real; its header is not the command.

### R4-8 (minor, process-doc; minor-class): red commands omit the preconditions they need (§11.4.292(C), §11.4.199(4))

`engine_repro.sh` takes ids as arguments and the prefix from `PFX`. The `reproduction_red_cmd` values give placeholders but not the item Type and prefix the script needs.

- My first re-run, with Bug items and the default prefix, gave diffs.
- With Task items (CON-001, CON-308, CON-002) and `HELIX_RELEASE_PREFIX=CON`, it gave 0 diffs and `validate` OK (`probes/p10_engine_repro_rerun/out2.txt`).

So the evidence reproduces exactly, but only with preconditions that are not recorded.

### R4-9 (nit, source-defect): sidecar and URI hygiene

- `plan` and `verify` open V, B and T with `file:%s?mode=ro` and an unquoted path. A path containing `?` or `#` would be mis-parsed.
- Only `replay` refuses a non-empty `-wal` sidecar, and only for its target copy (`:740-742`).
- A V, B or T copied without its `-wal` is read silently from the main file. I did not reproduce an uncheckpointed WAL through the engine (§9).

### Observations (not findings)

- Lint on the head database shows findings that are not introduced by this vehicle:
  - CON-262 has 19 XREF findings, present on base too (`probes/p01_lint_head/base262_on_base.txt`);
  - hygiene across all 307 items gives 169 EPHEMERAL findings (`all_hygiene.txt`).
- The 44 own ids are PASS (`own.txt`). The 3 changed base items are PASS without the XREF codes (`base3.txt`).

## 3. Closure of the round-3 findings

| Round 3 | Round 4 claim | My check | Status |
|---|---|---|---|
| R3-1 base-item changes lost | three-way plan, replay of every base change | fix227 landing carries CON-046, CON-243 (closed duplicate-of CON-262) and CON-262; `verify` PASS 47/0; my oracle PASS `bad=0 own=44 basechg=3` | closed for the reported shape; the MERGE path is open as R4-1 |
| R3-2 title id re-pointed | one foreign set per item; separate `verify` | CON-343 (was CON-330) keeps "fix227 CON-310 amendment" | closed |
| R3-3 two fields scanned | every surface, needled | every items column, `obsolete_details`, `operator_block_details`, history, body and rendered lines are scanned; LV1, LV2, LV3, LV5 killed | closed for surfaces; pattern gaps R4-3 |
| M-1 BODY-SYNC | class closed | author suite and mutants; not re-probed by me | author claim |
| M-2 DUP-HEAD | class closed | not re-probed | author claim |
| M-3 BLOB crash | BLIND rc 3 | not re-probed (needs a non-engine write) | author claim |
| M-4 U+2028 / NUL | CONTROL-CHAR on every surface | LV1 killed; BEL caught (p06) | closed; R4-3 widens it |
| M-5 range edge cases | refused | dotted and tight en dash refused; spaced en dash not refused | partly open: R4-4, RV3 |
| M-6 one stamp | one `update` per block | stamps equal per block in the fix227 landing | closed |
| M-7 stale evidence | regenerated | my plan and replay counts equal the committed ones; `map.tsv` byte-identical | closed |
| M-8 evidence sha in env | added | present for CON-339..342 | closed |
| M-9 v2 script hard-codes CON-306 | v4 script takes ids | the v4 script names no id; reproduces with the R4-8 preconditions | closed; R4-8 |
| M-10 decision record | revised | "Items changed" lists CON-243, CON-262, CON-308; O-1 states the R2-1 relationship correctly | closed |
| M-11 swallowed table error | BLIND on missing table | `load()` raises Blind for a missing required table (`intake_lint.py:835-837`) | closed (code read) |
| M-12 rewrite list not mechanical | `refs` subcommand | `refs` runs: live 10, evidence 137, database 1 (`out/refs_fix227.txt`) | closed |
| M-13 untested oracle branches | every reviewer mutant adopted | the round-3 instances are killed; new survivors RV1..RV7a, LV4, LV6 | open as a class: R4-2, R4-6 |
| M-14 reopen counter | disclosed | history is not carried by a landing (KNOWN in `verify`) | disclosed |
| N-1..N-3 | — | N-3 still holds: 9 url-cred shapes in round-1 captured sources, all fake (§6) | unchanged, acceptable |

## 4. Landing simulations

Run on fresh copies with `tools/landx.sh`: plan, then replay through the engine, then `verify`, then `validate`, then an input sha256 re-check. My independent oracle `tools/myoracle.py` ran on each landed database.

| Target | Plan | Replay | `verify` | `validate` | My oracle | Inputs |
|---|---|---|---|---|---|---|
| fix227 `fed933c0` | REPLAY own=44 base_changes=3 steps=68, conflicts 0, CON-312..CON-355 | APPLIED 68 / 44 | PASS 47/0, known 46 | OK 319 (in a merged tree; from the vehicle tree rc 1 on unresolvable fix227 evidence paths, an artifact of the tree) | PASS | unchanged |
| main `bd0036bd` | FAST-FORWARD own=44 base_changes=3, CON-299..CON-342 | copy | PASS 307/0 | OK 307 | PASS | unchanged |
| main, forced REPLAY | REPLAY steps=68 | APPLIED | PASS 47/0 | OK 307 | PASS | unchanged |

Counts confirmed:

- own 44, CON-299..342 → CON-312..355 for fix227;
- FAST-FORWARD on main.

The author's committed `remint/fix227/map.tsv` is byte-identical to mine.

`created_at` honesty: in the unmutated `verify`, every own item carries "replay time …, not carried", and CON-243 carries the CON-339 engine defect. RV4 shows that no test pins this.

## 5. Data integrity

- **Round-4 change to `docs/workable_items.db` is engine-only.** Six items changed (CON-336, 337, 339..342: description, body and reproduction fields). Each has one matching engine `Updated` history row (ids 618..623). There are no other table changes (`tools/dbdelta.py v3 → head`).
- **Head database.** `validate` OK 307; `diff --db-only` OK; `diff` DB ↔ Markdown in sync; re-render byte-identical (`probes/p00_head_integrity/`).
- **Referential integrity** (`probes/p07_referential_integrity/out.txt`) on head, fix227 and every landed database: 0 history sequence gaps, 0 orphan history / `obsolete_details` / `operator_block_details` rows, 0 duplicate ids, foreign keys clean, `integrity_check` ok.

## 6. Suites, static checks, secrets

| Check | Result |
|---|---|
| `tests/workable_items/test_intake_lint.sh`, twice | 256/0 both; outputs identical (sha256 `f42c486a…`) |
| `tests/workable_items/test_remint_ids.sh`, twice | 138/0 both; outputs identical (`d9a7d162…`) |
| shellcheck | rc 0 |
| pyright | 0 errors, 0 warnings |
| suite manifest | MANIFEST-OK, total 905 |
| gate-ledger ratchet | `unimplemented=394 baseline=394`, PASS |
| author `SHA256SUMS` (v4 evidence) | 137 / 137 OK |

**Secrets.** `tools/leakscan.py` uses 20 patterns, each with a positive needle and one negative line, and prints only pattern, location, length and a 6-character prefix. Results:

- head database, every text column of every table: 0;
- rendered documents: 0;
- round-4 added lines: 0;
- all vehicle added lines: 9 `url-cred` shapes, all in round-1 captured sources and all fake fixture values (N-3).

No secret value appears in this review.

## 7. Reviewer mutants

None of these is in the author's lists. `CTRL-R` and `CTRL-L` (unmutated copies): both pass.

| Id | Tool | Result | Notes |
|---|---|---|---|
| RV1 | remint `verify` | SURVIVED | R4-1 / R4-2, shown |
| RV2 | remint plan | SURVIVED | shown |
| RV3 | remint rewrite | SURVIVED | shown |
| RV4 | remint `verify` | SURVIVED | shown |
| RV5 | remint `verify` | SURVIVED | argued only |
| RV6 | remint `verify` | SURVIVED | argued only |
| RV7a | remint plan | SURVIVED | shown (p12) |
| RV7b | remint plan | KILLED | |
| LV1 | lint CONTROL-CHAR | KILLED | |
| LV2 | lint rendered default | KILLED | |
| LV3 | lint history reason | KILLED | |
| LV4 | lint rendered attribution | SURVIVED | shown (p11) |
| LV5 | lint SECRET anchoring | KILLED | |
| LV6 | lint `load()` dedup | SURVIVED | shown on an engine-imported, validate-rejected state (p11) |

**Total: 14 mutants, 5 killed, 9 survived** (remint 1/8 killed, lint 4/6 killed).

The author's own mutant runs (`runs/remint_mutations.txt` "mutants=53 all killed", `runs/lint_mutations.txt` "mutants=92 all killed as declared") were checksum-verified, not re-run by me.

## 8. Probes

All paths are under `<scratch>/rev_trackintake_v4.7Mz2/`.

| Probe | What |
|---|---|
| `probes/p00_head_integrity/` | validate, diff, re-render of head |
| `probes/p01_lint_head/` | lint of own, base and all items |
| `probes/p02_target_desc_rewrite/` | R4-1 member (a) |
| `probes/p03_block_disjoint_columns/` | R4-1 member (b) |
| `probes/p04_worded_ranges/` | range forms (R4-4), live scan |
| `probes/p05_leak_scan/` | secret scan of every published surface |
| `probes/p06_lint_coverage_gaps/` | R4-3 |
| `probes/p07_referential_integrity/` | gaps, orphans, foreign keys |
| `probes/p08_unicode_ids/` | R4-5 |
| `probes/p09_survivor_nonequivalence/` | RV1..RV4 evidence |
| `probes/p10_engine_repro_rerun/` | R4-8 |
| `probes/p11_lint_survivors/` | LV4, LV6 |
| `probes/p12_rv7a_lifecycle_conflict/` | RV7a |

Other locations:

- reviewer tools: `tools/` (`landx.sh`, `myoracle.py`, `dbdelta.py`, `leakscan.py`, `rvmut.py`);
- landed databases: `land/`;
- suite and static outputs: `out/`;
- mutants: `mut/`.

## 9. UNCONFIRMED / UNKNOWN

- **UNCONFIRMED:** RV5 and RV6 non-equivalence on an engine-reachable state (argued from code only).
- **UNCONFIRMED:** that a validate-clean database can hold two rows for one id (LV6 / the first-location scan gap).
- **UNCONFIRMED:** an uncheckpointed `-wal` on V, B or T produced through the engine (R4-9 is a code reading).
- **UNCONFIRMED:** the relayed 2026-11-11 round-budget decision covers this vehicle (it names CON-030, CON-033, CON-046); not re-checked with the operator.
- **UNKNOWN:** the HTML, PDF and DOCX exports are not scanned by the lint (class C8, disclosed by the author); I did not scan them either.
- **UNKNOWN:** reasoning effort of this review (not settable or readable on this path).
- **Not re-run:** the author's own mutant sets; only their recorded results and checksums were checked.
Scrubbed copy (tools/scrub_paths.py): the one host path, on the line that says where the probe paths are, is replaced by `<scratch>`; nothing else is changed.
