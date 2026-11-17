#!/usr/bin/env python3
"""class_inventory_r13.py -- review round 13 class inventory (section 11.4.276(C)), extending the round-12
inventory (docs/qa/sync_upstreams_2026_11_16_r12/class_inventory_refs.py, classes 1 and 2, kept) with the classes
the round-12 review found open. Read on the AST (sites) and by loading the engine (allow-list, env, parsers).

Class 1, name resolution (round 12, kept): every argument of an object/ref-naming git call is option, exact, scope or
  LOOKUP; a LOOKUP FAILs. New accepted option: '--format=' + FER_CONTAINS_FORMAT. Every rev-list shape ends with '--'
  (RV12-3: a work-tree file named HEAD makes 'rev-list --count HEAD' ambiguous).
Class 2, object visibility (round 12, kept).
Class 3, ref names git does not take literally (RV12-1): a SYMBOLIC ref at an exact name. Both for-each-ref formats
  must read %(symref) on the same line as the refname; resolve_ref_exact must give no commit for a symbolic hit and
  name it; contained_refs must drop symbolic lines and give NO ANSWER on a malformed line. Checked by feeding the
  engine's own parsers recorded output (a stand-in runner, no git process: gate-logic class).
Class 4, paths git reads as patterns (RV12-2): every git call whose subcommand takes a pathspec (add, ls-files,
  status, diff, rm, reset, commit, grep, checkout with '--', log/rev-list after '--') is listed with its path
  arguments; git_env must pin GIT_LITERAL_PATHSPECS=1 and drop GIT_GLOB/NOGLOB/ICASE_PATHSPECS (git refuses LITERAL
  together with GLOB or ICASE: ground_truth/gt_raw_git.txt); 'add' must take its path after '--'; write_git must call
  stage_pin_verified after the stage-pin add.
Class 5, call shapes (RV12-4): every git call of the engine must be a direct r.run(...) / g_out(...) with a LIST
  LITERAL vector, so classes 1 and 4 see it. Reported and FAILED: a call whose vector is not a list literal (a
  variable, a concatenation, a keyword argument), an alias of run/g_out (assigned, passed, or taken without a call),
  and any subprocess / os.exec* / os.system / os.popen call outside the Runner. The gate
  scripts/gates/cm_sync_upstreams_ff_only.sh holds the same oracle at build time (its SITES table and site count).

Control needles (section 11.4.273): the round-12 needles, plus a synthetic aliased call and a synthetic variable
vector that MUST be reported (class 5), and a synthetic symbolic row that MUST give no commit (class 3).
Usage: class_inventory_r13.py <engine.py>   Exit: 0 PASS, 1 FAIL, 2 BLIND."""
import ast
import importlib.util
import sys
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

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
            and node.left.value == "--format=" and getattr(node.right, "id", "") in ("FER_EXACT_FORMAT",
                                                                                     "FER_CONTAINS_FORMAT"):
        return "option"
    if fn == "resolve_ref_exact" and sub == "for-each-ref" and isinstance(node, ast.Name) and node.id == "ref":
        return "exact"
    return "LOOKUP"


CONSTS = {}
FUNVECS = {}


def load_vectors(tree):
    """Module-level list constants (STATUS_ARGS) and functions that build ONE vector from a list literal they
    return (fetch_args): a call site that passes either is resolved to that literal (class 5: no unseen vector)."""
    CONSTS.clear()
    FUNVECS.clear()
    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name) \
                and isinstance(n.value, ast.List):
            CONSTS[n.targets[0].id] = n.value
        if isinstance(n, ast.FunctionDef) and n.body:
            first = [s for s in n.body if not (isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant))]
            if first and isinstance(first[0], ast.Assign) and isinstance(first[0].value, ast.List) \
                    and len(first[0].targets) == 1 and isinstance(first[0].targets[0], ast.Name):
                var = first[0].targets[0].id
                rets = [s for s in ast.walk(n) if isinstance(s, ast.Return)]
                if rets and all(isinstance(r.value, ast.Name) and r.value.id == var for r in rets):
                    FUNVECS[n.name] = first[0].value


def vector_of(c, name):
    vi = 2 if name == "g_out" else 1
    vec = c.args[vi] if len(c.args) > vi else None
    if isinstance(vec, ast.Name) and vec.id in CONSTS:
        return CONSTS[vec.id]
    if isinstance(vec, ast.Call) and getattr(vec.func, "id", None) in FUNVECS:
        return FUNVECS[vec.func.id]
    return vec


def is_git_call(c):
    f = c.func
    if isinstance(f, ast.Attribute):
        return f.attr == "run" and not (isinstance(f.value, ast.Name) and f.value.id == "subprocess")
    return getattr(f, "id", None) == "g_out"


def sites(tree):
    out = []
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        for c in ast.walk(fn):
            if not isinstance(c, ast.Call):
                continue
            if not is_git_call(c):
                continue
            name = c.func.attr if isinstance(c.func, ast.Attribute) else c.func.id
            vec = vector_of(c, name)
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
    fcon = getattr(E, "FER_CONTAINS_FORMAT", "%(refname)")
    refuse = [["rev-parse", "--verify", "-q", "refs/remotes/origin/dev^{commit}"], ["rev-parse", "--verify", "-q", S],
              ["merge", "--ff-only", S], ["checkout", "--quiet", "--detach", S], ["merge-base", "--is-ancestor", S, S],
              ["rev-list", "--left-right", "--count", "origin/dev...HEAD", "--"], ["ls-tree", "-r", "-z", S],
              ["rev-list", "--left-right", "--count", o + "..." + o], ["rev-list", "--count", "HEAD"],
              ["for-each-ref", "--contains", S, "--format=" + fcon, "refs/remotes"],
              ["for-each-ref", "--contains", o, "--format=%(refname)", "refs/remotes"],
              ["add", "lib"], ["add", "--", "lib", "other"], ["ls-files", "-s", "-z", "lib"],
              ["for-each-ref", fer, "refs/remotes/*"], ["show-ref", "--verify", "refs/remotes/origin/dev"]]
    accept = [["rev-parse", "--verify", "-q", o], ["merge", "--ff-only", o], ["checkout", "--quiet", "--detach", o],
              ["merge-base", "--is-ancestor", o, o], ["rev-list", "--left-right", "--count", o + "..." + o, "--"],
              ["rev-list", "--count", "HEAD", "--"], ["ls-tree", "-r", "-z", o],
              ["for-each-ref", "--contains", o, "--format=" + fcon, "refs/remotes"], ["add", "--", "lib"],
              ["ls-files", "-s", "-z"],
              ["for-each-ref", fer, "refs/remotes/origin/dev"]]
    for a in refuse:
        try:
            E.check_git_args(a)
            fails.append("allow-list ACCEPTS the refused shape git %s" % " ".join(a)); rows.append(("refuse", a, "ACCEPTED"))
        except Exception:
            rows.append(("refuse", a, "refused"))
    for a in accept:
        try:
            E.check_git_args(a); rows.append(("accept", a, "accepted"))
        except Exception as e:
            fails.append("allow-list refuses the exact shape git %s (%s)" % (" ".join(a), e)); rows.append(("accept", a, "REFUSED"))
    caller = {"GIT_NO_REPLACE_OBJECTS": "0", "GIT_GRAFT_FILE": "/tmp/g", "GIT_ALTERNATE_OBJECT_DIRECTORIES": "/x",
              "GIT_OBJECT_DIRECTORY": "/x", "GIT_SHALLOW_FILE": "/x", "GIT_REPLACE_REF_BASE": "refs/x/",
              "GIT_NAMESPACE": "x", "PATH": "/usr/bin", "GIT_LITERAL_PATHSPECS": "0", "GIT_GLOB_PATHSPECS": "1",
              "GIT_NOGLOB_PATHSPECS": "1", "GIT_ICASE_PATHSPECS": "1"}
    env = E.git_env(caller)
    want = {"GIT_NO_REPLACE_OBJECTS": "1", "GIT_GRAFT_FILE": "/dev/null", "GIT_LITERAL_PATHSPECS": "1"}
    for k, v in want.items():
        rows.append(("env", k, env.get(k)))
        if env.get(k) != v:
            fails.append("git_env gives %s=%r, not %r (not pinned)" % (k, env.get(k), v))
    for k in ("GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_OBJECT_DIRECTORY", "GIT_SHALLOW_FILE", "GIT_REPLACE_REF_BASE",
              "GIT_NAMESPACE", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS"):
        rows.append(("env", k, env.get(k)))
        if k in env:
            fails.append("git_env keeps the caller's %s" % k)
    if env.get("PATH") != "/usr/bin":
        fails.append("control: git_env lost PATH")
    f3, r3 = symref_runtime(E, S)
    return fails + f3, rows + r3


PATH_SUBS = {"add", "ls-files", "status", "diff", "rm", "reset", "commit", "grep", "checkout", "log", "rev-list",
             "mv", "restore", "stash", "clean", "update-index", "check-ignore", "check-attr"}


class _Stub:
    """A stand-in runner: answers one call with recorded output, records no_answer (class 3, gate-logic class)."""
    def __init__(self, E, out):
        self.E, self.out, self.calls, self.na = E, out, [], []

    def run(self, repo, args, **kw):
        self.calls.append(list(args))
        return self.E.GitResult(True, 0, self.out, "", None)

    def no_answer(self, repo, sub, why):
        self.na.append((sub, why))


def symref_runtime(E, S):
    fails, rows = [], []
    for name in ("FER_EXACT_FORMAT", "FER_CONTAINS_FORMAT"):
        f = getattr(E, name, "")
        ok_ = f.startswith("%(refname)%00%(symref)")
        rows.append(("symref", name, "reads-symref" if ok_ else "NO-SYMREF"))
        if not ok_:
            fails.append("%s does not read %%(symref) right after %%(refname): %r" % (name, f))
    ref = "refs/remotes/origin/dev"
    cases = [("symbolic->branch", "\0".join([ref, "refs/heads/evil", "commit", S, "", ""]) + "\n", None, True),
             ("symbolic->tag", "\0".join([ref, "refs/tags/t", "tag", S, "commit", S]) + "\n", None, True),
             ("plain (control)", "\0".join([ref, "", "commit", S, "", ""]) + "\n", S, False)]
    for label, out, want, sym in cases:
        st = _Stub(E, out)
        notes = {}
        try:
            res, sha = E.resolve_ref_exact(st, "/x", ref, notes)
        except TypeError:
            res, sha = E.resolve_ref_exact(st, "/x", ref)
        good = sha == want and bool(notes.get("symbolic")) == sym and res.answered
        rows.append(("symref", "resolve_ref_exact " + label, "ok" if good else "WRONG sha=%s notes=%s" % (sha, notes)))
        if not good:
            fails.append("resolve_ref_exact on a %s row gives sha=%s notes=%s (want %s, symbolic=%s)"
                         % (label, sha, notes, want, sym))
    cr = getattr(E, "contained_refs", None)
    if cr is None:
        fails.append("no contained_refs(): the --contains answer is not parsed for symbolic lines")
    else:
        for label, out, want in (("drop symbolic", "refs/remotes/origin/HEAD\0refs/remotes/origin/main\n"
                                                    "refs/remotes/origin/main\0\n", ["refs/remotes/origin/main"]),
                                 ("malformed -> no answer", "refs/remotes/origin/main\n", None),
                                 ("outside refs/remotes -> no answer", "refs/heads/x\0\n", None)):
            st = _Stub(E, out)
            got = cr(st, "/x", E.GitResult(True, 0, out, "", None))
            good = got == want and (want is not None or st.na)
            rows.append(("symref", "contained_refs " + label, "ok" if good else "WRONG %s" % got))
            if not good:
                fails.append("contained_refs %s gives %s" % (label, got))
    return fails, rows


def path_sites(tree):
    out = []
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        for c in ast.walk(fn):
            if not isinstance(c, ast.Call):
                continue
            if not is_git_call(c):
                continue
            name = c.func.attr if isinstance(c.func, ast.Attribute) else c.func.id
            vec = vector_of(c, name)
            if not (isinstance(vec, ast.List) and vec.elts and isinstance(vec.elts[0], ast.Constant)):
                continue
            sub = vec.elts[0].value
            if sub in PATH_SUBS:
                el = vec.elts[1:]
                consts = [e.value for e in el if isinstance(e, ast.Constant)]
                dd = "--" in consts
                paths = [ast.unparse(e) for i, e in enumerate(el) if dd and consts and
                         any(isinstance(x, ast.Constant) and x.value == "--" for x in el[:i])]
                nonopt = [ast.unparse(e) for e in el if not (isinstance(e, ast.Constant) and str(e.value).startswith("-"))]
                out.append((fn.name, sub, c.lineno, dd, paths, nonopt, ast.unparse(vec)))
    return out


def path_semantic(tree, found):
    fails = []
    for f, s, ln, dd, paths, nonopt, txt in found:
        if s == "add" and not dd:
            fails.append("%s line %d: git add without '--' before its path: %s" % (f, ln, txt))
        if s == "rev-list" and not dd:
            fails.append("%s line %d: git rev-list without a trailing '--' (RV12-3): %s" % (f, ln, txt))
        if s == "checkout" and "'--detach'" in txt:
            continue  # 'checkout --detach <commit>' takes no pathspec (ground_truth/gt_checkout_detach.txt)
        if s not in ("add", "rev-list") and nonopt and not dd:
            fails.append("%s line %d: git %s takes a non-option argument with no '--': %s" % (f, ln, s, txt))
    fns = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    wg = fns.get("write_git")
    if wg is None or not any(isinstance(c, ast.Call) and getattr(c.func, "id", "") == "stage_pin_verified"
                             for c in ast.walk(wg)):
        fails.append("write_git does not verify the index after the stage-pin add (stage_pin_verified)")
    return fails


def primitive_ok(c, fn):
    """The ONE process primitive (proc_run_git): its Popen runs git_argv(<bin>, <repo>, checked) where, in the same
    function, checked = check_git_args(args). Any other process call outside the Runner is reported."""
    if fn is None or not c.args:
        return False
    a0 = c.args[0]
    if not (isinstance(a0, ast.Call) and getattr(a0.func, "id", "") == "git_argv" and a0.args
            and isinstance(a0.args[-1], ast.Name) and a0.args[-1].id == "checked"):
        return False
    return any(isinstance(s, ast.Assign) and len(s.targets) == 1 and getattr(s.targets[0], "id", "") == "checked"
               and isinstance(s.value, ast.Call) and getattr(s.value.func, "id", "") == "check_git_args"
               for s in ast.walk(fn))


def call_shapes(tree, runner_class="Runner"):
    """Class 5: every git call is direct with a list literal; no alias; no process call outside the Runner."""
    rep = []
    runner_lines = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.ClassDef) and n.name == runner_class:
            runner_lines = {x.lineno for x in ast.walk(n) if hasattr(x, "lineno")}
    called = set()
    enclosing, fns_by_line = {}, {}
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        for x in ast.walk(fn):
            if hasattr(x, "lineno"):
                enclosing[x.lineno] = fn.name
                fns_by_line[x.lineno] = fn
    for c in ast.walk(tree):
        if not isinstance(c, ast.Call):
            continue
        f = c.func
        called.add(id(f))
        name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", None)
        if is_git_call(c):
            vec = vector_of(c, name)
            fn = enclosing.get(c.lineno)
            if any(k.arg in ("args", "argv", "cmd") for k in c.keywords):
                rep.append(("keyword-vector", c.lineno, ast.unparse(c)))
            elif fn == "g_out" and isinstance(vec, ast.Name) and vec.id == "args":
                pass  # the wrapper itself: every g_out(...) call is a site of its own (checked above)
            elif not (isinstance(vec, ast.List) and vec.elts and isinstance(vec.elts[0], ast.Constant)):
                rep.append(("non-literal-vector", c.lineno, ast.unparse(c)))
        mod = f.value.id if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) else None
        if (mod == "subprocess" or (mod == "os" and (name or "").startswith(("exec", "spawn", "system", "popen")))) \
                and c.lineno not in runner_lines and not primitive_ok(c, fns_by_line.get(c.lineno)):
            rep.append(("process-call-outside-runner", c.lineno, ast.unparse(c)))
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute) and n.attr in ("run", "g_out") and id(n) not in called \
                and not (isinstance(n.value, ast.Name) and n.value.id == "subprocess"):
            rep.append(("alias", n.lineno, ast.unparse(n)))
        if isinstance(n, ast.Name) and n.id == "g_out" and isinstance(n.ctx, ast.Load) and id(n) not in called:
            rep.append(("alias", n.lineno, "g_out"))
    return rep


SHAPE_NEEDLE = """
class Runner:
    def run(self, p, args):
        return subprocess.run(args)
def f(r, p):
    go = r.run
    v = ["rev-parse", "HEAD"]
    r.run(p, v)
    r.run(p, ["status"] + [])
    subprocess.run(["git", "status"])
    r.run(p, ["status", "--porcelain=v2"])
"""


NEEDLE_SRC = '''
def evaluate_upstream(r, p, rem, branch):
    res = r.run(p, ["rev-parse", "--verify", "-q", "refs/remotes/%s/%s^{commit}" % (rem, branch)], ok=(0, 1))
def is_ancestor(r, p, a, b):
    res = r.run(p, ["merge-base", "--is-ancestor", obj(a), obj(b)], ok=(0, 1))
'''


def main(argv):
    if len(argv) != 1:
        print("usage: class_inventory_r13.py <engine.py>", file=sys.stderr)
        return 2
    nd = {(f, s): c for f, s, _, c, _ in sites(ast.parse(NEEDLE_SRC))}
    if nd.get(("evaluate_upstream", "rev-parse")) != ["option", "option", "LOOKUP"] or \
            nd.get(("is_ancestor", "merge-base")) != ["option", "exact", "exact"]:
        print("class-inventory-r13: BLIND - the control needles were not classed as expected: %s" % nd)
        return 2
    tree = ast.parse(open(argv[0], encoding="utf-8").read())
    load_vectors(tree)
    if "STATUS_ARGS" not in CONSTS or "fetch_args" not in FUNVECS:
        print("class-inventory-r13: BLIND - the known vectors STATUS_ARGS / fetch_args were not resolved")
        return 2
    found = sites(tree)
    if not any(f == "commit_present" and s == "rev-parse" for f, s, _, _, _ in found):
        print("class-inventory-r13: BLIND - the known site commit_present/rev-parse was not found")
        return 2
    if any(s == "frobnicate" for _, s, _, _, _ in found):
        print("class-inventory-r13: BLIND - the fabricated needle matched")
        return 2
    fails = []
    for f, s, ln, cls, txt in sorted(found, key=lambda x: x[2]):
        verdict = "LOOKUP" if "LOOKUP" in cls else "exact"
        print("site %-18s %-13s line %-5d %-6s %s" % (f, s, ln, verdict, txt))
        if verdict == "LOOKUP":
            fails.append("%s line %d: git %s resolves a name by git's lookup rules: %s" % (f, ln, s, txt))
    fails += semantic(tree)
    saved = (dict(CONSTS), dict(FUNVECS))
    nt = ast.parse(SHAPE_NEEDLE)
    load_vectors(nt)
    nshape = sorted(k for k, _, _ in call_shapes(nt))
    CONSTS.clear(); CONSTS.update(saved[0]); FUNVECS.clear(); FUNVECS.update(saved[1])
    if nshape != ["alias", "non-literal-vector", "non-literal-vector", "process-call-outside-runner"]:
        print("class-inventory-r13: BLIND - the call-shape needles were not reported as expected: %s" % nshape)
        return 2
    for kind, ln, txt in call_shapes(tree):
        print("shape  %-28s line %-5d %s" % (kind, ln, txt))
        fails.append("call shape %s at line %d (classes 1 and 4 cannot see it): %s" % (kind, ln, txt))
    pfound = path_sites(tree)
    if not any(s == "add" for _, s, _, _, _, _, _ in pfound):
        print("class-inventory-r13: BLIND - the known pathspec site (stage-pin add) was not found")
        return 2
    for f, s, ln, dd, paths, nonopt, txt in sorted(pfound, key=lambda x: x[2]):
        print("path   %-18s %-9s line %-5d dd=%-5s paths=%s %s" % (f, s, ln, dd, paths, txt))
    fails += path_semantic(tree, pfound)
    try:
        rf, rows = runtime(argv[0])
    except Exception as e:
        print("class-inventory-r13: BLIND - cannot load the engine: %s" % e)
        return 2
    for kind, a, res in rows:
        print("%-6s %-9s %s" % (kind, res, " ".join(a) if isinstance(a, list) else a))
    fails += rf
    print("class-inventory-r13: sites %d (exact %d, lookup %d); allow-list probes %d; env probes %d"
          % (len(found), sum(1 for x in found if "LOOKUP" not in x[3]), sum(1 for x in found if "LOOKUP" in x[3]),
             sum(1 for r in rows if r[0] not in ("env", "symref")), sum(1 for r in rows if r[0] == "env")))
    print("class-inventory-r13: pathspec sites %d; symref probes %d" % (len(pfound), sum(1 for r in rows if r[0] == "symref")))
    for x in fails:
        print("FAIL " + x)
    print("class-inventory-r13: %s" % ("FAIL (%d)" % len(fails) if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
