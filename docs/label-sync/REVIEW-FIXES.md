# label-sync — review-2 fix round

| Field | Value |
|---|---|
| Document | `docs/label-sync/REVIEW-FIXES.md` |
| Revision | 2 (2026-10-14) — third (re-)review round added |
| Branch | `feature/label-sync` (base `c4b7408`, after the merge `3d002e6` of upstream `2e70099`) |
| Anchors | §11.4.134, §11.4.115, §1.1, §11.4.201, §11.4.6 |

Two independent reviews (Opus, xhigh) returned NO-GO on the branch. This file
lists every finding of both reviews, the commit that closes it, how it was
reproduced RED on the unfixed tree, and the mutant that proves the fix is
load-bearing. The fix round is NOT a GO by itself: it goes back to an
independent re-review (§11.4.134).

How RED was reproduced: the new tests were run against `git archive` subsets
of the pre-fix revision (`c4b7408` for most findings, `edb6615` for the core
prover) and failed there, then passed on the fixed tree. The captured run logs
live in the fixer's host scratch directory and are NOT tracked; every RED is
re-derivable by running the named test against the pre-fix revision.

## Commits

| Commit | Scope |
|---|---|
| `edb6615` | label-busd: bind before writing `bus.addr`, hello size limit, exit 3 for a second instance |
| `89d8f71` | core + MCP: stale sweeper, explicit alias pins, patch id / pid validation, MCP line cap |
| `fd3f71c` | `helix-deps.yaml` refs equal their gitlinks + gate `CM-HELIX-DEPS-REF-MATCHES-GITLINK` |
| `47353b6` | hooks, labeler, post-update hook |
| `c2f6b3c` | adapters, wrapper, skill |
| `564276d` | renderers (shell label refresh), statusline preference, C2 determinism |
| `318affb` | core prover: a kill needs a `--- FAIL:` line, non-compiling mutants are UNDETERMINED (finding 5); 48 mutants |
| `4597875` | MCP: pid range checked at the argument layer (M8 had survived after `89d8f71`); MCP prover 14 mutants |
| `359db9c` | hook mutants (49), `run_step` isolation proven via a test-only fault seam, two post-hook mutants retargeted, hook prover kills need an assertion |
| _this commit_ | render / adapter provers (assertion-required kills), docs, this file |

## Review 1 — core, renderers, hooks

| # | Sev | Finding | Fix | RED on the unfixed tree | Mutant |
|---|---|---|---|---|---|
| 1 | HIGH | `)` in a branch (`fix(ui)`) broke `--derive` (exit 2), made the session follow the active alias, SessionStart said "pinned" | `47353b6`: the labeler maps `)`, ` - `, CR/LF/TAB in branch/alias/model to `_`; SessionStart says "pinned" only when the session really is pinned | hooks suite section 19 failed (part of the 23 failures on the unfixed tree) | `labeler_keeps_paren`, `session_start_always_says_pinned` |
| 2 | HIGH | hooks gate printed PASS with jq/go missing, turned a suite exit 2 into FAIL | `47353b6`: missing jq/git/go or suite exit 2 => gate exit 2 | gate meta cases 14-16 failed on the old gate | meta-test cases 14-16 |
| 3 | MED | a recorded model switch was undone by the next prompt | `47353b6`: `hooks/modelswitch/<sid>` record (model, transcript offset); it wins until a NEWER assistant entry appears | section 19 F3 failed | `model_switch_not_recorded`, `prompt_ignores_model_switch`, `model_switch_never_superseded` |
| 4 | MED | `register --alias … --model … --effort …` ignored the explicit triple and followed ACTIVE (CLI and MCP) | `89d8f71`: an explicit alias pins (CONTRACT §4.2); `update --alias` pins; MCP `label_register` the same | `TestExplicitAliasPinsLikeContract42`, MCP `TestRegisterExplicitAliasPinsAliaslessFollows` failed | core `explicit_alias_follows`, `update_alias_does_not_pin`; MCP M12, M13 |
| 5 | MED | `prove_mutations.sh` counted compile errors as kills | this round: build pre-check per mutant, a kill needs a `--- FAIL:` line, UNDETERMINED class (exit 2), `--selftest`; four mutants rewritten so they compile | the old prover reported `compaction_skips_base` KILLED although it did not compile; `--selftest` exits 2 on a non-compiling mutant | `--selftest` |
| 6 | MED | label-busd wrote `bus.addr` before Listen; render C2 flaky | `edb6615`: Listen first, then write `bus.addr`, remove it on failure; `564276d`: C2 waits for the seq to move | 4 new tests in `cmd/label-busd/review2_test.go` failed (seam `beforeListen`) | core `addr_before_listen` |
| 7 | MED | stale entities never removed after kill -9 | `89d8f71`: bounded sweeper (`LABEL_SYNC_STALE_SWEEP`, default 15m, `off`; batch `LABEL_SYNC_SWEEP_BATCH`, default 256; one fsync per batch) | sweeper tests failed; measured 2000 leftovers: write 76 ms, snapshot 900 KB; after: 13.9 ms, 195 B | `sweep_ignores_age`, `sweep_ignores_liveness`, `sweep_unbounded` |
| 8 | MED | shell labels never refreshed track/branch after `cd` / `git checkout` | `564276d`: `__ls_find_head` / `__ls_place_changed` + `shell-refresh` op | render H3, H4, H4b, H4c failed | render `refresh_ignores_cwd`, `refresh_ignores_head`, `refresh_keeps_stale_branch` |
| 9 | LOW | store-level id check in `update` untested (R1 survived); `prepare()` passed parent/session ids unchecked | `89d8f71`: `prepare()` validates patch ids; fold rejects bad ids | `internal/state/review2_test.go` failed | `patch_id_unchecked_in_prepare`, `patch_id_unchecked_in_fold_R1` |
| 10 | LOW | `"` escape in `ls_emit_context` untested (B2 survived) | `47353b6`: test with branch `q"uote` | section 19 F10 | `emit_context_no_quote_escape` |
| 11 | LOW | statusline session preference untested (B4 survived) | `564276d`: render H1 | the B4 mutant survives the old suite | render `statusline_no_session_preference` |
| 12 | LOW | `--pid -1` accepted | `89d8f71`: pid must be 0..4194304 (`MaxPID`) in the store and the CLI; `4597875`: the MCP argument check enforces the same range (re-running the MCP prover showed its M8 surviving once the store check existed) | `TestBadPidsRejectedRC1` failed; MCP `TestPidOutOfRangeRefusedAtArgumentLayer` failed (MaxPID+1 reached the store) | core `pid_range_unchecked`; MCP M8 |
| 13 | LOW | one binary cache shared by every checkout | `47353b6`: per-checkout cache keyed by module path, `.source-commit` stamp | hooks section 21 failed | `bincache_key_shared`, `bincache_commit_ignored` |
| 14 | LOW | busd: no hello size limit; `bus.addr` left on Listen failure; second instance exit 1 | `edb6615`: `MaxHelloBytes` 4096, address removed on failure, exit 3 (`exitAlreadyRunning`) | review2 busd tests failed | `hello_unlimited`, `second_instance_rc1`, `addr_before_listen` |
| 15 | UNCONF | parallel same-type subagent pairing / Stop semantics; same-user spoofing | `HOOKS.md` §12 known/unknown table; `CONTRACT.md` §8 trust boundary | — (documentation) | — |

## Review 2 — adapters, MCP, installer, merge

| # | Sev | Finding | Fix | RED on the unfixed tree | Mutant |
|---|---|---|---|---|---|
| A | HIGH | kimi/codex edits not idempotent, backups piled up (one held an `api_key`), `--remove` did not restore the original bytes | `c2f6b3c`: recorded separator, exact restore, JSON restore from the matching backup, created configs deleted, backups `O_EXCL` 0600, identical backups deduplicated | 14 idempotency/rollback/backup assertions failed | N9a, N9b, C4, C5, C9, C10 |
| B | HIGH | agents run through the wrapper ignored Ctrl-C | `c2f6b3c`: `( trap - INT QUIT; exec "$@" ) <&0 &`, INT forwarded once | pty Ctrl-C test failed | C1, C2; N8 (stdin) |
| C | MED | invalid consumer `.mcp.json` aborted the post-update hook | `47353b6`: `run_step` isolation; an unparseable file is left untouched with a warning. `359db9c`: no step returns non-zero on a reachable input, so `run_step` is proven through the test-only seam `POST_UPDATE_HOOK_FAULT_STEP` | section 20 C failed; the seam test failed before the seam existed (477/1) | `mcp_dst_parse_check_off`, `run_step_propagates_failure` |
| D | MED | merged `.mcp.json` named a path that does not exist in a consumer | `47353b6`: the path is rewritten relative to the consumer project; `"type"` removed. Whether Claude Code reads `cwd` / `autoApprove`: UNCONFIRMED (`MCP.md`) | section 20 D failed | `mcp_path_not_resolved` |
| E | MED | nothing ran `install_adapters.sh` after a pull | `47353b6`: step 4d, `LABEL_SYNC_ADAPTERS=dry-run` (default) / `apply` / `off` | section 20 E failed | `adapters_step_missing` |
| F | MED | entity registered before the traps (ghost entity, flaky test) | `c2f6b3c`: traps first, then register; deterministic test with a slow labelctl shim | F race test failed | C3 |
| G | MED | `helix-deps.yaml` kept `ref: d88a007` for continuum (gitlink `4639347`) | `fd3f71c`: refs set to their gitlinks; new gate `CM-HELIX-DEPS-REF-MATCHES-GITLINK` (mutation test 5/5) | gate: 3 DRIFT, exit 1 (continuum, plus pre-existing upstream drifts docs_chain and design-toolkit) | gate mutation test |
| H | LOW | hook commands broke on paths with spaces; `$` not refused | `c2f6b3c`: shlex quoting; `$`, backquote, `"`, `\`, newline refused with exit 2 | H tests failed | C6, C8 |
| I | LOW | trailing `--home` / `--agents` with no value hung | `c2f6b3c`: `needv` checks | I test failed | C7 |
| J | LOW | MCP server had no line-size limit | `89d8f71`: `MaxLineBytes` 4 MiB, one -32600 error, serving continues | `TestOversizedLineRejectedAndServingContinues` failed | MCP M14 |
| K | LOW | SKILL.md asked for a 60 s heartbeat and hardcoded `constitution/` | `c2f6b3c`: SKILL.md v1.1.0, event-driven updates, `<C>` path placeholder | — (documentation) | — |
| L | LOW | label-sync scripts skipped step-5 syntax checks; latency asserts failed under a CPU-limited scope | `47353b6`: step 5 checks label-sync `*.sh`; latency bound is wall time unless contention is measured (cgroup `nr_throttled` grew or CPU PSI some avg10 >= 10), then CPU time | section 20 L failed | `labelsync_scripts_not_syntax_checked` |
| M | NOTE | upstream `fa3a9cb` "REHEARSAL: remove kedge" had no recorded operator decision | Operator decided 2026-10-14: keep the untracked `submodules/kedge/` directory untouched. It is not staged, not deleted, not modified by this branch. | — | — |
| N1 | — | MCP `follow_active` default untested | `89d8f71` | MCP test failed | MCP M13 |
| N8 | — | wrapper dropping stdin untested | `c2f6b3c` | stdin test failed | N8 |

## Known limits after this round

- zsh and fish integrations do not refresh the place on `cd` / `git checkout`
  (finding 8 is fixed for bash only). Whether they need it is UNCONFIRMED.
- The full hook proof (before `359db9c`) showed `posthook_4c_aborts_hook` and
  `posthook_nongit_aborts` SURVIVING: once `run_step` isolates a step that
  returns 1, those `return 1` mutants were equivalent. They now mutate to
  `exit 1` (the abort no layer can isolate) and are killed.
- Mutation provers: render, adapter and hook provers now count a kill only
  when the run printed a failing assertion; a run that died without one is
  UNDETERMINED (exit 2). Proven on a scratch copy with a mutant that kills the
  test harness: all three reported UNDETERMINED and exited 2.
- Finding 15 rows in `HOOKS.md` §12 marked UNKNOWN were not observed live.
- `B7` (hostile id) was a hollow assertion before this round; whether the
  reviewer's control run failed for the same reason is UNKNOWN.
- The docs_chain and design-toolkit manifest drifts fixed in `fd3f71c` were
  pre-existing upstream. The parent repository's own `helix-deps.yaml`
  `conflict_resolution` entry that still names `16e4e76` was not touched (out
  of scope for this submodule).

## Review 3 — independent re-review of `edb6615..6dfc57a` (NO-GO, 3 MEDIUM)

| # | Sev | Finding | Fix | RED on the unfixed tree | Mutant |
|---|---|---|---|---|---|
| 1 | MED | `run_step` ran a step as `"$fn" \|\| rc=$?`, turning errexit OFF inside it: a mid-step `ln` failure printed "completed successfully", exit 0, no link | `4bf3cfc`: each step runs in a `set -e` subshell, WARNINGS/ERRORS come back through a temp dir, a failed step is an ERROR (exit 1), later steps still run; `exit`/`set -u` contained; step 5 no longer stops at the first broken script | suite §22: "R1 ln failing in the MIDDLE of install_skills makes the hook exit 1 (got '0' want '1')" and 6 more; §20 "SYNTAX ERROR in …broken.sh" missing after the second broken script | `step_errexit_disabled`, `step_failure_not_error`, `run_step_propagates_failure`, `validate_stops_at_first_error` |
| 2 | MED | the sweeper deleted an entity alive in ANOTHER PID namespace | `e41d76d`: `pid_ns` recorded at register; sweep only when the writer's namespace equals it; a pid patch clears it | `rereview_test.go`: "register does not record the registering process's PID namespace", "an entity with no recorded namespace was swept", "ProcPids does not report its PID namespace" | `sweep_ignores_pid_namespace`, `pid_namespace_not_recorded`, `pid_patch_keeps_namespace` |
| 3 | MED | a vendor-relative MCP command works only when Claude Code starts at the project root (measured by the reviewer, Claude Code 2.1.300) | `4bf3cfc`: the entry is `sh -c '<walk up to the vendored prefix; cd; exec>'`; MCP.md states what was measured | §20 R3: "the merged MCP entry launches through sh (got 'constitution/scripts/…' want 'sh')", the spawn from `sub/deeper` failed | `mcp_not_wrapped` |
| 4 | LOW | `"model":"<synthetic>"` entries undid a model switch / became the label's model | `4bf3cfc`: skipped in the lib and the labeler (jq and no-jq paths) | §19 R4: "(got '<synthetic>' want 'sonnet')", "(got '<synthetic>' want 'haiku')" | `lib_accepts_synthetic`, `labeler_accepts_synthetic` |
| 5 | LOW | binaries stale on ANY commit; no-Go host exited 2 with identical sources | `4bf3cfc`: `bincache.sh ls_bin_stale`, keyed on the module's git tree (`.source-tree`) | §21: "13 control … fresh (got '2' want '0')", "R5 identical source with newer mtimes …", "R5 a prebuilt LABEL_SYNC_BIN without a stamp …" | `bincache_commit_ignored`, `bincache_dirty_ignored` |
| 6 | LOW | an older detached shell refresh could overwrite a newer one; a refresh before shell-start was lost | `d7a76bb`: `--seq` ordering under a per-shell flock, one retry | render H6 "want [hb2] got [hb1-next]", H7 same | `refresh_ignores_order`, `refresh_never_retries`, `integration_omits_seq` |
| 7 | LOW | a signal between the stop check and `child=$!` was lost | `256979b`: re-check `$stop` after the spawn, forward to that one child pid | "a TERM in the spawn window still stops the agent (took 8s, rc 0)" | C11, C12 |
| 8 | NIT | MCP prover counted a non-compiling mutant as INOPERATIVE, exit 1 | `06e2b02`: UNDETERMINED, exit 2; `--selftest` | old prover, scratch copy: "INOPERATIVE X1 does not compile", rc=1 | `--selftest` (rc=2) |
| 9 | NIT | gofmt | `e41d76d` | `gofmt -l` listed 6 files | — |
| 10 | NIT | no test killed the two `bus.addr` removals in busd | `e41d76d`: `writeAddr` seam; `TestStaleAddrRemovedAtStart`, `TestFailedAddrWriteLeavesNoAddr` | the two mutants had no killing test | `stale_addr_not_removed`, `failed_addr_write_left` |
| 11 | NIT | `POST_UPDATE_HOOK_FAULT_STEP` honoured in production | `4bf3cfc`: fault seams need `POST_UPDATE_HOOK_TEST_MODE=1` | §22 R11 "no forced failure appears" failed | `fault_seam_without_test_mode` |
| 12 | — | the round-2 report said `test_wiring_audit_us4` still fails | correction, no code change | — | — |

**Correction (finding 12).** The round-2 report said the anchors test
`test_wiring_audit_us4.py` fails with "positive control 11.4.230 classified as a
gap", unchanged from before the fixes. That was measured from a scratch
directory holding only a symlinked `Constitution.md`, where the checker finds
no code evidence. Run in place (cwd `…/vasic/submodules`, so
`constitution/Constitution.md` resolves to the real checkout) it PASSES
(re-measured 2026-10-14, rc 0). The earlier statement is withdrawn.

**Upstream.** Remote `main` is `5082389` (one commit on top of `2e70099`, already
in the local object store). It changes `Constitution.md`, the four carriers and
`scripts/codegraph/**` + `docs/scripts/codegraph_safe.md`; none of those files
is changed on this branch (`c4b7408..HEAD`), so the next merge has no file
overlap with this work.

**Known limits after this round.** A signal can still end the post-update
hook (no in-process containment). zsh/fish integrations still do not refresh
the place. An entity registered by an older writer (no `pid_ns`), or whose pid
was changed by `update`, is never swept by a namespace-aware writer (kept,
`[stale]`), by design. That Claude Code itself starts the `sh` MCP entry from a
sub-directory was not re-measured with the client after the change; the suite
replays the spawn. The labeler's no-jq fallback matches only entries whose
`message` object starts with `"model"`, which real transcripts (measured on
this host) do not — `model` follows `id` there. A pre-existing limit, not
changed here; with `jq` installed the structural parse is used.

**Re-run battery (2026-10-15), all on the final tree.** `go test -race ./...`
ok; label-busd `-count=30 -cpu 1,4` ok; hooks suite 506/0, render 179/0,
adapters 189/0 (and 30/30 repeated runs); the five `cm_label_sync_*` gates and
`CM-HELIX-DEPS-REF-MATCHES-GITLINK`, each with its mutation test: exit 0.
Provers: core 53/53, MCP 14/14 (`--selftest` exit 2 as designed), render
30/30, adapters 30/30, hooks 57/57 — every kill by a failing assertion.
Two things the battery caught and this round closed or recorded:
- hook mutant `posthook_4c_aborts_hook` SURVIVED: with steps in a subshell,
  `exit 1` in step 4c no longer aborts the hook but turns a recorded warning
  into a failed step (exit 1). §F6 now asserts the refused install is a
  WARNING (hook exit 0, no "step … FAILED"); the mutant is killed.
- one adapter-prover CONTROL run failed with 2 FAILs that the prover did not
  print. Not reproduced in 30 suite runs and 8 further control runs; which
  assertions failed is UNKNOWN. The prover now prints its control's FAIL lines
  so a recurrence is attributable; the voided chunk (A1–A7) was re-run: 7/7.
