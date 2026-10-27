#!/usr/bin/env python3
# ============================================================================
# codegraph_launch_class.py — classify what an MCP server entry LAUNCHES
# ============================================================================
# Purpose      Decide, from the `command` + `args` of an MCP server entry (.mcp.json, a settings file, ~/.claude.json), whether the
#              entry launches the STOCK codegraph (@colbymchenry/codegraph: it opens the database for writing, runs a file watcher
#              and spawns a daemon, so it is not read-only), the sanctioned read-only wrapper (codegraph_mcp.sh) or something else.
#              The decision is made on the RESOLVED LAUNCH TARGET, never on the basename of `command` alone (a basename test misses
#              `node .../codegraph.js`, `bash -c "codegraph ..."`, `npx @colbymchenry/codegraph`, `env X=1 codegraph ...` and a shim
#              script that execs codegraph — measured by tests F13/F14 of test_codegraph_mcp_preflight.sh), and never on a substring
#              (an entry that only MENTIONS codegraph — `grep codegraph`, `codegraph-viewer.js`, `@other/codegraph-ui` — is not one
#              that launches it; a false refusal is a FAIL-bluff, constitution §11.4.201(1)).
# Usage        import codegraph_launch_class as L; kind, detail = L.classify(command, args, base_dir)
#              CLI (ad hoc / unit tests):  codegraph_launch_class.py [--base-dir DIR] -- COMMAND [ARG...]  -> "<kind>\t<detail>"
# Inputs       command (str), args (list of str), base_dir (directory relative paths resolve against; default ".")
# Outputs      (kind, detail): kind is "stock" | "wrapper" | "other"; detail is a short human reason built ONLY from file basenames and
#              constants — never from argument values, so a secret passed as an argument or environment value cannot reach a report
# Side effects none. Reads (never executes) the launch target: a regular file of at most 256 KiB, plus package.json of the nearest
#              enclosing package. PATH is consulted for a bare command name.
# Dependencies python3 standard library only
# Boundaries   (constitution §11.4.6) This is a STATIC classification. It resolves: direct names and symlinks, env/exec/nohup/nice/
#              timeout/stdbuf/ionice/setsid/sudo/command/time wrappers, sh/bash/dash/zsh/ash/ksh (-c strings and script files, quote- and
#              comment-aware, simple commands split on ; & | ( ) and newlines), node/nodejs/bun scripts, npx/pnpx/bunx/npm exec/pnpm
#              dlx/yarn dlx, `env -S`, and shell shims (a file starting with a shell shebang), to a depth of 12 file/shell hops (wrapper peeling is
#              unbounded but strictly shrinking) with a cycle guard; `command -v NAME` is a lookup and launches nothing. The threat
#              boundary is ACCIDENTAL misconfiguration, not an adversary assembling a launch to evade a static reader. It does NOT
#              see: a compiled launcher whose name is not codegraph, a script of 256 KiB or more, a script in a non-shell language
#              (python, perl, ...), a launch assembled at run time (variables, eval, command substitution results), or an interpreter
#              option that takes a separate value and is not in its table (the value would be taken for the script). Such entries are
#              classified "other" by name only; the runtime proof that the project's own server is read-only is preflight check P5.
# Cross-refs   codegraph_mcp_preflight.sh (P2, P3, P7), codegraph_mcp.sh, tests/test_codegraph_launch_class.py,
#              tests/test_codegraph_mcp_preflight.sh (F13-F17), constitution §11.4.201 / §11.4.273
# ============================================================================
import json
import os
import re
import shlex
import shutil
import stat
import sys

STOCK_PKG = "@colbymchenry/codegraph"
STOCK_NAMES = ("codegraph", "codegraph.js")
WRAPPER_NAME = "codegraph_mcp.sh"
WRAPPER_SIBLING = "fk_index_patch.py"
SHELLS = {"sh", "bash", "dash", "zsh", "ash", "ksh"}
NODE_RE = re.compile(r"^(node|nodejs|bun)([0-9][0-9.]*)?$")
NPX_RUNNERS = {"npx", "pnpx", "bunx"}
PM_EXEC = {"npm": ("exec", "x"), "pnpm": ("dlx", "exec"), "yarn": ("dlx", "exec"), "bun": ("x",)}
NPX_VALUE_OPTS = {"--registry", "--cache", "--prefix", "--node-options", "-w", "--workspace", "--userconfig", "--loglevel"}
NODE_VALUE_OPTS = {"-r", "--require", "--import", "--loader", "--experimental-loader", "-C", "--conditions", "--env-file"}
# transparent wrappers: name -> (options that take a separate value, number of leading positional words to skip, skips VAR=value)
WRAPPERS = {
    "env": ({"-u", "--unset", "-C", "--chdir"}, 0, True),
    "exec": ({"-a"}, 0, False),
    "command": (set(), 0, False),
    "nohup": (set(), 0, False),
    "time": ({"-f", "--format", "-o", "--output"}, 0, False),
    "nice": ({"-n", "--adjustment"}, 0, False),
    "ionice": ({"-c", "--class", "-n", "--classdata", "-p", "--pid", "-P", "--pgid", "-u", "--uid"}, 0, False),
    "setsid": (set(), 0, False),
    "stdbuf": ({"-i", "-o", "-e", "--input", "--output", "--error"}, 0, False),
    "timeout": ({"-s", "--signal", "-k", "--kill-after"}, 1, False),
    "sudo": ({"-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"}, 0, False),
}
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "{", "}", "!"}
MAX_DEPTH = 12                                                  # nested shell / file / `npx -c` hops (wrapper peeling is not counted)
MAX_FILE = 256 * 1024
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_SHELL_FLAGS = re.compile(r"^-[A-Za-z]+$")

OTHER = ("other", "")


def _stock(detail):
    return ("stock", detail)


def _is_str_list(x):
    return isinstance(x, list) and all(isinstance(a, str) for a in x)


def split_commands(text):
    """Split shell text into simple commands (lists of words). Quote- and comment-aware; performs no expansion. A command separator is
    ; & | ( ) or a newline; a redirection operator and its target word are dropped; here-document bodies (<<WORD, <<-WORD, quoted or
    not) are skipped as data, up to the line equal to the delimiter."""
    cmds, words, cur = [], [], None
    drop_next = False
    heredocs = []                                              # (delimiter, strip_leading_tabs) pending until the next newline

    def end_word():
        nonlocal cur, drop_next
        if cur is not None:
            if drop_next:
                drop_next = False
            else:
                words.append(cur)
            cur = None

    def end_cmd():
        nonlocal words
        end_word()
        if words:
            cmds.append(words)
        words = []

    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            if i + 1 < n and text[i + 1] != "\n":
                cur = (cur or "") + text[i + 1]
            i += 2
            continue
        if c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                return cmds + ([words] if words else [])      # unbalanced quote: bash would refuse to run it
            cur = (cur or "") + text[i + 1:j]
            i = j + 1
            continue
        if c == '"':
            j, buf = i + 1, ""
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n and text[j + 1] in '"\\$`':
                    buf += text[j + 1]
                    j += 2
                else:
                    buf += text[j]
                    j += 1
            if j >= n:
                return cmds + ([words] if words else [])
            cur = (cur or "") + buf
            i = j + 1
            continue
        if c == "#" and cur is None:
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c in " \t":
            end_word()
        elif c == "\n":
            end_cmd()
            while heredocs:                                    # skip the here-document bodies: their lines are data, not commands
                delim, strip = heredocs.pop(0)
                while i + 1 < n:
                    j = text.find("\n", i + 1)
                    line = text[i + 1:] if j < 0 else text[i + 1:j]
                    i = n - 1 if j < 0 else j
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
        elif c in ";&|()":
            end_cmd()
        elif c == "<" and text.startswith("<<", i) and not text.startswith("<<<", i):
            end_word()
            k = i + 2
            strip = k < n and text[k] == "-"
            if strip:
                k += 1
            while k < n and text[k] in " \t":
                k += 1
            delim = ""
            while k < n and text[k] not in " \t\n;&|()<>":
                if text[k] in "'\"":
                    q = text.find(text[k], k + 1)
                    if q < 0:
                        break
                    delim += text[k + 1:q]
                    k = q + 1
                else:
                    delim += text[k]
                    k += 1
            if delim:
                heredocs.append((delim, strip))
            i = k - 1
        elif c in "<>":
            if cur is not None and cur.isdigit():
                cur = None                                    # the fd number of `2>&1`
            end_word()
            drop_next = True                                  # the redirection target is not part of the command
            while i + 1 < n and text[i + 1] in "<>&|":
                i += 1
            while i + 1 < n and text[i + 1] in " \t":
                i += 1
        else:
            cur = (cur or "") + c
        i += 1
    end_cmd()
    return cmds


def _strip_wrapper(name, args):
    """The argv a transparent wrapper (env, exec, nohup, nice, timeout, ...) goes on to run, or [] when it launches nothing."""
    opts, skip_pos, assign = WRAPPERS[name]
    i, skipped, only_assign = 0, 0, False
    while i < len(args):
        a = args[i]
        if not only_assign and name == "command" and re.match(r"^-[p]*[vV][p]*$", a):
            return []                                          # `command -v NAME` is a lookup: it prints a path and launches nothing
        if not only_assign and name == "env" and a in ("-S", "--split-string") and i + 1 < len(args):
            try:
                extra = shlex.split(args[i + 1])               # env -S 'codegraph serve': the string is split into the command and its args
            except ValueError:
                extra = []
            args = args[:i] + extra + args[i + 2:]
            continue                                           # i unchanged: re-examine the spliced words
        if not only_assign and name == "env" and a.startswith("--split-string="):
            try:
                extra = shlex.split(a.split("=", 1)[1])
            except ValueError:
                extra = []
            args = args[:i] + extra + args[i + 1:]
            continue
        if not only_assign and a == "--":
            only_assign = True
            i += 1
            continue
        if not only_assign and a in opts:
            i += 2
            continue
        if not only_assign and a.startswith("--") and "=" in a:
            i += 1
            continue
        if not only_assign and a.startswith("-") and len(a) > 1:
            i += 1
            continue
        if assign and _ASSIGN.match(a):
            i += 1
            continue
        if skipped < skip_pos:
            skipped += 1
            i += 1
            continue
        break
    return args[i:]


def _resolve_path(word, base_dir):
    if "/" in word:
        return word if os.path.isabs(word) else os.path.join(base_dir, word)
    return shutil.which(word)


def _in_stock_package(real):
    d = os.path.dirname(real)
    for _ in range(8):
        pj = os.path.join(d, "package.json")
        try:
            st = os.stat(pj)
            if stat.S_ISREG(st.st_mode) and st.st_size <= 1048576:
                with open(pj, "rb") as fh:
                    return json.loads(fh.read().decode("utf-8", "replace")).get("name") == STOCK_PKG
        except (OSError, ValueError, AttributeError):
            pass
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return False


def _shebang_interp(head):
    first = head.split(b"\n", 1)[0].decode("utf-8", "replace")
    if not first.startswith("#!"):
        return None
    toks = first[2:].split()
    if not toks:
        return None
    interp = os.path.basename(toks[0])
    if interp == "env":
        for t in toks[1:]:
            if not t.startswith("-") and not _ASSIGN.match(t):
                return os.path.basename(t)
        return None
    return interp


def _classify_file(path, ctx, as_shell=False, interpreter=None):
    try:
        real = os.path.realpath(path)
        st = os.stat(real)
    except OSError:
        # A launch target that is not on disk (yet) is judged by its name: an entry that names codegraph.js still launches the stock
        # codegraph the moment the file appears, so "absent" is not "safe". Any other absent target is not codegraph.
        if os.path.basename(path) in STOCK_NAMES:
            return _stock("names %s (target file not present)" % os.path.basename(path))
        return OTHER
    if not stat.S_ISREG(st.st_mode):
        return OTHER
    if real in ctx["seen"]:
        return OTHER                                           # cycle guard
    ctx["seen"].add(real)
    rb = os.path.basename(real)
    if rb in STOCK_NAMES:
        return _stock("resolves to %s" % rb)
    if _in_stock_package(real):
        return _stock("inside the %s package" % STOCK_PKG)
    if rb == WRAPPER_NAME and os.path.isfile(os.path.join(os.path.dirname(real), WRAPPER_SIBLING)):
        return ("wrapper", "sanctioned %s" % WRAPPER_NAME)
    if interpreter is not None or st.st_size > MAX_FILE:
        return OTHER
    try:
        with open(real, "rb") as fh:
            data = fh.read(MAX_FILE)
    except OSError:
        return OTHER
    if as_shell or _shebang_interp(data) in SHELLS:
        kind, detail = _scan_shell_text(data.decode("utf-8", "replace"), ctx)
        if kind == "stock":
            return _stock("shim script %s -> %s" % (rb, detail))
        return (kind, detail)
    return OTHER


def _scan_shell_text(text, ctx):
    best = OTHER
    for words in split_commands(text):
        i = 0
        while i < len(words) and (words[i] in KEYWORDS or _ASSIGN.match(words[i])):
            i += 1
        if i >= len(words):
            continue
        kind, detail = _classify_argv(words[i:], ctx)
        if kind == "stock":
            return (kind, detail)
        if kind == "wrapper":
            best = (kind, detail)
    return best


def _pkg_name(spec):
    if spec.startswith("@"):
        m = re.match(r"^(@[^/@]+/[^/@]+)", spec)
        return m.group(1) if m else spec
    return spec.split("@", 1)[0]


def _classify_npx(args, ctx):
    pkgs, i, only_pos = [], 0, False
    while i < len(args):
        a = args[i]
        if not only_pos and a == "--":
            only_pos = True
            i += 1
            continue
        if not only_pos and a in ("-p", "--package"):
            if i + 1 < len(args):
                pkgs.append(args[i + 1])
            i += 2
            continue
        if not only_pos and a.startswith("--package="):
            pkgs.append(a.split("=", 1)[1])
            i += 1
            continue
        if not only_pos and a in ("-c", "--call"):
            if i + 1 < len(args):
                kind, detail = _scan_shell_text(args[i + 1], ctx)
                if kind == "stock":
                    return (kind, "npx -c string: %s" % detail)
            i += 2
            continue
        if not only_pos and a in NPX_VALUE_OPTS:
            i += 2
            continue
        if not only_pos and a.startswith("-") and len(a) > 1:
            i += 1
            continue
        pkgs.append(a)
        break
    for spec in pkgs:
        if _pkg_name(spec) in (STOCK_PKG, "codegraph"):
            return _stock("npx package %s" % STOCK_PKG)
    return OTHER


def _classify_argv(argv, ctx):
    if not argv:
        return OTHER
    if ctx["depth"] >= MAX_DEPTH:
        return OTHER
    sub = dict(ctx, depth=ctx["depth"] + 1)
    while argv and os.path.basename(argv[0]) in WRAPPERS:      # peel env/exec/nohup/...: each pass strictly shrinks argv, so it terminates
        argv = _strip_wrapper(os.path.basename(argv[0]), argv[1:])
    if not argv:
        return OTHER
    word = argv[0]
    base = os.path.basename(word)
    args = argv[1:]
    if base in STOCK_NAMES:
        return _stock("command word %r" % base)
    if base in SHELLS:
        i = 0
        while i < len(args):
            a = args[i]
            if a == "--":
                i += 1
                break
            if _SHELL_FLAGS.match(a):
                if "c" in a[1:] and i + 1 < len(args):
                    kind, detail = _scan_shell_text(args[i + 1], sub)
                    return (kind, "%s -c string: %s" % (base, detail) if detail else detail)
                i += 1
                continue
            if a.startswith("-"):
                i += 1
                continue
            break
        if i < len(args):
            path = _resolve_path(args[i], ctx["base_dir"])
            return _classify_file(path, sub, as_shell=True) if path else OTHER
        return OTHER
    if base in NPX_RUNNERS:
        return _classify_npx(args, sub)
    if base in PM_EXEC and args and args[0] in PM_EXEC[base]:    # before the node/bun branch: `bun x PKG` runs a package, not a script
        return _classify_npx(args[1:], sub)
    if NODE_RE.match(base):
        i = 0
        while i < len(args):
            a = args[i]
            if a in ("-e", "--eval", "-p", "--print"):
                return OTHER
            if a in NODE_VALUE_OPTS:
                i += 2
                continue
            if a.startswith("-"):
                i += 1
                continue
            break
        if i < len(args):
            path = _resolve_path(args[i], ctx["base_dir"])
            if path:
                kind, detail = _classify_file(path, sub, interpreter=base)
                return (kind, "%s script: %s" % (base, detail) if detail else detail)
        return OTHER
    path = _resolve_path(word, ctx["base_dir"])
    return _classify_file(path, sub) if path else OTHER


def classify_shell(text, base_dir="."):
    """Classify a SHELL COMMAND STRING (a settings-file hook `command`, the text a shell would run) -> (kind, detail), same kinds as classify()."""
    if not isinstance(text, str) or not text.strip():
        return ("other", "no launchable command")
    kind, detail = _scan_shell_text(text, {"base_dir": base_dir, "seen": set(), "depth": 0})
    return (kind, detail or "no codegraph launch target found")


def classify(command, args, base_dir="."):
    """Classify the launch target of an MCP server entry -> (kind, detail). kind: 'stock' | 'wrapper' | 'other'."""
    if args is None:
        args = []
    if not isinstance(command, str) or not command or not _is_str_list(args):
        return ("other", "no launchable command")
    ctx = {"base_dir": base_dir, "seen": set(), "depth": 0}
    kind, detail = _classify_argv([command] + args, ctx)
    return (kind, detail or "no codegraph launch target found")


def main(argv):
    base_dir = "."
    if argv and argv[0] == "--base-dir":
        if len(argv) < 2:
            sys.stderr.write("usage: codegraph_launch_class.py [--base-dir DIR] -- COMMAND [ARG...]\n")
            return 2
        base_dir, argv = argv[1], argv[2:]
    if argv and argv[0] == "--":
        argv = argv[1:]
    if not argv:
        sys.stderr.write("usage: codegraph_launch_class.py [--base-dir DIR] -- COMMAND [ARG...]\n")
        return 2
    kind, detail = classify(argv[0], argv[1:], base_dir)
    sys.stdout.write("%s\t%s\n" % (kind, detail))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
