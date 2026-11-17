package main

// Reviewer-authored (CON-456 round-3 review). RED: `update --description` on an
// item that carries engine-written detail lines must keep them in the body, so
// the next db-to-md -> md-to-db keeps the side tables and validate stays clean.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRev456R3_RED_UpdateDescriptionKeepsBlockRecord(t *testing.T) {
	dbPath := newTestDB(t)
	g456Add(t, dbPath, "CON-940", "blocked probe", "Task", "Low")
	if rc := blockCmd([]string{"--db", dbPath, "--id", "CON-940", "--details", "the decision",
		"--why", "every alternative was tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"}); rc != exitOK {
		t.Fatalf("block exited %d", rc)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-940", "--description", g456Desc + " Edited."}); rc != exitOK {
		t.Fatalf("update --description exited %d", rc)
	}
	body := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-940'`)
	if !strings.Contains(body, "**Operator-Block-Details:**") {
		t.Errorf("update --description dropped the Operator-Block-Details line:\n%s", body)
	}
	iss, fix := g456Export(t, dbPath, t.TempDir())
	rt := filepath.Join(t.TempDir(), "rt.db")
	raw, _ := os.ReadFile(dbPath)
	_ = os.WriteFile(rt, raw, 0o600)
	if rc := g456Import(rt, iss, fix); rc != exitOK {
		t.Fatalf("md-to-db exited %d", rc)
	}
	if got := g456Query(t, rt, `SELECT COUNT(*) FROM operator_block_details WHERE atm_id='CON-940'`); got != "1" {
		t.Errorf("operator_block_details rows after one cycle = %s, want 1", got)
	}
}

func TestRev456R3_RED_UpdateDescriptionKeepsClosureEvidenceLine(t *testing.T) {
	dbPath := newTestDB(t)
	ev := filepath.Join(t.TempDir(), "ev.txt")
	_ = os.WriteFile(ev, []byte("x\n"), 0o600)
	g456Add(t, dbPath, "CON-941", "closed probe", "Task", "Low")
	if rc := closeCmd([]string{"CON-941", "--db", dbPath, "--status", "completed", "--evidence", ev}); rc != exitOK {
		t.Fatalf("close exited %d", rc)
	}
	before := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-941'`)
	if !strings.Contains(before, "**Evidence:**") {
		t.Fatalf("control: the closed body carries no Evidence line:\n%s", before)
	}
	if rc := updateCmd([]string{"--db", dbPath, "--id", "CON-941", "--location", "Fixed", "--description", g456Desc + " Edited."}); rc != exitOK {
		t.Fatalf("update --description exited %d", rc)
	}
	after := g456Query(t, dbPath, `SELECT body_md FROM items WHERE atm_id='CON-941'`)
	if !strings.Contains(after, "**Evidence:**") {
		t.Errorf("update --description dropped the closure Evidence line:\n%s", after)
	}
}
