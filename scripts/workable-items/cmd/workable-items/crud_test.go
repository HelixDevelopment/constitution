// crud_test.go — anti-bluff coverage for add + close.
//
// Every test exercises the REAL SQLite driver + real parser + real renderer
// (no mocks). The decisive anti-bluff assertions: (1) add actually inserts a
// queryable row + a re-parseable Markdown block; (2) add survives a full
// md→db→md→db fixed-point cycle; (3) close performs the atomic Issues→Fixed
// move + records captured-evidence; (4) the closed item round-trips through
// sync db-to-md → sync md-to-db and re-validates.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newTestDB(t *testing.T) string {
	t.Helper()
	// §11.4.151 decoupling: pin the DERIVED default key so auto-id assertions are
	// deterministic and PROVE the resolver reads HELIX_RELEASE_PREFIX (without
	// this, the default would derive from the CWD dir name "workable-items"->"WOR"
	// and every WIT-* assertion would fail).
	t.Setenv("HELIX_RELEASE_PREFIX", "wit") // deriveKeyPrefix("wit") == "WIT"
	return filepath.Join(t.TempDir(), "workable_items.db")
}

// TestAdd_InsertsQueryableRow proves add mutates the DB: the row is present,
// status=Queued, and validate accepts it.
func TestAdd_InsertsQueryableRow(t *testing.T) {
	dbPath := newTestDB(t)
	code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-001",
		"--title", "first workable item",
		"--description", "a sufficiently long description that clears the §11.4.91 floor",
		"Bug", "Critical",
	})
	if code != exitOK {
		t.Fatalf("add exited %d, want %d", code, exitOK)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, "WIT-001", "Issues")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if it == nil {
		t.Fatal("add did not persist WIT-001 (row absent) — add is a bluff")
	}
	if it.Status != "Queued" {
		t.Errorf("status = %q, want Queued", it.Status)
	}
	if it.Type != "Bug" {
		t.Errorf("type = %q, want Bug", it.Type)
	}
	if it.Severity != "Critical" {
		t.Errorf("severity = %q, want Critical", it.Severity)
	}
	if !strings.Contains(it.BodyMD, "## WIT-001 — first workable item") {
		t.Errorf("body_md missing canonical heading:\n%s", it.BodyMD)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate after add exited %d (expected OK)", code)
	}
}

// TestAdd_AutoIDMonotonic proves auto-generated ids are monotonic + zero-padded.
func TestAdd_AutoIDMonotonic(t *testing.T) {
	// bluff-scan: nil-only-ok (asserts auto-generated DEM-001..003 are present — real monotonic-ID observable)
	dbPath := newTestDB(t)
	// Override with a DISTINCTIVE prefix to PROVE the id derives from
	// HELIX_RELEASE_PREFIX (not a leftover hardcode): "demoproject" -> "DEM".
	t.Setenv("HELIX_RELEASE_PREFIX", "demoproject")
	for i := 0; i < 3; i++ {
		if code := addCmd([]string{
			"--db", dbPath,
			"--title", "auto id item number",
			"--description", "a sufficiently long description that clears the §11.4.91 floor entirely",
			"Task", "Low",
		}); code != exitOK {
			t.Fatalf("add #%d exited %d", i, code)
		}
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	for _, want := range []string{"DEM-001", "DEM-002", "DEM-003"} {
		it, err := loadItem(db, want, "Issues")
		if err != nil || it == nil {
			t.Fatalf("expected auto-generated %s present (err=%v)", want, err)
		}
	}
}

// TestAdd_RejectsShortDescription is the §11.4.91 anti-bluff guard.
func TestAdd_RejectsShortDescription(t *testing.T) {
	dbPath := newTestDB(t)
	code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-009",
		"--title", "x", "--description", "too short", "Bug", "Low",
	})
	if code == exitOK {
		t.Fatal("add ACCEPTED a §11.4.91-violating short description — entry guard is a bluff")
	}
}

// TestAdd_FixedPoint proves add output is a stable fixed point: the generated
// body_md, written out via sync db-to-md and re-parsed via sync md-to-db,
// reproduces the same item — the round-trip is preserved.
func TestAdd_FixedPoint(t *testing.T) {
	dbPath := newTestDB(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-042",
		"--title", "fixed point round-trip item",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the fixed point",
		"Feature", "Medium",
	}); code != exitOK {
		t.Fatalf("add exited %d", code)
	}

	tmp := t.TempDir()
	outIssues := filepath.Join(tmp, "Issues.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-issues", outIssues}); code != exitOK {
		t.Fatalf("db-to-md exited %d", code)
	}
	gen, err := os.ReadFile(outIssues)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(gen), "## WIT-042 — fixed point round-trip item") {
		t.Fatalf("regenerated Issues.md missing the added item:\n%s", gen)
	}

	// Re-ingest the regenerated MD into a fresh DB and assert the item survives.
	db2 := filepath.Join(tmp, "second.db")
	if code := syncMDToDB([]string{"--db", db2, "--issues", outIssues}); code != exitOK {
		t.Fatalf("re-ingest md-to-db exited %d", code)
	}
	d2, _ := openDB(db2)
	defer d2.Close()
	it, err := loadItem(d2, "WIT-042", "Issues")
	if err != nil || it == nil {
		t.Fatalf("WIT-042 did not survive the md→db→md→db fixed-point (err=%v)", err)
	}
	if it.Type != "Feature" || it.Status != "Queued" {
		t.Errorf("after fixed-point: type=%q status=%q, want Feature/Queued", it.Type, it.Status)
	}

	// And the regenerated DB→MD→DB output is byte-stable on a second pass.
	out2 := filepath.Join(tmp, "Issues.2.md")
	if code := syncDBToMD([]string{"--db", db2, "--out-issues", out2}); code != exitOK {
		t.Fatalf("second db-to-md exited %d", code)
	}
	gen2, _ := os.ReadFile(out2)
	if string(gen) != string(gen2) {
		t.Errorf("add output is NOT a stable fixed point:\norig:\n%s\nregen:\n%s", gen, gen2)
	}
}

// TestClose_AtomicMove proves close performs the Issues→Fixed atomic move,
// requires evidence, sets the terminal status, and records item_history.
func TestClose_AtomicMove(t *testing.T) {
	dbPath := newTestDB(t)
	if code := addCmd([]string{
		"--db", dbPath, "--id", "WIT-100",
		"--title", "item to be closed",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the close test",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("add exited %d", code)
	}

	// Evidence is mandatory.
	if code := closeCmd([]string{"--db", dbPath, "--status", "fixed", "WIT-100"}); code == exitOK {
		t.Fatal("close ACCEPTED a closure with no --evidence — §11.4.5 guard is a bluff")
	}

	evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/WIT-100/transcript.md")
	if code := closeCmd([]string{"--db", dbPath, "--status", "fixed", "--evidence", evidence, "WIT-100"}); code != exitOK {
		t.Fatalf("close exited %d, want OK", code)
	}

	db, _ := openDB(dbPath)
	defer db.Close()

	// Gone from Issues, present in Fixed with the terminal status.
	if it, _ := loadItem(db, "WIT-100", "Issues"); it != nil {
		t.Error("WIT-100 still present in Issues after close — atomic move incomplete")
	}
	fx, err := loadItem(db, "WIT-100", "Fixed")
	if err != nil || fx == nil {
		t.Fatalf("WIT-100 absent from Fixed after close (err=%v)", err)
	}
	if fx.Status != "Fixed (→ Fixed.md)" {
		t.Errorf("Fixed status = %q, want 'Fixed (→ Fixed.md)'", fx.Status)
	}
	if !strings.Contains(fx.BodyMD, "**Evidence:** "+evidence) {
		t.Errorf("closed body_md missing evidence line:\n%s", fx.BodyMD)
	}

	// item_history records the closure with the evidence path.
	var n int
	if err := db.QueryRow(`SELECT COUNT(1) FROM item_history WHERE atm_id='WIT-100' AND event_type='Fixed' AND evidence_path=?`, evidence).Scan(&n); err != nil {
		t.Fatalf("history query: %v", err)
	}
	if n != 1 {
		t.Errorf("expected 1 'Fixed' history row with evidence, got %d", n)
	}

	// The Issues item-segment is gone; the Fixed item-segment is present.
	var issuesSeg, fixedSeg int
	db.QueryRow(`SELECT COUNT(1) FROM doc_segments WHERE document='Issues' AND kind='item' AND atm_id='WIT-100'`).Scan(&issuesSeg)
	db.QueryRow(`SELECT COUNT(1) FROM doc_segments WHERE document='Fixed' AND kind='item' AND atm_id='WIT-100'`).Scan(&fixedSeg)
	if issuesSeg != 0 {
		t.Errorf("Issues segment for WIT-100 not removed (%d)", issuesSeg)
	}
	if fixedSeg != 1 {
		t.Errorf("Fixed segment for WIT-100 missing (%d)", fixedSeg)
	}
}

// TestClose_RoundTripsAndValidates proves a closed item regenerates valid
// Markdown that re-ingests + re-validates — the close path preserves the
// §11.4.93 round-trip guarantee.
func TestClose_RoundTripsAndValidates(t *testing.T) {
	dbPath := newTestDB(t)
	addCmd([]string{
		"--db", dbPath, "--id", "WIT-200",
		"--title", "closed item that must round-trip",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for round-trip after close",
		"Task", "Low",
	})
	if code := closeCmd([]string{"--db", dbPath, "--status", "completed",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/WIT-200/run.md"), "WIT-200"}); code != exitOK {
		t.Fatalf("close exited %d", code)
	}

	tmp := t.TempDir()
	outFixed := filepath.Join(tmp, "Fixed.md")
	if code := syncDBToMD([]string{"--db", dbPath, "--out-fixed", outFixed}); code != exitOK {
		t.Fatalf("db-to-md exited %d", code)
	}
	db2 := filepath.Join(tmp, "second.db")
	if code := syncMDToDB([]string{"--db", db2, "--fixed", outFixed}); code != exitOK {
		t.Fatalf("re-ingest exited %d", code)
	}
	if code := validateCmd([]string{"--db", db2}); code != exitOK {
		t.Fatalf("validate after close round-trip exited %d (expected OK)", code)
	}
	d2, _ := openDB(db2)
	defer d2.Close()
	fx, err := loadItem(d2, "WIT-200", "Fixed")
	if err != nil || fx == nil {
		t.Fatalf("WIT-200 did not survive close round-trip (err=%v)", err)
	}
	if fx.Status != "Completed (→ Fixed.md)" {
		t.Errorf("status after round-trip = %q, want 'Completed (→ Fixed.md)'", fx.Status)
	}
}

// TestAdd_FlagsAfterPositionals proves the CLI accepts the documented arg order
// `add <type> <severity> --db ... --title ...` (positionals BEFORE flags) — the
// real-binary ordering the Go flag package alone would mis-handle. This guards
// the partitionArgs fix against regression.
func TestAdd_FlagsAfterPositionals(t *testing.T) {
	dbPath := newTestDB(t)
	code := addCmd([]string{
		"Bug", "Critical",
		"--db", dbPath, "--id", "WIT-777",
		"--title", "positional-first ordering item",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for arg ordering",
	})
	if code != exitOK {
		t.Fatalf("add (positionals-first) exited %d — partitionArgs regressed", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	if it, _ := loadItem(db, "WIT-777", "Issues"); it == nil {
		t.Fatal("WIT-777 not created with positionals-before-flags ordering")
	}
}

// TestClose_PositionalLast proves close accepts the id as a trailing positional
// (`close --db ... --status ... --evidence ... <atm-id>`), the ordering the
// real-binary e2e exercise and the documented usage both use.
func TestClose_PositionalLast(t *testing.T) {
	dbPath := newTestDB(t)
	// BOB-240 §11.4.33 Type↔Status guard reconciliation: this test's ORIGINAL
	// Type ("Task") did not match "--status implemented" (Feature's closure
	// word), which is now itself the exact Type↔Status mismatch BOB-240's
	// guard refuses. The test's actual intent — proving close accepts the
	// atm-id as a TRAILING positional — is unaffected by which Type/status
	// pair is used, so the seed Type is reconciled to "Feature" (the Type
	// "implemented" genuinely belongs to) rather than weakening the new guard.
	addCmd([]string{
		"--db", dbPath, "--id", "WIT-888",
		"--title", "trailing positional close item",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for trailing close",
		"Feature", "Low",
	})
	if code := closeCmd([]string{
		"--db", dbPath, "--status", "implemented",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/WIT-888/run.md"), "WIT-888",
	}); code != exitOK {
		t.Fatalf("close (trailing positional) exited %d", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	fx, _ := loadItem(db, "WIT-888", "Fixed")
	if fx == nil || fx.Status != "Implemented (→ Fixed.md)" {
		t.Fatalf("WIT-888 not closed to Implemented via trailing positional (%v)", fx)
	}
}

// TestClose_RejectsUnknownItem proves close fails loudly on a missing id.
func TestClose_RejectsUnknownItem(t *testing.T) {
	dbPath := newTestDB(t)
	// HXC-224: a REAL artefact, so the refusal below is the item-not-found
	// guard firing — not the record-time evidence guard masking it.
	if code := closeCmd([]string{"--db", dbPath, "--status", "fixed",
		"--evidence", materialiseEvidence(t, newEvidenceRoot(t), "x/y.md"), "WIT-NOPE"}); code == exitOK {
		t.Fatal("close PASSED on a non-existent item — missing-item guard is a bluff")
	}
}
