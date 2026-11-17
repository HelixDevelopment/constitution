# PR #23 landing on main 03e6645e (lander, 2026-11-17; PROVISIONAL)

The vehicle's 29 tracker writes (verification jobs for 27 Ready-for-testing items; CON-190 and CON-191
back to In progress) were replayed onto main's database through the engine (remint_ids.py plan /
replay --apply / verify); neither side of docs/workable_items.db was taken.

- remint_plan.txt: 28 items conflicted because main's CON-521 landing rewrote the same
  `**Verification:**` line (a due date). Each is resolved =vehicle (resolve_args.txt): the vehicle
  replaces that line with a scheduled job. For 27 items the only main line dropped is that
  `**Verification:**` line. For CON-144 main also carried a section 11.4.214 recurrence-link
  paragraph; the lander appended that paragraph to the vehicle's CON-144 text in the scratch
  vehicle copy before planning, so =vehicle drops neither side.
- remint_verify.txt: PASS items=29 mismatches=0. Engine validate: OK, 503 items.
- Not done here (follow-up): the review's M1 (add rc=3 known-failure=5 to the CON-015/CON-016 checks).

Evidence class: gate-logic only (section 11.4.289).
