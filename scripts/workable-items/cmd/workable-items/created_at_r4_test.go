// created_at_r4_test.go — CON-339 round 4: the round-3 independent review
// (NO-GO) showed that round 3 closed six named mutants but not their CLASS:
// reviewer mutant R3G03 widened the Opened-row attestation `s == *value` to
// `s <= *value` and survived with a real tracker write. Round 4 closes the
// class of comparison and ordering operators in the attestation and
// validation paths of restore-created-at:
//
//	(a) a census (TestRestoreCreatedAtR4_ComparisonCensus) enumerates every
//	    comparison (==, !=, <, <=, >, >=), every time ordering call (Before,
//	    After, Equal, Compare) and every switch on a value in
//	    restoreCreatedAtCmd and parseStoredTime from the parsed source, and
//	    requires it to equal a declared table naming, for each one, the tests
//	    that cover it; the instrument is control-needled on a synthetic source
//	    that holds every operator kind, so a zero is never read as "none";
//	(b) a boundary table (TestRestoreCreatedAtR4_AttestationBoundaries) for
//	    both attestation sources: equal, one second before, one second after,
//	    strictly between two recorded values, outside below, outside above;
//	(c) a boundary table (TestRestoreCreatedAtR4_ValidationBoundaries) for
//	    every time bound: first history row, earliest-row selection, tracker
//	    lower bound, already-equal, later-than-current;
//	(d) the reviewer's minor survivors: a carriage return in --reason (R3G10)
//	    and a 1 to 8 byte -wal / -journal sidecar (R3G06);
//	(e) a legacy row whose representation is NULL (R3G09, which the review
//	    called equivalent; it is not: openDB keeps a NOT NULL-less column).
//
// The census reads the source text, so it fails on any change to a listed
// comparison whether or not behaviour changes. The mutation runner therefore
// names it in CENSUS_TESTS and reports a mutant failed by it alone as
// CENSUS-ONLY, never as KILLED. Out of the census: checkEvidencePath
// (evidence.go, shared with other commands) and the SQL predicates; their
// comparisons are covered by the round-2 and round-3 tests, not by this table.
//
// Every case runs as a real run and as a dry run. Evidence class: gate-logic /
// unit (section 11.4.289); real command, real SQLite files under t.TempDir();
// no mocks.
package main

import (
	"bytes"
	"fmt"
	"go/ast"
	"go/parser"
	"go/printer"
	"go/token"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// --- (a) the census ---------------------------------------------------------

// r4CensusFuncs are the functions whose comparisons form the attestation and
// validation paths of restore-created-at. checkEvidencePath (evidence.go) is
// shared engine code with its own tests and is outside this census.
var r4CensusFuncs = map[string]bool{"restoreCreatedAtCmd": true, "parseStoredTime": true}

// r4Census returns every comparison of the named functions in src, rendered
// as source text, with its count.
func r4Census(t *testing.T, filename string, src []byte, funcs map[string]bool) map[string]int {
	t.Helper()
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, filename, src, 0)
	if err != nil {
		t.Fatalf("parse %s: %v", filename, err)
	}
	render := func(n ast.Node) string {
		var b bytes.Buffer
		if err := printer.Fprint(&b, fset, n); err != nil {
			t.Fatal(err)
		}
		return strings.Join(strings.Fields(b.String()), " ")
	}
	got := map[string]int{}
	for _, d := range file.Decls {
		fd, ok := d.(*ast.FuncDecl)
		if !ok || !funcs[fd.Name.Name] {
			continue
		}
		ast.Inspect(fd.Body, func(n ast.Node) bool {
			switch x := n.(type) {
			case *ast.BinaryExpr:
				switch x.Op {
				case token.EQL, token.NEQ, token.LSS, token.LEQ, token.GTR, token.GEQ:
					got[fd.Name.Name+": "+render(x)]++
				}
			case *ast.CallExpr:
				if sel, ok := x.Fun.(*ast.SelectorExpr); ok {
					switch sel.Sel.Name {
					case "Before", "After", "Equal", "Compare":
						got[fd.Name.Name+": "+render(x)]++
					}
				}
			case *ast.SwitchStmt:
				if x.Tag != nil {
					got[fd.Name.Name+": switch "+render(x.Tag)]++
				}
			}
			return true
		})
	}
	return got
}

// r4CensusEntry declares one comparison: how often it occurs, its class, and
// the tests that fail when it is changed.
type r4CensusEntry struct {
	n     int
	class string
	tests []string
}

// r4CensusTable is the declared inventory (round 4). A new comparison in the
// two functions fails TestRestoreCreatedAtR4_ComparisonCensus until it is
// added here with its covering tests.
var r4CensusTable = map[string]r4CensusEntry{
	// value ordering and equality (the R3G03 class)
	`restoreCreatedAtCmd: r.created == *value`: {1, "attestation: items row equals the value", []string{"TestRestoreCreatedAtR4_AttestationBoundaries"}},
	`restoreCreatedAtCmd: s == *value`:         {1, "attestation: Opened row equals the value", []string{"TestRestoreCreatedAtR4_AttestationBoundaries"}},
	`restoreCreatedAtCmd: attest == ""`: {3, "attestation: first attesting row wins / none attests",
		[]string{"TestRestoreCreatedAtR2_ItemsRowAttestationPreferred", "TestRestoreCreatedAtR4_AttestationBoundaries"}},
	`restoreCreatedAtCmd: newT.After(first)`: {1, "bound: not after the first history row", []string{"TestRestoreCreatedAtR4_ValidationBoundaries", "TestRestoreCreatedAtR2_FirstEventBoundary"}},
	`restoreCreatedAtCmd: n == 0`:            {2, "bound: first row seen / no history", []string{"TestRestoreCreatedAtR4_ValidationBoundaries", "TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: ht.Before(first)`:  {1, "bound: the earliest history row is the first", []string{"TestRestoreCreatedAtR4_ValidationBoundaries", "TestRestoreCreatedAtR2_LateHistoryRowDoesNotBound"}},
	`restoreCreatedAtCmd: newT.Before(trackerT.Add(-rcaTrackerSlack))`: {1, "bound: not before the tracker's first row minus the slack",
		[]string{"TestRestoreCreatedAtR4_ValidationBoundaries", "TestRestoreCreatedAtR3_TrackerBoundBothAttestations"}},
	`restoreCreatedAtCmd: target.created == *value`: {1, "already: the value equals the current one", []string{"TestRestoreCreatedAtR4_ValidationBoundaries", "TestRestoreCreatedAt_IdempotentAndDryRun"}},
	`restoreCreatedAtCmd: newT.After(curT)`:         {1, "bound: not later than the current value", []string{"TestRestoreCreatedAtR4_ValidationBoundaries", "TestRestoreCreatedAtR2_CurrentValueBoundary"}},
	`restoreCreatedAtCmd: si.Size() > 0`:            {1, "sidecar: a non-empty -wal / -journal is refused", []string{"TestRestoreCreatedAtR4_SidecarSizeBoundary", "TestRestoreCreatedAtR2_JournalSidecarRefused"}},
	`restoreCreatedAtCmd: err == nil`:               {1, "sidecar: the sidecar exists", []string{"TestRestoreCreatedAtR4_SidecarSizeBoundary"}},
	// identity of the evidence item
	`restoreCreatedAtCmd: r.typ != target.typ`:     {1, "identity: type", []string{"TestRestoreCreatedAtR3_IdentityNearMiss", "TestRestoreCreatedAtR2_EvidenceTypeMustMatch"}},
	`restoreCreatedAtCmd: r.title != target.title`: {1, "identity: title", []string{"TestRestoreCreatedAtR3_IdentityNearMiss", "TestRestoreCreatedAtR2_EvidenceTitleMustMatch"}},
	`restoreCreatedAtCmd: len(evRows) == 0`:        {1, "identity: the evidence has the item", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: switch len(found)`:       {1, "target: exactly one live row", []string{"TestRestoreCreatedAt_AmbiguousRowNeedsNarrowing", "TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	// provenance of the evidence file
	`restoreCreatedAtCmd: gotSHA != *evidenceSHA`: {1, "provenance: sha256 of the evidence file", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun", "TestRestoreCreatedAtR2_AlreadyNeedsValidEvidence"}},
	// usage
	`restoreCreatedAtCmd: fs.NArg() > 0`:                  {1, "usage: no positional argument", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun", "TestRestoreCreatedAt_Refusals"}},
	`restoreCreatedAtCmd: strings.TrimSpace(req.v) == ""`: {1, "usage: required flags", []string{"TestRestoreCreatedAt_Refusals", "TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: *location != ""`:                {2, "usage: --location / narrowing", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun", "TestRestoreCreatedAtR2_LocationNarrowsTheTarget"}},
	`restoreCreatedAtCmd: *location != "Issues"`:          {1, "usage: --location", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: *location != "Fixed"`:           {1, "usage: --location", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: *representation != ""`:          {2, "usage: --representation / narrowing", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun", "TestRestoreCreatedAtR2_CASNamesTheRepresentation"}},
	`restoreCreatedAtCmd: *representation != "section"`:   {1, "usage: --representation", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: *representation != "table"`:     {1, "usage: --representation", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: *by != "AI"`:                    {1, "usage: --by", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: *by != "User"`:                  {1, "usage: --by", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun"}},
	`restoreCreatedAtCmd: evID == ""`:                     {1, "usage: --evidence-id defaults to --id", []string{"TestRestoreCreatedAt_EvidenceIDMapsAReMintedItem"}},
	// the compare-and-set write
	`restoreCreatedAtCmd: n != 1`:                    {1, "write: exactly one row changed", []string{"TestRestoreCreatedAtR2_ConcurrentChangeIsRefused"}},
	`restoreCreatedAtCmd: rcaBeforeWriteHook != nil`: {1, "test seam: nil in production", []string{"TestRestoreCreatedAtR3_WriteCodesOnlyInARealRun"}},
	// error propagation: each err != nil turns a failing call into a refusal.
	// The reachable ones are cases of the round-3 refusal table (DB-UNREADABLE,
	// EVIDENCE-NOT-DB, HISTORY-UNREADABLE, WRITE); a Scan or Close error on a
	// row SQLite already returned is not deterministically reachable and is
	// not claimed covered.
	`restoreCreatedAtCmd: err != nil`: {25, "error propagation", []string{"TestRestoreCreatedAtR3_EveryRefusalSameInDryRun", "TestRestoreCreatedAtR2_DBUnreadable", "TestRestoreCreatedAtR2_AuditFailureRollsBack"}},
	// parseStoredTime
	`parseStoredTime: err != nil`:                      {1, "value format: time.Parse", []string{"TestRestoreCreatedAtR2_NonCanonicalValues"}},
	`parseStoredTime: t.Format(storedTimeLayout) != s`: {1, "value format: round trip (RR09 equivalent)", []string{"TestRestoreCreatedAtR2_NonCanonicalValues"}},
}

// r4TestNames returns every Test function declared in the package's test files.
func r4TestNames(t *testing.T) map[string]bool {
	t.Helper()
	files, err := filepath.Glob("*_test.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("glob test files: %v (%d files)", err, len(files))
	}
	names := map[string]bool{}
	fset := token.NewFileSet()
	for _, fn := range files {
		f, err := parser.ParseFile(fset, fn, nil, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", fn, err)
		}
		for _, d := range f.Decls {
			if fd, ok := d.(*ast.FuncDecl); ok && strings.HasPrefix(fd.Name.Name, "Test") {
				names[fd.Name.Name] = true
			}
		}
	}
	return names
}

// TestRestoreCreatedAtR4_ComparisonCensus: the census of the parsed source
// equals the declared table, every covering test exists, and the instrument
// sees every operator kind on a synthetic source (control needle).
func TestRestoreCreatedAtR4_ComparisonCensus(t *testing.T) {
	// Control needle: a synthetic function holding every operator kind the
	// census claims to see, plus a function outside the scope.
	needle := []byte(`package p
func restoreCreatedAtCmd() {
	if a == b || a != b || a < b || a <= b || a > b || a >= b {}
	if x.Before(y) || x.After(y) || x.Equal(y) || x.Compare(y) == 0 {}
	switch len(v) {}
}
func outside() { if q <= r {} }
`)
	nc := r4Census(t, "needle.go", needle, r4CensusFuncs)
	for _, want := range []string{
		"restoreCreatedAtCmd: a == b", "restoreCreatedAtCmd: a != b", "restoreCreatedAtCmd: a < b",
		"restoreCreatedAtCmd: a <= b", "restoreCreatedAtCmd: a > b", "restoreCreatedAtCmd: a >= b",
		"restoreCreatedAtCmd: x.Before(y)", "restoreCreatedAtCmd: x.After(y)", "restoreCreatedAtCmd: x.Equal(y)",
		"restoreCreatedAtCmd: x.Compare(y)", "restoreCreatedAtCmd: x.Compare(y) == 0", "restoreCreatedAtCmd: switch len(v)",
	} {
		if nc[want] != 1 {
			t.Fatalf("control needle: the census does not see %q (got %v)", want, nc)
		}
	}
	if _, ok := nc["outside: q <= r"]; ok {
		t.Fatalf("control needle: the census reads a function outside its scope")
	}

	src, err := os.ReadFile("restore_created_at.go")
	if err != nil {
		t.Fatal(err)
	}
	got := r4Census(t, "restore_created_at.go", src, r4CensusFuncs)
	// Positive control on the real source: the R3G03 guard is seen, its
	// mutant form is not.
	if got[`restoreCreatedAtCmd: s == *value`] != 1 {
		t.Fatalf("positive control: the census does not see the Opened-row attestation `s == *value`")
	}
	if _, ok := got[`restoreCreatedAtCmd: s <= *value`]; ok {
		t.Fatalf("negative control: the census reports the mutant form `s <= *value` in the unmutated source")
	}
	want := map[string]int{}
	for k, e := range r4CensusTable {
		if e.n > 0 {
			want[k] = e.n
		}
	}
	var keys []string
	for k := range got {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	total := 0
	for _, k := range keys {
		total += got[k]
		e, ok := r4CensusTable[k]
		if !ok || e.n == 0 {
			t.Errorf("comparison %q (%d) is not in the declared table: add it with its covering tests", k, got[k])
			continue
		}
		if e.n != got[k] {
			t.Errorf("comparison %q occurs %d times, the table declares %d", k, got[k], e.n)
		}
		t.Logf("CENSUS %2d x %s | %s | %s", got[k], k, e.class, strings.Join(e.tests, ","))
	}
	for k, n := range want {
		if got[k] != n {
			t.Errorf("declared comparison %q (%d) is not in the source (%d)", k, n, got[k])
		}
	}
	names := r4TestNames(t)
	for k, e := range r4CensusTable {
		if e.n == 0 {
			continue
		}
		if len(e.tests) == 0 {
			t.Errorf("comparison %q names no covering test", k)
		}
		for _, tn := range e.tests {
			if !names[tn] {
				t.Errorf("comparison %q names test %s, which does not exist", k, tn)
			}
		}
	}
	t.Logf("CENSUS total %d comparisons in %d distinct forms", total, len(keys))
}

// --- shared helpers of (b) and (c) ---------------------------------------------

// r4Want is the expected outcome of one case: "accept:<attestation>",
// "already", or "refuse:<CODE>".
type r4Want string

// r4Check runs one case in both modes and asserts the outcome; for a refusal
// or a dry run the database must be unchanged, a real accepted run must write
// exactly the value.
func r4Check(t *testing.T, mk func(t *testing.T) (rcaFix, []string), value string, want r4Want) {
	t.Helper()
	for _, mode := range []string{"real", "dry-run"} {
		mode := mode
		t.Run(mode, func(t *testing.T) {
			f, extra := mk(t)
			extra = append(extra, "--value", value)
			if mode == "dry-run" {
				extra = append(extra, "--dry-run")
			}
			before := r3Snapshot(t, f)
			rc, out, errOut := r3Run(t, f.args(extra...))
			after := r3Snapshot(t, f)
			got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`)
			switch {
			case strings.HasPrefix(string(want), "refuse:"):
				code := strings.TrimPrefix(string(want), "refuse:")
				if rc == exitOK || !strings.Contains(errOut, "refused ["+code+"]") {
					t.Fatalf("exit %d stdout %q stderr %q; want refused [%s]", rc, out, errOut, code)
				}
				if after != before {
					t.Fatalf("a refused run changed the database: %s -> %s", before, after)
				}
			case want == "already":
				if rc != exitOK || !strings.Contains(out, "already") || after != before {
					t.Fatalf("exit %d stdout %q stderr %q changed=%v; want 'already', nothing written", rc, out, errOut, after != before)
				}
			case strings.HasPrefix(string(want), "accept:"):
				att := strings.TrimPrefix(string(want), "accept:")
				if rc != exitOK {
					t.Fatalf("refused: exit %d stderr %q; want accepted (attested-by=%s)", rc, errOut, att)
				}
				if !strings.Contains(out, "attested-by="+att+":WIT-010") {
					t.Fatalf("stdout %q does not name attested-by=%s", out, att)
				}
				if mode == "dry-run" {
					if after != before {
						t.Fatalf("a dry run changed the database")
					}
				} else if got != value {
					t.Fatalf("real run: created_at %q, want %q", got, value)
				}
			default:
				t.Fatalf("bad want %q", want)
			}
		})
	}
}

// --- (b) attestation boundaries ---------------------------------------------

// TestRestoreCreatedAtR4_AttestationBoundaries (kills R3G03 and its siblings
// on both attestation loops: ==, <=, <, >=, >, != each fail at least one
// cell). rcaFixture bounds: live first event 10:00:00, tracker bound 09:59:00,
// current value 2026-01-05 12:00:00, so every value below lies inside every
// other bound and only the attestation decides.
func TestRestoreCreatedAtR4_AttestationBoundaries(t *testing.T) {
	const none = "2026-01-01 09:59:02" // a recorded value no case uses as --value
	forge := func(items, opened string) func(t *testing.T) (rcaFix, []string) {
		return func(t *testing.T) (rcaFix, []string) {
			f := rcaFixture(t)
			rel, sha := r3Forge(t, f, "attest.db",
				r3Q{q: `UPDATE items SET created_at=? WHERE atm_id='WIT-010'`, args: []any{items}},
				r3Q{q: `UPDATE item_history SET created_at=? WHERE atm_id='WIT-010' AND event_type='Opened'`, args: []any{opened}})
			if n := rcaQuery(t, f.evAbs, `SELECT COUNT(1) FROM item_history WHERE atm_id='WIT-010' AND event_type='Opened'`); n != "1" {
				t.Fatalf("control: evidence has %s Opened rows for WIT-010, want 1", n)
			}
			return f, []string{"--evidence", rel, "--evidence-sha256", sha}
		}
	}
	const e = "2026-01-01 09:59:30"
	for _, src := range []string{"items-row", "opened-event"} {
		rec := func(v string) func(t *testing.T) (rcaFix, []string) {
			if src == "items-row" {
				return forge(v, none)
			}
			return forge(none, v)
		}
		for _, c := range []struct {
			cell, value string
			want        r4Want
		}{
			{"equal", e, r4Want("accept:" + src)},
			{"one-second-before", "2026-01-01 09:59:29", "refuse:EVIDENCE-DOES-NOT-ATTEST"},
			{"one-second-after", "2026-01-01 09:59:31", "refuse:EVIDENCE-DOES-NOT-ATTEST"},
			{"outside-below", "2026-01-01 09:59:00", "refuse:EVIDENCE-DOES-NOT-ATTEST"},
			{"outside-above", "2026-01-01 09:59:59", "refuse:EVIDENCE-DOES-NOT-ATTEST"},
		} {
			c := c
			t.Run(src+"/"+c.cell, func(t *testing.T) { r4Check(t, rec(e), c.value, c.want) })
		}
	}
	// Strictly between two recorded values, neither equal: both orders, and
	// the reviewer's probe verbatim (items 09:59:45, Opened 09:59:10, value
	// 09:59:30; R3G03).
	for _, c := range []struct{ name, items, opened string }{
		{"between/items-below-opened-above", "2026-01-01 09:59:10", "2026-01-01 09:59:50"},
		{"between/opened-below-items-above", "2026-01-01 09:59:50", "2026-01-01 09:59:10"},
		{"between/reviewer-probe-R3G03", "2026-01-01 09:59:45", "2026-01-01 09:59:10"},
	} {
		c := c
		t.Run(c.name, func(t *testing.T) { r4Check(t, forge(c.items, c.opened), e, "refuse:EVIDENCE-DOES-NOT-ATTEST") })
	}
	// Both sources record the value: the items row attests (it is checked first).
	t.Run("both-equal", func(t *testing.T) { r4Check(t, forge(e, e), e, "accept:items-row") })
}

// --- (c) validation boundaries ----------------------------------------------

// TestRestoreCreatedAtR4_ValidationBoundaries: every time bound at equal, one
// second before and one second after, with the value attested by the
// evidence items row so only the bound decides.
func TestRestoreCreatedAtR4_ValidationBoundaries(t *testing.T) {
	// mk builds the fixture; live runs after the fixture (extra history rows,
	// a current value); the evidence items row records the case's value.
	mk := func(value string, live func(t *testing.T, f rcaFix)) func(t *testing.T) (rcaFix, []string) {
		return func(t *testing.T) (rcaFix, []string) {
			f := rcaFixture(t)
			if live != nil {
				live(t, f)
			}
			rel, sha := r3Forge(t, f, "bound.db", r3Q{q: `UPDATE items SET created_at=? WHERE atm_id='WIT-010'`, args: []any{value}})
			return f, []string{"--evidence", rel, "--evidence-sha256", sha}
		}
	}
	histRow := func(at string) func(t *testing.T, f rcaFix) {
		return func(t *testing.T, f rcaFix) { r2HistRow(t, f.db, "WIT-010", "Updated", at) }
	}
	current := func(at string) func(t *testing.T, f rcaFix) {
		return func(t *testing.T, f rcaFix) {
			rcaExec(t, f.db, `UPDATE items SET created_at=?, last_modified=? WHERE atm_id='WIT-010'`, at, at)
		}
	}
	for _, c := range []struct {
		name, value string
		live        func(t *testing.T, f rcaFix)
		want        r4Want
	}{
		// newT.After(first): first history row 10:00:00
		{"first-event/one-second-before", "2026-01-01 09:59:59", nil, "accept:items-row"},
		{"first-event/equal", "2026-01-01 10:00:00", nil, "accept:items-row"},
		{"first-event/one-second-after", "2026-01-01 10:00:01", nil, "refuse:VALUE-AFTER-FIRST-EVENT"},
		// ht.Before(first): a later-id row that is EARLIER (09:59:58) becomes the first
		{"earliest-row/equal-to-earlier-later-id-row", "2026-01-01 09:59:58", histRow("2026-01-01 09:59:58"), "accept:items-row"},
		{"earliest-row/one-second-after-it", "2026-01-01 09:59:59", histRow("2026-01-01 09:59:58"), "refuse:VALUE-AFTER-FIRST-EVENT"},
		// a later-id row that is LATER (10:00:05) does not move the first
		{"earliest-row/later-row-does-not-bound", "2026-01-01 10:00:01", histRow("2026-01-01 10:00:05"), "refuse:VALUE-AFTER-FIRST-EVENT"},
		{"earliest-row/tie", "2026-01-01 10:00:00", histRow("2026-01-01 10:00:00"), "accept:items-row"},
		// newT.Before(tracker - 60 s): tracker minimum 10:00:00, bound 09:59:00
		{"tracker/one-second-before", "2026-01-01 09:58:59", nil, "refuse:VALUE-BEFORE-TRACKER"},
		{"tracker/equal", "2026-01-01 09:59:00", nil, "accept:items-row"},
		{"tracker/one-second-after", "2026-01-01 09:59:01", nil, "accept:items-row"},
		// target.created == *value and newT.After(curT): current 09:59:40
		{"current/one-second-before", "2026-01-01 09:59:39", current("2026-01-01 09:59:40"), "accept:items-row"},
		{"current/equal", "2026-01-01 09:59:40", current("2026-01-01 09:59:40"), "already"},
		{"current/one-second-after", "2026-01-01 09:59:41", current("2026-01-01 09:59:40"), "refuse:VALUE-LATER-THAN-CURRENT"},
	} {
		c := c
		t.Run(c.name, func(t *testing.T) { r4Check(t, mk(c.value, c.live), c.value, c.want) })
	}
}

// --- (d) the reviewer's minor survivors -------------------------------------

// TestRestoreCreatedAtR4_ReasonCarriageReturn (kills R3G10): a --reason with
// a carriage return, alone or before a line feed, is not one line.
func TestRestoreCreatedAtR4_ReasonCarriageReturn(t *testing.T) {
	for _, r := range []string{"line one\rline two", "trailing CR\r", "\rleading CR", "CR LF\r\nnext"} {
		for _, mode := range []string{"real", "dry-run"} {
			f := rcaFixture(t)
			extra := []string{"--reason", r}
			if mode == "dry-run" {
				extra = append(extra, "--dry-run")
			}
			before := r3Snapshot(t, f)
			rc, out, errOut := r3Run(t, f.args(extra...))
			if rc == exitOK || !strings.Contains(errOut, "refused [USAGE]") || !strings.Contains(errOut, "one line") {
				t.Fatalf("%s %q: exit %d stdout %q stderr %q; want refused [USAGE] one line", mode, r, rc, out, errOut)
			}
			if r3Snapshot(t, f) != before {
				t.Fatalf("%s %q: a refused run changed the database", mode, r)
			}
		}
	}
	// control: the same text without CR is accepted
	f := rcaFixture(t)
	if rc, _, errOut := r3Run(t, f.args("--reason", "line one line two")); rc != exitOK {
		t.Fatalf("control: a one-line reason is refused: %s", errOut)
	}
}

// TestRestoreCreatedAtR4_SidecarSizeBoundary (kills R3G06): a -wal or
// -journal of 1 byte and of 8 bytes is refused; an empty one is not.
func TestRestoreCreatedAtR4_SidecarSizeBoundary(t *testing.T) {
	for _, side := range []string{"-wal", "-journal"} {
		for _, size := range []int{0, 1, 8, 9} {
			for _, mode := range []string{"real", "dry-run"} {
				name := fmt.Sprintf("%s/%d/%s", side, size, mode)
				f := rcaFixture(t)
				if err := os.WriteFile(f.evAbs+side, bytes.Repeat([]byte{'x'}, size), 0o644); err != nil {
					t.Fatal(err)
				}
				extra := []string{}
				if mode == "dry-run" {
					extra = append(extra, "--dry-run")
				}
				before := r3Snapshot(t, f)
				rc, out, errOut := r3Run(t, f.args(extra...))
				if size == 0 {
					if rc != exitOK {
						t.Fatalf("%s: an empty sidecar is refused: %s", name, errOut)
					}
					continue
				}
				if rc == exitOK || !strings.Contains(errOut, "refused [EVIDENCE-WAL]") {
					t.Fatalf("%s: exit %d stdout %q stderr %q; want refused [EVIDENCE-WAL]", name, rc, out, errOut)
				}
				if r3Snapshot(t, f) != before {
					t.Fatalf("%s: a refused run changed the database", name)
				}
			}
		}
	}
}

// r4RepresentationNotNull matches the NOT NULL of the items representation
// column in the current schema.
var r4RepresentationNotNull = regexp.MustCompile(`representation\s+TEXT\s+NOT\s+NULL`)

// TestRestoreCreatedAtR4_NullRepresentationLegacyRow (kills R3G09): a
// legacy-shaped items table that already has a nullable representation column
// is not rebuilt by openDB (the rebuild keys on the column's presence), so a
// NULL representation can reach the command. The row is the section row: it
// is found with --representation section and without --representation, and
// the compare-and-set write matches it. Control: the NULL is really there
// before the run.
func TestRestoreCreatedAtR4_NullRepresentationLegacyRow(t *testing.T) {
	for _, narrow := range []bool{true, false} {
		for _, mode := range []string{"real", "dry-run"} {
			name := fmt.Sprintf("narrow=%v/%s", narrow, mode)
			f := rcaFixture(t)
			r3RebuildItems(t, f.db, r4RepresentationNotNull, "representation TEXT")
			rcaExec(t, f.db, `UPDATE items SET representation=NULL WHERE atm_id='WIT-010'`)
			if got := rcaQuery(t, f.db, `SELECT COUNT(1) FROM items WHERE atm_id='WIT-010' AND representation IS NULL`); got != "1" {
				t.Fatalf("%s: control: NULL representation rows %s", name, got)
			}
			extra := []string{}
			if narrow {
				extra = append(extra, "--representation", "section")
			}
			if mode == "dry-run" {
				extra = append(extra, "--dry-run")
			}
			rc, out, errOut := r3Run(t, f.args(extra...))
			if rc != exitOK || !strings.Contains(out, "[Issues/section]") {
				t.Fatalf("%s: exit %d stdout %q stderr %q; want the NULL row found as the section row", name, rc, out, errOut)
			}
			got := rcaQuery(t, f.db, `SELECT created_at FROM items WHERE atm_id='WIT-010'`)
			if mode == "real" && got != rcaOpened {
				t.Fatalf("%s: created_at %q, want %q", name, got, rcaOpened)
			}
			if mode == "dry-run" && got != rcaRewritten {
				t.Fatalf("%s: a dry run wrote created_at %q", name, got)
			}
		}
	}
}
