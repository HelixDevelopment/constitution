# label-sync — review-2 fix round

| Field | Value |
|---|---|
| Document | `docs/label-sync/REVIEW-FIXES.md` |
| Revision | 1 (2026-10-14) |
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
