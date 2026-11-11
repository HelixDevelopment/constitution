# CON-030 round 5: author report (review r4 K1 to K12, M1 to M6)

| Field | Value |
|---|---|
| Item | CON-030 (parent of CON-070, CON-146, CON-147, CON-148) |
| Round | 5, past R_max by the operator decision of 2026-11-10, relayed verbatim: "Keep running rounds until GO is reached!" (section 11.4.276(E)(3); recorded in the CON-030 description) |
| Base | review r4 bundle head 6a645831, then live main 90efceb8 merged in (merge 0c0de3b3), then live main 2e8cfb90 merged in (merge fed5c780) |
| Commits | a14824bd (round-4 leftovers, K7), 0c0de3b3 (merge of main 90efceb8, K5), c74e3554 (engine, tests, mutation table, guide), ede6686e (tracker on 90efceb8, class sweep), fed5c780 (merge of main 2e8cfb90), baacd4fc (tracker re-applied on 2e8cfb90, ids re-minted), c34fe4b5 (K1b fixture), and the commit that adds this report |
| Author | Claude Opus 5.5 subagent; effort not settable or readable on this dispatch path (section 11.4.231(F.2)) |

## What changed, by finding

- **K7.** The round-4 author report (mutation section filled from the author's logs: two runs, 150 of 150
  killed each), the widened round-4 class sweep, the round-4 CON-109 entry and a copy of review r4 are committed
  first (a14824bd).
- **K5 (merge of live main).** Main's WIT-C02 fingerprint of the generated command sets is the third field of the
  structured `QuickIdent` (heads, status, gen). Unknown stays `None` (main used an in-band `?` inside a text
  identity); `ident_unknown()` checks `gen` and keeps the root-status `None` case; `gen_fingerprint` frames every
  record with `hrec()`, feeds names and link targets as file-system bytes and returns `None` on `OSError`. Main's
  text version raised `UnicodeEncodeError` on a name that is not UTF-8 (RED on main's engine, GREEN on the merged
  engine: `k5_nonutf8_red_green.txt`, sha256 0d91f0ee...). Main's tracker files were taken and the CON-030 work
  re-applied through the engine (K6 below).
- **K1 (markers found by substring).** `guide_parse()` finds the census block by whole marker LINES; a quoted
  marker is text. Two begin or end lines, an end before the begin, a missing end and a marker line with spaces
  around it are refused (exit 3, nothing written). The rewrite (`replace_lines()`) copies every byte outside the
  block unchanged (a CRLF line end and a byte that is not UTF-8 are kept); round 4 re-joined decoded lines.
  The guide reader in the lint is now `guide_parse`.
- **K2.** `--sync-guide` returns exit 3 with `RESULT: GUIDE-NOT-SYNCED` and the reason when it cannot rewrite;
  with no census block it says so and writes nothing.
- **K3.** `esc_out()` does the surrogate round trip first and escapes after it.
- **K9.** `--verify-manifest` runs `plan()` in both modes, so a manifest that a run refuses is not `MANIFEST-OK`.
- **K12.** `--generate-manifest` (write or print) refuses on any census problem: it names each, prints
  `RESULT: MANIFEST-NOT-GENERATED` and exits 3.
- **K4 (outside the class).** Not fixed: putting variable values into the printed context hash is a credential
  question that needs a decision. Registered as **CON-148** and stated in the guide (resume section).
- **K6.** Re-minted at the live next free id, never reused (section 11.4.214). The first re-mint (commit
  ede6686e) used the next free id of main 90efceb8 (CON-116 to CON-118); main 2e8cfb90 then took those ids for
  other items (its next free id is CON-146), so the items were re-minted again after the second merge:

  | First id | Id in ede6686e | Final id | Item |
  |---|---|---|---|
  | CON-108 (6a645831) | CON-116 | CON-146 | review r3 H4, ignored files inside submodules not hashed |
  | CON-109 (a14824bd) | CON-117 | CON-147 | tree_ident hashes split with splitlines(); retyped Task to Bug (K11) |
  | (new) | CON-118 | CON-148 | review r4 K4, resume context omits --timeout and --env-extra |
  | CON-070 | CON-070 | CON-070 | kept: main 2e8cfb90 names it reserved for the CON-030 class item and no main item holds it |

  Each re-minted item's description carries its id history. Vehicle commits that name the old ids are not
  rewritten (section 11.4.113).
- **K8, K10, K11.** Guide revision 10 with the round-5 status; the lint limit names a bare `open(...)`, the
  method calls and the five readers; CON-030 is In progress, CON-147 is a Bug.
- **M1, M2, M5, M6 (reviewer mutants RX1, RX2, RX5, RX6 that survived round 4).** Adopted verbatim with killing
  tests: CR in a TOPOLOGY line on stderr (RX1), a NEL in the guide must not read as current (RX2), every
  summary.txt line is a whole terminal line (RX5), NEL and LS names refused by the census (RX6). RX3, RX4, RX7
  are added as rows; RX8 and H3d are re-anchored to the decode-first `esc_out`.

## RED and GREEN

| Run | Engine | Tests | Result | Log sha256 |
|---|---|---|---|---|
| merge | merged engine before the round-5 fixes | merge-state tests | passed=364 failed=0 | 6d25beab... |
| RED | merged engine before the round-5 fixes | round-5 tests | passed=405 failed=34 | c27a19a3... |
| GREEN | c74e3554 (before the 2e8cfb90 merge) | round-5 tests | passed=440 failed=0 | (log st_r5green2.log) |
| GREEN | baacd4fc (after the 2e8cfb90 merge) | round-5 tests plus main's CON-047 tests | passed=454 failed=0 | 2d082f9d... |
| GREEN | c34fe4b5 (K1b fixture added) | the same plus the `nearplus` case | passed=461 failed=0 | 16f59a95... |

The 34 RED failures are all round-5 checks: K1 (18), K2 (3), K3 (1), K12 (8), K9 (2) and the M1 case (2; the
fixture was then corrected: `git add -A` had staged the gitlink as deleted, so the RED there was the fixture's,
not the engine's; the corrected case runs in the GREEN row). The M1, M2, M5 and M6 checks pass on the
pre-fix engine, as expected: the code they guard already existed; their RED is the reviewer mutants, shown in the
mutation run. The first merge run reported 8 failures whose log shows the self-test's own mktemp directory losing
files mid-run (`cannot change to .../good`); the cause is UNKNOWN; the re-run of the identical files passed.

Real tree, before the 2e8cfb90 merge: `--sync-guide` rc 0, `--verify-manifest` `MANIFEST-OK` (census total 866);
`--list` and `--list --include-heavy` of main 90efceb8 and of that head byte-identical (sha256 63f7ac30..., 334 and
532 RUN lines). Main 90efceb8's engine reads the guide as stale, because the guide quotes a marker in prose: the K1
defect, shown on the real file.

Real tree, this head (after the 2e8cfb90 merge): `--sync-guide` rc 0, nothing rewritten (census total 869, the same
as main's line); `--verify-manifest` rc 0 `MANIFEST-OK` (log sha256 97010e5e...); main's new `--check-known-open`
rc 0 `KNOWN-OPEN` (two CON-047 rows open).

Merge 2e8cfb90 (section 11.4.211): conflicts only in the tracker files (main's taken, then re-applied through the
workable-items engine: validate OK, 147 items, DB and Markdown in sync) and in the mutation table (union: main's
F47a-F47c rows and header sentence, the vehicle's round-5 rows). The engine, wrapper, self-test and guide merged
without conflict. One stale anchor found by checking every row against the merged engine: M27 occurred 0 times,
because main's CON-047 change rewrote `match_known`; this is also true on main 2e8cfb90 itself, so main's own
mutation table has a dead row. M27 is re-anchored to the same block with the same mutant. After the re-anchor all
177 rows occur exactly once.

## Mutation run

The full table (177 rows, about 7 minutes per mutant, run one at a time) was not run in this round. Two runs,
evidence in `con030_r5_mutation_after_merge.txt`:

- **Run 1**, a copy of baacd4fc (after the 2e8cfb90 merge): the round-5 rows RX1-RX8, GU, GN, GC, K1a-K1e, K2n,
  K12m, K9m, plus G4, RMb, the re-anchored M27 and main's F47a-F47c. Baseline ok; 24 of 25 killed; **K1b
  survived** (log sha256 09690649...).
- **K1b fix.** On the `space` fixture the begin line is missing anyway, so the block-count refusal fired in place of
  the near-marker rule. The new `nearplus` fixture holds a valid block and an indented end marker, so only the
  near-marker rule refuses; both cases check the reason text (c34fe4b5).
- **Run 2**, a copy of c34fe4b5: K1b killed (6 failing checks; log sha256 1c1516a4...).

Killed before the 2e8cfb90 merge (copy of c74e3554, run stopped for the merge): H3d, RW2, RW3, G1, G2, G3. The engine
code these rows mutate was not changed by the merge; they were not re-run after it.

## Mechanisms added in round 4, each with its fixture and paired mutant

| Mechanism (round 4) | Fixture | Paired mutant(s) |
|---|---|---|
| `gov_lines()` reads every governance file, LF only, refuses line breakers | H2 tests (manifest, table, lock, roster) | Q5 Q5k Q5x H2a H2b |
| CRLF tolerance in `gov_lines()` | Q5c fixture | Q5c |
| the guide read through `gov_lines()` (refused character reported) | r5 M2 (NEL in the guide) | RX2 |
| the roster reader names nobody on a refused line | round-4 roster tests | RX3 |
| structured unit key; `plan()` refuses one key or one display id twice | H1 tests | H1a-H1d RW6 RX4 RX7 |
| the same refusal in `--verify-manifest` (new in round 5) | r5 K9 (H1 fixture) | K9m |
| `esc_out()` on stdout | H3 tests | H3a |
| `esc_out()` on stderr | r5 M1 (CR in a TOPOLOGY line) | RX1 |
| `esc_out()` on summary.txt; the terminal summary written line by line | H3 tests; r5 M5 | H3b; RX5 |
| the escape itself and its round trip | H3 tests; r5 K3 unit probe | H3d; RX8 |
| census refuses line-breaker names | H3 tests; r5 M6 (NEL, LS) | H3c; RX6 |
| `--generate-manifest` refuses census problems (round 5) | r5 K12 | K12m |
| guide markers as whole lines, byte-exact rewrite (round 5) | r5 K1 cases | K1a-K1e |
| `--sync-guide` fails on what it cannot rewrite (round 5) | r5 K2 | K2n |
| the io lint | its own positive control and mutant probes | (the lint is the test) |
| merged gen fingerprint: unknown, bytes names, content record | r5 K5 cases | GU GN GC G1-G4 |

Reasoned EQUIVALENT, not claimed killed: K2m (drop the re-check after the rewrite; `guide_check(fix=True)` already
returns every problem it cannot fix). The after-unit `ident_unknown(qid)` half: a value unknown after a unit and
unknown before it is already caught by the before-unit check; a value that became unknown is a change caught by
`qid != qid0`. Reasoned, not tested.

## Class sweep (section 11.4.276(C)): shape D, markers and delimiters found by substring

`con030_class_sweep_r5.py` adds shape D to the round-4 sweep (a call of `index`, `find`, `rfind`, `count`,
`startswith`, `endswith`, `partition`, `rpartition`, `split`, `replace`, `strip` and similar, or an `in` test,
whose needle is a literal or an UPPER_CASE name). Controls pass on both engines (positive needle `GUIDE_BEGIN`,
negative needle absent). Pre-fix engine D=101, this head D=100. Every site was read by hand:

| Sites | Class |
|---|---|
| the round-4 `text.index(GUIDE_BEGIN)` / `find(GUIDE_END)` | **the K1 defect**, fixed (whole-line match) |
| shell model (lines 61-367, 777-1250) | the shell tokenizer's own scanning of script text; not a governance marker |
| `gov_lines`, `sub_paths`, `ls-files -s -z` parsing, `split("\0")`, `partition("\t")` | structural: a field split on a NUL or TAB record, never a substring search |
| manifest, table, lock and roster readers (`startswith("#")`, `split("\t")`, `startswith("# accepted ")`, `startswith("override:")`, `startswith("reason:")`) | anchored at the start of a line or of a field already split on TAB |
| `"--quick" not in read_text(...)` (runall-quick) | a precondition only; the model run with `--quick` decides (fail closed); a comment holding `--quick` cannot make a heavy member pass |
| `"160000 " in git ls-files -s` (tree hash) | conservative: a false match only adds a submodule record; a real gitlink line always starts with `160000 ` |
| submodule status `rfind(" (")` | guarded by the known-path set (round 3) |
| `write_manifest` `replace("\t", " ")` | unreachable: cells come from TAB-split rows or census names, and a TAB name is a census problem that now stops generation (K12) |
| parser, status words, `/fixtures/` containment, `/proc` environ, results tail | output parsing of suites (by design approximate, guide Limits), containment tests on paths, or record framing |

The `--sync-guide`, `--generate-manifest` and `--write` paths were read for the K2 shape (a write reported that
did not happen): both now fail with a RESULT line; `write_manifest` and `replace_lines` write to a temp file and
rename it.

## Honest limits

- K4 is open (CON-148); the resume context still omits `--timeout` and `--env-extra` values.
- H4 is open (CON-146), CON-147 is open.
- The full mutation table (177 rows) was not run; 31 rows were run (25 after the merge, 6 before it), see above.
- Main 2e8cfb90's own mutation table has a dead row (M27, anchor occurs 0 times in main's engine); fixed on this
  vehicle by re-anchoring, not reported to main separately.
- The cause of the one lost-files self-test run after the first merge is UNKNOWN.
- Independent review of round 5 is owed (section 11.4.142, on the section 11.4.209 substrate).
