# CON-211 evidence: writer default patch set follows the registry default

| Field | Value |
|---|---|
| Revision | 2 |
| Last modified | 2026-11-06T12:30:00Z |
| Item | CON-211 (parent CON-031) |
| Id map | bundle CON-117 = CON-211; bundle CON-120 (U59 TMPDIR) = CON-212 (re-minted 2026-11-11: both ids collided with different items on main). The captured `*.txt` files in this directory are the 2026-11-06 originals and still print the old id CON-117 in test names; they are unedited evidence. Re-runs on current main are in `rerun_2026-11-11/`. |

All runs on 2026-11-06, host codegraph 1.6.2, scratch directories only (no live index, the real runner cache
`~/.cache/helix/codegraph_runner` does not exist on this host before or after). `<scratch>` stands for the session
scratch directory.

| File | What it shows |
|---|---|
| `red_u38.txt` | U38 with the new expectations on the old writer: FAIL, `d1=[patch_tool --patches fkidx1,resolve1 --print-bin]`, `d5=[patch_tool --patches default --print-bin]` |
| `green_u38.txt` | U38 after the change: PASS (`d1` and `d5` are `patch_tool --print-bin`) |
| `mut_mb.txt` | mutants MB4, MB5 (writer gets its own list back), MB5b (`default` forwarded as an id) all killed by U38 |
| `mut_all.txt` | full `test_bulk_classify_mutations.sh`: GOLD (U31-U43 green) plus all 12 mutants killed |
| `patch_machinery.txt` | `test_patch_machinery.py` 19 pass, 0 fail, 0 skip (P3 registry default, P3b bare real-package run builds `1.6.2-fkidx1-resolve1-resolve2`) |
| `base_resolve2.txt` | `test_resolve2.sh` on 1.6.2: Q1-Q3 PASS (bridge no longer materializes methods; targets and full dump identical to stock) |
| `runner_ab.txt`, `runner_ab.sh.txt` | old writer runner `1.6.2-fkidx1-resolve1` vs new `1.6.2-fkidx1-resolve1-resolve2` vs stock, each run as the writer runs it (`init -y -v <P>`) on the resolve2 fixture: identical counts and byte-identical edge/ref dumps; swift-objc bridge edges present in all three (positive needle 4, negative needle 0) |
| `unit_safe_full.txt` | full `test_unit_safe.sh`: 63 of 64 pass; U59 fails on the unmodified head too (see below) |
| `u59_short_tmpdir.txt` | U59 passes with a short TMPDIR: its failure is a test artifact (the tool truncates echoed paths to 200 characters and U59's r1 matches the untruncated text), not caused by this change; tracked separately |
| `writer_e2e_preflight_refused.txt` | the real writer on a scratch project REFUSED at preflight: free disk 41 GB < required 60 GiB. The host guard was not bypassed, so the writer-level end-to-end run is SKIP (`disk_floor`), and the proof is at the runner layer above |

Honest limits: the fixture has 500 Java methods, so it shows that resolve2 changes no index content; it does not
reproduce the 3.5M-method heap OOM that resolve2 fixes. That OOM is recorded in resolve2's own docstring (ATMOSphere,
ATM-1030) and was not re-measured here.
