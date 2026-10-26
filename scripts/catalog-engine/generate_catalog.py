#!/usr/bin/env python3
# catalog-engine / generate_catalog.py
#
# Purpose:   Universal TEST CATALOG engine entry point (BG-006, P1). Scans the
#            INJECTED test roots, derives the §2 record schema per source file,
#            annotates git dates + taxonomy cluster/component, and emits
#            catalog.json + a hierarchical Markdown catalog + a self-contained
#            interactive HTML page (+ PDF/DOCX siblings ride the shared export
#            pipeline). ZERO consumer-project specifics — roots + taxonomy are
#            passed at runtime (§11.4.28 decoupled).
# Usage:     python3 generate_catalog.py --roots <yaml|json> --taxonomy <yaml>
#                                          --git-repo <path> --out <dir>
#                                          [--title <str>] [--check-only]
# Inputs:    --roots (root specs: list of {root,type,glob}), --taxonomy,
#            --git-repo, --out (all required); --title optional.
# Outputs:   <out>/catalog.json + <out>/Catalog.md + <out>/index.html
#            (+ Catalog.html/.pdf via the shared exporter when present).
# Side-effects: writes only under <out>/.
# Dependencies: lib/{scan,parse_shell,derive,gitmeta,render}.py; pandoc+
#            weasyprint (optional — honest SKIP if absent).
# Cross-refs: docs/research/test_catalog/P0_design.md, P1_generator_report.md.
"""Universal TEST CATALOG engine — P1 generator."""

import argparse
import datetime
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "lib"))

import scan  # noqa: E402
import derive  # noqa: E402
import gitmeta  # noqa: E402
import render  # noqa: E402


def _utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")


def _load_roots(path):
    """Load root specs from JSON or a flat YAML list of '- root: ... type: ...'.
    Returns a list of {root,type,glob} dicts."""
    text = open(path, "r", encoding="utf-8").read()
    if path.endswith(".json"):
        data = json.loads(text)
        return data["roots"] if isinstance(data, dict) else data
    # flat YAML: each spec starts on a '- <key>: <val>' list item (the first
    # inline key — e.g. 'root:' for a glob spec or 'file:' for a single-file
    # spec) and continues with indented 'key: val' siblings until the next
    # '- ' item. A leading 'roots:' section header is ignored.
    specs = []
    cur = None
    for raw in text.splitlines():
        ln = raw.rstrip()
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        m = re.match(r"^\s*-\s*([A-Za-z_]\w*):\s*(.+)$", ln)
        if m:
            if cur:
                specs.append(cur)
            cur = {m.group(1).strip(): _unquote(m.group(2).strip())}
            continue
        m = re.match(r"^\s+([A-Za-z_]\w*):\s*(.+)$", ln)
        if m and cur is not None:
            cur[m.group(1)] = _unquote(m.group(2).strip())
    if cur:
        specs.append(cur)
    return specs


def _unquote(v):
    """Strip a single matched pair of surrounding quotes from a flat-YAML
    scalar (e.g. glob: '*.sh' -> *.sh) so fnmatch sees the literal pattern."""
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    return v


def _corpus_fingerprint(records):
    """§11.4.86 drift-proof corpus fingerprint = sha256 of the sorted DISTINCT
    source-file list (the test-file roster), NOT per-record source_paths. A
    multi-record-per-file source (a gate/mutation file emits hundreds of
    records all sharing one path) must contribute its path ONCE — otherwise the
    fingerprint depends on record COUNT (a derivation detail), not on the corpus
    membership the §11.4.86 freshness gate is meant to track."""
    import hashlib
    payload = "\n".join(sorted({r["source_path"] for r in records}))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _join_gate_mutation(records):
    """§1.1 catalog relationship: link each pre-build-gate to its paired
    meta-test mutation (the mutation that proves the gate is not a bluff gate).
    Mutation records carry `pairs_gate`; gate records get `paired_mutation`
    set to the mutation id when a pair exists. Returns the pair count."""
    mut_by_gate = {}
    for r in records:
        if r.get("type") == "meta-test-mutation" and r.get("pairs_gate"):
            mut_by_gate.setdefault(r["pairs_gate"], r["id"])
    paired = 0
    for r in records:
        if r.get("type") == "pre-build-gate":
            mid = mut_by_gate.get(r["id"])
            if mid:
                r["paired_mutation"] = mid
                paired += 1
            else:
                r["derivation_gaps"].append("no-paired-mutation")
    return paired


def generate(roots_path, taxonomy_path, repo, out_dir, title, check_only=False):
    os.makedirs(out_dir, exist_ok=True)
    root_specs = _load_roots(roots_path)
    taxonomy = derive.load_taxonomy(taxonomy_path)
    date_index = gitmeta.build_date_index(repo)
    records = scan.scan_roots(root_specs, repo, taxonomy, date_index)
    gate_mutation_pairs = _join_gate_mutation(records)
    records.sort(key=lambda r: (r["type"], r["cluster"], r["component"], r["id"]))

    meta = {"title": title, "generated_at": _utc_now(),
            "fingerprint": _corpus_fingerprint(records)}

    # per-type breakdown (§11.4.6 — mechanical census, never estimated)
    by_type = {}
    for r in records:
        t = r["type"]
        d = by_type.setdefault(t, {"records": 0, "bluff_proofed": 0,
                                   "physical_evidence": 0})
        d["records"] += 1
        d["bluff_proofed"] += 1 if r["bluff_proofed"] else 0
        d["physical_evidence"] += 1 if r["physical_evidence"] else 0

    # gap census (honest backfill worklist)
    gap_census = {}
    for r in records:
        for g in r["derivation_gaps"]:
            gap_census[g] = gap_census.get(g, 0) + 1

    summary = {
        "records": len(records),
        "by_type": by_type,
        "bluff_proofed": sum(1 for r in records if r["bluff_proofed"]),
        "physical_evidence": sum(1 for r in records if r["physical_evidence"]),
        "with_derivation_gaps": sum(1 for r in records if r["derivation_gaps"]),
        "gate_mutation_pairs": gate_mutation_pairs,
        "gap_census": dict(sorted(gap_census.items(),
                                  key=lambda kv: -kv[1])),
        "feature_class_set": sorted(
            {r["feature_class"] for r in records if r["feature_class"]}),
        "clusters": sorted({r["cluster"] for r in records}),
        "fingerprint": meta["fingerprint"],
        "generated_at": meta["generated_at"],
    }

    if check_only:
        return {"summary": summary, "records": records, "meta": meta}

    catalog_json = os.path.join(out_dir, "catalog.json")
    with open(catalog_json, "w", encoding="utf-8") as fh:
        json.dump({"meta": meta, "summary": summary, "records": records},
                  fh, indent=2, ensure_ascii=False)

    md = render.render_markdown(records, meta)
    md_path = os.path.join(out_dir, "Catalog.md")
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(md)

    html = render.render_html(records, meta)
    html_path = os.path.join(out_dir, "index.html")
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(html)

    summary.update({
        "catalog_json": os.path.relpath(catalog_json, out_dir),
        "markdown": os.path.relpath(md_path, out_dir),
        "interactive_html": os.path.relpath(html_path, out_dir),
        "note_pdf_docx": "ride the shared §11.4.65 export pipeline "
                         "(sync_all_markdown_exports.sh) on Catalog.md, ONLY while the "
                         "formats-export switch is ON (default OFF, operator order 2026-10-26)",
    })
    return {"summary": summary, "records": records, "meta": meta}


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Universal TEST CATALOG engine (BG-006 P1).")
    ap.add_argument("--roots", required=True)
    ap.add_argument("--taxonomy", required=True)
    ap.add_argument("--git-repo", required=True, dest="repo")
    ap.add_argument("--out", required=True)
    ap.add_argument("--title", default="tests")
    ap.add_argument("--check-only", action="store_true")
    ap.add_argument("--print-fingerprint", action="store_true",
                    help="emit ONLY the corpus fingerprint (sorted-source-path "
                         "sha256) and exit — the §11.4.86 freshness probe.")
    args = ap.parse_args(argv)
    if args.print_fingerprint:
        res = generate(args.roots, args.taxonomy, args.repo, args.out,
                       args.title, check_only=True)
        print(res["meta"]["fingerprint"])
        return 0
    res = generate(args.roots, args.taxonomy, args.repo, args.out,
                   args.title, args.check_only)
    print(json.dumps(res["summary"], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
