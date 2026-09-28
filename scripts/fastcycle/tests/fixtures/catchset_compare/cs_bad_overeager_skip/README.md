# Fixture: cs_bad_overeager_skip (golden-bad)

Contract row 3: "NEW affected-set wrongly skips D's catcher | golden-bad |
exit 1 naming D and the skip reason recorded by the emitter".

Distinct from `cs_bad_dropped_gate`: here `g_marker` IS present in NEW's
manifest (`config_new.json` is byte-identical in gate-id set to
`config_old.json`); the bug is that the (simulated) affected-set logic
records a decision, in `skip_map.json`, to SKIP running `g_marker` against
D1 -- NOT the DEC-08 "affected-set undeterminable" honest fallback (which
per `contracts/common-conventions.md` Terms runs the full suite instead),
but a WRONG "not affected" determination.

- Both configs' manifests list `[g_marker, g_noop]`.
- `skip_map.json` records `{defect_id: D1, gate_id: g_marker, skip_reason}`
  for the NEW run only.
- Expected: same superset-violated outcome as `cs_bad_dropped_gate`
  (`lost=1`, exit 1, named D1) PLUS the skip reason is surfaced (proving the
  future implementation must distinguish "gate absent from manifest" from
  "gate present but wrongly skipped for this defect" and report both).
