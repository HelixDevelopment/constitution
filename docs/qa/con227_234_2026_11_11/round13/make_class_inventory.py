#!/usr/bin/env python3
"""Class inventory of the network-spawn gate, round 13 (§11.4.276(C)): every way a release script could start a
program outside rc_net, as a closed set of classes, each with its member control needles from
tests/release/netgate_controls.jsonl (part 2c of tests/release/test_channel_census.sh runs every one with an empty
PATH, through the analyser: netgate --pin tests/release/netgate_pin.tsv --analyser-only). Run from the repository
root:
  python3 -I docs/qa/con227_234_2026_11_11/round13/make_class_inventory.py > docs/qa/con227_234_2026_11_11/round13/class_inventory.md
Exit 1 when a control has no class, has two classes, or a class names a control that does not exist, so the
inventory cannot drift from the controls. Classes K1-K9 keep their round-12 members; K10-K14 are new in round 13.

What a class means here (corrected from round 12, F3 of the round-12 review): a class lists the members found so far
and the rule of the analyser that refuses them. The analyser is a positive grammar (anything outside it is refused),
so a member not yet found is refused when it falls outside that grammar; it is not a proof that bash has no other
member. The byte pin, not this inventory, is what makes an unreviewed change to a release script a finding."""
import ast
import json
import sys

R12 = "docs/qa/con227_234_2026_11_11/round12/make_class_inventory.py"


def r12_members():
    """the member lists of K1-K9 of round 12, read from the round-12 generator (never retyped)"""
    tree = ast.parse(open(R12, encoding="utf-8").read(), R12)
    val = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) \
                and node.targets[0].id in ("CLASSES", "NEG"):
            val[node.targets[0].id] = ast.literal_eval(node.value)
    return {c[0]: list(c[4]) for c in val["CLASSES"]}, list(val["NEG"][4])


M12, NEG12 = r12_members()
CLASSES = [
    ("K1", "Spelling of the command word",
     "a quoted, escaped, path, brace, glob, tilde, ANSI-C or variable command word",
     "a literal command word must match `CMDNAME_RE` after quote removal, else `command word the gate cannot "
     "classify`; an expansion in command position is refused except at the exact parsed words of `DYN_SITES`",
     M12["K1"] + ["R93_ctrl_ansi_c_command_word"]),
    ("K2", "Command position in a syntax context, or a construct outside the closed parser",
     "a command after a redirection, an fd prefix or an assignment, or inside a compound command, a substitution, a "
     "here-document, a process substitution or a `[[ ]]`; a construct the release scripts do not use",
     "the parser reads every command of every context it accepts and refuses (`unmodelled construct, refused`) every "
     "construct outside the feature set of the release scripts: `&`, `|&`, `coproc`, `select`, `until`, `time`, the "
     "`function` keyword, `for ((`, `$[ ]`, `$\"...\"`, backticks, `${ cmd; }`, here-documents (`<<`, `<<-`), a "
     "process substitution that is not a redirection target, and the redirection operators off `REDIR_OK`",
     M12["K2"] + ["R15_heredoc_delim_continuation", "R16_heredoc_body_in_comsub", "R23_cond_procsubst",
                  "R43_heredoc_delim_paren_in_comsub", "R91_ctrl_comment_continuation", "O03_function_keyword",
                  "O04_background", "O05_pipe_stderr", "O06_heredoc_comsub", "O07_backtick_escaped_nested",
                  "O08_locale_string_comsub", "O11_param_replace_comsub", "O42_process_substitution",
                  "O56_coproc", "O57_select", "O68_funsub_unquoted", "O69_valuesub_unquoted",
                  "O73_heredoc_body_read"]),
    ("K3", "A builtin or wrapper that runs a command, or a string that is run later",
     "`jobs -x`, `wait`, `command -p`, `builtin`, `exec`, `env`, `nice`, `xargs`, `eval`, `bash -c`, `source`, "
     "`trap` strings, `alias`, `enable`, `hash`, `mapfile`, `compgen`, `type`, `shopt`/`set` options, `${x@P}`",
     "`BUILTIN_ALLOWED` is the closed set of builtins the release scripts use, each with its own grammar in "
     "`Gate.builtin` (for example `command -v NAME` only, `compgen -e` or `compgen -A function` only, `shopt -s "
     "execfail` only, `set` with `+f +x -f -u` only, `trap` with a static action and EXIT/HUP/INT/TERM only, "
     "`exec` only on `ALLOW_EXEC`, `eval` and dynamic words only at the exact parsed words of `DYN_SITES`, `.` only "
     "in the exact forms of `SOURCE_OK`); every other builtin and option is refused; an interpreter or exec wrapper "
     "is allowed only when its parsed words equal an entry of `ALLOW_EXEC`",
     M12["K3"] + ["R01_jobs_x", "R02_builtin_jobs_x", "R06_allow_exec_comment", "R07_allow_exec_same_line",
                  "R22_source_same_basename", "D1_compgen_W", "D2_mapfile_tC", "D2b_mapfile_C_attached",
                  "MR10a_shopt_extdebug", "MR10b_set_o_extdebug", "O12_param_P_transform", "O13_compgen_V",
                  "O14_hash_p", "O15_command_p", "O29_exec_program", "O32_trap_USR1", "O33_shopt_expand_aliases",
                  "O34_set_o_posix", "O46_alias", "O47_source_other", "O48_eval", "O49_enable", "O55_type_p",
                  "O64_builtin_builtin"]),
    ("K4", "A local program that starts commands itself",
     "awk `system()`, pipes, `getline` from a command, `@load`, `/inet` (also computed, escaped, as an operand or "
     "through `-v`); sed `e`, `s///e`, `w`, `r`, options; sort `--compress-program` in every spelling, alone or with other options; sqlite3 "
     "dot-commands, `-init`, `-cmd`, `-nonce`, and `-safe` eaten as the value of another option",
     "`LOCAL_PROG`: an awk or sed program must have a sha256 on the P list of the pin (a whitelist, checked by the "
     "analyser too) and pass the checker; awk takes only `-F` and `-v` with no `inet` and no escape in the value, and "
     "no operand that is a `/inet` name or an assignment; sort takes `-V` only; sqlite3 must have `-safe` as its "
     "first argument and only the options of `SQLITE_OPTS`",
     M12["K4"] + ["R17_sqlite_separator_eats_safe", "R18_sqlite_nullvalue_eats_safe", "R19_gawk_inet_computed",
                  "R20_gawk_inet_octal_escape", "R21_gawk_inet_operand", "R31_gawk_inet_via_v",
                  "R96_ctrl_sed_e_command", "D6_sqlite_nonce", "D7_awk_attached_f", "D9_sort_compress_sep",
                  "O25_sqlite_safe_not_first", "O26_unpinned_awk", "O27_unpinned_sed",
                  "O28_sort_compress_attached", "O54_sqlite_init", "O62_awk_pinned_operand_inet",
                  "O63_sed_e_option", "O65_awk_v_escape", "O70_sort_long_option_alone"]),
    ("K5", "A network program, or a program the gate does not know",
     "git, curl, ssh, gh, glab, wget, socat, lftp, aria2c, `git-upload-pack`, `python3.13` and any other name",
     "`NETCMDS` only through `rc_net` or a trusted wrapper; any other name that is not a builtin of the closed set, "
     "a function of the scripts, `LOCAL_SIMPLE` or `LOCAL_PROG` is `unclassified command`, with no lookup on the host",
     M12["K5"] + ["R90_ctrl_plain_git"]),
    ("K6", "State that changes how a command is found or run",
     "`PATH`, `BASH_ENV`, `ENV`, `CDPATH`, `LD_*`, `GCONV_*` and the other names of `DANGER_NAMES`, written by an "
     "assignment, a prefix, `export`, `declare`, `local`, `read`, `getopts`, `printf -v`, `wait -p`, `${NAME:=}`, "
     "`set -k` or a dynamic `printf` format",
     "every write the parser records goes through one check (`check_writes`): a name of `DANGER_NAMES` or with the "
     "prefix `LD_` or `GCONV_` is a finding (IFS only with a value of `IFS_VALUES`), and so is a name off the name "
     "list of the pin (K13); the builtins that write names do so only in their closed grammars (`declare -A NAME`, "
     "`local NAME[=VALUE]`, `read` with `-r`/`-d`, `printf` without options); `${NAME:=}` and the other assigning "
     "parameter operators are off `PARAM_OPS`",
     M12["K6"] + ["R08_printf_v_attached_PATH", "R10_param_default_assign_PATH", "R11_wait_p_PATH",
                  "R14_set_a_bash_env", "R14b_set_a_bash_env", "R14c_ctrl_bash_env_named_assignment",
                  "R24_getopts_dashdash_PATH", "R42_set_k_PATH_in_args", "R95_ctrl_printf_v_separate_PATH",
                  "R97_ctrl_prefix_PATH", "D3_declare_gn_PATH", "D8_read_r_PATH", "MR5a_LD_LIBRARY_PATH_prefix",
                  "MR5b_export_LD_AUDIT", "O16_CDPATH", "O17_BASH_ARGV0", "O18_POSIXLY_CORRECT",
                  "O30_printf_v_PATH", "O31_printf_dynamic_format", "O36_declare_n", "O37_local_i", "O38_read_a",
                  "O50_IFS_dynamic", "O51_export_BASH_ENV", "O52_LD_PRELOAD_prefix", "O53_ENV",
                  "O59_GCONV_prefix", "O72_GCONV_prefix_other"]),
    ("K7", "A raw socket", "a redirection to `/dev/tcp/...`, `/dev/udp/...` or any other device file",
     "a redirection target under `/dev/` other than `/dev/null` is refused",
     M12["K7"] + ["R94_ctrl_dev_tcp", "O45_dev_tcp"]),
    ("K8", "The trusted wrappers themselves",
     "`nt` or `net` defined twice, assigned, given an extra body, a script's own `rc_net`, `unset -f rc_net`",
     "the wrappers are trusted only when their bodies match the expected form (`TRUST_CAND`, `GATE_WRAPPERS`); "
     "`rc_net` is trusted only as the library's; `unset` takes `-v` only",
     M12["K8"] + ["O35_unset_f_rc_net"]),
    ("K9", "A script the gate cannot read", "an unterminated quote, substitution or here-document",
     "a parse error is a finding (netgate) and a lint finding (the lint uses the same parser)", M12["K9"]),
    ("K10", "A function that changes what a name runs",
     "a function defined after its first call, in a subshell, a compound command, a dead branch or another "
     "function, defined twice, or named like a builtin or a program (round 12 treated a name as a function in the "
     "whole file when a definition existed anywhere: R03-R05)",
     "a function must be defined once, at the top level, before every call that can reach it (a trap action "
     "counts as a call where the trap is set), with a name outside `BASH_BUILTINS`, the reserved words, "
     "`NETCMDS`, `EXECWRAP` and `LOCAL_OK` (`check_def`, `check_process`)",
     ["R03_func_defined_after_use", "R04_func_in_subshell", "R05_func_in_dead_branch", "O21_nested_function",
      "O22_call_before_definition", "O23_duplicate_definition", "O24_function_named_like_builtin",
      "O60_trap_action_function_late"]),
    ("K11", "A redirection outside the closed grammar",
     "`<>`, `&>`, `{fd}`, an explicit file descriptor other than 1-4 and 9, a text value in a name used as a "
     "redirection target",
     "the operator must be on `REDIR_OK`, the file descriptor on `REDIR_FDS`; a `{name}` redirection is refused; a "
     "name used as a `>&`/`<&` target may be written only with a number",
     ["O39_redirect_read_write", "O40_redirect_both", "O41_redirect_fd_variable", "O44_exec_fd5",
      "O58_fd_name_written_text"]),
    ("K12", "An arithmetic or subscript context that assigns or runs",
     "`((PATH=0))`, `$((PATH=0))`, `$[ ]`, `for ((`, `let`, `[[ 1 -eq PATH=0 ]]`, `[[ -v 'a[...]' ]]`, `a[PATH=0]=1`, "
     "`declare -i`, a quoted command substitution in a subscript, a variable whose text holds an assignment, "
     "`++` and `--`",
     "arithmetic is read by a closed grammar (`arith_check`, `ARITH_TOK`: numbers, `N#digits`, names, `$name`, "
     "`${name}`, the operators `+ - * / % & | ^ ! ~ ( ) ? : ,`, `&&`, `||` and the comparisons; no `=` of any kind, "
     "no `++`/`--`, no `<<`/`>>`, no subscript, quote or substitution); a subscript of an indexed array must pass the same grammar; `[[ ]]` "
     "takes only `-n`, `-z`, `==`, `=`, `!=`, `=~`; a name read in arithmetic may be written only with a number "
     "(A6), except the run-time data of `A6_DATA`, each checked by the script before use",
     ["R09_arith_assign_PATH", "R12_wait_p_subscript", "R13_printf_v_attached_subscript", "R25_let_comma_PATH",
      "R26_declare_i_value_assigns_PATH", "R27_cond_eq_literal_subscript", "R28_int_var_literal_assignment",
      "R29_cond_v_literal_subscript", "R30_subscript_assigns_PATH", "R32_arith_expansion_PATH",
      "R33_cond_eq_assigns_PATH", "O01_old_arith_PATH", "O02_for_arith_PATH", "O09_cond_eq_PATH",
      "O10_cond_v_subscript", "O20_arith_name_holds_assignment", "O43_subscript_assigns_PATH",
      "O66_arith_increment"]),
    ("K13", "A name the pin does not know, or a name read indirectly",
     "a write to a variable no release script writes today; `${!n}` of a name off `INDIRECT_OK`",
     "every name a script writes must be on the N list of the pin (the names the reviewed scripts write); "
     "`${!name}` only for the names of `INDIRECT_OK` (each validated by the script before use) and only with the "
     "operators of `INDIRECT_OPS`",
     ["O19_indirect_default_assign", "O61_name_not_on_pin", "O67_indirect_plain"]),
    ("K14", "A shape that passed round 12 and is outside the round-13 grammar",
     "the round-12 pass controls rewritten in a shape the release scripts do not use (an awk or sed program off the "
     "whitelist, `sort` with an option other than `-V`, `local -r`, `printf -v`, a `{name}` redirection, a name off "
     "the pin)",
     "the positive grammar: the shape is refused because it is not one the scripts use, not because it is known bad",
     ["G28_rcnet_tempenv_secret_r12shape", "CP01_sed_ranges_r12shape", "CP02_awk_or_regex_r12shape",
      "CP03_sort_and_sqlite_r12shape", "CP05_builtins_r12shape", "CP06_names_r12shape",
      "CP08_exec_redirections_r12shape"]),
]
NEG = ("N", "Negative controls (must pass)",
       "clean scripts and the shapes the release scripts really use",
       "golden-FALSE: none of these may be a finding (§11.4.201(1))",
       NEG12 + ["R92_ctrl_neg_clean"])

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

print("# Class inventory of the network-spawn gate, round 13")
print()
print("Generated by `make_class_inventory.py` (beside this file, run from the repository root) from")
print("`tests/release/netgate_controls.jsonl`. Each class is a way a release script could start a program outside")
print("`rc_net`; every member is a control needle that part 2c of `tests/release/test_channel_census.sh` runs through")
print("`channel_census.py netgate --pin tests/release/netgate_pin.tsv --analyser-only` with an empty PATH. The generator")
print("exits 1 when a control has no class or two, so the inventory and the controls cannot drift apart.")
print()
print("A class lists the members found so far and the rule that refuses them. The analyser is a positive grammar, so a")
print("member not yet found is refused when it falls outside that grammar; this inventory is not a proof that bash has")
print("no other member (the round-12 inventory said \"in every form\" and \"every context\"; the round-12 review, F3,")
print("showed members it missed). The byte pin is what makes any unreviewed change to a release script a finding.")
print()
fin = sum(len(c[4]) for c in CLASSES)
print("Totals: %d classes, %d controls that must be a finding, %d negative controls, %d controls in all."
      % (len(CLASSES), fin, len(NEG[4]), len(rows)))
print()
print("| Class | Name | Members | Rule in the gate |")
print("|---|---|---|---|")
for cid, title, _d, rule, members in CLASSES + [NEG]:
    print("| %s | %s | %d | %s |" % (cid, title, len(members), rule.replace("|", "\\|")))
for cid, title, desc, _r, members in CLASSES + [NEG]:
    print()
    print("## %s. %s" % (cid, title))
    print()
    print(desc[0].upper() + desc[1:] + ".")
    print()
    print("| Control | Source | Expected | Reason the gate must give |")
    print("|---|---|---|---|")
    for n in members:
        r = names[n]
        print("| `%s` | %s | %s | %s |" % (n, r.get("src", "-").split(";")[0], r["want"],
                                          ("`%s`" % r["pattern"].replace("|", "\\|")) if r["pattern"] else "-"))
