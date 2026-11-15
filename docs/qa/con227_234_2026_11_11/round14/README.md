# CON-234 round 14 (structural): C43 made deterministic, the manifest made true, a landing gate

| Field | Value |
|---|---|
| Item | CON-234 (vehicle fix227, round 14) |
| Base | `4adcc6b0` (round 13, review NO-GO); bundle requires `fed933c0` |
| Date | 2026-11-14 |
| Status | PROVISIONAL (§11.4.290): the independent round-14 review is owed; not pushed |
| Rounds | past `R_max`, under the standing operator decision (continue until GO; fresh fixer and fresh reviewer per round); fresh fixer instance |
| Review answered | `review_fix227_r13.md` (sha256 `3ecb96c0...`), NO-GO: F1 and F2 Important, F3 to F5 |
| Release scripts changed | none (`scripts/release/*` byte-identical to `4adcc6b0`) |
| Effort | UNKNOWN (the dispatch path does not report it) |

## 1. Findings and what was done

### F1 (Important): `--verify-manifest` was MANIFEST-MISMATCH (exit 3)

Cause: `round13/tools/make_mutants_md.py` matches the census pattern (`mutant` in the name) and had no manifest
row, so the claim in the round-13 commit message and README ("verify-manifest OK") was false for the committed tree.

- The file was renamed to `make_mut_table_md.py` (not a census file; `assemble13.sh` follows the new name). No
  excluded row was added: an excluded row needs an operator acceptance, which a fixer cannot give.
- The manifest was regenerated with the sanctioned generator (`--generate-manifest --write`, then `--sync-guide`).
  The generator only re-sorted 3 unrelated rows (908 rows; the guide census line is unchanged, total=908). Trailer:
  `Out-of-scope: config/full_suite_manifest.tsv — generated-regeneration`.
- `round13/README.md` now says the round-13 commits give MISMATCH and that round 14 corrects it; `round13/SHA256SUMS`
  was regenerated (99 OK); the old file is kept as `round13_sums_before_r14.txt`.
- New landing gate `tools/landing_gate14.sh REPO COMMIT OUTDIR`: it clones the COMMITTED tree (`git clone --shared`)
  and runs `--verify-manifest` there; PASS only when rc is 0 and the last line is exactly `RESULT: MANIFEST-OK`.
  `tools/make_bundle14.sh` refuses to write a bundle unless the gate passes (and refuses a dirty tree).
  - RED on `4adcc6b0`: `checks/gate_red_4adcc6b0/` (rc 3, MANIFEST-MISMATCH).
  - GREEN on commit A `da33ac84`: `checks/gate_green_da33ac84/`.
  - The bundle of this round is made by `make_bundle14.sh`, so the gate also runs on the final head; that output is
    written beside the bundle (outside the tree, since it is made after the last commit).
- Generator, guide sync and working-tree verify outputs: `checks/manifest/`.

### F2 (Important, source-defect by default): C43 failed 1 of 4 RT20 runs (got 6, want 0)

Reproduction state: `reproduced-host-fixture` (surface `host-only`: the test and the tag script run on the host).
The natural failure was NOT reproduced: 30 runs of the old test at load 35 to 43 (`c43/runs/natural_load_old_test_30runs.txt`)
and 24 runs at load about 47 to 49 with 8 CPU stressors (`stress_old_test_24runs.txt`) all had 0 offenders. The
reviewer's 1 in 4 remains the only natural observation. The failure was reproduced by a controlled toggle instead.

Investigation state: `root-cause-found-with-evidence`. The cause is the instrument's scope, not a token exposure:

- The test's wrapper `run43.sh` runs its own `git -C w remote set-url ...` before it starts the tag script. That git
  is a child of the wrapper, started with the caller environment, so it holds the 6 names the reviewer counted
  (`M3W_GITEA_TOKEN XYZ_TOKEN GH_TOKEN GITLAB_TOKEN _rpg_tok GIT_CONFIG_VALUE_0`). The C43 filter excludes the
  wrapper, `sleep 1.43` and the tag script by argv, but not this git. It is caught only when it lives longer than
  one 50 ms sampling pass, which happens under load: hence 1 failure in 4.
- Decisive experiment (§11.4.292(G)): a shim `c43/tools/git_shim_0p6s` (sleeps 0.6 s, then runs the real git) first on
  PATH, so the wrapper's git always lives long enough to be sampled.
  - Old test: 3 of 3 FAIL (got 18, 18, 12). Every offender has ppid = the wrapper (the shim, its `sleep 0.6`,
    `/usr/bin/git -C ... remote set-url`). No child of the tag script was ever an offender. Outputs `c43/runs/shim_old_out_*`,
    sanitised samples `c43/samples/shim_old_p43_*`.
  - New wrapper (unsets the caller names before its own git): 3 of 3 PASS; the red wrapper on the new test:
    C43b 3 of 3 FAIL (18, 12, 12). `c43/runs/redgreen_out_*`, `c43/samples/redgreen_*`.
- So no child the tag script starts holds a caller token in any run measured. The release path needs no change.

Fix (`tests/release/test_tag_and_release.sh`):

- The caller environment is one array `ENV43`; the wrapper runs its own git in a subshell with those names unset.
  C43 now measures only what it names: the children of the tag script.
- On a C43 failure the test prints one line per offender: ppid, first 4 argv words and the variable NAMES only. It
  does not keep `p43.json`: the raw sample can hold the caller's whole environment (on a real host that can include
  real credentials, §11.4.10), so the test reports what the reviewer needed (which processes, which names) without
  storing values. The repro tools in `c43/tools/` keep raw files in scratch only and commit sanitised samples
  (`sanitise_p43.py`: argv, ppid, environment size and the test's own variable names).
- New C43b runs the same scenario with the 0.6 s shim on PATH: control needle (the shim was sampled), offender count
  0, no git left. C43b makes the old race fail every time, so the check is deterministic: it does not depend on load.
- Suite: 313 checks (was 310).

Proof under load (N = 10): 2 workers, 5 runs each, beside 8 CPU stressors (CPUQuota 800 %), load 37 to 55:
10 of 10 `pass=313 fail=0`, C43 and C43b PASS in every run (`c43/runs/n10_loaded_summary.txt`, `n10_out_*_c43.txt`).
RT20 runs of the mutation harness (the reviewer's setting): `checks/rt20_*.txt` (see section 3).

### F3: K8 N2 accepts B2 under soft NOFILE 1024

Filed as a follow-up draft: `followup_k8_n2_nofile.md` (Task, test-instrumentation, parent CON-234; minted in the
tracker at the landing on `main`). Not fixed in this round.

### F4 (nit): "byte for byte"

`round13/README.md` now names the 5 fixtures (R19, R20, R21, R22, R31) whose `@PORT@`/`@SB@` placeholders were
filled, instead of claiming the fixtures are byte for byte. The second half of F4 (the pin F-row line count sentence)
is deferred in the follow-up draft, because it belongs in `channel_census.py pin-regen`.

### F5 (nit): a killed `meq` mutant exited 0

`tests/release/test_release_tooling_mutations.sh`: a killed recorded-equivalent mutant now prints
`FAIL NAME EQUIVALENT-KILLED: ...`, is counted in `equivalent_killed=` on the RESULT line and is not counted as
killed. Exit codes (function `final_exit`): 1 when survived, stale or control failures are non-zero; else 4 when an
equivalent mutant was killed; else 3 for HUPIGN or inconclusive; else 0. So the standing run's killed/survived
accounting is unchanged and the new outcome has its own exit code. `RTM_EXIT_SELFTEST="SURVIVED STALE CTRL_BAD
EQKILLED HUPIGN INCONCLUSIVE"` runs no mutant and prints the exit code for given counters; the channel suite's N5b
checks 10 counter sets. Probe: RT12's NEW text forced to kill (`checks/meqprobe_rt12.diff`, a scratch clone only):
`FAIL RT12 EQUIVALENT-KILLED`, `equivalent_killed=1`, rc 4 (`checks/meqprobe_rt12.txt`).

## 2. Checks (this round, this host)

| Check | Result | File |
|---|---|---|
| landing gate on `4adcc6b0` | FAIL rc 3 (RED, expected) | `checks/gate_red_4adcc6b0/` |
| landing gate on `da33ac84` | PASS | `checks/gate_green_da33ac84/` |
| tag suite under load, N=10 | 10/10 pass=313 fail=0 | `c43/runs/n10_loaded_summary.txt` |
| shim toggle, old test | 3/3 FAIL (RED) | `c43/runs/shim_old_out_*` |
| shim toggle, new test / red wrapper | 3/3 PASS / C43b 3/3 FAIL | `c43/runs/redgreen_out_*` |
| channel census suite (with N5b), N=2 | pass=99 fail=0, both | `checks/census_*.txt` |
| mutation harness `STALE_ONLY=1` | 383 mutants apply, stale=0, rc 0 | `checks/stale_only.txt` |
| meq probe RT12 | EQUIVALENT-KILLED, rc 4 | `checks/meqprobe_rt12.txt` |
| RT20 runs, N=4 | 4/4 survives as recorded, rc 0 | `checks/rt20_*.txt` |
| shellcheck -S warning (5 changed shell files) | rc 0 | commit A message |

Runs used `env -i` with a fixed HOME and TMPDIR in the scratch directory, `systemd-run --user --scope -p
TasksMax=2000`, `nice -n 10`, at most 2 at a time. `c43/runs/invalid_relative_tmpdir_30runs.txt` is a first loop
that was invalid (a relative TMPDIR made the control needles fail); kept, not counted.

## 3. RT20

RT20 (recorded equivalent) under the mutation harness, the setting in which the reviewer saw C43 fail: 4 runs
(2 at a time), each `PASS RT20 equivalent, survives as recorded`, `equivalent_killed=0`, rc 0 (`checks/rt20_*.txt`,
load at start 34 to 41). Had C43 failed, the harness would now print `EQUIVALENT-KILLED` and exit 4 (F5).

## 4. Not done, UNCONFIRMED

- The natural C43 failure was not reproduced in 54 runs; the cause rests on the toggle experiment. Whether the
  reviewer's 6 offenders were exactly the wrapper's git is UNCONFIRMED (their sample file was deleted); the names
  match exactly.
- The full mutation harness run was not repeated in this round (only STALE_ONLY, RT12 probe, RT20).
- F3 and the pin sentence of F4 are follow-ups, not fixed.
- `c43/tools/c43_{new,only,red}.sh` are cut-down copies of the tag suite used only for the experiments;
  `shellcheck -S warning` reports SC2034 (unused variables kept from the copied suite header) on them. They are
  evidence tools, not run by any suite, and are not census files.
- Independent review owed; nothing pushed.
