#!/usr/bin/env python3
"""CON-030 round 4 class sweep (section 11.4.276(C), 11.4.273): list every site in the full-suite engine that has one
of the three bug shapes of review r3, so each can be classified by hand.

  A  line splitting / reading: splitlines(), split("\\n"), readline(s), open() (a file read or written)
  B  identity built from text: a string join or %-format whose result is compared, used as a dict key or hashed
  C  output: a write to stdout, stderr or a file (a message, an evidence line)

Usage: python3 -I con030_class_sweep_r4.py <engine.py>. Prints one line per site: shape, line, the AST form, the
source line. Control needles (section 11.4.273): for each shape a site known to exist must be found (positive) and a
fabricated name must not be (negative); a failed control exits 2 and the listing is not evidence.
"""
import ast
import sys

src = open(sys.argv[1]).read()  # the engine source, read whole
L = src.split("\n")
tree = ast.parse(src)
sites = []


def name_of(f):
    if isinstance(f, ast.Name):
        return f.id
    if isinstance(f, ast.Attribute):
        return f.attr
    return None


def text_built(n):
    """True for a str/bytes join, a %-format with a str/bytes literal, an f-string, a `+` with a literal, or a
    conditional whose branch is one of these."""
    if isinstance(n, ast.IfExp):
        return text_built(n.body) or text_built(n.orelse)
    if isinstance(n, ast.Call) and name_of(n.func) == "join" and isinstance(n.func, ast.Attribute) \
            and isinstance(n.func.value, ast.Constant) and isinstance(n.func.value.value, (str, bytes)):
        return True
    if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Mod) and isinstance(n.left, ast.Constant) \
            and isinstance(n.left.value, (str, bytes)):
        return True
    if isinstance(n, ast.JoinedStr):
        return True
    if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add):
        return any(isinstance(x, ast.Constant) and isinstance(x.value, (str, bytes)) for x in (n.left, n.right)) \
            or text_built(n.left) or text_built(n.right)
    return False


for n in ast.walk(tree):
    if isinstance(n, ast.Call):
        nm = name_of(n.func)
        if nm in ("splitlines", "readline", "readlines", "open") or (
                nm == "split" and n.args and isinstance(n.args[0], ast.Constant) and n.args[0].value in ("\n", b"\n")):
            sites.append(("A", n.lineno, nm))
        if nm in ("write", "out", "err") or (nm == "print"):
            sites.append(("C", n.lineno, nm))
        if nm in ("update", "sha256") and n.args and any(text_built(a) for a in n.args):
            sites.append(("B", n.lineno, "hash of built text"))
    if isinstance(n, ast.Compare) and any(text_built(x) for x in [n.left] + n.comparators):
        sites.append(("B", n.lineno, "compare built text"))
    if isinstance(n, ast.Subscript) and text_built(n.slice):
        sites.append(("B", n.lineno, "key from built text"))
    if isinstance(n, ast.Dict):
        for k in n.keys:
            if k is not None and text_built(k):
                sites.append(("B", n.lineno, "dict key from built text"))
    if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id in ("uid", "key") for t in n.targets) \
            and text_built(n.value):
        sites.append(("B", n.lineno, "id/key assigned from built text"))

needles = {"A": "gov_lines", "B": "uid = path", "C": "esc_out(msg)"}
fake = "zz_no_such_symbol_qq"
bad = False
for shape, needle in needles.items():
    hit = any(needle in L[ln - 1] or needle in "\n".join(L[max(0, ln - 25):ln])
              for s, ln, _ in sites if s == shape)
    if not hit:
        print("CONTROL FAIL: shape %s positive needle %r not found" % (shape, needle))
        bad = True
if any(fake in L[ln - 1] for _s, ln, _ in sites):
    print("CONTROL FAIL: negative needle found")
    bad = True
for s, ln, form in sorted(set(sites), key=lambda x: (x[0], x[1])):
    print("%s\t%d\t%s\t%s" % (s, ln, form, L[ln - 1].strip()[:150]))
print("SITES A=%d B=%d C=%d controls=%s" % tuple([len(set(x for x in sites if x[0] == k)) for k in "ABC"]
                                              + ["FAIL" if bad else "ok"]))
sys.exit(2 if bad else 0)
