#!/usr/bin/env bash
# cm_sync_upstreams_ff_only.sh — CM-SYNC-UPSTREAMS-FF-ONLY gate (§11.4.113, §11.4.84, §11.4.10, §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# scripts/sync/sync_all_upstreams.py fetches every remote of a project tree and integrates ONLY by
# fast-forward. This gate checks, on the engine file itself, that every git process it can start went
# through check_git_args and carries the safe configuration, and that the argument shapes it accepts
# cannot push, force, rewrite or delete:
#   (1) STATIC (Python AST, the file is never imported for this part):
#       a. IMPORT ALLOW-LIST: only `import <m>` of argparse, concurrent.futures, datetime, fcntl, hashlib,
#          json, os, re, shutil, signal, subprocess, sys, threading, time; no `from` import, no alias, no
#          import below module level;
#       b. ATTRIBUTE ALLOW-LIST: every use of an imported module is one exact dotted name from a fixed list
#          (os.path.join, subprocess.Popen, ...); a bare module name (an alias, a module passed on) is
#          refused, so os.system, subprocess.call, sys.modules, ... cannot appear in any spelling;
#       c. NO DYNAMIC ACCESS: no getattr / setattr / delattr / eval / exec / compile / __import__ /
#          globals / vars / locals / breakpoint / __builtins__ name, no dunder attribute, no dunder name
#          except __name__, no definition that shadows a module or one of those names;
#       d. exactly ONE subprocess.Popen, inside Runner.run, whose argv is `cmd`, assigned once before it
#          from git_argv(...), with no shell / executable / preexec_fn; Runner.run calls check_git_args
#          before it; os.killpg appears only in kill_own_group, which guards `pgid > 1` (§11.4.263);
#       e. every git call site (`<x>.run(repo, ARGS)` and `g_out(r, repo, ARGS)`) passes a literal list
#          whose first element is an allow-listed subcommand, or fetch_args(...); only g_out forwards its
#          own parameter;
#       f. WRITE_SUBCOMMANDS is exactly {fetch, merge, checkout, add}; no allow-list holds push, reset,
#          rebase, commit, clean, gc, update-ref, branch, tag, submodule, pull, stash, ...
#   (2) RUNTIME (the engine module is loaded from the file): git_argv(...) carries every required safe
#       -c pair (core.hooksPath=/dev/null, core.fsmonitor=false, fetch.prune=false, ...) before the
#       subcommand; fetch_args(...) is --no-prune --no-prune-tags --no-tags --refmap= with only the
#       engine-owned refspec(s); check_git_args REFUSES every forbidden shape (push, reset --hard, merge
#       --ff / --no-ff / --squash, a mirror or other-namespace refspec, a forced tag refspec, --prune,
#       --force, ext::, ...) and ACCEPTS every shape the engine really uses (the control needle, §11.4.273).
#   (3) the wrapper scripts/sync/sync_all_upstreams.sh execs the engine with `python3 -I`.
# What it does NOT prove (§11.4.6): that git itself honours the flags, that a user-configured clean or
# smudge filter or a diff driver cannot run, or that the engine's decisions are right (tests/sync/*).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_sync_upstreams_ff_only.sh [--root <constitution-root>]
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (reads two files; runs no git, no network).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, python3 (absent -> BLIND).
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.113, §11.4.84, §11.4.201, §11.4.273, §1.1 (paired mutation:
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
    -h|--help) sed -n 2,53p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
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
           "signal", "subprocess", "sys", "threading", "time"}
ALLOW = {"argparse.ArgumentParser", "concurrent.futures.ThreadPoolExecutor", "datetime.datetime.now",
         "datetime.timezone.utc", "fcntl.LOCK_EX", "fcntl.LOCK_NB", "fcntl.flock", "hashlib.sha256", "json.dumps",
         "os.O_CREAT", "os.O_NOCTTY", "os.O_NOFOLLOW", "os.O_RDWR", "os.close", "os.cpu_count", "os.environ",
         "os.environ.get", "os.fsync", "os.getcwd", "os.getpgid", "os.getpid", "os.killpg", "os.makedirs",
         "os.open", "os.path.basename", "os.path.exists", "os.path.expanduser", "os.path.isabs", "os.path.isdir",
         "os.path.isfile", "os.path.join", "os.path.lexists", "os.path.realpath", "os.read", "os.replace",
         "os.sep", "os.write", "re.compile", "re.match", "shutil.which", "signal.SIGKILL", "subprocess.DEVNULL",
         "subprocess.PIPE", "subprocess.Popen", "subprocess.TimeoutExpired", "sys.argv", "sys.exit", "sys.stderr",
         "threading.Lock", "time.monotonic"}
BANNED_NAMES = {"getattr", "setattr", "delattr", "eval", "exec", "compile", "__import__", "globals", "vars",
                "locals", "breakpoint", "__builtins__", "importlib", "builtins"}
parent = {}
for p_ in ast.walk(tree):
    for c in ast.iter_child_nodes(p_):
        parent[c] = p_
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
            if not isinstance(node.ctx, ast.Load) or ".".join(chain) not in ALLOW:
                fails.append("module use %s is not on the allow-list (line %d)" % (".".join(chain), node.lineno))
    elif isinstance(node, ast.Attribute) and node.attr.startswith("__"):
        fails.append("dunder attribute .%s (line %d)" % (node.attr, node.lineno))
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.arg, ast.alias)):
        nm = node.arg if isinstance(node, ast.arg) else (node.asname if isinstance(node, ast.alias) else node.name)
        if nm and isinstance(node, ast.alias):
            continue  # an alias is reported by the import rule above
        if nm in roots or nm in BANNED_NAMES:
            fails.append("definition shadows %s (line %d)" % (nm, node.lineno))


def fn(name, cls=None):
    body = tree.body
    if cls:
        c = [n for n in body if isinstance(n, ast.ClassDef) and n.name == cls]
        body = c[0].body if c else []
    f = [n for n in body if isinstance(n, ast.FunctionDef) and n.name == name]
    return f[0] if f else None


runner_run, g_out_fn, kog = fn("run", "Runner"), fn("g_out"), fn("kill_own_group")
if runner_run is None:
    fails.append("Runner.run not found")
popens = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and dotted(n.func) == "subprocess.Popen"]
if len(popens) != 1:
    fails.append("expected exactly one subprocess.Popen, found %d" % len(popens))
elif runner_run is not None:
    P = popens[0]
    if not (runner_run.lineno <= P.lineno <= runner_run.end_lineno):
        fails.append("the only Popen (line %d) is not inside Runner.run" % P.lineno)
    bad_kw = sorted(str(k.arg) for k in P.keywords if k.arg in (None, "shell", "executable", "preexec_fn", "args"))
    if bad_kw:
        fails.append("Popen uses %s" % bad_kw)
    first = P.args[0] if P.args else None
    def bound_names(n):  # every name a statement or expression (re)binds
        if isinstance(n, ast.Assign):
            tg = n.targets
        elif isinstance(n, (ast.AugAssign, ast.AnnAssign, ast.NamedExpr, ast.For, ast.comprehension)):
            tg = [n.target]
        elif isinstance(n, ast.With):
            tg = [i.optional_vars for i in n.items if i.optional_vars is not None]
        elif isinstance(n, ast.ExceptHandler):
            return {n.name} if n.name else set()
        else:
            return set()
        return {x.id for t in tg for x in ast.walk(t) if isinstance(x, ast.Name)}
    assigns = [n for n in ast.walk(runner_run) if "cmd" in bound_names(n)]
    ok_cmd = (isinstance(first, ast.Name) and first.id == "cmd" and len(assigns) == 1
              and isinstance(assigns[0], ast.Assign) and isinstance(assigns[0].value, ast.Call)
              and dotted(assigns[0].value.func) == "git_argv" and assigns[0].lineno < P.lineno)
    if not ok_cmd:
        fails.append("Popen's argv is not `cmd = git_argv(...)` assigned once before it")
    checks = [n.lineno for n in ast.walk(runner_run) if isinstance(n, ast.Call) and dotted(n.func) == "check_git_args"]
    if not checks or min(checks) > P.lineno:
        fails.append("Runner.run does not call check_git_args before Popen")
killpgs = [n.lineno for n in ast.walk(tree) if isinstance(n, ast.Call) and dotted(n.func) == "os.killpg"]
if kog is None or any(not (kog.lineno <= ln <= kog.end_lineno) for ln in killpgs):
    fails.append("os.killpg used outside kill_own_group")


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
       "fsck", "repack", "reflog", "init", "clone"}
if r is None:
    fails.append("READ_SUBCOMMANDS is not a literal set")
else:
    leak = sorted((r | (w or set())) & BAD)
    if leak:
        fails.append("allow-list contains %s" % leak)
SUBS = (r or set()) | (w or set())
sites = 0
for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue
    if isinstance(node.func, ast.Attribute) and node.func.attr == "run":
        a = node.args[1] if len(node.args) > 1 else None
    elif isinstance(node.func, ast.Name) and node.func.id == "g_out":
        a = node.args[2] if len(node.args) > 2 else None
    else:
        continue
    sites += 1
    inside_g_out = g_out_fn is not None and g_out_fn.lineno <= node.lineno <= g_out_fn.end_lineno
    if isinstance(a, ast.Name) and inside_g_out and a.id in [x.arg for x in g_out_fn.args.args]:
        continue
    if isinstance(a, ast.Call) and dotted(a.func) == "fetch_args":
        continue
    if (isinstance(a, ast.List) and a.elts and isinstance(a.elts[0], ast.Constant) and a.elts[0].value in SUBS
            and not any(isinstance(e, ast.Starred) for e in a.elts)):
        continue
    fails.append("git call at line %d does not pass a literal allow-listed argument list" % node.lineno)


def has_pgid_gt1(fn_):  # a real comparison node, never a docstring/comment carrier (§11.4.201(7)(a))
    for n in ast.walk(fn_):
        if (isinstance(n, ast.Compare) and isinstance(n.left, ast.Name) and n.left.id == "pgid" and len(n.ops) == 1
                and isinstance(n.ops[0], ast.Gt) and isinstance(n.comparators[0], ast.Constant)
                and n.comparators[0].value == 1):
            return True
    return False


if not kog or not has_pgid_gt1(kog):
    fails.append("kill_own_group lacks the `pgid > 1` guard (§11.4.263)")

# runtime table
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
    argv = E.git_argv("git", "/r", ["status"])
    cfg = [argv[i + 1] for i in range(len(argv) - 1) if argv[i] == "-c"]
    missing = [c for c in REQUIRED_CFG if c not in cfg]
    if missing:
        fails.append("git_argv lacks the safe -c pairs %s" % missing)
    if argv[-1] != "status" or argv[:3] != ["git", "-C", "/r"]:
        fails.append("git_argv does not end with the subcommand: %s" % argv)
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
    print("%s: BLIND — git_argv/fetch_args not callable: %s" % (gate, e))
    sys.exit(2)


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
          ["merge-base", "--is-ancestor", "+x", S], []]
ACCEPT = [FA, FT,
          ["merge", "--ff-only", S], ["checkout", "--quiet", "--detach", S], ["add", "--", "libs/a"],
          ["rev-parse", "HEAD"], ["ls-files", "-s", "-z"], ["symbolic-ref", "--short", "-q", "HEAD"],
          ["config", "--get", "remote.origin.url"], ["remote"], ["cat-file", "-e", S + "^{commit}"],
          ["merge-base", "--is-ancestor", S, S], ["rev-list", "--left-right", "--count", S + "..." + S],
          ["status", "--porcelain=v1", "--ignore-submodules=all", "--untracked-files=normal"],
          ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"],
          ["for-each-ref", "--contains", S, "--format=%(refname)", "refs/remotes"]]
for a in REFUSE:
    try:
        E.check_git_args(a)
        fails.append("ACCEPTED a forbidden shape: git %s" % " ".join(a))
    except E.GitRefused:
        pass
accepted = 0
for a in ACCEPT:
    try:
        E.check_git_args(a); accepted += 1
    except E.GitRefused as e:
        fails.append("control needle: REFUSED a shape the engine uses: git %s (%s)" % (" ".join(a), e))
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
print("%s: PASS — imports and module attributes on the allow-list, no dynamic access; 1 Popen (cmd from "
      "git_argv, check_git_args first); %d git call sites with literal allow-listed argv; safe -c pairs present; "
      "%d forbidden shapes refused; control needle %d/%d accepted" % (gate, sites, len(REFUSE), accepted, len(ACCEPT)))
PY
