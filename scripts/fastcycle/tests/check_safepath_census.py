#!/usr/bin/env python3
"""check_safepath_census.py -- the closure-by-construction guard of the trusted-parent rule (T048 V4 round 12, V4R12-1,
§11.4.276(E) STRUCTURAL; docs/qa/v4_round6_20261012/CONVERGENCE.md).

It reads cycle/fc_supervisor.py and cycle/baseline_replay.sh (the files UNDER TEST: FC_SUP_UNDER_TEST /
FC_BR_UNDER_TEST, or --sup / --br) and classifies EVERY path operation in them. It FAILS (exit 1) when an operation is
found that is neither routed through the trusted-parent helpers nor covered by one of a CLOSED set of justified
exemptions -- so a path operation added later, outside the rule, breaks the suite the moment it is written (a lint,
not a review comment).

Python (AST, every call):
  path operations: os.{open, unlink, remove, rmdir, mkdir, makedirs, rename, replace, link, symlink, chmod, chown,
  lchown, truncate, listdir, scandir, mkfifo, mknod, stat, lstat, access, readlink, utime}, os.path.{exists, lexists,
  isdir, isfile, islink, getsize}, every shutil.* and tempfile.* call, the builtin open().
  ROUTED  -- the call acts relative to a proved directory fd: a dir_fd / src_dir_fd / dst_dir_fd keyword, or (listdir /
             scandir) a first argument that is an fd variable (a name ending in "fd").
  ROOT    -- os.open("/") inside _walk: the one place a walk starts.
  TAGGED  -- a `# safepath:<tag>` comment on the call's line, tag from the closed set below, each checked:
             procfs  the path is a literal / %-format starting "/proc/" (kernel-owned);
             devnull the path is os.devnull (the device is the intent);
             probe   a READ-ONLY query (os.path.*, os.stat, os.lstat, os.access) whose answer only words a message or
                     reads a filesystem id -- it opens, creates and removes nothing.
  anything else -> VIOLATION.
Shell (every line of code):
  path operations: the commands mkdir, rm, rmdir, mv, cp, ln, touch, mktemp, tee, `find ... -delete`, `git worktree
  add`, and every output redirection > / >> to a target that is not /dev/null or an fd (>&N).
  ROUTED  -- the operation is `_fc_safe ...` (the helper's own arguments are not operations).
  PRIVATE -- every variable in the operation's operands is PROVED: assigned only from `$(_fc_safe mkdtemp|mkdir ...)`,
             `$(_fc_mktemp)`, `$(mktemp ["-d"] "$<proved>/...")`, `${FC_BR_TMPDIR...}` (checked with `_fc_safe check
             --exclusive` at worker start), or a string built from a proved variable -- i.e. the target is inside a
             directory the helper made / proved (nobody else can create or rename an entry there). A function
             parameter is proved only through a `# safepath:param <why>` tag whose function and variable are listed in
             PARAMS below (each with the reason every caller passes a proved path).
  TAGGED  -- `# safepath:<tag>`: msg (the keyword appears only inside quoted text -- checked by removing the quoted
             text and requiring that no operation is left), param (above), devnull.
  anything else -> VIOLATION.
Output: one census row per operation (file, line, kind, verdict, reason) -- --markdown prints the table the
CONVERGENCE document embeds -- and a SUMMARY line. Exit 0 no violation, 1 at least one, 2 usage / unreadable input."""
import ast
import os
import re
import sys

PY_OPS = {"open", "unlink", "remove", "rmdir", "mkdir", "makedirs", "rename", "replace", "link", "symlink", "chmod",
          "chown", "lchown", "truncate", "listdir", "scandir", "mkfifo", "mknod", "stat", "lstat", "access",
          "readlink", "utime"}
PY_PATH_OPS = {"exists", "lexists", "isdir", "isfile", "islink", "getsize"}
PY_READONLY = {"stat", "lstat", "access"} | {"path." + x for x in PY_PATH_OPS}
PY_TAGS = {"procfs", "devnull", "probe"}
SH_TAGS = {"msg", "param", "devnull"}
# function parameters that carry a path, with the reason every caller passes a proved one (checked by name)
PARAMS = {
    ("_fc_ledger_add", "kind"): "a NAME component inside $_FC_TMPDIR: every caller passes the literal wt, pend or logs",
    ("run_replay_isolated", "body_file"): "both callers (cmd_replay, cmd_replay_sample) pass a $(_fc_mktemp) file",
    ("_fc_run_child", "log"): "callers pass a $(_fc_mktemp) file, a $run_log_dir/... file (a helper-made run-log "
                              "directory) or /dev/null",
}
SH_CMDS = ("mkdir", "rm", "rmdir", "mv", "cp", "ln", "touch", "mktemp", "tee", "cat", "head", "tail")
TAG_RE = re.compile(r"#\s*safepath:(\w+)")


def py_census(path):
    src = open(path).read()
    lines = src.split("\n")
    tree = ast.parse(src)
    rows = []
    # every node -> its innermost enclosing function (ast.walk is breadth-first: an inner def is visited after its
    # outer one, so its assignment wins)
    func_of = {}
    for fn in ast.walk(tree):
        if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for n in ast.walk(fn):
                func_of[id(n)] = fn.name
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = None
        f = node.func
        if isinstance(f, ast.Name) and f.id == "open":
            name = "builtin open"
        elif isinstance(f, ast.Attribute):
            v = f.value
            if isinstance(v, ast.Name) and v.id == "os" and f.attr in PY_OPS:
                name = "os." + f.attr
            elif isinstance(v, ast.Attribute) and isinstance(v.value, ast.Name) and v.value.id == "os" \
                    and v.attr == "path" and f.attr in PY_PATH_OPS:
                name = "os.path." + f.attr
            elif isinstance(v, ast.Name) and v.id in ("shutil", "tempfile"):
                name = v.id + "." + f.attr
        if name is None:
            continue
        line = lines[node.lineno - 1]
        kws = {k.arg for k in node.keywords}
        func = func_of.get(id(node), "<module>")
        arg0 = node.args[0] if node.args else None
        verdict, why = "VIOLATION", "a path operation outside the trusted-parent helpers"
        if kws & {"dir_fd", "src_dir_fd", "dst_dir_fd"}:
            verdict, why = "ROUTED", "relative to a proved directory fd (%s)" % ",".join(sorted(kws & {"dir_fd", "src_dir_fd", "dst_dir_fd"}))
        elif name in ("os.listdir", "os.scandir") and isinstance(arg0, ast.Name) and arg0.id.endswith("fd"):
            verdict, why = "ROUTED", "lists a proved directory through its fd (%s)" % arg0.id
        elif name == "os.open" and func == "_walk" and isinstance(arg0, ast.Constant) and arg0.value == "/":
            verdict, why = "ROOT", "the walk starts at '/' (rule 2)"
        else:
            m = TAG_RE.search(line)
            if m:
                tag = m.group(1)
                if tag not in PY_TAGS:
                    why = "unknown safepath tag %r (closed set: %s)" % (tag, ", ".join(sorted(PY_TAGS)))
                elif tag == "procfs":
                    s0 = ast.unparse(arg0) if arg0 is not None else ""
                    if re.match(r"""^['"]/proc/""", s0):
                        verdict, why = "TAGGED", "procfs: kernel-owned (%s)" % s0[:40]
                    else:
                        why = "tagged procfs but the path is not a literal /proc/... (%s)" % s0[:40]
                elif tag == "devnull":
                    if arg0 is not None and ast.unparse(arg0) == "os.devnull":
                        verdict, why = "TAGGED", "devnull: the device is the intent"
                    else:
                        why = "tagged devnull but the path is not os.devnull"
                elif tag == "probe":
                    if name.replace("os.", "", 1) in PY_READONLY:
                        verdict, why = "TAGGED", "probe: a read-only query (%s)" % line.split("safepath:probe", 1)[1].strip()[:70]
                    else:
                        why = "tagged probe but %s is not a read-only query" % name
        rows.append((os.path.basename(path), node.lineno, func, name, verdict, why))
    return rows


def strip_quotes(s):
    """the line with every QUOTED character blanked to a space -- the SAME length, so a column found in it is the
    same column of the original line. A command substitution $( ... ) is CODE wherever it appears, also inside
    double quotes ("$(mktemp -d "$X/y.XXXXXX")" is an operation, not text): it is kept, with its own quoting handled
    recursively."""
    out = list(s)
    stack = ["code"]
    i = 0
    while i < len(s):
        c = s[i]
        top = stack[-1]
        if top == "sq":
            out[i] = " "
            if c == "'":
                stack.pop()
        elif top == "dq":
            if c == "\\" and i + 1 < len(s):
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if c == "$" and s[i + 1:i + 2] == "(":
                stack.append("cs")
                i += 2
                continue
            out[i] = " "
            if c == '"':
                stack.pop()
        else:                                   # code, cs (inside $( )), paren (a ( ) inside cs)
            if c == "'":
                out[i] = " "
                stack.append("sq")
            elif c == '"':
                out[i] = " "
                stack.append("dq")
            elif c == "\\":
                i += 2
                continue
            elif c == "$" and s[i + 1:i + 2] == "(":
                stack.append("cs")
                i += 2
                continue
            elif c == "(" and top in ("cs", "paren"):
                stack.append("paren")
            elif c == ")" and top in ("cs", "paren"):
                stack.pop()
        i += 1
    return "".join(out)


def code_part(line):
    """the line without its trailing comment (a # that starts a word, outside quotes)"""
    q = None
    for i, c in enumerate(line):
        if q is None and c in "'\"":
            q = c
        elif q is not None and c == q:
            q = None
        elif q is None and c == "#" and (i == 0 or line[i - 1] in " \t;"):
            return line[:i]
    return line


VAR_RE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")


HEREDOC_RE = re.compile(r"(?<!<)<<-?(?!<)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def _blank_heredocs(lines):
    """the lines with every here-document BODY replaced by '' (its text is data for the command that reads it -- an
    embedded Python program -- not shell); the line that opens it is kept"""
    out, end = [], None
    for raw in lines:
        if end is not None:
            out.append("")
            if raw.strip() == end:
                end = None
            continue
        out.append(raw)
        if not raw.lstrip().startswith("#"):
            m = HEREDOC_RE.search(code_part(raw))
            if m:
                end = m.group(2)
    return out


def sh_census(path):
    lines = _blank_heredocs(open(path).read().split("\n"))
    # 1) provenance of every variable: PROVED when EVERY non-empty assignment is of a proved form
    # an assignment ANYWHERE on a line (after `local`, after `case x)`, several on one `local` line), found in the
    # quote-blanked line so a NAME= inside a string is not one; its value is the shell word read from the real line
    assign_re = re.compile(r"(?:^|[\s;(&|])([A-Za-z_][A-Za-z0-9_]*)=")
    fdef = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{")
    assigns, fassigns, cur = {}, {}, "<top>"
    for no, raw in enumerate(lines, 1):
        if raw.lstrip().startswith("#"):
            continue
        m = fdef.match(raw)
        if m:
            cur = m.group(1)
        code = code_part(raw)
        bare = strip_quotes(code)
        for m in assign_re.finditer(bare):
            w = _orig_word(code, m.end())
            assigns.setdefault(m.group(1), []).append((no, w))
            fassigns.setdefault((cur, m.group(1)), []).append((no, w))
    proved = {"_FC_TMPDIR"}         # its assignments are checked below like any other
    roots = ("$(_fc_safe mkdtemp", "$(_fc_safe mkdir", "${FC_BR_TMPDIR")
    tmp_roots = ("$(_fc_mktemp)", '$(mktemp "$_FC_TMPDIR/', '$(mktemp -d "$_FC_TMPDIR/')   # only while _FC_TMPDIR is

    def rhs_proved(rhs, known):
        r = rhs.strip().strip('"')
        if r in ("", "''"):
            return True                                  # cleared: holds nothing
        if any(r.startswith(x) for x in roots):
            return True
        if any(r.startswith(x) for x in tmp_roots):
            return "_FC_TMPDIR" in known
        m = re.match(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(/.*)?$", r)
        return bool(m) and m.group(1) in known
    # the GREATEST fixed point: start from every assigned variable and remove, until nothing changes, each one that has
    # an assignment of an unproved form under the current set (removing one can only remove more -- monotone)
    proved = set(assigns) | {"_FC_TMPDIR"}
    changed = True
    while changed:
        changed = False
        for v in sorted(proved):
            if not all(rhs_proved(rhs, proved) for _, rhs in assigns.get(v, [])):
                proved.discard(v)
                changed = True
    def proved_in(fn, v):
        """a variable used in function fn is PROVED when every assignment of it IN fn is of a proved form (a local
        meaning), else -- assigned nowhere in fn -- when it is globally proved"""
        own = [a for a in fassigns.get((fn, v), []) if a[1].strip().strip('"') not in ("", "''")]
        if own:                                          # a value set HERE (an empty reset is not a value)
            return all(rhs_proved(rhs, proved) for _, rhs in own)
        return v in proved
    rows = []
    func = "<top>"
    for no, raw in enumerate(lines, 1):
        if raw.lstrip().startswith("#"):
            continue
        m = fdef.match(raw)
        if m:
            func = m.group(1)
        code = code_part(raw)
        tagm = TAG_RE.search(raw)
        # a tag on the line itself, or on the comment line(s) right above the command it heads (a continued command's
        # first physical line counts as the line the operation is on)
        k = no - 2
        while tagm is None and k >= 0 and lines[k].lstrip().startswith("#"):
            tagm = TAG_RE.search(lines[k])
            k -= 1
        if tagm is None and k >= 0 and lines[k].rstrip().endswith("\\"):
            j = k
            while j >= 0 and lines[j].rstrip().endswith("\\"):
                j -= 1
            j += 1
            while tagm is None and j - 1 >= 0 and lines[j - 1].lstrip().startswith("#"):
                tagm = TAG_RE.search(lines[j - 1])
                j -= 1
        tag = tagm.group(1) if tagm else None
        bare = strip_quotes(code)
        # the helper's own sub-command word is not an operation (blanked, column-preserving)
        bare_nohelper = re.sub(r"(?<=_fc_safe)\s+\S+", lambda mm: " " * len(mm.group(0)), bare)
        ops = []
        for c in SH_CMDS:
            for mm in re.finditer(r"(?:^|[\s;|&({`])" + c + r"(?=\s)", bare_nohelper):
                ops.append((c, mm.end()))
        # every redirection to or from a FILE: N>file, N>>file, &>file, <file (a read of a planted FIFO blocks: the
        # V4R11-1 class); N>&M / <&N (an fd), <<, <<< and >( ) / <( ) are not files
        for mm in re.finditer(r"(?<![<>&])(&?[0-9]*)(>>?|<)(?![&>(<|])", bare_nohelper):
            ops.append(("redirect" + mm.group(2), mm.end()))
        for mm in re.finditer(r"\bworktree\s+add\b", bare_nohelper):
            ops.append(("git worktree add", mm.end()))
        for mm in re.finditer(r"-delete\b", bare_nohelper):
            ops.append(("find -delete", mm.end()))
        if "_fc_safe" in bare and not ops:
            if re.search(r"_fc_safe\s+(check|mkdir|mkdtemp|write|rmtree)\b", code) or fdef.match(raw):
                rows.append((os.path.basename(path), no, func, "_fc_safe", "ROUTED", "the trusted-parent helper"))
            continue
        for kind, pos in ops:
            # operand span: up to an unquoted terminator, in the ORIGINAL code (variables live inside quotes)
            if kind == "git worktree add":
                words = [w for w in re.findall(r'"[^"]*"|\'[^\']*\'|\S+', _orig_cmd_span(code, bare_nohelper, pos))
                         if not w.startswith("-")]
                text = words[0] if words else ""      # the path operand (the commit-ish after it is not a path)
                vars_ = VAR_RE.findall(text)
            elif kind.startswith("redirect"):
                tgt = _orig_word(code, pos)
                if tgt in ("/dev/null", '"/dev/null"') or tgt.startswith("&"):
                    continue
                vars_ = VAR_RE.findall(tgt)
                text = tgt
            else:
                text = _orig_cmd_span(code, bare_nohelper, pos)
                vars_ = VAR_RE.findall(text)
                if kind in ("cat", "head", "tail", "tee") and not [w for w in text.split() if not w.startswith("-")
                                                                 and not w.isdigit()]:
                    continue                    # reads / writes stdin / stdout only: no file operand
            verdict, why = "VIOLATION", "%s on an operand that is not proved" % kind
            if tag == "msg":
                why = "tagged msg but an operation remains outside the quoted text"
            elif tag == "devnull" and "/dev/null" in text and not vars_:
                verdict, why = "TAGGED", "devnull"
            elif tag == "param":
                ps = [v for v in vars_ if (func, v) in PARAMS]
                rest = [v for v in vars_ if (func, v) not in PARAMS and not proved_in(func, v)]
                if ps and not rest:
                    verdict, why = "TAGGED", "param: " + "; ".join(PARAMS[(func, v)] for v in ps)
                else:
                    why = "tagged param but %r is not a listed parameter of %s" % (rest or vars_, func)
            elif tag is not None and tag not in SH_TAGS:
                why = "unknown safepath tag %r (closed set: %s)" % (tag, ", ".join(sorted(SH_TAGS)))
            elif vars_ and all(proved_in(func, v) for v in vars_) and not re.search(r"(^|[\s\"'])/",
                                                                              text.replace("/dev/null", "")):
                verdict, why = "PRIVATE", "inside a proved directory (%s)" % ", ".join(sorted(set(vars_)))
            rows.append((os.path.basename(path), no, func, kind, verdict, why))
        if tag == "msg" and not ops:
            raw_ops = any(re.search(r"(?:^|[\s;|&({`])" + c + r"(?=\s)", code) for c in SH_CMDS) or "worktree add" in code
            rows.append((os.path.basename(path), no, func, "(message)", "TAGGED" if raw_ops else "VIOLATION",
                         "msg: the keyword appears only inside quoted text" if raw_ops else "tagged msg without a keyword"))
    return rows, proved


def _orig_word(code, pos):
    """the redirection target at column pos of code: one shell word (quotes included), up to unquoted whitespace or
    ; | & ) }"""
    q = None
    i = pos
    while i < len(code) and code[i] in " \t":
        i += 1
    start = i
    while i < len(code):
        c = code[i]
        if q is None and c in "'\"":
            q = c
        elif q is not None and c == q:
            q = None
        elif q is None and (c in " \t;|&)}<>"):
            break
        i += 1
    return code[start:i]


def _orig_cmd_span(code, bare, pos):
    """the operand text of a command starting at column pos: up to an unquoted ; | & ) } < > or a comment"""
    q = None
    i = pos
    while i < len(code):
        c = code[i]
        if q is None and c in "'\"":
            q = c
        elif q is not None and c == q:
            q = None
        elif q is None and c in ";|&)}<>":
            break
        i += 1
    return code[pos:i]


def main(argv):
    md = "--markdown" in argv
    args = [a for a in argv if a != "--markdown"]
    here = os.path.dirname(os.path.abspath(__file__))
    fc = os.path.dirname(here)
    sup = os.environ.get("FC_SUP_UNDER_TEST") or os.path.join(fc, "cycle", "fc_supervisor.py")
    br = os.environ.get("FC_BR_UNDER_TEST") or os.path.join(fc, "cycle", "baseline_replay.sh")
    while args:
        a = args.pop(0)
        if a == "--sup" and args:
            sup = args.pop(0)
        elif a == "--br" and args:
            br = args.pop(0)
        else:
            sys.stderr.write("usage: check_safepath_census.py [--sup FILE] [--br FILE] [--markdown]\n")
            return 2
    try:
        rows = py_census(sup)
        srows, proved = sh_census(br)
    except (OSError, SyntaxError) as e:
        sys.stderr.write("check_safepath_census: cannot read the files under test: %s\n" % e)
        return 2
    rows = sorted(rows, key=lambda r: r[1]) + sorted(srows, key=lambda r: r[1])
    bad = [r for r in rows if r[4] == "VIOLATION"]
    if md:
        print("| file | line | function | operation | verdict | reason |")
        print("|---|---|---|---|---|---|")
        for r in rows:
            print("| %s | %d | `%s` | `%s` | %s | %s |" % (r[0], r[1], r[2], r[3], r[4], r[5].replace("|", "\\|")))
    else:
        for r in rows:
            print("%s %s:%d %s %s -- %s" % (r[4], r[0], r[1], r[2], r[3], r[5]))
    counts = {}
    for r in rows:
        counts[r[4]] = counts.get(r[4], 0) + 1
    print("SUMMARY operations=%d %s violations=%d proved_shell_vars=%s" % (
        len(rows), " ".join("%s=%d" % kv for kv in sorted(counts.items())), len(bad), ",".join(sorted(proved))))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
