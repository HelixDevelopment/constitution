#!/usr/bin/env python3
"""Round-9 class inventory (section 11.4.276(C)), path-wise. Round 8: "every path on which a write git can start while
a marker (or an unresolved write) is in its git dir". Round 9 adds the class "a filesystem object at or around a
path the engine reads, creates, clears or checks" (RV8-1 .. RV8-4) and "every lock file git takes for an engine
write" (RV8-1).

Scope (RV7-4). This instrument reads ONE engine file statically (Python AST). It sees: every r.run(..., write=True)
call (each is a path on which a write git can start), the token each passes, the function that produced that token,
every write_marker / clear_marker call and its function, and whether Runner.run checks the token before its one
spawn point (proc_run_git). It does NOT see: timing (what another process does between two lines), code that calls
git outside Runner.run (the gate CM-SYNC-UPSTREAMS-FF-ONLY covers that: proc_run_git is the only spawn), or the
behaviour of git itself. The DYNAMIC half of the inventory is the spawn audit of scripts/sync/inproc_driver.py, used
by the robustness checks sibling_kill, sibling_wipe, marker_pre (plant / race / swap x ff / pin / follow / stage,
plus pinparent), stop_pin and parent_lock: for every write git that really started, it records whether the marker
in its git dir at that moment was the write's own.

Rules checked (a violation is printed and makes the exit status 1):
  R1 every write=True call passes token=<name> and <name> is assigned from begin_write(...) in the same function;
  R2 write_marker is called only in begin_write (and in tests);
  R3 clear_marker is called only in begin_write (its own fresh marker), end_write, and run()'s earlier-marker loop;
  R4 Runner.run calls token_refusal before proc_run_git, inside an `if write:` branch;
  R5 (round 9) every filesystem operation (builtin open; os.open / unlink / remove / rename / replace / lstat /
     stat / makedirs / mkdir / rmdir / mkfifo / listdir / scandir / chmod / access / symlink / readlink / fdopen;
     os.path.exists / isfile / isdir / lexists / islink / getsize; tempfile.*; shutil.* except shutil.which, the
     git binary lookup) is inside path_kind, kind_of_mode or an fs_* function: no direct access is scattered;
  R6 (round 9) the lock sets: GITDIR_LOCKS and COMMON_LOCKS have a key for each git write subcommand the engine
     runs with write=True ('merge', 'checkout', 'add'), OP_GIT maps every write op to one of them, and in_progress
     reads its locks from lock_paths (no hand-kept second list);
  R7 (round 9) every end_write call passes a settled argument, and end_write's clear_marker is guarded by a test
     that names `settled` and by a marker_write_id comparison (a marker is cleared only after a settled write, and
     only while it is the write's own).
Control needles (section 11.4.201(7)(b)): the instrument must find `def write_git` exactly once (a known-present
name of the same query class), no call of `write_markerX` (known absent), at least one os.open call (a
known-present filesystem call of the R5 query class) and no `os.openX` (known absent). Exit 0 SEES + no violation,
1 SEES + violations, 2 BLIND. Usage: class_inventory_write_paths.py <engine.py>"""
import ast
import sys

src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
parent = {}
for n in ast.walk(tree):
    for c in ast.iter_child_nodes(n):
        parent[c] = n


def enclosing(n):
    while n in parent:
        n = parent[n]
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            return n
    return None


def cname(call):
    f = call.func
    return f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else None


funcs = [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
needle_pos = [f.name for f in funcs].count("write_git")
needle_neg = sum(1 for n in ast.walk(tree) if isinstance(n, ast.Call) and cname(n) == "write_markerX")
violations, writes, markers = [], [], []
for n in ast.walk(tree):
    if not isinstance(n, ast.Call):
        continue
    name = cname(n)
    fn = enclosing(n)
    fname = fn.name if fn else "<module>"
    if name == "run" and any(k.arg == "write" and isinstance(k.value, ast.Constant) and k.value.value
                             for k in n.keywords):
        tok = [k.value for k in n.keywords if k.arg == "token"]
        src_fn = None
        if tok and isinstance(tok[0], ast.Name) and fn is not None:
            for a in ast.walk(fn):
                if isinstance(a, ast.Assign) and isinstance(a.value, ast.Call) and cname(a.value) == "begin_write":
                    for t in a.targets:
                        if isinstance(t, ast.Tuple) and t.elts and isinstance(t.elts[0], ast.Name) and \
                                t.elts[0].id == tok[0].id:
                            src_fn = "begin_write"
        writes.append((n.lineno, fname, tok[0].id if tok and isinstance(tok[0], ast.Name) else None, src_fn))
        if src_fn != "begin_write":
            violations.append("R1 line %d in %s: write call without a begin_write token" % (n.lineno, fname))
    if name in ("write_marker", "clear_marker"):
        markers.append((n.lineno, name, fname))
        if name == "write_marker" and fname != "begin_write":
            violations.append("R2 line %d: write_marker called in %s" % (n.lineno, fname))
        if name == "clear_marker" and fname not in ("begin_write", "end_write", "run"):
            violations.append("R3 line %d: clear_marker called in %s" % (n.lineno, fname))
runner = [n for n in ast.walk(tree) if isinstance(n, ast.ClassDef) and n.name == "Runner"]
r4 = False
if runner:
    meth = [m for m in runner[0].body if isinstance(m, ast.FunctionDef) and m.name == "run"]
    if meth:
        spawn = [c.lineno for c in ast.walk(meth[0]) if isinstance(c, ast.Call) and cname(c) == "proc_run_git"]
        refuse =[c for c in ast.walk(meth[0]) if isinstance(c, ast.Call) and cname(c) == "token_refusal"]
        inside_if_write = False
        for c in refuse:
            p_ = c
            while p_ in parent and p_ is not meth[0]:
                p_ = parent[p_]
                if isinstance(p_, ast.If) and isinstance(p_.test, ast.Name) and p_.test.id == "write":
                    inside_if_write = True
        r4 = bool(spawn and refuse and min(c.lineno for c in refuse) < min(spawn) and inside_if_write)
if not r4:
    violations.append("R4 Runner.run does not check token_refusal (inside `if write:`) before proc_run_git")

# ---- R5: the path access layer ----
OS_FS = {"open", "unlink", "remove", "rename", "replace", "lstat", "stat", "makedirs", "mkdir", "rmdir", "mkfifo",
         "listdir", "scandir", "chmod", "access", "symlink", "readlink", "fdopen"}
OSPATH_FS = {"exists", "isfile", "isdir", "lexists", "islink", "getsize"}
LAYER = lambda f: f in ("path_kind", "kind_of_mode") or f.startswith("fs_")


def fs_op(call):
    f = call.func
    if isinstance(f, ast.Name) and f.id == "open":
        return "open"
    if isinstance(f, ast.Attribute):
        v = f.value
        if isinstance(v, ast.Name) and v.id == "os" and f.attr in OS_FS:
            return "os." + f.attr
        if isinstance(v, ast.Attribute) and isinstance(v.value, ast.Name) and v.value.id == "os" and \
                v.attr == "path" and f.attr in OSPATH_FS:
            return "os.path." + f.attr
        if isinstance(v, ast.Name) and v.id == "tempfile":
            return "tempfile." + f.attr
        if isinstance(v, ast.Name) and v.id == "shutil" and f.attr != "which":
            return "shutil." + f.attr
        if isinstance(v, ast.Name) and v.id == "os" and f.attr == "openX":
            return "os.openX"
    return None


fsops = []
for n in ast.walk(tree):
    if isinstance(n, ast.Call):
        op = fs_op(n)
        if op:
            fn = enclosing(n)
            fname = fn.name if fn else "<module>"
            fsops.append((n.lineno, op, fname))
            if op != "os.openX" and not LAYER(fname):
                violations.append("R5 line %d: %s outside the path access layer (in %s)" % (n.lineno, op, fname))
needle5_pos = sum(1 for ln, op, f in fsops if op == "os.open")  # any engine opens files: known present
needle5_neg = sum(1 for ln, op, f in fsops if op == "os.openX")

# ---- R6: the lock sets ----
consts = {}
for n in tree.body:
    if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
        try:
            consts[n.targets[0].id] = ast.literal_eval(n.value)
        except ValueError:
            pass
write_subs = set()
for n in ast.walk(tree):
    if isinstance(n, ast.Call) and cname(n) == "run" and any(
            k.arg == "write" and isinstance(k.value, ast.Constant) and k.value.value for k in n.keywords):
        if len(n.args) >= 2 and isinstance(n.args[1], ast.List) and n.args[1].elts and \
                isinstance(n.args[1].elts[0], ast.Constant):
            write_subs.add(n.args[1].elts[0].value)
gl, cl, og = consts.get("GITDIR_LOCKS") or {}, consts.get("COMMON_LOCKS") or {}, consts.get("OP_GIT") or {}
for sub in sorted(write_subs):
    if sub not in gl or sub not in cl:
        violations.append("R6 write subcommand %r has no lock set" % sub)
for op_, sub in sorted(og.items()):
    if sub not in write_subs:
        violations.append("R6 OP_GIT[%r] = %r is no write subcommand of the engine" % (op_, sub))
if not og:
    violations.append("R6 OP_GIT missing")
ip = [f for f in funcs if f.name == "in_progress"]
if not ip or not any(isinstance(c, ast.Call) and cname(c) == "lock_paths" for c in ast.walk(ip[0])):
    violations.append("R6 in_progress does not read its locks from lock_paths")

# ---- R7: settled clear ----
for n in ast.walk(tree):
    if isinstance(n, ast.Call) and cname(n) == "end_write":
        if len(n.args) + len(n.keywords) < 4:
            violations.append("R7 line %d: end_write called without a settled argument" % n.lineno)
ew = [f for f in funcs if f.name == "end_write"]
r7 = False
if ew:
    for c in ast.walk(ew[0]):
        if isinstance(c, ast.Call) and cname(c) == "clear_marker":
            tests = []
            p_ = c
            while p_ in parent and p_ is not ew[0]:
                p_ = parent[p_]
                if isinstance(p_, ast.If):
                    tests.append(ast.dump(p_.test))
            r7 = any("'settled'" in t for t in tests) and any("marker_write_id" in t for t in tests)
if not r7:
    violations.append("R7 end_write clears the marker without a settled test and a marker_write_id check")
print("control needle: def write_git found %d (want 1); write_markerX calls %d (want 0)" % (needle_pos, needle_neg))
print("control needle R5: os.open calls %d (want >= 1); os.openX calls %d (want 0)" % (needle5_pos, needle5_neg))
print("\n== write paths: r.run(..., write=True) (%d)" % len(writes))
for w in writes:
    print("  line %d  in %-12s token=%s from %s" % w)
print("\n== marker calls (%d)" % len(markers))
for m in markers:
    print("  line %d  %-12s in %s" % m)
print("\n== R4 token checked at the spawn choke point: %s" % ("yes" if r4 else "NO"))
print("\n== filesystem operations (%d)" % len(fsops))
for f_ in fsops:
    print("  line %d  %-16s in %s" % f_)
print("\n== lock sets: write subcommands %s; GITDIR_LOCKS %s; COMMON_LOCKS %s; OP_GIT %s"
      % (sorted(write_subs), gl, cl, og))
blind = not (needle_pos == 1 and needle_neg == 0 and writes and needle5_pos >= 1 and needle5_neg == 0)
print("\n== violations (%d)" % len(violations))
for v in violations:
    print("  " + v)
print("\nINSTRUMENT: %s" % ("BLIND" if blind else "SEES"))
sys.exit(2 if blind else 1 if violations else 0)
