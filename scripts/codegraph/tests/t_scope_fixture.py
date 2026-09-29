#!/usr/bin/env python3
# ============================================================================
# t_scope_fixture.py — builds the fixture git super-repo used by the scope tests
# ============================================================================
# Purpose      A faithful miniature of a real multi-submodule project: REAL git
#              submodules (local bare remotes, cloned + initialised recursively,
#              so the runner's `git ls-files --recurse-submodules` sees them
#              exactly as in production), whose working-tree .gitmodules URLs
#              are then rewritten to hosted-org form so ownership is derivable.
#              Planted: own-org submodule with a NESTED third-party submodule,
#              a top-level third-party submodule, secret-class source files,
#              a qa-results corpus, and owned source under a built-in-skipped
#              `build/` dir that needs a .gitignore negation.
# Usage        python3 t_scope_fixture.py <dest_dir>   (prints the super-repo path)
#              or import: build(dest) -> dict
# Inputs       none (all content synthetic)
# Outputs      <dest>/super (the project root), <dest>/remotes/* (bare repos),
#              <dest>/super/codegraph.scope.yaml (the fixture scope, count unset)
# Side effects creates <dest>; never touches any other path.
# Dependencies git >= 2.38 (protocol.file.allow), python3
# Cross-refs   t_scope_cases.py, run_scope_tests.sh
# ============================================================================
import os
import shutil
import subprocess
import sys

GITENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
              GIT_COMMITTER_EMAIL="t@t", GIT_AUTHOR_DATE="2026-01-01T00:00:00Z",
              GIT_COMMITTER_DATE="2026-01-01T00:00:00Z", GIT_CONFIG_NOSYSTEM="1",
              HOME=os.environ.get("HOME", "/tmp"))


def git(cwd, *args):
    return subprocess.run(["git", "-c", "protocol.file.allow=always", "-c", "init.defaultBranch=main",
                           *args], cwd=cwd, env=GITENV, check=True, capture_output=True, text=True).stdout


def write(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def make_repo(path, files):
    os.makedirs(path)
    git(path, "init", "-q")
    for rel, text in files.items():
        write(path, rel, text)
    git(path, "add", "-A")
    git(path, "commit", "-qm", "init")


def bare_from(src, bare):
    git(os.path.dirname(bare), "clone", "-q", "--bare", src, bare)


SCOPE_YAML = """schema_version: 1
runner: {config_filename: codegraph.json, dist_dir: ""}
own_orgs:
  hosts: [github.com]
  orgs: [OwnOrg]
submodule_class_overrides: {}
baseline_excludes:
  build_outputs: ["/out/"]
  caches: ["**/__pycache__/"]
  secrets: [".env", "*.env", "*secret*", "!*secret*/", "**/secrets/"]
  qa_corpora: ["**/qa-results/"]
project_excludes: ["/rubbish/"]
pathological_excludes: []
reinclude_negations: ["/build/"]
include_patterns: ["/app/vend/gen/"]
forbidden_classes:
  - {name: secrets_dir, regex: '(^|/)secrets/', positive: 'x/secrets/a.py', negative: 'x/secretsauce/a.py'}
  - {name: secret_basename, regex: '(?i)(^|/)[^/]*secret[^/]*$', positive: 'a/api_Secret.py', negative: 'a/secure.py'}
  - {name: qa_corpus, regex: '(^|/)qa-results/', positive: 'd/qa-results/r.py', negative: 'd/qa_resultsx/r.py'}
enumeration_controls:
  present: ["src/main.c"]
  fabricated: ["__helix_scope_fabricated_needle__/none.c"]
accepted_count: __COUNT__
tolerance_pct: 0
"""


def build(dest, count="0"):
    dest = os.path.abspath(dest)
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(os.path.join(dest, "src_repos"))
    os.makedirs(os.path.join(dest, "remotes"))
    sr, rm = os.path.join(dest, "src_repos"), os.path.join(dest, "remotes")
    # third-party repo nested inside the own-org submodule
    make_repo(os.path.join(sr, "tp_nested"), {"tp.c": "int tp_nested(void){return 0;}\n"})
    bare_from(os.path.join(sr, "tp_nested"), os.path.join(rm, "tp_nested.git"))
    # top-level third-party submodule
    make_repo(os.path.join(sr, "tp_top"), {"t.c": "int tp_top(void){return 0;}\n",
                                           "sub/u.py": "def u():\n    return 1\n"})
    bare_from(os.path.join(sr, "tp_top"), os.path.join(rm, "tp_top.git"))
    # own-org submodule that itself has a third-party submodule
    own = os.path.join(sr, "own_sub")
    make_repo(own, {"lib.c": "int own_lib(void){return 0;}\n"})
    git(own, "submodule", "add", "-q", os.path.join(rm, "tp_nested.git"), "vendored_tp")
    git(own, "commit", "-qm", "add nested tp")
    bare_from(own, os.path.join(rm, "own_sub.git"))
    # the super-repo (project root)
    sup = os.path.join(dest, "super")
    make_repo(sup, {
        "src/main.c": "int main(void){return 0;}\n",
        "src/util.py": "def util():\n    return 2\n",
        "build/tool.c": "int build_tool(void){return 0;}\n",          # built-in skip, owned
        "scripts/secrets/creds.py": "TOKEN_SHAPE = 'placeholder'\n",  # secrets dir (source ext)
        "app/api_secret.py": "def s():\n    return None\n",           # *secret* basename
        "app/secretmgr/impl.py": "def impl():\n    return 3\n",       # *secret* DIR — must stay
        "qa-results/run1/check.py": "def c():\n    return 4\n",        # qa corpus
        "rubbish/gen.c": "int gen(void){return 0;}\n",                 # project exclude
        "app/vend/keep.py": "def keep():\n    return 5\n",             # visible sibling of the nested-ignored dir
        "app/vend/.gitignore": "/gen/\n",                              # NESTED .gitignore hiding app/vend/gen
        ".gitignore": "# fixture root gitignore\n*.tmp\n",
    })
    git(sup, "submodule", "add", "-q", os.path.join(rm, "own_sub.git"), "own_sub")
    git(sup, "submodule", "add", "-q", os.path.join(rm, "tp_top.git"), "tp_top")
    git(sup, "commit", "-qm", "add submodules")
    git(sup, "submodule", "update", "--init", "--recursive", "-q")
    write(sup, "app/vend/gen/g.py", "def g():\n    return 6\n")            # source under a nested-.gitignore'd dir
    # rewrite working-tree .gitmodules URLs to hosted-org form (ownership source)
    git(sup, "config", "-f", ".gitmodules", "submodule.own_sub.url", "git@github.com:OwnOrg/own_sub.git")
    git(sup, "config", "-f", ".gitmodules", "submodule.tp_top.url", "https://github.com/someone/tp_top.git")
    git(os.path.join(sup, "own_sub"), "config", "-f", ".gitmodules", "submodule.vendored_tp.url",
        "git@github.com:ThirdParty/tp_nested.git")
    write(sup, "codegraph.scope.yaml", SCOPE_YAML.replace("__COUNT__", str(count)))
    return {"root": sup, "scope": os.path.join(sup, "codegraph.scope.yaml")}


if __name__ == "__main__":
    print(build(sys.argv[1])["root"])
