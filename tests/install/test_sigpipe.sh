#!/usr/bin/env bash
# test_sigpipe.sh — regression test for CON-PENDING-INSTALLER-SIGPIPE: bash features that can silently change what
# the install scripts decide. Five classes, one rule each (docs/qa/installer_sigpipe_2026_11_13/round2/README.md):
#   (a) no writable temporary file: no here-string and no here-document in the scripts' code (bash keeps those in a
#       temporary file; when it cannot be written the command is skipped and a check reads as passed)
#   (b) the caller's shell: BASH_COMPAT, POSIXLY_CORRECT, SHELLOPTS, BASHOPTS, CDPATH, GLOBIGNORE, TMOUT never change
#       a decision: hi_reset_shell_state runs first when a script is RUN (a test that sources it keeps its shell)
#   (c) pipefail + SIGPIPE: no pipe into a reader that can exit before it has read all of its input
#   (d) errexit off (a function called as `f || rc=1`): a step whose failure matters is checked explicitly
#   (e) large input: text is split and compared inside the shell, at any size
#
# Sections:
#   1. static scan, classes (a) and (c): the scanner below (sigscan, run with python3 -I) reads the six scripts
#      token by token and reports every here-string, here-document and pipe whose reader is not known to read all
#      of its input (deny by default). Control needles: every known spelling of the class is flagged and the safe
#      forms are not; a violation appended to each file is found and printed with its original line; a file the
#      scanner cannot lex is reported as blind (exit 2), never as clean.
#   2. class (b): one hi_reset_shell_state text in the four files that carry it, called before anything else when
#      the file is run; it undoes what a caller changed; a sourced copy keeps the caller's shell; with any of the
#      variables above in the environment, the installer prints exactly what a clean run prints.
#   3. hi_push_changed (the no-push check), real installer in library mode, under three conditions: a writable
#      temporary directory; no writable temporary file with BASH_COMPAT=50 (what bash 5.0 does); the same with
#      BASH_COMPAT=44 (bash 4.4). A control needle per condition: a here-string must fail where no temporary file
#      can be written. Fifteen cases from both sides (unchanged, R moved / new, L changed / unaskable, N removed /
#      added, V changed, Z before only / after only / both / with M lines that differ, M lines that differ, U before)
#      on small, mid (about 14 KB per mark, above bash's 8 KiB pipe limit) and large marks; three runs, identical.
#   4. the other helpers, under the same three conditions: hi_legacy_path_in, hi_has_line_prefix, hi_line_in,
#      hi_upstream_ok, hi_resolve_ref_in ("1.0" is not "1.00"), hi_on_remote, and the updater's
#      up_hook_declares_project_root (checked against the regex the updater used before).
#   5. differential fuzz: hi_read_fields against `read -r`, hi_split against `IFS=sep read -r -a`, hi_split_lines
#      against a read loop, hi_line_in against `grep -qxF`, hi_has_line_prefix against awk index().
#   6. ref names and urls carrying $(...) and backticks: compared as data, never run.
#   7. class (d), CLI installer: a link that cannot be created is counted, reported and fails the step; a clean run
#      and a run with SHELLOPTS=noglob link the same skills.
#   8. behavioural paired mutants: each must misread at least one case of sections 2 and 3 (proves those cases
#      discriminate) and, where it brings back a forbidden form, be flagged by the static scan.
#
# TEST-CLASS LABEL (§11.4.289): gate-logic / unit class. No network, no agent; the marks are constructed strings fed
# to the real functions, and the "no temporary file" condition is emulated with `ulimit -f 0` (writes to regular
# files fail) inside a subshell. This is not live evidence of an agent run.
# Usage: bash tests/install/test_sigpipe.sh   Exit 0 all pass · 1 a case failed.
# shellcheck disable=SC1090,SC1003,SC2016  # the files under test are sourced by variable; quoted needle and mutant text is literal on purpose
# shellcheck disable=SC2034  # T_NAME is read by finish() in lib.sh
T_NAME=sigpipe
# shellcheck source=lib.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox

CLI="$REPO/scripts/install_cli_agent_plugins.sh"
PREFIX="$REPO/scripts/install_action_prefix.sh"
SCRIPTS=("$INSTALLER" "$UPDATER" "$CLI" "$PREFIX" "$REPO/scripts/portable_symlink_lib.sh" "$REPO/scripts/lib/constitution_layout.sh")
ALLOW=hi_text_filter,hi_scrub,hi_mark_hash,hi_newest_tag   # functions verified to read all of their input
nl=$'\n'
has() { case "$1" in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }
rel() { printf '%s' "${1#"$REPO"/}"; }

# ── the scanner (identical to docs/qa/installer_sigpipe_2026_11_13/round2/tools/sigscan.py) ──
# shellcheck disable=SC2016  # Python source: nothing in it is meant to expand
prog='import bisect, re, sys

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


sys.exit(main(sys.argv[1:]))'
scan() { python3 -I -c "$prog" --allow-func "$ALLOW" "$@"; }   # → FILE:LINE: CLASS detail | original line
scan_lines() { scan "$@" | cut -d: -f2 | sort -n | tr '\n' ' ' | sed 's/ $//'; }

echo "# 1. static scan, classes (a) and (c)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "  SKIP static scan: python3 is not on PATH (reason: tool_not_present; the scan did NOT run)"
else
  N="$SB/needles.sh"
printf '%s\n' \
  'printf '\''%s\n'\'' "$x" | grep -q y' \
  'x | LC_ALL=C grep -q y' \
  'x | grep -m1 y >/dev/null' \
  'x |& grep -q y' \
  'x | egrep -q y' \
  'x | command grep -q y' \
  'x | \grep -q y' \
  'x | fgrep -q y' \
  'x | head -n1' \
  'x | awk '\''/y/ { print; exit }'\''' \
  'x | sed -n '\''/y/{p;q}'\''' \
  'x | grep --quiet y' \
  'x | grep -l y' \
  'x | some_unknown_command' \
  'v="$(x | grep -q y)"' \
  'x | while read -r l; do break; done' \
  'x | sort -c' \
  'grep -q y <<<"$x"' \
  'cat <<EOF' \
  'body | grep -q not-code' \
  'EOF' \
  'x \' \
  '  | grep -q y' \
  'x |' \
  '  grep -q y' \
  'case a in a|b) : ;; esac' \
  'echo $(( 1 | 2 ))' \
  '[[ a == b || c == d ]] && :' \
  'false || grep -q y file' \
  '# x | grep -q y' \
  'echo '\''x | grep -q y'\''' \
  'echo "x | grep -q y"' \
  'x | awk '\''{ n++ } END { print n; exit }'\''' \
  'x | sed -n p' \
  'x | grep -c y' \
  'x | while read -r l; do :; done' \
  'x | hi_scrub' \
  'x | cat' \
  'x | LC_ALL=C sort -u' \
  'x | timeout 5 grep -q y' \
  'x | env LC_ALL=C grep -q y' \
  'x | tail -n 1' >"$N"
  out="$(scan "$N")"; rc=$?
  expect="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 23 24 40 41"
  eq "needles: the scanner flags every known spelling and no safe form (42 needle lines)" "$expect" "$(scan_lines "$N")"
  eq "needles: exit 1 when something is found" 1 "$rc"
  eq "needles: one finding per flagged line" "$(printf '%s\n' "$expect" | wc -w | tr -d ' ')" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  printf 'echo "never closed\n' >"$SB/unlexable.sh"
  out="$(scan "$SB/unlexable.sh")"; rc=$?
  eq "needle: a file the scanner cannot read is reported blind (exit 2), never clean" "2 1" "$rc $(has "$out" 'cannot lex')"
  # shellcheck disable=SC2016  # the appended needle is literal on purpose
  needle='printf '"'"'%s\n'"'"' "$x" | LC_ALL=C grep -q '"'"'needle text'"'"
  for f in "${SCRIPTS[@]}"; do
    [ -f "$f" ] || { nok "scan target exists: $(rel "$f")"; continue; }
    out="$(scan "$f")"; rc=$?
    if [ "$rc" = 0 ] && [ -z "$out" ]; then ok "no here-string, here-document or early reader in $(rel "$f")"
    else nok "$(rel "$f") (scan exit $rc): $out"; fi
    { cat "$f"; printf '\n%s\n' "$needle"; } >"$SB/needle_copy"
    n="$(wc -l <"$SB/needle_copy" | tr -d ' ')"
    out="$(scan "$SB/needle_copy")"
    eq "needle appended to $(rel "$f"): exactly one finding, at its line, printed with the original line" \
      "1 $n 1" "$(printf '%s\n' "$out" | grep -c .) $(printf '%s' "$out" | cut -d: -f2) $(has "$out" "| $needle")"
  done
fi

echo "# 2. class (b): the caller's shell state"
fn_text() { awk '/^hi_reset_shell_state\(\) \{$/ { on = 1 } on { print } on && /^}$/ { exit }' "$1"; }
ref_fn="$(fn_text "$INSTALLER")"
if [ -n "$ref_fn" ]; then ok "hi_reset_shell_state found in the installer"; else nok "hi_reset_shell_state found in the installer"; fi
for f in "$UPDATER" "$CLI" "$PREFIX"; do
  eq "hi_reset_shell_state in $(rel "$f") is identical to the installer's" "$ref_fn" "$(fn_text "$f")"
done
blk() { awk '/^# >>> hi_shell_state /{ on = 1 } on { print } /^# <<< hi_shell_state/ { exit }' "$1"; }
eq "the hi_shell_state block is identical in the installer and the updater" "$(blk "$INSTALLER")" "$(blk "$UPDATER")"
for f in "$INSTALLER" "$UPDATER"; do
  c="$(grep -n '^\[ "\${HI_SOURCED:-0}" = 1 \] || hi_reset_shell_state' "$f" | cut -d: -f1)"
  s="$(grep -n '^HI_SOURCED=0; (return 0 2>/dev/null) && HI_SOURCED=1' "$f" | cut -d: -f1)"
  p="$(grep -n '^[^#]*<(' "$f" | head -n 1 | cut -d: -f1)"
  if [ -n "$c" ] && [ -n "$s" ] && [ -n "$p" ] && [ "$s" -lt "$c" ] && [ "$c" -lt "$p" ]; then
    ok "$(rel "$f"): HI_SOURCED set (line $s), reset called (line $c) before the first <( (line $p)"
  else nok "$(rel "$f"): HI_SOURCED line [$s], reset call [$c], first <( [$p]"; fi
done
# the /dev/fd boundary: process substitution is checked before the first one a run depends on (refuse, exit 3)
eq "the installer refuses (exit 3) when process substitution does not work" 1 \
  "$(grep -c '^    hi_plumbing_ok || { hi_err "process substitution does not work here.*exit 3; } ;;$' "$INSTALLER")"
eq "the updater refuses (exit 3) when process substitution does not work" 1 \
  "$(grep -c '^hi_plumbing_ok || die 3 "process substitution does not work here' "$UPDATER")"
for f in "$CLI" "$PREFIX"; do
  eq "$(rel "$f"): reset called in run mode, right before set -euo pipefail" \
    "(return 0 2>/dev/null) || hi_reset_shell_state${nl}set -euo pipefail" \
    "$(grep -A1 '^(return 0 2>/dev/null) || hi_reset_shell_state$' "$f")"
done
state() { # → the shell state the reset must restore, one word per item
  printf '%s' "$-" | tr -d 'hBiclsr'; printf ' compat=%s posix=%s cdpath=%s globignore=%s tmout=%s' "${BASH_COMPAT-unset}" \
    "$(shopt -oq posix && echo on || echo off)" "${CDPATH-unset}" "${GLOBIGNORE-unset}" "${TMOUT-unset}"
  shopt nocasematch nocaseglob extglob nullglob failglob dotglob lastpipe xpg_echo expand_aliases | awk '{ printf " %s=%s", $1, $2 }'
}
clean_state="$(bash --norc -c "$(declare -f state); state" 2>&1)"
# shellcheck disable=SC2030,SC2031  # every change below lives in a subshell on purpose
got="$( HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER" >/dev/null 2>&1
  set -f -u -e; set -o posix; shopt -s nocasematch nocaseglob extglob nullglob failglob dotglob lastpipe xpg_echo expand_aliases
  BASH_COMPAT=44; CDPATH=/nonexistent; GLOBIGNORE='*'; TMOUT=7
  hi_reset_shell_state; state )"
eq "hi_reset_shell_state undoes what a caller changed (options, BASH_COMPAT, CDPATH, GLOBIGNORE, TMOUT)" "$clean_state" "$got"
for pair in "INSTALLER HELIX_INSTALLER_LIB_MODE" "UPDATER HELIX_UPDATER_LIB_MODE"; do
  v="${pair%% *}"; m="${pair#* }"
  got="$( shopt -s nocasematch; export "$m"=1; . "${!v}" >/dev/null 2>&1; shopt -q nocasematch && echo kept || echo reset )"
  eq "a SOURCED $(rel "${!v}") keeps the caller's shell" kept "$got"
done
HOSTILE=(POSIXLY_CORRECT=1 SHELLOPTS=posix SHELLOPTS=noglob:nounset SHELLOPTS=errexit
         BASHOPTS=nocasematch:extglob:failglob:nullglob BASH_COMPAT=44 CDPATH=/nonexistent GLOBIGNORE='*' TMOUT=1)
run_inst() { (cd "$SB" && env "$@" bash "$INSTALLER_RUN" "${ARGS[@]}" 2>&1; echo "rc=$?"); }
hostile_check() { # installer-file label → number of (flag, environment) pairs whose output differs from a clean run
  local a e n=0 clean
  INSTALLER_RUN="$1"
  for a in --version --help --print-snippets; do
    ARGS=("$a"); clean="$(run_inst LC_ALL=C)"
    for e in "${HOSTILE[@]}"; do
      [ "$(run_inst LC_ALL=C "$e")" = "$clean" ] || { n=$((n + 1)); [ -n "$2" ] && echo "    differs: $a with $e" >&2; }
    done
  done
  echo "$n"
}
eq "run with any of ${#HOSTILE[@]} inherited settings, the installer prints what a clean run prints (--version --help --print-snippets)" \
  0 "$(hostile_check "$INSTALLER" show)"

echo "# 3. hi_push_changed under three temporary-file conditions"
sha=0123456789abcdef0123456789abcdef01234567
sha2=1123456789abcdef0123456789abcdef01234567
tail_lines() { local j; for ((j = 0; j < $1; j++)); do printf 'R 0 refs/remotes/origin/x%s %s 1\n' "$j" "$sha"; done; }
base_mark() { # tail → before-marks of one repository with every kind of line, then a tail of fetched R lines
  printf 'D 0 /p\nM 0 refs/remotes/origin/main 1\nR 0 refs/remotes/origin/main %s 0\nN 0 origin\nL 0 origin sha256sum:aa\nV 0 sha256sum:bb https://h.invalid/r.git\n%s' "$sha" "$1"
}
case_marks() { # name tail → CB (before) CA (after)
  local m; m="$(base_mark "$2")"; CB="$m"; CA="$m"
  case "$1" in
    same) ;;
    r_moved) CA="${m/"main $sha 0"/"main $sha2 0"}" ;;
    r_new_fetched) CA="$m${nl}R 0 refs/remotes/origin/new $sha 2" ;;
    r_new_unfetched) CA="$m${nl}R 0 refs/remotes/origin/new $sha 0" ;;
    l_changed) CA="${m/"sha256sum:aa"/"sha256sum:cc"}" ;;
    l_unaskable) CA="${m/"L 0 origin sha256sum:aa"/"U 0 origin"}" ;;
    n_removed) CA="${m/"N 0 origin$nl"/}" ;;
    n_added) CA="$m${nl}N 0 upstream" ;;
    v_changed) CA="${m/"sha256sum:bb"/"sha256sum:dd"}" ;;
    z_before) CB="$m${nl}Z 0 origin" ;;
    z_after) CA="$m${nl}Z 0 origin" ;;
    z_both) CB="$m${nl}Z 0 origin"; CA="$CB" ;;
    z_m_differ) CB="$m${nl}Z 0 origin"; CA="${m/"main 1$nl"/"main 2$nl"}" ;;
    m_differ) CA="${m/"main 1$nl"/"main 2$nl"}" ;;
    u_before) CB="$m${nl}U 0 upstream" ;;
  esac
}
CASES="same r_moved r_new_fetched r_new_unfetched l_changed l_unaskable n_removed n_added v_changed z_before z_after z_both z_m_differ m_differ u_before"
expect_cases() { # names → the expected lines (rc, Z error printed, "could not be asked before" warning printed)
  local c
  for c in $1; do
    case "$c" in
      same|r_new_fetched|n_added) echo "$c=1 z=0 w=0" ;;
      u_before) echo "$c=1 z=0 w=1" ;;
      z_*) echo "$c=0 z=1 w=0" ;;
      *) echo "$c=0 z=0 w=0" ;;
    esac
  done
}
cond_on() { # condition → applied to the current (sub)shell
  case "$1" in
    normal) ;;
    notemp50) trap '' XFSZ; ulimit -f 0; BASH_COMPAT=50 ;;
    notemp44) trap '' XFSZ; ulimit -f 0; BASH_COMPAT=44 ;;
  esac
}
# control needle: a here-string of 100 KB (above every pipe buffer, so bash must use a temporary file) fails
# exactly where no temporary file can be written
printf -v BIGX '%*s' 100000 ''; BIGX="${BIGX// /x}"
ctl_here() { if { grep -q x <<<"$BIGX"; } 2>/dev/null; then echo here-string-ok; else echo here-string-failed; fi; }
small_here() { if { grep -q x <<<"x"; } 2>/dev/null; then echo ok; else echo failed; fi; }
expect_ctl() { case "$1" in normal) echo "ctl=here-string-ok" ;; *) echo "ctl=here-string-failed" ;; esac; }
push_run() { # installer condition tail-lines names → ctl line + one line per case
  ( HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1 || { echo "source=failed"; exit 0; }
    set -u -o pipefail
    local T="" c out rc
    [ "$3" -gt 0 ] && T="$(tail_lines "$3")"
    cond_on "$2"
    echo "ctl=$(ctl_here)"
    for c in $4; do
      case_marks "$c" "$T"
      out="$(hi_push_changed "$CB" "$CA" 2>&1)"; rc=$?
      echo "$c=$rc z=$(has "$out" 'no cksum or sha256sum') w=$(has "$out" 'could not be asked before')"
    done ) 2>&1
}
for cond in normal notemp50 notemp44; do
  echo "  info: $cond: a SMALL here-string $( (cond_on "$cond"; small_here) ) under bash $BASH_VERSION (not a check: bash 5.1 uses a pipe for it even with BASH_COMPAT=50)"
  for size in 0 200; do
    want="$(expect_ctl "$cond")$nl$(expect_cases "$CASES")"
    r1="$(push_run "$INSTALLER" "$cond" "$size" "$CASES")"; r2="$(push_run "$INSTALLER" "$cond" "$size" "$CASES")"
    r3="$(push_run "$INSTALLER" "$cond" "$size" "$CASES")"
    eq "$cond, $size tail lines: control needle and all 15 cases" "$want" "$r1"
    eq "$cond, $size tail lines: runs 1, 2 and 3 identical" "$r1|$r1|$r1" "$r1|$r2|$r3"
  done
done
LARGE="same z_before z_after r_moved"
for cond in normal notemp50; do
  r1="$(push_run "$INSTALLER" "$cond" 2000 "$LARGE")"
  eq "$cond, 2000 tail lines (about 136 KB per mark): $LARGE" "$(expect_ctl "$cond")$nl$(expect_cases "$LARGE")" "$r1"
done

echo "# 4. the other helpers under the same conditions"
filler() { local j; for ((j = 0; j < $1; j++)); do printf 'line %s of text that names no path\n' "$j"; done; }
if ! { git init -q "$SB/rr" && git -C "$SB/rr" commit -q --allow-empty -m a && A="$(git -C "$SB/rr" rev-parse HEAD)" \
  && git -C "$SB/rr" commit -q --allow-empty -m b && B="$(git -C "$SB/rr" rev-parse HEAD)" \
  && git -C "$SB/rr" checkout -q --orphan other && git -C "$SB/rr" commit -q --allow-empty -m c \
  && C="$(git -C "$SB/rr" rev-parse HEAD)"; }; then nok "fixture repository for hi_resolve_ref_in / hi_on_remote"; fi
helper_run() { # installer condition → one line per helper case
  ( HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1 || { echo "source=failed"; exit 0; }
    set -u -o pipefail; exec 9>&2
    local big; big="$(filler 2000)"
    cond_on "$2"
    t() { local n="$1"; shift; "$@" >/dev/null 2>&1; echo "$n=$?"; }
    t lp1 hi_legacy_path_in 'see constitution/x'
    t lp2 hi_legacy_path_in 'see submodules/constitution/x'
    t lp3 hi_legacy_path_in 'a/constitution/x'
    t lp4 hi_legacy_path_in 'myconstitution/x'
    t lp5 hi_legacy_path_in '_constitution/x'
    t lp6 hi_legacy_path_in '(constitution/x)'
    t lp7 hi_legacy_path_in 'constitution/x and submodules/constitution/y'
    t lp8 hi_legacy_path_in "ok${nl}see constitution/x"
    t lp9 hi_legacy_path_in "$big${nl}constitution/x"
    t lp10 hi_legacy_path_in "$big"
    t lp11 hi_legacy_path_in 'Constitution/x'
    t hp1 hi_has_line_prefix '160000 abc' '160000 '
    t hp2 hi_has_line_prefix "100644 x${nl}160000 y" '160000 '
    t hp3 hi_has_line_prefix 'x160000 y' '160000 '
    t hp4 hi_has_line_prefix '' '160000 '
    t hp5 hi_has_line_prefix '160000' '160000 '
    t hp6 hi_has_line_prefix "$big${nl}160000 y" '160000 '
    t li1 hi_line_in b "a${nl}b${nl}c"
    t li2 hi_line_in b "a${nl}bb${nl}c"
    t li3 hi_line_in 'a b' "x${nl}a b"
    t li4 hi_line_in z "$big${nl}z"
    t uo1 hi_upstream_ok github
    t uo2 hi_upstream_ok gitlab-vasic
    t uo3 hi_upstream_ok gitflic
    t uo4 hi_upstream_ok git
    t uo5 hi_upstream_ok GitHub
    t uo6 hi_upstream_ok ''
    t uo7 hi_upstream_ok 'github|x'
    echo "rr1=$(hi_resolve_ref_in "$SB/rr" 1.0 "1.00 $A${nl}1.0 $B" 2>&1)"
    echo "rr2=$(hi_resolve_ref_in "$SB/rr" 1.00 "1.00 $A${nl}1.0 $B" 2>&1)"
    t or1 hi_on_remote "$SB/rr" "$A" "$B"
    t or2 hi_on_remote "$SB/rr" "$C" "$B"
    t or3 hi_on_remote "$SB/rr" "$B" "$C${nl}$B"
    t or4 hi_on_remote "$SB/rr" "not-a-sha" "$B" ) 2>&1
}
HELPER_WANT="$(printf '%s\n' lp1=0 lp2=1 lp3=1 lp4=1 lp5=1 lp6=0 lp7=1 lp8=0 lp9=0 lp10=1 lp11=1 \
  hp1=0 hp2=0 hp3=1 hp4=1 hp5=1 hp6=0 li1=0 li2=1 li3=0 li4=0 uo1=0 uo2=0 uo3=0 uo4=1 uo5=1 uo6=1 uo7=1 \
  "rr1=remote-tag ${B:-}" "rr2=remote-tag ${A:-}" or1=0 or2=1 or3=0 or4=1)"
hook_run() { # condition → one line per case of the updater's capability probe
  ( HELIX_UPDATER_LIB_MODE=1 . "$UPDATER" >/dev/null 2>&1 || { echo "source=failed"; exit 0; }
    set -u -o pipefail
    local big head; big="$(filler 2000)"; head="$(head -n 80 -- "$REPO/scripts/post_update_hook.sh")"
    cond_on "$1"
    t() { local n="$1"; shift; "$@" >/dev/null 2>&1; echo "$n=$?"; }
    t hk1 up_hook_declares_project_root '# HELIX_HOOK_CAPABILITIES: project-root'
    t hk2 up_hook_declares_project_root '#HELIX_HOOK_CAPABILITIES: a project-root b'
    t hk3 up_hook_declares_project_root '# HELIX_HOOK_CAPABILITIES: project-rootx'
    t hk4 up_hook_declares_project_root ' # HELIX_HOOK_CAPABILITIES: project-root'
    t hk5 up_hook_declares_project_root '# HELIX_HOOK_CAPABILITIES: xproject-root'
    t hk6 up_hook_declares_project_root "$big${nl}# HELIX_HOOK_CAPABILITIES: project-root"
    t hk7 up_hook_declares_project_root "$big"
    t hk8 up_hook_declares_project_root "$head" ) 2>&1
}
HOOK_RE='^#[[:space:]]*HELIX_HOOK_CAPABILITIES:([^[:cntrl:]]*[[:space:]])?project-root([[:space:]]|$)'
re_rc() { LC_ALL=C grep -qE "$HOOK_RE" <<<"$1"; echo $?; }
big_ref="$(filler 2000)"
HOOK_WANT="hk1=$(re_rc '# HELIX_HOOK_CAPABILITIES: project-root')
hk2=$(re_rc '#HELIX_HOOK_CAPABILITIES: a project-root b')
hk3=$(re_rc '# HELIX_HOOK_CAPABILITIES: project-rootx')
hk4=$(re_rc ' # HELIX_HOOK_CAPABILITIES: project-root')
hk5=$(re_rc '# HELIX_HOOK_CAPABILITIES: xproject-root')
hk6=$(re_rc "$big_ref${nl}# HELIX_HOOK_CAPABILITIES: project-root")
hk7=$(re_rc "$big_ref")
hk8=$(re_rc "$(head -n 80 -- "$REPO/scripts/post_update_hook.sh")")"
eq "the reference regex: the shipped hook declares project-root, the near misses do not" "0 0 1 1 1 0 1 0" \
  "$(printf '%s\n' "$HOOK_WANT" | cut -d= -f2 | tr '\n' ' ' | sed 's/ $//')"
for cond in normal notemp50 notemp44; do
  eq "$cond: installer helpers" "$HELPER_WANT" "$(helper_run "$INSTALLER" "$cond")"
  eq "$cond: updater up_hook_declares_project_root agrees with the regex it replaces" "$HOOK_WANT" "$(hook_run "$cond")"
done

echo "# 5. differential fuzz against the bash builtins and grep / awk"
fuzz_run() {
  ( HELIX_INSTALLER_LIB_MODE=1 . "$1" >/dev/null 2>&1 || { echo "source=failed"; exit 0; }
    local -a ch=(a b ' ' $'\t' '\' '*' '?' '[' ']' '$' "'" '"' '&' '/' '-' '!' '(' ')' '{' '}' '~' '#' '%' $'\r' 'é' x y)
    local i j n s s2 m p bad=0 cnt=0 r g v1 v2 v3 v4 sep l
    local -a arr=() ref=()
    jn() { local IFS=$'\x1f'; printf '%s' "$*"; }
    miss() { bad=$((bad + 1)); [ "$bad" -le 3 ] && printf 'mismatch %s: %q ref=%q got=%q\n' "$1" "$2" "$3" "$4"; }
    rnd() { local k; s=""; for ((k = 0; k < $1; k++)); do s+="${ch[RANDOM % ${#ch[@]}]}"; done; }
    RANDOM=20261113
    for ((i = 0; i < 250; i++)); do
      rnd $((RANDOM % 14)); s2="$s"
      v1="" v2="" v3="" v4=""
      IFS=$' \t\n' read -r v1 <<<"$s2"; r="$(jn "$v1")"; hi_read_fields "$s2" 1; g="$(jn "${HI_F[@]}")"
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss read1 "$s2" "$r" "$g"
      IFS=$' \t\n' read -r v1 v2 <<<"$s2"; r="$(jn "$v1" "$v2")"; hi_read_fields "$s2" 2; g="$(jn "${HI_F[@]}")"
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss read2 "$s2" "$r" "$g"
      IFS=$' \t\n' read -r v1 v2 v3 <<<"$s2"; r="$(jn "$v1" "$v2" "$v3")"; hi_read_fields "$s2" 3; g="$(jn "${HI_F[@]}")"
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss read3 "$s2" "$r" "$g"
      IFS=$' \t\n' read -r v1 v2 v3 v4 <<<"$s2"; r="$(jn "$v1" "$v2" "$v3" "$v4")"; hi_read_fields "$s2" 4; g="$(jn "${HI_F[@]}")"
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss read4 "$s2" "$r" "$g"
      rnd $((RANDOM % 6)); s2="$s2$nl$s"
      for sep in '&' / $' \t\n'; do
        ref=(); IFS="$sep" read -r -a ref <<<"$s2"; r="$(jn ${ref[@]+"${ref[@]}"})"
        hi_split "$sep" "$s2"; g="$(jn ${HI_SPLIT[@]+"${HI_SPLIT[@]}"})"
        cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss "split[$sep]" "$s2" "$r" "$g"
      done
      m=""; for ((j = RANDOM % 5; j > 0; j--)); do rnd $((RANDOM % 5)); m+="$s$nl"; done; [ $((RANDOM % 2)) = 0 ] && m="${m%"$nl"}"
      ref=(); while IFS= read -r l || [ -n "$l" ]; do [ -n "$l" ] && ref+=("$l"); done <<<"$m"
      r="$(jn ${ref[@]+"${ref[@]}"})"; hi_split_lines "$m"; g="$(jn ${HI_LINES[@]+"${HI_LINES[@]}"})"
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss split_lines "$m" "$r" "$g"
      rnd $((RANDOM % 4 + 1)); p="$s"; [ $((RANDOM % 3)) = 0 ] && m="$m$nl$p"
      LC_ALL=C grep -qxF -- "$p" <<<"$m"; r=$?; hi_line_in "$p" "$m"; g=$?
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss line_in "$p|$m" "$r" "$g"
      P="$p" LC_ALL=C awk 'index($0, ENVIRON["P"]) == 1 { f = 1 } END { exit !f }' <<<"$m"; r=$?; hi_has_line_prefix "$m" "$p"; g=$?
      cnt=$((cnt + 1)); [ "$r" = "$g" ] || miss line_prefix "$p|$m" "$r" "$g"
    done
    echo "compared=$cnt mismatches=$bad" ) 2>&1
}
f1="$(fuzz_run "$INSTALLER")"
eq "2500 comparisons, no mismatch" "compared=2500 mismatches=0" "$(printf '%s\n' "$f1" | tail -n 1)"
[ "$(printf '%s\n' "$f1" | wc -l | tr -d ' ')" = 1 ] || printf '%s\n' "$f1" | head -n 3

echo "# 6. ref names and urls with \$(...) and backticks are data"
mk_hostile() { # sha → marks whose names carry command text
  # shellcheck disable=SC2016  # literal command text, never meant to run
  printf 'D 0 /p\nR 0 refs/remotes/origin/$(touch${IFS}%s/pwn1) %s 0\nR 0 refs/remotes/origin/`touch %s/pwn2` %s 0\nR 0 refs/remotes/origin/a]b %s 0\nR 0 refs/remotes/origin/* %s 0\nN 0 o$(touch${IFS}%s/pwn3)\nL 0 o`touch %s/pwn4` sha256sum:aa\nV 0 sha256sum:bb https://h.invalid/$(touch${IFS}%s/pwn5)\n' \
    "$SB" "$1" "$SB" "$1" "$1" "$1" "$SB" "$SB" "$SB"
}
H1="$(mk_hostile "$sha")"; H2="${H1/"pwn1) $sha 0"/"pwn1) $sha2 0"}"
for cond in normal notemp50; do
  got="$( HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER" >/dev/null 2>&1; set -u -o pipefail; cond_on "$cond"
    hi_push_changed "$H1" "$H1" >/dev/null 2>&1; a=$?; hi_push_changed "$H1" "$H2" >/dev/null 2>&1; echo "$a $?" )"
  eq "$cond: unchanged marks with command text read as unchanged, a moved ref as moved" "1 0" "$got"
done
eq "no command text was run (no pwn file in the sandbox)" 0 "$(find "$SB" -maxdepth 1 -name 'pwn*' | wc -l | tr -d ' ')"

echo "# 7. class (d): the CLI installer counts a link it cannot create"
P1="$SB/proj_rw"; P2="$SB/proj_ro"; P3="$SB/proj_noglob"
mkdir -p "$P1" "$P2/.claude/skills" "$P3"
n_skills="$(find "$REPO/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
o1="$(bash "$CLI" --project-root "$P1" --skills-only 2>&1)"; rc1=$?
eq "writable: exit 0, every skill linked, none failed" "0 $n_skills 1" \
  "$rc1 $(find "$P1/.claude/skills" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' ') $(has "$o1" ", 0 failed)")"
o3="$(env SHELLOPTS=noglob bash "$CLI" --project-root "$P3" --skills-only 2>&1)"; rc3=$?
eq "SHELLOPTS=noglob inherited: the same skills are linked (class b)" "0 $n_skills" \
  "$rc3 $(find "$P3/.claude/skills" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' ')"
if [ "$(id -u)" = 0 ]; then
  echo "  SKIP read-only link case: running as root, a read-only directory does not stop root (reason: topology_unsupported)"
else
  chmod 555 "$P2/.claude/skills"
  o2="$(bash "$CLI" --project-root "$P2" --skills-only 2>&1)"; rc2=$?
  chmod 755 "$P2/.claude/skills"
  eq "read-only .claude/skills: exit 1, every failure counted and warned, nothing linked" "1 $n_skills $n_skills 0" \
    "$rc2 $(printf '%s\n' "$o2" | grep -c 'could not link') $(printf '%s' "$o2" | sed -n 's/.*, \([0-9]*\) failed).*/\1/p') $(find "$P2/.claude/skills" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' ')"
fi

echo "# 8. behavioural paired mutants (each must misread a case above)"
mutate() { # source-file out-file old new → 0 when old occurs exactly once and was replaced
  local src; src="$(cat "$1")"
  local n=0 t="$src"
  while [[ "$t" == *"$3"* ]]; do n=$((n + 1)); t="${t#*"$3"}"; done
  [ "$n" = 1 ] || { nok "mutant anchor occurs once in $(rel "$1") (found $n): $3"; return 1; }
  printf '%s\n' "${src/"$3"/"$4"}" >"$2"
}
Z_SITE="if hi_has_line_prefix \"\$b\$nl\$a\" 'Z '; then"
# shellcheck disable=SC2016
LOOP_SITE='hi_split_lines "$a"; al=(${HI_LINES[@]+"${HI_LINES[@]}"})'
M="$SB/mut.sh"
if mutate "$INSTALLER" "$M" "$Z_SITE" "if hi_has_line_prefix \"\$b\" 'Z '; then"; then
  eq "mutant Z-reads-before-only: the after-only Z case misreads" "ctl=here-string-ok${nl}z_after=1 z=0 w=0" "$(push_run "$M" normal 200 z_after)"
fi
if mutate "$INSTALLER" "$M" "$Z_SITE" "if printf '%s\\n%s\\n' \"\$b\" \"\$a\" | grep -q '^Z '; then"; then
  eq "mutant Z-pipe: a large before-only Z case misreads (SIGPIPE under pipefail)" "ctl=here-string-ok${nl}z_before=1 z=0 w=0" "$(push_run "$M" normal 2000 z_before)"
  command -v python3 >/dev/null 2>&1 && eq "mutant Z-pipe: flagged by the static scan" 1 "$(scan "$M" | grep -c 'EARLY-READER')"
fi
if mutate "$INSTALLER" "$M" "$Z_SITE" "if grep -q '^Z ' <<<\"\$b\$nl\$a\"; then"; then
  eq "mutant Z-here-string: the Z case misreads with no temporary file" "ctl=here-string-failed${nl}z_before=1 z=0 w=0" "$(push_run "$M" notemp50 2000 z_before)"
  command -v python3 >/dev/null 2>&1 && eq "mutant Z-here-string: flagged by the static scan" 1 "$(scan "$M" | grep -c 'HERESTR')"
fi
if mutate "$INSTALLER" "$M" "$LOOP_SITE" 'al=(); while IFS= read -r line; do al+=("$line"); done <<<"$a"'; then
  eq "mutant loop-here-string: unchanged marks read as a push with no temporary file" "ctl=here-string-failed${nl}same=0 z=0 w=0" "$(push_run "$M" notemp50 2000 same)"
  command -v python3 >/dev/null 2>&1 && eq "mutant loop-here-string: flagged by the static scan" 1 "$(scan "$M" | grep -c 'HERESTR')"
fi
if mutate "$INSTALLER" "$M" '[ "${HI_SOURCED:-0}" = 1 ] || hi_reset_shell_state' ':'; then
  n="$(hostile_check "$M" "")"
  if [ "$n" -gt 0 ]; then ok "mutant no-reset: $n (flag, environment) pairs differ from a clean run"
  else nok "mutant no-reset: no hostile environment changed the output (the class (b) case does not discriminate)"; fi
fi
finish
