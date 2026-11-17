# Sync upstreams, review round 4: class inventory

| Field | Value |
|---|---|
| Revision | 6 |
| Created | 2026-11-13 |
| Last modified | 2026-11-13T20:26:13Z |
| Status | active |
| Status summary | Every member of the six classes behind the round-3 review findings F1 to F9 (exit-status mapping, swallowed filesystem errors, record fields read before the state changed, credential string paths, signal paths, early-exit pipes under `pipefail`), each with the fix and the check that covers it. Written before the fixes (§11.4.276(C)); three later findings (M67, the blocked-write classification, quadratic redaction) in their own section. Gate-logic / unit-class evidence only (§11.4.289). |
| Issues | two open items |
| Issues summary | a blocked write is classified `behind`, not attention; `redact()` is quadratic in line length (both older than round 4, see [Found at the end of round 4](#found-at-the-end-of-round-4)) |
| Fixed | — |
| Fixed summary | — |
| Continuation | — |

## Table of contents

- [How this inventory was made](#how-this-inventory-was-made)
- [Class A: exit-status mapping of every git call site](#class-a-exit-status-mapping-of-every-git-call-site)
- [Class B: filesystem reads that swallow an error](#class-b-filesystem-reads-that-swallow-an-error)
- [Class C: record fields read before the state they describe changed](#class-c-record-fields-read-before-the-state-they-describe-changed)
- [Class D: every path a credential-bearing string can take](#class-d-every-path-a-credential-bearing-string-can-take)
- [Class E: every signal path](#class-e-every-signal-path)
- [Class F: early-exit pipes under pipefail](#class-f-early-exit-pipes-under-pipefail)
- [Found at the end of round 4](#found-at-the-end-of-round-4)
- [Honest boundary](#honest-boundary)

## How this inventory was made

The classes come from the round-3 review (`review_sync_upstreams_r3.md`, NO-GO). Each finding was taken as one
member of a class and the class was enumerated over the whole vehicle, not only at the reported line:

- class A: the gate's own call-site lister, run with `--print-sites` (added in this round), plus the AST
  lister of `tests/sync/test_faults.sh`; the two must agree (the fault suite fails when a listed site is not
  reached). Functions are named, not line numbers, because line numbers move.
- class B: every `os.path.*`, `os.lstat`, `open(` and `os.open` in `scripts/sync/sync_all_upstreams.py`.
- class C: every assignment to a `head_*`, `moved`, `followed` or `result` field, and every `continue` or
  `return` inside `integrate` and `write_git` that comes after a write.
- class D: every `print`, `say`, `Tty.say` / `Tty.ask`, report field, TSV column and exception text the engine
  can emit, followed back to its source.
- class E: every `kill`, `killpg`, `os.kill` and `kill -9` in `scripts/sync/`, `tests/sync/` and
  `scripts/gates/cm_sync_upstreams_ff_only*.sh`.
- class F: a static scan for a pipe into `grep -q` / `-m` / `-l` / `--quiet`, `head`, `sed …q` or
  `awk …exit` in every shell file of the vehicle; the scan is itself a test (`tests/sync/test_hardening.sh`,
  section "early-exit pipes") with a positive and a negative control.

## Class A: exit-status mapping of every git call site

Rule after this round: every call site declares its `ok` set and, for 128, what 128 means there. The gate
holds an oracle table of every site (function, argument list, `ok` set, `want`, meaning of 128) and compares the
engine's AST with it as a multiset, so a widened `ok` set (reviewer mutants X01, X06), a moved write
(X02, X02b) or a new site fails the gate. The fault suite reads the same table (`--print-sites`) and injects the
real status 128 at every site.

| Site (function: argument list) | `ok` | Exit 128 means | Round-3 member? |
|---|---|---|---|
| `read_head`: `rev-parse --verify -q HEAD^{commit}` | (0, 1) | no answer (BLIND) | — |
| `is_ancestor`: `merge-base --is-ancestor` | (0, 1) | no answer | — |
| `count_range`: `rev-list --left-right --count` | (0,) | no answer | — |
| `commit_present`: `rev-parse --verify -q <sha>^{commit}` | (0, 1) | no answer | — |
| `probe_child` (was `is_repo_root`): `rev-parse --show-toplevel` | (0,) | no answer: the submodule exists but cannot be read (F1) | **F1: was (0, 128) read as "not a repository"** |
| `index_gitlinks`: `ls-files -s -z` | (0,) | no answer | X06 |
| `head_gitlinks`: `ls-tree -r -z HEAD` | (0,) | no answer | — |
| `inspect_local`: `symbolic-ref --short -q HEAD` | (0, 1) | no answer | — |
| `inspect_local`: `rev-parse --absolute-git-dir … FETCH_HEAD` | (0,) | no answer | — |
| `inspect_local`: status (`STATUS_ARGS`) | (0,) | no answer | — |
| `inspect_local`: `remote` | (0,) | no answer | — |
| `inspect_local`: `config --get remote.<n>.url` | (0, 1) | no answer | — |
| `inspect_local`: `config --get core.sshCommand` | (0, 1) | no answer | — |
| `write_git`: status re-read (`STATUS_ARGS`) | (0,) | no answer: no write | **F8 / X01: no test injected 128 here** |
| `write_git`: `merge --ff-only <sha>` | (0, 1, 128) | failed (git refused the merge: not a fast-forward, local changes) | — |
| `write_git`: `checkout --quiet --detach <sha>` | (0, 1, 128) | failed | — |
| `write_git`: `add -- <path>` | (0, 128) | failed | — |
| `ignored_clobbers`: `ls-files -z --others --ignored --exclude-standard` | (0,) | no answer | — |
| `ignored_clobbers`: `ls-tree -r -z --name-only --full-tree <sha>` | (0,) | no answer | — |
| `control_needle`: `rev-list --count HEAD` | (0,) | no answer (needle fails, BLIND) | — |
| `control_needle`: `rev-list --left-right --count HEAD...HEAD` | (0,) | no answer | — |
| `main`: `rev-parse --show-toplevel` (start directory) | (0, 128) | "not a work tree" (exit 2) only when the start directory has no `.git` entry; with a `.git` entry it is BLIND (F1 class) | **F1 class: was always "not a work tree"** |
| `main`: `rev-parse --path-format=absolute --git-common-dir` | (0,) | no answer | — |
| `fetch_repo`: `fetch …` | (0, 1, 128) | the remote failed (unreachable, attention); when the repository's parent moved in the same run to a pin this repository never fetched, the follow is impossible and the repository is FAILED (`follow-blocked:new-pin-unfetchable`, exit 1) | — |
| `evaluate_upstream`: `rev-parse --verify -q refs/remotes/<r>/<b>^{commit}` | (0, 1) | no answer | — |
| `evaluate_pin`: `for-each-ref --contains` | (0,) | no answer | — |

Other members of the class, outside the call-site table:

- a write verb at a call site outside `write_git` (X02, X02b): the gate now refuses a `merge`, `checkout` or `add`
  argument list anywhere but `write_git`, and `fetch_args(...)` anywhere but `fetch_repo`. The round-3
  inventory said the gate already did this; it did not (review finding F6).
- an `ok` set wider than the statuses git can give for the verb (X06, 256 values): the gate now allows only
  sets drawn from {0, 1, 128}, at most three values, and only the set the oracle table records for that site.
- a later `-c` pair that overrides a required safe pair (X07): the runtime argv check now requires each
  required key exactly once, with the required value (case-insensitive key match).

The oracle as the gate prints it (`cm_sync_upstreams_ff_only.sh --print-sites`, 26 sites; columns: function,
argument list, `ok` set, output shape, meaning of 128, argument expression):

```text
read_head	rev-parse --verify -q HEAD^{commit}	0,1	SHA_RE	blind	['rev-parse', '--verify', '-q', 'HEAD^{commit}']
is_ancestor	merge-base --is-ancestor	0,1	-	blind	['merge-base', '--is-ancestor', a, b]
count_range	rev-list --left-right --count	0	TWO_COUNTS_RE	blind	['rev-list', '--left-right', '--count', '%s...%s' % (a, b)]
commit_present	rev-parse --verify -q	0,1	SHA_RE	blind	['rev-parse', '--verify', '-q', '%s^{commit}' % sha]
probe_child	rev-parse --show-toplevel	0	ABS_PATH_RE	blind	['rev-parse', '--show-toplevel']
index_gitlinks	ls-files -s -z	0	-	blind	['ls-files', '-s', '-z']
head_gitlinks	ls-tree -r -z HEAD	0	-	blind	['ls-tree', '-r', '-z', 'HEAD']
inspect_local	symbolic-ref --short -q HEAD	0,1	-	blind	['symbolic-ref', '--short', '-q', 'HEAD']
inspect_local	rev-parse --absolute-git-dir --path-format=absolute --git-path FETCH_HEAD	0	TWO_ABS_PATHS_RE	blind	['rev-parse', '--absolute-git-dir', '--path-format=absolute', '--git-path', 'FETCH_HEAD']
inspect_local	status --porcelain=v1 --ignore-submodules=all --untracked-files=normal	0	-	blind	STATUS_ARGS
inspect_local	remote	0	-	blind	['remote']
inspect_local	config --get	0,1	-	blind	['config', '--get', 'remote.%s.url' % n]
inspect_local	config --get core.sshCommand	0,1	-	blind	['config', '--get', 'core.sshCommand']
fetch_repo	fetch	0,1,128	-	unreachable	fetch_args(rem['_name'], tags)
evaluate_upstream	rev-parse --verify -q	0,1	SHA_RE	blind	['rev-parse', '--verify', '-q', 'refs/remotes/%s/%s^{commit}' % (rem['_name'], branch)]
evaluate_pin	for-each-ref --contains	0	-	blind	['for-each-ref', '--contains', gitlink, '--format=%(refname)', 'refs/remotes']
write_git	status --porcelain=v1 --ignore-submodules=all --untracked-files=normal	0	-	blind	STATUS_ARGS
write_git	merge --ff-only	0,1,128	-	failed	['merge', '--ff-only', target]
write_git	checkout --quiet --detach	0,1,128	-	failed	['checkout', '--quiet', '--detach', target]
write_git	add --	0,128	-	failed	['add', '--', rec['path_in_parent']]
ignored_clobbers	ls-files -z --others --ignored --exclude-standard	0	-	blind	['ls-files', '-z', '--others', '--ignored', '--exclude-standard']
ignored_clobbers	ls-tree -r -z --name-only --full-tree	0	-	blind	['ls-tree', '-r', '-z', '--name-only', '--full-tree', target]
control_needle	rev-list --count HEAD	0	DIGITS_RE	blind	['rev-list', '--count', 'HEAD']
control_needle	rev-list --left-right --count HEAD...HEAD	0	TWO_COUNTS_RE	blind	['rev-list', '--left-right', '--count', 'HEAD...HEAD']
main	rev-parse --show-toplevel	0,128	ABS_PATH_RE	start-dir	['rev-parse', '--show-toplevel']
main	rev-parse --path-format=absolute --git-common-dir	0	ABS_PATH_RE	blind	['rev-parse', '--path-format=absolute', '--git-common-dir']
```

## Class B: filesystem reads that swallow an error

`os.path.exists`, `isdir`, `isfile` and `lexists` return `False` for "permission denied" and for "path too long"
as well as for "not there". Where that `False` decides that something is absent, an unreadable thing is read
as absent: the same "unread is never clean" class as F1.

| Read (function) | What a swallowed error became in round 3 | Round 4 |
|---|---|---|
| `is_repo_root`: `isdir(path)` and `exists(path/.git)` | "not a repository": the submodule shows as not initialised, its subtree vanishes | `path_kind()` (one `os.lstat`, errors other than "not found" are "unreadable"); `probe_child()` records an unreadable path as a no-answer, never as uninitialised |
| `discover`: `lexists(child)` | "absent" | `path_kind()`: unreadable is a no-answer |
| `in_progress`: `exists(gitdir/<name>)` | "no operation in progress": a write could proceed | `path_kind()`: unreadable counts as in progress (`<name>?unreadable`), which blocks the write |
| `run`: `isfile(post_update_hook.sh)` / `isfile(Constitution.md)` | a hint not printed | unchanged: it only decides whether to print an optional hint; never a decision about the tree (documented) |
| `fetched_branches`: `open(FETCH_HEAD)` | already a no-answer in round 3 | unchanged |
| `evidence_file_ours`: `os.lstat` | already refuses (not ours) | unchanged |

## Class C: record fields read before the state they describe changed

| Field | Where it went stale in round 3 | Round 4 |
|---|---|---|
| `head_after` | read only at the end of an `integrate` iteration: a `continue` after a follow-pin, after an advance-pin whose checkout succeeded and whose add failed, or after a write that answered nothing left it unset, and `run` then copied `head_before` into it (F2) | read once for EVERY initialised repository after the whole integration pass, so every exit path is covered; in apply mode a value that could not be read is a no-answer (`head-after-not-read`), never a copy of `head_before` |
| `head_after` in the `want` test of an advance-pin | used before it existed (always fell back to `head_before`) | uses `head_before` directly (a repository that followed in this run is excluded by `followed`) |
| `result = updated` | "moved" alone decided it, even when a blocking reason (for example an unreachable remote after a follow) stood | `updated` only when the repository moved AND no blocking reason stands; otherwise `attention`, with `moved: true` recorded |
| `branch` / detached state before an advance-pin | not checked: `--advance-pins` detached a submodule that was on a local branch (F3) | refused as follow-pin does: `advance-skipped:submodule-on-branch`, reason `kept-on-branch:advance-pin` (attention) |
| `moved` (added 2026-11-13, found while running the mutation table) | not a stale read in round 3, but no test held the field against the disk; with the post-pass head read of round 4, mutant M59 (the `head_before is not None` term removed) reports `moved: true` for a repository whose first head read gave no answer and whose second one did, although it never moved. The round-3 proof that M59 is equivalent ended with "`head_after` = `head_before` (None)", which round 4 made false | the engine is unchanged (it already requires both heads); `tests/sync/test_faults.sh` now checks the field against the disk: in the control run the moved set equals the set of repositories whose HEAD changed, in every fault run a repository reported as moved has a changed HEAD. M59 is removed from the equivalent list and runs the fault suite; on a head-read-only copy of the fault suite it fails 4 runs (`moved-in-report-not-on-disk`) and the real engine passes (`red_m59_record_check.txt`, `green_record_check.txt`) |

## Class D: every path a credential-bearing string can take

| Path | Source of the string | Round 4 |
|---|---|---|
| `strip_userinfo` | any text with `scheme://` | the URL token now runs from the scheme mark to the end of the LINE, with no length limit and no cut at the next scheme mark; a mark inside an already-removed token is skipped (X05 and its class: a long secret, a secret holding `://`) |
| `redact_url` (new) | a remote URL from `config --get` | the whole value is one URL (newline-safe), used for the report's `url` field |
| known-secret registry (new) | the userinfo of every remote URL read, before any fetch thread starts | every registered piece (8 characters or more) is replaced everywhere before the structural cut, so git stderr that quotes a secret without its URL is also cleaned |
| `Authorization:` / `Proxy-Authorization:` header values | git stderr under curl tracing | redacted by pattern; the tracing variables that print them are also removed from the environment (F7) |
| report keys | a key could hold a path or a remote name | `redact_report` now redacts keys as well as values |
| argparse error messages | an unknown option that holds a URL | `ArgParser.error()` prints the redacted message |
| an unexpected exception | any exception text | the top-level handler prints the redacted type and message and `RESULT: FAILED exit=1` |
| the evidence-write `OSError` | a path in the error text | redacted |
| TSV, `say`, `Tty.say`, `Tty.ask` | report fields | already redacted (round 3); unchanged |
| `git_env` | inherited environment | also drops every `GIT_TRACE*` variable (including `GIT_TRACE2*`), `GIT_CURL_VERBOSE` and `GIT_TRACE_REDACT` (F7) |

## Class E: every signal path

| Site | Sends to | Guard after round 4 | Covered by |
|---|---|---|---|
| `proc_kill_group` (engine) | the process group of a git call the engine started in its own session | `os.getpgid(p.pid)` bound once; the call runs only inside `if isinstance(pgid, int) and pgid > 1 and pgid == p.pid:` — the gate now requires exactly that conjunction (no `or`, no `not`, no constant) and exactly `os.killpg(pgid, signal.SIGKILL)` | gate (X04 and seven new static shapes), unit tests with a patched `os.getpgid` / `os.killpg` (pgid 1, 0, -1, a string, `True`, a foreign pgid, `OSError`: never a signal; pgid equal to the child's pid: exactly one), and a real positive control (a child in its own session ends with -9) and a real negative control (a pgid that is not the child's is never signalled) |
| `tests/sync/test_mutations.py`, `run()` | its own suite child, started with `start_new_session` | `pgid = p.pid`, `> 1`, and `os.getpgid(p.pid) == pgid` (read; an `OSError` sends nothing) | ADDED in round 4: revision 1 of this inventory listed the `getpgid` check as already present; it was not (the round-3 harness checked `pgid > 1` only). Found while adopting the reviewer's mutants, whose harness had it |
| `tests/sync/test_chaos.sh` trap | background pids this suite recorded | `case` refuses empty, non-numeric, 0 and 1 | unchanged |
| `tests/sync/test_chaos.sh` escaper cleanup | its own `sleep 45` escaper | the command line is now read into a variable and matched with `case` (no pipe; class F) | chaos |
| fault shim, hardening shim, unit fake git | the shim's own pid (`kill -9 $$`) | a process can only signal itself here | unchanged |

## Class F: early-exit pipes under pipefail

A pipeline `producer | grep -q …` returns 141 when `grep` exits on the first match while the producer is still
writing (SIGPIPE). Under `pipefail` an `if` then takes the "no match" branch: the guard fails open exactly on the
input that should match. Found by the round-3 review in `tests/install/lib.sh` (F4) and in
`tests/sync/test_chaos.sh` (nit).

| Site | Round 4 |
|---|---|
| `tests/install/lib.sh`, `_refuse_shallow` (partial-clone check) | `_partial_refused` reads the config lines from a here-string in pure bash, no pipe and no external process; tested with a deterministic large input (a match on the first line followed by more than 128 KiB), with the round-3 pipeline as a control needle that returns 141 on the same input |
| `tests/sync/test_chaos.sh`, escaper cleanup | no pipe (class E) |
| `scripts/gates/cm_sync_upstreams_ff_only_mutation_test.sh`, failure excerpt | here-string instead of `printf | grep -m1` (display only, but the class is closed in every vehicle file) |
| `scripts/install_constitution.sh` (13 hits in round 3) | NOT in this vehicle: another fixer owns it (`vehicle/installer-sigpipe`). The lander must land that vehicle too. |

The static scan in `tests/sync/test_hardening.sh` keeps the class closed for every shell file of this vehicle.

## Found at the end of round 4

Four findings that are not members of the six classes above, found after the fixes while the evidence was
taken. None is a review-round-3 finding.

| Finding | How it was found | Round 4 |
|---|---|---|
| M67 survived: no test changes the parent's index between discovery and the writer's re-read (step 3 of `write_git`), so removing the re-read is not caught | the full mutation table (M67 SURVIVED); the round-3 suites on the round-3 engine pass M67 too, so the round-3 inventory's claim that hardening killed it was not true ([evidence](m67_r3_suites.txt)) | `tests/sync/test_hardening.sh` section 14: a git wrapper stages another gitlink in the root at libs/a's second status read (the writer's re-read); the case checks that libs/a is not checked out, that the other gitlink stays staged and that the action names `blocked:parent-index-changed`, with a control run that advances and stages the pin. M67 fails it; the round-4 engine passes it ([evidence](hardening_s14.txt)) |
| M70 survived: the check that an `--out` report file is a regular file was never the only thing between a case and a pass, because the one symlink case (unit `test_only_our_files`, hardening section 7) links the tsv path to a file whose content the content check refuses anyway | the full mutation table (M70 SURVIVED); the round-3 unit and hardening suites on the round-3 engine pass M70 too ([evidence](m70_r3_suites.txt)) | `tests/sync/test_hardening.sh` section 15: a link to a report this engine wrote, of the same kind, and a FIFO at the report path are both refused with exit 2 and left as they are, with a control run that reuses the directory holding the real report. M70 fails it (the link is replaced by a regular file; the engine blocks on the FIFO until `timeout 120` stops it); the round-4 engine passes it ([evidence](hardening_s15.txt)) |
| A write that a guard blocks (tree changed, parent index changed) leaves the repository `behind` (exit 3, UPDATES-AVAILABLE) with no reason; the ignored-file guard instead gives the reason `ignored-file-would-be-overwritten` (exit 4, ATTENTION) | section 14 of the hardening suite returned exit 3, not the expected 4 | not changed (the engine is unchanged by this): the case pins the current classification (`3 behind`). Whether a blocked write should be ATTENTION is an open item for the next round |
| `redact()` takes time quadratic in the length of a line: `_SCHEME` is searched with `finditer` and rescans a long run of scheme characters from every start | the unit suite took about 10 s, 9.9 s of it in one test (`unit_durations_real.txt`) | not changed; measured on both engines (`redact_scaling.txt`): about 8 s for a 65 536-character line without a URL, about four times as long for each doubling. Open item |

## Honest boundary

This inventory covers the files of this vehicle. It does not cover `scripts/install_constitution.sh` (another
vehicle) or code outside `scripts/sync/`, `tests/sync/`, `tests/install/lib.sh` and the two gate files. The
oracle table proves that every call site has the declared `ok` set and meaning of 128; it does not prove that
git gives 128 only for the reasons listed here (git's exit statuses are not a specified interface). Evidence class:
gate logic and unit / hermetic sandbox runs (§11.4.289), not a live run against real hosted remotes.
