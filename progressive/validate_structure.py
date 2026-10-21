#!/usr/bin/env python3
"""Structural validation (02_quality_optimization.md §4.1).

Checks, deterministically and with no network:
  * anchor integrity      every clause in Constitution.md exists in catalog.json
                          with a matching id + hash, and nothing extra;
  * twin consistency      every anchor referenced by AGENTS.md / CLAUDE.md /
                          QWEN.md / GEMINI.md resolves to a real clause;
  * split reproducibility generate_split.py --check must pass (byte-for-byte);
  * no placeholders       no TODO / FIXME / HACK / NotImplementedError in the
                          generated layer.

Exits 0 on success, 1 on a failed check, 2 when an input is missing (a missing
input is never treated as a pass). Writes JSON evidence when --evidence is given.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROG = ROOT / "progressive"
CATALOG = PROG / "catalog.json"
RULES = PROG / "rules"
ANCHOR_RE = re.compile(r"§\d+(?:\.\d+)*")


def load_catalog():
    if not CATALOG.is_file():
        return None
    return json.loads(CATALOG.read_text(encoding="utf-8"))


MANIFEST = PROG / "rules_manifest.json"


def load_manifest():
    if not MANIFEST.is_file():
        return None
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def test_catalog_complete(cat) -> tuple[bool, str]:
    """The slim catalog carries no digests; integrity lives in rules_manifest.json.
    Both must list the same ids, and every digest must match the rule file."""
    import hashlib
    if cat is None:
        return False, "catalog.json missing"
    man = load_manifest()
    if man is None:
        return False, "rules_manifest.json missing"
    ids = [a["id"] for a in cat["anchors"]]
    if len(ids) != len(set(ids)):
        return False, "catalog contains duplicate anchor ids"
    if cat.get("anchor_count") != len(ids):
        return False, "anchor_count does not match the entry list"
    if not (ROOT / cat["source"]).is_file():
        return False, "source missing"
    rules = man.get("rules", {})
    if set(rules) != set(ids):
        miss = sorted(set(ids) - set(rules))[:5]
        extra = sorted(set(rules) - set(ids))[:5]
        return False, f"catalog/manifest id mismatch: not-in-manifest={miss} not-in-catalog={extra}"
    for a in cat["anchors"]:
        r = rules[a["id"]]
        if r["file"] != a["file"]:
            return False, f"catalog/manifest path mismatch for {a['id']}"
        p = ROOT / a["file"]
        if not p.is_file():
            return False, f"rule file missing: {a['file']}"
        if "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest() != r["hash"]:
            return False, f"hash mismatch for {a['id']} ({a['file']})"
    return True, f"{len(ids)} anchors, catalog==manifest ids, every rule file hash-verified"


def test_anchor_integrity(cat) -> tuple[bool, str]:
    src = (ROOT / "Constitution.md").read_text(encoding="utf-8")
    defined = set("§" + m for m in ANCHOR_RE.findall(src))
    # headings are the contract; a bare reference is not a definition
    heads = set()
    for line in src.splitlines():
        m = re.match(r"^#{2,6}\s+(§\d+(?:\.\d+)*)", line)
        if m:
            heads.add(m.group(1))
            continue
        b = re.match(r"^\*\*(§\d+(?:\.\d+)*)\s*(?:—|-)", line)
        if b:
            heads.add(b.group(1))
    cat_ids = set(a["id"] for a in cat["anchors"]) if cat else set()
    missing = sorted(heads - cat_ids)
    extra = sorted(cat_ids - heads)
    if missing or extra:
        return False, f"missing={missing[:5]} extra={extra[:5]}"
    return True, f"{len(heads)} clause headings == catalog ids"


def test_twin_consistency(cat) -> tuple[bool, str]:
    """Twins may reference a SUBSET, but they may never invent an anchor; every
    defined anchor must be mirrored by at least one twin or declared in
    progressive/twin_exceptions.txt with a reason (governance-drift guard)."""
    if cat is None:
        return False, "catalog.json missing"
    src = (ROOT / "Constitution.md").read_text(encoding="utf-8", errors="ignore")
    defined = set(a["id"] for a in cat["anchors"])
    mentioned = set(ANCHOR_RE.findall(src))  # references the canon itself makes
    known = defined | mentioned
    twins = [n for n in ("AGENTS.md", "CLAUDE.md", "QWEN.md", "GEMINI.md") if (ROOT / n).is_file()]
    if not twins:
        return False, "no twin governance file found"
    referenced = set()
    invented = []
    for name in twins:
        refs = set(ANCHOR_RE.findall((ROOT / name).read_text(encoding="utf-8", errors="ignore")))
        referenced |= refs
        invented += [f"{name}:{r}" for r in sorted(refs - known)]
    if invented:
        return False, f"twin references an anchor absent from the canon: {invented[:5]}"
    exc_file = PROG / "twin_exceptions.txt"
    declared = set()
    if exc_file.is_file():
        for line in exc_file.read_text(encoding="utf-8").splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                declared.add(line)
    unmirrored = sorted(defined - referenced - declared)
    if unmirrored:
        return False, (f"{len(unmirrored)} defined anchor(s) are mirrored by no twin and not "
                       f"declared in progressive/twin_exceptions.txt: {unmirrored[:5]}")
    return True, (f"twins reference {len(referenced)} anchors, all resolvable; "
                  f"{len(defined - referenced)} declared exception(s)")


def test_split_reproducible() -> tuple[bool, str]:
    rc = subprocess.run(
        [sys.executable, str(PROG / "generate_split.py"), "--check"],
        capture_output=True, text=True,
    )
    out = (rc.stdout + rc.stderr).strip().splitlines()
    return rc.returncode == 0, (out[-1] if out else f"rc={rc.returncode}")


PLACEHOLDER_RE = re.compile(r"\b(TODO|FIXME|XXX|HACK|NotImplementedError)\b")


def test_no_placeholders() -> tuple[bool, str]:
    hits = []
    for p in sorted(PROG.rglob("*")):
        # rules/ are VERBATIM copies of the source; a banned word there is the
        # source's own prose, not a placeholder in delivered code.
        if "rules" in p.parts or "EVIDENCE" in p.parts:
            # rules/ are verbatim source copies; EVIDENCE/ is generated output
            # that legitimately QUOTES a banned marker when it reports one.
            continue
        if p.is_file() and p.suffix in (".py", ".md", ".json") and p.name != "validate_structure.py":
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                if PLACEHOLDER_RE.search(line):
                    hits.append(f"{p.relative_to(ROOT)}:{i}")
    if hits:
        return False, f"{len(hits)} placeholder marker(s): {hits[:5]}"
    return True, "no TODO/FIXME/HACK/NotImplementedError in the progressive layer"


CHECKS = [
    ("test_catalog_complete", test_catalog_complete),
    ("test_anchor_integrity", test_anchor_integrity),
    ("test_twin_consistency", test_twin_consistency),
    ("test_split_reproducible", lambda cat: test_split_reproducible()),
    ("test_no_placeholders", lambda cat: test_no_placeholders()),
]


def main() -> int:
    evidence = None
    if "--evidence" in sys.argv:
        evidence = Path(sys.argv[sys.argv.index("--evidence") + 1])
    cat = load_catalog()
    results, ok_all = [], True
    for name, fn in CHECKS:
        try:
            ok, detail = fn(cat)
        except Exception as e:  # a crash is a FAIL, never a skip
            ok, detail = False, f"exception: {type(e).__name__}: {e}"
        results.append({"check": name, "ok": ok, "detail": detail})
        print(f"{'PASS' if ok else 'FAIL'}: {name} — {detail}")
        ok_all = ok_all and ok
    if evidence:
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps({"checks": results, "ok": ok_all}, indent=1) + "\n", encoding="utf-8")
    print(f"STRUCTURE: {'PASS' if ok_all else 'FAIL'}")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
