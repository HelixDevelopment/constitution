#!/usr/bin/env python3
"""tests/layout/hermetic_lint.py -- WIT-C02 lint (ownership wave 2 review round 2, finding F5).

STATUS: ADVISORY tripwire (review round 3 N5, decision recorded in CON-109). Static detection of what a shell
script executes is not decidable in general; the round-3 review flagged 7 of 15 new violator shapes and missed 8
(`bash < file`, `flock ... bash`, `ionice -c3 bash`, `eval "bash ..."`, a function running `bash "$1"`,
`bash -lc "..."`, `"$(command -v bash)" file`, `chrt -i 0 bash`), plus one known false positive (an
`export HELIX_ACTION_OUT_ROOT=...` on an earlier line is not seen). The BINDING C02 check is the full-suite
runner's per-unit fingerprint of the generated sets and its end-of-run tree identity
(scripts/full_suite/run_full_suite.py gen_fingerprint / quick_ident). New shapes are NOT added per review round
(section 11.4.250); a miss is caught at run time by the fingerprint.

Flags shell tests that run, from the REAL checkout, a script that rewrites the tracked generated command
sets (plugins/helix/commands, plugins/helix/README.md, actions/generated):
  * scripts/generate_agent_prefix_commands.sh, unless the same command sets HELIX_ACTION_OUT_ROOT to a
    non-empty value (an `env -u HELIX_ACTION_OUT_ROOT` or an empty value does not count);
  * scripts/install_action_prefix.sh and scripts/install_cli_agent_plugins.sh, always: both unset the
    variable on purpose (layout test H3), so a test must run them from a throw-away constitution copy.

How it reads a file (stated so its limits are visible): heredoc bodies are skipped; `\\` continuations
are joined; each logical line is split with shlex into commands at ; && || | & ( ) { }; comments start at
a word beginning with `#`. A command is an INVOCATION when its command word (after NAME=VALUE prefixes and
the wrappers env, nice, timeout, nohup, exec, command, time, stdbuf, setsid, xargs, and any shell function of
the file whose body runs "$@" as a command; a wrapper's options are skipped with their values, e.g.
`nice -n 10`, `timeout -s KILL 60`) is the script path, or is bash/sh/dash/zsh/ksh/"$BASH"/"$SHELL" (options
skipped, `-o NAME` with its value; a `-c` string is read as commands) or source/`.` followed by the script
path, or is a variable that the file assigns to such a path. A `$VAR` after the first path segment is
expanded with every value the file assigns to it (so `"$REPO/scripts/$N"` with N=<script> is seen). `xargs`
fed by `echo`/`printf` through a pipe takes its path from that command's words.
Known limit (review round 2, R4): a relative path after `cd "$REPO"` is not flagged.
A path is REAL when it is rooted at a variable that is never assigned in the file (conservative) or at a
variable assigned from the test's own location (dirname, $0, BASH_SOURCE, git rev-parse --show-toplevel,
LAYOUT_SRC_ROOT, GEN_SRC_ROOT) or from another REAL variable. A path rooted at any other assigned variable
(a sandbox or copy) or a relative path is NOT flagged; the runner's per-unit fingerprint of the generated
sets (scripts/full_suite/run_full_suite.py gen_fingerprint) is the runtime check that catches what a
static reading cannot. A file that cannot be split is reported as UNPARSED (fail closed).

A line may carry `# C02-hermetic: <reason>` to exempt itself; every exemption is printed as
`EXEMPT <file>:<line> <reason>`, and the caller compares the set with its own expected list.

Usage: hermetic_lint.py TESTS_DIR -> prints `<relpath>:<line> <kind>` per finding; exit 0 always.
"""
import os
import re
import shlex
import sys

GEN = "generate_agent_prefix_commands.sh"
INSTALLERS = ("install_action_prefix.sh", "install_cli_agent_plugins.sh")
TARGETS = (GEN,) + INSTALLERS
KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "!", "function"}
WRAPPERS = {"env", "nice", "timeout", "nohup", "exec", "command", "time", "stdbuf", "setsid", "xargs"}
# options of a wrapper that take the NEXT word as their value (an attached value, -n10 or --x=v, is one word)
WRAP_VALUE_OPTS = {"nice": {"-n", "--adjustment"}, "timeout": {"-s", "--signal", "-k", "--kill-after"},
                   "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
                   "stdbuf": {"-i", "-o", "-e"}, "time": {"-f", "--format", "-o", "--output"},
                   "xargs": {"-n", "-I", "-P", "-d", "-a", "-L", "-s", "-E", "--max-args", "--max-procs",
                             "--delimiter", "--arg-file"}}
SHELLS = {"bash", "sh", "dash", "zsh", "ksh"}
SHELL_VARS = {"$BASH", "${BASH}", "$SHELL", "${SHELL}"}
SOURCERS = {"source", "."}
SHELL_VALUE_OPTS = {"-o", "+o", "-O", "+O"}
FUNC_DEF = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\)\s*\{?(.*)$")
RUNS_ARGS = re.compile(r"(?:^|[;{&|(]\s*|\bthen\s+|\bdo\s+|\bexec\s+|\bcommand\s+)\"?\$(?:@|\{@\})\"?(?:\s|;|$|\})")
SEPS = {";", "&&", "||", "|", "&", "(", ")", "{", "}", ";;", "|&"}
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
REAL_SRC = re.compile(r"dirname|\$0\b|BASH_SOURCE|show-toplevel|LAYOUT_SRC_ROOT|GEN_SRC_ROOT")
VAR_HEAD = re.compile(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")
QUOTED = re.compile(r"'[^']*'|\"(?:[^\"\\\\]|\\\\.)*\"")
EXEMPT = re.compile(r"#\s*C02-hermetic:\s*(\S.*)$")


def logical_lines(text):
    """(first line number, joined text) per logical line, heredoc bodies dropped."""
    out, buf, start, term = [], "", 0, None
    for n, raw in enumerate(text.split("\n"), 1):
        if term is not None:
            if raw.strip() == term:
                term = None
            continue
        if not buf:
            start = n
        if raw.endswith("\\") and not raw.lstrip().startswith("#"):  # RULE:C02-lint-continuation
            buf += raw[:-1] + " "
            continue
        buf += raw
        m = HEREDOC.search(QUOTED.sub("", buf))  # RULE:C02-lint-heredoc-unquoted
        if m:
            term = m.group(2)
        out.append((start, buf))
        buf = ""
    if buf:
        out.append((start, buf))
    return out


def split(line, seps=None):
    """Commands of a logical line. When SEPS is a list, the separator that FOLLOWS each command is appended
    to it (None after the last), so a pipe between two commands can be seen."""
    lx = shlex.shlex(line, posix=True, punctuation_chars=";&|(){}")
    lx.commenters = ""
    lx.whitespace_split = True
    toks = list(lx)
    cmds, cur = [], []
    for t in toks:
        if t.startswith("#"):
            break
        if t in SEPS or (t and all(ch in ";&|(){}" for ch in t)):  # RULE:C02-lint-punct-sep
            if cur:
                cmds.append(cur)
                if seps is not None:
                    seps.append(t)
            cur = []
        else:
            cur.append(t)
    if cur:
        cmds.append(cur)
        if seps is not None:
            seps.append(None)
    return cmds


RAW_ASSIGN = re.compile(r"(?:^|[\s;&|(])(?:local\s+|export\s+|readonly\s+|declare\s+(?:-\w+\s+)*)?([A-Za-z_][A-Za-z0-9_]*)=")
REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")


def raw_assignments(line):
    """(name, raw value) for every NAME=value in a logical line; the value runs to the first space or
    ; & | ) outside quotes and $( ) nesting (so "$(cd "$(dirname "$0")/.." && pwd)" is one value)."""
    out = []
    for m in RAW_ASSIGN.finditer(line):
        i, depth, q = m.end(), 0, None
        while i < len(line):
            ch = line[i]
            if q:
                if ch == "\\" and q == '"':
                    i += 2
                    continue
                if ch == q:
                    q = None
                elif q == '"' and line.startswith("$(", i):
                    depth += 1
                    i += 2
                    continue
                elif q == '"' and ch == ")" and depth:
                    depth -= 1
            else:
                if ch in "'\"":
                    q = ch
                elif line.startswith("$(", i):
                    depth += 1
                    i += 2
                    continue
                elif ch == ")" and depth:
                    depth -= 1
                elif depth == 0 and (ch.isspace() or ch in ";&|)"):
                    break
            i += 1
        out.append((m.group(1), line[m.end():i]))
    return out


def head_var(word):
    m = VAR_HEAD.match(word)
    return m.group(1) if m else None


def scan(path):
    text = open(path, errors="replace").read()
    lines = logical_lines(text)
    assigned = {}  # var -> list of values (shlex words, used for held paths)
    raw = {}  # var -> list of raw values (used to decide REAL)
    parsed = []
    unparsed = []
    funcs = set()  # shell functions of this file that run their arguments as a command ("$@")
    infunc = None
    for n, line in lines:
        fm = FUNC_DEF.match(line)  # RULE:C02-lint-func-wrapper
        if fm and line.rstrip().endswith("}") and RUNS_ARGS.search(fm.group(2).strip()):
            funcs.add(fm.group(1))
        elif fm and not line.rstrip().endswith("}"):
            infunc = fm.group(1)
        elif infunc and line.strip() == "}":
            infunc = None
        elif infunc and RUNS_ARGS.search(line.strip()):
            funcs.add(infunc)
        seps = []
        try:
            cmds = split(line, seps)
        except ValueError:
            # an unbalanced quote that spans lines: only a problem when it names a target
            if any(t in line for t in TARGETS):
                unparsed.append(n)
            continue
        parsed.append((n, line, cmds, seps))
        for name, val in raw_assignments(line):  # RULE:C02-lint-raw-assign
            raw.setdefault(name, []).append(val)
        for c in cmds:
            if len(c) >= 2 and c[0] == "for":  # RULE:C02-lint-for-var
                vals = c[3:] if len(c) > 3 and c[2] == "in" else ["$@"]
                assigned.setdefault(c[1], []).extend(vals)
                raw.setdefault(c[1], []).extend(vals)
            for w in c:
                for tok in ([w[len("local "):]] if w.startswith("local ") else [w]):
                    m = ASSIGN.match(tok)
                    if m:
                        assigned.setdefault(m.group(1), []).append(m.group(2))
    real = set()
    changed = True
    while changed:  # RULE:C02-lint-real-closure
        changed = False
        for v, vals in raw.items():
            if v in real:
                continue
            if any(REAL_SRC.search(x) or any(r in real for r in REF.findall(x)) for x in vals):
                real.add(v)
                changed = True

    def is_real(p):
        v = head_var(p)
        if v is None:
            return False  # relative or literal path: not provably the real tree
        return v in real or (v not in assigned and v not in raw)  # RULE:C02-lint-unassigned-is-real

    held = {v: vals for v, vals in assigned.items() if any(any(t in x for t in TARGETS) for x in vals)}

    def expand_tail(p):
        """P plus every variant with a non-head $VAR / ${VAR} replaced by a value the file assigns to it."""
        out = [p]
        for name in REF.findall(p)[1:] if head_var(p) else REF.findall(p):  # RULE:C02-lint-tail-var
            nxt = []
            for q in out:
                for val in assigned.get(name, []):
                    if "$" not in val:
                        nxt.append(q.replace("${%s}" % name, val).replace("$" + name, val))
            out += nxt[:32]
        return out
    finds, exempt = [], []
    for n, line, cmds0, seps0 in parsed:
        em = EXEMPT.search(line)
        todo = list(zip(cmds0, [None] + cmds0[:-1], [None] + seps0[:-1]))
        while todo:
            c, prev, sep = todo.pop(0)
            env = {}
            i = 0
            stdin_paths = []
            while i < len(c):
                m = ASSIGN.match(c[i])
                if m:
                    env[m.group(1)] = m.group(2)
                    i += 1
                    continue
                w = c[i]
                if w in KEYWORDS:  # RULE:C02-lint-keyword
                    i += 1
                    continue
                if w in WRAPPERS or w in funcs:
                    if w == "xargs" and sep == "|" and prev and prev[0] in ("echo", "printf"):  # RULE:C02-lint-xargs
                        stdin_paths = [x for x in prev[1:] if not x.startswith("-")]
                    vopts = WRAP_VALUE_OPTS.get(w, set())
                    i += 1
                    while i < len(c) and (c[i].startswith("-") or ASSIGN.match(c[i]) or
                                          (w == "timeout" and re.match(r"^[0-9.]+[smhd]?$", c[i]))):
                        if c[i] in ("-u", "--unset") and w == "env" and i + 1 < len(c):  # an unset never redirects
                            env.pop(c[i + 1], None)
                            i += 2
                            continue
                        m = ASSIGN.match(c[i])
                        if m:
                            env[m.group(1)] = m.group(2)
                        if c[i] in vopts:  # RULE:C02-lint-wrapper-opt-value
                            i += 1
                        i += 1
                        if w == "timeout" and i < len(c) and re.match(r"^[0-9.]+[smhd]?$", c[i]):
                            i += 1  # the DURATION after timeout's options
                            break
                    continue
                break
            if i >= len(c):
                continue
            word = c[i]
            if os.path.basename(word) in SHELLS or word in SHELL_VARS or word in SOURCERS:  # RULE:C02-lint-shell-words
                j = i + 1
                while word not in SOURCERS and j < len(c) and (c[j].startswith("-") or c[j].startswith("+")):
                    if c[j] == "-c" and j + 1 < len(c):  # RULE:C02-lint-dash-c
                        try:
                            todo.extend((x, None, None) for x in split(c[j + 1]))
                        except ValueError:
                            pass
                        j = len(c)
                        break
                    j += 2 if c[j] in SHELL_VALUE_OPTS else 1  # RULE:C02-lint-shell-opt-value
                if j >= len(c):
                    if not stdin_paths:
                        continue
                    word = None
                else:
                    word = c[j]
            if word is None:
                paths = stdin_paths
            else:
                v = head_var(word)
                paths = [word]
                if v in held and word in ("$" + v, "${%s}" % v):  # RULE:C02-lint-held-var
                    paths = held[v]
            paths = [x for p_ in paths for x in expand_tail(p_)]
            for p in paths:
                target = next((t for t in TARGETS if p.endswith(t)), None)
                if target is None or not is_real(p):
                    continue
                if target == GEN and env.get("HELIX_ACTION_OUT_ROOT", "") != "":  # RULE:C02-lint-nonempty-redirect
                    continue
                kind = "generator-without-redirect" if target == GEN else "installer-on-real-tree"
                if em:
                    exempt.append((n, em.group(1).strip()))
                else:
                    finds.append((n, kind))
    return finds, exempt, unparsed


def main():
    root = sys.argv[1]
    for d, _, fs in sorted(os.walk(root)):
        for f in sorted(fs):
            if not f.endswith(".sh"):
                continue
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root)
            finds, exempt, unparsed = scan(p)
            for n, k in sorted(set(finds)):
                print("%s:%d %s" % (rel, n, k))
            for n in unparsed:
                print("%s:%d UNPARSED" % (rel, n))
            for n, r in sorted(set(exempt)):
                print("EXEMPT %s:%d %s" % (rel, n, r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
