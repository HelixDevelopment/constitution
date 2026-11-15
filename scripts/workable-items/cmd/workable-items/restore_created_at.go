// restore_created_at.go — the `restore-created-at` subcommand (CON-339).
//
// # WHY THIS EXISTS
//
// Before the CON-339 fix, `close` and `sync md-to-db` deleted an item row and
// inserted it again without the created_at column, so the column DEFAULT
// (datetime('now')) stamped the time of the close or the sync over the item's
// real creation time. The fix stops new damage; this command repairs rows the
// defect already rewrote. The tracker is changed only through the engine
// (section 11.4.93), so the repair is an engine command, not a hand edit.
//
// # WHAT IT ACCEPTS (and nothing else)
//
//   - one row of one item (--id, narrowed by --location / --representation
//     when the item has more than one row);
//   - a value in the stored format YYYY-MM-DD HH:MM:SS that is a real date;
//   - evidence: a separate SQLite file (a committed tracker database extracted
//     with `git show <commit>:<path>`), named by path and sha256, that records
//     the value either as that item's items.created_at or as the created_at of
//     its Opened history row (--evidence-id names the item there when a later
//     landing re-minted the id);
//   - the evidence item must have the live item's type and title;
//   - the value must not be later than the live item's first history row, and
//     not later than the value it replaces: a restore only moves created_at
//     back to a recorded earlier time;
//   - the value must not be earlier than the tracker's first well-formed
//     history row by more than rcaTrackerSlack (60 s): no item of this tracker
//     was created before the tracker recorded anything (VALUE-BEFORE-TRACKER).
//
// Every refusal prints `restore-created-at: refused [CODE]: ...` and exits 1
// with nothing written. A successful restore updates the one row and writes an
// `Updated` item_history row whose reason records the old value, the new
// value, the evidence sha256, what attested the value and the operator's
// reason, in one transaction. A second run with the same value prints
// "already" and writes nothing. --dry-run runs every check and writes nothing.
//
// # LIMITS (stated, not hidden)
//
// The engine cannot prove that the evidence file is the committed database it
// claims to be; it records the file's sha256 in the audit row so a reviewer can
// compare it with `git show <commit>:<path> | sha256sum`. The evidence file is
// opened read-only with SQLite's immutable flag, which ignores a -wal file, so
// an evidence file with a non-empty -wal or -journal sidecar is refused.
//
// Provenance is otherwise asserted by the caller: an evidence file built by
// hand that names the item with the same type and title and records an earlier
// value inside the tracker's lifetime passes. The lower bound only rules out
// values before the tracker existed. Checking the evidence against a git blob
// (commit and path) is a tracked follow-up, not done here.
//
// --dry-run opens the live database the same way a real run does, which needs
// write access to it and its directory (SQLite may create a -journal or -wal
// file); a read-only database is refused as DB-UNREADABLE even in a dry run.
//
// The identity check compares the type and title VALUES of every evidence row
// of the id with the live row; the static guard test of the package
// (TestCON339_ItemsWriteSitesCarryCreatedAt) checks that every items INSERT
// names created_at as a column, not which value it inserts. The value is
// covered by the behaviour tests of close and sync md-to-db.
package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"
)

// storedTimeLayout is the format SQLite's datetime('now') writes and the
// tracker stores in items.created_at and item_history.created_at.
const storedTimeLayout = "2006-01-02 15:04:05"

var (
	storedTimeRE = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$`)
	sha256HexRE  = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

// rcaBeforeWriteHook is a TEST seam (round 2, CON-339): when non-nil it is
// called after every check has passed and before the write transaction
// begins, so a test can change the row through another connection and prove
// the compare-and-set UPDATE refuses. It is nil in production; no flag, input
// or environment variable sets it.
var rcaBeforeWriteHook func()

// rcaTrackerSlack is how far before the live tracker's earliest history row a
// restored value may lie (VALUE-BEFORE-TRACKER). `add` writes the items row and
// the Opened row in one transaction with two separate datetime('now')
// evaluations, so an item's created_at can precede the first history row of a
// tracker by the time between the two statements. 60 seconds is a declared
// margin, not a measured maximum.
const rcaTrackerSlack = 60 * time.Second

// parseStoredTime accepts exactly the stored format and a real calendar time.
func parseStoredTime(s string) (time.Time, bool) {
	if !storedTimeRE.MatchString(s) {
		return time.Time{}, false
	}
	t, err := time.Parse(storedTimeLayout, s)
	if err != nil || t.Format(storedTimeLayout) != s {
		return time.Time{}, false
	}
	return t, true
}

func runRestoreCreatedAt(args []string) {
	os.Exit(restoreCreatedAtCmd(args))
}

func rcaRefuse(code, format string, a ...any) int {
	fmt.Fprintf(os.Stderr, "restore-created-at: refused [%s]: %s\n", code, fmt.Sprintf(format, a...))
	return exitUsage
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// openEvidenceDB opens a SQLite file read-only and immutable: SQLite takes no
// lock, never writes, and creates no -wal / -shm / -journal file next to it.
func openEvidenceDB(abs string) (*sql.DB, error) {
	u := url.URL{Scheme: "file", Path: abs, RawQuery: "mode=ro&immutable=1"}
	return sql.Open("sqlite3", u.String())
}

func restoreCreatedAtCmd(args []string) int {
	fs := flag.NewFlagSet("restore-created-at", flag.ContinueOnError)
	dbPath := fs.String("db", "", "path to the workable-items SQLite DB (required)")
	id := fs.String("id", "", "item whose created_at is restored (required)")
	value := fs.String("value", "", "the created_at to restore, stored format YYYY-MM-DD HH:MM:SS (required)")
	evidence := fs.String("evidence", "", "path of a separate SQLite tracker database that records the value (required)")
	evidenceSHA := fs.String("evidence-sha256", "", "sha256 of the evidence file, lower-case hex (required)")
	reason := fs.String("reason", "", "why the value is restored; one line, recorded in the audit row (required)")
	evidenceID := fs.String("evidence-id", "", "the item's id in the evidence database (default: --id)")
	location := fs.String("location", "", "narrow to the row in Issues or Fixed")
	representation := fs.String("representation", "", "narrow to the section or table row")
	by := fs.String("by", "AI", "who performs the restore: AI or User")
	dryRun := fs.Bool("dry-run", false, "run every check and print the change; write nothing")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		return rcaRefuse("USAGE", "%v", err)
	}
	if fs.NArg() > 0 {
		return rcaRefuse("USAGE", "unexpected argument %q (every input is a flag)", fs.Arg(0))
	}
	for _, req := range []struct{ name, v string }{
		{"--db", *dbPath}, {"--id", *id}, {"--value", *value}, {"--evidence", *evidence},
		{"--evidence-sha256", *evidenceSHA}, {"--reason", *reason},
	} {
		if strings.TrimSpace(req.v) == "" {
			return rcaRefuse("USAGE", "%s is required", req.name)
		}
	}
	if strings.ContainsAny(*reason, "\r\n") {
		return rcaRefuse("USAGE", "--reason must be one line")
	}
	if *location != "" && *location != "Issues" && *location != "Fixed" {
		return rcaRefuse("USAGE", "--location must be Issues or Fixed, got %q", *location)
	}
	if *representation != "" && *representation != "section" && *representation != "table" {
		return rcaRefuse("USAGE", "--representation must be section or table, got %q", *representation)
	}
	if *by != "AI" && *by != "User" {
		return rcaRefuse("USAGE", "--by must be AI or User, got %q", *by)
	}
	evID := *evidenceID
	if evID == "" {
		evID = *id
	}

	newT, ok := parseStoredTime(*value)
	if !ok {
		return rcaRefuse("VALUE-FORMAT", "--value %q is not a real time in the stored format YYYY-MM-DD HH:MM:SS (UTC)", *value)
	}
	if !sha256HexRE.MatchString(*evidenceSHA) {
		return rcaRefuse("EVIDENCE-SHA256", "--evidence-sha256 %q is not 64 lower-case hex digits", *evidenceSHA)
	}

	// The live database must exist: openDB would create an empty one.
	liveAbs := resolveInvocationRelative(*dbPath)
	liveInfo, err := os.Stat(liveAbs)
	if err != nil || !liveInfo.Mode().IsRegular() {
		return rcaRefuse("DB-MISSING", "--db %q does not name an existing database file (resolved to %q)", *dbPath, liveAbs)
	}

	evRaw := strings.TrimSpace(*evidence)
	if err := checkEvidencePath(evRaw); err != nil {
		return rcaRefuse("EVIDENCE-UNRESOLVED", "%v", err)
	}
	evAbs := resolveInvocationRelative(evRaw)
	evInfo, err := os.Stat(evAbs)
	if err != nil || !evInfo.Mode().IsRegular() {
		return rcaRefuse("EVIDENCE-NOT-FILE", "evidence %q is not a regular file (resolved to %q)", evRaw, evAbs)
	}
	if os.SameFile(evInfo, liveInfo) {
		return rcaRefuse("EVIDENCE-IS-LIVE-DB", "evidence %q is the live database itself; name a separate copy of the committed database", evRaw)
	}
	gotSHA, err := fileSHA256(evAbs)
	if err != nil {
		return rcaRefuse("EVIDENCE-UNRESOLVED", "read evidence %q: %v", evAbs, err)
	}
	if gotSHA != *evidenceSHA {
		return rcaRefuse("EVIDENCE-SHA256", "evidence %q has sha256 %s, --evidence-sha256 says %s", evRaw, gotSHA, *evidenceSHA)
	}
	for _, side := range []string{"-wal", "-journal"} {
		if si, err := os.Stat(evAbs + side); err == nil && si.Size() > 0 {
			return rcaRefuse("EVIDENCE-WAL", "evidence %q has a non-empty %s file; the read-only, immutable open would ignore its content (checkpoint a copy first)", evRaw, side)
		}
	}

	db, err := openDB(*dbPath)
	if err != nil {
		return rcaRefuse("DB-UNREADABLE", "open %q: %v", *dbPath, err)
	}
	defer db.Close()

	// The one live row the restore targets.
	q := `SELECT current_location, COALESCE(representation,'section'), COALESCE(type,''), COALESCE(title,''), created_at
		FROM items WHERE atm_id=?`
	qa := []any{*id}
	if *location != "" {
		q += ` AND current_location=?`
		qa = append(qa, *location)
	}
	if *representation != "" {
		q += ` AND COALESCE(representation,'section')=?`
		qa = append(qa, *representation)
	}
	rows, err := db.Query(q, qa...)
	if err != nil {
		return rcaRefuse("DB-UNREADABLE", "query items: %v", err)
	}
	type liveRow struct{ loc, rep, typ, title, created string }
	var found []liveRow
	for rows.Next() {
		var r liveRow
		if err := rows.Scan(&r.loc, &r.rep, &r.typ, &r.title, &r.created); err != nil {
			rows.Close()
			return rcaRefuse("DB-UNREADABLE", "read items: %v", err)
		}
		found = append(found, r)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return rcaRefuse("DB-UNREADABLE", "read items: %v", err)
	}
	switch len(found) {
	case 0:
		return rcaRefuse("ITEM-NOT-FOUND", "no items row for %s (location %q, representation %q)", *id, *location, *representation)
	case 1:
	default:
		var where []string
		for _, r := range found {
			where = append(where, r.loc+"/"+r.rep)
		}
		return rcaRefuse("ITEM-AMBIGUOUS", "%s has %d rows (%s); narrow with --location and --representation", *id, len(found), strings.Join(where, ", "))
	}
	target := found[0]

	// The evidence database: the item exists there with the same type and
	// title, and records the value.
	edb, err := openEvidenceDB(evAbs)
	if err != nil {
		return rcaRefuse("EVIDENCE-NOT-DB", "open evidence %q: %v", evRaw, err)
	}
	defer edb.Close()
	type evRow struct{ typ, title, created string }
	var evRows []evRow
	erows, err := edb.Query(`SELECT COALESCE(type,''), COALESCE(title,''), COALESCE(created_at,'') FROM items WHERE atm_id=?`, evID)
	if err != nil {
		return rcaRefuse("EVIDENCE-NOT-DB", "evidence %q is not a readable workable-items database: %v", evRaw, err)
	}
	for erows.Next() {
		var r evRow
		if err := erows.Scan(&r.typ, &r.title, &r.created); err != nil {
			erows.Close()
			return rcaRefuse("EVIDENCE-NOT-DB", "read evidence items: %v", err)
		}
		evRows = append(evRows, r)
	}
	erows.Close()
	if err := erows.Err(); err != nil {
		return rcaRefuse("EVIDENCE-NOT-DB", "read evidence items: %v", err)
	}
	var opened []string
	hrows, err := edb.Query(`SELECT COALESCE(created_at,'') FROM item_history WHERE atm_id=? AND event_type='Opened' ORDER BY id`, evID)
	if err != nil {
		return rcaRefuse("EVIDENCE-NOT-DB", "evidence %q has no readable item_history: %v", evRaw, err)
	}
	for hrows.Next() {
		var s string
		if err := hrows.Scan(&s); err != nil {
			hrows.Close()
			return rcaRefuse("EVIDENCE-NOT-DB", "read evidence history: %v", err)
		}
		opened = append(opened, s)
	}
	hrows.Close()
	if err := hrows.Err(); err != nil {
		return rcaRefuse("EVIDENCE-NOT-DB", "read evidence history: %v", err)
	}
	if len(evRows) == 0 {
		return rcaRefuse("EVIDENCE-ITEM-MISSING", "evidence %q has no items row for %s (use --evidence-id when the id was re-minted)", evRaw, evID)
	}
	for _, r := range evRows {
		if r.typ != target.typ || r.title != target.title {
			return rcaRefuse("EVIDENCE-ITEM-MISMATCH", "evidence item %s is %s %q, the live item %s is %s %q",
				evID, r.typ, r.title, *id, target.typ, target.title)
		}
	}
	attest := ""
	var recorded []string
	for _, r := range evRows {
		recorded = append(recorded, "items.created_at="+r.created)
		if attest == "" && r.created == *value {
			attest = "items-row"
		}
	}
	for _, s := range opened {
		recorded = append(recorded, "Opened.created_at="+s)
		if attest == "" && s == *value {
			attest = "opened-event"
		}
	}
	if attest == "" {
		sort.Strings(recorded)
		return rcaRefuse("EVIDENCE-DOES-NOT-ATTEST", "evidence %q does not record %q for %s (it records: %s)", evRaw, *value, evID, strings.Join(recorded, "; "))
	}

	// The live item's own history bounds the value from above.
	hist, err := db.Query(`SELECT created_at FROM item_history WHERE atm_id=? ORDER BY id`, *id)
	if err != nil {
		return rcaRefuse("HISTORY-UNREADABLE", "query history of %s: %v", *id, err)
	}
	var first time.Time
	firstRaw, n := "", 0
	for hist.Next() {
		var s sql.NullString
		if err := hist.Scan(&s); err != nil {
			hist.Close()
			return rcaRefuse("HISTORY-UNREADABLE", "read history of %s: %v", *id, err)
		}
		ht, ok := parseStoredTime(s.String)
		if !ok {
			hist.Close()
			return rcaRefuse("HISTORY-UNREADABLE", "history of %s has created_at %q, not in the stored format; the first history time cannot be established", *id, s.String)
		}
		if n == 0 || ht.Before(first) {
			first, firstRaw = ht, s.String
		}
		n++
	}
	hist.Close()
	if err := hist.Err(); err != nil {
		return rcaRefuse("HISTORY-UNREADABLE", "read history of %s: %v", *id, err)
	}
	if n == 0 {
		return rcaRefuse("NO-HISTORY", "%s has no item_history row; the first history time cannot be established", *id)
	}
	if newT.After(first) {
		return rcaRefuse("VALUE-AFTER-FIRST-EVENT", "--value %q is later than the first history row of %s (%q); an item cannot be created after its first recorded event", *value, *id, firstRaw)
	}

	// Plausibility lower bound (round 2, F3): no item of this tracker can be
	// created long before the tracker recorded its first event. Only
	// well-formed rows count; ignoring a malformed row can only raise the bound
	// (refuse more), never lower it.
	var trackerFirst sql.NullString
	if err := db.QueryRow(`SELECT MIN(created_at) FROM item_history WHERE created_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]'`).Scan(&trackerFirst); err != nil {
		return rcaRefuse("HISTORY-UNREADABLE", "read the earliest history row of the tracker: %v", err)
	}
	trackerT, ok := parseStoredTime(trackerFirst.String)
	if !ok {
		return rcaRefuse("HISTORY-UNREADABLE", "the earliest history row of the tracker has created_at %q, not in the stored format", trackerFirst.String)
	}
	if newT.Before(trackerT.Add(-rcaTrackerSlack)) {
		return rcaRefuse("VALUE-BEFORE-TRACKER", "--value %q is earlier than the tracker's first history row (%q) by more than %s; no item of this tracker was created then", *value, trackerFirst.String, rcaTrackerSlack)
	}

	curT, ok := parseStoredTime(target.created)
	if !ok {
		return rcaRefuse("CURRENT-UNREADABLE", "the current created_at of %s is %q, not in the stored format", *id, target.created)
	}
	if target.created == *value {
		fmt.Printf("restore-created-at: %s [%s/%s] created_at is already %q; nothing written\n", *id, target.loc, target.rep, *value)
		return exitOK
	}
	if newT.After(curT) {
		return rcaRefuse("VALUE-LATER-THAN-CURRENT", "--value %q is later than the current created_at %q of %s; a restore only moves created_at back to a recorded earlier time", *value, target.created, *id)
	}

	audit := fmt.Sprintf("created-at-restored old=%q new=%q location=%s representation=%s evidence-sha256=%s attested-by=%s:%s reason=%s",
		target.created, *value, target.loc, target.rep, gotSHA, attest, evID, strings.TrimSpace(*reason))
	if *dryRun {
		fmt.Printf("restore-created-at: dry-run: would set %s [%s/%s] created_at %q -> %q (attested-by=%s:%s, evidence-sha256=%s); nothing written\n",
			*id, target.loc, target.rep, target.created, *value, attest, evID, gotSHA)
		return exitOK
	}

	if rcaBeforeWriteHook != nil {
		rcaBeforeWriteHook()
	}
	tx, err := db.Begin()
	if err != nil {
		return rcaRefuse("WRITE", "begin: %v", err)
	}
	defer tx.Rollback()
	res, err := tx.Exec(`UPDATE items SET created_at=?, last_modified=datetime('now')
		WHERE atm_id=? AND current_location=? AND COALESCE(representation,'section')=? AND created_at=?`,
		*value, *id, target.loc, target.rep, target.created)
	if err != nil {
		return rcaRefuse("WRITE", "update %s: %v", *id, err)
	}
	if n, err := res.RowsAffected(); err != nil || n != 1 {
		return rcaRefuse("CONCURRENT-CHANGE", "the row of %s changed while the restore ran (%d rows matched); nothing written", *id, n)
	}
	if err := recordHistory(tx, *id, "Updated", *by, audit, evRaw); err != nil {
		return rcaRefuse("WRITE", "audit history: %v", err)
	}
	if err := tx.Commit(); err != nil {
		return rcaRefuse("WRITE", "commit: %v", err)
	}
	fmt.Printf("restore-created-at: %s [%s/%s] created_at %q -> %q (attested-by=%s:%s, evidence-sha256=%s)\n",
		*id, target.loc, target.rep, target.created, *value, attest, evID, gotSHA)
	return exitOK
}
