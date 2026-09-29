# Fixture: cs_negctrl_removal_with_transfer (negative-control)

Contract row 7: "duplicate gate whose mutation the survivor catches |
negative-control | transfer record written, exit 0". Pairs with
`cs_bad_removal_no_transfer`: same tool (`gate_audit.py transfer-proof`),
opposite outcome, proving the harness can discriminate both directions
(§11.4.201(1) false-positive guard for this family).

- `g_marker_dup` (proposed for removal) and `g_marker` (survivor) both check
  `SAFE_MARKER` -- a real duplicate, unlike `g_extra` in the sibling
  golden-bad fixture, which checks a marker no survivor here checks.
- `removal_request.json` names D1 (drops `SAFE_MARKER`) as `g_marker_dup`'s
  own paired mutation.
- The RED test independently verifies `g_marker` genuinely FAILs against a
  D1-mutated disposable copy.
- Expected: `can_fail=PROVEN` for the survivor, `MutationTransferRecord`
  written, exit 0.
