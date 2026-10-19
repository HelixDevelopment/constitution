#!/usr/bin/env python3
"""Evidence-artifact validation (02_quality_optimization.md §2-§3, 03_speed_optimization.md §1.1/§10).

A missing or STALE evidence artifact FAILS. Checks, deterministic and offline:

  required_artifacts    every artifact the DoD names exists and is non-empty
  index_integrity       INDEX.json parses, lists every required artifact and every file in
                        EVIDENCE/, and every recorded sha256 equals the file on disk
  anchors_fresh         ANCHORS.json equals a fresh independent re-inventory of
                        Constitution.md + the twins (a dropped anchor makes it stale)
  anchors_discrepancies every disagreement between ANCHORS.json and catalog.json is named in
                        DISCREPANCIES.md (an unrecorded disagreement FAILS)
  manifest_fresh        PREFLIGHT_MANIFEST.json equals the current file tree (changed, extra
                        and, in a full tree, missing files FAIL)
  consumers_fresh       CONSUMERS.json equals a fresh scan of the parent repository
  known_issues_shape    KNOWN_ISSUES.md has one section per validator (+ --deep: re-run)

Flags:
  --partial-tree   the tree is a sandbox copy (mutation matrix): files named by the manifest
                   but absent on disk are tolerated, and CONSUMERS freshness is skipped
                   because the parent repository is not the real one
  --deep           also regenerate KNOWN_ISSUES.md by re-running the validators
  --evidence FILE  write a JSON result

Exit codes: 0 PASS, 1 a check FAILED, 2 the EVIDENCE directory is missing.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import gen_evidence as ge  # noqa: E402

EVD = ge.EVD
REQUIRED = (
    "PREFLIGHT_MANIFEST.json", "ANCHORS.json", "CONSUMERS.json", "INDEX.json",
    "KNOWN_ISSUES.md", "RISK_REGISTER.md", "DISCREPANCIES.md",
    "STRUCTURE.json", "BEHAVIOR.json", "TOKENS.json", "SUBMODULE.json", "MUTATIONS.json",
    "MCP_SELFTEST.txt",
)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def check_required(**_):
    bad = [n for n in REQUIRED if not (EVD / n).is_file() or (EVD / n).stat().st_size == 0]
    if bad:
        return False, f"missing or empty: {bad}"
    return True, f"{len(REQUIRED)} required artifacts present and non-empty"


def check_index(**_):
    p = EVD / "INDEX.json"
    if not p.is_file():
        return False, "INDEX.json missing"
    try:
        idx = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        return False, f"INDEX.json unparseable: {type(e).__name__}"
    arts = idx.get("artifacts")
    if not isinstance(arts, dict) or not arts:
        return False, "INDEX.json has no artifacts map"
    problems = []
    for n in REQUIRED:
        if n != "INDEX.json" and n not in arts:
            problems.append(f"{n} not indexed")
    on_disk = {q.name for q in EVD.iterdir() if q.is_file()} - set(ge.INDEX_EXCLUDED)
    for n in sorted(on_disk - set(arts)):
        problems.append(f"{n} present on disk but not indexed")
    for n, rec in sorted(arts.items()):
        f = EVD / n
        if not f.is_file():
            problems.append(f"{n} indexed but missing")
        elif sha(f) != rec.get("sha256"):
            problems.append(f"{n} sha256 differs from INDEX.json")
    if problems:
        return False, "; ".join(problems[:6]) + (f" (+{len(problems) - 6} more)" if len(problems) > 6 else "")
    return True, f"{len(arts)} artifacts indexed, every sha256 matches the file on disk"


def check_anchors_fresh(**_):
    p = EVD / "ANCHORS.json"
    if not p.is_file():
        return False, "ANCHORS.json missing"
    want = ge.gen_anchors().encode("utf-8")
    if p.read_bytes() != want:
        try:
            have = json.loads(p.read_text(encoding="utf-8"))
            now = json.loads(want)
            hd = {d["id"] for d in have["files"]["Constitution.md"]["definitions"]}
            nd = {d["id"] for d in now["files"]["Constitution.md"]["definitions"]}
            detail = f"inventory ids dropped={sorted(nd - hd)[:5]} added={sorted(hd - nd)[:5]}"
        except Exception:
            detail = "content differs"
        return False, f"ANCHORS.json is stale vs a fresh inventory ({detail})"
    n = len(json.loads(want)["files"]["Constitution.md"]["definitions"])
    return True, f"ANCHORS.json equals a fresh independent inventory ({n} canonical definitions)"


def check_discrepancies(**_):
    try:
        cc = json.loads((EVD / "ANCHORS.json").read_text(encoding="utf-8"))["crosscheck_vs_catalog"]
        text = (EVD / "DISCREPANCIES.md").read_text(encoding="utf-8")
    except Exception as e:
        return False, f"cannot read ANCHORS.json/DISCREPANCIES.md: {type(e).__name__}"
    named = set(cc["ids_only_in_inventory"]) | set(cc["ids_only_in_catalog"]) \
        | {m["id"] for m in cc["range_mismatches"]} | set(cc["hash_mismatches_with_equal_range"])
    unrecorded = sorted(i for i in named if i not in text)
    if unrecorded:
        return False, f"disagreement(s) not recorded in DISCREPANCIES.md: {unrecorded}"
    return True, f"{len(named)} catalog/inventory disagreement id(s), all recorded in DISCREPANCIES.md"


def check_manifest(partial: bool, **_):
    p = EVD / "PREFLIGHT_MANIFEST.json"
    if not p.is_file():
        return False, "PREFLIGHT_MANIFEST.json missing"
    try:
        man = json.loads(p.read_text(encoding="utf-8"))
        files = man["files"]
    except Exception as e:
        return False, f"unparseable: {type(e).__name__}"
    now = ge.tree_hashes()
    changed = sorted(k for k in set(files) & set(now) if files[k] != now[k])
    extra = sorted(set(now) - set(files))
    missing = [] if partial else sorted(set(files) - set(now))
    if changed or extra or missing:
        return False, (f"stale: changed={changed[:4]} (+{max(0, len(changed) - 4)}) "
                       f"new-on-disk={extra[:3]} (+{max(0, len(extra) - 3)}) "
                       f"missing-on-disk={missing[:3]} (+{max(0, len(missing) - 3)})")
    if not partial and man.get("file_count") != len(files):
        return False, "file_count does not match the files map"
    return True, f"{len(files)} manifest entries" + (" (partial tree: absent entries tolerated)" if partial else "") \
        + ", every on-disk file matches"


def check_consumers(partial: bool, **_):
    p = EVD / "CONSUMERS.json"
    if not p.is_file():
        return False, "CONSUMERS.json missing"
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        data["structured"], data["summary"], data["references"]
    except Exception as e:
        return False, f"unparseable or incomplete: {type(e).__name__}"
    if partial:
        return True, "parseable with structured/summary/references (freshness skipped: sandbox parent)"
    if p.read_bytes() != ge.gen_consumers().encode("utf-8"):
        return False, "CONSUMERS.json is stale vs a fresh scan of the parent repository"
    return True, f"equals a fresh scan ({data['summary']['files_with_references']} referencing files)"


def check_known_issues(deep: bool, **_):
    p = EVD / "KNOWN_ISSUES.md"
    if not p.is_file():
        return False, "KNOWN_ISSUES.md missing"
    text = p.read_text(encoding="utf-8")
    miss = [s for s, _ in ge.VALIDATORS if f"## {s}" not in text]
    if miss or "## Summary" not in text:
        return False, f"sections missing: {miss}"
    if deep and p.read_bytes() != ge.gen_known_issues().encode("utf-8"):
        return False, "KNOWN_ISSUES.md is stale vs a re-run of the validators"
    return True, "one section per validator + summary" + (" (re-run matches)" if deep else "")


CHECKS = (
    ("required_artifacts", check_required),
    ("index_integrity", check_index),
    ("anchors_fresh", check_anchors_fresh),
    ("anchors_discrepancies", check_discrepancies),
    ("manifest_fresh", check_manifest),
    ("consumers_fresh", check_consumers),
    ("known_issues_shape", check_known_issues),
)


def main() -> int:
    partial = "--partial-tree" in sys.argv
    deep = "--deep" in sys.argv
    if not EVD.is_dir():
        print(f"FAIL: EVIDENCE directory missing: {EVD}")
        return 2
    results, ok_all = [], True
    for name, fn in CHECKS:
        try:
            ok, detail = fn(partial=partial, deep=deep)
        except Exception as e:  # a crash is a FAIL, never a skip
            ok, detail = False, f"exception: {type(e).__name__}: {e}"
        results.append({"check": name, "ok": ok, "detail": detail})
        print(f"{'PASS' if ok else 'FAIL'}: {name} — {detail}")
        ok_all = ok_all and ok
    if "--evidence" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--evidence") + 1])
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"checks": results, "ok": ok_all}, indent=1, sort_keys=True) + "\n",
                       encoding="utf-8")
    print(f"EVIDENCE: {'PASS' if ok_all else 'FAIL'}")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
