#!/usr/bin/env python3
"""scripts/full_suite/run_full_suite.py -- engine of the section 11.4.40 full-suite runner.

Invoked through scripts/run_full_suite.sh (python3 -I -B). Full contract: the header of that
wrapper and docs/guides/full_suite_runner_guide.md. This one file holds:

* the SHELL MODEL (lexer, parser, abstract interpreter) that decides, from the executable code of a
  run_all / driver script, which test files it invokes (manifest membership is proved by structure,
  never by a name in a comment, an echo string or a here-document);
* the CENSUS (every test-like file, with a control-needle self-check), the MANIFEST checks, the
  PLAN, unit EXECUTION (clean env, own session, capped streamed log, token reaping), the summary
  VERDICT PARSER, the hash-chained results.jsonl and the RESULT labels.

Shell model notes:
Used by run_full_suite.py to decide manifest membership BY STRUCTURE (N3 of review round 2): a test
counts as a member of an entry only when the entry's executable code invokes it. A name that appears
only in a comment, an echo / printf string or a here-document body is not an invocation.

The model lexes and parses a bash subset (words with quoting, $VAR / ${VAR...} / $(...) / `...` /
<(...), arrays NAME=(...) / NAME+=(...), redirections, here-documents, ; & && || | ( ) { },
if / elif / else / fi, for / in / do / done, while / until, case / esac, function definitions) and
then INTERPRETS it abstractly with the given positional arguments:

* variables hold candidate values; an assignment under an unknown condition adds a candidate;
* `[ ... ]` / `test` with = == != -eq -ne -n -z on known values decide && || if; else unknown;
* for loops iterate literal words, globs (expanded against the files on disk under the root) and
  "${ARR[@]}"; case arms match with fnmatch when the subject is known (continue / break honoured);
* $(cd X && pwd), $(dirname X), $(basename X [suffix]) are evaluated; other substitutions run
  (their invocations count) but give an unknown value;
* a command whose word (after nice / ionice / timeout / env / exec / command / time / setsid / !
  and NAME=value prefixes, and after a call through a shell function that runs "$@") is bash / sh /
  python3 / python (or a variable whose candidates are such words) invokes its first non-option
  operand; a command word that is itself a file under the root is a direct invocation; `.` / source
  records the sourced file and interprets it (so functions it defines are known).

Every invocation is recorded as `definite` (on a path whose conditions are all known true) or
`conditional`. Anything the lexer / parser cannot handle (unterminated quote, parenthesis or
here-document, an unexpected keyword) raises ShParseError: the caller fails closed.
Honest limits: dynamic names built in ways not listed above (eval, indirect expansion, names read
from files) give unknown paths and are not counted as invocations; loops run their body once per
known item, a while / until body once as conditional.
"""
import fnmatch
import glob
import os
import re



class ShParseError(Exception):
    pass


def _split_assign(segs):
    """(name, append, value segments) when the word is NAME=... / NAME+=... by its unquoted literal
    prefix; else None."""
    buf = ""
    for i, sg in enumerate(segs):
        if sg[0] != "lit" or sg[2]:
            return None
        j = sg[1].find("=")
        if j < 0:
            buf += sg[1]
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*\+?$", buf):
                return None
            continue
        head = buf + sg[1][:j]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)(\+?)$", head)
        if not m:
            return None
        rest = ([("lit", sg[1][j + 1:], False)] if sg[1][j + 1:] else []) + list(segs[i + 1:])
        return m.group(1), bool(m.group(2)), (rest or [("lit", "", False)])
    return None


class _Stop(Exception):
    def __init__(self, kind, definite):
        Exception.__init__(self, kind)
        self.kind = kind          # exit | return | continue | break
        self.definite = definite


NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(\+?)=")
KEYWORDS = {"if", "then", "elif", "else", "fi", "for", "in", "do", "done", "while", "until", "case", "esac",
            "function", "{", "}", "!"}
OPS2 = {"&&", "||", ";;", ";&", "|&"}
SH_INTERP = {"bash", "sh", "dash", "/bin/bash", "/usr/bin/bash", "/bin/sh", "/usr/bin/sh", "/bin/dash"}
PY_INTERP = {"python3", "python", "/usr/bin/python3", "/usr/bin/python"}
ENV_KNOWN = {"HOME", "TMPDIR", "PATH", "PWD", "OLDPWD", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TERM",
             "TZ", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "FULL_SUITE_UNIT_TOKEN",
             "RANDOM", "SECONDS", "BASHPID", "PPID", "UID", "EUID", "HOSTNAME", "IFS", "OPTARG", "OPTIND",
             "GOCACHE", "GOMODCACHE", "GOFLAGS", "GOPROXY", "GOTOOLCHAIN", "GOTELEMETRY", "REPLY"}
MAXV = 64


# ----------------------------------------------------------------------------- lexer
def _match_close(s, i, opener, closer):
    """s[i] is just after `opener`; return the index of the matching closer (quote / escape / comment aware)."""
    depth, n = 1, len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            if j < 0:
                raise ShParseError("unterminated single quote")
            i = j + 1
            continue
        if c == '"':
            i = _skip_dq(s, i + 1)
            continue
        if c == "`":
            j = s.find("`", i + 1)
            if j < 0:
                raise ShParseError("unterminated backtick")
            i = j + 1
            continue
        if c == "#" and (i == 0 or s[i - 1] in " \t\n;&|("):
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "$" and i + 1 < n and s[i + 1] in "({":
            i = _match_close(s, i + 2, s[i + 1], ")" if s[i + 1] == "(" else "}") + 1
            continue
        if c == opener and opener != closer:
            depth += 1
        elif c == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ShParseError("unterminated %s" % opener)


def _skip_dq(s, i):
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
        elif c == '"':
            return i + 1
        elif c == "$" and i + 1 < n and s[i + 1] in "({":
            i = _match_close(s, i + 2, s[i + 1], ")" if s[i + 1] == "(" else "}") + 1
        elif c == "`":
            j = s.find("`", i + 1)
            if j < 0:
                raise ShParseError("unterminated backtick")
            i = j + 1
        else:
            i += 1
    raise ShParseError("unterminated double quote")


def _expansion(s, i, quoted):
    """s[i] == '$'; return (segment, next index)."""
    n = len(s)
    if i + 1 >= n:
        return ("lit", "$", quoted), i + 1
    c = s[i + 1]
    if s.startswith("$((", i):
        j = _match_close(s, i + 2, "(", ")")
        return ("lit", "0", True), j + 1
    if c == "(":
        j = _match_close(s, i + 2, "(", ")")
        return ("cmd", s[i + 2:j], quoted), j + 1
    if c == "{":
        j = _match_close(s, i + 2, "{", "}")
        return ("param", s[i + 2:j], quoted), j + 1
    m = re.match(r"[A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-]", s[i + 1:])
    if m:
        return ("param", m.group(0), quoted), i + 1 + len(m.group(0))
    return ("lit", "$", quoted), i + 1


def lex(s):
    """Return tokens: ("W", segs) | ("OP", op) | ("ARR", name, append, [segs...]) | ("PROC", text)."""
    toks, cur, i, n = [], None, 0, len(s)
    heredocs = []
    skipnext = [False]

    def flush():
        nonlocal cur
        if cur is not None:
            if skipnext[0]:
                skipnext[0] = False
            else:
                toks.append(("W", cur))
            cur = None

    def add(seg):
        nonlocal cur
        if cur is None:
            cur = []
        cur.append(seg)

    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            if s[i + 1] == "\n":
                i += 2
                continue
            add(("lit", s[i + 1], True))
            i += 2
            continue
        if c in " \t\r":
            flush()
            i += 1
            continue
        if c == "\n":
            flush()
            toks.append(("OP", "\n"))
            i += 1
            for delim, strip in heredocs:
                while True:
                    if i >= n:
                        raise ShParseError("unterminated here-document (delimiter %r)" % delim)
                    j = s.find("\n", i)
                    line = s[i:] if j < 0 else s[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
            heredocs = []
            continue
        if c == "#" and cur is None:
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "(" and cur is not None and all(sg[0] == "lit" and not sg[2] for sg in cur):
            wtxt = "".join(sg[1] for sg in cur)
            m = ASSIGN.match(wtxt)
            if m and wtxt == m.group(0):
                j = _match_close(s, i + 1, "(", ")")
                elems = [t[1] for t in lex(s[i + 1:j]) if t[0] == "W"]
                cur = None
                toks.append(("ARR", m.group(1), m.group(2) == "+", elems))
                i = j + 1
                continue
        if c in ";&|()":
            if c == "&" and s.startswith("&>", i):
                flush()
                i += 2 if not s.startswith("&>>", i) else 3
                skipnext[0] = True
                continue
            flush()
            two = s[i:i + 2]
            if two in OPS2:
                toks.append(("OP", two))
                i += 2
            else:
                toks.append(("OP", c))
                i += 1
            continue
        if c in "<>":
            if cur is not None and all(sg[0] == "lit" and not sg[2] and sg[1].isdigit() for sg in cur):
                cur = None
            flush()
            if s.startswith("<(", i) or s.startswith(">(", i):
                j = _match_close(s, i + 2, "(", ")")
                toks.append(("PROC", s[i + 2:j]))
                skipnext[0] = False  # the process substitution is the target of `< <(...)`
                i = j + 1
                continue
            if s.startswith("<<<", i):
                i += 3
                skipnext[0] = True
                continue
            if s.startswith("<<", i):
                strip = s.startswith("<<-", i)
                i += 3 if strip else 2
                while i < n and s[i] in " \t":
                    i += 1
                m = re.match(r"""(['"]?)([A-Za-z0-9_.\-]+)\1""", s[i:])
                if not m:
                    raise ShParseError("unparseable here-document delimiter")
                heredocs.append((m.group(2), strip))
                i += len(m.group(0))
                continue
            j = i
            while j < n and s[j] in "<>":
                j += 1
            if j < n and s[j] == "&":
                j += 1
                while j < n and (s[j].isdigit() or s[j] == "-"):
                    j += 1
                i = j
                continue
            i = j
            skipnext[0] = True
            continue
        if c == "'":
            j = s.find("'", i + 1)
            if j < 0:
                raise ShParseError("unterminated single quote")
            add(("lit", s[i + 1:j], True))
            i = j + 1
            continue
        if c == '"':
            j = _skip_dq(s, i + 1)
            inner, k = s[i + 1:j - 1], 0
            if inner == "":
                add(("lit", "", True))
            buf = ""
            while k < len(inner):
                d = inner[k]
                if d == "\\" and k + 1 < len(inner) and inner[k + 1] in '$`"\\\n':
                    buf += inner[k + 1]
                    k += 2
                elif d == "$":
                    if buf:
                        add(("lit", buf, True))
                        buf = ""
                    seg, k = _expansion(inner, k, True)
                    add(seg)
                elif d == "`":
                    e = inner.find("`", k + 1)
                    if buf:
                        add(("lit", buf, True))
                        buf = ""
                    add(("cmd", inner[k + 1:e], True))
                    k = e + 1
                else:
                    buf += d
                    k += 1
            if buf:
                add(("lit", buf, True))
            i = j
            continue
        if c == "$":
            seg, i = _expansion(s, i, False)
            add(seg)
            continue
        if c == "`":
            j = s.find("`", i + 1)
            if j < 0:
                raise ShParseError("unterminated backtick")
            add(("cmd", s[i + 1:j], False))
            i = j + 1
            continue
        add(("lit", c, False))
        i += 1
    flush()
    if heredocs:
        raise ShParseError("unterminated here-document (delimiter %r)" % heredocs[0][0])
    return toks


def lit_text(segs):
    """The word's text if it is purely literal, else None."""
    if all(sg[0] == "lit" for sg in segs):
        return "".join(sg[1] for sg in segs)
    return None


# ----------------------------------------------------------------------------- parser
class P:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def word_is(self, tok, *vals):
        return tok is not None and tok[0] == "W" and lit_text(tok[1]) in vals and \
            all(sg[0] == "lit" and not sg[2] for sg in tok[1])

    def skip_nl(self):
        while self.peek() is not None and self.peek()[0] == "OP" and self.peek()[1] in ("\n", ";"):
            self.i += 1

    def expect_word(self, *vals):
        self.skip_nl()
        tok = self.peek()
        if not self.word_is(tok, *vals):
            raise ShParseError("expected %s, got %r" % ("/".join(vals), tok))
        self.i += 1

    def parse_list(self, stops):
        items = []
        while True:
            self.skip_nl()
            tok = self.peek()
            if tok is None:
                if stops:
                    raise ShParseError("unexpected end of script (wanted %s)" % "/".join(sorted(stops)))
                return items
            if tok[0] == "W" and self.word_is(tok, *stops):
                return items
            if tok[0] == "OP" and tok[1] in stops:
                return items
            if tok[0] == "OP" and tok[1] in (")", ";;", ";&") and tok[1] not in stops:
                raise ShParseError("unexpected %r" % tok[1])
            items.append(self.parse_andor(stops))
            tok = self.peek()
            if tok is not None and tok[0] == "OP" and tok[1] in (";", "\n", "&"):
                self.i += 1

    def parse_andor(self, stops):
        parts = [(None, self.parse_pipeline(stops))]
        while True:
            tok = self.peek()
            if tok is not None and tok[0] == "OP" and tok[1] in ("&&", "||"):
                self.i += 1
                while self.peek() is not None and self.peek() == ("OP", "\n"):
                    self.i += 1
                parts.append((tok[1], self.parse_pipeline(stops)))
            else:
                return parts

    def parse_pipeline(self, stops):
        neg = False
        if self.word_is(self.peek(), "!"):
            self.i += 1
            neg = True
        cmds = [self.parse_command(stops)]
        while self.peek() is not None and self.peek()[0] == "OP" and self.peek()[1] in ("|", "|&"):
            self.i += 1
            while self.peek() == ("OP", "\n"):
                self.i += 1
            cmds.append(self.parse_command(stops))
        return ("pipe", neg, cmds)

    def trailing(self):
        """redirection-only tail and PROC tokens after a compound command (procsubs run)."""
        procs = []
        while self.peek() is not None and self.peek()[0] == "PROC":
            procs.append(self.peek()[1])
            self.i += 1
        return procs

    def parse_command(self, stops):
        tok = self.peek()
        if tok is None:
            raise ShParseError("missing command")
        if tok[0] == "OP" and tok[1] == "(":
            self.i += 1
            body = self.parse_list({")"})
            self.i += 1
            return ("sub", body, self.trailing())
        if self.word_is(tok, "{"):
            self.i += 1
            body = self.parse_list({"}"})
            self.i += 1
            return ("group", body, self.trailing())
        if self.word_is(tok, "if"):
            self.i += 1
            clauses, other = [], None
            cond = self.parse_list({"then"})
            self.expect_word("then")
            body = self.parse_list({"elif", "else", "fi"})
            clauses.append((cond, body))
            while True:
                t = self.peek()
                if self.word_is(t, "elif"):
                    self.i += 1
                    c = self.parse_list({"then"})
                    self.expect_word("then")
                    clauses.append((c, self.parse_list({"elif", "else", "fi"})))
                elif self.word_is(t, "else"):
                    self.i += 1
                    other = self.parse_list({"fi"})
                else:
                    break
            self.expect_word("fi")
            return ("if", clauses, other, self.trailing())
        if self.word_is(tok, "for"):
            self.i += 1
            if self.peek() == ("OP", "("):
                depth = 0
                while True:
                    t = self.peek()
                    if t is None:
                        raise ShParseError("unterminated arithmetic for")
                    self.i += 1
                    if t == ("OP", "("):
                        depth += 1
                    elif t == ("OP", ")"):
                        depth -= 1
                        if depth == 0:
                            break
                self.expect_word("do")
                body = self.parse_list({"done"})
                self.i += 1
                return ("afor", body, self.trailing())
            v = self.peek()
            if v is None or v[0] != "W" or not NAME.match(lit_text(v[1]) or ""):
                raise ShParseError("bad for variable")
            var = lit_text(v[1])
            self.i += 1
            items = None
            while self.peek() == ("OP", "\n"):
                self.i += 1
            if self.word_is(self.peek(), "in"):
                self.i += 1
                items = []
                while self.peek() is not None and self.peek()[0] == "W" and not self.word_is(self.peek(), "do"):
                    items.append(self.peek()[1])
                    self.i += 1
            self.expect_word("do")
            body = self.parse_list({"done"})
            self.i += 1
            return ("for", var, items, body, self.trailing())
        if self.word_is(tok, "while", "until"):
            self.i += 1
            cond = self.parse_list({"do"})
            self.expect_word("do")
            body = self.parse_list({"done"})
            self.i += 1
            return ("while", cond, body, self.trailing())
        if self.word_is(tok, "case"):
            self.i += 1
            subj = self.peek()
            if subj is None or subj[0] != "W":
                raise ShParseError("bad case subject")
            self.i += 1
            self.expect_word("in")
            arms = []
            while True:
                self.skip_nl()
                t = self.peek()
                if self.word_is(t, "esac"):
                    self.i += 1
                    break
                if t is not None and t[0] == "OP" and t[1] == "(":
                    self.i += 1
                pats = []
                while True:
                    t = self.peek()
                    if t is None or t[0] != "W":
                        raise ShParseError("bad case pattern")
                    pats.append(t[1])
                    self.i += 1
                    t = self.peek()
                    if t == ("OP", "|"):
                        self.i += 1
                        continue
                    if t == ("OP", ")"):
                        self.i += 1
                        break
                    raise ShParseError("bad case arm")
                body = self.parse_list({";;", ";&", "esac"})
                if self.peek() is not None and self.peek()[0] == "OP" and self.peek()[1] in (";;", ";&"):
                    self.i += 1
                arms.append((pats, body))
            return ("case", subj[1], arms, self.trailing())
        if self.word_is(tok, "function"):
            self.i += 1
            nm = lit_text(self.peek()[1]) if self.peek() and self.peek()[0] == "W" else None
            if not nm:
                raise ShParseError("bad function name")
            self.i += 1
            if self.peek() == ("OP", "("):
                self.i += 2
            while self.peek() == ("OP", "\n"):
                self.i += 1
            return ("func", nm, self.parse_command(stops))
        if tok[0] == "W" and self.i + 2 < len(self.t) and self.t[self.i + 1] == ("OP", "(") and \
                self.t[self.i + 2] == ("OP", ")") and NAME.match(lit_text(tok[1]) or "."):
            self.i += 3
            while self.peek() == ("OP", "\n"):
                self.i += 1
            return ("func", lit_text(tok[1]), self.parse_command(stops))
        words, arrs, procs = [], [], []
        while True:
            t = self.peek()
            if t is None or t[0] == "OP":
                break
            if t[0] == "W" and not words and self.word_is(t, *stops):
                break
            if t[0] == "W":
                words.append(t[1])
            elif t[0] == "ARR":
                arrs.append(t[1:])
            elif t[0] == "PROC":
                procs.append(t[1])
            self.i += 1
        if not words and not arrs and not procs:
            raise ShParseError("empty command near %r" % (self.peek(),))
        return ("simple", words, arrs, procs)


def parse(text):
    return P(lex(text)).parse_list(set())


# ----------------------------------------------------------------------------- interpreter
class Model:
    """Abstract interpretation of a parsed script. invoked / sourced: rel -> 'definite' | 'conditional'."""
    def __init__(self, root, rel, args):
        self.root = os.path.realpath(root)
        self.script = os.path.join(self.root, rel)
        self.cwd = self.root
        self.vars = {}            # name -> list of candidate strings (None in the list = unknown)
        self.arrays = {}          # name -> list of (value or None, definite)
        self.funcs = {}
        self.pos = [self.script] + list(args)
        self.invoked = {}
        self.sourced = {}
        self.unknown = 0
        self.depth = 0
        self.cur_def = True
        self.steps = 0

    def tick(self):
        self.steps += 1
        if self.steps > 200000:
            raise ShParseError("model step budget exceeded (runaway loop)")

    # -- values
    def lookup(self, name):
        if name in self.vars:
            return self.vars[name]
        if name == "PWD":
            return [self.cwd]
        if name in ENV_KNOWN:
            return [None]
        return [""]

    def setvar(self, name, vals, definite):
        vals = list(vals)[:MAXV]
        if definite or name not in self.vars:
            self.vars[name] = vals
        else:
            merged = list(self.vars[name])
            for v in vals:
                if v not in merged:
                    merged.append(v)
            self.vars[name] = merged[:MAXV]

    def param(self, expr):
        """Candidates (list) for a ${...} / $x expression; None inside the list = unknown."""
        if expr == "0" or expr in ("BASH_SOURCE", "BASH_SOURCE[0]"):
            return [self.script]
        if re.match(r"^[1-9]$", expr):
            k = int(expr)
            return [self.pos[k]] if k < len(self.pos) else [""]
        if expr in ("@", "*"):
            return [" ".join(x for x in self.pos[1:] if x is not None)]
        if expr in ("#",):
            return [str(len(self.pos) - 1)]
        if expr in ("?", "$", "!", "-"):
            return [None]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*|[1-9])(:?[-=+?])(.*)$", expr, re.S)
        if m:
            nm, op, rest = m.groups()
            base = self.param(nm)
            isset = nm in self.vars or nm in self.arrays or nm in ENV_KNOWN or (nm.isdigit() and int(nm) < len(self.pos))
            if op in (":-", "-", ":=", "="):
                res = []
                for b in base:
                    if b is None:
                        res.append(None)
                    elif (b == "" and op.startswith(":")) or not isset:
                        res.extend(self.eval_text(rest))
                    else:
                        res.append(b)
                if op in (":=", "=") and NAME.match(nm):
                    self.setvar(nm, res, True)
                return res[:MAXV]
            if op in (":+", "+"):
                res = []
                for b in base:
                    if b is None:
                        res.append(None)
                    elif (b == "" and op.startswith(":")) or not isset:
                        res.append("")
                    else:
                        res.extend(self.eval_text(rest))
                return res[:MAXV]
            return base
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\[([@*])\]$", expr)
        if m:
            return [" ".join(v for v, _d in self.arrays.get(m.group(1), []) if v is not None)]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\[(\d+)\]$", expr)
        if m:
            el = self.arrays.get(m.group(1), [])
            k = int(m.group(2))
            return [el[k][0]] if k < len(el) else [""]
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)([%#]{1,2})(.*)$", expr, re.S)
        if m:
            nm, op, pat = m.groups()
            res = []
            for b in self.param(nm):
                pv = self.eval_text(pat)
                if b is None or len(pv) != 1 or pv[0] is None:
                    res.append(None)
                    continue
                res.append(_strip(b, op, pv[0]))
            return res
        if NAME.match(expr):
            if expr in self.arrays and expr not in self.vars:
                el = self.arrays[expr]
                return [el[0][0]] if el else [""]
            return self.lookup(expr)
        return [None]

    def eval_text(self, text):
        toks = [t for t in lex(text) if t[0] == "W"]
        if not toks:
            return [""]
        return self.eval_word(toks[0][1], glob_ok=False)

    def cmdsub(self, text):
        """Run a $(...) / <(...) body in a subshell model (its invocations count); return its value
        when it is pwd / cd X && pwd / dirname / basename, else unknown."""
        try:
            ast = parse(text)
        except ShParseError:
            self.unknown += 1
            return [None]
        saved = (dict(self.vars), {k: list(v) for k, v in self.arrays.items()}, self.cwd)
        try:
            self.run_list(ast, self.cur_def)
        except _Stop:
            pass
        finally:
            self.vars, self.arrays, self.cwd = saved
        flat = []
        for item in ast:
            for _conn, pipe in item:
                if len(pipe[2]) == 1 and pipe[2][0][0] == "simple" and not pipe[1]:
                    flat.append(pipe[2][0])
                else:
                    return [None]
        if not flat:
            return [None]
        cwd = self.cwd
        value = [None]
        for cmd in flat:
            words = [self.eval_word(w, glob_ok=False) for w in cmd[1]]
            if not words or any(len(w) != 1 or w[0] is None for w in words):
                return [None]
            argv = [w[0] for w in words]
            if argv[0] == "cd":
                tgt = [x for x in argv[1:] if x not in ("-P", "-L", "--")]
                if len(tgt) != 1 or not tgt[0]:
                    return [None]
                cwd = self.absp(tgt[0], cwd)
                value = [""]
            elif argv[0] == "pwd":
                value = [cwd]
            elif argv[0] == "dirname" and len(argv) == 2:
                value = [os.path.dirname(argv[1]) or "."]
            elif argv[0] == "basename" and len(argv) in (2, 3):
                b = os.path.basename(argv[1].rstrip("/"))
                if len(argv) == 3 and b.endswith(argv[2]) and b != argv[2]:
                    b = b[: -len(argv[2])]
                value = [b]
            elif argv[0] == "realpath" and len(argv) == 2:
                value = [self.absp(argv[1], cwd)]
            else:
                return [None]
        return value

    def absp(self, p, cwd=None):
        return os.path.normpath(p if os.path.isabs(p) else os.path.join(cwd or self.cwd, p))

    def eval_word_ex(self, segs, glob_ok=True):
        """(list of candidate strings (None = unknown), split) -- split=True when the values are the
        separate fields of one glob expansion (not alternative candidates)."""
        cands = [("", False)]
        for sg in segs:
            if sg[0] == "lit":
                parts = [(sg[1], (not sg[2]) and any(ch in sg[1] for ch in "*?["))]
            elif sg[0] == "param":
                parts = [(v, False) for v in self.param(sg[1])]
            else:
                parts = [(v, False) for v in self.cmdsub(sg[1])]
            nxt = []
            for c, g in cands:
                for v, vg in parts:
                    if c is None or v is None:
                        nxt.append((None, False))
                    else:
                        nxt.append((c + v, g or vg))
            cands = nxt[:MAXV]
        if glob_ok and len(cands) == 1 and cands[0][0] is not None and cands[0][1]:
            c = cands[0][0]
            pat = self.absp(c) if not os.path.isabs(c) else c
            hits = sorted(glob.glob(pat))
            if hits:
                if not os.path.isabs(c):
                    hits = [os.path.relpath(h, self.cwd) for h in hits]
                return hits, True
            return [c], False
        return [c for c, _g in cands], False

    def eval_word(self, segs, glob_ok=True):
        return self.eval_word_ex(segs, glob_ok)[0]

    def eval_words(self, words, definite):
        """argv variants: list of (argv list (entries str or None), definite)."""
        variants = [([], definite)]
        for w in words:
            arr = None
            if len(w) == 1 and w[0][0] == "param":
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\[[@*]\]$", w[0][1])
                if m:
                    arr = self.arrays.get(m.group(1), [])
                elif w[0][1] in ("@", "*") and w[0][2]:
                    arr = [(p, True) for p in self.pos[1:]]
            nxt = []
            if arr is not None:
                for argv, d in variants:
                    nxt.append((argv + [v for v, _x in arr], d and all(x for _v, x in arr)))
            else:
                vals, split = self.eval_word_ex(w)
                if split:
                    for argv, d in variants:
                        nxt.append((argv + vals, d))
                else:
                    for argv, d in variants:
                        for v in vals:
                            nxt.append((argv + [v], d and len(vals) == 1))
            variants = nxt[:256]
        return variants

    # -- execution
    def record(self, path, definite, table):
        if path is None:
            self.unknown += 1
            return None
        p = self.absp(path)
        if not (p == self.root or p.startswith(self.root + os.sep)):
            return None
        rel = os.path.relpath(p, self.root)
        if table.get(rel) != "definite":
            table[rel] = "definite" if definite else "conditional"
        return rel

    def test_cond(self, argv):
        a = argv[1:]
        close = {"[": "]", "[[": "]]"}.get(argv[0])
        if close:
            if not a or a[-1] != close:
                return None
            a = a[:-1]
        if any(x is None for x in a):
            return None
        if len(a) == 1:
            return a[0] != ""
        if len(a) == 2 and a[0] in ("-n", "-z"):
            return (a[1] != "") == (a[0] == "-n")
        if len(a) == 3:
            x, op, y = a
            if op in ("=", "=="):
                return fnmatch.fnmatchcase(x, y) if argv[0] == "[[" else x == y
            if op == "!=":
                return not fnmatch.fnmatchcase(x, y) if argv[0] == "[[" else x != y
            if op in ("-eq", "-ne", "-lt", "-le", "-gt", "-ge"):
                try:
                    x, y = int(x), int(y)
                except ValueError:
                    return None
                return {"-eq": x == y, "-ne": x != y, "-lt": x < y, "-le": x <= y, "-gt": x > y, "-ge": x >= y}[op]
        return None

    def run_simple(self, cmd, definite):
        _k, words, arrs, procs = cmd
        for p in procs:
            self.cmdsub(p)
        for name, append, elems in arrs:
            vals = []
            for e in elems:
                ev, split = self.eval_word_ex(e)
                for v in ev:
                    vals.append((v, definite and (split or len(ev) == 1)))
            if append:
                self.arrays.setdefault(name, []).extend(vals)
            elif definite:
                self.arrays[name] = vals
            else:
                self.arrays.setdefault(name, []).extend(vals)
        # Leading NAME=value words are assignments by their literal prefix, whatever the value
        # evaluates to: an unknown value (a command substitution) assigns UNKNOWN, never nothing.
        k = 0
        pending = []
        while k < len(words):
            sp = _split_assign(words[k])
            if sp is None:
                break
            pending.append(sp)
            k += 1
        if pending and k == len(words):
            for nm, app, segs in pending:
                vals = self.eval_word(segs, glob_ok=False)
                if app:
                    old = self.lookup(nm)
                    vals = [None if (o is None or v is None) else o + v for o in old for v in vals]
                self.setvar(nm, vals, definite and len(vals) == 1)
            return True
        for _nm, _app, segs in pending:
            self.eval_word(segs, glob_ok=False)
        status = None
        for argv, d in self.eval_words(words[k:], definite):
            status = self.exec_argv(argv, d)
        return status

    def assign(self, word, definite):
        m = ASSIGN.match(word)
        nm, val = m.group(1), word[len(m.group(0)):]
        if m.group(2):
            old = self.lookup(nm)
            self.setvar(nm, [None if o is None else o + val for o in old], definite)
        else:
            self.setvar(nm, [val], definite)

    def exec_argv(self, argv, definite):
        self.tick()
        if argv and all(x is not None and ASSIGN.match(x) for x in argv):
            for x in argv:
                self.assign(x, definite)
            return True
        while argv and argv[0] is not None and ASSIGN.match(argv[0]):
            argv = argv[1:]
        if not argv:
            return True
        w = argv[0]
        if w is None:
            self.unknown += 1
            return None
        if w in (":", "true"):
            return True
        if w == "false":
            return False
        if w in ("local", "export", "readonly", "declare", "typeset"):
            for x in argv[1:]:
                if x is not None and ASSIGN.match(x):
                    self.assign(x, definite)
            return True
        if w in ("[", "[[", "test"):
            return self.test_cond(argv if w != "test" else ["["] + argv[1:] + ["]"])
        if w in ("exit", "return", "continue", "break"):
            raise _Stop(w, definite)
        if w == "cd":
            tgt = [x for x in argv[1:] if x not in ("-P", "-L", "--")]
            if len(tgt) == 1 and tgt[0] is not None and tgt[0] != "-":
                if definite:
                    self.cwd = self.absp(tgt[0])
            elif definite:
                self.cwd = self.root if not tgt else self.cwd
            return None
        if w in ("nice", "ionice", "timeout", "env", "exec", "command", "builtin", "time", "setsid", "stdbuf", "nohup"):
            rest = argv[1:]
            while rest and rest[0] is not None and (rest[0].startswith("-") or (w == "env" and ASSIGN.match(rest[0]))):
                o = rest.pop(0)
                if (w, o) in (("nice", "-n"), ("ionice", "-c"), ("ionice", "-n"), ("timeout", "-k"),
                              ("timeout", "-s"), ("env", "-u"), ("stdbuf", "-o"), ("stdbuf", "-e")) and rest:
                    rest.pop(0)
            if w == "timeout" and rest:
                rest.pop(0)
            if w == "command" and argv[1:2] == ["-v"]:
                return None
            return self.exec_argv(rest, definite)
        if w in (".", "source"):
            if len(argv) >= 2:
                rel = self.record(argv[1], definite, self.sourced)
                if rel and self.depth < 6 and os.path.isfile(os.path.join(self.root, rel)):
                    self.interpret_file(rel, definite)
            return None
        if w in self.funcs and self.depth < 8:
            saved = self.pos
            self.pos = [self.pos[0]] + argv[1:]
            self.depth += 1
            try:
                self.run_list(self.funcs[w], definite)
            except _Stop as e:
                if e.kind != "return" and (e.definite and definite):
                    raise
            finally:
                self.depth -= 1
                self.pos = saved
            return None
        base = os.path.basename(w)
        if base in ("bash", "sh", "dash", "python3", "python"):
            py = base.startswith("python")
            rest = argv[1:]
            while rest:
                o = rest[0]
                if o is None:
                    self.unknown += 1
                    return None
                if o == "-c":
                    if not py and len(rest) >= 2 and rest[1] is not None:
                        try:
                            ast = parse(rest[1])
                        except ShParseError:
                            return None
                        saved = self.pos
                        self.pos = [rest[2] if len(rest) > 2 else self.pos[0]] + list(rest[3:])
                        try:
                            self.run_list(ast, definite)
                        except _Stop:
                            pass
                        finally:
                            self.pos = saved
                    return None
                if py and o == "-m":
                    return None
                if o == "-" or o == "--":
                    if o == "-":
                        return None
                    rest = rest[1:]
                    break
                if o.startswith("-") or (not py and o.startswith("+")):
                    rest = rest[1:]
                    if (py and o in ("-W", "-X")) or (not py and o in ("-o", "-O", "+o", "+O")):
                        rest = rest[1:]
                    continue
                break
            if rest:
                self.record(rest[0], definite, self.invoked)
            return None
        if "/" in w and os.path.isfile(self.absp(w)):
            self.record(w, definite, self.invoked)
        return None

    def run_pipe(self, pipe, definite):
        _k, neg, cmds = pipe
        status = None
        for c in cmds:
            status = self.run_cmd(c, definite)
        if len(cmds) > 1:
            status = None if status is None else status
        if neg and status is not None:
            status = not status
        return status

    def soft(self, fn, *args):
        """Run a non-definite branch: a stop raised on a conditional path does not end the model."""
        try:
            return fn(*args)
        except _Stop as e:
            if e.definite:
                raise
            return None

    def run_andor(self, parts, definite):
        status, ran_def = None, definite
        for conn, pipe in parts:
            if conn is None:
                status = self.run_pipe(pipe, definite)
                continue
            if conn == "&&":
                if status is False:
                    continue
                d = ran_def and status is True
            else:
                if status is True:
                    continue
                d = ran_def and status is False
            status = self.run_pipe(pipe, d) if d else self.soft(self.run_pipe, pipe, d)
            ran_def = d
        return status

    def run_list(self, items, definite):
        saved = self.cur_def
        status = None
        try:
            for parts in items:
                self.cur_def = definite
                status = self.run_andor(parts, definite)
        finally:
            self.cur_def = saved
        return status

    def run_cmd(self, c, definite):
        k = c[0]
        self.cur_def = definite
        if k == "simple":
            return self.run_simple(c, definite)
        if k in ("sub", "group"):
            for p in c[2]:
                self.cmdsub(p)
            if k == "sub":
                saved = (dict(self.vars), {a: list(v) for a, v in self.arrays.items()}, self.cwd)
                try:
                    self.run_list(c[1], definite)
                except _Stop:
                    pass
                finally:
                    self.vars, self.arrays, self.cwd = saved
                return None
            return self.run_list(c[1], definite)
        if k == "func":
            self.funcs[c[1]] = [[(None, ("pipe", False, [c[2]]))]]
            return True
        if k == "if":
            for p in c[3]:
                self.cmdsub(p)
            d = definite
            for cond, body in c[1]:
                st = self.run_list(cond, d) if d else self.soft(self.run_list, cond, d)
                if st is True:
                    return self.run_list(body, d) if d else self.soft(self.run_list, body, d)
                if st is None:
                    self.soft(self.run_list, body, False)
                    d = False
            if c[2] is not None:
                if d:
                    self.run_list(c[2], d)
                else:
                    self.soft(self.run_list, c[2], False)
            return None
        if k == "while":
            for p in c[3]:
                self.cmdsub(p)
            self.soft(self.run_list, c[1], False)
            try:
                self.run_list(c[2], False)
            except _Stop:
                pass
            return None
        if k == "afor":
            try:
                self.run_list(c[1], False)
            except _Stop:
                pass
            return None
        if k == "for":
            _k, var, items, body, procs = c
            for p in procs:
                self.cmdsub(p)
            if items is None:
                values = [(v, definite) for v in self.pos[1:]]
            else:
                values = []
                for argv, d in self.eval_words(items, definite):
                    values.extend((x, d) for x in argv)
            for val, d in values[:2000]:
                self.setvar(var, [val], True)
                try:
                    self.run_list(body, d)
                except _Stop as e:
                    if e.kind == "continue":
                        continue
                    if e.kind == "break":
                        if e.definite and d:
                            break
                        continue
                    if not (e.definite and d):
                        continue
                    raise
            return None
        if k == "case":
            _k, subj, arms, procs = c
            for p in procs:
                self.cmdsub(p)
            vals = self.eval_word(subj, glob_ok=False)
            s = vals[0] if len(vals) == 1 else None
            for pats, body in arms:
                hit = False
                for pw in pats:
                    pv = self.eval_word(pw, glob_ok=False)
                    if s is None or len(pv) != 1 or pv[0] is None:
                        hit = "unknown"
                        continue
                    if fnmatch.fnmatchcase(s, pv[0]):
                        hit = True
                        break
                if hit is True:
                    return self.run_list(body, definite) if definite else self.soft(self.run_list, body, False)
                if hit == "unknown":
                    self.soft(self.run_list, body, False)
            return None
        raise ShParseError("unknown node %r" % k)

    def interpret_file(self, rel, definite):
        with open(os.path.join(self.root, rel), errors="replace") as fh:
            ast = parse(fh.read())
        self.depth += 1
        try:
            self.run_list(ast, definite)
        except _Stop as e:
            if e.kind not in ("exit", "return"):
                raise
        finally:
            self.depth -= 1


def _strip(b, op, pat):
    """${x%pat} ${x%%pat} ${x#pat} ${x##pat} with fnmatch patterns."""
    rng = range(len(b) + 1)
    if op == "#":
        for i in rng:
            if fnmatch.fnmatchcase(b[:i], pat):
                return b[i:]
    elif op == "##":
        for i in reversed(rng):
            if fnmatch.fnmatchcase(b[:i], pat):
                return b[i:]
    elif op == "%":
        for i in reversed(rng):
            if fnmatch.fnmatchcase(b[i:], pat):
                return b[:i]
    elif op == "%%":
        for i in rng:
            if fnmatch.fnmatchcase(b[i:], pat):
                return b[:i]
    return b


def model(root, rel, args):
    """Interpret `rel` (relative to `root`) with positional `args`; return the Model."""
    m = Model(root, rel, args)
    with open(m.script, errors="replace") as fh:
        text = fh.read()
    ast = parse(text)
    try:
        m.run_list(ast, True)
    except _Stop:
        pass
    m.invoked.pop(rel, None)
    return m

# =============================================================================== runner engine
import fcntl
import hashlib
import json
import secrets
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

SCHEMA = "fsr/3"
VERDICTS = ("PASS", "FAIL", "SKIP", "TIMEOUT", "ERROR", "SKIPPED-heavy", "NOT-RUN")
EXECUTED = ("PASS", "FAIL", "SKIP", "TIMEOUT", "ERROR")
BAD = ("FAIL", "TIMEOUT", "ERROR")
RANK = {"PASS": 0, "SKIP": 1, "FAIL": 2, "TIMEOUT": 2, "ERROR": 2}
HEAVY_NAME = re.compile(r"(mutation|mutant|mutate|chaos|stress|perf|meta_test|smoke)", re.I)
SH_PATTERNS = (re.compile(r"^test_.*\.sh$"), re.compile(r"^.*_test\.sh$"),
               re.compile(r"^.*selftest.*\.sh$"), re.compile(r"^run_all\.sh$"))
PY_PATTERNS = (re.compile(r"^test_.*\.py$"), re.compile(r"^.*_test\.py$"))
GO_PATTERN = re.compile(r"^.*_test\.go$")
SCRIPT_EXT = re.compile(r"\.(sh|bash|py)$", re.I)
TEST_KEYWORD = re.compile(r"(test|mutant|mutation|smoke|selftest)", re.I)
TEST_DIRS = ("tests", "test")
KINDS = ("sh", "py", "go", "runall")
CLASSES = ("entry", "member", "fixture", "excluded")
TIERS = ("default", "heavy", "-")
RUNNERS = ("bash", "sh", "python3", "go-test", "runall-whole", "runall-quick", "runall-members", "-")
IGNORED_NOT_HASHED = (re.compile(r"(^|/)__pycache__/"), re.compile(r"\.pyc$"), re.compile(r"(^|/)\.pytest_cache/"),
                      re.compile(r"^qa-results/"))
GUIDE_REL = os.path.join("docs", "guides", "full_suite_runner_guide.md")
GUIDE_BEGIN, GUIDE_END = "<!-- census:begin -->", "<!-- census:end -->"
TAIL_BYTES = 1 << 20
MANIFEST_HEADER = ("# config/full_suite_manifest.tsv -- declared set of test entry points for scripts/run_full_suite.sh\n"
                   "# (section 11.4.40). Generated by `bash scripts/run_full_suite.sh --generate-manifest --write`, then\n"
                   "# reviewed; regeneration keeps existing rows as they are. Every census file must have exactly one row;\n"
                   "# a census file without a row, or a row without a file, makes the runner refuse (exit 3).\n"
                   "# Columns (TAB): path kind class tier runner covered_by note\n"
                   "#   kind    sh | py | go (path = Go module dir) | runall\n"
                   "#   class   entry (run as a unit) | member (run only through covered_by, which must invoke it)\n"
                   "#           | fixture (under a fixtures/ dir, never run) | excluded (not a test; note `reason: <why>`)\n"
                   "#   tier    default | heavy (run only with --include-heavy) | - (fixture, excluded)\n"
                   "#   runner  bash | sh | python3 | go-test | runall-whole | runall-quick | runall-members | -\n"
                   "#   note    free text; `override:` documents a curated deviation; excluded rows need `reason: <why>`,\n"
                   "#           and `reason: helper, sourced by <path>` is checked against the shell model of <path>\n")


class Fatal(Exception):
    def __init__(self, code, msg):
        Exception.__init__(self, msg)
        self.code = code


def out(msg):
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


def err(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()


def git(root, *args, binary=False, check=True):
    p = subprocess.run(["git", "-C", root] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and p.returncode != 0:
        raise Fatal(2, "git %s failed: %s" % (" ".join(args), p.stderr.decode(errors="replace").strip()))
    return p.stdout if binary else p.stdout.decode(errors="replace")


def invoked(root, rel, args):
    """Set of root-relative paths the shell script `rel` invokes when run with `args` (shell model)."""
    return set(model(root, rel, args).invoked)


def sourced(root, rel):
    return set(model(root, rel, []).sourced)


# ----------------------------------------------------------------------------- census
def submodule_paths(root):
    p = subprocess.run(["git", "-C", root, "config", "-f", ".gitmodules", "--get-regexp", r"^submodule\..*\.path$"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    paths = []
    for line in p.stdout.decode(errors="replace").splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            paths.append(parts[1].strip().rstrip("/"))
    for line in git(root, "ls-files", "-s").splitlines():
        if line.startswith("160000 "):
            paths.append(line.split("\t", 1)[1])
    return sorted(set(paths))


def name_test(b):
    return any(p.match(b) for p in SH_PATTERNS) or any(p.match(b) for p in PY_PATTERNS)


def broad_candidate(f):
    """Name/dir rule (no content read): could this path be a test-like script?"""
    b = os.path.basename(f)
    parts = f.split("/")[:-1]
    ext = SCRIPT_EXT.search(b) is not None
    in_tdir = any(p in TEST_DIRS for p in parts)
    if name_test(b) or GO_PATTERN.match(b):
        return True
    if ext and (in_tdir or TEST_KEYWORD.search(b)):
        return True
    return in_tdir and "." not in b


def has_shebang(path):
    try:
        with open(path, "rb") as fh:
            return re.match(rb"^#!\s*\S*(sh|bash|python3?|env\s+(ba)?sh|env\s+python3?)\b", fh.read(128)) is not None
    except OSError:
        return False


def census(root):
    """Return (scripts {rel: kind}, gofiles [rel], problems [str]). Fatal(2) when not a git work tree."""
    if subprocess.run(["git", "-C", root, "rev-parse", "--git-dir"], stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode != 0:
        raise Fatal(2, "census impossible: %s is not a git work tree" % root)
    subs = submodule_paths(root)
    raw = git(root, "ls-files", "-co", "--exclude-standard", "-z", binary=True).decode(errors="replace")
    listed = sorted(set(x for x in raw.split("\0") if x))
    if not listed:
        raise Fatal(3, "census instrument blind: git ls-files listed nothing under %s (positive control failed)" % root)
    scripts, gofiles, probs = {}, [], []
    for f in listed:
        if any(f == s or f.startswith(s + "/") for s in subs):
            continue
        if not broad_candidate(f):
            continue
        p = os.path.join(root, f)
        if "\n" in f or "\t" in f:
            probs.append("census: file name with a newline or TAB cannot be listed in the manifest: %r" % f)
            continue
        if os.path.islink(p) and not os.path.exists(p):
            if "/fixtures/" in "/" + f:
                scripts[f] = "sh"  # fixture data: listed, so it needs a declared fixture row; never run
            else:
                probs.append("census: dangling symlink: %s" % f)
            continue
        if not os.path.isfile(p):
            continue  # deleted in the work tree, or a gitlink
        b = os.path.basename(f)
        if GO_PATTERN.match(b):
            gofiles.append(f)
            continue
        if not SCRIPT_EXT.search(b) and not has_shebang(p):
            continue
        if b.lower().endswith(".py") or (not SCRIPT_EXT.search(b) and has_shebang(p) and b"python" in open(p, "rb").read(64)):
            scripts[f] = "py"
        elif b == "run_all.sh":
            scripts[f] = "runall"
        else:
            scripts[f] = "sh"
    return scripts, gofiles, probs


NEEDLE = {"a/test_x.sh": 1, "a/y_test.sh": 1, "a/z_selftest.sh": 1, "a/w_selftest_mutations.sh": 1, "a/run_all.sh": 1,
          "a/test_p.py": 1, "a/q_test.py": 1, "tests/helper.sh": 1, "tests/UPPER.SH": 1, "tests/noext": 1,
          "test/t.bash": 1, "b/live_smoke.sh": 1, "b/meta_mutation.sh": 1, "b/x_mutants.py": 1, "m/k_test.go": 2,
          "a/plain.sh": 0, "a/test_x.txt": 0, "a/run_all.sh.bak": 0, "a/k_test.go.orig": 0, "tests/data.txt": 0,
          "tests/noshebang": 0, "sub/test_in_submodule.sh": 0}


def census_needle(scratch):
    """Control needle: census() on a fixture with known positives, decoys, a submodule path, then a
    dangling test symlink that MUST be reported (proves the instrument sees, section 11.4.273)."""
    d = tempfile.mkdtemp(prefix="fsr_needle.", dir=scratch)
    try:
        for f in NEEDLE:
            os.makedirs(os.path.join(d, os.path.dirname(f)), exist_ok=True)
            with open(os.path.join(d, f), "w") as fh:
                fh.write("#!/usr/bin/env bash\necho x\n" if f != "tests/noshebang" else "data\n")
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": d, "GIT_CONFIG_NOSYSTEM": "1"}
        subprocess.run(["git", "init", "-q", d], env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(os.path.join(d, ".gitmodules"), "w") as fh:
            fh.write('[submodule "sub"]\n\tpath = sub\n\turl = x\n')
        scripts, gofiles, probs = census(d)
        want_s = sorted(f for f, v in NEEDLE.items() if v == 1)
        want_g = sorted(f for f, v in NEEDLE.items() if v == 2)
        if sorted(scripts) != want_s or sorted(gofiles) != want_g or probs:
            raise Fatal(3, "census instrument blind: needle fixture gave scripts=%s go=%s problems=%s, want scripts=%s go=%s"
                        % (sorted(scripts), gofiles, probs, want_s, want_g))
        os.symlink("nowhere", os.path.join(d, "tests", "test_dangle.sh"))
        _s, _g, probs = census(d)
        if not any("tests/test_dangle.sh" in p for p in probs):
            raise Fatal(3, "census instrument blind: a dangling test symlink in the needle fixture was not reported")
    finally:
        rm_tree(d, scratch)


# ----------------------------------------------------------------------------- deletion
SAFE_RM = None


def rm_tree(path, scratch):
    """Delete a directory this run created, through scripts/lib/safe_rm.sh (section 11.4.287)."""
    real = os.path.realpath(path)
    sreal = os.path.realpath(scratch)
    if not real.startswith(sreal + os.sep) or not os.path.basename(real).startswith("fsr_"):
        raise Fatal(2, "refusing to delete %s: not a runner-made directory under %s" % (path, scratch))
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TMPDIR": sreal, "SAFE_RM_ALLOWED_ROOTS": sreal,
           "HOME": os.environ.get("HOME", "/nonexistent")}
    p = subprocess.run(["bash", "-c", '. "$1" || exit 2; safe_rm_rf "$2"', "_", SAFE_RM, real], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if p.returncode != 0:
        err("WARN: could not remove %s (safe_rm_rf rc=%d): %s" % (real, p.returncode, p.stderr.decode(errors="replace").strip()))


# ----------------------------------------------------------------------------- manifest
def read_text(root, rel):
    try:
        with open(os.path.join(root, rel), errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def shebang_runner(root, rel):
    first = read_text(root, rel).split("\n", 1)[0]
    if re.match(r"^#!\s*(/bin/sh|/usr/bin/env\s+sh)\s*$", first):
        return "sh"
    return "bash"


def go_module(root, rel):
    d = os.path.dirname(rel)
    while True:
        if os.path.isfile(os.path.join(root, d, "go.mod")):
            return d if d else "."
        if not d:
            return None
        d = os.path.dirname(d)


class Models:
    """Cache of shell-model results: (rel, args) -> Model or ShParseError."""
    def __init__(self, root):
        self.root, self.c = root, {}

    def get(self, rel, args=()):
        k = (rel, tuple(args))
        if k not in self.c:
            try:
                self.c[k] = model(self.root, rel, list(args))
            except (ShParseError, RecursionError, OSError) as e:
                self.c[k] = ShParseError(str(e))
        return self.c[k]

    def inv(self, rel, args=()):
        m = self.get(rel, args)
        if isinstance(m, ShParseError):
            raise m
        return set(m.invoked)


def generate(root, existing):
    """Draft manifest; rows already in `existing` (path -> row) are kept as they are."""
    scripts, gofiles, _probs = census(root)
    ms = Models(root)
    rows = {}
    shells = [f for f, k in scripts.items() if k in ("sh", "runall") and "/fixtures/" not in "/" + f]
    runalls = sorted(f for f in shells if scripts[f] == "runall")
    inv = {}
    for r in runalls:
        try:
            inv[r] = ms.inv(r)
        except ShParseError:
            inv[r] = set()
    srcby = {}
    for s in sorted(shells):
        m = ms.get(s)
        if not isinstance(m, ShParseError):
            for x in m.sourced:
                srcby.setdefault(x, s)
    for f in sorted(scripts):
        kind = scripts[f]
        if f in existing:
            rows[f] = existing[f]
            continue
        b = os.path.basename(f)
        if "/fixtures/" in "/" + f:
            rows[f] = [f, kind, "fixture", "-", "-", "-", "fixture path (not a test entry point)"]
            continue
        if not name_test(b) and not TEST_KEYWORD.search(b):
            if f in srcby:
                rows[f] = [f, kind, "excluded", "-", "-", "-", "reason: helper, sourced by %s" % srcby[f]]
            else:
                rows[f] = [f, kind, "excluded", "-", "-", "-", "UNREVIEWED: helper-like file; write `reason: <why>` or reclassify"]
            continue
        tier = "heavy" if HEAVY_NAME.search(b) else "default"
        cover = "-"
        if kind != "runall":
            same = [r for r in runalls if os.path.dirname(r) == os.path.dirname(f)]
            for r in same + [r for r in runalls if r not in same]:
                if f in inv[r]:
                    cover = r
                    break
            if cover == "-" and kind == "py":
                for s in sorted(x for x in shells if os.path.dirname(x) == os.path.dirname(f) and scripts[x] == "sh"):
                    if tier != "heavy" and HEAVY_NAME.search(os.path.basename(s)):
                        continue
                    try:
                        if f in ms.inv(s):
                            cover = s
                            break
                    except ShParseError:
                        continue
        if cover != "-":
            rows[f] = [f, kind, "member", tier, "-", cover, "auto: invoked by %s" % cover]
        elif kind == "py":
            rows[f] = [f, kind, "entry", tier, "python3", "-", "auto"]
        elif kind == "sh":
            rows[f] = [f, kind, "entry", tier, shebang_runner(root, f), "-", "auto"]
        else:
            rows[f] = [f, kind, "entry", "default", "runall-whole", "-", "auto"]
    for r in runalls:
        if r in existing:
            continue
        heavy = [x for x in rows.values() if x[2] == "member" and x[5] == r and x[3] == "heavy"]
        if heavy:
            rows[r][4] = "runall-members"
            rows[r][6] = "auto: invokes %d heavy member(s)" % len(heavy)
    for m in sorted(set(go_module(root, g) or ("?" + g) for g in gofiles)):
        if m in existing:
            rows[m] = existing[m]
        elif not m.startswith("?"):
            rows[m] = [m, "go", "entry", "default", "go-test", "-", "auto: Go module with *_test.go"]
    return [rows[k] for k in sorted(rows)]


def read_manifest(path):
    if not os.path.isfile(path):
        raise Fatal(3, "manifest missing: %s (generate with --generate-manifest --write)" % path)
    rows, seen = [], set()
    with open(path, errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) != 7:
                raise Fatal(3, "manifest line %d: want 7 TAB columns, got %d" % (n, len(cols)))
            if cols[0] in seen:
                raise Fatal(3, "manifest line %d: duplicate path %s" % (n, cols[0]))
            seen.add(cols[0])
            rows.append(cols)
    return rows


def census_line(rows):
    cls_counts = {}
    for r in rows:
        k = "%s/%s" % (r[1], r[2])
        cls_counts[k] = cls_counts.get(k, 0) + 1
    return "census: " + " ".join("%s=%d" % (k, cls_counts[k]) for k in sorted(cls_counts)) + " total=%d" % len(rows)


def guide_block(rows):
    return ("census (generated by `bash scripts/run_full_suite.sh --sync-guide`; do not edit by hand): %s"
            % census_line(rows)[len("census: "):])


def guide_check(root, rows, fix=False):
    """None when the guide has no census block or it is current; else a problem string (or rewrites it)."""
    p = os.path.join(root, GUIDE_REL)
    if not os.path.isfile(p):
        return None
    with open(p, errors="replace") as fh:
        text = fh.read()
    if GUIDE_BEGIN not in text:
        return None
    a = text.index(GUIDE_BEGIN) + len(GUIDE_BEGIN)
    b = text.find(GUIDE_END, a)
    if b < 0:
        return "%s: %s without %s" % (GUIDE_REL, GUIDE_BEGIN, GUIDE_END)
    want = "\n" + guide_block(rows) + "\n"
    if text[a:b] == want:
        return None
    if fix:
        tmp = p + ".tmp.%d" % os.getpid()
        with open(tmp, "w") as fh:
            fh.write(text[:a] + want + text[b:])
        os.replace(tmp, p)
        return None
    return "%s: census block is stale (run --sync-guide)" % GUIDE_REL


def verify(root, rows):
    """Return a list of problems (empty = manifest matches census and every rule)."""
    scripts, gofiles, probs = census(root)
    probs = list(probs)
    ms = Models(root)
    by = {r[0]: r for r in rows}
    gomods = set()
    for g in gofiles:
        m = go_module(root, g)
        if m is None:
            probs.append("unclassifiable: %s has no go.mod ancestor" % g)
        else:
            gomods.add(m)
    want = set(scripts) | gomods
    for f in sorted(want - set(by)):
        probs.append("census file without manifest row: %s" % f)
    for f in sorted(set(by) - want):
        probs.append("stale manifest row (no such test file / module): %s" % f)
    for path, kind, cls, tier, runner, cover, note in rows:
        o = note.startswith("override:")
        if kind not in KINDS or cls not in CLASSES or tier not in TIERS or runner not in RUNNERS:
            probs.append("%s: value outside closed set (%s/%s/%s/%s)" % (path, kind, cls, tier, runner))
            continue
        if path in scripts and kind != scripts[path]:
            probs.append("%s: kind %s but the census says %s" % (path, kind, scripts[path]))
        b = os.path.basename(path)
        if cls in ("fixture", "excluded"):
            if tier != "-" or runner != "-" or cover != "-":
                probs.append("%s: %s rows take tier/runner/covered_by '-'" % (path, cls))
            if cls == "fixture" and "/fixtures/" not in "/" + path and not o:
                probs.append("%s: fixture outside a fixtures/ dir needs an override: note" % path)
            if cls == "excluded":
                m = re.match(r"^reason:\s*(\S.*)$", note)
                if not m:
                    probs.append("%s: excluded row needs a `reason: <why>` note (got %r)" % (path, note))
                    continue
                s = re.match(r"^helper, sourced by (\S+)$", m.group(1))
                if s:
                    src = s.group(1)
                    mm = ms.get(src) if os.path.isfile(os.path.join(root, src)) else ShParseError("no such file")
                    if isinstance(mm, ShParseError) or path not in mm.sourced:
                        probs.append("%s: excluded as sourced by %s, but the shell model of %s does not source it"
                                     % (path, src, src))
            continue
        if tier == "-":
            probs.append("%s: non-fixture row needs tier default|heavy" % path)
        if HEAVY_NAME.search(b) and tier != "heavy" and not o:
            probs.append("%s: heavy-looking name but tier %s (use heavy, or an override: note)" % (path, tier))
        if kind == "go":
            if not (cls == "entry" and runner == "go-test"):
                probs.append("%s: go rows are entry/go-test" % path)
        elif kind == "runall":
            if cls != "entry" or not runner.startswith("runall-"):
                probs.append("%s: run_all rows are entry/runall-*" % path)
        elif cls == "entry":
            if runner not in (("python3",) if kind == "py" else ("bash", "sh")) or cover != "-":
                probs.append("%s: entry %s row has runner %s covered_by %s" % (path, kind, runner, cover))
        if cls == "member":
            if runner != "-":
                probs.append("%s: member rows take runner '-'" % path)
            c = by.get(cover)
            if c is None or c[2] not in ("entry", "member") or c[1] == "go":
                probs.append("%s: covered_by %s is not an entry/member shell row" % (path, cover))
                continue
            try:
                if path not in ms.inv(cover):
                    probs.append("%s: covered_by %s does not run it (no invocation in its executable code)" % (path, cover))
            except ShParseError as e:
                probs.append("%s: covered_by %s cannot be modelled (%s); fail closed" % (path, cover, e))
            if c[3] == "heavy" and tier != "heavy":
                probs.append("%s: member of a heavy entry must be tier heavy" % path)
    for path, kind, cls, tier, runner, cover, note in rows:
        if kind != "runall" or cls != "entry":
            continue
        members = [r for r in rows if r[2] == "member" and r[5] == path]
        heavy = [r for r in members if r[3] == "heavy"]
        if runner == "runall-whole" and heavy:
            probs.append("%s: runall-whole covers heavy members %s (use runall-quick or runall-members)"
                         % (path, [os.path.basename(r[0]) for r in heavy]))
        if runner == "runall-quick":
            if "--quick" not in read_text(root, path):
                probs.append("%s: runall-quick but the script never mentions --quick" % path)
            try:
                q = ms.inv(path, ["--quick"])
            except ShParseError as e:
                probs.append("%s: cannot be modelled with --quick (%s); fail closed" % (path, e))
                continue
            for r in heavy:
                if r[0] in q:
                    probs.append("%s: heavy member %s is still run by %s --quick" % (path, r[0], path))
            for r in members:
                if r[3] == "default" and r[0] not in q:
                    probs.append("%s: default member %s is not run by %s --quick" % (path, r[0], path))
    g = guide_check(root, rows)
    if g:
        probs.append(g)
    return probs


def write_manifest(path, rows):
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write(MANIFEST_HEADER)
        for r in rows:
            fh.write("\t".join(c.replace("\t", " ") for c in r) + "\n")
    os.replace(tmp, path)


# ----------------------------------------------------------------------------- plan
def plan(rows, heavy_mode):
    """Units: list of dicts {id, path, runner, args, tier, run (bool), why}."""
    by = {r[0]: r for r in rows}
    units = []

    def add(path, runner, args, tier, run, why=""):
        uid = path + ("" if not args else " " + " ".join(args))
        units.append({"id": uid, "path": path, "runner": runner, "args": list(args), "tier": tier, "run": run, "why": why})

    def eff_heavy(r):
        while r[2] == "member":
            if r[3] == "heavy":
                return True
            r = by[r[5]]
        return r[3] == "heavy"

    for r in rows:
        path, kind, cls, tier, runner, cover, note = r
        if cls in ("fixture", "excluded"):
            continue
        if cls == "member":
            c = by[cover]
            if c[1] == "runall" and c[4] == "runall-members" and not heavy_mode:
                if tier == "default":
                    add(path, "python3" if kind == "py" else shebang_runner(ROOT, path), [], tier, True)
                else:
                    add(path, "-", [], tier, False, "heavy_excluded (member of %s)" % cover)
            elif c[1] == "runall" and c[4] == "runall-quick" and not heavy_mode and tier == "heavy":
                add(path, "-", [], tier, False, "heavy_excluded (dropped by --quick of %s)" % cover)
            continue
        if kind == "runall":
            if runner == "runall-quick":
                add(path, "bash", [] if heavy_mode else ["--quick"], tier, True)
            elif runner == "runall-members":
                if heavy_mode:
                    add(path, "bash", [], "heavy", True)
                else:
                    add(path, "-", [], "heavy", False, "heavy_excluded (covers heavy members; default members run alone)")
            else:
                add(path, "bash", [], tier, heavy_mode or tier == "default",
                    "" if heavy_mode or tier == "default" else "heavy_excluded")
            continue
        run = heavy_mode or not eff_heavy(r)
        add(path, runner, [], tier, run, "" if run else "heavy_excluded")
    return units


# ----------------------------------------------------------------------------- verdict parsing
# Structural, case-insensitive parse of the last 8 non-empty log lines (N5 of review round 2).
WIN = 8
WORDSIG = re.compile(r"^\W*(?:[A-Za-z_-]+\s+)?(result|verdict|run_all|status|summary|overall)\s*[:=](.*)$", re.I)
NUM = re.compile(r"(?<![\w./])(\d+)(?![\w]|\.\d)")
TOK = re.compile(r"[A-Za-z_]+")
FAIL_W = re.compile(r"^(fail|fails|failed|failure|failures|failed_suites|fail_count|errors?|survivors?|survived)$", re.I)
SKIP_W = re.compile(r"^(skip|skips|skipped)$", re.I)
PASS_W = re.compile(r"^(pass|passes|passed|ok|killed)$", re.I)
TOTAL_W = re.compile(r"^(total|tests?|cases|checks|assertions|ran|run)$", re.I)
PRIO = {"kv=": 0, "nw": 1, "kv:": 2, "wn": 3}


def wclass(word, prev):
    if PASS_W.match(word) and prev and prev.lower() == "not":
        return "f"
    if FAIL_W.match(word):
        return "f"
    if SKIP_W.match(word):
        return "s"
    if PASS_W.match(word):
        return "p"
    if TOTAL_W.match(word):
        return "t"
    return None


def line_counts(line):
    """Return (bindings {p,f,s,t: value}, ambiguous_fail, conflict) for one line, or None."""
    work = line
    c4 = {}
    m = re.search(r"(?<![\w./])(\d+)\s+of\s+(\d+)(?![\w]|\.\d)", work, re.I)
    if m:
        c4 = {"p": int(m.group(1)), "t": int(m.group(2))}
        work = work[:m.start()] + " " * (m.end() - m.start()) + work[m.end():]
    nums = [(mm.start(), mm.end(), int(mm.group(1))) for mm in NUM.finditer(work)]
    words = [(mm.start(), mm.end(), mm.group(0)) for mm in TOK.finditer(work)]
    keys = []
    for i, (a, b, w) in enumerate(words):
        prev = words[i - 1][2] if i else ""
        cl = wclass(w, prev)
        if cl:
            keys.append((a, b, w, cl))
    cands = []  # (num_index, key_index, prio)
    for ni, (na, nb, _v) in enumerate(nums):
        for ki, (ka, kb, _w, _cl) in enumerate(keys):
            gap_after = work[kb:na]
            gap_before = work[nb:ka]
            if ka < na:
                if re.match(r"^=\s*$", gap_after) or re.match(r"^\s*=\s*$", gap_after):
                    cands.append((ni, ki, PRIO["kv="]))
                elif re.match(r"^\s*:\s*$", gap_after):
                    cands.append((ni, ki, PRIO["kv:"]))
                elif re.match(r"^[ \t]+$", gap_after):
                    cands.append((ni, ki, PRIO["wn"]))
            else:
                if re.match(r"^[ \t]+$", gap_before):
                    cands.append((ni, ki, PRIO["nw"]))
    # multiword key before ':' ("Failed tests: 3"): any fail word among the 1-3 words before the colon
    for ni, (na, nb, _v) in enumerate(nums):
        mm = re.search(r"([A-Za-z_]+(?:[ \t]+[A-Za-z_]+){1,2})[ \t]*:[ \t]*$", work[:na])
        if mm:
            ws = mm.group(1).split()
            if any(FAIL_W.match(x) for x in ws):
                ka = mm.start(1)
                for ki, k in enumerate(keys):
                    if k[0] == ka:
                        break
                else:
                    keys.append((ka, mm.end(1), mm.group(1), "f"))
                    ki = len(keys) - 1
                kidx = [i for i, k in enumerate(keys) if mm.start(1) <= k[0] < mm.end(1) and k[3] == "f"]
                for ki in kidx:
                    cands.append((ni, ki, PRIO["kv:"]))
    if not cands and not c4:
        return None
    # all maximum-cardinality matchings with minimal priority score (small: brute force)
    best = {"size": -1, "score": None, "results": []}
    nnum = len(nums)

    def rec(ni, used, size, score, binds):
        if ni == nnum:
            if size > best["size"] or (size == best["size"] and (best["score"] is None or score < best["score"])):
                best.update(size=size, score=score, results=[dict(binds)])
            elif size == best["size"] and score == best["score"]:
                best["results"].append(dict(binds))
            return
        rec(ni + 1, used, size, score, binds)
        for (a, ki, pr) in cands:
            if a == ni and ki not in used:
                cl = keys[ki][3]
                prev = binds.get(cl)
                binds[cl] = (prev or 0) + nums[ni][2]
                rec(ni + 1, used | {ki}, size + 1, score + pr, binds)
                if prev is None:
                    del binds[cl]
                else:
                    binds[cl] = prev
    if nnum <= 10:
        rec(0, frozenset(), 0, 0, {})
    else:
        return None
    results = best["results"] or [{}]
    for r in results:
        for k, v in c4.items():
            r.setdefault(k, v)
    fails = [r.get("f", 0) for r in results]
    amb_fail = any(f > 0 for f in fails)
    conflict = len(set(tuple(sorted(r.items())) for r in results)) > 1
    chosen = results[0]
    if amb_fail:
        chosen = next(r for r in results if r.get("f", 0) > 0)
    kv_fail = any(keys[ki][3] == "f" for (_n, ki, pr) in cands if pr == PRIO["kv="])
    if not ("f" in chosen or "t" in chosen or kv_fail):
        return None
    return chosen, amb_fail, conflict and not amb_fail


def word_signal(line):
    """'f' / 'p' / 's' (with reason) for a VERDICT/RESULT/... line whose word is not a count."""
    m = WORDSIG.match(line)
    if not m:
        return None
    rest = m.group(2)
    for mm in re.finditer(r"(?<![A-Za-z_])(fail|failed|failure|pass|passed|skip|skipped)(?![A-Za-z_])", rest, re.I):
        before, after = rest[:mm.start()], rest[mm.end():]
        if re.search(r"\d\s*$", before) or re.match(r"^\s*[=:]?\s*\d", after):
            continue
        w = mm.group(1).lower()
        if w.startswith("fail"):
            return ("f", "")
        if w.startswith("skip"):
            r = re.search(r"reason[= ]([A-Za-z0-9_]+)", after)
            return ("s", r.group(1) if r else "suite_reported_skip")
        return ("p", "")
    return None


CHECKLINE = re.compile(r"^(PASS(:|\s+[^\d\s=:])|ok\s+\d+(\s+-|\s+[A-Za-z])|ok\s+-)")


def judge_exit0(text, kind):
    """Return (verdict, reason, source, counts) for a unit that exited 0."""
    lines = [l.rstrip() for l in text.splitlines() if l.strip()]
    if kind == "go-test":
        oks = sum(1 for l in lines if re.match(r"^ok\s", l))
        fails = sum(1 for l in lines if re.match(r"^(FAIL|--- FAIL)\b", l))
        if fails:
            return "FAIL", "go_test_reports_failure", "summary", {"p": oks, "f": fails}
        if oks == 0:
            return "ERROR", "zero_tests", "summary", {"p": 0, "f": 0}
        return "PASS", "", "summary", {"p": oks, "f": 0}
    win = lines[-WIN:]
    counts, last_counts, words = [], None, []
    any_conflict = False
    for i, l in enumerate(win):
        # a passing single-check line carries free-text description, never a summary: its numbers
        # ("PASS: shape (5 FAIL + 56 ...)", "ok 3 - (2 failed) input") are not counts
        c = None if CHECKLINE.match(l) else line_counts(l)
        if c:
            counts.append(c[0])
            last_counts = c[0]
            if c[1]:
                return "FAIL", "summary_reports_failures", "summary", c[0]
            any_conflict = any_conflict or c[2]
        w = word_signal(l)
        if w:
            words.append((i, w))
    if any(c.get("f", 0) > 0 for c in counts):
        return "FAIL", "summary_reports_failures", "summary", next(c for c in counts if c.get("f", 0) > 0)
    if any(w[0] == "f" for _i, w in words):
        return "FAIL", "summary_word_FAIL", "summary", last_counts
    if any_conflict:
        return "ERROR", "conflicting_summary", "summary", last_counts
    term_skip = next((w for i, w in words if i == len(win) - 1 and w[0] == "s"), None)
    if last_counts is not None:
        p, f, s, t = (last_counts.get(k) for k in ("p", "f", "s", "t"))
        p, f, s = p or 0, f or 0, s or 0
        if (t is not None and t == 0) or (t is None and "p" in last_counts and p + f + s == 0):
            return "ERROR", "zero_tests", "summary", last_counts
        if t is not None and p + f + s > t:
            return "ERROR", "inconsistent_counts", "summary", last_counts
        if term_skip and p > 0:
            return "ERROR", "conflicting_summary", "summary", last_counts
        if p == 0 and s > 0:
            return "SKIP", "all_skipped", "summary", last_counts
        return "PASS", "", "summary", last_counts
    if term_skip:
        return "SKIP", term_skip[1], "summary", None
    if any(w[0] == "p" for _i, w in words):
        return "PASS", "", "summary", None
    return "PASS", "", "exit-code-only", None


def judge(rc, timed_out, text, runner):
    if timed_out:
        return "TIMEOUT", "per_unit_timeout_reached", "runner-timer", None
    if rc < 0:
        return "ERROR", "killed_by_signal_%d" % -rc, "exit-code", None
    if rc == 0:
        return judge_exit0(text, runner)
    if rc == 77:
        lines = [l for l in text.splitlines() if l.strip()]
        r = re.search(r"reason[= ]([A-Za-z0-9_]+)", lines[-1]) if lines else None
        return "SKIP", (r.group(1) if r else "suite_reported_skip"), "exit-code", None
    if rc in (124, 137):
        return "ERROR", "rc_%d_without_runner_timeout" % rc, "exit-code", None
    if rc >= 128:
        return "ERROR", "killed_by_signal_%d" % (rc - 128), "exit-code", None
    if rc in (126, 127):
        return "ERROR", "exec_failed_rc_%d" % rc, "exit-code", None
    return "FAIL", "rc_%d" % rc, "exit-code", None


# ----------------------------------------------------------------------------- execution
def uid_procs():
    me = os.getuid()
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                if os.stat("/proc/" + d).st_uid == me:
                    yield int(d)
            except OSError:
                pass


def reap_token(token):
    """Kill every own-uid process whose environment carries the unit token; return the count."""
    needle = ("FULL_SUITE_UNIT_TOKEN=" + token).encode()
    killed = 0
    for _ in range(3):
        found = []
        for pid in uid_procs():
            if pid <= 1 or pid == os.getpid():
                continue
            try:
                with open("/proc/%d/environ" % pid, "rb") as fh:
                    env = fh.read()
            except OSError:
                continue
            if needle in env.split(b"\0"):
                found.append(pid)
        if not found:
            break
        for pid in found:
            assert pid > 1
            try:
                os.kill(pid, signal.SIGKILL)
                killed += 1
            except OSError:
                pass
        time.sleep(0.2)
    return killed


def killpg_checked(pgid, sig):
    # section 11.4.263: never signal a group id <= 1 or our own group
    if not isinstance(pgid, int) or pgid <= 1 or pgid == os.getpgrp():
        raise Fatal(2, "refusing killpg(%r)" % (pgid,))
    try:
        os.killpg(pgid, sig)
    except ProcessLookupError:
        pass


ENV_BASE = ("PATH", "LANG", "LC_ALL", "LC_CTYPE", "TERM", "USER", "LOGNAME", "TZ")


def unit_env(home, token, runner, extras, gomodcache):
    env = {k: os.environ[k] for k in ENV_BASE if k in os.environ}
    env.setdefault("PATH", "/usr/local/bin:/usr/bin:/bin")
    for k in extras:
        if k in os.environ:
            env[k] = os.environ[k]
    tmp = os.path.join(home, "tmp")
    for sub in ("tmp", ".config", ".cache", ".local/share", ".local/state"):
        os.makedirs(os.path.join(home, sub), exist_ok=True)
    env.update({"HOME": home, "TMPDIR": tmp, "XDG_CONFIG_HOME": os.path.join(home, ".config"),
                "XDG_CACHE_HOME": os.path.join(home, ".cache"), "XDG_DATA_HOME": os.path.join(home, ".local/share"),
                "XDG_STATE_HOME": os.path.join(home, ".local/state"), "FULL_SUITE_UNIT_TOKEN": token})
    if runner == "go-test":
        env.update({"GOCACHE": os.path.join(home, ".cache", "go-build"), "GOFLAGS": "-mod=readonly",
                    "GOPROXY": "off", "GOTOOLCHAIN": "local", "GOTELEMETRY": "off"})
        if gomodcache:
            env["GOMODCACHE"] = gomodcache
    return env


def run_unit(u, tmo, log, scratch, extras, gomodcache, cap):
    """Run one unit; stream its output into `log` up to `cap` bytes. Returns
    (rc, timed_out, secs, leaked, env_names, tail_text, overflow, log_sha256)."""
    home = tempfile.mkdtemp(prefix="fsr_home.", dir=scratch)
    token = secrets.token_hex(16)
    env = unit_env(home, token, u["runner"], extras, gomodcache)
    if u["runner"] == "go-test":
        argv, cwd = ["go", "test", "-count=1", "./..."], os.path.join(ROOT, u["path"])
    else:
        argv, cwd = [u["runner"], u["path"]] + u["args"], ROOT
    argv = ["nice", "-n", "15", "ionice", "-c3"] + argv
    t0 = time.time()
    timed_out = overflow = False
    written, tail, h = 0, bytearray(), hashlib.sha256()
    proc = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, start_new_session=True)
    pgid = proc.pid
    fd = proc.stdout.fileno()
    try:
        with open(log, "wb") as fh:
            term_at = exit_at = None
            killed = False
            while True:
                now = time.time()
                if exit_at is None and proc.poll() is not None:
                    exit_at = now
                if exit_at is not None and now - exit_at > 2:
                    break  # a grandchild holds the pipe; it is reaped by token below
                if exit_at is None and not timed_out and now - t0 > tmo:
                    timed_out, term_at = True, now
                    killpg_checked(pgid, signal.SIGTERM)
                if timed_out and exit_at is None and not killed and now - term_at > 10:
                    killpg_checked(pgid, signal.SIGKILL)
                    killed = True
                r, _w, _x = select.select([fd], [], [], 0.25)
                if not r:
                    continue
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                room = cap - written
                if room > 0:
                    part = chunk[:room]
                    fh.write(part)
                    h.update(part)
                    written += len(part)
                if len(chunk) > max(room, 0):
                    overflow = True
                tail += chunk
                if len(tail) > TAIL_BYTES:
                    del tail[:-TAIL_BYTES]
            if overflow:
                note = ("\n[full-suite runner: log capped at %d bytes; output beyond the cap was read and dropped]\n"
                        % cap).encode()
                fh.write(note)
                h.update(note)
        rc = proc.wait()
    except BaseException:
        killpg_checked(pgid, signal.SIGKILL)
        proc.wait()
        reap_token(token)
        rm_tree(home, scratch)
        raise
    finally:
        proc.stdout.close()
    secs = round(time.time() - t0, 1)
    leaked = reap_token(token)
    rm_tree(home, scratch)
    return rc, timed_out, secs, leaked, sorted(env), tail.decode("utf-8", errors="replace"), overflow, h.hexdigest()


# ----------------------------------------------------------------------------- results (hash chain)
REQ = {"schema": str, "seq": int, "prev": str, "unit": str, "path": str, "sha": str, "tree": str, "ctx": str,
       "runner_hash": str, "verdict": str, "reason": str, "verdict_source": str, "rc": int, "secs": (int, float),
       "leaked": int, "log": str, "log_sha256": str}
GENESIS = "0" * 64


def line_hash(b):
    """sha256 of one results.jsonl line (bytes, without the newline)."""
    return hashlib.sha256(b).hexdigest()


def valid_record(o):
    if not isinstance(o, dict) or o.get("schema") != SCHEMA:
        return False
    for k, t in REQ.items():
        if k not in o or not isinstance(o[k], t) or (t is int and isinstance(o[k], bool)):
            return False
    return o["verdict"] in VERDICTS


class Results:
    """results.jsonl: every line is a record carrying seq (its index) and prev (sha256 of the previous
    line, GENESIS for the first). Any break of the chain, an invalid record or a duplicate log path is an
    integrity error (exit 2): a hand-appended, edited or deleted line cannot be resumed from."""
    def __init__(self, path):
        self.path, self.recs, self.last = path, [], None
        if not os.path.exists(path):
            return
        with open(path, "rb") as fh:
            data = fh.read()
        if data and not data.endswith(b"\n"):
            cut = data.rfind(b"\n") + 1
            err("WARN: torn last line in %s dropped (%d bytes; an interrupted write left no complete record)"
                % (path, len(data) - cut))
            data = data[:cut]
            with open(path, "r+b") as fh:
                fh.truncate(cut)
        logs = set()
        for n, raw in enumerate(data.splitlines()):
            try:
                o = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                raise Fatal(2, "results integrity: %s line %d is not JSON" % (path, n + 1))
            if not valid_record(o):
                raise Fatal(2, "results integrity: %s line %d is not a valid %s record" % (path, n + 1, SCHEMA))
            want_prev = GENESIS if self.last is None else line_hash(self.last)
            if o["seq"] != n or o["prev"] != want_prev:
                raise Fatal(2, "results integrity: %s line %d breaks the hash chain (seq %r, want %d)"
                            % (path, n + 1, o["seq"], n))
            if o["log"]:
                if o["log"] in logs:
                    raise Fatal(2, "results integrity: %s line %d reuses log %s" % (path, n + 1, o["log"]))
                logs.add(o["log"])
            self.recs.append(o)
            self.last = raw

    def append(self, o):
        o["seq"] = len(self.recs)
        o["prev"] = GENESIS if self.last is None else line_hash(self.last)
        raw = json.dumps(o, sort_keys=True).encode()
        with open(self.path, "ab") as fh:
            fh.write(raw + b"\n")
            fh.flush()
            os.fsync(fh.fileno())
        self.recs.append(o)
        self.last = raw


def tree_state(root):
    """Hash of the working tree: status, diff vs HEAD, untracked contents, every submodule's own status
    and diff (recursive), and ignored files (name, size, content hash) except IGNORED_NOT_HASHED."""
    h = hashlib.sha256()
    h.update(git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none", binary=True))
    h.update(git(root, "diff", "HEAD", "--binary", "--no-ext-diff", "--no-color", binary=True, check=False))
    for f in sorted(x for x in git(root, "ls-files", "-o", "--exclude-standard", "-z", binary=True).decode(errors="replace").split("\0") if x):
        h.update(b"U" + f.encode())
        h.update(file_digest(os.path.join(root, f)))
    if os.path.isfile(os.path.join(root, ".gitmodules")) or "160000 " in git(root, "ls-files", "-s", check=False):
        h.update(git(root, "submodule", "foreach", "--recursive", "--quiet",
                     "git status --porcelain=v1 -z --untracked-files=all; git diff HEAD --binary --no-ext-diff --no-color",
                     binary=True, check=False))
    ign = git(root, "ls-files", "-o", "-i", "--exclude-standard", "-z", binary=True, check=False).decode(errors="replace")
    for f in sorted(x for x in ign.split("\0") if x):
        if any(p.search(f) for p in IGNORED_NOT_HASHED):
            continue
        h.update(b"I" + f.encode())
        h.update(file_digest(os.path.join(root, f)))
    return h.hexdigest()


def file_digest(p):
    try:
        if os.path.islink(p):
            return b"L" + os.readlink(p).encode()
        hh = hashlib.sha256()
        with open(p, "rb") as fh:
            for blk in iter(lambda: fh.read(1 << 20), b""):
                hh.update(blk)
        return hh.digest()
    except OSError:
        return b"?"


def load_known(path):
    rows = []
    if not os.path.isfile(path):
        return rows, "absent"
    with open(path, errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            c = line.split("\t")
            if len(c) != 4 or not c[0] or not c[1] or not c[2]:
                raise Fatal(2, "known-failures %s line %d: want 4 TAB columns path, signature, tracked_id, note (first three non-empty)"
                            % (path, n))
            rows.append(c)
    return rows, "%d open row(s)" % len(rows)


def match_known(known, path, reason, logtext):
    for p, sig, tid, _note in known:
        if p != path:
            continue
        if sig.startswith("reason:"):
            if reason == sig[len("reason:"):]:
                return tid
        elif sig in logtext:
            return tid
    return ""


def file_bytes(p):
    try:
        with open(p, "rb") as fh:
            return fh.read()
    except OSError:
        return b"<absent>"


# ----------------------------------------------------------------------------- main
ROOT = ""


def usage():
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "run_full_suite.sh")) as fh:
        for line in fh.read().splitlines()[1:]:
            if not line.startswith("#"):
                break
            out(line[2:] if line.startswith("# ") else line[1:])


def lock_out(outdir):
    os.makedirs(os.path.join(outdir, "logs"), exist_ok=True)
    fd = os.open(os.path.join(outdir, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        raise Fatal(2, "--out %s is locked by another running full-suite runner" % outdir)
    return fd


def main(argv):
    global ROOT, SAFE_RM
    here = os.path.dirname(os.path.abspath(__file__))
    SAFE_RM = os.path.realpath(os.path.join(here, "..", "lib", "safe_rm.sh"))
    root = os.path.realpath(os.path.join(here, "..", ".."))
    outdir = known = only = manifest = ""
    tmo, heavy, rerun, lst, gen, write, verify_only, sync = 900, False, False, False, False, False, False, False
    cap_mb = 64
    extras = []
    a = list(argv)
    while a:
        x = a.pop(0)

        def val():
            if not a or a[0] == "":
                raise Fatal(2, "%s needs a value" % x)
            return a.pop(0)
        if x == "--root":
            root = os.path.realpath(val())
        elif x == "--out":
            outdir = val()
        elif x == "--timeout":
            v = val()
            if not re.match(r"^[1-9][0-9]{0,5}$", v):
                raise Fatal(2, "bad --timeout %r (positive integer seconds, at most 6 digits)" % v)
            tmo = int(v)
        elif x == "--log-cap-mb":
            v = val()
            if not re.match(r"^[1-9][0-9]{0,4}$", v):
                raise Fatal(2, "bad --log-cap-mb %r (positive integer MiB)" % v)
            cap_mb = int(v)
        elif x in ("--include-heavy", "--heavy"):
            heavy = True
        elif x == "--known":
            known = val()
        elif x == "--manifest":
            manifest = val()
        elif x == "--rerun-nonpass":
            rerun = True
        elif x == "--list":
            lst = True
        elif x == "--only":
            only = val()
        elif x == "--env-extra":
            v = val()
            if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", v):
                raise Fatal(2, "bad --env-extra name %r" % v)
            extras.append(v)
        elif x == "--generate-manifest":
            gen = True
        elif x == "--write":
            write = True
        elif x == "--verify-manifest":
            verify_only = True
        elif x == "--sync-guide":
            sync = True
        elif x in ("-h", "--help"):
            usage()
            return 0
        else:
            raise Fatal(2, "unknown arg: %s" % x)
    if not os.path.isdir(root):
        raise Fatal(2, "no such root: %s" % root)
    ROOT = root
    scratch = os.environ.get("FULL_SUITE_TMPDIR") or os.environ.get("TMPDIR") or "/tmp"
    if not os.path.isabs(scratch) or not os.path.isdir(scratch):
        raise Fatal(2, "scratch dir %r is not an existing absolute directory" % scratch)
    manifest = manifest or os.path.join(root, "config", "full_suite_manifest.tsv")
    known = known or os.path.join(root, "config", "full_suite_known_failures.tsv")
    if only:
        try:
            rx = re.compile(only)
        except re.error as e:
            raise Fatal(2, "bad --only regex: %s" % e)
    lockfd = None
    running = not (gen or verify_only or lst or sync)
    if outdir and running:
        outdir = os.path.realpath(outdir)
        if outdir == root or outdir.startswith(root + os.sep):
            raise Fatal(2, "--out %s is inside the repository root; suites that scan the tree could read the logs" % outdir)
        lockfd = lock_out(outdir)

    census_needle(scratch)
    if gen:
        existing = {}
        if os.path.isfile(manifest):
            existing = {r[0]: r for r in read_manifest(manifest)}
        rows = generate(root, existing)
        if write:
            os.makedirs(os.path.dirname(manifest), exist_ok=True)
            write_manifest(manifest, rows)
            out("wrote %s (%d rows)" % (manifest, len(rows)))
        else:
            sys.stdout.write(MANIFEST_HEADER)
            for r in rows:
                out("\t".join(r))
        return 0
    rows = read_manifest(manifest)
    if sync:
        guide_check(root, rows, fix=True)
        out("guide census block: %s" % guide_block(rows))
        return 0
    probs = verify(root, rows)
    cline = census_line(rows)
    if probs:
        for p in probs:
            err("MANIFEST: " + p)
        out(cline)
        out("RESULT: MANIFEST-MISMATCH (%d problem(s); nothing was run)" % len(probs))
        return 3
    if verify_only:
        out(cline)
        out("RESULT: MANIFEST-OK")
        return 0
    units = plan(rows, heavy)
    if lst:
        out(cline)
        for u in units:
            out("%s %s%s" % ("RUN" if u["run"] else "SKIPPED-heavy", u["id"], "" if u["run"] else "  (%s)" % u["why"]))
        out("units=%d run=%d skipped_heavy=%d mode=%s" % (len(units), sum(u["run"] for u in units),
                                                          sum(not u["run"] for u in units), "full" if heavy else "default"))
        return 0

    sha = git(root, "rev-parse", "HEAD", check=False).strip() or "nogit"
    tree = tree_state(root)
    with open(os.path.abspath(__file__), "rb") as fh:
        rhash = hashlib.sha256(fh.read()).hexdigest()[:16]
    ctx = hashlib.sha256(b"manifest\0" + file_bytes(manifest) + b"\0known\0" + file_bytes(known)).hexdigest()[:16]
    if not outdir:
        base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.environ.get("HOME", "/nonexistent"), ".cache")
        outdir = os.path.realpath(os.path.join(base, "full_suite_runner", "%s-%s-%s" % (os.path.basename(root), sha[:12], tree[:12])))
        if outdir == root or outdir.startswith(root + os.sep):
            raise Fatal(2, "--out %s is inside the repository root" % outdir)
        lockfd = lock_out(outdir)
    res = Results(os.path.join(outdir, "results.jsonl"))
    known_rows, known_state = load_known(known)
    gomodcache = ""
    if any(u["runner"] == "go-test" and u["run"] for u in units):
        p = subprocess.run(["go", "env", "GOMODCACHE"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        gomodcache = p.stdout.decode().strip()

    def key_ok(o, u):
        return (o["unit"] == u["id"] and o["sha"] == sha and o["tree"] == tree and o["runner_hash"] == rhash
                and o["ctx"] == ctx)

    mode = "full" if heavy else "default"
    out("full-suite runner  sha=%s tree=%s ctx=%s mode=%s out=%s" % (sha[:12], tree[:12], ctx, mode, outdir))
    out(cline)
    total = len(units)
    interrupted = False

    def emit(u, verdict, reason, source, rc, secs, leaked, env_names, counts, logrel, logsha):
        res.append({"schema": SCHEMA, "unit": u["id"], "path": u["path"], "args": u["args"], "sha": sha, "tree": tree,
                    "ctx": ctx, "runner_hash": rhash, "mode": mode, "verdict": verdict, "reason": reason,
                    "verdict_source": source, "rc": rc, "secs": secs, "timeout": u.get("tmo", 0), "log": logrel,
                    "log_sha256": logsha, "leaked": leaked, "env_names": env_names, "counts": counts or {},
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})

    def handler(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, handler)
    try:
        for n, u in enumerate(units, 1):
            if not u["run"]:
                if not any(key_ok(o, u) and o["verdict"] == "SKIPPED-heavy" for o in res.recs):
                    emit(u, "SKIPPED-heavy", u["why"], "plan", 0, 0, 0, [], None, "", "")
                out("[%d/%d] SKIPPED-heavy %s  (%s)" % (n, total, u["id"], u["why"]))
                continue
            if only and not rx.search(u["id"]):
                continue
            prior = [o for o in res.recs if key_ok(o, u) and o["verdict"] in EXECUTED]
            if prior:
                lv = prior[-1]["verdict"]
                if not (rerun and lv != "PASS"):
                    out("[%d/%d] resumed %s (%s)" % (n, total, u["id"], lv))
                    continue
            t = tmo * 2 if u["runner"] in ("go-test",) or u["path"].endswith("run_all.sh") else tmo
            u["tmo"] = t
            logrel = "logs/%06d.log" % len(res.recs)
            rc, timed_out, secs, leaked, env_names, tail, overflow, logsha = run_unit(
                u, t, os.path.join(outdir, logrel), scratch, extras, gomodcache, cap_mb << 20)
            if overflow and not timed_out:
                verdict, reason, source, counts = "ERROR", "log_overflow", "runner-log-cap", None
            else:
                verdict, reason, source, counts = judge(rc, timed_out, tail, u["runner"])
            emit(u, verdict, reason, source, rc, secs, leaked, env_names, counts, logrel, logsha)
            out("[%d/%d] %s%s %s %ss%s" % (n, total, verdict, " (%s)" % reason if reason else "", u["id"], secs,
                                            " leaked=%d" % leaked if leaked else ""))
    except KeyboardInterrupt:
        interrupted = True
        out("INTERRUPTED: stopping; the summary below is partial")

    # ---------------------------------------------------------------- summary
    cats = {v: 0 for v in VERDICTS}
    lines = []
    exit_only = known_n = leaks = bad = nondet = 0
    for u in units:
        if not u["run"]:
            cats["SKIPPED-heavy"] += 1
            continue
        mine = [o for o in res.recs if key_ok(o, u) and o["verdict"] in EXECUTED]
        if not mine:
            cats["NOT-RUN"] += 1
            lines.append("NOT-RUN  %s" % u["id"])
            continue
        o = max(mine, key=lambda r: (RANK[r["verdict"]], r["seq"]))  # worst verdict; a resume never upgrades
        flip = len(set(r["verdict"] for r in mine)) > 1
        v = o["verdict"]
        cats[v] += 1
        kid = ""
        if v in BAD:
            lp = os.path.join(outdir, o["log"])
            body = file_bytes(lp)
            if hashlib.sha256(body).hexdigest() == o["log_sha256"]:
                kid = match_known(known_rows, u["path"], o["reason"], body.decode("utf-8", errors="replace"))
            elif known_rows:
                err("WARN: log %s does not match its recorded sha256; KNOWN not applied" % lp)
        if v == "PASS" and o["verdict_source"] == "exit-code-only":
            exit_only += 1
        if kid and not flip:
            known_n += 1
        elif v in BAD or flip:
            bad += 1
        if flip:
            nondet += 1
        leaks += sum(r["leaked"] for r in mine)
        if v != "PASS" or o["verdict_source"] == "exit-code-only" or flip:
            tag = " [KNOWN %s]" % kid if kid and not flip else ""
            src = " [exit-code-only]" if v == "PASS" else ""
            nd = " [NONDETERMINISTIC: %s]" % "/".join(r["verdict"] for r in mine) if flip else ""
            lines.append("%s%s%s%s  %s  (%s) %s" % (v, tag, src, nd, u["id"], o["reason"], o["log"]))
    if sum(cats.values()) != total:
        raise Fatal(2, "internal: category counts %d != units %d" % (sum(cats.values()), total))
    tree_end = tree_state(root)
    summ = ["full-suite summary  sha=%s tree=%s ctx=%s mode=%s root=%s" % (sha, tree, ctx, mode, root),
            cline,
            "units=%d (run in this mode=%d, heavy not run=%d); known-failures table: %s (%s)"
            % (total, sum(u["run"] for u in units), sum(not u["run"] for u in units), known_state, known)]
    for v in VERDICTS:
        summ.append("%-14s %d" % (v, cats[v]))
    summ.append("PASS with verdict_source=exit-code-only (no suite summary recognised): %d" % exit_only)
    summ.append("KNOWN (failing, matched to an open row of the CURRENT table): %d" % known_n)
    summ.append("NONDETERMINISTIC (records of one key disagree; the worst verdict counts): %d" % nondet)
    summ.append("leaked processes killed after their unit: %d" % leaks)
    if tree_end != tree:
        summ.append("TREE CHANGED during the run (start %s, end %s): a suite wrote into the repository" % (tree[:12], tree_end[:12]))
    summ.append("--- non-PASS, nondeterministic and exit-code-only units")
    summ.extend(lines)
    with open(os.path.join(outdir, "summary.txt"), "w") as fh:
        fh.write("\n".join(summ) + "\n")
    out("\n".join(summ))
    tail = "SKIP=%d exit-code-only-PASS=%d KNOWN=%d NONDETERMINISTIC=%d" % (cats["SKIP"], exit_only, known_n, nondet)
    nf = " -- not a section 11.4.40 full retest"
    if bad:
        out("RESULT: FAIL (%d unexplained FAIL/TIMEOUT/ERROR/NONDETERMINISTIC; %s)" % (bad, tail))
        return 1
    if tree_end != tree:
        out("RESULT: FAIL (repository tree changed during the run; %s)" % tail)
        return 1
    if interrupted or cats["NOT-RUN"]:
        out("RESULT: PARTIAL-NOT-RUN (%d unit(s) not run%s; %s)%s"
            % (cats["NOT-RUN"], ", interrupted" if interrupted else "", tail, nf))
        return 4
    if cats["SKIPPED-heavy"]:
        out("RESULT: PARTIAL-DEFAULT-SET (%d heavy unit(s) NOT run; %s)%s; run with --include-heavy"
            % (cats["SKIPPED-heavy"], tail, nf))
        return 5
    if cats["SKIP"]:
        out("RESULT: PARTIAL-SKIPS (%d unit(s) SKIPPED, listed in summary.txt; %s)%s" % (cats["SKIP"], tail, nf))
        return 6
    out("RESULT: PASS-FULL (every unit run, none skipped, no unexplained FAIL/TIMEOUT/ERROR; %s)" % tail)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Fatal as e:
        err("run_full_suite: %s" % e)
        if e.code == 3:
            out("RESULT: MANIFEST-MISMATCH (%s)" % e)
        sys.exit(e.code)
