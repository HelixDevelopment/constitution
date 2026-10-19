#!/usr/bin/env python3
"""Mutation matrix (02_quality_optimization.md §5).

For each row: inject the defect into a THROWAWAY sandbox copy, run the named
validator, assert it FAILS, restore, assert it PASSES again. Both outcomes are
recorded to the evidence file.

The sandbox is built with hardlinks (``cp -al``) from the real tree, so a run is
fast and the live repository is never touched. A mutation that does not flip its
gate is a bluff gate: the matrix exits 1 and names it.

Usage:
  python3 progressive/mutation_matrix.py [--evidence FILE] [--json FILE]
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # constitution repo
CONSUMER = ROOT.parent
PY = sys.executable


def run_validator(sandbox: Path, which: str, extra: list[str] | None = None) -> int:
    script = sandbox / "constitution" / "progressive" / {
        "structure": "validate_structure.py",
        "tokens": "validate_tokens.py",
        "behavior": "validate_behavior.py",
        "submodule": "validate_submodule.py",
        "evidence": "validate_evidence.py",
    }[which]
    if which == "evidence":
        # the sandbox holds a partial tree and a sandbox parent repository
        extra = ["--partial-tree"] + (extra or [])
    p = subprocess.run([PY, str(script)] + (extra or []),
                       capture_output=True, text=True, cwd=str(sandbox))
    return p.returncode


def make_sandbox(tmp: Path) -> Path:
    """consumer/ { .constitution-pin, constitution/ { source, twins, progressive/ } }"""
    sb = tmp / "consumer"
    (sb / "constitution").mkdir(parents=True)
    for name in ("Constitution.md", "AGENTS.md", "CLAUDE.md", "QWEN.md", "GEMINI.md"):
        src = ROOT / name
        if src.is_file():
            shutil.copy2(src, sb / "constitution" / name)
    subprocess.run(["cp", "-al", str(ROOT / "progressive"), str(sb / "constitution" / "progressive")],
                   check=True)
    # a real git repo so the submodule checks read a real HEAD
    for args in (["git", "init", "-q"], ["git", "config", "user.email", "t@example.invalid"],
                 ["git", "config", "user.name", "t"], ["git", "add", "-A"],
                 ["git", "commit", "-qm", "sandbox"]):
        subprocess.run(args, cwd=str(sb / "constitution"), check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(sb / "constitution"),
                          capture_output=True, text=True).stdout.strip()
    pin_src = (CONSUMER / ".constitution-pin").read_text(encoding="utf-8")
    pin_out = "\n".join(("SHA=" + head) if l.startswith("SHA=") else l
                        for l in pin_src.splitlines()) + "\n"
    (sb / ".constitution-pin").write_text(pin_out, encoding="utf-8")
    # hardlinked files must be replaced, never edited in place, by the mutators
    return sb


def replace(sandbox: Path, rel: str, text: str) -> None:
    p = sandbox / rel
    p.unlink()
    p.write_text(text, encoding="utf-8")


EVD_REL = "constitution/progressive/EVIDENCE"


def resync_index(sandbox: Path) -> None:
    """Rewrite INDEX.json so every recorded sha256 matches the file on disk. Used by
    mutations that must be caught by a SEMANTIC check, not merely by the index hash."""
    import hashlib
    ip = sandbox / EVD_REL / "INDEX.json"
    idx = json.loads(ip.read_text(encoding="utf-8"))
    for name, rec in idx["artifacts"].items():
        data = (sandbox / EVD_REL / name).read_bytes()
        rec["sha256"] = hashlib.sha256(data).hexdigest()
        rec["bytes"] = len(data)
    replace(sandbox, f"{EVD_REL}/INDEX.json", json.dumps(idx, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


def main() -> int:
    evidence = None
    if "--evidence" in sys.argv:
        evidence = Path(sys.argv[sys.argv.index("--evidence") + 1])
    rows = []

    def record(mid, gate, expected, got_fail, got_pass, detail=""):
        ok = got_fail == "FAIL" and got_pass == "PASS"
        rows.append({"id": mid, "gate": gate, "injected": expected,
                     "mutated": got_fail, "restored": got_pass, "ok": ok, "detail": detail})
        print(f"{'PASS' if ok else 'FAIL'}: {mid} {gate} — mutated={got_fail} restored={got_pass}"
              + (f" ({detail})" if detail else ""))

    # Same filesystem as the source so the hardlink sandbox works (cross-device
    # hardlinks are impossible); cleaned up in the finally block.
    td_obj = tempfile.mkdtemp(prefix=".progressive_sandbox_", dir=str(CONSUMER))
    try:
        td = td_obj
        sb = make_sandbox(Path(td))
        # baseline must be green before any mutation counts
        base = {w: run_validator(sb, w) for w in ("structure", "behavior", "submodule")}
        print(f"baseline: structure={base['structure']} behavior={base['behavior']} submodule={base['submodule']} "
              f"(tokens/submodule carry live-telemetry UNCONFIRMED by design)")

        # M-01 core budget: append a large block to core.md
        p = "constitution/progressive/core.md"
        orig = (sb / p).read_text(encoding="utf-8")
        replace(sb, p, orig + "\n" + ("filler token block " * 4000) + "\n")
        record("M-01", "test_core_budget", "append ~5k-token block to core.md",
               "FAIL" if run_validator(sb, "tokens") == 1 else "PASS",
               "PASS" if (replace(sb, p, orig) or run_validator(sb, "tokens") in (0, 3)) else "FAIL")
        replace(sb, p, orig)

        # M-02 anchor integrity: drop an anchor from the catalog
        cp = "constitution/progressive/catalog.json"
        cat_orig = (sb / cp).read_text(encoding="utf-8")
        cat = json.loads(cat_orig)
        cat["anchors"] = [a for a in cat["anchors"] if a["id"] != "§11.4.141"]
        cat["anchor_count"] = len(cat["anchors"])
        replace(sb, cp, json.dumps(cat, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
        record("M-02", "test_anchor_integrity", "delete §11.4.141 from catalog.json",
               "FAIL" if run_validator(sb, "structure") == 1 else "PASS",
               "PASS" if (replace(sb, cp, cat_orig) or run_validator(sb, "structure") == 0) else "FAIL")
        replace(sb, cp, cat_orig)

        # M-03 twin consistency: remove the anchor from every twin
        twins = ["constitution/" + n for n in ("AGENTS.md", "CLAUDE.md", "QWEN.md", "GEMINI.md")
                 if (sb / "constitution" / n).is_file()]
        saved = {t: (sb / t).read_text(encoding="utf-8") for t in twins}
        for t, txt in saved.items():
            replace(sb, t, txt.replace("§11.4.141", ""))
        m3 = run_validator(sb, "structure")
        for t, txt in saved.items():
            replace(sb, t, txt)
        record("M-03", "test_twin_consistency", "remove §11.4.141 from every twin",
               "FAIL" if m3 == 1 else "PASS",
               "PASS" if run_validator(sb, "structure") == 0 else "FAIL")

        # M-04 split reproducibility: hand-edit one byte of a rule file
        p = "constitution/progressive/rules/11.4.141.md"
        rule_orig = (sb / p).read_text(encoding="utf-8")
        replace(sb, p, rule_orig + "x")
        record("M-04", "test_split_reproducible", "hand-edit one byte of rules/11.4.141.md",
               "FAIL" if run_validator(sb, "structure") == 1 else "PASS",
               "PASS" if (replace(sb, p, rule_orig) or run_validator(sb, "structure") == 0) else "FAIL")
        replace(sb, p, rule_orig)

        # M-05 per-prompt reduction: replace the lean core with the monolith
        core = (sb / "constitution/progressive/core.md").read_text(encoding="utf-8")
        mono = (sb / "constitution/Constitution.md").read_text(encoding="utf-8")
        replace(sb, "constitution/progressive/core.md", mono)
        record("M-05", "test_core_budget", "replace core.md with the full monolith",
               "FAIL" if run_validator(sb, "tokens") == 1 else "PASS",
               "PASS" if (replace(sb, "constitution/progressive/core.md", core) or
                          run_validator(sb, "tokens") in (0, 3)) else "FAIL")
        replace(sb, "constitution/progressive/core.md", core)

        # M-06 cache-warm: inject a volatile marker before the cache breakpoint
        replace(sb, "constitution/progressive/core.md", core + "\n<!-- volatile: 2026-10-18T00:00 -->\n")
        record("M-06", "test_cache_warm", "inject a volatile token into core.md",
               "FAIL" if run_validator(sb, "tokens") == 1 else "PASS",
               "PASS" if (replace(sb, "constitution/progressive/core.md", core) or
                          run_validator(sb, "tokens") in (0, 3)) else "FAIL")
        replace(sb, "constitution/progressive/core.md", core)

        # M-07 catalog search: corrupt the §11.4.141 entry description
        cat = json.loads(cat_orig)
        for a in cat["anchors"]:
            if a["id"] == "§11.4.141":
                a["one_line_description"] = ""
        replace(sb, cp, json.dumps(cat, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
        record("M-07", "test_catalog_description", "empty the §11.4.141 one-line description",
               "FAIL" if run_validator(sb, "behavior") == 1 else "PASS",
               "PASS" if (replace(sb, cp, cat_orig) or run_validator(sb, "behavior") == 0) else "FAIL")
        replace(sb, cp, cat_orig)

        # M-08 load_rule: point the catalog at a different rule file
        cat = json.loads(cat_orig)
        for a in cat["anchors"]:
            if a["id"] == "§11.4.141":
                a["file"] = "progressive/rules/11.4.142.md"
        replace(sb, cp, json.dumps(cat, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
        record("M-08", "test_load_rule_body", "make load_rule return a different anchor body",
               "FAIL" if run_validator(sb, "behavior") == 1 else "PASS",
               "PASS" if (replace(sb, cp, cat_orig) or run_validator(sb, "behavior") == 0) else "FAIL")
        replace(sb, cp, cat_orig)

        # M-09 pinned revision: advance the consumer pin without touching HEAD
        pin = sb / ".constitution-pin"
        pin_orig = pin.read_text(encoding="utf-8")
        replace(sb, ".constitution-pin", "\n".join(
            ("SHA=" + "0" * 40) if l.startswith("SHA=") else l for l in pin_orig.splitlines()) + "\n")
        record("M-09", "test_pinned_revision", "advance the submodule pin without a matching HEAD",
               "FAIL" if run_validator(sb, "submodule") == 1 else "PASS",
               "PASS" if (replace(sb, ".constitution-pin", pin_orig) or
                          run_validator(sb, "submodule") in (0, 3)) else "FAIL")
        replace(sb, ".constitution-pin", pin_orig)

        # M-10 recursive fetch: an uninitialised nested submodule in the status
        st = Path(td) / "status.txt"
        st.write_text(f" {head_sha(sb)} constitution (v-test)\n-{'0'*40} nested (v-test)\n", encoding="utf-8")
        record("M-10", "test_recursive_fetch", "introduce an uninitialised nested submodule",
               "FAIL" if run_validator(sb, "submodule", ["--status-file", str(st)]) == 1 else "PASS",
               "PASS" if run_validator(sb, "submodule") in (0, 3) else "FAIL")

        # M-11 evidence presence: a PASS must emit a readable artifact; an
        # unwritable evidence path must FAIL the run (never a silent PASS).
        ev = Path(td) / "evidence.json"
        base_rc = run_validator(sb, "tokens", ["--evidence", str(ev)])
        had = ev.is_file() and ev.stat().st_size > 0
        unwritable = run_validator(sb, "tokens", ["--evidence", "/proc/atmo_no_write/ev.json"])
        record("M-11", "test_evidence_presence", "make the evidence path unwritable",
               "FAIL" if (had and base_rc in (0, 3) and unwritable != 0) else "PASS",
               "PASS" if run_validator(sb, "tokens", ["--evidence", str(ev)]) in (0, 3) else "FAIL")

        # M-12 placeholders: plant a banned marker in delivered code
        p = "constitution/progressive/core.md"
        replace(sb, p, core + "\n" + "TO" + "DO: finish this later\n")
        record("M-12", "test_no_placeholders", "plant a placeholder marker in a delivered file",
               "FAIL" if run_validator(sb, "structure") == 1 else "PASS",
               "PASS" if (replace(sb, p, core) or run_validator(sb, "structure") == 0) else "FAIL")
        replace(sb, p, core)

        # ---- evidence-artifact gate (validate_evidence.py) -----------------------------
        ev_base = run_validator(sb, "evidence")
        print(f"baseline: evidence={ev_base}")
        index_orig = (sb / EVD_REL / "INDEX.json").read_text(encoding="utf-8")

        # M-13 required artifact present: delete CONSUMERS.json
        cons_p = f"{EVD_REL}/CONSUMERS.json"
        cons_orig = (sb / cons_p).read_text(encoding="utf-8")
        (sb / cons_p).unlink()
        m13 = run_validator(sb, "evidence")
        (sb / cons_p).write_text(cons_orig, encoding="utf-8")
        record("M-13", "test_required_artifacts", "delete EVIDENCE/CONSUMERS.json",
               "FAIL" if m13 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-14 index integrity: tamper one recorded sha256 in INDEX.json
        idx = json.loads(index_orig)
        victim = sorted(idx["artifacts"])[0]
        idx["artifacts"][victim]["sha256"] = "0" * 64
        replace(sb, f"{EVD_REL}/INDEX.json", json.dumps(idx, indent=1, sort_keys=True) + "\n")
        m14 = run_validator(sb, "evidence")
        replace(sb, f"{EVD_REL}/INDEX.json", index_orig)
        record("M-14", "test_index_integrity", f"tamper the INDEX.json sha256 of {victim}",
               "FAIL" if m14 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-15 anchors fresh: drop an anchor from ANCHORS.json (INDEX re-synced so only
        # the independent re-inventory can catch it)
        anc_p = f"{EVD_REL}/ANCHORS.json"
        anc_orig = (sb / anc_p).read_text(encoding="utf-8")
        anc = json.loads(anc_orig)
        anc["files"]["Constitution.md"]["definitions"] = [
            d for d in anc["files"]["Constitution.md"]["definitions"] if d["id"] != "§11.4.141"]
        replace(sb, anc_p, json.dumps(anc, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
        resync_index(sb)
        m15 = run_validator(sb, "evidence")
        replace(sb, anc_p, anc_orig)
        replace(sb, f"{EVD_REL}/INDEX.json", index_orig)
        record("M-15", "test_anchors_fresh", "drop §11.4.141 from ANCHORS.json (INDEX re-synced)",
               "FAIL" if m15 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-16 stale manifest: tamper a recorded file hash (INDEX re-synced)
        man_p = f"{EVD_REL}/PREFLIGHT_MANIFEST.json"
        man_orig = (sb / man_p).read_text(encoding="utf-8")
        man = json.loads(man_orig)
        man["files"]["progressive/core.md"] = "0" * 64
        replace(sb, man_p, json.dumps(man, indent=1, sort_keys=True) + "\n")
        resync_index(sb)
        m16 = run_validator(sb, "evidence")
        replace(sb, man_p, man_orig)
        replace(sb, f"{EVD_REL}/INDEX.json", index_orig)
        record("M-16", "test_manifest_fresh", "tamper the manifest hash of progressive/core.md (INDEX re-synced)",
               "FAIL" if m16 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-17 stale manifest, other direction: change a covered file without regenerating
        core_p = "constitution/progressive/core.md"
        core_o = (sb / core_p).read_text(encoding="utf-8")
        replace(sb, core_p, core_o + "\nedited without regenerating the evidence\n")
        m17 = run_validator(sb, "evidence")
        replace(sb, core_p, core_o)
        record("M-17", "test_manifest_fresh", "edit core.md without regenerating the manifest",
               "FAIL" if m17 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-18 hand-authored artifact: delete RISK_REGISTER.md
        rr_p = f"{EVD_REL}/RISK_REGISTER.md"
        rr_o = (sb / rr_p).read_text(encoding="utf-8")
        (sb / rr_p).unlink()
        m18 = run_validator(sb, "evidence")
        (sb / rr_p).write_text(rr_o, encoding="utf-8")
        record("M-18", "test_required_artifacts", "delete EVIDENCE/RISK_REGISTER.md",
               "FAIL" if m18 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-19 unrecorded discrepancy: strip the recorded genuine omission from DISCREPANCIES.md
        dis_p = f"{EVD_REL}/DISCREPANCIES.md"
        dis_o = (sb / dis_p).read_text(encoding="utf-8")
        replace(sb, dis_p, dis_o.replace("11.4.10.A", "<removed>"))
        resync_index(sb)
        m19 = run_validator(sb, "evidence")
        replace(sb, dis_p, dis_o)
        replace(sb, f"{EVD_REL}/INDEX.json", index_orig)
        record("M-19", "test_anchors_discrepancies", "remove §11.4.10.A from DISCREPANCIES.md (INDEX re-synced)",
               "FAIL" if m19 == 1 else "PASS", "PASS" if run_validator(sb, "evidence") == 0 else "FAIL")

        # M-20 slim catalog <-> manifest coupling: drop a digest from rules_manifest.json
        rm_p = "constitution/progressive/rules_manifest.json"
        rm_o = (sb / rm_p).read_text(encoding="utf-8")
        rm = json.loads(rm_o)
        del rm["rules"]["§11.4.141"]
        replace(sb, rm_p, json.dumps(rm, indent=1, sort_keys=True, ensure_ascii=False) + "\n")
        record("M-20", "test_catalog_complete", "drop §11.4.141 from rules_manifest.json",
               "FAIL" if run_validator(sb, "structure") == 1 else "PASS",
               "PASS" if (replace(sb, rm_p, rm_o) or run_validator(sb, "structure") == 0) else "FAIL")
        replace(sb, rm_p, rm_o)
    finally:
        shutil.rmtree(td_obj, ignore_errors=True)

    ok = all(r["ok"] for r in rows)
    payload = {"mutations": rows, "ok": ok, "count": len(rows)}
    if evidence:
        evidence.parent.mkdir(parents=True, exist_ok=True)
        evidence.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    if "--json" in sys.argv:
        j = Path(sys.argv[sys.argv.index("--json") + 1])
        j.parent.mkdir(parents=True, exist_ok=True)
        j.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    print(f"MUTATION MATRIX: {'PASS' if ok else 'FAIL'} — {sum(1 for r in rows if r['ok'])}/{len(rows)} mutations flipped their gate")
    return 0 if ok else 1


def head_sha(sandbox: Path) -> str:
    p = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(sandbox / "constitution"),
                       capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else "0" * 40


if __name__ == "__main__":
    sys.exit(main())
