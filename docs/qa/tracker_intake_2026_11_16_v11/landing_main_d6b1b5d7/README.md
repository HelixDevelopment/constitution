# Tracker-intake vehicle (PR #21) landing on main d6b1b5d7 (lander, 2026-11-17; PROVISIONAL)

The vehicle's docs/workable_items.db holds 309 items and descends from main 02c10935; its merge of
ebd8818c kept the vehicle database on purpose. Taking that side would delete about 195 main items.
Neither side was taken: the vehicle's tracker writes were replayed onto main d6b1b5d7's database
through the engine (remint_ids.py plan with base = 02c10935, vehicle = this branch's head,
target = main; replay --apply; verify).

- args.txt: the round-11 plan options (main_ebd8818c_args.txt), the duplicate-check file changed to
  dup_resolution_d6b1b5d7.tsv, plus --resolve CON-046=vehicle.
- dup_resolution_d6b1b5d7.tsv: the round-11 rows plus 44 DISTINCT verdicts by the lander (section
  11.4.214) for shared-file pairs with main items that are new or newly open since ebd8818c:
  GitLab pre-release findings CON-315..CON-327 against CON-513, CON-514, CON-530 and CON-226, and
  CON-304 against CON-184, CON-185, CON-222, CON-224. Each pair shares one file only and is a
  different defect.
- CON-046: both sides changed the description. The lander wrote main's text plus the vehicle's three
  extra paragraphs (restore note, relayed decision 2, foreign-id note) into the scratch vehicle copy
  before planning, so =vehicle drops neither side.
- remint_plan.txt: PLAN own=46, refusals 0, conflicts 0; the vehicle's CON-299..CON-344 land as
  CON-540..CON-584 (remint_map.tsv; CON-339 is superseded by CON-313). The Roadmap-Item trailers
  CON-527 in this branch's commits name the umbrella, which lands as CON-540 (CON-527 is a different
  item on main). History is not rewritten.
- remint_verify.txt: PASS items=49 mismatches=0 known=46. Engine validate: OK, 549 items (main 504 +
  45 new); no main item is absent.
- config/full_suite_excluded.lock: the 12 evidence-tree tool and fixture files the vehicle adds to the
  excluded set were accepted with --verify-manifest --accept-excluded-change (operator approval of
  excluded-lock rows, relayed by the conductor on 2026-11-17). The PR #21 review reported this
  mismatch.

Evidence class: gate-logic only (section 11.4.289).
