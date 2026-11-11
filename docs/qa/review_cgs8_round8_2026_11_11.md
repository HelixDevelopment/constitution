# Independent review, full-suite fix vehicle, round 8 (sections 11.4.142 / 11.4.209)

| Field | Value |
|---|---|
| Subject | bundle `cgs8/fullsuite_fixes_r8.bundle` (sha256 bf489eac058b9569f1a477a6efdd1e07457ee03f9bcf4d39f2a393b908328ad5, I computed it), head `4118f145` on `4fab8014` |
| Items | CON-031, CON-152, CON-157, CON-161 (the fc_require_items line) |
| Reviewer | independent subagent, not the author. Model: Opus 5.5, the model the harness reports for this session. Effort: UNVERIFIED, because this dispatch path does not report it (section 11.4.231(F.2)) |
| Method | a fresh clone in my own scratchpad (`r8`), with the bundle fetched and `4118f145` checked out. I re-ran the author's suites; measured the L26 fixture myself; re-ran the 25 param-class sweep mutants plus all 21 registered equivalents through the sweep's own `run` path (JOBS 6); and wrote 6 mutants of my own outside the sweep catalogue. I ran them through the helper suite, probed every survivor against head, and re-ran one survivor against the real helper (Part 4 included). Nothing was pushed or tagged, and the canonical checkout was not touched |

## Verdict

**GO-with-follow-ups.** Counts: critical 0, important 0, minor 3, nit 1. Every open finding is minor-class (`test-instrumentation`). None touches a critical-invariant, security, data-safety, host-safety or proof-of-batch surface, so section 11.4.276(G.2) applies: each finding becomes a tracked follow-up item, and this verdict is not a zero-finding GO.

Section 11.4.276 state, stated plainly: round 8 is above the hard ceiling of 7 in clause (G). It rests only on the section 11.4.276(E)(3) escalation decision "Authorise round 8", which the tracker records for CON-031, CON-152 and CON-157 (relayed 2026-11-11, scoped to CR7-1..CR7-4 and N7-1..N7-4). I saw that decision only as tracker text. I cannot verify the operator's own words. Nothing in this round's findings asks for another round: the follow-ups ride the next iteration with a fresh budget.

## Suites (measured on head `4118f145`, this session)

| Suite | Result |
|---|---|
| `test_consumer_required_helper.sh` (bash and dash) | SUMMARY 351 pass / 0 fail, rc 0, 1m54s |
| `test_consumer_required_mutations.sh` (hand table + cheap sweep check) | sweep check: generated=169 registered=21 stale=0 uncovered=0; baseline 338/0; **42/42 killed**, rc 0 |
| Sweep, param class (25) + the 21 registered keys, through `sweep.py run` | baseline passes; killed 22, survived 21, invalid 0, timeout 0; **the survivors are exactly the 21 registry keys** (diff empty) |
| workable-items `validate` / `diff` on a copy of the DB | OK, 163 items; DB and Markdown in sync (163/163) |

I did not re-run the full 169-mutant sweep. The helper's code is unchanged in this round (comments only, which I confirmed in the diff). The registered keys and the new param class are the parts that moved, and both ran.

## Round-7 findings

| Finding | State | Evidence |
|---|---|---|
| CR7-1 (L26 WAL) | **closed** | I rebuilt the fixture with the author's own commands. The main file holds 0 bytes matching `ATM-5` and the `-wal` holds 1. The header bytes 18/19 are 2/2, which marks WAL mode. The main file copied alone reads `CON-1` (sqlite3 CLI and Python `mode=ro`), and the main file plus the `-wal` reads `CON-1,ATM-5`. So the fixture really is WAL-only. RV7-4 (`immutable=1`) is killed by L26 in bash and dash. RV7-11 (`nolock=1`) is killed by the side-file leg |
| CR7-2 (L27) | **closed** | Row `from-items-sample.2` was removed from the registry. Hand row CR7-2 is killed by `l27_kcol.db` in bash and dash |
| CR7-3 (guide) | **closed** | The guide sentence names both CON-047 rows with signature `reason:rc_3+tracked`. That matches `config/full_suite_known_failures.tsv`, and it matches `run_full_suite.py:2980-2990`: at least one `[tracked]` token is required, and every such token must name CON-047 |
| CR7-4 (param class) | **closed within its stated bound** | The site census gives param=19 sites, 0 uncovered, 25 mutants. The bound (command substitutions, path word splitting, locale classes and multi-edit mutants are not enumerated) is stated in the helper test, in the mutation file and in the commit message. RV7-7 is killed by L28 and RV7-10 by L29 |
| N7-1 | closed | `git grep sweep_consumer_required_mutants` returns nothing |
| N7-2 | closed | `FC_SWEEP_TIMEOUT` is in place: a timeout fails the verdict, and a timeout of the baseline aborts the run. `--sweep` is documented as run on demand |
| N7-3 | closed | The `case-alt.0` proof is corrected and bounded (with an IFS that holds a digit, the decision is the same but the stderr differs). I checked it by hand: with `IFS='1 '` the output `1 0 0` splits into '', '0', '0' |
| N7-4 | closed | Documented in the helper header and as an open direction under CON-161 |

## The 21 registered equivalents

All 21 survive the current suite, which is the precondition for keeping a row. I re-attacked the three new param rows:

- `pfx-strip.0` (`%%-*` -> `%-*`): the two forms differ only for an id with two or more dashes. I checked `ATM-1-2`, `A--1`, `-ATM-1` and `ATM-`: both forms exit 2 with the same message. **Holds.**
- `unset.0|3de31c61` and `unset.0|3a2fbfa0`: `git grep '_fc[ri]_'` outside the helper and the mutation file hits only `docs/qa/manifest_triage_review/review_manifest_triage_r2.md`, a review document (a carrier). The control needle is the helper itself. The helper's own reads are all preceded by assignments. **Hold, within the stated bound** ("a future caller that reads them"). I did not grep the consumer repositories; their copies of this file are the same vendored file.

The 18 older rows were attacked in round 7 with 16 fixtures each, and the helper's code is unchanged, so I did not repeat that attack.

## My mutants (section 11.4.194(6)(d)), all outside the sweep catalogue

| Id | Class | Edit | Helper suite | Probe against head |
|---|---|---|---|---|
| M1 | path word splitting | `[ -e "$_fcr_abs" ]` -> unquoted | killed (12) | — |
| M2 | command substitution | `$(cd "$(dirname "$0")/...` -> inner `$(dirname "$0")` unquoted | killed (18) | — |
| **M3** | locale / character class | the rest of the prefix `*[!A-Z0-9]*` -> `*[![:alnum:]]*` | **survives 338/0** | `AtM-5` on a foreign register: head exits 2 (usage error); M3 SKIPs 77 (bash and dash) |
| **M4** | command substitution (`cd -P`) | `$(cd "$(dirname` -> `$(cd -P "$(dirname` | **survives 338/0** | a consumer whose `<canon>/scripts/fastcycle` is a symlink (the Part 4 layout): head RAN; M4 gives a false SKIP (bash and dash). **On the real helper (copy patched in a second clone), Part 4 kills it: 342/9** |
| M5 | multi-edit | separator `,` + `IFS=,; set -- $_fci_q` (and IFS leaked to the caller) | killed (2, S5 needle) | — |
| **M6** | path word splitting | `for _fcr_p in "$@"` -> `$*` | **survives 338/0** | path argument `my data`: head RAN; M6 gives a false SKIP (bash and dash) |

## Findings

- **R8-1 (minor, test-instrumentation).** The mutation harness cannot see Part 4. When `FC_HELPER_UNDER_TEST` is set, Part 4 is skipped (`test_consumer_required_helper.sh:600`). Both the sweep and the hand table set it. So any mutant that only the Part 4 legs kill is reported as "survived". M4 is such a mutant: it survives 338/0 through the harness path, and the same edit made in the real helper fails Part 4, 9 times. Today this does not lead to a false GO: no registered equivalent depends on it, and the routine suite runs Part 4 on the real helper. But the sweep's rule that a survivor must be equivalent or registered could push a future author to write a false equivalence proof for a mutant that Part 4 kills. Follow-up: run Part 4 against the mutant (link the mutant into the scratch consumer layout instead of the checkout's helper), or state this bound beside the sweep's claim. Then adopt M4 as a paired mutant.
- **R8-2 (minor, test-instrumentation; a recurrence of CON-102 / manifest-triage review R2-1 mutant M1G).** `for _fcr_p in "$@"` -> `$*` still survives. A path argument that contains a space gets a false SKIP. This is realistic for an absolute effective path under a consumer root that contains a space, a case the suite already exercises for root resolution. Per section 11.4.214, link it to CON-102 and do not mint a new item. Adopt M6 as a paired mutant when CON-102 is fixed.
- **R8-3 (minor, test-instrumentation).** The id contract `[A-Z][A-Z0-9]*-[0-9]+` is not fully pinned. A lowercase letter inside the prefix (`AtM-5`) is a usage error, but no fixture asserts that, so M3 (`[[:alnum:]]`) survives and turns the usage error into a SKIP. Follow-up: add `AtM-5` (and, for example, `A_B-1`) to the S7 or S7b usage-error list, and adopt M3.
- **N8-1 (nit, test-instrumentation).** L29 calls `bad` when the host classes no listed UTF-8 locale's A-umlaut as `[:upper:]`. A host without such a locale therefore FAILs the whole helper suite, when only that leg is missing topology. Section 11.4.3 asks for a SKIP-with-reason for that leg, not a FAIL. (On this host the locales are present, so the leg runs.)

## Safety

All work was done under my scratchpad (`r8`, `r8m4`, `mut/`, `sws/`, `probe.*`, `w26.*`). The one removal I did used a `${P:?}/${v:?}`-guarded path. No push, no tag, no write to `/home/milosvasic/Projects/constitution`.
