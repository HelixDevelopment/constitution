#!/usr/bin/env python3
"""git_allowlist.py — closed ALLOW-LIST guard for every command a setup prompt tells an agent to run.

Review round 7 (structural): round 5/6 allow-listed only git and rm and let every other command
word through (wrappers such as stdbuf, flock, setsid, find -exec, perl -e system, gh, hub, busybox,
`: > FILE`, environment injection into the allowed push shape ...). Round 7 inverts the whole
analyser: EVERY simple command in every runnable unit must resolve to a command WORD in the closed
table POLICY below, and its arguments must match that word's closed argument rule. Anything else
is a finding (fail closed):
  * an unknown command word, a command word that is a path (/usr/bin/git, ./x), a quoted or
    escaped command word, a dynamic command word ($x, $(...), `...`; the one exception is "$@"
    inside the canonical rrun definition), every wrapper (command, builtin, exec, nohup, sudo,
    env except the one exact bootstrap form, time, nice, timeout, xargs, stdbuf, flock, setsid,
    ionice, unbuffer, watch, parallel, script, su, ...), eval, source, ., alias, trap, shopt,
    export, declare, function;
  * a leading NAME=VALUE on a command unless the pair and the command are in PREFIX_ALLOW (never
    on git), and any assignment to a name with an upper-case letter (GIT_DIR, PATH, IFS, ...);
  * `git` with any global option except `-C DIR` where DIR is one of GIT_C_DIRS (all inside the
    project root), and any git shape not in GIT_ALLOW;
  * an output redirection (>, >>, >|, &>, &>>, >&FILE) whose target is not in REDIR_OUT_ALLOW,
    and every heredoc (its body would not be analysed);
  * `rm` other than exactly `rm -rf -- "${tmpdir:?}"`.
A unit that cannot be parsed is BLIND (rc 2): it is never accepted.

Runnable code = every line between `# <ID>-BEGIN` and `# <ID>-END` markers plus every line outside
the markers that LOOKS like code. Code detection is also fail closed: a line is prose only when it
starts with an upper-case letter (and is not NAME=VALUE ...), with a markdown/list marker
(`* `, `- `, `> `, `# `, `| `, `->`), or with a plain lower-case word from the declared prose
vocabulary PROSE_WORDS (none of which is a command on PATH or a shell builtin: a test asserts it);
a line that is a single https:// URL is data. Every other line is code. Continuation lines (`\\`
at the end) are joined first.

Prose is not allow-listed, but every prose SENTENCE that names a destructive git form must carry a
negation in that same sentence (PROSE-NEG).

THREAT BOUNDARY (stated, not hidden): the analyser reads text, it does not run it. It cannot see
what a command does with data it reads at run time (a file a block greps is data); a value a block
computes at run time (`x="$(...)"`) stays the symbolic `$x` and is accepted only where the rule for
that argument names `$x` explicitly. It does not judge the commands of scripts the prompt runs
(submodules/constitution/scripts/...): those are allowed by exact path and exact flags only.

Usage: git_allowlist.py check FILE prompt|whole   -> "OK <n> checked commands ..." or one
                                                     "BAD <line>: <reason>" per finding; rc 0/1
       git_allowlist.py shapes FILE prompt|whole  -> every normalised git shape (control needle)
       git_allowlist.py units FILE prompt|whole   -> every runnable unit ("<line>: <code>")
       git_allowlist.py words FILE prompt|whole   -> every simple command ("<line>: <word> | <args>")
rc 2 = BLIND: no runnable code at all, or a unit that cannot be parsed (and no BAD finding).
No network, no writes. Dependencies: python3 standard library.
"""
import re
import sys

# ============================================================================ the allow-lists
NW = r"[^\s-]\S*"                                      # a word that cannot be an option
# git shapes (after the one permitted global option, `-C DIR`, is removed)
GIT_ALLOW = [
    r"--version",
    r"rev-parse --show-toplevel",
    r"rev-parse --git-common-dir",
    r"rev-parse --git-path (?:hooks|info/exclude)",
    r"rev-parse HEAD",
    r"rev-parse --verify -q HEAD",
    r"rev-parse --verify -q \$target\^\{commit\}",
    r"rev-parse -q --verify refs/remotes/\$r/main",
    r"status --porcelain",
    r"status --porcelain=v1 --branch",
    r"status --porcelain -- \.gitmodules constitution",
    r"config -f \.gitmodules --get-regexp " + NW,
    r"config -f \.gitmodules --get submodule\.\$nm\.url",
    r"config --get (?:remote\.origin\.url|submodule\.\$nm\.url)",
    r"submodule status",
    r"submodule status(?: --)? (?:constitution|submodules/constitution)",
    r"submodule update --init -- (?:constitution|submodules/constitution|<that-path>)",
    r"submodule add -- \$url submodules/constitution",
    r"ls-remote --exit-code -- \$u HEAD",
    r"ls-remote --tags \$r",
    r"ls-remote --tags --refs (?:origin|https://github\.com/HelixDevelopment/HelixConstitution\.git) helixconstitution-v\*",
    r"fetch --tags origin",
    r"fetch \$r",
    r"checkout -q \$(?:t|tag)",
    r"add (?:\.gitmodules submodules/constitution|submodules/constitution|helix-deps\.yaml)",
    r"mv constitution submodules/constitution",
    r"log --oneline \$before\.\.HEAD",
    r'log --oneline HEAD --branches --not --remotes \$\{x\[@\]\+"\$\{x\[@\]\}"\} --',
    r"merge-base --is-ancestor (?:\$t HEAD|HEAD \$t|refs/remotes/\$r/main HEAD)",
    r"cat-file -e \$s\^\{commit\}",
    r"remote",
    r"remote -v",
    r"symbolic-ref --short -q HEAD",
    r"for-each-ref --format=%\(objectname\) %\(refname\)",
    r"bundle create \$bk/project\.bundle --all",
    r"bundle verify (?:\$bk|\$\{bk:\?\})/project\.bundle",
    r"describe --tags --exact-match",
    r"grep --untracked --no-exclude-standard -[cn]E " + NW + r" --(?: " + NW + r")+",
    r"push --recurse-submodules=no \$r HEAD:refs/heads/main",
]
GIT_ALLOW_RE = [re.compile(p) for p in GIT_ALLOW]
# the only `-C DIR` values: every one is inside the project root ($p/$c are the submodule paths
# the blocks pass to their helpers; a literal outside value such as /tmp/x is refused)
GIT_C_DIRS = {"submodules/constitution", "constitution", "$p", "$c"}

SCRIPT = r"submodules/constitution/scripts/"
BK = r"\$\{bk:\?\}"
INST_FLAGS = (r"--non-interactive --agent none --run-setup off --edit-agent-docs off "
              r"--register-hooks off --decision-layer off --commit off")
# command word -> regex for the expanded, space-joined argument list (re.fullmatch)
POLICY = {
    # read-only or output-only utilities (their output goes to the terminal or a pipe; writes are
    # caught by the redirection rule)
    "echo": r".*", "printf": r"(?!-v\b).*", "[": r".*", "[[": r".*", "test": r".*",
    "true": r"", "false": r"", "exit": r"\S*", "return": r"\S*", "break": r"", "continue": r"",
    "pwd": r"(?:-P)?", "basename": r"\S+", "dirname": r"\S+", "read": r"(?:-r|-d \S*|-[rd]+)(?: -d \S*)?(?: [a-z_][a-z0-9_]*)+",
    "head": r"-n \d+|-c \d+", "tail": r"-n \d+", "cut": r"-c\d+|-d \S -f\d+",
    "sort": r"-u|-V", "cmp": r"-s \S+ \S+", "date": r"-u \+%Y%m%dT%H%M%SZ",
    "ls": r"(?:-ld )?[^\s-]\S*(?: [^\s-]\S*)*", "mktemp": r"-d (?:\S+)",
    "grep": r"(?!.*(?:^| )--?(?:f|file)\b).*",
    "sed": None, "awk": None, "find": None, "cp": None, "mkdir": None, "chmod": None, "cd": None,
    "curl": None, "bash": None, "env": None, "rm": None, "git": None,
    # the prompt's own helpers (their definitions are analysed as code like everything else)
    "redact": r"", "gm_cred": r"", "own_checkout": r"\S+", "unpushed": r"\S+", "rrun": None,
    # shell syntax words
    "local": None, "unset": None, "for": None, "case": None,
}
SED_SCRIPTS = {
    "-E " + 's#://[^[:space:]]*@#://***@#g; s#(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@#\\1***@#g; s#([?&;][A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt])[A-Za-z_]*=)[^&;[:space:]]*#\\1***#g',
    "s#.*refs/tags/##",
}
AWK_PROGRAMS = {
    "-v p=$p $2 == p { n = $1; sub(/^submodule\\./, \"\", n); sub(/\\.path$/, \"\", n); print n; exit }",
    "-F: NF { s += $NF } END { print s + 0 }",
}
FIND_ARGS = re.compile(r"\. -type f(?: ! -i?name [^\s;]+)+ -print0")
ARG_RULES = {
    "cp": r'-p \$f \$bk/\$f|-p \$d/\$p \$bk/\$d/\$p|-pR \$hooks \$bk/git-hooks',
    "mkdir": r'-p (?:\.constitution-install-backup|submodules|\$\(dirname "\$excl"\)|\$bk/\$d/\$\(dirname "\$p"\))',
    "chmod": r"700 \.constitution-install-backup",
    "cd": r'\$d|\$p|submodules/constitution|\$\(git rev-parse --git-common-dir\)',
    "curl": r"-fsSL https://raw\.githubusercontent\.com/HelixDevelopment/HelixConstitution/\$tag/scripts/install_constitution\.sh -o " + BK + r"/install_constitution\.sh",
    "bash": (r"-n " + BK + r"/install_constitution\.sh"
             r"|" + BK + r"/install_constitution\.sh " + INST_FLAGS + r"(?: --dry-run)?"
             r"|" + SCRIPT + r"update_constitution\.sh --(?:check|dry-run|no-hook)"
             r"|" + SCRIPT + r"setup\.sh (?:--check-only|--project-root \$PWD)"
             r"|" + SCRIPT + r"deps_manifest/verify_helix_deps_manifests\.sh (?:--root \.|--scaffold \. --write|--validate-file helix-deps\.yaml)"
             r"|" + SCRIPT + r"gates/cm_hub_engine_no_ownorg_nesting\.sh --root submodules/constitution"
             r"|" + SCRIPT + r"jev/jev-status\.sh(?: --json)?"
             r"|" + SCRIPT + r"jev/bootstrap\.sh --non-interactive"
             r"|tests/test_constitution_inheritance\.sh"
             r"|install_upstreams\.sh"),
    "env": (r"(?:-u JEV_BOOTSTRAP_[A-Z_]+ )+JEV_BOOTSTRAP_MODE=shadow JEV_HOSTED_PROBE=0 "
            r"bash " + SCRIPT + r"jev/bootstrap\.sh --non-interactive"),
    "rm": r"-rf -- \$\{tmpdir:\?\}",
}
ARG_RULES_RE = {k: re.compile(v) for k, v in ARG_RULES.items()}
RM_ALLOW = ARG_RULES_RE["rm"]                       # the only removal a prompt may run
# NAME=VALUE pairs a command may carry in front (never git), and the commands that may carry them
PREFIX_ALLOW = {"CONSTITUTION_JEV_HOOK=off", "LABEL_SYNC_AUTOWIRE=dry-run", "LABEL_SYNC_ADAPTERS=dry-run"}
PREFIX_CMDS = {"bash"}
PREFIX_PAIRS = {("IFS=", "read")}          # (assignment, command word) pairs allowed besides the above
HELPERS = {"redact", "rrun", "gm_cred", "own_checkout", "unpushed"}   # the only functions a prompt defines
# output redirection targets (after expansion); a process substitution is analysed as code
REDIR_OUT_ALLOW = {"/dev/null", "$bk/refs.txt", "$bk/SAME_AS", "$bk/NO_BUNDLE", "$excl"}
CANON_RRUN = ("rrun() { local o rc; o=\"$(\"$@\" 2>&1)\"; rc=$?; [ -z \"$o\" ] || "
              "printf '%s\\n' \"$o\" | redact; return \"$rc\"; }")

# ============================================================================ prose vocabulary
# Plain lower-case words that may start a PROSE line (outside the marked blocks). A line whose first
# word is lower-case and NOT listed here is treated as code. None of these words may be a command:
# test_setup_prompt_round7.sh asserts that none is on PATH or a bash builtin.
PROSE_WORDS = set("""
a above added adding agent already an and another any are asks at back backup be blocked blobless
block bound branch by by-name calls change chat-model cites classes constitution content create
credentials custom decision default determined did docs  each edits empty engines enough error
even every example excluded existing exists explicitly facts files first flat from gates github
gitlab gitflic gitverse github-vasic gitlab-vasic heading here hit hooks idempotently  insecure
inside installer installer's installs invocation is it its layout legacy lines list looks maintainers
merge mirror mode model move needs never next no non-fast-forward non-zero not notes on one only
operator opt or other overridden own partial-clone path pattern place plain plus post-update proceed
project project's project-local proposals real really recorded reference referred regex remote
report requires_previous_success retry rewrite root routing said same session shadow shell show
skipped skips staged step submodule success tags text that the  there these third-party this
title to tokens  unconditionally update updates use verdict version weaken when whether with
work write writing you zero above
""".split())

# Command words a prose line may NEVER start with, even inside an unfinished sentence (a static,
# host-independent list; test_setup_prompt_round7.sh additionally asserts on the authoring host that
# no prose line of the shipped prompts starts with a word that is on PATH, a builtin or a keyword).
STATIC_CMDS = set("""
alias ar as at awk bash bg break builtin busybox cat cd chattr chgrp chmod chown command continue
coproc cp crontab curl dash dd declare diff disown doas echo ed emacs env eval ex exec exit export
false fc fg file find fish flock gawk getopts gh git gzip hash head hub install ionice jobs kill killall
ksh less let ln local logout make mapfile mawk mkdir mkfifo more mount mv nano nc nice node nohup
parallel paste patch perl pkill popd poweroff printf pushd python python2 python3 read readarray
readonly reboot return rm rmdir rsync ruby scp script sed set setsid sh shift shopt shred
shutdown sleep source ssh stdbuf su sudo sync systemctl tar tee test time timeout touch trap
true truncate trust type typeset ulimit umask umount unalias unbuffer unlink unset unzip vi vim
wait watch wget write xargs yes zip zsh
""".split())

# ============================================================================ text selection
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "esac", "!", "{", "}"}
BASH_RESERVED = {"case", "coproc", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in",
                 "select", "then", "time", "until", "while"}
CMD_LIKE = STATIC_CMDS | set(POLICY) | HELPERS | KEYWORDS | BASH_RESERVED
# commands that change or execute something; a shell segment inside a prose line (after ; & | ( ) {
# } or a backquote) that starts with one of them makes the line code (English words such as if, for,
# set, read or file may start a parenthesis in prose, so the segment check uses this narrower list)
DANGER_CMDS = set("""
alias awk bash busybox chattr chgrp chmod chown command coproc cp crontab curl dash dd declare doas
echo env eval exec export find fish flock gawk gh git halt hub install ionice kill killall ksh ln
mawk mkdir mkfifo mount mv nc nice node nohup parallel patch perl pkill poweroff printf python
python2 python3 readonly reboot rm rmdir rsync ruby scp script sed setsid sh shopt shred shutdown
source ssh stdbuf su sudo systemctl tar tee timeout touch trap truncate typeset umount unbuffer
unlink unzip watch wget xargs zip zsh
""".split())
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")
LOWER_NAME = re.compile(r"^[a-z_][a-z0-9_]*$")
LABEL = re.compile(r"^(S\d+|V\d+|\d+\.)\s+")
NEG = re.compile(r"\b(never|no|not|don't|do not|forbidden|refuse[sd]?|without)\b", re.I)
PROSE_DANGER = re.compile(r"\bgit\b.*(?:"
    r"--force|--force-with-lease|\brebase\b|reset\s+--hard|--no-verify|update\s+[^.]*--recursive|"
    r"clean\s+-[a-z]*f|push\s+--delete|branch\s+-D|checkout\s+-f|--mirror|stash\s+(drop|clear)|"
    r"filter-branch|--no-gpg-sign)")


def selected_lines(path, mode):
    text = open(path, encoding="utf-8").read().split("\n")
    if mode == "prompt":
        out, st = [], 0
        for l in text:
            if st == 0 and re.match(r"^## PROMPT\s*$", l):
                st = 1
                continue
            if st == 1 and re.match(r"^(```+|~~~+)", l):
                st = 2
                continue
            if st == 2 and re.match(r"^(```+|~~~+)\s*$", l):
                break
            if st == 2:
                out.append(l)
        text = out
    return text


SENT_END = re.compile(r"[.:;!?][)\]\"'`]*$")


def line_kind(s, prev_open=False):
    k = _line_kind(s)
    if k == "code" and prev_open and LABEL.sub("", s) == s and plain_word_start(s):
        return "prose"                      # the next line of an unfinished sentence, starting like a word
    return k


def _line_kind(s):
    """'code' | 'prose' | 'data' for a stripped line outside the marked blocks (fail closed).
    prev_open: the previous non-blank line was prose that did not end its sentence."""
    t = LABEL.sub("", s)
    if not t:
        return "prose"
    if re.fullmatch(r"https://\S+", t):
        return "data"
    if ASSIGN.match(t):
        return "code"
    if re.match(r"^(\* |- |-> |> |# |\| |---|```)", t) or t in ("-", "*", ">", "#"):
        return "prose"
    if re.match(r"^\d+[a-z]?\.\s+[A-Z]", t):
        return "prose"                      # a numbered heading such as "6b. Post-update hook"
    if t[0].isupper() or not (t[0].isascii() and (t[0].isalnum() or t[0] in "_./~$\\:({!<[-'\"`&;|>")):
        return "prose"
    w = t.lstrip("({! ").split()
    w = w[0] if w else ""
    if w[:1].isupper():
        return "prose"
    base = re.sub(r"[,.;:)\]]+$", "", w)
    if re.fullmatch(r"[a-z][a-z'_-]*", base) and base in PROSE_WORDS and plain_word_start(t):
        return "prose"
    return "code"


# a non-word first token a prose line may start with: a file or directory name, a URL, a version or
# a dotted key -- never an option, a variable, an absolute, ~ or ./ path, or a name ending in a
# script extension (a continuation line must not look like a command that runs a program)
DATA_TOKEN = re.compile(r"(?![-/~$.]/?)(?!.*[=$`])(?!.*\.(?:sh|bash|zsh|py|pl|rb|js|exe|bin)$)[A-Za-z0-9_.@<>/:*?#§+-]+|\.[A-Za-z][A-Za-z0-9_.*/-]*")
SEG_SPLIT = re.compile(r"[;&|(){}`\n]|\$\(")


def plain_word_start(t):
    """True when the line can only be prose: no $( ) or process substitution, and no shell segment
    of it (split at ; & | ( ) { } and backquotes, so a backquoted span is a segment) starts with a
    known command word (quotes, backslashes,
    a leading ! and a directory part stripped), and its first word is not followed by an option."""
    if "$(" in t or "<(" in t or ">(" in t:
        return False
    toks = t.split()
    if not toks or ASSIGN.match(t):
        return False
    first = re.sub(r"[,.;:)\]\"'`]+$", "", toks[0].lstrip("(\"'`"))
    if not (re.fullmatch(r"[a-z][a-z'-]*", first) or DATA_TOKEN.fullmatch(first)):
        return False                        # an option, a variable, an absolute or ./ path, a script
    if len(toks) > 1 and toks[1].startswith("-"):
        return False
    for k, seg in enumerate(SEG_SPLIT.split(t)):
        w = seg.split()
        if not w:
            continue
        base = re.sub(r"[\\'\"!]", "", w[0])
        base = base.rsplit("/", 1)[-1]
        base = re.sub(r"[,.;:)\]]+$", "", base)
        if base in (CMD_LIKE if k == 0 else DANGER_CMDS):
            return False
    return True


def is_cmd(t):
    """Kept for callers of round 5: True when the stripped line would be treated as code."""
    return line_kind(t) == "code"


def units(path, mode):
    """[(lineno, code, is_block, block_id)] with continuations joined; plus the prose lines."""
    text = selected_lines(path, mode)
    code, prose = [], []
    inblk, i, n, blkid, prev_open = False, 0, len(text), "", False
    while i < n:
        l = text[i]
        s = l.strip()
        if re.match(r"^# [A-Z0-9]+-BEGIN$", s):
            prev_open = False
            inblk = True
            blkid = s
            i += 1
            continue
        if re.match(r"^# [A-Z0-9]+-END$", s):
            inblk = False
            i += 1
            continue
        c = None
        if inblk:
            c = s
        elif s:
            k = line_kind(s, prev_open)
            if k == "code":
                c = LABEL.sub("", s)
            elif k == "data":
                i += 1
                continue
        if c is None:
            if s:
                prose.append((i + 1, s))
                prev_open = not SENT_END.search(s)
            i += 1
            continue
        prev_open = False
        start = i
        while c.endswith("\\") and i + 1 < n:
            i += 1
            c = c[:-1] + " " + text[i].strip()
        if not inblk:
            c = re.sub(r"\s+->\s.*$", "", c)      # "-> expected result" annotations are prose
        code.append((start + 1, c, inblk, blkid if inblk else "inline%d" % start))
        i += 1
    return code, prose


# ============================================================================ tokenizer
OPS = ["&&", "||", ";;", ";&", "|&", "<<<", "&>>", ">>", "<<", ">&", "<&", "&>", ">|", ";", "&", "|", "(", ")", "<", ">"]
REDIR_OPS = {"<<<", ">>", "<<", ">&", "<&", "&>", "&>>", ">|", "<", ">"}
REDIR_WRITE = {">>", ">&", "&>", "&>>", ">|", ">"}


def _match_paren(s, i):
    """s[i] == '(' : index just after the matching ')' (quote-aware), or -1."""
    depth, j, n = 0, i, len(s)
    while j < n:
        ch = s[j]
        if ch == "\\":
            j += 2
            continue
        if ch == "'":
            k = s.find("'", j + 1)
            if k < 0:
                return -1
            j = k + 1
            continue
        if ch == '"':
            j = _skip_dq(s, j)
            if j < 0:
                return -1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return -1


def _match_brace(s, i):
    """s[i] == '{' (of a ${...}) : index just after the matching '}' (quote-aware), or -1."""
    depth, j, n = 0, i, len(s)
    while j < n:
        ch = s[j]
        if ch == "\\":
            j += 2
            continue
        if ch == "'":
            k = s.find("'", j + 1)
            if k < 0:
                return -1
            j = k + 1
            continue
        if ch == '"':
            j = _skip_dq(s, j)
            if j < 0:
                return -1
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return -1


def _skip_dq(s, j):
    """s[j] == '"' : index after the closing quote, or -1."""
    k, n = j + 1, len(s)
    while k < n:
        if s[k] == "\\":
            k += 2
            continue
        if s.startswith("$(", k):
            e = _match_paren(s, k + 1)
            if e < 0:
                return -1
            k = e
            continue
        if s.startswith("${", k):
            e = _match_brace(s, k + 1)
            if e < 0:
                return -1
            k = e
            continue
        if s[k] == '"':
            return k + 1
        if s[k] == "`":
            e = s.find("`", k + 1)
            if e < 0:
                return -1
            k = e + 1
            continue
        k += 1
    return -1


def tokenize(s):
    """Shell-like tokens: ('W', word, quoted_or_escaped) | ('O', operator) | ('P', process-subst inner).
    Quotes are removed, $(...)/${...}/backticks are kept raw inside words. None = unparsable."""
    toks, i, n = [], 0, len(s)
    while i < n:
        ch = s[i]
        if ch in " \t":
            i += 1
            continue
        if ch == "#":
            break
        if s.startswith("<(", i) or s.startswith(">(", i):
            e = _match_paren(s, i + 1)
            if e < 0:
                return None
            toks.append(("P", s[i + 2:e - 1], False))
            i = e
            continue
        op = next((o for o in OPS if s.startswith(o, i)), None)
        if op:
            toks.append(("O", op, False))
            i += len(op)
            continue
        w, raw_digits, quoted = [], True, False
        while i < n:
            ch = s[i]
            if ch in " \t" or ch in ";&|()<>":
                break
            raw_digits = raw_digits and ch.isdigit()
            if ch == "\\":
                quoted = True
                if i + 1 < n:
                    w.append(s[i + 1])
                i += 2
                continue
            if ch == "'":
                quoted = True
                k = s.find("'", i + 1)
                if k < 0:
                    return None
                w.append(s[i + 1:k])
                i = k + 1
                continue
            if ch == '"':
                quoted = True
                k = _skip_dq(s, i)
                if k < 0:
                    return None
                inner = s[i + 1:k - 1]
                w.append(re.sub(r'\\(["\\$`])', r"\1", inner))
                i = k
                continue
            if s.startswith("$(", i):
                e = _match_paren(s, i + 1)
                if e < 0:
                    return None
                w.append(s[i:e])
                i = e
                continue
            if s.startswith("${", i):
                k = _match_brace(s, i + 1)
                if k < 0:
                    return None
                w.append(s[i:k])
                i = k
                continue
            if ch == "`":
                k = s.find("`", i + 1)
                if k < 0:
                    return None
                w.append(s[i:k + 1])
                i = k + 1
                continue
            w.append(ch)
            i += 1
        word = "".join(w)
        if raw_digits and word and i < n and s[i] in "<>":
            continue            # an fd number glued to a redirection (2>/dev/null)
        toks.append(("W", word, quoted))
    return toks


def substitutions(word):
    """Inner texts of every $( ... ) and backtick substitution in a word (nesting-aware)."""
    res, i = [], 0
    while i < len(word):
        if word.startswith("$((", i):
            e = _match_paren(word, i + 1)
            if e < 0:
                break
            i = e
            continue
        if word.startswith("$(", i):
            e = _match_paren(word, i + 1)
            if e < 0:
                res.append(word[i + 2:])
                break
            res.append(word[i + 2:e - 1])
            i = e
        elif word[i] == "`":
            j = word.find("`", i + 1)
            if j < 0:
                break
            res.append(word[i + 1:j])
            i = j + 1
        else:
            i += 1
    return res


SEPS = {";", "&", "&&", "||", "|", "(", ")", ";;", ";&", "|&"}
VAR_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:[:?\-=+][^}]*)?\}|\$([A-Za-z_][A-Za-z0-9_]*)")
SUBST_RE = re.compile(r"\$\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)|`[^`]*`")


def expand(word, env):
    def rep(m):
        name = m.group(1) or m.group(2)
        return env[name] if name in env else m.group(0)
    return VAR_RE.sub(rep, word)


def set_var(env, name, value):
    v = expand(value, env)
    if "$(" in v or "`" in v or "$" in v:
        env.pop(name, None)           # dynamic value: stays unresolved ($name)
    else:
        env[name] = v


class Ctx:
    def __init__(self, rrun_def=False):
        self.rrun_def = rrun_def


def bad(found, why):
    found.append(("<" + why + ">", False))


def analyse(text, env, found, ctx, depth=0):
    """Walk one shell text; append (description, allowed) for every simple command and every
    output redirection to found."""
    if depth > 8:
        bad(found, "too deep")
        return
    toks = tokenize(text)
    if toks is None:
        found.append(("<unparsable>", None))
        return
    toks = toks + [("O", ";", False)]
    cmd, i, case_pat = [], 0, 0          # case_pat: 1 = the next words up to ')' are a pattern
    case_depth = 0
    while i < len(toks):
        kind, t, q = toks[i]
        if kind == "W" and not cmd and case_depth and case_pat:
            # a case arm pattern: words up to the closing ')' (a leading '(' is allowed)
            while i < len(toks) and not (toks[i][0] == "O" and toks[i][1] == ")"):
                if toks[i][0] == "W":
                    for inner in substitutions(toks[i][1]):
                        analyse(inner, env, found, ctx, depth + 1)
                i += 1
            case_pat = 0
            i += 1
            continue
        if kind == "W":
            if not cmd and t == "esac" and not q:
                case_depth = max(0, case_depth - 1)
                case_pat = 0
            for inner in substitutions(t):
                analyse(inner, env, found, ctx, depth + 1)
            # NAME=( ... ) / NAME+=( ... ): an array assignment, one word
            if ASSIGN.match(t) and t.endswith("=") and i + 1 < len(toks) and toks[i + 1][:2] == ("O", "("):
                j, parts = i + 2, []
                while j < len(toks) and toks[j][:2] != ("O", ")"):
                    if toks[j][0] != "W":
                        bad(found, "array assignment holds an operator")
                        return
                    for inner in substitutions(toks[j][1]):
                        analyse(inner, env, found, ctx, depth + 1)
                    parts.append(toks[j][1])
                    j += 1
                cmd.append(("W", t + "(" + " ".join(parts) + ")", q))
                i = j + 1
                continue
            # NAME() { ...: a function definition; only the prompt's own helpers may be defined
            if not cmd and i + 2 < len(toks) and toks[i + 1][:2] == ("O", "(") and toks[i + 2][:2] == ("O", ")"):
                found.append(("FUNCDEF " + t, t in HELPERS and not q))
                i += 3
                continue
            cmd.append(toks[i])
            # `case WORD in`: the following arm starts with a pattern
            if len(cmd) >= 3 and cmd[0][1] == "case" and not cmd[0][2] and t == "in" and not q:
                simple(cmd, env, found, ctx, depth)
                cmd = []
                case_depth += 1
                case_pat = 1
            i += 1
            continue
        if kind == "P":
            analyse(t, env, found, ctx, depth + 1)
            cmd.append(("W", "<(" + t + ")>", True))
            i += 1
            continue
        if kind == "O" and t in REDIR_OPS:
            cmd.append(toks[i])
            i += 1
            continue
        # a separator
        if cmd:
            simple(cmd, env, found, ctx, depth)
        cmd = []
        if t in (";;", ";&") and case_depth:
            case_pat = 1
        i += 1


def simple(items, env, found, ctx, depth):
    # ---- split words and redirections; check every output redirection
    words, k = [], 0
    while k < len(items):
        kind, t, q = items[k]
        if kind == "O" and t in REDIR_OPS:
            tgt = items[k + 1] if k + 1 < len(items) and items[k + 1][0] == "W" else None
            k += 2 if tgt else 1
            if t == "<<":
                bad(found, "heredoc (its body is not analysed)")
                continue
            if t in REDIR_WRITE:
                if tgt is None:
                    bad(found, "redirection without a target")
                    continue
                v = expand(tgt[1], env)
                ok = (t == ">&" and re.fullmatch(r"\d", v)) or v in REDIR_OUT_ALLOW or v.startswith("<(")
                found.append(("REDIR %s %s" % (t, v), bool(ok)))
            continue
        words.append((t, q))
        k += 1
    # ---- leading keywords
    while words and words[0][0] in KEYWORDS and not words[0][1]:
        words = words[1:]
    if not words:
        return
    # ---- assignments
    pre = []
    while words and ASSIGN.match(words[0][0]):
        pre.append(words[0][0])
        words = words[1:]
    if pre and not words:
        for a in pre:
            name = a.split("=", 1)[0].rstrip("+").split("[")[0]
            if not LOWER_NAME.match(name):
                found.append(("ASSIGN " + a, False))
                continue
            found.append(("ASSIGN " + name, True))
            set_var(env, name, a.split("=", 1)[1])
        return
    w, wq = words[0]
    args = [x for x, _ in words[1:]]
    xargs = [expand(x, env) for x in args]
    joined = " ".join(xargs)
    if pre:
        if wq or not all((a in PREFIX_ALLOW and w in PREFIX_CMDS) or (a, w) in PREFIX_PAIRS for a in pre):
            found.append(("PREFIX %s %s" % (" ".join(pre), w), False))
            return
    # ---- the command word
    if wq:
        if w == "$@" and ctx.rrun_def:
            found.append(("RRUN-DEF $@", True))
            return
        found.append(("QUOTED-WORD %s" % w, False))
        return
    if "$" in w or "`" in w or "/" in w or w not in POLICY:
        if w == "$@" and ctx.rrun_def:
            found.append(("RRUN-DEF $@", True))
            return
        found.append(("WORD " + w + (" " + joined if joined else ""), False))
        return
    rule = POLICY[w]
    if w == "rrun":                                   # our helper: run the rest, output redacted
        if not words[1:]:
            found.append(("WORD rrun (no command)", False))
            return
        simple([("W", x, q) for x, q in words[1:]], env, found, ctx, depth)
        return
    if w == "git":
        if pre:
            found.append(("PREFIX on git", False))
            return
        sh = git_shape(xargs)
        found.append(("GIT " + sh[0], verdict(sh[0])))
        return
    if w in ("local", "unset"):
        okk = True
        for a in args:
            name = a.split("=", 1)[0].rstrip("+").split("[")[0] if ASSIGN.match(a) else a
            if not LOWER_NAME.match(name):
                okk = False
            elif ASSIGN.match(a):
                set_var(env, name, a.split("=", 1)[1])
            else:
                env.pop(name, None)
        found.append(("%s %s" % (w.upper(), joined), okk))
        return
    if w == "for":
        name = args[0] if args else ""
        okk = bool(LOWER_NAME.match(name)) and (len(args) == 1 or args[1] == "in")
        env.pop(name, None)
        found.append(("FOR " + name, okk))
        return
    if w == "case":
        found.append(("CASE", len(args) == 2 and args[1] == "in"))
        return
    if w == "sed":
        found.append(("sed " + joined, joined in SED_SCRIPTS))
        return
    if w == "awk":
        found.append(("awk " + joined, joined in AWK_PROGRAMS))
        return
    if w == "find":
        found.append(("find " + joined, bool(FIND_ARGS.fullmatch(joined))))
        return
    if w in ARG_RULES_RE:
        if w == "rm":
            found.append(("RM: " + joined, bool(RM_ALLOW.fullmatch(joined))))
        else:
            found.append(("%s %s" % (w, joined), bool(ARG_RULES_RE[w].fullmatch(joined))))
        return
    found.append(("%s %s" % (w, joined), bool(re.fullmatch(rule, joined))))


def git_shape(args):
    a = [SUBST_RE.sub("$()", x) for x in args]
    while a and a[0].startswith("-") and a[0] != "--version":
        if a[0] == "-C" and len(a) > 1:
            if a[1] not in GIT_C_DIRS:
                return ("<git -C outside the project: %s> %s" % (a[1], " ".join(a[2:])), "")
            a = a[2:]
            continue
        return ("<global option " + a[0] + "> " + " ".join(a[1:]), "")
    return (" ".join(a), "")


def verdict(shape):
    if shape.startswith("RM: "):
        return bool(RM_ALLOW.fullmatch(shape[4:]))
    if shape.startswith("<"):
        return False
    parts = shape.split()
    sub = parts[0] if parts else ""
    if sub == "push":
        refspecs = [x for x in parts[1:] if not x.startswith("-")]
        if any(x.startswith("+") or x.startswith(":") or x.endswith(":") for x in refspecs):
            return False
    return any(r.fullmatch(shape) for r in GIT_ALLOW_RE)


def scan(path, mode):
    code, prose = units(path, mode)
    found, env = [], {}
    prev_blk = None
    for ln, c, blk, bid in code:
        if bid != prev_blk:
            env = {}
        prev_blk = bid
        acc = []
        ctx = Ctx(rrun_def=re.sub(r"\s+#.*$", "", c).strip() == CANON_RRUN)
        analyse(c, env, acc, ctx)
        for desc, okv in acc:
            found.append((ln, desc, okv))
    return code, prose, found


def prose_sentences(prose):
    """[(first line, sentence)]: prose lines grouped into paragraphs (consecutive line numbers),
    each paragraph split into sentences. A negation must sit in the SAME sentence as the
    destructive form it excuses; a "no"/"not" in a neighbouring sentence does not count."""
    paras, cur, last = [], [], None
    for ln, s in prose:
        if last is not None and ln != last + 1:
            paras.append(cur)
            cur = []
        cur.append((ln, s))
        last = ln
    if cur:
        paras.append(cur)
    out = []
    for para in paras:
        text = " ".join(s for _, s in para)
        for sent in re.split(r"(?<=[.!?;])\s+", text):
            if sent.strip():
                out.append((para[0][0], sent.strip()))
    return out


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ("check", "shapes", "units", "words"):
        print("usage: git_allowlist.py check|shapes|units|words FILE prompt|whole", file=sys.stderr)
        return 64
    what, path, mode = sys.argv[1:]
    code, prose, found = scan(path, mode)
    if not code:
        print("BLIND: no runnable code")
        return 2
    if what == "units":
        for unit in code:
            print("%d: %s" % (unit[0], unit[1]))
        return 0
    if what == "shapes":
        for ln, desc, okv in found:
            if desc.startswith("GIT "):
                print("%d: %s" % (ln, desc[4:]))
        return 0
    if what == "words":
        for ln, desc, okv in found:
            print("%d: %s %s" % (ln, "OK " if okv else ("?? " if okv is None else "BAD"), desc))
        return 0
    bad_l = [(ln, d) for ln, d, okv in found if okv is False]
    blind = [(ln, d) for ln, d, okv in found if okv is None]
    for ln, sent in prose_sentences(prose):
        if PROSE_DANGER.search(sent) and not NEG.search(sent):
            bad_l.append((ln, "PROSE-NEG " + sent))
    for ln, d in bad_l:
        print("BAD %d: %s" % (ln, d))
    for ln, d in blind:
        print("BLIND %d: %s" % (ln, d))
    if bad_l:
        return 1
    if blind:
        return 2
    print("OK %d checked commands (every command word allow-listed) in %d runnable units" % (len(found), len(code)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
