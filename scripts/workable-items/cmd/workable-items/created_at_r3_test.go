// created_at_r3_test.go — CON-339 round 3: the round-2 independent review
// (NO-GO, finding R2-F1) showed that reviewer mutants on the guards of this
// batch survived, a recurrence of the round-1 F1 class. Round 3 closes the
// CLASS instead of one mutant at a time:
//
//	(a) every refusal code of restore-created-at runs WITH and WITHOUT
//	    --dry-run and must carry the same code (a dry run is a promise about
//	    the real run); a source scan proves the table names every code the
//	    command can print;
//	(b) the tracker lower bound under BOTH attestations (items row, Opened row),
//	    at the boundary, in a dry run and a real run;
//	(c) the identity check with near-miss values (letter case, leading and
//	    trailing space) for type and title, and near-miss ids;
//	(d) close refuses when the row's created_at cannot be read (VE03, made
//	    deterministic with a NULL created_at in a legacy-shaped items table).
//
// Evidence class: gate-logic / unit (section 11.4.289); real command, real
// SQLite files under t.TempDir(); no mocks. The one test seam
// (rcaBeforeWriteHook) is nil in production.
package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// r3Snapshot is the state a refused (or dry) run must leave unchanged.
func r3Snapshot(t *testing.T, f rcaFix) string {
	t.Helper()
	rows := rcaQuery(t, f.db, `SELECT group_concat(atm_id||'='||created_at||'@'||last_modified, ',') FROM (SELECT * FROM items ORDER BY atm_id, current_location, representation)`)
	return rows + "|h=" + rcaHistCount(t, f.db)
}

// r3Q is one fixture statement with its arguments.
type r3Q struct {
	q    string
	args []any
}

// r3Forge writes a copy of the fixture's evidence database with the given
// statements applied, checkpointed, and returns its repository-relative path
// and sha256.
func r3Forge(t *testing.T, f rcaFix, name string, stmts ...r3Q) (string, string) {
	t.Helper()
	rel := filepath.Join("evidence", name)
	abs := filepath.Join(f.root, rel)
	con339CopyDB(t, f.evAbs, abs)
	h, err := sql.Open("sqlite3", abs)
	if err != nil {
		t.Fatal(err)
	}
	defer h.Close()
	for _, s := range stmts {
		if _, err := h.Exec(s.q, s.args...); err != nil {
			t.Fatalf("forge %s: %s: %v", name, s.q, err)
		}
	}
	if _, err := h.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		t.Fatal(err)
	}
	h.Close()
	for _, s := range []string{"-wal", "-shm"} {
		os.Remove(abs + s)
	}
	return rel, rcaSHA(t, abs)
}

// r3Checkpoint folds a fixture database's -wal into the main file and removes
// the sidecars, so the evidence file is complete on its own.
func r3Checkpoint(t *testing.T, p string) {
	t.Helper()
	h, err := sql.Open("sqlite3", p)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		h.Close()
		t.Fatal(err)
	}
	h.Close()
	for _, s := range []string{"-wal", "-shm"} {
		os.Remove(p + s)
	}
}

// r3Run runs restore-created-at and returns exit code, stdout and stderr.
func r3Run(t *testing.T, args []string) (int, string, string) {
	t.Helper()
	var out string
	rc, errOut := captureStderrRun(t, func() int {
		var r int
		r, out = captureStdoutRun(t, func() int { return restoreCreatedAtCmd(args) })
		return r
	})
	return rc, out, errOut
}

// r3Case is one refusal: setup may change the fixture (and return extra
// argument overrides); the run must refuse with code, both modes.
type r3Case struct {
	name  string
	code  string
	setup func(t *testing.T, f *rcaFix) []string
}

func r3Cases() []r3Case {
	none := func(extra ...string) func(t *testing.T, f *rcaFix) []string {
		return func(t *testing.T, f *rcaFix) []string { return extra }
	}
	return []r3Case{
		{"usage: missing reason", "USAGE", none("--reason", "\x00")},
		{"usage: multi-line reason", "USAGE", none("--reason", "a\nb")},
		{"usage: positional argument", "USAGE", none("WIT-010")},
		{"usage: unknown flag", "USAGE", none("--frobnicate", "1")},
		{"usage: bad location", "USAGE", none("--location", "issues")},
		{"usage: bad representation", "USAGE", none("--representation", "Section")},
		{"usage: bad by", "USAGE", none("--by", "ai")},
		{"value: ISO-8601", "VALUE-FORMAT", none("--value", "2026-01-01T10:00:00Z")},
		{"value: impossible date", "VALUE-FORMAT", none("--value", "2026-02-30 10:00:00")},
		{"value: leading space", "VALUE-FORMAT", none("--value", " "+rcaOpened)},
		{"sha: not hex", "EVIDENCE-SHA256", none("--evidence-sha256", "ABC")},
		{"sha: mismatch", "EVIDENCE-SHA256", none("--evidence-sha256", strings.Repeat("0", 64))},
		{"db: missing", "DB-MISSING", func(t *testing.T, f *rcaFix) []string {
			return []string{"--db", filepath.Join(filepath.Dir(f.db), "absent.db")}
		}},
		{"evidence: unresolved", "EVIDENCE-UNRESOLVED", none("--evidence", "evidence/absent.db")},
		{"evidence: a directory", "EVIDENCE-NOT-FILE", none("--evidence", "evidence")},
		{"evidence: the live db", "EVIDENCE-IS-LIVE-DB", func(t *testing.T, f *rcaFix) []string {
			return []string{"--evidence", f.db, "--evidence-sha256", rcaSHA(t, f.db)}
		}},
		{"evidence: non-empty -wal", "EVIDENCE-WAL", func(t *testing.T, f *rcaFix) []string {
			if err := os.WriteFile(f.evAbs+"-wal", []byte("uncheckpointed"), 0o644); err != nil {
				t.Fatal(err)
			}
			return nil
		}},
		{"evidence: non-empty -journal", "EVIDENCE-WAL", func(t *testing.T, f *rcaFix) []string {
			if err := os.WriteFile(f.evAbs+"-journal", []byte("hot journal"), 0o644); err != nil {
				t.Fatal(err)
			}
			return nil
		}},
		{"db: unreadable", "DB-UNREADABLE", func(t *testing.T, f *rcaFix) []string {
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
			return nil
		}},
		{"item: not found", "ITEM-NOT-FOUND", none("--id", "WIT-999")},
		{"item: id in lower case", "ITEM-NOT-FOUND", none("--id", "wit-010")},
		{"item: id with trailing space", "ITEM-NOT-FOUND", none("--id", "WIT-010 ")},
		{"item: id with leading space", "ITEM-NOT-FOUND", none("--id", " WIT-010")},
		{"item: ambiguous", "ITEM-AMBIGUOUS", func(t *testing.T, f *rcaFix) []string {
			r2SecondRow(t, *f, "Issues", "table")
			return nil
		}},
		{"evidence: not a database", "EVIDENCE-NOT-DB", func(t *testing.T, f *rcaFix) []string {
			p := filepath.Join(f.root, "evidence", "notes.txt")
			if err := os.WriteFile(p, []byte("this is not a sqlite database, it is text\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			return []string{"--evidence", "evidence/notes.txt", "--evidence-sha256", rcaSHA(t, p)}
		}},
		{"evidence: id absent", "EVIDENCE-ITEM-MISSING", none("--evidence-id", "WIT-777")},
		{"evidence: id in lower case", "EVIDENCE-ITEM-MISSING", none("--evidence-id", "wit-010")},
		{"evidence: id with trailing space", "EVIDENCE-ITEM-MISSING", none("--evidence-id", "WIT-010 ")},
		{"evidence: names another item", "EVIDENCE-ITEM-MISMATCH", none("--id", "WIT-011", "--evidence-id", "WIT-010")},
		{"evidence: does not attest", "EVIDENCE-DOES-NOT-ATTEST", none("--value", "2026-01-01 09:59:30")},
		{"history: item row unreadable", "HISTORY-UNREADABLE", func(t *testing.T, f *rcaFix) []string {
			rcaExec(t, f.db, `UPDATE item_history SET created_at='yesterday' WHERE atm_id='WIT-010'`)
			return nil
		}},
		{"history: tracker minimum not a real time", "HISTORY-UNREADABLE", func(t *testing.T, f *rcaFix) []string {
			rcaExec(t, f.db, `UPDATE item_history SET created_at='2000-13-01 00:00:00' WHERE atm_id='WIT-011'`)
			return nil
		}},
		{"history: none", "NO-HISTORY", func(t *testing.T, f *rcaFix) []string {
			rcaExec(t, f.db, `DELETE FROM item_history WHERE atm_id='WIT-010'`)
			return nil
		}},
		{"value: after the first event", "VALUE-AFTER-FIRST-EVENT", func(t *testing.T, f *rcaFix) []string {
			rcaExec(t, f.db, `UPDATE item_history SET created_at='2026-01-01 09:59:59' WHERE atm_id='WIT-010' AND event_type='Opened'`)
			return nil
		}},
		{"value: before the tracker (items row attests)", "VALUE-BEFORE-TRACKER", func(t *testing.T, f *rcaFix) []string {
			rel, sha := r3Forge(t, *f, "forged_items.db", r3Q{q: `UPDATE items SET created_at='2000-01-01 00:00:00' WHERE atm_id='WIT-010'`})
			return []string{"--value", "2000-01-01 00:00:00", "--evidence", rel, "--evidence-sha256", sha}
		}},
		{"value: before the tracker (Opened row attests)", "VALUE-BEFORE-TRACKER", func(t *testing.T, f *rcaFix) []string {
			rel, sha := r3Forge(t, *f, "forged_opened.db", r3Q{q: `UPDATE item_history SET created_at='2000-01-01 00:00:00' WHERE atm_id='WIT-010' AND event_type='Opened'`})
			return []string{"--value", "2000-01-01 00:00:00", "--evidence", rel, "--evidence-sha256", sha}
		}},
		{"current: unreadable", "CURRENT-UNREADABLE", func(t *testing.T, f *rcaFix) []string {
			rcaExec(t, f.db, `UPDATE items SET created_at='sometime' WHERE atm_id='WIT-010'`)
			return nil
		}},
		{"value: later than current", "VALUE-LATER-THAN-CURRENT", func(t *testing.T, f *rcaFix) []string {
			rcaExec(t, f.db, `UPDATE items SET created_at='2026-01-01 09:59:00' WHERE atm_id='WIT-010'`)
			return nil
		}},
	}
}

// r3WriteOnlyCodes are printed only after the dry-run return; they are
// covered by TestRestoreCreatedAtR3_WriteCodesOnlyInARealRun.
var r3WriteOnlyCodes = map[string]bool{"WRITE": true, "CONCURRENT-CHANGE": true}

// TestRestoreCreatedAtR3_EveryRefusalSameInDryRun (R2-F1 (a); kills VM01 and
// every "skipped in a dry run" mutant of a refusal): each refusal case runs on
// a fresh fixture without and with --dry-run; both must refuse with the same
// code, write nothing, and leave the evidence file unchanged.
func TestRestoreCreatedAtR3_EveryRefusalSameInDryRun(t *testing.T) {
	for _, tc := range r3Cases() {
		tc := tc
		for _, mode := range []string{"real", "dry-run"} {
			mode := mode
			t.Run(tc.name+"/"+mode, func(t *testing.T) {
				f := rcaFixture(t)
				evBefore := rcaSHA(t, f.evAbs)
				extra := tc.setup(t, &f)
				args := f.args(extra...)
				if mode == "dry-run" {
					args = append([]string{"--dry-run"}, args...)
				}
				if tc.code == "DB-MISSING" {
					rc, out, errOut := r3Run(t, args)
					if rc == exitOK || !strings.Contains(errOut, "refused [DB-MISSING]") {
						t.Fatalf("exit %d, stdout %q, stderr %q; want refused [DB-MISSING]", rc, out, errOut)
					}
					if _, err := os.Stat(filepath.Join(filepath.Dir(f.db), "absent.db")); err == nil {
						t.Fatalf("a refused run created the missing database")
					}
					return
				}
				unreadable := tc.code == "DB-UNREADABLE" // openDB cannot read it for a snapshot either
				before := ""
				if unreadable {
					before = rcaSHA(t, f.db)
				} else {
					before = r3Snapshot(t, f)
				}
				rc, out, errOut := r3Run(t, args)
				if rc == exitOK {
					t.Fatalf("accepted (stdout %q); want refused [%s]", out, tc.code)
				}
				if !strings.Contains(errOut, "refused ["+tc.code+"]") {
					t.Fatalf("stderr %q does not carry refused [%s]", errOut, tc.code)
				}
				if strings.Contains(out, "would set") {
					t.Fatalf("a refused run printed a would-write: %q", out)
				}
				if unreadable {
					if got := rcaSHA(t, f.db); got != before {
						t.Errorf("a refused run changed the database file")
					}
				} else if got := r3Snapshot(t, f); got != before {
					t.Errorf("a refused run changed the database: %s -> %s", before, got)
				}
				if got := rcaSHA(t, f.evAbs); got != evBefore {
					t.Errorf("the evidence file changed: %s -> %s", evBefore, got)
				}
			})
		}
	}
}

// TestRestoreCreatedAtR3_RefusalTableNamesEveryCode: a source scan of
// restore_created_at.go finds every refusal code the command can print; each
// is in the table above or is one of the two write-only codes. A control
// needle proves the scan sees codes at all.
func TestRestoreCreatedAtR3_RefusalTableNamesEveryCode(t *testing.T) {
	src, err := os.ReadFile("restore_created_at.go")
	if err != nil {
		t.Fatal(err)
	}
	re := regexp.MustCompile(`rcaRefuse\("([A-Z0-9-]+)"`)
	inSource := map[string]bool{}
	for _, m := range re.FindAllStringSubmatch(string(src), -1) {
		inSource[m[1]] = true
	}
	if !inSource["USAGE"] || !inSource["VALUE-BEFORE-TRACKER"] || len(inSource) < 20 {
		t.Fatalf("control needle: the scan found %d codes (%v); it cannot see the source", len(inSource), inSource)
	}
	inTable := map[string]bool{}
	for _, c := range r3Cases() {
		inTable[c.code] = true
	}
	var missing, stale []string
	for c := range inSource {
		if !inTable[c] && !r3WriteOnlyCodes[c] {
			missing = append(missing, c)
		}
	}
	for c := range inTable {
		if !inSource[c] {
			stale = append(stale, c)
		}
	}
	for c := range r3WriteOnlyCodes {
		if !inSource[c] {
			stale = append(stale, c)
		}
	}
	sort.Strings(missing)
	sort.Strings(stale)
	if len(missing) > 0 || len(stale) > 0 {
		t.Fatalf("refusal table out of step with the source: missing %v, not in source %v", missing, stale)
	}
	t.Logf("%d refusal codes in the source, %d in the dry-run table, %d write-only", len(inSource), len(inTable), len(r3WriteOnlyCodes))
}

// TestRestoreCreatedAtR3_WriteCodesOnlyInARealRun: WRITE and CONCURRENT-CHANGE
// come after every check; a real run refuses with them, a dry run with the same
// seam accepts without reaching the seam and writes nothing.
func TestRestoreCreatedAtR3_WriteCodesOnlyInARealRun(t *testing.T) {
	for _, tc := range []struct {
		code string
		hook func(t *testing.T, f rcaFix) func()
	}{
		{"CONCURRENT-CHANGE", func(t *testing.T, f rcaFix) func() {
			return func() { rcaExec(t, f.db, `UPDATE items SET created_at='2026-01-03 03:03:03' WHERE atm_id='WIT-010'`) }
		}},
		{"WRITE", func(t *testing.T, f rcaFix) func() {
			return func() {
				rcaExec(t, f.db, `CREATE TRIGGER r3_no_history BEFORE INSERT ON item_history BEGIN SELECT RAISE(ABORT, 'r3 audit blocked'); END`)
			}
		}},
	} {
		tc := tc
		t.Run(tc.code, func(t *testing.T) {
			t.Cleanup(func() { rcaBeforeWriteHook = nil })
			f := rcaFixture(t)
			reached := false
			h := tc.hook(t, f)
			rcaBeforeWriteHook = func() { reached = true; h() }
			before := r3Snapshot(t, f)
			rc, out, errOut := r3Run(t, f.args("--dry-run"))
			if rc != exitOK || !strings.Contains(out, "would set") || reached {
				t.Fatalf("dry run: exit %d, reached %v, stdout %q, stderr %q", rc, reached, out, errOut)
			}
			if got := r3Snapshot(t, f); got != before {
				t.Fatalf("dry run changed the database: %s -> %s", before, got)
			}
			rc, _, errOut = r3Run(t, f.args())
			rcaBeforeWriteHook = nil
			if rc == exitOK || !reached || !strings.Contains(errOut, "refused ["+tc.code+"]") {
				t.Fatalf("real run: exit %d, reached %v, stderr %q; want refused [%s]", rc, reached, errOut, tc.code)
			}
			if got := rcaQuery(t, f.db, `SELECT COUNT(1) FROM item_history WHERE reason LIKE 'created-at-restored%'`); got != "0" {
				t.Errorf("an audit row was committed: %s", got)
			}
		})
	}
}

// TestRestoreCreatedAtR3_TrackerBoundBothAttestations (R2-F1 (b); kills VM06,
// its mirror and VM01): the lower bound holds whichever evidence row attests
// the value, at the boundary (tracker minimum minus the 60 s slack accepted,
// one second earlier refused), in a dry run and a real run. The accepted run
// names the attestation the case built.
func TestRestoreCreatedAtR3_TrackerBoundBothAttestations(t *testing.T) {
	// rcaFixture: every live history row is at rcaOpened (10:00:00), so the
	// tracker minimum is 10:00:00 and the bound is 09:59:00.
	for _, att := range []string{"items-row", "opened-event"} {
		for _, v := range []struct {
			value  string
			accept bool
		}{
			{"2000-01-01 00:00:00", false},
			{"2026-01-01 09:58:59", false},
			{"2026-01-01 09:59:00", true},
		} {
			for _, mode := range []string{"real", "dry-run"} {
				att, v, mode := att, v, mode
				t.Run(att+"/"+v.value+"/"+mode, func(t *testing.T) {
					f := rcaFixture(t)
					if got := rcaQuery(t, f.db, `SELECT MIN(created_at) FROM item_history`); got != rcaOpened {
						t.Fatalf("control: tracker minimum %q, want %q", got, rcaOpened)
					}
					var stmts []r3Q
					if att == "items-row" {
						stmts = []r3Q{{`UPDATE items SET created_at=? WHERE atm_id='WIT-010'`, []any{v.value}}}
					} else {
						// the items row holds a value no case uses, so only the Opened row attests
						stmts = []r3Q{
							{`UPDATE items SET created_at='2026-01-01 09:59:45' WHERE atm_id='WIT-010'`, nil},
							{`UPDATE item_history SET created_at=? WHERE atm_id='WIT-010' AND event_type='Opened'`, []any{v.value}},
						}
					}
					rel, sha := r3Forge(t, f, "bound.db", stmts...)
					extra := []string{"--value", v.value, "--evidence", rel, "--evidence-sha256", sha}
					if mode == "dry-run" {
						extra = append(extra, "--dry-run")
					}
					before := r3Snapshot(t, f)
					rc, out, errOut := r3Run(t, f.args(extra...))
					if !v.accept {
						if rc == exitOK || !strings.Contains(errOut, "refused [VALUE-BEFORE-TRACKER]") {
							t.Fatalf("exit %d, stdout %q, stderr %q; want refused [VALUE-BEFORE-TRACKER]", rc, out, errOut)
						}
						if got := r3Snapshot(t, f); got != before {
							t.Fatalf("a refused run changed the database")
						}
						return
					}
					if rc != exitOK {
						t.Fatalf("boundary value refused: exit %d, stderr %q", rc, errOut)
					}
					if !strings.Contains(out, "attested-by="+att+":WIT-010") {
						t.Fatalf("stdout %q does not name attested-by=%s", out, att)
					}
					got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`)
					if mode == "dry-run" && got != rcaRewritten {
						t.Fatalf("dry run wrote created_at %q", got)
					}
					if mode == "real" && got != v.value {
						t.Fatalf("real run: created_at %q, want %q", got, v.value)
					}
				})
			}
		}
	}
}

// TestRestoreCreatedAtR3_IdentityNearMiss (R2-F1 (c); kills VM02 and the
// type / trim variants): an evidence row whose type or title differs from the
// live row only in letter case or in a leading or trailing space does not
// identify the live item, in a dry run and a real run. The exact copy is the
// control and is accepted.
func TestRestoreCreatedAtR3_IdentityNearMiss(t *testing.T) {
	swapOne := func(s string) string { // swap the case of the first letter
		for i, r := range s {
			if r >= 'a' && r <= 'z' {
				return s[:i] + strings.ToUpper(string(r)) + s[i+1:]
			}
			if r >= 'A' && r <= 'Z' {
				return s[:i] + strings.ToLower(string(r)) + s[i+1:]
			}
		}
		t.Fatalf("no letter in %q", s)
		return s
	}
	cases := []struct{ col, val string }{
		{"type", "bug"}, {"type", "BUG"}, {"type", " Bug"}, {"type", "Bug "}, {"type", "Bug\t"},
		{"title", swapOne(rcaTitle)}, {"title", strings.ToUpper(rcaTitle)},
		{"title", " " + rcaTitle}, {"title", rcaTitle + " "}, {"title", rcaTitle + "\n"},
	}
	for _, c := range cases {
		for _, mode := range []string{"real", "dry-run"} {
			c, mode := c, mode
			t.Run(c.col+"/"+strings.NewReplacer(" ", "_", "\t", "TAB", "\n", "LF").Replace(c.val)+"/"+mode, func(t *testing.T) {
				f := rcaFixture(t)
				if c.val == rcaTitle || c.val == "Bug" {
					t.Fatalf("near-miss value equals the live value")
				}
				rel, _ := r3Forge(t, f, "near.db")
				abs := filepath.Join(f.root, rel)
				if c.col == "type" {
					// the closed type set is a CHECK of the current schema; an
					// evidence file from an older or hand-built schema has none
					r3RebuildItems(t, abs, r3TypeCheck, "")
				}
				rcaExec(t, abs, `UPDATE items SET `+c.col+`=? WHERE atm_id='WIT-010'`, c.val)
				r3Checkpoint(t, abs)
				sha := rcaSHA(t, abs)
				if got := rcaQuery(t, filepath.Join(f.root, rel), `SELECT `+c.col+` FROM items WHERE atm_id='WIT-010'`); got != c.val {
					t.Fatalf("control: forged %s %q, want %q", c.col, got, c.val)
				}
				extra := []string{"--evidence", rel, "--evidence-sha256", sha}
				if mode == "dry-run" {
					extra = append(extra, "--dry-run")
				}
				r2Refused(t, f, "EVIDENCE-ITEM-MISMATCH", f.args(extra...))
			})
		}
	}
	// Control: an unchanged copy identifies the item (the forge path itself
	// does not cause the refusals above).
	f := rcaFixture(t)
	rel, sha := r3Forge(t, f, "exact.db")
	r2Accepted(t, f, f.args("--evidence", rel, "--evidence-sha256", sha, "--dry-run"))
	r2Accepted(t, f, f.args("--evidence", rel, "--evidence-sha256", sha))
}

// r3RebuildItems rebuilds the items table of dbPath with the one match of re
// in its DDL replaced by repl, keeping every row and column: a legacy-shaped
// table (a fixture write on a scratch database). The current schema forbids
// the states these tests need (a NULL created_at, a type outside the closed
// set), so no engine path writes them; a caller-supplied evidence file or an
// old tracker may still hold them.
func r3RebuildItems(t *testing.T, dbPath string, re *regexp.Regexp, repl string) {
	t.Helper()
	h, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer h.Close()
	h.SetMaxOpenConns(1)
	var ddl string
	if err := h.QueryRow(`SELECT sql FROM sqlite_master WHERE type='table' AND name='items'`).Scan(&ddl); err != nil {
		t.Fatal(err)
	}
	if n := len(re.FindAllStringIndex(ddl, -1)); n != 1 {
		t.Fatalf("fixture: %d matches of %s in the items DDL", n, re)
	}
	newDDL := re.ReplaceAllLiteralString(ddl, repl)
	newDDL = strings.Replace(newDDL, "CREATE TABLE items", "CREATE TABLE items_r3", 1)
	if !strings.Contains(newDDL, "CREATE TABLE items_r3") {
		t.Fatalf("fixture: unexpected items DDL head: %.60s", ddl)
	}
	for _, q := range []string{
		`PRAGMA foreign_keys=OFF`,
		newDDL,
		`INSERT INTO items_r3 SELECT * FROM items`,
		`DROP TABLE items`,
		`ALTER TABLE items_r3 RENAME TO items`,
		`PRAGMA wal_checkpoint(TRUNCATE)`,
	} {
		if _, err := h.Exec(q); err != nil {
			t.Fatalf("fixture %.60s: %v", q, err)
		}
	}
}

var (
	r3CreatedAtNotNull = regexp.MustCompile(`created_at\s+TEXT\s+NOT\s+NULL`)
	r3TypeCheck        = regexp.MustCompile(`CHECK \(type IN \('Bug', 'Feature', 'Task'\)\)`)
)

// TestCON339R3_CloseRefusesUnreadableCreatedAt (R2-F2, kills VE03): when the
// Issues row's created_at cannot be read (NULL in a legacy-shaped table),
// close refuses and changes nothing; it never inserts a Fixed row with an
// empty created_at. Control: the same fixture with a readable value closes and
// carries the value.
func TestCON339R3_CloseRefusesUnreadableCreatedAt(t *testing.T) {
	for _, null := range []bool{true, false} {
		null := null
		name := "control-readable"
		if null {
			name = "null-created-at"
		}
		t.Run(name, func(t *testing.T) {
			root := newEvidenceRoot(t)
			db := newTestDB(t)
			r2Add(t, db, "WIT-010", "close fixture item", "Bug", "High")
			r3RebuildItems(t, db, r3CreatedAtNotNull, "created_at TEXT")
			if null {
				rcaExec(t, db, `UPDATE items SET created_at=NULL WHERE atm_id='WIT-010'`)
				if got := rcaQuery(t, db, `SELECT COUNT(1) FROM items WHERE atm_id='WIT-010' AND created_at IS NULL`); got != "1" {
					t.Fatalf("fixture: NULL created_at rows %s", got)
				}
			} else {
				rcaExec(t, db, `UPDATE items SET created_at='2026-01-01 10:00:00' WHERE atm_id='WIT-010'`)
			}
			ev := materialiseEvidence(t, root, "docs/qa/WIT-010/close.md")
			h0 := rcaHistCount(t, db)
			rc, errOut := captureStderrRun(t, func() int {
				return closeCmd([]string{"WIT-010", "--db", db, "--status", "fixed", "--evidence", ev})
			})
			fixed := rcaQuery(t, db, `SELECT COUNT(1) FROM items WHERE atm_id='WIT-010' AND current_location='Fixed'`)
			issues := rcaQuery(t, db, `SELECT COUNT(1) FROM items WHERE atm_id='WIT-010' AND current_location='Issues'`)
			if !null {
				if rc != exitOK || fixed != "1" || issues != "0" {
					t.Fatalf("control close: exit %d, Fixed %s, Issues %s, stderr %q", rc, fixed, issues, errOut)
				}
				if got := rcaQuery(t, db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != "2026-01-01 10:00:00" {
					t.Fatalf("control close: created_at %q", got)
				}
				return
			}
			if rc == exitOK {
				t.Fatalf("close accepted an unreadable created_at (Fixed %s, Issues %s)", fixed, issues)
			}
			if !strings.Contains(errOut, "read created_at of WIT-010") {
				t.Errorf("stderr %q does not name the created_at read", errOut)
			}
			if fixed != "0" || issues != "1" {
				t.Fatalf("a refused close changed rows: Fixed %s, Issues %s", fixed, issues)
			}
			if got := rcaHistCount(t, db); got != h0 {
				t.Errorf("a refused close wrote history (%s -> %s)", h0, got)
			}
		})
	}
}
