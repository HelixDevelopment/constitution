# CON-423 r5: structural fix of review r4 (evidence)

| Field | Value |
|---|---|
| Item | CON-423 (placeholder id; the lander re-mints) |
| Answers | review round 4 of CON-423 (NO-GO: C1 to C8, L1 and L4 line model, the tracked -wal and -shm sidecars, P4 Unicode-version floors, survivors N02 N04 N06 N07 N08 N10 N14 N17 N18, N03 and N22 equivalence unproven, the database opened without a read-only URI). No review text file exists; the dispatch brief carries the summary. |
| Base | the r4 bundle (head 0f56790a), merged with origin main cb7008c4 (merge commit 1059b57f, merge, no rebase) |
| Evidence class | gate-logic, PROVISIONAL (section 11.4.289(C)(2), section 11.4.290). No live claim. |
| Model / effort | Opus 5.5 / effort UNKNOWN |
| Round | 5 of the CON-423 review loop; section 11.4.276(E)(3) structural round, fresh fixer (operator decision: rounds until GO) |

## What changed

- `scripts/validation/check_provisional_verification_lines.py`: rebuilt as a POSITIVE closed grammar
  (`class_inventory.md` section 2: LINE, SEP, JOB, CHECKS, LAYER, TARGET, ARTIFACT, DUE, NOTE). A line is accepted
  only when it is a sentence of that grammar and every reference resolves: scripts, options, selectors and env names
  under `--root`, tracker ids against the database, the due date between the item's created date and today plus the
  window, device-class targets against a registry. Free text is no longer judged word by word; it is outside the
  grammar, so the r4 word rules (folds, look-alike reader, single-letter runs) and their bypass class C1 to C8 are gone.
- Line model (L1, L4): a line counts only when it starts a top-level CommonMark paragraph; a body that CommonMark
  0.31 and the older pandoc reading count differently is refused; a heading or thematic break ends a container's
  paragraph (the r4 lazy-continuation branch hid a valid line and was removed).
- The database is opened with `pathlib.Path(...).as_uri() + "?mode=ro"`; the tracked r4 `db_copy.db-wal` and
  `db_copy.db-shm` are removed and `docs/qa/**` sidecars are ignored.
- Tests (`tests/release/test_provisional_verification_lines.sh`, 59 cases, 60 with `PVL_EVIDENCE`): P0 self-checks
  of the fixture and of an independent regex oracle (`pvl_oracle.py`); fixture command-line cases; the real database;
  the case grid; a closed-world property test; the line model against pandoc; an inventory generated from the
  complement over the whole code space U+0000 to U+10FFFF (no member floors, so no Unicode-version dependence, P4); a
  1 s work bound; the reviewers' probes and mutants vendored verbatim; 30 own mutants and the 5 reviewer mutants that
  apply, each killed by `pvl_mutate.py` after an unmutated control.
- Reviewer files: `tests/release/pvl_reviewer/*.py.txt`, byte-identical copies (sha256 in `SHA256SUMS`), stored as
  `.txt` so the full-suite census does not take them for entry points. Every narrowed expectation is a row of
  `changes.tsv` (33), every reviewer mutant that cannot apply is a row of `mutants_map.tsv` with its covering cases
  (44), the 7 that target release tooling are named in that tooling's suites.
- `config/full_suite_manifest.tsv`: the new harnesses are members of the suite; the `pvl_grid.py` note changed, so
  `--verify-manifest` reports exactly that one problem. The excluded lock is NOT accepted (brief).
- `config/git_env_class_exemptions.tsv`: rows for `pvl_fixture.py`, `pvl_grid.py`, `pvl_inventory.py`.
- Tracker: no engine edit in this round. `tracker/mint_at_landing.json` lists the items the lander mints with
  `CON-PENDING-*` placeholders, among them one for the 29 refused real-database items.

## Evidence

`evidence.md` has the claim-by-claim table. `SHA256SUMS` lists every file in this directory.
