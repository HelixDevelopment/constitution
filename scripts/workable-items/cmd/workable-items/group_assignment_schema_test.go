// group_assignment_schema_test.go — P1 schema migration unit tests for the
// group-atomic track-assignment mechanism.
//
// Canonical authority: docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §3 (data
// model) + docs/tracks/ASSIGNMENT_MECHANISM_PLAN.md P1 (this phase's exact
// acceptance criteria). §11.4.176/§11.4.119/§11.4.111 (mechanism authority);
// §11.4.115 (RED-baseline-on-the-broken-artifact + polarity check — see
// TestGroupAssignmentSchemaMigration's pre/post condition pair); §11.4.93
// (byte-identical round-trip — verified by the PRE-EXISTING roundtrip_test.go
// / atm627_roundtrip_test.go suite continuing to pass unmodified, since this
// phase does not touch the `item` struct, loadItems, or replaceDocument).
//
// Proves the v5→v6 migration is NON-DESTRUCTIVE: a DB materialised under the
// CURRENT v5 schema (items table WITHOUT destination / logic_group; no
// logic_groups table) is brought up to v6 by openDB→migrateColumns with every
// pre-existing row preserved (same PK, same content, new columns NULL =
// "not yet classified"), the new logic_groups registry table + its indexes
// present (created via the embedded schema's CREATE TABLE IF NOT EXISTS —
// idempotent, no ALTER needed for a brand-new table), and schema_version
// advanced to '6'.
package main

import (
	"database/sql"
	"path/filepath"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// makeV5LikeDB hand-builds a DB whose `items` table matches the CURRENT (pre-
// P1) v5 shape — the shape the LIVE tracked docs/workable_items.db actually
// has today (representation 3-tuple PK, closure_date/round/commit_ref,
// parent_atm_id/session_ref) — but predates destination/logic_group and the
// logic_groups table entirely. This is the artifact migrateColumns (+ the
// embedded schema's CREATE TABLE IF NOT EXISTS) must upgrade.
func makeV5LikeDB(t *testing.T) string {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "v5.db")
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open raw: %v", err)
	}
	defer raw.Close()
	ddl := `
CREATE TABLE items (
  atm_id TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  severity TEXT,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  forensic_anchor TEXT,
  closure_criteria TEXT,
  composes_with TEXT,
  created_by TEXT NOT NULL DEFAULT '',
  assigned_to TEXT NOT NULL DEFAULT '',
  current_location TEXT NOT NULL DEFAULT 'Issues',
  body_md TEXT,
  representation TEXT NOT NULL DEFAULT 'section',
  closure_date TEXT,
  round TEXT,
  commit_ref TEXT,
  parent_atm_id TEXT,
  session_ref TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (atm_id, current_location, representation)
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL, last_modified TEXT NOT NULL DEFAULT (datetime('now')));
INSERT INTO meta(key,value) VALUES ('schema_version','5'),('last_sync_direction','md-to-db'),('last_sync_timestamp','2026-07-04T00:00:00Z'),('integrity_hash','xyz');
INSERT INTO items(atm_id,type,status,title,description,current_location,representation) VALUES
  ('ATM-700','Bug','Queued','p1 fixture one','desc one with enough words here for floor','Issues','section'),
  ('ATM-701','Task','In progress','p1 fixture two','desc two with enough words here for floor','Issues','section'),
  ('ATM-702','Feature','Fixed (→ Fixed.md)','p1 fixture three','desc three with enough words for floor','Fixed','section');
`
	if _, err := raw.Exec(ddl); err != nil {
		t.Fatalf("seed v5 DDL: %v", err)
	}
	return dbPath
}

func TestGroupAssignmentSchemaMigration(t *testing.T) {
	dbPath := makeV5LikeDB(t)

	// ---- PRE-condition (§11.4.115 RED baseline): columns/table ABSENT ----
	if cols := pragmaCols(t, dbPath); cols["destination"] || cols["logic_group"] {
		t.Fatalf("pre-migration items unexpectedly already has destination/logic_group")
	}
	if n := sqliteMasterCount(t, dbPath, "logic_groups"); n != 0 {
		t.Fatalf("pre-migration logic_groups table unexpectedly already exists")
	}
	if v := metaVal(t, dbPath, "schema_version"); v != "5" {
		t.Fatalf("pre schema_version = %q, want 5", v)
	}

	// openDB runs the embedded schema (CREATE TABLE IF NOT EXISTS logic_groups
	// + indexes) + migrateRepresentationColumn (no-op, already v5 shape) +
	// migrateColumns (ADD COLUMN destination/logic_group + their indexes +
	// schema_version bump) + migrateObsoleteReasonCheck (no-op, no
	// obsolete_details table in this minimal fixture).
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (migrate): %v", err)
	}
	defer db.Close()

	// ---- POST-condition (§11.4.115 GREEN): columns/table PRESENT ----
	cols := pragmaColsDB(t, db)
	for _, c := range []string{"destination", "logic_group"} {
		if !cols[c] {
			t.Errorf("post-migration items missing column %s", c)
		}
	}

	// logic_groups table present with the exact §3.2 column set.
	if n := sqliteMasterCountDB(t, db, "logic_groups"); n != 1 {
		t.Fatalf("post-migration logic_groups table missing (sqlite_master count=%d)", n)
	}
	lgCols := pragmaColsForTable(t, db, "logic_groups")
	for _, c := range []string{"group_id", "title", "destination", "priority", "state", "scope_note", "roadmap_ref"} {
		if !lgCols[c] {
			t.Errorf("post-migration logic_groups missing column %s", c)
		}
	}

	// logic_groups is empty — P1 lands schema only, no group DATA (that is a
	// later phase's job, per ASSIGNMENT_MECHANISM_PLAN.md P4/P5).
	var lgCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM logic_groups`).Scan(&lgCount); err != nil {
		t.Fatalf("count logic_groups: %v", err)
	}
	if lgCount != 0 {
		t.Errorf("post-migration logic_groups row count = %d, want 0 (P1 is schema-only)", lgCount)
	}

	// New indexes present (created in migrateColumns for items.*, in the
	// embedded schema for logic_groups.* — both idempotent CREATE INDEX IF NOT
	// EXISTS).
	for _, idx := range []string{"idx_items_logic_group", "idx_items_destination", "idx_logic_groups_destination", "idx_logic_groups_state"} {
		if n := sqliteMasterCountDB(t, db, idx); n != 1 {
			t.Errorf("expected index %q present after migration (count=%d)", idx, n)
		}
	}

	// schema_version advanced to 6, then further to 7 by T-A05's
	// migrateItemHistoryOccurredAt (§11.4.120 reconciled 2026-09-29: this test's
	// fixture assumption about the CURRENT final version is updated to match).
	var ver string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
	if ver != "7" {
		t.Fatalf("post schema_version = %q, want 7", ver)
	}

	// Live sync state preserved (INSERT OR IGNORE / UPDATE ... AND value<'6'
	// did NOT clobber unrelated meta rows).
	var lastDir string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='last_sync_direction'`).Scan(&lastDir)
	if lastDir != "md-to-db" {
		t.Fatalf("last_sync_direction = %q, want md-to-db (preserved across migration)", lastDir)
	}

	// ---- No data loss: same 3 rows, same PK, new columns NULL ("not yet
	// classified" — never invented, never silently defaulted to a real group).
	var total int
	_ = db.QueryRow(`SELECT COUNT(*) FROM items`).Scan(&total)
	if total != 3 {
		t.Fatalf("post-migration item count = %d, want 3 (no rows lost)", total)
	}
	type seed struct {
		atmID, loc, title string
	}
	for _, s := range []seed{
		{"ATM-700", "Issues", "p1 fixture one"},
		{"ATM-701", "Issues", "p1 fixture two"},
		{"ATM-702", "Fixed", "p1 fixture three"},
	} {
		var title string
		var dest, group sql.NullString
		err := db.QueryRow(`SELECT title, destination, logic_group FROM items
			WHERE atm_id=? AND current_location=? AND representation='section'`,
			s.atmID, s.loc).Scan(&title, &dest, &group)
		if err != nil {
			t.Fatalf("row %s [%s] not found after migration (PK changed or row lost): %v", s.atmID, s.loc, err)
		}
		if title != s.title {
			t.Errorf("row %s: title = %q, want %q (content changed by migration)", s.atmID, title, s.title)
		}
		if dest.Valid {
			t.Errorf("row %s: destination = %q, want NULL (unclassified pre-existing row)", s.atmID, dest.String)
		}
		if group.Valid {
			t.Errorf("row %s: logic_group = %q, want NULL (unclassified pre-existing row)", s.atmID, group.String)
		}
	}

	// PK shape unchanged (still the 3-tuple from the v5 fixture — v6 does NOT
	// rebuild the items table, it only ADDs nullable columns).
	if pk := itemsPKColumns(t, db); pk != "atm_id,current_location,representation" {
		t.Errorf("post-migration items PK = %q, want atm_id,current_location,representation (unchanged)", pk)
	}

	var ic string
	_ = db.QueryRow(`PRAGMA integrity_check`).Scan(&ic)
	if ic != "ok" {
		t.Fatalf("integrity_check = %q, want ok", ic)
	}
}

func TestGroupAssignmentSchemaIdempotent(t *testing.T) {
	dbPath := makeV5LikeDB(t)
	for i := 0; i < 3; i++ {
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB #%d: %v", i, err)
		}
		// §11.4.120 reconciled 2026-09-29 (T-A05: schema_version now advances to 7).
		var ver string
		_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
		if ver != "7" {
			t.Fatalf("re-open #%d schema_version = %q, want 7", i, ver)
		}
		var total int
		_ = db.QueryRow(`SELECT COUNT(*) FROM items`).Scan(&total)
		if total != 3 {
			t.Fatalf("re-open #%d item count = %d, want 3", i, total)
		}
		var lgCount int
		_ = db.QueryRow(`SELECT COUNT(*) FROM logic_groups`).Scan(&lgCount)
		if lgCount != 0 {
			t.Fatalf("re-open #%d logic_groups count = %d, want 0", i, lgCount)
		}
		db.Close()
	}
}

// TestFreshDBHasGroupAssignmentSchemaFromCreate proves a BRAND-NEW DB (no
// pre-existing items table at all) gets destination/logic_group + logic_groups
// directly from the embedded schema's CREATE TABLE (not only via the
// migrateColumns ADD-COLUMN back-compat path exercised by the tests above).
func TestFreshDBHasGroupAssignmentSchemaFromCreate(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "fresh.db")
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (fresh): %v", err)
	}
	defer db.Close()

	cols := pragmaColsDB(t, db)
	for _, c := range []string{"destination", "logic_group"} {
		if !cols[c] {
			t.Errorf("fresh DB items missing column %s", c)
		}
	}
	if n := sqliteMasterCountDB(t, db, "logic_groups"); n != 1 {
		t.Errorf("fresh DB missing logic_groups table")
	}
	// §11.4.120 reconciled 2026-09-29 (T-A05: a fresh DB now seeds schema_version=7).
	var ver string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
	if ver != "7" {
		t.Fatalf("fresh DB schema_version = %q, want 7 (seeded)", ver)
	}
}

// ---- helpers (sqlite_master introspection not already covered by
// migrate_v3_to_v4_test.go's pragmaCols / pragmaColsDB / metaVal / itemsPKColumns) ----

func sqliteMasterCount(t *testing.T, dbPath, name string) int {
	t.Helper()
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer raw.Close()
	return sqliteMasterCountDB(t, raw, name)
}

func sqliteMasterCountDB(t *testing.T, db *sql.DB, name string) int {
	t.Helper()
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name=?`, name).Scan(&n); err != nil {
		t.Fatalf("sqlite_master count %q: %v", name, err)
	}
	return n
}

// pragmaColsForTable is the generic (any-table) form of migrate_v3_to_v4_test.go's
// pragmaColsDB, which is hardcoded to `items`.
func pragmaColsForTable(t *testing.T, db *sql.DB, table string) map[string]bool {
	t.Helper()
	rows, err := db.Query(`PRAGMA table_info(` + table + `)`)
	if err != nil {
		t.Fatalf("pragma table_info(%s): %v", table, err)
	}
	defer rows.Close()
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notnull, pk int
		var name, typ string
		var dflt any
		if err := rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk); err != nil {
			t.Fatalf("scan: %v", err)
		}
		cols[name] = true
	}
	return cols
}
