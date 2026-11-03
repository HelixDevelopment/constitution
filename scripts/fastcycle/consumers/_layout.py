"""_layout.py - the constitution checkout paths for the consumer tools.

Purpose: one place (for the Python consumer tools: _enumerate_impl.py,
audit.py) that knows where a consumer keeps the constitution: the standard
`submodules/constitution` first, then the legacy `constitution`. The list is
READ from the ONE layout resolver, scripts/lib/constitution_layout.sh
(CONSTITUTION_LAYOUT_RELS), so it can never drift from the shell scripts.
Fails loudly (exit 2) when that file is unreadable -- never a silently
narrowed probe set (§11.4.201(6)).
Also owns the ambient-git-environment scrub (round 8): GIT_DIR / GIT_WORK_TREE /
GIT_INDEX_FILE & co. choose WHICH repository `git -C <path>` reads (GIT_DIR beats
-C), so every consumer tool calls scrub_git_env() before its first git call. The
variable list is READ from the same file (CL_GIT_SCRUB_VARS), never copied.
Usage: from _layout import LAYOUT_RELS, local_gitlink, scrub_git_env
Tests: tests/layout/test_fastcycle_layout.sh
"""
import os
import re
import subprocess
import sys

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib", "constitution_layout.sh")


def layout_rels(lib=_LIB):
    try:
        with open(lib, "r", encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r'^CONSTITUTION_LAYOUT_RELS="([^"]+)"\s*$', line)
                if m:
                    return tuple(m.group(1).split())
    except OSError:
        pass
    print("consumers/_layout.py: cannot read CONSTITUTION_LAYOUT_RELS from %s" % lib, file=sys.stderr)
    sys.exit(2)


LAYOUT_RELS = layout_rels()


def git_scrub_vars(lib=_LIB):
    try:
        with open(lib, "r", encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r'^CL_GIT_SCRUB_VARS="([^"]+)"\s*$', line)
                if m:
                    return tuple(m.group(1).split())
    except OSError:
        pass
    print("consumers/_layout.py: cannot read CL_GIT_SCRUB_VARS from %s" % lib, file=sys.stderr)
    sys.exit(2)


GIT_SCRUB_VARS = git_scrub_vars()


def scrub_git_env(notice=True):
    """Drop every ambient repository-locating GIT_* variable from os.environ
    (unset-and-proceed); one stderr notice names them (never their values)."""
    dropped = [v for v in GIT_SCRUB_VARS if v in os.environ]
    for v in dropped:
        del os.environ[v]
    if dropped and notice:
        print("[constitution] NOTICE: ignoring the ambient git environment (%s): "
              "the repository is discovered from the path, never from these variables." % " ".join(dropped),
              file=sys.stderr)
    return dropped


def git_env():
    """A copy of os.environ without the repository-locating GIT_* variables
    (for a direct subprocess call that runs before / without scrub_git_env)."""
    return {k: v for k, v in os.environ.items() if k not in GIT_SCRUB_VARS}


def local_gitlink(checkout, timeout=5):
    """Return (rel, sha) of the first layout holding a gitlink at HEAD in a
    local checkout, or (None, None)."""
    for rel in LAYOUT_RELS:
        try:
            proc = subprocess.run(
                ["git", "-C", checkout, "ls-tree", "HEAD", "--", rel],
                capture_output=True, text=True, timeout=timeout, env=git_env(),
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if proc.returncode == 0 and "160000 commit" in proc.stdout:
            parts = proc.stdout.split()
            if len(parts) >= 3:
                return rel, parts[2]
    return None, None
