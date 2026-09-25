// repair_bodies_test.go — anti-bluff coverage for the `repair-bodies` subcommand
// (ATM-627 / task #20), the STORAGE-side half of the column↔body Status durable fix.
//
// §11.4.115 RED-polarity: TestRepairBodies_ClearsDesyncs_RedPolarity captures the
// RED baseline on the BROKEN artifact (validate FAILs on a desynced DB) and, at the
// default polarity, proves repair-bodies converts it to GREEN (validate exit 0).
// RED_MODE=1 stops at the captured RED (defect reproduced, fix NOT applied).
//
// §1.1 PAIRED MUTATION (documented on classifyRepair, repair_bodies.go): stubbing
// classifyRepair to `return repairNoop, it.BodyMD` disables the repair →
// TestRepairBodies_ClearsDesyncs_RedPolarity + …_Idempotent FAIL (post-repair
// validate still reports desyncs). Restoring → GREEN. Proves the repair is not a
// tautology.
//
// HARD CONSTRAINT: fresh temp DBs only (t.TempDir); NEVER touches the live
// docs/workable_items.db.
package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// rbFixtureDB materialises a synced two-document DB via md→db so every item's
// column == its body Status line BY CONSTRUCTION (buildItem derives the column
// from exactly the body Status line). ATM-970 (Issues, Queued), ATM-971 (Fixed,
// closure), ATM-972 (Issues, Reopened — carries a **Reopened-Details:** block used
// by the preservation test). All descriptions clear the §11.4.91 floor.
func rbFixtureDB(t *testing.T) string {
	t.Helper()
	tmp := t.TempDir()
	dbPath := filepath.Join(tmp, "wi.db")
	issues := "# Issues\n\n" +
		"## §1. [ATM-970] alpha item with enough words to satisfy the description floor\n\n" +
		"**Type:** Bug\n**Status:** Queued\n\nbody one two three four five six.\n\n" +
		"## §3. [ATM-972] gamma reopened item with enough words to satisfy the floor\n\n" +
		"**Type:** Bug\n**Status:** Reopened\n" +
		"**Reopened-Details:** By: AI On: 2026-05-17 Reason: test-failed Evidence: qa/x\n\n" +
		"prose line for gamma.\n"
	fixed := "# Fixed\n\n" +
		"## §2. [ATM-971] beta item with enough words to satisfy the description floor\n\n" +
		"**Type:** Bug\n**Status:** Fixed (→ Fixed.md)\n\nbody one two three four five six.\n"
	issuesPath := filepath.Join(tmp, "Issues.md")
	fixedPath := filepath.Join(tmp, "Fixed.md")
	if err := os.WriteFile(issuesPath, []byte(issues), 0o644); err != nil {
		t.Fatalf("write issues: %v", err)
	}
	if err := os.WriteFile(fixedPath, []byte(fixed), 0o644); err != nil {
		t.Fatalf("write fixed: %v", err)
	}
	if code := syncMDToDB([]string{"--db", dbPath, "--issues", issuesPath, "--fixed", fixedPath}); code != exitOK {
		t.Fatalf("md-to-db exited %d", code)
	}
	// Sanity: the freshly-synced DB has ZERO desyncs (no false positive on the
	// canonical shape) — the RED baseline below is injected, never pre-existing.
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("fixture DB did not validate clean (exit %d)", code)
	}
	return dbPath
}

func rbOpen(t *testing.T, dbPath string) *sql.DB {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	return db
}

func rbExec(t *testing.T, db *sql.DB, q string, args ...any) {
	t.Helper()
	res, err := db.Exec(q, args...)
	if err != nil {
		t.Fatalf("exec %q: %v", q, err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("exec %q affected %d rows (expected 1)", q, n)
	}
}

// rbSnapshotBodies returns a map (atm_id\x00location\x00representation) -> body_md
// for every item — the byte-level oracle the idempotency test compares.
func rbSnapshotBodies(t *testing.T, dbPath string) map[string]string {
	t.Helper()
	db := rbOpen(t, dbPath)
	defer db.Close()
	items, err := loadItems(db)
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	m := map[string]string{}
	for _, it := range items {
		m[it.AtmID+"\x00"+it.CurrentLocation+"\x00"+it.repOrDefault()] = it.BodyMD
	}
	return m
}

// rbReadBody returns the stored body_md for a single (id, location) item.
func rbReadBody(t *testing.T, dbPath, id, location string) string {
	t.Helper()
	db := rbOpen(t, dbPath)
	defer db.Close()
	it, err := loadItem(db, id, location)
	if err != nil {
		t.Fatalf("loadItem %s/%s: %v", id, location, err)
	}
	if it == nil {
		t.Fatalf("loadItem %s/%s: not found", id, location)
	}
	return it.BodyMD
}

// TestRepairBodies_ClearsDesyncs_RedPolarity — the §11.4.115 RED→GREEN guard.
// Injects BOTH desync classes (stale-line + empty-body) via direct SQL; the
// pre-fix artifact (desynced DB) FAILs validate (captured RED); repair-bodies then
// converts it to a validate-clean DB (GREEN).
func TestRepairBodies_ClearsDesyncs_RedPolarity(t *testing.T) {
	redMode := os.Getenv("RED_MODE") == "1"
	dbPath := rbFixtureDB(t)

	// Inject the two drift classes exactly as a rogue `UPDATE items SET status=…`
	// would (bypassing renderItemBody):
	//   (1) STALE-LINE: advance ATM-970's column, leave its body Status line stale.
	//   (2) EMPTY-BODY: blank ATM-971's body_md AND advance its column.
	db := rbOpen(t, dbPath)
	rbExec(t, db, `UPDATE items SET status='In progress'
		WHERE atm_id='ATM-970' AND current_location='Issues' AND representation='section'`)
	// §11.4.120 reconciliation: the injected Fixed-location column value MUST be a
	// TERMINAL `… (→ Fixed.md)` status so it does not trip validateCmd's new
	// location↔status invariant (check (f), ATM-627 INTEG-03). This test exercises
	// the empty-body column↔body repair class, NOT a Fixed+non-terminal desync;
	// 'Obsolete' advances the column (was 'Fixed') AND blanks the body, so the
	// empty-body desync still fires while the item stays location↔status-valid.
	// BOB-240 reconciliation (2026-09-25): ATM-971 is Type=Bug, so the earlier
	// choice of 'Completed' here is now ITSELF a §11.4.33 Type↔Status mismatch
	// (Completed belongs to Task) — the exact new class this item's own guard
	// refuses. 'Obsolete' is valid for ANY Type (criterion 5) and is still a
	// genuine column change from the fixture's initial 'Fixed', so it exercises
	// the identical column↔body repair path without tripping the new invariant.
	rbExec(t, db, `UPDATE items SET body_md='', status='Obsolete (→ Fixed.md)'
		WHERE atm_id='ATM-971' AND current_location='Fixed' AND representation='section'`)
	db.Close()

	// RED baseline on the BROKEN artifact: validate FAILs (both desyncs present).
	if code := validateCmd([]string{"--db", dbPath}); code == exitOK {
		t.Fatalf("RED baseline: validate returned exitOK on a desynced DB (defect not reproduced)")
	}
	if redMode {
		// RED_MODE=1: assert ONLY that the defect reproduces; do NOT apply the fix.
		return
	}

	// GREEN: repair-bodies clears BOTH classes; validate then PASSes.
	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("repair-bodies exited %d (expected OK)", code)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) after repair-bodies — desyncs not cleared", code)
	}
	// Direct guard confirmation: statusColumnBodyDesyncs is empty post-repair.
	db = rbOpen(t, dbPath)
	items, err := loadItems(db)
	db.Close()
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("post-repair statusColumnBodyDesyncs reports %d finding(s): %v", len(d), d)
	}
}

// TestRepairBodies_Idempotent — after a repair, a SECOND repair-bodies run is a
// byte-identical no-op (0 changes) and leaves validate GREEN.
func TestRepairBodies_Idempotent(t *testing.T) {
	dbPath := rbFixtureDB(t)

	db := rbOpen(t, dbPath)
	rbExec(t, db, `UPDATE items SET status='In progress'
		WHERE atm_id='ATM-970' AND current_location='Issues' AND representation='section'`)
	// §11.4.120 reconciliation: the injected Fixed-location column value MUST be a
	// TERMINAL `… (→ Fixed.md)` status so it does not trip validateCmd's new
	// location↔status invariant (check (f), ATM-627 INTEG-03). This test exercises
	// the empty-body column↔body repair class, NOT a Fixed+non-terminal desync;
	// 'Obsolete' advances the column (was 'Fixed') AND blanks the body, so the
	// empty-body desync still fires while the item stays location↔status-valid.
	// BOB-240 reconciliation (2026-09-25): see the identical comment in
	// TestRepairBodies_ClearsDesyncs_RedPolarity above — ATM-971 is Type=Bug, so
	// 'Completed' would now itself be a §11.4.33 Type↔Status mismatch; 'Obsolete'
	// is valid for ANY Type and still exercises the same column↔body repair path.
	rbExec(t, db, `UPDATE items SET body_md='', status='Obsolete (→ Fixed.md)'
		WHERE atm_id='ATM-971' AND current_location='Fixed' AND representation='section'`)
	db.Close()

	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("first repair-bodies exited %d", code)
	}
	before := rbSnapshotBodies(t, dbPath)

	// Second run MUST be a no-op — every body already derives its column.
	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("second repair-bodies exited %d", code)
	}
	after := rbSnapshotBodies(t, dbPath)

	if !reflect.DeepEqual(before, after) {
		for k := range before {
			if before[k] != after[k] {
				t.Errorf("body_md changed on 2nd run for %q:\n--- before ---\n%q\n--- after ---\n%q",
					strings.ReplaceAll(k, "\x00", "|"), before[k], after[k])
			}
		}
		t.Fatalf("repair-bodies is NOT idempotent (2nd run mutated bodies)")
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) after idempotent 2nd run", code)
	}
}

// TestRepairBodies_PreservesDetailBlocksOnRewrite — the STALE-LINE rewrite path
// preserves a `**Reopened-Details:**` block + all prose while rewriting ONLY the
// Status line to the column value.
func TestRepairBodies_PreservesDetailBlocksOnRewrite(t *testing.T) {
	dbPath := rbFixtureDB(t)

	// ATM-972 carries a **Reopened-Details:** block + body **Status:** Reopened.
	// Advance the column to a closure value, leaving the body Status line stale.
	db := rbOpen(t, dbPath)
	rbExec(t, db, `UPDATE items SET status='Fixed (→ Fixed.md)'
		WHERE atm_id='ATM-972' AND current_location='Issues' AND representation='section'`)
	db.Close()

	before := rbReadBody(t, dbPath, "ATM-972", "Issues")
	if !strings.Contains(before, "**Status:** Reopened\n") {
		t.Fatalf("precondition: ATM-972 body should carry the stale '**Status:** Reopened' line:\n%q", before)
	}

	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("repair-bodies exited %d", code)
	}
	after := rbReadBody(t, dbPath, "ATM-972", "Issues")

	// Only the Status line changed: to the column value.
	if !strings.Contains(after, "**Status:** Fixed (→ Fixed.md)\n") {
		t.Fatalf("Status line not rewritten to the column value:\n%q", after)
	}
	if strings.Contains(after, "**Status:** Reopened\n") {
		t.Fatalf("stale '**Status:** Reopened' line survived the rewrite:\n%q", after)
	}
	// Detail block + prose + heading + Type preserved VERBATIM.
	if !strings.Contains(after, "**Reopened-Details:** By: AI On: 2026-05-17 Reason: test-failed Evidence: qa/x\n") {
		t.Fatalf("repair-bodies DROPPED/ALTERED the **Reopened-Details:** block:\n%q", after)
	}
	if !strings.Contains(after, "prose line for gamma.\n") ||
		!strings.Contains(after, "**Type:** Bug\n") ||
		!strings.Contains(after, "[ATM-972]") {
		t.Fatalf("repair-bodies altered non-Status content:\n%q", after)
	}

	// Surgical: exactly ONE line differs (the Status line). Everything else byte-equal.
	bl := strings.SplitAfter(before, "\n")
	al := strings.SplitAfter(after, "\n")
	if len(bl) != len(al) {
		t.Fatalf("line count changed on rewrite (before=%d after=%d) — not a single-line rewrite", len(bl), len(al))
	}
	diffs := 0
	for i := range bl {
		if bl[i] != al[i] {
			diffs++
			if !strings.HasPrefix(strings.TrimSpace(bl[i]), "**Status:**") {
				t.Fatalf("a NON-Status line was rewritten at index %d:\nbefore=%q\nafter=%q", i, bl[i], al[i])
			}
		}
	}
	if diffs != 1 {
		t.Fatalf("expected exactly 1 changed line (Status), got %d", diffs)
	}
}

// TestRepairBodies_PopulatesEmptyBodyFromColumns — the EMPTY-BODY populate path
// emits exactly renderItemBody(columns) and the result is re-parseable back to the
// same id + status (round-trip stable).
func TestRepairBodies_PopulatesEmptyBodyFromColumns(t *testing.T) {
	dbPath := rbFixtureDB(t)

	// Blank ATM-970's body_md and advance its column (the empty-body class).
	db := rbOpen(t, dbPath)
	rbExec(t, db, `UPDATE items SET body_md='', status='In progress'
		WHERE atm_id='ATM-970' AND current_location='Issues' AND representation='section'`)
	db.Close()

	if code := repairBodiesCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("repair-bodies exited %d", code)
	}

	// The stored body MUST equal renderItemBody() recomputed from the columns.
	db = rbOpen(t, dbPath)
	it, err := loadItem(db, "ATM-970", "Issues")
	db.Close()
	if err != nil || it == nil {
		t.Fatalf("loadItem ATM-970: %v (nil=%v)", err, it == nil)
	}
	want := renderItemBody(it.AtmID, it.Title, it.Type, it.Severity, it.Description, it.Status, it.CreatedBy, it.AssignedTo)
	if it.BodyMD != want {
		t.Fatalf("populated body != renderItemBody(columns):\n--- want ---\n%q\n--- got ---\n%q", want, it.BodyMD)
	}
	if !strings.Contains(it.BodyMD, "**Status:** In progress\n") {
		t.Fatalf("populated body missing the column-consistent Status line:\n%q", it.BodyMD)
	}

	// Re-parseable: a fresh md→db parse of the populated body re-derives the item.
	parsedItems, _ := parseIssues("# Issues\n\n" + it.BodyMD)
	found := false
	for _, p := range parsedItems {
		if p.AtmID == "ATM-970" && p.Status == "In progress" {
			found = true
		}
	}
	if !found {
		t.Fatalf("populated body did not re-parse to (ATM-970, In progress); parsed=%d items", len(parsedItems))
	}
}
