package main

// Reviewer-authored (CON-456 round-2 review), copied verbatim into the package by
// the round-3 fixer as a regression guard. RED evidence for two review findings; each asserts the behaviour
// the review expects, so it FAILS on the reviewed head.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// F-A: the description report_item.sh appends for every Bug (§11.4.292(C),
// §11.4.294(A) template lines) must mint, and the minted item must keep its
// state columns through db-to-md -> md-to-db.
func TestRev456R2_RED_BugTemplateMintsAndRoundTrips(t *testing.T) {
	dbPath := newTestDB(t)
	desc := "A reviewer bug report, long enough for the description floor.\n\n" +
		"**Reproduction:** none — UNREPRODUCED (§11.4.292)\n" +
		"**Investigation:** not-started (§11.4.294)"
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-910", "--title", "template probe",
		"--description", desc, "Bug", "Medium"}); rc != exitOK {
		t.Fatalf("add of the report_item.sh Bug template exited %d (the §11.4.202 fallback mint fails)", rc)
	}
	before := g456Query(t, dbPath, `SELECT reproduction_state||'|'||investigation_state FROM items WHERE atm_id='CON-910'`)
	iss, fix := g456Export(t, dbPath, t.TempDir())
	rt := filepath.Join(t.TempDir(), "rt.db")
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	after := g456Query(t, rt, `SELECT reproduction_state||'|'||investigation_state FROM items WHERE atm_id='CON-910'`)
	if before != after {
		t.Fatalf("state columns changed on the round trip: %s -> %s", before, after)
	}
}

// F-D: an obsolete-details --superseding value must either be refused or
// survive verbatim in the rendered Fixed.md (as block/close/reopen inputs do).
func TestRev456R2_RED_ObsoleteSupersedingSurvivesOrIsRefused(t *testing.T) {
	dbPath := newTestDB(t)
	dir := t.TempDir()
	ev := filepath.Join(dir, "ev.txt")
	if err := os.WriteFile(ev, []byte("x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-911", "--title", "obsolete probe",
		"--description", "reviewer obsolete probe, long enough for the description floor", "Task", "Low"}); rc != exitOK {
		t.Fatalf("add exited %d", rc)
	}
	if rc := closeCmd([]string{"CON-911", "--db", dbPath, "--status", "obsolete", "--evidence", ev}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	sup := "CON-082\n**Severity:** Critical"
	before := g456Dump(t, dbPath)
	rc := obsoleteDetailsCmd([]string{"CON-911", "--db", dbPath, "--since", "2026-11-17", "--reason", "duplicate-of",
		"--superseding", sup, "--evidence", ev})
	if rc != exitOK {
		if g456Dump(t, dbPath) != before {
			t.Fatalf("refused (rc=%d) but the database changed", rc)
		}
		return
	}
	_, fix := g456Export(t, dbPath, t.TempDir())
	b, err := os.ReadFile(fix)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), sup) || !strings.Contains(string(b), "Triple-check evidence: "+ev) {
		t.Fatalf("obsolete-details accepted --superseding %q but the rendered Fixed.md does not carry it (or the evidence) verbatim", sup)
	}
}
