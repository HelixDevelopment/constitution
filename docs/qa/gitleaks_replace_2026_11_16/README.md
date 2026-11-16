# CON-435 evidence: replace refs hid a secret from gitleaks_run_scan.sh (2026-11-16)

Status: PROVISIONAL (§11.4.290). This change has not been independently
reviewed yet. Reasoning effort of the producing agent: UNKNOWN.

Evidence class:

- Live, host-only, for the real scanner (§11.4.289): the real gitleaks 8.30.1
  binary (sha256 88f91962aa2f93ac6ab281d553b9e125f5197bbbce38f9f2437f7299c32e5509),
  real git 2.53.0, and local repositories that carry `refs/replace` entries
  and fake tokens built in Python.
- Gate-logic only, for the fake scanner runs
  (`tests/security/fixtures/fake_gitleaks_detect.py`).

Base: a clone of origin main cb7008c4. `red/script_and_test_hashes.txt` holds
the script hashes:

- before: 5a826b84…
- after: 17f5eda6…

Reproduced first by the conductor with the same binary in
`/mnt/DATA1TB/claude-work/scratch/gl_live_1794852136`. That evidence is
outside the repository; its `SHA256SUMS` has sha256 cd49366b…. Its leg d
(this script) on the replaced repository found 1 leak (the control). The plain
repository gave 2 leaks.

| File | What it shows |
|---|---|
| `red/r2_red_real_{1,2,3}.txt` | RED. It is the new suite with the real gitleaks, run against the unfixed script (`GLRS_SCRIPT` = a copy of `cb7008c4:scripts/gitleaks/gitleaks_run_scan.sh`). Result 4/8. On the commit-replace repository the hidden secret is missed (exit 1, 1 finding, the control only). On the blob-replace repository the exit is 0 with 0 findings, which is a false PASS. `core.useReplaceRefs=true` in the repository config, or in `GIT_CONFIG_PARAMETERS`, misses as well. The positive control (R2, R4) and the negative control (R5) pass. |
| `red/r2_red_fake_{1,2,3}.txt` | The same with the fake scanner: 4/9 (R1, R3, R6, R7 and R8 fail). R8 shows that the scanner process saw `GIT_NO_REPLACE_OBJECTS` UNSET. |
| `red/red_verdict_hashes.txt` | Hash of each RED file without its `     \|` detail lines. The detail lines carry timestamped evidence paths. The verdict lines are identical over the three runs. |
| `green/r2_green_real_{1,2,3}.txt` | GREEN. The same command on the fixed script gives 8/8. The three files are byte-identical. |
| `green/r2_green_fake_{1,2,3}.txt` | GREEN with the fake scanner gives 9/9. The three files are byte-identical. |
| `mutations/mut_{fake,real}_1.txt` | Paired mutants, run with both scanners. GM1 to GM8 are killed. They are: export removed; not exported; exported before the scrub; misspelt name; `env -u` on the scan; `unset` before the scan; exported only in a subshell; exported only after the scan. GE1 and GE2 (values `0` and empty) are behaviour-equivalent: with the real binary every case passes, and with the fake scanner only the contract case R8 (scanner sees exactly `1`) fails. This is measured, not assumed: git disables replace refs for any value. |
| `suites/` | Every `tests/security` suite run twice, plus the new suite and the mutation suite (fake and real) run twice. The two runs of each are compared in `hash_compare.txt`. All runs were made under `systemd-run --user --scope -p TasksMax=2000 nice -n 10`. |
| `probes/r0_sigpipe_probe.{sh,out}.txt` | Root cause of a test-instrument flake found while building the test. In the first version, the R0 precondition `git log -p --all \| grep -q` failed in 1 of 3 runs. The probe shows git exits 141 (SIGPIPE) in 18 of 60 runs when `grep -q` stops early; under `pipefail` the pipeline then reads as "not found". The test now writes the logs to files and greps the files. |
| `probes/attributes_probe_result.txt` | The CON-438 class, measured with the real binary on the fixed script. A `-diff` attribute gives a false PASS (exit 0, 0 leaks). This happens with the caller's `core.attributesFile` and also with a committed `.gitattributes`. Filed as `CON-PENDINGcon435`. Not fixed here. |
| `class_census.md`, `census_raw.txt` | §11.4.276(C): every script under `scripts/` that runs a scanner or reads git history. Only two run a secret scan over history, and both now export the variable. |

## Suite results (`suites/hash_compare.txt`)

Every suite passed in both runs:

| Suite | Result |
|---|---|
| forge | 168/168 |
| actions | 44/44 |
| history scan | 45/45 |
| deadlock | 19/19 |
| CON-425 replace | 17/17 |
| new suite, fake scanner | 9/9 |
| new suite, real scanner | 8/8 |
| mutation suite, fake scanner | killed 8, equivalent 2 |
| mutation suite, real scanner | killed 8, equivalent 2 |

The two runs are byte-identical for every suite except forge. Forge differs
only in the ephemeral loopback port of its fixture. After that port is
normalised the two runs are equal (`forge_port_normalised_hashes.txt`).

`census.txt`, `ratchet.txt` and `index.txt` record the checks run on the
working tree before the commit:

- git-env census: PASS, unscrubbed=0
- gate ledger ratchet: unimplemented=394, baseline=394
- index fresh: PASS

## Claims and their backing

- The defect reproduced with the real binary: `red/r2_red_real_*.txt`.
- Root cause: mutant GM1 (the export removed, which is the unfixed state)
  fails with the real binary, and the fixed script passes. See
  `mutations/mut_real_1.txt` and `green/r2_green_real_*.txt`.
- Fixed for commit replace and blob replace, also against
  `core.useReplaceRefs=true`: `green/r2_green_real_*.txt` (8/8, identical).
- Positive and negative controls hold on both the unfixed and the fixed
  script: R2, R4 and R5.

## Honest limits

- Only gitleaks 8.30.1 and git 2.53.0 were measured. Other versions are
  UNCONFIRMED.
- The fixture repositories are made for the test, not taken from the field.
  The surface is the host only.
- Real gitleaks R8 (the scanner's own environment) is not observable. It is
  reported as a SKIP line, and R1/R3 are the live proof instead.
- A replace ref is not listed or counted as a finding by this script; it only
  stops hiding content. `history_secret_scan.sh` lists replace refs; this
  script does not. That is a scope choice, not an operator decision.
- The script header says "Read-only against the scanned repo", but the script
  writes `qa-results/gitleaks/<ts>/` inside the scanned repository. This is
  pre-existing and not changed here.
- The `-diff` attributes class gives a false PASS. It is open as
  `CON-PENDINGcon435`.
