#!/usr/bin/env python3
"""class_inventory_refs.py -- review round 12 class inventory (section 11.4.276(C)): EVERY place the engine
scripts/sync/sync_all_upstreams.py names an object or a ref to git, and EVERY environment influence on which objects
and which ancestry git sees. Read on the AST (sites) and by loading the engine (allow-list and env), never by grep.

Class 1, name resolution. For each git call site (r.run / g_out with a list-literal vector) whose subcommand can
resolve a name (rev-parse, rev-list, merge-base, show-ref, ls-tree, merge, checkout, for-each-ref, cat-file, log, show,
diff, describe, name-rev, update-ref, branch, tag, reset), every argument after the subcommand is classed:
  option   a constant starting with '-' (or '--format=' + FER_EXACT_FORMAT)
  exact    the constant HEAD forms (HEAD, HEAD^{commit}, HEAD...HEAD), obj(<x>), '%s...%s' % (obj(a), obj(b)),
           or the parameter `ref` of resolve_ref_exact (exact refname filter, proven by the semantic check below)
  scope    a listed constant that is a path query or a ref-namespace scope, not a lookup (FETCH_HEAD after
           --git-path, 'refs/remotes' as the --contains scope)
  LOOKUP   anything else: a name git resolves with its lookup rules (refs/<name>, refs/tags/<name>, refs/heads/<name>,
           refs/remotes/<name>, ...). A full ref like 'refs/remotes/o/b' IS a lookup: when it is absent, git falls back
           to refs/tags/refs/remotes/o/b and refs/heads/refs/remotes/o/b (RV11-1). Every LOOKUP FAILs the run.
The r11 inventory classed the evaluate_upstream rev-parse site as 'full ref, safe' by its TEXT; this one has no such
row: a full ref is never accepted as exact.
Runtime layer (the second line): check_git_args must REFUSE every lookup shape and ACCEPT the exact ones.

Class 2, object visibility (environment). git_env() must give every git call GIT_NO_REPLACE_OBJECTS=1 and
GIT_GRAFT_FILE=/dev/null whatever the caller set, and drop the locating variables (alternates, object dir, shallow
file, replace-ref base, namespace).

Control needles (section 11.4.273): a synthetic DWIM site (rev-parse of a refs/remotes template) MUST be classed
LOOKUP and a synthetic obj() site MUST be exact; the fabricated subcommand 'frobnicate' must not be found; the known
site commit_present/rev-parse must be found in the real engine.
Usage: class_inventory_refs.py <engine.py>   Exit: 0 PASS, 1 FAIL, 2 BLIND."""
import ast
import importlib.util
import sys

OBJ_SUBS = {"rev-parse", "rev-list", "merge-base", "show-ref", "ls-tree", "merge", "checkout", "for-each-ref",
            "cat-file", "log", "show", "diff", "describe", "name-rev", "update-ref", "branch", "tag", "reset"}
HEAD_FORMS = {"HEAD", "HEAD^{commit}", "HEAD...HEAD"}
SCOPES = {("rev-parse", "FETCH_HEAD"), ("for-each-ref", "refs/remotes")}


def _is_obj(n):
    return isinstance(n, ast.Call) and getattr(n.func, "id", "") == "obj" and len(n.args) == 1


def classify(sub, node, fn):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        v = node.value
        if v.startswith("-"):
            return "option"
        if v in HEAD_FORMS:
            return "exact"
        if (sub, v) in SCOPES:
            return "scope"
        return "LOOKUP"
    if _is_obj(node):
        return "exact"
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod) and isinstance(node.left, ast.Constant) \
            and node.left.value == "%s...%s" and isinstance(node.right, ast.Tuple) \
            and all(_is_obj(e) for e in node.right.elts):
        return "exact"
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add) and isinstance(node.left, ast.Constant) \
            and node.left.value == "--format=" and getattr(node.right, "id", "") == "FER_EXACT_FORMAT":
        return "option"
    if fn == "resolve_ref_exact" and sub == "for-each-ref" and isinstance(node, ast.Name) and node.id == "ref":
        return "exact"
    return "LOOKUP"


def sites(tree):
    out = []
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        for c in ast.walk(fn):
            if not isinstance(c, ast.Call):
                continue
            name = c.func.attr if isinstance(c.func, ast.Attribute) else getattr(c.func, "id", None)
            if name not in ("run", "g_out"):
                continue
            vec = c.args[2] if name == "g_out" and len(c.args) > 2 else c.args[1] if name == "run" and len(c.args) > 1 else None
            if not (isinstance(vec, ast.List) and vec.elts and isinstance(vec.elts[0], ast.Constant)):
                continue
            sub = vec.elts[0].value
            if sub not in OBJ_SUBS:
                continue
            cls = [classify(sub, e, fn.name) for e in vec.elts[1:]]
            out.append((fn.name, sub, c.lineno, cls, ast.unparse(vec)))
    return out


def semantic(tree):
    fails = []
    fns = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    rre = fns.get("resolve_ref_exact")
    if rre is None:
        return ["no resolve_ref_exact(): no exact ref lookup"]
    exact_cmp = any(isinstance(c, ast.Compare) and isinstance(c.ops[0], ast.Eq) and isinstance(c.left, ast.Subscript)
                    and getattr(c.comparators[0], "id", "") == "ref" for c in ast.walk(rre))
    if not exact_cmp:
        fails.append("resolve_ref_exact does not keep only rows whose refname == ref")
    eu = fns.get("evaluate_upstream")
    if eu is None or not any(isinstance(c, ast.Call) and getattr(c.func, "id", "") == "resolve_ref_exact"
                             for c in ast.walk(eu)):
        fails.append("evaluate_upstream does not resolve the upstream through resolve_ref_exact()")
    return fails


def runtime(engine):
    fails, rows = [], []
    spec = importlib.util.spec_from_file_location("eng_inv", engine)
    E = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(E)
    S = "0123456789abcdef0123456789abcdef01234567"
    o = S + "^{commit}"
    fer = "--format=" + getattr(E, "FER_EXACT_FORMAT", "%(objectname)")
    refuse = [["rev-parse", "--verify", "-q", "refs/remotes/origin/dev^{commit}"], ["rev-parse", "--verify", "-q", S],
              ["merge", "--ff-only", S], ["checkout", "--quiet", "--detach", S], ["merge-base", "--is-ancestor", S, S],
              ["rev-list", "--left-right", "--count", "origin/dev...HEAD"], ["ls-tree", "-r", "-z", S],
              ["for-each-ref", "--contains", S, "--format=%(refname)", "refs/remotes"],
              ["for-each-ref", fer, "refs/remotes/*"], ["show-ref", "--verify", "refs/remotes/origin/dev"]]
    accept = [["rev-parse", "--verify", "-q", o], ["merge", "--ff-only", o], ["checkout", "--quiet", "--detach", o],
              ["merge-base", "--is-ancestor", o, o], ["rev-list", "--left-right", "--count", o + "..." + o],
              ["ls-tree", "-r", "-z", o], ["for-each-ref", "--contains", o, "--format=%(refname)", "refs/remotes"],
              ["for-each-ref", fer, "refs/remotes/origin/dev"]]
    for a in refuse:
        try:
            E.check_git_args(a)
            fails.append("allow-list ACCEPTS the lookup shape git %s" % " ".join(a)); rows.append(("refuse", a, "ACCEPTED"))
        except Exception:
            rows.append(("refuse", a, "refused"))
    for a in accept:
        try:
            E.check_git_args(a); rows.append(("accept", a, "accepted"))
        except Exception as e:
            fails.append("allow-list refuses the exact shape git %s (%s)" % (" ".join(a), e)); rows.append(("accept", a, "REFUSED"))
    caller = {"GIT_NO_REPLACE_OBJECTS": "0", "GIT_GRAFT_FILE": "/tmp/g", "GIT_ALTERNATE_OBJECT_DIRECTORIES": "/x",
              "GIT_OBJECT_DIRECTORY": "/x", "GIT_SHALLOW_FILE": "/x", "GIT_REPLACE_REF_BASE": "refs/x/",
              "GIT_NAMESPACE": "x", "PATH": "/usr/bin"}
    env = E.git_env(caller)
    want = {"GIT_NO_REPLACE_OBJECTS": "1", "GIT_GRAFT_FILE": "/dev/null"}
    for k, v in want.items():
        rows.append(("env", k, env.get(k)))
        if env.get(k) != v:
            fails.append("git_env gives %s=%r, not %r (object visibility not pinned)" % (k, env.get(k), v))
    for k in ("GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_OBJECT_DIRECTORY", "GIT_SHALLOW_FILE", "GIT_REPLACE_REF_BASE",
              "GIT_NAMESPACE"):
        rows.append(("env", k, env.get(k)))
        if k in env:
            fails.append("git_env keeps the caller's %s" % k)
    if env.get("PATH") != "/usr/bin":
        fails.append("control: git_env lost PATH")
    return fails, rows


NEEDLE_SRC = '''
def evaluate_upstream(r, p, rem, branch):
    res = r.run(p, ["rev-parse", "--verify", "-q", "refs/remotes/%s/%s^{commit}" % (rem, branch)], ok=(0, 1))
def is_ancestor(r, p, a, b):
    res = r.run(p, ["merge-base", "--is-ancestor", obj(a), obj(b)], ok=(0, 1))
'''


def main(argv):
    if len(argv) != 1:
        print("usage: class_inventory_refs.py <engine.py>", file=sys.stderr)
        return 2
    nd = {(f, s): c for f, s, _, c, _ in sites(ast.parse(NEEDLE_SRC))}
    if nd.get(("evaluate_upstream", "rev-parse")) != ["option", "option", "LOOKUP"] or \
            nd.get(("is_ancestor", "merge-base")) != ["option", "exact", "exact"]:
        print("class-inventory-refs: BLIND - the control needles were not classed as expected: %s" % nd)
        return 2
    tree = ast.parse(open(argv[0], encoding="utf-8").read())
    found = sites(tree)
    if not any(f == "commit_present" and s == "rev-parse" for f, s, _, _, _ in found):
        print("class-inventory-refs: BLIND - the known site commit_present/rev-parse was not found")
        return 2
    if any(s == "frobnicate" for _, s, _, _, _ in found):
        print("class-inventory-refs: BLIND - the fabricated needle matched")
        return 2
    fails = []
    for f, s, ln, cls, txt in sorted(found, key=lambda x: x[2]):
        verdict = "LOOKUP" if "LOOKUP" in cls else "exact"
        print("site %-18s %-13s line %-5d %-6s %s" % (f, s, ln, verdict, txt))
        if verdict == "LOOKUP":
            fails.append("%s line %d: git %s resolves a name by git's lookup rules: %s" % (f, ln, s, txt))
    fails += semantic(tree)
    try:
        rf, rows = runtime(argv[0])
    except Exception as e:
        print("class-inventory-refs: BLIND - cannot load the engine: %s" % e)
        return 2
    for kind, a, res in rows:
        print("%-6s %-9s %s" % (kind, res, " ".join(a) if isinstance(a, list) else a))
    fails += rf
    print("class-inventory-refs: sites %d (exact %d, lookup %d); allow-list probes %d; env probes %d"
          % (len(found), sum(1 for x in found if "LOOKUP" not in x[3]), sum(1 for x in found if "LOOKUP" in x[3]),
             sum(1 for r in rows if r[0] != "env"), sum(1 for r in rows if r[0] == "env")))
    for x in fails:
        print("FAIL " + x)
    print("class-inventory-refs: %s" % ("FAIL (%d)" % len(fails) if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
