# CON-234 class, round 11: one spawn wrapper for every network child, the SendEnv reader removed

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output and process state), with CON-227..233 touched; vehicle `vehicle/fix227-r11` |
| Round | 11, a structural round (§11.4.276(E)(3)): fresh fixer instance; the round-10 mechanism is replaced, not patched |
| Review answered | `review_fix227_r10.md` (this directory, a byte copy of the reviewer's scratch file, sha256 50be17b2d867832281d3e96970c63bc20538e5e55d66c2ecc159476a0a1ea76f; round-10 head `3fe216bd`, NO-GO): R10-1, R10-2 (22 reviewer mutants), R10-3, R10-4, nits N-1 to N-4 |
| Author | Claude Opus 5.5 subagent (fixer). The reasoning effort cannot be set or read on this dispatch path (§11.4.231(F.2)); none is claimed |
| Earlier rounds | `../round10/threat_model.md` (with a round-11 correction note in its section 2), `../round9/threat_model.md`, `../round8/threat_model.md` |

## 1. What the round-10 review found, and the round-11 answer

| Id | Finding | Round-11 answer | Evidence |
|---|---|---|---|
| R10-1 | the SendEnv reader `_rc_env_sendenv` fails open: 13 ssh and git configurations send an opted-in `RELEASE_ENV_KEEP` value to a real sshd | the reader is removed; every network child is started through `rc_net`, which builds the child's environment from a fixed allow-list (section 2). An ssh configuration can only send a variable the child has | `sshd_probe_red_3fe216bd.txt` (LEAK on all 13, both servers), `sshd_probe_green_round11.txt` (36/36 CLEAN) |
| R10-1 (gate) | nothing stops a later change from starting a network child outside the wrapper | `channel_census.py netgate`: a default-deny static gate over every command position of the four release scripts; part 2b of `test_channel_census.sh` runs it with 13 control fixtures (section 3) | `green_channel_census_*.txt` |
| R10-2 | 13 reviewer mutants survived (R01-R11, R13, R20) | R01-R11 mutate removed code and do not apply (section 4); R13 is RT13 (killed); R20 is RT20 (recorded equivalent with a bound proof); the 8 killed reviewer mutants are kept as RT12-RT21 | `mutants.md`, `mutations_*.txt` |
| R10-3 | false claims: `redact_cut.sh:176-177` and `round10/threat_model.md` section 2 | the comment went with the reader; the round-10 file carries a dated correction note (it is the record of round 10 and is not rewritten) | `../round10/threat_model.md` section 2 |
| R10-4 | `GITEA_PAT`, `NPM_PAT`, `DATABASE_DSN`, `SLACK_WEBHOOK`, `X_PRIVATE`, `CLIENT_CERT`, `SIGNING_SALT`, `HMAC`, `OTP` are kept by the credential-word filter | the filter is not widened (a word list is the same open-ended shape the round removes); instead no `RELEASE_ENV_KEEP` name reaches a network child at all. K11 (redact suite) and 29c (publish suite) put all nine names in `RELEASE_ENV_KEEP` with fake values and assert none reaches a network child, while a local child does (control) | `green_redact_cut_*.txt`, `green_publish_gitea_*.txt` |
| N-1 | a 40-hex codeset was a kept locale | the codeset and the modifier are CLOSED lists (`_RC_LOCALE_CODESET`, `_RC_LOCALE_MOD`); K9 R11 drops the 40-hex codeset, a `:`, a blank, a `/` after a known codeset, and keeps 15 real locales (control) | NN12, RT13, B5, RR10 |
| N-2 | under a client `SendEnv *`, base-list values leave the host | stated as a limit (section 5); the network list is now much smaller (no locale, no `USER`, `TERM`, `PWD`, `SHELL`) | — |
| N-3 | the tag suite needs an ambient git identity | the suite sets a local `user.email` and `user.name` in every work repository it creates | `green_tag_and_release_*.txt` run with no git identity in `HOME` |
| N-4 | "LIVE on the library" is not a §11.4.289 class | corrected in the round-10 file; this round labels the suites UNIT/fixture and only the sshd probe LIVE (section 6) | — |

*Correction (2026-11-13, round 12):* the row R10-1 (gate) above calls `netgate` "a default-deny static gate over
every command position". That overstates it: the round-11 gate kept only the command words that `shutil.which()` found on the checking host, and found
command positions with a regular expression, so a quoted, escaped, redirection-prefixed or path command word, a
trap string, `coproc`, `alias`, `command -p` and every program absent on the checking host passed it (the
round-11 review, F1; reviewer mutant RM30b survived the whole tag suite). It was not default-deny, and its result
depended on the host. Round 12 replaces it with a parser that classifies every command by its syntax alone
(`../round12/README.md`).

## 2. The structural change: `rc_net`

`rc_net CMD [ARG...]` (`scripts/release/redact_cut.sh`) is the one way the release scripts start a network child:
git (which can run ssh or a remote helper), ssh, curl, gh, glab, timeout(1) running one of them, and the badge
computer (which runs git). It forks a subshell and, inside it:

1. un-exports every exported variable whose name is not on `_RC_NET_KEEP`, or whose value fails
   `_rc_env_shape_ok` for its name (each name of the list has a value grammar: a path, a socket, a host name, a
   closed set; an unknown name has no grammar and is never passed);
2. exports the constants `LC_ALL=C`, `GIT_TRACE_REDACT=1`, `GIT_TERMINAL_PROMPT=0`, `GIT_TRACE2=0`,
   `GIT_TRACE2_EVENT=0`, `GIT_TRACE2_PERF=0`;
3. lists the exported names once more and refuses (status 125) when anything outside the list and the constants is
   still exported (so a name bash could not un-export is a refusal, not a leak);
4. un-exports every function (bash passes an exported function as an environment entry `BASH_FUNC_name%%`);
5. `builtin exec`s the command.

Every builtin is called as `builtin NAME`, `IFS` is set to blank, tab and newline and globbing is off, so a caller
function named `export` or an `IFS` holding `_` cannot change what is removed. Precondition: the script was
re-executed by `rc_env_clean` (an empty start environment, `_rc_env_state` "clean"); otherwise `rc_net` refuses,
because an inherited environment entry bash does not know as a variable cannot be un-exported.

**Why this closes the class.** ssh's `SendEnv` and `SetEnv` read the client's own environment; a variable the
client process does not have cannot be sent, whatever the configuration says, however the path is spelled, and
whichever file (Include, `-F`, `core.sshCommand`, `include.path`, a `GIT_SSH` wrapper, a `ProxyCommand` jump host)
says it. The allow-list does not depend on reading any configuration, so there is nothing to fail open.

**Local children.** `RELEASE_ENV_KEEP` extras still reach LOCAL children (awk, sed, sqlite3, jq, the tests' fake
tools): that is what the tests need them for. A local child that itself opens a network connection would be a
network child and must go through `rc_net`; the netgate (section 3) treats every command not on its closed local
list as unclassified and refuses it.

*Correction (2026-11-13, round 12):* the last sentence above is not what the round-11 gate did: the round-11 gate kept only the command words that `shutil.which()` found on the checking host, and found
command positions with a regular expression, so a quoted, escaped, redirection-prefixed or path command word, a
trap string, `coproc`, `alias`, `command -p` and every program absent on the checking host passed it (the
round-11 review, F1; reviewer mutant RM30b survived the whole tag suite). It was not default-deny, and its result
depended on the host. Round 12 replaces it with a parser that classifies every command by its syntax alone
(`../round12/README.md`).

## 3. The spawn-site inventory and the gate

`spawn_sites.md` lists every command position of the four release scripts by class (generated from
`channel_census.py`'s scanner and `channels.tsv`): 128 command sites; 52 of them are started through `rc_net`,
directly or through the wrappers `nt` and `net`, whose single-line definitions call `rc_net`: 51 network commands
(git, curl, gh, glab, timeout; the netgate's `network_through_rc_net=51`) and the badge computer (`rc_net bash
scripts/badges/compute_badges.sh`, a listed `ALLOW_EXEC` site, because it runs git).

`channel_census.py netgate SCRIPT...` reads every command position (the census scanner, with quoted text,
`[[ ]]` / `(( ))` operands and comments blanked, backticks, `$( )` and `${ }` followed) and reports:

| Finding | Meaning |
|---|---|
| network command outside rc_net | a command of the closed network set `NETCMDS` not reached through `rc_net`, `nt` or `net` |
| interpreter or exec wrapper not on the allow-list | `env`, `nice`, `bash -c`, `sudo` and the other members of `EXECWRAP`, except three listed call sites (`ALLOW_EXEC`) |
| unclassified command (default deny) | any other command not on the closed local list `LOCAL_OK` |
| awk program that can run a command | `system(`, `\| getline`, `print \|` inside an awk program |
| expansion in command position | `$G fetch`: a command chosen at run time (three listed functions of the library excepted, `DYN_OK`) |
| eval | an `eval` line |

`nt` and `net` are trusted only when their definition is one line whose every command position is `rc_net`
(computed, not assumed: GN3 shows that trusting them by name is caught). Exit 0 clean, 1 findings, 2 BLIND (no
command seen). The control fixtures of part 2b (13 must-find shapes, one clean fixture with 5 network calls, one
empty script that must be BLIND) are the instrument's own control needles (§11.4.273).

The census lint adds one rule: a `channels.tsv` row's `env` is `net-allowlist` exactly when every invocation of its
key is reached through `rc_net`, `nt` or `net`.

## 4. The removed parser (§11.4.124)

Removed: `_rc_env_sendenv`, `_rc_env_sendenv_read`, `_rc_env_pwhome`, the `_RC_SENDENV_*` variables and the
`RELEASE_ENV_KEEP` checks that used them (the static `LANG* LC_* COLORTERM NO_COLOR` refusal stays: it decides what a
local child may get).

- **How it was wired.** Round 10 (commit `3fe216bd`) added the reader to answer R9-1: `rc_env_lockdown` called it
  whenever `RELEASE_ENV_KEEP` was set and refused a keep-name that matched a SendEnv pattern, or every keep-name
  when the reader went BLIND.
- **Why it is dead by design, not by accident.** It re-implemented ssh's configuration language, git's
  configuration (including its include rules, worktrees and submodules) and shell word splitting in bash. The
  round-10 review measured 13 configurations it could not see, and its skip rule ("a file that cannot be read is
  skipped") was justified by a false premise. A further failure measured this round: the reader fails closed on the
  word `sendenv` anywhere in `./.git/config`, so a remote URL holding a path with that word (the first run of this
  round's probe, under a directory named `sendenv11.*`) refused every keep-name; it was correct only by accident.
  No parser can be complete, because git and ssh read configuration the bash reader cannot model (`Match exec`,
  `%` tokens, `includeIf`, a `GIT_SSH` program).
- **What replaces its property.** `rc_net` (section 2). The property "no `RELEASE_ENV_KEEP` value reaches the ssh
  client" is now held by construction and checked LIVE by `probe_sendenv_leak_sshd.sh`.
- **Tests and mutants removed with it.** The K10 reader cases of the redact suite and the mutants K7-K15 (they
  mutated the reader); `mutants.md` maps each to the round-11 mutant that kills the same property. The reviewer
  mutants R01-R11 mutate the removed code and do not apply.

## 5. Honest limits (§11.4.6)

- **N-2.** A value on the network list reaches the network child as it is: `HOME`, `PATH`, `TMPDIR`,
  `GIT_SSH_COMMAND`, `SSH_AUTH_SOCK` and the other names are paths, sockets, host names and a command line the caller
  chose. Under a client `SendEnv *` (or `SendEnv GIT_*`) ssh sends them. A password written by the caller inside
  `GIT_SSH_COMMAND` (`sshpass -p ...`) is not recognised; the common checks only drop URL user information and the
  GitHub and GitLab token shapes.
- **The gate is static.** It reads the four release scripts. A command that a script runs which itself starts a
  network child (the badge computer runs git) is covered only because that call site goes through `rc_net`; the
  gate cannot see inside another program. A network child started by a local child on `LOCAL_OK` (for example a jq
  or sqlite3 extension) is not a shape the scripts use and is not detected.
- **The probe covers the 18 configurations named here.** It shows the mechanism on real ssh and sshd; it is not a
  proof for every possible configuration. The argument for every configuration is the one in section 2 (ssh cannot
  send a variable it does not have), and K11 checks that the network child has only the listed names.
- **Locale values of local children.** A secret that happens to be a valid locale name (from the closed lists) is
  kept for a local child.
- **The runtime recorders raced (found and fixed this round; the earlier rounds' census results are affected).**
  The second run of the suites failed twice, in L2 of the derive suite and C48 of the tag suite. In both, a
  network child was reported holding the caller's names (`TAG`, `STUB_LOG`, `PWD`, `LOGNAME`).
  - Root cause: the cause was the instrument, not the release code. Each recorder (`env_census.py` and the
    recorder that `test_channel_census.sh` builds) appended its block to the shared log in several separate
    writes. When a network child and a local child of one pipeline ran at the same time, their lines
    interleaved: one log line read `P == git`, so a local child's names were counted under git's header.
  - RED on the round-10 recorder, 200 concurrent git and sed pairs: 194 records misattributed, and 175 of 400
    headers merged into other lines.
  - GREEN: 0 misattributed (`race/env_census_red_green.txt`). The channel recorder showed 91 and then 0
    (`race/channel_recorder_red_green.txt`).
  - The fix: each recorder writes its whole block to a private file and appends it in one step under `flock(1)`.
    A record that cannot be written stops the child with 125.
    *Correction (2026-11-13, round 12, F3):* "private file" means a per-process file (`LOG.rec.PID`), created
    with the caller's umask, not private by mode. The logs hold fake canaries only.
  - The standing checks are "R11 RACE" (redact suite) and "concurrent recorders never interleave" (channel
    suite). The mutants are EC1, which restores the round-10 recorder, and EC2, which writes the header outside
    the private file.
  - Consequence: the race can also hide a finding. A network child's names that land under a local child's
    header are checked only against the wider local allow-list. So the runtime-census PASS lines of rounds 7 to
    10 were measured with an instrument that could miss a network-child finding when two children overlapped.
    They are UNCONFIRMED as evidence for those rounds. This round's results were taken with the fixed recorder.

## 6. Evidence classes (§11.4.289)

| Evidence | Class | What it shows |
|---|---|---|
| `sshd_probe_red_3fe216bd.txt`, `sshd_probe_green_round11.txt` | LIVE | two throwaway sshd processes on 127.0.0.1 (one accepting `LANG LC_* ZZ*`, one with no `AcceptEnv`), the system ssh client, the real `tag_and_release.sh --dry-run` fetch; positive needle: the env line for `LANG`/`LC_ALL` in every case window |
| the six suites (`green_*_run1.txt`, `green_*_run2.txt`) | UNIT/fixture | the real library and scripts against fake tools (recorders of the child environment and descriptors) and fixture repositories; no network child reaches a server |
| `mutations_*.txt` | gate logic | every mutant against the suites |
| `netgate`, census lint | static instrument | the scripts' text, with control fixtures |
