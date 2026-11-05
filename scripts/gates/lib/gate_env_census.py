#!/usr/bin/env python3
"""scripts/gates/lib/gate_env_census.py -- static census of ambient environment reads in gate scripts (11.4.201(6)-(8)).

A gate verdict must not be changeable by a stray environment variable. This instrument lists, per gate file, every
variable the file READS but never ASSIGNS (an "ambient read": its value can only come from the environment), plus every
explicit environment read (printenv NAME, python os.environ / os.getenv, awk ENVIRON["NAME"], perl $ENV{NAME}, jq env.NAME /
$ENV.NAME, node process.env.NAME, `env | grep ^NAME=`, declare -p NAME, bash ${!NAME}-free forms).

Forms covered (shell text outside single quotes and outside quoted heredoc bodies):
    $NAME  ${NAME}  ${NAME:-x}  ${NAME-x}  ${NAME:=x}  ${NAME=x}  ${NAME:+x}  ${NAME:?x}  ${#NAME}  ${NAME[..]}  [ -n "$NAME" ]
    printenv NAME ; [[ -v NAME ]] ; declare -p NAME ; ${!NAME} is reported as INDIRECT (the census cannot resolve it: a finding).
Forms covered everywhere (also inside single quotes / quoted heredocs, i.e. embedded python / awk / perl / jq / node programs):
    os.environ["N"] os.environ.get("N") os.getenv("N") environ["N"] ENVIRON["N"] $ENV{N} env.N $ENV.N process.env.N
    process.env["N"]; a python alias (`from os import environ as E`, `E = os.environ`, `import os as o`) is followed.

INDIRECT / UNRESOLVED reads (kind=indirect, always a finding; they can be covered ONLY by an allowlist row naming the
pseudo-variable, because the census cannot say WHICH variable is read -- indirect reads need allowlist rows):
    pseudo-variable      form
    os.environ           whole-environment python use: dict(os.environ) os.environ.copy() os.environ.items() **os.environ ...
    process.env          whole-environment node use (Object.keys(process.env), {...process.env})
    %ENV                 perl whole-hash or non-literal $ENV{$k}
    <env-dump>           `env` / `printenv` with no variable name (env | grep ^X= also reports X as env-api)
    <declare-dump>       declare -p / typeset -p / export -p / compgen -e|-v / bare `set`
    <eval>               `eval` whose argument is built from an expansion (the code it runs is not visible)
    <proc-environ>       a read of /proc/<pid>/environ
    jq-env               jq bare `env` / `$ENV`
    <name>               ${!name}, os.environ.get(name), getenv(name), ENVIRON[name] with a non-literal key

A variable counts as ASSIGNED when the file (or a file it sources) contains, IN COMMAND POSITION (a `NAME=value` word that is
only an argument, or a prefix assignment `NAME=1 cmd` which lasts for that one command, does not count): NAME=, NAME+=,
local NAME[=], declare/typeset NAME=..  (NAME alone only with -a/-A), readonly/export NAME=.. (a bare `export NAME` /
`readonly NAME` / `declare -x NAME` does NOT assign: it re-exports the AMBIENT value), read [-opts] .. NAME, for NAME in,
printf -v NAME, mapfile/readarray .. NAME, getopts .. NAME, or cm_gate_env_set NAME (the guarded-override helper: its OUTVAR
is a local result, its ENV_NAME is a GUARDED read reported with kind=guarded). A read whose FIRST occurrence (in file order)
precedes the first assignment AND uses a default-bearing form (${N:-..}, ${N-..}, ${N:=..}, ${N=..}) is reported as
kind=ambient-default (the default form only makes sense when the value may come from outside): conservative, a finding.

SOURCE CLOSURE (--closure): every file reachable by `.` / `source` is censused. A source argument is resolved for real:
a literal path, `$VAR/rel/path` and `"$(...)/rel/path"` (the tail after the last expansion is tried against the script's
directory, every ancestor up to the root, and the root), or a whole variable (`. "$LIB"`) through ITS assignments in the file
(including `for f in dir/*.sh`). A source statement that cannot be resolved to a file is NOT skipped silently: the run
prints `UNRESOLVED-SOURCE file:line token` on stderr and exits 2 (BLIND).

BEST-EFFORT TRIPWIRE, NOT A PROOF (honest boundary, precedent: the 11.4.287 destructive-path guard). This is a static TEXT scan.
It does NOT detect: `declare -n` namerefs; a bare `declare | grep`-style dump pipeline beyond the forms listed above;
`bash -c '...$X'` / `sh -c` strings run as child programs; python `getattr(os, "environ")` / `posix.environ`; ruby `ENV[...]`
and other languages not listed; variables inherited by a child process the gate runs (that tool's read, not the gate's);
PATH/HOME (SPECIAL, above); gates in nested directories (only scripts/gates/cm_*.sh are enumerated, not scripts/gates/*/cm_*.sh);
`JEV_GATE_TIMEOUT=0` (a numeric knob that disables a timeout, not a name read). BASH_SOURCE is in SPECIAL: that is safe in bash
gates, but a POSIX-sh-capable library can receive an ambient BASH_SOURCE (dash/busybox import it; bash keeps an imported scalar),
so execution_record.sh uses it only after a content-sentinel check. `[ -v X ]`, `test -v X` and `printenv "$n"` ARE detected
(the last as <printenv-var>, indirect). A clean census means none of the detected forms were found, nothing more.

Output (TSV, one row per (file, var, kind)): file<TAB>var<TAB>kind<TAB>line
kinds: ambient (never assigned) | ambient-default | env-api (printenv/os.environ/ENVIRON/...) | guarded (cm_gate_env_set)
       | indirect (unresolvable, always a finding).
Bash special/standard variables (positional, BASH_SOURCE, ...) are ignored: they are not overrides a caller sets to steer
a verdict (listed in SPECIAL below). BOUNDARY: PATH and HOME ARE in SPECIAL and are therefore NOT censused. They are
environment-controlled by definition (every command lookup and every `~` depends on them); a gate whose verdict an attacker can
steer by PATH/HOME is out of scope of this instrument and is covered by the host-safety and PATH-trust rules (not by this
allowlist). A gate that exports or reads them to change behaviour deliberately is a finding for review, not for the census.
"""
import glob as _glob
import os
import re
import sys

SPECIAL = set("""
BASH_SOURCE BASH_LINENO BASH_REMATCH BASHPID BASH_VERSION BASH_VERSINFO BASH BASH_ARGV BASH_ARGC BASH_COMMAND BASH_SUBSHELL
FUNCNAME LINENO RANDOM SECONDS PIPESTATUS IFS OPTIND OPTARG OPTERR PPID UID EUID GROUPS HOSTNAME HOSTTYPE OSTYPE MACHTYPE
PWD OLDPWD HOME PATH SHELL USER LOGNAME TERM LANG LC_ALL LC_CTYPE LC_COLLATE TZ SHLVL REPLY COLUMNS LINES EPOCHSECONDS
EPOCHREALTIME SRANDOM TMPDIR ZSH_EVAL_CONTEXT ZSH_VERSION BASHOPTS SHELLOPTS PS4 HISTFILE COMP_WORDS MAPFILE XDG_RUNTIME_DIR XDG_CACHE_HOME
""".split())

NAME = r"[A-Za-z_][A-Za-z0-9_]*"
# assignment forms other than NAME=value / local / declare / export / readonly / for (those go through assign_table)
RE_ASSIGN = [
    re.compile(r"\bfor\s+\(\(\s*(" + NAME + r")\s*="),
    re.compile(r"\bprintf\s+-v\s+['\"]?(" + NAME + r")"),
    re.compile(r"\bgetopts\s+\S+\s+(" + NAME + r")"),
    re.compile(r"\bcm_gate_env_set\s+(" + NAME + r")\s"),
    re.compile(r"\bcm_hdeps_override\s+(" + NAME + r")\s"),
]
RE_READCMD = re.compile(r"(?:^|[\s;&|(!])(read|mapfile|readarray)\b")
RE_GUARDED = re.compile(r"\bcm_gate_env_set\s+" + NAME + r"\s+(" + NAME + r")\b")
RE_HDEPS = re.compile(r"\bcm_hdeps_override\s+" + NAME + r"\s+(" + NAME + r")\b")
# a source statement: `.` / `source` in COMMAND position (start of line, after ; & | ( { ` ! or a keyword), never an argument
# such as `jq -e . "$f"`.
RE_SRC_CMD = re.compile(r"(?:^|[;&|({`!]|\$\(|\b(?:then|do|else|elif|if|while|until)\b)\s*(?:(?:builtin|command)\s+)?(?:\.|source)\s+(?=\S)")
# `eval ". lib"` / `eval 'source lib'`: the sourced word lives inside a string eval re-parses, so it cannot be resolved here
RE_SRC_EVAL = re.compile(r"\beval\s+(?:\S+\s+)*?[\"']\s*(?:(?:builtin|command)\s+)?(?:\.|source)\s+\S")
RE_SRC_SPLICE = re.compile(r"(?:^|[\s;&|({])(?:\.|source)\s+\"?'\"\$\{?(" + NAME + r")\}?\"'\"")
RE_ENVAPI = [
    re.compile(r"\bprintenv\s+(" + NAME + r")"),
    re.compile(r"\benviron(?:\.get)?\s*[\[(]\s*['\"](" + NAME + r")['\"]"),
    re.compile(r"\bgetenv\s*\(\s*['\"](" + NAME + r")['\"]"),
    re.compile(r"\bENVIRON\s*\[\s*\\?\"(" + NAME + r")\\?\"\s*\]"),
    re.compile(r"\bos\.environ\.setdefault\s*\(\s*['\"](" + NAME + r")['\"]"),
    re.compile(r"\[\[\s+-v\s+(" + NAME + r")"),
    re.compile(r"(?:^|[\s;&|({!])\[\s+-v\s+(" + NAME + r")\s"),                                # [ -v NAME ]
    re.compile(r"(?:^|[\s;&|({!])test\s+-v\s+(" + NAME + r")\b"),                             # test -v NAME
    re.compile(r"\$ENV\s*\{\s*['\"]?(" + NAME + r")['\"]?\s*\}"),                      # perl
    re.compile(r"\bprocess\.env\.(" + NAME + r")\b"),                                     # node
    re.compile(r"\bprocess\.env\s*\[\s*['\"](" + NAME + r")['\"]\s*\]"),
    re.compile(r"\bdeclare\s+-[a-zA-Z]*p[a-zA-Z]*\s+(" + NAME + r")\b"),                 # declare -p NAME
    re.compile(r"\btypeset\s+-[a-zA-Z]*p[a-zA-Z]*\s+(" + NAME + r")\b"),
]
# jq: only meaningful in a file that mentions jq/yq (avoids `config/env.sh` style false hits)
RE_JQ_ENV = [
    re.compile(r"(?<![\w./$-])env\.(" + NAME + r")\b"),
    re.compile(r"\$ENV\.(" + NAME + r")\b"),
    re.compile(r"\$ENV\s*\[\s*\"(" + NAME + r")\"\s*\]"),
    re.compile(r"(?<![\w./$-])env\s*\[\s*\"(" + NAME + r")\"\s*\]"),
]
RE_JQ_ENV_DUMP = [
    re.compile(r"(?<![\w./$-])env\s*(?:\||\)|$)"),
    re.compile(r"\$ENV\b(?!\s*[.\[])"),
]
RE_ENVAPI_INDIRECT = [
    re.compile(r"\benviron(?:\.get)?\s*[\[(]\s*(?!['\"])([A-Za-z_][\w.]*)\s*[\])]"),
    re.compile(r"\bgetenv\s*\(\s*(?!['\"])([A-Za-z_][\w.]*)\s*\)"),
    re.compile(r"\bENVIRON\s*\[\s*(?!\\?\")([A-Za-z_]\w*)\s*\]"),
]
RE_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
CMDPOS = r"(?:^|[;&|({`!]|\$\(|\b(?:then|do|else|elif|if|while|until)\b)\s*"
RE_PRINTENV_VAR = re.compile(r"(?:^|[\s;&|({!])printenv\s+[\"']?\$")   # printenv "$n": a name chosen at run time
RE_ENV_DUMP_ENV = re.compile(CMDPOS + r"(?:env(?:\s+(?:-0|--null))*|printenv)\s*(?=$|[|;&)<>])")
RE_ENV_DUMP_DECL = re.compile(CMDPOS + r"(?:export\s+-p|(?:declare|typeset)\s+-[a-zA-Z]*p[a-zA-Z]*(?:\s+-[a-zA-Z]+)*|compgen\s+-[ev]|set)\s*(?=$|[|;&)<>])")
RE_EVAL = re.compile(CMDPOS + r"eval\b(.*)$")
RE_PROC_ENVIRON = re.compile(r"/proc/(?:self|\$\$|\$\{?\w+\}?|\d+)/environ")
RE_PERL_DUMP = [re.compile(r"(?<![\w%$@])%ENV\b"), re.compile(r"\$ENV\s*\{\s*\$")]
RE_PY_FROM = re.compile(r"\bfrom\s+os\s+import\s+([^\n;]+)")
RE_PY_MODALIAS = re.compile(r"\bimport\s+os\s+as\s+(" + NAME + r")")
RE_PY_ASSIGNALIAS = re.compile(r"\b(" + NAME + r")\s*=\s*(?:os\.)?environ\b(?!\s*[\[.(])")
RE_ENV_GREP = re.compile(r"\^(" + NAME + r")=")


RE_JQ_WORD = re.compile(r"(?<![\w./-])(?:jq|yq|gojq)(?![\w.-])")
RE_OWNER_ASSIGN = re.compile(r"(?:^|[\s;&|(])([A-Za-z_]\w*)\+?=\$?$")
RE_OWNER_READ = re.compile(r"\bread\b[^;&|]*?\s([A-Za-z_]\w*)\s*$")
# A command line that PROVABLY runs a non-jq interpreter at command position (awk/perl/python/sed/grep/...; wrappers such as
# env/command/exec/sudo/nice/time/timeout and VAR=val prefixes allowed). Only such a line disowns the quoted text on it.
# CLASS RULE (CON-015, 11.4.201(4)): the jq whole-environment check is DISARMED only for a region provably owned by such an
# interpreter, or assigned to a variable that is expanded only on such lines; every other region -- jq reached through a
# variable, a ${X:-jq} default, a path (/usr/bin/jq), a wrapper function, an array, a function that returns the program, a
# pipeline continued on the next line, `cmd=jq; "$cmd"`, or any command word the census cannot resolve -- stays ARMED.
_INTERP = (r"(?:awk|gawk|mawk|nawk|perl|python[\d.]*|ruby|node|nodejs|php|lua|sed|gsed|grep|egrep|fgrep|rg|expect|tclsh|"
           r"(?:ba|z|da|k)?sh\s+-c)")
RE_NONJQ_CMD = re.compile(
    r"(?:^|[;&|(`!{]|\$\(|\b(?:then|do|else|elif|if|while|until)\b)\s*"
    r"(?:(?:\w+=\S*|env|command|exec|sudo|nice(?:\s+-n\s*\d+)?|time|builtin|stdbuf\s+\S+|timeout\s+\S+)\s+)*"
    r"(?:\S*/)?" + _INTERP + r"(?![\w.-])")


# text written to a file by cat/tee/printf/echo (`cat >FILE <<'EOF'`, `echo '..' >>FILE`, `tee FILE`): a generated file is
# someone else's program unless FILE is a jq-looking name or is named on a jq command line (checked in census())
RE_OUT_FILE = re.compile(r"\b(?:cat|printf|echo)\b[^|;&]*?>>?\s*(\"[^\"]*\"|'[^']*'|[^\s;&|)]+)|\btee\s+(?:-[a-z]+\s+)*(\"[^\"]*\"|'[^']*'|[^\s;&|)]+)")


def _norm_target(t):
    return t.strip("\"'")


def _runs_nonjq(logical):
    """True when the command line `logical` runs a known non-jq interpreter and mentions no jq/yq/gojq word."""
    return not RE_JQ_WORD.search(logical) and RE_NONJQ_CMD.search(logical) is not None


def _region_owner(logical, prefix):
    """Owner of a quoted region (single-quoted text or a heredoc body) that opens after `prefix` on a command line whose
    text (backslash continuations joined) is `logical`: ("jq",) when that command line runs jq/yq/gojq, ("nonjq",) when it
    provably runs another interpreter (see RE_NONJQ_CMD), ("var", NAME) when the region is assigned to NAME (`NAME='...'`,
    `read ... NAME <<'X'`), ("file", TARGET) when cat/printf/echo/tee writes it to a file, else ("other",), which the census treats as ARMED (undecidable ownership)."""
    if RE_JQ_WORD.search(logical):
        return ("jq",)
    if _runs_nonjq(logical):
        return ("nonjq",)
    m = RE_OUT_FILE.search(logical)
    if m:
        return ("file", _norm_target(m.group(1) or m.group(2)))
    m = RE_OWNER_ASSIGN.search(prefix)
    if m:
        return ("var", m.group(1))
    m = RE_OWNER_READ.search(prefix)
    if m:
        return ("var", m.group(1))
    return ("other",)


def split_code(text, regions=None):
    """Return (expanding, literal) lists of lines (line structure preserved).
    expanding: shell text where $ expands (outside single quotes / $'..' / quoted heredoc bodies; comments blanked).
    literal:   single-quoted text and quoted heredoc bodies: scanned only for env-API calls (embedded python/awk/jq).
    Single-quoted text is rendered as \\x02 (opening quote) + \\x03 per character (including the closing quote): one
    non-blank run, so a word such as `NAME='a b'"$x"` stays ONE word for the structural scanners.
    Quote state is a stack: `$(`, a backquote and `(`-subshells open a fresh quoting context even inside "..."
    When `regions` is a list it receives, per line, a list of (owner, text) for the literal text of that line (owner from
    _region_owner): the jq whole-environment rule reads only regions that are jq code."""
    exp, lit, code = [], [], []
    owner = ("other",)
    cont = ""         # text of the preceding backslash-continued physical lines of the current command line
    lines = text.split("\n")
    i = 0
    stack = ["top"]   # contexts: top | dq | cmd (inside $( ) / backquote) ; sq handled by flag
    sq = None         # None | "'" (plain) | "$'" (ANSI-C, honours backslash escapes)
    while i < len(lines):
        line = lines[i]
        e, l, k = [], [], []
        rl = []
        pending = []
        j, n = 0, len(line)
        logical = cont + line

        def emit(txt):
            e.append(txt)
            k.append(" " * len(txt) if (stack[-1] == "dq" and txt != '"') else txt)
        while j < n:
            c = line[j]
            if sq:
                if sq == "$'" and c == "\\" and j + 1 < n:
                    l.append(line[j:j + 2]); rl.append((owner, line[j:j + 2])); emit("\x03\x03"); j += 2; continue
                if c == "'":
                    sq = None; emit("\x03")
                else:
                    l.append(c); rl.append((owner, c)); emit("\x03")
                j += 1; continue
            top = stack[-1]
            if c == "\\" and j + 1 < n:
                emit(line[j:j + 2]); j += 2; continue
            if top != "dq":
                if c == "$" and line.startswith("$'", j):
                    owner = _region_owner(logical, cont + line[:j]); sq = "$'"; emit("\x02\x03"); j += 2; continue
                if c == "'":
                    owner = _region_owner(logical, cont + line[:j]); sq = "'"; emit("\x02"); j += 1; continue
                if c == "#" and (j == 0 or line[j - 1] in " \t;&|()"):
                    break
                if c == "<" and line.startswith("<<", j) and not line.startswith("<<<", j):
                    m = RE_HEREDOC.match(line, j)
                    if m:
                        pending.append((m.group(2), bool(m.group(1)), line.startswith("<<-", j),
                                        _region_owner(logical, cont + line[:j])))
                        emit(line[j:m.end()]); j = m.end(); continue
                if c == ")" and top in ("cmd", "par"):
                    stack.pop(); emit(c); j += 1; continue
                if c == "(":
                    stack.append("par"); emit(c); j += 1; continue
                if c == "`":
                    if top == "bq":
                        stack.pop()
                    else:
                        stack.append("bq")
                    emit(c); j += 1; continue
            else:
                if c == "`":
                    stack.append("bq"); emit(c); j += 1; continue
            if c == "$" and line.startswith("$(", j) and not line.startswith("$((", j):
                stack.append("cmd"); emit("$("); j += 2; continue
            if c == '"':
                if top == "dq":
                    stack.pop()
                else:
                    stack.append("dq")
                emit(c); j += 1; continue
            emit(c); j += 1
        exp.append("".join(e)); lit.append("".join(l)); code.append("".join(k))
        if regions is not None:
            regions.append(rl)
        cont = (logical[:-1] + " ") if (not sq and line.endswith("\\") and not line.endswith("\\\\")) else ""
        i += 1
        for word, quoted, dash, howner in pending:
            while i < len(lines):
                body = lines[i]
                if (body.lstrip("\t") if dash else body) == word:
                    exp.append(""); lit.append(""); code.append(""); i += 1
                    if regions is not None:
                        regions.append([])
                    break
                if quoted:
                    exp.append(""); lit.append(body)
                else:
                    exp.append(body); lit.append(body)
                if regions is not None:
                    regions.append([(howner, body)])
                code.append("")  # heredoc bodies hold no assignments of the gate's own shell
                i += 1
    return exp, lit, code


def var_reads(line):
    out = []  # (name, defaultform, indirect)
    for m in re.finditer(r"\$\{(#|!)?(" + NAME + r")(\[[^\]]*\])?(:?[-=+?#%/^,]|\})?", line):
        if m.group(1) == "!":
            # ${!NAME} indirect, ${!NAME[@]} key list, ${!prefix*} name list
            rest = line[m.end(2):m.end(2) + 2]
            if m.group(3) or rest.startswith("*") or rest.startswith("@"):
                continue
            out.append((m.group(2), False, True)); continue
        op = m.group(4) or ""
        out.append((m.group(2), op in (":-", "-", ":=", "="), False))
    for m in re.finditer(r"(?<!\\)\$(" + NAME + r")", line):
        out.append((m.group(1), False, False))
    return out


# ---------------------------------------------------------------------------------------------------------------------
# shell word scanning and the assignment table
# ---------------------------------------------------------------------------------------------------------------------
def _skip_balanced(s, j, o, c):
    """s[j] == o; return the index after the matching c (quote aware); len(s) if unbalanced."""
    depth, n = 0, len(s)
    while j < n:
        ch = s[j]
        if ch == "\\":
            j += 2; continue
        if ch == '"':
            j = _skip_dq(s, j); continue
        if ch == "'":
            k = s.find("'", j + 1); j = n if k < 0 else k + 1; continue
        if ch == o:
            depth += 1
        elif ch == c:
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return n


def _skip_dq(s, j):
    n = len(s); j += 1
    while j < n:
        ch = s[j]
        if ch == "\\":
            j += 2; continue
        if ch == '"':
            return j + 1
        if ch == "$" and s.startswith("$(", j):
            j = _skip_balanced(s, j + 1, "(", ")"); continue
        if ch == "$" and s.startswith("${", j):
            j = _skip_balanced(s, j + 1, "{", "}"); continue
        if ch == "`":
            k = s.find("`", j + 1); j = n if k < 0 else k + 1; continue
        j += 1
    return n


def scan_word(s, i):
    """End index of the shell word starting at s[i] (quote and $()/${} aware; stops at unquoted blank or ; & | < > )."""
    n = len(s); j = i
    while j < n:
        c = s[j]
        if c == "\\":
            j += 2; continue
        if c in " \t;&|<>)":
            break
        if c == '"':
            j = _skip_dq(s, j); continue
        if c == "'":
            k = s.find("'", j + 1); j = n if k < 0 else k + 1; continue
        if c == "$" and s.startswith("$(", j):
            j = _skip_balanced(s, j + 1, "(", ")"); continue
        if c == "$" and s.startswith("${", j):
            j = _skip_balanced(s, j + 1, "{", "}"); continue
        if c == "`":
            k = s.find("`", j + 1); j = n if k < 0 else k + 1; continue
        if c == "(" and j > 0 and s[j - 1] == "=":
            j = _skip_balanced(s, j, "(", ")"); continue
        j += 1
    return j


RE_KW_BEFORE = re.compile(r"(?:^|[\s;&|({])(?:then|do|else|elif|if|while|until|time|!)$")


def _is_cmd_start(code, p):
    """True when a command word may start at code[p]: only blanks (or nothing) between it and line start / a command
    separator / a control keyword."""
    k = p - 1
    while k >= 0 and code[k] in " \t":
        k -= 1
    if k < 0:
        return True
    if code[k] in ";&|({`!)":
        return True
    return bool(RE_KW_BEFORE.search(code[:k + 1]))


RE_ASSIGN_AT = re.compile(r"(" + NAME + r")(?:\[[^\]]*\])?(\+?=)")
RE_KEYWORD = re.compile(r"(?<![\w.-])(local|declare|typeset|readonly|export)(?=\s)")
RE_FOR_IN = re.compile(r"\bfor\s+(" + NAME + r")\s+in\s+([^;]*?)\s*(?:;|$)")
_TERM = ";&|)}#<>"


def assign_table(code_lines, exp_lines):
    """Return (names, values): names = {var: first line of a PERSISTENT assignment}, values = {var: [value words]}.
    Persistent: `NAME=v` in command position that is NOT followed by a command word (a prefix assignment `NAME=1 cmd`
    lasts for that command only), `local NAME[=v]`, `declare|typeset NAME=v` (NAME alone only with -a/-A), `readonly|export
    NAME=v` (a bare `export NAME` / `readonly NAME` / `declare -x NAME` re-exports the AMBIENT value and assigns nothing),
    `for NAME in words`."""
    names, values = {}, {}

    def rec(nm, ln, word=None):
        names.setdefault(nm, ln)
        if word is not None:
            values.setdefault(nm, []).append(word)
    for ln, (code, exp) in enumerate(zip(code_lines, exp_lines), 1):
        if len(code) != len(exp):
            exp = code  # heredoc body lines carry no code
        consumed = set()
        for m in RE_ASSIGN_AT.finditer(code):
            s = m.start()
            if s in consumed or (s > 0 and (code[s - 1].isalnum() or code[s - 1] in "_$")):
                continue
            if not _is_cmd_start(code, s):
                continue
            chain, p = [], s
            while True:
                mm = RE_ASSIGN_AT.match(code, p)
                if not mm:
                    break
                e = scan_word(exp, mm.end())
                chain.append((mm.group(1), exp[mm.end():e]))
                consumed.add(p)
                q = e
                while q < len(code) and code[q] in " \t":
                    q += 1
                if q == e:      # no blank after the word: end of the chain
                    p = e
                    break
                p = q
            q = p
            while q < len(code) and code[q] in " \t":
                q += 1
            # a trailing line-continuation backslash is not a command word
            has_cmd = q < len(code) and code[q] not in _TERM and code[q] != "#" and code[q:].strip() != "\\"
            if not has_cmd:
                for nm, w in chain:
                    rec(nm, ln, w)
            # a prefix assignment (has_cmd) is deliberately NOT recorded
        for km in RE_KEYWORD.finditer(code):
            if not _is_cmd_start(code, km.start()):
                continue
            kw, p, flags = km.group(1), km.end(), ""
            while p < len(code):
                while p < len(code) and code[p] in " \t":
                    p += 1
                if p >= len(code) or code[p] in _TERM:
                    break
                e = scan_word(exp, p)
                if e == p:
                    break
                w = exp[p:e]
                if w.startswith("-") and len(w) > 1:
                    flags += w[1:]
                else:
                    wm = re.match(r"(" + NAME + r")(?:\[[^\]]*\])?(=(.*))?$", w, re.S)
                    if wm:
                        has_val = wm.group(2) is not None
                        if has_val or kw == "local" or (kw in ("declare", "typeset") and ("a" in flags or "A" in flags)):
                            rec(wm.group(1), ln, wm.group(3) if has_val else None)
                p = e
        for m in re.finditer(r"(?<![\w.-])cm_gate_env_set\s+(" + NAME + r")\s+" + NAME + r"\s+", code):
            if not _is_cmd_start(code, m.start()):
                continue
            p = m.end()
            e = scan_word(exp, p)
            if e > p:
                rec(m.group(1), ln, exp[p:e])
        for m in RE_FOR_IN.finditer(code):
            vals = exp[m.start(2):m.end(2)]
            i = 0
            while i < len(vals):
                while i < len(vals) and vals[i] in " \t":
                    i += 1
                if i >= len(vals):
                    break
                e = scan_word(vals, i)
                if e == i:
                    break
                rec(m.group(1), ln, vals[i:e]); i = e
            names.setdefault(m.group(1), ln)
    return names, values


def _first(names, k, ln):
    if k not in names or ln < names[k]:
        names[k] = ln


def assigned_names(code_lines, exp_lines=None):
    if exp_lines is None:
        exp_lines = code_lines
    names, _ = assign_table(code_lines, exp_lines)
    for ln, line in enumerate(code_lines, 1):
        for rx in RE_ASSIGN:
            for m in rx.finditer(line):
                _first(names, m.group(1), ln)
        for m in RE_READCMD.finditer(line):
            toks = re.split(r"[\s]+", re.split(r"[;&|)<>]", line[m.end(1):])[0].strip())
            argopt = set("dnNptuCcO") if m.group(1) == "read" else set("dnOsuC")
            skip = False
            for t in toks:
                if not t:
                    continue
                if skip:
                    skip = False; continue
                if t.startswith("-") and len(t) > 1:
                    if t[-1] in argopt:
                        skip = True
                    continue
                if re.fullmatch(NAME, t):
                    _first(names, t, ln)
        for m in re.finditer(r"\(\(\s*(" + NAME + r")\s*(?:[-+*/%]?=|\+\+|--)", line):
            _first(names, m.group(1), ln)
    return names


# ---------------------------------------------------------------------------------------------------------------------
# source resolution
# ---------------------------------------------------------------------------------------------------------------------
def _pieces(word):
    """Split a shell word into [('lit', text) | ('exp', text)] with quotes removed."""
    out, buf, i, n = [], [], 0, len(word)

    def flush():
        if buf:
            out.append(("lit", "".join(buf))); buf.clear()
    while i < n:
        c = word[i]
        if c == "\\" and i + 1 < n:
            buf.append(word[i + 1]); i += 2; continue
        if c in "\"'":
            i += 1; continue
        if c == "$" and word.startswith("$(", i):
            e = _skip_balanced(word, i + 1, "(", ")"); flush(); out.append(("exp", word[i:e])); i = e; continue
        if c == "$" and word.startswith("${", i):
            e = _skip_balanced(word, i + 1, "{", "}"); flush(); out.append(("exp", word[i:e])); i = e; continue
        if c == "$":
            m = re.compile(NAME).match(word, i + 1)
            if m:
                flush(); out.append(("exp", word[i:m.end()])); i = m.end(); continue
        if c == "`":
            k = word.find("`", i + 1); e = n if k < 0 else k + 1; flush(); out.append(("exp", word[i:e])); i = e; continue
        buf.append(c); i += 1
    flush()
    return out


def _bases(here, root):
    out, d = [], here
    while True:
        out.append(d)
        if os.path.abspath(d) == os.path.abspath(root) or os.path.dirname(d) == d:
            break
        d = os.path.dirname(d)
    if root not in out:
        out.append(root)
    return out


def _inside(p, root):
    return os.path.abspath(p).startswith(os.path.abspath(root) + os.sep)


def _try_tail(tail, here, root, self_path):
    found = set()
    rel = tail.lstrip("/")
    if not rel:
        return found
    for b in _bases(here, root):
        cand = os.path.normpath(os.path.join(b, rel))
        hits = _glob.glob(cand) if any(ch in cand for ch in "*?[") else [cand]
        for h in hits:
            if os.path.isfile(h) and _inside(h, root) and os.path.abspath(h) != os.path.abspath(self_path):
                found.add(os.path.abspath(h))
    return found


def dirs_of_word(word, values, here, root, depth=0):
    """Directories a shell word can denote: `$(cd [--] ARG && pwd)`, `$(dirname X)` (X = this script), `$VAR`/`${VAR}` through
    its assignments, and `<expansion>/rel/dir` (rel tried against the script's directory, its ancestors and the root)."""
    out = set()
    if depth > 6:
        return out
    w = word.strip()
    if w.startswith('"') and w.endswith('"') and len(w) >= 2:
        w = w[1:-1]
    m = re.match(r"\$\(\s*cd\s+(?:--\s+)?(.*?)\s*(?:&&|;)\s*pwd\s*\)$", w, re.S)
    if m:
        return dirs_of_word(m.group(1), values, here, root, depth + 1)
    m = re.match(r"\$\(\s*dirname\s+(?:--\s+)?(.*?)\s*\)$", w, re.S)
    if m:
        arg = m.group(1)
        if re.search(r"BASH_SOURCE|\$0\b|\$\{0[:}]", arg):
            return {here}
        for f in (resolve_word(arg, values, here, root, "", depth + 1) or ()):
            out.add(os.path.dirname(f))
        return out
    pcs = _pieces(w)
    if not pcs:
        return out
    if len(pcs) == 1 and pcs[0][0] == "exp" and pcs[0][1].startswith("$") and not pcs[0][1].startswith("$("):
        t = pcs[0][1]
        inner = t[2:-1] if t.startswith("${") else t[1:]
        mm = re.match(r"(" + NAME + r")(?::?[-=](.*))?$", inner, re.S)
        if mm:
            for v in values.get(mm.group(1), []) + ([mm.group(2)] if mm.group(2) else []):
                out |= dirs_of_word(v, values, here, root, depth + 1)
        return out
    if pcs[-1][0] == "lit":
        rel = pcs[-1][1].lstrip("/")
        for b in _bases(here, root):
            cand = os.path.normpath(os.path.join(b, rel)) if rel else b
            if os.path.isdir(cand) and _inside(cand + os.sep + "x", root):
                out.add(cand)
    return out


def resolve_word(word, values, here, root, self_path, depth=0, seen=None):
    """Files a sourced shell word can name, or None when nothing resolves."""
    seen = set() if seen is None else seen
    if depth > 6:
        return None
    pieces = _pieces(word)
    if not pieces:
        return None
    if all(k == "lit" for k, _ in pieces):
        lit = "".join(t for _, t in pieces)
        if os.path.isabs(lit):
            if _inside(lit, root):
                f = _try_tail(os.path.relpath(lit, root), root, root, self_path)
                return f or None
            return set() if os.path.exists(lit) else None   # an existing literal path outside the repo: external, not censused
        f = _try_tail(lit, here, root, self_path)
        return f or None
    last_k, last_t = pieces[-1]
    if last_k == "lit":
        f = _try_tail(last_t, here, root, self_path)
        if len(pieces) >= 2 and pieces[-2][0] == "exp":
            # the expansion before the literal tail may be a directory variable (`_dm="$(cd "$(dirname ..)/../x" && pwd)"`)
            pre = "".join(t for _, t in pieces[:-1])
            for d in dirs_of_word(pre, values, here, root):
                cand = os.path.normpath(os.path.join(d, last_t.lstrip("/")))
                if os.path.isfile(cand) and _inside(cand, root) and os.path.abspath(cand) != os.path.abspath(self_path):
                    f.add(os.path.abspath(cand))
        return f or None
    if len(pieces) == 1 and last_t.startswith("$") and not last_t.startswith("$("):
        inner = last_t[2:-1] if last_t.startswith("${") else last_t[1:]
        dflt = None
        m = re.match(r"(" + NAME + r")(?::?[-=])(.*)$", inner, re.S)
        vn = inner
        if m:
            vn, dflt = m.group(1), m.group(2)
        elif not re.fullmatch(NAME, inner):
            return None
        out, ok = set(), False
        if vn in seen:
            return None
        seen = seen | {vn}
        for w in values.get(vn, []):
            r = resolve_word(w, values, here, root, self_path, depth + 1, seen)
            if r is not None:
                out |= r; ok = True
        if dflt:
            r = resolve_word(dflt, values, here, root, self_path, depth + 1, seen)
            if r is not None:
                out |= r; ok = True
        return out if ok else None
    return None


def resolve_sources(path, code_lines, exp_lines, root, raw_lines=None):
    """(found, unresolved): files the script sources and the source statements that name nothing resolvable."""
    here = os.path.dirname(os.path.abspath(path))
    _, values = assign_table(code_lines, exp_lines)
    found, unresolved = set(), []

    def one(ln, word):
        r = resolve_word(word, values, here, root, path)
        if r is None:
            unresolved.append((ln, word))
        else:
            found.update(r)
    for ln, (code, exp) in enumerate(zip(code_lines, exp_lines), 1):
        if len(code) != len(exp):
            continue
        for m in RE_SRC_CMD.finditer(code):
            st = m.end()
            while st < len(exp) and exp[st] in " \t":
                st += 1
            e = scan_word(exp, st)
            if exp.startswith("<", st):   # `source <(cat lib)` / `. <file`: never a plain file word
                unresolved.append((ln, "<(process-substitution)"))
            elif e > st:
                w = exp[st:e]
                if w.startswith("<(") or w.startswith("<"):   # `source <(cat lib)`: process substitution, never a file
                    unresolved.append((ln, "<(process-substitution)"))
                else:
                    one(ln, w)
    if raw_lines:
        for ln, line in enumerate(raw_lines, 1):
            # `eval` must be a live command word (comments / string bodies are blanked in `code`); the string is read from raw
            cl = code_lines[ln - 1] if ln - 1 < len(code_lines) else ""
            if len(cl) == len(line):
                for em in re.finditer(r"\beval\b", cl):
                    if RE_SRC_EVAL.match(line, em.start()):
                        unresolved.append((ln, "eval-of-source-string")); break
            for m in RE_SRC_SPLICE.finditer(line):
                one(ln, "$" + m.group(1))
    return sorted(found), unresolved


def closure(files, root, unresolved_out=None):
    """Every file reachable by sourcing from `files` (the census scope: a sourced library runs inside the gate)."""
    seen, todo = set(), [os.path.abspath(f) for f in files]
    while todo:
        f = todo.pop()
        if f in seen or not os.path.isfile(f):
            continue
        seen.add(f)
        try:
            text = open(f, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        exp, _, code = split_code(text)
        found, unres = resolve_sources(f, code, exp, root, text.split("\n"))
        todo.extend(found)
        if unresolved_out is not None:
            for ln, w in unres:
                unresolved_out.append((os.path.relpath(f, root), ln, w))
    return sorted(seen)


def same_line_assigned_first(line, name):
    """`X=$(cmd); X=${X:-0}`: a complete assignment of X in an EARLIER ;/&&/|| segment of the same line runs
    before the read. `X="${X:-d}"` (read inside its own assignment) does not."""
    segs = re.split(r";|&&|\|\|", line)
    first_assign = first_read = None
    for i, sg in enumerate(segs):
        if first_assign is None and (re.search(r"(?:^|[\s(`{!])" + re.escape(name) + r"(?:\[[^\]]*\])?\+?=(?!=)", sg)
                                     or re.search(r"\b(?:read|mapfile|readarray)\b[^$]*\b" + re.escape(name) + r"\b", sg)):
            first_assign = i
        if first_read is None and re.search(r"\$\{?[#]?" + re.escape(name) + r"\b", sg):
            first_read = i
    return first_assign is not None and first_read is not None and first_assign < first_read


def _py_aliases(blob):
    """Names under which python code in `blob` can reach the environment mapping, and aliases of the os module."""
    env_names, mod_names = set(), {"os"}
    for m in RE_PY_FROM.finditer(blob):
        for part in m.group(1).split(","):
            mm = re.match(r"\s*\(?\s*environ(?:\s+as\s+(" + NAME + r"))?\s*\)?\s*$", part)
            if mm:
                env_names.add(mm.group(1) or "environ")
    for m in RE_PY_MODALIAS.finditer(blob):
        mod_names.add(m.group(1))
    for m in RE_PY_ASSIGNALIAS.finditer(blob):
        env_names.add(m.group(1))
    return env_names, mod_names


def census(path, root, _seen=None):
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    regions = []
    exp, lit, code = split_code(text, regions)
    # a region assigned to a variable is disowned only when that variable is expanded, and every expansion is on a command
    # line that provably runs a non-jq interpreter; never expanded, or expanded anywhere else, stays armed
    logical, cont = [], ""
    for e_ in exp:
        logical.append(cont + e_)
        cont = (cont + e_[:-1] + " ") if e_.endswith("\\") and not e_.endswith("\\\\") else ""
    var_lines = {}
    for lg in logical:
        for nm in set(re.findall(r"\$\{?[#!]?([A-Za-z_]\w*)", lg)):
            var_lines.setdefault(nm, []).append(lg)
    nonjq_vars = {nm for nm, lgs in var_lines.items() if all(_runs_nonjq(lg) for lg in lgs)}
    jq_text = "\n".join(lg for lg in logical if RE_JQ_WORD.search(lg))

    def _armed(o):
        if o[0] in ("jq", "other"):
            return True
        if o[0] == "var":
            return o[1] not in nonjq_vars
        if o[0] == "file":   # generated file: armed when it looks like a jq program or a jq command line names it
            return bool(re.search(r"jq|yq", o[1], re.I)) or (o[1] != "" and o[1] in jq_text)
        return False
    jqlit = ["".join(t for o, t in rl if _armed(o)) for rl in regions]
    assigned = assigned_names(code, exp)
    # assignments made by sourced libraries count (their reads are censused as their own units)
    found, _unres = resolve_sources(path, code, exp, root, text.split("\n"))
    for lib in found:
        try:
            lt = open(lib, encoding="utf-8", errors="replace").read()
            le, _, lc = split_code(lt)
            for k, v in assigned_names(lc, le).items():
                assigned.setdefault(k, 0)
        except OSError:
            pass
    rows = {}

    def add(var, kind, ln):
        rows.setdefault((var, kind), ln)
    for ln, line in enumerate(exp, 1):
        for m in RE_GUARDED.finditer(line):
            add(m.group(1), "guarded", ln)
        for m in RE_HDEPS.finditer(line):
            add(m.group(1), "guarded", ln)
        for name, dflt, ind in var_reads(line):
            if ind:
                add(name, "indirect", ln); continue
            if name in SPECIAL or re.fullmatch(r"\d+", name):
                continue
            a = assigned.get(name)
            if a is None:
                add(name, "ambient", ln)
            elif a and a == ln and same_line_assigned_first(line, name):
                continue
            elif a and a >= ln and dflt:
                add(name, "ambient-default", ln)
            elif a and a > ln:
                add(name, "read-before-assign", ln)
    alltext = "\n".join(exp) + "\n" + "\n".join(lit)
    has_jq = re.search(r"\b(?:jq|yq|gojq)\b", alltext) is not None
    env_alias, mod_alias = _py_aliases(alltext)
    rx_pyenv_idx = None
    if env_alias:
        al = "|".join(re.escape(a) for a in sorted(env_alias))
        rx_alias_lit = re.compile(r"(?<![\w.])(?:" + al + r")(?:\.get)?\s*[\[(]\s*['\"](" + NAME + r")['\"]")
        rx_alias_bare = re.compile(r"(?<![\w.])(?:" + al + r")\b(?!\s*(?:[\[(]|\.get\s*\())")
        rx_alias_dyn = re.compile(r"(?<![\w.])(?:" + al + r")(?:\.get)?\s*[\[(]\s*(?!['\"])")
    ma = "|".join(re.escape(a) for a in sorted(mod_alias))
    rx_os_bare = re.compile(r"(?<![\w.])(?:" + ma + r")\.environ\b(?!\s*(?:\[|\.get\s*\(|\.setdefault\s*\())")
    for ln, (e, l) in enumerate(zip(exp, lit), 1):
        for blob in (e, l):
            for rx in RE_ENVAPI:
                for m in rx.finditer(blob):
                    if m.group(1) not in SPECIAL:
                        add(m.group(1), "env-api", ln)
            for rx in RE_ENVAPI_INDIRECT:
                for m in rx.finditer(blob):
                    add(m.group(1), "indirect", ln)
            if has_jq:
                for rx in RE_JQ_ENV:
                    for m in rx.finditer(blob):
                        add(m.group(1), "env-api", ln)
            if has_jq and blob is l:
                # only quoted text that is jq code (see _region_owner); an awk/python program in the same file is not
                for rx in RE_JQ_ENV_DUMP:
                    if rx.search(jqlit[ln - 1]):
                        add("jq-env", "indirect", ln)
            if rx_os_bare.search(blob):
                add("os.environ", "indirect", ln)
            if env_alias:
                for m in rx_alias_lit.finditer(blob):
                    add(m.group(1), "env-api", ln)
                if rx_alias_bare.search(blob) or rx_alias_dyn.search(blob):
                    add("os.environ", "indirect", ln)
            if re.search(r"\bprocess\.env\b(?!\s*(?:\.\s*[A-Za-z_]|\[\s*['\"]))", blob):
                add("process.env", "indirect", ln)
            for rx in RE_PERL_DUMP:
                if rx.search(blob):
                    add("%ENV", "indirect", ln)
            if RE_PROC_ENVIRON.search(blob):
                add("<proc-environ>", "indirect", ln)
        # whole-environment dumps and eval (command position, shell text; sq text is blanked in e, so also test `l`)
        if RE_ENV_DUMP_ENV.search(e):
            add("<env-dump>", "indirect", ln)
            for m in RE_ENV_GREP.finditer(e + " " + l):
                if m.group(1) not in SPECIAL:
                    add(m.group(1), "env-api", ln)
        if RE_ENV_DUMP_DECL.search(e):
            add("<declare-dump>", "indirect", ln)
        if RE_PRINTENV_VAR.search(l) or RE_PRINTENV_VAR.search(e):
            add("<printenv-var>", "indirect", ln)
        mv = RE_EVAL.search(e)
        if mv and ("$" in mv.group(1) or "`" in mv.group(1) or "$" in l or "`" in l):
            add("<eval>", "indirect", ln)
    # an env-API read (embedded python/awk) of a variable this file guards through cm_gate_env_set AND re-assigns
    # (export NAME="$guarded") reads the guarded value: covered by the guard, reported as guarded.
    guarded = {v for (v, k) in rows if k == "guarded"}
    for (v, k) in list(rows):
        if k == "env-api" and v in guarded and v in assigned:
            rows.pop((v, k))
    return sorted((v, k, ln) for (v, k), ln in rows.items())


def main(argv):
    root = None
    files = []
    closure_mode = False
    it = iter(argv)
    for a in it:
        if a == "--root":
            root = next(it)
        elif a == "--closure":
            closure_mode = True
        else:
            files.append(a)
    if root is None:
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    unresolved = []
    if closure_mode:
        files = closure(files, root, unresolved)
    for p in files:
        rel = os.path.relpath(p, root)
        for var, kind, ln in census(p, root):
            print(f"{rel}\t{var}\t{kind}\t{ln}")
    if unresolved:
        for rel, ln, w in unresolved:
            print(f"UNRESOLVED-SOURCE {rel}:{ln} {w}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
