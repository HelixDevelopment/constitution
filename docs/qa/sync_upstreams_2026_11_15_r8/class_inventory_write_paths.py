#!/usr/bin/env python3
"""Round-8 class inventory (section 11.4.276(C)), path-wise: "every path on which a write git can start while a marker
(or an unresolved write) is in its git dir".

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
  R3 clear_marker is called only in write_marker (its own half-written file), begin_write, end_write, and run()'s
     earlier-marker loop;
  R4 Runner.run calls token_refusal before proc_run_git, inside an `if write:` branch.
Control needles (section 11.4.201(7)(b)): the instrument must find `def write_git` exactly once (a known-present
name of the same query class) and no call of `write_markerX` (known absent). Exit 0 SEES + no violation,
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
        if name == "clear_marker" and fname not in ("write_marker", "begin_write", "end_write", "run"):
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
print("control needle: def write_git found %d (want 1); write_markerX calls %d (want 0)" % (needle_pos, needle_neg))
print("\n== write paths: r.run(..., write=True) (%d)" % len(writes))
for w in writes:
    print("  line %d  in %-12s token=%s from %s" % w)
print("\n== marker calls (%d)" % len(markers))
for m in markers:
    print("  line %d  %-12s in %s" % m)
print("\n== R4 token checked at the spawn choke point: %s" % ("yes" if r4 else "NO"))
blind = not (needle_pos == 1 and needle_neg == 0 and writes)
print("\n== violations (%d)" % len(violations))
for v in violations:
    print("  " + v)
print("\nINSTRUMENT: %s" % ("BLIND" if blind else "SEES"))
sys.exit(2 if blind else 1 if violations else 0)
