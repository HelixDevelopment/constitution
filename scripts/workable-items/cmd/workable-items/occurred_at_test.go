// occurred_at_test.go — T019 (SpecKit-004 "fast-dev-cycles", User Story 1) RED
// baseline for the occurred_at / occurred_at_source columns item_history is
// missing today.
//
// THE GAP (verified directly, 2026-09-28, against BOTH schema.sql and the
// actually-embedded cmd/workable-items/schema_embed.sql -- the latter is what
// openDB() really applies at runtime): item_history has
// (id, atm_id, event_type, by, on_date, reason, evidence_path, created_at) --
// no occurred_at, no occurred_at_source, in either copy. `created_at` is the
// row-INSERT wall-clock time (DEFAULT (datetime('now'))); it is NOT a provable
// record of when the underlying EVENT occurred (§11.4.226 evidence-class-at-
// closure -- a row's insert time and the event's real occurrence time are
// DIFFERENT facts). T035 (a LATER, SEPARATE task) adds the schema migration +
// backfill mechanism; THIS file's job is only to (a) pin the CURRENT absence
// as a real, running, currently-passing assertion -- captured proof today's
// schema lacks the column, the §11.4.115-style RED baseline -- and (b)
// document, via t.Skip()-guarded stub tests, the golden / golden-bad /
// negative-control contract T035's implementer must satisfy.
//
// Why stubs and not live assertions: referencing an occurred_at column or a
// backfill function that does not exist today would break compilation for the
// WHOLE shared `package main` test build -- every other Phase-3 task (T024,
// T026, ...) adds its own new _test.go file into this SAME directory/package,
// so one broken reference here would collaterally block all of them.
//
// Producer≠Verifier (tasks.md convention, [TDD][SUBAGENT] markers): this file
// is authored at the RED step; T035's implementation is a separate, later
// task -- this file's author never implements the backfill.
//
// §11.4.273 control needle: before trusting "no such column: occurred_at" as
// proof of absence, TestOccurredAt_ColumnAbsent_RED first queries a column
// PROVEN present (event_type) through the identical Scan-based mechanism --
// if that control query ever failed too, an "absent" verdict for occurred_at
// would be an artifact of a broken query path, not a genuine finding.
package main

import (
	"strings"
	"testing"
)

// TestOccurredAt_ColumnAbsent_RED is the T019 RED baseline. It is a REAL,
// RUNNING (never skipped) test that captures, as of 2026-09-28, that
// item_history has no occurred_at column -- proof the backfill feature T035
// will add does not exist yet. It is EXPECTED to keep passing (proving
// absence) until T035 lands; at that point T035's implementer DELETES this
// test (superseded by the real golden / golden-bad / negative-control tests
// below, un-skipped and completed).
func TestOccurredAt_ColumnAbsent_RED(t *testing.T) {
	dbPath := newTestDB(t)
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	const id = "T019-PROBE-1"
	seedOpenItem(t, dbPath, id) // real addCmd -> real "Opened" item_history row

	// §11.4.273 control needle: prove the query mechanism itself can see a
	// KNOWN-PRESENT column through the exact same Scan path, BEFORE trusting
	// an absence result for occurred_at.
	var eventType string
	if err := db.QueryRow(
		`SELECT event_type FROM item_history WHERE atm_id=? ORDER BY id DESC LIMIT 1`,
		id,
	).Scan(&eventType); err != nil {
		t.Fatalf("control needle failed: querying a KNOWN-PRESENT column "+
			"(event_type) errored (%v) -- the absence check below would prove "+
			"nothing (§11.4.273 control-needle discipline)", err)
	}
	if eventType == "" {
		t.Fatalf("control needle failed: event_type scanned empty for a " +
			"freshly-seeded row -- the seeded row itself is suspect")
	}

	var occurredAt string
	err = db.QueryRow(
		`SELECT occurred_at FROM item_history WHERE atm_id=? ORDER BY id DESC LIMIT 1`,
		id,
	).Scan(&occurredAt)
	if err == nil {
		t.Fatalf("item_history.occurred_at now resolves (got %q) -- T035 has "+
			"landed the schema migration. DELETE this RED-baseline test; the "+
			"golden/golden-bad/negative-control stubs below are the real tests "+
			"to un-skip and complete.", occurredAt)
	}
	if !strings.Contains(err.Error(), "no such column") ||
		!strings.Contains(err.Error(), "occurred_at") {
		t.Fatalf("query failed for the WRONG reason (want an error containing "+
			"both \"no such column\" and \"occurred_at\", got %q) -- this "+
			"looks like a genuine unrelated bug, not the absence this RED "+
			"baseline exists to pin", err.Error())
	}
}

// --- T035 contract stubs (§11.4.115 golden / golden-bad / negative-control) ---
//
// The three tests below are t.Skip()-guarded SPECIFICATIONS for T035's
// implementer, not yet-working tests. Each documents required behaviour in
// its skip message; none references an undefined symbol, so the shared test
// build stays green for every other in-flight task's own new test file.

// TestOccurredAt_Golden_BackfillFromClosingCommit is the T035 GOLDEN contract:
// closing an item with a real commit timestamp available MUST backfill
// occurred_at from that commit's authored/committer time, AND record
// occurred_at_source naming the provenance (e.g. "commit:<sha>") -- never a
// bare "backfilled" flag with no traceable source.
func TestOccurredAt_Golden_BackfillFromClosingCommit(t *testing.T) {
	t.Skip("T035 contract stub (not yet implemented): closing an item whose " +
		"commit timestamp is available MUST set item_history.occurred_at to " +
		"that commit's time AND item_history.occurred_at_source to a value " +
		"naming the commit (e.g. \"commit:<sha>\") -- un-skip and implement " +
		"once T035 lands the schema migration + backfill mechanism")
}

// TestOccurredAt_GoldenBad_BackfillFromCreatedAtRefused is the T035
// GOLDEN-BAD contract: created_at (the row-insert wall-clock time) is NOT
// proof of when the underlying EVENT actually occurred (§11.4.226 evidence-
// class-at-closure). A backfill implementation that silently copies
// created_at into occurred_at MUST be refused/rejected, never silently
// accepted as a provable occurrence time.
func TestOccurredAt_GoldenBad_BackfillFromCreatedAtRefused(t *testing.T) {
	t.Skip("T035 contract stub (not yet implemented): a backfill that copies " +
		"item_history.created_at into occurred_at (treating row-insert " +
		"wall-clock time as a provable event-occurrence time) MUST be " +
		"refused -- created_at is evidence of when the ROW WAS WRITTEN, " +
		"never of when the EVENT HAPPENED -- un-skip and implement once " +
		"T035 lands")
}

// TestOccurredAt_NegativeControl_NoProvableTimeStaysUnknown is the T035
// NEGATIVE-CONTROL contract: an item_history event with NO provable time
// source (no commit, no captured timestamp of any kind) MUST leave
// occurred_at NULL and occurred_at_source reporting the literal "UNKNOWN" --
// never a guessed/assumed timestamp (§11.4.6 no-guessing).
func TestOccurredAt_NegativeControl_NoProvableTimeStaysUnknown(t *testing.T) {
	t.Skip("T035 contract stub (not yet implemented): an item_history event " +
		"with no provable time source MUST leave occurred_at NULL and " +
		"occurred_at_source = \"UNKNOWN\" -- never a guessed/assumed/default " +
		"timestamp -- un-skip and implement once T035 lands")
}
