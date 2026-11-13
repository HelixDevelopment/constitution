#!/usr/bin/env bash
# cm_sync_upstreams_ff_only.sh — CM-SYNC-UPSTREAMS-FF-ONLY gate (§11.4.113, §11.4.84, §11.4.10, §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# scripts/sync/sync_all_upstreams.py fetches every remote of a project tree and integrates ONLY by
# fast-forward. This gate proves, on the engine file itself, that it cannot do anything else:
#   (1) STATIC (Python AST, the file is never imported for this part):
#       a. exactly ONE process-spawning call in the whole file — subprocess.Popen inside Runner.run —
#          and no os.system / os.popen / os.exec* / os.spawn* / subprocess.run|call|check_* / pty;
#       b. inside Runner.run, check_git_args(...) is called BEFORE that Popen;
#       c. WRITE_SUBCOMMANDS is exactly {fetch, merge, checkout, add}; neither allow-list contains
#          push, reset, rebase, commit, clean, gc, update-ref, filter-branch, branch, tag, submodule,
#          pull, stash, restore, switch or worktree;
#       d. kill_own_group refuses a pgid <= 1 (the literal guard `pgid > 1` is present, §11.4.263).
#   (2) RUNTIME (the engine module is loaded from the file and its check_git_args is called on a fixed
#       table): every forbidden shape (push, reset --hard, rebase, commit, fetch +refspec, fetch --force,
#       merge without --ff-only, merge -s ours, checkout -f, ext:: transport, --upload-pack=, add -A,
#       config writes, remote add, ...) is REFUSED; every shape the engine really uses is ACCEPTED (the
#       control needle, §11.4.273: a gate that refuses everything proves nothing).
#   (3) the wrapper scripts/sync/sync_all_upstreams.sh execs the engine with `python3 -I`.
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
    -h|--help) sed -n 2,38p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
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

SPAWN = re.compile(r"^(subprocess\.(Popen|run|call|check_call|check_output|getoutput|getstatusoutput)|"
                   r"os\.(system|popen|exec\w*|spawn\w*|posix_spawn\w*|fork\w*)|pty\.\w+|asyncio\.create_subprocess_\w+)$")
spawns = []
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and SPAWN.match(dotted(node.func)):
        spawns.append((dotted(node.func), node.lineno))
for node in ast.walk(tree):
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        names = [a.name for a in node.names] + ([node.module] if isinstance(node, ast.ImportFrom) and node.module else [])
        for n in names:
            if n and (n == "pty" or n.startswith("asyncio") or n in ("Popen", "system", "run")):
                fails.append("forbidden import %s (line %d)" % (n, node.lineno))

runner_run = None
for node in ast.walk(tree):
    if isinstance(node, ast.ClassDef) and node.name == "Runner":
        for f in node.body:
            if isinstance(f, ast.FunctionDef) and f.name == "run":
                runner_run = f
if runner_run is None:
    fails.append("Runner.run not found")
if len(spawns) != 1 or spawns[0][0] != "subprocess.Popen":
    fails.append("expected exactly one process spawn (subprocess.Popen), found %s" % spawns)
elif runner_run is not None and not (runner_run.lineno <= spawns[0][1] <= runner_run.end_lineno):
    fails.append("the only Popen (line %d) is not inside Runner.run" % spawns[0][1])
if runner_run is not None and spawns:
    checks = [n.lineno for n in ast.walk(runner_run) if isinstance(n, ast.Call) and dotted(n.func) == "check_git_args"]
    if not checks or min(checks) > spawns[0][1]:
        fails.append("Runner.run does not call check_git_args before Popen")

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
       "cherry-pick", "revert", "replace", "notes", "send-pack", "receive-pack", "upload-pack"}
if r is None:
    fails.append("READ_SUBCOMMANDS is not a literal set")
else:
    leak = sorted((r | (w or set())) & BAD)
    if leak:
        fails.append("allow-list contains %s" % leak)
kog = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "kill_own_group"]
def has_pgid_gt1(fn):  # a real comparison node, never a docstring/comment carrier (§11.4.201(7)(a))
    for n in ast.walk(fn):
        if (isinstance(n, ast.Compare) and isinstance(n.left, ast.Name) and n.left.id == "pgid" and len(n.ops) == 1
                and isinstance(n.ops[0], ast.Gt) and isinstance(n.comparators[0], ast.Constant) and n.comparators[0].value == 1):
            return True
    return False
if not kog or not has_pgid_gt1(kog[0]):
    fails.append("kill_own_group lacks the `pgid > 1` guard (§11.4.263)")

# runtime table
try:
    spec = importlib.util.spec_from_file_location("sync_engine_gate", engine)
    E = importlib.util.module_from_spec(spec); spec.loader.exec_module(E)
except Exception as e:
    print("%s: BLIND — cannot load %s: %s" % (gate, engine, e)); sys.exit(2)
S = "0123456789abcdef0123456789abcdef01234567"
REFUSE = [["push", "origin", "main"], ["reset", "--hard", S], ["rebase", "origin/main"], ["commit", "-m", "x"],
          ["fetch", "--prune", "--no-recurse-submodules", "--", "origin", "+refs/heads/*:refs/heads/*"],
          ["fetch", "--prune", "--no-recurse-submodules", "--force", "--", "origin"],
          ["fetch", "origin"], ["fetch", "--prune", "--no-recurse-submodules", "--upload-pack=sh", "--", "origin"],
          ["fetch", "--prune", "--no-recurse-submodules", "--", "ext::sh -c x"],
          ["merge", S], ["merge", "--ff-only", "-s", "ours", S], ["merge", "--no-ff", S], ["merge", "--ff-only", "origin/main"],
          ["checkout", "-f", S], ["checkout", "--quiet", "--detach", "--force", S], ["checkout", "main"],
          ["add", "-A"], ["add", "--", "../x"], ["add", "--", "."], ["config", "core.hooksPath", "/x"],
          ["config", "--unset", "x"], ["remote", "add", "x", "y"], ["remote", "set-url", "o", "u"],
          ["symbolic-ref", "HEAD", "refs/heads/x"], ["update-ref", "refs/heads/main", S], ["branch", "-f", "main", S],
          ["submodule", "update", "--force"], ["clean", "-fdx"], ["stash"], ["status", "--force"],
          ["rev-parse", "--git-dir=/x"], ["rev-parse", "x\ny"], ["rev-parse", "+refs/heads/main"],
          ["merge-base", "--is-ancestor", "+x", S], []]
ACCEPT = [["fetch", "--prune", "--no-recurse-submodules", "--", "origin"],
          ["fetch", "--prune", "--no-recurse-submodules", "--tags", "--", "github_helix"],
          ["merge", "--ff-only", S], ["checkout", "--quiet", "--detach", S], ["add", "--", "libs/a"],
          ["rev-parse", "HEAD"], ["ls-files", "-s", "-z"], ["symbolic-ref", "--short", "-q", "HEAD"],
          ["config", "--get", "remote.origin.url"], ["remote"], ["cat-file", "-e", S + "^{commit}"],
          ["merge-base", "--is-ancestor", S, S], ["rev-list", "--left-right", "--count", S + "..." + S],
          ["status", "--porcelain=v1", "--ignore-submodules=all", "--untracked-files=normal"],
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
print("%s: PASS — 1 spawn site guarded by check_git_args; write allow-list {add, checkout, fetch, merge}; "
      "%d forbidden shapes refused; control needle %d/%d accepted" % (gate, len(REFUSE), accepted, len(ACCEPT)))
PY
