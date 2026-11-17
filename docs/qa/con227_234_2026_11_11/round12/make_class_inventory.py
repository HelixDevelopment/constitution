#!/usr/bin/env python3
"""Class inventory of the network-spawn gate, round 12 (§11.4.276(C)): every way a release script could start a
program that the round-11 gate did not see, as a closed set of classes, each with its member control needles from
tests/release/netgate_controls.jsonl (the controls part 2c of tests/release/test_channel_census.sh runs with an empty
PATH). Run from the repository root:
  python3 -I docs/qa/con227_234_2026_11_11/round12/make_class_inventory.py > docs/qa/con227_234_2026_11_11/round12/class_inventory.md
Exit 1 when a control has no class, has two classes, or a class names a control that does not exist, so the
inventory cannot drift from the controls."""
import json
import sys

CLASSES = [
    ("K1", "Spelling of the command word",
     "a quoted, escaped, path, brace, glob, tilde, ANSI-C or variable command word; the round-11 gate matched bare "
     "words with a regular expression",
     "a literal command word must match `CMDNAME_RE` after quote removal, else `command word the gate cannot "
     "classify`; an expansion in command position is refused unless it is one of the dynamic sites of `DYN_OK`",
     ["G02_dq_cmdword", "G03_sq_cmdword", "G04_backslash_cmdword", "G16_relative_path", "G17_abs_path_git",
      "G36_var_cmd", "G44_dq_var_cmd", "CI26_brace_cmdword", "CI27_glob_cmdword", "CI28_tilde_cmdword",
      "CI29_ansi_c_cmdword", "CI78_bash_word_cmd"]),
    ("K2", "Command position in a syntax context",
     "a command after a redirection, an fd prefix or an assignment, or inside a compound command, a substitution, a "
     "heredoc, a process substitution, an arithmetic context, `case`, `select`, `until`, `function`, a subshell, "
     "`!`, `|&` or `coproc`",
     "the recursive-descent parser (class `Parser`) visits every command of every context, including the text of "
     "every `$(...)`, backtick, `<(...)` and heredoc body; bash constructs it does not model are parse errors",
     ["G01_coproc", "G23_cmd_after_redirection", "G24_fd_redirect_prefix", "G25_env_assign_then_quoted",
      "G26_brace_group_newline", "G27_case_inline", "G39_subst_in_dq", "G45_curl_after_redir", "CI01_funsub",
      "CI02_valuesub", "CI49_case_paren", "CI50_heredoc_subst", "CI51_herestring", "CI52_procsubst",
      "CI53_arith_subst", "CI54_for_arith", "CI55_select", "CI56_until", "CI57_function_kw", "CI58_subshell_body",
      "CI59_bang", "CI60_pipe_amp", "CI61_default_subst", "CI62_nested_subst", "CI64_extglob",
      "CI79_backtick_nested", "CI80_cond_unquoted_subst"]),
    ("K3", "A builtin or wrapper that runs a command, or a string that is run later",
     "`command`, `command -p`, `builtin`, `exec`, `env`, `nice`, `timeout`, `time -p`, `xargs`, `eval`, `bash -c`, "
     "`source`, `trap` strings, `alias`, `enable`, `hash -p`, `mapfile -C`, `compgen -C`, `declare -n`, `set -x` "
     "with `PS4`, `unset -f`, `${x@P}`",
     "the builtins with rules (`command`/`builtin`/`exec` resolve their program; `trap` strings are re-parsed; "
     "`BUILTIN_DENY` refuses alias, enable, complete, compopt, fc, bind, history); a wrapper (`EXECWRAP`) is "
     "allowed only through `ALLOW_EXEC`; any other external is unclassified (default deny)",
     ["G11_command_p", "G12_time_p", "G13_trap_sq", "G14_trap_dq", "G15_alias", "G29_xargs_git", "G30_env_git",
      "G31_nice_git", "G32_timeout_git", "G33_exec_git", "G34_builtin_command_git", "G35_eval_git", "G37_bash_c",
      "CI03_prompt_expansion", "CI08_hash_p", "CI10_declare_n", "CI11_enable", "CI12_source_other",
      "CI13_mapfile_callback", "CI14_compgen_c", "CI15_trap_dynamic", "CI16_set_x", "CI17_ps4", "CI18_unset_f",
      "CI30_command_git", "CI31_builtin_eval", "CI32_exec_a_git", "CI33_builtin_named_function",
      "CI63_trap_dashdash", "CI69_command_unknown_opt", "CI70_exec_unknown_opt", "CI71_unset_dynamic",
      "CI72_set_o_xtrace", "CI73_shopt_o_xtrace", "CI74_set_posix", "CI75_local_n"]),
    ("K4", "A local program that starts commands itself",
     "awk `system()`, pipes, `getline` from a command, `@load`, `/inet`; sed `e`, `s///e`, `w`, `-f`, `-i`, `-r`; "
     "sort `--compress-program` and its abbreviations; sqlite3 `.system`, `.shell`, `-init`, `-cmd`",
     "`LOCAL_PROG`: awk, sed, sort and sqlite3 are allowed only when their program text and options pass a "
     "checker (`local-checked-*` classes); sqlite3 must run with `-safe`",
     ["G05_awk_multiline_system", "G05b_awk_multiline_system_stdin", "G05c_awk_oneline_system", "G06_sed_e_cmd",
      "G07_sed_s_e_flag", "G08_sort_compress_prog", "G09_sqlite_system", "G20_heredoc_to_awk_system",
      "CI34_sed_w_flag", "CI35_sed_f", "CI36_sed_i", "CI37_sed_r", "CI38_awk_print_pipe", "CI39_awk_getline_pipe",
      "CI40_awk_load", "CI41_awk_inet", "CI42_sort_long_abbrev", "CI43_sqlite_cmd", "CI76_awk_unknown_opt",
      "CI77_sqlite_init"]),
    ("K5", "A network program, or a program the gate does not know",
     "git, curl, ssh, gh, glab, wget, socat, lftp, aria2c, `git-upload-pack`, `python3.13` and any other name; the "
     "round-11 gate dropped every name `shutil.which()` did not find on the checking host",
     "`NETCMDS` only through `rc_net` or a trusted wrapper; every name that is not a builtin, a function, "
     "`LOCAL_SIMPLE` or `LOCAL_PROG` is `unclassified command (default deny)`, with no lookup on the host",
     ["CTRL_POS_plain_curl", "CTRL_POS_plain_git", "G10_absent_netcmd_aria2c", "G18_wget",
      "G21_git_via_gitdashcmd", "G22_python_via_absent_name", "G38_ssh", "G40_bare_glab", "G41_bare_gh",
      "G42_bare_socat", "G43_bare_lftp"]),
    ("K6", "State that changes how a command is found or run",
     "`PATH`, `BASH_ENV`, `BASH_CMDS`, `LD_*` and the other names of `DANGER_NAMES` set by assignment, `export`, "
     "`declare`, `read`, `getopts` or `printf -v`; a command substitution in a subscript or in an integer value",
     "an assignment to a name of `DANGER_NAMES` is a finding in every form; `SUBST_RE` is refused in every "
     "arithmetic context (subscripts, `let`, `[[ ]]`, `declare -i`, `printf -v` names)",
     ["CI06_path_tempenv", "CI07_bash_cmds", "CI09_export_path", "CI19_let_subscript", "CI20_cond_subscript",
      "CI21_assign_subscript", "CI22_param_subscript", "CI23_arith_quoted", "CI24_printf_v_subscript",
      "CI25_declare_i_value", "CI65_read_path", "CI66_getopts_path", "CI67_printf_v_ld", "CI68_declare_bash_env"]),
    ("K7", "A raw socket", "a redirection to `/dev/tcp/...` or `/dev/udp/...`",
     "a redirection target under `/dev/tcp` or `/dev/udp` is a finding", ["CI04_dev_tcp", "CI05_dev_udp"]),
    ("K8", "The trusted wrappers themselves",
     "`nt` or `net` defined twice, assigned, given an extra body, or a script's own `rc_net`",
     "the wrappers are trusted only when their bodies match the expected form (`TRUST_CAND`, `GATE_WRAPPERS`); "
     "`rc_net` is trusted only as the library's",
     ["CI44_nt_twice", "CI45_nt_assign", "CI46_nt_extra", "CI47_own_rc_net"]),
    ("K9", "A script the gate cannot read", "an unterminated quote, substitution or heredoc",
     "a parse error is a finding (netgate) and a lint finding (the lint now uses the same parser)",
     ["CI48_parse_error"]),
]
NEG = ("N", "Negative controls (must pass)",
       "clean scripts and the forms the release scripts really use",
       "golden-FALSE: none of these may be a finding (§11.4.201(1))",
       ["CTRL_NEG_clean", "G19_jq_free", "G28_rcnet_tempenv_secret", "CP01_sed_ranges", "CP02_awk_or_regex",
        "CP03_sort_and_sqlite", "CP04_trap_local", "CP05_builtins", "CP06_names", "CP07_wrappers",
        "CP08_exec_redirections"])

rows = [json.loads(line) for line in open("tests/release/netgate_controls.jsonl") if line.strip()]
names = {r["name"]: r for r in rows}
seen = {}
bad = []
for cid, _t, _d, _r, members in CLASSES + [NEG]:
    for n in members:
        if n not in names:
            bad.append("class %s names %s, which is not a control" % (cid, n))
        if n in seen:
            bad.append("%s is in %s and %s" % (n, seen[n], cid))
        seen[n] = cid
for n in names:
    if n not in seen:
        bad.append("control %s has no class" % n)
for cid, _t, _d, _r, members in CLASSES:
    for n in members:
        if n in names and names[n]["want"] != "finding":
            bad.append("%s is a bypass class member but expects %s" % (n, names[n]["want"]))
for n in NEG[4]:
    if n in names and names[n]["want"] != "pass":
        bad.append("%s is a negative control but expects %s" % (n, names[n]["want"]))
if bad:
    sys.stderr.write("\n".join(bad) + "\n")
    sys.exit(1)

print("# Class inventory of the network-spawn gate, round 12")
print()
print("Generated by `make_class_inventory.py` (beside this file, run from the repository root) from")
print("`tests/release/netgate_controls.jsonl`. Each class is a way a release script could start a program; every")
print("member is a control needle that part 2c of `tests/release/test_channel_census.sh` runs through")
print("`channel_census.py netgate` with an empty PATH (no lookup on the host). The generator exits 1 when a control")
print("has no class or two classes, so the inventory and the controls cannot drift apart.")
print()
fin = sum(len(c[4]) for c in CLASSES)
print("Totals: %d classes, %d controls that must be a finding, %d negative controls, %d controls in all."
      % (len(CLASSES), fin, len(NEG[4]), len(rows)))
print()
print("| Class | Name | Members | Rule in the gate |")
print("|---|---|---|---|")
for cid, title, _d, rule, members in CLASSES + [NEG]:
    print("| %s | %s | %d | %s |" % (cid, title, len(members), rule))
for cid, title, desc, _r, members in CLASSES + [NEG]:
    print()
    print("## %s. %s" % (cid, title))
    print()
    print(desc[0].upper() + desc[1:] + ".")
    print()
    print("| Control | Expected | Reason the gate must give |")
    print("|---|---|---|")
    for n in members:
        r = names[n]
        print("| `%s` | %s | %s |" % (n, r["want"], ("`%s`" % r["pattern"].replace("|", "\\|")) if r["pattern"] else "-"))
