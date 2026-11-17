// created_at_r2_test.go — CON-339 round 2: tests that pin the rules the
// round-1 independent review showed unpinned (reviewer mutants RM01..RM07 and
// RR01..RR15 survived the whole package; review sha256 9979116...).
//
// Each test names the mutant(s) it kills. Every test drives the real engine
// functions (the same functions the CLI dispatches) on real SQLite files under
// t.TempDir(); the restore tests call restoreCreatedAtCmd with CLI arguments.
// Fixture writes (raw UPDATE/INSERT on a scratch database) only build the
// state the defect left behind; assertions are about the command under test.
//
// Evidence class: gate-logic / unit (section 11.4.289); no mocks. The one test
// seam (rcaBeforeWriteHook) is a package variable that is nil in production.
package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const r2Desc = "a sufficiently long description that clears the section 11.4.91 floor for the CON-339 round 2 tests"

// r2Add adds one item through the real add command.
func r2Add(t *testing.T, dbPath, id, title, typ, sev string) {
	t.Helper()
	if rc := addCmd([]string{"--db", dbPath, "--description", r2Desc, "--id", id, "--title", title, typ, sev}); rc != exitOK {
		t.Fatalf("add %s exited %d", id, rc)
	}
}

// r2MDRoundTrip renders src to Markdown with the real db-to-md and loads it
// into dst with the real md-to-db.
func r2MDRoundTrip(t *testing.T, src, dst string) {
	t.Helper()
	dir := t.TempDir()
	iss, fix := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
	if rc := syncDBToMD([]string{"--db", src, "--out-issues", iss, "--out-fixed", fix}); rc != exitOK {
		t.Fatalf("db-to-md exited %d", rc)
	}
	if rc := syncMDToDB([]string{"--db", dst, "--issues", iss, "--fixed", fix}); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
}

// r2Issues renders the Issues document of dbPath and parses it back, giving
// the items and segments replaceDocument takes.
func r2Issues(t *testing.T, dbPath string) ([]item, []segment) {
	t.Helper()
	dir := t.TempDir()
	iss := filepath.Join(dir, "Issues.md")
	if rc := syncDBToMD([]string{"--db", dbPath, "--out-issues", iss}); rc != exitOK {
		t.Fatalf("db-to-md exited %d", rc)
	}
	b, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	items, segs := parseIssues(string(b))
	if len(items) == 0 {
		t.Fatalf("control: parsed no Issues items")
	}
	return items, segs
}

func r2Now(t *testing.T) time.Time {
	t.Helper()
	return time.Now().UTC().Truncate(time.Second)
}

// --- RM01 -----------------------------------------------------------------

// TestCON339R2_LookupFallbackDoesNotCrossIDPrefix (kills RM01): the fallback
// for a row whose exact key is absent matches the SAME id only. WIT-10 must
// not take WIT-100's earlier value.
func TestCON339R2_LookupFallbackDoesNotCrossIDPrefix(t *testing.T) {
	snap := createdAtSnapshot{
		"WIT-100|Issues|section": "2001-01-01 00:00:00",
		"WIT-10|Issues|section":  "2020-10-10 10:10:10",
	}
	got := snap.lookup("WIT-10", "Fixed", "section")
	if got == nil || *got != "2020-10-10 10:10:10" {
		t.Fatalf("lookup(WIT-10, Fixed) = %v, want WIT-10's own 2020-10-10 10:10:10", got)
	}
	if got := snap.lookup("WIT-1", "Fixed", "section"); got != nil {
		t.Fatalf("lookup(WIT-1) = %q, want nil (no row of WIT-1; WIT-10/WIT-100 are other items)", *got)
	}
}

// TestCON339R2_MDToDBMoveWithPrefixSiblingKeepsOwnCreatedAt (kills RM01
// end to end): WIT-10 moves Issues->Fixed through Markdown while WIT-100, an
// item whose id starts with "WIT-10", holds an earlier created_at.
func TestCON339R2_MDToDBMoveWithPrefixSiblingKeepsOwnCreatedAt(t *testing.T) {
	db := newTestDB(t)
	root := newEvidenceRoot(t)
	r2Add(t, db, "WIT-10", "r2 prefix item ten", "Task", "Low")
	r2Add(t, db, "WIT-100", "r2 prefix item one hundred", "Task", "Low")
	rcaExec(t, db, `UPDATE items SET created_at='2020-10-10 10:10:10' WHERE atm_id='WIT-10'`)
	rcaExec(t, db, `UPDATE items SET created_at='2001-01-01 00:00:00' WHERE atm_id='WIT-100'`)
	other := filepath.Join(t.TempDir(), "other.db")
	con339CopyDB(t, db, other)
	if rc := closeCmd([]string{"WIT-10", "--db", other, "--status", "obsolete",
		"--evidence", materialiseEvidence(t, root, "qa/r2/WIT-10.md")}); rc != exitOK {
		t.Fatalf("close on the copy exited %d", rc)
	}
	r2MDRoundTrip(t, other, db)
	rows := con339Rows(t, db)
	if _, ok := rows["WIT-10|Issues|section"]; ok {
		t.Fatalf("control: WIT-10 still in Issues; the move did not apply")
	}
	if got := rows["WIT-10|Fixed|section"]; got != "2020-10-10 10:10:10" {
		t.Errorf("WIT-10 after the move: created_at %q, want its own 2020-10-10 10:10:10", got)
	}
	if got := rows["WIT-100|Issues|section"]; got != "2001-01-01 00:00:00" {
		t.Errorf("WIT-100: created_at %q, want 2001-01-01 00:00:00", got)
	}
}

// --- RM02 / RM06 -----------------------------------------------------------

// TestCON339R2_InnerSnapshotWinsOverPrior (kills RM02 and RM06): the rows
// present at the start of the transaction win over the caller's prior.
func TestCON339R2_InnerSnapshotWinsOverPrior(t *testing.T) {
	db, _ := con339Fixture(t)
	items, segs := r2Issues(t, db)
	h, err := openDB(db)
	if err != nil {
		t.Fatal(err)
	}
	defer h.Close()
	prior := createdAtSnapshot{
		"WIT-001|Issues|section": "1999-09-09 09:09:09",
		"WIT-002|Issues|section": "1999-09-09 09:09:09",
	}
	if err := replaceDocumentWithSnapshot(h, "Issues", items, segs, prior); err != nil {
		t.Fatalf("replaceDocumentWithSnapshot: %v", err)
	}
	h.Close()
	rows := con339Rows(t, db)
	for _, id := range []string{"WIT-001", "WIT-002", "WIT-004"} {
		if got := rows[id+"|Issues|section"]; got != con339Sentinels[id] {
			t.Errorf("%s: created_at %q, want the row's own %q (the in-transaction value wins)", id, got, con339Sentinels[id])
		}
	}
}

// TestCON339R2_ReplaceDocumentWithoutPriorKeepsCreatedAt (kills RM06): the
// nil-prior wrapper still carries every row's own value.
func TestCON339R2_ReplaceDocumentWithoutPriorKeepsCreatedAt(t *testing.T) {
	db, _ := con339Fixture(t)
	items, segs := r2Issues(t, db)
	h, err := openDB(db)
	if err != nil {
		t.Fatal(err)
	}
	if err := replaceDocument(h, "Issues", items, segs); err != nil {
		h.Close()
		t.Fatalf("replaceDocument: %v", err)
	}
	h.Close()
	rows := con339Rows(t, db)
	for _, id := range []string{"WIT-001", "WIT-002", "WIT-004"} {
		if got := rows[id+"|Issues|section"]; got != con339Sentinels[id] {
			t.Errorf("%s: created_at %q, want %q", id, got, con339Sentinels[id])
		}
	}
}

// TestCON339R2_PriorFillsOnlyAbsentKeys: a prior key the transaction does not
// hold is used (the move case); companion of the inner-wins rule.
func TestCON339R2_PriorFillsOnlyAbsentKeys(t *testing.T) {
	db, _ := con339Fixture(t)
	items, segs := r2Issues(t, db)
	// Pretend WIT-002's Issues row is new to this transaction: delete it first
	// (what the Issues transaction of md-to-db does to a moved item).
	rcaExec(t, db, `DELETE FROM items WHERE atm_id='WIT-002'`)
	h, err := openDB(db)
	if err != nil {
		t.Fatal(err)
	}
	prior := createdAtSnapshot{"WIT-002|Issues|section": "2002-02-02 22:22:22"}
	if err := replaceDocumentWithSnapshot(h, "Issues", items, segs, prior); err != nil {
		h.Close()
		t.Fatalf("replaceDocumentWithSnapshot: %v", err)
	}
	h.Close()
	if got := con339Rows(t, db)["WIT-002|Issues|section"]; got != "2002-02-02 22:22:22" {
		t.Errorf("WIT-002 (absent from the transaction): created_at %q, want the prior's 2002-02-02 22:22:22", got)
	}
}

// --- RM03 -----------------------------------------------------------------

// TestCON339R2_NewItemInMarkdownGetsTheWriteTime (kills RM03): a genuinely new
// id loaded by md-to-db gets the time of the write, not any fixed value.
func TestCON339R2_NewItemInMarkdownGetsTheWriteTime(t *testing.T) {
	db, _ := con339Fixture(t)
	other := filepath.Join(t.TempDir(), "other.db")
	con339CopyDB(t, db, other)
	r2Add(t, other, "WIT-006", "r2 item new in Markdown", "Task", "Low")
	before := r2Now(t)
	r2MDRoundTrip(t, other, db)
	after := r2Now(t).Add(time.Second)
	got := con339Rows(t, db)["WIT-006|Issues|section"]
	gt, ok := parseStoredTime(got)
	if !ok {
		t.Fatalf("WIT-006 created_at %q is not a stored time", got)
	}
	if gt.Before(before) || gt.After(after) {
		t.Errorf("WIT-006 created_at %s is outside the write window [%s, %s]", got, before.Format(storedTimeLayout), after.Format(storedTimeLayout))
	}
}

// --- RM05 / RM07 -----------------------------------------------------------

// r2DualRep gives WIT-001 a second, 'table' row in Issues with another
// created_at (a GAP A dual representation).
func r2DualRep(t *testing.T, db string) {
	t.Helper()
	rcaExec(t, db, `INSERT INTO items (atm_id, type, status, title, description, current_location, representation, body_md, created_at, last_modified)
		SELECT atm_id, type, status, title, description, current_location, 'table', body_md, '2019-09-19 19:19:19', last_modified
		FROM items WHERE atm_id='WIT-001' AND representation='section'`)
}

// TestCON339R2_CloseDualRepCarriesTheClosedRowsValue (kills RM05): close moves
// the section row; the Fixed row takes the SECTION row's created_at, not the
// sibling table row's.
func TestCON339R2_CloseDualRepCarriesTheClosedRowsValue(t *testing.T) {
	db, root := con339Fixture(t)
	r2DualRep(t, db)
	if rc := closeCmd([]string{"WIT-001", "--db", db, "--status", "obsolete",
		"--evidence", materialiseEvidence(t, root, "qa/r2/dualrep.md")}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	rows := con339Rows(t, db)
	if got, ok := rows["WIT-001|Fixed|section"]; !ok || got != con339Sentinels["WIT-001"] {
		t.Errorf("WIT-001 Fixed/section created_at %q (present %v), want the closed section row's %q", got, ok, con339Sentinels["WIT-001"])
	}
	if got := rows["WIT-001|Issues|table"]; got != "2019-09-19 19:19:19" {
		t.Errorf("the table sibling changed: %q", got)
	}
}

// TestCON339R2_LookupExactUsesRepresentation (kills RM07).
func TestCON339R2_LookupExactUsesRepresentation(t *testing.T) {
	snap := createdAtSnapshot{
		"WIT-001|Issues|section": "2020-01-01 01:01:01",
		"WIT-001|Issues|table":   "2019-09-19 19:19:19",
	}
	for rep, want := range map[string]string{"section": "2020-01-01 01:01:01", "table": "2019-09-19 19:19:19"} {
		got := snap.lookup("WIT-001", "Issues", rep)
		if got == nil || *got != want {
			t.Errorf("lookup(WIT-001, Issues, %s) = %v, want %s", rep, got, want)
		}
	}
	// A row of another representation is not "the earliest value" when the
	// exact key exists: the section row keeps 2020 although table is earlier.
}

// TestCON339R2_LookupExactUsesLocation: an id with a row in Issues and a row
// in Fixed keeps each row's own value (the key carries the location).
func TestCON339R2_LookupExactUsesLocation(t *testing.T) {
	snap := createdAtSnapshot{}
	snap[createdAtKey("WIT-001", "Issues", "section")] = "2020-01-01 01:01:01"
	snap[createdAtKey("WIT-001", "Fixed", "section")] = "2021-01-01 01:01:01"
	for loc, want := range map[string]string{"Issues": "2020-01-01 01:01:01", "Fixed": "2021-01-01 01:01:01"} {
		got := snap.lookup("WIT-001", loc, "section")
		if got == nil || *got != want {
			t.Errorf("lookup(WIT-001, %s, section) = %v, want %s", loc, got, want)
		}
	}
	if len(snap) != 2 {
		t.Errorf("the two rows share one snapshot key (%d keys)", len(snap))
	}
}

// TestCON339R2_ReplaceDocumentDualRepKeepsEachRowsValue (kills RM07 end to
// end through replaceDocument, when the Markdown carries both rows).
func TestCON339R2_ReplaceDocumentDualRepKeepsEachRowsValue(t *testing.T) {
	db, _ := con339Fixture(t)
	r2DualRep(t, db)
	items, segs := r2Issues(t, db)
	nTable := 0
	for _, it := range items {
		if it.AtmID == "WIT-001" && it.repOrDefault() == "table" {
			nTable++
		}
	}
	t.Logf("db-to-md emitted %d table row(s) of WIT-001 (0 means the hand-built table item below is used)", nTable)
	if nTable == 0 {
		// The renderer does not emit a table row for this fixture; build the
		// parsed item set by hand from the section item instead.
		for _, it := range items {
			if it.AtmID == "WIT-001" {
				tb := it
				tb.Representation = "table"
				items = append(items, tb)
				break
			}
		}
	}
	h, err := openDB(db)
	if err != nil {
		t.Fatal(err)
	}
	if err := replaceDocument(h, "Issues", items, segs); err != nil {
		h.Close()
		t.Fatalf("replaceDocument: %v", err)
	}
	h.Close()
	rows := con339Rows(t, db)
	if got := rows["WIT-001|Issues|section"]; got != con339Sentinels["WIT-001"] {
		t.Errorf("section row %q, want %q", got, con339Sentinels["WIT-001"])
	}
	if got := rows["WIT-001|Issues|table"]; got != "2019-09-19 19:19:19" {
		t.Errorf("table row %q, want its own 2019-09-19 19:19:19", got)
	}
}

// --- restore-created-at ----------------------------------------------------

// r2RCA builds a restore fixture: WIT-010 (Bug) and WIT-011 (Task) with the
// live Opened time liveOpened; the evidence snapshot is taken while the items
// rows hold evItems; afterwards the live rows hold current.
func r2RCA(t *testing.T, liveOpened, evItems, current string) rcaFix {
	t.Helper()
	f := rcaFix{db: newTestDB(t), root: newEvidenceRoot(t)}
	r2Add(t, f.db, "WIT-010", rcaTitle, "Bug", "High")
	r2Add(t, f.db, "WIT-011", "restore fixture item eleven", "Task", "Low")
	rcaExec(t, f.db, `UPDATE item_history SET created_at=? WHERE atm_id IN ('WIT-010','WIT-011') AND event_type='Opened'`, liveOpened)
	rcaExec(t, f.db, `UPDATE items SET created_at=? WHERE atm_id IN ('WIT-010','WIT-011')`, evItems)
	f.ev = "evidence/snapshot.db"
	f.evAbs = filepath.Join(f.root, f.ev)
	if err := os.MkdirAll(filepath.Dir(f.evAbs), 0o755); err != nil {
		t.Fatal(err)
	}
	con339CopyDB(t, f.db, f.evAbs)
	f.sha = rcaSHA(t, f.evAbs)
	rcaExec(t, f.db, `UPDATE items SET created_at=?, last_modified=? WHERE atm_id IN ('WIT-010','WIT-011')`, current, current)
	return f
}

// r2Refused runs the command and asserts the refusal code and that nothing
// was written (items row values and the history count).
func r2Refused(t *testing.T, f rcaFix, code string, args []string) {
	t.Helper()
	ca := rcaQuery(t, f.db, `SELECT group_concat(atm_id||'='||created_at||'@'||last_modified, ',') FROM (SELECT * FROM items ORDER BY atm_id, representation)`)
	h := rcaHistCount(t, f.db)
	rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(args) })
	if rc == exitOK {
		t.Fatalf("accepted; want refusal [%s]", code)
	}
	if !strings.Contains(errOut, "refused ["+code+"]") {
		t.Fatalf("stderr %q does not carry refused [%s]", errOut, code)
	}
	if got := rcaQuery(t, f.db, `SELECT group_concat(atm_id||'='||created_at||'@'||last_modified, ',') FROM (SELECT * FROM items ORDER BY atm_id, representation)`); got != ca {
		t.Errorf("a refused run changed items: %s -> %s", ca, got)
	}
	if got := rcaHistCount(t, f.db); got != h {
		t.Errorf("a refused run wrote history (%s -> %s)", h, got)
	}
}

func r2Accepted(t *testing.T, f rcaFix, args []string) string {
	t.Helper()
	rc, out := captureStdoutRun(t, func() int { return restoreCreatedAtCmd(args) })
	if rc != exitOK {
		t.Fatalf("refused (exit %d); want accepted: %s", rc, out)
	}
	return out
}

// TestRestoreCreatedAtR2_FirstEventBoundary (kills RR01): = the first history
// row is accepted; one second later is refused although the evidence attests it.
func TestRestoreCreatedAtR2_FirstEventBoundary(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 10:00:01", "2026-01-05 12:00:00")
	r2Refused(t, f, "VALUE-AFTER-FIRST-EVENT", f.args("--value", "2026-01-01 10:00:01"))
	r2Accepted(t, f, f.args("--value", "2026-01-01 10:00:00"))
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != "2026-01-01 10:00:00" {
		t.Fatalf("created_at %q after the accepted restore", got)
	}
}

// TestRestoreCreatedAtR2_CurrentValueBoundary (kills RR02 and RR15): a value
// one second later than the current one is refused, in a real run and in a dry
// run alike; the current value itself is "already".
func TestRestoreCreatedAtR2_CurrentValueBoundary(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:30", "2026-01-01 10:00:01", "2026-01-01 10:00:00")
	r2Refused(t, f, "VALUE-LATER-THAN-CURRENT", f.args("--value", "2026-01-01 10:00:01"))
	r2Refused(t, f, "VALUE-LATER-THAN-CURRENT", f.args("--value", "2026-01-01 10:00:01", "--dry-run"))
}

// TestRestoreCreatedAtR2_AlreadyNeedsValidEvidence (kills RR03): "already" is
// answered only after every evidence check passed.
func TestRestoreCreatedAtR2_AlreadyNeedsValidEvidence(t *testing.T) {
	f := rcaFixture(t)
	r2Accepted(t, f, f.args())
	r2Refused(t, f, "EVIDENCE-SHA256", f.args("--evidence-sha256", strings.Repeat("0", 64)))
	junk := filepath.Join(f.root, "evidence", "junk.txt")
	if err := os.WriteFile(junk, []byte("not a database at all, just some text\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	r2Refused(t, f, "EVIDENCE-NOT-DB", f.args("--evidence", "evidence/junk.txt", "--evidence-sha256", rcaSHA(t, junk)))
	out := r2Accepted(t, f, f.args())
	if !strings.Contains(out, "already") {
		t.Fatalf("control: third run is not 'already': %s", out)
	}
}

// r2HistRow inserts one history row through the engine's recordHistory and
// stamps its created_at (a fixture write on a scratch database).
func r2HistRow(t *testing.T, dbPath, id, event, at string) {
	t.Helper()
	h, err := openDB(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer h.Close()
	tx, err := h.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if err := recordHistory(tx, id, event, "AI", "r2 fixture row", ""); err != nil {
		tx.Rollback()
		t.Fatal(err)
	}
	if _, err := tx.Exec(`UPDATE item_history SET created_at=? WHERE id=(SELECT MAX(id) FROM item_history)`, at); err != nil {
		tx.Rollback()
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
}

// TestRestoreCreatedAtR2_OnlyOpenedEventAttests (kills RR04): an Updated row
// of the evidence item at the value does not attest it. The Updated row exists
// in the evidence only, so the live bounds do not refuse the value.
func TestRestoreCreatedAtR2_OnlyOpenedEventAttests(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 09:59:00", "2026-01-05 12:00:00")
	r2HistRow(t, f.evAbs, "WIT-010", "Updated", "2026-01-01 09:59:30")
	h, err := sql.Open("sqlite3", f.evAbs)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		h.Close()
		t.Fatal(err)
	}
	h.Close()
	f.sha = rcaSHA(t, f.evAbs)
	if n := rcaQuery(t, f.evAbs, `SELECT COUNT(1) FROM item_history WHERE atm_id='WIT-010' AND event_type='Updated' AND created_at='2026-01-01 09:59:30'`); n != "1" {
		t.Fatalf("control: evidence Updated row count %s", n)
	}
	r2Refused(t, f, "EVIDENCE-DOES-NOT-ATTEST", f.args("--value", "2026-01-01 09:59:30"))
	// Control: the Opened time is attested and accepted.
	r2Accepted(t, f, f.args("--value", "2026-01-01 10:00:00"))
}

// TestRestoreCreatedAtR2_EvidenceTypeMustMatch (kills RR05).
func TestRestoreCreatedAtR2_EvidenceTypeMustMatch(t *testing.T) {
	f := rcaFixture(t)
	rcaExec(t, f.db, `UPDATE items SET type='Task' WHERE atm_id='WIT-010'`)
	r2Refused(t, f, "EVIDENCE-ITEM-MISMATCH", f.args())
}

// TestRestoreCreatedAtR2_EvidenceTitleMustMatch: the title half of the identity.
func TestRestoreCreatedAtR2_EvidenceTitleMustMatch(t *testing.T) {
	f := rcaFixture(t)
	rcaExec(t, f.db, `UPDATE items SET title='another title entirely' WHERE atm_id='WIT-010'`)
	r2Refused(t, f, "EVIDENCE-ITEM-MISMATCH", f.args())
}

// TestRestoreCreatedAtR2_EveryEvidenceRowIdentityChecked (kills RR10): the
// evidence holds WIT-010 twice (section and table); the second row has another
// title, so the evidence does not identify the live item.
func TestRestoreCreatedAtR2_EveryEvidenceRowIdentityChecked(t *testing.T) {
	f := rcaFixture(t)
	h, err := sql.Open("sqlite3", f.evAbs)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.Exec(`INSERT INTO items (atm_id, type, status, title, description, current_location, representation, body_md, created_at, last_modified)
		SELECT atm_id, type, status, 'a different item that reused the id', description, current_location, 'table', body_md, created_at, last_modified
		FROM items WHERE atm_id='WIT-010'`); err != nil {
		h.Close()
		t.Fatal(err)
	}
	if _, err := h.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		h.Close()
		t.Fatal(err)
	}
	h.Close()
	// Control: the mismatching row is the SECOND row of the id in scan order.
	ordered := rcaQuery(t, f.evAbs, `SELECT group_concat(representation, ',') FROM (SELECT representation FROM items WHERE atm_id='WIT-010')`)
	if ordered != "section,table" {
		t.Fatalf("control: evidence row order %q, want section,table", ordered)
	}
	f.sha = rcaSHA(t, f.evAbs)
	r2Refused(t, f, "EVIDENCE-ITEM-MISMATCH", f.args())
}

// TestRestoreCreatedAtR2_JournalSidecarRefused (kills RR06).
func TestRestoreCreatedAtR2_JournalSidecarRefused(t *testing.T) {
	f := rcaFixture(t)
	if err := os.WriteFile(f.evAbs+"-journal", []byte("hot journal"), 0o644); err != nil {
		t.Fatal(err)
	}
	r2Refused(t, f, "EVIDENCE-WAL", f.args())
	// An EMPTY -journal (and -wal) is not a refusal.
	if err := os.WriteFile(f.evAbs+"-journal", nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(f.evAbs+"-wal", nil, 0o644); err != nil {
		t.Fatal(err)
	}
	r2Accepted(t, f, f.args())
}

// TestRestoreCreatedAtR2_NonCanonicalValues: values time.Parse would accept
// but the stored format does not (RR09 is shown EQUIVALENT in the round-2
// evidence: the stored-format regexp refuses these before the round trip).
func TestRestoreCreatedAtR2_NonCanonicalValues(t *testing.T) {
	f := rcaFixture(t)
	for _, v := range []string{"2026-01-01 5:34:35", "2026-01-01 10:00:00.0", "2026-1-01 10:00:00", "2026-01-01 24:00:00", "2026-01-01 10:00:60"} {
		r2Refused(t, f, "VALUE-FORMAT", f.args("--value", v))
		if _, ok := parseStoredTime(v); ok {
			t.Errorf("parseStoredTime(%q) accepted", v)
		}
	}
}

// TestRestoreCreatedAtR2_ConcurrentChangeIsRefused (kills RR07): the row is
// changed by another connection after the checks and before the write; the
// compare-and-set UPDATE matches no row and nothing is written.
func TestRestoreCreatedAtR2_ConcurrentChangeIsRefused(t *testing.T) {
	f := rcaFixture(t)
	t.Cleanup(func() { rcaBeforeWriteHook = nil })
	rcaBeforeWriteHook = func() {
		rcaExec(t, f.db, `UPDATE items SET created_at='2026-01-03 03:03:03' WHERE atm_id='WIT-010'`)
	}
	h := rcaHistCount(t, f.db)
	rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(f.args()) })
	rcaBeforeWriteHook = nil
	if rc == exitOK || !strings.Contains(errOut, "refused [CONCURRENT-CHANGE]") {
		t.Fatalf("exit %d, stderr %q; want refused [CONCURRENT-CHANGE]", rc, errOut)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != "2026-01-03 03:03:03" {
		t.Errorf("the concurrent value was overwritten: %q", got)
	}
	if got := rcaHistCount(t, f.db); got != h {
		t.Errorf("history written on a refused write (%s -> %s)", h, got)
	}
}

// TestRestoreCreatedAtR2_AuditFailureRollsBack: when the audit row cannot be
// written, the UPDATE is rolled back ([WRITE], nothing changed).
func TestRestoreCreatedAtR2_AuditFailureRollsBack(t *testing.T) {
	f := rcaFixture(t)
	t.Cleanup(func() { rcaBeforeWriteHook = nil })
	rcaBeforeWriteHook = func() {
		rcaExec(t, f.db, `CREATE TRIGGER r2_no_history BEFORE INSERT ON item_history BEGIN SELECT RAISE(ABORT, 'r2 audit blocked'); END`)
	}
	ca := rcaQuery(t, f.db, `SELECT created_at||'@'||last_modified FROM items WHERE atm_id='WIT-010'`)
	h := rcaHistCount(t, f.db)
	rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(f.args()) })
	rcaBeforeWriteHook = nil
	if rc == exitOK || !strings.Contains(errOut, "refused [WRITE]") {
		t.Fatalf("exit %d, stderr %q; want refused [WRITE]", rc, errOut)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at||'@'||last_modified FROM items WHERE atm_id='WIT-010'`); got != ca {
		t.Errorf("items row changed although the audit failed: %s -> %s", ca, got)
	}
	if got := rcaHistCount(t, f.db); got != h {
		t.Errorf("history changed (%s -> %s)", h, got)
	}
}

// TestRestoreCreatedAtR2_DryRunDoesNotWrite: the seam is never reached by a
// dry run, and the dry run writes nothing.
func TestRestoreCreatedAtR2_DryRunDoesNotWrite(t *testing.T) {
	f := rcaFixture(t)
	reached := false
	t.Cleanup(func() { rcaBeforeWriteHook = nil })
	rcaBeforeWriteHook = func() { reached = true }
	out := r2Accepted(t, f, f.args("--dry-run"))
	rcaBeforeWriteHook = nil
	if reached {
		t.Errorf("a dry run reached the write path")
	}
	if !strings.Contains(out, "dry-run") || !strings.Contains(out, "nothing written") {
		t.Errorf("dry-run output %q", out)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != rcaRewritten {
		t.Errorf("dry run wrote %q", got)
	}
}

// TestRestoreCreatedAtR2_ValueBeforeTrackerRefused (F3): a value earlier than
// the live tracker's earliest history row is refused even with evidence that
// attests it (a self-made evidence database backdating an item).
func TestRestoreCreatedAtR2_ValueBeforeTrackerRefused(t *testing.T) {
	f := rcaFixture(t)
	// Forge: a separate database that says WIT-010 was created in 2000.
	forged := filepath.Join(f.root, "evidence", "forged.db")
	con339CopyDB(t, f.evAbs, forged)
	h, err := sql.Open("sqlite3", forged)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.Exec(`UPDATE items SET created_at='2000-01-01 00:00:00' WHERE atm_id='WIT-010'`); err != nil {
		h.Close()
		t.Fatal(err)
	}
	if _, err := h.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		h.Close()
		t.Fatal(err)
	}
	h.Close()
	r2Refused(t, f, "VALUE-BEFORE-TRACKER", f.args("--value", "2000-01-01 00:00:00",
		"--evidence", "evidence/forged.db", "--evidence-sha256", rcaSHA(t, forged)))
	// Boundary: the tracker's earliest history row itself is accepted.
	earliest := rcaQuery(t, f.db, `SELECT MIN(created_at) FROM item_history`)
	if earliest != rcaOpened {
		t.Fatalf("control: earliest history %q, want %q", earliest, rcaOpened)
	}
	r2Accepted(t, f, f.args("--value", rcaOpened))
}

// TestRestoreCreatedAtR2_ValueBeforeTrackerBoundary: the tracker's earliest
// history row minus rcaTrackerSlack is accepted; one second earlier is refused.
func TestRestoreCreatedAtR2_ValueBeforeTrackerBoundary(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 09:58:59", "2026-01-05 12:00:00")
	r2Refused(t, f, "VALUE-BEFORE-TRACKER", f.args("--value", "2026-01-01 09:58:59"))
	g := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 09:59:00", "2026-01-05 12:00:00")
	r2Accepted(t, g, g.args("--value", "2026-01-01 09:59:00"))
	if rcaTrackerSlack != 60*time.Second {
		t.Fatalf("rcaTrackerSlack %s; this boundary test assumes 60s", rcaTrackerSlack)
	}
}

// TestRestoreCreatedAtR2_DBUnreadable: a live database the engine cannot open
// read-write is refused (a dry run needs a writable database: openDB applies
// the schema).
func TestRestoreCreatedAtR2_DBUnreadable(t *testing.T) {
	f := rcaFixture(t)
	dir := filepath.Dir(f.db)
	if err := os.Chmod(f.db, 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o755); os.Chmod(f.db, 0o644) })
	if fh, err := os.CreateTemp(dir, "probe"); err == nil {
		fh.Close()
		t.Skip("cannot make a read-only directory here (privileges ignore modes)")
	}
	rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(f.args("--dry-run")) })
	if rc == exitOK || !strings.Contains(errOut, "refused [DB-UNREADABLE]") {
		t.Fatalf("exit %d, stderr %q; want refused [DB-UNREADABLE]", rc, errOut)
	}
}

// TestRestoreCreatedAtR2_EvidenceIsLiveDBByLink: a hard link and a symlink to
// the live database are the live database.
func TestRestoreCreatedAtR2_EvidenceIsLiveDBByLink(t *testing.T) {
	f := rcaFixture(t)
	hard := filepath.Join(f.root, "evidence", "hard.db")
	if err := os.Link(f.db, hard); err != nil {
		t.Skipf("hard link not possible here: %v", err)
	}
	r2Refused(t, f, "EVIDENCE-IS-LIVE-DB", f.args("--evidence", "evidence/hard.db", "--evidence-sha256", rcaSHA(t, f.db)))
	sym := filepath.Join(f.root, "evidence", "sym.db")
	if err := os.Symlink(f.db, sym); err != nil {
		t.Fatal(err)
	}
	r2Refused(t, f, "EVIDENCE-IS-LIVE-DB", f.args("--evidence", "evidence/sym.db", "--evidence-sha256", rcaSHA(t, f.db)))
}

// TestRestoreCreatedAtR2_AuditRowContent: the audit row names location,
// representation, the attestation and the evidence path; stdout names the
// sha256.
func TestRestoreCreatedAtR2_AuditRowContent(t *testing.T) {
	f := rcaFixture(t)
	out := r2Accepted(t, f, f.args())
	reason := rcaQuery(t, f.db, `SELECT reason FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`)
	for _, want := range []string{"location=Issues", "representation=section", "attested-by=opened-event:WIT-010", "evidence-sha256=" + f.sha} {
		if !strings.Contains(reason, want) {
			t.Errorf("audit reason %q lacks %q", reason, want)
		}
	}
	if n := rcaQuery(t, f.db, `SELECT COUNT(1) FROM item_history WHERE atm_id='WIT-010' AND event_type='Updated'`); n != "1" {
		t.Errorf("Updated rows for WIT-010: %s, want exactly 1", n)
	}
	if !strings.Contains(out, f.sha) {
		t.Errorf("stdout lacks the evidence sha256: %s", out)
	}
	// Only the targeted row changed.
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-011'`); got != rcaRewritten {
		t.Errorf("WIT-011 changed: %q", got)
	}
}

// TestRestoreCreatedAtR2_ItemsRowAttestationPreferred: when both the items row
// and the Opened row hold the value, the items row is named.
func TestRestoreCreatedAtR2_ItemsRowAttestationPreferred(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 10:00:00", "2026-01-05 12:00:00")
	r2Accepted(t, f, f.args("--value", "2026-01-01 10:00:00"))
	reason := rcaQuery(t, f.db, `SELECT reason FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`)
	if !strings.Contains(reason, "attested-by=items-row:WIT-010") {
		t.Errorf("audit reason %q, want attested-by=items-row", reason)
	}
}

// TestRestoreCreatedAtR2_OtherItemsHistoryDoesNotBound: the first-event bound
// is the TARGET item's own history, not another item's earlier row.
func TestRestoreCreatedAtR2_OtherItemsHistoryDoesNotBound(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 09:59:00", "2026-01-05 12:00:00")
	rcaExec(t, f.db, `UPDATE item_history SET created_at='2025-06-01 00:00:00' WHERE atm_id='WIT-011'`)
	r2Accepted(t, f, f.args("--value", "2026-01-01 09:59:00"))
}

// TestRestoreCreatedAtR2_LateHistoryRowDoesNotBound: the bound is the EARLIEST
// history row of the item, not the last.
func TestRestoreCreatedAtR2_LateHistoryRowDoesNotBound(t *testing.T) {
	f := rcaFixture(t)
	r2HistRow(t, f.db, "WIT-010", "Updated", "2026-01-02 00:00:00")
	r2Accepted(t, f, f.args())
	// and an earlier, later-inserted row lowers the bound:
	g := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 09:59:00", "2026-01-05 12:00:00")
	r2HistRow(t, g.db, "WIT-010", "Updated", "2026-01-01 09:58:00")
	r2Refused(t, g, "VALUE-AFTER-FIRST-EVENT", g.args("--value", "2026-01-01 09:59:00"))
}

// TestRestoreCreatedAtR2_LocationNarrowsTheTarget: --location picks the row;
// the other location's row is not touched.
func TestRestoreCreatedAtR2_LocationNarrowsTheTarget(t *testing.T) {
	f := rcaFixture(t)
	r2Refused(t, f, "ITEM-NOT-FOUND", f.args("--representation", "table"))
	r2Accepted(t, f, f.args("--location", "Issues", "--representation", "section"))
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != rcaOpened {
		t.Fatalf("created_at %q", got)
	}
}

// TestRestoreCreatedAtR2_TrackerBoundIsTheWholeTracker: the lower bound is the
// earliest history row of the TRACKER (any item), not of the target item.
func TestRestoreCreatedAtR2_TrackerBoundIsTheWholeTracker(t *testing.T) {
	f := r2RCA(t, "2026-01-01 10:00:00", "2026-01-01 09:58:30", "2026-01-05 12:00:00")
	rcaExec(t, f.db, `UPDATE item_history SET created_at='2026-01-01 09:00:00' WHERE atm_id='WIT-011'`)
	r2Accepted(t, f, f.args("--value", "2026-01-01 09:58:30"))
}

// TestRestoreCreatedAtR2_TrackerBoundIgnoresMalformedRows: a malformed history
// time of ANOTHER item does not block the bound (only well-formed rows count).
func TestRestoreCreatedAtR2_TrackerBoundIgnoresMalformedRows(t *testing.T) {
	f := rcaFixture(t)
	rcaExec(t, f.db, `UPDATE item_history SET created_at='1999-12-31' WHERE atm_id='WIT-011'`)
	r2Accepted(t, f, f.args())
}

// r2SecondRow copies WIT-010's live row to another (location, representation)
// with the same created_at, so the only thing that separates the two rows is
// the key the compare-and-set UPDATE names.
func r2SecondRow(t *testing.T, f rcaFix, loc, rep string) {
	t.Helper()
	h, err := openDB(f.db)
	if err != nil {
		t.Fatal(err)
	}
	defer h.Close()
	h.SetMaxOpenConns(1)
	for _, q := range []string{
		`CREATE TEMP TABLE r2copy AS SELECT * FROM items WHERE atm_id='WIT-010'`,
		`UPDATE r2copy SET current_location='` + loc + `', representation='` + rep + `'`,
		`INSERT INTO items SELECT * FROM r2copy`,
		`DROP TABLE r2copy`,
	} {
		if _, err := h.Exec(q); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	if got := rcaQuery(t, f.db, `SELECT count(*) FROM items WHERE atm_id='WIT-010' AND created_at=?`, rcaRewritten); got != "2" {
		t.Fatalf("fixture: want two WIT-010 rows holding %s, got %s", rcaRewritten, got)
	}
}

// TestRestoreCreatedAtR2_CASNamesTheLocation: two rows of one id in Issues and
// Fixed hold the same created_at; a restore narrowed to Issues changes only the
// Issues row (kills MR09: an UPDATE that ignores the location matches 2 rows).
func TestRestoreCreatedAtR2_CASNamesTheLocation(t *testing.T) {
	f := rcaFixture(t)
	r2SecondRow(t, f, "Fixed", "section")
	r2Accepted(t, f, f.args("--location", "Issues", "--representation", "section"))
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010' AND current_location='Issues'`); got != rcaOpened {
		t.Fatalf("Issues row created_at %q, want %q", got, rcaOpened)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010' AND current_location='Fixed'`); got != rcaRewritten {
		t.Fatalf("Fixed row created_at %q changed; want %q", got, rcaRewritten)
	}
}

// TestRestoreCreatedAtR2_CASNamesTheRepresentation: the same for a section and
// a table row of one id in Issues (kills MR10).
func TestRestoreCreatedAtR2_CASNamesTheRepresentation(t *testing.T) {
	f := rcaFixture(t)
	r2SecondRow(t, f, "Issues", "table")
	r2Accepted(t, f, f.args("--location", "Issues", "--representation", "section"))
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010' AND representation='section'`); got != rcaOpened {
		t.Fatalf("section row created_at %q, want %q", got, rcaOpened)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010' AND representation='table'`); got != rcaRewritten {
		t.Fatalf("table row created_at %q changed; want %q", got, rcaRewritten)
	}
}

// TestRestoreCreatedAtR2_TrackerMinimumNotARealTimeRefused: a history row that
// matches the stored-format pattern but is not a real time ('2000-13-01 ...')
// sorts first; the lower bound cannot be established and the restore is
// refused, never treated as "no bound" (kills MR07).
func TestRestoreCreatedAtR2_TrackerMinimumNotARealTimeRefused(t *testing.T) {
	f := rcaFixture(t)
	rcaExec(t, f.db, `UPDATE item_history SET created_at='2000-13-01 00:00:00' WHERE atm_id='WIT-011'`)
	r2Refused(t, f, "HISTORY-UNREADABLE", f.args())
}
