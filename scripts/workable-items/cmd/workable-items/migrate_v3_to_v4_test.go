// migrate_v3_to_v4_test.go — §11.4.149 schema v3→v4 migration unit tests.
//
// Proves the migration is NON-DESTRUCTIVE: a DB materialised under an OLDER
// schema (items table WITHOUT parent_atm_id / session_ref) is brought up to
// the CURRENT schema by openDB→migrateColumns with every pre-existing row
// preserved + backfilled as top-level (parent_atm_id IS NULL), schema_version
// advanced to the current version (currently '6' — see the in-body assertions
// + §11.4.120 reconciliation note where the literal is checked; this header
// intentionally does not hardcode the number twice), and the new test_diary
// table + view + indexes present.
package main

import (
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

// makeV3LikeDB hand-builds a DB whose `items` table predates the v4 columns
// (the shape an older schema_version produced), seeds rows, and stamps
// schema_version='3'. This is the artifact migrateColumns must upgrade.
func makeV3LikeDB(t *testing.T) string {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "v3.db")
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
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_modified TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (atm_id, current_location)
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL, last_modified TEXT NOT NULL DEFAULT (datetime('now')));
INSERT INTO meta(key,value) VALUES ('schema_version','3'),('last_sync_direction','md-to-db'),('last_sync_timestamp','2026-06-09T00:00:00Z'),('integrity_hash','abc');
INSERT INTO items(atm_id,type,status,title,description,current_location) VALUES
  ('ATM-001','Bug','Queued','t1','desc one with enough words here for floor','Issues'),
  ('ATM-002','Task','In progress','t2','desc two with enough words here for floor','Issues'),
  ('ATM-003','Feature','Fixed (→ Fixed.md)','t3','desc three with enough words here floor','Fixed');
`
	if _, err := raw.Exec(ddl); err != nil {
		t.Fatalf("seed v3 DDL: %v", err)
	}
	return dbPath
}

func TestMigrateV3ToV4NonDestructive(t *testing.T) {
	dbPath := makeV3LikeDB(t)

	// Pre-condition: items has no parent_atm_id, schema_version=3.
	if cols := pragmaCols(t, dbPath); cols["parent_atm_id"] {
		t.Fatalf("pre-migration items unexpectedly has parent_atm_id")
	}
	if v := metaVal(t, dbPath, "schema_version"); v != "3" {
		t.Fatalf("pre schema_version = %q, want 3", v)
	}

	// openDB runs the embedded schema (IF NOT EXISTS no-ops) + migrateColumns.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (migrate): %v", err)
	}
	defer db.Close()

	// Rows preserved: still 3, every one backfilled top-level (parent_atm_id NULL).
	var total, topLevel int
	_ = db.QueryRow(`SELECT COUNT(*) FROM items`).Scan(&total)
	_ = db.QueryRow(`SELECT COUNT(*) FROM items WHERE parent_atm_id IS NULL`).Scan(&topLevel)
	if total != 3 {
		t.Fatalf("post-migration item count = %d, want 3 (no rows lost)", total)
	}
	if topLevel != 3 {
		t.Fatalf("top-level (NULL parent) count = %d, want 3 (backfill)", topLevel)
	}

	// schema_version advanced to 6, then further to 7 by T-A05's
	// item_history.occurred_at migration (§11.4.120 reconciled 2026-09-29 —
	// same pattern as the prior v6 reconciliation this comment already
	// documents: the literal tracks whatever migration ran most recently).
	var ver string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver)
	if ver != "7" {
		t.Fatalf("post schema_version = %q, want 7", ver)
	}

	// Live sync state preserved (INSERT OR IGNORE did NOT clobber it).
	var lastDir string
	_ = db.QueryRow(`SELECT value FROM meta WHERE key='last_sync_direction'`).Scan(&lastDir)
	if lastDir != "md-to-db" {
		t.Fatalf("last_sync_direction = %q, want md-to-db (preserved across re-open)", lastDir)
	}

	// New v4 + v5 columns present (GAP-A representation discriminator + GAP-B
	// closure-metadata columns added non-destructively on top of the v3 table).
	cols := pragmaColsDB(t, db)
	for _, c := range []string{"parent_atm_id", "session_ref", "representation", "closure_date", "round", "commit_ref"} {
		if !cols[c] {
			t.Errorf("post-migration items missing column %s", c)
		}
	}

	// GAP A: the items PK was rebuilt to the 3-tuple (atm_id, current_location,
	// representation); the rebuild backfilled every existing row's representation
	// to 'section' (the only value a pre-v5 DB could hold).
	var nonSection int
	_ = db.QueryRow(`SELECT COUNT(*) FROM items WHERE representation <> 'section'`).Scan(&nonSection)
	if nonSection != 0 {
		t.Errorf("post-migration: %d rows with representation <> 'section' (rebuild backfill wrong)", nonSection)
	}
	if pk := itemsPKColumns(t, db); pk != "atm_id,current_location,representation" {
		t.Errorf("post-migration items PK = %q, want atm_id,current_location,representation", pk)
	}

	// test_diary table + view + indexes present.
	for _, obj := range []string{"test_diary", "test_diary_summary", "idx_items_parent", "idx_test_diary_atm_id"} {
		var n int
		_ = db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name=?`, obj).Scan(&n)
		if n != 1 {
			t.Errorf("expected schema object %q present after migration", obj)
		}
	}

	// integrity_check ok.
	var ic string
	_ = db.QueryRow(`PRAGMA integrity_check`).Scan(&ic)
	if ic != "ok" {
		t.Fatalf("integrity_check = %q, want ok", ic)
	}
}

func TestMigrateIdempotent(t *testing.T) {
	dbPath := makeV3LikeDB(t)
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
		db.Close()
	}
}

// ---- helpers ----

func pragmaCols(t *testing.T, dbPath string) map[string]bool {
	t.Helper()
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer raw.Close()
	return pragmaColsDB(t, raw)
}

func pragmaColsDB(t *testing.T, db *sql.DB) map[string]bool {
	t.Helper()
	rows, err := db.Query(`PRAGMA table_info(items)`)
	if err != nil {
		t.Fatalf("pragma: %v", err)
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

// itemsPKColumns returns the comma-joined names of the items PRIMARY KEY columns
// in key order (via PRAGMA table_info's pk ordinal), so the test can assert the
// GAP-A rebuild produced the 3-tuple PK.
func itemsPKColumns(t *testing.T, db *sql.DB) string {
	t.Helper()
	rows, err := db.Query(`PRAGMA table_info(items)`)
	if err != nil {
		t.Fatalf("pragma: %v", err)
	}
	defer rows.Close()
	type pkcol struct {
		name string
		ord  int
	}
	var pks []pkcol
	for rows.Next() {
		var cid, notnull, pk int
		var name, typ string
		var dflt any
		if err := rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk); err != nil {
			t.Fatalf("scan: %v", err)
		}
		if pk > 0 {
			pks = append(pks, pkcol{name, pk})
		}
	}
	// sort by pk ordinal
	for i := 1; i < len(pks); i++ {
		for j := i; j > 0 && pks[j-1].ord > pks[j].ord; j-- {
			pks[j-1], pks[j] = pks[j], pks[j-1]
		}
	}
	names := make([]string, len(pks))
	for i, p := range pks {
		names[i] = p.name
	}
	return strings.Join(names, ",")
}

func metaVal(t *testing.T, dbPath, key string) string {
	t.Helper()
	raw, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer raw.Close()
	var v string
	_ = raw.QueryRow(`SELECT value FROM meta WHERE key=?`, key).Scan(&v)
	return v
}
