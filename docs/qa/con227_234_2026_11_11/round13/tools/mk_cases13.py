#!/usr/bin/env python3
"""Round 13 cases: the round-12 reviewer's discriminating fixtures (D1-D9, from probes/tools/discriminate.py,
verbatim), the MR5 and MR10 gate-logic fixtures (probes/mutants/gate_logic_MR5_MR10.txt, verbatim, with the same
header line), and the round-13 fixer's own fixtures (O01-O..). Every body starts with the header H of the reviewer.
usage: mk_cases13.py OUT.json"""
import json, sys

H = "#!/usr/bin/env bash\nrc_net git status\n"
EVIL = "#!/bin/bash\n@SB@/bin/git fetch origin\n"
Z = {"0/cat": EVIL}            # a "cat" in ./0: PATH=0 (an arithmetic assignment) makes bash run it
E = {"evil/cat": EVIL}
C = []


def case(name, body, files=None, listen=False):
    c = {"name": name, "body": H + body}
    if files:
        c["files"] = files
    if listen:
        c["listen"] = True
    C.append(c)


# --- the reviewer's discriminating fixtures (verbatim) ---
case("D1_compgen_W", "compgen -W '$(git fetch origin)' x\n")
case("D2_mapfile_tC", "mapfile -tC 'git fetch origin' -c 1 a <<<x\n")
case("D2b_mapfile_C_attached", "mapfile -Cgit -c 1 a <<<x\n")
case("D3_declare_gn_PATH", 'declare -gn r=PATH\nr="$PWD/evil"\ncat /dev/null\n', E)
case("D6_sqlite_nonce", "printf '.nonce zz\\n.system git fetch origin\\n' | sqlite3 -safe -nonce zz :memory:\n")
case("D7_awk_attached_f", "awk -f/dev/stdin /dev/null <<'A'\nBEGIN { system(\"git fetch origin\") }\nA\n")
case("D8_read_r_PATH", 'read -r PATH <<<"$PWD/evil"\ncat /dev/null\n', E)
case("D9_sort_compress_sep", "for ((i = 0; i < 20000; i++)); do echo \"$i\"; done | sort -S 1k -T . --compress-program ./cp.sh >/dev/null\n",
     {"cp.sh": "#!/bin/bash\n@SB@/bin/git fetch origin\nexec cat\n"})
case("MR5a_LD_LIBRARY_PATH_prefix", "LD_LIBRARY_PATH=/x cat /dev/null\n")
case("MR5b_export_LD_AUDIT", "export LD_AUDIT=/x/a.so\n")
case("MR10a_shopt_extdebug", "shopt -s extdebug\n")
case("MR10b_set_o_extdebug", "set -o extdebug\n")

# --- the round-13 fixer's own fixtures (each names its class; the runtime leaks where the shape allows it) ---
case("O01_old_arith_PATH", ": $[PATH=0]\ncat /dev/null\n", Z)
case("O02_for_arith_PATH", "for ((PATH=0; 0; )); do :; done\ncat /dev/null\n", Z)
case("O03_function_keyword", "function f { :; }\nf\n")
case("O04_background", "cat /dev/null &\nwait\n")
case("O05_pipe_stderr", "echo x |& cat\n")
case("O06_heredoc_comsub", "cat <<E\n$(git fetch origin)\nE\n")
case("O07_backtick_escaped_nested", "x=`echo \\`git fetch origin\\``\n")
case("O08_locale_string_comsub", 'x=$"$(git fetch origin)"\n')
case("O09_cond_eq_PATH", "[[ 1 -eq PATH=0 ]]\ncat /dev/null\n", Z)
case("O10_cond_v_subscript", "[[ -v 'a[PATH=0]' ]]\ncat /dev/null\n", Z)
case("O11_param_replace_comsub", 'x=${y/a/$(git fetch origin)}\n')
case("O12_param_P_transform", "p='$(git fetch origin)'\nx=${p@P}\n")
case("O13_compgen_V", "compgen -V a x\n")
case("O14_hash_p", "hash -p @SB@/bin/git cat\ncat /dev/null\n")
case("O15_command_p", "command -p true\n")
case("O16_CDPATH", "CDPATH=/x\n")
case("O17_BASH_ARGV0", "BASH_ARGV0=x\n")
case("O18_POSIXLY_CORRECT", "POSIXLY_CORRECT=1\n")
case("O19_indirect_default_assign", 'n=ZZ\n: "${!n:=1}"\n')
case("O20_arith_name_holds_assignment", "n='PATH=0'\n: $((n+1))\ncat /dev/null\n", Z)
case("O21_nested_function", "f() { g() { :; }; }\nf\n")
case("O22_call_before_definition", "g\ng() { :; }\n")
case("O23_duplicate_definition", "g() { :; }\ng() { :; }\ng\n")
case("O24_function_named_like_builtin", "read() { :; }\n")
case("O25_sqlite_safe_not_first", "sqlite3 -batch -safe :memory: 'select 1'\n")
case("O26_unpinned_awk", "awk '{print $2}' /dev/null\n")
case("O27_unpinned_sed", "sed 's/a/b/' /dev/null\n")
case("O28_sort_compress_attached", "sort --compress-program=./cp.sh /dev/null\n")
case("O29_exec_program", "exec cat /dev/null\n")
case("O30_printf_v_PATH", "printf -v PATH %s @SB@/evil\ncat /dev/null\n", E)
case("O31_printf_dynamic_format", 'f=%s\nprintf "$f" x\n')
case("O32_trap_USR1", "trap ':' USR1\n")
case("O33_shopt_expand_aliases", "shopt -s expand_aliases\n")
case("O34_set_o_posix", "set -o posix\n")
case("O35_unset_f_rc_net", "unset -f rc_net\n")
case("O36_declare_n", "declare -n r=PATH\n")
case("O37_local_i", "f() { local -i x; }\nf\n")
case("O38_read_a", "read -a arr <<<x\n")
case("O39_redirect_read_write", "exec 3<>/dev/null\n")
case("O40_redirect_both", "cat /dev/null &>/dev/null\n")
case("O41_redirect_fd_variable", "exec {fd}</dev/null\n")
case("O42_process_substitution", "cat <(git fetch origin)\n")
case("O43_subscript_assigns_PATH", "a[PATH=0]=1\ncat /dev/null\n", Z)
case("O44_exec_fd5", "exec 5>/dev/null\n")
case("O45_dev_tcp", "exec 3<>/dev/tcp/127.0.0.1/@PORT@\n", listen=True)
case("O46_alias", "alias cat='git fetch origin'\n")
case("O47_source_other", ". ./x.sh\n", {"x.sh": "git fetch origin\n"})
case("O48_eval", "eval 'git fetch origin'\n")
case("O49_enable", "enable -n cat\n")
case("O50_IFS_dynamic", 'IFS="$x"\n')
case("O51_export_BASH_ENV", "export BASH_ENV=@SB@/e.sh\n")
case("O52_LD_PRELOAD_prefix", "LD_PRELOAD=/x cat /dev/null\n")
case("O53_ENV", "ENV=/x\n")
case("O54_sqlite_init", "sqlite3 -safe -init /dev/null :memory: 'select 1'\n")
case("O55_type_p", "type -p git\n")
case("O56_coproc", "coproc git fetch origin\n")
case("O57_select", "select x in a; do break; done </dev/null\n")
case("O58_fd_name_written_text", 'FD=/dev/tcp/127.0.0.1/@PORT@\necho x >&"$FD"\n', listen=True)
case("O59_GCONV_prefix", "GCONV_PATH=/x cat /dev/null\n")
case("O60_trap_action_function_late", "trap g EXIT\ng() { :; }\n")
case("O61_name_not_on_pin", "ZZTOKEN=v\n")
case("O62_awk_pinned_operand_inet", "awk '$2==t{print $1; exit}' /inet/tcp/0/127.0.0.1/@PORT@\n", listen=True)
case("O63_sed_e_option", "sed -e 's/a/b/' /dev/null\n")
case("O64_builtin_builtin", "builtin builtin true\n")
case("O65_awk_v_escape", "awk -vt='\\151net' '$2==t{print $1; exit}' /dev/null\n")
case("O66_arith_increment", "x=1\n: $((x++))\n")
case("O67_indirect_plain", "n=PATH\necho \"${!n}\"\n")
case("O68_funsub_unquoted", "x=${ git fetch origin; }\n")
case("O69_valuesub_unquoted", "x=${| git fetch origin; }\n")
case("O70_sort_long_option_alone", "printf '%s\\n' b a | sort --compress-program=git\n")
case("O71_sort_long_options_spill", "cat in.txt | sort --buffer-size=1k --temporary-directory=. "
     "--compress-program=./cp.sh >/dev/null\n",
     {"in.txt": "".join("%d\n" % i for i in range(20000)), "cp.sh": "#!/bin/bash\n@SB@/bin/git fetch origin\ncat\n"})
json.dump(C, open(sys.argv[1], "w"), indent=1)
print("cases=%d" % len(C))
