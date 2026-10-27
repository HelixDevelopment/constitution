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
ALLOW, so this guard never lets an exception escape: an internal failure in the
analysis of a text is class X (blocked, with a fallback scan for the reason),
an internal failure anywhere else in run() blocks with exit 2, and a command or
content that is not a string is class X. The one deliberate exception is a
payload that is not JSON at all: Claude Code always sends JSON, so that input is
not a reachable tool call, and blocking on it would block all work
(§11.4.201(1)); it is allowed (with a warning on stderr) only when its raw text
shows no destructive command, and blocked with exit 2 when `raw_scan` sees one
(tested).

WORKING DIRECTORY (fix round 4, structural). The guard threads the effective cwd
through the analysis as state with three values: KNOWN (a literal path), None
(the hook payload gave none) and LOST (a marker: something moved the shell to a
place the text cannot resolve). A cwd-changing construct sets it: `cd`/`pushd`/
`popd`, `CDPATH` lookups, `env -C`/`--chdir`, `sudo -D`/`--chdir`/`-i`/`-R`,
`run0 -D`/`--chdir`, `systemd-run --working-directory`, `unshare -w`, `su -`,
`pkexec`, `nsenter`, `chroot`. Wrappers not in that table are assumed to keep
the cwd. While the cwd is LOST, a RELATIVE destructive target blocks (class V,
overridable with a reasoned marker) when it walks `..`, is a whole-directory
token (`*`, `.*`, `.`) of a recursive delete, or its components equal the tail
of a protected path (`home`, `Projects`, `usr`, ...). Names like `build` or
`dist/out` stay allowed. Remedy: cd to a literal path, guard the cd with
`${VAR:?}`, or use an absolute path.
HONEST LIMITS of the cwd model: a destructive string run on another host
(`ssh`), inside an interpreter (`python -c`), under an unlisted wrapper that
changes directory (strace, ltrace, gdb, faketime, proot, firejail, bwrap), an
INHERITED CDPATH (not set in the text), a failed `cd` (the shell stays where it
was), `shopt cdable_vars`, and sourced scripts are not modelled; Write/Edit
payloads carry no cwd (None).

CLASSES
  P  PROTECTED TARGET  (NOT overridable): the target, resolved from literals and
     the real $HOME only, is `/`, a system directory, `/home`, a user home, the
     home directory, ANY ancestor of the home directory at any depth (both the
     resolved home and $HOME as written), a protected child of it, or a glob that
     can match one.
  X  UNPARSABLE / TOO DEEP (NOT overridable): the text cannot be parsed reliably
     (unterminated quote, `$(`, backtick or heredoc; shell re-parse depth over
     MAX_DEPTH=5 or total analysis nesting over MAX_FRAMES=40) and it contains a
     destructive command. Fail closed.
  H  HOME REASSIGNED THEN USED (overridable): HOME was assigned from an expansion
     that can be empty or tainted, then a destructive command runs under it.
  V  EMPTY OR TAINTED VARIABLE (overridable): the target derives from an
     unguarded positional parameter, an indirect expansion, or an unknown/empty
     variable that composes a protected path once it is empty; also an
     unresolved command word used with recursive/force flags, `xargs` /
     `parallel` input that cannot be inspected, a RECURSIVE delete of a whole
     target that is a variable the analysed text never assigns (round 7), and an
     inline `python3 -c` / `node -e` / `perl -e` / `ruby -e` that removes a tree
     whose path it computes (a literal protected path there is class P).
  U  UNINSPECTABLE CODE (overridable): code is fed to a shell from a source the
     guard cannot read (a pipe from an unknown producer, an unknown variable).

ESCAPE HATCH: a real single-line shell comment `# guardrails:allow <reason>` at
the TOP level of the command (non-empty reason; text inside quotes, heredoc
bodies, `bash -c`, traps or `$(...)` does not count) downgrades H, V and U to a
warning. Classes P and X have no escape hatch.

HONEST BOUNDARY (§11.4.6): this is a text scan at the tool-call boundary, not a
security boundary. It cannot see a path produced by `eval` of a decoded string,
command-substitution output used as a target, a downloaded script, a binary or a
language runtime deleting through its own API (only inline -c/-e code is read,
never a script FILE an interpreter runs); variable values are tracked in
statement order. A static command classifier cannot be exhaustive. Known limits
(round 7): namerefs, array appends and extglob; scripts written with `echo >` and
run later; environment inherited from the parent (XDG_* and any variable the
text does not set); a Unicode slash look-alike; `/HOME` on a case-sensitive
filesystem; IFS tricks; non-recursive rmdir/unlink; the run-time working
directory of a script that Write/Edit only creates (the payload `cwd` is the
start directory for a Bash call); script files run by `source` or an interpreter.
The runtime layer `scripts/lib/safe_rm.sh` is the second layer.

DECISIONS (round 7): `rm -rf /tmp/*` is class P and no marker allows it (use
`/tmp/build-*` or a `mktemp -d` value); `rm -rf ~/.cache/*` is class V (a reasoned
`# guardrails:allow` marker allows it). The former GUARD_R7_UV_OFF survey switch was removed in
review round 1 (finding 11): the anchor has no escape hatch, so the class-V unknown-target rule
has no environment switch; the paired mutation test turns it off by editing a copy of this file.
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
import time

MAX_DEPTH = 5
MAX_FRAMES = 40  # total nesting of substitutions, function calls and strings

# Work budget (a backstop against adversarial input; every known quadratic path is fixed at its
# cause). The PRIMARY limits are deterministic — characters of text handed to analyse() and function
# expansions — so the verdict does not depend on host speed. A wall clock (DEFAULT_CLOCK_SECS) is only
# a last-resort net. Whichever runs out first, the WHOLE input is re-checked by fallback_scan(): class P
# stays P, an uncertain recursive/forced delete or a hidden command word used with one is class X
# (not overridable), any other uncertain delete is class U, which only a marker on the first line (after
# a shebang) can allow. GUARD_TIME_BUDGET (seconds) overrides the clock for the tests; operators MUST NOT
# set it in the live hook environment.
MAX_FUNC_EXPANSIONS = 3000
MAX_WORK_CHARS = 4_000_000  # cumulative text handed to analyse()
DEFAULT_CLOCK_SECS = 25.0
_budget = {"deadline": None, "funcs": 0, "chars": 0, "hit": False, "secs": DEFAULT_CLOCK_SECS}


def _start_budget():
    try:
        secs = float(os.environ.get("GUARD_TIME_BUDGET", str(DEFAULT_CLOCK_SECS)))
    except ValueError:
        secs = DEFAULT_CLOCK_SECS
    if not (0 <= secs <= DEFAULT_CLOCK_SECS):  # can only shorten the clock; NaN/inf/negative -> default
        secs = DEFAULT_CLOCK_SECS
    _budget["secs"] = secs
    _budget["deadline"] = time.monotonic() + secs
    _budget["funcs"] = 0
    _budget["chars"] = 0
    _budget["hit"] = False


def _over_budget():
    d = _budget["deadline"]
    return (d is not None and time.monotonic() > d) or _budget["chars"] > MAX_WORK_CHARS

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
            "flock", "chroot", "busybox", "coproc", "watch", "systemd-run",
            "chrt", "taskset", "runuser", "unshare", "nsenter", "setpriv", "prlimit", "numactl",
            "gosu", "su-exec", "fakeroot", "eatmydata"}
# ---- the option grammar of every wrapper (fix round 5: ONE getopt-faithful parser, review round 4 finding I-1) ----
# One row per wrapper, read by `take_wrapper_options` (the only place wrapper options are decoded; `strip_wrappers`
# and `_cwd_effect` both consume its events). Keys:
#   flags   short letters that take NO argument
#   args    short letters that take a REQUIRED argument: the rest of the cluster is that argument (`-uroot`,
#           `-Eu root` = flag E, option u with argument root); with nothing left in the cluster the next word is it
#   opt     short letters with an OPTIONAL argument, which getopt only accepts ATTACHED (`nsenter -mFILE`): the rest
#           of the cluster is the argument, the next word never is
#   longs   long option -> takes an argument. getopt_long accepts any UNIQUE PREFIX (`--chd`), and an argument either
#           after `=` or as the next word; a long option with an optional argument takes it only after `=`
#   digits  `-5` style options (nice)
#   strict  the optstring is complete: an unknown letter or long option is not skipped silently, it leaves the
#           working directory LOST (the command still runs, but the guard cannot know where)
WRAP_SPEC = {
    "sudo": {"flags": "AbBEeHiKklnPSsVv", "args": "uDgCprtUThR", "strict": True,
             "longs": {"askpass": 0, "background": 0, "bell": 0, "close-from": 1, "chdir": 1, "preserve-env": 0,
                       "edit": 0, "group": 1, "set-home": 0, "help": 0, "host": 1, "login": 0,
                       "remove-timestamp": 0, "reset-timestamp": 0, "list": 0, "non-interactive": 0,
                       "preserve-groups": 0, "prompt": 1, "chroot": 1, "role": 1, "stdin": 0, "shell": 0,
                       "type": 1, "other-user": 1, "update": 0, "user": 1, "version": 0, "validate": 0,
                       "command-timeout": 1, "login-class": 1, "auth-type": 1}},
    "env": {"flags": "iv0hV", "args": "uCSaf", "strict": True,
            "longs": {"ignore-environment": 0, "null": 0, "unset": 1, "chdir": 1, "split-string": 1, "debug": 0,
                      "argv0": 1, "file": 1, "block-signal": 0, "default-signal": 0, "ignore-signal": 0,
                      "list-signal-handling": 0, "help": 0, "version": 0}},
    "doas": {"flags": "Lns", "args": "uC", "strict": True, "longs": {}},
    "timeout": {"flags": "fpv", "args": "sk", "strict": True,
                "longs": {"foreground": 0, "preserve-status": 0, "verbose": 0, "signal": 1, "kill-after": 1,
                          "help": 0, "version": 0}},
    "nice": {"flags": "", "args": "n", "digits": True, "strict": True,
             "longs": {"adjustment": 1, "help": 0, "version": 0}},
    "ionice": {"flags": "thV", "args": "cnpPu", "strict": True,
               "longs": {"class": 1, "classdata": 1, "pid": 1, "pgid": 1, "uid": 1, "ignore": 0, "help": 0,
                         "version": 0}},
    "stdbuf": {"flags": "", "args": "ioe", "strict": True,
               "longs": {"input": 1, "output": 1, "error": 1, "help": 0, "version": 0}},
    "setsid": {"flags": "cfwVh", "args": "", "strict": True,
               "longs": {"ctty": 0, "fork": 0, "wait": 0, "help": 0, "version": 0}},
    "nohup": {"flags": "", "args": "", "strict": True, "longs": {"help": 0, "version": 0}},
    "exec": {"flags": "cl", "args": "a", "longs": {}},
    "command": {"flags": "pvV", "args": "", "longs": {}},
    "builtin": {"flags": "", "args": "", "longs": {}},
    "time": {"flags": "apvVqh", "args": "of",
             "longs": {"output": 1, "format": 1, "append": 0, "portability": 0, "verbose": 0, "quiet": 0,
                       "help": 0, "version": 0}},
    "run0": {"flags": "tEn", "args": "ugDp",
             "longs": {"user": 1, "group": 1, "chdir": 1, "property": 1, "unit": 1, "description": 1, "slice": 1,
                       "setenv": 1, "nice": 1, "background": 1, "machine": 1}},
    "pkexec": {"flags": "", "args": "", "longs": {"user": 1, "disable-internal-agent": 0, "keep-cwd": 0,
                                                  "help": 0, "version": 0}},
    "chrt": {"flags": "", "args": "TPD",
             "longs": {"sched-runtime": 1, "sched-period": 1, "sched-deadline": 1}},
    "runuser": {"flags": "lmp", "args": "ugGswc",
                "longs": {"user": 1, "group": 1, "supp-group": 1, "shell": 1, "whitelist-environment": 1,
                          "command": 1, "login": 0, "preserve-environment": 0, "pty": 0}},
    "flock": {"flags": "nxsuoF", "args": "wEc",
              "longs": {"timeout": 1, "wait": 1, "conflict-exit-code": 1, "command": 1, "shared": 0,
                        "exclusive": 0, "unlock": 0, "nonblock": 0, "nb": 0, "close": 0, "no-fork": 0,
                        "verbose": 0}},
    "chroot": {"flags": "", "args": "", "longs": {"userspec": 1, "groups": 1, "skip-chdir": 0}},
    "watch": {"flags": "dtbecxgp", "args": "n", "longs": {"interval": 1}},
    "systemd-run": {"flags": "qdtPSGr", "args": "puEMHC",
                    "longs": {"property": 1, "unit": 1, "uid": 1, "gid": 1, "setenv": 1, "description": 1,
                              "slice": 1, "working-directory": 1, "machine": 1, "host": 1, "on-active": 1,
                              "on-calendar": 1, "service-type": 1, "same-dir": 0, "wait": 0, "pty": 0,
                              "pipe": 0, "quiet": 0, "collect": 0, "scope": 0, "user": 0, "system": 0}},
    "unshare": {"flags": "rfc", "args": "SGRw", "opt": "muinpUCT",
                "longs": {"setuid": 1, "setgid": 1, "root": 1, "wd": 1, "propagation": 1, "map-user": 1,
                          "map-group": 1, "map-users": 1, "map-groups": 1, "monotonic": 1, "boottime": 1}},
    "nsenter": {"flags": "rFZac", "args": "tSG", "opt": "muinpCTUw",
                "longs": {"target": 1, "setuid": 1, "setgid": 1, "wd": 0}},
    "setpriv": {"flags": "", "args": "",
                "longs": {"reuid": 1, "regid": 1, "ruid": 1, "euid": 1, "rgid": 1, "egid": 1, "groups": 1,
                          "inh-caps": 1, "ambient-caps": 1, "bounding-set": 1, "securebits": 1, "pdeathsig": 1,
                          "selinux-label": 1, "apparmor-profile": 1, "landlock-access": 1, "landlock-rule": 1}},
    "prlimit": {"flags": "", "args": "p", "longs": {"pid": 1}},
    "numactl": {"flags": "lsHhV", "args": "NCmip",
                "longs": {"cpunodebind": 1, "physcpubind": 1, "membind": 1, "interleave": 1, "preferred": 1}},
    "taskset": {"flags": "ap", "args": "", "opt": "c", "longs": {"cpu-list": 0, "all-tasks": 0, "pid": 0}},
    "fakeroot": {"flags": "uhv", "args": "lfisb", "longs": {"lib": 1, "faked": 1, "unknown-is-real": 0}},
    "gosu": {"flags": "", "args": "", "longs": {}},
    "su-exec": {"flags": "", "args": "", "longs": {}},
    "eatmydata": {"flags": "", "args": "", "longs": {}},
    "busybox": {"flags": "", "args": "", "longs": {}},
    "coproc": {"flags": "", "args": "", "longs": {}},
}
WRAP_POS = {"flock": 1, "chroot": 1, "chrt": 1, "taskset": 1, "gosu": 1, "su-exec": 1}
# a shell-string runner (`-c STR`): the shells proper, plus `su`/`sg`/`script`, whose `-c`/`--command`/
# `--session-command` carries a command line exactly as `sh -c` does
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "su", "ash", "hush", "fish", "csh", "tcsh", "mksh", "rbash",
          "sg", "script"}
# the runners whose `-c` argument may be attached (`-cSTR`) and which spell it `--command[=STR]`
_C_ATTACHED = {"su", "runuser", "flock", "sg", "script"}
_LONG_C = {"--command", "--session-command"}
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
    r"|\bmv\b\s+(?:-\S+\s+)*[/~$]"
    r"|\bdd\b[^\n]*\bof=/dev/"
    r"|\bgit\b[^\n]*\bclean\b[^\n]*(?:\s-\w*f|--force)")
HEREDOC_RE = re.compile(r"<<(-?)[ \t]*(?:'([^']*)'|\"([^\"]*)\"|\\?([^\s;&|<>()'\"\\]+))")

XARGS_ITEM = "\0T\0"    # an item xargs reads from input the guard cannot see
HOMEVAR = "\0HOME\0"   # symbolic $HOME
TV = "\0T\0"           # tainted: derives from an unguarded positional parameter
UV = "\0U\0"           # unknown / possibly empty
SV = "\0S\0"           # guarded or sandbox-derived: cannot be judged
CV = "\0C\0"           # output of a command substitution the guard cannot compute (may be empty)
MARKERS = (TV, UV, SV, CV)
STRENGTH = (TV, CV, UV, SV)  # strongest first: the marker an operation on a mixed value inherits
_PH_RE = re.compile("\0E([0-9]+)\0")  # a live $(...) / backtick, kept as ONE word by words_of()
_SUBST = []                            # placeholder id -> body of that substitution
BLOCKDEV_RE = re.compile(r"/dev/(?:sd[a-z]+\d*|nvme\d+n\d+(?:p\d+)?|hd[a-z]+\d*|vd[a-z]+\d*|xvd[a-z]+\d*"
                         r"|mmcblk\d+(?:p\d+)?|md\d+|dm-\d+|loop\d+|mapper/.+|disk/.+)")
# command names a command word that is a glob or a brace expansion may resolve to, destructive first
DCMDS = ("rm", "shred", "rmdir", "unlink", "find", "rsync", "mv", "chmod", "chown", "chgrp", "dd", "git",
         "xargs", "parallel", "eval", "bash", "sh", "zsh", "dash", "ksh")


ARRAY_TAG = "\x03"
ARRAY_SEP = "\x01"


def strongest(s):
    for mk in STRENGTH:
        if mk in s:
            return mk
    return None


def real_home():
    return os.path.realpath(os.environ.get("HOME", "") or "/nonexistent")


def home_ancestors(rh=None):
    """Every proper ancestor of the home directory, below `/` (`/` has its own rule): a delete of any of
    them deletes the home directory too. Both the resolved home and the home as written in $HOME count,
    so a symlinked home is covered on both sides. Matches scripts/lib/safe_rm.sh (review round 5 I1-r5:
    the guard protected only /home/<user> and /Users/<user> shapes, so /data/users stayed open)."""
    out = set()
    raw = os.environ.get("HOME", "")
    for h in {rh or real_home(), posixpath.normpath(raw) if raw.startswith("/") else ""}:
        d = posixpath.dirname(h) if h else ""
        while d not in ("", "/"):
            out.add(d)
            d = posixpath.dirname(d)
    return out


def protected_paths(rh):
    prot = set(SYSTEM_DIRS) | {rh} | home_ancestors(rh)
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


def ansic_end(text, i):
    """Index just past the closing quote of the ANSI-C string `$'...'` that opens at text[i]
    (backslash escapes are honoured, so \\' does not end it). Unterminated: end of text."""
    j, n = i + 2, len(text)
    while j < n:
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == "'":
            return j + 1
        j += 1
    return n


def arith_span(text, i):
    """text[i:i+3] == '$(('. Returns (end, kind): kind 'arith' when the span closes with two
    adjacent ')' that pair with the two opening ones (end is just past them), 'cmdsub' when it
    does not (bash then reads `$(` + a subshell, e.g. `$((cmd) )` or `$((cmd); other)`), and
    'open' when it never closes (end is len(text)). Quotes and ANSI-C strings are honoured."""
    n, j, depth = len(text), i + 3, 2
    sq = dq = False
    last_close = (-1, 0)  # (index of the last real ')', depth after it)
    while j < n:
        c = text[j]
        if sq:
            if c == "'":
                sq = False
        elif c == "\\":
            j += 1
        elif c == "$" and not dq and text.startswith("$'", j):
            j = ansic_end(text, j)
            continue
        elif c == "'" and not dq:
            sq = True
        elif c == '"':
            dq = not dq
        elif not dq and c == "(":
            depth += 1
        elif not dq and c == ")":
            depth -= 1
            last_close_prev = last_close
            last_close = (j, depth)
            if depth == 0:
                if last_close_prev == (j - 1, 1):
                    return j + 1, "arith"
                return j + 1, "cmdsub"
        j += 1
    return n, "open"


def param_span(text, i):
    """End index (exclusive) of the `${...}` that starts at text[i], or -1 when it does not close.

    Inside ${...} bash gives each quote its own context, also when the whole expansion sits in
    double quotes: `"${v//"'"/"''"}"` is ONE word (checked against bash 5.3). Single-quoted and
    double-quoted runs therefore shield `}` from the brace count, and a nested ${...} is matched
    recursively. The caller copies the span verbatim only when it holds no command substitution,
    so a delete inside `${u:-$(...)}` is still analysed by the normal path."""
    n = len(text)
    j = i + 2
    while j < n:
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == "'":
            k = text.find("'", j + 1)
            if k == -1:
                return -1
            j = k + 1
            continue
        if c == '"':
            j += 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 2
                    continue
                if text.startswith("${", j):
                    k = param_span(text, j)
                    if k == -1:
                        return -1
                    j = k
                    continue
                j += 1
            if j >= n:
                return -1
            j += 1
            continue
        if text.startswith("${", j):
            k = param_span(text, j)
            if k == -1:
                return -1
            j = k
            continue
        if c == "}":
            return j + 1
        j += 1
    return -1


def plain_param_span(text, i):
    """param_span, but only for a span that holds no `$(`, backtick, `<(` or `>(`; else -1."""
    j = param_span(text, i)
    if j == -1:
        return -1
    body = text[i:j]
    if "$(" in body or "`" in body or "<(" in body or ">(" in body:
        return -1
    return j


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
        if not sq and not dq and c == "$" and text.startswith("$'", k):
            k = ansic_end(text, k)
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
            if quote == '"' and text.startswith("${", i):
                j = plain_param_span(text, i)
                if j != -1:
                    cur.append(text[i:j])
                    i = j
                    continue
            if quote == '"' and c == "$" and text.startswith("$(", i):
                # a substitution inside double quotes is its own quoting context: `"$(echo "it's")"`
                # is valid bash. Copy the whole span verbatim (its body is analysed separately).
                if text.startswith("$((", i):
                    j, kind = arith_span(text, i)
                    if kind == "arith":
                        cur.append(text[i:j])
                        i = j
                        continue
                    if kind == "open":
                        problems.append("unterminated $(( arithmetic")
                        cur.append(text[i:])
                        i = n
                        continue
                j = matching_paren(text, i + 2)
                if j == -1:
                    problems.append("unterminated $( / <( / >(")
                    cur.append(text[i:])
                    i = n
                    continue
                cur.append(text[i:j])
                i = j
                continue
            if quote == '"' and c == "`":
                j = i + 1
                while j < n and text[j] != "`":
                    j += 2 if text[j] == "\\" else 1
                if j >= n:
                    problems.append("unterminated backtick")
                    cur.append(text[i:])
                    i = n
                    continue
                cur.append(text[i:j + 1])
                i = j + 1
                continue
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
        if text.startswith("${", i):
            j = plain_param_span(text, i)
            if j != -1:
                cur.append(text[i:j])
                i = j
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
            j, kind = arith_span(text, i)
            if kind != "cmdsub":
                if kind == "open":
                    problems.append("unterminated $(( arithmetic")
                cur.append(text[i:j])
                i = j
                continue
            # `$((cmd) )`: not arithmetic, bash reads `$(` followed by a subshell: fall through
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


def _bt_unescape(body):
    """Inside backticks bash removes the backslash before `, $ and \\ before parsing the body, so
    an escaped backtick is a NESTED substitution, not the end of this one."""
    return re.sub(r"\\([`$\\])", r"\1", body)


def balanced_subst(text):
    return list(_balanced_subst_cached(text))


ARITH_SCAN_LIMIT = 2_000_000  # characters arith_span may scan in one run; past it a `$((` is
_ARITH_WORK = [0]  # read as `$(` + subshell, so more text is analysed as code, never less


@functools.lru_cache(maxsize=512)
def _balanced_subst_cached(text):
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
        if not dq and c == "$" and text.startswith("$'", i):
            i = ansic_end(text, i)
            continue
        if text.startswith("$((", i) and _ARITH_WORK[0] < ARITH_SCAN_LIMIT:
            e, kind = arith_span(text, i)
            _ARITH_WORK[0] += e - i  # bounded per run: 200 KB of '$((' is otherwise quadratic
            if kind != "cmdsub":
                # arithmetic is NOT code: `a * b / 2` names no command and no path. Only the command
                # substitutions inside it run, so scanning continues inside the span, where the
                # `$(` and backtick branches below pick them up (a nested `$((` is handled again).
                i += 3
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
            j = i + 1
            while j < n and text[j] != "`":
                j += 2 if text[j] == "\\" else 1
            if j >= n:
                out.append(_bt_unescape(text[i + 1:]))
                break
            out.append(_bt_unescape(text[i + 1:j]))
            i = j + 1
            continue
        i += 1
    return out


_FUNC_DEF_RE = re.compile(
    r"(?:^|[\s;&|(){])(?:function\s+)?([A-Za-z_][\w:.-]*)\s*\(\)\s*\{"
    r"|(?:^|[\s;&|(){])function\s+([A-Za-z_][\w:.-]*)\s*\{")


def find_functions(text):
    out = {}
    qs = _QuoteScan(text)  # one forward scan for all matches: linear, not O(n*m)
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
            elif c == "\\":
                i += 2  # an escaped quote or brace is literal
                continue
            elif c == "#" and (i == start or text[i - 1] in " \t\n;"):
                j = text.find("\n", i)  # a comment: an apostrophe in it opens no string
                i = n if j < 0 else j
                continue
            elif c in "'\"":
                q = c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            i += 1
        body = text[start:i - 1] if depth == 0 else text[start:]
        if qs.inside(m.start(0) + (1 if text[m.start(0)] in " \t\n;&|(){" else 0)) and segment(body)[3]:
            # a "definition" spelled inside quoted text (a sed expression, a
            # mutation spec) whose body does not even parse is data, not code:
            # recording it would report valid bash as unparseable (class X,
            # review round 4 I1-r4). A quoted body that DOES parse is kept,
            # so eval 'f(){ rm -rf ~; }'; f stays resolved.
            continue
        out[name] = body
    return out


class _QuoteScan:
    """Quote state of ``text`` at increasing positions, from ONE forward scan
    (comments and escapes honoured). Queries must not go backwards; a query
    at a smaller position restarts the scan, so it is still correct."""

    def __init__(self, text):
        self.text, self.i, self.q, self.comment_end = text, 0, None, -1

    def inside(self, pos):
        if pos < self.i:
            self.i, self.q, self.comment_end = 0, None, -1
        text = self.text
        while self.i < pos:
            if self.comment_end > self.i:
                if self.comment_end >= pos:
                    return True  # pos lies inside a comment
                self.i = self.comment_end
                continue
            c, i, q = text[self.i], self.i, self.q
            if q == "'":
                if c == "'":
                    self.q = None
            elif q == '"':
                if c == "\\":
                    self.i += 2
                    continue
                if c == '"':
                    self.q = None
            elif c == "\\":
                self.i += 2
                continue
            elif c == "#" and (i == 0 or text[i - 1] in " \t\n;"):
                j = text.find("\n", i)
                self.comment_end = len(text) if j < 0 else j
                if self.comment_end >= pos:
                    return True
                continue
            elif c in "'\"":
                self.q = c
            self.i += 1
        return self.q is not None


def _in_quotes(text, pos):
    """True when text[pos] lies inside a single- or double-quoted string."""
    return _QuoteScan(text).inside(pos)


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
    return re.sub(r"\$'(?:[^'\\]|\\.)*'|'[^']*'|\"(?:[^\"\\]|\\.)*\"", "", s)


def words_of(seg):
    return list(_words_of_cached(seg)[0])


def split_set(seg):
    """Words of `seg` that contain an UNQUOTED variable or command expansion: bash word-splits their
    value, so `D="/tmp/x /home"; rm -rf $D` deletes two paths. (Quote information is lost by shlex,
    so a word that is unquoted ANYWHERE in the segment counts: fewer missed splits, never fewer checks.)"""
    return _words_of_cached(seg)[1]


_UNQ_MARK = "\x05"


def mark_unquoted(s):
    """Insert a sentinel before every `$` / command-substitution placeholder that sits outside quotes."""
    if "$" not in s and "\0E" not in s:
        return s
    out, i, n, sq, dq = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if c == "\\" and not sq and i + 1 < n:
            out.append(s[i:i + 2])
            i += 2
            continue
        if sq:
            if c == "'":
                sq = False
        elif dq:
            if c == '"':
                dq = False
        elif c == "'":
            sq = True
        elif c == '"':
            dq = True
        elif c == "$" and i + 1 < n and (s[i + 1].isalnum() or s[i + 1] in "_{@*"):
            out.append(_UNQ_MARK)
        elif c == "\0" and s.startswith("\0E", i):
            out.append(_UNQ_MARK)
        out.append(c)
        i += 1
    return "".join(out)


_SUBST_IDS = {}


def _ph(body):
    """A placeholder word for a live command substitution: it survives word splitting as part of ONE
    word, and expand() later replaces it with what the guard can compute about the output."""
    k = _SUBST_IDS.get(body)
    if k is None:
        k = _SUBST_IDS[body] = len(_SUBST)
        _SUBST.append(body)
    return "\0E%d\0" % k


def subst_placeholders(s):
    """Replace every live `$(...)` and backtick substitution with a placeholder, and a locale string
    `$"..."` with a plain double-quoted one. Single-quoted and ANSI-C text is literal and kept.
    Linear: an unterminated construct stops the pass (the rest is kept verbatim)."""
    if "$" not in s and "`" not in s:
        return s
    out, i, n, dq = [], 0, len(s), False
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            out.append(s[i:i + 2])
            i += 2
            continue
        if not dq and c == "'":
            j = s.find("'", i + 1)
            if j < 0:
                out.append(s[i:])
                break
            out.append(s[i:j + 1])
            i = j + 1
            continue
        if not dq and s.startswith("$'", i):
            j = ansic_end(s, i)
            out.append(s[i:j])
            i = j
            continue
        if c == '"':
            dq = not dq
            out.append(c)
            i += 1
            continue
        if not dq and s.startswith('$"', i):
            out.append('"')
            dq = True
            i += 2
            continue
        if s.startswith("$((", i):
            end, kind = arith_span(s, i)
            if kind == "arith":
                # an arithmetic expansion is ONE word whose value is a number: its operators and
                # operands (`a * b / 2`) are never command words or paths. Command substitutions
                # inside it are analysed separately (balanced_subst).
                out.append("0")
                i = end
                continue
            if kind == "open":
                out.append(s[i:])
                break
        if s.startswith("$(", i):
            j = matching_paren(s, i + 2)
            if j < 0:
                out.append(s[i:])
                break
            out.append(_ph(s[i + 2:j - 1]))
            i = j
            continue
        if c == "`":
            j = i + 1
            while j < n and s[j] != "`":
                j += 2 if s[j] == "\\" else 1
            if j >= n:
                out.append(s[i:])
                break
            out.append(_ph(_bt_unescape(s[i + 1:j])))
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


_LONG_RUN = 512
_LONG_RUN_RE = re.compile(r"[^\s'\"\\\x02\x03]{%d,}" % _LONG_RUN)
_LONG_PH_RE = re.compile(r"\x02(\d+)\x03")


@functools.lru_cache(maxsize=512)
def _words_of_cached(seg):
    s = clean_segment(seg)
    s = subst_placeholders(s)
    s = _IFS_RE.sub(" ", s)
    s = decode_ansic(s)
    s = arrays_flat(s)
    s = mark_unquoted(s.replace(_UNQ_MARK, "_"))
    # shlex builds each token one character at a time (quadratic on a long word: a 4 MB word took
    # minutes, so the hook would time out and the call would go through uninspected). A long run of
    # ordinary word characters is swapped for a short placeholder and restored afterwards; \x02 and
    # \x03 are reserved for the placeholder, so any in the input are neutralised first.
    longs = []
    if len(s) > _LONG_RUN:
        s = s.replace("\x02", "_").replace("\x03", "_")

        def _keep(m):
            longs.append(m.group(0))
            return "\x02%d\x03" % (len(longs) - 1)
        s = _LONG_RUN_RE.sub(_keep, s)
    try:
        raw = shlex.split(s, posix=True, comments=False)
    except ValueError:
        raw = s.split()
    if longs:
        raw = [_LONG_PH_RE.sub(lambda m: longs[int(m.group(1))], x) if "\x02" in x else x for x in raw]
    out, skip, spl = [], False, set()
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
                out.append(head.replace(_UNQ_MARK, ""))
            continue
        if _UNQ_MARK in x:
            spl.add(x.replace(_UNQ_MARK, ""))
            x = x.replace(_UNQ_MARK, "")
        out.append(x)
    return tuple(out), frozenset(spl)


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


def shnorm(words):
    """Canonical spelling of the shell-string option of `su`/`runuser`/`flock`/`sg`/`script`/shells: `--command STR`,
    `--command=STR`, `--session-command[=STR]` and (for the runners that take it attached) `-cSTR` all become
    the separate pair `-c STR`, so one scan finds the string whatever spelling the caller used (F3: the option
    SPELLING is the class; each spelling missed in review round 2 was one more member of it)."""
    if not words:
        return words
    base = os.path.basename(words[0])
    out = [words[0]]
    for x in words[1:]:
        if x == "--":
            out.append(x); continue
        m = re.match(r"^(--command|--session-command)=(.*)$", x, re.S)
        if m:
            out += ["-c", m.group(2)]
        elif x in _LONG_C:
            out.append("-c")
        elif base in _C_ATTACHED and len(x) > 2 and x.startswith("-c") and not x.startswith("--"):
            out += ["-c", x[2:]]
        elif base in _C_ATTACHED and re.match(r"^-[A-Za-z]+c.+$", x, re.S) and not x.startswith("--"):
            # a cluster of flag letters ending in `c` with the string attached (`script -qcSTR`)
            m = re.match(r"^(-[A-Za-z]+)c(.+)$", x, re.S)
            out += [m.group(1), "-c", m.group(2)]
        else:
            out.append(x)
    return out


# ---- the working directory a wrapper runs its command in (fix round 4) --------------------------------------
# The effective cwd is threaded as STATE: every wrapper is assumed to KEEP the caller's cwd (nice, timeout, nohup,
# time, stdbuf, setsid, flock, ...); the options below move it to a named directory, and the wrappers/options in
# `_CWD_LOST_WRAPPERS` and `_cwd_effect` move it somewhere the guard cannot name. Anything that moves it to an
# unnameable place leaves the cwd LOST (see lost_cwd()), and a RELATIVE destructive target that could name a
# protected path from there fails closed. This replaces the earlier per-spelling table rows: the question asked
# is "where does the command run", not "which spelling did the caller use".
_CHDIR_OPTS = {"env": ("-C", "--chdir"), "sudo": ("-D", "--chdir"), "run0": ("-D", "--chdir"),
               "systemd-run": (None, "--working-directory"), "unshare": ("-w", "--wd")}
_CWD_LOST_WRAPPERS = {"pkexec", "nsenter", "chroot"}       # run in another user's home / namespace / root


_EMPTY_SPEC = {"flags": "", "args": "", "longs": {}}


def _resolve_long(spec, name):
    """getopt_long resolves a long option by any UNIQUE PREFIX (`--chd` is `--chdir`); an exact name always wins.
    None when the name is unknown or ambiguous (getopt would refuse the command line)."""
    longs = spec["longs"]
    if name in longs:
        return name
    hit = [k for k in longs if k.startswith(name)] if name else []
    return hit[0] if len(hit) == 1 else None


def take_wrapper_options(base, w):
    """The ONE decoder of a wrapper's leading options (fix round 5, review round 4 finding I-1). Reads `w` the way
    getopt does for wrapper `base` (table: WRAP_SPEC) and returns (events, rest, dashdash): `events` is a list of
    (option, argument-or-None) with the option spelled canonically (`-u`, `--chdir`), `rest` is what follows the
    options, and `dashdash` says an explicit `--` ended them. A short-option CLUSTER is read letter by letter: a
    flag letter is a flag, a letter that takes an argument takes the REST of the cluster (`-uroot`, `-Eroot`) or,
    when nothing is left, the next word (`-Eu root`), and the cluster ends there. A lone `-` is `-i` for env. An
    unknown letter or long option of a wrapper whose optstring is complete (`strict`) becomes the event
    ("?", token): the caller cannot know what it does, so the working directory is LOST, never assumed kept.
    Both `strip_wrappers` (what runs) and `_cwd_effect` (where it runs) consume these events, so the two can never
    disagree about where one option ends and the next begins."""
    spec = WRAP_SPEC.get(base, _EMPTY_SPEC)
    strict = bool(spec.get("strict"))
    ev = []
    i, n = 0, len(w)
    while i < n:
        t = w[i]
        if t == "--":
            return ev, w[i + 1:], True
        if t == "-" and base == "env":
            ev.append(("-i", None)); i += 1
            continue
        if len(t) < 2 or t[0] != "-":
            break
        i += 1
        if t.startswith("--"):
            name, eq, val = t[2:].partition("=")
            full = _resolve_long(spec, name)
            if full is None:
                if strict:
                    ev.append(("?", t))
                else:
                    ev.append((t.split("=", 1)[0], val if eq else None))
                continue
            if eq:
                ev.append(("--" + full, val))
            elif spec["longs"][full] and i < n:
                ev.append(("--" + full, w[i])); i += 1
            else:
                ev.append(("--" + full, None))
            continue
        j = 1
        while j < len(t):
            ch = t[j]
            if ch in spec["args"]:
                rest = t[j + 1:]
                if rest:
                    ev.append(("-" + ch, rest))
                elif i < n:
                    ev.append(("-" + ch, w[i])); i += 1
                else:
                    ev.append(("-" + ch, None))
                break
            if ch in spec.get("opt", ""):
                rest = t[j + 1:]
                ev.append(("-" + ch, rest or None))
                break
            if ch in spec["flags"] or (spec.get("digits") and ch.isdigit()):
                ev.append(("-" + ch, None)); j += 1
                continue
            ev.append(("?" if strict else "-" + ch, "-" + ch if strict else None)); j += 1
    return ev, w[i:], False


def _cwd_effect(base, o, arg):
    """The cwd effect of option event (`o`, `arg`) of wrapper `base`, as produced by take_wrapper_options:
    ("set", RAW_PATH), ("lost",), ("keep",) or None when the option has no effect on the working directory."""
    if o == "?":
        return ("lost",)
    ent = _CHDIR_OPTS.get(base)
    if ent and o in ent:
        return ("set", arg) if arg is not None else ("lost",)
    if base in ("run0", "systemd-run") and o in ("-p", "--property") and arg and arg.startswith("WorkingDirectory="):
        return ("set", arg.split("=", 1)[1])
    if base == "systemd-run" and o in ("-d", "--same-dir"):
        return ("keep",)
    if base == "sudo" and o in ("-i", "--login", "-R", "--chroot"):
        return ("lost",)
    if base == "runuser" and o in ("-l", "--login"):
        return ("lost",)
    if base == "unshare" and o in ("-R", "--root"):
        return ("lost",)
    return None


_DESTRUCTIVE_HEADS = {"rm", "shred", "rmdir", "unlink", "find", "rsync", "chmod", "chown", "chgrp", "mv", "dd", "git"}


def strip_wrappers(words, collect=None, cwd_eff=None):
    """Words with the wrapper commands and leading `NAME=value` assignments removed. When `collect` is a
    list, the dropped assignments (and a marker `-i` for `env -i`) are appended in order: they are the
    environment the wrapped command runs with."""
    w = list(words)
    unknown_opt = False   # a wrapper option the table does not know: its argument may be the next word
    while w:
        head = w[0]
        if ASSIGN_RE.match(head):
            if collect is not None:
                collect.append(head)
            w.pop(0)
            continue
        base = os.path.basename(head)
        if base not in WRAPPERS:
            break
        w.pop(0)
        if cwd_eff is not None and base in _CWD_LOST_WRAPPERS:
            cwd_eff.append(("lost",))
        saw_dir = False
        if base in ("runuser", "flock"):
            w = shnorm([base] + w)[1:]
            if cwd_eff is not None and base == "runuser" and any(
                    x in ("-l", "--login", "-") for x in (w[:w.index("--")] if "--" in w else w)):
                cwd_eff.append(("lost",))
            hit = _shell_string_of(base, w)
            if hit is not None:
                return ["sh", "-c", hit]
        attached_list = False
        while True:
            events, w, dashdash = take_wrapper_options(base, w)
            resplit = False
            for o, a in events:
                if o == "?":
                    unknown_opt = True
                if base == "taskset" and o in ("-c", "--cpu-list") and a:
                    attached_list = True
                if base == "env" and o in ("-i", "--ignore-environment") and collect is not None:
                    collect.append("-i")
                if base == "env" and o in ("-S", "--split-string"):
                    if a is not None:
                        try:
                            parts = shlex.split(a)
                        except ValueError:
                            parts = a.split()
                        w = parts + w
                        resplit = True
                    continue
                if cwd_eff is not None:
                    ce = _cwd_effect(base, o, a)
                    if ce:
                        saw_dir = saw_dir or ce[0] in ("set", "keep")
                        if ce[0] != "keep":
                            cwd_eff.append(ce)
            if not resplit or dashdash:
                break
        if cwd_eff is not None and base in ("run0", "systemd-run") and not saw_dir:
            cwd_eff.append(("lost",))    # runs in the service manager's directory, not the caller's
        if base == "timeout" and w and re.fullmatch(r"\d+(?:\.\d+)?[smhd]?", w[0]):
            w.pop(0)
        for _ in range(0 if attached_list else WRAP_POS.get(base, 0)):
            if w:
                w.pop(0)
    if unknown_opt:
        # An unknown option may take an argument (`env -P DIR cmd` on BSD, `sudo -a TYPE cmd`): the next word is
        # then NOT the command. Fail closed: the first later word that is a destructive command is the command
        # (a false positive for `env -P x echo rm`-style text, which is accepted: it needs an unknown option).
        for k, x in enumerate(w):
            if os.path.basename(x) in _DESTRUCTIVE_HEADS:
                return w[k:]
    return w


def _shell_string_of(base, w):
    """The `-c STR` command line of a normalised `flock`/`runuser` argument list, or None. `runuser -u USER cmd`
    wraps a command (no string); `runuser [-l] USER -c STR` and `flock [opts] FILE -c STR` / `flock -c STR FILE`
    run a shell string. The scan stops at `--`, so a `-c` that belongs to the wrapped command is never read."""
    head = []
    for x in w:
        if x == "--":
            break
        head.append(x)
    if base == "runuser" and any(x in ("-u", "--user") or x.startswith("--user=") or
                                 re.fullmatch(r"-u.+", x) for x in head):
        return None
    for k, x in enumerate(head):
        if x == "-c" and k + 1 < len(w):
            return w[k + 1]
    return None


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
        if not dq and c == "$" and text.startswith("$'", i):
            i = ansic_end(text, i)
            out.append("$''"); continue
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


@functools.lru_cache(maxsize=1024)
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


def _ctx_text(ctx):
    """`ctx` is the text seen so far, or the State that owns it (joined only when a guard lookup
    really needs it: joining it eagerly for every child made deep chains quadratic)."""
    return ctx if isinstance(ctx, str) else ctx.ctx


def _ctx_guards(ctx):
    """Guarded names visible in `ctx` (a State keeps them incrementally: re-segmenting the whole
    text seen so far for every assignment made deep scripts quadratic)."""
    g = getattr(ctx, "guards", None)
    return g if g is not None else guarded_vars(_ctx_text(ctx))


def var_value(name, env, ctx):
    if name in env:
        return env[name]
    if name == "HOME":
        return HOMEVAR
    if name == "PWD" and getattr(ctx, "cwd", None):
        return ctx.cwd
    if (name.isdigit() and name != "0") or name in ("@", "*"):
        return SV if name in _ctx_guards(ctx) else TV
    if name in ("0", "#", "?", "$", "!", "-"):
        return SV
    return SV if name in _ctx_guards(ctx) else UV


def unph(s):
    """Put the original `$(...)` text back for every placeholder (for text that is analysed again)."""
    if "\0E" not in s:
        return s
    return _PH_RE.sub(lambda m: "$(" + _SUBST[int(m.group(1))] + ")", s)


def _plain(s):
    """A marker-free value with the symbolic home replaced by the real one (for string operations)."""
    return s.replace(HOMEVAR, real_home())


def _glob_rx(pat):
    rx = fnmatch.translate(pat)
    return rx[:-2] if rx.endswith("\\Z") else rx


def _trim(s, op, pat):
    """${v#p} ${v##p} ${v%p} ${v%%p}: shell pattern removal, smallest or largest match."""
    n = len(s)
    if op == "#":
        rng = (s[i:] for i in range(0, n + 1) if fnmatch.fnmatchcase(s[:i], pat))
    elif op == "##":
        rng = (s[i:] for i in range(n, -1, -1) if fnmatch.fnmatchcase(s[:i], pat))
    elif op == "%":
        rng = (s[:i] for i in range(n, -1, -1) if fnmatch.fnmatchcase(s[i:], pat))
    else:
        rng = (s[:i] for i in range(0, n + 1) if fnmatch.fnmatchcase(s[i:], pat))
    return next(rng, s)


def _case(s, op):
    if op == "^":
        return s[:1].upper() + s[1:]
    if op == "^^":
        return s.upper()
    if op == ",":
        return s[:1].lower() + s[1:]
    if op == ",,":
        return s.lower()
    if op == "~":
        return s[:1].swapcase() + s[1:]
    return s.swapcase()


def _param(inner, env, ctx, lvl):
    """Value of `${inner}`: every operator the guard can compute is computed; one it cannot yields
    the strongest marker of what it was applied to (or CV when the operand itself is known)."""
    if re.fullmatch(r"#(?:[A-Za-z_]\w*(?:\[[^\]]*\])?|[0-9]+|[@*])", inner):
        return "1"                                   # a length is a number, never a path
    if inner.startswith("!"):
        return TV                                    # indirect expansion: any variable's value
    mm = re.match(r"([A-Za-z_]\w*|[0-9]+|[@*#?!$-])(?:\[([^\]]*)\])?(.*)$", inner, re.S)
    if not mm:
        return UV
    name, idx, op = mm.group(1), mm.group(2), mm.group(3)
    base = var_value(name, env, ctx)
    if idx is not None and idx not in ("@", "*"):
        ix = expand(idx, env, ctx, lvl)
        elems = base.split(ARRAY_SEP)
        if base in MARKERS:
            pass
        elif re.fullmatch(r"-?\d+", ix.strip()):
            k = int(ix)
            base = elems[k] if -len(elems) <= k < len(elems) else UV
        # an index the guard cannot compute: any element (each one is checked)
    if op == "":
        return base
    if op[:2] in (":?",) or op[:1] == "?":
        return SV if (base == "" or strongest(base)) else base
    dm = re.match(r"(:?[-=])(.*)$", op, re.S)
    if dm:
        dflt = expand(dm.group(2), env, ctx, lvl)
        if dflt and base in (UV, TV, CV, ""):
            if dm.group(1)[-1] == "=" and re.fullmatch(r"[A-Za-z_]\w*", name) and idx is None \
                    and isinstance(env, dict):
                env[name] = dflt  # `${X:=v}` / `${X=v}` ASSIGNS: later uses of $X see the default
            return dflt
        return base
    if op.startswith(":+") or op.startswith("+"):
        word = op[2:] if op.startswith(":+") else op[1:]
        return UV + expand(word, env, ctx, lvl)
    mk = strongest(base)
    sm = re.fullmatch(r":\s*(-?\d+|\(\s*-\d+\s*\))\s*(?::\s*(-?\d+))?\s*", op)
    if sm:
        if mk:
            return mk
        s = _plain(base)
        off = int(sm.group(1).strip("() "))
        start = max(len(s) + off, 0) if off < 0 else off
        if sm.group(2) is None:
            return s[start:]
        ln = int(sm.group(2))
        return s[start:start + ln] if ln >= 0 else s[start:len(s) + ln]
    tm = re.match(r"(##|#|%%|%)(.*)$", op, re.S)
    if tm:
        pat = expand(tm.group(2), env, ctx, lvl)
        if mk or strongest(pat):
            return mk or CV
        return _trim(_plain(base)[:4096], tm.group(1), pat)
    if op.startswith("/"):
        mode = op[1] if len(op) > 1 and op[1] in "/#%" else ""
        body = op[1 + len(mode):]
        parts = re.split(r"(?<!\\)/", body, maxsplit=1)
        pat = expand(parts[0], env, ctx, lvl)
        rep = expand(parts[1], env, ctx, lvl) if len(parts) > 1 else ""
        if mk or strongest(pat + rep):
            return mk or strongest(pat + rep)
        if pat == "":
            return _plain(base)
        rx = _glob_rx(pat)
        s = _plain(base)[:4096]
        try:
            if mode == "#":
                return re.sub("^(?:%s)" % rx, lambda m: rep, s, count=1)
            if mode == "%":
                m2 = re.search("(?:%s)$" % rx, s)
                return s[:m2.start()] + rep if m2 else s
            return re.sub(rx, lambda m: rep, s, count=0 if mode == "/" else 1)
        except re.error:
            return CV
    cm = re.fullmatch(r"(\^\^|\^|,,|,|~~|~).*", op, re.S)
    if cm:
        return mk or _case(_plain(base), cm.group(1))
    am = re.fullmatch(r"@([A-Za-z])", op)
    if am:
        if mk:
            return mk
        f = am.group(1)
        s = _plain(base)
        if f == "U":
            return s.upper()
        if f == "u":
            return s[:1].upper() + s[1:]
        if f == "L":
            return s.lower()
        if f == "E":
            try:
                return s.encode("latin-1", "backslashreplace").decode("unicode_escape")
            except Exception:
                return CV
        return CV
    return mk or CV


_ESC1 = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
         "e": "\x1b", "E": "\x1b", "\\": "\\", "'": "'", '"': '"', "?": "?"}


def unescape_sh(t, b_mode=False):
    """Backslash escapes as `echo -e`, `printf` and `%b` read them. Returns (text, stopped_by_\\c)."""
    out, i, n = [], 0, len(t)
    while i < n:
        c = t[i]
        if c != "\\" or i + 1 >= n:
            out.append(c)
            i += 1
            continue
        d = t[i + 1]
        if d == "c":
            return "".join(out), True
        if d in _ESC1:
            out.append(_ESC1[d])
            i += 2
            continue
        if d in "01234567":
            j = i + 2 if d == "0" else i + 1
            digs = ""
            while j < n and len(digs) < 3 and t[j] in "01234567":
                digs += t[j]
                j += 1
            out.append(chr(int(digs or "0", 8) & 0xFF))
            i = j
            continue
        if d in "xuU":
            width = {"x": 2, "u": 4, "U": 8}[d]
            j, digs = i + 2, ""
            while j < n and len(digs) < width and t[j] in "0123456789abcdefABCDEF":
                digs += t[j]
                j += 1
            if digs:
                out.append(chr(int(digs, 16)))
                i = j
                continue
        out.append(c)
        i += 1
    return "".join(out), False


_PRINTF_CONV = re.compile(r"%(%|[a-zA-Z])")


def sh_printf(fmt, args):
    """What `printf FMT ARGS...` prints, or None when the format uses something this does not model
    (width, precision, flags, `%q`, `%(..)T`): the caller then treats the output as unknown."""
    if re.search(r"%[-+ #0'*.\d(]", fmt.replace("%%", "")):
        return None
    pieces, last = [], 0
    for m in _PRINTF_CONV.finditer(fmt):
        pieces.append(("lit", unescape_sh(fmt[last:m.start()])[0]))
        pieces.append(("pct", m.group(1)))
        last = m.end()
    pieces.append(("lit", unescape_sh(fmt[last:])[0]))
    convs = [p for p in pieces if p[0] == "pct" and p[1] != "%"]
    if any(c[1] not in "sbdiuxXoc" for c in convs):
        return None
    out, ai = [], 0
    while True:
        for kind, v in pieces:
            if kind == "lit":
                out.append(v)
            elif v == "%":
                out.append("%")
            else:
                a = args[ai] if ai < len(args) else None
                ai += 1
                if v == "s":
                    out.append(a or "")
                elif v == "b":
                    out.append(unescape_sh(a or "", True)[0])
                elif v == "c":
                    out.append((a or "")[:1])
                else:
                    try:
                        out.append(str(int(a, 0)) if a is not None else "0")
                    except ValueError:
                        out.append("0")
        if not convs or ai >= len(args):
            break
    return "".join(out)


def lit_output(base, args):
    """The text `echo ARGS` / `printf ARGS` writes to stdout, or None when it cannot be computed."""
    if base == "echo":
        k, interp, nl = 0, False, True
        while k < len(args) and re.fullmatch(r"-[neE]+", args[k]):
            for ch in args[k][1:]:
                if ch == "n":
                    nl = False
                elif ch == "e":
                    interp = True
                elif ch == "E":
                    interp = False
            k += 1
        text = " ".join(args[k:])
        if interp:
            text, stop = unescape_sh(text, True)
            if stop:
                return text
        return text + ("\n" if nl else "")
    k = 0
    while k < len(args) and args[k].startswith("-") and args[k] != "--":
        k += 1
    if k < len(args) and args[k] == "--":
        k += 1
    if k >= len(args):
        return ""
    return sh_printf(args[k], args[k + 1:])


def _cmd_output(body, env, ctx, lvl):
    """What `$(body)` prints, when the guard can compute it; otherwise CV (anything, maybe empty)."""
    if lvl >= 3:
        return CV
    flat = strip_quoted(subst_placeholders(body))
    if re.search(r"[;&|\n<>()]", flat):
        return CV
    w = list(words_of(body))
    _, w = split_assign(w)
    if not w:
        return ""
    if w[0] == "command" and len(w) > 2 and w[1] in ("-v", "-V"):
        return os.path.basename(expand(w[2], env, ctx, lvl + 1))
    w = strip_wrappers(w)
    if not w:
        return ""
    cmd, args = os.path.basename(w[0]), w[1:]

    def ex(a):
        return expand(tilde(a, getattr(ctx, "cwd", None)), env, ctx, lvl + 1)

    if cmd == "mktemp":
        return SV
    if cmd == "pwd":
        cwd = getattr(ctx, "cwd", None)
        return cwd if cwd else CV
    if cmd == "echo":
        while args and re.fullmatch(r"-[neE]+", args[0]):
            args = args[1:]
        return " ".join(ex(a) for a in args)
    if cmd == "printf" and args:
        if "%" not in args[0] and "\\" not in args[0]:
            return ex(args[0])
        if args[0] == "%s" and len(args) == 2:
            return ex(args[1])
        return CV
    if cmd in ("which", "type") and args:
        names = [a for a in args if not a.startswith("-")]
        if cmd == "type" and "-P" not in args and "-p" not in args:
            return CV
        return os.path.basename(ex(names[0])) if names else CV
    if cmd in ("dirname", "basename", "realpath", "readlink"):
        opts = [a for a in args if a.startswith("-")]
        pos = [a for a in args if not a.startswith("-")]
        if not pos or (cmd == "readlink" and not any(re.search(r"[fem]", o) for o in opts)):
            return CV
        v = ex(pos[0] if cmd == "basename" else pos[-1])
        mk = strongest(v)
        if mk:
            return mk
        p = _plain(v)
        if cmd == "basename":
            return posixpath.basename(p.rstrip("/")) or "/"
        if cmd == "dirname":
            q = p.rstrip("/") or "/"
            return posixpath.dirname(q) or "."
        cwd = getattr(ctx, "cwd", None)
        if not p.startswith("/"):
            if not cwd or strongest(cwd):
                return CV
            p = _plain(cwd).rstrip("/") + "/" + p
        try:
            return os.path.realpath(p)
        except Exception:
            return posixpath.normpath(p)
    return CV


def expand(tok, env, ctx, _lvl=0):
    def rep(m):
        if m.group(1) is not None:
            return _param(m.group(1), env, ctx, _lvl)
        return var_value(m.group(2), env, ctx)
    out = VAR_RE.sub(rep, tok) if "$" in tok else tok
    if "\0E" in out:
        out = _PH_RE.sub(lambda m: _cmd_output(_SUBST[int(m.group(1))], env, ctx, _lvl), out)
    return out


def tilde(tgt, cwd=None):
    m = re.match(r"~([^/]*)(.*)$", tgt, re.S)
    if not m:
        return tgt
    name, rest = m.group(1), m.group(2)
    if name == "":
        return "${HOME}" + rest
    if name == "+":
        return (cwd + rest) if cwd else "${PWD}" + rest
    if name == "-":
        return "${OLDPWD}" + rest
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


def lost_cwd(cwd):
    """True when the working directory is LOST: a cd, popd, CDPATH lookup or cwd-changing wrapper moved it to a
    place the guard cannot name. Distinct from None (the start directory was never supplied, a documented limit)
    and from a guarded value (SV, a `${VAR:?}` or mktemp directory, judged safe)."""
    return isinstance(cwd, str) and any(m in cwd for m in (TV, UV, CV))


def resolve_path(s, cwd):
    if not (s.startswith("/") or s.startswith(HOMEVAR)):
        if cwd is None or (isinstance(cwd, str) and any(m in cwd for m in MARKERS)):
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


# /proc/<pid>/root is the filesystem root of that process and /proc/<pid>/cwd its working directory: both are
# symlinks the kernel resolves at use time, so `rm -rf /proc/self/root/*` is `rm -rf /*` (review round 5 M-1).
PROC_ALIAS_RE = re.compile(r"/proc/(?:self|thread-self|\d+)(?:/task/\d+)?/(root|cwd)(?=/|$)")


def proc_alias(path):
    """('root'|'cwd', remainder) when `path` goes through a /proc/<pid>/root or /proc/<pid>/cwd link, else None."""
    m = PROC_ALIAS_RE.match(re.sub(r"/{2,}", "/", path))
    if not m:
        return None
    return m.group(1), re.sub(r"/{2,}", "/", path)[m.end():].lstrip("/")


def real_alias(path):
    """The on-disk realpath of a plain absolute path when it differs (symlinks). A glob is resolved through
    the longest glob-free directory prefix, so `<symlink-to-/>/*` is judged as `/*`."""
    if any(mk in path for mk in MARKERS):
        return None
    if path.startswith(HOMEVAR):
        path = real_home() + path[len(HOMEVAR):]
    if not path.startswith("/"):
        return None
    pa = proc_alias(path)
    if pa is not None:
        if pa[0] == "cwd":
            return None  # the process the link names is not the shell the command runs in: handled as a LOST cwd
        return "/" + pa[1] if pa[1] else "/"  # also right for a pid the guard may not read (sudo)
    if GLOB_RE.search(path):
        comps = path.split("/")
        k = next(i for i, c in enumerate(comps) if GLOB_RE.search(c))
        prefix, rest = "/".join(comps[:k]) or "/", "/".join(comps[k:])
        try:
            rp = os.path.realpath(prefix)
        except Exception:
            return None
        if rp == (prefix.rstrip("/") or "/"):
            return None
        return (rp.rstrip("/") + "/" + rest) if rest else rp
    try:
        rp = os.path.realpath(strip_tail(path))
    except Exception:
        return None
    return rp if rp != strip_tail(path) else None


def glob_below_protected_child(t):
    """True for a glob exactly one level BELOW a protected home child (~/.cache/*, ~/.config/fo*).

    The list contract (protected_paths.list) protects the child itself, not its contents; a glob that
    names the children is a bulk deletion of contents, overridable (class V), not a hard class P.
    """
    t = re.sub(r"/{2,}", "/", t).rstrip("/")
    rh = real_home()
    if t.startswith(rh + "/"):
        t = HOMEVAR + t[len(rh):]
    if not t.startswith(HOMEVAR + "/"):
        return False
    parts = t[len(HOMEVAR) + 1:].split("/")
    if len(parts) != 2 or GLOB_RE.search(parts[0]) or not GLOB_RE.search(parts[1]):
        return False
    return parts[0] in HOME_CHILDREN or parts[0].startswith(HOME_CHILD_PREFIXES)


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
    if t in home_ancestors(rh):
        return "an ancestor of the home directory (%s)" % t
    if BLOCKDEV_RE.fullmatch(t):
        return "a raw block device (%s)" % t
    if re.fullmatch(r"/home/[^/]+", t) or re.fullmatch(r"/Users/[^/]+", t):
        return "a user's home directory"
    return None


def lost_cwd_reason(s, kind):
    """Why the RELATIVE target `s` may name a protected path when the working directory is unknown (LOST), or
    None. Whole-directory targets (`.`, `*`, `.*`) count for a recursive delete only; otherwise `s` must be a
    `..` walk or its components must match the tail of a protected path (`home` for /home, `Projects` for
    ~/Projects): from some directory the guard cannot rule out, that relative name IS the protected path."""
    t = re.sub(r"/{2,}", "/", s)
    comps = [c for c in strip_tail(t).split("/") if c not in ("", ".")]
    if ".." in comps:
        return "a parent of that directory (a '..' walk)"
    recursive = kind.startswith(RECURSIVE_DELETE_KINDS)
    if not comps or comps in (["*"], [".*"]):
        return "the whole directory it runs in" if recursive else None
    rh = real_home()
    prot = protected_paths(rh) | {"/"}
    for p in sorted(prot):
        pc = [c for c in p.split("/") if c]
        if len(comps) <= len(pc) and all(fnmatch.fnmatchcase(pc[len(pc) - len(comps) + i], comps[i])
                                         for i in range(len(comps))):
            return "a protected path (%s)" % p
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
# a recursive delete whose whole target is unknown is class V (round 7). A constant, not an environment
# switch (review round 1, finding 11): only the mutation test edits it, in a scratch copy of this file.
R7_UNKNOWN_RECURSIVE = True
RECURSIVE_DELETE_KINDS = ("rm -r", "shred -r", "find -delete", "git clean")
INTERP_RE = re.compile(r"(?:python[0-9.]*|perl[0-9.]*|node(?:js)?|ruby[0-9.]*|php[0-9.]*)")
INTERP_DELETE_RE = re.compile(r"(?:\brmtree|\bremove_tree|\brm_rf|\brm_r|\brmSync|\brimraf(?:\.sync)?|\brmdirSync|\bFileUtils\.rm_rf|\bshutil\.rmtree)\s*\(\s*([^,)]*)")
_SCRIPT_TEXT = [""]
_REF_RE = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)")


def never_assigned_target(tgt):
    """True when the delete target is nothing but variable references, none of whose names appears
    anywhere in the analysed text except as a `$NAME` reference: it is never assigned, read, looped
    over or declared in the text, so its value comes from the caller's environment and can be empty.
    A name that is assigned somewhere (a `mktemp -d` result, a `read` loop variable) is not provably
    unknown, so ordinary scratch-directory cleanup is not flagged. Command substitutions are not
    covered here."""
    if "$(" in tgt or "`" in tgt or "\x00" in tgt:
        return False
    names = _REF_RE.findall(tgt)
    if tgt.strip("'\"") == "~-":
        names = ["OLDPWD"]  # `~-` is $OLDPWD; unset-in-the-text means it comes from the caller's environment
    if not names:
        return False
    text = _SCRIPT_TEXT[0]
    for n in set(names):
        if re.search(r"(?<![$\w{])" + re.escape(n) + r"(?!\w)", text):
            return False
    return True
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


_ASSIGN_PARAM_RE = re.compile(r"\$\{[A-Za-z_]\w*:?=")


def _split_words(ws, sp, env, st):
    """Word splitting: an unquoted expansion whose value holds whitespace becomes several words
    (`D="/tmp/x /home"; rm -rf $D` deletes both). Only fully known values are split."""
    out = []
    for x in ws:
        if x in sp and not ASSIGN_RE.match(x) and ("$" in x or "\0E" in x):
            v = expand(tilde(x, st.cwd), env, st)
            if not strongest(v) and ARRAY_SEP not in v:
                parts = v.split()
                if len(parts) > 1:
                    out.extend(parts)
                    continue
        out.append(x)
    return out


def xargs_split(args):
    """(replace-string or None, command words) of an `xargs`/`xargs -I` argument list."""
    i, repl = 0, None
    while i < len(args) and args[i].startswith("-") and args[i] != "--":
        a = args[i]
        if a in ("-I", "-J") and i + 1 < len(args):
            repl = args[i + 1]
            i += 2
        elif (a.startswith("-I") or a.startswith("-J")) and len(a) > 2:
            repl = a[2:]
            i += 1
        elif a == "-i" or a.startswith("--replace"):
            repl = a.split("=", 1)[1] if "=" in a else "{}"
            i += 1
        elif a.startswith("-i") and len(a) > 2:
            repl = a[2:]
            i += 1
        else:
            i += 2 if a in XARGS_ARG else 1
    if i < len(args) and args[i] == "--":
        i += 1
    return repl, args[i:]


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
        repl = xargs_split(args)[0]
        if repl:
            # `-I%`/`-J@`/`--replace=X`: the replace string stands for the piped item
            # (also when embedded, `%/x`), it is not a literal path
            tg = [("{}" if repl in x else x) for x in tg]
    else:
        prepl = None
        while i < len(args) and args[i].startswith("-"):
            a = args[i]
            if a in ("-I", "--replace") and i + 1 < len(args):
                prepl = args[i + 1]
            elif a.startswith("--replace="):
                prepl = a.split("=", 1)[1]
            elif a.startswith("-I") and len(a) > 2:
                prepl = a[2:]
            elif a in ("-i", "--replace"):
                prepl = "{}"
            i += 2 if a in PARALLEL_ARG else 1
        body = args[i:]
        if prepl and prepl != "{}":
            # parallel -I%: the replace string stands for the input item, not a literal path
            body = [("{}" if prepl in x else x) for x in body]
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
        if pipe[0] == "lit" and len(pipe) > 2 and pipe[2]:
            targets += [x for x in pipe[2].split("\0") if x.strip()]
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
        deletes, strings, own = info["delete"], [], None
        for ex in info["execs"]:
            cw = strip_wrappers(ex)
            if not cw:
                continue
            b = os.path.basename(cw[0])
            if b in ("rm", "shred", "unlink", "rmdir"):
                deletes = True
            elif b in OWNERSHIP_CMDS:
                own = own or b   # find recurses by itself: no -R needed
            elif b in SHELLS:
                cw = shnorm(cw)
                for k, x in enumerate(cw[1:], 1):
                    if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", x) and k + 1 < len(cw):
                        strings.append(cw[k + 1])
                        if DESTRUCT_RE.search(cw[k + 1]):
                            deletes = True
                        break
        if not deletes:
            if own:
                return "find -exec %s" % own, (paths or ["."]), {"find": info, "shell_strings": strings}
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
    if cmd == "git":
        # git [-C dir] [-c k=v] [--git-dir=..] [--work-tree=..] clean -f...: deletes untracked files
        # under the work tree (with -x also ignored ones, with -d whole directories)
        k, wd = 0, None
        while k < len(args) and args[k].startswith("-"):
            a = args[k]
            if a in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"):
                if a in ("-C", "--work-tree") and k + 1 < len(args):
                    nxt = args[k + 1]
                    wd = nxt if (wd is None or a == "--work-tree" or nxt.startswith(("/", "~", "$"))) else wd.rstrip("/") + "/" + nxt
                k += 2
                continue
            if a.startswith("--work-tree="):
                wd = a.split("=", 1)[1]
            k += 1
        if k >= len(args) or args[k] != "clean":
            return None
        opts = args[k + 1:]
        dry = any(o == "--dry-run" or re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", o) for o in opts)
        force = any(o == "--force" or re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", o) for o in opts)
        if dry or not force:
            return None
        return ("git clean -f", [wd or "."], {})
    if cmd == "dd":
        dest = [a.split("=", 1)[1] for a in args if a.startswith("of=")]
        return ("dd", dest, {}) if dest else None
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
                 funcs=None, links=None, active=None, _lazy=None):
        self._ctx = ctx
        self._lazy = _lazy  # (parent State, text, fresh): ctx is joined on first use
        self.env = env if env is not None else {}
        self.cwd = cwd
        self.findings = findings if findings is not None else []
        self.markers = markers if markers is not None else []
        self.funcs = funcs if funcs is not None else {}
        self.links = links if links is not None else {}
        self.active = active if active is not None else set()
        self._guards = None
        self._gsrc = None  # (parent State, text): guards = parent's guards plus those in text

    @property
    def guards(self):
        """Names guarded in the text seen so far. A child's set is its parent's plus the guards in
        its own text (a guard split across the join is not counted: fewer guards, never more)."""
        if self._guards is None:
            if self._gsrc is not None:
                parent, text = self._gsrc
                self._guards = parent.guards | guarded_vars(text)
                self._gsrc = None
            else:
                self._guards = guarded_vars(self.ctx)
        return self._guards

    @property
    def ctx(self):
        if self._ctx is None:
            parent, text, fresh = self._lazy
            pc = parent.ctx
            self._ctx = (text + "\n" + pc) if fresh else (pc + "\n" + text)
            self._lazy = None
        return self._ctx

    def child(self, text, fresh=False, positional=None, zero=None):
        if fresh:
            st = State(None, {}, None, self.findings, self.markers,
                       self.funcs, self.links, self.active, _lazy=(self, text, True))
        else:
            st = State(None, dict(self.env), self.cwd, self.findings,
                       self.markers, self.funcs, self.links, self.active, _lazy=(self, text, False))
        st._gsrc = (self, text)
        if positional is not None:
            for k in [k for k in st.env if k.isdigit()]:
                del st.env[k]
            for n, v in enumerate(positional, 1):
                st.env[str(n)] = v
            st.env["@"] = st.env["*"] = ARRAY_SEP.join(positional)
            st.env["#"] = SV
        if zero is not None:
            st.env["0"] = zero
        return st

    def add(self, cls, msg):
        self.findings.append((cls, unph(msg)))  # show `$(...)`, never the internal placeholder

    def apply_assign(self, name, raw, plus, env):
        if raw.startswith(ARRAY_TAG):
            body = raw[1:]
            val = ARRAY_SEP.join(expand(x, env, self) for x in body.split(ARRAY_SEP)) if body else ""
        else:
            val = expand(raw, env, self)
        # a variable holding unknown command output behaves like any unknown variable
        val = val.replace(CV, UV)
        if plus and name in env:
            val = env[name] + val
        if name in self.guards:
            val = val.replace(TV, SV).replace(UV, SV).replace(CV, SV)
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

    def loop_value(self, vals):
        """Value a literal `for` variable takes: the first literal that is protected (so the protected check
        applies to the loop body), else the first literal, else SV (empty word list)."""
        vals = [v for v in vals if v != ""]
        if not vals:
            return SV
        for v in vals:
            for piece in brace_expand(v):
                path = self.link_resolve(resolve_path(piece, self.cwd))
                if glob_below_protected_child(path) or protected_reason(path) or protected_reason(real_alias(path) or "/nonexistent-x"):
                    return piece
        return vals[0]

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
            home_taint = home_taint or CV in hv
            if home_taint:
                if not only_p:
                    self.add("H", "HOME is reassigned from an expansion that can be empty or tainted, then %s deletes %s — if the expansion is empty HOME becomes a real directory such as /home" % (kind, tgt))
                return
        expanded = expand(tilde(tgt, self.cwd), env, self)
        for piece in expanded.split(ARRAY_SEP):
            self._check_expanded(kind, tgt, piece, filt, only_p)

    def _check_expanded(self, kind, tgt, s, filt, only_p):
        if TV in s:  # MUT-V
            if not only_p:
                self.add("V", "%s deletes %s but it derives from an unguarded positional parameter, input read at run time (read/mapfile) or an indirect expansion — an empty or wrong value makes the target wrong; use ${VAR:?}" % (kind, tgt))
            return
        if SV in s:
            if not re.search(r"(?:^|/)\.\.(?:/|$)", s):
                return
            # a safe prefix followed by '..' can land anywhere (even on a sibling of the prefix)
            if not only_p:
                self.add("V", "%s deletes %s: a '..' component after a guarded or temporary prefix can leave that prefix's subtree" % (kind, tgt))
            return
        if UV in s or CV in s:
            u = s.replace(UV, "").replace(CV, "")
            if u and (u.startswith("/") or u.startswith(HOMEVAR)):
                why = protected_reason(self.link_resolve(resolve_path(u, None)))
                if why and not only_p:
                    self.add("V", "%s deletes %s; if the unknown/empty expansion in it is empty the target is %s — use ${VAR:?} or safe_rm_rf" % (kind, tgt, why))
                return
            whole = u in ("", "*", ".*", ".", "./")
            if UV in s and CV not in s and whole and not only_p and R7_UNKNOWN_RECURSIVE and kind.startswith(RECURSIVE_DELETE_KINDS) and never_assigned_target(tgt):
                # round 7: a recursive delete whose WHOLE target is a value the guard cannot know (an
                # unset or computed variable) can be empty or anything, `/` and `$HOME` included
                if filt is not None and not filt["unsafe"] and any(idx < filt["action_idx"] for _f, _p, idx in filt["names"]):
                    return
                self.add("V", "%s deletes %s: the whole target is a value the guard cannot know (unset, empty or computed) — if it is empty or wrong a protected path is deleted; guard it with ${VAR:?} or compute it from a literal" % (kind, tgt))
                return
            if CV in s and whole and not only_p:
                if filt is not None and not filt["unsafe"] and any(idx < filt["action_idx"] for _f, _p, idx in filt["names"]):
                    return
                self.add("V", "%s deletes %s: the whole target is the output of a command the guard cannot compute — it can be any path, including a protected one; compute it into a guarded variable (${VAR:?}) first" % (kind, tgt))
            return
        if lost_cwd(self.cwd) and not only_p and not (s.startswith("/") or s.startswith(HOMEVAR)):
            why = lost_cwd_reason(s, kind)
            if why:
                self.add("V", "%s deletes %s: the working directory is not known here (a cd, popd, CDPATH lookup or "
                         "wrapper moved it somewhere the guard cannot resolve) and this relative target can name %s "
                         "from there — cd to a literal directory first, guard the cd with ${VAR:?}, or use an "
                         "absolute path" % (kind, tgt, why))
                return
        pa = proc_alias(s) if s.startswith("/") else None
        if pa is not None and pa[0] == "cwd" and not only_p:
            # /proc/<pid>/cwd is that process's working directory: not the shell's, so it is a LOST directory
            why = lost_cwd_reason(pa[1] or ".", kind)
            if why:
                self.add("V", "%s deletes %s: /proc/<pid>/cwd is a working directory the guard cannot name and this "
                         "target can name %s from there — use a literal directory" % (kind, tgt, why))
                return
        path = self.link_resolve(resolve_path(s, self.cwd))
        if glob_below_protected_child(path):
            if not only_p:
                self.add("V", "%s deletes the contents of a protected home directory (%s) in bulk — overridable with a reasoned '# guardrails:allow' marker" % (kind, tgt))
            return
        why = protected_reason(path)
        if not why:
            real = real_alias(path)
            if real:
                why = protected_reason(real)
        if why:
            if filt is not None and self.find_ok(path, filt):
                return
            self.add("P", "%s targets %s (%s)" % (kind, why, tgt))


READ_ARG_OPTS = {"read": set("dnNptui"), "mapfile": set("dnOsuCc"), "readarray": set("dnOsuCc")}


def read_targets(base, args):
    """Variable names a `read`/`mapfile` assigns (options that take an argument are skipped)."""
    names, i = [], 0
    takes = READ_ARG_OPTS[base]
    while i < len(args):
        a = args[i]
        if a == "--":
            names.extend(args[i + 1:])
            break
        if a.startswith("-") and len(a) > 1:
            # a clustered option whose last letter takes an argument consumes the next word
            if a[-1] in takes and len(a) == 2 or (len(a) > 2 and a[-1] in takes and a[1] not in takes):
                i += 1
            i += 1
            continue
        names.append(a)
        i += 1
    names = [x for x in names if re.fullmatch(r"[A-Za-z_]\w*", x)]
    return names or (["MAPFILE"] if base != "read" else ["REPLY"])


_STMT_SPLIT_RE = re.compile(r"[;&|\n]")
_HIDE_HEADS = {"eval", "source", ".", "bash", "sh", "zsh", "dash", "ksh", "xargs", "parallel"}
_LEAD_KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "(", "time"}


def _hiding_head(stmt):
    """True when the command word of `stmt` is a construct a delete can hide behind: an expansion,
    a quoted expansion, a brace/glob head, an escaped word, or a command that runs another string."""
    toks = stmt.split()
    i = 0
    while i < len(toks) and (ASSIGN_RE.match(toks[i]) or toks[i] in WRAPPERS or toks[i] in _LEAD_KEYWORDS):
        i += 1
    if i >= len(toks):
        return False
    t = toks[i]
    if t in ("[", "[[", "]", "]]"):
        return False  # the test builtins: a bracket here is not a glob
    if t.startswith("#"):
        return False  # a comment
    if not re.search(r"[A-Za-z_]|\$\{?[@*0-9]", " ".join(toks[i:])):
        return False  # punctuation only and no positional parameter: no command can be named
    if t[0] in "$`\\" or (t[0] in "'\"" and ("$" in t or "`" in t)):
        return True  # also "$@" / $* / $1: the caller's arguments become the command
    if (t[0] == "{" and len(t) > 1) or GLOB_RE.search(t):
        return True
    return os.path.basename(t.strip("'\"")) in _HIDE_HEADS


def _body_inert(body):
    """True when nothing in `body` can delete, link, or run code the guard cannot see: no destructive
    verb (also obfuscated), no `ln`, and no statement (also inside a substitution) whose command word
    is an expansion or a command that runs another string."""
    if destructive_text(body) or re.search(r"(?<![\w.-])ln(?![\w.-])", body):
        return False
    for chunk in [body] + balanced_subst(body):
        for stmt in _STMT_SPLIT_RE.split(chunk):
            if stmt.strip() and _hiding_head(stmt):
                return False
    return True


_INERT_CACHE = {}


def inert_functions(funcs):
    """Names of functions whose call cannot produce a finding: their body is inert and every known
    function they mention is inert too (a fixpoint, so recursion is handled). Analysing such a call
    again for every call site was the dominant cost on large test scripts; the analysis of a call
    never changes the caller's environment (a child state copies it), so skipping it loses nothing."""
    key = (id(funcs), len(funcs), sum(len(b) for b in funcs.values()))
    hit = _INERT_CACHE.get(key)
    if hit is not None:
        return hit
    names = set(funcs)
    bad = {n for n, b in funcs.items() if not _body_inert(b)}
    calls = {n: set(re.findall(r"[A-Za-z_][\w:.-]*", b)) & names for n, b in funcs.items()}
    changed = True
    while changed:
        changed = False
        for n in names - bad:
            if calls[n] & bad:
                bad.add(n)
                changed = True
    out = frozenset(names - bad)
    _INERT_CACHE.clear()
    _INERT_CACHE[key] = out
    return out


class _BudgetExhausted(BaseException):
    """Raised when the deterministic work budget (or the last-resort clock) runs out. BaseException,
    so no `except Exception` inside the analysis can swallow it; run() catches it and hands the whole
    input to fallback_scan()."""


MAX_FALLBACK_DEPTH = 3            # eval / sh -c strings re-scanned on the degraded path
MAX_FALLBACK_WORK = 20_000_000    # characters of expanded words before the degraded path gives up
FALLBACK_VALUE_CAP = 4096         # a longer variable value is treated as unknown on the degraded path
_FN_HEAD_RE = re.compile(r"^(?:function\s+)?[A-Za-z_][\w.:-]*\s*\(\s*\)\s*")
_FORCE_RE = re.compile(r"-[A-Za-z]*[rRf][A-Za-z]*|--recursive|--force|-delete|--del\S*|--remove\S*")
_FB_SKIP_WORDS = _LEAD_KEYWORDS | {"}", ")", "fi", "done", "esac", ";;"}


def _forceful(words):
    """A recursive or forced delete flag among `words` (rm -r/-f, find -delete, git clean -f, ...)."""
    return any(_FORCE_RE.fullmatch(x) for x in words)


_FB_VERBS = ("rm", "shred", "rmdir", "unlink", "chmod", "chown", "chgrp", "find", "rsync", "mv", "dd",
             "git", "eval", "xargs", "env", "sudo", "doas", "command", "exec", "busybox", "trap",
             "sh", "bash", "dash", "zsh", "ksh", "mksh", "fish", "mkfs", "wipefs")


def _fb_glob_can_name_verb(head):
    """True when a glob command word could expand to a destructive or command-running program.
    A test bracket ('[', '[['), a jq-style '[.x]' or any pattern that cannot match such a name is
    not a hidden command."""
    import fnmatch
    if head in ("[", "[[", "]", "]]"):
        return False
    base = head.rsplit("/", 1)[-1] or head
    try:
        return any(fnmatch.fnmatchcase(v, base) for v in _FB_VERBS)
    except Exception:
        return True


def fallback_scan(text, st, why):
    """The ONE degraded check, used on every exit where the full analysis cannot finish: the work
    budget, the last-resort clock, nesting deeper than MAX_DEPTH, and an internal error. It is linear
    in the text and cannot raise. Per statement it follows plain assignments, mktemp/read/for values
    and cd, re-checks every delete for class P, and blocks with class X (not overridable) any delete
    it cannot judge that is recursive or forced, and any command word it cannot resolve (a variable,
    a function argument, an ANSI-C or split verb, eval or sh -c of an unreadable string) that is used
    with a recursive/force flag, a destructive verb or a protected path. An uncertain delete without
    such a flag is class U, which only a '# guardrails:allow' marker on the first line can allow."""
    try:
        _fallback(text, st, 0, [0], why)
    except Exception as exc:
        st.add("X", "%s, and the degraded check itself failed (%s: %s) — the text cannot be inspected" % (why, type(exc).__name__, exc))


def _fb_expand(tok, env, local, work):
    if tok.count("$") * FALLBACK_VALUE_CAP > 1_000_000:
        return UV  # too many references to expand cheaply
    v = expand(tok, env, local)
    work[0] += len(v)
    return v


def _fb_assign(local, m, env, work):
    if m.group(3).count("$") * FALLBACK_VALUE_CAP > 1_000_000:
        env[m.group(1)] = UV
        return
    local.apply_assign(m.group(1), m.group(3), bool(m.group(2)), env)
    work[0] += len(env[m.group(1)])
    if len(env[m.group(1)]) > FALLBACK_VALUE_CAP:
        env[m.group(1)] = UV


def _fb_protected_arg(args, env, local, work):
    for a in args:
        if a.startswith("-"):
            continue
        v = _fb_expand(tilde(a, local.cwd), env, local, work)
        if strongest(v):
            continue
        for piece in brace_expand(v)[:64]:
            path = local.link_resolve(resolve_path(piece, local.cwd))
            if glob_below_protected_child(path) or protected_reason(path):
                return True
    return False


_SHELLISH = ("bash", "sh", "zsh", "dash", "ksh", "mksh", "source", ".", "su", "eval", "sudo", "doas")


def _fb_statements(text, st, why):
    """The statements of `text` for the degraded check, split by the SAME tokenizer the full analysis
    uses (quotes respected), plus the statements inside every command substitution, and the body of
    a heredoc when it is fed to a shell or written to a file. The old quote-blind split on [;&|\n]
    made a quoted awk program ('$0 ~ /x/') look like a command (review round 4 B2-r4). When the
    tokenizer cannot parse the text, the quote-blind split is used, and a text that also contains a
    destructive command is class X, exactly as on the full path."""
    out, todo, n, chars = [], [text], 0, 0
    limit = max(4 * len(text), 400_000)  # nested bodies re-scan the same text: bound the total
    while todo and n < 20000 and chars < limit:
        t = todo.pop()
        n += 1
        chars += len(t)
        try:
            segs, heredocs, _comments, problems = segment(t)
        except Exception:
            segs, heredocs, problems = None, [], ["tokenizer failure"]
        if problems or segs is None:
            if destructive_text(t):
                st.add("X", "%s; the command cannot be parsed reliably (%s) and it contains a destructive command" % (why, "; ".join(sorted(set(problems)))))
            out.extend(_STMT_SPLIT_RE.split(t))
            continue
        for seg_text, _sep in segs:
            out.append(seg_text)
            todo.extend(balanced_subst(seg_text))
        for owner, body, quoted, stages in heredocs:
            otext = " ".join([owner] + list(stages))
            if any(re.search(r"(?<![\w.-])%s(?![\w.-])" % re.escape(x), otext) for x in _SHELLISH) or ">" in otext or "tee" in otext:
                todo.append(body)
            elif not quoted:
                todo.extend(balanced_subst(body))
    if todo and (destructive_text(text) or any(destructive_text(t) for t in todo[:200])):
        # a pending body is a substring of `text` (a backtick body is unescaped, hence the extra look)
        st.add("X", "%s; the degraded check reached its statement limit on text that contains a destructive command" % why)
    return out


def _fallback(text, st, depth, work, why):
    text = text.replace("\\\n", "")
    env = dict(st.env)
    found = []
    local = State(text, env, st.cwd, findings=found, markers=[], funcs=st.funcs, links=st.links)
    fb_restore = []  # cwd to put back after a command whose wrapper changed it

    def run_str(s):
        v = _fb_expand(s, env, local, work)
        if strongest(v):
            if destructive_text(text) or destructive_text(unph(s)):
                st.add("U", "%s; a shell would run %s, whose value the guard cannot read, in text that contains a destructive command" % (why, unph(s).strip()))
            return
        v = unph(v)
        if depth >= MAX_FALLBACK_DEPTH:
            if destructive_text(v):
                st.add("X", "%s; a string run by eval or sh -c is nested too deeply to inspect and contains a destructive command" % why)
            return
        _fallback(v, State(v, dict(env), local.cwd, findings=st.findings, markers=[], funcs=st.funcs, links=st.links), depth + 1, work, why)

    for raw in _fb_statements(text, st, why):
        if work[0] > MAX_FALLBACK_WORK:
            if destructive_text(text):
                st.add("X", "%s, and the degraded check reached its own work limit on text that contains a destructive command" % why)
            return
        s = _FN_HEAD_RE.sub("", raw.strip())
        if not s or s.startswith("#"):
            continue
        work[0] += len(s)
        try:
            words = words_of(s)
        except Exception:
            words = s.split()
        while words and (words[0] in _FB_SKIP_WORDS or words[0][:1] in "({"):
            first = words[0].lstrip("({")
            words = ([first] if first and words[0] not in _FB_SKIP_WORDS else []) + words[1:]
        assigns, rest = split_assign(words)
        for a in assigns:
            _fb_assign(local, ASSIGN_RE.match(a), env, work)
        weff = []
        w = strip_wrappers(rest, None, weff)
        if fb_restore:
            local.cwd = fb_restore.pop()
        if weff:
            fb_restore.append(local.cwd)
            for e in weff:
                if e[0] == "lost":
                    local.cwd = UV
                else:
                    v = _fb_expand(tilde(e[1], local.cwd), env, local, work)
                    sg = strongest(v)
                    local.cwd = (None if sg == SV else UV) if sg else (
                        local.cwd if (lost_cwd(local.cwd) and not v.startswith("/")) else resolve_path(v, local.cwd))
        if not w:
            continue
        base = os.path.basename(w[0])
        if base in DECLARERS:
            for x in w[1:]:
                m = ASSIGN_RE.match(x)
                if m:
                    _fb_assign(local, m, env, work)
            continue
        if base in READ_ARG_OPTS:
            for n in read_targets(base, w[1:]):
                env[n] = TV
            continue
        if base == "for" and len(w) >= 3 and w[2] == "in":
            vals = [_fb_expand(tilde(x, local.cwd), env, local, work) for x in w[3:]]
            if any(TV in v for v in vals):
                env[w[1]] = TV
            elif any(UV in v or CV in v for v in vals):
                env[w[1]] = UV
            else:
                env[w[1]] = local.loop_value(vals)
            continue
        if base in ("cd", "pushd"):
            def _fb_resolve(raw):
                v = _fb_expand(tilde(raw, local.cwd), env, local, work)
                sg = strongest(v)
                if sg is None:
                    return resolve_path(v, local.cwd) if not (lost_cwd(local.cwd) and not v.startswith("/")) else local.cwd
                return None if sg == SV else UV
            _old = local.cwd if isinstance(local.cwd, str) else UV
            local.cwd = cwd_transition(base, w[1:], local.cwd, env, _fb_resolve)
            env["OLDPWD"] = _old
            continue
        if base == "popd":
            local.cwd = UV
            continue
        # resolve the command word: a variable, a brace expansion or a glob can name a delete
        hidden = False
        for _ in range(4):
            head = w[0]
            if "$" in head or "\0E" in head:
                v = _fb_expand(head, env, local, work)
                if strongest(v) or not v.strip() or v == head:
                    hidden = True
                    break
                if ARRAY_SEP in v:
                    # "${a[@]}": each element is one word, never re-split
                    parts = [x for x in v.split(ARRAY_SEP) if x]
                else:
                    try:
                        parts = shlex.split(v) if len(v) <= 4096 else v.split()
                    except ValueError:
                        parts = v.split()
                if not parts:
                    hidden = True
                    break
                w = strip_wrappers(parts + w[1:])
            elif head[:1] == "{" and len(head) > 1:
                variants = brace_expand(head)
                if len(variants) < 2:
                    break
                w = strip_wrappers(variants + w[1:])
            elif head[:1] in "\\'\"" or ("\\" in head and not GLOB_RE.search(head)):
                # quoting does not hide a literal word: 'r'm -> rm
                plain = head.replace("\\", "").replace("'", "").replace('"', "")
                if not plain or plain == head:
                    break
                w = strip_wrappers([plain] + w[1:])
            elif GLOB_RE.search(head):
                # a glob hides a command only if it can name a destructive one (/bin/r?, r[m])
                hidden = _fb_glob_can_name_verb(head)
                break
            else:
                break
            if not w:
                break
        if not w:
            continue
        base = os.path.basename(w[0])
        args = w[1:]
        force = _forceful(args)
        if hidden:
            # X (not overridable) only for a recursive/force flag or a protected path; a hidden
            # command word next to a destructive word alone is uncertain, so class U (a marker can
            # allow it). Review round 4 B2-r4: '$0' in awk text was a non-overridable X.
            if force or _fb_protected_arg(args, env, local, work):
                st.add("X", "%s; in the text the guard could not fully analyse, the command word %s cannot be resolved and is used with a recursive/force flag or a protected path" % (why, unph(w[0])))
            elif destructive_text(unph(" ".join(w))):
                st.add("U", "%s; in the text the guard could not fully analyse, the command word %s cannot be resolved and is used with a destructive command" % (why, unph(w[0])))
            continue
        if base == "eval":
            run_str(" ".join(args))
            if _CD_WORD_RE.search(" ".join(args)) or "$" in " ".join(args):
                local.cwd = UV      # the string runs in this shell and may move it (fix round 5, M-2)
        elif base in SHELLS:
            args = shnorm([base] + list(args))[1:]
            for k, x in enumerate(args):
                if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", x) and k + 1 < len(args):
                    run_str(args[k + 1])
                    break
        elif base == "trap" and args and not args[0].startswith("-"):
            run_str(args[0])
            if _CD_WORD_RE.search(args[0]):
                local.cwd = UV      # a trap body runs in this shell and can move it before a later command
        try:
            res = delete_targets(w)
        except Exception:
            res = None
            if destructive_text(s) and force:
                st.add("X", "%s; a recursive or forced delete could not be parsed: %s" % (why, unph(s)[:120]))
        if not res:
            continue
        kind, targets, extra = res
        for ss in extra.get("shell_strings", []):
            run_str(ss)
        hard = force or kind.startswith("git clean") or extra.get("find") is not None
        if extra.get("unknown_input"):
            found.append(("V", "%s reads its targets from input the guard cannot inspect" % kind))
        for tgt in targets:
            local.check_target(kind, tgt, env, extra.get("find"))
        for cls, msg in found:
            if cls == "P":
                st.add("P", msg)
            elif hard:
                st.add("X", "%s; %s — recursive or forced, so not overridable" % (why, msg))
            else:
                st.add("U", "%s; %s" % (why, msg))
        del found[:]


_FRAMES = [0]


def new_cwd(raw, env, st):
    """The working directory after moving to `raw` (a cd/pushd argument or a wrapper's chdir value), as one of:
    a resolved path (known), UV (LOST: the guard cannot name it), or None (guarded value, judged safe).
    A relative target while the cwd is already LOST stays LOST; a non-empty CDPATH makes a bare relative name
    ambiguous (bash searches CDPATH first), so it is LOST too."""
    s = expand(tilde(raw, st.cwd), env, st)
    if any(mk in s for mk in (TV, UV, CV)):
        return UV
    if SV in s:
        return None
    if GLOB_RE.search(s):
        return UV
    absolute = s.startswith("/") or s.startswith(HOMEVAR)
    pa = proc_alias(s) if s.startswith("/") else None
    if pa is not None and pa[0] == "cwd":
        return UV  # /proc/<pid>/cwd is a working directory the guard cannot name
    if not absolute and lost_cwd(st.cwd):
        return st.cwd
    cdpath = env.get("CDPATH")
    if (isinstance(cdpath, str) and cdpath and not absolute and s not in (".", "..")
            and not s.startswith("./") and not s.startswith("../")):
        return UV
    return resolve_path(s, st.cwd)


_CD_WORD_RE = re.compile(r"(?<![\w./-])(?:cd|pushd|popd)(?![\w./-])")


def cwd_transition(base, args, cur, env, resolve):
    """The working directory after ONE `cd`/`pushd` command: the single implementation both the main walk and the
    degraded (fallback) walk call, so a fix cannot be applied to one copy only (review round 5 N-2).
    `args` are the words after the command name, `cur` the directory before it, `env` the variables known so far
    and `resolve(raw)` the caller's way of turning one path word into a directory (a path, UV = LOST, or None =
    a guarded value judged safe). A bare `cd` goes to the HOME the command text assigned (`resolve("~")` reads
    the tracked value), never to the startup HOME (review round 5 I-1)."""
    argv = [x for x in args if x == "-" or not x.startswith("-")]
    argv = [x for x in argv if x != "--"]
    if base == "pushd" and any(re.fullmatch(r"[+-]\d+", x) for x in args):
        return UV           # `pushd +N` / `-N` rotates the directory stack: the guard does not track it
    if base == "pushd" and "-n" in args:
        return cur          # `pushd -n DIR` adds to the stack WITHOUT changing the directory
    if not argv:
        return resolve("~") if base == "cd" else UV
    if argv[0] == "-":
        ov = env.get("OLDPWD", UV)
        return UV if (not isinstance(ov, str) or any(mk in ov for mk in MARKERS)) else ov
    return resolve(argv[0])


def analyse(text, st, depth=0):
    """`depth` counts how many times a STRING was re-parsed as code (eval, sh -c, a heredoc fed
    to a shell, a word that expands to several words): that is where obfuscation layers stack, so
    it stays bounded by MAX_DEPTH. Command substitutions and function calls do not raise `depth`
    (review round 4 B2-r4: ordinary libraries chain $(f) calls deeper than five levels); they are
    bounded by MAX_FRAMES, the total analysis nesting, and a function cannot re-enter itself."""
    root = _FRAMES[0] == 0
    _FRAMES[0] += 1
    try:
        _analyse(text, st, depth, root)
    finally:
        _FRAMES[0] -= 1


def _analyse(text, st, depth, root):
    text = text.replace("\\\n", "")
    _budget["chars"] += len(text)
    if _over_budget():
        raise _BudgetExhausted()
    if depth > MAX_DEPTH or _FRAMES[0] > MAX_FRAMES:
        fallback_scan(text, st, "nesting deeper than %d levels cannot be fully analysed"
                      % (MAX_DEPTH if depth > MAX_DEPTH else MAX_FRAMES))
        return
    segs, heredocs, comments, problems = segment(text)
    if problems and destructive_text(text):
        st.add("X", "the command cannot be parsed reliably (%s) and it contains a destructive command" % "; ".join(sorted(set(problems))))
    if root:
        for c, nested in comments:
            if nested:
                continue
            m = MARKER_RE.match(c.strip())
            if m:
                st.markers.append(m.group(1).strip())
    st.funcs.update(find_functions(text))

    def _shell_child(text, env, args):
        """State for a string run by a child shell: it sees the caller's variables (a prefix assignment
        or `env NAME=v` included); `sh -c STR a b` binds $0=a and $1..=rest; no args leaves $0 as the shell."""
        if args:
            vals = [expand(tilde(a, st.cwd), env, st) for a in args]
            ch = st.child(text, positional=vals[1:], zero=vals[0])
        else:
            ch = st.child(text)
        base_env = dict(env)
        for k in [k for k in ch.env if k.isdigit() or k in ("@", "*", "#")]:
            base_env[k] = ch.env[k]
        if not args:
            for k in [k for k in base_env if k.isdigit() or k in ("@", "*", "#")]:
                if k not in st.env:
                    del base_env[k]
        ch.env = base_env
        return ch

    def run_string(s, env, args=None, adopt=False):
        """Analyse a string a shell will execute; a lone variable reference is resolved first. `adopt` is for
        `eval`, which runs the string in the CURRENT shell: the working directory the string leaves is the
        caller's from then on (fix round 5, M-2); a string the guard cannot read leaves it LOST."""
        if re.fullmatch(r"\s*(?:\$\{?[A-Za-z_]\w*\}?|\0E\d+\0)\s*", s):
            s2 = expand(s, env, st)
            if not any(mk in s2 for mk in MARKERS):
                ch = _shell_child(s2, env, args)
                analyse(s2, ch, depth + 1)
                if adopt:
                    st.cwd = ch.cwd
            elif TV in s2 or UV in s2 or CV in s2:
                if DESTRUCT_RE.search(st.ctx):
                    st.add("U", "a shell would run %s, whose value the guard cannot read, in a command that also contains a destructive command" % unph(s).strip())
                if adopt:
                    st.cwd = UV
            elif adopt:
                st.cwd = UV
            return
        s = unph(s)
        ch = _shell_child(s, env, args)
        analyse(s, ch, depth + 1)
        if adopt:
            st.cwd = ch.cwd

    def arg_protected(args, env):
        """True when an argument of an unresolved command word is, as written, a protected path."""
        for a in args:
            if a.startswith("-"):
                continue
            v = expand(tilde(a, st.cwd), env, st)
            if strongest(v):
                continue
            for piece in brace_expand(v):
                path = st.link_resolve(resolve_path(piece, st.cwd))
                if glob_below_protected_child(path) or protected_reason(path):
                    return True
        return False

    def resolve_head(w, env, n=0):
        if not w:
            return w  # the command word expanded to wrappers only: nothing runs here
        head = w[0]
        if n > 4 or head in ("[", "[[", "{", "}", "!"):
            return w
        if "$" not in head and "\0E" not in head and "{" not in head and not GLOB_RE.search(head):
            return w
        if "$" not in head and "\0E" not in head:
            variants = brace_expand(head)
            if len(variants) > 1:
                # bash expands `{r,}m -rf X` to `rm m -rf X`: the first word runs, the rest are arguments
                return resolve_head(strip_wrappers(variants + w[1:]), env, n + 1)
            if GLOB_RE.search(head):
                pat = os.path.basename(head)
                hits = [c for c in DCMDS if fnmatch.fnmatchcase(c, pat)]
                for extra in hits[1:]:
                    t = shlex.join([extra] + [unph(x) for x in w[1:]])
                    analyse(t, st.child(t), depth + 1)
                if hits:
                    return [hits[0]] + w[1:]
            return w
        h2 = expand(head, env, st)
        mk = strongest(h2)
        if not mk:
            if h2 == head:
                return w  # nothing was resolved (e.g. an unterminated `$(`)
            if not h2.strip():
                # an empty command word disappears: the next word is the command
                return resolve_head(strip_wrappers(w[1:]), env, n + 1) if w[1:] else w
            if ARRAY_SEP in h2:
                parts = [x for x in h2.split(ARRAY_SEP) if x != ""]
            elif len(h2) > 4096:
                parts = h2.split()  # shlex is too slow on a huge value; plain splitting keeps the words
            else:
                try:
                    parts = shlex.split(h2)
                except ValueError:
                    parts = h2.split()
            return resolve_head(strip_wrappers(parts + w[1:]), env, n + 1) if parts else w
        # a guarded (${X:?}) command word is non-empty but still unknown: it can name a delete
        if any(RECUR_FLAG_RE.fullmatch(a) for a in w[1:]) or arg_protected(w[1:], env):
            st.add("V", "the command word %s is an expansion the guard cannot resolve, used with recursive/force flags or a protected path — it may be a destructive command; use a literal command" % unph(head))
            return w
        if mk == SV:
            return w
        if not h2.replace(TV, "").replace(UV, "").replace(CV, "").strip() and len(w) > 1:
            # an unknown, possibly empty command word: if it is empty the next word runs
            return resolve_head(strip_wrappers(w[1:]), env, n + 1)
        return w

    def xargs_shell(w, pipe, env):
        """`... | xargs [-I{}] sh -c STR [a b]`: the items become $0 $1.. (or replace {}) of STR."""
        repl, cmdw = xargs_split(w[1:])
        cmdw = strip_wrappers(cmdw)
        if not cmdw or os.path.basename(cmdw[0]) not in SHELLS:
            return
        cmdw = shnorm(cmdw)
        for k, x in enumerate(cmdw[1:], 1):
            if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", x) and k + 1 < len(cmdw):
                script, extra = cmdw[k + 1], [a for a in cmdw[k + 2:] if a != "--"]
                break
        else:
            return
        known = pipe is not None and pipe[0] in ("find", "lit")
        items = [x for x in (pipe[1] if known else []) if x not in ("", "{}")]
        if known and pipe[0] == "lit" and len(pipe) > 2 and pipe[2]:
            items += [x for x in pipe[2].split("\0") if x.strip()]
        if repl:
            for it in (items if known else [XARGS_ITEM]):
                run_string(script.replace(repl, it), env, extra)
            return
        if known:
            run_string(script, env, extra + items)
            for it in items:
                run_string(script, env, extra + [it])
            if not items:
                run_string(script, env, extra)
        else:
            run_string(script, env, extra + [XARGS_ITEM])

    cwdbox = []

    def handle(seg_text, sep, prev):
        # a wrapper's chdir (env -C, sudo -D, ...) applies to ONE command: the cwd is put back afterwards
        saved = [st.cwd]
        cwdbox.append(saved)
        try:
            return _handle(seg_text, sep, prev)
        finally:
            cwdbox.pop()
            if len(saved) > 1:
                st.cwd = saved[0]

    def _handle(seg_text, sep, prev):
        for inner in balanced_subst(seg_text):
            analyse(inner, st.child(inner), depth)
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
        # `${X:=v}` assigns X as a side effect of being expanded, even in `: "${X:=v}"`
        for x in rest:
            if "${" in x and _ASSIGN_PARAM_RE.search(x):
                expand(x, env, st)
        wrapped = []
        weff = []
        w = strip_wrappers(rest, wrapped, weff)
        if weff:
            cwdbox[-1].append(True)
            for e in weff:
                st.cwd = UV if e[0] == "lost" else new_cwd(e[1], env, st)
        if wrapped:
            if env is st.env:
                env = dict(st.env)
            for a in wrapped:
                if a == "-i":
                    env.clear()
                    continue
                m = ASSIGN_RE.match(a)
                if m:
                    st.apply_assign(m.group(1), m.group(3), bool(m.group(2)), env)
        if not w:
            return None
        w = resolve_head(w, env)
        if not w:
            return None
        sp = split_set(seg_text)
        if sp and len(w) > 1:
            w = [w[0]] + _split_words(w[1:], sp, env, st)
        if re.search(r"\s", w[0]) and not w[0].startswith("-"):
            t = unph(" ".join(w))
            analyse(t, st.child(t), depth + 1)
            return None
        base = os.path.basename(w[0])
        if base == "for" and len(w) >= 3 and w[2] == "in":
            vals = [expand(tilde(x, st.cwd), env, st) for x in w[3:]]
            if any(TV in v for v in vals):
                env[w[1]] = TV
            elif any(UV in v or CV in v for v in vals):
                env[w[1]] = UV
            else:
                env[w[1]] = st.loop_value(vals)
            return None
        if base in ("read", "mapfile", "readarray"):
            # data read at run time can be empty or anything: TAINTED (class V), like a positional parameter
            for nme in read_targets(base, w[1:]):
                env[nme] = TV
            return None
        if base == "set":
            if "--" in w:
                vals = [expand(x, env, st) for x in w[w.index("--") + 1:]]
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
                vals = [expand(tilde(x, st.cwd), env, st) for x in w[k + 2:]]
                out = None
                if not any(strongest(v) for v in vals) and vals:
                    out = sh_printf(vals[0], vals[1:])
                if out is None:
                    out = UV if "%" in fmt or "\\" in fmt else expand(fmt, env, st)
                if re.fullmatch(r"[A-Za-z_]\w*", w[k + 1]):
                    env[w[k + 1]] = out
            return None
        if base == "popd":
            st.cwd = UV  # the directory stack is not tracked: popd lands somewhere the guard cannot name
            return None
        if base in ("cd", "pushd"):
            old = st.cwd if isinstance(st.cwd, str) else UV
            new = cwd_transition(base, w[1:], st.cwd, env, lambda raw: new_cwd(raw, env, st))
            st.cwd = new
            st.env["OLDPWD"] = env["OLDPWD"] = old
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
                tgt = expand(tilde(pos[0]), env, st)
                link = expand(tilde(pos[-1]), env, st)
                if not any(mk in tgt + link for mk in MARKERS):
                    st.links[strip_tail(resolve_path(link, st.cwd))] = strip_tail(resolve_path(tgt, st.cwd))
            return None
        if base in st.funcs and base not in st.active and base in inert_functions(st.funcs):
            return None  # nothing in the body (or what it calls) can delete or hide a command
        if base in st.funcs and base not in st.active:
            body = st.funcs[base]
            _budget["funcs"] += 1
            if _budget["funcs"] > MAX_FUNC_EXPANSIONS:
                raise _BudgetExhausted()  # function expansions can grow exponentially
            st.active.add(base)
            try:
                pos = [expand(x, env, st) for x in w[1:]]
                analyse(body, st.child(body, positional=pos), depth)
            finally:
                st.active.discard(base)
            return None
        if base in SHELLS:
            has_c = False
            w = shnorm(w)
            for k, x in enumerate(w[1:], 1):
                if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", x) and k + 1 < len(w):
                    has_c = True
                    # `su -`, `su -l`, `su --login` start the string in the target user's home, not here
                    login = base == "su" and any(a in ("-", "-l", "--login") for a in w[1:k])
                    saved_cwd = st.cwd
                    if login:
                        st.cwd = UV
                    try:
                        run_string(w[k + 1], env, [a for a in w[k + 2:] if a != "--"] or None)
                    finally:
                        st.cwd = saved_cwd
                    break
            if not has_c and base in STDIN_SHELLS and all(x.startswith("-") for x in w[1:]):
                for s in herestrings(seg_text):
                    run_string(s, env)
                if sep in ("|", "|&"):
                    if prev and prev[0] == "lit":
                        raw = [prev[2]] if len(prev) > 2 and prev[2] else []
                        for s in [unph(" ".join(prev[1]))] + [unph(x) for x in prev[1]] + raw:
                            analyse(s, st.child(s), depth + 1)
                    elif not (prev and prev[0] == "heredoc"):
                        st.add("U", "code is piped into a shell from a source the guard cannot read — it could contain a destructive command")
        elif base == "eval":
            run_string(" ".join(w[1:]), env, adopt=True)
        elif base == "trap" and len(w) > 1 and not w[1].startswith("-"):
            run_string(w[1], env)
            if _CD_WORD_RE.search(w[1]):
                st.cwd = UV  # a trap body (DEBUG/ERR/RETURN/EXIT) runs in this shell and can move it (review round 5 M-2)
        elif INTERP_RE.fullmatch(base):
            # round 7: inline interpreter code (`python3 -c`, `perl -e`, `node -e`, `ruby -e`) that deletes a
            # tree. A literal protected argument is judged like `rm -rf <it>`; a computed argument is class V.
            # Script FILES run by an interpreter are not scanned (documented limit).
            for k, x in enumerate(w[1:], 1):
                if re.fullmatch(r"-[A-Za-z]*[ceE][A-Za-z]*|--eval|--command|-r", x) and k + 1 < len(w):
                    code = expand(w[k + 1], env, st)
                    for m in INTERP_DELETE_RE.finditer(code):
                        arg = m.group(1).strip()
                        lit = re.fullmatch(r"""(['"])([^'"]*)\1""", arg)
                        if lit:
                            st.check_target("rm -r", lit.group(2), env, None, False)
                        else:
                            st.add("V", "inline %s code deletes a tree whose path (%s) is computed at run time — the guard cannot know it; delete a literal, guarded path instead" % (base, arg[:60]))
                    break
        pipe = prev if sep in ("|", "|&") else None
        if base == "xargs":
            xargs_shell(w, pipe, env)
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
            raw_items = [x for x in w[1:] if not (x.startswith("-") and base == "echo")]
            vals = [expand(tilde(x, st.cwd), env, st) for x in w[1:]]
            text = None
            if not any(strongest(v) for v in vals):
                text = lit_output(base, vals)
            if text is None:
                return ("lit", raw_items, None)
            items = [x for x in re.split(r"[\s\0]+", text) if x]
            items += [x for x in raw_items if x not in items]
            return ("lit", items, text)
        if base == "cat" and "<<" in seg_text:
            return ("heredoc", None)
        return ("other", None)

    scope, prev = [], None
    for seg_i, (seg_text, sep) in enumerate(segs):
        stripped = strip_quoted(seg_text).strip()
        lead = 0 if stripped.startswith("((") else len(stripped) - len(stripped.lstrip("("))
        for _ in range(lead):
            scope.append((st.cwd, dict(st.env)))
        # every element of a pipeline runs in a SUBSHELL: a `cd` there does not move the shell that follows it
        # (fix round 5, M-1). The cwd the element started with is put back.
        in_pipe = sep in ("|", "|&") or (seg_i + 1 < len(segs) and segs[seg_i + 1][1] in ("|", "|&"))
        cwd_before = st.cwd
        prev = handle(seg_text, sep, prev)
        if in_pipe:
            st.cwd = cwd_before
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
                analyse(inner, st.child(inner), depth)
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
            dest = heredoc_dest(seg_text, head)
            if scriptish(dest, body):
                code = script_text(dest, body, extless_is_script=True)
                code = body if code is None else code
                analyse(code, st.child(code, fresh=True), depth + 1)
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


SHEBANG_SHELL_RE = re.compile(r"\s*#!.*\b(ba|z|da|k)?sh\b")


def file_kind(path, body, head="", extless_is_script=False):
    """ONE rule set for 'is this file code a shell/build tool will run' (used for Write/Edit/MultiEdit content
    and for heredoc destinations). Returns shell|make|just|yaml|docker, or None for data.
    `head` is the existing on-disk start of the file (Edit/MultiEdit); `extless_is_script` is the fail-closed
    reading used when the destination is only a name in a command and the content is unknown."""
    path = path or ""
    low = os.path.basename(path).lower()
    ext = os.path.splitext(low)[1]
    if ext in (".sh", ".bash", ".zsh", ".ksh") or SHEBANG_SHELL_RE.match(body) or (head and SHEBANG_SHELL_RE.match(head)):
        return "shell"
    if low in ("makefile", "gnumakefile") or ext == ".mk":
        return "make"
    if low == "justfile":
        return "just"
    if low == ".gitlab-ci.yml" or re.search(r"(^|/)\.github/workflows/[^/]+\.ya?ml$", path):
        return "yaml"
    if re.match(r"(dockerfile|containerfile)(\..+)?$", low) or re.search(r"\.(dockerfile|containerfile)$", low):
        return "docker"
    if extless_is_script and (not path or "$" in path or ext == ""):
        return "shell"
    return None


def scriptish(dest, body):
    return body.startswith("#!") or file_kind(dest, body, extless_is_script=True) is not None


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


def script_text(path, body, head="", extless_is_script=False):
    """The part of a written file that a shell would execute, or None when the file is data."""
    kind = file_kind(path, body, head, extless_is_script)
    if kind == "shell":
        return body
    if kind == "make":
        return make_lines(body)
    if kind == "just":
        return make_lines(body, just=True)
    if kind == "yaml":
        return yaml_lines(body)
    if kind == "docker":
        return "\n".join(re.sub(r"^\s*RUN\s+", "", l) for l in body.split("\n") if re.match(r"\s*RUN\s", l))
    return None


def disk_head(path, n=512):
    """First bytes of an existing file (for the shebang of a file being edited), "" when unreadable."""
    try:
        with open(path, "rb") as fh:
            return fh.read(n).decode("utf-8", "replace")
    except (OSError, ValueError):
        return ""


def early_marker(text):
    """The marker on line 1, or on line 2 when line 1 is a shebang; None otherwise."""
    lines = text.split("\n", 2)
    for k, line in enumerate(lines[:2]):
        if k == 0 and line.startswith("#!"):
            continue
        m = MARKER_RE.match(line.strip())
        return m.group(1).strip() if m else None
    return None


def run(payload):
    _start_budget()
    _FRAMES[0] = 0
    _ARITH_WORK[0] = 0
    _balanced_subst_cached.cache_clear()  # its results depend on the per-run arith budget
    tool = payload.get("tool_name", "")
    ti = payload.get("tool_input", {}) or {}
    texts = []
    if tool == "Bash":
        cmd = ti.get("command", "")
        if not isinstance(cmd, str):
            print("guardrails: BLOCKED — §11.4.287 class X: the command is not a string (%s), so it cannot be inspected (fail closed)" % type(cmd).__name__, file=sys.stderr)
            return 2
        texts.append(cmd)
    elif tool in ("Write", "Edit", "MultiEdit"):
        path = ti.get("file_path", "") or ""
        body = ti.get("content") or ti.get("new_string") or ""
        if tool == "MultiEdit":
            body = "\n".join(str(e.get("new_string", "")) for e in ti.get("edits", []) or [])
        if not isinstance(body, str):
            print("guardrails: BLOCKED — §11.4.287 class X: the content is not a string (%s), so it cannot be inspected (fail closed)" % type(body).__name__, file=sys.stderr)
            return 2
        head = ""
        if tool in ("Edit", "MultiEdit"):
            head = disk_head(path)
            if not head:  # file unreadable: the text being replaced is the best available context
                olds = [str(e.get("old_string", "")) for e in ti.get("edits", []) or []] if tool == "MultiEdit" else [str(ti.get("old_string", ""))]
                head = next((o for o in olds if SHEBANG_SHELL_RE.match(o)), "")
        text = script_text(path, body, head)
        if text is not None:
            texts.append(text)
    findings, markers = [], []
    pcwd = payload.get("cwd")
    start_cwd = None
    if tool == "Bash" and isinstance(pcwd, str) and pcwd.startswith("/") and "\0" not in pcwd:
        # the hook payload's cwd is where a Bash command really runs: relative targets (`./*`, `.`,
        # `..`, `Projects`) are judged against it. A Write/Edit script body runs elsewhere (cwd unknown).
        start_cwd = posixpath.normpath(pcwd)
    _SCRIPT_TEXT[0] = "\n".join(texts)
    for t in texts:
        st = State(t, findings=findings, markers=markers, cwd=start_cwd)
        try:
            analyse(t, st)
        except _BudgetExhausted:
            _budget["hit"] = True
            fallback_scan(t, State(t, findings=findings, markers=[]),
                          "the analysis budget ran out (%d characters of work, %d function expansions, or the %gs clock)" % (MAX_WORK_CHARS, MAX_FUNC_EXPANSIONS, _budget["secs"]))
        except Exception as exc:  # an analysis bug must never allow an uninspected command
            findings.append(("X", "internal failure in the guard (%s: %s) — the command was not fully inspected; blocked (fail closed)" % (type(exc).__name__, exc)))
            fallback_scan(t, State(t, findings=findings, markers=[]), "the full analysis failed")
    if not findings:
        return 0
    if _budget["hit"]:
        # under budget exhaustion only a marker the guard is guaranteed to have read counts
        markers = [m for m in (early_marker(t) for t in texts) if m]
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


_RAW_FIELD_RE = re.compile(r'"(command|content|new_string)"\s*:\s*"((?:[^"\\]|\\.)*)', re.S)


def raw_candidates(raw):
    """Texts to inspect when the payload is not valid JSON (truncated, mangled): every `command` / `content` /
    `new_string` string value found by a tolerant scan (an unterminated last value included), JSON-unescaped
    as far as it parses, plus the raw text itself."""
    out = []
    for m in _RAW_FIELD_RE.finditer(raw):
        val = m.group(2)
        try:
            val = json.loads('"' + val + '"')
        except Exception:
            val = val.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
        out.append((m.group(1), val))
    return out


def raw_scan(raw):
    """Unparsable payload: the guard still cannot know the intent (allow-by-default, §11.4.201(4) tension,
    documented), but a destructive command visible in the raw text is blocked with the same analysis a
    well-formed payload gets. Returns 2 on a block, 0 otherwise."""
    cands = [("command", v) if k == "command" else ("content", v) for k, v in raw_candidates(raw)]
    cands.append(("command", raw))
    for kind, text in cands:
        if not text.strip():
            continue
        payload = {"tool_name": "Bash", "tool_input": {"command": text}}
        try:
            if run(payload) == 2:
                return 2
        except Exception:
            return 2
    return 0


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except Exception:
        if raw_scan(raw) == 2:
            print("guard-destructive-paths: BLOCKED — the payload is not valid JSON, but a destructive command is visible in its raw text (§11.4.287; unparsable input is otherwise allowed because the guard cannot know the intent)", file=sys.stderr)
            return 2
        print("guard-destructive-paths: WARNING — unparsable payload, allowing (cannot inspect)", file=sys.stderr)
        return 0
    try:
        return run(payload)
    except Exception as exc:  # fail closed: an uninspected command is never allowed
        print("guard-destructive-paths: ERROR — internal failure (%s: %s); BLOCKED, the command could not be inspected (fail closed)" % (type(exc).__name__, exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
