// export.go — the export pipeline subcommand: export.
//
// §11.4.12 / §11.4.53 / §11.4.65: `export` regenerates the full documentation
// surface from the DB single-source-of-truth:
//
//   - Issues.md + Fixed.md         — the byte-identical round-trip docs (same as
//     `sync db-to-md`).
//   - Issues_Summary.md            — §11.4.12 open-only Type×Status tally + per-
//     item one-line rows.
//   - Fixed_Summary.md             — §11.4.53 closed-only Type×ClosureStatus tally
//   - per-item one-line rows.
//   - <doc>.html / .pdf / .docx    — §11.4.65 multi-format siblings for every
//     emitted .md, produced via pandoc when the
//     tool is present.
//
// §6.J / §11.4.6 anti-bluff: the pandoc / weasyprint steps are GATED on tool
// presence (`exec.LookPath`). When the tool is absent the .md is still emitted
// and a clear, honest message is printed — NO fake .html / .pdf / .docx file is
// ever written. A consuming project's gate that asserts the siblings exist will
// then correctly FAIL on a host lacking pandoc, rather than passing against
// empty placeholders.
package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// runExport implements `export --db <p> [--out-dir <d>] [...]`.
func runExport(args []string) {
	os.Exit(exportCmd(args))
}

func exportCmd(args []string) int {
	fs := flag.NewFlagSet("export", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	outDir := fs.String("out-dir", ".", "directory to write the regenerated docs into")
	outIssues := fs.String("out-issues", "", "explicit Issues.md output path (overrides --out-dir)")
	outFixed := fs.String("out-fixed", "", "explicit Fixed.md output path (overrides --out-dir)")
	noFormats := fs.Bool("no-formats", false, "emit only Markdown; skip HTML/PDF/DOCX sibling generation")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "export: --db is required")
		return exitUsage
	}

	// HXC-201: --out-dir / --out-issues / --out-fixed are the OUTPUT-side half
	// of the same defect openDB's --db handling closes: `go run -C
	// constitution/scripts/workable-items ./cmd/workable-items export --out-dir
	// docs` — the exact form every reference site documents — relocates the
	// process cwd to this tool's own directory, so a relative --out-dir landed
	// there instead of the caller's real docs/ tree while still printing
	// success. Anchor against the invoking shell's directory the same way.
	*outDir = resolveInvocationRelative(*outDir)
	*outIssues = resolveInvocationRelative(*outIssues)
	*outFixed = resolveInvocationRelative(*outFixed)

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "export: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "export: create out-dir: %v\n", err)
		return exitUsage
	}

	issuesPath := *outIssues
	if issuesPath == "" {
		issuesPath = filepath.Join(*outDir, "Issues.md")
	}
	fixedPath := *outFixed
	if fixedPath == "" {
		fixedPath = filepath.Join(*outDir, "Fixed.md")
	}
	issuesSummaryPath := filepath.Join(filepath.Dir(issuesPath), "Issues_Summary.md")
	fixedSummaryPath := filepath.Join(filepath.Dir(fixedPath), "Fixed_Summary.md")

	// 1. Byte-identical round-trip docs (Issues.md + Fixed.md).
	issuesText, err := renderDocument(db, "Issues")
	if err != nil {
		fmt.Fprintf(os.Stderr, "export: render issues: %v\n", err)
		return exitUsage
	}
	// §11.4.44 (task #68 / BOB-108): never let the DB's own stale header
	// segment regress the Revision counter already committed on disk.
	issuesText, err = reconcileRevisionHeader(issuesText, issuesPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "export: reconcile issues revision: %v\n", err)
		return exitUsage
	}
	if err := os.WriteFile(issuesPath, []byte(issuesText), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "export: write issues: %v\n", err)
		return exitUsage
	}
	fixedText, err := renderDocument(db, "Fixed")
	if err != nil {
		fmt.Fprintf(os.Stderr, "export: render fixed: %v\n", err)
		return exitUsage
	}
	fixedText, err = reconcileRevisionHeader(fixedText, fixedPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "export: reconcile fixed revision: %v\n", err)
		return exitUsage
	}
	if err := os.WriteFile(fixedPath, []byte(fixedText), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "export: write fixed: %v\n", err)
		return exitUsage
	}

	// 2. Summary docs (§11.4.12 + §11.4.53).
	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "export: load items: %v\n", err)
		return exitUsage
	}
	issuesSummary := renderIssuesSummary(items)
	if err := os.WriteFile(issuesSummaryPath, []byte(issuesSummary), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "export: write issues summary: %v\n", err)
		return exitUsage
	}
	fixedSummary := renderFixedSummary(items)
	if err := os.WriteFile(fixedSummaryPath, []byte(fixedSummary), 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "export: write fixed summary: %v\n", err)
		return exitUsage
	}

	mdFiles := []string{issuesPath, fixedPath, issuesSummaryPath, fixedSummaryPath}
	for _, f := range mdFiles {
		fmt.Printf("export: wrote %s\n", f)
	}

	// 3. §11.4.65 multi-format siblings (HTML / PDF / DOCX) — pandoc-gated.
	if *noFormats {
		fmt.Println("export: --no-formats set; skipped HTML/PDF/DOCX sibling generation")
		return exitOK
	}

	pandoc, hasPandoc := exec.LookPath("pandoc")
	if hasPandoc != nil {
		// §6.J / §11.4.6: no fake files. Emit an honest message and exit OK —
		// the .md docs were produced; the siblings are explicitly absent.
		fmt.Println("export: pandoc not found on PATH — emitted Markdown only; " +
			"HTML/PDF/DOCX siblings NOT generated (install pandoc + weasyprint to enable)")
		return exitOK
	}

	_, weasyErr := exec.LookPath("weasyprint")
	hasWeasy := weasyErr == nil
	if !hasWeasy {
		fmt.Println("export: weasyprint not found on PATH — HTML + DOCX will be generated, " +
			"PDF will be SKIPPED (install weasyprint to enable PDF)")
	}

	failures := 0
	for _, md := range mdFiles {
		base := strings.TrimSuffix(md, ".md")
		// HTML — standalone document.
		if err := runPandoc(pandoc, md, base+".html", "--standalone"); err != nil {
			fmt.Fprintf(os.Stderr, "export: pandoc HTML %s: %v\n", md, err)
			failures++
		} else {
			fmt.Printf("export: wrote %s\n", base+".html")
		}
		// DOCX.
		if err := runPandoc(pandoc, md, base+".docx"); err != nil {
			fmt.Fprintf(os.Stderr, "export: pandoc DOCX %s: %v\n", md, err)
			failures++
		} else {
			fmt.Printf("export: wrote %s\n", base+".docx")
		}
		// PDF — only when weasyprint is present (pandoc's --pdf-engine).
		if hasWeasy {
			if err := runPandoc(pandoc, md, base+".pdf", "--pdf-engine=weasyprint"); err != nil {
				fmt.Fprintf(os.Stderr, "export: pandoc PDF %s: %v\n", md, err)
				failures++
			} else {
				fmt.Printf("export: wrote %s\n", base+".pdf")
			}
		}
	}
	if failures > 0 {
		fmt.Fprintf(os.Stderr, "export: %d sibling-format generation failure(s)\n", failures)
		return exitUsage
	}
	return exitOK
}

// runPandoc invokes pandoc <in> -o <out> [extraArgs...]. The caller has already
// verified pandoc is on PATH.
//
// --from=markdown-yaml_metadata_block (T044, SpecKit-004 "fast-dev-cycles",
// 2026-09-29 / ATM-1105): a tracker doc's item BODY content legitimately uses
// a bare '---' line as a Markdown horizontal-rule / section-separator (110
// such occurrences confirmed in docs/Issues.md alone) -- none of these files
// carries a genuine top-level YAML frontmatter block (confirmed: every
// tracker doc's header is a plain "**Field:** value" block, never
// "---\nkey: value\n---"). Pandoc's default markdown reader enables the
// yaml_metadata_block extension unconditionally, so ANY blank-line-preceded
// bare '---' anywhere in the document is sniffed as a candidate YAML block;
// most spans happen not to trip pandoc's YAML parser, but one genuinely did
// (a body span containing a bare '*' pandoc could not resolve as a YAML
// alias reference), reproducibly failing pandoc with exit 64 ("Error parsing
// YAML metadata ... while scanning an alias") for EVERY sibling format
// (HTML/DOCX/PDF) of that one document. Disabling the extension is safe for
// every tracker doc (none needs it) and closes the WHOLE defect class (any
// future body content hitting the same YAML-alias edge case), not just
// today's one instance -- verified directly against the real
// docs/Issues.md before this change (exit 0, real 2.5MB HTML produced).
func runPandoc(pandoc, in, out string, extraArgs ...string) error {
	args := append([]string{"--from=markdown-yaml_metadata_block", in, "-o", out}, extraArgs...)
	cmd := exec.Command(pandoc, args...)
	combined, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(combined)))
	}
	return nil
}

// renderIssuesSummary produces the §11.4.12 open-only summary: a Type×Status
// tally over items still in the Issues tracker, plus a per-item one-line table.
func renderIssuesSummary(items []item) string {
	var open []item
	for _, it := range items {
		if it.CurrentLocation == "Issues" {
			open = append(open, it)
		}
	}
	var b strings.Builder
	b.WriteString("# Issues_Summary\n\n")
	b.WriteString("Open workable items (current_location = Issues), regenerated from the SQLite single-source-of-truth (§11.4.12).\n\n")
	b.WriteString(renderTypeStatusTally(open))
	b.WriteString("\n")
	b.WriteString(renderItemRows(open))
	return b.String()
}

// renderFixedSummary produces the §11.4.53 closed-only summary: a Type×Closure-
// Status tally over items in the Fixed tracker, plus a per-item one-line table.
func renderFixedSummary(items []item) string {
	var closed []item
	for _, it := range items {
		if it.CurrentLocation == "Fixed" {
			closed = append(closed, it)
		}
	}
	var b strings.Builder
	b.WriteString("# Fixed_Summary\n\n")
	b.WriteString("Closed workable items (current_location = Fixed), regenerated from the SQLite single-source-of-truth (§11.4.53).\n\n")
	b.WriteString(renderTypeStatusTally(closed))
	b.WriteString("\n")
	b.WriteString(renderFixedItemRows(closed))
	return b.String()
}

// renderTypeStatusTally renders a `Type | Status | Count` table sorted by Type
// then Status, with a TOTAL row — the §11.4.12 / §11.4.53 counts-by-Type×Status.
func renderTypeStatusTally(items []item) string {
	type key struct{ typ, status string }
	counts := map[key]int{}
	for _, it := range items {
		counts[key{it.Type, it.Status}]++
	}
	keys := make([]key, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].typ != keys[j].typ {
			return keys[i].typ < keys[j].typ
		}
		return keys[i].status < keys[j].status
	})

	var b strings.Builder
	b.WriteString("## Counts by Type × Status\n\n")
	b.WriteString("| Type | Status | Count |\n")
	b.WriteString("|---|---|---|\n")
	total := 0
	for _, k := range keys {
		fmt.Fprintf(&b, "| %s | %s | %d |\n", k.typ, k.status, counts[k])
		total += counts[k]
	}
	fmt.Fprintf(&b, "| **TOTAL** | | **%d** |\n", total)
	return b.String()
}

// renderItemRows renders a per-item one-line table sorted by ATM ID. Columns
// match the §11.4.54 ATM-ID-leftmost + §11.4.15/16 Status/Type convention.
func renderItemRows(items []item) string {
	rows := make([]item, len(items))
	copy(rows, items)
	sort.Slice(rows, func(i, j int) bool { return rows[i].AtmID < rows[j].AtmID })

	var b strings.Builder
	b.WriteString("## Items\n\n")
	b.WriteString("| ATM ID | Type | Status | Severity | Description |\n")
	b.WriteString("|---|---|---|---|---|\n")
	for _, it := range rows {
		sev := it.Severity
		if sev == "" {
			sev = "—"
		}
		fmt.Fprintf(&b, "| %s | %s | %s | %s | %s |\n",
			it.AtmID, it.Type, it.Status, sev, summaryDescription(it))
	}
	return b.String()
}

// renderFixedItemRows renders the §11.4.53 closed-archive per-item table with the
// §11.4.19 column-aligned header the CM-FIXED-COLUMN-ALIGNMENT pre-build gate AND
// the canonical shell generator scripts/testing/generate_fixed_summary.sh require:
//
//	| # | Level | Status | Type | Fixed-In Tag(s) | One-line description |
//
// This is DISTINCT from renderItemRows (which the open-tracker Issues_Summary
// uses) so the closed archive carries the version-tag column (feature 2026-05-30)
// WITHOUT changing the Issues_Summary layout. The leftmost column is a 1-based
// row number `#` (matching the gate), so the §11.4.54 stable ATM ID is carried
// INSIDE the One-line description cell (`<ATM-ID> — <desc>`) — the same place the
// shell generator surfaces it (via the item heading) — keeping the id visible +
// keeping the export_test WIT-NNN assertions satisfied.
func renderFixedItemRows(items []item) string {
	rows := make([]item, len(items))
	copy(rows, items)
	sort.Slice(rows, func(i, j int) bool { return rows[i].AtmID < rows[j].AtmID })

	var b strings.Builder
	b.WriteString("## Items\n\n")
	b.WriteString("| # | Level | Status | Type | Fixed-In Tag(s) | One-line description |\n")
	b.WriteString("|---|---|---|---|---|---|\n")
	for i, it := range rows {
		level := it.Severity
		if level == "" {
			level = "—"
		}
		// §11.4.6 (no fabrication): the Fixed-In release tag(s) come from the DERIVED
		// items.version_tags column (populated out-of-band by the `version-tags`
		// subcommand). loadItems does not load that optional column (it is absent on
		// pre-migration consumer DBs), and it is currently unpopulated on this tree,
		// so the honest render is the em-dash placeholder — never an invented tag.
		// The canonical shell generator likewise emits "—" when version_tags is
		// empty, so the two producers stay column-aligned.
		fixedInTag := "—"
		desc := it.AtmID + " — " + summaryDescription(it)
		fmt.Fprintf(&b, "| %d | %s | %s | %s | %s | %s |\n",
			i+1, level, it.Status, it.Type, fixedInTag, desc)
	}
	return b.String()
}

// fixedPipeTableHeader is the canonical Fixed.md closure-table header (GAP B),
// matching the live docs/Fixed.md:
//
//	| Closure | Title | Type | Status | Round | Commit(s) | Evidence |
//	|---|---|---|---|---|---|---|
const fixedPipeTableHeader = "| Closure | Title | Type | Status | Round | Commit(s) | Evidence |\n" +
	"|---|---|---|---|---|---|---|\n"

// renderClosurePipeRow (GAP B) SYNTHESIZES a single Fixed.md pipe-table closure
// row from an item's stored DB fields — the db→md direction that lets the binary
// regenerate a pipe row that exists in the DB but has no raw body_md to replay
// (the conductor's reconcile path for the ~74 missing pipe rows). Cells are the
// §11.4.93 closure metadata; the Title cell follows the live `<ID>: <title>`
// convention; the Evidence cell uses the closure_criteria when present. Pipes in
// any cell are escaped so the table stays well-formed.
//
// The trailing newline makes the row directly concatenable under
// fixedPipeTableHeader. A field absent in the DB renders as the em-dash
// placeholder the live docs use, never an empty cell that breaks column count.
func renderClosurePipeRow(it item) string {
	cell := func(s string) string {
		s = strings.ReplaceAll(s, "\n", " ")
		s = strings.ReplaceAll(s, "|", "\\|")
		s = strings.TrimSpace(s)
		if s == "" {
			return "—"
		}
		return s
	}
	titleCell := it.AtmID + ": " + strings.TrimSpace(it.Title)
	evidence := it.ClosureCriteria
	return fmt.Sprintf("| %s | %s | %s | %s | %s | %s | %s |\n",
		cell(it.ClosureDate), cell(titleCell), cell(it.Type), cell(it.Status),
		cell(it.Round), cell(it.CommitRef), cell(evidence))
}

// summaryDescription returns a §11.4.91-clarity one-line description (single line,
// pipes escaped so the Markdown table stays well-formed).
func summaryDescription(it item) string {
	d := it.Description
	if strings.TrimSpace(d) == "" {
		d = it.Title
	}
	d = strings.ReplaceAll(d, "\n", " ")
	d = strings.ReplaceAll(d, "|", "\\|")
	return strings.TrimSpace(d)
}
