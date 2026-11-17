// idgrammar_test.go — the one id grammar (idgrammar.go): add refuses an id the
// trackers cannot carry, every accepted id survives add → db-to-md → md-to-db,
// validate and md-to-db report a stored item the parser cannot read, and the
// grammar is not widened (CON-456; CON-435 review finding F3).
package main

import (
	"database/sql"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// idShapeCases is the class table: one row per id shape. accept is the
// verdict of the one grammar; every accepted id MUST round-trip.
var idShapeCases = []struct {
	name, id string
	accept   bool
}{
	{"canonical", "CON-123", true},
	{"canonical alnum suffix", "CON-14b", true},
	{"canonical one-hyphen placeholder", "CON-PENDINGengine", true},
	{"canonical four digits", "CON-0999", true},
	{"canonical very long suffix", "CON-" + strings.Repeat("9", 300), true},
	{"legacy letter code", "G01", true},
	{"legacy code with one part", "GS-2", true},
	{"legacy code word part", "BJ-SOURCE", true},
	{"two-letter key (legacy code form)", "AB-001", true},
	{"four-letter key (legacy code form)", "CATS-001", true},
	{"letters only", "CONX", true},
	{"second hyphen placeholder", "CON-PENDING-x2", false},
	{"second hyphen digits", "CON-033-001", false},
	{"lowercase key", "con-998", false},
	{"digits only", "123", false},
	{"empty suffix", "CON-", false},
	{"leading hyphen", "-001", false},
	{"unicode key", "ČON-001", false},
	{"unicode suffix", "CON-00ž", false},
	{"inner space", "CON 001", false},
	{"inner tab", "CON-9\t9", false},
	{"dot", "CON-1.2", false},
	{"hash", "CON-995#2", false},
	{"brackets", "[CON-994]", false},
	{"section sign", "§FL", false},
	{"parenthesis", "CON-993(x)", false},
	{"em dash", "CON—992", false},
	{"underscore", "CON_991", false},
	{"newline", "CON-1\nCON-2", false},
}

const idgDesc = "An id grammar test item, with a description long enough for the floor."

func idgAdd(t *testing.T, db string, extra ...string) int {
	t.Helper()
	args := append([]string{"Task", "Low", "--db", db, "--title", "idgrammar probe item", "--description", idgDesc}, extra...)
	return addCmd(args)
}

func idgCount(t *testing.T, dbPath, where string, args ...any) int {
	t.Helper()
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var n int
	if err := db.QueryRow(`SELECT COUNT(*) FROM items WHERE `+where, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// idgCycle runs db-to-md then md-to-db (into the same DB) and diff; it
// returns the md-to-db and diff exit codes.
func idgCycle(t *testing.T, db string) (mdToDB, diff int) {
	t.Helper()
	dir := filepath.Dir(db)
	is, fx := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
	if c := syncDBToMD([]string{"--db", db, "--out-issues", is, "--out-fixed", fx}); c != exitOK {
		t.Fatalf("db-to-md exited %d", c)
	}
	diff = diffCmd([]string{"--db", db, "--issues", is, "--fixed", fx})
	mdToDB = syncMDToDB([]string{"--db", db, "--issues", is, "--fixed", fx})
	return mdToDB, diff
}

// TestIDGrammar_ClassTable drives the real add and the real sync commands
// for every id shape: refused shapes write nothing; accepted shapes keep
// their exact id through db-to-md → md-to-db, diff clean, validate clean.
func TestIDGrammar_ClassTable(t *testing.T) {
	for _, c := range idShapeCases {
		c := c
		t.Run(c.name, func(t *testing.T) {
			db := newTestDB(t)
			if code := idgAdd(t, db, "--id", "WIT-001"); code != exitOK {
				t.Fatalf("seed add exited %d", code)
			}
			code := idgAdd(t, db, "--id", c.id)
			want := strings.TrimSpace(c.id)
			if !c.accept {
				if code == exitOK {
					t.Fatalf("add accepted %q; the grammar refuses it", c.id)
				}
				if n := idgCount(t, db, `atm_id <> 'WIT-001'`); n != 0 {
					t.Fatalf("refused add of %q still wrote %d row(s)", c.id, n)
				}
				return
			}
			if code != exitOK {
				t.Fatalf("add refused %q (exit %d); the grammar accepts it", c.id, code)
			}
			if rc, diff := idgCycle(t, db); rc != exitOK || diff != exitOK {
				t.Fatalf("%q: md-to-db exit %d, diff exit %d after db-to-md", c.id, rc, diff)
			}
			if n := idgCount(t, db, `atm_id = ?`, want); n != 1 {
				t.Fatalf("%q: %d row(s) with the exact id after the round trip, want 1", c.id, n)
			}
			if v := validateCmd([]string{"--db", db}); v != exitOK {
				t.Fatalf("%q: validate exited %d", c.id, v)
			}
		})
	}
}

// TestIDGrammar_PrefixAllocatedIDs: an id allocated from --prefix passes the
// same check as an explicit --id.
func TestIDGrammar_PrefixAllocatedIDs(t *testing.T) {
	for _, c := range []struct {
		prefix string
		accept bool
	}{{"CON", true}, {"AB", true}, {"CATS", true}, {"cat", false}, {"CON-X", false}, {"C.N", false}} {
		db := newTestDB(t)
		code := idgAdd(t, db, "--prefix", c.prefix)
		if (code == exitOK) != c.accept {
			t.Fatalf("--prefix %q: add exit %d, want accept=%v", c.prefix, code, c.accept)
		}
		if !c.accept {
			// CON-456 round 2 (review F8): a refusal is decided before the
			// database is opened, so no database file is created at all.
			if _, err := os.Stat(db); !os.IsNotExist(err) {
				t.Fatalf("--prefix %q refused but the database file exists (stat err=%v)", c.prefix, err)
			}
			continue
		}
		if rc, diff := idgCycle(t, db); rc != exitOK || diff != exitOK {
			t.Fatalf("--prefix %q: md-to-db %d diff %d", c.prefix, rc, diff)
		}
		if n := idgCount(t, db, `atm_id = ?`, c.prefix+"-001"); n != 1 {
			t.Fatalf("--prefix %q: id %s-001 not kept (%d)", c.prefix, c.prefix, n)
		}
	}
}

// TestIDGrammar_RefusalNamesIDAndGrammar: the refusal is precise.
func TestIDGrammar_RefusalNamesIDAndGrammar(t *testing.T) {
	err := checkIDRoundTrips("CON-PENDING-x2")
	if err == nil {
		t.Fatal("CON-PENDING-x2 accepted")
	}
	for _, want := range []string{`"CON-PENDING-x2"`, "second hyphen", "exactly three ASCII uppercase", "CON-PENDINGengine", "## CON-PENDING-x2. "} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("refusal %q lacks %q", err, want)
		}
	}
	if err := checkIDRoundTrips(""); err == nil {
		t.Fatal("empty id accepted by the grammar")
	}
	if err := checkIDRoundTrips("CON-PENDINGengine"); err != nil {
		t.Fatalf("control: CON-PENDINGengine refused: %v", err)
	}
}

// TestIDGrammar_RendererAgreesWithParser: the renderer writes the em-dash
// heading exactly for the ids the canonical parser reads (one pattern).
func TestIDGrammar_RendererAgreesWithParser(t *testing.T) {
	for _, id := range []string{"CON-123", "CON-14b", "CATS-001", "AB-001", "G01"} {
		body := renderItemBody(id, "t", "Task", "", idgDesc, "Queued", "", "")
		head := strings.SplitN(body, "\n", 2)[0]
		emDash := strings.HasPrefix(head, "## "+id+" — ")
		if emDash != (issueHeadingRe.FindStringSubmatch(head) != nil) {
			t.Fatalf("%q: renderer em-dash=%v but canonical parser match=%v (heading %q)", id, emDash, !emDash, head)
		}
		if emDash != canonicalIDRe.MatchString(id) {
			t.Fatalf("%q: em-dash=%v canonical=%v", id, emDash, canonicalIDRe.MatchString(id))
		}
	}
	if !strings.HasPrefix(renderItemBody("CATS-001", "t", "Task", "", idgDesc, "Queued", "", ""), "## CATS-001. t\n") {
		t.Fatal("CATS-001 must render in the legacy dot form the parser reads")
	}
}

// idgPlantRow inserts an items row + segment directly, the way an engine
// before this fix (or a hand edit) could leave it.
func idgPlantRow(t *testing.T, dbPath, id, location, body string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(`INSERT INTO items (atm_id, type, status, title, description, current_location, body_md)
		VALUES (?,?,?,?,?,?,?)`, id, "Task", "Queued", "planted", idgDesc, location, body); err != nil {
		t.Fatal(err)
	}
	if err := appendSegment(tx, location, id); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
}

func idgPlantedDB(t *testing.T, location string) string {
	t.Helper()
	db := newTestDB(t)
	if code := idgAdd(t, db, "--id", "WIT-001"); code != exitOK {
		t.Fatalf("seed add exited %d", code)
	}
	status := "Queued"
	if location == "Fixed" {
		status = "Fixed (→ Fixed.md)"
	}
	body := "## CON-PENDING-x2. planted\n\n**Status:** " + status + "\n**Type:** Task\n\n" + idgDesc + "\n\n"
	idgPlantRow(t, db, "CON-PENDING-x2", location, body)
	return db
}

// TestIDGrammar_ValidateReportsUnreadableStoredBody: golden-bad planted row
// is a violation; the seed row alone is clean (negative control).
func TestIDGrammar_ValidateReportsUnreadableStoredBody(t *testing.T) {
	clean := newTestDB(t)
	if code := idgAdd(t, clean, "--id", "WIT-001"); code != exitOK {
		t.Fatal("seed")
	}
	if v := validateCmd([]string{"--db", clean}); v != exitOK {
		t.Fatalf("negative control: clean DB validate exit %d", v)
	}
	for _, loc := range []string{"Issues", "Fixed"} {
		if v := validateCmd([]string{"--db", idgPlantedDB(t, loc)}); v == exitOK {
			t.Fatalf("%s: validate passed a stored body the parser cannot read", loc)
		}
	}
}

// TestIDGrammar_MDToDBRefusesSilentDrop: md-to-db refuses (nothing written)
// when a DB item's heading is still in the Markdown but unreadable; a real
// deletion (heading removed from the Markdown) is still applied.
func TestIDGrammar_MDToDBRefusesSilentDrop(t *testing.T) {
	for _, loc := range []string{"Issues", "Fixed"} {
		db := idgPlantedDB(t, loc)
		dir := filepath.Dir(db)
		is, fx := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
		if c := syncDBToMD([]string{"--db", db, "--out-issues", is, "--out-fixed", fx}); c != exitOK {
			t.Fatalf("db-to-md %d", c)
		}
		if c := syncMDToDB([]string{"--db", db, "--issues", is, "--fixed", fx}); c == exitOK {
			t.Fatalf("%s: md-to-db accepted a document that silently drops CON-PENDING-x2", loc)
		}
		if n := idgCount(t, db, `atm_id = 'CON-PENDING-x2'`); n != 1 {
			t.Fatalf("%s: refused md-to-db still changed the DB (%d rows)", loc, n)
		}
		// Real deletion: remove the item's text from the Markdown.
		path := is
		if loc == "Fixed" {
			path = fx
		}
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		cut := strings.Replace(string(raw), "## CON-PENDING-x2. planted\n", "", 1)
		if cut == string(raw) {
			t.Fatalf("%s: planted heading not rendered", loc)
		}
		if err := os.WriteFile(path, []byte(cut), 0o644); err != nil {
			t.Fatal(err)
		}
		if c := syncMDToDB([]string{"--db", db, "--issues", is, "--fixed", fx}); c != exitOK {
			t.Fatalf("%s: md-to-db refused a real deletion (exit %d)", loc, c)
		}
		if n := idgCount(t, db, `atm_id = 'CON-PENDING-x2'`); n != 0 {
			t.Fatalf("%s: deleted item still present", loc)
		}
	}
}

// TestIDGrammar_DedupCounterIsNotAViolation: two `## GS-2.` items parse to
// GS-2 and GS-2#1; neither is a validate violation nor blocks md-to-db.
func TestIDGrammar_DedupCounterIsNotAViolation(t *testing.T) {
	db := newTestDB(t)
	dir := filepath.Dir(db)
	is, fx := filepath.Join(dir, "Issues.md"), filepath.Join(dir, "Fixed.md")
	block := "## GS-2. twin\n\n**Status:** Queued\n**Type:** Task\n\n" + idgDesc + "\n\n"
	if err := os.WriteFile(is, []byte("# Issues\n\n"+block+block), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fx, []byte("# Fixed\n\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if c := syncMDToDB([]string{"--db", db, "--issues", is, "--fixed", fx}); c != exitOK {
		t.Fatalf("md-to-db %d", c)
	}
	if n := idgCount(t, db, `atm_id IN ('GS-2','GS-2#1')`); n != 2 {
		t.Fatalf("dedup fixture: %d rows, want 2", n)
	}
	if v := validateCmd([]string{"--db", db}); v != exitOK {
		t.Fatalf("validate flagged the #N dedup counter (exit %d)", v)
	}
	if c := syncMDToDB([]string{"--db", db, "--issues", is, "--fixed", fx}); c != exitOK {
		t.Fatalf("second md-to-db refused the dedup ids (exit %d)", c)
	}
}

// TestIDGrammar_KnownDefect_CanonicalParentChildID pins, as a known and
// tracked defect, that a sub-task child of a canonical parent (ATM-025-001,
// subtask.go; not reachable from the CLI dispatch) does not round-trip, and
// that validate now reports it instead of passing it.
func TestIDGrammar_KnownDefect_CanonicalParentChildID(t *testing.T) {
	if err := checkIDRoundTrips("ATM-025-001"); err == nil {
		t.Fatal("ATM-025-001 now round-trips: the child-id defect is fixed — update this pin and the tracker item")
	}
	db := newTestDBWithParent(t, "ATM-025")
	mustOK(t, subtaskAddCmd([]string{"ATM-025", "--db", db, "--session", "s"}))
	if v := validateCmd([]string{"--db", db}); v == exitOK {
		t.Fatal("validate passed a sub-task child the parser cannot read back")
	}
}

// TestIDGrammar_IntakeFollowsRenderableIDs: duplicate-of chains follow any
// renderable id (canonical or legacy code) and stop at a non-id.
func TestIDGrammar_IntakeFollowsRenderableIDs(t *testing.T) {
	dbPath := newTestDB(t)
	if code := idgAdd(t, dbPath, "--id", "WIT-001"); code != exitOK {
		t.Fatal("seed")
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	for _, r := range [][2]string{{"WIT-001", "G01"}, {"G01", "CATS-001"}, {"CATS-001", "not an id"}} {
		if _, err := db.Exec(`INSERT INTO obsolete_details(atm_id,since,reason,superseding_item,triple_check_evidence)
			VALUES (?,?,?,?,?)`, r[0], "2026-11-16", "duplicate-of", r[1], "e"); err != nil {
			t.Fatal(err)
		}
	}
	if got := followDuplicateChain(db, "WIT-001"); got != "CATS-001" {
		t.Fatalf("chain head %q, want CATS-001", got)
	}
}

// TestIDGrammar_ExistingTrackerIDsAccepted is the golden-FALSE: every id in
// this repository's tracker passes the grammar, and every stored section
// body reads back (skipped when the tracker is not reachable).
func TestIDGrammar_ExistingTrackerIDsAccepted(t *testing.T) {
	path, _ := filepath.Abs(filepath.Join("..", "..", "..", "..", "docs", "workable_items.db"))
	if _, err := os.Stat(path); err != nil {
		t.Skipf("tracker not reachable at %s", path)
	}
	db, err := sql.Open("sqlite3", "file:"+path+"?mode=ro")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	items, err := loadItems(db)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) < 100 {
		t.Fatalf("control: only %d items read from %s", len(items), path)
	}
	for _, it := range items {
		if err := checkIDRoundTrips(baseItemID(it.AtmID)); err != nil {
			t.Errorf("existing id refused: %v", err)
		}
		for _, pr := range roundTripProblems(it) {
			t.Errorf("existing item: %s", pr)
		}
	}
}

// TestIDGrammar_Property: generated ids — accepted ⇒ round-trips inside a
// real two-item document through the parser AND through add + sync.
func TestIDGrammar_Property(t *testing.T) {
	rng := rand.New(rand.NewSource(20261116))
	alphabet := []rune("ABCXYZabcz019-.#_ §ž\t")
	accepted := 0
	for i := 0; i < 4000; i++ {
		n := 1 + rng.Intn(12)
		var b strings.Builder
		for j := 0; j < n; j++ {
			b.WriteRune(alphabet[rng.Intn(len(alphabet))])
		}
		id := b.String()
		if i%3 == 0 { // bias toward key-shaped ids
			id = "CON-" + id
		}
		if checkIDRoundTrips(id) != nil {
			continue
		}
		accepted++
		doc := "# Issues\n\nprose\n\n" + renderItemBody(id, "p", "Task", "", idgDesc, "Queued", "", "") +
			renderItemBody("WIT-001", "q", "Task", "", idgDesc, "Queued", "", "")
		items, segs := parseIssues(doc)
		if len(items) != 2 || items[0].AtmID != id {
			t.Fatalf("accepted id %q not read back in a document (%d items)", id, len(items))
		}
		var re strings.Builder
		for _, s := range segs {
			if s.Kind == "raw" {
				re.WriteString(s.Raw)
			} else {
				for _, it := range items {
					if it.AtmID == s.AtmID {
						re.WriteString(it.BodyMD)
					}
				}
			}
		}
		if re.String() != doc {
			t.Fatalf("accepted id %q: document not byte-identical after parse", id)
		}
		if accepted%40 == 1 { // a sample also through the real CLI path
			db := newTestDB(t)
			if code := idgAdd(t, db, "--id", id); code != exitOK {
				t.Fatalf("add refused accepted id %q", id)
			}
			if rc, diff := idgCycle(t, db); rc != exitOK || diff != exitOK {
				t.Fatalf("%q: md-to-db %d diff %d", id, rc, diff)
			}
			if c := idgCount(t, db, `atm_id = ?`, strings.TrimSpace(id)); c != 1 {
				t.Fatalf("%q lost in the CLI round trip", id)
			}
		}
	}
	if accepted < 50 {
		t.Fatalf("control: only %d generated ids accepted — the generator does not exercise the accept side", accepted)
	}
	t.Logf("property: %d of 4000 generated ids accepted, all round-tripped", accepted)
}

// TestIDGrammar_CanonicalIDsUseEmDashHeading: every canonical-shape id
// (alnum suffix included) is written in the canonical em-dash heading and
// read by the canonical parser, never demoted to the legacy dot form.
func TestIDGrammar_CanonicalIDsUseEmDashHeading(t *testing.T) {
	for _, id := range []string{"CON-123", "CON-14b", "CON-PENDINGengine", "CON-0999", "HXC-014b"} {
		head := strings.SplitN(renderItemBody(id, "t", "Task", "", idgDesc, "Queued", "", ""), "\n", 2)[0]
		if head != "## "+id+" — t" {
			t.Fatalf("%q rendered as %q, want the canonical em-dash heading", id, head)
		}
		if m := issueHeadingRe.FindStringSubmatch(head); m == nil || m[1] != id {
			t.Fatalf("%q: canonical parser does not read %q", id, head)
		}
	}
}

// TestIDGrammar_EmptyBodyNotJudged: an empty stored body is the business of
// repair-bodies, not of the round-trip check (no false positive).
func TestIDGrammar_EmptyBodyNotJudged(t *testing.T) {
	for _, loc := range []string{"Issues", "Fixed"} {
		it := item{AtmID: "CON-1", Title: "t", Type: "Task", Status: "Queued",
			CurrentLocation: loc, BodyMD: "", Representation: "section"}
		if p := roundTripProblems(it); p != nil {
			t.Fatalf("%s: empty body judged: %v", loc, p)
		}
		it.BodyMD = "## CON-1 — t\n\n**Status:** Queued\n"
		if p := roundTripProblems(it); p != nil {
			t.Fatalf("%s: control body judged: %v", loc, p)
		}
		it.AtmID = "CON-1-2"
		it.BodyMD = "## CON-1-2. t\n\n**Status:** Queued\n"
		if p := roundTripProblems(it); p == nil {
			t.Fatalf("%s: golden-bad body not judged", loc)
		}
	}
}

// TestIDGrammar_RoundTripMatchesTheExactID (review RM04): a stored GS-7 whose
// Markdown reads back as GS-72 (a bracket id in the title) is a violation; a
// prefix match of the ids would pass it. Control: the same item with an
// ordinary title is clean.
func TestIDGrammar_RoundTripMatchesTheExactID(t *testing.T) {
	mk := func(title string) item {
		return item{AtmID: "GS-7", Title: title, Type: "Task", Status: "Queued",
			CurrentLocation: "Issues", Representation: "section",
			BodyMD: renderItemBody("GS-7", title, "Task", "", idgDesc, "Queued", "", "")}
	}
	if p := roundTripProblems(mk("ordinary probe title")); len(p) != 0 {
		t.Fatalf("control: an ordinary GS-7 item reports %v", p)
	}
	p := roundTripProblems(mk("[GS-72] probe title"))
	if len(p) == 0 || !strings.Contains(strings.Join(p, "; "), `"GS-72"`) {
		t.Fatalf("GS-7 read back as GS-72 is not reported by its id: %v", p)
	}
}

// TestIDGrammar_RoundTripComparesRepresentation (review F4, the M13 input): a
// Fixed SECTION item whose heading the parser cannot read and whose body holds
// a pipe row with the same id reads back as a TABLE item; that is a violation.
// Control: a real Fixed table row is clean, which also fails a gate that would
// read Fixed bodies with the Issues parser (the M13 mutant).
func TestIDGrammar_RoundTripComparesRepresentation(t *testing.T) {
	row := "| 2026-01-01 | CON-900 thing | Bug | Fixed | R1 | abc1234 | docs/x.md |\n"
	section := item{AtmID: "CON-900", Title: "", Type: "Bug", Status: "Fixed (→ Fixed.md)",
		CurrentLocation: "Fixed", Representation: "section", BodyMD: "## CON-900 —\n\n" + row}
	if p := roundTripProblems(section); len(p) == 0 {
		t.Fatal("a Fixed section item that reads back as a table row is not reported")
	}
	items, _ := parseFixed(row)
	if len(items) != 1 || items[0].repOrDefault() != "table" {
		t.Fatalf("fixture: the pipe row parses as %d item(s)", len(items))
	}
	table := items[0]
	table.CurrentLocation = "Fixed"
	if p := roundTripProblems(table); len(p) != 0 {
		t.Fatalf("control: a real Fixed table row reports %v", p)
	}
	// Only the representation differs: a section item whose body is a pipe
	// row and whose fields are what the row carries reads back as one item, in
	// one segment, with the same body and fields, but as a table row. The row
	// has an empty Type cell, so the section render inserts no `**Type:**`
	// line (alignMetaLines skips an empty Type column) and the body stays the
	// bare row; with a Type the render adds a line and the segment-count check
	// fires first, which would leave the representation compare unexercised.
	bareRow := "| 2026-01-01 | CON-901 thing |  | Fixed | R1 | abc1234 | docs/x.md |\n"
	bareItems, _ := parseFixed(bareRow)
	if len(bareItems) != 1 || bareItems[0].repOrDefault() != "table" {
		t.Fatalf("fixture: the empty-Type pipe row parses as %d item(s) %+v", len(bareItems), bareItems)
	}
	bare := bareItems[0]
	bare.CurrentLocation = "Fixed"
	if p := roundTripProblems(bare); len(p) != 0 {
		t.Fatalf("control: the empty-Type Fixed table row reports %v", p)
	}
	bare.Representation = "section"
	p := roundTripProblems(bare)
	if len(p) != 1 || !strings.Contains(p[0], "reads back as a table item") {
		t.Fatalf("a section item read back as a table row reports %v, want the representation alone", p)
	}
}
