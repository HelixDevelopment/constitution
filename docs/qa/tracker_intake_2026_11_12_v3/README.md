# Tracker-intake vehicle, round 3: fixes for the round-2 review

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T16:30:00Z |
| Status | active |
| Status summary | Round-3 answer to the round-2 independent review (NO-GO: R2-1 important, R2-2..R2-8 minor, R2-9..R2-11 nits). Every finding addressed for its class; operator decision 8 (CON-243 and CON-262 are one defect) carried out through the engine. Awaits the round-3 independent review. |
| Base | vehicle head 63f80e52 (round 2), which sits on main 02c10935; main has since moved to bd0036bd (UNCONFIRMED, not merged, not tested here) |
| Author | round-3 fixer, Claude Opus 5.5 (subagent of the conductor); effort not reported by the dispatch path |
| Evidence class | gate-logic only (section 11.4.289): scratch copies, the real workable-items engine, fixture databases; nothing here proves a product defect fixed |
| Issues | the round-3 review is owed (section 11.4.142); the remint and the landing have not been run |
| Continuation | land fix227 first, then re-mint this vehicle with `scripts/workable-items/remint_ids.py` (docs/guides/remint_ids_guide.md) |

## Table of contents

- [What round 3 changes](#what-round-3-changes)
- [Finding by finding](#finding-by-finding)
- [Operator decision 8](#operator-decision-8)
- [RED and GREEN](#red-and-green)
- [Mutants](#mutants)
- [The Pyright item](#the-pyright-item)
- [Checks run](#checks-run)
- [Files in this directory](#files-in-this-directory)
- [UNCONFIRMED and UNKNOWN](#unconfirmed-and-unknown)

## What round 3 changes

- `scripts/workable-items/intake_lint.py`: five new finding codes (XREF-UNLABELLED, DUP-HEAD,
  DUP-UNDECIDED, DUP-STATUS, OBSOLETE-STALE), BODY-SYNC in both directions, 18 SECRET patterns, the
  default `mktemp` shapes, a stricter XREF-LABEL, BLIND for a NULL column, an unknown prefix and any
  crash (never a traceback). Guide: `docs/guides/intake_lint_guide.md` revision 2.
- `scripts/workable-items/remint_ids.py` (new): plan, rewrite, replay and verify a re-mint through the
  engine. Guide: `docs/guides/remint_ids_guide.md`.
- Tests: `tests/workable_items/test_intake_lint.sh` (143 cases), `test_intake_lint_mutations.sh` (53
  mutants), `test_remint_ids.sh` (33 cases), `test_remint_ids_mutations.sh` (8 mutants); manifest rows
  for the two new tests in `config/full_suite_manifest.tsv`.
- Tracker data, all through the engine: `apply_v3.py` (log `apply_v3.log`: CON-308 reopened as
  UNDECIDED, CON-339..CON-342 minted for R2-9 and R2-6, label and text fixes, R2-11) and `apply_v3b.py`
  (log `apply_v3b.log`: operator decision 8). Exports regenerated (`docs/Issues.md`, `docs/Fixed.md`
  and their summaries).
- `docs/operator_decisions/2026-11-12_relayed_decisions.md` revision 2: decision 8 and the answered
  question O-1.

## Finding by finding

| Finding | Class named | Members found and how | Closure |
|---|---|---|---|
| R2-1 (important) | a SAME-DEFECT closure onto one of several heads (section 11.4.214(0)) | DUP-HEAD reads the chain one step: the head is the first id after `of`; a head that is closed, or that records an open UNDECIDED candidate, is not a single head. Run on the round-2 data it reports exactly CON-308 (`runs/red_v3_lint_on_v2_db.txt`). | Round 3 reopened CON-308 as UNDECIDED with both candidates (mint-with-link). Then operator decision 8 made CON-262 the single head: CON-243 and CON-308 closed duplicate-of CON-262 (`apply_v3b.log`). Lint on the final data: PASS (`final_lint.txt`). |
| R2-2 | an id cross-reference whose words do not match its target | XREF-UNLABELLED (no label, no shared word in the clause) and the stricter XREF-LABEL (more than a third of the label words not in the target) over every id in the batch. 11 findings on the round-2 data (`runs/red_v3_lint_on_v2_db.txt`), among them the CON-332 form of round 1. | Texts labelled or corrected in `apply_v3.py`; replay I2 and D3/D3b in the suite. |
| R2-3 | every SECRET pattern | 18 patterns, each with a positive and a negative needle in the suite. | Mutants C3, C4, C11 (the reviewer's) killed. |
| R2-4 | every mktemp and scratch shape | default `tmp.XXXXXXXXXX` in any case, mixed-case suffix of 4 or more, lowercase directory, `/tmp` path. | Mutants C2, N10, N11; data mutants D1, D1b. |
| R2-5 | every way body_md can disagree with the columns | empty, description missing, text after, text before, heading, Status line, Reproduction and Investigation lines, unknown key, line separator inside a header line. | Mutants N4..N9, N24; data mutants M2, D5, D6. |
| R2-6 | every duplicate-verdict state | DUP-SAME-OPEN, DUP-HEAD, DUP-UNDECIDED (no candidate, closed), DUP-STATUS (Obsolete duplicate-of without SAME-DEFECT); a golden-good UNDECIDED fixture. The engine accepting a superseding id that does not exist is CON-342. | Mutants O8, O14, C9, N12..N16. The UNDECIDED path stays covered by fixtures after decision 8 removed it from the real data. |
| R2-7 | a re-mint done by hand | `remint_ids.py` with dry run by default; a demo against a copy of the fix227 round-11 database (`remint/demo.txt`). | 8 mutants killed, one (R4) only after a new case (see below). |
| R2-8 | the lint CLI edge cases | unknown prefix BLIND, `--skip-check` validated with `--embeddings`, NULL column BLIND, crash BLIND, range interiors in `--embeddings`. | Mutants N20, N21, N25, N26, O10, O11, O19. |
| R2-9 | engine side effects of `close`, `reopen`, `update` | four items reproduced on a host fixture (`engine_repro.sh`, `engine_repro.txt`): CON-339 close rewrites created_at, CON-340 reopen keeps the obsolete_details row, CON-341 update drops Reopened-Details and Evidence lines, CON-342 dangling superseding id accepted. | Items filed; no engine change in this vehicle. CON-339 hit again in this round: the closes of decision 8 moved created_at of CON-243 from 2026-11-11 15:38:57 to 2026-11-13 13:56:42 (its Opened history row keeps 2026-11-11). |
| R2-10 | the suite's own exit on a refused cleanup | the cleanup exits 2 and names the dir; a child probe proves it. | Mutant S1 killed. |
| R2-11 | state lines without a checksum | the evidence sha256 is written into `reproduction_env` of CON-336 and CON-337 through the engine. | `apply_v3.log`. |

## Operator decision 8

Relayed to this fixer by the coordinating agent on 2026-11-13 (an interactive answer of the operator,
relayed by the conductor; not verbatim; the fixer did not hear the operator): CON-243 and CON-262 are
one defect. Recorded as decision 8 in `docs/operator_decisions/2026-11-12_relayed_decisions.md`.

- Head: CON-262, by the section 11.4.214 rule: older (created 2026-11-06, CON-243 2026-11-11), open,
  and it carries the measured census and the acceptance.
- CON-243: closed Obsolete, duplicate-of CON-262. Its tier-awareness part (the heavy L29 test) is
  appended to the acceptance of CON-262, so nothing of it is lost.
- CON-308: closed Obsolete, duplicate-of CON-262 (verdict SAME-DEFECT of CON-262).
- Lint findings of CON-243 and CON-262 before and after: four fewer, none added
  (`inventory/decision8_lint_delta.txt`; the remaining ones are in the pre-intake text of those
  items).
- The real-database cases of the suite that needed two open heads now put the second head back on a
  copy (replay R2-1, twice: the round-3 state and the round-2 line of CON-308 verbatim).

## RED and GREEN

| What | RED (before) | GREEN (after) |
|---|---|---|
| round-3 lint on the tracker data | round-2 data: FAIL, 11 findings, DUP-HEAD on CON-308 among them (`runs/red_v3_lint_on_v2_db.txt`) | round-3 data: PASS, 44 items, 0 findings (`final_lint.txt`) |
| round-3 suite on the round-2 lint | `runs/suite_v3_on_v2lint.txt` (the new cases fail) | 143/143 twice, identical (`runs/lint_suite_final_run1.txt`, `run2`) |
| Pyright crash sites | `runs/pyright/*.red.txt` (traceback, rc 1) | `runs/pyright/*.green.txt` (finding or BLIND) |
| remint suite | mutant R4 survived the first suite (`runs/remint_mut_run1_R4_survived.txt`) | a new case kills it (`runs/remint_mut_run2.txt`); suite 33/33 twice (`runs/remint_suite_final_run1.txt`, `run2`) |

## Mutants

- Lint and suite: 53 mutants, all killed as declared, run twice (`runs/lint_mut_v3_run2.txt` before
  the decision-8 rework of the real-database cases, `runs/lint_mut_v3_run3.txt` after; same set). The
  round-2 reviewer's code mutants C2, C3, C4, C6, C8, C9, C11 and C14 are adopted. N23 (`split` to
  `splitlines`) was dropped as equivalent: both report BODY-SYNC on the same input.
- remint: 8 mutants. R4 (the Foreign line rewritten) survived the first run: the ids of a Foreign line
  are excluded anyway, so it was equivalent for every input the suite had. An id written before the
  colon of a Foreign line tells the two apart; the case "Foreign line left alone before its colon too"
  was added and now kills R4.

## The Pyright item

Pyright reported, on the round-3 lint while it was being written, four errors: `.group` on a
possibly-None match at three sites and a call of a possibly-None `exists`. The round-2 lint has two of
them (`runs/pyright/pyright_v2_lint.txt`). Each site was checked for a real input:

- the body header loop (`body_problems`): REAL. A header line holding U+2028 (or another separator
  that `str.splitlines` splits on) made the lint crash with a traceback and rc 1. Fixed: split on
  newline only, report a separator inside a header line as BODY-SYNC, and a line that does not start
  with a key is a finding. Fixture `BODY-SYNC/header-line-separator`.
- EPHEMERAL `.group` and the PATH-MISSING `exists` call: not reachable (the same pattern and string
  are matched twice; `exists` is set whenever `--repo-root` is). Refactored so the type checker can
  see it.
- SAME-DEFECT head `.group`: not reachable (`verdict` is None when the line is absent). Refactored.
- The same review found two more crash paths: a NULL description and a BLOB state column. A NULL
  title, description, status or location is now BLIND (exit 3), and any exception in the lint is BLIND
  with its type printed, never a traceback. Suite fixtures `null.db` and a BLOB-state fixture
  (Pyright RED/GREEN runs `runs/pyright/nul.db.*` and `blob.*`), mutants N25 and N26.

Final: `pyright scripts/workable-items/intake_lint.py scripts/workable-items/remint_ids.py` gives 0
errors, 0 warnings (`runs/pyright/pyright_v3_final.txt`).

## Checks run

| Check | Result |
|---|---|
| `workable-items validate` | OK, 307 items |
| `workable-items diff --issues docs/Issues.md --fixed docs/Fixed.md` | in sync, 307 items |
| intake lint on the batch | PASS, 44 items, 0 findings |
| shellcheck on the four test scripts and `engine_repro.sh` | 0 warnings and errors (needle: a script with `cd foo` gives 1) |
| `run_full_suite.sh --verify-manifest` (after `--sync-guide`) | MANIFEST-OK, 905 rows |
| `cm_gate_ledger_ratchet.sh` | PASS, unimplemented 394 = baseline 394; no new CM name in a changed file |
| secret scan of the 51 changed text files and of every item text in the database, with the lint's 18 patterns | 0 hits; needle (an AWS-key-shaped string) hits |

## Files in this directory

`SHA256SUMS` lists every file. Paths of the scratchpad in captured runs are written as `<scratch>`,
`<scratchpad>` and `<mktemp-dir>`. `sources/review_tracker_intake_v2.md` is the round-2 review copied
verbatim (its scratchpad paths are left as written).

## UNCONFIRMED and UNKNOWN

- UNCONFIRMED: main has moved to bd0036bd; this vehicle is not merged onto it and nothing here was
  tested on it.
- UNCONFIRMED: the remint has been run only on copies; the landing order (fix227 first, then this
  vehicle re-minted against the database that landed) is a plan, not a result.
- UNCONFIRMED: whether fix227 carries its own version of
  `docs/operator_decisions/2026-11-12_relayed_decisions.md`; the remint demo copied this vehicle's
  version over the fix227 copy, so the lander must merge the two texts.
- UNCONFIRMED: decision 8 reached this fixer through the coordinating agent; the fixer did not hear
  the operator.
- UNKNOWN: whether the operator wants the created_at of CON-243 and CON-308 restored (CON-339
  acceptance asks for that decision).
- The lint's duplicate checks follow the chain one step and read the verdict line; they do not decide
  whether two items are one defect.
