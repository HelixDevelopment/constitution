# Follow-up drafts (not filed; for the conductor to file through the workable-items engine)

## FU-1 (Task, nit): hi_lock_pid / up_lock_pid check-then-open race (review F-6)
- What: `[ -f "$f" ] && [ ! -L "$f" ]` and `timeout 5 head -c 20 -- "$f"` are separate steps; a lock path swapped
  for a symlink to /dev/tty between them would make head read the terminal, and uutils timeout would then hang.
- Affected scope: scripts/install_constitution.sh hi_lock_pid, scripts/update_constitution.sh up_lock_pid.
- Reproduction: UNCONFIRMED (needs write access to .git; outside the threat model stated by the review).
- Acceptance: the read cannot reach a terminal (open with O_NOFOLLOW / read through a descriptor checked with
  `-f` after open, or put `trap '' TTIN TTOU` before timeout as at every other site); the census then lists the
  sites as `yes` and the round-2 README's "cannot touch the terminal in normal operation" stays true without the
  qualifier.

## FU-2 (Task): python3 without -I outside the six install scripts
- What: repository-wide census `docs/qa/installer_followups_2026_11_14/census/py_isolation_census_repo.tsv`
  counts 1972 `python3` invocations without `-I`; a `json.py` (or any module name) in the current directory or
  on PYTHONPATH would be imported by them.
- Affected scope: repository-wide; out of scope of the installer follow-ups vehicle.
- Reproduction: per site UNCONFIRMED (only counted).
- Acceptance: each reachable site classified (reads only trusted cwd / sets -I / -P plus PYTHONPATH cleared),
  with a census gate like tests/install/test_python_isolation.sh.

## FU-3 (Bug): no-push gate SOURCE-FAILED on relative --file paths
- What: `scripts/gates/cm_installer_no_push_no_force.sh` reports SOURCE-FAILED when given relative `--file`
  paths (seen by the round-1 fixer, docs/qa/installer_followups_2026_11_14/README.md section 7; not fixed).
- Reproduction: UNREPRODUCED in this round (not attempted: out of scope).
- Acceptance: a relative `--file` path is resolved against the cwd (or refused with a usage error, exit 64),
  never reported as a source failure; a test with both forms.

## FU-4 (Task): timeout sites the census cannot see
- What: the round-2 census follows file names and scripts/... paths (and scripts/x/$v.sh from `for v in` lists)
  from the four entry scripts. It does not see a timeout reached through a binary (llmctl, claude_toolkit,
  labelctl, the installers of submodules that are not checked out here) or a file named only at run time.
- Acceptance: the boundary is either closed per entry (submodule installers audited in their own repositories)
  or recorded as a documented gap (it is recorded in the round-2 README).
