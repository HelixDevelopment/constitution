// occurred_at_test.go — T035 (SpecKit-004 "fast-dev-cycles", plan T-A05)
// golden / golden-bad / negative-control coverage for item_history.occurred_at
// + occurred_at_source.
//
// The T019 RED baseline (TestOccurredAt_ColumnAbsent_RED) that used to live
// in this file has been DELETED per its own documented instruction: "at that
// point T035's implementer DELETES this test (superseded by the real
// golden / golden-bad / negative-control tests below)". T035 has landed
// (occurred_at.go: migrateItemHistoryOccurredAt + recordHistoryWithTime) —
// the column now genuinely exists, so a "prove it's absent" test would be
// asserting a false thing.
//
// §11.4.226 evidence-class-at-closure is the governing principle throughout:
// created_at (row-INSERT wall-clock time) and occurred_at (the event's real
// occurrence time) are DIFFERENT facts, and conflating them is the exact
// class of bluff these tests exist to make structurally impossible.
package main

import (
	"database/sql"
	"strings"
	"testing"
)

// TestOccurredAt_Golden_BackfillFromClosingCommit is the T035 GOLDEN contract:
// closing an item with a real commit timestamp available MUST record
// occurred_at from that commit's time, AND occurred_at_source naming the
// provenance (e.g. "commit:<sha>") — never a bare flag with no traceable
// source.
func TestOccurredAt_Golden_BackfillFromClosingCommit(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "T035-GOLDEN-1"
	seedOpenItem(t, dbPath, id)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	const commitSHA = "a1b2c3d4e5f6789012345678901234567890abcd"
	const commitTime = "2026-09-15T14:22:07Z" // a real, provable commit time
	const source = "commit:" + commitSHA

	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("Begin: %v", err)
	}
	if err := recordHistoryWithTime(tx, id, "Fixed", "AI", "", "", commitTime, source); err != nil {
		t.Fatalf("recordHistoryWithTime with a real commit provenance was refused: %v", err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatalf("Commit: %v", err)
	}

	gotAt, gotSrc := lastHistoryOccurredAt(t, db, id)
	if gotAt != commitTime {
		t.Fatalf("occurred_at = %q, want %q (the commit's real time)", gotAt, commitTime)
	}
	if gotSrc != source {
		t.Fatalf("occurred_at_source = %q, want %q (naming the commit)", gotSrc, source)
	}
	if !strings.HasPrefix(gotSrc, "commit:") {
		t.Fatalf("occurred_at_source %q does not name a commit provenance", gotSrc)
	}
}

// TestOccurredAt_GoldenBad_BackfillFromCreatedAtRefused is the T035
// GOLDEN-BAD contract: created_at (row-insert wall-clock time) is NOT proof
// of when the underlying EVENT occurred (§11.4.226). A caller attempting to
// use it as an occurred_at_source MUST be refused, never silently accepted.
func TestOccurredAt_GoldenBad_BackfillFromCreatedAtRefused(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "T035-GOLDENBAD-1"
	seedOpenItem(t, dbPath, id)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	tx, err := db.Begin()
	if err != nil {
		t.Fatalf("Begin: %v", err)
	}
	// Attempt exactly the bluff §11.4.226 forbids: label a fabricated time with
	// a "created_at"-derived source, as if the row-insert wall-clock time were
	// a provable event-occurrence time.
	err = recordHistoryWithTime(tx, id, "Fixed", "AI", "", "", "2026-01-01T00:00:00Z", "created_at")
	if err == nil {
		tx.Rollback()
		t.Fatalf("recordHistoryWithTime ACCEPTED occurred_at_source=\"created_at\" — this is exactly the §11.4.226 bluff (row-insert time treated as a provable event-occurrence time) this golden-bad test exists to catch")
	}
	if !strings.Contains(err.Error(), "created_at") {
		t.Fatalf("refusal error %q does not name the offending source — the refusal must be diagnosable, not a generic failure", err.Error())
	}
	tx.Rollback()

	// A second attempt using a row-insert-derived label variant must also be
	// refused — the guard is a class check, not a single-string match.
	tx2, err := db.Begin()
	if err != nil {
		t.Fatalf("Begin: %v", err)
	}
	err = recordHistoryWithTime(tx2, id, "Fixed", "AI", "", "", "2026-01-01T00:00:00Z", "row-insert-time")
	if err == nil {
		tx2.Rollback()
		t.Fatalf("recordHistoryWithTime ACCEPTED occurred_at_source=\"row-insert-time\" — the refusal guard must catch the WHOLE class, not merely the literal string \"created_at\"")
	}
	tx2.Rollback()

	// Confirm no row was actually written by either rejected attempt (the
	// refusal is a hard error, never a partial/silent write).
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM item_history WHERE atm_id=? AND occurred_at_source LIKE '%created%'`, id).Scan(&count); err != nil {
		t.Fatalf("post-refusal query: %v", err)
	}
	if count != 0 {
		t.Fatalf("a refused recordHistoryWithTime call still left %d row(s) behind — the refusal must prevent the write entirely", count)
	}
}

// TestOccurredAt_NegativeControl_NoProvableTimeStaysUnknown is the T035
// NEGATIVE-CONTROL contract: an item_history event with NO provable time
// source (the ordinary case — every existing recordHistory call site) MUST
// leave occurred_at NULL and occurred_at_source reporting the literal
// "UNKNOWN" — never a guessed/assumed timestamp (§11.4.6).
func TestOccurredAt_NegativeControl_NoProvableTimeStaysUnknown(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "T035-NEGCTRL-1"
	// seedOpenItem's own internal addCmd call goes through the ORDINARY
	// recordHistory path (crud.go), with no occurred_at supplied — the exact
	// real-world case this negative control targets.
	seedOpenItem(t, dbPath, id)

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	var occurredAt sql.NullString
	var occurredAtSource sql.NullString
	row := db.QueryRow(
		`SELECT occurred_at, occurred_at_source FROM item_history WHERE atm_id=? AND event_type='Opened' ORDER BY id DESC LIMIT 1`,
		id,
	)
	if err := row.Scan(&occurredAt, &occurredAtSource); err != nil {
		t.Fatalf("query the seeded Opened row: %v", err)
	}
	if occurredAt.Valid {
		t.Fatalf("occurred_at = %q, want SQL NULL (no provable time was supplied)", occurredAt.String)
	}
	if !occurredAtSource.Valid {
		t.Fatalf("occurred_at_source is SQL NULL, want the literal string \"UNKNOWN\" — an unset column and an honestly-reported-unknown provenance must be distinguishable")
	}
	if occurredAtSource.String != "UNKNOWN" {
		t.Fatalf("occurred_at_source = %q, want exactly \"UNKNOWN\"", occurredAtSource.String)
	}
}

// TestMigrateItemHistoryOccurredAt_SchemaVersionNeverRegresses is the T048
// round-2 review finding F15 regression guard: migrateItemHistoryOccurredAt's
// own `UPDATE meta SET value='7' WHERE key='schema_version' AND ...` clause
// MUST NOT regress a schema_version that has already advanced PAST 7 (e.g.
// a future migration bumped it to a double-digit value like '10') back down
// to '7' the next time this function runs. Before the fix, comparing
// schema_version as TEXT made '10' < '7' evaluate TRUE (lexicographic: '1'
// < '7'), so re-running this idempotent migration on an already-advanced DB
// silently REGRESSED the version marker -- the exact class of bluff
// §11.4.226 forbids applied to the DB's own self-description of its schema.
func TestMigrateItemHistoryOccurredAt_SchemaVersionNeverRegresses(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	// Simulate a DB whose schema_version has already advanced past 7 (a
	// future migration bumped it into double digits).
	if _, err := db.Exec(`UPDATE meta SET value='10' WHERE key='schema_version'`); err != nil {
		t.Fatalf("seed schema_version=10: %v", err)
	}

	// Re-run the SAME idempotent migration this test's own name targets --
	// this is exactly what a normal openDB() call on an already-migrated,
	// already-advanced DB does every time the tool runs.
	if err := migrateItemHistoryOccurredAt(db); err != nil {
		t.Fatalf("migrateItemHistoryOccurredAt (second run): %v", err)
	}

	var got string
	row := db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`)
	if err := row.Scan(&got); err != nil {
		t.Fatalf("query schema_version: %v", err)
	}
	if got != "10" {
		t.Fatalf("schema_version regressed to %q after re-running migrateItemHistoryOccurredAt on an already-advanced DB — want it to stay \"10\" (F15: TEXT comparison must not treat '10' as < '7')", got)
	}
}

// TestMigrateColumns_SchemaVersionNeverRegresses is the T048 round-2 review
// finding F15 sibling regression guard: db.go's migrateColumns() carries the
// SAME `UPDATE meta SET value='6' WHERE key='schema_version' AND ...` TEXT-
// comparison pattern occurred_at.go's own v7 clause was found+fixed for
// (see TestMigrateItemHistoryOccurredAt_SchemaVersionNeverRegresses above) —
// fixed for consistency the same session. This test proves openDB()'s own
// migration chain (which runs migrateColumns on every call, idempotently)
// does not regress an already-advanced double-digit schema_version.
func TestMigrateColumns_SchemaVersionNeverRegresses(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	if _, err := db.Exec(`UPDATE meta SET value='10' WHERE key='schema_version'`); err != nil {
		t.Fatalf("seed schema_version=10: %v", err)
	}

	// Re-open against the SAME db path: openDB() re-runs the full migration
	// chain (migrateColumns included) idempotently on every call, exactly as
	// every real subcommand invocation does against an already-migrated DB.
	db2, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (second open): %v", err)
	}
	defer db2.Close()

	var got string
	row := db2.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`)
	if err := row.Scan(&got); err != nil {
		t.Fatalf("query schema_version: %v", err)
	}
	if got != "10" {
		t.Fatalf("schema_version regressed to %q after re-opening an already-advanced DB — want it to stay \"10\" (F15 sibling: TEXT comparison must not treat '10' as < '6')", got)
	}
}

// lastHistoryOccurredAt returns (occurred_at, occurred_at_source) for the
// newest item_history row of id, failing the test if either column is
// unexpectedly NULL (callers expect a populated row).
func lastHistoryOccurredAt(t *testing.T, db *sql.DB, id string) (string, string) {
	t.Helper()
	var at, src sql.NullString
	row := db.QueryRow(
		`SELECT occurred_at, occurred_at_source FROM item_history WHERE atm_id=? ORDER BY id DESC LIMIT 1`,
		id,
	)
	if err := row.Scan(&at, &src); err != nil {
		t.Fatalf("query newest item_history row for %s: %v", id, err)
	}
	if !at.Valid {
		t.Fatalf("occurred_at is SQL NULL for %s, want a populated value", id)
	}
	if !src.Valid {
		t.Fatalf("occurred_at_source is SQL NULL for %s, want a populated value", id)
	}
	return at.String, src.String
}
