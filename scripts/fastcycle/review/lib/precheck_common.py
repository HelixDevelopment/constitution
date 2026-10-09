#!/usr/bin/env python3
"""precheck_common.py - the ONE shared definition of the primitives that the
pre-check gate (lib/precheck_pack_run.py) and the pack builder / dispatch
verifier (lib/precheck_pack_build_run.py) must agree on byte-for-byte
(F13: no duplicated copies that can drift).

  _DIFF_PIN / _change_diff_argv  the exact `git diff` argv a change_id is the
                                 sha256 of (builder writes it, gate and
                                 verifier recompute it);
  _git_env                       GIT_* stripped, system + global config off, no prompt;
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


def _git_env():
    """GIT_* stripped, system AND global (~/.gitconfig, $XDG_CONFIG_HOME/git/config)
    configuration neutralised (M6), no prompt."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


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
