// update_location_status_invariant_test.go — the location↔status invariant at the
// `update` seam, and its detective half in `validate`.
//
// THE DEFECT (reproduced at runtime before this file was written): `close` performs
// the §11.4.19 ATOMIC closure migration (row + doc_segment move Issues→Fixed, plus a
// mandatory --evidence artefact). `update --status` sets the SAME terminal closed-set
// value with NO evidence and NO migration, leaving the row at current_location=Issues
// carrying a `… (→ Fixed.md)` status — a closed item stranded in the OPEN tracker, so
// it neither disappears from the open summary nor appears in the closed one. Exit was
// 0 and the confirmation line even PRINTED the location it was leaving behind:
//
//	$ workable-items update --id <id> --db <p> --status 'Fixed (→ Fixed.md)'
//	  update: <id> updated in Issues (status=Fixed (→ Fixed.md), type=Task)
//	$ sqlite3 <p> "SELECT atm_id,status,current_location FROM items WHERE atm_id='<id>'"
//	  <id>|Fixed (→ Fixed.md)|Issues
//
// WHY NOTHING CAUGHT IT. The invariant already existed but only in ONE direction.
// `moveCmd` (mutate.go) refuses BOTH bad pairs; `fixedLocationNonTerminalStatus`
// (sync.go, validate check (f)) asserts only Fixed ⇒ terminal. The mirror predicate —
// Issues ⇒ NON-terminal — was enforced at the `move` seam and NOWHERE else, so
// `update` could create it and `validate` could not see it. Control-needled before
// this fix: on a DB holding rows in the forbidden state validate reported "OK — all
// invariants satisfied" (exit 0), while the SAME validate on the SAME DB through the
// SAME path fired immediately when the MIRROR direction was injected (exit 1) —
// proving the null was a real gap and not a blind instrument (§11.4.201(6)(7)(b)).
//
// WHAT IS ADDED. Both halves of the same predicate, both sourced from
// terminalStatuses() — itself derived from closeStatusMap — so the preventive guard
// (updateCmd), the sibling preventive guard (moveCmd) and the two detective gates
// (sync.go) can never drift apart:
//   - PREVENTIVE (updateCmd): refuse a terminal --status while the item is located
//     in Issues, naming BOTH correct paths (`close` for a new closure, which demands
//     evidence; `move` for reconciling a row already closed elsewhere).
//   - DETECTIVE (validate): issuesLocationTerminalStatus, so rows ALREADY in the
//     forbidden state — written before the guard existed, or by raw SQL that bypasses
//     the CLI entirely — are caught by a full-table sweep, not merely prevented going
//     forward (§11.4.146(D3)).
//
// §11.4.201(1) FALSE-POSITIVE GUARD. A refusal that blocks legitimate work is a
// FAIL-bluff of equal severity to the hole it closes, so both directions carry
// negative controls: a NON-terminal --status on an Issues item must still succeed, a
// terminal --status on an item already located in Fixed must still succeed, a
// non-status field-only update on a row already in the forbidden state must still
// succeed (otherwise the guard would block the very remediation work it creates), and
// validate must stay silent on a legitimately-closed item.
//
// §1.1 PAIRED MUTATION (documented + exercised): delete the terminal/Issues check in
// updateCmd → TestUpdateCmd_RefusesTerminalStatusOnIssuesLocatedItem FAILs; replace
// issuesLocationTerminalStatus's body with `return nil` →
// TestValidate_CatchesTerminalStatusAtIssues FAILs. Restore → GREEN.
//
// §11.4.115 RED POLARITY: RED_MODE=1 asserts the GUARD-ABSENT baseline (the defect
// reproduces), so the same source proves the pre-fix state and guards the post-fix
// state. Default (RED_MODE unset) asserts the guard is present.
//
// HARD CONSTRAINT: fresh temp DB only (newTestDB); NEVER touches a live tracker DB.
package main

import (
	"os"
	"strings"
	"testing"
)

// seedIssuesItem adds a fresh Issues item through the REAL add path. The result is
// current_location='Issues' with status='Queued' — the exact shape the reproduction
// starts from.
func seedIssuesItem(t *testing.T, dbPath, id string) {
	t.Helper()
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "an open item that must not be closed by a bare status write",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the invariant tests",
		"Bug", "High",
	}); code != exitOK {
		t.Fatalf("seed add %s: exit %d", id, code)
	}
}

// forbiddenState reports whether id is in the §11.4.19-violating state: a terminal
// closed-set status while still located in Issues.
func forbiddenState(t *testing.T, dbPath, id string) (bool, string) {
	t.Helper()
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
		return false, "(not in Issues)"
	}
	return terminalStatuses()[strings.TrimSpace(it.Status)], it.Status
}

// TestUpdateCmd_RefusesTerminalStatusOnIssuesLocatedItem is the PREVENTIVE guard and
// the exact runtime reproduction. The decisive assertion is on the DB ROW, not on the
// exit code alone: a refusal that still wrote the row would be a bluff.
func TestUpdateCmd_RefusesTerminalStatusOnIssuesLocatedItem(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	// THE INPUT SPACE IS NOT THE FOUR CANONICAL STRINGS. normalizeStatus (parse.go)
	// deliberately accepts operator shorthand and prose-suffixed values, so a status
	// that is NON-terminal as typed still becomes terminal before it is stored. Two
	// distinct non-canonical routes reach terminalStatuses():
	//   - synonym contains-match:            "fixed"  -> "Fixed (→ Fixed.md)"
	//   - prefix match with trailing prose:  "Completed (→ Fixed.md) — see notes"
	//                                                 -> "Completed (→ Fixed.md)"
	// A guard that tests the RAW flag instead of the NORMALIZED value passes every
	// canonical case above and still strands the row on these — a real operator input
	// class, and precisely the §11.4.115(F) hole of a guard dimension never observed
	// failing. Covering both routes is what makes the §1.1 pairing complete on the
	// normalization dimension.
	for _, tc := range []struct{ input, normalizesTo string }{
		{"Fixed (→ Fixed.md)", "Fixed (→ Fixed.md)"},
		{"Implemented (→ Fixed.md)", "Implemented (→ Fixed.md)"},
		{"Completed (→ Fixed.md)", "Completed (→ Fixed.md)"},
		{"Obsolete (→ Fixed.md)", "Obsolete (→ Fixed.md)"},
		{"fixed", "Fixed (→ Fixed.md)"},
		{"obsolete", "Obsolete (→ Fixed.md)"},
		{"Completed (→ Fixed.md) — see notes", "Completed (→ Fixed.md)"},
	} {
		t.Run(tc.input, func(t *testing.T) {
			// The case's own precondition, asserted not assumed (§11.4.6): if
			// normalizeStatus ever stops mapping this input to a terminal value the
			// case would silently stop testing anything.
			if got := normalizeStatus(tc.input); got != tc.normalizesTo {
				t.Fatalf("precondition broken: normalizeStatus(%q) = %q, want %q — this case no longer exercises the guard",
					tc.input, got, tc.normalizesTo)
			}

			dbPath := newTestDB(t)
			seedIssuesItem(t, dbPath, "WIT-900")

			code := updateCmd([]string{"--db", dbPath, "--id", "WIT-900", "--status", tc.input})

			bad, got := forbiddenState(t, dbPath, "WIT-900")
			if assertGuardAbsent {
				// RED_MODE=1: assert the guard-absent baseline reproduces — update
				// accepted the terminal status and stranded the row in Issues.
				if code != exitOK {
					t.Fatalf("RED_MODE=1: update refused (exit %d) — guard present, guard-absent baseline no longer reproducible", code)
				}
				if !bad {
					t.Fatalf("RED_MODE=1: row not in the forbidden state (status=%q) — defect no longer reproducible", got)
				}
				return
			}

			if code == exitOK {
				t.Errorf("update returned OK for --status %q (normalizes to the terminal %q) on an Issues-located item — §11.4.19 closure migration skipped",
					tc.input, tc.normalizesTo)
			}
			if bad {
				t.Fatalf("row left in the forbidden state: status=%q at current_location=Issues — a closed item stranded in the OPEN tracker (input was %q)", got, tc.input)
			}
		})
	}
}

// TestUpdateCmd_RefusalNamesBothCorrectPaths: a refusal that only says "no" leaves the
// operator stuck. §11.4.201(5) — print the resolved evidence and the way forward. The
// two situations are different, so BOTH paths must be named: `close` mints a NEW
// closure (and demands --evidence), `move` reconciles a row already closed elsewhere.
func TestUpdateCmd_RefusalNamesBothCorrectPaths(t *testing.T) {
	if os.Getenv("RED_MODE") == "1" {
		t.Skip("RED_MODE=1: no refusal is emitted in the guard-absent baseline") // SKIP-OK: RED polarity
	}
	dbPath := newTestDB(t)
	seedIssuesItem(t, dbPath, "WIT-901")

	rc, stderr := captureStderrRun(t, func() int {
		return updateCmd([]string{"--db", dbPath, "--id", "WIT-901", "--status", "Fixed (→ Fixed.md)"})
	})
	if rc == exitOK {
		t.Fatalf("update returned OK — no refusal was emitted to inspect")
	}

	for _, want := range []string{"WIT-901", "Issues", "close", "--evidence", "move", "§11.4.19"} {
		if !strings.Contains(stderr, want) {
			t.Errorf("refusal message does not mention %q — not actionable (§11.4.201(5)).\ngot: %s", want, stderr)
		}
	}
}

// --- §11.4.201(1) NEGATIVE CONTROLS: the guard must refuse NOTHING else. ---

// TestUpdateCmd_AllowsNonTerminalStatusOnIssuesLocatedItem: the ordinary, overwhelmingly
// common case. If the guard blocks this it is a false-positive refusal.
func TestUpdateCmd_AllowsNonTerminalStatusOnIssuesLocatedItem(t *testing.T) {
	// The COMPLETE non-terminal half of the §11.4.15 closed set, so the sweep is
	// exhaustive rather than a sample: every value the guard must let through.
	for _, tc := range []struct {
		status string
		// wholeDBValidates is false where the status carries an ADDITIONAL, unrelated
		// obligation that `update` alone cannot satisfy: §11.4.148 D3 requires an
		// Operator-blocked item to own an operator_block_details row, which the
		// `block` command writes. Asserting whole-DB validate there would fail on a
		// DIFFERENT, correct invariant and say nothing about this guard. The
		// load-bearing assertion — the guard does NOT refuse the status — is applied
		// to every value either way.
		wholeDBValidates bool
	}{
		{"Queued", true},
		{"In progress", true},
		{"Ready for testing", true},
		{"In testing", true},
		{"Reopened", true},
		{"Operator-blocked", false},
	} {
		t.Run(tc.status, func(t *testing.T) {
			dbPath := newTestDB(t)
			seedIssuesItem(t, dbPath, "WIT-902")

			if code := updateCmd([]string{"--db", dbPath, "--id", "WIT-902", "--status", tc.status}); code != exitOK {
				t.Fatalf("update refused a legitimate non-terminal status %q (exit %d) — §11.4.201(1) false-positive refusal", tc.status, code)
			}
			db, _ := openDB(dbPath)
			it, _ := loadItem(db, "WIT-902", "Issues")
			db.Close()
			if it == nil {
				t.Fatal("WIT-902 vanished from Issues")
			}
			if strings.TrimSpace(it.Status) != tc.status {
				t.Fatalf("status = %q, want %q — the legitimate update did not land", it.Status, tc.status)
			}
			if tc.wholeDBValidates {
				if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
					t.Fatalf("validate FAILed (%d) after a legitimate non-terminal update", code)
				}
			}
			// Regardless of the above, THIS guard must find nothing: a non-terminal
			// status at Issues is coherent by definition.
			vdb, _ := openDB(dbPath)
			vitems, _ := loadItems(vdb)
			vdb.Close()
			if f := issuesLocationTerminalStatus(vitems); len(f) != 0 {
				t.Fatalf("location↔status gate fired on a coherent non-terminal row: %v", f)
			}
		})
	}
}

// TestUpdateCmd_AllowsTerminalStatusOnFixedLocatedItem: a terminal status is CORRECT
// for an item already located in Fixed. The guard keys on the location↔status PAIR,
// never on the status alone; blocking this would break legitimate closed-item edits.
func TestUpdateCmd_AllowsTerminalStatusOnFixedLocatedItem(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-903") // add + close → Fixed, terminal (Type=Bug, per reopen_relocate_test.go's seedFixedItem).

	// BOB-240 §11.4.33 Type↔Status guard reconciliation: this test's ORIGINAL
	// target value — "Implemented (→ Fixed.md)" — is Feature's closure word,
	// not Bug's, so it is now itself a Type↔Status mismatch BOB-240's guard
	// correctly refuses (WIT-903 is seeded Type=Bug by seedFixedItem). The
	// negative-control INTENT this test exists to prove — a genuinely
	// terminal-status-changing update at Fixed must still be ACCEPTED, never
	// blocked as a false positive (§11.4.201(1)) — is preserved by targeting
	// "Obsolete (→ Fixed.md)" instead: it is BOTH terminal (still exercises
	// the BOB-175 guard this test predates) AND valid for ANY Type per
	// BOB-240 criterion 5, so it is a legitimate transition under BOTH
	// guards simultaneously and a real status change (Fixed -> Obsolete)
	// still lands, unlike re-asserting the SAME value.
	if code := updateCmd([]string{"--db", dbPath, "--id", "WIT-903", "--location", "Fixed",
		"--status", "Obsolete (→ Fixed.md)"}); code != exitOK {
		t.Fatalf("update refused a terminal status on a Fixed-located item (exit %d) — §11.4.201(1) false-positive refusal", code)
	}
	db, _ := openDB(dbPath)
	it, _ := loadItem(db, "WIT-903", "Fixed")
	db.Close()
	if it == nil {
		t.Fatal("WIT-903 vanished from Fixed")
	}
	if strings.TrimSpace(it.Status) != "Obsolete (→ Fixed.md)" {
		t.Fatalf("status = %q, want Obsolete (→ Fixed.md) — the legitimate update did not land", it.Status)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) after a legitimate terminal update at Fixed", code)
	}
}

// TestUpdateCmd_AllowsNonStatusFieldEditOnAlreadyForbiddenRow: rows already in the
// forbidden state exist in real corpora (they are why the detective gate is needed).
// Editing an unrelated field on such a row must still work — a guard that blocked it
// would block the remediation work it exists to prompt.
func TestUpdateCmd_AllowsNonStatusFieldEditOnAlreadyForbiddenRow(t *testing.T) {
	dbPath := newTestDB(t)
	seedIssuesItem(t, dbPath, "WIT-904")
	injectTerminalStatusAtIssues(t, dbPath, "WIT-904", "Fixed (→ Fixed.md)")

	if code := updateCmd([]string{"--db", dbPath, "--id", "WIT-904", "--severity", "Critical"}); code != exitOK {
		t.Fatalf("update refused a non-status field edit on an already-forbidden row (exit %d) — the guard blocks its own remediation path", code)
	}
	db, _ := openDB(dbPath)
	it, _ := loadItem(db, "WIT-904", "Issues")
	db.Close()
	if it == nil || strings.TrimSpace(it.Severity) != "Critical" {
		t.Fatalf("severity edit did not land (item=%v)", it)
	}
}

// --- DETECTIVE GATE (validate), §11.4.146(D3) full-table sweep. ---

// injectTerminalStatusAtIssues writes the forbidden state by RAW SQL, deliberately
// bypassing the CLI — the class the write-seam guard alone cannot cover. body_md's
// `**Status:**` line is canonicalized to the SAME value as the column so this does NOT
// trip the pre-existing column↔body guard; ONLY the location↔status invariant can
// catch it.
func injectTerminalStatusAtIssues(t *testing.T, dbPath, id, terminal string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var body string
	if err := db.QueryRow(`SELECT COALESCE(body_md,'') FROM items WHERE atm_id=? AND current_location='Issues'`, id).Scan(&body); err != nil {
		t.Fatalf("read body: %v", err)
	}
	res, err := db.Exec(`UPDATE items SET status=?, body_md=? WHERE atm_id=? AND current_location='Issues'`,
		terminal, canonicalizeBodyStatusLine(body, terminal), id)
	if err != nil {
		t.Fatalf("inject: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("inject affected %d rows, want 1", n)
	}
	// Guard the ISOLATION: the column↔body guard must find nothing, or this fixture
	// would fail for the wrong reason (a §11.4.107(10) analyzer bluff).
	items, _ := loadItems(db)
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("fixture not isolated: column↔body guard fired (%v)", d)
	}
}

// TestValidate_CatchesTerminalStatusAtIssues is the golden-BAD fixture: validate must
// FAIL on a row in the forbidden state, and the finding must name the item.
func TestValidate_CatchesTerminalStatusAtIssues(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	// Every terminal value, not just one: otherwise a mutation dropping a single
	// entry from terminalStatuses() (e.g. Obsolete) would be caught ONLY by the
	// preventive test, leaving the detective half dependent on its sibling. Looping
	// here makes this gate self-sufficient.
	for _, terminal := range []string{
		"Fixed (→ Fixed.md)",
		"Implemented (→ Fixed.md)",
		"Completed (→ Fixed.md)",
		"Obsolete (→ Fixed.md)",
	} {
		t.Run(terminal, func(t *testing.T) {
			validateCatchesTerminalAtIssues(t, terminal, assertGuardAbsent)
		})
	}
}

func validateCatchesTerminalAtIssues(t *testing.T, terminal string, assertGuardAbsent bool) {
	t.Helper()
	dbPath := newTestDB(t)
	seedIssuesItem(t, dbPath, "WIT-905")
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate on a clean DB exited %d (want OK)", code)
	}

	injectTerminalStatusAtIssues(t, dbPath, "WIT-905", terminal)

	code := validateCmd([]string{"--db", dbPath})
	if assertGuardAbsent {
		if code != exitOK {
			t.Fatalf("RED_MODE=1: validate FAILed (%d) — detective gate present, guard-absent baseline no longer reproducible", code)
		}
		return
	}
	if code == exitOK {
		t.Fatal("validate returned OK on an Issues-located item carrying a terminal status — location↔status detective gate not wired")
	}

	// The finding must be readable and name the offender (§11.4.6/§11.4.201(5)).
	db, _ := openDB(dbPath)
	items, _ := loadItems(db)
	db.Close()
	findings := issuesLocationTerminalStatus(items)
	if len(findings) != 1 {
		t.Fatalf("issuesLocationTerminalStatus returned %d findings, want exactly 1: %v", len(findings), findings)
	}
	if !strings.Contains(findings[0], "WIT-905") {
		t.Errorf("finding does not name the offending item: %q", findings[0])
	}

	// SPECIFICITY: relocating the row to Fixed (the real repair) clears the finding.
	repair, _ := openDB(dbPath)
	if _, err := repair.Exec(`UPDATE items SET current_location='Fixed' WHERE atm_id='WIT-905'`); err != nil {
		repair.Close()
		t.Fatalf("repair: %v", err)
	}
	ritems, _ := loadItems(repair)
	repair.Close()
	if f := issuesLocationTerminalStatus(ritems); len(f) != 0 {
		t.Fatalf("guard still fires after the row was relocated to Fixed: %v — not specific to the desync", f)
	}
}

// TestValidate_DoesNotFireOnLegitimateClosedItem is the detective gate's NEGATIVE
// CONTROL: a properly closed item (terminal status AT Fixed) must produce ZERO
// findings, or the gate is a §11.4.201(1) false-positive engine.
func TestValidate_DoesNotFireOnLegitimateClosedItem(t *testing.T) {
	if os.Getenv("RED_MODE") == "1" {
		t.Skip("RED_MODE=1: issuesLocationTerminalStatus does not exist in the guard-absent baseline") // SKIP-OK: RED polarity
	}
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-906")  // closed correctly: terminal @ Fixed
	seedIssuesItem(t, dbPath, "WIT-907") // open correctly: non-terminal @ Issues

	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) on a DB whose every item is location↔status coherent", code)
	}
	db, _ := openDB(dbPath)
	items, _ := loadItems(db)
	db.Close()
	if f := issuesLocationTerminalStatus(items); len(f) != 0 {
		t.Fatalf("detective gate fired on a coherent DB: %v — §11.4.201(1) false-positive refusal", f)
	}
	// Control needle: the gate is not simply inert. Flip one row into the forbidden
	// state in memory and confirm the SAME function sees it.
	for i := range items {
		if items[i].AtmID == "WIT-907" {
			items[i].Status = "Fixed (→ Fixed.md)"
		}
	}
	if f := issuesLocationTerminalStatus(items); len(f) != 1 {
		t.Fatalf("control needle: gate returned %d findings on a seeded violation, want 1 — the clean result above proves nothing", len(f))
	}
}

// --- BOB-175: the MIRROR direction — a NON-terminal --status on a Fixed-located
// item. BOB-166 (above) closed Issues⇒terminal; this closes Fixed⇒non-terminal,
// the direction BOB-166 deliberately left open (tracked, not left as a comment —
// see the design-decision comment on the guard itself in mutate.go). ---

// fixedForbiddenState reports whether id, located in Fixed, carries a NON-terminal
// status — the BOB-175 mirror of forbiddenState (which checks the Issues direction
// above). This is exactly the state fixedLocationNonTerminalStatus (validate check
// (f), sync.go) refuses.
func fixedForbiddenState(t *testing.T, dbPath, id string) (bool, string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, err := loadItem(db, id, "Fixed")
	if err != nil {
		t.Fatalf("loadItem: %v", err)
	}
	if it == nil {
		return false, "(not in Fixed)"
	}
	return !terminalStatuses()[strings.TrimSpace(it.Status)], it.Status
}

// TestUpdateCmd_RefusesNonTerminalStatusOnFixedLocatedItem is the BOB-175 PREVENTIVE
// guard and its exact runtime reproduction. Verified empirically by the independent
// reviewer of BOB-166 (quoted verbatim in the item):
//
//	update --location Fixed --status 'In progress'   -> exit 0
//	validate                                          -> FAILS, naming the row (check (f))
//
// The decisive assertion is on the DB ROW, not on the exit code alone: a refusal
// that still wrote the row would be a bluff. Covers the same normalization
// dimension as TestUpdateCmd_RefusesTerminalStatusOnIssuesLocatedItem (canonical
// values plus non-canonical routes through normalizeStatus), so a guard that reads
// the raw flag instead of the normalized value cannot pass either table.
func TestUpdateCmd_RefusesNonTerminalStatusOnFixedLocatedItem(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	for _, tc := range []struct{ input, normalizesTo string }{
		{"Queued", "Queued"},
		{"In progress", "In progress"},
		{"Ready for testing", "Ready for testing"},
		{"In testing", "In testing"},
		{"Reopened", "Reopened"},
		{"queued", "Queued"},
		{"still making progress on this", "In progress"},
	} {
		t.Run(tc.input, func(t *testing.T) {
			if got := normalizeStatus(tc.input); got != tc.normalizesTo {
				t.Fatalf("precondition broken: normalizeStatus(%q) = %q, want %q — this case no longer exercises the guard",
					tc.input, got, tc.normalizesTo)
			}

			dbPath := newTestDB(t)
			seedFixedItem(t, dbPath, "WIT-910")

			code := updateCmd([]string{"--db", dbPath, "--id", "WIT-910", "--location", "Fixed", "--status", tc.input})

			bad, got := fixedForbiddenState(t, dbPath, "WIT-910")
			if assertGuardAbsent {
				// RED_MODE=1: assert the guard-absent baseline reproduces exactly
				// the independent reviewer's empirical finding — update accepted the
				// non-terminal status on a Fixed row AND the row validate then
				// refuses actually exists.
				if code != exitOK {
					t.Fatalf("RED_MODE=1: update refused (exit %d) — guard present, guard-absent baseline no longer reproducible", code)
				}
				if !bad {
					t.Fatalf("RED_MODE=1: row not in the forbidden state (status=%q) — defect no longer reproducible", got)
				}
				if vc := validateCmd([]string{"--db", dbPath}); vc == exitOK {
					t.Fatalf("RED_MODE=1: validate returned OK on the row update just minted — the reproduction is incomplete (check (f) should refuse it)")
				}
				return
			}

			if code == exitOK {
				t.Errorf("update returned OK for --status %q (normalizes to the non-terminal %q) on a Fixed-located item — mints a row validate immediately refuses",
					tc.input, tc.normalizesTo)
			}
			if bad {
				t.Fatalf("row left in the forbidden state: status=%q at current_location=Fixed (input was %q)", got, tc.input)
			}
		})
	}
}

// TestUpdateCmd_FixedRefusalNamesAllThreePaths is BOB-175 acceptance criterion (a)
// made runtime-visible, not just a source comment: the refusal must name the
// genuine-demotion path (`reopen`, default — relocates to Issues), the non-demotion
// relocation path (`move --to Issues`), AND the sanctioned transient override
// (`reopen --location Fixed`) — so an operator reading the error, not only a future
// reader of mutate.go, learns the coexistence decision.
func TestUpdateCmd_FixedRefusalNamesAllThreePaths(t *testing.T) {
	if os.Getenv("RED_MODE") == "1" {
		t.Skip("RED_MODE=1: no refusal is emitted in the guard-absent baseline") // SKIP-OK: RED polarity
	}
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-911")

	rc, stderr := captureStderrRun(t, func() int {
		return updateCmd([]string{"--db", dbPath, "--id", "WIT-911", "--location", "Fixed", "--status", "In progress"})
	})
	if rc == exitOK {
		t.Fatalf("update returned OK — no refusal was emitted to inspect")
	}

	for _, want := range []string{
		"WIT-911", "Fixed", "§11.4.34",
		"reopen --id", "move --id", "--location Fixed",
	} {
		if !strings.Contains(stderr, want) {
			t.Errorf("refusal message does not mention %q — not actionable (§11.4.201(5)).\ngot: %s", want, stderr)
		}
	}
}

// --- §11.4.201(1) NEGATIVE CONTROLS for the BOB-175 direction. ---

// injectNonTerminalStatusAtFixed writes the forbidden state by RAW SQL, deliberately
// bypassing the CLI — the mirror of injectTerminalStatusAtIssues for the Fixed
// direction, used to set up the "already-forbidden row" fixtures below without
// depending on the guard under test.
func injectNonTerminalStatusAtFixed(t *testing.T, dbPath, id, nonTerminal string) {
	t.Helper()
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var body string
	if err := db.QueryRow(`SELECT COALESCE(body_md,'') FROM items WHERE atm_id=? AND current_location='Fixed'`, id).Scan(&body); err != nil {
		t.Fatalf("read body: %v", err)
	}
	res, err := db.Exec(`UPDATE items SET status=?, body_md=? WHERE atm_id=? AND current_location='Fixed'`,
		nonTerminal, canonicalizeBodyStatusLine(body, nonTerminal), id)
	if err != nil {
		t.Fatalf("inject: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("inject affected %d rows, want 1", n)
	}
	items, _ := loadItems(db)
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("fixture not isolated: column↔body guard fired (%v)", d)
	}
}

// TestUpdateCmd_AllowsNonStatusFieldEditOnFixedLocatedForbiddenRow mirrors
// TestUpdateCmd_AllowsNonStatusFieldEditOnAlreadyForbiddenRow for the Fixed
// direction: a row already in the forbidden state (planted before the guard
// existed, by raw SQL, or by reopen's sanctioned override) must still accept a
// non-status field edit — a guard that blocked this would block the very
// remediation work it exists to prompt.
func TestUpdateCmd_AllowsNonStatusFieldEditOnFixedLocatedForbiddenRow(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-912")
	injectNonTerminalStatusAtFixed(t, dbPath, "WIT-912", "In progress")

	if code := updateCmd([]string{"--db", dbPath, "--id", "WIT-912", "--location", "Fixed", "--severity", "Critical"}); code != exitOK {
		t.Fatalf("update refused a non-status field edit on an already-forbidden Fixed row (exit %d) — the guard blocks its own remediation path", code)
	}
	db, _ := openDB(dbPath)
	it, _ := loadItem(db, "WIT-912", "Fixed")
	db.Close()
	if it == nil || strings.TrimSpace(it.Severity) != "Critical" {
		t.Fatalf("severity edit did not land (item=%v)", it)
	}
}

// TestUpdateCmd_FixedGuardDoesNotAffectReopenSanctionedOverride is BOB-175's SHARP
// negative control, exactly as the item names it: the sanctioned reopen path MUST
// still work. reopenCmd performs its own tx.Exec write and never calls updateCmd
// (verified by inspection — see point 1 of the design-decision comment on the guard
// in mutate.go), so this is expected to pass BY CONSTRUCTION; it is asserted here
// directly rather than merely trusted, because "the code paths don't share a
// function" is a claim, not itself captured evidence (§11.4.6). A guard that broke
// this would be worse than the gap it closes — it would break a workflow operators
// are told to use.
func TestUpdateCmd_FixedGuardDoesNotAffectReopenSanctionedOverride(t *testing.T) {
	dbPath := newTestDB(t)
	seedFixedItem(t, dbPath, "WIT-913")

	if code := reopenCmd([]string{"--db", dbPath, "--id", "WIT-913",
		"--location", "Fixed",
		"--why", "test-failed", "--who", "AI",
		"--when", "2026-09-25", "--incident", "qa-results/wit-913.log"}); code != exitOK {
		t.Fatalf("reopenCmd (--location Fixed sanctioned override) exit %d after the BOB-175 update guard landed — regression in a workflow operators are told to use", code)
	}
	db, _ := openDB(dbPath)
	defer db.Close()
	fx, _ := loadItem(db, "WIT-913", "Fixed")
	if fx == nil {
		t.Fatal("--location Fixed override NOT honored after BOB-175 — WIT-913 left Fixed")
	}
	if fx.Status != "Reopened" {
		t.Errorf("override item status = %q, want Reopened", fx.Status)
	}
	// Exactly as TestReopenCmd_LocationFixedOverrideKeepsInFixed documents: this
	// state IS flagged by validate (the sanctioned override is deliberately
	// transient) — proving the guard did not silently start suppressing that
	// detective finding either.
	if vc := validateCmd([]string{"--db", dbPath}); vc == exitOK {
		t.Fatal("validate returned OK on the sanctioned override's transient state — expected it to flag WIT-913 (check (f)), same as before BOB-175")
	}
}
