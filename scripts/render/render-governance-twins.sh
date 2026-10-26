#!/usr/bin/env bash
# render-governance-twins.sh — §11.4.65 export-sync: deterministically regenerate the
# governance Markdown → {.html,.docx,.pdf} "twins" so the rendered siblings never drift
# from the canonical .md (the drift that left §11.4.237 absent from the renders).
#
# Reproducible + governed pipeline (reverse-engineered + verified against the operator's
# historical renders 2026-08-07; the operator's exact <head>/OpenDesign styling is
# reproduced byte-for-byte via assets/governance-template.html5 — HEAD diff = 0 for all
# five docs). Body uses the gfm reader (matches heading-IDs, suppresses colgroup widths,
# smart off — all verified by round-trip). One documented deviation from the pre-2026-08-07
# historical renders: those passed the HTML body through a non-standard post-step that
# escaped literal `"`→`&quot;`; this pipeline emits standard pandoc output (renders
# identically). See _tests/evidence/render58/ANALYSIS.md for the full forensic proof.
#
# Determinism: SOURCE_DATE_EPOCH pins docx/pdf timestamps. Pin weasyprint==69.0 to match
# the historical PDF Producer exactly (this host has 66.0 → Producer differs, content same).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# Operator order 2026-10-26 ("stop exporting Markdown docs into other formats"): the constitution's ONE formats-export
# switch (config/formats_export.conf, default false) gates this exporter. OFF => announced skip, no twin is produced.
# shellcheck source=../formats_export_lib.sh
. "$ROOT/scripts/formats_export_lib.sh"
formats_export_gate render-governance-twins "${FORMATS_EXPORT_ROOT:-$ROOT}" || exit 0
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1785674948}"   # 2026-08-02T12:49:08Z (from historical docx core.xml)
PANDOC="${PANDOC:-pandoc}"                                    # pandoc 3.10 (3.10.1 is output-equivalent for this corpus)
TMPL="$ROOT/scripts/render/assets/governance-template.html5"  # operator head + OpenDesign styles, title/body parameterized
DOCS="${DOCS:-Constitution AGENTS CLAUDE GEMINI QWEN}"

command -v "$PANDOC" >/dev/null || { echo "FATAL: pandoc not found" >&2; exit 1; }
[ -f "$TMPL" ] || { echo "FATAL: template missing: $TMPL" >&2; exit 1; }

for d in $DOCS; do
  [ -f "$d.md" ] || { echo "skip (no source): $d.md" >&2; continue; }
  echo "[twins] $d → html/docx/pdf"
  "$PANDOC" "$d.md" -f gfm -t html5 -s \
    -M lang=en -M title="$d" -M pagetitle="$d" \
    -V pandoc-version=3.10 \
    --template="$TMPL" --wrap=auto \
    -o "$d.html"
  "$PANDOC" "$d.md" -f gfm -t docx -M lang=en -o "$d.docx"
  if command -v weasyprint >/dev/null 2>&1; then
    weasyprint "$d.html" "$d.pdf" 2>/dev/null || echo "[twins] weasyprint failed for $d (pdf skipped)" >&2
  else
    echo "[twins] weasyprint absent — $d.pdf not regenerated" >&2
  fi
done
echo "[twins] done: $DOCS"
