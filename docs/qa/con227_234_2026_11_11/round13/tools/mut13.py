#!/usr/bin/env python3
"""Round 13 gate mutants: one spec, two uses.
  mut13.py emit                      print the harness block (bash mp lines, quoted by this file, never by hand)
  mut13.py check REPO                every replaced text is found exactly once in its source (a stale check)
  mut13.py apply REPO NAME OUTFILE   write the mutated copy of the source of NAME to OUTFILE
  mut13.py names [SRC]               the names (of one source variable)
A mutant is (name, property regex, source variable, [(old, new), ...], comment). The round-12 mutants whose text
still exists are kept with their round-12 text (r12_gate_block.jsonl, extracted by bash from the round-12 harness);
the stale ones are re-applied to the round-13 line that does the same job."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRCS = {"$CENPY": "tests/release/channel_census.py", "$DRF": "scripts/release/derive_release_facts.sh",
        "$TAR": "scripts/release/tag_and_release.sh", "$PUB": "scripts/release_publish_gitea.sh",
        "$LIB": "scripts/release/redact_cut.sh"}
M = []


def mp(name, pat, src, pairs, comment):
    M.append((name, pat, src, pairs, comment))


R12 = {}
for l in open(os.path.join(HERE, "r12_gate_block.jsonl")):
    a = json.loads(l)
    R12[a[0]] = a
R12_COMMENT = {"GN1": "backticks not read as code (a command in `...` is not seen)",
               "GN2": "git not a network command",
               "GN3": "nt and net trusted without reading their definitions",
               "GN4": "a command in a variable not reported",
               "NR1": "a literal command word with a path, glob, brace or tilde taken as a plain name",
               "NR6": "the sed e command not named", "NR7": "the s///e and s///w flags not named",
               "NR10": "awk system() allowed", "NR11": "an awk pipe to or from a command allowed",
               "NR14": "an assignment to PATH allowed", "NR17": "the body of a wrapper candidate not checked",
               "NR28": "a single-quoted command substitution in arithmetic allowed",
               "NR30": "the lint does not report a parse error (a short census)"}
KEEP_PAT = {}   # round 13: property regexes of the kept round-12 mutants, where the killing control changed


def keep(name, pat=None, note=""):
    a = R12[name]
    pairs = list(zip(a[3::2], a[4::2]))
    mp(name, pat or a[1], a[2], pairs, R12_COMMENT[name] + (("; " + note) if note else ""))


# ---- kept: their round-12 text is in the round-13 gate unchanged ----
keep("GN1", "git in backticks|CI79_backtick_nested|O07_backtick_escaped_nested")
keep("GN2")
keep("GN3")
keep("GN4")
keep("NR1")
keep("NR6")
keep("NR7")
keep("NR10")
keep("NR11")
keep("NR14")
keep("NR17")
keep("NR28")
keep("NR30")

# ---- re-applied to the round-13 line that does the same job (their round-12 text is gone) ----
ELSE_GRAMMAR = ('        else:\n            bad("without a grammar (an internal error of the gate)")',
                '        else:\n            pass')


def allowed(b):
    return ('BUILTIN_ALLOWED = {".", ":", "[",', 'BUILTIN_ALLOWED = {"%s", ".", ":", "[",' % b)


mp("GN5", "G21_git_via_gitdashcmd|G22_python_via_absent_name|an unknown command", "$CENPY",
   [('            self.find("unclassified command (default deny): %s:%d %s" % (u.name, line, prog), u, line)',
     '            pass')], "an unknown program name not reported (round 13: re-applied to the site rule)")
mp("GN6", "G29_xargs_git|G30_env_git|G31_nice_git|G37_bash_c|git under env|git under nice|bash -c", "$CENPY",
   [('            if (u.name, via, tuple(x.raw for x in [w] + list(args))) in ALLOW_EXEC:',
     '            if True:')], "every interpreter and exec wrapper allowed (round 13: the parsed-word match)")
mp("NR2", "G13_trap_sq|G14_trap_dq", "$CENPY",
   [('                if a.sval in ("", "-") or FUNC_RE.match(a.sval):\n                    continue',
     '                if True:\n                    continue')], "a trap string not read as code (round 13: load())")
mp("NR3", "G01_coproc|O56_coproc", "$CENPY",
   [('        if w in ("until", "select", "coproc"):', '        if w in ("until", "select"):')],
   "coproc allowed (round 13: the parser refusal)")
mp("NR4", "G15_alias|O46_alias", "$CENPY", [allowed("alias"), ELSE_GRAMMAR],
   "alias allowed (round 13: on the closed list, and the fail-closed else of the builtin grammar dropped)")
mp("NR5", "G11_command_p|CI30_command_git|G34_builtin_command_git|O15_command_p|C53 netgate control needle", "$CENPY",
   [('            if not (len(args) == 2 and sv[0] == "-v"):', '            if False:')],
   "command other than command -v NAME allowed (round 13: the command grammar)")
mp("NR8", "G08_sort_compress_prog|CI42_sort_long_abbrev|D9_sort_compress_sep|O28_sort_compress_attached|O70_sort_long_option_alone",
   "$CENPY",
   [('            if any(x != "-V" for x in sv):',
     '            if any(x != "-V" and not (x or "").startswith("--") for x in sv):')],
   "a long option of sort allowed (round 13: sort -V only; also covers the reviewer's MR9; killed by O70, the only "
   "control with a long option and no other operand)")
mp("NR9", "G09_sqlite_system|O25_sqlite_safe_not_first", "$CENPY",
   [('            if sv[:1] != ["-safe"]:', '            if False:')], "sqlite3 without -safe first allowed")
mp("NR12", "CI70_exec_unknown_opt", "$CENPY",
   [('                else:\n                    bad("with the option %s" % sv[j])\n                    return',
     '                else:\n                    j += 1')], "an unknown exec option skipped")
mp("NR13", "O47_source_other", "$CENPY",
   [('                    not any(x[0] == u.name and x[1] == ws[1].raw for x in SOURCE_OK)):',
     '                    False):')], "a source command outside SOURCE_OK allowed")
mp("NR15", "CI19_let_subscript", "$CENPY", [allowed("let"), ELSE_GRAMMAR],
   "let allowed (round 13: let is off the closed list)")
mp("NR16", "CI20_cond_subscript|O09_cond_eq_PATH|O10_cond_v_subscript", "$CENPY",
   [('            self.refuse(start, "[[ ]] outside the closed grammar: %s" % why)', '            pass')],
   "[[ ]] outside its closed grammar allowed (round 13: cond_check)")
mp("NR18", "CI18_unset_f|O35_unset_f_rc_net", "$CENPY",
   [('            else:\n                bad("other than unset -v NAME... or unset \'NAME[SUBSCRIPT]\'")',
     '            else:\n                pass')], "unset -f allowed (round 13: the unset grammar)")
mp("NR19", "CI16_set_x", "$CENPY", [('SET_ARGS = {"+x", "-u", "-f", "+f"}', 'SET_ARGS = {"+x", "-x", "-u", "-f", "+f"}')],
   "set -x allowed")
mp("NR20", "CI03_prompt_expansion|O12_param_P_transform", "$CENPY",
   [('PARAM_OPS = {"", ":-",', 'PARAM_OPS = {"@", "", ":-",')], "${x@P} allowed (round 13: the operator list)")
mp("NR21", "O68_funsub_unquoted|O69_valuesub_unquoted", "$CENPY",
   [('            self.refuse(start, "${ command; } substitution (bash 5.3): a command list inside a parameter expansion")',
     '            pass')], "${ cmd; } and ${| cmd; } allowed (round 13: killed by the unquoted forms O68 O69)")
mp("NR22", "CI04_dev_tcp|CI05_dev_udp|O45_dev_tcp", "$CENPY",
   [('        elif "/dev/" in target and target != "/dev/null":', '        elif False:')],
   "a /dev/tcp or /dev/udp redirection allowed (round 13: every device file but /dev/null)")
mp("NR23", "CI10_declare_n|O36_declare_n|D3_declare_gn_PATH", "$CENPY",
   [('            else:\n                bad("other than declare -A NAME")', '            else:\n                pass')],
   "declare -n allowed (round 13: declare -A NAME only; also covers the reviewer's MR3)")
mp("NR23b", "CI75_local_n|O37_local_i", "$CENPY",
   [('                if w.sval == "-":\n                    continue', '                if w.sval.startswith("-"):\n                    continue')],
   "local -n allowed (round 13: local takes only - and names)")
mp("NR24", "CI08_hash_p|O14_hash_p", "$CENPY", [allowed("hash"), ELSE_GRAMMAR], "hash -p allowed")
mp("NR25", "G35_eval_git|CI31_builtin_eval|O48_eval", "$CENPY",
   [('        elif s == "eval":\n            bad("outside the exact sites of DYN_SITES")', '        elif s == "eval":\n            pass')],
   "eval allowed (round 13: eval only at the exact DYN_SITES)")
mp("NR26", "CI13_mapfile_callback|D2_mapfile_tC|D2b_mapfile_C_attached", "$CENPY", [allowed("mapfile"), ELSE_GRAMMAR],
   "mapfile -C allowed (round 13: mapfile is off the closed list; also covers the reviewer's MR2)")
mp("NR27", "CI14_compgen_c|D1_compgen_W|O13_compgen_V", "$CENPY",
   [('            if sv not in (["-e"], ["-A", "function"]):', '            if False:')],
   "compgen -C/-W/-V allowed (round 13: the compgen grammar; also covers the reviewer's MR1)")
mp("NR29", "CI21_assign_subscript|O43_subscript_assigns_PATH", "$CENPY",
   [('        if why:\n            self.find("a subscript of the indexed array', '        if False:\n            self.find("a subscript of the indexed array')],
   "a subscript outside the arithmetic grammar allowed (round 13: subscript())")
mp("NR32", "lint depends on the host PATH|lint misses|lint rc=|stale row", "$CENPY",
   [('           for n, l, p, via, _cls, norm in g.sites if n == base and not p.startswith(("rc_", "_rc_"))]',
     '           for n, l, p, via, _cls, norm in g.sites if n == base and not p.startswith(("rc_", "_rc_")) and __import__("shutil").which(p)]')],
   "the round-11 host lookup put back into the lint census")
mp("NR33", "G10_absent_netcmd_aria2c|depends on the host PATH|golden-FALSE", "$CENPY",
   [('        else:\n            self.external(u, c, k, "")\n\n    def builtin',
     '        elif __import__("shutil").which(s):\n            self.external(u, c, k, "")\n\n    def builtin')],
   "the round-11 host lookup put back into the gate")

# ---- the round-12 reviewer's mutants MR5-MR10, re-applied to the round-13 rule that does the same job (MR1, MR2,
# MR3 and MR9 are NR27, NR26, NR23 and NR8; MR4 is NR22) ----
mp("MR5x", "MR5a_LD_LIBRARY_PATH_prefix|MR5b_export_LD_AUDIT", "$CENPY",
   [('    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))',
     '    return name in DANGER_NAMES or name.startswith(("LD_PRELOAD", "GCONV_"))')],
   "MR5 re-applied: LD_LIBRARY_PATH and LD_AUDIT not dangerous")
mp("MR6x", "D6_sqlite_nonce", "$CENPY",
   [('SQLITE_OPTS = {"-readonly",', 'SQLITE_OPTS = {"-nonce", "-readonly",')], "MR6 re-applied: sqlite3 -nonce allowed")
mp("MR7x", "D7_awk_attached_f", "$CENPY",
   [('                if s.startswith(("-F", "-v")) and len(s) > 2:', '                if s.startswith(("-F", "-v", "-f")) and len(s) > 2:')],
   "MR7 re-applied: awk -fFILE skipped as an attached option")
mp("MR8x", "D8_read_r_PATH", "$CENPY",
   [('                if sv[j] == "-r":\n                    j += 1', '                if sv[j] == "-r":\n                    j += 2')],
   "MR8 re-applied: the name after read -r taken as an option value")
mp("MR10x", "MR10a_shopt_extdebug", "$CENPY",
   [('            if sv != ["-s", "execfail"]:', '            if sv not in (["-s", "execfail"], ["-s", "extdebug"]):')],
   "MR10 re-applied: shopt -s extdebug allowed")
mp("MR10y", "MR10b_set_o_extdebug", "$CENPY",
   [('SET_ARGS = {"+x", "-u", "-f", "+f"}', 'SET_ARGS = {"+x", "-u", "-f", "+f", "-o", "extdebug"}')],
   "MR10 re-applied: set -o extdebug allowed")
mp("MS1", "C53 netgate", "$DRF", [('q() { sqlite3 -safe -readonly', 'q() { sqlite3 -separator -safe -readonly')],
   "the round-12 reviewer's MS1 verbatim: -safe swallowed as the value of -separator (killed by the derive suite's C53)")

# ---- PN: the pin (layer 1), killed by part 2d of the channel suite ----
mp("PN1", "netgate pin: a trailing space|netgate pin: an appended comment line", "$CENPY",
   [('        if sha(u.text) == h and len(u.lines) == nl:\n            continue', '        if True:\n            continue')],
   "the byte comparison of a pinned file skipped")
mp("PN2", "netgate pin: a trailing space", "$CENPY",
   [('            if new != old:\n                out.append("PIN %s:%d line key',
     '            if (new or (None,))[0] != (old or (None,))[0]:\n                out.append("PIN %s:%d line key')],
   "a line compared by its normalised key only (a trailing space passes the line check)")
mp("PN3", "netgate pin: a file that is not on the pin", "$CENPY",
   [('        out.append("PIN a file that is not on the pin: %s" % name)', '        pass')],
   "a file that is not on the pin not reported")
mp("PN4", "netgate pin: a file of the pin that was not given", "$CENPY",
   [('        out.append("PIN a file of the pin that was not given or loaded: %s" % name)', '        pass')],
   "a pinned file that was not given not reported")
mp("PN5", "netgate pin: a site row removed from the pin", "$CENPY",
   [('    for s in sorted(got - pin["S"]):', '    for s in sorted(set()):')], "a site that is not on the pin not reported")
mp("PN6", "netgate pin: a site row the analyser does not find", "$CENPY",
   [('    for s in sorted(pin["S"] - got):', '    for s in sorted(set()):')], "a pinned site the analyser does not find not reported")
mp("PN7", "netgate pin: an unreadable pin|unreadable pin \\(the name", "$CENPY",
   [('        pin["bad"].append("the pin table cannot be read: %s" % e.strerror)', '        pass')],
   "an unreadable pin not reported")
mp("PN8", "netgate pin: a pin with no rows", "$CENPY",
   [('    if not pin["F"] or not pin["N"]:', '    if False:')], "a pin with no F or N rows accepted")
mp("PN9", "netgate pin: a row the gate does not know", "$CENPY",
   [('                pin["bad"].append("pin table line %d: a row the gate does not know" % n)', '                pass')],
   "an unknown pin row skipped")
mp("PN10", "netgate pin: a number field that is not a number", "$CENPY",
   [('            pin["bad"].append("pin table line %d: a number field that is not a number" % n)', '            pass')],
   "a pin row with a bad number skipped")
mp("PN11", "netgate pin: netgate without --pin", "$CENPY",
   [('        if rest[:1] != ["--pin"] or len(rest) < 2:', '        if len(rest) < 2:')],
   "netgate without --pin runs (the first script read as the pin)")
mp("PN12", "pin-regen is refused|pin-regen with a finding", "$CENPY",
   [('    if bad:\n        for f in bad:\n            print("REFUSED " + f)\n        return 1',
     '    if False:\n        for f in bad:\n            print("REFUSED " + f)\n        return 1')],
   "pin-regen writes the table while the analyser has a finding")
mp("PN14", "unreadable pin \\(the name", "$CENPY",
   [('    if analyser_only and pin["bad"]:', '    if False:')],
   "the analyser alone ignores an unreadable pin (its name and program lists come from the pin)")
mp("PN15", "committed pin differs|pin-diff of the committed|pin-diff shows a changed file", "$CENPY",
   [('            rows.append(("L", u.name, str(i), k8, s16))', '            rows.append(("L", u.name, str(i), k8, l[:40]))')],
   "the pin and pin-diff carry script text")
mp("PN16", "committed pin differs", "$CENPY",
   [('        if name not in first or (u.name, line) < first[name]:', '        if name not in first:')],
   "the name rows depend on the argument order")
mp("PN17", "pin-diff of a changed copy", "$CENPY",
   [('    return 1 if (old != new or g.findings) else 0', '    return 1 if g.findings else 0')],
   "pin-diff exits 0 on a difference")
mp("PN18", "netgate pin: a site row the analyser does not find|netgate pin: a site row removed", "$CENPY",
   [('    got = {(n, l, p, v or "", c, sha(norm)[:8]) for n, l, p, v, c, norm in g.sites}',
     '    got = set(pin["S"])')], "the analyser's sites not compared with the pin")

mp("PN19", "netgate pin: pin-regen BLIND", "$CENPY",
   [('    if not g.sites:\n        bad.append("BLIND: no invocation found")', '    if False:\n        bad.append("BLIND: no invocation found")')],
   "pin-regen writes a table for files with no invocation (BLIND)")
MEQ = [("PN13", "$CENPY", '        if is_danger(name) and name != "IFS":', '        if False:',
        "pin-regen refuses on every analyser finding first, and the analyser reports every write of a name of "
        "DANGER_NAMES (IFS only with a closed value), so the second check in pin_regen cannot change the outcome; "
        "probe: round13/mutants.md PN13")]


# ---- AN: the analyser (layer 2), the round-13 rules, each killed by its control needle ----
def refuse_pass(text):
    return [(text, text[:len(text) - len(text.lstrip())] + "pass")]


mp("AN1", "O66_arith_increment", "$CENPY",
   [('        if tok in ("+", "-") and prev == tok:', '        if False:')], "++ and -- allowed in arithmetic")
mp("AN2", "O67_indirect_plain|O19_indirect_default_assign", "$CENPY",
   [('        if (script, name) not in INDIRECT_OK or subs:', '        if False:')], "every indirect expansion allowed")
mp("AN3", "O65_awk_v_escape", "$CENPY",
   [('        if s is not None and ("inet" in s or "\\\\" in s):', '        if False:')],
   "an awk -v value with an escape or inet allowed")
mp("AN4", "O62_awk_pinned_operand_inet", "$CENPY",
   [('                if w.sval is not None and ("inet" in w.sval or re.match(', '                if False and ("inet" in w.sval or re.match(')],
   "an awk operand /inet/... or NAME=VALUE allowed")
mp("AN5", "O26_unpinned_awk|O27_unpinned_sed", "$CENPY",
   [('        if self.pin is not None and not self.regen and (kind, h) not in self.pin["P"]:', '        if False:')],
   "an awk or sed program off the pin's whitelist allowed")
mp("AN6", "O61_name_not_on_pin", "$CENPY",
   [('            if self.pin is not None and not self.regen and name not in self.pin["N"]:', '            if False:')],
   "a write to a name off the pin's name list allowed")
mp("AN7", "O23_duplicate_definition", "$CENPY",
   [('                if rec[0] in defs:\n                    self.find("a function defined twice', '                if False:\n                    self.find("a function defined twice')],
   "a function defined twice allowed")
mp("AN8", "O22_call_before_definition|O60_trap_action_function_late", "$CENPY",
   [('                if g in defs and defs[g] >= k:', '                if False:')], "a call before the definition allowed")
mp("AN9", "O21_nested_function", "$CENPY", [('        if not top:', '        if False:')],
   "a function defined outside the top level allowed")
mp("AN10", "O24_function_named_like_builtin", "$CENPY",
   [('        if name in BASH_BUILTINS or name in RESERVED or name in NETCMDS or name in EXECWRAP or name in LOCAL_OK:',
     '        if False:')], "a function named like a builtin or a program allowed")
mp("AN11", "O04_background", "$CENPY",
   refuse_pass('                self.refuse(self.i, "& (a background job runs past the statement that started it)")'),
   "a background job allowed")
mp("AN12", "O05_pipe_stderr", "$CENPY", refuse_pass('                self.refuse(self.i, "|& (a pipe of standard error)")'),
   "|& allowed")
mp("AN13", "O03_function_keyword", "$CENPY",
   refuse_pass('            self.refuse(i, "the function keyword (a definition is NAME() { ... } at the top level)")'),
   "the function keyword allowed")
mp("AN14", "O42_process_substitution", "$CENPY",
   refuse_pass('                        self.refuse(start, "a process substitution that is not the target of a redirection")'),
   "a process substitution as an argument allowed")
mp("AN15", "O08_locale_string_comsub", "$CENPY",
   refuse_pass('            self.refuse(i, \'$"..." (a locale translation of a string)\')'), "$\"...\" allowed")
mp("AN17", "O01_old_arith_PATH", "$CENPY", refuse_pass('            self.refuse(i, "$[ ... ] (the old arithmetic expansion)")'),
   "$[ ] allowed")
mp("AN18", "O02_for_arith_PATH", "$CENPY", refuse_pass('            self.refuse(i, "for (( ... )) (an arithmetic loop)")'),
   "for (( )) allowed")
mp("AN20", "O20_arith_name_holds_assignment", "$CENPY",
   [('                if why and (wu.name, func, name) not in A6_DATA:', '                if False:')],
   "a non-numeric value of a name read in arithmetic allowed (A6)")
mp("AN21", "O58_fd_name_written_text", "$CENPY",
   [("            if name in fdn and (val is None or val.sval is None or not re.match(r'[0-9]+\\Z', val.sval)):",
     '            if False:')], "a file-descriptor name holding text allowed")
mp("AN22", "O39_redirect_read_write|O40_redirect_both", "$CENPY",
   [('        if op not in REDIR_OK:', '        if False:')], "every redirection operator allowed")
mp("AN23", "O44_exec_fd5", "$CENPY", [('        if fd not in REDIR_FDS:', '        if False:')],
   "a redirection of any file descriptor allowed")
mp("AN24", "O41_redirect_fd_variable", "$CENPY",
   refuse_pass('                    self.refuse(self.i, "a {name} redirection (it assigns the name)")'), "{fd} redirection allowed")
mp("AN25", "O30_printf_v_PATH|O31_printf_dynamic_format", "$CENPY",
   [('            if not sv or sv[0] is None or (sv[0].startswith("-") and not dd):', '            if not sv:')],
   "printf -v and a dynamic format allowed")
mp("AN26", "O32_trap_USR1", "$CENPY",
   [('            if len(args) < 2 or sv[0] is None or any(x not in TRAP_SIGNALS for x in sv[1:]):',
     '            if len(args) < 2 or sv[0] is None:')], "trap on any signal allowed")
mp("AN27", "O33_shopt_expand_aliases|MR10a_shopt_extdebug", "$CENPY",
   [('            if sv != ["-s", "execfail"]:', '            if False:')], "every shopt allowed")
mp("AN28", "O50_IFS_dynamic", "$CENPY",
   [('                      val.sval is not None and val.sval in IFS_VALUES)', '                      True)')],
   "IFS with any value allowed")
mp("AN29", "O29_exec_program", "$CENPY", [('            if (u.name, "exec", prog) in ALLOW_EXEC:', '            if True:')],
   "exec of any command allowed")
mp("AN30", "O64_builtin_builtin", "$CENPY",
   [('            if args and args[0].lit and args[0].sval in BUILTIN_ALLOWED and args[0].sval != "builtin":',
     '            if args and args[0].lit and args[0].sval in BUILTIN_ALLOWED:')], "builtin builtin allowed")
mp("AN31", "O38_read_a", "$CENPY",
   [('                else:\n                    bad("with the option %s (only -r and -d)" % sv[j])\n                    return',
     '                else:\n                    j += 1')], "read with any option allowed")
mp("AN32", "O57_select", "$CENPY", [('        if w in ("until", "select", "coproc"):', '        if w in ("until", "coproc"):')],
   "select allowed")
mp("AN33", "O16_CDPATH", "$CENPY", [('"BASHOPTS", "BASH_LOADABLES_PATH", "BASH_CMDS", "BASH_ALIASES", "GCONV_PATH", "CDPATH",',
                                     '"BASHOPTS", "BASH_LOADABLES_PATH", "BASH_CMDS", "BASH_ALIASES", "GCONV_PATH",')],
   "CDPATH not dangerous")
mp("AN34", "O72_GCONV_prefix_other", "$CENPY",
   [('    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))', '    return name in DANGER_NAMES or name.startswith(("LD_",))')],
   "the GCONV_ prefix not dangerous (O59 writes GCONV_PATH, also on DANGER_NAMES; O72 writes GCONV_ZZ)")
mp("AN35", "O53_ENV|O51_export_BASH_ENV", "$CENPY",
   [('DANGER_NAMES = {"PATH", "EXECIGNORE", "BASH_ENV", "ENV",', 'DANGER_NAMES = {"PATH", "EXECIGNORE",')],
   "BASH_ENV and ENV not dangerous")
mp("AN36", "CI01_funsub|CI02_valuesub|parse error", "$CENPY",
   [('            self.findings.append("parse error (the gate refuses what it cannot read): %s" % e)\n        # the action',
     '            pass\n        # the action')], "a parse error of a script not reported (the gate passes a script it cannot read)")
mp("AN37", "O73_heredoc_body_read", "$CENPY",
   [('            if not quoted:\n                c = self.child(text, start)\n                c.read_dq(None)',
     '            if False:\n                c = self.child(text, start)\n                c.read_dq(None)')],
   "an unquoted here-document body not read (the refusal of `<<` stays; the finding for the command substitution "
   "in the body is lost; killed by O73)")
mp("AN38", "O11_param_replace_comsub", "$CENPY",
   [("        return \"the operator %s (:= and = assign; @, / and the others are not on the list)\" % op, arr, subs, offs",
     "        return None, arr, subs, offs")], "every parameter operator allowed")
mp("AN39", "O52_LD_PRELOAD_prefix", "$CENPY",
   [('    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))', '    return name in DANGER_NAMES or name.startswith(("GCONV_",))')],
   "the LD_ prefix not dangerous")

mp("AN40", "netgate prints the line text or no key", "$CENPY",
   [('        f = "%s | key=%s" % (msg, key)', '        f = "%s | %s" % (msg, self.norm(u, line)[:100])')],
   "a finding prints the line text (O2 of the round-12 review)")
mp("AN41", "lint misses a new token line, printed by its key only", "$CENPY",
   [('findings.append("secret reference with no secret-ref or allowed row: %s:%d key=%s" % (a, i, k))',
     'findings.append("secret reference with no secret-ref or allowed row: %s:%d key=%s | %s" % (a, i, k, _norm))')],
   "a lint finding on a secret line prints the line text (O2)")
mp("AN42", "lint misses a new command with no row, printed by its key only", "$CENPY",
   [('findings.append("no row: %s:%d %s key=%s" % (a, i, c, k))',
     'findings.append("no row: %s:%d %s key=%s | %s" % (a, i, c, k, _norm))')],
   "a lint no-row finding prints the line text (O2)")


def q(s):
    """bash quoting: '...' when it can be, else $'...'"""
    if all(c not in s for c in "'\\\n\t") and all(32 <= ord(c) for c in s):
        return "'" + s + "'"
    out = []
    for c in s:
        out.append({"\\": "\\\\", "'": "\\'", "\n": "\\n", "\t": "\\t"}.get(c, c))
    return "$'" + "".join(out) + "'"


def emit():
    for name, pat, src, pairs, comment in M:
        args = " ".join("%s %s" % (q(o), q(n)) for o, n in pairs)
        print("mp %s %s \"%s\" %s   # %s" % (name, q(pat), src, args, comment))
    for name, src, o, n, ev in MEQ:
        print("meq %s \"%s\" %s %s %s" % (name, src, q(o), q(n), q(ev)))


def check(repo):
    bad = 0
    names = set()
    for name, pat, src, pairs, comment in M:
        if name in names:
            print("DUPLICATE", name)
            bad += 1
        names.add(name)
        s = open(os.path.join(repo, SRCS[src]), encoding="utf-8").read()
        for o, n in pairs:
            if s.count(o) != 1:
                print("STALE", name, s.count(o), repr(o[:70]))
                bad += 1
            s = s.replace(o, n)
    for name, src, o, n, ev in MEQ:
        s = open(os.path.join(repo, SRCS[src]), encoding="utf-8").read()
        if s.count(o) != 1 or name in names:
            print("STALE-OR-DUP", name)
            bad += 1
    print("mutants=%d equivalent=%d bad=%d" % (len(M), len(MEQ), bad))
    return 1 if bad else 0


def apply(repo, name, out):
    for n, pat, src, pairs, comment in M:
        if n == name:
            s = open(os.path.join(repo, SRCS[src]), encoding="utf-8").read()
            for o, nw in pairs:
                assert s.count(o) == 1, (name, o)
                s = s.replace(o, nw)
            open(out, "w", encoding="utf-8").write(s)
            return 0
    return 2


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["emit"]:
        emit()
    elif a[:1] == ["check"]:
        sys.exit(check(a[1]))
    elif a[:1] == ["apply"]:
        sys.exit(apply(a[1], a[2], a[3]))
    elif a[:1] == ["names"]:
        print("\n".join(m[0] for m in M if len(a) < 2 or m[2] == a[1]))
    elif a[:1] == ["pat"]:
        print("\n".join("%s\t%s" % (m[0], m[1]) for m in M))
    else:
        sys.exit(__doc__)
