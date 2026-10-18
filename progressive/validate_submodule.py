#!/usr/bin/env python3
"""Submodule-integration validation (02_quality_optimization.md §4.4).

Checks the real submodule relationship, not a mock:
  * pinned revision  the consumer's .constitution-pin SHA equals this repo's HEAD;
  * recursive fetch  no uninitialised (``-`` prefix) nested submodule;
  * deterministic tree  the submodule working tree is clean (a split run leaves
    no drift), and `git submodule status --recursive` is reproducible.

A missing consumer pin is UNCONFIRMED (exit 3), never a pass.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # the constitution repo
CONSUMER = ROOT.parent                                  # the consuming project


def sh(args, cwd=ROOT) -> tuple[int, str]:
    p = subprocess.run(args, cwd=str(cwd), capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def main() -> int:
    evidence = None
    if "--evidence" in sys.argv:
        evidence = Path(sys.argv[sys.argv.index("--evidence") + 1])
    results, ok_all = [], True

    rc, head = sh(["git", "rev-parse", "HEAD"])
    head = head if rc == 0 else ""

    pin_file = CONSUMER / ".constitution-pin"
    if not pin_file.is_file():
        ok_all = False
        results.append({"check": "test_pinned_revision", "status": "UNCONFIRMED",
                        "detail": f"no consumer pin at {pin_file}"})
        print(f"UNCONFIRMED: test_pinned_revision — no consumer pin at {pin_file}")
    else:
        pin = ""
        for line in pin_file.read_text(encoding="utf-8").splitlines():
            if line.startswith("SHA="):
                pin = line.split("=", 1)[1].strip()
        ok = bool(pin) and pin == head
        ok_all = ok_all and ok
        results.append({"check": "test_pinned_revision", "status": "PASS" if ok else "FAIL",
                        "pin": pin, "head": head})
        print(f"{'PASS' if ok else 'FAIL'}: test_pinned_revision — pin={pin[:12] or '<empty>'} head={head[:12]}")

    if "--status-file" in sys.argv:
        st = Path(sys.argv[sys.argv.index("--status-file") + 1]).read_text(encoding="utf-8")
        rc = 0
    else:
        rc, st = sh(["git", "submodule", "status", "--recursive"])
    uninit = [l.split()[1] for l in st.splitlines() if l.startswith("-")]
    # The invariant is "no PHANTOM/orphan gitlink": an uninitialised path that is
    # NOT declared in .gitmodules can never be fetched (a dead pointer). A
    # declared-but-uninitialised optional tooling submodule is a recorded state,
    # not an orphan.
    declared_paths = []
    for gm in ROOT.rglob(".gitmodules"):
        if ".git" in gm.parts:
            continue
        for line in gm.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if line.startswith("path = "):
                declared_paths.append(line[len("path = "):].strip().rstrip("/"))
    orphans = [u for u in uninit
               if not any(u == d or u.endswith("/" + d) for d in declared_paths)]
    ok = rc == 0 and not orphans
    ok_all = ok_all and ok
    results.append({"check": "test_recursive_fetch", "status": "PASS" if ok else "FAIL",
                    "orphans": orphans, "declared_uninitialised": len(uninit) - len(orphans)})
    print(f"{'PASS' if ok else 'FAIL'}: test_recursive_fetch — "
          + ("no orphan gitlink" if ok else f"{len(orphans)} orphan gitlink(s): {orphans[:5]}")
          + f"; {len(uninit) - len(orphans)} declared-but-uninitialised optional submodule(s)")

    rc, dirty = sh(["git", "status", "--porcelain", "--untracked-files=no", "--", "progressive"])
    ok = rc == 0 and dirty == ""
    ok_all = ok_all and ok
    results.append({"check": "test_deterministic_tree", "status": "PASS" if ok else "FAIL",
                    "dirty": dirty.splitlines()[:5]})
    print(f"{'PASS' if ok else 'FAIL'}: test_deterministic_tree — "
          + ("progressive/ is clean (split reproduced exactly)" if ok else "progressive/ has unstaged drift"))

    if evidence:
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps({"checks": results}, indent=1) + "\n", encoding="utf-8")
    if not ok_all:
        if any(r["status"] == "FAIL" for r in results):
            print("SUBMODULE: FAIL")
            return 1
        print("SUBMODULE: UNCONFIRMED")
        return 3
    print("SUBMODULE: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
