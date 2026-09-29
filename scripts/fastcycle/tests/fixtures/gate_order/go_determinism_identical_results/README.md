# go_determinism_identical_results (determinism)

Uses `../_shared/affected.json` and `../_shared/history/prebuild_sections.tsv`
directly. Runs `gate_runner.sh` TWICE against the identical inputs:

1. WITH `--order history-cost`
2. WITHOUT the `--order` flag (natural/declared section order)

Per contract AS-013: "ordering never removes a member and the final
verdict set is identical with and without ordering" (also the literal
task-text claim, tasks.md T054: "the final verdict set is identical with
and without ordering").

`expected.json` asserts the `results` array (sorted by `gate_id` per the
`verdicts/v1` output schema, C-002/C-003 determinism) is BYTE-IDENTICAL
between the two runs — same 4 gate_ids, same 4 verdicts (a=PASS, b=PASS,
c=FAIL, d=PASS) — even though the two runs' `execution_order` fields (per
this fixture set's own design note, see `../go_ordered_planted_fail_first/`)
are expected to DIFFER (ordered run executes c first; unordered run
executes members in declared section order a, b, d, c).
