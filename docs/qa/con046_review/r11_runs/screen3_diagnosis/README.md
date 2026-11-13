# CON-046 round 11: why screen 3 failed (2026-11-13)

Screen 3 ran on head 7bdffcf6 from 2026-11-12 18:55:53 to 2026-11-13 00:45:32 CET and ended rc 1. It reported
`gen-rxq-da7dc34398` and the equivalence proofs `eq-site-ident-aborts`, `eq-site-nopy-aborts` and
`eq-site-cannottell-aborts` as "killed". See `screen3_vs_screen2.diff`.

## Cause (measured)

- Date is ruled out as the cause of the kills. The judge (`jv`) can only report "killed" when the real result and the
  job result carry the SAME date stamp, so every kill compared two results from the same day.
  `eq-site-cannottell-aborts` was also killed under the PINNED GNU date, not only under the alternative date. The
  uutils upgrade (0.8.0 to 0.10.0, `uutils_upgrade.txt`) happened at 06:01 on 11-12, before screen 1, so all three
  screens ran on the same uutils.
- Resource exhaustion is the cause. The session scope (`tmx-constitution-8423.scope`, `pids.max` 6000) was at 5889 at
  about 01:00 on 11-13, and `pids.events` `max` rose from 522 to 554 to 558 within minutes. About 3700 foreign
  processes (`git`, `git-upload-pack` and `sh`, from a sync-upstreams test under `syncup.kB5E`) had been stuck since
  00:35:57. Screen 3's equivalence jobs are launched last, so they ran in that window. The jobs sent their stderr to
  `/dev/null`, so a refused fork showed up only as a different vector, and that was judged "killed".
- Reproduced (`fork_reproduction.txt`). In the same window, the pre-fix suite printed `fork failed: Resource
  temporarily unavailable`, and the real gate's vector under the alternative date came out as `BASEFORM=0,0/X`
  instead of `1,1/B`. Both stamps in that run were the same day, `2026-11-12~2026-11-12`. A refused fork alone changes
  the vector, with no date change.
- Not measured: the four jobs' own vectors from screen 3 are lost, because their temporary directory was deleted. The
  cause is the measured mechanism plus the timing, not a replay of those exact four jobs.

## Fix (test-first)

1. Resource failure is INCONCLUSIVE. A classify is INCONCLUSIVE, and is re-run, when its stderr matches a
   fork or memory failure signature, or when the cgroup `pids.events:max` or `memory.events:oom_kill` counter grew
   during it (own cgroup and every ancestor). It is never read as killed. The new self-test is
   `selftest-resource-failure`: the real gate runs with one git call failing the way a refused fork fails.
   - RED, with `resclean` disabled: `BAD resource self-test: a job with a refused fork was judged killed`
     (`red_resource_selftest_resclean_disabled.log`).
   - GREEN: the job is INCONCLUSIVE (`green_members_and_selftests.log`, which also shows the four screen-3 members
     passing on 11-13).
2. Injected clock. Every `date` the suite and the gate run is pinned to one instant, `SUITE_NOW` (default: noon UTC of
   the start day). The rewrites are:
   - a bare read becomes `-d $SUITE_NOW`;
   - a relative `-d` value is counted from `SUITE_NOW`;
   - an absolute value is passed through unchanged.

   A needle stops the run when the pin is blind. RED, before the pin with `SUITE_NOW=2000-06-15T12:00:00Z`: `got
   2026-11-12/...` (`red_clock_pin_blind.txt`). The screen-3 failure was not caused by the date, so this is hardening
   that the conductor asked for, not the fix for screen 3.

`../superseded_7bdffcf6/` keeps the three logs from head 7bdffcf6 (screens 1 and 2 rc 0, screen 3 rc 1). They are
superseded by the rerun on the fixed head.
