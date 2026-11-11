#!/usr/bin/env python3
"""Mechanical single-edit mutants of the review_record.py TIER decision legs (CON-033 round 5,
structural round; constitution section 11.4.274: deterministic enumeration belongs in a script).

Why this exists: the sub-clause sweep (sweep_review_record_subclauses.sh) flips one and/or OPERAND
of every decision construct. It cannot write the other single-edit mutants a reviewer writes by
hand -- a comparison operator swapped, an `in (a, b)` tuple narrowed, `any` -> `all`, a returned
constant changed, a whole `if` condition forced, an exception tuple narrowed, a `|` of two mode
bits reduced to one. Rounds 2 to 5 each found such a mutant by hand (R2-F2, R3-F1, R3-F2, RV5-A,
RV5-C, RV5-D) that no suite killed. This script generates the whole CLASS, runs each mutant
against the tier suites and requires every one to be KILLED or listed EQUIVALENT with a proof.

Targets: the functions below (the tier decision: sub-id ranges, ACL probe, path components, the
resolution chain, owner-only check, owner declaration, path tier, store tier).

Mutation kinds (each yields one mutant per site):
  cmp     one comparison operator of a Compare swapped (==/!=, </<=, >/>=, in/not in, is/is not)
  bool    one and/or operator swapped
  not     one `not` removed
  cond    one `if`/`elif` condition replaced by True, and by False
  const   a True/False flipped; an int constant n -> n+1; a str constant inside a Compare gets "x"
  call    any <-> all
  ret     a returned value replaced: a (tier, reason) tuple's tier flipped; None -> "mut"; any
          other returned expression -> False and -> True
  tuple   one element dropped from a tuple used as the right side of `in` / `not in`
  exc     one element dropped from an `except (A, B)` tuple; a single `except E` -> `except KeyError`
  loop    `continue` / `break` -> `pass`
  bits    a `a | b` of two operands reduced to a, and to b
  arg-none / arg-sibling   (CALL SITES, CON-033 round 7, review R6-F1) for EVERY call of a tier function
          anywhere in the module -- the gate's own `_store_tier(a.records, a.dispatch_ledger, ...)`
          included, which lies outside TARGETS -- each argument replaced by None, and by each OTHER
          argument of the same call. Reviewer mutant RV6-E (the ledger argument replaced by the
          records argument) is exactly an arg-sibling mutant. A census of the call sites is printed
          first and checked with a control needle (a known site must be present, a fabricated callee
          must not): an empty or blind census exits 2, never "no call sites, nothing to mutate".

Two stages: stage 1 runs the fast tier suites; a mutant surviving stage 1 goes to stage 2 (every
review_record suite). The control must be GREEN. KILLED = a suite's exit status differs from its
control status. A mutant that survives stage 2 must be listed in the equivalence file
(key <TAB> reason); an unlisted survivor, or a listed key that no longer exists, FAILS the run.

Usage: mutate_tier_legs.py [--jobs N] [--stage1-only] [--list] [--only KIND] [--limit N]
                           [--equivalents FILE] [--out FILE]
Exit : 0 all killed or listed equivalent; 1 a survivor/stale key; 2 setup error; 77 control skipped.
"""
import argparse
import ast
import concurrent.futures
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FC = os.path.dirname(HERE)
TOOL = os.path.join(FC, "review", "review_record.py")
TARGETS = ("_subid_ranges", "_has_acl", "_path_components", "_resolution_chain", "_owner_only_error",
           "_owner_declaration_error", "_path_tier", "_store_tier")
STAGE1 = ("test_review_record_tier_legs_regression.sh", "test_review_record_store_tier_all_entries_regression.sh",
          "test_review_record_resolution_ground_truth.sh", "test_review_record_subclause_cases.sh")
STAGE2 = STAGE1 + ("test_review_record_round_budget_boundary_regression.sh", "test_review_record_gate_authority_r4_regression.sh",
                   "test_review_record_gate_authority_r3_regression.sh", "test_review_record_gate_authority_r1_regression.sh",
                   "test_review_record_gate_authority_r2_regression.sh", "test_review_record_red.sh",
                   "test_review_record_finding_layer_red.sh", "test_review_record_evidence_hash_r5_regression.sh",
                   "test_review_record_backfill_evidence_r2_regression.sh")
CMP_SWAP = {ast.Eq: ("==", "!="), ast.NotEq: ("!=", "=="), ast.Lt: ("<", "<="), ast.LtE: ("<=", "<"),
            ast.Gt: (">", ">="), ast.GtE: (">=", ">")}


def offsets(src):
    starts = [0]
    for line in src.splitlines(keepends=True):
        starts.append(starts[-1] + len(line.encode("utf-8")))
    return starts


class Gen(ast.NodeVisitor):
    def __init__(self, src):
        self.src = src
        self.b = src.encode("utf-8")
        self.starts = offsets(src)
        self.out = []          # (kind, fn, start, end, new_text)
        self.fn = None

    def pos(self, node):
        return (self.starts[node.lineno - 1] + node.col_offset,
                self.starts[node.end_lineno - 1] + node.end_col_offset)

    def text(self, a, b):
        return self.b[a:b].decode("utf-8")

    def add(self, kind, a, b, new):
        if self.fn is None:
            return
        self.out.append((kind, self.fn, a, b, new))

    def visit_FunctionDef(self, node):
        if node.name in TARGETS and self.fn is None:
            self.fn = node.name
            # skip the docstring expression
            for child in node.body:
                if (isinstance(child, ast.Expr) and isinstance(child.value, ast.Constant)
                        and isinstance(child.value.value, str)):
                    continue
                self.visit(child)
            self.fn = None
        else:
            self.generic_visit(node)

    def visit_Compare(self, node):
        operands = [node.left] + list(node.comparators)
        for i, op in enumerate(node.ops):
            a = self.pos(operands[i])[1]
            b = self.pos(operands[i + 1])[0]
            seg = self.text(a, b)
            new = None
            if type(op) in CMP_SWAP:
                old, rep = CMP_SWAP[type(op)]
                if old in seg:
                    new = seg.replace(old, rep, 1)
            elif isinstance(op, ast.In):
                new = re.sub(r"\bin\b", "not in", seg, count=1)
            elif isinstance(op, ast.NotIn):
                new = re.sub(r"\bnot\s+in\b", "in", seg, count=1)
            elif isinstance(op, ast.Is):
                new = re.sub(r"\bis\b", "is not", seg, count=1)
            elif isinstance(op, ast.IsNot):
                new = re.sub(r"\bis\s+not\b", "is", seg, count=1)
            if new is not None and new != seg:
                self.add("cmp", a, b, new)
            # tuple narrowing on the right side of in / not in
            right = operands[i + 1]
            if isinstance(op, (ast.In, ast.NotIn)) and isinstance(right, (ast.Tuple, ast.List)) and len(right.elts) >= 2:
                for k in range(len(right.elts)):
                    keep = [e for j, e in enumerate(right.elts) if j != k]
                    parts = [self.text(*self.pos(e)) for e in keep]
                    ra, rb = self.pos(right)
                    new_t = "(" + ", ".join(parts) + ("," if len(parts) == 1 else "") + ")"
                    self.add("tuple", ra, rb, new_t)
            # str constants inside a Compare
            for sub in operands:
                for c in ast.walk(sub):
                    if isinstance(c, ast.Constant) and isinstance(c.value, str):
                        ca, cb = self.pos(c)
                        lit = self.text(ca, cb)
                        if len(lit) >= 2 and lit[-1] in "\"'":
                            self.add("const", ca, cb, lit[:-1] + "x" + lit[-1])
        self.generic_visit(node)

    def visit_BoolOp(self, node):
        word = "and" if isinstance(node.op, ast.And) else "or"
        rep = "or" if word == "and" else "and"
        for i in range(len(node.values) - 1):
            a = self.pos(node.values[i])[1]
            b = self.pos(node.values[i + 1])[0]
            seg = self.text(a, b)
            new = re.sub(r"\b%s\b" % word, rep, seg, count=1)
            if new != seg:
                self.add("bool", a, b, new)
        self.generic_visit(node)

    def visit_UnaryOp(self, node):
        if isinstance(node.op, ast.Not):
            a, b = self.pos(node)
            oa = self.pos(node.operand)[0]
            self.add("not", a, oa, "")
        self.generic_visit(node)

    def visit_If(self, node):
        a, b = self.pos(node.test)
        for new in ("True", "False"):
            if self.text(a, b) != new:
                self.add("cond", a, b, new)
        self.generic_visit(node)

    def visit_Constant(self, node):
        a, b = self.pos(node)
        if node.value is True:
            self.add("const", a, b, "False")
        elif node.value is False:
            self.add("const", a, b, "True")
        elif isinstance(node.value, int) and not isinstance(node.value, bool):
            self.add("const", a, b, str(node.value + 1))

    def visit_Call(self, node):
        if isinstance(node.func, ast.Name) and node.func.id in ("any", "all"):
            a, b = self.pos(node.func)
            self.add("call", a, b, "all" if node.func.id == "any" else "any")
        self.generic_visit(node)

    def visit_Return(self, node):
        v = node.value
        if v is None:
            return
        a, b = self.pos(v)
        if isinstance(v, ast.Tuple) and len(v.elts) == 2 and isinstance(v.elts[0], ast.Constant) \
                and v.elts[0].value in ("capability", "instance"):
            ta, tb = self.pos(v.elts[0])
            flip = "instance" if v.elts[0].value == "capability" else "capability"
            self.add("ret", ta, tb, '"%s"' % flip)
        elif isinstance(v, ast.Constant) and v.value is None:
            self.add("ret", a, b, '"mut"')
        elif not (isinstance(v, ast.Constant) and isinstance(v.value, bool)):
            for new in ("False", "True"):
                self.add("ret", a, b, new)
        self.generic_visit(node)

    def visit_ExceptHandler(self, node):
        t = node.type
        if isinstance(t, ast.Tuple) and len(t.elts) >= 2:
            for k in range(len(t.elts)):
                keep = [self.text(*self.pos(e)) for j, e in enumerate(t.elts) if j != k]
                ta, tb = self.pos(t)
                self.add("exc", ta, tb, keep[0] if len(keep) == 1 else "(" + ", ".join(keep) + ")")
        elif t is not None:
            ta, tb = self.pos(t)
            if self.text(ta, tb) != "KeyError":
                self.add("exc", ta, tb, "KeyError")
        self.generic_visit(node)

    def visit_Continue(self, node):
        a, b = self.pos(node)
        self.add("loop", a, b, "pass")

    def visit_Break(self, node):
        a, b = self.pos(node)
        self.add("loop", a, b, "pass")

    def visit_BinOp(self, node):
        if isinstance(node.op, ast.BitOr):
            a, b = self.pos(node)
            for side in (node.left, node.right):
                self.add("bits", a, b, self.text(*self.pos(side)))
        self.generic_visit(node)


CALLEES = frozenset(TARGETS)
# call sites the census MUST find (positive needles): the gate's store-tier call and one internal chain
NEEDLE_SITES = (("cmd_gate", "_store_tier"), ("_store_tier", "_path_tier"), ("_path_tier", "_owner_only_error"),
                ("_path_tier", "_owner_declaration_error"), ("_owner_only_error", "_has_acl"),
                ("_path_tier", "_resolution_chain"), ("_path_tier", "_subid_ranges"))
NEGATIVE_NEEDLE = "_no_such_tier_function_xyz"


class CallGen(ast.NodeVisitor):
    """Argument mutants for every call of a tier function (anywhere in the module)."""
    def __init__(self, src):
        self.b = src.encode("utf-8")
        self.starts = offsets(src)
        self.stack = []
        self.sites = []     # (enclosing, callee, line, nargs)
        self.out = []

    def pos(self, node):
        return (self.starts[node.lineno - 1] + node.col_offset,
                self.starts[node.end_lineno - 1] + node.end_col_offset)

    def visit_FunctionDef(self, node):
        self.stack.append(node.name)
        self.generic_visit(node)
        self.stack.pop()

    def visit_Call(self, node):
        name = node.func.id if isinstance(node.func, ast.Name) else None
        if name in CALLEES and self.stack:
            fn = self.stack[-1]
            args = list(node.args) + [k.value for k in node.keywords]
            self.sites.append((fn, name, node.lineno, len(args)))
            texts = [self.b[self.pos(x)[0]:self.pos(x)[1]].decode("utf-8") for x in args]
            for i, x in enumerate(args):
                a, e = self.pos(x)
                if texts[i] != "None":
                    self.out.append(("arg-none", "%s>%s#%d" % (fn, name, i), a, e, "None"))
                for j, t in enumerate(texts):
                    if j != i and t != texts[i]:
                        self.out.append(("arg-sibling", "%s>%s#%d" % (fn, name, i), a, e, t))
        self.generic_visit(node)


def census(src):
    """Call-site census with control needles. Returns (sites, error-or-None)."""
    g = CallGen(src)
    g.visit(ast.parse(src))
    have = {(fn, callee) for fn, callee, _l, _n in g.sites}
    missing = [n for n in NEEDLE_SITES if n not in have]
    if missing:
        return g.sites, "census is BLIND: known call site(s) not found: %r" % (missing,)
    if any(callee == NEGATIVE_NEEDLE for _fn, callee, _l, _n in g.sites):
        return g.sites, "census is too broad: a fabricated callee was 'found'"
    return g.sites, None


def enumerate_mutants(src):
    tree = ast.parse(src)
    g = Gen(src)
    g.visit(tree)
    cgen = CallGen(src)
    cgen.visit(tree)
    g.out.extend(cgen.out)
    b = src.encode("utf-8")
    seen = {}
    ordinal = {}
    res = []
    for kind, fn, a, e, new in g.out:
        mutated = (b[:a] + new.encode("utf-8") + b[e:]).decode("utf-8")
        if mutated == src:
            continue
        try:
            compile(mutated, "<mutant>", "exec")
        except SyntaxError:
            continue
        h = hashlib.sha256(mutated.encode()).hexdigest()
        if h in seen:
            continue
        seen[h] = 1
        old = b[a:e].decode("utf-8")
        line = src.count("\n", 0, len(b[:a].decode("utf-8"))) + 1
        base = "%s|%s|%s|%s" % (fn, kind, " ".join(old.split()), " ".join(new.split()))
        ordinal[base] = ordinal.get(base, 0) + 1
        key = "%s|#%d" % (base, ordinal[base])   # n-th identical edit within the file: unique, line-shift stable
        res.append({"key": key, "kind": kind, "fn": fn, "line": line, "old": old, "new": new, "src": mutated})
    return res


def build_mirror(d, srcfile):
    os.makedirs(os.path.join(d, "review"))
    os.makedirs(os.path.join(d, "tests", "lib"))
    os.makedirs(os.path.join(d, "tests", "fixtures"))
    shutil.copy(srcfile, os.path.join(d, "review", "review_record.py"))
    shutil.copy(os.path.join(HERE, "lib", "review_record_genuine.sh"), os.path.join(d, "tests", "lib"))
    for fx in ("review_record", "review_record_finding_layer"):
        shutil.copytree(os.path.join(HERE, "fixtures", fx), os.path.join(d, "tests", "fixtures", fx))
    for t in STAGE2:
        shutil.copy(os.path.join(HERE, t), os.path.join(d, "tests", t))


def run_suite(d, t):
    try:
        p = subprocess.run(["bash", os.path.join(d, "tests", t)], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=300)
        return p.returncode
    except subprocess.TimeoutExpired:
        return 124


def kill_status(mirror, suites, control):
    for t in suites:
        rc = run_suite(mirror, t)
        if rc != control[t]:
            return "%s (rc %d, control %d)" % (t, rc, control[t])
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--stage1-only", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--keys", help="file of mutant keys (one per line, or a result TSV): run only those")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--equivalents", default=os.path.join(HERE, "fixtures", "review_record_tier_leg_equivalents.tsv"))
    ap.add_argument("--out")
    ap.add_argument("--tool", default=TOOL)
    a = ap.parse_args()
    src = open(a.tool, encoding="utf-8").read()
    sites, cerr = census(src)
    print("# call-site census: %d call(s) of %d tier functions; %s" % (
        len(sites), len(CALLEES), "control needles ok (positive sites found, fabricated callee absent)" if not cerr else cerr),
        file=sys.stderr)
    if cerr:
        print("NOT ok %s" % cerr)
        return 2
    muts = enumerate_mutants(src)
    if a.only:
        muts = [m for m in muts if m["kind"] == a.only or m["kind"].startswith(a.only + "-")]
    if a.keys:
        want = set()
        for raw in open(a.keys, encoding="utf-8"):
            raw = raw.rstrip("\n")
            want.add(raw.split("\t", 1)[1] if raw.split("\t", 1)[0] in ("KILLED", "SURVIVED", "EQUIVALENT") and "\t" in raw else raw)
        muts = [m for m in muts if m["key"] in want]
    if a.limit:
        muts = muts[:a.limit]
    if a.list:
        for m in muts:
            print("%s\t%d\t%s" % (m["key"], m["line"], m["kind"]))
        print("# %d mutants" % len(muts), file=sys.stderr)
        return 0
    equiv = {}
    if os.path.exists(a.equivalents):
        for raw in open(a.equivalents, encoding="utf-8"):
            if raw.strip() and not raw.startswith("#"):
                k, _, why = raw.rstrip("\n").partition("\t")
                if not why.strip():
                    print("equivalence entry without a reason: %s" % k, file=sys.stderr)
                    return 2
                equiv[k] = why
    work = tempfile.mkdtemp(prefix="mut_tier_")
    os.chmod(work, 0o700)
    try:
        ctl = os.path.join(work, "control")
        build_mirror(ctl, a.tool)
        control = {}
        for t in STAGE2:
            control[t] = run_suite(ctl, t)
            if control[t] not in (0, 77):
                print("NOT ok control is RED at %s (rc %d)" % (t, control[t]))
                return 2
        skipped = [t for t, rc in control.items() if rc == 77]
        print("control GREEN across %d suites%s" % (len(STAGE2), (" (skipped: %s)" % " ".join(skipped)) if skipped else ""))
        results = {}

        def one(i_m):
            i, m = i_m
            d = os.path.join(work, "m%d" % i)
            build_mirror(d, a.tool)
            with open(os.path.join(d, "review", "review_record.py"), "w", encoding="utf-8") as fh:
                fh.write(m["src"])
            k = kill_status(d, STAGE1, control)
            stage = 1
            if k is None and not a.stage1_only:
                k = kill_status(d, STAGE2[len(STAGE1):], control)
                stage = 2
            shutil.rmtree(d, ignore_errors=True)
            return m, k, stage

        survivors = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
            for n, (m, k, stage) in enumerate(ex.map(one, enumerate(muts)), 1):
                status = "KILLED" if k else ("EQUIVALENT" if m["key"] in equiv else "SURVIVED")
                results[m["key"]] = status
                print("%s %s (line %d) %s%s" % (status, m["key"][:150], m["line"], ("by " + k) if k else "", ""), flush=True)
                if status == "SURVIVED":
                    survivors.append(m)
        stale = [k for k in equiv if k not in {m["key"] for m in muts}]
        n_k = sum(1 for v in results.values() if v == "KILLED")
        n_e = sum(1 for v in results.values() if v == "EQUIVALENT")
        print("mutants %d: killed %d, equivalent %d, survived %d, stale equivalence keys %d"
              % (len(muts), n_k, n_e, len(survivors), len(stale)))
        for k in stale:
            print("STALE equivalence key (no such mutant): %s" % k)
        if a.out:
            with open(a.out, "w", encoding="utf-8") as fh:
                for key, st in sorted(results.items()):
                    fh.write("%s\t%s\n" % (st, key))
        return 1 if survivors or stale else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
