// reopen_body_preservation_test.go — §11.4.93 data-integrity RED/GREEN guard for
// the `reopen` subcommand's body_md-preservation contract.
//
// FORENSIC ANCHOR (FACT, measured 2026-07-20 on a throwaway copy of the live DB):
// `reopen --id ATM-406 --location Issues --why captured-evidence-contradicts …`
// collapsed that item's authored body_md 3740 → 328 bytes (91% destroyed). What the
// regeneration lost, none of which exists in ANY column: the verbatim user-mandate
// forensic anchor, the Phase 39.P source-side fix description, the
// `CM-P-PRIMARY-INTERACTIVE` 5-invariant pre-build gate, its paired §1.1 mutation,
// the §11.4.52 autonomous-validation classification, and every cross-reference.
//
// ROOT CAUSE: the pre-fix renderReopenedBody built the body from renderItemBody — a
// minimal id/title/status/type/description template — instead of patching the
// existing body. This is the SAME defect class `update` was already fixed for
// (SPK-481: `update --severity` collapsed a 10 KB body to ~250 bytes,
// update_body_preservation_test.go); `reopen` never received that fix.
//
// §11.4.115 polarity: each test asserts the CORRECT post-fix behaviour, so it FAILS
// on the pre-fix code (reproducing the truncation) and PASSES on the fixed code — the
// bug-catcher IS the regression-guard. Drives the REAL reopenCmd against a REAL
// on-disk SQLite DB (no mock, §11.4.27).
//
// §1.1 PAIRED MUTATION (documented): revert reopenedBody (mutate.go) to
// `return insertMetaLine(renderItemBody(…), detail)` → TestReopenCmd_PreservesAuthoredBody
// FAILs on the byte-comparison; restore → GREEN. Proves the fix + guard are not
// tautologies.
//
// HARD CONSTRAINT: fresh temp DB only (newTestDB); NEVER touches docs/workable_items.db.
package main

import (
	"strings"
	"testing"
)

// seedRichFixedItem seeds an item through the REAL add + close paths, then injects a
// multi-KB authored freeform body — the shape a real md→db sync produces for a
// closed item (canonical heading + meta block + large operator-authored sections).
// Returns the exact injected bytes so callers can assert byte-level preservation.
func seedRichFixedItem(t *testing.T, dbPath, id string) string {
	t.Helper()
	seedFixedItem(t, dbPath, id)

	freeform := strings.Repeat(
		"* **Authored forensic line:** operator-written content that exists in NO column "+
			"and MUST survive a reopen — gate invariants, paired mutations, cross-references.\n", 40)
	rich := "## P. [" + id + "] a closed item that will be reopened later\n\n" +
		"**Status:** Fixed (→ Fixed.md)\n" +
		"**Type:** Bug\n\n" +
		"### Forensic anchor — authored freeform section (must survive reopen)\n\n" +
		freeform + "\n"
	if len(rich) < 3000 {
		t.Fatalf("fixture body too small (%d bytes); need multi-KB to catch truncation", len(rich))
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(`UPDATE items SET body_md=? WHERE atm_id=? AND current_location='Fixed'`, rich, id); err != nil {
		t.Fatalf("seed rich body: %v", err)
	}
	return rich
}

// reopenRich runs the real reopenCmd with full §11.4.34 attribution and returns the
// resulting Issues-side body.
func reopenRich(t *testing.T, dbPath, id string) string {
	t.Helper()
	if code := reopenCmd([]string{"--db", dbPath, "--id", id,
		"--why", "captured-evidence-contradicts", "--who", "AI",
		"--when", "2026-07-20", "--incident", "docs/evidence/" + id + ".md"}); code != exitOK {
		t.Fatalf("reopenCmd: exit %d", code)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, id, "Issues")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if it == nil {
		t.Fatalf("%s not found in Issues after reopen", id)
	}
	return it.BodyMD
}

// TestReopenCmd_PreservesAuthoredBody is the KEYSTONE guard: a reopen may change
// EXACTLY the `**Status:**` line and add the §11.4.34 `**Reopened-Details:**` line.
// Every other authored line must survive byte-for-byte.
func TestReopenCmd_PreservesAuthoredBody(t *testing.T) {
	dbPath := newTestDB(t)
	rich := seedRichFixedItem(t, dbPath, "WIT-400")
	got := reopenRich(t, dbPath, "WIT-400")

	// The truncation signature: the pre-fix path produces a ~330-byte template.
	if len(got) < len(rich) {
		t.Fatalf("body SHRANK on reopen: %d → %d bytes — the §11.4.93 truncation defect "+
			"(authored content destroyed by regeneration from columns)", len(rich), len(got))
	}

	// Line-level proof: every authored line of the fixture must still be present,
	// and the ONLY differences may be the Status line + the added detail line.
	want := strings.Split(strings.ReplaceAll(rich, "**Status:** Fixed (→ Fixed.md)", "**Status:** Reopened"), "\n")
	have := strings.Split(got, "\n")
	var extra []string
	hi := 0
	for _, w := range want {
		for hi < len(have) && have[hi] != w {
			extra = append(extra, have[hi])
			hi++
		}
		if hi >= len(have) {
			t.Fatalf("authored line destroyed by reopen: %q not found in the reopened body", w)
		}
		hi++
	}
	for _, e := range extra {
		if strings.TrimSpace(e) == "" {
			continue
		}
		if !strings.HasPrefix(e, "**Reopened-Details:**") {
			t.Errorf("reopen introduced an unexpected line (only **Reopened-Details:** is allowed): %q", e)
		}
	}
}

// TestReopenCmd_WritesReopenedDetails proves the §11.4.34 attribution line is still
// emitted by the preserving path — the fix must not trade truncation for a missing
// detail block.
func TestReopenCmd_WritesReopenedDetails(t *testing.T) {
	dbPath := newTestDB(t)
	seedRichFixedItem(t, dbPath, "WIT-401")
	got := reopenRich(t, dbPath, "WIT-401")

	const want = "**Reopened-Details:** By: AI On: 2026-07-20 Reason: captured-evidence-contradicts Evidence: docs/evidence/WIT-401.md"
	if !strings.Contains(got, want) {
		t.Fatalf("§11.4.34 detail line absent from reopened body; want %q", want)
	}
	if !strings.Contains(got, "**Status:** Reopened") {
		t.Error("body **Status:** line not canonicalized to Reopened")
	}
	if strings.Contains(got, "**Status:** Fixed (→ Fixed.md)") {
		t.Error("stale terminal **Status:** line survived the reopen (column↔body desync)")
	}
}

// TestReopenCmd_DetailLineIsUpserted proves a SECOND reopen replaces the detail line
// rather than stacking a duplicate: two contradictory `**Reopened-Details:**` lines
// adjacent to one heading is a §11.4.6 ambiguity, and the §11.4.34 walk-pattern gates
// read that line positionally. The append-only audit trail is item_history, which
// correctly keeps BOTH events.
func TestReopenCmd_DetailLineIsUpserted(t *testing.T) {
	dbPath := newTestDB(t)
	seedRichFixedItem(t, dbPath, "WIT-402")
	reopenRich(t, dbPath, "WIT-402")

	// Second reopen (the item is now in Issues; reopen auto-detects the source).
	if code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-402",
		"--why", "test-failed", "--who", "User",
		"--when", "2026-07-21", "--incident", "docs/evidence/WIT-402-second.md"}); code != exitOK {
		t.Fatalf("second reopenCmd: exit %d", code)
	}

	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, "WIT-402", "Issues")
	if err != nil || it == nil {
		t.Fatalf("loadItem after second reopen: %v", err)
	}

	if n := strings.Count(it.BodyMD, "**Reopened-Details:**"); n != 1 {
		t.Fatalf("**Reopened-Details:** appears %d times after two reopens, want exactly 1 (upsert, not stack)", n)
	}
	if !strings.Contains(it.BodyMD, "On: 2026-07-21") {
		t.Error("detail line not updated to the SECOND reopen's attribution")
	}
	// The audit trail keeps both — that is where reopen history belongs.
	if n := historyCount(t, db, "WIT-402", "Reopened"); n != 2 {
		t.Errorf("item_history Reopened rows = %d, want 2 (append-only audit keeps every reopen)", n)
	}
}

// TestReopenCmd_TableRepresentationPreservedVerbatim guards the legacy Fixed.md
// pipe-table row shape: it has no meta block, so injecting a detail line would
// corrupt the table and emitting an H2 block would make the row unparseable on the
// next round-trip (the F-DBTOOL-2 defect class). The row must survive verbatim.
//
// CON-456 round 2: relocating the row into Issues.md is refused, because the
// Issues parser reads no pipe-table rows: the reopened item would be raw text in
// Issues.md and the next sync md-to-db would drop it (and its status cell would
// still read "Fixed"). The refusal writes nothing, so the row stays in Fixed
// verbatim.
func TestReopenCmd_TableRepresentationPreservedVerbatim(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-403")

	const row = "| 2026-05-18 | a closed item that will be reopened later | Bug | Fixed | R7 | abc1234 | docs/qa/WIT-403/close.md |\n"
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	if _, err := db.Exec(`UPDATE items SET body_md=?, representation='table' WHERE atm_id='WIT-403' AND current_location='Fixed'`, row); err != nil {
		db.Close()
		t.Fatalf("seed table row: %v", err)
	}
	db.Close()

	if code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-403",
		"--why", "test-failed", "--who", "AI",
		"--when", "2026-07-20", "--incident", "docs/evidence/WIT-403.md"}); code == exitOK {
		t.Fatalf("reopenCmd relocated a pipe-table row into Issues.md, where the next md-to-db cannot read it")
	}

	db, err = openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	if it, err := loadItem(db, "WIT-403", "Issues"); err != nil || it != nil {
		t.Fatalf("refused reopen still wrote an Issues row (err=%v)", err)
	}
	it, err := loadItem(db, "WIT-403", "Fixed")
	if err != nil || it == nil {
		t.Fatalf("loadItem Fixed: %v", err)
	}
	if it.BodyMD != row || it.Status == "Reopened" {
		t.Fatalf("table-representation row mutated by a refused reopen:\n got %q (status %q)\nwant %q", it.BodyMD, it.Status, row)
	}
}
