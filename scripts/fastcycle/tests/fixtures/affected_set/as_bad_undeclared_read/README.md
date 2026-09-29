# as_bad_undeclared_read (golden-bad, AS-001 + AS-010)

`map_undeclared.json`'s `gate_undeclared` entry carries
`undeclared_reads: ["src/secret_extra.sh"]` -- a read
`gate_undeclared.sh` genuinely performs (see the shared gate script) but its
declaration never listed. AS-001: this marks `gate_undeclared`
`INPUTS_UNSOUND`, cache-ineligible, and always-run. AS-010 additionally
states "any gate is INPUTS_UNSOUND" is itself one of the unconditional
determinable=false triggers -- so this fixture's change (`src/alpha.sh`,
otherwise an ordinary single-component change) is STILL undeterminable
overall, and the full suite runs including `gate_undeclared` itself. This is
the strict, literal reading of AS-010's clause list (each condition is an
independent OR-trigger, not scoped to only the currently-changed paths).
