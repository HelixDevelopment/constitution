# Fixture: cs_negctrl_gained_catch (negative-control, task-line-driven)

tasks.md T050's literal negative-control clause: "a run catching more
PASSes". This exact wording does NOT match either of the contract's two
NAMED negative-control rows (`cs_negctrl_removal_with_transfer`,
`cs_negctrl_old_missed`, both about `gate_audit.py transfer-proof` /
`OLD_MISSED` respectively) -- neither is about a comparison run where NEW
simply catches something extra. This fixture supplies that missing case,
derived directly from clause CS-004's own definition ("superset=true iff no
row has `old=CAUGHT ∧ new=MISSED`"), never contradicting or extending the
contract's rules -- only exercising a shape CS-004 already permits but the
8 named rows never happen to cover.

- Defect D_extra (`../_shared/patches/defect_d_extra_widget.sh`): drops
  `EXTRA_MARKER`.
- OLD config: `[g_marker, g_noop]` -- does not even attempt `g_extra`.
- NEW config: `[g_marker, g_noop, g_extra]` -- gains `g_extra`.
- `old_verdict=MISSED`, `new_verdict=CAUGHT` for D_extra: this is the
  `gained` shape, never the violating `old=CAUGHT ∧ new=MISSED` shape.
- Expected: superset holds, `counts.gained=1`, `counts.lost=0`, exit 0 --
  "a run catching more PASSes".
