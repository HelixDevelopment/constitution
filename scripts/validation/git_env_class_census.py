#!/usr/bin/env python3
"""git_env_class_census.py - closed-world census of the "ambient git variables redirect git" class.

Purpose
  A script that runs git inherits the caller's repository-locating git variables. GIT_DIR beats
  `git -C <dir>` and `cd <dir>`, and GIT_INDEX_FILE names the index every index-writing command uses,
  so under a git hook (a pre-commit hook receives GIT_INDEX_FILE, wrappers set GIT_DIR) such a script
  writes into another repository: measured 2026-11-13 for scripts/gates/cm_agent_type_label.sh and
  scripts/gates/cm_anchor_record_complete.sh, and 2026-11-15 for scripts/gates/cm_rule_binds_to_seam.sh
  (`--selftest` exited 0 while it committed into a sentinel repository; git was called through `$GIT`).

  Round 3 (review of 005bcfd1, R3-1): detecting the CALL SHAPE of a git write is not a safe basis for
  membership. Git can be called through a variable (`$GIT init`, `"${G[@]}" commit`, `$GITBIN -C`), a
  helper whose name has no `git` in it (`g("init", ...)`), a list argument (`_git(repo, ["worktree",
  ...])`), and every new shape is one more false null. So the census is CLOSED-WORLD:

    universe  every tracked file of the repository (`git ls-files -s`, the WHOLE tree; round 4, R4-1:
              round 3 read scripts/ and tests/ only and missed install_upstreams.sh, find_constitution.sh,
              progressive/*.py, docs/qa/ repro scripts and others) that is code: shell (.sh .bash .zsh
              .ksh, a shell shebang, or an EXECUTABLE file without a shebang, which the kernel's ENOEXEC
              fallback runs as shell), python, javascript, Go, Makefiles and other code extensions or
              shebangs (judged by the write detector only). Closed-world accounting: every tracked path
              lands in exactly one bucket (gitlink, symlink, absent, binary, data, code); a path whose
              extension is in no closed list is UNCLASSIFIED and fails the run, and the inventory line
              must account for every tracked path or the run is BLIND. A data extension (.md, .txt,
              .json, ...) is data even with a shebang-like first line, unless the file is executable;
    member    a universe file whose text contains `git` in ANY form: the regular expression
              `(?<![A-Za-z])git`, case-insensitive, over the whole raw text (comments, strings, variable
              names such as GITBIN or GIT_DIR included). Over-inclusion is deliberate: a file that runs
              git must name it somewhere (directly, in a helper, in a variable value or in a path);
    rule      every member carries a FILE-LEVEL scrub of the class, or is in the checked-in list
              config/git_env_class_exemptions.tsv with a closed reason. Detection of the write form is
              no longer what keeps a member safe; it is only a second check on exempted rows.

  Statuses:
    HERMETIC   a file-level scrub that is effective:
               - shell: the canonical line `for _ge_v in <list>; do unset "$_ge_v"; done; unset _ge_v` at
                 column 0 in the file's preamble (only comments, blank lines, `set`, `shopt`, `umask` and
                 plain assignments before it);
               - python: `import os as _ge_os` + `for _ge_v in "<list>".split(): _ge_os.environ.pop(_ge_v,
                 None)` as top-level statements that only a docstring and import statements precede
                 (checked on the ast);
               - javascript: `for (const _ge_v of "<list>".split(" ")) delete process.env[_ge_v];` at
                 column 0 with only comments, blank lines and a 'use strict' directive before it;
               - shell: a `cl_scrub_git_env` call at top level (outside every function) before the first
                 detected write, or a reviewed own scrub at top level that names every variable of the
                 list AND clears exactly those names (an `unset` naming them, or a `for V in ...` loop
                 whose body runs `unset "$V"`; a no-op loop with an unrelated `unset` elsewhere is not a
                 scrub, review R3-2);
               the list must equal CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh word for word.
    EXEMPT     a member with no file-level scrub that is covered by a row of the exemption list; the row's
               reason is checked against what the file does (below).
    UNSCRUBBED a member with no file-level scrub and no valid row, a member whose scrub is not effective
               or clears a discovery LIMIT, or a row whose reason the file contradicts.

  Exemption reasons (closed set) and what the census checks for each:
    no-git-execution   the git words are text; FAIL if the write detector sees a git write in the file;
    sourced-library    a file `.`/`source`d into its caller's shell: a top-level scrub would clear the
                       caller's own variables, so any git it runs goes through a wrapper that scrubs in a
                       subshell, or it only reads; FAIL if a detected write is not inside a scrubbed wrapper;
    entry-function-scrub the file's code runs only through one entry function whose first statements clear
                       the list (kept there because the scrub prints a notice); FAIL unless the file holds a
                       list-operating clear naming every variable, the clear is IN the entry function and
                       before its first git mention or git-function call, top level neither mentions git
                       nor sources a file, and the last statement calls the entry function (R4-4);
    subject-follows-caller a read-only PreToolUse guard that must judge the repository the guarded command
                       acts on, which an ambient GIT_DIR selects; clearing it would make the guard check
                       the wrong repository (R4-7); FAIL if the write detector sees a git write (lines that
                       only print text with echo/printf, with no pipe, substitution, eval or chain, are
                       not counted for this row);
    pinned-fixture     a byte-pinned historical copy that a test compares or replays verbatim;
    fixture-tree       a row whose path ends with `/` and contains a `fixtures/` path component covers every
                       member below it (data trees of fake hooks, stub binaries, pinned copies); a member
                       under such a prefix in which the write detector sees a git write needs its own row;
    go-binary-owed     Go source compiled into a committed binary (owed, tracked).
  Readers of a sourced library (R4-2): every shell file that sources a file with a sourced-library row
  that has an unwrapped git call must itself be HERMETIC (or carry a sourced-library or
  entry-function-scrub row), because the library's git calls run in the reader's shell.
  Preamble (R4-3): only whole lines of `set <flags>`, `shopt -s/-u <names>`, `umask <octal>`, plain
  assignments, comments and blank lines may precede the canonical line; `set -e; git ...` is not a
  preamble line. A list-operating clear (R4-5) must loop over the canonical list (literal, or an array
  or variable assigned it) and must not sit inside a heredoc.
  A row that covers no member, or a row for a HERMETIC file, is a FAIL (stale row). The canonical library
  scripts/lib/constitution_layout.sh is built in as a sourced library (it defines the list and the scrub).

  The write detector (second check only) finds `git <write>`, `$VAR <write>` / `"${VAR[@]}" <write>` for a
  shell variable or array assigned a value that starts with git (or a path ending in /git, or
  `$(command -v git)`), `${X:-git}`, python list forms `["git", ..., "<write>"]`, python helper functions
  whose body runs "git" called with a writing subcommand (also as a list argument), shell wrapper functions
  (bodies that run git with "$@"), and Go `exec.Command("git", ..., "<write>")`.

  Discovery limits (round 2): GIT_CEILING_DIRECTORIES and GIT_DISCOVERY_ACROSS_FILESYSTEM do not redirect
  git, they bound (or, by the caller's explicit choice, widen) repository DISCOVERY. They must never be in
  the canonical list (else BLIND) and a scrub statement of a member that clears one is UNSCRUBBED.

Control needles (§11.4.273): before the tree is judged the classifier runs on built-in samples covering
  every status, every reason check and every detector form, including the round-3 shapes (`$GIT`,
  `"${G[@]}"`, `$GITBIN`, `g("init")`, `_git(repo, ["worktree"])`), a text-only member and a word that
  only contains the letters (`digit`, never a member). A wrong answer on any sample is BLIND. The
  inventory line prints how many tracked files, universe files and members were seen; zero universe files
  or zero members is BLIND.

Honest boundary (§11.4.6)
  Tracked files of this repository only: the contents of submodules (gitlinks), untracked files and
  files outside the checkout are not read; binaries (committed executables, archives) are counted as
  binary and not judged; data files (.md, .txt, .json, systemd units, templates, ...) are not code even
  when they hold shell text, so a template copied out and run elsewhere is judged where it runs. A file
  that runs git without the three letters anywhere in its text (a name built at run time, `"gi""t"`,
  base64, a path read from a file) is not a member; no static census can see that case. A file that runs a TOOL that runs git
  (`go build` stamps VCS data by calling git; another script) relies on that tool or script being a member
  itself. Go source is in the universe, but a Go file is a member only when the write detector sees
  a git write in it (`exec.Command("git", ..., "<write>")`), because no file-level scrub form is defined for
  Go (a scrub there needs a reviewed binary rebuild); such a member is UNSCRUBBED unless it has a row
  (R4-6). A python module that is imported (not run) pops the variables in
  the importing process too; that is accepted (the importers are scripts of this class). A sourced-library
  or entry-function-scrub row rests on a reviewed reading of the file plus the write detector, not on a
  decidable property. The class is the 14 repository-locating names; other git variables that change
  semantics are out of scope, among them GIT_CONFIG_* / GIT_CONFIG_PARAMETERS (config injection),
  identity, transport and template variables, GIT_LITERAL_PATHSPECS / GIT_GLOB_PATHSPECS /
  GIT_NOGLOB_PATHSPECS / GIT_ICASE_PATHSPECS (pathspec semantics: measured, GIT_LITERAL_PATHSPECS=1 makes
  `git add 'g*'` fail with "pathspec did not match", a possible false null for a gate that globs with git),
  GIT_ATTR_SOURCE (attributes read from a tree) and GIT_EXEC_PATH (where git finds its sub-commands; no
  effect on builtins measured). HERMETIC means an effective scrub is present and placed as above, not that
  every code path was run: the behaviour is shown separately by tests/test_git_env_class.sh with sentinel
  repositories.

Usage
  git_env_class_census.py [--root <repo>] [--exemptions <tsv>] [--tsv]
  --tsv prints one `<status>\t<lang>\t<path>\t<line>\t<detail>` row per member.

Exit codes
  0 every member is HERMETIC or EXEMPT; 1 at least one UNSCRUBBED member, a stale or malformed exemption
  row; 2 BLIND (no canonical list, a canonical list that holds a discovery limit, a control needle failed,
  git could not list the tree, or zero universe files or members were found); 64 usage.

Side effects: none; reads the tree through `git ls-files` run with the class cleared.
Dependencies: python3 (3.8+), git. Classification: universal (§11.4.17).
"""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
import ast
import io
import os
import re
import subprocess
import sys
import tokenize
import unicodedata

TOOL = "git-env-class-census"
REASONS = {
    "no-git-execution": "the git words are text (messages, patterns, payloads, comments); the file never runs git",
    "sourced-library": "sourced into the caller's shell; git runs only through a scrubbing wrapper, or is only read",
    "entry-function-scrub": "the file runs only through one entry function whose first statements clear the list",
    "pinned-fixture": "a byte-pinned historical copy that a test compares or replays verbatim; it is never run as an entry point",
    "fixture-tree": "a data tree under fixtures/ (fake hooks, stub binaries, pinned copies); prefix row",
    "go-binary-owed": "Go source compiled into a committed binary; the fix needs a reviewed rebuild of that binary (owed, tracked)",
    "subject-follows-caller": "a read-only guard that must inspect the same repository as the command it guards, which the caller's variables select; it runs no writing git command",
}
BUILTIN_LIBS = {
    "scripts/lib/constitution_layout.sh": "built-in sourced-library: defines CL_GIT_SCRUB_VARS, cl_scrub_git_env and the scrubbing wrapper cl__git",
}
# Discovery limits: bound (or, by explicit choice, widen) where git looks for a repository; never scrubbed.
LIMIT_VARS = ("GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM")
# merge(?!-base\b): `git merge-base` only reads (CON-046 round 13: a read-only pre-commit gate was read as writing)
# symbolic-ref with read flags only and ONE name (`symbolic-ref -q HEAD`) only reads (CON-046 round 14: the gate's
# broken-HEAD check, review r13 R13-4); a second argument (set) or -d / --delete (delete) is a write. The lookahead
# needs whitespace after the subcommand, so python and go argument lists stay classified as writes (conservative).
SYMREF_READ = r"""(?!(?:\s+(?:-q|--quiet|--short|--no-recurse))*\s+[^\s;&|)"'`<>-][^\s;&|)"'`<>]*\s*(?:[;&|)"'`]|[0-9]?>|$))"""
WRITE = (r"init|add|commit|config|branch|tag|checkout|switch|update-ref|update-index|read-tree|merge(?!-base\b)|reset|"
         r"stash|rm|mv|push|worktree|apply|am|cherry-pick|rebase|clone|submodule|fetch|pull|notes|gc|repack|"
         r"checkout-index|commit-tree|hash-object|symbolic-ref" + SYMREF_READ + r"|restore|clean|write-tree|fast-import|bundle|"
         r"pack-objects|prune|replace|filter-branch|mktree|mktag|unpack-objects|index-pack")
MENTION = re.compile(r"(?<![A-Za-z])git", re.I)
GOPT = r"(?:\s+(?:-C\s+\S+|-c\s+\S+|--[\w-]+(?:=\S+)?))*"
# shell: git as a word (or an absolute path ending in /git, or ${X:-git}), any global options, a writing subcommand
SH_GIT = r"(?:(?<![\w./$-])[\"']?(?:/(?:[\w.-]+/)*)?git\b[\"']?|\$\{\w+:-(?:/(?:[\w.-]+/)*)?git\})"
SH_RE = re.compile(SH_GIT + GOPT + r"\s+(?:" + WRITE + r")\b")
SH_GITWORD = re.compile(r"(?<![\w./$-])git\b")
# shell: a variable or array whose value starts with git: GIT="git -c x", G=(git -c x), GITBIN=/usr/bin/git, X=$(command -v git)
SH_VARASSIGN = re.compile(r"""(?:^|[\s;&|(])(?:export\s+|local\s+|readonly\s+|declare\s+(?:-\w+\s+)*)?([A-Za-z_]\w*)=\(?\s*["']?(?:(?:/(?:[\w.-]+/)*)?git\b|\$\((?:command\s+-v|which)\s+git\))""")
# python: ["git", ..., "<write>", ...] with only simple items before the subcommand
PY_RE = re.compile(r"""["']git["']\s*,\s*(?:(?:["'][^"'\n]*["']|[\w.\[\]]+)\s*,\s*)*["'](?:""" + WRITE + r""")["']""")
PYCALL_RE = re.compile(r"subprocess\.|os\.system\(|os\.popen\(|Popen\(|check_output\(|check_call\(|shell=True")
# python: a git wrapper called with a writing subcommand: git(repo, "commit"), _git("add"), _git(repo, ["worktree", ...])
PYW_RE = re.compile(r"""\b\w*git\w*\((?:[^,()"'\n]+,\s*)?\[?\s*["'](?:""" + WRITE + r""")["']""")
PY_DEF = re.compile(r"^(\s*)def\s+([A-Za-z_]\w*)\s*\(")
GO_RE = re.compile(r"""exec\.Command(?:Context)?\([^)]*"git"\s*,\s*(?:"[^"\n]*"\s*,\s*|[\w.*]+\s*,\s*)*"(?:""" + WRITE + r""")\"""")
CANON_SH = re.compile(r"""^for _ge_v in ([A-Z_ ]+); do unset "\$_ge_v"; done; unset _ge_v(?:\s+#.*)?$""")
CANON_SH_ANY = re.compile(r"""^\s*for _ge_v in ([A-Z_ ]+); do unset "\$_ge_v"; done; unset _ge_v(?:\s+#.*)?$""")
CANON_JS = re.compile(r"""^for \(const _ge_v of "([A-Z_ ]+)"\.split\(" "\)\) delete process\.env\[_ge_v\];(?:\s*//.*)?$""")
JS_PREAMBLE = re.compile(r"""^(?:\s*//.*|\s*/\*.*\*/\s*|\s*['"]use strict['"];?\s*)$""")
LIBCALL = re.compile(r"(?:^|[\s;&|(])cl_scrub_git_env\b")
LIB_WRAPPERS = ("cl__git",)   # defined in scripts/lib/constitution_layout.sh with a scrubbing body
LEGACY = re.compile(r"chi__git|jb__git|ls__git|\bscrub_git_env\b|^\s*unset (?:-v )?GIT_DIR|for _pu_v in GIT_DIR|for _v in GIT_DIR|"
                    r"for _fc_unset_var|GIT_SCRUB_VARS|^_git_scrub=\(", re.M)
SH_CLEARS = re.compile(r"\bunset\b|(?:^|\s)-u\s+\S")
# `{ set +o xtrace ...; } 2>/dev/null` is allowed so a tool that silences tracing first stays silent under a
# caller's SHELLOPTS=xtrace (scripts/fastcycle/tokens/dispatch_stamp.sh, test RV11-2: the scrub line must come after it)
PREAMBLE = re.compile(r"""^(?:set(?:[ \t]+(?:[-+][A-Za-z]+|[a-z]+|--))+[ \t]*$|shopt(?:[ \t]+-[su])+(?:[ \t]+[a-z_]+)+[ \t]*$|umask[ \t]+[0-7]{3,4}[ \t]*$|\{ set [+-]o [a-z]+(?: [+-]o [a-z]+)*; \} 2>/dev/null$|export\s+[A-Za-z_]\w*=[^$`();&|<>]*$|[A-Za-z_]\w*=[^$`();&|<>]*$)""")
FUNC_RE = re.compile(r"^(\s*)(?:function\s+)?([A-Za-z_][\w]*)\s*\(\)\s*(\{.*)?$")
# CON-450 round 4 (review R3-1 / R3-2 / R3-5, section 11.4.276(E) structural): a member is judged on the text its
# interpreter runs. Python's str.lstrip / strip / isspace and `\s` treat CR, VT, FF, FS..US, NEL, NBSP and the other
# Unicode spaces as blank; bash treats only SPACE and TAB as blank and LF as the only line end, so `\r#;cmd` or
# `<NBSP>#;cmd` was a comment to this census and a command to bash (measured: the scrub defeated, the census PASS).
# The census therefore admits a CLOSED ALLOW-LIST and refuses the rest, fail-closed (READING_PROBLEM below):
#   shell   every character: TAB, LF or printable ASCII, or a non-ASCII character of a Unicode category L M N P S that
#           str.isspace() does not accept (CR, NUL..US but TAB / LF, DEL anywhere are refused);
#           every line: the first character after its SPACE / TAB run is printable ASCII or such a character;
#           line 1: a `#!` line is one of SH_SHEBANGS exactly (a file run directly runs its shebang's arguments first);
#           the preamble (every line up to and including the first canonical-looking scrub line): a full-line comment
#           may carry the characters above (no U+FFFD, the mark of a byte that is not UTF-8); any other line is TAB /
#           printable ASCII only;
#   python  no CR (the interpreter ends a line at a lone CR, measured: `# c\ry=2` runs y=2; this census numbers lines
#           by LF);
#   js      no CR, U+2028 or U+2029 (JavaScript line terminators).
SH_SHEBANGS = ("#!/usr/bin/env bash", "#!/bin/bash", "#!/bin/sh", "#!/system/bin/sh")
SH_COMMENT_LINE = re.compile(r"[ \t]*#")


def _ok_char(ch, ascii_only=False):
    o = ord(ch)
    if ch == "\t" or 0x20 <= o <= 0x7e:
        return True
    return (not ascii_only and o >= 0x80 and ch != "\ufffd" and unicodedata.category(ch)[0] in "LMNPS"
            and not ch.isspace())


def reading_problem(lang, text):
    """(line, reason) where the file leaves what this census models of its interpreter's reading, or None."""
    if lang in ("py", "js"):
        bad = "\r" if lang == "py" else "\r\u2028\u2029"
        for no, l in enumerate(text.split("\n"), 1):
            for ch in l:
                if ch in bad:
                    return no, ("U+%04X ends a line for the %s interpreter but not for this census (lines split on LF); "
                                "not modelled, fail-closed (CON-450 r4)" % (ord(ch), lang))
        return None
    if lang != "sh":
        return None
    lines = text.split("\n")
    canon_at = next((i for i, l in enumerate(lines, 1) if CANON_SH_ANY.match(l)), 0)
    for no, l in enumerate(lines, 1):
        if no == 1 and l.startswith("#!") and l not in SH_SHEBANGS:
            return no, ("line 1 is a #! line outside the closed set (%s): a file run directly runs its shebang's "
                        "arguments before line 2; not modelled, fail-closed (CON-450 r4)" % ", ".join(SH_SHEBANGS))
        com = bool(SH_COMMENT_LINE.match(l))
        pre = no <= canon_at
        rest = l.lstrip(" \t")
        for col, ch in enumerate(l, 1):
            o = ord(ch)
            if (ch != "\t" and o < 0x20) or o == 0x7f or (pre and not _ok_char(ch, ascii_only=not com)):
                return no, ("column %d holds U+%04X (%s, %s)%s: bash and this census read it differently; not "
                            "modelled, fail-closed (CON-450 r4)" % (col, o, unicodedata.name(ch, "unnamed"),
                                                                    unicodedata.category(ch),
                                                                    " in the preamble" if pre else ""))
        if rest and not _ok_char(rest[0]) and rest[0] != "\ufffd":
            return no, ("the first character after the blanks is U+%04X (%s, %s): blank to Python, a word to bash; not "
                        "modelled, fail-closed (CON-450 r4)" % (ord(rest[0]), unicodedata.name(rest[0], "unnamed"),
                                                                unicodedata.category(rest[0])))
    return None
# Round 4 (R4-1): the universe is every tracked file. A text file is data only when its extension is in this closed
# list (or it has no extension, no shebang and no executable bit); any other extension is UNCLASSIFIED and the census
# FAILs, so a new kind of file can never fall silently outside the census. Systemd units, templates and configs are
# data here: a command they name is a tracked script (a member in its own right) or an external program.
DATA_EXT = ("md", "txt", "json", "jsonl", "tsv", "yaml", "yml", "lock", "html", "html5", "pdf", "docx", "csv", "toml",
            "cfg", "ini", "svg", "png", "sum", "mod", "sql", "log", "out", "err", "diff", "patch", "template", "tmpl",
            "example", "list", "sha256", "config", "conf", "css", "roster", "mdy", "summary", "service", "timer",
            "precheck-evidence", "canon", "xml", "rst", "gif", "jpg", "jpeg", "ico", "pub", "asc", "bundle", "gz", "tar", "zip")
# Jev round 12 (review of a1eeb0d7, R11-C): `.rc` and `.ls` are NOT data extensions. A blanket extension rule made every
# non-executable `*.rc` / `*.ls` file data, so a file of that name holding git writes was no longer counted. A file with
# one of these extensions is data only when it is not executable, lies under docs/qa/, and its WHOLE content has the
# captured shape: `.rc` one exit status (an integer 0 to 255, optional newline); `.ls` an `ls -l` listing (a `total N`
# line, then only listing lines). Any other `.rc` / `.ls` file stays UNCLASSIFIED and fails the run (closed world).
# Jev round 13 (R12-B2): re.ASCII, so a digit is 0-9 and a space is an ASCII space (a Unicode digit such as U+0661 or a
# Unicode space such as U+2003 never makes a line listing-shaped).
LS_LINE = re.compile(r"^[-dlcbpsD][rwxsStT-]{9}[.+@]?\s+\d+\s+\S+\s+\S+\s+\d+\s+[A-Z][a-z]{2}\s+\d{1,2}\s+(?:\d{1,2}:\d{2}|\d{4})\s+\S.*$", re.ASCII)


def shaped_data(path, ext, text, executable):
    """True when an `.rc` / `.ls` file is a captured evidence record of the declared shape (see the note above)."""
    if executable or ext not in ("rc", "ls") or not path.startswith("docs/qa/"):
        return False
    # round 12: a listing line may carry any file name (`\S.*$`), so a record that names git is never data by shape.
    # Round 13 (R12-B2): the SAME definition the member detector uses (MENTION, case-insensitive, letter boundary only),
    # so no text the detector counts as a git mention (GIT, Git, _git, 1git, gitx, ${G,,} after G=GIT) is data by shape.
    if MENTION.search(text):
        return False
    if ext == "rc":
        m = re.fullmatch(r"(\d{1,3})\n?", text, re.ASCII)
        return bool(m) and int(m.group(1)) <= 255
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if len(lines) < 1 or not re.fullmatch(r"total \d+", lines[0], re.ASCII):
        return False
    return all(LS_LINE.match(ln) for ln in lines[1:])


SKIP_EXT = re.compile(r"\.(" + "|".join(re.escape(e) for e in DATA_EXT) + r")$")
OTHER_CODE_EXT = (".fish", ".pl", ".pm", ".rb", ".lua", ".ps1", ".ts", ".tcl", ".awk", ".sed", ".exp", ".php")
CODE_EXT = (".sh", ".bash", ".zsh", ".ksh", ".py", ".go", ".js", ".mjs", ".cjs", ".mk") + OTHER_CODE_EXT


def lang_of(path, head, executable=False):
    """sh, py, js, go, other:<interpreter> or None (data).
    Round 4 (R4-1): `.zsh`/`.ksh` are shell, `.fish`, Makefiles and other script extensions are code of their own
    language, and a tracked file with the executable bit and no shebang is shell (the kernel refuses it with
    ENOEXEC and the calling shell runs it as a shell script)."""
    if path.endswith((".sh", ".bash", ".zsh", ".ksh")):
        return "sh"
    base = path.rsplit("/", 1)[-1]
    if base in ("Makefile", "makefile", "GNUmakefile") or path.endswith(".mk"):
        return "other:make"
    for ext in OTHER_CODE_EXT:
        if path.endswith(ext):
            return "other:" + ext[1:]
    if path.endswith(".py"):
        return "py"
    if path.endswith(".go"):
        return "go"
    if path.endswith((".js", ".mjs", ".cjs")):
        return "js"
    first = head.split("\n", 1)[0]
    if first.startswith("#!"):
        if re.search(r"\b(ba|da|z|k)?sh\b", first):
            return "sh"
        if "python" in first:
            return "py"
        if re.search(r"\bnode\b", first):
            return "js"
        return "other:" + first[2:].strip().split("/")[-1][:30]
    if executable:
        return "sh"
    return None


def strip_sh_comment(line):
    """The line without a shell comment (a `#` at the start of a word, outside quotes)."""
    q = None
    i = 0
    while i < len(line):
        c = line[i]
        if q is None:
            if c == "\\":
                i += 2
                continue
            if c in "'\"":
                q = c
            elif c == "#" and (i == 0 or line[i - 1] in " \t;&|("):
                return line[:i]
        elif c == q:
            q = None
        elif c == "\\" and q == '"':
            i += 2
            continue
        i += 1
    return line


def code_lines(lang, text):
    """List of the file's lines with comments (and python docstrings) blanked; same line numbering."""
    lines = text.split("\n")
    if lang == "sh":
        return [strip_sh_comment(l) if not SH_COMMENT_LINE.match(l) else "" for l in lines]   # bash blanks only (r4)
    if lang in ("go", "js"):
        return ["" if l.lstrip().startswith("//") else l for l in lines]
    if lang != "py":
        return ["" if l.lstrip().startswith("#") else l for l in lines]
    out = list(lines)
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.COMMENT:
                r, c = tok.start
                out[r - 1] = out[r - 1][:c]
        tree = ast.parse(text)
        for node in ast.walk(tree):
            if isinstance(node, ast.Expr) and isinstance(getattr(node, "value", None), ast.Constant) \
                    and isinstance(node.value.value, str):
                for r in range(node.lineno, node.end_lineno + 1):
                    out[r - 1] = ""
    except (SyntaxError, tokenize.TokenError, ValueError):
        out = ["" if l.lstrip().startswith("#") else l for l in lines]
    return out


def sh_functions(code):
    """{name: (start, end, body_text)} for shell functions (one-line or block), 1-based lines."""
    funcs = {}
    n = len(code)
    i = 0
    while i < n:
        m = FUNC_RE.match(code[i])
        if not m:
            i += 1
            continue
        indent, name, rest = m.group(1), m.group(2), m.group(3) or ""
        if rest.count("{") and rest.rstrip().endswith("}") and rest.count("{") <= rest.count("}"):
            funcs[name] = (i + 1, i + 1, rest)
            i += 1
            continue
        body = [rest]
        j = i + 1
        while j < n and j < i + 400:
            body.append(code[j])
            if re.match(r"^" + re.escape(indent) + r"\}\s*;?\s*$", code[j]) or (indent == "" and re.match(r"^\}\s*$", code[j])):
                break
            j += 1
        funcs[name] = (i + 1, min(j + 1, n), "\n".join(body))
        i = j + 1
    return funcs


def names_all(text, canon):
    """Every variable of the list is named in the text outside heredoc bodies (round 4, R4-5)."""
    hd = heredoc_blank(text)
    return all(re.search(r"\b" + v + r"\b", hd) for v in canon)


HEREDOC_RE = re.compile(r"""(?<![<\w])<<(?!<)(-?)\s*(["']?)([A-Za-z_]\w*)\2""")


def heredoc_blank(text):
    """The text with every heredoc body replaced by blank lines (same numbering): a heredoc is data for the shell
    that reads it, so a scrub written there clears nothing (round 4, R4-5)."""
    out = []
    pending = []
    for line in text.split("\n"):
        if pending:
            word, dash = pending[0]
            out.append("")
            if (line.lstrip("\t") if dash else line) == word:
                pending.pop(0)
            continue
        out.append(line)
        for m in HEREDOC_RE.finditer(strip_sh_comment(line)):
            pending.append((m.group(3), m.group(1) == "-"))
    return "\n".join(out)


KEEP_QUOTED = re.compile(r"^(?:[A-Za-z_]\w*|\$[A-Za-z_]\w*|\$\{[A-Za-z_]\w*(?:\[[@*]\])?\})$")


def quote_blank(text):
    """The text with the content of every quoted string replaced by `x` (newlines kept), except a string that is one
    bare name or one expansion ("$_v", "${arr[@]}", "GIT_DIR"): text inside a string is a payload, not a statement
    (round 4, R4-5)."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;&|("):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        if c in "'\"":
            j = i + 1
            while j < n and text[j] != c:
                if c == '"' and text[j] == "\\":
                    j += 1
                j += 1
            body = text[i + 1:j]
            if KEEP_QUOTED.match(body):
                out.append(c + body + c)
            else:
                out.append(c + "".join("\n" if ch == "\n" else "x" for ch in body) + c)
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


UNSET_AT_CMD = re.compile(r"(?:^|[;&|({]|\bthen\b|\bdo\b|\belse\b)[ \t]*unset[ \t]+(?:-v[ \t]+)?(?:--[ \t]+)?([^;&|\n]*)", re.M)
FOR_IN = re.compile(r"(?:^|[;&|({]|\bthen\b|\bdo\b|\belse\b)[ \t]*for[ \t]+([A-Za-z_]\w*)[ \t]+in[ \t]+([^;\n]*?)[ \t]*(?:;|\n)[ \t\n]*do\b", re.M)


def loop_words(words, hd):
    """The names a `for V in <words>` list expands to, resolving "${ARR[@]}" and "$V" against array and string
    assignments of the same text (heredoc bodies excluded); None when a word cannot be resolved."""
    names = set()
    for w in words.split():
        w = w.strip("\"'")
        m = re.match(r"^\$\{([A-Za-z_]\w*)\[[@*]\]\}$", w)
        if m:
            am = None
            for am in re.finditer(r"(?:^|[\s;&|(])(?:local\s+|declare\s+-a\s+|readonly\s+)?" + re.escape(m.group(1)) + r"=\(([^)]*)\)", hd):
                pass
            if am is None:
                return None
            names.update(x.strip("\"'") for x in am.group(1).split())
            continue
        m = re.match(r"^\$\{?([A-Za-z_]\w*)\}?$", w)
        if m:
            vm = None
            for vm in re.finditer(r"(?:^|[\s;&|(])(?:local\s+|readonly\s+|export\s+)?" + re.escape(m.group(1)) + r"=([\"']?)([^\"'\n]*)\1", hd):
                pass
            if vm is None:
                return None
            names.update(vm.group(2).split())
            continue
        if re.match(r"^[A-Za-z_]\w*$", w):
            names.add(w)
            continue
        return None
    return names


def list_clear_at(text, canon):
    """Line number (1-based) of the first statement that clears exactly the list, or 0: an `unset` at command
    position naming every variable, or a `for V in <list>` loop whose list expands to every variable and whose body
    runs `unset "$V"`. Heredoc bodies, comments and string payloads never count (round 4, R4-5: an unset loop over
    another list, or an `unset LIST` inside a heredoc, is a carrier)."""
    hd = heredoc_blank(text)
    nq = quote_blank(hd)
    joined = re.sub(r"\\\n", "  ", nq)
    hits = []
    for m in UNSET_AT_CMD.finditer(joined):
        if all(re.search(r"(?<![\w$])" + v + r"\b", m.group(1)) for v in canon):
            hits.append(m.start(1))
    for m in FOR_IN.finditer(joined):
        var = m.group(1)
        names = loop_words(m.group(2), hd)
        if names is None or not set(canon) <= names:
            continue
        tail = joined[m.end():m.end() + 4000]
        dm = re.search(r"\bdone\b", tail)
        body = tail[:dm.start()] if dm else tail
        if re.search(r"""(?:^|[;&|({]|\bthen\b|\bdo\b|\belse\b)?[ \t]*\bunset[ \t]+(?:-v[ \t]+)?(?:--[ \t]+)?["']?\$\{?""" + re.escape(var) + r"""\b""", body):
            hits.append(m.start(1))
    if not hits:
        return 0
    return joined[:min(hits)].count("\n") + 1


def list_clear(text, canon):
    """True iff the text holds a statement that clears exactly the list (see list_clear_at)."""
    return list_clear_at(text, canon) > 0


SOURCE_RE = re.compile(r"(?:^|[\s;&|(])(?:\.|source)\s+[\"'$\w/~.{]", re.M)
SH_GITCALL = re.compile(r"(?:(?<![\w./$-])[\"']?(?:/(?:[\w.-]+/)*)?git\b[\"']?|\$\{\w+:-(?:/(?:[\w.-]+/)*)?git\})" + r"(?:\s+(?:-C\s+\S+|-c\s+\S+|--[\w-]+(?:=\S+)?))*" + r"\s+[A-Za-z-]")


def unwrapped_git_calls(text, canon):
    """[(line, src)] of shell lines that run git (any subcommand, read or write) outside a function whose body
    scrubs (a scrubbing wrapper or a function with its own clear): the calls a sourcing caller's environment
    reaches (round 4, R4-2)."""
    code = code_lines("sh", heredoc_blank(text))
    gv = git_vars(code)
    wraps, funcs = wrappers(code, canon, gv)
    covered = [(s, e) for name, (s, e, body) in funcs.items() if wraps.get(name) or block_scrubs(body, canon)]
    vre = None
    if gv:
        vre = re.compile(r"""["']?\$\{?(?:""" + "|".join(re.escape(v) for v in sorted(gv)) + r""")(?:\[[@*]\])?\}?["']?\s+[A-Za-z-]""")
    out = []
    for i, line in enumerate(code, 1):
        if not line.strip() or any(s <= i <= e for s, e in covered):
            continue
        if SH_GITCALL.search(line) or (vre is not None and vre.search(line)):
            out.append((i, line.strip()))
    return out


ENTRY_CALL = re.compile(r'^\s*(?:exec\s+)?([A-Za-z_]\w*)(?:\s+"\$@")?\s*(?:;\s*)?(?:exit\s+\$\?\s*)?$')


def entry_function_problem(text, canon):
    """None when the file runs only through one entry function that clears the list before its first git use, else
    the reason (round 4, R4-4): the top level (every function body blanked) must not mention git or source a file;
    the last top-level statement calls the entry function; every other function called at top level must not
    mention git; inside the entry function no line before the clear mentions git or calls a function that does."""
    code = code_lines("sh", text)
    funcs = sh_functions(code)
    tl = top_level(code, funcs)
    last = 0
    for i, l in enumerate(tl, 1):
        if not l.strip():
            continue
        last = i
        if MENTION.search(l):
            return "the top level (outside every function) mentions git at line %d: %s" % (i, l.strip()[:100])
        if SOURCE_RE.search(l):
            return "the top level sources a file at line %d (its code would run before the entry function's clear)" % i
    if not last:
        return "no top-level statement calls an entry function"
    m = ENTRY_CALL.match(tl[last - 1])
    if not m or m.group(1) not in funcs:
        return "the last top-level statement (line %d) is not a call of a function of this file" % last
    entry = m.group(1)
    gitfuncs = {n for n, (_s, _e, body) in funcs.items() if MENTION.search(body)}
    toptext = "\n".join(tl)
    for n in sorted(gitfuncs - {entry}):
        if re.search(r"(?<![\w-])" + re.escape(n) + r"\b", toptext):
            return "function %s, called at top level, mentions git (it runs before the entry function's clear)" % n
    s, e, body = funcs[entry]
    lines = body.split("\n")
    at = list_clear_at(body, canon)
    if not at:
        return "the entry function %s holds no statement that clears every variable of the list" % entry
    for k, l in enumerate(lines[:at - 1], 1):
        if k == 1:
            l = re.sub(r"^\s*(?:function\s+)?\w+\s*\(\)\s*\{?", "", l)
        if MENTION.search(l):
            return "line %d of the entry function %s mentions git before the clear" % (s + k - 1, entry)
        for n in sorted(gitfuncs - {entry}):
            if re.search(r"(?<![\w-])" + re.escape(n) + r"\b", l):
                return "line %d of the entry function %s calls %s, which mentions git, before the clear" % (s + k - 1, entry, n)
    return None


def block_scrubs(body, canon):
    """True iff a function body really clears the class (canonical line, library call, or own scrub)."""
    for l in body.split("\n"):
        m = CANON_SH_ANY.match(l)
        if m and m.group(1).split() == canon:
            return True
    if LIBCALL.search(body) or re.search(r"\bcl__git\b", body):
        return True
    # `env -i ... git`: git runs in an environment built from nothing, so no caller variable reaches it
    if re.search(r"(?<![\w./$-])env\s+-i\b(?:[^;&|\n]|\\\n)*?(?<![\w./$-])git\b", body):
        return True
    return names_all(body, canon) and list_clear(body, canon)


def git_vars(code):
    """Names of shell variables/arrays assigned a value that starts with git."""
    out = set()
    for l in code:
        for m in SH_VARASSIGN.finditer(l):
            out.add(m.group(1))
    return out


def py_helpers(code):
    """Names of python functions (also in shell heredocs) whose body runs "git"."""
    out = set()
    n = len(code)
    for i, l in enumerate(code):
        m = PY_DEF.match(l)
        if not m:
            continue
        ind = len(m.group(1))
        body = []
        for j in range(i + 1, min(n, i + 200)):
            lj = code[j]
            if lj.strip() and (len(lj) - len(lj.lstrip())) <= ind:
                break
            body.append(lj)
        if re.search(r"""["']git["']|["']git\s""", "\n".join(body)):
            out.add(m.group(2))
    return out


def wrappers(code, canon, gvars):
    """{name: scrubbed?} for shell wrapper functions: the body runs git (or another wrapper) with "$@"."""
    funcs = sh_functions(code)
    out = {}
    vre = None
    if gvars:
        vre = re.compile(r"""\$\{?(?:""" + "|".join(re.escape(v) for v in sorted(gvars)) + r""")\b""")
    for name, (_s, _e, body) in funcs.items():
        if name == "git":
            continue
        if (SH_GITWORD.search(body) or (vre is not None and vre.search(body))) and re.search(r'"\$@"|\$@|"\$\*"', body):
            out[name] = block_scrubs(body, canon)
    known = dict(out)
    known.update({w: True for w in LIB_WRAPPERS})
    changed = True
    while changed:   # a wrapper of a wrapper inherits the callee's verdict
        changed = False
        for name, (_s, _e, body) in funcs.items():
            if name in known or name == "git":
                continue
            for w, sc in list(known.items()):
                if re.search(r"(?<![\w./$-])" + re.escape(w) + r"\b", body) and re.search(r'"\$@"|\$@', body):
                    known[name] = sc or block_scrubs(body, canon)
                    out[name] = known[name]
                    changed = True
                    break
    for w in LIB_WRAPPERS:
        out.setdefault(w, True)
    return out, funcs


def writes(lang, code, wraps):
    """[(line, src, via)] for every detected writing git command; via is None (bare) or the wrapper's name."""
    found = []
    wre = None
    if wraps:
        wre = re.compile(r"(?<![\w./$-])(" + "|".join(re.escape(w) for w in sorted(wraps, key=len, reverse=True)) + r")"
                         + GOPT + r"\s+(?:" + WRITE + r")\b")
    gvars = git_vars(code) if lang == "sh" else set()
    vre = None
    if gvars:
        vre = re.compile(r"""["']?\$\{?(?:""" + "|".join(re.escape(v) for v in sorted(gvars)) + r""")(?:\[[@*]\])?\}?["']?"""
                         + GOPT + r"\s+(?:" + WRITE + r")\b")
    helpers = py_helpers(code) if lang in ("sh", "py") else set()
    hre = None
    if helpers:
        hre = re.compile(r"""(?<![\w.])(?:""" + "|".join(re.escape(h) for h in sorted(helpers)) + r""")\((?:[^()\n]*?,\s*)?\[?\s*["'](?:"""
                         + WRITE + r""")["']""")
    for i, line in enumerate(code, 1):
        if not line.strip():
            continue
        hit = None
        if lang == "sh":
            if SH_RE.search(line) or PY_RE.search(line) or PYW_RE.search(line) or (vre is not None and vre.search(line)) \
                    or (hre is not None and hre.search(line)):
                hit = (i, line.strip(), None)
            elif wre is not None:
                m = wre.search(line)
                if m:
                    hit = (i, line.strip(), m.group(1))
        elif lang == "py":
            if PY_RE.search(line) or PYW_RE.search(line) or (SH_RE.search(line) and PYCALL_RE.search(line)) \
                    or (hre is not None and hre.search(line)):
                hit = (i, line.strip(), None)
        elif lang == "js":
            if re.search(r"""["']git["']\s*,\s*\[?\s*["'](?:""" + WRITE + r""")["']""", line) or \
                    re.search(r"""\bgit\w*\([^()\n]*\[\s*["'](?:""" + WRITE + r""")["']""", line):
                hit = (i, line.strip(), None)
        elif lang == "go" and GO_RE.search(line):
            hit = (i, line.strip(), None)
        if hit:
            found.append(hit)
    return found


def py_top_scrub(text, canon):
    """(line, words) of a top-level canonical python scrub that only a docstring and imports precede, or
    None; (line, None) when the form exists at top level but after other statements."""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return None
    alias = False
    late = False
    for idx, node in enumerate(tree.body):
        if isinstance(node, ast.Import) and any(a.name == "os" and a.asname == "_ge_os" for a in node.names):
            alias = True
            continue
        if alias and isinstance(node, ast.For) and isinstance(node.target, ast.Name) and node.target.id == "_ge_v":
            it = node.iter
            if (isinstance(it, ast.Call) and isinstance(it.func, ast.Attribute) and it.func.attr == "split"
                    and isinstance(it.func.value, ast.Constant) and isinstance(it.func.value.value, str)
                    and len(node.body) == 1 and isinstance(node.body[0], ast.Expr)):
                c = node.body[0].value
                ok = (isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute) and c.func.attr == "pop"
                      and isinstance(c.func.value, ast.Attribute) and c.func.value.attr == "environ"
                      and isinstance(c.func.value.value, ast.Name) and c.func.value.value.id == "_ge_os"
                      and len(c.args) == 2 and isinstance(c.args[0], ast.Name) and c.args[0].id == "_ge_v")
                if ok:
                    return (node.lineno, None if late else it.func.value.value.split())
        if idx == 0 and isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            continue
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            continue
        late = True
    return None


def sh_top_scrub(code_raw, code):
    """(line, words) of a canonical shell scrub at column 0 in the preamble, or None."""
    for i, raw in enumerate(code_raw, 1):
        c = code[i - 1].strip(" \t")
        if i == 1 and raw.startswith("#!"):
            continue
        m = CANON_SH.match(raw)
        if m:
            return i, m.group(1).split()
        if not c:
            continue
        # a preamble statement is one whole line: balanced quotes, no continuation (else the next line could be
        # inside a multi-line string, where a canonical-looking line is text, not a statement)
        if not PREAMBLE.match(c) or c.count('"') % 2 or c.count("'") % 2 or c.endswith("\\"):
            return None
    return None


def js_top_scrub(raw):
    """(line, words) of the canonical javascript scrub in the preamble, or None."""
    for i, l in enumerate(raw, 1):
        if i == 1 and l.startswith("#!"):
            continue
        m = CANON_JS.match(l)
        if m:
            return i, m.group(1).split()
        if not l.strip() or JS_PREAMBLE.match(l):
            continue
        return None
    return None


def limit_hits(lang, text, code):
    """[(line, name)] where a scrub statement clears a discovery limit."""
    hits = []
    if lang == "sh":
        i = 0
        while i < len(code):
            j = i
            logical = code[i]
            while logical.rstrip().endswith("\\") and j + 1 < len(code):
                j += 1
                logical = logical.rstrip()[:-1] + " " + code[j]
            logical = re.sub(r"'[^']*'", lambda m: "'" + " " * (len(m.group(0)) - 2) + "'", logical)  # payload text in quotes
            clearing = SH_CLEARS.search(logical) or re.match(r"^\s*for\s+\w+\s+in\b", logical)
            if clearing:
                for v in LIMIT_VARS:
                    for m in re.finditer(r"\b" + v + r"\b", logical):
                        a, b = m.start(), m.end()
                        before = logical[a - 1] if a else " "
                        after = logical[b] if b < len(logical) else " "
                        if before == "|" or after in "|)" or after == "=" or before == "$" or logical[max(0, a - 2):a] == "${":
                            continue   # a case pattern (keep-list), an assignment or an expansion
                        hits.append((i + 1, v))
            i = j + 1
    elif lang == "py":
        try:
            tree = ast.parse(text)
        except SyntaxError:
            return hits
        for node in ast.walk(tree):
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                tg = node.targets if isinstance(node, ast.Assign) else [node.target]
                names = [t.id for t in tg if isinstance(t, ast.Name)]
                if any(re.search(r"SCRUB|UNSET|CLEAR", n, re.I) for n in names):
                    for c in ast.walk(node.value):
                        if isinstance(c, ast.Constant) and isinstance(c.value, str):
                            for v in LIMIT_VARS:
                                if re.search(r"\b" + v + r"\b", c.value):
                                    hits.append((node.lineno, v))
            if isinstance(node, ast.For) and isinstance(node.target, ast.Name) and node.target.id == "_ge_v":
                for c in ast.walk(node.iter):
                    if isinstance(c, ast.Constant) and isinstance(c.value, str):
                        for v in LIMIT_VARS:
                            if re.search(r"\b" + v + r"\b", c.value):
                                hits.append((node.lineno, v))
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in ("pop", "unsetenv") \
                    and node.args and isinstance(node.args[0], ast.Constant) and node.args[0].value in LIMIT_VARS:
                hits.append((node.lineno, node.args[0].value))
    elif lang == "js":
        for i, l in enumerate(code, 1):
            if "delete process.env" in l or "_ge_v" in l:
                for v in LIMIT_VARS:
                    if v in l:
                        hits.append((i, v))
    return hits


def top_level(code, funcs):
    """The code with every shell function body blanked (same numbering)."""
    out = list(code)
    for _n, (s, e, _b) in funcs.items():
        for r in range(s, e + 1):
            out[r - 1] = ""
    return out


def judge(lang, text, canon):
    """-> (status, line, detail, writes) for one file; status in
       None      not a member (no `git` in the text, or Go without a detected write);
       HERMETIC  effective file-level scrub;
       UNSCRUBBED with a reason;
       NOSCRUB   a member with no file-level scrub and no detected write outside a scrubbed wrapper
                 (it needs a row of the exemption list or the canonical line);
       WRAPPER   no file-level scrub, every detected write goes through a scrubbed wrapper (needs a
                 sourced-library row or the canonical line)."""
    raw = text.split("\n")
    mm = MENTION.search(text)
    if mm is None:
        return None, 0, "", []
    mline = text[:mm.start()].count("\n") + 1
    rp = reading_problem(lang, text)
    if rp is not None:
        return "UNSCRUBBED", rp[0], rp[1], []
    code = code_lines(lang, text)
    gv = git_vars(code) if lang == "sh" else set()
    wraps, funcs = (wrappers(code, canon, gv) if lang == "sh" else ({}, {}))
    ws = writes(lang, code, wraps)
    if lang == "go":
        if not ws:
            return None, 0, "", []
        return "UNSCRUBBED", ws[0][0], "Go: " + ws[0][1][:150], ws
    if lang.startswith("other:"):
        return "NOSCRUB", mline, "language %s has no canonical scrub form; mentions git at line %d" % (lang[6:], mline), ws
    covered_ranges = [(s, e) for n, (s, e, _b) in funcs.items() if wraps.get(n)]
    top = None
    lib = None
    if lang == "sh":
        top = sh_top_scrub(raw, code)
        if top is None:
            for i, l in enumerate(raw, 1):
                m = CANON_SH_ANY.match(l)
                if m and not any(s <= i <= e for s, e in covered_ranges):
                    return "UNSCRUBBED", i, "canonical scrub line at line %d is not effective (not at column 0 in the preamble: inside a block, a function or after other code)" % i, ws
    elif lang == "py":
        top = py_top_scrub(text, canon)
        if top is not None and top[1] is None:
            return "UNSCRUBBED", top[0], "python scrub at line %d is not effective (other top-level statements than a docstring and imports come before it)" % top[0], ws
        if top is None and re.search(r"^\s*for _ge_v in ", text, re.M):
            m = re.search(r"^\s*for _ge_v in ", text, re.M)
            at = text[:m.start()].count("\n") + 1
            if code[at - 1].strip():
                return "UNSCRUBBED", at, "python scrub at line %d is not effective (not the top-level `_ge_os.environ.pop` form)" % at, ws
    elif lang == "js":
        top = js_top_scrub(raw)
        if top is None and "_ge_v" in text:
            m = re.search(r"_ge_v", text)
            return "UNSCRUBBED", text[:m.start()].count("\n") + 1, "javascript scrub is not effective (not the canonical line at column 0 in the preamble)", ws
    if top is not None and top[1] != canon:
        return "UNSCRUBBED", top[0], "canonical scrub line with a list that differs from CL_GIT_SCRUB_VARS", ws
    if top is None and lang == "sh":
        tl = "\n".join(top_level(code, funcs))
        if LIBCALL.search(tl):
            lib = "calls the library scrub (cl_scrub_git_env) at top level"
        elif LEGACY.search("\n".join(code)) and names_all(tl, canon) and list_clear(tl, canon):
            lib = "own reviewed scrub at top level naming and clearing every variable of the list"
    for line, src, via in ws:
        if top is not None:
            if top[0] < line:
                continue
            return "UNSCRUBBED", line, "canonical scrub at line %d comes after the first git write at line %d" % (top[0], line), ws
        if lib is not None:
            continue
        if via is not None and wraps.get(via):
            continue
        if any(s <= line <= e for s, e in covered_ranges):
            continue
        if via is not None:
            return "UNSCRUBBED", line, "no file-level scrub; write through wrapper %s, which does not scrub: %s" % (via, src[:120]), ws
        return "UNSCRUBBED", line, "no file-level scrub; git write: %s" % src[:150], ws
    lh = limit_hits(lang, text, code)
    if lh:
        return "UNSCRUBBED", lh[0][0], "the scrub at line %d clears the discovery limit %s (a caller's fence; never scrubbed)" % lh[0], ws
    if top is not None:
        return "HERMETIC", top[0], "canonical scrub at line %d" % top[0], ws
    if lib is not None:
        return "HERMETIC", mline, lib, ws
    if ws:
        return "WRAPPER", ws[0][0], "no file-level scrub; every detected write goes through a scrubbed wrapper", ws
    return "NOSCRUB", mline, "mentions git (first at line %d) and has no file-level scrub" % mline, ws


# A line that only prints text (echo/printf, no pipe, substitution, eval, `;` or `&`-chain) runs no git;
# used ONLY for the subject-follows-caller row, whose files print usage hints such as "git add <paths>".
ECHO_ONLY = re.compile(r"""^(?:echo|printf)\b(?!.*(?:\||`|\$\(|\beval\b|;|&&|\bsh\b|\bbash\b))""")


def apply_row(status, line, detail, ws, row, text, canon):
    """Combine the file's own status with its exemption row -> (status, line, detail)."""
    if row is None:
        if status == "NOSCRUB":
            return "UNSCRUBBED", line, detail + " and no row in the exemption list (add the canonical line, or a justified row)"
        if status == "WRAPPER":
            return "UNSCRUBBED", line, detail + " but has no file-level scrub and no sourced-library row"
        return status, line, detail
    reason, just, prefix = row
    if status == "HERMETIC" and prefix:
        return status, line, detail   # a scrubbing file inside a fixture tree needs nothing from the prefix row
    if status == "HERMETIC":
        return "UNSCRUBBED", line, "stale row (%s): the file already scrubs at file level" % reason
    if reason in ("pinned-fixture", "go-binary-owed"):
        return "EXEMPT", line, reason + ": " + just
    if status == "UNSCRUBBED" and not ws:
        # an ineffective or limit-clearing scrub is never covered by a row
        return status, line, detail + " (row %s does not cover an ineffective scrub)" % reason
    if prefix and ws:
        return "UNSCRUBBED", ws[0][0], "under the fixture-tree prefix %s but a git write is detected; needs its own row: %s" % (prefix, ws[0][1][:120])
    if reason == "no-git-execution":
        if ws:
            return "UNSCRUBBED", ws[0][0], "row no-git-execution, but a git write is detected: %s" % ws[0][1][:120]
        return "EXEMPT", line, reason + ": " + just
    if reason == "sourced-library":
        if status == "UNSCRUBBED":
            return "UNSCRUBBED", line, "row sourced-library, but %s" % detail
        return "EXEMPT", line, reason + ": " + just
    if reason == "entry-function-scrub":
        if not (names_all(text, canon) and list_clear(text, canon)):
            return "UNSCRUBBED", line, "row entry-function-scrub, but no list-operating clear of every variable is in the file"
        why = entry_function_problem(text, canon)
        if why is not None:
            return "UNSCRUBBED", line, "row entry-function-scrub, but " + why
        return "EXEMPT", line, reason + ": " + just
    if reason == "subject-follows-caller":
        ws = [w for w in ws if not ECHO_ONLY.match(w[1])]
        if ws:
            return "UNSCRUBBED", ws[0][0], "row subject-follows-caller, but a git write is detected: %s" % ws[0][1][:120]
        return "EXEMPT", line, reason + ": " + just
    if reason == "fixture-tree":
        if status == "UNSCRUBBED":
            return "UNSCRUBBED", line, detail
        return "EXEMPT", line, "fixture-tree %s: %s" % (prefix, just)
    return "UNSCRUBBED", line, "row reason %s is not valid for this file" % reason


def needles(canon):
    """Run the classifier on samples whose answer is known; return (failures, count)."""
    lst = " ".join(canon)
    sh_scrub = 'for _ge_v in %s; do unset "$_ge_v"; done; unset _ge_v\n' % lst
    py_scrub = 'import os as _ge_os\nfor _ge_v in "%s".split(): _ge_os.environ.pop(_ge_v, None)\n' % lst
    js_scrub = 'for (const _ge_v of "%s".split(" ")) delete process.env[_ge_v];\n' % lst
    unset_all = "unset " + lst + "\n"
    cases = [
        # (name, lang, text, row, want-final-status); row = None or (reason, justification, prefix)
        ("sh bare init", "sh", "#!/bin/sh\ngit init -q x\n", None, "UNSCRUBBED"),
        ("sh -C commit", "sh", '#!/bin/bash\ngit -C "$d" -c user.name=t commit -qm m\n', None, "UNSCRUBBED"),
        ("sh word digit only", "sh", "#!/bin/sh\necho digit legitimate\n", None, None),
        ("sh comment only", "sh", "#!/bin/sh\n# git init is not run here\necho hi\n", None, "UNSCRUBBED"),
        ("sh comment only, text row", "sh", "#!/bin/sh\n# git init is not run here\necho hi\n", ("no-git-execution", "text", ""), "EXEMPT"),
        ("sh read only", "sh", "#!/bin/sh\ngit -C x rev-parse HEAD\n", None, "UNSCRUBBED"),
        ("sh $GIT var", "sh", '#!/bin/bash\nGIT="git -c a=b"\n$GIT init -q x\n', None, "UNSCRUBBED"),
        ("sh ${G[@]} array", "sh", '#!/bin/bash\nG=(git -c a=b)\n"${G[@]}" -C x commit -q -m m\n', None, "UNSCRUBBED"),
        ("sh $GITBIN path", "sh", '#!/bin/bash\nGITBIN=/usr/bin/git\n$GITBIN -C x add f\n', None, "UNSCRUBBED"),
        ("sh $GIT var, text row", "sh", '#!/bin/bash\nGIT="git -c a=b"\n$GIT init -q x\n', ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("sh ${G[@]}, library row", "sh", '#!/bin/bash\nG=(git -c a=b)\n"${G[@]}" -C x commit -q -m m\n', ("sourced-library", "x", ""), "UNSCRUBBED"),
        ("sh ${X:-git} write, text row", "sh", '#!/bin/bash\n${GITX:-git} -C x commit -q -m m\n', ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("sh canonical", "sh", "#!/bin/sh\n" + sh_scrub + "git init -q x\n", None, "HERMETIC"),
        ("sh canonical, $GIT", "sh", "#!/bin/bash\n" + sh_scrub + 'GIT="git -c a=b"\n$GIT init -q x\n', None, "HERMETIC"),
        ("sh canonical after set", "sh", "#!/bin/sh\nset -eu\nexport LC_ALL=C\n" + sh_scrub + "git init -q x\n", None, "HERMETIC"),
        ("sh canonical with stale row", "sh", "#!/bin/sh\n" + sh_scrub + "git init -q x\n", ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("sh scrub late", "sh", "#!/bin/sh\ngit init -q x\n" + sh_scrub, None, "UNSCRUBBED"),
        ("sh scrub short", "sh", "#!/bin/sh\n" + sh_scrub.replace(" GIT_INDEX_FILE", "") + "git init -q x\n", None, "UNSCRUBBED"),
        ("sh scrub with ceiling", "sh", "#!/bin/sh\n" + sh_scrub.replace(" GIT_SHALLOW_FILE", " GIT_CEILING_DIRECTORIES GIT_SHALLOW_FILE") + "git init -q x\n", None, "UNSCRUBBED"),
        ("sh extra ceiling unset", "sh", "#!/bin/sh\n" + sh_scrub + "unset GIT_CEILING_DIRECTORIES\ngit init -q x\n", None, "UNSCRUBBED"),
        ("sh ceiling keep-list", "sh", "#!/bin/bash\n" + sh_scrub + 'for v in ${!GIT_*}; do case "$v" in GIT_CEILING_DIRECTORIES|GIT_AUTHOR_*) ;; *) unset "$v" ;; esac; done\ngit init -q x\n', None, "HERMETIC"),
        ("sh scrub inside a multi-line string", "sh", '#!/bin/sh\nUSAGE="usage:\n' + sh_scrub + '"\ngit init -q x\n', None, "UNSCRUBBED"),
        ("sh scrub after an xtrace-silencing group", "sh", "#!/bin/bash\n{ set +o xtrace +o verbose; } 2>/dev/null\n" + sh_scrub + "git init -q x\n", None, "HERMETIC"),
        ("sh scrub after a git brace group", "sh", "#!/bin/bash\n{ git init -q x; } 2>/dev/null\n" + sh_scrub, None, "UNSCRUBBED"),
        ("sh scrub in if false", "sh", "#!/bin/sh\nif false; then\n" + sh_scrub + "fi\ngit init -q x\n", None, "UNSCRUBBED"),
        ("sh canonical loop typo", "sh", "#!/bin/sh\n" + sh_scrub.replace('unset "$_ge_v"', 'unset "$_ge_w"') + "git init -q x\n", None, "UNSCRUBBED"),
        ("sh no-op loop", "sh", '#!/bin/sh\n# CL_GIT_SCRUB_VARS\nfor _ge_v in %s; do : "$_ge_v"; done; unset _ge_v\ngit init -q x\n' % lst, None, "UNSCRUBBED"),
        ("sh legacy no-op loop + unrelated unset", "sh", '#!/bin/bash\n_git_scrub=(%s)\nfor _v in "${_git_scrub[@]}"; do : "$_v"; done\nunset _v\ngit init -q x\n' % lst, None, "UNSCRUBBED"),
        ("sh legacy array loop", "sh", '#!/bin/bash\n_git_scrub=(%s)\nfor _v in "${_git_scrub[@]}"; do unset "$_v"; done\nunset _v\ngit init -q x\n' % lst, None, "HERMETIC"),
        ("sh legacy unset all", "sh", "#!/bin/sh\n" + unset_all + "git add f\n", None, "HERMETIC"),
        ("sh legacy partial", "sh", "#!/bin/sh\nunset GIT_DIR GIT_WORK_TREE\ngit add f\n", None, "UNSCRUBBED"),
        ("sh legacy names but never clears", "sh", '#!/bin/sh\nGIT_SCRUB_VARS="%s"\ngit init -q x\n' % lst, None, "UNSCRUBBED"),
        ("sh legacy in function only", "sh", "#!/bin/sh\nf() {\n  " + unset_all + "}\ngit add f\n", None, "UNSCRUBBED"),
        ("sh library call", "sh", "#!/bin/sh\n. ./constitution_layout.sh\ncl_scrub_git_env quiet\ngit add f\n", None, "HERMETIC"),
        ("sh library call in function", "sh", "#!/bin/sh\n. ./constitution_layout.sh\nf() {\n  cl_scrub_git_env quiet\n}\ngit add f\n", None, "UNSCRUBBED"),
        ("sh library call in comment", "sh", "#!/bin/sh\n# cl_scrub_git_env quiet\ngit add f\n", None, "UNSCRUBBED"),
        ("sh python heredoc", "sh", "#!/bin/sh\npython3 - <<'PY'\nimport subprocess\nsubprocess.run([\"git\", \"init\", \"d\"])\nPY\n", None, "UNSCRUBBED"),
        ("sh python heredoc helper g, text row", "sh", "#!/bin/sh\npython3 - <<'PY'\nimport subprocess\ndef g(*a):\n    return subprocess.run([\"git\"] + list(a))\ng(\"init\", \"-q\", \"d\")\nPY\n", ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("sh env -i wrapper, library row", "sh", '#!/bin/sh\ng() {\n    env -i PATH="$PATH" \\\n        git -c a=b "$@"\n}\ng commit -m x\n', ("sourced-library", "x", ""), "EXEMPT"),
        ("sh env -i wrapper, no row", "sh", '#!/bin/sh\ng() {\n    env -i PATH="$PATH" \\\n        git -c a=b "$@"\n}\ng commit -m x\n', None, "UNSCRUBBED"),
        ("sh env -i elsewhere, library row", "sh", '#!/bin/sh\ng() { env -i true; git -c a=b "$@"; }\ng commit -m x\n', ("sourced-library", "x", ""), "UNSCRUBBED"),
        ("sh limit name in quoted payload", "sh", '#!/bin/sh\n' + sh_scrub + "sed 's/x/env -u GIT_CEILING_DIRECTORIES y/' f\ngit commit -m x\n", None, "HERMETIC"),
        ("sh wrapper after scrub", "sh", '#!/bin/sh\n' + sh_scrub + 'g() { git -c a=b "$@"; }\ng commit -m x\n', None, "HERMETIC"),
        ("sh scrubbed wrapper, library row", "sh", '#!/bin/sh\nw() {\n  (\n    ' + sh_scrub + '    exec git "$@"\n  )\n}\nw -C d commit -m x\n', ("sourced-library", "x", ""), "EXEMPT"),
        ("sh scrubbed wrapper bypassed, library row", "sh", '#!/bin/sh\nw() {\n  (\n    ' + sh_scrub + '    exec git "$@"\n  )\n}\nw -C d commit -m x\ngit -C d submodule update\n', ("sourced-library", "x", ""), "UNSCRUBBED"),
        ("sh wrapper via $GIT, library row", "sh", '#!/bin/bash\nGIT=git\nw() { $GIT "$@"; }\nw -C d commit -m x\n', ("sourced-library", "x", ""), "UNSCRUBBED"),
        ("sh entry-function scrub", "sh", "#!/bin/bash\nmain() {\n  local _v\n  for _v in %s; do unset \"$_v\"; done\n  git add f\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "EXEMPT"),
        ("sh entry-function no-op", "sh", "#!/bin/bash\nmain() {\n  local _v\n  for _v in %s; do : \"$_v\"; done\n  unset _v\n  git add f\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh fixture tree, text", "sh", "#!/bin/sh\n# fixture git hook\necho hook\n", ("fixture-tree", "x", "fixtures/t/"), "EXEMPT"),
        ("sh fixture tree, scrubbing file", "sh", "#!/bin/sh\n" + sh_scrub + "git commit -q -m x\n", ("fixture-tree", "x", "fixtures/t/"), "HERMETIC"),
        ("sh fixture tree, write", "sh", "#!/bin/sh\ngit commit -q -m x\n", ("fixture-tree", "x", "fixtures/t/"), "UNSCRUBBED"),
        ("py list form", "py", 'import subprocess\nsubprocess.run(["git", "-C", d, "commit", "-m", "x"])\n', None, "UNSCRUBBED"),
        ("py docstring only", "py", '"""run git init by hand"""\nprint(1)\n', None, "UNSCRUBBED"),
        ("py no git", "py", 'print(1)\n', None, None),
        ("py shell string", "py", 'import os\nos.system("git add -A")\n', None, "UNSCRUBBED"),
        ("py canonical", "py", py_scrub + 'import subprocess\nsubprocess.run(["git", "init", d])\n', None, "HERMETIC"),
        ("py canonical after docstring and future", "py", '"""doc git"""\nfrom __future__ import annotations\n' + py_scrub + 'import subprocess\nsubprocess.run(["git", "init", d])\n', None, "HERMETIC"),
        ("py canonical after code", "py", 'X = 1\n' + py_scrub + 'import subprocess\nsubprocess.run(["git", "init", d])\n', None, "UNSCRUBBED"),
        ("py helper g", "py", 'import subprocess\ndef g(*a):\n    return subprocess.run(["git"] + list(a))\ng("init", "-q", "d")\n', ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("py _git list arg", "py", 'import subprocess\ndef _git(repo, args):\n    return subprocess.run(["git", "-C", repo] + args)\n_git(r, ["worktree", "prune"])\n', ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("py helper g, canonical", "py", py_scrub + 'import subprocess\ndef g(*a):\n    return subprocess.run(["git"] + list(a))\ng("init", "-q", "d")\n', None, "HERMETIC"),
        ("py pop->get", "py", '# list = CL_GIT_SCRUB_VARS\n' + py_scrub.replace("environ.pop", "environ.get") + 'import subprocess\nsubprocess.run(["git", "init", d])\n', None, "UNSCRUBBED"),
        ("py scrub in if", "py", 'if False:\n' + "".join("    " + l + "\n" for l in py_scrub.rstrip("\n").split("\n")) + 'import subprocess\nsubprocess.run(["git", "init", d])\n', None, "UNSCRUBBED"),
        ("py docstring carrier", "py", '"""cl_scrub_git_env GIT_SCRUB_VARS %s, each os.environ.pop(v)"""\nimport subprocess\nsubprocess.run(["git", "init", d])\n' % lst, None, "UNSCRUBBED"),
        ("py scrub after the write", "py", 'import subprocess\nsubprocess.run(["git", "init", d])\n' + py_scrub, None, "UNSCRUBBED"),
        ("py wrapper", "py", 'def git(*a): pass\ngit(repo, "commit", "-m", "x")\n', None, "UNSCRUBBED"),
        ("js canonical", "js", "#!/usr/bin/env node\n// tool\n'use strict';\n" + js_scrub + "execFileSync('git', ['init']);\n", None, "HERMETIC"),
        ("js no scrub", "js", "#!/usr/bin/env node\nexecFileSync('git', ['rev-parse']);\n", None, "UNSCRUBBED"),
        ("js scrub late", "js", "#!/usr/bin/env node\nconst x = 1;\n" + js_scrub + "execFileSync('git', ['init']);\n", None, "UNSCRUBBED"),
        ("other shebang language", "other:perl", "#!/usr/bin/perl\nsystem('git init');\n", None, "UNSCRUBBED"),
        ("go exec", "go", 'package m\nfunc f() { exec.Command("git", "-C", r, "checkout", b) }\n', None, "UNSCRUBBED"),
        ("go exec, owed row", "go", 'package m\nfunc f() { exec.Command("git", "-C", r, "checkout", b) }\n', ("go-binary-owed", "x", ""), "EXEMPT"),
        ("go comment", "go", 'package m\n// git checkout -b x\n', None, None),
        # round 4 (R4-3..R4-5, R4-7, R8b)
        ("sh preamble set -e; git", "sh", "#!/bin/sh\nset -e; git init -q x\n" + sh_scrub, None, "UNSCRUBBED"),
        ("sh preamble set -e && git", "sh", "#!/bin/sh\nset -e && git init -q x\n" + sh_scrub, None, "UNSCRUBBED"),
        ("sh preamble shopt, umask", "sh", "#!/bin/bash\nshopt -s nullglob\numask 022\n" + sh_scrub + "git init -q x\n", None, "HERMETIC"),
        ("sh quoted \"git\" word", "sh", '#!/bin/sh\n"git" init -q x\n', ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("sh entry fn, top-level git", "sh", "#!/bin/bash\ngit init -q x\nmain() {\n  local _v\n  for _v in %s; do unset \"$_v\"; done\n  git add f\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh entry fn, clear after git", "sh", "#!/bin/bash\nmain() {\n  git add f\n  local _v\n  for _v in %s; do unset \"$_v\"; done\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh entry fn, clear in other fn", "sh", "#!/bin/bash\nclr() {\n  local _v\n  for _v in %s; do unset \"$_v\"; done\n}\nmain() {\n  git add f\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh entry fn, never called", "sh", "#!/bin/bash\nmain() {\n  local _v\n  for _v in %s; do unset \"$_v\"; done\n  git add f\n}\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh entry fn, unset over wrong list", "sh", "#!/bin/bash\n# %s\nmain() {\n  local _v\n  for _v in A B; do unset \"$_v\"; done\n  git add f\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh entry fn, clear in heredoc", "sh", "#!/bin/bash\nmain() {\n  cat <<EOF\nfor _v in %s; do unset \"$_v\"; done\nEOF\n  git add f\n}\nmain \"$@\"\n" % lst, ("entry-function-scrub", "x", ""), "UNSCRUBBED"),
        ("sh wrapper, clear only in heredoc", "sh", "#!/bin/bash\ng() {\n  local L=\"%s\"\n  cat <<EOF\nfor _v in $L; do unset \"$_v\"; done\nEOF\n  git \"$@\"\n}\ng init -q d\n" % lst, ("sourced-library", "x", ""), "UNSCRUBBED"),
        ("sh guard, read only", "sh", "#!/bin/bash\nB=$(git rev-parse --abbrev-ref HEAD)\necho \"stage with git add <paths>\" >&2\n", ("subject-follows-caller", "x", ""), "EXEMPT"),
        ("sh guard, write", "sh", "#!/bin/bash\ngit add -A\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        ("sh guard, echo piped to sh", "sh", "#!/bin/bash\necho \"git add -A\" | sh\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        ("sh guard, merge-base read", "sh", "#!/bin/bash\ngit merge-base --is-ancestor a b\n", ("subject-follows-caller", "x", ""), "EXEMPT"),
        ("sh guard, merge write", "sh", "#!/bin/bash\ngit merge -q x\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        ("sh guard, merge-tree write", "sh", "#!/bin/bash\ngit merge-tree --write-tree a b\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        # CON-046 round 14 (review r13 R13-6): a merge of a branch whose name ends in -base is a write; the mutant
        # merge(?!.*base) read it as a read and passed every other needle
        ("sh guard, merge of x-base write", "sh", "#!/bin/bash\ngit merge x-base\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        # CON-046 round 14 (R13-4): `symbolic-ref` with one name only reads; with a second argument or -d it writes
        ("sh guard, symbolic-ref read", "sh", "#!/bin/bash\nsref=\"$(git symbolic-ref -q HEAD 2>/dev/null)\" || exit 2\n", ("subject-follows-caller", "x", ""), "EXEMPT"),
        ("sh guard, symbolic-ref short read", "sh", "#!/bin/bash\ngit symbolic-ref --short HEAD\n", ("subject-follows-caller", "x", ""), "EXEMPT"),
        ("sh guard, symbolic-ref set write", "sh", "#!/bin/bash\ngit symbolic-ref HEAD refs/heads/x\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        ("sh guard, symbolic-ref quiet set write", "sh", "#!/bin/bash\ngit symbolic-ref -q HEAD refs/heads/x 2>/dev/null\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        ("sh guard, symbolic-ref delete write", "sh", "#!/bin/bash\ngit symbolic-ref -d HEAD\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
        ("sh guard, symbolic-ref long delete write", "sh", "#!/bin/bash\ngit symbolic-ref --delete HEAD\n", ("subject-follows-caller", "x", ""), "UNSCRUBBED"),
    ]
    # CON-450 round 4 (review R3-1 / R3-2 / R3-5): the closed allow-list of the interpreter's reading. Each refused
    # sample is a member bash runs differently from the census's old reading (the scrub defeated or a write hidden).
    cd = "command declare -l _g\\e_v\n"
    for nm, ch in (("CR", "\r"), ("VT", "\x0b"), ("FF", "\x0c"), ("FS", "\x1c"), ("GS", "\x1d"), ("RS", "\x1e"),
                   ("US", "\x1f"), ("NEL", "\u0085"), ("NBSP", "\u00a0"), ("EMSP", "\u2003"), ("LSEP", "\u2028"),
                   ("ZWSP", "\u200b"), ("RLO", "\u202e"), ("BOM", "\ufeff"), ("NUL-like DEL", "\x7f")):
        cases.append(("sh %s comment before the canonical line" % nm, "sh", "#!/bin/bash\n" + ch + "#;" + cd + sh_scrub +
                      "git init -q x\n", None, "UNSCRUBBED"))
        cases.append(("sh %s inside a preamble comment" % nm, "sh", "#!/bin/bash\n# x" + ch + "y\n" + sh_scrub +
                      "git init -q x\n", None, "UNSCRUBBED"))
    cases += [
        ("sh CRLF file", "sh", ("#!/bin/bash\n" + sh_scrub + "git init -q x\n").replace("\n", "\r\n"), None, "UNSCRUBBED"),
        ("sh env -S shebang", "sh", "#!/usr/bin/env -S bash -c 'declare -l _g\\\\e_v; . \"$0\"'\n" + sh_scrub +
         "git init -q x\n", None, "UNSCRUBBED"),
        ("sh shebang with an argument", "sh", "#!/bin/bash -x\n" + sh_scrub + "git init -q x\n", None, "UNSCRUBBED"),
        ("sh CR hides a write, text row", "sh", "#!/bin/sh\necho hi\n:\r#; git commit -qm x\n", ("no-git-execution", "x", ""), "UNSCRUBBED"),
        ("sh NBSP-led line after the scrub", "sh", "#!/bin/bash\n" + sh_scrub + "\u00a0#; git init -q x\n", None, "UNSCRUBBED"),
        ("sh non-UTF-8 byte in the preamble", "sh", "#!/bin/bash\n# x\ufffdy\n" + sh_scrub + "git init -q x\n", None, "UNSCRUBBED"),
        ("sh em dash and Cyrillic in a preamble comment", "sh", "#!/bin/bash\n# a \u2014 \u043c \u00a7 b\n" + sh_scrub +
         "git init -q x\n", None, "HERMETIC"),
        ("sh NBSP inside a string after the scrub", "sh", "#!/bin/bash\n" + sh_scrub + "echo 'a\u00a0b'\ngit init -q x\n", None, "HERMETIC"),
        ("sh no shebang, comment first", "sh", "# shellcheck shell=bash\n" + sh_scrub + "git init -q x\n", None, "HERMETIC"),
        ("sh /bin/sh shebang", "sh", "#!/bin/sh\n" + sh_scrub + "git init -q x\n", None, "HERMETIC"),
        ("py CR hides a write", "py", py_scrub.replace("import os as _ge_os\n", "import os as _ge_os  # c\rimport subprocess; subprocess.run(['git', 'init', 'x'])\n"), None, "UNSCRUBBED"),
        ("js LSEP ends a comment", "js", "#!/usr/bin/env node\n// c\u2028execFileSync('git', ['init']);\n" + js_scrub, None, "UNSCRUBBED"),
        ("js CR ends a comment", "js", "#!/usr/bin/env node\n// c\rexecFileSync('git', ['init']);\n" + js_scrub, None, "UNSCRUBBED"),
    ]
    bad = []
    for name, lang, text, row, want in cases:
        st, line, detail, ws = judge(lang, text, canon)
        if st is not None:
            st, line, detail = apply_row(st, line, detail, ws, row, text, canon)
        if st != want:
            bad.append("%s: got %s, want %s (%s)" % (name, st, want, detail[:100] if st else ""))
    # the mention detector itself: present forms are seen, letter-embedded ones are not
    for s, want in (("$GITBIN", True), ('"${G[@]}"', False), ("g('x') # Git", True), ("/usr/bin/git", True),
                    ("GIT_DIR", True), ("digit", False), ("legitimate", False)):
        if bool(MENTION.search(s)) != want:
            bad.append("mention detector on %r: got %s" % (s, not want))
    # R11-C: the `.rc` / `.ls` shape rule (control needles: the captured shapes pass, a git write does not)
    lsok = "total 8\ndrwxrwxr-x 2 u u 4096 Nov 13 18:38 .\ndrwx------ 8 u u 4096 Nov 13 18:38 ..\n"
    shapes = (("docs/qa/a/x.rc", "rc", "0\n", False, True), ("docs/qa/a/x.rc", "rc", "255", False, True),
              ("docs/qa/a/x.rc", "rc", "256\n", False, False), ("docs/qa/a/x.rc", "rc", "0\n", True, False),
              ("tests/x.rc", "rc", "0\n", False, False),
              ("docs/qa/a/x.rc", "rc", "GIT_DIR=/tmp/x git commit -q -m m\n", False, False),
              ("docs/qa/a/x.rc", "rc", "0\ngit init -q d\n", False, False),
              ("docs/qa/a/x.ls", "ls", lsok, False, True), ("docs/qa/a/x.ls", "ls", lsok, True, False),
              ("docs/qa/a/x.ls", "ls", lsok + "git -C d commit -m x\n", False, False),
              ("docs/qa/a/x.ls", "ls", "GIT_DIR=/tmp/x git commit -q -m m\n", False, False),
              ("docs/qa/a/x.ls", "ls", "", False, False),
              # round 12: a listing-shaped line that names git, and a header followed by a non-listing line
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 x; git commit -q -m y\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 0\nrm -rf x\n", False, False),
              # round 13 (R12-B2): the shape rule and the detector share one definition; digits and spaces are ASCII
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 x; G=GIT; ${G,,} commit -q -m y\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 Git=1\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 x_git\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 gitx\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- 1 u u 1 Nov 13 18:38 digit\n", False, True),
              ("docs/qa/a/x.rc", "rc", "\u0661\u0662\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total \u0668\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r--\u20031 u u 1 Nov 13 18:38 x\n", False, False),
              ("docs/qa/a/x.ls", "ls", "total 8\n-rw-rw-r-- \u0661 u u 1 Nov 13 18:38 x\n", False, False))
    for sp, se, st_, sx, want in shapes:
        if shaped_data(sp, se, st_, sx) != want:
            bad.append("shape rule on %s %r exec=%s: got %s" % (sp, st_[:40], sx, not want))
    return bad, len(cases) + 7 + len(shapes)


def git_env(canon):
    """The caller's environment without the canonical class (the census's own `git ls-files` is a read)."""
    env = dict(os.environ)
    for v in canon:
        env.pop(v, None)
    return env


def main(argv):
    root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    exf = None
    tsv = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--root", "--exemptions") and i + 1 < len(argv):
            if a == "--root":
                root = os.path.abspath(argv[i + 1])
            else:
                exf = argv[i + 1]
            i += 2
        elif a == "--tsv":
            tsv = True
            i += 1
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print("usage: git_env_class_census.py [--root <repo>] [--exemptions <tsv>] [--tsv]", file=sys.stderr)
            return 64
    if exf is None:
        exf = os.path.join(root, "config", "git_env_class_exemptions.tsv")

    def blind(msg):
        print("%s: BLIND - %s" % (TOOL, msg))
        return 2

    lib = os.path.join(root, "scripts", "lib", "constitution_layout.sh")
    try:
        m = re.search(r'^CL_GIT_SCRUB_VARS="([^"]+)"', open(lib, encoding="utf-8").read(), re.M)
    except OSError as e:
        return blind("cannot read the canonical list in %s: %s" % (lib, e))
    if not m or "GIT_DIR" not in m.group(1).split() or "GIT_INDEX_FILE" not in m.group(1).split():
        return blind("no CL_GIT_SCRUB_VARS list holding GIT_DIR and GIT_INDEX_FILE in %s" % lib)
    canon = m.group(1).split()
    lim = [v for v in canon if v in LIMIT_VARS]
    if lim:
        return blind("the canonical list CL_GIT_SCRUB_VARS holds the discovery limit %s (it must never be scrubbed)" % ",".join(lim))
    bad, ncases = needles(canon)
    if bad:
        return blind("control needle: " + "; ".join(bad))

    # round 4 (R4-1): the whole tracked tree, with the index mode of every entry (gitlink, symlink, executable bit)
    p = subprocess.run(["git", "-C", root, "ls-files", "-z", "-s"], capture_output=True, env=git_env(canon))
    if p.returncode != 0:
        return blind("git ls-files failed in %s: %s" % (root, p.stderr.decode("utf-8", "replace").strip()))
    entries = []
    for ent in p.stdout.decode("utf-8", "surrogateescape").split("\0"):
        if not ent:
            continue
        meta, _tab, f = ent.partition("\t")
        if not f or not meta.split():
            return blind("unparseable `git ls-files -s` entry %r" % ent[:80])
        entries.append((meta.split()[0], f))
    files = sorted({f for _m, f in entries})
    modes = {}
    for m_, f in entries:
        modes.setdefault(f, m_)   # an unmerged path has one entry per stage; the first mode is enough here
    if not files:
        return blind("git ls-files listed no tracked file in %s" % root)

    problems = []
    exact = {}
    prefixes = {}
    if os.path.exists(exf):
        for n, raw in enumerate(open(exf, encoding="utf-8").read().split("\n"), 1):
            if not raw.strip() or raw.startswith("#"):
                continue
            cols = raw.split("\t")
            if len(cols) != 3 or cols[1] not in REASONS or not cols[2].strip():
                problems.append("exemption line %d is malformed (want <path>TAB<reason>TAB<justification>, reason one of %s)" % (n, ",".join(sorted(REASONS))))
                continue
            path, reason, just = cols
            if path.endswith("/"):
                if reason != "fixture-tree" or "/fixtures/" not in "/" + path:
                    problems.append("exemption line %d: a prefix row (path ending in /) must have reason fixture-tree and lie under a fixtures/ directory" % n)
                    continue
                if path in prefixes:
                    problems.append("exemption line %d repeats %s" % (n, path))
                prefixes[path] = (reason, just, path)
            else:
                if reason == "fixture-tree":
                    problems.append("exemption line %d: reason fixture-tree needs a prefix row (path ending in /)" % n)
                    continue
                if path in exact:
                    problems.append("exemption line %d repeats %s" % (n, path))
                exact[path] = (reason, just, "")

    used = set()
    rows = []
    reasons = {}
    # closed-world accounting (R4-1): every tracked path lands in exactly one bucket; the sum is checked below
    inv = {"tracked": len(files), "gitlink": 0, "symlink": 0, "absent": 0, "binary": 0, "data": 0, "code": 0, "unclassified": 0}
    langs = {}
    texts = {}
    for f in files:
        path = os.path.join(root, f)
        mode = modes.get(f, "")
        if mode == "160000":
            inv["gitlink"] += 1       # a submodule: its files are governed in its own repository
            continue
        if mode == "120000" or os.path.islink(path):
            inv["symlink"] += 1       # the target, when tracked, is judged under its own path
            continue
        if not os.path.isfile(path):
            inv["absent"] += 1
            problems.append("tracked file %s is absent from the working tree (cannot be judged)" % f)
            continue
        try:
            b = open(path, "rb").read()
        except OSError as e:
            inv["absent"] += 1
            problems.append("cannot read %s: %s" % (f, e))
            continue
        if b"\0" in b:
            inv["binary"] += 1
            continue
        text = b.decode("utf-8", "replace")
        executable = mode == "100755"
        base = f.rsplit("/", 1)[-1]
        ext = base.lstrip(".").rsplit(".", 1)[1] if "." in base.lstrip(".") else ""
        # a data extension wins over a shebang (evidence copies of scripts are stored as `*.sh.txt`), but never
        # over the executable bit: an executable file can be run as `./file` whatever its name
        lang = None if ((ext in DATA_EXT and not executable) or shaped_data(f, ext, text, executable)) \
            else lang_of(f, text[:200], executable)
        if lang is None:
            if ext and ext not in DATA_EXT and not shaped_data(f, ext, text, executable):
                inv["unclassified"] += 1
                problems.append("tracked file %s has the extension .%s, which is neither code nor in the closed data list "
                                "(add it to DATA_EXT or a code language; the universe is closed-world)" % (f, ext))
                continue
            inv["data"] += 1
            continue
        inv["code"] += 1
        lk = lang if not lang.startswith("other:") else "other"
        langs[lk] = langs.get(lk, 0) + 1
        if lang == "sh":
            texts[f] = text
        st, line, detail, ws = judge(lang, text, canon)
        if st is None:
            continue
        row = exact.get(f)
        key = f
        if f in BUILTIN_LIBS and row is None:
            row = ("sourced-library", BUILTIN_LIBS[f], "")
            key = None
        if row is None:
            for pre in sorted(prefixes, key=len, reverse=True):
                if f.startswith(pre):
                    row = prefixes[pre]
                    key = pre
                    break
        if row is not None and key is not None:
            used.add(key)
        st, line, detail = apply_row(st, line, detail, ws, row, text, canon)
        rows.append([st, lang, f, line, detail])
        reasons[f] = row[0] if row is not None else None
    for k in sorted((set(exact) | set(prefixes)) - used):
        problems.append("exemption for %s, which covers no member of the class (stale row)" % k)
    # R4-2: a sourced-library row rests on "its callers scrub first". That premise is decidable from the source
    # graph: every shell file that sources such a library (a `.`/`source` statement plus the library's file name
    # in its code, also through a variable) must itself be HERMETIC, or be a sourced library / entry-function file
    # with its own row. Libraries whose every git call runs inside a scrubbing wrapper need nothing from callers.
    status_of = {r[2]: r for r in rows}
    readers = {}
    for f, (reason, _j, _p) in exact.items():
        if reason == "sourced-library" and f in texts:
            calls = unwrapped_git_calls(texts[f], canon)
            if calls:
                readers[f] = calls[0]
    for f, text in sorted(texts.items()):
        code = "\n".join(code_lines("sh", text))
        if not SOURCE_RE.search(code):
            continue
        for lib_, (lline, lsrc) in sorted(readers.items()):
            if lib_ == f or not re.search(r"(?<![\w.-])" + re.escape(lib_.rsplit("/", 1)[-1]) + r"\b", code):
                continue
            r = status_of.get(f)
            if r is not None and (r[0] == "HERMETIC" or (r[0] == "EXEMPT" and reasons.get(f) in ("sourced-library", "entry-function-scrub"))):
                continue
            msg = ("sources the sourced-library %s, which runs git outside a scrubbing wrapper (line %d: %s); a file "
                   "that sources it must scrub at file level (R4-2)" % (lib_, lline, lsrc[:80]))
            if r is None:
                rows.append(["UNSCRUBBED", "sh", f, 1, msg])
                status_of[f] = rows[-1]
            elif r[0] != "UNSCRUBBED":
                r[0], r[3], r[4] = "UNSCRUBBED", 1, msg
            break
    universe = sum(langs.values())
    accounted = sum(v for k, v in inv.items() if k != "tracked")
    inventory = ("inventory: tracked=%d accounted=%d universe=%d (%s) gitlink=%d symlink=%d binary=%d data=%d "
                 "unclassified=%d absent=%d members=%d non_members=%d") % (
        inv["tracked"], accounted, universe, " ".join("%s=%d" % kv for kv in sorted(langs.items())), inv["gitlink"],
        inv["symlink"], inv["binary"], inv["data"], inv["unclassified"], inv["absent"], len(rows), universe - len(rows))
    if accounted != inv["tracked"] or universe != inv["code"]:
        return blind("closed-world accounting does not add up: %s" % inventory)
    if universe == 0:
        return blind("zero code files found in the tracked tree (%s)" % inventory)
    if not rows:
        return blind("zero members found (the mention detector is blind or the tree is wrong; %s)" % inventory)

    if tsv:
        for r in sorted(rows, key=lambda r: r[2]):
            print("%s\t%s\t%s\t%d\t%s" % tuple(r))
    counts = {}
    for r in rows:
        counts[r[0]] = counts.get(r[0], 0) + 1
    for r in sorted(rows, key=lambda r: r[2]):
        if r[0] == "UNSCRUBBED":
            problems.append("UNSCRUBBED %s (line %d): %s" % (r[2], r[3], r[4]))
    summary = "members=%d hermetic=%d exempt=%d unscrubbed=%d" % (
        len(rows), counts.get("HERMETIC", 0), counts.get("EXEMPT", 0), counts.get("UNSCRUBBED", 0))
    print("%s: %s" % (TOOL, inventory))
    if problems:
        for pr in problems:
            print("%s: FAIL - %s" % (TOOL, pr))
        print("%s: FAIL - %s" % (TOOL, summary))
        return 1
    print("%s: control needles seen (%d samples)" % (TOOL, ncases))
    print("%s: PASS - %s" % (TOOL, summary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
