import bisect, re, sys

# sigscan: token-level, deny-by-default scan of bash files for the CON-PENDING-INSTALLER-SIGPIPE classes.
#   class a: a here-string (<<<) or here-document (<<, <<-) in code (bash keeps those in a temporary file)
#   class c: a pipeline stage after | or |& that is not known to read all of its input
# A reader is allowed only when it is on the read-all list (with its options checked), a while/until loop
# with no break/return/exit, or a function named with --allow-func. Everything else is reported.
# Usage: python3 -I -c "$prog" [--allow-func a,b] [--pipes] FILE...
# Output: FILE:LINE: CLASS detail | original line      (--pipes: FILE<TAB>LINE<TAB>OP<TAB>READER per pipe)
# Exit: 0 nothing found, 1 findings, 2 a file could not be read or lexed (unterminated quote, heredoc, ...).

SQ, DQ = chr(39), chr(34)
DS = "$" + SQ
META = set("|&;()<> \t\n")
OPS = ["<<<", "<<-", ";;&", "&>>", "<<", "&&", "||", ";;", ";&", "|&", ">>", "<&", ">&", "<>", ">|", "&>", "|", "&", ";", "<", ">"]
REDIR = {"<", ">", ">>", "<<", "<<<", "<<-", "<&", ">&", "&>", "&>>", "<>", ">|"}
STAGE_END = {"|", "|&", ";", "&&", "||", "&", ";;", ";&", ";;&", ")", "("}
CMDPOS_AFTER_OP = {";", "&&", "||", "|", "|&", "&", "(", ")", ";;", ";&", ";;&"}
KW_NEXT_CMD = {"then", "do", "else", "elif", "if", "while", "until", "!", "{", "time"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")
READ_ALL = {"cat", "uniq", "wc", "tr", "cut", "tee", "tail", "base64", "od", "xxd", "sha256sum", "sha1sum",
            "md5sum", "cksum", "jq", "column", "paste", "fold", "rev", "nl"}
AWK_END = re.compile(r"\bEND\s*\{")
AWK_STOP = re.compile(r"\b(exit|nextfile)\b")


class LexError(Exception):
    pass


class Tok:
    __slots__ = ("k", "v", "pos", "end", "cmd", "quoted")

    def __init__(self, k, v, pos, end, cmd=False, quoted=False):
        self.k, self.v, self.pos, self.end, self.cmd, self.quoted = k, v, pos, end, cmd, quoted


class Lexer:
    def __init__(self, text):
        self.s = text
        self.n = len(text)
        self.nl = [i for i, ch in enumerate(text) if ch == "\n"]
        self.findings = []
        self.programs = []
        self.heredocs = []

    def line(self, i):
        return bisect.bisect_left(self.nl, i) + 1

    def find(self, i, cls, detail):
        self.findings.append((self.line(i), cls, detail))

    def cmd_pos(self, toks):
        j = len(toks) - 1
        while j >= 0:
            t = toks[j]
            if t.k == "NL" or t.k == "PAT":
                return True
            if t.k == "OP":
                return t.v in CMDPOS_AFTER_OP
            if t.k == "W":
                if t.cmd and not t.quoted and t.v in KW_NEXT_CMD:
                    return True
                if t.cmd and ASSIGN.match(t.v):
                    return True
                return False
            j -= 1
        return True

    def skip_heredocs(self, i):
        for delim, strip in self.heredocs:
            while True:
                if i >= self.n:
                    raise LexError("unterminated here-document (delimiter %r)" % delim)
                j = self.s.find("\n", i)
                if j < 0:
                    j = self.n
                ln = self.s[i:j]
                i = j + 1
                if (ln.lstrip("\t") if strip else ln) == delim:
                    break
        self.heredocs = []
        return i

    def skip_arith(self, i, depth):
        start = i
        while i < self.n:
            ch = self.s[i]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        raise LexError("unterminated arithmetic at line %d" % self.line(start))

    def read_squote(self, i, out):
        j = self.s.find(SQ, i)
        if j < 0:
            raise LexError("unterminated single quote at line %d" % self.line(i))
        out.append(self.s[i:j])
        return j + 1

    def read_ansic(self, i, out):
        start = i
        while i < self.n:
            ch = self.s[i]
            if ch == "\\":
                out.append(self.s[i:i + 2])
                i += 2
                continue
            if ch == SQ:
                return i + 1
            out.append(ch)
            i += 1
        raise LexError("unterminated ANSI-C quote at line %d" % self.line(start))

    def read_dollar(self, i, out, in_dq):
        s = self.s
        if s.startswith("$((", i):
            out.append("$((...))")
            return self.skip_arith(i + 3, 2)
        if s.startswith("$(", i):
            toks, i = self.lex_code(i + 2, ")")
            self.programs.append(toks)
            out.append("$(...)")
            return i
        if s.startswith("${", i):
            return self.read_param(i + 2, out, in_dq)
        if s.startswith(DS, i) and not in_dq:
            return self.read_ansic(i + 2, out)
        out.append("$")
        return i + 1

    def read_param(self, i, out, in_dq):
        start = i
        depth = 1
        buf = []
        while i < self.n:
            ch = self.s[i]
            if ch == "\\":
                buf.append(self.s[i:i + 2])
                i += 2
                continue
            if ch == SQ and not in_dq:
                i = self.read_squote(i + 1, buf)
                continue
            if ch == DQ:
                i = self.read_dq(i + 1, buf)
                continue
            if ch == "`":
                toks, i = self.lex_code(i + 1, "`")
                self.programs.append(toks)
                continue
            if ch == "$":
                if self.s.startswith("${", i):
                    depth += 1
                    buf.append("${")
                    i += 2
                    continue
                i = self.read_dollar(i, buf, in_dq)
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    out.append("${" + "".join(buf) + "}")
                    return i + 1
            buf.append(ch)
            i += 1
        raise LexError("unterminated ${ at line %d" % self.line(start))

    def read_dq(self, i, out):
        start = i
        while i < self.n:
            ch = self.s[i]
            if ch == "\\":
                nx = self.s[i + 1:i + 2]
                if nx == "\n":
                    i += 2
                    continue
                out.append(nx if nx in "$`\"\\" else "\\" + nx)
                i += 2
                continue
            if ch == DQ:
                return i + 1
            if ch == "`":
                toks, i = self.lex_code(i + 1, "`")
                self.programs.append(toks)
                out.append("`...`")
                continue
            if ch == "$":
                i = self.read_dollar(i, out, True)
                continue
            out.append(ch)
            i += 1
        raise LexError("unterminated double quote at line %d" % self.line(start))

    def read_word(self, i, dbracket=False):
        s = self.s
        start = i
        out = []
        quoted = False
        while i < self.n:
            ch = s[i]
            if dbracket:
                if ch in " \t\n" or (s.startswith("]]", i) and i > start and (i + 2 == self.n or s[i + 2] in META)):
                    break
            elif ch in META:
                if ch in "<>" and s[i + 1:i + 2] == "(":   # <( >( inside a word: still a process substitution
                    toks, i = self.lex_code(i + 2, ")")
                    self.programs.append(toks)
                    out.append("<(...)")
                    continue
                break
            if ch == "\\":
                if s[i + 1:i + 2] == "\n":
                    i += 2
                    continue
                out.append(s[i + 1:i + 2])
                quoted = True
                i += 2
                continue
            if ch == SQ:
                i = self.read_squote(i + 1, out)
                quoted = True
                continue
            if ch == DQ:
                i = self.read_dq(i + 1, out)
                quoted = True
                continue
            if ch == "`":
                toks, i = self.lex_code(i + 1, "`")
                self.programs.append(toks)
                out.append("`...`")
                continue
            if ch == "$":
                if s.startswith(DS, i):
                    quoted = True
                i = self.read_dollar(i, out, False)
                continue
            if not dbracket and ch in "@*+?!" and s[i + 1:i + 2] == "(":   # extglob group: part of the word
                j, depth = i + 2, 1
                while j < self.n and depth:
                    if s[j] == "\\":
                        j += 2
                        continue
                    if s[j] == "(":
                        depth += 1
                    elif s[j] == ")":
                        depth -= 1
                    j += 1
                if depth:
                    raise LexError("unterminated extglob at line %d" % self.line(i))
                out.append(s[i:j])
                i = j
                continue
            out.append(ch)
            i += 1
        return i, Tok("W", "".join(out), start, i, quoted=quoted)

    def read_pattern(self, i):
        s = self.s
        start = i
        if s[i] == "(":
            i += 1
        depth = 0
        while i < self.n:
            ch = s[i]
            if ch == "\\":
                i += 2
                continue
            if ch == SQ:
                i = self.read_squote(i + 1, [])
                continue
            if ch == DQ:
                i = self.read_dq(i + 1, [])
                continue
            if ch == "$":
                i = self.read_dollar(i, [], False)
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                if depth == 0:
                    return i + 1, Tok("PAT", s[start:i], start, i + 1)
                depth -= 1
            i += 1
        raise LexError("unterminated case pattern at line %d" % self.line(start))

    def lex_code(self, i, stop):
        s = self.s
        toks = []
        depth = 0
        cases = []
        while i < self.n:
            ch = s[i]
            if stop == "`" and ch == "`":
                return toks, i + 1
            if ch == "\\" and s[i + 1:i + 2] == "\n":
                i += 2
                continue
            if ch in " \t":
                i += 1
                continue
            if ch == "\n":
                toks.append(Tok("NL", "\n", i, i + 1))
                i += 1
                if self.heredocs:
                    i = self.skip_heredocs(i)
                continue
            if cases and cases[-1] == "pat":
                if s.startswith("esac", i) and (i + 4 == self.n or s[i + 4] in META):
                    toks.append(Tok("W", "esac", i, i + 4, cmd=True))
                    cases.pop()
                    i += 4
                    continue
                if ch == "#":
                    j = s.find("\n", i)
                    i = self.n if j < 0 else j
                    continue
                i, t = self.read_pattern(i)
                toks.append(t)
                cases[-1] = "body"
                continue
            if ch == "#":
                j = s.find("\n", i)
                i = self.n if j < 0 else j
                continue
            if ch == ")":
                if depth == 0 and stop == ")":
                    return toks, i + 1
                depth -= 1
                toks.append(Tok("OP", ")", i, i + 1))
                i += 1
                continue
            if ch == "(":
                if s.startswith("((", i) and self.cmd_pos(toks):
                    j = self.skip_arith(i + 2, 2)
                    toks.append(Tok("W", "((arith))", i, j, cmd=True))
                    i = j
                    continue
                depth += 1
                toks.append(Tok("OP", "(", i, i + 1))
                i += 1
                continue
            if ch in "<>" and s[i + 1:i + 2] == "(":
                j, t = self.read_word(i)
                t.cmd = self.cmd_pos(toks)
                toks.append(t)
                i = j
                continue
            op = next((o for o in OPS if s.startswith(o, i)), None)
            if op:
                if op in (";;", ";&", ";;&") and cases and cases[-1] == "body":
                    cases[-1] = "pat"
                toks.append(Tok("OP", op, i, i + len(op)))
                if op == "<<<":
                    self.find(i, "HERESTR", "here-string <<<")
                i += len(op)
                if op in ("<<", "<<-"):
                    while i < self.n and s[i] in " \t":
                        i += 1
                    j, t = self.read_word(i)
                    if not t.v:
                        raise LexError("here-document without a delimiter at line %d" % self.line(i))
                    self.heredocs.append((t.v, op == "<<-"))
                    self.find(i, "HEREDOC", "here-document %s%s" % (op, t.v))
                    toks.append(t)
                    i = j
                continue
            cp = self.cmd_pos(toks)
            if cp and s.startswith("[[", i) and (i + 2 == self.n or s[i + 2] in " \t\n"):
                toks.append(Tok("W", "[[", i, i + 2, cmd=True))
                i += 2
                start = i
                while True:
                    while i < self.n and s[i] in " \t\n":
                        i += 1
                    if i >= self.n:
                        raise LexError("unterminated [[ at line %d" % self.line(start))
                    if s.startswith("]]", i) and (i + 2 == self.n or s[i + 2] in META):
                        toks.append(Tok("W", "]]", i, i + 2))
                        i += 2
                        break
                    i, t = self.read_word(i, dbracket=True)
                    toks.append(t)
                continue
            i, t = self.read_word(i)
            t.cmd = cp
            if cp and not t.quoted:
                if t.v == "case":
                    cases.append("head")
                elif t.v == "esac" and cases and cases[-1] == "body":
                    cases.pop()
            elif cases and cases[-1] == "head" and t.v == "in" and not t.quoted:
                cases[-1] = "pat"
            toks.append(t)
        if stop is not None:
            raise LexError("unterminated %s" % ("$(...)" if stop == ")" else "`...`"))
        if self.heredocs:
            self.skip_heredocs(i)
        return toks, i


def sed_class(script):
    s = script
    i, n = 0, len(script)
    while i < n:
        ch = s[i]
        if ch in " \t\n;{}!":
            i += 1
            continue
        # address: number, $, /re/, \cREc, ranges, steps
        while i < n and (s[i].isdigit() or s[i] in "$,~+" or s[i] == "/" or s[i] == "\\"):
            if s[i] in "/\\":
                d = s[i] if s[i] == "/" else s[i + 1:i + 2]
                i += 1 if s[i] == "/" else 2
                while i < n and s[i] != d:
                    i += 2 if s[i] == "\\" else 1
                i += 1
                while i < n and s[i] in "IM":
                    i += 1
            else:
                i += 1
        while i < n and s[i] in " \t!":
            i += 1
        if i >= n:
            break
        c = s[i]
        i += 1
        if c in "{}":
            continue
        if c in "qQ":
            return "EARLY"
        if c in "sy":
            if i >= n:
                return "UNKNOWN"
            d = s[i]
            i += 1
            for _ in range(2):
                while i < n and s[i] != d:
                    i += 2 if s[i] == "\\" else 1
                i += 1
            if c == "s":
                while i < n and s[i] in "gpiImMe0123456789":
                    i += 1
                if i < n and s[i] == "w":
                    j = s.find("\n", i)
                    i = n if j < 0 else j
            continue
        if c in ":btTaicrRwW":
            while i < n and s[i] not in "\n;" if c in "btT" else (i < n and s[i] != "\n"):
                i += 1
            continue
        if c in "pPdDnNhHgGx=lzFe":
            continue
        return "UNKNOWN"
    return "ALL"


def awk_class(prog):
    p = prog
    while True:
        m = AWK_END.search(p)
        if not m:
            break
        i, depth, instr = m.end() - 1, 0, False
        while i < len(p):
            ch = p[i]
            if instr:
                if ch == "\\":
                    i += 1
                elif ch == DQ:
                    instr = False
            elif ch == DQ:
                instr = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if i >= len(p):
            return "EARLY?"
        p = p[:m.start()] + p[i + 1:]
    return "EARLY" if AWK_STOP.search(p) else "ALL"


def skip_wrappers(w):
    # w: list of cooked words; returns the index of the command name, or -1 when it cannot be decided
    i = 0
    while i < len(w) and ASSIGN.match(w[i]):
        i += 1
    while i < len(w):
        name = w[i]
        if name in ("command", "builtin", "nohup"):
            i += 1
            while i < len(w) and w[i].startswith("-") and w[i] != "--":
                i += 1
            if i < len(w) and w[i] == "--":
                i += 1
            continue
        if name == "exec":
            i += 1
            while i < len(w) and w[i].startswith("-"):
                i += 2 if w[i] == "-a" else 1
            continue
        if name == "env":
            i += 1
            while i < len(w) and (w[i].startswith("-") or ASSIGN.match(w[i])):
                if w[i] in ("-S", "--split-string") or w[i].startswith("-S"):
                    return -1
                i += 2 if w[i] in ("-u", "-C", "--unset", "--chdir") else 1
            continue
        if name in ("nice", "ionice", "setsid", "stdbuf", "time", "timeout"):
            i += 1
            argful = {"nice": ("-n", "--adjustment"), "ionice": ("-c", "-n", "-t"), "stdbuf": ("-i", "-o", "-e"),
                      "timeout": ("-s", "-k", "--signal", "--kill-after"), "setsid": (), "time": ()}[name]
            while i < len(w) and w[i].startswith("-") and w[i] != "--":
                i += 2 if w[i] in argful else 1
            if i < len(w) and w[i] == "--":
                i += 1
            if name == "timeout":
                i += 1   # the duration
            continue
        return i
    return -1


def grep_class(args):
    cls = "ALL"
    i = 0
    while i < len(args):
        a = args[i]
        i += 1
        if a == "--":
            break
        if a.startswith("--"):
            k = a.split("=", 1)[0]
            if k in ("--quiet", "--silent", "--max-count", "--files-with-matches", "--files-without-match"):
                cls = "EARLY"
            if "=" not in a and k in ("--regexp", "--file", "--max-count", "--after-context", "--before-context",
                                      "--context", "--devices", "--directories", "--label", "--include", "--exclude"):
                i += 1
            continue
        if a.startswith("-") and len(a) > 1:
            for j, ch in enumerate(a[1:]):
                if ch in "qlLm":
                    cls = "EARLY"
                if ch in "efmABCdD":
                    if j == len(a) - 2:
                        i += 1
                    break
    return cls


def stage_class(toks, k, allow):
    while k < len(toks) and toks[k].k == "NL":
        k += 1
    if k >= len(toks):
        return "UNKNOWN", "end of input"
    t = toks[k]
    if t.k == "OP":
        return "UNKNOWN", "compound " + t.v
    if t.k == "W" and not t.quoted and t.v in ("while", "until"):
        depth, j, early = 0, k, False
        while j < len(toks):
            u = toks[j]
            if u.k == "W" and u.cmd and not u.quoted:
                if u.v in ("while", "until", "for", "select"):
                    depth += 1
                elif u.v == "done":
                    depth -= 1
                    if depth == 0:
                        break
                elif u.v in ("break", "return", "exit"):
                    early = True
            j += 1
        return ("EARLY" if early else "ALL"), t.v + "-loop"
    if t.k == "W" and not t.quoted and t.v in ("if", "case", "for", "select", "{", "[[", "((arith))", "!", "function"):
        return "UNKNOWN", "compound " + t.v
    words = []
    j = k
    while j < len(toks):
        u = toks[j]
        if u.k == "NL" or (u.k == "OP" and u.v in STAGE_END):
            break
        if u.k == "OP" and u.v in REDIR:
            if words and words[-1][1].isdigit() and toks[j - 1].end == u.pos:
                words.pop()
            j += 2
            continue
        if u.k == "W":
            words.append((u, u.v))
        j += 1
    w = [x[1] for x in words]
    ci = skip_wrappers(w)
    if ci < 0 or ci >= len(w):
        return "UNKNOWN", " ".join(w) or "(no command)"
    name, args = w[ci], w[ci + 1:]
    if "$" in name or "`" in name:
        return "UNKNOWN", "dynamic command " + name
    if name in ("grep", "egrep", "fgrep", "zgrep", "rg"):
        return grep_class(args), name
    if name == "sed":
        script, i = None, 0
        while i < len(args):
            a = args[i]
            if a in ("-e", "--expression"):
                script = (script or "") + "\n" + (args[i + 1] if i + 1 < len(args) else "")
                i += 2
                continue
            if a in ("-f", "--file") or a.startswith("--file="):
                return "UNKNOWN", "sed -f"
            if a.startswith("-") and len(a) > 1:
                i += 1
                continue
            if script is None:
                script = a
            i += 1
        if script is None:
            return "UNKNOWN", "sed without a script"
        return sed_class(script), name
    if name in ("awk", "gawk", "mawk", "nawk"):
        prog, i = None, 0
        while i < len(args):
            a = args[i]
            if a in ("-F", "-v"):
                i += 2
                continue
            if a == "-f" or a.startswith("--file"):
                return "UNKNOWN", "awk -f"
            if a.startswith("-") and len(a) > 1 and prog is None:
                i += 1
                continue
            if prog is None:
                prog = a
            i += 1
        if prog is None:
            return "UNKNOWN", "awk without a program"
        return awk_class(prog), name
    if name == "sort":
        early = any(a in ("-c", "-C", "--check") or a.startswith("--check=") or (a.startswith("-") and not a.startswith("--") and ("c" in a[1:] or "C" in a[1:])) for a in args)
        return ("EARLY" if early else "ALL"), name
    if name == "xargs":
        early = any(a in ("-E", "-e") or a.startswith("--eof") or (a.startswith("-E") and len(a) > 2) for a in args)
        return ("EARLY" if early else "ALL"), name
    if name in READ_ALL:
        return "ALL", name
    if name in allow:
        return "ALL", name + " (allowed function)"
    if name in ("head", "read", "true", "false", ":", "exit", "return", "dd", "[", "test", "mapfile", "readarray"):
        return "EARLY", name
    return "UNKNOWN", name


def scan(path, allow, pipes_mode, out):
    try:
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
    except OSError as e:
        out.append("%s:0: ERROR cannot read (%s)" % (path, e))
        return 2
    lines = text.split("\n")
    lx = Lexer(text)
    try:
        toks, _ = lx.lex_code(0, None)
    except LexError as e:
        out.append("%s:0: ERROR cannot lex (%s)" % (path, e))
        return 2
    progs = [toks] + lx.programs
    found = []
    for line, cls, detail in lx.findings:
        found.append((line, cls, detail))
    for p in progs:
        for k, t in enumerate(p):
            if t.k == "OP" and t.v in ("|", "|&"):
                cls, what = stage_class(p, k + 1, allow)
                if pipes_mode:
                    out.append("%s\t%d\t%s\t%s\t%s" % (path, lx.line(t.pos), t.v, what, cls))
                if cls != "ALL":
                    found.append((lx.line(t.pos), "EARLY-READER" if cls.startswith("EARLY") else "UNKNOWN-READER",
                                  "%s after %s" % (what, t.v)))
    if pipes_mode:
        return 0
    found.sort()
    for line, cls, detail in found:
        src = lines[line - 1].strip() if 0 < line <= len(lines) else ""
        out.append("%s:%d: %s %s | %s" % (path, line, cls, detail, src))
    return 1 if found else 0


def main(argv):
    allow, pipes_mode, files = set(), False, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--allow-func":
            allow |= set(x for x in argv[i + 1].split(",") if x)
            i += 2
            continue
        if a == "--pipes":
            pipes_mode = True
            i += 1
            continue
        files.append(a)
        i += 1
    rc, out = 0, []
    for f in files:
        rc = max(rc, scan(f, allow, pipes_mode, out))
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return rc


sys.exit(main(sys.argv[1:]))
