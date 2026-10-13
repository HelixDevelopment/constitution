// version_tags_test.go — §11.4.93 / §11.4.27 unit coverage for the
// release-tag column feature (version_tags.go, operator mandate 2026-05-30).
//
// Scope (per §11.4.27 no-fakes-beyond-unit + §11.4.50 deterministic-consistency):
// only the PURE string-formatting + DB-migration logic is covered here. The
// git-coupled derivation (deriveOpenedInTag / deriveFixedInTags / git) shells
// out to `git log` / `git describe` / `git tag --contains` against live
// repository history — testing those as unit tests would depend on the
// committed tag graph, which is non-deterministic across worktrees and would be
// §11.4.50-flaky. They are deferred to integration-tier (documented in the
// research note). A temp REAL SQLite DB (no mocks) is used for the migration +
// --emit tests — the temp DB IS the real system per §11.4.27.
//
// Units covered:
//   - migrateVersionTagsColumn  (idempotent column-add + schema_version→3 bump)
//   - itemsHasVersionTagsColumn  (exercised by the migration assertions)
//   - renderVersionTagCell       (Issues/Fixed cell formatting, all branches)
//   - itemKeyForGit              (ATM-DERIVED title-key vs id, '#N' suffix strip)
//   - lastLine                   (boundary helper)
//   - versionTagsCmd --emit      (DB read path; NOT the git-derivation path)
package main

import (
	"database/sql"
	"io"
	"os"
	"path/filepath"
	"testing"
)

// readSchemaVersion reads meta.schema_version from a real DB (helper for the
// migration test; not a mock).
func readSchemaVersion(t *testing.T, db *sql.DB) string {
	t.Helper()
	var ver string
	if err := db.QueryRow(`SELECT value FROM meta WHERE key='schema_version'`).Scan(&ver); err != nil {
		t.Fatalf("read schema_version: %v", err)
	}
	return ver
}

// countVersionTagsColumns counts how many columns named version_tags exist on
// items — proves the idempotent ALTER did not duplicate the column.
func countVersionTagsColumns(t *testing.T, db *sql.DB) int {
	t.Helper()
	rows, err := db.Query(`PRAGMA table_info(items)`)
	if err != nil {
		t.Fatalf("PRAGMA table_info: %v", err)
	}
	defer rows.Close()
	n := 0
	for rows.Next() {
		var cid int
		var name, ctype string
		var notnull, pk int
		var dflt any
		if err := rows.Scan(&cid, &name, &ctype, &notnull, &dflt, &pk); err != nil {
			t.Fatalf("scan table_info: %v", err)
		}
		if name == "version_tags" {
			n++
		}
	}
	return n
}

// captureStdout redirects os.Stdout for the duration of fn and returns what fn
// printed. versionTagsCmd writes its --emit output via fmt.Println(os.Stdout),
// so capturing the real os.Stdout is the only faithful way to assert it.
func captureStdout(t *testing.T, fn func() int) string {
	t.Helper()
	orig := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stdout = w
	rc := fn()
	w.Close()
	os.Stdout = orig
	out, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read captured stdout: %v", err)
	}
	if rc != exitOK {
		t.Fatalf("versionTagsCmd returned %d, want exitOK(%d); stdout=%q", rc, exitOK, string(out))
	}
	return string(out)
}

func TestVersionTagsLastLine(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"whitespace only", "   \n\t ", ""},
		{"single line", "abc123", "abc123"},
		{"single line trailing newline", "abc123\n", "abc123"},
		{"two lines", "first\nsecond", "second"},
		{"two lines trailing newline", "first\nsecond\n", "second"},
		{"three lines", "a\nb\nc", "c"},
		{"last line padded", "a\n  b  ", "b"},
		{"trailing blank lines collapse", "a\nb\n\n\n", "b"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := lastLine(tc.in); got != tc.want {
				t.Fatalf("lastLine(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestVersionTagsItemKeyForGit(t *testing.T) {
	longTitle := "This is a very long item title that exceeds forty-eight characters easily"
	cases := []struct {
		name string
		it   item
		want string
	}{
		{
			name: "plain ATM id",
			it:   item{AtmID: "ATM-042", Title: "irrelevant"},
			want: "ATM-042",
		},
		{
			name: "ATM id with PK-collision suffix is stripped",
			it:   item{AtmID: "ATM-042#3", Title: "irrelevant"},
			want: "ATM-042",
		},
		{
			name: "short code id kept verbatim",
			it:   item{AtmID: "BJ-SOURCE", Title: "irrelevant"},
			want: "BJ-SOURCE",
		},
		{
			name: "derived id with short title uses full title",
			it:   item{AtmID: "ATM-DERIVED-ab12cd", Title: "Short title"},
			want: "Short title",
		},
		{
			name: "derived id with long title truncates to 48 chars",
			it:   item{AtmID: "ATM-DERIVED-ab12cd", Title: longTitle},
			want: longTitle[:48],
		},
		{
			name: "derived id with empty title falls back to id",
			it:   item{AtmID: "ATM-DERIVED-ab12cd", Title: "   "},
			want: "ATM-DERIVED-ab12cd",
		},
		{
			name: "derived id with whitespace-padded title is trimmed",
			it:   item{AtmID: "ATM-DERIVED-ab12cd", Title: "  Padded  "},
			want: "Padded",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := itemKeyForGit(tc.it); got != tc.want {
				t.Fatalf("itemKeyForGit(%+v) = %q, want %q", tc.it, got, tc.want)
			}
		})
	}
}

func TestVersionTagsRenderVersionTagCell(t *testing.T) {
	cases := []struct {
		name     string
		jsonStr  string
		location string
		want     string
	}{
		{"empty json Issues", "", "Issues", "—"},
		{"empty json Fixed", "", "Fixed", "—"},
		{"invalid json", "{not json", "Fixed", "—"},
		{"Issues opened_in present", `{"opened_in":"v1.0.0"}`, "Issues", "v1.0.0"},
		{"Issues opened_in empty (pre-first-tag)", `{"opened_in":""}`, "Issues", "—"},
		{"Issues ignores fixed_in", `{"opened_in":"v1.0.0","fixed_in":["v2.0.0"]}`, "Issues", "v1.0.0"},
		{"Fixed single tag", `{"fixed_in":["v1.1.5-dev"]}`, "Fixed", "v1.1.5-dev"},
		{"Fixed multiple tags joined", `{"fixed_in":["v1.1.3-dev","v1.1.4-dev","v1.1.5-dev"]}`, "Fixed", "v1.1.3-dev, v1.1.4-dev, v1.1.5-dev"},
		{"Fixed empty fixed_in", `{"fixed_in":[]}`, "Fixed", "—"},
		{"Fixed no fixed_in field", `{"opened_in":"v1.0.0"}`, "Fixed", "—"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := renderVersionTagCell(tc.jsonStr, tc.location); got != tc.want {
				t.Fatalf("renderVersionTagCell(%q, %q) = %q, want %q",
					tc.jsonStr, tc.location, got, tc.want)
			}
		})
	}
}

func TestVersionTagsMigrationIdempotent(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	// Pre-condition: a freshly-opened DB (base schema) does NOT yet have the
	// version_tags column.
	if has, err := itemsHasVersionTagsColumn(db); err != nil {
		t.Fatalf("itemsHasVersionTagsColumn (pre): %v", err)
	} else if has {
		t.Fatalf("version_tags column unexpectedly present before migration")
	}

	// First migration adds the column. schema_version is already '7' here: openDB
	// seeds a fresh DB at the current schema version ('7' since T-A05's
	// item_history.occurred_at + occurred_at_source landed on top of the prior
	// v6 destination/logic_group + logic_groups group-atomic track-assignment
	// columns — ASSIGNMENT_MECHANISM_DESIGN.md §3.1/§3.2 — on top of the GAP-A
	// representation rebuild + GAP-B closure-metadata columns), and
	// migrateVersionTagsColumn bumps only FORWARD (its `verNum < 3` numeric
	// guard -- T048 round-3 review finding R3-I4, 2026-09-30, fixed the prior
	// lexicographic-string `ver < "3"` comparison, which could regress a DB
	// already past v3 back down to '3'; see version_tags.go's own comment at
	// the guard site for the full fix), so it never downgrades a v7 DB.
	// §11.4.120: this literal is reconciled to the new
	// correct current-version value on every schema_version bump — it is NOT a
	// version_tags-specific invariant, just this test's fixture assumption about
	// "what a fresh DB's schema_version already is" before migrateVersionTagsColumn
	// runs. (RECONCILED 2026-09-29, T035/T-A05: 6 -> 7, per this comment's own
	// documented §11.4.120 process — the migration that ran ahead of this test's
	// assertion changed, the test's fixture assumption is updated to match.)
	if err := migrateVersionTagsColumn(db); err != nil {
		t.Fatalf("migrateVersionTagsColumn (1st): %v", err)
	}
	if has, err := itemsHasVersionTagsColumn(db); err != nil {
		t.Fatalf("itemsHasVersionTagsColumn (post-1): %v", err)
	} else if !has {
		t.Fatalf("version_tags column missing after first migration")
	}
	if ver := readSchemaVersion(t, db); ver != "7" {
		t.Fatalf("schema_version = %q after first migration, want \"7\"", ver)
	}

	// Second migration is a no-op (idempotent) — must not error, must not
	// duplicate the column, must leave schema_version at 7 (forward-only).
	if err := migrateVersionTagsColumn(db); err != nil {
		t.Fatalf("migrateVersionTagsColumn (2nd): %v", err)
	}
	if n := countVersionTagsColumns(t, db); n != 1 {
		t.Fatalf("version_tags column count = %d after 2nd migration, want exactly 1", n)
	}
	if ver := readSchemaVersion(t, db); ver != "7" {
		t.Fatalf("schema_version = %q after second migration, want \"7\"", ver)
	}
}

func TestVersionTagsEmitJSON(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	if err := migrateVersionTagsColumn(db); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	// Seed two items: one with a stored version_tags JSON, one without.
	if _, err := db.Exec(`INSERT INTO items
		(atm_id, type, status, title, description, current_location, version_tags)
		VALUES ('ATM-900','Bug','Fixed (→ Fixed.md)','seeded item','a sufficiently long description for the row','Fixed',?)`,
		`{"opened_in":"v1.0.0","fixed_in":["v1.1.5-dev"]}`); err != nil {
		t.Fatalf("seed tagged item: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO items
		(atm_id, type, status, title, description, current_location)
		VALUES ('ATM-901','Task','Queued','untagged item','a sufficiently long description for the row','Issues')`); err != nil {
		t.Fatalf("seed untagged item: %v", err)
	}
	db.Close()

	// --emit for the tagged item prints the stored JSON verbatim.
	out := captureStdout(t, func() int {
		return versionTagsCmd([]string{"--db", dbPath, "--emit", "ATM-900"})
	})
	wantTagged := `{"opened_in":"v1.0.0","fixed_in":["v1.1.5-dev"]}` + "\n"
	if out != wantTagged {
		t.Fatalf("--emit ATM-900 stdout = %q, want %q", out, wantTagged)
	}

	// --emit for the untagged item prints the empty-object sentinel.
	out = captureStdout(t, func() int {
		return versionTagsCmd([]string{"--db", dbPath, "--emit", "ATM-901"})
	})
	if out != "{}\n" {
		t.Fatalf("--emit ATM-901 stdout = %q, want %q", out, "{}\n")
	}

	// --emit for an unknown id also prints the sentinel (NULL scan path).
	out = captureStdout(t, func() int {
		return versionTagsCmd([]string{"--db", dbPath, "--emit", "ATM-DOES-NOT-EXIST"})
	})
	if out != "{}\n" {
		t.Fatalf("--emit unknown id stdout = %q, want %q", out, "{}\n")
	}
}

// TestMigrateVersionTagsColumn_SchemaVersionNeverRegresses is the T048
// round-3 review finding R3-I4 regression guard: migrateVersionTagsColumn's
// own `ver == "" || ver < "3"` clause (fixed this session) used to compare
// schema_version as TEXT — the exact SAME lexicographic-string-comparison
// bug occurred_at.go's migrateItemHistoryOccurredAt() and db.go's own
// schema_version bump were independently found+fixed for in T048 round-2
// (finding F15; see TestMigrateItemHistoryOccurredAt_SchemaVersionNeverRegresses
// and TestMigrateColumns_SchemaVersionNeverRegresses in occurred_at_test.go).
// R3-I4 proved this THIRD occurrence of the same bug class live: seeding
// schema_version='10' then calling migrateVersionTagsColumn regressed it to
// '3'; a subsequent openDB() re-open (which re-runs db.go's own v6 bump,
// the next migration step above v3 in the chain) then advanced it to '7' —
// the exact 10 -> 3 -> 7 round-trip this test reproduces and asserts against
// BEFORE trusting the fix, per §11.4.199 exact-reproduction-sequence.
// strconv.Atoi now forces a genuine numeric comparison, matching this
// column's real monotonic-integer semantics.
func TestMigrateVersionTagsColumn_SchemaVersionNeverRegresses(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "wi.db")
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()

	// Simulate a DB whose schema_version has already advanced past 3 into
	// double digits (a future migration bumped it well beyond what this
	// column's own migration would ever need to set).
	if _, err := db.Exec(`UPDATE meta SET value='10' WHERE key='schema_version'`); err != nil {
		t.Fatalf("seed schema_version=10: %v", err)
	}

	// Re-run the SAME idempotent migration this test's own name targets --
	// this is exactly what the real `workable-items version-tags`
	// subcommand does every time it runs against an already-advanced DB.
	if err := migrateVersionTagsColumn(db); err != nil {
		t.Fatalf("migrateVersionTagsColumn (on an already-advanced DB): %v", err)
	}
	if ver := readSchemaVersion(t, db); ver != "10" {
		t.Fatalf("schema_version regressed to %q after migrateVersionTagsColumn on an already-advanced DB — want it to stay \"10\" (R3-I4: numeric comparison must not treat '10' as < '3')", ver)
	}

	// The reviewer's own exact reproduction sequence (§11.4.199): reopen the
	// SAME db path afterward and confirm it advances forward through the
	// rest of the migration chain (never bounces off a wrongly-regressed
	// value) — never re-regresses.
	db2, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB (second open): %v", err)
	}
	defer db2.Close()
	if ver := readSchemaVersion(t, db2); ver != "10" {
		t.Fatalf("schema_version = %q after re-opening an already-advanced DB — want it to stay \"10\"", ver)
	}
}
