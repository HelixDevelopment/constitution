# Sync upstreams, review round 3: class inventory

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T00:00:00Z |
| Status | active |
| Status summary | Every member of the five finding classes of review round 2 (I-1 F3, I-2 F5, I-3 writes, I-4 / S-1 redaction and environment, m-5 config hardening) with the check that covers it. Gate-logic / unit-class evidence only (§11.4.289). |
| Issues | none |
| Issues summary | — |
| Fixed | — |
| Fixed summary | — |
| Continuation | — |

## Table of contents

- [How this inventory was made](#how-this-inventory-was-made)
- [Class I-1: every git read and write call site](#class-i-1-every-git-read-and-write-call-site)
- [Class I-2: process spawn and signal sites](#class-i-2-process-spawn-and-signal-sites)
- [Class I-3: write paths](#class-i-3-write-paths)
- [Class I-4 and S-1: redaction and environment](#class-i-4-and-s-1-redaction-and-environment)
- [Class m-5: configuration hardening](#class-m-5-configuration-hardening)
- [Honest boundary](#honest-boundary)

## How this inventory was made

The call sites are not a hand list. The call-site lister inside `tests/sync/test_faults.sh` walks the engine's AST
(`scripts/sync/sync_all_upstreams.py`) and prints every `Runner.run` / `g_out` call with its declared
`ok` set (the exit statuses that are answers) and whether it declares an output shape (`want`). The fault
suite `tests/sync/test_faults.sh` runs that lister and FAILS when a listed site is not reached by its
control run, so a new call site cannot be missed by this inventory or by the fault runs. The gate
`CM-SYNC-UPSTREAMS-FF-ONLY` proves from the same AST that every call site passes a literal `ok` tuple
containing 0 and that `want` is a name. Line numbers are those of the round-3 engine at the commit that adds
this file.

## Class I-1: every git read and write call site

A call has an answer only when git exited with a status in the call's `ok` set and, when `want` is set, the
output has the declared shape. A signal, a status outside the set (126, 127, 128 where not declared, 129,
...), a timeout or the deadline give no answer: the repository is `unresolved`, it is never written, and the
run is `BLIND` (exit 6), or `INCONCLUSIVE` (exit 5) when every unresolved call only ran out of time.

| Line | Git call (constant prefix) | ok | want | Covered by |
|---:|---|---|---|---|
| 407 | `rev-parse --verify -q HEAD^{commit}` | 0,1 | yes | faults (sigkill, rc77, garbage), unit |
| 412 | `merge-base --is-ancestor` | 0,1 | — | faults (sigkill, rc77) |
| 418 | `rev-list --left-right --count` | 0 | yes | faults (all three) |
| 427 | `rev-parse --verify -q` | 0,1 | yes | faults (all three) |
| 462 | `rev-parse --show-toplevel` | 0,128 | yes | faults (all three) |
| 483 | `ls-files -s -z` | 0 | — | faults (sigkill, rc77) |
| 499 | `ls-tree -r -z HEAD` | 0 | — | faults (sigkill, rc77) |
| 521 | `symbolic-ref --short -q HEAD` | 0,1 | — | faults (sigkill, rc77) |
| 523 | `rev-parse --absolute-git-dir --path-format=absolute --git-path FETCH_HEAD` | 0 | yes | faults (all three) |
| 528 | `status --porcelain=v1 ...` (precondition) | 0 | — | faults (sigkill, rc77) |
| 530 | `remote` | 0 | — | faults (sigkill, rc77) |
| 536 | `config --get` (remote URL) | 0,1 | — | faults (sigkill, rc77) |
| 544 | `config --get core.sshCommand` | 0,1 | — | faults (sigkill, rc77) |
| 593 | `fetch` (via `fetch_args`) | 0,1,128 | — | faults (sigkill, rc77), chaos |
| 631 | `rev-parse --verify -q` (remote main) | 0,1 | yes | faults (all three) |
| 689 | `for-each-ref --contains` | 0 | — | faults (sigkill, rc77) |
| 888 | `status --porcelain=v1 ...` (write_git re-check) | 0 | — | faults, hardening |
| 911 | `merge --ff-only` | 0,1,128 | — | faults (sigkill, rc77), integration |
| 913 | `checkout --quiet --detach` | 0,1,128 | — | faults (sigkill, rc77), integration |
| 925 | `add --` | 0,128 | — | faults (sigkill, rc77), hardening |
| 943 | `ls-files -z --others --ignored --exclude-standard` | 0 | — | faults (sigkill, rc77), hardening |
| 949 | `ls-tree -r -z --name-only --full-tree` | 0 | — | faults (sigkill, rc77), hardening |
| 1106 | `rev-list --count HEAD` (control needle) | 0 | yes | faults (all three) |
| 1107 | `rev-list --left-right --count HEAD...HEAD` (control needle) | 0 | yes | faults (all three) |
| 1193 | `rev-parse --show-toplevel` (start directory) | 0,128 | yes | faults (all three) |
| 1229 | `rev-parse --path-format=absolute --git-common-dir` | 0 | yes | faults (all three) |

26 sites (the gate reports 27 because it also counts the forwarding call inside `g_out()`, which passes its
caller's own `ok` and `want` on and is checked to do so). Fault modes: `sigkill` (the git process is killed by a signal), `rc77` (an exit status no site
declares), `garbage` (exit 0 with output of the wrong shape, only for sites with `want`). Each fault run
injects one fault at one call of a full `--apply` run and asserts exit 6, the `BLIND` result line, the
faulted repository's result `blind`, and that neither it nor any repository below it moved when the fault
came before its first write. Mutants M61 to M64 and M72 to M73 (no-answer read as an answer, `ok` or
`want` ignored, blind list emptied, blind/failed precedence reversed) are killed; the first killing suite
the harness records is `test_faults.sh` for M61 and M73, `test_unit.py` for M62 to M64 and `test_chaos.sh`
for M72.

## Class I-2: process spawn and signal sites

| Site | Function | Rule (gate `CM-SYNC-UPSTREAMS-FF-ONLY`, AST) |
|---|---|---|
| `subprocess.Popen(git_argv(git_bin, repo, checked), ...)` | `proc_run_git` (line 264) | the only `Popen`; argv is `git_argv(git_bin, repo, checked)`; `checked` is bound once from `check_git_args(args)` before it and `args` is never rebound |
| `os.getpgid(p.pid)`, `os.killpg(pgid, signal.SIGKILL)` | `proc_kill_group` (lines 295, 300) | the only `killpg`, under an `if` whose test contains `pgid > 1` (§11.4.263) |

The gate allow-lists every module attribute the engine may use; `subprocess.*`, `signal.*`, `os.killpg`
and `os.getpgid` are scoped to these two top-level functions; aliases (`P = subprocess.Popen`), `map`,
`getattr`, `importlib`, `from ... import`, `__import__` and other dunders, `global` / `nonlocal`, a nested
`def`, `.kill` / `.terminate` / `.send_signal` and `.run` used as a value are refused. `proc_run_git` is
called once (from `Runner.run`), `proc_kill_group` once (from `proc_run_git`). At run time the gate calls
`proc_run_git` with a forbidden verb (`push`) and requires `GitRefused` before any process starts, and
checks the exact argv of 25 accepted shapes (`-C <repo>`, every `SAFE_CONFIG` pair,
`--no-optional-locks`). Reviewer mutants K01 to K04 are killed by the gate, and the gate's meta-test has 50 cases, each
of which the gate must classify correctly.

## Class I-3: write paths

| Write | Caller | Guard (`write_git`, in order) |
|---|---|---|
| `merge --ff-only <sha>` | fast-forward of a repository (line 847) | 0 no unresolved call for this repository; 1 status re-read must answer and be empty, no merge/rebase/cherry-pick/revert/bisect in progress; 2 `clobber_guard` (no ignored file the target tree would overwrite); 3 the write |
| `checkout --quiet --detach <sha>` | follow-pin of a submodule (line 1020) | the same guard |
| `checkout` then `add -- <path>` | advance-pin (line 860) | the same guard, plus: the parent index must still record the gitlink read earlier |

`write_git` is the only function that runs a write verb; the gate refuses `merge`, `checkout` and `add`
anywhere else. `follow_children` runs only after its parent moved (`moved`), so a child never follows a
gitlink its parent did not take. Reviewer mutants K06, K07 and K11 and own mutants M65, M66, M67 and M37b
are killed by `test_hardening.sh`, K07b by `test_security.sh`, and M61 by `test_faults.sh`.

## Class I-4 and S-1: redaction and environment

| Site | What is redacted / scrubbed | Covered by |
|---|---|---|
| `strip_userinfo` (line 182) | every `scheme://user:secret@host` token cut at the LAST `@` before the host | unit (adversarial shapes: `@` in the password, several `@`, percent-encoding, no scheme), gate RED table (8 shapes), gate meta-test case S1-REDACT, harness mutant M08 (killed by unit) |
| `redact` (line 206) | userinfo plus token-shaped strings | unit, security |
| remote name / URL (lines 534, 538) | token-shaped remote names (n-2) and URLs | security, unit, hardening; K05 (URL written unredacted) killed by hardening, the only suite that asserts the backstop found nothing for a credential URL |
| `fetch_error` and fetch lines (600, 605) | git's stderr | security; K12 killed by hardening |
| action `error` (915, 928), `ignored_clobber` (975) | git's stderr, file names | hardening, security |
| messages and errors (1122 to 1377) | paths and questions printed to the terminal | ui, security |
| `redact_report` (line 213, called at 1369) | backstop over every string in the report; drops `_` fields; `redaction_backstop` must be empty | unit, M71 killed |
| `git_env` (line 313) | removes the scrubbed variables, every `GIT_CONFIG_KEY_*` / `GIT_CONFIG_VALUE_*` and `GIT_CONFIG_PARAMETERS`; sets no-prompt, batch-mode ssh, `LC_ALL=C` | gate (13 injectors), K16 killed |

## Class m-5: configuration hardening

`SAFE_CONFIG` (line 70) is passed as `-c` on every git call: `core.hooksPath=/dev/null`,
`core.fsmonitor=false`, `submodule.recurse=false`, `gc.auto=0`, `maintenance.auto=false`,
`merge.autoStash=false`, `protocol.ext.allow=never`, `fetch.prune=false`, `fetch.pruneTags=false`,
`fetch.recurseSubmodules=false`. The gate checks every pair on the runtime argv of every accepted shape.
The install suite's F6 guard (`tests/install/lib.sh`) checks every promisor and partial-clone setting
(`remote.*.promisor`, `remote.*.partialclonefilter`, `extensions.partialclone`) of every fixture clone.

## Honest boundary

This is gate-logic and unit-class evidence on host fixtures (real git against real bare repositories in
scratch directories, no network). Behaviour against real forges is UNCONFIRMED. A clean filter configured by
the user still runs during `git status` and a smudge filter during checkout or merge; the engine does not
disable them. Evidence retention is an open item.
