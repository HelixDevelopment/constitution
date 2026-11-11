# resolve1 excluded-set change: corrected proposal (fixu round 2, review P-1 and P-2)

Status: APPLIED in e6b16598 (lock 53 -> 55 rows); kept unchanged below as the record (section 11.4.215). Original status line: PROPOSAL. Not applied in any tracked tree. `config/full_suite_excluded.lock` is not edited by hand,
and the acceptance is the operator's act (a rostered reviewer). This replaces
`scratchpad/fixu/resolve1_lock_diff_PROPOSED.txt`.

## What changes

In `config/full_suite_manifest.tsv`, two rows change class from `member` to `excluded`:

```
scripts/codegraph/tests/test_resolve1_dump.py	py	excluded	-	-	-	override: reason: tool: argv-driven helper (usage: test_resolve1_dump.py <db> <outprefix>) invoked by test_resolve1.sh and test_resolve2.sh, which check its output; with no arguments it raises IndexError, so a standalone run is a false FAIL; not a test
scripts/codegraph/tests/test_resolve1_fixture.py	py	excluded	-	-	-	override: reason: tool: argv-driven fixture generator (usage: test_resolve1_fixture.py <outdir> <n_filler> <n_probe> [--mixed|--novue]) invoked by test_resolve1.sh; with no arguments it raises IndexError, so a standalone run is a false FAIL; not a test
```

## Procedure (corrected)

1. Replace the two manifest rows above.
2. `bash scripts/run_full_suite.sh --sync-guide`. P-1: this step was missing. Without it, `--verify-manifest`
   reports two problems: the stale guide census block (py/excluded 22 -> 24, py/member 26 -> 24) and the
   lock difference.
3. `bash scripts/run_full_suite.sh --verify-manifest` must now report exactly one problem, the excluded set
   difference (added the two rows, removed none).
4. The operator runs `bash scripts/run_full_suite.sh --verify-manifest --accept-excluded-change <rostered id>`.
   P-2: `excl_accept` rewrites the whole lock body from the manifest and appends one `# accepted` line, so
   no lock row is written by hand. The row count goes 52 -> 54 (the head lock and manifest both hold 52;
   the earlier "57 -> 59" was wrong).
5. `--verify-manifest` gives `RESULT: MANIFEST-OK`.

## Rehearsal (disposable clone, measured 2026-11-06)

A local clone of the fixu2 head (74f1f128), with its origin removed and never pushed:

- After step 1: rc 3, two problems (stale guide, lock difference). `ev/prop_verify1.out`
- After step 2: rc 3, one problem (lock difference only). `ev/prop_sync.out`, `ev/prop_verify2.out`
- Step 4 with the real roster refused, as it should, for an uncommitted roster. With a roster entry
  `rehearsal@example.invalid` committed in the clone only (labelled REHEARSAL ONLY): rc 0, the lock gained
  `test_resolve1_dump.py b936cad3425d32bc` and `test_resolve1_fixture.py 949a083d5d9e16cd` in sorted
  position, and `# accepted ... accepted_by=rehearsal@example.invalid ... rows=54`. `ev/prop_accept_rehearsal.out`
- Step 5: `RESULT: MANIFEST-OK`, census total 855, py/excluded=24.

The rehearsal identity is not an operator and its acceptance has no standing; it only shows the
steps and the row count.
