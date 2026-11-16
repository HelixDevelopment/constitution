# CON-423 evidence: exact-match pass deadlock in history_secret_scan.sh (2026-11-16)

Evidence class: gate-logic, host-only, hermetic (§11.4.289): fake gitleaks, local
repositories, real git and python3. PROVISIONAL (§11.4.290). Reasoning effort of
the producing agent: UNKNOWN.

| File | What it shows |
|---|---|
| `red_deadlock_test_on_prefix.txt` | RED: the new test against the unfixed script (sha256 e03c80988748a0cd...), `HSS_DL_TIMEOUT=60`: case 1 fails (rc 124 after the gitleaks stage reported "control OK"); 4/16 pass |
| `red_wchan_prefix.txt` | RED, root cause: after 25 s the python3 matcher and `git cat-file --batch` both wait in `anon_pipe_write`; the script is still running |
| `green_wchan_fixed.txt` | decisive experiment: the same probe on the fixed script; the run ends before 25 s and prints the exact-match result |
| `history_secret_scan_deadlock_run{1,2}.txt` | GREEN: 17/17, two runs |
| `history_secret_scan_run{1,2}.txt` | the existing 45-case suite still passes, two runs |
| `history_secret_scan_deadlock_mutations_run{1,2}.txt` | 14 own paired mutants killed (DM1 re-introduces the deadlock), control passes, two runs |
| `hash_compare.txt` | sha256 of run 1 and run 2 of each suite: identical |
| `existing_hm_mutants.txt` | the 21 existing history-script mutants of `test_security_scripts_mutations.sh` on the fixed script |
| `class_census.md` | §11.4.276(C) census of the same deadlock class in `scripts/` |
| `wchan_probe.sh.txt` | the probe used for the two wchan files (stored as text, not a tracked script) |

The run-1 file of the deadlock suite was recorded after the 17th case was added
(the first GREEN run had 16 cases and is not kept).
