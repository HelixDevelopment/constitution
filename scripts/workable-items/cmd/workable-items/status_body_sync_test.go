// status_body_sync_test.go — §11.4.115 RED-polarity standing regression guard
// proving NO status-mutating subcommand leaves a column↔body Status desync (the
// ATM-627 / task #20 invariant, extended from validate/repair-bodies to the
// mutation-write paths). §11.4.135 standing guard.
//
// FACT (captured 2026-07-04, all invariants proven on /tmp copies — NEVER the live
// DB): the WIRED status-mutating subcommands (add / update / reopen / block / close)
// ALREADY regenerate body_md via renderItemBody with the new status, so each leaves
// 0 column↔body desyncs. The ONE bare `UPDATE items SET status=…` path — the
// (built + unit-tested, not-yet-CLI-wired) subtask-status command (subtask.go) —
// advanced the items.status column WITHOUT touching body_md, so a child whose body
// still read `**Status:** Queued` got column `In progress`: a genuine
// §11.4.93/ATM-627 column↔body desync that `validate` (statusColumnBodyDesyncs)
// flags and `sync db-to-md` would replay as a stale line. This guard REPRODUCES
// that on the pre-fix binary (RED) and locks in 0-desync for EVERY mutation path
// once subtask-status routes through the setStatusAndSyncBody choke-point (GREEN).
//
// §11.4.115 polarity (TestSubtaskStatus_DesyncRedPolarity): DEFAULT = standing
// GREEN guard (subtask-status leaves NO desync). RED_MODE=1 asserts the PRE-FIX
// bluff (subtask-status DID leave a desync) — it PASSes only against a build where
// the fix is absent (the captured RED proof) and FAILs on this fixed binary.
//
// §1.1 PAIRED MUTATION (documented): stub setStatusAndSyncBody (crud.go) so it does
// a bare `UPDATE items SET status=…` (drop the canonicalizeBodyStatusLine body
// write) → TestNoStatusMutationLeavesDesync (subtask-status row) +
// TestSubtaskStatus_DesyncRedPolarity FAIL; restore → GREEN. Proves the guard is
// not a tautology.
//
// HARD CONSTRAINT: fresh temp DBs only; NEVER touches the live docs/workable_items.db.
package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// childDesync returns the statusColumnBodyDesyncs finding-strings for the DB at
// dbPath (loaded through the real driver — no mocks).
func loadDesyncs(t *testing.T, dbPath string) []string {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	items, err := loadItems(db)
	if err != nil {
		t.Fatalf("loadItems: %v", err)
	}
	return statusColumnBodyDesyncs(items)
}

// TestNoStatusMutationLeavesDesync is the §11.4.135 standing guard: after EVERY
// status-mutating subcommand runs on a freshly-synced item, the DB reports ZERO
// column↔body Status desyncs AND validate exits OK. Pre-fix the subtask-status row
// FAILs (bare UPDATE left the body stale); post-fix all rows PASS.
func TestNoStatusMutationLeavesDesync(t *testing.T) {
	cases := []struct {
		name    string
		mutate  func(t *testing.T) string // returns dbPath after the mutation
	}{
		{"update --status", func(t *testing.T) string {
			db := newTestDB(t)
			mustOK(t, addCmd([]string{"--db", db, "--id", "WIT-001",
				"--title", "an item", "--description", "a sufficiently long description clearing the floor", "Bug", "High"}))
			mustOK(t, updateCmd([]string{"--db", db, "--id", "WIT-001", "--status", "In progress"}))
			return db
		}},
		{"reopen", func(t *testing.T) string {
			db := newTestDB(t)
			mustOK(t, addCmd([]string{"--db", db, "--id", "WIT-002",
				"--title", "an item", "--description", "a sufficiently long description clearing the floor", "Bug", "High"}))
			mustOK(t, reopenCmd([]string{"--db", db, "--id", "WIT-002",
				"--why", "test-failed", "--who", "AI", "--when", "2026-07-04", "--incident", "qa/x.log"}))
			return db
		}},
		{"block", func(t *testing.T) string {
			db := newTestDB(t)
			mustOK(t, addCmd([]string{"--db", db, "--id", "WIT-003",
				"--title", "an item", "--description", "a sufficiently long description clearing the floor", "Task", "Medium"}))
			mustOK(t, blockCmd([]string{"--db", db, "--id", "WIT-003",
				"--details", "operator must reconfigure the host", "--why", "needs host root",
				"--unblock", "[A] raise limit · [B] cap devices", "--who", "Operator"}))
			return db
		}},
		{"close", func(t *testing.T) string {
			db := newTestDB(t)
			mustOK(t, addCmd([]string{"--db", db, "--id", "WIT-004",
				"--title", "an item", "--description", "a sufficiently long description clearing the floor", "Bug", "High"}))
			// HXC-217 (§11.4.120 reconciliation): the closure-evidence
			// RESOLVABILITY guard requires a closed item's evidence_path to
			// resolve to a real artefact. The fabricated `qa/x.log` this case
			// used is exactly the class that guard refuses, so the fixture
			// lands a real artefact and cites it — the assertion under test
			// (close leaves NO column↔body Status desync) is unchanged.
			evidence := filepath.Join(t.TempDir(), "close-evidence.log")
			if err := os.WriteFile(evidence, []byte("captured closure evidence\n"), 0o644); err != nil {
				t.Fatalf("write close evidence: %v", err)
			}
			mustOK(t, closeCmd([]string{"WIT-004", "--db", db, "--status", "fixed", "--evidence", evidence}))
			return db
		}},
		{"subtask-status", func(t *testing.T) string {
			// Parent BG: its child BG-001 is a legacy code the parser reads back,
			// so validate judges the status sync here, not the separate
			// canonical-parent child-id defect pinned in idgrammar_test.go.
			db := newTestDBWithParent(t, "BG")
			mustOK(t, subtaskAddCmd([]string{"BG", "--db", db, "--session", "s"}))
			mustOK(t, subtaskStatusCmd([]string{"BG-001", "--db", db, "--to", "In progress"}))
			return db
		}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dbPath := c.mutate(t)
			if d := loadDesyncs(t, dbPath); len(d) != 0 {
				t.Fatalf("%q left %d column↔body desync(s): %v", c.name, len(d), d)
			}
			if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
				t.Fatalf("%q: validate exited %d after mutation (expected OK)", c.name, code)
			}
		})
	}
}

// TestSubtaskStatus_DesyncRedPolarity is the dedicated §11.4.115 polarity guard for
// the ONE genuine bare-status write. It builds an in-sync child (body **Status:**
// Queued == column Queued), advances the status via subtask-status, and asserts the
// child is NOT desynced. RED_MODE=1 asserts the PRE-FIX bluff (the child WAS left
// desynced) so the captured RED is reproducible only against a fix-absent build.
func TestSubtaskStatus_DesyncRedPolarity(t *testing.T) {
	assertPreFixBluff := os.Getenv("RED_MODE") == "1"

	// Parent BG (child BG-001 round-trips); see the note in the case table above.
	dbPath := newTestDBWithParent(t, "BG")
	mustOK(t, subtaskAddCmd([]string{"BG", "--db", dbPath, "--session", "s"}))
	child := "BG-001"

	// Sanity: the freshly-added child is in sync (body Queued == column Queued).
	if d := loadDesyncs(t, dbPath); len(d) != 0 {
		t.Fatalf("freshly-added sub-task already desynced (fixture bug): %v", d)
	}

	mustOK(t, subtaskStatusCmd([]string{child, "--db", dbPath, "--to", "In progress"}))

	found := false
	for _, v := range loadDesyncs(t, dbPath) {
		if strings.Contains(v, child) && strings.Contains(v, "In progress") && strings.Contains(v, "Queued") {
			found = true
		}
	}

	if assertPreFixBluff {
		if !found {
			t.Fatalf("RED_MODE=1: subtask-status left NO desync — fix present, pre-fix bluff no longer reproducible")
		}
		return
	}
	if found {
		t.Fatalf("subtask-status left a column↔body desync on %s (bare UPDATE bypassed the body Status line)", child)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate exited %d after subtask-status (desync leaked)", code)
	}
}

func mustOK(t *testing.T, code int) {
	t.Helper()
	if code != exitOK {
		t.Fatalf("subcommand exited %d, want %d", code, exitOK)
	}
}

// TestSetStatusAndSyncBody_PreservesProseAndDetailBlocks proves the bare-status
// choke-point is a SURGICAL single-line rewrite: it advances the column, rewrites
// ONLY the last `**Status:**` line to the column value, and preserves every other
// line — multi-line prose AND a `**Reopened-Details:**` detail block — verbatim.
func TestSetStatusAndSyncBody_PreservesProseAndDetailBlocks(t *testing.T) {
	dbPath := newTestDB(t)
	mustOK(t, addCmd([]string{"--db", dbPath, "--id", "WIT-050", "--title", "rich item",
		"--description", "a sufficiently long description clearing the floor", "Bug", "High"}))

	// Seed a RICH, in-sync body directly (Queued == column Queued): prose + a
	// **Reopened-Details:** block the naive full-regen renderItemBody path would drop.
	rich := "## §1. [WIT-050] rich item\n\n**Status:** Queued\n**Type:** Bug\n" +
		"**Reopened-Details:** By: AI On: 2026-07-04 Reason: test-failed Evidence: qa/x\n\n" +
		"Detailed multi-line prose.\nSecond prose line with acceptance criteria.\n\n"
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	if _, err := db.Exec(`UPDATE items SET body_md=? WHERE atm_id='WIT-050' AND current_location='Issues'`, rich); err != nil {
		db.Close()
		t.Fatalf("seed rich body: %v", err)
	}
	tx, err := db.Begin()
	if err != nil {
		db.Close()
		t.Fatalf("begin: %v", err)
	}
	if err := setStatusAndSyncBody(tx, "WIT-050", "Issues", "In progress"); err != nil {
		tx.Rollback()
		db.Close()
		t.Fatalf("setStatusAndSyncBody: %v", err)
	}
	if err := tx.Commit(); err != nil {
		db.Close()
		t.Fatalf("commit: %v", err)
	}
	var st, body string
	if err := db.QueryRow(`SELECT status, body_md FROM items WHERE atm_id='WIT-050' AND current_location='Issues'`).Scan(&st, &body); err != nil {
		db.Close()
		t.Fatalf("readback: %v", err)
	}
	db.Close()

	if st != "In progress" {
		t.Fatalf("status column = %q, want In progress", st)
	}
	if !strings.Contains(body, "**Status:** In progress\n") {
		t.Fatalf("body Status line not canonicalized to the column:\n%q", body)
	}
	if strings.Contains(body, "**Status:** Queued") {
		t.Fatalf("stale **Status:** Queued line survived:\n%q", body)
	}
	if !strings.Contains(body, "**Reopened-Details:** By: AI On: 2026-07-04 Reason: test-failed Evidence: qa/x\n") {
		t.Fatalf("**Reopened-Details:** block dropped/altered:\n%q", body)
	}
	if !strings.Contains(body, "Detailed multi-line prose.\n") ||
		!strings.Contains(body, "Second prose line with acceptance criteria.\n") {
		t.Fatalf("prose altered/dropped:\n%q", body)
	}
	if d := loadDesyncs(t, dbPath); len(d) != 0 {
		t.Fatalf("helper left a desync: %v", d)
	}
}

// TestBlock_LeavesRepairBodiesNoop is the task-verify(3) guard: a freshly-blocked
// item is ALREADY canonical, so repair-bodies (classifyRepair) proposes NO change
// for it — proving block leaves the item column↔body-consistent (repair-bodies has
// nothing to fix afterwards).
func TestBlock_LeavesRepairBodiesNoop(t *testing.T) {
	dbPath := newTestDB(t)
	mustOK(t, addCmd([]string{"--db", dbPath, "--id", "WIT-060", "--title", "block me",
		"--description", "a sufficiently long description clearing the floor", "Task", "Medium"}))
	mustOK(t, blockCmd([]string{"--db", dbPath, "--id", "WIT-060",
		"--details", "operator must do X", "--why", "needs host root",
		"--unblock", "[A] a · [B] b", "--who", "Operator"}))

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, "WIT-060", "Issues")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if it == nil {
		t.Fatal("WIT-060 absent after block")
	}
	action, newBody := classifyRepair(*it)
	if action != repairNoop {
		t.Fatalf("repair-bodies would %q a freshly-blocked item (expected noop) — block did not leave it canonical", action)
	}
	if newBody != it.BodyMD {
		t.Fatal("classifyRepair proposed a body change for a noop item")
	}
}
