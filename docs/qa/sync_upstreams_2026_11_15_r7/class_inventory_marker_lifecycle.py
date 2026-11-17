#!/usr/bin/env python3
"""Round-7 class inventory (§11.4.276(C)): "marker lifecycle: every exit path between write and completion".

Enumerates, from the engine's AST, (1) every call of write_marker / clear_marker / read_marker with its function,
(2) every r.run(..., write=True) call, and (3) every `return GitResult(...)` inside Runner.run with its `why` and its
`started` value. Control needles (§11.4.201(7)(b)): the instrument must find `def write_marker` exactly once (a
known-present name of the same query class, a FunctionDef) and must find NO call of `write_markerX` (known
absent). Usage: class_inventory_marker_lifecycle.py <engine.py>"""
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
            return n.name
    return "<module>"


defs = [n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
needle_pos = defs.count("write_marker")
calls, writes, results = [], [], []
needle_neg = 0
for n in ast.walk(tree):
    if isinstance(n, ast.Call):
        f = n.func
        name = f.id if isinstance(f, ast.Name) else f.attr if isinstance(f, ast.Attribute) else None
        if name in ("write_marker", "clear_marker", "read_marker"):
            calls.append((n.lineno, name, enclosing(n), ast.get_source_segment(src, n)))
        if name == "write_markerX":
            needle_neg += 1
        if name == "run" and any(k.arg == "write" for k in n.keywords):
            writes.append((n.lineno, enclosing(n), ast.get_source_segment(src, n)))
        if name == "GitResult" and enclosing(n) == "run":
            why = ast.get_source_segment(src, n.args[4]) if len(n.args) > 4 else "?"
            st = [ast.get_source_segment(src, k.value) for k in n.keywords if k.arg == "started"]
            results.append((n.lineno, why, st[0] if st else "True (default)"))
print("control needle: def write_marker found %d (want 1); write_markerX calls %d (want 0)" % (needle_pos, needle_neg))
print("\n== marker calls (%d)" % len(calls))
for c in calls:
    print("  line %d  %-12s in %-18s %s" % c)
print("\n== write calls r.run(..., write=True) (%d)" % len(writes))
for w in writes:
    print("  line %d  in %-12s %s" % (w[0], w[1], w[2].replace("\n", " ")))
print("\n== GitResult returns in Runner.run (%d)" % len(results))
for r in results:
    print("  line %d  why=%-22s started=%s" % r)
ok = needle_pos == 1 and needle_neg == 0 and calls and writes and results
print("\nINSTRUMENT: %s" % ("SEES" if ok else "BLIND"))
sys.exit(0 if ok else 2)
