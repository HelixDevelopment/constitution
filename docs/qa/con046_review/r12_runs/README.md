# CON-046 round 12: fixer evidence

| Field | Value |
|---|---|
| Item | CON-046, PROVISIONAL, gate-logic class (§11.4.289(C)(2)); no live or verified claim |
| Review fixed | `review_con046_r11.md` (sha256 `1a537247…`), findings F1 to F5 |
| Source commit | `892aa4ea` (parent `ce139483`); the evidence commit follows it |
| Gate and hook | byte-identical to `0aaf3f95`, where the round-11 screens ran (blob `78bbdc53…` gate, `4cf5a1b0…` hook) |
| Author | fixer subagent, Opus 5.5; effort not reported by the dispatch path |

## What changed in the source (and what did not)

- `cm_submodule_pin_not_downgraded_mutation_test.sh`: two AUTHNORM fixtures (fields 7 and 8) inserted before the
  positive control; the seven reviewer mutants RVR11-01..07 inserted by the reviewer's own `add_rv_mutants.py`, applied
  unchanged (the result is byte-identical to the RED copy, `cmp` checked); `want` changes only in AUTHNORM
  (`1,1,1,1,1,1,0` -> `1,1,1,1,1,1,1,1,0`); a header paragraph. No other line changed (`git diff -U0`).
- `cm_submodule_pin_not_downgraded_members.py`: a NORM kind. `cm_submodule_pin_not_downgraded_members.tsv`: 5 rows
  added, the 136 earlier rows byte-identical (0 removed lines in the diff).
- `cm_submodule_pin_not_downgraded_inventory.tsv`: the seven reviewer mutants named in the rows of their anchors
  (I070, I083, I092e, I137, I036, I081); I070's reason text extended.
- Unchanged (`git diff --exit-code 0aaf3f95 892aa4ea`): the gate, the hook, `_sites.py`, `_sites.tsv`,
  `_members_eq.tsv`, `_probes/`.

## Which earlier screen results stay valid, and why

A fixture's exit code is a function of (fixture repo state, gate text, environment). `waive` overwrites the waiver file
and stages it, nothing is committed, so the two new fixtures do not change the state any other fixture sees. For every
mutant M, its round-12 vector restricted to the round-11 fixtures is therefore its round-11 vector, and the round-12
`want` restricted the same way is the round-11 `want`. So every mutant the three round-11 screens killed is still
killed, and its fail directions can only grow (the dynamic lint needs a subset). What CAN change: (a) the 26 survivors
whose equivalence is claimed (17 proofs and 9 generated members), because a new fixture could kill one; (b) the new
mutants. Those are the "targeted set", run three times (below). The full suite also ran twice on 2026-11-15
as direct evidence, not only the argument; the guard refused a third run that day (see below).

## F1: RED, GREEN and the normalisation class

- RED (`red_r11test_rvr11.log`): the round-11 suite plus the reviewer's mutants, without the new fixtures, run with
  `MUT_ONLY=^RVR11-0[12]`: `BAD mutant RVR11-01-outer-nfc-dropped SURVIVED`, the same for RVR11-02, rc 1.
- Reviewer e2e scripts (`rv01_e2e.py`, `rv02_e2e.py`, unchanged) run three times each against the real gate and against
  the two mutant gates (`e2e_rv0[12]_run[123].txt`): every run real rc 1 ("producer cannot self-waive"), mutant rc 0,
  both `ops` controls rc 0. The rc columns are identical across the three runs (the SHAs differ, they are fresh repos).
- GREEN: see "Targeted set" below.
- Class census (`norm_census.py`, output `norm_census.txt`, rc 0): 20 tokens in four classes, each token needled on its
  own line, a fabricated line gives 0 hits, the gate's `.casefold()` is found in place. Hits in the gate and hook:
  class N (python normalisation and casing) 3 members on line 208 (two `normalize`, one `casefold`) and 2 on line 209
  (the two `f(..)` operands of `==`); class E 1 (`decode("utf-8")`, line 204); class L 4 (bash `=~` ranges on lines
  190, 191, 257, 260); class B 0. Every class-N member has exactly one generated NORM mutant. Instrument mutants of the
  census: NORM kind removed from the generator -> rc 1 (MISMATCH); `f`-operand rule removed -> rc 1; one needle broken
  -> rc 2 (BLIND) (`census_mut_*.txt`).
- Class E has no NORM mutant: its one member (the `decode("utf-8")` split, line 204) is already a hand row (I063,
  `idpy-split-wrong`), and a non-UTF-8 authoriser byte is the `badutf8` fixture whose python failure is the I133 site
  (`site-pyfail-aborts`, SITEUTF8).

## New finding N1 (source-defect, not fixed in this round): class L depends on the caller's locale

The four bash `=~` bracket ranges (`[A-Z]`, `[A-Z0-9]`, `[0-9]`) are collation-dependent in bash. Measured with
`locale_probe.py` against the real gate, three runs, identical (`locale_probe_run[123].txt`):

| case | C.UTF-8 rc | en_US.UTF-8 rc |
|---|---|---|
| item `CON-046` (control) | 0 | 0 |
| item `CON-²³¹` (superscript digits) | 1 | **0** (waived) |
| `item_prefix=AB` (control) | 0 | 0 |
| `item_prefix=ÀB` | 1 | **0** (accepted) |
| `max_waiver_days=30` (control) | 0 | 0 |
| `max_waiver_days=¹30` | 1 | 1 |
| expiry with superscript year | 1 | 1 |

So the item-id and item-prefix checks accept non-ASCII characters under a common operator locale. The days and expiry
sites are not affected (the `-le` test and the `date` round trip refuse). This is not part of the review's F1 and it
needs a GATE change (for example `LC_ALL=C` around the checks, or explicit ASCII classes), which would invalidate all
three screens and the 26 equivalence proofs. Three new full screens do not fit on one calendar day together with this
round's work, so it is NOT fixed here. It is reported as a new tracked finding for round 13, with a RED fixture
(`locale_probe.py`) ready. Nothing in this round claims class L covered.

## F2 to F5

- F2: `r11_runs/drive.log` gets one appended ERRATUM line (the prefix before it still hashes to the old
  `4f24bd0e…`, so the change is append-only); `r11_runs/SHA256SUMS` updated. No rerun was faked. The round-12 drive
  (`drive12.sh`) passes no guard input by hand: `longest` is the longest screen of the same drive.
- F3: the round-11 count is 484 mutants + 2 self-tests (date skew, resource fault), reported so here and in the CON-046
  description. The suite's own summary line still prints the sum.
- F4: see "Resource pair" below.
- F5: landing on `main` conflicts in four derived files (`docs/Issues.md`, `docs/Issues_Summary.md`, the census line
  of `docs/guides/full_suite_runner_guide.md`, `docs/workable_items.db`). The lander regenerates them with the engine
  (`sync db-to-md`, `--sync-guide`) after the merge; the DB is never merged by hand.

## Targeted set: three runs (2026-11-15, head 892aa4ea, clean tree, SUITE_NOW 2026-11-15T12:00:00Z)

`tools/targeted.sh` ran with MUT_JOBS 3 in its own scope, TasksMax 2000. The set covers:

- the 7 RVR11 mutants;
- the 5 new NORM members;
- every equivalence claim (17 proofs and the 9 generated survivors);
- the two self-tests;
- the round-11 killers for the normalisation and the self-authoriser.

Each of the three runs ended with:

- `mutants: 48 (killed 20, survived 0, equivalent-with-proof 26, inconclusive 0)`;
- rc 0;
- 0 findings in both lints;
- `member ledger current: 141 generated members, 141 viable`.

| run | start | end | pids.peak | pids.events |
|---|---|---|---|---|
| 1 | 10:36:34 | 12:18:35 | 48 | 0 |
| 2 | 12:18:35 | 13:56:42 | 47 | 0 |
| 3 | 13:56:42 | 15:23:33 | 43 | 0 |

The result lines of the three logs are 73 lines once the pid counters are removed. They hash to the same sha256 in all
three runs: `82860cba…`.

## Full screens (2026-11-15, head 892aa4ea, the same injected clock)

`tools/drive12.sh` ran with MUT_JOBS 6 and TasksMax 2000. Its 1.5x guard takes no input passed by hand.

| screen | start | end | result | pids.peak |
|---|---|---|---|---|
| 1 | 10:41:34 | 15:32:26 | 498 entries (496 mutants + 2 self-tests): killed 470, survived 0, equivalent-with-proof 26, inconclusive 0, rc 0 | 66 |
| 2 | 15:32:26 | 19:35:10 | same counts, rc 0 | 64 |
| 3 | not run | - | REFUSED by the guard at 19:35:10: 15,590 s were left, and 1.5 x 17,452 s were needed | - |

The two logs differ only in their scope header line.

Screen 3 did not run. This round therefore does NOT meet the rule of three full-suite screens on one calendar day.

The round rests instead on the evidence stated above:

- the gate and the hook are byte-identical to the head that round 11 screened;
- the change only adds fixtures and mutants;
- every mutant whose result the change can affect is in the targeted set, which ran three times with identical
  results.

The two full screens are extra, direct evidence for the same claim. The reviewer and the operator decide whether it is
enough. A third full screen needs a calendar day of its own.

## Resource pair (F4)

The round-11 resource failures came from the shared session scope, not from the suite. That scope had pids.max 6000,
and a foreign fork storm ran in it.

Measured here, each run in its own scope:

- MUT_JOBS 6 peaks at 64 to 66 pids.
- MUT_JOBS 3 peaks at 43 to 48 pids.
- pids.events stays 0 in every run.

The recommended pair is a dedicated scope with TasksMax 2000 and MUT_JOBS 6 or less. That leaves about 30x headroom
under TasksMax. The ancestor limits are app.slice 16384 and user-1000.slice 40000.

The resource self-test still reads 480 old events in the ancestors. The count went 480 -> 480, so no new event
happened.

## Evidence files

See `SHA256SUMS`. Every figure above is copied from the logs; nothing is predicted.
