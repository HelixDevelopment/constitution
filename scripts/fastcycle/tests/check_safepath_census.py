#!/usr/bin/env python3
"""check_safepath_census.py -- the census of the trusted-parent rule's path operations (T048 V4; round 12 V4R12-1,
round 13 V4R13-3: FAIL-CLOSED). docs/qa/v4_round7_20261012/CONVERGENCE.md states its scope as the closed list below.

It reads cycle/fc_supervisor.py and cycle/baseline_replay.sh (the files UNDER TEST: FC_SUP_UNDER_TEST /
FC_BR_UNDER_TEST, or --sup / --br) and classifies every operation it MODELS; anything it does not model is a VIOLATION
(exit 1) until it is added to a table here with its reason -- the census does not have to recognise a dangerous form
to refuse it. Round 6's name-list census missed 20/24 Python and 16/32 shell forms (v4_round6_review section 4); every
one of them is a needle of [R13CENSUS-*] now.

SCOPE (closed; what a PASS means): every IMPORT, every os / os.path / subprocess / ctypes / importlib attribute, every
call of a path-acting method name, getattr/eval/exec/__import__, and the builtin open() of fc_supervisor.py; every
SIMPLE COMMAND of baseline_replay.sh (top level, $( ), backticks, <( ), subshells, groups, if/while/for/case bodies,
trap actions, `"$BASH" -c '<literal>'`, the command after `--` of _fc_run_child, through env / exec / command), its
redirections, and every here-document Python program (proved READ-ONLY). NOT in scope (stated, never implied): what
the programs run BY this tool do to the filesystem -- git (its own repository and the worktree it is told to make),
lib/fc_common.py emit (the report; verified by report_verified afterwards), the gate command, the compiler -- each is
an EXEMPT row with its reason; the values of variables at run time beyond the provenance rules below.

Python (AST):
  imports      exactly PY_IMPORTS; an alias / `from` import / another module -> VIOLATION at the import and at every use
  os.X         OS_PURE (no path), PY_OPS (path: classified below), PY_EXEMPT (function, op) with reason; else VIOLATION;
               a PY_OPS function REFERENCED but not called (functools.partial(os.unlink, p)) -> VIOLATION
  os.path.X    OS_PATH_PURE (strings); OS_PATH_READ -> needs a `# safepath:probe` tag; else VIOLATION
  round 14     a DUNDER attribute anywhere (.__call__, __getattribute__, __builtins__, __globals__) -> VIOLATION; an
               attribute of a permitted module (signal, sys, json, argparse, fcntl, ...) outside MODULE_ATTRS ->
               VIOLATION; a module OBJECT used as a value (passed, stored, called) -> VIOLATION; an attribute OF a
               path operation (os.unlink.X) -> VIOLATION; a procfs tag never covers an xattr WRITE
  ROUTED       a PY_OPS call whose dir_fd / src_dir_fd / dst_dir_fd (or listdir / scandir argument) is a PROVED directory
               fd: a value from the helpers (FD_DIRECT, FD_TUPLE), an os.open itself ROUTED, a parameter EVERY call site
               of which passes a proved fd (checked over the call graph; None only where FD_NONE_OK says why; a
               function with no call site proves nothing), PY_FD_VARS / PY_FD_EXPRS (closed, with reasons). A constant
               (dir_fd=None) is never proved.
  ROOT         os.open("/") inside _walk.   TAGGED  procfs (a literal /proc/...), devnull (os.devnull), probe (a
               read-only query, PY_READONLY).   EXEMPT  PY_EXEMPT.
Shell (a lexer, _ShLex):
  command word must be a PLAIN word in SH_NOOP / SH_READ / SH_WRITE / SH_WRAPPERS / git / python3 / a function of this
               file; a quoted, escaped or indirect command word, eval, sh/bash/source, or any other word -> VIOLATION
  SH_READ / SH_WRITE / redirections (> >> >| <> < &> N>) / git worktree add|remove|unlock / git -C D submodule:
               every path operand must be PRIVATE (it starts with a PROVED variable; every other expansion in it is a
               proved variable; no '..' component, no '~', no bare relative word; a plain suffix only on a FILE
               variable), or TAGGED (param: PARAMS; devnull; procfs literal for reads)
  PROVED       a variable EVERY assignment of which is: $(_fc_safe mkdtemp ...), $(_fc_safe mkdir --exclusive ...) (a
               plain `_fc_safe mkdir` result is NOT a namespace), $(_fc_mktemp), $(mktemp [-d] "$_FC_TMPDIR/NAME") with
               NAME free of '/' and '..', ${FC_BR_TMPDIR} (proved --exclusive at worker start), or a proved variable +
               '/...' -- the greatest fixed point; read / for targets are never proved; round 14: `printf -v V` or
               `unset V` of a PROVED V, and any nameref declaration (local / declare / typeset -n), -> VIOLATION
  ROUND 15     (V4R15-2, §11.4.276(E) structural -- the CLASS "a proved variable changed or emptied outside the
               provenance model", closed by rules, not by needles; enumeration: docs/qa/v4_round9_20261014/
               CONVERGENCE.md):
               (a) a NAME is read through quote removal ('_X', "_X", backslash-_X, -v"_X" name _X), and a NAME holding an
                   expansion ("$n", ${n}, $(..), `..`) in ANY variable-name position of printf -v / unset / read
                   [-a] / wait -p / local / declare / typeset / export / readonly -> VIOLATION (an option word holding
                   an expansion too); every other name-taking builtin is outside the tables (let, mapfile,
                   readarray, getopts, select, coproc, builtin, ...: an unknown command);
               (b) a PROVED V assigned by printf -v / wait -p / unset, or given an attribute (-i -l -u -c -a -A -t)
                   -> VIOLATION; typeset and quoted NAME=VALUE words are MODELLED (provenance), read's targets too;
               (c) in the EXPANDED text (unquoted here-documents included): ${V=..} / ${V:=..} of a proved V,
                   ${!R=..} / ${!R:=..} always, an arithmetic assignment (= op= ++ --) to a proved V inside (( )),
                   $(( )), $[ ], [[ ]], a NAME[..] subscript or a ${X:offset}, and a {V}> fd redirection -> VIOLATION;
               (d) EMPTY: every expansion of a proved variable in a path operand (and in a derived value with a
                   suffix) must be ${V:?} -- bash aborts the command when V is empty or unset -- so no form of
                   emptying (V="", local V, unset, a function that never assigns its local) can make an operand
                   "/suffix" or "" (`cp -r d ""` copies into the cwd; `awk 1 ""` reads stdin -- measured). The
                   round-14 "cleared to ''" residual is CLOSED by (d).
  python3      "$_FC_SUPERVISOR" -> ROUTED (censused as Python); `python3 - <<'X'` -> its program must be READ-ONLY
               (_heredoc_py_bad); SH_PROGRAMS / SH_EXEMPT rows; anything else (python3 -c ...) -> VIOLATION
  git          GIT_RO sub-commands, `config --get*`, `worktree list`, `worktree prune` (TAGGED); add/remove/unlock and
               `-C D submodule` need proved operands; any other sub-command -> VIOLATION
Output: one census row per operation (file, line, kind, verdict, reason) -- --markdown prints the table the
CONVERGENCE document embeds -- and a SUMMARY line. Exit 0 no violation, 1 at least one, 2 usage / unreadable input.
--self-test prints the forms the census recognises and refuses (its own needles; [R13CENSUS-self])."""
import ast
import os
import re
import sys

SH_TAGS = {"msg", "param", "devnull"}
# function parameters that carry a path, with the reason every caller passes a proved one (checked by name)
PARAMS = {
    ("_fc_ledger_add", "kind"): "a NAME component inside $_FC_TMPDIR: every caller passes the literal wt, pend or logs",
    ("run_replay_isolated", "body_file"): "both callers (cmd_replay, cmd_replay_sample) pass a $(_fc_mktemp) file",
    ("_fc_submodule_reference_update", "tgt"): "its only caller (the `\"$BASH\" -c` in _do_one_replay_body) passes "
                                              "$wt_path, a directory made by `safepath mkdtemp --exclusive-parent` "
                                              "in the proved --worktree-root",
    ("_fc_run_child", "log"): "callers pass a $(_fc_mktemp) file, a $run_log_dir/... file (a helper-made run-log "
                              "directory) or /dev/null",
}
TAG_RE = re.compile(r"#\s*safepath:(\w+)")



# ====================================================================================================================
# PYTHON (fc_supervisor.py): the census MODELS a closed list of names; anything outside it is a VIOLATION (fail-closed,
# round 13 -- the round-6 review showed 20 of 24 path-operation forms passing a name-list census unseen).
# ====================================================================================================================
# every import the module may make, exactly (module, alias): an alias or `from` import of a filesystem module, or any
# module not listed (pathlib, io, codecs, glob, shutil, tempfile, sqlite3, functools, ...) is a violation at the import
# AND at every line that uses a name it bound
PY_IMPORTS = {("_signal", "_early_sig"), ("os", None), ("signal", None), ("ctypes", None), ("select", None),
              ("stat", "_st"), ("subprocess", None), ("sys", None), ("time", None), ("fcntl", None),
              ("importlib.util", None), ("json", None), ("argparse", None), ("grp", None), ("pwd", None)}
# os functions that take a PATH: each call is ROUTED (dir_fd / src_dir_fd / dst_dir_fd = a PROVED directory fd, or --
# listdir / scandir -- a proved fd as the argument), ROOT, TAGGED, or a VIOLATION
PY_OPS = {"open", "unlink", "remove", "rmdir", "mkdir", "makedirs", "rename", "replace", "link", "symlink", "chmod",
          "chown", "lchown", "truncate", "listdir", "scandir", "mkfifo", "mknod", "stat", "lstat", "access",
          "readlink", "utime", "listxattr", "getxattr", "setxattr", "removexattr"}
# round 14 (V4R14-1): the xattr family takes a path too; listxattr / getxattr are read-only queries (the procfs tag is
# accepted for them), setxattr / removexattr CHANGE the object -- never accepted by a tag
PY_XATTR_WRITE = {"os.setxattr", "os.removexattr"}
# os attributes that take no path (reviewed one by one; fd-, pid- or value-based); O_* and W* macros too
OS_PURE = {"_exit", "close", "dup2", "environ", "fdopen", "fork", "fsdecode", "fsencode", "fstat", "fsync",
           "ftruncate", "getcwd", "getegid", "geteuid", "getgroups", "getpid", "getppid", "pidfd_open", "pipe", "read",
           "set_blocking", "set_inheritable", "setpgid", "setsid", "strerror", "umask", "urandom", "waitpid", "write",
           "devnull", "path"}
OS_PATH_PURE = {"join", "split", "basename", "dirname", "normpath", "isabs", "splitext", "abspath"}  # strings (+cwd)
OS_PATH_READ = {"exists", "lexists", "isdir", "isfile", "islink", "getsize", "realpath"}  # probes: need a tag
PY_READONLY = {"os.stat", "os.lstat", "os.access"} | {"os.path." + x for x in OS_PATH_READ}
SUBPROCESS_PURE = {"DEVNULL", "PIPE", "SubprocessError", "TimeoutExpired", "CompletedProcess"}
CTYPES_PURE = {"c_int", "c_ulong", "c_char_p", "get_errno"}
LIBC_PURE = {"prctl"}
# method names that act on a path whatever object carries them (pathlib-style): a call is a violation unless EXEMPT
METHOD_OPS = {"unlink", "rmdir", "mkdir", "touch", "write_text", "write_bytes", "symlink_to", "hardlink_to",
              "exec_module", "rmtree", "makedirs", "removedirs", "renames", "chmod", "lchmod", "chown", "mkfifo",
              "link_to", "open_text"}
FS_MODULE_NAMES = {"pathlib", "io", "codecs", "glob", "shutil", "tempfile", "sqlite3", "fileinput", "posix", "mmap",
                   "zipfile", "tarfile", "gzip", "bz2", "lzma", "dbm", "shelve", "runpy", "pty", "socket"}
PY_DYNAMIC = {"getattr", "setattr", "__import__", "eval", "exec", "compile", "globals", "vars",
              "breakpoint"}   # round 15: breakpoint() calls the hook an environment variable names (fail-closed)
PY_TAGS = {"procfs", "devnull", "probe"}
# round 14 (V4R14-2): EVERY attribute of a permitted module that is NOT one of the os / subprocess / ctypes /
# importlib families above is MODELLED here (the names fc_supervisor.py uses, each reviewed: none takes a path); any
# other attribute of these modules -- argparse.FileType, sys.modules, fcntl.ioctl, ... -- is a VIOLATION (fail-closed).
MODULE_ATTRS = {
    "signal": {"NSIG", "SIGCHLD", "SIGCONT", "SIGHUP", "SIGINT", "SIGKILL", "SIGQUIT", "SIGSTOP", "SIGTERM", "SIGUSR2",
               "SIG_BLOCK", "SIG_DFL", "SIG_IGN", "SIG_SETMASK", "getsignal", "pidfd_send_signal", "pthread_sigmask",
               "signal"},                                  # signal numbers and dispositions; pidfd_* acts on a pid fd
    "_early_sig": {"SIGINT", "SIG_IGN", "getsignal", "signal"},
    "select": {"select"},                                  # waits on fds
    "sys": {"argv", "exit", "stderr", "stdout"},           # the process's own arguments / streams (already open)
    "time": {"monotonic", "sleep", "time_ns"},
    "fcntl": {"F_GETFL", "LOCK_EX", "LOCK_NB", "fcntl", "flock"},   # on fds this module opened through the helpers
    "json": {"dumps", "loads"},                            # strings only (dump / load would take a file object)
    "argparse": {"ArgumentParser"},                        # FileType would OPEN a path: not modelled
    "grp": {"getgrgid"}, "pwd": {"getpwall", "getpwuid"},  # the group / user database (read-only queries)
    "_st": {"S_IMODE", "S_ISDIR", "S_ISLNK", "S_ISREG", "S_ISVTX"},  # mode-bit arithmetic
}
# round 14 (V4R14-2): module OBJECTS -- a bare use of one of these names (passed, stored, called, a default value)
# hands the module to code the census cannot follow (type(os).__getattribute__(os, "unlink"), (lambda o: ...)(os))
PY_MODULE_OBJECTS = {"os", "subprocess", "ctypes", "importlib", "_libc"} | set(MODULE_ATTRS)
# the closed, justified EXEMPTIONS (function, operation) -> why: each is a path operation by design
PY_EXEMPT = {
    ("spawn", "os.chdir"): "the gate's working directory, in the forked child before exec: callers pass a worktree "
                           "made by `safepath mkdtemp` in the proved --worktree-root (or the repository root); a "
                           "chdir creates, writes and removes nothing",
    ("spawn", "os.execvpe"): "runs the command line the caller chose (gate / git / the worker): running it is the "
                             "intent",
    ("_git", "subprocess.Popen"): "`git -C REPO`: `worktree list --porcelain` (read-only) and remove_worktree's "
                                  "`worktree unlock / remove -f -f / prune` of a replay worktree BY PATH -- a "
                                  "directory this tool made by `safepath mkdtemp` in the proved --worktree-root "
                                  "(rule 4's one stated exception)",
    ("_report_prepare_at", "importlib.util.spec_from_file_location"):
        "loads lib/fc_common.py from the path main was handed (its own installation): code, read-only",
    ("_report_prepare_at", "exec_module"): "runs that module's top level (definitions only)",
    ("<module>", "ctypes.CDLL"): "libc (CDLL(None)); its only attribute used is prctl (LIBC_PURE)",
}
# function parameters that carry a DIRECTORY FD: proved when EVERY call site of the function passes a proved fd at that
# position -- checked, not trusted (a greatest fixed point over the call graph). None is accepted only where the
# function's own PATH branch walks first (FD_NONE_OK).
FD_NONE_OK = {
    ("open_owned_dir", "dir_fd"): "None selects the PATH branch, which walks the parent first (_at_parent) and returns",
    ("open_owned_file", "dir_fd"): "None selects the PATH branch, which walks the parent first (_at_parent) and returns",
    ("_read_owned", "dir_fd"): "passed on to open_owned_file (its None branch walks first)",
    ("_lease_free", "dir_fd"): "passed on to open_owned_dir (its None branch walks first)",
    ("_remove_state_at", "dfd"): "None -> opened HERE by open_owned_dir(name, pfd) before any use (a local assignment, "
                                 "itself checked)",
}
# helpers that RETURN a proved directory fd: directly, or at a tuple position
FD_DIRECT = {"open_owned_dir", "_reopen_dir"}
FD_TUPLE = {"_walk": 0, "open_trusted_dir": 0, "_trusted_parent": 0, "_mkdtemp_at": 1}
# lambda arguments whose FIRST parameter is a proved fd (fn(proved parent fd, name) -- _at_parent's contract)
LAMBDA_PROVERS = {"_at_parent": 1}
# the one local that is proved by construction (and why)
PY_FD_VARS = {("_walk", "cur"): "the top of the stack of PROVED directory fds (only a proved directory is pushed)"}
# expressions that are proved by construction (function, expression text) -> why
PY_FD_EXPRS = {("_gc_at", "held[-1]"): "the state directory fd _lease_free has just proved (open_owned_dir) and appended "
                                       "to `held`, its keep list"}


def _scopes(tree):
    """node id -> its innermost enclosing FunctionDef / Lambda node (None at module level); and node id -> parent"""
    scope, parent = {}, {}

    def visit(n, sc):
        for ch in ast.iter_child_nodes(n):
            parent[id(ch)] = n
            scope[id(ch)] = sc
            visit(ch, ch if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)) else sc)
    visit(tree, None)
    return scope, parent


def _sname(sc):
    if sc is None:
        return "<module>"
    return sc.name if not isinstance(sc, ast.Lambda) else "<lambda>"


def _dotted(e):
    """'os.path.join' for an Attribute chain on a Name, else None"""
    parts = []
    while isinstance(e, ast.Attribute):
        parts.append(e.attr)
        e = e.value
    if isinstance(e, ast.Name):
        return ".".join([e.id] + parts[::-1])
    return None


def _params(fn):
    a = fn.args
    return [x.arg for x in a.posonlyargs + a.args + a.kwonlyargs]


def py_census(path):
    src = open(path).read()
    lines = src.split("\n")
    tree = ast.parse(src)
    scope, parent = _scopes(tree)
    rows = []

    def row(node, func, name, verdict, why):
        rows.append((os.path.basename(path), node.lineno, func, name, verdict, why))
    funcs = {}
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs.setdefault(n.name, n)
    # ---- imports ----
    unmodelled = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for al in n.names:
                if (al.name, al.asname) not in PY_IMPORTS:
                    unmodelled.add(al.asname or al.name.split(".")[0])
                    row(n, _sname(scope.get(id(n))), "import %s%s" % (al.name, " as " + al.asname if al.asname else ""),
                        "VIOLATION", "an import outside the census's modelled set (fail-closed: PY_IMPORTS)")
        elif isinstance(n, ast.ImportFrom):
            for al in n.names:
                unmodelled.add(al.asname or al.name)
            row(n, _sname(scope.get(id(n))), "from %s import ..." % n.module, "VIOLATION",
                "a `from` import binds names the census cannot follow (fail-closed)")
    # ---- proved directory fds: a greatest fixed point over locals and parameters ----
    assigns = {}                                   # (scope id, name) -> [value expr or a marker]

    def add_assign(sc, name, val):
        assigns.setdefault((id(sc) if sc else 0, name), []).append(val)
    for n in ast.walk(tree):
        sc = scope.get(id(n))
        if isinstance(n, ast.Assign):
            for tg in n.targets:
                if isinstance(tg, ast.Name):
                    add_assign(sc, tg.id, n.value)
                elif isinstance(tg, ast.Tuple):
                    for k, el in enumerate(tg.elts):
                        if isinstance(el, ast.Name):
                            add_assign(sc, el.id, ("tuple", k, n.value))
        elif isinstance(n, (ast.AugAssign, ast.AnnAssign)) and isinstance(n.target, ast.Name):
            add_assign(sc, n.target.id, "other")
        elif isinstance(n, (ast.For, ast.comprehension)):
            for el in ast.walk(n.target):
                if isinstance(el, ast.Name):
                    add_assign(sc, el.id, "other")
        elif isinstance(n, ast.withitem) and n.optional_vars is not None:
            for el in ast.walk(n.optional_vars):
                if isinstance(el, ast.Name):
                    add_assign(sc, el.id, "other")
        elif isinstance(n, ast.ExceptHandler) and n.name:
            add_assign(sc, n.name, "other")
        elif isinstance(n, ast.NamedExpr):
            add_assign(sc, n.target.id, n.value)
    calls_of = {}                                   # function name -> [(call node, caller scope)]
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in funcs:
            calls_of.setdefault(n.func.id, []).append((n, scope.get(id(n))))
    # a parameter with NO call site in the file proves nothing (vacuity is not proof: round 13, the reviewer's A14)
    proved_params = {(f, p) for f, fn in funcs.items() for p in _params(fn) if f in calls_of}
    lambda_ok = set()                               # id(lambda) whose first parameter is proved
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in LAMBDA_PROVERS:
            k = LAMBDA_PROVERS[n.func.id]
            if len(n.args) > k and isinstance(n.args[k], ast.Lambda):
                lambda_ok.add(id(n.args[k]))
    routed_open = set()                             # id() of os.open calls whose dir_fd is proved

    def name_proved(sc, name, seen):
        key = (id(sc) if sc else 0, name)
        if key in seen:
            return True                              # greatest fixed point: an assumption until refuted
        seen = seen | {key}
        if isinstance(sc, ast.Lambda):
            ps = [a.arg for a in sc.args.args]
            if name in ps:
                return id(sc) in lambda_ok and ps.index(name) == 0
        if isinstance(sc, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if (sc.name, name) in PY_FD_VARS:
                return True
            if name in _params(sc):
                local = assigns.get(key, [])
                return (sc.name, name) in proved_params and all(val_proved(sc, v, seen) for v in local)
        vals = assigns.get(key)
        if not vals:
            # not assigned here: a closure variable of an enclosing scope
            outer = scope.get(id(sc)) if sc is not None else None
            if sc is None:
                return False
            return name_proved(outer, name, seen)
        return all(val_proved(sc, v, seen) for v in vals)

    def val_proved(sc, v, seen):
        if isinstance(v, str):
            return False
        if isinstance(v, tuple):
            _t, k, call = v
            return isinstance(call, ast.Call) and isinstance(call.func, ast.Name) and FD_TUPLE.get(call.func.id) == k
        return expr_proved(sc, v, seen)

    def expr_proved(sc, e, seen=frozenset()):
        if (_sname(sc), ast.unparse(e)) in PY_FD_EXPRS:
            return True
        if isinstance(e, ast.Name):
            return name_proved(sc, e.id, seen)
        if isinstance(e, ast.Call):
            if isinstance(e.func, ast.Name) and e.func.id in FD_DIRECT:
                return True
            if _dotted(e.func) == "os.open":
                return dirfd_ok(e, sc, seen)
        return False

    def dirfd_ok(call, sc, seen=frozenset()):
        kws = {k.arg: k.value for k in call.keywords if k.arg in ("dir_fd", "src_dir_fd", "dst_dir_fd")}
        return bool(kws) and all(expr_proved(sc, v, seen) for v in kws.values())
    def arg_ok(f, p, arg, csc):
        if arg is None or (isinstance(arg, ast.Constant) and arg.value is None):
            return (f, p) in FD_NONE_OK                  # the default (None): see FD_NONE_OK
        if isinstance(arg, ast.IfExp):
            return arg_ok(f, p, arg.body, csc) and arg_ok(f, p, arg.orelse, csc)
        return expr_proved(csc, arg)
    changed = True
    while changed:                                   # parameters: refuted by any call site passing an unproved fd
        changed = False
        for (f, p) in sorted(proved_params):
            fn = funcs[f]
            ps = _params(fn)
            k = ps.index(p)
            for call, csc in calls_of.get(f, []):
                arg = None
                if k < len(call.args):
                    arg = call.args[k]
                for kw in call.keywords:
                    if kw.arg == p:
                        arg = kw.value
                good = arg_ok(f, p, arg, csc)
                if not good:
                    proved_params.discard((f, p))
                    changed = True
                    break
    # ---- every Attribute / Name use ----
    for node in ast.walk(tree):
        sc = scope.get(id(node))
        func = _sname(sc)
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id in FS_MODULE_NAMES \
                and node.id not in {m.split(".")[0] for m, al in PY_IMPORTS if al is None}:
            row(node, func, node.id, "VIOLATION", "uses a filesystem module the census does not model (fail-closed)")
            continue
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id in unmodelled:
            row(node, func, node.id, "VIOLATION", "uses a name bound by an unmodelled import (fail-closed)")
            continue
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in PY_DYNAMIC:
            a0 = node.args[0] if node.args else None
            if node.func.id != "getattr" or (isinstance(a0, ast.Name) and a0.id in
                                             {"os", "subprocess", "ctypes", "_libc", "importlib", "sys", "fcntl"}):
                row(node, func, node.func.id + "()", "VIOLATION",
                    "a dynamic lookup / evaluation the census cannot follow (fail-closed)")
            continue
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load) and node.id in PY_MODULE_OBJECTS:
            par0 = parent.get(id(node))
            if not (isinstance(par0, ast.Attribute) and par0.value is node):
                row(node, func, node.id, "VIOLATION", "the module object %s is used as a VALUE (passed, stored, "
                    "called): the census cannot follow what is done with it (fail-closed, round 14)" % node.id)
            continue
        if not isinstance(node, ast.Attribute):
            continue
        if node.attr.startswith("__") and node.attr.endswith("__"):
            row(node, func, "." + node.attr, "VIOLATION", "a dunder attribute (%s) reaches a callable / namespace past "
                "the census's model (.__call__, __getattribute__, __builtins__, __globals__, __dict__: fail-closed, "
                "round 14)" % node.attr)
            continue
        d = _dotted(node)
        par = parent.get(id(node))
        is_called = isinstance(par, ast.Call) and par.func is node
        if d is None:
            if node.attr in METHOD_OPS and is_called and (func, node.attr) not in PY_EXEMPT:
                row(node, func, "." + node.attr + "()", "VIOLATION",
                    "a path-acting method on an object the census cannot type (fail-closed)")
            elif node.attr in METHOD_OPS and is_called:
                row(node, func, node.attr, "EXEMPT", PY_EXEMPT[(func, node.attr)])
            continue
        head = d.split(".")[0]
        if isinstance(par, ast.Attribute) and _dotted(par) is not None:
            continue                                  # judged at the longest chain
        if d.startswith("os.path."):
            rest = d[len("os.path."):]
            if rest in OS_PATH_PURE:
                continue
            if rest in OS_PATH_READ and is_called:
                rows.append(_py_tagged(path, par, func, d, lines))
                continue
            row(node, func, d, "VIOLATION", "os.path.%s: not in the census's model (fail-closed)" % rest)
            continue
        if head in MODULE_ATTRS:
            if d.count(".") == 0 or d.split(".")[1] not in MODULE_ATTRS[head]:
                row(node, func, d, "VIOLATION", "%s: an attribute of %s outside MODULE_ATTRS (fail-closed, round 14)"
                    % (d, head))
            continue
        if head == "os" and d.count(".") >= 2 and d.split(".")[1] in PY_OPS:
            row(node, func, d, "VIOLATION", "%s: an attribute OF a path operation -- the census cannot see what it is "
                "applied to (fail-closed, round 14)" % d)
            continue
        if head == "os" and d.count(".") == 1:
            attr = d[3:]
            if attr in OS_PURE or attr.startswith("O_") or (attr[:1] == "W" and attr.isupper()):
                continue
            if attr in PY_OPS:
                if not is_called:
                    row(node, func, d, "VIOLATION", "a path operation REFERENCED, not called -- the census cannot "
                                                    "see what it is applied to (fail-closed)")
                    continue
                rows.append(_py_classify(path, par, func, d, lines, dirfd_ok, expr_proved, sc))
                continue
            if (func, d) in PY_EXEMPT and is_called:
                row(node, func, d, "EXEMPT", PY_EXEMPT[(func, d)])
                continue
            row(node, func, d, "VIOLATION", "%s: not in the census's model (fail-closed: OS_PURE / PY_OPS)" % d)
            continue
        if head == "subprocess":
            attr = d.split(".", 1)[1] if "." in d else ""
            if attr in SUBPROCESS_PURE:
                continue
            if (func, d) in PY_EXEMPT and is_called:
                row(node, func, d, "EXEMPT", PY_EXEMPT[(func, d)])
                continue
            row(node, func, d, "VIOLATION", "%s: runs a program outside the census's model (fail-closed)" % d)
            continue
        if head == "ctypes":
            attr = d.split(".", 1)[1] if "." in d else ""
            if attr in CTYPES_PURE:
                continue
            if (func, d) in PY_EXEMPT:
                row(node, func, d, "EXEMPT", PY_EXEMPT[(func, d)])
                continue
            row(node, func, d, "VIOLATION", "%s: not in the census's model (fail-closed)" % d)
            continue
        if head == "_libc":
            if d.split(".", 1)[1] not in LIBC_PURE:
                row(node, func, d, "VIOLATION", "a libc function outside LIBC_PURE (fail-closed)")
            continue
        if head == "importlib":
            if d in ("importlib.util", "importlib.util.module_from_spec"):
                continue
            if (func, d) in PY_EXEMPT and is_called:
                row(node, func, d, "EXEMPT", PY_EXEMPT[(func, d)])
                continue
            row(node, func, d, "VIOLATION", "%s: loads code from a path outside the census's model" % d)
            continue
        if node.attr in METHOD_OPS and is_called:
            if (func, node.attr) in PY_EXEMPT:
                row(node, func, node.attr, "EXEMPT", PY_EXEMPT[(func, node.attr)])
            else:
                row(node, func, d, "VIOLATION", "a path-acting method (fail-closed)")
    # ---- the builtin open() ----
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open":
            rows.append(_py_tagged(path, node, _sname(scope.get(id(node))), "builtin open", lines))
    return rows


def _py_tagged(path, call, func, name, lines):
    """a call allowed only with a checked `# safepath:<tag>` on its line"""
    line = lines[call.lineno - 1]
    arg0 = call.args[0] if call.args else None
    verdict, why = "VIOLATION", "a path operation outside the trusted-parent helpers"
    m = TAG_RE.search(line)
    if m:
        tag = m.group(1)
        if tag not in PY_TAGS:
            why = "unknown safepath tag %r (closed set: %s)" % (tag, ", ".join(sorted(PY_TAGS)))
        elif tag == "procfs":
            s0 = ast.unparse(arg0) if arg0 is not None else ""
            if name in PY_XATTR_WRITE:
                why = "tagged procfs but %s CHANGES the object (round 14: the tag covers queries only)" % name
            elif re.match(r"""^['"]/proc/[^'"]*['"]( % .*)?$""", s0) and ".." not in s0:
                verdict, why = "TAGGED", "procfs: kernel-owned (%s)" % s0[:40]
            else:
                why = "tagged procfs but the path is not a literal /proc/... (%s)" % s0[:40]
        elif tag == "devnull":
            if arg0 is not None and ast.unparse(arg0) == "os.devnull":
                verdict, why = "TAGGED", "devnull: the device is the intent"
            else:
                why = "tagged devnull but the path is not os.devnull"
        elif tag == "probe":
            if name in PY_READONLY:
                verdict, why = "TAGGED", "probe: a read-only query (%s)" % line.split("safepath:probe", 1)[1].strip()[:70]
            else:
                why = "tagged probe but %s is not a read-only query" % name
    return (os.path.basename(path), call.lineno, func, name, verdict, why)


def _py_classify(path, call, func, name, lines, dirfd_ok, expr_proved, sc):
    kws = {k.arg: k.value for k in call.keywords}
    arg0 = call.args[0] if call.args else None
    fdkw = sorted(set(kws) & {"dir_fd", "src_dir_fd", "dst_dir_fd"})
    if fdkw:
        if dirfd_ok(call, sc):
            return (os.path.basename(path), call.lineno, func, name, "ROUTED",
                    "relative to a PROVED directory fd (%s)" % ", ".join("%s=%s" % (k, ast.unparse(kws[k])) for k in fdkw))
        return (os.path.basename(path), call.lineno, func, name, "VIOLATION",
                "%s is not a PROVED directory fd (a constant, or a value not from the helpers)"
                % ", ".join("%s=%s" % (k, ast.unparse(kws[k])) for k in fdkw))
    if name in ("os.listdir", "os.scandir") and arg0 is not None and not isinstance(arg0, ast.Constant) \
            and not isinstance(arg0, (ast.BinOp, ast.JoinedStr)) and expr_proved(sc, arg0):
        return (os.path.basename(path), call.lineno, func, name, "ROUTED",
                "lists a PROVED directory through its fd (%s)" % ast.unparse(arg0))
    if name == "os.open" and func == "_walk" and isinstance(arg0, ast.Constant) and arg0.value == "/":
        return (os.path.basename(path), call.lineno, func, name, "ROOT", "the walk starts at '/' (rule 2)")
    return _py_tagged(path, call, func, name, lines)


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


def _heredoc_bodies(lines):
    """{line number of the command that opens a here-document: its body text}"""
    out, end, cur, start = {}, None, [], 0
    for no, raw in enumerate(lines, 1):
        if end is not None:
            if raw.strip() == end:
                out[start] = "\n".join(cur)
                end, cur = None, []
            else:
                cur.append(raw)
            continue
        if not raw.lstrip().startswith("#"):
            m = HEREDOC_RE.search(code_part(raw))
            if m:
                end, start = m.group(2), no
    return out


# ---- the shell census's closed tables ----
SH_NOOP = {"[", "[[", "((", ":", "true", "false", "echo", "printf", "local", "declare", "export", "readonly",
           "return", "exit", "shift", "set", "unset", "wait", "continue", "break", "case", "for", "read", "date",
           "basename", "dirname", "pwd", "kill", "sleep", "test", "fi", "done", "esac", "}",
           # probes: they name a path but open, create and remove nothing
           "cd", "df", "realpath"}
SH_READ = {"cat", "head", "tail", "grep", "awk", "sed"}           # file operands are READ (a FIFO there blocks)
SH_WRITE = {"rm", "rmdir", "mkdir", "mktemp", "touch", "mv", "cp", "ln", "tee", "cc"}
SH_WRAPPERS = {"env", "exec", "command"}
GIT_RO = {"rev-parse", "log", "cat-file", "ls-files", "show", "diff", "status"}
HEREDOC_PY_IMPORTS = {"json", "sys", "sqlite3", "statistics"}
# the closed, justified shell EXEMPTIONS: (function, the command text with whitespace collapsed) -> why
SH_EXEMPT = {
    ("run_gate_once", '"$@"'): "the GATE command line the caller passed with --gate-cmd (parsed into GATE_ARGV), run "
                               "under _fc_run_child: running it is the intent",
    ("emit_doc", "python3 -c 'import json,platform; print(json.dumps({\"host\": platform.node()}))'"):
        "prints this host's name: the program is a literal and opens nothing",
}
# programs run by path whose own file writes are outside this census (stated scope, CONVERGENCE.md)
SH_PROGRAMS = {
    ("emit_doc", '"$FC/lib/fc_common.py"'):
        "the report writer (lib/fc_common.py emit: a temp file + rename in --out's directory, which `_fc_safe mkdir` "
        "proved just before); the supervisor then verifies the file there by identity + body_hash (report_verified)",
}
# `cc -o` of the configured host tool: inside the replay worktree (ours alone), behind the canonical-path check
CC_EXEMPT = {("_do_one_replay_body", '"$_rt_bin"'):
             "the host tool compiled INSIDE the replay worktree (a directory of ours alone); a symlink escaping it is "
             "refused by the canonical-path check just above (the 2026-09-29 remediation)"}
_PLAIN_CMD = re.compile(r"^[A-Za-z0-9_.:/+\[\]-]+$")


def _unq(w):
    return w[1:-1] if len(w) >= 2 and w[0] == w[-1] == '"' else w


# round 15 (V4R15-2, §11.4.276(E) structural): the census no longer matches a variable NAME as the literal word the
# script wrote. A NAME goes through the shell's QUOTE REMOVAL first ('_X', "_X", \_X, -v"_X" all name _X), and a
# NAME any part of which is an EXPANSION ("$n", ${n}, $(..), `..`, $'..') is a name the census cannot know -- a
# VIOLATION in every variable-name position, whatever variable it would turn out to be.
# an expansion of a variable: ${V} / ${V:?msg} (group 2 = the :? guard) / $V
_EXP_RE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(:\?[^}]*)?\}|\$([A-Za-z_][A-Za-z0-9_]*)")


def _dq_chars(w):
    """quote removal, char by char: [(char, from_expansion)]; an expansion ($x ${..} $(..) $((..)) `..` $'..' $"..")
    is ONE ('$', True) item (its value is unknown to the census)"""
    out, i, n, q = [], 0, len(w), None

    def skip_exp(i):
        if w[i] == "`":
            k = i + 1
            while k < n and w[k] != "`":
                k += 2 if w[k] == "\\" else 1
            return k + 1
        if w.startswith(("$'", '$"'), i):
            k = i + 2
            while k < n and w[k] != w[i + 1]:
                k += 2 if w[k] == "\\" else 1
            return k + 1
        if w.startswith(("${", "$("), i):
            op = w[i + 1]
            cl = "}" if op == "{" else ")"
            d, k = 1, i + 2
            while k < n and d:
                if w[k] == "\\":
                    k += 2
                    continue
                if w[k] == op:
                    d += 1
                elif w[k] == cl:
                    d -= 1
                k += 1
            return k
        m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])", w[i:])
        return i + (m.end() if m else 1)
    while i < n:
        c = w[i]
        if q == "'":
            if c == "'":
                q = None
            else:
                out.append((c, False))
            i += 1
            continue
        if c == "\\":
            if i + 1 < n and (q is None or w[i + 1] in '$`"\\'):
                out.append((w[i + 1], False))
                i += 2
            else:
                out.append((c, False))
                i += 1
            continue
        if q == '"' and c == '"':
            q = None
            i += 1
            continue
        if q is None and c in "'\"":
            q = c
            i += 1
            continue
        if c == "`" or (c == "$" and i + 1 < n):
            out.append(("$", True))
            i = max(skip_exp(i), i + 1)
            continue
        out.append((c, False))
        i += 1
    return out


def _lit(w):
    """the literal text of word w after quote removal, or None when any part of it is an expansion"""
    ch = _dq_chars(w)
    return None if [1 for _c, d in ch if d] else "".join(c for c, _d in ch)


def _options(args, valued=""):
    """(the option letters, {letter: the chars of its value}, the operands) of a builtin's arguments, after quote
    removal: an option is a word starting with a literal - or + (before the first operand or '--'); a letter in
    `valued` takes the rest of its word (-v"_X") or the next word. A +X option REMOVES attribute X (its letter is not
    recorded). An EXPANSION where an option letter should be adds the letter '$' (the caller refuses it)."""
    letters, vals, i = set(), {}, 0
    while i < len(args):
        ch = _dq_chars(args[i])
        if len(ch) < 2 or ch[0] not in (("-", False), ("+", False)):
            break
        if [c for c, _d in ch] == ["-", "-"] and not ch[1][1]:
            i += 1
            break
        j = 1
        while j < len(ch):
            c, dyn = ch[j]
            if dyn:
                letters.add("$")
                break
            if ch[0][0] == "-":
                letters.add(c)
            if c in valued:
                if j + 1 < len(ch):
                    vals[c] = ch[j + 1:]
                else:
                    vals[c] = _dq_chars(args[i + 1]) if i + 1 < len(args) else []
                    i += 1
                break
            j += 1
        i += 1
    return letters, vals, args[i:]


# the builtins (in SH_NOOP) that take a variable NAME, and where (round 15, the closed list -- every other name-taking
# builtin of bash is outside the census's tables and refused as an unknown command: let, mapfile, readarray, getopts,
# select, coproc, builtin, enable, compgen, source, eval)
NAME_BUILTINS = {"printf": "printf -v NAME", "unset": "unset NAME...", "read": "read [-a NAME] NAME...",
                 "wait": "wait -p NAME", "local": "local NAME[=V]...", "declare": "declare NAME[=V]...",
                 "typeset": "typeset NAME[=V]...", "export": "export NAME[=V]...", "readonly": "readonly NAME[=V]..."}
DECLARE_FAMILY = ("local", "declare", "typeset", "export", "readonly")


def _name_words(w0, args):
    """[(chars of a NAME, role)] of every word of command w0 in a variable-NAME position, and the option letters: role
    'set' (the command assigns or unsets it: printf -v, read, wait -p, unset) or 'decl' (a declare-family operand,
    NAME or NAME=VALUE -- the provenance pass models its value)"""
    if w0 == "printf":
        letters, vals, _ops = _options(args, "v")
        return ([(vals["v"], "set")] if "v" in vals else []), letters
    if w0 == "unset":
        letters, _vals, ops = _options(args)
        return ([] if letters & {"f"} else [(_dq_chars(a), "set") for a in ops]), letters
    if w0 == "read":
        letters, vals, ops = _options(args, "adinNptu")
        return ([(vals["a"], "set")] if "a" in vals else []) + [(_dq_chars(a), "set") for a in ops], letters
    if w0 == "wait":
        letters, vals, _ops = _options(args, "p")
        return ([(vals["p"], "set")] if "p" in vals else []), letters
    if w0 in DECLARE_FAMILY:
        letters, _vals, ops = _options(args)
        out = []
        for a in ops:
            ch = _dq_chars(a)
            k = next((i for i, (c, d) in enumerate(ch) if c == "=" and not d), None)
            out.append((ch if k is None else ch[:k], "decl"))
        return out, letters
    return [], set()


def sh_census(path):
    lines = open(path).read().split("\n")
    cmds, funcs, extents = sh_commands(lines)
    bodies = _heredoc_bodies(lines)
    # ---- provenance: every assignment of every variable, by function ----
    assigns = {}                                          # (func, name) -> [value]
    gassigns = {}                                         # name -> [value]

    def note(func, name, val):
        assigns.setdefault((func, name), []).append(val)
        gassigns.setdefault(name, []).append((func, val))
    for cm in cmds:
        for w, _ln in cm["assigns"]:
            nm, val = w.split("=", 1)
            note(cm["func"], nm.rstrip("+").split("[")[0], val)
        if cm["cmd"] in DECLARE_FAMILY:                   # round 15: typeset too; NAMEs after quote removal
            for w in _options(cm["args"])[2]:
                ch = _dq_chars(w)
                k = next((i for i, (c, d) in enumerate(ch) if c == "=" and not d), None)
                if k is None or [1 for _c, d in ch[:k] if d]:
                    continue                              # no value / a non-literal NAME (refused by classify)
                nm = "".join(c for c, _d in ch[:k]).rstrip("+").split("[")[0]
                # a quoted NAME=VALUE word ("X=/etc") is an assignment the raw value split cannot read: unproved
                note(cm["func"], nm, w.split("=", 1)[1] if _ASSIGN_RE.match(w) else "<quoted assignment>")
        if cm["cmd"] == "read":                           # read's targets: values from input, never proved
            for ch, _role in _name_words("read", cm["args"])[0]:
                lit = None if [1 for _c, d in ch if d] else "".join(c for c, _d in ch)
                if lit and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", lit):
                    note(cm["func"], lit, "<read>")
        if cm["cmd"] == "for" and cm["args"]:
            note(cm["func"], cm["args"][0], "<for>")
    roots = ("$(_fc_safe mkdtemp ", "$(_fc_safe mkdir --exclusive ", "$(_fc_mktemp)")

    def mktemp_name_ok(name, func):
        """the NAME part of a mktemp template in $_FC_TMPDIR: no '/', no '..'; an expansion only of a parameter PARAMS
        lists for that function (a NAME component by its stated reason)"""
        if "/" in name or ".." in name:
            return False
        return all((func, v) in PARAMS for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", name)) \
            and not re.search(r"\$\{[^}]*[^A-Za-z0-9_}]", name)

    def is_file_rhs(func, rhs):
        r = _unq(rhs.strip())
        return r == "$(_fc_mktemp)" or bool(re.match(r'^\$\(mktemp "(\$_FC_TMPDIR|\$\{_FC_TMPDIR:\?[^}]*\})/[^"/]*"\)$', r))

    def rhs_proved(rhs, known, func="<top>"):
        r = _unq(rhs.strip())
        if r in ("", "''", "()"):
            return True                                   # cleared: holds nothing
        if r.startswith("<"):
            return False
        if any(r.startswith(x) for x in roots) and r.endswith(")"):
            return True
        if r in ("${FC_BR_TMPDIR}", "$FC_BR_TMPDIR", "${FC_BR_TMPDIR:-}"):
            return True                                   # proved --exclusive at worker start (_fc_worker_init)
        m = re.match(r'^\$\(mktemp (-d )?"(?:\$_FC_TMPDIR|\$\{_FC_TMPDIR:\?[^}]*\})/([^"/]*)"\)$', r)
        if m:
            return "_FC_TMPDIR" in known and mktemp_name_ok(m.group(2), func)
        return word_proved(r, known, copy_ok=True)

    def word_proved(r, known, copy_ok=False, guard=True):
        """the word starts with a proved variable and every other expansion in it is a proved variable; no '..'
        component, no '~'; a FILE variable (a $(_fc_mktemp) / mktemp result) may carry a plain suffix ($marker.t: a
        sibling in the same proved directory) -- a directory variable may not ($dir.x is outside it).
        ROUND 15 (V4R15-2, the CLEARED / emptied class -- §11.4.276(E) structural): every expansion of a proved
        variable in it must be ${V:?...} (bash aborts the command when V is empty or unset), so NO way of emptying a
        proved variable (V="", local V, unset V, a function that never assigns its local, ...) can make a path
        operand "/suffix" or ""  -- measured: `cp -r d ""` copies into the CWD, `awk 1 ""` reads stdin
        (v4_round9_20261014/logs/empty_operand_probe.log). copy_ok: a provenance RIGHT-HAND side that is exactly
        $V / ${V} (a copy: an empty value stays empty and is guarded where IT is used). guard=False: the round-14
        test, used only to word the refusal reason."""
        m = _EXP_RE.match(r)
        if not m:
            return False
        var = m.group(1) or m.group(3)
        if var not in known:
            return False
        rest = r[m.end():]
        if guard and not m.group(2) and not (copy_ok and rest == ""):
            return False
        if rest and not rest.startswith("/"):
            return var in files and bool(re.match(r"^[A-Za-z0-9_.+-]+$", rest))
        if re.search(r"(^|/)\.\.(/|$)", rest) or "~" in rest or "`" in rest or "$(" in rest:
            return False
        exps = list(_EXP_RE.finditer(rest))
        if rest.count("$") != len(exps):
            return False                                  # an expansion of another form (${v:-x}, $1, ...)
        for e in exps:
            v = e.group(1) or e.group(3)
            if v not in known or (guard and not e.group(2)):
                return False
        return True
    proved = set(gassigns) | {"_FC_TMPDIR"}
    files = {v for v, vals in gassigns.items()
             if [x for f, x in vals if _unq(x.strip()) not in ("", "''")] and
             all(is_file_rhs(f, x) for f, x in vals if _unq(x.strip()) not in ("", "''"))}
    changed = True
    while changed:                                        # the GREATEST fixed point (monotone)
        changed = False
        for v in sorted(proved):
            if not all(rhs_proved(x, proved, f) for f, x in gassigns.get(v, [])):
                proved.discard(v)
                changed = True
    # a variable assigned only from FILE variables is a file variable too
    changed = True
    while changed:
        changed = False
        for v, vals in gassigns.items():
            nz = [x for f, x in vals if _unq(x.strip()) not in ("", "''")]
            if v not in files and nz and all(re.match(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$", _unq(x.strip())) and
                                              re.match(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)", _unq(x.strip())).group(1)
                                              in files for x in nz):
                files.add(v)
                changed = True

    def proved_in(fn, v):
        own = [a for a in assigns.get((fn, v), []) if _unq(a.strip()) not in ("", "''")]
        if own:
            return all(rhs_proved(x, proved, fn) for x in own)
        return v in proved

    def known_in(fn):
        class K:
            def __contains__(self, v):
                return proved_in(fn, v)
        return K()
    rows = []

    def tag_at(no):
        raw = lines[no - 1] if no - 1 < len(lines) else ""
        tagm = TAG_RE.search(raw)
        k = no - 2
        while tagm is None and k >= 0 and lines[k].lstrip().startswith("#"):
            tagm = TAG_RE.search(lines[k])
            k -= 1
        return tagm.group(1) if tagm else None

    def operand(cm, w, kind, read=False):
        """the verdict of one path operand w of operation `kind` in command cm"""
        func, no = cm["func"], cm["line"]
        tag = tag_at(no)
        u = _unq(w)
        if u == "/dev/null":
            return ("TAGGED", "devnull") if tag == "devnull" or True else None
        if read and re.match(r"^/proc/[A-Za-z0-9_/]+$", u) and ".." not in u:
            return "TAGGED", "procfs: kernel-owned (%s)" % u
        if tag == "msg":
            return "VIOLATION", "tagged msg but an operation remains outside the quoted text"
        if tag == "param":
            vs = re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", u)
            ps = [v for v in vs if (func, v) in PARAMS]
            rest = [v for v in vs if (func, v) not in PARAMS and not proved_in(func, v)]
            # round 15: a proved variable in a param-tagged operand is ${V:?}-guarded like any other
            rest += [v for v in vs if (func, v) not in PARAMS and proved_in(func, v) and
                     not re.search(r"\$\{%s:\?" % re.escape(v), u)]
            if ps and not rest and ".." not in u and "~" not in u:
                return "TAGGED", "param: " + "; ".join(PARAMS[(func, v)] for v in ps)
            return "VIOLATION", "tagged param but %r is not a listed parameter of %s" % (rest or vs, func)
        if tag is not None and tag not in SH_TAGS:
            return "VIOLATION", "unknown safepath tag %r (closed set: %s)" % (tag, ", ".join(sorted(SH_TAGS)))
        if word_proved(u, known_in(func)):
            return "PRIVATE", "inside a proved directory (%s)" % ", ".join(
                sorted(set(re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", u))))
        if word_proved(u, known_in(func), guard=False):
            return "VIOLATION", ("%s on %s: a proved variable expanded WITHOUT ${V:?} may expand EMPTY (V=\"\", local "
                                 "V, unset V) -- \"/suffix\" or \"\" (round 15, V4R15-2)" % (kind, w[:60]))
        return "VIOLATION", "%s on an operand that is not proved (%s)" % (kind, w[:60])

    def add(cm, kind, verdict, why):
        rows.append((os.path.basename(path), cm["line"], cm["func"], kind, verdict, why))

    def operands(words, valued=()):
        out, skip, ddash = [], False, False
        for w in words:
            if skip:
                skip = False
                continue
            if not ddash and w == "--":
                ddash = True
                continue
            if not ddash and w.startswith("-") and len(w) > 1:
                if w in valued:
                    skip = True
                continue
            out.append(w)
        return out

    def classify(cm, words, depth=0):
        """one command (words[0] = the command word) of cm"""
        if not words:
            return
        w0, args = words[0], words[1:]
        func = cm["func"]
        flat = " ".join([w0] + args)
        if (func, flat) in SH_EXEMPT:
            add(cm, w0, "EXEMPT", SH_EXEMPT[(func, flat)])
            return
        if w0 == '"$BASH"' and args[:1] == ["-c"] and len(args) > 1 and args[1][:1] == "'" and args[1][-1:] == "'":
            sub = _ShLex(args[1][1:-1], cm["line"])           # a literal program: lexed and censused like any code
            sub.parse_list(0, None)
            for scm in sub.cmds:
                scm["func"] = func
                if scm["cmd"]:
                    classify(scm, [scm["cmd"]] + scm["args"], depth + 1)
            return
        if not _PLAIN_CMD.match(w0) and w0 not in ("[[", "((", "}", "{"):
            add(cm, w0[:40], "VIOLATION", "a quoted / escaped / indirect command word -- the census cannot see what "
                                         "runs (fail-closed)")
            return
        if w0 == "eval" or w0 in ("sh", "bash", "dash", "zsh", "ksh", "source", "."):
            add(cm, w0, "VIOLATION", "%s runs text the census cannot see (fail-closed)" % w0)
            return
        if w0 in funcs:
            if w0 == "_fc_safe":
                if args and args[0] in ("check", "mkdir", "mkdtemp", "write", "rmtree"):
                    add(cm, "_fc_safe", "ROUTED", "the trusted-parent helper (%s)" % args[0])
                else:
                    add(cm, "_fc_safe", "VIOLATION", "_fc_safe with an operation outside its closed set")
                return
            if w0 == "_fc_run_child" and "--" in args:
                classify(cm, args[args.index("--") + 1:], depth + 1)
            return                                        # a function of this file: its body is censused
        if w0 in SH_WRAPPERS:
            rest = list(args)
            if w0 == "command":
                if rest[:1] == ["-v"]:
                    return
            elif w0 == "env":
                while rest and (rest[0].startswith("-") or _ASSIGN_RE.match(rest[0])):
                    if rest[0] in ("-u", "--unset", "-C", "--chdir", "-S"):
                        if rest[0] in ("-C", "--chdir", "-S"):
                            add(cm, "env " + rest[0], "VIOLATION", "env %s: not in the census's model" % rest[0])
                            return
                        rest = rest[2:]
                    else:
                        rest = rest[1:]
            elif w0 == "exec" and rest[:1] == ['${blk[@]+"${blk[@]}"}']:
                vals = assigns.get((func, "blk"), [])
                if vals and all(v in ("()", "(env --block-signal=INT)") for v in vals):
                    rest = ["env", "--block-signal=INT"] + rest[1:]
                else:
                    add(cm, "exec ${blk...}", "VIOLATION", "exec through an array not assigned only "
                                                           "(env --block-signal=INT)")
                    return
            classify(cm, rest, depth + 1)
            return
        # round 14 (V4R14-2) -> round 15 (V4R15-2, the CLASS): every variable-NAME position of every name-taking
        # builtin the tables admit (NAME_BUILTINS), after quote removal; each a VIOLATION at its own line
        if w0 in NAME_BUILTINS:
            words, letters = _name_words(w0, args)
            if "$" in letters:
                add(cm, w0 + " -$X", "VIOLATION", "an option word of %s holds an expansion: the census cannot know "
                    "which option (or which NAME) it is (fail-closed, round 15)" % w0)
                return
            if w0 in ("local", "declare", "typeset") and "n" in letters and \
                    [a for a in args if (_lit(a) or "").startswith("-") and "n" in (_lit(a) or "")]:
                add(cm, w0 + " -n", "VIOLATION", "a NAMEREF: an assignment through it changes another variable the "
                                                "provenance pass cannot follow (fail-closed, round 14)")
                return
            what = {"printf": "printf -v assigns", "unset": "unset of", "wait": "wait -p assigns"}
            for ch, role in words:
                if [1 for _c, d in ch if d]:
                    add(cm, w0 + " $NAME", "VIOLATION", "a non-literal variable NAME (%s) in a name position of %s: "
                        "the census cannot know which variable it changes (fail-closed, round 15)"
                        % ("".join(c for c, _d in ch)[:30], NAME_BUILTINS[w0]))
                    return
                nm = "".join(c for c, _d in ch).rstrip("+").split("[")[0]
                if nm not in proved:
                    continue
                if role == "set" and w0 == "read":
                    continue                              # MODELLED: read's targets are un-proved ('<read>')
                if role == "set":
                    add(cm, w0 if w0 not in ("printf", "wait") else w0 + (" -v" if w0 == "printf" else " -p"),
                        "VIOLATION", "%s the PROVED variable %s outside the provenance model -- it would expand to a "
                        "value the census never proved, or EMPTY (fail-closed, round 14/15)" % (what[w0], nm))
                    return
                attrs = letters & set("ilucaAt")
                if attrs:
                    add(cm, w0 + " -" + "".join(sorted(attrs)), "VIOLATION", "an attribute (-%s) on the PROVED variable "
                        "%s changes every later value given to it (-i arithmetic, -l/-u/-c case, -a/-A array): "
                        "outside the provenance model (fail-closed, round 15)" % ("".join(sorted(attrs)), nm))
                    return
        if w0 in SH_NOOP:
            if w0 == "trap" or (w0 == "command" and args[:1] != ["-v"]):
                pass
            return
        if w0 == "trap":
            return
        if w0 in SH_READ:
            if w0 == "sed" and [a for a in args if a == "-i" or a.startswith(("-i", "--in-place"))]:
                add(cm, "sed -i", "VIOLATION", "sed -i writes its file operands (not in the census's model)")
                return
            valued = {"cat": (), "head": ("-c", "-n"), "tail": ("-c", "-n"), "grep": ("-e", "-f", "-m", "-A", "-B", "-C"),
                      "awk": ("-F", "-v", "-f"), "sed": ("-e", "-f")}[w0]
            ops = operands(args, valued)
            if w0 in ("grep", "sed") and not [a for a in args if a in ("-e", "-f")] and ops:
                ops = ops[1:]                             # the pattern / script
            if w0 == "awk" and "-f" not in args and ops:
                ops = [o for o in ops[1:] if not _ASSIGN_RE.match(o)]
            for o in ops:
                v, why = operand(cm, o, w0, read=True)
                add(cm, w0, v, why)
            return
        if w0 in SH_WRITE:
            if w0 == "cc":
                if "-o" in args:
                    tgt = args[args.index("-o") + 1] if args.index("-o") + 1 < len(args) else ""
                    if (func, tgt) in CC_EXEMPT:
                        add(cm, "cc -o", "EXEMPT", CC_EXEMPT[(func, tgt)])
                    else:
                        v, why = operand(cm, tgt, "cc -o")
                        add(cm, "cc -o", v, why)
                    return
                add(cm, "cc", "VIOLATION", "cc without -o writes a.out in the cwd")
                return
            ops = operands(args, ("-m", "-p", "--tmpdir", "-t", "-S", "--suffix") if w0 in ("mktemp", "mkdir") else ())
            if not ops and w0 != "mktemp":
                return
            if w0 == "mktemp" and not ops:
                add(cm, "mktemp", "VIOLATION", "mktemp without a template uses $TMPDIR (not proved)")
                return
            for o in ops:
                v, why = operand(cm, o, w0)
                add(cm, w0, v, why)
            return
        if w0 == "python3":
            i = 0
            while i < len(args) and args[i].startswith("-") and args[i] not in ("-", "-c"):
                i += 1
            prog = args[i] if i < len(args) else ""
            if prog == '"$_FC_SUPERVISOR"':
                add(cm, "python3 supervisor", "ROUTED", "the supervisor module (censused above as Python)")
            elif (func, prog) in SH_PROGRAMS:
                add(cm, "python3 " + prog, "EXEMPT", SH_PROGRAMS[(func, prog)])
            elif prog == "-" and any(r[0] in ("<<", "<<-") for r in cm["redirs"]) and depth == 0:
                keys = [k for k in bodies if k >= cm["line"]]
                body = bodies.get(min(keys)) if keys else None
                bad = _heredoc_py_bad(body) if body is not None else "its here-document body was not found"
                if bad:
                    add(cm, "python3 heredoc", "VIOLATION", "the here-document program is not read-only: " + bad)
                else:
                    add(cm, "python3 heredoc", "TAGGED", "a READ-ONLY program (imports json/sys/sqlite3/statistics "
                        "only; open() for reading; sqlite3 only mode=ro): it reads the files it is handed")
            else:
                add(cm, "python3 " + prog[:30], "VIOLATION", "python3 running a program the census does not model "
                                                             "(fail-closed)")
            return
        if w0 == "git":
            i, cdir = 0, None
            while i < len(args) and args[i].startswith("-"):
                if args[i] in ("-C", "-c"):
                    if args[i] == "-C":
                        cdir = args[i + 1] if i + 1 < len(args) else ""
                    i += 2
                else:
                    i += 1
            sub = args[i] if i < len(args) else ""
            rest = args[i + 1:]
            if sub in GIT_RO:
                return
            if sub == "config" and [a for a in rest if a in ("--get", "--get-regexp", "--get-all", "-l", "--list")]:
                return
            if sub == "worktree" and rest:
                op = rest[0]
                if op == "list":
                    return
                if op == "prune" and len(rest) == 1:
                    add(cm, "git worktree prune", "TAGGED", "git's own administrative entries of worktrees that no "
                        "longer exist, in the repository's git directory")
                    return
                if op in ("add", "remove", "unlock"):
                    ops = operands(rest[1:])
                    if op == "add":
                        ops = ops[:1]                     # the path (the commit-ish after it is not a path)
                    for o in ops:
                        v, why = operand(cm, o, "git worktree " + op)
                        add(cm, "git worktree " + op, v, why)
                    return
            if sub == "submodule" and cdir is not None:
                v, why = operand(cm, cdir, "git -C ... submodule")
                add(cm, "git submodule (in -C)", v, why)
                return
            add(cm, ("git " + sub + " " + (rest[0] if rest else "")).strip(), "VIOLATION",
                "a git sub-command the census does not model (fail-closed)")
            return
        add(cm, w0, "VIOLATION", "a command word not in the census's tables (fail-closed: SH_NOOP / SH_READ / "
                                 "SH_WRITE / git / python3 / this file's functions)")

    for cm in cmds:
        w0 = cm["cmd"]
        if w0 is not None:
            classify(cm, [w0] + cm["args"])
            if w0 == "trap" and cm["args"]:
                act = cm["args"][0]
                if "$" in act or "`" in act:
                    add(cm, "trap", "VIOLATION", "a trap action with an expansion (fail-closed)")
                else:
                    sub = _ShLex(act[1:-1] if act[:1] in "'\"" else act, cm["line"])
                    sub.parse_list(0, None)
                    for scm in sub.cmds:
                        scm["func"] = cm["func"]
                        if scm["cmd"]:
                            classify(scm, [scm["cmd"]] + scm["args"])
        for op, tgt, _ln in cm["redirs"]:
            if op in ("<<", "<<-", "<<<"):
                continue
            if op in (">&", "<&") or op.endswith(">&") or op.endswith("<&"):
                if re.match(r"^-?[0-9]*-?$", _unq(tgt)):
                    continue                              # an fd (2>&1, >&2, <&-)
            if tgt.startswith("&") or _unq(tgt) == "/dev/null":
                continue
            kind = "redirect" + op.lstrip("0123456789&")
            v, why = operand(cm, tgt, kind, read=(op.endswith("<") and not op.endswith("<>")))
            add(cm, kind, v, why)
    # a msg tag on a line with no operation at all -- the keyword is quoted text: one row says so
    oplines = {r[1] for r in rows}
    for no, raw in enumerate(lines, 1):
        m = TAG_RE.search(raw)
        if m and m.group(1) == "msg" and no not in oplines:
            rows.append((os.path.basename(path), no, func_at(extents, no), "(message)", "TAGGED",
                         "msg: the keyword appears only inside quoted text"))
    rows += sh_assign_scan(path, lines, proved, extents)
    return rows, proved


# round 15 (V4R15-2): the assignment forms that are not a command's NAME operand -- found in the script's EXPANDED
# text (comments removed; a here-document body kept when its delimiter is UNQUOTED: the shell expands it; trap
# actions and `"$BASH" -c '...'` programs are in the text too), so a context the lexer does not model (a case
# subject or pattern, a here-document, an arithmetic command) cannot hide one:
#   ${V=..} ${V:=..} ${V[i]:=..}   assign V when unset / empty            -> VIOLATION for a PROVED V
#   ${!R=..} ${!R:=..}            assign the variable R NAMES             -> VIOLATION always (unknown target)
#   arithmetic: (( )), $(( )), $[ ], [[ ]], a NAME[..] subscript, a ${V:offset:length}
#               V = .. / V op= .. / V++ / ++V / V-- / --V                -> VIOLATION for a PROVED V
#   {V}>file / {V}<file           a redirection that stores an fd in V  -> VIOLATION for a PROVED V
_ARITH_OPS = r"(?:=(?!=)|[-+*/%&|^]=|<<=|>>=|\+\+|--)"


def _sh_text_lines(lines):
    """[(line number, text)] of the script as the shell EXPANDS it (see above)"""
    out, end, quoted = [], None, False
    for no, raw in enumerate(lines, 1):
        if end is not None:
            if raw.strip() == end:
                end = None
            elif not quoted:
                out.append((no, raw))
            continue
        if raw.lstrip().startswith("#"):
            continue
        code = code_part(raw)
        out.append((no, code))
        m = HEREDOC_RE.search(code)
        if m:
            end, quoted = m.group(2), bool(m.group(1))
    return out


def _balanced(t, i, opener, closer, depth=1):
    """the text from index i to the matching closer (exclusive)"""
    k = i
    while k < len(t) and depth:
        if t.startswith(closer, k):
            depth -= 1
            if not depth:
                break
            k += len(closer)
            continue
        if t.startswith(opener, k):
            depth += 1
            k += len(opener)
            continue
        k += 1
    return t[i:k]


def _arith_spans(t):
    """the ARITHMETIC texts of one line (see above)"""
    spans = []
    for m in re.finditer(r"\(\(", t):
        spans.append(_balanced(t, m.end(), "(", ")", 2))
    for m in re.finditer(r"\$\[", t):
        spans.append(_balanced(t, m.end(), "[", "]"))
    for m in re.finditer(r"\[\[", t):
        k = t.find("]]", m.end())
        spans.append(t[m.end():k if k >= 0 else len(t)])
    for m in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*\[", t):
        spans.append(_balanced(t, m.end(), "[", "]"))
    for m in re.finditer(r"\$\{[A-Za-z_][A-Za-z0-9_]*:(?![-=?+])", t):
        spans.append(_balanced(t, m.end(), "{", "}"))
    return spans


def sh_assign_scan(path, lines, proved, extents):
    """census rows for the assignment forms above (each a VIOLATION at its own line)"""
    rows, seen = [], set()
    name = os.path.basename(path)

    def add(no, kind, why):
        if (no, kind) not in seen:
            seen.add((no, kind))
            rows.append((name, no, func_at(extents, no), kind, "VIOLATION", why))
    pats = {v: re.compile(r"(?<![\w$])%s\s*(?:\[[^\]]*\])?\s*%s|(?:\+\+|--)\s*%s(?!\w)"
                          % (re.escape(v), _ARITH_OPS, re.escape(v))) for v in proved}
    for no, t in _sh_text_lines(lines):
        for m in re.finditer(r"\$\{(!?)([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?:?=", t):
            if m.group(1):
                add(no, "${!R:=}", "an INDIRECT default assignment ${!%s=...}: it assigns whatever variable %s names "
                    "-- the census cannot know which (fail-closed, round 15)" % (m.group(2), m.group(2)))
            elif m.group(2) in proved:
                add(no, "${V:=}", "a default assignment ${%s:=...} of the PROVED variable %s outside the provenance "
                    "model (fail-closed, round 15)" % (m.group(2), m.group(2)))
        spans = _arith_spans(t)
        for v, pat in pats.items():
            if [sp for sp in spans if pat.search(sp)]:
                add(no, "arith " + v, "an ARITHMETIC assignment to the PROVED variable %s (( ), $(( )), [[ ]], a "
                    "subscript or an offset): outside the provenance model (fail-closed, round 15)" % v)
        for m in re.finditer(r"\{([A-Za-z_][A-Za-z0-9_]*)\}\s*(?:[<>]|&>)", t):
            if m.group(1) in proved:
                add(no, "{V}>", "a {%s}> redirection stores an fd NUMBER in the PROVED variable %s (fail-closed, "
                    "round 15)" % (m.group(1), m.group(1)))
    return rows


def _heredoc_py_bad(body):
    """'' when the here-document Python program is READ-ONLY by construction, else the first reason it is not"""
    try:
        tree = ast.parse(body)
    except SyntaxError as e:
        return "does not parse (%s)" % e
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for al in n.names:
                if al.name not in HEREDOC_PY_IMPORTS or al.asname:
                    return "imports %s" % al.name
        elif isinstance(n, ast.ImportFrom):
            return "a from-import"
        elif isinstance(n, ast.Name) and n.id in PY_DYNAMIC | {"os", "shutil", "subprocess"}:
            return "uses %s" % n.id
        elif isinstance(n, ast.Call):
            f = n.func
            if isinstance(f, ast.Name) and f.id == "open":
                mode = n.args[1] if len(n.args) > 1 else next((k.value for k in n.keywords if k.arg == "mode"), None)
                if mode is not None and not (isinstance(mode, ast.Constant) and mode.value in ("r", "rb", "rt")):
                    return "open() with mode %s" % ast.unparse(mode)
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "sqlite3":
                a0 = ast.unparse(n.args[0]) if n.args else ""
                uri = any(k.arg == "uri" and isinstance(k.value, ast.Constant) and k.value.value is True
                          for k in n.keywords)
                if f.attr != "connect" or "mode=ro" not in a0 or not uri:
                    return "sqlite3.%s not read-only (%s)" % (f.attr, a0[:40])
            if isinstance(f, ast.Attribute) and f.attr in METHOD_OPS:
                return "calls .%s()" % f.attr
    return ""


# --------------------------------------------------------------------------------------------------------------------
# THE SHELL LEXER (round 13, V4R13-3: fail-closed). Every SIMPLE COMMAND of the script -- at the top level, inside
# $( ), backticks, <( ) / >( ), subshells, { } groups, if/while/until/for/case bodies and [[ ]] -- is found with its
# COMMAND WORD (raw: quotes and backslashes kept), its arguments, its redirections and its leading assignments. The
# census then requires every command word to be a plain word from a CLOSED table (SH_KNOWN); a quoted, escaped or
# indirect command word ("rm", \rm, ${X:-rm}, $cmd), eval, and any word the table does not know are VIOLATIONS --
# the census no longer has to recognise a dangerous command to refuse it. Here-document bodies are data (blanked
# before lexing; the python3 programs among them are a closed, stated exemption -- HEREDOC_PY).
# --------------------------------------------------------------------------------------------------------------------
_ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")
_REDIR_RE = re.compile(r"([0-9]*|&)(>>|>\||>&|>|<<<|<<-|<<|<>|<&|<)")
_LEAD = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "time"}
_END = {"fi", "done", "esac", "}"}


class _ShLex:
    def __init__(self, text, base_line=1):
        self.s = text
        self.n = len(text)
        self.base = base_line
        self.cmds = []
        self.funcs = []                  # (name, line)
        self.extents = []                # (name, first line, last line) of every function body
        self.depth = 0                   # { } nesting
        self.fstack = []                 # (name, depth at its {, first line)
        self.pending = None              # a name() seen, its { not yet
        self._nl = [i for i, ch in enumerate(text) if ch == "\n"]

    def line(self, i):
        import bisect
        return self.base + bisect.bisect_left(self._nl, i)

    # ---- low level ----
    def blank(self, i, newlines=False):
        s = self.s
        while i < self.n:
            if s[i] in " \t" or (newlines and s[i] == "\n"):
                i += 1
            elif s.startswith("\\\n", i):
                i += 2
            else:
                break
        return i

    def at_word(self, i, w):
        j = i + len(w)
        return self.s.startswith(w, i) and (j >= self.n or self.s[j] in " \t\n;&|()<>")

    def skip_balanced(self, i, depth=1, opener="(", closer=")"):
        """i is just after an opener; returns the index after the matching closer (quotes honoured)"""
        s = self.s
        while i < self.n and depth:
            c = s[i]
            if c == "\\":
                i += 2
                continue
            if c == "'":
                k = s.find("'", i + 1)
                i = (k if k >= 0 else self.n - 1) + 1
                continue
            if c == '"':
                i = self.dq(i + 1, [])
                continue
            if c == opener:
                depth += 1
            elif c == closer:
                depth -= 1
            i += 1
        return i

    def dq(self, i, out):
        """inside "...": returns the index after the closing quote; nested $( ) / ` ` are lexed"""
        s = self.s
        while i < self.n:
            c = s[i]
            if c == "\\":
                out.append(s[i:i + 2])
                i += 2
                continue
            if c == '"':
                return i + 1
            if c == "$" and s.startswith("$((", i):
                j = self.skip_balanced(i + 3, 2)
                out.append(s[i:j])
                i = j
                continue
            if c == "$" and s.startswith("$(", i):
                j = self.parse_list(i + 2, ")")
                out.append(s[i:j])
                i = j
                continue
            if c == "$" and s.startswith("${", i):
                j = self.brace(i + 2)
                out.append(s[i:j])
                i = j
                continue
            if c == "`":
                j = self.backtick(i)
                out.append(s[i:j])
                i = j
                continue
            out.append(c)
            i += 1
        return i

    def brace(self, i):
        """inside ${ ... }: returns the index after the matching }; nested $( ) lexed"""
        s = self.s
        depth = 1
        while i < self.n and depth:
            c = s[i]
            if c == "\\":
                i += 2
                continue
            if c == "'":
                k = s.find("'", i + 1)
                i = (k if k >= 0 else self.n - 1) + 1
                continue
            if c == '"':
                i = self.dq(i + 1, [])
                continue
            if s.startswith("$(", i) and not s.startswith("$((", i):
                i = self.parse_list(i + 2, ")")
                continue
            if s.startswith("${", i):
                depth += 1
                i += 2
                continue
            if c == "}":
                depth -= 1
            i += 1
        return i

    def backtick(self, i):
        s = self.s
        j = i + 1
        while j < self.n and s[j] != "`":
            j += 2 if s[j] == "\\" else 1
        inner = _ShLex(s[i + 1:j].replace("\\`", "`"), self.line(i + 1))
        inner.parse_list(0, None)
        self.cmds.extend(inner.cmds)
        return j + 1

    def read_word(self, i):
        s = self.s
        out = []
        start = i
        if s.startswith(("<(", ">("), i):
            j = self.parse_list(i + 2, ")")
            return s[i:j], j
        while i < self.n:
            c = s[i]
            if c in " \t\n;&|()<>":
                if c == "(" and _ASSIGN_RE.match("".join(out)) and "".join(out).endswith("="):
                    j = self.skip_balanced(i + 1)          # NAME=( ... ): an array literal, part of the word
                    out.append(s[i:j])
                    i = j
                    continue
                break
            if s.startswith("\\\n", i):
                i += 2
                continue
            if c == "\\":
                out.append(s[i:i + 2])
                i += 2
                continue
            if c == "'":
                k = s.find("'", i + 1)
                k = k if k >= 0 else self.n - 1
                out.append(s[i:k + 1])
                i = k + 1
                continue
            if c == "$" and s.startswith("$'", i):
                k = i + 2
                while k < self.n and s[k] != "'":
                    k += 2 if s[k] == "\\" else 1
                out.append(s[i:k + 1])
                i = k + 1
                continue
            if c == '"' or (c == "$" and s.startswith('$"', i)):
                q = i + (2 if c == "$" else 1)
                j = self.dq(q, [])
                out.append(s[i:j])
                i = j
                continue
            if c == "$" and s.startswith("$((", i):
                j = self.skip_balanced(i + 3, 2)
                out.append(s[i:j])
                i = j
                continue
            if c == "$" and s.startswith("$(", i):
                j = self.parse_list(i + 2, ")")
                out.append(s[i:j])
                i = j
                continue
            if c == "$" and s.startswith("${", i):
                j = self.brace(i + 2)
                out.append(s[i:j])
                i = j
                continue
            if c == "`":
                j = self.backtick(i)
                out.append(s[i:j])
                i = j
                continue
            out.append(c)
            i += 1
        return s[start:i], i

    def comment(self, i):
        k = self.s.find("\n", i)
        return self.n if k < 0 else k

    # ---- grammar ----
    def parse_list(self, i, stop):
        """commands until `stop`: ')' (consumed, the index after it is returned), 'case' (an item's end: ;; ;& ;;&
        or the word esac -- not consumed), None (end of text)"""
        s = self.s
        while i < self.n:
            i = self.blank(i)
            if i >= self.n:
                break
            c = s[i]
            if stop == "case" and (s.startswith((";;", ";&"), i) or self.at_word(i, "esac")):
                return i
            if c in "\n;":
                i += 1
                continue
            if c == "#":
                i = self.comment(i)
                continue
            if c == ")":
                if stop == ")":
                    return i + 1
                i += 1
                continue
            if c in "&|":
                i += 2 if s[i:i + 2] in ("&&", "||", "|&") else 1
                continue
            if c == "(":
                if s.startswith("((", i):
                    i = self.skip_balanced(i + 2, 2)
                    continue
                i = self.parse_list(i + 1, ")")
                continue
            i = self.parse_command(i, stop)
        return i

    def parse_command(self, i, stop):
        s = self.s
        rec = {"line": self.line(i), "cmd": None, "args": [], "redirs": [], "assigns": []}
        while i < self.n:
            i = self.blank(i)
            if i >= self.n:
                break
            c = s[i]
            if not s.startswith(("<(", ">("), i):
                m = _REDIR_RE.match(s, i)
                if m:                                   # [N]> >> >| <> < << <<- <<< >& <& &> &>>
                    i = self.blank(m.end())
                    tgt, i = self.read_word(i)
                    rec["redirs"].append((m.group(1) + m.group(2), tgt, self.line(m.start())))
                    continue
            if c in "\n;&|)":
                break
            if c == "#":
                i = self.comment(i)
                break
            if rec["cmd"] is None and stop == "case" and self.at_word(i, "esac"):
                break
            if c == "(":
                if rec["cmd"] is not None and re.match(r"\(\s*\)", s[i:i + 8]) and not rec["args"]:
                    self.funcs.append((rec["cmd"], rec["line"]))      # name() -- a function definition
                    self.pending = (rec["cmd"], rec["line"])
                    i = s.index(")", i) + 1
                    rec = {"line": self.line(i), "cmd": None, "args": [], "redirs": [], "assigns": []}
                    continue
                if rec["cmd"] is None and s.startswith("((", i):
                    i = self.skip_balanced(i + 2, 2)
                    rec["cmd"] = "(("
                    continue
                if rec["cmd"] is None:
                    i = self.parse_list(i + 1, ")")
                    continue
                break
            w, i = self.read_word(i)
            if w == "":
                i += 1
                continue
            if rec["cmd"] is None:
                if w == "{":
                    if self.pending:
                        self.fstack.append((self.pending[0], self.depth, self.pending[1]))
                        self.pending = None
                    self.depth += 1
                if w == "}":
                    self.depth -= 1
                    if self.fstack and self.fstack[-1][1] == self.depth:
                        nm, _d, first = self.fstack.pop()
                        self.extents.append((nm, first, self.line(i)))
                if w in _LEAD:
                    rec["line"] = self.line(i)
                    continue
                if not rec["args"] and _ASSIGN_RE.match(w):
                    rec["assigns"].append((w, rec["line"]))
                    continue
                rec["cmd"] = w
                rec["line"] = self.line(i - len(w))
                if w == "[[":
                    i = self.dbracket(i, rec)
                elif w == "case":
                    self.cmds.append(rec)
                    return self.case(i)
                elif w == "for":
                    i = self.blank(i)
                    if s.startswith("((", i):
                        i = self.skip_balanced(i + 2, 2)
                    else:
                        while i < self.n and s[i] not in "\n;":
                            if s[i] == "#":
                                i = self.comment(i)
                                break
                            if s[i] in " \t":
                                i += 1
                                continue
                            ww, i = self.read_word(i)
                            rec["args"].append(ww)
                    break
                elif w == "function":
                    i = self.blank(i)
                    nm, i = self.read_word(i)
                    self.funcs.append((nm, rec["line"]))
                    self.pending = (nm, rec["line"])
                    i = self.blank(i)
                    if s.startswith("()", i):
                        i += 2
                    rec = {"line": self.line(i), "cmd": None, "args": [], "redirs": [], "assigns": []}
                continue
            rec["args"].append(w)
        if rec["cmd"] is not None or rec["assigns"] or rec["redirs"]:
            self.cmds.append(rec)
        return i

    def dbracket(self, i, rec):
        s = self.s
        while i < self.n:
            i = self.blank(i, newlines=True)
            if self.at_word(i, "]]"):
                return i + 2
            if s[i] in ";&|()<>!\n":
                i += 1
                continue
            w, i = self.read_word(i)
            if w:
                rec["args"].append(w)
            else:
                i += 1
        return i

    def case(self, i):
        s = self.s
        while i < self.n:                       # subject, up to `in`
            i = self.blank(i)
            if self.at_word(i, "in"):
                i += 2
                break
            _w, j = self.read_word(i)
            i = j if j > i else i + 1
        while i < self.n:
            i = self.blank(i, newlines=True)
            if i >= self.n:
                break
            if s[i] == "#":
                i = self.comment(i)
                continue
            if self.at_word(i, "esac"):
                return i + 4
            if s[i] == "(":
                i += 1
            while i < self.n and s[i] != ")":   # the pattern (quotes honoured)
                if s[i] in "'\"\\$`":
                    _w, i = self.read_word(i)
                else:
                    i += 1
            i = self.parse_list(i + 1, "case")
            for t in (";;&", ";;", ";&"):
                if s.startswith(t, i):
                    i += len(t)
                    break
        return i


def sh_commands(lines):
    """every simple command of the script (here-document bodies blanked first), each with the function it is in"""
    lex = _ShLex("\n".join(_blank_heredocs(lines)))
    lex.parse_list(0, None)
    for cm in lex.cmds:
        cm["func"] = func_at(lex.extents, cm["line"])
    return sorted(lex.cmds, key=lambda c: c["line"]), {nm for nm, _ in lex.funcs}, lex.extents


def func_at(extents, line):
    """the innermost function whose body holds line ('<top>' outside every function)"""
    best = None
    for nm, a, b in extents:
        if a <= line <= b and (best is None or a >= best[1]):
            best = (nm, a)
    return best[0] if best else "<top>"


# ---- --self-test: the forms the census must REFUSE (needles) and must ACCEPT (controls), each run on its own ----
# the round-6 reviewer's 24 Python and 32 shell forms (v4_round6_review_20261012.md section 4) + round 13's own
SELF_PY_MODULE = ["import os as _o2", "from os import unlink as _u", "import pathlib", "import io", "import glob",
                  "import functools", "import codecs", "import sqlite3", "import shutil", "import tempfile"]
# "IMPORT;;LINE": the import is placed at module level, the line in a function (each needle on its own)
SELF_PY = ['import os as _o2;;_o2.unlink(p)', 'from os import unlink as _u;;_u(p)', 'getattr(os, "unlink")(p)', 'import functools;;functools.partial(os.unlink, p)()',
           'import pathlib;;pathlib.Path(p).unlink()', 'import pathlib;;pathlib.Path(p).write_text("x")', 'import io;;io.open(p, "w")', 'import codecs;;codecs.open(p, "w")',
           'import glob;;glob.glob(p + "/*")', 'subprocess.run(["rm", "-rf", p])', 'os.renames(p, p + "x")', 'os.removedirs(p)',
           'os.unlink(p, dir_fd=None)', 'os.listdir(fd)', 'os.unlink("a", dir_fd=os.open(p, os.O_RDONLY))',
           'os.chdir(p)', 'os.walk(p)', 'import sqlite3;;sqlite3.connect(p)', 'os.mkdir(f"{p}/x")', 'os.system("rm -rf " + p)',
           'os.setxattr(p, "user.x", b"1")', 'os.lchmod(p, 0o777)', 'os.utime(p)', 'import shutil;;shutil.rmtree(p)',
           'import tempfile;;tempfile.mkdtemp()', 'open(p, "w")', 'os.path.exists(p)', 'eval("os.unlink(p)")', 'f = os.unlink',
           'x.exec_module(m)', 'subprocess.Popen(["rm", p])', 'os.unlink(p, dir_fd=fd)', '_libc.unlink(p)',
           'os.path.getmtime(p)', '__import__("os").unlink(p)', 'os.popen("rm " + p)', 'os.truncate(p, 0)',
           '!os.listdir(fd)', '!os.unlink("x", dir_fd=fd)',   # '!': the function has NO call site (vacuity, A14)
           # round 14 (V4R14-2): the round-7 reviewer's 4 escapes, and the class they belong to (dunder access to a
           # modelled callable / to builtins, attributes of permitted-but-unmodelled modules, module objects as values)
           'os.unlink.__call__(p)', 'type(os).__getattribute__(os, "unlink")(p)', 'select.__builtins__["open"](p, "w")',
           'argparse.FileType("w")(p)', 'signal.signal.__globals__["os"].unlink(p)', 'time.__loader__',
           'sys.modules["os"].unlink(p)', 'fcntl.ioctl(fd, 0)', 'json.dump({}, m)', 'x = os', 'os.unlink.func(p)',
           'os.setxattr("/proc/self/fd/%d" % fd, "user.x", b"1")  # safepath:procfs',
           # round 15: the round-8 reviewer's Python census probe (rv8_review/cen/py_needles.txt), VERBATIM -- the
           # needles the census refuses (the rest are SELF_PY_OK rows below, each with the reason it is harmless)
           'locals()["os"].unlink(p)', 'dir(os)', 'help(os)', 'breakpoint()', '(lambda: 0).__code__', 'os.fspath(p)',
           'os.path.join(p, "x").__len__', 'time.sleep.__self__', 'importlib.util.spec_from_file_location("x", p)',
           'subprocess.run(["true"])']
# needles that must be refused for a SPECIFIC reason (the rule that is meant to catch them, not a later fallback)
SELF_REASON = {'\\rm -rf "$u/j"': "indirect", '"rm" -rf "$u/k"': "indirect", '${RMCMD:-rm} -rf "$u/m"': "indirect",
               'eval "rm -rf $u/l"': "eval runs text", 'install -d "$u/a"': "not in the census's tables",
               'os.unlink(p, dir_fd=None)': "not a PROVED directory fd", '!os.listdir(fd)': "outside the trusted",
               'rm -rf "$_FC_TMPDIR/../../victim"': "not proved", 'f = os.unlink': "REFERENCED, not called",
               # round 14: each new needle refused by the rule written for it
               'os.unlink.__call__(p)': "dunder", 'type(os).__getattribute__(os, "unlink")(p)': "dunder",
               'select.__builtins__["open"](p, "w")': "dunder", 'argparse.FileType("w")(p)': "outside MODULE_ATTRS",
               'signal.signal.__globals__["os"].unlink(p)': "dunder", 'time.__loader__': "dunder",
               'sys.modules["os"].unlink(p)': "outside MODULE_ATTRS", 'fcntl.ioctl(fd, 0)': "outside MODULE_ATTRS",
               'json.dump({}, m)': "outside MODULE_ATTRS", 'x = os': "used as a VALUE",
               'os.unlink.func(p)': "an attribute OF a path operation",
               'printf -v _wr %s /etc; rm -rf "$_wr/x"': "printf -v", 'printf -v_wr %s /etc': "printf -v",
               'local -n _rvref=_wr; _rvref=/etc; rm -rf "$_wr"': "NAMEREF", 'declare -n _rv2=_wr': "NAMEREF",
               'unset _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"': "unset of the PROVED", 'unset -v _wr': "unset of the PROVED",
               # round 15: the class members, each by its own rule
               'rm -f "$_FC_TMPDIR/x"': "may expand EMPTY", 'local _wr; rm -rf "$_wr/x"': "may expand EMPTY",
               '_FC_TMPDIR=""; rm -rf "$_FC_TMPDIR/x"': "may expand EMPTY",
               '(( _FC_TMPDIR = 0 ))': "ARITHMETIC assignment", '(( _wr++ ))': "ARITHMETIC assignment",
               '(( ++_wr ))': "ARITHMETIC assignment", 'x=$(( _wr += 1 ))': "ARITHMETIC assignment",
               '[[ _wr=1 -eq 1 ]]': "ARITHMETIC assignment", 'a[_wr=1]=x': "ARITHMETIC assignment",
               'echo "${a[_wr=2]}"': "ARITHMETIC assignment", 'echo "${HOME:_wr=1:2}"': "ARITHMETIC assignment",
               'echo $[ _wr = 1 ]': "ARITHMETIC assignment", ': "${_wr:=/etc}"': "default assignment",
               ': "${_wr=/etc}"': "default assignment", ': "${_FC_TMPDIR[0]:=/etc}"': "default assignment",
               'r=_wr; : "${!r:=/etc}"': "INDIRECT default", 'case "${_wr:=/etc}" in x) ;; esac': "default assignment",
               'exec {_wr}>/dev/null': "stores an fd", 'wait -n -p _FC_TMPDIR': "wait -p assigns",
               'wait -p "$n"': "non-literal variable NAME", "unset '_wr'": "unset of", 'unset \\_wr': "unset of",
               'unset "$n"': "non-literal variable NAME", 'printf -v "$n" %s x': "non-literal variable NAME",
               'printf -v"$n" %s x': "non-literal variable NAME",
               'IFS= read -r "$n"': "non-literal variable NAME", 'read -a "$n"': "non-literal variable NAME",
               'declare -g "$n=/etc"': "non-literal variable NAME", 'local "$n"': "non-literal variable NAME",
               'export "$n=/etc"': "non-literal variable NAME", 'readonly "$n"': "non-literal variable NAME",
               'typeset "$n"': "non-literal variable NAME", 'declare -i _wr': "an attribute",
               'local -l _wr': "an attribute", 'declare -u _FC_TMPDIR': "an attribute", 'typeset -a _wr': "an attribute",
               'declare -A _wr': "an attribute", 'rm -rf "${_wr:?}/$_wr"': "may expand EMPTY", 'read "-$o" x': "option word", 'mapfile -t _wr': "not in the census",
               'readarray _wr': "not in the census", 'getopts ab _wr': "not in the census", 'let "_wr=1"': "not in the census",
               'declare -gn _r=_wr; _r=/etc; rm -rf "$_wr"': "NAMEREF", 'local -rn _r2=_FC_TMPDIR': "NAMEREF",
               "printf -v '_FC_TMPDIR' %s /etc; rm -rf \"$_FC_TMPDIR/x\"": "printf -v assigns",
               'printf -v"_FC_TMPDIR" %s /etc; rm -rf "$_FC_TMPDIR/x"': "printf -v assigns",
               'unset "_FC_TMPDIR"; rm -rf "$_FC_TMPDIR/x"': "unset of the PROVED",
               'n=_FC_TMPDIR; printf -v "$n" %s /etc; rm -rf "$_FC_TMPDIR/x"': "non-literal variable NAME",
               'n=_FC_TMPDIR; unset "$n"; rm -rf "$_FC_TMPDIR/x"': "non-literal variable NAME",
               'n=_FC_TMPDIR; declare -g "$n=/etc"; rm -rf "$_FC_TMPDIR/x"': "non-literal variable NAME",
               'n=_FC_TMPDIR; read -r "$n" <<<"/etc"; rm -rf "$_FC_TMPDIR/x"': "non-literal variable NAME",
               '(( _FC_TMPDIR = 0 )); rm -rf "$_FC_TMPDIR/x"': "ARITHMETIC assignment",
               ': "${_wr:=/etc}"; rm -rf "$_wr/x"': "default assignment",
               'wait -n -p _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"': "wait -p assigns"}
# needles that UN-PROVE a variable (an assignment the provenance pass MODELS: an array element, read's targets): the
# variable -- and every variable derived from it -- loses its proof, so every later path use is refused ELSEWHERE.
# Such a needle passes when at least one row refuses it (here or elsewhere) and every row elsewhere is a provenance
# refusal ("not proved" / "not a listed parameter"), never an unrelated one.
SELF_UNPROVES = {'_FC_TMPDIR[0]=/etc; rm -rf "$_FC_TMPDIR/x"', 'read -r -a _FC_TMPDIR', 'IFS= read -r _FC_TMPDIR',
                 'declare -g "_FC_TMPDIR=/etc"', 'typeset _FC_TMPDIR=/etc'}
SELF_PY_OK = ['os.listxattr("/proc/self/fd/%d" % fd)  # safepath:procfs', 'os.environ.get("HOME", "")',  # round 14
              'sys.stderr.write("x")', 'json.dumps({})',
              'os.unlink("x", dir_fd=open_owned_dir(p))', 'os.path.join(p, "x")', 'os.close(fd)',
              'n = os.fstat(fd).st_size',
              # round 15: the round-8 reviewer's probe needles the census ACCEPTS, verbatim -- none names, opens,
              # creates or removes a path: an fd close, attributes of the already-open std streams, a signal
              # disposition, json from a string, mode arithmetic, a comprehension, print to stderr, a memoryview of
              # bytes, the name `super`, a yield
              'sys.stderr.buffer.raw', 'sys.stdout.reconfigure()', 'signal.signal(signal.SIGTERM, lambda *a: None)',
              'json.loads(p, object_hook=None)', '_st.S_IMODE(0)', '[o for o in (1,)]', 'print("x", file=sys.stderr)',
              'memoryview(b"x")', 'super', '(yield)']
SELF_SH = ['install -d "$u/a"', 'dd if=/dev/zero of="$u/b" count=1', 'rsync -a "$u/c" "$u/d"', 'chmod 777 "$u/e"',
           'truncate -s0 "$u/f"', 'sed -i s/a/b/ "$u/g"', 'echo x >| "$u/h"', 'exec 3<> "$u/i"', '\\rm -rf "$u/j"',
           '"rm" -rf "$u/k"', 'eval "rm -rf $u/l"', '${RMCMD:-rm} -rf "$u/m"', "python3 -c 'import os; os.unlink(\"/x\")'",
           'git -C "$u" worktree move a b', 'git clone x "$u/n"', 'rm -rf "$_FC_TMPDIR" relative_victim',
           'rm -rf "$_FC_TMPDIR" ~/victim', 'rm -rf "$_FC_TMPDIR/../../victim"', 'mapfile -t arr < "$u/o"',
           'find "$u" -exec rm {} +', 'cp -r "$u/p" "$u/q"', 'ln -s "$u/r" "$u/s"', 'printf x >>"$u/t"', ': >"$u/v"',
           'echo `rm "$u/w"`', 'cat <(rm "$u/z")', 'mkfifo "$u/fifo"', 'mv "$u/a1" "$u/a2"', 'touch "$u/tt"',
           'pr="$(_fc_safe mkdir /tmp)"; printf x >"$pr/fixed"', 'pd="$_FC_TMPDIR/../../.."; printf x >"$pd/escaped"',
           'git -C "$u" worktree remove "$u"', 'env rm -rf "$u"', 'command rm -rf "$u"', 'exec 4>"$u/x"',
           'echo x &>"$u/y"', "trap 'rm -rf /tmp/x' EXIT", "\"$BASH\" -c 'rm -rf /tmp/x'",
           '_fc_run_child /dev/null 1 "$u" "$u" -- rm -rf "$u"', 'x="$_FC_TMPDIR"; rm -rf "$x.sibling"',
           'git -C "$u" checkout -f', 'source "$u/x"', 'bash "$u/x"', 'cc -o "$u/bin" x.c',
           'sed -n p "$u/file"',
           # round 14 (V4R14-2): the round-7 reviewer's 3 shell escapes (assignments the provenance pass did not see)
           'printf -v _wr %s /etc; rm -rf "$_wr/x"', 'local -n _rvref=_wr; _rvref=/etc; rm -rf "$_wr"',
           'unset _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"', 'declare -n _rv2=_wr', 'printf -v_wr %s /etc',
           'unset -v _wr',
           # round 15 (V4R15-2, RV8-07): the round-8 reviewer's shell census probe (rv8_review/cen/sh_needles.txt +
           # n2.txt), VERBATIM
           'rm -f "$_FC_TMPDIR/x"', 'local _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"', 'local _wr; rm -rf "$_wr/x"',
           '(( _FC_TMPDIR = 0 )); rm -rf "$_FC_TMPDIR/x"', 'let _FC_TMPDIR=0; rm -rf "$_FC_TMPDIR/x"',
           ': "${_wr:=/etc}"; rm -rf "$_wr/x"', 'wait -n -p _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"',
           'select _FC_TMPDIR in /etc; do break; done; rm -rf "$_FC_TMPDIR/x"', '_FC_TMPDIR[0]=/etc; rm -rf "$_FC_TMPDIR/x"',
           "printf -v '_FC_TMPDIR' %s /etc; rm -rf \"$_FC_TMPDIR/x\"", 'n=_FC_TMPDIR; printf -v "$n" %s /etc; rm -rf "$_FC_TMPDIR/x"',
           'n=_FC_TMPDIR; unset "$n"; rm -rf "$_FC_TMPDIR/x"', 'n=_FC_TMPDIR; declare -g "$n=/etc"; rm -rf "$_FC_TMPDIR/x"',
           'n=_FC_TMPDIR; read -r "$n" <<<"/etc"; rm -rf "$_FC_TMPDIR/x"', 'coproc _FC_TMPDIR { :; }; rm -rf "$_FC_TMPDIR/x"',
           'unset "_FC_TMPDIR"; rm -rf "$_FC_TMPDIR/x"', 'unset -v -- _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"',
           'declare +n _x; typeset -n _y=_wr; _y=/etc; rm -rf "$_wr"', 'local -- _FC_TMPDIR=""; rm -rf "$_FC_TMPDIR/x"',
           '_FC_TMPDIR=""; rm -rf "$_FC_TMPDIR/x"', 'printf -v"_FC_TMPDIR" %s /etc; rm -rf "$_FC_TMPDIR/x"',
           'command printf -v _FC_TMPDIR %s /etc; rm -rf "$_FC_TMPDIR/x"', 'builtin unset _FC_TMPDIR; rm -rf "$_FC_TMPDIR/x"',
           'declare -gn _r=_wr; _r=/etc; rm -rf "$_wr"', 'local -rn _r2=_FC_TMPDIR',
           # round 15: the CLASS, each member ALONE (no trailing operand that would be refused anyway), so each one is
           # refused by the rule written for it -- the enumeration (closed list) is in CONVERGENCE.md of round 9
           '(( _FC_TMPDIR = 0 ))', '(( _wr++ ))', '(( ++_wr ))', 'x=$(( _wr += 1 ))', '[[ _wr=1 -eq 1 ]]',
           'a[_wr=1]=x', 'echo "${a[_wr=2]}"', 'echo "${HOME:_wr=1:2}"', 'echo $[ _wr = 1 ]',
           ': "${_wr:=/etc}"', ': "${_wr=/etc}"', ': "${_FC_TMPDIR[0]:=/etc}"', 'r=_wr; : "${!r:=/etc}"',
           'case "${_wr:=/etc}" in x) ;; esac', 'exec {_wr}>/dev/null', 'wait -n -p _FC_TMPDIR', 'wait -p "$n"',
           "unset '_wr'", 'unset \\_wr', 'unset "$n"', 'printf -v "$n" %s x', 'printf -v"$n" %s x',
           'read -r -a _FC_TMPDIR', 'IFS= read -r _FC_TMPDIR', 'IFS= read -r "$n"', 'read -a "$n"',
           'declare -g "$n=/etc"', 'local "$n"', 'export "$n=/etc"', 'readonly "$n"', 'typeset "$n"',
           'declare -i _wr', 'local -l _wr', 'declare -u _FC_TMPDIR', 'typeset -a _wr', 'declare -A _wr',
           'read "-$o" x', 'mapfile -t _wr', 'readarray _wr', 'getopts ab _wr', 'let "_wr=1"',
           'rm -rf "${_wr:?}/$_wr"', 'declare -g "_FC_TMPDIR=/etc"', 'typeset _FC_TMPDIR=/etc']
SELF_SH_OK = ['printf -v _intr %s x', 'unset FC_OUT', 'unset -f _needle', 'local -r _ro=1',   # round 14 controls
              'rm -f "${_FC_TMPDIR:?}/x"', 'printf x >"${_FC_TMPDIR:?}/y"', '_fc_safe rmtree "$u"', 'echo "rm -rf $u"',
              'm="$(_fc_mktemp)"; rm -f "${m:?}.t"', 'git -C "$u" rev-parse HEAD', 'printf x >&2', ': >/dev/null',
              # round 15 controls (no false refusal): the same forms on variables that are NOT proved, a literal
              # quoted NAME that is not proved, emptying a proved variable WITHOUT a later unguarded use, reads
              'printf -v "_intr" %s x', "unset 'FC_OUT'", '(( n = 1 ))', 'x=$(( 1 + 2 ))', ': "${FC_X:=1}"',
              'read -r line', 'read -ra parts', 'wait -n', 'wait -n -p _pid', 'declare -r _ro2=1', 'export FC_X=1',
              'local _wr', '_FC_TMPDIR=""', 'declare -i n=1', '[[ -d "${_wr:?}" ]]',
              # read's targets are MODELLED (un-proved, '<read>'): _wr has no path use, so nothing is refused
              'read -r _wr', 'read -ra _wr',
              'rm -rf "${_wr:?}/x/${_wr:?}"', 'echo "${a[1]}"', 'echo "${HOME:0:2}"', 'case "$x" in a) ;; esac']


def self_test(sup, br):
    """every needle must be flagged ON ITS OWN LINE, every control must not -- each against the files under test"""
    import tempfile as _tf
    out, bad = [], 0
    src_py, src_sh = open(sup).read(), open(br).read()
    d = _tf.mkdtemp(prefix="census_self.")
    try:
        cases = [("py", x, True, True) for x in SELF_PY_MODULE] + [("py", x, False, True) for x in SELF_PY] + \
                [("py", x, False, False) for x in SELF_PY_OK] + [("sh", x, False, True) for x in SELF_SH] + \
                [("sh", x, False, False) for x in SELF_SH_OK]
        for lang, text, module, want in cases:
            if lang == "py":
                imp, _s, line = text.rpartition(";;")
                nocall = line.startswith("!")
                line = line.lstrip("!")
                body = (line + "\n") if module else \
                    "def _needle(p, fd, x, m):\n    %s\n\n\n%s\n" % (line, "" if nocall else "_needle(None, None, None, None)")
                path = os.path.join(d, "sup.py")
                open(path, "w").write(src_py + "\n" + body + (imp + "\n" if imp else ""))
                first = src_py.count("\n") + 2
                rows = py_census(path)
                at = first if module else first + 1
                if imp:                               # the import's own row is expected too (not "elsewhere")
                    rows = [r for r in rows if not (r[4] == "VIOLATION" and r[3].startswith(("import", "from")))]
            else:
                body = '_needle() {\n  local u="$1"\n  %s\n}\n' % text
                path = os.path.join(d, "br.sh")
                open(path, "w").write(src_sh + "\n" + body)
                first = src_sh.count("\n") + 2
                rows, _ = sh_census(path)
                at = first + 2
            hits = [r for r in rows if r[1] == at and r[4] == "VIOLATION"]
            if want and text in SELF_REASON:
                hits = [r for r in hits if SELF_REASON[text] in r[5]]
            other = [r for r in rows if r[4] == "VIOLATION" and r[1] != at]
            if text in SELF_UNPROVES:                 # elsewhere rows expected: provenance refusals only
                hits = hits + [r for r in other if "not proved" in r[5] or "not a listed parameter" in r[5]]
                other = [r for r in other if not ("not proved" in r[5] or "not a listed parameter" in r[5])]
            good = bool(hits) == want and not other
            bad += 0 if good else 1
            out.append("%s %s %-9s %s%s" % ("ok" if good else "NOT-ok", lang, "REFUSES" if want else "ACCEPTS",
                                           text, "" if good else "   (hits=%d, elsewhere=%d)" % (len(hits), len(other))))
    finally:
        import shutil as _sh
        _sh.rmtree(d, ignore_errors=True)
    for line in out:
        print(line)
    print("SELFTEST cases=%d failed=%d" % (len(out), bad))
    return 1 if bad else 0


def main(argv):
    md = "--markdown" in argv
    selft = "--self-test" in argv
    args = [a for a in argv if a not in ("--markdown", "--self-test")]
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
            sys.stderr.write("usage: check_safepath_census.py [--sup FILE] [--br FILE] [--markdown | --self-test]\n")
            return 2
    if selft:
        return self_test(sup, br)
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
