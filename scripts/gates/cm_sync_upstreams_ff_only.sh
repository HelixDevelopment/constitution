#!/usr/bin/env bash
# cm_sync_upstreams_ff_only.sh — CM-SYNC-UPSTREAMS-FF-ONLY gate (§11.4.113, §11.4.84, §11.4.10, §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# scripts/sync/sync_all_upstreams.py fetches every remote of a project tree and integrates ONLY by
# fast-forward. This gate checks, on the engine file itself, that the engine can start a process at ONE place
# only, that this place puts every argument list through check_git_args and the safe configuration, that it
# can send a signal at ONE place only (guarded), and that the argument shapes it accepts cannot push, force,
# rewrite or delete:
#   (1) STATIC (Python AST, the file is never imported for this part):
#       a. IMPORT ALLOW-LIST: only `import <m>` of argparse, concurrent.futures, datetime, fcntl, hashlib,
#          json, os, re, shutil, signal, subprocess, sys, tempfile, threading, time; no `from` import, no alias,
#          no import below module level;
#       b. ATTRIBUTE ALLOW-LIST: every use of an imported module is one exact dotted name from a fixed list
#          (os.path.join, subprocess.Popen, ...); a bare module name (an alias, a module passed on) is
#          refused, so os.system, subprocess.call, sys.modules, ... cannot appear in any spelling;
#       c. ONE SPAWN POINT, ONE SIGNAL POINT (review round 2, I-2): subprocess.Popen / DEVNULL / PIPE /
#          TimeoutExpired may appear ONLY inside proc_run_git, and os.killpg / os.getpgid / signal.SIGKILL ONLY
#          inside proc_kill_group (scoped by the nearest enclosing def, so a nested def or lambda does not
#          count); Popen and killpg appear only as the function of a call (never bound to a name, passed to
#          map(), stored, ...); proc_run_git is referenced exactly once (called from Runner.run) and
#          proc_kill_group exactly once (called from proc_run_git); no `.kill` / `.terminate` / `.send_signal`
#          attribute anywhere; no `global` / `nonlocal`; check_git_args, git_argv, fetch_args, proc_run_git,
#          proc_kill_group, SAFE_CONFIG, STATUS_ARGS and the allow-lists are each bound exactly once, at module
#          level;
#       d. NO DYNAMIC ACCESS: no getattr / setattr / delattr / eval / exec / compile / __import__ / globals /
#          vars / locals / breakpoint / __builtins__ / importlib name, no dunder attribute, no dunder name
#          except __name__, no definition that shadows a module or one of those names;
#       e. the ONE Popen's argv is git_argv(git_bin, repo, checked), `checked` bound exactly once before it from
#          check_git_args(args), the parameter `args` never rebound; no shell / executable / preexec_fn / args /
#          ** keyword; the ONE killpg is os.killpg(pgid, ...) inside an `if` whose test has `pgid > 1` (§11.4.263);
#       f. every git call site (`<x>.run(repo, ARGS, ok=...)` and `g_out(r, repo, ARGS, ok=...)`) passes a literal
#          list whose first element is an allow-listed subcommand, fetch_args(...), or a module-level literal
#          list constant (STATUS_ARGS); declares the statuses that are an answer as a literal tuple of ints
#          0..255 holding 0 (review round 2, I-1); any want= is a name; only g_out forwards its own parameters;
#          `.run` appears only as a called function;
#       g. WRITE_SUBCOMMANDS is exactly {fetch, merge, checkout, add}; no allow-list holds push, reset, rebase,
#          commit, clean, gc, update-ref, branch, tag, submodule, pull, stash, cat-file, ...
#   (2) RUNTIME (the engine module is loaded from the file): for EVERY accepted argument shape (each verb the
#       engine uses), git_argv(...) is exactly [git, -C, repo] + "-c" pairs holding every required safe pair +
#       --no-optional-locks + the shape (review round 2, K04: no verb may lose a pair); git_env drops every
#       config- and transport-injecting variable (GIT_CONFIG_PARAMETERS, GIT_CONFIG_COUNT / KEY_* / VALUE_*,
#       GIT_DIR, GIT_SSH, ...; K16); redact() removes the userinfo of adversarial URL shapes ('@' or a space
#       inside a password, S-1), known token shapes and control characters; proc_run_git refuses a forbidden
#       shape BEFORE any process exists; fetch_args(...) is --no-prune --no-prune-tags --no-tags --refmap= with
#       only the engine-owned refspec(s); check_git_args REFUSES every forbidden shape and ACCEPTS every shape the
#       engine really uses (the control needle, §11.4.273).
#   (3) the wrapper scripts/sync/sync_all_upstreams.sh execs the engine with `python3 -I`.
# What it does NOT prove (§11.4.6): that git itself honours the flags, that a user-configured clean or smudge
# filter cannot run (git runs a clean filter during `status`, a smudge filter during a checkout or merge), or
# that the engine's decisions are right (tests/sync/*). It is a source check, not a sandbox: code it cannot
# see (a C extension, a modified interpreter) is out of its scope.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_sync_upstreams_ff_only.sh [--root <constitution-root>]
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (reads two files; runs no git, no network; the runtime part calls proc_run_git only with a forbidden
#   shape and a non-existent git, which must be refused before any process exists).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (absent -> BLIND).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.113, §11.4.84, §11.4.201, §11.4.263, §11.4.273, §1.1 (paired mutation:
#   cm_sync_upstreams_ff_only_mutation_test.sh); docs/manuals/sync_upstreams_manual.md.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (engine missing or unparseable, python3 missing).
#
# Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-SYNC-UPSTREAMS-FF-ONLY"
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "${2:-/nonexistent}" 2>/dev/null && pwd)" || { echo "$GATE: BLIND — bad --root" >&2; exit 2; }; shift 2 ;;
    -h|--help) sed -n 2,74p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
engine="$root/scripts/sync/sync_all_upstreams.py"
wrapper="$root/scripts/sync/sync_all_upstreams.sh"
command -v python3 >/dev/null 2>&1 || { echo "$GATE: BLIND — python3 missing" >&2; exit 2; }
[ -r "$engine" ] || { echo "$GATE: BLIND — $engine unreadable" >&2; exit 2; }
python3 -I - "$engine" "$wrapper" "$GATE" <<'PY'
import ast, importlib.util, re, sys
engine, wrapper, gate = sys.argv[1], sys.argv[2], sys.argv[3]
fails = []
try:
    src = open(engine, encoding="utf-8").read()
    tree = ast.parse(src)
except Exception as e:  # unparseable engine: cannot decide
    print("%s: BLIND — cannot parse %s: %s" % (gate, engine, e)); sys.exit(2)


def dotted(n):
    if isinstance(n, ast.Attribute):
        b = dotted(n.value)
        return b + "." + n.attr if b else n.attr
    if isinstance(n, ast.Name):
        return n.id
    return ""


MODULES = {"argparse", "concurrent.futures", "datetime", "fcntl", "hashlib", "json", "os", "re", "shutil",
           "signal", "subprocess", "sys", "tempfile", "threading", "time"}
ALLOW = {"argparse.ArgumentParser", "concurrent.futures.ThreadPoolExecutor", "datetime.datetime.now",
         "datetime.timezone.utc", "fcntl.LOCK_EX", "fcntl.LOCK_NB", "fcntl.flock", "hashlib.sha256", "json.dumps",
         "json.load", "os.O_CREAT", "os.O_NOCTTY", "os.O_NOFOLLOW", "os.O_RDWR", "os.close", "os.cpu_count",
         "os.environ", "os.environ.get", "os.fdopen", "os.fsync", "os.getcwd", "os.getpgid", "os.getpid", "os.killpg",
         "os.lstat", "os.makedirs", "os.open", "os.path.basename", "os.path.dirname", "os.path.exists",
         "os.path.expanduser", "os.path.isabs", "os.path.isdir", "os.path.isfile", "os.path.join", "os.path.lexists",
         "os.path.realpath", "os.read", "os.replace", "os.sep", "os.unlink", "os.write", "re.compile", "re.match",
         "shutil.which", "signal.SIGKILL", "subprocess.DEVNULL", "subprocess.PIPE", "subprocess.Popen",
         "subprocess.TimeoutExpired", "sys.argv", "sys.exit", "sys.stderr", "tempfile.mkstemp", "threading.Lock",
         "time.monotonic"}
# the ONE spawn point and the ONE signal point: these names may appear only inside the named function
SCOPED = {"subprocess.Popen": "proc_run_git", "subprocess.DEVNULL": "proc_run_git", "subprocess.PIPE": "proc_run_git",
          "subprocess.TimeoutExpired": "proc_run_git", "os.killpg": "proc_kill_group",
          "os.getpgid": "proc_kill_group", "signal.SIGKILL": "proc_kill_group"}
CALL_ONLY = {"subprocess.Popen", "os.killpg"}
BANNED_NAMES = {"getattr", "setattr", "delattr", "eval", "exec", "compile", "__import__", "globals", "vars",
                "locals", "breakpoint", "__builtins__", "importlib", "builtins"}
BANNED_ATTRS = {"kill", "terminate", "send_signal"}
BIND_ONCE = {"check_git_args", "git_argv", "fetch_args", "proc_run_git", "proc_kill_group", "git_env", "SAFE_CONFIG",
             "STATUS_ARGS", "READ_SUBCOMMANDS", "WRITE_SUBCOMMANDS", "FORBIDDEN_TOKENS", "FORBIDDEN_PREFIXES"}
parent = {}
for p_ in ast.walk(tree):
    for c in ast.iter_child_nodes(p_):
        parent[c] = p_


def enclosing_def(node):
    """Nearest enclosing def or lambda (a nested def or lambda is its own scope, never the outer function)."""
    cur = node
    while cur in parent:
        cur = parent[cur]
        if isinstance(cur, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)):
            return cur
    return None


def is_called(node):
    p = parent.get(node)
    return isinstance(p, ast.Call) and p.func is node


roots = {m.split(".")[0] for m in MODULES}
for node in ast.walk(tree):
    if isinstance(node, ast.ImportFrom):
        fails.append("`from` import is not allowed (line %d)" % node.lineno)
    elif isinstance(node, ast.Import):
        if node not in tree.body:
            fails.append("import below module level (line %d)" % node.lineno)
        for a in node.names:
            if a.name not in MODULES or a.asname:
                fails.append("import %s%s is not on the allow-list (line %d)"
                             % (a.name, " as " + a.asname if a.asname else "", node.lineno))
    elif isinstance(node, (ast.Global, ast.Nonlocal)):
        fails.append("global/nonlocal statement (line %d)" % node.lineno)
    elif isinstance(node, ast.Name):
        if node.id in BANNED_NAMES:
            fails.append("dynamic-access name %s (line %d)" % (node.id, node.lineno))
        elif node.id.startswith("__") and node.id != "__name__":
            fails.append("dunder name %s (line %d)" % (node.id, node.lineno))
        elif node.id in roots:
            chain, cur = [node.id], node
            while isinstance(parent.get(cur), ast.Attribute) and parent[cur].value is cur:
                cur = parent[cur]
                chain.append(cur.attr)
            name = ".".join(chain)
            if not isinstance(node.ctx, ast.Load) or name not in ALLOW:
                fails.append("module use %s is not on the allow-list (line %d)" % (name, node.lineno))
            elif name in SCOPED:
                d = enclosing_def(node)
                if not isinstance(d, ast.FunctionDef) or d.name != SCOPED[name] or d not in tree.body:
                    fails.append("%s used outside %s (line %d)" % (name, SCOPED[name], node.lineno))
                if name in CALL_ONLY and not is_called(cur):
                    fails.append("%s used as a value, not called (line %d)" % (name, node.lineno))
    elif isinstance(node, ast.Attribute):
        if node.attr.startswith("__"):
            fails.append("dunder attribute .%s (line %d)" % (node.attr, node.lineno))
        elif node.attr in BANNED_ATTRS:
            fails.append("signal-sending attribute .%s (line %d)" % (node.attr, node.lineno))
        elif node.attr == "run" and not is_called(node):
            fails.append(".run used as a value, not called (line %d)" % node.lineno)
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.arg)):
        nm = node.arg if isinstance(node, ast.arg) else node.name
        if nm in roots or nm in BANNED_NAMES:
            fails.append("definition shadows %s (line %d)" % (nm, node.lineno))


def bound_names(n):  # every name a statement or expression (re)binds
    if isinstance(n, ast.Assign):
        tg = n.targets
    elif isinstance(n, (ast.AugAssign, ast.AnnAssign, ast.NamedExpr, ast.For, ast.comprehension)):
        tg = [n.target]
    elif isinstance(n, ast.With):
        tg = [i.optional_vars for i in n.items if i.optional_vars is not None]
    elif isinstance(n, ast.ExceptHandler):
        return {n.name} if n.name else set()
    elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return {n.name}
    elif isinstance(n, ast.Import):
        return {a.asname or a.name.split(".")[0] for a in n.names}
    elif isinstance(n, ast.arg):
        return {n.arg}
    else:
        return set()
    return {x.id for t in tg for x in ast.walk(t) if isinstance(x, ast.Name)}


for nm in sorted(BIND_ONCE):
    binds = [n for n in ast.walk(tree) if nm in bound_names(n)]
    if len(binds) != 1 or binds[0] not in tree.body:
        fails.append("%s is bound %d time(s) (must be exactly once, at module level)" % (nm, len(binds)))


def fn(name, cls=None):
    body = tree.body
    if cls:
        c = [n for n in body if isinstance(n, ast.ClassDef) and n.name == cls]
        body = c[0].body if c else []
    f = [n for n in body if isinstance(n, ast.FunctionDef) and n.name == name]
    return f[0] if f else None


runner_run, g_out_fn, prg, pkg = fn("run", "Runner"), fn("g_out"), fn("proc_run_git"), fn("proc_kill_group")
for nm, f_ in (("Runner.run", runner_run), ("proc_run_git", prg), ("proc_kill_group", pkg), ("g_out", g_out_fn)):
    if f_ is None:
        fails.append("%s not found" % nm)


def loads(name):
    return [n for n in ast.walk(tree) if isinstance(n, ast.Name) and n.id == name and isinstance(n.ctx, ast.Load)]


for name, caller, cname in (("proc_run_git", runner_run, "Runner.run"), ("proc_kill_group", prg, "proc_run_git")):
    r_ = loads(name)
    if len(r_) != 1 or not is_called(r_[0]) or caller is None or enclosing_def(r_[0]) is not caller:
        fails.append("%s must be referenced exactly once, called from %s (found %d reference(s))" % (name, cname, len(r_)))

popens = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and dotted(n.func) == "subprocess.Popen"]
if len(popens) != 1:
    fails.append("expected exactly one subprocess.Popen call, found %d" % len(popens))
elif prg is not None:
    P = popens[0]
    bad_kw = sorted(str(k.arg) for k in P.keywords if k.arg in (None, "shell", "executable", "preexec_fn", "args"))
    if bad_kw:
        fails.append("Popen uses %s" % bad_kw)
    first = P.args[0] if P.args else None
    params = [x.arg for x in prg.args.args]
    ok_argv = (len(P.args) == 1 and isinstance(first, ast.Call) and dotted(first.func) == "git_argv"
               and not first.keywords and len(first.args) == 3
               and all(isinstance(x, ast.Name) for x in first.args)
               and [x.id for x in first.args] == ["git_bin", "repo", "checked"])
    if not ok_argv or params[:3] != ["git_bin", "repo", "args"]:
        fails.append("the Popen argv is not git_argv(git_bin, repo, checked) in proc_run_git(git_bin, repo, args, ...)")
    cb = [n for n in ast.walk(prg) if "checked" in bound_names(n)]
    ok_checked = (len(cb) == 1 and isinstance(cb[0], ast.Assign) and len(cb[0].targets) == 1
                  and isinstance(cb[0].targets[0], ast.Name) and isinstance(cb[0].value, ast.Call)
                  and dotted(cb[0].value.func) == "check_git_args" and len(cb[0].value.args) == 1
                  and not cb[0].value.keywords and isinstance(cb[0].value.args[0], ast.Name)
                  and cb[0].value.args[0].id == "args" and cb[0] in prg.body and cb[0].lineno < P.lineno)
    if not ok_checked:
        fails.append("`checked = check_git_args(args)` is not bound exactly once, at the top of proc_run_git, before Popen")
    if [n for n in ast.walk(prg) if "args" in bound_names(n) and not isinstance(n, ast.arg)]:
        fails.append("proc_run_git rebinds its parameter `args`")

kills = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and dotted(n.func) == "os.killpg"]


def has_pgid_gt1(test):  # a real comparison node, never a docstring/comment carrier (§11.4.201(7)(a))
    for n in ast.walk(test):
        if (isinstance(n, ast.Compare) and isinstance(n.left, ast.Name) and n.left.id == "pgid" and len(n.ops) == 1
                and isinstance(n.ops[0], ast.Gt) and isinstance(n.comparators[0], ast.Constant)
                and n.comparators[0].value == 1):
            return True
    return False


if len(kills) != 1:
    fails.append("expected exactly one os.killpg call, found %d" % len(kills))
else:
    K = kills[0]
    guarded, cur = False, K
    while cur in parent:
        cur, child = parent[cur], cur
        if isinstance(cur, ast.If) and child in cur.body and has_pgid_gt1(cur.test):
            guarded = True
    if not (K.args and isinstance(K.args[0], ast.Name) and K.args[0].id == "pgid") or not guarded:
        fails.append("os.killpg is not os.killpg(pgid, ...) inside `if ... pgid > 1 ...` (§11.4.263)")


def set_literal(name):
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            try:
                return set(ast.literal_eval(node.value))
            except Exception:
                return None
    return None


w, r = set_literal("WRITE_SUBCOMMANDS"), set_literal("READ_SUBCOMMANDS")
if w != {"fetch", "merge", "checkout", "add"}:
    fails.append("WRITE_SUBCOMMANDS is %s, expected exactly {fetch, merge, checkout, add}" % (sorted(w) if w else w))
BAD = {"push", "reset", "rebase", "commit", "clean", "gc", "update-ref", "filter-branch", "branch", "tag",
       "submodule", "pull", "stash", "restore", "switch", "worktree", "prune", "rm", "mv", "am", "apply",
       "cherry-pick", "revert", "replace", "notes", "send-pack", "receive-pack", "upload-pack", "maintenance",
       "fsck", "repack", "reflog", "init", "clone", "cat-file", "diff", "show", "log", "archive", "bundle",
       "difftool", "mergetool", "grep", "blame"}
if r is None:
    fails.append("READ_SUBCOMMANDS is not a literal set")
else:
    leak = sorted((r | (w or set())) & BAD)
    if leak:
        fails.append("allow-list contains %s" % leak)
SUBS = (r or set()) | (w or set())
LIST_CONSTS = {}
for node in tree.body:
    if (isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
            and isinstance(node.value, ast.List) and node.value.elts
            and all(isinstance(e, ast.Constant) and isinstance(e.value, str) for e in node.value.elts)):
        LIST_CONSTS[node.targets[0].id] = [e.value for e in node.value.elts]
gparams = [x.arg for x in g_out_fn.args.args] if g_out_fn else []
sites = 0
for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue
    if isinstance(node.func, ast.Attribute) and node.func.attr == "run":
        idx = 1
    elif isinstance(node.func, ast.Name) and node.func.id == "g_out":
        idx = 2
    else:
        continue
    sites += 1
    a = node.args[idx] if len(node.args) > idx else None
    kw = {k.arg: k.value for k in node.keywords}
    if None in kw or len(node.args) != idx + 1 or any(isinstance(x, ast.Starred) for x in node.args):
        fails.append("git call at line %d passes **, * or extra positional arguments" % node.lineno)
    if g_out_fn is not None and enclosing_def(node) is g_out_fn and isinstance(a, ast.Name) and a.id in gparams:
        okn, wn = kw.get("ok"), kw.get("want")
        if not (isinstance(okn, ast.Name) and okn.id == "ok" and isinstance(wn, ast.Name) and wn.id == "want"):
            fails.append("g_out does not forward ok= / want= unchanged (line %d)" % node.lineno)
        continue
    good = ((isinstance(a, ast.Call) and dotted(a.func) == "fetch_args")
            or (isinstance(a, ast.Name) and a.id in LIST_CONSTS and LIST_CONSTS[a.id][0] in SUBS)
            or (isinstance(a, ast.List) and a.elts and isinstance(a.elts[0], ast.Constant) and a.elts[0].value in SUBS
                and not any(isinstance(e, ast.Starred) for e in a.elts)))
    if not good:
        fails.append("git call at line %d does not pass a literal allow-listed argument list" % node.lineno)
    okn, okv = kw.get("ok"), None
    if (isinstance(okn, ast.Tuple) and okn.elts
            and all(isinstance(e, ast.Constant) and type(e.value) is int for e in okn.elts)):
        okv = [e.value for e in okn.elts]
    if okv is None or 0 not in okv or any(not 0 <= v <= 255 for v in okv):
        fails.append("git call at line %d does not declare its answer statuses as a literal ok=(0, ...) tuple"
                     % node.lineno)
    if "want" in kw and not isinstance(kw["want"], ast.Name):
        fails.append("git call at line %d: want= is not a name" % node.lineno)

# ── runtime part
try:
    spec = importlib.util.spec_from_file_location("sync_engine_gate", engine)
    E = importlib.util.module_from_spec(spec); spec.loader.exec_module(E)
except Exception as e:
    print("%s: BLIND — cannot load %s: %s" % (gate, engine, e)); sys.exit(2)
S = "0123456789abcdef0123456789abcdef01234567"
REQUIRED_CFG = ["core.hooksPath=/dev/null", "core.fsmonitor=false", "fetch.prune=false", "fetch.pruneTags=false",
                "fetch.recurseSubmodules=false", "submodule.recurse=false", "protocol.ext.allow=never",
                "merge.autoStash=false", "gc.auto=0", "maintenance.auto=false"]
try:
    for tags in (False, True):
        fa = E.fetch_args("origin", tags)
        want_refs = ["+refs/heads/*:refs/remotes/origin/*"] + (["refs/tags/*:refs/tags/*"] if tags else [])
        for flag in ("--no-prune", "--no-prune-tags", "--no-tags", "--refmap=", "--no-recurse-submodules"):
            if flag not in fa:
                fails.append("fetch_args(tags=%s) lacks %s" % (tags, flag))
        if "--" not in fa or fa[fa.index("--") + 1:] != ["origin"] + want_refs:
            fails.append("fetch_args(tags=%s) refspecs are %s" % (tags, fa))
        if any(x in fa for x in ("--prune", "--prune-tags", "--tags", "--force", "-f", "--mirror")):
            fails.append("fetch_args(tags=%s) carries a pruning or forcing flag: %s" % (tags, fa))
    FA = E.fetch_args("origin", False)
    FT = E.fetch_args("github_helix", True)
except Exception as e:
    print("%s: BLIND — fetch_args not usable: %s" % (gate, e))
    sys.exit(2)
STATUS = list(getattr(E, "STATUS_ARGS", None) or [])  # the gate may use getattr; the engine may not
if STATUS[:1] != ["status"]:
    fails.append("STATUS_ARGS (the one status shape) is missing or not a status call")
    STATUS = ["status", "--porcelain=v1"]
for need in ("proc_run_git", "git_env", "redact"):
    if not callable(getattr(E, need, None)):
        fails.append("engine has no %s()" % need)


def fx(*extra):  # the engine's own fetch shape with one change
    i = FA.index("--") if "--" in FA else len(FA)
    return FA[:i] + list(extra) + FA[i:]


REFUSE = [["push", "origin", "main"], ["reset", "--hard", S], ["rebase", "origin/main"], ["commit", "-m", "x"],
          ["fetch", "--prune", "--no-recurse-submodules", "--", "origin"],
          ["fetch", "--prune", "--no-recurse-submodules", "--tags", "--", "origin"],
          ["fetch", "--prune", "--no-recurse-submodules", "--", "origin", "+refs/heads/*:refs/heads/*"],
          ["fetch", "origin"], fx("--prune"), fx("--prune-tags"), fx("--force"), fx("--tags"), fx("--depth=1"),
          fx("--upload-pack=sh"), [x for x in FA if x != "--no-prune"], [x for x in FA if x != "--refmap="],
          [x for x in FA if x != "--no-tags"], [x for x in FA if x != "--no-prune-tags"],
          FA[:-1] + ["+refs/*:refs/*"], FA[:-1] + ["+refs/heads/*:refs/remotes/other/*"],
          FA[:-1] + ["+refs/heads/*:refs/heads/*"], FA + ["+refs/tags/*:refs/tags/*"],
          FA[:-2] + ["ext::sh -c x", "+refs/heads/*:refs/remotes/ext::sh -c x/*"],
          FA[:-2] + ["..", "+refs/heads/*:refs/remotes/../*"],
          ["merge", S], ["merge", "--ff", S], ["merge", "--no-ff", S], ["merge", "--squash", S],
          ["merge", "--commit", S], ["merge", "--no-commit", S], ["merge", "--ff-only", "-s", "ours", S],
          ["merge", "--ff-only", "origin/main"],
          ["checkout", "-f", S], ["checkout", "--quiet", "--detach", "--force", S], ["checkout", "main"],
          ["add", "-A"], ["add", "--", "../x"], ["add", "--", "."], ["config", "core.hooksPath", "/x"],
          ["config", "--unset", "x"], ["remote", "add", "x", "y"], ["remote", "set-url", "o", "u"],
          ["symbolic-ref", "HEAD", "refs/heads/x"], ["update-ref", "refs/heads/main", S], ["branch", "-f", "main", S],
          ["submodule", "update", "--force"], ["clean", "-fdx"], ["stash"], ["status", "--force"],
          ["rev-parse", "--git-dir=/x"], ["rev-parse", "x\ny"], ["rev-parse", "+refs/heads/main"],
          ["merge-base", "--is-ancestor", "+x", S], ["cat-file", "-e", S + "^{commit}"],
          ["diff", "--stat", "HEAD@{1}", "HEAD"], []]
# every shape the engine really uses (one per call site; the control needle)
ACCEPT = [FA, FT, STATUS,
          ["merge", "--ff-only", S], ["checkout", "--quiet", "--detach", S], ["add", "--", "libs/a"],
          ["rev-parse", "--verify", "-q", "HEAD^{commit}"], ["rev-parse", "--verify", "-q", S + "^{commit}"],
          ["rev-parse", "--verify", "-q", "refs/remotes/origin/main^{commit}"], ["rev-parse", "--show-toplevel"],
          ["rev-parse", "--absolute-git-dir", "--path-format=absolute", "--git-path", "FETCH_HEAD"],
          ["rev-parse", "--path-format=absolute", "--git-common-dir"], ["ls-files", "-s", "-z"],
          ["ls-tree", "-r", "-z", "HEAD"], ["ls-tree", "-r", "-z", "--name-only", "--full-tree", S],
          ["symbolic-ref", "--short", "-q", "HEAD"], ["config", "--get", "remote.origin.url"],
          ["config", "--get", "core.sshCommand"], ["remote"], ["merge-base", "--is-ancestor", S, S],
          ["rev-list", "--left-right", "--count", S + "..." + S], ["rev-list", "--count", "HEAD"],
          ["rev-list", "--left-right", "--count", "HEAD...HEAD"],
          ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"],
          ["for-each-ref", "--contains", S, "--format=%(refname)", "refs/remotes"]]
refused = 0
for a in REFUSE:
    try:
        E.check_git_args(a)
        fails.append("ACCEPTED a forbidden shape: git %s" % " ".join(a))
    except E.GitRefused:
        refused += 1
accepted = 0
for a in ACCEPT:
    try:
        E.check_git_args(a); accepted += 1
    except E.GitRefused as e:
        fails.append("control needle: REFUSED a shape the engine uses: git %s (%s)" % (" ".join(a), e))
        continue
    try:  # the EXACT argv of this verb: no pair lost, nothing between the pairs and the shape (K04, K14)
        argv = list(E.git_argv("git", "/r", a))
    except Exception as e:
        fails.append("git_argv raised for git %s: %s" % (" ".join(a), e)); continue
    i, cfg = 3, []
    while i + 1 < len(argv) and argv[i] == "-c":
        cfg.append(argv[i + 1]); i += 2
    missing = [c for c in REQUIRED_CFG if c not in cfg]
    if argv[:3] != ["git", "-C", "/r"] or missing or argv[i:] != ["--no-optional-locks"] + list(a):
        fails.append("git_argv for git %s is not [git -C repo] + safe -c pairs + --no-optional-locks + shape "
                     "(missing pairs %s): %s" % (" ".join(a[:3]), missing, argv))
# the environment every git call runs with: no injected config or transport (K16)
INJECT = {"GIT_CONFIG_PARAMETERS": "'core.hooksPath'='/x'", "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.x",
          "GIT_CONFIG_VALUE_0": "y", "GIT_CONFIG_KEY_7": "a", "GIT_CONFIG_VALUE_7": "b", "GIT_DIR": "/x",
          "GIT_WORK_TREE": "/x", "GIT_SSH": "/x", "GIT_ASKPASS": "/x", "GIT_PROXY_COMMAND": "/x",
          "GIT_EXEC_PATH": "/x", "GIT_ALTERNATE_OBJECT_DIRECTORIES": "/x", "PATH": "/usr/bin"}
try:
    env = E.git_env(dict(INJECT))
    left = sorted(k for k in env if k in INJECT and k != "PATH")
    if left:
        fails.append("git_env keeps injecting variables %s" % left)
    if env.get("GIT_TERMINAL_PROMPT") != "0" or env.get("PATH") != "/usr/bin":
        fails.append("git_env does not set GIT_TERMINAL_PROMPT=0 or does not keep PATH")
except Exception as e:
    fails.append("git_env not callable: %s" % e)
# redaction of adversarial credential shapes (S-1); each secret must be gone, the host must stay
GH, GL = "gh" "p_", "gl" "pat-"
RED = [("https://user:pa ss@word@example.org/r.git", ("pa ss", "word@", "user"), "example.org"),
       ("fatal: unable to access 'https://u:s3cr3t@example.org/r.git/': 403", ("s3cr3t",), "example.org"),
       ("ssh://git:hunter2@example.org:22/r.git", ("hunter2",), "example.org"),
       ("https://" + GH + "ABCDEFGHIJKLMNOPQRSTUV@github.com/o/r", ("ABCDEFGHIJ",), "github.com"),
       ("token " + GL + "abcdefghijklmnop in text", ("abcdefghijklmnop",), "token"),
       ("https://example.org/r/" + GH + "ABCDEFGHIJKLMNOPQRST/x", ("ABCDEFGHIJ",), "example.org"),
       ("https://a:b@one.org/x https://c:d@two.org/y", (":b@", ":d@"), "two.org"),
       ("esc \x1b[31mred\x1b[0m", ("\x1b",), "red")]
for text, gone, kept in RED:
    try:
        out = E.redact(text)
    except Exception as e:
        fails.append("redact raised: %s" % e); continue
    if any(g in out for g in gone) or kept not in out:
        fails.append("redact(%r) = %r (a secret remains or the host was lost)" % (text, out))
# the choke point refuses a forbidden shape before any process exists (a non-existent git: a spawn would say
# 'not-runnable', a refusal raises)
try:
    E.proc_run_git("/nonexistent/git-gate-probe", "/", ["push", "origin", "main"], {}, 1)
    fails.append("proc_run_git did not refuse git push before spawning")
except E.GitRefused:
    pass
except Exception as e:
    fails.append("proc_run_git raised %s instead of GitRefused" % type(e).__name__)
try:
    wsrc = open(wrapper, encoding="utf-8").read()
    if not re.search(r'^exec python3 -I\b.*sync_all_upstreams\.py', wsrc, re.M):
        fails.append("wrapper does not exec the engine with python3 -I")
except OSError:
    fails.append("wrapper %s unreadable" % wrapper)
if fails:
    for f in fails:
        print("%s: FAIL — %s" % (gate, f))
    sys.exit(1)
print("%s: PASS — imports and module attributes on the allow-list, no dynamic access; one spawn point "
      "(proc_run_git: argv from git_argv(check_git_args(args))) and one guarded signal point (proc_kill_group); "
      "%d git call sites with literal allow-listed argv and declared answer statuses; %d accepted shapes carry "
      "the exact safe argv; git_env scrubs %d injectors; %d redaction shapes; %d/%d forbidden shapes refused; "
      "control needle %d/%d accepted" % (gate, sites, accepted, len(INJECT) - 1, len(RED), refused, len(REFUSE),
                                          accepted, len(ACCEPT)))
PY
