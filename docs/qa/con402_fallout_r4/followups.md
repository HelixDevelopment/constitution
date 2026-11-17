# CON-402 audit fallout, round 4: follow-up items and honest boundaries

Status: PROVISIONAL. Every item below is a placeholder for the tracker (no id minted here). Evidence class:
gate-logic (hermetic tests of two censuses and of a test layer), host-only, not a live product run. This file
supersedes `../con402_fallout_r3/followups.md`: FU-1, FU-3, FU-4 and FU-5 are carried over unchanged (read them
there); FU-6 and FU-7 are new.

## FU-1, FU-3, FU-4, FU-5: carried over unchanged

See `../con402_fallout_r3/followups.md`. Round 4 does not change the inherited-attribute boundary (FU-1): code that
runs before the file (BASH_ENV, a sourcing parent, an exported `BASH_FUNC_unset%%`) is outside what a file-scope
census can see.

## FU-6 (new): the same reading class in other census-style gates, outside this vehicle's scope

Root cause of R3-1 / R3-5: a classifier decides "this line is a comment / blank" with whitespace semantics that are
not those of the language that runs the file (Python `str.lstrip()` / `\s`, or POSIX `[[:space:]]`, which in a
C.UTF-8 locale also matches CR, VT, FF and, through `iswspace`, several Unicode spaces). Swept 2026-11-17 over
`scripts/validation` and `scripts/gates` (every `startswith("#")` in Python and every `^[[:space:]]*#` /
`^[ \t]*#` / `^\s*#` in shell):

| file | what it classifies | in class? | note |
|---|---|---|---|
| `scripts/validation/git_env_class_census.py` | shell / Python / JS source | yes | round-4 hardening (`reading_problem`, closed shebang set); the review of round 4 reopened the class (R4-1, R4-3, R4-4), see `../con402_fallout_r5/` |
| `scripts/fastcycle/tests/check_safepath_census.py` | `baseline_replay.sh` | yes | round-4 hardening (`_sh_read_as_bash`), reopened by R4-1 and R4-2 and re-hardened in round 5 (`../con402_fallout_r5/`); every shell helper (`_blank_heredocs`, `_heredoc_bodies`, `_git_env_scrub_sh`, `tag_at`, `_sh_text_lines`, `sh_commands`) only sees text that passed the gate. `py_census` keeps universal newlines on purpose: Python's own parser treats a lone CR as a line break (measured, `ast.parse("# c\ry=2")` yields `y=2`) |
| `scripts/gates/lib/instrument_trap_scan.sh` | shell source (awk `/^[[:space:]]*#/`) | yes | a `VT#; <trap>` line is skipped as a comment while bash runs it: an evasion of the scanner |
| `scripts/gates/cm_feature_directive.sh`, `scripts/gates/cm_reporting_directives.sh` | engine source (`grep -vE '^[[:space:]]*#'`) before a project-literal leak check | yes | a literal after a VT/FF/CR-led "comment" is hidden from the leak check |
| `scripts/gates/cm_test_mock_pid_explicit_int.sh` | Python test files (`sed 's/^[[:space:]]*#.*$//'`) | yes, weaker | Python accepts SPACE, TAB and FF as indentation; VT/CR-led lines differ |
| `scripts/validation/enumerate_decision_mutants.py` (`is_comment`) | shell lines for mutant generation | yes, weaker | a misread line yields fewer mutants (coverage gap), not a hidden pass |
| `scripts/gates/cm_unreferenced_gate_bound_or_retired.sh` line 218 | seam code, presence of a reference | conservative | a hidden reference makes a gate look unreferenced (refusal), never a pass |
| `cm_escape_ratchet*.sh`, `cm_mutation_score_on_diff.sh`, `cm_first_refusal_observed*.sh`, `cm_git_hooks_installed.sh`, `cm_rule_binds_to_seam.sh`, `cm_unreferenced_gate_bound_or_retired.sh` (data), `gate_ledger.sh`, `lib_claim_ledger.sh`, `cm_version_increment_on_deploy.sh`, `enumerate_decision_mutants.py` (`read_ledger`) | project-owned data / config / ledger files | no | not executed by an interpreter; a misread comment changes a parse, it cannot hide code |

Proposed item text: "Census-style gates that drop comment lines before scanning source must read the file as its
interpreter does: shell as bytes split on LF with SPACE/TAB only, refusing (fail-closed) control bytes and Unicode
spaces in leading position; one shared helper, used by instrument_trap_scan, cm_feature_directive,
cm_reporting_directives, cm_test_mock_pid_explicit_int and enumerate_decision_mutants, each with a VT-led and a
CR-led needle row." Not fixed here: outside the CON-450 / CON-451 / CON-251 scope (section 11.4.293).

## FU-7 (new): computed program text

The censuses read the text of a literal `bash -c '...'` program as written. A program built with `$'...'` escapes
(for example `bash -c $'\r#;...'`) holds a CR only at run time. Measured 2026-11-17 (`runs/fu7_program_text_probe.txt`): after the canonical
line, `bash -c $'\r#;:'`, `bash -c $':'` and `bash -c ':'` are each refused by the safepath census (rc=1,
"bash runs text the census cannot see"); the class instrument does not contain a member for it. Proposed item text:
"add `$'...'` program-text members (CR, VT, NBSP escapes) to the class instrument and the F1 suite, and keep them
refused."

## FU-8 (new, pre-existing, outside this vehicle's diff): sweep_red golden-good fixture needs a gitignored file

`test_custody_sweep_red.sh` fails in a fresh clone (rc=1, 2 NOT ok: `proposal_golden_good_verified_hash.json`
derives REFUSED, and the discrimination needle). Root cause: the fixture's `backup_artifact_path`
(`qa-results/agent_custody_20260926/backup_worktrees/a17eb3df7db2f148a/tracked.patch`) is under `qa-results/`,
which `.gitignore` line 6 excludes, so only a checkout that already holds that file can pass. Measured: the same
two rows fail on the unmodified base e48ca38f (`runs/sweep_red_on_base_e48ca38f.txt`) and on the round-4 head; this
vehicle's diff touches neither the test, the fixture nor the oracle. The round-3 suite set did not contain this test (its "sweep_red", 17 ok, is
`test_sweep_review_record_subclauses_red.sh`); it was run here by mistake, and it is recorded because it fails. Proposed item text: "make the golden-good custody fixture
self-contained: commit its backup artifact under tests/fixtures (or build it in the test from a tracked input and
compute the hash at run time), with a needle that fails when the artifact is absent."
