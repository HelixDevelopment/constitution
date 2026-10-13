// bob240_type_status_test.go — the §11.4.33 Type↔Status mapping invariant at
// the `close` and `update` seams, and its detective half in `validate`.
//
// THE DEFECT. This session's own conductor made the identical mistake FOUR
// times in a row (BOB-077/100/179/226 — all Type=Task closed with `--status
// fixed`, the Bug-mapped word, instead of `--status completed`) — on a DB
// that ALREADY held 30+ historical instances of the same class from earlier
// sessions (bulk-corrected in BOB-239). `close --status <word>` /
// `update --status <word>` accepted a status keyword whose §11.4.33 closure
// vocabulary belongs to a DIFFERENT Type than the target item's own Type,
// silently minting exactly the closure-vocabulary violation the closed
// {Bug→Fixed, Feature→Implemented, Task→Completed, any→Obsolete} mapping
// forbids. `validate` never checked this agreement either: confirmed this
// session that `validate: OK` ran repeatedly against a DB simultaneously
// holding 30+ live violations of this exact class — the existing invariant
// set checked the status/type CLOSED-SETS independently (validateCmd's
// statusSet/typeSet) and the location↔status desync ((f)/(f2),
// fixedLocationNonTerminalStatus/issuesLocationTerminalStatus), but never
// whether a TERMINAL status and its item's Type actually AGREE.
//
// WHAT IS ADDED. One shared predicate, typeStatusMismatch (crud.go) — derived
// from closeStatusMap (typeCloseKeyword names the correct KEYWORD per Type;
// the STATUS TEXT itself is never re-derived, §11.4.251) — reused by THREE
// surfaces so none can drift from another:
//
//   - PREVENTIVE (closeCmd): refuse a --status keyword whose Type-mapping
//     mismatches src.Type; Obsolete is exempt for ANY Type (criterion 5).
//   - PREVENTIVE (updateCmd): the identical guard, scoped to a TERMINAL
//     --status. This composes cleanly with BOB-166/BOB-175's existing
//     location↔status guards rather than competing with them: those two
//     guards already partition every call into exactly one of three
//     mutually-exclusive cells — {Issues,terminal} (BOB-166 refuses),
//     {Fixed,non-terminal} (BOB-175 refuses), {Issues,non-terminal}
//     (legitimate, passes through) — leaving {Fixed,terminal} as the ONLY
//     cell that can still reach this new check. A single call can therefore
//     never trigger more than one of the three guards; BOB-240's check is
//     placed last and fires ONLY in the one cell the first two already let
//     through. See TestUpdateCmd_LocationGuardFiresBeforeTypeStatusGuard for
//     the runtime proof of this partition (documented in the closure
//     evidence as the BOB-175-interaction note the task requested).
//   - DETECTIVE (validate): typeStatusMismatches (sync.go), a full-table
//     sweep over every Fixed-location item, so rows minted before the guard
//     existed — or by raw SQL bypassing the CLI entirely — are caught too
//     (§11.4.146(D3)).
//
// §11.4.201(1) FALSE-POSITIVE GUARD: every refusal carries a negative
// control — a Type-matching close/update must still succeed, and Obsolete
// must succeed for EVERY Type (criterion 5) — so a guard that blocks
// legitimate work is caught with the same rigor as one that misses a real
// violation.
//
// §1.1 PAIRED MUTATION (documented + exercised, mirroring the RED_MODE
// convention update_location_status_invariant_test.go established):
// RED_MODE=1 asserts the guard-ABSENT baseline — the mismatched close/update
// call SUCCEEDS, and (for the update/validate cases) `validate` reports OK on
// the resulting Fixed-location mismatch — true only against the pre-fix
// source. Default (RED_MODE unset) asserts the guard fires. This is the SAME
// physical exercise as "delete the guard, confirm the test fails, restore":
// running these tests BEFORE typeStatusMismatch/its three call sites existed
// (this session's actual authoring order) reproduced exactly the RED_MODE=1
// branch; the guard's addition is what makes the default branch pass.
//
// HARD CONSTRAINT: fresh temp DB only (newTestDB); NEVER touches a live
// tracker DB.
package main

import (
	"os"
	"strings"
	"testing"
)

// seedFixedItemOfType seeds an item of the given Type, closed via the REAL
// close subcommand with the given --status keyword, landing it at
// current_location='Fixed' with the matching terminal status. Callers use a
// keyword that DOES match typ (so the seed itself never trips the guard under
// test) to set up the "already correctly closed" starting state the update
// guard tests then mutate away from.
func seedFixedItemOfType(t *testing.T, dbPath, id, typ, closeStatus string) {
	t.Helper()
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "a type-status seed item for " + id,
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the BOB-240 seed fixture",
		typ, "High",
	}); code != exitOK {
		t.Fatalf("seed add %s: exit %d", id, code)
	}
	evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/"+id+"/seed.md")
	if code := closeCmd([]string{"--db", dbPath, "--status", closeStatus, "--evidence", evidence, id}); code != exitOK {
		t.Fatalf("seed close %s --status %s: exit %d", id, closeStatus, code)
	}
}

// injectTypeStatusMismatchAtFixed writes a Fixed-location item whose Type does
// NOT match its terminal status's §11.4.33 mapping, by RAW SQL — deliberately
// bypassing the close/update guards entirely, mirroring
// injectTerminalStatusAtIssues / injectNonTerminalStatusAtFixed
// (update_location_status_invariant_test.go). The detective gate must catch
// rows minted before the guard existed, or by anything that bypasses the CLI.
func injectTypeStatusMismatchAtFixed(t *testing.T, dbPath, id, typ, mismatchedStatus string) {
	t.Helper()
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "a Fixed-location item seeded directly in the mismatched state",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the type-status mismatch fixture",
		typ, "High",
	}); code != exitOK {
		t.Fatalf("seed add %s: exit %d", id, code)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	var body string
	if err := db.QueryRow(`SELECT COALESCE(body_md,'') FROM items WHERE atm_id=? AND current_location='Issues'`, id).Scan(&body); err != nil {
		t.Fatalf("read body: %v", err)
	}
	newBody := canonicalizeBodyStatusLine(body, mismatchedStatus)
	res, err := db.Exec(`UPDATE items SET status=?, current_location='Fixed', body_md=? WHERE atm_id=? AND current_location='Issues'`,
		mismatchedStatus, newBody, id)
	if err != nil {
		t.Fatalf("inject: %v", err)
	}
	if n, _ := res.RowsAffected(); n != 1 {
		t.Fatalf("inject affected %d rows, want 1", n)
	}
	if _, err := db.Exec(`DELETE FROM doc_segments WHERE document='Issues' AND kind='item' AND atm_id=?`, id); err != nil {
		t.Fatalf("remove Issues segment: %v", err)
	}
	var maxSeq int
	_ = db.QueryRow(`SELECT COALESCE(MAX(seq),-1) FROM doc_segments WHERE document='Fixed'`).Scan(&maxSeq)
	if _, err := db.Exec(`INSERT INTO doc_segments (document, seq, kind, atm_id, raw) VALUES ('Fixed', ?, 'item', ?, NULL)`, maxSeq+1, id); err != nil {
		t.Fatalf("append Fixed segment: %v", err)
	}
	// Isolation guard (§11.4.107(10)): the fixture must trip ONLY the
	// Type↔Status invariant under test, not any pre-existing check — otherwise
	// this proves nothing about the NEW guard specifically.
	items, lerr := loadItems(db)
	if lerr != nil {
		t.Fatalf("loadItems: %v", lerr)
	}
	if d := fixedLocationNonTerminalStatus(items); len(d) != 0 {
		t.Fatalf("fixture not isolated: location↔status guard fired (%v)", d)
	}
	if d := statusColumnBodyDesyncs(items); len(d) != 0 {
		t.Fatalf("fixture not isolated: column↔body guard fired (%v)", d)
	}
}

// ---- close ----

// TestCloseCmd_RefusesTypeStatusMismatch is the PREVENTIVE guard and the exact
// runtime reproduction of BOB-077/100/179/226 (the "Task closed fixed" case is
// literally the mistake made four times this session). The decisive assertion
// is on the DB ROW, not the exit code alone: a refusal that still wrote the
// row would be a bluff.
func TestCloseCmd_RefusesTypeStatusMismatch(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	for _, tc := range []struct{ name, typ, closeStatus string }{
		{"Bug_closed_implemented", "Bug", "implemented"},
		{"Bug_closed_completed", "Bug", "completed"},
		{"Feature_closed_fixed", "Feature", "fixed"},
		{"Feature_closed_completed", "Feature", "completed"},
		{"Task_closed_fixed", "Task", "fixed"}, // the exact BOB-077/100/179/226 shape.
		{"Task_closed_implemented", "Task", "implemented"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dbPath := newTestDB(t)
			const id = "WIT-950"
			if code := addCmd([]string{
				"--db", dbPath, "--id", id,
				"--title", "a type-status mismatch close probe",
				"--description", "a sufficiently long description that clears the §11.4.91 floor for the close guard test",
				tc.typ, "High",
			}); code != exitOK {
				t.Fatalf("seed add: exit %d", code)
			}
			evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/"+id+"/"+tc.name+".md")
			code := closeCmd([]string{"--db", dbPath, "--status", tc.closeStatus, "--evidence", evidence, id})

			if assertGuardAbsent {
				if code != exitOK {
					t.Fatalf("RED_MODE=1: close refused (exit %d) — guard already present, guard-absent baseline no longer reproducible", code)
				}
				// Matches the REAL historical incident this item documents: close
				// accepted the mismatch AND validate ALSO reported OK on the
				// resulting DB (the "validate: OK ran repeatedly against a DB
				// simultaneously holding 30+ live violations" finding). Whether
				// validate itself has been taught to catch this is
				// TestValidate_CatchesTypeStatusMismatch's own, independent RED
				// baseline — asserted there, not duplicated here.
				if vc := validateCmd([]string{"--db", dbPath}); vc != exitOK {
					t.Fatalf("RED_MODE=1: validate unexpectedly refused (exit %d) on the pre-BOB-240 baseline", vc)
				}
				return
			}

			if code == exitOK {
				t.Fatalf("close ACCEPTED Type=%s closed with --status %s — §11.4.33 Type↔Status guard is a bluff", tc.typ, tc.closeStatus)
			}
			db, err := openDB(dbPath)
			if err != nil {
				t.Fatalf("openDB: %v", err)
			}
			defer db.Close()
			if it, _ := loadItem(db, id, "Fixed"); it != nil {
				t.Fatal("refused close still wrote the item into Fixed")
			}
			it, _ := loadItem(db, id, "Issues")
			if it == nil {
				t.Fatal("refused close removed the item from Issues without writing it anywhere — data loss")
			}
			if it.Status != "Queued" {
				t.Errorf("refused close mutated the item's status anyway: %q", it.Status)
			}
		})
	}
}

// TestCloseCmd_RefusalNamesCorrectWord is criterion 1's "printing the correct
// word to use" made runtime-visible, not just a source comment.
func TestCloseCmd_RefusalNamesCorrectWord(t *testing.T) {
	if os.Getenv("RED_MODE") == "1" {
		t.Skip("RED_MODE=1: no refusal is emitted in the guard-absent baseline") // SKIP-OK: RED polarity
	}
	dbPath := newTestDB(t)
	const id = "WIT-951"
	if code := addCmd([]string{
		"--db", dbPath, "--id", id,
		"--title", "a close refusal message probe",
		"--description", "a sufficiently long description that clears the §11.4.91 floor for the refusal message test",
		"Task", "Medium",
	}); code != exitOK {
		t.Fatalf("seed add: exit %d", code)
	}
	evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/"+id+"/run.md")
	rc, stderr := captureStderrRun(t, func() int {
		return closeCmd([]string{"--db", dbPath, "--status", "fixed", "--evidence", evidence, id})
	})
	if rc == exitOK {
		t.Fatal("close returned OK — no refusal was emitted to inspect")
	}
	for _, want := range []string{id, "Task", "completed", "§11.4.33"} {
		if !strings.Contains(stderr, want) {
			t.Errorf("refusal message does not mention %q — not actionable (§11.4.201(5)).\ngot: %s", want, stderr)
		}
	}
}

// TestCloseCmd_AllowsMatchingTypeStatus is the §11.4.201(1) false-positive
// guard: a Type-matching closure must still succeed for every member of the
// closed Type↔Status mapping.
func TestCloseCmd_AllowsMatchingTypeStatus(t *testing.T) {
	for _, tc := range []struct{ typ, status, wantTerminal string }{
		{"Bug", "fixed", "Fixed (→ Fixed.md)"},
		{"Feature", "implemented", "Implemented (→ Fixed.md)"},
		{"Task", "completed", "Completed (→ Fixed.md)"},
	} {
		t.Run(tc.typ, func(t *testing.T) {
			dbPath := newTestDB(t)
			const id = "WIT-970"
			if code := addCmd([]string{
				"--db", dbPath, "--id", id,
				"--title", "a matching type-status close probe for " + tc.typ,
				"--description", "a sufficiently long description that clears the §11.4.91 floor for the matching close test",
				tc.typ, "Low",
			}); code != exitOK {
				t.Fatalf("seed add: exit %d", code)
			}
			evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/"+id+"/"+tc.typ+".md")
			if code := closeCmd([]string{"--db", dbPath, "--status", tc.status, "--evidence", evidence, id}); code != exitOK {
				t.Fatalf("close REFUSED a Type-matching closure (%s/%s) — §11.4.201(1) false-positive refusal (exit %d)", tc.typ, tc.status, code)
			}
			db, err := openDB(dbPath)
			if err != nil {
				t.Fatalf("openDB: %v", err)
			}
			defer db.Close()
			fx, _ := loadItem(db, id, "Fixed")
			if fx == nil || fx.Status != tc.wantTerminal {
				t.Fatalf("closed status = %+v, want %q", fx, tc.wantTerminal)
			}
			if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
				t.Fatalf("validate FAILed (%d) on a legitimate matching closure", code)
			}
		})
	}
}

// TestCloseCmd_AllowsObsoleteForAnyType is criterion 5: Obsolete is valid
// closure vocabulary for ANY Type and must never false-positive.
func TestCloseCmd_AllowsObsoleteForAnyType(t *testing.T) {
	for _, typ := range []string{"Bug", "Feature", "Task"} {
		t.Run(typ, func(t *testing.T) {
			dbPath := newTestDB(t)
			const id = "WIT-960"
			if code := addCmd([]string{
				"--db", dbPath, "--id", id,
				"--title", "an obsolete-exemption probe for " + typ,
				"--description", "a sufficiently long description that clears the §11.4.91 floor for the obsolete exemption test",
				typ, "Low",
			}); code != exitOK {
				t.Fatalf("seed add: exit %d", code)
			}
			evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/"+id+"/"+typ+".md")
			if code := closeCmd([]string{"--db", dbPath, "--status", "obsolete", "--evidence", evidence, id}); code != exitOK {
				t.Fatalf("close REFUSED --status obsolete for Type=%s (exit %d) — Obsolete must be valid for ANY Type (criterion 5)", typ, code)
			}
			db, err := openDB(dbPath)
			if err != nil {
				t.Fatalf("openDB: %v", err)
			}
			defer db.Close()
			fx, _ := loadItem(db, id, "Fixed")
			if fx == nil || fx.Status != "Obsolete (→ Fixed.md)" {
				t.Fatalf("closed status = %+v, want Obsolete (→ Fixed.md)", fx)
			}
			if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
				t.Fatalf("validate FAILed (%d) on a legitimate Obsolete closure of Type=%s", code, typ)
			}
		})
	}
}

// ---- update ----

// TestUpdateCmd_RefusesTypeStatusMismatch is the update-command analogue of
// TestCloseCmd_RefusesTypeStatusMismatch — the same BOB-077-class mistake,
// made via `update --location Fixed --status <word>` instead of `close`.
func TestUpdateCmd_RefusesTypeStatusMismatch(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	dbPath := newTestDB(t)
	const id = "WIT-980"
	seedFixedItemOfType(t, dbPath, id, "Task", "completed") // Type=Task, correctly closed Completed.

	// "fixed" is the exact BOB-077/100/179/226 mistake, attempted via `update`.
	code := updateCmd([]string{"--db", dbPath, "--id", id, "--location", "Fixed", "--status", "fixed"})

	if assertGuardAbsent {
		if code != exitOK {
			t.Fatalf("RED_MODE=1: update refused (exit %d) — guard already present, guard-absent baseline no longer reproducible", code)
		}
		db, err := openDB(dbPath)
		if err != nil {
			t.Fatalf("openDB: %v", err)
		}
		fx, _ := loadItem(db, id, "Fixed")
		db.Close()
		if fx == nil || fx.Status != "Fixed (→ Fixed.md)" {
			t.Fatalf("RED_MODE=1: mismatched status did not land (%+v) — reproduction incomplete", fx)
		}
		// See the identical comment on TestCloseCmd_RefusesTypeStatusMismatch:
		// matches the real historical incident — update accepted the mismatch
		// AND validate ALSO reported OK on the resulting DB.
		if vc := validateCmd([]string{"--db", dbPath}); vc != exitOK {
			t.Fatalf("RED_MODE=1: validate unexpectedly refused (exit %d) on the pre-BOB-240 baseline", vc)
		}
		return
	}

	if code == exitOK {
		t.Fatal("update ACCEPTED a Type=Task item updated to --status fixed at Fixed location — §11.4.33 Type↔Status guard is a bluff")
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, _ := loadItem(db, id, "Fixed")
	if it == nil || it.Status != "Completed (→ Fixed.md)" {
		t.Fatalf("refused update mutated the row anyway: %+v", it)
	}
}

// TestUpdateCmd_RefusalNamesCorrectWord mirrors TestCloseCmd_RefusalNamesCorrectWord
// for the update seam.
func TestUpdateCmd_RefusalNamesCorrectWord(t *testing.T) {
	if os.Getenv("RED_MODE") == "1" {
		t.Skip("RED_MODE=1: no refusal is emitted in the guard-absent baseline") // SKIP-OK: RED polarity
	}
	dbPath := newTestDB(t)
	const id = "WIT-982"
	seedFixedItemOfType(t, dbPath, id, "Feature", "implemented")

	rc, stderr := captureStderrRun(t, func() int {
		return updateCmd([]string{"--db", dbPath, "--id", id, "--location", "Fixed", "--status", "completed"})
	})
	if rc == exitOK {
		t.Fatal("update returned OK — no refusal was emitted to inspect")
	}
	for _, want := range []string{id, "Feature", "implemented", "§11.4.33"} {
		if !strings.Contains(stderr, want) {
			t.Errorf("refusal message does not mention %q — not actionable (§11.4.201(5)).\ngot: %s", want, stderr)
		}
	}
}

// TestUpdateCmd_AllowsMatchingTypeStatus is the §11.4.201(1) false-positive
// guard for update: re-affirming (or transitioning between) Type-matching
// terminal statuses at Fixed must still succeed.
func TestUpdateCmd_AllowsMatchingTypeStatus(t *testing.T) {
	dbPath := newTestDB(t)
	const id = "WIT-983"
	seedFixedItemOfType(t, dbPath, id, "Bug", "fixed")

	// Bug -> Obsolete is a legitimate Type-matching (exempt) transition that
	// also EXERCISES the update: the status genuinely changes.
	if code := updateCmd([]string{"--db", dbPath, "--id", id, "--location", "Fixed", "--status", "obsolete"}); code != exitOK {
		t.Fatalf("update REFUSED a legitimate Bug→Obsolete transition at Fixed (exit %d) — §11.4.201(1) false-positive refusal", code)
	}
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	it, _ := loadItem(db, id, "Fixed")
	if it == nil || it.Status != "Obsolete (→ Fixed.md)" {
		t.Fatalf("status after update = %+v, want Obsolete (→ Fixed.md)", it)
	}
	if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
		t.Fatalf("validate FAILed (%d) after a legitimate matching update", code)
	}
}

// TestUpdateCmd_LocationGuardFiresBeforeTypeStatusGuard is the BOB-175-
// interaction proof the task requested: BOB-166's location↔status guard and
// BOB-240's Type↔Status guard partition the (location, terminality) state
// space into disjoint cells — {Issues,terminal} is refused by BOB-166 BEFORE
// BOB-240's check is ever reached — so a single call can never trigger both,
// and the message an operator sees is unambiguous.
func TestUpdateCmd_LocationGuardFiresBeforeTypeStatusGuard(t *testing.T) {
	if os.Getenv("RED_MODE") == "1" {
		t.Skip("RED_MODE=1: BOB-240 guard absent in this baseline") // SKIP-OK: RED polarity
	}
	dbPath := newTestDB(t)
	const id = "WIT-981"
	seedIssuesItem(t, dbPath, id) // Bug, Issues, Queued (update_location_status_invariant_test.go).

	rc, stderr := captureStderrRun(t, func() int {
		// "fixed" is TYPE-CORRECT for this Bug item (no Type↔Status violation)
		// yet TERMINAL while the item is still located in Issues — so this
		// call violates ONLY the location guard, isolating which guard fires.
		return updateCmd([]string{"--db", dbPath, "--id", id, "--status", "fixed"})
	})
	if rc == exitOK {
		t.Fatal("update accepted a terminal status on an Issues-located item")
	}
	if !strings.Contains(stderr, "located in Issues") {
		t.Errorf("expected the BOB-166 location↔status refusal (proving it fires first), got: %s", stderr)
	}
	if strings.Contains(stderr, "§11.4.33") {
		t.Errorf("BOB-240's Type↔Status refusal fired on a call that only violates the location guard — the two guards are masking/competing instead of partitioning cleanly: %s", stderr)
	}
}

// ---- validate ----

// TestValidate_CatchesTypeStatusMismatch is the DETECTIVE golden-BAD fixture
// (criterion 3): validate must FAIL on a Fixed-location item whose Type and
// terminal status disagree, and the finding must name the item + the correct
// word — even when the mismatch was planted by raw SQL, never through the
// (now-guarded) CLI.
func TestValidate_CatchesTypeStatusMismatch(t *testing.T) {
	assertGuardAbsent := os.Getenv("RED_MODE") == "1"

	dbPath := newTestDB(t)
	const id = "WIT-940"
	injectTypeStatusMismatchAtFixed(t, dbPath, id, "Task", "Fixed (→ Fixed.md)")

	rc, stderr := captureStderrRun(t, func() int {
		return validateCmd([]string{"--db", dbPath})
	})

	if assertGuardAbsent {
		if rc != exitOK {
			t.Fatalf("RED_MODE=1: validate refused (exit %d) — guard already present, guard-absent baseline no longer reproducible", rc)
		}
		return
	}

	if rc == exitOK {
		t.Fatal("validate returned OK on a Type=Task item closed with 'Fixed (→ Fixed.md)' — §11.4.33 Type↔Status mismatch not caught")
	}
	for _, want := range []string{id, "Task", "completed", "§11.4.33"} {
		if !strings.Contains(stderr, want) {
			t.Errorf("validate finding does not mention %q — not actionable (§11.4.201(5)).\ngot: %s", want, stderr)
		}
	}

	// Control needle (§11.4.201(6)(7)(b)): the gate is not simply inert.
	// Confirm the SAME function, called directly on the loaded items, sees
	// exactly one finding — proving the wiring above (validateCmd -> the new
	// invariant) is real, not a coincidental non-zero exit from something
	// else.
	db, err := openDB(dbPath)
	if err != nil {
		t.Fatalf("openDB: %v", err)
	}
	defer db.Close()
	items, lerr := loadItems(db)
	if lerr != nil {
		t.Fatalf("loadItems: %v", lerr)
	}
	if f := typeStatusMismatches(items); len(f) != 1 {
		t.Fatalf("typeStatusMismatches returned %d findings on a single seeded violation, want 1: %v", len(f), f)
	}
}

// TestValidate_DoesNotFireOnMatchingOrObsoleteClosures is the §11.4.201(1)
// false-positive sibling: every legitimate Type↔Status pairing (the three
// matching pairs plus Obsolete for any Type) must NOT trip the new invariant.
func TestValidate_DoesNotFireOnMatchingOrObsoleteClosures(t *testing.T) {
	for _, tc := range []struct{ name, typ, closeStatus string }{
		{"Bug_fixed", "Bug", "fixed"},
		{"Feature_implemented", "Feature", "implemented"},
		{"Task_completed", "Task", "completed"},
		{"Bug_obsolete", "Bug", "obsolete"},
		{"Feature_obsolete", "Feature", "obsolete"},
		{"Task_obsolete", "Task", "obsolete"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dbPath := newTestDB(t)
			const id = "WIT-941"
			if code := addCmd([]string{
				"--db", dbPath, "--id", id,
				"--title", "a legitimate-closure validate probe for " + tc.name,
				"--description", "a sufficiently long description that clears the §11.4.91 floor for the validate negative control",
				tc.typ, "Low",
			}); code != exitOK {
				t.Fatalf("seed add: exit %d", code)
			}
			evidence := materialiseEvidence(t, newEvidenceRoot(t), "docs/qa/"+id+"/"+tc.name+".md")
			if code := closeCmd([]string{"--db", dbPath, "--status", tc.closeStatus, "--evidence", evidence, id}); code != exitOK {
				t.Fatalf("seed close: exit %d", code)
			}
			if code := validateCmd([]string{"--db", dbPath}); code != exitOK {
				t.Fatalf("validate FAILed (%d) on a legitimate %s closure — §11.4.201(1) false-positive refusal", code, tc.name)
			}
			db, err := openDB(dbPath)
			if err != nil {
				t.Fatalf("openDB: %v", err)
			}
			items, lerr := loadItems(db)
			db.Close()
			if lerr != nil {
				t.Fatalf("loadItems: %v", lerr)
			}
			if f := typeStatusMismatches(items); len(f) != 0 {
				t.Fatalf("typeStatusMismatches fired on a legitimate %s closure: %v", tc.name, f)
			}
		})
	}
}
