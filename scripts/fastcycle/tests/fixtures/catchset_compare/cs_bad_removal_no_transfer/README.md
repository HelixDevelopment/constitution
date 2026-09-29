# Fixture: cs_bad_removal_no_transfer (golden-bad)

Contract row 6: "remove gate G whose mutation no other gate catches |
golden-bad | `gate_audit.py transfer-proof` exit 1".

Exercises the OTHER tool named by the contract's Invocation section:
`gate_audit.py transfer-proof --gate <gate_id> --into <surviving_gate_id>`
(CS-005), not `catchset_compare.py compare`.

- `removal_request.json` names `g_extra` as the gate proposed for removal,
  with its own paired-mutation defect `D_extra`
  (`../_shared/patches/defect_d_extra_widget.sh`, drops `EXTRA_MARKER`).
- `surviving_config.json` lists `[g_marker, g_noop]` -- the gates that would
  remain if `g_extra` were removed.
- The RED test independently verifies (by actually executing `g_marker` and
  `g_noop` against a `D_extra`-mutated disposable copy) that NEITHER
  survivor fails -- `EXTRA_MARKER`'s removal is invisible to both.
- Expected: transfer-proof correctly REFUSES the removal (exit 1, no
  `MutationTransferRecord` written) because no survivor has `can_fail =
  PROVEN` for `D_extra`.
