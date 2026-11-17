# Tracked item draft: CON-PENDING-O6-1 (no id minted; the lander assigns one)

- Type: Bug. Status: Queued. Reproduction: none — UNREPRODUCED. Investigation: not-started.
- Title: intermittent failure of `tests/jev/test_review_fixes_r2.sh` P2 (bootstrap row), root cause UNKNOWN.
- What: P2 failed once in a full run during round 6; it has not been seen again. Round 7 added an instrument
  (`keep_bs_evidence`: keeps bs.out/err, gate.out, status.json, cap.json and the rc, prints the stderr tail); the
  round-7 review judged the instrument adequate and found 0 rows in `docs/workable_items.db` tracking it (R7-D).
- Reproduction: 12 of 12 standalone repetitions and every `run_all` run passed (round 7); round 8 did not reproduce
  it either (not attempted beyond the regular suite runs). Next step: run P2 in a loop under load (≥ 50 runs, the
  host at its normal load) and keep every instrument dump of a failure.
- Acceptance: a captured failing run with the instrument output, a root cause shown by a decisive experiment
  (§11.4.292(G)), and a RED-to-GREEN row; or closure as `not-reproducible` with the attempts and a control needle.
- Roadmap-Item: CON-PENDING-JEV.
