#!/usr/bin/env python3
"""Self-review probes of the round-12 gate, written by the fixer after the controls were fixed (a second look, not a
control set): each body is run through `channel_census.py netgate` with an empty PATH. OK = a finding; MISS = the gate
passes it. The README (section 3) explains every MISS by hand. Not run by any suite.
Usage: probe_extra.py CENSUS_PY WORKDIR (WORKDIR: an empty directory for the probe scripts)"""
import os
import subprocess
import sys

cen, wd = sys.argv[1:3]
PRE = "#!/usr/bin/env bash\nrc_net git status\n"
BODIES = {
    "line_continuation_in_word": "gi\\\nt fetch\n",
    "time_keyword": "time git fetch\n",
    "source_procsubst": "source <(echo git fetch)\n",
    "dot_stdin_herestring": ". /dev/stdin <<< 'git fetch'\n",
    "if_brace": "if true; then { git fetch; }; fi\n",
    "function_kw_call": "function f { git fetch; }\nf\n",
    "assign_only_subst": "x=$(git fetch)\n",
    "case_body": "case $x in *) git fetch ;; esac\n",
    "indirect_expansion": "n=git; ${!n} fetch\n",
    "empty_quotes_in_word": "g''it fetch\n",
    "nohup": "nohup git fetch\n",
    "stdbuf": "stdbuf -o0 git fetch\n",
    "command_eval": "command eval 'git fetch'\n",
    "builtin_source": "builtin source /tmp/x.sh\n",
    "while_cond": "while git fetch; do :; done\n",
    "until_cond": "until git fetch; do :; done\n",
    "pipeline_tail": "echo x | git fetch\n",
    "and_list": "true && git fetch\n",
    "or_list": "false || git fetch\n",
    "subshell": "( git fetch )\n",
    "arith_cmd": "(( a[$(git fetch)] ))\n",
    "for_in_subst": "for i in $(git fetch); do :; done\n",
    "redirect_target_subst": "echo x > \"$(git fetch)\"\n",
    "heredoc_quoted_to_bash": "bash <<'E'\ngit fetch\nE\n",
    "printf_v_PATH": "printf -v PATH %s /tmp\n",
    "declare_x_PATH": "declare -x PATH=/tmp\n",
    "local_PATH": "f() { local PATH=/tmp; git fetch; }\n",
    "export_f": "git() { :; }\nexport -f git\n",
    "fn_named_git": "git() { curl -s https://h.invalid; }\ngit\n",
    "array_assign_subst": "a=( $(git fetch) )\n",
    "param_default_assign": ": ${x:=$(git fetch)}\n",
    "brace_expansion_cmd": "{git,x} fetch\n",
    "ansi_c_quote_cmd": "$'git' fetch\n",
    "locale_quote_cmd": "$\"git\" fetch\n",
    "exec_fd_tcp": "exec {fd}<>/dev/tcp/h.invalid/80\n",
    "redirect_dup_tcp": "cat 3</dev/tcp/h.invalid/80\n",
    "trap_err": "trap 'git fetch' ERR\n",
    "trap_return": "trap 'git fetch' RETURN\n",
    "prompt_command": "PROMPT_COMMAND='git fetch'\n",
    "bash_env_assign": "BASH_ENV=/tmp/x bash -c :\n",
    "ifs_assign": "IFS=/\n",
    "shellopts": "SHELLOPTS=xtrace\n",
    "ps4": "PS4='$(git fetch)'\n",
    "bash_xtracefd": "BASH_XTRACEFD=3\n",
    "awk_dash_f": "awk -f /tmp/p.awk x\n",
    "sed_e_in_script_file": "sed -f /tmp/s.sed x\n",
    "sort_compress_eq": "sort --compress-program=gzip x\n",
    "sqlite_no_safe": "sqlite3 /tmp/x.db 'select 1'\n",
    "sqlite_safe_dot_shell": "sqlite3 -safe /tmp/x.db '.shell git fetch'\n",
    "jq_env": "jq -n 'env' \n",
    "comment_then_cmd": "# x\ngit fetch # y\n",
    "semicolon_after_comment_word": "echo a#b; git fetch\n",
    "keyword_as_arg_then_cmd": "echo if; git fetch\n",
}
bad = 0
for n, b in sorted(BODIES.items()):
    p = os.path.join(wd, n + ".sh")
    with open(p, "w") as f:
        f.write(PRE + b)
    r = subprocess.run([sys.executable, "-I", cen, "netgate", p], env={"PATH": "/nonexistent", "LANG": "C.UTF-8"},
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    first = next((l for l in r.stdout.splitlines() if l.startswith(("FINDING", "BLIND"))), r.stdout.splitlines()[-1])
    ok = r.returncode != 0
    bad += not ok
    print("%-4s %-30s rc=%d %s" % ("OK" if ok else "MISS", n, r.returncode, first[:150]))
print("SUMMARY probes=%d missed=%d" % (len(BODIES), bad))
