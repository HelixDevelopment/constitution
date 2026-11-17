#!/usr/bin/env python3
"""tests/release/channel_census.py — channel census of the release scripts (round 6, structural; round 12 parser;
round 13 byte pin and positive-shape analyser).

Every external command a release script runs is one row of tests/release/channels.tsv, with the channels
through which data reaches it (argv, environment, stdin), the files it writes and its time bound. This tool
finds the invocations in the scripts and checks the table against them.

Usage:
  channel_census.py list SCRIPT...          print one line per invocation: script, line, command, key
  channel_census.py lint TABLE SCRIPT...    check the table; exit 0 clean, 1 findings, 2 blind or bad table
  channel_census.py commands TABLE          print the command names of the table (for runtime recorders)
  channel_census.py netgate --pin PIN [--sites] [--analyser-only] SCRIPT...
                                            the network-spawn gate (see the netgate section below): the byte pin
                                            PIN (tests/release/netgate_pin.tsv) and the positive-shape analyser;
                                            --analyser-only skips the byte comparison (for fixtures and mutated
                                            copies; the name list and the awk and sed programs of PIN still
                                            apply); --sites prints one SITE line per invocation first (script,
                                            line, program, wrapper or -, class); exit 0 clean, 1 findings, 2 blind
                                            or usage (netgate without --pin is a usage error)
  channel_census.py pin-regen PIN SCRIPT... write PIN for the scripts; refused (exit 1, nothing written) while the
                                            analyser has a finding or a name of DANGER_NAMES other than IFS is
                                            written; the result does not depend on the argument order
  channel_census.py pin-diff PIN SCRIPT...  the rows PIN would lose (-) and gain (+): line keys, sites, programs
                                            and names, never script text; exit 0 equal, 1 different, 2 blind

How invocations are found (a static instrument; its limits are stated in the threat model and in the netgate
section below). Round 12: from the parser of the network-spawn gate (class Parser, class Gate), with no lookup on the
checking host, so the result is the same on every host and with an empty PATH (§11.4.50). Rounds 6 to 11 used a
regular expression and kept only the words that shutil.which() found on the host; the round-11 review showed that
this dropped every program absent on the checking host (F1). The parser finds the same 128 invocations of the
release scripts, with the same lines, keys and wrappers (docs/qa/con227_234_2026_11_11/round12/parity.txt; round 13
keeps them, docs/qa/con227_234_2026_11_11/round13/README.md):
  * every simple command, also inside a command or process substitution, a here-document, a trap string, a
    compound command or a function body, is read with its quotes, escapes, redirections and assignments;
  * a call of a function of the scripts is not an invocation (its body is read like any other code); a call of a
    function of the helper library (a name starting with rc_ or _rc_) is not an invocation either;
  * a wrapper function (rc_net, nt, net) is followed into its argument: "nt gh api" is the command gh, "net
    ls-remote" is git. The wrappers themselves are rows too (timeout inside nt, git inside net).
  * an exec with a command word ("exec -c -a NAME "$BASH" ...", round 7) is an invocation of that command; round
    13: also when the gate refuses it (not on ALLOW_EXEC), with the class FINDING;
  * the key is the script name, the command and the first 8 hex digits of sha256 of the whitespace-
    normalised line, so a row goes stale when its line changes.
  * a script the parser cannot read is a lint finding (never a short census).

Lint findings: an invocation with no row; a row whose invocation is gone; a value outside the closed
vocabulary; a secret channel on any row but the two allowed ones; a line that names a secret variable
(_rpg_tok, TOKEN_VAR, M3W_GITEA_TOKEN; since B-M2 also _tar_reads, gtv and ${!tv} of the tag script) that is neither an allowed secret row nor listed as a secret-ref row;
a parse error.
"""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
import bisect
import hashlib
import os
import re
import sys
from typing import Any

SECRET = re.compile(r'_rpg_tok|TOKEN_VAR|M3W_GITEA_TOKEN|_tar_reads|\bgtv\b|\$\{!tv')   # B-M2: the tag script's token variable of a gitea spec (gtv, ${!tv}, the READS prescan)
COLS = ["script", "command", "key", "argv", "env", "stdin", "files", "bound", "note"]
VOCAB = {
    "argv": {"fixed", "validated-data", "url-validated", "caller-path", "own-argv"},
    "env": {"allowlist", "net-allowlist", "allowlist+token", "empty"},
    "stdin": {"none", "pipe-local", "pipe-network-text", "token-config", "file-local", "state-pipe"},
    "files": {"none", "rundir", "repo-refs", "repo-tags", "temp-create", "temp-remove"},
    "bound": {"local", "nt-timeout", "curl-m60", "publisher"},
}
# the only two rows allowed to carry the token, and the channel each may use
# (round 7: the re-execution of rc_env_clean carries the token variable on its fd 9 state pipe, never in an argv or
# in its environment, which is empty)
ALLOWED_SECRET = {("release_publish_gitea.sh", "curl"): ("stdin", "token-config"),
                  ("tag_and_release.sh", "bash"): ("env", "allowlist+token"),
                  ("redact_cut.sh", "bash"): ("stdin", "state-pipe")}


def invocations(path):
    return [(a, i, c, k, norm) for a, i, c, k, norm, _ in scan(path)]


def scan(path):
    """invocations with the wrapper each was reached through: (script, line, command, key, line text, via);
    via is "rc_net", "nt", "net", "exec" or "" (a plain command position).

    Round 12 (F1 of the round-11 review): read from the parser of the network-spawn gate (class Gate below), with no
    lookup on the checking host: the census of round 6 to 11 found command words with a regular expression and kept
    only the words shutil.which() found on the host. The parser finds the same 128 invocations of the release
    scripts, with the same lines, keys and wrappers, alone and together (docs/qa/con227_234_2026_11_11/round12,
    parity.txt), and it finds every program, also one absent on the host. A call of a function of the helper
    library (a name starting with rc_ or _rc_) that is not analysed here is a call, not an invocation, as before."""
    g = Gate([path]).run()
    base = os.path.basename(path)   # round 13: the library a script sources is read with it; its sites are its own
    out = [(n, l, p, hashlib.sha256(norm.encode()).hexdigest()[:8], norm, via)
           for n, l, p, via, _cls, norm in g.sites if n == base and not p.startswith(("rc_", "_rc_"))]
    return sorted(out, key=lambda x: x[1])


def parse_errors(path):
    return [f for f in Gate([path]).findings if f.startswith("parse error")]


def secret_lines(path):
    name = path.rsplit("/", 1)[-1]
    out = []
    for i, l in enumerate(open(path).read().split("\n"), 1):
        t = l.strip()
        if not t or t.startswith("#"):
            continue
        if SECRET.search(blank_comments(l)):
            norm = " ".join(l.split())
            out.append((name, i, hashlib.sha256(norm.encode()).hexdigest()[:8], norm))
    return out


def blank_comments(l):
    return re.sub(r'(^|\s)#\s.*$', r'\1', l)


def read_table(path):
    rows, bad = [], []
    for n, l in enumerate(open(path).read().split("\n"), 1):
        if not l.strip() or l.startswith("#"):
            continue
        f = l.split("\t")
        if len(f) != len(COLS):
            bad.append("table line %d: %d fields, want %d" % (n, len(f), len(COLS)))
            continue
        rows.append(dict(zip(COLS, f), _line=n))
    return rows, bad


def lint(table, scripts):
    rows, findings = read_table(table)
    if not rows:
        print("BLIND: the table has no rows")
        return 2
    inv = []
    for s in scripts:
        inv += invocations(s)
    if not inv:
        print("BLIND: no invocation found in the scripts")
        return 2
    for s in scripts:
        findings += parse_errors(s)   # round 12: a script the parser cannot read is a finding, never a short census
    netvia = {}
    for s in scripts:
        for a, i, c, k, norm, via in scan(s):
            netvia.setdefault((a, c, k), set()).add(via)
    have = {(r["script"], r["command"], r["key"]) for r in rows if r["command"] != "-"}
    found = {(a, c, k) for a, _, c, k, _ in inv}
    for a, i, c, k, _norm in inv:
        if (a, c, k) not in have:
            findings.append("no row: %s:%d %s key=%s" % (a, i, c, k))   # round 13, O2: the key, never the text
    for r in rows:
        if r["command"] == "-":
            continue
        if (r["script"], r["command"], r["key"]) not in found:
            findings.append("stale row (table line %d): %s %s key=%s" % (r["_line"], r["script"], r["command"], r["key"]))
        for col, vals in VOCAB.items():
            if r[col] not in vals:
                findings.append("table line %d: %s=%r is not in the vocabulary" % (r["_line"], col, r[col]))
        # round 11: env 'net-allowlist' exactly on the rows whose command is reached through rc_net (or nt/net)
        vias = netvia.get((r["script"], r["command"], r["key"]), set())
        if vias and (r["env"] == "net-allowlist") != (vias <= {"rc_net", "nt", "net"}):
            findings.append("table line %d: env=%s but the command is reached via %s" % (r["_line"], r["env"], ",".join(sorted(v or "-" for v in vias))))
        allowed = ALLOWED_SECRET.get((r["script"], r["command"]))
        for col, sv in (("stdin", "token-config"), ("env", "allowlist+token"), ("stdin", "state-pipe")):
            if r[col] == sv and allowed != (col, sv):
                findings.append("table line %d: secret channel %s=%s on a row that may not carry the token" % (r["_line"], col, sv))
    for s in scripts:
        lines = open(s).read().split("\n")
        # round 7: the first command after loading the helper is rc_env_clean (the positive environment)
        lock = next((i for i, l in enumerate(lines, 1) if re.match(r"rc_env_clean\s", l)), None)
        if lock is None and any(l.strip().startswith(". ") and "redact_cut.sh" in l for l in lines):
            findings.append("%s loads redact_cut.sh but never calls rc_env_clean" % s.rsplit("/", 1)[-1])
        if lock is not None:
            for a, i, c, k, norm in invocations(s):
                if i < lock:
                    findings.append("external command before rc_env_clean: %s:%d %s (it gets the caller's whole environment)" % (a, i, c))
    secret_refs = {(r["script"], r["key"]) for r in rows if r["command"] == "-"}
    secret_rows = {(r["script"], r["key"]) for r in rows
                   if (r["script"], r["command"]) in ALLOWED_SECRET and
                   r[ALLOWED_SECRET[(r["script"], r["command"])][0]] == ALLOWED_SECRET[(r["script"], r["command"])][1]}
    for s in scripts:
        for a, i, k, _norm in secret_lines(s):
            if (a, k) not in secret_refs and (a, k) not in secret_rows:
                # round 13, O2 of the round-12 review: the key, never the text of a line that names a secret
                findings.append("secret reference with no secret-ref or allowed row: %s:%d key=%s" % (a, i, k))
    for f in findings:
        print("FINDING " + f)
    print("CENSUS invocations=%d rows=%d secret_lines=%d findings=%d" %
          (len(inv), sum(1 for r in rows if r["command"] != "-"), sum(len(secret_lines(s)) for s in scripts), len(findings)))
    return 1 if findings else 0


# ---- the network-spawn gate (netgate), round 13: a byte pin and a positive-shape analyser ----
# Goal: no release script starts a network program outside rc_net (whose environment is the fixed network
# allow-list), and no credential reaches a program by another channel. Rounds 11 (regular expressions) and 12 (a parser
# with deny-lists) both failed review on the same class: a deny-list over an open language misses members (the round-12
# review, F1: 32 bypasses). Round 13 changes the structure (docs/qa/con227_234_2026_11_11/round13/README.md):
#   1. THE PIN (the release gate): tests/release/netgate_pin.tsv holds the sha256 of every release script, the sha256 of
#      every line, every invocation site with its class, the whitelisted awk and sed programs and the names the
#      scripts assign. "netgate --pin TABLE SCRIPT..." refuses any script, line, site, program or name that is not in
#      the table: a change to a release script is a finding until the table is regenerated, and the regeneration is a
#      reviewed act (pin-regen refuses while the analyser has a finding; pin-diff prints the line-key diff for the
#      reviewer, never the text). This layer is default-deny in the literal sense: the bytes that run are the bytes that
#      were reviewed. It proves nothing about those bytes; that is the analyser's and the reviewer's job.
#   2. THE ANALYSER (defence in depth, and the regeneration guard): a positive-shape reader. The parser refuses every
#      construct outside the closed feature set the release scripts use (class Parser, refuse()); the gate allows only
#      the command shapes the scripts use: a closed set of builtins, each with its own option grammar (Gate.builtin);
#      exact dynamic sites (DYN_SITES) and interpreter calls (ALLOW_EXEC) matched against the parsed words; a closed
#      set of local programs (awk and sed only with a whitelisted program hash, sort -V, sqlite3 with -safe first);
#      network programs only through rc_net or a computed wrapper; functions defined once at the top level before any
#      call that can reach them; every variable a script writes on the name list of the pin; arithmetic, parameter
#      expansion and [[ ]] in closed grammars. Anything else is a finding. It is not a proof: bash is larger than the
#      reader, and the residuals below are run-time data the reader cannot see.
#   3. THE RUNTIME LAYER (tests/release/test_channel_census.sh part 3): recorders for every program of the table, run
#      with the publisher; it sees only the paths a test executes. A network namespace (unshare -n) is not available
#      to an unprivileged user on the reference host (measured 2026-11-13: "unshare: write failed /proc/self/uid_map:
#      Operation not permitted"), so no layer here proves the absence of a connection at the kernel.
# Residuals (stated, §11.4.6): run-time values: an awk or sed operand or a sqlite3 argument that arrives as data (an
# expanded "-safe"-cancelling option or a /inet file name), the text of a variable evaluated in arithmetic when the
# value comes from data (A6 checks the static assignments only), the target of an expanded redirection, the values the
# dynamic sites assign; the caller's environment before rc_env_clean (PATH, CDPATH); a hand edit of the pin table that
# the reviewer does not see in pin-diff.
NETCMDS = {"git", "ssh", "scp", "sftp", "curl", "wget", "gh", "glab", "nc", "ncat", "netcat", "socat", "rsync",
           "telnet", "ftp", "lftp", "aria2c", "http", "https", "openssl", "gpg", "timeout"}
EXECWRAP = {"bash", "sh", "dash", "zsh", "ksh", "mksh", "busybox", "python", "python3", "perl", "ruby", "node",
            "env", "nice", "nohup", "setsid", "stdbuf", "xargs", "sudo", "doas", "chrt", "ionice", "taskset", "flock",
            "unshare", "nsenter", "script", "watch", "parallel", "find", "make", "expect", "su", "runuser", "systemd-run"}
# local programs that cannot start a process (none of them has an option or a program text that runs a command)
LOCAL_SIMPLE = {"cat", "chmod", "cp", "cut", "date", "grep", "jq", "mktemp", "rm", "rmdir", "sha256sum", "tr",
                "unlink", "wc"}
# local programs whose program text or options can start a process: allowed only in the shapes of LOCAL_PROG rules
LOCAL_PROG = {"awk", "sed", "sort", "sqlite3"}
LOCAL_OK = LOCAL_SIMPLE | LOCAL_PROG
# (script, via, words from the program word on): the only interpreter calls a release script makes, matched against
# the parsed words (round 13, R06/R07 of the round-12 review: round 12 matched a substring of the line)
ALLOW_EXEC = {("tag_and_release.sh", "rc_net", ("bash", "scripts/badges/compute_badges.sh", "--check")),
              ("tag_and_release.sh", "", ("bash", "scripts/release_publish_gitea.sh", "--token-var", '"$tv"', '"$@"')),   # B-M2
              ("redact_cut.sh", "exec", ('"$BASH"', '"$0"', '"$@"'))}
# (script, function, raw words): the only commands that run a command named by an expansion or write a name read at
# run time: rc_net's builtin exec "$@" (its own arguments) and its environment census; the lockdown's export -n;
# rc_git_env's unset -v; _rc_env_closefds's eval "exec $n<&-" ($n matched ^[0-9]+$); _rc_env_restore's printf -v
# and export (n matched ^[A-Za-z_][A-Za-z0-9_]{0,63}$ and not _rc_env_reserved); the publisher's unset of the token
# variable (TOKEN_VAR matched ^[A-Z_][A-Z0-9_]*$); the tag script's pub export of the spec's token variable (B-M2)
DYN_SITES = {("redact_cut.sh", "rc_net", ("builtin", "exec", '"$@"')),
             ("redact_cut.sh", "rc_net", ("builtin", "export", "-n", '"$_rc_v"')),
             ("redact_cut.sh", "rc_net", ("builtin", "export", "-n", "-f", '"$_rc_v"')),
             ("redact_cut.sh", "rc_env_lockdown", ("export", "-n", '"$v"')),
             ("redact_cut.sh", "rc_env_lockdown", ("export", "-n", "-f", '"$v"')),
             ("redact_cut.sh", "rc_git_env", ("unset", "-v", '"$v"')),
             ("redact_cut.sh", "_rc_env_closefds", ("eval", '"exec $n<&-"')),
             ("redact_cut.sh", "_rc_env_restore", ("printf", "-v", '"$n"', "'%s'", '"$val"')),
             ("redact_cut.sh", "_rc_env_restore", ("export", '"${n?}"')),
             ("release_publish_gitea.sh", "", ("unset", "-v", '"$TOKEN_VAR"')),
             ("tag_and_release.sh", "pub", ("export", '"${tv?}"'))}   # B-M2: the gitea spec's token variable (matched RE_GT's [A-Z][A-Z0-9_]{0,63})
# (script, name): the names an indirect expansion ${!name} may read (each validated as a variable name before use)
INDIRECT_OK = {("redact_cut.sh", "_rc_v"), ("redact_cut.sh", "v"), ("release_publish_gitea.sh", "TOKEN_VAR")}
# (script, raw source word, the analysed script it loads): the only source commands (round 13, R22: round 12 accepted
# any path whose base name was an analysed script)
SOURCE_OK = {("derive_release_facts.sh", '"$(cd "$_rc_d" && pwd)/redact_cut.sh"', "redact_cut.sh"),
             ("tag_and_release.sh", '"$(cd "$_rc_d" && pwd)/redact_cut.sh"', "redact_cut.sh"),
             ("release_publish_gitea.sh", '"$(cd "$_rc_d" && pwd)/release/redact_cut.sh"', "redact_cut.sh")}
TRUST_CAND = ("nt", "net")
# what a trusted wrapper runs: None = its first argument (nt), a name = that program with the call's arguments (net)
GATE_WRAPPERS = {"nt": None, "net": "git"}
# every bash 5.3 builtin (compgen -b): a name here is never looked up as a program
BASH_BUILTINS = {".", ":", "[", "alias", "bg", "bind", "break", "builtin", "caller", "cd", "command", "compgen",
                 "complete", "compopt", "continue", "declare", "dirs", "disown", "echo", "enable", "eval", "exec",
                 "exit", "export", "false", "fc", "fg", "getopts", "hash", "help", "history", "jobs", "kill", "let",
                 "local", "logout", "mapfile", "popd", "printf", "pushd", "pwd", "read", "readarray", "readonly",
                 "return", "set", "shift", "shopt", "source", "suspend", "test", "times", "trap", "true", "type",
                 "typeset", "ulimit", "umask", "unalias", "unset", "wait"}
BUILTINS = BASH_BUILTINS
# the closed set of builtins the release scripts use; every other builtin is refused (round 13, K3: round 12 let 29
# builtins pass with any option, jobs -x and wait -p among them)
BUILTIN_ALLOWED = {".", ":", "[", "builtin", "cd", "command", "compgen", "continue", "declare", "echo", "eval",
                   "exec", "exit", "export", "local", "printf", "pwd", "read", "return", "set", "shift", "shopt",
                   "trap", "true", "unset"}
# names whose value changes how bash finds or runs a command, or what a child loads before main(); the pin's name list
# may not hold one (pin-regen refuses), so an assignment to one is refused twice
DANGER_NAMES = {"PATH", "EXECIGNORE", "BASH_ENV", "ENV", "PS0", "PS1", "PS2", "PS4", "PROMPT_COMMAND", "SHELLOPTS",
                "BASHOPTS", "BASH_LOADABLES_PATH", "BASH_CMDS", "BASH_ALIASES", "GCONV_PATH", "CDPATH", "BASH_COMPAT",
                "POSIXLY_CORRECT", "BASH_XTRACEFD", "BASH_ARGV0", "BASH_ARGV", "BASH_ARGC", "FUNCNEST", "GLOBIGNORE",
                "HOME", "TMPDIR", "HISTFILE", "INPUTRC", "MAILPATH", "TIMEFORMAT", "BASH_SOURCE", "BASH_LINENO",
                "FUNCNAME", "BASH_REMATCH", "COMP_WORDBREAKS", "OPTIND", "OPTARG", "IFS"}
# (script, function, name): the names read in arithmetic whose value is read at run time (A6); each is checked by the
# script before it is used (the reason is in docs/qa/con227_234_2026_11_11/round13/class_inventory.md, A6)
A6_DATA = {("redact_cut.sh", "_rc_env_closefds", "fl"),   # matched ^[0-7]{1,11}$ just before the arithmetic
           ("derive_release_facts.sh", "grp", "n")}      # the read loop is the last element of a pipeline: a subshell
# IFS is on the name list of the scripts, with these static values only (a separator for read, or the default)
IFS_VALUES = {"", "\x1e", "\x1f", " \t\n"}
REDIR_OK = {">", ">>", "<", ">&", "<&", "<<<"}
REDIR_FDS = {None, "1", "2", "3", "4", "9"}
PARAM_OPS = {"", ":-", "-", ":?", "?", "+", "#", "##", "%", "%%", ",,", "^^", ":"}
INDIRECT_OPS = {"", "-", "+", ":-"}
COND_UNARY = {"-n", "-z"}
COND_BINARY = {"==", "=", "!=", "=~"}
SET_ARGS = {"+x", "-u", "-f", "+f"}
TRAP_SIGNALS = {"EXIT", "HUP", "INT", "TERM"}
TEST_OPS = {"-eq", "-ne", "-gt", "-ge", "-lt", "-le", "-n", "-z", "-f", "-d", "-s", "-e", "-r", "-S", "=", "!=", "!"}
SQLITE_OPTS = {"-readonly", "-batch", "-noheader", "-ascii", "-bail"}
BASH_WORDS = ('"$BASH"', "$BASH", '"${BASH}"', "${BASH}")
RESERVED = {"if", "then", "else", "elif", "fi", "do", "done", "case", "esac", "while", "until", "for", "in",
            "select", "function", "time", "{", "}", "!", "[[", "]]", "coproc"}
METACH = " \t\n;&|()<>"
NAME_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*\Z')
FUNC_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*\Z')
# a command word the gate classifies: [ : . or a name of letters, digits, _ . + - (no quote, escape, expansion, glob,
# brace, tilde or path character: bash would expand or look such a word up in a way the gate does not follow)
CMDNAME_RE = re.compile(r'(\[|:|\.|[A-Za-z0-9_][A-Za-z0-9_.+-]*)\Z')
SUBST_RE = re.compile(r'\$\(|`')
ASSIGN_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=')
FDVAR_RE = re.compile(r'\{[A-Za-z_][A-Za-z0-9_]*\}\Z')
PEEK_RE = re.compile(r'[^\s;&|()<>\'"\\$`]+')
REDIR_OPS = ("&>>", "&>", "<<<", "<<-", "<<", "<>", "<&", ">&", ">>", ">|", "<", ">")
DIGITS = "0123456789"
LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
# the arithmetic grammar (round 13, A6): numbers (also N#digits and N#$name), names, $name, ${name}, and operators
# without assignment: no =, +=, <<=, ++, --, no subscript, no quote, no $( )
ARITH_TOK = re.compile(r'[ \t\n]+|[0-9]+#(?:[0-9A-Za-z@_]+|\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})'
                       r'|[0-9]+|\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*'
                       r'|&&|\|\||<=|>=|==|!=|[-+*/%&|^<>!~()?:,]')


def arith_check(text):
    """(why or None, names read) for an arithmetic text in the closed grammar"""
    names, i, prev = [], 0, ""
    while i < len(text):
        m = ARITH_TOK.match(text, i)
        if not m:
            return "the character %r (an assignment, a subscript, a quote or a substitution)" % text[i], names
        tok = m.group()
        if tok in ("+", "-") and prev == tok:
            return "%s%s (an increment assigns)" % (tok, tok), names
        if tok in ("<", ">") and text[m.end():m.end() + 1] == tok:
            return "%s%s (a shift; <<= and >>= assign)" % (tok, tok), names
        if tok[:1] in LETTERS or "$" in tok:   # a name, $name, ${name} or N#$name: its value is evaluated
            nm = re.search(r'[A-Za-z_][A-Za-z0-9_]*(?=\}?\Z)', tok)
            if nm is None:   # round 13: a name the grammar cannot read is refused (fail closed)
                return "a name the gate cannot read: %s" % tok[:20], names
            names.append(nm.group())
        prev = tok
        i = m.end()
    return None, names


def param_check(inner, script):
    """(why or None, array name or None, subscript texts, substring offset texts) for the inside of ${...}"""
    s = inner
    bang = s.startswith("!")
    if bang:
        s = s[1:]
    length = len(s) > 1 and s.startswith("#")
    if length:
        s = s[1:]
    m = re.match(r'[A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-]', s)
    if not m:
        return "a parameter the analyser cannot read", None, [], []
    name, rest = m.group(), s[m.end():]
    subs, offs, arr = [], [], None
    if rest.startswith("["):
        d, e = 1, 1
        while e < len(rest) and d:
            d += {"[": 1, "]": -1}.get(rest[e], 0)
            e += 1
        if d:
            return "an unterminated subscript", None, [], []
        sub, rest = rest[1:e - 1], rest[e:]
        if sub not in ("@", "*"):
            subs.append(sub)
            arr = name
    if length:
        return (("an operator after ${#...}" if rest else None), arr, subs, offs)
    op = None
    for o in (":-", ":=", ":?", ":+", "##", "%%", "//", "/#", "/%", ",,", "^^", "-", "=", "?", "+", "#", "%", "/",
              ",", "^", "@", ":"):
        if rest.startswith(o):
            op = o
            break
    if op is None:
        if rest:
            return "an operator the analyser does not know", arr, subs, offs
        op = ""
    if bang:
        if (script, name) not in INDIRECT_OK or subs:
            return "an indirect expansion of %s (only the validated names of INDIRECT_OK)" % name, arr, subs, offs
        if op not in INDIRECT_OPS:
            return "the operator %s on an indirect expansion" % op, arr, subs, offs
        return None, arr, subs, offs
    if op not in PARAM_OPS:
        return "the operator %s (:= and = assign; @, / and the others are not on the list)" % op, arr, subs, offs
    if op in (",,", "^^") and rest != op:
        return "a pattern after %s" % op, arr, subs, offs
    if op == ":":
        offs.extend(rest[1:].split(":"))
    return None, arr, subs, offs


def cond_check(toks):
    """why a [[ ]] token list is outside the closed grammar, or None (expr := term (&& term | || term)*;
    term := ! term | ( expr ) | UNARY word | word BINARY word | word =~ regex | word)"""
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def isword(p, vals=None):
        return p is not None and p[0] == "w" and (vals is None or (p[1].lit and p[1].sval in vals))

    def primary():
        p = peek()
        if p is None or not isword(p):
            return "an operand was expected"
        pos[0] += 1
        w = p[1]
        q = peek()
        if w.lit and w.sval in COND_UNARY and q is not None and isword(q):
            pos[0] += 1
            return None
        if w.lit and re.match(r'-[A-Za-z]+\Z', w.sval) and not isword(q, COND_BINARY):
            return "the operator %s" % w.sval
        if q is not None and isword(q, COND_BINARY):
            op = q[1].sval
            pos[0] += 1
            r = peek()
            if (op == "=~") != (r is not None and r[0] == "re") or (op != "=~" and not isword(r)):
                return "%s without a right operand" % op
            pos[0] += 1
            return None
        if q is not None and isword(q):
            return "the operator %s (an arithmetic or file comparison)" % (q[1].sval if q[1].lit else q[1].raw[:20])
        return None

    def term():
        p = peek()
        if p == ("op", "!"):
            pos[0] += 1
            return term()
        if p == ("op", "("):
            pos[0] += 1
            r = expr()
            if r:
                return r
            if peek() != ("op", ")"):
                return "a missing )"
            pos[0] += 1
            return None
        return primary()

    def expr():
        r = term()
        while r is None and peek() in (("op", "&&"), ("op", "||")):
            pos[0] += 1
            r = term()
        return r

    if not toks:
        return "an empty [[ ]]"
    r = expr()
    if r is None and pos[0] != len(toks):
        r = "an unexpected token"
    return r


class ParseError(Exception):
    pass


class Word(object):
    """one shell word: raw text; lit (plain unquoted characters only); sval (its value after quote removal, None
    when it holds an expansion); tail (the static text after its last expansion); dyn (holds an expansion)"""
    __slots__ = ("raw", "lit", "sval", "tail", "dyn", "line")


class Cmd(object):
    """one simple command (or the redirections of a compound command): assignments, words, redirections; stmt is
    the number of the top-level statement it runs in (round 13: the order of definitions and calls)"""
    __slots__ = ("line", "func", "assigns", "words", "redirs", "heredocs", "stmt", "cmpd", "depth")

    def __init__(self, line, func, stmt=0, depth=0):
        self.line, self.func, self.stmt, self.depth = line, func, stmt, depth
        self.assigns, self.words, self.redirs, self.heredocs = [], [], [], []
        self.cmpd = False


class Shared(object):
    """what the parser of a script and its child parsers (substitutions) record together"""
    __slots__ = ("cmds", "problems", "funcdefs", "stmt", "arith_names", "sub_names", "writes", "subs", "fdnames")

    def __init__(self):
        self.cmds, self.problems, self.funcdefs, self.stmt = [], [], [], 0
        # every variable the script writes that the parser sees (loop variables; the gate adds the others):
        # (line, func, name, how, value word or None)
        self.writes = []
        # (func, name) read in an arithmetic context, and $name used in a subscript (round 13, A6)
        self.arith_names, self.sub_names = set(), set()
        # (line, func, array, subscript text) of every ${array[subscript]}: arithmetic unless declare -A (the gate)
        self.subs = []
        # (line, func, name) of every >&"$name" or <&"$name": the name must hold a file descriptor number (the gate)
        self.fdnames = []


def is_danger(name):
    return name in DANGER_NAMES or name.startswith(("LD_", "GCONV_"))


class Parser(object):
    """A recursive-descent reader of the bash syntax the release scripts use. Every simple command (also inside a
    function, a compound command, a command substitution, a process substitution, a parameter or arithmetic
    expansion) is recorded in cmds with the line of its first word, the function it belongs to and the top-level
    statement it runs in. Round 13: a form outside the closed feature set of the release scripts is refused, never
    read past (a problem when the reader can step over it exactly, a ParseError when it cannot): the parser fails
    closed (docs/qa/con227_234_2026_11_11/round13/class_inventory.md, A1)."""

    def __init__(self, text, script, line0=1, func="", shared=None, depth=0):
        self.t, self.n, self.i = text, len(text), 0
        self.script, self.line0, self.func = script, line0, func
        self.nls = [k for k, c in enumerate(text) if c == "\n"]
        self.sh = Shared() if shared is None else shared
        self.cmds, self.problems, self.funcdefs = self.sh.cmds, self.sh.problems, self.sh.funcdefs
        self.heredocs = []
        self.depth = depth          # 0: the top level of the script (not in a compound, a function or a substitution)
        self.ps_ok_at = -1          # a process substitution is allowed only as the whole target of a redirection

    # -- positions --
    def line(self, i):
        return self.line0 + bisect.bisect_left(self.nls, i)

    def err(self, msg):
        raise ParseError("%s:%d: %s" % (self.script, self.line(self.i), msg))

    def problem(self, i, msg):
        self.problems.append((self.line(i), self.func, msg))

    def refuse(self, i, what):
        """a construct outside the closed feature set (round 13, A1): a finding, never read as something else"""
        self.problem(i, "unmodelled construct, refused: %s" % what)

    def sh_write(self, i, name, how, value=None):
        self.sh.writes.append((self.line(i), self.func, name, how, value))

    def child(self, text, pos):
        return Parser(text, self.script, self.line(pos), self.func, self.sh, self.depth + 1)

    def nest(self, fn, *a):
        self.depth += 1
        try:
            return fn(*a)
        finally:
            self.depth -= 1

    def parse_all(self):
        self.parse_list(set(), "")
        self.skip_ws_nl()
        if self.i < self.n:
            self.err("unexpected %r" % self.t[self.i])
        if self.heredocs:
            self.err("here-document without a body")

    # -- blanks, comments, newlines --
    def skip_blank(self):
        t, n = self.t, self.n
        while self.i < n:
            c = t[self.i]
            if c in " \t":
                self.i += 1
            elif c == "\\" and self.i + 1 < n and t[self.i + 1] == "\n":
                self.i += 2
            else:
                return

    def skip_comment(self):
        j = self.t.find("\n", self.i)
        self.i = self.n if j < 0 else j

    def skip_ws_nl(self):
        while True:
            self.skip_blank()
            if self.i < self.n and self.t[self.i] == "#":
                self.skip_comment()
            if self.i < self.n and self.t[self.i] == "\n":
                self.newline()
                continue
            return

    def newline(self):
        """consume a newline, then the bodies of the here-documents opened on that line"""
        self.i += 1
        pend, self.heredocs = self.heredocs, []
        for delim, strip, quoted, cmd in pend:
            start, body = self.i, []
            while True:
                if self.i >= self.n:
                    self.err("here-document %r ended by the end of the file" % delim)
                j = self.t.find("\n", self.i)
                j = self.n if j < 0 else j
                ln = self.t[self.i:j]
                self.i = min(j + 1, self.n)
                if (ln.lstrip("\t") if strip else ln) == delim:
                    break
                body.append(ln)
            text = "".join(x + "\n" for x in body)
            cmd.heredocs.append((text, quoted))
            if not quoted:
                c = self.child(text, start)
                c.read_dq(None)

    def peek_word(self):
        m = PEEK_RE.match(self.t, self.i)
        if not m:
            return None
        j = m.end()
        if j < self.n and self.t[j] not in METACH:
            return None
        return m.group()

    # -- lists, pipelines, commands --
    def parse_list(self, stop_words, stop_chars):
        t = self.t
        while True:
            self.skip_ws_nl()
            if self.i >= self.n:
                return
            c = t[self.i]
            if c in stop_chars:
                return
            if t.startswith(";;", self.i) or t.startswith(";&", self.i):
                return
            if c in ";)":
                self.err("unexpected %r" % c)
            if self.peek_word() in stop_words:
                return
            if self.depth == 0:
                self.sh.stmt += 1
            self.parse_andor()
            self.skip_blank()
            if self.i >= self.n:
                return
            c = t[self.i]
            if c == "#":
                self.skip_comment()
            elif c == "\n":
                self.newline()
            elif c == "&":
                self.refuse(self.i, "& (a background job runs past the statement that started it)")
                self.i += 1
            elif c == ";":
                if t.startswith(";;", self.i) or t.startswith(";&", self.i):
                    return
                self.i += 1
            elif c in stop_chars:
                return
            elif self.peek_word() in stop_words:
                return
            else:
                self.err("unexpected %r" % c)

    def parse_andor(self):
        self.parse_pipeline()
        while True:
            self.skip_blank()
            if self.t.startswith("&&", self.i) or self.t.startswith("||", self.i):
                self.i += 2
                self.skip_ws_nl()
                self.parse_pipeline()
            else:
                return

    def parse_pipeline(self):
        while True:
            self.skip_blank()
            w = self.peek_word()
            if w == "!":
                self.i += 1
                continue
            if w == "time":
                self.refuse(self.i, "the time keyword")
                self.i += 4
                self.skip_blank()
                if self.peek_word() == "-p":
                    self.i += 2
                continue
            break
        self.parse_command()
        while True:
            self.skip_blank()
            if self.t.startswith("||", self.i):
                return
            if self.t.startswith("|&", self.i):
                self.refuse(self.i, "|& (a pipe of standard error)")
                self.i += 2
            elif self.t.startswith("|", self.i):
                self.i += 1
            else:
                return
            self.skip_ws_nl()
            self.parse_command()

    def expect(self, kw):
        self.skip_ws_nl()
        if self.peek_word() != kw:
            self.err("expected %r" % kw)
        self.i += len(kw)

    def parse_command(self):
        self.skip_blank()
        if self.i >= self.n:
            self.err("a command was expected")
        t, i = self.t, self.i
        w = self.peek_word()
        if w == "function":
            self.refuse(i, "the function keyword (a definition is NAME() { ... } at the top level)")
        if w in ("until", "select", "coproc"):
            self.refuse(i, "%s" % w)
        if w in ("for", "select") and re.match(r'[a-z]+[ \t]*\(\(', t[i:i + 12]):
            self.refuse(i, "for (( ... )) (an arithmetic loop)")
        if w in ("if", "while", "until", "for", "select", "case", "{", "[[") or (i < self.n and t[i] == "("):
            self.depth += 1
            try:
                self.compound(w, i)
            finally:
                self.depth -= 1
        elif w == "function":
            self.compound(w, i)
            return
        elif w == "coproc":
            self.i += 6
            self.parse_command()
            return
        elif w in RESERVED and w not in ("!", "time"):
            self.err("unexpected reserved word %r" % w)
        else:
            self.simple()
            return
        cmd = Cmd(self.line(i), self.func, self.sh.stmt, self.depth)   # the redirections of a compound command
        cmd.cmpd = True
        while True:
            self.skip_blank()
            if self.at_redir():
                if not cmd.redirs:
                    self.cmds.append(cmd)
                self.redirect(cmd, None)
                continue
            m = re.match(r'[0-9]+(?=[<>])|\{[A-Za-z_][A-Za-z0-9_]*\}(?=[<>])', t[self.i:self.i + 40])
            if m and not t.startswith("(", self.i + m.end() + 1):
                if not cmd.redirs:
                    self.cmds.append(cmd)
                self.i += m.end()
                self.redirect(cmd, m.group())
                continue
            return

    def compound(self, w, i):
        t = self.t
        if w == "if":
            self.i += 2
            self.parse_list({"then"}, "")
            self.expect("then")
            self.parse_list({"elif", "else", "fi"}, "")
            while True:
                self.skip_ws_nl()
                k = self.peek_word()
                if k == "elif":
                    self.i += 4
                    self.parse_list({"then"}, "")
                    self.expect("then")
                    self.parse_list({"elif", "else", "fi"}, "")
                    continue
                if k == "else":
                    self.i += 4
                    self.parse_list({"fi"}, "")
                self.expect("fi")
                break
        elif w in ("while", "until"):
            self.i += len(w)
            self.parse_list({"do"}, "")
            self.expect("do")
            self.parse_list({"done"}, "")
            self.expect("done")
        elif w in ("for", "select"):
            self.i += len(w)
            self.skip_blank()
            if t.startswith("((", self.i):
                self.i += 2
                self.arith()
            else:
                v = self.read_word()
                if not (v.lit and NAME_RE.match(v.sval)):
                    self.err("a loop variable that is not a name")
                self.sh_write(i, v.sval, "for")
                self.skip_ws_nl()
                if self.peek_word() == "in":
                    self.i += 2
                    while True:
                        self.skip_blank()
                        if self.i >= self.n or t[self.i] in ";\n":
                            break
                        if t[self.i] == "#":
                            self.skip_comment()
                            continue
                        self.read_word()
            self.skip_blank()
            if self.i < self.n and t[self.i] == ";":
                self.i += 1
            self.expect("do")
            self.parse_list({"done"}, "")
            self.expect("done")
        elif w == "case":
            self.case()
        elif w == "{":
            self.i += 1
            self.parse_list({"}"}, "")
            self.expect("}")
        elif t[i] == "(":
            if t.startswith("((", i):
                self.i += 2
                self.arith()
            else:
                self.i += 1
                self.parse_list(set(), ")")
                self.skip_ws_nl()
                if self.i >= self.n or t[self.i] != ")":
                    self.err("missing ) of a subshell")
                self.i += 1
        elif w == "[[":
            self.cond()
        elif w == "function":
            self.i += 8
            self.skip_blank()
            v = self.read_word()
            if not (v.lit and FUNC_RE.match(v.sval)):
                self.err("a function name that is not a plain name")
            self.skip_blank()
            if t.startswith("(", self.i):
                self.i += 1
                self.skip_blank()
                if not t.startswith(")", self.i):
                    self.err("bad function definition")
                self.i += 1
            self.funcbody(v.sval, v.line)

    def funcbody(self, name, line):
        """a definition NAME() BODY: recorded with whether it is at the top level (round 13, A3: a definition inside a
        compound command, a subshell, a substitution or a function is refused by the gate) and its statement"""
        self.skip_ws_nl()
        w = self.peek_word()
        if w != "{":
            self.refuse(self.i, "a function body that is not { ... }")
        if not (w in ("{", "if", "while", "until", "for", "case", "select", "[[") or self.t.startswith("(", self.i)):
            self.err("a function body that is not a compound command")
        outer, self.func = self.func, name
        rec = [name, line, len(self.cmds), None, self.depth == 0 and outer == "", self.sh.stmt]
        self.funcdefs.append(rec)
        self.depth += 1
        try:
            self.parse_command()
        finally:
            self.depth -= 1
        rec[3] = len(self.cmds)
        self.func = outer

    def case(self):
        t = self.t
        self.i += 4
        self.skip_blank()
        self.read_word()
        self.skip_ws_nl()
        if self.peek_word() != "in":
            self.err("case without in")
        self.i += 2
        while True:
            self.skip_ws_nl()
            if self.peek_word() == "esac":
                self.i += 4
                return
            if self.i >= self.n:
                self.err("case without esac")
            if t[self.i] == "(":
                self.i += 1
            while True:
                self.skip_blank()
                if self.i >= self.n or t[self.i] in "|)\n;":
                    self.err("an empty case pattern")
                self.read_word()
                self.skip_blank()
                if t.startswith("|", self.i):
                    self.i += 1
                    continue
                if t.startswith(")", self.i):
                    self.i += 1
                    break
                self.err("a bad case pattern")
            self.parse_list({"esac"}, "")
            self.skip_blank()
            for term in (";;&", ";;", ";&"):
                if t.startswith(term, self.i):
                    if term != ";;":
                        self.refuse(self.i, "the case terminator %s (it falls through to the next pattern)" % term)
                    self.i += len(term)
                    break

    def cond(self):
        """[[ ... ]] read into tokens and checked against a closed grammar (round 13, A4): string tests only
        (COND_UNARY, COND_BINARY); an arithmetic or file comparison (-eq, -lt, -nt, ...), -v, < and > and a process
        substitution are refused (an operand of -eq is evaluated as arithmetic: an assignment or a subscript runs)"""
        t = self.t
        start = self.i
        self.i += 2
        toks = []
        while True:
            self.skip_blank()
            if self.i >= self.n:
                self.err("[[ without ]]")
            c = t[self.i]
            if c == "\n":
                self.refuse(self.i, "a newline inside [[ ]]")
                self.newline()
                continue
            if t.startswith("]]", self.i) and (self.i + 2 >= self.n or t[self.i + 2] in METACH):
                self.i += 2
                break
            if t.startswith("&&", self.i) or t.startswith("||", self.i):
                toks.append(("op", t[self.i:self.i + 2]))
                self.i += 2
                continue
            if c in "()":
                toks.append(("op", c))
                self.i += 1
                continue
            if c == "!" and t[self.i + 1:self.i + 2] in (" ", "\t"):
                toks.append(("op", "!"))
                self.i += 1
                continue
            if c in "<>":
                self.refuse(self.i, "< or > inside [[ ]] (an order test or a process substitution)")
                if t.startswith("(", self.i + 1):
                    self.i += 2
                    self.until_paren("a process substitution")
                else:
                    self.i += 1
                continue
            if c in ";&|":
                self.err("%r inside [[ ]]" % c)
            if toks and toks[-1][0] == "w" and toks[-1][1].lit and toks[-1][1].sval == "=~":
                self.cond_regex()
                toks.append(("re", None))
                continue
            toks.append(("w", self.read_word()))
        why = cond_check(toks)
        if why:
            self.refuse(start, "[[ ]] outside the closed grammar: %s" % why)

    def cond_regex(self):
        """the regular expression after =~ : up to white space outside parentheses (bash reads | and ( ) as part of
        it); ; & < > and white space inside parentheses are refused"""
        t, n = self.t, self.n
        depth, start = 0, self.i
        while self.i < n:
            c = t[self.i]
            if c in " \t\n":
                if depth == 0:
                    break
                self.refuse(self.i, "white space inside parentheses of a =~ regular expression")
                self.i += 1
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    self.err("an unbalanced ) in a =~ regular expression")
                depth -= 1
            elif c == "\\":
                self.i += 2
                continue
            elif c == "'":
                j = t.find("'", self.i + 1)
                if j < 0:
                    self.err("an unterminated single quote")
                self.i = j + 1
                continue
            elif c == '"':
                self.i += 1
                self.read_dq('"')
                continue
            elif c == "$":
                self.dollar(False)
                continue
            elif c == "`":
                self.backtick()
                continue
            elif c in ";&<>":
                self.refuse(self.i, "%r in a =~ regular expression" % c)
            self.i += 1
        if self.i == start or depth:
            self.err("=~ without a complete regular expression")

    def simple(self):
        t, n = self.t, self.n
        cmd = Cmd(self.line(self.i), self.func, self.sh.stmt, self.depth)
        self.cmds.append(cmd)
        while True:
            self.skip_blank()
            if self.i >= n:
                return
            c = t[self.i]
            if c == "#" or c in "\n;|)" or (c == "&" and not t.startswith("&>", self.i)):
                return
            if c == "(":
                if (len(cmd.words) == 1 and not cmd.assigns and not cmd.redirs and cmd.words[0].lit and
                        FUNC_RE.match(cmd.words[0].sval)):
                    self.i += 1
                    self.skip_blank()
                    if not t.startswith(")", self.i):
                        self.err("bad function definition")
                    self.i += 1
                    self.cmds.remove(cmd)
                    self.funcbody(cmd.words[0].sval, cmd.line)
                    return
                self.err("unexpected (")
            if self.at_redir():
                self.redirect(cmd, None)
                continue
            w = self.read_word()
            if (w.lit and (w.sval.isdigit() or FDVAR_RE.match(w.sval)) and self.i < n and t[self.i] in "<>" and
                    not t.startswith("(", self.i + 1)):
                if FDVAR_RE.match(w.sval):
                    self.refuse(self.i, "a {name} redirection (it assigns the name)")
                self.redirect(cmd, w.sval)
                continue
            assign = bool(ASSIGN_RE.match(w.raw))
            if assign and w.raw.endswith("=") and self.i < n and t[self.i] == "(":
                self.i += 1
                self.array_elems()
                w.lit, w.sval, w.dyn = False, None, True
            if not cmd.words and assign:
                cmd.assigns.append(w)
                continue
            if not cmd.words and not cmd.assigns and not cmd.redirs and w.lit and w.sval in RESERVED:
                self.err("unexpected reserved word %r" % w.sval)
            cmd.words.append(w)

    def array_elems(self):
        while True:
            self.skip_ws_nl()
            if self.i >= self.n:
                self.err("missing ) of an array")
            if self.t[self.i] == ")":
                self.i += 1
                return
            self.read_word()

    def at_redir(self):
        t, i = self.t, self.i
        if t.startswith("&>", i):
            return True
        return i < self.n and t[i] in "<>" and not t.startswith("(", i + 1)

    def redirect(self, cmd, fd):
        t = self.t
        op = next(o for o in REDIR_OPS if t.startswith(o, self.i))
        self.i += len(op)
        self.skip_blank()
        if self.i >= self.n or t[self.i] in "\n;|&)":
            self.err("a redirection without a target")
        start = self.i
        self.ps_ok_at = self.i
        try:
            w = self.read_word()
        finally:
            self.ps_ok_at = -1
        cmd.redirs.append((fd, op, w))
        # round 13 (A5): a closed set of redirection operators, file descriptors and static targets
        if op not in REDIR_OK:
            self.refuse(start, "the redirection operator %s" % op)
        if fd not in REDIR_FDS:
            self.refuse(start, "a redirection of file descriptor %s" % fd)
        if op in ("<<", "<<-"):
            if w.sval is None:
                self.err("a here-document delimiter with an expansion")
            self.heredocs.append((w.sval, op == "<<-", not w.lit, cmd))
            return
        target = w.sval if w.sval is not None else w.raw
        if op in (">&", "<&"):
            m = re.match(r'"?\$([A-Za-z_][A-Za-z0-9_]*)"?\Z', w.raw)
            if m and w.raw.count('"') in (0, 2):
                self.sh.fdnames.append((self.line(start), self.func, m.group(1)))
            elif w.sval is None or not re.match(r'([0-9]+|-)\Z', w.sval):
                self.refuse(start, "a %s target that is not a literal file descriptor (a name opens a file)" % op)
        elif "/dev/" in target and target != "/dev/null":
            self.refuse(start, "a redirection to a device file other than /dev/null (/dev/tcp and /dev/udp open a "
                               "network connection)")

    # -- words --
    def read_word(self):
        t, n = self.t, self.n
        w = Word()
        start = self.i
        w.line = self.line(start)
        sv, tail = [], []
        lit, dyn = True, False
        while self.i < n:
            c = t[self.i]
            if c in METACH:
                if c in "<>" and self.i == start and t.startswith("(", self.i + 1):
                    if start != self.ps_ok_at:
                        self.refuse(start, "a process substitution that is not the target of a redirection")
                    self.ps_ok_at = -1
                    self.i += 2
                    self.until_paren("a process substitution")
                    lit, dyn, tail = False, True, []
                    continue
                break
            if c == "\\":
                if self.i + 1 >= n:
                    self.err("a backslash at the end of the file")
                if t[self.i + 1] == "\n":
                    self.i += 2
                    continue
                lit = False
                sv.append(t[self.i + 1])
                tail.append(t[self.i + 1])
                self.i += 2
                continue
            if c == "'":
                j = t.find("'", self.i + 1)
                if j < 0:
                    self.err("an unterminated single quote")
                sv.append(t[self.i + 1:j])
                tail.append(t[self.i + 1:j])
                lit = False
                self.i = j + 1
                continue
            if c == '"':
                self.i += 1
                d_sv, d_dyn, d_tail = self.read_dq('"')
                lit = False
                sv.extend(d_sv)
                if d_dyn:
                    dyn, tail = True, list(d_tail)
                else:
                    tail.extend(d_tail)
                continue
            if c == "`":
                self.backtick()
                lit, dyn, tail = False, True, []
                continue
            if c == "$":
                k = self.dollar(False)
                lit = False
                if k is None:
                    dyn, tail = True, []
                else:
                    sv.append(k)
                    tail.append(k)
                continue
            sv.append(c)
            tail.append(c)
            self.i += 1
        if self.i == start:
            self.err("unexpected %r" % (t[start] if start < n else "end of file"))
        w.raw = t[start:self.i]
        w.dyn = dyn
        w.lit = lit and not dyn
        w.sval = None if dyn else "".join(sv)
        w.tail = "".join(tail)
        return w

    def read_dq(self, term):
        """the inside of a double-quoted string (term '"') or of an unquoted here-document body (term None):
        returns (static characters, holds an expansion, static text after the last expansion)"""
        t, n = self.t, self.n
        esc = '$`"\\' if term else "$`\\"
        sv, tail, dyn = [], [], False
        while True:
            if self.i >= n:
                if term is None:
                    return sv, dyn, tail
                self.err("an unterminated double quote")
            c = t[self.i]
            if term is not None and c == term:
                self.i += 1
                return sv, dyn, tail
            if c == "\\" and self.i + 1 < n:
                d = t[self.i + 1]
                if d == "\n":
                    self.i += 2
                    continue
                if d in esc:
                    sv.append(d)
                    tail.append(d)
                    self.i += 2
                    continue
            if c == "`":
                self.backtick()
                dyn, tail = True, []
                continue
            if c == "$" and t[self.i + 1:self.i + 2] not in ("'", '"'):
                k = self.dollar(True)
                if k is None:
                    dyn, tail = True, []
                else:
                    sv.append(k)
                    tail.append(k)
                continue
            sv.append(c)
            tail.append(c)
            self.i += 1

    def dollar(self, in_dq):
        """a '$' form at self.i: returns its static text ($'..', $".." and a lone $) or None for an expansion"""
        t, n, i = self.t, self.n, self.i
        nx = t[i + 1] if i + 1 < n else ""
        if nx == "'" and not in_dq:
            self.i = i + 2
            return self.ansi_c()
        if nx == '"' and not in_dq:
            self.refuse(i, '$"..." (a locale translation of a string)')
            self.i = i + 2
            s, d, _ = self.read_dq('"')
            return None if d else "".join(s)
        if nx == "[":
            self.refuse(i, "$[ ... ] (the old arithmetic expansion)")
            self.i = i + 2
            j = t.find("]", self.i)
            self.i = n if j < 0 else j + 1
            return None
        if t.startswith("$((", i):
            self.i = i + 3
            self.arith()
            return None
        if nx == "(":
            self.i = i + 2
            self.until_paren("a command substitution")
            return None
        if nx == "{":
            self.i = i + 2
            self.param(in_dq)
            return None
        if nx and (nx in DIGITS or nx in "@*#?$!-"):
            self.i = i + 2
            return None
        if nx and nx in LETTERS:
            j = i + 1
            while j < n and (t[j] in LETTERS or t[j] in DIGITS):
                j += 1
            self.i = j
            return None
        self.i = i + 1
        return "$"

    def ansi_c(self):
        t, n = self.t, self.n
        out = []
        simple = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "e": "\x1b",
                  "E": "\x1b", "\\": "\\", "'": "'", '"': '"', "?": "?"}
        while self.i < n:
            c = t[self.i]
            if c == "'":
                self.i += 1
                return "".join(out)
            if c == "\\" and self.i + 1 < n:
                d = t[self.i + 1]
                if d in simple:
                    out.append(simple[d])
                    self.i += 2
                    continue
                m = re.match(r'x([0-9A-Fa-f]{1,2})|u([0-9A-Fa-f]{1,4})|U([0-9A-Fa-f]{1,8})|([0-7]{1,3})',
                             t[self.i + 1:self.i + 10])
                if m:
                    hx = m.group(1) or m.group(2) or m.group(3)
                    out.append(chr(int(hx, 16)) if hx else chr(int(m.group(4), 8) & 0xff))
                    self.i += 1 + m.end()
                    continue
                if d == "c" and self.i + 2 < n:
                    out.append(chr(ord(t[self.i + 2]) & 0x1f))
                    self.i += 3
                    continue
                out.append("\\" + d)
                self.i += 2
                continue
            out.append(c)
            self.i += 1
        self.err("an unterminated $'...' string")

    def backtick(self):
        t, n = self.t, self.n
        start = self.i
        self.refuse(start, "a backquote command substitution (use $( ))")
        j, buf = self.i + 1, []
        while j < n and t[j] != "`":
            if t[j] == "\\" and j + 1 < n and t[j + 1] in "`\\$":
                buf.append(t[j + 1])
                j += 2
                continue
            buf.append(t[j])
            j += 1
        if j >= n:
            self.err("an unterminated backquote")
        self.i = j + 1
        c = self.child("".join(buf), start + 1)
        c.parse_all()

    def until_paren(self, what):
        self.parse_list(set(), ")")
        self.skip_ws_nl()
        if self.i >= self.n or self.t[self.i] != ")":
            self.err("missing ) of %s" % what)
        self.i += 1

    def param(self, in_dq):
        """the inside of ${...}; round 13 (A6): checked against a closed grammar (param_check): a closed set of
        operators (no := or = assignment, no @P, no pattern substitution), indirect expansion only of the validated
        names of INDIRECT_OK, every subscript and substring offset in the arithmetic grammar (arith_check)"""
        t, n = self.t, self.n
        start = self.i
        if self.i < n and t[self.i] in " \t\n|":
            self.refuse(start, "${ command; } substitution (bash 5.3): a command list inside a parameter expansion")
            if t[self.i] == "|":
                self.i += 1
            self.parse_list({"}"}, "")
            self.expect("}")
            return
        while self.i < n:
            c = t[self.i]
            if c == "\\":
                self.i += 2
                continue
            if c == "'" and not in_dq:
                j = t.find("'", self.i + 1)
                if j < 0:
                    self.err("an unterminated single quote")
                self.i = j + 1
                continue
            if c == '"':
                self.i += 1
                self.read_dq('"')
                continue
            if c == "`":
                self.backtick()
                continue
            if c == "$":
                self.dollar(in_dq)
                continue
            if c == "}":
                inner = t[start:self.i]
                self.i += 1
                why, arr, subs, offs = param_check(inner, self.script)
                if why:
                    self.refuse(start, "${%s}: %s" % (inner[:30], why))
                for text in subs:
                    self.sh.subs.append((self.line(start), self.func, arr, text))
                for text in offs:
                    self.arith_text(start, text, None)
                return
            self.i += 1
        self.err("missing } of a parameter expansion")

    def arith_text(self, i, text, arr):
        """an arithmetic text (of $(( )), (( )), a subscript of array arr, a substring offset) in the closed grammar;
        the names it reads are recorded (the gate checks what is assigned to them)"""
        why, names = arith_check(text)
        if why:
            self.refuse(i, "arithmetic outside the closed grammar: %s" % why)
        for nm in names:
            if arr is None:
                self.sh.arith_names.add((self.func, nm))
            else:
                self.sh.sub_names.add((self.func, arr, nm))

    def arith(self):
        """an arithmetic text after $(( or ((, up to the matching )); round 13: checked by arith_check"""
        t, n = self.t, self.n
        depth = 0
        a0 = self.i
        while self.i < n:
            c = t[self.i]
            if c == ")" and depth == 0:
                if t.startswith("))", self.i):
                    self.arith_text(a0, t[a0:self.i], None)
                    self.i += 2
                    return
                self.err("an arithmetic expression closed by a single )")
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == "\\":
                self.i += 2
                continue
            elif c == "'":
                j = t.find("'", self.i + 1)
                if j < 0:
                    self.err("an unterminated single quote")
                if SUBST_RE.search(t[self.i + 1:j]):
                    self.problem(self.i, "a quoted command substitution in arithmetic (it is evaluated)")
                self.i = j + 1
                continue
            elif c == '"':
                q = self.i
                self.i += 1
                sv, _d, _tl = self.read_dq('"')
                if SUBST_RE.search("".join(sv)):
                    self.problem(q, "a quoted command substitution in arithmetic (it is evaluated)")
                continue
            elif c == "`":
                self.backtick()
                continue
            elif c == "$":
                self.dollar(False)
                continue
            self.i += 1
        self.err("an unterminated arithmetic expression")


def awk_strip(prog):
    """the awk program with its string literals, regular-expression literals and comments blanked (a regular
    expression is read only where awk's grammar allows no division: after ( , ~ ! { } ; ? : = & | or a newline)"""
    out, i, n, prev = [], 0, len(prog), "\n"
    while i < n:
        c = prog[i]
        if c == "#":
            j = prog.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == '"':
            j = i + 1
            while j < n and prog[j] != '"':
                j += 2 if prog[j] == "\\" else 1
            out.append('""')
            i, prev = j + 1, '"'
            continue
        if c == "/" and prev in "(,~!{};?:=&|\n":
            j, br = i + 1, False
            while j < n and prog[j] != "\n" and (prog[j] != "/" or br):
                if prog[j] == "\\":
                    j += 2
                    continue
                if prog[j] == "[":
                    br = True
                elif prog[j] == "]":
                    br = False
                j += 1
            out.append("//")
            i, prev = j + 1, "/"
            continue
        out.append(c)
        if c not in " \t":
            prev = c
        i += 1
    return "".join(out)


def awk_runs(prog):
    """why an awk program can start a process or open a network connection, or None"""
    if "/inet" in prog:
        return "a /inet special file"
    s = awk_strip(prog)
    if re.search(r'\bsystem\b', s):
        return "system()"
    if "|" in s.replace("||", "  "):
        return "a pipe to or from a command (|, |&)"
    if "@" in s:
        return "@load, @include or an indirect call"
    return None


def sed_runs(sc):
    """why a sed script can start a process or open a file, or None (a small reader of the GNU sed syntax)"""
    i, n = 0, len(sc)

    def delimited(i, parts):
        if i >= n or sc[i] in "\n\\":
            return -1
        d = sc[i]
        i += 1
        for _ in range(parts):
            while i < n and sc[i] != d:
                i += 2 if sc[i] == "\\" else 1
            if i >= n:
                return -1
            i += 1
        return i

    while i < n:
        while i < n and sc[i] in " \t\n;":
            i += 1
        if i >= n:
            return None
        if sc[i] == "#":
            j = sc.find("\n", i)
            i = n if j < 0 else j
            continue
        for _ in range(2):   # an address, and the second one after ','
            if i < n and sc[i] in DIGITS + "$":
                while i < n and sc[i] in DIGITS + "$~+":
                    i += 1
            elif i < n and sc[i] in "/\\":
                j = delimited(i + 1, 1) if sc[i] == "\\" else delimited(i, 1)
                if j < 0:
                    return "an address the gate cannot read"
                i = j
                while i < n and sc[i] in "IM":
                    i += 1
            while i < n and sc[i] in " \t":
                i += 1
            if i < n and sc[i] == ",":
                i += 1
                while i < n and sc[i] in " \t":
                    i += 1
                continue
            break
        while i < n and sc[i] in " \t!":
            i += 1
        if i >= n:
            return None
        c = sc[i]
        i += 1
        if c in "{}=dDgGhHnNpPxzF":
            continue
        if c in "lqQL":
            while i < n and sc[i] in " \t" + DIGITS:
                i += 1
            continue
        if c in ":btT":
            while i < n and sc[i] not in ";\n":
                i += 1
            continue
        if c in "aic":
            while i < n:
                j = sc.find("\n", i)
                j = n if j < 0 else j
                more = sc[i:j].endswith("\\")
                i = j + 1
                if not more:
                    break
            continue
        if c == "y":
            i = delimited(i, 2)
            if i < 0:
                return "a y command the gate cannot read"
            continue
        if c == "s":
            i = delimited(i, 2)
            if i < 0:
                return "an s command the gate cannot read"
            j = i
            while i < n and sc[i] in "gpiImM" + DIGITS:
                i += 1
            if i < n and sc[i] in "ewW":
                return "the s///%s flag (it runs a command or writes a file)" % sc[i]
            continue
        if c in "erRwWv":
            return "the %s command (it runs a command or opens a file)" % c
        return "a sed command the gate does not know (%r)" % c
    return None


def sha(text):
    return hashlib.sha256(text.encode("utf-8", "surrogateescape")).hexdigest()


def norm_line(l):
    return " ".join(l.split())


def line_keys(l):
    """(key8, sha16) of one line: key8 is the census key of the whitespace-normalised line, sha16 is the first 16
    hex digits of sha256 of the exact bytes (so a change in white space alone is a changed line too)"""
    return sha(norm_line(l))[:8], sha(l)[:16]


class Unit(object):
    """one file the gate reads: a script given on the command line or a library one of them sources"""
    __slots__ = ("name", "path", "p", "lines", "text", "srcs", "lib", "assoc", "wsubs")

    def __init__(self, path):
        self.path, self.name = path, os.path.basename(path)
        self.text = open(path, encoding="utf-8", errors="surrogateescape").read()
        self.lines = self.text.split("\n")
        self.p = None  # type: Any  # the Parser of the file, set by Gate.load
        self.srcs, self.lib, self.assoc, self.wsubs = [], False, set(), []


class Gate(object):
    """the network-spawn gate over a set of scripts (netgate), also the invocation census (sites).
    Round 13: a positive-shape analyser (the second layer of the netgate; the first is the pin, check_pin below).
    pin: the parsed pin table (read_pin), or None (the census: no program or name list); regen: collect the names and
    the awk and sed programs for pin-regen instead of checking them against the pin."""

    def __init__(self, scripts, pin=None, regen=False):
        self.findings, self.sites, self.n_net = [], [], 0
        self.pin, self.regen = pin, regen
        self.units, self.mains = {}, []
        self.writes = []        # (unit, line, func, name, how, value word or None for a value read at run time)
        self.progs = []         # (kind, sha256, script, line) of every awk and sed program text (pin-regen)
        for s in scripts:
            u = self.load(s)
            if u is not None and u not in self.mains:
                self.mains.append(u)
        # the libraries the scripts source (SOURCE_OK only; a library sources nothing)
        for u in list(self.mains):
            for c in u.p.cmds:
                if self.is_source(c):
                    self.source(u, c)
        # a process is a script given on the command line with the libraries it sources
        self.procs = []
        for u in self.mains:
            self.procs.append([(u, None)] + [(lib, s) for s, lib in u.srcs])
        self.defs = {}
        for u in self.units.values():
            for rec in u.p.funcdefs:
                self.defs.setdefault(rec[0], []).append((u, rec))
        self.trusted = {"rc_net"}
        changed = True
        while changed:
            changed = False
            for f in TRUST_CAND:
                if f in self.trusted or len(self.defs.get(f, [])) != 1:
                    continue
                u, _rec = self.defs[f][0]
                body = [c for c in u.p.cmds if c.func == f]
                if body and all(self.wrapper_cmd_ok(f, c) for c in body) and any(
                        c.words and c.words[0].sval in self.trusted for c in body):
                    self.trusted.add(f)
                    changed = True

    # -- loading --
    def load(self, path):
        rp = os.path.realpath(path)
        if rp in self.units:
            return self.units[rp]
        try:
            u = Unit(path)
        except OSError as e:
            self.findings.append("parse error (the gate refuses what it cannot read): %s: %s" % (path, e.strerror))
            return None
        self.units[rp] = u
        p = Parser(u.text, u.name)
        u.p = p
        try:
            p.parse_all()
        except ParseError as e:
            self.findings.append("parse error (the gate refuses what it cannot read): %s" % e)
        # the action strings of trap commands are read here, into the same record, at the statement of the trap
        k = 0
        while k < len(p.cmds):
            c = p.cmds[k]
            k += 1
            ws = c.words
            j = 1 if ws and ws[0].lit and ws[0].sval == "builtin" else 0
            if len(ws) > j + 1 and ws[j].lit and ws[j].sval == "trap" and ws[j + 1].sval is not None:
                a = ws[j + 1]
                if a.sval in ("", "-") or FUNC_RE.match(a.sval):
                    continue
                n0 = len(p.cmds)
                tp = Parser(a.sval, u.name, a.line, c.func, p.sh, max(c.depth, 1))
                tp.heredocs = []
                try:
                    tp.parse_all()
                except ParseError as e:
                    self.findings.append("parse error in a trap action (the gate refuses what it cannot read): %s" % e)
                for c2 in p.cmds[n0:]:
                    c2.stmt, c2.depth = c.stmt, max(c2.depth, 1)
        return u

    def is_source(self, c):
        return bool(c.words) and c.words[0].lit and c.words[0].sval == "."

    def source(self, u, c):
        """a source command: only the exact forms of SOURCE_OK, at the top level, two words, in a script (never in a
        library); the library is read from the directory of the script"""
        raw = c.words[1].raw if len(c.words) == 2 else None
        ok = [x for x in SOURCE_OK if x[0] == u.name and x[1] == raw]
        if raw is None or not ok or c.func or c.depth or c.assigns or c.redirs or u.lib:
            return   # the builtin rule reports it (finding)
        rel = raw[raw.index("pwd)/") + 5:-1]
        lib = self.load(os.path.join(os.path.dirname(u.path), rel))
        if lib is None:
            return
        if lib.name != ok[0][2]:
            self.findings.append("source of a file other than the declared library: %s:%d" % (u.name, c.line))
            return
        lib.lib = True
        u.srcs.append((c.stmt, lib))

    def wrapper_cmd_ok(self, f, c):
        """a command of the body of candidate wrapper f: a test builtin, or a call of rc_net or of a trusted
        argument-running wrapper whose target is what f declares it runs (GATE_WRAPPERS)"""
        if c.assigns or c.redirs or c.heredocs or not c.words or not c.words[0].lit:
            return False
        s = c.words[0].sval
        if s in ("[", "true", ":"):
            return True
        if s not in self.trusted or GATE_WRAPPERS.get(s) or len(c.words) < 2:
            return False
        tg = c.words[1]
        prog = GATE_WRAPPERS.get(f)
        if prog is None:
            return tg.raw == '"$@"' or (tg.lit and tg.sval == "timeout" and c.words[-1].raw == '"$@"')
        return tg.lit and tg.sval == prog

    def procs_of(self, u):
        return [P for P in self.procs if any(x is u for x, _ in P)]

    def fn_kind(self, u, f):
        """True when f is a function in every process u runs in, False in none, None when it differs"""
        k = {any(any(r[0] == f for r in x.p.funcdefs) for x, _ in P) for P in self.procs_of(u)}
        if not k:
            k = {any(r[0] == f for r in u.p.funcdefs)}
        return k.pop() if len(k) == 1 else None

    # -- reporting --
    def norm(self, u, line):
        return norm_line(u.lines[line - 1]) if 0 < line <= len(u.lines) else ""

    def find(self, msg, u, line):
        # round 13 (O2 of the round-12 review): a finding names its line by the census key (8 hex digits of the
        # sha256 of the normalised line), never by its text, so a literal on a refused line is not copied into the
        # evidence. The message names the offending word or option where it has one.
        key = line_keys(u.lines[line - 1])[0] if 0 < line <= len(u.lines) else "-"
        f = "%s | key=%s" % (msg, key)
        if f not in self.findings:
            self.findings.append(f)

    def run(self):
        for u in self.units.values():
            for line, func, msg in u.p.problems:
                self.find("%s: %s:%d in %s" % (msg, u.name, line, func or "-"), u, line)
            for rec in u.p.funcdefs:
                self.check_def(u, rec)
            for c in list(u.p.cmds):
                self.classify(u, c)
            for line, func, name, how, _v in u.p.sh.writes:   # loop variables (the parser records them)
                self.writes.append((u, line, func, name, how, None))
        for P in self.procs:
            self.check_process(P)
        self.check_writes()
        return self

    # -- functions: defined once, at the top level, before every call that can reach them (round 13, A3) --
    def check_def(self, u, rec):
        name, line, _k0, _k1, top, _stmt = rec
        if not top:
            self.find("a function defined outside the top level (in a function, a compound command, a subshell "
                      "or a substitution: bash defines it only when that code runs): %s:%d %s" % (u.name, line, name),
                      u, line)
        if name in BASH_BUILTINS or name in RESERVED or name in NETCMDS or name in EXECWRAP or name in LOCAL_OK:
            self.find("a function named like a builtin or a program (it changes what the name runs): %s:%d %s" % (
                u.name, line, name), u, line)
        if name == "rc_net" and u.name != "redact_cut.sh":
            self.find("a definition of rc_net outside redact_cut.sh: %s:%d" % (u.name, line), u, line)

    def key(self, s_src, stmt):
        return (stmt, 0) if s_src is None else (s_src, stmt)

    def calls(self, u, c, fnames):
        """the functions command c calls: its command word, and the function named by a trap action"""
        out = []
        ws = c.words
        if ws and ws[0].lit and ws[0].sval in fnames:
            out.append(ws[0].sval)
        j = 1 if ws and ws[0].lit and ws[0].sval == "builtin" else 0
        if len(ws) > j + 1 and ws[j].lit and ws[j].sval == "trap" and ws[j + 1].sval in fnames:
            out.append(ws[j + 1].sval)
        return out

    def check_process(self, P):
        defs, body = {}, {}
        for u, s_src in P:
            for rec in u.p.funcdefs:
                k = self.key(s_src, rec[5])
                if rec[0] in defs:
                    self.find("a function defined twice in one process (the later one replaces it at run time): "
                              "%s:%d %s" % (u.name, rec[1], rec[0]), u, rec[1])
                    continue
                defs[rec[0]] = k
        fnames = set(defs)
        tops = []
        for u, s_src in P:
            for c in u.p.cmds:
                for f in self.calls(u, c, fnames):
                    if c.func:
                        body.setdefault(c.func, set()).add(f)
                    else:
                        tops.append((self.key(s_src, c.stmt), f, u, c))
        for k, f, u, c in tops:
            seen, todo = set(), [f]
            while todo:
                g = todo.pop()
                if g in seen:
                    continue
                seen.add(g)
                todo.extend(body.get(g, ()))
                if g in defs and defs[g] >= k:
                    self.find("a function called before its definition (bash would run a program or a builtin of "
                              "that name): %s:%d %s%s" % (u.name, c.line, g, "" if g == f else " (through %s)" % f),
                              u, c.line)
        # every process: the names declared with declare -A (their subscripts are not arithmetic)
        assoc = set()
        for u, _s in P:
            assoc |= u.assoc
        for u, _s in P:
            for line, func, arr, text in u.p.sh.subs:
                self.subscript(u, line, func, arr, text, assoc)
            for line, func, arr, text in u.wsubs:
                self.subscript(u, line, func, arr, text, assoc)
        # A6: a name read in arithmetic (also a subscript of an indexed array) holds a number: every static value
        # that can reach the read is a number or an arithmetic expansion, every value read at run time is on A6_DATA.
        # Which writes reach a read in function g (bash scopes dynamically): when g declares the name local, the
        # writes in g and in the functions g calls that do not declare it local themselves; otherwise the writes at
        # the top level, in every function that does not declare it local, and in every function that declares it
        # local and calls g.
        reads = set()
        for u, _s in P:
            reads |= set(u.p.sh.arith_names)
            reads |= {(f, nm) for f, arr, nm in u.p.sh.sub_names if arr not in assoc}
        inP = [w for w in self.writes if any(x is w[0] for x, _ in P)]
        locs = {}
        for w in inP:
            if w[4] == "local":
                locs.setdefault(w[2], set()).add(w[3])

        def reach(f):
            seen, todo = set(), [f]
            while todo:
                g = todo.pop()
                if g not in seen:
                    seen.add(g)
                    todo.extend(body.get(g, ()))
            return seen
        for g, nm in sorted(reads):
            if nm in locs.get(g, ()):
                fs = {h for h in reach(g) if h == g or nm not in locs.get(h, ())}
                hit = [w for w in inP if w[3] == nm and w[2] in fs]
            else:
                hit = [w for w in inP if w[3] == nm and (
                    not w[2] or nm not in locs.get(w[2], ()) or (g and g in reach(w[2])))]
            for wu, line, func, name, how, val in hit:
                why = self.numeric(val)
                if why and (wu.name, func, name) not in A6_DATA:
                    self.find("a value that is not a number written to %s, which is read in arithmetic in %s (its "
                              "text is evaluated: an assignment in it runs): %s:%d (%s)" % (
                                  name, g or "the top level", wu.name, line, why), wu, line)
        # a name used as a file descriptor (>&"$name"): every value written to it is a number
        fdn = set()
        for u, _s in P:
            fdn |= {nm for _l, _f, nm in u.p.sh.fdnames}
        for wu, line, func, name, how, val in inP:
            if name in fdn and (val is None or val.sval is None or not re.match(r'[0-9]+\Z', val.sval)):
                self.find("a value that is not a file descriptor number written to %s, which is a redirection "
                          "target (a file name there opens it; /dev/tcp opens a connection): %s:%d" % (
                              name, wu.name, line), wu, line)

    def numeric(self, val):
        if val is None:
            return "a value read at run time"
        s = val.sval
        if s is not None:
            return None if re.match(r'-?[0-9]*\Z', s) else "the static value %r" % s[:20]
        if re.match(r'"?\$\(\((?:[^()]|\([^()]*\))*\)\)"?\Z', val.raw) or re.match(
                r'"?\$\{#[A-Za-z_][A-Za-z0-9_]*\}"?\Z', val.raw):
            return None
        return "a value with an expansion"

    def subscript(self, u, line, func, arr, text, assoc):
        if arr in assoc:
            return
        why, names = arith_check(text)
        if why:
            self.find("a subscript of the indexed array %s outside the arithmetic grammar (it is evaluated): %s:%d "
                      "(%s)" % (arr, u.name, line, why), u, line)
        for nm in names:
            u.p.sh.sub_names.add((func, arr, nm))

    # -- the names a script writes (round 13: every name on the pin's name list, none of DANGER_NAMES) --
    def write(self, u, c, line, name, how, val):
        self.writes.append((u, line, c.func, name, how, val))

    def check_writes(self):
        names = set()
        done = set()
        for u, line, func, name, how, val in self.writes:
            if (u.path, line, name, how) in done:
                continue
            done.add((u.path, line, name, how))
            names.add(name)
            if is_danger(name):
                ok = (name == "IFS" and how in ("assign", "prefix", "local") and val is not None and
                      val.sval is not None and val.sval in IFS_VALUES)
                if not ok:
                    self.find("a write to %s (%s; it changes how a command is found, run or loaded): %s:%d" % (
                        name, how, u.name, line), u, line)
            if self.pin is not None and not self.regen and name not in self.pin["N"]:
                self.find("a write to a name that is not on the name list of the pin (%s, %s): %s:%d" % (
                    name, how, u.name, line), u, line)
        self.names = names

    # -- classification --
    def classify(self, u, c):
        for w in c.assigns:
            m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)(?:\[([^\]]*)\])?\+?=', w.raw)
            if m is None:
                self.find("an assignment the gate cannot read: %s:%d" % (u.name, w.line), u, w.line)
                continue
            val = self.value_of(w, m.end())
            self.write(u, c, w.line, m.group(1), "prefix" if c.words else "assign", val)
            if m.group(2) is not None:   # checked with the process (check_process): arithmetic unless declare -A
                self.wsub(u, w.line, c.func, m.group(1), m.group(2))
        if c.words:
            self.command(u, c, 0)

    def wsub(self, u, line, func, arr, text):
        u.wsubs.append((line, func, arr, text))

    def value_of(self, w, at):
        """the value part of an assignment word NAME=VALUE (a Word), or None when it is an array (a list)"""
        if w.raw[at:at + 1] == "(":
            return None
        v = Word()
        v.raw = w.raw[at:]
        v.line = w.line
        v.dyn = w.dyn
        v.lit = w.lit
        v.sval = None if w.sval is None else w.sval.split("=", 1)[1] if "=" in w.sval else None
        v.tail = ""
        return v

    def cannot(self, u, c, w, why):
        self.find("command word the gate cannot classify (%s): %s:%d %s in %s" % (
            why, u.name, w.line, w.raw[:40], c.func or "-"), u, w.line)

    def plain(self, u, c, w):
        """the word is a plain literal name; otherwise a finding"""
        if w.lit and CMDNAME_RE.match(w.sval):
            return True
        if w.dyn:
            why = "expansion in command position"
        elif not w.lit:
            why = "quoted or escaped"
        elif "/" in w.sval:
            why = "a path"
        else:
            why = "a glob, brace, tilde or other character bash expands"
        self.cannot(u, c, w, why)
        return False

    def command(self, u, c, k):
        """the command named by c.words[k] in bash's order: a function, a builtin, a program"""
        w = c.words[k]
        if not self.plain(u, c, w):
            return
        s = w.sval
        kind = self.fn_kind(u, s)
        if s == "rc_net":
            self.external(u, c, k + 1, "rc_net")
        elif kind is None:
            self.find("a name that is a function in one process and a command in another: %s:%d %s" % (
                u.name, w.line, s), u, w.line)
        elif kind:
            if s in TRUST_CAND:
                if GATE_WRAPPERS.get(s):
                    self.site(u, c, w, GATE_WRAPPERS[s], s, c.words[k + 1:])
                else:
                    self.external(u, c, k + 1, s)
        elif s in BASH_BUILTINS:
            self.builtin(u, c, k)
        else:
            self.external(u, c, k, "")

    def builtin(self, u, c, k):
        """a builtin in the closed list, in the closed grammar of its options (round 13, K3)"""
        ws = c.words
        s, args = ws[k].sval, ws[k + 1:]
        line = ws[k].line
        sv = [w.sval for w in args]

        def bad(why):
            self.find("builtin %s %s: %s:%d" % (s, why, u.name, line), u, line)

        if k == 0 and (u.name, c.func, tuple(w.raw for w in ws)) in DYN_SITES:
            return   # an exact dynamic site: the name or command it uses is validated at run time (a residual)
        if s not in BUILTIN_ALLOWED:
            bad("is not on the closed list of builtins the release scripts use (it can run, define or look up a "
                "command, or write a name, in a way the gate does not follow)")
            return
        if s == "builtin":
            if args and args[0].lit and args[0].sval in BUILTIN_ALLOWED and args[0].sval != "builtin":
                self.builtin(u, c, k + 1)
            else:
                bad("of a word that is not a builtin of the closed list")
        elif s in (":", "true", "echo", "pwd", "return", "exit", "shift", "continue", "cd"):
            return
        elif s == ".":
            if (u.lib or c.func or c.depth or len(ws) != 2 or k != 0 or
                    not any(x[0] == u.name and x[1] == ws[1].raw for x in SOURCE_OK)):
                bad("other than the exact forms of SOURCE_OK at the top level of a script (round 13, R22)")
        elif s == "[":
            if not args or args[-1].sval != "]":
                bad("without a closing ]")
            for w in args[:-1]:
                if w.sval is not None and w.sval.startswith("-") and len(w.sval) > 1 and w.sval not in TEST_OPS:
                    bad("with the operator %s (not on TEST_OPS; -v evaluates a subscript)" % w.sval)
        elif s == "command":
            if not (len(args) == 2 and sv[0] == "-v"):
                bad("other than command -v NAME")
        elif s == "compgen":
            if sv not in (["-e"], ["-A", "function"]):
                bad("other than compgen -e or compgen -A function (-C, -F, -W and -X run code)")
        elif s == "declare":
            if len(args) == 2 and sv[0] == "-A" and sv[1] is not None and NAME_RE.match(sv[1]):
                self.write(u, c, line, sv[1], "declare", None)
                u.assoc.add(sv[1])
            else:
                bad("other than declare -A NAME")
        elif s == "local":
            for w in args:
                if w.sval == "-":
                    continue
                m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)(=|\Z)', w.raw)
                if not m:
                    bad("of a word that is not NAME or NAME=VALUE")
                    continue
                self.write(u, c, line, m.group(1), "local", self.value_of(w, m.end()) if m.group(2) else Word0())
        elif s == "export":
            for w in args:
                m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)(=|\Z)', w.raw)
                if not m:
                    bad("of a word that is not NAME or NAME=VALUE (an option or a name read at run time)")
                    continue
                self.write(u, c, line, m.group(1), "export", self.value_of(w, m.end()) if m.group(2) else Word0())
        elif s == "read":
            j = 0
            while j < len(args) and sv[j] is not None and sv[j].startswith("-"):
                if sv[j] == "-r":
                    j += 1
                elif sv[j] == "-d" and j + 1 < len(args):
                    j += 2
                else:
                    bad("with the option %s (only -r and -d)" % sv[j])
                    return
                continue
            for w in args[j:]:
                if w.lit and NAME_RE.match(w.sval):
                    self.write(u, c, line, w.sval, "read", None)
                else:
                    bad("of a word that is not a plain name")
        elif s == "printf":
            dd = sv[:1] == ["--"]
            if dd:
                sv = sv[1:]
            if not sv or sv[0] is None or (sv[0].startswith("-") and not dd):
                bad("with a format that is not a static string, or with an option (-v writes a name)")
        elif s == "set":
            if not args or any(x not in SET_ARGS for x in sv):
                bad("other than %s" % " ".join(sorted(SET_ARGS)))
        elif s == "shopt":
            if sv != ["-s", "execfail"]:
                bad("other than shopt -s execfail")
        elif s == "trap":
            if len(args) < 2 or sv[0] is None or any(x not in TRAP_SIGNALS for x in sv[1:]):
                bad("other than trap ACTION SIGNAL... with a static action and a signal of %s" % ", ".join(
                    sorted(TRAP_SIGNALS)))
        elif s == "unset":
            if sv[:1] == ["-v"]:
                for w in args[1:]:
                    if w.lit and NAME_RE.match(w.sval):
                        self.write(u, c, line, w.sval, "unset", Word0())
                    else:
                        bad("-v of a word that is not a plain name")
            elif len(args) == 1 and sv[0] is not None and re.match(r'[A-Za-z_][A-Za-z0-9_]*\[.*\]\Z', sv[0]):
                arr = sv[0].split("[", 1)[0]
                self.wsub(u, line, c.func, arr, sv[0][len(arr) + 1:-1])
                self.write(u, c, line, arr, "unset", Word0())
            else:
                bad("other than unset -v NAME... or unset 'NAME[SUBSCRIPT]'")
        elif s == "exec":
            j = 0
            while j < len(args) and sv[j] is not None and sv[j].startswith("-"):
                if sv[j] in ("-c", "-l"):
                    j += 1
                elif sv[j] == "-a" and j + 1 < len(args):
                    j += 2
                else:
                    bad("with the option %s" % sv[j])
                    return
            if j == len(args):
                if j:
                    bad("with options and no command")
                return
            prog = tuple(w.raw for w in args[j:])
            if (u.name, "exec", prog) in ALLOW_EXEC:
                self.site(u, c, args[j], "bash", "exec", args[j + 1:])
            else:
                bad("of a command not on ALLOW_EXEC")
                w0 = args[j]   # still an invocation of the census (list, lint), labelled FINDING
                self.sites.append((u.name, w0.line, "bash" if w0.raw in BASH_WORDS else (w0.sval or w0.raw), "exec",
                                   "FINDING", self.norm(u, w0.line)))
        elif s == "eval":
            bad("outside the exact sites of DYN_SITES")
        else:
            bad("without a grammar (an internal error of the gate)")

    def external(self, u, c, k, via):
        """c.words[k] is run as a program, reached through via (rc_net, nt, net or "")"""
        if k >= len(c.words):
            return
        w = c.words[k]
        if not w.lit and w.dyn and via in self.trusted and c.func in self.trusted and w.raw == '"$@"':
            return   # a trusted wrapper runs its own arguments
        if not self.plain(u, c, w):
            return
        self.site(u, c, w, w.sval, via, c.words[k + 1:])

    def site(self, u, c, w, prog, via, args):
        line = w.line
        norm = self.norm(u, line)
        cls = None
        if prog in NETCMDS:
            if via in self.trusted:
                self.n_net += 1
                cls = "network-through-" + via
            else:
                self.find("network command outside rc_net: %s:%d %s (via %s)" % (u.name, line, prog, via or "-"), u, line)
        elif prog in EXECWRAP:
            if (u.name, via, tuple(x.raw for x in [w] + list(args))) in ALLOW_EXEC:
                cls = "interpreter-allow-listed"
            else:
                self.find("interpreter or exec wrapper not on the allow-list: %s:%d %s (via %s)" % (
                    u.name, line, prog, via or "-"), u, line)
        elif prog in LOCAL_SIMPLE:
            cls = "local"
        elif prog in LOCAL_PROG:
            why = self.prog_check(u, line, prog, args)
            if why:
                self.find("%s that can run a command or is not on the pin: %s:%d (%s)" % (prog, u.name, line, why), u, line)
            else:
                cls = "local-checked-" + prog
        else:
            self.find("unclassified command (default deny): %s:%d %s" % (u.name, line, prog), u, line)
        self.sites.append((u.name, line, prog, via, cls or "FINDING", norm))

    def program_ok(self, u, line, kind, text):
        why = awk_runs(text) if kind == "awk" else sed_runs(text)
        if why:
            return why
        h = sha(text)
        self.progs.append((kind, h, u.name, line))
        if self.pin is not None and not self.regen and (kind, h) not in self.pin["P"]:
            return "a %s program that is not on the whitelist of the pin (sha256 %s)" % (kind, h[:16])
        return None

    def prog_check(self, u, line, prog, args):
        sv = [w.sval for w in args]
        if prog == "awk":
            j = 0
            while j < len(args):
                s = sv[j]
                if s is None:
                    return "an option or a program the gate cannot read"
                if s in ("-F", "-v"):
                    if j + 1 >= len(args):
                        return "%s without a value" % s
                    val = args[j + 1]
                    if s == "-F" and val.sval is None:
                        return "a field separator the gate cannot read"
                    if s == "-v":
                        why = self.awk_assign(val.raw, val.sval)
                        if why:
                            return why
                    j += 2
                    continue
                if s.startswith(("-F", "-v")) and len(s) > 2:
                    if s.startswith("-v"):
                        why = self.awk_assign(s[2:], s[2:])
                        if why:
                            return why
                    j += 1
                    continue
                if s.startswith("-") and s != "-":
                    return "the option %s (only -F and -v; -f, -e, -E, -i, -l and the long options load text)" % s
                break
            if j >= len(args):
                return "no program"
            if sv[j] is None:
                return "a program the gate cannot read"
            why = self.program_ok(u, line, "awk", sv[j])
            if why:
                return why
            for w in args[j + 1:]:
                if w.sval is not None and ("inet" in w.sval or re.match(r'[A-Za-z_][A-Za-z0-9_]*=', w.sval)):
                    return "the operand %r (an assignment operand or a /inet special file)" % w.sval[:30]
            return None
        if prog == "sed":
            j = 0
            while j < len(args) and sv[j] == "-n":
                j += 1
            if j >= len(args) or sv[j] is None or sv[j].startswith("-"):
                return "an option other than -n, or a script the gate cannot read"
            return self.program_ok(u, line, "sed", sv[j])
        if prog == "sort":
            if any(x != "-V" for x in sv):
                return "an argument other than -V (--compress-program and its prefixes run a program)"
            return None
        if prog == "sqlite3":
            if sv[:1] != ["-safe"]:
                return "-safe is not the first argument (an option that takes a value can swallow a later -safe)"
            for x in sv[1:]:
                if x is not None and x.startswith("-") and x not in SQLITE_OPTS:
                    return "the option %s (not on SQLITE_OPTS)" % x
            return None
        return None

    def awk_assign(self, raw, s):
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*=', raw)
        if not m:
            return "an awk -v that is not NAME=VALUE"
        if s is not None and ("inet" in s or "\\" in s):
            return "an awk -v value with inet or an escape (awk processes escapes in -v values)"
        return None


class Word0(object):
    """the value of NAME without =: none (a declaration)"""
    raw, sval, dyn, lit, line, tail = "", "", False, True, 0, ""



def read_pin(path):
    """the pin table: F (file sha and lines), L (line keys), S (sites), P (programs), N (names)"""
    pin = {"F": {}, "L": {}, "S": set(), "P": set(), "N": set(), "bad": []}
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        pin["bad"].append("the pin table cannot be read: %s" % e.strerror)
        return pin
    for n, l in enumerate(text.split("\n"), 1):
        if not l or l.startswith("#"):
            continue
        f = l.split("\t")
        try:
            if f[0] == "F" and len(f) == 4:
                pin["F"][f[1]] = (f[2], int(f[3]))
            elif f[0] == "L" and len(f) == 5:
                pin["L"][(f[1], int(f[2]))] = (f[3], f[4])
            elif f[0] == "S" and len(f) == 7:
                pin["S"].add((f[1], int(f[2]), f[3], "" if f[4] == "-" else f[4], f[5], f[6]))
            elif f[0] == "P" and len(f) == 4:
                pin["P"].add((f[1], f[2]))
            elif f[0] == "N" and len(f) == 3:
                pin["N"].add(f[1])
            else:
                pin["bad"].append("pin table line %d: a row the gate does not know" % n)
        except ValueError:
            pin["bad"].append("pin table line %d: a number field that is not a number" % n)
    if not pin["F"] or not pin["N"]:
        pin["bad"].append("the pin table has no F or no N rows")
    return pin


def build_pin(g):
    """the rows of the pin table for the files and the analyser record of gate g (sorted, no script text)"""
    rows = []
    for u in sorted(g.units.values(), key=lambda x: x.name):
        rows.append(("F", u.name, sha(u.text), str(len(u.lines))))
        for i, l in enumerate(u.lines, 1):
            k8, s16 = line_keys(l)
            rows.append(("L", u.name, str(i), k8, s16))
    for name, line, prog, via, cls, norm in sorted(g.sites, key=lambda x: (x[0], x[1], x[2], x[3])):
        rows.append(("S", name, str(line), prog, via or "-", cls, sha(norm)[:8]))
    seen = set()
    for kind, h, name, line in sorted(g.progs):
        if (kind, h) not in seen:
            seen.add((kind, h))
            rows.append(("P", kind, h, "%s:%d" % (name, line)))
    first = {}   # the first write of each name, by (script, line): the table does not depend on the argument order
    for u, line, _f, name, _how, _v in g.writes:
        if name not in first or (u.name, line) < first[name]:
            first[name] = (u.name, line)
    for name in sorted(first):
        rows.append(("N", name, "%s:%d" % first[name]))
    return rows


def check_pin(pin, g):
    """the first layer: the bytes of every file are the bytes of the pin; a difference is reported by line number
    and line key, never by text (review O2)"""
    out = list(pin["bad"])
    have = {u.name: u for u in g.units.values()}
    for name in sorted(set(have) - set(pin["F"])):
        out.append("PIN a file that is not on the pin: %s" % name)
    for name in sorted(set(pin["F"]) - set(have)):
        out.append("PIN a file of the pin that was not given or loaded: %s" % name)
    for name in sorted(set(have) & set(pin["F"])):
        u = have[name]
        h, nl = pin["F"][name]
        if sha(u.text) == h and len(u.lines) == nl:
            continue
        out.append("PIN %s differs from the pin (sha256 %s, pinned %s; %d lines, pinned %d)" % (
            name, sha(u.text)[:16], h[:16], len(u.lines), nl))
        for i in range(1, max(len(u.lines), nl) + 1):
            new = line_keys(u.lines[i - 1]) if i <= len(u.lines) else None
            old = pin["L"].get((name, i))
            if new != old:
                out.append("PIN %s:%d line key %s, pinned %s" % (name, i, new[0] if new else "(none)",
                                                                 old[0] if old else "(none)"))
    got = {(n, l, p, v or "", c, sha(norm)[:8]) for n, l, p, v, c, norm in g.sites}
    for s in sorted(got - pin["S"]):
        out.append("PIN a site that is not on the pin: %s:%d %s via %s class %s key %s" % (
            s[0], s[1], s[2], s[3] or "-", s[4], s[5]))
    for s in sorted(pin["S"] - got):
        out.append("PIN a site of the pin that the analyser does not find: %s:%d %s via %s class %s key %s" % (
            s[0], s[1], s[2], s[3] or "-", s[4], s[5]))
    return out


def gate_sites(scripts):
    """(script, line, command, key, line text, via) of every program a script runs, from the parser"""
    g = Gate(scripts).run()
    out = []
    for name, line, prog, via, _cls, norm in g.sites:
        out.append((name, line, prog, sha(norm)[:8], norm, via))
    return out


def netgate(pin_path, scripts, show_sites=False, analyser_only=False):
    pin = read_pin(pin_path)
    g = Gate(scripts, pin=pin).run()
    pin_findings = [] if analyser_only else check_pin(pin, g)
    if analyser_only and pin["bad"]:
        pin_findings = list(pin["bad"])
    if show_sites:
        for name, line, prog, via, cls, norm in sorted(g.sites):
            print("SITE\t%s\t%d\t%s\t%s\t%s" % (name, line, prog, via or "-", cls))
    for f in pin_findings:
        print("FINDING " + f)
    for f in g.findings:
        print("FINDING " + f)
    n = len(g.findings) + len(pin_findings)
    print("NETGATE layer=%s invocations=%d network_through_rc_net=%d findings=%d" % (
        "analyser" if analyser_only else "pin+analyser", len(g.sites), g.n_net, n))
    if n:
        return 1
    if not g.sites:
        print("BLIND: no invocation found")
        return 2
    return 0


def pin_regen(pin_path, scripts):
    """write the pin table for the scripts; refused while the analyser has a finding (the regeneration is a reviewed
    act: run pin-diff first and review the line-key diff)"""
    g = Gate(scripts, pin=None, regen=True).run()
    bad = list(g.findings)
    for name in sorted(g.names):
        if is_danger(name) and name != "IFS":
            bad.append("a name of DANGER_NAMES would be pinned: %s" % name)
    if not g.sites:
        bad.append("BLIND: no invocation found")
    if bad:
        for f in bad:
            print("REFUSED " + f)
        return 1
    rows = build_pin(g)
    with open(pin_path, "w", encoding="utf-8") as fh:
        fh.write(PIN_HEADER)
        for r in rows:
            fh.write("\t".join(r) + "\n")
    print("PIN-REGEN rows=%d files=%d sites=%d programs=%d names=%d" % (
        len(rows), sum(1 for r in rows if r[0] == "F"), sum(1 for r in rows if r[0] == "S"),
        sum(1 for r in rows if r[0] == "P"), sum(1 for r in rows if r[0] == "N")))
    return 0


def pin_diff(pin_path, scripts):
    """the rows the pin would gain (+) and lose (-): line keys, sites, programs and names, never script text"""
    try:
        old = {tuple(l.split("\t")) for l in open(pin_path, encoding="utf-8").read().split("\n")
               if l and not l.startswith("#")}
    except OSError as e:
        print("BLIND: the pin table cannot be read: %s" % e.strerror)
        return 2
    g = Gate(scripts, pin=None, regen=True).run()
    new = set(build_pin(g))
    order = {"F": 0, "L": 1, "S": 2, "P": 3, "N": 4}

    def k(r):
        return (order.get(r[0], 9), r[1], int(r[2]) if r[0] in ("L", "S") and r[2].isdigit() else 0, r)
    for r in sorted(old - new, key=k):
        print("-" + "\t".join(r))
    for r in sorted(new - old, key=k):
        print("+" + "\t".join(r))
    for f in g.findings:
        print("FINDING " + f)
    print("PIN-DIFF removed=%d added=%d analyser_findings=%d" % (len(old - new), len(new - old), len(g.findings)))
    return 1 if (old != new or g.findings) else 0


PIN_HEADER = """# tests/release/netgate_pin.tsv — the pin of the network-spawn gate (round 13; written by
# tests/release/channel_census.py pin-regen, never by hand). Rows, tab separated:
#   F script sha256 lines            the bytes of every release script and of the library it sources
#   L script line key8 sha16         every line: key8 = census key of the normalised line, sha16 = its exact bytes
#   S script line program via class key8   every invocation site the analyser finds, with its class
#   P awk|sed sha256 script:line     the whitelisted awk and sed program texts (each passed awk_runs or sed_runs)
#   N name script:line               every variable name the scripts write (none of DANGER_NAMES but IFS)
# A change to a release script fails "netgate --pin" until this table is regenerated. Regenerate only after
# reviewing "channel_census.py pin-diff TABLE SCRIPT..." (line keys and sites, never script text).
"""


def main():
    a = sys.argv[1:]
    if a[:1] == ["list"]:
        for s in a[1:]:
            for name, i, c, k, norm in invocations(s):
                print("%s\t%d\t%s\t%s\t%s" % (name, i, c, k, norm[:120]))
        for s in a[1:]:
            for name, i, k, norm in secret_lines(s):
                print("%s\t%d\t-\t%s\t%s" % (name, i, k, norm[:120]))
        return 0
    if a[:1] == ["lint"] and len(a) > 2:
        return lint(a[1], a[2:])
    if a[:1] == ["netgate"]:
        rest = a[1:]
        if rest[:1] != ["--pin"] or len(rest) < 2:
            sys.stderr.write("netgate needs --pin TABLE (round 13: the pin is the release gate)\n" + (__doc__ or ""))
            return 2
        table, rest = rest[1], rest[2:]
        flags = {"--sites": False, "--analyser-only": False}
        while rest and rest[0] in flags:
            flags[rest.pop(0)] = True
        if not rest:
            sys.stderr.write(__doc__ or "")
            return 2
        return netgate(table, rest, show_sites=flags["--sites"], analyser_only=flags["--analyser-only"])
    if a[:1] == ["pin-regen"] and len(a) > 2:
        return pin_regen(a[1], a[2:])
    if a[:1] == ["pin-diff"] and len(a) > 2:
        return pin_diff(a[1], a[2:])
    if a[:1] == ["commands"] and len(a) == 2:
        rows, _ = read_table(a[1])
        print("\n".join(sorted({r["command"] for r in rows if r["command"] != "-"})))
        return 0
    sys.stderr.write(__doc__ or "")
    return 2


if __name__ == "__main__":
    sys.exit(main())
