#!/usr/bin/env python3
"""class_inventory_names_r13.py -- review round 13 copy (unchanged rules; it loads class_inventory_r13.py, which also
resolves named and built vectors, instead of the round-12 refs inventory) of the round-12 copy of the round-11 (RV10-1 / RV10-2) class inventory: every place the engine
scripts/sync/sync_all_upstreams.py DERIVES a branch, ref, remote, path or other name from git OUTPUT or from a
PARAMETER, and every place such a name is USED in a path, lock, marker or comparison. Read on the AST, never by
grep. Closed world: every git call site (r.run / g_out with a list-literal argument vector) and every sink (os.path.join,
str.format, '%' formatting with a ref or path template, a == / != / in comparison with a name) found here must be in
CLASSIFIED below with the validation that makes it safe; an unclassified site FAILs the run, a classified site that is
no longer there FAILs too (stale row). Control needles (section 11.4.273): the known RV9-1 sink
'n.format(branch=branch)' in lock_paths and the RV10-1 source 'symbolic-ref' in read_branch must be found; the
fabricated subcommand 'frobnicate' must not.
Round 12 (RV11-1): the round-11 copy classed the evaluate_upstream rev-parse site as safe because its TEXT was a
full ref. A full ref is not exact (git's lookup rules fall back to refs/tags/<name> and refs/heads/<name>), so a
classification by text cannot make a name-resolving site safe: semantic check 3 runs the ref-resolution classifier of
class_inventory_refs.py over every git site and FAILs on any LOOKUP, whatever row the site has here.
Usage: class_inventory_names.py <engine.py>   Exit: 0 PASS, 1 FAIL, 2 BLIND."""
import ast
import sys
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

# (function, kind, key) -> how the derived value is made safe before it reaches a path, lock or comparison
CLASSIFIED = {
    # SOURCES: git output read as a name
    ("read_branch", "git", "symbolic-ref"): "FULL ref only (-q HEAD; --short refused by check_git_args); refs/heads/ "
        "stripped by branch_of_ref(); name checked by valid_branch_name(); case kept (RV10-1, RV10-2)",
    ("inspect_local", "git", "remote"): "each name checked by safe_remote() before any use; invalid -> state invalid-name",
    ("inspect_local", "git", "rev-parse"): "three absolute paths, one per line (THREE_ABS_PATHS_RE), else unknown git dir",
    ("inspect_local", "git", "config"): "remote.<name>.url / core.sshCommand: values, never used in a path",
    ("inspect_local", "git", "status"): "porcelain listing: dirty or not, never a name",
    ("read_head", "git", "rev-parse"): "SHA_RE",
    ("is_ancestor", "git", "merge-base"): "exit code only; objects named by obj() (exact)",
    ("count_range", "git", "rev-list"): "TWO_COUNTS_RE; objects named by obj() (exact)",
    ("commit_present", "git", "rev-parse"): "SHA_RE; the object named by obj() (exact)",
    ("probe_child", "git", "rev-parse"): "ABS_PATH_RE",
    ("index_gitlinks", "git", "ls-files"): "-z records; paths checked by safe_relpath() where used",
    ("head_gitlinks", "git", "ls-tree"): "-z records; paths checked by safe_relpath() where used",
    ("tree_gitlinks", "git", "ls-tree"): "-z records; paths checked by safe_relpath() where used",
    ("update_strategies", "git", "config"): "-z records keyed by submodule path; values lower-cased words",
    ("write_settled", "git", "ls-files"): "byte comparison with the pre-write listing",
    ("fetch_repo", "git", "fetch"): "remote name from safe_remote(); refspec fixed by fetch_args()",
    ("resolve_ref_exact", "git", "for-each-ref"): "the one ref-name lookup: rows kept only when refname == ref "
        "(exact), ids SHA_RE, peeled to a commit or None; malformed or duplicate -> no answer (RV11-1)",
    ("evaluate_pin", "git", "for-each-ref"): "full refnames compared EXACTLY with refs/remotes/<remote>/<branch>; "
        "the gitlink named by obj()",
    ("write_git", "git", "merge"): "write: target named by obj() (exact)",
    ("write_git", "git", "checkout"): "write: target named by obj() (exact; a branch named <hex> cannot win)",
    ("write_git", "git", "add"): "write: path_in_parent checked by safe_relpath()",
    ("write_git", "git", "status"): "porcelain listing: dirty or not",
    ("ignored_clobbers", "git", "ls-files"): "-z paths compared as strings, never joined",
    ("ignored_clobbers", "git", "ls-tree"): "-z paths compared as strings, never joined",
    ("control_needle", "git", "rev-list"): "DIGITS_RE / TWO_COUNTS_RE",
    ("main", "git", "rev-parse"): "ABS_PATH_RE (common dir of the run lock)",
    # SINKS: a name put into a path, lock or ref
    ("lock_paths", "sink", "format:branch"): "branch from read_branch() (valid_branch_name) only; case kept",
    ("lock_paths", "sink", "join"): "git dir / common dir: absolute paths from rev-parse; names are fixed constants",
    ("in_progress", "sink", "join"): "fixed operation names joined to the absolute git dir",
    ("marker_path", "sink", "join"): "fixed WRITE_MARKER joined to the absolute git dir",
    ("fetch_args", "sink", "percent:refs/remotes/"): "remote from safe_remote(); the whole vector is re-checked by check_git_args()",
    ("evaluate_upstream", "sink", "percent:refs/remotes/"): "safe_remote() + valid_branch_name() (--branch); the ref "
        "is handed to resolve_ref_exact() only",
    ("evaluate_pin", "sink", "percent:refs/remotes/"): "safe_remote() + valid_branch_name() (--branch)",
    ("inspect_local", "sink", "percent:remote."): "config key of a safe_remote() name",
    ("probe_child", "sink", "join"): "fixed '.git' joined to a child path that walk() checked (safe_relpath, inside parent)",
    ("discover", "sink", "join"): "gitlink path joined to the parent; probed or walked ONLY when safe_relpath() and the "
        "outside-parent check pass (RV4-13, RV4-15)",
    ("walk", "sink", "join"): "same site as discover (walk is nested in discover)",
    ("main", "sink", "join"): "fixed names (.git, the cache dir, the run lock, evidence file names) joined to an "
        "absolute path: --root's toplevel, XDG_CACHE_HOME / ~/.cache, --out, the common dir",
    ("lock_repositories", "sink", "join"): "fixed run-lock name joined to a realpath'd common dir",
    ("tsv_rows", "sink", "percent:/"): "report text (counts 'ahead/behind'); remote name already redacted, no path",
    ("run", "sink", "percent:/"): "recovery hint TEXT for the operator (a command line to copy), never opened or run",
    ("run", "sink", "join"): "fixed names (post_update_hook.sh, Constitution.md, the report files) joined to absolute paths",
    ("ignored_clobbers", "git", "ls-files"): "-z paths compared as strings, never joined",
}
SUBCOMMANDS = None


def git_sites(tree):
    out = []
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        for c in ast.walk(fn):
            if not isinstance(c, ast.Call):
                continue
            f = c.func
            name = f.attr if isinstance(f, ast.Attribute) else f.id if isinstance(f, ast.Name) else None
            if name not in ("run", "g_out") or len(c.args) < 3 if name == "g_out" else len(c.args) < 2:
                continue
            vec = c.args[2] if name == "g_out" else c.args[1]
            sub = None
            if isinstance(vec, ast.List) and vec.elts and isinstance(vec.elts[0], ast.Constant):
                sub = vec.elts[0].value
            elif isinstance(vec, ast.Name) and vec.id == "STATUS_ARGS":
                sub = "status"
            elif isinstance(vec, ast.Call) and getattr(vec.func, "id", "") == "fetch_args":
                sub = "fetch"
            if sub is not None:
                out.append((fn.name, "git", sub, c.lineno))
    return out


def sink_sites(tree):
    out = []
    for fn in [n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]:
        for c in ast.walk(fn):
            if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute):
                if c.func.attr == "format" and any(k.arg == "branch" for k in c.keywords):
                    out.append((fn.name, "sink", "format:branch", c.lineno))
                if c.func.attr == "join" and isinstance(c.func.value, ast.Attribute) and c.func.value.attr == "path":
                    out.append((fn.name, "sink", "join", c.lineno))
            if isinstance(c, ast.BinOp) and isinstance(c.op, ast.Mod) and isinstance(c.left, ast.Constant) \
                    and isinstance(c.left.value, str):
                for pre in ("refs/remotes/", "refs/heads/", "refs/", "remote.", "/"):
                    if pre in c.left.value:  # anywhere in the template ('+refs/heads/*:refs/remotes/%s/*' too)
                        out.append((fn.name, "sink", "percent:" + pre, c.lineno))
                        break
    return out


def semantic_checks(tree):
    """The two properties round 10 lacked, read on the AST (a FAIL each names what is wrong):
    1. read_branch asks for the FULL ref: its symbolic-ref vector is exactly ['symbolic-ref', '-q', 'HEAD'] and the
       body calls branch_of_ref() (RV10-1);
    2. the {branch} of lock_paths is the parameter itself, unmodified (no .lower(), no call, no constant; RV10-2)."""
    fails = []
    fns = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    rb = fns.get("read_branch")
    vecs = [c.args[1] for c in ast.walk(rb) if isinstance(c, ast.Call) and getattr(c.func, "attr", "") == "run"] if rb else []
    lits = [[e.value for e in v.elts if isinstance(e, ast.Constant)] for v in vecs if isinstance(v, ast.List)]
    if lits != [["symbolic-ref", "-q", "HEAD"]]:
        fails.append("read_branch symbolic-ref vector is %r, not ['symbolic-ref', '-q', 'HEAD']" % (lits,))
    if not rb or not any(isinstance(c, ast.Call) and getattr(c.func, "id", "") == "branch_of_ref" for c in ast.walk(rb)):
        fails.append("read_branch does not call branch_of_ref()")
    lp = fns.get("lock_paths")
    kws = [k.value for c in ast.walk(lp) if isinstance(c, ast.Call) and getattr(c.func, "attr", "") == "format"
           for k in c.keywords if k.arg == "branch"] if lp else []
    if len(kws) != 1 or not (isinstance(kws[0], ast.Name) and kws[0].id == "branch"):
        fails.append("lock_paths {branch} is not the parameter 'branch' unmodified: %s"
                     % [ast.dump(k) for k in kws])
    # 3. round 12: no site resolves a name by git's lookup rules (a full ref is not exact)
    import importlib.util as _u
    import os as _os
    spec = _u.spec_from_file_location("refs_inv", _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),
                                                                "class_inventory_r13.py"))
    ri = _u.module_from_spec(spec)
    spec.loader.exec_module(ri)
    ri.load_vectors(tree)
    for f, s, ln, cls, txt in ri.sites(tree):
        if "LOOKUP" in cls:
            fails.append("%s line %d: git %s resolves a name by git's lookup rules (not exact): %s" % (f, ln, s, txt))
    return fails


def main(argv):
    if len(argv) != 1:
        print("usage: class_inventory_names_r13.py <engine.py>", file=sys.stderr)
        return 2
    src = open(argv[0], encoding="utf-8").read()
    tree = ast.parse(src)
    sites = git_sites(tree) + sink_sites(tree)
    keys = {(f, k, s) for f, k, s, _ in sites}
    # control needles
    if ("lock_paths", "sink", "format:branch") not in keys or ("read_branch", "git", "symbolic-ref") not in keys:
        print("class-inventory-names: BLIND - a known site was not found (instrument cannot see)")
        return 2
    if any(s == "frobnicate" for _, _, s in keys):
        print("class-inventory-names: BLIND - the fabricated needle matched")
        return 2
    fail = 0
    for f, k, s, line in sorted(sites, key=lambda x: x[3]):
        cls = CLASSIFIED.get((f, k, s))
        print("%s\t%s\t%s\t%s\tline %d\t%s" % ("OK" if cls else "UNCLASSIFIED", f, k, s, line, cls or "-"))
        fail += cls is None
    for msg in semantic_checks(tree):
        print("SEMANTIC-FAIL\t%s" % msg)
        fail += 1
    stale = sorted(set(CLASSIFIED) - keys)
    for row in stale:
        print("STALE\t%s\t%s\t%s" % row)
    print("class-inventory-names: %s - sites=%d classified-keys=%d unclassified=%d stale=%d"
          % ("PASS" if not fail and not stale else "FAIL", len(sites), len(keys), fail, len(stale)))
    return 0 if not fail and not stale else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
