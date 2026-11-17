Lander note (2026-11-17): the vehicle placeholder CON-PENDINGr3g1 is landed as CON-539. The id was renamed in a scratch copy of the vehicle DB (all atm_id columns and the item text) so the plan sees a CON-prefixed own id; the landed DB is built by the engine replay. Evidence files elsewhere keep the old id.

Re-landing on main 61d943d7 (after #17 and #23): the same plan (own=1, CON-PENDINGr3g1 -> CON-539; the CON-453 base change) replayed again; remint_plan_61d943d7.txt, remint_verify_61d943d7.txt: PASS items=2 mismatches=0 known=1; validate OK, 504 items.
