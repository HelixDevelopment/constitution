#!/usr/bin/env python3
"""precheck_pack_build_run.py - real implementation behind
review/precheck_pack_build.sh, the one-shot convenience wrapper that
automates the manual slicer.py + precheck_pack.sh sequence a human/agent
otherwise repeats by hand every review round (spec-004 "fast-dev-cycles";
RB-001/RB-002 per contracts/review-batch-and-precheck.md). This is
precheck_pack_build.sh's OWN internal library (house pattern:
gates/io_trace.sh -> gates/lib/io_trace_parse.py; review/precheck_pack.sh
-> review/lib/precheck_pack_run.py) -- invoked ONLY by that thin POSIX sh
dispatcher, never called directly by a contract-facing caller.

Two subcommands, both operating on real data only (constitution 11.4.6 --
nothing fabricated):

  prepare --repo <const-root> --base <ref> --head <ref>
          --paths-file <file, one changed path per line>
          --scratch <dir> --logic-group <name>
      For every changed path: computes the REAL `git diff <base> <head> --
      <path>` content, writes it verbatim to
      <scratch>/changes/NNNN.diff, and writes a sibling
      <scratch>/changes/NNNN.json change descriptor whose `change_id` is
      the REAL sha256 of those exact diff bytes (the same verification
      review/slicer.py's own load_change() performs on load -- computed
      here with the identical hashlib.sha256(bytes).hexdigest() primitive,
      so a descriptor this tool writes always passes slicer.py's own
      content-address check). `lines_changed` is the real count of lines
      in the diff beginning with '+' or '-', excluding the `+++`/`---`
      file-header lines (never a guessed/fabricated line count). Also
      writes <scratch>/config.yaml mapping every changed path to the one
      given --logic-group (review/slicer.py's own --config contract:
      a top-level `components: {<path>: <logic group>}` mapping; RB-001
      DEC-06 "shared logic group, feature, or defect class" -- this
      wrapper's default behaviour per its own CLI contract is "all
      changed paths of ONE commit/range share one logic group", with
      --logic-group as the caller's override). Prints, to stdout, two
      lines a POSIX sh caller can parse without eval:
          DESCRIPTORS=<comma-joined absolute paths to each *.json descriptor>
          CONFIG=<absolute path to config.yaml>
      Exit: 0 on success; 2 on a usage/IO error (unreadable --paths-file,
      --repo not a git worktree, a `git diff` invocation itself failing);
      a `git diff` that runs but returns an empty (unchanged) result for a
      declared path is NOT an error (DEC: a path present in --paths-file
      but genuinely unchanged between base/head is a caller bug, not this
      tool's to silently paper over -- it still gets a real, empty-diff
      descriptor with lines_changed=0, never dropped: RB-001 "batching
      never drops a change" extended to this wrapper's own intake step).

  emit --out-dir <dir> [--validate-only]
      Reads <dir>/precheck.json (schema-checked: "schema" ==
      "precheck/v1", "batch_id" present and not the literal "UNKNOWN",
      "all_pass" a real bool) and, unless --validate-only, prints the
      EXACT two marker lines scripts/hooks/review_dispatch_guard.sh's own
      documented RB-002 convention requires on a review dispatch's
      description, so a caller can copy them verbatim:
          PRECHECK-PACK: <dir>/precheck.json
          BATCH-ID: <batch_id>
      Exit: 0 if the pack is schema-valid AND all_pass is true (dispatch-
      ready); 1 if schema-valid but all_pass is false (produced, but not
      yet dispatch-ready -- the real precheck_pack.sh exit-code
      convention, contracts/review-batch-and-precheck.md "Exit codes");
      3 if <dir>/precheck.json is missing, unreadable, or fails the
      schema check (an honest "no usable pack here" signal, distinct from
      both 0 and 1, matching this project's own other tools' convention
      of a distinct exit code for "no honest verdict" rather than folding
      it into a generic 2 -- review/precheck_pack_run.py's own
      --determinism-check uses exit 4 for exactly this shape of
      distinction). --validate-only suppresses the marker-line stdout
      (used by the sh dispatcher's idempotent-cache-check path, which
      must not print a possibly-stale marker before the cache is
      confirmed trustworthy).

Decoupling (11.4.28/11.4.177): this file carries no project literal
beyond its own house-pattern paths; every repo/path/commit value is a
caller-supplied argument.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

SCHEMA = "precheck/v1"


def _write_bytes(path, data):
    out_dir = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def _lines_changed_of(diff_bytes):
    """Real count of changed lines in a unified diff: every line starting
    with '+' or '-' EXCLUDING the '+++'/'---' file-header lines. Decoded
    permissively (errors="replace") so a binary-file diff (which carries
    no +/- hunk lines at all -- git emits a single "Binary files ... and
    ... differ" line) never crashes this tool; it legitimately counts 0,
    never a fabricated non-zero guess."""
    text = diff_bytes.decode("utf-8", errors="replace")
    count = 0
    for line in text.splitlines():
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+") or line.startswith("-"):
            count += 1
    return count


def cmd_prepare(a):
    if not os.path.isdir(a.repo):
        print("precheck_pack_build: --repo is not a directory: %s" % a.repo, file=sys.stderr)
        return 2
    try:
        with open(a.paths_file, encoding="utf-8") as fh:
            paths = [ln.rstrip("\n") for ln in fh if ln.strip()]
    except OSError as exc:
        print("precheck_pack_build: cannot read --paths-file %s: %s" % (a.paths_file, exc), file=sys.stderr)
        return 2
    if not paths:
        print("precheck_pack_build: --paths-file names zero changed paths -- nothing to prepare",
              file=sys.stderr)
        return 2

    changes_dir = os.path.join(a.scratch, "changes")
    os.makedirs(changes_dir, exist_ok=True)

    descriptor_paths = []
    for i, path in enumerate(paths, start=1):
        try:
            proc = subprocess.run(
                ["git", "-C", a.repo, "diff", "--no-color", a.base, a.head, "--", path],
                capture_output=True, timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            print("precheck_pack_build: real `git diff` for %r failed to run: %s" % (path, exc),
                  file=sys.stderr)
            return 2
        if proc.returncode != 0:
            # `git diff <a> <b> -- <path>` (no --exit-code) returns 0 regardless of
            # whether a difference was found -- real, empirically confirmed on this
            # host (`git diff HEAD~1 HEAD -- <real file>` and `git diff HEAD HEAD --
            # <real file>` both exit 0); only a genuine git-level error (e.g. a bad
            # ref) returns non-zero (128). A non-zero exit here is therefore always a
            # real error this tool must not silently swallow into a fabricated empty
            # descriptor -- never "no differences".
            print("precheck_pack_build: real `git diff` for %r exited %d: %s"
                  % (path, proc.returncode, (proc.stderr or b"").decode("utf-8", errors="replace")),
                  file=sys.stderr)
            return 2
        diff_bytes = proc.stdout

        diff_name = "%04d.diff" % i
        json_name = "%04d.json" % i
        diff_path = os.path.join(changes_dir, diff_name)
        json_path = os.path.join(changes_dir, json_name)
        _write_bytes(diff_path, diff_bytes)

        change_id = "sha256:" + hashlib.sha256(diff_bytes).hexdigest()
        descriptor = {
            "change_id": change_id,
            "path": path,
            "diff": diff_name,
            "lines_changed": _lines_changed_of(diff_bytes),
        }
        with open(json_path, "w", encoding="utf-8") as fh:
            json.dump(descriptor, fh, sort_keys=True)
            fh.write("\n")
        descriptor_paths.append(os.path.abspath(json_path))

    # review/slicer.py's --config contract (its own module docstring): a YAML
    # mapping `components: {<changed path>: <logic group>}`. Every key is
    # written via json.dumps() -- a valid YAML double-quoted scalar for ANY
    # string content (colons, quotes, leading dashes, unicode all handled
    # correctly), never a hand-rolled YAML-escaping guess.
    config_path = os.path.join(a.scratch, "config.yaml")
    lines = ["components:"]
    for path in paths:
        lines.append("  %s: %s" % (json.dumps(path), json.dumps(a.logic_group)))
    with open(config_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print("DESCRIPTORS=%s" % ",".join(descriptor_paths))
    print("CONFIG=%s" % os.path.abspath(config_path))
    return 0


def cmd_emit(a):
    path = os.path.join(a.out_dir, "precheck.json")
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        print("precheck_pack_build: no usable pack at %s: %s" % (path, exc), file=sys.stderr)
        return 3
    if not isinstance(doc, dict):
        print("precheck_pack_build: %s is not a JSON object" % path, file=sys.stderr)
        return 3
    if doc.get("schema") != SCHEMA:
        print("precheck_pack_build: %s has schema=%r, want %r"
              % (path, doc.get("schema"), SCHEMA), file=sys.stderr)
        return 3
    batch_id = doc.get("batch_id")
    if not isinstance(batch_id, str) or not batch_id or batch_id == "UNKNOWN":
        print("precheck_pack_build: %s carries no genuine batch_id (got %r)"
              % (path, batch_id), file=sys.stderr)
        return 3
    all_pass = doc.get("all_pass")
    if not isinstance(all_pass, bool):
        print("precheck_pack_build: %s has a non-boolean all_pass (got %r)"
              % (path, all_pass), file=sys.stderr)
        return 3

    if not a.validate_only:
        print("PRECHECK-PACK: %s" % os.path.abspath(path))
        print("BATCH-ID: %s" % batch_id)

    return 0 if all_pass else 1


def main(argv):
    p = argparse.ArgumentParser(prog="precheck_pack_build_run")
    sub = p.add_subparsers(dest="cmd", required=True)

    pp = sub.add_parser("prepare")
    pp.add_argument("--repo", required=True)
    pp.add_argument("--base", required=True)
    pp.add_argument("--head", required=True)
    pp.add_argument("--paths-file", required=True)
    pp.add_argument("--scratch", required=True)
    pp.add_argument("--logic-group", required=True)
    pp.set_defaults(func=cmd_prepare)

    pe = sub.add_parser("emit")
    pe.add_argument("--out-dir", required=True)
    pe.add_argument("--validate-only", action="store_true")
    pe.set_defaults(func=cmd_emit)

    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    try:
        return a.func(a)
    except Exception as exc:  # an internal error is never a finding -- refuse honestly
        print("precheck_pack_build: internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
