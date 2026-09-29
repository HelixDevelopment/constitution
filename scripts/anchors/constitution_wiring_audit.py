#!/usr/bin/env python3
"""constitution_wiring_audit.py — per-anchor wiring-gap report.
See specs/003-reorganize-constitution-yaml/contracts/wiring-gap-checker-cli.md.
Extends constitution/scripts/mechanical/anchor_census.sh's inventory approach
(research.md R2.4) rather than reimplementing it — this tool consumes the
ALREADY-GENERATED constitution_index.yaml (Phase 3/4/5), it does not re-parse
the source constitution itself.
"""
import argparse, os, re, subprocess, sys
import yaml

# The two standing control-needle fixtures (research.md R2.3 / ATM-1036 —
# real, already-measured findings, not fabricated per W-003/W-004).
POSITIVE_CONTROL_ID = "11.4.230"
NEGATIVE_CONTROL_ID = "11.4.108"
NEGATIVE_CONTROL_CROSS_REF = "ATM-1036"
NEGATIVE_CONTROL_MIRROR = "GEMINI.md"

_EXCLUDED_MIRROR_BASENAMES = {"CLAUDE.md", "AGENTS.md", "QWEN.md", "GEMINI.md", "Constitution.md"}

# Scan-scope exclusion (added 2026-09-26 — a genuine, load-bearing performance
# defect found by ACTUALLY RUNNING this tool, never assumed acceptable from the
# plan's literal design alone): a naive per-anchor `grep -rIl <consumer_root>`
# — the plan's own literal T019 code — issues one FULL recursive traversal of
# the WHOLE repository PER ANCHOR (283+ times). On this project's real scale
# (an Android 15 AOSP checkout — a full upstream source tree, not a small
# reference repo) a SINGLE such pass was directly measured taking several
# minutes and never completing within any reasonable budget; 283 sequential
# passes is not tractable at all. Confirmed this is a genuine I/O-bound cost,
# not a grep-engine inefficiency (the host's own grep is `ugrep`, already a
# fast, SIMD-parallel implementation; the process sat in uninterruptible "D"
# disk-wait state under real measurement).
#
# Fix: (1) a SINGLE combined pass across the whole scan scope, searching for
# EVERY anchor's gate name simultaneously (one alternation regex) instead of
# one pass per anchor — see _build_gate_index; (2) an EXPLICIT, evidence-based
# exclusion of the top-level directories that are upstream AOSP vendor/build
# source, build output, or other ephemeral artifacts that could NEVER contain
# a project-governance gate implementation (every REAL gate-implementation hit
# found during this investigation lived under constitution/, docs/, specs/,
# scripts/, device/rockchip/, or tools/ — never inside any of the directories
# below). This is an ALLOWLIST-style safety choice inverted into an excludelist
# only because the excluded set is short + independently verifiable (a full
# `ls -d */` of the repository root), not because a denylist is preferred in
# general — an unrecognized NEW top-level directory is included by DEFAULT
# (never silently excluded), so this cannot silently hide a genuine gate
# implementation that lands somewhere unanticipated.
_EXCLUDED_SCAN_DIRS = {
    # Upstream AOSP vendor/source trees — never project-governance code.
    "art", "bionic", "bootable", "build", "cts", "dalvik", "developers",
    "development", "external", "frameworks", "hardware", "kernel", "kernel-5.10",
    "libcore", "libnativehelper", "packages", "pdk", "platform_testing",
    "prebuilts", "sdk", "system", "test", "toolchain", "trusty", "u-boot",
    "vendor",
    # Vendor-specific binary/firmware blobs (Rockchip toolchain + images).
    "rkbin", "rkst", "RKTools", "rockchip_images", "rockdev", "firmware",
    # Build output / logs / release artifacts — ephemeral, never source.
    "out", "logs", "flash_logs", "qa-results", "releases",
    # Tool-internal, explicitly-gitignored per-agent worktree state (added
    # 2026-09-26 — measured at 146 GB, LARGER than .git itself, and
    # confirmed via `git check-ignore -v` to be listed in .gitignore).
    # Purely duplicative of whatever the main tree already contains — a
    # gate genuinely wired in the main tree is found there directly; a
    # worktree-only copy adds scan cost and noisy, non-canonical evidence
    # paths without adding any wiring information a real consumer needs.
    ".claude",
}


# CRITICAL fix (T024 independent review, 2026-09-26): evidence acceptance
# restricted to genuine executable/source-code file extensions. Before this
# fix, ANY textual mention of a gate name outside the 5 excluded .md
# basenames counted as "IMPLEMENTED" — measured live against the real
# corpus's own 166 "IMPLEMENTED" evidence citations: 123 (74%) were `.tsv`
# data-pack ledgers (e.g. covenant_propagation_anchors.tsv, explicitly
# labelled "DATA PACK" in its own header), 7 were `.html` doc-twin exports
# of the excluded .md mirrors (_EXCLUDED_MIRROR_BASENAMES never excluded
# their .html/.pdf/.docx siblings, which are real, git-tracked files), 3
# were plain-text `.txt` ledgers — only 33 (20%) were genuine `.sh` gate
# scripts. This made the checker structurally incapable of reporting a real
# gap against this corpus (whose OWN separately-measured §11.4.227 anchor
# states "413 named CM-* gates, 241 = 58% unimplemented"), a hollow PASS of
# exactly the class this project's anti-bluff covenant (§11.4.226/§11.4.262)
# forbids in the tool built to detect that failure mode elsewhere.
_EVIDENCE_EXTENSIONS = {".sh", ".py"}  # confirmed, via direct investigation
# of every currently-real gate implementation in this corpus (constitution/
# scripts/gates/*.sh, the paired mutation-test convention, plus a real
# propagation-check inside device/rockchip/rk3588/tests/
# pre_build_verification.sh) — no gate implementation in this project is
# written in any other language; .tsv/.txt/.md/.html/.pdf/.docx are
# EXCLUDED by omission (data/doc artifacts, never executable gate code).


def _build_gate_index(consumer_root: str, gate_names: set) -> dict:
    """ONE combined recursive pass over consumer_root (minus
    _EXCLUDED_SCAN_DIRS) for ALL gate names simultaneously, returning
    {gate_name: [file_paths]}. Phase 1 finds the (small) set of files
    containing ANY gate name via one alternation-regex grep; Phase 2
    re-greps only those already-matched files (cheap — a handful of small
    text files, never the whole tree again) to attribute each hit to its
    SPECIFIC gate name(s). Evidence is accepted ONLY from files whose
    extension is in _EVIDENCE_EXTENSIONS (genuine executable/source code) —
    see the CRITICAL-fix comment above _EVIDENCE_EXTENSIONS."""
    if not gate_names:
        return {}
    exclude_flags = []
    for d in sorted(_EXCLUDED_SCAN_DIRS):
        exclude_flags += ["--exclude-dir", d]
    exclude_flags += ["--exclude-dir", ".git"]

    alternation = "|".join(re.escape(g) for g in sorted(gate_names))
    phase1 = subprocess.run(
        ["grep", "-rIlE"] + exclude_flags + [alternation, consumer_root],
        capture_output=True, text=True,
    )
    candidate_files = [
        path for path in phase1.stdout.splitlines()
        if os.path.basename(path) not in _EXCLUDED_MIRROR_BASENAMES
        and os.path.splitext(path)[1] in _EVIDENCE_EXTENSIONS
    ]

    index: dict = {g: [] for g in gate_names}
    if not candidate_files:
        return index
    for path in candidate_files:
        phase2 = subprocess.run(
            ["grep", "-lE", alternation, path],
            capture_output=True, text=True,
        )
        if phase2.returncode != 0:
            continue
        # Attribute this file to every specific gate name it actually
        # contains (a file can legitimately reference more than one gate).
        with open(path, "r", errors="ignore") as f:
            content = f.read()
        for g in gate_names:
            if g in content:
                index[g].append(path)
    return index


def _classify_anchor(anchor: dict, gate_index: dict) -> tuple[str, list[str]]:
    gate = anchor.get("propagation_gate")
    if not gate:
        return "NOT-APPLICABLE", []
    hits = gate_index.get(gate, [])
    if hits:
        return "IMPLEMENTED", hits
    return "NAMED-BUT-UNIMPLEMENTED", []


def _selftest(index: dict, gate_index: dict) -> bool:
    by_id = {a["id"]: a for a in index["anchors"]}
    if POSITIVE_CONTROL_ID not in by_id:
        sys.stderr.write(f"FATAL: positive control {POSITIVE_CONTROL_ID} not in index\n")
        return False
    status, hits = _classify_anchor(by_id[POSITIVE_CONTROL_ID], gate_index)
    if status == "NAMED-BUT-UNIMPLEMENTED":
        sys.stderr.write(
            f"FATAL: positive control {POSITIVE_CONTROL_ID} classified as a gap — "
            f"the checker cannot be trusted on real data (W-003)\n"
        )
        return False
    if NEGATIVE_CONTROL_ID not in by_id:
        sys.stderr.write(f"FATAL: negative control {NEGATIVE_CONTROL_ID} not in index\n")
        return False
    return True


def build_report(index: dict, gate_index: dict) -> str:
    lines = ["# Wiring-Gap Audit Report", ""]
    gaps, implemented, not_applicable = [], [], []
    for a in index["anchors"]:
        status, hits = _classify_anchor(a, gate_index)
        if status == "IMPLEMENTED":
            implemented.append((a, hits))
        elif status == "NAMED-BUT-UNIMPLEMENTED":
            gaps.append((a, hits))
        else:
            not_applicable.append(a)

    lines.append(f"IMPLEMENTED: {len(implemented)} · NAMED-BUT-UNIMPLEMENTED: {len(gaps)} "
                 f"· NOT-APPLICABLE: {len(not_applicable)}")
    lines.append("")
    lines.append("## Known Pre-Existing Drift (distinct from wiring gaps, W-006)")
    lines.append(f"- §{NEGATIVE_CONTROL_ID}: absent from `constitution/{NEGATIVE_CONTROL_MIRROR}` "
                 f"— lockstep-mirror gap, cross-referenced {NEGATIVE_CONTROL_CROSS_REF}, "
                 f"NOT a cross-project wiring gap.")
    lines.append("")
    lines.append("## Gaps")
    for a, hits in gaps:
        evidence = ", ".join(hits) if hits else "absent"
        lines.append(f"- §{a['id']} `{a['propagation_gate']}` — expected consumer: repository-wide "
                     f"— evidence: {evidence}")
    lines.append("")
    lines.append("## Implemented")
    for a, hits in implemented:
        lines.append(f"- §{a['id']} `{a['propagation_gate']}` — evidence: {hits[0]}")
    return "\n".join(lines) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--index", required=True)
    p.add_argument("--consumer-root", required=True)
    p.add_argument("--report", required=True)
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()

    with open(args.index) as f:
        index = yaml.safe_load(f)

    gate_names = {a["propagation_gate"] for a in index["anchors"] if a.get("propagation_gate")}
    gate_index = _build_gate_index(args.consumer_root, gate_names)

    if args.selftest and not _selftest(index, gate_index):
        sys.exit(1)

    report = build_report(index, gate_index)
    with open(args.report, "w") as f:
        f.write(report)
    print(f"wiring-gap report written to {args.report}")
    sys.exit(0)


if __name__ == "__main__":
    main()
