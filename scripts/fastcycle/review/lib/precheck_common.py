#!/usr/bin/env python3
"""precheck_common.py - the ONE shared definition of the primitives that the
pre-check gate (lib/precheck_pack_run.py) and the pack builder / dispatch
verifier (lib/precheck_pack_build_run.py) must agree on byte-for-byte
(F13: no duplicated copies that can drift).

  _DIFF_PIN / _change_diff_argv  the exact `git diff` argv a change_id is the
                                 sha256 of (builder writes it, gate and
                                 verifier recompute it);
  _git_env(repo)                 env for git against a GATE-OWNED copy of repo's git dir (H2);
  _canon / _body_hash_of         canonical JSON + body_hash (run_meta and
                                 body_hash excluded);
  gate_version                   sha256 over the gate's own source files, so a
                                 pack built by different gate logic is stale;
  EMPTY_TREE                     git's well-known empty-tree id;
  CANONICAL_EXCEPTIONS_REL       the one legacy-exception TSV path of a bound run.

Imported by both libraries via their own directory (never installed, never a
project literal -- constitution 11.4.28/11.4.177).
"""
import hashlib
import json
import os

EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
# The ONE legacy-exception TSV path a bound run may use (gate decides; verifier recomputes).
CANONICAL_EXCEPTIONS_REL = "config/shellcheck_legacy_exceptions.tsv"
_EXCLUDED = ("run_meta", "body_hash")
_HERE = os.path.dirname(os.path.abspath(__file__))
# The files whose bytes define "the gate": the check library and this module.
GATE_FILES = (os.path.join(_HERE, "precheck_pack_run.py"), os.path.abspath(__file__))

# M6: every diff-output-shaping config key a repo-local .git/config could still set is pinned
# here (global + system config are neutralised by _git_env).
_DIFF_PIN = ["-c", "core.quotePath=false", "-c", "diff.noprefix=false", "-c", "diff.mnemonicPrefix=false",
             "-c", "diff.relative=false", "-c", "diff.external=", "-c", "color.diff=false",
             "-c", "diff.algorithm=myers", "-c", "diff.indentHeuristic=true", "-c", "diff.interHunkContext=0",
             "-c", "diff.context=3", "-c", "diff.submodule=short", "-c", "diff.ignoreSubmodules=none",
             "-c", "diff.suppressBlankEmpty=false"]


def _change_diff_argv(repo, base, head, path):
    return (["git", "--literal-pathspecs", "-C", repo] + _DIFF_PIN +
            ["diff", "--no-color", "--no-textconv", "--no-ext-diff", "--no-renames", base, head, "--", path])


# r13 (ATM-1217 review H2): every git call of the gate and the builder runs against a GATE-OWNED git dir.
# Pinning keys of the producer's own config (the r12 approach) cannot be complete: any key that names a program
# (filter.*, gpg.program with log.showSignature, alternateRefsCommand, include/includeIf, ...) and any
# $GIT_DIR/info/attributes line is read from the producer repository. The gate therefore never lets git read the
# producer's git dir as a repository: it copies the DATA git needs (HEAD, refs, packed-refs, shallow, the index and
# its split-index files) into a fresh temporary directory, writes its own minimal config there, borrows the
# objects read-only through objects/info/alternates, and runs git with GIT_DIR/GIT_WORK_TREE pointing at it and an
# environment built from nothing (PATH only), system and global config off. The producer's config, hooks,
# info/attributes, info/exclude and config.worktree are never opened by git. Only cmd_snapshot WRITES objects; it
# writes them into the producer's object store (GIT_OBJECT_DIRECTORY), as the r12 code did through -C.
_GATE_PINS = (("core.fsmonitor", "false"), ("core.hooksPath", os.devnull), ("commit.gpgSign", "false"),
              ("diff.external", ""), ("core.pager", "cat"), ("core.attributesFile", os.devnull))
_OK_EXTENSIONS = ("objectformat", "worktreeconfig", "preciousobjects", "noop")
_GATE_DIRS = {}       # realpath(producer git dir) -> (gate git dir, toplevel, common dir)
_BAD_GIT_DIR = os.path.join(os.sep, "nonexistent", "precheck-gate-git-dir")


class GateGitError(Exception):
    pass


def _read_gitfile(dotgit):
    with open(dotgit, "rb") as fh:
        line = fh.read(4096).split(b"\n", 1)[0].strip()
    if not line.startswith(b"gitdir:"):
        raise GateGitError("%s is not a gitdir: file" % dotgit)
    target = os.fsdecode(line[len(b"gitdir:"):].strip())
    return target if os.path.isabs(target) else os.path.join(os.path.dirname(dotgit), target)


def toplevel(path):
    """The work-tree toplevel containing `path` (the first ancestor holding a .git entry), computed WITHOUT
    running git; None when there is none. Does not stop at file-system boundaries or ceiling directories."""
    cur = os.path.abspath(path)
    while True:
        if os.path.lexists(os.path.join(cur, ".git")):
            return cur
        up = os.path.dirname(cur)
        if up == cur:
            return None
        cur = up


def _resolve(path):
    """-> (git dir, common dir, toplevel) of the work tree containing `path`, read as data (never run git)."""
    top = toplevel(path)
    if top is None:
        raise GateGitError("not inside a git work tree: %s" % path)
    dotgit = os.path.join(top, ".git")
    gd = _read_gitfile(dotgit) if os.path.isfile(dotgit) and not os.path.islink(dotgit) else dotgit
    gd = os.path.realpath(gd)
    if not os.path.isfile(os.path.join(gd, "HEAD")):
        raise GateGitError("no HEAD in %s" % gd)
    common = gd
    cfile = os.path.join(gd, "commondir")
    if os.path.isfile(cfile):
        with open(cfile, "rb") as fh:
            c = os.fsdecode(fh.read(4096).strip())
        common = os.path.realpath(c if os.path.isabs(c) else os.path.join(gd, c))
    if not os.path.isdir(os.path.join(common, "objects")):
        raise GateGitError("no objects directory in %s" % common)
    return gd, common, top


def _extensions(common):
    """[extensions] keys of the producer config, parsed as text (no include is followed, nothing is run)."""
    out, sect = {}, ""
    try:
        with open(os.path.join(common, "config"), "rb") as fh:
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return out
    for ln in lines:
        t = ln.strip()
        if t.startswith("["):
            sect = t[1:t.find("]")].strip().lower() if "]" in t else ""
            continue
        if sect == "extensions" and "=" in t and not t.startswith(("#", ";")):
            k, v = t.split("=", 1)
            out[k.strip().lower()] = v.strip().strip('"').lower()
    return out


def make_gate_git_dir(repo, dest):
    """Populate the empty directory `dest` as a gate-owned git dir for the work tree containing `repo`.
    Returns (toplevel, common dir). Raises GateGitError (fail closed) on an unsupported layout."""
    import shutil
    gd, common, top = _resolve(repo)
    ext = _extensions(common)
    bad = sorted(k for k in ext if k not in _OK_EXTENSIONS)
    if bad:
        raise GateGitError("unsupported repository extension(s) %s in %s" % (", ".join(bad), common))
    if os.path.exists(os.path.join(common, "reftable")):
        raise GateGitError("reftable repositories are not supported: %s" % common)
    if os.listdir(dest):
        raise GateGitError("gate git dir is not empty: %s" % dest)
    cfg = ["[core]", "\trepositoryformatversion = %d" % (1 if "objectformat" in ext else 0), "\tbare = false",
           "\tfilemode = true", "\tlogallrefupdates = false"]
    if "objectformat" in ext:
        cfg += ["[extensions]", "\tobjectformat = %s" % ext["objectformat"]]
    with open(os.path.join(dest, "config"), "w") as fh:
        fh.write("\n".join(cfg) + "\n")
    shutil.copyfile(os.path.join(gd, "HEAD"), os.path.join(dest, "HEAD"))
    if os.path.isdir(os.path.join(common, "refs")):
        shutil.copytree(os.path.join(common, "refs"), os.path.join(dest, "refs"), symlinks=False)
    else:
        os.makedirs(os.path.join(dest, "refs", "heads"))
    for name in ("packed-refs", "shallow"):
        src = os.path.join(common, name)
        if os.path.isfile(src):
            shutil.copyfile(src, os.path.join(dest, name))
    for name in os.listdir(gd):
        if name == "index" or name.startswith("sharedindex."):
            shutil.copyfile(os.path.join(gd, name), os.path.join(dest, name))
    os.makedirs(os.path.join(dest, "objects", "info"))
    os.makedirs(os.path.join(dest, "objects", "pack"))
    with open(os.path.join(dest, "objects", "info", "alternates"), "w") as fh:
        fh.write(os.path.join(common, "objects") + "\n")
    return top, common


def base_git_env():
    """An environment built from nothing: PATH, system + global config off, no prompt, the empty tree as
    attribute source, and the r12 pins as a belt (they also win over the gate dir's own config)."""
    env = {"PATH": os.environ.get("PATH", os.defpath), "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
           "GIT_TERMINAL_PROMPT": "0", "GIT_ATTR_SOURCE": EMPTY_TREE}
    env["GIT_CONFIG_COUNT"] = str(len(_GATE_PINS))
    for i, (k, v) in enumerate(_GATE_PINS):
        env["GIT_CONFIG_KEY_%d" % i] = k
        env["GIT_CONFIG_VALUE_%d" % i] = v
    return env


def gate_git_info(repo):
    """(gate git dir, toplevel, common dir) for `repo`, created once per process and removed at exit."""
    import atexit
    import shutil
    import tempfile
    gd, _common, _top = _resolve(repo)
    hit = _GATE_DIRS.get(gd)
    if hit:
        return hit
    dest = tempfile.mkdtemp(prefix="precheck-gate-git.")
    atexit.register(shutil.rmtree, dest, True)
    top, common = make_gate_git_dir(repo, dest)
    _GATE_DIRS[gd] = (dest, top, common)
    return _GATE_DIRS[gd]


def _git_env(repo, write_objects=False):
    """Environment for `git -C repo ...`: GIT_DIR = the gate-owned copy, GIT_WORK_TREE = the toplevel. A path
    that is not a supported git work tree gets a GIT_DIR that does not exist, so git fails (exit 128) and the
    caller's error path runs -- never a silent fall-back to the producer's own git dir."""
    env = base_git_env()
    try:
        gdir, top, common = gate_git_info(repo)
    except (GateGitError, OSError):
        env["GIT_DIR"] = _BAD_GIT_DIR
        return env
    env["GIT_DIR"] = gdir
    env["GIT_WORK_TREE"] = top
    if write_objects:
        env["GIT_OBJECT_DIRECTORY"] = os.path.join(common, "objects")
    return env


def _main(argv):
    """CLI for precheck_pack_build.sh: `toplevel PATH` | `make-git-dir --repo PATH --dir EMPTY_DIR`."""
    if len(argv) == 2 and argv[0] == "toplevel":
        t = toplevel(argv[1])
        if t is None:
            return 1
        print(t)
        return 0
    if len(argv) == 5 and argv[0] == "make-git-dir" and argv[1] == "--repo" and argv[3] == "--dir":
        try:
            make_gate_git_dir(argv[2], argv[4])
        except (GateGitError, OSError) as exc:
            print("precheck_common: %s" % exc, file=__import__("sys").stderr)
            return 2
        return 0
    print("usage: precheck_common.py toplevel PATH | make-git-dir --repo PATH --dir EMPTY_DIR",
          file=__import__("sys").stderr)
    return 64


EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"  # sha1 of the empty tree (sha1 repositories; see the guide)


def _canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _body_hash_of(doc):
    body = {k: v for k, v in doc.items() if k not in _EXCLUDED}
    return hashlib.sha256(_canon(body).encode("utf-8")).hexdigest()


def gate_version():
    """sha256 over the gate source files (name-tagged, fixed order)."""
    h = hashlib.sha256()
    for path in GATE_FILES:
        with open(path, "rb") as fh:
            data = fh.read()
        h.update(os.path.basename(path).encode("utf-8") + b"\0" + str(len(data)).encode("ascii") + b"\0" + data)
    return h.hexdigest()


if __name__ == "__main__":
    raise SystemExit(_main(__import__("sys").argv[1:]))
