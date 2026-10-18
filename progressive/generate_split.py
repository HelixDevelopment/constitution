#!/usr/bin/env python3
"""Deterministic Constitution splitter (02_quality_optimization.md §3.1/§3.2).

Reads ``Constitution.md`` and writes, byte-for-byte reproducibly:

  progressive/core.md        hand-authored lean core (NOT generated; only checked)
  progressive/catalog.json   machine-readable anchor index
  progressive/rules/<id>.md  one file per clause

Guarantees:
  * PURE FUNCTION of Constitution.md — no timestamps, no host paths, sorted keys,
    '\n' line endings, stable ordering. Running twice yields identical bytes.
  * REJECTS an unknown/malformed anchor rather than silently emitting a file.
  * ``--check`` regenerates into a temp dir and compares hashes against the
    committed artifacts; exits 1 on any drift.

Usage:
  python3 progressive/generate_split.py            # write catalog.json + rules/
  python3 progressive/generate_split.py --check    # verify committed artifacts
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Constitution.md"
OUT = ROOT / "progressive"
CATALOG = OUT / "catalog.json"
RULES = OUT / "rules"

# A clause heading: '### §11.4.141 — Title' / '## §8. Title' / '### §7.1 ...'
# Two definition styles are used by the source:
#   heading   '### §11.4.141 — Title'
#   bold-prose '**§11.4.182 — Title ...**' (a full clause on one line)
CLAUSE_RE = re.compile(r"^(#{2,6})\s+§(\d+(?:\.\d+)*)\.?(?:\s|—|-|$)(.*)$")
BOLD_RE = re.compile(r"^\*\*§(\d+(?:\.\d+)*)\s*(?:—|-)\s*(.*?)\*\*")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse(src: Path):
    """Return [(level, id, title, line_start, line_end, text)] in file order."""
    lines = src.read_text(encoding="utf-8").splitlines()
    heads = []
    for i, line in enumerate(lines):
        m = CLAUSE_RE.match(line)
        if m:
            level = len(m.group(1))
            cid = m.group(2)
            title = m.group(3).strip().lstrip("—-").strip()
            heads.append((i, level, cid, title))
            continue
        b = BOLD_RE.match(line)
        if b:
            # a single-line bold definition: level 3 so any following heading
            # closes it, and it never swallows a nested clause
            heads.append((i, 3, b.group(1), b.group(2).strip()))
    clauses = []
    seen = set()
    for idx, (i, level, cid, title) in enumerate(heads):
        # A rule file carries the clause's OWN text only: it stops at the next
        # clause heading of ANY level, so children are loaded separately instead
        # of being duplicated inside the parent (that is the whole point of
        # progressive disclosure — §11 must not ship every §11.4.x body).
        end = len(lines)
        if idx + 1 < len(heads):
            end = heads[idx + 1][0]
        body = "\n".join(lines[i:end]).rstrip("\n") + "\n"
        if cid in seen:
            raise SystemExit(f"FATAL: duplicate clause id §{cid} at line {i + 1}")
        seen.add(cid)
        if not re.fullmatch(r"\d+(?:\.\d+)*", cid):
            raise SystemExit(f"FATAL: malformed anchor id §{cid} at line {i + 1}")
        clauses.append({
            "id": f"§{cid}",
            "level": level,
            "title": title,
            "line_start": i + 1,
            "line_end": end,
            "text": body,
        })
    if not clauses:
        raise SystemExit("FATAL: no clause headings found")
    return clauses


def one_liner(title: str, text: str, limit: int = 64) -> str:
    """First sentence of the title, else the first prose sentence of the body."""
    candidate = title.strip()
    if not candidate:
        for line in text.splitlines()[1:]:
            s = line.strip()
            if s and not s.startswith(("#", "|", "-", "*", ">")):
                candidate = s
                break
    candidate = re.sub(r"\s+", " ", candidate).strip()
    if len(candidate) > limit:
        candidate = candidate[: limit - 1].rstrip() + "…"
    return candidate


TAG_RULES = [
    ("token-efficiency", ("token", "efficien", "cache", "context")),
    ("testing", ("test", "mutation", "evidence", "gate", "verif")),
    ("anti-bluff", ("bluff", "evidence", "pass", "fail")),
    ("host-safety", ("host", "session", "oom", "suspend", "memory")),
    ("credentials", ("credential", "secret", "key", "password")),
    ("review", ("review", "round", "reviewer")),
    ("git", ("git", "commit", "push", "branch", "submodule")),
    ("build", ("build", "soong", "make", "image")),
    ("governance", ("governance", "constitution", "anchor", "covenant")),
]


def tags_for(text: str) -> list[str]:
    low = text.lower()
    out = [name for name, needles in TAG_RULES if any(n in low for n in needles)]
    return out[:3]


def build(src: Path, out_dir: Path) -> dict:
    clauses = parse(src)
    rules_dir = out_dir / "rules"
    rules_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for c in clauses:
        fname = f"{c['id'].lstrip('§')}.md"
        data = c["text"].encode("utf-8")
        (rules_dir / fname).write_bytes(data)
        t = re.sub(r"\s+", " ", c["title"]).strip()
        if len(t) > 80:
            t = t[:79].rstrip() + "…"
        entries.append({
            "id": c["id"],
            "title": t,
            "one_line_description": one_liner(c["title"], c["text"]),
            "tags": tags_for(c["text"]),
            "file": f"progressive/rules/{fname}",
            "line_start": c["line_start"],
            "line_end": c["line_end"],
            "hash": "sha256:" + sha256_bytes(data),
        })
    catalog = {
        "schema_version": 1,
        "source": "Constitution.md",
        "source_sha256": sha256_bytes(src.read_bytes()),
        "anchor_count": len(entries),
        "anchors": entries,
    }
    (out_dir / "catalog.json").write_text(
        json.dumps(catalog, indent=1, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return catalog


def file_hashes(d: Path) -> dict:
    out = {}
    for p in sorted(d.rglob("*")):
        if p.is_file():
            out[str(p.relative_to(d))] = sha256_bytes(p.read_bytes())
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--source", default=str(SOURCE))
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args()
    src = Path(a.source)
    out = Path(a.out)
    if not src.is_file():
        print(f"FATAL: source missing: {src}", file=sys.stderr)
        return 2

    if a.check:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            build(src, tmp)
            want = file_hashes(tmp)
            have = {}
            for rel in ("catalog.json",):
                p = out / rel
                if p.is_file():
                    have[rel] = sha256_bytes(p.read_bytes())
            if (out / "rules").is_dir():
                for p in sorted((out / "rules").glob("*.md")):
                    have[f"rules/{p.name}"] = sha256_bytes(p.read_bytes())
            missing = sorted(set(want) - set(have))
            extra = sorted(set(have) - set(want))
            drift = sorted(k for k in set(want) & set(have) if want[k] != have[k])
            if missing or extra or drift:
                print("check: DRIFT", file=sys.stderr)
                for k in missing[:10]:
                    print(f"  missing: {k}", file=sys.stderr)
                for k in extra[:10]:
                    print(f"  extra:   {k}", file=sys.stderr)
                for k in drift[:10]:
                    print(f"  differs: {k}", file=sys.stderr)
                return 1
            print(f"check: reproducible ({len(want)} artifact(s), byte-identical)")
            return 0

    cat = build(src, out)
    print(f"generated: {cat['anchor_count']} anchors -> catalog.json + rules/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
