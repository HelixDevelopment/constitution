# CON-234 class, round 10: RELEASE_ENV_KEEP refuses what ssh sends, the locale grammar, the missing proofs added

| Field | Value |
|---|---|
| Item | CON-234 (credential text in external-command output and process state), with CON-227..233 touched; vehicle `vehicle/fix227-r9` |
| Round | 10. Operator decision 2026-11-11: review rounds run until GO; every round past 5 is structural (§11.4.276(E)(3)), fresh fixer instance, class-exhaustive (§11.4.276(C)) |
| Review answered | `scratchpad/review_fix227_r9.md` (round-9 head `9d2171e4`, NO-GO): R9-1, R9-2, R9-3, R9-4, the nits N1 (F8), N2, N3, N4, and the reviewer mutants Q1, Q4, Q5, Q11 |
| Author | Claude Opus 5.5 subagent (fixer). The reasoning effort cannot be set or read on this dispatch path (§11.4.231(F.2)); none is claimed |
| RED / GREEN | `red_redact_cut.txt` (the final round-10 tests, round-9 library: pass 321, fail 44) and `green_*.txt` (round-10 tree), beside this file; `summary.txt` has the six suite results |
| Earlier rounds | `../round9/threat_model.md` and `../round8/threat_model.md` stay the record of the descriptor close, the allow-list and the value classes; this file records what round 10 changes |

## 1. What the round-9 review found, and the round-10 answer

| Id | Finding | Round-10 answer | Evidence |
|---|---|---|---|
| R9-1 | `RELEASE_ENV_KEEP` passed `LC_*`, `LANG*`, `COLORTERM`, `NO_COLOR`, the names the default `/etc/ssh/ssh_config` sends with `SendEnv`, so an opted-in value left the host (round-7 N1 class). `round9/threat_model.md:21` said every name "the channels git, ssh ... read" is refused; ssh sends these names, so the claim was wrong | Two layers in `rc_env_lockdown`. (1) A static class by name, upper-cased: `LANG*`, `LC_*`, `COLORTERM`, `NO_COLOR`. (2) The SendEnv patterns read at run time by `_rc_env_sendenv`: `/etc/ssh/ssh_config`, `$HOME/.ssh/config`, the `.ssh/config` of the passwd home of `$UID` (the one ssh uses) when it differs, every file named by `-F` in `GIT_SSH_COMMAND`, and their `Include` files (globs, relative names, up to 8 levels). Host and Match context is ignored, so the list is a superset. A name matching a pattern (as given, upper case or lower case) is refused. Fail closed: when a SendEnv argument is not a plain pattern of `[A-Za-z0-9_*?]`, an Include names `%` or `$`, the Include depth passes 8, `GIT_SSH_COMMAND` contains `sendenv`, or a git configuration file the run may read contains `sendenv` (core.sshCommand), every `RELEASE_ENV_KEEP` name is refused; the base list still passes. The round-9 claim is corrected by a note in `../round9/threat_model.md` | RED: `red_redact_cut.txt` (the SendEnv class, the static class, the run-time SendEnv, fail-closed and census cases fail on the round-9 library). GREEN: `green_redact_cut.txt`. LIVE: `sendenv_sshd_probe.txt`: with `RELEASE_ENV_KEEP="LC_ZZ LC_X LANGX COLORTERM NO_COLOR ZZSENDX10 KEEPME"` and fake values, the round-9 scripts send `LC_TIME=<40 hex>`, `NO_COLOR`, `COLORTERM`, `LC_X`, `LC_ZZ=user:ZZFAKEPW10@host` and `ZZSENDX10` to the sshd; the round-10 scripts send only `LANG=C.UTF-8` and `LC_ALL=C` |
| R9-1 (census) | nothing compared the extra names with `ssh -G` | `K10 census`: every name `ssh -G` (the real client, on this host's configuration) lists as a SendEnv pattern is put in `RELEASE_ENV_KEEP` and must not reach the child; control needles first show that `ssh -G` reports patterns and that a non-matching name is kept | `green_redact_cut.txt` (`K10 census`) |
| R9-1 (nit) | the `${RELEASE_ENV_KEEP}` loop is unquoted (N2) | the loop runs under `set -f` (restored with `local -`), so the words are never glob-expanded. The review called N2 harmless because "every result then fails the identifier check"; that is not so: with a file `ZZG10A` in the current directory, `ZZG10*` expands to `ZZG10A`, an identifier, which round 9 kept. Now it is refused (it is not an identifier) | RED: `K10 N2 RELEASE_ENV_KEEP glob-expanded passes on: ZZG10A` in `red_redact_cut.txt`. Mutant NG1 |
| F8 (N1) | `LANGUAGE=user:pw@host` kept; a 40-hex token in `LC_TIME` kept | the locale names of the base list (LANG and the 13 LC_ names) must match `_rc_env_locale_ok`: empty, `C`, `POSIX`, or a language of 2 or 3 lower-case letters with an optional `_TERRITORY` (2 upper-case letters or 3 digits), an optional `.codeset` (letters, digits, `-`, up to 32) and an optional `@modifier` (lower-case letters and digits, up to 32), at most 64 bytes. `LANGUAGE` is a `:`-separated list of such names, at most 256 bytes, every element checked. Decision on F8: `user:pw@host` in LANGUAGE is dropped by the value check, as asked | RED and GREEN: the `F8` keep and drop tables (LANG, LC_TIME, LANGUAGE) in the two files. Mutants L1, L2, L3, B5, RR10 |
| R9-2 | the A10 equivalence claim was false (with `HELP=1` in the caller, the A10 publisher printed help and exited 0) | `release_publish_gitea.sh` sets `HELP=0` on a line of its own after its defaults; a new test `K10 R9-2` runs a probe script through `rc_env_clean` with `ZZPLAIN10=ZZP10 HELP=1` in the caller and expects both unset in the re-executed process. A10 is now a property mutant (`mp A10 'K10 R9-2'`) and is killed; it is removed from the equivalent list | `green_redact_cut.txt`; A10 killed (`mutations.txt`). The channel census (`green_channel_census.txt`) still passes: the HELP line is separate from the `TOKEN_VAR` line the census reads |
| R9-3 | six of the seven F7 prefixes had no test (Q4, Q5 survived) | `K10 R9-3`: one name per refused prefix (`GIT_ZZX10 SSH_ZZX10 CURL_ZZX10 GH_ZZX10 GLAB_ZZX10 GITLAB_ZZX10 LD_ZZX10 ZZX10_URL ZZX10_URI zzx10_url`), each with a value that passes the common checks so only the name decides, and control names that hold such a prefix later in the name (`XGIT_ZZ10 XLC_ZZ10 MYLANG10`, kept) | QQ4, QQ5 (the reviewer's Q4, Q5 verbatim) and J1..J5 (the other prefixes) killed |
| R9-4 | Q1 (fd 5 kept) and Q11 (`PASS` dropped from the credential words) survived | `K10 R9-4`: the caller opens every descriptor 3..64 (on `/dev/null`) and the child of the re-executed probe must hold none; one `RELEASE_ENV_KEEP` name per credential word (`ZW_TOK ZW_SECRET ZW_PASS ZW_PWD ZW_KEY ZW_CRED ZW_AUTH ZW_COOKIE ZW_SESSION ZW_JWT ZW_PROXY zw_passwd`) must be refused | QQ1, QQ11 (verbatim) and CW1..CW10 (every other word) killed |
| N3 | children inherit the script's own fd 3 (and derive's fd 4), a copy of the original stderr | not changed: a design limit, recorded here. The scripts open fd 3 after `rc_env_clean` to keep a channel to the caller's terminal; no allow-listed variable tells a child to write to an inherited descriptor (GIT_TRACE is not on the list); the census allows fd 3 by design (`--allow-fd 3`). A child that chose to write to fd 3 would bypass redaction | — |
| N4 | `round9/red_redact_cut.txt` (253/13) predated the final round-9 tests | refreshed: the committed round-9 tests (`9d2171e4`) run with `RC_LIB` set to the round-8 library (`4c80482c`): 253 pass, 15 fail, 11 of them `K9 F7`, as the review measured. The file says so in its first line | `../round9/red_redact_cut.txt` |
| F10 | commits of the range without a parsed `Roadmap-Item:` trailer | nothing to change (history is not rewritten, §11.4.113). The round-10 commit carries `Roadmap-Item: CON-234` and the co-author line in one trailer block | `git log` of the bundle |

## 2. Why the SendEnv refusal is class-wide, and what it cannot see

The class is "a variable name the ssh client sends to the remote server". ssh decides that from its configuration,
so a static list alone is a guess about the host. Round 10 reads the configuration at run time and keeps a static
floor for the names the stock OpenSSH configuration sends (`/etc/ssh/ssh_config` on this host, line 50:
`SendEnv LANG LC_* COLORTERM NO_COLOR`), so a host where the reader cannot see a file still refuses them.

The reader is a superset by construction: it ignores Host and Match blocks, counts a negated pattern (`-NAME`) as a
pattern, reads `/etc/ssh/ssh_config` and `~/.ssh/config` even when `-F` makes ssh skip them, and matches a name as
given, in upper case and in lower case. Every uncertainty it can detect turns into a refusal of every
`RELEASE_ENV_KEEP` name (fail closed); the base list is not affected, so the release scripts still run.

> **Correction (round 11, R10-3 of the round-10 review).** The sentence "Every uncertainty it can detect turns into a
> refusal" was false as a claim about the leak class: the reader skipped a file it could not open on the premise that
> ssh, as the same user, could not open it either, and that premise is false whenever the shell expands the path
> (`~`, `$HOME`), the flag is clustered (`-qF`), the path is quoted, or `./.git` is a file (a linked worktree or a
> submodule checkout). The same holds for the claim below that a `-F` file named inside `core.sshCommand` fails
> closed: it does not in a linked worktree or submodule (C4w), from a subdirectory (C4s) or through `include.path`
> (C10). The round-10 review measured 13 such configurations sending an opted-in value to a real sshd. Round 11
> removes the reader; see `../round11/threat_model.md`, sections 2 and 4. This file is kept as the
> record of round 10 and is not otherwise rewritten.

Honest limits (§11.4.6): the reader does not see a SendEnv given by a `GIT_SSH` wrapper program, a `-F` file named
inside `core.sshCommand` (it does see the word `sendenv` there and fails closed), a git `include.path` file, a
`Match exec` that changes which file applies, or an Include path holding a blank. ssh sends `TERM` when it allocates
a terminal; git does not ask for one, and TERM is on the base list with its own shape. A secret that happens to be a
locale name (`ab_CD`) is kept by the grammar. The grammar drops some locale aliases (`en_US.utf8@euro` is kept,
`de_DE@euro` is kept, a name with an upper-case modifier such as `sr_RS@Latin` is dropped); dropping a locale only
changes message language, it never leaks.

Two notes on the evidence. The live probe's tag run stops at its own CHANGELOG precondition (the probe tag is not in
`CHANGELOG.md`), after the ssh fetch; the fetch is the step measured, one ssh session per case. The F8 row shows that
round 9's `LC_TIME` bare token did leave the host (the review rated F8 a nit "not a leak path off-host" for LANGUAGE;
LANGUAGE is indeed no SendEnv name, but LC_TIME is). Part of the RED is an interface mismatch, not only the defect:
the census cases call `_rc_env_sendenv`, which the round-9 library does not have; the behavioural RED is the
`RELEASE_ENV_KEEP` cases and the live probe.

## 3. Evidence classes (§11.4.289)

| Evidence | Class | Why |
|---|---|---|
| `sendenv_sshd_probe.txt` | LIVE | a real sshd of this user on 127.0.0.1 (own host key, own authorized key, free port), the real system ssh client, the real `tag_and_release.sh --dry-run` of the round-10 working tree and of `9d2171e4`; the sshd log is the sink; control needle: `LANG=C.UTF-8` arrives |
| `K10 census` (redact suite) | LIVE | the real `ssh -G` on this host's configuration |
| `K10 R9-2`, `K10 R9-4` descriptors (redact suite) | LIVE | the real `rc_env_clean`, the real re-exec, a child reading its own `/proc/self/fd` and environment |
| `K10 R9-1`, `R9-3`, `R9-4` words, `N2`, `F8` (redact suite) | LIVE on the library (corrected in round 11, N-4: UNIT/fixture; the library runs in a clean bash with fixture files, no network child and no server) | the real `rc_env_lockdown` in a clean bash; the ssh configuration files of the run-time cases are prepared files (fixture inputs fed to the real code, §11.4.289(C)(3)) |
| `K10 R9-1 static class (no run-time pattern)` | UNIT | `_rc_env_sendenv` is replaced by a stub that finds no pattern (§11.4.289(C)(1)); it isolates the static floor, which this host's own ssh_config otherwise hides (section 4) |
| `_rc_env_pwhome` on a prepared passwd file | UNIT (fixture input) | the parser alone |
| mutation harness | gate-logic | proves the tests decide; it is not evidence that a release works |

## 4. Mutation run

Own mutants of round 10 (each in `tests/release/test_release_tooling_mutations.sh`, each named once; a new
`dupname` check makes a name used twice a stale mutant, after the round-9 review's Q1, Q4, Q5 and Q11 collided with
the round-4 names Q1..Q12):

| Mutant | What it changes | Result (full run, `mutations.txt`) |
|---|---|---|
| A10 | round 10 (R9-2): NOT equivalent (the round-8 record was wrong): every caller variable became a shell variable of the re-executed script (HELP=1 printed the publ | killed by its property (FAIL K10 R9-2 a caller variable off the list is not a variable of the re-executed script (got 'rc=0 zzplain=ZZP10 help=1) |
| B5 | re-applied (round 10: the locale grammar); N1: a locale value with a blank (a word after the locale) | killed by its property (FAIL K8 N1 not dropped: ZZLCP8) |
| RR10 | re-applied (round 10: the locale grammar); R10: a locale value may hold : and / | killed (FAIL K8 N1 class table: rc 1 CLASSES ssh=ssh sendenv=LANG LC_* COLORTERM NO_COLOR CLASS LANG                      class=) |
| QQ1 | fd 5 kept: a caller's open credential file reaches every child | killed by its property (FAIL K10 R9-4 descriptors reach a child: childfds=5) |
| QQ4 | SSH_* not refused in RELEASE_ENV_KEEP | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: SSH_ZZX10) |
| QQ5 | LD_* not refused | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: LD_ZZX10) |
| QQ11 | PASS not a credential word (DB_PASSWORD kept) | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_PASS) |
| J1 | CURL_* not refused | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: CURL_ZZX10) |
| J2 | GH_* not refused | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: GH_ZZX10) |
| J3 | GLAB_* not refused | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: GLAB_ZZX10) |
| J4 | GITLAB_* not refused | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: GITLAB_ZZX10) |
| J5 | *_URI not refused (H4 drops both) | killed by its property (FAIL K10 R9-3 RELEASE_ENV_KEEP (prefix) passes on: ZZX10_URI) |
| K1 | LANG* not refused | killed by its property (FAIL K10 R9-1 RELEASE_ENV_KEEP (SendEnv class) passes on: LANGX10) |
| K2 | LC_* not refused | killed by its property (FAIL K10 R9-1 static class (no run-time pattern) passes on: LC_ZZ10) |
| K3 | COLORTERM not refused | killed by its property (FAIL K10 R9-1 static class (no run-time pattern) passes on: COLORTERM) |
| K4 | NO_COLOR not refused | killed by its property (FAIL K10 R9-1 static class (no run-time pattern) passes on: NO_COLOR) |
| K5 | the static SendEnv class removed (the run-time patterns of this host's ssh_config still refuse some) | killed by its property (FAIL K10 R9-1 RELEASE_ENV_KEEP (SendEnv class) passes on: LANGX10) |
| K6 | case-sensitive: lc_zz10 kept | killed by its property (FAIL K10 R9-1 static class (no run-time pattern) passes on: lc_zz10) |
| K7 | the run-time SendEnv patterns not applied | killed by its property (FAIL K10 R9-1 runtime SendEnv (~/.ssh/config, its Include, the -F file of GIT_SSH_COMMAND) passes on: ZZSENDA10_X) |
| K8 | an unreadable configuration not refused (fail open) | killed by its property (FAIL K10 R9-1 fail closed (GIT_SSH_COMMAND ssh -F /home/milosvasic/.cache/claude-tmp/rtm_test.WIpNUL/tmp.cu4nkC/k6.z8Chd) |
| K9 | Include lines not followed | killed by its property (FAIL K10 R9-1 runtime SendEnv (~/.ssh/config, its Include, the -F file of GIT_SSH_COMMAND) passes on: ZZSENDC10) |
| K10 | the -F file of GIT_SSH_COMMAND not read | killed by its property (FAIL K10 R9-1 runtime SendEnv (~/.ssh/config, its Include, the -F file of GIT_SSH_COMMAND) passes on: ZZSENDE10) |
| K11 | SendEnv on the GIT_SSH_COMMAND line not refused | killed by its property (FAIL K10 R9-1 fail closed (GIT_SSH_COMMAND ssh -o SendEnv=ZZSENDF10) passes on: KEEPME) |
| K12 | SendEnv in a git configuration file not refused | killed by its property (FAIL K10 R9-1 fail closed (GIT_CONFIG_GLOBAL /home/milosvasic/.cache/claude-tmp/rtm_test.WIpNUL/tmp.6IbVEb/k6.h4dU9d/g10) |
| K13 | an unreadable SendEnv pattern dropped silently | killed by its property (FAIL K10 R9-1 fail closed (GIT_SSH_COMMAND ssh -F /home/milosvasic/.cache/claude-tmp/rtm_test.WIpNUL/tmp.NgdhNl/k6.Tqb3k) |
| K14 | the passwd home's ssh config not read | killed by its property (FAIL K10 R9-1 passwd home's ssh config not read (files:  /etc/ssh/ssh_config /etc/ssh/ssh_config.d/20-systemd-ssh-proxy.) |
| K15 | /etc/ssh/ssh_config not read | killed by its property (FAIL K10 census: blind or unreadable: 0) |
| L1 | x}" -le 64 ] && _rc_env_locale_ok "$x" ;;' '      [[ $x =~ ^[A-Za-z0-9_.@-]{0,64}$ ]] ;;'   # the round-9 locale class (a bare token kept) | killed by its property (FAIL K9 F8 not a locale: '0123456789abcdef0123456789abcdef01234567': LC_TIME (got 'keep', want 'drop')) |
| L2 | LANGUAGE elements not checked | killed by its property (FAIL K9 F8 LANGUAGE dropped 'user:ZZPW10@host': LANGUAGE (got 'keep', want 'drop')) |
| L3 | *:}" ;; *) rest="" ;; esac; done ;;' '        rest=""; done ;;'   # only the first LANGUAGE element checked | killed by its property (FAIL K9 F8 LANGUAGE dropped 'en:ZZTOKEN10': LANGUAGE (got 'keep', want 'drop')) |
| NG1 | RELEASE_ENV_KEEP glob-expanded against the current directory | killed by its property (FAIL K10 N2 RELEASE_ENV_KEEP glob-expanded passes on: ZZG10A) |
| CW1 | TOK not a credential word | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_TOK) |
| CW2 | SECRET | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_SECRET) |
| CW3 | PWD | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_PWD) |
| CW4 | KEY | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_KEY) |
| CW5 | CRED | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_CRED) |
| CW6 | AUTH | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_AUTH) |
| CW7 | COOKIE | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_COOKIE) |
| CW8 | SESSION | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_SESSION) |
| CW9 | JWT | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_JWT) |
| CW10 | PROXY (the first form also removed JWT and was killed by ZW_JWT, not ZW_PROXY) | killed by its property (FAIL K10 R9-4 RELEASE_ENV_KEEP (credential word) passes on: ZW_PROXY) |

The first targeted run found K2 (`LC_*` dropped from the static class) and K3 (`COLORTERM` dropped) SURVIVED
(`targeted_first_run.txt`): on this host `/etc/ssh/ssh_config` sends `LANG LC_* COLORTERM NO_COLOR`, so the run-time
reader refused those names anyway and the static floor was untested. The unit case `K10 R9-1 static class (no
run-time pattern)` was added; K2..K4 are killed by it (`targeted_second_run.txt`).

`mutations.txt` (the full harness, sequential, `nice -n 10`, on the final round-10 tree, 9786 s): `RESULT: killed=242 survived=0 equivalent=3 stale=0 control_failures=0 inconclusive=0`, harness rc 0; 245 mutants plus the six controls (all pass). The three equivalent mutants are X12, Z6 and A14 (A10 is no longer among them). Each was run alone with `--only` and survives as recorded; A14 was also probed LIVE outside the harness (`a14_equivalence_probe.txt`: the real publisher and an A14 copy give the same output and status with the token unset and empty). X12 and Z6 were not probed outside the harness this round; their records are on the publisher and the tag script, which round 10 does not change apart from the publisher's `HELP=0` line. A stale check (`STALE_ONLY=1`) gives `stale=0`; a duplicate name was shown to count as stale on a scratch copy (a second `QQ1` line: stale=1, rc 1).

Other checks on the final tree: `shellcheck.txt` (shellcheck 0.11.0 `-S warning` over the release scripts, the release tests and the probe: rc 0; a first run flagged two unused `read` fields, a literal `~/` pattern, a glob match and two generated argument lists, fixed or annotated before the final run), `verify_manifest.txt` (`MANIFEST-OK`), `gate_ledger_ratchet.txt` (PASS, unimplemented=394 baseline=394), `sync_guide.txt` (rc 0, no change to the guide), `green_classes.txt` (44 names, 0 findings).
