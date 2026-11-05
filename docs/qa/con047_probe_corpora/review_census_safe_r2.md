# Independent re-review, round 2: vehicle/census-safe (head bc788b7)

| Field | Value |
|---|---|
| Reviewer | independent subagent, Claude Opus 5.5 (claude-opus-5-5); effort not settable or readable on this dispatch path, so no effort is claimed (11.4.231(F.2)) |
| Date | 2026-11-05 |
| Round | 2 of R_max 5 (11.4.276(G)) |
| Under review | bundle /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/census_safe_r2.bundle, head bc788b77569dc4f54a75dc9fd97696b5b23ee503 (fix commit bc788b7 on merge 2f04959 of main feacc50); bundle verifies, one head, prerequisite cb31e32 |
| Mode | read-only; all runs in throwaway clones under /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv2.DsqC (`c` = head, `m` = head merged with main 8e496db), HOME and TMPDIR set to fresh mktemp dirs |
| Verdict | **NO-GO** (one important source-defect on the proof-of-batch surface: a reviewer mutation of the F1 fix survives the proving guard; the remedy is test-only, four cases, already drafted and measured) |

## 1. What was run (this session)

| Run | Tree | Result |
|---|---|---|
| tests/gates/test_gate_env_census_jq_regions.sh | head | rc 0, `== 45 passed, 0 failed ==` (G1..G5, W1, W2 all PASS) |
| same test file, census of dbe1b65 (= 2f04959, cmp: no diff) | old order | rc 1, `== 40 passed, 5 failed ==`, FAIL exactly G1 G2 G3 G4 G5 (RED on the old order, as the author states) |
| same test file, census of main (cb31e32 = feacc50 = 8e496db, md5 identical) | main | 30/15: A1..A6b, M9, W1, W2 fail (the intended widening); G1..G5 PASS on main (main fires them, so the round-1 regression was real and is now gone) |
| tests/gates/test_gate_env_census_closure.sh | head | rc 3, `== 31 passed, 0 failed, 1 known-failure ==`, `KNOWN-FAIL N3 negative ... (rc=1, signature matches CON-047)`, `PASS G5 ... UNCOVERED (rc=1)` |
| same | merged with main | rc 3, `== 31 passed, 0 failed, 1 known-failure ==` (jq-region on merged: 45/0) |
| G5 end to end, each tree through ITS OWN gate (census cmp-checked) | dbe1b65 / head / main | dbe1b65: rc 0 `VERDICT: PASS ... uncovered=0` (the regression); head: rc 1 `UNCOVERED scripts/gates/cm_repro_first_anchor_wired.sh:364 jq-env (indirect)`; main: rc 1, same line |
| scripts/gates/cm_gate_env_reads_allowlisted.sh | head and merged | both rc 0, `VERDICT: PASS ... gates=187 reads=170 guarded=54 allowlisted=116 uncovered=0 stale=0 needle=ok` |
| scripts/gates/cm_gate_env_reads_allowlisted_mutation_test.sh (background, about 15 min under load 27) | merged | `mut_rc=0`, `META PASS ... kills every mutant`, 34 `ok`, 0 FAIL/SURVIVED |
| Real-tree census (187 gates, --closure, merged tree), census exit status captured separately from sort | main / dbe1b65 / head / RN1 / F7-separator variant | all rc 0, 170 rows, 7 `<eval>` rows, 0 `jq-env` rows, sorted output md5 8a4385fd for all five (byte-identical); negative control (fabricated needle) 0 hits |
| RM3 (round-1 reviewer mutant) applied to the head census, closure test on that tree | RM3 | rc 1, `FAIL N3 negative: failure does NOT match CON-047's signature (rc=2 uncovered=0): UNRESOLVED-SOURCE ...:1376 eval-of-source-string`, `== 31 passed, 1 failed ==` (killed; F3 fixed) |
| RM8 / RM14 applied to the head census, jq-region test | RM8 / RM14 | RM8: rc 1, 44/1, FAIL W1; RM14: rc 1, 44/1, FAIL W2 (both killed; F2 fixed) |
| N3-negative injection, gate output inspected | head | rc 1, exactly one `UNCOVERED scripts/gates/cm_killpg_pgid_guard.sh:425 jq-env (indirect)` line, VERDICT line uses lowercase `uncovered=1`, so `grep -c UNCOVERED` counts rows only (pin is sound) |
| Round-1 probes probe.sh..probe4.sh (25 shapes) | main / r1 / r2 | section 5 |
| New probes probe5.sh (22 shapes) | main / r1 / r2 | section 5 |
| Merge of main 8e496db into the head | throwaway `m` | clean ort merge, no conflict; main touched only cm_oracle_strategy_named_and_independent.sh, its mutation test and tests/gates/test_gate_env_overrides_guarded.sh |
| Gitlinks | head vs feacc50 and 8e496db | 27 gitlinks, identical |
| Secrets | added lines of 2f04959..bc788b7 | 0 hit lines (positive control `api_key=abcdef123` hits 1) |
| Parse | both test files `bash -n`, census `py_compile` | clean |

Instrument errors of mine, found and discarded: (1) a first F7 measurement used an unquoted shell heredoc that turned `"\\n"` into a newline, so the variant did not compile and reported 0 rows with rc 0, because the rc I printed was sort's, not the census's (11.4.273(g)); redone with the census rc captured on its own. (2) A second F7 variant joined on owner identity, but `("jq",)` is an interned constant tuple, so no boundary was seen; replaced by a separator at the closing quote. (3) A first G6 draft put `jq` on the same line, so it was not discriminating (it passed on the old order); rewritten as a two-line function.

## 2. Status of the round-1 findings

| Id | Round-1 class | Status in round 2 | Evidence |
|---|---|---|---|
| F1 | important, source-defect | **Fixed** for the shapes tested. The RE_OWNER_ASSIGN / RE_OWNER_READ checks now run before the whole-line nonjq / file checks. G1..G5 RED on the old order, GREEN now; G5 end to end FAILs on the head and on main, PASSes on dbe1b65. But the proving guard pins only `NAME=` at line start and `read`: see N1. | section 1 |
| F2 | important, source-defect | **Fixed.** W1 kills RM8, W2 kills RM14. | section 1 |
| F3 | important, test-instrumentation | **Fixed.** KNOWN-FAIL requires rc 1, exactly one UNCOVERED row, that row a jq-env row of cm_killpg_pgid_guard.sh, and no UNRESOLVED-SOURCE; anything else is a FAIL. RM3 (rc 2) and RM2 (rc 2) now FAIL on the case itself. Residual, accepted: the census keeps one jq-env row per file, so a second jq-env false positive in that same file would hide inside the known one. | section 1 |
| F4 | minor, process-doc | **Open.** Commit 94a1d28 is not in the bundle (`git cat-file -e 94a1d28` fails after fetching it) and is on none of the 5 upstreams (ls-remote shows only wip/continue-20261105/census-followups 0e4b197 and wip/continue-20261105b/census-safe dbe1b65). See section 7. | section 7 |
| F5 | minor, test-instrumentation, pre-existing | **Open, untracked.** jq-region test still has no row in config/full_suite_manifest.tsv and is not called by the meta-test; the 52 cases this batch relies on run only by hand. | grep of manifest and meta-test |
| F6 | minor, test-instrumentation, pre-existing | **Open, untracked.** `cen()` still has no unmutated closure baseline. | meta-test lines 134-148 |
| F7 | minor, source-defect, pre-existing | **Open, untracked; broader than rated in round 1, and cheap to fix.** See N3. | section 5 |
| F8 | nit | Open (CON-047 history attribution and UNSET reproduction state). | — |

F5, F6 and F7 are not recorded as workable items (no hit for them in docs/Issues.md or docs/Issues_Summary.md of the head). 11.4.276(G.2) follow-ups must be tracked items in the 11.4.93 store; today they exist only in review files.

## 3. New findings

Severity per 11.4.276(G.2); layer per 11.4.235(D).

### N1 (important, source-defect, proof-of-batch surface, BLOCKING) — a reviewer mutation of the F1 fix survives: keyword-prefixed assignments are unpinned

Reviewer mutant RN1: in RE_OWNER_ASSIGN, `(?:^|[\s;&|(])` -> `(?:^|[;&|(])` (a name preceded by whitespace is no longer an assignment owner). The jq-region suite stays at `45 passed, 0 failed`. The mutant changes behaviour in exactly the F1 direction: with RN1 the probes

| Probe | main | head | RN1 |
|---|---|---|---|
| FN1 `local P='env \| keys'; awk 1 f` then `jq -n "$P"` | fire | fire | **quiet** |
| FN2 `export P='$ENV'; sed -n 1p f` then `jq -n "$P"` | fire | fire | **quiet** |
| FN3 `declare -r P='env \| keys'; grep -q x f` then `jq -n "$P"` | fire | fire | **quiet** |

go quiet: the round-1 fail-open regression returns for `local`, `export`, `declare`, `readonly` and `typeset` assignments, the most common way a gate function holds a program, and no case notices. G1..G5 all use a bare `NAME=` at line start (or `read`). The F1 fix states its class as "the region is assigned to / read into a variable" (CLASS RULE (2)); its proving guard covers one spelling of that class (11.4.276(C)). Under 11.4.194(6)(d) and 11.4.235(D) a proving guard whose reviewer-authored mutation survives means the fix is not proven, and 11.4.276(G.2) keeps that out of the minor class. Same standing as round-1 F2 (RM8).

Related, minor (recorded here, not separately): RN7 (`\+?=` -> `=`) also survives; `P+='env | keys'; sed -n 1p f` then `jq -n "$P"` goes quiet (main fires it).

Remedy (verified direction, not a reviewed fix): four `fire` cases, drafted at /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv2.DsqC/addcases/t.sh (the head's test file plus G6..G9):

```
case_ G6 fire "local P=...; awk on the assignment line"      # f() {\n  local P='env | keys'; awk 1 f\n  jq -n "$P"\n}
case_ G7 fire "export P=...; sed on the assignment line"     # export P='$ENV'; sed -n 1p f / jq -n "$P"
case_ G8 fire "declare -r P=...; grep on the assignment line" # declare -r P='env | keys'; grep -q x f / jq -n "$P"
case_ G9 fire "P+=...; sed on the assignment line"            # P+='env | keys'; sed -n 1p f / jq -n "$P"
```

Measured: head 49 passed, 0 failed; dbe1b65 (old order) FAIL G1..G9; RN1 FAIL G6 G7 G8; RN7 FAIL G9. No source change is needed.

A stronger guard for the whole F1 class (suggestion, not required): a differential case that runs every `fire` case of main's census through the current census and fails if any goes quiet. Section 6 shows this monotonicity holds by construction today; a differential test would keep it true across future edits.

### N2 (minor, source-defect, latent, fail-closed direction) — the reorder adds false positives for option-argument and env-prefix assignments

Because the assignment check now runs before the interpreter check, any `NAME=` before a quoted region is a variable owner, including an awk `-v` option and an env prefix of an interpreter. Such a NAME is never `$NAME`-expanded, so the region is armed (by design for never-expanded variables, A5b). Probes, each in a file that also runs `jq --version`:

| Probe | main | r1 | head |
|---|---|---|---|
| FP1 `awk -v re='^(sudo\|env\|time)$' '$1 ~ re' f` | quiet | quiet | **fire** |
| FP2 `PAT='env\|x' awk 'BEGIN{print ENVIRON["PAT"]}'` | quiet | quiet | **fire** |
| FP3 `env PAT='^(env\|nice)$' sed -n p f` | quiet | quiet | **fire** |
| FP4 `grep -E -e x='(env\|sudo)' f` | quiet | quiet | **fire** |
| FP6 `awk '/^(env\|time)$/' f` (control, no assignment) | quiet | quiet | quiet |

These are FAIL-bluff shapes (11.4.201(1)): the gate would refuse a correct file. They are latent (the real-tree census is byte-identical to main's) and visible when they occur (an UNCOVERED row, cured by an allowlist row), so minor. FP1 is the CON-047 shape written with `awk -v` instead of a heredoc. Do not add a regex layer for them (section 6); add FP1..FP4 to the CON-047 corpus as cases the structural rewrite must keep quiet.

### N3 (minor, source-defect, pre-existing, out of this diff's class) — F7 hides real jq programs on lines that DO name jq, and a one-line fix is measured

Round 1 rated F7 on two shapes. Probing more widely, the glue hides the environment dump on ordinary jq lines that carry any earlier quoted text:

| Probe | main | r1 | head | head + separator |
|---|---|---|---|---|
| J1 `jq --arg k 'v' -n 'env \| keys'` | quiet | quiet | quiet | fire |
| FN5 `jq -n --arg a 'b' --arg c 'd' 'env \| keys'` | quiet | quiet | quiet | fire |
| FN9 `jq -n "$(printf '%s' 'env \| keys')"` | quiet | quiet | quiet | fire |
| FN15 `jq -n '.a' \| jq 'env'` | quiet | quiet | quiet | fire |
| FN4 `printf '%s\n' 'env \| keys' \| "$JQ" -f /dev/stdin` | quiet | quiet | quiet | fire |

Cause, shown with split_code: the regions of one line are kept as (owner, char) pairs and joined with `""`, giving `venv | keys`, `.aenv`, `%s\nenv | keys`. Variant measured (not a reviewed fix): in split_code, at the closing single quote, append `(owner, "\n")` before `sq = None`. Result: the five probes and J1..J4 fire, the jq-region suite stays 45/0, and the real-tree census output is byte-identical (md5 8a4385fd), so F7 hides nothing on today's tree. It also exposes data arguments as their own region (J2 `jq -n '.a' 'env'` then fires), which belongs to the program-operand class of CON-047. Track it as an item; it can ride the next round or CON-047.

### N4 (minor, process-doc) — follow-ups and the landing state are not tracked

F5, F6, F7, N2 and the two author-admitted shapes (R2 `"${JQ:-jq}" -n '$ENV' | sed ...`, R6 `x=$(grep -c f g); jq_run -n 'env | keys'`, plus the variable form FN6/FN7/R5 of the same per-simple-command class) have no workable item. The wip ref wip/continue-20261105b/census-safe still points at dbe1b65 on every upstream; round 2 exists only in the bundle. Before landing: register the follow-ups (11.4.202, 11.4.93), and either push the head to the wip ref (no force) or keep the bundle with the continuation record.

### N5 (nit, process-doc) — CLASS RULE comment precision

(a) Rule (2) says "armed when a jq line expands it"; the code arms a variable unless every expansion is on a provably non-jq line, so it is also armed when never expanded or expanded on an unknown line (stricter than written, which is the safe direction). (b) Rule (2) "assigned to a variable" also matches `awk -v NAME=` and `NAME=value interp` (N2). (c) Rule (4) "a file not named on a jq line" uses the jq-word lines only, so `/usr/bin/jq -f "$f"`, `"${JQ:-jq}" -f "$f"` and `jq -f "${f}"` (another spelling of `$f`) leave the generated file disarmed (round-1 probes R3, R4, G6, G7: quiet on main, r1 and head). The round-1 comment listed `${X:-jq}` and `/usr/bin/jq` as armed; the new comment no longer claims it for the file rule, which is correct, but a reader can miss that `/usr/bin/jq` is not a "jq word".

## 4. Reviewer mutants (round 2; none is in the author's set)

| Id | Change (head census) | Run | Result |
|---|---|---|---|
| RN1 | RE_OWNER_ASSIGN `(?:^\|[\s;&\|(])` -> `(?:^\|[;&\|(])` | jq-region | **survives** 45/0; behaviour: FN1..FN3 quiet (N1). Killed by drafted G6/G7/G8 |
| RN2 | RE_OWNER_READ check moved back after the nonjq check | jq-region | killed by G2 |
| RN3 | `_armed` var: also require the name to be expanded somewhere | jq-region | killed by A5b |
| RN4 | nonjq_vars `all(...)` -> `any(...)` | jq-region | killed by M3, M9 |
| RN5 | `_runs_nonjq` without the jq-word exclusion | jq-region | killed by M4 |
| RN7 | RE_OWNER_ASSIGN `\+?=` -> `=` | jq-region | **survives** 45/0; behaviour: FN12 quiet (N1). Killed by drafted G9 |
| RN8 | RE_OWNER_ASSIGN `\$?$` -> `$` | jq-region + probe5 | survives, no behaviour change on the 45 suite cases or the 22 probe5 shapes; `$'..'` regions get their prefix before the `$`, so the `\$?` is likely dead: recorded as equivalent, no finding |
| RN9 | var_lines regex without `[#!]?` | jq-region | killed by M9 |
| RM3 (round 1) | eval-of-source reads the raw line (comments trigger it) | closure | killed (rc 1, N3-negative signature mismatch) |
| RM8 (round 1) | no word boundary after `_INTERP` | jq-region | killed by W1 |
| RM14 (round 1) | any word before `>FILE` is a file writer | jq-region | killed by W2 |

Mutant sources: /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv2.DsqC/mutants (mk.py, mk2.py; each mutant tree has its census and output).

## 5. Probe matrix (47 shapes, real census CLI, every census rc 0)

Round-1 probes (probe.sh..probe4.sh in /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rvcs.b2JY) and the new probe5.sh (/home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rv2.DsqC/probes/probe5.sh), each takes a census path and a sandbox dir.

- Fire on main, quiet on head: **none** of the 47 (no false-negative regression against main).
- Fire on head, quiet on main: R7, R12, K1, FN10 (intended widening) and FP1..FP4 (N2).
- G1, G2, G3, G5 (round-1 F1 probes): main fire, r1 quiet, head fire.
- Quiet on all three (pre-existing false negatives): R1..R6, R9, R10, J1, J2, J4, G6, G7, K2, FN4..FN7, FN9, FN13, FN15. They fall into four classes: line classified as a whole, not per simple command (R1, R2, R5, R6, K2, FN6, FN7); glued regions (J1, J2, J4, FN4, FN5, FN9, FN15: N3); generated file read by jq through a path, default or other spelling (R3, R4, R9, R10, and round-1 probe3 G6, G7); herestring read not recognised as an assignment (FN13).

## 6. Heuristic-tower assessment (11.4.250) and the structural approach

Honest reading. The quoted-region ownership is decided by regexes over the whole logical line: a jq-word test, an assignment-prefix test, a read-prefix test, an interpreter-at-command-position test with a wrapper list, a file-writer test, a jq-text name match for generated files, and the all-expansions-non-jq rule for variables. CON-017 took two NO-GOs on regex disown rules; this vehicle took a NO-GO in round 1 for rule ORDER and an interpreter boundary, and round 2 finds unpinned assignment spellings (N1) and option-argument assignments (N2). Each round finds residuals of one primitive defect: the census does not know which simple command, and which operand of that command, a quoted region belongs to. That is the 11.4.250 signal (depth well above 2).

What round 2 did right: it added no layer (a reorder plus tests), and the comment now lists the known non-reported shapes instead of overclaiming. And there is a property that holds by construction, which I checked against the code and the probes: main arms a region only when its owner is `jq`, or `var` expanded on a jq-word line; the head evaluates the same `jq` and `var` tests first, in the same order, with the same regexes, and arms a variable unless every expansion is on a provably non-jq line, so every region main arms, the head arms. The change can only add reports, never remove one that main makes; it trades false negatives for false positives, which is the stated fail-closed direction of CON-015.

Recommendation. Do not grow this vehicle into the rewrite: its scope (CON-015/016 fail-closed arming) is met once N1 is pinned, and the rewrite needs its own RED corpus and review rounds. Do treat the structural approach as the next work on this instrument and adopt a stop rule now: no further regex owner layers in gate_env_census.py; every new residual goes into the CON-047 corpus as a case. The structural approach should replace the whole region-owner heuristic, not only CON-047's awk shape: tokenize each logical line into simple commands (quote-aware, already half-present in split_code), take the command word through wrappers and variable resolution, arm a region only when its command is jq (or unresolvable), and for jq judge only the program operand (first non-option argument, or the file named by -f/--from-file), with assignment words judged as assignments only at assignment position. Reuse the 94a1d28 corpus (402 test lines), the round-1/round-2 probes, FP1..FP4 and the G cases. The F7 separator (N3) can land before that, since it is one line and measured.

## 7. CON-047 evidence, commit 94a1d28

94a1d28 (`fix(gates): env census CON-017 disowns a program only when the whole class is proven non-jq ...`, parent d1b3b9b) is the second, NO-GO'd CON-017 rewrite: +212/-32 in gate_env_census.py and +402 lines of jq-region cases. It lives on branch fix/con017-class of /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/c017.upI4/c, a `--shared` clone whose objects come from /home/milosvasic/.cache/claude-tmp/tmp.EP8YhTHVJ2/c/.git/objects (alternates). It is **not** in census_safe_r2.bundle and **not** on any upstream. CON-047's text, which lands with this vehicle into docs/Issues.md, points at those scratch paths. Before landing: `git bundle create` the branch (or push it to a wip ref, no force) to a durable place and cite that place in CON-047 (11.4.197, 11.4.215). The author report acknowledges this but did not do it.

## 8. Merge with main 8e496db

Clean merge (no conflict); the main side changes only the oracle gate, its mutation test and test_gate_env_overrides_guarded.sh. On the merged tree: allowlist gate PASS, same counts (gates=187 reads=170 uncovered=0 stale=0 needle=ok); real-tree census byte-identical across main, r1, head; jq-region suite rc 0 `== 45 passed, 0 failed ==`; closure test rc 3 `== 31 passed, 0 failed, 1 known-failure ==` (`KNOWN-FAIL N3 negative ... (rc=1, signature matches CON-047)`); allowlist mutation test `mut_rc=0`, `META PASS: CM-GATE-ENV-READS-ALLOWLISTED kills every mutant`, 34 `ok` lines, 0 FAIL/SURVIVED. The meta-test still holds no mutant of the region-owner code and does not run the jq-region suite (F5), so its PASS says nothing about N1.

## 9. Verdict

**NO-GO.** F1, F2 and F3 are fixed with evidence. N1 is a surviving reviewer mutation of the F1 fix (RN1, plus RN7) that restores the round-1 fail-open regression for `local` / `export` / `declare` / `+=` assignments with the whole suite green; under 11.4.194(6)(d), 11.4.235(D) and 11.4.276(G.2) that is a proof-of-batch source-defect and blocks `GO-with-follow-ups`. The remedy is test-only (G6..G9, drafted and measured: 49/0 on the head, RED on the old order, kills RN1 and RN7). With N1 closed and the follow-ups (F4, F5, F6, F7/N3, N2, N4, N5, F8) registered as tracked items, I expect round 3 to be `GO-with-follow-ups` without further source change; the structural rewrite (section 6) belongs to CON-047, not to this vehicle.
