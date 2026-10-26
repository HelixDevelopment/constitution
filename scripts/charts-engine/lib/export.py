#!/usr/bin/env python3
# charts-engine / lib / export.py
#
# Purpose:   Four-format wrapper (§11.4.65) for a chart landing document:
#            write the Markdown landing doc next to the PNG/SVG, then render
#            HTML (pandoc) + PDF (weasyprint) siblings.
# Inputs:    a landing-doc title + body markdown + output path.
# Outputs:   <doc>.md + <doc>.html + <doc>.pdf. HTML/PDF are best-effort —
#            a missing pandoc/weasyprint is reported HONESTLY as a SKIP, never
#            a fake success (§11.4.106 ToolAbsentError discipline).
# Side-effects: writes files under the caller-provided dir ONLY; shells out to
#            pandoc + weasyprint if present on PATH.
# Dependencies: pandoc + weasyprint (optional — honest SKIP if absent).
"""Markdown landing-doc + HTML + PDF export for chart landing pages."""

import os
import shutil
import subprocess


def _tool(name):
    return shutil.which(name)


def write_landing_doc(md_path, markdown_body):
    """Write the Markdown landing doc (the source of truth for the export)."""
    os.makedirs(os.path.dirname(md_path), exist_ok=True)
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(markdown_body)
    return md_path


def formats_export_enabled():
    """True iff the constitution's ONE formats-export switch is ON (operator order 2026-10-26: Markdown is not exported
    into html/pdf/docx unless explicitly enabled; default false in config/formats_export.conf). Asked of the shared
    reader scripts/formats_export_lib.sh; a missing/unreadable reader reads as OFF (fail-closed)."""
    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "formats_export_lib.sh")
    if not os.path.isfile(lib):
        return False
    rc = subprocess.run(["bash", "-c", '. "$1" && formats_export_enabled "${FORMATS_EXPORT_ROOT:-}"', "_", lib]).returncode
    return rc == 0


def export_html_pdf(md_path):
    """Render <doc>.html (pandoc) + <doc>.pdf (weasyprint) from the Markdown.
    Returns dict {html, pdf, skipped:[...]} — `skipped` enumerates any
    unavailable tool with an honest reason (never a fabricated artefact).
    With the formats-export switch OFF (the default) nothing is rendered and `skipped` says so."""
    base = os.path.splitext(md_path)[0]
    html_path = base + ".html"
    pdf_path = base + ".pdf"
    result = {"html": None, "pdf": None, "skipped": []}
    if not formats_export_enabled():
        result["skipped"].append("html+pdf: formats-export switch is OFF (constitution/config/formats_export.conf default false; "
                                 "enable with DOCS_EXPORT=1) -- Markdown only")
        return result

    doc_dir = os.path.dirname(os.path.abspath(md_path))
    abs_md = os.path.abspath(md_path)
    abs_html = os.path.abspath(html_path)
    pandoc = _tool("pandoc")
    if pandoc:
        # Run pandoc FROM the doc directory (cwd=doc_dir) with absolute in/out
        # paths so the relative PNG references resolve, and --embed-resources
        # base64-inlines them → portable single-file HTML (§11.4.65).
        subprocess.run(
            [pandoc, abs_md, "-s", "--embed-resources",
             "--resource-path", doc_dir, "-o", abs_html],
            check=True, timeout=60, cwd=doc_dir,
        )
        result["html"] = html_path
    else:
        result["skipped"].append("html: pandoc absent on PATH")

    weasyprint = _tool("weasyprint")
    if weasyprint and result["html"]:
        subprocess.run(
            [weasyprint, html_path, pdf_path],
            check=True, timeout=60,
        )
        result["pdf"] = pdf_path
    elif not weasyprint:
        result["skipped"].append("pdf: weasyprint absent on PATH")
    elif not result["html"]:
        result["skipped"].append("pdf: skipped because html step skipped")

    return result
