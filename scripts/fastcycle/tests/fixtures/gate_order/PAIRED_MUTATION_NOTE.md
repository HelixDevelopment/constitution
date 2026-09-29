# Paired-mutation obligation (task-text example / C-005) — documented, not implemented here

Task line (tasks.md T054, verbatim, mutation clause): the sibling design
brief for this class of task states the canonical mutation for ordering
logic as "reverse the order key". Per `contracts/common-conventions.md`
C-005: "Each tool also ships a paired §1.1 mutation of its own detection
logic that flips a golden-bad to exit 0; the meta-test asserts the
mutation is caught."

**This is T070's obligation, not T054's.** T054 (this RED test / this
fixture set) exists specifically because
`constitution/scripts/fastcycle/gates/gate_runner.sh` does not exist yet
(see the main test's absence-proof Section A) — there is no ordering logic
to mutate. Fabricating a premature mutation-test for code that does not
exist would itself be a §11.4.6 violation (asserting a fact about an
artefact's behaviour with nothing to observe).

**What T070's implementation must ship (named precisely, so this
obligation is traceable and not lost per §11.4.197):** T070's
implementation of `gate_runner.sh`'s `--order history-cost` sort MUST have
a paired `scripts/testing/meta_test_false_positive_proof.sh` mutation that
**reverses the sort direction** of the `historical_fail_rate / mean_cost`
ordering key — for example, changing the comparator from descending to
ascending (or negating the computed ratio before sorting) — and re-running
it against `go_ordered_planted_fail_first/` (this directory's own golden
fixture, whose `expected.json` says
`execution_order_first_gate_id: "gate_c_planted_fail"`) MUST observe the
mutated tool wrongly report `gate_a_reliable` (the LOWEST-ranked gate)
first instead — i.e. the golden test flips from PASS to FAIL under the
reversed key. The meta-test then asserts that mutation is caught (some
OTHER check — golden-fixture regression, or the mutation-detection harness
itself — FAILs when the reversal is applied), closing the loop C-005
requires.

This file is the durable record of that obligation so it is not silently
dropped between T054 (RED, this task) and T070 (GREEN implementation).
