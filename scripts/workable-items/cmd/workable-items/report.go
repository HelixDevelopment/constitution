// report.go — the read-only query subcommand: report.
//
// §11.4.93 + §11.4.95(J): `report` is a read-only DB query surface, orthogonal
// to build. It groups items by type / status / severity, or runs the §11.4.90
// obsolete audit. Output is a stable, sorted, plain-text tally suitable for CI
// logs and operator review.
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

// runReport implements `report [--by-type|--by-status|--by-severity|
// --obsolete-audit] --db <p>`. Exactly one grouping flag selects the view;
// --by-status is the default when none is given.
func runReport(args []string) {
	os.Exit(reportCmd(args))
}

func reportCmd(args []string) int {
	fs := flag.NewFlagSet("report", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	byType := fs.Bool("by-type", false, "group counts by Type")
	byStatus := fs.Bool("by-status", false, "group counts by Status (default)")
	bySeverity := fs.Bool("by-severity", false, "group counts by Severity")
	byAssigned := fs.Bool("by-assigned", false, "group counts by Assigned-To (§11.4.104)")
	byCreator := fs.Bool("by-creator", false, "group counts by Created-By (§11.4.104)")
	obsoleteAudit := fs.Bool("obsolete-audit", false, "list Obsolete items + their §11.4.90 details")
	byRepro := fs.Bool("by-reproduction", false, "group counts by §11.4.292 reproduction_state")
	byInv := fs.Bool("by-investigation", false, "group counts by §11.4.292 investigation_state")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "report: --db is required")
		return exitUsage
	}

	selected := 0
	for _, b := range []bool{*byType, *byStatus, *bySeverity, *byAssigned, *byCreator, *obsoleteAudit, *byRepro, *byInv} {
		if b {
			selected++
		}
	}
	if selected > 1 {
		fmt.Fprintln(os.Stderr, "report: choose at most one of --by-type / --by-status / --by-severity / --by-assigned / --by-creator / --obsolete-audit / --by-reproduction / --by-investigation")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "report: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	switch {
	case *obsoleteAudit:
		return reportObsoleteAudit(db)
	case *byType:
		return reportGroupBy(db, "type", "Type")
	case *bySeverity:
		return reportGroupBy(db, "COALESCE(severity,'(none)')", "Severity")
	case *byAssigned:
		return reportGroupBy(db, "CASE WHEN COALESCE(assigned_to,'')='' THEN '(unassigned)' ELSE assigned_to END", "Assigned-To")
	case *byCreator:
		return reportGroupBy(db, "CASE WHEN COALESCE(created_by,'')='' THEN '(none)' ELSE created_by END", "Created-By")
	case *byRepro:
		return reportGroupBy(db, "COALESCE(reproduction_state,'UNSET')", "Reproduction")
	case *byInv:
		return reportGroupBy(db, "COALESCE(investigation_state,'UNSET')", "Investigation")
	default: // --by-status or no flag
		return reportGroupBy(db, "status", "Status")
	}
}

// reportGroupBy prints a sorted "<value>  <count>" tally for the given column
// expression, plus a total line. Values sort by descending count then name so
// the dominant bucket leads.
func reportGroupBy(db *sql.DB, colExpr, label string) int {
	rows, err := db.Query(`SELECT ` + colExpr + ` AS g, COUNT(1) FROM items GROUP BY g`)
	if err != nil {
		fmt.Fprintf(os.Stderr, "report: %v\n", err)
		return exitUsage
	}
	defer rows.Close()

	type bucket struct {
		name  string
		count int
	}
	var buckets []bucket
	total := 0
	for rows.Next() {
		var b bucket
		if err := rows.Scan(&b.name, &b.count); err != nil {
			fmt.Fprintf(os.Stderr, "report: %v\n", err)
			return exitUsage
		}
		buckets = append(buckets, b)
		total += b.count
	}
	if err := rows.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "report: %v\n", err)
		return exitUsage
	}

	sort.Slice(buckets, func(i, j int) bool {
		if buckets[i].count != buckets[j].count {
			return buckets[i].count > buckets[j].count
		}
		return buckets[i].name < buckets[j].name
	})

	width := len(label)
	for _, b := range buckets {
		if len(b.name) > width {
			width = len(b.name)
		}
	}

	fmt.Printf("Workable items by %s:\n", label)
	for _, b := range buckets {
		fmt.Printf("  %-*s  %d\n", width, b.name, b.count)
	}
	fmt.Printf("  %s\n", strings.Repeat("-", width+5))
	fmt.Printf("  %-*s  %d\n", width, "TOTAL", total)
	return exitOK
}

// reportObsoleteAudit lists every Obsolete item and joins its §11.4.90
// obsolete_details row (Since / Reason / Superseding-item / Triple-check
// evidence). Items marked Obsolete WITHOUT a details row are flagged as a
// §11.4.90 compliance gap (bare-assertion forbidden).
func reportObsoleteAudit(db *sql.DB) int {
	rows, err := db.Query(`SELECT i.atm_id, i.title,
		COALESCE(d.since,''), COALESCE(d.reason,''),
		COALESCE(d.superseding_item,''), COALESCE(d.triple_check_evidence,'')
		FROM items i
		LEFT JOIN obsolete_details d ON d.atm_id = i.atm_id
		WHERE i.status = 'Obsolete (→ Fixed.md)'
		ORDER BY i.atm_id`)
	if err != nil {
		fmt.Fprintf(os.Stderr, "report: %v\n", err)
		return exitUsage
	}
	defer rows.Close()

	count := 0
	gaps := 0
	fmt.Println("§11.4.90 Obsolete audit:")
	for rows.Next() {
		var id, title, since, reason, superseding, evidence string
		if err := rows.Scan(&id, &title, &since, &reason, &superseding, &evidence); err != nil {
			fmt.Fprintf(os.Stderr, "report: %v\n", err)
			return exitUsage
		}
		count++
		fmt.Printf("  %s — %s\n", id, title)
		if since == "" && reason == "" && superseding == "" && evidence == "" {
			fmt.Printf("      ⚠ §11.4.90 GAP: no obsolete_details row (bare-assertion Obsolete)\n")
			gaps++
			continue
		}
		fmt.Printf("      Since: %s  Reason: %s  Superseding: %s\n", since, reason, superseding)
		fmt.Printf("      Triple-check evidence: %s\n", evidence)
	}
	if err := rows.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "report: %v\n", err)
		return exitUsage
	}
	fmt.Printf("  %d Obsolete item(s), %d compliance gap(s)\n", count, gaps)
	if gaps > 0 {
		return exitUsage
	}
	return exitOK
}
