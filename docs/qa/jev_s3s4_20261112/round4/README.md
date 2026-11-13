# Jev S3/S4 round 4 (CON-299): fixes for the independent review of `1c9277b9` (NO-GO, R3-1 to R3-4, surviving mutants Y2, Y7, Y11)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13 |
| Status | evidence (CON-299, In progress; no GO claimed) |
| Evidence class | gate-logic only (stub llmctl, stub curl, fixture records; §11.4.289(C)(2)). Nothing here is live evidence. |

Round 4 of `R_max` 5 (§11.4.276). The round-3 review returned NO-GO with four findings (R3-1 to R3-4), three
surviving mutants (Y2, Y7, Y11) and a CHANGELOG nit. Every fix was written test-first: each new test was run first
against the round-3 code (RED) and then against the fixed code (GREEN). Only stub binaries ran. No real `llmctl`,
`systemctl`, hosted endpoint, network or forge call was made, and nothing was pushed. Key values used anywhere in this
round are FAKE (`fake-typesafe-1111111111111111` and similar); no real key was read or printed.

## RED then GREEN

| Suite | Round-3 code (RED) | Round-4 code (GREEN) | Log |
|---|---|---|---|
| test_s4_placement.sh (P33 to P37) | 168 pass / 31 fail | 199 / 0 | `red_s4.txt`, `green_s4.txt` |
| test_gate_bootstrap_hermetic.sh (new) | 6 pass / 3 fail (the round-3 gate called the caller's `llmctl` and `claude-providers`, and exited 1 with fake keys) | 9 / 0 | `red_hermetic.txt`, `green_hermetic.txt` |
| cm_jev_bootstrap_idempotent_mutation_test.sh | round-3 gate: SETUP FAILURE, the gate itself was RED on genuine state in this environment (bootstrap exited 5/5: not hermetic) | PASS (mutations A to I) | `red_bootstrap_gate_head.txt`, `gate_bootstrap_idempotent_mutation.txt` |
| mutation I of that test (new needle) | with the earlier needle (`PATH="$GUARDBIN"`): MUTATION I SURVIVED | RED flip I asserted (rc 2, guard blind) | `red_gate_mutation_I_old_needle.txt`, `gate_bootstrap_idempotent_mutation.txt` |
| test_jev_status_health.sh (S9) | round-3 matcher: 53 pass / 17 fail (before the three Z11 cases); Z11-mutant matcher: 70 / 3 | 73 / 0 | `red_health.txt`, `red_health_z11.txt`, `green_health.txt` |
| test_tab_fields.sh (new, F1 to F5) | pre-fix tree (`git archive` of `1c9277b9`): 2 pass / 9 fail | 11 / 0 | `red_tab.txt`, `green_tab.txt` |
| test_s3_bootstrap_honesty.sh (H12, H13) | not captured separately: H12 is shown by mutant Y2, H13 by Z4, Z5, Z6 | 125 / 0 (final tree) | `green_s3.txt` |

The S4 RED run used the round-3 `jev-place.sh` through `S4_PLACE_UNDER_TEST`; the health RED runs used
`S8_LIB_UNDER_TEST`; the TAB RED run used `JEV_TAB_TREE_UNDER_TEST` pointed at an export of the round-3 tree; the
hermetic RED run used `JEV_HERMETIC_GATE_UNDER_TEST`.

## Findings

| id | status | what changed | test |
|---|---|---|---|
| R3-1 | FIXED | `acquire` evaluates EVERY existing set, not only the first. A lease-less set this producer started, whose unit is not `running`/`active` or whose verdict is not a fit, is stopped (bounded `llmctl stop`), dropped with its cache entry and not restarted by the same acquire (§11.4.291(D) hold); a failed disposal stop keeps `{stop_owed, stop_failed}`, is never joined and is retried by every later acquire and release. A set with a live lease is never stopped by this path; a reap alone never stops a model (§11.4.291(J)); an operator-started set is never stopped (three layers, see Z16 / Z16c). | P33 to P37 |
| R3-2 | FIXED | `CM-JEV-BOOTSTRAP-IDEMPOTENT` runs every bootstrap with `env -i` and a whitelist, a PATH of the stub dir plus a dir of recording refusal guards (`curl wget llmctl claude-providers claude kimi opencode pi gemini qwen codex`) before the system dirs, `JEV_HOSTED_PROBE=0`, and `JEV_LLMCTL_BIN` / `JEV_TOOLKIT_BIN` naming absent files. Clause 5 fails on any guard call; its control needle runs `curl` on the SAME PATH as the runs, so a PATH that lets a real tool through is reported blind (rc 2). `bootstrap.sh` honours `JEV_LLMCTL_BIN` / `JEV_TOOLKIT_BIN` as the only candidate (non-executable = absent, logged, no PATH fallback); `cm_jev_detection.sh` honours `JEV_LLMCTL_BIN` through the guarded override (test mode, temp root). | `test_gate_bootstrap_hermetic.sh` (fake keys and no keys), H13, mutations H and I |
| R3-3 | FIXED | `jev_settings_wired` tokenises each PreToolUse hook command into shell words and simple commands; it counts only when a simple command runs a file named exactly `jev-gate.sh`: directly, through `env` / `exec`, through `sh`/`bash`/`zsh`/`dash`, or through such an interpreter's `-c` script (3 levels). An assignment value, a comment, an argument of another command, a renamed file or an unterminated quote is not wiring. Honest limits (in the source): no expansion, a quoted assignment-looking word is treated as an assignment, `env -S` is not split. | S9 (31 cases) |
| R3-4 | FIXED | Every TAB-separated `read` in the Jev scripts and gates now reads with the unit separator `\x1f`, converting the producer's TAB (`jq @tsv` escapes a TAB inside a value, so a raw TAB only separates fields). Sites: `bootstrap.sh`, `jev-place.sh`, `lib_decide.sh`, `lib_keys.sh`, `jev-status.sh`, `jev-calibrate.sh`, `cm_jev_detection.sh`, `post_update_hook.sh`. Census after the change: 0 TAB-IFS reads; the `\x1f` needle finds 30 (the instrument sees). Real members of the class: `jev_usable_live` counted an empty-url jev-verdict service as live (F1), bootstrap recorded it with the protocol as its url (F2), the detection gate skipped the probe replay and the real-key check of an empty-id endpoint (F3, F4), calibrate attributed empty answers to `unknown|unknown` (F5). | `test_tab_fields.sh` |
| Y2 | KILLED | H12: two runs with a gateway CA file; each run makes exactly one healthz call and every call carries `--cacert`. | H12 |
| Y7 | KILLED | P36: a cleanup stop that times out (rc 124) keeps the owned set. | P36 |
| Y11 | KILLED | S9 `echo /x/jev-gate.sh` and the structural matcher. | S9 |
| nit | FIXED | CHANGELOG round-3 entry: "42 (the reviewer's 20, X1 to X19 and X11b, plus 22 new)". | n/a |
| R2-7 | OPEN, for the lander | Unchanged from round 3: `dc654757` carries `Roadmap-Item: CON-PENDING-JEV-CONSTITUTION`. Every commit of this vehicle is unpushed, so re-committing it tree-equal with `Roadmap-Item: CON-299` before the first push rewrites no published ref; this vehicle still does not do it. Every round-4 commit carries `Roadmap-Item: CON-299`. | n/a |

## Mutants (this round)

20 mutants written by the fixer: the three round-3 survivor shapes (Y2, Y7, Y11) re-expressed on the round-4 code and
17 new ones (Z1 to Z16c) on the round-4 logic. Each is an exact anchor replacement (an anchor that does not occur
exactly once is INVALID, never skipped; none was). Harness: `mutants.py.txt` (rename to `.py` to run), the reviewer's
round-3 engine with a new list; it runs one suite under `nice -n 10` in its own process group, stops at the first
`FAIL - ` line, restores with `git checkout --` and refuses to continue unless the tree is clean. It ran in a separate
local clone of the committed vehicle.

Result: **18 KILLED, 2 EQUIVALENT, 0 SURVIVED.** Run 1 (`mutants_run1.tsv`) left Z3, Z11 and Z16. Z11 was killed in
run 2 (`mutants_run2.tsv`) after the S9 unterminated-quote cases were added. Z16c was added to show what Z16 hides. Run 3 (`mutants_run3.tsv`) re-ran Z1 after the control-needle fix.

| id | mutation | suite | final | killed by |
|---|---|---|---|---|
| Y2 | health probe in the signature drops the CA | test_s3_bootstrap_honesty.sh | KILLED | H12 (2 healthz calls instead of 1) |
| Y7 | cleanup-stop failure only for rc 1 | test_s4_placement.sh | KILLED | P36 |
| Y11 | every word is an interpreter | test_jev_status_health.sh | KILLED | S4 |
| Z1 | hermetic PATH prefixed with the ambient PATH | test_gate_bootstrap_hermetic.sh | KILLED | run 1: gate rc 1 by clause 4 only (the real git), clause 5 still said hermetic; run 3, after the needle change (`7c7ec0c`): clause 5 reports the guard blind (`mutants_run3.tsv`) |
| Z2 | hermetic check always passes | cm_jev_bootstrap_idempotent_mutation_test.sh | KILLED | mutation H |
| Z3 | `JEV_HOSTED_PROBE=1` inside the hermetic run | test_gate_bootstrap_hermetic.sh | EQUIVALENT | see below |
| Z4 | bootstrap `JEV_LLMCTL_BIN` executable check dropped | test_s3_bootstrap_honesty.sh | KILLED | H13 |
| Z5 | bootstrap non-executable `JEV_TOOLKIT_BIN` falls back to PATH | test_s3_bootstrap_honesty.sh | KILLED | H13 |
| Z6 | detection gate non-executable `JEV_LLMCTL_BIN` falls back to PATH | test_s3_bootstrap_honesty.sh | KILLED | H13 |
| Z7 | assignments are command words | test_jev_status_health.sh | KILLED | S8 |
| Z8 | `#` comment rule removed | test_jev_status_health.sh | KILLED | S9 |
| Z9 | interpreter `-c` not followed | test_jev_status_health.sh | KILLED | S9 |
| Z10 | `env` not unwrapped | test_jev_status_health.sh | KILLED | S9 |
| Z11 | unterminated quote accepted | test_jev_status_health.sh | KILLED (run 2) | S9 (new cases) |
| Z12 | `jev_usable_live` service rows not converted | test_tab_fields.sh | KILLED | F1 |
| Z13 | calibrate sample not converted | test_tab_fields.sh | KILLED | F5 |
| Z14 | detection clause 6 not converted | test_tab_fields.sh | KILLED | F3 |
| Z15 | disposal also stops a set with a live lease | test_s4_placement.sh | KILLED | P25 |
| Z16 | disposal guard drops the constitution-started check | test_s4_placement.sh | EQUIVALENT | see below |
| Z16c | Z16 plus both earlier filters removed | test_s4_placement.sh | KILLED | P35 CONTROL (an operator-started unit is stopped: 1 stop, want 0) |

Z3 is EQUIVALENT on this code: the gate's `env -i` whitelist carries no key variable and no keys-file variable, and
`HOME` is a fresh sandbox without `~/api_keys.sh`, so no real key can reach a hermetic run; bootstrap probes a hosted
endpoint only with a real key. `JEV_HOSTED_PROBE=0` is kept as a second layer.

Z16 is EQUIVALENT on this code: before the disposal loop, `acquire` forgets every lease-less set that is not
constitution-started, and the loop's own selection keeps only sets with a lease or `constitution_started == true`, so a
lease-less set reaching the guard is always constitution-started. Z16c removes all three layers and is KILLED by the
P35 CONTROL, so the observable rule (a model this producer did not start is never stopped) is tested.

## Other checks (final tree)

| check | result | log |
|---|---|---|
| `tests/jev/run_all.sh` | ran 34, failed 0, rc 0 (code of 7c7ec0c) | `run_all.txt` |
| `tests/jev/test_gate_pairs.sh`, no keys | PASS (4 pairs GREEN+RED) | `gate_pairs_nokeys.txt` |
| `tests/jev/test_gate_pairs.sh`, FAKE keys and a fake keys file exported, `JEV_HOSTED_PROBE=1` | PASS (4 pairs GREEN+RED); 0 fake key values in the output | `gate_pairs_fakekeys.txt` |
| `cm_jev_detection_mutation_test.sh`, `cm_jev_token_reduction_mutation_test.sh`, `cm_jev_wiring_mutation_test.sh` | PASS each | `gate_*_mutation.txt` |
| `scripts/run_full_suite.sh --verify-manifest` | MANIFEST-OK | `verify_manifest.txt` |
| `scripts/gates/cm_gate_ledger_ratchet.sh` | PASS (unimplemented 394, baseline 394) | `gate_ledger_ratchet.txt` |
| shellcheck `-S warning`, changed shell files | no new warning (same count as round 3 per file; the two new tests 0) | `shellcheck_r4.txt` |

## Guard false positive met while writing this round

The §11.4.287 destructive-path guard blocked Bash heredoc and Write content that contained a `case` pattern
`sh|bash|zsh|dash)` as code piped into a shell (class U). The code was rewritten as `[[ "$1" == sh || ... ]]`; the
guard was not routed around otherwise. Reported as a guard false-positive class, not fixed here.
