# CON-402 audit fallout, round 3: evidence

| Field | Value |
|---|---|
| Items | CON-450 (F1 safepath census, structural round), CON-451 (F2/F3 r15 layer test, R2-6), CON-251 (F4 evidence files, R2-3 / R2-8) |
| Base | round-2 vehicle head 7d0fb360 rebuilt on origin/main ebd8818c (merge commit with a Roadmap-Item trailer, R2-7) |
| Review answered | REVIEW_con402_fallout_r2.md (R2-1 to R2-8) |
| Evidence class | gate-logic (hermetic tests of a census and of a test layer), PROVISIONAL |
| Oracle | GNU bash 5.3.9 |
| Created | 2026-11-17 |

Host paths in copied logs are normalised to `<P>` (this fixer's work directory) and `<S>` (other scratch paths).
`SHA256SUMS` covers every file in this directory.

## F1 (CON-450): the deny-lists are replaced by class-exhaustive rules (section 11.4.276(E))

Class named by the review (R2-1, R2-2): "the canonical loop, a trusted function or another function of the file means
something else than the census reads". Rules (census docstring, `git-env` paragraph):

1. Preamble allow-list: before the canonical line only a line-1 `#!`, blank lines and comments. Everything that could
   run before the loop (wrappers such as `command` / `builtin`, DEBUG / ERR traps, `set`, attribute declarations in
   any spelling) is refused by construction. The round-2 blockers stay as a second layer (RVM1 / RVM2 are killed by
   after-the-line rows).
2. Unset allow-list: an operand that can name a function must be a plain identifier after quote removal and may name
   neither a trusted function nor another function of the file, except a scoped helper (the real `_sc_one`).
3. A wrapper never runs a file function; a function defined in a trap action or a `-c` program is refused; a trusted
   function defined twice is refused.

Measurements:

- `f1/class_new_census_run1.txt`, `run2.txt`: 85 members (wrappers W*, traps T*, unset spellings U*, line forms L*,
  extra X*, each also inserted after the line), measured in bash (does the proved `wt_path` / `_FC_TMPDIR` change, is
  `_fc_safe` or `run_gate_once` gone or replaced by a same-named program on PATH?) and against the census.
  New census: escapes 0, controls hold (real file accepted, a literal `unset wt_path` refused, the round-1 S1 shape
  refused); run 1 and run 2 give identical verdicts. The instrument script is `f1/r3_class.py.txt`.
- `f1/class_round2_census_run2.txt`: the round-2 census (sha256 in `f1/census_round2.sha256.txt`, equal to
  62362649's file): escapes 30. `f1/class_round2_census_run1_BLIND.txt` is a first run in which the instrument did not
  pass `--sup`; the census exited 2 for every member and the instrument reported BLIND (no verdict), so the
  instrument was fixed and run again.
- `f1/f1_red_round2_census.log`: the F1 suite against the round-2 census: 23 behaviour rows and 14 new mutant anchors
  fail (pass=69 fail=37, RED). `f1/f1_green_run1.log`: pass=106 fail=0; every census mutant KILLED, including the
  reviewer's RVM1 and RVM2 verbatim and RVM4 (`-f`-only).

## FU-1 (R2-5) and the boundary

`fu1/`: `unset -v _ge_v` follows an inherited nameref and unsets the proved variable; `unset -n _ge_v` alone keeps an
inherited value-less `declare -l`; the pair `unset -n _ge_v; unset -v _ge_v` keeps both. An inherited DEBUG trap or an
exported `BASH_FUNC_unset%%` defeats every prefix (`bash_boundary_probes.txt`: the exported function shadows the
builtin; IFS is not inherited from the environment; quoted or escaped function names are refused in a definition, so
a redefinition cannot be spelled around rule 3). See `followups.md`.

## CON-451 (R2-6): one vector, asserted in the child

`test_custody_sweep_r15_regression.sh`: both ME1 legs read `ME1_VECTOR`, and each layer check asserts that the vector
is in the case's environment. `r26/tmr26_vector_dropped_func_only.log` (diff in `r26/tmr26.diff.txt`): with the
export dropped from the func-only leg only, the suite reports `NOT ok layer check ME1_func_only: the inherited vector
... is not in the case's environment` and exits 1.

## CON-251 (R2-3, R2-8)

- `r23/gitenv_RED_before_rename.txt`: the git-env census on the round-2 tree, rc=1, `unclassified=20` (the
  `*.log.norm` files). The files are renamed to `*.log.norm.txt` (content unchanged, `../con402_fallout_r2/SHA256SUMS`
  updated); `r23/gitenv_after_rename_worktree.txt`: rc=0. The PASS on the final committed tree is recorded in the
  hand-back (a file in the tree cannot carry the census result of the tree that contains it).
- R2-8: the FU-5 text is restated in `followups.md` with the measured sequence.

## Double runs

`runs/summary.txt`: the ten suites twice and the gates twice on a clean worktree of 66fb5655 (all rc=0; every suite run1 == run2 after normalisation, `test_fc_safepath_v4r15` and `test_custody_sweep_r15_regression` after also normalising commit ids and mktemp suffixes, files `*.norm_volatile.txt`; git-env census PASS unscrubbed=0; safepath violations=0; ratchet PASS; index fresh; validate and diff OK with 491 items; guard table ok; sync-guide leaves the tree clean).

## Follow-ups

`followups.md` (supersedes round 2 for FU-1, FU-2, FU-5).
