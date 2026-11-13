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
#          ** keyword; start_new_session=True; the ONE killpg is EXACTLY os.killpg(pgid, signal.SIGKILL), `pgid`
#          bound exactly once as `pgid = os.getpgid(p.pid)`, and its nearest `if` (only a try may stand between)
#          is a direct statement of proc_kill_group whose test is EXACTLY the conjunction
#          `isinstance(pgid, int) and pgid > 1 and pgid == p.pid` in any order (no `or`, no `not`, no constant, no
#          fourth term; review round 3, X04: `pgid > 1 or True` passed the old "has pgid > 1" test) (§11.4.263);
#       f. every git call site (`<x>.run(repo, ARGS, ok=...)` and `g_out(r, repo, ARGS, ok=...)`) passes a literal
#          list whose first element is an allow-listed subcommand, fetch_args(...), or a module-level literal
#          list constant (STATUS_ARGS); declares the statuses that are an answer as a literal tuple of ints
#          0..255 holding 0 (review round 2, I-1); any want= is a name; only g_out forwards its own parameters;
#          `.run` appears only as a called function;
#       g. WRITE_SUBCOMMANDS is exactly {fetch, merge, checkout, add}; no allow-list holds push, reset, rebase,
#          commit, clean, gc, update-ref, branch, tag, submodule, pull, stash, cat-file, ...
#       h. BOUNDED ANSWER SETS (review round 3, X06): every declared ok= is a subset of {0, 1, 128} with at most
#          three values (a site that "declares" every status 0..255 declares nothing);
#       i. WRITE VERBS IN ONE PLACE (review round 3, X02 / X02b): a call site whose argument list starts with
#          merge, checkout or add is inside write_git (the one guarded writer), and fetch_args(...) is passed only
#          inside fetch_repo;
#       j. THE CALL-SITE ORACLE (review round 3, X01, and the false class-inventory claim of round 3): SITES below is
#          an independent table, written by hand, of every git call site: (function, argument list as source text,
#          declared answer statuses, declared output shape, what an exit 128 becomes there). The multiset of call
#          sites read from the engine's AST must EQUAL it: a new site, a moved site, a changed argument list, a
#          widened or narrowed ok= set (rc 128 accepted as a clean answer at a write guard) or a dropped want= is a
#          FAIL until the table (and docs/qa/<round>/class_inventory.md) is changed with it. The table is checked
#          for self-consistency first: "blind" (128 is no answer) exactly when 128 is not declared; "failed" only
#          for merge / checkout / add in write_git; "unreachable" only for fetch_args in fetch_repo; "start-dir" only
#          in main (the work-tree probe of the start directory, BLIND when a .git exists there).
#   (2) RUNTIME (the engine module is loaded from the file): for EVERY accepted argument shape (each verb the
#       engine uses), git_argv(...) is exactly [git, -C, repo] + "-c" pairs + --no-optional-locks + the shape,
#       where the pairs set every required safe key EXACTLY ONCE (key compared without case) to its required value
#       and set no other key (review round 2, K04: no verb may lose a pair; round 3, X07: a later
#       core.hooksPath=<dir> pair overrides the first one, so presence alone proves nothing); git_env drops every
#       config-, transport- and trace-injecting variable (GIT_CONFIG_PARAMETERS, GIT_CONFIG_COUNT / KEY_* /
#       VALUE_*, GIT_DIR, GIT_SSH, every GIT_TRACE*, GIT_CURL_VERBOSE, ...; K16, F7); redact() removes the
#       userinfo of adversarial URL shapes ('@' or a space inside a password, S-1; a password of 64, 128 or 512
#       characters, one holding '://' or '%40', X05), Authorization header values, known token shapes and
#       control characters; redact_url() redacts a configured URL holding a newline as ONE value; redact_report()
#       redacts report keys; a registered remote secret is removed from text that quotes it without its URL; an
#       argparse error that echoes a URL is redacted; proc_run_git refuses a forbidden
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
#   cm_sync_upstreams_ff_only.sh [--root <constitution-root>] [--print-sites]
#   --print-sites  print the call-site oracle (SITES) as TSV and exit 0, checking nothing: one line per site,
#                  FUNCTION<TAB>PREFIX<TAB>OK<TAB>WANT<TAB>ON128<TAB>ARGV, where PREFIX is the constant leading
#                  words of the argument list (a module-level list constant of the engine at --root is resolved,
#                  fetch_args(...) is "fetch"), OK the declared statuses joined by ',', WANT the shape name or '-',
#                  ON128 one of blind / failed / unreachable / start-dir. tests/sync/test_faults.sh uses it to know
#                  what an injected exit 128 must become at each call.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (reads two files; runs no git, no network; the runtime part calls proc_run_git only with a forbidden
#   shape and a non-existent git, which must be refused before any process exists; it calls the engine's main()
#   once with an unknown argument, which ends in the argument parser before anything else runs, and clears the
#   engine's in-memory secret registry after its own probe).
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
print_sites=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "${2:-/nonexistent}" 2>/dev/null && pwd)" || { echo "$GATE: BLIND — bad --root" >&2; exit 2; }; shift 2 ;;
    --print-sites) print_sites=1; shift ;;
    -h|--help) sed -n 2,103p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
engine="$root/scripts/sync/sync_all_upstreams.py"
wrapper="$root/scripts/sync/sync_all_upstreams.sh"
command -v python3 >/dev/null 2>&1 || { echo "$GATE: BLIND — python3 missing" >&2; exit 2; }
[ -r "$engine" ] || { echo "$GATE: BLIND — $engine unreadable" >&2; exit 2; }
python3 -I - "$engine" "$wrapper" "$GATE" "$print_sites" <<'PY'
import ast, contextlib, importlib.util, io, re, sys
engine, wrapper, gate, print_sites = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
fails = []
try:
    src = open(engine, encoding="utf-8").read()
    tree = ast.parse(src)
except Exception as e:  # unparseable engine: cannot decide
    print("%s: BLIND — cannot parse %s: %s" % (gate, engine, e)); sys.exit(2)

# ── the call-site oracle (check j). Written by hand from the engine's design, NOT generated from its AST: a change
#    of the engine that adds, moves or reshapes a git call FAILS until a person changes this table with it (and
#    records why in the class inventory). Columns: function, argument list as ast.unparse() text, declared answer
#    statuses, declared output shape ("-" for none), what an exit 128 becomes there.
SITES = [
    ("read_head", "['rev-parse', '--verify', '-q', 'HEAD^{commit}']", (0, 1), "SHA_RE", "blind"),
    ("is_ancestor", "['merge-base', '--is-ancestor', a, b]", (0, 1), "-", "blind"),
    ("count_range", "['rev-list', '--left-right', '--count', '%s...%s' % (a, b)]", (0,), "TWO_COUNTS_RE", "blind"),
    ("commit_present", "['rev-parse', '--verify', '-q', '%s^{commit}' % sha]", (0, 1), "SHA_RE", "blind"),
    ("probe_child", "['rev-parse', '--show-toplevel']", (0,), "ABS_PATH_RE", "blind"),
    ("index_gitlinks", "['ls-files', '-s', '-z']", (0,), "-", "blind"),
    ("head_gitlinks", "['ls-tree', '-r', '-z', 'HEAD']", (0,), "-", "blind"),
    ("inspect_local", "['symbolic-ref', '--short', '-q', 'HEAD']", (0, 1), "-", "blind"),
    ("inspect_local", "['rev-parse', '--absolute-git-dir', '--path-format=absolute', '--git-path', 'FETCH_HEAD']",
     (0,), "TWO_ABS_PATHS_RE", "blind"),
    ("inspect_local", "STATUS_ARGS", (0,), "-", "blind"),
    ("inspect_local", "['remote']", (0,), "-", "blind"),
    ("inspect_local", "['config', '--get', 'remote.%s.url' % n]", (0, 1), "-", "blind"),
    ("inspect_local", "['config', '--get', 'core.sshCommand']", (0, 1), "-", "blind"),
    ("fetch_repo", "fetch_args(rem['_name'], tags)", (0, 1, 128), "-", "unreachable"),
    ("evaluate_upstream", "['rev-parse', '--verify', '-q', 'refs/remotes/%s/%s^{commit}' % (rem['_name'], branch)]",
     (0, 1), "SHA_RE", "blind"),
    ("evaluate_pin", "['for-each-ref', '--contains', gitlink, '--format=%(refname)', 'refs/remotes']", (0,), "-",
     "blind"),
    ("write_git", "STATUS_ARGS", (0,), "-", "blind"),
    ("write_git", "['merge', '--ff-only', target]", (0, 1, 128), "-", "failed"),
    ("write_git", "['checkout', '--quiet', '--detach', target]", (0, 1, 128), "-", "failed"),
    ("write_git", "['add', '--', rec['path_in_parent']]", (0, 128), "-", "failed"),
    ("ignored_clobbers", "['ls-files', '-z', '--others', '--ignored', '--exclude-standard']", (0,), "-", "blind"),
    ("ignored_clobbers", "['ls-tree', '-r', '-z', '--name-only', '--full-tree', target]", (0,), "-", "blind"),
    ("control_needle", "['rev-list', '--count', 'HEAD']", (0,), "DIGITS_RE", "blind"),
    ("control_needle", "['rev-list', '--left-right', '--count', 'HEAD...HEAD']", (0,), "TWO_COUNTS_RE", "blind"),
    ("main", "['rev-parse', '--show-toplevel']", (0, 128), "ABS_PATH_RE", "start-dir"),
    ("main", "['rev-parse', '--path-format=absolute', '--git-common-dir']", (0,), "ABS_PATH_RE", "blind"),
]
ON128 = ("blind", "failed", "unreachable", "start-dir")
WRITE_VERBS = ("merge", "checkout", "add")


def argv_words(text, consts):
    """The constant leading words of an argument list given as source text; None when there is none."""
    try:
        node = ast.parse(text, mode="eval").body
    except SyntaxError:
        return None
    if isinstance(node, ast.Name):
        return consts.get(node.id)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "fetch_args":
        return ["fetch"]
    if isinstance(node, ast.List):
        words = []
        for e in node.elts:
            if not (isinstance(e, ast.Constant) and isinstance(e.value, str)):
                break
            words.append(e.value)
        return words or None
    return None


ENGINE_CONSTS = {}
for node in tree.body:
    if (isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)
            and isinstance(node.value, ast.List) and node.value.elts
            and all(isinstance(e, ast.Constant) and isinstance(e.value, str) for e in node.value.elts)):
        ENGINE_CONSTS[node.targets[0].id] = [e.value for e in node.value.elts]
if print_sites:
    for fn_, argv_, ok_, want_, on128_ in SITES:
        words = argv_words(argv_, ENGINE_CONSTS)
        print("\t".join((fn_, " ".join(words) if words else "?", ",".join(str(x) for x in ok_), want_, on128_, argv_)))
    sys.exit(0)
# the table's own consistency, before it is used as an oracle
for fn_, argv_, ok_, want_, on128_ in SITES:
    words = argv_words(argv_, {"STATUS_ARGS": ["status"]}) or []
    row = "%s %s" % (fn_, argv_)
    if on128_ not in ON128:
        fails.append("oracle row %s: unknown exit-128 class %s" % (row, on128_))
    if (on128_ == "blind") != (128 not in ok_):
        fails.append("oracle row %s: class %s does not match ok=%s (blind exactly when 128 is not declared)"
                     % (row, on128_, ok_))
    if on128_ == "failed" and not (fn_ == "write_git" and words[:1] and words[0] in WRITE_VERBS):
        fails.append("oracle row %s: 'failed' outside the merge / checkout / add of write_git" % row)
    if on128_ == "unreachable" and not (fn_ == "fetch_repo" and argv_.startswith("fetch_args(")):
        fails.append("oracle row %s: 'unreachable' outside fetch_args in fetch_repo" % row)
    if on128_ == "start-dir" and fn_ != "main":
        fails.append("oracle row %s: 'start-dir' outside main" % row)
    if 0 not in ok_ or not set(ok_) <= {0, 1, 128} or len(ok_) > 3 or list(ok_) != sorted(set(ok_)):
        fails.append("oracle row %s: ok=%s is not a sorted subset of {0, 1, 128} holding 0" % (row, ok_))


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
if len(kills) != 1:
    fails.append("expected exactly one os.killpg call, found %d" % len(kills))
elif pkg is not None:
    # §11.4.263, exact shape (review round 3, X04: `pgid > 1 or True` passed a "test contains pgid > 1" check)
    K = kills[0]
    pv = [x.arg for x in pkg.args.args]
    pv = pv[0] if len(pv) == 1 else None
    if pv is None:
        fails.append("proc_kill_group does not take exactly one parameter (the child process)")
    pb = [n for n in ast.walk(pkg) if "pgid" in bound_names(n)]
    want_bind = "pgid = os.getpgid(%s.pid)" % pv
    if len(pb) != 1 or not isinstance(pb[0], ast.Assign) or ast.unparse(pb[0]) != want_bind:
        fails.append("pgid is not bound exactly once, as `%s`, in proc_kill_group (§11.4.263)" % want_bind)
    if ast.unparse(K) != "os.killpg(pgid, signal.SIGKILL)":
        fails.append("the signal call is %s, not exactly os.killpg(pgid, signal.SIGKILL) (§11.4.263)" % ast.unparse(K))
    guard, cur = None, K
    while cur in parent:
        cur, child = parent[cur], cur
        if isinstance(cur, ast.If):
            guard = cur if child in cur.body else "else"
            break
        if not (isinstance(cur, ast.Expr) or (isinstance(cur, ast.Try) and child in cur.body)):
            guard = "a %s" % type(cur).__name__
            break
    terms = sorted(["isinstance(pgid, int)", "pgid > 1", "pgid == %s.pid" % pv])
    if not isinstance(guard, ast.If):
        fails.append("os.killpg is not in the body of an `if` (found %s before any `if`) (§11.4.263)" % guard)
    elif parent.get(guard) is not pkg:
        fails.append("the `if` guarding os.killpg is not a direct statement of proc_kill_group (§11.4.263)")
    elif not (isinstance(guard.test, ast.BoolOp) and isinstance(guard.test.op, ast.And)
              and sorted(ast.unparse(v) for v in guard.test.values) == terms):
        fails.append("the guard of os.killpg is `%s`, not exactly `%s` (§11.4.263)"
                     % (ast.unparse(guard.test), " and ".join(terms)))
if popens:
    snk = [k for k in popens[0].keywords if k.arg == "start_new_session"]
    if len(snk) != 1 or not (isinstance(snk[0].value, ast.Constant) and snk[0].value.value is True):
        fails.append("the one Popen does not pass start_new_session=True (the group it kills must be its own)")


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
found = []  # (function, argv text, ok, want) of every call site, for the oracle (check j)
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
    d_ = enclosing_def(node)
    site_fn = d_.name if isinstance(d_, (ast.FunctionDef, ast.AsyncFunctionDef)) else "<%s>" % type(d_).__name__
    a_text = ast.unparse(a) if a is not None else "<none>"
    lead = argv_words(a_text, {}) or []
    if isinstance(a, ast.Name) and a.id in LIST_CONSTS:
        lead = LIST_CONSTS[a.id]
    if lead[:1] and lead[0] in WRITE_VERBS and site_fn != "write_git":
        fails.append("git %s call at line %d is outside write_git, the one guarded writer" % (lead[0], node.lineno))
    if isinstance(a, ast.Call) and dotted(a.func) == "fetch_args" and site_fn != "fetch_repo":
        fails.append("fetch_args(...) is passed at line %d outside fetch_repo" % node.lineno)
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
    elif not set(okv) <= {0, 1, 128} or len(okv) > 3:
        fails.append("git call at line %d declares ok=%s: an answer set is a subset of {0, 1, 128} with at most three "
                     "values" % (node.lineno, tuple(okv)))
    if "want" in kw and not isinstance(kw["want"], ast.Name):
        fails.append("git call at line %d: want= is not a name" % node.lineno)
    found.append((site_fn, a_text, tuple(okv) if okv is not None else ast.unparse(okn) if okn is not None else "-",
                   ast.unparse(kw["want"]) if "want" in kw else "-"))
want_sites = sorted((f, a, tuple(o), w) for f, a, o, w, _ in SITES)
got_sites = sorted(found, key=repr)
for x in sorted(set(got_sites), key=repr):
    extra = got_sites.count(x) - want_sites.count(x)
    if extra > 0:
        fails.append("call site not in the oracle table (%dx): %s %s ok=%s want=%s" % ((extra,) + x))
for x in sorted(set(want_sites), key=repr):
    miss = want_sites.count(x) - got_sites.count(x)
    if miss > 0:
        fails.append("oracle row with no call site in the engine (%dx): %s %s ok=%s want=%s" % ((miss,) + x))

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
REQUIRED_KEYS = {c.split("=", 1)[0].lower() for c in REQUIRED_CFG}
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
    # every required key EXACTLY once (git compares config keys without case; a later pair overrides an earlier
    # one), with its required value, and no other key (review round 3, X07)
    keys = [c.split("=", 1)[0].lower() for c in cfg]
    missing = [c for c in REQUIRED_CFG if keys.count(c.split("=", 1)[0].lower()) != 1 or c not in cfg]
    other = sorted(set(c for c in cfg if c.split("=", 1)[0].lower() not in REQUIRED_KEYS))
    if argv[:3] != ["git", "-C", "/r"] or missing or other or argv[i:] != ["--no-optional-locks"] + list(a):
        fails.append("git_argv for git %s is not [git -C repo] + each safe -c pair exactly once + "
                     "--no-optional-locks + shape (missing, repeated or changed %s; unexpected %s): %s"
                     % (" ".join(a[:3]), missing, other, argv))
# the environment every git call runs with: no injected config or transport (K16)
INJECT = {"GIT_CONFIG_PARAMETERS": "'core.hooksPath'='/x'", "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.x",
          "GIT_CONFIG_VALUE_0": "y", "GIT_CONFIG_KEY_7": "a", "GIT_CONFIG_VALUE_7": "b", "GIT_DIR": "/x",
          "GIT_WORK_TREE": "/x", "GIT_SSH": "/x", "GIT_ASKPASS": "/x", "GIT_PROXY_COMMAND": "/x",
          "GIT_EXEC_PATH": "/x", "GIT_ALTERNATE_OBJECT_DIRECTORIES": "/x",
          # traces write protocol traffic, headers or URLs to a file or to stderr (review round 3, F7)
          "GIT_TRACE": "1", "GIT_TRACE2": "1", "GIT_TRACE2_EVENT": "/x", "GIT_TRACE2_PERF": "/x",
          "GIT_TRACE_PERFORMANCE": "1", "GIT_TRACE_PACKET": "1", "GIT_TRACE_CURL": "1", "GIT_TRACE_SETUP": "1",
          "GIT_CURL_VERBOSE": "1", "PATH": "/usr/bin"}
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
       ("esc \x1b[31mred\x1b[0m", ("\x1b",), "red"),
       # review round 3, X05 and its class: no fixed-width window; a secret holding '://' or '%40'
       ("fatal: unable to access 'https://user:" + "Q" * 64 + "@example.org/r.git/': 403", ("Q" * 8, "user"),
        "example.org"),
       ("https://user:" + "W" * 128 + "@example.org/r.git", ("W" * 8, "user"), "example.org"),
       ("https://user:" + "E" * 255 + "@x" + "E" * 255 + "@example.org/r.git", ("E" * 8,), "example.org"),
       ("https://user:pa://S3cr3tPw@example.org/r.git", ("S3cr3tPw", "user", "pa:"), "example.org"),
       ("https://user:ab%40Cd" + "Z" * 40 + "@example.org/r.git", ("Cd" + "Z" * 8, "%40"), "example.org"),
       ("< Authorization: Basic dXNlcjpzM2NyM3Q=", ("dXNlcjpzM2NyM3Q",), "Authorization:"),
       ("> proxy-authorization: Bearer tok3n-v4lue-xyz", ("tok3n-v4lue",), "authorization:")]
for text, gone, kept in RED:
    try:
        out = E.redact(text)
    except Exception as e:
        fails.append("redact raised: %s" % e); continue
    if any(g in out for g in gone) or kept not in out:
        fails.append("redact(%r) = %r (a secret remains or the host was lost)" % (text, out))
# the other paths a secret can take (review round 3, class D)
NL = "https://u:pa\nS3cr3tPwXY@example.org/r.git"
try:
    out = E.redact_url(NL)
    if "S3cr3tPwXY" in out or ":pa" in out or "example.org" not in out:
        fails.append("redact_url(%r) = %r (a configured URL with a newline is not one value)" % (NL, out))
except Exception as e:
    fails.append("redact_url not usable: %s" % e)
try:
    hits = []
    outr = E.redact_report({"https://u:S3cr3tKey9@h.example/x": {"ok": 1}}, "r", hits)
    if any("S3cr3tKey9" in k for k in outr) or not hits:
        fails.append("redact_report leaves a secret in a KEY or does not report it: %s %s" % (outr, hits))
except Exception as e:
    fails.append("redact_report not usable: %s" % e)
try:  # a secret git repeats WITHOUT its URL: removed once the remote URL was registered
    E.register_secret("https://u:RegS3cr3t77@h.example/x")
    out = E.redact("error: RegS3cr3t77 rejected by the server")
    if "RegS3cr3t77" in out:
        fails.append("a registered remote secret survives in text without its URL: %r" % out)
except Exception as e:
    fails.append("register_secret not usable: %s" % e)
finally:
    known = getattr(E, "_KNOWN", None)
    if hasattr(known, "clear"):
        known.clear()
buf = io.StringIO()
try:  # argparse prints an unknown argument back; a URL in it must come out redacted
    with contextlib.redirect_stderr(buf), contextlib.redirect_stdout(buf):
        try:
            E.main(["--check", "https://u:ArgS3cr3t55@example.org/x"])
        except SystemExit:
            pass
    if "ArgS3cr3t55" in buf.getvalue():
        fails.append("an argument-parser error prints a secret: %r" % buf.getvalue()[-200:])
except Exception as e:
    fails.append("main() with an unknown argument raised %s" % type(e).__name__)
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
      "%d git call sites (plus the g_out forwarder) with literal allow-listed argv and bounded answer statuses, "
      "equal to the %d-row call-site oracle; %d accepted shapes carry the exact safe argv (each safe key once); "
      "git_env scrubs %d injectors; %d redaction shapes + 4 secret paths; %d/%d forbidden shapes refused; "
      "control needle %d/%d accepted" % (gate, len(found), len(SITES), accepted, len(INJECT) - 1, len(RED),
                                          refused, len(REFUSE), accepted, len(ACCEPT)))
PY
