package main

// Reviewer-authored (CON-456 round-2 review), copied verbatim into the package by
// the round-3 fixer as a regression guard. It shows the post-allocation gate of `add` (M15) is reachable: an
// existing id at the int64 maximum makes nextID overflow to "CON--9223372036854775808",
// a shape the pre-open probe id "CON-001" never had.

import (
	"strings"
	"testing"
)

func TestRev456R2_AllocatedIDAfterInt64MaxIsRefused(t *testing.T) {
	dbPath := newTestDB(t)
	desc := "reviewer probe description, long enough for the description floor"
	if rc := addCmd([]string{"--db", dbPath, "--id", "CON-9223372036854775807", "--title", "max int id",
		"--description", desc, "Task", "Low"}); rc != exitOK {
		t.Fatalf("explicit add at the int64 maximum exited %d", rc)
	}
	rc := addCmd([]string{"--db", dbPath, "--prefix", "CON", "--title", "allocated after max",
		"--description", desc, "Task", "Low"})
	got := g456Query(t, dbPath, `SELECT group_concat(atm_id, ',') FROM items`)
	if rc == exitOK || strings.Contains(got, "CON--") {
		t.Fatalf("add --prefix after an int64-max id: rc=%d, items=%s (an unreadable id was minted)", rc, got)
	}
}
