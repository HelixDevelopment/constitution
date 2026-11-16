# CON-046 round 14: fixer evidence

| Field | Value |
|---|---|
| Item | CON-046, PROVISIONAL, gate-logic class (§11.4.289(C)(2)); no live or verified claim |
| Review fixed | round-13 independent review (NO-GO on head `22c07d7b`), findings R13-1 to R13-8 |
| Base | `457ff31e` (merge of the round-13 vehicle `22c07d7b` onto main `65ebc179`) |
| Confusables table | unchanged, sha256 `e5afc46b542187fb7c2955fb172c14e56798fae316f826ac3c2ddb0e3c9ee74f` |
| Author | fresh structural fixer subagent, Opus 5.5; effort not reported by the dispatch path (UNKNOWN) |
| Corrections to round 13 | `ERRATUM_r13.md` (append-only; no earlier evidence file is edited, R13-8) |

## Findings and what was done

| Finding | Done | Evidence |
|---|---|---|
| R13-1 (RVR13-04 survives: the category-C check skipping the first character) | AUTHPOS14: 12 code points (Cf U+200B U+FEFF U+00AD U+202E, Co U+E000 U+F0000 U+10FFFD, Cn U+0378 U+FFFF U+E0FFF, Cc U+0001 U+007F), each at the start, middle and end of `release-mgr` (36 fixtures), all refused. A survey of 22 per-position, slice and predicate variants of the gate's own expression: every one killed by the 12-string AUTHPOS14 shape alone (`a.strip()` is equivalent because the same line refuses `a!=a.strip()`; measured over every C-category whitespace) | `tools/catpos14.py`, `catpos/catpos_new.txt`, `catpos/catpos_r13.txt` |
| R13-2 (`AIex` waived for `Alex`: casefold before the table) | The gate keeps the caseless skeleton f and also compares the case-preserving UTS #39 skeleton e = f(map(NFD(s))) fixpoint; the two are a union. The claim is not narrowed. Measured with the gate's own functions (`tools/gatefns14.py` loads them verbatim): single-code-point skeleton classes split by the relation 165 (round 13, review form) and 100 (round 13, NFKD form), 0 with the union; false refusals +12 of 38781 distinct name pairs (0.0309%; round 13 refused 4, round 14 refuses 16, e.g. ELIA/ELLA). Usable; header and this file state it | `tools/caseconf14.py`, `tools/falseref14.py`, `measure/caseconf14.txt`, `measure/falseref14.txt`; fixtures CASE14, QNFD14, FTWIN14 |
| R13-3 (U+2800 and blank-only authorisers waived) | U+2800 maps to nothing; a skeleton that is empty or only whitespace is refused (rc 3). 268 single code points (Lo 4, Mn 263, So 1). OPEN operator question in the gate header: other visible-blank glyphs with a non-empty skeleton (no mechanical rule identifies them; UNCONFIRMED) | `tools/blank14.py`, `catpos/blank_census.txt`; fixture BRAILLE14 |
| R13-4 (a broken HEAD read as unborn) | HEAD that is not a commit: BLIND (rc 2) unless HEAD names a ref that does not exist (the real unborn case). Loose ref and packed ref to a missing object, detached at a missing object, ref to a tree: all BLIND | fixture UNBORNBAD14 (UNBORN / UNBORN256 stay PASS) |
| R13-4 follow-on | The git-env census read the gate's `symbolic-ref -q HEAD` as a write. Narrowed: one name plus read flags is a read; a second argument, `-d` or `--delete` is a write. Six control needles; four mutants of the narrowing all make the census BLIND | `keepgreen/keepgreen_pre.txt` (RED), `census/summary.txt` |
| R13-5 (RVR13-01, 02, 05, 07, 09, 13, 15) | 01, 05, 13, 15 killed by ROUNDS14 / CONFDIR14 / FTWIN14; 02 (`range(3)`) equivalent with proof (fixpoint calls measured: at most 3 over 10.4M two-character strings; probe `pr_rounds14`, control `range(2)`); 07 and 09 equivalent with proof (`pr_loc13`, control: pin deleted) | targeted runs below |
| R13-6 (census needle `git merge x-base`) | needle added; the mutant `merge(?!.*base)` is BLIND | `census/summary.txt`, `census/red/` |
| R13-7 (norm_census traceback on a missing table) | BLIND, rc 2 | `norm/norm_census_missing_table_BLIND.txt`, RED `norm/norm_census_r13_missing_table_RED.txt`, GREEN `norm/norm_census_GREEN.txt` |
| R13-8 (in-place edits) | `ERRATUM_r13.md`; outer-k-dropped is a recorded equivalence (probe `pr_outerk14`, control RVR13-12) | this directory |

## RED before, GREEN after

| Check | RED (before) | GREEN (after) |
|---|---|---|
| Round-14 suite against the round-13 gate (`runs/red_r13gate.log`, sha256 `eeb61f59…5906`) | the classification vector differs on exactly four fixture keys: BRAILLE14 want `1,1,1,1,0` got `0,0,0,0,0` (R13-3); CASE14 want `1,1,1,1,1,1,1,1,0` got all 0 (R13-2); QNFD14 want `1` got `0` (R13-2); UNBORNBAD14 want `2/1` ×4 got `0/0` ×4 (R13-4); plus 15 lint findings (anchors and code lines the round-13 gate does not have) | the round-14 gate: vector equals want, lints clean (targeted runs below) |
| AUTHPOS14, FTWIN14, ROUNDS14, CONFDIR14 | not RED on the round-13 gate by design: they kill mutants (RVR13-04, RVR13-01/05/13/15), not a gate defect | the named reviewer mutants are killed in every targeted run |
| category-C position survey (`tools/catpos14.py`) | `catpos/catpos_r13.txt` | `catpos/catpos_new.txt`: all 22 variants killed by AUTHPOS14 |
| norm_census on a missing table (R13-7) | `norm/norm_census_r13_missing_table_RED.txt`: Python traceback (`FileNotFoundError`) | `norm/norm_census_missing_table_BLIND.txt`: BLIND rc 2; `norm/norm_census_GREEN.txt` on the real table |
| git-env census needle `git merge x-base` (R13-6) | `census/red/summary.txt`: the mutants `merge(?!.*base)` and `merge(?!-base)` both PASS (97 samples) | `census/summary.txt`: `merge(?!.*base)` BLIND; `merge(?!-)`, `merge` BLIND; the symbolic-ref narrowing mutants all BLIND |
| census on the round-14 gate before the narrowing (R13-4 follow-on) | `keepgreen/keepgreen_pre.txt`: FAIL, unscrubbed=1 (`symbolic-ref -q HEAD` read as a write) | `keepgreen/keepgreen_post.txt`: PASS, unscrubbed=0 |

Census mutant `merge(?!-base)` (the `\b` dropped) still PASSes after the change. It differs from the real regex only on `merge-base` followed by a word character. Recorded equivalence, not a kill: `census/merge_base_word_eq.txt` lists every git subcommand of git 2.53.0 starting with `merge` (positive control `^merge-base$` = 1, count of `^merge-base[A-Za-z0-9_]` = 0, negative control `^zzmerge` = 0). It is bounded to that git version (UNCONFIRMED for other versions; a later git adding such a subcommand would make it a real survivor).

## Targeted runs

PENDING

## Keep-green checks

`keepgreen/keepgreen_post.txt`, every check rc 0: git-env census PASS (members 660, unscrubbed 0, 104 control needles); CM-CONSTITUTION-INDEX-FRESH PASS; ledger ratchet unimplemented 394 = baseline 394; `--sync-guide` rc 0; `--verify-manifest` MANIFEST-OK; engine validate OK (382 items); engine diff in sync (382 items).
