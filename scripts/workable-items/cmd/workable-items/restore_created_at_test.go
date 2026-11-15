// restore_created_at_test.go — CON-339: `restore-created-at`, the one engine
// path that changes items.created_at, restoring a value an earlier engine
// defect overwrote.
//
// The fixture plays the defect out on a t.TempDir() database: an item is
// created, a SNAPSHOT of the database is taken (the evidence: a committed
// tracker database in real use), then the item's created_at is overwritten with
// a later value (what `close` / `md-to-db` did before the fix). The fixture
// writes are test writes on a scratch database; the command under test is the
// only writer the assertions are about.
//
// Evidence class: gate-logic / unit (section 11.4.289) — real command on real
// SQLite files; no mocks.
package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	rcaOpened    = "2026-01-01 10:00:00" // the Opened history row's created_at (attested)
	rcaOriginal  = "2026-01-01 09:59:00" // the item row's created_at in the snapshot (attested)
	rcaRewritten = "2026-01-05 12:00:00" // what the defect wrote over it
	rcaTitle     = "restore fixture item ten"
)

type rcaFix struct {
	db, root, ev, evAbs, sha string
}

func rcaSHA(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("read %s: %v", p, err)
	}
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func rcaExec(t *testing.T, dbPath, q string, args ...any) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(q, args...); err != nil {
		t.Fatalf("fixture exec %q: %v", q, err)
	}
}

func rcaQuery(t *testing.T, dbPath, q string, args ...any) string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var s sql.NullString
	if err := db.QueryRow(q, args...).Scan(&s); err != nil {
		t.Fatalf("query %q: %v", q, err)
	}
	return s.String
}

func rcaFixture(t *testing.T) rcaFix {
	t.Helper()
	f := rcaFix{db: newTestDB(t), root: newEvidenceRoot(t)}
	for _, a := range [][]string{
		{"--id", "WIT-010", "--title", rcaTitle, "Bug", "High"},
		{"--id", "WIT-011", "--title", "restore fixture item eleven", "Task", "Low"},
	} {
		args := append([]string{"--db", f.db, "--description",
			"a sufficiently long description that clears the section 11.4.91 floor for the restore tests"}, a...)
		if rc := addCmd(args); rc != exitOK {
			t.Fatalf("fixture add %v exited %d", a, rc)
		}
	}
	rcaExec(t, f.db, `UPDATE item_history SET created_at=? WHERE atm_id IN ('WIT-010','WIT-011') AND event_type='Opened'`, rcaOpened)
	rcaExec(t, f.db, `UPDATE items SET created_at=? WHERE atm_id IN ('WIT-010','WIT-011')`, rcaOriginal)
	f.ev = "evidence/snapshot.db"
	f.evAbs = filepath.Join(f.root, f.ev)
	if err := os.MkdirAll(filepath.Dir(f.evAbs), 0o755); err != nil {
		t.Fatal(err)
	}
	con339CopyDB(t, f.db, f.evAbs)
	f.sha = rcaSHA(t, f.evAbs)
	// The defect: created_at overwritten after the snapshot; last_modified too.
	rcaExec(t, f.db, `UPDATE items SET created_at=?, last_modified=? WHERE atm_id IN ('WIT-010','WIT-011')`, rcaRewritten, rcaRewritten)
	return f
}

func (f rcaFix) args(extra ...string) []string {
	base := map[string]string{
		"--db": f.db, "--id": "WIT-010", "--value": rcaOpened, "--evidence": f.ev,
		"--evidence-sha256": f.sha, "--reason": "CON-339 restore test",
	}
	order := []string{"--db", "--id", "--value", "--evidence", "--evidence-sha256", "--reason"}
	// extra overrides: "--flag", "value" pairs; a value of "\x00" drops the flag.
	for i := 0; i+1 < len(extra); i += 2 {
		if _, ok := base[extra[i]]; !ok {
			order = append(order, extra[i])
		}
		base[extra[i]] = extra[i+1]
	}
	var out []string
	for _, k := range order {
		if v := base[k]; v != "\x00" {
			out = append(out, k, v)
		}
	}
	if len(extra)%2 == 1 {
		out = append(out, extra[len(extra)-1])
	}
	return out
}

func rcaHistCount(t *testing.T, dbPath string) string {
	t.Helper()
	return rcaQuery(t, dbPath, `SELECT COUNT(1) FROM item_history`)
}

func TestRestoreCreatedAt_RestoresFromOpenedEvent(t *testing.T) {
	f := rcaFixture(t)
	before := rcaHistCount(t, f.db)
	rc, out := captureStdoutRun(t, func() int { return restoreCreatedAtCmd(f.args()) })
	if rc != exitOK {
		t.Fatalf("restore exited %d: %s", rc, out)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != rcaOpened {
		t.Fatalf("created_at %q, want %q", got, rcaOpened)
	}
	if got := rcaQuery(t, f.db, `SELECT last_modified FROM items WHERE atm_id='WIT-010'`); got == rcaRewritten {
		t.Errorf("last_modified not advanced by the restore: %q", got)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-011'`); got != rcaRewritten {
		t.Errorf("WIT-011 changed: %q", got)
	}
	if after := rcaHistCount(t, f.db); after == before {
		t.Fatalf("no item_history row written")
	}
	reason := rcaQuery(t, f.db, `SELECT reason FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`)
	for _, want := range []string{
		`created-at-restored`, `old="` + rcaRewritten + `"`, `new="` + rcaOpened + `"`,
		`evidence-sha256=` + f.sha, `attested-by=opened-event:WIT-010`, `reason=CON-339 restore test`,
	} {
		if !strings.Contains(reason, want) {
			t.Errorf("audit reason %q lacks %q", reason, want)
		}
	}
	if ev := rcaQuery(t, f.db, `SELECT evidence_path FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`); ev != f.ev {
		t.Errorf("audit evidence_path %q, want %q", ev, f.ev)
	}
	if ev := rcaQuery(t, f.db, `SELECT event_type || '/' || by FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`); ev != "Updated/AI" {
		t.Errorf("audit row %q, want Updated/AI", ev)
	}
	if !strings.Contains(out, rcaRewritten) || !strings.Contains(out, rcaOpened) {
		t.Errorf("stdout does not name old and new value: %s", out)
	}
	// The evidence database is read, never written, and grows no sidecar.
	if got := rcaSHA(t, f.evAbs); got != f.sha {
		t.Errorf("evidence database changed: %s", got)
	}
	for _, s := range []string{"-wal", "-shm", "-journal"} {
		if _, err := os.Stat(f.evAbs + s); err == nil {
			t.Errorf("evidence sidecar %s created", s)
		}
	}
	if rc := validateCmd([]string{"--db", f.db}); rc != exitOK {
		t.Errorf("validate after restore exited %d", rc)
	}
}

// TestRestoreCreatedAt_ReadOnlyEvidence: evidence kept read-only (file 0444 in
// a 0555 directory, as an extracted committed database should be) is still
// read. The fixture database is in WAL mode, and SQLite cannot open a WAL-mode
// file in a directory it cannot write unless the open is immutable (measured
// 2026-11-13: mode=ro alone fails with "attempt to write a readonly database").
func TestRestoreCreatedAt_ReadOnlyEvidence(t *testing.T) {
	f := rcaFixture(t)
	dir := filepath.Dir(f.evAbs)
	if err := os.Chmod(f.evAbs, 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o755); os.Chmod(f.evAbs, 0o644) })
	// Control: the directory really is read-only for this process.
	if fh, err := os.CreateTemp(dir, "probe"); err == nil {
		fh.Close()
		t.Skip("cannot make a read-only directory here (running with privileges that ignore modes)")
	}
	if rc := restoreCreatedAtCmd(f.args()); rc != exitOK {
		t.Fatalf("restore from read-only evidence exited %d", rc)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != rcaOpened {
		t.Fatalf("created_at %q, want %q", got, rcaOpened)
	}
	if got := rcaSHA(t, f.evAbs); got != f.sha {
		t.Errorf("evidence database changed: %s", got)
	}
}

func TestRestoreCreatedAt_RestoresFromItemsRow(t *testing.T) {
	f := rcaFixture(t)
	rc, out := captureStdoutRun(t, func() int { return restoreCreatedAtCmd(f.args("--value", rcaOriginal, "--by", "User")) })
	if rc != exitOK {
		t.Fatalf("restore exited %d: %s", rc, out)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != rcaOriginal {
		t.Fatalf("created_at %q, want %q", got, rcaOriginal)
	}
	reason := rcaQuery(t, f.db, `SELECT reason FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`)
	if !strings.Contains(reason, "attested-by=items-row:WIT-010") {
		t.Errorf("audit reason %q does not name the items-row attestation", reason)
	}
	if by := rcaQuery(t, f.db, `SELECT by FROM item_history WHERE atm_id='WIT-010' ORDER BY id DESC LIMIT 1`); by != "User" {
		t.Errorf("audit by %q, want User", by)
	}
}

func TestRestoreCreatedAt_IdempotentAndDryRun(t *testing.T) {
	f := rcaFixture(t)
	h0 := rcaHistCount(t, f.db)
	rc, out := captureStdoutRun(t, func() int { return restoreCreatedAtCmd(f.args("--dry-run")) })
	if rc != exitOK || !strings.Contains(out, "dry-run") {
		t.Fatalf("dry-run exited %d: %s", rc, out)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`); got != rcaRewritten {
		t.Fatalf("dry-run wrote created_at %q", got)
	}
	if h := rcaHistCount(t, f.db); h != h0 {
		t.Fatalf("dry-run wrote history (%s -> %s)", h0, h)
	}
	if rc := restoreCreatedAtCmd(f.args()); rc != exitOK {
		t.Fatalf("first restore exited %d", rc)
	}
	h1 := rcaHistCount(t, f.db)
	lm1 := rcaQuery(t, f.db, `SELECT last_modified FROM items WHERE atm_id='WIT-010'`)
	rc, out = captureStdoutRun(t, func() int { return restoreCreatedAtCmd(f.args()) })
	if rc != exitOK || !strings.Contains(out, "already") {
		t.Fatalf("second restore exited %d: %s", rc, out)
	}
	if h := rcaHistCount(t, f.db); h != h1 {
		t.Errorf("second restore wrote history (%s -> %s)", h1, h)
	}
	if lm := rcaQuery(t, f.db, `SELECT last_modified FROM items WHERE atm_id='WIT-010'`); lm != lm1 {
		t.Errorf("second restore touched last_modified (%s -> %s)", lm1, lm)
	}
}

// TestRestoreCreatedAt_EvidenceIDMapsAReMintedItem: a landing may re-mint an
// item's id; --evidence-id names the id the evidence database uses.
func TestRestoreCreatedAt_EvidenceIDMapsAReMintedItem(t *testing.T) {
	f := rcaFixture(t)
	if rc := addCmd([]string{"--db", f.db, "--id", "WIT-012", "--title", rcaTitle, "--description",
		"a sufficiently long description that clears the section 11.4.91 floor for the restore tests", "Bug", "High"}); rc != exitOK {
		t.Fatalf("add WIT-012 exited %d", rc)
	}
	rcaExec(t, f.db, `UPDATE item_history SET created_at='2026-01-06 00:00:00' WHERE atm_id='WIT-012'`)
	rcaExec(t, f.db, `UPDATE items SET created_at='2026-01-06 00:00:00' WHERE atm_id='WIT-012'`)
	rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(f.args("--id", "WIT-012")) })
	if rc == exitOK || !strings.Contains(errOut, "[EVIDENCE-ITEM-MISSING]") {
		t.Fatalf("without --evidence-id: exit %d, stderr %s", rc, errOut)
	}
	if rc := restoreCreatedAtCmd(f.args("--id", "WIT-012", "--evidence-id", "WIT-010")); rc != exitOK {
		t.Fatalf("with --evidence-id exited %d", rc)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-012'`); got != rcaOpened {
		t.Fatalf("WIT-012 created_at %q, want %q", got, rcaOpened)
	}
	reason := rcaQuery(t, f.db, `SELECT reason FROM item_history WHERE atm_id='WIT-012' ORDER BY id DESC LIMIT 1`)
	if !strings.Contains(reason, "attested-by=opened-event:WIT-010") {
		t.Errorf("audit reason %q does not name the evidence id", reason)
	}
}

// TestRestoreCreatedAt_AmbiguousRowNeedsNarrowing: an id with two rows (a
// dual representation) is refused until --representation picks one.
func TestRestoreCreatedAt_AmbiguousRowNeedsNarrowing(t *testing.T) {
	f := rcaFixture(t)
	rcaExec(t, f.db, `INSERT INTO items (atm_id, type, status, title, description, current_location, representation, created_at, last_modified)
		SELECT atm_id, type, status, title, description, current_location, 'table', created_at, last_modified FROM items WHERE atm_id='WIT-010'`)
	rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(f.args()) })
	if rc == exitOK || !strings.Contains(errOut, "[ITEM-AMBIGUOUS]") {
		t.Fatalf("ambiguous: exit %d, stderr %s", rc, errOut)
	}
	if rc := restoreCreatedAtCmd(f.args("--representation", "section", "--location", "Issues")); rc != exitOK {
		t.Fatalf("narrowed restore exited %d", rc)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010' AND representation='section'`); got != rcaOpened {
		t.Errorf("section row %q, want %q", got, rcaOpened)
	}
	if got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010' AND representation='table'`); got != rcaRewritten {
		t.Errorf("table row changed: %q", got)
	}
}

func TestRestoreCreatedAt_Refusals(t *testing.T) {
	cases := []struct {
		name  string
		code  string
		setup func(t *testing.T, f *rcaFix) // may change the fixture before the run
		args  func(f rcaFix) []string
	}{
		{"missing reason", "USAGE", nil, func(f rcaFix) []string { return f.args("--reason", "\x00") }},
		{"blank reason", "USAGE", nil, func(f rcaFix) []string { return f.args("--reason", "   ") }},
		{"multi-line reason", "USAGE", nil, func(f rcaFix) []string { return f.args("--reason", "a\nb") }},
		{"missing evidence", "USAGE", nil, func(f rcaFix) []string { return f.args("--evidence", "\x00") }},
		{"missing value", "USAGE", nil, func(f rcaFix) []string { return f.args("--value", "\x00") }},
		{"positional argument", "USAGE", nil, func(f rcaFix) []string { return f.args("WIT-010") }},
		{"bad location", "USAGE", nil, func(f rcaFix) []string { return f.args("--location", "Elsewhere") }},
		{"bad representation", "USAGE", nil, func(f rcaFix) []string { return f.args("--representation", "list") }},
		{"bad by", "USAGE", nil, func(f rcaFix) []string { return f.args("--by", "robot") }},
		{"ISO-8601 value", "VALUE-FORMAT", nil, func(f rcaFix) []string { return f.args("--value", "2026-01-01T10:00:00Z") }},
		{"impossible date", "VALUE-FORMAT", nil, func(f rcaFix) []string { return f.args("--value", "2026-02-30 10:00:00") }},
		{"trailing space", "VALUE-FORMAT", nil, func(f rcaFix) []string { return f.args("--value", rcaOpened+" ") }},
		{"date only", "VALUE-FORMAT", nil, func(f rcaFix) []string { return f.args("--value", "2026-01-01") }},
		{"sha not hex", "EVIDENCE-SHA256", nil, func(f rcaFix) []string { return f.args("--evidence-sha256", "ABC") }},
		{"sha upper case", "EVIDENCE-SHA256", nil, func(f rcaFix) []string { return f.args("--evidence-sha256", strings.ToUpper(f.sha)) }},
		{"sha mismatch", "EVIDENCE-SHA256", nil, func(f rcaFix) []string { return f.args("--evidence-sha256", strings.Repeat("0", 64)) }},
		{"live db missing", "DB-MISSING", nil, func(f rcaFix) []string {
			return f.args("--db", filepath.Join(filepath.Dir(f.db), "nope", "absent.db"))
		}},
		{"evidence missing", "EVIDENCE-UNRESOLVED", nil, func(f rcaFix) []string { return f.args("--evidence", "evidence/absent.db") }},
		{"evidence is a directory", "EVIDENCE-NOT-FILE", nil, func(f rcaFix) []string { return f.args("--evidence", "evidence") }},
		{"evidence is the live db", "EVIDENCE-IS-LIVE-DB", nil, func(f rcaFix) []string {
			return f.args("--evidence", f.db, "--evidence-sha256", "\x01")
		}},
		{"evidence has a wal", "EVIDENCE-WAL", func(t *testing.T, f *rcaFix) {
			if err := os.WriteFile(f.evAbs+"-wal", []byte("uncheckpointed"), 0o644); err != nil {
				t.Fatal(err)
			}
		}, func(f rcaFix) []string { return f.args() }},
		{"evidence not a database", "EVIDENCE-NOT-DB", func(t *testing.T, f *rcaFix) {
			p := filepath.Join(f.root, "evidence", "notes.txt")
			if err := os.WriteFile(p, []byte("this is not a sqlite database, it is text\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			f.ev, f.evAbs, f.sha = "evidence/notes.txt", p, rcaSHA(t, p)
		}, func(f rcaFix) []string { return f.args() }},
		{"item not found", "ITEM-NOT-FOUND", nil, func(f rcaFix) []string { return f.args("--id", "WIT-999") }},
		{"location narrows to nothing", "ITEM-NOT-FOUND", nil, func(f rcaFix) []string { return f.args("--location", "Fixed") }},
		{"evidence names another item", "EVIDENCE-ITEM-MISMATCH", nil, func(f rcaFix) []string {
			return f.args("--id", "WIT-011", "--evidence-id", "WIT-010")
		}},
		{"evidence id absent", "EVIDENCE-ITEM-MISSING", nil, func(f rcaFix) []string { return f.args("--evidence-id", "WIT-777") }},
		{"value not in evidence", "EVIDENCE-DOES-NOT-ATTEST", nil, func(f rcaFix) []string { return f.args("--value", "2026-01-01 09:00:00") }},
		{"value later than first event", "VALUE-AFTER-FIRST-EVENT", func(t *testing.T, f *rcaFix) {
			rcaExec(t, f.db, `UPDATE item_history SET created_at='2025-12-31 23:00:00' WHERE atm_id='WIT-010' AND event_type='Opened'`)
		}, func(f rcaFix) []string { return f.args() }},
		{"value later than current", "VALUE-LATER-THAN-CURRENT", func(t *testing.T, f *rcaFix) {
			rcaExec(t, f.db, `UPDATE items SET created_at='2026-01-01 08:00:00' WHERE atm_id='WIT-010'`)
		}, func(f rcaFix) []string { return f.args() }},
		{"no history", "NO-HISTORY", func(t *testing.T, f *rcaFix) {
			rcaExec(t, f.db, `DELETE FROM item_history WHERE atm_id='WIT-010'`)
		}, func(f rcaFix) []string { return f.args() }},
		{"history time unreadable", "HISTORY-UNREADABLE", func(t *testing.T, f *rcaFix) {
			rcaExec(t, f.db, `UPDATE item_history SET created_at='yesterday' WHERE atm_id='WIT-010'`)
		}, func(f rcaFix) []string { return f.args() }},
		{"current value unreadable", "CURRENT-UNREADABLE", func(t *testing.T, f *rcaFix) {
			rcaExec(t, f.db, `UPDATE items SET created_at='sometime' WHERE atm_id='WIT-010'`)
		}, func(f rcaFix) []string { return f.args() }},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			f := rcaFixture(t)
			if tc.setup != nil {
				tc.setup(t, &f)
			}
			args := tc.args(f)
			for i := range args {
				if args[i] == "\x01" { // the live db's own sha256
					args[i] = rcaSHA(t, f.db)
				}
			}
			caBefore := rcaQuery(t, f.db, `SELECT group_concat(atm_id||'='||created_at||'@'||last_modified, ',') FROM (SELECT * FROM items ORDER BY atm_id, representation)`)
			hBefore := rcaHistCount(t, f.db)
			rc, errOut := captureStderrRun(t, func() int { return restoreCreatedAtCmd(args) })
			if rc == exitOK {
				t.Fatalf("accepted; want refusal [%s]", tc.code)
			}
			if !strings.Contains(errOut, "refused ["+tc.code+"]") {
				t.Fatalf("stderr %q does not carry refused [%s]", errOut, tc.code)
			}
			if tc.code == "DB-MISSING" {
				if _, err := os.Stat(filepath.Join(filepath.Dir(f.db), "nope")); err == nil {
					t.Errorf("a refused run created the missing database's directory")
				}
				return
			}
			if got := rcaQuery(t, f.db, `SELECT group_concat(atm_id||'='||created_at||'@'||last_modified, ',') FROM (SELECT * FROM items ORDER BY atm_id, representation)`); got != caBefore {
				t.Errorf("a refused run changed items: %s -> %s", caBefore, got)
			}
			if h := rcaHistCount(t, f.db); h != hBefore {
				t.Errorf("a refused run wrote history (%s -> %s)", hBefore, h)
			}
		})
	}
}
