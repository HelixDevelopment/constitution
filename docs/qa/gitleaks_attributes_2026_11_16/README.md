# CON-453 evidence: git attributes and other read-time rewrites hid secrets from both history scanners (2026-11-16)

Status: PROVISIONAL (§11.4.290). This change has not been independently
reviewed yet. Reasoning effort of the producing agent: UNKNOWN.

Class: CON-438 (read-time hiding in `scripts/security/history_secret_scan.sh`)
and its sibling in `scripts/gitleaks/gitleaks_run_scan.sh`. The work item is
`CON-453` (filed as CON-PENDINGcon435 in the CON-435 bundle, re-minted at
landing). The same change also covers the shapes filed as CON-454 (merge-only
secret, `-m`), CON-455 (grafts and shallow), CON-457 (the fake scanner now
honours `--log-opts`) and CON-459 (class census beyond replace refs). Those
items stay open for the reviewer to close.

Evidence class:

- Live, host-only, for the real scanner (§11.4.289): the real gitleaks 8.30.1
  binary (sha256 88f91962aa2f93ac6ab281d553b9e125f5197bbbce38f9f2437f7299c32e5509),
  real git 2.53.0, local fixture repositories, and fake tokens built in Python.
- Gate-logic only, for the fake scanner runs
  (`tests/security/fixtures/fake_gitleaks_detect.py`, `fake_gitleaks.py`).
  Four cases per script exist only in this mode: a scanner that ignores or
  drops `--text`, `--no-textconv` or `-m` must make the script INCONCLUSIVE /
  BLIND. They prove the fail-closed self-check, not the scanner.

Base: the RED, GREEN and mutation runs were made on a clone of origin main
cb7008c4 with the CON-435 bundle head 55b225f1 fast-forwarded on top. The
work was then moved, unchanged, onto origin main 3e5e7e7d (which contains
55b225f1; none of the two scripts, the fixtures or the tests changed upstream
in between). `red/script_hashes.txt` holds the before and after hashes of
both scripts.

## What the defect was

gitleaks reads history through `git log -p`. The argv was captured with a git
wrapper: `log -p -U0 --full-history --all --diff-filter=tuxdb` by default,
and `log -p -U0 <opts>` when `--log-opts` is given (the caller's options
REPLACE the defaults). That git call honours every diff-attribute source, every
textconv driver, grafts and shallow files. It prints no diff for merges without
`-m`. When gitleaks' git fails (for example on a really shallow clone),
gitleaks logs "stderr is not empty", scans 0 commits and exits 0 with no
leaks. Every one of these ends as exit 0, "0 real leaks": a false PASS.

## Fix

`gitleaks_run_scan.sh` (S):

- appends `-m --text --no-textconv` LAST to every `--log-opts` the scan uses,
  including the caller's own, so a caller cannot undo them; a bare
  `--log-opts` with no value is a usage error (exit 2);
- exports `GIT_GRAFT_FILE=/dev/null/no-grafts` (an impossible path: with
  `/dev/null` git prints a deprecation hint on stderr, and gitleaks then
  reads nothing) and `GIT_SHALLOW_FILE=/dev/null` after the git-env scrub;
- runs a git pre-flight with the same options: a non-zero exit or any stderr
  is INCONCLUSIVE (exit 3), with a hint when the repository is shallow;
- runs a self-check before the scan: a throw-away repository with a `-diff`
  needle, a textconv needle, a merge-only needle and a plain negative file,
  scanned with the same binary and options. A missed needle or a found
  negative is INCONCLUSIVE (exit 3). The temporary repository is removed with
  `safe_rm_rf` (§11.4.287(B)).

`history_secret_scan.sh` (H):

- scans with `--log-opts="--all -m --text --no-textconv"`;
- adds two needles inside the mirror: a path marked `-diff` in the mirror's
  `info/attributes`, and a path whose diff driver has an empty `textconv`.
  Missing either is BLIND (exit 3);
- refuses a shallow mirror (a remote that is a shallow clone) as BLIND
  (exit 3).

## Files

| File | What it shows |
|---|---|
| `red/red_real_{1,2,3}.txt` | RED. The new suite with the real gitleaks against the scripts of 55b225f1: 8/27. Every attribute source, textconv, caller `--log-opts`, merge-only secret, grafts and fake shallow exit 0 with 0 findings in S. Caller attributes and a shallow remote exit 0 in H. The positive and negative controls pass. |
| `red/red_fake_{1,2,3}.txt` | The same with the fake scanners: 8/33. |
| `red/verdict_hashes.txt` | sha256 of each RED and GREEN file without its `     \|` detail lines (they carry temporary paths). The three runs of each leg have the same hash. |
| `green/green_real_{1,2,3}.txt` | GREEN. The same command on the fixed scripts: 27/27. |
| `green/green_fake_{1,2,3}.txt` | GREEN with the fake scanners: 33/33. |
| `red_first/` | The first RED runs (29/27 cases, before four fake-only cases were added): the same result. |
| `mutations/mut_fake_1.txt` | 24 paired mutants (AM1 to AM24), all killed with the fake scanners. |
| `mutations/mut_real_1.txt` | The 15 mutants that do not need a broken scanner, all killed with the real gitleaks. |
| `probes/attr_repro.py.txt` | The probe: 27 shapes, each run through S and H with the real gitleaks. |
| `probes/probe_red_21_shapes.txt`, `probes/probe_red_6_new_shapes.txt` | Probe on the unfixed scripts. |
| `probes/probe_green_27_shapes.txt` | Probe on the fixed scripts: every shape FOUND, except a really shallow clone (S and H) and a fake shallow file (H), which are rc=3 (fail closed). |
| `probes/run_legs.sh.txt` | The script that ran the RED, GREEN and suite legs, one run at a time under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`. |
| `probes/size_unfixed.txt`, `probes/size_fixed.txt`, `probes/size_findings_compare.txt` | Run time and findings of S on this repository, before and after the fix (see "Results on the final tree"). |
| `probes/run_legs2.sh.txt` | The load-bounded runner of the final legs: one job at a time in its own `systemd-run --user --scope` unit, pause while load1 > 50, stop that unit (never by pattern) and retry when load1 > 60. |
| `class_census.md` | §11.4.276(C): every script that scans history or file content for secrets, every shape and the primitive that closes it. |
| `suites/` | The existing security and forge suites, each run twice on the final tree, with `hash_compare.txt` (made by `hash_compare.sh.txt`). |
| `followups/r3g1_intermittent/` | Evidence for CON-PENDINGr3g1, a test-instrument defect found while running the suites (see "Found on the way"). |

## Claims and their backing

- The false PASS reproduced live with the real binary for every shape listed
  in `class_census.md`: `red/red_real_*.txt`, `probes/probe_red_*.txt`.
- Root cause: each part of the fix, removed alone (mutants AM1 to AM6,
  AM11 to AM14, AM16 to AM20), brings back a miss or a wrong exit with the
  real binary: `mutations/mut_real_1.txt`.
- Fixed: `green/green_real_*.txt` (27/27, three runs, same verdict hash).
- Fails closed: a scanner that drops any forced option makes S exit 3 and H
  exit 3: `green/green_fake_*.txt` cases S19 to S22, H9 and H10 (gate-logic).

## Results on the final tree (origin main 3e5e7e7d plus this change)

Measured 2026-11-16/17, one heavy job at a time, load between about 15 and 45.

| Leg | Result |
|---|---|
| New suite, real gitleaks, 3 runs | 27/27 each, same verdict hash (`green/verdict_hashes.txt`) |
| New suite, fake scanners, 3 runs | 33/33 each, same verdict hash |
| Paired mutants AM1 to AM24, fake | killed 24, skipped 0, failed 0 |
| Paired mutants, real gitleaks | killed 15, skipped 9 (fake-only), failed 0 |
| 19 existing security and forge suites, 2 runs each | all rc=0, run 1 and run 2 IDENTICAL after normalising the loopback port and temp paths (`suites/hash_compare.txt`) |
| git-env class census | PASS, unscrubbed=0 |
| Gate-ledger ratchet | unimplemented=394, baseline=394, PASS |
| Constitution index | fresh, PASS |
| `run_full_suite.sh --verify-manifest` | MANIFEST-OK (sh/entry=390, total=959) |
| shellcheck `-S warning` on the changed scripts and tests | clean |
| workable-items `validate` / `diff` | OK, 451 items; DB and Markdown in sync |

`tests/security/test_security_scripts_mutations.sh` mutant HM4 ("drop `-m`
from H's log-opts") was restated: its pattern was the old line
`--log-opts="--all -m"`, which this change replaced with
`--log-opts="--all -m --text --no-textconv"`. The restated mutant drops only
`-m`; it is killed in both runs (119/119). The first round-1 run, made before
the restatement, reported HM4 as "pattern not found" (kept as
`followups/r3g1_intermittent/suite_run1_survived.txt`).

Size (S on this repository at 55b225f1, 1532 commits; `probes/size_*`):
24.6 s and 228 findings before, 76.4 s and 682 findings after. Both runs
have the same 157 distinct (rule, file, secret) keys; the 454 extra findings
are all in merge commits, so they are `-m` repeats of keys already found.
On this repository the fix finds no new secret and costs about three times
the run time. This was measured once, not three times.

## Found on the way (not part of this fix)

Mutant R3G1 (`gh api` without `--hostname github.com` in
`github_actions_inventory_disable.sh`) survived the first suite run and was
killed in others. The test check has the shape
`! grep -v PATTERN LOG | grep -q .` under `set -o pipefail`: when `grep -q`
exits on its first match, `grep -v` can die of SIGPIPE (exit 141), pipefail
makes the pipeline fail, and `!` turns that into a PASS. Measured with GNU
grep 3.12 (`followups/r3g1_intermittent/race_result.txt`): the
mutant-shaped 5.7 KB log false-passes the check 30 and 50 times in 300; a
135 KB log 300 times in 300 with `grep -v` exit 141; the clean log passes
300 times in 300. The single-command form `! grep -qv PATTERN LOG` gives 0
false passes. Four sites in two test files have the shape
(`class_sites.txt`). The files are byte-identical to origin main 3e5e7e7d;
this change does not touch them and does not fix them. Filed as
CON-PENDINGr3g1 (re-mint at landing). The new tests of this change contain
no `| grep -q` pipeline (same regex, which finds the four other sites).

## Honest limits

- Only gitleaks 8.30.1 and git 2.53.0 were measured. Other versions are
  UNCONFIRMED.
- The system attributes file (`$(prefix)/etc/gitattributes`) needs root and
  was not tested. A system `core.attributesFile` set through
  `GIT_CONFIG_SYSTEM` was tested.
- Behaviour changes for callers of S: binary files are now scanned as text and
  merge diffs are read (together about three times the run time on this
  repository, see "Results on the final tree"; the share of each was not
  measured); `-m` can report the same secret once per merge
  parent; a shallow clone now exits 3 instead of a silent PASS; exit code 3
  is new for S.
- The self-check uses fixed log-opts, not the caller's. It proves the binary
  and the forced flags, not the caller's revision range.
- H5 (a caller textconv in the global config) is not a RED case for H: the
  bare mirror does not read committed attributes, so the driver is never
  selected there.
- The fixture repositories are made for the test, not taken from the field.
  The surface is the host only.
- `gitleaks_run_scan.sh` has no separate guide; its header is its
  documentation (pre-existing).
- The 119/119 of `test_security_scripts_mutations.sh` in both final runs is
  not proof that R3G1 is always killed: that check is intermittent
  (CON-PENDINGr3g1).
- The status of CON-453 is In progress and PROVISIONAL until the
  independent review; CON-454, CON-455, CON-457 and CON-459 are left open.
