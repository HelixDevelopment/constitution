# as_selfchange (self-change, AS-010a, tasks.md T053 line item 4)

The changed path is `gates/gate_gamma.sh` itself -- gate_gamma's OWN script
file, not any of its declared `observed_inputs` (`src/shared_lib.sh`).
AS-010a: "every gate whose own script changed is a member" -- this is a
SEPARATE selection rule from the observed-inputs match (AS-011), so the
tool must special-case "did the gate's own script path change" independent
of its declared input list. gate_gamma must be selected even though the
changed path never appears in gate_gamma's `observed_inputs` array.
