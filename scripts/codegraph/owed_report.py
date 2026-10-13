#!/usr/bin/env python3
"""owed_report.py — generated, state-independent report of which governed indexing tools still lack tests or a guide.

Purpose      The constitution states the RULE "a tool lacking its own tests or its §11.4.18 guide MUST NOT be pointed at a live
             index" but never enumerates WHICH tools currently lack them: any prose list goes stale the day a test or guide
             lands (a measured defect — the enumeration said "none exists yet" while three guides existed). This tool
             derives the answer from the tree on every run, so the rule text stays true without being edited.
Usage        owed_report.py [--root <constitution dir>] [--json] [--strict]
Inputs       --root   constitution submodule root (default: two levels above this script)
Outputs      text table (default) or --json on stdout. Exit 0 = report produced (informational), 1 = --strict and >=1 tool owes
             something, 3 = REFUSED (root unreadable, or NO tool discovered — a blind scan must never read as "nothing owed",
             §11.4.201(6)), 2 = usage.
Side effects none (read-only)
Dependencies python3 (stdlib only)
Cross-refs   test_owed_report.py, test_owed_report_mutations.sh, docs/scripts/owed_report.md, §11.4.18, §11.4.201, §11.4.224, §11.4.273

Definitions (all boundaries are exact, so a substring can never count — §11.4.273 negative control):
  tool         scripts/codegraph/*.{sh,py,js}, scripts/codegraph/runner_patches/*.py (minus __init__/common), scripts/lumen/*.{sh,py}
  tested       a file in <tooldir>/tests (fixtures/ and __pycache__ excluded) that is named test_<stem>[_mutate|_mutations].<ext>
               or t_<stem>.<ext>, OR whose text contains the tool's exact file name (runner patches: the patch id) bounded by
               non-identifier characters
  guide        docs/scripts/<stem>.md (or <name>.md)
"""
import argparse, json, os, re, sys

CODE_EXT = (".sh", ".py", ".js")
TEST_EXT = (".sh", ".py", ".js", ".bats")
PATCH_SKIP = {"__init__.py", "common.py"}


def refuse(msg):
    print("REFUSED: " + msg, file=sys.stderr)
    sys.exit(3)


def list_files(d, exts):
    try:
        return sorted(f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f)) and f.endswith(exts))
    except OSError:
        return []


def discover(root):
    tools = []
    cg, lu = os.path.join(root, "scripts", "codegraph"), os.path.join(root, "scripts", "lumen")
    for f in list_files(cg, CODE_EXT):
        tools.append(("scripts/codegraph/" + f, "tool", "scripts/codegraph"))
    for f in list_files(os.path.join(cg, "runner_patches"), (".py",)):
        if f not in PATCH_SKIP:
            tools.append(("scripts/codegraph/runner_patches/" + f, "runner_patch", "scripts/codegraph"))
    for f in list_files(lu, (".sh", ".py")):
        tools.append(("scripts/lumen/" + f, "tool", "scripts/lumen"))
    return sorted(tools)


def read_tests(root, tooldir):
    """[(relpath, text)] for the test files of one tool directory (fixtures and caches excluded)."""
    out, base = [], os.path.join(root, tooldir, "tests")
    for dp, dns, fns in os.walk(base):
        dns[:] = sorted(d for d in dns if d not in ("fixtures", "__pycache__"))
        for f in sorted(fns):
            if not f.endswith(TEST_EXT):
                continue
            p = os.path.join(dp, f)
            try:
                with open(p, encoding="utf-8") as fh:
                    text = fh.read()
            except (OSError, UnicodeDecodeError):
                continue
            out.append((os.path.relpath(p, root).replace(os.sep, "/"), text))
    return out


def token_re(token, is_filename):
    # bounded by non-identifier characters on both sides; a filename is additionally not followed by ".<alnum>" (c_tool.js.bak)
    tail = r"(?![A-Za-z0-9_]|\.[A-Za-z0-9])" if is_filename else r"(?![A-Za-z0-9_])"
    return re.compile(r"(?<![A-Za-z0-9_.\-])" + re.escape(token) + tail)


def name_matches(test_file, stem):
    b = os.path.basename(test_file)
    pat = r"^(?:test_%s(?:_mutate|_mutations)?|t_%s)\.(?:sh|py|js|bats)$" % (re.escape(stem), re.escape(stem))
    return re.match(pat, b) is not None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    default_root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    ap.add_argument("--root", default=default_root)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()
    root = a.root
    if not os.path.isdir(root):
        refuse("root is not a directory: %s" % root)
    tools = discover(root)
    if not tools:
        refuse("no governed indexing tool discovered under %s (scripts/codegraph, scripts/lumen) — refusing to report 'nothing owed' from a blind scan" % root)

    tests_cache, rows = {}, []
    for rel, kind, tooldir in tools:
        name = os.path.basename(rel)
        stem = os.path.splitext(name)[0]
        if tooldir not in tests_cache:
            tests_cache[tooldir] = read_tests(root, tooldir)
        rx = token_re(stem if kind == "runner_patch" else name, kind != "runner_patch")
        hits = sorted({tp for tp, text in tests_cache[tooldir] if name_matches(tp, stem) or rx.search(text)})
        guide = None
        for cand in ("docs/scripts/%s.md" % stem, "docs/scripts/%s.md" % name):
            if os.path.isfile(os.path.join(root, cand)):
                guide = cand
                break
        owed = (["tests"] if not hits else []) + (["guide"] if guide is None else [])
        rows.append({"path": rel, "kind": kind, "tested": bool(hits), "tests": hits, "guide": guide, "owed": owed})

    owed_rows = [r for r in rows if r["owed"]]
    if a.json:
        print(json.dumps({"root": os.path.abspath(root), "tools": rows, "owed_count": len(owed_rows)}, indent=1, sort_keys=True))
    else:
        w = max(len(r["path"]) for r in rows)
        print("%-*s  %-12s %-6s %-6s" % (w, "TOOL", "KIND", "TESTS", "GUIDE"))
        for r in rows:
            print("%-*s  %-12s %-6s %-6s%s" % (w, r["path"], r["kind"], "yes" if r["tested"] else "NO", "yes" if r["guide"] else "NO",
                                             ("  OWED: " + ", ".join(r["owed"])) if r["owed"] else ""))
        print("owed: %d of %d tool(s)" % (len(owed_rows), len(rows)))
    return 1 if (a.strict and owed_rows) else 0


if __name__ == "__main__":
    sys.exit(main())
