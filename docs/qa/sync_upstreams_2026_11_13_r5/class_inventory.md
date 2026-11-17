# Round 5 class inventory — sync-all-upstreams engine

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-14 |
| Last modified | 2026-11-14 |
| Status | PROVISIONAL (fixer's inventory; pending the independent round-5 review) |
| Status summary | The four classes named by the round-4 review (§11.4.276(E) structural round): every member, how it is closed, the test that proves it, or the stated reason it is out of scope. |
| Authority | §11.4.276(E), §11.4.6, §11.4.84, §11.4.263, §11.4.289. |

Engine: `scripts/sync/sync_all_upstreams.py` at the round-5 head of `vehicle/sync-upstreams-r5`.
Ground truth for class (d): `ground_truth/git_precedence_experiments.py` (rows D1–D22, runs 1 and 2 identical)
and `ground_truth/git_uploadpack_experiment.py` (rows D23–D24, runs 1 and 2 identical), git 2.53.0, real git
against scratch repositories (`file://` and loopback only). The experiments were run before the fixes were
written.

"Live check" = `tests/sync/test_robustness.sh` (`scripts/sync/robustness_checks.py`): drives the real engine
wrapper against real git repositories in a sandbox. Where a live check uses `scripts/sync/race_git_shim.py`,
the shim is a test double for the USER (it acts in the work tree at a chosen git call), never for git: every
git call still reaches the real binary. "Unit" = `tests/sync/test_unit.py` (gate-logic class: a scripted git
model, §11.4.289; it proves the decision logic, not git's behaviour).

## (a) User state that changes between inspection and the write

Every write runs in `write_git`. The table lists every precondition of a write and where it is read again.
"Re-read at write" means: read again inside `write_git`, after inspection, as the last checks before git is
started.

| # | Precondition | Inspection | Re-read at write | Proof (RED on round 4 → GREEN on round 5) |
|---|---|---|---|---|
| a1 | Every git call of the repository answered | whole run | step 0 (`unresolved_for`) | existing (round 3 F-series; `test_faults.sh`) |
| a2 | Work tree clean (`status --porcelain`) | inspect_local | step 1 | existing; live `autostash` (V02) |
| a3 | No operation in progress (MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, BISECT_LOG, rebase-*, index.lock) | inspect_local | step 1 (`in_progress`) | existing (V05–V07) |
| a4 | No ignored file overwritten or removed by the move | — | step 2 (`clobber_guard`) | existing (round 2 I-3) |
| a5 | Parent INDEX still records the gitlink this run discovered (pin writes) | discover | step 3 | existing (M67) |
| a6 | Parent HEAD TREE still records that gitlink (a commit in the parent moved it) — **new, RV4-2** | discover | step 3 | unit `test_parent_head_tree_changed_blocks`; mutant P07 |
| a7 | Index gitlink equal to HEAD-tree gitlink (a gitlink the USER staged, or one an earlier `--advance-pins` run staged) — **new, RV4-2** | discover (`gitlink_staged`) + write_git step 3 | reported `gitlink-staged:<path>` (attention, exit 4) without holding back the rest of the repository; the staged path itself is never written over (step 3 refuses `blocked:parent-index-changed`, which is then `write-blocked:…`, attention). Decided 2026-11-14 (round 5): a stage equal to the submodule's checkout is NOT re-advanced either, because that is exactly the reviewer's P32 case (user checks out X and stages it); the tests ui 4, security 3 and hardening M67 were changed to expect attention | live `staged_gitlink` (RED on r4: user's staged pin overwritten); mutants P06, P08 |
| a8 | HEAD is the commit read at inspection — **new, RV4-1** | inspect_local (`head_before`) | step 4 (`read_head`) | live `race_commit` (RED on r4: user commit orphaned, report APPLIED); unit `test_moved_head_at_write_time_blocks`; mutant P01 |
| a9 | Symbolic ref: fast-forward needs the SAME branch, a pin write needs a DETACHED HEAD — **new, RV4-1** | inspect_local (`read_branch`) | step 4 (`read_branch`, three states: branch / detached / unknown) | live `race_switch` (r4 advanced `topic`), `race_sub_branch` (r4 detached a branch); unit `test_branch_at_write_time_blocks_a_pin_write`, `test_unread_branch_at_write_time_blocks`; mutants P02, P03, P32 |
| a10 | The write landed: HEAD == target and branch / detached state unchanged — **new, RV4-1** | — | step 6 (post-write verify, final reads) | unit `test_head_not_at_target_after_write_is_a_failure`; mutant P04 |
| a11 | A head that moved, but not to what THIS run wrote, is not reported as this run's update — **new, RV4-1** | — | classification (`_wrote_to` vs `head_after`: `head-changed-during-run`, blocking) | live `race_other` (an `--apply` run while the user commits on the root: asserts `head-changed-during-run` and `changed_by_other`; RED on the P05 mutant 3/2, `red/red_p05_race_other.txt`, GREEN 5/0), `race_control`; mutant P05 |
| a12 | Remote tip | measure (fetched `refs/remotes/<r>/<branch>`) | NOT re-read. **Scoped out:** the target is a fixed object id chosen at measure time; `merge --ff-only <sha>` itself proves it descends from HEAD. A remote that moves after the fetch makes the target older, never wrong; the next run sees the new tip. |
| a13 | Upstream configuration (`branch.<b>.remote/merge`) | — | **Not a precondition:** the engine never uses the configured upstream; it measures every remote's `<branch>` by exact ref name. |
| a14 | `submodule.<name>.update=none` | — | **Scoped out (RV4-10), tracked:** follow-pin does not read it. Open item `SYNC-R5-OPEN-1` (README). The follow-pin still only moves a clean, detached child that sat exactly at the parent's old gitlink. |
| a15 | The window between the step-4 reads and git's own ref lock | — | **Residual, stated:** a few milliseconds (one `rev-parse`, one `symbolic-ref`, then `merge` / `checkout`). git's own ref lock protects the update itself. A change that lands inside that window is not prevented; step 6 (a10) and a11 report it afterwards. Stated in the manual, never claimed closed. |
| a16 | Another sync run over an overlapping tree — **RV4-11** | — | `lock_repositories`: every repository's git common dir is flocked (O_NOFOLLOW, LOCK_NB) before any fetch or write; a run that cannot take one exits 7 | live `lock_overlap` (RED on r4: proceeded), `lock_symlink` (root lock and, round 5, a submodule's lock: RED on P27 3/2, `red/red_p27_lock_symlink.txt`); mutants P26, P27, V13 |

## (b) Streams and resources a remote (or a hostile repository) can supply

| # | Resource | Bound | Proof |
|---|---|---|---|
| b1 | stdout of one git call | `OUT_CAP` 128 MiB read in 64 KiB pieces; beyond it the call is killed (own group) and gives NO ANSWER (`output-too-large`) — never a truncated value read as an answer | unit `test_stdout_cap_is_no_answer`; mutant P15 |
| b2 | stderr of one git call | only the last `ERR_TAIL` (64 KiB) is kept; the partial first line of the tail is dropped behind `[earlier stderr dropped]` (no half URL, so no userinfo can lose its scheme) | live `huge_stderr` (r4: whole stream in memory, RED); unit `test_stderr_tail_drops_partial_first_line`; mutants P16, P17 |
| b3 | Redaction time | linear: one `rfind("@")` per line, each `://` found once, the backward scheme run cannot pass the previous `://` | live `long_line` (r4: 127 s for one 256 KiB line, RED); unit `test_strip_userinfo_is_linear`, equivalence fuzz against the round-4 algorithm (4 000 random texts); gate: two long texts must redact in < 2 s; mutant P18 |
| b4 | `FETCH_HEAD` | read at most `FETCH_HEAD_CAP` (64 MiB) + 1; larger is unread (no answer), never half-read | existing (round 4) |
| b5 | Evidence files the engine replaces | at most 64 MiB inspected | existing |
| b6 | Time | per-call `--timeout`, run `--deadline` | existing; INCONCLUSIVE |
| b7 | A grandchild that escaped the call's group and holds a pipe | the read loop stops as soon as git itself has exited and nothing is buffered (`p.poll()`), so the pipe is never waited for; then pipes closed, `wait(5)` | `test_chaos.sh` section 7 (git itself times out there); robustness `escaped_after_exit` (git answers and exits while the grandchild holds stderr: the case M53 needs; M53 survived the chaos suite alone in the first round-5 mutation run, RED on the mutant in `red/red_m53_escaped_after_exit.txt`) |
| b8 | Number of refs / ignored files / gitlinks | all read through b1 | — |
| b9 | Disk taken by fetched objects | **Scoped out:** git's own; a fetch of a huge history fills disk like any `git fetch`. Stated in the manual. |
| b10 | Submodule count and depth | `--max-depth` (32), real-path cycle cut | existing |

## (c) Process lifecycle under signals

| # | Event | Behaviour | Proof |
|---|---|---|---|
| c1 | SIGTERM / SIGINT / SIGHUP at any point | handlers installed first in `main` (`proc_on_stop_signals`); the handler only sets `STOP_REQUESTED` | live `sigterm_fetch`, `sigint_fetch` (r4: traceback / no report / orphaned fetch, RED); mutants P09, P11 |
| c2 | A read in flight | its own process group is killed (one guarded place, pgid > 1 and == the child's pid, §11.4.263); it returns `interrupted` | same |
| c3 | A write in flight (`merge`, `checkout`, `add`) | never killed half-way (`level 0`); it finishes, and its result is recorded | live `sigterm_write` (signal sent from inside the write's own git call; the write still completed and is reported moved); mutant P10 |
| c4 | Calls after the stop | refused (`interrupted`), except the FINAL head reads that record what moved, each capped at 10 s | live `no_new_call` (the engine's `git_calls` equals the calls the shim saw: RED on P14, 27 against 23), `final_cap` (final reads that hang after a stop: real 22 s, P33 92 s, RED 2/2); mutants P14, P33 |
| c5 | Second signal | `HARD_STOP`: the final reads stop too | unit `test_second_signal_is_a_hard_stop`; mutant P12 |
| c6 | Exit | the report is written; verdict `INTERRUPTED`, exit 8 (new code), before every other verdict | live sigterm/sigint checks; mutant P13; `sync_step_lib.sh` maps 8 → INTERRUPTED, setup fails, hook warns |
| c7 | SIGKILL / OOM kill of the engine | **Cannot be handled in-process (stated boundary).** A git call in flight runs on in its own session until git's own network timeouts end it. The shipped systemd example unit uses the default `KillMode=control-group`, which kills the whole cgroup. Stated in the manual. |
| c8 | SIGPIPE (stdout closed early) | **Not changed this round; measured** (`green/sigpipe_probe.txt`, 5 runs): no traceback, reports written, exit 120 with `BrokenPipeError` on stderr; 120 is not an engine code, so a caller reads it as BLIND (fail-safe, but not the run's verdict). Open item `SYNC-R5-OPEN-3`: map the final flush failure to the run's own code. |

## (d) Environment and configuration that can re-enable prompts, protocols, helpers, hooks or commands

"Pinned" = a `-c` pair on every call (beats every config file, D19–D22). "Set" / "Dropped" = `git_env`.
Each row cites the ground-truth row that shows git's real precedence, and the test.

| Variable / key | What it can do | Engine | Ground truth | Test |
|---|---|---|---|---|
| `GIT_TERMINAL_PROMPT` | terminal prompt | set `0` | — | existing (gate SET) |
| `GIT_ASKPASS` | askpass program; beats `core.askPass` (D10) | **set empty** (no program, beats config: D9) | D7–D10 | live `askpass` (r4: askpass ran, RED); unit; mutant P19 |
| `core.askPass` | askpass program | **pinned empty** | D8 | mutant P34: behaviourally EQUIVALENT while `GIT_ASKPASS=""` is set (row D9), so the live `askpass` check stays green; killed by the gate (every safe `-c` pair exactly once), survives `--no-gate` |
| `SSH_ASKPASS` | git falls back to it (D11) | dropped | D11–D13 | live `askpass_ssh_only`; mutant V16: behaviourally EQUIVALENT (rows D12, D13: no fallback to `SSH_ASKPASS` when `GIT_ASKPASS` is empty or `core.askPass=` is pinned), killed by the gate, survives `--no-gate` |
| `SSH_ASKPASS_REQUIRE` | ssh: `force` runs askpass without a display | **set `never`** | D12, D13 | live `askpass_ssh_only`; mutant P20 |
| `GCM_INTERACTIVE` | Git Credential Manager UI | set `never` | — | existing |
| `credential.interactive` | helper prompts | pinned `false` | D15 | gate |
| `credential.helper` | runs a helper on auth | **kept by design** (how a user authenticates); it still runs under `-c credential.interactive=false` (D15) | D14, D15 | stated in manual |
| `GIT_ALLOW_PROTOCOL` | beats `-c protocol.ext.allow=never` (D2) | **dropped** | D1–D3 | live `ext_env` (r4: `ext::` command ran, RED); mutant P21 |
| `protocol.ext.allow` | `ext::` runs a command | pinned `never` | D1, D3, D4 (`insteadOf` rewrite also refused) | live `ext_repo` (V01) |
| `GIT_PROTOCOL_FROM_USER` | changes `protocol.*.allow=user` | **dropped** | D5, D6 | live `protocol_from_user` (r4 RED); mutant P22 |
| `GIT_SSL_NO_VERIFY` | turns TLS verification off | **dropped** | — (https not exercised: no network) | unit `test_round5_environment_scrub`; mutant P23 |
| `http.sslVerify=false` in user config | TLS off | **kept (user's config), stated**; not pinned because a user with a private CA may need it |  — | stated in manual |
| `GIT_SSH_COMMAND` (env) | ssh command | **replaced** by `ssh -o BatchMode=yes -o ConnectTimeout=10` (RV4-14: a user's env value is not honoured; documented) | D16 | existing |
| `core.sshCommand` | ssh command | honoured: the engine then runs the call without its own `GIT_SSH_COMMAND` (which would win, D16), reported as `repos[].ssh = "core.sshCommand"`; the call still has no terminal (new session, stdin `/dev/null`) and `SSH_ASKPASS_REQUIRE=never` | D16, D17 | existing |
| `GIT_SSH` | ssh program | dropped | D18 | existing |
| `GIT_PROXY_COMMAND`, `core.gitProxy` | a command for `git://` | env dropped (V15); `core.gitProxy` in the user's config **kept, stated** (not pinnable to "none" without breaking a user who needs it; `git://` not exercised) | — (UNCONFIRMED: no `git://` daemon in the sandbox) | V15 |
| `remote.<name>.uploadpack` (config) | the program run for a `file://` / ssh fetch | **kept, stated: cannot be pinned** — a `-c remote.<n>.uploadpack=` pair does NOT override the repository value (D24) | D23, D24 | stated in manual; `--upload-pack=` on the argv stays refused |
| `core.hooksPath`, `core.fsmonitor` | hooks, fsmonitor command | pinned `/dev/null`, `false` | D19, D20 | existing |
| `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_*`, `GIT_CONFIG_VALUE_*` | inject config | dropped | D21, D22 | existing |
| `GIT_TRACE*`, `GIT_CURL_VERBOSE`, `GIT_REDACT_COOKIES` | write traffic / headers to a file | dropped | — | live `trace_env`; existing unit |
| `GIT_DIR`-class, `GIT_EXEC_PATH` | redirect the repository / git's helpers | dropped | — | existing |
| `filter.<x>.clean` / `smudge` | run commands on status / checkout | **kept, stated boundary** (a user's filter; a hostile filter can only come from the user's own config, never from fetched content) | — | stated in manual |
| `merge.autoStash`, `submodule.recurse`, `fetch.prune*`, `gc.auto`, `maintenance.auto`, `fetch.recurseSubmodules` | side effects of a write / fetch | pinned | — | existing (V02, V03) |
| `GIT_EDITOR`, `core.pager`, aliases | — | **not reached:** `merge --ff-only` opens no editor, calls have no terminal, an alias cannot shadow a built-in subcommand | — | — |

Members closed this round: a6–a11, a16, b1–b3, b7, c1–c6, and in (d) `GIT_ASKPASS`, `core.askPass`,
`SSH_ASKPASS_REQUIRE`, `GIT_ALLOW_PROTOCOL`, `GIT_PROTOCOL_FROM_USER`, `GIT_SSL_NO_VERIFY`. Scoped out with a
reason: a12, a13, a14 (tracked), a15 (residual), b9, c7, c8 (open), and the "kept" rows of (d).

## (e) The run's own evidence directory (RV4-8, RV4-12)

Not one of the four classes the review named; listed because each row is a precondition checked before any
write, and three of its mutants (P24, P29, and P27 for the per-repository lock) survived the first round-5
mutation run until the checks below were added.

| # | Member | Closure | Proof |
|---|---|---|---|
| e1 | `--out` (or the default) missing and cannot be created | `makedirs` fails: exit 2, nothing done | live `out_unwritable` (RED on r4) |
| e2 | `--out` exists but cannot be written | a real probe file (`mkstemp` + unlink) before anything else: exit 2, nothing done | live `out_unwritable` existing-directory case with a writable control (RED on P24 3/2, `red/red_p24_out_unwritable.txt`); mutant P24 |
| e3 | Evidence lost after a write | exit 1 (FAILED) and stderr names what moved, never exit 2 | live `out_lost`; mutant P25 |
| e4 | A relative `XDG_CACHE_HOME` (default directory) | refused (exit 2) on its own, also when the run starts outside the tree | live `default_out_relative` (run from inside the tree, and round 5 from a directory outside it with an absolute-cache control: RED on P29 3/2, `red/red_p29_default_out_relative.txt`); mutant P29 |
| e5 | The default resolves into the work tree through a link | refused (exit 2) after resolution | live `default_out_symlink`; mutant P28 |
