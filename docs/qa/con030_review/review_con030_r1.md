# Independent review: CON-030 vehicle (round 1 of max 5)

| Field | Value |
|---|---|
| Reviewed | vehicle/con030 head da9d4253c40a75ea1c4d2d2b8176933221616150 (parent ef18fea), from con030.bundle |
| Integration check | merged onto real main 8e496db in a throwaway clone (merge 8a75800): clean; main did not touch the three files |
| Reviewer | independent subagent, Opus 5.5 (effort not settable or readable on this dispatch path, so not claimed, section 11.4.231(F.2)) |
| Mode | read-only; all work in throwaway clones under /home/milosvasic/.cache/claude-tmp/rv030.glpGPU, HOME and TMPDIR from mktemp |
| Verdict | **NO-GO** (one important source-defect regression, F1) |

## What was verified (with this session's evidence)

1. RED on the parent, GREEN on the head, on my own fixture (`exp/root`): submodules at `plain`, `sub dir`, `a<TAB>b`, ` lead`, `trail `, `x (xyz)`, `ünï cødé`, `par(1)`, nested `nest ed/in ner`.
   - parent: `sub_paths` = `['lead','a','nest','nest','par(1)','plain','sub','trail','x','ünï']`, 8 bogus "recorded commit ... is not in its object store" gaps, `ident_diff(same,same)` non-empty.
   - head: `sub_paths` = `[' lead','a\tb','nest ed','nest ed/in ner','par(1)','plain','sub dir','trail ','x (xyz)','ünï cødé']`, `gaps=[]`, `ident_diff(same,same)` = `''`.
   - `-` (fresh clone, uninitialised): head names every path whole except `x (xyz)` -> `x` (the documented limit). `+` (drifted `sub dir`): head gives exactly one gap `drifted submodule: sub dir ...`; parent gives 7 bogus gaps. `U` (real gitlink merge conflict on `con flict`): head `submodule with merge conflicts: con flict`, parent `... con`.
2. Self-test `tests/test_run_full_suite.sh`: parent 239/0 rc 0, head 247/0 rc 0, head merged onto 8e496db 247/0 rc 0 (logs/selftest_*.log).
3. RED of the head's own CON-030 checks against the parent engine: see section "RED run" below.
4. `--verify-manifest` on the real repository with the parent, head and merged engines: rc 3, 25 problems each, stdout and stderr byte-identical parent vs head (cmp), head vs merged identical. The real working tree was clean before and after (0 porcelain lines).
5. Real repository (32 submodules): `sub_paths` identical parent vs head (cmp), `topology` 0 gaps on both.
6. Newline claim: measured, and it is FALSE (finding F3).
7. Mutation file: M30a to M30d 4/4 killed; whole file 97/98 killed, R2 survived (pre-existing on the parent too, F11); 3 of my 6 reviewer mutants survived (F6). See "Mutants" below.

## Required for GO (round 2)

1. F1: fix the describe-with-parentheses regression (flag-aware rule, or paths from a `-z` machine format) and add the four tests named under F1.
2. F5 and F11: register the tracked follow-up items (the same-class members in other tools; the weak R2 test) before CON-030 is reported done.
3. Strongly recommended in the same round, all small: F2 (`split("\n")`), F3 (correct the newline claim in the docstring and the commit message), F6 (a SHA-256 row and a leading/trailing-space path in the tests), F7 (document the new gap type). F4, F8, F9 and F10 may go to follow-up items.

## Findings

### F1 — IMPORTANT, finding_layer source-defect, REGRESSION introduced by this change: a describe that contains `(` or `)` is swallowed into the path

`_SUB_STATUS_RE` only strips a trailing ` (describe)` whose text has no parentheses (`[^()]*`). Branch and tag names may contain `(` and `)` (refname rules allow them), and `git submodule status` prints `git describe` / `--tags` / `--contains` / `--all --always` output in that slot. When the describe has a parenthesis the optional group fails and the whole ` (describe)` becomes part of the path.

Reproduced (fixture `exp/root2`, two plain-named submodules: `plainb` on branch `feat(x)`, `plaint` at tag `v1(beta)`; status lines ` <sha> plainb (heads/feat(x))` and ` <sha> plaint (v1(beta))`):

| engine | sub_paths | topology gaps | full run `--include-heavy` | run `--allow-topology-gaps` |
|---|---|---|---|---|
| parent ef18fea | `['plainb','plaint']` | 0 | rc 0, `RESULT: PASS-FULL` | rc 0, PASS-FULL |
| head da9d425 | `['plainb (heads/feat(x))','plaint (v1(beta))']` | 2 bogus "recorded commit ... is not in its object store" | rc 9, `REFUSED-TOPOLOGY` | rc 1, `RESULT: FAIL (identity changed during the run ...)` |

So a checkout that the parent runs correctly is refused by the head, and with `--allow-topology-gaps` the head reports, confidently and falsely, that the identity changed during the run (a section 11.4.201(1) FAIL-bluff). It fails closed (no wrong PASS), so it is not critical, but it is a regression of a path class the old parser handled (paths without spaces), on legal input.

Suggested fix (flag-aware, removes residual limit (1) for `-` and `U` too): git prints a describe only for `' '` and `'+'` lines (measured in this session: every `' '`/`'+'` line of my fixtures carried one, the `-` lines of `exp/rootF` and the `U` line of `exp/rootV` did not; that this follows from `print_status` in builtin/submodule--helper.c is from memory, not re-read: UNCONFIRMED), and a describe never contains a space (ref names cannot; abbreviated sha and `~N^M` suffixes have none). So: for `-` and `U`, path = everything after `<sha> `; for `' '`/`'+'`, strip a final ` \(([^ ]+)\)$` (greedy path). Better still (section 11.4.250, see below): take paths from a machine format (`git ls-files -s -z` / `ls-tree -r -z` gitlinks, recursively) and use the status line only for flag and sha, matched against the known path set. Add tests: branch with parentheses, tag with parentheses, a `)`-only tag, and an uninitialised `x (xyz)`. A throwaway prototype of the flag-aware rule (`rv030.glpGPU/drv/proto.py`, not applied to the engine) returned the right path for every real status line of my fixtures, including `plainb`/`plaint` (describe with parentheses), `x (xyz)` both initialised and uninitialised, ` lead`, `trail `, `a<TAB>b`, nested `nest ed/in ner` and the `U` line.

### F2 — MINOR, source-defect, same class, pre-existing and not closed: `str.splitlines()` splits paths on characters other than `\n`

`topology()` and `sub_paths()` iterate `stdout.decode().splitlines()`, which splits on `\r \v \f \x1c \x1d \x1e \x85    ` as well as `\n`. `git submodule add` accepted paths with `\r`, `\f`, `\x1c` and U+2028 (fixture `exp/root3`). Head: each line breaks into two; the first fragment parses as a wrong path (`cr`, `ff`, `fs`, `ls`) and the second is an "unparseable" gap; result fails closed (rc 9) for a valid checkout; parent fails closed too. Fix: `split("\n")`. The docstring's claim "a fragment line that did appear would not parse and would be a gap" is only half true: the first fragment does parse, to a wrong path.

### F3 — MINOR, process-doc (false factual claim, section 11.4.6): "git cannot record a newline in .gitmodules (measured)"

Measured false: a hand-written `.gitmodules` with `path = "nl\nx"` plus a gitlink added with `git update-index --cacheinfo 160000,<sha>,$'nl\nx'` is committed, `git submodule update --init` checks it out, and `git submodule status` prints it across two lines (fixture `exp/root4`). What is true is that `git submodule add` refuses it (`invalid key (newline)`, because the default name is the path). Fail-closed outcome holds (head: gap `submodule nl ...` plus unparseable `x (heads/master)`). The newline separator in `quick_ident()` is still safe, but for a different reason than stated: nothing `sub_paths()` returns can contain `\n`, because the status text is split on line breaks before parsing. Correct the docstring and the commit-message sentence ("a submodule path cannot contain one").

### F4 — MINOR, source-defect, same file and same class; the root-cause note calls it "safe": `submodule_paths()`

`git config --get-regexp` default output is `<key> <value>` and the key embeds the submodule NAME, which defaults to the path, so `split(None, 1)` turns `submodule.sub dir.path sub dir` into `dir.path sub dir`; `git ls-files -s` without `-z` C-quotes TAB and non-ASCII paths. Measured on `exp/root`: the function returns `'dir.path sub dir'`, `'b.path a\tb'`, `'lead.path  lead'`, `'"a\\tb"'`, `'"\\303\\274n..."'` and misses `a<TAB>b` and `ünï cødé`. Effect today: none found (it only feeds the census exclusion of files inside submodules, and `ls-files -co` does not descend into gitlinks), so latent. Fix with `--null` and `ls-files -s -z` (repo_verify.py already does), or scope it out with a tracked item; do not record it as safe.

### F5 — IMPORTANT (pre-existing, outside this diff; registered follow-up required, not a fix in this vehicle), source-defect in other tools: the class inventory (section 11.4.276(C), 11.4.273) is incomplete

Control-needled census (positive needle: `"submodule", "status"` in the engine = 3 hits, and `--get-regexp` hits in run_full_suite.py and repo_verify.py found; negative needle = 0 files). Members of the same class (whitespace tokenising of git output whose field may be a submodule name or path):

| location | shape | measured effect |
|---|---|---|
| progressive/validate_submodule.py:60 | `l.split()[1]` on `-` status lines | crafted `--status-file` with orphan `x y` and declared `x`: PASS (false); control `zz`: FAIL (instrument sees). With real git output: false FAIL for a spaced uninitialised path. |
| scripts/gates/cm_hub_engine_no_ownorg_nesting.sh:68 | `--get-regexp` + `awk '$2 ~ /^submodules\//'` | extraction drops `submodules/my engine` silently (only `submodules/plain` emitted), so that submodule would not be inspected: potential false PASS; gate end to end UNCONFIRMED |
| scripts/gates/cm_gitlink_on_remote.sh:55, :57 | `ls-tree` / `ls-files -s` + awk `$4` as path | path truncated at the first space (UNCONFIRMED end to end) |
| scripts/gates/cm_gitlink_on_remote.sh:63 | `--get-regexp` + `awk '$2==p'` | key lookup for `submodules/my engine` returns empty (measured); control `submodules/plain` found |
| scripts/fastcycle/cycle/baseline_replay.sh:1049-1052 | `IFS=' ' read -r key path` | name/path wrong for spaced names (UNCONFIRMED) |
| scripts/gates/cm_helix_deps_ref_matches_gitlink.sh:79, :95, :105 | `--get-regexp` + `awk '$2==p'` | same as above (UNCONFIRMED) |
| scripts/fastcycle/consumers/migrate.sh:2432-2433, docs/prompts/setup/latest.md:290 and siblings | first-space split / awk `$2` | low: compared against fixed constitution paths |
| safe | repo_verify.py (`-z`, `--null`), lib/constitution_layout.sh (`-z`), lib/third_party_prune.sh (`--null`), hooks/post-merge (`-z`), codegraph/scope_render.py (`--null`); deps_manifest/helix_deps_manifest.py greedy regex mostly safe (strips leading/trailing spaces) | |

CON-030's own scope is the full-suite runner, so these need not be fixed here, but they must be registered as a tracked item (one class item listing the members) before CON-030 counts as done, per section 11.4.276(C).

### F6 — MINOR, test-instrumentation: three of my six reviewer mutants survive (section 11.4.194(6)(d))

- RA `[0-9a-f]{40,64}` -> `{40}` SURVIVED (247/0): the SHA-256 width the regex claims is never exercised; one 64-hex row in the `parse_sub_status` table (or a `--object-format=sha256` fixture) would pin it. The parent read the sha as any token, so a SHA-256 repository is a behaviour this change must keep.
- RF `out_.append(parsed[2])` -> `parsed[2].strip()` SURVIVED (247/0): no test has a submodule path with a leading or trailing space, although such paths exist and the head handles them (measured on `exp/root`: ` lead`, `trail `). With RF, `quick_ident` would read `HEAD` in a non-existent directory and give `?`, a false IDENTITY CHANGED.
- RB `parsed is not None and parsed[0] != "-"` -> `parsed is not None` SURVIVED (247/0): the rewritten `-` filter in `sub_paths()` has no test. Measured effect of the mutant in the normal case is nil (an uninitialised submodule directory is empty, so `git -C` reads the root's HEAD), so this one is near-equivalent; noted, low priority.

### F7 — MINOR, process-doc: the new gap type is not documented

`docs/guides/full_suite_runner_guide.md:91` and the TOPOLOGY block in `scripts/run_full_suite.sh:37-40` list the gap types; "unparseable git submodule status line" is a new one and appears in neither (section 11.4.12 / 11.4.60).

### F8 — NIT, pre-existing, out of scope (the author noted the first): in-band sentinels in the quick identity

- A submodule path containing `?` makes `"?" in qid` true on every check, so a run stops before its first unit with `IDENTITY CHANGED before unit ...:` and an empty difference text (measured on `exp/rootQ`, parent and head alike).
- A path containing `=` collides keys in `ident_diff()` (`k` and `k=v` both become key `k`): only the report text is affected (measured: identity differs, `ident_diff` returns `''`). `rpartition("=")` would fix it (the value is a sha or `?`).

### F9 — NIT, test-instrumentation

- The unparseable-line case uses a git shim. That is a gate-logic test and legal (section 11.4.289(C)(2)), but a real-git fixture exists (the `\r` path through `git submodule add`, or the hand-written newline path of F3) and would prove the same branch on real output.
- The "ident_diff names a spaced submodule whose HEAD moved" case passes an unused third argument (`$sp/plain`).
- New mutant ids `M30a`-`M30d` sit next to an older, unrelated `M30`; selection is by exact token so nothing breaks, but the names mislead.

### F11 — MINOR, test-instrumentation, found by the full mutation-file run: the old reviewer mutant R2 SURVIVES, and its real effect is a false PASS-FULL

The full mutation file on the head: 97 of 98 killed, `R2` SURVIVED (shard 2). R2 turns the final `if tree_end != tree:` (the `RESULT: FAIL (repository tree changed ...)` branch) into `if False:`. Its only test (section 18, `R2: suite writing into the tree`) writes a NEW untracked file; since the round-6 quick identity hashes `git status --porcelain`, that write also sets `id_changed`, so the earlier `if id_changed:` branch prints a message that still matches `^RESULT: FAIL \(repository tree changed` and returns 1. The tree branch is therefore never the one that decides in the test.

R2 is not equivalent. `tree_state()` also hashes ignored files and file contents, which the quick identity does not. Direct probe (`rv030.glpGPU/r2probe.EO8p`, head engine, a suite writes `out.dat`):

| engine | `out.dat` untracked | `out.dat` listed in `.gitignore` |
|---|---|---|
| head, unmutated | rc 1, FAIL (tree changed; identity changed) | rc 1, FAIL (repository tree changed) |
| head + R2 | rc 1, FAIL (tree changed; identity changed) | **rc 0, `RESULT: PASS-FULL`** |

So with the tree branch disabled, a suite that writes an ignored file into the repository gets a false PASS-FULL, and no test notices. Fix: add a case where the suite writes an ignored file (or rewrites the content of an already-modified tracked file), and assert rc 1 with the tree message and WITHOUT `identity changed`. PRE-EXISTING (measured): R2 alone, re-run on the head twice and on the parent ef18fea once, SURVIVED all three times with byte-identical logs. So the mutation file is already red on main for this mutant; nobody re-ran the whole file after the round-6 identity check landed. Not caused by this diff's logic (the three CON-030 edits do not touch `tree_state`, `id_changed` or the result branches); CON-030 should register it as a follow-up, not fix it here.

### F10 — NIT, process-doc

The evidence logs cited by the author report carry no sha256, and the tracker entry for CON-030 still shows reproduction and investigation state UNSET; set both from the parent item at landing (section 11.4.292(C), 11.4.294).

## Section 11.4.250 and 11.4.289 checks

- 11.4.250: not a tower yet (one parser), but F1 and F2 both come from the same primitive choice: parsing a human-oriented, unquoted line format. A second heuristic for the describe would start a tower. The durable primitive is a machine format for paths (`-z`) with the status line used only for flag and sha.
- 11.4.289: the tests drive the real engine against real git repositories built on the host (host-fixture class, appropriate for host-only code); the end-to-end case runs the real runner; the git shim is a gate-logic double and is not cited as live evidence. No issue beyond F9.

## Mutants

**Author's mutants M30a to M30d** (head, my own run, shard 0): baseline passes, `SUMMARY mutants=4 killed=4 survivors=0 not_applicable=0`, rc 0. Each anchor occurs exactly once in the head engine; on the parent only M30a to M30d are absent (their anchors are new code), every other anchor applies on both.

**Whole mutation file** (head, 98 mutants, 7 parallel shards, each shard its own `HOME`/`TMPDIR` from mktemp and its own baseline):

| shard | mutants | killed | survived | rc | log sha256 |
|---|---|---|---|---|---|
| 0 (M30a-M30d) | 4 | 4 | 0 | 0 | fdc80d8028ab01b19bffaaf634f254f7c6cd6c52ffde2ed912e8ba9505dc18e3 |
| 1 | 16 | 16 | 0 | 0 | ff3c891b8a79904e04f6c225cefd8f6739e108321a2b5f7047be99fe3d467bd1 |
| 2 | 16 | 15 | 1 (R2) | 1 | 3f8aded8449bc9b8c24777a548785e041c9a2bf5a8d38bc4dc301081e977dcf0 |
| 3 | 16 | 16 | 0 | 0 | 6f788d9dfda44e47b10d9c3c095b8948e3286b882e4a06fa8e808c66d73cfac8 |
| 4 | 16 | 16 | 0 | 0 | dc82824d6201e45ff4bd69a259f0c3b9e28239ed1eea44c4aeffee761dcf19d0 |
| 5 | 16 | 16 | 0 | 0 | 15b8ec5f0e7ce7387e552b438165c057852fed7636df9d769b52f194d007fb84 |
| 6 | 14 | 14 | 0 | 0 | 54d7ad02faa396b34e53ad4097dca69ed0636886a95231e4608be811413d0141 |
| total | 98 | 97 | 1 | | |

R2 re-run alone: head 2/2 SURVIVED, parent 1/1 SURVIVED (logs `r2_head1.log`, `r2_head2.log`, `r2_parent1.log`, all sha256 df1c7aaee415e249f0bdd3b14092e423c04d47d1dabe4a2ed9807b6b98828afc). Pre-existing, see F11.

**Reviewer mutants of my own** (section 11.4.194(6)(d); applied one at a time to a copy of the head engine, then the head self-test run against it):

| id | change | result |
|---|---|---|
| RA | `[0-9a-f]{40,64}` -> `[0-9a-f]{40}` | SURVIVED 247/0 (F6) |
| RB | `sub_paths`: drop the `parsed[0] != "-"` filter | SURVIVED 247/0 (F6, near-equivalent) |
| RC | describe group made greedy | killed (1 FAIL, `parse_sub_status` table) |
| RD | path group made greedy | killed (25 FAIL) |
| RE | `ident_diff` splits on whitespace instead of `\n` | killed (3 FAIL) |
| RF | `sub_paths` appends `parsed[2].strip()` | SURVIVED 247/0 (F6) |

Plus the F1 fixture (`exp/root2`), which acts as a seventh probe the self-test does not have: the head refuses a valid checkout the parent accepts.

## RED run

The head's `tests/test_run_full_suite.sh` run against the PARENT engine (`FSR_RUNNER=parent/scripts/run_full_suite.sh`): `passed=240 failed=7`, rc 1. All 7 failures are CON-030 checks (space, TAB, end-to-end rc 9 instead of 0, topology line, moved-HEAD round trip `False 2`, unparseable-line case, `parse_sub_status` missing); the CON-030 control (path without a space) passes; zero non-CON-030 failures. On the head the same file is 247/0. Polarity confirmed on one command, one fixture shape, one symptom (REFUSED-TOPOLOGY rc 9 from a truncated path). Note: on the parent the shim's `not a status line` was already a gap (`unknown status flag 'n'`), so that case proves the new message, not a new fail-closed outcome; the old silent `continue` applied only to a line with fewer than two tokens.

## Evidence (this session)

Root of all scratch work: `/home/milosvasic/.cache/claude-tmp/rv030.glpGPU` (throwaway clones `parent`, `head`, `merged`; fixtures under `exp/`; driver scripts under `drv/`; logs under `logs/`). Input bundle `con030.bundle` sha256 `a33c05ca4464a9b6019cabece0f3ed47bbd3b403f93ebb1a9b0d1488958d95fe`.

| file (under rv030.glpGPU/logs) | result | sha256 |
|---|---|---|
| selftest_parent.log | passed=239 failed=0, rc=0 | fb2b2b0bd4e9bc184ed11371ee7c37fb2b5c572b15801ccd57fa9e8e0c89e277 |
| selftest_head.log | passed=247 failed=0, rc=0 | e7032e8179dd9010ddfe5a0d375105992f6b2946881628d0c489107c3986fdb0 |
| selftest_merged.log | passed=247 failed=0, rc=0 | 1b95c4a91e71917750bee5174dda0246c6b1990c70fae676547cde206cadffcd |
| red_headtests_on_parent.log | passed=240 failed=7, rc=1 | 85e7bb3a87f8b40e8fe633efcf6c4ca18452293554f1e1077bf0d2bde86bdf95 |
| vm_parent.out / vm_head.out / vm_merged.out | `RESULT: MANIFEST-MISMATCH (25 problem(s); nothing was run)`, all three identical | 8e815d7e7fa11a9d8bef0df8f8839e482a92e70b7b00f8145f80d269b06357fd |
| vm_parent.err / vm_head.err / vm_merged.err | identical | 14a270233568a65306e235508fb212f2745a09b1e13e21ca59c3097887d60191 |
| rmut_a.log | RA SURVIVED, RB SURVIVED | c026a38b5f82c00f0158d30db9befbffedf7ec9b068afbf30a9361f9f85a96d3 |
| rmut_b.log | RC killed, RD killed, RE killed, RF SURVIVED | 3eb171592e5378ed4fe21ab893b7e1e25cac6f28a57866f1fad57828bb4c2dde |

Driver scripts (drv/): `proto.py` (flag-aware prototype of the F1 fix, not applied) e92c17f53093349a27687d001ca8cb1e4cf69bfdb8b22ec1d078bc4670dc4867; `rmut.sh` 105a9208eb9b93065a66edce12cb4bd74471f37766ad4d14ae84dd62c6eef5f0; `rmut_a.json` ff3af9180e852fa4cdd7d2e80ab90d15bffadb4fb00e7937405a65c913796bd8; `rmut_b.json` dba35dea8ad9450f15cf64438e3821da007da360b205415ec46493e853476402; `apply_mut.py` b79b5031b996975fcbd64bf5d3f45b9fcc01b83726390967d2b2f6338c45b431; `probe.py` b0bd6c815fc080904e758517f644126bdd3e74520ddae831aae6df38703ac66e; `subs.py` 98ca3f370a0964f70136cb4c91aa423a7861bf80f593fb529d043280f10c2efd.

Mutation shard logs `mut_shard0.log` to `mut_shard6.log` and R2 reruns `r2_*.log`: hashes in "Mutants" above. R2 probe (F11): `rv030.glpGPU/r2probe.EO8p/probe.sh` 466a3c91c7340a118930618e7411db7dce42acffc04ddb3225b75d2ba9361dbd; `o_plain_untracked.log` 9ca7b5e27afb3cc82f8d2e94f77aabcd60c8ef689a92ab2ab28e86ce0b4510cc; `o_plain_ignored.log` d701009cb5e5d370a84796fcc49dc2d71b58fcc7c722a3f3d43d09b95261c250; `o_mut_untracked.log` c42807ae0c8efecded4d9d74cf9a890072a7558ba11097553795cd8ea8f8074a; `o_mut_ignored.log` (the false PASS-FULL) 7cec964f43d9b0b9ac68f50f2bcd050fe791ccbb242428705385f45fdecacbdc.

The real repository working tree was not modified (0 porcelain lines before and after); no clone outside the scratch root was written; no push was made.
