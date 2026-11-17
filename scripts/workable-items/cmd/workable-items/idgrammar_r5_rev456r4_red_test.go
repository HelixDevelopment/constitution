package main

// Reviewer RED tests, CON-456 round-4 independent review (reviewer-authored,
// §11.4.194(6)(d)). Each test is expected to FAIL on 94c95d83.

import (
	"os"
	"strings"
	"testing"
)

// R4-F1: block regenerates the body from the columns and drops every authored
// line the description column does not hold. On the real tracker the stored
// description of an item read by md-to-db is its title, so block (and update
// --description with the same text, and close) drop the item's whole authored
// body, including the §11.4.290 **Verification:** line. validate stays OK.
func TestRev456R4_RED_BlockKeepsAuthoredBody(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-960", "reviewer authored body probe", "Task", "Low")
	dir := t.TempDir()
	iss, fix := g456Export(t, dbPath, dir)
	raw, err := os.ReadFile(iss)
	if err != nil {
		t.Fatal(err)
	}
	const authored = "**Verification:** provisional (section 11.4.290) -- job: reviewer probe -- due: next run."
	const prose = "Acceptance criteria: the reviewer probe line survives every body writer."
	s := strings.Replace(string(raw), g456Desc+"\n", g456Desc+"\n\n"+prose+"\n\n"+authored+"\n", 1)
	if s == string(raw) {
		t.Fatal("control: could not place the authored lines")
	}
	if err := os.WriteFile(iss, []byte(s), 0o600); err != nil {
		t.Fatal(err)
	}
	if rc := g456Import(dbPath, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	before := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-960'`)
	if !strings.Contains(before, authored) || !strings.Contains(before, prose) {
		t.Fatalf("control: the imported body lacks the authored lines:\n%s", before)
	}
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-960", "--details", "the operator decides",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	after := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-960'`)
	for _, want := range []string{authored, prose} {
		if !strings.Contains(after, want) {
			t.Errorf("block dropped the authored line %q:\n%s", want, after)
		}
	}
}

// R4-F2: a line of the old description is skipped as operator text even when it
// is also the engine-written block record. Two description edits lose the block
// record; the next md-to-db deletes operator_block_details and validate fails
// (§11.4.148 D3), the round-3 finding-1 end state.
func TestRev456R4_RED_DescriptionOwnedSkipKeepsBlockRecord(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-961", "reviewer description owned probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-961", "--details", "the operator decides",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	var rec string
	for _, ln := range strings.Split(g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-961'`), "\n") {
		if strings.HasPrefix(ln, "**Operator-Block-Details:**") {
			rec = ln
		}
	}
	if rec == "" {
		t.Fatal("control: no block record line")
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-961", "--description", g456Desc + "\n" + rec}); rc != exitOK {
		t.Fatalf("update 1 exited %d", rc)
	}
	rc := updateCmd([]string{"--db", dbPath, "--id", "CON-961", "--description", g456Desc + " Edited twice."})
	if rc != exitOK {
		return // a refusal keeps the record: acceptable
	}
	dir := t.TempDir()
	iss, fix := g456Export(t, dbPath, dir)
	if rc := g456Import(dbPath, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if n := g456Query(t, dbPath, `SELECT count(*) FROM operator_block_details WHERE atm_id='CON-961'`); n != "1" {
		t.Errorf("the block record was lost: operator_block_details rows = %s, status %s", n,
			g456Query(t, dbPath, `SELECT status FROM items WHERE atm_id='CON-961'`))
	}
}
