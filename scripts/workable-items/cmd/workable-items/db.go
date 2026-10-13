// db.go — SQLite access layer for the workable-items single-source-of-truth.
//
// §11.4.93 / §11.4.95: the DB at docs/workable_items.db is the authoritative
// registry. This file owns schema application + item/segment persistence +
// read-back. CGO go-sqlite3 driver.
package main

import (
	"database/sql"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// schemaSQL is the authoritative DDL, embedded so the binary is self-contained
// (no runtime dependency on the schema.sql file location).
//
//go:embed schema_embed.sql
var schemaSQL string

// openDB opens (creating if absent) the SQLite DB at path and applies the
// schema. The schema is idempotent (CREATE TABLE IF NOT EXISTS), so re-opening
// an existing DB is safe.
//
// HXC-201: a relative path is first anchored against the invoking shell's
// directory (see pathresolve.go) rather than trusted as relative to this
// process's actual cwd — every `--db` flag across every subcommand shares
// this single chokepoint, so the `go run -C` footgun documented in
// pathresolve.go is closed once, here, for the whole tool.
func openDB(path string) (*sql.DB, error) {
	path = resolveInvocationRelative(path)
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return nil, fmt.Errorf("create db dir %q: %w", dir, err)
		}
	}
	db, err := sql.Open("sqlite3", path+"?_foreign_keys=on")
	if err != nil {
		return nil, fmt.Errorf("open sqlite %q: %w", path, err)
	}
	if _, err := db.Exec(schemaSQL); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	// GAP A (v4→v5): rebuild items + doc_segments to the 3-tuple PK + the
	// representation discriminator. MUST run BEFORE migrateColumns so the
	// rebuilt items table is the target of the subsequent ADD COLUMN steps.
	// Idempotent (no-op once `representation` exists), lossless.
	if err := migrateRepresentationColumn(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate representation: %w", err)
	}
	// Forward-compatible migrations for DBs created by an OLDER schema. CREATE
	// TABLE IF NOT EXISTS never alters an existing table, so columns added after
	// a DB was first materialised must be ADDed here. Each step is idempotent
	// (skipped when the column already exists) and lossless (NOT NULL DEFAULT '').
	if err := migrateColumns(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate columns: %w", err)
	}
	// §11.4.90 — a DB materialised before `not-reproducible` joined the closed-set
	// reason vocabulary carries the OLD 5-value CHECK constraint on
	// obsolete_details.reason. SQLite cannot ALTER a CHECK, and CREATE TABLE IF
	// NOT EXISTS never replaces an existing table, so the new value would be
	// rejected. Rebuild the table (lossless, idempotent) when the old CHECK is
	// detected.
	if err := migrateObsoleteReasonCheck(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate obsolete_details CHECK: %w", err)
	}
	// T-A05 (SpecKit-004, v6→v7): item_history.occurred_at + occurred_at_source.
	// Idempotent (no-op once both columns exist), lossless (nullable, no DEFAULT).
	if err := migrateItemHistoryOccurredAt(db); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrate item_history occurred_at: %w", err)
	}
	return db, nil
}

// migrateColumns brings an existing `items` table up to the current schema by
// adding any missing columns. §11.4.104 added created_by + assigned_to; a DB
// materialised under schema_version 2 (or earlier) lacks them and would fail the
// attribution INSERT/SELECT paths. ALTER TABLE … ADD COLUMN preserves all
// existing rows; the NOT NULL DEFAULT ” backfills legacy rows transparently.
func migrateColumns(db *sql.DB) error {
	have, err := itemColumns(db)
	if err != nil {
		return err
	}
	type colDef struct{ name, ddl string }
	wanted := []colDef{
		{"created_by", `ALTER TABLE items ADD COLUMN created_by TEXT NOT NULL DEFAULT ''`},
		{"assigned_to", `ALTER TABLE items ADD COLUMN assigned_to TEXT NOT NULL DEFAULT ''`},
		// §11.4.148/§11.4.149 v4 sub-task hierarchy. NULLABLE (no DEFAULT): a
		// legacy row with NULL parent_atm_id is correctly a top-level item.
		{"parent_atm_id", `ALTER TABLE items ADD COLUMN parent_atm_id TEXT`},
		{"session_ref", `ALTER TABLE items ADD COLUMN session_ref TEXT`},
		// GAP B (v4→v5): per-item closure metadata parsed from Fixed.md pipe-table
		// rows, so db→md can synthesize a pipe row from DB fields. NULLABLE (no
		// DEFAULT): legacy rows + every H2-only item carry NULL and are unaffected.
		{"closure_date", `ALTER TABLE items ADD COLUMN closure_date TEXT`},
		{"round", `ALTER TABLE items ADD COLUMN round TEXT`},
		{"commit_ref", `ALTER TABLE items ADD COLUMN commit_ref TEXT`},
		// v5→v6 (ASSIGNMENT_MECHANISM_DESIGN.md §3.1; §11.4.176/§11.4.119/
		// §11.4.111) group-atomic track-assignment. NULLABLE (no DEFAULT): NULL
		// means "not yet classified" — the correct starting state for every
		// pre-existing row; a later phase's one-time classification pass sets
		// real values, and a later phase's `validate-groups` enforces the
		// totality invariant (every OPEN item must carry non-null values).
		{"destination", `ALTER TABLE items ADD COLUMN destination TEXT`},
		{"logic_group", `ALTER TABLE items ADD COLUMN logic_group TEXT`},
	}
	for _, c := range wanted {
		if have[c.name] {
			continue
		}
		if _, err := db.Exec(c.ddl); err != nil {
			return fmt.Errorf("add column %s: %w", c.name, err)
		}
	}
	// idx_items_parent is created here (NOT in the embedded schema) because the
	// schema is exec'd BEFORE this migration: a pre-v4 items table would not yet
	// have parent_atm_id when the embedded CREATE INDEX ran. By this point the
	// column is guaranteed present (added above or already there).
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_parent ON items(parent_atm_id)`); err != nil {
		return fmt.Errorf("create idx_items_parent: %w", err)
	}
	// v5→v6 (ASSIGNMENT_MECHANISM_DESIGN.md §3.1): same reasoning — created here,
	// not in the embedded schema, because destination/logic_group are guaranteed
	// present only AFTER the ADD COLUMN steps above have run.
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_logic_group ON items(logic_group)`); err != nil {
		return fmt.Errorf("create idx_items_logic_group: %w", err)
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_destination ON items(destination)`); err != nil {
		return fmt.Errorf("create idx_items_destination: %w", err)
	}
	// Performance indexes for high-frequency query patterns (status/type are the
	// primary filter axes for summary generation and gate checks; current_location
	// discriminates open vs closed; created_by/assigned_to are attribution axes).
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_status ON items(status)`); err != nil {
		return fmt.Errorf("create idx_items_status: %w", err)
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_type ON items(type)`); err != nil {
		return fmt.Errorf("create idx_items_type: %w", err)
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_status_type ON items(status, type)`); err != nil {
		return fmt.Errorf("create idx_items_status_type: %w", err)
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_current_location ON items(current_location)`); err != nil {
		return fmt.Errorf("create idx_items_current_location: %w", err)
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_created_by ON items(created_by)`); err != nil {
		return fmt.Errorf("create idx_items_created_by: %w", err)
	}
	if _, err := db.Exec(`CREATE INDEX IF NOT EXISTS idx_items_assigned_to ON items(assigned_to)`); err != nil {
		return fmt.Errorf("create idx_items_assigned_to: %w", err)
	}
	// Keep the schema_version meta marker honest after a successful migration: a
	// DB materialised under an older schema (2/3/4/5) is now at v6 (destination +
	// logic_group + logic_groups, ASSIGNMENT_MECHANISM_DESIGN.md).
	//
	// T048 round-2 review finding F15 (2026-09-30, sibling fix): this comment's
	// own "lexical string compare is safe for single-digit versions" claim is
	// now FALSE now that occurred_at.go's migrateItemHistoryOccurredAt() has
	// landed a v7 -- the exact SAME `value < 'N'` TEXT-comparison pattern
	// there was found+fixed to silently REGRESS a double-digit schema_version
	// (e.g. '10' < '6' is lexicographically TRUE) back down to a stale single-
	// digit value on its NEXT run. Reproduced directly against this clause's
	// own pattern before fixing. CAST forces genuine numeric comparison,
	// matching this column's real monotonic-integer semantics -- defusing the
	// same latent landmine here for consistency with occurred_at.go's fix.
	if _, err := db.Exec(`UPDATE meta SET value='6' WHERE key='schema_version' AND CAST(value AS INTEGER) < 6`); err != nil {
		return err
	}
	return nil
}

// migrateRepresentationColumn (GAP A, v4→v5) rebuilds the `items` and
// `doc_segments` tables when their PRIMARY KEY / shape predates the
// `representation` discriminator. SQLite cannot ALTER a PRIMARY KEY, and a plain
// `ALTER TABLE … ADD COLUMN representation` would leave the old 2-tuple PK
// `(atm_id, current_location)` in force — so HXC-044-style dual representation
// (a pipe-table row AND an H2 section for the SAME id in the SAME tracker) would
// still collide. The rebuild is detected by column presence (no representation
// column ⇒ old shape), is lossless (every existing row copied with
// representation='section', the only value a pre-v5 DB could have held), and is
// idempotent (a no-op once the column exists). Mirrors migrateObsoleteReasonCheck.
//
// MUST run BEFORE migrateColumns's ADD COLUMN steps so those columns survive on
// the rebuilt table; openDB orders the calls accordingly.
func migrateRepresentationColumn(db *sql.DB) error {
	have, err := itemColumns(db)
	if err != nil {
		return err
	}
	if have["representation"] {
		return nil // already current
	}

	// Discover the EXACT current column set of items so the rebuild copies every
	// column a prior migration may have already ADDed (created_by/assigned_to/
	// parent_atm_id/session_ref/version_tags), never dropping data. The rebuilt
	// table is created by the embedded schema's CREATE TABLE (already exec'd in
	// openDB) — but that no-ops on an existing table, so we build the new table
	// explicitly here with the full v5 column set + the 3-tuple PK.
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// 1) Rebuild items with the 3-tuple PK + representation column. The GAP-B
	//    closure-metadata columns are added by migrateColumns's ADD-COLUMN steps
	//    AFTER this rebuild, so they are intentionally absent here. version_tags
	//    is preserved-if-present (it is added lazily by versionTagsCmd, so a DB
	//    that already ran that path would otherwise lose it across this rebuild).
	if _, err := tx.Exec(`CREATE TABLE items_new (
    atm_id           TEXT NOT NULL,
    type             TEXT NOT NULL,
    status           TEXT NOT NULL,
    severity         TEXT,
    title            TEXT NOT NULL,
    description      TEXT NOT NULL,
    forensic_anchor  TEXT,
    closure_criteria TEXT,
    composes_with    TEXT,
    created_by       TEXT NOT NULL DEFAULT '',
    assigned_to      TEXT NOT NULL DEFAULT '',
    -- ATM-627 (C1) defense-in-depth: mirror the fresh-schema CHECK
    -- (schema_embed.sql:70) onto the MIGRATED table so a legacy DB rebuilt
    -- through this path stops silently re-admitting an out-of-set
    -- current_location literal (e.g. the old 'Fixed.md' half-migration class).
    -- §11.4.6 HONEST BOUNDARY: this CHECK would NOT have prevented the ATM-627
    -- committed-DB corruption — that corruption moved an item Issues->Fixed
    -- (BOTH valid closed-set values) while its Issues doc_segment stayed, so the
    -- value never left the set. The renderability guard in validateCmd (sync.go)
    -- is the PRIMARY enforcement for that segment<->item location-mismatch class;
    -- this CHECK guards only the earlier out-of-set literal class. The INSERT
    -- below normalizes the known legacy 'Fixed.md' stray so this CHECK never
    -- bricks openDB() on such a DB.
    current_location TEXT NOT NULL
                     CHECK (current_location IN ('Issues', 'Fixed')) DEFAULT 'Issues',
    body_md          TEXT,
    representation   TEXT NOT NULL DEFAULT 'section'
                     CHECK (representation IN ('section', 'table')),
    parent_atm_id    TEXT,
    session_ref      TEXT,
    version_tags     TEXT,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    last_modified    TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (atm_id, current_location, representation)
)`); err != nil {
		return fmt.Errorf("create items_new: %w", err)
	}
	// Copy every column, defending against optional columns that may or may not
	// exist depending on how old the DB is. created_by/assigned_to were added by
	// the §11.4.104 migration, so a v2-era DB may lack them too — colOrDefaultStr
	// emits the column when present else the empty-string literal (the NOT NULL
	// DEFAULT '' semantics). parent_atm_id/session_ref/version_tags are nullable,
	// so colOrNull. migrateColumns then backfills any still-missing column.
	//
	// ATM-627 (C1): the projected current_location is wrapped in a CASE that maps
	// the known legacy 'Fixed.md' half-migration stray to the closed-set 'Fixed'
	// BEFORE it reaches items_new's new CHECK — so migrating a legacy DB that
	// carries that stray does NOT brick openDB(). Any OTHER out-of-set literal
	// genuinely trips the CHECK (fail-closed, never silently re-admitted). §11.4.6
	// honest boundary: this normalization does not touch the ATM-627 corruption
	// itself (an Issues->Fixed relocation — both valid — with a dangling segment);
	// that class is caught by validateCmd's renderability guard, not by this CHECK.
	if _, err := tx.Exec(`INSERT INTO items_new
		(atm_id, type, status, severity, title, description, forensic_anchor,
		 closure_criteria, composes_with, created_by, assigned_to,
		 current_location, body_md, parent_atm_id, session_ref, version_tags,
		 created_at, last_modified)
		SELECT atm_id, type, status, severity, title, description, forensic_anchor,
		 closure_criteria, composes_with, ` +
		colOrDefaultStr(have, "created_by") + `, ` + colOrDefaultStr(have, "assigned_to") + `,
		 CASE current_location WHEN 'Fixed.md' THEN 'Fixed' ELSE current_location END,
		 body_md, ` + colOrNull(have, "parent_atm_id") + `, ` +
		colOrNull(have, "session_ref") + `, ` + colOrNull(have, "version_tags") + `,
		 created_at, last_modified
		FROM items`); err != nil {
		return fmt.Errorf("copy items rows: %w", err)
	}
	if _, err := tx.Exec(`DROP TABLE items`); err != nil {
		return fmt.Errorf("drop old items: %w", err)
	}
	if _, err := tx.Exec(`ALTER TABLE items_new RENAME TO items`); err != nil {
		return fmt.Errorf("rename items_new: %w", err)
	}

	// 2) Rebuild doc_segments with the representation column (default 'section'
	//    preserves every existing segment's meaning — a pre-v5 DB had at most one
	//    representation per id, the section form).
	if _, err := tx.Exec(`CREATE TABLE doc_segments_new (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    document    TEXT NOT NULL CHECK (document IN ('Issues', 'Fixed')),
    seq         INTEGER NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('item', 'raw')),
    atm_id      TEXT,
    representation TEXT NOT NULL DEFAULT 'section',
    raw         TEXT,
    UNIQUE(document, seq)
)`); err != nil {
		return fmt.Errorf("create doc_segments_new: %w", err)
	}
	if _, err := tx.Exec(`INSERT INTO doc_segments_new
		(id, document, seq, kind, atm_id, raw)
		SELECT id, document, seq, kind, atm_id, raw FROM doc_segments`); err != nil {
		return fmt.Errorf("copy doc_segments rows: %w", err)
	}
	if _, err := tx.Exec(`DROP TABLE doc_segments`); err != nil {
		return fmt.Errorf("drop old doc_segments: %w", err)
	}
	if _, err := tx.Exec(`ALTER TABLE doc_segments_new RENAME TO doc_segments`); err != nil {
		return fmt.Errorf("rename doc_segments_new: %w", err)
	}
	if _, err := tx.Exec(`CREATE INDEX IF NOT EXISTS idx_doc_segments_document ON doc_segments(document)`); err != nil {
		return fmt.Errorf("recreate idx_doc_segments_document: %w", err)
	}
	return tx.Commit()
}

// colOrNull returns the bare column name when present on the source table, else
// the literal NULL — so the rebuild's SELECT compiles whether or not an optional
// column was ever ADDed to the pre-v5 items table.
func colOrNull(have map[string]bool, name string) string {
	if have[name] {
		return name
	}
	return "NULL"
}

// colOrDefaultStr returns the bare column name when present, else the empty
// string literal — for NOT NULL DEFAULT ” columns (created_by/assigned_to) that
// a v2-era pre-attribution items table may lack, so the rebuild's SELECT
// compiles and the rebuilt NOT NULL column receives ” rather than NULL.
func colOrDefaultStr(have map[string]bool, name string) string {
	if have[name] {
		return name
	}
	return "''"
}

// migrateObsoleteReasonCheck rebuilds the obsolete_details table when its live
// CHECK constraint predates the §11.4.90 `not-reproducible` reason value. The
// constraint text is read from sqlite_master; if it already mentions
// 'not-reproducible' the migration is a no-op. Otherwise the table is rebuilt
// preserving every existing row (the standard SQLite "create new, copy, drop,
// rename" pattern), so the new closed-set value becomes insertable on a DB that
// was first materialised under the old 5-value vocabulary.
func migrateObsoleteReasonCheck(db *sql.DB) error {
	var ddl sql.NullString
	if err := db.QueryRow(
		`SELECT sql FROM sqlite_master WHERE type='table' AND name='obsolete_details'`,
	).Scan(&ddl); err != nil {
		if err == sql.ErrNoRows {
			return nil // schema not yet applied (cannot happen post-openDB), nothing to migrate
		}
		return err
	}
	if !ddl.Valid || strings.Contains(ddl.String, "not-reproducible") {
		return nil // already current
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`CREATE TABLE obsolete_details_new (
    atm_id                  TEXT PRIMARY KEY,
    since                   TEXT NOT NULL,
    reason                  TEXT NOT NULL CHECK (reason IN (
                                'superseded-by-design-change',
                                'superseded-by-later-mandate',
                                'feature-removed',
                                'duplicate-of',
                                'unsupported-topology',
                                'not-reproducible'
                            )),
    superseding_item        TEXT NOT NULL,
    triple_check_evidence   TEXT NOT NULL
)`); err != nil {
		return fmt.Errorf("create rebuilt table: %w", err)
	}
	if _, err := tx.Exec(`INSERT INTO obsolete_details_new
		(atm_id, since, reason, superseding_item, triple_check_evidence)
		SELECT atm_id, since, reason, superseding_item, triple_check_evidence
		FROM obsolete_details`); err != nil {
		return fmt.Errorf("copy rows: %w", err)
	}
	if _, err := tx.Exec(`DROP TABLE obsolete_details`); err != nil {
		return fmt.Errorf("drop old table: %w", err)
	}
	if _, err := tx.Exec(`ALTER TABLE obsolete_details_new RENAME TO obsolete_details`); err != nil {
		return fmt.Errorf("rename rebuilt table: %w", err)
	}
	return tx.Commit()
}

// itemColumns returns the set of column names currently present on the `items`
// table (via PRAGMA table_info), so migrateColumns can ADD only what is missing.
func itemColumns(db *sql.DB) (map[string]bool, error) {
	rows, err := db.Query(`PRAGMA table_info(items)`)
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

// item is the in-memory representation of a workable item row.
type item struct {
	AtmID           string
	Type            string
	Status          string
	Severity        string
	Title           string
	Description     string
	ForensicAnchor  string
	ClosureCriteria string
	ComposesWith    string
	CreatedBy       string // §11.4.104 canonical handle that opened the item ("" = legacy)
	AssignedTo      string // §11.4.104 canonical handle the item is assigned to ("" = legacy)
	CurrentLocation string // "Issues" | "Fixed"
	BodyMD          string
	Representation  string // GAP A: "section" (H2 block, default) | "table" (pipe-table row)
	ClosureDate     string // GAP B: pipe-table "Closure" cell ("" = none)
	Round           string // GAP B: pipe-table "Round" cell ("" = none)
	CommitRef       string // GAP B: pipe-table "Commit(s)" cell ("" = none)
	Destination     string // ASSIGNMENT_MECHANISM_DESIGN.md §3.1 — "" = not yet classified
	LogicGroup      string // ASSIGNMENT_MECHANISM_DESIGN.md §3.1 — "" = not yet classified
}

// repOrDefault normalises an item's Representation, defaulting an empty value to
// "section" so callers (CRUD, tests) that don't set it stay correct.
func (it item) repOrDefault() string {
	if it.Representation == "" {
		return "section"
	}
	return it.Representation
}

// segment is one ordered piece of a source document: either an item reference
// or verbatim raw prose.
type segment struct {
	Document       string // "Issues" | "Fixed"
	Seq            int
	Kind           string // "item" | "raw"
	AtmID          string // when Kind=="item"
	Representation string // when Kind=="item": "section" | "table" (GAP A); "" => "section"
	Raw            string // when Kind=="raw"
}

// repOrDefault normalises a segment's Representation, defaulting empty to
// "section" (raw segments + callers that don't set it).
func (s segment) repOrDefault() string {
	if s.Representation == "" {
		return "section"
	}
	return s.Representation
}

// --- T-A02 tracker-writer timing instrumentation --------------------------
// (plan.md T-A02; tasks.md T031; research.md DEC-05)
//
// DEC-05 acceptance criterion: "the instrumentation must not change any
// verdict". Applied literally to this write path: replaceDocument's own
// return value, the items/segments it actually persists, and every existing
// caller's observable behaviour are IDENTICAL whether or not this
// instrumentation is active. Timing is a pure side channel -- a best-effort
// append to a TSV file. A failure to resolve, create, open, or write that
// file is NEVER surfaced as an error from replaceDocument itself (see
// fcTimerEnabled's doc comment for why this deliberately differs from
// fc_timer.sh's own fail-closed contract).
//
// Row shape + env-var contract are REUSED, not reinvented, from fc_timer.sh
// (T028, constitution/scripts/fastcycle/timing/fc_timer.sh) for cross-tool
// joinability -- the SAME TSV (or a TSV sharing the identical 11-column
// header) can be read by whatever consumes bash-emitted rows (e.g. a future
// cycle_report.py):
//   run_id  candidate_fingerprint  id  start_ns  end_ns  duration_ms  verdict
//   checks  fails  warns  extra
//
// This is a Go-NATIVE reimplementation of that contract, not a port: there is
// no practical way for this Go binary to `source` a bash library across a
// process boundary without re-invoking a shell on every row (unacceptable
// latency + correctness risk on the tracker's hot write path). What IS
// reused verbatim: the TSV row shape above, the FC_TIMING="0" opt-out, the
// FC_TIMER_TSV output-path env var, the FC_TIMER_RUN_ID / FC_TIMER_REPO_ROOT
// / FC_TIMER_CANDIDATE_FINGERPRINT override env vars (so a parent process --
// e.g. a future commit_all.sh, T030 -- can export these ONCE and have every
// bash- and Go-emitted row of one logical run share an identical run id and
// candidate fingerprint), and the "date +%s%N"-equivalent honest limit (Go's
// time.Now().UnixNano() is wall-clock, not a true CLOCK_MONOTONIC reading,
// exactly like fc_timer.sh's own documented limitation).
//
// Explicitly OUT OF SCOPE for this instrumentation (see NOTES.md for why):
// lock-acquisition wait-duration timing (a separate T-A02 line item; this
// file has no lock primitive to instrument) and "docs_chain rebaseline"
// timing (the rebaseline logic lives in the SEPARATE constitution/submodules/
// docs_chain Go module, outside this file's scope by the task's own stated
// target -- see NOTES.md S3 for a labeled, out-of-scope proposal).
var (
	fcTimerOnce        sync.Once
	fcTimerRunID       string
	fcTimerFingerprint string
)

// fcTimerResolveIdentity lazily resolves (and memoizes, once per process) the
// run id and candidate fingerprint every timing row this process emits
// shares -- mirrors fc_timer.sh's own "memoized after the first call"
// contract, so every row from one invocation of the workable-items binary is
// internally consistent.
func fcTimerResolveIdentity() (runID, fingerprint string) {
	fcTimerOnce.Do(func() {
		if v := os.Getenv("FC_TIMER_RUN_ID"); v != "" {
			fcTimerRunID = v
		} else {
			fcTimerRunID = fmt.Sprintf("%s_%d", time.Now().UTC().Format("20060102T150405Z"), os.Getpid())
		}
		if v := os.Getenv("FC_TIMER_CANDIDATE_FINGERPRINT"); v != "" {
			fcTimerFingerprint = v
		} else {
			root := os.Getenv("FC_TIMER_REPO_ROOT")
			if root == "" {
				root = "."
			}
			// -C <root> (never a bare `git rev-parse` relying on process cwd)
			// mirrors this same package's own established convention for git
			// invocations under the HXC-201 "invocation-directory mismatch"
			// footgun documented at the top of this file (see group.go's
			// identical `-C` usage).
			out, gerr := exec.Command("git", "-C", root, "rev-parse", "HEAD").Output()
			if gerr != nil {
				fcTimerFingerprint = "UNKNOWN"
			} else if fp := strings.TrimSpace(string(out)); fp != "" {
				fcTimerFingerprint = fp
			} else {
				fcTimerFingerprint = "UNKNOWN"
			}
		}
	})
	return fcTimerRunID, fcTimerFingerprint
}

// fcTimerEnabled reports whether timing instrumentation is active for this
// process, and if so the TSV path to append rows to.
//
// FC_TIMING == "0" disables timing (matches fc_timer.sh's contract exactly:
// any other value, including unset, means enabled).
//
// An UNSET or empty FC_TIMER_TSV also disables timing -- WITHOUT an error.
// This intentionally diverges from fc_timer.sh's own contract, which treats
// "enabled but FC_TIMER_TSV unset" as a FATAL usage error (return 2).
// fc_timer.sh is sourced only by scripts (T029/T030's
// pre_build_verification.sh, commit_all.sh) that were EXPLICITLY WRITTEN to
// export FC_TIMER_TSV before ever calling it -- an unset value there really
// is a wiring bug in that specific script. `workable-items` (this binary)
// has a much broader, timing-UNAWARE caller population (hooks, ad hoc CLI
// invocations, other tools' subprocess calls, every existing agent session
// that has never heard of FC_TIMER_TSV) -- making every one of those
// invocations start failing because of an env var they do not set would
// itself BE the "instrumentation changes a verdict" regression DEC-05
// forbids. Treating an unset FC_TIMER_TSV as "timing is simply off" is
// therefore the safe adaptation for this binary's caller population,
// documented here explicitly rather than silently diverging.
func fcTimerEnabled() (tsvPath string, enabled bool) {
	if os.Getenv("FC_TIMING") == "0" {
		return "", false
	}
	tsvPath = os.Getenv("FC_TIMER_TSV")
	if tsvPath == "" {
		return "", false
	}
	return tsvPath, true
}

// fcTimerAppendRow appends ONE row to the FC_TIMER_TSV file in the
// fc_timer.sh row shape, creating the file (and its parent directory) with
// the canonical header if it does not already exist.
//
// Best-effort by design: any failure to create the directory, open the file,
// or write the row is reported to stderr ONLY (never returned) -- a timing
// plumbing failure must never change the caller's own verdict (see
// fcTimerEnabled's doc comment above).
func fcTimerAppendRow(id string, startNS, endNS int64, verdict string, checks, fails, warns int, extra string) {
	tsvPath, enabled := fcTimerEnabled()
	if !enabled {
		return
	}
	runID, fingerprint := fcTimerResolveIdentity()
	durationMS := (endNS - startNS) / 1_000_000
	if durationMS < 0 {
		// Honest-limits clamp, matching fc_timer.sh: time.Now().UnixNano() is
		// wall-clock, not CLOCK_MONOTONIC; a backward clock adjustment mid-call
		// would otherwise yield a negative, nonsensical duration. start_ns/
		// end_ns below remain the real, unmodified readings either way.
		durationMS = 0
	}
	if dir := filepath.Dir(tsvPath); dir != "" && dir != "." {
		if mkErr := os.MkdirAll(dir, 0o755); mkErr != nil {
			fmt.Fprintf(os.Stderr, "fc_timer(db.go): cannot create directory for FC_TIMER_TSV=%s: %v\n", tsvPath, mkErr)
			return
		}
	}
	needsHeader := false
	if _, statErr := os.Stat(tsvPath); statErr != nil {
		needsHeader = true
	}
	f, openErr := os.OpenFile(tsvPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if openErr != nil {
		fmt.Fprintf(os.Stderr, "fc_timer(db.go): cannot open FC_TIMER_TSV=%s: %v\n", tsvPath, openErr)
		return
	}
	defer f.Close()
	if needsHeader {
		if _, werr := f.WriteString("run_id\tcandidate_fingerprint\tid\tstart_ns\tend_ns\tduration_ms\tverdict\tchecks\tfails\twarns\textra\n"); werr != nil {
			fmt.Fprintf(os.Stderr, "fc_timer(db.go): cannot write header to FC_TIMER_TSV=%s: %v\n", tsvPath, werr)
			return
		}
	}
	safe := strings.NewReplacer("\t", " ", "\n", " ", "\r", " ")
	row := fmt.Sprintf("%s\t%s\t%s\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%s\n",
		runID, fingerprint, safe.Replace(id), startNS, endNS, durationMS, verdict,
		checks, fails, warns, safe.Replace(extra))
	if _, werr := f.WriteString(row); werr != nil {
		fmt.Fprintf(os.Stderr, "fc_timer(db.go): failed to append row to FC_TIMER_TSV=%s: %v\n", tsvPath, werr)
	}
}

// replaceDocument wipes prior state for a document and persists the freshly
// parsed items + segments inside a single transaction (atomic md→db sync).
// Items are keyed by atm_id (PRIMARY KEY); an atm_id may appear in only one
// document, which the parser guarantees by partitioning Issues vs Fixed.
//
// T-A02 (tasks.md T031): requested_at is the moment THIS write is REQUESTED
// -- function entry, before db.Begin() is even called (so a future
// connection-pool contention delay inside db.Begin() itself is counted as
// part of the write's own latency, not hidden ahead of the timer).
// applied_at is the moment the write attempt CONCLUDES -- the deferred
// row-emission below runs after EVERY return path (success or failure),
// reading the function's own named return value `err`. On a FAIL verdict
// "applied_at" means "the write attempt concluded (and was rolled back) at
// this time", not "was durably applied" -- the field name is kept symmetric
// with the PASS case (matching fc_timer.sh's own single start/end
// bracketing convention, which likewise times a section regardless of its
// verdict) but this asymmetry is stated here explicitly rather than left to
// be inferred (S11.4.6).
func replaceDocument(db *sql.DB, document string, items []item, segs []segment) (err error) {
	requestedNS := time.Now().UnixNano()
	defer func() {
		verdict, checks, fails, warns := "PASS", 1, 0, 0
		if err != nil {
			verdict, checks, fails, warns = "FAIL", 0, 1, 0
		}
		appliedNS := time.Now().UnixNano()
		extra := fmt.Sprintf("document=%s;items=%d;segments=%d", document, len(items), len(segs))
		fcTimerAppendRow("tracker-writer:"+document, requestedNS, appliedNS, verdict, checks, fails, warns, extra)
	}()

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	// Clear segments for this document; clear items whose current_location is
	// this document (so a full two-document sync rebuilds everything).
	//
	// §11.4.148 D3: also clear the operator_block_details rows OWNED by this
	// document's items BEFORE the items are deleted (the sub-select needs the
	// items table intact) so the reconstruction below is idempotent — a re-sync
	// after an item leaves Operator-blocked (or leaves this tracker) drops its
	// stale OBD row instead of orphaning it.
	if _, err := tx.Exec(`DELETE FROM operator_block_details
		WHERE atm_id IN (SELECT atm_id FROM items WHERE current_location = ?)`, document); err != nil {
		return fmt.Errorf("clear operator_block_details: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM doc_segments WHERE document = ?`, document); err != nil {
		return fmt.Errorf("clear segments: %w", err)
	}
	if _, err := tx.Exec(`DELETE FROM items WHERE current_location = ?`, document); err != nil {
		return fmt.Errorf("clear items: %w", err)
	}

	insItem, err := tx.Prepare(`INSERT INTO items
		(atm_id, type, status, severity, title, description,
		 forensic_anchor, closure_criteria, composes_with,
		 created_by, assigned_to, current_location, body_md,
		 representation, closure_date, round, commit_ref)
		VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`)
	if err != nil {
		return err
	}
	defer insItem.Close()

	// §11.4.148 D3 — reconstruct the operator_block_details sub-table from each
	// Operator-blocked item's `**Operator-Block-Details:**` body block. Without
	// this, md→db left the sub-table empty and `validate` reported every
	// Operator-blocked item as "no operator_block_details row" (the RED). Uses
	// INSERT OR REPLACE (idempotent; atm_id PK) mirroring mutate.go's block path.
	insOBD, err := tx.Prepare(`INSERT OR REPLACE INTO operator_block_details
		(atm_id, what, why_exhausted_alternatives, unblock_condition, who)
		VALUES (?,?,?,?,?)`)
	if err != nil {
		return err
	}
	defer insOBD.Close()

	for _, it := range items {
		if _, err := insItem.Exec(it.AtmID, it.Type, it.Status,
			nullable(it.Severity), it.Title, it.Description,
			nullable(it.ForensicAnchor), nullable(it.ClosureCriteria),
			nullable(it.ComposesWith), it.CreatedBy, it.AssignedTo,
			it.CurrentLocation, it.BodyMD, it.repOrDefault(),
			nullable(it.ClosureDate), nullable(it.Round), nullable(it.CommitRef)); err != nil {
			return fmt.Errorf("insert item %s [%s]: %w", it.AtmID, it.repOrDefault(), err)
		}
		// Repopulate operator_block_details only for Operator-blocked items whose
		// body actually carries the block (a genuinely-missing block stays absent
		// so the §11.4.148 D3 validator can still catch it). The 'section'
		// representation guard skips a pipe-table 'table' row for the same id,
		// which carries no OBD block of its own.
		if it.Status == "Operator-blocked" && it.repOrDefault() == "section" {
			if ob, ok := parseOperatorBlockDetails(it.BodyMD); ok {
				if _, err := insOBD.Exec(it.AtmID, ob.what, ob.why,
					ob.unblock, nullable(ob.who)); err != nil {
					return fmt.Errorf("insert operator_block_details %s: %w", it.AtmID, err)
				}
			}
		}
	}

	insSeg, err := tx.Prepare(`INSERT INTO doc_segments
		(document, seq, kind, atm_id, representation, raw) VALUES (?,?,?,?,?,?)`)
	if err != nil {
		return err
	}
	defer insSeg.Close()

	for _, s := range segs {
		if _, err := insSeg.Exec(s.Document, s.Seq, s.Kind,
			nullable(s.AtmID), s.repOrDefault(), nullableRaw(s.Raw, s.Kind)); err != nil {
			return fmt.Errorf("insert segment %s#%d: %w", s.Document, s.Seq, err)
		}
	}

	if _, err := tx.Exec(`UPDATE meta SET value=?, last_modified=datetime('now') WHERE key='last_sync_direction'`, "md-to-db"); err != nil {
		return err
	}
	if _, err := tx.Exec(`UPDATE meta SET value=datetime('now') WHERE key='last_sync_timestamp'`); err != nil {
		return err
	}
	return tx.Commit()
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// nullableRaw stores raw only for raw segments (empty raw on an item segment
// is legitimate and must remain NULL).
func nullableRaw(s, kind string) any {
	if kind != "raw" {
		return nil
	}
	return s
}

// loadItems returns every item row, ordered by atm_id.
//
// ASSIGNMENT_MECHANISM_DESIGN.md §3.1: destination + logic_group (added to the
// `items` table by P1, ATM-659) are included here so every caller of loadItems
// — validate-groups (P2, this phase) foremost — can read them. Purely
// additive: two new trailing struct fields + two new SELECT columns; every
// existing caller (validateCmd, export, sync round-trip) is unaffected because
// none of them constructs an `item{}` via positional (unkeyed) literal.
func loadItems(db *sql.DB) ([]item, error) {
	rows, err := db.Query(`SELECT atm_id, type, status,
		COALESCE(severity,''), title, description,
		COALESCE(forensic_anchor,''), COALESCE(closure_criteria,''),
		COALESCE(composes_with,''),
		COALESCE(created_by,''), COALESCE(assigned_to,''),
		current_location, COALESCE(body_md,''),
		COALESCE(representation,'section'), COALESCE(closure_date,''),
		COALESCE(round,''), COALESCE(commit_ref,''),
		COALESCE(destination,''), COALESCE(logic_group,'')
		FROM items ORDER BY atm_id, current_location, representation`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.AtmID, &it.Type, &it.Status, &it.Severity,
			&it.Title, &it.Description, &it.ForensicAnchor,
			&it.ClosureCriteria, &it.ComposesWith,
			&it.CreatedBy, &it.AssignedTo, &it.CurrentLocation,
			&it.BodyMD, &it.Representation, &it.ClosureDate,
			&it.Round, &it.CommitRef, &it.Destination, &it.LogicGroup); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// renderDocument reassembles a document's source text from doc_segments +
// items.body_md, walked in seq order — the byte-identical-round-trip path.
func renderDocument(db *sql.DB, document string) (string, error) {
	// Body lookup scoped to THIS document AND keyed by (atm_id, representation):
	// the same atm_id may exist in both trackers (Issues tombstone + Fixed
	// closure) AND, within ONE tracker, under BOTH a pipe-table row + an H2
	// section (GAP A — HXC-044). Keying on atm_id alone would cross-wire the two
	// representations' bodies; the segment carries which representation it points
	// to, so the lookup key is atm_id + "\x00" + representation.
	bodyByKey := map[string]string{}
	brows, err := db.Query(`SELECT atm_id, representation, status, COALESCE(body_md,'')
		FROM items WHERE current_location = ?`, document)
	if err != nil {
		return "", err
	}
	for brows.Next() {
		var id, rep, status, body string
		if err := brows.Scan(&id, &rep, &status, &body); err != nil {
			brows.Close()
			return "", err
		}
		// ATM-627 (task #20) generator-symmetry: emit the `**Status:**` line from the
		// authoritative items.status column so a directly-mutated (stale-body) item
		// still renders a column-consistent Status line. STRICT no-op for every synced
		// item (lastBodyStatus(body)==status BY CONSTRUCTION on a clean md→db import) →
		// the byte-identical round-trip is preserved; only a genuinely desynced item's
		// Status line is rewritten, and its `**Reopened-Details:**` /
		// `**Operator-Block-Details:**` blocks + all other content are preserved verbatim
		// (see canonicalizeBodyStatusLine, parse.go).
		bodyByKey[id+"\x00"+rep] = canonicalizeBodyStatusLine(body, status)
	}
	brows.Close()
	if err := brows.Err(); err != nil {
		return "", err
	}

	rows, err := db.Query(`SELECT seq, kind, COALESCE(atm_id,''), representation, COALESCE(raw,'')
		FROM doc_segments WHERE document = ? ORDER BY seq`, document)
	if err != nil {
		return "", err
	}
	defer rows.Close()

	var sb []byte
	// ATM-627 (WRITER, §11.4.115): a `## <heading>` at the START of a segment
	// (an item body always begins with its H2 heading; a raw section-header
	// segment does too) MUST land at a line-start so the `^## `-anchored reader
	// (parseIssues) can see it. When the PRECEDING content ends on a non-newline
	// byte — the data state the `update`/`repair-bodies` body-mutation path leaves
	// (item body_md ending `…PROGRESS.md.` with NO trailing "\n") — a verbatim
	// concatenation glues the heading mid-line (`…PROGRESS.md.## AP. [ATM-381] …`),
	// SILENTLY ABSORBING the next item into the previous body (wrong
	// body/status/type) + reporting it "absent in Markdown". appendSegment inserts
	// exactly ONE separating "\n" iff the about-to-append content starts with a
	// heading AND sb does not already end with "\n" — idempotent (fires ONLY on the
	// non-newline-terminated case, never double-inserts) and byte-identical for
	// every already-well-formed item (whose preceding body ends "\n\n", so sb ends
	// "\n" and no separator is added). Fix at the WRITER, not the reader.
	//
	// F-DBTOOL defense-in-depth (2026-07-12): the original guard only covered a
	// glued HEADING (content starting "## "). A newline-less body followed by
	// a segment that does NOT start with "## " — e.g. a pipe-TABLE row
	// (content starting "| ") — was still glued onto the tail of the preceding
	// body with zero separation, verbatim-concatenating the two segments'
	// TEXT into one unparseable run. Reproduced live: a body left newline-less
	// by a mutation-path bug (see injectObsoleteDetails / docs/research/
	// f_dbtool_20260712/ROOTCAUSE.md) glued the FOLLOWING closure pipe-row
	// directly onto its tail, and because that pipe row no longer began a line
	// on its own, parseFixed absorbed EVERY item from that point on into the
	// glued body — reporting ~188 items "absent in Markdown". Generalising the
	// separator condition to "whenever the preceding buffer doesn't already
	// end in a newline" (dropping the "## "-only restriction) closes the WHOLE
	// glue-defect class, not just the heading instance, while remaining a
	// strict no-op for every well-formed body (which always ends "\n" or
	// "\n\n") — so the existing byte-identical round-trip fixtures are
	// unaffected (proven by the full test suite staying green after this
	// change).
	appendSegment := func(content string) {
		if len(sb) > 0 && sb[len(sb)-1] != '\n' {
			sb = append(sb, '\n')
		}
		sb = append(sb, content...)
	}
	for rows.Next() {
		var seq int
		var kind, atmID, rep, raw string
		if err := rows.Scan(&seq, &kind, &atmID, &rep, &raw); err != nil {
			return "", err
		}
		switch kind {
		case "raw":
			appendSegment(raw)
		case "item":
			if rep == "" {
				rep = "section"
			}
			body, ok := bodyByKey[atmID+"\x00"+rep]
			if !ok {
				return "", fmt.Errorf("segment references unknown item %q [%s]", atmID, rep)
			}
			appendSegment(body)
		}
	}
	return string(sb), rows.Err()
}
