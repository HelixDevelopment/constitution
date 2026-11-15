# Follow-up register, round 2 (drafts of tracked items)

| Field | Value |
|---|---|
| Revision | 2 (round 3: R2-F4, R2-F5 and the fastcycle temporary-directory leak added) |
| Created | 2026-11-14 |
| Status | DRAFTS: none of these is in the tracker yet; ids are placeholders `CON-PENDING-*` |
| Roadmap-Item | CON-PENDING-ENGINE-CREATEDAT |

These drafts answer finding F4 of the round-1 review. They were not filed in the tracker because this vehicle works
on a copy and must not touch the real tracker database; the lander files each one through the engine (`add`), with
the text below, and replaces the placeholder in this file and in the commit trailers. Each states what is known and
marks the rest UNCONFIRMED (§11.4.6).

## CON-PENDING-MDRT-DATALOSS (Bug): an md round trip rewrites descriptions and nulls severities

- What: an unchanged `sync db-to-md` then `sync md-to-db` round trip of the base tracker rewrites `description` on
  38 rows (replaced with different text, for example CON-030, CON-246) and sets `severity` to NULL on 3 rows
  (CON-266, CON-267, CON-268, `Low` to NULL).
- Scope: pre-existing, measured by the round-1 reviewer on the base `bd0036bd` binary and on the vehicle binary
  (same result); silent data loss on every round trip.
- Reproduction: `reproduced-host-fixture` by the reviewer (column census of the round trip on a copy of the committed
  database); root cause UNCONFIRMED (not investigated here).
- Acceptance: a round trip of an unchanged database leaves every column of every row unchanged except
  `last_modified`, with a column census as the oracle.

## CON-PENDING-226-ROWS (Task): decide the 226 rows whose created_at is later than their first event

- What: at `bd0036bd`, 226 of 263 items hold a created_at later than their first `item_history` row; 222 hold
  `2026-11-11 15:38:57` and 4 hold `2026-11-11 15:34:52` (two batch times that fit earlier document rebuilds). The
  cause of each row was not traced.
- Options: restore each to its Opened time with `restore-created-at` (one plan row each, evidence a committed blob),
  or leave them and record why. The decision is the operator's.
- Acceptance: one recorded decision; if restore, a plan file and an applier run with an audit row per item.

## CON-PENDING-CON243-NONUNIFORM (Task): CON-243 is restored, its same-second siblings are not

- What: the restore plan moves CON-243 to its Opened time `2026-11-11 15:34:35`. CON-242 and CON-244 were opened in
  the same second and keep `15:38:57`. After landing, these three items disagree.
- Resolution: part of CON-PENDING-226-ROWS; listed separately so the non-uniformity is visible.

## CON-PENDING-EVIDENCE-PROVENANCE (Task): read restore evidence from a git blob

- What: `restore-created-at` checks the sha256 the caller names; a hand-built evidence file that records an earlier
  value inside the tracker's lifetime passes (round 2 added only the lower bound VALUE-BEFORE-TRACKER).
- Options: `--evidence-commit` and `--evidence-path` read with `git cat-file` so the engine computes the sha itself,
  or a gate that resolves every audit row's evidence sha256 to a committed blob.
- Acceptance: a test with a hand-built evidence file that is not a committed blob is refused.

## CON-PENDING-FOUND-DEFECTS (Bug): defects found while working on CON-339

Each is a candidate item of its own; the lander may split them.

- D-01: `group set --item`, `repair-bodies`, `version-tags` and `sync md-to-db` write no history rows.
- D-02: `close` drops `forensic_anchor`, `closure_criteria`, `composes_with`, `parent_atm_id`, `session_ref` and
  `version_tags`; `sync md-to-db` drops `destination`, `logic_group`, `parent_atm_id`, `session_ref`,
  `version_tags` and resets `last_modified`.
- D-03: the vehicle `b48091ea` has duplicated `Obsolete` history rows (ids 592/593, 614/615, 616/617).
- D-04: `subtask add` and `subtask status` are not dispatched by `main()`.
- D-05: the 226 rows above (tracked as CON-PENDING-226-ROWS).
- D-06: `apply_restore_plan.sh` applies rows one by one (not atomic across rows); stated in its header, not changed.
- D-07: `restore-created-at --dry-run` needs write access to the live database (it opens it like a real run);
  documented, not changed.
- D-08 (round-2 review R2-F4, nit, source-defect, by reading only, not run): with `--root /` the applier's pattern
  `"$ROOT"/*` is `//*`, which no resolved directory matches, so every row is BLIND (fail-closed). Acceptance: either
  `--root /` is refused at argument time with its own message, or a test shows a row applied under `--root /` on a
  scratch root; UNCONFIRMED until run.
- D-09 (round-2 review R2-F5, nit, source-defect, pre-existing since round 1): the applier reads the plan with
  `IFS=$'\t'`; tab is IFS white space, so consecutive tabs collapse and an empty column moves every later field one
  place left. The current plan uses `-` for an absent id and is not affected. Acceptance: a plan row with an empty
  column is refused (BLIND) by a test, or the header documents the `-` convention and a check rejects empty fields.
- D-10 (round-2 review, out of scope of this vehicle, §11.4.293): `fastcycle_sibling_search_test.go` (2026-09-29)
  leaves a `wi-fastcycle-siblingsearch-bin-*` temporary directory behind on every package run (the reviewer found
  five in its `TMPDIR`). Acceptance: a package run leaves no such directory; filed separately, not changed here.
