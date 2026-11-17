# CON-402 audit fallout, round 5: evidence

| Field | Value |
|---|---|
| Items | CON-450 (git-env census and safepath census: reviewer classes R4-1..R4-4), CON-451 (r15 layer check, reviewer mutant RC1), CON-251 (history note wording) |
| Base | round-4 head e3c5a558 (pull request #14) |
| Review answered | REVIEW.md of round 4 (R4-1 to R4-4, mutants GM1/GM3/GM4, SM1..SM8, RC1/RC3/RC4) |
| Evidence class | gate-logic (hermetic tests of two censuses, a differential test against the bash and Python interpreters, and a test layer), host-only, PROVISIONAL (section 11.4.289(I)) |
| Created | 2026-11-17 |

## CON-450: class fixed by comparing the census with the interpreter, not by one more spelling

Class (review round 4): text that bash or the Python interpreter runs differently from what the census reads.
- R4-1: a PEP 263 coding cookie (for example utf-7) changes how Python decodes the source. `git_env_class_census.py`
  (`hidden_mention_problem`) and `check_safepath_census.py` (`_py_read_as_interpreter`) refuse any cookie on lines 1-2
  other than utf-8 / ascii forms.
- R4-2: bash runs `$(...)` and backticks in the body of an UNQUOTED heredoc. `_sh_read_as_bash` refuses such a body line
  (quoted delimiters stay data).
- R4-3: a NUL anywhere in a shell/Python/JS file is UNSCRUBBED (bash drops it after line 1). Native executables are still
  recognised by magic bytes and stay in the binary bucket (inventory unchanged: 665 members, unscrubbed 0).
- R4-4: a backslash continuation followed by a `#; cmd` line is a joined word, not a comment. `_sh_logical` /
  `sh_continued` decide comments on the joined text and keep heredoc body lines as text.

Structural addition: `tests/test_git_env_census_differential.sh` executes a generated corpus under bash and Python
with a recording `git` shim and poisoned git variables; the census must never report HERMETIC (or no row) for a file
whose run was RAN-UNSCRUBBED, and must still clear some (it must not refuse everything). Result on the fixed census:
372 pass, 0 fail, 365 corpus files; on the round-4 census it fails (NUL, utf-7 cookie, continuation and
heredoc-comment rows). Manifest row added.

Real-tree runs: git-env census PASS members=665 hermetic=511 exempt=154 unscrubbed=0 (164 control-needle samples);
F1 suite `test_fc_safepath_gitenv_scrub.sh` pass=213 fail=0 (all new mutants KILLED).

Reviewer mutants: GM1 (`<` for `<=`), GM3 (extra shebang accepted) and GM4 (`lstrip().startswith("#")`) each turn the
census BLIND (rc 2), so they die; new needles added for each. SM1, SM3, SM4, SM5, SM6, SM8 are in the F1 MUTANTS table
and killed. GM2, GM6 and SM2: recorded as equivalent by the reviewer; NOT independently re-verified here (UNCONFIRMED).
Differential mutants: NUL skip restored (D2) killed (14 rows); continuation join disabled (D3) killed (4 rows); D1
(`sh_continued` always False) survives the differential and is killed by the direct code_lines needle.

## CON-451: reviewer mutant RC1

RC1 survived the round-4 r15 layer check (51 ok, 0 notok). The record is now written by the python3 process that runs the
tool in-process (runpy), with no exec chain or launcher between them. Real suite: 51 ok, 0 notok. Mutants against the new
suite: variant of RC1 (`env -u GIT_INDEX_FILE` before python3) killed; RC4 (record not written when unset) killed;
RC3 (round-4 copy) killed. NOT killed: a variant that pops the variable inside the same three-line recorder after the
record (RC1c, the harness mutating itself): it survives, recorded as a residual boundary, because a record taken after the
run is unusable (the tool edits its own os.environ; measured: 3 layer checks fail).

## CON-251: wording

Round 4 wrote "FIXED in round 4" for the censuses; the review showed that overstated. The note and `../con402_fallout_r4/followups.md`
now say "round-4 hardening, reopened". Follow-ups FU-6..FU-8 are in `followups.md` (no ids minted).

## Not claimed

Re-exporting a scrubbed variable after the scrub, names built at run time (`g\it`), inherited attributes (BASH_ENV),
and the other census-style gates of FU-6. PROVISIONAL: nothing here is a live product run.
