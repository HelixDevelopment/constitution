# Independent review: fix227 round 8 (CON-234), head 4c80482c

| Field | Value |
|---|---|
| Reviewer | Independent subagent, model Claude Opus 5.5 (`claude-opus-5-5`). The reasoning effort cannot be read on this dispatch path (§11.4.231(F.2)), so no effort level is claimed. |
| Input | bundle `fix227_r8.bundle`, sha256 `8db66bd6740243f15cc2e65e597343dca285eec919cb03f12211b3b3205b51d1` (verified), head `4c80482c0eb29aa01e7dde251375b6b0d2a0b7c1`, parent `4dd5235e`; range `02c10935..HEAD` has 21 commits |
| Workspace | a scratch repo made with `mktemp -d` under the scratchpad, with objects borrowed from the earlier scratch clone `rv7.sN1Y/constitution` through alternates (the bundle needs prerequisite commits). The live checkout was not touched. No fetch, push or forge call was made. |
| Verdict | **NO-GO**: one important source defect (F1). The other findings are minor or nits. |

## 1. Runs (this session, at `nice -n 10`, one after another)

| Suite | Result | rc |
|---|---|---|
| test_redact_cut.sh | pass=187 fail=0 | 0 |
| test_channel_census.sh | pass=33 fail=0 | 0 |
| test_derive_release_facts.sh | pass=92 fail=0 | 0 |
| test_publish_gitea.sh | pass=138 fail=0 | 0 |
| test_tag_and_release.sh | pass=291 fail=0 | 0 |
| test_render_release_entry.sh | pass=19 fail=0, 1 SKIP (RRE_FACTS not set, the documented expected skip) | 0 |
| `shellcheck -S warning` on scripts/release/*.sh and tests/release/*.sh | no output | 0 |
| `scripts/run_full_suite.sh --verify-manifest` | `RESULT: MANIFEST-OK` (total=908) | 0 |

I did not re-run the author's full mutation harness. Its recorded result (`killed=180 survived=0 equivalent=4`) is UNCONFIRMED by me.

## 2. Findings

### F1: IMPORTANT, source-defect. `_rc_env_closefds` leaves every inherited descriptor numbered 10000 or higher open
`[[ $n =~ ^[0-9]{1,4}$ ]] || continue` skips any fd number with five or more digits. Those descriptors are never closed, so they reach every child process. The function fails open on input it does not recognise (§11.4.201(4)). The round-8 claim "every inherited file descriptor above 2 except fd 9 is closed" (comment in redact_cut.sh, threat_model.md section 1 N3) is false. The host's `ulimit -n` is 524288, so any caller can pass such a descriptor (`exec 12345<file`, Python `pass_fds`, and so on).

Evidence, from this session:
- Library driver (`rc_env_clean` then `ls /proc/self/fd` in a child), run with `10000</dev/null 300</dev/null 9</dev/null 7</dev/null`. The child had fds `0 1 10000 2 3`. fd 3 is ls's own directory fd; 300, 9 and 7 were closed.
- The real `scripts/release/derive_release_facts.sh`, with a `git` wrapper on PATH that records `/proc/$$/fd`, run with the same descriptors. The git child had fds `0 1 10 10000 2`. fd 10000 reached git.

This is an incomplete closure of the class that round 8 itself declared (N3, caller descriptors). The fix is small: accept `^[0-9]+$`, or close every number that is not 0-2 or 9. Add a test case that passes a descriptor of 3 digits and one of 5 or more digits (see F2).

### F2: minor, test-instrumentation. The descriptor census tests only fd 7 and fd 63
My mutant R1 (`{1,4}` changed to `{1,2}`, so fds 100 and above are not closed) **survived** every case of test_redact_cut.sh. No test fails when large descriptor numbers leak, so F1 was not caught.

### F3: minor, test-instrumentation. Only one of the stated token shapes is tested
`env_census.py` BAD has one token sample, `ghp_` + 36 characters.
- R5 (the `glpat-` alternative removed) **survived**.
- R6 (`gh[pousr]_` narrowed to `gh[p]_`) **survived**.

Under either mutant, a GitLab token or a `gho_`/`ghs_`/`ghu_`/`ghr_` token is kept in `PATH`, `GIT_SSH_COMMAND` and the path classes. A `glpat-` value even passes the locale shape (`-` is allowed there), so `LC_TIME=glpat-...` would be kept and forwarded off-host by ssh. The source is correct today; the claimed set (`gh?_`, `github_pat_`, `glpat-`) is not pinned by tests.

### F4: minor, test-instrumentation. Several class shapes are not pinned
- R10: the locale class widened to allow `:` and `/` **survived**. A value with user information and no scheme (`u:pw@host`) would then be kept in `LC_*` and sent by ssh. No case covers user information without a scheme.
- R4: `[[:cntrl:]]` narrowed to newline only **survived**. DEL, ESC and other control characters in `PATH` or `GIT_SSH_COMMAND` are not tested.
- R8: `-S` changed to `-e` **survived**. The only bad `SSH_AUTH_SOCK` case is a path that does not exist; there is no case where it names a regular file.
- R9: the 4096-byte cap removed **survived**.

None of these leaks anything with the current source.

### F5: minor, test-instrumentation. The N6 class (a skip hidden in the exit status) is not closed everywhere
Two cases print SKIP without going through `skp`/`suite_exit`, so their suite still exits 0 when they skip:
- `test_redact_cut.sh:119` (`SKIP C11 no C.UTF-8 locale`; the suite ends with `[ "$fail" -eq 0 ]`).
- `test_tag_and_release.sh:242` (`echo "SKIP C22-C23 real gitea publisher: jq or curl is not installed"`, not counted in `skipped`).

On a host without C.UTF-8, or without jq or curl, these suites report a full pass. The comment in `test_render_release_entry.sh:67` says "Every other release suite exits 77 on a skipped case", and the threat model says the render skip is the one expected skip. Both statements are false. This is the §11.4.276(C) class-exhaustive rule not being met.

### F6: minor, test-instrumentation. The new empty-line guard in derive is untested
D1 (the `""|` branch removed from the case in the remote-refs loop) **survived**. Under D1, a remote with no refs gives the here-string one empty line, and `git rev-list --count "$B.."` counts `B..HEAD`. When HEAD is ahead of the base, that would report a false `unmerged_refs[r]=:N` with count 1. This impact is worked out from the code and UNCONFIRMED end to end: the suite only runs with `--base HEAD`, where the count is 0.

T1 (the `[ -n "$u" ] || continue` guard removed in tag) **survived**. I judge it equivalent: `rc_url_has_userinfo ""` returns 1, as checked from the code path.

### F7: minor, source-defect / process-doc. `RELEASE_ENV_KEEP` can be used in production, and the names it adds bypass the round-8 value check
It is documented as "tests only", but nothing enforces that. Its names are kept with no shape check.
- `GIT_CONFIG_PARAMETERS` passes the name filter (it contains none of TOK, SECRET, PASS, PWD, KEY, CRED, AUTH, COOKIE, SESSION, JWT, PROXY).
- Probe: `RELEASE_ENV_KEEP="GIT_CONFIG_PARAMETERS DATABASE_URL"`, with `GIT_CONFIG_PARAMETERS="'http.extraheader'='Authorization: Bearer ZZSEKRIT'"` and `DATABASE_URL=postgres://u:ZZPW@h/db`. Both reached the child environment.

This contradicts the comment above `rc_env_lockdown` that says `GIT_CONFIG_PARAMETERS` is never passed on. The caller has to opt in, and the value goes into same-user environ only, so the severity is minor. Suggested fixes: apply `_rc_env_shape_ok`'s common checks to the extra names too, refuse `GIT_CONFIG_*` and URL-shaped values, or gate the variable to the test harness.

### F8: nit, source-defect
- `LANGUAGE` keeps `user:hunter2@host`. User information without a scheme passes, because `:` and `@` are both allowed there. LANGUAGE is not a SendEnv name, so it stays on the host.
- A Gitea token (40 hex characters) in `LC_TIME` is kept and would be sent by ssh. This is covered by the documented limit that a bare word cannot be recognised.

### F9: nit, test-instrumentation
E1 (`= 1` changed to `-n`) **survived**. With it, `RELEASE_TESTS_ALLOW_SKIP=0` would also allow skips. This is harmless.

### F10: nit, process-doc. Trailers in the range
- 9 of the 21 commits have no `Roadmap-Item:` trailer: 9cd1539a, 66b411ef, 1089054b, 7b42614d, 34bbeb4e, b4526da6, 858a47e2, 23c301e6 (rounds 1 to 5 and merges). History cannot be rewritten (§11.4.113), so this should be recorded in the landing notes (§11.4.293(A)).
- The round-8 commit has `Roadmap-Item: CON-234` and `Co-Authored-By: Claude Opus 5.5`.
- 34bbeb4e and b4526da6 carry a `Claude Sonnet 5.5` co-author.

## 3. Attempts that held (the round-8 mechanisms worked)
- An `LC_*` name that is not a locale category (LC_ZZTOKEN) was dropped. Values in LC_PAPER with DEL and in LC_NAME with byte 0x85 were dropped.
- A sourced wrapper ran once and got rc=4. A script run from stdin got rc=4. `bash -c '. ./drv.sh' ./drv.sh` re-executed the correct script, which is acceptable.
- argv0 set to the marker with a dirty environment gave rc=4 (loop guard).
- A process that was already clean, with a forged fd 9 carrying `GH_TOKEN` and `LC_TIME=ghp_...`, kept neither (the lockdown after restore dropped both).
- Under `bash -x` with `PS4='+${HOME}'`, the first process traces with the caller's PS4, as documented in N7.

## 4. Mutants written by me (20; none of them is an author mutant)

| Id | Change | Result |
|---|---|---|
| R1 | closefds fd regex `{1,4}` to `{1,2}` | **survived** (F2) |
| R2 | keep fd 7 instead of fd 9 | killed (7 FAIL) |
| R3 | wrong close-on-exec bit (`0200000`) | survived. Benign: it closes more descriptors, bash's own included, and the suites still pass. |
| R4 | `[[:cntrl:]]` narrowed to newline | **survived** (F4) |
| R5 | `glpat-` alternative removed | **survived** (F3) |
| R6 | `gh[pousr]_` narrowed to `gh[p]_` | **survived** (F3) |
| R7 | GH_HOST regex without `^` | killed |
| R8 | SSH_AUTH_SOCK `-S` changed to `-e` | **survived** (F4) |
| R9 | 4096-byte cap removed | **survived** (F4) |
| R10 | locale class allows `:` and `/` | **survived** (F4) |
| R11 | LANGUAGE allows `/` and space | killed |
| R12 | `BASH_SOURCE[-1]` check removed | survived. I judge it equivalent, UNCONFIRMED: it would need the script to source itself. |
| R13 | `BASH_SOURCE[1]` check removed | killed |
| R14 | loop guard returns 0 | killed |
| R15 | closefds also closes fd 9 | killed |
| R16 | SSH_AUTH_SOCK always kept | killed |
| R17 | names with no class are kept | killed |
| D1 | derive `""` guard removed | **survived** (F6) |
| T1 | tag empty-URL guard removed | survived, equivalent (F6) |
| E1 | ALLOW_SKIP `= 1` changed to `-n` | survived (F9) |

Totals: 9 killed, 11 survived. Of the survivors, 3 are equivalent or benign (R3, R12, T1); 8 expose test gaps (R1, R4, R5, R6, R8, R9, R10, D1, plus E1 as a nit). None of the survivors leaks anything with the current source. R1, R5, R6 and R10 would leak if the source regressed in that way.

## 5. Equivalent mutants claimed by the author
- **A10** (first lockdown removed): I agree it is equivalent. `exec -c` empties the environment of the new process. The dump subshell runs builtins only. After restore, the lockdown un-exports every unlisted name and every bad value. The residue is that caller variables become unexported shell variables in the clean process; the scripts assign their working variables before use (DBDIR, RUNDIR, `unset -v _rpg_tok`).
- **A14** (`${!v+x}` changed to `${!v:-}`): I agree it is equivalent. `M3W_GITEA_TOKEN` is used only through `${..+x}` and then `${!TOKEN_VAR:-}`. `RELEASE_NET_TIMEOUT` is read through `:-600`.
- **X12** and **Z6**: not re-measured; I accept them from the earlier rounds. UNCONFIRMED by me.

## 6. Hygiene
- The synthetic tokens in the range are all fixture needles (`ghp_ZZ...`, `ghp_LEAKSHRINK...`, `github_pat_ZZT2...`, `glpat-ZZT3...`). No real credential was found.
- No forge write and no force push were made in this review. The scratch workspace was removed with `safe_rm_rf`.

## 7. What it takes to reach GO
1. Fix F1 (close every numeric fd except 0, 1, 2 and 9). Add test cases for a 3-digit and a 5-digit or longer descriptor, which kills R1.
2. Optional but recommended, as follow-ups if F1 is fixed: F2 to F7 (the missing token, shape and SKIP-class cases, the D1 test, and `RELEASE_ENV_KEEP`). Under §11.4.276(G.2), F2 to F6 and F9 are test-instrumentation or nit and qualify as follow-up items. F7 is a minor source-defect outside the excluded surfaces, so it may also become a follow-up if the operator agrees.
