package main

// CON-456 round 2 (review of d3fa27ac): command-level tests of the one
// round-trip rule. Every test drives the real commands (add, update, block,
// move, sync db-to-md, sync md-to-db, validate, repair-bodies) and only those,
// so the file compiles against the round-1 head and shows its RED there.
//
// Findings covered: F1 (a legacy id with a bracket-id title), F2 (md-to-db
// atomic across both documents), F3 (a legacy id with a leading-space title),
// F4 (a Fixed section item read back as a table row), F8 (a refused add does
// not create the database file), RM06 (an id with outer whitespace), and the
// pre-existing O1 (a heading line inside the title or description) and O2 (a
// status-like suffix in the title), which round 2 fixes in the same class.

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const g456Desc = "a sufficiently long description that clears the description floor for round two"

// g456Dump is a logical dump of every table, read through a read-only handle,
// so a refused command can be shown to have written nothing.
func g456Dump(t *testing.T, path string) string {
	t.Helper()
	db, err := sql.Open("sqlite3", "file:"+path+"?mode=ro")
	if err != nil {
		t.Fatalf("open %s read-only: %v", path, err)
	}
	defer db.Close()
	rows, err := db.Query(`SELECT type, name, COALESCE(sql,'') FROM sqlite_master ORDER BY type, name`)
	if err != nil {
		t.Fatalf("read schema of %s: %v", path, err)
	}
	var b strings.Builder
	var tables []string
	for rows.Next() {
		var typ, name, ddl string
		if err := rows.Scan(&typ, &name, &ddl); err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(&b, "%s %s %s\n", typ, name, ddl)
		if typ == "table" {
			tables = append(tables, name)
		}
	}
	rows.Close()
	for _, tbl := range tables {
		r, err := db.Query(`SELECT * FROM "` + tbl + `" ORDER BY rowid`)
		if err != nil {
			// a WITHOUT ROWID table: dump in primary-key order
			r, err = db.Query(`SELECT * FROM "` + tbl + `" ORDER BY 1`)
			if err != nil {
				t.Fatalf("dump %s: %v", tbl, err)
			}
		}
		cols, _ := r.Columns()
		for r.Next() {
			vals := make([]any, len(cols))
			ptrs := make([]any, len(cols))
			for i := range vals {
				ptrs[i] = &vals[i]
			}
			if err := r.Scan(ptrs...); err != nil {
				t.Fatal(err)
			}
			fmt.Fprintf(&b, "%s:", tbl)
			for _, v := range vals {
				if bs, ok := v.([]byte); ok {
					v = string(bs)
				}
				fmt.Fprintf(&b, " %q", fmt.Sprint(v))
			}
			b.WriteString("\n")
		}
		r.Close()
	}
	return b.String()
}

func g456Exec(t *testing.T, dbPath, q string, args ...any) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(q, args...); err != nil {
		t.Fatalf("exec %q: %v", q, err)
	}
}

func g456Query(t *testing.T, dbPath, q string, args ...any) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var s sql.NullString
	if err := db.QueryRow(q, args...).Scan(&s); err != nil && err != sql.ErrNoRows {
		t.Fatalf("query %q: %v", q, err)
	}
	return s.String
}

func g456Add(t *testing.T, dbPath, id, title, typ, severity string) {
	t.Helper()
	args := []string{"--db", dbPath, "--id", id, "--title", title, "--description", g456Desc, typ}
	if severity != "" {
		args = append(args, severity)
	}
	if rc := addCmd(args); rc != exitOK {
		t.Fatalf("seed add %s exited %d", id, rc)
	}
}

// g456Export writes both trackers of dbPath into dir and returns their paths.
func g456Export(t *testing.T, dbPath, dir string) (string, string) {
	t.Helper()
	iss, fix := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
	if rc := syncDBToMD([]string{"--db", dbPath, "--out-issues", iss, "--out-fixed", fix}); rc != exitOK {
		t.Fatalf("db-to-md exited %d", rc)
	}
	return iss, fix
}

func g456Import(dbPath, iss, fix string) int {
	return syncMDToDB([]string{"--db", dbPath, "--issues", iss, "--fixed", fix})
}

// g456CutBlock removes the item block whose heading starts with prefix from the
// file and returns it.
func g456CutBlock(t *testing.T, path, prefix string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.SplitAfter(string(raw), "\n")
	start := -1
	for i, ln := range lines {
		if strings.HasPrefix(ln, prefix) {
			start = i
			break
		}
	}
	if start < 0 {
		t.Fatalf("no block %q in %s", prefix, path)
	}
	end := start + 1
	for end < len(lines) && !strings.HasPrefix(lines[end], "## ") {
		end++
	}
	block := strings.Join(lines[start:end], "")
	rest := strings.Join(lines[:start], "") + strings.Join(lines[end:], "")
	if err := os.WriteFile(path, []byte(rest), 0o644); err != nil {
		t.Fatal(err)
	}
	return block
}

func g456Append(t *testing.T, path, text string) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	s := string(raw)
	if s != "" && !strings.HasSuffix(s, "\n") {
		s += "\n"
	}
	if err := os.WriteFile(path, []byte(s+"\n"+text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func g456Items(t *testing.T, dbPath string) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	rows, err := db.Query(`SELECT atm_id, current_location, representation, title FROM items ORDER BY atm_id, current_location`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var b strings.Builder
	for rows.Next() {
		var id, loc, rep, title string
		if err := rows.Scan(&id, &loc, &rep, &title); err != nil {
			t.Fatal(err)
		}
		fmt.Fprintf(&b, "%s|%s|%s|%q\n", id, loc, rep, title)
	}
	return b.String()
}

// TestCON456R2_AddRefusesTextTheParserCannotCarry: add refuses an item whose
// Markdown the parser would read back as another id, as two items or with
// another title. A refusal writes nothing: no row in an existing database, and
// no database file at a fresh --db path (F8).
func TestCON456R2_AddRefusesTextTheParserCannotCarry(t *testing.T) {
	cases := []struct{ name, id, prefix, title, desc, cause string }{
		{"F1_legacy_id_bracket_title", "GS-72", "", "[ABC-9] first probe item", g456Desc, `title "[ABC-9] first probe item"`},
		{"F1_legacy_id_bracket_collision", "G71", "", "crash in [CON-123] path probe", g456Desc, `title "crash in [CON-123] path probe"`},
		{"O2_status_suffix_title", "G74", "", "thing — `Fixed (→ Fixed.md)` probe", g456Desc, "title \"thing — `Fixed"},
		{"O1_heading_in_title", "CON-810", "", "a\n## CON-811 — injected", g456Desc, `title "a\n## CON-811`},
		{"O1_heading_in_description", "CON-812", "", "t canon desc heading",
			"line one of the description\n## CON-813 — injected via description\nmore words here to pass the floor", "CON-813"},
		{"O1_heading_in_title_prefix_mode", "", "CON", "a\n## CON-811 — injected", g456Desc, `title "a\n## CON-811`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			args := func(db string) []string {
				a := []string{"--db", db, "--title", c.title, "--description", c.desc}
				if c.id != "" {
					a = append(a, "--id", c.id)
				} else {
					a = append(a, "--prefix", c.prefix)
				}
				return append(a, "Task", "Low")
			}
			fresh := filepath.Join(newTestDB(t))
			if rc := addCmd(args(fresh)); rc == exitOK {
				t.Fatalf("add accepted %q; its Markdown does not read back as this item", c.title)
			}
			if _, err := os.Stat(fresh); !os.IsNotExist(err) {
				t.Fatalf("a refused add created the database file at a fresh path (err=%v)", err)
			}
			existing := newTestDB(t)
			g456Add(t, existing, "CON-001", "an ordinary seed item", "Task", "Low")
			before := g456Dump(t, existing)
			rc, out := captureStderrRun(t, func() int { return addCmd(args(existing)) })
			if rc == exitOK {
				t.Fatalf("add accepted %q into an existing database", c.title)
			}
			// Review F9: the refusal names the text that causes it.
			if c.cause != "" && !strings.Contains(out, c.cause) {
				t.Errorf("refusal does not name the cause %q: %s", c.cause, out)
			}
			if after := g456Dump(t, existing); after != before {
				t.Fatalf("a refused add changed the database:\n%s", firstDiff(before, after))
			}
		})
	}
}

// TestCON456R2_AddTrimsAndRoundTrips: surrounding whitespace of the id (RM06)
// and of the title (F3) is trimmed, and the item then survives db-to-md and
// md-to-db with its id and title. On the round-1 head a legacy id with a
// leading-space title is accepted and every later md-to-db refuses.
func TestCON456R2_AddTrimsAndRoundTrips(t *testing.T) {
	dbPath := newTestDB(t)
	if rc := addCmd([]string{"--db", dbPath, "--id", "  CON-996  ", "--title", "  leading probe title  ",
		"--description", g456Desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("add with outer whitespace exited %d", rc)
	}
	if rc := addCmd([]string{"--db", dbPath, "--id", "G73", "--title", "  leading legacy probe",
		"--description", g456Desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("add of a legacy id with a leading-space title exited %d", rc)
	}
	want := "CON-996|Issues|section|\"leading probe title\"\nG73|Issues|section|\"leading legacy probe\"\n"
	if got := g456Items(t, dbPath); got != want {
		t.Fatalf("stored items:\n got %s\nwant %s", got, want)
	}
	iss, fix := g456Export(t, dbPath, t.TempDir())
	rt := filepath.Join(t.TempDir(), "rt.db")
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db of the exported trackers exited %d", rc)
	}
	if got := g456Items(t, rt); got != want {
		t.Fatalf("items after the round trip:\n got %s\nwant %s", got, want)
	}
	if rc, out := captureStderrRun(t, func() int { return validateCmd([]string{"--db", dbPath}) }); rc != exitOK {
		t.Fatalf("validate exited %d: %s", rc, out)
	}
}

// g456PlantUnreadableFixed adds G77 in Issues, moves it to Fixed, and then
// stores (by SQL, as a database written before round 2 could hold) a title
// with a leading space and the heading it renders: `## G77.   leading …` is not
// a heading the parser reads.
func g456PlantUnreadableFixed(t *testing.T, dbPath string) {
	t.Helper()
	g456Add(t, dbPath, "G77", "probe partial write item", "Task", "Low")
	if rc := moveCmd([]string{"--db", dbPath, "--id", "G77", "--to", "Fixed", "--status", "Fixed",
		"--why", "test: put an item in Fixed"}); rc != exitOK {
		t.Fatalf("move G77 to Fixed exited %d", rc)
	}
	g456Exec(t, dbPath, `UPDATE items SET title='  leading partial-write probe',
		body_md=replace(body_md, '## G77. probe partial write item', '## G77.   leading partial-write probe')
		WHERE atm_id='G77'`)
	if !strings.HasPrefix(g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='G77'`), "## G77.   leading") {
		t.Fatal("plant of the unreadable G77 heading did not take")
	}
}

// g456MoveScenario seeds CON-001 and CON-002 in Issues (and, when plant is set,
// the unreadable G77 in Fixed), exports, and moves the CON-001 block from
// Issues.md to the end of Fixed.md with a Fixed status, as an operator would.
func g456MoveScenario(t *testing.T, plant bool) (dbPath, iss, fix string) {
	t.Helper()
	dbPath = newTestDB(t)
	g456Add(t, dbPath, "CON-001", "item the operator moves by hand", "Task", "Low")
	g456Add(t, dbPath, "CON-002", "item that stays in Issues", "Task", "Low")
	if plant {
		g456PlantUnreadableFixed(t, dbPath)
	}
	iss, fix = g456Export(t, dbPath, t.TempDir())
	block := g456CutBlock(t, iss, "## CON-001 — ")
	moved := strings.Replace(block, "**Status:** Queued", "**Status:** Fixed (→ Fixed.md)", 1)
	if moved == block {
		t.Fatalf("no Status line to change in the moved block:\n%s", block)
	}
	g456Append(t, fix, moved)
	return dbPath, iss, fix
}

// TestCON456R2_MDToDBIsAtomicAcrossDocuments (F2): md-to-db checks both
// documents before its first write and writes both in one transaction. The
// operator moves CON-001 from Issues.md to Fixed.md while Fixed holds an item
// the parser cannot read; the import refuses and the database is unchanged.
// A failure of the Fixed leg itself (a trigger) also leaves it unchanged. The
// control is the same move with neither cause: it is imported.
func TestCON456R2_MDToDBIsAtomicAcrossDocuments(t *testing.T) {
	t.Run("control_move_is_imported", func(t *testing.T) {
		dbPath, iss, fix := g456MoveScenario(t, false)
		if rc, out := captureStderrRun(t, func() int { return g456Import(dbPath, iss, fix) }); rc != exitOK {
			t.Fatalf("md-to-db refused an ordinary move (rc=%d): %s", rc, out)
		}
		if got := g456Query(t, dbPath, `SELECT current_location FROM items WHERE atm_id='CON-001'`); got != "Fixed" {
			t.Fatalf("CON-001 is in %q after the move, want Fixed; items:\n%s", got, g456Items(t, dbPath))
		}
	})
	t.Run("refusal_on_the_Fixed_side", func(t *testing.T) {
		dbPath, iss, fix := g456MoveScenario(t, true)
		before := g456Dump(t, dbPath)
		if rc := g456Import(dbPath, iss, fix); rc == exitOK {
			t.Fatal("md-to-db accepted a Fixed.md whose G77 heading it cannot read")
		}
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused md-to-db changed the database:\n%s", firstDiff(before, after))
		}
	})
	t.Run("failure_of_the_Fixed_leg", func(t *testing.T) {
		dbPath, iss, fix := g456MoveScenario(t, false)
		g456Exec(t, dbPath, `CREATE TRIGGER r2_force_fixed_leg BEFORE INSERT ON items
			WHEN NEW.atm_id='CON-001' AND NEW.current_location='Fixed'
			BEGIN SELECT RAISE(ABORT, 'forced failure of the Fixed leg'); END`)
		before := g456Dump(t, dbPath)
		if rc := g456Import(dbPath, iss, fix); rc == exitOK {
			t.Fatal("md-to-db reported success although the Fixed insert failed")
		}
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a failed md-to-db left a partial write:\n%s", firstDiff(before, after))
		}
	})
}

// TestCON456R2_MDToDBRefusesWhatTheParserWouldLose: a stored item whose
// unchanged Markdown the parser reads as another id (F1), as two items (O1),
// with a cut title (O2), or as a table row instead of a section (F4, the M13
// input) is not replaced on md-to-db: the import refuses, writes nothing, and
// validate reports the item.
func TestCON456R2_MDToDBRefusesWhatTheParserWouldLose(t *testing.T) {
	plantGS72 := func(t *testing.T, dbPath string) {
		g456Add(t, dbPath, "GS-72", "first probe", "Task", "Low")
		g456Exec(t, dbPath, `UPDATE items SET title='[ABC-9] first probe',
			body_md=replace(body_md, '## GS-72. first probe', '## GS-72. [ABC-9] first probe') WHERE atm_id='GS-72'`)
	}
	cases := []struct {
		name  string
		plant func(t *testing.T, dbPath string)
		edit  func(t *testing.T, iss string)
	}{
		{"F1_legacy_bracket_title", plantGS72, nil},
		// The operator edits the item's description: its text is no longer
		// in the Markdown, but its heading line is, and it parses as ABC-9.
		{"F1_legacy_bracket_title_description_edited", plantGS72, func(t *testing.T, iss string) {
			raw, _ := os.ReadFile(iss)
			i := strings.Index(string(raw), "## GS-72. [ABC-9] first probe")
			j := strings.Index(string(raw)[i:], g456Desc)
			if i < 0 || j < 0 {
				t.Fatalf("fixture: GS-72 block not exported as planted:\n%s", raw)
			}
			edited := string(raw)[:i+j] + "an edited description of the probe item, long enough" + string(raw)[i+j+len(g456Desc):]
			if err := os.WriteFile(iss, []byte(edited), 0o644); err != nil {
				t.Fatal(err)
			}
		}},
		{"O1_heading_line_in_description", func(t *testing.T, dbPath string) {
			g456Add(t, dbPath, "CON-810", "description holds a heading", "Task", "Low")
			g456Exec(t, dbPath, `UPDATE items SET body_md=replace(body_md, '`+g456Desc+`', 'line one'||char(10)||'## CON-811 — injected'||char(10)||'more words') WHERE atm_id='CON-810'`)
		}, nil},
		{"O2_status_suffix_title", func(t *testing.T, dbPath string) {
			g456Add(t, dbPath, "G74", "thing probe", "Task", "Low")
			g456Exec(t, dbPath, "UPDATE items SET title='thing — `Fixed (→ Fixed.md)` probe', "+
				"body_md=replace(body_md, '## G74. thing probe', '## G74. thing — `Fixed (→ Fixed.md)` probe') WHERE atm_id='G74'")
		}, nil},
		{"F4_fixed_section_read_as_table_row", func(t *testing.T, dbPath string) {
			g456Add(t, dbPath, "CON-900", "section that holds a pipe row", "Bug", "Low")
			if rc := moveCmd([]string{"--db", dbPath, "--id", "CON-900", "--to", "Fixed", "--status", "Fixed",
				"--why", "test: put an item in Fixed"}); rc != exitOK {
				t.Fatalf("move CON-900 exited %d", rc)
			}
			g456Exec(t, dbPath, `UPDATE items SET title='',
				body_md='## CON-900 —'||char(10)||char(10)||'| 2026-01-01 | CON-900 thing | Bug | Fixed | R1 | abc1234 | docs/x.md |'||char(10)
				WHERE atm_id='CON-900'`)
		}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dbPath := newTestDB(t)
			g456Add(t, dbPath, "CON-001", "an ordinary neighbour item", "Task", "Low")
			c.plant(t, dbPath)
			iss, fix := g456Export(t, dbPath, t.TempDir())
			if c.edit != nil {
				c.edit(t, iss)
			}
			before := g456Dump(t, dbPath)
			rc, out := captureStderrRun(t, func() int { return g456Import(dbPath, iss, fix) })
			if rc == exitOK {
				t.Fatalf("md-to-db accepted Markdown that loses or changes a stored item; items now:\n%s", g456Items(t, dbPath))
			}
			if !strings.Contains(out, "nothing written") {
				t.Errorf("refusal does not say nothing was written: %s", out)
			}
			if after := g456Dump(t, dbPath); after != before {
				t.Fatalf("a refused md-to-db changed the database:\n%s", firstDiff(before, after))
			}
			if rc, _ := captureStderrRun(t, func() int { return validateCmd([]string{"--db", dbPath}) }); rc == exitOK {
				t.Fatal("validate passed a stored item whose Markdown does not read back as itself")
			}
		})
	}
}

// TestCON456R2_MDToDBImportsRealEdits is the golden-good control of the guard:
// an edited description, a deleted block and an appended item are imported.
func TestCON456R2_MDToDBImportsRealEdits(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-001", "item whose description is edited", "Task", "Low")
	g456Add(t, dbPath, "CON-002", "item whose block is deleted", "Task", "Low")
	g456Add(t, dbPath, "CON-003", "item left alone", "Task", "Low")
	iss, fix := g456Export(t, dbPath, t.TempDir())
	raw, _ := os.ReadFile(iss)
	edited := strings.Replace(string(raw), g456Desc, "an edited description that is still long enough for the floor", 1)
	if err := os.WriteFile(iss, []byte(edited), 0o644); err != nil {
		t.Fatal(err)
	}
	g456CutBlock(t, iss, "## CON-002 — ")
	g456Append(t, iss, "## CON-950 — item appended by hand\n\n**Status:** Queued\n**Type:** Task\n\nan appended description long enough for the floor here\n")
	if rc, out := captureStderrRun(t, func() int { return g456Import(dbPath, iss, fix) }); rc != exitOK {
		t.Fatalf("md-to-db refused real edits (rc=%d): %s", rc, out)
	}
	got := g456Items(t, dbPath)
	want := "CON-001|Issues|section|\"item whose description is edited\"\nCON-003|Issues|section|\"item left alone\"\nCON-950|Issues|section|\"item appended by hand\"\n"
	if got != want {
		t.Fatalf("items after the edits:\n got %s\nwant %s", got, want)
	}
	if body := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-001'`); !strings.Contains(body, "an edited description") {
		t.Fatalf("the edited description was not imported: %q", body)
	}
}

// TestCON456R2_UpdateTitleRoundTrips: update --title rewrites the heading of a
// legacy-code item too, so the new title survives the round trip; a title the
// parser cannot carry is refused and nothing is written.
func TestCON456R2_UpdateTitleRoundTrips(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "G76", "old legacy title words", "Task", "Low")
	g456Add(t, dbPath, "CON-997", "old canonical title words", "Task", "Low")
	if rc := updateCmd([]string{"--db", dbPath, "--id", "G76", "--title", "new legacy title words"}); rc != exitOK {
		t.Fatalf("update --title of a legacy item exited %d", rc)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-997", "--title", "new canonical title words"}); rc != exitOK {
		t.Fatalf("update --title of a canonical item exited %d", rc)
	}
	iss, fix := g456Export(t, dbPath, t.TempDir())
	rt := filepath.Join(t.TempDir(), "rt.db")
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	want := "CON-997|Issues|section|\"new canonical title words\"\nG76|Issues|section|\"new legacy title words\"\n"
	if got := g456Items(t, rt); got != want {
		t.Fatalf("items after the round trip:\n got %s\nwant %s", got, want)
	}
	for _, c := range []struct{ id, title string }{
		{"G76", "[ABC-9] bracket title"},
		{"CON-997", "a\n## CON-998 — injected"},
	} {
		before := g456Dump(t, dbPath)
		if rc := updateCmd([]string{"--db", dbPath, "--id", c.id, "--title", c.title}); rc == exitOK {
			t.Fatalf("update accepted title %q for %s", c.title, c.id)
		}
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused update changed the database:\n%s", firstDiff(before, after))
		}
	}
}

// TestCON456R2_UpdateSeverityReachesMarkdown: a severity changed by update is
// in the exported Markdown and survives md-to-db.
func TestCON456R2_UpdateSeverityReachesMarkdown(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-997", "item whose severity changes", "Task", "Low")
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-997", "--severity", "High"}); rc != exitOK {
		t.Fatalf("update --severity exited %d", rc)
	}
	iss, fix := g456Export(t, dbPath, t.TempDir())
	if raw, _ := os.ReadFile(iss); !strings.Contains(string(raw), "**Severity:** High") || strings.Contains(string(raw), "**Severity:** Low") {
		t.Fatalf("exported Markdown does not carry the new severity:\n%s", raw)
	}
	rt := filepath.Join(t.TempDir(), "rt.db")
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if got := g456Query(t, rt, `SELECT severity FROM items WHERE atm_id='CON-997'`); got != "High" {
		t.Fatalf("severity after the round trip = %q, want High", got)
	}
}

// TestCON456R2_ColumnBodyDesyncHealed: a severity column that disagrees with
// the stored body (as three real items held before round 2) is exported from
// the column, survives md-to-db, and repair-bodies aligns the stored body.
func TestCON456R2_ColumnBodyDesyncHealed(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-997", "item with a stale severity line", "Task", "Low")
	g456Exec(t, dbPath, `UPDATE items SET severity='High' WHERE atm_id='CON-997'`)
	iss, fix := g456Export(t, dbPath, t.TempDir())
	if raw, _ := os.ReadFile(iss); !strings.Contains(string(raw), "**Severity:** High") {
		t.Fatalf("db-to-md did not render the severity from the column:\n%s", raw)
	}
	rt := filepath.Join(t.TempDir(), "rt.db")
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if got := g456Query(t, rt, `SELECT severity FROM items WHERE atm_id='CON-997'`); got != "High" {
		t.Fatalf("severity after the round trip = %q, want High", got)
	}
	if rc := repairBodiesCmd([]string{"--db", dbPath}); rc != exitOK {
		t.Fatalf("repair-bodies exited %d", rc)
	}
	body := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-997'`)
	if !strings.Contains(body, "**Severity:** High") || strings.Contains(body, "**Severity:** Low") {
		t.Fatalf("repair-bodies did not align the stored body: %q", body)
	}
}

// TestCON456R2_BlockDetailsCannotInjectAnItem: block refuses details that would
// put a heading line into the item's Markdown; ordinary details are accepted.
func TestCON456R2_BlockDetailsCannotInjectAnItem(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-998", "item that is blocked", "Task", "Low")
	before := g456Dump(t, dbPath)
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-998", "--details", "blocked action\n## CON-999 — injected",
		"--why", "w", "--unblock", "u", "--who", "x"}); rc == exitOK {
		t.Fatal("block accepted details holding a heading line")
	}
	if after := g456Dump(t, dbPath); after != before {
		t.Fatalf("a refused block changed the database:\n%s", firstDiff(before, after))
	}
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-998", "--details", "waiting for the operator's key",
		"--why", "every self-resolution path tried", "--unblock", "the key file exists", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block with ordinary details exited %d", rc)
	}
	iss, fix := g456Export(t, dbPath, t.TempDir())
	rt := filepath.Join(t.TempDir(), "rt.db")
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if got := g456Items(t, rt); got != "CON-998|Issues|section|\"item that is blocked\"\n" {
		t.Fatalf("items after the round trip: %s", got)
	}
}

// TestCON456R2_MoveRefusesAnItemFixedCannotRead: move judges the item as it
// will be written to the destination tracker; a stored item whose heading
// reads as another id is not moved. Control: an ordinary item is moved.
func TestCON456R2_MoveRefusesAnItemFixedCannotRead(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-001", "an ordinary item that moves", "Task", "Low")
	g456Add(t, dbPath, "GS-72", "first probe", "Task", "Low")
	g456Exec(t, dbPath, `UPDATE items SET title='[ABC-9] first probe',
		body_md=replace(body_md, '## GS-72. first probe', '## GS-72. [ABC-9] first probe') WHERE atm_id='GS-72'`)
	before := g456Dump(t, dbPath)
	if rc := moveCmd([]string{"--db", dbPath, "--id", "GS-72", "--to", "Fixed", "--status", "Fixed",
		"--why", "test: move an item whose heading reads as another id"}); rc == exitOK {
		t.Fatal("move accepted an item whose Markdown reads back as ABC-9")
	}
	if after := g456Dump(t, dbPath); after != before {
		t.Fatalf("a refused move changed the database:\n%s", firstDiff(before, after))
	}
	if rc := moveCmd([]string{"--db", dbPath, "--id", "CON-001", "--to", "Fixed", "--status", "Fixed",
		"--why", "test: move an ordinary item"}); rc != exitOK {
		t.Fatalf("control: move of an ordinary item exited %d", rc)
	}
}

// g456PlantHeadingInDescription stores (by SQL) a description line that reads
// as another item's heading, as a database written before round 2 could hold.
func g456PlantHeadingInDescription(t *testing.T, dbPath, id string) {
	t.Helper()
	body := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id=?`, id)
	if !strings.Contains(body, "a sufficiently long description") {
		t.Fatalf("fixture: %s has no description to plant into: %q", id, body)
	}
	g456Exec(t, dbPath, `UPDATE items SET body_md=replace(body_md, 'a sufficiently long description',
		'line one'||char(10)||'## CON-811 — injected'||char(10)||'a sufficiently long description') WHERE atm_id=?`, id)
}

// TestCON456R2_BodyWritersRefuseAnItemTheParserSplits: close, obsolete-details,
// states import and repair-bodies judge the body they write; on an item whose description
// holds a heading line each refuses and writes nothing. Controls: the same
// commands on ordinary items succeed (close, obsolete-details and states
// import here; the repair-bodies control is TestCON456R2_ColumnBodyDesyncHealed).
func TestCON456R2_BodyWritersRefuseAnItemTheParserSplits(t *testing.T) {
	// refusedByGate runs one command and requires that it exits non-zero
	// because of the write gate (its stderr names the round trip), not for
	// some other reason such as a wrong closure status or a missing file.
	refusedByGate := func(t *testing.T, what string, fn func() int) {
		t.Helper()
		rc, stderr := captureStderrRun(t, fn)
		if rc == exitOK {
			t.Fatalf("%s accepted an item whose Markdown reads back as two items", what)
		}
		if !strings.Contains(stderr, "would not read back as this item") || !strings.Contains(stderr, "CON-811") {
			t.Fatalf("%s exited %d but not because of the round trip; stderr:\n%s", what, rc, stderr)
		}
	}
	t.Run("close", func(t *testing.T) {
		dbPath := newTestDB(t)
		g456Add(t, dbPath, "CON-020", "item that is closed", "Task", "Low")
		g456Add(t, dbPath, "CON-021", "ordinary item that is closed", "Task", "Low")
		ev := filepath.Join(t.TempDir(), "close.md")
		if err := os.WriteFile(ev, []byte("captured closure evidence\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		// close rebuilds the body from the description COLUMN (renderItemBody),
		// so a line planted only in body_md is discarded and the close is
		// correct; the plant that reaches close's gate is in the column.
		g456Exec(t, dbPath, `UPDATE items SET description='line one'||char(10)||'## CON-811 — injected'||char(10)||description WHERE atm_id='CON-020'`)
		before := g456Dump(t, dbPath)
		refusedByGate(t, "close", func() int {
			return closeCmd([]string{"--db", dbPath, "--status", "completed", "--evidence", ev, "CON-020"})
		})
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused close changed the database:\n%s", firstDiff(before, after))
		}
		if rc := closeCmd([]string{"--db", dbPath, "--status", "completed", "--evidence", ev, "CON-021"}); rc != exitOK {
			t.Fatalf("control: close of an ordinary item exited %d", rc)
		}
	})
	t.Run("obsolete-details", func(t *testing.T) {
		dbPath := filepath.Join(t.TempDir(), "wi.db")
		addThenObsolete(t, dbPath, "CON-030")
		// Each addThenObsolete call moves the working directory to a new
		// evidence root; relative evidence resolves against the last one.
		evRoot := addThenObsolete(t, dbPath, "CON-031")
		g456PlantHeadingInDescription(t, dbPath, "CON-030")
		args := func(id string) []string {
			return []string{id, "--db", dbPath, "--since", "2026-06-09", "--reason", "not-reproducible",
				"--superseding", "none", "--evidence", materialiseEvidence(t, evRoot, "docs/qa/"+id+"/evidence.md")}
		}
		a := args("CON-030")
		before := g456Dump(t, dbPath)
		refusedByGate(t, "obsolete-details", func() int { return obsoleteDetailsCmd(a) })
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused obsolete-details changed the database:\n%s", firstDiff(before, after))
		}
		if rc := obsoleteDetailsCmd(args("CON-031")); rc != exitOK {
			t.Fatalf("control: obsolete-details of an ordinary item exited %d", rc)
		}
	})
	t.Run("states-import", func(t *testing.T) {
		dbPath := newTestDB(t)
		g456Add(t, dbPath, "CON-050", "item whose records are imported", "Bug", "Low")
		g456Add(t, dbPath, "CON-051", "ordinary item whose records are imported", "Bug", "Low")
		g456PlantHeadingInDescription(t, dbPath, "CON-050")
		row := func(id string) string {
			return tsvRow(map[string]string{"atm_id": id, "location": "Issues", "reproduction_state": "UNREPRODUCED",
				"investigation_state": "in-progress"})
		}
		before := g456Dump(t, dbPath)
		tsv := writeTSV(t, row("CON-050"))
		refusedByGate(t, "states import", func() int {
			return statesCmd([]string{"import", "--db", dbPath, "--tsv", tsv, "--by", "importer", "--at", statesAt})
		})
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused states import changed the database:\n%s", firstDiff(before, after))
		}
		if rc := statesCmd([]string{"import", "--db", dbPath, "--tsv", writeTSV(t, row("CON-051")), "--by", "importer", "--at", statesAt}); rc != exitOK {
			t.Fatalf("control: states import of an ordinary item exited %d", rc)
		}
	})
	t.Run("repair-bodies", func(t *testing.T) {
		dbPath := newTestDB(t)
		g456Add(t, dbPath, "CON-040", "item with a stale severity line", "Task", "Low")
		g456PlantHeadingInDescription(t, dbPath, "CON-040")
		g456Exec(t, dbPath, `UPDATE items SET severity='High' WHERE atm_id='CON-040'`)
		before := g456Dump(t, dbPath)
		refusedByGate(t, "repair-bodies", func() int { return repairBodiesCmd([]string{"--db", dbPath}) })
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused repair-bodies changed the database:\n%s", firstDiff(before, after))
		}
	})
}

// TestCON456R2_MDToDBWithoutDocumentsCreatesNoDatabase: a usage error is
// reported before the database is opened, so no file appears at a fresh path.
func TestCON456R2_MDToDBWithoutDocumentsCreatesNoDatabase(t *testing.T) {
	fresh := newTestDB(t)
	if rc := syncMDToDB([]string{"--db", fresh}); rc == exitOK {
		t.Fatal("md-to-db with neither --issues nor --fixed exited 0")
	}
	if _, err := os.Stat(fresh); !os.IsNotExist(err) {
		t.Fatalf("md-to-db with a usage error created the database file (err=%v)", err)
	}
}

// TestCON456R2_SeverityTheParserCannotCarryIsRefused: a severity with a line
// break renders as a Severity line plus a loose line, which md-to-db reads back
// as a shorter severity. Only the carried-severity comparison of the round trip
// sees it (the body bytes, title, type and status all read back unchanged), so
// add and update must refuse it, name the severity, and write nothing. Control:
// an ordinary severity is accepted by both.
func TestCON456R2_SeverityTheParserCannotCarryIsRefused(t *testing.T) {
	bad := "High\nmore text"
	fresh := newTestDB(t)
	rc, out := captureStderrRun(t, func() int {
		return addCmd([]string{"--db", fresh, "--id", "CON-998", "--title", "item added with a broken severity",
			"--description", g456Desc, "Task", bad})
	})
	if rc == exitOK {
		t.Fatalf("add accepted the severity %q, which reads back as %q", bad, "High")
	}
	if !strings.Contains(out, "severity reads back as") {
		t.Errorf("add refusal does not name the severity: %s", out)
	}
	if _, err := os.Stat(fresh); !os.IsNotExist(err) {
		t.Fatalf("a refused add created the database file (err=%v)", err)
	}

	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-997", "item whose severity gets a line break", "Task", "Low")
	before := g456Dump(t, dbPath)
	rc, out = captureStderrRun(t, func() int {
		return updateCmd([]string{"--db", dbPath, "--id", "CON-997", "--severity", bad})
	})
	if rc == exitOK {
		t.Fatalf("update accepted the severity %q, which reads back as %q", bad, "High")
	}
	if !strings.Contains(out, "severity reads back as") {
		t.Errorf("update refusal does not name the severity: %s", out)
	}
	if after := g456Dump(t, dbPath); after != before {
		t.Fatalf("a refused update changed the database:\n%s", firstDiff(before, after))
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-997", "--severity", "High"}); rc != exitOK {
		t.Fatalf("control: update --severity High exited %d", rc)
	}
}

// TestCON456R2_StateLineInDescriptionIsRefused: a description line that reads
// as a reproduction record (malformed, so the renderer leaves it alone) would
// be read by the next md-to-db as the item's reproduction state: on the
// round-1 head, add accepted it and md-to-db turned the state UNSET into
// reproduced-live with no evidence (a forged state record). Only the state
// record comparison of the round trip sees it, so add and update --description
// must refuse it and write nothing. Control: the same words inline are accepted.
func TestCON456R2_StateLineInDescriptionIsRefused(t *testing.T) {
	forged := "line one of a long enough description\n**Reproduction:** reproduced-live"
	const cause = "the reproduction/investigation records read back differently"
	fresh := newTestDB(t)
	rc, out := captureStderrRun(t, func() int {
		return addCmd([]string{"--db", fresh, "--id", "CON-996", "--title", "item with a state line in its description",
			"--description", forged, "Bug", "Low"})
	})
	if rc == exitOK {
		t.Fatal("add accepted a description line that md-to-db reads as a reproduction record")
	}
	if !strings.Contains(out, cause) {
		t.Errorf("add refusal does not name the state records: %s", out)
	}
	if _, err := os.Stat(fresh); !os.IsNotExist(err) {
		t.Fatalf("a refused add created the database file (err=%v)", err)
	}

	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-995", "item whose description gets a state line", "Bug", "Low")
	before := g456Dump(t, dbPath)
	rc, out = captureStderrRun(t, func() int {
		return updateCmd([]string{"--db", dbPath, "--id", "CON-995", "--description", forged})
	})
	if rc == exitOK {
		t.Fatal("update accepted a description line that md-to-db reads as a reproduction record")
	}
	if !strings.Contains(out, cause) {
		t.Errorf("update refusal does not name the state records: %s", out)
	}
	if after := g456Dump(t, dbPath); after != before {
		t.Fatalf("a refused update changed the database:\n%s", firstDiff(before, after))
	}
	inline := "line one of a long enough description mentioning **Reproduction:** inline only"
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-995", "--description", inline}); rc != exitOK {
		t.Fatalf("control: an inline mention was refused (exit %d)", rc)
	}
}

// TestCON456R2_DescriptionLineTheRendererRewritesIsRefused: a well-formed
// investigation record line inside a description is replaced by the renderer
// with the record of the state columns, so the operator's line is gone from
// the Markdown; every field still reads back unchanged. On the round-1 head the
// line was dropped from the stored body without a word. Only the check that
// each embedded operator text survives sees it, so add and update
// --description must refuse it and write nothing.
func TestCON456R2_DescriptionLineTheRendererRewritesIsRefused(t *testing.T) {
	desc := "line one of a long enough description\n**Investigation:** root-cause-found-with-evidence — root-cause `x`"
	const cause = "would not survive in the Markdown"
	fresh := newTestDB(t)
	rc, out := captureStderrRun(t, func() int {
		return addCmd([]string{"--db", fresh, "--id", "CON-994", "--title", "item with an investigation line in its description",
			"--description", desc, "Bug", "Low"})
	})
	if rc == exitOK {
		t.Fatal("add accepted a description line that the renderer replaces")
	}
	if !strings.Contains(out, cause) {
		t.Errorf("add refusal does not name the lost text: %s", out)
	}
	if _, err := os.Stat(fresh); !os.IsNotExist(err) {
		t.Fatalf("a refused add created the database file (err=%v)", err)
	}

	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-993", "item whose description gets a record line", "Bug", "Low")
	before := g456Dump(t, dbPath)
	rc, out = captureStderrRun(t, func() int {
		return updateCmd([]string{"--db", dbPath, "--id", "CON-993", "--description", desc})
	})
	if rc == exitOK {
		t.Fatal("update accepted a description line that the renderer replaces")
	}
	if !strings.Contains(out, cause) {
		t.Errorf("update refusal does not name the lost text: %s", out)
	}
	if after := g456Dump(t, dbPath); after != before {
		t.Fatalf("a refused update changed the database:\n%s", firstDiff(before, after))
	}
}

// TestCON456R2_UpdateRefusalNamesTheTitle: a title that does not round-trip is
// refused by update with the title named as the cause (review F9), not only as
// a generic "would not read back" message of the whole item. Control: the
// item-level gate alone (without the title check) still refuses the same
// title, so this test pins the cause naming, not the refusal itself.
func TestCON456R2_UpdateRefusalNamesTheTitle(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "G76", "old legacy title words", "Task", "Low")
	for _, c := range []struct{ id, title string }{
		{"G76", "[ABC-9] bracket title"},
		{"G76", "legacy title ending in a status suffix — `Fixed (→ Fixed.md)`"},
	} {
		before := g456Dump(t, dbPath)
		rc, out := captureStderrRun(t, func() int {
			return updateCmd([]string{"--db", dbPath, "--id", c.id, "--title", c.title})
		})
		if rc == exitOK {
			t.Fatalf("update accepted title %q for %s", c.title, c.id)
		}
		if want := fmt.Sprintf("title %q does not round-trip under id %q", c.title, c.id); !strings.Contains(out, want) {
			t.Errorf("update refusal for %s does not name the title as the cause (want %q):\n%s", c.id, want, out)
		}
		if after := g456Dump(t, dbPath); after != before {
			t.Fatalf("a refused update changed the database:\n%s", firstDiff(before, after))
		}
	}
}
