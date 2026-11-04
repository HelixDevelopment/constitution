// repair_bodies.go — the `repair-bodies` subcommand (ATM-627 / task #20).
//
// §11.4.93 / §11.4.95: items.status is the authoritative single source of truth;
// body_md is a derived surface that `sync db-to-md` (renderDocument) replays into
// the trackers. THREE classes of drift accumulate when items are inserted/mutated
// directly against the DB (added DB-direct without a follow-up `sync md-to-db`
// reparse, or a direct `UPDATE items SET status=…`) instead of through the
// md<->db round-trip:
//
//   - STALE-LINE (38 items on the live tree): a NON-empty section body whose LAST
//     `**Status:**` line disagrees with the column. renderDocument's
//     canonicalizeBodyStatusLine already emits the column-consistent line on the
//     fly, but the STORED body_md stays stale, so `validate`'s column↔body guard
//     (statusColumnBodyDesyncs) keeps flagging it. repair-bodies persists the
//     canonicalized line INTO storage — a surgical single-line rewrite that
//     preserves every other line (prose + `**Reopened-Details:**` /
//     `**Operator-Block-Details:**` blocks) verbatim.
//
//   - EMPTY-BODY (72 items on the live tree; 26 non-Queued desyncs + 46 Queued
//     that are not desyncs but still vanish from a db→md regen): a section item
//     whose body_md is empty/NULL. canonicalizeBodyStatusLine is a no-op on it
//     (no line to rewrite), so repair-bodies POPULATES it via renderItemBody —
//     the SAME renderer the `add` path uses — emitting the `**Status:**` /
//     `**Type:**` / `**Severity:**` / `**Created-By:**` / `**Assigned-To:**`
//     block + the description from the authoritative columns.
//
//   - MISSING-SEGMENT (112 items on the live tree, captured 2026-07-05): an item
//     with a populated body_md but NO doc_segments row for its
//     (atm_id, current_location, representation). renderDocument (db.go) walks
//     doc_segments in seq order and only ever emits an item THAT HAS a segment
//     row — an item lacking one is simply never visited, so `sync db-to-md`
//     returns exitOK and SILENTLY DROPS the item from the regenerated Markdown
//     (no error, no warning — the exact "db-to-md drops N segmentless items"
//     symptom ATM-627 reports). repair-bodies BACKFILLS a `kind='item'` segment
//     row for every such item, appended after the current MAX(seq) for that
//     item's document (deterministic ORDER BY atm_id so the operation is
//     reproducible run-to-run) — restoring the item to db-to-md's output without
//     touching any EXISTING segment's seq/position (so the byte-identical
//     round-trip of every already-segmented item is unaffected).
//
// After repair-bodies, `validate` reports 0 column↔body desyncs AND 0
// missing-item-segments. The operation is IDEMPOTENT: a second run classifies
// every item as noop (a populated body already derives its column; a rewritten
// line already equals its column; a backfilled item now HAS a segment row) and
// issues NO UPDATE / INSERT — the DB is byte-identical.
//
// HARD CONSTRAINT (§11.4.95 / §9.2): the conductor runs this against the live
// docs/workable_items.db inside the §9.2-backed sync pipeline
// (scripts/testing/workable_items_sync_all.sh). This binary only ever writes the
// --db it is given; the test-suite drives it exclusively against /tmp copies.
package main

import (
	"database/sql"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

// repairAction classifies what repair-bodies will do to one item's body_md.
type repairAction string

const (
	repairNoop     repairAction = "noop"
	repairRewrite  repairAction = "rewrite"
	repairPopulate repairAction = "populate"
)

// classifyRepair decides the repair action + the new body_md for one item. It is
// the generator-symmetric mirror of the column↔body invariant enforced by
// statusColumnBodyDesyncs (sync.go) + renderDocument's canonicalizeBodyStatusLine
// (db.go / parse.go) — repair-bodies persists into storage exactly what those two
// derive on the fly, so a repaired DB round-trips byte-identically.
//
//   - A NON-'section' representation ('table' pipe-table row) is ALWAYS noop: its
//     Status lives in the pipe cell, NOT a `**Status:**` line, and its verbatim
//     row must be preserved (populating it would destroy the pipe row). No 'table'
//     rows exist on the live tree today (all 415 items are 'section'), but the
//     guard keeps repair-bodies correct if one is ever added — it mirrors
//     statusColumnBodyDesyncs's own `repOrDefault() != "section"` skip.
//   - An EMPTY/whitespace-only section body is POPULATED via renderItemBody from
//     the authoritative columns (the SPK/ATM empty-body class).
//   - A NON-empty section body has its LAST `**Status:**` line canonicalized to
//     the column via canonicalizeBodyStatusLine — a STRICT byte-identical no-op
//     when already synced (or when the body carries no `**Status:**` line at all),
//     a surgical single-line rewrite when stale — AND is normalized to end with a
//     trailing "\n" via ensureTrailingNewline (the ATM-627-part-2 STORE-side fix:
//     a stored body ending with NO "\n" breaks the byte-identical round-trip
//     because renderDocument synthesizes the missing separator "\n", so the
//     re-parsed body is one "\n" longer — the live md=N+1/db=N residual). Both are
//     byte-identical no-ops on an already-canonical, already-"\n"-terminated body.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return repairNoop, it.BodyMD` disables the repair; TestRepairBodies_
// ClearsDesyncs_RedPolarity + …_Idempotent then FAIL (post-repair validate still
// reports desyncs) — proving the repair is not a tautology. Removing the
// ensureTrailingNewline call (or stubbing it to `return body`) makes
// TestRepairBodies_NormalizesTrailingNewline_RedPolarity FAIL — proving the
// trailing-newline normalization is load-bearing, not a tautology.
func classifyRepair(it item) (repairAction, string) {
	if it.repOrDefault() != "section" {
		return repairNoop, it.BodyMD
	}
	// §11.4.292 (v8): the records are column-authoritative too, so a populated or
	// rewritten body also carries the state columns' records (a STRICT no-op for
	// a body that already parses to its columns).
	if strings.TrimSpace(it.BodyMD) == "" {
		body := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity,
			it.Description, it.Status, it.CreatedBy, it.AssignedTo)
		return repairPopulate, canonicalizeStateLines(body, it.States, it.repOrDefault())
	}
	newBody := ensureTrailingNewline(canonicalizeStateLines(
		canonicalizeBodyStatusLine(it.BodyMD, it.Status), it.States, it.repOrDefault()))
	if newBody == it.BodyMD {
		return repairNoop, it.BodyMD
	}
	return repairRewrite, newBody
}

func runRepairBodies(args []string) {
	os.Exit(repairBodiesCmd(args))
}

// segmentBackfillPlan is one item that needs a NEW doc_segments row.
type segmentBackfillPlan struct {
	it  item
	seq int
}

// existingItemSegmentKeys returns the set of (atm_id, document, representation)
// keys that already have a `kind='item'` doc_segments row, keyed exactly as
// itemsMissingSegments (sync.go) joins them.
func existingItemSegmentKeys(db *sql.DB) (map[string]bool, error) {
	rows, err := db.Query(`SELECT atm_id, document, COALESCE(representation,'section')
		FROM doc_segments WHERE kind='item' AND atm_id IS NOT NULL`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	keys := map[string]bool{}
	for rows.Next() {
		var atmID, document, rep string
		if err := rows.Scan(&atmID, &document, &rep); err != nil {
			return nil, err
		}
		keys[atmID+"\x00"+document+"\x00"+rep] = true
	}
	return keys, rows.Err()
}

// maxSeqPerDocument returns the current MAX(seq) per document, defaulting to -1
// for a document with zero rows so the first backfilled segment gets seq=0.
func maxSeqPerDocument(db *sql.DB) (map[string]int, error) {
	maxSeq := map[string]int{"Issues": -1, "Fixed": -1}
	rows, err := db.Query(`SELECT document, MAX(seq) FROM doc_segments GROUP BY document`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var document string
		var seq int
		if err := rows.Scan(&document, &seq); err != nil {
			return nil, err
		}
		maxSeq[document] = seq
	}
	return maxSeq, rows.Err()
}

// planSegmentBackfill computes, for every item lacking a doc_segments row, the
// NEW segment it needs — appended after the document's current MAX(seq), assigned
// in a DETERMINISTIC order (sorted by current_location then atm_id) so re-running
// repair-bodies on the same drifted DB always produces the identical plan
// (§11.4.50 deterministic consistency). Existing segments (and their seq values)
// are never touched — this is purely additive, so every already-segmented item's
// byte-identical round-trip is unaffected.
//
// §1.1 PAIRED-MUTATION SENTINEL: replacing this function's body with
// `return nil, nil` disables the backfill; TestRepairBodies_BackfillsMissingSegments
// (RED polarity per §11.4.115) then FAILs — proving the backfill is not a tautology.
func planSegmentBackfill(db *sql.DB, items []item) ([]segmentBackfillPlan, error) {
	existing, err := existingItemSegmentKeys(db)
	if err != nil {
		return nil, err
	}
	maxSeq, err := maxSeqPerDocument(db)
	if err != nil {
		return nil, err
	}

	var missing []item
	for _, it := range items {
		key := it.AtmID + "\x00" + it.CurrentLocation + "\x00" + it.repOrDefault()
		if !existing[key] {
			missing = append(missing, it)
		}
	}
	sort.Slice(missing, func(i, j int) bool {
		if missing[i].CurrentLocation != missing[j].CurrentLocation {
			return missing[i].CurrentLocation < missing[j].CurrentLocation
		}
		return missing[i].AtmID < missing[j].AtmID
	})

	var plan []segmentBackfillPlan
	for _, it := range missing {
		maxSeq[it.CurrentLocation]++
		plan = append(plan, segmentBackfillPlan{it: it, seq: maxSeq[it.CurrentLocation]})
	}
	return plan, nil
}

// repairBodiesCmd implements `repair-bodies [--dry-run] [--db PATH]`.
func repairBodiesCmd(args []string) int {
	fs := flag.NewFlagSet("repair-bodies", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB")
	dryRun := fs.Bool("dry-run", false, "print per-item summary + totals, write nothing")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	if *dbPath == "" {
		fmt.Fprintln(os.Stderr, "repair-bodies: --db is required")
		return exitUsage
	}

	db, err := openDB(*dbPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: %v\n", err)
		return exitUsage
	}
	defer db.Close()

	items, err := loadItems(db)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: %v\n", err)
		return exitUsage
	}

	type plan struct {
		it      item
		action  repairAction
		newBody string
	}
	var toApply []plan
	var nRewrite, nPopulate, nNoop int
	for _, it := range items {
		action, newBody := classifyRepair(it)
		switch action {
		case repairRewrite:
			nRewrite++
		case repairPopulate:
			nPopulate++
		default:
			nNoop++
			continue
		}
		toApply = append(toApply, plan{it: it, action: action, newBody: newBody})
		if *dryRun {
			detail := fmt.Sprintf("empty body -> render **Status:** %s", it.Status)
			if action == repairRewrite {
				old, _ := lastBodyStatus(it.BodyMD)
				detail = fmt.Sprintf("stale **Status:** %q -> column %q", old, it.Status)
			}
			fmt.Printf("  %s [%s/%s]: %s (%s)\n",
				it.AtmID, it.CurrentLocation, it.repOrDefault(), action, detail)
		}
	}

	backfillPlan, err := planSegmentBackfill(db, items)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: plan segment backfill: %v\n", err)
		return exitUsage
	}

	if *dryRun {
		for _, bp := range backfillPlan {
			fmt.Printf("  %s [%s/%s]: backfill-segment (seq=%d, no prior doc_segments row)\n",
				bp.it.AtmID, bp.it.CurrentLocation, bp.it.repOrDefault(), bp.seq)
		}
		fmt.Printf("repair-bodies (dry-run): scanned %d items — %d rewrite, %d populate, %d noop, %d backfill-segment (nothing written)\n",
			len(items), nRewrite, nPopulate, nNoop, len(backfillPlan))
		return exitOK
	}

	if len(toApply) == 0 && len(backfillPlan) == 0 {
		fmt.Printf("repair-bodies: scanned %d items — already canonical (0 rewrite, 0 populate, 0 backfill-segment); no changes\n", len(items))
		return exitOK
	}

	// Single transaction (WAL journal per schema_embed.sql): every body_md write +
	// every backfilled doc_segments row commits atomically or not at all.
	tx, err := db.Begin()
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: begin: %v\n", err)
		return exitUsage
	}
	defer tx.Rollback()

	stmt, err := tx.Prepare(`UPDATE items SET body_md=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND representation=?`)
	if err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: prepare: %v\n", err)
		return exitUsage
	}
	defer stmt.Close()

	for _, p := range toApply {
		res, err := stmt.Exec(p.newBody, p.it.AtmID, p.it.CurrentLocation, p.it.repOrDefault())
		if err != nil {
			fmt.Fprintf(os.Stderr, "repair-bodies: update %s: %v\n", p.it.AtmID, err)
			return exitUsage
		}
		if n, _ := res.RowsAffected(); n != 1 {
			fmt.Fprintf(os.Stderr, "repair-bodies: update %s [%s/%s] affected %d rows (expected 1)\n",
				p.it.AtmID, p.it.CurrentLocation, p.it.repOrDefault(), n)
			return exitUsage
		}
	}

	if len(backfillPlan) > 0 {
		segStmt, err := tx.Prepare(`INSERT INTO doc_segments (document, seq, kind, atm_id, representation, raw)
			VALUES (?, ?, 'item', ?, ?, '')`)
		if err != nil {
			fmt.Fprintf(os.Stderr, "repair-bodies: prepare segment insert: %v\n", err)
			return exitUsage
		}
		defer segStmt.Close()
		for _, bp := range backfillPlan {
			if _, err := segStmt.Exec(bp.it.CurrentLocation, bp.seq, bp.it.AtmID, bp.it.repOrDefault()); err != nil {
				fmt.Fprintf(os.Stderr, "repair-bodies: backfill segment %s: %v\n", bp.it.AtmID, err)
				return exitUsage
			}
		}
	}

	if err := tx.Commit(); err != nil {
		fmt.Fprintf(os.Stderr, "repair-bodies: commit: %v\n", err)
		return exitUsage
	}

	fmt.Printf("repair-bodies: scanned %d items — applied %d change(s): %d rewrite, %d populate, %d noop, %d backfill-segment\n",
		len(items), len(toApply)+len(backfillPlan), nRewrite, nPopulate, nNoop, len(backfillPlan))
	return exitOK
}
