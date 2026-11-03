# Canon self-scan triage: dangerous-combination and oracle-strategy gates

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-31 |
| Status | triage record; no gate edited, no defect fixed; linked from README (design plans list) |
| Last modified | 2026-10-31 |
| Source | commit 39ad2ce (scanner gates scan the canon itself by default) |
| Base | main at 7c0bcc9 |

Evidence logs (all under `/home/milosvasic/.cache/claude-tmp/`): `dcfc_first_party.log`, `oracle_first_party.log`, `oracle_default.log`. "PROVEN" means measured in this session with the command shown. Anything else is marked UNCONFIRMED.

## 1. How the gates were scoped (no gate edited)

Both gates take their prune list from an environment variable, so no wrapper was needed:

```
DANGEROUS_COMBO_EXCLUDE=".git node_modules vendor .venv __pycache__ scripts/gates out build dist submodules" \
  nice -n 15 scripts/gates/cm_dangerous_combination_fail_closed.sh --root .
ORACLE_GUARD_EXCLUDE="<same list>" \
  nice -n 15 scripts/gates/cm_oracle_strategy_named_and_independent.sh --root .
```

The only addition to the default list is `submodules` (every submodule here is third-party or a hub engine). `scripts/gates` is excluded by the gates' own default, so the gates are never scanned by themselves. No other vendored directory exists outside `submodules/` (a find for `third_party`, `vendor`, `node_modules` returned nothing). Run time: dangerous-combination 33.7 s, oracle 0.4 s.

## 2. CM-DANGEROUS-COMBINATION-FAIL-CLOSED on first-party source

Result: exit 1, 152 hits, all in Python (88 "silent default return", 64 "swallowed exception"). 173 `.py` files are in scope. Zero hits lie under `submodules/`.

Control needles (PROVEN, scratch root): a file with `except Exception: pass` is flagged; a file with `except Exception as e: raise ... from e` is not; a JS `catch (e) { }` is flagged. So the instrument sees both shapes and does not flag a clean handler. Non-Python findings are zero, and the JS needle shows the zero is not blindness for that shape.

Where the hits are (file counts from the log): `scripts/fastcycle` 83, `scripts/codegraph` 23, `scripts/decisions` 12, `scripts/constitution_ext` 10, `scripts/credscan` 7, `scripts/label-sync` 5, `scripts/hooks` 5, `scripts/catalog-engine` 4, `scripts/anchors` 2, `tests/extensions` 1, `progressive/validate_tokens.py` 1.

### Classification

Exception type: 135 narrow (OSError 63, ValueError 8, `(OSError, ValueError)` 8, subprocess timeout shapes 9, ProcessLookupError 6, FileNotFoundError 6, sqlite3.Error 6, others) and 17 broad (`Exception` 16, `BaseException` 1). All 17 broad ones were read in context.

Bucket counts (heuristic bucketing by try-body keywords; the five bucket counts sum to 152):

| Bucket | Count | Verdict |
|---|---|---|
| A. test code (`except X: pass` after `assert False`, test cleanup) | 5 | false positive (see below) |
| B. best-effort reporting of an error that was already surfaced (`write_doc`/`write_report_atomic` of an internal-error report, `flush`, stderr emit) | 10 | acceptable with reason |
| C. idempotent cleanup / liveness (`unlink`, `rmdir`, `close`, `killpg` ProcessLookupError, `waitid` ChildProcessError) | 34 | acceptable with reason |
| D. read or probe helper returning a sentinel (`None`, `[]`, `{}`, `False`, a reason string) | 80 | acceptable with reason, with a caller check (below) |
| E. optional read where failure leaves a default (`pass`) | 23 | acceptable with reason |
| TRUE defects | 0 | none confirmed |

Why the gate fires although nothing is wrong:

- The gate's own header says it implements only the literal shape half of §11.4.252 and "CANNOT honestly claim" to prove that a path combines two dangerous capabilities. It therefore flags a handler even in a pure parse or probe helper that has no mutation, credential or side effect. Most of the 152 are such helpers (`open` → `OSError` → `None`).
- Test idiom (A): `try: f(); assert False; except ExpectedError: pass` is how the expected exception is asserted (`scripts/anchors/tests/test_anchor_lib.py:29,374`). Nothing is swallowed, because the `assert False` raises if the exception does not occur.
- Sentinel returns (D) hand the caller a distinguishable value. Where the direction matters, the sentinel is the safe one. Examples read in context: `ext_engine.py` lstat failure → `False` for "is a safe directory/nonce/marker" checks (fail-closed); `custody_sweep.py:405-409` PermissionError → "group exists" (documented as the safe default); `cycle_report.py:443` unparseable instant → `True` ("cannot be shown to precede the cutoff", documented); `guard-destructive-paths.py:2769` → `True`, `:3740` → `2` (block); `validate_tokens.py:31` tiktoken missing → `None`, and the caller prints `UNCONFIRMED` and sets failure (fail-closed, visible); `codegraph_mcp_health.py:607` import failure → `src=None`, and the report then says "installed schema unknown".
- Best-effort cleanup after the real work (C) must not mask the primary result. `ProcessLookupError` on `killpg` means the group is already gone, which is the goal.

Items worth a reviewer's second look (not defects; UNCONFIRMED risk, none fixed here):

1. `scripts/fastcycle/closure/reopen_rate.py:141` and `scripts/fastcycle/cycle/select_sample.py:489`: `except Exception: return False` around a timestamp subtraction. A malformed `created_at` silently makes a pair "not a reopen pair", which can undercount a metric. Narrowing to `(KeyError, ValueError, TypeError)` and counting the skips would be the repair. No dangerous capability is involved, so it is a measurement-honesty nit (§11.4.201(6)), not §11.4.252.
2. `scripts/decisions/decisions_engine.py:503` `is_locked()` returns `False` for a key `spec_for` refuses. Callers at lines 510 and 583 validate the key shape first, so the effect is not shown to matter. UNCONFIRMED whether an unknown but well-formed key can reach a store.
3. `scripts/hooks/guard-destructive-paths.py:1983,1990`: `except Exception: return None` around `os.path.realpath`, meaning "no extra resolution". `realpath` effectively raises only `ValueError` (embedded NUL). The direction is the guard's cautious one, but a guard is the place where a silent default deserves a comment. No change made.

### Suggested gate repair (a separate work item, not done)

- Do not flag `except X: pass` inside a `try` that contains `assert False` or `pytest.raises`-style expectations (golden-FALSE carrier).
- Report narrow-exception sentinel returns as a lower class unless the enclosing function also contains a mutation, credential or exec call; this is the "combination" half the header says it cannot do. A cheap proxy is a function-level capability scan.
- Add `submodules` (or the `third_party: true` paths from `helix-deps.yaml`) to the default prune list; today the default run descends into every third-party tree and takes more than 15 minutes.
- Consider scanning `scripts/gates` with the gate itself, or state why not.

Fixed in this pass: nothing. No finding was both a confirmed defect and small enough to change safely.

## 3. CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT

Result with default scope (cwd = canon, scanning the canon plus every submodule): exit 1, 6759 unannotated test functions. With third-party removed: 414.

| Tree | Unannotated | Class |
|---|---|---|
| `submodules/llmctl` | 3122 | third-party hub engine |
| `submodules/watch-skill` | 1603 | third-party |
| `submodules/repo-qa` | 922 | third-party |
| `submodules/verify` | 299 | third-party |
| `submodules/claude-video` | 188 | third-party |
| `submodules/agentic-validation` | 129 | third-party |
| `submodules/donespec` | 54 | third-party |
| `submodules/containers` | 20 | third-party |
| `submodules/open_design` | 6 | third-party |
| `submodules/claude_toolkit` | 2 | third-party |
| subtotal submodules | 6345 | |
| `tests/extensions/test_unit.py` | 213 | first party |
| `scripts/credscan/tests/test_credscan.py` | 67 | first party |
| `scripts/codegraph/tests/*` (3 files: `test_fk_cascade_probe.py` 42, `test_scope_exceptions.py` 13, `test_owed_report.py` 12) | 67 | first party |
| `scripts/anchors/tests/*` (11 files; largest `test_anchor_lib.py` 21) | 67 | first party |
| subtotal first party | 414 | |
| total | 6759 | |

6345 + 414 = 6759, so the breakdown is complete. Of the 6759, 6756 are "no annotation" and 3 are "strategy not in the closed set" (`RAW`, `THE`, `DEEPSEEK_V`).

First-party annotation coverage is 0 of 414 (`grep -ci 'oracle:'` over the four first-party test trees finds one prose comment, in `test_query_us2.py:208`, and no valid annotation).

### Is the annotation grammar realistic?

- Python only: the gate globs `*test*.py`. The canon's own tests are largely shell: 553 `test_*.sh`/`*_test.sh`/`*mutation_test.sh` files outside `submodules/` against 30 Python test files. So a green result would cover a small share of first-party tests. (Counts from `find`; the Python figure counts files named `test_*`/`*_test.py`.)
- The grammar is a per-function comment within 3 lines of the `def` or a docstring line `oracle: <STRATEGY>`. For one function that is cheap. For 414 existing functions it needs a human judgement per test, because the strategy is a claim about independence of the expected value, not a label.
- False-positive in the matcher: any prose `oracle: <word>` is read as an annotation with a strategy. `scripts/anchors/tests/test_query_us2.py:182` ("Independent oracle: raw grep") reports `RAW` as an unknown strategy, and the two submodule hits are the same shape. So three of the failures are wrongly worded matches, not unannotated tests.
- It checks presence and closed-set membership only; independence (the real point of §11.4.245) stays reviewer territory, as the gate header states. Adding 414 annotations by hand would make the number green without improving oracle quality, which is exactly the "annotation theatre" risk.

### Staged adoption plan (ratchet, per §11.4.224(E) / §11.4.135 style)

The repo already has the pattern: `scripts/gates/cm_zero_findings_monotone_ratchet.sh` (snapshot ceiling, `<=` check, new class implicitly 0), `escape_ratchet_baseline.txt` and `gate_ledger_baseline.txt`. The initial ceiling value is an operator decision (§11.4.66); the escape-ratchet baseline file already documents why an agent must not invent it.

1. Scope first. Default-exclude third-party paths (via `helix-deps.yaml` `third_party: true`, or `submodules`). That removes 6345 of 6759 and is not a loosening: the canon does not own those tests. Each owning repository adopts the gate itself.
2. Fix the matcher: require the annotation form `oracle: <TOKEN>` where the token is a single word followed by end of line or `#`, or anchor to a leading comment/docstring line. Add golden-FALSE fixtures for the prose carrier (`Independent oracle: raw grep`).
3. Ratchet baseline of 414 (first-party) as the checked-in ceiling, recorded per file so a new unannotated test in an already-counted file still fails (per-file ceiling, not only a total). New test files start at 0. A decrease lowers the ceiling.
4. Rule for new and modified tests only: any test function added or changed after the baseline must carry a valid annotation (diff-scoped check). This stops the count growing without a mass edit.
5. Burn down by risk, not alphabetically: start with the gate and hook tests that guard safety paths, then `scripts/anchors/tests` (67), then `scripts/credscan/tests` and `scripts/codegraph/tests`, last `tests/extensions/test_unit.py` (213, one file). A sensible pace is per file, each annotation reviewed for an independent source (spec, reference implementation, invariant) rather than copied from the code.
6. Decide separately whether the 553 shell tests are in scope; that needs a shell-aware extractor and its own control needles. Until then the gate's PASS must be reported as "Python tests only".

## 4. Honest boundaries

- Bucketing in section 2 is by keyword on the try-body text; the split between B, C, D and E could differ by a few items under a stricter reading. The totals (152; 135 narrow, 17 broad) are exact counts from the gate log. The verdict "no confirmed defect" rests on reading the 17 broad handlers and a sample of narrow ones in context, not on reading all 135 narrow handlers' callers. UNCONFIRMED: that no caller of a sentinel-returning helper mishandles `None`.
- The scoped runs excluded `scripts/gates`, so the gates and their mutation tests were not scanned.
- Nothing was committed or pushed. The working tree already contained unrelated modifications by other sessions; this pass touched only this file and one README link.

## 5. Follow-up: the three "reviewer's second look" items, investigated (2026-10-31)

Each was reproduced on the real code first, then decided from the evidence.

1. `reopen_rate.py:141` and `select_sample.py:489` (`except Exception: return False` around the Opened-to-closure `created_at` subtraction): **TRUE DEFECT (silent metric distortion)**. RED: with NB-001's closure `created_at` set to `not-a-timestamp` in the negative-control fixture, `reopen_rate.py` exited 0 with no message and reported Bug `closed` 3 / rate 0.333333 instead of `closed` 2 / 0.0 (the retroactive item is silently counted as an ordinary closure). Fix: a tri-state `retroactive_state()` (`retroactive` / `normal` / `unparseable`) in both tools, exception narrowed to `(KeyError, ValueError, TypeError, AttributeError)`; the boolean functions keep their signature and meaning (parity test S7 still holds). `reopen_rate.py` still counts the item (retroactivity cannot be proven) but lists it under `unparseable_timestamps` (per type and overall) and warns on stderr; `select_sample.classify_exclusions` excludes it with the explicit reason `unparseable-timestamp (...)` because a duration sample cannot rest on a corrupt timestamp. A well-formed export produces byte-identical output (no new key). Tests: `scripts/fastcycle/tests/test_unparseable_timestamp_regression.sh`. The mutant anchor in `test_select_sample_r5_regression.sh` (SS_N3) was moved to the new line. Separate finding, not fixed: a list or dict `created_at` crashes `reopen_rate.py` earlier, in `dedup_history` (`TypeError: unhashable`), with a traceback and non-zero exit (loud, so not silent).
2. `decisions_engine.py` `is_locked()` False for a refused key: **ACCEPTABLE**. Evidence: `drop_locked({'bogus.key':1})` keeps the key, but every input to it was validated first (`validate_map`, `check_key`), and `dump_file` with an unknown key raises `Refused` through its round-trip parse, writing nothing. Returning `True` would instead make `drop_locked` silently discard invalid input, the worse direction. No behaviour change; a comment records the reason and `tests/decisions/test_is_locked_contract.sh` pins it (with a mutation that removes the guards and is detected).
3. `guard-destructive-paths.py` `except Exception: return None` around `realpath`: **TRUE DEFECT, in a neighbouring place; the handler itself was benign**. The `ValueError` it swallowed comes from an embedded NUL, and the guard never analysed NUL-bearing text the way a shell reads it. Measured: `printf 'echo ho\0me' | bash` prints `home` (bash drops NUL on stdin), and the guard returned 0 for `rm -rf /ho\u0000me` in a Bash payload and in a Write of a script (should block, class P). Fix: `run()` analyses the original text and the NUL-stripped text; the two `realpath` handlers are narrowed to `(ValueError, OSError)` so any other exception reaches `main()`'s fail-closed block. Tests: `scripts/hooks/test_guard_nul_regression.sh` (block cases, benign NUL allowed, injected fault fails closed, two paired mutations). Honest limit: the Bash tool itself cannot carry a NUL in argv; the reachable paths are script content (Write/Edit, heredoc) later fed to a shell on stdin.

## 6. Note 2026-11-01: third-party prune narrowed (operator decision)

Operator decision (2026-11-01, interactive answer, relayed): `scripts/lib/third_party_prune.sh` (used by `cm_oracle_strategy_named_and_independent.sh` and `cm_dangerous_combination_fail_closed.sh`) prunes ONLY helix-deps.yaml deps marked `third_party: true` (their `path:`, else `submodules/<name>`) plus the directory names `third_party` and `site-packages`. It no longer prunes every `.gitmodules` path, so own-org submodules (for example `continuum`, `containers`) are scanned. Hostile-path handling is unchanged. The statement in section 1 that the default prunes every `.gitmodules` path is superseded by this note; the earlier text is left as written. Counts before and after on the canon root, and the consequence that findings now appear in own-org submodules, are in the report of the change (they are measured, not hidden or annotated). Tests: `scanner_gate_false_positive_repairs_test.sh` (own-org scanned, third_party:true pruned, submodule absent from helix-deps scanned, lib prune list exact) and its mutation test (mutants m14 to m17).

## 7. Note 2026-11-01: nested third_party marking, and what it did not change

`scripts/lib/third_party_prune.sh` now also reads each own-org (not `third_party: true`) submodule's own `helix-deps.yaml` (submodules/* directories and non-third_party dep paths, depth <= 3, symlinks never followed) and emits `<submodule path>/<dep path or submodules/<name>>` for its `third_party: true` entries, with the same hostile-path validation (validated on the raw path before prefixing, so an absolute path cannot become relative). Tests: repair test nested block and mutants m18 to m22.

Measured effect on the canon root: NONE. oracle `--strict` total 6753 before and after; dcfc 815 hits, 612 s before and after. Cause (read from the trees): `submodules/llmctl/helix-deps.yaml` marks only `superspec` third_party; `llama.cpp` and `colibri` (in its `.gitmodules`) are not listed at all, so no marking exists to honour. Per-submodule oracle hits: llmctl/submodules/colibri 2528, watch-skill 1603, repo-qa 922, verify 299, llmctl 299, llmctl/submodules/llama.cpp 295, claude-video 188, agentic-validation 129. The five last-named top-level ones (watch-skill, repo-qa, verify, claude-video, agentic-validation) are third-party URLs absent from the ROOT `helix-deps.yaml`. Needed (not done here; outside the files this change may touch): upstream llmctl must list llama.cpp and colibri with `third_party: true`, and the root manifest should list/mark the five. Whether a root-level override for nested trees is allowed by the operator decision is UNCONFIRMED and was not added.

`--write-baseline` refuses to RAISE `config/oracle_ratchet_baseline.txt` (by design), so the baseline stays at 414 and the default ratchet run now fails on the newly scanned own-org/unmarked submodules until they are marked or the operator decides how to adopt the debt.

## Addendum 2026-11-01 — helix-deps.yaml third-party entries

Added `third_party: true` entries (ref = recorded gitlink, licence read from each tree's LICENSE) for watch-skill (MIT), repo-qa (Apache-2.0), verify (MIT), claude-video (MIT), agentic-validation (MIT) and, via explicit `path:`, the llmctl-nested colibri (Apache-2.0) and llama.cpp (MIT) so `cm_third_party_prune_paths` prunes them. Oracle strict total from a foreign cwd fell 3612 -> 789 with the nested entries. Still absent from the manifest (external per .gitmodules, not added): verification, repo-proof, donespec, skill-doctor, verfix, MVT, wave-dpctf, mcp-audio-tweaker, polyscreen-mcp, video-quality-mcp. `CM-HELIX-DEPS-REF-MATCHES-GITLINK` only reads root `.gitmodules`, so the two nested entries read BLIND there (continuum DRIFT is pre-existing). [Superseded by the "Addendum 2026-11-01 (2)" below: the "still absent" list and the nested-entries-read-BLIND statement no longer hold; see that addendum.]

## Addendum 2026-11-01 (2) — eight more third-party entries, continuum pin, nested-path gate

- Root `helix-deps.yaml` now also lists, as `third_party: true` at the recorded gitlinks, with the licence re-read from each tree's file: verification (MIT, LICENSE), repo-proof (Apache-2.0, LICENSE), donespec (MIT, LICENSE), skill-doctor (Apache-2.0, LICENSE), verfix (Apache-2.0, LICENSE.md), MVT (Apache-2.0, LICENSE; COPYING also present), mcp-audio-tweaker (MIT, LICENSE), polyscreen-mcp (MPL-2.0, LICENSE). None of the eight URLs is vasic-digital/HelixDevelopment (checked in `.gitmodules`). NOT added, operator decision needed: wave-dpctf (has a LICENSE file whose type was not confirmed by this pass) and video-quality-mcp (no LICENSE file; licence not determinable from the tree). Both stay scanned and unmarked.
- continuum: the manifest ref `9d95651` was stale; the recorded gitlink is `213ad07`, set deliberately by commit 02504a2 (genericised test literals) on top of 9d95651. The manifest ref was updated to `213ad07`.
- `CM-HELIX-DEPS-REF-MATCHES-GITLINK` now resolves manifest entries with a nested `path:` through the parent submodule (`git -C <parent> ls-tree <parent-gitlink> -- <rest>`) instead of reporting BLIND. Test first: three new fixtures in the mutation test were RED (exit 2 where 0 and 1 were required), then GREEN; a mutant reading the wrong ls-tree field is killed.
- Measured after the change (from a mktemp cwd): oracle `--strict` total 735 (was 789): llmctl 299, tests/extensions 213, scripts/credscan 67, scripts/codegraph 67, scripts/anchors 67, containers 20, claude_toolkit 2. Default ratchet: total=735, 19 files over baseline, 0 new/modified unannotated functions, FAIL. dcfc on the canon root: 264 hits (265 FAIL lines incl. summary), 414 s; by location: scripts 149, llmctl 72, claude_toolkit 35, wave-dpctf 5, video-quality-mcp 3, tests 1, other 1.
- Adoption 2026-11-01 (operator decision): the 321 unannotated oracle functions in 19 own-org submodule files (llmctl 299 in 17 files, containers 20, claude_toolkit 2) were adopted into `config/oracle_ratchet_baseline.txt` at today's level with the new narrow path `--adopt-new-files --reason "<text>"` (adds entries only for files that have none; refuses without a reason; refuses if any existing entry would rise; never lowers; audited in `config/oracle_ratchet_adoptions.log`). Ratchet total 735 unchanged; default ratchet now PASS with 0 over / 0 new. The ratchet only shrinks from here and new/changed tests must still annotate. `wave-dpctf` and `video-quality-mcp` stay scanned and unmarked as third party until their upstream licence is clarified (UNCONFIRMED).

- Review fixes 2026-11-01 (independent Opus review NO-GO, F1-F6): (F1) the third-party prune resolver now parses manifest KEYS, not substrings: comments are stripped, `name:`/`path:`/`third_party:` count only at the dep-field indentation, a top-level key ends the deps block (symlink guards and the depth cap 3 now have tests and mutants). (F2) `--adopt-new-files` refuses any file whose unannotated functions are NEW or MODIFIED relative to a non-sliding base and refuses at all (rc=2) when no such base exists; the non-sliding base is the merge-base of HEAD with the upstream main (`@{upstream}`, else `origin/main`, else `origin/master`), also the default rule-(3) base when it differs from HEAD, so empty commits cannot slide it; content already pushed to the upstream main is trusted by the base (honest limit). (F4, honest limit) rule (3) diffs the scanned repository only and cannot see inside an own-org submodule's contents: new or modified test functions inside a baseline-covered submodule are held only by that submodule's count rule (1); stated in the gate help and in every new adoption log line (`limit=submodule_contents_not_diffed`; the 2026-11-01 log line predates the field). (F5) `--standalone-canon` is honoured only when the root has `Constitution.md` and is not a vendored submodule, else rc=2 (never a SKIP). (F6) root-level helix-deps entries with `path:` again have their `ssh_url` checked against `.gitmodules`.

- Round-3 structural fixes 2026-11-01 (round 2 NO-GO: I1-I4, M1-M4, N1-N2; the findings recurred in two classes, so the fixes replace rather than layer): (I1/M2/M3, class "non-structural parse") `third_party_prune.sh` now reads each dep as a WHOLE list item (a block opens at ANY `- key:` at the list-item column under `deps:`, all fields at the field column are collected, the decision is taken at block end), `#` inside quotes is no longer a comment, and manifest-derived prune entries are ROOT-ANCHORED in the gates (`cm_third_party_prune_find_expr`; only the literal names `third_party` and `site-packages` stay name-based at any depth). `cm_helix_deps_ref_matches_gitlink.sh` got the same whole-item awk parse. (I2/I3, class "base can slide or be disabled") `ORACLE_GUARD_BASE` is gone (ignored with a note); `--base` is accepted only as the non-sliding base or OLDER (ancestor of HEAD, not newer), never with `--adopt-new-files`; the non-sliding base is the OLDEST merge-base of HEAD over `@{upstream}` and EVERY `<remote>/main|master` ref (multi-upstream remotes such as `github_x` work); with none the check is BLIND rc=2, never HEAD~1; the verdict line carries `base=<sha12>`. (I4/N1) nested `path:` entries are compared to the url the PARENT records in its own `.gitmodules` at the parent gitlink; any ssh_url mismatch (root-level or nested) is DRIFT (rc=1), no longer BLIND. (M1) `cm_is_canon_root` needs the `### §11.4.1 —` anchor heading in `Constitution.md` plus `scripts/gates`. (M4) baseline entries whose file no longer exists are reported as `stale baseline entry` even under `--quiet` (`stale_entries=N`), and `--write-baseline` prunes them. (N2) the RED-proof sandbox fails loudly if `git show HEAD:<lib>` fails.

- Round-4 structural fix 2026-11-01 (round 3 NO-GO: F1-F3, the SAME "non-structural parse" class a third time, in both hand-written manifest parsers). Replaced, not patched: the bash line parser in `scripts/lib/third_party_prune.sh` and the awk parser in `scripts/gates/cm_helix_deps_ref_matches_gitlink.sh` are gone. Both now call ONE reader, `scripts/deps_manifest/helix_deps_tsv.{py,sh}`, which parses the manifest as real YAML (PyYAML through the §11.4.31 verifier's StrictLoader: duplicate keys refused, multi-document refused, tabs refused) and emits one record per dep strictly from the parsed structure (name, path, ssh_url, ref, third_party; `third_party` is true only for the exact scalar `true`). Unknown shapes (non-mapping top level, non-list `deps`, non-mapping dep, non-string field, field containing a separator or newline) are refused. An independent awk count of the top-level `deps:` list items is cross-checked against the parsed count; a mismatch (and any non-empty flow-style `deps: [...]`, which the cheap count cannot see) is a refusal. Fail-closed semantics: prune lib -> on ANY refusal or missing PyYAML it emits only the literal directory names `third_party` and `site-packages` (scans MORE) and prints a note to stderr; ref gate -> BLIND (rc 2), never PASS. Hostile-path validation, root anchoring, nested descent (depth cap 3) and symlink guards are unchanged. Honest limits: a manifest that is valid YAML but written in flow style now reads as BLIND/literals-only even when correct (conservative by design); `third_party: True` (capital) is not treated as true (prunes less, the safe direction); the env switch `HELIX_DEPS_TSV_FORCE_NO_YAML=1` exists for tests only. Follow-ups F4/F5 in the oracle gate: the ratchet verdict line now carries `rule3=evaluated|skipped` (a non-git tree reports `skipped`, not a silent PASS) and `via=<remote ref that selected the merge-base>`; `cm_is_canon_root` ignores an anchor heading that only appears inside a code fence. Not converted (outside the files this round may edit, same class, UNCONFIRMED exploitable): `scripts/jev/bootstrap.sh` `manifest_field` (awk on `  - name:` for ssh_url/ref) and `scripts/gates/cm_llmctl_submodule_nonrecursive.sh` (awk extraction of the llmctl entry); tracked for the next round.

## Addendum 2026-11-01: remaining hand-written helix-deps.yaml readers converted

- `scripts/jev/bootstrap.sh` `manifest_field` and `scripts/gates/cm_llmctl_submodule_nonrecursive.sh` no longer parse the manifest with awk; both call the new `scripts/deps_manifest/helix_deps_field.py` (StrictLoader, same refusal codes as `helix_deps_tsv.py`, plus rc 9 = dep not listed, rc 7 = usage). Bootstrap stops (rc 4) on an unreadable / ambiguous / no-PyYAML manifest instead of using an empty ref; the llmctl gate reports BLIND (rc 2), never PASS. Old behaviour confirmed wrong on bare `-`, quoted-key, `name :` shapes, and the gate falsely PASSed when the `recursive_init: false` marker sat in the NEXT bare-dash entry.
- Tests: `tests/jev/test_bootstrap_manifest_reader.sh` (17), `tests/gates/test_helix_deps_field.sh` (19), 10 new shape cases in `cm_llmctl_submodule_nonrecursive_mutation_test.sh`.
- Still awk-based, NOT converted (outside the allowed file list): `scripts/gates/cm_jev_bootstrap_idempotent.sh` lines 137-138 (`name: X` / `ssh_url:` / `ref:` first-match awk) and the test stub `scripts/gates/fixtures/jev/bin/bootstrap.sh` lines 44-45 (same awk; a fixture standing in for the real script).

## Round-5 (last §11.4.276 round) 2026-11-01

- Fixed (round-4 review NO-GO, one important finding plus minors): I-1 `cm_dangerous_combination_fail_closed.sh` now DERIVES `HEADER_LINES` from its `# Classification:` line (no hand-counted literal; its mutation test fails if a literal returns and checks `--help` ends on that line). M-1 `helix_deps_tsv.py` / `helix_deps_field.py` reject every C0 control char and DEL (incl. NUL) in values (rc 6). M-2 fixtures for escaped newline, US, CR, literal block scalar and a forged-record value assert rc 6 / literals-only; mutants M6 (US/LF/CR rejection removed) and M7 (old reject set) are killed. M-3 the `HELIX_DEPS_TSV_PY`, `HELIX_DEPS_FIELD_PY`, `HELIX_DEPS_*_FORCE_NO_YAML` overrides are honoured only with `HELIX_TEST_MODE=1` and (for helper paths) a path under the temp root (`scripts/deps_manifest/override_guard.sh`); otherwise ignored with a stderr note; mutants M8/M9 killed. N-1 the oracle gate `--help` prints through the real header end (derived), with a test and a hardcoded-cut mutant.
- Follow-ups NOT done (review budget exhausted, minor): N-2 and N-3 of the round-4 review are open follow-ups to be tackled in the next iteration (tracked here; UNCONFIRMED whether a tracker item exists).

## Follow-up round 2026-11-03

- Oracle gate rule (3): deletion-only hunks are now parsed; stripping an `oracle:` annotation from a surviving function marks it MODIFIED, other deletions are ignored. Parser tests gained nested-list fixtures (mutant M10). `--help` of `cm_codegraph_mcp_health.sh` / `cm_opendesign_ui_system.sh` prints the full header. Dead consumer-side methodology links replaced by a code span. See `known_failures_v73.md` for status and the honest remaining list; N-2 / N-3 above are still UNCONFIRMED (text not found).
