# CON-402 audit fallout, round 2: evidence

| Field | Value |
|---|---|
| Items | CON-450 (F1 safepath census), CON-451 (F2/F3 layer tests), CON-251 (F4 kill ledger) |
| Base | round-1 bundle head 1f0dea79, merged with origin/main ebd8818c |
| Review answered | REVIEW_con402_fallout_f1_f4.md (F1-A, F1-B, F1-C, F1-E, F23-A, F23-B, F23-C, F4-A) |
| Evidence class | gate-logic (hermetic tests of a census, of test layers and of a generator), PROVISIONAL |
| Created | 2026-11-17 |

Host paths in the copied logs are normalised to `<P>`. `SHA256SUMS` covers every file in this directory.

## F1 (CON-450): the shell desugar is refused when `_ge_v` can carry an attribute

- `f1/enum_red.txt` / `f1/enum_green.txt`: a 35-member class instrument (attribute flags `-l -u -c -i -n`, the
  name spelled through backslash, quotes, `$''`, braces, globs, plus readonly / export / assign / printf -v /
  arithmetic / eval / alias / function `unset` / `enable -n` / mapfile and others), each member measured in bash
  (does the loop unset the proved `wt_path` or the function `_fc_safe`?) and against the census. Bundle-head census
  (sha256 in `f1/census_bundle_head.sha256`): 20 mismatches. Fixed census: 0. Control needles: the real file is
  accepted, an added `unset _FC_TMPDIR` is refused.
- `f1/reviewer_S1_S13.txt`: the reviewer's S1 and S13 inputs (sha256 verified): bundle-head census rc=0
  violations=0; fixed census rc=1 with the "NOT desugared" row; the real `baseline_replay.sh` rc=0 on both.
- `f1/f1test_red_bundle_census.log`: the round-2 test against the bundle-head census: 12 behaviour rows fail and the
  new census mutants cannot apply (RED). GREEN: `runs/` (pass=59 fail=0, twice, identical; every census mutant
  KILLED, including the review's surviving RM2, RM3 and RM6 and the unset-of-a-trusted-function mutant).
- `f1/gitenv_census_attr_probe.txt`: the file-scope git-env census already refuses an in-file `declare -l _ge_v`;
  the remaining exposure (a sourcing parent or BASH_ENV) is follow-up FU-1.

## F23 (CON-451): every layer measurement uses a fresh victim, with a polarity control

- `f23/tmr2_*.verdicts.txt`: the review's test-of-test shapes on the round-2 tests. Each removes the layer its
  check claims is load-bearing; each check now says NOT ok (tm1_r8, tm2_rv, tm3_rv, tm6_r15). tm2r_rv (the
  measurement order swapped) fails the scrub check and keeps the full-revert check ok: no order dependence.
- `f23/rv_subshell_counter_debug.txt`: the first round-2 rv fix used a counter incremented inside `$(...)`; it never
  advanced, so every call reused one repository. The new polarity control failed on it; replaced with `mktemp -d`.

## F4 (CON-251): the ledger records its topology class

- `f4/topology_probe.txt`: a TMPDIR under the scratch directory classes as `shared:` (a group-writable ancestor);
  the sweep ran on a directory whose whole ancestor chain is owner-only.
- `f4/sweep_owner_only.summary.log`: exit 0, 345 rows, control GREEN 460 checks across 13 suites.
- `f4/ledger_diff_vs_main.txt` (empty) and `f4/ledger_diff_vs_bundle.txt`: the three rows round 1 changed did NOT
  reproduce; every row equals origin/main's ledger again. Round 1 recorded no topology class, so the cause of its
  differences is UNKNOWN.
- `f4/guard_table.run*.log`: GT-REAL ok; GB12 (shared chain) and GB13 (no chain recorded) fail for their own reason.

## Double runs

`runs/summary.txt`: ten suites and seven gates, each twice, all rc=0, identical normalised verdicts and identical
gate outputs (manifest, git-env census, safepath census, ratchet 394/394, index fresh, workable-items validate and
diff).

## Follow-ups

`followups.md`.
