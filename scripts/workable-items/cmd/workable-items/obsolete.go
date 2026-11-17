// obsolete.go — §11.4.90 write-path for the obsolete_details triple-check table.
//
// The `close --status obsolete` path performs the §11.4.19 atomic Issues→Fixed
// move and records the closure evidence in item_history, but deliberately leaves
// the richer §11.4.90 `**Obsolete-Details:**` row (Since / Reason / Superseding-
// item / Triple-check evidence) to this dedicated flow. `obsolete-details`
// upserts that row for an item already marked `Obsolete (→ Fixed.md)`, so the
// §11.4.90 audit (report --obsolete-audit) no longer flags it as a bare-assertion
// gap. Modeled on the §11.4.21 `block` write-path.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
)

// obsoleteReasonClosedSet is the §11.4.90 closed-set Reason vocabulary, kept in
// lockstep with the obsolete_details.reason CHECK constraint in schema_embed.sql.
// `not-reproducible` = a reported defect that does NOT reproduce on the canonical
// tree/baseline (environment / isolated-worktree artifact), not a real product
// defect.
var obsoleteReasonClosedSet = []string{
	"superseded-by-design-change",
	"superseded-by-later-mandate",
	"feature-removed",
	"duplicate-of",
	"unsupported-topology",
	"not-reproducible",
}

func isValidObsoleteReason(r string) bool {
	for _, v := range obsoleteReasonClosedSet {
		if v == r {
			return true
		}
	}
	return false
}

func runObsoleteDetails(args []string) {
	os.Exit(obsoleteDetailsCmd(args))
}

// obsoleteDetailsCmd implements
// `obsolete-details <atm-id> --db <p> --since <ISO> --reason <r> --superseding <s> --evidence <p>`.
// It upserts the §11.4.90 obsolete_details row for an item already in the
// terminal `Obsolete (→ Fixed.md)` status and records an item_history entry.
func obsoleteDetailsCmd(args []string) int {
	fs := flag.NewFlagSet("obsolete-details", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	since := fs.String("since", "", "§11.4.90 Since: ISO date (YYYY-MM-DD) of the obsolescence determination (required)")
	reason := fs.String("reason", "", "§11.4.90 Reason: one of the closed-set vocabulary (required)")
	superseding := fs.String("superseding", "", "§11.4.90 Superseding-item: §-letter / ATM-NNN / 'none' (required)")
	evidence := fs.String("evidence", "", "§11.4.90 Triple-check evidence: path to captured non-reproduction / supersession proof (required)")
	pos, flagArgs := partitionArgs(args, nil)
	if err := fs.Parse(flagArgs); err != nil {
		return exitUsage
	}
	if len(pos) < 1 {
		fmt.Fprintln(os.Stderr, "obsolete-details: missing positional <atm-id>")
		return exitUsage
	}
	id := pos[0]
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "obsolete-details: --db is required")
		return exitUsage
	}
	sinceVal := strings.TrimSpace(*since)
	reasonVal := strings.TrimSpace(*reason)
	supersedingVal := strings.TrimSpace(*superseding)
	evidenceVal := strings.TrimSpace(*evidence)
	if sinceVal == "" || reasonVal == "" || supersedingVal == "" || evidenceVal == "" {
		fmt.Fprintln(os.Stderr, "obsolete-details: --since, --reason, --superseding and --evidence are all required (§11.4.90 four sub-facts)")
		return exitUsage
	}
	// HXC-224 record-time closure-evidence guard: the §11.4.90 triple-check
	// evidence is a closure warrant like any other — it lands in
	// item_history.evidence_path (below) on an item already in a terminal
	// status, exactly the rows the HXC-217 validator scopes to. Refuse an
	// unresolvable path here rather than at a later sweep.
	// CON-456 round 3 (review F-D): the four values are written into ONE
	// `**Obsolete-Details:**` line. A line break would split it, so a later
	// line could read as one of the item's own metadata lines and be
	// rewritten from the columns, and a re-run (injectObsoleteDetails drops
	// only the marker line) would leave the tail behind. Refuse it, naming
	// the flag.
	for _, f := range []struct{ name, val string }{
		{"--since", sinceVal}, {"--reason", reasonVal}, {"--superseding", supersedingVal}, {"--evidence", evidenceVal},
	} {
		if i := strings.IndexAny(f.val, "\r\n\u0085  "); i >= 0 {
			fmt.Fprintf(os.Stderr, "obsolete-details: refusing (nothing written) — %s %q carries a line break; the §11.4.90 details are one Markdown line\n", f.name, f.val)
			return exitUsage
		}
	}
	if !requireEvidencePath("obsolete-details", evidenceVal) {
		return exitUsage
	}
	if !isValidObsoleteReason(reasonVal) {
		fmt.Fprintf(os.Stderr, "obsolete-details: --reason must be one of the §11.4.90 closed-set: %s\n", strings.Join(obsoleteReasonClosedSet, " | "))
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	// The item must exist and already be in the terminal Obsolete status (in
	// either tracker). obsolete_details is meaningless for a non-Obsolete item.
	cur, err := loadItem(db, id, "Fixed")
	if err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: %v\n", err)
		return exitUsage
	}
	if cur == nil {
		if cur, err = loadItem(db, id, "Issues"); err != nil {
			fmt.Fprintf(os.Stderr, "obsolete-details: %v\n", err)
			return exitUsage
		}
	}
	if cur == nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: item %s not found in Issues or Fixed\n", id)
		return exitUsage
	}
	if !strings.Contains(strings.ToLower(cur.Status), "obsolete") {
		fmt.Fprintf(os.Stderr, "obsolete-details: item %s status is %q, not Obsolete — close it with `close %s --status obsolete` first (§11.4.90)\n", id, cur.Status, id)
		return exitUsage
	}

	// §11.4.90 requires the `**Obsolete-Details:**` line to appear within 8
	// non-blank lines of the heading in the RENDERED tracker, not only in the
	// obsolete_details table. Inject it into the item body so a db-to-md regen
	// surfaces it (idempotent: a prior Obsolete-Details line is replaced).
	newBody := injectObsoleteDetails(cur.BodyMD, sinceVal, reasonVal, supersedingVal, evidenceVal)
	// One round trip (idgrammar.go, CON-456): the item's Markdown must still
	// read back as this item after the details line is injected.
	gated := *cur
	gated.BodyMD = newBody
	// The operator values are judged as inputs: each must appear unchanged in
	// the text db-to-md writes (review F-D: a metadata line inside a value was
	// accepted and then rewritten from the columns in Fixed.md).
	if newBody, err = gateItemWrite(gated, sinceVal, supersedingVal, evidenceVal); err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: refusing (nothing written) — %v\n", err)
		return exitUsage
	}

	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`INSERT OR REPLACE INTO obsolete_details
		(atm_id, since, reason, superseding_item, triple_check_evidence)
		VALUES (?,?,?,?,?)`,
		id, sinceVal, reasonVal, supersedingVal, evidenceVal); err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: write row: %v\n", err)
		return exitUsage
	}
	// F-DBTOOL fix (2026-07-12): scope by representation — cur came from
	// loadItem's now-deterministic (atm_id, location) read, which prefers the
	// 'section' row when a dual-representation item (GAP A, e.g. HXC-044) has
	// both. Without this scope the UPDATE matched EVERY representation row for
	// (atm_id, location) and clobbered the sibling 'table' pipe-row's body_md
	// with the 'section' row's content — the confirmed reproduction of the
	// F-DBTOOL desync (see docs/research/f_dbtool_20260712/ROOTCAUSE.md).
	if _, err := tx.Exec(`UPDATE items SET body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`, newBody, id, cur.CurrentLocation, cur.repOrDefault()); err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: update body: %v\n", err)
		return exitUsage
	}
	if err := recordHistory(tx, id, "Obsolete", "AI", reasonVal, evidenceVal); err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: history: %v\n", err)
		return exitUsage
	}
	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "obsolete-details: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("obsolete-details: %s written (Since:%s Reason:%s Superseding:%s Evidence:%s)\n",
		id, sinceVal, reasonVal, supersedingVal, evidenceVal)
	return exitOK
}

// injectObsoleteDetails inserts (or replaces) the §11.4.90 `**Obsolete-Details:**`
// line into a rendered item body, immediately after the contiguous heading meta
// block (the `**Field:** value` lines following the H2), so it lands within 8
// non-blank lines of the heading. Any prior Obsolete-Details line is dropped
// first, making the operation idempotent.
//
// F-DBTOOL fix (2026-07-12): the drop-then-scan used to run as ONE pass over
// the ORIGINAL lines, so when a body ALREADY carried an Obsolete-Details line
// (the common, intended-to-be-idempotent re-run case) the lookahead used to
// decide "is this the LAST contiguous meta line" saw the STALE, about-to-be-
// dropped Obsolete-Details line as lines[i+1] — which itself matches the
// generic `**Field:** value` meta shape — so `nextIsMeta` was wrongly true at
// the REAL last meta field, the loop never found a genuine insertion point,
// and the code fell through to the "append at the very end" fallback: the new
// details line landed AFTER the prose body with NO trailing newline (Join
// never adds a trailing separator after the last element). That newline-less
// tail is exactly what renderDocument's segment-glue logic (db.go
// appendSegment) does not defend against for non-heading content, so the next
// document segment glued directly onto it — corrupting parseFixed's view of
// every subsequent item (reproduced live via `obsolete-details HXC-044` on a
// body that already carried an Obsolete-Details line: see
// docs/research/f_dbtool_20260712/ROOTCAUSE.md).
//
// Fix: drop stale Obsolete-Details line(s) in a FIRST pass, producing a
// cleaned line list, THEN run the insertion-point scan over that cleaned list
// — so the lookahead can never mistake a soon-to-be-removed line for a
// genuine blocking meta field. A body with no prior Obsolete-Details line (or
// none at all) behaves exactly as before.
func injectObsoleteDetails(body, since, reason, superseding, evidence string) string {
	detailsLine := fmt.Sprintf("**Obsolete-Details:** Since: %s; Reason: %s; Superseding-item: %s; Triple-check evidence: %s",
		since, reason, superseding, evidence)

	rawLines := strings.Split(body, "\n")
	lines := make([]string, 0, len(rawLines))
	for _, ln := range rawLines {
		// Drop a pre-existing Obsolete-Details line (idempotent re-run).
		if strings.HasPrefix(strings.TrimSpace(ln), "**Obsolete-Details:**") {
			continue
		}
		lines = append(lines, ln)
	}

	out := make([]string, 0, len(lines)+1)
	inserted := false
	for i, ln := range lines {
		out = append(out, ln)
		if inserted {
			continue
		}
		// Insert after the LAST contiguous `**Field:**` meta line, i.e. when the
		// current line is a meta field and the next is not (blank or prose).
		isMeta := strings.HasPrefix(strings.TrimSpace(ln), "**") && strings.Contains(ln, ":**")
		nextIsMeta := i+1 < len(lines) &&
			strings.HasPrefix(strings.TrimSpace(lines[i+1]), "**") &&
			strings.Contains(lines[i+1], ":**")
		if isMeta && !nextIsMeta {
			out = append(out, detailsLine)
			inserted = true
		}
	}
	if !inserted {
		// No meta block found — append the line at the end as a fallback.
		out = append(out, detailsLine)
	}
	return strings.Join(out, "\n")
}
