# Fixture: cs_bad_dropped_gate (golden-bad)

Contract row 2: "NEW omits the one gate that catches defect D | golden-bad |
exit 1, row D `CAUGHT→MISSED`". Matches tasks.md T050's literal golden-bad
clause verbatim.

- Defect D1: drops `SAFE_MARKER`.
- OLD config: `[g_marker, g_noop]` — `g_marker` catches D1.
- NEW config: `[g_noop]` — `g_marker` entirely absent from the manifest.
- Expected (`expected.json`): `old_verdict=CAUGHT`, `new_verdict=MISSED`,
  `counts.lost=1`, superset VIOLATED, exit 1, `named_defects=["D1"]`.
