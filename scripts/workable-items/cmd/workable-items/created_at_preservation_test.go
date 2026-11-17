// created_at_preservation_test.go — CON-339: no engine command may rewrite
// items.created_at.
//
// Before the fix two paths re-created an items row without carrying created_at,
// so the column DEFAULT (datetime('now')) stamped the write time over the item's
// creation time: `close` (DELETE from Issues, INSERT into Fixed) and
// `sync md-to-db` (replaceDocument deletes a whole document and re-inserts it).
//
// The tests here are class-wide:
//   - TestCON339_CreatedAtPreservedByEveryMutatingCommand runs every mutating
//     command the CLI dispatches on a fixture whose items carry distinct, known
//     created_at values and asserts every pre-existing row keeps its own value,
//     and that the command writes the item_history row it is designed to write
//     (or, for the commands that by design write none, that it writes none).
//   - TestCON339_CommandEnumerationGuard parses main.go's dispatch switch, so a
//     new subcommand fails here until it is classified (covered by a case above,
//     read-only, delegating, or restoring by design).
//   - TestCON339_ItemsWriteSitesCarryCreatedAt scans the engine source: every
//     statement that re-creates an items row must name created_at, so a future
//     DELETE+INSERT writer cannot reintroduce the defect without failing here.
//
// Evidence class: gate-logic / unit (section 11.4.289) — the real command
// functions on a real SQLite database in t.TempDir(); no mocks.
package main

import (
	"database/sql"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// con339Sentinels are the created_at values the fixture stamps on its items.
// They are distinct per item, so a writer that copies the WRONG item's value
// fails as surely as one that stamps the current time.
var con339Sentinels = map[string]string{
	"WIT-001": "2020-01-01 01:01:01",
	"WIT-002": "2020-02-02 02:02:02",
	"WIT-003": "2020-03-03 03:03:03",
	"WIT-004": "2020-04-04 04:04:04",
}

var con339StoredTimeRE = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$`)

// con339Fixture builds a database with two open Bugs, one open Task and one
// Obsolete (closed) Bug, then stamps the sentinel created_at values. The stamp
// is a TEST fixture write on a t.TempDir() database (never a tracker database).
func con339Fixture(t *testing.T) (dbPath, evRoot string) {
	t.Helper()
	dbPath = newTestDB(t)
	evRoot = newEvidenceRoot(t)
	for _, a := range [][]string{
		{"--id", "WIT-001", "--title", "con339 open bug one", "Bug", "High"},
		{"--id", "WIT-002", "--title", "con339 open task two", "Task", "Medium"},
		{"--id", "WIT-003", "--title", "con339 bug three, closed in the fixture", "Bug", "Low"},
		{"--id", "WIT-004", "--title", "con339 open task four", "Task", "Low"},
	} {
		args := append([]string{"--db", dbPath, "--description",
			"a sufficiently long description that clears the section 11.4.91 floor for CON-339"}, a...)
		if rc := addCmd(args); rc != exitOK {
			t.Fatalf("fixture add %v exited %d", a, rc)
		}
	}
	if rc := closeCmd([]string{"WIT-003", "--db", dbPath, "--status", "obsolete",
		"--evidence", materialiseEvidence(t, evRoot, "qa/con339/WIT-003-close.md")}); rc != exitOK {
		t.Fatalf("fixture close WIT-003 exited %d", rc)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("fixture openDB: %v", err)
	}
	defer db.Close()
	for id, v := range con339Sentinels {
		res, err := db.Exec(`UPDATE items SET created_at=? WHERE atm_id=?`, v, id)
		if err != nil {
			t.Fatalf("fixture stamp %s: %v", id, err)
		}
		if n, _ := res.RowsAffected(); n != 1 {
			t.Fatalf("fixture stamp %s touched %d rows, want 1", id, n)
		}
	}
	return dbPath, evRoot
}

// con339Rows returns created_at keyed by "atm_id|location|representation".
func con339Rows(t *testing.T, dbPath string) map[string]string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	rows, err := db.Query(`SELECT atm_id, current_location, representation, created_at FROM items`)
	if err != nil {
		t.Fatalf("query items: %v", err)
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var id, loc, rep, ca string
		if err := rows.Scan(&id, &loc, &rep, &ca); err != nil {
			t.Fatalf("scan: %v", err)
		}
		out[id+"|"+loc+"|"+rep] = ca
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("rows: %v", err)
	}
	return out
}

// con339History returns item_history counts keyed by "atm_id|event_type", plus
// the total row count.
func con339History(t *testing.T, dbPath string) (map[string]int, int) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	rows, err := db.Query(`SELECT atm_id, event_type FROM item_history`)
	if err != nil {
		t.Fatalf("query history: %v", err)
	}
	defer rows.Close()
	out, total := map[string]int{}, 0
	for rows.Next() {
		var id, ev string
		if err := rows.Scan(&id, &ev); err != nil {
			t.Fatalf("scan: %v", err)
		}
		out[id+"|"+ev]++
		total++
	}
	return out, total
}

func con339ClosureHistoryID(t *testing.T, dbPath, id string) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var hid int64
	if err := db.QueryRow(`SELECT MAX(id) FROM item_history WHERE atm_id=? AND event_type IN ('Fixed','Implemented','Completed','Obsolete')`, id).Scan(&hid); err != nil {
		t.Fatalf("closure history id of %s: %v", id, err)
	}
	return strconv.FormatInt(hid, 10)
}

type con339HistWant struct {
	key   string // "atm_id|event_type"
	delta int
}

type con339Case struct {
	name string
	run  func(t *testing.T, dbPath, evRoot string) int
	// hist lists the history rows the command writes by design. When empty,
	// noHistory states why the command writes none, and the test asserts the
	// total item_history count is unchanged.
	hist      []con339HistWant
	noHistory string
	// newIDs are ids the command creates; their created_at must be a fresh
	// stored timestamp, never one of the sentinels.
	newIDs []string
}

func con339Cases() []con339Case {
	ev := func(t *testing.T, root, name string) string {
		return materialiseEvidence(t, root, "qa/con339/"+name)
	}
	return []con339Case{
		{name: "close-obsolete", run: func(t *testing.T, db, root string) int {
			return closeCmd([]string{"WIT-001", "--db", db, "--status", "obsolete", "--evidence", ev(t, root, "c1.md")})
		}, hist: []con339HistWant{{"WIT-001|Obsolete", 1}}},
		{name: "close-fixed", run: func(t *testing.T, db, root string) int {
			return closeCmd([]string{"WIT-001", "--db", db, "--status", "fixed", "--evidence", ev(t, root, "c2.md")})
		}, hist: []con339HistWant{{"WIT-001|Fixed", 1}}},
		{name: "close-completed", run: func(t *testing.T, db, root string) int {
			return closeCmd([]string{"WIT-002", "--db", db, "--status", "completed", "--evidence", ev(t, root, "c3.md")})
		}, hist: []con339HistWant{{"WIT-002|Completed", 1}}},
		{name: "update-title", run: func(t *testing.T, db, root string) int {
			return updateCmd([]string{"--db", db, "--id", "WIT-002", "--title", "con339 open task two, retitled"})
		}, hist: []con339HistWant{{"WIT-002|Updated", 1}}},
		{name: "update-fixed", run: func(t *testing.T, db, root string) int {
			return updateCmd([]string{"--db", db, "--id", "WIT-003", "--location", "Fixed", "--title", "con339 bug three, retitled in Fixed"})
		}, hist: []con339HistWant{{"WIT-003|Updated", 1}}},
		{name: "reopen-fixed", run: func(t *testing.T, db, root string) int {
			return reopenCmd([]string{"--db", db, "--id", "WIT-003", "--why", "test-failed", "--who", "AI",
				"--when", "2026-11-13", "--incident", ev(t, root, "reopen.log")})
		}, hist: []con339HistWant{{"WIT-003|Reopened", 1}}},
		{name: "move-to-issues", run: func(t *testing.T, db, root string) int {
			return moveCmd([]string{"--db", db, "--id", "WIT-003", "--to", "Issues", "--status", "Ready for testing",
				"--why", "con339 property case: Fixed to Issues", "--evidence", ev(t, root, "move1.md")})
		}, hist: []con339HistWant{{"WIT-003|Updated", 1}}},
		{name: "move-to-fixed", run: func(t *testing.T, db, root string) int {
			return moveCmd([]string{"--db", db, "--id", "WIT-004", "--to", "Fixed", "--status", "Obsolete",
				"--why", "con339 property case: Issues to Fixed", "--evidence", ev(t, root, "move2.md")})
		}, hist: []con339HistWant{{"WIT-004|Updated", 1}}},
		{name: "block", run: func(t *testing.T, db, root string) int {
			return blockCmd([]string{"--db", db, "--id", "WIT-002", "--details", "needs an operator decision on the fixture",
				"--why", "no alternative in a unit test", "--unblock", "operator answers", "--who", "operator"})
		}, hist: []con339HistWant{{"WIT-002|Updated", 1}}},
		{name: "obsolete-details", run: func(t *testing.T, db, root string) int {
			return obsoleteDetailsCmd([]string{"WIT-003", "--db", db, "--since", "2026-11-13", "--reason", "not-reproducible",
				"--superseding", "none", "--evidence", ev(t, root, "od.md")})
		}, hist: []con339HistWant{{"WIT-003|Obsolete", 1}}},
		{name: "states-import", run: func(t *testing.T, db, root string) int {
			tsv := writeTSV(t, tsvRow(map[string]string{"atm_id": "WIT-001", "location": "Issues",
				"reproduction_state": "UNREPRODUCED", "reproduction_red_cmd": "bash red.sh", "investigation_state": "in-progress"}))
			return statesCmd([]string{"import", "--db", db, "--tsv", tsv, "--by", "importer", "--at", statesAt})
		}, hist: []con339HistWant{{"WIT-001|Updated", 1}}},
		{name: "states-freeze", run: func(t *testing.T, db, root string) int {
			return statesCmd([]string{"freeze", "--db", db, "--by", "conductor", "--at", statesAt})
		}, noHistory: "freeze writes the meta table and closure-gate exemptions, never an item row"},
		{name: "repair-bodies", run: func(t *testing.T, db, root string) int {
			return repairBodiesCmd([]string{"--db", db})
		}, noHistory: "repair-bodies rewrites body_md only and records no history row (existing behaviour)"},
		{name: "version-tags", run: func(t *testing.T, db, root string) int {
			return versionTagsCmd([]string{"--db", db, "--repo", t.TempDir()})
		}, noHistory: "version-tags derives a column from git and records no history row (existing behaviour)"},
		{name: "group-set-item", run: func(t *testing.T, db, root string) int {
			if rc := groupAddCmd([]string{"grp-con339", "main", "3", "--db", db, "--title", "con339 group for the property case"}); rc != exitOK {
				return rc
			}
			return groupSetCmd([]string{"--db", db, "--item", "WIT-002", "--group", "grp-con339"})
		}, noHistory: "group set --item writes logic_group/destination and records no history row (existing behaviour)"},
		{name: "correct-history-evidence", run: func(t *testing.T, db, root string) int {
			return correctHistoryEvidenceCmd([]string{"--db", db, "--atm-id", "WIT-003",
				"--history-id", con339ClosureHistoryID(t, db, "WIT-003"),
				"--evidence-path", ev(t, root, "corrected.md"), "--reason", "con339 property case"})
		}, hist: []con339HistWant{{"WIT-003|Updated", 1}}},
		{name: "diary-add", run: func(t *testing.T, db, root string) int {
			return diaryGroupAddCmd([]string{"--id", "WIT-001", "--db", db, "--tested-by", "AI-agent",
				"--result", "SKIP", "--detail", "con339 property case", "--observations", "con339: diary rows never touch items"})
		}, noHistory: "diary add writes test_diary only"},
		{name: "add-new-item", run: func(t *testing.T, db, root string) int {
			return addCmd([]string{"--db", db, "--id", "WIT-005", "--title", "con339 new item",
				"--description", "a sufficiently long description that clears the section 11.4.91 floor for CON-339", "Task", "Low"})
		}, hist: []con339HistWant{{"WIT-005|Opened", 1}}, newIDs: []string{"WIT-005"}},
		{name: "sync-roundtrip", run: func(t *testing.T, db, root string) int {
			dir := t.TempDir()
			iss, fix := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
			if rc := syncDBToMD([]string{"--db", db, "--out-issues", iss, "--out-fixed", fix}); rc != exitOK {
				return rc
			}
			return syncMDToDB([]string{"--db", db, "--issues", iss, "--fixed", fix})
		}, noHistory: "md-to-db rebuilds rows from Markdown and records no history row (existing behaviour)"},
	}
}

func TestCON339_CreatedAtPreservedByEveryMutatingCommand(t *testing.T) {
	for _, tc := range con339Cases() {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			dbPath, evRoot := con339Fixture(t)
			before := con339Rows(t, dbPath)
			// Control needle: the fixture stamp is visible to the instrument.
			if got := before["WIT-001|Issues|section"]; got != con339Sentinels["WIT-001"] {
				t.Fatalf("BLIND: fixture sentinel not visible: WIT-001 created_at %q", got)
			}
			hBefore, totBefore := con339History(t, dbPath)
			if rc := tc.run(t, dbPath, evRoot); rc != exitOK {
				t.Fatalf("%s exited %d", tc.name, rc)
			}
			after := con339Rows(t, dbPath)
			seen := map[string]bool{}
			for key, ca := range after {
				id := strings.SplitN(key, "|", 2)[0]
				want, pre := con339Sentinels[id]
				if !pre {
					continue
				}
				seen[id] = true
				if ca != want {
					t.Errorf("%s: %s created_at %q, want %q (CON-339: the command rewrote created_at)", tc.name, key, ca, want)
				}
			}
			for id := range con339Sentinels {
				if !seen[id] {
					t.Errorf("%s: %s has no row after the command", tc.name, id)
				}
			}
			for _, id := range tc.newIDs {
				found := false
				for key, ca := range after {
					if strings.HasPrefix(key, id+"|") {
						found = true
						if !con339StoredTimeRE.MatchString(ca) {
							t.Errorf("%s: new item %s created_at %q is not a stored timestamp", tc.name, key, ca)
						}
						for _, s := range con339Sentinels {
							if ca == s {
								t.Errorf("%s: new item %s took a sentinel created_at %q", tc.name, key, ca)
							}
						}
					}
				}
				if !found {
					t.Errorf("%s: new item %s not found", tc.name, id)
				}
			}
			hAfter, totAfter := con339History(t, dbPath)
			if len(tc.hist) == 0 {
				if tc.noHistory == "" {
					t.Fatalf("%s: case declares neither a history row nor why it writes none", tc.name)
				}
				if totAfter != totBefore {
					t.Errorf("%s: item_history rows %d -> %d, want unchanged (%s)", tc.name, totBefore, totAfter, tc.noHistory)
				}
			}
			for _, hw := range tc.hist {
				if d := hAfter[hw.key] - hBefore[hw.key]; d != hw.delta {
					t.Errorf("%s: item_history %s delta %d, want %d", tc.name, hw.key, d, hw.delta)
				}
			}
		})
	}
}

// TestCON339_MDToDBMoveAcrossDocumentsKeepsCreatedAt: a Markdown-side closure
// moves an item from Issues.md to Fixed.md. md-to-db replaces Issues first (the
// item's Issues row is gone after that transaction) and Fixed second, so the
// value must come from a snapshot taken before both — a per-transaction
// snapshot inside replaceDocument would miss it.
func TestCON339_MDToDBMoveAcrossDocumentsKeepsCreatedAt(t *testing.T) {
	dbPath, evRoot := con339Fixture(t)
	other := filepath.Join(t.TempDir(), "other.db")
	con339CopyDB(t, dbPath, other)
	if rc := closeCmd([]string{"WIT-001", "--db", other, "--status", "obsolete",
		"--evidence", materialiseEvidence(t, evRoot, "qa/con339/md-move.md")}); rc != exitOK {
		t.Fatalf("close on the copy exited %d", rc)
	}
	if rc := addCmd([]string{"--db", other, "--id", "WIT-006", "--title", "con339 item new in Markdown",
		"--description", "a sufficiently long description that clears the section 11.4.91 floor for CON-339", "Task", "Low"}); rc != exitOK {
		t.Fatalf("add on the copy exited %d", rc)
	}
	dir := t.TempDir()
	iss, fix := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
	if rc := syncDBToMD([]string{"--db", other, "--out-issues", iss, "--out-fixed", fix}); rc != exitOK {
		t.Fatalf("db-to-md exited %d", rc)
	}
	if rc := syncMDToDB([]string{"--db", dbPath, "--issues", iss, "--fixed", fix}); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	after := con339Rows(t, dbPath)
	if _, ok := after["WIT-001|Issues|section"]; ok {
		t.Fatalf("control: WIT-001 still in Issues, the Markdown move did not apply")
	}
	if got := after["WIT-001|Fixed|section"]; got != con339Sentinels["WIT-001"] {
		t.Errorf("WIT-001 moved Issues->Fixed by md-to-db: created_at %q, want %q", got, con339Sentinels["WIT-001"])
	}
	for _, id := range []string{"WIT-002", "WIT-004"} {
		if got := after[id+"|Issues|section"]; got != con339Sentinels[id] {
			t.Errorf("%s: created_at %q, want %q", id, got, con339Sentinels[id])
		}
	}
	if got := after["WIT-003|Fixed|section"]; got != con339Sentinels["WIT-003"] {
		t.Errorf("WIT-003: created_at %q, want %q", got, con339Sentinels["WIT-003"])
	}
	got := after["WIT-006|Issues|section"]
	if !con339StoredTimeRE.MatchString(got) {
		t.Errorf("WIT-006 (new in Markdown) created_at %q is not a stored timestamp", got)
	}
	for _, s := range con339Sentinels {
		if got == s {
			t.Errorf("WIT-006 (new in Markdown) took a sentinel created_at %q", got)
		}
	}
}

func con339CopyDB(t *testing.T, src, dst string) {
	t.Helper()
	db, err := sql.Open("sqlite3", src)
	if err != nil {
		t.Fatalf("open %s: %v", src, err)
	}
	if _, err := db.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		t.Fatalf("checkpoint: %v", err)
	}
	db.Close()
	b, err := os.ReadFile(src)
	if err != nil {
		t.Fatalf("read %s: %v", src, err)
	}
	if err := os.WriteFile(dst, b, 0o644); err != nil {
		t.Fatalf("write %s: %v", dst, err)
	}
}

// con339CommandClass classifies every top-level subcommand main.go dispatches.
// kind: "covered" (a case above runs it), "read-only" (writes no table),
// "no-items-write" (writes tables other than items), "delegates" (performs its
// writes through other covered commands), "restores" (changes created_at by
// design: restore-created-at, tested in restore_created_at_test.go).
var con339CommandClass = map[string]struct {
	kind  string
	cases []string
	why   string
}{
	"sync":                     {"covered", []string{"sync-roundtrip"}, "md-to-db re-creates rows; db-to-md reads the DB"},
	"diff":                     {"read-only", nil, "compares DB and Markdown"},
	"validate":                 {"read-only", nil, "closed-set checks"},
	"repair-bodies":            {"covered", []string{"repair-bodies"}, "UPDATE body_md"},
	"version-tags":             {"covered", []string{"version-tags"}, "UPDATE version_tags"},
	"add":                      {"covered", []string{"add-new-item"}, "INSERT of a new item"},
	"update":                   {"covered", []string{"update-title", "update-fixed"}, "UPDATE in place"},
	"reopen":                   {"covered", []string{"reopen-fixed"}, "UPDATE in place"},
	"move":                     {"covered", []string{"move-to-issues", "move-to-fixed"}, "UPDATE in place"},
	"block":                    {"covered", []string{"block"}, "UPDATE in place"},
	"close":                    {"covered", []string{"close-obsolete", "close-fixed", "close-completed"}, "DELETE + INSERT"},
	"closure-check":            {"read-only", nil, "dry-run seam check; never modifies the tracker"},
	"obsolete-details":         {"covered", []string{"obsolete-details"}, "obsolete_details + UPDATE body_md"},
	"intake-match":             {"delegates", nil, "--apply calls reopenCmd / addCmd, covered by reopen-fixed / add-new-item"},
	"report":                   {"read-only", nil, "grouped tally"},
	"diary":                    {"covered", []string{"diary-add"}, "test_diary rows"},
	"export":                   {"read-only", nil, "reads the DB, writes Markdown and rendered files"},
	"group":                    {"covered", []string{"group-set-item"}, "logic_groups; set --item UPDATEs an item"},
	"validate-groups":          {"read-only", nil, "invariant checks"},
	"assign":                   {"no-items-write", nil, "claim registry and logic_groups only (no items write in assign.go)"},
	"classify":                 {"read-only", nil, "writes a review file, never the DB"},
	"correct-history-evidence": {"covered", []string{"correct-history-evidence"}, "item_history only"},
	"states":                   {"covered", []string{"states-import", "states-freeze"}, "UPDATE state columns; meta"},
	"restore-created-at":       {"restores", nil, "the one path that changes created_at; restore_created_at_test.go"},
	"-h":                       {"read-only", nil, "usage"},
	"--help":                   {"read-only", nil, "usage"},
	"help":                     {"read-only", nil, "usage"},
}

// TestCON339_CommandEnumerationGuard: the dispatch switch in main() and the
// classification table above must name exactly the same subcommands.
func TestCON339_CommandEnumerationGuard(t *testing.T) {
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "main.go", nil, 0)
	if err != nil {
		t.Fatalf("parse main.go: %v", err)
	}
	var labels []string
	ast.Inspect(f, func(n ast.Node) bool {
		fn, ok := n.(*ast.FuncDecl)
		if !ok || fn.Name.Name != "main" {
			return true
		}
		ast.Inspect(fn.Body, func(m ast.Node) bool {
			cc, ok := m.(*ast.CaseClause)
			if !ok {
				return true
			}
			for _, e := range cc.List {
				if bl, ok := e.(*ast.BasicLit); ok && bl.Kind == token.STRING {
					s, _ := strconv.Unquote(bl.Value)
					labels = append(labels, s)
				}
			}
			return true
		})
		return false
	})
	// Control needle: the parser sees the dispatch at all.
	if len(labels) < 20 {
		t.Fatalf("BLIND: parsed only %d case labels from main(): %v", len(labels), labels)
	}
	sort.Strings(labels)
	known := map[string]bool{}
	for _, l := range labels {
		known[l] = true
		if _, ok := con339CommandClass[l]; !ok {
			t.Errorf("subcommand %q is dispatched by main() but not classified for CON-339 (add a property case or a classification)", l)
		}
	}
	caseNames := map[string]bool{}
	for _, c := range con339Cases() {
		caseNames[c.name] = true
	}
	for cmd, cl := range con339CommandClass {
		if !known[cmd] {
			t.Errorf("classified subcommand %q is not dispatched by main()", cmd)
		}
		switch cl.kind {
		case "covered":
			if len(cl.cases) == 0 {
				t.Errorf("%q is classified covered but names no case", cmd)
			}
			for _, c := range cl.cases {
				if !caseNames[c] {
					t.Errorf("%q names case %q, which does not exist", cmd, c)
				}
			}
		case "read-only", "no-items-write", "delegates", "restores":
			if cl.why == "" {
				t.Errorf("%q has kind %q with no reason", cmd, cl.kind)
			}
		default:
			t.Errorf("%q has unknown kind %q", cmd, cl.kind)
		}
	}
}

// TestCON339_ItemsWriteSitesCarryCreatedAt scans the engine's non-test Go
// source for statements that write the items table.
//   - INSERT OR REPLACE / REPLACE INTO items is forbidden outright (a REPLACE is
//     a DELETE + INSERT that would drop created_at);
//   - every INSERT INTO items (and the migration's INSERT INTO items_new) must
//     name created_at in its column list, except in the two functions that
//     create a genuinely NEW item, where the column default is the truth;
//   - DELETE FROM items may appear only in the two functions whose re-insert
//     carries created_at, so a new delete-and-recreate writer fails here until
//     it is reviewed.
func TestCON339_ItemsWriteSitesCarryCreatedAt(t *testing.T) {
	newItemCreators := map[string]bool{"addCmd": true, "subtaskAddCmd": true}
	deleteAllowed := map[string]bool{"closeCmd": true, "replaceDocumentInTx": true}
	files, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	insertRE := regexp.MustCompile(`(?i)\bINSERT\s+INTO\s+items(_new)?\b`)
	replaceRE := regexp.MustCompile(`(?i)\b(INSERT\s+OR\s+REPLACE|REPLACE)\s+INTO\s+items\b`)
	deleteRE := regexp.MustCompile(`(?i)\bDELETE\s+FROM\s+items\b`)
	funcRE := regexp.MustCompile(`(?m)^func\s+(?:\([^)]*\)\s*)?([A-Za-z0-9_]+)`)
	inserts, deletes := 0, map[string]int{}
	for _, fn := range files {
		if strings.HasSuffix(fn, "_test.go") {
			continue
		}
		b, err := os.ReadFile(fn)
		if err != nil {
			t.Fatalf("read %s: %v", fn, err)
		}
		src := string(b)
		enclosing := func(off int) string {
			name := "<file scope>"
			for _, m := range funcRE.FindAllStringSubmatchIndex(src, -1) {
				if m[0] > off {
					break
				}
				name = src[m[2]:m[3]]
			}
			return name
		}
		for _, m := range replaceRE.FindAllStringIndex(src, -1) {
			t.Errorf("%s: %s: REPLACE INTO items re-creates the row and drops created_at", fn, enclosing(m[0]))
		}
		for _, m := range insertRE.FindAllStringIndex(src, -1) {
			if lineIsComment(src, m[0]) {
				continue
			}
			inserts++
			fnName := enclosing(m[0])
			open := strings.Index(src[m[1]:], "(")
			end := strings.Index(src[m[1]:], ")")
			if open < 0 || end < 0 || end < open {
				t.Errorf("%s: %s: cannot read the column list of an INSERT INTO items", fn, fnName)
				continue
			}
			cols := src[m[1]+open : m[1]+end]
			if newItemCreators[fnName] {
				continue
			}
			if !strings.Contains(cols, "created_at") {
				t.Errorf("%s: %s: INSERT INTO items without created_at re-stamps the column default (CON-339)", fn, fnName)
			}
		}
		for _, m := range deleteRE.FindAllStringIndex(src, -1) {
			if lineIsComment(src, m[0]) {
				continue
			}
			deletes[enclosing(m[0])]++
		}
	}
	// Control needle: the scanner sees the known writers (add, close,
	// replaceDocument, subtask add, the migration copy).
	if inserts < 5 {
		t.Fatalf("BLIND: found only %d INSERT INTO items sites", inserts)
	}
	for fnName := range deletes {
		if !deleteAllowed[fnName] {
			t.Errorf("DELETE FROM items in %s: a delete-and-recreate writer must carry created_at and be listed here after review", fnName)
		}
	}
	for fnName := range deleteAllowed {
		if deletes[fnName] == 0 {
			t.Errorf("BLIND: expected a DELETE FROM items in %s and found none (the scan or the allow-list is stale)", fnName)
		}
	}
}

// lineIsComment reports whether the line holding off starts with "//".
func lineIsComment(src string, off int) bool {
	start := strings.LastIndex(src[:off], "\n") + 1
	return strings.HasPrefix(strings.TrimSpace(src[start:off]), "//")
}
