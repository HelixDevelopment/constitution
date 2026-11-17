# Sync-all-upstreams, review round 12 — evidence pack

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Last modified | 2026-11-17T01:30:00Z |
| Status | gate-logic / unit class (§11.4.289(C)(2)), PROVISIONAL (§11.4.290); pending independent review |
| Base | `sync-r11` head `516207f2` (bundle `sync_upstreams_r11.bundle`, sha256 `b89a0b5a…`) |
| Review answered | `rev_sync_r11.FeRl/review/review_sync_r11.md` (RV11-1, RV11-2, RV11-3) |
| Roadmap item | `CON-PENDINGsync3` (the vehicle item; placeholder, see RV11-3) |
| Follow-ups | `CON-PENDINGsync1` (work-tree-only failed write), `CON-PENDINGsync2` (defaults per the 2026-11-14 decision) |
| Model / effort | fixer: Opus 5.5; effort UNKNOWN (§11.4.231(F.2)) |

## Findings and fixes

| Finding | Fix | RED (r11) | GREEN (r12) |
|---|---|---|---|
| RV11-1 DWIM upstream lookup | The upstream is resolved by `resolve_ref_exact()` (`for-each-ref`, exact refname, peel to a commit, malformed or duplicate = no answer). Structural fix for the class (4th recurrence of the name-lookup class): every object the engine names is `obj(<id>)` = `<id>^{commit}`; `check_object_names()` in `check_git_args` admits a CLOSED set of shapes for rev-parse / rev-list / merge-base / ls-tree / for-each-ref, and merge / checkout require `<id>^{commit}`. Found in the same enumeration: `checkout --detach <hex>` takes a local BRANCH named `<hex>` (measured, git 2.53). | `red/red_r11_new_checks.txt` (the new robustness checks on the r11 engine: 36 FAIL lines); `red/red_r11_unit.txt` (6 failing unit tests) | `green/green_r12_new_checks.txt` (59 PASS, 0 FAIL) |
| RV11-2 replace refs / grafts | `git_env()` ends with `env.update(OBJECT_VISIBILITY_PIN)`: `GIT_NO_REPLACE_OBJECTS=1`, `GIT_GRAFT_FILE=/dev/null` (after the scrub, so the caller's value never survives). Tests: robustness `objvis` with five shapes (replace ref, replace ref + caller `GIT_NO_REPLACE_OBJECTS=1` (the r11 regression), `core.useReplaceRefs=true`, `info/grafts`, caller `GIT_GRAFT_FILE`) plus a golden-false (unrelated blob replace still fast-forwards). The scrub test (the one AC09 hit) now asserts the pinned values. | same RED files (objvis shapes FAIL on r11) | same GREEN file |
| RV11-3 colliding CON ids | Every citation renamed mechanically: CON-423 -> `CON-PENDINGsync1`, CON-424 -> `CON-PENDINGsync2`, CON-425 -> `CON-PENDINGsync3` (18 replacements, see below). The r10 and r11 README hashes in their SHA256SUMS were regenerated (`sha256sum -c` passes). | — | `grep CON-42[345]` outside the tracker files: 0 |
| own | `obj()` / `_exact_obj()` matched a value with a trailing newline (`re` `$`); now `fullmatch`. Not exploitable (`check_git_args` refuses `\n` first); closed anyway. | `red/red_r12_obj_newline.txt` | `green/green_r12_obj_newline.txt` |

### RV11-3 citation sites (renamed in this commit)

`scripts/sync/sync_all_upstreams.py` (docstring, 1), `docs/qa/sync_upstreams_2026_11_15_r10/README.md` (1),
`docs/qa/sync_upstreams_2026_11_16_r11/README.md` (10), `docs/faq/sync_upstreams_faq.md` (1),
`docs/manuals/sync_upstreams_manual.md` (4), `docs/guides/sync_upstreams_user_guide.md` (1).
NOT renamed (engine-owned, never hand-edited): `docs/Issues.md`, `docs/Issues_Summary.md`, `docs/workable_items.db`
still hold the round-11 rows CON-423/424/425 of this branch. The lander drops those rows in the merge (main owns
those ids), mints three new items through `scripts/workable-items/bin/workable-items add` (dedupe search first,
§11.4.214), and replaces each `CON-PENDINGsyncN` with the minted id in the six files above, then regenerates the r10
and r11 SHA256SUMS. Commit trailers keep the placeholder spelling.

## Class-exhaustive enumeration (§11.4.276(C))

`class_inventory_refs.py <engine>` (AST + runtime). Control needles: a synthetic DWIM rev-parse site must be classed
LOOKUP and a synthetic `obj()` site exact; the known site commit_present/rev-parse must be found; the fabricated
subcommand `frobnicate` must not.

* r11 engine: FAIL (23) — 9 of 17 name-resolving sites are LOOKUP (`is_ancestor`, `count_range`, `commit_present`,
  `tree_gitlinks`, `evaluate_upstream`, `evaluate_pin`, `write_git` merge and checkout, `ignored_clobbers`), no exact
  lookup, the allow-list accepts 9 lookup shapes, and `git_env` pins nothing (`inv/refs_r11.txt`).
* r12 engine: PASS — 17 sites, 17 exact, 0 lookup; 18 allow-list probes; 7 env probes (`inv/refs_r12.txt`).
* `class_inventory_names.py` (the r11 inventory, copied with the classifier fix: a site is never safe by its text;
  semantic check 3 runs the ref classifier): r11 FAIL (10 unclassified/semantic, 1 stale), r12 PASS 58 sites
  (`inv/names_r11.txt`, `inv/names_r12.txt`).

### Environment influences on object lookup and ancestry

| Influence | Effect | Handling (r12) |
|---|---|---|
| replace refs (`refs/replace/*`, `core.useReplaceRefs`) | rewrites ancestry: can make L look like an ancestor of U | `GIT_NO_REPLACE_OBJECTS=1` pinned (the env var wins over the config; objvis `replace_config_on`) |
| `GIT_REPLACE_REF_BASE` | moves the replace namespace | scrubbed |
| grafts (`info/grafts`, `GIT_GRAFT_FILE`) | rewrites ancestry | `GIT_GRAFT_FILE=/dev/null` pinned (objvis `info_grafts`, `graft_file_env`) |
| shallow (`shallow` file, `GIT_SHALLOW_FILE`) | only removes edges: less ancestry, reported diverged | file honoured (safe direction); env scrubbed |
| alternates (`objects/info/alternates`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`) | content-addressed: adds objects, no ancestry change | file honoured; env scrubbed |
| `GIT_OBJECT_DIRECTORY`, `GIT_DIR`, `GIT_COMMON_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_NAMESPACE` | repository relocation | scrubbed (census 676 members, 0 unscrubbed) |
| `GIT_CONFIG_PARAMETERS` / `GIT_CONFIG_COUNT` | could set `core.useReplaceRefs` | scrubbed; the env pin wins anyway |
| object format (sha256 repositories) | 64-hex ids | `SHA_RE` / `EXACT_OBJ_RE` accept 40 or 64 hex |
| ref lookup rules (DWIM) | a tag/branch stands in for a ref; a branch named `<hex>` beats the object | exact-name rule (above) |
| commit-graph file | a corrupted graph can give wrong ancestry (git trusts it) | NOT neutralised; residual, UNCONFIRMED |
| `GIT_TEST_*` | git test-suite debug switches | NOT scrubbed; not shown exhaustive, UNCONFIRMED |

## Suites (run twice, identical summaries)

`sum_1.txt` = `sum_2.txt`, sha256 `ccbdbd80…7369475`. The full logs stay in the fixer's scratch (`syncfix12.zGcd/ev/suites_run1.txt` sha256 `1afd03563abfcf435a973d8bb97ab8025cec826b21e0a57b46f848a565ed5aab`, `suites_run2.txt` sha256 `61bd68def993896776665e3bbc64923925603940ca3e1f441c11b30f5b81ff87`): they are not committed because a redaction test prints its fabricated token-shaped sample, which a history secret scan would flag.

| Suite | r11 | r12 |
|---|---|---|
| unit | 133/0 | 139/0 |
| integration | 149/0 | 149/0 |
| e2e | 24/0 | 24/0 |
| full-automation | 34/0 | 34/0 |
| security | 83/0 | 83/0 |
| determinism | 15/0 | 15/0 |
| ui | 26/0 | 26/0 |
| hardening | 119/0 | 119/0 |
| chaos | 58/0 | 58/0 |
| perf | 13/0 | 13/0 |
| faults | 21/0 | 21/0 |
| robustness | 1217/0 | 1276/0 (+ ref_exact, checkout_exact, objvis) |

Gate `cm_sync_upstreams_ff_only.sh` PASS (oracle: 30 rows = 30 sites; 26 accepted shapes; forbidden shapes refused,
now including bare ids, ref names, lookup patterns, the `+` check alone, and merge/checkout options with an exact
object). Gate meta-test PASS, 104 cases (new: R12-MERGE-BARE-ID, R12-CHECKOUT-BARE-ID, R12-NO-OBJECT-NAMES,
R12-OBJ-BARE, R12-UPSTREAM-DWIM, R12-EXACT-ANY-PATTERN, R12-NO-PIN; MERGE-ANY / CHECKOUT-ANY / R1-MERGE-FF
re-anchored). Census PASS (676 members, 0 unscrubbed). `tests/test_git_env_class.sh`: 142 passed, 0 failed, 1 skipped.

## Mutants

See `mutants/mutants_r12.txt`. Table: 369 rows (343 + AC01-AC11, CX1, CX2 verbatim + AD01-AD13 own); every anchor
occurs exactly once. M04, M05, M38, R1 re-anchored (same meaning). EQUIVALENT added: AC10 (proof: every git spawn
goes through `proc_run_git` with `env=git_env(...)`, which drops a superset of the popped names and sets the pin)
and CX1 (control).

RE-RUN in this round (changed regions only): M04, M05, M38, R1, AB14, AC01-AC11, CX1, CX2, AD01-AD13 (31).
Result: 31 mutants, 29 killed, 2 equivalent (AC10, CX1: both ran every suite of their list, 686 s and
706 s, and survived as expected), 0 survived, 0 harness errors. CX2 (must die) was killed. AD12 died in the
robustness checks (the merge shape refusal is behavioural there), the others in the unit suite.
NOT re-run: the other 338 rows of the table (about 5.5 h; scope bound). Their anchors are verified to apply
exactly once, and every suite they use passes on r12, but whether each still dies was not measured this round.
Note on AC09 / AB14: with the pin, dropping the two names from `_SCRUB` no longer changes git's environment
(the pin overwrites them); the mutant now dies only on the parity assertion with `CL_GIT_SCRUB_VARS`
(`test_engine_scrub_covers_the_canonical_list`), not behaviourally.

## Limits (§11.4.6)

Real git against local bare repositories; no network, no forge. Commit-graph corruption and `GIT_TEST_*` are
residuals (table above). The merge onto current main was not re-done in this round (lander's step).
