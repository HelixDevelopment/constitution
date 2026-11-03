# gate_env_census fixtures

Inputs for `scripts/gates/cm_gate_env_reads_allowlisted.sh` and its paired mutation test.

- `needle/` is the control needle the gate runs through the census on every run (11.4.273). It carries one read
  of every form the census must see, plus two negatives (an assigned-then-read variable and a fabricated name in
  single quotes) that it must not see.
- `golden_good/` and `golden_bad/` are templates. The mutation test copies `demo_gate.sh` to
  `scripts/gates/cm_demo.sh` and `allowlist.tsv` to `config/gate_env_allowlist.tsv` inside a `mktemp -d` root.
  They are not named `cm_*.sh` here so that no gate scanner treats them as gates.
