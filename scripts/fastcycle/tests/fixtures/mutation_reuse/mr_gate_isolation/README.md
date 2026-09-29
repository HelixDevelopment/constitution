# mr_gate_isolation/ — cross-gate cache isolation (T057 case 1, "not others")

Every OTHER scenario under `fixtures/mutation_reuse/` uses a single
hardcoded gate id (`GATE-MR-DEMO`) and its own isolated scratch cache
directory, so none of them individually proves the "(not others)" half of
tasks.md T057's case 1: "changing one gate's input content re-runs THAT
gate's mutations (not others)". This directory closes that gap directly:
two DIFFERENT gates (`GATE-MR-ISO-A`, `GATE-MR-ISO-B`), each with its own
gate script + mutation patch (so their DEC-23 keys are genuinely distinct
-- confirmed by the RED test's Section B before any claim is made about
the real tool), are `put` into ONE SHARED cache directory. Gate A's
observed input is then flipped between put and get (expect MISS -- its
own mutations must re-run); gate B's inputs are left byte-identical in
that SAME shared cache directory (expect HIT -- its cached verdict must
remain servable, untouched by gate A's change). All four envelope JSON
files reuse the SAME real file/patch/script bytes (and their real
sha256 sums) as the sibling scenarios in this directory -- see
`../gate_script.sh` / `../gate_script_v2.sh` / `../mutation_patch.diff` /
`../mutation_patch_v2.diff` / `../observed_input.txt` /
`../observed_input_flipped.txt` -- so this scenario is non-vacuous by
construction, not by assertion.
