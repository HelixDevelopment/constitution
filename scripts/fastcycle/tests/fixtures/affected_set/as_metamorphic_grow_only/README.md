# as_metamorphic_grow_only (metamorphic, tasks.md T053 line item 3)

Not a fixed-input/fixed-output fixture like the others -- this one drives
the REAL tool TWICE (run A, run B) and checks a RELATION between the two
outputs rather than a single golden output. Run A changes only
`src/alpha.sh`; run B changes that SAME path plus an unrelated one
(`src/beta.sh`). The selected member set for run B must be a superset of (or
equal to) run A's -- adding an unrelated changed path must NEVER cause a
gate that was selected before to become skipped. This is the metamorphic
property tasks.md's T053 line names explicitly: "adding an unrelated changed
path never shrinks the selected set".
