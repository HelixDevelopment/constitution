#!/usr/bin/env python3
"""Evidence generator (02_quality_optimization.md §2-§3, 03_speed_optimization.md §1.1/§10).

ONE deterministic script that produces the evidence artifacts the DoD names:

  EVIDENCE/PREFLIGHT_MANIFEST.json  sha256 of every file in the constitution submodule
                                    tree (excluding .git, __pycache__ and EVIDENCE/)
  EVIDENCE/ANCHORS.json             independent anchor inventory of Constitution.md and
                                    the twin governance files + cross-check vs catalog
  EVIDENCE/CONSUMERS.json           read-only scan of the parent repo for every reference
                                    to the constitution submodule
  EVIDENCE/KNOWN_ISSUES.md          non-PASS results of the existing validators
  EVIDENCE/INDEX.json               machine-parseable index of every EVIDENCE artifact
                                    with its sha256

EVIDENCE/RISK_REGISTER.md is hand-authored; this script requires it to exist and
indexes it.

The ANCHORS inventory is written WITHOUT importing generate_split.py: it uses its own
regexes and its own line model, so agreement or disagreement with catalog.json is
evidence, not tautology. Disagreements are reported, never forced.

Determinism: sorted keys, '\\n' endings, no host paths, no timestamps. The single
exception is INDEX.json "generated_at", which is excluded from every comparison and is
preserved across re-runs when nothing else changed (so a no-op run is byte-identical).

Usage:
  python3 progressive/gen_evidence.py            # write the artifacts
  python3 progressive/gen_evidence.py --check    # regenerate into a temp dir and diff
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # constitution submodule
PROG = ROOT / "progressive"
EVD = PROG / "EVIDENCE"
CONSUMER = ROOT.parent                                  # parent repo

GENERATED = ("PREFLIGHT_MANIFEST.json", "ANCHORS.json", "CONSUMERS.json", "KNOWN_ISSUES.md")
HAND_AUTHORED = ("RISK_REGISTER.md", "DISCREPANCIES.md")
PRODUCERS = {
    "PREFLIGHT_MANIFEST.json": "gen_evidence.py",
    "ANCHORS.json": "gen_evidence.py",
    "CONSUMERS.json": "gen_evidence.py",
    "KNOWN_ISSUES.md": "gen_evidence.py",
    "STRUCTURE.json": "validate_structure.py --evidence",
    "BEHAVIOR.json": "validate_behavior.py --evidence",
    "TOKENS.json": "validate_tokens.py --evidence",
    "SUBMODULE.json": "validate_submodule.py --evidence",
    "MUTATIONS.json": "mutation_matrix.py --evidence",
    "MCP_SELFTEST.txt": "mcp_server.py --selftest (stdout)",
    "DISCREPANCIES.md": "hand-authored from measured output",
    "RISK_REGISTER.md": "hand-authored",
}
# an append-only server log grows on every call; it can never have a stable digest
INDEX_EXCLUDED = {"INDEX.json": "the index itself", "mcp_accounting.jsonl": "append-only server log"}
TWINS = ("AGENTS.md", "CLAUDE.md", "QWEN.md", "GEMINI.md")
CANON = "Constitution.md"


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def dumps(obj) -> str:
    return json.dumps(obj, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


# --------------------------------------------------------------------------- manifest
MANIFEST_EXCLUDED_DIRS = (".git", "__pycache__")


def tree_hashes(root: Path = ROOT, evidence_dir: Path = EVD) -> dict:
    """{relpath: sha256} for every file under root, excluding .git (dir or gitlink
    file), __pycache__ and the EVIDENCE dir (which records this very result)."""
    out = {}
    ev = evidence_dir.resolve()
    for dp, dns, fns in os.walk(root, followlinks=False):
        dpp = Path(dp)
        dns[:] = sorted(d for d in dns
                        if d not in MANIFEST_EXCLUDED_DIRS and (dpp / d).resolve() != ev)
        for fn in sorted(fns):
            if fn == ".git":
                continue
            p = dpp / fn
            rel = p.relative_to(root).as_posix()
            if p.is_symlink():
                out[rel] = "symlink:" + os.readlink(p)
                continue
            try:
                out[rel] = sha256_file(p)
            except OSError as e:
                out[rel] = f"UNREADABLE:{type(e).__name__}"
    return dict(sorted(out.items()))


def gen_manifest() -> str:
    files = tree_hashes()
    agg = hashlib.sha256()
    for k, v in files.items():
        agg.update(f"{k}\0{v}\n".encode("utf-8"))
    return dumps({
        "schema_version": 1,
        "scope": "every file under the constitution submodule working tree",
        "excluded": {"dirs": list(MANIFEST_EXCLUDED_DIRS),
                     "paths": ["progressive/EVIDENCE/"],
                     "files": [".git (gitlink file)"],
                     "reason": "EVIDENCE/ records this result; .git is VCS metadata"},
        "file_count": len(files),
        "tree_sha256": agg.hexdigest(),
        "files": files,
    })


# --------------------------------------------------------------------------- anchors
ID_DEF = r"§\d+(?:\.\d+)*(?:\.[A-Za-z]+|\([A-Za-z0-9]+\))?"
HEAD_RE = re.compile(r"^(#{1,6})[ \t]+(" + ID_DEF + r")\.?(?=[ \t]|$|—|–|-)")
BOLD_RE = re.compile(r"^\*\*(" + ID_DEF + r")[ \t]*(?:—|–|-)")
REF_RE = re.compile(r"§\d+(?:\.\d+)*")
LINE_START_RE = re.compile(r"^([ \t]*(?:[-*>][ \t]+)?)(§\d+(?:\.\d+)*)")
FENCE_RE = re.compile(r"^[ \t]*(```|~~~)")


def inventory(path: Path) -> dict:
    raw = path.read_bytes()
    text = raw.decode("utf-8", errors="replace")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    defs, in_fence, fence_skipped = [], False, []
    line_start_nd = []
    for i, line in enumerate(lines, 1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        m = HEAD_RE.match(line)
        b = None if m else BOLD_RE.match(line)
        if in_fence:
            if m or b:
                fence_skipped.append(i)
            continue
        if m:
            defs.append({"id": m.group(2), "kind": f"heading-h{len(m.group(1))}", "line": i,
                         "heading": line.strip()[:100]})
        elif b:
            defs.append({"id": b.group(1), "kind": "bold-line", "line": i,
                         "heading": line.strip()[:100]})
        else:
            ls = LINE_START_RE.match(line)
            if ls:
                line_start_nd.append((i, ls))
    def_lines = [d["line"] for d in defs]
    seen_ids, dups = set(), []
    for idx, d in enumerate(defs):
        end = def_lines[idx + 1] - 1 if idx + 1 < len(defs) else len(lines)
        body = "\n".join(lines[d["line"] - 1:end]).rstrip("\n") + "\n"
        d["line_start"], d["line_end"] = d["line"], end
        d["text_sha256"] = sha256_bytes(body.encode("utf-8"))
        del d["line"]
        if d["id"] in seen_ids:
            dups.append(d["id"])
        seen_ids.add(d["id"])
    defined = {d["id"] for d in defs}
    nd = []
    for ln, ls in line_start_nd:
        prev = lines[ln - 2].strip() if ln >= 2 else ""
        tok = ls.group(2)
        if ls.group(1).strip():
            kind = "list-item-reference"
        elif prev and not prev.startswith("#") and not re.search(r"[.:;!?)]$", prev):
            kind = "wrapped-paragraph-continuation"
        elif prev:
            kind = "paragraph-start-reference"
        else:
            kind = "paragraph-start-reference"
        nd.append({"id": tok, "line": ln, "kind": kind,
                   "previous_line_tail": prev[-60:], "text": lines[ln - 1].strip()[:100],
                   "id_defined_elsewhere": tok in defined})
    refs: dict = {}
    in_fence = False
    for i, line in enumerate(lines, 1):
        for tok in REF_RE.findall(line):
            r = refs.setdefault(tok, {"count": 0, "first_line": i})
            r["count"] += 1
    return {
        "sha256": sha256_bytes(raw),
        "line_count": len(lines),
        "definitions": defs,
        "duplicate_definition_ids": sorted(set(dups)),
        "definition_like_lines_inside_code_fences": fence_skipped,
        "line_start_non_definitions": nd,
        "reference_ids": dict(sorted(refs.items())),
    }


def crosscheck(canon_inv: dict) -> dict:
    """Compare the independent inventory with catalog.json + rules_manifest.json.
    Reported, never forced."""
    cat = json.loads((PROG / "catalog.json").read_text(encoding="utf-8"))
    man = json.loads((PROG / "rules_manifest.json").read_text(encoding="utf-8"))["rules"]
    cat_ids = {a["id"] for a in cat["anchors"]}
    mine = {d["id"]: d for d in canon_inv["definitions"]}
    only_a = sorted(set(mine) - cat_ids)
    only_c = sorted(cat_ids - set(mine))
    range_mm, hash_mm = [], []
    for i in sorted(set(mine) & cat_ids):
        d, r = mine[i], man.get(i)
        if r is None:
            continue
        if [d["line_start"], d["line_end"]] != [r["line_start"], r["line_end"]]:
            range_mm.append({"id": i, "anchors_json": [d["line_start"], d["line_end"]],
                             "catalog": [r["line_start"], r["line_end"]]})
        elif "sha256:" + d["text_sha256"] != r["hash"]:
            hash_mm.append(i)
    ref_only = []  # line-start tokens that are not definitions and not defined elsewhere
    for t in canon_inv["line_start_non_definitions"]:
        if not t["id_defined_elsewhere"] and t["id"] not in cat_ids:
            ref_only.append({"id": t["id"], "line": t["line"], "kind": t["kind"]})
    return {
        "catalog_anchor_count": len(cat_ids),
        "inventory_definition_count": len(mine),
        "ids_only_in_inventory": only_a,
        "ids_only_in_catalog": only_c,
        "range_mismatches": range_mm,
        "hash_mismatches_with_equal_range": hash_mm,
        "line_start_tokens_defined_nowhere": ref_only,
        "agree": not (only_a or only_c or range_mm or hash_mm),
    }


def gen_anchors() -> str:
    files = {}
    for name in (CANON,) + TWINS:
        p = ROOT / name
        if p.is_file():
            files[name] = inventory(p)
    canon = files[CANON]
    twin_ids = sorted({i for n in TWINS if n in files for i in files[n]["reference_ids"]})
    canon_all = set(canon["reference_ids"])
    return dumps({
        "schema_version": 1,
        "method": ("independent regex inventory of definitions (heading '#{1,6} §id' and "
                   "bold-line '**§id —'), code fences excluded; span = definition line to the "
                   "line before the next definition; text_sha256 = sha256 of the span, "
                   "rstripped + one '\\n'. Does not import generate_split.py."),
        "files": files,
        "twin_reference_ids_not_in_canon_text": sorted(set(twin_ids) - canon_all),
        "crosscheck_vs_catalog": crosscheck(canon),
    })


# --------------------------------------------------------------------------- consumers
SCAN_FILES = (".gitmodules", ".constitution-pin", "CLAUDE.md", "AGENTS.md", "GEMINI.md", "QWEN.md",
              "CONSTITUTION_ACTIVATION.md", ".mcp.json", ".claude/settings.json",
              ".claude/settings.local.json", ".gitignore", ".commit_all_exclude")
SCAN_DIRS = (".claude/skills", ".claude/agents", ".github", ".codegraph", ".gemini", ".helix",
             ".opencode", ".qwen", ".cursor", ".specify", "scripts", "tests", "config", "docker",
             "device/rockchip/rk3588/tests")
SCAN_EXCLUDED = ("external", "prebuilts", "out", ".git", "node_modules", ".backups",
                 "__pycache__", "constitution")
SCAN_SUFFIX = {".md", ".sh", ".py", ".json", ".yml", ".yaml", ".toml", ".cfg", ".conf", ".txt",
               ".mk", ".bp", ".template", ".rc", ".ini", ""}
MAX_BYTES = 2_000_000
PATTERNS = (
    ("path", re.compile(r"(?<![A-Za-z0-9_.-])constitution/")),
    ("canon-file", re.compile(r"Constitution\.md")),
    ("pin-file", re.compile(r"\.constitution-pin")),
    ("helix-name", re.compile(r"HelixConstitution|helixconstitution", re.I)),
    ("import", re.compile(r"^\s*@\S*constitution\S*", re.I)),
)


def category(rel: str) -> str:
    if rel == ".gitmodules":
        return "submodule-declaration"
    if rel == ".constitution-pin":
        return "pin"
    if rel in ("CLAUDE.md", "AGENTS.md", "GEMINI.md", "QWEN.md", "CONSTITUTION_ACTIVATION.md"):
        return "instruction-file"
    if rel == ".mcp.json":
        return "mcp-config"
    if rel.startswith(".claude/settings"):
        return "claude-settings"
    if rel.startswith(".claude/skills"):
        return "claude-skill"
    if rel.startswith(".claude/agents"):
        return "claude-agent"
    if rel.startswith(".github"):
        return "ci-workflow"
    if rel.startswith((".codegraph", ".helix")):
        return "codegraph-lsp-config"
    if rel.startswith((".gemini", ".opencode", ".qwen", ".cursor", ".specify")):
        return "other-agent-config"
    if rel.startswith("scripts/"):
        return "script"
    if rel.startswith(("tests/", "device/")):
        return "test"
    return "other"


def scan_file(rel: str, p: Path) -> dict | None:
    try:
        if p.stat().st_size > MAX_BYTES:
            return None
        text = p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        UNREADABLE.append(rel)
        return None
    kinds, samples, n = set(), [], 0
    for i, line in enumerate(text.split("\n"), 1):
        hit = [k for k, rx in PATTERNS if rx.search(line)]
        if hit:
            n += 1
            kinds.update(hit)
            if len(samples) < 3:
                samples.append({"line": i, "text": line.strip()[:140]})
    if not n:
        return None
    return {"path": rel, "category": category(rel), "hit_lines": n,
            "kinds": sorted(kinds), "samples": samples}


UNREADABLE: list = []


def gen_consumers() -> str:
    UNREADABLE.clear()
    hits = []
    for rel in SCAN_FILES:
        p = CONSUMER / rel
        if p.is_file():
            r = scan_file(rel, p)
            if r:
                hits.append(r)
    for d in SCAN_DIRS:
        base = CONSUMER / d
        if not base.is_dir():
            continue
        def onerr(e):
            UNREADABLE.append(Path(e.filename).relative_to(CONSUMER).as_posix())

        for dp, dns, fns in os.walk(base, followlinks=False, onerror=onerr):
            dns[:] = sorted(x for x in dns if x not in SCAN_EXCLUDED)
            for fn in sorted(fns):
                p = Path(dp) / fn
                try:
                    if p.suffix.lower() not in SCAN_SUFFIX or p.is_symlink():
                        continue
                except OSError:
                    UNREADABLE.append(p.relative_to(CONSUMER).as_posix())
                    continue
                r = scan_file(p.relative_to(CONSUMER).as_posix(), p)
                if r:
                    hits.append(r)
    hits.sort(key=lambda h: h["path"])

    structured: dict = {}
    gm = CONSUMER / ".gitmodules"
    if gm.is_file():
        cur, entries = None, []
        for line in gm.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            m = re.match(r'\[submodule "(.+)"\]', line)
            if m:
                cur = {"name": m.group(1)}
                entries.append(cur)
            elif cur is not None and "=" in line:
                k, v = (x.strip() for x in line.split("=", 1))
                cur[k] = v
        structured["gitmodules_constitution"] = [
            e for e in entries if "constitution" in json.dumps(e).lower()]
    pin = CONSUMER / ".constitution-pin"
    if pin.is_file():
        kv = {}
        for line in pin.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                kv[k.strip()] = v.strip()
        structured["constitution_pin"] = kv
    mcp = CONSUMER / ".mcp.json"
    if mcp.is_file():
        try:
            servers = json.loads(mcp.read_text(encoding="utf-8")).get("mcpServers", {})
            structured["mcp_servers_referencing_constitution"] = {
                k: v for k, v in sorted(servers.items()) if "constitution" in json.dumps(v)}
        except Exception as e:
            structured["mcp_parse_error"] = f"{type(e).__name__}: {e}"
    hooks = {}
    for sf in (".claude/settings.json", ".claude/settings.local.json"):
        p = CONSUMER / sf
        if not p.is_file():
            continue
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            hooks[sf] = f"parse error: {type(e).__name__}: {e}"
            continue
        found = []
        for ev, groups in sorted((data.get("hooks") or {}).items()):
            for g in groups or []:
                for h in g.get("hooks", []):
                    c = h.get("command", "")
                    if "constitution" in c.lower():
                        found.append({"event": ev, "matcher": g.get("matcher", ""),
                                      "command": c[:200]})
        hooks[sf] = found
    structured["claude_hooks_referencing_constitution"] = hooks
    imports = [{"path": h["path"], "line": s["line"], "text": s["text"]}
               for h in hits if h["category"] == "instruction-file"
               for s in h["samples"] if s["text"].startswith("@")]
    structured["instruction_file_imports"] = imports
    by_cat: dict = {}
    for h in hits:
        c = by_cat.setdefault(h["category"], {"files": 0, "hit_lines": 0})
        c["files"] += 1
        c["hit_lines"] += h["hit_lines"]
    return dumps({
        "schema_version": 1,
        "scope": {
            "root": "parent repository of the constitution submodule",
            "files": list(SCAN_FILES), "dirs_recursive": list(SCAN_DIRS),
            "excluded_dir_names": list(SCAN_EXCLUDED),
            "suffixes": sorted(SCAN_SUFFIX), "max_file_bytes": MAX_BYTES,
            "note": ("read-only, bounded scan of configuration/instruction/script locations; "
                     "the AOSP tree (external/ prebuilts/ out/ and source trees) is not scanned"),
        },
        "patterns": [k for k, _ in PATTERNS],
        "structured": structured,
        "summary": {"files_with_references": len(hits), "by_category": dict(sorted(by_cat.items())),
                    "unreadable_paths_not_scanned": sorted(set(UNREADABLE))},
        "references": hits,
    })


# --------------------------------------------------------------------------- known issues
VALIDATORS = (
    ("validate_structure.py", None),
    ("validate_behavior.py", None),
    ("validate_tokens.py", None),
    ("validate_submodule.py", ("test_pinned_revision", "test_deterministic_tree")),
)


def gen_known_issues() -> str:
    rows = []
    for script, git_state in VALIDATORS:
        p = subprocess.run([sys.executable, str(PROG / script)], capture_output=True, text=True,
                           cwd=str(CONSUMER))
        lines = (p.stdout + p.stderr).splitlines()
        bad = [l for l in lines if re.match(r"(FAIL|UNCONFIRMED):", l)]
        if git_state:
            bad = [l for l in bad if not any(g in l for g in git_state)]
        rows.append((script, None if git_state else p.returncode, bad, git_state))
    out = ["# Known issues (pre-existing; found by running the existing validators)", "",
           "Generated by `progressive/gen_evidence.py`; do not edit by hand. Each section is",
           "the non-PASS output of one validator, captured at generation time.", ""]
    total = 0
    for script, rc, bad, git_state in rows:
        out.append(f"## {script}")
        out.append("")
        out.append(f"- exit code: {rc}" if rc is not None else
                   "- exit code: not recorded (the validator has git-state-dependent checks)")
        if git_state:
            out.append(f"- not snapshotted (depend on commit state, not on content): "
                       f"{', '.join(git_state)}")
        if bad:
            total += len(bad)
            out.extend(f"- `{b}`" for b in bad)
        else:
            out.append("- no FAIL or UNCONFIRMED line")
        out.append("")
    out.append("## Summary")
    out.append("")
    out.append(f"{total} non-PASS check line(s) across {len(rows)} validators. "
               "An UNCONFIRMED line is a measurement that cannot exist on this host "
               "(for example a live provider usage object), not a defect hidden as a pass. "
               "Findings about the source document are in `DISCREPANCIES.md`.")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------- index
def build_index(overrides: dict[str, bytes], prev_generated_at: str | None) -> dict:
    names = set(overrides)
    if EVD.is_dir():
        names |= {p.name for p in EVD.iterdir() if p.is_file()}
    names -= set(INDEX_EXCLUDED)
    arts = {}
    for n in sorted(names):
        data = overrides[n] if n in overrides else (EVD / n).read_bytes()
        arts[n] = {"sha256": sha256_bytes(data), "bytes": len(data),
                   "producer": PRODUCERS.get(n, "unknown")}
    return {
        "schema_version": 1,
        "artifacts": arts,
        "excluded": dict(sorted(INDEX_EXCLUDED.items())),
        "generated_at": prev_generated_at,
    }


def strip_ts(index_text: str) -> str:
    d = json.loads(index_text)
    d.pop("generated_at", None)
    return dumps(d)


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def generate(dest: Path) -> dict[str, bytes]:
    dest.mkdir(parents=True, exist_ok=True)
    out = {
        "PREFLIGHT_MANIFEST.json": gen_manifest().encode("utf-8"),
        "ANCHORS.json": gen_anchors().encode("utf-8"),
        "CONSUMERS.json": gen_consumers().encode("utf-8"),
        "KNOWN_ISSUES.md": gen_known_issues().encode("utf-8"),
    }
    for name, data in out.items():
        (dest / name).write_bytes(data)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    for need in HAND_AUTHORED:
        if not (EVD / need).is_file():
            print(f"FATAL: required hand-authored artifact missing: EVIDENCE/{need}", file=sys.stderr)
            return 2
    prev_ts = None
    idx_path = EVD / "INDEX.json"
    if idx_path.is_file():
        try:
            prev_ts = json.loads(idx_path.read_text(encoding="utf-8")).get("generated_at")
        except Exception:
            prev_ts = None

    if a.check:
        with tempfile.TemporaryDirectory() as td:
            gen = generate(Path(td))
            want_index = dumps(build_index(gen, None))
            diffs = []
            for name, data in gen.items():
                have = (EVD / name).read_bytes() if (EVD / name).is_file() else None
                if have != data:
                    diffs.append(name + (" (missing)" if have is None else " (differs)"))
            have_idx = idx_path.read_text(encoding="utf-8") if idx_path.is_file() else None
            if have_idx is None or strip_ts(have_idx) != strip_ts(want_index):
                diffs.append("INDEX.json " + ("(missing)" if have_idx is None else "(differs)"))
            if diffs:
                print("check: STALE", file=sys.stderr)
                for d in diffs:
                    print(f"  {d}", file=sys.stderr)
                return 1
            print(f"check: reproducible ({len(gen) + 1} artifact(s) regenerate byte-identically; "
                  f"INDEX.json compared without generated_at)")
            return 0

    EVD.mkdir(parents=True, exist_ok=True)
    gen = generate(EVD)
    idx = build_index(gen, prev_ts)
    if prev_ts is None or idx_path.is_file() is False or \
            strip_ts(idx_path.read_text(encoding="utf-8")) != strip_ts(dumps(idx)):
        idx["generated_at"] = now()
    idx_path.write_text(dumps(idx), encoding="utf-8")
    print(f"generated: {', '.join(gen)} + INDEX.json ({len(idx['artifacts'])} artifacts indexed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
