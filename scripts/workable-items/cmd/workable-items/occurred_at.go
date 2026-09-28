// occurred_at.go — T035 (SpecKit-004 "fast-dev-cycles", plan T-A05).
//
// Adds item_history.occurred_at + item_history.occurred_at_source: the
// event's OWN provable occurrence time, distinct from created_at (the
// row-INSERT wall-clock time — §11.4.226 evidence-class-at-closure: a row's
// insert time and the event's real occurrence time are DIFFERENT facts, and
// treating one as the other is exactly the class of bluff §11.4.226 forbids).
//
// Migration follows the SAME idempotent ALTER-TABLE-ADD-COLUMN pattern as
// migrateColumns (db.go) — itemHistoryColumns (PRAGMA table_info) + a
// wanted-column loop, guarded so it is a no-op once the columns exist.
//
// recordHistoryWithTime extends recordHistory (crud.go) with two optional
// parameters. The REFUSAL guard is structural (§11.4.241 illegal-state-
// unrepresentability preference): occurred_at_source is REQUIRED whenever
// occurred_at is non-empty, and a caller naming "created_at" (or any
// row-insert-time-derived label) as the source is rejected outright — there
// is no code path anywhere in this file that reads created_at to populate
// occurred_at.
package main

import (
	"database/sql"
	"fmt"
	"strings"
)

// itemHistoryColumns returns the set of column names currently present on the
// `item_history` table (via PRAGMA table_info), mirroring itemColumns (db.go)
// for the items table.
func itemHistoryColumns(db *sql.DB) (map[string]bool, error) {
	rows, err := db.Query(`PRAGMA table_info(item_history)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var (
			cid       int
			name, typ string
			notNull   int
			dfltValue any
			pk        int
		)
		if err := rows.Scan(&cid, &name, &typ, &notNull, &dfltValue, &pk); err != nil {
			return nil, err
		}
		cols[name] = true
	}
	return cols, rows.Err()
}

// migrateItemHistoryOccurredAt (T-A05, v6→v7) brings an existing item_history
// table up to the current schema by ADDing occurred_at + occurred_at_source
// when absent. Idempotent (a no-op once both columns exist) and lossless
// (nullable, no DEFAULT — every pre-existing row correctly reports
// occurred_at=NULL / occurred_at_source=NULL until a later, separate
// backfill pass touches it; §11.4.6 — an untouched legacy row is honestly
// "never assessed", not silently "UNKNOWN", since UNKNOWN is itself a
// positive assertion this migration has not made for rows it did not write).
func migrateItemHistoryOccurredAt(db *sql.DB) error {
	have, err := itemHistoryColumns(db)
	if err != nil {
		return err
	}
	type colDef struct{ name, ddl string }
	wanted := []colDef{
		{"occurred_at", `ALTER TABLE item_history ADD COLUMN occurred_at TEXT`},
		{"occurred_at_source", `ALTER TABLE item_history ADD COLUMN occurred_at_source TEXT`},
	}
	for _, c := range wanted {
		if have[c.name] {
			continue
		}
		if _, err := db.Exec(c.ddl); err != nil {
			return fmt.Errorf("add column %s: %w", c.name, err)
		}
	}
	if _, err := db.Exec(`UPDATE meta SET value='7' WHERE key='schema_version' AND value < '7'`); err != nil {
		return fmt.Errorf("advance schema_version to 7: %w", err)
	}
	return nil
}

// recordHistoryWithTime is recordHistory (crud.go) extended with the event's
// own provable occurrence time.
//
//   - occurredAt == "": the event's occurrence time is not (yet) provable.
//     occurredAtSource is forced to the literal "UNKNOWN" regardless of what
//     the caller passed (§11.4.6 — a caller cannot smuggle a fabricated
//     source in alongside an empty time). occurred_at is written NULL.
//
//   - occurredAt != "": occurredAtSource MUST be non-empty (every provable
//     time names its provenance — §11.4.6 no-guessing) and MUST NOT be
//     "created_at" or a row-insert-time label (§11.4.226 — the row-insert
//     wall-clock time is never a provable event-occurrence time; this is
//     the T035 golden-bad refusal, enforced HERE so no caller anywhere in
//     this package can accidentally recreate the bluff by construction).
func recordHistoryWithTime(tx *sql.Tx, id, event, by, reason, evidence, occurredAt, occurredAtSource string) error {
	if occurredAt == "" {
		occurredAtSource = "UNKNOWN"
	} else {
		if occurredAtSource == "" {
			return fmt.Errorf("recordHistoryWithTime: occurred_at %q given with no occurred_at_source — every non-empty occurred_at MUST name its provenance (§11.4.6 no-guessing)", occurredAt)
		}
		lower := strings.ToLower(occurredAtSource)
		if lower == "created_at" || strings.HasPrefix(lower, "row-insert") || strings.HasPrefix(lower, "rowinsert") {
			return fmt.Errorf("recordHistoryWithTime: refusing occurred_at_source %q — created_at (the row-INSERT wall-clock time) is NEVER a provable event-occurrence time (§11.4.226 evidence-class-at-closure)", occurredAtSource)
		}
	}
	_, err := tx.Exec(`INSERT INTO item_history
		(atm_id, event_type, by, on_date, reason, evidence_path, occurred_at, occurred_at_source)
		VALUES (?,?,?,date('now'),?,?,?,?)`,
		id, event, nullable(by), nullable(reason), nullable(evidence), nullable(occurredAt), occurredAtSource)
	return err
}
