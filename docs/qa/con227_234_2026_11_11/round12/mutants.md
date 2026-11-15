# Mutants of round 12

Each mutant is an `mp` line of `tests/release/test_release_tooling_mutations.sh`: it counts as killed only when
its suite fails AND a FAIL line matches the regex in the third column (the property it targets). Run one by one
with `--only NAME` on the round-12 tree (`mutants_targeted_r12.tsv`; `run_targeted.sh` in the fixer's scratch
directory). The standing run of all mutants is in `README.md` section 5.

Result of the targeted run: `SUMMARY mutants=55 killed_by_property=55 failed=0 other=0`.

## Round-11 gate mutants (GN1-GN6), re-applied to the round-12 gate

| Mutant | Source | Must die by (FAIL line regex) | What it breaks | Result |
|---|---|---|---|---|
| GN1 | `tests/release/channel_census.py` | `git in backticks\|CI79_backtick_nested` | backticks not read as code (a command in `...` is not seen) | killed by its property (35s): `FAIL netgate misses git in backticks (rc 2): NETGATE invocations=0 network_through_rc_net=0 findings=0 BLIND: ` |
| GN2 | `tests/release/channel_census.py` | `CTRL_POS_plain_git\|a bare git` | git not a network command | killed by its property (30s): `FAIL netgate misses a bare git (rc 1): FINDING unclassified command (default deny): ng.sh:2 git \| git fetch -` |
| GN3 | `tests/release/channel_census.py` | `CI44_nt_twice\|CI45_nt_assign\|CI46_nt_extra\|untrusted nt` | nt and net trusted without reading their definitions | killed by its property (33s): `FAIL netgate misses git through an untrusted nt (rc 1): FINDING network command outside rc_net: ng.sh:2 timeou` |
| GN4 | `tests/release/channel_census.py` | `G36_var_cmd\|G44_dq_var_cmd\|CI47_own_rc_net\|CI78_bash_word_cmd\|a command in a variable` | a command in a variable not reported | killed by its property (31s): `FAIL netgate misses a command in a variable (rc 2): NETGATE invocations=0 network_through_rc_net=0 findings=0 ` |
| GN5 | `tests/release/channel_census.py` | `G21_git_via_gitdashcmd\|G22_python_via_absent_name\|an unknown command` | default deny dropped | killed by its property (31s): `FAIL netgate misses an unknown command (default deny) (rc 0): NETGATE invocations=1 network_through_rc_net=0 f` |
| GN6 | `tests/release/channel_census.py` | `G29_xargs_git\|G30_env_git\|G31_nice_git\|G37_bash_c\|git under env\|git under nice\|bash -c` | every interpreter and exec wrapper allowed | killed by its property (35s): `FAIL netgate misses git under env (rc 0): NETGATE invocations=1 network_through_rc_net=0 findings=0 ` |

## Own mutants of the round-12 fixer (NR1-NR33; NR31 is not used)

| Mutant | Source | Must die by (FAIL line regex) | What it breaks | Result |
|---|---|---|---|---|
| NR1 | `tests/release/channel_census.py` | `G16_relative_path\|G17_abs_path_git\|CI26_brace_cmdword\|CI27_glob_cmdword\|CI28_tilde_cmdword` | a literal command word with a path, glob, brace or tilde taken as a plain name | killed by its property (28s): `FAIL netgate control G16_relative_path: want a finding 'command word the gate cannot classify (a path): G16_re` |
| NR2 | `tests/release/channel_census.py` | `G13_trap_sq\|G14_trap_dq\|CI63_trap_dashdash` | a trap string not read as code | killed by its property (29s): `FAIL netgate control G13_trap_sq: want a finding 'network command outside rc_net: G13_trap_sq.sh:3 git (via -)` |
| NR3 | `tests/release/channel_census.py` | `G01_coproc` | coproc allowed | killed by its property (29s): `FAIL netgate control G01_coproc: want a finding 'coproc (a coprocess the gate does not follow): G01_coproc.sh:` |
| NR4 | `tests/release/channel_census.py` | `G15_alias` | alias not refused | killed by its property (37s): `FAIL netgate control G15_alias: want a finding 'builtin alias (it defines or loads a command the gate cannot f` |
| NR5 | `tests/release/channel_census.py` | `G11_command_p\|CI30_command_git\|G34_builtin_command_git` | the program run by command (also command -p) not classified | killed by its property (34s): `FAIL netgate control G11_command_p: want a finding 'network command outside rc_net: G11_command_p.sh:3 git (vi` |
| NR6 | `tests/release/channel_census.py` | `G06_sed_e_cmd` | the sed e command not named | killed by its property (38s): `FAIL netgate control G06_sed_e_cmd: want a finding 'sed that can run a command: G06_sed_e_cmd.sh:3 (the e comm` |
| NR7 | `tests/release/channel_census.py` | `G07_sed_s_e_flag\|CI34_sed_w_flag` | the s///e and s///w flags not named | killed by its property (40s): `FAIL netgate control G07_sed_s_e_flag: want a finding 'sed that can run a command: G07_sed_s_e_flag.sh:3 (the ` |
| NR8 | `tests/release/channel_census.py` | `G08_sort_compress_prog\|CI42_sort_long_abbrev` | a long option of sort allowed | killed by its property (35s): `FAIL netgate control G08_sort_compress_prog: want a finding 'sort that can run a command: G08_sort_compress_pr` |
| NR9 | `tests/release/channel_census.py` | `G09_sqlite_system` | sqlite3 without -safe allowed | killed by its property (38s): `FAIL netgate control G09_sqlite_system: want a finding 'sqlite3 that can run a command: G09_sqlite_system.sh:3` |
| NR10 | `tests/release/channel_census.py` | `G05_awk_multiline_system\|G05b_awk\|G05c_awk` | awk system() allowed | killed by its property (32s): `FAIL netgate control G05_awk_multiline_system: want a finding 'awk program that can run a command: G05_awk_mul` |
| NR11 | `tests/release/channel_census.py` | `CI38_awk_print_pipe\|CI39_awk_getline_pipe` | an awk pipe to or from a command allowed | killed by its property (36s): `FAIL netgate control CI38_awk_print_pipe: want a finding 'a pipe to or from a command', rc 0: NETGATE invocati` |
| NR12 | `tests/release/channel_census.py` | `CI70_exec_unknown_opt` | an unknown exec option skipped | killed by its property (39s): `FAIL netgate control CI70_exec_unknown_opt: want a finding 'exec with an option the gate does not know', rc 1:` |
| NR13 | `tests/release/channel_census.py` | `CI12_source_other` | source of a file the gate does not read allowed | killed by its property (42s): `FAIL netgate control CI12_source_other: want a finding 'source of a file the gate does not read', rc 0: NETGAT` |
| NR14 | `tests/release/channel_census.py` | `CI06_path_tempenv\|CI09_export_path\|CI65_read_path\|CI66_getopts_path` | an assignment to PATH allowed | killed by its property (44s): `FAIL netgate control CI06_path_tempenv: want a finding 'assignment to PATH', rc 0: NETGATE invocations=2 netwo` |
| NR15 | `tests/release/channel_census.py` | `CI19_let_subscript` | a command substitution in let allowed | killed by its property (40s): `FAIL netgate control CI19_let_subscript: want a finding 'let with a command substitution', rc 0: NETGATE invoc` |
| NR16 | `tests/release/channel_census.py` | `CI20_cond_subscript` | a quoted command substitution inside [[ ]] allowed | killed by its property (43s): `FAIL netgate control CI20_cond_subscript: want a finding 'inside [[ ]]', rc 0: NETGATE invocations=1 network_t` |
| NR17 | `tests/release/channel_census.py` | `CI45_nt_assign\|CI46_nt_extra` | the body of a wrapper candidate not checked | killed by its property (44s): `FAIL netgate control CI45_nt_assign: want a finding 'network command outside rc_net: CI45_nt_assign.sh:4 git (` |
| NR18 | `tests/release/channel_census.py` | `CI18_unset_f` | unset -f allowed | killed by its property (37s): `FAIL netgate control CI18_unset_f: want a finding 'unset -f', rc 0: NETGATE invocations=1 network_through_rc_n` |
| NR19 | `tests/release/channel_census.py` | `CI16_set_x` | set -x allowed | killed by its property (42s): `FAIL netgate control CI16_set_x: want a finding 'set that turns on xtrace', rc 0: NETGATE invocations=1 networ` |
| NR20 | `tests/release/channel_census.py` | `CI03_prompt_expansion` | ${x@P} allowed | killed by its property (42s): `FAIL netgate control CI03_prompt_expansion: want a finding '@P', rc 0: NETGATE invocations=1 network_through_r` |
| NR21 | `tests/release/channel_census.py` | `CI01_funsub\|CI02_valuesub` | ${ cmd; } and ${| cmd; } allowed | killed by its property (46s): `FAIL netgate control CI01_funsub: want a finding 'bash 5.3', rc 1: FINDING parse error (the gate refuses what ` |
| NR22 | `tests/release/channel_census.py` | `CI04_dev_tcp\|CI05_dev_udp` | a /dev/tcp redirection allowed | killed by its property (43s): `FAIL netgate control CI04_dev_tcp: want a finding '/dev/tcp or /dev/udp', rc 0: NETGATE invocations=1 network_` |
| NR23 | `tests/release/channel_census.py` | `CI10_declare_n\|CI75_local_n` | declare -n and local -n allowed | killed by its property (44s): `FAIL netgate control CI10_declare_n: want a finding 'declare -n', rc 0: NETGATE invocations=1 network_through_` |
| NR24 | `tests/release/channel_census.py` | `CI08_hash_p` | hash -p allowed | killed by its property (45s): `FAIL netgate control CI08_hash_p: want a finding 'hash other than hash -r', rc 0: NETGATE invocations=1 networ` |
| NR25 | `tests/release/channel_census.py` | `G35_eval_git\|CI31_builtin_eval\|eval` | eval allowed | killed by its property (50s): `FAIL netgate misses eval (rc 2): NETGATE invocations=0 network_through_rc_net=0 findings=0 BLIND: no invocatio` |
| NR26 | `tests/release/channel_census.py` | `CI13_mapfile_callback` | mapfile -C allowed | killed by its property (44s): `FAIL netgate control CI13_mapfile_callback: want a finding 'mapfile with a callback', rc 0: NETGATE invocation` |
| NR27 | `tests/release/channel_census.py` | `CI14_compgen_c` | compgen -C allowed | killed by its property (51s): `FAIL netgate control CI14_compgen_c: want a finding 'compgen with -C', rc 0: NETGATE invocations=1 network_thr` |
| NR28 | `tests/release/channel_census.py` | `CI23_arith_quoted` | a single-quoted command substitution in arithmetic allowed | killed by its property (45s): `FAIL netgate control CI23_arith_quoted: want a finding 'in arithmetic', rc 0: NETGATE invocations=1 network_th` |
| NR29 | `tests/release/channel_census.py` | `CI21_assign_subscript` | a command substitution in an assignment subscript allowed | killed by its property (41s): `FAIL netgate control CI21_assign_subscript: want a finding 'subscript of an assignment', rc 0: NETGATE invocat` |
| NR30 | `tests/release/channel_census.py` | `the parser cannot read` | the lint does not report a parse error (a short census) | killed by its property (41s): `FAIL lint misses a script the parser cannot read (rc 0): CENSUS invocations=128 rows=124 secret_lines=13 findi` |
| NR32 | `tests/release/channel_census.py` | `lint depends on the host PATH\|lint misses\|lint rc=\|stale row` | the round-11 host lookup put back into the lint census | killed by its property (49s): `FAIL lint rc=1: FINDING stale row (table line 112): tag_and_release.sh glab key=8d2b1a5e` |
| NR33 | `tests/release/channel_census.py` | `G10_absent_netcmd_aria2c\|depends on the host PATH\|golden-FALSE` | the round-11 host lookup put back into the gate | killed by its property (44s): `FAIL lint depends on the host PATH (rc 0/1): FINDING stale row (table line 13): derive_release_facts.sh awk ke` |

## Mutants of the round-11 reviewer, adopted verbatim

| Mutant | Source | Must die by (FAIL line regex) | What it breaks | Result |
|---|---|---|---|---|
| RM2 | `scripts/release/derive_release_facts.sh` | `C53 netgate` | quoted "git" rev-parse in derive | killed by its property (44s): `FAIL C53 netgate rc=1: FINDING command word the gate cannot classify (quoted or escaped): derive_release_facts` |
| RM9 | `scripts/release/redact_cut.sh` | `K11` | rc_net keeps allow-listed names without their shape check | killed by its property (26s): `FAIL K11 shape (a URL with a password in GH_HOST, a relative XDG_CACHE_HOME) passes on: GH_HOST` |
| RM10 | `scripts/release/redact_cut.sh` | `K11\|C48` | TZ SHELL LANGUAGE added to _RC_NET_KEEP | killed by its property (27s): `FAIL K11 rc_net passes on: LANGUAGE` |
| RM12 | `scripts/release_publish_gitea.sh` | `28 X11` | publisher keeps the token variable (unset removed) (re-applied to the round-12 line) | killed by its property (36s): `FAIL 28 X11: a child holds the token of an allow-listed --token-var (== grep` |
| RM19 | `scripts/release/redact_cut.sh` | `K11` | rc_net constants without GIT_TERMINAL_PROMPT/GIT_TRACE_REDACT | killed by its property (32s): `FAIL K11 the network child census blind or over-refusing: GIT_TRACE_REDACT missing` |
| RM20 | `scripts/release/redact_cut.sh` | `R12 F2` | locale modifier widened | killed by its property (35s): `FAIL K9 R12 F2 a modifier not on the closed list: 'en_US.UTF-8@zztoken11': LC_TIME (got 'keep', want 'drop'` |
| RM21 | `scripts/release/redact_cut.sh` | `K8\|K9` | locale language widened | killed by its property (44s): `FAIL K8 N1 class table: rc 1 CLASSES ssh=ssh sendenv=LANG LC_* COLORTERM NO_COLOR CLASS LANG                  ` |
| RM25 | `scripts/release/redact_cut.sh` | `K11` | rc_net without IFS reset / set -f | killed by its property (35s): `FAIL K11 IFS=_: rc_net runs the command (status 0) (got 'rc=125', want 'rc=0'` |
| RM26 | `scripts/release/redact_cut.sh` | `K11` | rc_net without the clean-state precondition | killed by its property (29s): `FAIL K11 not rebuilt by rc_env_clean: status 125 (got 'rc=0', want 'rc=125'` |
| RM27 | `scripts/release_publish_gitea.sh` | `token in curl argv\|on curl.s stdin\|curl without -q` | publisher token in curl argv instead of -K - stdin | killed by its property (34s): `FAIL token in curl argv` |
| RM28 | `scripts/release/redact_cut.sh` | `K11` | rc_net function un-export skipped | killed by its property (33s): `FAIL K11 an exported function reaches the network child` |
| RM30 | `scripts/release/tag_and_release.sh` | `C53 netgate` | NEW line: command -p git fetch (no rc_net) | killed by its property (218s): `FAIL C53 netgate rc=1: FINDING network command outside rc_net: tag_and_release.sh:196 git (via -) \| command -` |
| RM30b | `scripts/release/tag_and_release.sh` | `C53 netgate` | NEW line: command -p git fetch, then hash -r (no rc_net, no hash-table side effect) | killed by its property (213s): `FAIL C53 netgate rc=1: FINDING network command outside rc_net: tag_and_release.sh:196 git (via -) \| command -` |
| RM31 | `scripts/release/tag_and_release.sh` | `C53 netgate` | NEW line: "git" fetch with a quoted command word (no rc_net) | killed by its property (195s): `FAIL C53 netgate rc=1: FINDING command word the gate cannot classify (quoted or escaped): tag_and_release.sh:1` |
| RM32 | `scripts/release/tag_and_release.sh` | `C53 netgate` | NEW line: redirection before git fetch (no rc_net) | killed by its property (213s): `FAIL C53 netgate rc=1: FINDING network command outside rc_net: tag_and_release.sh:196 git (via -) \| >/dev/nul` |
| RM33 | `scripts/release/tag_and_release.sh` | `C53 netgate` | NEW line: plain git fetch (no rc_net) - control mutant | killed by its property (223s): `FAIL C53 netgate rc=1: FINDING network command outside rc_net: tag_and_release.sh:196 git (via -) \| git fetch` |
| RM34 | `scripts/release/tag_and_release.sh` | `C53 netgate` | NEW line: /usr/bin/git fetch (absolute path, no rc_net) | killed by its property (182s): `FAIL C53 netgate rc=1: FINDING command word the gate cannot classify (a path): tag_and_release.sh:196 /usr/bin` |

## Reviewer mutants not adopted

| Mutant | Source | Status | Reason |
|---|---|---|---|
| RM1 | `scripts/release/tag_and_release.sh` | not adopted | the reviewer's run hung in C41 for its 1500 s budget (the edited fetch line loses nt's timeout); the property (a git outside rc_net) is RM33's |
| RM3 | `scripts/release/tag_and_release.sh` | not adopted | abandoned by the reviewer (same reason as RM1); replaced by RM30 and RM30b |
| RM22 | `scripts/release/tag_and_release.sh` | not adopted | abandoned by the reviewer (same reason as RM1); replaced by RM34 |
