# CON-234 class, round 9: every inheritable descriptor closed, RELEASE_ENV_KEEP bounded, the missing tests added

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output and process state), with CON-227..233 touched; vehicle `vehicle/fix227-r9` |
| Round | 9. Operator decision 2026-11-11: review rounds run until GO; every round past 5 is structural (§11.4.276(E)(3)), fresh fixer instance, class-exhaustive (§11.4.276(C)) |
| Review answered | `scratchpad/review_fix227_r8.md` (round-8 head `4c80482c`, NO-GO): F1..F10 and the surviving mutants R1, R4, R5, R6, R8, R9, R10, D1, E1 |
| Author | Claude Opus 5.5 subagent (fixer). The reasoning effort cannot be set or read on this dispatch path (§11.4.231(F.2)); none is claimed |
| RED / GREEN | `red_*.txt` (round-8 scripts and library, run with the round-9 suites) and `green_*.txt` (round-9 head), beside this file |
| Earlier rounds | `../round8/threat_model.md` stays the record of the allow-list and value classes; this file records what round 9 changes |

## 1. What the round-8 review found, and the round-9 answer

| Id | Finding | Round-9 answer | Evidence |
|---|---|---|---|
| F1 | `_rc_env_closefds` skipped every descriptor number of five or more digits (`^[0-9]{1,4}$`), so an inherited fd 10000 or above reached every child | the function now lists `DIR/fd` (`/proc/$$/fd`) and closes every entry whose name is all digits, whatever its length, other than 0, 1, 2 and 9, unless `DIR/fdinfo/N` shows the close-on-exec flag; a descriptor whose flags cannot be read is closed (fail closed); when `DIR/fd` lists nothing (cannot be read) the function returns 1 and `rc_env_clean` refuses with status 3 | RED: `red_redact_cut.txt` (`childfds=12345 100000`), `red_derive_release_facts.txt`, `red_publish_gitea.txt`, `red_tag_and_release.txt` (fds 12345 and 100000 reach the children of the real scripts; fd 300 is already closed). GREEN: the same cases pass |
| F2 | the census never tested a descriptor of 100 or above, nor a 5-digit one | each of the four suites opens fds 7, 300, 12345 and 100000 in the caller (soft `ulimit -n` raised to the hard limit first; when the limit stays at or below 100000 the case is SKIPPED, exit 77, never passed) and checks that no child of the library driver (K9) or of the real derive, publisher and tag scripts (their recorders) holds one; a census control first shows that the recorder does see those four descriptors when they are inherited | `green_*.txt`: `K9`, `F1` (derive), `29b` (publish), `C50` (tag) |
| F3, F4 | the token shapes `gho_ ghu_ ghs_ ghr_ github_pat_ glpat-`, control characters other than newline, the 4096-byte cap, an `SSH_AUTH_SOCK` naming a regular file or a directory, and a locale value with user information but no scheme were not tested | K9 shape table (`sh9`): every token shape in LC_TIME, PATH and USER, upper case too; bytes 01 07 09 0d 1b 7f in PATH and GIT_SSH_COMMAND; a 4096-byte PATH kept, 4097 dropped; SSH_AUTH_SOCK as a socket (kept), a regular file and a directory (dropped); `u:ZZPW9@host`, `C:UTF-8` and `en_US/x` dropped and `sr_RS.UTF-8@latin` kept for LANG, LC_ALL, LC_TIME and LC_MESSAGES. The `classes` instrument (`tests/release/env_census.py classes`) now runs the 14 common bad values and a per-class list of shape-bad values on every allow-listed name | `green_redact_cut.txt`, `green_classes.txt`; RR4, RR5, RR6, RR8, RR9, RR10 killed (`mutations.txt`) |
| F5 | C11 (redact suite) and C22, C23 (tag suite) skipped without exit 77 | both suites count their skips and end with `suite_exit` | the suites' last lines; their skips were not taken on this host |
| F6 | D1 (derive, the `""` guard of the remote-refs loop removed) was not killed | a test with a remote that has no refs and a base one commit behind HEAD expects `unmerged_refs_count[rnone9]=0`, `unmerged_refs[rnone9]=` and the real ref of a second remote counted | `green_derive_release_facts.txt`; RD1 killed |
| F7 | `RELEASE_ENV_KEEP` names bypassed the value checks, and the variable is usable outside the tests (`GIT_CONFIG_PARAMETERS` with an `http.extraheader` reached the children) | (CORRECTED in round 10, R9-1 of the round-9 review: the claim below that every name ssh reads is refused was wrong; `LANG*`, `LC_*`, `COLORTERM` and `NO_COLOR`, which ssh sends, still passed. See `../round10/threat_model.md`.) nothing can tell a test from a caller, so the variable stays and is bounded: names of the channels git, ssh, curl, gh, glab and the loader read (`GIT_*`, `SSH_*`, `CURL_*`, `GH_*`, `GLAB_*`, `GITLAB_*`, `LD_*`) and `*_URL`, `*_URI` are refused, as are names bash gives a meaning of its own (`_rc_env_reserved`); the value of an added name gets the common checks (`_rc_env_common_ok`: 4096 bytes, no control character, no URL user information, no token shape). The comment that said no value check applies is corrected | RED: 9 `K9 F7` failures in `red_redact_cut.txt`; GREEN passes; H1-H4 killed (`mutations.txt`). H4 first survived (`mutations_targeted_pre_h4fix.txt`: the `*_URL` test value carried user information, so the value check dropped it anyway); the suite now also keeps `API_URL=https://zzurl9.example/x` and `API_URI=zzuri9:x` in `RELEASE_ENV_KEEP` and expects them refused by name |
| F8 | `LANGUAGE` keeps `user:hunter2@host` (user information without a scheme; LANGUAGE is not a SendEnv name, so it stays on the host); a 40-hex Gitea token in `LC_TIME` is kept (the documented bare-word limit) | NOT changed in round 9: the round-9 brief did not list F8. Open for the lander as a nit follow-up (§11.4.276(G.2)); the LANGUAGE regex still allows `:` and `@` | — |
| F9 | E1 (`= 1` changed to `-n` in `suite_exit`) survived | `test_channel_census.sh` sources `${ENV_ALLOW_LIB:-…}` and checks that 0, an empty value, `yes`, `true` and `11` still give 77, and that a failure with `RELEASE_TESTS_ALLOW_SKIP=1` gives 1; the harness runs mutant RE1 against a mutated copy of `env_allow.sh` | RE1 killed. The checks pass on the round-8 source too (`red_channel_census.txt`, 39/0): the source was right, only the test was missing |
| F10 | 8 commits of the range `02c10935..4c80482c` have no `Roadmap-Item:` trailer that git parses | recorded here for the lander (§11.4.293(A)); history is not rewritten (§11.4.113). Measured with `git interpret-trailers --parse`: `9cd1539a`, `66b411ef`, `1089054b`, `7b42614d`, `34bbeb4e`, `b4526da6`, `858a47e2`, `23c301e6`. `9cd1539a` holds a `Roadmap-Item:` line, but in a paragraph of its own before the `Co-Authored-By:` paragraph, so git does not read it as a trailer. The review says "9 of the 21" and names these 8; the ninth is UNCONFIRMED. The round-9 commit carries `Roadmap-Item: CON-234` and the co-author line in one trailer block | `git log` of the bundle |

## 2. Why the descriptor close is now class-wide

The round-8 function had two independent limits: the name filter (`{1,4}` digits) and the source of the list
(`/proc/$$/fdinfo`, read only for its names). Round 9 removes the length limit entirely (`^[0-9]+$`), takes the list
from `/proc/$$/fd` (the descriptors that exist), reads the flags from the matching `fdinfo` entry, and turns every
uncertainty into a close or a refusal: unreadable flags close the descriptor, an unreadable list refuses the run. The
only descriptors left open are 0, 1, 2, 9 (the state pipe, closed later by `rc_env_clean`) and those that carry
close-on-exec (bash's own, which no child inherits). The function takes the directory as an argument so a test can
drive every decision on a prepared directory (`K9 F1 _rc_env_closefds decisions`), and the live tests drive it
through `/proc` with real descriptors up to 100000.

Mutants of this class (`mutations.txt`): RR1 (two digits), G1 (four, the round-8 shape), G2 (five), G3 (numbers
starting with 1 kept), G4 (fd 300 kept), G5 (one-character glob), G6 (refusal dropped), G7 (status always 0), G8
(unreadable flags kept), G9 (fds of 1000 and above kept), G10 (flags read from another directory), B1, B11, B12 and
A4 re-applied.

## 3. Honest limits (§11.4.6)

- The decision tests on a prepared directory use the round-9 interface (`_rc_env_closefds DIR`). On the round-8
  library that interface does not exist, so part of their RED (`9=open 71=open ...`, status 0) is an interface
  mismatch, not only the defect. The behavioural RED is the live one: `childfds=12345 100000` through the library
  driver and the leaks through the three real scripts.
- The 5-digit and 6-digit cases need a soft descriptor limit above 100000. On this host `ulimit -Hn` is 524288. On a
  host whose hard limit is lower the cases SKIP with exit 77; they never pass silently.
- A `RELEASE_ENV_KEEP` name that is not refused by name and holds a plain secret word (no token shape, no URL user
  information) still passes; the variable is meant for the tests and nothing can tell a secret word from a value.
- `/proc` is Linux; on a system without it `rc_env_clean` now refuses (status 3) instead of running with descriptors
  it could not see.
- Shellcheck: `shellcheck.txt` (rc 0 at `-S warning`).

## 4. Mutation run

`mutations.txt` (full harness, sequential, `nice -n 10`, on the round-9 tree): `RESULT: killed=203 survived=0
equivalent=4 stale=0 control_failures=0 inconclusive=0`, harness rc 0. The six controls pass, including the new
`env_allow.sh` control (a first full run failed that control: the N6 table of `test_channel_census.sh` inherited
the harness's `RELEASE_TESTS_ALLOW_SKIP=1`; it now clears the variable for those calls, and that run was stopped).
The four equivalent mutants X12, Z6, A10 and A14 still survive as recorded; their evidence lines were re-read and
still describe the round-9 code (A10 and A14 do not touch the lines round 9 changed; X12 and Z6 are on the publisher
and the tag script, unchanged). No new equivalent mutant is claimed.
