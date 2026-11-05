# Independent review: vehicle/census-safe (cb31e32..dbe1b65)

| Field | Value |
|---|---|
| Reviewer | independent subagent, Claude Opus 5.5 (claude-opus-5-5); effort not settable or readable on this dispatch path, so no effort is claimed (11.4.231(F.2)) |
| Date | 2026-11-05 |
| Vehicle | /home/milosvasic/.cache/claude-tmp/censafe.3dfZ/c, branch vehicle/census-safe = remote wip/continue-20261105b/census-safe = dbe1b6540479a9e824c0c79d746c20412e80af6d (checked with git ls-remote) |
| Commits | e37aa4b (census CON-015/016), 2ddece9 (jq-region tests), c73298a (2 allowlist rows), dbe1b65 (closure KNOWN-FAIL, CON-047, mutation-test rc rule) |
| Mode | read-only on the vehicle; every run in a throwaway clone /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rvcs.b2JY/c with HOME and TMPDIR set to fresh mktemp dirs |
| Verdict | **NO-GO** (2 important source-defect findings block; the rest are follow-ups) |

## 1. What was run (this session, throwaway copy)

| Run | Result |
|---|---|
| tests/gates/test_gate_env_census_jq_regions.sh | rc 0, `== 38 passed, 0 failed ==` |
| tests/gates/test_gate_env_census_closure.sh | rc 3, `== 30 passed, 0 failed, 1 known-failure ==`, `KNOWN-FAIL N3 negative ... (rc=1) [tracked CON-047]` |
| scripts/gates/cm_gate_env_reads_allowlisted.sh | rc 0, `VERDICT: PASS ... gates=187 reads=170 guarded=54 allowlisted=116 uncovered=0 stale=0 needle=ok` |
| scripts/gates/cm_gate_env_reads_allowlisted_mutation_test.sh | mut_rc=0, `META PASS: CM-GATE-ENV-READS-ALLOWLISTED kills every mutant`; 34 `ok` lines, 0 FAIL/SURVIVED (golden + 10 discriminators, M1–M12, F1, N1, F4, N3a–c, N6a–b, N2a–c). It contains no mutant of the new region-owner code (see F2/F5) |
| Census output on the real tree, base cb31e32 census vs new census (187 gates, --closure) | 170 rows each, byte-identical after LC_ALL=C sort (positive control: 7 `<eval>` rows; negative control: fabricated needle 0) |
| CON-047 claim check: N3-negative tree, each copy run through its OWN gate | base census: rc 0 PASS uncovered=0; new census: rc 1 FAIL `UNCOVERED scripts/gates/cm_killpg_pgid_guard.sh:425 jq-env (indirect)`. The CON-047 text is correct. (My first attempt ran both copies through the vehicle's gate, whose HERE-relative census is the new one, and showed FAIL for both: an instrument error of mine, found by a cmp of the census actually used, and discarded.) |
| Tracker on a copy of docs/workable_items.db | `validate: OK — 47 items`; `diff`: DB and Markdown in sync (47 vs 47); `sync db-to-md` and `export` regenerate Issues.md, Fixed.md and Issues_Summary.md byte-identical to the committed files: engine-made |
| Submodules | submodules/containers gitlink 5ea870a at both cb31e32 and dbe1b65; no other gitlink in the diff |
| Secrets | regex scan of the text diff and of the CON-047 description: 0 hits (positive control `api_key=abc` hits 1) |
| full-suite manifest (`run_full_suite.sh --verify-manifest`) | rc 3 MANIFEST-MISMATCH, 25 census files without a manifest row, one of them tests/gates/test_gate_env_census_jq_regions.sh (pre-existing; see F5) |

## 2. Findings

Severity per 11.4.276(G.2); layer per 11.4.235(D).

### F1 (important, source-defect, BLOCKING) — the change disarms real jq programs that main's census reports (a fail-open regression in a fail-closed fix)

`_region_owner()` now classifies the WHOLE logical line as `nonjq` (any interpreter at any command position on the line) or `file` (any cat/printf/echo/tee redirection on the line) BEFORE it checks whether the region is assigned to a variable. A region assigned to a variable that jq later expands is therefore disowned as soon as the assignment line also runs awk/sed/grep or writes some file. Probes through the real census CLI (same invocation as the jq-region test), base = census of cb31e32:

| Probe | base | new |
|---|---|---|
| G1 `P='env \| keys'; awk 1 f` then `jq -n "$P"` | fire | **quiet** |
| G2 `read -r -d '' Q <<'X' \|\| grep -q y f` (body `env \| keys`) then `jq -n "$Q"` | fire | **quiet** |
| G3 `P='env \| keys'; echo done > "$log"` then `jq -n "$P"` | fire | **quiet** |
| G5 `P='$ENV'; x=$(sed -n 1p f)` then `jq -n "$P"` | fire | **quiet** |

End to end through the gate (each tree run through its OWN gate script, census checked with cmp): appending `P='$ENV'; x=$(sed -n 1p /dev/null)` and `jq -n "$P" >/dev/null` to scripts/gates/cm_repro_first_anchor_wired.sh gives, with main's census, `VERDICT: FAIL ... UNCOVERED scripts/gates/cm_repro_first_anchor_wired.sh:364 jq-env (indirect)` (rc 1, correct), and with the vehicle's census `VERDICT: PASS ... uncovered=0` (rc 0).

These are true positives (a jq program that dumps the whole environment) that main reports and this change silently drops: a FALSE-NEGATIVE PASS of a guard (11.4.201(2)), introduced by a change whose stated purpose is to keep the check armed (CON-015, 11.4.201(4)). Not visible on today's tree (census output identical), so it is latent, but it is a regression of the instrument and no test covers it. The same line-level classification also contradicts the CLASS RULE comment the change adds ("DISARMED only for a region provably owned by such an interpreter"): `"${JQ:-jq}" -n '$ENV' | sed 's/a/b/'` and `x=$(grep -c foo bar); jq_run -n 'env | keys'` are quiet (quiet on main too, so not a regression, but the comment overclaims).

Verified direction (not a reviewed fix): moving the RE_OWNER_ASSIGN / RE_OWNER_READ checks before the `nonjq` / `file` checks in `_region_owner` makes G1–G5 fire and keeps the jq-region suite at 38/0 (scratch copy fixprobe). A complete fix judges the simple command that owns the region, not the whole line; it needs its own RED tests (G1–G5 as `fire` cases).

### F2 (important, source-defect per 11.4.235(D) — a reviewer-authored mutation of this batch's proving guard survives) — the interpreter word boundary is not pinned

Reviewer mutant RM8: drop `(?![\w.-])` after `_INTERP` in RE_NONJQ_CMD. It changes behaviour (probe `sedjq -n 'env | keys'` + `jq --version`: new = fire, RM8 = quiet; a command whose name merely starts with sed/awk/grep/perl/... is treated as that interpreter and its jq program is disowned), and the jq-region suite still reports 38 passed, 0 failed. Under 11.4.194(6)(d) / 11.4.235(D) a proving guard whose reviewer mutation survives means the fix is not proven. Add a `fire` case for a command word that only starts with an interpreter name (and, for RM14 below, a jq-through-variable line with a redirection).

Other reviewer mutants on the new code: RM4 (file branch never armed by a jq command line naming it) killed by A6; RM12 (`>>?` -> `>>`) killed by Q6; RM14 (any word before `>FILE` counts as a file writer) survived, but it is a mutant of a branch that only disowns cat/printf/echo/tee, so I record it with F2 as a missing case, not as a separate finding.

### F3 (important, test-instrumentation, minor-class under 11.4.276(G.2), must be a tracked follow-up or fixed with F1) — the KNOWN-FAIL accepts ANY failure of the case, so a genuine regression of the property the case guards passes as "known"

`kchk` counts the case as KNOWN-FAIL whenever its rc is not 0. The case "N3 negative" guards three things: `echo "a command . b"`, `jq -e . "$0"` (argument) and `# eval ". x"` (comment) must not be read as source statements. CON-047's failure is a different thing (rc 1, one UNCOVERED jq-env row at cm_killpg_pgid_guard.sh:425). Reviewer mutant RM3 (eval-of-source detection reads the raw line, so comments trigger it) re-introduces the comment defect: on the N3 line it makes the census BLIND (`UNRESOLVED-SOURCE ... eval-of-source-string`, rc 2), does not affect the real tree (census rc 0), and the closure test then prints `KNOWN-FAIL N3 negative ... (rc=2) [tracked CON-047]`, `== 30 passed, 0 failed, 1 known-failure ==`, exit 3: exactly the counts and exit status of the unmutated tree. RM2 (source no longer needs command position) shows the same rc-2 KNOWN-FAIL line on the case, and is killed only because 21 other cases fail collaterally. So while CON-047 is open, the comment clause and the echo clause of "N3 negative" are guarded by nothing (the `jq -e .` clause is still covered by the control needle fixture). The meta-test would report such a mutant as SURVIVED (crc 3 is not 1), which is the right direction, but no such mutant is in its list.

Fix: pin the KNOWN-FAIL to CON-047's signature (rc 1 AND the only UNCOVERED line is `cm_killpg_pgid_guard.sh:<n> jq-env (indirect)` AND no UNRESOLVED-SOURCE line); anything else is FAIL. Better: run the three source-negative words in a gate file that has no quoted env text (so they stay a real PASS) and keep a separate, signature-pinned KNOWN-FAIL case for CON-047. Also consider the existing signature-matched mechanism `config/full_suite_known_failures.tsv` (path + signature + tracked id) instead of a second, unsigned one (11.4.227 reuse); today the full-suite runner scores the closure test's exit 3 as `FAIL rc_3` (judge(): any rc other than 0/77/124/137/126/127/>=128 is FAIL), which is honest.

### F4 (minor, process-doc) — CON-047 depends on scratch-only artefacts

The CON-047 body names the evidence and case corpus by absolute paths inside the session scratchpad and a `git clone --shared` scratch clone (commit 94a1d28, "no branch pushed"). Scratchpads are session-specific; if they are cleaned, the corpus the item tells the next implementer to reuse is lost (11.4.197, 11.4.215). Push 94a1d28 to a wip ref (no force) or bundle it into the repository, and cite that.

### F5 (minor, test-instrumentation, pre-existing) — the proving guard of CON-015/016 is run by no seam

tests/gates/test_gate_env_census_jq_regions.sh has no row in config/full_suite_manifest.tsv (the runner reports it among 25 census files without a row and refuses to run), and the allowlist meta-test does not call it (its `cen` mutants run only the closure test). The 30 new cases therefore run only when someone runs the file by hand. Pre-existing (the file came in with b7e944c, an ancestor of main), but this batch's fix depends on it.

### F6 (minor, test-instrumentation, pre-existing) — `cen` kills have no unmutated baseline

`cen()` counts a mutant as killed when the closure test returns 1, but the meta-test never runs the unmutated closure test to show it returns 3 (or 0). If the closure test failed for an environmental reason, every `cen` mutant would be "killed" (11.4.273 control). One baseline run before the `cen` list closes it.

### F7 (minor, source-defect, pre-existing, outside this diff's class) — adjacent quoted regions are glued together

`jqlit` joins the armed region texts of a line with `""`, so the text before a region becomes a word character in front of `env`: `jq --arg k 'v' -n 'env | keys'` is quiet ("venv | keys"), `printf '%s\n' 'env | keys' > "$T"; jq -f "$T"` is quiet ("\nenv"). Quiet on main too. Track it (a separator between regions would fix it).

### F8 (nit) — CON-047 history attribution and state fields

item_history records CON-047 as `Opened | User` although an agent created it (the same default as CON-045/046), and the item is a Bug with a measured reproduction (rc 1 vs rc 0) but `reproduction_state` UNSET (11.4.294 allows UNSET at intake; recording `reproduced-host-fixture` with the measurement would be more accurate).

## 3. Checks that passed

- Allowlist rows (c73298a): both new files eval a fixed single-quoted `case "$DG" in CM-?*) grep -F -q -- "$DG" "$BLK" ;; *) false ;; esac` over the local DG read by awk from the registry (cm_state_fields_anchor_wired.sh:403-405, cm_geo_substitute_anchor_wired.sh:318-320), the same shape and reason as the sibling rows; exact paths, no globs. Justified. The gate is PASS with uncovered=0 stale=0, and the census reports exactly those two `<eval>` rows.
- The awk-program false positive (CON-047) cannot make the allowlist gate FAIL-bluff on the real tree: cm_killpg_pgid_guard.sh has no jq word, so the jq-env rule is not active there, and the real-tree census output is identical to main's. It cannot hide a real read either: it is an extra report, never a removed one. It appears only in the closure fixture, where it is recorded as KNOWN-FAIL, never as PASS.
- KNOWN-FAIL semantics otherwise sound: never counted as PASS, XPASS counts as FAIL (forces removal of the marker), exit 1 dominates exit 3, and the meta-test counts only rc 1 as a kill (a mutant that leaves only the known failure is reported SURVIVED).
- Tracker: CON-047 consistent across DB, Issues.md and Issues_Summary.md, engine-made and valid (section 1). Its measured claim (main census PASS, new census FAIL on the N3-negative tree) reproduced.
- No submodule drift, no secret.
- The census change does widen arming on main's undecidable regions (A1–A6, Y1–Y4, D1/D2 all as declared; my probes R7 and R12 fire on the new census and are quiet on main).

## 4. Reviewer-authored mutants (none of them is in the author's set)

| Id | Change (census) | Run against | Result |
|---|---|---|---|
| RM2 | RE_SRC_CMD: `(?:^\|[;&\|({`!]\|` -> `(?:^\|\s\|[;&\|({`!]\|` (source no longer needs command position) | closure test | killed (rc 1, 21 FAIL), but the N3-negative case itself prints `KNOWN-FAIL ... (rc=2)` |
| RM3 | resolve_sources: `if len(cl) == len(line):` -> `if True:` and `finditer(r"\beval\b", cl)` -> `line` (comments trigger eval-of-source) | closure test | **survives as KNOWN-FAIL**: rc 3, 30/0/1, identical to the unmutated tree (F3) |
| RM4 | `_armed` file branch: `or (o[1] != "" and o[1] in jq_text)` -> `or False` | jq-region test | killed by A6 |
| RM8 | RE_NONJQ_CMD: `_INTERP + r"(?![\w.-])"` -> `_INTERP` | jq-region test | **survives**: 38/0 (F2); behaviour change shown by probe `sedjq` |
| RM12 | RE_OUT_FILE `>>?` -> `>>` | jq-region test | killed by Q6 |
| RM14 | RE_OUT_FILE writer word `(?:cat\|printf\|echo)` -> `(?:cat\|printf\|echo\|[a-z_]+)` | jq-region test | survives: 38/0 (recorded with F2) |

Probe scripts: /home/milosvasic/.cache/claude-tmp/claude-1000/-home-milosvasic-Projects-constitution/013b6b97-2330-9750-4ee5-95de77324e46/scratchpad/rvcs.b2JY/probe.sh, probe2.sh, probe3.sh, probe4.sh (each takes a census path and a sandbox dir).

## 5. Verdict

**NO-GO.** F1 is a fail-open regression of a guard introduced by a change whose purpose is fail-closed, and F2 is a surviving reviewer mutation of this batch's own proving guard; both are important source-defects, so 11.4.276(G.2) `GO-with-follow-ups` is not available. F3–F8 are follow-ups (F3 should be fixed in the same round, since its fix is small and it hides real regressions). Re-review needs: G1–G5 as `fire` cases (RED on dbe1b65, GREEN after), an RM8-killing case, and preferably the signature-pinned KNOWN-FAIL.
