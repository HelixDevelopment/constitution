# CON-425 evidence: replace refs hid a secret from history_secret_scan.sh (2026-11-16)

Evidence class: gate-logic, host-only, hermetic (§11.4.289): fake gitleaks,
local repositories, real git 2.53.0 and python3. PROVISIONAL (§11.4.290), not
yet independently reviewed. Reasoning effort of the producing agent: UNKNOWN.
Base: clone of origin main cc51c320 (all four fetched remotes at the same tip).
Script sha256: before d6bd918ef33e0dbf, after a992798f2fe66d00.

| File | What it shows |
|---|---|
| `review_replace_probe.txt`, `review_replace_log_probe.txt`, `review_rv1_probe.txt`, `review_rv16_probe.txt`, `review_rmut_out.txt` | the CON-423 review round 2 fixtures adopted as RED input, copied from `rev2_secscan_dl_ev/` (its `SHA256SUMS` verified OK for these five files before copying; the probe scripts stay outside the repository because they carry fixed fake literals) |
| `red_current_main.txt` | RED (§11.4.292 reproduce first) on the unfixed script: a secret blob replaced by a clean blob gives `--exact-only` rc=0 MYKEY=0 and scanner rc=0 findings=0; a forced blob->tree replace gives `--exact-only` rc=7 and scanner rc=0 findings=0; a caller's `GIT_NO_REPLACE_OBJECTS=1` changes nothing (the git-env scrub clears it). The `No such file` lines are noise of the first probe version (it read output files that a mode does not write); the stored `red_toggle.sh.txt` silences them, nothing else changed |
| `red_replace_suite_on_main.txt` | the new suite `tests/security/test_history_secret_scan_replace.sh` against the unfixed script: 3/17 |
| `toggle_minus_export.txt` | root cause by toggling one line: the fixed script with only `export GIT_NO_REPLACE_OBJECTS=1` removed hides the secret again (MYKEY=0, findings=0, tree rc=7); the replace refs are still listed, so the exit is 1 |
| `green_fixed.txt` | the same probe on the fixed script: every fixture found by both passes, `replace refs: 1` listed |
| `probe_git_sem.txt` | git 2.53.0 semantics: the variable wins over `core.useReplaceRefs=true` (`-c`, `GIT_CONFIG_PARAMETERS`, repository config); a replaced commit's diff is seen; a ref to a blob does not break `git log --all`. Probe script sha256 b9363096d35357bb (kept outside the repository, it carries a fixed fake literal) |
| `class_census.md`, `census_git_calls.txt`, `census_git_calls.sh.txt` | §11.4.276(C): every git call of the script and how it is replace-proof; the two sibling scripts and `safe_rm.sh` make no local git call |
| `suites/` | GREEN, two runs each with identical sha256 (`hash_compare.txt`), the mutation runs and the 21 existing history mutants |
| `red_toggle.sh.txt` | the probe used for the RED, toggle and GREEN files (stored as text, not a tracked script; sha256 46f62353fc00c24f) |

## Claims and their backing

- The defect reproduced on main: `red_current_main.txt`, `red_replace_suite_on_main.txt` (3/17).
- Root cause: `toggle_minus_export.txt` against `green_fixed.txt` differ only by the export line.
- Fixed in both passes: `suites/history_secret_scan_replace_run{1,2}.txt` (17/17).
- No regression: `suites/history_secret_scan_run{1,2}.txt` (45/45), `suites/history_secret_scan_deadlock_run{1,2}.txt` (19/19, two new cases for RV5 and RV16).
- Mutants: see the RESULT lines of `suites/*mutations*` and `suites/existing_hm21_mutants.txt`.

## Honest limits

- The scanner pass is proven with the fake gitleaks only, which runs `git log -p` with the inherited environment. Whether the real gitleaks v8 binary does the same is UNCONFIRMED (no run with the real binary; CON-401).
- Other git versions than 2.53.0: UNCONFIRMED.
- A replace ref is now a finding (exit 1) even when it hides nothing secret; that is a deliberate choice (classify by hand), not an operator decision.
- Remotes #2..n are fetched for heads, tags and replace refs only (pre-existing scope, see `class_census.md`).

## Heavy suite runs (suites/)

All runs were made under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`.

- Each suite was run twice and the hashes compared (`hash_compare.txt`):
  - deadlock: 19/19
  - 45-case history scan: 45/45
  - replace: 17/17
- Mutant suites, each run twice:
  - deadlock mutations: 16/16 killed
  - replace mutations: 14/14 killed
- Existing 21 HM mutants:
  - First run (`existing_hm21_mutants.txt`): Z8 reported BROKEN. Its anchor still named the old exit line, from before `rh` was added.
  - Fix: the Z8 anchor in `tests/security/test_security_scripts_mutations.sh` now matches the new exit line. The mutant still drops only the `kh` term.
  - Rerun (`existing_hm21_mutants_rerun.txt`): killed 21/21, problems 0.
