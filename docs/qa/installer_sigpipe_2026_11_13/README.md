# Installer SIGPIPE under pipefail (CON-PENDING-INSTALLER-SIGPIPE)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | fix on vehicle/installer-sigpipe, PROVISIONAL (independent review owed) |
| Evidence class | gate-logic / unit only (§11.4.289): constructed marks fed to the real functions, no remote, no agent, no network |
| Base | b5a1815a |

## Defect

`scripts/install_constitution.sh` runs under `set -u -o pipefail`. `hi_push_changed` tested membership with
`printf '%s\n' "$x" | grep -qxF -- LINE`. `grep -q` exits at the first match; when `printf` still has lines to
write it dies of SIGPIPE, the pipeline returns 141, and a MATCH reads as NO MATCH:

- R, L and N lines: an unchanged remote is read as changed, so the run is refused with "a push happened during
  the agent run" (exit 5 in `tests/install/test_agent.sh`; also in real use). A false refusal (§11.4.201(1)).
- Z line (`printf b a | grep -q '^Z '`): a missing fingerprint tool is NOT seen, the fail-closed refusal is
  skipped. A false pass (§11.4.201(2)).

Measured on this host (bash 5.3.9): the bash `printf` builtin writes a multi-line string to a pipe one line per
`write()` (strace: 3 lines, 3 writes), so any input whose match is not on the last line can lose the race. Small
inputs lose it rarely (timing); an input larger than the pipe buffer plus grep's read buffer loses it every time.

## RED and GREEN (harness `tools/red_harness.sh`, three runs per version, N = 3000)

Run under `systemd-run --user --scope -p TasksMax=3000 nice -n 10 env -i PATH=/usr/bin:/bin`; `old` is
`git show b5a1815a:scripts/install_constitution.sh`, `new` is this change. Raw outputs: `harness/`.

| Leg | old run 1 | old run 2 | old run 3 | new run 1 | new run 2 | new run 3 |
|---|---|---|---|---|---|---|
| control needle `yes \| grep -q y` gives 141 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |
| raw 3-line `printf \| grep -qxF` gives 141 (not the installer; shows the race) | 0/3000 | 0/3000 | 1/3000 | 0/3000 | 1/3000 | 0/3000 |
| raw 60-line `printf \| grep -qxF` gives 141 (not the installer) | 8/3000 | 6/3000 | 14/3000 | 5/3000 | 5/3000 | 0/3000 |
| here-string of the same 3 lines misses the match | 0/3000 | 0/3000 | 0/3000 | 0/3000 | 0/3000 | 0/3000 |
| real `hi_push_changed`, small marks (11 lines), b == a, read as a push | 4/3000 | 8/3000 | 1/3000 | 0/3000 | 0/3000 | 0/3000 |
| real `hi_push_changed`, medium marks (63 lines, about 4 KiB), b == a, read as a push | 18/3000 | 12/3000 | 17/3000 | 0/3000 | 0/3000 | 0/3000 |
| real `hi_push_changed`, large marks (20 003 lines, 1 468 997 bytes), b == a, read as a push | 3/3 | 3/3 | 3/3 | 0/3 | 0/3 | 0/3 |
| real `hi_push_changed`, large marks with a Z line, fails closed | 0/3 | 0/3 | 0/3 | 3/3 | 3/3 | 3/3 |
| positive needle: a moved ref is read as a push | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

The two "raw" rows run the same pipe in both columns (they demonstrate the race on this host; the fix does not
touch them). Every row that runs the installer function goes from failing to 0 failures.

Control needle: `yes | grep -q y` must show `PIPESTATUS[0] = 141` (3/3 in every run), so the harness can see a
SIGPIPE death. Positive needle: a moved ref must still be read as a push (3/3 in every run, old and new).

## Class inventory (§11.4.276(C))

Instrument: a regex over the four install scripts for a pipe into an early-exit reader (`grep -q`, `-qx*`,
`-vq`, `--quiet`, `--silent`, `head`, `sed ... q`, `awk ... exit`, `read`, `cmp`, `head -c`), continuation lines
included, then each hit read by hand for whether the pipeline status reaches a decision. Files scanned:
`scripts/install_constitution.sh` (sources no other file), `scripts/update_constitution.sh`,
`scripts/install_cli_agent_plugins.sh`, `scripts/install_action_prefix.sh`.

| File:line (base) | Pipeline | Status used | Exposure | Closure |
|---|---|---|---|---|
| install 1683 | `printf b a \| grep -q '^Z '` | if | exposed (multi-line printf), fail-OPEN | here-string |
| install 1692 | `printf b \| grep -qxF R…` | `&& continue` | exposed, false push | here-string |
| install 1697 | `printf a \| grep -qxF L…` | `&& continue` | exposed, false push | here-string |
| install 1702 | `printf a \| grep -qxF N…` | `\|\| return 0` | exposed, false push | here-string |
| install 842 | `ls-remote URL REF \| grep -q .` | `&& return 0` | exposed when the pattern matches many refs: a found ref reads as missing | captured, then tested |
| install 1792 | `printf blk \| grep -E \| grep -vq` | if | exposed for a large block: a legacy path hidden (false pass) | captured, then tested |
| install 569, 571, 574 | `git ls-files/ls-tree -- path \| grep -q '^160000 '` | if / `&&` | single-line output today (one write) | captured, then tested |
| install 1110, 1111 | same, `hi_staged_only_gitlink` | `&&`, `!` | single-line output today | captured, then tested |
| install 678, 754 | `hi_upstream_table \| cut \| grep -qxF` | `\|\|` | small, cut writes once at exit today | `hi_upstream_ok` uses a here-string; 678 calls it |
| update 400 | `ls-files -s -- REL \| grep -q '^160000 '` | `\|\| die` | single-line output today | captured, then tested (`if !`) |
| update 560 | `head -n 80 hook \| grep -qE CAP` | `&&` | exposed when the first 80 lines exceed head's 4 KiB buffer: the capability reads as absent | captured, then tested |
| cli 359, 398 | `claude plugin list \| grep -q NAME` | if | exposed (multi-write output): an installed plugin reads as missing | captured, then tested |

Not in the class (status never reaches a decision): `install 522, 1182, 1306` and `update 256, 467`
(`… | head -n 1` inside an assignment whose status is not tested), `install 1247` / `update 432`
(`awk … exit` in an assignment, the next line tests the value), `update 409, 539, 540` (message text and display
output only), `install 468, 1366` and `update 452` (`tail` reads all input). Line 1217 already used `grep -c`.

Exact semantics: a `printf` producer is replaced by a here-string with the same bytes (`printf '%s\n' "$x"` and
`<<<"$x"` both give `x` plus one newline; `printf '%s\n%s\n' "$b" "$a"` and `<<<"$b"$'\n'"$a"` give the same
lines). A command producer is captured and tested as `o="$(cmd)" && grep … <<<"$o"`, so the producer must still
exit 0, as `pipefail` required before. Here-strings of the same size were already used by the loops of
`hi_push_changed` (`done <<<"$b"`), so no new temporary-file dependency is added.

## Regression test

`tests/install/test_sigpipe.sh`, run by `tests/install/run_all.sh` (manifest row generated with
`--generate-manifest --write`; the generator also re-sorted three existing rows, the row set differs by the new row
only; guide census line rewritten by `--sync-guide`; `--verify-manifest` gives `MANIFEST-OK`).

1. Static scan of the four scripts for a pipe into `grep -q` / `--quiet` / `--silent` in executable text
   (comments and single-quoted text dropped, double-quoted text kept because `"$(…)"` is code). Needles: a
   fixture with four violation shapes and four safe shapes must give exactly the four; each real file with one
   violation appended must give exactly one hit (a quote state left open would hide it).
2. `hi_push_changed` from the real installer in library mode: large marks (8000 fetched R lines) with b == a,
   one case per membership test, plus Z, small marks, and a moved ref. Three runs, identical.
3. Paired mutant built inside the test: the four membership tests put back into the pipe form. It must misread
   (R, L, N read as a push, Z error missed) and the static scan must flag four lines.

Runs on the fixed tree: three runs, `PASS 16 FAIL 0`, rc 0, outputs byte-identical (sha256 `245ea9ec…152f2f`).

External paired mutants (the test run unchanged against a mutated tree):

- the whole base installer (`b5a1815a`): `PASS 9 FAIL 3`, rc 1 (static scan flags line 569; the behavioural case
  misreads; the internal mutant finds 0 lines to revert);
- the fixed installer with only the R membership test put back into the pipe form: `PASS 13 FAIL 3`, rc 1 (static
  scan flags it; the behavioural case reads `R=0`, a false push; the internal mutant reverts 3 of 4).

Raw outputs: `test_runs/`.

## Second reported flake: test_lock "mutant (no re-check)"

ROOT CAUSE (proven, natural runs): `reclaim_race` launched run A with `bash -c … >"$SB/ra" &`. The redirection
runs in the child, so the parent's poll `grep -q 'TEST PAUSE reclaim' "$SB/ra"` could read the PREVIOUS race's
output (the updater case prints the same line) before the child truncated the file. The poll then stopped at
iteration 0, the test put the live pid into the lock before A had read it, and A refused at the first liveness
check ("another installer run (pid LIVE) holds …", rc=3) instead of pausing. The mutant case expects rc=0.

Probe `tools/lock_race_probe.sh` (the suite's `reclaim_race`, an updater race before each mutant race):

| Variant | Mutant case failures |
|---|---|
| base, natural | 12/150 and 3/80; the timed run shows loop iterations 0, an empty file copied at the break, and A naming the LIVE pid |
| base, constructed (child sleeps 1 s before its redirection) | 3/3 |
| fix (`: >"$SB/ra"` in the parent before A starts), natural | 0/150 |
| fix, constructed | 0/3 |

Fix: `tests/install/test_lock.sh` empties `$SB/ra` before launching A. Raw outputs: `lock/`.

## Install quick suites, four runs before and after

`tests/install/run_all.sh --quick` (the unit, integration, updater, e2e, agent, security, determinism, detection,
self-guard, git-wrapper, minor, lock and round 6 to 11 suites, upstream-main and, on the new tree, sigpipe, plus the four
installer gates with their mutation tests), with `env -i`, a stub `HOME`, `PATH=/usr/bin:/bin`, under
`systemd-run --user --scope -p TasksMax=3000 nice -n 10`. The old and new streams ran at the same time; host load
average was about 35 from other work.

| Run | old (`b5a1815a`) | new (this change) |
|---|---|---|
| 1 | PASS, 18 suites, 1713 checks, 0 failed (4493 s) | PASS, 19 suites, 1729 checks, 0 failed (4548 s) |
| 2 | PASS, 1713 / 0 (4136 s) | PASS, 1729 / 0 (4181 s) |
| 3 | PASS, 1713 / 0 (4486 s) | FAIL, 1728 / 1: `test_round8` (4568 s), see below |
| 4 | PASS, 1713 / 0 (4952 s) | PASS, 1729 / 0 (4957 s) |

Raw outputs: `suites/` (`summary.txt`, per-suite counts of every run, the failing excerpt of new run 3); runner
`tools/suite_runs.sh`. The 16 extra checks on the new tree are `test_sigpipe`. The `test_lock` "mutant (no re-check)" failure the
caller reported did not occur in any of these eight runs (before or after its fix); its evidence is the probe above.

### The `test_round8` failure in new run 3

The failed check is `update SIGTERM after 1.1s (first rc=143): re-run rc=1`. This is the "chaos on the UPDATE
path" case: SIGTERM is sent to the installer's process group during a real update, and then a clean re-run must
converge. The re-run's updater refused its checkout because a git lock file existed ("Another git process seems to
be running in this repository"). `tests/install/test_round8.sh` is unchanged by this change.

Probe `tools/r8_chaos_probe.sh` (v1) and `tools/r8_chaos_probe_v2.sh` (v2) run the same case at 0.9, 1.0, 1.1, 1.2
and 1.3 s. After the first run, v2 records the lock files under the project, the processes of the killed group
that are still alive, the processes whose working directory is in the project, and the holders of each lock. Raw
outputs: `r8/`.

| Run | old (`b5a1815a`) | new |
|---|---|---|
| the four suite runs above (10 SIGINT/SIGTERM cases each) | 0/40 | 1/40 |
| v1, 100 cases, old and new run one after the other while the suites ran | 0/100 | 2/100 |
| v2, 100 cases, old and new at the same time after the suites | 0/100 | 0/100 |
| total | 0/240 | 3/240 |

The two v1 failures on the new tree:

- case 25: after the first run, `.git/modules/submodules/constitution/index.lock` existed and no process of the
  killed group was alive. The re-run failed with rc 1 because of the lock.
- case 62: five processes of the killed group were still alive when the re-run started, and the re-run refused
  with rc 3. Five processes alive at that moment also occurred five times on the old tree (v1) and once per tree
  (v2), and those re-runs converged.

Not established (UNCONFIRMED):

- Whether this change makes these outcomes more likely. 0/240 against 3/240 is not a significant difference
  (two-sided Fisher exact p is about 0.25), and the two parallel runs both gave 0/100. No mechanism linking the
  change to them was found. The changed lines replace a pipe into `grep -q` with a captured read; they take no git
  lock and do not touch the submodule's index. The only checkout on this path (`install_constitution.sh` 1417 /
  `update_constitution.sh` 538) is unchanged.
- What left the stale submodule `index.lock` in case 25.

A related mechanism, measured on this host but not shown to cause these failures: `timeout` (uutils coreutils
0.10.0) puts itself and its child into a NEW process group, so a signal sent to the caller's group does not
reach them (`r8/timeout_pgid_mechanism.txt`). The updater's `fetch` runs under `HI_GX_TIMEOUT=300` (base line
418), so a signal to the installer's group would leave such a fetch running. The v2 probe saw no process left
in the project in any of its 200 cases.

Neither item is fixed here, because both are outside this change's scope (§11.4.293). They are reported for
tracking.

## Checks

Shellcheck finding counts (`shellcheck -f gcc`, base `b5a1815a` vs this change, same host version):

| File | base | new |
|---|---|---|
| scripts/install_constitution.sh | 37 | 37 |
| scripts/update_constitution.sh | 4 | 4 |
| scripts/install_cli_agent_plugins.sh | 4 | 4 |
| scripts/install_action_prefix.sh | 1 | 1 |
| tests/install/run_all.sh | 0 | 0 |
| tests/install/test_lock.sh | 29 | 29 |
| tests/install/test_sigpipe.sh | (new) | 1 (SC1091 note: `lib.sh` not followed, as in the other suites) |

Gate-ledger ratchet (`CM-GATE-LEDGER-RATCHET`): base and new both `unimplemented=394 baseline=394 fails=0`, PASS.
No `CM-*` name is added. `run_full_suite.sh --verify-manifest`: `MANIFEST-OK` (census `sh/member=323 total=914`).

## UNCONFIRMED

- The reported rate "8 of 6000" was not reproduced at the reported input size: the 3-line raw pipe gave 0, 0, 1, 0, 1
  and 0 of 3000 in the six runs here (2 in 18 000); the real function on realistic small marks (11 lines) did reproduce it (see table).
- Behaviour on bash other than 5.3.9 (another `printf` write pattern) and on hosts without `strace` evidence.
- Whether any installed `claude plugin list` really writes in more than one `write()`; the CLI sites are closed
  by the class rule, not by an observed failure.
- No live agent run was made (§11.4.289: evidence is gate-logic / unit class).
