# Fixture: cs_good_equal (golden-good)

Contract row 1 (`contracts/catch-set-comparison-harness.md` RED fixtures table):
"NEW = OLD with ordering only | golden-good | superset true, `lost=0`".

Also satisfies the tasks.md T050 line's literal golden-good clause: "a defect
caught today is recorded caught".

- Defect D1 (`../_shared/patches/defect_d1_widget.sh`): drops `SAFE_MARKER`.
- OLD config (`config_old.json`): `[g_marker, g_noop]`.
- NEW config (`config_new.json`): `[g_noop, g_marker]` — same gate-id SET,
  different declared order.
- Both configs run `g_marker` against the D1-mutated disposable copy: it
  FAILs (catches D1) in both. `g_noop` PASSes in both (always-pass gate).
- Expected (`expected.json`): superset holds, `lost=0`, `gained=0`,
  `old_verdict=new_verdict=CAUGHT`, exit 0.
