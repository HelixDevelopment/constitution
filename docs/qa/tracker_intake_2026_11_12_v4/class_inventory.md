# Tracker-intake vehicle, round 4: class inventory

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T19:30:00Z |
| Status | active |
| Status summary | The classes behind R3-1, R3-2 and R3-3, enumerated before the round-4 fix was written (section 11.4.276(C)). Each member names the rule that closes it, or the evidence-backed reason it stays open. |
| Author | round-4 structural fixer, Claude Opus 5.5 (subagent of the conductor) |
| Evidence class | gate-logic only (section 11.4.289) |

## Table of contents

- [How the inventory was built](#how-the-inventory-was-built)
- [A. Landing: every way a base-item or target change can be lost or altered](#a-landing-every-way-a-base-item-or-target-change-can-be-lost-or-altered)
- [B. Cross-references: every way an id can end up naming the wrong item](#b-cross-references-every-way-an-id-can-end-up-naming-the-wrong-item)
- [C. Published surfaces: where a secret, a scratch path or a control character can reach readers](#c-published-surfaces-where-a-secret-a-scratch-path-or-a-control-character-can-reach-readers)
- [D. body_md header keys](#d-body_md-header-keys)
- [E. Minor findings of the round-3 review, mapped to their class](#e-minor-findings-of-the-round-3-review-mapped-to-their-class)
- [F. Defects the round-4 tests found in the round-4 work itself](#f-defects-the-round-4-tests-found-in-the-round-4-work-itself)

## How the inventory was built

The schema was read from the databases themselves, not from memory.

- Tables: `select name from sqlite_master where type='table'` on the base (02c10935), the vehicle
  head (53b6d9ed) and fix227 round 11 (fed933c0). The three hold the same 11 tables: `items`,
  `item_history`, `sqlite_sequence`, `obsolete_details`, `operator_block_details`,
  `firebase_metadata`, `logic_groups`, `doc_segments`, `test_diary`, `repro_gate_exemptions`, `meta`.
- Columns: `pragma table_info(<table>)` for every table. `items` has 38 columns.
- Engine behaviour: read from `scripts/workable-items/cmd/workable-items/` (`mutate.go` updateCmd,
  `states_cli.go` apply / stampStates, `states.go` renderReproLine / renderInvestigationLine,
  `crud.go` renderItemBody / appendEvidence, `obsolete.go` injectObsoleteDetails).
- Data: a full-table three-way diff (base, vehicle, target) with `tools/tdiff3.py` (this directory).

The landing tool (`scripts/workable-items/remint_ids.py`, revision 4) refuses, with an exit 3 BLIND,
any `items` column or any table that is not listed below. A new column or table therefore cannot be
landed silently: it needs a rule first.

## A. Landing: every way a base-item or target change can be lost or altered

"Base item" = an id in the base. "Own item" = an id in the vehicle and not in the base. "V", "B",
"T", "R" = the vehicle, base, target and landed (result) databases.

| # | Class | Round-3 behaviour | Round-4 rule |
|---|---|---|---|
| A1 | A base item's text or field changed in V (title, description, type, severity, created_by, assigned_to) | lost (R3-1) | replayed with `update`; every update that touches a field also passes `--description`, so the engine re-renders body_md and no header line goes stale (the engine keeps body_md verbatim on a field-only update, `mutate.go` updateCmd) |
| A2 | A base item's status or location changed in V (close, reopen, move) | lost (R3-1: CON-243) | replayed from T's state to V's state: `close` with V's closure evidence, `obsolete-details`, `reopen` with V's Reopened row, or `update --status` for a non-terminal change; any other transition is refused |
| A3 | A base item's `obsolete_details` row changed in V | lost | treated as a column of the item; replayed with `obsolete-details`, the superseding id mapped |
| A4 | A base item's reproduction or investigation block changed in V | lost (R3-1: CON-046) | replayed as one `update` per block, each with its own `--states-updated-by/--states-updated-at` from V, so each block keeps its own stamp (M-6) |
| A5 | Only the stamp of a block changed (content equal) | lost | refused: the engine stamps a block only when its content changes (`stampStates`), so a stamp-only change cannot be replayed |
| A6 | V deleted a base item | not seen | refused |
| A7 | V and T both changed the same base item | V's change lost, T's kept, silently | a three-way conflict, refused and reported; `--resolve ID=target` or `--resolve ID=vehicle` records the human decision in the plan; changes on disjoint columns with no lifecycle change are merged and reported as MERGE |
| A8 | T deleted a base item that V changed | not seen | conflict |
| A9 | V rewrote or deleted a base `item_history` row | not seen | refused (history is append-only) |
| A10 | V changed `operator_block_details`, `firebase_metadata`, `logic_groups`, `test_diary` or `repro_gate_exemptions` | lost | refused: the landing has no replay rule for these tables |
| A11 | V changed a column that has no replay rule (`forensic_anchor`, `closure_criteria`, `composes_with`, `destination`, `logic_group`, `parent_atm_id`, `session_ref`, `closure_date`, `round`, `commit_ref`, `representation`) | lost | refused |
| A12 | Schema drift: a table or `items` column that the rules do not list, a different `meta.schema_version` | not seen | BLIND (exit 3) |
| A13 | `doc_segments` | ignored | derived: every row is `kind='item'` and tied to an item (checked: 307 of 307 rows); re-generated by `sync db-to-md`; the plan refuses a non-item segment that V changed |
| A14 | `meta` (last sync, integrity hash) and `sqlite_sequence` | ignored | engine-owned; schema_version must be equal, the rest is not carried |
| A15 | `created_at` and `last_modified` | not compared | declared stamps: `last_modified` is the replay time; `created_at` is the replay time for own items, and the engine's `close` rewrites it for a base item it closes (engine defect CON-339); `verify` reports the second as KNOWN, never as a pass of a changed value. No engine command sets `created_at`, so it is not restored by hand (section 11.4.93: the engine is the only writer) |
| A16 | `item_history` of V is not carried | silent | stated: the engine writes new rows on replay; `verify` checks that R holds every T row unchanged and that the closure/reopen event sequence of V's new rows appears in R's new rows. Reopen counters fall back to the replayed events (M-14) |
| A17 | The target changed after the plan was made | replayed onto the wrong base | the plan records the sha256 of V, B and T; `replay` refuses unless the target copy hashes to the plan's T; `verify` refuses inputs that differ from the plan's |
| A18 | A replay stops part way | partly replayed copy | the copy is to be discarded (unchanged rule); `replay` prints the step |
| A19 | An own id collides with a T id or with a V item that stays | refused (round 3) | kept |
| A20 | `assigned_to` / `created_by` dropped by the replay (reviewer mutant RC6) | possible | carried for own and base items; `verify` compares them exactly |
| A21 | The engine trims state values | not compared | `verify` compares every state field exactly, so a trimmed value is a MISMATCH |
| A22 | Two rows for one id (the PK is atm_id, current_location, representation) | refused for own ids only | refused for every id the landing touches |
| A23 | The target is the base (bare main) | replayed anyway | reported as FAST-FORWARD: the vehicle database is the landed database; `--no-fast-forward` still builds the replay, as a self-test |
| A24 | V changed a base item's `body_md` and no column (a hand edit; the engine renders body_md from the columns) | lost | refused: no engine command writes body_md alone |
| A25 | The `obsolete_details` row of an item on each lifecycle path: unchanged lifecycle with a changed row, close, reopen of a closed item, close then reopen, an open item | the row was replayed only on a close (round 4 draft: a reopened own item lost its row, see F2) | replayed on every path that ends on, or passes through, an Obsolete status (the engine writes the row only on an Obsolete item); a row on an item left open is refused, because the engine has no path to it |

## B. Cross-references: every way an id can end up naming the wrong item

| # | Class | Round-3 behaviour | Round-4 rule |
|---|---|---|---|
| B1 | The foreign set was built per column (R3-2) | a declared foreign id in the title was re-minted | one foreign set per item: the union of the `Foreign ids` lines of every text column of V's version, plus B's version for a base item, plus `--foreign` |
| B2 | An own id already written in B's text of a base item (it meant something else before the vehicle minted it) | rewritten | refused as ambiguous |
| B3 | A file without a `Foreign ids` line names an id that the map moves and that T also holds | rewritten (reviewer t2.txt) | `rewrite --write` needs `--target-db`; such a token is refused unless `--own` or `--foreign` declares it |
| B4 | Ranges: reverse `P-7..P-5`, short form `P-5..7`, unbounded `P-1..P-90000000`, partly mapped, mapped to non-contiguous ids, a range that mixes foreign and own ids, the en dash form `P-5–P-7` | silent / wrong / MemoryError | refused when the range holds a moved id; no range is expanded into memory (own ids are counted against the bounds); the en dash is a range separator like `..` |
| B5 | An id inside a path (`/P-5`, `P-5.txt`) | rewritten | refused: a path is not rewritten, and a path that holds a moved id needs a human |
| B6 | Evidence paths (`reproduction_evidence`, `investigation_evidence`, closure evidence, Obsolete triple-check evidence, reopen incident) | rewritten as text | never rewritten (a rewritten path names a file that does not exist) |
| B7 | `obsolete_details.superseding_item` | rewritten | mapped when own; the plan refuses a superseding id that R will not hold |
| B8 | A script under docs/qa/ that hard-codes a moved id and is run by an item's red or green command (M-9) | not seen | `plan --repo-root` refuses it; the round-4 repro scripts take the id as an argument |
| B9 | Map integrity: header, an id named twice, two old ids for one new id, mixed prefixes | refused (two branches untested: RC7) | kept, each branch now has a test |
| B10 | The oracle re-ran the producer (section 11.4.249) | verify was blind to B1 | `verify` is a separate implementation: it aligns the id tokens of V's and R's text, recomputes the item-wide foreign set itself, checks every own token's referent (title, type, created_by), checks every base-item change and every untouched target row, and runs its own control needles before it reads a database |
| B11 | Plain-English ranges (`P-5 to P-7`) | each id mapped | each id mapped (documented: the word "to" is not a range separator, because "moved P-5 to P-7" is not a range) |
| B12 | A script run by a red or green command names an id that is foreign (B8's escape route) | n/a (no script scan) | the script scan honours the same declarations as the item's text: the item's own `Foreign ids` line, `plan --foreign`, and, inside the script, a comment line `# Foreign ids (...): ...` (also `//` and `--`; a script cannot hold a bare `Foreign ids` line); a `Foreign ids` text that is not a comment line declares nothing (round-4 draft refused every case, see F3) |

## C. Published surfaces: where a secret, a scratch path or a control character can reach readers

Every surface below is read by the lint for the selected items, and each has its own control needle
in `selfcheck()` (section 11.4.273(f)).

| # | Surface | Published where | Round-3 scan | Round-4 scan |
|---|---|---|---|---|
| C1 | `items.title`, `items.description` | Issues.md / Fixed.md, both summaries | yes | yes |
| C2 | Every other TEXT column of `items` (enumerated by `pragma table_info`, so a new column is scanned without a code change): the 11 state detail and stamp columns, `created_by`, `assigned_to`, `forensic_anchor`, `closure_criteria`, `composes_with`, `destination`, `logic_group`, `parent_atm_id`, `session_ref`, `closure_date`, `round`, `commit_ref`, `type`, `status`, `severity`, `current_location`, `representation` | the state lines and header lines of body_md, the summaries' Reproduction / Investigation cells | no (R3-3) | yes |
| C3 | `items.body_md`, every line (headers included) | Issues.md / Fixed.md verbatim | no (R3-3, DM5) | yes |
| C4 | `obsolete_details` (since, reason, superseding_item, triple_check_evidence) | the Obsolete-Details header line | no | yes |
| C5 | `operator_block_details` (what, why_exhausted_alternatives, unblock_condition, who) | the Operator-Block-Details header line | no | yes |
| C6 | `item_history` (by, on_date, reason, evidence_path) | the Reopened-Details and Evidence header lines; history is not exported otherwise | no | yes |
| C7 | The rendered `Issues.md`, `Fixed.md`, `Issues_Summary.md`, `Fixed_Summary.md` | the published sink | no | yes, with `--rendered`: the lines of each selected item's section, and the summary rows that name it; a selected item that appears in none of the rendered files is BLIND |
| C8 | The HTML, PDF and DOCX exports | derived from the Markdown | no | not scanned (binary, and derived from C7); UNCONFIRMED that every exporter carries the Markdown text unchanged |
| C9 | `test_diary`, `firebase_metadata`, `logic_groups`, `repro_gate_exemptions` | not exported by `sync db-to-md` | no | not scanned; the landing refuses any change to them (A10) |

Shapes searched on every surface:

- the 18 secret patterns of round 3 (AWS key id and secret, GitHub token and fine-grained PAT,
  GitLab PAT and other GitLab tokens, GCP key, private-key block, Hugging Face, JWT, Slack, OpenAI /
  Anthropic, URL userinfo password, bearer token, password assignment, Stripe, npm, Telegram);
- the ephemeral shapes of round 3, plus two new ones: a home directory path (`/home/<user>/`,
  `/Users/<user>/`, `~/` followed by a dotted directory) and a session id directory under a
  `.claude*` tree;
- control characters (new code CONTROL-CHAR): NUL, C0 controls other than tab and newline, DEL,
  C1 controls, U+2028 and U+2029 (M-4).

## D. body_md header keys

The engine writes these keys into the header block. BODY-SYNC now checks every key against its
source, exactly (M-1). A key outside the set, or a key written twice, is a finding.

| Key | Source | Rule |
|---|---|---|
| Status | `items.status` | exactly the column |
| Type | `items.type` | exactly the column |
| Severity | `items.severity` | present if and only if the column is not blank; exactly the column |
| Created-By | `items.created_by` | present if and only if the column is not blank; exactly the column |
| Assigned-To | `items.assigned_to` | present if and only if the column is not blank; exactly the column |
| Evidence | `item_history.evidence_path` of a closure row (Fixed, Implemented, Completed, Obsolete) | must equal the evidence of one of the item's closure rows |
| Reproduction | the 10 reproduction columns | must equal the engine rendering (`renderReproLine`): state and label, details in canonical order, code spans fenced one backtick longer than the longest run |
| Investigation | the 5 investigation columns | must equal the engine rendering (`renderInvestigationLine`) |
| Obsolete-Details | the `obsolete_details` row | present if and only if the item is Obsolete and has a row; exactly `Since: …; Reason: …; Superseding-item: …; Triple-check evidence: …` |
| Reopened-Details | the last `Reopened` row of `item_history` | exactly `By: … On: … Reason: … Evidence: …`; absent when the item has no Reopened row |
| Operator-Block-Details | `operator_block_details` | must start `WHAT: <what>` of the item's row; absent when the item has no row |
| Reopens-count | legacy, written by no current engine path | must equal the number of `Reopened` history rows |

## E. Minor findings of the round-3 review, mapped to their class

| Finding | Class closed | Where |
|---|---|---|
| M-1 | D (every header key) | `intake_lint.py` body_problems |
| M-2 | DUP-HEAD in both directions, any case, any wording: an open item that names an open SAME-DEFECT head's id on its own Duplicate check line with a verdict other than DISTINCT, or a head whose text names an open item as a candidate | `intake_lint.py` dup_heads |
| M-3 | every instrument exception is BLIND: the selection now runs inside the guarded block, and a non-text value in any read column is BLIND | `intake_lint.py` main |
| M-4 | C (CONTROL-CHAR on every surface) | `intake_lint.py` |
| M-5 | B4 | `remint_ids.py` |
| M-6 | A4 | `remint_ids.py` |
| M-7 | stale evidence: every remint artefact of this round is regenerated from the final head by `make_evidence.sh` | this directory |
| M-8 | every `reproduced-*`, `not-reproducible-with-evidence`, `root-cause-found-with-evidence` and `closed-no-defect` state of the batch carries an evidence sha256; new lint code STATE-EVIDENCE checks the class | data + `intake_lint.py` |
| M-9 | B8 | data (CON-336, CON-337) + `remint_ids.py plan --repo-root` |
| M-10 | the decision record's facts, re-checked against the databases | `docs/operator_decisions/2026-11-12_relayed_decisions.md` |
| M-11 | every table the lint reads is required: a missing or unreadable table is BLIND | `intake_lint.py` load |
| M-12 | B3 + a mechanical file list: `remint_ids.py refs` (LIVE, EVIDENCE and DATABASE classes) | `remint_ids.py`, guide |
| M-13 | every reviewer mutant adopted (see the README) | tests |
| M-14 | A16: not carried by the landing; the vehicle's own history cannot be edited (section 11.4.93) | stated |

## F. Defects the round-4 tests found in the round-4 work itself

Each was reproduced first (RED captured), then fixed, then covered by a mutant that reverts it.

| # | Defect | Where it lived | RED | Fix | Mutant |
|---|---|---|---|---|---|
| F1 | `clause_at` bounded its sentence scan at the id (`finditer(text, 0, start)`), so `$` matched at the bound and the dot of a range `FX-001..FX-003` read as a sentence end: the range end lost its clause and was reported XREF-UNLABELLED | `intake_lint.py`; the round-3 lint has the same code (`intake_lint_r3.py`) | `red/clause_endpos_probe.txt` (bounded scan finds a split at 32, the full-text scan none, control 3); the golden-good "range whose interior exists" case failed | scan the whole text and stop at the first split past the id; a self-check needle `golden-good-range-end-clause` | lint M27 |
| F2 | A vehicle item that was closed Obsolete and reopened lost its `obsolete_details` row on replay (the row was replayed only on a close) | `remint_ids.py` lifecycle_steps (round-4 draft) | `red/od_reopen_red.txt`: verify FAIL, mismatches=2, `obsolete_details: present in the vehicle only` | the row is replayed on every lifecycle path (A25) | remint X18..X22 |
| F3 | The script scan of `plan --repo-root` ignored every foreign declaration, so a red command whose script names another tracker's id could not be landed at all | `remint_ids.py` scripts_naming_moved (round-4 draft) | `red/remint_suite_on_pre_scriptforeign.txt`: the three foreign cases FAIL (132 pass, 3 fail) | B12 | remint X23, X24 |
| F4 | The suite's fixture instrument `fx_sql` did not stop on a failing edit, so a fixture whose INSERT broke a CHECK constraint ran as an unchanged copy and its case tested nothing | `test_remint_ids.sh` (round-4 draft) | `red/remint_suite_try1_pre_scriptforeign.txt`: "plan refusal: a non-item doc segment" rc=0 | `fx_sql` exits 2 on a failing edit or on an edit that changes no row; two instrument self-checks | remint S1..S3 |
| F5 | A golden-bad case of the lint's built-in needles was judged by its rule code alone, so a second check under the same code kept the needle quiet when the named check was switched off. Three instances, found by measuring every case (`red/probe_badcases_pre_binding.txt`: two cases carry two findings of their code): BODY-SYNC/header-line-separator (also caught by the Status compare), EPHEMERAL/mktemp-default (also caught by tmp-path), XREF-DANGLING/range-interior-150 (the range end stays dangling when the interior is not expanded). The round-3 lint judged the same way | `intake_lint.py` selfcheck (round 3 and the round-4 draft) | the phase-a mutation run on the draft: N24 and LC8 needle-kill=no though declared yes; `red/needle_binding_red_green.txt` | every golden-bad case carries the message text of the check it is named for, a case without one fails the needles; three suite cases switch a check off in a copy and require the needle to name it | lint M28 |
