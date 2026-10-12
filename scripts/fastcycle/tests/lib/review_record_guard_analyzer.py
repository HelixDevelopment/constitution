#!/usr/bin/env python3
"""review_record_guard_analyzer.py -- the MECHANICAL guard inventory for
review/review_record.py (T048 restart, V3 round 4, R4-F3; constitution
11.4.276(C)/(D), 11.4.194(6)(d)).

Round 3's meta-check looked only at `if` statements whose body returned or
appended, inside a HAND-MAINTAINED list of 19 functions, and bound one test
case to a whole compound condition. Reviewer mutations R4-A..R4-H survived in
code that list never reached. This module replaces the hand list with facts
derived from the source itself:

  * GUARDED SET -- every module-level function reachable from the roots
    `cmd_gate` and `cmd_record` through the call graph (a function counts as
    reached when its name is called OR referenced, e.g. passed as
    object_pairs_hook).
  * DECISION CONSTRUCTS -- in every guarded function: `if`/`elif`, `while`,
    `assert`, conditional expressions (`x if c else y`), comprehension
    filters (`[... if c]`), `except` handlers (an error turned into an
    outcome), and boolean-valued `return`/assignments (BoolOp, Compare,
    `not`, isinstance/any/all/hasattr/callable calls). Each must carry, on
    the line directly above its statement (or its `except` line), either
    `# guard: <ID>` or `# not-a-guard: <reason>`.
  * SUB-CLAUSES -- each guard's condition is decomposed by AST: every
    operand of every `and`/`or` (at any depth, inside calls and
    comprehensions too) is one sub-clause; a condition with no `and`/`or` at
    its root is one sub-clause. An `except` handler is one sub-clause.
  * MUTANTS -- one per sub-clause, applied by AST position, flipping JUST
    that sub-clause: an `and` operand becomes True and an `or` operand
    becomes False (the operand is removed from its condition); a root
    if/while/assert/filter condition becomes False (the guard never fires);
    a root conditional-expression test or boolean value is negated; an
    `except` body becomes `raise` (or `continue`/`pass` when it already
    re-raises).

Used by test_review_record_guard_table.sh (static completeness) and
test_review_record_subclause_sweep.sh (the dynamic kill sweep). Python
stdlib only.

CLI: review_record_guard_analyzer.py list TOOL        (TSV of sub-clauses)
     review_record_guard_analyzer.py mutate TOOL ID OUT (write one mutant)
"""
import ast
import hashlib
import json
import re
import sys

ROOTS = ("cmd_gate", "cmd_record")
TAG_RE = re.compile(r"^\s*# guard: (G-[A-Z0-9-]+)\s*$")
NOT_RE = re.compile(r"^\s*# not-a-guard: (\S.{14,})$")
BOOL_CALLS = {"isinstance", "any", "all", "hasattr", "callable"}


def _module_functions(tree):
    return {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}


def reachable(tree):
    """Functions reachable from ROOTS (name called or referenced)."""
    funcs = _module_functions(tree)
    seen, todo = set(), [r for r in ROOTS if r in funcs]
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        for n in ast.walk(funcs[name]):
            if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load) and n.id in funcs and n.id not in seen:
                todo.append(n.id)
    return sorted(seen)


def _is_boolish(expr):
    if isinstance(expr, (ast.BoolOp, ast.Compare)):
        return True
    if isinstance(expr, ast.UnaryOp) and isinstance(expr.op, ast.Not):
        return True
    return (isinstance(expr, ast.Call) and isinstance(expr.func, ast.Name)
            and expr.func.id in BOOL_CALLS)


def _parents(root):
    par = {}
    for n in ast.walk(root):
        for c in ast.iter_child_nodes(n):
            par[c] = n
    return par


def _enclosing_stmt(node, par):
    while not isinstance(node, ast.stmt):
        node = par[node]
    return node


def constructs(tree, fn_names):
    """[(fn, kind, anchor_line, node, expr_or_None)] for every decision
    construct in the named functions. anchor_line is the line whose
    predecessor must carry the tag."""
    funcs = _module_functions(tree)
    out = []
    for fn in fn_names:
        froot = funcs[fn]
        par = _parents(froot)
        for n in ast.walk(froot):
            if isinstance(n, (ast.If, ast.While, ast.Assert)):
                out.append((fn, type(n).__name__.lower(), n.lineno, n, n.test))
            elif isinstance(n, ast.IfExp):
                out.append((fn, "ifexp", _enclosing_stmt(n, par).lineno, n, n.test))
            elif isinstance(n, ast.comprehension):
                for cond in n.ifs:
                    out.append((fn, "filter", _enclosing_stmt(cond, par).lineno, cond, cond))
            elif isinstance(n, ast.ExceptHandler):
                out.append((fn, "except", n.lineno, n, None))
            elif isinstance(n, ast.Return) and n.value is not None and _is_boolish(n.value):
                out.append((fn, "boolreturn", n.lineno, n, n.value))
            elif isinstance(n, (ast.Assign, ast.AnnAssign, ast.AugAssign)) and n.value is not None \
                    and _is_boolish(n.value):
                out.append((fn, "boolassign", n.lineno, n, n.value))
    return out


def tags(lines):
    """{line_number_of_tag: ("guard", id) | ("not", reason) | ("bad", text)}"""
    out = {}
    for i, line in enumerate(lines, 1):
        m = TAG_RE.match(line)
        if m:
            out[i] = ("guard", m.group(1))
            continue
        if line.strip().startswith("# not-a-guard:"):
            m = NOT_RE.match(line)
            out[i] = ("not", m.group(1)) if m else ("bad", line.strip())
    return out


def _strip_not(expr):
    while isinstance(expr, ast.UnaryOp) and isinstance(expr.op, ast.Not):
        expr = expr.operand
    return expr


def _in_loop(node, par):
    while node in par:
        node = par[node]
        if isinstance(node, (ast.For, ast.While)):
            return True
        if isinstance(node, ast.FunctionDef):
            return False
    return False


def subclauses(src):
    """[{id, guard, fn, kind, line, leaf, start, end, repl}] for every guard
    sub-clause, plus the analysis facts needed by the meta-check."""
    tree = ast.parse(src)
    lines = src.splitlines()
    fns = reachable(tree)
    cons = constructs(tree, fns)
    tg = tags(lines)
    funcs = _module_functions(tree)
    rows, per_guard = [], {}
    for fn, kind, anchor, node, expr in cons:
        t = tg.get(anchor - 1)
        if not t or t[0] != "guard":
            continue
        gid = t[1]
        cands = []
        if kind == "except":
            par = _parents(funcs[fn])
            body = node.body
            reraise = len(body) == 1 and isinstance(body[0], ast.Raise) and body[0].exc is None
            repl = ("continue" if _in_loop(node, par) else "pass") if reraise else "raise"
            mode = "block" if body[0].lineno > node.lineno else "stmt"
            cands.append((body[0].lineno, body[0].col_offset, body[-1].end_lineno, body[-1].end_col_offset,
                          "except:" + (ast.unparse(node.type) if node.type is not None else "*"),
                          repl, mode))
        else:
            boolops = [b for b in ast.walk(expr) if isinstance(b, ast.BoolOp)]
            for b in boolops:
                for operand in b.values:
                    if isinstance(operand, ast.BoolOp):
                        continue
                    repl = "True" if isinstance(b.op, ast.And) else "False"
                    cands.append((operand.lineno, operand.col_offset, operand.end_lineno, operand.end_col_offset,
                                  ast.unparse(operand), repl, "expr"))
            if not isinstance(_strip_not(expr), ast.BoolOp):
                if kind in ("if", "while", "assert", "filter"):
                    repl = "False"
                else:
                    repl = "(not (%s))" % ast.unparse(expr)
                cands.append((expr.lineno, expr.col_offset, expr.end_lineno, expr.end_col_offset,
                              ast.unparse(expr), repl, "expr"))
        cands.sort()
        for c in cands:
            k = per_guard.get(gid, 0) + 1
            per_guard[gid] = k
            rows.append({"id": "%s#%d" % (gid, k), "guard": gid, "fn": fn, "kind": kind, "line": anchor,
                         "leaf": " ".join(c[4].split()), "start": [c[0], c[1]], "end": [c[2], c[3]],
                         "repl": c[5], "mode": c[6]})
    return rows


def mutate(src, row):
    """Source with exactly `row`'s sub-clause flipped; raises ValueError if
    the result does not parse (an ERROR, never a silent survivor)."""
    lines = src.splitlines(keepends=True)
    (sl, sc), (el, ec) = row["start"], row["end"]
    if row["mode"] == "block":
        indent = lines[sl - 1][:sc]
        new = lines[:sl - 1] + [indent + row["repl"] + "\n"] + lines[el:]
    else:
        # character offsets on (1-based line, 0-based UTF-8 byte column) -> str index
        def idx(line, col):
            prefix = "".join(lines[:line - 1])
            return len(prefix) + len(lines[line - 1].encode("utf-8")[:col].decode("utf-8"))
        text = "".join(lines)
        a, b = idx(sl, sc), idx(el, ec)
        wrapped = row["repl"] if row["mode"] == "stmt" else "(" + row["repl"] + ")"
        new = [text[:a] + wrapped + text[b:]]
    out = "".join(new)
    ast.parse(out)
    return out


def source_sha(src):
    return hashlib.sha256(src.encode("utf-8")).hexdigest()


def main(argv):
    if len(argv) >= 2 and argv[0] == "list":
        src = open(argv[1], encoding="utf-8").read()
        for r in subclauses(src):
            print("\t".join([r["id"], r["fn"], r["kind"], str(r["line"]), r["leaf"], r["repl"]]))
        return 0
    if len(argv) == 4 and argv[0] == "mutate":
        src = open(argv[1], encoding="utf-8").read()
        rows = {r["id"]: r for r in subclauses(src)}
        if argv[2] not in rows:
            print("unknown sub-clause %s" % argv[2], file=sys.stderr)
            return 2
        try:
            out = mutate(src, rows[argv[2]])
        except (SyntaxError, ValueError) as exc:
            print("mutant does not parse: %s" % exc, file=sys.stderr)
            return 3
        open(argv[3], "w", encoding="utf-8").write(out)
        return 0
    if len(argv) == 2 and argv[0] == "json":
        print(json.dumps(subclauses(open(argv[1], encoding="utf-8").read())))
        return 0
    print(__doc__.split("CLI:")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
