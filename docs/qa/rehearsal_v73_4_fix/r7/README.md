# CON-423 round 7: the verification-line checker reads a real CommonMark parse

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-16 |
| Item | CON-423 (rehearsal of the v73.4 cut, D2) |
| Round | 7 (structural, sections 11.4.276(E)(3) and 11.4.250), after the r6 NO-GO review |
| Class | gate-logic, PROVISIONAL (sections 11.4.289(C)(2), 11.4.290); no live claim |
| Effort | UNKNOWN (not settable or readable on the dispatch path, section 11.4.231(F.2)) |

## What changed and why

Review r6 found three shapes the r6 hand-written line model counted as a visible line
while every reader shows them as a continuation (I-1):

- an empty list item after a paragraph;
- a list item, a blank line, then a line indented four columns;
- a quote paragraph followed by kind-7 HTML.

It also showed `<span hidden>` and `display:none` hiding the line. Rounds 5 and 6 each
patched the model for the shapes found, which is the heuristic-tower pattern (section
11.4.250). Round 7 removes the model.

- **Decision source.** `scripts/validation/check_provisional_verification_lines.py` reads the token stream of
  markdown-it-py 3.0.0 (preset `commonmark`). A line counts only when all of the following hold:
  - it starts a top-level paragraph (`paragraph_open`, level 0);
  - the paragraph's inline content starts with the bold label;
  - the paragraph's first source line starts with `**Verification:** provisional` at column 0.
- **Raw HTML.** Any raw HTML other than a complete comment refuses the body. This covers every hiding or wrapping
  element and the `<!-->` reading difference.
- **The label anywhere else.** If the label appears in any other source line or in any other rendered text (inline
  text, code, comments, link titles and destinations, block content), the body is refused.
- **Dependency.** The parser is a recorded dependency (section 11.4.270): [dependency_verdict.md](dependency_verdict.md).
  If it is missing or a version is not tested, the result is BLIND (fail closed).
- **Database read** (review r6 I-3, M-1):
  - the path is resolved with `realpath` before the copy;
  - the database and its sidecars are opened non-blocking and must be regular files on the open descriptor;
  - the copy is bounded by `MAX_DB_BYTES` (1 GiB);
  - a FIFO, a device or a symlink to `/dev/zero` gives BLIND within the time bound.

## Findings of review r6 and where each is closed

| Finding | RED (on the r6 checker) | Fix | GREEN |
|---|---|---|---|
| I-1 container and paragraph state | `red/blockstate_r6.txt`: `danger=3498` of 39009 bodies; `red/lineend_r6.txt`: `danger=9` (all on the reviewer's three shapes R01-R03) and `pandoc_danger=6`; `red/probe_r6_on_r6.txt`: 10 DANGER lines; `red/probe_hide_on_r6.txt`: 4 of 4 hiding bodies accepted | the parser is the decision source; raw HTML other than complete comments refused; the label anywhere else refused | `green/blockstate.txt`: `danger=0`; `green/lineend.txt`: `danger=0 pandoc_danger=0`; `green/probe_r6.txt`: 0 DANGER; P11 `probes_r6 ... danger=0 hide=4 hide_accepted=0` |
| I-2 reviewer mutant RW04 survives | `RW04` survived the r6 suite | the mutated code (the near rule in the quote and list branch) no longer exists | `RW04` is NOT-APPLICABLE with a map row (old text occurs 0 times); the property is covered by pvl_blockstate and own O46 O47 |
| I-3 a symlinked path gives a false PASS | `red/api_r7_cases_on_r6.txt`: direct path `fail=1`, symlinked path `items=1 provisional_status=0` (PASS) | `realpath` before the copy | P4c and `api_r7`: the row only in the target's `-wal` is read through the link |
| M-1 unbounded copy | `red/api_r7_cases_on_r6.txt`: a `-wal` symlink to `/dev/zero` and a FIFO `-journal` both TIMEOUT after 60 s | non-blocking open, `S_ISREG` on the descriptor, byte budget | P4c: BLIND within 60 s, "is not a regular file"; own mutants O52 O53 killed |
| M-2 the P5 needle opened the real database in place | - | the needle counts on a byte copy | P5 |
| M-3 the RW01 property was not killed by pvl_mutate | RW01 survived pvl_mutate | `api_r7` adds a WAL database with a live writer (the row only in `-wal`) | RW01 killed |
| M-4 lock note mismatch, stale census | - | `--generate-manifest --write` and `--sync-guide` run; `tests/release/pvl_blockstate.py` added as a member | the lock line for `tests/release/pvl_grid.py` still needs an operator acceptance (see Open questions) |
| M-5 "exhaustive" overstated | - | the docstrings of `pvl_lineend.py` and `pvl_blockstate.py` now name what they enumerate and say they are not a proof over every document | - |

The r6 README (`../r6/README.md`) is kept as recorded. Its row "I-1 class enumeration" describes the
line-ending and start-of-line class only. It did not cover container or paragraph state, which
is what review r6 M-5 pointed out.

## The new class harness

`tests/release/pvl_blockstate.py` enumerates the state a reader is in when the line arrives:

- 111 contexts, 13 joins, 9 suffixes and 3 line endings, plus the 16 reviewer shapes (39009 bodies).
- Every body the checker accepts is rendered by markdown-it-py, by pandoc `commonmark` and by pandoc `gfm`.
  pandoc is skipped for a lone CR, and a needle proves it is blind there.
- The HTML is judged by an html.parser oracle that does not share code with the checker.

It covers the listed members and their cross product, not every CommonMark document.

False refusals rose from 2877 (r6) to 4557. These are bodies a reader renders cleanly that
the checker refuses, the safe direction. That is the price of refusing all raw HTML and
every other placement of the label.

On the real tracker database, read from a byte copy, the suite step P5 counts 29 provisional
items, and the checker refuses all 29, as r6 did. Only the first reason per item is reported.
For 4 of the 29 that first reason is the raw-HTML rule (`suite_run1.txt`, `P5-REFUSED` lines).

## Mutants

- **Own** (`tests/release/pvl_mutants.tsv`): 49 rows, each killed.
- **Retired** (`tests/release/pvl_mutants_retired.tsv`): 11 rows (O20 O23 O24 O25 O26 O27 O32 O33 O34 O35 O42). Their code was removed with
  the line model; every run re-proves the old text occurs 0 times.
- **Equivalent** (`tests/release/pvl_mutants_equivalent.tsv`): 3 rows (O48 O50 O60), reported as survivors, never
  counted as killed. Each row carries the argument. `tools/survivor_search.py` found no body that tells
  them apart: `survivor_search.txt`.
- **Reviewer**: 20 apply to this suite and are killed:
  - 5 of r2-r4;
  - RV01-RV12 except RV04, RV07, RV11;
  - RW01-RW03, RW07-RW09.
- **Reviewer, not applicable**: RV07, RV11, RW04, RW05, RW06, RW10 have map rows in
  `tests/release/pvl_reviewer/mutants_map.tsv`. Their old text occurs 0 times.
- **Run 1** survivors were O46, O48, O50, O58, O59, O60 and RW03 (`mutate_run1.txt`).
  - O46, O58, O59 and RW03 were turned into kill cases CON-961 to CON-964 in `api_r7`:
    - a label only in a link reference definition, plain or written with a character reference;
    - a label on the counted line inside a comment or a link title (reason-level: the grammar refuses that line too).
  - O48, O50 and O60 are the equivalent rows above.
- **Survivor search** (`survivor_search.txt`, 154 label placements and 78018 blockstate bodies per mutant, accept/refuse
  level). Telling bodies per mutant:
  - O46 26/154, RW03 12/154: kill cases added;
  - O58 0, O59 0: they change only the refusal reason, so the reason-level cases CON-963 and CON-964 kill them;
  - O48 0, O50 0, O60 0: equivalent.

  The search is an enumeration over those bodies. It does not prove equivalence over every document.

## Reviewer material vendored verbatim

`tests/release/pvl_reviewer/` holds three files byte-equal to the r6 review output; their sums
match the review's own SHA256SUMS:

- `mutants_r6.tsv` (the review's `reviewer_mutants_r6_tsv.txt`; only its RW rows are reviewer mutants);
- `probe_r6.py.txt`;
- `probe_hide.py.txt`.

## Runs

All runs were made on 2026-11-16 under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`, one heavy job at a time.

- `suite_run1.txt` and `suite_run2.txt` (`tests/release/test_provisional_verification_lines.sh`):
  - each ends `RESULT: pass=96 fail=0`, exit 0;
  - `compare.txt` shows the two files are byte-identical (0 diff lines).
- `mutate_run2.txt` (`tests/release/pvl_mutate.py`): `MUTATE total=69 killed=69 survived=0 not_applied=0 retired=11
  equivalent=3 retired_fail=0`.
- `mutate_run1.txt`: the run before the kill cases CON-961 to CON-964, with 7 survivors.
- `verify_manifest.txt` (`scripts/run_full_suite.sh --verify-manifest`): one problem remains, the note of
  `tests/release/pvl_grid.py` differs from `config/full_suite_excluded.lock`. Accepting it needs a rostered reviewer
  id (`--accept-excluded-change <reviewer>`), which this fixer does not have. The census is in sync.

## Limits

- **Evidence class.** gate-logic only (section 11.4.289(C)(2)). It proves the checker decides correctly on the bodies
  listed. It does not prove that the provisional items on the real tracker are verified.
- **Scope.** The harnesses enumerate listed members and their cross product. No proof is claimed over every CommonMark
  or GFM document; see M-5 above.
- **Readers.** Rendering is done by two independent readers (markdown-it-py 3.0.0 and pandoc 3.11). A reader that
  renders differently from both (for example a forge's own Markdown renderer) is not tested.
- **The dependency.** Its presence is verified on this host only. Elsewhere the result is BLIND, which is safe, but it
  makes the checker unusable on a host without markdown-it-py 3.0.0.
- **False refusals.** They rose from 2877 to 4557 in pvl_blockstate. All are in the safe direction.
- **Equivalent mutants.** O48, O50 and O60 are argued equivalent, not proved. The search covers the listed bodies only.

## Open questions for the operator

1. **Lock note.** Accept the changed lock note of `tests/release/pvl_grid.py`
   (`--verify-manifest --accept-excluded-change <rostered id>`). The lander does this with a rostered id.
2. **Dependency.** Is markdown-it-py 3.0.0 available, or may it be installed, on the release host? If not, the checker
   reports BLIND there.
3. **False refusals.** Is the higher false-refusal count acceptable? The alternative is to allow some inline HTML
   again, which brings back the hiding class that review r6 found.
