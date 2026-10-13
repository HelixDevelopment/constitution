# Fixture: cs_negctrl_old_missed (negative-control)

Contract row 8: "defect neither config catches | negative-control |
`OLD_MISSED`, not counted as lost, exit 0".

- Defect D_uncaught (`../_shared/patches/defect_d_uncaught_widget.sh`):
  changes only a comment line; every marker (`SAFE_MARKER`, `OTHER_MARKER`,
  `EXTRA_MARKER`) stays present.
- Both configs list `[g_marker, g_noop]` -- neither gate's grep target is
  touched, so neither catches it.
- The RED test independently verifies (by executing `g_marker`) that it
  genuinely PASSes against the D_uncaught-mutated copy, proving the
  fixture is honestly uncatchable by the gate set present, not merely
  claimed to be.
- Expected: `OLD_MISSED=["D_uncaught"]`, `counts.lost=0` (excluded, per
  CS-003, from the superset test for this row), exit 0.
