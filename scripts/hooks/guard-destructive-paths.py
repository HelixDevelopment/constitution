#!/usr/bin/env python3
"""scripts/hooks/guard-destructive-paths.py

Claude Code PreToolUse guard (mechanical block) for constitution §11.4.287:
a recursive delete / recursive permission change / `find -delete` /
`rsync --delete` / `mv` of a protected directory must NEVER be able to reach `/`,
`/home`, a user's home, or a well-known top-level system / personal directory —
whether the path is written literally or arrives through a variable that can
expand to nothing or to the wrong place.

FORENSIC ANCHOR (2026-10-23): a reviewer subagent wrote a scratch script whose
header was `W="$2"; export HOME="$W/home"; rm -rf "$HOME"` and ran it with no
arguments. `W` was empty, so `HOME` became `/home` and `rm -rf /home` ran as the
operator until a timeout killed it.

CONTRACT (PreToolUse hook): JSON on stdin; exit 0 = allow; exit 2 = BLOCK with
the reason on stderr. Tools inspected: Bash (the command, plus the bodies of
`bash -c`, `eval`, `trap`, `$(...)`, backticks, strings piped or here-stringed
into a shell, functions at their call sites, and heredocs written to a script or
fed to a shell), Write / Edit / MultiEdit (shell scripts, Makefiles, justfiles,
CI yaml). Any other exit status of the hook process is treated by Claude Code as
ALLOW, so this guard catches its own exceptions, says so loudly on stderr, and
exits 0 on purpose (a guard that blocks on its own failure blocks all work,
§11.4.201(1)).

CLASSES
  P  PROTECTED TARGET  (NOT overridable): the target, resolved from literals and
     the real $HOME only, is `/`, a system directory, `/home`, a user home, the
     home directory, a protected child of it, or a glob that can match one.
  X  UNPARSABLE / TOO DEEP (NOT overridable): the text cannot be parsed reliably
     (unterminated quote, `$(`, backtick or heredoc, nesting deeper than 5) and it
     contains a destructive command. Fail closed.
  H  HOME REASSIGNED THEN USED (overridable): HOME was assigned from an expansion
     that can be empty or tainted, then a destructive command runs under it.
  V  EMPTY OR TAINTED VARIABLE (overridable): the target derives from an
     unguarded positional parameter, an indirect expansion, or an unknown/empty
     variable that composes a protected path once it is empty; also an
     unresolved command word used with recursive/force flags, and `xargs` /
     `parallel` input that cannot be inspected.
  U  UNINSPECTABLE CODE (overridable): code is fed to a shell from a source the
     guard cannot read (a pipe from an unknown producer, an unknown variable).

ESCAPE HATCH: a real single-line shell comment `# guardrails:allow <reason>` at
the TOP level of the command (non-empty reason; text inside quotes, heredoc
bodies, `bash -c`, traps or `$(...)` does not count) downgrades H, V and U to a
warning. Classes P and X have no escape hatch.

HONEST BOUNDARY (§11.4.6): this is a text scan at the tool-call boundary, not a
security boundary. It cannot see a path produced by `eval` of a decoded string,
command-substitution output used as a target, a downloaded script, a binary or a
language runtime deleting through its own API; variable values are tracked in
statement order. The runtime layer `scripts/lib/safe_rm.sh` is the second layer.
"""
import fnmatch
import functools
import json
import os
import posixpath
import pwd
import re
import shlex
import sys

MAX_DEPTH = 5

SYSTEM_DIRS = {
    "/", "/bin", "/boot", "/dev", "/etc", "/lib", "/lib32", "/lib64", "/libx32",
    "/opt", "/proc", "/root", "/run", "/sbin", "/srv", "/sys", "/usr", "/var",
    "/mnt", "/media", "/snap", "/home", "/Users", "/tmp", "/var/lib", "/usr/lib",
    "/usr/bin", "/usr/local", "/var/log",
}
HOME_CHILDREN = {
    "Projects", "backups", "Documents", "Desktop", "Downloads", "Pictures",
    "Music", "Videos", "Obsidian", "scripts", "bin", "go", "opt", "Android",
    ".ssh", ".gnupg", ".config", ".local", ".cache", ".claude", ".claude-shared",
    ".git", ".aws", ".kube", ".docker", ".password-store", "vasic", "ytdlp",
}
HOME_CHILD_PREFIXES = (".claude",)  # matches the list entry ~/.claude*
RECURSIVE_CMDS = {"rm", "shred"}
OWNERSHIP_CMDS = {"chmod", "chown", "chgrp"}
WRAPPERS = {"sudo", "env", "command", "exec", "nice", "ionice", "nohup", "time",
            "timeout", "stdbuf", "setsid", "builtin", "doas", "run0", "pkexec",
            "flock", "chroot", "busybox", "coproc", "watch", "systemd-run"}
WRAP_OPTS = {
    "sudo": {"-u", "-g", "-C", "-h", "-p", "-r", "-t", "-U", "-D", "-T", "--user", "--group",
             "--host", "--prompt", "--role", "--type", "--other-user", "--close-from",
             "--chdir", "--chroot", "--command-timeout"},
    "env": {"-u", "-C", "--unset", "--chdir"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "--class", "--classdata", "--pid"},
    "stdbuf": {"-i", "-o", "-e", "--input", "--output", "--error"},
    "exec": {"-a"},
    "time": {"-o", "-f", "--output", "--format"},
    "doas": {"-u", "-C"},
    "run0": {"-u", "-g", "-D", "--user", "--group", "--chdir", "--property", "-p"},
    "pkexec": {"--user"},
    "flock": {"-w", "-E", "--timeout", "--conflict-exit-code"},
    "chroot": {"--userspec", "--groups"},
    "watch": {"-n", "--interval"},
    "systemd-run": {"-p", "--property", "-u", "--unit", "--uid", "--gid", "-E", "--setenv",
                    "-d", "--description", "--slice", "--working-directory", "-M",
                    "--machine", "-H", "--host", "--on-active", "--on-calendar",
                    "--service-type"},
}
WRAP_POS = {"flock": 1, "chroot": 1}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "su"}
STDIN_SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
DECLARERS = {"export", "local", "declare", "readonly", "typeset"}
MARKER_RE = re.compile(r"^#\s*guardrails:allow\s+(\S.*)$")
ASSIGN_RE = re.compile(r"^([A-Za-z_]\w*)(\+?)=(.*)$", re.S)
VAR_RE = re.compile(r"\$(?:\{([^}]*)\}|([A-Za-z_]\w*|[0-9]|[@*#?!$-]))")
GLOB_RE = re.compile(r"[*?\[]")
RECUR_FLAG_RE = re.compile(r"-[A-Za-z]*(?:rf|fr|Rf|fR)[A-Za-z]*|--recursive|--force")
DESTRUCT_RE = re.compile(
    r"\b(?:rm|shred|rmdir|unlink)\b"
    r"|\b(?:chmod|chown|chgrp)\b[^\n]*(?:\s-\w*R|--rec)"
    r"|\bfind\b[^\n]*(?:-delete|-exec|-ok)"
    r"|\brsync\b[^\n]*--(?:del|remove)"
    r"|\bmv\b\s+(?:-\S+\s+)*[/~$]")
HEREDOC_RE = re.compile(r"<<(-?)[ \t]*(?:'([^']*)'|\"([^\"]*)\"|\\?([^\s;&|<>()'\"\\]+))")

HOMEVAR = "\0HOME\0"   # symbolic $HOME
TV = "\0T\0"           # tainted: derives from an unguarded positional parameter
UV = "\0U\0"           # unknown / possibly empty
SV = "\0S\0"           # guarded or sandbox-derived: cannot be judged
MARKERS = (TV, UV, SV)
ARRAY_TAG = "\x03"
ARRAY_SEP = "\x01"


def real_home():
    return os.path.realpath(os.environ.get("HOME", "") or "/nonexistent")


def protected_paths(rh):
    prot = set(SYSTEM_DIRS) | {rh, posixpath.dirname(rh)}
    prot |= {rh + "/" + c for c in HOME_CHILDREN}
    prot |= {rh + "/" + p + "x" for p in HOME_CHILD_PREFIXES}
    return prot


# --------------------------------------------------------------------------
# Quote-aware segmenter. Returns (segments, heredocs, comments, problems).
# Each segment is (text, separator_before). Heredoc bodies and real comments are
# collected apart; comments carry a flag saying they sit inside $(...) / backticks.
# --------------------------------------------------------------------------
def _heredoc_end(text, k_nl, pending):
    """From the index of a newline, skip the bodies of `pending` heredocs; return the index after the
    last terminator, or -1 if any terminator is missing (then the opener was not a real heredoc)."""
    i, n = k_nl + 1, len(text)
    for strip, delim in pending:
        found = False
        while i < n:
            j = text.find("\n", i)
            line = text[i:] if j == -1 else text[i:j]
            i = n if j == -1 else j + 1
            if (line.lstrip("\t") if strip else line) == delim:
                found = True
                break
        if not found:
            return -1
    return i


def matching_paren(text, start, heredocs=True):
    """Index just past the ')' that closes the '(' whose content starts at `start`. Heredoc bodies
    inside are skipped (a ')' or quote in a body must not end or unbalance the substitution)."""
    depth, k, n = 1, start, len(text)
    sq = dq = False
    pend = []
    while k < n and depth:
        c = text[k]
        if heredocs and not sq and not dq and c == "<" and text.startswith("<<", k) and not text.startswith("<<<", k):
            m = HEREDOC_RE.match(text, k)
            if m:
                delim = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else m.group(4))
                if delim and (m.group(4) is None or re.match(r"[A-Za-z_]", delim)):
                    pend.append((m.group(1) == "-", delim))
                    k = m.end()
                    continue
        if heredocs and pend and c == "\n" and not sq:
            e = _heredoc_end(text, k, pend)
            pend = []
            if e != -1:
                k = e
                continue
        if sq:
            if c == "'":
                sq = False
        elif c == "\\":
            k += 1
        elif c == "'" and not dq:
            sq = True
        elif c == '"':
            dq = not dq
        elif not dq and c == "(":
            depth += 1
        elif not dq and c == ")":
            depth -= 1
        k += 1
    return k if depth == 0 else -1


def segment(text):
    segs, heredocs, comments, problems = [], [], [], []
    i, n = 0, len(text)
    cur, quote, pending, prev_sep = [], None, [], "\n"
    sub, bt = 0, False
    while i < n:
        c = text[i]
        if quote:
            cur.append(c)
            if c == "\\" and quote in ('"', "$'") and i + 1 < n:
                cur.append(text[i + 1])
                i += 2
                continue
            if (quote == '"' and c == '"') or (quote in ("'", "$'") and c == "'"):
                quote = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            cur.append(c)
            cur.append(text[i + 1])
            i += 2
            continue
        if c == "$" and text.startswith("$'", i):
            quote = "$'"
            cur.append("$'")
            i += 2
            continue
        if c in "'\"":
            quote = c
            cur.append(c)
            i += 1
            continue
        if c == "`":
            bt = not bt
            cur.append(c)
            i += 1
            continue
        if text.startswith("$((", i):
            depth, j = 2, i + 3
            while j < n and depth:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                j += 1
            if depth:
                problems.append("unterminated $(( arithmetic")
            cur.append(text[i:j])
            i = j
            continue
        if text.startswith("$(", i) or (c in "<>" and text.startswith("(", i + 1)):
            sub += 1
            cur.append(text[i:i + 2])
            i += 2
            continue
        if sub and c == "(":
            sub += 1
        elif sub and c == ")":
            sub -= 1
        if c == "#" and (not cur or cur[-1] in " \t\n;&|("):
            j = text.find("\n", i)
            end = n if j == -1 else j
            comments.append((text[i:end], bool(sub or bt)))
            i = end
            continue
        if c == "<" and text.startswith("<<<", i):
            cur.append("<<<")
            i += 3
            continue
        if c == "<" and text.startswith("<<", i):
            m = HEREDOC_RE.match(text, i)
            if m:
                delim = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else m.group(4))
                quoted = m.group(4) is None or m.group(0).find("\\") != -1
                # owner = the statement that holds `<<` (not the last statement on the line)
                owner = ("seg", len(segs))
                pending.append((m.group(1) == "-", delim, quoted, owner))
                cur.append(m.group(0))
                i += len(m.group(0))
                continue
        if c == "\n":
            seg_text = "".join(cur)
            i += 1
            body_start = i
            embedded = bool(sub or bt) and bool(pending)
            for strip, delim, quoted, owner in pending:
                body, found = [], False
                while i < n:
                    j = text.find("\n", i)
                    line = text[i:] if j == -1 else text[i:j]
                    i = n if j == -1 else j + 1
                    chk = line.lstrip("\t") if strip else line
                    if chk == delim:
                        found = True
                        break
                    body.append(line)
                if not found:
                    problems.append("unterminated heredoc <<%s" % delim)
                if not embedded:
                    heredocs.append([owner, "\n".join(body), quoted])
            pending = []
            if sub or bt:
                cur.append("\n")
                if embedded:
                    # inside $( ) / backticks: keep the heredoc (opener, body, terminator) in the
                    # substitution text, so the recursive analysis of that text sees a real
                    # top-level heredoc with its true owner statement and pipeline
                    cur.append(text[body_start:i])
                continue
            if not seg_text.strip() and prev_sep.strip() in ("||", "&&", "|", "|&"):
                cur = []
                continue  # operator at end of line continues onto the next line
            segs.append((seg_text, prev_sep))
            prev_sep = "\n"
            cur = []
            continue
        if c in ";&|" and not sub and not bt:
            if c == "&" and ((cur and cur[-1] in "<>") or text.startswith("&>", i)):
                cur.append(c)
                i += 1
                continue
            segs.append(("".join(cur), prev_sep))
            cur = []
            j = i
            while j < n and text[j] in ";&|":
                j += 1
            prev_sep = text[i:j]
            i = j
            continue
        cur.append(c)
        i += 1
    if quote:
        problems.append("unterminated quote")
    if sub:
        problems.append("unterminated $( / <( / >(")
    if bt:
        problems.append("unterminated backtick")
    segs.append(("".join(cur), prev_sep))
    # resolve each heredoc to (owner statement text, body, quoted, later stages of its pipeline)
    resolved = []
    for owner, body_h, quoted_h in heredocs:
        k = owner[1]
        otext = segs[k][0] if k < len(segs) else ""
        stages, k0, k = [], k, k + 1
        while k < len(segs) and segs[k][1].strip() in ("|", "|&"):
            stages.append(segs[k][0])
            k += 1
        # a heredoc on a compound command's closer (`{ sh; } <<E`, `done <<E`, `fi <<E`, `) <<E`)
        # feeds the statements INSIDE the block: bind it to them
        first = otext.strip().split(None, 1)[0] if otext.strip() else ""
        if first in ("}", "fi", "done", "esac", ")") or otext.strip().startswith(")"):
            opener_found = False
            for j in range(k0 - 1, max(-1, k0 - 401), -1):
                stages.append(segs[j][0])
                if re.match(r"^\s*(?:\{|\(|if\b|while\b|until\b|for\b|case\b|select\b)", segs[j][0]):
                    opener_found = True
                    break
            if not opener_found:
                stages.append("bash")  # block opener not found: fail closed, treat the body as shell input
        resolved.append((otext, body_h, quoted_h, stages))
    heredocs = resolved
    return [s for s in segs if s[0].strip()], heredocs, comments, problems


def destructive_text(t):
    """A destructive verb anywhere in `t`, also when obfuscated by backslashes or quotes (r\\m, 'r'm)."""
    return bool(DESTRUCT_RE.search(t) or DESTRUCT_RE.search(re.sub(r"[\\'\"]", "", t)))


def balanced_subst(text):
    """Bodies of $(...), <(...), >(...) and backticks that are live (not single-quoted)."""
    out, i, n = [], 0, len(text)
    sq = dq = False
    while i < n:
        c = text[i]
        if sq:
            if c == "'":
                sq = False
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c == "'" and not dq:
            sq = True
            i += 1
            continue
        if c == '"':
            dq = not dq
            i += 1
            continue
        if text.startswith("$((", i):
            k = matching_paren(text, i + 2, heredocs=False)
            i = n if k == -1 else k
            continue
        if text.startswith("$(", i) or (not dq and c in "<>" and text.startswith("(", i + 1)):
            start = i + 2
            k = matching_paren(text, start)
            if k == -1:
                out.append(text[start:])
                break
            out.append(text[start:k - 1])
            i = k
            continue
        if c == "`":
            j = text.find("`", i + 1)
            if j == -1:
                out.append(text[i + 1:])
                break
            out.append(text[i + 1:j])
            i = j + 1
            continue
        i += 1
    return out


_FUNC_DEF_RE = re.compile(
    r"(?:^|[\s;&|(){])(?:function\s+)?([A-Za-z_][\w:.-]*)\s*\(\)\s*\{"
    r"|(?:^|[\s;&|(){])function\s+([A-Za-z_][\w:.-]*)\s*\{")


def find_functions(text):
    out = {}
    for m in _FUNC_DEF_RE.finditer(text):
        name = m.group(1) or m.group(2)
        start, depth, i, n, q = m.end(), 1, m.end(), len(text), None
        while i < n and depth:
            c = text[i]
            if q:
                if c == "\\" and q == '"':
                    i += 2
                    continue
                if c == q:
                    q = None
            elif c in "'\"":
                q = c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        out[name] = text[start:i - 1] if depth == 0 else text[start:]
    return out


# --------------------------------------------------------------------------
# Words
# --------------------------------------------------------------------------
CASE_RE = re.compile(r"^\s*case\b.*?\bin\b\s+[^\s()]*\)\s*")
ARM_RE = re.compile(r"^\s*[\w*?\[\]|.\-'\"]+\)\s+")
FUNC_RE = re.compile(r"^\s*(?:function\s+)?[A-Za-z_][\w:.-]*\s*\(\)\s*")
FUNCKW_RE = re.compile(r"^\s*function\s+[A-Za-z_][\w:.-]*\s*")
LEAD_RE = re.compile(r"^\s*(?:\(+|\{\s|\}\s*|!\s|(?:if|then|else|elif|do|while|until|fi|done|esac)\b\s*)")
_ANSI_RE = re.compile(r"\$'((?:[^'\\]|\\.)*)'", re.S)
_ARRAY_RE = re.compile(r"(?<![\w$])([A-Za-z_]\w*)=\(([^()]*)\)")
_IFS_RE = re.compile(r"\$\{IFS\}|\$IFS(?![A-Za-z0-9_])")


def clean_segment(seg):
    s = seg.strip()
    for _ in range(16):
        before = s
        for rx in (CASE_RE, ARM_RE, FUNC_RE, FUNCKW_RE, LEAD_RE):
            s = rx.sub("", s, 1)
        s = s.strip()
        if s == before:
            break
    while s.endswith(")") and s.count(")") > s.count("("):
        s = s[:-1].rstrip()
    return s


def decode_ansic(s):
    def rep(m):
        try:
            val = m.group(1).encode("latin-1", "backslashreplace").decode("unicode_escape")
        except Exception:
            val = m.group(1)
        return shlex.quote(val)
    return _ANSI_RE.sub(rep, s)


def arrays_flat(s):
    def rep(m):
        try:
            items = shlex.split(m.group(2))
        except ValueError:
            items = m.group(2).split()
        return m.group(1) + "=" + shlex.quote(ARRAY_TAG + ARRAY_SEP.join(items))
    return _ARRAY_RE.sub(rep, s)


def strip_quoted(s):
    return re.sub(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"", "", s)


def words_of(seg):
    s = clean_segment(seg)
    s = _IFS_RE.sub(" ", s)
    s = decode_ansic(s)
    s = arrays_flat(s)
    try:
        raw = shlex.split(s, posix=True, comments=False)
    except ValueError:
        raw = s.split()
    out, skip = [], False
    for x in raw:
        if skip:
            skip = False
            continue
        if re.fullmatch(r"\d*(?:>>?|<<<|<|&>>?|>&)", x):
            skip = True
            continue
        if "<" in x or ">" in x:
            head = re.split(r"[<>]", x, maxsplit=1)[0]
            if head and not head.isdigit():
                out.append(head)
            continue
        out.append(x)
    return out


def herestrings(seg):
    out = []
    for m in re.finditer(r"<<<\s*('[^']*'|\"(?:[^\"\\]|\\.)*\"|\S+)", seg):
        try:
            parts = shlex.split(m.group(1))
        except ValueError:
            parts = [m.group(1)]
        out.extend(parts)
    return out


def split_assign(words):
    i = 0
    while i < len(words) and ASSIGN_RE.match(words[i]):
        i += 1
    return words[:i], words[i:]


def strip_wrappers(words):
    w = list(words)
    while w:
        head = w[0]
        if ASSIGN_RE.match(head):
            w.pop(0)
            continue
        base = os.path.basename(head)
        if base not in WRAPPERS:
            break
        w.pop(0)
        optset = WRAP_OPTS.get(base, set())
        while w and w[0].startswith("-") and w[0] != "-":
            o = w.pop(0)
            if o == "--":
                break
            if base == "env" and o in ("-S", "--split-string"):
                if w:
                    s = w.pop(0)
                    try:
                        parts = shlex.split(s)
                    except ValueError:
                        parts = s.split()
                    w = parts + w
                continue
            if o in optset and w:
                w.pop(0)
        if base == "timeout" and w and re.fullmatch(r"\d+(?:\.\d+)?[smhd]?", w[0]):
            w.pop(0)
        for _ in range(WRAP_POS.get(base, 0)):
            if w:
                w.pop(0)
        if base == "flock" and w and w[0] in ("-c", "--command"):
            return w[1:2]
    return w


# --------------------------------------------------------------------------
# Variables and expansion
# --------------------------------------------------------------------------
def inert_stripped(text):
    """Drop comments and single-quoted strings: a guard token there never runs."""
    out, i, n = [], 0, len(text)
    dq = False
    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            out.append(text[i:i + 2]); i += 2; continue
        if not dq and c == "'":
            j = text.find("'", i + 1)
            i = n if j < 0 else j + 1
            out.append("''"); continue
        if c == '"':
            dq = not dq
        elif c == "#" and not dq and (i == 0 or text[i - 1] in " \t\n;&|("):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        out.append(c); i += 1
    return "".join(out)


_EXIT_WORDS = {"exit", "return"}  # `die` is not a builtin: an undefined one does not leave
_PRE_SAFE = {"echo", "printf", ":", "true", "logger"}
_COMPOUND = {"if", "then", "else", "elif", "fi", "while", "until", "do", "done", "case", "esac", "for",
             "select", "function", "!", "time", "coproc", "}", "{", "(", ")"}
_CONT_STRIP = re.compile(r"^(?:\{|then|else|do)\s+")


@functools.lru_cache(maxsize=64)
def live_segments(text):
    """Executable statements only, as the segmenter sees them (heredoc bodies and comments are
    already dropped; quoting is respected, so text inside a string is never a separate statement)."""
    return tuple(segment(text.replace("\\\n", ""))[0])


def _plain_seps(sep):
    return sep != "" and all(ch in ";\n" for ch in sep)


def _leaves(segs, j):
    """From statement j: simple statements (separated by ';' or newline) up to a bare exit/return/die.
    Compound commands, subshells, and other operators before the exit make this False."""
    first = True
    for k in range(j, min(len(segs), j + 40)):
        seg, sep = segs[k]
        if not first and not _plain_seps(sep):
            return False
        text = seg.strip()
        if first:
            text = _CONT_STRIP.sub("", text, count=1)
        first = False
        if text in ("{", "then", "else", "do"):
            continue  # opener on its own line: the body follows
        words = text.split()
        w = words[0] if words else ""
        if w in _EXIT_WORDS:
            return True
        if not w or w in _COMPOUND or w[0] in "({":
            return False
        # a statement that runs BEFORE the exit also runs when the guard fires: it must be harmless
        if w not in _PRE_SAFE or "`" in text or "$(" in text or "<(" in text or ">(" in text or destructive_text(text):
            return False
    return False


_TEST_GENERIC = re.compile(r"^(?:(?:if|then|elif|while)\s+|\{\s*)?(\[\[|\[|test)\s+(-n|!\s+-z|-z)\s+(\"?)\$\{?([A-Za-z_]\w*|[0-9]|[@*])\}?(\"?)\s*(?:\]\]?)?\s*$")


@functools.lru_cache(maxsize=64)
def guarded_vars(text):
    """Names of variables guarded by a real statement in `text` (computed once per text)."""
    segs = live_segments(text)
    joined = inert_stripped("".join(("" if i == 0 else sp) + sg for i, (sg, sp) in enumerate(segs)))
    names = set(re.findall(r"\$\{([A-Za-z_]\w*|[0-9]|[@*]):\?", joined))
    n = len(segs)
    for i in range(n - 1):
        m = _TEST_GENERIC.match(segs[i][0].strip())
        if not m:
            continue
        form, op, q1, name, q2 = m.groups()
        kind = "z" if op == "-z" else "n"
        # `[ -n $V ]` / `test -n $V` with an empty V is `[ -n ]`, which is TRUE: quotes are required there
        if kind == "n" and form != "[[" and not (q1 and q2):
            continue
        if kind == "n" and form != "[[" and name == "@":
            continue  # "$@" with no arguments expands to nothing: `[ -n ]` is TRUE
        nxt_sep = segs[i + 1][1].strip()
        if kind == "n" and nxt_sep == "||" and _leaves(segs, i + 1):
            names.add(name)
        elif kind == "z":
            if nxt_sep == "&&" and _leaves(segs, i + 1):
                names.add(name)
            elif _plain_seps(segs[i + 1][1]) and re.match(r"^\s*if\b", segs[i][0]) \
                    and segs[i + 1][0].strip().startswith("then") and _leaves(segs, i + 1):
                names.add(name)
    return frozenset(names)


def has_guard(var, text):
    """A guard counts only if it is a real statement: `${VAR:?}` in executable text, or a whole
    `[ -n "$V" ]` / `[ ! -z "$V" ]` statement followed by `|| <leave>`, or a whole `[ -z $V ]`
    statement followed by `&& <leave>` or `; then <leave>`. Linear, no backtracking."""
    return var in guarded_vars(text)


def var_value(name, env, ctx):
    if name in env:
        return env[name]
    if name == "HOME":
        return HOMEVAR
    if (name.isdigit() and name != "0") or name in ("@", "*"):
        return SV if has_guard(name, ctx) else TV
    if name in ("0", "#", "?", "$", "!", "-"):
        return SV
    return SV if has_guard(name, ctx) else UV


def expand(tok, env, ctx):
    def rep(m):
        if m.group(1) is not None:
            inner = m.group(1)
            if inner.startswith("!"):
                return TV          # indirect expansion: any variable's value
            mm = re.match(r"([A-Za-z_]\w*|[0-9]|[@*#?!$-])(.*)$", inner, re.S)
            if not mm:
                return UV
            name, op = mm.group(1), mm.group(2)
            if op.startswith(":?") or op.startswith("?"):
                return SV
            base = var_value(name, env, ctx)
            dm = re.match(r"(:?[-=])(.*)$", op, re.S)
            if dm:
                dflt = expand(dm.group(2), env, ctx)
                if dflt and base in (UV, TV, ""):
                    return dflt
                return base
            if op.startswith(":+") or op.startswith("+"):
                word = op[2:] if op.startswith(":+") else op[1:]
                return UV + expand(word, env, ctx)
            return base
        return var_value(m.group(2), env, ctx)
    return VAR_RE.sub(rep, tok)


def tilde(tgt):
    m = re.match(r"~([^/]*)(.*)$", tgt, re.S)
    if not m:
        return tgt
    name, rest = m.group(1), m.group(2)
    if name == "":
        return "${HOME}" + rest
    if name in ("+", "-"):
        return tgt
    try:
        home = pwd.getpwnam(name).pw_dir
    except KeyError:
        return tgt
    if os.path.realpath(home) == real_home():
        return "${HOME}" + rest
    return home + rest


def _find_brace(t):
    for i, ch in enumerate(t):
        if ch != "{" or (i and t[i - 1] == "$"):
            continue
        depth, parts, last = 0, [], i + 1
        for j in range(i, len(t)):
            c = t[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    parts.append(t[last:j])
                    if len(parts) > 1:
                        return t[:i], parts, t[j + 1:]
                    break
            elif c == "," and depth == 1:
                parts.append(t[last:j])
                last = j + 1
    return None


def brace_expand(tok):
    out = [tok]
    for _ in range(4):
        nxt, changed = [], False
        for t in out:
            m = _find_brace(t)
            if not m:
                nxt.append(t)
                continue
            pre, alts, post = m
            nxt.extend(pre + a + post for a in alts)
            changed = True
        out = nxt[:64]
        if not changed:
            break
    return out


def normpath_home(s):
    parts = s.split("/")
    symbolic = parts[0] == HOMEVAR
    stack = [HOMEVAR] if symbolic else []
    seq = parts[1:] if (symbolic or parts[0] == "") else parts
    for p in seq:
        if p in ("", "."):
            continue
        if p == "..":
            if stack == [HOMEVAR]:
                stack = [q for q in real_home().split("/") if q][:-1]
            elif stack:
                stack.pop()
            continue
        stack.append(p)
    if stack and stack[0] == HOMEVAR:
        return "/".join(stack)
    return "/" + "/".join(stack)


def resolve_path(s, cwd):
    if not (s.startswith("/") or s.startswith(HOMEVAR)):
        if cwd is None:
            return s
        s = cwd.rstrip("/") + "/" + s
    return normpath_home(s)


def strip_tail(t):
    changed = True
    while changed:
        changed = False
        for suf in ("/*", "/.*", "/.", "/"):
            if len(t) > len(suf) and t.endswith(suf):
                t = t[:-len(suf)]
                changed = True
    return t


def real_alias(path):
    """The on-disk realpath of a plain absolute path when it differs (symlinks)."""
    if any(mk in path for mk in MARKERS) or GLOB_RE.search(path):
        return None
    if path.startswith(HOMEVAR):
        path = real_home() + path[len(HOMEVAR):]
    if not path.startswith("/"):
        return None
    try:
        rp = os.path.realpath(strip_tail(path))
    except Exception:
        return None
    return rp if rp != strip_tail(path) else None


def protected_reason(t):
    if not t or t.startswith("-"):
        return None
    t = re.sub(r"/{2,}", "/", t)
    if t in ("/", "/*", "/.*", "/."):
        return "the filesystem root"
    rh = real_home()
    if (t.startswith("/") or t.startswith(HOMEVAR)) and GLOB_RE.search(t):
        probe = rh + t[len(HOMEVAR):] if t.startswith(HOMEVAR) else t
        prot = protected_paths(rh)
        for pat in (probe, strip_tail(probe)):
            if GLOB_RE.search(pat):
                for p in sorted(prot):
                    if fnmatch.fnmatchcase(p, pat):
                        return "a glob that can match a protected path (%s)" % p
    t = strip_tail(t)
    if t == "":
        return "the filesystem root"
    if t.startswith("/"):
        if t == rh:
            t = HOMEVAR
        elif t.startswith(rh + "/"):
            t = HOMEVAR + t[len(rh):]
    if t == HOMEVAR:
        return "the home directory"
    if t.startswith(HOMEVAR + "/"):
        rest = t[len(HOMEVAR) + 1:]
        first = rest.split("/")[0]
        if "/" not in rest and (first in HOME_CHILDREN or first.startswith(HOME_CHILD_PREFIXES) or first in ("*", ".*")):
            return "a protected directory under the home directory (%s)" % first
        return None
    if t in SYSTEM_DIRS:
        return "a system directory (%s)" % t
    if re.fullmatch(r"/home/[^/]+", t) or re.fullmatch(r"/Users/[^/]+", t):
        return "a user's home directory"
    return None


def at_risk(path):
    """Full paths a `find` rooted at `path` could delete that are protected: itself and protected children."""
    rh = real_home()
    base = rh + path[len(HOMEVAR):] if path.startswith(HOMEVAR) else path
    base = base.rstrip("/") or "/"
    prot = protected_paths(rh)
    return {base} | {p for p in prot if posixpath.dirname(p) == base and p != base}


# --------------------------------------------------------------------------
# Destructive commands
# --------------------------------------------------------------------------
XARGS_ARG = {"-n", "-I", "-P", "-d", "-L", "-s", "-E", "-a", "-J"}
PARALLEL_ARG = {"-j", "-n", "-N", "-a", "-S", "-I", "--jobs", "--max-args", "--arg-file",
                "--sshlogin", "--replace"}
FIND_ACTIONS = ("-exec", "-execdir", "-ok", "-okdir")
FIND_NAMES = ("-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename",
              "-regex", "-iregex")


def parse_find(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-H", "-L", "-P") or re.fullmatch(r"-O\d?", a):
            i += 1
        elif a == "-D":
            i += 2
        else:
            break
    paths = []
    while i < len(args) and not args[i].startswith("-") and args[i] not in ("(", "!", ")"):
        paths.append(args[i])
        i += 1
    return paths, args[i:]


def find_expr(rest):
    info = {"delete": False, "execs": [], "names": [], "unsafe": False, "action_idx": len(rest)}
    k = 0
    while k < len(rest):
        a = rest[k]
        if a == "-delete":
            info["delete"] = True
            info["action_idx"] = min(info["action_idx"], k)
        elif a in FIND_ACTIONS:
            j, cmd = k + 1, []
            while j < len(rest) and rest[j] not in (";", "+"):
                cmd.append(rest[j])
                j += 1
            info["execs"].append(cmd)
            info["action_idx"] = min(info["action_idx"], k)
            k = j
        elif a in FIND_NAMES and k + 1 < len(rest):
            info["names"].append((a, rest[k + 1], k))
            k += 1
        elif a in ("!", "-not", "-o", "-or", "(", ")"):
            info["unsafe"] = True
        k += 1
    return info


def find_paths(words):
    w = strip_wrappers(words)
    if not w or os.path.basename(w[0]) != "find":
        return None
    paths, _ = parse_find(w[1:])
    return paths or ["."]


def _xargs_like(cmd, args, pipe):
    i = 0
    if cmd == "xargs":
        file_input = False
        while i < len(args) and args[i].startswith("-"):
            if args[i] in ("-a", "--arg-file"):
                file_input = True
            i += 2 if args[i] in XARGS_ARG else 1
        r = delete_targets(args[i:], None)
        if not r:
            return None
        kind, tg, extra = r
    else:
        while i < len(args) and args[i].startswith("-"):
            i += 2 if args[i] in PARALLEL_ARG else 1
        body = args[i:]
        file_input = False
        sep = next((s for s in (":::", "::::") if s in body), None)
        if sep:
            k = body.index(sep)
            cmdw, vals = body[:k], body[k + 1:]
            variants = ([[v if x == "{}" else x for x in cmdw] for v in vals]
                        if "{}" in cmdw else [cmdw + vals])
            kind, tgs = None, []
            for var in variants:
                r = delete_targets(var, None)
                if r:
                    kind = r[0]
                    tgs.extend(r[1])
            if kind is None:
                return None
            return kind + " via parallel", tgs, {}
        r = delete_targets(body, None)
        if not r:
            return None
        kind, tg, extra = r
    explicit = [x for x in tg if x not in ("{}", "")]
    if explicit:
        targets, unknown = explicit, False
    elif not file_input and pipe and pipe[0] in ("find", "lit"):
        targets, unknown = list(pipe[1]), False
    else:
        targets, unknown = [], True
    ex = dict(extra)
    ex["unknown_input"] = unknown
    return kind + " via " + cmd, targets, ex


def delete_targets(words, pipe=None):
    """Return (kind, [targets], extra) for a destructive invocation, else None."""
    w = strip_wrappers(words)
    if not w:
        return None
    cmd = os.path.basename(w[0])
    args = w[1:]
    if cmd in ("xargs", "parallel"):
        return _xargs_like(cmd, args, pipe)
    if cmd in RECURSIVE_CMDS:
        recursive = cmd == "shred"
        tgts, end = [], False
        for a in args:
            if not end and a == "--":
                end = True
                continue
            if not end and a.startswith("-"):
                if a.startswith("--"):
                    if len(a) >= 3 and "--recursive".startswith(a.split("=")[0]):
                        recursive = True
                elif re.search(r"[rR]", a):
                    recursive = True
                continue
            tgts.append(a)
        return ("%s -r" % cmd, tgts, {}) if recursive else None
    if cmd in OWNERSHIP_CMDS:
        rec, mode_done, pos, end = False, False, [], False
        for a in args:
            if end:
                pos.append(a)
                continue
            if a == "--":
                end = True
                continue
            if a.startswith("--"):
                name = a.split("=")[0]
                if len(name) >= 5 and "--recursive".startswith(name):
                    rec = True
                elif len(name) >= 5 and "--reference".startswith(name):
                    mode_done = True
                continue
            if a.startswith("-") and len(a) > 1:
                letters = a[1:]
                if cmd == "chmod" and not re.fullmatch(r"[RvcfHLP]+", letters):
                    mode_done = True   # a symbolic mode such as -w or -rwx
                    continue
                if "R" in letters:
                    rec = True
                continue
            pos.append(a)
        if not rec:
            return None
        return cmd + " -R", (pos if mode_done else pos[1:]), {}
    if cmd == "find":
        paths, rest = parse_find(args)
        info = find_expr(rest)
        deletes, strings = info["delete"], []
        for ex in info["execs"]:
            cw = strip_wrappers(ex)
            if not cw:
                continue
            b = os.path.basename(cw[0])
            if b in ("rm", "shred", "unlink", "rmdir"):
                deletes = True
            elif b in SHELLS:
                for k, x in enumerate(cw[1:], 1):
                    if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", x) and k + 1 < len(cw):
                        strings.append(cw[k + 1])
                        if DESTRUCT_RE.search(cw[k + 1]):
                            deletes = True
                        break
        if not deletes:
            return None
        return "find -delete", (paths or ["."]), {"find": info, "shell_strings": strings}
    if cmd == "rsync":
        flag = any(a == "--del" or a.startswith("--delete") or a in ("--remove-source-files", "--remove-sent-files")
                   for a in args)
        if flag:
            pos = [a for a in args if not a.startswith("-")]
            rem = "--remove-source-files" in args or "--remove-sent-files" in args
            return "rsync --delete", (pos if rem else pos[-1:]), {}
        return None
    if cmd == "mv":
        pos, tdir, end, k = [], False, False, 0
        while k < len(args):
            a = args[k]
            k += 1
            if end:
                pos.append(a)
                continue
            if a == "--":
                end = True
                continue
            if a == "-t" or a.startswith("--target-directory"):
                tdir = True
                if a == "-t" and k < len(args):
                    k += 1
                continue
            if a.startswith("-t") and not a.startswith("--") and len(a) > 2:
                tdir = True
                continue
            if a in ("-S", "--suffix"):
                k += 1
                continue
            if a.startswith("-"):
                continue
            pos.append(a)
        srcs = pos if tdir else pos[:-1]
        return ("mv", srcs, {}) if srcs else None
    return None


# --------------------------------------------------------------------------
# Analysis
# --------------------------------------------------------------------------
def _match(name, pat, ci):
    if ci:
        name, pat = name.lower(), pat.lower()
    return fnmatch.fnmatchcase(name, pat)


class State:
    def __init__(self, ctx, env=None, cwd=None, findings=None, markers=None,
                 funcs=None, links=None, active=None):
        self.ctx = ctx
        self.env = env if env is not None else {}
        self.cwd = cwd
        self.findings = findings if findings is not None else []
        self.markers = markers if markers is not None else []
        self.funcs = funcs if funcs is not None else {}
        self.links = links if links is not None else {}
        self.active = active if active is not None else set()

    def child(self, text, fresh=False, positional=None):
        if fresh:
            st = State(text + "\n" + self.ctx, {}, None, self.findings, self.markers,
                       self.funcs, self.links, self.active)
        else:
            st = State(self.ctx + "\n" + text, dict(self.env), self.cwd, self.findings,
                       self.markers, self.funcs, self.links, self.active)
        if positional is not None:
            for k in [k for k in st.env if k.isdigit()]:
                del st.env[k]
            for n, v in enumerate(positional, 1):
                st.env[str(n)] = v
            st.env["@"] = st.env["*"] = ARRAY_SEP.join(positional)
            st.env["#"] = SV
        return st

    def add(self, cls, msg):
        self.findings.append((cls, msg))

    def apply_assign(self, name, raw, plus, env):
        if raw.startswith(ARRAY_TAG):
            body = raw[1:]
            val = ARRAY_SEP.join(expand(x, env, self.ctx) for x in body.split(ARRAY_SEP)) if body else ""
        elif raw.startswith("$(") or raw.startswith("`"):
            inner = raw[2:] if raw.startswith("$(") else raw[1:]
            val = SV if re.match(r"\s*(?:command\s+)?mktemp\b", inner) else UV
        else:
            val = expand(raw, env, self.ctx)
        if plus and name in env:
            val = env[name] + val
        if has_guard(name, self.ctx):
            val = val.replace(TV, SV).replace(UV, SV)
        env[name] = val

    def link_resolve(self, path):
        p = strip_tail(path)
        hit_any = False
        for _ in range(8):
            hit = None
            for link, target in self.links.items():
                if p == link or p.startswith(link + "/"):
                    hit = target + p[len(link):]
                    break
            if hit is None:
                break
            p, hit_any = hit, True
        return p if hit_any else path

    def find_ok(self, path, filt):
        """True when a name/path filter placed before the action keeps `find` away from protected names."""
        if filt["unsafe"]:
            return False
        fulls = at_risk(path)
        names = [posixpath.basename(f) for f in fulls if posixpath.basename(f)]
        for flag, pat, idx in filt["names"]:
            if idx > filt["action_idx"]:
                continue
            ci = flag.startswith("-i")
            if flag in ("-name", "-iname"):
                if not any(_match(n, pat, ci) for n in names):
                    return True
            elif flag in ("-path", "-ipath", "-wholename", "-iwholename"):
                if not any(_match(f, pat, ci) for f in fulls):
                    return True
        return False

    def check_target(self, kind, tgt, env, filt=None, only_p=False):
        if not tgt or tgt.startswith("-"):
            return
        for variant in brace_expand(tgt):
            self._check_one(kind, variant, env, filt, only_p)

    def _check_one(self, kind, tgt, env, filt, only_p):
        if not tgt or tgt.startswith("-"):
            return
        hv = env.get("HOME")
        if hv is not None and re.search(r"\$\{?HOME\b|^~(?:/|$)", tgt):
            home_taint = TV in hv or UV in hv  # MUT-H
            if home_taint:
                if not only_p:
                    self.add("H", "HOME is reassigned from an expansion that can be empty or tainted, then %s deletes %s — if the expansion is empty HOME becomes a real directory such as /home" % (kind, tgt))
                return
        expanded = expand(tilde(tgt), env, self.ctx)
        for piece in expanded.split(ARRAY_SEP):
            self._check_expanded(kind, tgt, piece, filt, only_p)

    def _check_expanded(self, kind, tgt, s, filt, only_p):
        if TV in s:  # MUT-V
            if not only_p:
                self.add("V", "%s deletes %s but it derives from an unguarded positional parameter or an indirect expansion — an empty or wrong value makes the target wrong; use ${VAR:?}" % (kind, tgt))
            return
        if SV in s:
            if not re.search(r"(?:^|/)\.\.(?:/|$)", s):
                return
            # a safe prefix followed by '..' can land anywhere (even on a sibling of the prefix)
            if not only_p:
                self.add("V", "%s deletes %s: a '..' component after a guarded or temporary prefix can leave that prefix's subtree" % (kind, tgt))
            return
        if UV in s:
            u = s.replace(UV, "")
            if u and (u.startswith("/") or u.startswith(HOMEVAR)):
                why = protected_reason(self.link_resolve(resolve_path(u, None)))
                if why and not only_p:
                    self.add("V", "%s deletes %s; if the unknown/empty variable in it is empty the target is %s — use ${VAR:?} or safe_rm_rf" % (kind, tgt, why))
            return
        path = self.link_resolve(resolve_path(s, self.cwd))
        why = protected_reason(path)
        if not why:
            real = real_alias(path)
            if real:
                why = protected_reason(real)
        if why:
            if filt is not None and self.find_ok(path, filt):
                return
            self.add("P", "%s targets %s (%s)" % (kind, why, tgt))


def analyse(text, st, depth=0):
    text = text.replace("\\\n", "")
    if depth > MAX_DEPTH:
        if destructive_text(text):
            st.add("X", "nesting deeper than %d levels cannot be inspected and it contains a destructive command" % MAX_DEPTH)
        return
    segs, heredocs, comments, problems = segment(text)
    if problems and destructive_text(text):
        st.add("X", "the command cannot be parsed reliably (%s) and it contains a destructive command" % "; ".join(sorted(set(problems))))
    if depth == 0:
        for c, nested in comments:
            if nested:
                continue
            m = MARKER_RE.match(c.strip())
            if m:
                st.markers.append(m.group(1).strip())
    st.funcs.update(find_functions(text))

    def run_string(s, env):
        """Analyse a string a shell will execute; a lone variable reference is resolved first."""
        if re.fullmatch(r"\s*\$\{?[A-Za-z_]\w*\}?\s*", s):
            s2 = expand(s, env, st.ctx)
            if not any(mk in s2 for mk in MARKERS):
                analyse(s2, st.child(s2), depth + 1)
            elif TV in s2 or UV in s2:
                if DESTRUCT_RE.search(st.ctx):
                    st.add("U", "a shell would run %s, whose value the guard cannot read, in a command that also contains a destructive command" % s.strip())
            return
        analyse(s, st.child(s), depth + 1)

    def resolve_head(w, env):
        head = w[0]
        if "$" not in head and "`" not in head:
            return w
        h2 = expand(head, env, st.ctx)
        unknown = TV in h2 or UV in h2 or "$(" in head or "`" in head
        if not unknown and SV not in h2 and h2.strip():
            try:
                parts = shlex.split(h2)
            except ValueError:
                parts = h2.split()
            return strip_wrappers(parts + w[1:])
        if unknown and any(RECUR_FLAG_RE.fullmatch(a) for a in w[1:]):
            st.add("V", "the command word %s is an unresolved expansion used with recursive/force flags — it may be a destructive command; use a literal command" % head)
        return w

    def handle(seg_text, sep, prev):
        for inner in balanced_subst(seg_text):
            analyse(inner, st.child(inner), depth + 1)
        words = words_of(seg_text)
        if not words:
            return None
        assigns, rest = split_assign(words)
        env = st.env
        if assigns and rest:
            env = dict(st.env)
        for a in assigns:
            m = ASSIGN_RE.match(a)
            st.apply_assign(m.group(1), m.group(3), bool(m.group(2)), env)
        w = strip_wrappers(rest)
        if not w:
            return None
        w = resolve_head(w, env)
        if not w:
            return None
        if re.search(r"\s", w[0]) and not w[0].startswith("-"):
            analyse(" ".join(w), st.child(" ".join(w)), depth + 1)
            return None
        base = os.path.basename(w[0])
        if base == "for" and len(w) >= 3 and w[2] == "in":
            vals = [expand(x, env, st.ctx) for x in w[3:]]
            env[w[1]] = TV if any(TV in v for v in vals) else (UV if any(UV in v for v in vals) else SV)
            return None
        if base == "read":
            names = [x for x in w[1:] if re.fullmatch(r"[A-Za-z_]\w*", x)] or ["REPLY"]
            for nme in names:
                env[nme] = UV
            return None
        if base == "set":
            if "--" in w:
                vals = [expand(x, env, st.ctx) for x in w[w.index("--") + 1:]]
                for k in [k for k in env if k.isdigit()]:
                    del env[k]
                for n, v in enumerate(vals, 1):
                    env[str(n)] = v
                env["@"] = env["*"] = ARRAY_SEP.join(vals)
            return None
        if base == "printf" and "-v" in w:
            k = w.index("-v")
            if k + 1 < len(w):
                fmt = w[k + 2] if k + 2 < len(w) else ""
                env[w[k + 1]] = UV if "%" in fmt else expand(fmt, env, st.ctx)
            return None
        if base in ("cd", "pushd"):
            argv = [x for x in w[1:] if not x.startswith("-")]
            if not argv:
                st.cwd = HOMEVAR
            else:
                s = expand(tilde(argv[0]), env, st.ctx)
                st.cwd = None if any(mk in s for mk in MARKERS) else resolve_path(s, st.cwd)
            return None
        if base in DECLARERS:
            for x in w[1:]:
                m = ASSIGN_RE.match(x)
                if m:
                    st.apply_assign(m.group(1), m.group(3), bool(m.group(2)), env)
            return None
        if base == "ln" and any(x.startswith("-") and "s" in x for x in w[1:]):
            pos = [x for x in w[1:] if not x.startswith("-")]
            if len(pos) >= 2:
                tgt = expand(tilde(pos[0]), env, st.ctx)
                link = expand(tilde(pos[-1]), env, st.ctx)
                if not any(mk in tgt + link for mk in MARKERS):
                    st.links[strip_tail(resolve_path(link, st.cwd))] = strip_tail(resolve_path(tgt, st.cwd))
            return None
        if base in st.funcs and base not in st.active:
            body = st.funcs[base]
            st.active.add(base)
            try:
                pos = [expand(x, env, st.ctx) for x in w[1:]]
                analyse(body, st.child(body, positional=pos), depth + 1)
            finally:
                st.active.discard(base)
            return None
        if base in SHELLS:
            has_c = False
            for k, x in enumerate(w[1:], 1):
                if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", x) and k + 1 < len(w):
                    has_c = True
                    run_string(w[k + 1], env)
                    break
            if not has_c and base in STDIN_SHELLS and all(x.startswith("-") for x in w[1:]):
                for s in herestrings(seg_text):
                    run_string(s, env)
                if sep in ("|", "|&"):
                    if prev and prev[0] == "lit":
                        for s in [" ".join(prev[1])] + list(prev[1]):
                            analyse(s, st.child(s), depth + 1)
                    elif not (prev and prev[0] == "heredoc"):
                        st.add("U", "code is piped into a shell from a source the guard cannot read — it could contain a destructive command")
        elif base == "eval":
            run_string(" ".join(w[1:]), env)
        elif base == "trap" and len(w) > 1 and not w[1].startswith("-"):
            run_string(w[1], env)
        pipe = prev if sep in ("|", "|&") else None
        res = delete_targets(w, pipe)
        if res:
            kind, targets, extra = res
            for s in extra.get("shell_strings", []):
                run_string(s, env)
            if extra.get("unknown_input"):
                st.add("V", "%s reads its targets from input the guard cannot inspect — pass explicit, guarded paths" % kind)
            for tgt in targets:
                st.check_target(kind, tgt, env, extra.get("find"), kind == "mv")
        if base == "find":
            return ("find", find_paths(w) or ["."])
        if base in ("echo", "printf"):
            return ("lit", [x for x in w[1:] if not (x.startswith("-") and base == "echo")])
        if base == "cat" and "<<" in seg_text:
            return ("heredoc", None)
        return ("other", None)

    scope, prev = [], None
    for seg_text, sep in segs:
        stripped = strip_quoted(seg_text).strip()
        lead = 0 if stripped.startswith("((") else len(stripped) - len(stripped.lstrip("("))
        for _ in range(lead):
            scope.append((st.cwd, dict(st.env)))
        prev = handle(seg_text, sep, prev)
        body = stripped.lstrip("(")
        closes = max(0, body.count(")") - body.count("("))
        for _ in range(min(closes, len(scope))):
            st.cwd, st.env = scope.pop()
    for seg_text, body, quoted, stages in heredocs:
        sw = strip_wrappers(words_of(seg_text))
        head = os.path.basename(sw[0]) if sw else ""
        stage_heads = []
        for stg in stages:
            sws = strip_wrappers(words_of(stg))
            stage_heads.append(os.path.basename(sws[0]) if sws else "")
        if not quoted:
            for inner in balanced_subst(body):
                analyse(inner, st.child(inner), depth + 1)
        writes_file = ">" in seg_text or head == "tee"
        shellish = ("bash", "sh", "zsh", "dash", "ksh", "source", ".", "su", "eval")

        def starts_shell(t):
            ws = words_of(t)
            if not ws:
                return False
            b0 = os.path.basename(ws[0])
            if b0 in ("sudo", "doas", "pkexec", "run0") and any(x in ("--shell", "--login") or re.fullmatch(r"-[A-Za-z]*[si][A-Za-z]*", x) for x in ws[1:]):
                return True
            sw2 = strip_wrappers(ws)
            h2 = os.path.basename(sw2[0]) if sw2 else ""
            if h2 in shellish:
                return True
            return h2 == "xargs" and any(os.path.basename(x) in shellish for x in sw2[1:])

        feeds_shell = head in shellish or starts_shell(seg_text) or any(starts_shell(t) for t in stages)
        if not feeds_shell and head in st.funcs:
            feeds_shell = any(starts_shell(pc) for pc in re.split(r"[;&|\n{}]+", st.funcs[head]))
        if not feeds_shell:
            # the `<<` may sit inside a substitution of the owner statement: `x=$(bash <<E); y=$(...)`
            for inner in balanced_subst(seg_text):
                if "<<" in inner and any(starts_shell(pc) for pc in re.split(r"[;&|\n]+", inner)):
                    feeds_shell = True
                    break
        if head in ("cat", "tee") and writes_file:
            if scriptish(heredoc_dest(seg_text, head), body):
                analyse(body, st.child(body, fresh=True), depth + 1)
        elif feeds_shell:
            analyse(body, st.child(body, fresh=True), depth + 1)


def heredoc_dest(seg_text, head):
    m = list(re.finditer(r">>?\s*([^\s;&|<>()]+)", seg_text))
    if m:
        return m[-1].group(1)
    if head == "tee":
        pos = [x for x in words_of(seg_text)[1:] if not x.startswith("-")]
        return pos[-1] if pos else ""
    return ""


def scriptish(dest, body):
    if body.startswith("#!") or not dest or "$" in dest:
        return True
    low = os.path.basename(dest).lower()
    ext = os.path.splitext(low)[1]
    return ext in (".sh", ".bash", ".zsh", ".ksh", ".mk", "") or low in ("makefile", "justfile", "dockerfile")


def make_lines(body, just=False):
    out = []
    for line in body.split("\n"):
        if line[:1] == "\t" or (just and line[:1] == " " and line.strip()):
            l = line.strip()
            l = re.sub(r"^[@\-+]+", "", l)
            l = l.replace("$(RM)", "rm -f").replace("${RM}", "rm -f").replace("$$", "$")
            l = re.sub(r"\$\(([A-Za-z_][\w-]*)\)", r"${\1}", l)
            out.append(l)
    return "\n".join(out)


def yaml_lines(body):
    out = []
    for line in body.split("\n"):
        l = line.strip()
        l = re.sub(r"^-\s+", "", l)
        l = re.sub(r"^(?:run|script|command|cmd|shell|before_script|after_script)\s*:\s*", "", l)
        l = l.strip()
        if len(l) > 1 and l[0] == l[-1] and l[0] in "'\"":
            l = l[1:-1]
        if l in ("|", ">", "|-", ">-"):
            continue
        out.append(l)
    return "\n".join(out)


def script_text(path, body):
    """The part of a written file that a shell would execute, or None when the file is data."""
    path = path or ""
    low = os.path.basename(path).lower()
    if re.search(r"\.(sh|bash|zsh|ksh)$", low) or re.match(r"#!.*\b(ba|z|da|k)?sh\b", body):
        return body
    if low in ("makefile", "gnumakefile") or low.endswith(".mk"):
        return make_lines(body)
    if low == "justfile":
        return make_lines(body, just=True)
    if low == ".gitlab-ci.yml" or re.search(r"(^|/)\.github/workflows/[^/]+\.ya?ml$", path):
        return yaml_lines(body)
    if low == "dockerfile":
        return "\n".join(re.sub(r"^\s*RUN\s+", "", l) for l in body.split("\n") if re.match(r"\s*RUN\s", l))
    return None


def run(payload):
    tool = payload.get("tool_name", "")
    ti = payload.get("tool_input", {}) or {}
    texts = []
    if tool == "Bash":
        cmd = ti.get("command", "")
        if not isinstance(cmd, str):
            print("guard-destructive-paths: WARNING — command is not a string (%s), allowing; NOT inspected" % type(cmd).__name__, file=sys.stderr)
            return 0
        texts.append(cmd)
    elif tool in ("Write", "Edit", "MultiEdit"):
        path = ti.get("file_path", "") or ""
        body = ti.get("content") or ti.get("new_string") or ""
        if tool == "MultiEdit":
            body = "\n".join(str(e.get("new_string", "")) for e in ti.get("edits", []) or [])
        if not isinstance(body, str):
            print("guard-destructive-paths: WARNING — content is not a string, allowing; NOT inspected", file=sys.stderr)
            return 0
        text = script_text(path, body)
        if text is not None:
            texts.append(text)
    findings, markers = [], []
    for t in texts:
        analyse(t, State(t, findings=findings, markers=markers))
    if not findings:
        return 0
    marker = markers[0] if markers else None
    hard = ("P", "X")
    blocking = [f for f in findings if f[0] in hard or marker is None]
    for cls, msg in findings:
        tag = "BLOCKED" if (cls in hard or marker is None) else "WARNING (allowed by '# guardrails:allow %s')" % marker
        print("guardrails: %s — §11.4.287 class %s: %s" % (tag, cls, msg), file=sys.stderr)
    if blocking:
        print("Use scripts/lib/safe_rm.sh (safe_rm_rf), guard variables with ${VAR:?}, and never reassign HOME from an expansion that can be empty. Classes P and X are not overridable.", file=sys.stderr)
        return 2
    return 0


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        print("guard-destructive-paths: WARNING — unparsable payload, allowing (cannot inspect)", file=sys.stderr)
        return 0
    try:
        return run(payload)
    except Exception as exc:  # fail open, but never silently
        print("guard-destructive-paths: ERROR — internal failure (%s: %s); allowing, the command was NOT inspected" % (type(exc).__name__, exc), file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main())
